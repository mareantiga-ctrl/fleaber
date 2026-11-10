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
  // use full uuid from previous query
  final oids = [
    '248dc728', 'e53d9ceb', '61b701ff',
  ];
  // search by prefix
  final orders = await sb.select('orders',
    filter: 'seller_id=eq.$sellerId&status=eq.pago&payment_method=eq.Pagamento na App&price_total=eq.5',
    limit: 5);
  for (final o in orders) {
    final oid = o['id'].toString();
    final evts = await sb.select('stripe_checkout_events',
      filter: 'order_id=eq.$oid&event=eq.checkout.paid', limit:1);
    print(jsonEncode({
      'id': oid.substring(0,8),
      'checkout_session': o['stripe_checkout_session_id'],
      'stripe_evt_session': evts.isNotEmpty ? evts.first['session_id'] : null,
      'buyer_id': (o['buyer_id'] as String?)?.substring(0,8),
    }));
  }
}
