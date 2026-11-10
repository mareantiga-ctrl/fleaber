import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  for (final oid in ['b0d566cf-f8e2-4068-8f0b-af1e2cd02216','903c41b3-8c43-4c75-a4b2-d49786bef009']) {
    final o = (await sb.select('orders', filter: "id=eq.$oid", limit:1)).first;
    final pid = o['product_id']?.toString() ?? '';
    // try product directly
    if (pid.isNotEmpty) {
      try {
        final prod = await sb.select('products', filter: 'id=eq.$pid', limit:1);
        if (prod.isNotEmpty) {
          final p = prod.first;
          print('order=${oid.substring(0,8)} product_name=${p['name']} brand=${p['brand']}');
          continue;
        }
      } catch(_) {}
    }
    // check all columns of the order
    print('order=${oid.substring(0,8)} all_keys=${o.keys.toList()}');
    print('  title=${o['title']} name=${o['name']} product_name=${o['product_name']} description=${o['description']}');
  }
}
