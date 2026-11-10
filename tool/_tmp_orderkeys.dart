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
    print('order=${oid.substring(0,8)} keys=${o.keys.toList()}');
  }
}
