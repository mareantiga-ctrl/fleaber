// ignore_for_file: avoid_print
/// Diagnostico: rifa(s) e participacoes da live atual (MAESTRO_LIVE_ID).
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

void main(List<String> args) async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(_req(staging, 'SUPABASE_URL')),
    anonKey: _req(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: _req(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final env = _readEnv(File('.maestro/.env'));
  final liveId = env['MAESTRO_LIVE_ID']?.trim() ?? '';
  print('live_id=$liveId');

  final raffles = await client.select(
    'live_raffles',
    filter: 'live_id=eq.$liveId&order=created_at.desc',
    limit: 20,
  );
  print('Rifas: ${raffles.length}');
  for (final r in raffles) {
    print('  raffle=${r['id']}  status=${r['status']}  '
        'item=${r['live_item_id']}  entries=${r['entries_count']}');
    final entries = await client.select(
      'live_raffle_entries',
      filter: 'raffle_id=eq.${r['id']}',
      limit: 50,
    );
    print('    entries rows: ${entries.length}');
    for (final e in entries) {
      print('      buyer=${e['buyer_id'] ?? e['user_id']}  '
          'qty=${e['entries'] ?? e['entry_count'] ?? e['qty']}  '
          'src=${e['source']}');
    }
  }
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

String _req(Map<String, String> env, String key) {
  final v = env[key]?.trim() ?? '';
  if (v.isEmpty) throw StateError('$key em falta');
  return v;
}
