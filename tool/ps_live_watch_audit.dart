// ignore_for_file: avoid_print
/// Watch / snapshot BD das reservas PS da live mais recente (ou --live-id).
///
/// Uso:
///   dart run tool/ps_live_watch_audit.dart
///   dart run tool/ps_live_watch_audit.dart --live-id UUID
///   dart run tool/ps_live_watch_audit.dart --watch   (atualiza a cada 8s)
library;

import 'dart:io';

import 'live_ops_staging_client.dart';
import 'regression/staging_guard.dart';

Future<void> main(List<String> args) async {
  String? liveId;
  var watch = false;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--live-id' && i + 1 < args.length) {
      liveId = args[++i];
    } else if (args[i] == '--watch') {
      watch = true;
    }
  }

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

  Future<void> dump() async {
    var lid = liveId?.trim() ?? '';
    if (lid.isEmpty) {
      final lives = await client.select(
        'lives',
        filter: 'order=created_at.desc',
        limit: 1,
      );
      if (lives.isEmpty) {
        print('Sem lives.');
        return;
      }
      lid = (lives.first['id'] ?? '').toString();
      print(
        'Live mais recente: ${lives.first['title']} | '
        'created=${lives.first['created_at']} | id=$lid',
      );
    }

    final items = await client.select(
      'live_items',
      filter: 'live_id=eq.$lid&order=created_at.asc',
      limit: 40,
    );
    print('\n--- artigos ---');
    for (final i in items) {
      print('  ${i['ref_code']} qty=${i['quantity']} id=${i['id']}');
    }

    final reqs = await client.select(
      'live_reservation_requests',
      filter: 'live_id=eq.$lid&order=created_at.asc',
      limit: 100,
    );
    final pending = reqs.where((r) => r['status'] == 'pending' || r['status'] == 'accepted');
    final rejected = reqs.where((r) => r['status'] == 'rejected');
    print('\n--- reservas (${reqs.length} total · '
        '${pending.length} pendentes/aceites · ${rejected.length} rejected) ---');
    for (final r in reqs) {
      print(
        '  ${r['created_at']} | ${r['status']} | '
        'ref=${r['resolved_ref_slug']} qty=${r['requested_qty']} | '
        '${r['external_display_name']}\n'
        '    raw=${r['ocr_raw_line']}',
      );
    }

    print('\n=== RESUMO ESPERADO NO CENTRO ===');
    print('reservas (contador card) ≈ ${reqs.length}');
    print('pagamentos pendentes ≈ ${pending.length}');
    print('Abrir resumo → Reservas FB/PS deve listar sobretudo pending/accepted.');

    try {
      final panel = await client.select(
        'ps_panel_events',
        filter: 'live_id=eq.$lid&order=created_at.asc',
        limit: 200,
      );
      if (panel.isNotEmpty) {
        print('\n--- painel PS (${panel.length} eventos) ---');
        for (final e in panel) {
          final kind = e['event_kind'] ?? '';
          final msg = e['message'] ?? '';
          final detail = e['detail'];
          final meta = e['meta'];
          print(
            '  ${e['created_at']} | $kind | $msg'
            '${detail != null && detail.toString().isNotEmpty ? '\n    → $detail' : ''}'
            '${meta != null ? '\n    meta=$meta' : ''}',
          );
        }
      } else {
        print('\n--- painel PS: sem eventos (ext v1.4+ + SQL ps_panel_events?) ---');
      }
    } catch (e) {
      print('\n--- painel PS: tabela indisponível ($e) ---');
    }

    print('\n=== SYNC TREINO (agente) ===');
    print('powershell -File tool/ps_ai/sync_training_pipeline.ps1 -LiveId $lid -Battery TT');
  }

  await dump();
  if (!watch) return;

  print('\nA observar (Ctrl+C para parar)…');
  while (true) {
    await Future<void>.delayed(const Duration(seconds: 8));
    print('\n──────── ${DateTime.now().toIso8601String()} ────────');
    await dump();
  }
}
