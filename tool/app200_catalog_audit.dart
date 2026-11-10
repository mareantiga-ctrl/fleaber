// ignore_for_file: avoid_print
/// APP-200 reteste — conta marketplace no catálogo da live.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

void main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );

  final liveId = Platform.environment['LIVE_ID'] ??
      (File('.maestro/.env').existsSync()
          ? _readEnv(File('.maestro/.env'))['MAESTRO_LIVE_ID']
          : null);
  if (liveId == null || liveId.trim().isEmpty) {
    stderr.writeln('FAIL: LIVE_ID / MAESTRO_LIVE_ID');
    exit(1);
  }

  final items = await client.select(
    'live_items',
    filter: 'live_id=eq.${liveId.trim()}',
    limit: 500,
  );
  final marketplace = items.where((row) {
    final pid = row['product_id']?.toString().trim() ?? '';
    final kind = row['item_kind']?.toString().trim() ?? '';
    return pid.isNotEmpty && kind != 'live_only';
  }).toList();

  final out = {
    'live_id': liveId.trim(),
    'total_items': items.length,
    'marketplace_count': marketplace.length,
    'marketplace_titles': [
      for (final row in marketplace) row['title']?.toString() ?? '?',
    ],
  };
  print(const JsonEncoder.withIndent('  ').convert(out));
}

Map<String, String> _readEnv(File file) {
  final out = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i < 1) continue;
    out[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  return out;
}
