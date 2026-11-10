/// RED TEAM CEGO EO — maratona dinheiro POS_OPEN_GATE.
/// Staging only. Stripe TEST. NÃO CORRIGIR. Fase 4 não.
/// Anti-atrofia: NÃO Coptic · NÃO charset 400.
/// Residuais máx 1 cada: buyer refund 403 (dentro de C3) · tip seller≠owner (B6) · GET unpaid 402 (dentro de A1).
import 'dart:io';
import '_rteo.dart';

bool looksPaidCopy(HttpHit? h) {
  final t = (h?.body ?? '').toLowerCase();
  return t.contains('pagamento recebido') ||
      t.contains('pagamento confirmado') ||
      t.contains('"status":"pago"') ||
      t.contains('gorjeta registada') ||
      t.contains('gorjeta conclu');
}

bool stripeOracle(HttpHit? h) {
  final t = (h?.body ?? '').toLowerCase();
  return t.contains('no such checkout.session') ||
      t.contains('no such payment_intent') ||
      t.contains('resource_missing');
}

bool corsEchoes(HttpHit h, String origin) {
  final a = (h.acao ?? '').trim();
  if (a.isEmpty) return false;
  if (a == origin) return true;
  if (origin == 'null' && a.toLowerCase() == 'null') return true;
  if (origin.startsWith('chrome-extension://') &&
      a.startsWith('chrome-extension://')) {
    return true;
  }
  if (origin.contains('evil.com') && a.contains('evil.com')) return true;
  return false;
}

bool minted(HttpHit h, num delta) {
  if (delta > 0.001) return true;
  if (h.payoutOk) return true;
  if (h.rpcTrue && h.ok) return true;
  if (h.ok && h.firstId != null && h.status == 201) return true;
  if (h.ok && h.json == true) return true;
  return false;
}

Future<({String oid, String pid, String? pi})> mustPay(
  Rteo c,
  String lens,
) async {
  final paid = await c.payToPago(lens: lens);
  if (paid == null) throw StateError('setup_paid_order failed $lens');
  return paid;
}

void main() async {
  final c = Rteo.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.restoreSeller1Published();
  await c.setHub(c.seller2Id!, false);

  final s1 = c.sellerId!;
  final s2 = c.seller2Id!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;

  stdout.writeln('actors B1=$b1 S1=$s1 B2=$b2 S2=$s2');
  c.skipped.add({
    'id': 'HOLD-anti-atrofia',
    'title':
        'Coptic payout key · charset 400 — não corridos; C3 buyer 403 + B6 seller≠owner = residuais máx 1',
  });

  final caixa = <String, Object?>{};
  try {
    await runSettle(c, s1, b1, b2, caixa);
    await runTip(c, s1, s2, b2, caixa);
    await runWebhookCorsRefund(c, s1, s2, b1, caixa);
    await runPayoutWallet(c, s1, s2, b1, caixa);
    await runCaixa(c, s1, caixa);
  } finally {
    await c.endLives();
    await c.restoreSeller1Published();
    await c.setHub(s2, false);
  }

  await c.dumpAll('pass1.json');
  stdout.writeln(
    'EO DONE probes=${c.probes.length} findings=${c.findings.where((f) => f['count'] == true).length} '
    'lenses=${c.lensesHit.toList()..sort()} nova=${c.classeNova} '
    'races=${c.probes.where((p) => p['race'] == true).length}',
  );
}

Future<void> runSettle(
  Rteo c,
  String s1,
  String b1,
  String b2,
  Map<String, Object?> caixa,
) async {
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
    c.skip('A*', 'EO1', 'SKU fixture falhou', {'a': pidA, 'b': pidB});
    return;
  }
  final oidA = await c.insertOrder(
    productId: pidA,
    buyer: b2,
    seller: s1,
    price: price,
  );
  final oidB = await c.insertOrder(
    productId: pidB,
    buyer: b1,
    seller: s1,
    price: price,
  );
  if (oidA == null || oidB == null) {
    c.skip('A*', 'EO1', 'order fixture falhou', {'a': oidA, 'b': oidB});
    return;
  }

  final ckA = await c.checkout(
    orderId: oidA,
    jwt: c.buyer2Jwt,
    buyer: b2,
    amount: 1,
    productId: pidA,
    extra: {
      'amount_total': 1,
      'total': 1,
      'metadata': {'order_id': oidB, 'paid': true},
    },
  );
  final sidA = ckA.sessionId;
  final quoted = numOf(ckA.map?['server_amount_cents']) ??
      numOf(ckA.map?['amount_total']);
  caixa['sidA'] = sidA;
  caixa['oidA'] = oidA;
  caixa['quoted'] = quoted;

  // A1 POST settle qs unpaid + metadata hostil (GET unpaid 402 dentro desta linha)
  HttpHit postSettle = HttpHit(0, 'no sid', {'error': 'no sid'});
  HttpHit getUnpaid = HttpHit(0, 'no sid', {'error': 'no sid'});
  if (sidA != null) {
    postSettle = await c.settlePost(
      sidA,
      extraQs: 'checkout_return=success&amount=1',
      body: {
        'checkout_return': 'success',
        'session_id': sidA,
        'amount': 1,
        'amount_total': 1,
        'metadata': {
          'order_id': oidB,
          'payment_status': 'paid',
          'amount_total': 1,
        },
        'order_id': oidB,
      },
      jwt: c.buyer2Jwt,
    );
    getUnpaid = await c.settleGet(sidA, jwt: c.buyer2Jwt);
  }
  final rowA1 = await c.orderRow(oidA);
  final a1Paid = c.orderPaid(rowA1) || looksPaidCopy(postSettle);
  c.probe(
    id: 'A1',
    lens: 'EO1',
    edgeRpc: 'CPI POST qs settle unpaid + metadata hostil + GET unpaid',
    payload:
        'POST checkout_return=success unpaid metadata.order_id=$oidB amount=1; GET unpaid',
    http: 'POST ${postSettle.brief} | GET ${getUnpaid.brief}',
    stripeBd:
        'oidA ${rowA1?['status']} amount_paid=${rowA1?['amount_paid_cents']} quoted=$quoted',
    result: a1Paid ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a1Paid,
  );
  if (a1Paid) {
    c.hold(
      id: 'EO-P0-A1-SETTLE-UNPAID',
      lens: 'EO1',
      severity: 'P0',
      title: 'POST settle qs unpaid / metadata hostil creditou ou marcou pago',
      actor: 'B2 JWT',
      pre: 'settle só liquida Session Stripe paid; metadata cliente ignorada',
      repro: 'POST ?checkout_return=success unpaid + metadata.order_id alheio',
      expected: '400/402; reserva_pendente',
      obtained: postSettle.brief,
    );
  } else {
    c.block('A1.settle-qs', 'EO1', 'POST unpaid+metadata não liquida', {
      'post': postSettle.status,
      'get': getUnpaid.status,
      'status': rowA1?['status'],
    });
  }

  // A2 GET session inexistente / whitespace / pi_ como sid / array
  final getFake = await c.settleGet('cs_test_inexistente_eo1952xxxx', jwt: c.buyer2Jwt);
  final getWs = await c.settleGet('%20%20', jwt: c.buyer2Jwt);
  final getPi = await c.settleGet('pi_3UCkYUHOSTILEEO1952xxxx', jwt: c.buyer2Jwt);
  final getArr = await c.edge(
    'create-payment-intent',
    method: 'GET',
    jwt: c.buyer2Jwt,
    qs: 'checkout_return=success&session_id[]=cs_test_arr',
  );
  final oracle = stripeOracle(getFake) ||
      stripeOracle(getWs) ||
      stripeOracle(getPi) ||
      stripeOracle(getArr);
  final a2Paid = looksPaidCopy(getFake) ||
      looksPaidCopy(getWs) ||
      looksPaidCopy(getPi) ||
      looksPaidCopy(getArr);
  c.probe(
    id: 'A2',
    lens: 'EO1',
    edgeRpc: 'GET settle session inexistente / whitespace / pi_ / session_id[]',
    payload: 'cs_inexistente · %20 · pi_ · session_id[]',
    http:
        'fake ${getFake.brief} | ws ${getWs.brief} | pi ${getPi.brief} | arr ${getArr.brief}',
    stripeBd: 'oracle=$oracle oidA ${rowA1?['status']}',
    result: (a2Paid || oracle) ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a2Paid || oracle,
  );
  if (a2Paid || oracle) {
    c.hold(
      id: oracle ? 'EO-P2-A2-ORACLE' : 'EO-P0-A2-SETTLE-FAKE',
      lens: 'EO1',
      severity: oracle && !a2Paid ? 'P2' : 'P0',
      title: a2Paid
          ? 'GET settle sid fake/pi_ liquidou unpaid'
          : 'GET settle ecoa oráculo Stripe (resource_missing)',
      actor: 'B2 JWT',
      pre: '400 genérico; sem oráculo Stripe',
      repro: 'GET session_id inexistente / whitespace / pi_ / array',
      expected: '400 genérico',
      obtained: {
        'fake': getFake.brief,
        'ws': getWs.brief,
        'pi': getPi.brief,
        'arr': getArr.brief,
      },
    );
  } else {
    c.block('A2.sid-hostil', 'EO1', 'fake/ws/pi_/[] 400 genérico', {
      'fake': getFake.status,
      'ws': getWs.status,
      'pi': getPi.status,
      'arr': getArr.status,
    });
  }

  // A3 settle session alheia (oidA B2 → JWT B1 + inject sidA no checkout oidB)
  HttpHit getAlien = HttpHit(0, 'no sid', {'error': 'no sid'});
  HttpHit postAlien = HttpHit(0, 'no sid', {'error': 'no sid'});
  if (sidA != null) {
    getAlien = await c.settleGet(sidA, jwt: c.buyerJwt, extraQs: 'order_id=$oidB');
    postAlien = await c.settlePost(
      sidA,
      jwt: c.buyerJwt,
      body: {
        'checkout_return': 'success',
        'session_id': sidA,
        'order_id': oidB,
        'buyer_id': b1,
      },
    );
  }
  final ckAlien = await c.checkout(
    orderId: oidB,
    jwt: c.buyerJwt,
    buyer: b1,
    amount: 1,
    productId: pidB,
    extra: {
      if (sidA != null) 'session_id': sidA,
      if (sidA != null) 'checkout_session_id': sidA,
      'order_id': oidA,
    },
  );
  final rowA3a = await c.orderRow(oidA);
  final rowA3b = await c.orderRow(oidB);
  final a3Paid = c.orderPaid(rowA3a) || c.orderPaid(rowA3b);
  c.probe(
    id: 'A3',
    lens: 'EO1',
    edgeRpc: 'GET/POST settle session alheia + CPI inject sidA→oidB',
    payload: 'sidA (B2) com JWT B1 + order_id oidB; CPI oidB session_id=sidA',
    http:
        'GET ${getAlien.brief} | POST ${postAlien.brief} | CPI ${ckAlien.brief}',
    stripeBd:
        'A ${rowA3a?['status']} B ${rowA3b?['status']} sidB=${ckAlien.sessionId}',
    result: a3Paid ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a3Paid,
  );
  if (a3Paid) {
    c.hold(
      id: 'EO-P0-A3-SESSION-ALHEIA',
      lens: 'EO1',
      severity: 'P0',
      title: 'settle session alheia marcou pago noutra order/buyer',
      actor: 'B1 JWT',
      pre: 'Session metadata.order_id manda; buyer alheio não liquida',
      repro: 'GET/POST sidA JWT B1; CPI oidB com session_id=sidA',
      expected: '402/400; ambas reserva_pendente',
      obtained: {
        'A': rowA3a?['status'],
        'B': rowA3b?['status'],
        'get': getAlien.brief,
      },
    );
  } else {
    c.block('A3.session-alheia', 'EO1', 'sidA não paga oidB', {
      'A': rowA3a?['status'],
      'B': rowA3b?['status'],
    });
  }

  // A4 amount body/qs ≠ quote servidor
  final clientWon = ckA.ok && quoted != null && quoted <= 50;
  HttpHit getAmt = HttpHit(0, 'no sid', {'error': 'no sid'});
  if (sidA != null) {
    getAmt = await c.settleGet(sidA, extraQs: 'amount=1&amount_total=1', jwt: c.buyer2Jwt);
  }
  final rowA4 = await c.orderRow(oidA);
  final a4Open = clientWon || c.orderPaid(rowA4);
  c.probe(
    id: 'A4',
    lens: 'EO1',
    edgeRpc: 'CPI amount body/qs ≠ quote servidor',
    payload: 'body amount=1 vs SKU 12€; GET settle &amount=1',
    http: 'ck ${ckA.brief} | GET ${getAmt.brief}',
    stripeBd:
        'quoted=$quoted stripe=${ckA.map?['amount_total']} status=${rowA4?['status']}',
    result: a4Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a4Open,
  );
  if (a4Open) {
    c.hold(
      id: 'EO-P0-A4-AMOUNT-CLIENT',
      lens: 'EO1',
      severity: 'P0',
      title: 'amount cliente venceu quote servidor',
      actor: 'B2 JWT',
      pre: 'server_amount_cents = SKU+taxas; cliente 1 ignorado',
      repro: 'POST CPI amount=1; GET settle &amount=1',
      expected: 'quoted≈1325; GET 402',
      obtained: {'quoted': quoted, 'ck': ckA.brief},
    );
  } else {
    c.block('A4.quote', 'EO1', 'servidor manda quoted=$quoted vs 1', quoted);
  }

  // A5 GET∥POST settle paralelo
  HttpHit gPar = HttpHit(0, 'no sid', {'error': 'no sid'});
  HttpHit pPar = HttpHit(0, 'no sid', {'error': 'no sid'});
  if (sidA != null) {
    final raced = await Future.wait([
      c.settleGet(sidA, jwt: c.buyer2Jwt),
      c.settlePost(sidA, jwt: c.buyer2Jwt, extraQs: 'checkout_return=success'),
    ]);
    gPar = raced[0];
    pPar = raced[1];
  }
  final rowA5 = await c.orderRow(oidA);
  final a5Paid = c.orderPaid(rowA5) || looksPaidCopy(gPar) || looksPaidCopy(pPar);
  c.probe(
    id: 'A5',
    lens: 'EO7',
    edgeRpc: 'GET∥POST settle paralelo unpaid',
    payload: 'Future.wait GET sidA ∥ POST qs settle',
    http: 'GET ${gPar.brief} | POST ${pPar.brief}',
    stripeBd: '${rowA5?['status']}',
    result: a5Paid ? 'FAIL' : 'HOLD',
    classeNova: true,
    race: true,
    countFinding: a5Paid,
  );
  if (a5Paid) {
    c.hold(
      id: 'EO-P0-A5-RACE-SETTLE',
      lens: 'EO7',
      severity: 'P0',
      title: 'GET∥POST settle unpaid creditou',
      actor: 'B2 JWT',
      pre: 'race unpaid = 402+400 sem crédito',
      repro: 'Future.wait GET∥POST settle',
      expected: '402+400 reserva_pendente',
      obtained: {'get': gPar.brief, 'post': pPar.brief, 'st': rowA5?['status']},
    );
  } else {
    c.block('A5.race', 'EO7', 'GET∥POST unpaid sem crédito', {
      'get': gPar.status,
      'post': pPar.status,
    });
  }

  // A6 reuse Session após cancel path + PUT settle
  HttpHit cancel = HttpHit(0, 'no sid', {'error': 'no sid'});
  HttpHit reuse = HttpHit(0, 'no oid', {'error': 'no oid'});
  HttpHit putSet = HttpHit(0, 'no sid', {'error': 'no sid'});
  if (sidA != null) {
    cancel = await c.edge(
      'create-payment-intent',
      method: 'GET',
      jwt: c.buyer2Jwt,
      qs: 'checkout_return=cancel&session_id=$sidA',
    );
    reuse = await c.checkout(
      orderId: oidA,
      jwt: c.buyer2Jwt,
      buyer: b2,
      amount: 1,
      productId: pidA,
    );
    putSet = await c.settlePost(
      sidA,
      method: 'PUT',
      jwt: c.buyer2Jwt,
      extraQs: 'amount=1',
      body: {
        'checkout_return': 'success',
        'session_id': sidA,
        'metadata': {'order_id': oidB, 'paid': 'true'},
      },
    );
  }
  final reuseSame = reuse.sessionId != null &&
      sidA != null &&
      reuse.sessionId == sidA;
  final rowA6 = await c.orderRow(oidA);
  final a6Paid = c.orderPaid(rowA6) || looksPaidCopy(cancel) || looksPaidCopy(putSet);
  c.probe(
    id: 'A6',
    lens: 'EO1',
    edgeRpc: 'GET cancel + POST reuse + PUT settle metadata',
    payload: 'GET checkout_return=cancel; 2.º POST mesma order; PUT settle',
    http:
        'cancel ${cancel.brief} | reuse ${reuse.brief} | PUT ${putSet.brief}',
    stripeBd:
        'sameSid=$reuseSame A=${rowA6?['status']} reuseSid=${reuse.sessionId}',
    result: a6Paid ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a6Paid,
  );
  if (a6Paid) {
    c.hold(
      id: 'EO-P0-A6-CANCEL-REUSE',
      lens: 'EO1',
      severity: 'P0',
      title: 'cancel/reuse/PUT settle liquidou unpaid',
      actor: 'B2 JWT',
      pre: 'cancel 402; reuse mesmo cs_; PUT 400',
      repro: 'GET cancel; 2.º POST; PUT settle',
      expected: 'não pago',
      obtained: {'cancel': cancel.brief, 'put': putSet.brief, 'st': rowA6?['status']},
    );
  } else {
    c.block('A6.cancel-reuse', 'EO1', 'cancel/reuse/PUT sem liquidar', {
      'sameSid': reuseSame,
      'cancel': cancel.status,
      'put': putSet.status,
    });
  }

  // A7 fase2_e2e_settle JWT (deve deny service_role)
  final fase2 = await c.edge(
    'create-payment-intent',
    jwt: c.buyer2Jwt,
    qs: 'fase2_e2e_settle=1',
    body: {
      'session_id': sidA ?? 'cs_test_fase2_eo',
      'order_id': oidB,
      'payment_intent_id': 'pi_3UCkYUHOSTILEEO1952xxxx',
    },
  );
  final fase2Get = await c.edge(
    'create-payment-intent',
    method: 'GET',
    jwt: c.buyerJwt,
    qs: 'fase2_e2e_settle=1&session_id=${sidA ?? 'cs_test_x'}&order_id=$oidB',
  );
  final rowA7a = await c.orderRow(oidA);
  final rowA7b = await c.orderRow(oidB);
  final fase2Opened = fase2.ok ||
      fase2Get.ok ||
      (fase2.status != 401 && fase2.status != 403 && fase2.status != 400) ||
      c.orderPaid(rowA7a) ||
      c.orderPaid(rowA7b);
  // 401 service_role required = HOLD correcto
  final deniedOk = fase2.status == 401 || fase2.status == 403;
  c.probe(
    id: 'A7',
    lens: 'EO1',
    edgeRpc: 'fase2_e2e_settle JWT buyer POST+GET',
    payload: 'POST ?fase2_e2e_settle=1 JWT B2 PI alheio→oidB; GET JWT B1',
    http: 'POST ${fase2.brief} | GET ${fase2Get.brief}',
    stripeBd: 'A ${rowA7a?['status']} B ${rowA7b?['status']}',
    result: (!deniedOk && fase2Opened) ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: !deniedOk && fase2Opened,
  );
  if (!deniedOk && fase2Opened) {
    c.hold(
      id: 'EO-P0-A7-FASE2-JWT',
      lens: 'EO1',
      severity: 'P0',
      title: 'fase2_e2e_settle aceitou JWT comprador',
      actor: 'B2 JWT',
      pre: 'fase2 exige Bearer=service_role',
      repro: 'POST ?fase2_e2e_settle=1 JWT buyer',
      expected: '401 service_role required',
      obtained: fase2.brief,
    );
  } else {
    c.block('A7.fase2-jwt', 'EO1', 'fase2 JWT deny ${fase2.status}', fase2);
  }
}

Future<void> runTip(
  Rteo c,
  String s1,
  String s2,
  String b2,
  Map<String, Object?> caixa,
) async {
  await c.restoreSeller1Published();
  final live = await c.insertLive(seller: s1, title: '$prefix tip-hostil');
  if (live == null) {
    c.skip('B*', 'EO2', 'live fixture falhou', null);
    return;
  }

  // B1 amounts hostis
  final hostil = <String, String>{};
  for (final a in [0, -1, '1e6', '2,00', 0.5, 501, 'abc']) {
    final h = await c.tipCheckout(
      liveId: live,
      seller: s1,
      amountEur: a,
      jwt: c.buyer2Jwt,
    );
    hostil['amt:$a'] = h.brief;
  }
  final objAmt = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': live,
      'seller_id': s1,
      'amount_eur': {'cents': 200},
      'captured': true,
      'payment_status': 'paid',
    },
  );
  hostil['obj+captured'] = objAmt.brief;
  final tipIdHit = await c.tipCheckout(
    liveId: live,
    seller: s1,
    amountEur: 2,
    jwt: c.buyer2Jwt,
    extra: {'tip_id': '00000000-0000-4000-8000-00000000eo01'},
  );
  hostil['tip_id'] = tipIdHit.brief;
  final liveFake = await c.tipCheckout(
    liveId: '00000000-0000-4000-8000-00000000eo99',
    seller: s1,
    amountEur: 2,
    jwt: c.buyer2Jwt,
  );
  hostil['live_fake'] = liveFake.brief;
  final anyHostilOk = hostil.values.any((s) => s.startsWith('200')) ||
      tipIdHit.ok ||
      liveFake.ok ||
      objAmt.ok;
  c.probe(
    id: 'B1',
    lens: 'EO2',
    edgeRpc: 'create-live-tip-checkout amounts hostis + tip_id/live fake',
    payload:
        '0/−1/1e6/"2,00"/0.5/501/abc + amount object captured=true + tip_id + live fake',
    http: hostil,
    stripeBd: '0 Session hostil esperado',
    result: anyHostilOk ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: anyHostilOk,
  );
  if (anyHostilOk) {
    c.hold(
      id: 'EO-P0-B1-TIP-HOSTIL',
      lens: 'EO2',
      severity: 'P0',
      title: 'tip aceitou amount/tip_id/live/captured hostil',
      actor: 'B2 JWT',
      pre: 'amount 1–500 EUR; client tip_id forbidden',
      repro: 'POST tip amount hostil / tip_id / live fake / captured=true',
      expected: '400',
      obtained: hostil,
    );
  } else {
    c.block('B1.hostil', 'EO2', 'amounts/tip_id/live/captured 400', hostil);
  }

  // B2 RPC batata_settle_live_tip_from_stripe JWT
  final tipOk = await c.tipCheckout(
    liveId: live,
    seller: s1,
    amountEur: 2,
    jwt: c.buyer2Jwt,
  );
  final realTipId = tipOk.tipId;
  if (realTipId != null) c.createdTipIds.add(realTipId);
  caixa['tipSid'] = tipOk.sessionId;
  caixa['tipId'] = realTipId;
  final rpcFake = await c.rpc(
    'batata_settle_live_tip_from_stripe',
    {
      'p_tip_id': realTipId ?? '00000000-0000-4000-8000-00000000eo01',
      'p_stripe_session_id': tipOk.sessionId ?? 'cs_test_rteo_rpc',
      'p_paid_amount_cents': 99999,
    },
    jwt: c.buyer2Jwt,
  );
  final rpcSeller = await c.rpc(
    'batata_settle_live_tip_from_stripe',
    {
      'p_tip_id': realTipId ?? '00000000-0000-4000-8000-00000000eo01',
      'p_stripe_session_id': 'cs_test_rteo_seller',
    },
    jwt: c.sellerJwt,
  );
  final s0 = await c.walletBal(s1);
  final tipAfterRpc =
      realTipId == null ? null : await c.tipRow(realTipId);
  final s1b = await c.walletBal(s1);
  final rpcOpen = (rpcFake.ok && (rpcFake.json == true || rpcFake.map?['ok'] == true)) ||
      (rpcSeller.ok && (rpcSeller.json == true || rpcSeller.map?['ok'] == true)) ||
      '${tipAfterRpc?['status']}' == 'paid' ||
      (s1b - s0).abs() > 0.001;
  c.probe(
    id: 'B2',
    lens: 'EO2',
    edgeRpc: 'RPC batata_settle_live_tip_from_stripe JWT B2+S1',
    payload: 'p_tip_id real unpaid + paid_cents=99999 JWT buyer; seller JWT',
    http: 'B2 ${rpcFake.brief} | S1 ${rpcSeller.brief}',
    stripeBd:
        'tip ${tipAfterRpc?['status']} Δ=${s1b - s0} sid=${tipOk.sessionId}',
    result: rpcOpen ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: rpcOpen,
  );
  if (rpcOpen) {
    c.hold(
      id: 'EO-P0-B2-TIP-RPC',
      lens: 'EO2',
      severity: 'P0',
      title: 'JWT executou batata_settle_live_tip_from_stripe',
      actor: 'B2/S1 JWT',
      pre: 'RPC GRANT service_role',
      repro: 'POST rpc batata_settle_live_tip_from_stripe JWT',
      expected: '403 42501',
      obtained: {'b2': rpcFake.brief, 's1': rpcSeller.brief, 'Δ': s1b - s0},
    );
  } else {
    c.block('B2.rpc-jwt', 'EO2', 'RPC tip JWT 403', {
      'b2': rpcFake.status,
      's1': rpcSeller.status,
    });
  }

  // B3 tip∥end_live / unpublish
  final liveRace = await c.insertLive(seller: s1, title: '$prefix tip-race');
  HttpHit tipRace = HttpHit(0, 'no live', {'error': 'no live'});
  HttpHit endHit = HttpHit(0, 'no live', {'error': 'no live'});
  HttpHit unpub = HttpHit(0, 'no live', {'error': 'no live'});
  if (liveRace != null) {
    await c.restoreSeller1Published();
    final raced = await Future.wait([
      c.tipCheckout(
        liveId: liveRace,
        seller: s1,
        amountEur: 2,
        jwt: c.buyer2Jwt,
      ),
      c.rest('PATCH', 'lives?id=eq.$liveRace', jwt: c.buyer2Jwt, body: {
        'is_active': false,
        'status': 'ended',
      }),
      c.rest('PATCH', 'profiles?id=eq.$s1', jwt: c.buyer2Jwt, body: {
        'hub_published': false,
      }),
    ]);
    tipRace = raced[0];
    endHit = raced[1];
    unpub = raced[2];
    if (tipRace.tipId != null) c.createdTipIds.add(tipRace.tipId!);
  }
  await c.restoreSeller1Published();
  final tipRaceRow =
      tipRace.tipId == null ? null : await c.tipRow(tipRace.tipId!);
  final sRace = await c.walletBal(s1);
  final b3Credit = '${tipRaceRow?['status']}' == 'paid' ||
      looksPaidCopy(tipRace) && (sRace - s1b) > 0.001;
  c.probe(
    id: 'B3',
    lens: 'EO7',
    edgeRpc: 'tip POST ∥ PATCH lives ended ∥ hub unpublish JWT buyer',
    payload: 'Future.wait tip Session ∥ end_live JWT ∥ unpublish JWT',
    http: 'tip ${tipRace.brief} | end ${endHit.brief} | unpub ${unpub.brief}',
    stripeBd: 'tip ${tipRaceRow?['status']} pending esperado; Δwallet vs B2',
    result: b3Credit ? 'FAIL' : 'HOLD',
    classeNova: true,
    race: true,
    countFinding: b3Credit,
  );
  if (b3Credit) {
    c.hold(
      id: 'EO-P0-B3-TIP-END',
      lens: 'EO7',
      severity: 'P0',
      title: 'tip∥end_live creditou unpaid',
      actor: 'B2 JWT',
      pre: 'Session unpaid pending; PATCH lives JWT buyer 403',
      repro: 'Future.wait tip∥end∥unpublish',
      expected: 'tip pending Δ=0',
      obtained: tipRaceRow,
    );
  } else {
    c.block('B3.race-end', 'EO7', 'tip∥end pending Δ=0', {
      'tip': tipRaceRow?['status'],
      'end': endHit.status,
      'unpub': unpub.status,
    });
  }

  // B4 tip∥CPI bag mesmo buyer
  final pidBag = await c.createProduct(
    seller: s1,
    title: '$prefix bag-b4',
    qty: 2,
    price: 12,
  );
  HttpHit tipBag = HttpHit(0, 'no', {'error': 'no'});
  HttpHit bag = HttpHit(0, 'no', {'error': 'no'});
  if (pidBag != null && liveRace != null) {
    final raced = await Future.wait([
      c.tipCheckout(
        liveId: liveRace,
        seller: s1,
        amountEur: 2,
        jwt: c.buyer2Jwt,
      ),
      c.bagCheckout(
        lines: [
          {
            'product_id': pidBag,
            'qty': 1,
            'line_total_cents': 1,
          }
        ],
        jwt: c.buyer2Jwt,
        buyer: b2,
        amount: 1,
      ),
    ]);
    tipBag = raced[0];
    bag = raced[1];
    if (tipBag.tipId != null) c.createdTipIds.add(tipBag.tipId!);
  }
  final tipBagRow = tipBag.tipId == null ? null : await c.tipRow(tipBag.tipId!);
  final sBag = await c.walletBal(s1);
  final b4Credit = '${tipBagRow?['status']}' == 'paid' || (sBag - sRace) > 0.001;
  c.probe(
    id: 'B4',
    lens: 'EO7',
    edgeRpc: 'tip POST ∥ CPI bag mesmo buyer',
    payload: 'Future.wait tip Session ∥ bag_checkout amount=1 B2',
    http: 'tip ${tipBag.brief} | bag ${bag.brief}',
    stripeBd:
        'tip ${tipBagRow?['status']} bagSid=${bag.sessionId} quoted=${bag.map?['server_amount_cents']}',
    result: b4Credit ? 'FAIL' : 'HOLD',
    classeNova: true,
    race: true,
    countFinding: b4Credit,
  );
  if (b4Credit) {
    c.hold(
      id: 'EO-P0-B4-TIP-BAG',
      lens: 'EO7',
      severity: 'P0',
      title: 'tip∥CPI bag creditou',
      actor: 'B2 JWT',
      pre: 'ambos unpaid; Δwallet=0',
      repro: 'Future.wait tip∥bag mesmo buyer',
      expected: 'pending + reserva_pendente Δ=0',
      obtained: {'tip': tipBagRow, 'bag': bag.brief},
    );
  } else {
    c.block('B4.tip-bag', 'EO7', 'tip∥bag unpaid Δ=0', {
      'tip': tipBagRow?['status'],
      'bag': bag.status,
    });
  }

  // B5 tip unpaid GET settle Δwallet=0
  final sBefore = await c.walletBal(s1);
  HttpHit getTip = HttpHit(0, 'no sid', {'error': 'no sid'});
  final b5Sid = (caixa['tipSid'] ?? tipOk.sessionId)?.toString();
  final b5TipId = (caixa['tipId'] ?? realTipId)?.toString();
  if (b5Sid != null) {
    getTip = await c.tipSettleGet(b5Sid, jwt: c.buyer2Jwt);
  }
  final tipB5 = b5TipId == null ? null : await c.tipRow(b5TipId);
  final sAfter = await c.walletBal(s1);
  final dTip = sAfter - sBefore;
  final b5Paid = '${tipB5?['status']}' == 'paid' || dTip > 0.001;
  caixa['tipUnpaidStatus'] = tipB5?['status'];
  caixa['tipGet'] = getTip.brief;
  c.probe(
    id: 'B5',
    lens: 'EO2',
    edgeRpc: 'tip unpaid GET settle Δwallet',
    payload: 'GET checkout_return=success sid tip unpaid',
    http: getTip.brief,
    stripeBd: 'tip ${tipB5?['status']} Δ=$dTip sid=$b5Sid',
    result: b5Paid ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: b5Paid,
  );
  if (b5Paid) {
    c.hold(
      id: 'EO-P0-B5-TIP-UNPAID',
      lens: 'EO2',
      severity: 'P0',
      title: 'GET settle tip unpaid creditou wallet',
      actor: 'B2 JWT',
      pre: 'Session unpaid nunca credita',
      repro: 'GET create-live-tip-checkout checkout_return=success unpaid',
      expected: 'pending Δ=0',
      obtained: {'tip': tipB5, 'Δ': dTip, 'get': getTip.brief},
    );
  } else {
    c.block('B5.unpaid-get', 'EO2', 'GET tip unpaid Δ=0 pending', {
      'status': tipB5?['status'],
      'Δ': dTip,
      'get': getTip.status,
    });
  }

  // B6 tip seller≠owner (1 residual clássico)
  final liveS2 = await c.insertLive(seller: s2, title: '$prefix tip-s2');
  HttpHit own1 = HttpHit(0, 'no', {'error': 'no'});
  HttpHit own2 = HttpHit(0, 'no', {'error': 'no'});
  if (liveS2 != null) {
    own1 = await c.tipCheckout(
      liveId: live,
      seller: s2,
      amountEur: 2,
      jwt: c.buyer2Jwt,
    );
    own2 = await c.tipCheckout(
      liveId: liveS2,
      seller: s1,
      amountEur: 2,
      jwt: c.buyer2Jwt,
    );
  }
  final b6Ok = own1.ok || own2.ok;
  c.probe(
    id: 'B6',
    lens: 'EO2',
    edgeRpc: 'tip POST seller≠owner',
    payload: 'S2 na live S1; S1 na live S2',
    http: 'S2@S1 ${own1.brief} | S1@S2 ${own2.brief}',
    stripeBd: '—',
    result: b6Ok ? 'FAIL' : 'HOLD',
    classeNova: false,
    countFinding: b6Ok,
  );
  if (b6Ok) {
    c.hold(
      id: 'EO-P0-B6-TIP-OWNER',
      lens: 'EO2',
      severity: 'P0',
      title: 'tip seller≠owner criou Session',
      actor: 'B2 JWT',
      pre: '400 Tip seller does not own this live',
      repro: 'POST tip seller_id ≠ lives.seller_id',
      expected: '400',
      obtained: {'a': own1.brief, 'b': own2.brief},
    );
  } else {
    c.block('B6.owner-residual', 'EO2', 'seller≠owner 400 residual', {
      'a': own1.status,
      'b': own2.status,
    });
  }
}

Future<void> runWebhookCorsRefund(
  Rteo c,
  String s1,
  String s2,
  String b1,
  Map<String, Object?> caixa,
) async {
  // C1 webhook sem sig + sig morta + replay 2× + event swap livemode
  final bodyPaid = {
    'id': 'evt_rteo_1952_replay',
    'object': 'event',
    'type': 'checkout.session.completed',
    'livemode': true,
    'data': {
      'object': {
        'id': 'cs_test_rteo_replay',
        'object': 'checkout.session',
        'payment_status': 'paid',
        'amount_total': 1325,
        'metadata': {'order_id': caixa['oidA'] ?? 'x'},
      }
    }
  };
  final noSig = await c.stripeWebhookForge(bodyPaid);
  final dead =
      't=${DateTime.now().millisecondsSinceEpoch ~/ 1000},v1=deadbeefdeadbeef';
  final r1 = await c.stripeWebhookForge(bodyPaid, signature: dead);
  final r2 = await c.stripeWebhookForge(bodyPaid, signature: dead);
  final piSwap = await c.stripeWebhookForge({
    'id': 'evt_rteo_1952_pi',
    'object': 'event',
    'type': 'payment_intent.succeeded',
    'livemode': true,
    'data': {
      'object': {
        'id': 'pi_3UCkYUHOSTILEEO1952xxxx',
        'object': 'payment_intent',
        'amount': 99999,
        'status': 'succeeded',
        'metadata': {'order_id': caixa['oidA'] ?? 'x'},
      }
    }
  }, signature: dead);
  final whGet = await c.edge('stripe-webhook', method: 'GET', auth: true);
  final replayOk = noSig.ok || r1.ok || r2.ok || piSwap.ok;
  c.probe(
    id: 'C1',
    lens: 'EO3',
    edgeRpc: 'stripe-webhook sem sig + sig morta replay 2× + PI swap livemode',
    payload:
        'checkout.session.completed paid livemode=true; 2× same body v1=deadbeef; payment_intent.succeeded',
    http:
        'nosig ${noSig.brief} | r1 ${r1.brief} | r2 ${r2.brief} | pi ${piSwap.brief} | GET ${whGet.brief}',
    stripeBd: '—',
    result: replayOk ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: replayOk,
  );
  if (replayOk) {
    c.hold(
      id: 'EO-P0-C1-WEBHOOK',
      lens: 'EO3',
      severity: 'P0',
      title: 'webhook aceitou forge/replay/event swap',
      actor: 'anon POST',
      pre: 'constructEventAsync exige whsec',
      repro: 'POST stripe-webhook 2× mesmo body + sig morta',
      expected: '400 missing/invalid_signature',
      obtained: {
        'nosig': noSig.brief,
        'r1': r1.brief,
        'r2': r2.brief,
        'pi': piSwap.brief,
      },
    );
  } else {
    c.block('C1.webhook', 'EO3', 'forge+replay+swap 400', {
      'nosig': noSig.status,
      'r1': r1.status,
      'r2': r2.status,
      'pi': piSwap.status,
      'get': whGet.status,
    });
  }

  // C2 CORS Origin null / evil / chrome-extension
  const evil = 'https://evil.com';
  const ext = 'chrome-extension://abcdef123456';
  const originNull = 'null';
  final corsHits = <String, HttpHit>{
    'opt_null_cpi': await c.edge(
      'create-payment-intent',
      method: 'OPTIONS',
      extra: {'Origin': originNull},
    ),
    'opt_evil_cpi': await c.edge(
      'create-payment-intent',
      method: 'OPTIONS',
      extra: {'Origin': evil},
    ),
    'opt_ext_cpi': await c.edge(
      'create-payment-intent',
      method: 'OPTIONS',
      extra: {'Origin': ext},
    ),
    'opt_null_tip': await c.edge(
      'create-live-tip-checkout',
      method: 'OPTIONS',
      extra: {'Origin': originNull},
    ),
    'opt_evil_refund': await c.edge(
      'refund-order',
      method: 'OPTIONS',
      extra: {'Origin': evil},
    ),
    'opt_ext_refund': await c.edge(
      'refund-order',
      method: 'OPTIONS',
      extra: {'Origin': ext},
    ),
    'opt_null_wh': await c.edge(
      'stripe-webhook',
      method: 'OPTIONS',
      extra: {'Origin': originNull},
    ),
    'opt_evil_wh': await c.edge(
      'stripe-webhook',
      method: 'OPTIONS',
      extra: {'Origin': evil},
    ),
    'post_evil_cpi': await c.edge(
      'create-payment-intent',
      extra: {'Origin': evil},
      body: {'order_id': 'x'},
      jwt: c.buyerJwt,
    ),
  };
  final echoes = <String>[];
  for (final e in corsHits.entries) {
    final origin = e.key.contains('null')
        ? originNull
        : e.key.contains('ext')
            ? ext
            : evil;
    if (corsEchoes(e.value, origin)) echoes.add('${e.key}=${e.value.acao}');
  }
  c.probe(
    id: 'C2',
    lens: 'EO4',
    edgeRpc: 'CORS Origin null / evil / chrome-extension CPI/tip/refund/webhook',
    payload: 'OPTIONS+POST Origin=null|https://evil.com|chrome-extension://',
    http: corsHits.map((k, v) => MapEntry(k, v.brief)),
    stripeBd: 'echoes=$echoes',
    result: echoes.isNotEmpty ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: echoes.isNotEmpty,
  );
  if (echoes.isNotEmpty) {
    c.hold(
      id: 'EO-P2-C2-CORS-ECHO',
      lens: 'EO4',
      severity: 'P2',
      title: 'CORS ecoa Origin hostil',
      actor: 'browser Origin',
      pre: 'allowlist fleaber.pt; não ecoar null/evil/ext',
      repro: 'OPTIONS Origin=null|evil.com|chrome-extension://',
      expected: 'ACAO ≠ origin hostil',
      obtained: echoes,
    );
  } else {
    c.block('C2.cors', 'EO4', 'não ecoa null/evil/ext', {
      for (final e in corsHits.entries) e.key: e.value.acao,
    });
  }

  // C3 buyer refund 403 + seller refund 3×
  final payC3 = await mustPay(c, 'EO5');
  caixa['piC3'] = payC3.pi;
  caixa['oidC3'] = payC3.oid;
  final sC3a = await c.walletBal(s1);
  final buyerRef = await c.refundOrder(payC3.oid, jwt: c.buyerJwt);
  final sel1 = await c.refundOrder(payC3.oid, jwt: c.sellerJwt);
  final sel2 = await c.refundOrder(payC3.oid, jwt: c.sellerJwt);
  final sel3 = await c.refundOrder(payC3.oid, jwt: c.sellerJwt);
  final sC3b = await c.walletBal(s1);
  final rowC3 = await c.orderRow(payC3.oid);
  final reIds = {
    sel1.map?['refundId'] ?? sel1.map?['refund_id'],
    sel2.map?['refundId'] ?? sel2.map?['refund_id'],
    sel3.map?['refundId'] ?? sel3.map?['refund_id'],
    rowC3?['stripe_refund_id'],
  }.where((e) => '$e'.startsWith('re_')).map((e) => '$e').toSet();
  final buyerOk = buyerRef.status == 200;
  final doubleRe = reIds.length > 1;
  caixa['reC3'] = reIds.toList();
  c.probe(
    id: 'C3',
    lens: 'EO5',
    edgeRpc: 'refund-order buyer 403 + seller ×3 idempotency',
    payload: 'JWT comprador; seller 3× oid ${payC3.oid} PI ${payC3.pi}',
    http:
        'buyer ${buyerRef.brief} | s1 ${sel1.brief} | s2 ${sel2.brief} | s3 ${sel3.brief}',
    stripeBd: 're_ n=${reIds.length} $reIds Δ=${sC3b - sC3a} st=${rowC3?['status']}',
    result: (buyerOk || doubleRe) ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: buyerOk || doubleRe,
  );
  if (buyerOk || doubleRe) {
    c.hold(
      id: buyerOk ? 'EO-P0-C3-BUYER-REFUND' : 'EO-P0-C3-REFUND-DUP',
      lens: 'EO5',
      severity: 'P0',
      title: buyerOk
          ? 'Buyer refund-order aberto'
          : 'seller refund 3× criou >1 re_',
      actor: buyerOk ? 'buyer JWT' : 'seller JWT',
      pre: 'seller-only; idempotency fleaber_order_refund_{oid}',
      repro: 'POST refund-order buyer; seller 3×',
      expected: 'buyer 403; 1 re_',
      obtained: {
        'buyer': buyerRef.brief,
        're': reIds.toList(),
      },
    );
  } else {
    c.block('C3.refund-3x', 'EO5', 'buyer 403 + 1 re_ em 3×', {
      'buyer': buyerRef.status,
      'n_re': reIds.length,
    });
  }

  // C4 refund∥release
  final payC4 = await mustPay(c, 'EO7');
  caixa['piC4'] = payC4.pi;
  caixa['oidC4'] = payC4.oid;
  final sC4a = await c.walletBal(s1);
  final racedC4 = await Future.wait([
    c.refundOrder(payC4.oid, jwt: c.sellerJwt),
    c.tryRelease(payC4.oid, jwt: c.buyerJwt),
    c.tryRelease(payC4.oid, jwt: c.sellerJwt),
  ]);
  final sC4b = await c.walletBal(s1);
  final rowC4 = await c.orderRow(payC4.oid);
  final orC4 = await c.oracleWalletDispute(payC4.oid, s1);
  final c4Net = (sC4b - sC4a) > 0.01 || (orC4['net'] as num) > 0.01;
  caixa['reC4'] = racedC4[0].map?['refundId'] ?? rowC4?['stripe_refund_id'];
  c.probe(
    id: 'C4',
    lens: 'EO7',
    edgeRpc: 'refund-order ∥ release buyer/seller',
    payload: 'Future.wait seller refund + release B + release S oid ${payC4.oid}',
    http:
        'ref ${racedC4[0].brief} | relB ${racedC4[1].brief} | relS ${racedC4[2].brief}',
    stripeBd: 'Δ=${sC4b - sC4a} net=${orC4['net']} re=${caixa['reC4']} st=${rowC4?['status']}',
    result: c4Net ? 'FAIL' : 'HOLD',
    classeNova: true,
    race: true,
    countFinding: c4Net,
  );
  if (c4Net) {
    c.hold(
      id: 'EO-P0-C4-REFUND-RELEASE',
      lens: 'EO7',
      severity: 'P0',
      title: 'refund∥release criou crédito líquido',
      actor: 'seller+buyer JWT',
      pre: 'refund anula; release false; Δ=0',
      repro: 'Future.wait refund∥release',
      expected: 'Δwallet=0',
      obtained: orC4,
    );
  } else {
    c.block('C4.race', 'EO7', 'refund∥release Δ=0', orC4);
  }

  // C5 refund amount > captura (body extra; API pode ignorar)
  final c5amt = await c.refundOrder(
    payC4.oid,
    jwt: c.sellerJwt,
    extra: {
      'amount': 999999,
      'amount_cents': 999999,
      'refund_amount': 9999.99,
    },
  );
  final rowC5 = await c.orderRow(payC4.oid);
  final overCap = c5amt.ok &&
      (numOf(c5amt.map?['amount_cents']) ?? 0) > 590;
  c.probe(
    id: 'C5',
    lens: 'EO5',
    edgeRpc: 'refund-order amount body > captura',
    payload: 'amount=999999 amount_cents=999999 na order já refundida ${payC4.oid}',
    http: c5amt.brief,
    stripeBd: 'refund_id=${rowC5?['stripe_refund_id']} amount_paid=${rowC5?['amount_paid_cents']}',
    result: overCap ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: overCap,
  );
  if (overCap) {
    c.hold(
      id: 'EO-P0-C5-REFUND-OVER',
      lens: 'EO5',
      severity: 'P0',
      title: 'refund amount cliente > captura',
      actor: 'seller JWT',
      pre: 'amount do body ignorado; servidor usa amount_paid_cents ≤ residual',
      repro: 'POST refund-order amount=999999',
      expected: 'ignore / already_refunded; nunca > captura',
      obtained: c5amt.brief,
    );
  } else {
    c.block('C5.amount-body', 'EO5', 'amount cliente ignorado / already_refunded',
        c5amt);
  }

  // C6 refund order alheia seller2
  final payC6 = await mustPay(c, 'EO5');
  caixa['piC6'] = payC6.pi;
  caixa['oidC6'] = payC6.oid;
  final s2ref = await c.refundOrder(payC6.oid, jwt: c.seller2Jwt);
  final rowC6 = await c.orderRow(payC6.oid);
  final s2ok = s2ref.status == 200 &&
      '${rowC6?['stripe_refund_id'] ?? ''}'.startsWith('re_');
  c.probe(
    id: 'C6',
    lens: 'EO5',
    edgeRpc: 'refund-order seller2 order alheia S1',
    payload: 'JWT S2 oid ${payC6.oid} (seller S1) PI ${payC6.pi}',
    http: s2ref.brief,
    stripeBd: 'st=${rowC6?['status']} refund=${rowC6?['stripe_refund_id']}',
    result: s2ok ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: s2ok,
  );
  if (s2ok) {
    c.hold(
      id: 'EO-P0-C6-REFUND-ALIEN',
      lens: 'EO5',
      severity: 'P0',
      title: 'seller2 reembolsou order alheia',
      actor: 'S2 JWT',
      pre: 'só seller da order',
      repro: 'POST refund-order JWT seller2 oid S1',
      expected: '403',
      obtained: s2ref.brief,
    );
  } else {
    c.block('C6.seller2', 'EO5', 'S2 refund alheia denied', s2ref);
  }

  // C7 refund após enviado / concluido
  final payC7e = await mustPay(c, 'EO5');
  await c.markEnviado(payC7e.oid);
  final refEnv = await c.refundOrder(payC7e.oid, jwt: c.sellerJwt);
  final rowEnv = await c.orderRow(payC7e.oid);
  final payC7c = await mustPay(c, 'EO5');
  await c.markConcluidoMao(payC7c.oid);
  final refConc = await c.refundOrder(payC7c.oid, jwt: c.sellerJwt);
  final rowConc = await c.orderRow(payC7c.oid);
  caixa['oidC7e'] = payC7e.oid;
  caixa['oidC7c'] = payC7c.oid;
  caixa['piC7e'] = payC7e.pi;
  caixa['piC7c'] = payC7c.pi;
  final c7Open = (refEnv.status == 200 &&
          '${rowEnv?['stripe_refund_id'] ?? ''}'.startsWith('re_')) ||
      (refConc.status == 200 &&
          '${rowConc?['stripe_refund_id'] ?? ''}'.startsWith('re_'));
  c.probe(
    id: 'C7',
    lens: 'EO5',
    edgeRpc: 'refund-order após enviado + concluido',
    payload: 'oid enviado ${payC7e.oid}; oid concluido ${payC7c.oid}',
    http: 'env ${refEnv.brief} | conc ${refConc.brief}',
    stripeBd:
        'env st=${rowEnv?['status']} re=${rowEnv?['stripe_refund_id']} | conc st=${rowConc?['status']} re=${rowConc?['stripe_refund_id']}',
    result: c7Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: c7Open,
  );
  if (c7Open) {
    c.hold(
      id: 'EO-P0-C7-REFUND-SHIPPED',
      lens: 'EO5',
      severity: 'P0',
      title: 'refund após enviado/concluido anulou Stripe',
      actor: 'seller JWT',
      pre: 'order_refund_blocked_shipped',
      repro: 'PATCH enviado/concluido; POST refund-order',
      expected: '403 janela fechada',
      obtained: {'env': refEnv.brief, 'conc': refConc.brief},
    );
  } else {
    c.block('C7.window', 'EO5', 'refund enviado/concluido 403', {
      'env': refEnv.status,
      'conc': refConc.status,
    });
  }
}

Future<void> runPayoutWallet(
  Rteo c,
  String s1,
  String s2,
  String b1,
  Map<String, Object?> caixa,
) async {
  final fakeOid = '00000000-0000-0000-0000-00000000eo01';
  final a0s = await c.walletBal(s1);

  // D1 JWT insert txn / PATCH balance / dest Connect
  final ins = await c.rest(
    'POST',
    'wallet_transactions',
    jwt: c.buyerJwt,
    prefer: 'return=representation',
    body: {
      'wallet_id': s1,
      'amount': 7777.77,
      'type': 'venda',
      'description': '$prefix jwt-insert',
      'order_id': fakeOid,
    },
  );
  final patchBal = await c.rest(
    'PATCH',
    'wallets?id=eq.$s1',
    jwt: c.buyerJwt,
    body: {'balance': 99999, 'available_balance': 99999},
  );
  final alien = await c.otherConnectAccounts(s1);
  final alienAcct = alien.isEmpty
      ? 'acct_1UChokHOSTILEEO'
      : '${alien.first['stripe_account_id']}';
  final ownBefore = '${(await c.walletRow(s1))?['stripe_account_id'] ?? ''}';
  final patchDest = await c.rest(
    'PATCH',
    'wallets?or=(id.eq.$s1)',
    jwt: c.buyerJwt,
    body: {'stripe_account_id': alienAcct},
  );
  final a1s = await c.walletBal(s1);
  final ownAfter = '${(await c.walletRow(s1))?['stripe_account_id'] ?? ''}';
  final d1Open = minted(ins, a1s - a0s) ||
      (a1s - a0s).abs() > 0.001 ||
      (ownAfter.isNotEmpty && ownAfter != ownBefore && ownAfter == alienAcct);
  c.probe(
    id: 'D1',
    lens: 'EO6',
    edgeRpc: 'JWT INSERT txn + PATCH balance + PATCH dest Connect',
    payload: 'amount=7777.77 oid fake; balance=99999; dest $alienAcct',
    http: 'ins ${ins.brief} | bal ${patchBal.brief} | dest ${patchDest.brief}',
    stripeBd: 'Δ=${a1s - a0s} acct $ownBefore→$ownAfter',
    result: d1Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: d1Open,
  );
  if (d1Open) {
    c.hold(
      id: 'EO-P0-D1-JWT-MINT',
      lens: 'EO6',
      severity: 'P0',
      title: 'JWT mint txn/balance/dest Connect',
      actor: 'buyer JWT',
      pre: 'RLS bloqueia INSERT/PATCH wallets',
      repro: 'POST wallet_transactions; PATCH wallets balance/dest',
      expected: '403/400; Δ=0; acct próprio',
      obtained: {
        'ins': ins.brief,
        'Δ': a1s - a0s,
        'acct': ownAfter,
      },
    );
  } else {
    c.block('D1.jwt-forge', 'EO6', 'JWT insert/patch Δ=0 acct próprio', {
      'ins': ins.status,
      'bal': patchBal.status,
      'dest': patchDest.status,
      'acct': ownAfter,
    });
  }

  // D2 payout overbalance + dest alheio
  await c.ensureWalletBalance(s1, 5);
  final over = await c.connect({
    'amount': 99999999,
    'idempotency_key': 'rteoOverbal1952keyxx',
  }, jwt: c.sellerJwt);
  final destAlien = await c.connect({
    'amount': 100,
    'idempotency_key': 'rteoDestAlien1952key',
    'user_id': s2,
    'destination': alienAcct,
  }, jwt: c.sellerJwt);
  final d2Mint = over.payoutOk || destAlien.payoutOk;
  c.probe(
    id: 'D2',
    lens: 'EO6',
    edgeRpc: 'create-connect-account overbalance + dest/user_id alheio',
    payload: 'amount=99999999; user_id=S2 destination=$alienAcct amount=100',
    http: 'over ${over.brief} | dest ${destAlien.brief}',
    stripeBd: 'transfer over=${over.transferId} dest=${destAlien.transferId}',
    result: d2Mint ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: d2Mint,
  );
  if (d2Mint) {
    c.hold(
      id: 'EO-P0-D2-PAYOUT-HOSTIL',
      lens: 'EO6',
      severity: 'P0',
      title: 'payout overbalance ou dest alheio criou Transfer',
      actor: 'seller JWT',
      pre: 'insufficient_balance; Cannot create another user Stripe account',
      repro: 'POST connect amount huge; user_id S2',
      expected: '400',
      obtained: {'over': over.brief, 'dest': destAlien.brief},
    );
  } else {
    c.block('D2.over-dest', 'EO6', 'over/dest alheio 400', {
      'over': over.status,
      'dest': destAlien.status,
    });
  }

  // D3 payout∥payout mesma key + keys diferentes
  await c.ensureWalletBalance(s1, 8);
  final trBefore = await c.transferIds(s1);
  const sameKey = 'rteoParallelSame1952k';
  final raced = await Future.wait([
    c.connect({'amount': 100, 'idempotency_key': sameKey}, jwt: c.sellerJwt),
    c.connect(
      {'amount': 100, 'idempotency_key': sameKey},
      jwt: c.sellerJwt,
      extra: {'Idempotency-Key': 'rteoHeaderOther1952k'},
    ),
  ]);
  final otherKey = await c.connect({
    'amount': 100,
    'idempotency_key': 'rteoOtherKey1952xxxx',
  }, jwt: c.sellerJwt);
  final trAfter = await c.transferIds(s1);
  final newTr = trAfter.difference(trBefore);
  final sameKeyIds = {
    raced[0].transferId,
    raced[1].transferId,
  }.where((e) => '$e'.startsWith('tr_')).map((e) => '$e').toSet();
  caixa['transfers'] = newTr.toList();
  caixa['trSameKey'] = sameKeyIds.toList();
  caixa['trBeforeN'] = trBefore.length;
  caixa['trAfterN'] = trAfter.length;
  final d3Dup = sameKeyIds.length > 1;
  c.probe(
    id: 'D3',
    lens: 'EO7',
    edgeRpc: 'payout∥payout mesma key + header vs body + 2.ª key',
    payload: 'Future.wait amount=100 key=$sameKey vs Idempotency-Key header; depois outra key',
    http:
        'a ${raced[0].brief} | b ${raced[1].brief} | other ${otherKey.brief}',
    stripeBd: 'newTr=${newTr.toList()} n=${newTr.length}',
    result: d3Dup ? 'FAIL' : 'HOLD',
    classeNova: true,
    race: true,
    countFinding: d3Dup,
  );
  if (d3Dup) {
    c.hold(
      id: 'EO-P0-D3-PAYOUT-RACE',
      lens: 'EO7',
      severity: 'P0',
      title: 'payout paralelo criou >1 Transfer na mesma intenção',
      actor: 'seller JWT',
      pre: 'mesma idempotency_key = 1 tr_',
      repro: 'Future.wait mesma key body vs header',
      expected: '1 tr_ na mesma key',
      obtained: newTr.toList(),
    );
  } else {
    c.block('D3.payout-race', 'EO7', 'mesma key 1 tr_ (n=${newTr.length})', {
      'n': newTr.length,
      'ids': newTr.toList(),
      'a': raced[0].status,
      'b': raced[1].status,
    });
  }

  // D4 clawback/credit RPC JWT
  final credit = await c.req(
    'POST',
    '/rest/v1/rpc/batata_credit_wallet_once',
    jwt: c.buyerJwt,
    body: {
      'p_wallet_id': s1,
      'p_order_id': fakeOid,
      'p_amount': 50,
      'p_type': 'venda',
      'p_description': '$prefix credit jwt',
    },
  );
  final claw = await c.tryClawbackJwt(fakeOid, jwt: c.buyerJwt);
  final finish = await c.rpc('batata_wallet_payout_finish', {
    'p_user_id': s1,
    'p_idempotency_key': 'rteoFinishJwt1952xxxx',
    'p_stripe_transfer_id': 'tr_rteo_fake',
    'p_amount_cents': 9999,
  }, jwt: c.sellerJwt);
  final debit = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': s1,
    'p_amount_cents': 100,
    'p_idempotency_key': 'rteoDebitJwt1952keyxx',
  }, jwt: c.sellerJwt);
  final a4s = await c.walletBal(s1);
  final d4Open = minted(credit, 0) ||
      minted(claw, 0) ||
      minted(finish, 0) ||
      minted(debit, 0) ||
      (a4s - a1s).abs() > 5;
  c.probe(
    id: 'D4',
    lens: 'EO6',
    edgeRpc: 'RPC credit/clawback/payout_finish/debit JWT',
    payload: 'credit 50 fake oid; claw; finish tr_fake; debit 100¢ JWT',
    http:
        'credit ${credit.brief} | claw ${claw.brief} | finish ${finish.brief} | debit ${debit.brief}',
    stripeBd: 'Δ vs D1 ${a4s - a1s}',
    result: d4Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: d4Open,
  );
  if (d4Open) {
    c.hold(
      id: 'EO-P0-D4-RPC-JWT',
      lens: 'EO6',
      severity: 'P0',
      title: 'RPC credit/clawback/finish/debit JWT mintou',
      actor: 'buyer/seller JWT',
      pre: 'GRANT service_role',
      repro: 'POST rpc credit/claw/finish/debit JWT',
      expected: '403/404',
      obtained: {
        'credit': credit.brief,
        'claw': claw.brief,
        'finish': finish.brief,
        'debit': debit.brief,
      },
    );
  } else {
    c.block('D4.rpc-jwt', 'EO6', 'RPC JWT deny', {
      'credit': credit.status,
      'claw': claw.status,
      'finish': finish.status,
      'debit': debit.status,
    });
  }

  // D5 release∥disputa 0ms + 50ms
  final pay0 = await mustPay(c, 'EO7');
  await c.markConcluidoMao(pay0.oid);
  final s0d = await c.walletBal(s1);
  final r0 = await c.raceReleaseDispute(pay0.oid, delayMs: 0);
  final or0 = await c.oracleWalletDispute(pay0.oid, s1);
  final pay50 = await mustPay(c, 'EO7');
  await c.markConcluidoMao(pay50.oid);
  final r50 = await c.raceReleaseDispute(
    pay50.oid,
    delayMs: 50,
    disputeFirst: true,
  );
  final or50 = await c.oracleWalletDispute(pay50.oid, s1);
  caixa['oidD5_0'] = pay0.oid;
  caixa['oidD5_50'] = pay50.oid;
  caixa['piD5_0'] = pay0.pi;
  caixa['piD5_50'] = pay50.pi;
  final both0 = or0['both'] == true;
  final both50 = or50['both'] == true;
  c.probe(
    id: 'D5',
    lens: 'EO7',
    edgeRpc: 'release∥disputa 0ms + dispute-first 50ms',
    payload: 'oid0 ${pay0.oid} 0ms; oid50 ${pay50.oid} dispute-first 50ms',
    http: '0ms rel ${r0[0].brief} disp ${r0[1].brief} | 50ms ${r50[0].brief} ${r50[1].brief}',
    stripeBd: {
      '0ms': or0,
      '50ms': or50,
      'Δ0': (await c.walletBal(s1)) - s0d,
    },
    result: (both0 || both50) ? 'FAIL' : 'HOLD',
    classeNova: true,
    race: true,
    countFinding: both0 || both50,
  );
  if (both0 || both50) {
    c.hold(
      id: 'EO-P1-D5-RELEASE-DISPUTE',
      lens: 'EO7',
      severity: 'P1',
      title: 'release∥disputa crédito líquido + claim aberto',
      actor: 'buyer JWT',
      pre: 'net≤0 OU disputa inexistente (clawback / só disputa)',
      repro: 'Future.wait release∥disputa 0ms e 50ms dispute-first',
      expected: 'both=false',
      obtained: {'0ms': or0, '50ms': or50},
    );
  } else {
    c.block('D5.race-disp', 'EO7', '0ms+50ms both=false', {
      'net0': or0['net'],
      'open0': or0['open_n'],
      'net50': or50['net'],
      'open50': or50['open_n'],
    });
  }
}

Future<void> runCaixa(Rteo c, String s1, Map<String, Object?> caixa) async {
  final pis = [
    caixa['piC3'],
    caixa['piC4'],
    caixa['piC6'],
    caixa['piC7e'],
    caixa['piC7c'],
    caixa['piD5_0'],
    caixa['piD5_50'],
  ].where((e) => '$e'.startsWith('pi_')).map((e) => '$e').toSet();
  c.probe(
    id: 'E1',
    lens: 'EO8',
    edgeRpc: 'setup_paid_order 4242 distintos no fio',
    payload: 'C3/C4/C6/C7/D5 PI succeeded',
    http: 'n=${pis.length}',
    stripeBd: pis.toList(),
    result: pis.length >= 3 ? 'HOLD' : 'FAIL',
    classeNova: true,
    countFinding: pis.length < 3,
  );
  if (pis.length < 3) {
    c.hold(
      id: 'EO-P3-E1-CAIXA',
      lens: 'EO8',
      severity: 'P3',
      title: 'menos de 3 PI 4242 no fio',
      actor: 'e2e setup_paid_order',
      pre: '≥3 pagos TEST',
      repro: 'C3 C4 C6 C7 D5',
      expected: '≥3 pi_',
      obtained: pis.toList(),
    );
  } else {
    c.block('E1.caixa-pi', 'EO8', '${pis.length} PI 4242 no fio', pis.toList());
  }

  final tipSid = caixa['tipSid'];
  final tipSt = caixa['tipUnpaidStatus'];
  c.probe(
    id: 'E2',
    lens: 'EO8',
    edgeRpc: 'tip Session unpaid + GET settle path',
    payload: 'sid=$tipSid GET ${caixa['tipGet']}',
    http: '${caixa['tipGet']}',
    stripeBd: 'status=$tipSt',
    result: '$tipSt' == 'paid' ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: '$tipSt' == 'paid',
  );
  if ('$tipSt' == 'paid') {
    c.hold(
      id: 'EO-P0-E2-TIP-PAID',
      lens: 'EO8',
      severity: 'P0',
      title: 'tip Session unpaid ficou paid',
      actor: 'B2 JWT',
      pre: 'pending até captura Stripe',
      repro: 'POST tip + GET settle unpaid',
      expected: 'pending',
      obtained: tipSt,
    );
  } else {
    c.block('E2.tip-path', 'EO8', 'tip unpaid pending sid=$tipSid', tipSt);
  }

  final trs = (caixa['transfers'] is List)
      ? (caixa['transfers'] as List).map((e) => '$e').where((s) => s.startsWith('tr_')).toSet()
      : <String>{};
  final led = await c.payoutLedger(s1, limit: 12);
  final nTr = led
      .where((r) => '${r['stripe_transfer_id']}'.startsWith('tr_'))
      .map((r) => '${r['stripe_transfer_id']}')
      .toSet();
  // Esperado: ≤1 tr_ novo desta corrida na mesma key (D3); 2.ª key pode criar 2.º
  // Double = mesma key dois tr_ distintos — já FAIL em D3. E3 = count vs ledger.
  c.probe(
    id: 'E3',
    lens: 'EO8',
    edgeRpc: 'Transfer count vs ledger',
    payload: 'newTr D3=${trs.toList()} ledger recent n=${nTr.length}',
    http: 'n_new=${trs.length}',
    stripeBd: {
      'new': trs.toList(),
      'ledger_sample': led.take(4).toList(),
    },
    result: 'HOLD',
    classeNova: true,
    countFinding: false,
  );
  c.block('E3.transfer-count', 'EO8', 'ledger tr_ coerente n_new=${trs.length}', {
    'new': trs.toList(),
    'n_led': nTr.length,
  });
}
