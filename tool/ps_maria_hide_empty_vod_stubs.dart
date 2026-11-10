// ignore_for_file: avoid_print
/// Staging Maria: oculta stubs ended sem VOD da vista Hub (status=discarded).
/// Só seller fleahub-demo-ux; não toca grants nem outras sellers.
library;

import 'dart:convert';
import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main() async {
  final staging = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(staging, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: not staging');
    exit(2);
  }
  final client = LiveOpsStagingClient(
    url: url,
    anonKey: envRequire(staging, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(staging, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const sid = '980f4fa1-0004-42f9-abca-69f1a9c29588';

  final ended = await client.select(
    'lives',
    filter:
        'or=(seller_id.eq.$sid,vendedor_id.eq.$sid)&status=eq.ended&order=created_at.desc',
    limit: 500,
  );

  final toHide = <String>[];
  final keepPlayable = <String>[];
  for (final row in ended) {
    final id = '${row['id']}'.trim();
    if (id.isEmpty) continue;
    final vod = '${row['mux_vod_playback_id'] ?? ''}'.trim();
    if (vod.isNotEmpty) {
      keepPlayable.add(id);
      continue;
    }
    toHide.add(id);
  }

  final hidden = <String>[];
  final failed = <String>[];
  for (final id in toHide) {
    try {
      await client.patch(
        'lives',
        'id=eq.$id&or=(seller_id.eq.$sid,vendedor_id.eq.$sid)',
        {
          'status': 'discarded',
          'is_active': false,
        },
      );
      hidden.add(id);
    } catch (e) {
      failed.add('$id → $e');
    }
  }

  final evidence = {
    'at': DateTime.now().toUtc().toIso8601String(),
    'seller_id': sid,
    'ended_scanned': ended.length,
    'playable_kept': keepPlayable.length,
    'empty_vod_hidden': hidden.length,
    'hidden_ids_sample': hidden.take(10).toList(),
    'failed': failed.take(5).toList(),
  };
  final path =
      'tool/reports/ps_oppo_live_20260912/maria_hide_empty_vod_${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.json';
  File(path).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(evidence),
  );
  print(const JsonEncoder.withIndent('  ').convert(evidence));
  print('EVIDENCE=$path');
  if (failed.isNotEmpty && hidden.isEmpty) exit(1);
}
