import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const sid = '980f4fa1-0004-42f9-abca-69f1a9c29588';
  final act = await sb.select(
    'lives',
    filter: 'or=(seller_id.eq.$sid,vendedor_id.eq.$sid)&is_active=eq.true&order=created_at.desc',
    limit: 10,
  );
  print('IS_ACTIVE_TRUE count=${act.length}');
  for (final l in act) {
    print('  ${l['id']} status=${l['status']} seller=${l['seller_id']} vend=${l['vendedor_id']} created=${l['created_at']} title=${l['title']}');
  }
  // Full row for race live
  final race = await sb.select('lives', filter: 'id=eq.f90d7927-b17f-4f1c-b78c-6a45da22a2c7', limit: 1);
  if (race.isNotEmpty) {
    final l = race.first;
    final keys = [
      'id','status','is_active','went_live_at','ended_at','created_at','updated_at',
      'mux_playback_id','mux_vod_playback_id','mux_live_stream_id','publish_backend',
      'seller_id','vendedor_id','title'
    ];
    for (final k in keys) {
      print('RACE.$k=${l[k]}');
    }
  }
  // Ingest samples with ocr line
  final ingest = await sb.select(
    'ps_ingest_audit',
    filter: 'live_id=eq.f90d7927-b17f-4f1c-b78c-6a45da22a2c7&order=created_at.asc',
    limit: 5,
  );
  for (final r in ingest) {
    print('ING ${r['created_at']} err=${r['error']} intent=${r['parser_intent']} ref=${r['ref_slug_in']} line=${r['ocr_raw_line']} name=${r['external_display_name']}');
  }
  // Hub view items
  try {
    final hubItems = await sb.select(
      'hub_live_items_public',
      filter: 'live_id=eq.f90d7927-b17f-4f1c-b78c-6a45da22a2c7',
      limit: 10,
    );
    print('HUB_ITEMS=${hubItems.length}');
    for (final i in hubItems) {
      print('  hub ${i['ref_code']} active=${i['is_active']}');
    }
  } catch (e) {
    print('HUB_ITEMS_ERR $e');
  }
  try {
    final hubLive = await sb.select(
      'hub_lives_public',
      filter: 'id=eq.f90d7927-b17f-4f1c-b78c-6a45da22a2c7',
      limit: 1,
    );
    print('HUB_LIVE=${hubLive.isEmpty ? null : hubLive.first}');
  } catch (e) {
    print('HUB_LIVE_ERR $e');
  }
}
