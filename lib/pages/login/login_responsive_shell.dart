import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';

/// Shell responsivo P08 — split desktop / coluna tablet-mobile.
/// Não contém lógica de autenticação.
class LoginResponsiveShell extends StatelessWidget {
  const LoginResponsiveShell({
    super.key,
    required this.fleaHubContext,
    required this.form,
    this.cookieBottomPad = 0,
    this.brandHeadline,
    this.brandBody,
  });

  final bool fleaHubContext;
  final Widget form;

  /// Espaço extra no fundo do scroll enquanto o banner de cookies está visível.
  final double cookieBottomPad;

  /// Copy do painel esquerdo (desktop). Null = texto P08 Login (defaults).
  final String? brandHeadline;
  final String? brandBody;

  static const splitBreakpoint = 1024.0;
  static const tabletBreakpoint = 768.0;
  static const wideDesktopBreakpoint = 1440.0;

  static double _formMaxWidth(double w) {
    if (w >= 1600) return 468;
    if (w >= wideDesktopBreakpoint) return 448;
    if (w >= 1280) return 420;
    // 1024–1279: um pouco mais estreito no painel direito.
    return 400;
  }

  static double _formHorizontalPad(double w) {
    if (w >= 1600) return 60;
    if (w >= wideDesktopBreakpoint) return 48;
    if (w >= 1280) return 40;
    return 36;
  }

  static double _formTopPad(double w) {
    if (w >= wideDesktopBreakpoint) return 56;
    if (w >= 1280) return 40;
    // 1024: menos padding superior → melhor equilíbrio vertical.
    return 28;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final split = w >= splitBreakpoint;
        final bottomPad = 28.0 + cookieBottomPad;

        if (split) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 11,
                child: _BrandPanel(
                  fleaHubContext: fleaHubContext,
                  viewportWidth: w,
                  headline: brandHeadline,
                  body: brandBody,
                ),
              ),
              Expanded(
                flex: 10,
                child: ColoredBox(
                  color: FleaberColors.bgTint,
                  child: LayoutBuilder(
                    builder: (context, panelConstraints) {
                      final formMax = _formMaxWidth(w);
                      final hPad = _formHorizontalPad(w);
                      final tPad = _formTopPad(w);
                      return SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          hPad,
                          tPad,
                          hPad,
                          bottomPad,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: panelConstraints.maxHeight,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: formMax),
                              child: form,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        }

        final tablet = w >= tabletBreakpoint;
        final formMax = tablet ? 480.0 : double.infinity;
        final hPad = tablet ? 40.0 : 20.0;
        final tPad = tablet ? 36.0 : 12.0;

        return ColoredBox(
          color: FleaberColors.bgTint,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, tPad, hPad, bottomPad),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: formMax),
                child: form,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({
    required this.fleaHubContext,
    required this.viewportWidth,
    this.headline,
    this.body,
  });

  final bool fleaHubContext;
  final double viewportWidth;
  final String? headline;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final wide = viewportWidth >= LoginResponsiveShell.wideDesktopBreakpoint;
    final ultra = viewportWidth >= 1600;
    final headlineSize = ultra ? 40.0 : (wide ? 38.0 : 34.0);
    final sidePad = ultra ? 60.0 : (wide ? 56.0 : 40.0);
    final resolvedHeadline = headline ??
        (fleaHubContext
            ? 'Entra para continuares a explorar.'
            : 'Bem-vindo de volta.');
    final resolvedBody = body ??
        (fleaHubContext
            ? 'Reservas, compras, gravados e marketplace — '
                'no mesmo sítio onde viste o directo.'
            : 'Entra na tua conta Fleaber para continuares.');

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F1417),
            Color(0xFF152028),
            Color(0xFF0C3A40),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            left: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00A3AD).withValues(alpha: 0.18),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(sidePad, 48, sidePad, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fleaHubContext ? 'FLEAHUB' : 'FLEABER',
                    style: GoogleFonts.inter(
                      // Mais claro que o teal do círculo — legível no gradiente.
                      color: const Color(0xFF7ADCE2),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const Spacer(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Text(
                      resolvedHeadline,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: headlineSize,
                        fontWeight: FontWeight.w700,
                        height: 1.18,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Text(
                      resolvedBody,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 16,
                        height: 1.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
