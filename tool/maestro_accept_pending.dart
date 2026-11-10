// ignore_for_file: avoid_print
/// Aceita reservas pendentes pelo backend (sem precisar da UI seller ao vivo).
///
/// Usa o mesmo RPC da app: batata_process_live_reservation_request (p_action=accept).
///
/// Uso:
///   dart run tool/maestro_accept_pending.dart                # aceita todas pendentes do seller
///   dart run tool/maestro_accept_pending.dart --live-id=UUID # só dessa live
///   dart run tool/maestro_accept_pending.dart --ref=W2       # só ref_code que contenha W2
///   dart run tool/maestro_accept_pending.dart --list         # só lista, não aceita
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

void main(List<String> args) async {
  String? liveId;
  String? ref;
  String? onlyId;
  var listOnly = false;
  for (final a in args) {
    if (a.startsWith('--live-id=')) liveId = a.split('=').last.trim();
    if (a.startsWith('--ref=')) ref = a.split('=').last.trim();
    if (a.startsWith('--id=')) onlyId = a.split('=').last.trim();
    if (a == '--list') listOnly = true;
  }

  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final env = _readEnv(File('.maestro/.env'));
  final sellerId = env['MAESTRO_SELLER_ID']?.trim() ?? '';
  if (!isUuid(sellerId)) {
    stderr.writeln('MAESTRO_SELLER_ID inválido em .maestro/.env');
    exit(1);
  }

  var filter = 'seller_id=eq.$sellerId&status=eq.pending&order=created_at.desc';
  if (liveId != null && liveId.isNotEmpty) {
    filter = 'seller_id=eq.$sellerId&status=eq.pending&live_id=eq.$liveId'
        '&order=created_at.desc';
  }

  final pending = await client.select(
    'live_reservation_requests',
    filter: filter,
    limit: 50,
  );

  final targets = pending.where((r) {
    if (onlyId != null && onlyId.isNotEmpty) {
      return (r['id'] ?? '').toString() == onlyId;
    }
    if (ref == null || ref.isEmpty) return true;
    final rc = (r['ref_code'] ?? '').toString().toLowerCase();
    return rc.contains(ref.toLowerCase());
  }).toList();

  print('Pendentes encontradas: ${pending.length} (alvo: ${targets.length})');
  for (final r in targets) {
    print('  ${r['id']}  ref=${r['ref_code']}  qty=${r['requested_qty']}  '
        'live=${r['live_id']}  buyer=${r['buyer_id']}');
  }

  if (listOnly) return;

  var ok = 0;
  for (final r in targets) {
    final reqId = r['id']!.toString();
    try {
      final res = await client.rpc('batata_process_live_reservation_request', {
        'p_request_id': reqId,
        'p_action': 'accept',
        'p_processed_by': sellerId,
        'p_notes': 'maestro_backend_accept',
      });
      print('ACEITE $reqId → $res');
      ok++;
    } catch (e) {
      print('FALHA $reqId → $e');
    }
  }
  print('maestro_accept_pending OK: $ok/${targets.length} aceites');
}

Map<String, String> _readEnv(File file) {
  final map = <String, String>{};
  if (!file.existsSync()) return map;
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i < 1) continue;
    map[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  return map;
}

String envRequire(Map<String, String> env, String key) {
  final v = env[key]?.trim() ?? '';
  if (v.isEmpty) throw StateError('$key em falta');
  return v;
}
