import 'dart:io';

import '_rtaw.dart';

/// Pass 2 — deepen P3 draft Hub + total_qty UUID; confirm lives ended. No fixes.
void main() async {
  final c = Rtaw.fromEnv(loadEnv());
  await c.loginActors();

  const draftId = 'cd6d425c-8891-445f-b2be-7f901bdaac13';
  const errorId = '06021c4d-270b-47cf-9dd9-ceffed8d6ab5';
  const livePub = '181fc282-68ad-469f-8e10-e4e592d3d859';
  const endedAvail = '4da8d43f-332a-47ab-ac95-f50ce475f978';
  const endedRf = 'a71ab22f-8afd-4cb8-bbcc-8836bbeeb08c';
  const hitchZero = '157accc0-389f-4478-bb27-ca929da77a89';
  const pausedItem = '62ffcbe4-f4f3-4516-b54a-d3caaff628d5';
  const showing = '6c925d2b-fc26-42ce-b713-ef8526e5ca86';

  final out = <String, Object?>{
    'auditor': 'REDTEAM_BLIND_AW_HUB_EDGE_POS_ANAS_v1',
    'pass': 2,
    'stamp': stamp,
  };

  final lives = await c.rest(
    'GET',
    'lives?id=in.($draftId,$errorId,$livePub)&select=id,status,is_active,title',
    service: true,
  );
  out['lives_svc'] = lives.json;

  final hub = await c.rest(
    'GET',
    'hub_lives_public?id=in.($draftId,$errorId,$livePub)&select=id,status,is_active,mux_playback_id,mux_vod_playback_id,title',
  );
  out['hub_lives'] = hub.json;
  final rows = hub.list.whereType<Map>().toList();
  final draftRow = rows.where((r) => r['id'] == draftId).toList();
  final errorRow = rows.where((r) => r['id'] == errorId).toList();
  out['draft_row'] = draftRow;
  out['error_row'] = errorRow;

  if (draftRow.isNotEmpty) {
    c.finding(
      id: 'RTAW-AW1-DRAFT-ACTIVE-HUB-LIVES',
      lens: 'AW1',
      severity: 'P3',
      title: 'hub_lives_public ainda lista draft (mesmo após endLives se status não mudou para ended)',
      actor: 'anon',
      pre: 'pass1 draft+is_active; pass2 re-read',
      repro: 'GET hub_lives_public?id=eq.draft',
      expected: '[] após cleanup ended, ou ausente se ainda draft',
      obtained: draftRow,
    );
  }

  if (errorRow.isNotEmpty) {
    c.finding(
      id: 'RTAW-AW1-ERROR-ACTIVE-HUB-LIVES',
      lens: 'AW1',
      severity: 'P3',
      title: 'hub_lives_public lista status=error via OR is_active',
      actor: 'anon',
      pre: 'status=error is_active (cleanup may have ended it)',
      repro: 'GET hub_lives_public',
      expected: 'error fora da vitrine',
      obtained: errorRow,
    );
  }

  final fomoDraft = await c.rpc('batata_hub_live_fomo_snapshot', {
    'p_live_id': draftId,
  });
  out['fomo_draft'] = fomoDraft.json;

  final qty = <String, Object?>{};
  for (final e in {
    'ended_avail': endedAvail,
    'ended_rf': endedRf,
    'hitch0': hitchZero,
    'paused': pausedItem,
    'showing': showing,
  }.entries) {
    final stock = await c.rpc('batata_live_item_stock', {
      'p_live_item_id': e.value,
    });
    final tq = await c.rpc('batata_live_item_total_qty', {
      'p_live_item_id': e.value,
    });
    qty[e.key] = {'stock': stock.brief, 'qty': tq.brief, 'qty_json': tq.json};
  }
  out['qty_vs_stock'] = qty;

  final muxDraft = await c.edge('resolve-mux-playback', body: {'live_id': draftId});
  final muxErr = await c.edge('resolve-mux-playback', body: {'live_id': errorId});
  out['mux_draft'] = muxDraft.brief;
  out['mux_error'] = muxErr.brief;

  // decimal IP connect (AW2) — confirm Location
  final dec = await c.edge(
    'create-connect-account',
    method: 'GET',
    qs: '?web_return_origin=${Uri.encodeQueryComponent('https://2130706433')}',
  );
  final shorthand = await c.edge(
    'create-connect-account',
    method: 'GET',
    qs: '?web_return_origin=${Uri.encodeQueryComponent('https://127.1')}',
  );
  out['connect_decimal'] = dec.brief;
  out['connect_127_1'] = shorthand.brief;
  if ((dec.location ?? '').contains('127.0.0.1') ||
      (shorthand.location ?? '').contains('127.0.0.1')) {
    c.finding(
      id: 'RTAW-AW2-CONNECT-DECIMAL-LOCALHOST',
      lens: 'AW2',
      severity: 'P3',
      title:
          'Connect GET aceita 2130706433 / 127.1 e 303 para https://127.0.0.1/wallet',
      actor: 'anon',
      pre: 'sanitize hostAllowed(127.0.0.1) após URL parse',
      repro: 'GET create-connect-account?web_return_origin=https://2130706433',
      expected: 'rejeitar IPs decimais / shorthand (não na allowlist literal)',
      obtained: {'decimal': dec.brief, 'shorthand': shorthand.brief},
    );
  }

  out['findings'] = c.findings;
  out['holds'] = c.holds;
  final dir = Directory.current.path.contains('redteam_blind_aw_')
      ? Directory.current.path
      : '${Directory.current.path}/tool/redteam_blind_aw_$stamp';
  await dumpJson('$dir/pass2.json', out);
  stdout.writeln('PASS2 findings=${c.findings.length}');
}
