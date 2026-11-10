import 'dart:convert';
import 'dart:io';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId  = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final orderId  = '0f632c04-b3c5-4074-8957-892e258f7f92';

  final o = (await sb.select('orders', filter: 'id=eq.$orderId', limit:1)).first;
  final sellerW = (await sb.select('wallets', filter: 'id=eq.$sellerId', limit:1)).first;
  final buyerW  = (await sb.select('wallets', filter: 'id=eq.$buyerId',  limit:1)).first;
  final txs = await sb.select('wallet_transactions', filter: 'order_id=eq.$orderId', limit:10);
  final chatMsgs = await sb.select('chat_messages',
    filter: "chat_id=eq.6a1d51f2-f57b-4eda-b675-905cd97dbdfb",
    limit: 10);

  final snap = {
    'ts': DateTime.now().toUtc().toIso8601String(),
    'order': {
      'status': o['status'],
      'stripe_refund_id': o['stripe_refund_id'],
      'stripe_refunded_at': o['stripe_refunded_at'],
      'wallet_release_processed_at': o['wallet_release_processed_at'],
    },
    'seller_balance': sellerW['balance'],
    'buyer_balance':  buyerW['balance'],
    'wallet_txs': txs.map((t) => {
      'type': t['type'], 'amount': t['amount'],
      'wallet': (t['wallet_id'] as String).substring(0,8)
    }).toList(),
    'chat_msg_count': chatMsgs.length,
    'chat_msgs': chatMsgs.map((m) {
      final body = (m['body'] ?? '').toString();
      return {'body': body.substring(0, body.length.clamp(0, 120))};
    }).toList(),
  };
  await Directory('tool/reports/battery_143_145_2026-08-24/bd').create(recursive: true);
  await File('tool/reports/battery_143_145_2026-08-24/bd/after_143_final.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(snap));
  print(jsonEncode(snap));
}
