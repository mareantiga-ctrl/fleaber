import 'package:flutter/foundation.dart';

import 'fleaber_web_deploy.dart';

/// Redirect OAuth Facebook — web (fleaber.pt/fleahub) vs app (deep link).
abstract final class FleaberOAuthRedirect {
  static const mobileFacebookCallback = 'fleaber://fleaber.com/auth-callback';

  /// Query param preservado no redirect Supabase (PKCE `?code=`).
  static const returnToQueryKey = 'fleaber_return';

  /// Marca redirect de recuperação de palavra-passe (vs OAuth Facebook).
  static const recoveryQueryKey = 'fleaber_recovery';

  static String passwordRecoveryRedirectTo() {
    // Mobile: HTTPS App Link (mesmo path que o email de recuperação usa).
    if (!kIsWeb) {
      return 'https://fleaber.pt/redefinir-senha?$recoveryQueryKey=1';
    }

    final base = _webCallbackBase();
    final uri = Uri.parse(base);
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            recoveryQueryKey: '1',
          },
        )
        .toString();
  }

  /// HTTPS App Link — abre a app se instalada (assetlinks); senão o browser.
  static const httpsAuthCallback = 'https://fleaber.pt/auth-callback';

  /// Redirect após o utilizador confirmar o e-mail (link Supabase).
  /// Mobile: HTTPS App Link (email clients bloqueiam fleaber://).
  /// Web: shell Hub — nunca path 404 na raiz do site.
  static String emailConfirmRedirectTo() {
    if (!kIsWeb) return httpsAuthCallback;
    return _webCallbackBase();
  }

  static bool isPasswordRecoveryUri(Uri uri) {
    if (uri.queryParameters[recoveryQueryKey] == '1') return true;
    if (uri.queryParameters['type'] == 'recovery') return true;
    if ((uri.queryParameters['token_hash'] ?? '').isNotEmpty) return true;
    if (uri.fragment.contains('type=recovery')) return true;
    final frag = uri.fragment.trim();
    if (frag.isEmpty) return false;
    try {
      return Uri.parse('http://local/?$frag').queryParameters['type'] ==
          'recovery';
    } catch (_) {
      return false;
    }
  }

  static String facebookRedirectTo({String? returnTo}) {
    if (!kIsWeb) return mobileFacebookCallback;

    final base = _webCallbackBase();
    final rt = returnTo?.trim();
    if (rt == null || rt.isEmpty) return base;

    final uri = Uri.parse(base);
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            returnToQueryKey: rt,
          },
        )
        .toString();
  }

  static String _webCallbackBase() {
    final base = Uri.base;
    final origin = base.origin;
    final host = base.host.toLowerCase();

    // fleaber.pt (landing, hub.html, /fleahub/) — nunca /auth-callback na raiz
    // (hosting estático → 404). Sempre voltar ao shell Flutter.
    if (host == 'fleaber.pt' || host == 'www.fleaber.pt') {
      return '$origin/fleahub/index.html';
    }

    // Deploy fleaber.pt/fleahub/ (base-href /fleahub/)
    if (base.path.contains('/fleahub')) {
      return '$origin/fleahub/index.html';
    }

    // flutter run -d chrome (dev)
    if (FleaberWebDeploy.useHashUrlOnWeb) {
      return '$origin/index.html';
    }
    return '$origin/auth-callback';
  }
}
