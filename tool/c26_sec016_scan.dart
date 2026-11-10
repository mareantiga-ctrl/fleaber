// ignore_for_file: avoid_print
/// C26 — SEC-016: lives com playback / VOD + smoke edge.
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
  final seller = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  final lives = await sb.select(
    'lives',
    filter: 'seller_id=eq.$seller&order=created_at.desc',
    limit: 40,
  );

  final withLivePb = <Map<String, dynamic>>[];
  final withVod = <Map<String, dynamic>>[];
  final ended = <Map<String, dynamic>>[];
  for (final l in lives) {
    final row = {
      'id': l['id'],
      'title': l['title'] ?? l['name'],
      'status': l['status'],
      'is_active': l['is_active'],
      'mux_playback_id': l['mux_playback_id'],
      'mux_vod_playback_id': l['mux_vod_playback_id'],
      'created_at': l['created_at'],
    };
    final pb = (l['mux_playback_id'] ?? '').toString();
    final vod = (l['mux_vod_playback_id'] ?? '').toString();
    if (pb.isNotEmpty) withLivePb.add(row);
    if (vod.isNotEmpty) withVod.add(row);
    if ((l['status'] ?? '').toString() == 'ended' || l['is_active'] == false) {
      ended.add(row);
    }
  }

  // Edge smoke (anon should not get secrets; resolve may 401/200)
  Map<String, dynamic>? edgeResult;
  final probeId = withVod.isNotEmpty
      ? withVod.first['id']
      : (withLivePb.isNotEmpty ? withLivePb.first['id'] : (ended.isNotEmpty ? ended.first['id'] : null));
  if (probeId != null) {
    try {
      final uri = Uri.parse(
        '${normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'))}/functions/v1/resolve-mux-playback',
      );
      final res = await HttpClient().postUrl(uri).then((req) async {
        req.headers.set('Authorization', 'Bearer ${envRequire(env, 'SUPABASE_ANON_KEY')}');
        req.headers.set('apikey', envRequire(env, 'SUPABASE_ANON_KEY'));
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'live_id': probeId}));
        return req.close();
      });
      final body = await res.transform(utf8.decoder).join();
      edgeResult = {
        'http': res.statusCode,
        'body_preview': body.length > 400 ? '${body.substring(0, 400)}…' : body,
        'live_id': probeId,
      };
    } catch (e) {
      edgeResult = {'error': e.toString(), 'live_id': probeId};
    }
  }

  final out = {
    'seller': seller,
    'counts': {
      'lives_scanned': lives.length,
      'with_live_playback': withLivePb.length,
      'with_vod': withVod.length,
      'ended_or_inactive': ended.length,
    },
    'vod_candidates': withVod.take(5).toList(),
    'live_pb_candidates': withLivePb.take(5).toList(),
    'ended_sample': ended.take(5).toList(),
    'edge': edgeResult,
    'ui_target': withVod.isNotEmpty
        ? {'path': 'open_vod_player', 'live': withVod.first}
        : (ended.isNotEmpty
            ? {'path': 'gravados_preparing_or_card', 'live': ended.first}
            : {'path': 'no_lives', 'live': null}),
  };

  final dir = Directory('tool/reports/battery_c26_2026-08-22/bd');
  await dir.create(recursive: true);
  await File('${dir.path}/c26_sec016_scan.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print(jsonEncode(out['ui_target']));
  print('edge=${jsonEncode(edgeResult)}');
  print('vod=${withVod.length} livePb=${withLivePb.length}');
}
