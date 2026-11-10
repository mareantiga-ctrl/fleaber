import 'dart:io';

import '_rtn.dart';

/// Pass 4 — state-final: retract false positives; seller_id spoof on reservations; tip row.
void main() async {
  final c = Rtn.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final out = <String, Object?>{
    'auditor': 'REDTEAM_BLIND_N_LIVE_STREAM_v1',
    'pass': 4,
    'stamp': stamp,
  };

  final liveA = await c.insertLive(
    seller: c.sellerId,
    status: 'live',
    active: true,
    muxPlayback: 'rtn4_a_pb_$stamp',
    muxLiveId: 'rtn4_a_mux_$stamp',
    streamKey: 'rtn4_a_sk_$stamp',
  );
  final itemH = await c.rest('POST', 'live_items', service: true, body: {
    'live_id': liveA,
    'ref_code': 'RTN4A',
    'title': '$prefix a',
    'price': 7,
    'is_active': true,
    'quantity': 1,
    'status': 'available',
  });
  final itemA = itemH.firstId;
  if (itemA != null) c.createdLiveItemIds.add(itemA);

  // prior pass3 ids
  const priorResS2 = '01677f6a-5e0a-4c7f-80af-df2880b9dd6e';
  const priorTip = '7e3899bf-19a5-4e57-a8e7-0b2289049ea6';
  const priorTipX = '05c8b5e0-d1df-4ee2-940f-15cfd6ffd438';

  final prevS2 = await c.rest(
    'GET',
    'live_reservation_requests?id=eq.$priorResS2&select=id,status,buyer_id,seller_id,requested_qty',
    service: true,
  );
  c.note('p4.prev.s2res', 'pass3 s2 reservation status', prevS2.brief, lens: 'N5');
  out['prev.s2.status'] = prevS2.map;
  final st = prevS2.map?['status']?.toString();
  if (st == 'accepted' || st == 'converted') {
    c.finding(
      id: 'RTN-n5.bag.s2.confirmed',
      lens: 'N5',
      severity: 'P1',
      title: 'reserva pass3 de S2 ficou accepted/converted',
      actor: 'seller2',
      pre: 'INSERT status=accepted',
      repro: 'GET service reservation 01677f6a',
      expected: 'pending (coerção)',
      obtained: st,
    );
  } else {
    c.hold(
      id: 'n5.bag.s2.coerced',
      lens: 'N5',
      title: 'INSERT accepted de não-dono foi coerido (não P1)',
      actor: 'seller2',
      obtained: st ?? prevS2.brief,
    );
  }

  final tipRow = await c.rest(
    'GET',
    'live_tips?id=eq.$priorTip&select=id,status,amount,stripe_session_id,buyer_id,seller_id,payment_source',
    service: true,
  );
  c.note('p4.prev.tip', 'pass3 tip pending', tipRow.brief, lens: 'N7');
  out['prev.tip'] = tipRow.map;
  final cs = tipRow.map?['stripe_session_id'];
  if (cs != null && cs.toString().isNotEmpty) {
    c.finding(
      id: 'RTN-n7.tip.cs.persist',
      lens: 'N7',
      severity: 'P1',
      title: 'tip pending gravou stripe_session_id do cliente',
      actor: 'buyer',
      pre: 'p_stripe_session_id forjado',
      repro: 'GET live_tips id',
      expected: 'null',
      obtained: cs,
    );
  } else {
    c.hold(
      id: 'n7.tip.cs.null',
      lens: 'N7',
      title: 'create_live_tip_pending ignora session do cliente (null)',
      actor: 'buyer',
      obtained: tipRow.map?['status'],
    );
  }

  final tipX = await c.rest(
    'GET',
    'live_tips?id=eq.$priorTipX&select=id,buyer_id,seller_id,amount,status',
    service: true,
  );
  out['prev.tipX'] = tipX.map;
  final weAreSeller = tipX.map?['seller_id']?.toString() == c.buyerId;
  c.note('p4.tipx.role', 'tips.cross row: we are seller?', weAreSeller, lens: 'N7');
  if (weAreSeller) {
    c.hold(
      id: 'n7.tips.cross.retract',
      lens: 'N7',
      title: 'tips.cross era gorjeta em que o JWT é o vendedor — RLS própria, retratado',
      actor: 'buyer',
      obtained: tipX.map,
    );
  }

  final alienTips = await c.rest(
    'GET',
    'live_tips?and=(seller_id.neq.${c.buyerId},buyer_id.neq.${c.buyerId})&select=id,buyer_id,seller_id,amount&limit=5',
    jwt: c.buyerJwt,
  );
  c.note('p4.tips.alien', 'tips where we are neither party', alienTips.brief,
      lens: 'N7');
  out['tips.alien'] = {'http': alienTips.status, 'n': alienTips.list.length};
  if (alienTips.ok && alienTips.list.isNotEmpty) {
    c.finding(
      id: 'RTN-n7.tips.alien',
      lens: 'N7',
      severity: 'P1',
      title: 'comprador lê live_tips onde não é buyer nem seller',
      actor: 'buyer',
      pre: 'filtro seller_id≠me AND buyer_id≠me',
      repro: 'GET live_tips',
      expected: '[]',
      obtained: alienTips.brief,
    );
  } else {
    c.hold(
      id: 'n7.tips.parties_only',
      lens: 'N7',
      title: 'JWT não lê tips alheias (só onde é parte)',
      actor: 'buyer',
      obtained: alienTips,
    );
  }

  // wallets before spoof
  Future<double?> bal(String id) async {
    final h = await c.rest(
      'GET',
      'wallets?id=eq.$id&select=id,balance',
      service: true,
    );
    final b = h.map?['balance'];
    if (b is num) return b.toDouble();
    return double.tryParse('$b');
  }

  final wSeller0 = await bal(c.sellerId!);
  final wBuyer0 = await bal(c.buyerId!);
  out['wallet.before'] = {'seller': wSeller0, 'buyer': wBuyer0};

  // ----- N5 seller_id spoof: S2 claims seller_id=self on live A -----
  final spoof = await c.rest(
    'POST',
    'live_reservation_requests',
    jwt: c.seller2Jwt,
    body: {
      'live_id': liveA,
      'live_item_id': itemA,
      'seller_id': c.seller2Id,
      'buyer_id': c.seller2Id,
      'requested_qty': 1,
      'status': 'accepted',
      'source': 'fleaber_live',
    },
  );
  c.note('p4.n5.spoof.seller_id', 'S2 INSERT accepted seller_id=self on live A',
      spoof.brief,
      lens: 'N5');
  out['n5.spoof'] = spoof.map ?? spoof.snippet;
  if (spoof.firstId != null) c.createdRequestIds.add(spoof.firstId!);
  final spoofSt = spoof.map?['status']?.toString();
  final spoofSeller = spoof.map?['seller_id']?.toString();
  if (spoof.ok && spoofSt == 'accepted') {
    c.finding(
      id: 'RTN-n5.spoof.seller_id',
      lens: 'N5',
      severity: 'P0',
      title: 'S2 spoofa seller_id=próprio e INSERT reserva accepted no artigo da live A',
      actor: 'seller2',
      pre: 'live A do lab seller, item qty=1, body.seller_id=S2',
      repro: 'POST live_reservation_requests seller_id=<self> status=accepted',
      expected: 'pending ou 403 (seller_id tem de ser o dono da live)',
      obtained: 'status=$spoofSt seller_id=$spoofSeller',
      evidence: {'row': spoof.map},
    );
  } else if (spoof.ok) {
    c.hold(
      id: 'n5.spoof.pending',
      lens: 'N5',
      title: 'spoof seller_id não ficou accepted (status=$spoofSt)',
      actor: 'seller2',
      obtained: spoof.map,
    );
  } else {
    c.hold(
      id: 'n5.spoof.denied',
      lens: 'N5',
      title: 'spoof seller_id recusado',
      actor: 'seller2',
      obtained: spoof,
    );
  }

  final stock = itemA == null
      ? null
      : await c.rpc('batata_live_item_stock', {'p_live_item_id': itemA},
          jwt: c.sellerJwt);
  c.note('p4.n5.stock', 'stock after spoof', stock?.brief, lens: 'N5');
  out['n5.stock.after'] = stock?.json ?? stock?.snippet;

  // S2 try process accept on B1 request if any
  final proc = await c.rpc(
    'batata_process_live_reservation_request',
    {
      'p_request_id': spoof.firstId ?? priorResS2,
      'p_action': 'accept',
      'p_processed_by': c.seller2Id,
    },
    jwt: c.seller2Jwt,
  );
  c.note('p4.n5.proc.s2', 'S2 process accept', proc.brief, lens: 'N5');
  out['n5.proc.s2'] = proc.json ?? proc.snippet;
  if (proc.ok && proc.map?['ok'] == true) {
    c.finding(
      id: 'RTN-n5.proc.s2',
      lens: 'N5',
      severity: 'P1',
      title: 'S2 processa reserva da live A',
      actor: 'seller2',
      pre: 'não é dono',
      repro: 'rpc batata_process_live_reservation_request accept',
      expected: 'not_allowed',
      obtained: proc.brief,
    );
  }

  // settle tip via edge GET
  final settle = await c.edge(
    'create-live-tip-checkout',
    method: 'GET',
    qs: '?checkout_return=success&session_id=cs_test_rtn3_forged_$stamp',
    jwt: c.buyerJwt,
  );
  c.note('p4.n7.settle.forged', 'GET tip settle forged cs', settle.brief, lens: 'N7');
  out['n7.settle'] = settle.brief;

  final wSeller1 = await bal(c.sellerId!);
  final wBuyer1 = await bal(c.buyerId!);
  out['wallet.after'] = {'seller': wSeller1, 'buyer': wBuyer1};
  final dS = (wSeller1 ?? 0) - (wSeller0 ?? 0);
  final dB = (wBuyer1 ?? 0) - (wBuyer0 ?? 0);
  if (dS.abs() > 0.001 || dB.abs() > 0.001) {
    c.finding(
      id: 'RTN-n7.wallet.delta',
      lens: 'N8',
      severity: 'P0',
      title: 'Δwallet após tip pending/settle forjado',
      actor: 'buyer',
      pre: 'sem captura Stripe',
      repro: 'create_live_tip_pending + GET settle',
      expected: 'Δ=0',
      obtained: 'seller $dS buyer $dB',
    );
  } else {
    c.hold(
      id: 'n7.wallet.delta0',
      lens: 'N7',
      title: 'sem Δwallet (pending ≠ captura)',
      actor: 'buyer',
      obtained: 'seller=$wSeller1 buyer=$wBuyer1',
    );
  }

  // device tokens star again: lab seller
  final tokLab = await c.rest(
    'GET',
    'seller_device_tokens?seller_id=eq.${c.sellerId}&select=id,seller_id,token_hash',
    jwt: c.buyerJwt,
  );
  final tokStar = await c.rest(
    'GET',
    'seller_device_tokens?select=id,seller_id,token_hash&limit=10',
    jwt: c.buyerJwt,
  );
  c.note(
    'p4.n1.tok',
    'tokens lab vs list',
    'lab.n=${tokLab.list.length} list.n=${tokStar.list.length} ids=${tokStar.list.whereType<Map>().map((e) => e['seller_id']).toSet()}',
    lens: 'N1',
  );
  out['n1.tok'] = {
    'lab_n': tokLab.list.length,
    'list_n': tokStar.list.length,
    'seller_ids': tokStar.list
        .whereType<Map>()
        .map((e) => e['seller_id']?.toString())
        .toSet()
        .toList(),
  };

  // live_items seller2 GET qty (confirm) — not a finding vs FOMO
  final qty = await c.rest(
    'GET',
    'live_items?id=eq.$itemA&select=quantity',
    jwt: c.buyerJwt,
  );
  out['n5.qty'] = qty.map;

  await c.endLives();
  out['findings'] = c.findings;
  out['holds'] = c.holds;
  out['notes'] = c.notes;
  await dumpJson('${outDir()}/pass4.json', out);
  stdout.writeln('FINDINGS ${c.findings.length} HOLDS ${c.holds.length}');
  stdout.writeln('WROTE ${outDir()}/pass4.json');
}
