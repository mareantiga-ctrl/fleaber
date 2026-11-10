import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/widgets/fleaber_primary_button.dart';

import '../theme/hub_theme.dart';

/// Entrada compacta para recuperar reservas feitas no Facebook (Hub Live B3).
///
/// Não é um segundo saco — só descoberta + acção (Entrar / Continuar com Facebook).
enum HubFacebookRecoverMode {
  /// Visitante — sugerir login para recuperar reservas Facebook.
  guest,

  /// Autenticado sem identity Facebook — RPC `facebook_login_required`.
  needsFacebookLogin,
}

class HubFacebookRecoverCta extends StatelessWidget {
  const HubFacebookRecoverCta({
    super.key,
    required this.mode,
    required this.onPressed,
    this.compact = true,
    this.loading = false,
  });

  final HubFacebookRecoverMode mode;
  final VoidCallback? onPressed;
  final bool compact;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final isFb = mode == HubFacebookRecoverMode.needsFacebookLogin;
    final title = isFb
        ? 'Encontrámos reservas associadas ao teu Facebook.'
        : 'Reservaste artigos no Facebook?';
    final body = isFb
        ? 'Continua com Facebook para as recuperar e concluir a compra.'
        : 'Entra para consultar e concluir a compra.';
    final cta = isFb ? 'Continuar com Facebook' : 'Entrar';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 14,
        compact ? 8 : 12,
        compact ? 8 : 14,
        compact ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF141C22),
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
        border: Border.all(
          color: HubTheme.teal.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: compact ? 11 : 14,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          SizedBox(height: compact ? 3 : 6),
          Text(
            body,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          SizedBox(height: compact ? 6 : 12),
          FleaberPrimaryButton(
            label: cta,
            height: compact ? 32 : 44,
            borderRadius: compact ? 10 : 14,
            fontSize: compact ? 12 : 14,
            loading: loading,
            onPressed: loading ? null : onPressed,
          ),
        ],
      ),
    );
  }
}
