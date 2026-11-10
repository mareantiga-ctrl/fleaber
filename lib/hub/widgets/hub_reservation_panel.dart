import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/backend/supabase/supabase.dart';
import '/utils/live_reservation_queue_service.dart';
import '/widgets/fleaber_primary_button.dart';

import '../hub_live_reservation_ui.dart';
import '../theme/hub_theme.dart';

/// Card Hub unificado — login, vazio, fila, urgente (U10 + T4b).
class HubReservationPanel extends StatelessWidget {
  const HubReservationPanel._({
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(16, 4, 16, 10),
  });

  final Widget child;
  final EdgeInsets margin;

  /// Visitante — pedir login (Live scroll + Gravado B7a).
  factory HubReservationPanel.loginPrompt({
    required VoidCallback onLogin,
  }) {
    const accent = Color(0xFF00A3AD);
    return HubReservationPanel._(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.22),
              blurRadius: 16,
              spreadRadius: 0,
            ),
          ],
        ),
        child: _HubPanelSurface(
          borderColor: accent.withValues(alpha: 0.55),
          borderWidth: 1.5,
          backgroundColor: const Color(0xFF101820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      color: accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tens reservas feitas no Facebook?',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            'Recuperar reservas',
                            style: GoogleFonts.inter(
                              color: accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Entra para recuperares as tuas reservas e continuares a compra.',
                style: HubTheme.body.copyWith(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 14),
              FleaberPrimaryButton(
                label: 'Entrar',
                height: 44,
                onPressed: onLogin,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Resumo activo (fila / pagamento pendente).
  factory HubReservationPanel.activeSummary({
    required HubReservationSummary summary,
    required VoidCallback onOpenBag,
    bool loading = false,
  }) {
    final urgent = summary.hasUrgentAction;
    final borderColor =
        urgent ? const Color(0xFFFF3B30) : const Color(0xFFFFB74D);
    final accentIcon =
        urgent ? Icons.warning_amber_rounded : Icons.shopping_bag_outlined;

    return HubReservationPanel._(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: urgent
              ? [
                  BoxShadow(
                    color: const Color(0x66FF3B30),
                    blurRadius: 16,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: _HubPanelSurface(
          borderColor: borderColor,
          borderWidth: urgent ? 1.5 : 1,
          backgroundColor:
              urgent ? const Color(0xFF2A0A0E) : const Color(0xFF1A1410),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (urgent)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: borderColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'AÇÃO NECESSÁRIA',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(accentIcon, color: borderColor, size: urgent ? 26 : 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.hubCardTitle,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                        if (summary.hubCardSubline.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            summary.hubCardSubline,
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FleaberPrimaryButton.compact(
                  label: summary.hubCardCta,
                  loading: loading,
                  onPressed: loading ? null : onOpenBag,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sem reservas (autenticado).
  factory HubReservationPanel.empty({
    required String message,
    IconData icon = Icons.shopping_bag_outlined,
  }) {
    return HubReservationPanel._(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: _HubPanelSurface(
        child: Row(
          children: [
            Icon(icon, color: HubTheme.textMuted, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: HubTheme.body.copyWith(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  /// Linha de reserva (lista «As minhas reservas»).
  factory HubReservationPanel.row({
    required LiveReservationRequestsRow reservation,
  }) {
    final status = LiveReservationQueueService.buyerBagStatusLabel(
      reservation.status,
      notes: reservation.notes,
      requestKind: reservation.requestKind,
      expiresAt: reservation.expiresAt,
      queuePosition: reservation.queuePosition,
    );
    final pos = reservation.queuePosition;
    final qty = reservation.requestedQty < 1 ? 1 : reservation.requestedQty;
    final chip = HubReservationStatusUi.statusChip(
      reservation.status ?? '',
      notes: reservation.notes,
      queuePosition: pos,
      requestKind: reservation.requestKind,
      expiresAt: reservation.expiresAt,
    );

    return HubReservationPanel._(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: _HubPanelSurface(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lugar #${pos ?? '—'}',
                    style: HubTheme.titleMd.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  chip,
                  if (status.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(status, style: HubTheme.label.copyWith(fontSize: 11)),
                  ],
                ],
              ),
            ),
            Text(
              '×$qty',
              style: GoogleFonts.inter(
                color: HubTheme.accent,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  factory HubReservationPanel.loading() {
    return HubReservationPanel._(
      margin: const EdgeInsets.all(16),
      child: _HubPanelSurface(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: HubTheme.teal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(padding: margin, child: child);
  }
}

class _HubPanelSurface extends StatelessWidget {
  const _HubPanelSurface({
    required this.child,
    this.borderColor,
    this.borderWidth = 1,
    this.backgroundColor,
  });

  final Widget child;
  final Color? borderColor;
  final double borderWidth;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor ?? HubTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.08),
          width: borderWidth,
        ),
        boxShadow: const [],
      ),
      child: child,
    );
  }
}
