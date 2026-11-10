import 'package:shared_preferences/shared_preferences.dart';

/// Preferências de login neste dispositivo.
///
/// **Nunca** guarda a password (nem em claro nem em base64).
/// A sessão persistente fica a cargo do Supabase Auth (refresh token seguro).
/// «Memorizar» = apenas o e-mail para pré-preencher o formulário.
class LoginRememberStorage {
  LoginRememberStorage._();

  static const _kRemember = 'fleaber_login_remember_v1';
  static const _kEmail = 'fleaber_login_email_v1';

  /// Chaves legadas (password recuperável) — sempre removidas no acesso.
  static const _kPasswordLegacy = 'fleaber_login_password_v1';
  static const _legacyPasswordKeys = <String>[
    _kPasswordLegacy,
    'fleaber_login_password',
    'login_password',
    'remembered_password',
  ];

  /// Remove quaisquer restos de password em SharedPreferences (upgrade seguro).
  static Future<void> purgeLegacyPasswords() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _legacyPasswordKeys) {
      if (prefs.containsKey(key)) {
        await prefs.remove(key);
      }
    }
  }

  static Future<bool> isRememberEnabled() async {
    await purgeLegacyPasswords();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kRemember) ?? false;
  }

  /// Só e-mail. Password nunca é devolvida.
  static Future<String?> loadRememberedEmail() async {
    await purgeLegacyPasswords();
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_kRemember) ?? false)) return null;
    final email = prefs.getString(_kEmail)?.trim() ?? '';
    if (email.isEmpty) return null;
    return email;
  }

  /// @Deprecated — usar [loadRememberedEmail]. Mantido só para não partir imports.
  static Future<({String email, String password})?> loadCredentials() async {
    final email = await loadRememberedEmail();
    if (email == null) return null;
    return (email: email, password: '');
  }

  static Future<void> saveRememberedEmail(String email) async {
    await purgeLegacyPasswords();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRemember, true);
    await prefs.setString(_kEmail, email.trim());
  }

  /// @Deprecated — password é ignorada de propósito.
  static Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {
    // password intencionalmente ignorada (não persistir).
    await saveRememberedEmail(email);
  }

  static Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRemember, false);
    await prefs.remove(_kEmail);
    await purgeLegacyPasswords();
  }
}
