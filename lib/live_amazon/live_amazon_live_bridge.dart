import 'package:flutter/foundation.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/live_amazon/live_amazon_models.dart';
import '/utils/live_catalog_stock_service.dart';

/// Liga um artigo Amazon preparado à montra do directo (sem republicar Amazon).
class LiveAmazonLiveBridge {
  LiveAmazonLiveBridge._();
  static final instance = LiveAmazonLiveBridge._();

  /// Evita duplicar o mesmo produto/LPN na mesma live.
  Future<String?> addToVitrine({
    required String liveId,
    required String sellerId,
    required LiveAmazonPresentItem item,
  }) async {
    final lid = liveId.trim();
    final sid = sellerId.trim();
    if (lid.isEmpty || sid.isEmpty) {
      throw StateError('live_or_seller_missing');
    }
    if (!item.isSellableNow && (item.fleaberProductId ?? '').isEmpty) {
      // Sem stock Fleaber e sem produto: não inventar venda.
      throw StateError('not_sellable_no_fleaber_stock');
    }

    // Já na montra? Reutilizar live_item (anti-duplicado por leitura repetida).
    final existingId = await _findExistingLiveItem(
      liveId: lid,
      fleaberProductId: item.fleaberProductId,
      asin: item.asin,
      lpn: item.lpn,
    );
    if (existingId != null) return existingId;

    final fleaberId = (item.fleaberProductId ?? '').trim();
    if (fleaberId.isNotEmpty) {
      // Respeita stock do produto marketplace; RPC existente impede oversell.
      final id = await LiveCatalogStockService.upsertMarketplaceProduct(
        sellerId: sid,
        productId: fleaberId,
        liveId: lid,
      );
      return id;
    }

    // Artigo só no catálogo Amazon privado → live-only com ref AMZ-ASIN.
    final ref = item.lpn?.isNotEmpty == true
        ? 'LPN-${item.lpn}'
        : 'AMZ-${item.asin}';
    final qty = item.availableQty > 0 ? item.availableQty : item.unitCount;
    if (qty <= 0) throw StateError('zero_qty');
    final res = await LiveCatalogStockService.upsertLiveOnlyItem(
      sellerId: sid,
      liveId: lid,
      refCode: ref,
      title: item.titlePt,
      price: item.fleaberPriceEur,
      quantity: qty,
      photoUrl: item.imageUrl,
      lineageMode: 'new',
    );
    return res?.liveItemId;
  }

  Future<void> setActiveLiveItem({
    required String liveId,
    required String liveItemId,
  }) async {
    final lid = liveId.trim();
    final id = liveItemId.trim();
    if (lid.isEmpty || id.isEmpty) return;
    await SupaFlow.client
        .from('live_items')
        .update({'is_active': false}).eq('live_id', lid);
    await SupaFlow.client
        .from('live_items')
        .update({'is_active': true}).eq('id', id);
    try {
      await SupaFlow.client.from('live_item_show_events').insert({
        'live_id': lid,
        'live_item_id': id,
        'shown_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[LiveAmazonLiveBridge] show_event: $e');
    }
  }

  Future<String?> _findExistingLiveItem({
    required String liveId,
    String? fleaberProductId,
    required String asin,
    String? lpn,
  }) async {
    final pid = (fleaberProductId ?? '').trim();
    if (pid.isNotEmpty) {
      final rows = await SupaFlow.client
          .from('live_items')
          .select('id')
          .eq('live_id', liveId)
          .eq('product_id', pid)
          .limit(1);
      if ((rows as List).isNotEmpty) return rows.first['id']?.toString();
    }
    final refCandidates = <String>[
      if ((lpn ?? '').trim().isNotEmpty) 'LPN-${lpn!.trim()}',
      if (asin.trim().isNotEmpty) 'AMZ-${asin.trim()}',
    ];
    for (final ref in refCandidates) {
      final rows = await SupaFlow.client
          .from('live_items')
          .select('id')
          .eq('live_id', liveId)
          .eq('ref_code', ref)
          .limit(1);
      if ((rows as List).isNotEmpty) return rows.first['id']?.toString();
    }
    return null;
  }

  String get currentSellerId => currentUserUid;
}
