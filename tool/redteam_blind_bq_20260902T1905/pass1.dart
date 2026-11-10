/// PASS 1 — BQ1–BQ8 disputa/envio/devolução pós-BFBK.
/// Exactos BK/AY (observar, NÃO contar): seller pago→pedido_devolucao · proof query-string wrap.
/// Novas: disputa 2.ª · partial · fragment # · replies proof · devolvida cedo ·
/// buyer concluido mid-return · stock restore dup · B2 disputa · Edge amount.
import 'dart:io';
import '_rtbq.dart';

Future<void> main() async {
  final c = Rtbq.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('actors', 'JWT B1/S1/B2/S2', {
    'b1': c.buyerId,
    's1': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
  });
  final w0 = await c.wallets();
  c.note('p1.wallets', 'saldos iniciais', w0, lens: 'BQ8');

  Future<({String oid, String pid, String? pi})> mustPay(String lens,
      {int qty = 2}) async {
    final paid = await c.payToPago(lens: lens, initialQty: qty);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  // =========================================================================
  // paidA — BQ1 hops pedido_devolucao + BQ7 B2/2.ª + exacto seller
  // =========================================================================
  final a = await mustPay('BQ1');
  var oa = await c.orderRow(a.oid);
  final qtyA0 = await c.qtyOf(a.pid);
  c.note('BQ1.fixture', 'pago Stripe', {
    'oid': a.oid,
    'pid': a.pid,
    'status': oa?['status'],
    'paid': oa?['amount_paid_cents'],
    'pi': a.pi,
    'qty': qtyA0,
    'ship': oa?['shipping_method'],
  }, lens: 'BQ1');

  // Exacto BK — NÃO contar
  final exactoSellerPed = await c.patchOrder(
    a.oid,
    {'status': 'pedido_devolucao'},
    jwt: c.sellerJwt,
  );
  final oaExacto = await c.orderRow(a.oid);
  c.note('exacto.BK.seller_pedido', 'BK exacto seller pago→pedido_devolucao', {
    'hit': exactoSellerPed.brief,
    'status': oaExacto?['status'],
  }, lens: 'BQ1');

  await c.expectStatusNot(
    id: 'BQ1-01-buyer-pedido-from-pago-no-dispute',
    lens: 'BQ1',
    title: 'Buyer marca pedido_devolucao a partir de pago sem disputa',
    oid: a.oid,
    forbidden: 'pedido_devolucao',
    hit: await c.patchOrder(
      a.oid,
      {'status': 'pedido_devolucao'},
      jwt: c.buyerJwt,
    ),
    actor: 'buyer JWT',
    pre: 'pago capturado, sem order_disputes',
    repro: 'PATCH status=pedido_devolucao',
    severityIfOpen: 'P1',
  );

  // BQ7 — B2 abre disputa na order de B1
  final b2Disp = await c.insertDispute(
    orderId: a.oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  await c.expectDenied(
    id: 'BQ7-01-b2-insert-dispute',
    lens: 'BQ7',
    title: 'B2 abre disputa na encomenda de B1',
    hit: b2Disp,
    actor: 'buyer2 JWT',
    pre: 'order B1–S1 paga',
    repro: 'POST order_disputes buyer_id=B2 order_id=B1',
    severityIfOpen: 'P1',
  );

  final b2AsB1 = await c.insertDispute(
    orderId: a.oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyerId,
  );
  await c.expectDenied(
    id: 'BQ7-02-b2-spoof-buyer-id',
    lens: 'BQ7',
    title: 'B2 abre disputa com buyer_id=B1',
    hit: b2AsB1,
    actor: 'buyer2 JWT',
    pre: 'spoof buyer_id',
    repro: 'POST order_disputes buyer_id=B1 JWT=B2',
    severityIfOpen: 'P1',
  );

  final d1 = await c.insertDispute(orderId: a.oid);
  c.note('BQ1.dispute', 'B1 abre disputa em pago', d1.brief, lens: 'BQ1');
  final didA = d1.firstId;
  if (didA != null) c.createdDisputeIds.add(didA);
  if (!d1.ok || didA == null) {
    c.skip('BQ1.dispute.fail', 'BQ1', 'não abriu disputa em pago', d1);
  }

  // BQ1 — buyer pedido_devolucao FROM pago WITH disputa (ainda deve negar: só concluido/entregue)
  await c.expectStatusNot(
    id: 'BQ1-02-buyer-pedido-from-pago-with-dispute',
    lens: 'BQ1',
    title: 'Buyer pedido_devolucao a partir de pago COM disputa aberta',
    oid: a.oid,
    forbidden: 'pedido_devolucao',
    hit: await c.patchOrder(
      a.oid,
      {'status': 'pedido_devolucao'},
      jwt: c.buyerJwt,
    ),
    actor: 'buyer JWT',
    pre: 'pago + disputa aberta',
    repro: 'PATCH status=pedido_devolucao',
    severityIfOpen: 'P1',
  );

  // BQ7 — 2.ª disputa
  final d2 = await c.insertDispute(
    orderId: a.oid,
    description: 'RTBQ segunda disputa na mesma encomenda.',
  );
  final listed = await c.disputesFor(a.oid);
  if (d2.ok || listed.length > 1) {
    c.hold(
      id: 'BQ7-03-second-dispute',
      lens: 'BQ7',
      severity: 'P1',
      title: '2.ª disputa na mesma encomenda',
      actor: 'buyer JWT',
      pre: 'já existe disputa',
      repro: 'POST order_disputes 2×',
      expected: 'unique / 409 / 4xx',
      obtained: {
        'hit': d2.brief,
        'count': listed.length,
        'ids': listed.map((e) => (e as Map)['id']).toList(),
      },
    );
  } else {
    c.block('BQ7-03-second-dispute', 'BQ7', '2.ª disputa', {
      'hit': d2.brief,
      'count': listed.length,
    });
  }

  // Race 2× INSERT numa encomenda fresca
  final aRace = await mustPay('BQ7', qty: 1);
  final raceHits = await Future.wait([
    c.insertDispute(orderId: aRace.oid, description: 'RTBQ race A'),
    c.insertDispute(orderId: aRace.oid, description: 'RTBQ race B'),
  ]);
  final raceList = await c.disputesFor(aRace.oid);
  c.note('BQ7.race', 'Future.wait 2× POST disputa', {
    'a': raceHits[0].brief,
    'b': raceHits[1].brief,
    'count': raceList.length,
  }, lens: 'BQ7');
  if (raceList.length > 1) {
    c.hold(
      id: 'BQ7-04-race-two-disputes',
      lens: 'BQ7',
      severity: 'P1',
      title: 'Corrida 2× POST cria duas disputas',
      actor: 'buyer JWT',
      pre: 'pago sem disputa',
      repro: 'Future.wait 2× POST order_disputes',
      expected: '1 linha',
      obtained: {
        'count': raceList.length,
        'hits': raceHits.map((h) => h.brief).toList(),
      },
    );
  } else {
    c.block('BQ7-04-race-two-disputes', 'BQ7', 'race 2 disputas', {
      'count': raceList.length,
      'hits': raceHits.map((h) => h.brief).toList(),
    });
  }
  for (final row in raceList) {
    final id = (row as Map)['id']?.toString();
    if (id != null) c.createdDisputeIds.add(id);
  }

  // BQ2 hops from pago — devolvida cedo / skip FSM
  await c.expectStatusNot(
    id: 'BQ2-01-seller-devolvida-from-pago',
    lens: 'BQ2',
    title: 'Seller marca devolvida a partir de pago (cedo)',
    oid: a.oid,
    forbidden: 'devolvida',
    hit: await c.patchOrder(a.oid, {'status': 'devolvida'}, jwt: c.sellerJwt),
    actor: 'seller JWT',
    pre: 'pago + disputa',
    repro: 'PATCH status=devolvida',
    severityIfOpen: 'P0',
  );
  await c.expectStatusNot(
    id: 'BQ2-02-seller-em-devolucao-from-pago',
    lens: 'BQ2',
    title: 'Seller marca em_devolucao a partir de pago',
    oid: a.oid,
    forbidden: 'em_devolucao',
    hit: await c.patchOrder(a.oid, {'status': 'em_devolucao'}, jwt: c.sellerJwt),
    actor: 'seller JWT',
    pre: 'pago',
    repro: 'PATCH status=em_devolucao',
    severityIfOpen: 'P1',
  );
  await c.expectStatusNot(
    id: 'BQ2-03-buyer-em-devolucao-from-pago',
    lens: 'BQ2',
    title: 'Buyer marca em_devolucao a partir de pago',
    oid: a.oid,
    forbidden: 'em_devolucao',
    hit: await c.patchOrder(a.oid, {'status': 'em_devolucao'}, jwt: c.buyerJwt),
    actor: 'buyer JWT',
    pre: 'pago',
    repro: 'PATCH status=em_devolucao',
    severityIfOpen: 'P1',
  );
  await c.expectStatusNot(
    id: 'BQ2-04-buyer-devolvida',
    lens: 'BQ2',
    title: 'Buyer marca devolvida',
    oid: a.oid,
    forbidden: 'devolvida',
    hit: await c.patchOrder(a.oid, {'status': 'devolvida'}, jwt: c.buyerJwt),
    actor: 'buyer JWT',
    pre: 'pago',
    repro: 'PATCH status=devolvida',
    severityIfOpen: 'P1',
  );

  // S2 PATCH disputa de B1
  if (didA != null) {
    final s2Patch = await c.patchDispute(
      didA,
      {'status': 'resolvida', 'buyer_decision': 'accepted_return'},
      jwt: c.seller2Jwt,
    );
    final afterS2 = await c.disputeRow(didA);
    if ('${afterS2?['status']}'.toLowerCase() == 'resolvida') {
      c.hold(
        id: 'BQ7-05-s2-resolve-dispute',
        lens: 'BQ7',
        severity: 'P1',
        title: 'S2 fecha disputa de S1/B1',
        actor: 'seller2 JWT',
        pre: 'disputa aberta B1',
        repro: 'PATCH status=resolvida',
        expected: 'RLS / 4xx, status=aberta',
        obtained: {'hit': s2Patch.brief, 'status': afterS2?['status']},
      );
    } else {
      c.block('BQ7-05-s2-resolve-dispute', 'BQ7', 'S2 resolve', {
        'hit': s2Patch.brief,
        'status': afterS2?['status'],
      });
    }
  }

  // =========================================================================
  // paidB — return chain + mid-return concluido + proofs + replies
  // =========================================================================
  final b = await mustPay('BQ2');
  final qtyB0 = await c.qtyOf(b.pid);
  final envB = await c.patchOrder(b.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  var ob = await c.orderRow(b.oid);
  c.note('BQ2.enviado', 'seller enviado', {
    'hit': envB.brief,
    'status': ob?['status'],
    'shipped_at': ob?['shipped_at'],
  }, lens: 'BQ2');

  final concB = await c.patchOrder(
    b.oid,
    {'status': 'concluido'},
    jwt: c.buyerJwt,
  );
  ob = await c.orderRow(b.oid);
  c.note('BQ2.concluido', 'buyer concluido após enviado', {
    'hit': concB.brief,
    'status': ob?['status'],
  }, lens: 'BQ2');

  final dB = await c.insertDispute(
    orderId: b.oid,
    description: 'RTBQ disputa pós-concluido para cadeia de devolução.',
  );
  final didB = dB.firstId;
  if (didB != null) c.createdDisputeIds.add(didB);
  c.note('BQ2.dispute', 'disputa pós-concluido', dB.brief, lens: 'BQ2');

  final pedB = await c.patchOrder(
    b.oid,
    {'status': 'pedido_devolucao'},
    jwt: c.buyerJwt,
  );
  ob = await c.orderRow(b.oid);
  c.note('BQ1.pedido-from-concluido', 'buyer pedido_devolucao a partir de concluido', {
    'hit': pedB.brief,
    'status': ob?['status'],
  }, lens: 'BQ1');
  if ('${ob?['status']}'.toLowerCase() != 'pedido_devolucao') {
    c.skip('BQ1.pedido.happy', 'BQ1', 'não entrou pedido_devolucao', {
      'hit': pedB.brief,
      'status': ob?['status'],
    });
  }

  // BQ2 — buyer concluido mid-return
  final midConc = await c.patchOrder(
    b.oid,
    {'status': 'concluido'},
    jwt: c.buyerJwt,
  );
  await c.expectStatusNot(
    id: 'BQ2-05-buyer-concluido-mid-return',
    lens: 'BQ2',
    title: 'Buyer força concluido com pedido_devolucao activo',
    oid: b.oid,
    forbidden: 'concluido',
    hit: midConc,
    actor: 'buyer JWT',
    pre: 'pedido_devolucao + disputa aberta',
    repro: 'PATCH status=concluido',
    severityIfOpen: 'P1',
  );

  // seller hops skip: pedido → devolvida
  await c.expectStatusNot(
    id: 'BQ2-06-seller-devolvida-skip-fsm',
    lens: 'BQ2',
    title: 'Seller marca devolvida a saltar em_devolucao/devolucao_entregue',
    oid: b.oid,
    forbidden: 'devolvida',
    hit: await c.patchOrder(b.oid, {'status': 'devolvida'}, jwt: c.sellerJwt),
    actor: 'seller JWT',
    pre: 'pedido_devolucao',
    repro: 'PATCH status=devolvida',
    severityIfOpen: 'P1',
  );

  // seller enviado during return
  await c.expectStatusNot(
    id: 'BQ2-07-seller-enviado-during-return',
    lens: 'BQ2',
    title: 'Seller volta a enviado durante devolução',
    oid: b.oid,
    forbidden: 'enviado',
    hit: await c.patchOrder(b.oid, {'status': 'enviado'}, jwt: c.sellerJwt),
    actor: 'seller JWT',
    pre: 'pedido_devolucao',
    repro: 'PATCH status=enviado',
    severityIfOpen: 'P1',
  );

  // BQ6 release during return
  final relMid = await c.tryRelease(b.oid, jwt: c.buyerJwt);
  final wMid = await c.wallets();
  final obMid = await c.orderRow(b.oid);
  final released = obMid?['wallet_release_processed_at'] != null;
  final relTrue = relMid.ok && '${relMid.json}' == 'true';
  c.note('BQ6.release-mid-return', 'release durante pedido_devolucao', {
    'hit': relMid.brief,
    'released_at': obMid?['wallet_release_processed_at'],
    'wallets': wMid,
    'delta_seller': (wMid['seller'] ?? 0) - (w0['seller'] ?? 0),
  }, lens: 'BQ6');
  if (released || relTrue) {
    c.hold(
      id: 'BQ6-01-release-mid-return',
      lens: 'BQ6',
      severity: (wMid['seller']! > w0['seller']!) ? 'P0' : 'P1',
      title: 'Release da carteira do vendedor a meio da devolução',
      actor: 'buyer JWT',
      pre: 'pedido_devolucao + PI capturado',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false / sem mint',
      obtained: {
        'hit': relMid.brief,
        'released_at': obMid?['wallet_release_processed_at'],
        'wallets': wMid,
      },
    );
  } else {
    c.block('BQ6-01-release-mid-return', 'BQ6', 'release mid-return', relMid);
  }

  // ---- BQ3 proofs: fragment # (NOVO) vs query wrap (exacto, não contar)
  if (didB != null) {
    final nMine = needle(c.buyerId!, b.oid);
    final nOther = needle(c.buyerId!, a.oid);
    final otherPath = proofUrl(c.buyerId!, a.oid, file: 'secret.png');
    final minePath = proofUrl(c.buyerId!, b.oid, file: 'ok.png');

    // Exacto AY/BK query wrap — observar
    final qWrap = '$otherPath?q=$nMine';
    final qHit = await c.patchDispute(didB, {
      'proof_photos': [qWrap],
    }, jwt: c.buyerJwt);
    final qRow = await c.disputeRow(didB);
    c.note('exacto.AY.query-wrap', 'AY/BK exacto needle na query', {
      'hit': qHit.brief,
      'photos': qRow?['proof_photos'],
    }, lens: 'BQ3');

    // NOVO: fragment wrap — needle no #, path alheio
    final fragWrap = '$otherPath#$nMine';
    final fHit = await c.patchDispute(didB, {
      'proof_photos': [fragWrap],
    }, jwt: c.buyerJwt);
    final fRow = await c.disputeRow(didB);
    final storedFrag = '${fRow?['proof_photos']}'.contains(nOther) &&
        '${fRow?['proof_photos']}'.contains('#');
    if (fHit.mutated && storedFrag) {
      c.hold(
        id: 'BQ3-01-fragment-wrap-path-alheio',
        lens: 'BQ3',
        severity: 'P1',
        title: 'proof_photos aceita path alheio com needle no fragmento #',
        actor: 'buyer JWT',
        pre: 'disputa B, needle só no #',
        repro: 'PATCH proof_photos=[storage/other#order_disputes/mine/oid/]',
        expected: 'dispute_proof_url_denied (needle só no path)',
        obtained: {'hit': fHit.brief, 'photos': fRow?['proof_photos']},
      );
    } else {
      c.block('BQ3-01-fragment-wrap-path-alheio', 'BQ3', 'fragment wrap', {
        'hit': fHit.brief,
        'photos': fRow?['proof_photos'],
      });
    }

    // label fragment wrap
    final labFrag = '$otherPath#$nMine';
    final labHit = await c.patchDispute(didB, {
      'return_label_url': labFrag,
    }, jwt: c.sellerJwt);
    final labRow = await c.disputeRow(didB);
    final labStored = '${labRow?['return_label_url']}'.contains('#') &&
        '${labRow?['return_label_url']}'.contains(nOther);
    if (labStored) {
      c.hold(
        id: 'BQ3-02-label-fragment-wrap',
        lens: 'BQ3',
        severity: 'P1',
        title: 'return_label_url path alheio + needle no #',
        actor: 'seller JWT',
        pre: 'disputa B',
        repro: 'PATCH return_label_url=other#needle',
        expected: 'order_dispute_label_url_denied',
        obtained: {'hit': labHit.brief, 'url': labRow?['return_label_url']},
      );
    } else {
      c.block('BQ3-02-label-fragment-wrap', 'BQ3', 'label fragment', {
        'hit': labHit.brief,
        'url': labRow?['return_label_url'],
      });
    }

    // path traversal ../ with own needle as prefix
    final trav =
        '$minePath/../../../order_disputes/${c.buyerId}/${a.oid}/secret.png';
    final tHit = await c.patchDispute(didB, {
      'proof_photos': [trav],
    }, jwt: c.buyerJwt);
    final tRow = await c.disputeRow(didB);
    final tStored = '${tRow?['proof_photos']}'.contains('../');
    if (tHit.mutated && tStored) {
      c.hold(
        id: 'BQ3-03-path-traversal',
        lens: 'BQ3',
        severity: 'P1',
        title: 'proof_photos aceita ../ para pasta de outra encomenda',
        actor: 'buyer JWT',
        pre: 'needle próprio no prefixo + ../',
        repro: 'PATCH proof_photos=[.../mine/oid/x.png/../../../other/secret]',
        expected: 'denied',
        obtained: {'hit': tHit.brief, 'photos': tRow?['proof_photos']},
      );
    } else {
      c.block('BQ3-03-path-traversal', 'BQ3', 'path traversal', {
        'hit': tHit.brief,
        'photos': tRow?['proof_photos'],
      });
    }

    // ---- replies proof (NOVO: bind mais frouxo que a tabela disputa)
    final replyOk = await c.insertReply(
      disputeId: didB,
      message: 'RTBQ reply limpo',
      photos: <String>[],
    );
    final rid = replyOk.firstId;
    c.note('BQ3.reply-ok', 'reply limpo', replyOk.brief, lens: 'BQ3');

    if (rid != null) {
      // PATCH javascript + needle (insert-guard não corre)
      final jsNeedle = 'javascript:alert(1)//$nMine';
      final jsHit = await c.rest(
        'PATCH',
        'order_dispute_replies?id=eq.$rid',
        jwt: c.buyerJwt,
        body: {
          'proof_photos': [jsNeedle],
        },
      );
      final jsAfter = await c.rest(
        'GET',
        'order_dispute_replies?id=eq.$rid&select=id,proof_photos',
        service: true,
      );
      final jsStored = '${jsAfter.map?['proof_photos']}'.contains('javascript:');
      if (jsStored) {
        c.hold(
          id: 'BQ3-04-reply-patch-javascript-needle',
          lens: 'BQ3',
          severity: 'P2',
          title: 'PATCH reply proof_photos javascript: com needle (guard só no INSERT)',
          actor: 'buyer JWT',
          pre: 'reply limpo; trigger bind replies = needle no URL inteiro',
          repro: 'PATCH proof_photos=[javascript:alert(1)//order_disputes/uid/oid/]',
          expected: 'dispute_proof_url_denied',
          obtained: {'hit': jsHit.brief, 'photos': jsAfter.map?['proof_photos']},
        );
      } else {
        c.block('BQ3-04-reply-patch-javascript-needle', 'BQ3', 'reply js', {
          'hit': jsHit.brief,
          'photos': jsAfter.map?['proof_photos'],
        });
      }

      // PATCH fragment wrap replies
      final rFrag = '$otherPath#$nMine';
      final rfHit = await c.rest(
        'PATCH',
        'order_dispute_replies?id=eq.$rid',
        jwt: c.buyerJwt,
        body: {
          'proof_photos': [rFrag],
        },
      );
      final rfAfter = await c.rest(
        'GET',
        'order_dispute_replies?id=eq.$rid&select=id,proof_photos',
        service: true,
      );
      final rfStored = '${rfAfter.map?['proof_photos']}'.contains(nOther) &&
          '${rfAfter.map?['proof_photos']}'.contains('#');
      if (rfStored) {
        c.hold(
          id: 'BQ3-05-reply-fragment-wrap',
          lens: 'BQ3',
          severity: 'P1',
          title: 'PATCH reply prova: path alheio + needle no fragmento #',
          actor: 'buyer JWT',
          pre: 'replies guard position(needle in url) sem strip de #',
          repro: 'PATCH proof_photos=[storage/other#order_disputes/mine/oid/]',
          expected: 'denied (needle só no path, como na disputa)',
          obtained: {
            'hit': rfHit.brief,
            'photos': rfAfter.map?['proof_photos'],
          },
        );
      } else {
        c.block('BQ3-05-reply-fragment-wrap', 'BQ3', 'reply fragment', {
          'hit': rfHit.brief,
          'photos': rfAfter.map?['proof_photos'],
        });
      }

      // PATCH query wrap replies (classe replies, NÃO o exacto da tabela disputa)
      final rQ = '$otherPath?q=$nMine';
      final rqHit = await c.rest(
        'PATCH',
        'order_dispute_replies?id=eq.$rid',
        jwt: c.buyerJwt,
        body: {
          'proof_photos': [rQ],
        },
      );
      final rqAfter = await c.rest(
        'GET',
        'order_dispute_replies?id=eq.$rid&select=id,proof_photos',
        service: true,
      );
      final rqStored = '${rqAfter.map?['proof_photos']}'.contains(nOther) &&
          '${rqAfter.map?['proof_photos']}'.contains('?');
      if (rqStored) {
        c.hold(
          id: 'BQ3-06-reply-query-wrap',
          lens: 'BQ3',
          severity: 'P1',
          title: 'PATCH reply prova: path alheio + needle na query (tabela disputa já fecha isto)',
          actor: 'buyer JWT',
          pre: 'replies não strip ?#',
          repro: 'PATCH proof_photos=[storage/other?q=needle]',
          expected: 'denied',
          obtained: {
            'hit': rqHit.brief,
            'photos': rqAfter.map?['proof_photos'],
          },
        );
      } else {
        c.block('BQ3-06-reply-query-wrap', 'BQ3', 'reply query wrap', {
          'hit': rqHit.brief,
          'photos': rqAfter.map?['proof_photos'],
        });
      }
    } else {
      c.skip('BQ3.reply', 'BQ3', 'reply limpo falhou', replyOk);
    }

    // INSERT reply fleaber.pt + needle (host allowlist largo no INSERT)
    final ptUrl = 'https://fleaber.pt/$nMine phishing.png';
    final ptHit = await c.insertReply(
      disputeId: didB,
      message: 'RTBQ fleaber.pt',
      photos: [ptUrl],
    );
    if (ptHit.ok) {
      c.hold(
        id: 'BQ3-07-reply-insert-fleaber-pt',
        lens: 'BQ3',
        severity: 'P2',
        title: 'INSERT reply aceita https://fleaber.pt/… com needle (não é storage)',
        actor: 'buyer JWT',
        pre: 'insert-guard allowlist fleaber.pt',
        repro: 'POST proof_photos=[https://fleaber.pt/order_disputes/uid/oid/…]',
        expected: 'só fleaber_private storage',
        obtained: ptHit.brief,
      );
    } else {
      c.block('BQ3-07-reply-insert-fleaber-pt', 'BQ3', 'fleaber.pt insert', ptHit);
    }
  }

  // =========================================================================
  // paidC — BQ4 Edge amount / partial + BQ5 stock restore
  // =========================================================================
  final cPay = await mustPay('BQ4', qty: 1);
  final qtyC0 = await c.qtyOf(cPay.pid);
  final oc0 = await c.orderRow(cPay.oid);
  final paidCents = numOf(oc0?['amount_paid_cents']) ?? 0;

  // Edge amount client-controlled (NOVO)
  final amt1 = await c.refundOrder(cPay.oid, extraBody: {'amount': 1});
  final ocAmt1 = await c.orderRow(cPay.oid);
  final stripeAmt1 = numOf(amt1.map?['amount_cents']);
  c.note('BQ4.amount-1', 'refund-order amount=1', {
    'hit': amt1.brief,
    'stripe_amount': stripeAmt1,
    'paid': paidCents,
    'refund_id': ocAmt1?['stripe_refund_id'],
    'status': ocAmt1?['status'],
  }, lens: 'BQ4');

  if (amt1.ok &&
      stripeAmt1 != null &&
      stripeAmt1 > 0 &&
      stripeAmt1 < paidCents &&
      paidCents > 1) {
    c.hold(
      id: 'BQ4-01-edge-amount-partial',
      lens: 'BQ4',
      severity: 'P0',
      title: 'Edge refund-order honra amount=1 do cliente (parcial < captura)',
      actor: 'seller JWT',
      pre: 'pago capturado, amount_paid_cents=$paidCents',
      repro: 'POST refund-order {order_id, amount:1}',
      expected: 'ignora amount; reembolsa a parcela da linha',
      obtained: {
        'hit': amt1.brief,
        'amount_cents': stripeAmt1,
        'paid': paidCents,
        'refund_id': ocAmt1?['stripe_refund_id'],
      },
    );
  } else if (amt1.ok && stripeAmt1 == paidCents) {
    c.block('BQ4-01-edge-amount-partial', 'BQ4', 'amount=1 ignorado, usou captura', {
      'hit': amt1.brief,
      'amount_cents': stripeAmt1,
      'paid': paidCents,
    });
  } else if (!amt1.ok) {
    c.block('BQ4-01-edge-amount-partial', 'BQ4', 'amount=1 rejeitado/bloqueado', amt1);
  } else {
    c.note('BQ4.amount-1.other', 'amount=1 resultado', amt1.brief, lens: 'BQ4');
  }

  // If first refund already consumed PI, skip oversize on same order
  final ocNow = await c.orderRow(cPay.oid);
  final alreadyRefunded =
      '${ocNow?['stripe_refund_id'] ?? ''}'.trim().isNotEmpty;
  if (!alreadyRefunded) {
    final amtHuge = await c.refundOrder(cPay.oid, extraBody: {'amount': 999999});
    final hugeCents = numOf(amtHuge.map?['amount_cents']);
    if (amtHuge.ok && hugeCents != null && hugeCents > paidCents) {
      c.hold(
        id: 'BQ4-02-edge-amount-oversize',
        lens: 'BQ4',
        severity: 'P0',
        title: 'Edge refund-order amount=999999 excede captura da linha',
        actor: 'seller JWT',
        pre: 'pago',
        repro: 'POST refund-order amount=999999',
        expected: 'cap na parcela amount_paid_cents',
        obtained: {'hit': amtHuge.brief, 'amount_cents': hugeCents, 'paid': paidCents},
      );
    } else {
      c.block('BQ4-02-edge-amount-oversize', 'BQ4', 'amount oversize', {
        'hit': amtHuge.brief,
        'amount_cents': hugeCents,
        'paid': paidCents,
      });
    }
  } else {
    c.note('BQ4.oversize.skip', 'já há refund_id, oversize noutra order',
        ocNow?['stripe_refund_id'],
        lens: 'BQ4');
  }

  // Buyer / B2 refund
  final bRef = await c.refundOrder(cPay.oid, jwt: c.buyerJwt);
  await c.expectDenied(
    id: 'BQ4-03-buyer-refund-edge',
    lens: 'BQ4',
    title: 'Buyer dispara refund-order',
    hit: bRef,
    actor: 'buyer JWT',
    pre: 'order paga',
    repro: 'POST refund-order JWT=buyer',
    severityIfOpen: 'P0',
    isSuccess: (h) =>
        h.ok && h.map?['ok'] == true && h.map?['skipped'] != true,
  );
  final b2Ref = await c.refundOrder(cPay.oid, jwt: c.buyer2Jwt);
  await c.expectDenied(
    id: 'BQ7-06-b2-refund-edge',
    lens: 'BQ7',
    title: 'B2 dispara refund-order na order de B1',
    hit: b2Ref,
    actor: 'buyer2 JWT',
    pre: 'order B1',
    repro: 'POST refund-order JWT=B2',
    severityIfOpen: 'P0',
    isSuccess: (h) =>
        h.ok && h.map?['ok'] == true && h.map?['skipped'] != true,
  );

  // Stock after refund on C
  final qtyC1 = await c.qtyOf(cPay.pid);
  final oc1 = await c.orderRow(cPay.oid);
  c.note('BQ5.stock-after-refund-C', 'stock vs refund', {
    'qty0': qtyC0,
    'qty1': qtyC1,
    'applied': oc1?['stock_units_applied'],
    'refund_id': oc1?['stripe_refund_id'],
    'status': oc1?['status'],
  }, lens: 'BQ5');

  // JWT finalize refund RPC
  await c.expectDenied(
    id: 'BQ4-04-jwt-finalize-refund-rpc',
    lens: 'BQ4',
    title: 'JWT chama batata_finalize_stripe_order_refund',
    hit: await c.rpc('batata_finalize_stripe_order_refund', {
      'p_order_id': cPay.oid,
      'p_refund_id': 're_fake_rtbq',
    }, jwt: c.sellerJwt),
    actor: 'seller JWT',
    pre: 'RPC service_role-only',
    repro: 'POST rpc batata_finalize_stripe_order_refund',
    severityIfOpen: 'P0',
  );

  // =========================================================================
  // paidD — BQ5 race 2× refund stock dup
  // =========================================================================
  final dPay = await mustPay('BQ5', qty: 1);
  final qtyD0 = await c.qtyOf(dPay.pid);
  final raceRef = await Future.wait([
    c.refundOrder(dPay.oid),
    c.refundOrder(dPay.oid),
  ]);
  final qtyD1 = await c.qtyOf(dPay.pid);
  final od1 = await c.orderRow(dPay.oid);
  c.note('BQ5.race-refund', '2× refund-order', {
    'a': raceRef[0].brief,
    'b': raceRef[1].brief,
    'qty0': qtyD0,
    'qty1': qtyD1,
    'delta': qtyD1 - qtyD0,
    'applied': od1?['stock_units_applied'],
    'refund_id': od1?['stripe_refund_id'],
  }, lens: 'BQ5');
  final stockDup = (qtyD1 - qtyD0) > 1;
  if (stockDup) {
    c.hold(
      id: 'BQ5-01-race-refund-stock-dup',
      lens: 'BQ5',
      severity: 'P0',
      title: 'Corrida 2× refund-order restaurou stock duas vezes',
      actor: 'seller JWT',
      pre: 'pago stock_units_applied, qty=$qtyD0',
      repro: 'Future.wait 2× POST refund-order',
      expected: 'Δqty ≤ unidades da linha (1)',
      obtained: {
        'qty0': qtyD0,
        'qty1': qtyD1,
        'delta': qtyD1 - qtyD0,
        'hits': raceRef.map((h) => h.brief).toList(),
      },
    );
  } else {
    c.block('BQ5-01-race-refund-stock-dup', 'BQ5', 'race stock', {
      'qty0': qtyD0,
      'qty1': qtyD1,
      'delta': qtyD1 - qtyD0,
      'hits': raceRef.map((h) => h.brief).toList(),
    });
  }

  // =========================================================================
  // paidE — BQ5 devolvida cedo + stock restore sem refund; BQ6 release open dispute
  // =========================================================================
  final ePay = await mustPay('BQ5', qty: 1);
  final qtyE0 = await c.qtyOf(ePay.pid);
  await c.patchOrder(ePay.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(ePay.oid, {'status': 'concluido'}, jwt: c.buyerJwt);
  final dE = await c.insertDispute(orderId: ePay.oid);
  final didE = dE.firstId;
  if (didE != null) c.createdDisputeIds.add(didE);
  await c.patchOrder(ePay.oid, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt);
  await c.patchOrder(ePay.oid, {'status': 'em_devolucao'}, jwt: c.sellerJwt);
  await c.patchOrder(
    ePay.oid,
    {'status': 'devolucao_entregue'},
    jwt: c.sellerJwt,
  );
  final devE = await c.patchOrder(
    ePay.oid,
    {'status': 'devolvida'},
    jwt: c.sellerJwt,
  );
  final oe = await c.orderRow(ePay.oid);
  final qtyE1 = await c.qtyOf(ePay.pid);
  c.note('BQ5.devolvida-chain', 'cadeia até devolvida', {
    'hit': devE.brief,
    'status': oe?['status'],
    'qty0': qtyE0,
    'qty1': qtyE1,
    'applied': oe?['stock_units_applied'],
    'refund_id': oe?['stripe_refund_id'],
    'pi': oe?['stripe_payment_intent_id'],
  }, lens: 'BQ5');

  // Stock restore on devolvida WITH live capture and NO refund → P0 if restored
  if ('${oe?['status']}'.toLowerCase() == 'devolvida' &&
      '${oe?['stripe_refund_id'] ?? ''}'.trim().isEmpty &&
      qtyE1 > qtyE0) {
    c.hold(
      id: 'BQ5-02-devolvida-stock-without-refund',
      lens: 'BQ5',
      severity: 'P0',
      title: 'devolvida restaurou stock com captura Stripe viva e sem refund',
      actor: 'seller JWT',
      pre: 'cadeia return, PI vivo, stripe_refund_id null',
      repro: 'PATCH … → devolvida',
      expected: 'stock intacto até refund',
      obtained: {
        'qty0': qtyE0,
        'qty1': qtyE1,
        'applied': oe?['stock_units_applied'],
        'status': oe?['status'],
      },
    );
  } else if ('${oe?['status']}'.toLowerCase() == 'devolvida' &&
      qtyE1 <= qtyE0) {
    c.block('BQ5-02-devolvida-stock-without-refund', 'BQ5',
        'devolvida sem restore (captura viva)', {
      'qty0': qtyE0,
      'qty1': qtyE1,
      'status': oe?['status'],
      'refund_id': oe?['stripe_refund_id'],
    });
  } else {
    c.note('BQ5.devolvida.not-reached', 'não ficou devolvida', {
      'hit': devE.brief,
      'status': oe?['status'],
    }, lens: 'BQ5');
  }

  // Then refund on devolvida — stock should restore ONCE
  if ('${oe?['status']}'.toLowerCase() == 'devolvida') {
    final qtyBeforeRef = await c.qtyOf(ePay.pid);
    final refE = await c.refundOrder(ePay.oid);
    final qtyAfterRef = await c.qtyOf(ePay.pid);
    final oe2 = await c.orderRow(ePay.oid);
    c.note('BQ5.refund-after-devolvida', 'refund em devolvida', {
      'hit': refE.brief,
      'qty_before': qtyBeforeRef,
      'qty_after': qtyAfterRef,
      'delta': qtyAfterRef - qtyBeforeRef,
      'status': oe2?['status'],
      'refund_id': oe2?['stripe_refund_id'],
    }, lens: 'BQ5');
    if ((qtyAfterRef - qtyBeforeRef) > 1) {
      c.hold(
        id: 'BQ5-03-refund-devolvida-stock-dup',
        lens: 'BQ5',
        severity: 'P0',
        title: 'Refund em devolvida restaurou stock >1',
        actor: 'seller JWT',
        pre: 'devolvida, captura viva',
        repro: 'POST refund-order',
        expected: 'Δqty = unidades da linha (1) ou 0 se já restaurado',
        obtained: {
          'delta': qtyAfterRef - qtyBeforeRef,
          'hit': refE.brief,
        },
      );
    } else {
      c.block('BQ5-03-refund-devolvida-stock-dup', 'BQ5', 'refund devolvida stock', {
        'delta': qtyAfterRef - qtyBeforeRef,
        'hit': refE.brief,
      });
    }
  }

  // Open-dispute refund on A (ainda aberta, pago)
  final oaNow = await c.orderRow(a.oid);
  if ('${oaNow?['stripe_refund_id'] ?? ''}'.trim().isEmpty) {
    final refOpen = await c.refundOrder(a.oid);
    c.note('BQ4.refund-open-dispute', 'refund-order com disputa aberta',
        refOpen.brief,
        lens: 'BQ4');
    final okLoot = refOpen.ok &&
        refOpen.map?['ok'] == true &&
        refOpen.map?['skipped'] != true &&
        (refOpen.map?['refund_id'] != null ||
            '${(await c.orderRow(a.oid))?['stripe_refund_id'] ?? ''}'
                .trim()
                .isNotEmpty);
    if (okLoot) {
      c.hold(
        id: 'BQ4-05-refund-open-dispute',
        lens: 'BQ4',
        severity: 'P1',
        title: 'refund-order Stripe com disputa aberta',
        actor: 'seller JWT',
        pre: 'pago + disputa aberta',
        repro: 'POST refund-order',
        expected: '403 order_refund_blocked_open_dispute',
        obtained: refOpen.brief,
      );
    } else {
      c.block('BQ4-05-refund-open-dispute', 'BQ4', 'refund open dispute', refOpen);
    }
  }

  // Release with open dispute on A (pago, not concluido — should fail anyway)
  final relA = await c.tryRelease(a.oid, jwt: c.buyerJwt);
  c.note('BQ6.release-pago-open-dispute', 'release em pago+disputa', relA.brief,
      lens: 'BQ6');
  if (relA.ok && '${relA.json}' == 'true') {
    c.hold(
      id: 'BQ6-02-release-pago-open-dispute',
      lens: 'BQ6',
      severity: 'P0',
      title: 'Release em pago com disputa aberta mintou carteira',
      actor: 'buyer JWT',
      pre: 'pago + disputa',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false',
      obtained: relA.brief,
    );
  } else {
    c.block('BQ6-02-release-pago-open-dispute', 'BQ6', 'release pago disputa', relA);
  }

  // Seller PATCH disputa resolvida sem buyer_decision (clássico — residual)
  if (didA != null) {
    final close = await c.patchDispute(didA, {'status': 'resolvida'}, jwt: c.sellerJwt);
    final afterClose = await c.disputeRow(didA);
    if ('${afterClose?['status']}'.toLowerCase() == 'resolvida') {
      c.hold(
        id: 'BQ7-07-seller-resolve-without-decision',
        lens: 'BQ7',
        severity: 'P1',
        title: 'Seller fecha disputa para resolvida sem buyer_decision',
        actor: 'seller JWT',
        pre: 'disputa aberta',
        repro: 'PATCH status=resolvida',
        expected: 'status permanece aberta',
        obtained: {'hit': close.brief, 'status': afterClose?['status']},
      );
    } else {
      c.block('BQ7-07-seller-resolve-without-decision', 'BQ7', 'seller resolve', {
        'hit': close.brief,
        'status': afterClose?['status'],
      });
    }
  }

  // Anon refund / dispute
  await c.expectDenied(
    id: 'BQ7-08-anon-refund',
    lens: 'BQ7',
    title: 'anon chama refund-order',
    hit: await c.edge('refund-order', body: {'order_id': a.oid}),
    actor: 'anon',
    pre: 'sem JWT',
    repro: 'POST refund-order anon',
    severityIfOpen: 'P0',
    isSuccess: (h) => h.ok && h.map?['ok'] == true,
  );

  final w1 = await c.wallets();
  c.note('BQ8.wallets-final', 'saldos finais vs iniciais', {
    'before': w0,
    'after': w1,
    'd_buyer': (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0),
    'd_seller': (w1['seller'] ?? 0) - (w0['seller'] ?? 0),
    'd_b2': (w1['buyer2'] ?? 0) - (w0['buyer2'] ?? 0),
    'd_s2': (w1['seller2'] ?? 0) - (w0['seller2'] ?? 0),
  }, lens: 'BQ8');

  await c.dumpAll('pass1.json');
  stdout.writeln(
    'PASS1 done findings=${c.findings.length} blocked=${c.blocked.length} '
    'notes=${c.notes.length} lenses=${c.lensesHit.toList()..sort()}',
  );
}
