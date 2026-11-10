import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  // find existing chats between seller and buyer (any product)
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId  = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final chats = await sb.select(
    'chats',
    filter: 'user_a=eq.$buyerId',
    limit: 3,
  );
  for (final c in chats) {
    print(jsonEncode({'id': c['id'], 'product_id': c['product_id'], 'ub': (c['user_b'] as String?)?.substring(0,8)}));
  }

  // also check stripe_checkout_events for 0f632c04
  final evts = await sb.select(
    'stripe_checkout_events',
    filter: 'order_id=eq.0f632c04-b3c5-4074-8957-892e258f7f92',
    limit: 3,
  );
  for (final e in evts) {
    print(jsonEncode({'session_id': e['session_id'], 'event': e['event']}));
  }
}
