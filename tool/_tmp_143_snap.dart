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

  final wallets = await sb.select('wallets',
    filter: 'id=in.($sellerId,$buyerId)', limit: 2);
  final txV = await sb.select('wallet_transactions',
    filter: 'wallet_id=eq.$sellerId&order_id=eq.0f632c04-b3c5-4074-8957-892e258f7f92', limit: 5);
  final txB = await sb.select('wallet_transactions',
    filter: 'wallet_id=eq.$buyerId&order_id=eq.0f632c04-b3c5-4074-8957-892e258f7f92', limit: 5);

  final payload = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'label': 'BEFORE_cancel_143',
    'wallets': wallets.map((w) => {
      'id': (w['id'] as String).substring(0,8),
      'balance': w['balance'],
    }).toList(),
    'tx_seller_0f632c04': txV,
    'tx_buyer_0f632c04': txB,
  };
  final dir = Directory('tool/reports/battery_143_145_2026-08-24/bd');
  await dir.create(recursive: true);
  await File('${dir.path}/snapshot_before.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  print(jsonEncode(payload));
}
