import '_rtbv.dart';

/// Pass 2 — BV3 release+refund · BV5 unship/FSM · BV6 actor cruzado · BV7 Δwallet
void main() async {
  final c = Rtbv.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  Future<({String oid, String pid, String? pi})> mustPay(String lens) async {
    final paid = await c.payToPago(lens: lens);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  // --- buyer refund-order ---
  final pBuyer = await mustPay('BV3');
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
  }, lens: 'BV3');
  final buyerDidRefund = buyerRefund.ok &&
      buyerRefund.map?['ok'] == true &&
      buyerRefund.map?['skipped'] != true &&
      (rowAfterBuyer?['stripe_refund_id'] != null &&
          '${rowAfterBuyer?['stripe_refund_id']}'.isNotEmpty);
  if (buyerDidRefund) {
    c.hold(
      id: 'BV-P0-BUYER-REFUND',
      lens: 'BV3',
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
    c.block('refund.buyer', 'BV3', 'buyer refund-order recusado', buyerRefund);
  }

  // seller2 on seller1 order
  final pX = await mustPay('BV6');
  final s2ref = await c.refundOrder(pX.oid, jwt: c.seller2Jwt);
  await c.expectDenied(
    id: 'bv6.s2.refund',
    lens: 'BV6',
    title: 'seller2 refund-order da venda do seller1',
    hit: s2ref,
    actor: 'seller2 JWT',
    pre: 'só o seller da encomenda',
    repro: 'POST refund-order order do seller1, JWT seller2',
    severityIfOpen: 'P0',
    openIf: (h) => h.ok && h.map?['ok'] == true && h.map?['skipped'] != true,
  );

  // amount extra no refund (parcial > captura)
  final pAmt = await mustPay('BV3');
  final over = await c.refundOrder(pAmt.oid, extraBody: {
    'amount': 999999,
    'amount_cents': 999999,
    'partial': true,
  }, jwt: c.sellerJwt);
  final rowOver = await c.orderRow(pAmt.oid);
  c.note('refund.over', 'seller refund body amount=999999', {
    'hit': over.brief,
    'order': rowOver,
  }, lens: 'BV3');
  // Se refundou mais que amount_paid_cents da linha → P0
  final paidCents = (numOf(rowOver?['amount_paid_cents']) ?? 0).round();
  final refundedOk = over.ok && over.map?['ok'] == true && over.map?['skipped'] != true;
  final claimed = (numOf(over.map?['amount_cents']) ?? 0).round();
  if (refundedOk && claimed > paidCents && paidCents > 0) {
    c.hold(
      id: 'BV-P0-PARTIAL',
      lens: 'BV3',
      severity: 'P0',
      title: 'refund-order body amount/cents > captura da linha',
      actor: 'seller JWT',
      pre: 'amount vem da ordem/PI residual, não do body',
      repro: 'POST refund-order {order_id, amount:999999, amount_cents:999999}',
      expected: 'refund ≤ amount_paid_cents/remaining',
      obtained: {'hit': over.brief, 'paid_cents': paidCents, 'claimed': claimed},
    );
  } else if (refundedOk) {
    c.block('refund.over', 'BV3', 'refund ignorou amount do body (≤ captura)', {
      'hit': over.brief,
      'paid_cents': paidCents,
      'claimed': claimed,
    });
  } else {
    c.block('refund.over', 'BV3', 'refund extra-amount não passou (gate estado?)', over);
  }

  // JWT finalize com amount enorme
  final finJwt = await c.rpc('batata_finalize_stripe_order_refund', {
    'p_order_id': pAmt.oid,
    'p_refund_id': 're_fake_rtbv',
    'p_amount_cents': 999999,
  }, jwt: c.sellerJwt);
  await c.expectDenied(
    id: 'bv6.finalize.jwt',
    lens: 'BV6',
    title: 'JWT executou batata_finalize_stripe_order_refund amount enorme',
    hit: finJwt,
    actor: 'seller JWT',
    pre: 'GRANT só service_role',
    repro: 'POST rpc/batata_finalize_stripe_order_refund p_amount_cents=999999',
    severityIfOpen: 'P0',
    openIf: (h) => h.ok && h.map?['ok'] == true,
  );

  // --- BV5 release sem mão / concluido sem envio ---
  final pHand = await mustPay('BV5');
  final shipCtt = await c.patchOrder(pHand.oid, {
    'shipping_method': 'CTT',
  }, jwt: c.sellerJwt);
  c.note('ship.ctt', 'seller PATCH shipping CTT', shipCtt.brief, lens: 'BV5');

  final conclBuyer = await c.patchOrder(pHand.oid, {
    'status': 'concluido',
  }, jwt: c.buyerJwt);
  final rowConcl = await c.orderRow(pHand.oid);
  c.note('concl.buyer.ctt', 'buyer pago→concluido CTT sem shipped_at', {
    'hit': conclBuyer.brief,
    'status': rowConcl?['status'],
    'shipped_at': rowConcl?['shipped_at'],
  }, lens: 'BV5');
  if ('${rowConcl?['status']}'.toLowerCase() == 'concluido') {
    c.hold(
      id: 'BV-P1-CONCL-UNSHIP',
      lens: 'BV5',
      severity: 'P1',
      title: 'buyer marcou concluido em CTT sem shipped_at',
      actor: 'buyer JWT',
      pre: 'pago + não is_hand → order_concluido_requires_shipped',
      repro: 'PATCH orders status=concluido (shipping CTT, shipped_at null)',
      expected: 'status continua pago',
      obtained: {'hit': conclBuyer.brief, 'order': rowConcl},
    );
  } else {
    c.block('concl.buyer.ctt', 'BV5', 'buyer não concluiu CTT sem envio', {
      'hit': conclBuyer.brief,
      'status': rowConcl?['status'],
    });
  }

  // near-hand spoof
  for (final method in [
    'hand delivery',
    'mão a mão',
    'entrega em maozinha',
    'HANDS',
    'pickup at store',
    'entrega em m%',
  ]) {
    final p = await mustPay('BV5');
    await c.patchOrder(p.oid, {'shipping_method': method}, service: true);
    final hit = await c.patchOrder(p.oid, {'status': 'concluido'}, jwt: c.buyerJwt);
    final row = await c.orderRow(p.oid);
    final st = '${row?['status']}'.toLowerCase();
    c.note('hand.spoof.$method', 'buyer concluido method=$method', {
      'hit': hit.brief,
      'status': st,
    }, lens: 'BV5');
    if (st == 'concluido') {
      c.hold(
        id: 'BV-P1-HAND-$method',
        lens: 'BV5',
        severity: 'P1',
        title: 'is_hand spoof "$method" permitiu concluido sem envio',
        actor: 'buyer JWT',
        pre: 'allowlist exacta batata_shipping_method_is_hand',
        repro: 'shipping_method=$method; PATCH concluido',
        expected: 'não concluido',
        obtained: {'hit': hit.brief, 'order': row},
      );
    } else {
      c.block('hand.spoof.$method', 'BV5', 'spoof "$method" recusado', hit);
    }
  }

  // fixture service concluido CTT sem shipped + release JWT buyer
  final pRel = await mustPay('BV3');
  await c.patchOrder(pRel.oid, {
    'shipping_method': 'CTT',
    'status': 'concluido',
    'shipped_at': null,
  }, service: true);
  final rowForced = await c.orderRow(pRel.oid);
  final balBeforeRel = await c.walletBal(c.sellerId);
  final relBuyer = await c.tryRelease(pRel.oid, jwt: c.buyerJwt);
  final relSeller = await c.tryRelease(pRel.oid, jwt: c.sellerJwt);
  final relB2 = await c.tryRelease(pRel.oid, jwt: c.buyer2Jwt);
  final rowRel = await c.orderRow(pRel.oid);
  final balAfterRel = await c.walletBal(c.sellerId);
  final dRel = balAfterRel - balBeforeRel;
  c.note('release.unship', 'release concluido CTT sem shipped_at', {
    'forced': rowForced,
    'relBuyer': relBuyer.brief,
    'relSeller': relSeller.brief,
    'relB2': relB2.brief,
    'after': rowRel,
    'delta_seller': dRel,
  }, lens: 'BV3');
  final released = rowRel?['wallet_release_processed_at'] != null && dRel > 0;
  if (released) {
    c.hold(
      id: 'BV-P0-REL-UNSHIP',
      lens: 'BV3',
      severity: 'P0',
      title: 'release creditou carteira em concluido CTT sem shipped_at',
      actor: 'buyer JWT (estado forçado service = fixture; crédito via JWT)',
      pre: 'release exige concluido + (shipped_at OU is_hand)',
      repro: 'service PATCH concluido CTT shipped_at null; rpc release JWT buyer',
      expected: 'rpc false, sem Δwallet',
      obtained: {
        'relBuyer': relBuyer.brief,
        'delta': dRel,
        'order': rowRel,
      },
    );
  } else {
    c.block('release.unship', 'BV3', 'release sem mão/envio não creditou', {
      'relBuyer': relBuyer.brief,
      'relSeller': relSeller.brief,
      'jsonBuyer': relBuyer.json,
      'delta': dRel,
      'flag': rowRel?['wallet_release_processed_at'],
    });
  }

  // unship after shipped+concluido
  final pUnship = await mustPay('BV5');
  await c.patchOrder(pUnship.oid, {
    'shipping_method': 'CTT',
    'status': 'enviado',
    'shipped_at': DateTime.now().toUtc().toIso8601String(),
  }, jwt: c.sellerJwt);
  final conclOk = await c.patchOrder(pUnship.oid, {'status': 'concluido'}, jwt: c.buyerJwt);
  final rowShipped = await c.orderRow(pUnship.oid);
  c.note('fsm.ship.concl', 'CTT enviado→concluido', {
    'concl': conclOk.brief,
    'order': rowShipped,
  }, lens: 'BV5');
  final unship = await c.patchOrder(pUnship.oid, {
    'shipped_at': null,
    'status': 'pago',
  }, jwt: c.sellerJwt);
  final rowUnship = await c.orderRow(pUnship.oid);
  c.note('fsm.unship', 'seller tenta unship/pago após concluido', {
    'hit': unship.brief,
    'order': rowUnship,
  }, lens: 'BV5');
  if ('${rowUnship?['status']}'.toLowerCase() == 'pago' ||
      rowUnship?['shipped_at'] == null && '${rowShipped?['status']}'.toLowerCase() == 'concluido' && unship.ok) {
    final stillConcl = '${rowUnship?['status']}'.toLowerCase() == 'concluido';
    if (!stillConcl) {
      c.hold(
        id: 'BV-P1-UNSHIP',
        lens: 'BV5',
        severity: 'P1',
        title: 'seller reverteu concluido/envio (unship FSM)',
        actor: 'seller JWT',
        pre: 'concluido imutável para seller',
        repro: 'após concluido, PATCH status=pago shipped_at=null',
        expected: 'status continua concluido',
        obtained: {'hit': unship.brief, 'order': rowUnship},
      );
    } else {
      c.block('fsm.unship', 'BV5', 'status concluido manteve-se', {
        'hit': unship.brief,
        'order': rowUnship,
      });
    }
  } else {
    c.block('fsm.unship', 'BV5', 'unship/regressão recusada', {
      'hit': unship.brief,
      'status': rowUnship?['status'],
      'shipped_at': rowUnship?['shipped_at'],
    });
  }

  // release + refund composição (venda paga → refund seller → release)
  final pComp = await mustPay('BV3');
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
  }, lens: 'BV3');
  if ((balC1 - balC0) > 0 && '${rowComp?['stripe_refund_id'] ?? ''}'.isNotEmpty) {
    c.hold(
      id: 'BV-P0-REFUND-REL',
      lens: 'BV3',
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
    c.block('comp.refund.release', 'BV3', 'sem crédito líquido pós-refund', {
      'delta': balC1 - balC0,
      'refund': rf.brief,
      'release': relAfterRf.json,
      'flag_rel': rowComp?['wallet_release_processed_at'],
      'refund_id': rowComp?['stripe_refund_id'],
    });
  }

  // race refund
  final pRace = await mustPay('BV3');
  final raceRf = await Future.wait([
    c.refundOrder(pRace.oid, jwt: c.sellerJwt),
    c.refundOrder(pRace.oid, jwt: c.sellerJwt),
    c.refundOrder(pRace.oid, jwt: c.sellerJwt),
  ]);
  c.note('race.refund', '3× refund-order', raceRf.map((h) => h.brief).toList(), lens: 'BV3');
  final oks = raceRf.where((h) => h.ok && h.map?['ok'] == true && h.map?['skipped'] != true).length;
  c.block('race.refund', 'BV3', 'race refund hits (ok count=$oks; idempotência Stripe key por order)', {
    'hits': raceRf.map((h) => h.brief).toList(),
    'ok_true': oks,
  });

  await c.dumpAll('pass2.json');
}
