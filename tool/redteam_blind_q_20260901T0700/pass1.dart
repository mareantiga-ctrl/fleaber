/// PASS 1 — Q1 live reserva: campos/JWT além de seller_id; Q7 2.º actor.
import 'dart:io';

import '_rtq.dart';

void main() async {
  final env = loadEnv();
  final c = Rtq.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final prodA = await c.createProduct(
    title: '$prefix A-sku',
    seller: c.sellerId,
    qty: 4,
    live: true,
    price: 11,
  );
  final prodB = await c.createProduct(
    title: '$prefix B-sku',
    seller: c.seller2Id,
    qty: 4,
    live: true,
    price: 11,
  );
  final liveA = await c.insertLive(
    seller: c.sellerId,
    active: true,
    muxLiveId: 'ML_RTQ_A',
    streamKey: 'SK_RTQ_A',
    egressId: 'EG_RTQ_A',
    roomName: 'fleaber_rtq_a',
  );
  final liveB = await c.insertLive(
    seller: c.seller2Id,
    active: true,
    muxLiveId: 'ML_RTQ_B',
    streamKey: 'SK_RTQ_B',
    egressId: 'EG_RTQ_B',
    roomName: 'fleaber_rtq_b',
  );
  final itemA = await c.insertLiveItem(
    liveId: liveA ?? '',
    title: '$prefix item A',
    qty: 2,
  );
  final itemB = await c.insertLiveItem(
    liveId: liveB ?? '',
    title: '$prefix item B',
    qty: 2,
  );
  c.note('p1.fixture', 'lives+items', {
    'liveA': liveA,
    'liveB': liveB,
    'itemA': itemA,
    'itemB': itemB,
    'prodA': prodA,
    'prodB': prodB,
  }, lens: 'Q1');

  // Q1-a: S2 INSERT facebook_manual accepted no artigo de A, live_id = live B
  final spoofItem = await c.rest(
    'POST',
    'live_reservation_requests',
    jwt: c.seller2Jwt,
    body: {
      'live_id': liveB,
      'live_item_id': itemA,
      'seller_id': c.seller2Id,
      'buyer_id': c.buyer2Id,
      'requested_qty': 1,
      'status': 'accepted',
      'source': 'facebook_manual',
    },
  );
  c.note('p1.q1.s2.itemA.viaLiveB', 'S2 accepted no item A via live B',
      spoofItem.brief,
      lens: 'Q1');
  final spoofId = spoofItem.firstId;
  Map<String, dynamic>? spoofRow;
  if (spoofId != null) {
    c.createdRequestIds.add(spoofId);
    spoofRow = await c.reservationRow(spoofId);
  }
  final itemAAfterSpoof = await c.liveItemRow(itemA ?? '');
  final consumedA = (spoofRow?['status'] == 'accepted' ||
          spoofRow?['status'] == 'converted') &&
      spoofRow?['live_item_id'] == itemA;
  if (spoofItem.ok && consumedA) {
    c.hold(
      id: 'RTQ-Q1-live-item-mismatch-accept',
      lens: 'Q1',
      severity: 'P0',
      title:
          'S2 aceita reserva no artigo da live A ligando live_id da própria live B',
      actor: 'seller2 JWT',
      pre: 'live A (S1) item qty=2; live B (S2); sem spoof seller_id clássico',
      repro:
          'POST live_reservation_requests source=facebook_manual live_id=<B> live_item_id=<itemA> status=accepted',
      expected: 'recusa / item tem de pertencer à live',
      obtained: spoofRow,
      evidence: {
        'http': spoofItem.brief,
        'itemA_after': itemAAfterSpoof,
      },
    );
  }

  // Q1-b: buyer pending live_id=B live_item=A, depois S2 accept RPC
  final buyerCross = await c.rest(
    'POST',
    'live_reservation_requests',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveB,
      'live_item_id': itemA,
      'buyer_id': c.buyerId,
      'requested_qty': 1,
      'status': 'pending',
      'source': 'fleaber_live',
    },
  );
  c.note('p1.q1.buyer.cross', 'buyer pending item A na live B', buyerCross.brief,
      lens: 'Q1');
  final buyerCrossId = buyerCross.firstId;
  HttpHit? acceptCross;
  Map<String, dynamic>? buyerCrossRow;
  if (buyerCrossId != null) {
    c.createdRequestIds.add(buyerCrossId);
    acceptCross = await c.rpc(
      'batata_process_live_reservation_request',
      {
        'p_request_id': buyerCrossId,
        'p_action': 'accept',
      },
      jwt: c.seller2Jwt,
    );
    c.note('p1.q1.s2.accept.cross', 'S2 RPC accept pedido cruzado',
        acceptCross.brief,
        lens: 'Q1');
    buyerCrossRow = await c.reservationRow(buyerCrossId);
    if (buyerCrossRow?['status'] == 'accepted') {
      c.hold(
        id: 'RTQ-Q1-buyer-cross-live-s2-accept',
        lens: 'Q1',
        severity: 'P0',
        title: 'S2 aceita reserva do comprador no artigo de S1 via live_id B',
        actor: 'buyer JWT + seller2 JWT',
        pre: 'pending com live_item de A e live_id de B',
        repro:
            'POST reserva live_id=B live_item=A; rpc process accept como S2',
        expected: 'pending forçado a live A / accept recusado',
        obtained: buyerCrossRow,
        evidence: {'insert': buyerCross.brief, 'accept': acceptCross.brief},
      );
    }
  }

  // Q1-c: buyer retarget live_item_id após pending
  final legitPend = await c.rest(
    'POST',
    'live_reservation_requests',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveA,
      'live_item_id': itemA,
      'buyer_id': c.buyerId,
      'requested_qty': 1,
      'status': 'pending',
      'source': 'fleaber_live',
    },
  );
  final legitId = legitPend.firstId;
  c.note('p1.q1.buyer.pendingA', 'buyer pending item A', legitPend.brief,
      lens: 'Q1');
  HttpHit? retarget;
  Map<String, dynamic>? retargetRow;
  if (legitId != null) {
    c.createdRequestIds.add(legitId);
    retarget = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$legitId',
      jwt: c.buyerJwt,
      body: {
        'live_item_id': itemB,
        'live_id': liveB,
      },
    );
    c.note('p1.q1.buyer.retarget', 'buyer PATCH live_item → B', retarget.brief,
        lens: 'Q1');
    retargetRow = await c.reservationRow(legitId);
    if (retarget.ok && retargetRow?['live_item_id'] == itemB) {
      c.hold(
        id: 'RTQ-Q1-buyer-retarget-live-item',
        lens: 'Q1',
        severity: 'P1',
        title: 'Comprador muda live_item_id da reserva pending para artigo alheio',
        actor: 'buyer JWT',
        pre: 'pending no item A',
        repro: 'PATCH live_reservation_requests live_item_id=<itemB>',
        expected: 'live_item_id imutável para o comprador',
        obtained: retargetRow,
        evidence: {'http': retarget.brief},
      );
    }
  }

  // Q1-d: S2 PATCH seller_id da live A (transferência)
  final stealLive = await c.rest(
    'PATCH',
    'lives?id=eq.$liveA',
    jwt: c.seller2Jwt,
    body: {'seller_id': c.seller2Id, 'vendedor_id': c.seller2Id},
  );
  c.note('p1.q1.s2.patch.liveA', 'S2 PATCH owner live A', stealLive.brief,
      lens: 'Q1');
  final liveAAfter = await c.liveRow(liveA ?? '');
  if (stealLive.ok && liveAAfter?['seller_id'] == c.seller2Id) {
    c.hold(
      id: 'RTQ-Q1-s2-steal-live-owner',
      lens: 'Q1',
      severity: 'P0',
      title: 'S2 torna-se dono da live A via PATCH seller_id',
      actor: 'seller2 JWT',
      pre: 'live A pertence a S1',
      repro: 'PATCH lives seller_id=<S2>',
      expected: 'RLS 0 rows / 401',
      obtained: liveAAfter,
      evidence: {'http': stealLive.brief},
    );
  }

  // Q1-e: S1 PATCH seller_id→S2 (vende a live) — collusion; then S2 accept
  final donate = await c.rest(
    'PATCH',
    'lives?id=eq.$liveA',
    jwt: c.sellerJwt,
    body: {'seller_id': c.seller2Id},
  );
  c.note('p1.q1.s1.donate', 'S1 PATCH seller_id=S2', donate.brief, lens: 'Q7');
  final liveADonated = await c.liveRow(liveA ?? '');
  if (donate.ok && liveADonated?['seller_id'] == c.seller2Id) {
    c.hold(
      id: 'RTQ-Q7-owner-reassign-live',
      lens: 'Q7',
      severity: 'P2',
      title: 'Dono reassigna seller_id da live activa para S2 (autoridade)',
      actor: 'seller JWT',
      pre: 'live A no ar',
      repro: 'PATCH lives seller_id=<S2>',
      expected: 'seller_id da live imutável após broadcast / só end',
      obtained: liveADonated,
      evidence: {'http': donate.brief},
    );
    // revert for rest of tests
    await c.rest('PATCH', 'lives?id=eq.$liveA', service: true, body: {
      'seller_id': c.sellerId,
      'vendedor_id': c.sellerId,
    }, prefer: 'return=minimal');
  }

  // Q1-f: helper self-insert on S1
  final helperIns = await c.rest('POST', 'seller_helpers', jwt: c.seller2Jwt, body: {
    'seller_id': c.sellerId,
    'helper_user_id': c.seller2Id,
    'invited_by': c.seller2Id,
    'display_name': 'rtq-s2',
    'active': true,
    'invitation_status': 'accepted',
    'permissions': {
      'can_manage_reservations': true,
    },
  });
  c.note('p1.q7.helper.self', 'S2 INSERT helper na loja S1', helperIns.brief,
      lens: 'Q7');
  if (helperIns.ok) {
    c.hold(
      id: 'RTQ-Q7-self-staff-s1',
      lens: 'Q7',
      severity: 'P0',
      title: 'S2 insere-se como staff de S1 com can_manage_reservations',
      actor: 'seller2 JWT',
      pre: 'sem convite de S1',
      repro: 'POST seller_helpers seller_id=<S1> helper=<S2> accepted',
      expected: 'RLS recusa (só dono convida)',
      obtained: helperIns.brief,
    );
  }

  // Q1-g: S2 SELECT item A then convert via process as p_processed_by=S1
  if (legitId != null) {
    final confused = await c.rpc(
      'batata_process_live_reservation_request',
      {
        'p_request_id': legitId,
        'p_action': 'accept',
        'p_processed_by': c.sellerId,
      },
      jwt: c.seller2Jwt,
    );
    c.note('p1.q1.confused.deputy', 'S2 accept com p_processed_by=S1',
        confused.brief,
        lens: 'Q1');
    final afterConfused = await c.reservationRow(legitId);
    if (afterConfused?['status'] == 'accepted') {
      c.hold(
        id: 'RTQ-Q1-processed-by-confused-deputy',
        lens: 'Q1',
        severity: 'P0',
        title: 'S2 aceita reserva de S1 passando p_processed_by do dono',
        actor: 'seller2 JWT',
        pre: 'pending na live A',
        repro: 'rpc process accept p_processed_by=<S1>',
        expected: 'not_allowed',
        obtained: afterConfused,
        evidence: {'http': confused.brief},
      );
    }
  }

  // Q1-h: classic seller_id spoof (should be closed — document block, not finding)
  final classic = await c.rest(
    'POST',
    'live_reservation_requests',
    jwt: c.seller2Jwt,
    body: {
      'live_id': liveA,
      'live_item_id': itemA,
      'seller_id': c.seller2Id,
      'buyer_id': c.buyer2Id,
      'requested_qty': 1,
      'status': 'accepted',
      'source': 'facebook_manual',
    },
  );
  c.note('p1.q1.classic.spoof', 'S2 seller_id spoof na live A (fecho NOP)',
      classic.brief,
      lens: 'Q1');
  if (classic.ok) {
    final row = classic.firstId != null
        ? await c.reservationRow(classic.firstId!)
        : classic.map;
    if (row?['status'] == 'accepted') {
      c.hold(
        id: 'RTQ-Q1-classic-seller-id-spoof-still-open',
        lens: 'Q1',
        severity: 'P0',
        title: 'Spoof seller_id clássico ainda aceita (fecho NOP falhou)',
        actor: 'seller2 JWT',
        pre: 'NOP deveria forçar seller_id=dono live',
        repro: 'POST reserva seller_id=<self> live_id=<A> status=accepted',
        expected: 'pending ou reservation_accept_not_authorized',
        obtained: row,
      );
    }
  }

  await c.endLives();
  await dumpJson('${outDir()}/pass1.json', {
    'notes': c.notes,
    'findings': c.findings,
    'lives': {'A': liveA, 'B': liveB},
    'items': {'A': itemA, 'B': itemB},
  });
  stdout.writeln('PASS1 findings=${c.findings.length}');
  exit(0);
}
