import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  for (final oid in [
    '70517197-6f1c-4ae1-8e4b-6db6dbf44a97',
    '903c41b3-8c43-4c75-a4b2-d49786bef009',
  ]) {
    final o = (await sb.select('orders', filter: 'id=eq.$oid', limit: 1)).first;
    print(jsonEncode({
      'id': oid.substring(0, 8),
      'status': o['status'],
      'pm': o['payment_method'],
      'total': o['price_total'],
      'stripe_refund_id': o['stripe_refund_id'],
    }));
  }
}
