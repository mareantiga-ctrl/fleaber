import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/utils/fleaber_colors.dart';
import '/utils/fleaber_elevation.dart';
import '/widgets/fleaber_primary_button.dart';

import 'fleahub_site_chrome.dart';

/// Entrada permanente H03 — reservas originadas no Facebook.
///
/// Não cria reservas nem afirma existência sem o fluxo real (login / claim / saco).
enum HubFacebookReservationsEntryKind {
  /// Sem sessão → autenticar.
  guest,

  /// Sessão sem identity Facebook (RPC).
  needsFacebookLogin,

  /// Sessão OK → abrir saco / consultar reservas reais.
  openBag,
}

class HubFacebookReservationsEntry extends StatelessWidget {
  const HubFacebookReservationsEntry({
    super.key,
    required this.kind,
    required this.onPressed,
    this.compact = false,
    this.loading = false,
    this.chip = false,
    this.light = false,
  });

  final HubFacebookReservationsEntryKind kind;
  final VoidCallback? onPressed;
  final bool compact;
  final bool loading;

  /// Mobile: faixa sobre o player (não tapar controlos centrais).
  final bool chip;

  /// Desktop Hub claro (H01/H02).
  final bool light;

  @override
  Widget build(BuildContext context) {
    const title = 'Compraste num direto do Facebook?';
    final subtitle = switch (kind) {
      HubFacebookReservationsEntryKind.guest =>
        'Consulta os artigos que reservaste e termina a tua compra.',
      HubFacebookReservationsEntryKind.needsFacebookLogin =>
        'Continua com Facebook para recuperar as tuas reservas.',
      HubFacebookReservationsEntryKind.openBag =>
        'Consulta os artigos que reservaste e termina a tua compra.',
    };
    final ctaFull = switch (kind) {
      HubFacebookReservationsEntryKind.guest => 'Ver as minhas reservas',
      HubFacebookReservationsEntryKind.needsFacebookLogin =>
        'Continuar com Facebook',
      HubFacebookReservationsEntryKind.openBag => 'Ver as minhas reservas',
    };
    // Compact (coluna chat ~220): texto completo sem cortar no botão.
    final cta = compact
        ? switch (kind) {
            HubFacebookReservationsEntryKind.needsFacebookLogin =>
              'Continuar com Facebook',
            _ => 'Ver reservas',
          }
        : ctaFull;

    if (chip) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              color: const Color(0xF0101518),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: FleaberColors.teal.withValues(alpha: 0.65),
              ),
              boxShadow: const [FleaberElevation.sm],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.facebook_rounded,
                      color: FleaberColors.teal, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: FleaHubSiteLayout.typeBody,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: FleaHubSiteLayout.typeCaption,
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cta,
                          style: GoogleFonts.inter(
                            color: FleaberColors.teal,
                            fontSize: FleaHubSiteLayout.typeSecondary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final bg = light ? const Color(0xFFF0F4F6) : const Color(0xFF141C22);
    final titleFg = light ? const Color(0xFF101518) : Colors.white;
    final subFg = light
        ? const Color(0xFF57636C)
        : Colors.white.withValues(alpha: 0.65);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 12,
        compact ? 10 : 12,
        compact ? 10 : 12,
        compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(color: FleaberColors.teal.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: titleFg,
              fontSize: compact
                  ? FleaHubSiteLayout.typeSecondary
                  : FleaHubSiteLayout.typeBody,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              color: subFg,
              fontSize: FleaHubSiteLayout.typeCaption,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: FleaberPrimaryButton(
                label: cta,
                height: compact ? 36 : 40,
                borderRadius: 12,
                fontSize: FleaHubSiteLayout.typeBody,
                loading: loading,
                onPressed: loading ? null : onPressed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
