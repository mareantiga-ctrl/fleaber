// ignore_for_file: avoid_print
/// Fecha lives activas do seller QA. Sem criar produto.
library;

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  var sellerId = staging['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  if (!isUuid(sellerId)) {
    final t = await client.signIn(
      email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
      password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
    );
    sellerId = await client.userIdForAccessToken(t);
  }
  final lives = await client.select(
    'lives',
    filter: 'seller_id=eq.$sellerId&order=created_at.desc',
    limit: 30,
  );
  var n = 0;
  for (final live in lives) {
    final id = live['id']?.toString() ?? '';
    final status = (live['status'] ?? '').toString().toLowerCase();
    final active = live['is_active'] == true;
    if (id.isEmpty) continue;
    if (status == 'live' || active || status == 'scheduled') {
      await client.patch(
        'lives',
        'id=eq.$id',
        {'status': 'ended', 'is_active': false},
      );
      n++;
      print('fechada $id ${live['title']} $status');
    }
  }
  print('fechadas=$n');
}
