import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_raffle_service.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';

/// Botão lateral direito — Rifa da Live (comprador).
class LiveRaffleSidebarButton extends StatefulWidget {
  const LiveRaffleSidebarButton({
    super.key,
    required this.state,
    required this.onTap,
    this.loading = false,
  });

  final LiveRaffleState state;
  final VoidCallback onTap;
  final bool loading;

  @override
  State<LiveRaffleSidebarButton> createState() => _LiveRaffleSidebarButtonState();
}

class _LiveRaffleSidebarButtonState extends State<LiveRaffleSidebarButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  static const _accent = Color(0xFF00A3AD);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final raffle = widget.state.raffle;
    if (!widget.state.hasRaffle || raffle == null) {
      return const SizedBox.shrink();
    }

    final tickets = widget.state.viewer.ticketBalance;
    final joined = widget.state.viewer.joined;
    final showTicketBadge = tickets > 0;
    final showNewBadge = raffle.isActive && !raffle.isDrawn && !joined;
    final pulse = raffle.isActive && !raffle.isDrawn;

    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, child) {
        final glow = pulse ? 0.42 + (_pulseCtrl.value * 0.38) : 0.0;
        final ring = pulse ? 0.55 + (_pulseCtrl.value * 0.35) : 0.0;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: pulse
                ? Border.all(
                    color: _accent.withValues(alpha: ring),
                    width: 2.2,
                  )
                : null,
            boxShadow: pulse
                ? [
                    BoxShadow(
                      color: _accent.withValues(alpha: glow),
                      blurRadius: 22,
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Semantics(
            label: 'Rifa da Live',
            button: true,
            child: Material(
              color: Colors.black.withValues(alpha: 0.42),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.loading ? null : widget.onTap,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Center(
                    child: widget.loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.card_giftcard_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                  ),
                ),
              ),
            ),
          ),
          if (showNewBadge)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [FleaberElevation.smAccent(_accent)],
                ),
                child: Text(
                  '1',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
          if (showTicketBadge)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [FleaberElevation.sm],
                ),
                child: Text(
                  tickets > 99 ? '99+' : '$tickets',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Popup de detalhes — estilo live shopping.
class LiveRaffleDetailsSheet extends StatelessWidget {
  const LiveRaffleDetailsSheet({
    super.key,
    required this.state,
    this.participantCount,
    this.onShareTap,
    this.onParticipate,
    this.joinLoading = false,
  });

  final LiveRaffleState state;
  final int? participantCount;
  final VoidCallback? onShareTap;
  final VoidCallback? onParticipate;
  final bool joinLoading;

  static Future<void> show(
    BuildContext context, {
    required LiveRaffleState state,
    int? participantCount,
    VoidCallback? onShareTap,
    VoidCallback? onParticipate,
    bool joinLoading = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LiveRaffleDetailsSheet(
        state: state,
        participantCount: participantCount,
        onShareTap: onShareTap,
        onParticipate: onParticipate,
        joinLoading: joinLoading,
      ),
    );
  }

  static const _accent = Color(0xFF00A3AD);
  static const _panel = Color(0xFF101518);

  @override
  Widget build(BuildContext context) {
    final raffle = state.raffle!;
    final tickets = state.viewer.ticketBalance;
    final joined = state.viewer.joined;

    String timeLine;
    if (raffle.isDrawn) {
      timeLine = 'Sorteio concluído';
    } else if (raffle.hasTimer && raffle.secondsLeft != null) {
      timeLine =
          'Termina em: ${LiveRaffleService.formatCountdown(raffle.secondsLeft)}';
    } else if (raffle.isClosed) {
      timeLine = 'Inscrições fechadas';
    } else {
      timeLine = 'Rifa activa — a vendedora encerra quando quiser';
    }

    String participantsLine;
    if (participantCount != null && participantCount! > 0) {
      participantsLine = '$participantCount participantes';
    } else if (joined) {
      participantsLine = 'Já estás na rifa';
    } else {
      participantsLine = 'Participa para entrares no sorteio';
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.52,
      minChildSize: 0.38,
      maxChildSize: 0.88,
      builder: (context, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: _accent.withValues(alpha: 0.35)),
            boxShadow: const [FleaberElevation.md],
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.card_giftcard_rounded, color: _accent, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Rifa da Live',
                    style: GoogleFonts.interTight(
                      color: _accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: FleaberRadius.circularSm,
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: _prizePhoto(raffle.photoUrl),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          raffle.title,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            height: 1.2,
                          ),
                        ),
                        if (raffle.description?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 6),
                          Text(
                            raffle.description!.trim(),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: Colors.white70,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (!joined && raffle.isActive && onParticipate != null) ...[
                FleaberPrimaryButton(
                  label: 'Participar na Rifa (+1)',
                  loading: joinLoading,
                  onPressed: joinLoading ? null : onParticipate,
                ),
                const SizedBox(height: 14),
              ],
              _statTile(
                icon: Icons.confirmation_number_outlined,
                label: 'As tuas rifas',
                value: '$tickets',
              ),
              const SizedBox(height: 8),
              _statTile(
                icon: Icons.people_outline_rounded,
                label: 'Participantes',
                value: participantsLine,
              ),
              const SizedBox(height: 8),
              _statTile(
                icon: Icons.timer_outlined,
                label: raffle.hasTimer ? 'Tempo' : 'Estado',
                value: timeLine,
              ),
              const SizedBox(height: 20),
              Text(
                'Ganha mais rifas',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              _earnRow(
                icon: Icons.how_to_reg_outlined,
                label: 'Seguir vendedor',
                hint: '+1',
                done: state.viewer.followBonusClaimed,
                subtitle: state.viewer.followBonusClaimed
                    ? null
                    : 'Usa o botão Seguir no topo da live',
              ),
              _earnRow(
                icon: Icons.ios_share_rounded,
                label: 'Partilhar live',
                hint: '+1',
                done: state.viewer.shareBonusClaimed,
                onTap: !state.viewer.shareBonusClaimed &&
                        raffle.isActive &&
                        joined &&
                        onShareTap != null
                    ? onShareTap
                    : null,
              ),
              _earnRow(
                icon: Icons.person_add_alt_1_outlined,
                label: 'Convidar amigos',
                hint: '+2',
                done: false,
                subtitle: joined
                    ? 'Link com código — visitante 60s+ na live'
                    : 'Participa primeiro',
                onTap: raffle.isActive && joined && onShareTap != null
                    ? onShareTap
                    : null,
              ),
              _earnRow(
                icon: Icons.shopping_bag_outlined,
                label: 'Compra paga',
                hint: '+2',
                done: state.viewer.purchaseBonusClaimed,
                subtitle: state.viewer.purchaseBonusClaimed
                    ? null
                    : 'Por encomenda paga na live (participa primeiro)',
              ),
              if (raffle.showPublicLeaderboard &&
                  state.leaderboard.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Top rifas',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                ...state.leaderboard.map(_leaderboardRow),
              ],
              const SizedBox(height: 10),
              Text(
                'Gorjetas não dão rifas.',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
              ),
              if (raffle.isDrawn && state.winners.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD54F).withValues(alpha: 0.12),
                    borderRadius: FleaberRadius.circularMd,
                    border: Border.all(
                      color: const Color(0xFFFFD54F).withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.emoji_events_outlined,
                        color: Color(0xFFFFD54F),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          state.viewer.isWinner
                              ? 'Ganhaste a Rifa da Live!'
                              : 'Vencedor: ${state.winners.first.displayName ?? 'Participante'}',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _leaderboardRow(LiveRaffleLeaderboardEntry e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '#${e.rank}',
              style: GoogleFonts.inter(
                color: _accent,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              e.displayName ?? 'Participante',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${e.ticketBalance}',
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _prizePhoto(String? url) {
    final u = url?.trim() ?? '';
    if (u.isEmpty) {
      return ColoredBox(
        color: _accent.withValues(alpha: 0.15),
        child: const Center(
          child: Icon(Icons.card_giftcard_rounded, color: _accent, size: 24),
        ),
      );
    }
    return BatataCachedNetworkImage(
      imageUrl: u,
      fit: BoxFit.cover,
      placeholderColor: const Color(0xFF222222),
    );
  }

  Widget _statTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: FleaberRadius.circularMd,
      ),
      child: Row(
        children: [
          Icon(icon, color: _accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _earnRow({
    required IconData icon,
    required String label,
    required String hint,
    required bool done,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    final row = Row(
      children: [
        Icon(
          done ? Icons.check_circle_rounded : icon,
          color: done ? const Color(0xFF4CAF50) : Colors.white54,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 10,
                    height: 1.25,
                  ),
                ),
            ],
          ),
        ),
        Text(
          done ? 'Feito' : hint,
          style: GoogleFonts.inter(
            color: done ? const Color(0xFF4CAF50) : Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: _accent, size: 18),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: onTap == null
          ? row
          : Material(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: FleaberRadius.circularMd,
              child: InkWell(
                onTap: onTap,
                borderRadius: FleaberRadius.circularMd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: row,
                ),
              ),
            ),
    );
  }
}
