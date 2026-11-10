// ignore_for_file: avoid_print
library;
import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final userA = '4b343994-0b66-488e-a470-b7594f51cffb';
  final userB = '69104e91-6a00-40d9-a7c9-b1571422ae43';

  for (final uid in [userA, userB]) {
    final p = await sb.select('profiles', filter: 'id=eq.$uid', limit: 1);
    print('$uid → ${p.firstOrNull}');
  }

  // Also check the seller env
  final sellerId = staging['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  final buyerId = staging['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
  print('seller env: $sellerId');
  print('buyer env: $buyerId');
}
