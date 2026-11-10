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

  // Verificar várias threads com shipped+completed para encontrar uma com seller env
  final sellerId = staging['LIVE_OPS_TEST_SELLER_ID']?.trim() ?? '';
  final buyerId = staging['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
  print('looking for seller=$sellerId buyer=$buyerId');

  final chatIds = [
    '83718a7a-bff5-46df-b470-1d292c5cd2be',
    '655829e0-b5b5-45cc-9186-2ca16f918197',
    '5e226f35-7fea-471f-814f-0c1de622827b',
    '5cbc7175-d0db-4b83-9d63-86c14e6d0d32',
  ];
  for (final cid in chatIds) {
    final t = await sb.select('chats', filter: 'id=eq.$cid', limit: 1);
    if (t.isEmpty) continue;
    final chat = t.first;
    final ua = chat['user_a']?.toString() ?? '';
    final ub = chat['user_b']?.toString() ?? '';
    final match = ua == sellerId || ub == sellerId || ua == buyerId || ub == buyerId;
    print('$cid ua=$ua ub=$ub match=$match');
  }
}
