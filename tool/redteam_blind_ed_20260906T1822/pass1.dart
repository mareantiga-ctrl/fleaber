/// RED TEAM CEGO ED — matriz A settle + B tip + C webhook/CORS/refund + D caixa.
/// Staging only. NÃO corrigir. NÃO produção. NÃO Fase 4.
/// DX saturado clássicos — ângulos novos: POST settle, Origin null, webhook replay,
/// bag line_total hostil, GET∥POST, tip∥CPI, fase2_e2e_settle JWT, RPC tip buyer.
import 'dart:io';
import '_rted.dart';

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

void main() async {
  final c = Rted.fromEnv(loadEnv());
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
    await runWebhookCorsRefund(c, s1, b1);
    await runCaixa(c, s1, b2);
  } finally {
    await c.endLives();
    await c.restoreSeller1Published();
    await c.setHub(s2, false);
  }

  await c.dumpAll('pass1.json');
  stdout.writeln(
    'ED DONE probes=${c.probes.length} findings=${c.findings.where((f) => f['count'] == true).length} '
    'lenses=${c.lensesHit.toList()..sort()} nova=${c.probes.where((p) => p['classe_nova'] == true).length} '
    'races=${c.probes.where((p) => p['race'] == true).length}',
  );
}

Future<void> runSettle(Rted c, String s1, String b1, String b2) async {
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
  final pidBag = await c.createProduct(
    seller: s1,
    title: '$prefix settle-bag',
    qty: 4,
    price: price,
  );
  if (pidA == null || pidB == null || pidBag == null) {
    c.skip('A*', 'ED1', 'SKU fixture falhou', {
      'a': pidA,
      'b': pidB,
      'bag': pidBag,
    });
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
  final oidBag = await c.insertOrder(
    productId: pidBag,
    buyer: b2,
    seller: s1,
    price: price,
  );
  if (oidA == null || oidB == null || oidBag == null) {
    c.skip('A*', 'ED1', 'order fixture falhou', {
      'a': oidA,
      'b': oidB,
      'bag': oidBag,
    });
    return;
  }

  // A3 bag line_total_cents hostil + currency usd vs quote servidor (classe_nova)
  final bagHit = await c.bagCheckout(
    lines: [
      {
        'order_id': oidBag,
        'product_id': pidBag,
        'seller_id': s1,
        'quantity': 99,
        'line_total_cents': 1,
      },
    ],
    jwt: c.buyer2Jwt,
    buyer: b2,
    amount: 1,
    currency: 'usd',
    extra: {
      'total': 50,
      'server_amount_cents': '50',
      'item_price': 0.01,
    },
  );
  final bagQuoted = numOf(bagHit.map?['server_amount_cents'])?.round();
  final bagStripe = numOf(bagHit.map?['amount_total'])?.round();
  final bagClientWon = bagHit.ok &&
      ((bagQuoted != null && bagQuoted <= 50) ||
          (bagStripe != null && bagStripe <= 50));
  final bagUsd = '${bagHit.map?['currency'] ?? bagHit.body}'.toLowerCase().contains('usd') &&
      bagHit.ok &&
      (bagQuoted == 1 || bagStripe == 1);
  c.probe(
    id: 'A3',
    edgeRpc: 'create-payment-intent POST bag_checkout',
    payload:
        'B2 bag line_total_cents=1 qty=99 currency=usd amount=1 vs SKU 12,00€',
    http: bagHit,
    stripeBd: {
      'sid': bagHit.sessionId,
      'server_amount_cents': bagQuoted,
      'amount_total': bagStripe,
      'price_total': (await c.orderRow(oidBag))?['price_total'],
    },
    result: !bagHit.ok && bagHit.status >= 400
        ? 'HOLD'
        : ((bagClientWon || bagUsd) ? 'FAIL' : 'HOLD'),
    lens: 'ED1',
    countFinding: bagClientWon || bagUsd,
    classeNova: true,
  );
  if (bagClientWon || bagUsd) {
    c.hold(
      id: 'ED-P0-A3-BAG-CLIENT-AMOUNT',
      lens: 'ED1',
      severity: 'P0',
      title: 'bag_checkout usou line_total_cents/currency do cliente',
      actor: 'B2 JWT',
      pre: 'SKU 12,00€; line_total_cents=1; currency=usd',
      repro: 'POST create-payment-intent bag_checkout line_total_cents=1',
      expected: 'quote servidor ≥1200¢ EUR; não 1¢ / USD',
      obtained: bagHit.brief,
    );
  } else {
    c.block('A3.bag', 'ED1', 'bag quote servidor; line_total cliente ignorado', {
      'quoted': bagQuoted,
      'amount_total': bagStripe,
      'status': bagHit.status,
    });
  }

  // Checkout A para unpaid session (settle alvo)
  final ckA = await c.checkout(
    orderId: oidA,
    buyer: b2,
    jwt: c.buyer2Jwt,
    amount: 1,
    productId: pidA,
    seller: s1,
    extra: {'total': 50, 'server_amount_cents': '50'},
  );
  final sidA = ckA.sessionId;
  if (sidA == null) {
    c.skip('A1-A5', 'ED1', 'checkout A sem session_id', ckA);
    return;
  }

  // A1 POST settle unpaid + GET inexistente (classe_nova vs DX GET-only)
  final a1post = await c.settlePost(
    sidA,
    jwt: c.buyer2Jwt,
    extraQs: 'order_id=$oidA',
  );
  final a1get = await c.settleGet(sidA);
  final a1fake = await c.settleGet('cs_test_rted_inexistente_dead_000');
  final a1ws = await c.edge(
    'create-payment-intent',
    method: 'GET',
    qs: 'checkout_return=success&session_id=%20$sidA%20',
  );
  final rowA1 = await c.orderRow(oidA);
  final a1credited = c.orderPaid(rowA1) ||
      looksPaidCopy(a1post) ||
      looksPaidCopy(a1get) ||
      looksPaidCopy(a1ws) ||
      (numOf(rowA1?['amount_paid_cents']) ?? 0) > 0;
  final a1oracle = stripeOracle(a1fake) || stripeOracle(a1ws);
  c.probe(
    id: 'A1',
    edgeRpc: 'create-payment-intent POST?qs settle + GET fake',
    payload:
        'POST checkout_return=success&session_id unpaid + GET unpaid + GET cs_inexistente + whitespace sid',
    http: {
      'post': a1post.brief,
      'get': a1get.brief,
      'fake': a1fake.brief,
      'ws': a1ws.brief,
    },
    stripeBd: {
      'status': rowA1?['status'],
      'amount_paid_cents': rowA1?['amount_paid_cents'],
    },
    result: (a1credited || a1oracle) ? 'FAIL' : 'HOLD',
    lens: 'ED1',
    countFinding: a1credited || a1oracle,
    classeNova: true,
  );
  if (a1credited || a1oracle) {
    c.hold(
      id: a1credited ? 'ED-P0-A1-POST-SETTLE-UNPAID' : 'ED-P3-A1-ORACLE',
      lens: 'ED1',
      severity: a1credited ? 'P0' : 'P3',
      title: a1credited
          ? 'POST/GET settle unpaid marcou encomenda paga'
          : 'session inexistente ecoa oráculo Stripe',
      actor: 'B2 POST + anon GET',
      pre: 'Session unpaid',
      repro: 'POST create-payment-intent?checkout_return=success&session_id=',
      expected: 'POST não liquida unpaid; fake 400 genérico',
      obtained: {
        'post': a1post.brief,
        'get': a1get.brief,
        'fake': a1fake.brief,
        'row': rowA1,
      },
    );
  } else {
    c.block('A1.post', 'ED1', 'POST qs settle unpaid sem crédito / sem oráculo', {
      'post': a1post.status,
      'get': a1get.status,
      'fake': a1fake.status,
      'status': rowA1?['status'],
    });
  }

  // A2 session_id alheio: tip cs_ no CPI + PI id como session_id (classe_nova vs DX order_id qs)
  final liveA2 = await c.insertLive(seller: s1, title: '$prefix tip-a2');
  HttpHit? tipA2;
  if (liveA2 != null) {
    await c.restoreSeller1Published();
    tipA2 = await c.tipCheckout(
      liveId: liveA2,
      seller: s1,
      amountEur: 2,
      jwt: c.buyer2Jwt,
    );
  }
  final sidTip = tipA2?.sessionId;
  if (tipA2?.tipId != null) c.createdTipIds.add(tipA2!.tipId!);
  final paidForPi = await c.payToPago(lens: 'ED1', buyer: b2);
  final piAsSid = paidForPi?.pi;
  HttpHit? a2tipOnCpi;
  HttpHit? a2piAsSession;
  if (sidTip != null) {
    a2tipOnCpi = await c.settleGet(sidTip, extraQs: 'order_id=$oidB');
  }
  if (piAsSid != null) {
    a2piAsSession = await c.settleGet(piAsSid, extraQs: 'order_id=$oidB');
  }
  final rowB2 = await c.orderRow(oidB);
  final rowPaidA2 = paidForPi == null ? null : await c.orderRow(paidForPi.oid);
  final a2paidB = c.orderPaid(rowB2) ||
      looksPaidCopy(a2tipOnCpi) ||
      looksPaidCopy(a2piAsSession) ||
      (numOf(rowB2?['amount_paid_cents']) ?? 0) > 0;
  final a2doublePaid = paidForPi != null &&
      rowPaidA2 != null &&
      (numOf(rowPaidA2['amount_paid_cents']) ?? 0) > 590 * 2;
  c.probe(
    id: 'A2',
    edgeRpc: 'create-payment-intent GET session alheio',
    payload:
        'GET CPI settle cs_tip + GET CPI settle pi_ (PI 4242) order_id=oidB',
    http: {
      'tip_create': tipA2?.brief,
      'tip_on_cpi': a2tipOnCpi?.brief,
      'pi_as_sid': a2piAsSession?.brief,
    },
    stripeBd: {
      'oidB': rowB2?['status'],
      'paid_oid': rowPaidA2?['status'],
      'sidTip': sidTip,
      'pi': piAsSid,
    },
    result: (a2paidB || a2doublePaid) ? 'FAIL' : 'HOLD',
    lens: 'ED1',
    countFinding: a2paidB || a2doublePaid,
    classeNova: true,
  );
  if (a2paidB || a2doublePaid) {
    c.hold(
      id: 'ED-P0-A2-SESSION-ALHEIO',
      lens: 'ED1',
      severity: 'P0',
      title: 'settle CPI com cs_tip ou pi_ creditou order B / duplicou pago',
      actor: 'anon GET',
      pre: 'session_id tem de ser cs_ da própria order',
      repro: 'GET create-payment-intent session_id=cs_tip|pi_ &order_id=B',
      expected: 'oidB reserva_pendente; pago existente inalterado',
      obtained: {
        'tip_on_cpi': a2tipOnCpi?.brief,
        'pi': a2piAsSession?.brief,
        'rowB': rowB2,
      },
    );
  } else {
    c.block('A2.alheio', 'ED1', 'cs_tip/pi_ não liquidam oidB', {
      'oidB': rowB2?['status'],
      'tip': a2tipOnCpi?.status,
      'pi': a2piAsSession?.status,
    });
  }

  // A4 reuse + GET cancel + fase2_e2e_settle JWT comprador (classe_nova)
  final cancelHit = await c.edge(
    'create-payment-intent',
    method: 'GET',
    qs: 'checkout_return=cancel&session_id=$sidA',
  );
  final reuse = await c.checkout(
    orderId: oidA,
    buyer: b2,
    jwt: c.buyer2Jwt,
    amount: 1,
    productId: pidA,
    seller: s1,
  );
  HttpHit? fase2Buyer;
  if (paidForPi?.pi != null) {
    fase2Buyer = await c.fase2SettleBuyer(
      orderId: oidB,
      paymentIntentId: paidForPi!.pi!,
      productId: pidB,
      jwt: c.buyer2Jwt,
    );
  }
  final rowA4 = await c.orderRow(oidA);
  final rowB4 = await c.orderRow(oidB);
  final a4paid = c.orderPaid(rowA4) || looksPaidCopy(cancelHit);
  final a4fase2 = fase2Buyer != null &&
      fase2Buyer.ok &&
      (c.orderPaid(rowB4) || fase2Buyer.map?['ok'] == true);
  c.probe(
    id: 'A4',
    edgeRpc: 'GET cancel + POST reuse + fase2_e2e_settle JWT buyer',
    payload:
        'GET checkout_return=cancel sidA; 2.º POST mesma order; POST ?fase2_e2e_settle=1 JWT B2 no oidB+PI alheio',
    http: {
      'cancel': cancelHit.brief,
      'reuse': reuse.brief,
      'fase2': fase2Buyer?.brief,
    },
    stripeBd: {
      'sidA': sidA,
      'reuseSid': reuse.sessionId,
      'oidA': rowA4?['status'],
      'oidB': rowB4?['status'],
    },
    result: (a4paid || a4fase2) ? 'FAIL' : 'HOLD',
    lens: 'ED1',
    countFinding: a4paid || a4fase2,
    classeNova: true,
  );
  if (a4paid || a4fase2) {
    c.hold(
      id: a4fase2 ? 'ED-P0-A4-FASE2-JWT' : 'ED-P0-A4-CANCEL-SETTLE',
      lens: 'ED1',
      severity: 'P0',
      title: a4fase2
          ? 'fase2_e2e_settle aceitou JWT comprador (não service_role)'
          : 'GET cancel / reuse liquidou unpaid',
      actor: 'B2 JWT',
      pre: 'fase2_e2e_settle exige Bearer=service_role',
      repro: 'POST ?fase2_e2e_settle=1 JWT buyer; GET cancel',
      expected: 'fase2 401; order A ≠pago',
      obtained: {
        'fase2': fase2Buyer?.brief,
        'cancel': cancelHit.brief,
        'rowA': rowA4,
        'rowB': rowB4,
      },
    );
  } else {
    c.block('A4.reuse', 'ED1', 'cancel/reuse sem captura; fase2 JWT recusado', {
      'reuseSid': reuse.sessionId,
      'fase2': fase2Buyer?.status,
      'oidA': rowA4?['status'],
      'oidB': rowB4?['status'],
    });
  }

  // A5 GET∥POST settle paralelo (race obrigatória, classe_nova vs DX GET∥GET)
  final raced = await Future.wait([
    c.settleGet(sidA),
    c.settlePost(sidA, jwt: c.buyer2Jwt, extraQs: 'order_id=$oidA'),
  ]);
  final rowA5 = await c.orderRow(oidA);
  final a5paid = c.orderPaid(rowA5) ||
      looksPaidCopy(raced[0]) ||
      looksPaidCopy(raced[1]) ||
      (numOf(rowA5?['amount_paid_cents']) ?? 0) > 0;
  c.probe(
    id: 'A5',
    edgeRpc: 'create-payment-intent GET ∥ POST settle',
    payload: 'Future.wait GET settle sidA ∥ POST ?checkout_return=success sidA',
    http: {'get': raced[0].brief, 'post': raced[1].brief},
    stripeBd: {
      'status': rowA5?['status'],
      'amount_paid_cents': rowA5?['amount_paid_cents'],
    },
    result: a5paid ? 'FAIL' : 'HOLD',
    lens: 'ED6',
    countFinding: a5paid,
    classeNova: true,
    race: true,
  );
  if (a5paid) {
    c.hold(
      id: 'ED-P0-A5-GET-POST-RACE',
      lens: 'ED6',
      severity: 'P0',
      title: 'GET∥POST settle unpaid marcou pago',
      actor: 'anon GET + B2 POST',
      pre: 'Session unpaid',
      repro: 'Future.wait GET+POST checkout_return=success',
      expected: 'ambos sem liquidar; reserva_pendente',
      obtained: {
        'get': raced[0].brief,
        'post': raced[1].brief,
        'row': rowA5,
      },
    );
  } else {
    c.block('A5.race', 'ED6', 'GET∥POST unpaid sem crédito', {
      'get': raced[0].status,
      'post': raced[1].status,
      'status': rowA5?['status'],
    });
  }
}

Future<void> runTip(Rted c, String s1, String s2, String b2) async {
  final live = await c.insertLive(seller: s1, title: '$prefix tip-s1');
  final liveS2 = await c.insertLive(seller: s2, title: '$prefix tip-s2');
  if (live == null) {
    c.skip('B*', 'ED2', 'live S1 fixture falhou', live);
    return;
  }
  await c.restoreSeller1Published();

  // B1 amount hostil novo (1e2 string, 2,00, Inf) + tip_id + live fake + buyer RPC settle
  final hostilHits = <String, String>{};
  for (final a in <Object>[0, -1, '2,00', 0.5, 501, '1e6']) {
    final h = await c.tipCheckout(
      liveId: live,
      seller: s1,
      amountEur: a,
      jwt: c.buyer2Jwt,
    );
    hostilHits['$a'] = h.brief;
  }
  final infBody = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': live,
      'seller_id': s1,
      'amount_eur': null,
      'playback_id': '../../../admin',
      'is_live': false,
    },
  );
  hostilHits['null+playback'] = infBody.brief;
  final tipIdHit = await c.tipCheckout(
    liveId: live,
    seller: s1,
    amountEur: 2,
    jwt: c.buyer2Jwt,
    extra: {'tip_id': '00000000-0000-4000-8000-000000000001'},
  );
  hostilHits['tip_id'] = tipIdHit.brief;
  final liveFake = await c.tipCheckout(
    liveId: '00000000-0000-4000-8000-000000000099',
    seller: s1,
    amountEur: 2,
    jwt: c.buyer2Jwt,
  );
  hostilHits['live_fake'] = liveFake.brief;

  final rpcBuyer = await c.rpc(
    'batata_settle_live_tip_from_stripe',
    {
      'p_tip_id': '00000000-0000-4000-8000-000000000001',
      'p_stripe_session_id': 'cs_test_rted_rpc_buyer',
      'p_paid_amount_cents': 200,
    },
    jwt: c.buyer2Jwt,
  );
  hostilHits['rpc_buyer'] = rpcBuyer.brief;
  final rpcCredited = rpcBuyer.ok && rpcBuyer.json == true;
  final anyHostilOk = hostilHits.values.any((s) => s.startsWith('200')) ||
      tipIdHit.ok ||
      liveFake.ok ||
      infBody.ok;
  c.probe(
    id: 'B1',
    edgeRpc: 'create-live-tip-checkout POST + RPC settle JWT',
    payload:
        'amount 0/-1/"2,00"/0.5/501/"1e6" + playback_id + tip_id + live fake + batata_settle_live_tip JWT B2',
    http: hostilHits,
    stripeBd: {'rpc_json': rpcBuyer.json, 'rpc_status': rpcBuyer.status},
    result: (anyHostilOk || rpcCredited) ? 'FAIL' : 'HOLD',
    lens: 'ED2',
    countFinding: anyHostilOk || rpcCredited,
    classeNova: true,
  );
  if (anyHostilOk || rpcCredited) {
    c.hold(
      id: rpcCredited ? 'ED-P0-B1-TIP-RPC' : 'ED-P0-B1-TIP-HOSTIL',
      lens: 'ED2',
      severity: 'P0',
      title: rpcCredited
          ? 'JWT comprador executou batata_settle_live_tip_from_stripe'
          : 'tip aceitou amount/tip_id/live_id/playback hostil',
      actor: 'B2 JWT',
      pre: 'RPC só service_role; amount 1–500; client tip_id forbidden',
      repro: 'POST tip hostil; RPC settle JWT buyer',
      expected: 'Edge 400; RPC 401/403/false',
      obtained: hostilHits,
    );
  } else {
    c.block('B1.hostil', 'ED2', 'amount/tip_id/live/RPC buyer recusados', hostilHits);
  }

  // B2 tip Session criada → GET settle ∥ end_live ∥ unpublish (classe_nova vs DX POST∥end)
  final liveRace = await c.insertLive(seller: s1, title: '$prefix tip-race');
  HttpHit? tipCreated;
  if (liveRace != null) {
    await c.restoreSeller1Published();
    tipCreated = await c.tipCheckout(
      liveId: liveRace,
      seller: s1,
      amountEur: 2,
      jwt: c.buyer2Jwt,
    );
  }
  final sidRace = tipCreated?.sessionId;
  if (tipCreated?.tipId != null) c.createdTipIds.add(tipCreated!.tipId!);
  HttpHit? settleR;
  HttpHit? endR;
  num dB2 = 0;
  Map<String, dynamic>? tipRaceRow;
  if (sidRace != null && liveRace != null) {
    final w0 = await c.walletBal(s1);
    final raced = await Future.wait([
      c.tipSettleGet(sidRace),
      c.rest('PATCH', 'lives?id=eq.$liveRace', service: true, body: {
        'is_active': false,
        'status': 'ended',
      }, prefer: 'return=minimal'),
      () async {
        await c.setHub(s1, false);
        return HttpHit(0, 'unpublish', {'ok': true});
      }(),
    ]);
    settleR = raced[0];
    endR = raced[1];
    final w1 = await c.walletBal(s1);
    dB2 = w1 - w0;
    await c.restoreSeller1Published();
    if (tipCreated?.tipId != null) {
      tipRaceRow = await c.tipRow(tipCreated!.tipId!);
    }
  }
  final b2credited = c.tipCredited(tipRaceRow) ||
      dB2 > 0 ||
      looksPaidCopy(settleR);
  c.probe(
    id: 'B2',
    edgeRpc: 'tip GET settle ∥ end_live/unpublish',
    payload:
        'Session tip unpaid já criada; Future.wait GET settle ∥ PATCH ended ∥ hub unpublish',
    http: {
      'create': tipCreated?.brief,
      'settle': settleR?.brief,
      'end': endR?.brief,
    },
    stripeBd: {
      'tip_id': tipCreated?.tipId,
      'tip_status': tipRaceRow?['status'],
      'delta_wallet': dB2,
    },
    result: sidRace == null ? 'SKIP' : (b2credited ? 'FAIL' : 'HOLD'),
    lens: 'ED6',
    countFinding: b2credited,
    classeNova: true,
    race: true,
  );
  if (b2credited) {
    c.hold(
      id: 'ED-P0-B2-TIP-SETTLE-UNPUBLISH',
      lens: 'ED6',
      severity: 'P0',
      title: 'GET settle tip unpaid ∥ unpublish creditou wallet',
      actor: 'anon GET + service end_live',
      pre: 'Session unpaid; tips só broadcasting',
      repro: 'criar tip Session; Future.wait GET settle ∥ PATCH ended',
      expected: 'pending Δwallet 0',
      obtained: {
        'settle': settleR?.brief,
        'row': tipRaceRow,
        'delta': dB2,
      },
    );
  } else if (sidRace != null) {
    c.block('B2.race', 'ED6', 'GET settle∥end unpaid sem crédito', {
      'settle': settleR?.status,
      'status': tipRaceRow?['status'],
      'delta': dB2,
    });
  } else {
    c.skip('B2', 'ED6', 'não criou tip Session (broadcast/429)', tipCreated);
  }

  // B3 seller≠owner (1 residual máx)
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
    http: {'s2_on_s1': wrong.brief, 's1_on_s2': s2own?.brief},
    result: b3fail ? 'FAIL' : 'HOLD',
    lens: 'ED2',
    countFinding: b3fail,
  );
  if (b3fail) {
    c.hold(
      id: 'ED-P1-B3-TIP-SELLER',
      lens: 'ED2',
      severity: 'P1',
      title: 'tip aceita seller_id ≠ dono da live',
      actor: 'B2 JWT',
      pre: 'Tip seller does not own this live',
      repro: 'POST create-live-tip-checkout seller_id alheio',
      expected: '400',
      obtained: {'wrong': wrong.brief, 's2own': s2own?.brief},
    );
  } else {
    c.block('B3.owner', 'ED2', 'seller≠owner 400 (residual clássico)', {
      'wrong': wrong.brief,
      's2own': s2own?.brief,
    });
  }

  // B4 tip unpaid Δwallet 0 + tip∥CPI bag (classe_nova composição)
  final liveB4 = await c.insertLive(seller: s1, title: '$prefix tip-b4');
  final pidCpi = await c.createProduct(
    seller: s1,
    title: '$prefix cpi-b4',
    qty: 3,
    price: 12,
  );
  final oidCpi = pidCpi == null
      ? null
      : await c.insertOrder(
          productId: pidCpi,
          buyer: b2,
          seller: s1,
          price: 12,
        );
  HttpHit? tipB4c;
  HttpHit? cpiB4;
  if (liveB4 != null && oidCpi != null) {
    await c.restoreSeller1Published();
    final raced = await Future.wait([
      c.tipCheckout(
        liveId: liveB4,
        seller: s1,
        amountEur: 2,
        jwt: c.buyer2Jwt,
      ),
      c.checkout(
        orderId: oidCpi,
        buyer: b2,
        jwt: c.buyer2Jwt,
        amount: 1,
        productId: pidCpi,
        seller: s1,
      ),
    ]);
    tipB4c = raced[0];
    cpiB4 = raced[1];
  }
  if (tipB4c?.tipId != null) c.createdTipIds.add(tipB4c!.tipId!);
  final sidTipB4 = tipB4c?.sessionId;
  HttpHit? settleB4;
  Map<String, dynamic>? tipB4row;
  num dB4 = 0;
  if (sidTipB4 != null) {
    final w0 = await c.walletBal(s1);
    settleB4 = await c.tipSettleGet(sidTipB4);
    final w1 = await c.walletBal(s1);
    dB4 = w1 - w0;
    if (tipB4c?.tipId != null) tipB4row = await c.tipRow(tipB4c!.tipId!);
  }
  final rowCpi = oidCpi == null ? null : await c.orderRow(oidCpi);
  final b4credited = dB4 > 0 ||
      looksPaidCopy(settleB4) ||
      c.tipCredited(tipB4row) ||
      c.orderPaid(rowCpi);
  c.probe(
    id: 'B4',
    edgeRpc: 'tip POST ∥ CPI bag/checkout + GET unpaid',
    payload:
        'Future.wait tip Session ∥ create-payment-intent mesma B2; GET tip unpaid',
    http: {
      'tip': tipB4c?.brief,
      'cpi': cpiB4?.brief,
      'settle': settleB4?.brief,
    },
    stripeBd: {
      'tip_status': tipB4row?['status'],
      'cpi_status': rowCpi?['status'],
      'delta_wallet': dB4,
      'sid_tip': sidTipB4,
      'sid_cpi': cpiB4?.sessionId,
    },
    result: sidTipB4 == null && cpiB4 == null
        ? 'SKIP'
        : (b4credited ? 'FAIL' : 'HOLD'),
    lens: 'ED6',
    countFinding: b4credited,
    classeNova: true,
    race: true,
  );
  if (b4credited) {
    c.hold(
      id: 'ED-P0-B4-TIP-CPI-RACE',
      lens: 'ED6',
      severity: 'P0',
      title: 'tip∥CPI unpaid creditou wallet ou marcou order paga',
      actor: 'B2 JWT paralelo',
      pre: 'nenhuma Session paga',
      repro: 'Future.wait tip POST ∥ CPI POST; GET tip settle',
      expected: 'tip pending Δ=0; order reserva_pendente',
      obtained: {
        'tip': tipB4row,
        'cpi': rowCpi,
        'delta': dB4,
      },
    );
  } else if (sidTipB4 != null || cpiB4 != null) {
    c.block('B4.race', 'ED6', 'tip∥CPI unpaid sem crédito', {
      'tip': tipB4row?['status'],
      'cpi': rowCpi?['status'],
      'delta': dB4,
    });
  } else {
    c.skip('B4', 'ED6', 'tip∥CPI não criou Sessions', {
      'tip': tipB4c?.brief,
      'cpi': cpiB4?.brief,
    });
  }
}

Future<void> runWebhookCorsRefund(Rted c, String s1, String b1) async {
  Future<({String oid, String pid, String? pi})> mustPay(String lens) async {
    final paid = await c.payToPago(lens: lens);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  // C1 webhook forge + replay mesmo body 2× (classe_nova vs DX 1 POST)
  const fakeEvent = {
    'id': 'evt_rted_replay',
    'object': 'event',
    'type': 'checkout.session.completed',
    'created': 1710000000,
    'data': {
      'object': {
        'id': 'cs_test_rted_replay',
        'object': 'checkout.session',
        'payment_status': 'paid',
        'amount_total': 99999,
        'metadata': {
          'order_id': '00000000-0000-4000-8000-000000000002',
          'purpose': 'live_tip',
          'tip_id': '00000000-0000-4000-8000-000000000003',
        },
      },
    },
  };
  const sig =
      't=1710000000,v1=deadbeefcafebabe0123456789abcdef0123456789abcdef0123456789abcdef';
  final noSig = await c.webhookPost(fakeEvent, extra: {'Origin': 'null'});
  final r1 = await c.webhookPost(fakeEvent, extra: {
    'stripe-signature': sig,
    'Origin': 'null',
  });
  final r2 = await c.webhookPost(fakeEvent, extra: {
    'stripe-signature': sig,
    'Origin': 'null',
  });
  final whGet = await c.edge('stripe-webhook', method: 'GET');
  final replayOk = noSig.ok || r1.ok || r2.ok;
  c.probe(
    id: 'C1',
    edgeRpc: 'stripe-webhook POST forge + replay',
    payload:
        'POST sem sig + 2× mesmo body checkout.session.completed paid v1=deadbeef Origin null',
    http: {
      'no_sig': noSig.brief,
      'r1': r1.brief,
      'r2': r2.brief,
      'get': whGet.brief,
    },
    stripeBd: {
      'no_sig_acao': noSig.acao,
      'r1_acao': r1.acao,
    },
    result: replayOk ? 'FAIL' : 'HOLD',
    lens: 'ED3',
    countFinding: replayOk,
    classeNova: true,
  );
  if (replayOk) {
    c.hold(
      id: 'ED-P0-C1-WEBHOOK-REPLAY',
      lens: 'ED3',
      severity: 'P0',
      title: 'webhook aceitou forge ou replay sem assinatura válida',
      actor: 'anon POST',
      pre: 'constructEventAsync exige whsec; replay sem sig válida = 400',
      repro: 'POST stripe-webhook 2× mesmo body + sig morta',
      expected: '400 missing/invalid_signature ambos',
      obtained: {'no_sig': noSig.brief, 'r1': r1.brief, 'r2': r2.brief},
    );
  } else {
    c.block('C1.replay', 'ED3', 'webhook recusa forge e replay (400)', {
      'no_sig': noSig.status,
      'r1': r1.status,
      'r2': r2.status,
      'get': whGet.status,
    });
  }

  // C2 CORS Origin null + evil + chrome-extension (classe_nova: null)
  const evil = 'https://evil.com';
  const ext = 'chrome-extension://abcdef123456';
  const originNull = 'null';
  final hits = <String, HttpHit>{
    'opt_null_cpi': await c.edge(
      'create-payment-intent',
      method: 'OPTIONS',
      extra: {'Origin': originNull},
    ),
    'post_null_tip': await c.edge(
      'create-live-tip-checkout',
      method: 'OPTIONS',
      extra: {'Origin': originNull},
    ),
    'opt_null_refund': await c.edge(
      'refund-order',
      method: 'OPTIONS',
      extra: {'Origin': originNull},
    ),
    'get_null': await c.settleGet(
      'cs_test_rted_cors_null',
      extra: {'Origin': originNull},
    ),
    'opt_evil': await c.edge(
      'create-payment-intent',
      method: 'OPTIONS',
      extra: {'Origin': evil},
    ),
    'opt_ext': await c.edge(
      'refund-order',
      method: 'OPTIONS',
      extra: {'Origin': ext},
    ),
    'opt_wh_null': await c.edge(
      'stripe-webhook',
      method: 'OPTIONS',
      extra: {'Origin': originNull},
    ),
  };
  final echoed = corsEchoes(hits['opt_null_cpi']!, originNull) ||
      corsEchoes(hits['post_null_tip']!, originNull) ||
      corsEchoes(hits['opt_null_refund']!, originNull) ||
      corsEchoes(hits['get_null']!, originNull) ||
      corsEchoes(hits['opt_evil']!, evil) ||
      corsEchoes(hits['opt_ext']!, ext) ||
      corsEchoes(hits['opt_wh_null']!, originNull);
  c.probe(
    id: 'C2',
    edgeRpc: 'CORS OPTIONS/GET Origin null / evil / chrome-extension',
    payload:
        'Origin: null + https://evil.com + chrome-extension:// em CPI/tip/refund/webhook',
    http: hits.map((k, v) => MapEntry(k, v.brief)),
    stripeBd: hits.map((k, v) => MapEntry('acao_$k', v.acao)),
    result: echoed ? 'FAIL' : 'HOLD',
    lens: 'ED4',
    countFinding: echoed,
    classeNova: true,
  );
  if (echoed) {
    c.hold(
      id: 'ED-P2-C2-CORS-NULL',
      lens: 'ED4',
      severity: 'P2',
      title: 'CORS ecoa Origin null / evil / chrome-extension',
      actor: 'browser Origin header',
      pre: 'null/extensões nunca reflectir; hostil → fleaber.pt',
      repro: 'OPTIONS Origin=null | evil.com | chrome-extension://',
      expected: 'ACAO ≠ null / evil / chrome-extension',
      obtained: hits.map((k, v) => MapEntry(k, v.acao)),
    );
  } else {
    c.block('C2.cors', 'ED4', 'Origin null/evil/ext não ecoado',
        hits.map((k, v) => MapEntry(k, v.acao)));
  }

  // C3 buyer refund 403 (residual) + seller refund 2× idempotente
  final pBuyer = await mustPay('ED5');
  final balS0 = await c.walletBal(s1);
  final buyerRefund = await c.refundOrder(pBuyer.oid, jwt: c.buyerJwt);
  final rowAfterBuyer = await c.orderRow(pBuyer.oid);
  final balS1w = await c.walletBal(s1);
  final buyerDid = buyerRefund.ok &&
      buyerRefund.map?['ok'] == true &&
      buyerRefund.map?['skipped'] != true &&
      '${rowAfterBuyer?['stripe_refund_id'] ?? ''}'.isNotEmpty;

  final pIdem = await mustPay('ED5');
  final sRefund1 = await c.refundOrder(pIdem.oid, jwt: c.sellerJwt);
  final row1 = await c.orderRow(pIdem.oid);
  final sRefund2 = await c.refundOrder(pIdem.oid, jwt: c.sellerJwt);
  final row2 = await c.orderRow(pIdem.oid);
  final id1 = '${row1?['stripe_refund_id'] ?? sRefund1.map?['refund_id'] ?? ''}';
  final id2 = '${row2?['stripe_refund_id'] ?? sRefund2.map?['refund_id'] ?? ''}';
  final firstOk = sRefund1.ok && sRefund1.map?['ok'] == true && sRefund1.map?['skipped'] != true;
  final secondNew = sRefund2.ok &&
      sRefund2.map?['ok'] == true &&
      sRefund2.map?['already_refunded'] != true &&
      sRefund2.map?['idempotent'] != true &&
      id2.isNotEmpty &&
      id1.isNotEmpty &&
      id2 != id1;
  c.probe(
    id: 'C3',
    edgeRpc: 'refund-order buyer + seller ×2',
    payload:
        'JWT comprador ${pBuyer.oid}; seller refund 2× ${pIdem.oid}',
    http: {
      'buyer': buyerRefund.brief,
      'r1': sRefund1.brief,
      'r2': sRefund2.brief,
    },
    stripeBd: {
      'buyer_refund_id': rowAfterBuyer?['stripe_refund_id'],
      'buyer_status': rowAfterBuyer?['status'],
      'deltaSeller': balS1w - balS0,
      'refund1': id1,
      'refund2': id2,
      'pi_buyer': pBuyer.pi,
      'pi_seller': pIdem.pi,
    },
    result: (buyerDid || secondNew) ? 'FAIL' : 'HOLD',
    lens: 'ED5',
    countFinding: buyerDid || secondNew,
  );
  if (buyerDid || secondNew) {
    c.hold(
      id: buyerDid ? 'ED-P0-C3-BUYER-REFUND' : 'ED-P0-C3-REFUND-DUP',
      lens: 'ED5',
      severity: 'P0',
      title: buyerDid
          ? 'buyer refund-order anulou Stripe da venda'
          : '2.º refund-order criou refund Stripe distinto',
      actor: buyerDid ? 'buyer JWT' : 'seller JWT',
      pre: 'seller-only + idempotency fleaber_order_refund_{id}',
      repro: 'POST refund-order buyer; seller 2×',
      expected: 'buyer 403; 2.º already_refunded mesmo re_',
      obtained: {
        'buyer': buyerRefund.brief,
        'r1': sRefund1.brief,
        'r2': sRefund2.brief,
      },
    );
  } else {
    c.block('C3.refund', 'ED5', 'buyer 403; seller 2.º idempotente', {
      'buyer': buyerRefund.status,
      'r1': sRefund1.brief,
      'r2': sRefund2.brief,
      'id1': id1,
      'id2': id2,
    });
  }

  // C4 refund∥release race
  final pRace = await mustPay('ED6');
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
    id: 'C4',
    edgeRpc: 'refund-order ∥ batata_release_seller_wallet_for_order',
    payload: 'Future.wait refund seller + release buyer/seller no pago',
    http: raced.map((h) => h.brief).toList(),
    stripeBd: {
      'refunded': refunded,
      'released': released,
      'delta': balC1 - balC0,
      'pi': pRace.pi,
    },
    result: raceOpen ? 'FAIL' : 'HOLD',
    lens: 'ED6',
    countFinding: raceOpen,
    race: true,
  );
  if (raceOpen) {
    c.hold(
      id: 'ED-P0-C4-RACE',
      lens: 'ED6',
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
    c.block('C4.race', 'ED6', 'race pago sem crédito+refund simultâneo', {
      'refunded': refunded,
      'released': released,
      'delta': balC1 - balC0,
    });
  }
}

Future<void> runCaixa(Rted c, String s1, String b2) async {
  // D1 pago 4242 + GET settle replay coerente order/wallet (classe_nova vs DX só setup_paid)
  final replay = await c.e2e('settle_get_replay', {}, buyer: b2);
  final rm = replay.map ?? {};
  final oid = rm['order_id']?.toString();
  if (oid != null) c.createdOrderIds.add(oid);
  final pid = rm['product_id']?.toString();
  if (pid != null) c.createdProductIds.add(pid);
  final row = oid == null ? null : await c.orderRow(oid);
  final w0 = await c.walletBal(s1);
  HttpHit? extraSettle;
  final sid = rm['session_id']?.toString();
  if (sid != null && sid.startsWith('cs_')) {
    extraSettle = await c.settleGet(sid);
  }
  final w1 = await c.walletBal(s1);
  final isPago = replay.ok &&
      c.orderPaid(row) &&
      '${row?['stripe_payment_intent_id'] ?? rm['payment_intent_id'] ?? ''}'
          .startsWith('pi_');
  final refunded = '${row?['stripe_refund_id'] ?? ''}'.isNotEmpty;
  final minted = (w1 - w0) > 0;
  c.probe(
    id: 'D1',
    edgeRpc: 'e2e settle_get_replay + GET settle extra',
    payload:
        'PI 4242 + Checkout Session paga + GET settle 2× e2e + 3.º GET auditor',
    http: {
      'e2e': replay.brief,
      'extra': extraSettle?.brief,
    },
    stripeBd: {
      'oid': oid,
      'sid': sid,
      'pi': rm['payment_intent_id'] ?? row?['stripe_payment_intent_id'],
      'status': row?['status'],
      'amount_paid_cents': row?['amount_paid_cents'],
      'refund_id': row?['stripe_refund_id'],
      'delta_wallet': w1 - w0,
      'settle1': rm['settle1_http'],
      'settle2': rm['settle2_http'],
    },
    result: !isPago
        ? 'SKIP'
        : ((refunded || minted) ? 'FAIL' : 'HOLD'),
    lens: 'ED7',
    countFinding: isPago && (refunded || minted),
    classeNova: true,
  );
  if (isPago && (refunded || minted)) {
    c.hold(
      id: 'ED-P0-D1-SETTLE-REPLAY',
      lens: 'ED7',
      severity: 'P0',
      title: 'GET settle replay em order já paga refund/creditou wallet',
      actor: 'anon GET settle + e2e 4242',
      pre: 'order pago; replay GET não emite refund nem minta',
      repro: 'e2e settle_get_replay; GET extra session_id',
      expected: 'status pago; refund_id vazio; Δwallet 0',
      obtained: {
        'row': row,
        'delta': w1 - w0,
        'extra': extraSettle?.brief,
      },
    );
  } else if (isPago) {
    c.block('D1.replay', 'ED7', 'pago 4242; settle replay coerente sem mint/refund', {
      'pi': rm['payment_intent_id'],
      'sid': sid,
      'status': row?['status'],
      'delta': w1 - w0,
    });
  } else {
    c.skip('D1', 'ED7', 'settle_get_replay não liquidou', replay);
  }

  // D2 tip Session TEST + GET unpaid + RPC buyer no tip real (Δwallet)
  final liveD2 = await c.insertLive(seller: s1, title: '$prefix tip-d2');
  HttpHit? tipD2;
  if (liveD2 != null) {
    await c.restoreSeller1Published();
    tipD2 = await c.tipCheckout(
      liveId: liveD2,
      seller: s1,
      amountEur: 2,
      jwt: c.buyer2Jwt,
    );
  }
  final tipId = tipD2?.tipId;
  final sidD2 = tipD2?.sessionId;
  if (tipId != null) c.createdTipIds.add(tipId);
  final wD0 = await c.walletBal(s1);
  HttpHit? rpcTip;
  HttpHit? settleD2;
  if (tipId != null && sidD2 != null) {
    rpcTip = await c.rpc(
      'batata_settle_live_tip_from_stripe',
      {
        'p_tip_id': tipId,
        'p_stripe_session_id': sidD2,
        'p_paid_amount_cents': 200,
      },
      jwt: c.buyer2Jwt,
    );
    settleD2 = await c.tipSettleGet(sidD2);
  }
  final wD1 = await c.walletBal(s1);
  final tipRow = tipId == null ? null : await c.tipRow(tipId);
  final d2credited = (wD1 - wD0) > 0 ||
      c.tipCredited(tipRow) ||
      (rpcTip != null && rpcTip.ok && rpcTip.json == true) ||
      looksPaidCopy(settleD2);
  c.probe(
    id: 'D2',
    edgeRpc: 'create-live-tip-checkout Session + RPC buyer + GET unpaid',
    payload:
        'POST tip 2€ Session TEST; JWT B2 RPC settle paid_cents=200; GET unpaid',
    http: {
      'create': tipD2?.brief,
      'rpc': rpcTip?.brief,
      'settle': settleD2?.brief,
    },
    stripeBd: {
      'sid': sidD2,
      'tip_id': tipId,
      'tip_status': tipRow?['status'],
      'delta_wallet': wD1 - wD0,
      'rpc_json': rpcTip?.json,
    },
    result: sidD2 == null ? 'SKIP' : (d2credited ? 'FAIL' : 'HOLD'),
    lens: 'ED7',
    countFinding: d2credited,
    classeNova: true,
  );
  if (d2credited) {
    c.hold(
      id: 'ED-P0-D2-TIP-CREDIT',
      lens: 'ED7',
      severity: 'P0',
      title: 'tip unpaid / RPC buyer creditou wallet',
      actor: 'B2 JWT + anon GET',
      pre: 'Session payment_status≠paid; RPC só service_role',
      repro: 'POST tip; RPC settle JWT; GET unpaid',
      expected: 'pending Δwallet 0; RPC false/401',
      obtained: {
        'rpc': rpcTip?.brief,
        'row': tipRow,
        'delta': wD1 - wD0,
      },
    );
  } else if (sidD2 != null) {
    c.block('D2.unpaid', 'ED7', 'tip Session TEST unpaid Δwallet 0; RPC buyer recusado', {
      'status': tipRow?['status'],
      'delta': wD1 - wD0,
      'rpc': rpcTip?.status,
      'sid': sidD2,
    });
  } else {
    c.skip('D2', 'ED7', 'não criou tip Session', tipD2);
  }

  // D3 amount_total Session ≠ body cliente (servidor ganha) + GET settle amount qs
  final pidD3 = await c.createProduct(
    seller: s1,
    title: '$prefix d3-amt',
    qty: 3,
    price: 12,
  );
  final oidD3 = pidD3 == null
      ? null
      : await c.insertOrder(
          productId: pidD3,
          buyer: b2,
          seller: s1,
          price: 12,
        );
  HttpHit? ckD3;
  if (oidD3 != null) {
    ckD3 = await c.checkout(
      orderId: oidD3,
      buyer: b2,
      jwt: c.buyer2Jwt,
      amount: 1,
      productId: pidD3,
      seller: s1,
      extra: {
        'total': 1,
        'amount_total': 1,
        'server_amount_cents': 1,
        'item_price': 0.01,
        'protection_fee': 0,
        'shipping': 0,
      },
    );
  }
  final quoted = numOf(ckD3?.map?['server_amount_cents'])?.round();
  final stripeAmt = numOf(ckD3?.map?['amount_total'])?.round();
  HttpHit? settleAmt;
  if (ckD3?.sessionId != null) {
    settleAmt = await c.settleGet(
      ckD3!.sessionId!,
      extraQs: 'amount=1&amount_total=1&server_amount_cents=1',
    );
  }
  final rowD3 = oidD3 == null ? null : await c.orderRow(oidD3);
  final clientWon = ckD3 != null &&
      ckD3.ok &&
      ((quoted != null && quoted <= 50) ||
          (stripeAmt != null && stripeAmt <= 50));
  final settlePaid = c.orderPaid(rowD3) || looksPaidCopy(settleAmt);
  c.probe(
    id: 'D3',
    edgeRpc: 'create-payment-intent POST amount hostil + GET settle amount qs',
    payload:
        'body amount/total/amount_total=1 vs SKU 12€; GET settle &amount=1 unpaid',
    http: {'ck': ckD3?.brief, 'settle': settleAmt?.brief},
    stripeBd: {
      'server_amount_cents': quoted,
      'amount_total': stripeAmt,
      'status': rowD3?['status'],
      'sid': ckD3?.sessionId,
    },
    result: ckD3 == null
        ? 'SKIP'
        : ((clientWon || settlePaid) ? 'FAIL' : 'HOLD'),
    lens: 'ED7',
    countFinding: clientWon || settlePaid,
    classeNova: true,
  );
  if (clientWon || settlePaid) {
    c.hold(
      id: clientWon ? 'ED-P0-D3-CLIENT-AMOUNT' : 'ED-P0-D3-SETTLE-QS-AMOUNT',
      lens: 'ED7',
      severity: 'P0',
      title: clientWon
          ? 'Session amount_total seguiu body cliente'
          : 'GET settle amount qs liquidou unpaid',
      actor: 'B2 JWT + anon GET',
      pre: 'quote servidor a partir da order/SKU',
      repro: 'POST amount=1; GET settle &amount=1',
      expected: 'amount_total ≥1200¢; GET unpaid sem crédito',
      obtained: {
        'quoted': quoted,
        'stripe': stripeAmt,
        'settle': settleAmt?.brief,
        'row': rowD3,
      },
    );
  } else if (ckD3 != null) {
    c.block('D3.server', 'ED7', 'servidor ganha amount; GET qs amount inerte', {
      'quoted': quoted,
      'amount_total': stripeAmt,
      'settle': settleAmt?.status,
      'status': rowD3?['status'],
    });
  } else {
    c.skip('D3', 'ED7', 'checkout D3 falhou', ckD3);
  }
}
