import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  // check 3 of the 5€ orders for checkout session
  for (final oid in ['248dc728-58cb-4551-a3ef-adf49d74e71d','e53d9ceb-a3b0-4f8f-91e0-db7ecb3f5c97','61b701ff-4e90-4a95-8ccf-1ca7d7e1e2c5']) {
    final rows = await sb.select('orders', filter: 'id=eq.$oid', limit:1);
    if (rows.isEmpty) { print('$oid not found'); continue; }
    final o = rows.first;
    // check stripe events
    final evts = await sb.select('stripe_checkout_events',
      filter: 'order_id=eq.$oid&event=eq.checkout.paid', limit:1);
    print(jsonEncode({
      'id': oid.substring(0,8),
      'checkout_session': o['stripe_checkout_session_id'],
      'stripe_evt': evts.isNotEmpty ? evts.first['session_id'] : null,
      'buyer_id': (o['buyer_id'] as String?)?.substring(0,8),
    }));
  }
}
