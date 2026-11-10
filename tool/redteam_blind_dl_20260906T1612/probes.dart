/// RED TEAM CEGO DL — matriz A settle + B tip + C refund/Connect.
/// Staging only. NÃO corrigir. NÃO produção. NÃO Fase 4.
import 'dart:io';
import '_rtdl.dart';

bool looksPaidCopy(HttpHit? h) {
  final t = (h?.body ?? '').toLowerCase();
  return t.contains('pagamento recebido') ||
      t.contains('pagamento confirmado') ||
      t.contains('"status":"pago"');
}

void main() async {
  final c = Rtdl.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.restoreSeller1Published();
  await c.setHub(c.seller2Id!, false);

  final s1 = c.sellerId!;
  final s2 = c.seller2Id!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;

  try {
    await runSettle(c, s1, b1, b2);
    await runTip(c, s1, s2, b2);
    await runRefundConnect(c, s1, s2, b1);
  } finally {
    await c.endLives();
    await c.restoreSeller1Published();
    await c.setHub(s2, false);
  }

  await c.dumpAll('probes.json');
  stdout.writeln(
    'DL DONE probes=${c.probes.length} findings=${c.findings.length} '
    'lenses=${c.lensesHit.toList()..sort()}',
  );
}

Future<void> runSettle(Rtdl c, String s1, String b1, String b2) async {
  const price = 12.0;
  final pidA = await c.createProduct(
    seller: s1,
    title: '$prefix settle-A',
    qty: 4,
    price: price,
  );
  final pidB = await c.createProduct(
    seller: s1,
    title: '$prefix settle-B',
    qty: 4,
    price: price,
  );
  if (pidA == null || pidB == null) {
    c.skip('A*', 'DL1', 'SKU fixture falhou', {'a': pidA, 'b': pidB});
    return;
  }
  final oidA = await c.insertOrder(productId: pidA, buyer: b1, seller: s1, price: price);
  final oidB = await c.insertOrder(productId: pidB, buyer: b1, seller: s1, price: price);
  if (oidA == null || oidB == null) {
    c.skip('A*', 'DL1', 'order fixture falhou', {'a': oidA, 'b': oidB});
    return;
  }

  // A3 first so we observe client amount vs server on a fresh checkout.
  final ckA3 = await c.checkout(
    orderId: oidA,
    buyer: b1,
    jwt: c.buyerJwt,
    amount: 1,
    productId: pidA,
    seller: s1,
    extra: {
      'total': 50,
      'server_amount_cents': '50',
      'metadata_amount': 1,
    },
  );
  final sidA = ckA3.sessionId;
  HttpHit? sessA;
  int? stripeAmount;
  String? metaServer;
  String? metaTotal;
  String? metaOrder;
  if (sidA != null) {
    sessA = await c.stripeSession(sidA, expandPi: true);
    stripeAmount = numOf(sessA.map?['amount_total'])?.round();
    final meta = sessA.map?['metadata'];
    if (meta is Map) {
      metaServer = '${meta['server_amount_cents'] ?? ''}';
      metaTotal = '${meta['total'] ?? ''}';
      metaOrder = '${meta['order_id'] ?? ''}';
    }
  }
  final rowA3 = await c.orderRow(oidA);
  final clientWon = stripeAmount != null &&
      stripeAmount <= 50 &&
      stripeAmount != 1200 &&
      stripeAmount != 1250;
  // 12,00 € + possível taxa: servidor ≥ 1200. Cliente pediu 1 / 50.
  c.probe(
    id: 'A3',
    edgeRpc: 'create-payment-intent POST',
    payload:
        'POST checkout amount=1 total=50 server_amount_cents=50 vs quote SKU 12,00€',
    http: ckA3,
    stripeBd: {
      'sid': sidA,
      'stripe_amount_total': stripeAmount,
      'meta.server_amount_cents': metaServer,
      'meta.total': metaTotal,
      'meta.order_id': metaOrder,
      'order.status': rowA3?['status'],
      'order.price_total': rowA3?['price_total'],
    },
    result: !ckA3.ok
        ? 'SKIP'
        : (clientWon ? 'FAIL' : 'HOLD'),
    lens: 'DL1',
    countFinding: clientWon,
  );
  if (clientWon) {
    c.hold(
      id: 'DL-P0-A3-CLIENT-AMOUNT',
      lens: 'DL1',
      severity: 'P0',
      title: 'Checkout Stripe usou amount/total do cliente em vez da quote servidor',
      actor: 'B1 JWT',
      pre: 'SKU 12,00€; body amount=1 total=50',
      repro: 'POST create-payment-intent {amount:1,total:50,server_amount_cents:50}',
      expected: 'Session amount_total = quote servidor (≥1200¢)',
      obtained: {
        'stripe_amount_total': stripeAmount,
        'meta': {'server': metaServer, 'total': metaTotal},
        'http': ckA3.brief,
      },
    );
  } else if (ckA3.ok) {
    c.block('A3.amount', 'DL1', 'Session cobra quote servidor, não body.amount', {
      'stripe_amount_total': stripeAmount,
      'meta.server': metaServer,
      'meta.total': metaTotal,
    });
  } else {
    c.skip('A3', 'DL1', 'checkout A3 não criou Session', ckA3);
  }

  // A1 settle unpaid GET
  HttpHit? a1get;
  Map<String, dynamic>? rowA1;
  if (sidA != null) {
    a1get = await c.settleGet(sidA);
    rowA1 = await c.orderRow(oidA);
  }
  final a1credited = c.orderPaid(rowA1) ||
      looksPaidCopy(a1get) ||
      (numOf(rowA1?['amount_paid_cents']) ?? 0) > 0;
  c.probe(
    id: 'A1',
    edgeRpc: 'create-payment-intent GET settle',
    payload: 'GET checkout_return=success Session unpaid $sidA',
    http: a1get ?? ckA3,
    stripeBd: {
      'status': rowA1?['status'],
      'amount_paid_cents': rowA1?['amount_paid_cents'],
      'pi': rowA1?['stripe_payment_intent_id'],
    },
    result: sidA == null ? 'SKIP' : (a1credited ? 'FAIL' : 'HOLD'),
    lens: 'DL1',
    countFinding: a1credited,
  );
  if (a1credited) {
    c.hold(
      id: 'DL-P0-A1-SETTLE-UNPAID',
      lens: 'DL1',
      severity: 'P0',
      title: 'GET settle unpaid marcou encomenda paga',
      actor: 'anon GET (sem JWT)',
      pre: 'Checkout Session payment_status≠paid',
      repro: 'GET create-payment-intent?checkout_return=success&session_id=',
      expected: 'status≠pago; amount_paid=0',
      obtained: {'get': a1get?.brief, 'row': rowA1},
    );
  } else if (sidA != null) {
    c.block('A1.unpaid', 'DL1', 'GET settle unpaid não creditou', {
      'get': a1get?.brief,
      'status': rowA1?['status'],
    });
  }

  // A2 session_id alheio: GET settle sidA contra... + swap metadata order A→B
  final ckB = await c.checkout(
    orderId: oidB,
    buyer: b1,
    jwt: c.buyerJwt,
    amount: 1200,
    productId: pidB,
    seller: s1,
  );
  final sidB = ckB.sessionId;
  HttpHit? a2cross;
  HttpHit? a2swapGet;
  HttpHit? a2pay;
  HttpHit? a2settlePaid;
  Map<String, dynamic>? rowA2a;
  Map<String, dynamic>? rowA2b;
  String? swapPi;
  if (sidA != null) {
    a2cross = await c.settleGet(sidA); // B2 não precisa — session resolve order_id
    // GET com session B no endpoint, já coberto; alien = mutar metadata A→B
    if (c.stripeTestKey != null) {
      final patch = await c.stripePatchSessionMeta(sidA, {
        'order_id': oidB,
        'product_id': pidB,
      });
      c.note('A2.patch', 'Stripe metadata order_id A→B', patch, lens: 'DL1');
      a2swapGet = await c.settleGet(sidA);
      rowA2a = await c.orderRow(oidA);
      rowA2b = await c.orderRow(oidB);
      final sess = await c.stripeSession(sidA, expandPi: true);
      swapPi = c.piFromSession(sess);
      if (swapPi != null) {
        a2pay = await c.stripeConfirmPi(swapPi);
        c.note('A2.pay', 'confirm PI após swap metadata', a2pay, lens: 'DL1');
        if (a2pay.ok || '${a2pay.map?['status']}' == 'succeeded') {
          a2settlePaid = await c.settleGet(sidA);
          rowA2a = await c.orderRow(oidA);
          rowA2b = await c.orderRow(oidB);
        }
      }
    }
  }
  final bPaidWrong = c.orderPaid(rowA2b) && !c.orderPaid(rowA2a);
  final unpaidSwapCredit =
      (c.orderPaid(rowA2b) || c.orderPaid(rowA2a)) && a2pay == null;
  final a2fail = bPaidWrong || unpaidSwapCredit;
  c.probe(
    id: 'A2',
    edgeRpc: 'create-payment-intent GET + Stripe metadata swap',
    payload:
        'settle session A; metadata.order_id A→B; confirm PI TEST se possível',
    http: {
      'ckB': ckB.brief,
      'crossGet': a2cross?.brief,
      'swapGet': a2swapGet?.brief,
      'pay': a2pay?.brief,
      'settlePaid': a2settlePaid?.brief,
    },
    stripeBd: {
      'sidA': sidA,
      'sidB': sidB,
      'oidA': oidA,
      'oidB': oidB,
      'statusA': rowA2a?['status'] ?? (await c.orderRow(oidA))?['status'],
      'statusB': rowA2b?['status'] ?? (await c.orderRow(oidB))?['status'],
      'pi': swapPi,
    },
    result: sidA == null
        ? 'SKIP'
        : (a2fail ? 'FAIL' : 'HOLD'),
    lens: 'DL1',
    countFinding: a2fail,
  );
  if (a2fail) {
    c.hold(
      id: 'DL-P0-A2-ALIEN-SESSION',
      lens: 'DL1',
      severity: 'P0',
      title: bPaidWrong
          ? 'Session A (metadata swap) liquidou encomenda B'
          : 'GET settle com session alheia creditou encomenda unpaid',
      actor: 'anon GET + sk_test_ metadata',
      pre: 'duas orders 12,00€; Session A unpaid; metadata.order_id→B',
      repro: 'POST Stripe sessions metadata order_id=B; GET settle sidA',
      expected: 'A e B continuam não pagas (unpaid) ou mismatch quote recusa',
      obtained: {
        'A': rowA2a,
        'B': rowA2b,
        'pay': a2pay?.brief,
        'settle': a2settlePaid?.brief,
      },
    );
  } else if (sidA != null) {
    c.block('A2.alien', 'DL1', 'session alheia / swap metadata não liquidou B', {
      'statusA': (rowA2a ?? await c.orderRow(oidA))?['status'],
      'statusB': (rowA2b ?? await c.orderRow(oidB))?['status'],
      'pay': a2pay?.brief,
    });
  }

  // A4 reuse after expire
  final pidE = await c.createProduct(
    seller: s1,
    title: '$prefix expire',
    qty: 2,
    price: price,
  );
  final oidE = pidE == null
      ? null
      : await c.insertOrder(productId: pidE, buyer: b1, seller: s1, price: price);
  HttpHit? ckE;
  HttpHit? exp;
  HttpHit? a4get;
  HttpHit? a4pay;
  Map<String, dynamic>? rowE;
  String? sidE;
  if (oidE != null && pidE != null) {
    ckE = await c.checkout(
      orderId: oidE,
      buyer: b1,
      jwt: c.buyerJwt,
      amount: 1200,
      productId: pidE,
      seller: s1,
    );
    sidE = ckE.sessionId;
    if (sidE != null && c.stripeTestKey != null) {
      exp = await c.stripeExpire(sidE);
      a4get = await c.settleGet(sidE);
      final sessE = await c.stripeSession(sidE, expandPi: true);
      final piE = c.piFromSession(sessE);
      if (piE != null) {
        a4pay = await c.stripeConfirmPi(piE);
      }
      rowE = await c.orderRow(oidE);
    }
  }
  final a4credited = c.orderPaid(rowE) ||
      looksPaidCopy(a4get) ||
      (a4pay != null &&
          a4pay.ok &&
          '${a4pay.map?['status']}' == 'succeeded');
  c.probe(
    id: 'A4',
    edgeRpc: 'create-payment-intent GET + sessions/expire',
    payload: 'expire Session unpaid → GET settle + confirm PI',
    http: {
      'create': ckE?.brief,
      'expire': exp?.brief,
      'get': a4get?.brief,
      'confirm': a4pay?.brief,
    },
    stripeBd: {
      'sid': sidE,
      'status': rowE?['status'],
      'sess_status': exp?.map?['status'],
    },
    result: sidE == null || c.stripeTestKey == null
        ? 'SKIP'
        : (a4credited ? 'FAIL' : 'HOLD'),
    lens: 'DL1',
    countFinding: a4credited,
  );
  if (a4credited) {
    c.hold(
      id: 'DL-P0-A4-EXPIRE-REUSE',
      lens: 'DL1',
      severity: 'P0',
      title: 'Session expirada ainda settle/paga',
      actor: 'anon GET + sk_test_ confirm',
      pre: 'POST /v1/checkout/sessions/:id/expire',
      repro: 'GET settle + PaymentIntent confirm após expire',
      expected: 'não pago; confirm recusado',
      obtained: {
        'expire': exp?.brief,
        'get': a4get?.brief,
        'pay': a4pay?.brief,
        'row': rowE,
      },
    );
  } else if (sidE != null) {
    c.block('A4.expire', 'DL1', 'expire impede settle/confirm', {
      'get': a4get?.brief,
      'pay': a4pay?.brief,
      'status': rowE?['status'],
    });
  }

  // Extra: webhook unsigned (settle/webhook lens)
  final wh = await c.edge(
    'stripe-webhook',
    body: {
      'type': 'checkout.session.completed',
      'data': {
        'object': {
          'id': sidA ?? 'cs_test_rtdl_fake',
          'payment_status': 'paid',
          'metadata': {'order_id': oidA, 'purpose': 'order'},
        },
      },
    },
    extra: {'stripe-signature': 't=1,v1=deadbeef'},
  );
  final rowWh = await c.orderRow(oidA);
  final whOpen = c.orderPaid(rowWh) && !c.orderPaid(rowA1);
  c.probe(
    id: 'A5',
    edgeRpc: 'stripe-webhook POST',
    payload: 'POST webhook assinatura forjada checkout.session.completed paid',
    http: wh,
    stripeBd: {'status': rowWh?['status']},
    result: whOpen ? 'FAIL' : 'HOLD',
    lens: 'DL1',
    countFinding: whOpen,
  );
  if (whOpen) {
    c.hold(
      id: 'DL-P0-A5-WEBHOOK-FORGE',
      lens: 'DL1',
      severity: 'P0',
      title: 'Webhook Stripe sem assinatura válida liquidou encomenda',
      actor: 'anon POST',
      pre: 'constructEventAsync exige STRIPE_WEBHOOK_SECRET',
      repro: 'POST stripe-webhook stripe-signature lixo',
      expected: '400 invalid_signature; order inalterada',
      obtained: {'http': wh.brief, 'row': rowWh},
    );
  } else {
    c.block('A5.webhook', 'DL1', 'assinatura forjada recusada', wh);
  }
}

Future<void> runTip(Rtdl c, String s1, String s2, String b2) async {
  await c.restoreSeller1Published();
  await c.setHub(s2, false);
  final live = await c.insertLive(
    seller: s1,
    active: true,
    status: 'live',
    title: '$prefix air',
  );
  if (live == null) {
    c.skip('B*', 'DL2', 'live fixture falhou', null);
    return;
  }

  Future<HttpHit> publish(bool on) =>
      c.rpc('batata_publish_hub', {'p_publish': on}, jwt: c.sellerJwt);

  // B1 amount hostil / tip_id cliente
  final amounts = <num>[0, 0.01, -1, 0.5, 501];
  final amtHits = <String, String>{};
  final amtOk = <num>[];
  for (final amt in amounts) {
    final t = await c.tipCheckout(
      liveId: live,
      seller: s1,
      amountEur: amt,
      jwt: c.buyer2Jwt,
    );
    amtHits['$amt'] = t.brief;
    if (t.ok) amtOk.add(amt);
  }
  final tipIdBody = await c.tipCheckout(
    liveId: live,
    seller: s1,
    amountEur: 2,
    jwt: c.buyer2Jwt,
    extra: {'tip_id': '00000000-0000-4000-a000-0000000000dd'},
  );
  final b1fail = amtOk.isNotEmpty || tipIdBody.ok;
  c.probe(
    id: 'B1',
    edgeRpc: 'create-live-tip-checkout POST',
    payload: 'amount 0/0.01/-1/0.5/501 + tip_id cliente',
    http: {'amounts': amtHits, 'tip_id': tipIdBody.brief},
    stripeBd: {'accepted': amtOk},
    result: b1fail ? 'FAIL' : 'HOLD',
    lens: 'DL2',
    countFinding: b1fail,
  );
  if (b1fail) {
    c.hold(
      id: 'DL-P1-B1-TIP-HOSTILE',
      lens: 'DL2',
      severity: amtOk.any((a) => a >= 501) ? 'P2' : 'P1',
      title: 'tip aceita amount hostil e/ou tip_id do cliente',
      actor: 'B2 JWT',
      pre: 'teto 1–500 EUR; Client tip_id is not allowed',
      repro: 'POST create-live-tip-checkout amount_eur hostil / tip_id UUID',
      expected: '400',
      obtained: {'amounts': amtHits, 'tip_id': tipIdBody.brief},
    );
  } else {
    c.block('B1.amount', 'DL2', 'amount hostil + tip_id cliente 400', {
      'amounts': amtHits,
      'tip_id': tipIdBody.brief,
    });
  }

  // B2 mid-unpublish unpaid
  final bal0 = await c.walletBal(s1);
  final create = await c.tipCheckout(
    liveId: live,
    seller: s1,
    amountEur: 2,
    jwt: c.buyer2Jwt,
  );
  final tipId = create.tipId;
  final sess = create.sessionId;
  if (tipId != null) c.createdTipIds.add(tipId);
  final unpub = await publish(false);
  final mid = await c.profile(s1);
  HttpHit? getUnpaid;
  if (sess != null) {
    getUnpaid = await c.tipSettleGet(sess, jwt: c.buyer2Jwt);
  }
  var tipSt = '';
  if (tipId != null) {
    final row = await c.rest(
      'GET',
      'live_tips?id=eq.$tipId&select=id,status,amount',
      service: true,
    );
    tipSt = '${row.map?['status'] ?? ''}';
  }
  final bal1 = await c.walletBal(s1);
  await publish(true);
  await c.restoreSeller1Published();
  final after = await c.profile(s1);
  final unpaidCredit =
      c.tipCredited(tipSt, bal1 - bal0) || looksPaidCopy(getUnpaid);
  String b2res;
  if (!create.ok) {
    b2res = 'SKIP';
    c.skip('B2', 'DL2', 'não criou Session tip', create);
  } else if (mid?['hub_published'] != false) {
    b2res = 'SKIP';
    c.skip('B2', 'DL2', 'unpublish S1 não pegou', mid);
  } else {
    b2res = unpaidCredit ? 'FAIL' : 'HOLD';
  }
  c.probe(
    id: 'B2',
    edgeRpc: 'create-live-tip-checkout GET settle',
    payload: 'Session published → unpublish hub → GET unpaid',
    http: {
      'create': create.brief,
      'unpub': unpub.brief,
      'get': getUnpaid?.brief,
    },
    stripeBd: {
      'hub_mid': mid?['hub_published'],
      'hub_after': after?['hub_published'],
      'tipStatus': tipSt,
      'delta': bal1 - bal0,
    },
    result: b2res,
    lens: 'DL2',
    countFinding: unpaidCredit && create.ok && mid?['hub_published'] == false,
  );
  if (unpaidCredit && create.ok && mid?['hub_published'] == false) {
    c.hold(
      id: 'DL-P0-B2-TIP-MIDUNPUB',
      lens: 'DL2',
      severity: 'P0',
      title: 'GET settle após unpublish creditou gorjeta não paga',
      actor: 'B2',
      pre: 'Session S1 published; hub_published=false a meio',
      repro: 'GET create-live-tip-checkout?checkout_return=success',
      expected: 'pending; Δwallet=0',
      obtained: {'status': tipSt, 'delta': bal1 - bal0, 'get': getUnpaid?.brief},
    );
  } else if (create.ok && mid?['hub_published'] == false) {
    c.block('B2.midunpub', 'DL2', 'GET unpaid mid-unpublish não creditou', {
      'status': tipSt,
      'delta': bal1 - bal0,
    });
  }

  // B3 seller≠owner
  final liveS2 = await c.insertLive(
    seller: s2,
    active: true,
    status: 'live',
    title: '$prefix s2',
  );
  await c.setHub(s2, true);
  final wrong = await c.tipCheckout(
    liveId: live,
    seller: s2,
    amountEur: 2,
    jwt: c.buyer2Jwt,
  );
  final s2own = liveS2 == null
      ? null
      : await c.tipCheckout(
          liveId: liveS2,
          seller: s1,
          amountEur: 2,
          jwt: c.buyer2Jwt,
        );
  await c.setHub(s2, false);
  final b3fail = wrong.ok || (s2own?.ok == true);
  c.probe(
    id: 'B3',
    edgeRpc: 'create-live-tip-checkout POST',
    payload: 'seller_id S2 na live S1; seller_id S1 na live S2',
    http: {'s2_on_s1_live': wrong.brief, 's1_on_s2_live': s2own?.brief},
    result: b3fail ? 'FAIL' : 'HOLD',
    lens: 'DL2',
    countFinding: b3fail,
  );
  if (b3fail) {
    c.hold(
      id: 'DL-P1-B3-TIP-SELLER',
      lens: 'DL2',
      severity: 'P1',
      title: 'tip aceita seller_id ≠ dono da live',
      actor: 'B2 JWT',
      pre: 'Tip seller does not own this live',
      repro: 'POST create-live-tip-checkout seller_id alheio',
      expected: '400',
      obtained: {'wrong': wrong.brief, 's2own': s2own?.brief},
    );
  } else {
    c.block('B3.owner', 'DL2', 'seller≠owner 400', {
      'wrong': wrong.brief,
      's2own': s2own?.brief,
    });
  }
}

Future<void> runRefundConnect(Rtdl c, String s1, String s2, String b1) async {
  Future<({String oid, String pid, String? pi})> mustPay(String lens) async {
    final paid = await c.payToPago(lens: lens);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  // C1 buyer refund → 403 (HOLD, não contar)
  final pBuyer = await mustPay('DL3');
  final balS0 = await c.walletBal(s1);
  final buyerRefund = await c.refundOrder(pBuyer.oid, jwt: c.buyerJwt);
  final rowAfterBuyer = await c.orderRow(pBuyer.oid);
  final balS1w = await c.walletBal(s1);
  final buyerDid = buyerRefund.ok &&
      buyerRefund.map?['ok'] == true &&
      buyerRefund.map?['skipped'] != true &&
      '${rowAfterBuyer?['stripe_refund_id'] ?? ''}'.isNotEmpty;
  c.probe(
    id: 'C1',
    edgeRpc: 'refund-order',
    payload: 'POST refund-order JWT comprador order=${pBuyer.oid}',
    http: buyerRefund,
    stripeBd: {
      'refund_id': rowAfterBuyer?['stripe_refund_id'],
      'status': rowAfterBuyer?['status'],
      'deltaSeller': balS1w - balS0,
    },
    result: buyerDid ? 'FAIL' : 'HOLD',
    lens: 'DL3',
    countFinding: buyerDid,
  );
  if (buyerDid) {
    c.hold(
      id: 'DL-P0-C1-BUYER-REFUND',
      lens: 'DL3',
      severity: 'P0',
      title: 'buyer refund-order anulou Stripe da venda',
      actor: 'buyer JWT',
      pre: 'Edge exige user.id === seller_id',
      repro: 'POST refund-order {order_id} JWT comprador',
      expected: '403 Sem permissão',
      obtained: buyerRefund.brief,
    );
  } else {
    c.block('C1.buyer', 'DL3', 'buyer refund-order recusado (seller-only)',
        buyerRefund);
  }

  // C2 seller refund idempotente 2× — dinheiro TEST real
  final pIdem = await mustPay('DL4');
  final r1 = await c.refundOrder(pIdem.oid, jwt: c.sellerJwt);
  final row1 = await c.orderRow(pIdem.oid);
  final r2 = await c.refundOrder(pIdem.oid, jwt: c.sellerJwt);
  final row2 = await c.orderRow(pIdem.oid);
  final id1 = '${row1?['stripe_refund_id'] ?? r1.map?['refund_id'] ?? ''}';
  final id2 = '${row2?['stripe_refund_id'] ?? r2.map?['refund_id'] ?? ''}';
  final firstOk = r1.ok && r1.map?['ok'] == true && r1.map?['skipped'] != true;
  final secondNew = r2.ok &&
      r2.map?['ok'] == true &&
      r2.map?['already_refunded'] != true &&
      r2.map?['idempotent'] != true &&
      id2.isNotEmpty &&
      id1.isNotEmpty &&
      id2 != id1;
  c.probe(
    id: 'C2',
    edgeRpc: 'refund-order ×2',
    payload: 'seller refund pago ${pIdem.oid} duas vezes',
    http: {'r1': r1.brief, 'r2': r2.brief},
    stripeBd: {
      'refund1': id1,
      'refund2': id2,
      'status1': row1?['status'],
      'status2': row2?['status'],
      'already': r2.map?['already_refunded'],
      'idempotent': r2.map?['idempotent'],
    },
    result: !firstOk
        ? 'SKIP'
        : (secondNew ? 'FAIL' : 'HOLD'),
    lens: 'DL4',
    countFinding: secondNew,
  );
  if (secondNew) {
    c.hold(
      id: 'DL-P0-C2-REFUND-DUP',
      lens: 'DL4',
      severity: 'P0',
      title: '2.º refund-order criou refund Stripe distinto',
      actor: 'seller JWT',
      pre: 'idempotency fleaber_order_refund_{orderId}',
      repro: 'POST refund-order 2× mesma order paga',
      expected: '2.º already_refunded / mesmo refund_id',
      obtained: {'r1': r1.brief, 'r2': r2.brief, 'id1': id1, 'id2': id2},
    );
  } else if (firstOk) {
    c.block('C2.idem', 'DL4', '2.º refund idempotente', {
      'r1': r1.brief,
      'r2': r2.brief,
      'id1': id1,
      'id2': id2,
    });
  } else {
    c.skip('C2', 'DL4', '1.º seller refund não passou', r1);
  }

  // C3 refund∥release race
  final pRace = await mustPay('DL5');
  final balC0 = await c.walletBal(s1);
  final raced = await Future.wait([
    c.refundOrder(pRace.oid, jwt: c.sellerJwt),
    c.tryRelease(pRace.oid, jwt: c.buyerJwt),
    c.tryRelease(pRace.oid, jwt: c.sellerJwt),
  ]);
  final balC1 = await c.walletBal(s1);
  final refunded = raced[0].ok &&
      raced[0].map?['ok'] == true &&
      raced[0].map?['skipped'] != true;
  final released = raced[1].json == true || raced[2].json == true;
  final raceOpen = refunded && released && (balC1 - balC0) > 0;
  c.probe(
    id: 'C3',
    edgeRpc: 'refund-order ∥ batata_release_seller_wallet_for_order',
    payload: 'Future.wait refund seller + release buyer/seller no pago',
    http: raced.map((h) => h.brief).toList(),
    stripeBd: {
      'refunded': refunded,
      'released': released,
      'delta': balC1 - balC0,
    },
    result: raceOpen ? 'FAIL' : 'HOLD',
    lens: 'DL5',
    countFinding: raceOpen,
  );
  if (raceOpen) {
    c.hold(
      id: 'DL-P0-C3-RACE',
      lens: 'DL5',
      severity: 'P0',
      title: 'race refund∥release: Stripe refund + crédito wallet',
      actor: 'seller refund + buyer/seller release paralelo',
      pre: 'release inelegível em pago',
      repro: 'Future.wait refund-order + release',
      expected: 'refund OU nada; release false; Δ≤0',
      obtained: {
        'hits': raced.map((h) => h.brief).toList(),
        'delta': balC1 - balC0,
      },
    );
  } else {
    c.block('C3.race', 'DL5', 'race pago sem crédito+refund simultâneo', {
      'refunded': refunded,
      'released': released,
      'delta': balC1 - balC0,
    });
  }

  // C4 Connect idempotency hostil (NÃO charset Coptic — amount mutate + cross-user)
  await c.ensureWalletBalance(s1, 8);
  final t0 = await c.transferIds(s1);
  final balP0 = await c.walletBal(s1);
  final key = 'rtdl1612amtmut01';
  final p100 = await c.connect({'amount': 100, 'idempotency_key': key});
  final p500 = await c.connect({'amount': 500, 'idempotency_key': key});
  final foreign = await c.connect(
    {'amount': 100, 'idempotency_key': key},
    jwt: c.seller2Jwt,
  );
  final t1 = await c.transferIds(s1);
  final newT = t1.difference(t0);
  final balP1 = await c.walletBal(s1);
  final mutated = newT.length >= 2 || (balP0 - balP1) >= 6;
  final foreignOk = foreign.payoutOk;
  c.probe(
    id: 'C4',
    edgeRpc: 'create-connect-account',
    payload: 'mesma key amount 100 depois 500; S2 reutiliza key S1',
    http: {
      'p100': p100.brief,
      'p500': p500.brief,
      's2': foreign.brief,
    },
    stripeBd: {
      'new_tr': newT.toList(),
      'delta': balP1 - balP0,
      'idempotent500': p500.map?['idempotent'],
    },
    result: (mutated || foreignOk) ? 'FAIL' : 'HOLD',
    lens: 'DL6',
    countFinding: mutated || foreignOk,
  );
  if (mutated || foreignOk) {
    c.hold(
      id: 'DL-P0-C4-IDEM-HOSTILE',
      lens: 'DL6',
      severity: 'P0',
      title: mutated
          ? 'idempotency_key + amount hostil criou 2.ª Transfer'
          : 'S2 reutilizou idempotency_key de S1 e levantou',
      actor: 'seller JWT / S2 JWT',
      pre: 'key canónica por user; amount no débito',
      repro: 'POST connect key K amount 100 depois 500; S2 POST key K',
      expected: '2.º POST S1 idempotente 100¢; S2 400 foreign',
      obtained: {
        'p100': p100.brief,
        'p500': p500.brief,
        's2': foreign.brief,
        'new_tr': newT.toList(),
        'delta': balP1 - balP0,
      },
    );
  } else {
    c.block('C4.idem', 'DL6', 'amount mutate + cross-user key sem 2.ª Transfer', {
      'p100': p100.brief,
      'p500': p500.brief,
      's2': foreign.brief,
      'n_tr': newT.length,
    });
  }

  // C5 overbalance / dest alheio
  final w0 = await c.walletRow(s1);
  final ownAcct = '${w0?['stripe_account_id'] ?? ''}';
  final others = await c.otherConnectAccounts(s1);
  final otherAcct = others.isNotEmpty
      ? '${others.first['stripe_account_id']}'
      : 'acct_1RTDLOtherSellerXXXX';
  await c.ensureWalletBalance(s1, 5);
  final tD0 = await c.transferIds(s1);
  final destBody = await c.connect({
    'amount': 100,
    'idempotency_key': 'rtdl1612destxxxx',
    'destination': otherAcct,
    'stripe_account_id': otherAcct,
    'account': otherAcct,
    'connect_account': otherAcct,
    'currency': 'usd',
  });
  final tD1 = await c.transferIds(s1);
  var destDiverted = false;
  if (destBody.payoutOk && otherAcct.isNotEmpty && otherAcct != ownAcct) {
    final logs = await c.rest(
      'GET',
      'app_logs?category=eq.wallet_payout&select=error_message,device_info,created_at&order=created_at.desc&limit=6',
      service: true,
    );
    destDiverted = logs.list.any((row) {
      final blob = '$row';
      return blob.contains(otherAcct) && blob.contains('payout_start');
    });
  }
  final balNow = await c.walletBal(s1);
  final huge = await c.connect({
    'amount': 99999999,
    'idempotency_key': 'rtdl1612overbalx',
  });
  final balAfterHuge = await c.walletBal(s1);
  final mintOpen = huge.payoutOk || (balAfterHuge - balNow) < -1;
  c.probe(
    id: 'C5',
    edgeRpc: 'create-connect-account',
    payload: 'destination=$otherAcct currency=usd; amount=99999999 vs saldo $balNow',
    http: {'dest': destBody.brief, 'huge': huge.brief},
    stripeBd: {
      'own': ownAcct,
      'other': otherAcct,
      'new_tr': tD1.difference(tD0).toList(),
      'deltaHuge': balAfterHuge - balNow,
      'destDiverted': destDiverted,
    },
    result: (destDiverted || mintOpen) ? 'FAIL' : 'HOLD',
    lens: 'DL6',
    countFinding: destDiverted || mintOpen,
  );
  if (destDiverted || mintOpen) {
    c.hold(
      id: destDiverted ? 'DL-P0-C5-DEST' : 'DL-P0-C5-OVERBAL',
      lens: destDiverted ? 'DL6' : 'DL7',
      severity: 'P0',
      title: destDiverted
          ? 'Transfer destination = conta Stripe alheia'
          : 'payout > saldo debitou/mintou',
      actor: 'seller JWT',
      pre: 'destination do body ignorado; amount ≤ wallet.balance',
      repro: 'POST connect destination alheio / amount 99999999',
      expected: 'Transfer própria; overbalance 400 Δ=0',
      obtained: {
        'dest': destBody.brief,
        'huge': huge.brief,
        'deltaHuge': balAfterHuge - balNow,
      },
    );
  } else {
    c.block('C5.dest.over', 'DL6', 'dest própria; overbalance recusado', {
      'dest': destBody.brief,
      'huge': huge.brief,
      'deltaHuge': balAfterHuge - balNow,
    });
  }
}
