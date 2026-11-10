import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import '/auth/auth_manager.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/utils/fleaber_fcm_service.dart';
import '/utils/fleaber_oauth_redirect.dart';
import '/utils/login_remember_storage.dart';
import 'email_auth.dart';
import 'email_account_create_result.dart';

import 'supabase_user_provider.dart';

export 'email_account_create_result.dart';

export '/auth/base_auth_user_provider.dart';

/// Última falha do fluxo Facebook (mensagem no ecrã de login).
String? lastFacebookLoginFailureMessage;

class SupabaseAuthManager extends AuthManager
    with EmailSignInManager, FacebookSignInManager {
  static const _facebookOAuthTimeout = Duration(seconds: 90);

  @override
  Future<BaseAuthUser?> signInWithFacebook(
    BuildContext context, {
    String? returnTo,
  }) async {
    lastFacebookLoginFailureMessage = null;

    // Web: redirect completo — a pagina recarrega; recovery em main.dart.
    if (kIsWeb) {
      try {
        final redirectTo = FleaberOAuthRedirect.facebookRedirectTo(
          returnTo: returnTo,
        );
        final launched = await SupaFlow.client.auth.signInWithOAuth(
          OAuthProvider.facebook,
          redirectTo: redirectTo,
          authScreenLaunchMode: LaunchMode.platformDefault,
        );
        if (!launched) {
          lastFacebookLoginFailureMessage =
              'Nao foi possivel abrir o login do Facebook.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(lastFacebookLoginFailureMessage!)),
          );
        }
      } on AuthException catch (e) {
        lastFacebookLoginFailureMessage = 'Erro no Facebook: ${e.message}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lastFacebookLoginFailureMessage!)),
        );
      }
      return null;
    }

    StreamSubscription<AuthState>? authSub;
    try {
      final sessionCompleter = Completer<BaseAuthUser?>();
      authSub = SupaFlow.client.auth.onAuthStateChange.listen((data) {
        if (data.event != AuthChangeEvent.signedIn || data.session == null) {
          return;
        }
        final uid = currentUser?.uid ?? data.session!.user.id;
        if (uid.isEmpty || sessionCompleter.isCompleted) return;
        sessionCompleter.complete(currentUser);
      });

      final launched = await SupaFlow.client.auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: FleaberOAuthRedirect.mobileFacebookCallback,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!launched) {
        lastFacebookLoginFailureMessage =
            'Não foi possível abrir o browser para o login do Facebook.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lastFacebookLoginFailureMessage!)),
        );
        return null;
      }

      final user = await sessionCompleter.future.timeout(
        _facebookOAuthTimeout,
        onTimeout: () => null,
      );
      if (user != null && (user.uid ?? '').isNotEmpty) {
        return user;
      }

      lastFacebookLoginFailureMessage =
          'O login no Facebook não voltou à app a tempo. '
          'Se no browser apareceu «Invalid Scopes: email», activa a permissão email em '
          'Meta Developers → Fleaber → Use cases → Authentication and Account Creation → Add email. '
          'Redirect URI na Meta: ${SupaFlow.supabaseUrl}/auth/v1/callback';
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tempo esgotado ao iniciar sessão com Facebook.'),
        ),
      );
      return null;
    } on AuthException catch (e) {
      lastFacebookLoginFailureMessage = 'Erro no Facebook: ${e.message}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lastFacebookLoginFailureMessage!)),
      );
      return null;
    } catch (e) {
      lastFacebookLoginFailureMessage = 'Erro no Facebook: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lastFacebookLoginFailureMessage!)),
      );
      return null;
    } finally {
      await authSub?.cancel();
    }
  }

  @override
  Future signOut() async {
    await LoginRememberStorage.purgeLegacyPasswords();
    try {
      await FleaberFcmService.onLogout();
    } catch (_) {}
    return SupaFlow.client.auth.signOut();
  }

  @override
  Future deleteUser(BuildContext context) async {
    try {
      if (!loggedIn) {
        print('Error: delete user attempted with no logged in user!');
        return;
      }
      await currentUser?.delete();
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.message}')),
      );
    }
  }

  @override
  Future updateEmail({
    required String email,
    required BuildContext context,
  }) async {
    try {
      if (!loggedIn) {
        print('Error: update email attempted with no logged in user!');
        return;
      }
      await currentUser?.updateEmail(email);
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.message}')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Email change confirmation email sent')),
    );
  }

  Future updatePassword({
    required String newPassword,
    required BuildContext context,
  }) async {
    try {
      if (!loggedIn) {
        print('Error: update password attempted with no logged in user!');
        return;
      }
      await currentUser?.updatePassword(newPassword);
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.message}')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Password updated successfully')),
    );
  }

  /// Confirma a palavra-passe actual, define a nova e regista sessão.
  /// O Supabase Auth pode enviar email de alerta de segurança (conforme projecto).
  Future<bool> changePasswordWithReauth({
    required String currentPassword,
    required String newPassword,
    required BuildContext context,
  }) async {
    final email = (currentUser?.email ?? '').trim();
    if (!loggedIn || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inicia sessão com email para alterar a palavra-passe.'),
        ),
      );
      return false;
    }
    try {
      await SupaFlow.client.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
      await SupaFlow.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      await refreshUser();
      return true;
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      final pt = msg.contains('invalid') || msg.contains('credentials')
          ? 'Palavra-passe actual incorrecta.'
          : e.message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(pt)),
      );
      return false;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
      return false;
    }
  }

  @override
  Future resetPassword({
    required String email,
    required BuildContext context,
    String? redirectTo,
  }) async {
    try {
      await SupaFlow.client.auth
          .resetPasswordForEmail(email, redirectTo: redirectTo);
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.message}')),
      );
      return null;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Se o e-mail existir, enviámos o link. Vê a tua caixa de entrada.',
        ),
      ),
    );
  }

  @override
  Future<BaseAuthUser?> signInWithEmail(
    BuildContext context,
    String email,
    String password,
  ) =>
      _signInOrCreateAccount(
        context,
        () => emailSignInFunc(email, password),
      );

  @override
  Future<BaseAuthUser?> createAccountWithEmail(
    BuildContext context,
    String email,
    String password,
  ) async {
    final result = await createEmailAccount(
      context,
      email: email,
      password: password,
    );
    if (result.status == EmailAccountCreateStatus.signedIn) {
      return currentUser;
    }
    return null;
  }

  /// Registo completo: sessão imediata **ou** confirmação de e-mail pendente.
  Future<EmailAccountCreateResult> createEmailAccount(
    BuildContext context, {
    required String email,
    required String password,
    String? fullName,
    String? phone,
    int? formMs,
    String honeypot = '',
    String? challengeToken,
  }) async {
    try {
      final result = await emailCreateAccountDetailed(
        email: email,
        password: password,
        fullName: fullName,
        phone: phone,
        formMs: formMs,
        honeypot: honeypot,
        challengeToken: challengeToken,
      );

      if (result.status == EmailAccountCreateStatus.signedIn &&
          result.user != null) {
        final authUser = FleaberSupabaseUser(result.user);
        currentUser = authUser;
        AppStateNotifier.instance.update(authUser);
        return result;
      }

      if (result.status == EmailAccountCreateStatus.pendingEmailConfirmation) {
        return result;
      }

      final msg = result.errorMessage ??
          'Não foi possível criar a conta. Tenta outra vez.';
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Dialog garante leitura (SnackBar no Flutter Web por vezes fora da árvore a11y).
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Registo'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return result;
    } on AuthException catch (e) {
      final errorMsg = mapAuthExceptionToPt(e, forSignUp: true);
      debugPrint('AUTH_SIGNUP_ERR: ${e.message}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg)),
        );
      }
      return EmailAccountCreateResult.failed(errorMsg);
    }
  }

  /// Tries to sign in using Supabase Auth.
  Future<BaseAuthUser?> _signInOrCreateAccount(
    BuildContext context,
    Future<User?> Function() signInFunc, {
    bool forSignUp = false,
  }) async {
    try {
      final user = await signInFunc();
      final authUser = user == null ? null : FleaberSupabaseUser(user);

      // Update currentUser here in case user info needs to be used immediately
      // after a user is signed in. This should be handled by the user stream,
      // but adding here too in case of a race condition where the user stream
      // doesn't assign the currentUser in time.
      if (authUser != null) {
        currentUser = authUser;
        AppStateNotifier.instance.update(authUser);
      }
      return authUser;
    } on AuthException catch (e) {
      final errorMsg = mapAuthExceptionToPt(e, forSignUp: forSignUp);
      debugPrint('AUTH_SIGNIN_ERR: ${e.message}');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg)),
      );
      return null;
    }
  }
}
