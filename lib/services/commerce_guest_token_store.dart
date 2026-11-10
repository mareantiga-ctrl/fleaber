import 'package:shared_preferences/shared_preferences.dart';

import '/services/commerce_guest_session_service.dart';

/// Persistência local do token guest UC (browser + Android).
/// Só o token próprio — nunca dados de outros utilizadores.
abstract final class CommerceGuestTokenStore {
  static const _prefsKey = 'fleaber_uc_guest_token_v1';

  static Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_prefsKey)?.trim() ?? '';
    if (!CommerceGuestSessionService.isValidGuestToken(t)) return null;
    return t;
  }

  static Future<void> write(String token) async {
    final t = token.trim();
    if (!CommerceGuestSessionService.isValidGuestToken(t)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, t);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Garante token válido: resolve o guardado ou cria sessão nova.
  static Future<String?> ensureToken({
    CommerceGuestSessionService? service,
    int ttlSeconds = 86400,
  }) async {
    final svc = service ?? CommerceGuestSessionService();
    final existing = await read();
    if (existing != null) {
      final resolved = await svc.resolve(existing);
      if (resolved.ok) return existing;
      await clear();
    }
    final created = await svc.create(ttlSeconds: ttlSeconds);
    if (!created.ok || created.token == null) return null;
    await write(created.token!);
    return created.token;
  }
}
