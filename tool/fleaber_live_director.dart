#!/usr/bin/env dart
// CLI runner Live Director — corre motor com service role (staging).
// Uso: dart run tool/fleaber_live_director.dart --run-id <uuid>

import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  String? runId;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--run-id' && i + 1 < args.length) {
      runId = args[++i].trim();
    }
    if (args[i] == '--help' || args[i] == '-h') {
      stdout.writeln('''
Live Director CLI (staging)

  dart run tool/fleaber_live_director.dart --run-id <uuid>

Requer tool/live_ops_staging.env e SQL live_director_batata.sql aplicado.
O motor completo corre na Admin Console; este CLI valida run e estado.
''');
      exit(0);
    }
  }

  if (runId == null || runId.isEmpty) {
    stderr.writeln('Erro: --run-id obrigatório');
    exit(2);
  }

  final env = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final rows = await client.select(
    'live_director_runs',
    filter: 'id=eq.$runId',
    limit: 1,
  );
  if (rows.isEmpty) {
    stderr.writeln('Run não encontrada: $runId');
    exit(1);
  }

  final run = rows.first;
  stdout.writeln('Run: $runId');
  stdout.writeln('Status: ${run['status']}');
  stdout.writeln('Live: ${run['live_id']}');
  stdout.writeln('Modo: ${run['mode']}');
  stdout.writeln('');
  stdout.writeln('Para executar beats, abre /admin/live-director → Console → Iniciar Director.');
  stdout.writeln('Este CLI confirma que a run existe e o ambiente staging responde.');
  exit(0);
}
