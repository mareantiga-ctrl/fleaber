// ignore_for_file: avoid_print
/// Cancel open bag lines for staging buyer except optionally keep-listed IDs.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  final keep = args.toSet();
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
  final buyerId = await client.userIdForAccessToken(buyerToken);
  final rows = await client.select(
    'live_reservation_requests',
    filter: 'buyer_id=eq.$buyerId&status=in.(pending,accepted)',
    limit: 400,
  );
  var cancelled = 0;
  final skipped = <String>[];
  for (final r in rows) {
    final id = r['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    if (keep.contains(id)) {
      skipped.add(id);
      continue;
    }
    final kind = (r['request_kind'] ?? '').toString();
    final status = (r['status'] ?? '').toString();
    if (status == 'accepted' && kind == 'guaranteed') {
      try {
        await client.rpc(
          'batata_commerce_cancel_guaranteed_reservation',
          {'p_request_id': id},
          accessToken: buyerToken,
        );
        cancelled++;
        continue;
      } catch (_) {}
    }
    await client.patch(
      'live_reservation_requests',
      'id=eq.$id',
      {
        'status': 'rejected',
        'notes': '${r['notes'] ?? ''} | bag_cancelled | p55_clear',
        'expiry_reason': 'buyer_cancelled',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    cancelled++;
  }
  final out = {
    'buyer_id': buyerId,
    'open_before': rows.length,
    'cancelled': cancelled,
    'kept': skipped,
  };
  final dir = Directory('14-unified-commerce-phase5.5-product-polish-final/raw');
  await dir.create(recursive: true);
  await File('${dir.path}/buyer_bag_cleared.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
}
