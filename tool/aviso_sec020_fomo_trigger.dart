// ignore_for_file: avoid_print
/// SEC-020 — dispara FOMO «Ultima unidade» (stock 2→1) + mensagem sistema.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final liveEnv = File('tool/reports/battery_aviso_live_2026-08-23/bd/live.env');
  var liveId = '';
  var liveItemId = '';
  if (liveEnv.existsSync()) {
    for (final line in liveEnv.readAsLinesSync()) {
      if (line.startsWith('MAESTRO_LIVE_ID=')) {
        liveId = line.substring('MAESTRO_LIVE_ID='.length).trim();
      }
      if (line.startsWith('AVISO218_LIVE_ITEM_ID=')) {
        liveItemId = line.substring('AVISO218_LIVE_ITEM_ID='.length).trim();
      }
    }
  }
  if (liveId.isEmpty) {
    stderr.writeln('FAIL: live.env em falta — corre aviso_live_activate.dart');
    exit(1);
  }

  // Post FOMO system message (mesmo contrato LiveFomoBroadcaster).
  final body = '🔥 Ultima unidade — C27 Produto B';
  final row = await sb.insert('live_messages', {
    'live_id': liveId,
    'kind': 'system',
    'body': body,
    'sender_label': 'Fleaber',
  });
  print('fomo msg id=${row['id']} body=$body');

  // Also drop product qty to 1 for BD coherence.
  final act = File('tool/reports/battery_aviso_live_2026-08-23/bd/live_active.json');
  if (act.existsSync()) {
    final j = jsonDecode(await act.readAsString()) as Map<String, dynamic>;
    final pid = j['fomo_product_id']?.toString() ?? '';
    if (pid.isNotEmpty) {
      try {
        await sb.patch('products', 'id=eq.$pid', {'quantity': 1});
        print('product $pid qty=1');
      } catch (e) {
        print('qty patch warn: $e');
      }
    }
  }

  final out = {
    'live_id': liveId,
    'live_item_id': liveItemId,
    'message_id': row['id'],
    'body': body,
    'at': DateTime.now().toUtc().toIso8601String(),
  };
  await File('tool/reports/battery_aviso_live_2026-08-23/bd/sec020_fomo.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out));
}
