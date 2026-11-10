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
  final buyer = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final seller = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final productId = '9d0c3ef1-983f-4ee9-8686-902141e727a0';
  final orderId = 'e04a0fde-973d-4d0d-9663-bd2f2a4c46ae';

  final chatsByProduct = await sb.select(
    'chats',
    filter: 'product_id=eq.$productId',
    limit: 20,
  );
  final chatsPair = await sb.select(
    'chats',
    filter:
        'or=(and(user_a.eq.$buyer,user_b.eq.$seller),and(user_a.eq.$seller,user_b.eq.$buyer))&order=last_message_time.desc.nullslast',
    limit: 30,
  );
  final match = chatsPair.where((c) => c['product_id']?.toString() == productId).toList();

  print(jsonEncode({
    'chats_for_regression_product': chatsByProduct,
    'chats_pair_with_regression': match,
    'all_pair_chats': chatsPair
        .map((c) => {
              'id': c['id'],
              'product_id': c['product_id'],
              'last_message_time': c['last_message_time'],
            })
        .toList(),
    'recommended': match.isNotEmpty
        ? {'chat_id': match.first['id'], 'order_id': orderId}
        : null,
  }));
}
