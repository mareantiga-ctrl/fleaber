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
  final o1 = (await sb.select('orders', filter: 'id=eq.70517197-6f1c-4ae1-8e4b-6db6dbf44a97', limit: 1)).first;
  final o2 = (await sb.select('orders', filter: 'id=eq.903c41b3-8c43-4c75-a4b2-d49786bef009', limit: 1)).first;
  final snap = {
    'label': 'BEFORE_144',
    'wallets': wallets.map((w) => {'id': (w['id'] as String).substring(0,8), 'balance': w['balance']}).toList(),
    'o_newer': {'id': o1['id'], 'status': o1['status'], 'stripe_refund_id': o1['stripe_refund_id']},
    'o_older': {'id': o2['id'], 'status': o2['status'], 'stripe_refund_id': o2['stripe_refund_id']},
  };
  await Directory('tool/reports/battery_143_145_2026-08-24/bd').create(recursive: true);
  await File('tool/reports/battery_143_145_2026-08-24/bd/snapshot_before_144.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(snap));
  print(jsonEncode(snap));
}
