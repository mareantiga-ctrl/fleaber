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
  final orders = await sb.select(
    'orders',
    filter: 'buyer_id=eq.$buyer&status=eq.pago&order=created_at.desc',
    limit: 30,
  );
  final out = <Map<String, dynamic>>[];
  for (final o in orders) {
    final oid = o['id'].toString();
    final msgs = await sb.select(
      'chat_messages',
      filter: 'text=like.%25$oid%25&order=created_at.desc',
      limit: 3,
    );
    out.add({
      'id': oid,
      'payment_method': o['payment_method'],
      'created_at': o['created_at'],
      'product_id': o['product_id'],
      'chat_msgs': msgs.length,
    });
  }
  print(jsonEncode(out));
}
