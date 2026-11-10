import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  // get the product name for 903c41b3
  final o = (await sb.select('orders', filter: 'id=eq.903c41b3-8c43-4c75-a4b2-d49786bef009', limit:1)).first;
  final pid = o['product_id']?.toString() ?? '';
  print('product_id: $pid');
  if (pid.isNotEmpty) {
    try {
      final prod = (await sb.select('products', filter: 'id=eq.$pid', limit:1)).first;
      print('product name: ${prod['name']} title: ${prod['title']}');
      // find all keys
      print('keys: ${prod.keys.toList()}');
    } catch (e) { print('product err: $e'); }
  }
}
