import 'dart:convert';

import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/backend/supabase/supabase.dart';
import '/fleaber_live_player/fleaber_live_player_widget.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/utils/fleaber_logger.dart';

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

  static Future<void> tryResumeOnAppResumed(GoRouter router) async {
    final ctx = await peek();
    if (ctx == null) return;

    final tipId = ctx['tip_id']?.toString().trim() ?? '';
    if (tipId.isNotEmpty) {
      try {
        final row = await SupaFlow.client
            .from('live_tips')
            .select('status, amount_eur')
            .eq('id', tipId)
            .maybeSingle();
        final status = row?['status']?.toString() ?? '';
        if (status == 'paid') {
          await clear();
          FleaberLogger.instance.event('stripe.tip.resume', {
            'tip_id': tipId,
            'live_id': ctx['live_id'],
            'status': status,
          });
          goToLivePlayer(router, ctx);
          return;
        }
      } catch (e) {
        FleaberLogger.instance.error('stripe.tip.resume', e);
      }
    }

    // Sessão pode ter sido liquidada sem tip_id local — limpar após 2h.
    final savedAt = DateTime.tryParse(ctx['saved_at']?.toString() ?? '');
    if (savedAt != null &&
        DateTime.now().toUtc().difference(savedAt) > const Duration(hours: 2)) {
      await clear();
    }
  }
}
