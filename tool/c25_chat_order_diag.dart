// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final chatId = '8751ec5b-fad4-456a-8526-5662a859ec06';
  final orderId = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';
  final chats = await sb.select('chats', filter: 'id=eq.$chatId', limit: 1);
  final order = (await sb.select('orders', filter: 'id=eq.$orderId', limit: 1)).first;
  final productId = order['product_id'];
  final product = (await sb.select('products', filter: 'id=eq.$productId', limit: 1)).first;
  final chatProduct = chats.isEmpty || chats.first['product_id'] == null
      ? null
      : (await sb.select('products', filter: 'id=eq.${chats.first['product_id']}', limit: 1)).firstOrNull;
  final ordersSameChat = await sb.select(
    'orders',
    filter:
        'product_id=eq.$productId&buyer_id=eq.${order['buyer_id']}&seller_id=eq.${order['seller_id']}&order=created_at.desc',
    limit: 10,
  );
  print(jsonEncode({
    'chat': chats.isEmpty ? null : chats.first,
    'chat_product_title': chatProduct?['title'],
    'order_product_title': product['title'],
    'order_status': order['status'],
    'orders_same_product_pair': ordersSameChat
        .map((o) => {'id': o['id'], 'status': o['status'], 'created_at': o['created_at']})
        .toList(),
  }));
}

extension _E<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
