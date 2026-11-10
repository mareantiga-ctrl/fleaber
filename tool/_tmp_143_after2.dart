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
  final orderId = '0f632c04-b3c5-4074-8957-892e258f7f92';
  final chatId  = '6a1d51f2-f57b-4eda-b675-905cd97dbdfb';

  // check chat_messages or live_messages
  final msgs = await sb.select('chat_messages',
    filter: "chat_id=eq.$chatId",
    limit: 10);
  print('chat_messages count: ${msgs.length}');
  for (final m in msgs) {
    final body = m['body']?.toString() ?? m['text']?.toString() ?? m['content']?.toString() ?? '';
    print('  msg type=${m['type']} body=${body.substring(0, body.length.clamp(0,80))}');
  }

  final dir = Directory('tool/reports/battery_143_145_2026-08-24/bd');
  await dir.create(recursive: true);
  final o = (await sb.select('orders', filter: 'id=eq.$orderId', limit:1)).first;
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId  = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerW = (await sb.select('wallets', filter: 'id=eq.$sellerId', limit:1)).first;
  final buyerW  = (await sb.select('wallets', filter: 'id=eq.$buyerId',  limit:1)).first;
  final txs = await sb.select('wallet_transactions', filter: 'order_id=eq.$orderId', limit:10);

  final snap = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'label': 'AFTER_cancel_143',
    'order': {'id': orderId, 'status': o['status'], 'stripe_refund_id': o['stripe_refund_id'], 'stripe_refunded_at': o['stripe_refunded_at']},
    'seller_balance': sellerW['balance'],
    'buyer_balance':  buyerW['balance'],
    'wallet_txs': txs.map((t) => {'type': t['type'], 'amount': t['amount'], 'wallet_id': (t['wallet_id'] as String).substring(0,8)}).toList(),
    'chat_messages_total': msgs.length,
    'chat_messages_sample': msgs.take(3).map((m) => {
      'type': m['type'],
      'body': (m['body'] ?? m['text'] ?? m['content'] ?? '').toString().substring(0, ((m['body'] ?? m['text'] ?? m['content'] ?? '').toString().length).clamp(0, 100)),
    }).toList(),
  };
  await File('tool/reports/battery_143_145_2026-08-24/bd/snapshot_after_143.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(snap));
  print(jsonEncode(snap));
}
