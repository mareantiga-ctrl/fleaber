// ignore_for_file: avoid_print
/// Termina live APP-218/SEC-020 + force-stop players.
library;

import 'dart:io';

import 'live_ops_staging_client.dart';

Future<void> main(List<String> args) async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  var liveId = args.isNotEmpty ? args.first.trim() : '';
  if (liveId.isEmpty) {
    final f = File('tool/reports/battery_aviso_live_2026-08-23/bd/live.env');
    if (f.existsSync()) {
      for (final line in f.readAsLinesSync()) {
        if (line.startsWith('MAESTRO_LIVE_ID=')) {
          liveId = line.substring('MAESTRO_LIVE_ID='.length).trim();
        }
      }
    }
  }
  if (liveId.isEmpty) {
    // end all active for seller
    final lives = await sb.select(
      'lives',
      filter: 'or=(seller_id.eq.$sellerId,vendedor_id.eq.$sellerId)&is_active=eq.true',
      limit: 20,
    );
    for (final l in lives) {
      final id = l['id'].toString();
      await sb.patch('lives', 'id=eq.$id', {
        'status': 'ended',
        'is_active': false,
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      });
      print('ended $id');
    }
    print('done (all active)');
    return;
  }

  await sb.patch('lives', 'id=eq.$liveId', {
    'status': 'ended',
    'is_active': false,
    'ended_at': DateTime.now().toUtc().toIso8601String(),
  });
  print('ended $liveId');
}
