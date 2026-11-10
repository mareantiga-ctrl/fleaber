import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_radius.dart';
import '/utils/live_raffle_prize_copy.dart';
import '/utils/raffle_log.dart';
import '/widgets/fleaber_primary_button.dart';

/// Card de celebração do vencedor — tem de tocar «Percebi» para fechar.
class LiveRaffleWinnerCelebration extends StatefulWidget {
  const LiveRaffleWinnerCelebration({
    super.key,
    required this.prizeTitle,
    this.winnerName,
  });

  final String prizeTitle;
  final String? winnerName;

  static Future<void> show(
    BuildContext context, {
    required String prizeTitle,
    String? winnerName,
  }) async {
    RaffleLog.d('winner celebration SHOW start', {
      'prize': prizeTitle,
      'mounted': context.mounted,
      'hasOverlay': Overlay.maybeOf(context, rootOverlay: true) != null,
    });
    if (!context.mounted) {
      RaffleLog.d('winner celebration ABORT unmounted');
      return;
    }

    try {
      await showGeneralDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierLabel: 'Vencedor da rifa',
        barrierColor: Colors.black.withValues(alpha: 0.72),
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (ctx, anim, secondary) {
          return LiveRaffleWinnerCelebration(
            prizeTitle: prizeTitle,
            winnerName: winnerName,
          );
        },
        transitionBuilder: (ctx, anim, secondary, child) {
          final curved =
              CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
          return FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: curved, child: child),
          );
        },
      );
      RaffleLog.d('winner celebration SHOW closed (generalDialog)');
      return;
    } catch (e) {
      RaffleLog.e('winner celebration generalDialog failed', e);
    }

    if (!context.mounted) return;
    try {
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (ctx) => LiveRaffleWinnerCelebration(
          prizeTitle: prizeTitle,
          winnerName: winnerName,
        ),
      );
      RaffleLog.d('winner celebration SHOW closed (dialog fallback)');
    } catch (e) {
      RaffleLog.e('winner celebration dialog fallback failed', e);
    }
  }

  @override
  State<LiveRaffleWinnerCelebration> createState() =>
      _LiveRaffleWinnerCelebrationState();
}

class _LiveRaffleWinnerCelebrationState extends State<LiveRaffleWinnerCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFD54F);
    const teal = Color(0xFF00A3AD);

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Material(
            color: const Color(0xFF12181C),
            borderRadius: FleaberRadius.circularLg,
            elevation: 12,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) {
                      final t = 0.55 + (_pulse.value * 0.45);
                      return Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: gold.withValues(alpha: 0.16),
                          boxShadow: [
                            BoxShadow(
                              color: gold.withValues(alpha: 0.35 * t),
                              blurRadius: 18 * t,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: child,
                      );
                    },
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: gold,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Ganhaste a Rifa!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.interTight(
                      color: gold,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.prizeTitle.trim().isEmpty
                        ? 'O prémio é teu.'
                        : widget.prizeTitle.trim(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    LiveRafflePrizeCopy.celebrationBody,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Largura ≈ texto + 25%; texto igual; centrado no botão.
                  Builder(
                    builder: (context) {
                      const label = 'Percebi';
                      const fontSize = 15.0;
                      final painter = TextPainter(
                        text: TextSpan(
                          text: label,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: fontSize,
                          ),
                        ),
                        textDirection: TextDirection.ltr,
                        maxLines: 1,
                      )..layout();
                      final buttonWidth = painter.width * 1.25;
                      return FleaberPrimaryButton(
                        label: label,
                        width: buttonWidth,
                        height: 48,
                        fontSize: fontSize,
                        textAlign: TextAlign.center,
                        backgroundColor: teal,
                        onPressed: () =>
                            Navigator.of(context, rootNavigator: true).pop(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
