import '/backend/supabase/supabase.dart';
import '/utils/live_prep_ref_details.dart';
import '/utils/live_prep_refs.dart';

/// Copia artigos marcados para o directo → `live_items` desta live.
abstract final class LiveCatalogSync {
  static String _normalizeRef(String raw) {
    var r = raw.trim().toUpperCase();
    if (r.startsWith('#')) r = r.substring(1);
    return r.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  static bool _productHasRef(List<ProductsRow> products, String ref) {
    final want = _normalizeRef(ref);
    if (want.isEmpty) return false;
    return products.any((p) => _normalizeRef(p.refCode ?? '') == want);
  }

  /// Resultado do sync para logs e UI.
  static Future<({
    int inserted,
    int schemeItems,
    int productItems,
    int schemesInPrefs,
  })> syncForLive({
    required String liveId,
    required String sellerId,
  }) async {
    final lid = liveId.trim();
    final sid = sellerId.trim();
    if (lid.isEmpty || sid.isEmpty) {
      return (
        inserted: 0,
        schemeItems: 0,
        productItems: 0,
        schemesInPrefs: 0,
      );
    }

    final products = await ProductsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('seller_id', sid)
          .eqOrNull('available_for_live', true)
          .eqOrNull('is_sold', false)
          .order('created_at', ascending: true),
      limit: 200,
    );

    final schemes = await LivePrepRefs.readSchemes();
    final refDetails = await LivePrepRefDetails.readAll();

    // Só apaga tudo quando o catálogo está vazio (1.º sync). Com itens já migrados
    // do draft (marketplace), usar [mergeForLive] para não perder entradas.
    final existing = await LiveItemsTable().queryRows(
      queryFn: (q) => q.eqOrNull('live_id', lid),
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return mergeForLive(liveId: lid, sellerId: sid);
    }

    var inserted = 0;
    var schemeRows = 0;
    var productRows = 0;
    var first = true;

    // Referências só-texto (Preparar Directo).
    for (final scheme in schemes) {
      if (scheme.spanCount <= 0) continue;

      if (scheme.spanCount <= 15) {
        // Ex.: «1 a 10» → um card por ref (#1, #2, …).
        for (final ref in scheme.expandRefs(max: 100)) {
          if (_productHasRef(products, ref)) continue;
          final detail = refDetails[LivePrepRefDetails.normalizeRefKey(ref)];
          final fallback = 'Ref ${ref.startsWith('#') ? ref.substring(1) : ref}';
          await LiveItemsTable().insert({
            'live_id': lid,
            'ref_code': ref,
            'title': detail?.buildLiveItemTitle(fallback) ?? fallback,
            'price': detail?.price,
            'photo_url': null,
            'is_active': first,
            'item_kind': 'live_only',
            'product_id': null,
            'quantity': detail?.quantity ?? 1,
          });
          inserted++;
          schemeRows++;
          first = false;
        }
      } else {
        await LiveItemsTable().insert({
          'live_id': lid,
          'ref_code': scheme.refCodeForCard(),
          'title': 'Refs ${scheme.displayLabel()}',
          'price': null,
          'photo_url': null,
          'is_active': first,
          'item_kind': 'live_only',
          'product_id': null,
          'quantity': 1,
        });
        inserted++;
        schemeRows++;
        first = false;

        for (final ref in scheme.expandRefs(max: 40)) {
          if (_productHasRef(products, ref)) continue;
          final detail = refDetails[LivePrepRefDetails.normalizeRefKey(ref)];
          final fallback = 'Ref ${ref.startsWith('#') ? ref.substring(1) : ref}';
          await LiveItemsTable().insert({
            'live_id': lid,
            'ref_code': ref,
            'title': detail?.buildLiveItemTitle(fallback) ?? fallback,
            'price': detail?.price,
            'photo_url': null,
            'is_active': first,
            'item_kind': 'live_only',
            'product_id': null,
            'quantity': detail?.quantity ?? 1,
          });
          inserted++;
          schemeRows++;
          first = false;
        }
      }
    }

    for (final p in products) {
      final ref = (p.refCode ?? '').trim();
      final title = (p.title ?? '').trim();
      final photos = p.imageUrls;
      await LiveItemsTable().insert({
        'live_id': lid,
        'ref_code': ref.isNotEmpty ? ref : '#${p.id?.substring(0, 6) ?? "item"}',
        'title': title.isNotEmpty ? title : 'Artigo',
        'price': p.price,
        'photo_url': photos.isNotEmpty ? photos.first : null,
        'is_active': first,
        'item_kind': 'marketplace_product',
        'product_id': p.id,
        'quantity': null,
      });
      inserted++;
      productRows++;
      first = false;
    }

    // Não limpar aqui — o 1.º sync (Mux) apagava refs antes do «Iniciar».
    return (
      inserted: inserted,
      schemeItems: schemeRows,
      productItems: productRows,
      schemesInPrefs: schemes.length,
    );
  }

  /// Acrescenta refs de esquema e produtos marketplace em falta — nunca apaga existentes.
  static Future<({
    int inserted,
    int schemeItems,
    int productItems,
    int schemesInPrefs,
  })> mergeForLive({
    required String liveId,
    required String sellerId,
  }) async {
    final lid = liveId.trim();
    final sid = sellerId.trim();
    if (lid.isEmpty || sid.isEmpty) {
      return (
        inserted: 0,
        schemeItems: 0,
        productItems: 0,
        schemesInPrefs: 0,
      );
    }

    final products = await ProductsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('seller_id', sid)
          .eqOrNull('available_for_live', true)
          .eqOrNull('is_sold', false)
          .order('created_at', ascending: true),
      limit: 200,
    );

    final schemes = await LivePrepRefs.readSchemes();
    final refDetails = await LivePrepRefDetails.readAll();

    final existing = await LiveItemsTable().queryRows(
      queryFn: (q) => q.eqOrNull('live_id', lid),
    );

    final existingRefs = <String>{};
    final existingProductIds = <String>{};
    var hasActive = existing.any((r) => r.isActive == true);
    for (final row in existing) {
      final ref = _normalizeRef(row.refCode ?? '');
      if (ref.isNotEmpty) existingRefs.add(ref);
      final pid = row.productId?.trim() ?? '';
      if (pid.isNotEmpty) existingProductIds.add(pid);
    }

    var inserted = 0;
    var schemeRows = 0;
    var productRows = 0;

    Future<void> insertSchemeItem({
      required String ref,
      required String fallbackTitle,
      LiveRefChipDetail? detail,
      required bool active,
    }) async {
      final norm = _normalizeRef(ref);
      if (norm.isEmpty || existingRefs.contains(norm)) return;
      await LiveItemsTable().insert({
        'live_id': lid,
        'ref_code': ref,
        'title': detail?.buildLiveItemTitle(fallbackTitle) ?? fallbackTitle,
        'price': detail?.price,
        'photo_url': null,
        'is_active': active,
        'item_kind': 'live_only',
        'product_id': null,
        'quantity': detail?.quantity ?? 1,
      });
      existingRefs.add(norm);
      inserted++;
      schemeRows++;
      if (active) hasActive = true;
    }

    for (final scheme in schemes) {
      if (scheme.spanCount <= 0) continue;

      if (scheme.spanCount <= 15) {
        for (final ref in scheme.expandRefs(max: 100)) {
          if (_productHasRef(products, ref)) continue;
          final detail = refDetails[LivePrepRefDetails.normalizeRefKey(ref)];
          final fallback =
              'Ref ${ref.startsWith('#') ? ref.substring(1) : ref}';
          await insertSchemeItem(
            ref: ref,
            fallbackTitle: fallback,
            detail: detail,
            active: !hasActive,
          );
        }
      } else {
        final cardRef = scheme.refCodeForCard();
        final cardNorm = _normalizeRef(cardRef);
        if (!existingRefs.contains(cardNorm)) {
          await LiveItemsTable().insert({
            'live_id': lid,
            'ref_code': cardRef,
            'title': 'Refs ${scheme.displayLabel()}',
            'price': null,
            'photo_url': null,
            'is_active': !hasActive,
            'item_kind': 'live_only',
            'product_id': null,
            'quantity': 1,
          });
          existingRefs.add(cardNorm);
          inserted++;
          schemeRows++;
          if (!hasActive) hasActive = true;
        }

        for (final ref in scheme.expandRefs(max: 40)) {
          if (_productHasRef(products, ref)) continue;
          final detail = refDetails[LivePrepRefDetails.normalizeRefKey(ref)];
          final fallback =
              'Ref ${ref.startsWith('#') ? ref.substring(1) : ref}';
          await insertSchemeItem(
            ref: ref,
            fallbackTitle: fallback,
            detail: detail,
            active: !hasActive,
          );
        }
      }
    }

    for (final p in products) {
      final pid = p.id?.trim() ?? '';
      if (pid.isEmpty || existingProductIds.contains(pid)) continue;
      final ref = (p.refCode ?? '').trim();
      final title = (p.title ?? '').trim();
      final photos = p.imageUrls;
      await LiveItemsTable().insert({
        'live_id': lid,
        'ref_code': ref.isNotEmpty ? ref : '#${pid.substring(0, 6)}',
        'title': title.isNotEmpty ? title : 'Artigo',
        'price': p.price,
        'photo_url': photos.isNotEmpty ? photos.first : null,
        'is_active': !hasActive,
        'item_kind': 'marketplace_product',
        'product_id': p.id,
        'quantity': null,
      });
      existingProductIds.add(pid);
      inserted++;
      productRows++;
      if (!hasActive) hasActive = true;
    }

    return (
      inserted: inserted,
      schemeItems: schemeRows,
      productItems: productRows,
      schemesInPrefs: schemes.length,
    );
  }

  /// Limpa prefs de preparação após o directo terminar.
  static Future<void> clearPrepAfterLiveEnd() async {
    await LivePrepRefs.clear();
    await LivePrepRefDetails.clear();
  }
}
