// ignore_for_file: avoid_print
/// End all active lives for the staging seller (post-test hygiene).
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final sellerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final sellerId = await client.userIdForAccessToken(sellerToken);
  final active = await client.select(
    'lives',
    filter:
        'seller_id=eq.$sellerId&or=(status.eq.live,is_active.eq.true)',
    limit: 200,
  );
  final ended = <String>[];
  for (final row in active) {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) continue;
    await client.patch(
      'lives',
      'id=eq.$id',
      {
        'status': 'ended',
        'is_active': false,
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    ended.add(id);
  }
  final out = {
    'seller_id': sellerId,
    'found_active': active.length,
    'ended_ids': ended,
  };
  final dir = Directory('14-unified-commerce-phase5.4-final-visual-proof/raw');
  await dir.create(recursive: true);
  final f = File('${dir.path}/lives_ended.json');
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
}
