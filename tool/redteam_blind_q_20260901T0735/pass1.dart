/// PASS 1 — Q1 live reserva (campos ≠ seller_id) · Q2 egress/publish · Q7 2.º actor.
import 'dart:io';

import '_rtq.dart';

void main() async {
  final env = loadEnv();
  final c = Rtq.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final prodVictim = await c.createProduct(
    title: '$prefix vic-sku',
    seller: c.sellerId,
    qty: 5,
    live: true,
    listed: true,
    price: 14,
  );
  final prodAttack = await c.createProduct(
    title: '$prefix atk-sku',
    seller: c.seller2Id,
    qty: 5,
    live: true,
    listed: true,
    price: 14,
  );

  final liveV = await c.insertLive(
    seller: c.sellerId,
    muxLiveId: 'MLQ_${stamp}_V',
    streamKey: 'SKQ_${stamp}_V',
    egressId: 'EGQ_${stamp}_V',
    roomName: 'fleaber_q_${stamp}_v',
    muxPlayback: 'PBQ_${stamp}_V',
  );
  final liveA = await c.insertLive(
    seller: c.seller2Id,
    muxLiveId: 'MLQ_${stamp}_A',
    streamKey: 'SKQ_${stamp}_A',
    egressId: 'EGQ_${stamp}_A',
    roomName: 'fleaber_q_${stamp}_a',
    muxPlayback: 'PBQ_${stamp}_A',
  );

  final itemV = await c.insertLiveItem(
    liveId: liveV ?? '',
    title: '$prefix itemV',
    qty: 3,
    productId: prodVictim,
  );
  final itemA = await c.insertLiveItem(
    liveId: liveA ?? '',
    title: '$prefix itemA',
    qty: 3,
    productId: prodAttack,
  );

  c.note('p1.fixture', 'lives+items', {
    'liveV': liveV,
    'liveA': liveA,
    'itemV': itemV,
    'itemA': itemA,
    'prodVictim': prodVictim,
    'prodAttack': prodAttack,
  }, lens: 'Q1');

  // ---- Q2: SELECT leak stream / mux_live_id ----
  final selBuyer = await c.rest(
    'GET',
    'lives?id=eq.$liveV&select=id,status,mux_live_id,mux_stream_key,stream_key,livekit_egress_id,mux_playback_id',
    jwt: c.buyerJwt,
  );
  c.note('p1.q2.select.buyer', 'buyer SELECT lives secret cols', selBuyer.brief,
      lens: 'Q2');
  final selAnon = await c.rest(
    'GET',
    'lives?id=eq.$liveV&select=id,mux_live_id,mux_stream_key,stream_key',
  );
  c.note('p1.q2.select.anon', 'anon SELECT lives secret cols', selAnon.brief,
      lens: 'Q2');
  final leakedMux = selBuyer.map?['mux_live_id']?.toString() ??
      selBuyer.map?['mux_stream_key']?.toString();
  if (selBuyer.ok &&
      (selBuyer.map?['mux_stream_key'] != null ||
          selBuyer.map?['stream_key'] != null ||
          selBuyer.map?['mux_live_id'] != null)) {
    c.hold(
      id: 'RTQ-Q2-lives-secret-cols-jwt',
      lens: 'Q2',
      severity: 'P2',
      title: 'JWT comprador lê mux_live_id / stream_key de live alheia',
      actor: 'buyer JWT',
      pre: 'live vítima is_active',
      repro: 'GET /rest/v1/lives?id=eq.<victim>&select=mux_live_id,mux_stream_key',
      expected: 'coluna omitida / 401',
      obtained: selBuyer.brief,
      evidence: {'row': selBuyer.map},
    );
  }

  // ---- Q2: parar live alheia por live_id ----
  final stopBuyer = await c.edge(
    'complete-mux-live',
    {'live_id': liveV},
    jwt: c.buyerJwt,
  );
  final stopS2 = await c.edge(
    'complete-mux-live',
    {'live_id': liveV},
    jwt: c.seller2Jwt,
  );
  final stopAnon = await c.edge('complete-mux-live', {'live_id': liveV});
  c.note('p1.q2.complete.jwt', 'complete-mux-live alheia', {
    'buyer': stopBuyer.brief,
    'seller2': stopS2.brief,
    'anon': stopAnon.brief,
  }, lens: 'Q2');

  final egressBuyer = await c.edge(
    'livekit-mux-publish',
    {'step': 'stop_egress', 'live_id': liveV},
    jwt: c.buyerJwt,
  );
  final egressS2 = await c.edge(
    'livekit-mux-publish',
    {'step': 'egress', 'live_id': liveV, 'stream_key': 'stolen'},
    jwt: c.seller2Jwt,
  );
  final tokenS2 = await c.edge(
    'livekit-mux-publish',
    {'step': 'token', 'live_id': liveV},
    jwt: c.seller2Jwt,
  );
  c.note('p1.q2.livekit', 'livekit-mux-publish alheia', {
    'stop_buyer': egressBuyer.brief,
    'egress_s2': egressS2.brief,
    'token_s2': tokenS2.brief,
  }, lens: 'Q2');

  final liveAfterStop = await c.liveRow(liveV ?? '');
  c.note('p1.q2.live.after', 'live vítima após tentativas stop', liveAfterStop,
      lens: 'Q2');
  if (liveAfterStop?['status']?.toString() == 'ended' ||
      liveAfterStop?['is_active'] == false) {
    c.hold(
      id: 'RTQ-Q2-stop-victim-live-by-id',
      lens: 'Q2',
      severity: 'P0',
      title: '2.º actor / comprador parou live vítima',
      actor: 'buyer|seller2 JWT',
      pre: 'fixture live activa',
      repro: 'POST complete-mux-live | livekit-mux-publish stop_egress live_id vítima',
      expected: '403; live continua activa',
      obtained: liveAfterStop,
    );
  }

  // PATCH lives alheia
  final patchLiveB = await c.rest(
    'PATCH',
    'lives?id=eq.$liveV',
    jwt: c.buyerJwt,
    body: {'status': 'ended', 'is_active': false},
  );
  final patchLiveS2 = await c.rest(
    'PATCH',
    'lives?id=eq.$liveV',
    jwt: c.seller2Jwt,
    body: {'status': 'ended', 'is_active': false},
  );
  c.note('p1.q2.patch.lives', 'PATCH lives vítima', {
    'buyer': patchLiveB.brief,
    'seller2': patchLiveS2.brief,
  }, lens: 'Q2');
  final liveAfterPatch = await c.liveRow(liveV ?? '');
  if (liveAfterPatch?['status']?.toString() == 'ended' &&
      (patchLiveB.ok || patchLiveS2.ok)) {
    c.hold(
      id: 'RTQ-Q2-patch-lives-ended-foreign',
      lens: 'Q2',
      severity: 'P0',
      title: 'PATCH lives status=ended em live alheia',
      actor: 'buyer|seller2',
      pre: 'RLS lives_update_own',
      repro: 'PATCH /rest/v1/lives?id=eq.<victim> status=ended',
      expected: '0 rows / 401',
      obtained: {'patch': patchLiveB.brief, 'row': liveAfterPatch},
    );
  }

  // Clone mux_live_id via INSERT próprio + complete
  final cloneIns = await c.rest('POST', 'lives', jwt: c.seller2Jwt, body: {
    'seller_id': c.seller2Id,
    'vendedor_id': c.seller2Id,
    'title': '$prefix clone mux',
    'status': 'live',
    'is_active': true,
    'mux_live_id': 'MLQ_${stamp}_V',
  });
  c.note('p1.q2.clone.insert', 'seller2 INSERT lives mux_live_id vítima',
      cloneIns.brief,
      lens: 'Q2');
  final cloneId = cloneIns.firstId;
  if (cloneId != null) c.createdLiveIds.add(cloneId);
  if (cloneId != null) {
    final cloneComplete = await c.edge(
      'complete-mux-live',
      {'live_id': cloneId},
      jwt: c.seller2Jwt,
    );
    c.note('p1.q2.clone.complete', 'complete-mux-live no clone',
        cloneComplete.brief,
        lens: 'Q2');
    if (cloneComplete.ok) {
      c.hold(
        id: 'RTQ-Q2-mux-id-clone-complete',
        lens: 'Q2',
        severity: 'P1',
        title: 'INSERT live própria com mux_live_id alheio + complete-mux-live',
        actor: 'seller2 JWT',
        pre: 'mux_live_id conhecido (fixture)',
        repro: 'POST lives mux_live_id=vítima; POST complete-mux-live live_id=clone',
        expected: 'INSERT recusa mux_live_id alheio; complete só no stream próprio',
        obtained: cloneComplete.brief,
      );
    }
  }

  // ---- Q1: seller_id spoof (controlo — clássico, só nota se bloquear) ----
  final spoof = await c.rest('POST', 'live_reservation_requests', jwt: c.buyerJwt, body: {
    'live_id': liveV,
    'live_item_id': itemV,
    'seller_id': c.buyerId,
    'buyer_id': c.buyerId,
    'requested_qty': 1,
    'status': 'accepted',
    'source': 'fleaber_live',
  });
  c.note('p1.q1.spoof.seller_id', 'buyer INSERT accepted seller_id=self',
      spoof.brief,
      lens: 'Q1');
  final spoofId = spoof.firstId;
  if (spoofId != null) c.createdRequestIds.add(spoofId);
  final spoofRow = spoofId == null ? null : await c.reservationRow(spoofId);
  if (spoofRow?['status'] == 'accepted' &&
      spoofRow?['seller_id']?.toString() == c.buyerId) {
    c.hold(
      id: 'RTQ-Q1-seller-id-spoof-accepted',
      lens: 'Q1',
      severity: 'P0',
      title: 'Comprador aceita reserva com seller_id=self (N-P0 ainda aberto)',
      actor: 'buyer JWT',
      pre: 'live vítima',
      repro: 'POST live_reservation_requests status=accepted seller_id=buyer',
      expected: 'pending + seller_id=dono live',
      obtained: spoofRow,
    );
  }

  // Q1 variante: live_item de live A no live_id vítima
  final crossItem = await c.rest(
    'POST',
    'live_reservation_requests',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveV,
      'live_item_id': itemA,
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'requested_qty': 1,
      'status': 'pending',
      'source': 'fleaber_live',
    },
  );
  c.note('p1.q1.cross.item', 'live_item de live A em live V', crossItem.brief,
      lens: 'Q1');
  final crossId = crossItem.firstId;
  if (crossId != null) c.createdRequestIds.add(crossId);
  final crossRow = crossId == null ? null : await c.reservationRow(crossId);
  if (crossItem.ok &&
      crossRow?['live_item_id']?.toString() == itemA &&
      crossRow?['live_id']?.toString() == liveV) {
    c.hold(
      id: 'RTQ-Q1-live-item-cross-live',
      lens: 'Q1',
      severity: 'P0',
      title: 'Reserva com live_item_id de outro directo no live_id vítima',
      actor: 'buyer JWT',
      pre: 'itemA ∈ liveA; liveV vítima',
      repro: 'POST live_reservation_requests live_id=V live_item_id=itemA',
      expected: 'live_item_live_mismatch',
      obtained: crossRow,
    );
  }

  // Q1/Q7: seller2 PATCH live_item product_id = produto vítima
  final hijackItem = await c.rest(
    'PATCH',
    'live_items?id=eq.$itemA',
    jwt: c.seller2Jwt,
    body: {
      'product_id': prodVictim,
      'item_kind': 'marketplace_product',
    },
  );
  c.note('p1.q1.hijack.product', 'seller2 aponta live_item ao SKU vítima',
      hijackItem.brief,
      lens: 'Q1');
  final itemAAfter = await c.liveItemRow(itemA ?? '');
  if (itemAAfter?['product_id']?.toString() == prodVictim) {
    // buyer reserva no live atacante sobre SKU vítima
    final resHij = await c.rest(
      'POST',
      'live_reservation_requests',
      jwt: c.buyerJwt,
      body: {
        'live_id': liveA,
        'live_item_id': itemA,
        'seller_id': c.seller2Id,
        'buyer_id': c.buyerId,
        'requested_qty': 2,
        'status': 'pending',
        'source': 'fleaber_live',
      },
    );
    final hijId = resHij.firstId;
    if (hijId != null) c.createdRequestIds.add(hijId);
    final accHij = hijId == null
        ? null
        : await c.rpc('batata_process_live_reservation_request', {
            'p_request_id': hijId,
            'p_action': 'accept',
          }, jwt: c.seller2Jwt);
    final hijRow = hijId == null ? null : await c.reservationRow(hijId);
    final qtyVictim = await c.productRow(prodVictim ?? '');
    c.note('p1.q1.hijack.accept', 'accept sobre SKU vítima', {
      'insert': resHij.brief,
      'accept': accHij?.brief,
      'res': hijRow,
      'qty_victim': qtyVictim?['quantity'],
    }, lens: 'Q1');
    if (hijRow?['status'] == 'accepted') {
      c.hold(
        id: 'RTQ-Q1-live-item-foreign-product-accept',
        lens: 'Q1',
        severity: 'P1',
        title: 'Live atacante reserva/aceita contra product_id do vendedor vítima',
        actor: 'seller2 JWT + buyer',
        pre: 'live_items RLS permite product_id alheio',
        repro: 'PATCH live_items.product_id=SKU vítima; POST reserva; RPC accept',
        expected: 'product_id tem de ser do dono da live',
        obtained: {
          'item': itemAAfter,
          'res': hijRow,
          'qty_victim': qtyVictim?['quantity'],
        },
      );
    }
  }

  // Q1: INSERT JWT seller2 com item vítima
  final s2OnV = await c.rest(
    'POST',
    'live_reservation_requests',
    jwt: c.seller2Jwt,
    body: {
      'live_id': liveV,
      'live_item_id': itemV,
      'seller_id': c.seller2Id,
      'buyer_id': c.seller2Id,
      'requested_qty': 1,
      'status': 'accepted',
      'source': 'fleaber_live',
    },
  );
  c.note('p1.q7.s2.accept.victim', 'seller2 INSERT accepted no live vítima',
      s2OnV.brief,
      lens: 'Q7');
  final s2OnVId = s2OnV.firstId;
  if (s2OnVId != null) c.createdRequestIds.add(s2OnVId);
  final s2OnVRow = s2OnVId == null ? null : await c.reservationRow(s2OnVId);
  if (s2OnVRow?['status'] == 'accepted') {
    c.hold(
      id: 'RTQ-Q7-seller2-accept-on-victim-live',
      lens: 'Q7',
      severity: 'P0',
      title: '2.º vendedor insere reserva accepted no directo alheio',
      actor: 'seller2 JWT',
      pre: 'itemV ∈ liveV',
      repro: 'POST live_reservation_requests status=accepted live_id vítima',
      expected: 'pending (não-dono) ou 42501',
      obtained: s2OnVRow,
    );
  }

  // Q7: buyer2 RPC accept do pedido do buyer1
  final pendB1 = await c.rest(
    'POST',
    'live_reservation_requests',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveV,
      'live_item_id': itemV,
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'requested_qty': 1,
      'status': 'pending',
      'source': 'fleaber_live',
    },
  );
  final pendB1Id = pendB1.firstId;
  if (pendB1Id != null) c.createdRequestIds.add(pendB1Id);
  final accB2 = pendB1Id == null
      ? null
      : await c.rpc('batata_process_live_reservation_request', {
          'p_request_id': pendB1Id,
          'p_action': 'accept',
        }, jwt: c.buyer2Jwt);
  final accS2rpc = pendB1Id == null
      ? null
      : await c.rpc('batata_process_live_reservation_request', {
          'p_request_id': pendB1Id,
          'p_action': 'accept',
        }, jwt: c.seller2Jwt);
  final convB2 = pendB1Id == null
      ? null
      : await c.rpc('batata_live_reservation_stripe_convert', {
          'p_request_id': pendB1Id,
        }, jwt: c.buyer2Jwt);
  c.note('p1.q7.rpc.foreign', 'RPC accept/convert por 2.º actor', {
    'pend': pendB1.brief,
    'acc_b2': accB2?.brief,
    'acc_s2': accS2rpc?.brief,
    'conv_b2': convB2?.brief,
  }, lens: 'Q7');
  final pendAfter = pendB1Id == null ? null : await c.reservationRow(pendB1Id);
  if (pendAfter?['status'] == 'accepted' || pendAfter?['status'] == 'converted') {
    final via = (accB2?.ok == true)
        ? 'buyer2'
        : (accS2rpc?.ok == true)
            ? 'seller2'
            : 'convert';
    c.hold(
      id: 'RTQ-Q7-second-actor-accept-or-convert',
      lens: 'Q7',
      severity: 'P0',
      title: '2.º actor aceita ou converte reserva alheia',
      actor: via,
      pre: 'pending buyer1 no live vítima',
      repro: 'rpc batata_process_live_reservation_request accept | stripe_convert',
      expected: 'not_allowed',
      obtained: pendAfter,
    );
  }

  // Q1: source facebook_manual accepted (force pending trigger)
  final fb = await c.rest('POST', 'live_reservation_requests', jwt: c.sellerJwt, body: {
    'live_id': liveV,
    'live_item_id': itemV,
    'seller_id': c.sellerId,
    'buyer_id': c.buyerId,
    'requested_qty': 1,
    'status': 'accepted',
    'source': 'facebook_manual',
  });
  c.note('p1.q1.fb.manual', 'seller INSERT facebook_manual accepted', fb.brief,
      lens: 'Q1');
  final fbId = fb.firstId;
  if (fbId != null) c.createdRequestIds.add(fbId);
  final fbRow = fbId == null ? null : await c.reservationRow(fbId);

  // Q1: buyer PATCH status accepted na sua pending
  if (pendB1Id != null) {
    final selfAcc = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$pendB1Id',
      jwt: c.buyerJwt,
      body: {'status': 'accepted', 'requested_qty': 3},
    );
    final selfRow = await c.reservationRow(pendB1Id);
    c.note('p1.q1.buyer.patch.accept', 'buyer PATCH accepted+qty', {
      'patch': selfAcc.brief,
      'row': selfRow,
    }, lens: 'Q1');
    if (selfRow?['status'] == 'accepted') {
      c.hold(
        id: 'RTQ-Q1-buyer-self-accept-patch',
        lens: 'Q1',
        severity: 'P0',
        title: 'Comprador PATCH da própria reserva para accepted',
        actor: 'buyer JWT',
        pre: 'pending própria',
        repro: 'PATCH live_reservation_requests status=accepted',
        expected: 'status congelado pending',
        obtained: selfRow,
      );
    }
  }

  // Q7 race: dois buyers pending + seller accept paralelo vs buyer2 insert accepted
  final racePend = await c.rest(
    'POST',
    'live_reservation_requests',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveV,
      'live_item_id': itemV,
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'requested_qty': 2,
      'status': 'pending',
      'source': 'fleaber_live',
    },
  );
  final raceId = racePend.firstId;
  if (raceId != null) c.createdRequestIds.add(raceId);
  if (raceId != null) {
    final raced = await parallel([
      c.rpc('batata_process_live_reservation_request', {
        'p_request_id': raceId,
        'p_action': 'accept',
      }, jwt: c.sellerJwt),
      c.rest('POST', 'live_reservation_requests', jwt: c.buyer2Jwt, body: {
        'live_id': liveV,
        'live_item_id': itemV,
        'seller_id': c.sellerId,
        'buyer_id': c.buyer2Id,
        'requested_qty': 3,
        'status': 'accepted',
        'source': 'fleaber_live',
      }),
    ]);
    c.note('p1.q4.race.accept.vs.b2insert', 'accept ∥ buyer2 INSERT accepted', {
      'seller_accept': raced[0].brief,
      'b2_insert': raced[1].brief,
    }, lens: 'Q4');
    final b2rid = raced[1].firstId;
    if (b2rid != null) c.createdRequestIds.add(b2rid);
  }

  await dumpJson('${outDir()}/pass1.json', {
    'findings': c.findings,
    'notes': c.notes,
    'fb_row': fbRow,
    'live_after': liveAfterPatch,
  });
  await c.endLives();
  stdout.writeln('PASS1 findings=${c.findings.length}');
  exit(0);
}
