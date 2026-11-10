// ignore_for_file: avoid_print
/// Auditoria PS — lives e reservas recentes (Z vs ZV).
/// Uso: dart run tool/ps_reservations_audit.dart
library;

import 'dart:io';

import 'live_ops_staging_client.dart';
import 'regression/staging_guard.dart';

Future<void> main() async {
  Map<String, String> env;
  try {
    env = loadLiveOpsStagingEnv();
  } catch (e) {
    print('SKIP_CONFIG: $e');
    exit(3);
  }

  final guard = RegressionStagingGuard.check(env);
  if (!guard.ok) {
    print('SKIP_CONFIG: ${guard.reason}');
    exit(3);
  }

  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  print('=== PS reservations audit ===');
  print('project: ${client.url}\n');

  final lives = await client.select(
    'lives',
    filter: 'order=created_at.desc',
    limit: 15,
  );
  print('--- lives (15 recentes) ---');
  for (final l in lives) {
    print(
      '${l['id']} | ${l['title']} | status=${l['status']} | '
      'created=${l['created_at']} | went_live=${l['went_live_at']} | '
      'seller=${l['seller_id'] ?? l['vendedor_id']}',
    );
  }

  print('\n--- live_items com ref Z ou ZV (recentes) ---');
  final items = await client.select(
    'live_items',
    filter: 'order=created_at.desc',
    limit: 40,
  );
  for (final i in items) {
    final ref = (i['ref_code'] ?? '').toString();
    if (!RegExp(r'\bZV?\d', caseSensitive: false).hasMatch(ref)) continue;
    print(
      '${i['live_id']} | ref=$ref | qty=${i['quantity']} | '
      'created=${i['created_at']}',
    );
  }

  print('\n--- reservas PS/OCR (50 recentes) ---');
  final reqs = await client.select(
    'live_reservation_requests',
    filter: 'order=created_at.desc',
    limit: 50,
  );
  for (final r in reqs) {
    final raw = (r['ocr_raw_line'] ?? '').toString();
    final ref = (r['resolved_ref_slug'] ?? '').toString();
    final ext = (r['external_display_name'] ?? '').toString();
    if (!raw.toUpperCase().contains('ZV') &&
        !ref.toUpperCase().contains('ZV') &&
        !ext.toLowerCase().contains('cláudia') &&
        !ext.toLowerCase().contains('claudia')) {
      continue;
    }
    print(
      '${r['id']} | live=${r['live_id']} | ref=$ref | qty=${r['requested_qty']} | '
      'status=${r['status']} | src=${r['source']} | '
      'detected=${r['detected_at']} | created=${r['created_at']}\n'
      '  name=$ext\n'
      '  raw=$raw',
    );
  }

  print('\n--- reservas hoje (todas, 30) ---');
  final today = DateTime.now().toUtc();
  final since =
      DateTime.utc(today.year, today.month, today.day).toIso8601String();
  final todayReqs = await client.select(
    'live_reservation_requests',
    filter: 'created_at=gte.$since&order=created_at.desc',
    limit: 30,
  );
  for (final r in todayReqs) {
    print(
      '${r['created_at']} | live=${r['live_id']} | ref=${r['resolved_ref_slug']} | '
      'qty=${r['requested_qty']} | ${r['status']} | '
      '${r['external_display_name']} | ${r['ocr_raw_line']}',
    );
  }

  const zvLive = '0d0f7af5-77cc-44a9-9bf3-4ad580f61b95';
  const zLive = 'ec448a42-5112-476e-9511-dde5242fedc0';
  for (final id in [zvLive, zLive]) {
    print('\n=== ALL reservations live $id ===');
    final live = await client.select('lives', filter: 'id=eq.$id', limit: 1);
    if (live.isNotEmpty) {
      final l = live.first;
      print(
        'title=${l['title']} seller=${l['seller_id'] ?? l['vendedor_id']} '
        'created=${l['created_at']}',
      );
    }
    final reqs = await client.select(
      'live_reservation_requests',
      filter: 'live_id=eq.$id&order=created_at.asc',
      limit: 50,
    );
    print('count=${reqs.length}');
    for (final r in reqs) {
      print(
        '  ${r['created_at']} | ref=${r['resolved_ref_slug']} qty=${r['requested_qty']} '
        '${r['status']} | ${r['external_display_name']} | ${r['ocr_raw_line']}',
      );
    }
  }

  for (final sid in [
    '97f3089e-6a84-4f9e-9d4a-4d68b2894fd6',
    '69104e91-6a00-40d9-a7c9-b1571422ae43',
  ]) {
    final p = await client.select('profiles', filter: 'id=eq.$sid', limit: 1);
    if (p.isEmpty) {
      print('\nprofile $sid => (sem perfil)');
      continue;
    }
    print(
      '\nprofile $sid => ${p.first['full_name'] ?? p.first['username'] ?? '?'}',
    );
  }
}
