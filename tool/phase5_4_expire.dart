// ignore_for_file: avoid_print
/// Force expiry of guaranteed reservation for Phase 5.4 E proof.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  final seedPath = args.isNotEmpty
      ? args.first
      : '14-unified-commerce-phase5.4-final-visual-proof/raw/seed_expiry.json';
  final seed =
      jsonDecode(await File(seedPath).readAsString()) as Map<String, dynamic>;
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final requestId = seed['request_id']!.toString();
  final itemId = seed['item_id']!.toString();
  final buyerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );

  Future<int> avail() async {
    final snap = await client.rpc(
      'batata_live_item_stock',
      {'p_live_item_id': itemId},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    return (snap['available_qty'] as num?)?.toInt() ?? -1;
  }

  final past = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
  await client.patch(
    'live_reservation_requests',
    'id=eq.$requestId',
    {'expires_at': past.toIso8601String()},
  );
  final before = await client.select(
    'live_reservation_requests',
    filter: 'id=eq.$requestId',
    limit: 1,
  );
  final availBefore = await avail();
  final exp = await client.rpc(
    'batata_expire_guaranteed_reservations',
    {
      'p_now': DateTime.now().toUtc().toIso8601String(),
      'p_request_id': requestId,
    },
  );
  final after = await client.select(
    'live_reservation_requests',
    filter: 'id=eq.$requestId',
    limit: 1,
  );
  final out = {
    'request_id': requestId,
    'expires_at_patched_to': past.toIso8601String(),
    'row_before': before.isEmpty ? null : before.first,
    'available_qty_before': availBefore,
    'expire_rpc': exp,
    'row_after': after.isEmpty ? null : after.first,
    'available_qty_after': await avail(),
  };
  final f = File(
    '14-unified-commerce-phase5.4-final-visual-proof/raw/expire_rpc.json',
  );
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
  print('Wrote ${f.path}');
}
