// ignore_for_file: avoid_print
/// Garante catálogo vazio para prep (A002): desmarca available_for_live no seller.
///
/// Uso: dart run tool/maestro_prep_empty_catalog.dart
library;

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  var sellerId = staging['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  if (!isUuid(sellerId)) {
    final token = await client.signIn(
      email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
      password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
    );
    sellerId = await client.userIdForAccessToken(token);
  }

  await client.patch(
    'products',
    'seller_id=eq.$sellerId&is_sold=eq.false',
    {'available_for_live': false},
  );

  print('maestro_prep_empty_catalog OK seller=$sellerId');
}
