/// RED TEAM CEGO DL pass2 — A1–A4 settle sem sk_test_ local (claim fresco).
import 'dart:io';
import '_rtdl.dart';

bool looksPaidCopy(HttpHit? h) {
  final t = (h?.body ?? '').toLowerCase();
  return t.contains('pagamento recebido') ||
      t.contains('pagamento confirmado') ||
      t.contains('"status":"pago"');
}

Future<HttpHit> checkoutRetry(
  Rtdl c, {
  required String orderId,
  required String productId,
  required String seller,
  required String buyer,
  Object? amount = 1,
  Map<String, Object?> extra = const {},
}) async {
  HttpHit last = await c.checkout(
    orderId: orderId,
    buyer: buyer,
    jwt: c.buyerJwt,
    amount: amount,
    productId: productId,
    seller: seller,
    extra: extra,
  );
  for (var i = 0; i < 4 && !last.ok; i++) {
    final err = last.body.toLowerCase();
    if (!err.contains('contention') && !err.contains('busy')) break;
    await Future<void>.delayed(Duration(milliseconds: 400 + i * 300));
    last = await c.checkout(
      orderId: orderId,
      buyer: buyer,
      jwt: c.buyerJwt,
      amount: amount,
      productId: productId,
      seller: seller,
      extra: extra,
    );
  }
  return last;
}

Future<void> main() async {
  final c = Rtdl.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.restoreSeller1Published();

  final s1 = c.sellerId!;
  final b1 = c.buyerId!;
  const price = 12.0;

  Future<(String pid, String oid)> sku() async {
    final pid = await c.createProduct(
      seller: s1,
      title: '$prefix p2-${DateTime.now().millisecondsSinceEpoch % 100000}',
      qty: 3,
      price: price,
    );
    if (pid == null) throw StateError('sku');
    final oid = await c.insertOrder(
      productId: pid,
      buyer: b1,
      seller: s1,
      price: price,
    );
    if (oid == null) throw StateError('order');
    return (pid, oid);
  }

  final (pidA, oidA) = await sku();
  final ckA = await checkoutRetry(
    c,
    orderId: oidA,
    productId: pidA,
    seller: s1,
    buyer: b1,
    amount: 1,
    extra: {'total': 50, 'server_amount_cents': '50'},
  );
  c.note('p2.ckA', 'checkout A amount=1', ckA, lens: 'DL1');
  final sidA = ckA.sessionId;
  final quoted = numOf(ckA.map?['server_amount_cents'])?.round();
  final stripeAmt = numOf(ckA.map?['amount_total'])?.round();
  final clientWon = ckA.ok &&
      ((quoted != null && quoted <= 50) ||
          (stripeAmt != null && stripeAmt <= 50));
  c.probe(
    id: 'A3',
    edgeRpc: 'create-payment-intent POST',
    payload:
        'POST checkout amount=1 total=50 server_amount_cents=50 vs SKU 12,00€',
    http: ckA,
    stripeBd: {
      'sid': sidA,
      'server_amount_cents': quoted,
      'amount_total': stripeAmt,
      'order': (await c.orderRow(oidA))?['price_total'],
    },
    result: !ckA.ok ? 'SKIP' : (clientWon ? 'FAIL' : 'HOLD'),
    lens: 'DL1',
    countFinding: clientWon,
  );
  if (clientWon) {
    c.hold(
      id: 'DL-P0-A3-CLIENT-AMOUNT',
      lens: 'DL1',
      severity: 'P0',
      title: 'Checkout usou amount/total do cliente em vez da quote servidor',
      actor: 'B1 JWT',
      pre: 'SKU 12,00€ (+taxa); body amount=1',
      repro: 'POST create-payment-intent {amount:1,total:50}',
      expected: 'server_amount_cents/amount_total = quote (≥1200¢)',
      obtained: ckA.brief,
    );
  } else if (ckA.ok) {
    c.block('A3.amount', 'DL1', 'Edge devolve quote servidor, ignora body.amount', {
      'quoted': quoted,
      'amount_total': stripeAmt,
    });
  }

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
    http: a1get ?? ckA,
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
      actor: 'anon GET',
      pre: 'Session payment_status≠paid',
      repro: 'GET create-payment-intent?checkout_return=success&session_id=',
      expected: 'não pago; texto unpaid / 402',
      obtained: {'get': a1get?.brief, 'row': rowA1},
    );
  } else if (sidA != null) {
    c.block('A1.unpaid', 'DL1', 'GET settle unpaid não creditou', {
      'get': a1get?.brief,
      'status': rowA1?['status'],
    });
  }

  final (pidB, oidB) = await sku();
  final ckB = await checkoutRetry(
    c,
    orderId: oidB,
    productId: pidB,
    seller: s1,
    buyer: b1,
    amount: 99999,
  );
  final sidB = ckB.sessionId;
  c.note('p2.ckB', 'checkout B amount=99999', ckB, lens: 'DL1');

  await c.restoreSeller1Published();
  final live = await c.insertLive(seller: s1, title: '$prefix p2-tip');
  HttpHit? tipCk;
  String? tipSid;
  if (live != null) {
    tipCk = await c.tipCheckout(
      liveId: live,
      seller: s1,
      amountEur: 2,
      jwt: c.buyer2Jwt,
    );
    tipSid = tipCk.sessionId;
    if (tipCk.tipId != null) c.createdTipIds.add(tipCk.tipId!);
  }

  HttpHit? getAlienTipOnOrder;
  HttpHit? getAlienOrderOnTip;
  HttpHit? getB2onA;
  Map<String, dynamic>? rowA2;
  Map<String, dynamic>? rowB2s;
  if (sidA != null) {
    getB2onA = await c.settleGet(sidA);
  }
  if (tipSid != null) {
    getAlienTipOnOrder = await c.settleGet(tipSid);
  }
  if (sidB != null) {
    getAlienOrderOnTip = await c.tipSettleGet(sidB);
  }
  rowA2 = await c.orderRow(oidA);
  rowB2s = await c.orderRow(oidB);
  var tipSt = '';
  if (tipCk?.tipId != null) {
    final tr = await c.rest(
      'GET',
      'live_tips?id=eq.${tipCk!.tipId}&select=id,status',
      service: true,
    );
    tipSt = '${tr.map?['status'] ?? ''}';
  }
  final a2fail = c.orderPaid(rowA2) ||
      c.orderPaid(rowB2s) ||
      tipSt == 'paid' ||
      tipSt == 'settled' ||
      looksPaidCopy(getAlienTipOnOrder) ||
      looksPaidCopy(getAlienOrderOnTip);
  c.probe(
    id: 'A2',
    edgeRpc: 'create-payment-intent GET / create-live-tip-checkout GET',
    payload:
        'settle tip-cs_ no endpoint de encomenda; settle order-cs_ no endpoint de tip; B2 GET sidA',
    http: {
      'ckB': ckB.brief,
      'tip': tipCk?.brief,
      'b2onA': getB2onA?.brief,
      'tipOnOrder': getAlienTipOnOrder?.brief,
      'orderOnTip': getAlienOrderOnTip?.brief,
    },
    stripeBd: {
      'sidA': sidA,
      'sidB': sidB,
      'tipSid': tipSid,
      'statusA': rowA2?['status'],
      'statusB': rowB2s?['status'],
      'tipStatus': tipSt,
      'ckB_server_cents': ckB.map?['server_amount_cents'],
      'ckB_amount_total': ckB.map?['amount_total'],
    },
    result: (sidA == null && sidB == null) ? 'SKIP' : (a2fail ? 'FAIL' : 'HOLD'),
    lens: 'DL1',
    countFinding: a2fail,
  );
  if (a2fail) {
    c.hold(
      id: 'DL-P0-A2-ALIEN-SESSION',
      lens: 'DL1',
      severity: 'P0',
      title: 'session_id alheio (tip↔order) liquidou pagamento',
      actor: 'anon GET',
      pre: 'GET settle usa metadata da Session, não o path',
      repro: 'GET create-payment-intent?session_id=cs_tip e vice-versa',
      expected: 'unpaid; tip pending; orders reserva_pendente',
      obtained: {
        'A': rowA2,
        'B': rowB2s,
        'tip': tipSt,
        'tipOnOrder': getAlienTipOnOrder?.brief,
        'orderOnTip': getAlienOrderOnTip?.brief,
      },
    );
  } else {
    c.block('A2.alien', 'DL1', 'session alheia tip↔order não creditou', {
      'statusA': rowA2?['status'],
      'statusB': rowB2s?['status'],
      'tip': tipSt,
    });
  }

  // A4 reuse + dead session (sem sk_test_ expire)
  final ckReuse = await checkoutRetry(
    c,
    orderId: oidA,
    productId: pidA,
    seller: s1,
    buyer: b1,
    amount: 1,
  );
  final sidReuse = ckReuse.sessionId;
  final reusedSame = sidA != null && sidReuse == sidA;
  HttpHit? a4get;
  if (sidA != null) a4get = await c.settleGet(sidA);
  final deadSid = 'cs_test_deaddeaddeaddeaddeadRTDL1612xx';
  final deadGet = await c.settleGet(deadSid);
  HttpHit? page;
  if (sidA != null) {
    page = await c.req(
      'GET',
      'https://checkout.stripe.com/c/pay/$sidA',
      auth: false,
    );
  }
  final rowA4 = await c.orderRow(oidA);
  final a4credited = c.orderPaid(rowA4) || looksPaidCopy(a4get);
  final dualOpen = ckReuse.ok &&
      sidReuse != null &&
      sidA != null &&
      sidReuse != sidA &&
      sidReuse.startsWith('cs_');
  c.probe(
    id: 'A4',
    edgeRpc: 'create-payment-intent POST reuse + GET settle dead cs_',
    payload:
        '2.º POST mesma order (reuse Session); GET unpaid; GET cs_test_dead…',
    http: {
      'reuse': ckReuse.brief,
      'getUnpaid': a4get?.brief,
      'deadGet': deadGet.brief,
      'hosted': page == null ? '' : '${page.status} ${clip(page.body, 80)}',
    },
    stripeBd: {
      'sidA': sidA,
      'sidReuse': sidReuse,
      'reusedSame': reusedSame,
      'dualOpen': dualOpen,
      'status': rowA4?['status'],
      'deadHttp': deadGet.status,
    },
    result: sidA == null
        ? 'SKIP'
        : ((a4credited || dualOpen) ? 'FAIL' : 'HOLD'),
    lens: 'DL1',
    countFinding: a4credited || dualOpen,
  );
  if (a4credited || dualOpen) {
    c.hold(
      id: dualOpen ? 'DL-P1-A4-DUAL-SESSION' : 'DL-P0-A4-EXPIRE-REUSE',
      lens: 'DL1',
      severity: dualOpen ? 'P1' : 'P0',
      title: dualOpen
          ? '2.º checkout da mesma order abriu Session Stripe distinta ainda open'
          : 'GET settle (reuse/dead) creditou encomenda',
      actor: 'B1 JWT + anon GET',
      pre: 'sem sk_test_ local para expire nativo; claim deve reuse cs_ open',
      repro: 'POST checkout 2× mesma order; GET settle; GET cs_ morta',
      expected: 'mesmo sid; GET unpaid; dead 400; order não paga',
      obtained: {
        'sidA': sidA,
        'sidReuse': sidReuse,
        'get': a4get?.brief,
        'dead': deadGet.brief,
        'row': rowA4,
      },
    );
  } else if (sidA != null) {
    c.block('A4.reuse', 'DL1', 'reuse mesmo sid; dead GET não liquida', {
      'reusedSame': reusedSame,
      'dead': deadGet.brief,
      'get': a4get?.brief,
      'status': rowA4?['status'],
    });
  }

  await c.endLives();
  await c.restoreSeller1Published();
  await c.dumpAll('pass2.json');
  stdout.writeln(
    'PASS2 probes=${c.probes.length} findings=${c.findings.length}',
  );
}
