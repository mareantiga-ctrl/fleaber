// ignore_for_file: avoid_print
import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const sid = '980f4fa1-0004-42f9-abca-69f1a9c29588';
  final lives = await sb.select(
    'lives',
    filter: 'or=(seller_id.eq.$sid,vendedor_id.eq.$sid)&order=created_at.desc',
    limit: 8,
  );
  for (final l in lives) {
    print(
      'LIVE ${l['id']} status=${l['status']} active=${l['is_active']} went=${l['went_live_at']} created=${l['created_at']} ended=${l['ended_at']}',
    );
  }
  final latest = lives.isNotEmpty ? '${lives.first['id']}' : '';
  print('LATEST=$latest');
  if (latest.isNotEmpty) {
    final items = await sb.select(
      'live_items',
      filter: 'live_id=eq.$latest&order=created_at.asc',
      limit: 20,
    );
    print('ITEMS_COUNT=${items.length}');
    for (final i in items) {
      print(
        '  ${i['ref_code']} active=${i['is_active']} status=${i['status']} kind=${i['item_kind']} id=${i['id']}',
      );
    }
  }
  final liveNow = await sb.select(
    'lives',
    filter: 'or=(seller_id.eq.$sid,vendedor_id.eq.$sid)&status=eq.live&order=created_at.desc',
    limit: 10,
  );
  print('STATUS_LIVE_COUNT=${liveNow.length}');
  for (final l in liveNow) {
    print('  STILL_LIVE ${l['id']} active=${l['is_active']}');
  }
  // also is_active true any status
  final act = await sb.select(
    'lives',
    filter: 'or=(seller_id.eq.$sid,vendedor_id.eq.$sid)&is_active=eq.true&order=created_at.desc',
    limit: 10,
  );
  print('IS_ACTIVE_TRUE=${act.length}');
  final ingest = await sb.select('ps_ingest_audit', filter: 'order=created_at.desc', limit: 25);
  for (final r in ingest.take(20)) {
    final raw = '${r['raw_text'] ?? r['comment_text'] ?? r['raw_line'] ?? r['ceo_comentario'] ?? ''}';
    print(
      'INGEST t=${r['created_at']} live=${r['live_id']} ok=${r['ok']} err=${r['error'] ?? r['error_code'] ?? r['result']} raw=$raw keys=${r.keys.take(12).toList()}',
    );
  }
  try {
    final pair = await sb.select('ps_pairing_sessions', filter: 'order=created_at.desc', limit: 5);
    for (final p in pair) {
      print('PAIR t=${p['created_at']} live=${p['live_id']} claimed=${p['claimed_at']}');
    }
  } catch (e) {
    print('PAIR_ERR $e');
  }
}
