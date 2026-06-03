import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Credenciais guardadas só neste dispositivo (memorizar login).
class LoginRememberStorage {
  LoginRememberStorage._();

  static const _kRemember = 'fleaber_login_remember_v1';
  static const _kEmail = 'fleaber_login_email_v1';
  static const _kPassword = 'fleaber_login_password_v1';

  static Future<bool> isRememberEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kRemember) ?? false;
  }

  static Future<({String email, String password})?> loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_kRemember) ?? false)) return null;
    final email = prefs.getString(_kEmail)?.trim() ?? '';
    final encoded = prefs.getString(_kPassword);
    if (email.isEmpty || encoded == null || encoded.isEmpty) return null;
    try {
      final password = utf8.decode(base64Decode(encoded));
      return (email: email, password: password);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRemember, true);
    await prefs.setString(_kEmail, email.trim());
    await prefs.setString(
      _kPassword,
      base64Encode(utf8.encode(password)),
    );
  }

  static Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRemember, false);
    await prefs.remove(_kEmail);
    await prefs.remove(_kPassword);
  }
}
