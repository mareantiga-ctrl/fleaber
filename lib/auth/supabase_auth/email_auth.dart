import 'package:flutter/foundation.dart' show debugPrint;

import '/backend/supabase/supabase.dart';
import '/utils/fleaber_oauth_redirect.dart';
import 'email_account_create_result.dart';
import 'signup_device_id.dart';

Future<User?> emailSignInFunc(
  String email,
  String password,
) async {
  final AuthResponse res = await SupaFlow.client.auth
      .signInWithPassword(email: email.trim(), password: password);
  return res.user;
}

/// Mensagem PT-PT a partir de [AuthException] (sem expor detalhes internos).
String mapAuthExceptionToPt(AuthException e, {required bool forSignUp}) {
  final raw = e.message.toLowerCase();
  final code = (e.code ?? '').toLowerCase();

  if (code.contains('over_email_send_rate_limit') ||
      raw.contains('rate limit') ||
      raw.contains('email rate limit')) {
    return 'Demasiados e-mails de verificação. Espera uns minutos e tenta outra vez.';
  }
  if (raw.contains('limite diário de novos registos') ||
      raw.contains('daily_smtp_budget')) {
    return 'Atingimos o limite diário de novos registos. Tenta amanhã.';
  }
  if (raw.contains('verificação rápida') ||
      raw.contains('challenge_required') ||
      raw.contains('verificação incorrecta')) {
    return 'Precisamos de uma verificação rápida antes de criar a conta.';
  }
  if (raw.contains('domínio de e-mail não é aceite') ||
      raw.contains('denied_domain')) {
    return 'Este domínio de e-mail não é aceite. Usa outro e-mail.';
  }
  if (raw.contains('user already registered') ||
      raw.contains('already been registered') ||
      raw.contains('already in use') ||
      raw.contains('already registered')) {
    return 'Este e-mail já tem conta Fleaber. Entra ou recupera a palavra-passe.';
  }
  if (raw.contains('password') &&
      (raw.contains('weak') ||
          raw.contains('least') ||
          raw.contains('short') ||
          raw.contains('characters'))) {
    return 'A palavra-passe é demasiado fraca. Usa pelo menos 6 caracteres.';
  }
  if (raw.contains('invalid') && raw.contains('email')) {
    return 'O e-mail não é válido. Confirma e tenta outra vez.';
  }
  if (raw.contains('email not confirmed') ||
      raw.contains('email_not_confirmed') ||
      code.contains('email_not_confirmed')) {
    return 'Confirma o e-mail que te enviámos antes de entrar.';
  }
  if (raw.contains('invalid login') || raw.contains('invalid credentials')) {
    return 'E-mail ou palavra-passe incorrectos.';
  }
  if (forSignUp) {
    return 'Não foi possível criar a conta. Verifica os dados e tenta outra vez.';
  }
  return 'Não foi possível entrar. Verifica os dados e tenta outra vez.';
}

/// Registo com metadados + redirect de confirmação.
///
/// Distingue sucesso com sessão vs conta criada à espera de confirmação de e-mail
/// (não trata confirmação pendente como falha).
Future<EmailAccountCreateResult> emailCreateAccountDetailed({
  required String email,
  required String password,
  String? fullName,
  String? phone,
  String userType = 'vendedor',
  int? formMs,
  String honeypot = '',
  String? challengeToken,
}) async {
  final trimmed = email.trim();
  final deviceId = await fleaberSignupDeviceId();
  final meta = <String, dynamic>{
    if (fullName != null && fullName.trim().isNotEmpty)
      'full_name': fullName.trim(),
    if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    'user_type': userType,
    'device_id': deviceId,
    'form_ms': formMs ?? 999999,
    'hp': honeypot,
    if (challengeToken != null && challengeToken.isNotEmpty)
      'challenge_token': challengeToken,
  };

  late final AuthResponse res;
  try {
    res = await SupaFlow.client.auth.signUp(
      email: trimmed,
      password: password,
      emailRedirectTo: FleaberOAuthRedirect.emailConfirmRedirectTo(),
      data: meta,
    );
  } on AuthException catch (e) {
    debugPrint('AUTH_SIGNUP_ERR: ${e.message}');
    return EmailAccountCreateResult.failed(
      mapAuthExceptionToPt(e, forSignUp: true),
    );
  }

  final created = res.user;
  if (created == null) {
    return EmailAccountCreateResult.failed(
      'Não foi possível criar a conta. Tenta outra vez.',
    );
  }

  // Supabase: re-signup do mesmo e-mail pode devolver user sem identities.
  final identities = created.identities;
  if (identities != null && identities.isEmpty) {
    return EmailAccountCreateResult.failed(
      'Este e-mail já tem conta Fleaber. Entra ou recupera a palavra-passe.',
    );
  }

  if (res.session != null) {
    return EmailAccountCreateResult.signedIn(created);
  }

  // Sem sessão: tipicamente confirmação de e-mail activa.
  try {
    final signIn = await SupaFlow.client.auth.signInWithPassword(
      email: trimmed,
      password: password,
    );
    if (signIn.session != null && signIn.user != null) {
      return EmailAccountCreateResult.signedIn(signIn.user!);
    }
  } on AuthException catch (e) {
    final raw = e.message.toLowerCase();
    final code = (e.code ?? '').toLowerCase();
    final needsConfirm = raw.contains('email not confirmed') ||
        raw.contains('email_not_confirmed') ||
        code.contains('email_not_confirmed') ||
        created.emailConfirmedAt == null;
    if (needsConfirm) {
      return EmailAccountCreateResult.pendingEmailConfirmation(created);
    }
    debugPrint('AUTH_SIGNUP_LOGIN_ERR: ${e.message}');
    return EmailAccountCreateResult.failed(
      mapAuthExceptionToPt(e, forSignUp: true),
    );
  } catch (e) {
    debugPrint('AUTH_SIGNUP_LOGIN_ERR: $e');
  }

  if (created.emailConfirmedAt == null) {
    return EmailAccountCreateResult.pendingEmailConfirmation(created);
  }
  return EmailAccountCreateResult.signedIn(created);
}

/// Compat: devolve user só se houver sessão utilizável; senão null.
@Deprecated('Prefer emailCreateAccountDetailed')
Future<User?> emailCreateAccountFunc(
  String email,
  String password,
) async {
  final result = await emailCreateAccountDetailed(
    email: email,
    password: password,
  );
  if (result.status == EmailAccountCreateStatus.signedIn) {
    return result.user;
  }
  if (result.status == EmailAccountCreateStatus.pendingEmailConfirmation) {
    // Comportamento legado devolvia null — callers novos usam Detailed.
    return null;
  }
  if (result.errorMessage != null) {
    throw AuthException(result.errorMessage!);
  }
  return null;
}
