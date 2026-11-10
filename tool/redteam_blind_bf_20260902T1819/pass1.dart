/// RED TEAM CEGO BF — marketplace / checkout pós-ATBE. Staging only. Não corrige.
library;

import 'dart:io';

import '_rtbf.dart';

Future<void> main() async {
  final c = Rtbf.fromEnv(loadEnv());
  stdout.writeln('RTBF $stamp ${c.url}');
  if (!c.url.contains(projectMust)) {
    stderr.writeln('refusing non-staging');
    exit(3);
  }
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('actors', 'login', {
    'buyer': c.buyerId,
    'seller': c.sellerId,
    'buyer2': c.buyer2Id,
    'seller2': c.seller2Id,
  });

  await bfUnicodeZwj(c);
  await bfCompactHyphenDupLine(c);
  await bfCurrencyExtreme(c);
  await bfOfferQty(c);
  await bfBundlePatchTotal(c);
  await bfSettleReorderProductIds(c);
  await bfTwoBagsShareOrder(c);
  await bfSessionReopenAfterExpire(c);
  await bfHoldCheckoutSealedOffer(c);
  await bfSecondActor(c);
  await bfFsmPosCaptura(c);
  await bfDetachOfferExact(c);
  await bfLegitCaixa(c);

  await dumpJson('${outDir()}/pass1.json', {
    'stamp': stamp,
    'auditor': 'REDTEAM_BLIND_BF_MARKETPLACE_POS_ATBE_v1',
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
    'DONE findings=${c.findings.length} blocked=${c.blocked.length} lenses=${c.lensesHit}',
  );
}

Map<String, Object?> line(String oid, String pid) => {
      'order_id': oid,
      'product_id': pid,
      'seller_id': null,
    };

Future<void> bfUnicodeZwj(Rtbf c) async {
  final sku = await c.createProduct(title: '$prefix zwj', qty: 3, price: 12);
  if (sku == null) return;
  final oid = await c.insertOrder(productId: sku, jwt: c.buyerJwt, qty: 1, price: 12);
  if (oid == null) return;
  final catalog = expectedCheckoutCents(1200);

  final variants = <String, String>{
    'zwj': '$oid\u200d',
    'zwsp': '\u200b$oid',
    'nbsp': '$oid\u00a0',
    'unicode_hyphen': oid.replaceAll('-', '\u2010'),
    'bom': '\ufeff$oid',
    'braces': '{$oid}',
  };

  for (final e in variants.entries) {
    final ck = await c.checkoutBag(
      lines: [
        {'order_id': e.value, 'product_id': sku},
      ],
      amount: 1,
    );
    final amt = ck.serverAmount;
    if (ck.ok && amt != null && amt < catalog) {
      c.hold(
        id: 'RTBF-BF2-unicode-${e.key}',
        lens: 'BF2',
        severity: 'P0',
        title: 'Unicode/ZWJ em bag_order_ids cria Session abaixo do contrato',
        actor: 'buyer JWT',
        pre: 'order $oid SKU 12€',
        repro: 'POST create-payment-intent bag_lines.order_id variante ${e.key}',
        expected: 'recusar ID não canónico ou cobrar $catalog',
        obtained: {'variant': e.key, 'status': ck.status, 'amount': amt, 'body': ck.brief},
      );
    } else if (ck.ok && (ck.checkoutSessionId ?? '').startsWith('cs_')) {
      c.note('bf2.unicode.${e.key}', 'Session criada com encoding hostil (mesmo montante?)', {
        'amt': amt,
        'catalog': catalog,
        'sid': ck.checkoutSessionId,
        'brief': ck.brief,
      }, lens: 'BF2');
    } else {
      c.block('RTBF-BF2-unicode-${e.key}', 'BF2', 'ID hostil ${e.key} recusado', ck.brief);
    }
  }
}

Future<void> bfCompactHyphenDupLine(Rtbf c) async {
  final sku = await c.createProduct(title: '$prefix dupline', qty: 4, price: 15);
  if (sku == null) return;
  final oid = await c.insertOrder(productId: sku, jwt: c.buyerJwt, qty: 1, price: 15);
  if (oid == null) return;
  final single = expectedCheckoutCents(1500);
  final doubled = expectedCheckoutCents(3000);

  final ck = await c.checkoutBag(
    lines: [
      {'order_id': oid, 'product_id': sku},
      {'order_id': compactUuid(oid), 'product_id': compactUuid(sku)},
    ],
    amount: 1,
  );
  final amt = ck.serverAmount;
  c.note('bf2.dupline', 'hífen+compact mesma order no mesmo POST', {
    'oid': oid,
    'amt': amt,
    'single': single,
    'doubled': doubled,
    'sid': ck.checkoutSessionId,
    'brief': ck.brief,
  }, lens: 'BF2');

  if (ck.ok && amt != null && amt != single) {
    final sev = amt < single ? 'P0' : 'P2';
    c.hold(
      id: 'RTBF-BF2-dup-hyphen-compact-line',
      lens: 'BF2',
      severity: sev,
      title: amt < single
          ? 'Mesma order hífen+compact no saco cobra abaixo do contrato'
          : 'Mesma order hífen+compact no saco duplica linha (montante ≠ 1 unidade)',
      actor: 'buyer JWT',
      pre: '1 order 15€; seenBag não normaliza compact vs hífen',
      repro: 'bag_lines: [hífen UUID, compact UUID] da mesma order',
      expected: '1 linha, $single cêntimos',
      obtained: {'amount': amt, 'single': single, 'doubled': doubled, 'sid': ck.checkoutSessionId},
    );
  } else {
    c.block(
      'RTBF-BF2-dup-hyphen-compact-line',
      'BF2',
      'duplicado compact∥hífen colapsado ou recusado',
      ck.brief,
    );
  }
}

Future<void> bfCurrencyExtreme(Rtbf c) async {
  final sku = await c.createProduct(title: '$prefix ccy', qty: 2, price: 10);
  if (sku == null) return;
  final oid = await c.insertOrder(productId: sku, jwt: c.buyerJwt, qty: 1, price: 10);
  if (oid == null) return;
  final eur = expectedCheckoutCents(1000);
  final variants = {
    'EUR': 'EUR',
    'Eur': 'Eur',
    'eUr': 'eUr',
    'EURO': 'EURO',
    'usd': 'usd',
    'eur_zwsp': 'eur\u200b',
    'eur_nbsp': 'eur\u00a0',
    'fullwidth': 'ｅｕｒ',
    'empty': '',
  };
  for (final e in variants.entries) {
    final ck = await c.checkout(
      orderId: oid,
      amount: 1,
      productId: sku,
      currency: e.value,
    );
    final amt = ck.serverAmount;
    if (ck.ok && amt != null && amt < eur && e.key != 'EUR' && e.key != 'Eur' && e.key != 'eUr') {
      c.hold(
        id: 'RTBF-BF1-currency-${e.key}',
        lens: 'BF1',
        severity: 'P0',
        title: 'currency=${e.value} criou Session abaixo de EUR',
        actor: 'buyer JWT',
        pre: 'SKU 10€',
        repro: 'POST create-payment-intent currency=${e.key}',
        expected: 'só eur (casing ASCII) ou recusar',
        obtained: ck.brief,
      );
    } else if (ck.ok && (e.key == 'usd' || e.key == 'EURO' || e.key == 'fullwidth' || e.key.startsWith('eur_'))) {
      c.hold(
        id: 'RTBF-BF1-currency-accepted-${e.key}',
        lens: 'BF1',
        severity: 'P2',
        title: 'currency hostil aceite (não só eur ASCII)',
        actor: 'buyer JWT',
        pre: 'SKU 10€',
        repro: 'currency=${e.value}',
        expected: 'Checkout blocked: only EUR',
        obtained: {'amt': amt, 'brief': ck.brief},
        proven: ck.ok,
      );
    } else if (ck.ok) {
      c.note('bf1.ccy.${e.key}', 'currency aceite', {'amt': amt, 'eur': eur, 'brief': ck.brief}, lens: 'BF1');
    } else {
      c.block('RTBF-BF1-currency-${e.key}', 'BF1', 'currency ${e.key} recusado', ck.brief);
    }
  }
}

Future<void> bfOfferQty(Rtbf c) async {
  final sku = await c.createProduct(title: '$prefix offerqty', qty: 5, price: 25);
  if (sku == null) return;
  final chat = await c.ensureChat(sku);
  final off = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': sku,
    'chat_id': chat,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': 6,
    'list_price': 25,
    'offered_by': 'buyer',
  });
  final offerId = off.firstId;
  if (offerId == null) {
    c.block('RTBF-BF3-offer-ins', 'BF3', 'INSERT oferta falhou', off.brief);
    return;
  }
  c.createdOfferIds.add(offerId);
  await c.rest('PATCH', 'product_offers?id=eq.$offerId', jwt: c.sellerJwt, body: {
    'status': 'accepted',
  });

  final q3 = await c.insertOrder(
    productId: sku,
    jwt: c.buyerJwt,
    qty: 3,
    price: 6,
    offerId: offerId,
  );
  if (q3 != null) {
    final row = await c.orderRow(q3);
    final ck = await c.checkout(orderId: q3, amount: 1, productId: sku);
    final amt = ck.serverAmount;
    final catalog3 = expectedCheckoutCents(2500 * 3);
    if (ck.ok && amt != null && amt < catalog3) {
      c.hold(
        id: 'RTBF-BF3-offer-qty3',
        lens: 'BF3',
        severity: 'P0',
        title: 'Oferta aceite aplica-se a quantity>1 no checkout',
        actor: 'buyer JWT',
        pre: 'SKU 25€ stock 5; oferta 6€ aceite',
        repro: 'INSERT orders quantity=3 product_offer_id; POST create-payment-intent',
        expected: 'offer_quantity_must_be_one ou catálogo 3×25€',
        obtained: {
          'order': row,
          'amt': amt,
          'catalog3': catalog3,
          'sid': ck.checkoutSessionId,
        },
      );
    } else {
      c.block('RTBF-BF3-offer-qty3', 'BF3', 'qty>1 com oferta recusado', {
        'insert_oid': q3,
        'row': row,
        'ck': ck.brief,
      });
    }
  } else {
    c.block('RTBF-BF3-offer-qty3', 'BF3', 'INSERT qty=3+offer recusado', 'no row');
  }

  final q1 = await c.insertOrder(
    productId: sku,
    jwt: c.buyerJwt,
    qty: 1,
    price: 6,
    offerId: offerId,
  );
  if (q1 != null) {
    final patchQty = await c.rest(
      'PATCH',
      'orders?id=eq.$q1',
      jwt: c.buyerJwt,
      body: {'quantity': 3, 'contract_qty': 3},
    );
    final row = await c.orderRow(q1);
    final cq = numOf(row?['contract_qty']) ?? numOf(row?['quantity']);
    if (patchQty.ok && (cq ?? 1) > 1) {
      final ck = await c.checkout(orderId: q1, amount: 1, productId: sku);
      c.hold(
        id: 'RTBF-BF3-offer-qty-patch',
        lens: 'BF3',
        severity: 'P0',
        title: 'PATCH quantity>1 após oferta selada qty=1',
        actor: 'buyer JWT',
        pre: 'order oferta 6€ qty=1',
        repro: 'PATCH orders.quantity=3,contract_qty=3; checkout',
        expected: 'order_money_fields_immutable',
        obtained: {
          'patch': patchQty.brief,
          'row': row,
          'ck': ck.brief,
          'amt': ck.serverAmount,
        },
      );
    } else {
      c.block('RTBF-BF3-offer-qty-patch', 'BF3', 'PATCH qty imutável', patchQty.brief);
    }

    final q2 = await c.insertOrder(
      productId: sku,
      jwt: c.buyerJwt,
      qty: 1,
      price: 6,
      offerId: offerId,
    );
    if (q2 != null) {
      final r2 = await c.orderRow(q2);
      final unit = numOf(r2?['contract_unit_cents']);
      if ((unit ?? 2500) < 2500 && r2?['product_offer_id'] != null) {
        c.hold(
          id: 'RTBF-BF3-offer-reuse',
          lens: 'BF3',
          severity: 'P1',
          title: '2.ª order reutiliza oferta aceite já ligada',
          actor: 'buyer JWT',
          pre: 'oferta 6€ já em order activa',
          repro: 'INSERT 2.ª order com o mesmo product_offer_id',
          expected: 'offer_already_consumed',
          obtained: r2,
        );
      } else {
        c.block('RTBF-BF3-offer-reuse', 'BF3', '2.ª order não herda oferta', r2);
      }
    } else {
      c.block('RTBF-BF3-offer-reuse', 'BF3', '2.ª order com oferta recusada', 'no row');
    }
  }
}

Future<void> bfBundlePatchTotal(Rtbf c) async {
  final hi = await c.createProduct(title: '$prefix bun-hi', qty: 2, price: 20);
  final a = await c.createProduct(title: '$prefix bun-a', qty: 3, price: 8);
  final b = await c.createProduct(title: '$prefix bun-b', qty: 3, price: 8);
  if (hi == null || a == null || b == null) return;

  final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_ids': [hi, a, b],
    'status': 'pending',
    'total_eur': 0.5,
    'discount_pct': 50,
  });
  final bid = bun.firstId;
  if (bid == null) {
    c.block('RTBF-BF3-bundle-ins', 'BF3', 'INSERT bundle falhou', bun.brief);
    return;
  }
  c.createdBundleIds.add(bid);
  final insTotal = numOf(bun.map?['total_eur']);
  c.note('bf3.bundle.ins', 'INSERT com total_eur=0.50', {
    'brief': bun.brief,
    'total': insTotal,
  }, lens: 'BF3');

  final acc = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.sellerJwt,
    body: {'status': 'accepted', 'discount_pct': 50, 'total_eur': 0.5},
  );
  c.note('bf3.bundle.acc', 'seller accept + total_eur=0.50', acc.brief, lens: 'BF3');
  final accTotal = numOf(acc.map?['total_eur']) ?? insTotal;

  final buyerPatch = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.buyerJwt,
    body: {'total_eur': 0.5},
  );
  final bpTotal = numOf(buyerPatch.map?['total_eur']);
  if (buyerPatch.ok && bpTotal != null && bpTotal <= 0.5 && (accTotal ?? 99) > 1) {
    c.hold(
      id: 'RTBF-BF3-bundle-buyer-patch-total',
      lens: 'BF3',
      severity: 'P0',
      title: 'Buyer PATCH total_eur do conjunto aceite para 0,50 €',
      actor: 'buyer JWT',
      pre: 'bundle accepted 3 SKUs',
      repro: 'PATCH product_bundles.total_eur=0.50',
      expected: 'total congelado',
      obtained: buyerPatch.map,
    );
  } else {
    c.block('RTBF-BF3-bundle-buyer-patch-total', 'BF3', 'buyer não muda total aceite', buyerPatch.brief);
  }

  final sellerPatch = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.sellerJwt,
    body: {'total_eur': 0.5, 'discount_pct': 50},
  );
  final spTotal = numOf(sellerPatch.map?['total_eur']);
  if (sellerPatch.ok && spTotal != null && spTotal <= 0.5 && (accTotal ?? 99) > 1) {
    c.hold(
      id: 'RTBF-BF3-bundle-seller-patch-total',
      lens: 'BF3',
      severity: 'P0',
      title: 'Seller PATCH total_eur do conjunto aceite para 0,50 €',
      actor: 'seller JWT',
      pre: 'bundle accepted',
      repro: 'PATCH total_eur=0.50 após accepted',
      expected: 'totais congelados em accepted',
      obtained: sellerPatch.map,
    );
  } else {
    c.block(
      'RTBF-BF3-bundle-seller-patch-total',
      'BF3',
      'seller não muda total aceite',
      sellerPatch.brief,
    );
  }

  final reorder = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.sellerJwt,
    body: {
      'product_ids': [b, a, hi],
    },
  );
  c.note('bf3.bundle.reorder', 'PATCH product_ids reordenados', reorder.brief, lens: 'BF3');

  final oHi = await c.insertOrder(productId: hi, jwt: c.buyerJwt, qty: 1, price: 20, bundleId: bid);
  final oA = await c.insertOrder(productId: a, jwt: c.buyerJwt, qty: 1, price: 8, bundleId: bid);
  final oB = await c.insertOrder(productId: b, jwt: c.buyerJwt, qty: 1, price: 8, bundleId: bid);
  if (oHi == null || oA == null || oB == null) {
    c.block('RTBF-BF3-bundle-orders', 'BF3', 'orders do conjunto falharam', {
      'hi': oHi,
      'a': oA,
      'b': oB,
    });
    return;
  }

  final ckFull = await c.checkoutBag(
    lines: [
      {'order_id': oHi, 'product_id': hi},
      {'order_id': oA, 'product_id': a},
      {'order_id': oB, 'product_id': b},
    ],
    amount: 1,
  );
  final catalog = expectedCheckoutCents(2000 + 800 + 800);
  final amt = ckFull.serverAmount;
  c.note('bf3.bundle.fullck', 'saco completo conjunto', {
    'amt': amt,
    'catalog': catalog,
    'bundle_total': accTotal,
    'brief': ckFull.brief,
  }, lens: 'BF3');

  if (ckFull.ok && amt != null && accTotal != null && amt < catalog - 50) {
    final expectedBundle = expectedCheckoutCents(euroToCents(accTotal));
    if ((spTotal ?? accTotal) <= 0.5) {
      c.hold(
        id: 'RTBF-BF3-bundle-checkout-patched-total',
        lens: 'BF3',
        severity: 'P0',
        title: 'Checkout do conjunto usa total_eur forjado',
        actor: 'buyer JWT',
        pre: 'bundle accepted; PATCH total tentado',
        repro: 'bag_checkout 3 linhas',
        expected: 'catálogo ou total servidor do desconto 50% (18€ + protecção)',
        obtained: {'amt': amt, 'catalog': catalog, 'bundle_total': accTotal, 'expectedBundle': expectedBundle},
      );
    }
  }
}

Future<void> bfSettleReorderProductIds(Rtbf c) async {
  final p1 = await c.createProduct(title: '$prefix reord-1', qty: 2, price: 18);
  final p2 = await c.createProduct(title: '$prefix reord-2', qty: 2, price: 9);
  if (p1 == null || p2 == null) return;
  final o1 = await c.insertOrder(productId: p1, jwt: c.buyerJwt, qty: 1, price: 18);
  final o2 = await c.insertOrder(productId: p2, jwt: c.buyerJwt, qty: 1, price: 9);
  if (o1 == null || o2 == null) return;

  final swapped = await c.checkoutBag(
    lines: [
      {'order_id': o1, 'product_id': p2},
      {'order_id': o2, 'product_id': p1},
    ],
    amount: 1,
  );
  if (swapped.ok) {
    final amt = swapped.serverAmount;
    final honest = expectedCheckoutCents(1800 + 900);
    c.note('bf2.reorder.ck', 'bag product_ids trocados vs orders', {
      'amt': amt,
      'honest': honest,
      'sid': swapped.checkoutSessionId,
      'brief': swapped.brief,
    }, lens: 'BF2');
    if (amt != null && amt < honest) {
      c.hold(
        id: 'RTBF-BF1-settle-reorder-product-ids',
        lens: 'BF1',
        severity: 'P0',
        title: 'product_ids reordenados no saco baixam o total',
        actor: 'buyer JWT',
        pre: '2 orders 18€ + 9€',
        repro: 'bag_lines com product_id da outra linha',
        expected: 'recusar mismatch ou cobrar 27€ + protecção',
        obtained: {'amt': amt, 'honest': honest, 'sid': swapped.checkoutSessionId},
      );
    }
  } else {
    c.block(
      'RTBF-BF1-settle-reorder-product-ids',
      'BF1',
      'product_ids trocados recusados',
      swapped.brief,
    );
  }
}

Future<void> bfTwoBagsShareOrder(Rtbf c) async {
  final a = await c.createProduct(title: '$prefix share-a', qty: 2, price: 14);
  final b = await c.createProduct(title: '$prefix share-b', qty: 2, price: 11);
  final d = await c.createProduct(title: '$prefix share-c', qty: 2, price: 7);
  if (a == null || b == null || d == null) return;
  final oa = await c.insertOrder(productId: a, jwt: c.buyerJwt, qty: 1, price: 14);
  final ob = await c.insertOrder(productId: b, jwt: c.buyerJwt, qty: 1, price: 11);
  final oc = await c.insertOrder(productId: d, jwt: c.buyerJwt, qty: 1, price: 7);
  if (oa == null || ob == null || oc == null) return;

  final jobs = await parallel([
    c.checkoutBag(
      lines: [
        {'order_id': oa, 'product_id': a},
        {'order_id': ob, 'product_id': b},
      ],
      amount: 1,
    ),
    c.checkoutBag(
      lines: [
        {'order_id': oa, 'product_id': a},
        {'order_id': oc, 'product_id': d},
      ],
      amount: 1,
    ),
  ]);
  final sids = jobs
      .map((h) => h.checkoutSessionId)
      .whereType<String>()
      .where((s) => s.startsWith('cs_'))
      .toSet();
  final amts = jobs.map((h) => h.serverAmount).toList();
  c.note('bf6.two-bags', '2 bags partilham order A em paralelo', {
    'oa': oa,
    'sids': sids.toList(),
    'amts': amts,
    'a': jobs[0].brief,
    'b': jobs[1].brief,
    'reused': jobs.map((h) => h.map?['reused_session']).toList(),
  }, lens: 'BF6');

  final ra = await c.orderRow(oa);
  final rb = await c.orderRow(ob);
  final rc = await c.orderRow(oc);
  final stored = {
    'A': ra?['stripe_checkout_session_id'],
    'B': rb?['stripe_checkout_session_id'],
    'C': rc?['stripe_checkout_session_id'],
  };

  if (sids.length >= 2) {
    c.hold(
      id: 'RTBF-BF2-two-bags-share-order-dual-session',
      lens: 'BF2',
      severity: 'P1',
      title: '2 sacos que partilham 1 order geram 2 Sessions abertas',
      actor: 'buyer JWT',
      pre: 'orders A,B,C; race bag(A,B) ∥ bag(A,C)',
      repro: 'Future.wait dois POST create-payment-intent bag_checkout',
      expected: '1 Session (expire a outra) ou recusar o 2.º saco',
      obtained: {
        'sids': sids.toList(),
        'amts': amts,
        'stored': stored,
        'briefs': [jobs[0].brief, jobs[1].brief],
      },
    );
  } else {
    c.block(
      'RTBF-BF2-two-bags-share-order-dual-session',
      'BF2',
      'race 2 bags: uma Session ou falha',
      {'sids': sids.toList(), 'stored': stored, 'n_ok': jobs.where((h) => h.ok).length},
    );
  }
}

Future<void> bfSessionReopenAfterExpire(Rtbf c) async {
  final p1 = await c.createProduct(title: '$prefix exp-1', qty: 2, price: 13);
  final p2 = await c.createProduct(title: '$prefix exp-2', qty: 2, price: 9);
  final p3 = await c.createProduct(title: '$prefix exp-3', qty: 2, price: 6);
  if (p1 == null || p2 == null || p3 == null) return;
  final o1 = await c.insertOrder(productId: p1, jwt: c.buyerJwt, qty: 1, price: 13);
  final o2 = await c.insertOrder(productId: p2, jwt: c.buyerJwt, qty: 1, price: 9);
  final o3 = await c.insertOrder(productId: p3, jwt: c.buyerJwt, qty: 1, price: 6);
  if (o1 == null || o2 == null || o3 == null) return;

  final first = await c.checkoutBag(
    lines: [
      {'order_id': o1, 'product_id': p1},
      {'order_id': o2, 'product_id': p2},
    ],
    amount: 1,
  );
  final sid1 = first.checkoutSessionId;
  final url1 = first.map?['checkoutUrl']?.toString();
  c.note('bf2.expire.s1', 'Session saco 1+2', first.brief, lens: 'BF2');

  final second = await c.checkoutBag(
    lines: [
      {'order_id': o1, 'product_id': p1},
      {'order_id': o3, 'product_id': p3},
    ],
    amount: 1,
  );
  final sid2 = second.checkoutSessionId;
  c.note('bf2.expire.s2', 'Session saco 1+3 (deve expirar S1)', second.brief, lens: 'BF2');

  var url1Alive = false;
  if (url1 != null && url1.startsWith('http')) {
    try {
      final hit = await c.req('GET', url1);
      url1Alive = hit.status >= 200 && hit.status < 400 && !hit.body.toLowerCase().contains('expired');
      c.note('bf2.expire.url1', 'GET checkoutUrl S1 após 2.º saco', {
        'status': hit.status,
        'alive': url1Alive,
        'snippet': clip(hit.body, 180),
      }, lens: 'BF2');
    } catch (e) {
      c.note('bf2.expire.url1.err', 'GET S1 falhou', '$e', lens: 'BF2');
    }
  }

  final reopen = await c.checkoutBag(
    lines: [
      {'order_id': o1, 'product_id': p1},
      {'order_id': o2, 'product_id': p2},
    ],
    amount: 1,
  );
  final sid3 = reopen.checkoutSessionId;
  c.note('bf2.expire.reopen', 'reabrir saco 1+2 após expire', {
    'sid1': sid1,
    'sid2': sid2,
    'sid3': sid3,
    'reused': reopen.map?['reused_session'],
    'brief': reopen.brief,
  }, lens: 'BF2');

  final distinct = {sid1, sid2, sid3}.whereType<String>().where((s) => s.startsWith('cs_')).toSet();
  if (url1Alive && sid2 != null && sid2 != sid1) {
    c.hold(
      id: 'RTBF-BF2-session-reopen-post-expire',
      lens: 'BF2',
      severity: 'P1',
      title: 'Checkout URL da Session expirada continua servível após 2.º saco',
      actor: 'buyer JWT',
      pre: 'S1 bag(A,B); S2 bag(A,C) dispara expire',
      repro: 'GET checkoutUrl de S1 depois do 2.º POST',
      expected: 'S1 expired; URL morta',
      obtained: {'sid1': sid1, 'sid2': sid2, 'url1Alive': url1Alive, 'sid3': sid3},
    );
  } else if (distinct.length >= 3) {
    c.hold(
      id: 'RTBF-BF2-session-reopen-new-cs',
      lens: 'BF2',
      severity: 'P2',
      title: 'Reabrir saco após expire cria 3.ª Session (S1 pode continuar paga?)',
      actor: 'buyer JWT',
      pre: 'S1 depois S2 expire depois reopen S1 bag',
      repro: '3 POST bag_checkout sequenciais',
      expected: 'S1 expirada; reopen reutiliza ou substitui sem 3 cs_ vivos',
      obtained: {'sids': distinct.toList(), 'url1Alive': url1Alive},
      proven: true,
    );
  } else {
    c.block(
      'RTBF-BF2-session-reopen-post-expire',
      'BF2',
      'expire+reopen: URL S1 morta e sem 3 cs_',
      {'sid1': sid1, 'sid2': sid2, 'sid3': sid3, 'url1Alive': url1Alive},
    );
  }
}

Future<void> bfHoldCheckoutSealedOffer(Rtbf c) async {
  final sku = await c.createProduct(title: '$prefix holdrace', qty: 1, price: 22);
  if (sku == null) return;
  final chat = await c.ensureChat(sku);
  final off = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': sku,
    'chat_id': chat,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': 7,
    'list_price': 22,
    'offered_by': 'buyer',
  });
  final offerId = off.firstId;
  if (offerId == null) return;
  c.createdOfferIds.add(offerId);
  await c.rest('PATCH', 'product_offers?id=eq.$offerId', jwt: c.sellerJwt, body: {
    'status': 'accepted',
  });

  final hold = await c.insertOrder(
    productId: sku,
    jwt: c.buyerJwt,
    qty: 1,
    price: 7,
    offerId: offerId,
  );
  if (hold == null) {
    c.block('RTBF-BF5-hold-offer', 'BF5', 'hold com oferta selada falhou', 'no row');
    return;
  }

  final b2order = await c.insertOrder(
    productId: sku,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    qty: 1,
    price: 22,
  );
  c.note('bf5.b2.hold', 'B2 tenta hold no mesmo SKU qty=1', {
    'b1': hold,
    'b2': b2order,
  }, lens: 'BF5');

  final jobs = await parallel([
    c.checkout(orderId: hold, amount: 1, productId: sku),
    if (b2order != null)
      c.checkout(
        orderId: b2order,
        amount: 1,
        productId: sku,
        jwt: c.buyer2Jwt,
        buyer: c.buyer2Id,
      )
    else
      Future.value(HttpHit(0, 'no-b2', null)),
  ]);

  final okSessions = jobs.where((h) => h.ok && (h.checkoutSessionId ?? '').startsWith('cs_')).toList();
  c.note('bf6.hold-checkout', 'hold oferta ∥ checkout B2', {
    'b1': jobs[0].brief,
    'b2': jobs.length > 1 ? jobs[1].brief : null,
    'ok_sessions': okSessions.length,
    'amts': okSessions.map((h) => h.serverAmount).toList(),
  }, lens: 'BF6');

  if (okSessions.length >= 2) {
    c.hold(
      id: 'RTBF-BF5-hold-checkout-sealed-offer-dual',
      lens: 'BF5',
      severity: 'P1',
      title: 'Hold com oferta selada e checkout B2 no mesmo SKU qty=1 geram 2 Sessions',
      actor: 'buyer + B2 JWT',
      pre: 'SKU stock=1; B1 hold oferta 7€; B2 hold catálogo',
      repro: 'Future.wait checkout B1 ∥ checkout B2',
      expected: 'só 1 Session (stock efectivo 0 para o outro)',
      obtained: {
        'n': okSessions.length,
        'sids': okSessions.map((h) => h.checkoutSessionId).toList(),
        'amts': okSessions.map((h) => h.serverAmount).toList(),
        'b2_order': b2order,
      },
    );
  } else {
    c.block(
      'RTBF-BF5-hold-checkout-sealed-offer-dual',
      'BF5',
      'só uma Session ou B2 recusado',
      {
        'b2_order': b2order,
        'n_ok': okSessions.length,
        'b1': jobs[0].brief,
        'b2': jobs.length > 1 ? jobs[1].brief : null,
      },
    );
  }
}

Future<void> bfSecondActor(Rtbf c) async {
  final sku = await c.createProduct(title: '$prefix xact', qty: 2, price: 16);
  if (sku == null) return;
  final oid = await c.insertOrder(productId: sku, jwt: c.buyerJwt, qty: 1, price: 16);
  if (oid == null) return;

  final b2pay = await c.checkout(
    orderId: oid,
    amount: 1,
    productId: sku,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  if (b2pay.ok) {
    c.hold(
      id: 'RTBF-BF7-b2-pays-b1-order',
      lens: 'BF7',
      severity: 'P0',
      title: 'B2 cria Session para order do B1',
      actor: 'buyer2 JWT',
      pre: 'order buyer=B1',
      repro: 'POST create-payment-intent buyer_id=B2 order_id=B1',
      expected: 'Invalid checkout user / order does not belong',
      obtained: b2pay.brief,
    );
  } else {
    c.block('RTBF-BF7-b2-pays-b1-order', 'BF7', 'B2 não paga order B1', b2pay.brief);
  }

  final anon = await c.checkout(orderId: oid, amount: 1, productId: sku, jwt: '');
  c.block('RTBF-BF7-anon', 'BF7', 'anon checkout', anon.brief);

  final steal = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyer2Jwt,
    body: {'buyer_id': c.buyer2Id},
  );
  if (steal.ok && steal.map?['buyer_id'] == c.buyer2Id) {
    c.hold(
      id: 'RTBF-BF7-steal-order',
      lens: 'BF7',
      severity: 'P0',
      title: 'B2 PATCH buyer_id da order alheia',
      actor: 'buyer2 JWT',
      pre: 'order B1',
      repro: 'PATCH orders.buyer_id=B2',
      expected: '0 linhas / RLS',
      obtained: steal.map,
    );
  } else {
    c.block('RTBF-BF7-steal-order', 'BF7', 'B2 não rouba buyer_id', steal.brief);
  }
}

Future<void> bfFsmPosCaptura(Rtbf c) async {
  final paid = await c.payToPago(lens: 'BF4', initialQty: 2);
  if (paid == null) {
    c.block('RTBF-BF4-fixture', 'BF4', 'setup_paid_order falhou', 'null');
    return;
  }
  final oid = paid.oid;
  final before = await c.books(oid);
  c.note('bf4.paid', 'compra Stripe TEST', {
    'oid': oid,
    'status': before['order']?['status'],
    'amount_paid_cents': before['order']?['amount_paid_cents'],
    'stock': before['product']?['quantity'],
    'pi': paid.pi,
  }, lens: 'BF4');

  final buyerCancel = await c.markCancel(oid);
  final afterCancel = await c.orderRow(oid);
  if (afterCancel?['status'] == 'cancelado') {
    c.hold(
      id: 'RTBF-BF4-buyer-cancel-pago',
      lens: 'BF4',
      severity: 'P0',
      title: 'Buyer cancela order já paga (Stripe)',
      actor: 'buyer JWT',
      pre: 'order pago Stripe TEST',
      repro: 'PATCH status=cancelado',
      expected: 'permanece pago',
      obtained: afterCancel,
    );
  } else {
    c.block('RTBF-BF4-buyer-cancel-pago', 'BF4', 'cancel pós-pago bloqueado', buyerCancel.brief);
  }

  final mb = await c.createProduct(title: '$prefix mbway', qty: 2, price: 9);
  if (mb == null) return;
  final mbOid = await c.insertOrder(
    productId: mb,
    jwt: c.buyerJwt,
    qty: 1,
    price: 9,
    payment: 'MB WAY',
  );
  if (mbOid == null) return;
  final sellerPago = await c.markPago(mbOid);
  final mbRow = await c.orderRow(mbOid);
  final prod = await c.productRow(mb);
  c.note('bf4.mbway', 'seller marca MB WAY pago', {
    'patch': sellerPago.brief,
    'order': mbRow,
    'product': prod,
  }, lens: 'BF4');
  if (mbRow?['status'] == 'pago' && mbRow?['proof_url'] == null) {
    c.note('bf4.mbway.pago-sem-prova', 'seller pago sem proof_url (fluxo off-platform)', mbRow, lens: 'BF4');
  }
}

Future<void> bfDetachOfferExact(Rtbf c) async {
  final sku = await c.createProduct(title: '$prefix detach', qty: 3, price: 30);
  if (sku == null) return;
  final chat = await c.ensureChat(sku);
  final off = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': sku,
    'chat_id': chat,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': 8,
    'list_price': 30,
    'offered_by': 'buyer',
  });
  final offerId = off.firstId;
  if (offerId == null) return;
  await c.rest('PATCH', 'product_offers?id=eq.$offerId', jwt: c.sellerJwt, body: {
    'status': 'accepted',
  });
  final oid = await c.insertOrder(
    productId: sku,
    jwt: c.buyerJwt,
    qty: 1,
    price: 8,
    offerId: offerId,
  );
  if (oid == null) return;
  final det = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'product_offer_id': null},
  );
  final row = await c.orderRow(oid);
  if (det.ok && row?['product_offer_id'] == null) {
    c.note(
      'bf3.detach',
      'ATBE exact: detach product_offer_id — NÃO CONTAR se igual',
      {'patch': det.brief, 'row': row},
      lens: 'BF3',
    );
  } else {
    c.block('RTBF-BF3-detach-offer', 'BF3', 'product_offer_id imutável (ATBE exact blocked)', det.brief);
  }
}

Future<void> bfLegitCaixa(Rtbf c) async {
  final w0 = await c.wallets();
  final legit = await c.payToPago(lens: 'BF8', initialQty: 3);
  if (legit == null) {
    c.block('RTBF-BF8-legit', 'BF8', 'setup_paid_order falhou', 'null');
    return;
  }
  final books = await c.books(legit.oid);
  c.note('bf8.legit', 'compra marketplace Stripe TEST', {
    'oid': legit.oid,
    'pid': legit.pid,
    'pi': legit.pi,
    'w0': w0,
    'status': books['order']?['status'],
    'amount_paid_cents': books['order']?['amount_paid_cents'],
    'stock_units_applied': books['order']?['stock_units_applied'],
    'product_qty': books['product']?['quantity'],
    'seller_venda': books['seller_venda'],
  }, lens: 'BF8');

  final bag = await c.e2e('setup_paid_bag', {});
  c.note('bf8.bag', 'setup_paid_bag Stripe TEST', bag.brief, lens: 'BF8');

  final wInsert = await c.rest('POST', 'wallet_transactions', jwt: c.buyerJwt, body: {
    'wallet_id': c.buyerId,
    'amount': 50,
    'type': 'venda',
    'description': '$prefix hostile',
  });
  if (wInsert.ok) {
    c.hold(
      id: 'RTBF-BF8-jwt-wallet-insert',
      lens: 'BF8',
      severity: 'P0',
      title: 'Buyer JWT INSERT wallet_transactions',
      actor: 'buyer JWT',
      pre: 'carteira B1',
      repro: 'POST wallet_transactions amount=50 type=venda',
      expected: 'RLS deny',
      obtained: wInsert.brief,
    );
  } else {
    c.block('RTBF-BF8-jwt-wallet-insert', 'BF8', 'JWT não cria fundo', wInsert.brief);
  }
}
