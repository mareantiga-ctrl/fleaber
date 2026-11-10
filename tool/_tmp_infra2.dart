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

  // Check stripe columns
  try {
    final row = (await sb.select('orders',
      filter: 'id=eq.0f632c04-b3c5-4074-8957-892e258f7f92', limit: 1)).first;
    final keys = row.keys.where((k) => k.startsWith('stripe_')).toList();
    print('stripe_cols: $keys');
    print('stripe_checkout_session_id: ${row['stripe_checkout_session_id']}');
    print('stripe_refund_id: ${row['stripe_refund_id']}');
  } catch (e) {
    print('ERROR orders: $e');
  }
}
