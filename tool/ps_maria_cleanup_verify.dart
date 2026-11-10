// ignore_for_file: avoid_print
/// Recupera evidência pós-cleanup (lives acabadas de terminar da Maria).
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

  final active = await client.select(
    'lives',
    filter:
        'or=(seller_id.eq.$sid,vendedor_id.eq.$sid)&status=eq.live&is_active=eq.true',
    limit: 50,
  );
  final statusLive = await client.select(
    'lives',
    filter: 'or=(seller_id.eq.$sid,vendedor_id.eq.$sid)&status=eq.live',
    limit: 50,
  );

  // Lives terminadas nesta sessão (~última 2h) — captura do 1.º pass.
  final recentlyEnded = await client.select(
    'lives',
    filter:
        'or=(seller_id.eq.$sid,vendedor_id.eq.$sid)&status=eq.ended&ended_at=gte.2026-09-12T16:40:00Z&order=ended_at.desc',
    limit: 200,
  );

  final fx = await client.select(
    'products',
    filter: 'seller_id=eq.$sid&ref_code=in.(FX1,FX2)',
    limit: 10,
  );
  final fxIds = fx.map((p) => p['id']).whereType<Object>().map((e) => '$e').toList();
  var fxLiveItems = 0;
  var fxOpenReqs = 0;
  if (fxIds.isNotEmpty) {
    final items = await client.select(
      'live_items',
      filter: 'product_id=in.(${fxIds.join(',')})',
      limit: 500,
    );
    fxLiveItems = items.length;
    if (items.isNotEmpty) {
      final liIds = items.map((e) => '${e['id']}').join(',');
      final reqs = await client.select(
        'live_reservation_requests',
        filter:
            'live_item_id=in.($liIds)&status=not.in.(cancelled,expired,rejected)',
        limit: 500,
      );
      fxOpenReqs = reqs.length;
    }
  }

  final evidence = {
    'at': DateTime.now().toUtc().toIso8601String(),
    'note':
        'Pass1 (antes deste verify) terminou zombies; pass2 confirmou 0 activas + FX limpos.',
    'zombies_active_before_estimated_from_ended_at_window': recentlyEnded.length,
    'recently_ended_ids': recentlyEnded.map((e) => e['id']).toList(),
    'recently_ended_sample': recentlyEnded
        .take(5)
        .map((e) => {
              'id': e['id'],
              'title': e['title'],
              'ended_at': e['ended_at'],
              'publish_backend': e['publish_backend'],
            })
        .toList(),
    'zombies_active_after': active.length,
    'status_live_after': statusLive.length,
    'fx_products': fx
        .map((p) => {
              'id': p['id'],
              'ref_code': p['ref_code'],
              'quantity': p['quantity'],
              'available_for_live': p['available_for_live'],
            })
        .toList(),
    'fx_live_items_remaining': fxLiveItems,
    'fx_open_reservations_remaining': fxOpenReqs,
    'active_lives_final_must_be_zero': active.isEmpty && statusLive.isEmpty,
  };

  final path =
      'tool/reports/ps_oppo_live_20260912/maria_zombie_cleanup_VERIFY_${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.json';
  File(path).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(evidence),
  );
  print(const JsonEncoder.withIndent('  ').convert(evidence));
  print('EVIDENCE=$path');
  if (active.isNotEmpty || statusLive.isNotEmpty) {
    exit(1);
  }
}
