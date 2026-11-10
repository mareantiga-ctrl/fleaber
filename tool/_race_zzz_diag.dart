import 'dart:convert';
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final sb = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  const seller = '980f4fa1-0004-42f9-abca-69f1a9c29588';
  const mariana = '69104e91-6a00-40d9-a7c9-b1571422ae43';

  final items = await sb.select('live_items', filter: 'ref_code=ilike.*ZZZ*', limit: 30);
  print('ZZZ items ${items.length}');
  items.sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
  for (final i in items.take(10)) {
    print('  live=${i['live_id']} ref=${i['ref_code']} qty=${i['quantity']} status=${i['status']} kind=${i['item_kind']} created=${i['created_at']}');
  }

  final lives = await sb.select('lives', filter: 'seller_id=eq.$seller', limit: 10);
  lives.sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
  print('Recent lives:');
  for (final l in lives.take(4)) {
    print('  ${l['id']} status=${l['status']} active=${l['is_active']} went=${l['went_live_at']} mux=${l['mux_playback_id']}');
  }

  String liveId = '';
  if (items.isNotEmpty) {
    liveId = items.first['live_id'] as String;
  } else if (lives.isNotEmpty) {
    liveId = lives.first['id'] as String;
  }
  print('FOCUS $liveId');

  final L = (await sb.select('lives', filter: 'id=eq.$liveId', limit: 1)).first;
  print('LIVE ${jsonEncode({'status': L['status'], 'active': L['is_active'], 'mux': L['mux_playback_id'], 'went': L['went_live_at']})}');

  final li = await sb.select('live_items', filter: 'live_id=eq.$liveId', limit: 20);
  print('items ${li.length}');
  for (final i in li) {
    print('  ${i['ref_code']} id=${i['id']} qty=${i['quantity']} status=${i['status']} kind=${i['item_kind']} product=${i['product_id']}');
  }

  final res = await sb.select('live_reservation_requests', filter: 'live_id=eq.$liveId', limit: 40);
  print('reservations ${res.length}');
  for (final r in res) {
    print('  ${r['created_at']} status=${r['status']} src=${r['source']} buyer=${r['buyer_id']} qty=${r['requested_qty']} name=${r['external_display_name']} ref=${r['external_buyer_ref']} item=${r['live_item_id']} notes=${r['notes']}');
  }

  final msgs = await sb.select('live_messages', filter: 'live_id=eq.$liveId', limit: 30);
  print('msgs ${msgs.length}');
  for (final m in msgs) {
    print('  ${m['created_at']} ${m['kind']} ${m['body']}');
  }

  final mine = await sb.select('live_reservation_requests', filter: 'live_id=eq.$liveId&buyer_id=eq.$mariana', limit: 20);
  print('mariana ${mine.length}');
  for (final r in mine) {
    print('  status=${r['status']} src=${r['source']} qty=${r['requested_qty']}');
  }

  for (final i in li) {
    try {
      final st = await sb.rpc('batata_live_item_stock', {'p_live_item_id': i['id']});
      print('stock ${i['ref_code']} $st');
    } catch (e) {
      print('stock ${i['ref_code']} ERR $e');
    }
  }

  final hub = await sb.select('hub_lives_public', filter: 'id=eq.$liveId', limit: 1);
  print('hub live mux=${hub.isEmpty ? null : hub.first['mux_playback_id']} status=${hub.isEmpty ? null : hub.first['status']}');
}
