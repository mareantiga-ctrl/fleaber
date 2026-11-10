// ignore_for_file: avoid_print
/// C27 — fechar live activa na BD (BATATA).
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
  final env = _readEnv(File('.maestro/.env'));
  final liveId = env['MAESTRO_LIVE_ID']?.trim() ?? '';
  if (!isUuid(liveId)) {
    stderr.writeln('FAIL: MAESTRO_LIVE_ID');
    exit(1);
  }
  await client.patch('lives', 'id=eq.$liveId', {
    'status': 'ended',
    'is_active': false,
  });
  print('live $liveId ended');
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
