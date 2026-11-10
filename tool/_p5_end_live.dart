// ignore_for_file: avoid_print
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const live = 'a7af3768-12d4-455f-ae83-3a2675861469';
  await client.patch('lives', 'id=eq.$live', {
    'status': 'ended',
    'is_active': false,
  });
  final all = await client.select(
    'live_reservation_requests',
    filter: 'live_id=eq.$live',
    limit: 20,
  );
  for (final r in all) {
    print(
      'id=${r['id']} status=${r['status']} kind=${r['request_kind']} '
      'ext=${r['extended_once']}',
    );
  }
  print('ENDED live $live');
}
