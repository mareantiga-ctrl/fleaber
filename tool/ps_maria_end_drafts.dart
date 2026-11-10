// ignore_for_file: avoid_print
/// Fecha draft lives da Maria (prep) para reteste limpo FX1/FX2.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final staging = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL')),
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const sid = '980f4fa1-0004-42f9-abca-69f1a9c29588';
  final drafts = await client.select(
    'lives',
    filter:
        'or=(seller_id.eq.$sid,vendedor_id.eq.$sid)&status=in.(draft,scheduled,preparing)&order=created_at.desc',
    limit: 50,
  );
  final endedAt = DateTime.now().toUtc().toIso8601String();
  final ended = <String>[];
  for (final d in drafts) {
    final id = '${d['id']}'.trim();
    if (id.isEmpty) continue;
    await client.patch(
      'lives',
      'id=eq.$id&or=(seller_id.eq.$sid,vendedor_id.eq.$sid)',
      {'status': 'ended', 'is_active': false, 'ended_at': endedAt},
    );
    ended.add(id);
  }
  final out = {
    'at': endedAt,
    'drafts_found': drafts.length,
    'drafts_ended': ended,
  };
  final path =
      'tool/reports/ps_oppo_live_20260912/maria_drafts_cleanup_${endedAt.replaceAll(':', '-')}.json';
  File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print(const JsonEncoder.withIndent('  ').convert(out));
  print('EVIDENCE=$path');
}
