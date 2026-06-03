import 'package:flutter/foundation.dart';

import '/backend/supabase/supabase.dart';

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
    this.liveStatus,
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
  final String? liveStatus;

  bool get isMarketplaceProduct => itemKind == 'marketplace_product';

  bool get isLiveOnly => itemKind == 'live_only';

  /// ID para checkout Stripe (TYPE A = product_id; TYPE B = checkout shadow).
  String? get checkoutProductIdOrPrimary =>
      isMarketplaceProduct ? productId : (checkoutProductId ?? productId);

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
      liveStatus: m['live_status']?.toString(),
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
    final out = <String, LiveCatalogStockSnapshot>{};
    for (final id in liveItemIds) {
      final snap = await fetch(id);
      if (snap != null) out[id.trim()] = snap;
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

  static Future<String?> upsertLiveOnlyItem({
    required String sellerId,
    required String refCode,
    String? title,
    double? price,
    int? quantity,
    String? clothingSize,
    String? gender,
    String? photoUrl,
    String? liveId,
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
        },
      );
      return res?.toString();
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
}
