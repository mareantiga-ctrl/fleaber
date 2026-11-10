import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/live_catalog_prep_service.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_prep_ref_details.dart';
import '/utils/live_prep_refs.dart';
import '/utils/live_ref_scheme.dart';
import 'package:flutter/foundation.dart';

/// Copia artigos marcados para o directo → `live_items` desta live.
///
/// **Marketplace:** a selecção vem do prep (draft → migrate / upsert).
/// [mergeForLive] **não** volta a injectar todos os `available_for_live=true`
/// (isso rebentava o catálogo com dezenas de V0/QA).
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
          .eqOrNull('is_draft', false)
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
    const productRows = 0;
    var first = true;

    // Referências só-texto (Preparar Directo).
    // is_active = «a mostrar agora» (destaque), NÃO «pertence ao catálogo».
    // Só o 1.º recebe destaque; os restantes ficam no catálogo com is_active=false.
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

    // Marketplace: só via prep (draft upsert → migrate). Não injectar todos
    // os available_for_live=true (QA V0 enchia o catálogo).
    return (
      inserted: inserted,
      schemeItems: schemeRows,
      productItems: productRows,
      schemesInPrefs: schemes.length,
    );
  }

  /// Só prune marketplace/live_only — sem injectar refs (anti-creep APP-200).
  static Future<int> enforcePrepAllowList({
    required String liveId,
    required String sellerId,
  }) async {
    final lid = liveId.trim();
    final sid = sellerId.trim();
    if (lid.isEmpty || sid.isEmpty) return 0;

    final productsOn = await ProductsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('seller_id', sid)
          .eqOrNull('available_for_live', true)
          .eqOrNull('is_sold', false)
          .eqOrNull('is_draft', false)
          .order('created_at', ascending: true),
      limit: 200,
    );

    final schemes = await LivePrepRefs.readSchemes();
    final existing = await LiveItemsTable().queryRows(
      queryFn: (q) => q.eqOrNull('live_id', lid),
    );
    if (existing.isEmpty) return 0;

    final allowedProductIds = await _resolveAllowedMarketplaceProductIds(
      sellerId: sid,
      liveId: lid,
      existing: existing,
    );

    final availableForLiveById = {
      for (final p in productsOn)
        if ((p.id ?? '').trim().isNotEmpty) p.id!.trim(): p.availableForLive == true,
    };

    var deleted = await _pruneUnavailableMarketplaceItems(
      liveId: lid,
      sellerId: sid,
      existing: existing,
      allowedProductIds: allowedProductIds,
      availableForLiveById: availableForLiveById,
    );

    deleted += await _pruneStaleLiveOnlyItems(
      liveId: lid,
      existing: existing,
      schemes: schemes,
      allowedProductRefs: _allowedProductRefsFromSelection(
        productsOn: productsOn,
        allowedProductIds: allowedProductIds,
      ),
    );
    return deleted;
  }

  static Set<String> _allowedProductRefsFromSelection({
    required List<ProductsRow> productsOn,
    required Set<String> allowedProductIds,
  }) {
    if (allowedProductIds.isEmpty) return {};
    final refs = <String>{};
    for (final p in productsOn) {
      final pid = p.id?.trim() ?? '';
      if (pid.isEmpty || !allowedProductIds.contains(pid)) continue;
      final norm = _normalizeRef(p.refCode ?? '');
      if (norm.isNotEmpty) refs.add(norm);
    }
    return refs;
  }

  /// Acrescenta refs em falta e remove marketplace desactivado no prep.
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

    // Só para evitar duplicar refs live_only que já têm produto marketplace ON.
    final productsOn = await ProductsTable().queryRows(
      queryFn: (q) => q
          .eqOrNull('seller_id', sid)
          .eqOrNull('available_for_live', true)
          .eqOrNull('is_sold', false)
          .eqOrNull('is_draft', false)
          .order('created_at', ascending: true),
      limit: 200,
    );

    final schemes = await LivePrepRefs.readSchemes();
    final refDetails = await LivePrepRefDetails.readAll();

    final existing = await LiveItemsTable().queryRows(
      queryFn: (q) => q.eqOrNull('live_id', lid),
    );

    // Regressão APP-200: allow-list = prep (pref/draft), NÃO todos os ON na BD.
    final allowedProductIds = await _resolveAllowedMarketplaceProductIds(
      sellerId: sid,
      liveId: lid,
      existing: existing,
    );

    final availableForLiveById = {
      for (final p in productsOn)
        if ((p.id ?? '').trim().isNotEmpty) p.id!.trim(): p.availableForLive == true,
    };

    // Prep desactivou: tira do catálogo desta live (RPC — respeita p_live_id).
    await _pruneUnavailableMarketplaceItems(
      liveId: lid,
      sellerId: sid,
      existing: existing,
      allowedProductIds: allowedProductIds,
      availableForLiveById: availableForLiveById,
    );

    await _pruneStaleLiveOnlyItems(
      liveId: lid,
      existing: existing,
      schemes: schemes,
      allowedProductRefs: _allowedProductRefsFromSelection(
        productsOn: productsOn,
        allowedProductIds: allowedProductIds,
      ),
    );

    final existingAfterPrune = await LiveItemsTable().queryRows(
      queryFn: (q) => q.eqOrNull('live_id', lid),
    );

    final existingRefs = <String>{};
    var hasActive = existingAfterPrune.any((r) => r.isActive == true);
    for (final row in existingAfterPrune) {
      final ref = _normalizeRef(row.refCode ?? '');
      if (ref.isNotEmpty) existingRefs.add(ref);
    }

    var inserted = 0;
    var schemeRows = 0;
    const productRows = 0;

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
          if (_productHasRef(productsOn, ref)) continue;
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
          if (_productHasRef(productsOn, ref)) continue;
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

    // Marketplace: NÃO inserir aqui. Só draft/migrate/upsert do prep.
    return (
      inserted: inserted,
      schemeItems: schemeRows,
      productItems: productRows,
      schemesInPrefs: schemes.length,
    );
  }

  /// Resolve allow-list marketplace para merge/prune (regressão APP-200).
  @visibleForTesting
  static Future<Set<String>> resolveAllowedMarketplaceProductIds({
    required String sellerId,
    required String liveId,
    required List<LiveItemsRow> existing,
    required Future<Set<String>> Function() readPrepSelected,
    required Future<String?> Function(String sellerId) findDraftLiveId,
    required Future<Set<String>> Function(String liveId) productIdsOnLive,
  }) async {
    final fromPrep = await readPrepSelected();
    if (fromPrep.isNotEmpty) return fromPrep;

    final draftId = await findDraftLiveId(sellerId.trim());
    if (draftId != null && draftId.trim().isNotEmpty) {
      final fromDraft = await productIdsOnLive(draftId.trim());
      if (fromDraft.isNotEmpty) return fromDraft;
    }

    // Prep sem marketplace (só refs live_only / tudo desmarcado): allow-list
    // vazia. NÃO cair no que já está na live — isso impedia o prune e
    // reapareciam T01–T10 após desmarcar no Preparar (APP-200).
    return {};
  }

  static Future<Set<String>> _resolveAllowedMarketplaceProductIds({
    required String sellerId,
    required String liveId,
    required List<LiveItemsRow> existing,
  }) =>
      resolveAllowedMarketplaceProductIds(
        sellerId: sellerId,
        liveId: liveId,
        existing: existing,
        readPrepSelected: LiveCatalogPrepService.readSelectedProductIds,
        findDraftLiveId: LiveCatalogStockService.findDraftLiveId,
        productIdsOnLive: _marketplaceProductIdsOnLive,
      );

  static Future<Set<String>> _marketplaceProductIdsOnLive(String liveId) async {
    final rows = await LiveItemsTable().queryRows(
      queryFn: (q) => q.eqOrNull('live_id', liveId),
      limit: 500,
    );
    final ids = <String>{};
    for (final row in rows) {
      final kind = (row.itemKind ?? '').trim();
      if (kind == 'live_only') continue;
      final pid = row.productId?.trim() ?? '';
      if (pid.isNotEmpty) ids.add(pid);
    }
    return ids;
  }

  /// Se [allowedProductIds] não vazio → só esses.
  /// Se vazio → remover marketplace desta live (prep sem catálogo / desmarcado).
  /// Não usar `available_for_live` como allow-list: produtos ON na loja voltavam
  /// ao directo depois de desmarcados no Preparar.
  @visibleForTesting
  static bool shouldPruneMarketplaceProduct({
    required String productId,
    required Set<String> allowedProductIds,
    required bool? availableForLive,
  }) {
    final pid = productId.trim();
    if (pid.isEmpty) return false;
    if (allowedProductIds.isNotEmpty) {
      return !allowedProductIds.contains(pid);
    }
    // Empty allow-list = prep without marketplace (ignore shop available_for_live).
    final _ignoredShopFlag = availableForLive;
    assert(_ignoredShopFlag == availableForLive);
    return true;
  }

  /// Remove `live_items` marketplace fora da selecção prep.
  static Future<int> _pruneUnavailableMarketplaceItems({
    required String liveId,
    required String sellerId,
    required List<LiveItemsRow> existing,
    required Set<String> allowedProductIds,
    required Map<String, bool> availableForLiveById,
  }) async {
    final lid = liveId.trim();
    final sid = sellerId.trim().isNotEmpty ? sellerId.trim() : currentUserUid;
    if (lid.isEmpty || existing.isEmpty || sid.isEmpty) return 0;

    var deleted = 0;
    for (final row in existing) {
      final pid = row.productId?.trim() ?? '';
      if (pid.isEmpty) continue;
      final kind = (row.itemKind ?? '').trim();
      if (kind == 'live_only') continue;
      if (!shouldPruneMarketplaceProduct(
        productId: pid,
        allowedProductIds: allowedProductIds,
        availableForLive: availableForLiveById[pid],
      )) {
        continue;
      }
      try {
        await LiveCatalogStockService.removeMarketplaceProduct(
          sellerId: sid,
          productId: pid,
          liveId: lid,
        );
        deleted++;
      } catch (_) {
        try {
          final iid = row.id?.trim() ?? '';
          if (iid.isEmpty) continue;
          await LiveItemsTable().delete(
            matchingRows: (q) => q.eqOrNull('id', iid),
          );
          deleted++;
        } catch (_) {}
      }
    }
    return deleted;
  }

  /// Remove refs live_only que já não estão no prep (intervalos / chips).
  ///
  /// **BATATA:** se não há allow-list de prep (schemes vazios + sem refs de
  /// produtos), **não apagar** live_only — foram criadas no Studio (ex. FX1/FX2
  /// manuais). Allow-list vazia + prune = apagava o catálogo inteiro.
  static Future<int> _pruneStaleLiveOnlyItems({
    required String liveId,
    required List<LiveItemsRow> existing,
    required List<LiveRefScheme> schemes,
    required Set<String> allowedProductRefs,
  }) async {
    final lid = liveId.trim();
    if (lid.isEmpty || existing.isEmpty) return 0;

    final allowedRefs = <String>{...allowedProductRefs};
    for (final scheme in schemes) {
      if (scheme.spanCount <= 0) continue;
      final max = scheme.spanCount <= 15 ? 100 : 40;
      for (final ref in scheme.expandRefs(max: max)) {
        final norm = _normalizeRef(ref);
        if (norm.isNotEmpty) allowedRefs.add(norm);
      }
      if (scheme.spanCount > 15) {
        final cardNorm = _normalizeRef(scheme.refCodeForCard());
        if (cardNorm.isNotEmpty) allowedRefs.add(cardNorm);
      }
    }

    // Sem prep explícito → manter live_only criadas no directo.
    if (allowedRefs.isEmpty) return 0;

    var deleted = 0;
    for (final row in existing) {
      final kind = (row.itemKind ?? '').trim();
      if (kind != 'live_only') continue;
      final iid = row.id?.trim() ?? '';
      if (iid.isEmpty) continue;
      final norm = _normalizeRef(row.refCode ?? '');
      if (!shouldPruneLiveOnlyRef(
        refNorm: norm,
        allowedRefs: allowedRefs,
      )) {
        continue;
      }
      try {
        await LiveItemsTable().delete(
          matchingRows: (q) => q.eqOrNull('id', iid),
        );
        deleted++;
      } catch (_) {}
    }
    return deleted;
  }

  /// true = apagar esta ref live_only (fora da allow-list do prep).
  @visibleForTesting
  static bool shouldPruneLiveOnlyRef({
    required String refNorm,
    required Set<String> allowedRefs,
  }) {
    if (allowedRefs.isEmpty) return false;
    final norm = refNorm.trim();
    if (norm.isEmpty) return false;
    return !allowedRefs.contains(norm);
  }

  /// Limpa prefs de preparação após o directo terminar.
  static Future<void> clearPrepAfterLiveEnd() async {
    await LivePrepRefs.clear();
    await LivePrepRefDetails.clear();
    await LiveCatalogPrepService.clearSelectedProductIds();
  }
}
