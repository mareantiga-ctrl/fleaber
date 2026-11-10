import 'package:supabase_flutter/supabase_flutter.dart';

/// E74 — Sessão guest UC (create / resolve / revoke).
/// Não acede a encomendas/reservas de outros: RPCs só devolvem a própria sessão.
class CommerceGuestSessionService {
  CommerceGuestSessionService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _minTokenLen = 32;

  static bool isValidGuestToken(String token) =>
      token.trim().length >= _minTokenLen;

  static Map<String, dynamic> checkoutGuestParamsStatic(String token) => {
        'p_guest_token': token.trim(),
      };

  Future<GuestSessionCreateResult> create({int ttlSeconds = 86400}) async {
    final raw = await _client.rpc(
      'batata_commerce_guest_session_create',
      params: {'p_ttl_seconds': ttlSeconds.clamp(900, 86400 * 7)},
    );
    final map = _asMap(raw);
    if (map['ok'] != true) {
      return GuestSessionCreateResult.fail(
        map['error']?.toString() ?? 'guest_create_failed',
      );
    }
    final token = map['guest_token']?.toString() ?? '';
    if (token.length < _minTokenLen) {
      return GuestSessionCreateResult.fail('invalid_guest_token_returned');
    }
    return GuestSessionCreateResult.ok(
      sessionId: map['guest_session_id']?.toString() ?? '',
      token: token,
      expiresAt: DateTime.tryParse(map['expires_at']?.toString() ?? ''),
    );
  }

  Future<GuestSessionResolveResult> resolve(String token) async {
    final t = token.trim();
    if (t.length < _minTokenLen) {
      return GuestSessionResolveResult.fail('invalid_guest_token');
    }
    final raw = await _client.rpc(
      'batata_commerce_guest_session_resolve',
      params: {'p_guest_token': t},
    );
    final map = _asMap(raw);
    if (map['ok'] != true) {
      return GuestSessionResolveResult.fail(
        map['error']?.toString() ?? 'guest_resolve_failed',
      );
    }
    return GuestSessionResolveResult.ok(
      sessionId: map['guest_session_id']?.toString() ?? '',
      expiresAt: DateTime.tryParse(map['expires_at']?.toString() ?? ''),
    );
  }

  Future<GuestSessionRevokeResult> revoke(String token) async {
    final t = token.trim();
    if (t.length < _minTokenLen) {
      return GuestSessionRevokeResult.fail('invalid_guest_token');
    }
    final raw = await _client.rpc(
      'batata_commerce_guest_session_revoke',
      params: {'p_guest_token': t},
    );
    final map = _asMap(raw);
    if (map['ok'] != true) {
      return GuestSessionRevokeResult.fail(
        map['error']?.toString() ?? 'guest_revoke_failed',
      );
    }
    return GuestSessionRevokeResult.ok(
      sessionId: map['guest_session_id']?.toString() ?? '',
    );
  }

  /// Params seguros para checkout begin (só o token próprio).
  Map<String, dynamic> checkoutGuestParams(String token) =>
      checkoutGuestParamsStatic(token);

  /// Monta args de `batata_commerce_checkout_begin` para convidado (sem pagamento).
  /// Não inclui provas Stripe/Ifthenpay — só pré-pagamento / off_platform.
  static Map<String, dynamic> checkoutBeginParams({
    required String guestToken,
    required List<Map<String, dynamic>> lines,
    String shippingMethod = 'hand',
    String paymentRail = 'off_platform',
    Map<String, dynamic>? delivery,
    String? liveId,
    String? clientIdempotencyKey,
    bool confirmRemainder = false,
  }) {
    final t = guestToken.trim();
    if (t.length < _minTokenLen) {
      throw ArgumentError('invalid_guest_token');
    }
    return {
      'p_lines': lines,
      'p_shipping_method': shippingMethod,
      'p_payment_rail': paymentRail,
      'p_delivery': delivery ?? <String, dynamic>{},
      'p_live_id': liveId,
      'p_client_idempotency_key': clientIdempotencyKey,
      'p_confirm_remainder': confirmRemainder,
      'p_guest_token': t,
    };
  }

  Future<Map<String, dynamic>> checkoutBegin({
    required String guestToken,
    required List<Map<String, dynamic>> lines,
    String shippingMethod = 'hand',
    String paymentRail = 'off_platform',
    Map<String, dynamic>? delivery,
    String? liveId,
    String? clientIdempotencyKey,
    bool confirmRemainder = false,
  }) async {
    final raw = await _client.rpc(
      'batata_commerce_checkout_begin',
      params: checkoutBeginParams(
        guestToken: guestToken,
        lines: lines,
        shippingMethod: shippingMethod,
        paymentRail: paymentRail,
        delivery: delivery,
        liveId: liveId,
        clientIdempotencyKey: clientIdempotencyKey,
        confirmRemainder: confirmRemainder,
      ),
    );
    return _asMap(raw);
  }

  Future<Map<String, dynamic>> checkoutRevalidate({
    required String guestToken,
    required List<Map<String, dynamic>> lines,
    required String sellerId,
    String shippingMethod = 'hand',
  }) async {
    final t = guestToken.trim();
    if (t.length < _minTokenLen) {
      return {'ok': false, 'error': 'invalid_guest_token'};
    }
    final raw = await _client.rpc(
      'batata_commerce_checkout_revalidate',
      params: {
        'p_lines': lines,
        'p_shipping_method': shippingMethod,
        'p_seller_id': sellerId,
        'p_guest_token': t,
      },
    );
    return _asMap(raw);
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }
}

class GuestSessionCreateResult {
  GuestSessionCreateResult._({
    required this.ok,
    this.sessionId,
    this.token,
    this.expiresAt,
    this.error,
  });

  factory GuestSessionCreateResult.ok({
    required String sessionId,
    required String token,
    DateTime? expiresAt,
  }) =>
      GuestSessionCreateResult._(
        ok: true,
        sessionId: sessionId,
        token: token,
        expiresAt: expiresAt,
      );

  factory GuestSessionCreateResult.fail(String error) =>
      GuestSessionCreateResult._(ok: false, error: error);

  final bool ok;
  final String? sessionId;
  final String? token;
  final DateTime? expiresAt;
  final String? error;
}

class GuestSessionResolveResult {
  GuestSessionResolveResult._({
    required this.ok,
    this.sessionId,
    this.expiresAt,
    this.error,
  });

  factory GuestSessionResolveResult.ok({
    required String sessionId,
    DateTime? expiresAt,
  }) =>
      GuestSessionResolveResult._(
        ok: true,
        sessionId: sessionId,
        expiresAt: expiresAt,
      );

  factory GuestSessionResolveResult.fail(String error) =>
      GuestSessionResolveResult._(ok: false, error: error);

  final bool ok;
  final String? sessionId;
  final DateTime? expiresAt;
  final String? error;
}

class GuestSessionRevokeResult {
  GuestSessionRevokeResult._({
    required this.ok,
    this.sessionId,
    this.error,
  });

  factory GuestSessionRevokeResult.ok({required String sessionId}) =>
      GuestSessionRevokeResult._(ok: true, sessionId: sessionId);

  factory GuestSessionRevokeResult.fail(String error) =>
      GuestSessionRevokeResult._(ok: false, error: error);

  final bool ok;
  final String? sessionId;
  final String? error;
}
