import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '/pages/login/login_responsive_shell.dart';
import '/utils/fleaber_colors.dart';
import '/widgets/fleaber_cookie_consent_banner.dart';

/// Shell partilhado para Esqueci / Nova senha — formulário centrado, largura
/// controlada (mesmos máximos do painel direito do Login), padding para cookies.
/// Sem painel escuro; fundo [FleaberColors.bgTint].
class AuthCenteredFormShell extends StatelessWidget {
  const AuthCenteredFormShell({
    super.key,
    required this.child,
    this.appBar,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width;

    return ValueListenableBuilder<bool>(
      valueListenable: FleaberCookieConsentBanner.consentAccepted,
      builder: (context, cookiesOk, _) {
        final cookiePad = (!kIsWeb || cookiesOk)
            ? 0.0
            : FleaberCookieConsentBanner.scrollReserveForViewport(
                width: width,
                height: size.height,
              );
        final bottomPad = 28.0 + cookiePad;
        final formMax = width >= LoginResponsiveShell.wideDesktopBreakpoint
            ? 448.0
            : (width >= 1280
                ? 420.0
                : (width >= LoginResponsiveShell.tabletBreakpoint
                    ? 400.0
                    : double.infinity));
        final hPad = width >= LoginResponsiveShell.tabletBreakpoint ? 40.0 : 20.0;
        final tPad = width >= LoginResponsiveShell.tabletBreakpoint ? 28.0 : 12.0;

        return Scaffold(
          backgroundColor: FleaberColors.bgTint,
          appBar: appBar,
          body: SafeArea(
            top: appBar == null,
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(hPad, tPad, hPad, bottomPad),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - tPad - bottomPad,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: formMax),
                        child: child,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
