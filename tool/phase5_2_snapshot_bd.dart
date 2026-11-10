// ignore_for_file: avoid_print
/// Snapshot backend state for a Phase 5.2 request / live after UI action.
///
///   dart run tool/phase5_2_snapshot_bd.dart <scenario> [request_id]
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/phase5_2_snapshot_bd.dart g|l|m|n1|n2');
    exit(2);
  }
  final scenario = args.first.trim().toLowerCase();
  final seedPath =
      '14-unified-commerce-phase5.2-final-evidence/raw/seed_$scenario.json';
  final seed =
      jsonDecode(await File(seedPath).readAsString()) as Map<String, dynamic>;

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final buyerToken = await client.signIn(
    email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );

  final liveId = seed['live_id']?.toString() ?? '';
  final itemId = seed['item_id']?.toString() ?? '';
  final sellerId = seed['seller_id']?.toString() ?? '';
  final buyerId = seed['buyer_id']?.toString() ?? '';
  final requestId = (args.length > 1
          ? args[1]
          : (seed['request_id'] ??
              seed['pending_request_id'] ??
              ''))
      .toString();

  Future<int> avail() async {
    if (itemId.isEmpty) return -1;
    final snap = await client.rpc(
      'batata_live_item_stock',
      {'p_live_item_id': itemId},
      accessToken: buyerToken,
    ) as Map<String, dynamic>;
    return (snap['available_qty'] as num?)?.toInt() ?? -1;
  }

  final rows = requestId.isEmpty
      ? <Map<String, dynamic>>[]
      : await client.select(
          'live_reservation_requests',
          filter: 'id=eq.$requestId',
          limit: 1,
        );
  final liveRows = liveId.isEmpty
      ? <Map<String, dynamic>>[]
      : await client.select(
          'live_reservation_requests',
          filter: 'live_id=eq.$liveId',
          limit: 50,
        );
  final trust = (sellerId.isEmpty || buyerId.isEmpty)
      ? <Map<String, dynamic>>[]
      : await client.select(
          'seller_buyer_trust',
          filter: 'seller_id=eq.$sellerId&buyer_id=eq.$buyerId',
          limit: 1,
        );
  final events = <Map<String, dynamic>>[];
  // Optional commerce events table may not exist on all staging schemas.
  try {
    if (requestId.isNotEmpty) {
      events.addAll(
        await client.select(
          'commerce_reservation_events',
          filter: 'request_id=eq.$requestId',
          limit: 30,
        ),
      );
    }
  } catch (_) {}
  try {
    if (requestId.isNotEmpty && events.isEmpty) {
      events.addAll(
        await client.select(
          'reservation_lifecycle_events',
          filter: 'request_id=eq.$requestId',
          limit: 30,
        ),
      );
    }
  } catch (_) {}

  final failures = buyerId.isEmpty
      ? <Map<String, dynamic>>[]
      : await client.select(
          'buyer_trust_events',
          filter:
              'buyer_id=eq.$buyerId&kind=eq.failure&failure_reason=eq.guaranteed_hold_expired_unpaid',
          limit: 20,
        );

  final snap = {
    'scenario': scenario,
    'captured_at': DateTime.now().toUtc().toIso8601String(),
    'request_id': requestId,
    'row': rows.isEmpty ? null : rows.first,
    'all_live_rows': liveRows,
    'available_qty': await avail(),
    'seller_buyer_trust': trust,
    'live_reservation_events': events,
    'd25_failures_sample_count': failures.length,
    'seed_ref': seedPath,
  };

  final out = File(
    '14-unified-commerce-phase5.2-final-evidence/raw/bd_after_$scenario.json',
  );
  await out.parent.create(recursive: true);
  await out.writeAsString(const JsonEncoder.withIndent('  ').convert(snap));
  print(jsonEncode(snap));
  print('Wrote ${out.path}');
}
