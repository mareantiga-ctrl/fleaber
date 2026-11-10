import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/flutter_flow/nav/nav.dart';

import '../hub_account_routes.dart';
import '../hub_actions.dart';
import '../hub_navigation.dart';
import '../hub_public_access.dart';
import '../routing/hub_route_paths.dart';
import '../theme/hub_theme.dart';

/// Barra de conta Hub — sessão visível + Entrar / FleaHub / Sair.
///
/// Usada em [HubPageShell] (perfil, loja, avaliações, 404, loading).
/// Não altera o player live (BATATA).
class HubAccountChromeBar extends StatelessWidget {
  const HubAccountChromeBar({super.key});

  String _sessionLabel() {
    final name = currentUserDisplayName.trim();
    if (name.isNotEmpty) return name;
    final email = currentUserEmail.trim();
    if (email.isNotEmpty) {
      final at = email.indexOf('@');
      return at > 0 ? email.substring(0, at) : email;
    }
    return 'Conta';
  }

  String _returnTo(BuildContext context) {
    try {
      return HubActions.normalizeReturnTo(GoRouterState.of(context).uri);
    } catch (_) {
      return HubRoutePaths.landing;
    }
  }

  Future<void> _signOut() async {
    await authManager.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStateNotifier.instance,
      builder: (context, _) {
        final loggedIn = AppStateNotifier.instance.loggedIn;
        final hasBack = HubNavigation.hasInternalBack(context);
        return Material(
          color: HubTheme.surfaceElevated,
          elevation: 0,
          child: SafeArea(
            bottom: false,
            child: Container(
              width: double.infinity,
              height: 44,
              padding: EdgeInsets.only(
                left: hasBack ? 44 : 12,
                right: 8,
              ),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0x33FFFFFF), width: 1),
                ),
              ),
              child: Row(
                children: [
                  _link(
                    'FleaHub',
                    () {
                      final path = GoRouterState.of(context).uri.path;
                      if (path == HubRoutePaths.landing ||
                          path.endsWith('/fleahub')) {
                        return;
                      }
                      HubActions.openFleaHubLanding(context);
                    },
                  ),
                  const Spacer(),
                  if (loggedIn) ...[
                    Flexible(
                      child: Text(
                        _sessionLabel(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.inter(
                          color: HubTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _link(
                      'Conta',
                      () => HubAccountRoutes.openResumo(context),
                    ),
                    _link('Sair', () => unawaited(_signOut())),
                  ] else ...[
                    _link(
                      'Entrar',
                      () => HubActions.openLoginForReturn(
                        context,
                        returnTo: _returnTo(context),
                      ),
                    ),
                    if (HubPublicAccess.registrationEnabled)
                      _link(
                        'Registar',
                        () => HubActions.openRegistoForReturn(
                          context,
                          returnTo: _returnTo(context),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _link(String label, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: HubTheme.accent,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}
