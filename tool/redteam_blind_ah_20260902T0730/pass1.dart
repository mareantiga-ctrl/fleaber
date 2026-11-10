/// RED TEAM CEGO AH pass1 — variantes novas pós-AEAFAG.
/// Não repetir exactos AE1-STALE-ENDED / AE2-BAG-SAME-AMOUNT / AE2-BAG-THEN-SINGLE
/// / AB3 currency / AB5 qty 1→9 / Y2 bundle qty>1.
import 'dart:io';

import '_rtah.dart';

Future<void> main() async {
  final c = Rtah.fromEnv(loadEnv());
  stdout.writeln('AH pass1 staging=${c.url} prefix=$prefix');
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('actors', 'ids', {
    'b': c.buyerId,
    's': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
  });

  await ah1LiveActivePriceDropAfterSeal(c);
  await ah1CatalogPriceDropAfterSeal(c);
  await ah1JwtPatchContract(c);
  await ah1JwtPatchQty(c);
  await ah1JwtPatchShippingThenCheckout(c);
  await ah1JwtInsertUnderContract(c);
  await ah1SelfAcceptOffer(c);
  await ah1SwapLiveItemAfterSeal(c);

  await ah2BagRecomposeNoExpire(c);
  await ah2SingleThenBagNoExpire(c);
  await ah2BagPermutationReuse(c);
  await ah2SameAmountDifferentLinesNoReuse(c);
  await ah2SingleShipPatchOrphan(c);

  await ah3BundlePartialAndBuyer2(c);
  await ah3BundleTotalPatch(c);
  await ah3TwoBundleIds(c);

  await ah4CapturedNoReopen(c);

  await ah5StockOneTwoCheckouts(c);
  await ah5SellerQtyInflateWithHold(c);
  await ah5JwtQtyInflate(c);

  await ah6ParallelCheckout(c);
  await ah6ParallelBag(c);

  await ah7CrossBuyerCheckout(c);
  await ah7AnonAndSellerCheckout(c);
  await ah7BuyerRefund(c);
  await ah7Seller2Refund(c);

  await ah8WalletBaseline(c);

  await c.dumpAll();
  stdout.writeln(
    'DONE findings=${c.findings.length} blocked=${c.blocked.length} notes=${c.notes.length}',
  );
}

Map<String, Object?> bagLine(String orderId, String productId) => {
      'order_id': orderId,
      'product_id': productId,
    };

Future<void> ah1LiveActivePriceDropAfterSeal(Rtah c) async {
  final lens = 'AH1';
  final pid = await c.createProduct(price: 40, qty: 2, title: '$prefix-live-drop');
  if (pid == null) return c.skip('AH1.LIVE.DROP', lens, 'no product', '');
  final liveId = await c.insertLive(active: true, status: 'live');
  if (liveId == null) return c.skip('AH1.LIVE.DROP', lens, 'no live', '');
  final li = await c.insertMarketItem(
    liveId: liveId,
    productId: pid,
    price: 18,
    service: true,
  );
  if (li == null) return c.skip('AH1.LIVE.DROP', lens, 'no live_item', '');
  final oid = await c.insertOrder(
    productId: pid,
    jwt: c.buyerJwt,
    price: 18,
    liveItemId: li,
    liveId: liveId,
  );
  final before = await c.orderRow(oid ?? '');
  final sealed = numOf(before?['contract_unit_cents']);
  final drop = await c.rest(
    'PATCH',
    'live_items?id=eq.$li',
    service: true,
    body: {'price': 1.0},
    prefer: 'return=representation',
  );
  c.note('AH1.LIVE.DROP.patch', 'live_item still broadcasting price=1', drop.brief,
      lens: lens);
  final ck = await c.checkout(orderId: oid ?? '', amount: 50);
  c.note('AH1.LIVE.DROP.ck', 'checkout after live price drop (live still active)',
      '${ck.brief} amt=${ck.amountTotal} sealed=$sealed',
      lens: lens);
  final expect = expectedQuoteCents(unitEur: (sealed ?? 1800) / 100);
  if (ck.ok && ck.amountTotal != null && ck.amountTotal! < expect - 50) {
    c.hold(
      id: 'AH1-LIVE-ACTIVE-PRICE-DROP',
      lens: lens,
      severity: 'P0',
      title: 'Checkout usa preço live_item baixado após selo (live ainda activa)',
      actor: 'buyer JWT',
      pre: 'order selada com live_item 18€; live continua broadcasting; PATCH price=1',
      repro: 'POST create-payment-intent',
      expected: expect,
      obtained: ck.amountTotal,
      evidence: {'sealed': sealed, 'session': ck.sessionId},
    );
  } else if (ck.ok && ck.amountTotal == expect) {
    c.block('AH1-LIVE-ACTIVE-PRICE-DROP', lens,
        'checkout manteve contrato selado', 'amt=${ck.amountTotal} sealed=$sealed');
  } else {
    c.note('AH1.LIVE.DROP.result', 'não underpay', ck.brief, lens: lens);
  }
}

Future<void> ah1CatalogPriceDropAfterSeal(Rtah c) async {
  final lens = 'AH1';
  final pid = await c.createProduct(price: 25, qty: 2, title: '$prefix-cat-drop');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 25);
  final before = await c.orderRow(oid ?? '');
  final sealed = numOf(before?['contract_unit_cents']);
  await c.rest('PATCH', 'products?id=eq.$pid', service: true, body: {'price': 1.0});
  final ck = await c.checkout(orderId: oid ?? '', amount: 50);
  final expect = expectedQuoteCents(unitEur: (sealed ?? 2500) / 100);
  c.note('AH1.CAT.DROP', 'checkout após catálogo 25→1',
      '${ck.brief} amt=${ck.amountTotal} expect=$expect sealed=$sealed',
      lens: lens);
  if (ck.ok && ck.amountTotal != null && ck.amountTotal! < expect - 50) {
    c.hold(
      id: 'AH1-CATALOG-PRICE-DROP',
      lens: lens,
      severity: 'P0',
      title: 'Checkout usa catálogo baixado após contrato selado',
      actor: 'buyer JWT',
      pre: 'order 25€; PATCH products.price=1',
      repro: 'POST create-payment-intent',
      expected: expect,
      obtained: ck.amountTotal,
    );
  } else {
    c.block('AH1-CATALOG-PRICE-DROP', lens, 'manteve contrato',
        'amt=${ck.amountTotal} sealed=$sealed');
  }
}

Future<void> ah1JwtPatchContract(Rtah c) async {
  final lens = 'AH1';
  final pid = await c.createProduct(price: 22, qty: 1, title: '$prefix-patch-c');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 22);
  final patch = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'contract_unit_cents': 50},
  );
  final row = await c.orderRow(oid ?? '');
  c.note('AH1.PATCH.CONTRACT', 'JWT PATCH contract_unit_cents=50',
      '${patch.brief} now=${row?['contract_unit_cents']}',
      lens: lens);
  if (numOf(row?['contract_unit_cents']) == 50) {
    c.hold(
      id: 'AH1-JWT-PATCH-CONTRACT',
      lens: lens,
      severity: 'P0',
      title: 'Buyer JWT altera contract_unit_cents após INSERT',
      actor: 'buyer JWT',
      pre: 'order selada ~2200',
      repro: 'PATCH orders contract_unit_cents=50',
      expected: 'immutable',
      obtained: row?['contract_unit_cents'],
    );
  } else {
    c.block('AH1-JWT-PATCH-CONTRACT', lens, 'contract imutável', patch.brief);
  }
}

Future<void> ah1JwtPatchQty(Rtah c) async {
  final lens = 'AH1';
  final pid = await c.createProduct(price: 11, qty: 9, title: '$prefix-patch-q');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 11, qty: 1);
  final patch = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'quantity': 9, 'contract_qty': 9},
  );
  final row = await c.orderRow(oid ?? '');
  c.note('AH1.PATCH.QTY', 'JWT PATCH qty 1→9',
      '${patch.brief} qty=${row?['quantity']} cq=${row?['contract_qty']}',
      lens: lens);
  if (numOf(row?['quantity']) == 9 || numOf(row?['contract_qty']) == 9) {
    c.hold(
      id: 'AH1-JWT-PATCH-QTY',
      lens: lens,
      severity: 'P1',
      title: 'Buyer JWT inflaciona quantity/contract_qty',
      actor: 'buyer JWT',
      pre: 'order qty=1 stock=9',
      repro: 'PATCH quantity=9 contract_qty=9',
      expected: 'immutable',
      obtained: {'qty': row?['quantity'], 'cq': row?['contract_qty']},
    );
  } else {
    c.block('AH1-JWT-PATCH-QTY', lens, 'qty imutável', patch.brief);
  }
}

Future<void> ah1JwtPatchShippingThenCheckout(Rtah c) async {
  final lens = 'AH1';
  final pid = await c.createProduct(price: 15, qty: 1, title: '$prefix-ship');
  if (pid == null) return;
  final oid = await c.insertOrder(
    productId: pid,
    jwt: c.buyerJwt,
    price: 15,
    shipping: 'Envio Transportadora (€3.50)',
  );
  final before = await c.orderRow(oid ?? '');
  final ck1 = await c.checkout(orderId: oid ?? '', shipping: 'carrier', amount: 50);
  final patch = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'shipping_method': 'entrega em mão'},
  );
  final after = await c.orderRow(oid ?? '');
  final ck2 = await c.checkout(orderId: oid ?? '', shipping: 'mao', amount: 50);
  c.note('AH1.SHIP', 'carrier→mão', {
    'before': before?['shipping_method'],
    'after': after?['shipping_method'],
    'patch': patch.brief,
    'ck1': '${ck1.amountTotal} ${ck1.sessionId} reused=${ck1.reused}',
    'ck2': '${ck2.amountTotal} ${ck2.sessionId} reused=${ck2.reused}',
  }, lens: lens);
  final expectCarrier = expectedQuoteCents(unitEur: 15, shipCents: 350);
  final expectHand = expectedQuoteCents(unitEur: 15, shipCents: 0);
  if (ck2.ok &&
      ck2.amountTotal != null &&
      ck2.amountTotal == expectHand &&
      (before?['shipping_method'] ?? '').toString().toLowerCase().contains('transp')) {
    if (patch.ok || after?['shipping_method'] != before?['shipping_method']) {
      c.hold(
        id: 'AH1-SHIP-PATCH-HAND',
        lens: lens,
        severity: 'P2',
        title: 'Buyer JWT troca portes selados carrier→mão e checkout baixa',
        actor: 'buyer JWT',
        pre: 'order shipping=transportadora',
        repro: 'PATCH shipping_method=entrega em mão; create-payment-intent',
        expected: expectCarrier,
        obtained: ck2.amountTotal,
        evidence: {
          'ck1': ck1.amountTotal,
          'ck2': ck2.amountTotal,
          's1': ck1.sessionId,
          's2': ck2.sessionId,
        },
      );
    }
  } else {
    c.block('AH1-SHIP-PATCH-HAND', lens, 'portes não baixaram via PATCH JWT', {
      'patch': patch.brief,
      'ck2': ck2.amountTotal,
      'ship': after?['shipping_method'],
    });
  }
}

Future<void> ah1JwtInsertUnderContract(Rtah c) async {
  final lens = 'AH1';
  final pid = await c.createProduct(price: 30, qty: 1, title: '$prefix-under');
  if (pid == null) return;
  final hit = await c.insertOrderHit(
    productId: pid,
    jwt: c.buyerJwt,
    price: 0.5,
    contractUnitCents: 50,
  );
  final row = hit.firstId != null ? await c.orderRow(hit.firstId!) : null;
  c.note('AH1.INSERT.UNDER', 'INSERT price=0.50 contract=50', {
    'hit': hit.brief,
    'contract': row?['contract_unit_cents'],
    'price_total': row?['price_total'],
  }, lens: lens);
  if (row != null && numOf(row['contract_unit_cents']) == 50) {
    c.hold(
      id: 'AH1-INSERT-UNDER-CONTRACT',
      lens: lens,
      severity: 'P0',
      title: 'JWT INSERT sela contract abaixo do catálogo',
      actor: 'buyer JWT',
      pre: 'product 30€',
      repro: 'POST orders price_total=0.5 contract_unit_cents=50',
      expected: '>=3000',
      obtained: row['contract_unit_cents'],
    );
  } else {
    c.block('AH1-INSERT-UNDER-CONTRACT', lens, 'selo ignorou client cents',
        'contract=${row?['contract_unit_cents']}');
  }
}

Future<void> ah1SelfAcceptOffer(Rtah c) async {
  final lens = 'AH1';
  final pid = await c.createProduct(price: 40, qty: 1, title: '$prefix-offer');
  if (pid == null) return;
  final ins = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': pid,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': 0.8,
    'status': 'pending',
  });
  final oidOffer = ins.firstId;
  if (oidOffer != null) c.createdOfferIds.add(oidOffer);
  c.note('AH1.OFFER.ins', 'buyer cria oferta 0.80', ins.brief, lens: lens);
  if (oidOffer == null) {
    return c.block('AH1-SELF-ACCEPT-OFFER', lens, 'não criou oferta', ins.brief);
  }
  final acc = await c.rest(
    'PATCH',
    'product_offers?id=eq.$oidOffer',
    jwt: c.buyerJwt,
    body: {'status': 'accepted', 'responded_at': DateTime.now().toUtc().toIso8601String()},
  );
  c.note('AH1.OFFER.self', 'buyer PATCH accepted', acc.brief, lens: lens);
  final ord = await c.insertOrderHit(
    productId: pid,
    jwt: c.buyerJwt,
    price: 0.8,
    offerId: oidOffer,
  );
  final row = ord.firstId != null ? await c.orderRow(ord.firstId!) : null;
  c.note('AH1.OFFER.ord', 'order com oferta', {
    'ord': ord.brief,
    'contract': row?['contract_unit_cents'],
    'offer': row?['product_offer_id'],
  }, lens: lens);
  if (row != null &&
      numOf(row['contract_unit_cents']) != null &&
      numOf(row['contract_unit_cents'])! < 2000 &&
      (acc.ok || row['product_offer_id'] == oidOffer)) {
    c.hold(
      id: 'AH1-SELF-ACCEPT-OFFER',
      lens: lens,
      severity: 'P1',
      title: 'Comprador auto-aceita oferta baixa e sela contrato',
      actor: 'buyer JWT',
      pre: 'product 40€ oferta 0.80 pending',
      repro: 'PATCH product_offers status=accepted JWT buyer; POST orders product_offer_id',
      expected: 'só seller aceita; contrato catálogo',
      obtained: row['contract_unit_cents'],
    );
  } else {
    c.block('AH1-SELF-ACCEPT-OFFER', lens, 'auto-accept não selou abaixo', {
      'acc': acc.brief,
      'contract': row?['contract_unit_cents'],
    });
  }
}

Future<void> ah1SwapLiveItemAfterSeal(Rtah c) async {
  final lens = 'AH1';
  final pid = await c.createProduct(price: 20, qty: 2, title: '$prefix-swap-li');
  if (pid == null) return;
  final liveId = await c.insertLive();
  if (liveId == null) return;
  final liHi = await c.insertMarketItem(
      liveId: liveId, productId: pid, price: 20, service: true);
  final liLo = await c.insertMarketItem(
      liveId: liveId, productId: pid, price: 6, service: true);
  final oid = await c.insertOrder(
    productId: pid,
    jwt: c.buyerJwt,
    price: 20,
    liveItemId: liHi,
    liveId: liveId,
  );
  final patch = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'live_item_id': liLo},
  );
  final row = await c.orderRow(oid ?? '');
  final ck = await c.checkout(orderId: oid ?? '', amount: 50);
  c.note('AH1.SWAP.LI', 'PATCH live_item_id hi→lo', {
    'patch': patch.brief,
    'li': row?['live_item_id'],
    'contract': row?['contract_unit_cents'],
    'amt': ck.amountTotal,
  }, lens: lens);
  final expectHi = expectedQuoteCents(unitEur: 20);
  if (ck.ok && ck.amountTotal != null && ck.amountTotal! < expectHi - 50) {
    c.hold(
      id: 'AH1-SWAP-LIVE-ITEM',
      lens: lens,
      severity: 'P0',
      title: 'Trocar live_item_id após selo baixa o checkout',
      actor: 'buyer JWT',
      pre: 'order live_item 20€; outro live_item 6€ mesmo product',
      repro: 'PATCH live_item_id; create-payment-intent',
      expected: expectHi,
      obtained: ck.amountTotal,
    );
  } else {
    c.block('AH1-SWAP-LIVE-ITEM', lens, 'swap não baixou quote', {
      'patch': patch.brief,
      'amt': ck.amountTotal,
      'li': row?['live_item_id'],
    });
  }
}

Future<void> ah2BagRecomposeNoExpire(Rtah c) async {
  final lens = 'AH2';
  final pa = await c.createProduct(price: 12, qty: 2, title: '$prefix-bag-a');
  final pb = await c.createProduct(price: 13, qty: 2, title: '$prefix-bag-b');
  final pc = await c.createProduct(price: 21, qty: 2, title: '$prefix-bag-c');
  if (pa == null || pb == null || pc == null) return;
  final oa = await c.insertOrder(productId: pa, jwt: c.buyerJwt, price: 12);
  final ob = await c.insertOrder(productId: pb, jwt: c.buyerJwt, price: 13);
  final oc = await c.insertOrder(productId: pc, jwt: c.buyerJwt, price: 21);
  if (oa == null || ob == null || oc == null) return;
  final bag1 = await c.checkoutBag(lines: [bagLine(oa, pa), bagLine(ob, pb)]);
  final s1 = bag1.sessionId;
  final bag2 = await c.checkoutBag(lines: [bagLine(oa, pa), bagLine(oc, pc)]);
  final s2 = bag2.sessionId;
  HttpHit? st1;
  HttpHit? st2;
  if (s1 != null) st1 = await c.stripeSession(s1);
  if (s2 != null) st2 = await c.stripeSession(s2);
  final ra = await c.orderRow(oa);
  final rb = await c.orderRow(ob);
  final rc = await c.orderRow(oc);
  final s1Status = st1?.map?['status']?.toString();
  final s1Url = st1?.map?['url']?.toString();
  final s1Paid = st1?.map?['payment_status']?.toString();
  final s2Status = st2?.map?['status']?.toString();
  c.note('AH2.BAG.RECOMPOSE', 'bag A+B then A+C', {
    'bag1': '${bag1.brief} reused=${bag1.reused}',
    'bag2': '${bag2.brief} reused=${bag2.reused}',
    's1': s1,
    's2': s2,
    's1_status': s1Status,
    's1_url_live': s1Url != null && s1Url.isNotEmpty,
    's2_status': s2Status,
    'oa_sid': ra?['stripe_checkout_session_id'],
    'ob_sid': rb?['stripe_checkout_session_id'],
    'oc_sid': rc?['stripe_checkout_session_id'],
  }, lens: lens);

  final twoOpen = s1 != null &&
      s2 != null &&
      s1 != s2 &&
      s1Status == 'open' &&
      s2Status == 'open';
  if (twoOpen) {
    Map<String, Object?> payEv = {};
    if (c.stripeTestKey != null) {
      final pi = st1?.map?['payment_intent'];
      final piId = pi is Map ? pi['id']?.toString() : pi?.toString();
      if (piId != null && piId.startsWith('pi_')) {
        final conf = await c.stripeConfirmPi(piId);
        payEv['confirm'] = conf.brief;
        payEv['pi'] = piId;
        if (conf.ok) {
          final settle = await c.settleGet(s1);
          payEv['settle'] = settle.brief;
          final ra2 = await c.orderRow(oa);
          final rb2 = await c.orderRow(ob);
          payEv['oa'] = ra2?['status'];
          payEv['ob'] = rb2?['status'];
          payEv['oa_pi'] = ra2?['stripe_payment_intent_id'];
        }
      } else {
        payEv['no_pi'] = true;
      }
    }
    final paidStuck = payEv['oa'] == 'pago' && payEv['ob'] == 'pago';
    c.hold(
      id: 'AH2-BAG-RECOMPOSE-ORPHAN',
      lens: lens,
      severity: paidStuck ? 'P1' : 'P1',
      title:
          'Bag A+B → bag A+C (montantes diferentes) não expira Session S1; 2 cs_ abertas',
      actor: 'buyer JWT',
      pre: '3 orders mesmo seller; checkout saco A+B depois A+C',
      repro:
          'POST create-payment-intent bag A+B; POST bag A+C; GET Stripe session S1',
      expected: 'S1 expired; só S2 open; bag_order_ids S2',
      obtained: {
        's1_status': s1Status,
        's2_status': s2Status,
        's1_payment_status': s1Paid,
        'url_live': s1Url != null && s1Url.isNotEmpty,
        'oa_db': ra?['stripe_checkout_session_id'],
        'ob_db': rb?['stripe_checkout_session_id'],
        'oc_db': rc?['stripe_checkout_session_id'],
        'pay': payEv,
      },
      evidence: {
        's1': s1,
        's2': s2,
        'bag1_amt': bag1.amountTotal,
        'bag2_amt': bag2.amountTotal,
      },
    );
  } else if (s1 != null && s1Status == 'expired') {
    c.block('AH2-BAG-RECOMPOSE-ORPHAN', lens, 'S1 expirou no recompose', {
      's1': s1Status,
      's2': s2Status,
    });
  } else {
    c.note('AH2.BAG.RECOMPOSE.other', 'não 2 open', {
      's1': s1Status,
      's2': s2Status,
      'same': s1 == s2,
    }, lens: lens);
  }
}

Future<void> ah2SingleThenBagNoExpire(Rtah c) async {
  final lens = 'AH2';
  final pa = await c.createProduct(price: 14, qty: 2, title: '$prefix-s2b-a');
  final pb = await c.createProduct(price: 16, qty: 2, title: '$prefix-s2b-b');
  if (pa == null || pb == null) return;
  final oa = await c.insertOrder(productId: pa, jwt: c.buyerJwt, price: 14);
  final ob = await c.insertOrder(productId: pb, jwt: c.buyerJwt, price: 16);
  if (oa == null || ob == null) return;
  final single = await c.checkout(orderId: oa, amount: 50);
  final bag = await c.checkoutBag(lines: [bagLine(oa, pa), bagLine(ob, pb)]);
  final s1 = single.sessionId;
  final s2 = bag.sessionId;
  HttpHit? st1;
  if (s1 != null) st1 = await c.stripeSession(s1);
  c.note('AH2.SINGLE.THEN.BAG', 'single A then bag A+B', {
    'single': '${single.brief} reused=${single.reused}',
    'bag': '${bag.brief} reused=${bag.reused}',
    's1_status': st1?.map?['status'],
    's1_url': (st1?.map?['url']?.toString() ?? '').isNotEmpty,
    'same': s1 == s2,
  }, lens: lens);
  if (s1 != null &&
      s2 != null &&
      s1 != s2 &&
      st1?.map?['status'] == 'open') {
    c.hold(
      id: 'AH2-SINGLE-THEN-BAG-ORPHAN',
      lens: lens,
      severity: 'P1',
      title:
          'Checkout single A depois saco A+B não expira Session single (inverso AE2 bag→single)',
      actor: 'buyer JWT',
      pre: 'order A session open; bag A+B amount diferente',
      repro: 'POST create-payment-intent order A; POST bag A+B',
      expected: 'S1 expired (paridade expireSharedBagCheckoutSession)',
      obtained: {
        's1_status': st1?.map?['status'],
        's2': s2,
        'oa': (await c.orderRow(oa))?['stripe_checkout_session_id'],
        'ob': (await c.orderRow(ob))?['stripe_checkout_session_id'],
      },
      evidence: {'s1': s1, 's2': s2},
    );
  } else if (st1?.map?['status'] == 'expired') {
    c.block('AH2-SINGLE-THEN-BAG-ORPHAN', lens, 'single expirou', st1?.brief);
  } else {
    c.note('AH2.S2B.other', 'sem orphan claro', {
      's1': st1?.map?['status'],
      'same': s1 == s2,
    }, lens: lens);
  }
}

Future<void> ah2BagPermutationReuse(Rtah c) async {
  final lens = 'AH2';
  final pa = await c.createProduct(price: 10, qty: 2, title: '$prefix-perm-a');
  final pb = await c.createProduct(price: 11, qty: 2, title: '$prefix-perm-b');
  if (pa == null || pb == null) return;
  final oa = await c.insertOrder(productId: pa, jwt: c.buyerJwt, price: 10);
  final ob = await c.insertOrder(productId: pb, jwt: c.buyerJwt, price: 11);
  if (oa == null || ob == null) return;
  final b1 = await c.checkoutBag(lines: [bagLine(oa, pa), bagLine(ob, pb)]);
  final b2 = await c.checkoutBag(lines: [bagLine(ob, pb), bagLine(oa, pa)]);
  c.note('AH2.PERM', 'bag A,B vs B,A', {
    'b1': '${b1.sessionId} reused=${b1.reused} amt=${b1.amountTotal}',
    'b2': '${b2.sessionId} reused=${b2.reused} amt=${b2.amountTotal}',
  }, lens: lens);
  if (b1.ok && b2.ok && b1.sessionId != null && b2.sessionId == b1.sessionId) {
    c.block('AH2-BAG-PERM-REUSE', lens, 'permutação reutiliza (sort ids)', b2.brief);
  } else if (b1.ok && b2.ok && b1.sessionId != b2.sessionId) {
    HttpHit? st1;
    if (b1.sessionId != null) st1 = await c.stripeSession(b1.sessionId!);
    if (st1?.map?['status'] == 'open') {
      c.hold(
        id: 'AH2-BAG-PERM-DUAL',
        lens: lens,
        severity: 'P2',
        title: 'Mesmo saco ordem diferente cria 2ª Session sem expirar a 1ª',
        actor: 'buyer JWT',
        pre: 'bag A,B depois B,A mesmos ids',
        repro: '2× bag_checkout com linhas permutadas',
        expected: 'reuse após sort',
        obtained: {'s1': b1.sessionId, 's2': b2.sessionId, 's1_st': st1?.map?['status']},
      );
    } else {
      c.note('AH2.PERM.no_dual', 's1 not open', st1?.brief, lens: lens);
    }
  }
}

Future<void> ah2SameAmountDifferentLinesNoReuse(Rtah c) async {
  final lens = 'AH2';
  final pa = await c.createProduct(price: 10, qty: 2, title: '$prefix-same-a');
  final pb = await c.createProduct(price: 10, qty: 2, title: '$prefix-same-b');
  final pc = await c.createProduct(price: 10, qty: 2, title: '$prefix-same-c');
  if (pa == null || pb == null || pc == null) return;
  final oa = await c.insertOrder(productId: pa, jwt: c.buyerJwt, price: 10);
  final ob = await c.insertOrder(productId: pb, jwt: c.buyerJwt, price: 10);
  final oc = await c.insertOrder(productId: pc, jwt: c.buyerJwt, price: 10);
  if (oa == null || ob == null || oc == null) return;
  final b1 = await c.checkoutBag(lines: [bagLine(oa, pa), bagLine(ob, pb)]);
  final b2 = await c.checkoutBag(lines: [bagLine(oa, pa), bagLine(oc, pc)]);
  HttpHit? st1;
  if (b1.sessionId != null) st1 = await c.stripeSession(b1.sessionId!);
  c.note('AH2.SAME.AMT.DIFF', 'A+B vs A+C mesmo montante', {
    'b1': '${b1.sessionId} amt=${b1.amountTotal} reused=${b1.reused}',
    'b2': '${b2.sessionId} amt=${b2.amountTotal} reused=${b2.reused}',
    's1_st': st1?.map?['status'],
    'same_sid': b1.sessionId == b2.sessionId,
  }, lens: lens);
  if (b1.ok && b2.ok && b1.sessionId != null && b1.sessionId == b2.sessionId) {
    c.hold(
      id: 'AH2-SAME-AMT-WRONG-REUSE',
      lens: lens,
      severity: 'P1',
      title: 'Saco A+C reutiliza Session de A+B porque o montante coincide',
      actor: 'buyer JWT',
      pre: '3 SKUs 10€; bag A+B depois A+C',
      repro: '2× bag_checkout mesmo amount_total linhas diferentes',
      expected: 'não reuse (bag_order_ids)',
      obtained: b2.sessionId,
    );
  } else if (b1.sessionId != b2.sessionId && st1?.map?['status'] == 'open') {
    c.hold(
      id: 'AH2-SAME-AMT-NO-EXPIRE',
      lens: lens,
      severity: 'P1',
      title:
          'Saco A+B vs A+C mesmo montante: não reuse (ok) mas S1 fica open (não expira)',
      actor: 'buyer JWT',
      pre: '3 SKUs 10€',
      repro: 'bag A+B; bag A+C; Stripe retrieve S1',
      expected: 'S1 expired',
      obtained: {'s1': b1.sessionId, 's2': b2.sessionId, 's1_st': st1?.map?['status']},
    );
  } else {
    c.block('AH2-SAME-AMT', lens, 'reuse correcto ou S1 expirada', {
      'same': b1.sessionId == b2.sessionId,
      's1': st1?.map?['status'],
    });
  }
}

Future<void> ah2SingleShipPatchOrphan(Rtah c) async {
  final lens = 'AH2';
  final pid = await c.createProduct(price: 18, qty: 1, title: '$prefix-ship-orph');
  if (pid == null) return;
  final oid = await c.insertOrder(
    productId: pid,
    jwt: c.buyerJwt,
    price: 18,
    shipping: 'entrega em mão',
  );
  final ck1 = await c.checkout(orderId: oid ?? '', shipping: 'mao', amount: 50);
  await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    service: true,
    body: {'shipping_method': 'Envio Transportadora (€3.50)'},
  );
  final ck2 = await c.checkout(orderId: oid ?? '', shipping: 'carrier', amount: 50);
  HttpHit? st1;
  if (ck1.sessionId != null) st1 = await c.stripeSession(ck1.sessionId!);
  c.note('AH2.SHIP.ORPHAN', 'mão session depois carrier (service patch portes)', {
    'ck1': '${ck1.amountTotal} ${ck1.sessionId}',
    'ck2': '${ck2.amountTotal} ${ck2.sessionId} reused=${ck2.reused}',
    's1_st': st1?.map?['status'],
  }, lens: lens);
  if (ck1.sessionId != null &&
      ck2.sessionId != null &&
      ck1.sessionId != ck2.sessionId &&
      st1?.map?['status'] == 'open' &&
      ck1.amountTotal != ck2.amountTotal) {
    c.hold(
      id: 'AH2-SINGLE-AMOUNT-MISMATCH-NO-EXPIRE',
      lens: lens,
      severity: 'P2',
      title:
          'Single checkout: amount mismatch não chama expire na Session não-bag; S1 open + S2 nova',
      actor: 'buyer JWT + service patch shipping (observação)',
      pre: 'S1 mão; PATCH shipping carrier; S2',
      repro: '2× create-payment-intent amount diferente na mesma order',
      expected: 'S1 expired',
      obtained: {
        's1': ck1.sessionId,
        's2': ck2.sessionId,
        's1_st': st1?.map?['status'],
        'a1': ck1.amountTotal,
        'a2': ck2.amountTotal,
      },
    );
  } else {
    c.block('AH2-SINGLE-AMOUNT-MISMATCH-NO-EXPIRE', lens, 'sem dual open', {
      's1': st1?.map?['status'],
      'same': ck1.sessionId == ck2.sessionId,
    });
  }
}

Future<void> ah3BundlePartialAndBuyer2(Rtah c) async {
  final lens = 'AH3';
  final p1 = await c.createProduct(price: 12, qty: 1, title: '$prefix-bun-1');
  final p2 = await c.createProduct(price: 14, qty: 1, title: '$prefix-bun-2');
  if (p1 == null || p2 == null) return;
  final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
    'seller_id': c.sellerId,
    'buyer_id': c.buyerId,
    'product_ids': [p1, p2],
    'subtotal_eur': 26,
    'discount_pct': 10,
    'discount_eur': 2.6,
    'total_eur': 23.4,
    'status': 'accepted',
  });
  final bid = bun.firstId;
  if (bid != null) c.createdBundleIds.add(bid);
  c.note('AH3.BUN.ins', 'bundle accepted JWT buyer', bun.brief, lens: lens);
  if (bid == null) {
    final bunS = await c.rest('POST', 'product_bundles', jwt: c.sellerJwt, body: {
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'product_ids': [p1, p2],
      'subtotal_eur': 26,
      'total_eur': 23.4,
      'status': 'accepted',
    });
    final bid2 = bunS.firstId;
    if (bid2 != null) c.createdBundleIds.add(bid2);
    c.note('AH3.BUN.seller', 'bundle via seller', bunS.brief, lens: lens);
    if (bid2 == null) {
      return c.block('AH3-BUNDLE', lens, 'não criou bundle', bunS.brief);
    }
    return ah3BundleWithId(c, bid2, p1, p2);
  }
  await ah3BundleWithId(c, bid, p1, p2);
}

Future<void> ah3BundleWithId(Rtah c, String bid, String p1, String p2) async {
  final lens = 'AH3';
  final o1 = await c.insertOrder(
    productId: p1,
    jwt: c.buyerJwt,
    price: 12,
    bundleId: bid,
  );
  final o2 = await c.insertOrder(
    productId: p2,
    jwt: c.buyerJwt,
    price: 14,
    bundleId: bid,
  );
  if (o1 == null || o2 == null) {
    return c.note('AH3.BUN.ord.fail', 'orders bundle', '$o1 $o2', lens: lens);
  }
  final partial = await c.checkoutBag(lines: [bagLine(o1, p1)]);
  c.note('AH3.PARTIAL', 'bag só 1 linha do conjunto aceite', partial.brief,
      lens: lens);
  if (partial.ok) {
    c.hold(
      id: 'AH3-BUNDLE-PARTIAL',
      lens: lens,
      severity: 'P1',
      title: 'Checkout saco parcial de conjunto aceite',
      actor: 'buyer JWT',
      pre: 'bundle accepted 2 SKUs; 2 orders',
      repro: 'bag_checkout só order 1',
      expected: 'blocked must include all items',
      obtained: partial.brief,
    );
  } else {
    c.block('AH3-BUNDLE-PARTIAL', lens, 'parcial bloqueado', partial.brief);
  }
  final full = await c.checkoutBag(lines: [bagLine(o1, p1), bagLine(o2, p2)]);
  c.note('AH3.FULL', 'bag completo conjunto', {
    'amt': full.amountTotal,
    'ok': full.ok,
    'brief': full.brief,
  }, lens: lens);
  if (c.buyer2Jwt != null && c.buyer2Id != null) {
    final b2 = await c.checkoutBag(
      lines: [bagLine(o1, p1), bagLine(o2, p2)],
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    );
    c.note('AH3.B2', 'B2 checkout bundle B1', b2.brief, lens: lens);
    if (b2.ok) {
      c.hold(
        id: 'AH3-BUNDLE-B2',
        lens: lens,
        severity: 'P1',
        title: '2.º buyer faz checkout do conjunto de B1',
        actor: 'buyer2 JWT',
        pre: 'orders buyer=B1 bundle accepted',
        repro: 'create-payment-intent bag JWT B2',
        expected: 'blocked',
        obtained: b2.brief,
      );
    } else {
      c.block('AH3-BUNDLE-B2', lens, 'B2 bloqueado', b2.brief);
    }
  }
}

Future<void> ah3BundleTotalPatch(Rtah c) async {
  final lens = 'AH3';
  if (c.createdBundleIds.isEmpty) return;
  final bid = c.createdBundleIds.last;
  final patchB = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.buyerJwt,
    body: {'total_eur': 1.0},
  );
  final patchS = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.sellerJwt,
    body: {'total_eur': 1.0},
  );
  c.note('AH3.TOTAL.PATCH', 'PATCH total_eur=1', {
    'buyer': patchB.brief,
    'seller': patchS.brief,
  }, lens: lens);
  final got = await c.rest(
    'GET',
    'product_bundles?id=eq.$bid&select=id,total_eur,status,buyer_id',
    service: true,
  );
  final total = numOf(got.map?['total_eur']);
  if (total != null && total <= 1.05) {
    c.hold(
      id: 'AH3-BUNDLE-TOTAL-PATCH',
      lens: lens,
      severity: 'P1',
      title: 'JWT altera total_eur do conjunto aceite para 1€',
      actor: 'buyer/seller JWT',
      pre: 'bundle accepted',
      repro: 'PATCH product_bundles total_eur=1',
      expected: 'imutável após accepted',
      obtained: total,
    );
  } else {
    c.block('AH3-BUNDLE-TOTAL-PATCH', lens, 'total não baixou', got.brief);
  }
}

Future<void> ah3TwoBundleIds(Rtah c) async {
  final lens = 'AH3';
  final p1 = await c.createProduct(price: 9, qty: 1, title: '$prefix-mix-1');
  final p2 = await c.createProduct(price: 9, qty: 1, title: '$prefix-mix-2');
  if (p1 == null || p2 == null) return;
  final b1 = await c.rest('POST', 'product_bundles', service: true, body: {
    'seller_id': c.sellerId,
    'buyer_id': c.buyerId,
    'product_ids': [p1],
    'total_eur': 9,
    'status': 'accepted',
  });
  final b2 = await c.rest('POST', 'product_bundles', service: true, body: {
    'seller_id': c.sellerId,
    'buyer_id': c.buyerId,
    'product_ids': [p2],
    'total_eur': 9,
    'status': 'accepted',
  });
  final id1 = b1.firstId;
  final id2 = b2.firstId;
  if (id1 != null) c.createdBundleIds.add(id1);
  if (id2 != null) c.createdBundleIds.add(id2);
  if (id1 == null || id2 == null) return;
  final o1 = await c.insertOrder(
      productId: p1, jwt: c.buyerJwt, price: 9, bundleId: id1);
  final o2 = await c.insertOrder(
      productId: p2, jwt: c.buyerJwt, price: 9, bundleId: id2);
  if (o1 == null || o2 == null) return;
  final mix = await c.checkoutBag(lines: [bagLine(o1, p1), bagLine(o2, p2)]);
  c.note('AH3.TWO.BUN', 'bag 2 bundle_id', mix.brief, lens: lens);
  if (mix.ok) {
    c.hold(
      id: 'AH3-TWO-BUNDLE-IDS',
      lens: lens,
      severity: 'P1',
      title: 'Saco mistura dois bundle_id',
      actor: 'buyer JWT',
      pre: '2 bundles accepted',
      repro: 'bag_checkout orders de bundles diferentes',
      expected: 'blocked cannot mix',
      obtained: mix.brief,
    );
  } else {
    c.block('AH3-TWO-BUNDLE-IDS', lens, 'mix bloqueado', mix.brief);
  }
}

Future<void> ah4CapturedNoReopen(Rtah c) async {
  final lens = 'AH4';
  final pid = await c.createProduct(price: 19, qty: 2, title: '$prefix-cap');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 19);
  if (oid == null) return;
  await c.rest('PATCH', 'orders?id=eq.$oid', service: true, body: {
    'status': 'pago',
    'amount_paid_cents': 2065,
    'stripe_payment_intent_id': 'pi_fake_ah4_$stamp',
  });
  final ck = await c.checkout(orderId: oid, amount: 50);
  c.note('AH4.REOPEN', 'checkout order já pago (fixture service)', ck.brief,
      lens: lens);
  if (ck.ok) {
    c.hold(
      id: 'AH4-CAPTURED-REOPEN',
      lens: lens,
      severity: 'P1',
      title: 'create-payment-intent abre Session em order já capturada',
      actor: 'buyer JWT',
      pre: 'order status=pago amount_paid_cents>0 PI set (service fixture)',
      repro: 'POST create-payment-intent',
      expected: 'blocked already captured',
      obtained: ck.brief,
    );
  } else {
    c.block('AH4-CAPTURED-REOPEN', lens, 'capturado não reabre', ck.brief);
  }
}

Future<void> ah5StockOneTwoCheckouts(Rtah c) async {
  final lens = 'AH5';
  final pid = await c.createProduct(price: 12, qty: 1, title: '$prefix-stk1');
  if (pid == null) return;
  final o1 = await c.insertOrder(
    productId: pid,
    jwt: c.buyerJwt,
    price: 12,
  );
  final o2 = await c.insertOrder(
    productId: pid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    price: 12,
  );
  if (o1 == null || o2 == null) {
    return c.note('AH5.STK.ord', 'segunda order', '$o1 $o2', lens: lens);
  }
  final ck1 = await c.checkout(orderId: o1, amount: 50);
  final ck2 = await c.checkout(
    orderId: o2,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    amount: 50,
  );
  c.note('AH5.STK1.TWO', 'stock=1 duas sessions', {
    'ck1': ck1.brief,
    'ck2': ck2.brief,
  }, lens: lens);
  if (ck1.ok && ck2.ok) {
    c.hold(
      id: 'AH5-STOCK1-TWO-SESSIONS',
      lens: lens,
      severity: 'P2',
      title: 'Stock=1: dois buyers obtêm Session aberta (captura só no settle)',
      actor: 'buyer + buyer2 JWT',
      pre: 'product qty=1; duas orders',
      repro: '2× create-payment-intent',
      expected: '2.ª Session bloqueada por hold da 1.ª',
      obtained: {'s1': ck1.sessionId, 's2': ck2.sessionId},
    );
  } else {
    c.block('AH5-STOCK1-TWO-SESSIONS', lens, '2.ª checkout bloqueada', {
      'ck1': ck1.brief,
      'ck2': ck2.brief,
    });
  }
}

Future<void> ah5SellerQtyInflateWithHold(Rtah c) async {
  final lens = 'AH5';
  final pid = await c.createProduct(price: 8, qty: 1, title: '$prefix-inf');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 8);
  final patch = await c.rest(
    'PATCH',
    'products?id=eq.$pid',
    jwt: c.sellerJwt,
    body: {'quantity': 9},
  );
  final row = await c.productRow(pid);
  c.note('AH5.INFLATE', 'seller PATCH qty 1→9 com order hold', {
    'patch': patch.brief,
    'qty': row?['quantity'],
    'oid': oid,
  }, lens: lens);
  if (numOf(row?['quantity']) == 9) {
    c.hold(
      id: 'AH5-SELLER-QTY-INFLATE-HOLD',
      lens: lens,
      severity: 'P1',
      title: 'Seller sobe quantity com order activa a prender stock',
      actor: 'seller JWT',
      pre: 'product qty=1 + order reserva',
      repro: 'PATCH products quantity=9',
      expected: 'blocked active order',
      obtained: row?['quantity'],
    );
  } else {
    c.block('AH5-SELLER-QTY-INFLATE-HOLD', lens, 'inflate bloqueado', patch.brief);
  }
}

Future<void> ah5JwtQtyInflate(Rtah c) async {
  final lens = 'AH5';
  final pid = await c.createProduct(price: 7, qty: 5, title: '$prefix-bq');
  if (pid == null) return;
  final hit = await c.insertOrderHit(
    productId: pid,
    jwt: c.buyerJwt,
    price: 7,
    qty: 5,
  );
  final row = hit.firstId != null ? await c.orderRow(hit.firstId!) : null;
  c.note('AH5.JWT.QTY', 'INSERT qty=5 stock=5', {
    'hit': hit.brief,
    'qty': row?['quantity'],
    'cq': row?['contract_qty'],
  }, lens: lens);
  if (row != null && numOf(row['quantity']) == 5) {
    final ck = await c.checkout(orderId: hit.firstId!, quantity: 5, amount: 50);
    c.note('AH5.JWT.QTY.ck', 'checkout qty5', ck.brief, lens: lens);
    if (ck.ok) {
      c.note('AH5.JWT.QTY.ok', 'qty=5 permitido se stock=5 (não inflate)', ck.amountTotal,
          lens: lens);
    }
  } else {
    c.block('AH5-JWT-QTY5', lens, 'qty5 recusado ou selado 1', hit.brief);
  }
}

Future<void> ah6ParallelCheckout(Rtah c) async {
  final lens = 'AH6';
  final pid = await c.createProduct(price: 17, qty: 1, title: '$prefix-race');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 17);
  if (oid == null) return;
  final rs = await parallel([
    c.checkout(orderId: oid, amount: 50),
    c.checkout(orderId: oid, amount: 50),
  ]);
  final sids = rs.map((e) => e.sessionId).whereType<String>().toSet();
  c.note('AH6.PAR.SINGLE', 'Future.wait 2× same order', {
    'a': rs[0].brief,
    'b': rs[1].brief,
    'unique_cs': sids.length,
  }, lens: lens);
  if (sids.length > 1) {
    final sts = <String, String?>{};
    for (final s in sids) {
      final st = await c.stripeSession(s);
      sts[s] = st.map?['status']?.toString();
    }
    final open = sts.values.where((v) => v == 'open').length;
    if (open > 1) {
      c.hold(
        id: 'AH6-RACE-TWO-OPEN',
        lens: lens,
        severity: 'P1',
        title: 'POST paralelo cria 2 Sessions open na mesma order',
        actor: 'buyer JWT',
        pre: '1 order',
        repro: 'Future.wait 2× create-payment-intent',
        expected: '1 cs_ (claim slot)',
        obtained: sts,
      );
    } else {
      c.block('AH6-RACE-TWO-OPEN', lens, 'não 2 open', sts);
    }
  } else {
    c.block('AH6-RACE-TWO-OPEN', lens, '1 session ou fail', sids.toList());
  }
}

Future<void> ah6ParallelBag(Rtah c) async {
  final lens = 'AH6';
  final pa = await c.createProduct(price: 8, qty: 1, title: '$prefix-pr-a');
  final pb = await c.createProduct(price: 9, qty: 1, title: '$prefix-pr-b');
  if (pa == null || pb == null) return;
  final oa = await c.insertOrder(productId: pa, jwt: c.buyerJwt, price: 8);
  final ob = await c.insertOrder(productId: pb, jwt: c.buyerJwt, price: 9);
  if (oa == null || ob == null) return;
  final lines = [bagLine(oa, pa), bagLine(ob, pb)];
  final rs = await parallel([
    c.checkoutBag(lines: lines),
    c.checkoutBag(lines: lines),
  ]);
  final sids = rs.map((e) => e.sessionId).whereType<String>().toSet();
  c.note('AH6.PAR.BAG', 'Future.wait 2× same bag', {
    'a': rs[0].brief,
    'b': rs[1].brief,
    'unique': sids.length,
  }, lens: lens);
  if (sids.length > 1) {
    final sts = <String, String?>{};
    for (final s in sids) {
      sts[s] = (await c.stripeSession(s)).map?['status']?.toString();
    }
    final open = sts.values.where((v) => v == 'open').length;
    if (open > 1) {
      c.hold(
        id: 'AH6-BAG-RACE-TWO-OPEN',
        lens: lens,
        severity: 'P1',
        title: 'Bag paralelo cria 2 Sessions open',
        actor: 'buyer JWT',
        pre: '2 orders mesmo saco',
        repro: 'Future.wait 2× bag_checkout',
        expected: '1 cs_',
        obtained: sts,
      );
    } else {
      c.block('AH6-BAG-RACE-TWO-OPEN', lens, 'não 2 open', sts);
    }
  } else {
    c.block('AH6-BAG-RACE-TWO-OPEN', lens, '1 session', sids.toList());
  }
}

Future<void> ah7CrossBuyerCheckout(Rtah c) async {
  final lens = 'AH7';
  final pid = await c.createProduct(price: 13, qty: 1, title: '$prefix-xbuy');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 13);
  if (oid == null || c.buyer2Jwt == null) return;
  final ck = await c.checkout(
    orderId: oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    amount: 50,
  );
  c.note('AH7.B2.ORDER', 'B2 checkout order B1', ck.brief, lens: lens);
  if (ck.ok) {
    c.hold(
      id: 'AH7-B2-CHECKOUT-B1',
      lens: lens,
      severity: 'P0',
      title: '2.º buyer inicia Stripe na order de B1',
      actor: 'buyer2 JWT',
      pre: 'order buyer=B1',
      repro: 'POST create-payment-intent JWT B2 buyer_id=B2',
      expected: 'blocked not owner',
      obtained: ck.brief,
    );
  } else {
    c.block('AH7-B2-CHECKOUT-B1', lens, 'B2 bloqueado', ck.brief);
  }
}

Future<void> ah7AnonAndSellerCheckout(Rtah c) async {
  final lens = 'AH7';
  final pid = await c.createProduct(price: 11, qty: 1, title: '$prefix-anon');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 11);
  if (oid == null) return;
  final anon = await c.edge('create-payment-intent', {
    'buyer_id': c.buyerId,
    'order_id': oid,
    'amount': 50,
    'currency': 'eur',
    'shipping_method': 'mao',
  });
  c.note('AH7.ANON', 'anon checkout', anon.brief, lens: lens);
  if (anon.ok) {
    c.hold(
      id: 'AH7-ANON-CHECKOUT',
      lens: lens,
      severity: 'P0',
      title: 'anon cria Checkout Session',
      actor: 'anon',
      pre: 'order B1',
      repro: 'POST create-payment-intent sem JWT user',
      expected: '401/400',
      obtained: anon.brief,
    );
  } else {
    c.block('AH7-ANON-CHECKOUT', lens, 'anon bloqueado', anon.brief);
  }
  final sel = await c.checkout(
    orderId: oid,
    jwt: c.sellerJwt,
    buyer: c.sellerId,
    amount: 50,
  );
  c.note('AH7.SELLER', 'seller JWT buyer_id=seller', sel.brief, lens: lens);
  if (sel.ok) {
    c.hold(
      id: 'AH7-SELLER-AS-BUYER',
      lens: lens,
      severity: 'P1',
      title: 'Seller JWT inicia checkout da order do buyer',
      actor: 'seller JWT',
      pre: 'order buyer=B1',
      repro: 'POST create-payment-intent JWT seller buyer_id=seller',
      expected: 'blocked',
      obtained: sel.brief,
    );
  } else {
    c.block('AH7-SELLER-AS-BUYER', lens, 'seller bloqueado', sel.brief);
  }
}

Future<void> ah7BuyerRefund(Rtah c) async {
  final lens = 'AH7';
  final pid = await c.createProduct(price: 10, qty: 1, title: '$prefix-bref');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 10);
  if (oid == null) return;
  final r = await c.refund(oid, jwt: c.buyerJwt);
  c.note('AH7.BUYER.REFUND', 'buyer chama refund-order', r.brief, lens: lens);
  if (r.ok && r.map?['ok'] == true && r.map?['skipped'] != true) {
    c.hold(
      id: 'AH7-BUYER-REFUND',
      lens: lens,
      severity: 'P1',
      title: 'Buyer executa refund-order',
      actor: 'buyer JWT',
      pre: 'order B1',
      repro: 'POST refund-order JWT buyer',
      expected: '403 seller-only',
      obtained: r.brief,
    );
  } else {
    c.block('AH7-BUYER-REFUND', lens, 'buyer refund recusado', r.brief);
  }
}

Future<void> ah7Seller2Refund(Rtah c) async {
  final lens = 'AH7';
  final pid = await c.createProduct(price: 10, qty: 1, title: '$prefix-s2ref');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 10);
  if (oid == null || c.seller2Jwt == null) return;
  final r = await c.refund(oid, jwt: c.seller2Jwt);
  c.note('AH7.S2.REFUND', 'S2 refund order S1', r.brief, lens: lens);
  if (r.ok && r.map?['ok'] == true && r.map?['skipped'] != true) {
    c.hold(
      id: 'AH7-S2-REFUND',
      lens: lens,
      severity: 'P1',
      title: '2.º seller reembolsa order de outro vendedor',
      actor: 'seller2 JWT',
      pre: 'order seller=S1',
      repro: 'POST refund-order JWT S2',
      expected: '403',
      obtained: r.brief,
    );
  } else {
    c.block('AH7-S2-REFUND', lens, 'S2 refund recusado', r.brief);
  }
}

Future<void> ah8WalletBaseline(Rtah c) async {
  final lens = 'AH8';
  final w = await c.wallets();
  c.note('AH8.WALLET', 'saldos staging (observação, sem captura P0)', w, lens: lens);
}
