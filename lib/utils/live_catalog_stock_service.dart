import 'package:flutter/foundation.dart';

import '/backend/supabase/supabase.dart';
import '/utils/live_catalog_prep_service.dart';
import '/utils/live_ref_lineage_preview_service.dart';

/// Snapshot de stock unificado (RPC `batata_live_item_stock`).
class LiveCatalogStockSnapshot {
  const LiveCatalogStockSnapshot({
    required this.liveItemId,
    required this.liveId,
    required this.itemKind,
    this.productId,
    this.checkoutProductId,
    this.refCode,
    required this.totalQty,
    required this.blockedQty,
    required this.reservedAcceptedQty,
    required this.pendingBagQty,
    required this.soldConvertedQty,
    required this.availableQty,
    this.crossReservedQty = 0,
    this.raffleHoldQty = 0,
    this.liveStatus,
    this.liveItemPrice,
  });

  final String liveItemId;
  final String liveId;
  final String itemKind;
  final String? productId;
  final String? checkoutProductId;
  final String? refCode;
  final int totalQty;
  final int blockedQty;
  final int reservedAcceptedQty;
  final int pendingBagQty;
  final int soldConvertedQty;
  final int availableQty;
  /// Reservas pendentes/aceites noutros directos (mesma ref, mesmo vendedor).
  final int crossReservedQty;
  /// Unidades retidas por rifa AM5 (active/closed/drawn).
  final int raffleHoldQty;
  final String? liveStatus;
  final double? liveItemPrice;

  bool get isMarketplaceProduct => itemKind == 'marketplace_product';

  bool get isLiveOnly => itemKind == 'live_only';

  /// Reservas locais neste directo (saco pendente + aceites a pagar).
  int get localReservedQty {
    final pending = pendingBagQty < 0 ? 0 : pendingBagQty;
    final accepted = reservedAcceptedQty < 0 ? 0 : reservedAcceptedQty;
    return pending + accepted;
  }

  /// Reservas visíveis no card (local + outros directos/gravados com a mesma ref).
  int get displayReservedQty {
    final cross = crossReservedQty < 0 ? 0 : crossReservedQty;
    return localReservedQty + cross;
  }

  /// ID para checkout Stripe (TYPE A = product_id; TYPE B = checkout shadow).
  String? get checkoutProductIdOrPrimary =>
      isMarketplaceProduct ? productId : (checkoutProductId ?? productId);

  /// Stock local deste artigo no directo (ignora bloqueios cross-live/ref).
  int localDirectPayCapacity({int restorePendingQty = 0}) {
    final restore = restorePendingQty < 0 ? 0 : restorePendingQty;
    final pendingOthers = (pendingBagQty - restore).clamp(0, 99999);
    return (totalQty - soldConvertedQty - reservedAcceptedQty - pendingOthers)
        .clamp(0, 99999);
  }

  /// Prep com preço + stock local → compra directa sem aprovação da vendedora (Z6).
  bool canDirectPayWithoutApproval(int requestedQty, {int restorePendingQty = 0}) {
    final price = liveItemPrice;
    if (price == null || price <= 0) return false;
    final req = requestedQty < 1 ? 1 : requestedQty;
    return req <= localDirectPayCapacity(restorePendingQty: restorePendingQty);
  }

  /// O pedido excede o stock físico na live (ignora a própria linha pendente).
  bool requestExceedsSellableCapacity(
    int requestedQty, {
    int restorePendingQty = 0,
  }) {
    final req = requestedQty < 1 ? 1 : requestedQty;
    final restore = restorePendingQty < 0 ? 0 : restorePendingQty;
    final pendingOthers =
        (pendingBagQty - restore).clamp(0, 99999);
    final cap =
        (totalQty - blockedQty - reservedAcceptedQty - pendingOthers)
            .clamp(0, 99999);
    return req > cap;
  }

  factory LiveCatalogStockSnapshot.fromRpc(dynamic raw) {
    if (raw is! Map) {
      throw ArgumentError('Invalid stock RPC payload');
    }
    final m = Map<String, dynamic>.from(raw);
    if (m['ok'] != true) {
      throw StateError(m['error']?.toString() ?? 'stock_unavailable');
    }
    int i(dynamic v, [int fallback = 0]) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? fallback;
    }

    double? d(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse('$v'.replaceAll(',', '.'));
    }

    return LiveCatalogStockSnapshot(
      liveItemId: m['live_item_id']?.toString() ?? '',
      liveId: m['live_id']?.toString() ?? '',
      itemKind: m['item_kind']?.toString() ?? 'live_only',
      productId: m['product_id']?.toString(),
      checkoutProductId: m['checkout_product_id']?.toString(),
      refCode: m['ref_code']?.toString(),
      totalQty: i(m['total_qty'], 1),
      blockedQty: i(m['blocked_qty']),
      reservedAcceptedQty: i(m['reserved_accepted_qty']),
      pendingBagQty: i(m['pending_bag_qty']),
      soldConvertedQty: i(m['sold_converted_qty']),
      availableQty: i(m['available_qty']),
      crossReservedQty: i(m['cross_reserved_qty']),
      raffleHoldQty: i(m['raffle_hold_qty']),
      liveStatus: m['live_status']?.toString(),
      liveItemPrice: d(m['price']),
    );
  }
}

/// Fonte única de stock live (seller, helper, buyer, VOD, PDP com live_item).
abstract final class LiveCatalogStockService {
  static Future<LiveCatalogStockSnapshot?> fetch(String liveItemId) async {
    final id = liveItemId.trim();
    if (id.isEmpty) return null;
    try {
      final res = await SupaFlow.client.rpc(
        'batata_live_item_stock',
        params: {'p_live_item_id': id},
      );
      if (res == null) return null;
      return LiveCatalogStockSnapshot.fromRpc(res);
    } catch (e) {
      debugPrint('[LiveCatalogStock] fetch failed: $e');
      return null;
    }
  }

  static Future<Map<String, LiveCatalogStockSnapshot>> fetchMany(
    Iterable<String> liveItemIds,
  ) async {
    final ids = liveItemIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return {};

    final out = <String, LiveCatalogStockSnapshot>{};
    // Paralelo em lotes — evita N RPCs sequenciais a bloquear o isolate.
    // 12: menos ondas HTTP com catálogos ~80 sem mudar o contrato (1 RPC/item).
    const batchSize = 12;
    for (var i = 0; i < ids.length; i += batchSize) {
      final chunk = ids.sublist(
        i,
        i + batchSize > ids.length ? ids.length : i + batchSize,
      );
      final snaps = await Future.wait(chunk.map(fetch));
      for (var j = 0; j < chunk.length; j++) {
        final snap = snaps[j];
        if (snap != null) out[chunk[j]] = snap;
      }
    }
    return out;
  }

  static Future<LiveCatalogStockSnapshot?> updateItem({
    required String liveItemId,
    int? quantity,
    double? price,
    String? title,
    String? clothingSize,
    String? gender,
    String? refCode,
    String? photoUrl,
    String? description,
    bool? listOnMarketplace,
  }) async {
    final id = liveItemId.trim();
    if (id.isEmpty) return null;
    try {
      final res = await SupaFlow.client.rpc(
        'batata_update_live_item',
        params: {
          'p_live_item_id': id,
          if (quantity != null) 'p_quantity': quantity,
          if (price != null) 'p_price': price,
          if (title != null) 'p_title': title,
          if (clothingSize != null) 'p_clothing_size': clothingSize,
          if (gender != null) 'p_gender': gender,
          if (refCode != null) 'p_ref_code': refCode,
          if (photoUrl != null) 'p_photo_url': photoUrl,
          if (description != null) 'p_description': description,
          if (listOnMarketplace != null)
            'p_list_on_marketplace': listOnMarketplace,
        },
      );
      if (res == null) return null;
      return LiveCatalogStockSnapshot.fromRpc(res);
    } catch (e) {
      debugPrint('[LiveCatalogStock] update failed: $e');
      rethrow;
    }
  }

  static Future<String?> ensureDraftLive(String sellerId) async {
    final sid = sellerId.trim();
    if (sid.isEmpty) return null;
    try {
      final res = await SupaFlow.client.rpc(
        'batata_ensure_draft_live',
        params: {'p_seller_id': sid},
      );
      return res?.toString();
    } catch (e) {
      debugPrint('[LiveCatalogStock] ensureDraftLive: $e');
      return null;
    }
  }

  static Future<String?> upsertMarketplaceProduct({
    required String sellerId,
    required String productId,
    String? liveId,
  }) async {
    final sid = sellerId.trim();
    final pid = productId.trim();
    final lid = liveId?.trim() ?? '';
    if (lid.isNotEmpty && sid.isNotEmpty && pid.isNotEmpty) {
      final isDraft = await isDraftLiveForSeller(liveId: lid, sellerId: sid);
      if (!isDraft) {
        final allowed = await LiveCatalogPrepService.readSelectedProductIds();
        if (allowed.isNotEmpty && !allowed.contains(pid)) {
          debugPrint(
            '[LiveCatalogStock] upsert blocked: produto fora do prep ($pid)',
          );
          throw StateError('product_not_in_prep_selection');
        }
      }
    }
    try {
      final res = await SupaFlow.client.rpc(
        'batata_upsert_marketplace_live_item',
        params: {
          'p_seller_id': sellerId.trim(),
          'p_product_id': productId.trim(),
          if (liveId != null && liveId.trim().isNotEmpty)
            'p_live_id': liveId.trim(),
        },
      );
      return res?.toString();
    } catch (e) {
      debugPrint('[LiveCatalogStock] upsertMarketplace: $e');
      rethrow;
    }
  }

  static Future<void> removeMarketplaceProduct({
    required String sellerId,
    required String productId,
    String? liveId,
  }) async {
    await SupaFlow.client.rpc(
      'batata_remove_marketplace_live_item',
      params: {
        'p_seller_id': sellerId.trim(),
        'p_product_id': productId.trim(),
        if (liveId != null && liveId.trim().isNotEmpty)
          'p_live_id': liveId.trim(),
      },
    );
  }

  static Future<LiveOnlyUpsertResult?> upsertLiveOnlyItem({
    required String sellerId,
    required String refCode,
    String? title,
    double? price,
    int? quantity,
    String? clothingSize,
    String? gender,
    String? photoUrl,
    String? liveId,
    String lineageMode = 'new',
    String? logicalItemId,
  }) async {
    try {
      final res = await SupaFlow.client.rpc(
        'batata_upsert_live_only_item',
        params: {
          'p_seller_id': sellerId.trim(),
          'p_ref_code': refCode.trim(),
          if (title != null) 'p_title': title,
          if (price != null) 'p_price': price,
          if (quantity != null) 'p_quantity': quantity,
          if (clothingSize != null) 'p_clothing_size': clothingSize,
          if (gender != null) 'p_gender': gender,
          if (photoUrl != null) 'p_photo_url': photoUrl,
          if (liveId != null && liveId.trim().isNotEmpty)
            'p_live_id': liveId.trim(),
          'p_lineage_mode': lineageMode.trim(),
          if (logicalItemId != null && logicalItemId.trim().isNotEmpty)
            'p_logical_item_id': logicalItemId.trim(),
        },
      );
      final parsed = LiveOnlyUpsertResult.fromRpc(res);
      if (parsed.liveItemId.isEmpty) return null;
      return parsed;
    } catch (e) {
      debugPrint('[LiveCatalogStock] upsertLiveOnly: $e');
      rethrow;
    }
  }

  static Future<int> migrateCatalog({
    required String fromLiveId,
    required String toLiveId,
    required String sellerId,
  }) async {
    try {
      final res = await SupaFlow.client.rpc(
        'batata_migrate_live_catalog',
        params: {
          'p_from_live_id': fromLiveId.trim(),
          'p_to_live_id': toLiveId.trim(),
          'p_seller_id': sellerId.trim(),
        },
      );
      if (res is int) return res;
      if (res is num) return res.toInt();
      return int.tryParse('$res') ?? 0;
    } catch (e) {
      debugPrint('[LiveCatalogStock] migrateCatalog: $e');
      return 0;
    }
  }

  static Future<String?> ensureCheckoutProduct(String liveItemId) async {
    final id = liveItemId.trim();
    if (id.isEmpty) return null;
    try {
      final res = await SupaFlow.client.rpc(
        'batata_ensure_checkout_product',
        params: {'p_live_item_id': id},
      );
      return res?.toString();
    } catch (e) {
      debugPrint('[LiveCatalogStock] ensureCheckoutProduct: $e');
      return null;
    }
  }

  /// Produto Stripe para checkout live (RPC security definer + fallback local).
  static Future<ProductsRow?> resolveCheckoutProduct(
    String liveItemId, {
    LiveItemsRow? itemRow,
    String? sellerId,
    String? liveId,
  }) async {
    final id = liveItemId.trim();
    if (id.isEmpty) return null;

    final fromRpc = await _resolveCheckoutProductRpc(id);
    if (fromRpc != null) return fromRpc;

    return synthesizeCheckoutProductRow(
      liveItemId: id,
      itemRow: itemRow,
      sellerId: sellerId,
      liveId: liveId,
    );
  }

  /// Monta `ProductsRow` para Stripe sem ler `products` (RLS shadow).
  static Future<ProductsRow?> synthesizeCheckoutProductRow({
    required String liveItemId,
    LiveItemsRow? itemRow,
    String? sellerId,
    String? liveId,
  }) async {
    final id = liveItemId.trim();
    if (id.isEmpty) return null;

    try {
      var row = itemRow ?? await fetchLiveItemById(id);
      String? ensureErr;
      String? shadowId;
      try {
        shadowId = await ensureCheckoutProduct(id);
      } catch (e) {
        ensureErr = e.toString();
      }
      row = await fetchLiveItemById(id) ?? row;
      shadowId = (shadowId != null && shadowId.trim().isNotEmpty)
          ? shadowId.trim()
          : row?.checkoutProductId?.trim();
      if (shadowId == null || shadowId.isEmpty) {
        debugPrint(
          '[LiveCatalogStock] synthesize no shadow id'
          '${ensureErr != null ? ': $ensureErr' : ''}',
        );
        return null;
      }

      final snap = await fetch(id);
      final price = (snap?.liveItemPrice != null && snap!.liveItemPrice! > 0)
          ? snap.liveItemPrice
          : row?.price;
      if (price == null || price <= 0) return null;

      var sid = sellerId?.trim() ?? '';
      if (sid.isEmpty) {
        final lid = (liveId ?? row?.liveId ?? snap?.liveId ?? '').trim();
        if (lid.isNotEmpty) {
          final lives = await LivesTable().queryRows(
            queryFn: (q) => q.eqOrNull('id', lid),
            limit: 1,
          );
          if (lives.isNotEmpty) {
            sid = lives.first.sellerId?.trim() ?? '';
          }
        }
      }
      if (sid.isEmpty) return null;

      final photo = row?.photoUrl?.trim();
      return ProductsRow({
        'id': shadowId,
        'seller_id': sid,
        'title': row?.title?.trim().isNotEmpty == true
            ? row!.title!.trim()
            : 'Artigo live',
        'price': price,
        'ref_code': row?.refCode,
        'image_urls': photo != null && photo.isNotEmpty ? [photo] : <String>[],
        'list_on_marketplace': false,
        'available_for_live': false,
      });
    } catch (e) {
      debugPrint('[LiveCatalogStock] synthesizeCheckoutProductRow: $e');
      return null;
    }
  }

  static ProductsRow? _productRowFromCheckoutRpc(Map<String, dynamic> m) {
    final pid = m['product_id']?.toString();
    if (pid == null || pid.isEmpty) return null;
    final imgs = m['image_urls'];
    List<String> imageUrls = const [];
    if (imgs is List) {
      imageUrls = imgs.map((e) => e.toString()).toList();
    }
    double? price;
    final rawPrice = m['price'];
    if (rawPrice is num) {
      price = rawPrice.toDouble();
    } else if (rawPrice != null) {
      price = double.tryParse('$rawPrice'.replaceAll(',', '.'));
    }
    final sellerId = m['seller_id']?.toString();
    if (sellerId == null || sellerId.isEmpty) return null;
    return ProductsRow({
      'id': pid,
      'seller_id': sellerId,
      'title': m['title']?.toString() ?? 'Artigo live',
      'price': price,
      'ref_code': m['ref_code']?.toString(),
      'image_urls': imageUrls,
      'description': m['description']?.toString(),
      'clothing_size': m['clothing_size']?.toString(),
      'gender': m['gender']?.toString(),
      'list_on_marketplace': false,
      'available_for_live': false,
    });
  }

  static Future<ProductsRow?> _resolveCheckoutProductRpc(String id) async {
    try {
      final res = await SupaFlow.client.rpc(
        'batata_resolve_live_checkout_product',
        params: {'p_live_item_id': id},
      );
      if (res is! Map) return null;
      final m = Map<String, dynamic>.from(res);
      if (m['ok'] != true) {
        debugPrint(
          '[LiveCatalogStock] resolveCheckoutProduct rpc: ${m['error']}',
        );
        return null;
      }
      return _productRowFromCheckoutRpc(m);
    } catch (e) {
      debugPrint('[LiveCatalogStock] resolveCheckoutProduct rpc miss: $e');
      return null;
    }
  }

  static Future<LiveCatalogStockSnapshot?> markItemSold(String liveItemId) async {
    final id = liveItemId.trim();
    if (id.isEmpty) return null;
    try {
      final res = await SupaFlow.client.rpc(
        'batata_mark_live_item_sold',
        params: {'p_live_item_id': id},
      );
      if (res == null) return null;
      final map = res is Map ? Map<String, dynamic>.from(res) : null;
      if (map != null && map['ok'] != true) {
        throw StateError(map['error']?.toString() ?? 'mark_sold_failed');
      }
      return LiveCatalogStockSnapshot.fromRpc(res);
    } catch (e) {
      debugPrint('[LiveCatalogStock] markItemSold failed: $e');
      rethrow;
    }
  }

  /// Lê `live_items` fresco (preço/qty após editar no directo).
  ///
  /// Após aceite o artigo pode ficar `reserved_full` / `is_active=false` e a
  /// policy `live_items_select_for_live` esconde a linha ao comprador — o saco
  /// via SELECT fica sem preço («aguarda preço» / 0 €). Fallback: RPCs
  /// security definer (`batata_resolve_live_checkout_product` /
  /// `batata_live_item_stock`) que já permitem comprador com saco.
  static Future<LiveItemsRow?> fetchLiveItemById(String liveItemId) async {
    final id = liveItemId.trim();
    if (id.isEmpty) return null;
    try {
      final rows = await LiveItemsTable().queryRows(
        queryFn: (q) => q.eqOrNull('id', id),
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final row = rows.first;
        final p = row.price;
        if (p != null && p > 0) return row;
        // Linha visível mas sem preço útil → enriquecer via RPC.
        final viaRpc = await fetchLiveItemRowForBag(id);
        if (viaRpc != null) return viaRpc;
        return row;
      }
    } catch (e) {
      debugPrint('[LiveCatalogStock] fetchLiveItemById: $e');
    }
    return fetchLiveItemRowForBag(id);
  }

  /// Monta `LiveItemsRow` para o saco quando o SELECT RLS falha/omite o artigo.
  static Future<LiveItemsRow?> fetchLiveItemRowForBag(String liveItemId) async {
    final id = liveItemId.trim();
    if (id.isEmpty) return null;
    try {
      final fromCheckout = await _resolveCheckoutProductRpc(id);
      final snap = await fetch(id);
      if (fromCheckout == null && snap == null) return null;
      return liveItemRowFromBagRpcs(
        liveItemId: id,
        snap: snap,
        checkoutProduct: fromCheckout,
      );
    } catch (e) {
      debugPrint('[LiveCatalogStock] fetchLiveItemRowForBag: $e');
      return null;
    }
  }

  /// Puro / testável: une snapshot stock + produto checkout no row do saco.
  static LiveItemsRow liveItemRowFromBagRpcs({
    required String liveItemId,
    LiveCatalogStockSnapshot? snap,
    ProductsRow? checkoutProduct,
  }) {
    // Live-first (mesmo critério do checkout / resolveFreshUnitPrice).
    final livePrice = snap?.liveItemPrice;
    final productPrice = checkoutProduct?.price;
    double? price;
    if (livePrice != null && livePrice > 0) {
      price = livePrice;
    } else if (productPrice != null && productPrice > 0) {
      price = productPrice;
    }
    final imgs = checkoutProduct?.imageUrls ?? const <String>[];
    final photo = imgs.isNotEmpty ? imgs.first : null;
    final ref = (snap?.refCode ?? checkoutProduct?.refCode)?.trim();
    final title = checkoutProduct?.title?.trim();
    final productId = (snap?.productId != null && snap!.productId!.isNotEmpty)
        ? snap.productId
        : checkoutProduct?.id;
    return LiveItemsRow({
      'id': liveItemId,
      if (snap?.liveId != null && snap!.liveId.isNotEmpty) 'live_id': snap.liveId,
      if (ref != null && ref.isNotEmpty) 'ref_code': ref,
      'title': (title != null && title.isNotEmpty)
          ? title
          : (ref != null && ref.isNotEmpty ? 'Ref $ref' : 'Artigo live'),
      if (photo != null && photo.isNotEmpty) 'photo_url': photo,
      if (price != null) 'price': price,
      if (productId != null && productId.isNotEmpty) 'product_id': productId,
      if (snap?.checkoutProductId != null)
        'checkout_product_id': snap!.checkoutProductId,
      'item_kind': snap?.itemKind ??
          (checkoutProduct != null ? 'marketplace_product' : 'live_only'),
      if (checkoutProduct?.sellerId != null &&
          checkoutProduct!.sellerId!.isNotEmpty)
        'seller_id': checkoutProduct.sellerId,
      if (checkoutProduct?.clothingSize != null)
        'clothing_size': checkoutProduct!.clothingSize,
      if (checkoutProduct?.gender != null) 'gender': checkoutProduct!.gender,
    });
  }

  /// Stock efectivo para PDP marketplace: se o artigo está num directo com
  /// rifa (hold), devolve o snapshot live (availableQty já com hold).
  /// Sem live_item ligado → null (usar `products.quantity`).
  ///
  /// Preferir RPC `batata_live_stock_for_product` (security definer) — o
  /// SELECT em `live_items` pode falhar por RLS e o detalhe mostrava o
  /// `products.quantity` cru (ex. 2 em vez de 1 com rifa).
  static Future<LiveCatalogStockSnapshot?> fetchForMarketplaceProduct(
    String productId,
  ) async {
    final pid = productId.trim();
    if (pid.isEmpty) return null;
    try {
      final res = await SupaFlow.client.rpc(
        'batata_live_stock_for_product',
        params: {'p_product_id': pid},
      );
      if (res != null) {
        try {
          return LiveCatalogStockSnapshot.fromRpc(res);
        } on StateError catch (e) {
          // Sem live_item → cair no fallback table / null.
          if (!e.toString().contains('no_live_item_for_product')) {
            debugPrint('[LiveCatalogStock] product RPC: $e');
          }
        } catch (e) {
          debugPrint('[LiveCatalogStock] product RPC parse: $e');
        }
      }
    } catch (e) {
      // RPC ainda não deployada → fallback SELECT.
      debugPrint('[LiveCatalogStock] product RPC unavailable: $e');
    }

    try {
      final byProduct = await LiveItemsTable().queryRows(
        queryFn: (q) => q.eqOrNull('product_id', pid),
        limit: 20,
      );
      final byCheckout = await LiveItemsTable().queryRows(
        queryFn: (q) => q.eqOrNull('checkout_product_id', pid),
        limit: 20,
      );
      final seen = <String>{};
      final ids = <String>[];
      for (final r in [...byProduct, ...byCheckout]) {
        final id = r.id?.trim() ?? '';
        if (id.isEmpty || !seen.add(id)) continue;
        ids.add(id);
      }
      if (ids.isEmpty) return null;

      LiveCatalogStockSnapshot? best;
      for (final id in ids) {
        final snap = await fetch(id);
        if (snap == null) continue;
        if (best == null) {
          best = snap;
          continue;
        }
        // Preferir o que tem hold de rifa / menos Disp. (mais restritivo).
        if (snap.raffleHoldQty > best.raffleHoldQty) {
          best = snap;
        } else if (snap.raffleHoldQty == best.raffleHoldQty &&
            snap.availableQty < best.availableQty) {
          best = snap;
        }
      }
      return best;
    } catch (e) {
      debugPrint('[LiveCatalogStock] fetchForMarketplaceProduct: $e');
      return null;
    }
  }

  /// Stock para vários produtos marketplace num único lote (menos round-trips).
  ///
  /// 1) Uma query `live_items` por `product_id` (+ checkout) em chunks.
  /// 2) RPCs/`fetch` só para os live_item ids candidatos (em paralelo).
  /// Produtos sem live_item → `null` (usar `products.quantity` no caller).
  static Future<Map<String, LiveCatalogStockSnapshot?>>
      fetchForMarketplaceProductsBatch(Iterable<String> productIds) async {
    final ids = productIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    final out = <String, LiveCatalogStockSnapshot?>{
      for (final id in ids) id: null,
    };
    if (ids.isEmpty) return out;

    // Map productId → live_item ids candidatos.
    final liveItemIdsByProduct = <String, List<String>>{};
    const idChunk = 80;
    for (var start = 0; start < ids.length; start += idChunk) {
      final end = start + idChunk > ids.length ? ids.length : start + idChunk;
      final chunk = ids.sublist(start, end);
      try {
        final byProduct = await LiveItemsTable().queryRows(
          queryFn: (q) => q.inFilter('product_id', chunk),
          limit: chunk.length * 5,
        );
        final byCheckout = await LiveItemsTable().queryRows(
          queryFn: (q) => q.inFilter('checkout_product_id', chunk),
          limit: chunk.length * 5,
        );
        for (final r in [...byProduct, ...byCheckout]) {
          final liveItemId = r.id?.trim() ?? '';
          if (liveItemId.isEmpty) continue;
          final pid = (r.productId?.trim().isNotEmpty == true
                  ? r.productId!.trim()
                  : (r.data['checkout_product_id']?.toString().trim() ?? ''))
              .trim();
          if (pid.isEmpty || !out.containsKey(pid)) continue;
          final list = liveItemIdsByProduct.putIfAbsent(pid, () => <String>[]);
          if (!list.contains(liveItemId)) list.add(liveItemId);
        }
      } catch (e) {
        debugPrint('[LiveCatalogStock] batch live_items lookup: $e');
      }
    }

    final allLiveItemIds = <String>{};
    for (final list in liveItemIdsByProduct.values) {
      allLiveItemIds.addAll(list);
    }

    final snapByLiveItem = <String, LiveCatalogStockSnapshot?>{};
    const fetchChunk = 24;
    final liveIds = allLiveItemIds.toList();
    for (var start = 0; start < liveIds.length; start += fetchChunk) {
      final end =
          start + fetchChunk > liveIds.length ? liveIds.length : start + fetchChunk;
      final chunk = liveIds.sublist(start, end);
      final snaps = await Future.wait(
        chunk.map(
          (id) => fetch(id)
              .timeout(const Duration(seconds: 5), onTimeout: () => null)
              .catchError((_) => null),
        ),
      );
      for (var i = 0; i < chunk.length; i++) {
        snapByLiveItem[chunk[i]] = snaps[i];
      }
    }

    for (final pid in ids) {
      final candidates = liveItemIdsByProduct[pid];
      if (candidates == null || candidates.isEmpty) {
        // Sem live_item: tentar RPC individual (rifa/hold) só se necessário.
        // Em lote preferimos null → caller usa products.quantity.
        continue;
      }
      LiveCatalogStockSnapshot? best;
      for (final lid in candidates) {
        final snap = snapByLiveItem[lid];
        if (snap == null) continue;
        if (best == null) {
          best = snap;
          continue;
        }
        if (snap.raffleHoldQty > best.raffleHoldQty) {
          best = snap;
        } else if (snap.raffleHoldQty == best.raffleHoldQty &&
            snap.availableQty < best.availableQty) {
          best = snap;
        }
      }
      out[pid] = best;
    }

    // Sem live_item → null; o caller usa products.quantity (igual ao fluxo antigo).
    return out;
  }

  /// Actualiza entradas do mapa com dados actuais da BD.
  static Future<Map<String, LiveItemsRow>> refreshCatalogByItemIds(
    Map<String, LiveItemsRow> catalog,
    Iterable<String> itemIds,
  ) async {
    final out = Map<String, LiveItemsRow>.from(catalog);
    for (final raw in itemIds) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      final fresh = await fetchLiveItemById(id);
      if (fresh != null) out[id] = fresh;
    }
    return out;
  }

  /// Draft válido em cache: existe, `status=draft` e pertence ao seller.
  static Future<bool> isDraftLiveForSeller({
    required String liveId,
    required String sellerId,
  }) async {
    final id = liveId.trim();
    final sid = sellerId.trim();
    if (id.isEmpty || sid.isEmpty) return false;
    try {
      final rows = await LivesTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('id', id)
            .eqOrNull('status', 'draft')
            .or('seller_id.eq.$sid,vendedor_id.eq.$sid'),
        limit: 1,
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> findDraftLiveId(String sellerId) async {
    final sid = sellerId.trim();
    if (sid.isEmpty) return null;
    try {
      final rows = await LivesTable().queryRows(
        queryFn: (q) => q
            .eqOrNull('status', 'draft')
            .eqOrNull('is_active', false)
            .order('created_at', ascending: false),
        limit: 5,
      );
      for (final r in rows) {
        final s = r.sellerId?.trim() ?? r.vendedorId?.trim() ?? '';
        if (s == sid) return r.id;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> findLatestSessionLiveId(String sellerId) async {
    final sid = sellerId.trim();
    if (sid.isEmpty) return null;
    try {
      final rows = await LivesTable().queryRows(
        queryFn: (q) => q
            .inFilter('status', ['live', 'ended'])
            .order('created_at', ascending: false),
        limit: 8,
      );
      for (final r in rows) {
        final s = r.sellerId?.trim() ?? r.vendedorId?.trim() ?? '';
        if (s == sid) return r.id;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Set<String>> fetchLiveOnlyNormalizedRefs(String liveId) async {
    final id = liveId.trim();
    if (id.isEmpty) return {};
    try {
      final rows = await LiveItemsTable().queryRows(
        queryFn: (q) =>
            q.eqOrNull('live_id', id).eqOrNull('item_kind', 'live_only'),
      );
      final out = <String>{};
      for (final r in rows) {
        final raw = r.refCode?.trim() ?? '';
        if (raw.isEmpty) continue;
        var key = raw.toUpperCase();
        if (key.startsWith('#')) key = key.substring(1);
        key = key.replaceAll(RegExp(r'[^A-Z0-9]'), '');
        if (key.isNotEmpty) out.add(key);
      }
      return out;
    } catch (_) {
      return {};
    }
  }
}
