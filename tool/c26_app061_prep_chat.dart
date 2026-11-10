// ignore_for_file: avoid_print
/// C26 APP-061 — garante card reservation_request no chat + IDs.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  final orderId = args.isEmpty
      ? 'f8a144da-5dd9-4156-bf49-6f0c468792cf'
      : args.first;
  final env = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final orders = await c.select('orders', filter: 'id=eq.$orderId', limit: 1);
  if (orders.isEmpty) {
    stderr.writeln('order not found');
    exit(1);
  }
  final o = orders.first;
  final status = (o['status'] ?? '').toString();
  if (status != 'reserva_pendente') {
    stderr.writeln('expected reserva_pendente got $status');
    exit(2);
  }
  final buyerId = o['buyer_id'].toString();
  final sellerId = o['seller_id'].toString();
  final productId = o['product_id'].toString();
  final total = o['price_total'];

  var chats = await c.select(
    'chats',
    filter:
        'product_id=eq.$productId&or=(and(user_a.eq.$buyerId,user_b.eq.$sellerId),and(user_a.eq.$sellerId,user_b.eq.$buyerId))',
    limit: 5,
  );
  String chatId;
  if (chats.isEmpty) {
    final ins = await c.insert('chats', {
      'user_a': buyerId,
      'user_b': sellerId,
      'product_id': productId,
      'last_message': 'Pedido de reserva',
      'last_message_time': DateTime.now().toUtc().toIso8601String(),
    });
    chatId = ins['id'].toString();
  } else {
    chatId = chats.first['id'].toString();
  }

  final expiresAt = DateTime.now().toUtc().add(const Duration(days: 5));
  final payload = {
    'kind': 'reservation_request',
    'order_id': orderId,
    'product_id': productId,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'expires_at': expiresAt.toIso8601String(),
    'total': total,
    'v': 1,
  };
  final text = 'FLEABER_JSON_V1:${jsonEncode(payload)}';

  final existing = await c.select(
    'chat_messages',
    filter: 'chat_id=eq.$chatId&text=like.%25reservation_request%25',
    limit: 20,
  );
  Map<String, dynamic>? match;
  for (final m in existing) {
    if ((m['text'] ?? '').toString().contains(orderId)) {
      match = m;
      break;
    }
  }
  if (match == null) {
    await c.insert('chat_messages', {
      'chat_id': chatId,
      'sender_id': buyerId,
      'receiver_id': sellerId,
      'text': text,
      'is_read': false,
      'is_reservation': true,
    });
    print('inserted reservation_request');
  } else {
    final raw = (match['text'] ?? '').toString();
    final needsFix = !raw.contains('buyer_id') || !raw.contains('seller_id');
    if (needsFix) {
      await c.patch(
        'chat_messages',
        'id=eq.${match['id']}',
        {'text': text},
      );
      print('patched reservation_request (payload completo)');
    } else {
      print('reservation_request already present');
    }
  }

  final out = {
    'order_id': orderId,
    'chat_id': chatId,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': productId,
    'status': status,
    'price_total': total,
  };
  await Directory('tool/reports/battery_c26_2026-08-22/bd').create(recursive: true);
  await File('tool/reports/battery_c26_2026-08-22/bd/c26_app061_prep.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
}
