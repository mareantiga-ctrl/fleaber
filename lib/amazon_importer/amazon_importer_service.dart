import 'package:flutter/foundation.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/fleaber_gallery_picker.dart';

import 'amazon_importer_models.dart';
import 'amazon_manifest_parser.dart';
import 'amazon_scan_models.dart';
import 'amazon_weight.dart';

/// Serviço cliente do Importador Amazon (admin-only via RLS + RPC).
class AmazonImporterService {
  AmazonImporterService._();
  static final instance = AmazonImporterService._();

  Future<bool> isAuthorized() async {
    if (currentUserUid.isEmpty) return false;
    try {
      final res = await SupaFlow.client.rpc('batata_is_amazon_importer_admin');
      return res == true;
    } catch (_) {
      // Fallback: mesmo critério do Admin Fleaber (profiles.user_type).
      try {
        final row = await SupaFlow.client
            .from('profiles')
            .select('user_type')
            .eq('id', currentUserUid)
            .maybeSingle();
        final t = (row?['user_type']?.toString() ?? '').trim().toLowerCase();
        return const {
          'admin',
          'admim',
          'administrador',
          'administracao',
        }.contains(t);
      } catch (_) {
        return false;
      }
    }
  }

  Future<List<Map<String, dynamic>>> listLots({int limit = 40}) async {
    final rows = await SupaFlow.client
        .from('amazon_import_lots')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> searchCatalog({
    String? query,
    String? status,
    int limit = 80,
  }) async {
    var q = SupaFlow.client.from('amazon_catalog_products').select();
    final raw = (query ?? '').trim();
    if (raw.isNotEmpty) {
      // Pesquisa por ASIN/EAN/título (postgrest or).
      q = q.or(
        'asin.ilike.%$raw%,ean.ilike.%$raw%,upc.ilike.%$raw%,title.ilike.%$raw%',
      );
    }
    final st = (status ?? '').trim();
    if (st.isNotEmpty) {
      q = q.eq('catalog_status', st);
    }
    final rows = await q.order('updated_at', ascending: false).limit(limit);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>?> findByBarcode(String code) async {
    final c = code.trim();
    if (c.isEmpty) return null;
    // LPN exacto
    final unit = await SupaFlow.client
        .from('amazon_catalog_units')
        .select('*, amazon_catalog_products(*)')
        .eq('lpn', c)
        .maybeSingle();
    if (unit != null) return Map<String, dynamic>.from(unit as Map);

    final byAsin = await SupaFlow.client
        .from('amazon_catalog_products')
        .select()
        .eq('asin', c)
        .maybeSingle();
    if (byAsin != null) return Map<String, dynamic>.from(byAsin as Map);

    final byEan = await SupaFlow.client
        .from('amazon_catalog_products')
        .select()
        .or('ean.eq.$c,upc.eq.$c')
        .maybeSingle();
    if (byEan != null) return Map<String, dynamic>.from(byEan as Map);
    return null;
  }

  Future<Map<String, dynamic>> createLot({
    required String filename,
    required String csvText,
  }) async {
    final digest = AmazonManifestParser.sha256HexPlaceholder(csvText);
    final preview = AmazonManifestParser.preview(csvText);
    // Dedupe por SHA: se já existe lote completed/importing com o mesmo CSV.
    final prior = await SupaFlow.client
        .from('amazon_import_lots')
        .select()
        .eq('source_sha256', digest)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (prior != null) {
      final st = prior['status']?.toString() ?? '';
      if (st == 'completed' || st == 'importing' || st == 'paused') {
        return Map<String, dynamic>.from({
          ...Map<String, dynamic>.from(prior as Map),
          '_reused': true,
        });
      }
    }
    final row = await SupaFlow.client
        .from('amazon_import_lots')
        .insert({
          'created_by': currentUserUid,
          'source_filename': filename,
          'source_sha256': digest,
          'source_csv_text': csvText,
          'status': 'draft',
          'row_count': preview.totalRows,
          'distinct_asin_count': preview.distinctAsin,
          'cursor_row': 0,
          'pause_requested': false,
          'meta': {
            'headers': preview.headers,
            'missing_required': preview.missingRequired,
            'preview_valid': preview.isValid,
            'zip': '166-C2',
          },
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row as Map);
  }

  Future<void> requestLotPause(String lotId) async {
    await SupaFlow.client.from('amazon_import_lots').update({
      'pause_requested': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', lotId);
  }

  Future<Map<String, dynamic>?> getLot(String lotId) async {
    final row = await SupaFlow.client
        .from('amazon_import_lots')
        .select()
        .eq('id', lotId)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  /// Importa em lotes; retoma se [resumeFromRow] > 0 ou a partir de cursor do lote.
  /// Respeita [pause_requested] sem reprocessar linhas já em amazon_import_row_progress.
  Future<Map<String, dynamic>> importManifestRows({
    required String lotId,
    required List<Map<String, String>> rows,
    int? resumeFromRow,
    void Function(int done, int total, String? message)? onProgress,
  }) async {
    final lot = await getLot(lotId);
    final start = resumeFromRow ??
        ((lot?['cursor_row'] as num?)?.toInt() ?? 0);
    await SupaFlow.client.from('amazon_import_lots').update({
      'status': 'importing',
      'pause_requested': false,
      'source_csv_text': lot?['source_csv_text'],
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', lotId);

    var imported = (lot?['imported_units'] as num?)?.toInt() ?? 0;
    var duplicates = (lot?['duplicate_units'] as num?)?.toInt() ?? 0;
    var errors = (lot?['error_count'] as num?)?.toInt() ?? 0;
    final total = rows.length;
    var paused = false;

    for (var i = start; i < rows.length; i++) {
      // Pausar a pedido (UI) — retoma no mesmo cursor.
      if (i % 5 == 0) {
        final live = await getLot(lotId);
        if (live?['pause_requested'] == true) {
          paused = true;
          await SupaFlow.client.from('amazon_import_lots').update({
            'status': 'paused',
            'cursor_row': i,
            'imported_units': imported,
            'duplicate_units': duplicates,
            'error_count': errors,
            'progress_pct':
                double.parse(((i / total) * 100).toStringAsFixed(2)),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', lotId);
          onProgress?.call(i, total, 'Pausado');
          break;
        }
      }

      final doneProgress = await SupaFlow.client
          .from('amazon_import_row_progress')
          .select('id, status')
          .eq('lot_id', lotId)
          .eq('row_number', i + 2)
          .maybeSingle();
      if (doneProgress != null) {
        onProgress?.call(i + 1, total, 'já processada');
        continue;
      }

      final r = rows[i];
      final lpn = (r['LPN'] ?? '').trim();
      final asin = (r['ASIN'] ?? '').trim();
      onProgress?.call(i + 1, total, lpn);
      if (lpn.isEmpty || asin.isEmpty) {
        errors++;
        await _logRowError(
          lotId: lotId,
          rowNumber: i + 2,
          lpn: lpn,
          asin: asin,
          code: 'missing_lpn_or_asin',
          message: 'LPN e ASIN são obrigatórios.',
          raw: r,
        );
        await _markRowProgress(
          lotId: lotId,
          rowNumber: i + 2,
          lpn: lpn,
          asin: asin,
          status: 'error',
          code: 'missing_lpn_or_asin',
          message: 'LPN e ASIN são obrigatórios.',
        );
        continue;
      }
      try {
        final existing = await SupaFlow.client
            .from('amazon_catalog_units')
            .select('id')
            .eq('lpn', lpn)
            .maybeSingle();
        if (existing != null) {
          duplicates++;
          await _markRowProgress(
            lotId: lotId,
            rowNumber: i + 2,
            lpn: lpn,
            asin: asin,
            status: 'duplicate',
          );
          continue;
        }

        final productId = await _upsertProductFromRow(r);
        final cost = parseManifestMoney(r['COST']);
        final retail = parseManifestMoney(r['UNIT RETAIL']) ??
            parseManifestMoney(r['TOTAL RETAIL']);
        final qty = int.tryParse((r['QTY'] ?? '1').trim()) ?? 1;

        await SupaFlow.client.from('amazon_catalog_units').insert({
          'lot_id': lotId,
          'product_id': productId,
          'lpn': lpn,
          'asin': asin,
          // CONDITION do manifesto fica em condition_code (nota interna).
          // Estado de venda Fleaber: sempre Novo (decisão comercial).
          'condition_code': r['CONDITION'],
          'condition_label': 'Novo',
          'qty': qty < 1 ? 1 : qty,
          'manifesto_cost_eur': cost,
          'manifesto_retail_eur': retail,
          'manifesto_currency': (r['CURRENCY CODE'] ?? 'EUR').trim(),
          'sku_fc': r['FCSku'],
          'fnsku': r['FNSku'],
          'internal_ref': r['Listing_id'],
          'package_weight': parseManifestMoney(r['ItemPkgWeight']),
          'package_weight_uom': r['ItemPkgWeightUOM'],
          'raw_row': r,
        });
        imported++;
        await _markRowProgress(
          lotId: lotId,
          rowNumber: i + 2,
          lpn: lpn,
          asin: asin,
          status: 'imported',
        );
        await refreshMissingReasons(productId);
      } catch (e) {
        errors++;
        await _logRowError(
          lotId: lotId,
          rowNumber: i + 2,
          lpn: lpn,
          asin: asin,
          code: 'insert_failed',
          message: e.toString(),
          raw: r,
        );
        await _markRowProgress(
          lotId: lotId,
          rowNumber: i + 2,
          lpn: lpn,
          asin: asin,
          status: 'error',
          code: 'insert_failed',
          message: e.toString(),
        );
      }

      if (i % 10 == 0 || i == rows.length - 1) {
        final pct = total == 0 ? 100.0 : ((i + 1) / total) * 100.0;
        await SupaFlow.client.from('amazon_import_lots').update({
          'imported_units': imported,
          'duplicate_units': duplicates,
          'error_count': errors,
          'cursor_row': i + 1,
          'progress_pct': double.parse(pct.toStringAsFixed(2)),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', lotId);
      }
    }

    if (paused) {
      return {
        'imported_units': imported,
        'duplicate_units': duplicates,
        'error_count': errors,
        'status': 'paused',
        'paused': true,
      };
    }

    final done = {
      'imported_units': imported,
      'duplicate_units': duplicates,
      'error_count': errors,
      'progress_pct': 100.0,
      'cursor_row': total,
      'pause_requested': false,
      'status': errors > 0 && imported == 0 ? 'failed' : 'completed',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await SupaFlow.client.from('amazon_import_lots').update(done).eq('id', lotId);
    return done;
  }

  Future<void> _markRowProgress({
    required String lotId,
    required int rowNumber,
    String? lpn,
    String? asin,
    required String status,
    String? code,
    String? message,
  }) async {
    await SupaFlow.client.from('amazon_import_row_progress').upsert({
      'lot_id': lotId,
      'row_number': rowNumber,
      'lpn': lpn,
      'asin': asin,
      'status': status,
      'error_code': code,
      'error_message': message,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'lot_id,row_number');
  }

  Future<String> _upsertProductFromRow(Map<String, String> r) async {
    final asin = (r['ASIN'] ?? '').trim();
    final existing = await SupaFlow.client
        .from('amazon_catalog_products')
        .select('id, manifest_weight_kg')
        .eq('asin', asin)
        .maybeSingle();
    final rawW = parseManifestMoney(r['ItemPkgWeight']);
    final uom = r['ItemPkgWeightUOM'];
    final manifestKg = AmazonWeight.toKg(rawW, uom);
    final shippingKg = manifestKg == null
        ? null
        : AmazonWeight.shippingKgFromManifest(manifestKg);
    final grams = manifestKg == null ? null : manifestKg * 1000.0;
    final ean = (r['EAN'] ?? '').trim();
    final upc = (r['UPC'] ?? '').trim();
    if (existing != null) {
      final id = existing['id'].toString();
      // Idempotente: só preenche peso se ainda vazio (não re-aplica 10% em cima).
      final hasManifest = existing['manifest_weight_kg'] != null;
      final patch = <String, dynamic>{
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (ean.isNotEmpty) patch['ean'] = ean;
      if (upc.isNotEmpty) patch['upc'] = upc;
      if (!hasManifest && manifestKg != null) {
        patch['manifest_weight_kg'] = manifestKg;
        patch['shipping_weight_kg'] = shippingKg;
        patch['weight_grams'] = grams;
        patch['weight_packaging_pct'] = AmazonWeight.packagingPct;
        patch['weight_source'] = 'manifesto';
      }
      if (patch.length > 1) {
        await SupaFlow.client
            .from('amazon_catalog_products')
            .update(patch)
            .eq('id', id);
      }
      return id;
    }
    final inserted = await SupaFlow.client
        .from('amazon_catalog_products')
        .insert({
          'asin': asin,
          'ean': ean.isEmpty ? null : ean,
          'upc': upc.isEmpty ? null : upc,
          'title': (r['Item Desc'] ?? '').trim(),
          'category': r['CATEGORY'],
          'subcategory': r['SUBCATEGORY'],
          'weight_grams': grams,
          'manifest_weight_kg': manifestKg,
          'shipping_weight_kg': shippingKg,
          'weight_packaging_pct': AmazonWeight.packagingPct,
          'weight_source': manifestKg == null ? null : 'manifesto',
          'catalog_status': 'imported',
          'discount_pct': 50.0,
        })
        .select('id')
        .single();
    return inserted['id'].toString();
  }

  /// Pesquisa admin por EAN, LPN ou ASIN (vários hits se EAN partilhado).
  Future<List<AmazonScanHit>> lookupByCode(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return const [];
    final upper = code.toUpperCase();

    // LPN exacto
    final byLpn = await SupaFlow.client
        .from('amazon_catalog_units')
        .select(
          'id, lpn, asin, qty, condition_label, storage_location, product_id, '
          'amazon_catalog_products(id, asin, ean, title, primary_image_url, '
          'approved_sale_eur, suggested_sale_eur, manifest_weight_kg, shipping_weight_kg)',
        )
        .eq('lpn', code)
        .limit(20);
    if ((byLpn as List).isNotEmpty) {
      return _hitsFromUnitRows(byLpn);
    }

    // ASIN — expandir unidades (igual ao EAN) para escolha quando há várias
    final byAsin = await SupaFlow.client
        .from('amazon_catalog_products')
        .select(
          'id, asin, ean, title, primary_image_url, approved_sale_eur, '
          'suggested_sale_eur, manifest_weight_kg, shipping_weight_kg',
        )
        .eq('asin', upper)
        .limit(5);
    if ((byAsin as List).isNotEmpty) {
      final hits = <AmazonScanHit>[];
      for (final row in byAsin) {
        final p = Map<String, dynamic>.from(row as Map);
        final units = await SupaFlow.client
            .from('amazon_catalog_units')
            .select('id, lpn, qty, condition_label, storage_location')
            .eq('product_id', p['id'])
            .limit(20);
        if ((units as List).isEmpty) {
          hits.add(await _hitFromProduct(p));
        } else {
          for (final u in units) {
            hits.add(await _hitFromProduct(
              p,
              unitId: u['id']?.toString(),
              lpn: u['lpn']?.toString(),
              qty: (u['qty'] as num?)?.toInt(),
              condition: u['condition_label']?.toString(),
              storage: u['storage_location']?.toString(),
            ));
          }
        }
      }
      return hits;
    }

    // EAN — pode haver várias unidades
    final byEan = await SupaFlow.client
        .from('amazon_catalog_products')
        .select(
          'id, asin, ean, title, primary_image_url, approved_sale_eur, '
          'suggested_sale_eur, manifest_weight_kg, shipping_weight_kg',
        )
        .eq('ean', code)
        .limit(40);
    if ((byEan as List).isEmpty) return const [];
    final hits = <AmazonScanHit>[];
    for (final row in byEan) {
      final p = Map<String, dynamic>.from(row as Map);
      final units = await SupaFlow.client
          .from('amazon_catalog_units')
          .select('id, lpn, qty, condition_label, storage_location')
          .eq('product_id', p['id'])
          .limit(20);
      if ((units as List).isEmpty) {
        hits.add(await _hitFromProduct(p));
      } else {
        for (final u in units) {
          hits.add(await _hitFromProduct(
            p,
            unitId: u['id']?.toString(),
            lpn: u['lpn']?.toString(),
            qty: (u['qty'] as num?)?.toInt(),
            condition: u['condition_label']?.toString(),
            storage: u['storage_location']?.toString(),
          ));
        }
      }
    }
    return hits;
  }

  Future<List<AmazonScanHit>> _hitsFromUnitRows(List rows) async {
    final out = <AmazonScanHit>[];
    for (final raw in rows) {
      final u = Map<String, dynamic>.from(raw as Map);
      final pRaw = u['amazon_catalog_products'];
      final p = pRaw is Map
          ? Map<String, dynamic>.from(pRaw)
          : <String, dynamic>{};
      out.add(await _hitFromProduct(
        p,
        unitId: u['id']?.toString(),
        lpn: u['lpn']?.toString(),
        qty: (u['qty'] as num?)?.toInt(),
        condition: u['condition_label']?.toString(),
        storage: u['storage_location']?.toString(),
      ));
    }
    return out;
  }

  Future<AmazonScanHit> _hitFromProduct(
    Map<String, dynamic> p, {
    String? unitId,
    String? lpn,
    int? qty,
    String? condition,
    String? storage,
  }) async {
    final asin = (p['asin'] ?? '').toString();
    String? fleaberId;
    if (asin.isNotEmpty) {
      final pr = await SupaFlow.client
          .from('products')
          .select('id')
          .eq('ref_code', 'AMZ-$asin')
          .maybeSingle();
      fleaberId = pr?['id']?.toString();
    }
    final sale = (p['approved_sale_eur'] as num?)?.toDouble() ??
        (p['suggested_sale_eur'] as num?)?.toDouble();
    return AmazonScanHit(
      catalogProductId: (p['id'] ?? '').toString(),
      asin: asin,
      unitId: unitId,
      ean: p['ean']?.toString(),
      lpn: lpn,
      title: p['title']?.toString(),
      imageUrl: p['primary_image_url']?.toString(),
      saleEur: sale,
      manifestKg: (p['manifest_weight_kg'] as num?)?.toDouble(),
      shippingKg: (p['shipping_weight_kg'] as num?)?.toDouble(),
      qty: qty,
      condition: condition,
      storageLocation: storage,
      fleaberProductId: fleaberId,
    );
  }

  static const _adminLpnLotNote = 'ZIP163-admin-lpn-ensure';

  Future<String> _ensureAdminLpnLotId() async {
    final existing = await SupaFlow.client
        .from('amazon_import_lots')
        .select('id')
        .eq('notes', _adminLpnLotNote)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (existing != null) {
      return existing['id'].toString();
    }
    final uid = SupaFlow.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sessão necessária para associar LPN');
    }
    final inserted = await SupaFlow.client
        .from('amazon_import_lots')
        .insert({
          'source_filename': 'ZIP163_LPN_MANUAL.csv',
          'notes': _adminLpnLotNote,
          'status': 'completed',
          'created_by': uid,
        })
        .select('id')
        .single();
    return inserted['id'].toString();
  }

  /// Associa LPN a um produto do catálogo — falha se LPN já existir.
  /// Não escolhe automaticamente entre unidades ambíguas: cria unidade nova
  /// só quando o produto ainda não tem esse LPN.
  Future<void> associateLpn({
    required String lpn,
    required String catalogProductId,
    required String asin,
    String? storageLocation,
    String? conditionLabel,
    int qty = 1,
  }) async {
    final code = lpn.trim();
    if (code.isEmpty) {
      throw StateError('LPN vazio');
    }
    if (catalogProductId.trim().isEmpty || asin.trim().isEmpty) {
      throw StateError('Produto/ASIN em falta');
    }
    final clash = await SupaFlow.client
        .from('amazon_catalog_units')
        .select('id, product_id, asin')
        .eq('lpn', code)
        .maybeSingle();
    if (clash != null) {
      final sameProduct = clash['product_id']?.toString() == catalogProductId;
      if (sameProduct) {
        return; // já associado correctamente
      }
      throw StateError('LPN já associado a outra unidade (${clash['asin']})');
    }
    final lotId = await _ensureAdminLpnLotId();
    await SupaFlow.client.from('amazon_catalog_units').insert({
      'lot_id': lotId,
      'product_id': catalogProductId,
      'lpn': code,
      'asin': asin.trim(),
      'condition_label': conditionLabel,
      'qty': qty < 1 ? 1 : qty,
      'storage_location': storageLocation,
      'raw_row': {
        'source': 'manual_associate',
        'lpn': code,
        'asin': asin.trim(),
      },
    });
  }

  /// Corrige LPN de uma unidade existente (admin). Impede duplicados.
  Future<void> reassignUnitLpn({
    required String unitId,
    required String newLpn,
  }) async {
    final code = newLpn.trim();
    if (unitId.isEmpty || code.isEmpty) {
      throw StateError('Unidade/LPN em falta');
    }
    final clash = await SupaFlow.client
        .from('amazon_catalog_units')
        .select('id')
        .eq('lpn', code)
        .neq('id', unitId)
        .maybeSingle();
    if (clash != null) {
      throw StateError('LPN já associado a outra unidade');
    }
    await SupaFlow.client.from('amazon_catalog_units').update({
      'lpn': code,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', unitId);
  }

  /// Sincroniza `products.shipping_weight_kg` a partir do catálogo (AMZ-ASIN).
  Future<void> syncFleaberShippingWeightFromCatalog(String asin) async {
    final cat = await SupaFlow.client
        .from('amazon_catalog_products')
        .select('shipping_weight_kg, manifest_weight_kg')
        .eq('asin', asin)
        .maybeSingle();
    final ship = (cat?['shipping_weight_kg'] as num?)?.toDouble();
    if (ship == null || ship <= 0) return;
    await SupaFlow.client
        .from('products')
        .update({'shipping_weight_kg': ship}).eq('ref_code', 'AMZ-$asin');
  }

  Future<void> _logRowError({
    required String lotId,
    required int rowNumber,
    String? lpn,
    String? asin,
    required String code,
    required String message,
    required Map<String, String> raw,
  }) async {
    try {
      await SupaFlow.client.from('amazon_import_row_errors').insert({
        'lot_id': lotId,
        'row_number': rowNumber,
        'lpn': lpn,
        'asin': asin,
        'error_code': code,
        'error_message': message,
        'raw_row': raw,
      });
    } catch (e) {
      debugPrint('amazon_import_row_errors fail: $e');
    }
  }

  Future<void> updateProductSale({
    required String productId,
    double? discountPct,
    double? approvedSaleEur,
    double? realAcquisitionCostEur,
    String? catalogStatus,
    String? title,
    String? description,
    String? prepNotes,
    double? shippingWeightKgManual,
  }) async {
    final data = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      if (discountPct != null) 'discount_pct': discountPct,
      if (approvedSaleEur != null) 'approved_sale_eur': approvedSaleEur,
      if (realAcquisitionCostEur != null)
        'real_acquisition_cost_eur': realAcquisitionCostEur,
      if (catalogStatus != null) 'catalog_status': catalogStatus,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (prepNotes != null) 'prep_notes': prepNotes,
    };
    if (shippingWeightKgManual != null && shippingWeightKgManual > 0) {
      data['shipping_weight_kg'] = shippingWeightKgManual;
      data['weight_source'] = 'manual';
    }
    await SupaFlow.client
        .from('amazon_catalog_products')
        .update(data)
        .eq('id', productId);

    if (shippingWeightKgManual != null && shippingWeightKgManual > 0) {
      final row = await SupaFlow.client
          .from('amazon_catalog_products')
          .select('asin')
          .eq('id', productId)
          .maybeSingle();
      final asin = row?['asin']?.toString();
      if (asin != null && asin.isNotEmpty) {
        await SupaFlow.client.from('products').update({
          'shipping_weight_kg': shippingWeightKgManual,
        }).eq('ref_code', 'AMZ-$asin');
      }
    }
  }

  Future<List<AmazonOfferView>> offersForProduct(String productId) async {
    final rows = await SupaFlow.client
        .from('amazon_market_offers')
        .select()
        .eq('product_id', productId)
        .order('fetched_at', ascending: false)
        .limit(40);
    return (rows as List)
        .map((e) => AmazonOfferView.fromRow(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Pesquisa automática via Edge (admin). Para se receber captcha/block.
  Future<Map<String, dynamic>> researchAsin({
    required String productId,
    required String asin,
  }) async {
    final response = await SupaFlow.client.functions.invoke(
      'amazon-importer-research',
      body: {
        'product_id': productId,
        'asin': asin,
      },
    );
    final data = response.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {'ok': false, 'error': 'invalid_response', 'status': response.status};
  }

  Future<List<Map<String, dynamic>>> listProductsForResearch({
    String? lotId,
    bool onlyMissingPrice = true,
    int limit = 2000,
  }) async {
    var q = SupaFlow.client
        .from('amazon_catalog_products')
        .select('id, asin, title, catalog_status, suggested_sale_eur');
    if (onlyMissingPrice) {
      q = q.or(
        'suggested_sale_eur.is.null,catalog_status.eq.imported,catalog_status.eq.needs_review',
      );
    }
    final rows = await q.order('created_at').limit(limit);
    var list = (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (lotId != null && lotId.isNotEmpty) {
      final units = await SupaFlow.client
          .from('amazon_catalog_units')
          .select('product_id')
          .eq('lot_id', lotId);
      final ids = {
        for (final u in (units as List))
          (u as Map)['product_id']?.toString(),
      }..remove(null);
      list = list.where((p) => ids.contains(p['id']?.toString())).toList();
    }
    return list;
  }

  Future<Map<String, dynamic>> createResearchRun({
    String? lotId,
    required int asinCount,
    int throttleMs = 2500,
  }) async {
    final row = await SupaFlow.client
        .from('amazon_research_runs')
        .insert({
          'created_by': currentUserUid,
          'lot_id': lotId,
          'scope': lotId == null ? 'catalog_batch' : 'lot_batch',
          'status': 'running',
          'asin_count': asinCount,
          'throttle_ms': throttleMs,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row as Map);
  }

  Future<void> updateResearchRun(
    String runId,
    Map<String, dynamic> patch,
  ) async {
    await SupaFlow.client.from('amazon_research_runs').update({
      ...patch,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', runId);
  }

  Future<Map<String, dynamic>?> latestResearchRun() async {
    final row = await SupaFlow.client
        .from('amazon_research_runs')
        .select()
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  /// Corre lote com throttle; respeita [shouldPause] e para em CAPTCHA.
  Future<Map<String, dynamic>> runBatchResearch({
    required String runId,
    required List<Map<String, dynamic>> products,
    required int startIndex,
    required int throttleMs,
    required bool Function() shouldPause,
    void Function(int index, int total, String asin, String message)? onProgress,
  }) async {
    var ok = 0;
    var blocked = 0;
    var errors = 0;
    var i = startIndex;
    for (; i < products.length; i++) {
      if (shouldPause()) {
        await updateResearchRun(runId, {
          'status': 'paused',
          'cursor_index': i,
          'done_count': i,
          'ok_count': ok,
          'blocked_count': blocked,
          'error_count': errors,
          'pause_requested': false,
        });
        return {
          'status': 'paused',
          'cursor_index': i,
          'ok': ok,
          'blocked': blocked,
          'errors': errors,
        };
      }
      final p = products[i];
      final asin = (p['asin'] ?? '').toString();
      final pid = (p['id'] ?? '').toString();
      onProgress?.call(i + 1, products.length, asin, 'A pesquisar…');
      await updateResearchRun(runId, {
        'status': 'running',
        'cursor_index': i,
        'done_count': i,
        'last_asin': asin,
        'ok_count': ok,
        'blocked_count': blocked,
        'error_count': errors,
      });
      try {
        final res = await researchAsin(productId: pid, asin: asin);
        if (res['blocked'] == true) {
          blocked++;
          await updateResearchRun(runId, {
            'status': 'blocked',
            'cursor_index': i,
            'done_count': i + 1,
            'blocked_count': blocked,
            'ok_count': ok,
            'error_count': errors,
            'last_error': 'captcha_or_block',
            'last_asin': asin,
          });
          return {
            'status': 'blocked',
            'cursor_index': i,
            'ok': ok,
            'blocked': blocked,
            'errors': errors,
            'asin': asin,
          };
        }
        final n = (res['numeric_price_count'] as num?)?.toInt() ?? 0;
        if (n > 0) {
          ok++;
          await refreshSuggestedPrice(pid);
        } else {
          errors++;
        }
      } catch (e) {
        errors++;
        await updateResearchRun(runId, {
          'last_error': e.toString(),
          'error_count': errors,
        });
      }
      if (i + 1 < products.length) {
        await Future<void>.delayed(Duration(milliseconds: throttleMs));
      }
    }
    await updateResearchRun(runId, {
      'status': 'completed',
      'cursor_index': products.length,
      'done_count': products.length,
      'ok_count': ok,
      'blocked_count': blocked,
      'error_count': errors,
    });
    return {
      'status': 'completed',
      'cursor_index': products.length,
      'ok': ok,
      'blocked': blocked,
      'errors': errors,
    };
  }

  Future<void> refreshSuggestedPrice(String productId) async {
    final product = await SupaFlow.client
        .from('amazon_catalog_products')
        .select('discount_pct, catalog_status')
        .eq('id', productId)
        .maybeSingle();
    final discount =
        (product?['discount_pct'] as num?)?.toDouble() ?? 50.0;
    final offers = await offersForProduct(productId);
    final suspicious = hasSuspiciousAmazonPriceSpread(offers);
    final ref = suspicious ? null : pickAmazonReferenceOffer(offers);
    final suggested = (ref == null || suspicious)
        ? null
        : suggestedSaleFromOffers(offers: offers, discountPct: discount);
    await SupaFlow.client.from('amazon_catalog_products').update({
      'suggested_sale_eur': suggested,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      if (suggested == null || suspicious) 'catalog_status': 'needs_review',
      if (suggested != null &&
          !suspicious &&
          (product?['catalog_status']?.toString() == 'imported' ||
              product?['catalog_status']?.toString() == 'needs_review'))
        'catalog_status': 'researched',
    }).eq('id', productId);
  }

  /// Fotografias do produto (upload + refs Amazon com direitos pendentes).
  Future<List<Map<String, dynamic>>> photosForProduct(String productId) async {
    final rows = await SupaFlow.client
        .from('amazon_product_photos')
        .select()
        .eq('product_id', productId)
        .order('sort_order')
        .order('created_at');
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> deletePhoto(String photoId) async {
    await SupaFlow.client
        .from('amazon_product_photos')
        .delete()
        .eq('id', photoId);
  }

  Future<void> setPrimaryPhoto({
    required String productId,
    required String photoId,
  }) async {
    await SupaFlow.client
        .from('amazon_product_photos')
        .update({'is_primary': false}).eq('product_id', productId);
    await SupaFlow.client
        .from('amazon_product_photos')
        .update({'is_primary': true}).eq('id', photoId);
    final row = await SupaFlow.client
        .from('amazon_product_photos')
        .select('public_url')
        .eq('id', photoId)
        .maybeSingle();
    final url = row?['public_url']?.toString();
    if (url != null && url.isNotEmpty) {
      await SupaFlow.client.from('amazon_catalog_products').update({
        'primary_image_url': url,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', productId);
    }
  }

  Future<void> reorderPhotos(List<Map<String, dynamic>> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      final id = ordered[i]['id']?.toString();
      if (id == null || id.isEmpty) continue;
      await SupaFlow.client.from('amazon_product_photos').update({
        'sort_order': i,
        'is_primary': i == 0,
      }).eq('id', id);
    }
  }

  Future<void> updateUnitSaleCondition({
    required String unitId,
    required String conditionLabel,
  }) async {
    await SupaFlow.client.from('amazon_catalog_units').update({
      'condition_label': conditionLabel,
    }).eq('id', unitId);
  }

  Future<String?> uploadProductPhoto({
    required String productId,
    required Uint8List bytes,
    required String filename,
  }) async {
    final existing = await photosForProduct(productId);
    final path =
        'amazon_importer/$productId/${DateTime.now().millisecondsSinceEpoch}_$filename';
    await SupaFlow.client.storage.from('chat_media').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    final url = SupaFlow.client.storage.from('chat_media').getPublicUrl(path);
    await SupaFlow.client.from('amazon_product_photos').insert({
      'product_id': productId,
      'storage_path': path,
      'public_url': url,
      'sort_order': existing.length,
      'is_primary': existing.isEmpty,
      'source': 'upload',
    });
    if (existing.isEmpty) {
      await SupaFlow.client.from('amazon_catalog_products').update({
        'primary_image_url': url,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', productId);
    }
    return url;
  }

  Future<String?> pickAndUploadPhoto(String productId) async {
    final file = await FleaberGalleryPicker.pickSingleImage();
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return uploadProductPhoto(
      productId: productId,
      bytes: bytes,
      filename: file.name.isNotEmpty ? file.name : 'photo.jpg',
    );
  }

  /// Obtém fotografias via CDN Amazon (ASIN), sem scrape HTML / CAPTCHA.
  /// Guarda origem `amazon_cdn_pending_rights` — direitos de publicação pendentes.
  Future<int> fetchAmazonCdnPhotos(String productId, String asin) async {
    final response = await SupaFlow.client.functions.invoke(
      'amazon-importer-research',
      body: {
        'product_id': productId,
        'asin': asin,
        'photos_only': true,
      },
    );
    final data = response.data;
    if (data is Map && data['photo_count'] != null) {
      return (data['photo_count'] as num).toInt();
    }
    if (data is Map && data['ok'] == true) {
      final photos = await photosForProduct(productId);
      return photos
          .where((p) =>
              p['source']?.toString() == 'amazon_cdn_pending_rights' ||
              p['source']?.toString() == 'amazon_ref_pending_rights')
          .length;
    }
    throw StateError(
      data is Map
          ? (data['error']?.toString() ?? 'photos_failed')
          : 'photos_failed',
    );
  }

  // ---------------------------------------------------------------------------
  // ZIP 166 — revisão / aprovação / sync simulado
  // ---------------------------------------------------------------------------

  Future<List<String>> refreshMissingReasons(String productId) async {
    try {
      final res = await SupaFlow.client.rpc(
        'batata_amazon_refresh_missing_reasons',
        params: {'p_product_id': productId},
      );
      if (res is List) {
        return res.map((e) => e.toString()).toList();
      }
    } catch (e) {
      debugPrint('refreshMissingReasons rpc: $e');
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> listReadiness({
    String filter = 'all',
    int limit = 120,
  }) async {
    var q = SupaFlow.client.from('amazon_catalog_readiness').select();
    switch (filter) {
      case 'ready':
        q = q.eq('is_ready_to_approve', true).isFilter('approved_at', null);
        break;
      case 'approved':
        q = q.not('approved_at', 'is', null);
        break;
      case 'missing_price':
        q = q.contains('missing_reasons', ['missing_price']);
        break;
      case 'missing_photo':
        q = q.contains('missing_reasons', ['missing_photo']);
        break;
      case 'missing_weight':
        q = q.contains('missing_reasons', ['missing_weight']);
        break;
      case 'incomplete':
        q = q.neq('missing_reasons', '{}');
        break;
      default:
        break;
    }
    final rows = await q.order('asin').limit(limit);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Aprovação só via RPC PROD (`batata_amazon_approve_products`).
  /// Artigos incompletos são rejeitados com motivos — nunca publicados.
  Future<Map<String, dynamic>> bulkApprove({
    required List<String> productIds,
    String? note,
  }) async {
    if (productIds.isEmpty) {
      return {
        'approved': 0,
        'blocked': 0,
        'approved_ids': <String>[],
        'rejected': <Map<String, dynamic>>[],
        'published': false,
      };
    }
    final res = await SupaFlow.client.rpc(
      'batata_amazon_approve_products',
      params: {
        'p_product_ids': productIds,
        'p_note': note,
      },
    );
    if (res is! Map) {
      throw StateError('Resposta inválida da aprovação: $res');
    }
    final map = Map<String, dynamic>.from(res);
    final rejectedRaw = map['rejected'];
    final rejected = <Map<String, dynamic>>[];
    if (rejectedRaw is List) {
      for (final e in rejectedRaw) {
        if (e is Map) rejected.add(Map<String, dynamic>.from(e));
      }
    }
    final approvedIds = <String>[];
    final approvedRaw = map['approved_ids'];
    if (approvedRaw is List) {
      for (final e in approvedRaw) {
        if (e != null) approvedIds.add(e.toString());
      }
    }
    final skippedIds = <String>[];
    final skippedRaw = map['skipped_ids'];
    if (skippedRaw is List) {
      for (final e in skippedRaw) {
        if (e != null) skippedIds.add(e.toString());
      }
    }
    return {
      'approved': (map['approved'] as num?)?.toInt() ?? approvedIds.length,
      'blocked': (map['blocked'] as num?)?.toInt() ?? rejected.length,
      'skipped_already_approved':
          (map['skipped_already_approved'] as num?)?.toInt() ??
              skippedIds.length,
      'approved_ids': approvedIds,
      'skipped_ids': skippedIds,
      'rejected': rejected,
      'blocked_ids': [
        for (final r in rejected) r['product_id']?.toString() ?? '',
      ].where((e) => e.isNotEmpty).toList(),
      // Aprovação ≠ publicação.
      'published': false,
    };
  }

  Future<Map<String, dynamic>> approveOne({
    required String productId,
    String? note,
  }) =>
      bulkApprove(productIds: [productId], note: note);

  Future<Map<String, dynamic>> simulateFleaberDraft({
    required String productId,
    required bool confirm,
  }) async {
    if (!confirm) {
      return {'ok': false, 'message': 'Confirmação explícita em falta.'};
    }
    final ready = await refreshMissingReasons(productId);
    if (ready.isNotEmpty) {
      return {
        'ok': false,
        'message': 'Dados incompletos: ${ready.join(', ')}',
      };
    }
    final row = await SupaFlow.client
        .from('amazon_catalog_products')
        .select('catalog_status, approved_at, asin')
        .eq('id', productId)
        .maybeSingle();
    if (row == null || row['approved_at'] == null) {
      return {
        'ok': false,
        'message': 'Só após aprovação. Publicação automática desactivada.',
      };
    }
    final fakeId = 'SIM-FLEABER-${row['asin']}';
    await SupaFlow.client.from('amazon_catalog_products').update({
      'fleaber_sync_status': 'simulated_ok',
      'fleaber_sync_error': null,
      'catalog_status': 'draft_fleaber',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', productId);
    await SupaFlow.client.from('amazon_export_links').insert({
      'product_id': productId,
      'target': 'fleaber_draft',
      'external_id': fakeId,
      'status': 'skipped',
      'last_error':
          'Simulação ZIP 166 — nenhum anúncio real criado na Fleaber.',
      'meta': {
        'simulated': true,
        'zip': '166-C2',
        'external_id': fakeId,
      },
    });
    await SupaFlow.client.from('amazon_approval_events').insert({
      'actor_id': currentUserUid,
      'product_id': productId,
      'action': 'simulate_fleaber',
      'after_state': {'external_id': fakeId},
      'note': 'simulação — sem publicação',
    });
    return {
      'ok': true,
      'simulated': true,
      'external_id': fakeId,
      'message': 'Simulação Fleaber OK — sem criar anúncio real.',
    };
  }

  Future<Map<String, dynamic>> simulateMoloni({
    required String productId,
    required bool confirm,
  }) async {
    if (!confirm) {
      return {'ok': false, 'message': 'Confirmação explícita em falta.'};
    }
    final row = await SupaFlow.client
        .from('amazon_catalog_products')
        .select('asin, ean, title, approved_sale_eur, shipping_weight_kg')
        .eq('id', productId)
        .maybeSingle();
    if (row == null) {
      return {'ok': false, 'message': 'Produto em falta.'};
    }
    final payload = AmazonMoloniFieldMap.fromProduct(
      Map<String, dynamic>.from(row as Map),
    );
    // Peek próximo FLB sem avançar (ZIP 176).
    String plannedRef = 'FLB######';
    try {
      final peek = await SupaFlow.client.rpc(
        'peek_moloni_next_references',
        params: {'p_count': 1},
      );
      if (peek is List && peek.isNotEmpty) {
        final first = peek.first;
        if (first is Map && first['reference'] != null) {
          plannedRef = first['reference'].toString();
        }
      }
    } catch (_) {
      /* offline / sem grant — mantém placeholder */
    }
    payload['reference'] = plannedRef;
    final fakeId = 'SIM-MOLONI-$plannedRef';
    await SupaFlow.client.from('amazon_catalog_products').update({
      'moloni_sync_status': 'simulated_ok',
      'moloni_product_id': fakeId,
      'moloni_sync_error': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', productId);
    await SupaFlow.client.from('amazon_export_links').insert({
      'product_id': productId,
      'target': 'moloni',
      'external_id': fakeId,
      'status': 'skipped',
      'last_error':
          'Simulação ZIP 176 — sem products/insert (aguarda GO auto-create).',
      'meta': {
        'simulated': true,
        'zip': '176-C2',
        'planned_reference': plannedRef,
        'payload_preview': payload,
      },
    });
    await SupaFlow.client.from('amazon_approval_events').insert({
      'actor_id': currentUserUid,
      'product_id': productId,
      'action': 'simulate_moloni',
      'after_state': payload,
      'note': 'simulação ZIP 176 — FLB seq; sem API real',
    });
    return {
      'ok': true,
      'simulated': true,
      'external_id': fakeId,
      'planned_reference': plannedRef,
      'payload': payload,
      'message':
          'Simulação Moloni OK ($plannedRef) — sem criar artigo real.',
    };
  }
}

/// Mapa de campos Moloni (ZIP 176 — simulação; referência FLB###### na edge).
class AmazonMoloniFieldMap {
  static Map<String, dynamic> fromProduct(Map<String, dynamic> p) {
    return {
      // reference real atribuída pela sequência FLB###### (não usar ASIN).
      'reference': 'FLB###### (peek seq)',
      'ean': p['ean']?.toString(),
      'name': p['title']?.toString(),
      'price': p['approved_sale_eur'] ?? p['suggested_sale_eur'],
      'unit_id': 3308782, // Unidade
      'category_id': 10587619, // Amzeu
      'type': 1,
      'has_stock': 1,
      'stock': 0,
      'at_product_category': 'M',
      'weight': p['shipping_weight_kg'],
      'fiscal_regime': 'pending_accountant',
      'notes':
          'ZIP 176 auto-create — stock 0; regime margem 2ª mão só se elegível '
          '(validação contabilista).',
      'company_id': 354250,
      'asin': p['asin']?.toString(),
    };
  }
}
