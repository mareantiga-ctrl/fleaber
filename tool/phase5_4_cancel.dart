// ignore_for_file: avoid_print
/// Cancel guaranteed reservation (canonical buyer RPC) for Phase 5.4 D proof.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  final seedPath = args.isNotEmpty
      ? args.first
      : '14-unified-commerce-phase5.4-final-visual-proof/raw/seed_cancel.json';
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
    email: (seed['buyer_email'] ??
            envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'))
        .toString(),
    password: (seed['buyer_password'] ??
            envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'))
        .toString(),
  );

  Future<int> avail() async {
    final snap = await client.rpc(
      'batata_live_item_stock',
      {'p_live_item_id': itemId},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    return (snap['available_qty'] as num?)?.toInt() ?? -1;
  }

  final before = await client.select(
    'live_reservation_requests',
    filter: 'id=eq.$requestId',
    limit: 1,
  );
  final availBefore = await avail();
  final rpc = await client.rpc(
    'batata_commerce_cancel_guaranteed_reservation',
    {'p_request_id': requestId},
    accessToken: buyerToken,
  );
  final after = await client.select(
    'live_reservation_requests',
    filter: 'id=eq.$requestId',
    limit: 1,
  );
  final availAfter = await avail();
  final failures = await client.select(
    'buyer_trust_events',
    filter:
        'buyer_id=eq.${seed['buyer_id']}&kind=eq.failure&failure_reason=eq.guaranteed_hold_expired_unpaid',
    limit: 20,
  );
  final out = {
    'request_id': requestId,
    'row_before': before.isEmpty ? null : before.first,
    'available_qty_before': availBefore,
    'cancel_rpc': rpc,
    'row_after': after.isEmpty ? null : after.first,
    'available_qty_after': availAfter,
    'd25_failure_rows_sample': failures.length,
    'stock_released': availAfter > availBefore,
  };
  final f = File(
    '14-unified-commerce-phase5.4-final-visual-proof/raw/cancel_rpc.json',
  );
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
  print('Wrote ${f.path}');
}
