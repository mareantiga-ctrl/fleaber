import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';

/// Cliente do RPC `batata_emit_user_notification` (inbox server-side).
/// Falhas são soft — nunca bloqueiam compra/chat/reserva.
abstract final class FleaberNotifyEmit {
  FleaberNotifyEmit._();

  static Future<String?> emit({
    required String recipientId,
    required String kind,
    required String title,
    required String body,
    String? chatId,
    String? productId,
    String? offerId,
    String? actorId,
    String? dedupeKey,
    String? orderId,
  }) async {
    final uid = currentUserUid.trim();
    if (uid.isEmpty) return null;
    final rid = recipientId.trim();
    if (rid.isEmpty || rid == uid) return null;
    try {
      final res = await SupaFlow.client.rpc(
        'batata_emit_user_notification',
        params: {
          'p_recipient_id': rid,
          'p_kind': kind,
          'p_title': title,
          'p_body': body,
          'p_chat_id': (chatId ?? '').trim().isEmpty ? null : chatId!.trim(),
          'p_product_id':
              (productId ?? '').trim().isEmpty ? null : productId!.trim(),
          'p_offer_id': (offerId ?? '').trim().isEmpty ? null : offerId!.trim(),
          'p_actor_id': (actorId ?? uid).trim().isEmpty ? uid : actorId!.trim(),
          'p_dedupe_key':
              (dedupeKey ?? '').trim().isEmpty ? null : dedupeKey!.trim(),
          'p_order_id': (orderId ?? '').trim().isEmpty ? null : orderId!.trim(),
        },
      );
      if (res == null) return null;
      return res.toString();
    } catch (_) {
      return null;
    }
  }

  /// Dispara Edge `notify-dispatch` (best-effort; não bloqueia).
  static Future<void> requestDispatch(String? notificationId) async {
    final nid = notificationId?.trim() ?? '';
    if (nid.isEmpty) return;
    try {
      await SupaFlow.client.functions.invoke(
        'notify-dispatch',
        body: {'notification_id': nid},
      );
    } catch (_) {}
  }
}
