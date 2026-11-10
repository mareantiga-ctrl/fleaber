import 'dart:html' as html;

import 'package:go_router/go_router.dart';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/nav/nav.dart';
import '/hub/hub_actions.dart';
import '/index.dart';
import '/utils/fleaber_oauth_redirect.dart';

bool fleaberWebOAuthPending() {
  final uri = Uri.parse(html.window.location.href);
  return uri.queryParameters.containsKey('code') ||
      uri.fragment.contains('access_token') ||
      FleaberOAuthRedirect.isPasswordRecoveryUri(uri);
}

/// Processa `?code=` após redirect Facebook → fleaber.pt/fleahub/.
Future<void> fleaberRecoverWebOAuthIfNeeded({
  required GoRouter router,
}) async {
  final href = html.window.location.href;
  final uri = Uri.parse(href);
  final isRecovery = FleaberOAuthRedirect.isPasswordRecoveryUri(uri);
  if (!uri.queryParameters.containsKey('code') &&
      !uri.fragment.contains('access_token')) {
    return;
  }

  try {
    await SupaFlow.client.auth.getSessionFromUrl(uri);
    await authManager.refreshUser();
  } catch (_) {
    // Supabase pode já ter processado.
  }

  for (var i = 0; i < 24; i++) {
    if (currentUserUid.isNotEmpty) break;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  if (currentUserUid.isEmpty) return;

  if (isRecovery) {
    router.go(NovaSenhaWidget.routePath);
    return;
  }

  final returnTo = uri.queryParameters[FleaberOAuthRedirect.returnToQueryKey]
          ?.trim() ??
      uri.queryParameters['returnTo']?.trim();

  await HubActions.publishAuthSession();

  if (returnTo != null && returnTo.isNotEmpty) {
    final loc = returnTo.startsWith('/') ? returnTo : '/$returnTo';
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null && HubActions.isFleaHubReturnPath(loc)) {
      await HubActions.finishAuthWithHubWelcome(ctx, returnTo: loc);
    } else {
      router.go(loc);
    }
  } else {
    router.go('/fleahub');
  }

  // Limpar ?code= da barra de endereço (mantém path /fleahub/index.html).
  try {
    final clean = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      fragment: uri.fragment.isNotEmpty ? uri.fragment : null,
    );
    html.window.history.replaceState(null, '', clean.toString());
  } catch (_) {}
}
