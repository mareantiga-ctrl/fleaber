import '_rtcb.dart';

/// Pass 2 — CB3 release+refund · CB5 FSM · CB6 actor cruzado · CB7 Δwallet
/// Novas: release cedo (pago/enviado) · mão unicode/sinónimos novos · refund body extra.
void main() async {
  final c = Rtcb.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  Future<({String oid, String pid, String? pi})> mustPay(String lens) async {
    final paid = await c.payToPago(lens: lens);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  // --- buyer refund-order ---
  final pBuyer = await mustPay('CB3');
  final balS0 = await c.walletBal(c.sellerId);
  final balB0 = await c.walletBal(c.buyerId);
  final buyerRefund = await c.refundOrder(pBuyer.oid, jwt: c.buyerJwt);
  final rowAfterBuyer = await c.orderRow(pBuyer.oid);
  final balS1 = await c.walletBal(c.sellerId);
  final balB1 = await c.walletBal(c.buyerId);
  c.note('refund.buyer', 'buyer refund-order', {
    'hit': buyerRefund.brief,
    'order': rowAfterBuyer,
    'dSeller': balS1 - balS0,
    'dBuyer': balB1 - balB0,
  }, lens: 'CB3');
  final buyerDidRefund = buyerRefund.ok &&
      buyerRefund.map?['ok'] == true &&
      buyerRefund.map?['skipped'] != true &&
      (rowAfterBuyer?['stripe_refund_id'] != null &&
          '${rowAfterBuyer?['stripe_refund_id']}'.isNotEmpty);
  if (buyerDidRefund) {
    c.hold(
      id: 'CB-P0-BUYER-REFUND',
      lens: 'CB3',
      severity: 'P0',
      title: 'buyer refund-order anulou Stripe da venda alheia',
      actor: 'buyer JWT',
      pre: 'Edge exige user.id === seller_id',
      repro: 'POST refund-order {order_id} com JWT comprador',
      expected: '403 Sem permissão',
      obtained: {
        'hit': buyerRefund.brief,
        'order': rowAfterBuyer,
        'dSeller': balS1 - balS0,
        'dBuyer': balB1 - balB0,
      },
    );
  } else {
    c.block('refund.buyer', 'CB3', 'buyer refund-order recusado', buyerRefund);
  }

  final pX = await mustPay('CB6');
  final s2ref = await c.refundOrder(pX.oid, jwt: c.seller2Jwt);
  await c.expectDenied(
    id: 'cb6.s2.refund',
    lens: 'CB6',
    title: 'seller2 refund-order da venda do seller1',
    hit: s2ref,
    actor: 'seller2 JWT',
    pre: 'só o seller da encomenda',
    repro: 'POST refund-order order do seller1, JWT seller2',
    severityIfOpen: 'P0',
    openIf: (h) => h.ok && h.map?['ok'] == true && h.map?['skipped'] != true,
  );

  // amount extra + novos campos body
  final pAmt = await mustPay('CB3');
  final over = await c.refundOrder(pAmt.oid, extraBody: {
    'amount': 999999,
    'amount_cents': 999999,
    'refund_amount': 999999,
    'total': 9999.99,
    'partial': true,
  }, jwt: c.sellerJwt);
  final rowOver = await c.orderRow(pAmt.oid);
  c.note('refund.over', 'seller refund body amount=999999 + refund_amount/total', {
    'hit': over.brief,
    'order': rowOver,
  }, lens: 'CB3');
  final paidCents = (numOf(rowOver?['amount_paid_cents']) ?? 0).round();
  final refundedOk = over.ok && over.map?['ok'] == true && over.map?['skipped'] != true;
  final claimed = (numOf(over.map?['amount_cents']) ?? 0).round();
  if (refundedOk && claimed > paidCents && paidCents > 0) {
    c.hold(
      id: 'CB-P0-PARTIAL',
      lens: 'CB3',
      severity: 'P0',
      title: 'refund-order body amount/refund_amount > captura da linha',
      actor: 'seller JWT',
      pre: 'amount vem da ordem/PI residual, não do body',
      repro: 'POST refund-order {order_id, amount:999999, refund_amount:999999}',
      expected: 'refund ≤ amount_paid_cents/remaining',
      obtained: {'hit': over.brief, 'paid_cents': paidCents, 'claimed': claimed},
    );
  } else if (refundedOk) {
    c.block('refund.over', 'CB3', 'refund ignorou amount do body (≤ captura)', {
      'hit': over.brief,
      'paid_cents': paidCents,
      'claimed': claimed,
    });
  } else {
    c.block('refund.over', 'CB3', 'refund extra-amount não passou (gate estado?)', over);
  }

  final finJwt = await c.rpc('batata_finalize_stripe_order_refund', {
    'p_order_id': pAmt.oid,
    'p_refund_id': 're_fake_rtcb',
    'p_amount_cents': 999999,
  }, jwt: c.sellerJwt);
  await c.expectDenied(
    id: 'cb6.finalize.jwt',
    lens: 'CB6',
    title: 'JWT executou batata_finalize_stripe_order_refund amount enorme',
    hit: finJwt,
    actor: 'seller JWT',
    pre: 'GRANT só service_role',
    repro: 'POST rpc/batata_finalize_stripe_order_refund p_amount_cents=999999',
    severityIfOpen: 'P0',
    openIf: (h) => h.ok && h.map?['ok'] == true,
  );

  // --- CB5 buyer concluido CTT sem envio ---
  final pHand = await mustPay('CB5');
  final shipCtt = await c.patchOrder(pHand.oid, {
    'shipping_method': 'CTT Expresso',
  }, jwt: c.sellerJwt);
  c.note('ship.ctt', 'seller PATCH shipping CTT Expresso', shipCtt.brief, lens: 'CB5');

  final conclBuyer = await c.patchOrder(pHand.oid, {
    'status': 'concluido',
  }, jwt: c.buyerJwt);
  final rowConcl = await c.orderRow(pHand.oid);
  c.note('concl.buyer.ctt', 'buyer pago→concluido CTT Expresso sem shipped_at', {
    'hit': conclBuyer.brief,
    'status': rowConcl?['status'],
    'shipped_at': rowConcl?['shipped_at'],
  }, lens: 'CB5');
  if ('${rowConcl?['status']}'.toLowerCase() == 'concluido') {
    c.hold(
      id: 'CB-P1-CONCL-UNSHIP',
      lens: 'CB5',
      severity: 'P1',
      title: 'buyer marcou concluido em CTT Expresso sem shipped_at',
      actor: 'buyer JWT',
      pre: 'pago + não is_hand → order_concluido_requires_shipped',
      repro: 'PATCH orders status=concluido (shipping CTT Expresso, shipped_at null)',
      expected: 'status continua pago',
      obtained: {'hit': conclBuyer.brief, 'order': rowConcl},
    );
  } else {
    c.block('concl.buyer.ctt', 'CB5', 'buyer não concluiu CTT Expresso sem envio', {
      'hit': conclBuyer.brief,
      'status': rowConcl?['status'],
    });
  }

  // NEW hand spoofs (não exactos BJ/BV LIKE / hand delivery / HANDS)
  for (final method in [
    'em mão',
    'hand-delivery',
    'in person',
    'pessoalmente',
    'face to face',
    'entrega em mã\u03BF', // mão with greek omicron
    'entrega em mäo',
  ]) {
    final p = await mustPay('CB5');
    await c.patchOrder(p.oid, {'shipping_method': method}, service: true);
    final hit = await c.patchOrder(p.oid, {'status': 'concluido'}, jwt: c.buyerJwt);
    final row = await c.orderRow(p.oid);
    final st = '${row?['status']}'.toLowerCase();
    c.note('hand.spoof.$method', 'buyer concluido method=$method', {
      'hit': hit.brief,
      'status': st,
    }, lens: 'CB5');
    if (st == 'concluido') {
      c.hold(
        id: 'CB-P1-HAND-$method',
        lens: 'CB5',
        severity: 'P1',
        title: 'is_hand spoof "$method" permitiu concluido sem envio',
        actor: 'buyer JWT',
        pre: 'allowlist exacta batata_shipping_method_is_hand',
        repro: 'shipping_method=$method; PATCH concluido',
        expected: 'não concluido',
        obtained: {'hit': hit.brief, 'order': row},
      );
    } else {
      c.block('hand.spoof.$method', 'CB5', 'spoof "$method" recusado', hit);
    }
  }

  // --- CB3 release CEDO: status=pago ---
  final pPago = await mustPay('CB3');
  final balPago0 = await c.walletBal(c.sellerId);
  final relPago = await c.tryRelease(pPago.oid, jwt: c.buyerJwt);
  final relPagoS = await c.tryRelease(pPago.oid, jwt: c.sellerJwt);
  final rowPago = await c.orderRow(pPago.oid);
  final balPago1 = await c.walletBal(c.sellerId);
  final dPago = balPago1 - balPago0;
  c.note('release.pago', 'release enquanto status=pago', {
    'buyer': relPago.brief,
    'seller': relPagoS.brief,
    'delta': dPago,
    'order': rowPago,
  }, lens: 'CB3');
  final releasedPago = rowPago?['wallet_release_processed_at'] != null && dPago > 0;
  if (releasedPago) {
    c.hold(
      id: 'CB-P0-REL-PAGO',
      lens: 'CB3',
      severity: 'P0',
      title: 'release creditou carteira com encomenda ainda pago (cedo)',
      actor: 'buyer JWT',
      pre: 'release exige concluido + (shipped_at OU is_hand)',
      repro: 'rpc batata_release_seller_wallet_for_order em status=pago',
      expected: 'false, Δ=0',
      obtained: {'rel': relPago.brief, 'delta': dPago, 'order': rowPago},
    );
  } else {
    c.block('release.pago', 'CB3', 'release em pago não creditou', {
      'rel': relPago.json,
      'delta': dPago,
      'flag': rowPago?['wallet_release_processed_at'],
    });
  }

  // release CEDO: enviado mas não concluido
  final pEnv = await mustPay('CB3');
  final shipOnly = await c.patchOrder(pEnv.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  c.note('ship.only', 'seller PATCH enviado', shipOnly.brief, lens: 'CB5');
  final balEnv0 = await c.walletBal(c.sellerId);
  final relEnv = await c.tryRelease(pEnv.oid, jwt: c.buyerJwt);
  final rowEnv = await c.orderRow(pEnv.oid);
  final balEnv1 = await c.walletBal(c.sellerId);
  final dEnv = balEnv1 - balEnv0;
  c.note('release.enviado', 'release status=enviado (não concluido)', {
    'rel': relEnv.brief,
    'delta': dEnv,
    'order': rowEnv,
  }, lens: 'CB3');
  if (rowEnv?['wallet_release_processed_at'] != null && dEnv > 0) {
    c.hold(
      id: 'CB-P0-REL-ENVIADO',
      lens: 'CB3',
      severity: 'P0',
      title: 'release creditou em enviado sem concluido',
      actor: 'buyer JWT',
      pre: 'release exige concluido',
      repro: 'PATCH enviado; rpc release',
      expected: 'false, Δ=0',
      obtained: {'rel': relEnv.brief, 'delta': dEnv, 'order': rowEnv},
    );
  } else {
    c.block('release.enviado', 'CB3', 'release em enviado não creditou', {
      'rel': relEnv.json,
      'delta': dEnv,
      'status': rowEnv?['status'],
    });
  }

  // fixture service concluido CTT sem shipped + release JWT
  final pRel = await mustPay('CB3');
  await c.patchOrder(pRel.oid, {
    'shipping_method': 'CTT Expresso',
    'status': 'concluido',
    'shipped_at': null,
  }, service: true);
  final balBeforeRel = await c.walletBal(c.sellerId);
  final relBuyer = await c.tryRelease(pRel.oid, jwt: c.buyerJwt);
  final relSeller = await c.tryRelease(pRel.oid, jwt: c.sellerJwt);
  final relB2 = await c.tryRelease(pRel.oid, jwt: c.buyer2Jwt);
  final rowRel = await c.orderRow(pRel.oid);
  final balAfterRel = await c.walletBal(c.sellerId);
  final dRel = balAfterRel - balBeforeRel;
  c.note('release.unship', 'release concluido CTT Expresso sem shipped_at', {
    'relBuyer': relBuyer.brief,
    'relSeller': relSeller.brief,
    'relB2': relB2.brief,
    'after': rowRel,
    'delta_seller': dRel,
  }, lens: 'CB3');
  final released = rowRel?['wallet_release_processed_at'] != null && dRel > 0;
  if (released) {
    c.hold(
      id: 'CB-P0-REL-UNSHIP',
      lens: 'CB3',
      severity: 'P0',
      title: 'release creditou carteira em concluido CTT Expresso sem shipped_at',
      actor: 'buyer JWT (estado forçado service = fixture; crédito via JWT)',
      pre: 'release exige concluido + (shipped_at OU is_hand)',
      repro: 'service PATCH concluido CTT Expresso shipped_at null; rpc release JWT buyer',
      expected: 'rpc false, sem Δwallet',
      obtained: {
        'relBuyer': relBuyer.brief,
        'delta': dRel,
        'order': rowRel,
      },
    );
  } else {
    c.block('release.unship', 'CB3', 'release sem mão/envio não creditou', {
      'relBuyer': relBuyer.brief,
      'jsonBuyer': relBuyer.json,
      'delta': dRel,
      'flag': rowRel?['wallet_release_processed_at'],
    });
  }

  // refund + release composição (mão fixture)
  final pComp = await mustPay('CB3');
  await c.patchOrder(pComp.oid, {
    'shipping_method': 'entrega em mão',
  }, service: true);
  final rf = await c.refundOrder(pComp.oid, jwt: c.sellerJwt);
  await c.patchOrder(pComp.oid, {'status': 'concluido'}, service: true);
  final balC0 = await c.walletBal(c.sellerId);
  final relAfterRf = await c.tryRelease(pComp.oid, jwt: c.buyerJwt);
  final balC1 = await c.walletBal(c.sellerId);
  final rowComp = await c.orderRow(pComp.oid);
  c.note('comp.refund.release', 'refund depois release (mão fixture)', {
    'refund': rf.brief,
    'release': relAfterRf.brief,
    'delta': balC1 - balC0,
    'order': rowComp,
  }, lens: 'CB3');
  if ((balC1 - balC0) > 0 && '${rowComp?['stripe_refund_id'] ?? ''}'.isNotEmpty) {
    c.hold(
      id: 'CB-P0-REFUND-REL',
      lens: 'CB3',
      severity: 'P0',
      title: 'release creditou seller depois de refund Stripe',
      actor: 'buyer JWT release + seller refund',
      pre: 'stripe_refund_id deve selar release sem crédito',
      repro: 'refund-order; service concluido mão; rpc release',
      expected: 'Δwallet seller ≤ 0',
      obtained: {
        'delta': balC1 - balC0,
        'refund': rf.brief,
        'release': relAfterRf.brief,
        'order': rowComp,
      },
    );
  } else {
    c.block('comp.refund.release', 'CB3', 'sem crédito líquido pós-refund', {
      'delta': balC1 - balC0,
      'refund': rf.brief,
      'release': relAfterRf.json,
      'flag_rel': rowComp?['wallet_release_processed_at'],
      'refund_id': rowComp?['stripe_refund_id'],
    });
  }

  final pRace = await mustPay('CB3');
  final raceRf = await Future.wait([
    c.refundOrder(pRace.oid, jwt: c.sellerJwt),
    c.refundOrder(pRace.oid, jwt: c.sellerJwt),
    c.refundOrder(pRace.oid, jwt: c.sellerJwt),
  ]);
  c.note('race.refund', '3× refund-order', raceRf.map((h) => h.brief).toList(), lens: 'CB3');
  final oks = raceRf.where((h) => h.ok && h.map?['ok'] == true && h.map?['skipped'] != true).length;
  c.block('race.refund', 'CB3', 'race refund hits (ok count=$oks; idempotência Stripe key por order)', {
    'hits': raceRf.map((h) => h.brief).toList(),
    'ok_true': oks,
  });

  await c.dumpAll('pass2.json');
}
