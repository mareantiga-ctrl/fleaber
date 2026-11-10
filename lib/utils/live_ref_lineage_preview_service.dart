import 'dart:convert';

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
    this.displayQuantity,
    this.lastUsedAt,
    required this.lastOrigin,
    required this.openReservationCount,
    required this.openReservedUnits,
    required this.completedPurchaseCount,
    required this.completedUnits,
    this.availableQuantity,
    this.historyStatus = 'active',
    this.liveCount = 0,
    this.salesValueEur = 0,
    this.canContinue = true,
  });

  final String logicalItemId;
  final String displayTitle;
  final String? displayPhotoUrl;
  final double? displayPrice;
  final int? displayQuantity;
  final int? availableQuantity;
  final DateTime? lastUsedAt;
  final String lastOrigin;
  final int openReservationCount;
  final int openReservedUnits;
  final int completedPurchaseCount;
  final int completedUnits;
  final String historyStatus;
  final int liveCount;
  final double salesValueEur;
  final bool canContinue;

  bool get hasOpen => openReservationCount > 0;
  bool get isActive => historyStatus == 'active';

  bool get showContinueButton => historyStatus == 'active' && canContinue;

  LiveRefLineageEntry asClosed() => LiveRefLineageEntry(
        logicalItemId: logicalItemId,
        displayTitle: displayTitle,
        displayPhotoUrl: displayPhotoUrl,
        displayPrice: displayPrice,
        displayQuantity: displayQuantity,
        availableQuantity: availableQuantity,
        lastUsedAt: lastUsedAt,
        lastOrigin: lastOrigin,
        openReservationCount: openReservationCount,
        openReservedUnits: openReservedUnits,
        completedPurchaseCount: completedPurchaseCount,
        completedUnits: completedUnits,
        historyStatus: 'closed',
        liveCount: liveCount,
        salesValueEur: salesValueEur,
        canContinue: false,
      );

  String badgeLabel() {
    if (!isActive) return 'Histórico encerrado';
    final parts = <String>[];
    if (completedUnits > 0) {
      parts.add('🟢 $completedUnits vendas globais');
    }
    if (openReservationCount > 0) {
      final units = openReservedUnits > 0 ? ' · $openReservedUnits un.' : '';
      parts.add('🟠 $openReservationCount reservas abertas$units');
    }
    if (parts.isNotEmpty) return parts.join(' · ');
    if (lastUsedAt != null) {
      return 'Última utilização: $lastOrigin';
    }
    return '';
  }

  factory LiveRefLineageEntry.fromJson(Map<String, dynamic> json) {
    return LiveRefLineageEntry(
      logicalItemId: json['logical_item_id']?.toString() ??
          json['history_id']?.toString() ??
          '',
      displayTitle: (json['display_title']?.toString() ?? 'Artigo').trim(),
      displayPhotoUrl: json['display_photo_url']?.toString(),
      displayPrice: _asDouble(json['display_price']),
      displayQuantity: _asIntOpt(json['display_quantity']),
      availableQuantity: _asIntOpt(json['available_quantity']),
      lastUsedAt: _parseDate(json['last_used_at']),
      lastOrigin: (json['last_origin']?.toString() ?? '').trim(),
      openReservationCount: _asInt(json['open_reservation_count']),
      openReservedUnits: _asInt(json['open_reserved_units']),
      completedPurchaseCount: _asInt(json['completed_purchase_count']),
      completedUnits: _asInt(json['completed_units']),
      historyStatus: json['history_status']?.toString() ?? 'active',
      liveCount: _asInt(json['live_count']),
      salesValueEur: _asDouble(json['sales_value_eur']) ?? 0,
      canContinue: json['can_continue'] == true &&
          (json['history_status']?.toString() ?? 'active') == 'active',
    );
  }
}

class LiveRefLineagePreviewReport {
  const LiveRefLineagePreviewReport({
    required this.isOk,
    this.error,
    required this.refCode,
    required this.refNormalized,
    required this.usageWindowMonths,
    required this.hasRelevantHistory,
    required this.shouldShowSheet,
    required this.summary,
    required this.lineages,
    required this.draft,
  });

  final bool isOk;
  final String? error;
  final String refCode;
  final String refNormalized;
  final int usageWindowMonths;
  final bool hasRelevantHistory;
  final bool shouldShowSheet;
  final LiveRefLineageSummary summary;
  final List<LiveRefLineageEntry> lineages;
  final LiveRefLineageDraftState draft;

  /// Espelha SQL: `needs_lineage_decision` + fallback client-side.
  bool get needsSheetForDraft => shouldPromptLineageDecision;

  /// Sheet quando há histórico relevante e o draft ainda não tem linhagem.
  List<LiveRefLineageEntry> get continuableLineages =>
      lineages.where((e) => e.canContinue && e.isActive).toList();

  bool get shouldPromptLineageDecision {
    if (!isOk) return false;
    final existing = draft.logicalItemId?.trim() ?? '';
    if (existing.isNotEmpty) return false;
    return shouldShowSheet && lineages.isNotEmpty;
  }

  factory LiveRefLineagePreviewReport.fromRpc(dynamic raw) {
    if (raw is! Map) {
      return const LiveRefLineagePreviewReport(
        isOk: false,
        error: 'invalid_response',
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
    if (!_asBool(map['ok'])) {
      return LiveRefLineagePreviewReport(
        isOk: false,
        error: map['error']?.toString(),
        refCode: '',
        refNormalized: '',
        usageWindowMonths: 12,
        hasRelevantHistory: false,
        shouldShowSheet: false,
        summary: const LiveRefLineageSummary(
          lineageCount: 0,
          openReservationCount: 0,
          openReservedUnits: 0,
          completedPurchaseCount: 0,
          completedUnits: 0,
        ),
        lineages: const [],
        draft: const LiveRefLineageDraftState(needsLineageDecision: false),
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
      isOk: true,
      refCode: map['ref_code']?.toString() ?? '',
      refNormalized: map['ref_normalized']?.toString() ?? '',
      usageWindowMonths: _asInt(map['usage_window_months'], 12),
      hasRelevantHistory: _asBool(map['has_relevant_history']),
      shouldShowSheet: _asBool(map['should_show_sheet']),
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

int? _asIntOpt(dynamic v) {
  if (v == null) return null;
  return _asInt(v);
}

bool computeShouldShowSheetFromLineages(
  List<LiveRefLineageEntry> lineages, {
  DateTime? now,
  int usageWindowMonths = 12,
}) {
  for (final e in lineages.where((x) => x.canContinue && x.isActive)) {
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

/// Parse robusto do array `lineages` (List, Map único, ou JSON string).
List<LiveRefLineageEntry> parseLineagesFromRpc(dynamic raw) {
  dynamic value = raw;
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const [];
    try {
      value = jsonDecode(trimmed);
    } catch (_) {
      return const [];
    }
  }

  if (value is Map) {
    return [
      LiveRefLineageEntry.fromJson(Map<String, dynamic>.from(value)),
    ];
  }

  if (value is! List) return const [];

  final out = <LiveRefLineageEntry>[];
  for (final row in value) {
    if (row is Map) {
      out.add(LiveRefLineageEntry.fromJson(Map<String, dynamic>.from(row)));
    }
  }
  return out;
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

bool _asBool(dynamic v) => v == true || v == 1 || '$v'.toLowerCase() == 'true';

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
