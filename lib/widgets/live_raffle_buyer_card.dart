import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/utils/fleaber_elevation.dart';
import '/utils/fleaber_radius.dart';
import '/utils/live_raffle_service.dart';
import '/utils/live_raffle_share.dart';
import '/utils/raffle_log.dart';
import '/widgets/batata_cached_image.dart';
import '/widgets/fleaber_primary_button.dart';

const _kRaffleAccent = Color(0xFF00A3AD);
const _kRafflePanel = Color(0xFF101518);

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

  static const _kRaffleAccent = Color(0xFF00A3AD);

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
                    color: _kRaffleAccent.withValues(alpha: ring),
                    width: 2.2,
                  )
                : null,
            boxShadow: pulse
                ? [
                    BoxShadow(
                      color: _kRaffleAccent.withValues(alpha: glow),
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
                  color: _kRaffleAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [FleaberElevation.smAccent(_kRaffleAccent)],
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
                  color: _kRaffleAccent,
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
class LiveRaffleDetailsSheet extends StatefulWidget {
  const LiveRaffleDetailsSheet({
    super.key,
    required this.liveId,
    required this.initialState,
    this.initialParticipantCount,
    this.preferredShareLink,
    this.onJoined,
    this.onNeedAuth,
    this.onShareResult,
  });

  final String liveId;
  final LiveRaffleState initialState;
  final int? initialParticipantCount;
  /// Link preferido (Hub) — senão usa fleaber.app/live/…
  final String? preferredShareLink;
  /// Após join OK — sincronizar estado no Player.
  final void Function(int ticketBalance)? onJoined;
  /// Pedir login (Hub/Fleaber) se o utilizador não estiver autenticado.
  final Future<bool> Function()? onNeedAuth;
  /// Após partilha (com ou sem bónus) — snack + sync no parent.
  final void Function(LiveRaffleShareResult result)? onShareResult;

  static Future<void> show(
    BuildContext context, {
    required String liveId,
    required LiveRaffleState state,
    int? participantCount,
    String? preferredShareLink,
    void Function(int ticketBalance)? onJoined,
    Future<bool> Function()? onNeedAuth,
    void Function(LiveRaffleShareResult result)? onShareResult,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LiveRaffleDetailsSheet(
        liveId: liveId,
        initialState: state,
        initialParticipantCount: participantCount,
        preferredShareLink: preferredShareLink,
        onJoined: onJoined,
        onNeedAuth: onNeedAuth,
        onShareResult: onShareResult,
      ),
    );
  }

  @override
  State<LiveRaffleDetailsSheet> createState() => _LiveRaffleDetailsSheetState();
}

class _LiveRaffleDetailsSheetState extends State<LiveRaffleDetailsSheet> {
  late LiveRaffleState _state;
  int? _participantCount;
  bool _joinLoading = false;
  bool _shareLoading = false;
  bool _refreshing = false;
  String? _errorBanner;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
    _participantCount = widget.initialParticipantCount;
    // Sempre refrescar ao abrir — evita sheet «preso» pré-sorteio.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshFromServer());
    });
  }

  Future<void> _refreshFromServer() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final next = await LiveRaffleService.fetchState(widget.liveId);
      if (!mounted) return;
      if (!next.hasRaffle || next.raffle == null) {
        RaffleLog.d('sheet refresh empty — keep', {'prev': _state.debugSummary});
        return;
      }
      final merged = _state.hasRaffle && _state.raffle != null
          ? _state.mergePreferringLocalViewer(next)
          : next;
      // Preferir status remoto se avançou (drawn/closed).
      final preferRemoteStatus = next.raffle != null &&
          _state.raffle != null &&
          _statusRank(next.raffle!.status) >= _statusRank(_state.raffle!.status);
      final applied = preferRemoteStatus
          ? next.copyWith(
              viewer: merged.viewer,
            )
          : merged;
      int? participants;
      final rid = applied.raffle?.id;
      if (rid != null && rid.isNotEmpty) {
        participants = await LiveRaffleService.fetchParticipantCount(rid);
      }
      if (!mounted) return;
      setState(() {
        _state = applied;
        if (participants != null) _participantCount = participants;
      });
      RaffleLog.d('sheet refresh ok', {'state': applied.debugSummary});
    } catch (e) {
      RaffleLog.e('sheet refresh', e);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  int _statusRank(String status) {
    switch (status) {
      case 'drawn':
        return 3;
      case 'closed':
        return 2;
      case 'active':
        return 1;
      default:
        return 0;
    }
  }

  String _humanJoinError(Object e) {
    final s = e.toString();
    if (s.contains('auth_required') || s.contains('Auth')) {
      return 'Inicia sessão para participar na rifa.';
    }
    if (s.contains('raffle_not_active')) {
      return 'Esta rifa já não está activa.';
    }
    if (s.contains('raffle_ended')) {
      return 'Esta rifa já terminou.';
    }
    if (s.contains('raffle_not_found')) {
      return 'Rifa não encontrada. Fecha e abre de novo.';
    }
    if (s.contains('not_eligible')) {
      return 'Não és elegível nesta rifa.';
    }
    return 'Não foi possível participar. Tenta outra vez.';
  }

  Future<void> _handleShare() async {
    if (_shareLoading) return;
    RaffleLog.d('sheet share tap', {
      'liveId': widget.liveId,
      'state': _state.debugSummary,
    });
    if (currentUserUid.isEmpty) {
      final ok = await widget.onNeedAuth?.call() ?? false;
      if (!mounted) return;
      if (!ok || currentUserUid.isEmpty) {
        setState(
          () => _errorBanner = 'Inicia sessão para partilhar e ganhar rifa.',
        );
        return;
      }
    }

    setState(() {
      _shareLoading = true;
      _errorBanner = null;
    });
    try {
      final result = await LiveRaffleShare.shareLive(
        liveId: widget.liveId,
        preferredLink: widget.preferredShareLink,
      );
      if (!mounted) return;
      final bal = result.ticketBalance;
      setState(() {
        _state = _state.copyWith(
          hasRaffle: true,
          raffle: _state.raffle,
          viewer: _state.viewer.copyWith(
            joined: true,
            shareBonusClaimed:
                result.awardedShareBonus || result.shareAlreadyClaimed
                    ? true
                    : _state.viewer.shareBonusClaimed,
            ticketBalance: bal != null && bal > 0
                ? bal
                : (result.awardedShareBonus
                    ? (_state.viewer.ticketBalance > 0
                        ? _state.viewer.ticketBalance + 1
                        : 2)
                    : _state.viewer.ticketBalance),
          ),
        );
      });
      RaffleLog.d('sheet share after setState', {'state': _state.debugSummary});
      widget.onShareResult?.call(result);
    } catch (e) {
      RaffleLog.e('sheet share', e);
      if (!mounted) return;
      setState(
        () => _errorBanner = 'Não foi possível partilhar. Tenta outra vez.',
      );
    } finally {
      if (mounted) setState(() => _shareLoading = false);
    }
  }

  Future<void> _handleParticipate() async {
    if (_joinLoading) return;
    final raffleId = (_state.raffle?.id ?? '').trim();
    if (raffleId.isEmpty) {
      setState(() => _errorBanner = 'Rifa inválida. Fecha e abre de novo.');
      return;
    }

    if (currentUserUid.isEmpty) {
      final ok = await widget.onNeedAuth?.call() ?? false;
      if (!mounted) return;
      if (!ok || currentUserUid.isEmpty) {
        setState(
          () => _errorBanner = 'Inicia sessão para participar na rifa.',
        );
        return;
      }
    }

    final previous = _state;
    setState(() {
      _joinLoading = true;
      _errorBanner = null;
      _state = previous.copyWith(
        hasRaffle: true,
        raffle: previous.raffle,
        viewer: previous.viewer.copyWith(
          joined: true,
          ticketBalance: previous.viewer.ticketBalance > 0
              ? previous.viewer.ticketBalance
              : 1,
        ),
      );
      if ((_participantCount ?? 0) < 1) _participantCount = 1;
    });

    try {
      final tickets = await LiveRaffleService.join(raffleId);
      if (!mounted) return;
      final bal = tickets > 0 ? tickets : 1;
      setState(() {
        _state = _state.copyWith(
          viewer: _state.viewer.copyWith(joined: true, ticketBalance: bal),
        );
        _errorBanner = null;
      });
      widget.onJoined?.call(bal);

      try {
        final next = await LiveRaffleService.fetchState(widget.liveId);
        if (!mounted) return;
        // Só aplicar refresh se confirmar joined — senão mantém optimista.
        if (next.hasRaffle &&
            next.raffle != null &&
            next.viewer.joined == true) {
          final participants = await LiveRaffleService.fetchParticipantCount(
            next.raffle!.id,
          );
          if (!mounted) return;
          setState(() {
            _state = next;
            _participantCount = participants ?? _participantCount;
          });
        }
      } catch (_) {
        /* mantém optimista */
      }
    } catch (e) {
      debugPrint('[LiveRaffle] join sheet: $e');
      if (!mounted) return;
      setState(() {
        _state = previous;
        _errorBanner = _humanJoinError(e);
      });
    } finally {
      if (mounted) setState(() => _joinLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final raffle = state.raffle;
    if (raffle == null) {
      return DraggableScrollableSheet(
        initialChildSize: 0.28,
        minChildSize: 0.22,
        maxChildSize: 0.4,
        builder: (context, scrollCtrl) {
          return Container(
            decoration: BoxDecoration(
              color: _kRafflePanel,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                const SizedBox(height: 20),
                Text(
                  'A carregar a rifa…',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.white70),
                ),
              ],
            ),
          );
        },
      );
    }
    final tickets = state.viewer.ticketBalance;
    final joined = state.viewer.joined;
    final participantCount = _participantCount;
    final canParticipate = !joined && raffle.isActive;

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

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.48,
      minChildSize: 0.36,
      maxChildSize: 0.86,
      builder: (context, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: _kRafflePanel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: _kRaffleAccent.withValues(alpha: 0.35),
            ),
            boxShadow: const [FleaberElevation.md],
          ),
          // CTA fora do ListView — evita o arrastar engolir o tap em «Participar».
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
                        const Icon(
                          Icons.card_giftcard_rounded,
                          color: _kRaffleAccent,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Rifa da Live',
                          style: GoogleFonts.interTight(
                            color: _kRaffleAccent,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (raffle.isDrawn) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD54F).withValues(alpha: 0.14),
                          borderRadius: FleaberRadius.circularMd,
                          border: Border.all(
                            color: const Color(0xFFFFD54F)
                                .withValues(alpha: 0.5),
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
                                    ? 'Parabéns! Ganhaste a Rifa da Live 🏆'
                                    : (state.winners.isNotEmpty
                                        ? 'Vencedor: ${state.winners.first.displayName ?? 'Participante'}'
                                        : (_refreshing
                                            ? 'Sorteio concluído — a carregar vencedor…'
                                            : 'Sorteio concluído')),
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (_refreshing)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFFFD54F),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: FleaberRadius.circularSm,
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: _prizePhoto(raffle.photoUrl),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                raffle.title,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  height: 1.2,
                                ),
                              ),
                              if (raffle.description?.trim().isNotEmpty ==
                                  true) ...[
                                const SizedBox(height: 4),
                                Text(
                                  raffle.description!.trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_errorBanner != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0x33FF5252),
                          borderRadius: FleaberRadius.circularSm,
                          border: Border.all(color: const Color(0xFFFF8A80)),
                        ),
                        child: Text(
                          _errorBanner!,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _statTile(
                            icon: Icons.confirmation_number_outlined,
                            label: 'As tuas rifas',
                            value: '$tickets',
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _statTile(
                            icon: Icons.people_outline_rounded,
                            label: 'Participantes',
                            value: participantCount != null &&
                                    participantCount > 0
                                ? '$participantCount'
                                : (joined ? '1+' : '—'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _statTile(
                      icon: Icons.timer_outlined,
                      label: raffle.hasTimer ? 'Tempo' : 'Estado',
                      value: timeLine,
                    ),
                    const SizedBox(height: 14),
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
                      hint: _shareLoading ? '…' : '+1',
                      done: state.viewer.shareBonusClaimed,
                      subtitle: state.viewer.shareBonusClaimed
                          ? null
                          : (joined
                              ? 'Copia o link e ganha +1 rifa'
                              : 'Participa primeiro'),
                      onTap: !state.viewer.shareBonusClaimed &&
                              raffle.isActive &&
                              joined &&
                              !_shareLoading
                          ? () => _handleShare()
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
                      onTap: raffle.isActive && joined && !_shareLoading
                          ? () => _handleShare()
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
                      style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (canParticipate || joined)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      12 + (bottomInset > 0 ? 0 : 4),
                    ),
                    child: canParticipate
                        ? FleaberPrimaryButton(
                            label: 'Participar (+1 rifa)',
                            height: 48,
                            width: double.infinity,
                            loading: _joinLoading,
                            onPressed:
                                _joinLoading ? null : _handleParticipate,
                          )
                        : Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: _kRaffleAccent.withValues(alpha: 0.14),
                              borderRadius: FleaberRadius.circularMd,
                              border: Border.all(
                                color: _kRaffleAccent.withValues(alpha: 0.55),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: _kRaffleAccent,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    tickets > 0
                                        ? 'Estás na rifa · $tickets ${tickets == 1 ? 'rifa' : 'rifas'}'
                                        : 'Estás na rifa',
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
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
                color: _kRaffleAccent,
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
        color: _kRaffleAccent.withValues(alpha: 0.15),
        child: const Center(
          child: Icon(Icons.card_giftcard_rounded, color: _kRaffleAccent, size: 24),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: FleaberRadius.circularMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _kRaffleAccent, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.25,
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
          Icon(Icons.chevron_right_rounded, color: _kRaffleAccent, size: 18),
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
