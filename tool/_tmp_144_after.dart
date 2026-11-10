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
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final wallets = await sb.select('wallets', filter: 'id=in.($sellerId,$buyerId)', limit: 2);
  final results = <Map<String, dynamic>>[];
  for (final oid in [
    '70517197-6f1c-4ae1-8e4b-6db6dbf44a97',
    '903c41b3-8c43-4c75-a4b2-d49786bef009',
  ]) {
    final o = (await sb.select('orders', filter: 'id=eq.$oid', limit: 1)).first;
    final txs = await sb.select('wallet_transactions', filter: 'order_id=eq.$oid', limit: 10);
    results.add({
      'id': oid.substring(0, 8),
      'status': o['status'],
      'pm': o['payment_method'],
      'stripe_refund_id': o['stripe_refund_id'],
      'stripe_refunded_at': o['stripe_refunded_at'],
      'wallet_txs': txs.map((t) => {'type': t['type'], 'amount': t['amount']}).toList(),
    });
  }
  final snap = {
    'label': 'AFTER_144',
    'ts': DateTime.now().toUtc().toIso8601String(),
    'wallets': wallets.map((w) => {'id': (w['id'] as String).substring(0,8), 'balance': w['balance']}).toList(),
    'orders': results,
  };
  await Directory('tool/reports/battery_143_145_2026-08-24/bd').create(recursive: true);
  await File('tool/reports/battery_143_145_2026-08-24/bd/snapshot_after_144.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(snap));
  print(jsonEncode(snap));
}
