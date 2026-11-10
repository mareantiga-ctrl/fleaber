import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';

/// Projecto Spy — emparelhamento PS Reader + confirmação OCR no studio.
class PsIngestService {
  /// Gera código de emparelhamento de 6 dígitos (mostrar no Studio).
  static Future<Map<String, dynamic>?> createPairing({
    required String liveId,
    String? deviceIdHint,
  }) async {
    if (currentUserUid.isEmpty) {
      return {'ok': false, 'error': 'not_authenticated'};
    }
    try {
      final res = await SupaFlow.client.rpc(
        'batata_ps_create_pairing',
        params: {
          'p_live_id': liveId.trim(),
          if (deviceIdHint != null && deviceIdHint.trim().isNotEmpty)
            'p_device_id_hint': deviceIdHint.trim(),
        },
      );
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return {'ok': false, 'error': 'invalid_response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Legado — token manual (fallback admin).
  static Future<Map<String, dynamic>?> createDeviceToken({
    required String deviceId,
    String? label,
  }) async {
    if (currentUserUid.isEmpty) return null;
    final res = await SupaFlow.client.rpc(
      'batata_create_seller_device_token',
      params: {
        'p_device_id': deviceId.trim(),
        if (label != null && label.trim().isNotEmpty) 'p_label': label.trim(),
      },
    );
    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    return null;
  }

  static Future<bool> revokeDeviceToken(String deviceId) async {
    if (currentUserUid.isEmpty) return false;
    final res = await SupaFlow.client.rpc(
      'batata_revoke_seller_device_token',
      params: {'p_device_id': deviceId.trim()},
    );
    if (res is Map) {
      return res['ok'] == true;
    }
    return false;
  }

  static Future<Map<String, dynamic>?> confirmReservation({
    required String requestId,
    required String action,
    int? refNumber,
    String? refSlug,
    int? publicSlot,
    int? requestedQty,
  }) async {
    if (currentUserUid.isEmpty) return null;

    if (refSlug != null && refSlug.trim().isNotEmpty) {
      final res = await SupaFlow.client.rpc(
        'batata_confirm_ps_reservation_v2',
        params: {
          'p_request_id': requestId.trim(),
          'p_action': action.trim(),
          'p_ref_slug': refSlug.trim(),
          if (publicSlot != null) 'p_public_slot': publicSlot,
          if (requestedQty != null) 'p_requested_qty': requestedQty,
        },
      );
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    }

    final res = await SupaFlow.client.rpc(
      'batata_confirm_ps_reservation',
      params: {
        'p_request_id': requestId.trim(),
        'p_action': action.trim(),
        if (refNumber != null) 'p_ref_number': refNumber,
      },
    );
    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    return null;
  }

  /// Estado Reader (heartbeat) — null se nunca emparelhado.
  static Future<List<Map<String, dynamic>>> listReaderHeartbeats() async {
    if (currentUserUid.isEmpty) return [];
    try {
      final rows = await SupaFlow.client
          .from('ps_reader_heartbeats')
          .select()
          .eq('seller_id', currentUserUid)
          .order('last_seen_at', ascending: false)
          .limit(5);
      return rows
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {}
    return [];
  }
}
