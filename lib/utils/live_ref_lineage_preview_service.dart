import 'package:flutter/foundation.dart';

import '/backend/supabase/supabase.dart';

/// Resultado do upsert live_only (RPC jsonb).
class LiveOnlyUpsertResult {
  const LiveOnlyUpsertResult({
    required this.liveItemId,
    this.logicalItemId,
    required this.lineageMode,
  });

  final String liveItemId;
  final String? logicalItemId;
  final String lineageMode;

  factory LiveOnlyUpsertResult.fromRpc(dynamic raw) {
    if (raw is! Map) return const LiveOnlyUpsertResult(liveItemId: '', lineageMode: '');
    final map = Map<String, dynamic>.from(raw);
    if (map['ok'] != true) return const LiveOnlyUpsertResult(liveItemId: '', lineageMode: '');
    return LiveOnlyUpsertResult(
      liveItemId: map['live_item_id']?.toString() ?? '',
      logicalItemId: map['logical_item_id']?.toString(),
      lineageMode: map['lineage_mode']?.toString() ?? '',
    );
  }
}

class LiveRefLineageSummary {
  const LiveRefLineageSummary({
    required this.lineageCount,
    required this.openReservationCount,
    required this.openReservedUnits,
    required this.completedPurchaseCount,
    required this.completedUnits,
  });

  final int lineageCount;
  final int openReservationCount;
  final int openReservedUnits;
  final int completedPurchaseCount;
  final int completedUnits;

  factory LiveRefLineageSummary.fromJson(Map<String, dynamic> json) {
    return LiveRefLineageSummary(
      lineageCount: _asInt(json['lineage_count']),
      openReservationCount: _asInt(json['open_reservation_count']),
      openReservedUnits: _asInt(json['open_reserved_units']),
      completedPurchaseCount: _asInt(json['completed_purchase_count']),
      completedUnits: _asInt(json['completed_units']),
    );
  }
}

class LiveRefLineageDraftState {
  const LiveRefLineageDraftState({
    this.liveItemId,
    this.logicalItemId,
    required this.needsLineageDecision,
  });

  final String? liveItemId;
  final String? logicalItemId;
  final bool needsLineageDecision;

  factory LiveRefLineageDraftState.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const LiveRefLineageDraftState(needsLineageDecision: false);
    }
    return LiveRefLineageDraftState(
      liveItemId: json['live_item_id']?.toString(),
      logicalItemId: json['logical_item_id']?.toString(),
      needsLineageDecision: json['needs_lineage_decision'] == true,
    );
  }
}

class LiveRefLineageEntry {
  const LiveRefLineageEntry({
    required this.logicalItemId,
    required this.displayTitle,
    this.displayPhotoUrl,
    this.displayPrice,
    this.lastUsedAt,
    required this.lastOrigin,
    required this.openReservationCount,
    required this.openReservedUnits,
    required this.completedPurchaseCount,
    required this.completedUnits,
  });

  final String logicalItemId;
  final String displayTitle;
  final String? displayPhotoUrl;
  final double? displayPrice;
  final DateTime? lastUsedAt;
  final String lastOrigin;
  final int openReservationCount;
  final int openReservedUnits;
  final int completedPurchaseCount;
  final int completedUnits;

  bool get hasOpen => openReservationCount > 0;

  String badgeLabel() {
    if (openReservationCount > 0) {
      final units = openReservedUnits > 0 ? ' · $openReservedUnits un.' : '';
      return '🟠 $openReservationCount reservas abertas$units';
    }
    if (completedPurchaseCount > 0) {
      return '🟢 $completedPurchaseCount vendas concluídas';
    }
    if (lastUsedAt != null) {
      return 'Última utilização: $lastOrigin';
    }
    return '';
  }

  factory LiveRefLineageEntry.fromJson(Map<String, dynamic> json) {
    return LiveRefLineageEntry(
      logicalItemId: json['logical_item_id']?.toString() ?? '',
      displayTitle: (json['display_title']?.toString() ?? 'Artigo').trim(),
      displayPhotoUrl: json['display_photo_url']?.toString(),
      displayPrice: _asDouble(json['display_price']),
      lastUsedAt: _parseDate(json['last_used_at']),
      lastOrigin: (json['last_origin']?.toString() ?? '').trim(),
      openReservationCount: _asInt(json['open_reservation_count']),
      openReservedUnits: _asInt(json['open_reserved_units']),
      completedPurchaseCount: _asInt(json['completed_purchase_count']),
      completedUnits: _asInt(json['completed_units']),
    );
  }
}

class LiveRefLineagePreviewReport {
  const LiveRefLineagePreviewReport({
    required this.refCode,
    required this.refNormalized,
    required this.usageWindowMonths,
    required this.hasRelevantHistory,
    required this.shouldShowSheet,
    required this.summary,
    required this.lineages,
    required this.draft,
  });

  final String refCode;
  final String refNormalized;
  final int usageWindowMonths;
  final bool hasRelevantHistory;
  final bool shouldShowSheet;
  final LiveRefLineageSummary summary;
  final List<LiveRefLineageEntry> lineages;
  final LiveRefLineageDraftState draft;

  bool get needsSheetForDraft => draft.needsLineageDecision;

  factory LiveRefLineagePreviewReport.fromRpc(dynamic raw) {
    if (raw is! Map) {
      return const LiveRefLineagePreviewReport(
        refCode: '',
        refNormalized: '',
        usageWindowMonths: 12,
        hasRelevantHistory: false,
        shouldShowSheet: false,
        summary: LiveRefLineageSummary(
          lineageCount: 0,
          openReservationCount: 0,
          openReservedUnits: 0,
          completedPurchaseCount: 0,
          completedUnits: 0,
        ),
        lineages: [],
        draft: LiveRefLineageDraftState(needsLineageDecision: false),
      );
    }
    final map = Map<String, dynamic>.from(raw);
    if (map['ok'] != true) {
      return const LiveRefLineagePreviewReport(
        refCode: '',
        refNormalized: '',
        usageWindowMonths: 12,
        hasRelevantHistory: false,
        shouldShowSheet: false,
        summary: LiveRefLineageSummary(
          lineageCount: 0,
          openReservationCount: 0,
          openReservedUnits: 0,
          completedPurchaseCount: 0,
          completedUnits: 0,
        ),
        lineages: [],
        draft: LiveRefLineageDraftState(needsLineageDecision: false),
      );
    }

    final summaryRaw = map['summary'];
    final lineagesRaw = map['lineages'];
    final draftRaw = map['draft'];

    final lineages = <LiveRefLineageEntry>[];
    if (lineagesRaw is List) {
      for (final row in lineagesRaw) {
        if (row is Map) {
          lineages.add(
            LiveRefLineageEntry.fromJson(Map<String, dynamic>.from(row)),
          );
        }
      }
    }

    return LiveRefLineagePreviewReport(
      refCode: map['ref_code']?.toString() ?? '',
      refNormalized: map['ref_normalized']?.toString() ?? '',
      usageWindowMonths: _asInt(map['usage_window_months'], 12),
      hasRelevantHistory: map['has_relevant_history'] == true,
      shouldShowSheet: map['should_show_sheet'] == true,
      summary: summaryRaw is Map
          ? LiveRefLineageSummary.fromJson(
              Map<String, dynamic>.from(summaryRaw),
            )
          : const LiveRefLineageSummary(
              lineageCount: 0,
              openReservationCount: 0,
              openReservedUnits: 0,
              completedPurchaseCount: 0,
              completedUnits: 0,
            ),
      lineages: lineages,
      draft: draftRaw is Map
          ? LiveRefLineageDraftState.fromJson(
              Map<String, dynamic>.from(draftRaw),
            )
          : const LiveRefLineageDraftState(needsLineageDecision: false),
    );
  }
}

/// L1/L2/L3 — espelha critério SQL (testável).
bool lineageEntryHasRelevantHistory({
  required int openReservationCount,
  required int completedPurchaseCount,
  DateTime? lastUsedAt,
  DateTime? now,
  int usageWindowMonths = 12,
}) {
  if (openReservationCount > 0) return true;
  if (completedPurchaseCount > 0) return true;
  if (lastUsedAt == null) return false;
  final anchor = now ?? DateTime.now().toUtc();
  final cutoff = anchor.subtract(Duration(days: usageWindowMonths * 30));
  return !lastUsedAt.isBefore(cutoff);
}

bool computeShouldShowSheetFromLineages(
  List<LiveRefLineageEntry> lineages, {
  DateTime? now,
  int usageWindowMonths = 12,
}) {
  for (final e in lineages) {
    if (lineageEntryHasRelevantHistory(
      openReservationCount: e.openReservationCount,
      completedPurchaseCount: e.completedPurchaseCount,
      lastUsedAt: e.lastUsedAt,
      now: now,
      usageWindowMonths: usageWindowMonths,
    )) {
      return true;
    }
  }
  return false;
}

abstract final class LiveRefLineagePreviewService {
  static Future<LiveRefLineagePreviewReport?> fetch({
    required String sellerId,
    required String refCode,
    String? liveId,
  }) async {
    final sid = sellerId.trim();
    final ref = refCode.trim();
    if (sid.isEmpty || ref.isEmpty) return null;
    try {
      final res = await SupaFlow.client.rpc(
        'batata_live_ref_open_reservations_preview',
        params: {
          'p_seller_id': sid,
          'p_ref_code': ref,
          if (liveId != null && liveId.trim().isNotEmpty)
            'p_live_id': liveId.trim(),
        },
      );
      return LiveRefLineagePreviewReport.fromRpc(res);
    } catch (e) {
      debugPrint('[LiveRefLineagePreview] fetch failed: $e');
      return null;
    }
  }
}

int _asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? fallback;
}

double? _asDouble(dynamic v) {
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
