import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final o = (await sb.select('orders', filter: 'id=eq.903c41b3-8c43-4c75-a4b2-d49786bef009', limit:1)).first;
  print('buyer_id: ${o['buyer_id']}');
  print('product_id: ${o['product_id']}');
  print('price_total: ${o['price_total']}');
  print('status: ${o['status']}');
  print('payment_method: ${o['payment_method']}');
}
