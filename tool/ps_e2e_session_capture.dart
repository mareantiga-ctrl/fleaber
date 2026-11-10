// ignore_for_file: avoid_print
/// Captura reservas + itens de uma live para evidência E2E.
/// dart run tool/ps_e2e_session_capture.dart --live-id=UUID
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  String? liveId;
  for (final a in args) {
    if (a.startsWith('--live-id=')) liveId = a.substring('--live-id='.length);
  }
  if (liveId == null || liveId!.trim().isEmpty) {
    stderr.writeln('Uso: dart run tool/ps_e2e_session_capture.dart --live-id=UUID');
    exit(2);
  }
  liveId = liveId!.trim();

  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final lives = await sb.select('lives', filter: 'id=eq.$liveId', limit: 1);
  final items = await sb.select(
    'live_items',
    filter: 'live_id=eq.$liveId&order=created_at.asc',
    limit: 50,
  );
  final reqs = await sb.select(
    'live_reservation_requests',
    filter: 'live_id=eq.$liveId&order=created_at.asc',
    limit: 100,
  );

  final out = {
    'at': DateTime.now().toUtc().toIso8601String(),
    'live_id': liveId,
    'live': lives.isEmpty ? null : lives.first,
    'live_items': items,
    'reservations': reqs,
    'mariana_buyer_id': '69104e91-6a00-40d9-a7c9-b1571422ae43',
    'mariana_oauth_provider_id': '122187140426664823',
  };

  final dir = Directory(
    'tool/reports/battery_ps_face_real_BRIEFING_AUDITOR/provas',
  )..createSync(recursive: true);
  final path = '${dir.path}/CAPTURE_live_${liveId}_LATEST.json';
  File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print(const JsonEncoder.withIndent('  ').convert({
    'written': path,
    'items': items.length,
    'reservations': reqs.length,
    'live_status': lives.isEmpty ? null : lives.first['status'],
  }));
}
