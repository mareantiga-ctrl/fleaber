import 'package:shared_preferences/shared_preferences.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/utils/live_catalog_stock_service.dart';
import '/utils/live_prep_ref_details.dart';
import '/utils/live_prep_refs.dart';

/// Catálogo prep no servidor (draft live) — não depende de stock em prefs.
abstract final class LiveCatalogPrepService {
  static const _draftLivePref = 'batata_draft_live_id_v1';

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
    } else {
      await LiveCatalogStockService.removeMarketplaceProduct(
        sellerId: sid,
        productId: productId,
      );
    }
  }
}
