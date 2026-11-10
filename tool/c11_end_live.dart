// ignore_for_file: avoid_print
/// Fecha a live C11 na BD (não deixar directo a correr).
///
///   dart run tool/c11_end_live.dart
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final envFile = File('.maestro/.env');
  var liveId = '';
  if (envFile.existsSync()) {
    for (final line in envFile.readAsLinesSync()) {
      if (line.startsWith('MAESTRO_LIVE_ID=')) {
        liveId = line.substring('MAESTRO_LIVE_ID='.length).trim();
      }
    }
  }
  if (!isUuid(liveId)) {
    stderr.writeln('FAIL: MAESTRO_LIVE_ID');
    exit(1);
  }
  await client.patch(
    'lives',
    'id=eq.$liveId',
    {'status': 'ended', 'is_active': false},
  );
  print('C11 live ended $liveId');
}
