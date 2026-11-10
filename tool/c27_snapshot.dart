// ignore_for_file: avoid_print
/// C27 — snapshot BD (live, reservas, saco).
///
///   dart run tool/c27_snapshot.dart --label=before_expire
library;

import 'dart:convert';
import 'dart:io';

import 'bag_crosscheck_logic.dart';
import 'live_ops_staging_client.dart';

const _reportDir = 'tool/reports/battery_c27_2026-08-23';

void main(List<String> args) async {
  var label = 'snap';
  for (final a in args) {
    if (a.startsWith('--label=')) label = a.split('=').last.trim();
  }

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final env = _readEnv(File('.maestro/.env'));
  final liveId = env['MAESTRO_LIVE_ID']?.trim() ?? '';
  if (!isUuid(liveId)) {
    stderr.writeln('FAIL: MAESTRO_LIVE_ID');
    exit(1);
  }
  var buyerId = staging['LIVE_OPS_TEST_BUYER_ID']?.trim() ?? '';
  if (!isUuid(buyerId)) {
    final t = await client.signIn(
      email: envRequire(staging, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(staging, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
    );
    buyerId = await client.userIdForAccessToken(t);
  }

  final lives = await client.select('lives', filter: 'id=eq.$liveId', limit: 1);
  final items = await client.select(
    'live_items',
    filter: 'live_id=eq.$liveId&order=is_active.desc,created_at.asc',
    limit: 200,
  );
  final reservations = await client.select(
    'live_reservation_requests',
    filter: 'live_id=eq.$liveId&order=created_at.desc',
    limit: 50,
  );

  final buyerRows = reservations
      .where((r) => r['buyer_id']?.toString() == buyerId)
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
  final bag = BagCrosscheckLogic.fromRows(buyerRows);

  Map<String, dynamic> slimRes(Map<String, dynamic> r) => {
        'id': r['id'],
        'status': r['status'],
        'requested_qty': r['requested_qty'],
        'live_item_id': r['live_item_id'],
        'expires_at': r['expires_at'],
      };

  final out = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'label': label,
    'live_id': liveId,
    'buyer_id': buyerId,
    'live': lives.isEmpty
        ? null
        : {
            'id': lives.first['id'],
            'status': lives.first['status'],
            'is_active': lives.first['is_active'],
          },
    'items': items
        .map((i) => {
              'id': i['id'],
              'title': i['title'],
              'is_active': i['is_active'],
              'status': i['status'],
            })
        .toList(),
    'reservations': reservations.map(slimRes).toList(),
    'bag': {
      'in_bag_units': bag.inBagUnitQty,
      'pending_visible': bag.pendingVisibleInBag,
    },
  };

  Directory('$_reportDir/bd').createSync(recursive: true);
  final file = File('$_reportDir/bd/c27_$label.json');
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print('wrote ${file.path}');
  print(jsonEncode(out));
}

Map<String, String> _readEnv(File file) {
  final out = <String, String>{};
  if (!file.existsSync()) return out;
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i < 1) continue;
    out[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  return out;
}
