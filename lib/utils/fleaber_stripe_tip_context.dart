import 'dart:async';
import 'dart:convert';

import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '/backend/supabase/supabase.dart';
import '/fleaber_live_player/fleaber_live_player_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/utils/fleaber_logger.dart';
import '/utils/live_publish_cleanup.dart';

/// Gorjeta Stripe — restaurar directo após pagamento (como encomendas live).
class FleaberStripeTipContext {
  FleaberStripeTipContext._();

  static const _prefsKey = 'fleaber_pending_stripe_tip_v1';

  static Future<void> save({
    required String liveId,
    required String sellerId,
    String? tipId,
    String? playbackId,
    bool isLive = true,
    String? checkoutSessionId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'live_id': liveId.trim(),
        'seller_id': sellerId.trim(),
        if (tipId != null && tipId.trim().isNotEmpty) 'tip_id': tipId.trim(),
        if (playbackId != null && playbackId.trim().isNotEmpty)
          'playback_id': playbackId.trim(),
        'is_live': isLive,
        if (checkoutSessionId != null && checkoutSessionId.trim().isNotEmpty)
          'checkout_session_id': checkoutSessionId.trim(),
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

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static bool isTipSettled(String? status) =>
      status == 'completed' || status == 'paid';

  static Future<String?> tipStatus(String tipId) async {
    final id = tipId.trim();
    if (id.isEmpty) return null;
    try {
      final row = await SupaFlow.client
          .from('live_tips')
          .select('status')
          .eq('id', id)
          .maybeSingle();
      return row?['status']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Repete o settle do browser (success_url) quando o utilizador volta à app.
  static Future<void> settleTipStripeSession(String sessionId) async {
    final id = sessionId.trim();
    if (id.isEmpty) return;
    try {
      final session = SupaFlow.client.auth.currentSession;
      final token = session?.accessToken;
      if (token == null || token.isEmpty) return;

      final uri = Uri.parse(
        '${SupaFlow.supabaseUrl}/functions/v1/create-live-tip-checkout',
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
        'tip_settle_http',
        data: {
          'session_id': id,
          'http_status': res.statusCode,
        },
      );
    } catch (e) {
      FleaberLogger.instance.warning(
        'stripe.tip.settle',
        'falhou session_id=$id: $e',
      );
    }
  }

  static void goToLivePlayer(GoRouter router, Map<String, dynamic> ctx) {
    final liveId = ctx['live_id']?.toString().trim() ?? '';
    if (liveId.isEmpty) return;

    final playbackId = ctx['playback_id']?.toString().trim() ?? '';
    final sellerId = ctx['seller_id']?.toString().trim() ?? '';
    final isLive = ctx['is_live'] == true || ctx['is_live'] == 'true';

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

  /// Poll/settle após fechar browser Stripe (web ou mobile).
  static Future<bool> trySettlePendingTip() async {
    final ctx = await peek();
    if (ctx == null) return false;

    final sessionId = ctx['checkout_session_id']?.toString().trim() ?? '';
    if (sessionId.isNotEmpty) {
      await settleTipStripeSession(sessionId);
    }

    final tipId = ctx['tip_id']?.toString().trim() ?? '';
    if (tipId.isEmpty) return false;

    final status = await tipStatus(tipId);
    if (isTipSettled(status)) {
      await clear();
      FleaberLogger.instance.event('stripe.tip.settled', {
        'tip_id': tipId,
        'live_id': ctx['live_id'],
        'status': status,
      });
      return true;
    }
    return false;
  }

  static Future<void> tryResumeOnAppResumed(GoRouter router) async {
    final ctx = await peek();
    if (ctx == null) return;

    final liveId = ctx['live_id']?.toString().trim() ?? '';
    final broadcasting =
        await LivePublishCleanup.preferredActiveBroadcastId() ?? '';
    if (liveId.isNotEmpty && broadcasting.isEmpty) {
      goToLivePlayer(router, ctx);
    } else if (broadcasting.isNotEmpty) {
      unawaited(
        FleaberLogger.instance.event('stripe.tip.resume_skipped_broadcast', {
          'pending_live_id': liveId,
          'broadcast_live_id': broadcasting,
        }),
      );
    }

    if (await trySettlePendingTip()) {
      FleaberLogger.instance.event('stripe.tip.resume', {
        'tip_id': ctx['tip_id'],
        'live_id': ctx['live_id'],
      });
      return;
    }

    // Sessão pode ter sido liquidada sem tip_id local — limpar após 2h.
    final savedAt = DateTime.tryParse(ctx['saved_at']?.toString() ?? '');
    if (savedAt != null &&
        DateTime.now().toUtc().difference(savedAt) > const Duration(hours: 2)) {
      await clear();
    }
  }
}
