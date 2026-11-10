/// Pass 1 — REDTEAM_BLIND_AE marketplace pós-ABACAD. Variantes NOVAS. Não corrigir.
import '_rtae.dart';

Future<void> main() async {
  final c = Rtae.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('boot', 'actors', {
    'b1': c.buyerId,
    's1': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
  });

  try {
    await _ae1Currency(c);
    await _ae1StaleLivePrice(c);
    await _ae1ClientAmount(c);
    await _ae2ReuseVariants(c);
    await _ae3BundleConjunto(c);
    await _ae4Captured(c);
    await _ae5Stock(c);
    await _ae6Race(c);
    await _ae7Actors(c);
    await _ae8RefundWallet(c);
  } catch (e, st) {
    c.note('crash', 'pass1 exception', '$e\n$st');
  } finally {
    await c.dumpAll('pass1_findings.json');
  }
}

Future<void> _ae1Currency(Rtae c) async {
  final pid = await c.createProduct(title: '$prefix-ae1-cur', price: 12, qty: 4);
  if (pid == null) return;
  final oid = await c.insertOrder(
    productId: pid,
    jwt: c.buyerJwt,
    price: 12,
  );
  if (oid == null) {
    c.note('ae1.order.fail', 'insert', 'null', lens: 'AE1');
    return;
  }
  final want = expectedQuoteCents(unitEur: 12);
  final baseline = await c.checkout(orderId: oid, amount: want, currency: 'eur');
  c.note('ae1.baseline', 'EUR ok?', {
    'http': baseline.status,
    'amt': baseline.amountTotal,
    'want': want,
    'reused': baseline.reused,
  }, lens: 'AE1');
  if (baseline.ok && (baseline.amountTotal ?? 0) != want) {
    c.hold(
      id: 'AE1-BASELINE-QUOTE-MISMATCH',
      lens: 'AE1',
      severity: 'P0',
      title: 'Session EUR com montante ≠ quote servidor',
      actor: 'buyer JWT',
      pre: 'order 12€ mão',
      repro: 'POST create-payment-intent currency=eur',
      expected: want,
      obtained: baseline.brief,
    );
  }

  // Variantes NOVAS — não jpy/usd/gbp exactos AB.
  final probes = <String, Object?>{
    'krw': 'krw',
    'inr': 'inr',
    'brl': 'brl',
    'chf': 'chf',
    'clp': 'clp',
    'vnd': 'vnd',
    'xxx': 'xxx',
    'euro': 'euro',
    '978': '978',
    'eu': 'eu',
    'empty': '',
    'cyrillic': 'еur', // U+0435
    'zwsp': 'eur\u200b',
    'fullwidth': 'ＥＵＲ',
    'eur_nullbyte': 'eur\u0000',
    'bool_true': true,
    'num_978': 978,
  };
  for (final e in probes.entries) {
    final h = await c.checkout(orderId: oid, amount: want, currency: e.value);
    final opened = h.ok && (h.sessionId ?? '').startsWith('cs_');
    c.note('ae1.cur.${e.key}', 'currency=${e.value}', h.brief, lens: 'AE1');
    if (opened && e.key != 'empty') {
      c.hold(
        id: 'AE1-CURRENCY-${e.key.toUpperCase()}',
        lens: 'AE1',
        severity: 'P0',
        title: 'Checkout aceitou currency não-EUR (${e.key})',
        actor: 'buyer JWT',
        pre: 'order 12€',
        repro: 'POST create-payment-intent currency=${e.value}',
        expected: '400 only EUR',
        obtained: {
          'http': h.status,
          'sid': h.sessionId,
          'amt': h.amountTotal,
        },
      );
    } else if (!h.ok) {
      c.block('AE1-CURRENCY-${e.key}', 'AE1', 'recusado ${e.key}', h);
    }
  }

  final omitted = await c.checkout(
    orderId: oid,
    amount: want,
    includeCurrency: false,
  );
  c.note('ae1.omit', 'sem currency (default eur)', omitted.brief, lens: 'AE1');
}

Future<void> _ae1StaleLivePrice(Rtae c) async {
  final pid = await c.createProduct(
    title: '$prefix-ae1-stale',
    price: 40,
    qty: 2,
  );
  if (pid == null) return;
  final liveId = await c.insertLive(active: true);
  if (liveId == null) return;
  final li = await c.insertMarketItem(
    liveId: liveId,
    productId: pid,
    price: 5,
    jwt: c.sellerJwt,
  );
  await c.rest('PATCH', 'lives?id=eq.$liveId', service: true, body: {
    'is_active': false,
    'status': 'ended',
  }, prefer: 'return=minimal');
  if (li == null) {
    c.note('ae1.stale.li.fail', 'live_item', 'null', lens: 'AE1');
    return;
  }
  final oid = await c.insertOrder(
    productId: pid,
    jwt: c.buyerJwt,
    price: 40,
    liveItemId: li,
    liveId: liveId,
  );
  if (oid == null) {
    c.note('ae1.stale.order.fail', 'insert com live_item ended', 'null',
        lens: 'AE1');
    return;
  }
  final row = await c.orderRow(oid);
  final ck = await c.checkout(orderId: oid, amount: 1);
  final wantCat = expectedQuoteCents(unitEur: 40);
  final wantLive = expectedQuoteCents(unitEur: 5);
  c.note('ae1.stale', 'checkout após live ended price 5 vs cat 40', {
    'contract': row?['contract_unit_cents'],
    'ck': ck.brief,
    'amt': ck.amountTotal,
    'wantCat': wantCat,
    'wantLive': wantLive,
  }, lens: 'AE1');
  final amt = ck.amountTotal ?? 0;
  if (ck.ok && amt > 0 && amt < wantCat - 50) {
    c.hold(
      id: 'AE1-STALE-LIVE-ITEM-PRICE',
      lens: 'AE1',
      severity: 'P0',
      title: 'Order marketplace puxa preço de live_item ended (mais barato)',
      actor: 'buyer JWT',
      pre: 'SKU 40€ + live_item 5€ em live ended',
      repro:
          'POST orders live_item_id+live_id ended; POST create-payment-intent',
      expected: wantCat,
      obtained: {
        'amount_total': amt,
        'want_live': wantLive,
        'contract_unit_cents': row?['contract_unit_cents'],
      },
      evidence: {'order': row, 'checkout': ck.map},
    );
  } else if (!ck.ok) {
    c.block('AE1-STALE-LIVE', 'AE1', 'checkout recusou live ended', ck);
  }
}

Future<void> _ae1ClientAmount(Rtae c) async {
  final pid = await c.createProduct(title: '$prefix-ae1-amt', price: 12, qty: 2);
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 12);
  if (oid == null) return;
  final want = expectedQuoteCents(unitEur: 12);
  for (final amt in [0, 0.5, 1, 50, 500, -12, 12.00, '12.00', 1e6]) {
    final h = await c.checkout(orderId: oid, amount: amt);
    c.note('ae1.amt.$amt', 'client amount', {
      'want': want,
      'got': h.amountTotal,
      'http': h.status,
      'ok': h.ok,
    }, lens: 'AE1');
    if (h.ok && (h.amountTotal ?? want) < want - 1) {
      c.hold(
        id: 'AE1-CLIENT-AMOUNT-$amt',
        lens: 'AE1',
        severity: 'P0',
        title: 'body.amount abaixou Session',
        actor: 'buyer JWT',
        pre: 'order 12€ want=$want',
        repro: 'POST create-payment-intent amount=$amt',
        expected: want,
        obtained: h.amountTotal,
      );
    }
  }
}

Future<void> _ae2ReuseVariants(Rtae c) async {
  // Mesmo montante, linhas diferentes (A+B vs A+C) — NÃO o overlap barato AB3.
  final p1 = await c.createProduct(title: '$prefix-ae2-p1', price: 10, qty: 4);
  final p2 = await c.createProduct(title: '$prefix-ae2-p2', price: 10, qty: 4);
  final p3 = await c.createProduct(title: '$prefix-ae2-p3', price: 10, qty: 4);
  if (p1 == null || p2 == null || p3 == null) return;
  final a = await c.insertOrder(productId: p1, jwt: c.buyerJwt, price: 10);
  final b = await c.insertOrder(productId: p2, jwt: c.buyerJwt, price: 10);
  final d = await c.insertOrder(productId: p3, jwt: c.buyerJwt, price: 10);
  if (a == null || b == null || d == null) return;

  final bagAB = await c.checkoutBag(lines: [
    {'order_id': a, 'product_id': p1},
    {'order_id': b, 'product_id': p2},
  ], amount: 1);
  c.note('ae2.ab', 'bag A+B', bagAB.brief, lens: 'AE2');
  final bagAC = await c.checkoutBag(lines: [
    {'order_id': a, 'product_id': p1},
    {'order_id': d, 'product_id': p3},
  ], amount: 1);
  c.note('ae2.ac', 'bag A+C mesmo montante', {
    'ab_sid': bagAB.sessionId,
    'ac_sid': bagAC.sessionId,
    'ac_reused': bagAC.reused,
    'ab_amt': bagAB.amountTotal,
    'ac_amt': bagAC.amountTotal,
    'same_sid': bagAB.sessionId != null && bagAB.sessionId == bagAC.sessionId,
  }, lens: 'AE2');

  if (bagAB.ok &&
      bagAC.ok &&
      bagAC.reused == true &&
      bagAB.sessionId != null &&
      bagAB.sessionId == bagAC.sessionId) {
    c.hold(
      id: 'AE2-BAG-SAME-AMOUNT-DIFFERENT-LINES',
      lens: 'AE2',
      severity: 'P1',
      title: 'Saco A+C reutiliza Session de A+B só porque o montante coincide',
      actor: 'buyer JWT',
      pre: '3 SKUs 10€; Session saco A+B',
      repro: 'POST bag A+C após bag A+B (amount_total igual)',
      expected: 'nova Session com metadata A+C',
      obtained: {
        'sid': bagAC.sessionId,
        'reused': bagAC.reused,
      },
      evidence: {
        'ab': bagAB.map,
        'ac': bagAC.map,
        'orders': [a, b, d],
      },
    );
  } else if (bagAC.ok && bagAC.reused != true) {
    c.block('AE2-BAG-COMPOSITION', 'AE2', 'não reutilizou A+B em A+C', bagAC);
  }

  // Split: saco A+B depois single A (montante diferente) → Session barata em A.
  final p4 = await c.createProduct(title: '$prefix-ae2-p4', price: 15, qty: 3);
  final p5 = await c.createProduct(title: '$prefix-ae2-p5', price: 15, qty: 3);
  if (p4 == null || p5 == null) return;
  final o4 = await c.insertOrder(productId: p4, jwt: c.buyerJwt, price: 15);
  final o5 = await c.insertOrder(productId: p5, jwt: c.buyerJwt, price: 15);
  if (o4 == null || o5 == null) return;
  final bag45 = await c.checkoutBag(lines: [
    {'order_id': o4},
    {'order_id': o5},
  ]);
  final single4 = await c.checkout(orderId: o4, amount: 1);
  final row4 = await c.orderRow(o4);
  final row5 = await c.orderRow(o5);
  c.note('ae2.split', 'bag depois single', {
    'bag_sid': bag45.sessionId,
    'bag_amt': bag45.amountTotal,
    'single_sid': single4.sessionId,
    'single_amt': single4.amountTotal,
    'o4_sid': row4?['stripe_checkout_session_id'],
    'o5_sid': row5?['stripe_checkout_session_id'],
  }, lens: 'AE2');
  final bagAmt = bag45.amountTotal ?? 0;
  final sAmt = single4.amountTotal ?? 0;
  if (bag45.ok &&
      single4.ok &&
      sAmt > 0 &&
      bagAmt > sAmt &&
      '${row4?['stripe_checkout_session_id']}' !=
          '${row5?['stripe_checkout_session_id']}') {
    c.hold(
      id: 'AE2-BAG-THEN-SINGLE-ORPHAN-SESSION',
      lens: 'AE2',
      severity: 'P2',
      title:
          'Single após saco substitui Session da linha; a outra linha fica com Session do saco',
      actor: 'buyer JWT',
      pre: 'saco 2×15€ depois checkout single da 1.ª linha',
      repro: 'bag_checkout A+B; depois create-payment-intent order A',
      expected: '1 Session por contrato / fail-closed',
      obtained: {
        'bag_amt': bagAmt,
        'single_amt': sAmt,
        'o4_sid': row4?['stripe_checkout_session_id'],
        'o5_sid': row5?['stripe_checkout_session_id'],
      },
    );
  }

  // Mesmo montante single de dois SKUs iguais — não deve reutilizar cross-order.
  final sA = await c.checkout(orderId: a, amount: 1);
  final sB = await c.checkout(orderId: b, amount: 1);
  c.note('ae2.cross.single', 'singles mesmo preço', {
    'a': sA.sessionId,
    'b': sB.sessionId,
    'same': sA.sessionId != null && sA.sessionId == sB.sessionId,
    'b_reused': sB.reused,
  }, lens: 'AE2');
  if (sA.ok && sB.ok && sA.sessionId != null && sA.sessionId == sB.sessionId) {
    c.hold(
      id: 'AE2-CROSS-ORDER-SESSION-REUSE',
      lens: 'AE2',
      severity: 'P1',
      title: 'Duas orders reutilizam a mesma Session (só montante)',
      actor: 'buyer JWT',
      pre: 'duas orders 10€',
      repro: 'checkout A; checkout B',
      expected: 'Sessions distintas',
      obtained: sA.sessionId,
    );
  }
}

Future<void> _ae3BundleConjunto(Rtae c) async {
  final cheap = await c.createProduct(
    title: '$prefix-ae3-c',
    price: 8,
    qty: 5,
  );
  final dear = await c.createProduct(
    title: '$prefix-ae3-d',
    price: 30,
    qty: 5,
  );
  if (cheap == null || dear == null) return;

  // Buyer tenta criar bundle aceite com total_eur baixo.
  final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
    'seller_id': c.sellerId,
    'buyer_id': c.buyerId,
    'product_ids': [cheap, dear],
    'status': 'accepted',
    'total_eur': 1.0,
  });
  c.note('ae3.bundle.insert.buyer', 'buyer INSERT accepted total=1', bun.brief,
      lens: 'AE3');
  final bid = bun.firstId;
  if (bid != null) c.createdBundleIds.add(bid);
  if (bun.ok && bid != null) {
    final t = numOf(bun.map?['total_eur']);
    if (t != null && t <= 2) {
      c.hold(
        id: 'AE3-BUYER-FORGE-BUNDLE-TOTAL',
        lens: 'AE3',
        severity: 'P0',
        title: 'Buyer criou product_bundles accepted com total_eur=1',
        actor: 'buyer JWT',
        pre: 'SKUs 8€+30€',
        repro: 'POST product_bundles status=accepted total_eur=1',
        expected: 'RLS/trigger recusa',
        obtained: bun.map,
      );
    }
    final o1 = await c.insertOrderHit(
      productId: cheap,
      jwt: c.buyerJwt,
      price: 8,
      bundleId: bid,
    );
    final o2 = await c.insertOrderHit(
      productId: dear,
      jwt: c.buyerJwt,
      price: 30,
      bundleId: bid,
    );
    c.note('ae3.bundle.orders', 'orders com bundle forjado', {
      'o1': o1.brief,
      'o2': o2.brief,
    }, lens: 'AE3');
    if (o1.firstId != null && o2.firstId != null) {
      final ck = await c.checkoutBag(lines: [
        {'order_id': o1.firstId},
        {'order_id': o2.firstId},
      ]);
      final catalog = expectedQuoteCents(unitEur: 8) +
          expectedQuoteCents(unitEur: 30) -
          protectionFeeCents(800, 0) -
          protectionFeeCents(3000, 0) +
          protectionFeeCents(800 + 3000, 0);
      // bag: items 8+30, one shipping, one protection on sum
      final bagWant = expectedQuoteCents(unitEur: 38); // not quite — 8+30 items
      final items = 800 + 3000;
      final bagExact = items + protectionFeeCents(items, 0);
      c.note('ae3.bundle.ck', 'checkout bundle forjado', {
        'ck': ck.brief,
        'amt': ck.amountTotal,
        'bagExactCatalog': bagExact,
        'catalogApprox': catalog,
      }, lens: 'AE3');
      final amt = ck.amountTotal ?? 0;
      if (ck.ok && amt > 0 && amt < bagExact - 200) {
        c.hold(
          id: 'AE3-BUNDLE-FORGED-TOTAL-CHECKOUT',
          lens: 'AE3',
          severity: 'P0',
          title: 'Checkout saco usa total_eur forjado (abaixo do catálogo)',
          actor: 'buyer JWT',
          pre: 'bundle accepted total_eur=1',
          repro: 'bag_checkout das 2 orders do bundle',
          expected: bagExact,
          obtained: amt,
        );
      }
    }
  } else {
    c.block('AE3-BUNDLE-INSERT', 'AE3', 'buyer não forja bundle', bun);
  }

  // Seller cria bundle aceite legítimo; buyer tenta qty=2 (não o exact 3+1 Y2).
  final bunS = await c.rest('POST', 'product_bundles', jwt: c.sellerJwt, body: {
    'seller_id': c.sellerId,
    'buyer_id': c.buyerId,
    'product_ids': [cheap, dear],
    'status': 'accepted',
    'total_eur': 35.0,
  });
  c.note('ae3.bundle.seller', 'seller bundle', bunS.brief, lens: 'AE3');
  final bs = bunS.firstId;
  if (bs != null) {
    c.createdBundleIds.add(bs);
    final q2 = await c.insertOrderHit(
      productId: cheap,
      jwt: c.buyerJwt,
      qty: 2,
      price: 16,
      bundleId: bs,
    );
    c.note('ae3.qty2', 'bundle qty=2', q2.brief, lens: 'AE3');
    if (q2.ok) {
      c.hold(
        id: 'AE3-BUNDLE-QTY2',
        lens: 'AE3',
        severity: 'P1',
        title: 'Order de conjunto aceite com quantity=2',
        actor: 'buyer JWT',
        pre: 'bundle accepted',
        repro: 'POST orders quantity=2 bundle_id',
        expected: 'bundle_order_quantity_must_be_one',
        obtained: q2.map,
      );
    } else {
      c.block('AE3-QTY2', 'AE3', 'qty=2 recusado', q2);
    }
  }

  // Conjunto sem bundle_id: 2 SKUs + desconto seller; buyer extra SKU.
  await c.rest('POST', 'seller_bundle_discounts', jwt: c.sellerJwt, body: {
    'seller_id': c.sellerId,
    'enabled': true,
    'tier_2_pct': 10,
    'tier_3_pct': 20,
    'tier_5_pct': 30,
  });
  final buyerDisc = await c.rest(
    'PATCH',
    'seller_bundle_discounts?seller_id=eq.${c.sellerId}',
    jwt: c.buyerJwt,
    body: {
      'tier_2_pct': 50,
      'custom_tiers': [
        {'min_items': 2, 'pct': 90}
      ],
    },
  );
  c.note('ae3.disc.buyer', 'buyer PATCH descontos seller', buyerDisc.brief,
      lens: 'AE3');
  if (buyerDisc.ok) {
    c.hold(
      id: 'AE3-BUYER-PATCH-BUNDLE-DISCOUNT',
      lens: 'AE3',
      severity: 'P0',
      title: 'Buyer alterou seller_bundle_discounts',
      actor: 'buyer JWT',
      pre: 'descontos do vendedor',
      repro: 'PATCH seller_bundle_discounts',
      expected: 'RLS recusa',
      obtained: buyerDisc.map,
    );
  } else {
    c.block('AE3-DISC-PATCH', 'AE3', 'buyer não muda descontos', buyerDisc);
  }

  // qty=1 extra SKU no saco vs conjunto de 2 (desconto 3 itens).
  final pExtra = await c.createProduct(
    title: '$prefix-ae3-x',
    price: 8,
    qty: 3,
  );
  if (pExtra == null) return;
  final ox1 = await c.insertOrder(productId: cheap, jwt: c.buyerJwt, price: 8);
  final ox2 = await c.insertOrder(productId: dear, jwt: c.buyerJwt, price: 30);
  final ox3 =
      await c.insertOrder(productId: pExtra, jwt: c.buyerJwt, price: 8);
  if (ox1 != null && ox2 != null && ox3 != null) {
    final ck = await c.checkoutBag(lines: [
      {'order_id': ox1},
      {'order_id': ox2},
      {'order_id': ox3},
    ]);
    c.note('ae3.tier3', 'saco 3 itens desconto', {
      'amt': ck.amountTotal,
      'ok': ck.ok,
      'brief': ck.brief,
    }, lens: 'AE3');
  }
}

Future<void> _ae4Captured(Rtae c) async {
  final paid = await c.payToPago(lens: 'AE4', initialQty: 2);
  if (paid == null) {
    c.skip('AE4', 'AE4', 'setup_paid_order fixture falhou', 'null');
    return;
  }
  final oid = paid.oid;
  final before = await c.orderRow(oid);
  c.note('ae4.paid', 'fixture pago', before, lens: 'AE4');

  // Aliases novos — não hop exacto Y8 pago→reserva_pendente como único teste,
  // mas tentamos vários (incluindo RP como um entre muitos).
  for (final st in [
    'aguarda_pagamento',
    'reservado',
    'aguarda_confirmacao',
    'pendente',
    'paid',
    'captured',
    'processing',
    'reserva_pendente',
  ]) {
    final h = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: c.buyerJwt,
      body: {'status': st},
    );
    final after = await c.orderRow(oid);
    c.note('ae4.hop.$st', 'buyer PATCH status', {
      'http': h.status,
      'status': after?['status'],
      'pi': after?['stripe_payment_intent_id'],
    }, lens: 'AE4');
    final now = '${after?['status']}'.toLowerCase();
    if (now == st && st != 'paid' && st != 'captured' && st != 'processing') {
      c.hold(
        id: 'AE4-HOP-$st',
        lens: 'AE4',
        severity: 'P1',
        title: 'Buyer reabriu order capturada para $st',
        actor: 'buyer JWT',
        pre: 'order pago+PI Stripe TEST',
        repro: 'PATCH orders status=$st',
        expected: 'status permanece pago',
        obtained: after,
      );
    }
  }

  final ck = await c.checkout(orderId: oid, amount: 1);
  c.note('ae4.ck', 'checkout order capturada', ck.brief, lens: 'AE4');
  if (ck.ok && (ck.sessionId ?? '').startsWith('cs_')) {
    c.hold(
      id: 'AE4-CHECKOUT-AFTER-CAPTURE',
      lens: 'AE4',
      severity: 'P0',
      title: 'create-payment-intent abriu Session em order já capturada',
      actor: 'buyer JWT',
      pre: 'setup_paid_order',
      repro: 'POST create-payment-intent',
      expected: 'order already captured',
      obtained: ck.map,
    );
  } else {
    c.block('AE4-CK', 'AE4', 'checkout capturada recusado', ck);
  }

  // Seller tenta limpar PI.
  final clr = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.sellerJwt,
    body: {
      'stripe_payment_intent_id': null,
      'amount_paid_cents': 0,
      'status': 'reserva_pendente',
    },
  );
  c.note('ae4.seller.clear', 'seller limpa captura', clr.brief, lens: 'AE4');
  if (clr.ok) {
    final after = await c.orderRow(oid);
    if ((after?['stripe_payment_intent_id'] == null ||
            '${after?['stripe_payment_intent_id']}'.isEmpty) &&
        (numOf(after?['amount_paid_cents']) ?? 1) == 0) {
      c.hold(
        id: 'AE4-SELLER-CLEAR-CAPTURE',
        lens: 'AE4',
        severity: 'P0',
        title: 'Seller apagou PI/cents de order capturada',
        actor: 'seller JWT',
        pre: 'order pago',
        repro: 'PATCH stripe_payment_intent_id=null amount_paid_cents=0',
        expected: 'order_money_fields_immutable',
        obtained: after,
      );
    }
  } else {
    c.block('AE4-CLEAR', 'AE4', 'seller não limpa captura', clr);
  }
}

Future<void> _ae5Stock(Rtae c) async {
  // Inflate NÃO exact 1→9: aumento 2→3 com hold reserva_pendente.
  final p = await c.createProduct(title: '$prefix-ae5-inf', price: 12, qty: 2);
  if (p == null) return;
  final o = await c.insertOrder(productId: p, jwt: c.buyerJwt, qty: 1, price: 12);
  final inc = await c.rest(
    'PATCH',
    'products?id=eq.$p',
    jwt: c.sellerJwt,
    body: {'quantity': 3},
  );
  final after = await c.productRow(p);
  c.note('ae5.inc23', 'seller qty 2→3 com hold', {
    'http': inc.status,
    'qty': after?['quantity'],
    'order': o,
    'body': inc.brief,
  }, lens: 'AE5');
  if (inc.ok && (numOf(after?['quantity']) ?? 2) >= 3) {
    c.hold(
      id: 'AE5-QTY-2-TO-3-WITH-HOLD',
      lens: 'AE5',
      severity: 'P1',
      title: 'Seller aumentou stock 2→3 com hold activo (não é o 1→9 AB5)',
      actor: 'seller JWT',
      pre: 'stock=2, order qty=1 reserva_pendente',
      repro: 'PATCH products quantity=3',
      expected: 'product_quantity_increase_blocked_active_order',
      obtained: after,
    );
  } else {
    c.block('AE5-INC', 'AE5', 'aumento com hold recusado', inc);
  }

  // Dois buyers stock=1.
  final p1 = await c.createProduct(title: '$prefix-ae5-race', price: 12, qty: 1);
  if (p1 == null) return;
  final b1 = await c.insertOrderHit(
    productId: p1,
    jwt: c.buyerJwt,
    qty: 1,
    price: 12,
  );
  final b2 = await c.insertOrderHit(
    productId: p1,
    buyer: c.buyer2Id,
    jwt: c.buyer2Jwt,
    qty: 1,
    price: 12,
  );
  c.note('ae5.two.buyers', 'stock=1 duas orders', {
    'b1': b1.brief,
    'b2': b2.brief,
  }, lens: 'AE5');
  if (b1.ok && b2.ok) {
    c.hold(
      id: 'AE5-TWO-HOLD-STOCK1',
      lens: 'AE5',
      severity: 'P0',
      title: 'Dois buyers criaram hold qty=1 em stock=1',
      actor: 'buyer JWT + buyer2 JWT',
      pre: 'SKU quantity=1',
      repro: 'POST orders B1; POST orders B2',
      expected: 'segunda INSERT order_hold_exceeds_stock',
      obtained: {'b1': b1.firstId, 'b2': b2.firstId},
    );
    if (b1.firstId != null && b2.firstId != null) {
      final ck1 = await c.checkout(orderId: b1.firstId!);
      final ck2 = await c.checkout(
        orderId: b2.firstId!,
        jwt: c.buyer2Jwt,
        buyer: c.buyer2Id,
      );
      c.note('ae5.two.ck', 'dois checkouts stock=1', {
        'ck1': ck1.brief,
        'ck2': ck2.brief,
      }, lens: 'AE5');
      if (ck1.ok && ck2.ok) {
        c.hold(
          id: 'AE5-TWO-CHECKOUT-STOCK1',
          lens: 'AE5',
          severity: 'P0',
          title: 'Duas Sessions Stripe em stock=1',
          actor: 'B1+B2 JWT',
          pre: 'duas orders stock=1',
          repro: '2× create-payment-intent',
          expected: 'um checkout bloqueado',
          obtained: {
            's1': ck1.sessionId,
            's2': ck2.sessionId,
            'a1': ck1.amountTotal,
            'a2': ck2.amountTotal,
          },
        );
      }
    }
  } else {
    c.block('AE5-TWO', 'AE5', 'segundo hold recusado', b2);
  }

  // Buyer PATCH quantity do produto.
  final pBuy = await c.createProduct(title: '$prefix-ae5-bp', price: 12, qty: 1);
  if (pBuy != null) {
    final pb = await c.rest(
      'PATCH',
      'products?id=eq.$pBuy',
      jwt: c.buyerJwt,
      body: {'quantity': 9},
    );
    c.note('ae5.buyer.qty', 'buyer PATCH product qty', pb.brief, lens: 'AE5');
    final row = await c.productRow(pBuy);
    if ((numOf(row?['quantity']) ?? 1) >= 9) {
      c.hold(
        id: 'AE5-BUYER-PRODUCT-QTY',
        lens: 'AE5',
        severity: 'P0',
        title: 'Buyer inflacionou quantity do produto',
        actor: 'buyer JWT',
        pre: 'SKU qty=1',
        repro: 'PATCH products quantity=9',
        expected: 'RLS recusa / revert',
        obtained: row,
      );
    } else {
      c.block('AE5-BUYER-QTY', 'AE5', 'buyer não muda qty', pb);
    }
  }

  // is_sold=true depois order, seller is_sold=false.
  final ps = await c.createProduct(title: '$prefix-ae5-sold', price: 12, qty: 2);
  if (ps != null) {
    final os =
        await c.insertOrder(productId: ps, jwt: c.buyerJwt, price: 12);
    await c.rest('PATCH', 'products?id=eq.$ps', jwt: c.sellerJwt, body: {
      'is_sold': true,
    }, prefer: 'return=minimal');
    final ckSold = os == null ? null : await c.checkout(orderId: os);
    c.note('ae5.sold.ck', 'checkout is_sold', ckSold?.brief, lens: 'AE5');
    if (ckSold != null && ckSold.ok) {
      c.hold(
        id: 'AE5-CHECKOUT-IS-SOLD',
        lens: 'AE5',
        severity: 'P1',
        title: 'Checkout com produto is_sold=true',
        actor: 'buyer JWT',
        pre: 'hold + seller marcou vendido',
        repro: 'PATCH is_sold=true; create-payment-intent',
        expected: 'product is marked sold',
        obtained: ckSold.map,
      );
    } else if (ckSold != null) {
      c.block('AE5-SOLD', 'AE5', 'checkout is_sold recusado', ckSold);
    }
    final unsold = await c.rest(
      'PATCH',
      'products?id=eq.$ps',
      jwt: c.sellerJwt,
      body: {'is_sold': false, 'quantity': 5},
    );
    c.note('ae5.unsold', 'seller unsold+qty', unsold.brief, lens: 'AE5');
  }

  // Ghost: cancelar hold, stock deve libertar; depois 2.º buyer.
  final pg = await c.createProduct(title: '$prefix-ae5-gh', price: 12, qty: 1);
  if (pg != null) {
    final og = await c.insertOrder(productId: pg, jwt: c.buyerJwt, price: 12);
    if (og != null) {
      final can = await c.rest(
        'PATCH',
        'orders?id=eq.$og',
        jwt: c.sellerJwt,
        body: {'status': 'cancelado'},
      );
      final og2 = await c.insertOrderHit(
        productId: pg,
        buyer: c.buyer2Id,
        jwt: c.buyer2Jwt,
        price: 12,
      );
      c.note('ae5.ghost', 'cancel + 2.º hold', {
        'cancel': can.brief,
        'b2': og2.brief,
      }, lens: 'AE5');
    }
  }

  // RPC stock check como B2 noutro produto.
  if (p != null) {
    final sc = await c.stockCheck(p, need: 9);
    c.note('ae5.rpc', 'checkout_available need=9', sc.brief, lens: 'AE5');
  }
}

Future<void> _ae6Race(Rtae c) async {
  final p = await c.createProduct(title: '$prefix-ae6', price: 12, qty: 1);
  if (p == null) return;
  final hits = await parallel([
    c.insertOrderHit(productId: p, jwt: c.buyerJwt, price: 12),
    c.insertOrderHit(
      productId: p,
      buyer: c.buyer2Id,
      jwt: c.buyer2Jwt,
      price: 12,
    ),
  ]);
  final oks = hits.where((h) => h.ok).toList();
  c.note('ae6.insert', 'Future.wait 2 INSERT stock=1', {
    'h0': hits[0].brief,
    'h1': hits[1].brief,
    'ok': oks.length,
  }, lens: 'AE6');
  if (oks.length >= 2) {
    c.hold(
      id: 'AE6-RACE-TWO-INSERTS-STOCK1',
      lens: 'AE6',
      severity: 'P0',
      title: 'Corrida: 2 INSERT orders stock=1 ambos OK',
      actor: 'B1∥B2 JWT',
      pre: 'quantity=1',
      repro: 'Future.wait 2× POST orders',
      expected: '1 OK + 1 hold_exceeds_stock',
      obtained: oks.map((h) => h.firstId).toList(),
    );
  } else {
    c.block('AE6-INSERT', 'AE6', 'corrida INSERT serializada', hits[0]);
  }

  final p2 = await c.createProduct(title: '$prefix-ae6b', price: 12, qty: 2);
  if (p2 == null) return;
  final o = await c.insertOrder(productId: p2, jwt: c.buyerJwt, price: 12);
  if (o == null) return;
  final cks = await parallel([
    c.checkout(orderId: o, amount: 1),
    c.checkout(orderId: o, amount: 1),
  ]);
  final sids = cks
      .map((h) => h.sessionId)
      .where((s) => s != null && s.startsWith('cs_'))
      .toSet();
  c.note('ae6.ck', 'Future.wait 2 checkout mesma order', {
    'c0': cks[0].brief,
    'c1': cks[1].brief,
    'unique_sids': sids.length,
    'reused': [cks[0].reused, cks[1].reused],
  }, lens: 'AE6');
  if (sids.length >= 2) {
    c.hold(
      id: 'AE6-RACE-TWO-SESSIONS',
      lens: 'AE6',
      severity: 'P1',
      title: 'Dois POST checkout paralelos criaram 2 Sessions',
      actor: 'buyer JWT',
      pre: '1 order',
      repro: 'Future.wait 2× create-payment-intent',
      expected: '1 Session (claim/reuse)',
      obtained: sids.toList(),
    );
  } else {
    c.block('AE6-CK', 'AE6', 'claim serializou Sessions', cks[0]);
  }
}

Future<void> _ae7Actors(Rtae c) async {
  final p = await c.createProduct(title: '$prefix-ae7', price: 12, qty: 3);
  if (p == null) return;
  final o = await c.insertOrder(productId: p, jwt: c.buyerJwt, price: 12);
  if (o == null) return;

  final b2ck = await c.checkout(
    orderId: o,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  c.note('ae7.b2.ck', 'B2 checkout order B1', b2ck.brief, lens: 'AE7');
  if (b2ck.ok) {
    c.hold(
      id: 'AE7-B2-CHECKOUT-B1-ORDER',
      lens: 'AE7',
      severity: 'P0',
      title: 'B2 criou Session da order de B1',
      actor: 'buyer2 JWT',
      pre: 'order B1',
      repro: 'POST create-payment-intent buyer_id=B2 order_id=B1',
      expected: 'Invalid checkout user / not belong',
      obtained: b2ck.map,
    );
  } else {
    c.block('AE7-B2CK', 'AE7', 'B2 não checkout B1', b2ck);
  }

  final b2bag = await c.checkoutBag(
    lines: [
      {'order_id': o}
    ],
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  c.note('ae7.b2.bag', 'B2 saco com order B1', b2bag.brief, lens: 'AE7');
  if (b2bag.ok) {
    c.hold(
      id: 'AE7-B2-BAG-B1',
      lens: 'AE7',
      severity: 'P0',
      title: 'B2 saco checkout da order B1',
      actor: 'buyer2 JWT',
      pre: 'order B1',
      repro: 'bag_checkout bag_lines=order B1',
      expected: 'blocked',
      obtained: b2bag.map,
    );
  } else {
    c.block('AE7-B2BAG', 'AE7', 'B2 saco recusado', b2bag);
  }

  final anon = await c.edge('create-payment-intent', {
    'buyer_id': c.buyerId,
    'order_id': o,
    'currency': 'eur',
    'amount': 50,
    'shipping_method': 'mao',
  });
  c.note('ae7.anon', 'anon checkout', anon.brief, lens: 'AE7');
  if (anon.ok) {
    c.hold(
      id: 'AE7-ANON-CHECKOUT',
      lens: 'AE7',
      severity: 'P0',
      title: 'anon criou Checkout Session',
      actor: 'anon',
      pre: 'order B1',
      repro: 'POST create-payment-intent sem JWT user',
      expected: 'Missing authorization / Invalid checkout user',
      obtained: anon.map,
    );
  } else {
    c.block('AE7-ANON', 'AE7', 'anon recusado', anon);
  }

  final self = await c.checkout(
    orderId: o,
    jwt: c.sellerJwt,
    buyer: c.sellerId,
  );
  c.note('ae7.seller.self', 'seller como buyer_id', self.brief, lens: 'AE7');
  if (self.ok) {
    c.hold(
      id: 'AE7-SELLER-AS-BUYER',
      lens: 'AE7',
      severity: 'P1',
      title: 'Seller JWT checkout com buyer_id=seller em order alheia',
      actor: 'seller JWT',
      pre: 'order B1',
      repro: 'POST create-payment-intent JWT seller buyer_id=seller',
      expected: 'blocked',
      obtained: self.map,
    );
  } else {
    c.block('AE7-SELLER', 'AE7', 'seller não impersona buyer', self);
  }

  // Seller S2 tenta refund order S1 (se houver pago).
  final paid = await c.payToPago(lens: 'AE7', initialQty: 2);
  if (paid != null) {
    final r2 = await c.refund(paid.oid, jwt: c.seller2Jwt);
    c.note('ae7.s2.refund', 'S2 refund order S1', r2.brief, lens: 'AE7');
    if (r2.ok) {
      c.hold(
        id: 'AE7-S2-REFUND-S1',
        lens: 'AE7',
        severity: 'P0',
        title: 'Seller2 reembolsou order de Seller1',
        actor: 'seller2 JWT',
        pre: 'order pago S1',
        repro: 'POST refund-order',
        expected: 'não é o vendedor',
        obtained: r2.map,
      );
    } else {
      c.block('AE7-S2REF', 'AE7', 'S2 refund recusado', r2);
    }
    final rb = await c.refund(paid.oid, jwt: c.buyerJwt);
    c.note('ae7.b.refund', 'buyer refund-order', rb.brief, lens: 'AE7');
    if (rb.ok) {
      c.hold(
        id: 'AE7-BUYER-REFUND',
        lens: 'AE7',
        severity: 'P0',
        title: 'Buyer invocou refund-order',
        actor: 'buyer JWT',
        pre: 'order pago',
        repro: 'POST refund-order JWT buyer',
        expected: 'seller-only',
        obtained: rb.map,
      );
    } else {
      c.block('AE7-BREF', 'AE7', 'buyer refund recusado', rb);
    }
  }

  // Off-platform + stripe.
  final pOff =
      await c.createProduct(title: '$prefix-ae7-off', price: 12, qty: 2);
  if (pOff != null) {
    final oOff = await c.insertOrder(
      productId: pOff,
      jwt: c.buyerJwt,
      payment: 'MB WAY',
      price: 12,
    );
    if (oOff != null) {
      final ck = await c.checkout(orderId: oOff);
      c.note('ae7.off', 'MB WAY + stripe', ck.brief, lens: 'AE7');
      if (ck.ok) {
        c.hold(
          id: 'AE7-OFFPLATFORM-STRIPE',
          lens: 'AE7',
          severity: 'P1',
          title: 'Order MB WAY abriu Checkout Stripe',
          actor: 'buyer JWT',
          pre: 'payment_method=MB WAY',
          repro: 'POST create-payment-intent',
          expected: 'off-platform payment',
          obtained: ck.map,
        );
      } else {
        c.block('AE7-OFF', 'AE7', 'off-platform sem Stripe', ck);
      }
    }
  }

  // prize_shipping em order normal.
  final prize = await c.checkout(orderId: o, prize: true);
  c.note('ae7.prize', 'prize_shipping false prize', prize.brief, lens: 'AE7');
  if (prize.ok) {
    final want = expectedQuoteCents(unitEur: 12);
    final amt = prize.amountTotal ?? 0;
    if (amt > 0 && amt < want - 100) {
      c.hold(
        id: 'AE7-FAKE-PRIZE-SHIPPING',
        lens: 'AE7',
        severity: 'P0',
        title: 'prize_shipping=true reduziu total de order não-rifa',
        actor: 'buyer JWT',
        pre: 'order marketplace',
        repro: 'POST create-payment-intent prize_shipping=true',
        expected: 'order is not a raffle prize OU total catálogo',
        obtained: amt,
      );
    }
  } else {
    c.block('AE7-PRIZE', 'AE7', 'prize fake recusado', prize);
  }

  // Seller INSERT order para o buyer.
  final forced = await c.insertOrderHit(
    productId: p,
    jwt: c.sellerJwt,
    buyer: c.buyerId,
    seller: c.sellerId,
    price: 12,
  );
  c.note('ae7.seller.insert', 'seller INSERT order do buyer', forced.brief,
      lens: 'AE7');
}

Future<void> _ae8RefundWallet(Rtae c) async {
  final paid = await c.payToPago(lens: 'AE8', initialQty: 2);
  if (paid == null) {
    c.skip('AE8', 'AE8', 'sem captura TEST', 'null');
    return;
  }
  final w0 = await c.wallets();
  final row0 = await c.orderRow(paid.oid);
  final r1 = await c.refund(paid.oid, jwt: c.sellerJwt);
  final row1 = await c.orderRow(paid.oid);
  final r2 = await c.refund(paid.oid, jwt: c.sellerJwt);
  final w1 = await c.wallets();
  c.note('ae8.refund', 'seller refund ×2', {
    'r1': r1.brief,
    'r2': r2.brief,
    'w0': w0,
    'w1': w1,
    'st0': row0?['status'],
    'st1': row1?['status'],
    'ref': row1?['stripe_refund_id'],
  }, lens: 'AE8');

  final ck = await c.checkout(orderId: paid.oid);
  c.note('ae8.ck.after.refund', 'checkout pós-refund', ck.brief, lens: 'AE8');
  if (ck.ok) {
    c.hold(
      id: 'AE8-CHECKOUT-AFTER-REFUND',
      lens: 'AE8',
      severity: 'P1',
      title: 'Checkout reabriu após refund',
      actor: 'buyer JWT',
      pre: 'order refunded',
      repro: 'POST refund-order; POST create-payment-intent',
      expected: 'already refunded',
      obtained: ck.map,
    );
  } else {
    c.block('AE8-CK', 'AE8', 'pós-refund sem nova Session', ck);
  }

  if (r1.ok && r2.ok) {
    final dSeller = (w1['seller'] ?? 0) - (w0['seller'] ?? 0);
    final dBuyer = (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0);
    if (dBuyer > 0.01 && dSeller >= -0.01) {
      c.hold(
        id: 'AE8-DOUBLE-REFUND-MONEY',
        lens: 'AE8',
        severity: 'P0',
        title: 'Dois refunds criaram dinheiro líquido',
        actor: 'seller JWT',
        pre: 'order pago Stripe TEST',
        repro: '2× POST refund-order',
        expected: '2.º idempotente, Δwallet ≤ captura',
        obtained: {'w0': w0, 'w1': w1, 'dBuyer': dBuyer, 'dSeller': dSeller},
      );
    }
  }

  // P0 de passes anteriores: se Session barata existe, pagar via e2e não aplica
  // a Session hostil — apenas documentar. Encadear só se finding P0 com sid.
  final p0 = c.findings.where((f) => f['severity'] == 'P0').toList();
  c.note('ae8.p0.count', 'P0 até agora', p0.map((f) => f['id']).toList(),
      lens: 'AE8');
}
