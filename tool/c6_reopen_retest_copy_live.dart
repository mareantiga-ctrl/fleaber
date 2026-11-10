// ignore_for_file: avoid_print
/// Reabre C6_RETEST_COPY só para o reteste 204b (vitrine + buyer).
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
  const itemA = 'fd57c4ab-ffa7-4e0e-a768-a3ffabbd8bca';
  await client.patch('lives', 'id=eq.$liveId', {
    'status': 'live',
    'is_active': true,
  });
  final live = await client.select('lives', filter: 'id=eq.$liveId', limit: 1);
  final item = await client.select('live_items', filter: 'id=eq.$itemA', limit: 1);
  print('live ${live.first['status']} active=${live.first['is_active']}');
  print('item A ${item.first['title']} status=${item.first['status']}');
}
