import 'package:flutter/material.dart';

import '/backend/supabase/supabase.dart';
import '/utils/live_bag_copy.dart';
import '/utils/live_reservation_queue_service.dart';

/// Resumo de reservas da compradora numa live (H1).
class HubReservationSummary {
  const HubReservationSummary({
    required this.total,
    required this.inQueue,
    required this.confirmed,
    required this.pendingAwaiting,
    this.needsPayment = 0,
    this.duePayment = 0,
  });

  final int total;
  final int inQueue;
  final int confirmed;
  final int pendingAwaiting;
  final int needsPayment;
  /// Unidades aceites aguardando pagamento (subtexto «por pagar»).
  final int duePayment;

  bool get hasAny => total > 0;

  bool get hasUrgentAction => duePayment > 0 || needsPayment > 0;

  String get headline {
    if (total == 0) return '';
    return 'Tens $total reserva${total == 1 ? '' : 's'}';
  }

  String get hubCardTitle {
    if (total == 0) return '';
    if (hasUrgentAction) {
      return 'Tens $total reserva${total == 1 ? '' : 's'} por concluir';
    }
    return 'Tens $total reserva${total == 1 ? '' : 's'}';
  }

  String get hubCardSubline {
    if (total == 0) return '';
    final parts = <String>[];
    if (inQueue > 0) parts.add('$inQueue em fila');
    if (hasUrgentAction && duePayment > 0) {
      parts.add('$duePayment por pagar');
    } else if (pendingAwaiting > 0) {
      parts.add('$pendingAwaiting por confirmar');
    } else if (confirmed > 0) {
      parts.add('$confirmed confirmada${confirmed == 1 ? '' : 's'}');
    }
    return parts.join(' · ');
  }

  String get hubCardCta =>
      hasUrgentAction ? 'Ver saco e pagar' : 'Ver saco';

  String get paymentHint {
    if (needsPayment == 0) return '';
    return needsPayment == 1
        ? '1 reserva aguarda pagamento ou confirmação no saco.'
        : '$needsPayment reservas aguardam pagamento ou confirmação no saco.';
  }

  String get subline {
    if (total == 0) return '';
    final parts = <String>[];
    if (inQueue > 0) {
      parts.add('$inQueue em fila');
    }
    if (confirmed > 0) {
      parts.add('$confirmed confirmada${confirmed == 1 ? '' : 's'}');
    }
    if (pendingAwaiting > 0) {
      parts.add('$pendingAwaiting pendente${pendingAwaiting == 1 ? '' : 's'}');
    }
    return parts.join(' · ');
  }

  static int _rowQty(LiveReservationRequestsRow row) =>
      row.requestedQty < 1 ? 1 : row.requestedQty;

  static HubReservationSummary fromRows(List<LiveReservationRequestsRow> rows) {
    var inQueue = 0;
    var confirmed = 0;
    var pendingAwaiting = 0;
    var needsPayment = 0;
    var duePayment = 0;

    for (final r in rows) {
      final status = r.status ?? '';
      if (LiveReservationQueueService.isBuyerCancelledReservation(
        status: status,
        notes: r.notes,
      )) {
        continue;
      }
      if (status == 'rejected' || status == 'expired') continue;

      final qty = _rowQty(r);

      if (status == 'accepted' || status == 'converted') {
        confirmed += qty;
        if (LiveReservationQueueService.isAcceptedAwaitingPayment(
          status: status,
          notes: r.notes,
        )) {
          needsPayment += qty;
          duePayment += qty;
        }
        continue;
      }
      if (status != 'pending') continue;

      needsPayment += qty;
      final pos = r.queuePosition;
      if (pos != null && pos > 0) {
        inQueue += qty;
      } else {
        pendingAwaiting += qty;
      }
    }

    final total = inQueue + confirmed + pendingAwaiting;
    return HubReservationSummary(
      total: total,
      inQueue: inQueue,
      confirmed: confirmed,
      pendingAwaiting: pendingAwaiting,
      needsPayment: needsPayment,
      duePayment: duePayment,
    );
  }

  /// Primeira reserva activa/por pagar (fila → aceite pendente).
  static String? firstActionableReservationId(
    List<LiveReservationRequestsRow> rows,
  ) {
    LiveReservationRequestsRow? best;
    int bestScore = 1 << 30;

    for (final r in rows) {
      final status = r.status ?? '';
      if (LiveReservationQueueService.isBuyerCancelledReservation(
        status: status,
        notes: r.notes,
      )) {
        continue;
      }
      if (status == 'rejected' ||
          status == 'expired' ||
          status == 'converted') {
        continue;
      }
      final pending = status == 'pending';
      final awaitingPay = LiveReservationQueueService.isAcceptedAwaitingPayment(
        status: status,
        notes: r.notes,
      );
      if (!pending && !awaitingPay) continue;

      final score = pending
          ? (r.queuePosition ?? 9999)
          : 100000 + (r.queuePosition ?? 0);
      if (score < bestScore) {
        bestScore = score;
        best = r;
      }
    }
    return best?.id;
  }
}

/// Cores/chips de estado (H2).
abstract final class HubReservationStatusUi {
  static const green = Color(0xFF4CAF50);
  static const yellow = Color(0xFFFFB74D);
  static const orange = Color(0xFFFF9800);
  static const red = Color(0xFFE57373);
  static const gray = Color(0xFF8A9BA8);

  static _StatusStyle styleFor(
    String status, {
    String? notes,
    int? queuePosition,
    String? requestKind,
    DateTime? expiresAt,
    bool unavailable = false,
  }) {
    if (LiveReservationQueueService.isBuyerCancelledReservation(
      status: status,
      notes: notes,
    )) {
      return const _StatusStyle(
        label: 'Cancelado',
        fg: gray,
        bg: Color(0x332A2F33),
      );
    }
    if (unavailable) {
      return const _StatusStyle(
        label: LiveBagBuyerStateCopy.unavailable,
        fg: red,
        bg: Color(0x33E57373),
      );
    }

    final kind = (requestKind ?? '').trim().isEmpty
        ? 'approval_pending'
        : requestKind!.trim();

    if (status == 'accepted' && kind == 'guaranteed') {
      final label = LiveReservationQueueService.buyerBagStatusLabel(
        status,
        requestKind: kind,
        expiresAt: expiresAt,
      );
      return _StatusStyle(
        label: label,
        fg: green,
        bg: const Color(0x334CAF50),
      );
    }
    if (status == 'pending' && kind == 'bag_hold_none') {
      return const _StatusStyle(
        label: LiveBagBuyerStateCopy.immediatePayment,
        fg: yellow,
        bg: Color(0x33FFB74D),
      );
    }
    if (status == 'pending') {
      // approval_pending + legacy — never show queue rank to buyer.
      return const _StatusStyle(
        label: LiveBagBuyerStateCopy.approvalPending,
        fg: orange,
        bg: Color(0x33FF9800),
      );
    }

    return switch (status) {
      'accepted' || 'converted' => const _StatusStyle(
          label: 'Confirmado',
          fg: green,
          bg: Color(0x334CAF50),
        ),
      'rejected' => const _StatusStyle(
          label: 'Rejeitado',
          fg: red,
          bg: Color(0x33E57373),
        ),
      'expired' => const _StatusStyle(
          label: 'Expirado',
          fg: gray,
          bg: Color(0x332A2F33),
        ),
      _ => const _StatusStyle(
          label: 'Estado',
          fg: gray,
          bg: Color(0x332A2F33),
        ),
    };
  }

  static String sourceBadge(String source, {bool psDemo = false}) {
    if (psDemo && source == 'facebook_manual') return 'Facebook demo';
    return LiveReservationQueueService.sourceLabel(source);
  }

  static Widget statusChip(
    String status, {
    String? notes,
    int? queuePosition,
    String? requestKind,
    DateTime? expiresAt,
    bool unavailable = false,
    /// Hub drawer claro: texto escuro sobre fundo âmbar/verde suave.
    bool lightChrome = false,
  }) {
    final s = styleFor(
      status,
      notes: notes,
      queuePosition: queuePosition,
      requestKind: requestKind,
      expiresAt: expiresAt,
      unavailable: unavailable,
    );
    final lineState = LiveReservationQueueService.commercialLineState(
      status: status,
      requestKind: requestKind,
      unavailable: unavailable,
    );
    final info = LiveBagBuyerStateCopy.infoTextForLineState(lineState);
    // Hub / drawer claro: mesmo chip 108.1 (texto escuro + pastel + ⓘ).
    return LiveBagBuyerStateChip(
      label: s.label,
      color: s.fg,
      infoText: info,
      fontSize: 10,
      onLightBackground: lightChrome,
    );
  }
}

class _StatusStyle {
  const _StatusStyle({
    required this.label,
    required this.fg,
    required this.bg,
  });

  final String label;
  final Color fg;
  final Color bg;
}
