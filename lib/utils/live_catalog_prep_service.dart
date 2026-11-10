import 'package:shared_preferences/shared_preferences.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_catalog_sync.dart';
import '/utils/live_prep_ref_details.dart';
import '/utils/live_prep_refs.dart';

/// Catálogo prep no servidor (draft live) — não depende de stock em prefs.
abstract final class LiveCatalogPrepService {
  static const _draftLivePref = 'batata_draft_live_id_v1';
  /// Regressão APP-200: selecção explícita do prep (não todos os ON na BD).
  static const _selectedProductsPref = 'batata_prep_selected_product_ids_v1';

  /// IDs marketplace que o vendedor ligou em Preparar directo (fonte de verdade do sync).
  static Future<Set<String>> readSelectedProductIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_selectedProductsPref);
    if (raw == null || raw.isEmpty) return {};
    return raw.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  static Future<void> writeSelectedProductIds(Set<String> productIds) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = productIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
      ..sort();
    if (ids.isEmpty) {
      await prefs.remove(_selectedProductsPref);
      return;
    }
    await prefs.setStringList(_selectedProductsPref, ids);
  }

  static Future<void> clearSelectedProductIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedProductsPref);
  }

  static Future<String?> ensureDraftLive({String? sellerId}) async {
    final sid = (sellerId ?? currentUserUid).trim();
    if (sid.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_draftLivePref)?.trim();
    if (cached != null && cached.isNotEmpty) {
      if (await LiveCatalogStockService.isDraftLiveForSeller(
        liveId: cached,
        sellerId: sid,
      )) {
        return cached;
      }
      await prefs.remove(_draftLivePref);
    }

    final id = await LiveCatalogStockService.ensureDraftLive(sid);
    if (id != null && id.isNotEmpty) {
      await prefs.setString(_draftLivePref, id);
    }
    return id;
  }

  static Future<void> clearDraftLivePref() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftLivePref);
  }

  /// Remove do prep local refs já usadas no último directo/gravado.
  static Future<void> purgePrepRefsFromLastSession({String? sellerId}) async {
    final sid = (sellerId ?? currentUserUid).trim();
    if (sid.isEmpty) return;
    final liveId = await LiveCatalogStockService.findLatestSessionLiveId(sid);
    if (liveId == null || liveId.isEmpty) return;
    final refs =
        await LiveCatalogStockService.fetchLiveOnlyNormalizedRefs(liveId);
    if (refs.isEmpty) return;
    await LivePrepRefs.purgeNormalizedRefs(refs);
    await LivePrepRefDetails.removeKeys(refs);
  }

  static Future<void> _purgeRefsFromLive(String? liveId) async {
    if (liveId == null || liveId.trim().isEmpty) return;
    final refs =
        await LiveCatalogStockService.fetchLiveOnlyNormalizedRefs(liveId);
    if (refs.isEmpty) return;
    await LivePrepRefs.purgeNormalizedRefs(refs);
    await LivePrepRefDetails.removeKeys(refs);
  }

  static Future<void> onMuxLiveCreated({
    required String newLiveId,
    required String sellerId,
  }) async {
    final draftId = await LiveCatalogStockService.findDraftLiveId(sellerId) ??
        (await SharedPreferences.getInstance()).getString(_draftLivePref);

    if (draftId != null &&
        draftId.isNotEmpty &&
        draftId.trim() != newLiveId.trim()) {
      await LiveCatalogStockService.migrateCatalog(
        fromLiveId: draftId,
        toLiveId: newLiveId,
        sellerId: sellerId,
      );
      await _purgeRefsFromLive(draftId);
    }
    await clearDraftLivePref();
    // Garante FX/marketplace no live canónico mesmo se migrate falhou
    // ou houve 2.º create-mux (Studio usa o live_id mais recente).
    await ensureSelectedProductsOnLive(
      liveId: newLiveId.trim(),
      sellerId: sellerId.trim(),
    );
  }

  /// Re-upsert da allow-list prep → `live_items` deste [liveId].
  static Future<void> ensureSelectedProductsOnLive({
    required String liveId,
    required String sellerId,
  }) async {
    final lid = liveId.trim();
    final sid = sellerId.trim();
    if (lid.isEmpty || sid.isEmpty) return;

    final selected = await readSelectedProductIds();
    for (final pid in selected) {
      try {
        await LiveCatalogStockService.upsertMarketplaceProduct(
          sellerId: sid,
          productId: pid,
          liveId: lid,
        );
      } catch (_) {}
    }
    await LiveCatalogSync.enforcePrepAllowList(
      liveId: lid,
      sellerId: sid,
    );
  }

  static Future<void> setProductInCatalog({
    required String productId,
    required bool inCatalog,
    String? sellerId,
  }) async {
    final sid = (sellerId ?? currentUserUid).trim();
    if (sid.isEmpty || productId.trim().isEmpty) return;

    if (inCatalog) {
      await ensureDraftLive(sellerId: sid);
      await LiveCatalogStockService.upsertMarketplaceProduct(
        sellerId: sid,
        productId: productId,
      );
      final selected = await readSelectedProductIds();
      selected.add(productId.trim());
      await writeSelectedProductIds(selected);
    } else {
      await LiveCatalogStockService.removeMarketplaceProduct(
        sellerId: sid,
        productId: productId,
      );
      final selected = await readSelectedProductIds();
      selected.remove(productId.trim());
      await writeSelectedProductIds(selected);
    }
  }

  /// Alinha o draft ao que o vendedor ligou em Preparar (lista visível).
  /// Evita migrar dezenas de V0 antigos ainda `available_for_live=true`.
  static Future<void> reconcileDraftToSelectedProducts({
    required Iterable<String> selectedProductIds,
    String? sellerId,
  }) async {
    final sid = (sellerId ?? currentUserUid).trim();
    if (sid.isEmpty) return;

    final draftId = await ensureDraftLive(sellerId: sid);
    if (draftId == null || draftId.isEmpty) return;

    final want = selectedProductIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    final existing = await LiveItemsTable().queryRows(
      queryFn: (q) => q.eqOrNull('live_id', draftId),
      limit: 500,
    );

    for (final row in existing) {
      final pid = row.productId?.trim() ?? '';
      if (pid.isEmpty) continue;
      if (want.contains(pid)) continue;
      try {
        await LiveCatalogStockService.removeMarketplaceProduct(
          sellerId: sid,
          productId: pid,
          liveId: draftId,
        );
      } catch (_) {}
    }

    for (final pid in want) {
      try {
        await LiveCatalogStockService.upsertMarketplaceProduct(
          sellerId: sid,
          productId: pid,
          liveId: draftId,
        );
      } catch (_) {}
    }

    await writeSelectedProductIds(want);
  }
}
