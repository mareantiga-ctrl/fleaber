import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv('tool/live_ops_staging.env');
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(env['SUPABASE_URL']!),
    anonKey: env['SUPABASE_ANON_KEY']!,
    serviceRoleKey: env['SUPABASE_SERVICE_ROLE_KEY']!,
  );

  final sellerEmail = env['LIVE_OPS_TEST_SELLER_EMAIL']!;
  final sellerPass = env['LIVE_OPS_TEST_SELLER_PASSWORD']!;
  final buyerId = env['LIVE_OPS_TEST_BUYER_ID']!;
  final sellerId = env['LIVE_OPS_TEST_SELLER_ID']!;

  final token = await client.signIn(email: sellerEmail, password: sellerPass);
  final uid = await client.userIdForAccessToken(token);
  stdout.writeln('seller_uid=$uid expected=$sellerId');

  final bundles = await client.select(
    'product_bundles',
    filter: 'seller_id=eq.$sellerId&buyer_id=eq.$buyerId&order=created_at.desc',
    limit: 1,
  );
  if (bundles.isEmpty) {
    stdout.writeln('NO_BUNDLE_SAMPLE');
    exitCode = 2;
    return;
  }

  final sample = bundles.first;
  final chatId = sample['chat_id'];
  final productIds = sample['product_ids'];
  stdout.writeln('sample_chat=$chatId product_ids=$productIds');

  final row = <String, dynamic>{
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'chat_id': chatId,
    'product_ids': productIds,
    'subtotal_eur': 32.0,
    'discount_pct': 10.0,
    'discount_eur': 3.2,
    'total_eur': 28.8,
    'status': 'pending',
  };

  try {
    final inserted = await client.insertAsUser(
      'product_bundles',
      row,
      accessToken: token,
    );
    final id = inserted['id']?.toString();
    stdout.writeln('SELLER_INSERT_OK id=$id');
    if (id != null && id.isNotEmpty) {
      await client.deleteWhere('product_bundles', 'id=eq.$id');
      stdout.writeln('CLEANUP_OK');
    }
  } catch (e) {
    stdout.writeln('SELLER_INSERT_FAIL $e');
    exitCode = 1;
  }
}
