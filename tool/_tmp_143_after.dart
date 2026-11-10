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
  print('order status: ${o['status']}');
  print('stripe_refund_id: ${o['stripe_refund_id']}');
  print('stripe_refunded_at: ${o['stripe_refunded_at']}');
  print('wallet_release_processed_at: ${o['wallet_release_processed_at']}');

  final sellerWallet = (await sb.select('wallets', filter: 'id=eq.$sellerId', limit:1));
  final buyerWallet  = (await sb.select('wallets', filter: 'id=eq.$buyerId',  limit:1));
  if (sellerWallet.isNotEmpty) print('seller balance: ${sellerWallet.first['balance']}');
  if (buyerWallet.isNotEmpty)  print('buyer balance: ${buyerWallet.first['balance']}');

  // wallet transactions for this order
  final txs = await sb.select('wallet_transactions',
    filter: 'order_id=eq.$orderId', limit: 10);
  for (final t in txs) {
    print('tx: ${jsonEncode({'type':t['type'],'amount':t['amount'],'wallet_id':(t['wallet_id'] as String).substring(0,8)})}');
  }

  // check if chat message was added (messages in chat 6a1d51f2)
  final msgs = await sb.select('messages',
    filter: "chat_id=eq.6a1d51f2-f57b-4eda-b675-905cd97dbdfb&content=like.%reembolso%",
    limit: 5);
  print('reembolso messages: ${msgs.length}');
  for (final m in msgs) {
    print('  msg: ${m['content']?.toString().substring(0, (m['content']?.toString().length ?? 0).clamp(0, 80))}');
  }

  final dir = Directory('tool/reports/battery_143_145_2026-08-24/bd');
  await dir.create(recursive: true);
  final snap = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'label': 'AFTER_cancel_143',
    'order': {
      'id': orderId,
      'status': o['status'],
      'stripe_refund_id': o['stripe_refund_id'],
      'stripe_refunded_at': o['stripe_refunded_at'],
    },
    'seller_balance': sellerWallet.isNotEmpty ? sellerWallet.first['balance'] : null,
    'buyer_balance':  buyerWallet.isNotEmpty  ? buyerWallet.first['balance']  : null,
    'wallet_tx_count': txs.length,
    'reembolso_msgs': msgs.length,
  };
  await File('tool/reports/battery_143_145_2026-08-24/bd/snapshot_after_143.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(snap));
  print('snapshot saved');
}
