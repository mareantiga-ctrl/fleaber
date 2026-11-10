/// PASS 2 — Q2 egress/publish: plant mux_live_id / egress; complete alheio; leak.
import 'dart:io';

import '_rtq.dart';

void main() async {
  final env = loadEnv();
  final c = Rtq.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final liveA = await c.insertLive(
    seller: c.sellerId,
    active: true,
    muxLiveId: 'ML_RTQ_VICTIM_A',
    streamKey: 'SK_RTQ_VICTIM_A',
    egressId: 'EG_RTQ_VICTIM_A',
    roomName: 'fleaber_rtq_victim_a',
    muxPlayback: 'PB_RTQ_A',
  );
  final liveB = await c.insertLive(
    seller: c.seller2Id,
    active: true,
    muxLiveId: 'ML_RTQ_OWN_B',
    streamKey: 'SK_RTQ_OWN_B',
    egressId: 'EG_RTQ_OWN_B',
    roomName: 'fleaber_rtq_own_b',
  );
  c.note('p2.fixture', 'lives A/B', {'A': liveA, 'B': liveB}, lens: 'Q2');

  // Q2-a: leak columns via buyer SELECT
  final leak = await c.rest(
    'GET',
    'lives?id=eq.$liveA&select=id,seller_id,mux_live_id,mux_stream_key,stream_key,livekit_egress_id,mux_playback_id,status',
    jwt: c.buyerJwt,
  );
  c.note('p2.q2.leak.buyer', 'buyer SELECT keys live A', leak.brief, lens: 'Q2');
  final leaked = leak.map ?? {};
  final leakedMux = leaked['mux_live_id']?.toString();
  final leakedKey = (leaked['mux_stream_key'] ?? leaked['stream_key'])?.toString();
  final leakedEg = leaked['livekit_egress_id']?.toString();
  if (leak.ok &&
      ((leakedKey != null && leakedKey.isNotEmpty) ||
          (leakedEg != null && leakedEg.isNotEmpty))) {
    c.hold(
      id: 'RTQ-Q2-buyer-select-stream-or-egress',
      lens: 'Q2',
      severity: 'P2',
      title: 'Comprador lê mux_stream_key ou livekit_egress_id da live alheia',
      actor: 'buyer JWT',
      pre: 'live A pública',
      repro: 'GET lives?id=eq.<A>&select=mux_stream_key,livekit_egress_id',
      expected: 'colunas de publish ocultas',
      obtained: leaked,
    );
  }

  // Q2-b: S2 plant mux_live_id da vítima na própria live, complete-mux-live
  final plantMux = await c.rest(
    'PATCH',
    'lives?id=eq.$liveB',
    jwt: c.seller2Jwt,
    body: {'mux_live_id': leakedMux ?? 'ML_RTQ_VICTIM_A'},
  );
  c.note('p2.q2.plant.mux', 'S2 PATCH mux_live_id=vítima', plantMux.brief,
      lens: 'Q2');
  final liveBAfterPlant = await c.liveRow(liveB ?? '');
  final complete = await c.edge(
    'complete-mux-live',
    {'live_id': liveB},
    jwt: c.seller2Jwt,
  );
  c.note('p2.q2.complete.planted', 'complete-mux-live após plant', complete.brief,
      lens: 'Q2');
  final liveAAfterComplete = await c.liveRow(liveA ?? '');
  final usedVictim = (complete.body.contains('ML_RTQ_VICTIM_A') ||
          complete.body.contains(leakedMux ?? '___none___')) &&
      complete.status != 403 &&
      complete.status != 401;
  if (plantMux.ok && usedVictim) {
    c.hold(
      id: 'RTQ-Q2-plant-mux-live-id-complete',
      lens: 'Q2',
      severity: 'P1',
      title:
          'S2 grava mux_live_id alheio na própria live e complete-mux-live usa-o',
      actor: 'seller2 JWT',
      pre: 'live B própria; mux_live_id de A conhecido por SELECT ou fixture',
      repro:
          'PATCH lives.mux_live_id=<A>; POST complete-mux-live live_id=<B>',
      expected: 'mux_live_id imutável / complete só do Mux criado para esta live',
      obtained: complete.brief,
      evidence: {
        'plant': plantMux.brief,
        'liveB': liveBAfterPlant,
        'liveA_after': liveAAfterComplete,
      },
    );
  }

  // Recreate B if complete ended it
  var liveB2 = liveB;
  final bState = await c.liveRow(liveB ?? '');
  if (bState?['status'] == 'ended' || bState?['is_active'] == false) {
    liveB2 = await c.insertLive(
      seller: c.seller2Id,
      active: true,
      muxLiveId: 'ML_RTQ_OWN_B2',
      egressId: 'EG_RTQ_OWN_B2',
    );
  }

  // Q2-c: plant egress_id then stop_egress (variante nova vs body.egress_id)
  final plantEg = await c.rest(
    'PATCH',
    'lives?id=eq.$liveB2',
    jwt: c.seller2Jwt,
    body: {'livekit_egress_id': leakedEg ?? 'EG_RTQ_VICTIM_A'},
  );
  c.note('p2.q2.plant.egress', 'S2 PATCH livekit_egress_id=vítima', plantEg.brief,
      lens: 'Q2');
  final stop = await c.edge(
    'livekit-mux-publish',
    {
      'step': 'stop_egress',
      'live_id': liveB2,
      'egress_id': leakedEg ?? 'EG_RTQ_VICTIM_A',
    },
    jwt: c.seller2Jwt,
  );
  c.note('p2.q2.stop.planted', 'stop_egress após plant na row', stop.brief,
      lens: 'Q2');
  final stopUsedPlant = stop.ok ||
      (stop.status != 403 &&
          stop.status != 401 &&
          (stop.body.contains('EG_RTQ_VICTIM_A') ||
              stop.body.contains(leakedEg ?? '___none___') ||
              stop.map?['stopped'] != null));
  if (plantEg.ok && stopUsedPlant && stop.status != 403) {
    c.hold(
      id: 'RTQ-Q2-plant-egress-id-stop',
      lens: 'Q2',
      severity: 'P1',
      title:
          'S2 planta livekit_egress_id alheio na própria live e stop_egress segue a row',
      actor: 'seller2 JWT',
      pre: 'variante nova: não envia só egress_id no body; escreve na lives',
      repro:
          'PATCH lives.livekit_egress_id=<A>; POST livekit-mux-publish step=stop_egress live_id=<B>',
      expected: 'egress_id da row não injectável / stop só do egress desta live',
      obtained: stop.brief,
      evidence: {'plant': plantEg.brief, 'liveB': await c.liveRow(liveB2 ?? '')},
    );
  }

  // Q2-d: buyer stop / complete live A by id leak
  final buyerStop = await c.edge(
    'livekit-mux-publish',
    {'step': 'stop_egress', 'live_id': liveA},
    jwt: c.buyerJwt,
  );
  final buyerComplete = await c.edge(
    'complete-mux-live',
    {'live_id': liveA},
    jwt: c.buyerJwt,
  );
  final buyerToken = await c.edge(
    'livekit-mux-publish',
    {'step': 'token', 'live_id': liveA},
    jwt: c.buyerJwt,
  );
  c.note('p2.q2.buyer.stop', 'buyer stop live A', buyerStop.brief, lens: 'Q2');
  c.note('p2.q2.buyer.complete', 'buyer complete live A', buyerComplete.brief,
      lens: 'Q2');
  c.note('p2.q2.buyer.token', 'buyer token live A', buyerToken.brief, lens: 'Q2');
  if (buyerStop.ok || buyerComplete.ok || buyerToken.ok) {
    c.hold(
      id: 'RTQ-Q2-buyer-publish-or-stop-foreign',
      lens: 'Q2',
      severity: 'P0',
      title: 'Comprador para ou publica live alheia por ID',
      actor: 'buyer JWT',
      pre: 'live_id A conhecido',
      repro: 'POST livekit-mux-publish/complete-mux-live live_id=<A>',
      expected: '403 Sem permissão',
      obtained: {
        'stop': buyerStop.brief,
        'complete': buyerComplete.brief,
        'token': buyerToken.brief,
      },
    );
  }

  // Q2-e: S2 PATCH live A status ended
  final endForeign = await c.rest(
    'PATCH',
    'lives?id=eq.$liveA',
    jwt: c.seller2Jwt,
    body: {'status': 'ended', 'is_active': false},
  );
  c.note('p2.q2.s2.endA', 'S2 PATCH ended live A', endForeign.brief, lens: 'Q2');
  final aAfterEnd = await c.liveRow(liveA ?? '');
  if (endForeign.ok &&
      (aAfterEnd?['status'] == 'ended' || aAfterEnd?['is_active'] == false)) {
    c.hold(
      id: 'RTQ-Q2-s2-patch-end-foreign-live',
      lens: 'Q2',
      severity: 'P0',
      title: 'S2 termina live A via PATCH status=ended',
      actor: 'seller2 JWT',
      pre: 'live A de S1',
      repro: 'PATCH lives status=ended is_active=false',
      expected: 'RLS 0 rows',
      obtained: aAfterEnd,
    );
  }

  // Q2-f: buyer PATCH is_active false
  final buyerPatch = await c.rest(
    'PATCH',
    'lives?id=eq.$liveA',
    jwt: c.buyerJwt,
    body: {'is_active': false},
  );
  c.note('p2.q2.buyer.patch', 'buyer PATCH is_active', buyerPatch.brief,
      lens: 'Q2');

  await c.endLives();
  await dumpJson('${outDir()}/pass2.json', {
    'notes': c.notes,
    'findings': c.findings,
  });
  stdout.writeln('PASS2 findings=${c.findings.length}');
  exit(0);
}
