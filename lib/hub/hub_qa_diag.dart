import 'dart:async';

import 'package:flutter/foundation.dart';

import '/backend/supabase/supabase.dart';
import '/utils/fleaber_logger.dart';

import 'hub_live_reservation_ui.dart';

/// Logs estruturados para QA manual Hub (D1 login web, C1 saco vs resumo).
abstract final class HubQaDiag {
  static const _d1 = 'hub.qa.d1';
  static const _c1 = 'hub.qa.c1';

  static String? _lastC1Fingerprint;

  // —— D1 · login Chrome ————————————————————————————————————————————————————

  static void logD1ScreenOpen() {
    if (!kIsWeb) return;
    unawaited(
      FleaberLogger.instance.event(_d1, {
        'step': 'screen_open',
        'platform': 'web',
        'note': 'Semantics omitido no web — TextFormField nativo',
      }),
    );
    debugPrint('[$_d1] screen_open web semantics=omitted');
  }

  static void logD1FieldChange({
    required String field,
    required int prevLen,
    required int newLen,
  }) {
    if (!kIsWeb) return;
    final delta = newLen - prevLen;
    final trigger = switch (delta) {
      > 1 => 'paste_or_autofill_likely',
      1 => 'char_added',
      -1 => 'char_removed',
      < -1 => 'bulk_delete_or_replace',
      _ => 'unchanged',
    };
    unawaited(
      FleaberLogger.instance.event(_d1, {
        'step': 'field_change',
        'field': field,
        'prev_len': prevLen,
        'new_len': newLen,
        'delta': delta,
        'trigger': trigger,
      }),
    );
    debugPrint(
      '[$_d1] $field len $prevLen→$newLen ($trigger)',
    );
  }

  static void logD1RememberAutofill({required int emailLen, required int passLen}) {
    if (!kIsWeb) return;
    unawaited(
      FleaberLogger.instance.event(_d1, {
        'step': 'remember_autofill',
        'email_len': emailLen,
        'pass_len': passLen,
      }),
    );
    debugPrint('[$_d1] remember_autofill email=$emailLen pass=$passLen');
  }

  static void logD1Submit({required int emailLen, required int passLen}) {
    if (!kIsWeb) return;
    unawaited(
      FleaberLogger.instance.event(_d1, {
        'step': 'submit_tap',
        'email_len': emailLen,
        'pass_len': passLen,
        'email_empty': emailLen == 0,
        'pass_empty': passLen == 0,
      }),
    );
    debugPrint('[$_d1] submit email=$emailLen pass=$passLen');
  }

  // —— C1 · saco vs resumo —————————————————————————————————————————————————

  static int unitQty(LiveReservationRequestsRow row) =>
      row.requestedQty < 1 ? 1 : row.requestedQty;

  static int sumUnits(Iterable<LiveReservationRequestsRow> rows) =>
      rows.fold<int>(0, (a, r) => a + unitQty(r));

  static List<Map<String, dynamic>> _rowSnapshots(
    List<LiveReservationRequestsRow> rows,
  ) {
    return [
      for (final r in rows)
        {
          'id': (r.id ?? '').trim(),
          'status': r.status ?? '',
          'qty': unitQty(r),
          'raw_requested_qty': r.requestedQty,
          'queue_pos': r.queuePosition,
          'source': r.source ?? '',
          'live_item_id': (r.liveItemId ?? '').trim(),
        },
    ];
  }

  /// Compara contagens entre superfícies (hub card, saco, badge player).
  static void logC1({
    required String source,
    required List<LiveReservationRequestsRow> rows,
    String? liveId,
    HubReservationSummary? summary,
    int? bagBadgeCount,
    int? bagSheetLineCount,
    int? bagSheetUnitCount,
  }) {
    final s = summary ?? HubReservationSummary.fromRows(rows);
    final unitSum = sumUnits(rows);
    final fingerprint =
        '$source|${liveId ?? ''}|${rows.length}|$unitSum|${s.total}|'
        '${s.inQueue}|${s.confirmed}|${s.pendingAwaiting}|'
        '$bagBadgeCount|$bagSheetLineCount|$bagSheetUnitCount';
    if (fingerprint == _lastC1Fingerprint) return;
    _lastC1Fingerprint = fingerprint;

    final mismatchBagVsSummary =
        bagSheetUnitCount != null && bagSheetUnitCount != s.total;
    final mismatchBadgeVsSummary =
        bagBadgeCount != null && bagBadgeCount != s.total;
    final mismatchLinesVsUnits = rows.isNotEmpty && rows.length != unitSum;

    final payload = <String, dynamic>{
      'step': 'reservation_counts',
      'surface': source,
      if (liveId != null && liveId.isNotEmpty) 'live_id': liveId,
      'row_count': rows.length,
      'unit_sum_raw_rows': unitSum,
      'summary_total': s.total,
      'summary_in_queue': s.inQueue,
      'summary_confirmed': s.confirmed,
      'summary_pending_awaiting': s.pendingAwaiting,
      'summary_needs_payment': s.needsPayment,
      'summary_headline': s.headline,
      if (bagBadgeCount != null) 'player_badge_count': bagBadgeCount,
      if (bagSheetLineCount != null) 'bag_sheet_line_count': bagSheetLineCount,
      if (bagSheetUnitCount != null) 'bag_sheet_unit_count': bagSheetUnitCount,
      'mismatch_bag_units_vs_summary': mismatchBagVsSummary,
      'mismatch_badge_vs_summary': mismatchBadgeVsSummary,
      'mismatch_lines_vs_units': mismatchLinesVsUnits,
      'rows': _rowSnapshots(rows),
    };

    unawaited(FleaberLogger.instance.event(_c1, payload));

    final flag = mismatchBagVsSummary || mismatchBadgeVsSummary ? ' MISMATCH' : '';
    debugPrint(
      '[$_c1] $source rows=${rows.length} units=$unitSum '
      'summary=${s.total} (${s.headline})$flag',
    );
  }
}
