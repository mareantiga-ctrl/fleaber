/// RED TEAM CEGO DL pass2b — A1–A4 com B2 (quota checkout B1 429).
import 'dart:io';
import '_rtdl.dart';

bool looksPaidCopy(HttpHit? h) {
  final t = (h?.body ?? '').toLowerCase();
  return t.contains('pagamento recebido') ||
      t.contains('pagamento confirmado') ||
      t.contains('"status":"pago"');
}

Future<void> main() async {
  final c = Rtdl.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.restoreSeller1Published();

  final s1 = c.sellerId!;
  final b2 = c.buyer2Id!;
  const price = 12.0;

  final pidA = await c.createProduct(
    seller: s1,
    title: '$prefix b2-a3',
    qty: 4,
    price: price,
  );
  final pidB = await c.createProduct(
    seller: s1,
    title: '$prefix b2-a2',
    qty: 4,
    price: price,
  );
  if (pidA == null || pidB == null) {
    stderr.writeln('sku fail');
    exit(2);
  }
  final oidA = await c.insertOrder(
    productId: pidA,
    buyer: b2,
    seller: s1,
    price: price,
  );
  final oidB = await c.insertOrder(
    productId: pidB,
    buyer: b2,
    seller: s1,
    price: price,
  );
  if (oidA == null || oidB == null) {
    stderr.writeln('order fail');
    exit(2);
  }

  Future<HttpHit> ck(
    String oid,
    String pid, {
    Object? amount = 1,
    Map<String, Object?> extra = const {},
  }) {
    return c.checkout(
      orderId: oid,
      buyer: b2,
      jwt: c.buyer2Jwt,
      amount: amount,
      productId: pid,
      seller: s1,
      extra: extra,
    );
  }

  final ckA = await ck(oidA, pidA, amount: 1, extra: {
    'total': 50,
    'server_amount_cents': '50',
  });
  c.note('b2.ckA', 'B2 checkout amount=1', ckA, lens: 'DL1');
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
        'B2 POST checkout amount=1 total=50 server_amount_cents=50 vs SKU 12,00€',
    http: ckA,
    stripeBd: {
      'sid': sidA,
      'server_amount_cents': quoted,
      'amount_total': stripeAmt,
      'price_total': (await c.orderRow(oidA))?['price_total'],
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
      title: 'Checkout usou amount do cliente em vez da quote servidor',
      actor: 'B2 JWT',
      pre: 'SKU 12,00€; body amount=1',
      repro: 'POST create-payment-intent {amount:1,total:50}',
      expected: 'server_amount_cents ≥ 1200',
      obtained: ckA.brief,
    );
  } else if (ckA.ok) {
    c.block('A3.amount', 'DL1', 'quote servidor, body.amount ignorado', {
      'quoted': quoted,
      'amount_total': stripeAmt,
    });
  } else {
    c.skip('A3', 'DL1', 'checkout B2 falhou', ckA);
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
    payload: 'GET unpaid session $sidA',
    http: a1get ?? ckA,
    stripeBd: {
      'status': rowA1?['status'],
      'amount_paid_cents': rowA1?['amount_paid_cents'],
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
      pre: 'Session unpaid',
      repro: 'GET create-payment-intent?checkout_return=success',
      expected: 'não pago',
      obtained: {'get': a1get?.brief, 'row': rowA1},
    );
  } else if (sidA != null) {
    c.block('A1.unpaid', 'DL1', 'GET settle unpaid não creditou', {
      'get': a1get?.brief,
      'status': rowA1?['status'],
    });
  }

  final ckB = await ck(oidB, pidB, amount: 99999);
  final sidB = ckB.sessionId;
  c.note('b2.ckB', 'B2 checkout amount=99999', ckB, lens: 'DL1');

  final live = await c.insertLive(seller: s1, title: '$prefix b2-tip');
  HttpHit? tipCk;
  if (live != null) {
    tipCk = await c.tipCheckout(
      liveId: live,
      seller: s1,
      amountEur: 2,
      jwt: c.buyer2Jwt,
    );
    if (tipCk.tipId != null) c.createdTipIds.add(tipCk.tipId!);
  }
  final tipSid = tipCk?.sessionId;

  final getTipOnOrder =
      tipSid == null ? null : await c.settleGet(tipSid);
  final getOrderOnTip =
      sidB == null ? null : await c.tipSettleGet(sidB);
  final rowA2 = await c.orderRow(oidA);
  final rowB2 = await c.orderRow(oidB);
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
      c.orderPaid(rowB2) ||
      tipSt == 'paid' ||
      tipSt == 'settled' ||
      looksPaidCopy(getTipOnOrder) ||
      looksPaidCopy(getOrderOnTip);
  c.probe(
    id: 'A2',
    edgeRpc: 'GET settle session_id alheio tip↔order',
    payload:
        'GET payment-intent?session_id=cs_tip; GET tip-checkout?session_id=cs_order',
    http: {
      'ckB': ckB.brief,
      'tip': tipCk?.brief,
      'tipOnOrder': getTipOnOrder?.brief,
      'orderOnTip': getOrderOnTip?.brief,
    },
    stripeBd: {
      'sidA': sidA,
      'sidB': sidB,
      'tipSid': tipSid,
      'statusA': rowA2?['status'],
      'statusB': rowB2?['status'],
      'tipStatus': tipSt,
      'ckB_quoted': ckB.map?['server_amount_cents'],
      'ckB_total': ckB.map?['amount_total'],
    },
    result: (sidB == null && tipSid == null)
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
      title: 'session_id alheio liquidou tip ou encomenda',
      actor: 'anon GET',
      pre: 'GET settle lê metadata da Session',
      repro: 'cruzar cs_ tip e cs_ order nos dois Edges',
      expected: 'unpaid / pending',
      obtained: {
        'A': rowA2,
        'B': rowB2,
        'tip': tipSt,
        'tipOnOrder': getTipOnOrder?.brief,
        'orderOnTip': getOrderOnTip?.brief,
      },
    );
  } else {
    c.block('A2.alien', 'DL1', 'session alheia não creditou', {
      'statusA': rowA2?['status'],
      'statusB': rowB2?['status'],
      'tip': tipSt,
      'tipOnOrder': getTipOnOrder?.brief,
      'orderOnTip': getOrderOnTip?.brief,
    });
  }

  final ckReuse = await ck(oidA, pidA, amount: 1);
  final sidReuse = ckReuse.sessionId;
  final reusedSame = sidA != null && sidReuse == sidA;
  final a4get = sidA == null ? null : await c.settleGet(sidA);
  final deadGet =
      await c.settleGet('cs_test_deaddeaddeaddeaddeadRTDL1612xx');
  final rowA4 = await c.orderRow(oidA);
  final a4credited = c.orderPaid(rowA4) || looksPaidCopy(a4get);
  final dualOpen = ckReuse.ok &&
      sidReuse != null &&
      sidA != null &&
      sidReuse != sidA;
  c.probe(
    id: 'A4',
    edgeRpc: 'create-payment-intent reuse + GET dead cs_',
    payload: '2.º POST mesma order; GET unpaid; GET cs_test_dead…',
    http: {
      'reuse': ckReuse.brief,
      'getUnpaid': a4get?.brief,
      'deadGet': deadGet.brief,
    },
    stripeBd: {
      'sidA': sidA,
      'sidReuse': sidReuse,
      'reusedSame': reusedSame,
      'status': rowA4?['status'],
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
          ? '2.º checkout abriu Session distinta'
          : 'GET settle reuse/dead creditou',
      actor: 'B2 + anon GET',
      pre: 'sem sk_test_ expire; claim deve reuse cs_ open',
      repro: 'POST 2×; GET settle; GET cs_ morta',
      expected: 'mesmo sid; unpaid; dead 400',
      obtained: {
        'sidA': sidA,
        'sidReuse': sidReuse,
        'get': a4get?.brief,
        'dead': deadGet.brief,
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
  await c.dumpAll('pass2b.json');
  stdout.writeln(
    'PASS2b probes=${c.probes.length} findings=${c.findings.length} sidA=$sidA',
  );
}
