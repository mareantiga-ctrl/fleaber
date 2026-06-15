import 'dart:convert';

import 'package:flutter/foundation.dart';

import '/backend/supabase/supabase.dart';
import '/utils/live_prep_ref_details.dart';

class RefHistoryListEntry {
  const RefHistoryListEntry({
    required this.historyId,
    required this.refCode,
    required this.refNormalized,
    required this.displayTitle,
    this.displayPhotoUrl,
    required this.historyStatus,
    required this.liveCount,
    required this.openReservationCount,
    required this.completedPurchaseCount,
    required this.salesValueEur,
    this.lastUsedAt,
  });

  final String historyId;
  final String refCode;
  final String refNormalized;
  final String displayTitle;
  final String? displayPhotoUrl;
  final String historyStatus;
  final int liveCount;
  final int openReservationCount;
  final int completedPurchaseCount;
  final double salesValueEur;
  final DateTime? lastUsedAt;

  bool get isActive => historyStatus == 'active';
  bool get isClosed => historyStatus == 'closed';
  bool get isMerged => historyStatus == 'merged';

  factory RefHistoryListEntry.fromJson(Map<String, dynamic> json) {
    return RefHistoryListEntry(
      historyId: json['history_id']?.toString() ?? '',
      refCode: json['ref_code']?.toString() ?? '',
      refNormalized: json['ref_normalized']?.toString() ?? '',
      displayTitle: (json['display_title']?.toString() ?? '').trim(),
      displayPhotoUrl: json['display_photo_url']?.toString(),
      historyStatus: json['history_status']?.toString() ?? 'active',
      liveCount: _asInt(json['live_count']),
      openReservationCount: _asInt(json['open_reservation_count']),
      completedPurchaseCount: _asInt(json['completed_purchase_count']),
      salesValueEur: _asDouble(json['sales_value_eur']),
      lastUsedAt: _parseDate(json['last_used_at']),
    );
  }
}

class RefHistoryDetail {
  const RefHistoryDetail({
    required this.historyId,
    required this.refCode,
    required this.displayTitle,
    this.displayPhotoUrl,
    this.displayPrice,
    this.displayQuantity,
    required this.historyStatus,
    required this.liveCount,
    required this.openReservationCount,
    required this.completedPurchaseCount,
    required this.salesValueEur,
    required this.canClose,
    required this.canMerge,
    required this.reservationsOpen,
    required this.purchasesCompleted,
    required this.livesUsed,
  });

  final String historyId;
  final String refCode;
  final String displayTitle;
  final String? displayPhotoUrl;
  final double? displayPrice;
  final int? displayQuantity;
  final String historyStatus;
  final int liveCount;
  final int openReservationCount;
  final int completedPurchaseCount;
  final double salesValueEur;
  final bool canClose;
  final bool canMerge;
  final List<Map<String, dynamic>> reservationsOpen;
  final List<Map<String, dynamic>> purchasesCompleted;
  final List<Map<String, dynamic>> livesUsed;

  factory RefHistoryDetail.fromRpc(dynamic raw) {
    if (raw is! Map || raw['ok'] != true) {
      return const RefHistoryDetail(
        historyId: '',
        refCode: '',
        displayTitle: '',
        historyStatus: 'active',
        liveCount: 0,
        openReservationCount: 0,
        completedPurchaseCount: 0,
        salesValueEur: 0,
        canClose: false,
        canMerge: false,
        reservationsOpen: [],
        purchasesCompleted: [],
        livesUsed: [],
      );
    }
    final h = Map<String, dynamic>.from(raw['history'] as Map? ?? {});
    return RefHistoryDetail(
      historyId: h['history_id']?.toString() ?? h['logical_item_id']?.toString() ?? '',
      refCode: h['ref_code']?.toString() ?? '',
      displayTitle: (h['display_title']?.toString() ?? '').trim(),
      displayPhotoUrl: h['display_photo_url']?.toString(),
      displayPrice: _asDoubleOpt(h['display_price']),
      displayQuantity: _asIntOpt(h['display_quantity']),
      historyStatus: h['history_status']?.toString() ?? 'active',
      liveCount: _asInt(h['live_count']),
      openReservationCount: _asInt(h['open_reservation_count']),
      completedPurchaseCount: _asInt(h['completed_purchase_count']),
      salesValueEur: _asDouble(h['sales_value_eur']),
      canClose: h['can_close'] == true,
      canMerge: h['can_merge'] == true,
      reservationsOpen: _asMapList(h['reservations_open']),
      purchasesCompleted: _asMapList(h['purchases_completed']),
      livesUsed: _asMapList(h['lives_used']),
    );
  }
}

class RefHistoryClosePreview {
  const RefHistoryClosePreview({
    required this.ok,
    this.error,
    required this.willCancelTotal,
    required this.pendingRequests,
    required this.acceptedRequests,
    required this.unpaidOrders,
  });

  final bool ok;
  final String? error;
  final int willCancelTotal;
  final int pendingRequests;
  final int acceptedRequests;
  final int unpaidOrders;

  factory RefHistoryClosePreview.fromRpc(dynamic raw) {
    if (raw is! Map) {
      return const RefHistoryClosePreview(ok: false, willCancelTotal: 0, pendingRequests: 0, acceptedRequests: 0, unpaidOrders: 0);
    }
    return RefHistoryClosePreview(
      ok: raw['ok'] == true,
      error: raw['error']?.toString(),
      willCancelTotal: _asInt(raw['will_cancel_total']),
      pendingRequests: _asInt(raw['pending_requests']),
      acceptedRequests: _asInt(raw['accepted_requests']),
      unpaidOrders: _asInt(raw['unpaid_orders']),
    );
  }
}

class RefHistoryMergePreview {
  const RefHistoryMergePreview({
    required this.ok,
    this.error,
    required this.refCode,
    required this.itemsToRepoint,
  });

  final bool ok;
  final String? error;
  final String refCode;
  final int itemsToRepoint;

  factory RefHistoryMergePreview.fromRpc(dynamic raw) {
    if (raw is! Map) {
      return const RefHistoryMergePreview(ok: false, refCode: '', itemsToRepoint: 0);
    }
    return RefHistoryMergePreview(
      ok: raw['ok'] == true,
      error: raw['error']?.toString(),
      refCode: raw['ref_code']?.toString() ?? '',
      itemsToRepoint: _asInt(raw['items_to_repoint']),
    );
  }
}

class RefHistoryListResult {
  const RefHistoryListResult({
    required this.items,
    this.error,
    this.total = 0,
  });

  final List<RefHistoryListEntry> items;
  final String? error;
  final int total;
}

abstract final class RefHistoryService {
  static Future<RefHistoryListResult> listWithMeta({
    required String sellerId,
    String filter = 'all',
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final res = await SupaFlow.client.rpc(
        'batata_ref_histories_list',
        params: {
          'p_seller_id': sellerId.trim(),
          'p_filter': filter.trim(),
          if (search != null && search.trim().isNotEmpty)
            'p_search': search.trim(),
          'p_limit': limit,
          'p_offset': offset,
        },
      );
      if (res is! Map) {
        return const RefHistoryListResult(items: [], error: 'invalid_response');
      }
      if (res['ok'] != true) {
        return RefHistoryListResult(
          items: const [],
          error: res['error']?.toString() ?? 'list_failed',
        );
      }
      dynamic rows = res['histories'];
      if (rows is String) {
        try {
          rows = jsonDecode(rows);
        } catch (_) {
          rows = null;
        }
      }
      if (rows is! List) {
        return const RefHistoryListResult(items: [], error: 'invalid_histories');
      }
      final items = rows
          .whereType<Map>()
          .map((r) => RefHistoryListEntry.fromJson(Map<String, dynamic>.from(r)))
          .where((e) => e.historyId.isNotEmpty)
          .toList();
      return RefHistoryListResult(
        items: items,
        total: _asInt(res['total']),
      );
    } catch (e) {
      debugPrint('[RefHistoryService] list: $e');
      return RefHistoryListResult(items: const [], error: '$e');
    }
  }

  /// Fallback quando o RPC da lista falha ou devolve vazio (H6).
  static Future<List<RefHistoryListEntry>> listFallbackFromLiveItems(
    String sellerId,
  ) async {
    final sid = sellerId.trim();
    if (sid.isEmpty) return const [];
    try {
      final lives = await LivesTable().queryRows(
        queryFn: (q) => q.or('seller_id.eq.$sid,vendedor_id.eq.$sid'),
        limit: 500,
      );
      if (lives.isEmpty) return const [];
      final liveIds = lives
          .map((l) => l.id?.trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      if (liveIds.isEmpty) return const [];

      final items = await LiveItemsTable().queryRows(
        queryFn: (q) => q
            .inFilter('live_id', liveIds)
            .eq('item_kind', 'live_only')
            .order('updated_at', ascending: false),
        limit: 2000,
      );

      final grouped = <String, List<LiveItemsRow>>{};
      for (final item in items) {
        final logicalRaw = item.data['logical_item_id']?.toString().trim();
        final hid = logicalRaw != null && logicalRaw.isNotEmpty
            ? logicalRaw
            : (item.id?.trim() ?? '');
        if (hid.isEmpty) continue;
        grouped.putIfAbsent(hid, () => []).add(item);
      }

      return grouped.entries.map((e) {
        final head = e.value.first;
        return RefHistoryListEntry(
          historyId: e.key,
          refCode: head.refCode?.trim() ?? '',
          refNormalized: LivePrepRefDetails.normalizeRefKey(head.refCode ?? ''),
          displayTitle: head.title?.trim() ?? '',
          displayPhotoUrl: head.photoUrl,
          historyStatus: 'active',
          liveCount: e.value.map((i) => i.liveId).toSet().length,
          openReservationCount: 0,
          completedPurchaseCount: 0,
          salesValueEur: 0,
          lastUsedAt: head.updatedAt,
        );
      }).toList()
        ..sort((a, b) {
          final at = a.lastUsedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.lastUsedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });
    } catch (e) {
      debugPrint('[RefHistoryService] listFallback: $e');
      return const [];
    }
  }

  static Future<List<RefHistoryListEntry>> list({
    required String sellerId,
    String filter = 'all',
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final r = await listWithMeta(
      sellerId: sellerId,
      filter: filter,
      search: search,
      limit: limit,
      offset: offset,
    );
    return r.items;
  }

  static Future<RefHistoryDetail?> detail({
    required String sellerId,
    required String historyId,
  }) async {
    try {
      final res = await SupaFlow.client.rpc(
        'batata_ref_history_detail',
        params: {
          'p_seller_id': sellerId.trim(),
          'p_history_id': historyId.trim(),
        },
      );
      final parsed = RefHistoryDetail.fromRpc(res);
      if (parsed.historyId.isEmpty) return null;
      return parsed;
    } catch (e) {
      debugPrint('[RefHistoryService] detail: $e');
      return null;
    }
  }

  static Future<RefHistoryClosePreview> closePreview({
    required String sellerId,
    required String historyId,
  }) async {
    try {
      final res = await SupaFlow.client.rpc(
        'batata_ref_history_close_preview',
        params: {
          'p_seller_id': sellerId.trim(),
          'p_history_id': historyId.trim(),
        },
      );
      return RefHistoryClosePreview.fromRpc(res);
    } catch (e) {
      debugPrint('[RefHistoryService] closePreview: $e');
      return const RefHistoryClosePreview(ok: false, willCancelTotal: 0, pendingRequests: 0, acceptedRequests: 0, unpaidOrders: 0);
    }
  }

  static Future<({bool ok, String? error})> closeWithMeta({
    required String sellerId,
    required String historyId,
    String? reason,
  }) async {
    try {
      final res = await SupaFlow.client.rpc(
        'batata_ref_history_close',
        params: {
          'p_seller_id': sellerId.trim(),
          'p_history_id': historyId.trim(),
          if (reason != null && reason.trim().isNotEmpty) 'p_reason': reason.trim(),
        },
      );
      if (res is Map && res['ok'] == true) return (ok: true, error: null);
      if (res is Map) return (ok: false, error: res['error']?.toString());
      return (ok: false, error: 'invalid_response');
    } catch (e) {
      debugPrint('[RefHistoryService] close: $e');
      return (ok: false, error: '$e');
    }
  }

  static Future<bool> close({
    required String sellerId,
    required String historyId,
    String? reason,
  }) async {
    final r = await closeWithMeta(
      sellerId: sellerId,
      historyId: historyId,
      reason: reason,
    );
    return r.ok;
  }

  static Future<RefHistoryMergePreview> mergePreview({
    required String sellerId,
    required String targetHistoryId,
    required String sourceHistoryId,
  }) async {
    try {
      final res = await SupaFlow.client.rpc(
        'batata_ref_histories_merge_preview',
        params: {
          'p_seller_id': sellerId.trim(),
          'p_target_history_id': targetHistoryId.trim(),
          'p_source_history_id': sourceHistoryId.trim(),
        },
      );
      return RefHistoryMergePreview.fromRpc(res);
    } catch (e) {
      debugPrint('[RefHistoryService] mergePreview: $e');
      return const RefHistoryMergePreview(ok: false, refCode: '', itemsToRepoint: 0);
    }
  }

  static Future<bool> merge({
    required String sellerId,
    required String targetHistoryId,
    required String sourceHistoryId,
    String? reason,
  }) async {
    try {
      final res = await SupaFlow.client.rpc(
        'batata_ref_histories_merge',
        params: {
          'p_seller_id': sellerId.trim(),
          'p_target_history_id': targetHistoryId.trim(),
          'p_source_history_id': sourceHistoryId.trim(),
          if (reason != null && reason.trim().isNotEmpty) 'p_reason': reason.trim(),
        },
      );
      return res is Map && res['ok'] == true;
    } catch (e) {
      debugPrint('[RefHistoryService] merge: $e');
      return false;
    }
  }
}

int _asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? fallback;
}

int? _asIntOpt(dynamic v) {
  if (v == null) return null;
  return _asInt(v);
}

double _asDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? fallback;
}

double? _asDoubleOpt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toUtc();
}

List<Map<String, dynamic>> _asMapList(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();
}
