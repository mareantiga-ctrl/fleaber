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

  final msgs = await sb.select(
    'chat_messages',
    filter: 'text=like.FLEABER_JSON_V1%25&order=created_at.desc',
    limit: 800,
  );

  final candidates = <Map<String, dynamic>>[];
  for (final m in msgs) {
    final text = (m['text'] ?? '').toString();
    if (!text.startsWith('FLEABER_JSON_V1:')) continue;
    Map? payload;
    try {
      payload = jsonDecode(text.substring('FLEABER_JSON_V1:'.length)) as Map?;
    } catch (_) {
      continue;
    }
    final kind = payload?['kind']?.toString() ?? '';
    if (kind != 'seguro_fleaber_paid' &&
        kind != 'marketplace_bag_paid' &&
        kind != 'reservation_payment_submitted') {
      continue;
    }
    final orderId = payload?['order_id']?.toString();
    if (orderId == null || orderId.isEmpty) continue;
    final orders = await sb.select('orders', filter: 'id=eq.$orderId', limit: 1);
    if (orders.isEmpty) continue;
    final o = orders.first;
    if (o['buyer_id'] != buyer || o['seller_id'] != seller) continue;
    final st = (o['status'] ?? '').toString();
    if (st != 'pago' && st != 'enviado') continue;
    candidates.add({
      'order_id': orderId,
      'status': st,
      'kind': kind,
      'chat_id': m['chat_id'],
      'created_at': m['created_at'],
      'payment_method': o['payment_method'],
    });
    if (candidates.length >= 15) break;
  }

  print(jsonEncode({'candidates': candidates}));
}
