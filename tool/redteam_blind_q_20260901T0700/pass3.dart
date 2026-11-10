/// PASS 3 — Q3 devolução pós-O34, Q4 race, Q5 FSM disputa, proof/label variantes.
import 'dart:io';

import '_rtq.dart';

Future<String?> openDispute(Rtq c, String oid, {String lens = 'Q5'}) async {
  final ins = await c.rest('POST', 'order_disputes', jwt: c.buyerJwt, body: {
    'order_id': oid,
    'buyer_id': c.buyerId,
    'reason': 'nao_corresponde',
    'description': '$prefix disputa',
    'status': 'aberta',
    'current_turn': 'vendedor',
  });
  c.note('p3.dispute.insert', 'buyer abre disputa', ins.brief, lens: lens);
  final id = ins.firstId;
  if (id != null) c.createdDisputeIds.add(id);
  return id;
}

Future<Map<String, dynamic>?> disputeRow(Rtq c, String id) async {
  final h = await c.rest(
    'GET',
    'order_disputes?id=eq.$id&select=id,order_id,status,current_turn,seller_refund_percent,seller_offer_type,buyer_decision,return_label_url,admin_resolution',
    service: true,
  );
  return h.map;
}

void main() async {
  final env = loadEnv();
  final c = Rtq.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.wallets();
  c.note('p3.w0', 'wallets before', w0, lens: 'Q8');

  final oid = await c.payToEntregue(lens: 'Q3');
  if (oid == null) {
    stderr.writeln('no paid order');
    exit(4);
  }
  var o = await c.orderRow(oid);
  c.note('p3.order.entregue', 'order after entregue', o, lens: 'Q3');
  final pid = o?['product_id']?.toString();
  final stock0 = pid != null ? await c.productRow(pid) : null;
  final pi = o?['stripe_payment_intent_id']?.toString();

  // Q5-a: disputa a partir de entregue
  final did = await openDispute(c, oid);
  if (did == null) {
    // tentar concluido
    await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
      'status': 'concluido',
    });
    final did2 = await openDispute(c, oid);
    c.note('p3.dispute.retry.concluido', 'retry após concluido', did2, lens: 'Q5');
  }
  final disputeId = c.createdDisputeIds.isNotEmpty
      ? c.createdDisputeIds.last
      : did;
  if (disputeId == null) {
    c.note('p3.dispute.blocked', 'não abriu disputa — ledger', o, lens: 'Q5');
  }

  // Q3-a: fake stripe_refund_id then devolvida (variante nova vs PATCH devolvida directo)
  final fakeRef = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.sellerJwt,
    body: {'stripe_refund_id': 're_RTQ_FAKE'},
  );
  c.note('p3.q3.fake.refund.id', 'seller PATCH stripe_refund_id fake',
      fakeRef.brief,
      lens: 'Q3');
  final oFake = await c.orderRow(oid);
  if (fakeRef.ok && oFake?['stripe_refund_id'] == 're_RTQ_FAKE') {
    c.hold(
      id: 'RTQ-Q3-fake-stripe-refund-id',
      lens: 'Q3',
      severity: 'P0',
      title: 'Vendedor grava stripe_refund_id forjado',
      actor: 'seller JWT',
      pre: 'encomenda Stripe paga sem refund real',
      repro: 'PATCH orders stripe_refund_id=re_RTQ_FAKE',
      expected: 'order_money_fields_immutable',
      obtained: oFake,
    );
  }

  // Q3-b: PATCH devolvida sem refund (fecho O3 — documentar block)
  final toDev = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.sellerJwt,
    body: {'status': 'devolvida'},
  );
  c.note('p3.q3.devolvida.direct', 'seller PATCH devolvida', toDev.brief,
      lens: 'Q3');
  final oDev = await c.orderRow(oid);
  final stockDev = pid != null ? await c.productRow(pid) : null;
  if (toDev.ok && oDev?['status'] == 'devolvida') {
    final noStripe = (oDev?['stripe_refund_id'] == null ||
            '${oDev?['stripe_refund_id']}'.isEmpty) &&
        (oFake?['stripe_refund_id'] != 're_RTQ_FAKE');
    c.hold(
      id: 'RTQ-Q3-devolvida-without-stripe-still-open',
      lens: 'Q3',
      severity: 'P0',
      title: 'devolvida ainda passa sem stripe_refund_id (O3 falhou)',
      actor: 'seller JWT',
      pre: 'plataforma capturada',
      repro: 'PATCH orders status=devolvida',
      expected: 'order_devolvida_requires_refund',
      obtained: {'order': oDev, 'stock': stockDev, 'noStripe': noStripe},
    );
  }

  // Q3-c: PATCH payment_method off-platform then devolvida
  final pmFlip = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.sellerJwt,
    body: {'payment_method': 'transferencia bancaria'},
  );
  c.note('p3.q3.pm.flip', 'seller PATCH payment_method', pmFlip.brief, lens: 'Q3');
  if (pmFlip.ok) {
    final d2 = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: c.sellerJwt,
      body: {'status': 'devolvida'},
    );
    final oPm = await c.orderRow(oid);
    c.note('p3.q3.devolvida.after.pm', 'devolvida após flip PM', d2.brief,
        lens: 'Q3');
    if (d2.ok && oPm?['status'] == 'devolvida') {
      c.hold(
        id: 'RTQ-Q3-flip-payment-method-then-devolvida',
        lens: 'Q3',
        severity: 'P0',
        title: 'Vendedor classifica a ordem como off-platform e marca devolvida',
        actor: 'seller JWT',
        pre: 'Stripe capturado; O3 só corre se platform+captured',
        repro:
            'PATCH payment_method=transferencia; PATCH status=devolvida',
        expected: 'payment_method imutável',
        obtained: oPm,
      );
    }
  }

  // Q3-d: RPC finalize fake (JWT)
  final fin = await c.rpc(
    'batata_finalize_stripe_order_refund',
    {
      'p_order_id': oid,
      'p_refund_id': 're_RTQ_JWT',
      'p_payment_intent_id': pi,
      'p_session_id': null,
      'p_amount_cents': 50,
    },
    jwt: c.sellerJwt,
  );
  c.note('p3.q3.finalize.jwt', 'JWT finalize_stripe_order_refund', fin.brief,
      lens: 'Q3');
  final oFin = await c.orderRow(oid);
  if (fin.ok && oFin?['stripe_refund_id'] == 're_RTQ_JWT') {
    c.hold(
      id: 'RTQ-Q3-jwt-finalize-fake-refund',
      lens: 'Q3',
      severity: 'P0',
      title: 'JWT chama finalize_stripe_order_refund com refund_id inventado',
      actor: 'seller JWT',
      pre: 'RPC deveria ser service_role',
      repro: 'rpc batata_finalize_stripe_order_refund p_refund_id=re_RTQ_JWT',
      expected: '42501 / not granted',
      obtained: {'rpc': fin.brief, 'order': oFin},
    );
  }

  // Q5 FSM
  if (disputeId != null) {
    final skipRes = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$disputeId',
      jwt: c.sellerJwt,
      body: {'status': 'resolvida', 'current_turn': 'administracao'},
    );
    c.note('p3.q5.skip.resolvida', 'seller PATCH resolvida desde aberta',
        skipRes.brief,
        lens: 'Q5');
    final dSkip = await disputeRow(c, disputeId);
    if (skipRes.ok && dSkip?['status'] == 'resolvida') {
      c.hold(
        id: 'RTQ-Q5-seller-skip-to-resolvida',
        lens: 'Q5',
        severity: 'P1',
        title: 'Vendedor salta FSM: aberta → resolvida',
        actor: 'seller JWT',
        pre: 'disputa aberta',
        repro: 'PATCH order_disputes status=resolvida',
        expected: 'transição recusada / só admin',
        obtained: dSkip,
      );
      // reopen
      final reopen = await c.rest('POST', 'order_disputes', jwt: c.buyerJwt, body: {
        'order_id': oid,
        'buyer_id': c.buyerId,
        'reason': 'danificado',
        'description': '$prefix reopen',
        'status': 'aberta',
      });
      c.note('p3.q5.reopen', 'buyer INSERT disputa após resolvida', reopen.brief,
          lens: 'Q5');
      if (reopen.ok) {
        c.createdDisputeIds.add(reopen.firstId ?? '');
        c.hold(
          id: 'RTQ-Q5-reopen-after-resolvida',
          lens: 'Q5',
          severity: 'P1',
          title: 'Comprador reabre disputa INSERT após resolvida',
          actor: 'buyer JWT',
          pre: 'disputa marcada resolvida pelo vendedor',
          repro: 'POST order_disputes nova row no mesmo order_id',
          expected: 'uma disputa por encomenda / recusa',
          obtained: reopen.brief,
        );
      }
    } else {
      // escalate
      final esc = await c.rest(
        'PATCH',
        'order_disputes?id=eq.$disputeId',
        jwt: c.buyerJwt,
        body: {'status': 'escalada_fleaber'},
      );
      c.note('p3.q5.escalate', 'buyer escalate', esc.brief, lens: 'Q5');
      final dEsc = await disputeRow(c, disputeId);
      final sellerOfferAfterEsc = await c.rest(
        'PATCH',
        'order_disputes?id=eq.$disputeId',
        jwt: c.sellerJwt,
        body: {
          'seller_refund_percent': 100,
          'seller_offer_type': 'partial_refund',
          'current_turn': 'comprador',
        },
      );
      c.note('p3.q5.offer.after.esc', 'seller offer após escalate',
          sellerOfferAfterEsc.brief,
          lens: 'Q5');
      final dOffer = await disputeRow(c, disputeId);
      if (dEsc?['status'] == 'escalada_fleaber' &&
          dOffer?['current_turn'] == 'comprador') {
        c.hold(
          id: 'RTQ-Q5-seller-rewinds-escalate-turn',
          lens: 'Q5',
          severity: 'P1',
          title: 'Após escalate, vendedor volta current_turn para comprador',
          actor: 'seller JWT',
          pre: 'status escalada_fleaber deveria forçar administracao',
          repro: 'PATCH current_turn=comprador + oferta 100%',
          expected: 'current_turn=administracao sticky',
          obtained: dOffer,
        );
      }
      if (dOffer?['seller_refund_percent'] != null &&
          dEsc?['status'] == 'escalada_fleaber') {
        // offer after escalate may still be ok product-wise; only finding if turn rewind
      }
    }
  }

  // Q3/Q4: process_partial 100% (should require stripe) vs 99%
  if (disputeId != null) {
    await c.rest(
      'PATCH',
      'order_disputes?id=eq.$disputeId',
      jwt: c.sellerJwt,
      body: {
        'seller_refund_percent': 100,
        'seller_offer_type': 'partial_refund',
        'seller_offer_set_by': c.sellerId,
      },
    );
    // seller_offer_set_by might be trigger-filled; try without if fail
    final offer100 = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$disputeId',
      jwt: c.sellerJwt,
      body: {
        'seller_refund_percent': 100,
        'seller_offer_type': 'partial_refund',
      },
    );
    c.note('p3.q3.offer100', 'seller oferta 100%', offer100.brief, lens: 'Q3');

    final partial100 = await c.rpc(
      'batata_process_partial_refund_dispute',
      {'p_order_id': oid, 'p_refund_percent': 100},
      jwt: c.buyerJwt,
    );
    c.note('p3.q3.partial100', 'buyer process_partial 100%', partial100.brief,
        lens: 'Q3');
    final w100 = await c.wallets();
    final o100 = await c.orderRow(oid);
    final minted = (w100['buyer'] ?? 0) > (w0['buyer'] ?? 0) + 0.01;
    if (partial100.ok &&
        minted &&
        (o100?['stripe_refund_id'] == null ||
            '${o100?['stripe_refund_id']}'.isEmpty)) {
      c.hold(
        id: 'RTQ-Q3-partial-100-mints-without-stripe',
        lens: 'Q3',
        severity: 'P0',
        title: 'process_partial 100% minta carteira sem Stripe refund',
        actor: 'buyer JWT',
        pre: 'O4 deveria exigir dispute_full_refund_requires_stripe',
        repro: 'rpc batata_process_partial_refund_dispute 100',
        expected: '42501 dispute_full_refund_requires_stripe',
        obtained: {
          'rpc': partial100.brief,
          'wallets': w100,
          'order': o100,
        },
      );
    }

    final offer99 = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$disputeId',
      jwt: c.sellerJwt,
      body: {
        'seller_refund_percent': 99,
        'seller_offer_type': 'partial_refund',
      },
    );
    c.note('p3.q3.offer99', 'seller oferta 99%', offer99.brief, lens: 'Q3');
    final partial99 = await c.rpc(
      'batata_process_partial_refund_dispute',
      {'p_order_id': oid, 'p_refund_percent': 99},
      jwt: c.buyerJwt,
    );
    c.note('p3.q3.partial99', 'buyer process_partial 99%', partial99.brief,
        lens: 'Q3');
    final w99 = await c.wallets();
    final o99 = await c.orderRow(oid);
    if (partial99.ok &&
        (w99['buyer'] ?? 0) > (w0['buyer'] ?? 0) + 0.5 &&
        (o99?['stripe_refund_id'] == null ||
            '${o99?['stripe_refund_id']}'.isEmpty)) {
      c.hold(
        id: 'RTQ-Q3-partial-99-near-full-wallet-mint',
        lens: 'Q3',
        severity: 'P1',
        title:
            'Oferta 99% minta quase o total na carteira sem anular o PaymentIntent',
        actor: 'buyer JWT + seller JWT',
        pre: 'O4 só bloqueia >=100; PI Stripe continua capturado',
        repro: 'PATCH offer 99; rpc process_partial',
        expected: 'teto ou Stripe proporcional / sem mint se PI activo',
        obtained: {
          'rpc': partial99.brief,
          'w0': w0,
          'w99': w99,
          'order': o99,
        },
      );
    }
  }

  // Q4 race: process_partial ∥ refund-order  (verbos ≠ N/O)
  final wRace0 = await c.wallets();
  final race = await parallel([
    c.rpc(
      'batata_process_partial_refund_dispute',
      {'p_order_id': oid},
      jwt: c.buyerJwt,
    ),
    c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt),
  ]);
  c.note('p3.q4.race.partial.vs.refund', 'process_partial ∥ refund-order', {
    'partial': race[0].brief,
    'refund': race[1].brief,
  }, lens: 'Q4');
  final oRace = await c.orderRow(oid);
  final wRace1 = await c.wallets();
  final stockRace = pid != null ? await c.productRow(pid) : null;
  final buyerDelta = (wRace1['buyer'] ?? 0) - (wRace0['buyer'] ?? 0);
  final sellerDelta = (wRace1['seller'] ?? 0) - (wRace0['seller'] ?? 0);
  final stripeRef = oRace?['stripe_refund_id']?.toString();
  final doublePay = buyerDelta > 0.01 &&
      stripeRef != null &&
      stripeRef.isNotEmpty;
  if (doublePay) {
    c.hold(
      id: 'RTQ-Q4-partial-parallel-refund-order-double',
      lens: 'Q4',
      severity: 'P0',
      title: 'Race process_partial ∥ refund-order: carteira + Stripe no mesmo PI',
      actor: 'buyer JWT + seller JWT',
      pre: 'disputa com oferta; Stripe TEST pago',
      repro: 'Future.wait rpc process_partial + POST refund-order',
      expected: 'um caminho só; O4/refund-order mutex',
      obtained: {
        'partial': race[0].brief,
        'refund': race[1].brief,
        'buyerDelta': buyerDelta,
        'sellerDelta': sellerDelta,
        'order': oRace,
        'stock': stockRace,
      },
    );
  }

  // Q4-b: refund-order ∥ PATCH devolvida
  final race2 = await parallel([
    c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt),
    c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
      'status': 'devolvida',
    }),
  ]);
  c.note('p3.q4.race.refund.vs.devolvida', 'refund-order ∥ devolvida', {
    'refund': race2[0].brief,
    'devolvida': race2[1].brief,
  }, lens: 'Q4');
  final oRace2 = await c.orderRow(oid);
  final stockRace2 = pid != null ? await c.productRow(pid) : null;
  final qty0 = numOf(stock0?['quantity']) ?? 0;
  final qty2 = numOf(stockRace2?['quantity']) ?? 0;
  if (oRace2?['status'] == 'devolvida' &&
      qty2 > qty0 &&
      (oRace2?['stripe_refund_id'] == null ||
          '${oRace2?['stripe_refund_id']}'.isEmpty)) {
    c.hold(
      id: 'RTQ-Q4-devolvida-restock-without-stripe-race',
      lens: 'Q4',
      severity: 'P0',
      title: 'Race refund-order ∥ devolvida restaurou stock sem Stripe',
      actor: 'seller JWT',
      pre: 'encomenda paga',
      repro: 'Future.wait refund-order + PATCH devolvida',
      expected: 'devolvida só com stripe_refund_id; stock alinhado ao dinheiro',
      obtained: {'order': oRace2, 'stock0': stock0, 'stock2': stockRace2},
    );
  }

  // Proof / label NEW variants (fragment, not wrap clássico)
  final proofFrag = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.sellerJwt,
    body: {'proof_url': 'https://fleaber.app/ok#https://evil.example/phish'},
  );
  c.note('p3.proof.fragment', 'proof_url fragment', proofFrag.brief, lens: 'Q3');
  final oProof = await c.orderRow(oid);
  if (proofFrag.ok &&
      '${oProof?['proof_url']}'.contains('evil.example')) {
    c.hold(
      id: 'RTQ-Q3-proof-url-fragment-evil',
      lens: 'Q3',
      severity: 'P2',
      title: 'proof_url aceita fragmento https://fleaber.app/ok#https://evil',
      actor: 'seller JWT',
      pre: 'wrap clássico /https:// bloqueado; fragmento não',
      repro: 'PATCH proof_url=https://fleaber.app/ok#https://evil.example/phish',
      expected: 'order_proof_url_denied ou URL sanitizada',
      obtained: oProof?['proof_url'],
    );
  }

  if (disputeId != null) {
    final lab = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$disputeId',
      jwt: c.sellerJwt,
      body: {
        'return_label_url':
            'https://fleaber.app/ok#https://evil.example/label',
      },
    );
    c.note('p3.label.fragment', 'return_label fragment', lab.brief, lens: 'Q3');
    final dLab = await disputeRow(c, disputeId);
    if (lab.ok &&
        '${dLab?['return_label_url']}'.contains('evil.example')) {
      c.hold(
        id: 'RTQ-Q3-label-url-fragment-evil',
        lens: 'Q3',
        severity: 'P2',
        title: 'return_label_url fragmento fleaber.app#https://evil',
        actor: 'seller JWT',
        pre: 'wrap path /https:// bloqueado',
        repro: 'PATCH return_label_url fragment',
        expected: 'dispute_return_label_url_denied',
        obtained: dLab?['return_label_url'],
      );
    }
  }

  // Buyer2 on same order
  final b2patch = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyer2Jwt,
    body: {'status': 'devolvida'},
  );
  c.note('p3.q7.b2.order', 'buyer2 PATCH order', b2patch.brief, lens: 'Q7');
  final b2disp = await c.rest('POST', 'order_disputes', jwt: c.buyer2Jwt, body: {
    'order_id': oid,
    'buyer_id': c.buyer2Id,
    'reason': 'outro',
    'description': 'rtq b2',
  });
  c.note('p3.q7.b2.dispute', 'buyer2 INSERT disputa ordem alheia', b2disp.brief,
      lens: 'Q7');
  if (b2disp.ok) {
    c.hold(
      id: 'RTQ-Q7-buyer2-dispute-foreign-order',
      lens: 'Q7',
      severity: 'P0',
      title: '2.º comprador abre disputa em encomenda alheia',
      actor: 'buyer2 JWT',
      pre: 'order buyer=B1',
      repro: 'POST order_disputes order_id alheio',
      expected: 'RLS recusa',
      obtained: b2disp.brief,
    );
  }

  final wEnd = await c.wallets();
  c.note('p3.wend', 'wallets end', {
    'w0': w0,
    'wEnd': wEnd,
    'order': await c.orderRow(oid),
    'stock': pid != null ? await c.productRow(pid) : null,
    'pi': pi,
  }, lens: 'Q8');

  await dumpJson('${outDir()}/pass3.json', {
    'notes': c.notes,
    'findings': c.findings,
    'order_id': oid,
    'product_id': pid,
    'w0': w0,
    'wEnd': wEnd,
  });
  stdout.writeln('PASS3 findings=${c.findings.length}');
  exit(0);
}
