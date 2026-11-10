import 'live_ops_staging_client.dart';

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL')),
    anonKey: envRequire(e, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final email = envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL');
  final t = await c.signIn(
    email: email,
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  print('OK $email token=${t.length}');
}
