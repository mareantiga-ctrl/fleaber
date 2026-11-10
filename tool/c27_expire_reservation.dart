// ignore_for_file: avoid_print
/// C27 — expirar reserva aceite (APP-253) via RPC oficial.
///
///   dart run tool/c27_expire_reservation.dart
///   dart run tool/c27_expire_reservation.dart --id=UUID
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

void main(List<String> args) async {
  String? onlyId;
  for (final a in args) {
    if (a.startsWith('--id=')) onlyId = a.split('=').last.trim();
  }

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final env = _readEnv(File('.maestro/.env'));
  final liveId = env['MAESTRO_LIVE_ID']?.trim() ?? '';
  final sellerId = env['MAESTRO_SELLER_ID']?.trim() ?? '';
  if (!isUuid(liveId) || !isUuid(sellerId)) {
    stderr.writeln('FAIL: MAESTRO_LIVE_ID / MAESTRO_SELLER_ID');
    exit(1);
  }

  var filter =
      'live_id=eq.$liveId&status=eq.accepted&order=created_at.desc';
  if (onlyId != null && onlyId.isNotEmpty) {
    filter = 'id=eq.$onlyId';
  }

  final rows = await client.select(
    'live_reservation_requests',
    filter: filter,
    limit: 5,
  );
  if (rows.isEmpty) {
    stderr.writeln('FAIL: nenhuma reserva accepted para expirar');
    exit(2);
  }
  final req = rows.first;
  final reqId = req['id']!.toString();

  final res = await client.rpc('batata_process_live_reservation_request', {
    'p_request_id': reqId,
    'p_action': 'expire',
    'p_processed_by': sellerId,
    'p_notes': 'c27_app253_expire',
  });

  final after = (await client.select(
    'live_reservation_requests',
    filter: 'id=eq.$reqId',
    limit: 1,
  ))
      .first;

  final out = {
    'request_id': reqId,
    'rpc': res,
    'before_status': req['status'],
    'after_status': after['status'],
    'live_item_id': after['live_item_id'],
  };
  print(jsonEncode(out));
  if (after['status']?.toString() != 'expired') exit(3);
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
