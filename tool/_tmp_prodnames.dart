import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  // Get product names for both test orders
  for (final info in [
    {'oid': 'b0d566cf-f8e2-4068-8f0b-af1e2cd02216', 'label': 'APP143'},
    {'oid': '903c41b3-8c43-4c75-a4b2-d49786bef009', 'label': 'APP144'},
  ]) {
    final o = (await sb.select('orders', filter: "id=eq.${info['oid']}", limit:1)).first;
    final pid = o['product_id']?.toString() ?? '';
    final prod = pid.isNotEmpty
      ? (await sb.select('products', filter: 'id=eq.$pid', limit:1))
      : [];
    final name = prod.isNotEmpty ? prod.first['name'] : '?';
    print('${info['label']}: order=${o['id'].toString().substring(0,8)} product="$name" total=${o['price_total']} status=${o['status']}');
  }
}
