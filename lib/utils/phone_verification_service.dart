import 'package:supabase_flutter/supabase_flutter.dart';

import '/backend/supabase/supabase.dart';

/// Verificação SMS do telemóvel via Supabase Auth (após registo com email).
class PhoneVerificationService {
  /// Converte número PT (9 dígitos ou +351…) para E.164.
  static String? toE164(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('351') && digits.length >= 12) {
      return '+$digits';
    }
    if (digits.length == 9) {
      return '+351$digits';
    }
    if (digits.length >= 10 && digits.length <= 15) {
      return '+$digits';
    }
    return null;
  }

  /// [resend] true → pede novo SMS sem alterar o número outra vez.
  static Future<void> sendSmsCode(
    String phoneE164, {
    bool resend = false,
  }) async {
    final user = SupaFlow.client.auth.currentUser;
    if (user == null) {
      throw Exception('Inicia sessão antes de verificar o telemóvel.');
    }
    try {
      if (resend) {
        await SupaFlow.client.auth.resend(
          type: OtpType.phoneChange,
          phone: phoneE164,
        );
      } else {
        await SupaFlow.client.auth.updateUser(
          UserAttributes(phone: phoneE164),
        );
      }
    } on AuthException catch (e) {
      throw Exception(_friendlyAuthError(e));
    }
  }

  static String _friendlyAuthError(AuthException e) {
    final raw = e.message.toLowerCase();
    // Log técnico para diagnóstico (nunca no SnackBar).
    // ignore: avoid_print
    print('SMS_AUTH_ERR: ${e.message}');
    if (raw.contains('missing phone or otp in hook payload') ||
        raw.contains('hook secret') ||
        raw.contains('invalid payload sent to hook') ||
        (raw.contains('hook') && raw.contains('secret'))) {
      return 'Não foi possível enviar o SMS de verificação. '
          'Tenta novamente dentro de momentos ou contacta o suporte.';
    }
    if (raw.contains('rate limit') || raw.contains('too many')) {
      return 'Demasiados pedidos. Aguarda alguns minutos e tenta outra vez.';
    }
    if (raw.contains('invalid') && raw.contains('phone')) {
      return 'Número de telemóvel inválido. Confirma o formato (+351…).';
    }
    return 'Não foi possível verificar o telemóvel. Tenta novamente.';
  }

  static Future<void> verifySmsCode({
    required String phoneE164,
    required String token,
  }) async {
    final code = token.replaceAll(RegExp(r'\D'), '');
    if (code.length < 4) {
      throw Exception('Introduz o código recebido por SMS.');
    }
    try {
      await SupaFlow.client.auth.verifyOTP(
        type: OtpType.phoneChange,
        phone: phoneE164,
        token: code,
      );
    } on AuthException catch (e) {
      throw Exception(_friendlyAuthError(e));
    }
  }
}
