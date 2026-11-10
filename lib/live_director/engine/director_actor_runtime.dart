import 'package:supabase_flutter/supabase_flutter.dart';

import '/backend/supabase/supabase.dart';
import '/live_director/models/director_beat.dart';
import '/live_director/models/director_script.dart';

/// Resultado de uma acção de actor.
class ActorActionResult {
  const ActorActionResult({
    required this.ok,
    this.refTable,
    this.refId,
    this.payload = const {},
    this.error,
  });

  final bool ok;
  final String? refTable;
  final String? refId;
  final Map<String, dynamic> payload;
  final String? error;
}

/// Executa acções de bots — cliente Supabase isolado por bot (não afecta sessão admin).
class DirectorActorRuntime {
  DirectorActorRuntime({
    SupabaseClient? adminClient,
  }) : _admin = adminClient ?? SupaFlow.client;

  final SupabaseClient _admin;
  final Map<String, SupabaseClient> _botClients = {};
  final Map<String, String> _botTokens = {};

  Future<ActorActionResult> execute({
    required DirectorCastMember actor,
    required DirectorBeat beat,
    required String liveId,
    required String sellerId,
    required String notesTag,
    String? raffleId,
    String? botPassword,
  }) async {
    try {
      final client = await _clientFor(actor, botPassword);
      final token = _botTokens[actor.profileId] ?? '';
      switch (beat.action) {
        case DirectorActionType.enter:
          final count = await client.rpc(
            'batata_live_viewer_ping',
            params: {'p_live_id': liveId},
          );
          return ActorActionResult(
            ok: true,
            payload: {'viewer_count': count},
          );
        case DirectorActionType.exit:
          return const ActorActionResult(ok: true, payload: {'left': true});
        case DirectorActionType.like:
        case DirectorActionType.likeBurst:
          await client.rpc(
            'batata_live_viewer_ping',
            params: {'p_live_id': liveId},
          );
          final msgRaw = await client.from('live_messages').insert({
            'live_id': liveId,
            'user_id': actor.profileId,
            'kind': 'chat',
            'body': '👏',
            'sender_label': actor.displayName,
          }).select().maybeSingle();
          final msg = msgRaw is Map
              ? Map<String, dynamic>.from(msgRaw as Map)
              : null;
          return ActorActionResult(
            ok: true,
            refTable: 'live_messages',
            refId: msg?['id']?.toString(),
          );
        case DirectorActionType.chat:
          await client.rpc(
            'batata_live_viewer_ping',
            params: {'p_live_id': liveId},
          );
          final body = beat.messageText ?? beat.phraseTag ?? '…';
          final rowRaw = await client.from('live_messages').insert({
            'live_id': liveId,
            'user_id': actor.profileId,
            'kind': 'chat',
            'body': body,
            'sender_label': actor.displayName,
          }).select().maybeSingle();
          final chatRow = rowRaw is Map
              ? Map<String, dynamic>.from(rowRaw as Map)
              : null;
          return ActorActionResult(
            ok: true,
            refTable: 'live_messages',
            refId: chatRow?['id']?.toString(),
            payload: {'body': body},
          );
        case DirectorActionType.reserve:
          final row = await _reserve(
            client: client,
            liveId: liveId,
            sellerId: sellerId,
            actor: actor,
            beat: beat,
            notesTag: notesTag,
          );
          return ActorActionResult(
            ok: row != null,
            refTable: 'live_reservation_requests',
            refId: row?['id']?.toString(),
            error: row == null ? 'reserve_failed' : null,
          );
        case DirectorActionType.purchase:
          return await _purchase(
            client: client,
            liveId: liveId,
            sellerId: sellerId,
            actor: actor,
            beat: beat,
            notesTag: notesTag,
          );
        case DirectorActionType.raffleJoin:
          if (raffleId == null || raffleId.isEmpty) {
            return const ActorActionResult(ok: false, error: 'raffle_id_missing');
          }
          final res = await client.rpc(
            'batata_join_live_raffle',
            params: {'p_raffle_id': raffleId},
          );
          final ok = res is Map ? res['ok'] == true : res != null;
          return ActorActionResult(ok: ok, payload: {'raffle_id': raffleId});
        case DirectorActionType.silence:
        case DirectorActionType.wait:
          return const ActorActionResult(ok: true, payload: {'noop': true});
      }
    } catch (e) {
      return ActorActionResult(ok: false, error: e.toString());
    }
    return const ActorActionResult(ok: false, error: 'unknown_action');
  }

  Future<Map<String, dynamic>?> _reserve({
    required SupabaseClient client,
    required String liveId,
    required String sellerId,
    required DirectorCastMember actor,
    required DirectorBeat beat,
    required String notesTag,
  }) async {
    final itemId = beat.liveItemId ?? '';
    if (itemId.isEmpty) return null;
    final notes = '$notesTag | DIRECTOR';
    final rowRaw = await client.from('live_reservation_requests').insert({
      'live_id': liveId,
      'live_item_id': itemId,
      'seller_id': sellerId,
      'buyer_id': actor.profileId,
      'requested_qty': beat.qty,
      'source': 'fleaber_live',
      'status': 'pending',
      'notes': notes,
    }).select().maybeSingle();
    if (rowRaw is Map) {
      return Map<String, dynamic>.from(rowRaw as Map);
    }
    return null;
  }

  Future<ActorActionResult> _purchase({
    required SupabaseClient client,
    required String liveId,
    required String sellerId,
    required DirectorCastMember actor,
    required DirectorBeat beat,
    required String notesTag,
  }) async {
    if (beat.paymentMode == DirectorPaymentMode.real) {
      return const ActorActionResult(
        ok: false,
        error: 'real_payment_requires_edge',
      );
    }
    final itemId = beat.liveItemId ?? '';
    if (itemId.isEmpty) {
      return const ActorActionResult(ok: false, error: 'no_product');
    }
    // Simulated: order hold only — sem Stripe.
    final itemsRaw = await client
        .from('live_items')
        .select('product_id, price')
        .eq('id', itemId)
        .maybeSingle();
    if (itemsRaw is! Map) {
      return const ActorActionResult(ok: false, error: 'item_not_found');
    }
    final items = Map<String, dynamic>.from(itemsRaw as Map);
    final productId = items['product_id']?.toString();
    if (productId == null || productId.isEmpty) {
      return const ActorActionResult(ok: false, error: 'no_product_id');
    }
    final price = (items['price'] as num?)?.toDouble() ?? 0;
    final total = price * beat.qty;
    final orderRaw = await client.from('orders').insert({
      'product_id': productId,
      'buyer_id': actor.profileId,
      'seller_id': sellerId,
      'price_total': total,
      'status': beat.paymentMode == DirectorPaymentMode.simulated
          ? 'reserva_pendente'
          : 'reserva_pendente',
      'payment_method': 'Pagamento na App',
      'live_id': liveId,
      'live_item_id': itemId,
      'quantity': beat.qty,
      'notes': '$notesTag | DIRECTOR_SIM',
    }).select().maybeSingle();
    final order = orderRaw is Map
        ? Map<String, dynamic>.from(orderRaw as Map)
        : null;
    return ActorActionResult(
      ok: order != null,
      refTable: 'orders',
      refId: order?['id']?.toString(),
      payload: {'payment_mode': beat.paymentMode.name, 'total': total},
    );
  }

  Future<SupabaseClient> _clientFor(
    DirectorCastMember actor,
    String? botPassword,
  ) async {
    if (_botClients.containsKey(actor.profileId)) {
      return _botClients[actor.profileId]!;
    }
    final botClient = SupabaseClient(SupaFlow.supabaseUrl, SupaFlow.anonKey);
    if (actor.email != null &&
        actor.email!.isNotEmpty &&
        botPassword != null &&
        botPassword.isNotEmpty) {
      final res = await botClient.auth.signInWithPassword(
        email: actor.email!,
        password: botPassword,
      );
      _botTokens[actor.profileId] = res.session?.accessToken ?? '';
    }
    _botClients[actor.profileId] = botClient;
    return botClient;
  }

  void dispose() {
    for (final c in _botClients.values) {
      c.auth.signOut();
    }
    _botClients.clear();
    _botTokens.clear();
  }
}
