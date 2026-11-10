import 'live_ops_staging_client.dart';
Future<void> main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  await client.patch(
    'live_reservation_requests',
    'id=eq.fcac95eb-f868-4a9f-820a-5f21fae73073',
    {'request_kind': 'guaranteed'},
  );
  print('patched kind=guaranteed on accepted-from-pending row');
}
