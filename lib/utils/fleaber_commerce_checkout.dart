import 'dart:convert';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/services/commerce_guest_session_service.dart';
import '/services/commerce_guest_token_store.dart';

/// Phase 4 — canonical checkout revalidate / begin (server authority).
/// Convidado (sem sessão auth): anexa `p_guest_token` via [CommerceGuestTokenStore].
class FleaberCommerceCheckout {
  FleaberCommerceCheckout._();

  static Future<String?> _guestTokenIfNeeded() async {
    if (currentUserUid.trim().isNotEmpty) return null;
    return CommerceGuestTokenStore.ensureToken();
  }

  static Future<Map<String, dynamic>> revalidate({
    required List<Map<String, dynamic>> lines,
    required String shippingMethod,
    String? sellerId,
    String? guestToken,
  }) async {
    final token = guestToken?.trim().isNotEmpty == true
        ? guestToken!.trim()
        : await _guestTokenIfNeeded();
    final raw = await SupaFlow.client.rpc(
      'batata_commerce_checkout_revalidate',
      params: {
        'p_lines': lines,
        'p_shipping_method': shippingMethod,
        if (sellerId != null && sellerId.trim().isNotEmpty)
          'p_seller_id': sellerId.trim(),
        if (token != null &&
            CommerceGuestSessionService.isValidGuestToken(token))
          'p_guest_token': token,
      },
    );
    return _asMap(raw);
  }

  static Future<Map<String, dynamic>> begin({
    required List<Map<String, dynamic>> lines,
    required String shippingMethod,
    required String paymentRail,
    Map<String, dynamic>? delivery,
    String? liveId,
    String? clientIdempotencyKey,
    bool confirmRemainder = false,
    String? guestToken,
  }) async {
    final token = guestToken?.trim().isNotEmpty == true
        ? guestToken!.trim()
        : await _guestTokenIfNeeded();
    final raw = await SupaFlow.client.rpc(
      'batata_commerce_checkout_begin',
      params: {
        'p_lines': lines,
        'p_shipping_method': shippingMethod,
        'p_payment_rail': paymentRail,
        'p_delivery': delivery ?? <String, dynamic>{},
        if (liveId != null && liveId.trim().isNotEmpty) 'p_live_id': liveId.trim(),
        if (clientIdempotencyKey != null && clientIdempotencyKey.trim().isNotEmpty)
          'p_client_idempotency_key': clientIdempotencyKey.trim(),
        'p_confirm_remainder': confirmRemainder,
        if (token != null &&
            CommerceGuestSessionService.isValidGuestToken(token))
          'p_guest_token': token,
      },
    );
    return _asMap(raw);
  }

  static Future<Map<String, dynamic>> release(String attemptId, {String reason = 'abandoned'}) async {
    final raw = await SupaFlow.client.rpc(
      'batata_commerce_checkout_release',
      params: {
        'p_attempt_id': attemptId,
        'p_reason': reason,
      },
    );
    return _asMap(raw);
  }

  static Map<String, dynamic> linePayload({
    required String productId,
    String? liveItemId,
    String? reservationRequestId,
    required int quantity,
  }) {
    return {
      'product_id': productId,
      if (liveItemId != null && liveItemId.isNotEmpty) 'live_item_id': liveItemId,
      if (reservationRequestId != null && reservationRequestId.isNotEmpty)
        'reservation_request_id': reservationRequestId,
      'quantity': quantity < 1 ? 1 : quantity,
    };
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return {'ok': false, 'error': 'unexpected_rpc_shape', 'raw': '$raw'};
  }

  static bool isOk(Map<String, dynamic> m) => m['ok'] == true;

  static String? currentBuyerId() {
    final uid = currentUserUid.trim();
    return uid.isEmpty ? null : uid;
  }
}
