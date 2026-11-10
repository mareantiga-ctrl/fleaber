// ignore_for_file: avoid_print
/// Termina a live C6_RETEST_COPY. Não toca em MAESTRO_SMOKE_LIVE.
library;

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const liveId = '86457b9d-9dfd-46af-b497-49418bc1ac6e';
  await client.patch('lives', 'id=eq.$liveId', {
    'status': 'ended',
    'is_active': false,
    'ended_at': DateTime.now().toUtc().toIso8601String(),
  });
  final rows = await client.select('lives', filter: 'id=eq.$liveId', limit: 1);
  print('ended ${rows.first['id']} status=${rows.first['status']} active=${rows.first['is_active']}');
}
