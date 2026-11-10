import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  // all Pago/Seguro orders from seller
  final orders = await sb.select('orders',
    filter: 'seller_id=eq.$sellerId&status=eq.pago&payment_method=eq.Pagamento na App',
    limit: 20);
  for (final o in orders) {
    print(jsonEncode({
      'id': o['id'].toString().substring(0,8),
      'total': o['price_total'],
      'stripe_refund_id': o['stripe_refund_id'],
      'product_id': o['product_id']?.toString().substring(0,8),
    }));
  }
}
