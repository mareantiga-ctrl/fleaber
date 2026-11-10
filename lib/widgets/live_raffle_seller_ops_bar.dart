import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_radius.dart';
import '/utils/live_raffle_service.dart';
import '/widgets/fleaber_primary_button.dart';

/// Barra compacta / expansível da Rifa da Live (vendedora).
class LiveRaffleSellerOpsBar extends StatefulWidget {
  const LiveRaffleSellerOpsBar({
    super.key,
    required this.state,
    this.participantCount,
    this.ticketTotal,
    this.loading = false,
    this.onCreate,
    this.onCloseEntries,
    this.onDraw,
    this.onCancel,
  });

  final LiveRaffleState? state;
  final int? participantCount;
  /// Soma de tickets (rifas) de todos os participantes.
  final int? ticketTotal;
  final bool loading;
  final VoidCallback? onCreate;
  final VoidCallback? onCloseEntries;
  final VoidCallback? onDraw;
  final VoidCallback? onCancel;

  @override
  State<LiveRaffleSellerOpsBar> createState() => _LiveRaffleSellerOpsBarState();
}

class _LiveRaffleSellerOpsBarState extends State<LiveRaffleSellerOpsBar> {
  bool _expanded = false;

  static const _accent = Color(0xFF00A3AD);

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final raffle = state?.raffle;
    final hasRaffle = state?.hasRaffle == true && raffle != null;

    if (!hasRaffle) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: widget.onCreate,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(
            'Nova rifa da live',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      );
    }

    final title = raffle!.title;
    final participants = widget.participantCount ?? 0;
    final tickets = widget.ticketTotal ?? 0;
    final countsLabel = tickets > 0
        ? '$participants participantes · $tickets rifas'
        : '$participants participantes';
    final timeLabel = _timeLabel(raffle);
    final statusPrefix = raffle.isDrawn
        ? 'Rifa sorteada'
        : raffle.isClosed
            ? 'Rifa fechada'
            : 'Rifa activa';

    if (_expanded) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.1),
          borderRadius: FleaberRadius.circularMd,
          border: Border.all(color: _accent.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.card_giftcard_rounded, color: _accent, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    raffle.isDrawn
                        ? 'RIFA SORTEADA'
                        : raffle.isClosed
                            ? 'RIFA FECHADA'
                            : 'RIFA ACTIVA',
                    style: GoogleFonts.interTight(
                      color: _accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _expanded = false),
                  icon: const Icon(Icons.expand_less_rounded, color: Colors.white70),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              countsLabel,
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
            Text(
              timeLabel,
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
            if (raffle.isDrawn) ...[
              const SizedBox(height: 6),
              Text(
                state!.winners.isNotEmpty
                    ? 'Vencedor: ${state.winners.first.displayName ?? 'Participante'}'
                    : 'Sorteio concluído.',
                style: GoogleFonts.inter(
                  color: const Color(0xFFFFD54F),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (raffle.isActive) ...[
              FleaberPrimaryButton(
                label: 'Encerrar inscrições',
                loading: widget.loading,
                height: 40,
                onPressed: widget.loading ? null : widget.onCloseEntries,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: widget.loading ? null : widget.onCancel,
                child: const Text('Cancelar rifa'),
              ),
            ] else if (raffle.isClosed) ...[
              FleaberPrimaryButton(
                label: participants < 1
                    ? 'Sortear (sem participantes)'
                    : 'Sortear vencedor',
                loading: widget.loading,
                height: 40,
                onPressed: widget.loading || participants < 1
                    ? null
                    : widget.onDraw,
              ),
              const SizedBox(height: 8),
              // Sem isto: sortear/fechar com 0 pax = beco sem saída (só «Sortear»).
              OutlinedButton(
                onPressed: widget.loading ? null : widget.onCancel,
                child: Text(
                  participants < 1
                      ? 'Cancelar e criar outra'
                      : 'Cancelar rifa',
                ),
              ),
              if (participants < 1) ...[
                const SizedBox(height: 8),
                Text(
                  'Sem participantes — cancela para criar uma rifa nova.',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                ),
              ],
            ] else if (raffle.isDrawn) ...[
              Text(
                state!.winners.isEmpty
                    ? 'Sorteio sem vencedores. Podes criar outra rifa.'
                    : 'Sorteio concluído. Podes criar outra rifa neste directo.',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 10),
              FleaberPrimaryButton(
                label: 'Nova rifa da live',
                loading: widget.loading,
                height: 40,
                onPressed: widget.loading ? null : widget.onCreate,
              ),
            ],
          ],
        ),
      );
    }

    return InkWell(
      onTap: () => setState(() => _expanded = true),
      borderRadius: FleaberRadius.circularMd,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: FleaberRadius.circularMd,
          border: Border.all(color: _accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.card_giftcard_rounded, color: _accent, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$statusPrefix · $title · $countsLabel · $timeLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
            const Icon(Icons.expand_more_rounded, color: Colors.white54, size: 18),
          ],
        ),
      ),
    );
  }

  String _timeLabel(LiveRaffleInfo r) {
    if (r.isDrawn) return 'sorteada';
    if (r.isClosed) return 'fechada';
    if (r.hasTimer && r.secondsLeft != null) {
      return LiveRaffleService.formatCountdown(r.secondsLeft);
    }
    return 'sem limite';
  }
}
