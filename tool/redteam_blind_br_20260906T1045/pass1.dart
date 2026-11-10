/// RED TEAM CEGO BR pass1 — variantes novas pós-BLBQ marketplace.
/// Não contar exactos: AB∥AC dual Session · hífen+compact mesma linha · detach offer.
import 'dart:io';

import '_rtbr.dart';

Future<void> main() async {
  final c = Rtbr.fromEnv(loadEnv());
  stdout.writeln('BR pass1 staging=${c.url} prefix=$prefix');
  if (c.stripeTestKey == null) {
    stdout.writeln('WARN no sk_test_ — Stripe retrieve/expire/pay limitado');
  }
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('actors', 'ids', {
    'b': c.buyerId,
    's': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
  });
  final wallets0 = await c.wallets();
  c.note('BR8.wallet.pre', 'baseline', wallets0, lens: 'BR8');

  await br1CurrencyUnicode(c);
  await br1UnitAmountString(c);
  await br1AmountStringUnderpay(c);

  await br2TripleBagIntersect(c);
  await br2HyphenCompactSameLineNotCounted(c);
  await br2AbAcDualNotCounted(c);
  await br2BagWithPago(c);
  await br2ClaimTokenRace(c);
  await br2MetadataProductIdsReorder(c);
  await br2SessionReopenAfterExpire(c);

  await br3BundlePatchTotal(c);
  await br3OfferUnicodeQty(c);
  await br3DetachOfferNotCounted(c);

  await br4SettleOrphan(c);
  await br4CheckoutAfterCaptured(c);

  await br5StockOneTwoBags(c);
  await br5JwtQtyUnicode(c);

  await br6ParallelClaimSingle(c);
  await br6ParallelTripleBag(c);

  await br7B2PaysABag(c);
  await br7Seller2Refund(c);
  await br7AnonCheckout(c);

  final wallets1 = await c.wallets();
  c.note('BR8.wallet.post', 'após probes (sem captura TEST nesta pass se unpaid)', {
    'pre': wallets0,
    'post': wallets1,
  }, lens: 'BR8');
  if (wallets1['buyer'] != wallets0['buyer'] ||
      wallets1['seller'] != wallets0['seller']) {
    c.hold(
      id: 'BR8-WALLET-DELTA-UNPAID',
      lens: 'BR8',
      severity: 'P0',
      title: 'Δwallet sem captura Stripe TEST',
      actor: 'observação',
      pre: 'probes checkout unpaid',
      repro: 'SELECT wallets',
      expected: wallets0,
      obtained: wallets1,
    );
  } else {
    c.block('BR8-WALLET-DELTA-UNPAID', 'BR8', 'wallets inalteradas', wallets1);
  }

  await c.dumpAll();
  stdout.writeln(
    'DONE findings=${c.findings.length} blocked=${c.blocked.length} notes=${c.notes.length}',
  );
}

Map<String, Object?> bagLine(String orderId, String productId) => {
      'order_id': orderId,
      'product_id': productId,
    };

Future<List<String>> openSessionIds(Rtbr c, List<String> orderIds) async {
  final ids = <String>{};
  for (final oid in orderIds) {
    final row = await c.orderRow(oid);
    final sid = (row?['stripe_checkout_session_id'] ?? '').toString().trim();
    if (sid.startsWith('cs_')) ids.add(sid);
  }
  if (c.stripeTestKey == null) return ids.toList();
  final open = <String>[];
  for (final sid in ids) {
    final s = await c.stripeSession(sid);
    final st = s.map?['status']?.toString();
    if (st == 'open') open.add(sid);
  }
  return open;
}

bool underpay(HttpHit ck, int expect, [int slack = 40]) =>
    ck.ok && ck.amountTotal != null && ck.amountTotal! + slack < expect;

/// BR1 — currency NBSP / ZWJ / `EUR ` (não AB3 USD).
Future<void> br1CurrencyUnicode(Rtbr c) async {
  const lens = 'BR1';
  final pid = await c.createProduct(price: 12, qty: 3, title: '$prefix-cur');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 12);
  if (oid == null) return;
  final expect = expectedQuoteCents(unitEur: 12);
  final variants = <String, Object?>{
    'EUR_space': 'EUR ',
    'nbsp': 'eur\u00A0',
    'zwj': 'eur\u200D',
    'zwsp': 'eur\u200B',
    'nfd': 'e\u0300ur',
    'fullwidth': 'ｅｕｒ',
    'EUR': 'EUR',
  };
  for (final e in variants.entries) {
    final ck = await c.checkout(
      orderId: oid,
      currency: e.value,
      amount: 50,
    );
    c.note('BR1.CUR.${e.key}', 'currency=${e.key}',
        '${ck.brief} amt=${ck.amountTotal} expect=$expect',
        lens: lens);
    if (underpay(ck, expect)) {
      c.hold(
        id: 'BR1-CURRENCY-${e.key.toUpperCase()}',
        lens: lens,
        severity: 'P0',
        title: 'Currency ${e.key} criou Session abaixo do contrato',
        actor: 'buyer JWT',
        pre: 'order 12€ selada',
        repro: 'POST create-payment-intent currency=${e.key}',
        expected: expect,
        obtained: ck.amountTotal,
        evidence: {'session': ck.sessionId, 'status': ck.status},
      );
    } else if (ck.ok && ck.amountTotal == expect) {
      c.block('BR1-CURRENCY-${e.key.toUpperCase()}', lens,
          'EUR Session ao contrato (trim/allow)', ck.brief);
    } else {
      c.block('BR1-CURRENCY-${e.key.toUpperCase()}', lens,
          'bloqueado ou não underpay', ck.brief);
    }
  }
}

/// BR1 — `unit_amount` string no body (campo extra; Edge constrói line_items).
Future<void> br1UnitAmountString(Rtbr c) async {
  const lens = 'BR1';
  final pid = await c.createProduct(price: 18, qty: 2, title: '$prefix-ua');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 18);
  if (oid == null) return;
  final expect = expectedQuoteCents(unitEur: 18);
  final ck = await c.checkoutRaw({
    'buyer_id': c.buyerId,
    'order_id': oid,
    'amount': 50,
    'currency': 'eur',
    'shipping_method': 'mao',
    'unit_amount': '1',
    'line_items': [
      {
        'price_data': {'currency': 'eur', 'unit_amount': '1'},
        'quantity': 1
      }
    ],
  });
  c.note('BR1.UA.str', 'unit_amount string extra',
      '${ck.brief} amt=${ck.amountTotal} expect=$expect',
      lens: lens);
  if (underpay(ck, expect)) {
    c.hold(
      id: 'BR1-UNIT-AMOUNT-STRING',
      lens: lens,
      severity: 'P0',
      title: 'Body unit_amount string baixou Session',
      actor: 'buyer JWT',
      pre: 'order 18€',
      repro: 'POST CPI unit_amount="1" + line_items',
      expected: expect,
      obtained: ck.amountTotal,
    );
  } else {
    c.block('BR1-UNIT-AMOUNT-STRING', lens, 'unit_amount extra ignorado',
        'amt=${ck.amountTotal} expect=$expect ${ck.brief}');
  }
}

Future<void> br1AmountStringUnderpay(Rtbr c) async {
  const lens = 'BR1';
  final pid = await c.createProduct(price: 22, qty: 2, title: '$prefix-amtstr');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 22);
  if (oid == null) return;
  final expect = expectedQuoteCents(unitEur: 22);
  for (final amt in ['1', '50', '1e1', '0x32']) {
    final ck = await c.checkout(orderId: oid, amount: amt);
    c.note('BR1.AMT.$amt', 'amount string',
        '${ck.brief} amt=${ck.amountTotal}', lens: lens);
    if (underpay(ck, expect)) {
      c.hold(
        id: 'BR1-AMOUNT-STRING-$amt',
        lens: lens,
        severity: 'P0',
        title: 'amount="$amt" Session abaixo do contrato',
        actor: 'buyer JWT',
        pre: 'order 22€',
        repro: 'POST CPI amount string',
        expected: expect,
        obtained: ck.amountTotal,
      );
    }
  }
  c.block('BR1-AMOUNT-STRING', lens, 'strings não underpay (ver notes)', expect);
}

/// BR2 — 3 sacos A∩B∩C (variante nova, não AB∥AC exact).
Future<void> br2TripleBagIntersect(Rtbr c) async {
  const lens = 'BR2';
  final pa = await c.createProduct(price: 10, qty: 2, title: '$prefix-A');
  final pb = await c.createProduct(price: 11, qty: 2, title: '$prefix-B');
  final pc = await c.createProduct(price: 12, qty: 2, title: '$prefix-C');
  if (pa == null || pb == null || pc == null) return;
  final oa = await c.insertOrder(productId: pa, jwt: c.buyerJwt, price: 10);
  final ob = await c.insertOrder(productId: pb, jwt: c.buyerJwt, price: 11);
  final oc = await c.insertOrder(productId: pc, jwt: c.buyerJwt, price: 12);
  if (oa == null || ob == null || oc == null) return;
  final ckAb = await c.checkoutBag(lines: [
    bagLine(oa, pa),
    bagLine(ob, pb),
  ]);
  final ckBc = await c.checkoutBag(lines: [
    bagLine(ob, pb),
    bagLine(oc, pc),
  ]);
  final ckCa = await c.checkoutBag(lines: [
    bagLine(oc, pc),
    bagLine(oa, pa),
  ]);
  final sids = {
    ckAb.sessionId,
    ckBc.sessionId,
    ckCa.sessionId,
  }.whereType<String>().where((s) => s.startsWith('cs_')).toSet();
  final open = await openSessionIds(c, [oa, ob, oc]);
  c.note('BR2.TRIPLE.seq', 'AB then BC then CA', {
    'ab': ckAb.brief,
    'bc': ckBc.brief,
    'ca': ckCa.brief,
    'unique_sids': sids.toList(),
    'open_on_orders': open,
  }, lens: lens);
  if (open.length > 1) {
    c.hold(
      id: 'BR2-TRIPLE-BAG-INTERSECT',
      lens: lens,
      severity: 'P1',
      title: '3 sacos A∩B∩C deixaram >1 Session aberta nas orders',
      actor: 'buyer JWT',
      pre: '3 SKUs / 3 orders; bags AB, BC, CA sequenciais',
      repro: '3× POST CPI bag_checkout',
      expected: '≤1 cs_ open (expire overlap)',
      obtained: open,
      evidence: {'unique_returned': sids.toList()},
    );
  } else {
    c.block('BR2-TRIPLE-BAG-INTERSECT', lens, '≤1 Session aberta após 3 sacos',
        'open=$open returned=${sids.length}');
  }
}

/// Exact BF: hífen+compact mesma linha — NÃO CONTAR.
Future<void> br2HyphenCompactSameLineNotCounted(Rtbr c) async {
  const lens = 'BR2';
  final p1 = await c.createProduct(price: 9, qty: 2, title: '$prefix-hc1');
  final p2 = await c.createProduct(price: 9, qty: 2, title: '$prefix-hc2');
  if (p1 == null || p2 == null) return;
  final o1 = await c.insertOrder(productId: p1, jwt: c.buyerJwt, price: 9);
  final o2 = await c.insertOrder(productId: p2, jwt: c.buyerJwt, price: 9);
  if (o1 == null || o2 == null) return;
  final compact = o1.replaceAll('-', '');
  final expect2 = expectedQuoteCents(unitEur: 9) +
      expectedQuoteCents(unitEur: 9) -
      protectionFeeCents(900, 0); // 2 items + 1 prot? bag sums items then 1 prot
  final items = 900 + 900;
  final expectBag = items + protectionFeeCents(items, 0);
  final ck = await c.checkoutBag(lines: [
    bagLine(o1, p1),
    {'order_id': compact, 'product_id': p1},
    bagLine(o2, p2),
  ]);
  c.note('BR2.HYPHEN.exact', 'hífen+compact mesma linha (NÃO CONTAR)', {
    'ck': ck.brief,
    'amt': ck.amountTotal,
    'expect_bag_2lines': expectBag,
    'expect_if_dup_counted': expectBag + 900,
  }, lens: lens);
  if (ck.ok &&
      ck.amountTotal != null &&
      ck.amountTotal! >= expectBag + 800) {
    c.note('BR2.HYPHEN.would_be_finding', 'dup linha cobrada — exact BF, não CONTAGEM',
        ck.amountTotal,
        lens: lens);
  } else {
    c.block('BR2-HYPHEN-COMPACT-EXACT', lens, 'dedup hífen/compact (exact, n/c)',
        'amt=${ck.amountTotal} expect2=$expectBag');
  }
}

/// Exact BFBK AB∥AC — NÃO CONTAR.
Future<void> br2AbAcDualNotCounted(Rtbr c) async {
  const lens = 'BR2';
  final pa = await c.createProduct(price: 8, qty: 2, title: '$prefix-ab');
  final pb = await c.createProduct(price: 8, qty: 2, title: '$prefix-bb');
  final pc = await c.createProduct(price: 8, qty: 2, title: '$prefix-cb');
  if (pa == null || pb == null || pc == null) return;
  final oa = await c.insertOrder(productId: pa, jwt: c.buyerJwt, price: 8);
  final ob = await c.insertOrder(productId: pb, jwt: c.buyerJwt, price: 8);
  final oc = await c.insertOrder(productId: pc, jwt: c.buyerJwt, price: 8);
  if (oa == null || ob == null || oc == null) return;
  final hits = await parallel([
    c.checkoutBag(lines: [bagLine(oa, pa), bagLine(ob, pb)]),
    c.checkoutBag(lines: [bagLine(oa, pa), bagLine(oc, pc)]),
  ]);
  final sids = hits
      .map((h) => h.sessionId)
      .whereType<String>()
      .where((s) => s.startsWith('cs_'))
      .toSet();
  var openCount = 0;
  if (c.stripeTestKey != null) {
    for (final s in sids) {
      final st = await c.stripeSession(s);
      if (st.map?['status'] == 'open') openCount++;
    }
  } else {
    openCount = sids.length;
  }
  c.note('BR2.ABAC.exact', 'AB∥AC dual (NÃO CONTAR)', {
    'h0': hits[0].brief,
    'h1': hits[1].brief,
    'sids': sids.toList(),
    'open': openCount,
  }, lens: lens);
  c.block('BR2-AB-AC-EXACT', lens, 'exact BFBK AB∥AC — fora da CONTAGEM',
      'open=$openCount sids=$sids');
}

/// BR2 — saco com order já pago.
Future<void> br2BagWithPago(Rtbr c) async {
  const lens = 'BR2';
  final pPaid = await c.createProduct(price: 14, qty: 2, title: '$prefix-pago');
  final pNew = await c.createProduct(price: 14, qty: 2, title: '$prefix-sib');
  if (pPaid == null || pNew == null) return;
  final oPaid = await c.insertOrder(productId: pPaid, jwt: c.buyerJwt, price: 14);
  final oNew = await c.insertOrder(productId: pNew, jwt: c.buyerJwt, price: 14);
  if (oPaid == null || oNew == null) return;

  var paidViaStripe = false;
  final ck1 = await c.checkout(orderId: oPaid);
  if (ck1.ok && ck1.sessionId != null && c.stripeTestKey != null) {
    final sess = await c.stripeSession(ck1.sessionId!, expandPi: true);
    final piRaw = sess.map?['payment_intent'];
    final pi = piRaw is Map
        ? piRaw['id']?.toString()
        : piRaw?.toString();
    if (pi != null && pi.startsWith('pi_')) {
      final conf = await c.stripeConfirmPi(pi);
      c.note('BR2.PAGO.confirm', 'confirm PI', conf.brief, lens: lens);
      await c.settleGet(ck1.sessionId!);
      paidViaStripe = true;
    }
  }
  if (!paidViaStripe) {
    // fixture: estado pago (service_role) — actor do exploit continua JWT bag
    await c.rest('PATCH', 'orders?id=eq.$oPaid', service: true, body: {
      'status': 'pago',
      'amount_paid_cents': 1540,
      'stripe_payment_intent_id': 'pi_RTBR_fixture_pago',
    }, prefer: 'return=minimal');
    c.note('BR2.PAGO.fixture', 'service_role marcou pago (sem captura real)', oPaid,
        lens: lens);
  }
  final after = await c.orderRow(oPaid);
  final bag = await c.checkoutBag(lines: [
    bagLine(oPaid, pPaid),
    bagLine(oNew, pNew),
  ]);
  c.note('BR2.PAGO.bag', 'bag inclui pago', {
    'paid_status': after?['status'],
    'pi': after?['stripe_payment_intent_id'],
    'bag': bag.brief,
    'sid': bag.sessionId,
  }, lens: lens);
  if (bag.ok && bag.sessionId != null) {
    c.hold(
      id: 'BR2-BAG-INCLUDES-PAGO',
      lens: lens,
      severity: 'P1',
      title: 'Saco aceita linha já paga e cria Session',
      actor: 'buyer JWT',
      pre: 'order A status=pago (+ PI); order B pendente',
      repro: 'POST CPI bag_checkout A+B',
      expected: '400 already captured / status cannot start payment',
      obtained: bag.brief,
      evidence: {'paid_row': after, 'via_stripe': paidViaStripe},
    );
  } else {
    c.block('BR2-BAG-INCLUDES-PAGO', lens, 'saco recusou linha paga', bag.brief);
  }
}

/// BR2 — claim token race (RPC JWT + PATCH claiming: + paralelo).
Future<void> br2ClaimTokenRace(Rtbr c) async {
  const lens = 'BR2';
  final pid = await c.createProduct(price: 16, qty: 3, title: '$prefix-claim');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 16);
  if (oid == null) return;

  final rpcJwt = await c.rpc('batata_claim_checkout_session_slot', {
    'p_order_id': oid,
    'p_claim_token': 'claiming:rtbr-jwt-attack-token',
  }, jwt: c.buyerJwt);
  c.note('BR2.CLAIM.rpc.jwt', 'JWT RPC claim', rpcJwt.brief, lens: lens);
  if (rpcJwt.ok) {
    c.hold(
      id: 'BR2-CLAIM-RPC-JWT',
      lens: lens,
      severity: 'P1',
      title: 'JWT executa batata_claim_checkout_session_slot',
      actor: 'buyer JWT',
      pre: 'GRANT esperado só service_role',
      repro: 'POST rpc/batata_claim_checkout_session_slot',
      expected: '403',
      obtained: rpcJwt.brief,
    );
  } else {
    c.block('BR2-CLAIM-RPC-JWT', lens, 'RPC claim 403 JWT', rpcJwt.brief);
  }

  final patch = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'stripe_checkout_session_id': 'claiming:rtbr-stolen'},
  );
  c.note('BR2.CLAIM.patch', 'JWT PATCH claiming:', patch.brief, lens: lens);
  if (patch.ok) {
    final row = await c.orderRow(oid);
    if ((row?['stripe_checkout_session_id'] ?? '').toString().startsWith('claiming:')) {
      c.hold(
        id: 'BR2-CLAIM-PATCH-JWT',
        lens: lens,
        severity: 'P1',
        title: 'JWT grava claiming: no slot da Session',
        actor: 'buyer JWT',
        pre: 'order pendente',
        repro: 'PATCH orders.stripe_checkout_session_id=claiming:…',
        expected: '403 / imutável',
        obtained: row?['stripe_checkout_session_id'],
      );
    }
  } else {
    c.block('BR2-CLAIM-PATCH-JWT', lens, 'PATCH slot bloqueado', patch.brief);
  }
}

/// BR2 — metadata bag_product_ids reordenados (request + Stripe PATCH).
Future<void> br2MetadataProductIdsReorder(Rtbr c) async {
  const lens = 'BR2';
  final p1 = await c.createProduct(price: 13, qty: 2, title: '$prefix-m1');
  final p2 = await c.createProduct(price: 17, qty: 2, title: '$prefix-m2');
  if (p1 == null || p2 == null) return;
  final o1 = await c.insertOrder(productId: p1, jwt: c.buyerJwt, price: 13);
  final o2 = await c.insertOrder(productId: p2, jwt: c.buyerJwt, price: 17);
  if (o1 == null || o2 == null) return;
  final swapped = await c.checkoutBag(lines: [
    {'order_id': o1, 'product_id': p2},
    {'order_id': o2, 'product_id': p1},
  ]);
  c.note('BR2.META.swap.req', 'bag_lines product_ids trocados', swapped.brief,
      lens: lens);
  if (swapped.ok) {
    c.hold(
      id: 'BR2-BAG-PRODUCT-SWAP-REQUEST',
      lens: lens,
      severity: 'P1',
      title: 'Saco aceita product_id ≠ order.product_id',
      actor: 'buyer JWT',
      pre: '2 orders SKUs distintos',
      repro: 'bag_lines com product_ids cruzados',
      expected: '400 bag product does not match order',
      obtained: swapped.brief,
    );
  } else {
    c.block('BR2-BAG-PRODUCT-SWAP-REQUEST', lens, 'mismatch product_id recusado',
        swapped.brief);
  }

  final okBag = await c.checkoutBag(lines: [
    bagLine(o1, p1),
    bagLine(o2, p2),
  ]);
  if (!okBag.ok || okBag.sessionId == null || c.stripeTestKey == null) {
    c.note('BR2.META.stripe.skip', 'sem Session/sk para reorder metadata',
        okBag.brief,
        lens: lens);
    return;
  }
  final sid = okBag.sessionId!;
  final compactP1 = p1.replaceAll('-', '');
  final compactP2 = p2.replaceAll('-', '');
  final upd = await c.stripeUpdateSessionMeta(sid, {
    'bag_product_ids': '$compactP2,$compactP1',
  });
  c.note('BR2.META.stripe.patch', 'Stripe metadata product_ids reversed',
      upd.brief,
      lens: lens);
  final settle = await c.settleGet(sid);
  c.note('BR2.META.settle', 'GET settle após reorder (session unpaid)',
      settle.brief,
      lens: lens);
  // unpaid settle não deve marcar pago
  final r1 = await c.orderRow(o1);
  final r2 = await c.orderRow(o2);
  if (r1?['status'] == 'pago' || r2?['status'] == 'pago') {
    c.hold(
      id: 'BR2-META-REORDER-SETTLE-UNPAID',
      lens: lens,
      severity: 'P0',
      title: 'Settle unpaid após metadata reorder marcou pago',
      actor: 'GET settle (anon URL) + sk_test metadata',
      pre: 'saco aberto; metadata bag_product_ids invertidos',
      repro: 'GET create-payment-intent?checkout_return=success',
      expected: 'não pago',
      obtained: {'o1': r1?['status'], 'o2': r2?['status']},
    );
  } else {
    c.block('BR2-META-REORDER-UNPAID', lens, 'settle unpaid não liquidou',
        '${r1?['status']}/${r2?['status']} ${settle.brief}');
  }
}

/// BR2 — Session reopen pós-expire.
Future<void> br2SessionReopenAfterExpire(Rtbr c) async {
  const lens = 'BR2';
  final pid = await c.createProduct(price: 15, qty: 2, title: '$prefix-exp');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 15);
  if (oid == null) return;
  final ck1 = await c.checkout(orderId: oid);
  if (!ck1.ok || ck1.sessionId == null) {
    return c.skip('BR2-REOPEN', lens, 'sem Session', ck1.brief);
  }
  final sid1 = ck1.sessionId!;
  HttpHit? exp;
  if (c.stripeTestKey != null) {
    exp = await c.stripeExpire(sid1);
    c.note('BR2.EXP.stripe', 'expire sid1', exp.brief, lens: lens);
  }
  final ck2 = await c.checkout(orderId: oid);
  c.note('BR2.EXP.ck2', 'checkout após expire', {
    'sid1': sid1,
    'ck2': ck2.brief,
    'sid2': ck2.sessionId,
    'reused': ck2.reused,
  }, lens: lens);
  if (ck2.ok && ck2.reused && ck2.sessionId == sid1) {
    c.hold(
      id: 'BR2-SESSION-REOPEN-AFTER-EXPIRE',
      lens: lens,
      severity: 'P1',
      title: 'Checkout reutilizou Session já expirada',
      actor: 'buyer JWT',
      pre: 'cs_ open → Stripe expire',
      repro: 'POST CPI de novo',
      expected: 'nova cs_ ou 400; reused=false',
      obtained: ck2.brief,
    );
  } else if (ck2.ok &&
      ck2.sessionId != null &&
      ck2.sessionId != sid1 &&
      !ck2.reused) {
    c.block('BR2-SESSION-REOPEN-AFTER-EXPIRE', lens,
        'nova Session após expire (não reopen)', ck2.sessionId);
  } else {
    c.block('BR2-SESSION-REOPEN-AFTER-EXPIRE', lens, 'não reopen exact',
        ck2.brief);
  }

  final settleOld = await c.settleGet(sid1);
  final row = await c.orderRow(oid);
  c.note('BR2.EXP.settle_old', 'settle da Session expirada', {
    'settle': settleOld.brief,
    'status': row?['status'],
  }, lens: lens);
  if (row?['status'] == 'pago') {
    c.hold(
      id: 'BR2-SETTLE-EXPIRED-MARKS-PAGO',
      lens: lens,
      severity: 'P0',
      title: 'GET settle de Session expirada marcou pago',
      actor: 'anon GET success URL',
      pre: 'Session expired unpaid',
      repro: 'GET checkout_return=success&session_id=expired',
      expected: 'não pago',
      obtained: row?['status'],
    );
  }
}

/// BR3 — bundle PATCH total (buyer + seller).
Future<void> br3BundlePatchTotal(Rtbr c) async {
  const lens = 'BR3';
  final p1 = await c.createProduct(price: 20, qty: 2, title: '$prefix-bun1');
  final p2 = await c.createProduct(price: 20, qty: 2, title: '$prefix-bun2');
  if (p1 == null || p2 == null) return;
  final ins = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_ids': [p1, p2],
    'status': 'pending',
    'total_eur': 0.5,
    'discount_pct': 90,
  });
  final bid = ins.firstId;
  if (bid != null) c.createdBundleIds.add(bid);
  c.note('BR3.BUN.ins', 'INSERT bundle total 0.50', ins.brief, lens: lens);
  if (bid == null) {
    return c.block('BR3-BUNDLE-PATCH-TOTAL', lens, 'INSERT bundle falhou',
        ins.brief);
  }
  final acc = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.sellerJwt,
    body: {'status': 'accepted'},
  );
  c.note('BR3.BUN.acc', 'seller accept', acc.brief, lens: lens);
  final patchBuyer = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.buyerJwt,
    body: {'total_eur': 0.5},
  );
  final patchSeller = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.sellerJwt,
    body: {'total_eur': 0.5, 'discount_pct': 90},
  );
  c.note('BR3.BUN.patch', 'PATCH total 0.50', {
    'buyer': patchBuyer.brief,
    'seller': patchSeller.brief,
  }, lens: lens);
  final row = (await c.rest(
    'GET',
    'product_bundles?id=eq.$bid&select=id,status,total_eur,discount_pct,subtotal_eur',
    service: true,
  ))
      .map;
  final o1 = await c.insertOrder(
    productId: p1,
    jwt: c.buyerJwt,
    price: 0.5,
    bundleId: bid,
  );
  final o2 = await c.insertOrder(
    productId: p2,
    jwt: c.buyerJwt,
    price: 0.5,
    bundleId: bid,
  );
  HttpHit? ck;
  if (o1 != null && o2 != null) {
    ck = await c.checkoutBag(lines: [bagLine(o1, p1), bagLine(o2, p2)]);
  }
  final total = numOf(row?['total_eur']);
  c.note('BR3.BUN.ck', 'checkout conjunto após PATCH', {
    'row': row,
    'ck': ck?.brief,
    'amt': ck?.amountTotal,
  }, lens: lens);
  final expectCat = 4000 + protectionFeeCents(4000, 0);
  if (ck != null && ck.ok && underpay(ck, expectCat - 200, 200)) {
    c.hold(
      id: 'BR3-BUNDLE-PATCH-TOTAL',
      lens: lens,
      severity: 'P0',
      title: 'PATCH total_eur cola e checkout cobra abaixo do catálogo',
      actor: 'buyer/seller JWT',
      pre: 'bundle 2×20€',
      repro: 'PATCH total_eur=0.50; bag checkout',
      expected: '≥ catálogo 40€+prot',
      obtained: ck.amountTotal,
      evidence: {'bundle': row},
    );
  } else if (total != null && total <= 1.0 && (row?['status'] == 'accepted')) {
    c.hold(
      id: 'BR3-BUNDLE-PATCH-TOTAL-STUCK',
      lens: lens,
      severity: 'P1',
      title: 'total_eur hostil persistiu no conjunto aceite',
      actor: 'JWT',
      pre: 'bundle accepted',
      repro: 'PATCH total_eur=0.50',
      expected: 'rewrite catálogo',
      obtained: row,
    );
  } else {
    c.block('BR3-BUNDLE-PATCH-TOTAL', lens, 'total reescrito / checkout catálogo',
        'total=$total amt=${ck?.amountTotal} ${ck?.brief}');
  }
}

/// BR3 — offer Unicode qty (coluna extra + order qty unicode + amount fullwidth).
Future<void> br3OfferUnicodeQty(Rtbr c) async {
  const lens = 'BR3';
  final pid = await c.createProduct(price: 30, qty: 3, title: '$prefix-off');
  if (pid == null) return;
  final ins = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': pid,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': 5,
    'list_price': 30,
    'offered_by': 'buyer',
    'status': 'pending',
    'quantity': '９',
  });
  c.note('BR3.OFF.ins', 'offer + quantity fullwidth', ins.brief, lens: lens);
  final oidOffer = ins.firstId;
  if (oidOffer != null) c.createdOfferIds.add(oidOffer);

  final amtFw = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': pid,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': '０．５０',
    'offered_by': 'buyer',
    'status': 'pending',
  });
  c.note('BR3.OFF.amt.fw', 'amount fullwidth', amtFw.brief, lens: lens);

  if (oidOffer != null) {
    await c.rest(
      'PATCH',
      'product_offers?id=eq.$oidOffer',
      jwt: c.sellerJwt,
      body: {
        'status': 'accepted',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }
  final ordU = await c.insertOrderHit(
    productId: pid,
    jwt: c.buyerJwt,
    price: 5,
    qty: 1,
    offerId: oidOffer,
  );
  // qty unicode via raw body
  final ordQty = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pid,
    'price_total': 5,
    'quantity': '９',
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
    if (oidOffer != null) 'product_offer_id': oidOffer,
  });
  if (ordQty.firstId != null) c.createdOrderIds.add(ordQty.firstId!);
  Map<String, dynamic>? ordURow;
  Map<String, dynamic>? ordQtyRow;
  if (ordU.firstId != null) ordURow = await c.orderRow(ordU.firstId!);
  if (ordQty.firstId != null) ordQtyRow = await c.orderRow(ordQty.firstId!);
  c.note('BR3.OFF.ord', 'order qty unicode / offer', {
    'ordU': ordU.brief,
    'ordQty': ordQty.brief,
    'contract': ordURow?['contract_unit_cents'],
    'qtyRow': ordQtyRow?['quantity'],
  }, lens: lens);

  final qtyRow = ordQty.firstId != null ? await c.orderRow(ordQty.firstId!) : null;
  final q = numOf(qtyRow?['quantity']);
  if (ordQty.ok && q != null && q > 1 && oidOffer != null) {
    c.hold(
      id: 'BR3-OFFER-UNICODE-QTY',
      lens: lens,
      severity: 'P1',
      title: 'quantity Unicode na order com oferta (>1)',
      actor: 'buyer JWT',
      pre: 'oferta accepted; offer_quantity_must_be_one',
      repro: 'POST orders quantity="９" product_offer_id',
      expected: 'reject / qty=1',
      obtained: qtyRow,
    );
  } else {
    c.block('BR3-OFFER-UNICODE-QTY', lens, 'qty unicode não inflou oferta',
        ordQty.brief);
  }

  if (ordU.firstId != null) {
    final row = await c.orderRow(ordU.firstId!);
    final sealed = numOf(row?['contract_unit_cents']);
    final ck = await c.checkout(orderId: ordU.firstId!);
    final expectOffer = expectedQuoteCents(unitEur: 5);
    final expectCat = expectedQuoteCents(unitEur: 30);
    c.note('BR3.OFF.ck', 'checkout oferta', {
      'sealed': sealed,
      'amt': ck.amountTotal,
      'expectOffer': expectOffer,
      'expectCat': expectCat,
    }, lens: lens);
    if (ck.ok &&
        ck.amountTotal != null &&
        ck.amountTotal! < expectCat - 100 &&
        (sealed == null || sealed >= 2000)) {
      // checkout below catalog without sealed offer — finding
      c.hold(
        id: 'BR3-OFFER-CHECKOUT-UNDER-CATALOG',
        lens: lens,
        severity: 'P0',
        title: 'Checkout oferta abaixo do catálogo sem contrato de oferta',
        actor: 'buyer JWT',
        pre: 'produto 30€',
        repro: 'checkout order com product_offer_id',
        expected: expectCat,
        obtained: ck.amountTotal,
      );
    }
  }
}

/// Exact: detach offer — NÃO CONTAR.
Future<void> br3DetachOfferNotCounted(Rtbr c) async {
  const lens = 'BR3';
  final pid = await c.createProduct(price: 25, qty: 2, title: '$prefix-det');
  if (pid == null) return;
  final ins = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': pid,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': 8,
    'offered_by': 'buyer',
    'status': 'pending',
  });
  final off = ins.firstId;
  if (off == null) {
    return c.block('BR3-DETACH-EXACT', lens, 'não criou oferta (exact n/c)',
        ins.brief);
  }
  c.createdOfferIds.add(off);
  await c.rest(
    'PATCH',
    'product_offers?id=eq.$off',
    jwt: c.sellerJwt,
    body: {
      'status': 'accepted',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    },
  );
  final oid = await c.insertOrder(
    productId: pid,
    jwt: c.buyerJwt,
    price: 8,
    offerId: off,
  );
  if (oid == null) return;
  final det = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'product_offer_id': null},
  );
  c.note('BR3.DETACH.exact', 'detach offer (NÃO CONTAR)', det.brief, lens: lens);
  c.block('BR3-DETACH-EXACT', lens, 'exact BFBK detach — fora da CONTAGEM',
      det.brief);
}

/// BR4 — settle orphan (Session A expired / SID alheio).
Future<void> br4SettleOrphan(Rtbr c) async {
  const lens = 'BR4';
  final pid = await c.createProduct(price: 19, qty: 2, title: '$prefix-orph');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 19);
  if (oid == null) return;
  final ck = await c.checkout(orderId: oid);
  final fake = await c.settleGet('cs_test_orphan_rtbr_not_real');
  c.note('BR4.ORPH.fake', 'settle SID inventado', fake.brief, lens: lens);
  final row0 = await c.orderRow(oid);
  if (row0?['status'] == 'pago') {
    c.hold(
      id: 'BR4-SETTLE-FAKE-SID',
      lens: lens,
      severity: 'P0',
      title: 'Settle SID inventado marcou pago',
      actor: 'anon GET',
      pre: 'order pendente',
      repro: 'GET session_id=cs_test_orphan…',
      expected: 'não pago',
      obtained: row0?['status'],
    );
  }
  if (ck.ok && ck.sessionId != null && c.stripeTestKey != null) {
    await c.stripeExpire(ck.sessionId!);
    final s2 = await c.checkout(orderId: oid);
    // settle the expired (orphan) while a new session may exist
    final settleOrphan = await c.settleGet(ck.sessionId!);
    final row = await c.orderRow(oid);
    c.note('BR4.ORPH.expired', 'settle Session expirada com sid novo possível', {
      'old': ck.sessionId,
      'new': s2.sessionId,
      'settle': settleOrphan.brief,
      'status': row?['status'],
      'sid_now': row?['stripe_checkout_session_id'],
    }, lens: lens);
    if (row?['status'] == 'pago') {
      c.hold(
        id: 'BR4-SETTLE-ORPHAN-EXPIRED',
        lens: lens,
        severity: 'P0',
        title: 'Settle da Session órfã/expirada liquidou a order',
        actor: 'anon GET',
        pre: 'sid1 expired; sid2 maybe open',
        repro: 'GET success sid1',
        expected: 'não pago',
        obtained: row,
      );
    } else {
      c.block('BR4-SETTLE-ORPHAN-EXPIRED', lens, 'órfã expirada não liquidou',
          settleOrphan.brief);
    }
  }
}

Future<void> br4CheckoutAfterCaptured(Rtbr c) async {
  const lens = 'BR4';
  final pid = await c.createProduct(price: 21, qty: 2, title: '$prefix-cap');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 21);
  if (oid == null) return;
  await c.rest('PATCH', 'orders?id=eq.$oid', service: true, body: {
    'status': 'pago',
    'amount_paid_cents': 2280,
    'stripe_payment_intent_id': 'pi_RTBR_captured',
  }, prefer: 'return=minimal');
  final ck = await c.checkout(orderId: oid, amount: 50);
  c.note('BR4.CAP.ck', 'checkout após pago fixture', ck.brief, lens: lens);
  if (ck.ok) {
    c.hold(
      id: 'BR4-CHECKOUT-AFTER-PAGO',
      lens: lens,
      severity: 'P1',
      title: '2.ª Session após order já paga',
      actor: 'buyer JWT',
      pre: 'status=pago + PI fixture',
      repro: 'POST CPI',
      expected: '400 already captured',
      obtained: ck.brief,
    );
  } else {
    c.block('BR4-CHECKOUT-AFTER-PAGO', lens, 'bloqueado pós-captura', ck.brief);
  }
}

/// BR5 — stock=1, dois sacos que partilham o SKU (ordens distintas).
Future<void> br5StockOneTwoBags(Rtbr c) async {
  const lens = 'BR5';
  final pShared = await c.createProduct(price: 10, qty: 1, title: '$prefix-stk');
  final pOther = await c.createProduct(price: 10, qty: 2, title: '$prefix-sto');
  if (pShared == null || pOther == null) return;
  final oA = await c.insertOrder(productId: pShared, jwt: c.buyerJwt, price: 10);
  final oB = await c.insertOrder(
    productId: pShared,
    jwt: c.buyerJwt,
    price: 10,
  );
  final oC = await c.insertOrder(productId: pOther, jwt: c.buyerJwt, price: 10);
  c.note('BR5.STOCK.ordB', '2.ª order mesmo SKU stock=1', {
    'oA': oA,
    'oB': oB == null ? 'blocked' : oB,
  }, lens: lens);
  if (oA == null || oC == null) return;
  if (oB != null) {
    final bag1 = await c.checkoutBag(lines: [bagLine(oA, pShared), bagLine(oC, pOther)]);
    final bag2 = await c.checkoutBag(lines: [
      bagLine(oB, pShared),
    ]);
    c.note('BR5.STOCK.bags', 'saco A+C e saco B (mesmo SKU qty1)', {
      'bag1': bag1.brief,
      'bag2': bag2.brief,
    }, lens: lens);
    if (bag1.ok && bag2.ok) {
      c.hold(
        id: 'BR5-STOCK1-TWO-BAG-SESSIONS',
        lens: lens,
        severity: 'P1',
        title: 'Stock=1: duas Sessions de saco/linha no mesmo SKU',
        actor: 'buyer JWT',
        pre: 'qty=1; duas orders hold',
        repro: 'bag A+other e checkout B',
        expected: '2.º bloqueado por stock',
        obtained: {'bag1': bag1.sessionId, 'bag2': bag2.sessionId},
      );
    } else {
      c.block('BR5-STOCK1-TWO-BAG-SESSIONS', lens, '2.º saco/hold bloqueado',
          'b1=${bag1.status} b2=${bag2.status} oB=$oB');
    }
  } else {
    c.block('BR5-STOCK1-TWO-ORDERS', lens, '2.ª order no SKU stock=1 recusada',
        'oA=$oA');
  }
}

Future<void> br5JwtQtyUnicode(Rtbr c) async {
  const lens = 'BR5';
  final pid = await c.createProduct(price: 12, qty: 2, title: '$prefix-qtyu');
  if (pid == null) return;
  final hit = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pid,
    'price_total': 12,
    'quantity': '２',
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  if (hit.firstId != null) c.createdOrderIds.add(hit.firstId!);
  c.note('BR5.QTY.fw', 'order quantity fullwidth ２', hit.brief, lens: lens);
  if (hit.ok && hit.firstId != null) {
    final row = await c.orderRow(hit.firstId!);
    final q = numOf(row?['quantity']);
    final ck = await c.checkout(orderId: hit.firstId!);
    c.note('BR5.QTY.ck', 'checkout qty unicode', {
      'qty': q,
      'contract_qty': row?['contract_qty'],
      'amt': ck.amountTotal,
    }, lens: lens);
    final expect1 = expectedQuoteCents(unitEur: 12, qty: 1);
    if (q != null && q >= 2 && ck.ok && (ck.amountTotal ?? 0) <= expect1 + 10) {
      c.hold(
        id: 'BR5-QTY-UNICODE-UNDERCHARGE',
        lens: lens,
        severity: 'P0',
        title: 'qty Unicode≥2 mas Session cobrou 1 unidade',
        actor: 'buyer JWT',
        pre: 'stock 2; quantity="２"',
        repro: 'POST orders + CPI',
        expected: 'qty=1 ou cobrar 2',
        obtained: {'qty': q, 'amt': ck.amountTotal},
      );
    } else {
      c.block('BR5-QTY-UNICODE', lens, 'qty unicode não undercharge',
          'qty=$q amt=${ck.amountTotal}');
    }
  } else {
    c.block('BR5-QTY-UNICODE', lens, 'INSERT qty fullwidth recusado', hit.brief);
  }
}

/// BR6 — parallel single claim.
Future<void> br6ParallelClaimSingle(Rtbr c) async {
  const lens = 'BR6';
  final pid = await c.createProduct(price: 11, qty: 2, title: '$prefix-par');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 11);
  if (oid == null) return;
  final hits = await parallel([
    c.checkout(orderId: oid),
    c.checkout(orderId: oid),
    c.checkout(orderId: oid),
  ]);
  final sids = hits
      .map((h) => h.sessionId)
      .whereType<String>()
      .where((s) => s.startsWith('cs_'))
      .toSet();
  var open = 0;
  if (c.stripeTestKey != null) {
    for (final s in sids) {
      if ((await c.stripeSession(s)).map?['status'] == 'open') open++;
    }
  } else {
    open = sids.length;
  }
  c.note('BR6.PAR.single', '3× CPI paralelo mesma order', {
    'briefs': hits.map((h) => h.brief).toList(),
    'sids': sids.toList(),
    'open': open,
  }, lens: lens);
  if (open > 1) {
    c.hold(
      id: 'BR6-CLAIM-RACE-THREE-OPEN',
      lens: lens,
      severity: 'P1',
      title: '3 POST paralelos → >1 Session aberta na mesma order',
      actor: 'buyer JWT',
      pre: '1 order',
      repro: 'Future.wait 3× create-payment-intent',
      expected: '1 cs_ open (claim slot)',
      obtained: {'open': open, 'sids': sids.toList()},
    );
  } else {
    c.block('BR6-CLAIM-RACE-THREE-OPEN', lens, 'claim serializou 3 POSTs',
        'open=$open sids=$sids');
  }
}

Future<void> br6ParallelTripleBag(Rtbr c) async {
  const lens = 'BR6';
  final pa = await c.createProduct(price: 7, qty: 2, title: '$prefix-pA');
  final pb = await c.createProduct(price: 7, qty: 2, title: '$prefix-pB');
  final pc = await c.createProduct(price: 7, qty: 2, title: '$prefix-pC');
  if (pa == null || pb == null || pc == null) return;
  final oa = await c.insertOrder(productId: pa, jwt: c.buyerJwt, price: 7);
  final ob = await c.insertOrder(productId: pb, jwt: c.buyerJwt, price: 7);
  final oc = await c.insertOrder(productId: pc, jwt: c.buyerJwt, price: 7);
  if (oa == null || ob == null || oc == null) return;
  final hits = await parallel([
    c.checkoutBag(lines: [bagLine(oa, pa), bagLine(ob, pb)]),
    c.checkoutBag(lines: [bagLine(ob, pb), bagLine(oc, pc)]),
    c.checkoutBag(lines: [bagLine(oc, pc), bagLine(oa, pa)]),
  ]);
  final sids = hits
      .map((h) => h.sessionId)
      .whereType<String>()
      .where((s) => s.startsWith('cs_'))
      .toSet();
  var open = 0;
  if (c.stripeTestKey != null) {
    for (final s in sids) {
      if ((await c.stripeSession(s)).map?['status'] == 'open') open++;
    }
  } else {
    open = sids.length;
  }
  c.note('BR6.PAR.triple', '3 sacos A∩B∩C em paralelo', {
    'briefs': hits.map((h) => h.brief).toList(),
    'sids': sids.toList(),
    'open': open,
    'on_orders': await openSessionIds(c, [oa, ob, oc]),
  }, lens: lens);
  if (open > 1) {
    c.hold(
      id: 'BR6-TRIPLE-BAG-RACE',
      lens: lens,
      severity: 'P1',
      title: 'Corrida 3 sacos A∩B∩C deixou >1 Session Stripe aberta',
      actor: 'buyer JWT',
      pre: '3 orders; bags AB∥BC∥CA',
      repro: 'Future.wait 3× bag_checkout',
      expected: '≤1 cs_ open (overlap expire + claim)',
      obtained: {'open': open, 'sids': sids.toList()},
    );
  } else {
    c.block('BR6-TRIPLE-BAG-RACE', lens, 'corrida 3 sacos ≤1 Session aberta',
        'open=$open');
  }
}

Future<void> br7B2PaysABag(Rtbr c) async {
  const lens = 'BR7';
  final p1 = await c.createProduct(price: 9, qty: 2, title: '$prefix-b2a');
  final p2 = await c.createProduct(price: 9, qty: 2, title: '$prefix-b2b');
  if (p1 == null || p2 == null) return;
  final o1 = await c.insertOrder(productId: p1, jwt: c.buyerJwt, price: 9);
  final o2 = await c.insertOrder(productId: p2, jwt: c.buyerJwt, price: 9);
  if (o1 == null || o2 == null) return;
  final ck = await c.checkoutBag(
    lines: [bagLine(o1, p1), bagLine(o2, p2)],
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  c.note('BR7.B2.bag', 'B2 checkout saco de B1', ck.brief, lens: lens);
  if (ck.ok) {
    c.hold(
      id: 'BR7-B2-CHECKOUT-B1-BAG',
      lens: lens,
      severity: 'P1',
      title: '2.º buyer cria Session no saco de outro',
      actor: 'buyer2 JWT',
      pre: 'orders buyer1',
      repro: 'POST CPI bag buyer_id=B2',
      expected: '400 invalid user / not owner',
      obtained: ck.brief,
    );
  } else {
    c.block('BR7-B2-CHECKOUT-B1-BAG', lens, 'B2 recusado no saco B1', ck.brief);
  }
}

Future<void> br7Seller2Refund(Rtbr c) async {
  const lens = 'BR7';
  final pid = await c.createProduct(price: 10, qty: 1, title: '$prefix-rf');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 10);
  if (oid == null) return;
  final r = await c.refund(oid, jwt: c.seller2Jwt);
  c.note('BR7.S2.refund', 'S2 refund order S1', r.brief, lens: lens);
  if (r.ok) {
    c.hold(
      id: 'BR7-S2-REFUND-FOREIGN',
      lens: lens,
      severity: 'P1',
      title: 'Seller2 reembolsa encomenda de outro vendedor',
      actor: 'seller2 JWT',
      pre: 'order seller1',
      repro: 'POST refund-order',
      expected: '403',
      obtained: r.brief,
    );
  } else {
    c.block('BR7-S2-REFUND-FOREIGN', lens, 'S2 refund 403', r.brief);
  }
}

Future<void> br7AnonCheckout(Rtbr c) async {
  const lens = 'BR7';
  final pid = await c.createProduct(price: 10, qty: 1, title: '$prefix-anon');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 10);
  if (oid == null) return;
  final ck = await c.checkoutRaw({
    'buyer_id': c.buyerId,
    'order_id': oid,
    'amount': 50,
    'currency': 'eur',
    'shipping_method': 'mao',
  }, jwt: null);
  c.note('BR7.ANON', 'anon CPI', ck.brief, lens: lens);
  if (ck.ok) {
    c.hold(
      id: 'BR7-ANON-CHECKOUT',
      lens: lens,
      severity: 'P1',
      title: 'Anon criou Checkout Session',
      actor: 'anon',
      pre: 'order buyer',
      repro: 'POST CPI sem JWT (só apikey)',
      expected: '401/403',
      obtained: ck.brief,
    );
  } else {
    c.block('BR7-ANON-CHECKOUT', lens, 'anon bloqueado', ck.brief);
  }
}
