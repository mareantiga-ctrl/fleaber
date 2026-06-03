import 'dart:convert';

import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/chat_session_util.dart';
import '/order_cancel_eligibility.dart';

const String kFleaberChatJsonPrefix = 'FLEABER_JSON_V1:';

String fleaberChatJsonEncode(Map<String, dynamic> m) =>
    kFleaberChatJsonPrefix + jsonEncode(m);

List<Map<String, dynamic>> _rowsFromDynamic(dynamic res) {
  if (res is! List) return [];
  return [
    for (final e in res)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
}

/// UPDATE por `id` (sem filtrar status na query — evita falhas com enum/RLS).
/// [requireStatusKey] valida o estado actual antes de escrever.
Future<Map<String, dynamic>> batataPatchOrderById({
  required String orderId,
  required Map<String, dynamic> patch,
  String? requireStatusKey,
}) async {
  print(
    'BATATA_PATCH start orderId=$orderId require=$requireStatusKey patch=$patch',
  );

  final existing = await SupaFlow.client
      .from('orders')
      .select('id, status, seller_id, buyer_id, product_id')
      .eq('id', orderId)
      .maybeSingle();

  if (existing == null) {
    throw Exception('Encomenda não encontrada.');
  }

  final existingMap = Map<String, dynamic>.from(existing);
  final currentKey =
      normalizeOrderStatusKey(orderStatusRawFromData(existingMap));
  print(
    'BATATA_PATCH current status key=$currentKey raw=${existingMap['status']}',
  );

  if (requireStatusKey != null && currentKey != requireStatusKey) {
    throw Exception(
      'Este pedido já não está em «$requireStatusKey» '
      '(estado actual: «$currentKey»).',
    );
  }

  final dynamic res = await SupaFlow.client
      .from('orders')
      .update(patch)
      .eq('id', orderId)
      .select('id, status, seller_id, buyer_id, product_id');

  final rows = _rowsFromDynamic(res);
  print(
    'BATATA_PATCH rows=${rows.length} '
    'newStatus=${rows.isEmpty ? null : rows.first['status']}',
  );

  if (rows.isEmpty) {
    throw Exception(
      'Não foi possível actualizar a encomenda (0 linhas). '
      'Confirma as políticas RLS em `public.orders` '
      '(supabase/sql/orders_rls_batata.sql).',
    );
  }
  return rows.first;
}

Future<void> assertOrderStatusKey({
  required String orderId,
  required String expectedKey,
}) async {
  final row = await SupaFlow.client
      .from('orders')
      .select('status')
      .eq('id', orderId)
      .maybeSingle();
  if (row == null) {
    throw Exception('Encomenda não encontrada após actualizar.');
  }
  final st = orderStatusRawFromData(Map<String, dynamic>.from(row));
  if (normalizeOrderStatusKey(st) != expectedKey) {
    throw Exception(
      'Estado inesperado após actualizar: «$st» (esperado «$expectedKey»).',
    );
  }
}

Future<void> assertOrderCancelled(String orderId) async {
  final row = await SupaFlow.client
      .from('orders')
      .select('status')
      .eq('id', orderId)
      .maybeSingle();
  if (row == null) {
    throw Exception('Encomenda não encontrada após actualizar.');
  }
  final st = orderStatusRawFromData(Map<String, dynamic>.from(row));
  if (!orderIsCancelled(st)) {
    throw Exception(
      'O cancelamento não ficou registado (estado actual: «$st»).',
    );
  }
}

Future<void> insertSellerReservationOutcomeMessages({
  required String chatId,
  required String buyerId,
  required String orderId,
  required String outcome,
  DateTime? expiresAtUtc,
}) async {
  await ChatMessagesTable().insert({
    'sender_id': currentUserUid,
    'receiver_id': buyerId,
    'is_read': false,
    'text': fleaberChatJsonEncode({
      'kind': 'reservation_request_outcome',
      'order_id': orderId,
      'outcome': outcome,
      'v': 1,
    }),
    'chat_id': chatId,
    'is_reservation': true,
  });

  if (outcome == 'accepted' && expiresAtUtc != null) {
    await ChatMessagesTable().insert({
      'sender_id': currentUserUid,
      'receiver_id': buyerId,
      'is_read': false,
      'text': fleaberChatJsonEncode({
        'kind': 'reservation_accepted',
        'order_id': orderId,
        'expires_at': expiresAtUtc.toIso8601String(),
        'v': 1,
      }),
      'chat_id': chatId,
      'is_reservation': true,
    });
  }
}

/// Actualiza `live_items.status` (ESGOTADO/reservado) quando a encomenda tem contexto live.
Future<void> batataSyncLiveCatalogForOrder(String orderId) async {
  final oid = orderId.trim();
  if (oid.isEmpty) return;
  try {
    await SupaFlow.client.rpc(
      'batata_sync_live_item_for_order',
      params: {'p_order_id': oid},
    );
  } catch (e) {
    print('BATATA_SYNC_LIVE_ITEM_FOR_ORDER ERRO: $e');
  }
}

Future<void> touchChatLastMessage({
  required String chatId,
  required String preview,
}) async {
  await ChatsTable().update(
    data: {
      'last_message': preview,
      'last_message_time': DateTime.now().toUtc().toIso8601String(),
    },
    matchingRows: (rows) => rows.eqOrNull('id', chatId),
  );
}

/// Vendedor recusa pedido de reserva pendente.
Future<void> batataSellerDeclineReservaPendente({
  required String orderId,
  required String buyerId,
  required String productId,
}) async {
  if (orderId.isEmpty) throw Exception('ID de encomenda inválido.');
  await batataPatchOrderById(
    orderId: orderId,
    patch: {'status': 'cancelado'},
    requireStatusKey: 'reserva_pendente',
  );
  await assertOrderCancelled(orderId);
  await batataSyncLiveCatalogForOrder(orderId);

  if (buyerId.isEmpty || productId.isEmpty) return;

  final chat = await ensureSellerChat(
    otherUserId: buyerId,
    productId: productId,
  );
  final cid = chat.id;
  if (cid == null || cid.isEmpty) return;

  await insertSellerReservationOutcomeMessages(
    chatId: cid,
    buyerId: buyerId,
    orderId: orderId,
    outcome: 'declined',
  );
  await touchChatLastMessage(chatId: cid, preview: 'Reserva recusada');
}

/// Vendedor aceita pedido de reserva pendente.
Future<void> batataSellerAcceptReservaPendente({
  required String orderId,
  required String buyerId,
  required String productId,
}) async {
  if (orderId.isEmpty) throw Exception('ID de encomenda inválido.');
  final newExp = DateTime.now().toUtc().add(const Duration(days: 5));

  await batataPatchOrderById(
    orderId: orderId,
    patch: {
      'status': 'reservado',
      'reservation_expires_at': newExp.toIso8601String(),
    },
    requireStatusKey: 'reserva_pendente',
  );
  await assertOrderStatusKey(orderId: orderId, expectedKey: 'reservado');
  await batataSyncLiveCatalogForOrder(orderId);

  if (buyerId.isEmpty || productId.isEmpty) return;

  final chat = await ensureSellerChat(
    otherUserId: buyerId,
    productId: productId,
  );
  final cid = chat.id;
  if (cid == null || cid.isEmpty) return;

  await insertSellerReservationOutcomeMessages(
    chatId: cid,
    buyerId: buyerId,
    orderId: orderId,
    outcome: 'accepted',
    expiresAtUtc: newExp,
  );
  await touchChatLastMessage(chatId: cid, preview: 'Reserva aceite');
}

/// Comprador cancela pedido de reserva pendente.
Future<void> batataBuyerCancelReservaPendente({
  required String orderId,
  required String sellerId,
  required String productId,
}) async {
  if (orderId.isEmpty) throw Exception('ID de encomenda inválido.');
  await batataPatchOrderById(
    orderId: orderId,
    patch: {'status': 'cancelado'},
    requireStatusKey: 'reserva_pendente',
  );
  await assertOrderCancelled(orderId);
  await batataSyncLiveCatalogForOrder(orderId);

  if (sellerId.isEmpty || productId.isEmpty) return;

  final chat = await ensureSellerChat(
    otherUserId: sellerId,
    productId: productId,
  );
  final cid = chat.id;
  if (cid == null || cid.isEmpty) return;

  await ChatMessagesTable().insert({
    'sender_id': currentUserUid,
    'receiver_id': sellerId,
    'is_read': false,
    'text': 'O comprador cancelou o pedido de reserva desta encomenda.',
    'chat_id': cid,
    'is_reservation': true,
  });
  await touchChatLastMessage(
    chatId: cid,
    preview: 'Pedido de reserva cancelado',
  );
}
