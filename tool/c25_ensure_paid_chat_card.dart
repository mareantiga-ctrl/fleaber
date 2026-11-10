// ignore_for_file: avoid_print
/// Repara thread paga em falta (ensureSeguroFleaberPaidSaleChat via REST) — só prep QA.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  final orderId = args.isEmpty
      ? 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae'
      : args.first;
  final env = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final buyerEmail = envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final buyerPassword = envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD');
  final buyerToken = await client.signIn(email: buyerEmail, password: buyerPassword);
  final buyerId = await client.userIdForAccessToken(buyerToken);

  final orders = await client.select('orders', filter: 'id=eq.$orderId', limit: 1);
  if (orders.isEmpty) {
    stderr.writeln('order not found');
    exit(1);
  }
  final o = orders.first;
  final sellerId = o['seller_id'].toString();
  final productId = o['product_id'].toString();
  final total = o['price_total'];

  // Chat correcto do produto (ou criar)
  var chats = await client.select(
    'chats',
    filter:
        'product_id=eq.$productId&or=(and(user_a.eq.$buyerId,user_b.eq.$sellerId),and(user_a.eq.$sellerId,user_b.eq.$buyerId))',
    limit: 5,
  );
  String chatId;
  if (chats.isEmpty) {
    final ins = await client.insert('chats', {
      'user_a': buyerId,
      'user_b': sellerId,
      'product_id': productId,
      'last_message': 'Compra paga pelo Seguro Fleaber',
      'last_message_time': DateTime.now().toUtc().toIso8601String(),
    });
    chatId = ins['id'].toString();
    print('created chat $chatId');
  } else {
    chatId = chats.first['id'].toString();
  }

  final text = 'FLEABER_JSON_V1:${jsonEncode({
        'kind': 'seguro_fleaber_paid',
        'order_id': orderId,
        'total': total,
        'v': 1,
      })}';

  final existing = await client.select(
    'chat_messages',
    filter: 'chat_id=eq.$chatId&text=like.%25seguro_fleaber_paid%25',
    limit: 5,
  );
  final has = existing.any((m) => (m['text'] ?? '').toString().contains(orderId));
  if (!has) {
    await client.insert('chat_messages', {
      'chat_id': chatId,
      'sender_id': buyerId,
      'receiver_id': sellerId,
      'text': text,
      'is_read': false,
      'is_reservation': true,
    });
    print('inserted seguro_fleaber_paid message');
  } else {
    print('message already exists');
  }

  await client.patch('chats', 'id=eq.$chatId', {
    'last_message': 'Compra paga pelo Seguro Fleaber',
    'last_message_time': DateTime.now().toUtc().toIso8601String(),
  });

  print(jsonEncode({
    'order_id': orderId,
    'chat_id': chatId,
    'product_id': productId,
    'note':
        'Prep QA: card em falta após pagamento API — permite UI envio/disputa; ordem já pago na BD.',
  }));
}
