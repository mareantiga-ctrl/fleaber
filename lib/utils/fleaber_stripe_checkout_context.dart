import 'dart:convert';

import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '/backend/supabase/supabase.dart';
import '/fleaber_live_player/fleaber_live_player_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/order_cancel_eligibility.dart';
import '/utils/fleaber_logger.dart';
import '/utils/live_raffle_service.dart';
import '/utils/live_reservation_queue_service.dart';

/// Contexto de checkout Stripe iniciado no live — restaurado se o deep link perder query params.
class FleaberStripeCheckoutContext {
  FleaberStripeCheckoutContext._();

  static const _prefsKey = 'fleaber_pending_stripe_checkout_v1';

  static Future<void> save({
    required String orderId,
    required String productId,
    String? liveId,
    String? playbackId,
    bool? isLive,
    String? sellerId,
    String? liveItemId,
    String? reservationRequestId,
    String? checkoutSessionId,
    String? bagOrdersJson,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'order_id': orderId,
        'product_id': productId,
        if (liveId != null && liveId.trim().isNotEmpty) 'live_id': liveId.trim(),
        if (playbackId != null && playbackId.trim().isNotEmpty)
          'playback_id': playbackId.trim(),
        if (isLive != null) 'is_live': isLive,
        if (sellerId != null && sellerId.trim().isNotEmpty)
          'seller_id': sellerId.trim(),
        if (liveItemId != null && liveItemId.trim().isNotEmpty)
          'live_item_id': liveItemId.trim(),
        if (reservationRequestId != null &&
            reservationRequestId.trim().isNotEmpty)
          'reservation_request_id': reservationRequestId.trim(),
        if (checkoutSessionId != null && checkoutSessionId.trim().isNotEmpty)
          'checkout_session_id': checkoutSessionId.trim(),
        if (bagOrdersJson != null && bagOrdersJson.trim().isNotEmpty)
          'bag_orders_json': bagOrdersJson.trim(),
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  static Future<Map<String, dynamic>?> peek() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> loadAndClear() async {
    final data = await peek();
    if (data != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    }
    return data;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Volta ao directo onde o checkout começou (live player).
  static void goToLivePlayer(GoRouter router, Map<String, dynamic> ctx) {
    final liveId = ctx['live_id']?.toString().trim() ?? '';
    if (liveId.isEmpty) return;

    final playbackId = ctx['playback_id']?.toString().trim() ?? '';
    final sellerId = ctx['seller_id']?.toString().trim() ?? '';
    final isLive = _boolFrom(ctx['is_live']);

    router.goNamed(
      FleaberLivePlayerWidget.routeName,
      queryParameters: <String, String?>{
        'liveId': serializeParam(liveId, ParamType.String),
        'playbackId': serializeParam(
          playbackId.isEmpty ? null : playbackId,
          ParamType.String,
        ),
        'isLive': serializeParam(isLive, ParamType.bool),
        'sellerId': serializeParam(
          sellerId.isEmpty ? null : sellerId,
          ParamType.String,
        ),
      }.withoutNulls,
    );
  }

  /// Quando o deep link falha, o utilizador volta à app em `/` — regressa ao directo e reconcilia pagamento.
  static Future<bool> tryResumeOnAppResumed(GoRouter router) async {
    final pending = await peek();
    if (pending == null) return false;

    final liveId = pending['live_id']?.toString().trim() ?? '';
    if (liveId.isEmpty) return false;

    final orderId = pending['order_id']?.toString().trim() ?? '';

    // Regressar já ao directo (não esperar por `pago` nem ficar em `/` ou detalhes).
    goToLivePlayer(router, pending);

    var status = orderId.isEmpty ? null : await orderStatus(orderId);
    if (status != 'pago' && orderId.isNotEmpty) {
      final sessionId = pending['checkout_session_id']?.toString().trim() ?? '';
      if (sessionId.isNotEmpty) {
        await settleCheckoutSession(sessionId);
        status = await orderStatus(orderId);
      }
    }

    await FleaberLogger.instance.logStripe(
      'resume',
      data: {
        'live_id': liveId,
        'order_id': orderId.isEmpty ? null : orderId,
        'status': status,
      },
    );

    if (status == 'pago') {
      await _reconcilePendingBagOrders(pending, liveId: liveId);
      await loadAndClear();
    }
    return true;
  }

  static bool? _boolFrom(Object? v) {
    if (v is bool) return v;
    if (v is String) {
      if (v == 'true') return true;
      if (v == 'false') return false;
    }
    return null;
  }

  static Future<String?> orderStatus(String orderId) async {
    try {
      final rows = await OrdersTable().querySingleRow(
        queryFn: (q) => q.eqOrNull('id', orderId),
      );
      if (rows.isEmpty) return null;
      return normalizeOrderStatusKey(rows.first.status);
    } catch (_) {
      return null;
    }
  }

  /// Repete o settle do browser (success_url) quando o utilizador volta à app.
  static Future<void> settleCheckoutSession(String sessionId) async {
    final id = sessionId.trim();
    if (id.isEmpty) return;
    try {
      final session = SupaFlow.client.auth.currentSession;
      final token = session?.accessToken;
      if (token == null || token.isEmpty) return;

      final uri = Uri.parse(
        '${SupaFlow.supabaseUrl}/functions/v1/create-payment-intent',
      ).replace(
        queryParameters: {
          'checkout_return': 'success',
          'session_id': id,
        },
      );
      final apikey = SupaFlow.client.headers['apikey'] ??
          SupaFlow.client.headers['Apikey'] ??
          '';
      final res = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          if (apikey.isNotEmpty) 'apikey': apikey,
        },
      );
      await FleaberLogger.instance.logStripe(
        'settle_http',
        data: {
          'session_id': id,
          'http_status': res.statusCode,
        },
      );
    } catch (e) {
      FleaberLogger.instance.warning(
        'stripe.checkout.settle',
        'falhou session_id=$id: $e',
      );
    }
  }

  static Future<String?> _orderStatus(String orderId) => orderStatus(orderId);

  static Future<void> _trySettleCheckoutSession(String sessionId) =>
      settleCheckoutSession(sessionId);

  /// Reconcilia saco multi-artigo após Stripe pago.
  static Future<void> reconcilePendingBagOrders(
    Map<String, dynamic> pending, {
    required String liveId,
  }) =>
      _reconcilePendingBagOrders(pending, liveId: liveId);

  static Future<void> _reconcilePendingBagOrders(
    Map<String, dynamic> pending, {
    required String liveId,
  }) async {
    final raw = pending['bag_orders_json']?.toString().trim() ?? '';
    if (raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final entry in list) {
          if (entry is! Map) continue;
          final map = Map<String, dynamic>.from(entry);
          final oid = map['order_id']?.toString().trim() ?? '';
          if (oid.isEmpty) continue;
          final res = await LiveReservationQueueService().reconcileStripePaidOrder(
            orderId: oid,
            reservationRequestId:
                map['reservation_request_id']?.toString(),
          );
          await FleaberLogger.instance.logStripe(
            'reconcile_bag_line',
            data: {'order_id': oid, 'live_id': liveId, 'result': res},
          );
          await LiveRaffleService.tryAwardPurchaseBonus(oid);
        }
        return;
      } catch (_) {}
    }
    final orderId = pending['order_id']?.toString().trim() ?? '';
    if (orderId.isEmpty) return;
    final reconcile = await LiveReservationQueueService().reconcileStripePaidOrder(
      orderId: orderId,
      reservationRequestId: pending['reservation_request_id']?.toString(),
    );
    await FleaberLogger.instance.logStripe(
      'reconcile',
      data: {'order_id': orderId, 'live_id': liveId, 'result': reconcile},
    );
    await LiveRaffleService.tryAwardPurchaseBonus(orderId);
  }
}
