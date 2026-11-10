/// REDTEAM_BLIND_AT pass1 — variantes NOVAS pós-ANAS marketplace. Staging. Não corrigir.
import 'dart:io';
import '_rtat.dart';

Future<void> main() async {
  final c = Rtat.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.wallets();
  c.note('actors', 'JWT B1/S1/B2/S2', {
    'b1': c.buyerId,
    's1': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
    'wallets0': w0,
  });

  await _enableTier(c);
  await _at1Price(c);
  await _at3Bundle(c);
  await _at2SessionBag(c);
  await _at5Stock(c);
  await _at6Race(c);
  await _at4Captured(c);
  await _at7SecondActor(c);
  await _at8Caixa(c, w0);

  await c.dumpAll('pass1.json');
  stdout.writeln(
      'DONE findings=${c.findings.length} blocked=${c.blocked.length} lenses=${c.lensesHit.toList()..sort()}');
}

Future<void> _enableTier(Rtat c) async {
  final up = await c.rest(
    'POST',
    'seller_bundle_discounts',
    jwt: c.sellerJwt,
    body: {
      'seller_id': c.sellerId,
      'enabled': true,
      'tier_2_pct': 10,
      'tier_3_pct': 20,
      'tier_5_pct': 30,
      'custom_tiers': [
        {'min_items': 4, 'pct': 25}
      ],
    },
    prefer: 'return=representation,resolution=merge-duplicates',
  );
  if (!up.ok) {
    final patch = await c.rest(
      'PATCH',
      'seller_bundle_discounts?seller_id=eq.${c.sellerId}',
      jwt: c.sellerJwt,
      body: {
        'enabled': true,
        'tier_2_pct': 10,
        'tier_3_pct': 20,
        'tier_5_pct': 30,
        'custom_tiers': [
          {'min_items': 4, 'pct': 25}
        ],
      },
    );
    c.note('tier.upsert', 'seller_bundle_discounts', '${up.brief} / ${patch.brief}',
        lens: 'AT3');
  } else {
    c.note('tier.upsert', 'seller_bundle_discounts', up.brief, lens: 'AT3');
  }

  final before = await c.rest(
    'GET',
    'seller_bundle_discounts?seller_id=eq.${c.sellerId}&select=seller_id,enabled,tier_2_pct,tier_3_pct,tier_5_pct,custom_tiers',
    service: true,
  );
  final buyerWrite = await c.rest(
    'PATCH',
    'seller_bundle_discounts?seller_id=eq.${c.sellerId}',
    jwt: c.buyerJwt,
    body: {
      'tier_2_pct': 50,
      'custom_tiers': [
        {'min_items': 2, 'pct': 50}
      ],
    },
  );
  final after = await c.rest(
    'GET',
    'seller_bundle_discounts?seller_id=eq.${c.sellerId}&select=seller_id,enabled,tier_2_pct,tier_3_pct,tier_5_pct,custom_tiers',
    service: true,
  );
  final t2b = numOf(before.map?['tier_2_pct']);
  final t2a = numOf(after.map?['tier_2_pct']);
  final mutated = t2a != null && t2a != t2b;
  if (mutated) {
    c.hold(
      id: 'AT3-01',
      lens: 'AT3',
      severity: 'P1',
      title: 'Buyer PATCH seller_bundle_discounts do vendedor (mutação real)',
      actor: 'buyer JWT',
      pre: 'row seller_id = S1 tier_2=$t2b',
      repro: 'PATCH seller_bundle_discounts?seller_id=eq.S1 tier_2_pct=50',
      expected: '0 rows / RLS write own',
      obtained: 'http=${buyerWrite.status} tier_2 $t2b → $t2a custom=${after.map?['custom_tiers']}',
      evidence: {'before': before.map, 'after': after.map, 'patch': buyerWrite.brief},
    );
  } else {
    c.block(
      'AT3-01',
      'AT3',
      'Buyer PATCH discounts sem mutação (HTTP ${buyerWrite.status} 0-row)',
      'before=$t2b after=$t2a body=${buyerWrite.brief}',
    );
  }
}

Future<void> _at1Price(Rtat c) async {
  final pid = await c.insertProduct(price: 12.0, qty: 8, title: '$prefix-AT1');
  if (pid == null) {
    c.skip('AT1.prod', 'AT1', 'fixture produto', 'null');
    return;
  }

  final cheap = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pid,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
    'contract_unit_cents': 1,
    'price_total': 0.01,
  });
  if (cheap.firstId != null) c.createdOrderIds.add(cheap.firstId!);
  final cheapRow = cheap.firstId != null ? await c.orderRow(cheap.firstId!) : null;
  final sealed = numOf(cheapRow?['contract_unit_cents']);
  if (cheap.ok && sealed != null && sealed < 1200) {
    c.hold(
      id: 'AT1-01',
      lens: 'AT1',
      severity: 'P0',
      title: 'INSERT JWT sela contract_unit_cents abaixo do catálogo',
      actor: 'buyer JWT',
      pre: 'produto 12.00 €',
      repro: 'POST /orders contract_unit_cents=1',
      expected: 'selo ≥ 1200 ou 4xx',
      obtained: 'http=${cheap.status} sealed=$sealed row=$cheapRow',
      evidence: {'row': cheapRow},
    );
  } else {
    c.block('AT1-01', 'AT1', 'INSERT contract_unit_cents=1',
        'http=${cheap.status} sealed=$sealed');
  }

  if (cheap.firstId != null) {
    final patch = await c.rest(
      'PATCH',
      'orders?id=eq.${cheap.firstId}',
      jwt: c.buyerJwt,
      body: {'contract_unit_cents': 1, 'price_total': 0.01},
    );
    final after = await c.orderRow(cheap.firstId!);
    final afterSealed = numOf(after?['contract_unit_cents']);
    if (patch.ok && afterSealed != null && afterSealed < 1200) {
      c.hold(
        id: 'AT1-02',
        lens: 'AT1',
        severity: 'P0',
        title: 'PATCH JWT reduz contract_unit_cents',
        actor: 'buyer JWT',
        pre: 'order existente',
        repro: 'PATCH /orders contract_unit_cents=1',
        expected: '403 immutable',
        obtained: 'http=${patch.status} sealed=$afterSealed',
      );
    } else {
      c.block('AT1-02', 'AT1', 'PATCH contract_unit_cents', patch);
    }
  }

  // Oferta negociada + detach product_offer_id (variante NOVA vs AN-P3-02)
  final pA = await c.insertProduct(price: 20.0, qty: 4, title: '$prefix-offerA');
  final pB = await c.insertProduct(price: 20.0, qty: 4, title: '$prefix-offerB');
  if (pA == null || pB == null) {
    c.skip('AT1.offer', 'AT1', 'produtos oferta', 'null');
    return;
  }

  Future<String?> makeAcceptedOffer(String productId) async {
    final ins = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
      'product_id': productId,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'amount': 10.0,
      'list_price': 20.0,
      'offered_by': 'buyer',
      'status': 'pending',
    });
    final oid = ins.firstId;
    if (oid != null) c.createdOfferIds.add(oid);
    if (!ins.ok || oid == null) {
      c.note('offer.ins', 'POST product_offers', ins.brief, lens: 'AT1');
      return null;
    }
    final acc = await c.rest(
      'PATCH',
      'product_offers?id=eq.$oid',
      jwt: c.sellerJwt,
      body: {'status': 'accepted', 'responded_at': DateTime.now().toUtc().toIso8601String()},
    );
    if (!acc.ok) {
      c.note('offer.acc', 'seller accept', acc.brief, lens: 'AT1');
      return null;
    }
    return oid;
  }

  final offA = await makeAcceptedOffer(pA);
  final offB = await makeAcceptedOffer(pB);
  if (offA == null || offB == null) {
    c.skip('AT1.offer.acc', 'AT3', 'seller accept oferta', 'null');
    return;
  }

  final oA = await c.insertOrder(
      productId: pA, offerId: offA, priceTotal: 10, jwt: c.buyerJwt);
  final oB = await c.insertOrder(
      productId: pB, offerId: offB, priceTotal: 10, jwt: c.buyerJwt);
  if (oA == null || oB == null) {
    c.skip('AT1.offer.ord', 'AT3', 'orders com oferta', 'null');
    return;
  }
  final rowA = await c.orderRow(oA);
  final rowB = await c.orderRow(oB);
  c.note('AT1.offer.seal', 'contrato após oferta', {
    'A': rowA?['contract_unit_cents'],
    'B': rowB?['contract_unit_cents'],
    'offerA': rowA?['product_offer_id'],
    'offerB': rowB?['product_offer_id'],
  }, lens: 'AT1');

  // qty>1 com oferta (variante NOVA)
  final qtyOffer = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pA,
    'quantity': 2,
    'product_offer_id': offA,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  if (qtyOffer.firstId != null) c.createdOrderIds.add(qtyOffer.firstId!);
  await c.expectDenied(
    id: 'AT1-03',
    lens: 'AT1',
    title: 'Order qty=2 com product_offer_id aceite',
    hit: qtyOffer,
    actor: 'buyer JWT',
    pre: 'oferta aceite amount=10',
    repro: 'POST /orders quantity=2 product_offer_id',
    severityIfOpen: 'P1',
  );

  // Checkout COM offer_id (tier NÃO deve aplicar — 2×10€)
  final withOffer = await c.bagCpi([
    {'order_id': oA, 'product_id': pA, 'seller_id': c.sellerId, 'quantity': 1},
    {'order_id': oB, 'product_id': pB, 'seller_id': c.sellerId, 'quantity': 1},
  ]);
  final wantOfferNoTier = expectedBagTotal(2000);
  final wantOfferPlusTier = expectedBagTotal(1800);
  final gotOffer = withOffer.serverAmount;
  c.note('AT3.bag.offer', 'saco com ofertas seladas', {
    'http': withOffer.status,
    'amt': gotOffer,
    'wantNoTier': wantOfferNoTier,
    'wantPlusTier': wantOfferPlusTier,
    'err': withOffer.err,
  }, lens: 'AT3');
  if (withOffer.ok && gotOffer != null && gotOffer <= wantOfferPlusTier + 2) {
    c.hold(
      id: 'AT3-02',
      lens: 'AT3',
      severity: 'P1',
      title: 'Saco com product_offer_id aplica tier por cima do preço negociado',
      actor: 'buyer JWT',
      pre: '2 ofertas aceite 10€; tier_2=10%',
      repro: 'POST create-payment-intent bag_checkout 2 orders com offer_id',
      expected: 'items 2000¢ + protecção (sem tier) ≈ $wantOfferNoTier',
      obtained: 'server_amount_cents=$gotOffer (tier stack ≈ $wantOfferPlusTier)',
      evidence: {'body': withOffer.brief},
    );
  } else if (withOffer.ok) {
    c.block('AT3-02', 'AT3', 'saco oferta sem tier extra',
        'amt=$gotOffer want=$wantOfferNoTier');
  } else {
    c.block('AT3-02', 'AT3', 'saco oferta checkout bloqueado', withOffer);
  }

  // Detach offer_id (variante NOVA) — contrato barato deve ficar; tier NÃO deve empilhar
  final detachA = await c.rest(
    'PATCH',
    'orders?id=eq.$oA',
    jwt: c.buyerJwt,
    body: {'product_offer_id': null},
  );
  final detachB = await c.rest(
    'PATCH',
    'orders?id=eq.$oB',
    jwt: c.buyerJwt,
    body: {'product_offer_id': null},
  );
  final afterDetachA = await c.orderRow(oA);
  final afterDetachB = await c.orderRow(oB);
  c.note('AT3.detach', 'PATCH product_offer_id null', {
    'httpA': detachA.status,
    'httpB': detachB.status,
    'offerA': afterDetachA?['product_offer_id'],
    'offerB': afterDetachB?['product_offer_id'],
    'centsA': afterDetachA?['contract_unit_cents'],
    'centsB': afterDetachB?['contract_unit_cents'],
  }, lens: 'AT3');

  final offerCleared = afterDetachA?['product_offer_id'] == null &&
      afterDetachB?['product_offer_id'] == null;
  final stillCheap = (numOf(afterDetachA?['contract_unit_cents']) ?? 0) <= 1000 &&
      (numOf(afterDetachB?['contract_unit_cents']) ?? 0) <= 1000;

  if (detachA.ok && offerCleared && stillCheap) {
    final afterBag = await c.bagCpi([
      {'order_id': oA, 'product_id': pA, 'seller_id': c.sellerId},
      {'order_id': oB, 'product_id': pB, 'seller_id': c.sellerId},
    ]);
    final got = afterBag.serverAmount;
    c.note('AT3.detach.cpi', 'checkout após detach', {
      'http': afterBag.status,
      'amt': got,
      'wantStack': wantOfferPlusTier,
      'wantOffer': wantOfferNoTier,
    }, lens: 'AT3');
    if (afterBag.ok && got != null && got <= wantOfferPlusTier + 2) {
      c.hold(
        id: 'AT3-03',
        lens: 'AT3',
        severity: 'P1',
        title:
            'Detach product_offer_id mantém contrato de oferta e reaplica tier do saco',
        actor: 'buyer JWT',
        pre: 'orders seladas a 10€ com oferta; PATCH offer_id=null',
        repro:
            'PATCH orders product_offer_id=null; bag checkout 2 linhas; comparar server_amount_cents',
        expected:
            'offer_id imutável OU checkout sem tier sobre preço de oferta (≈ $wantOfferNoTier) OU regressão a catálogo',
        obtained: 'server_amount_cents=$got (stack oferta+tier ≈ $wantOfferPlusTier)',
        evidence: {
          'detach': detachA.brief,
          'cpi': afterBag.brief,
          'rowA': afterDetachA,
          'rowB': afterDetachB,
        },
      );
    } else {
      c.block('AT3-03', 'AT3', 'detach não empilha tier barato',
          'amt=$got http=${afterBag.status}');
    }
  } else if (detachA.ok && offerCleared && !stillCheap) {
    c.block('AT3-03', 'AT3', 'detach limpou oferta mas contrato voltou ao catálogo',
        afterDetachA);
  } else {
    c.block('AT3-03', 'AT3', 'PATCH product_offer_id negado ou não limpou',
        '${detachA.brief} / ${detachB.brief}');
  }

  // Body amount hostil no single
  if (cheap.firstId != null) {
    final bodyAmt = await c.singleCpi(cheap.firstId!, extra: {
      'amount': 50,
      'item_price': 0.5,
      'currency': 'usd',
    });
    final amt = bodyAmt.serverAmount;
    if (bodyAmt.ok && amt != null && amt < 1000) {
      c.hold(
        id: 'AT1-04',
        lens: 'AT1',
        severity: 'P1',
        title: 'CPI aceita amount/currency do body abaixo do contrato',
        actor: 'buyer JWT',
        pre: 'order catálogo 12€',
        repro: 'POST create-payment-intent amount=50 currency=usd',
        expected: 'quote ≥ catálogo EUR ou 4xx',
        obtained: 'http=${bodyAmt.status} amt=$amt reused=${bodyAmt.reused}',
      );
    } else {
      c.block('AT1-04', 'AT1', 'body amount/currency ignorado ou bloqueado',
          'http=${bodyAmt.status} amt=$amt ${clip(bodyAmt.err, 120)}');
    }
  }
}

Future<void> _at3Bundle(Rtat c) async {
  final p1 = await c.insertProduct(price: 8.0, qty: 4, title: '$prefix-bun1');
  final p2 = await c.insertProduct(price: 8.0, qty: 4, title: '$prefix-bun2');
  if (p1 == null || p2 == null) {
    c.skip('AT3.bun.prod', 'AT3', 'produtos bundle', 'null');
    return;
  }

  final hostileIns = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_ids': [p1, p2],
    'status': 'accepted',
    'total_eur': 0.50,
    'discount_pct': 50,
    'subtotal_eur': 16,
    'discount_eur': 15.5,
  });
  if (hostileIns.firstId != null) c.createdBundleIds.add(hostileIns.firstId!);
  await c.expectDenied(
    id: 'AT3-04',
    lens: 'AT3',
    title: 'INSERT bundle status=accepted total forjado (regressão ANAS)',
    hit: hostileIns,
    actor: 'buyer JWT',
    pre: '2 produtos 8€',
    repro: 'POST product_bundles status=accepted total_eur=0.50',
    severityIfOpen: 'P1',
  );

  final pending = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_ids': [p1, p2],
    'status': 'pending',
    'discount_pct': 40,
  });
  final bid = pending.firstId;
  if (bid != null) c.createdBundleIds.add(bid);
  if (!pending.ok || bid == null) {
    c.skip('AT3.bun.pending', 'AT3', 'INSERT pending bundle', pending.brief);
    return;
  }
  final pendingRow = pending.map;
  c.note('AT3.bun.ins', 'pending rewrite', {
    'status': pendingRow?['status'],
    'total': pendingRow?['total_eur'],
    'pct': pendingRow?['discount_pct'],
  }, lens: 'AT3');
  final buyerPct = numOf(pendingRow?['discount_pct']) ?? -1;
  if (buyerPct > 0) {
    c.hold(
      id: 'AT3-05',
      lens: 'AT3',
      severity: 'P2',
      title: 'Buyer INSERT bundle com discount_pct persistido',
      actor: 'buyer JWT',
      pre: 'INSERT pending discount_pct=40',
      repro: 'POST product_bundles discount_pct=40',
      expected: 'discount_pct=0 (só seller)',
      obtained: 'pct=$buyerPct total=${pendingRow?['total_eur']}',
    );
  } else {
    c.block('AT3-05', 'AT3', 'buyer discount_pct forçado a 0', pendingRow);
  }

  final buyerAccept = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.buyerJwt,
    body: {'status': 'accepted', 'total_eur': 0.50, 'discount_pct': 50},
  );
  await c.expectDenied(
    id: 'AT3-06',
    lens: 'AT3',
    title: 'Buyer PATCH bundle → accepted + total forjado',
    hit: buyerAccept,
    actor: 'buyer JWT',
    pre: 'bundle pending do próprio buyer',
    repro: 'PATCH product_bundles status=accepted total_eur=0.50',
    severityIfOpen: 'P1',
  );

  final sellerTotal = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.sellerJwt,
    body: {'total_eur': 0.50},
  );
  final afterTotal = await c.rest(
    'GET',
    'product_bundles?id=eq.$bid&select=id,status,total_eur,discount_pct,subtotal_eur',
    service: true,
  );
  final tot = numOf(afterTotal.map?['total_eur']);
  c.note('AT3.seller.total', 'seller PATCH total_eur=0.50', {
    'http': sellerTotal.status,
    'total': tot,
    'row': afterTotal.map,
  }, lens: 'AT3');
  if (sellerTotal.ok && tot != null && tot < 1) {
    c.hold(
      id: 'AT3-07',
      lens: 'AT3',
      severity: 'P1',
      title: 'Seller PATCH total_eur ignora recálculo de catálogo',
      actor: 'seller JWT',
      pre: 'bundle pending subtotal 16€',
      repro: 'PATCH product_bundles total_eur=0.50',
      expected: 'total recalculado a partir de discount_pct (não 0.50)',
      obtained: 'total=$tot',
    );
  } else {
    c.block('AT3-07', 'AT3', 'seller total_eur recalculado ou negado',
        'http=${sellerTotal.status} total=$tot');
  }

  final sellerDisc = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.sellerJwt,
    body: {'discount_pct': 50, 'status': 'accepted'},
  );
  final accRow = await c.rest(
    'GET',
    'product_bundles?id=eq.$bid&select=id,status,total_eur,discount_pct',
    service: true,
  );
  c.note('AT3.seller.accept', 'seller accept+50%', {
    'http': sellerDisc.status,
    'row': accRow.map,
  }, lens: 'AT3');

  final postAcceptPatch = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.sellerJwt,
    body: {'discount_pct': 10, 'total_eur': 1.00},
  );
  final frozen = await c.rest(
    'GET',
    'product_bundles?id=eq.$bid&select=id,status,total_eur,discount_pct',
    service: true,
  );
  final frozenPct = numOf(frozen.map?['discount_pct']);
  final accPct = numOf(accRow.map?['discount_pct']);
  if (postAcceptPatch.ok &&
      frozen.map?['status']?.toString().toLowerCase() == 'accepted' &&
      frozenPct != null &&
      accPct != null &&
      frozenPct != accPct) {
    c.hold(
      id: 'AT3-08',
      lens: 'AT3',
      severity: 'P2',
      title: 'Seller PATCH discount após accepted altera contrato',
      actor: 'seller JWT',
      pre: 'bundle already accepted',
      repro: 'PATCH product_bundles discount_pct=10 após accepted',
      expected: 'valores congelados',
      obtained: 'before=$accPct after=$frozenPct ${frozen.map}',
    );
  } else {
    c.block('AT3-08', 'AT3', 'accepted freeze discount/total',
        'http=${postAcceptPatch.status} frozen=${frozen.map}');
  }

  // 2 bundle_id no mesmo saco
  final pending2 = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_ids': [p1],
    'status': 'pending',
  });
  if (pending2.firstId != null) c.createdBundleIds.add(pending2.firstId!);
  final o1 = await c.insertOrder(productId: p1, bundleId: bid);
  final o2 = await c.insertOrder(
      productId: p2, bundleId: pending2.firstId ?? bid);
  if (o1 != null && o2 != null) {
    final mix = await c.bagCpi([
      {'order_id': o1, 'product_id': p1},
      {'order_id': o2, 'product_id': p2},
    ]);
    if (mix.ok) {
      c.hold(
        id: 'AT3-09',
        lens: 'AT3',
        title: 'Saco mistura 2 bundle_id distintos',
        severity: 'P1',
        actor: 'buyer JWT',
        pre: 'orders com bundle_id diferentes',
        repro: 'bag checkout 2 linhas / 2 bundle_id',
        expected: 'Checkout blocked: bag cannot mix multiple bundle contracts',
        obtained: mix.brief,
      );
    } else {
      c.block('AT3-09', 'AT3', 'mix 2 bundle_id bloqueado', mix);
    }
  }
}

Future<void> _at2SessionBag(Rtat c) async {
  final products = <String>[];
  final orders = <String>[];
  for (var i = 0; i < 16; i++) {
    final p = await c.insertProduct(
      price: 1.2,
      qty: 2,
      title: '$prefix-bag$i',
    );
    if (p == null) break;
    products.add(p);
    final o = await c.insertOrder(productId: p, priceTotal: 1.2);
    if (o == null) break;
    orders.add(o);
  }
  c.note('AT2.n', 'produtos/orders saco', {
    'products': products.length,
    'orders': orders.length,
  }, lens: 'AT2');

  if (orders.length >= 2) {
    final lines2 = [
      for (var i = 0; i < 2; i++)
        {'order_id': orders[i], 'product_id': products[i], 'seller_id': c.sellerId},
    ];
    final first = await c.bagCpi(lines2);
    c.note('AT2.cpi1', 'primeiro saco 2 linhas', {
      'http': first.status,
      'sid': first.checkoutSessionId,
      'amt': first.serverAmount,
      'reused': first.reused,
      'url': first.checkoutUrl != null,
    }, lens: 'AT2');

    final second = await c.bagCpi(lines2);
    c.note('AT2.cpi2', 'segundo saco mesmas linhas', {
      'http': second.status,
      'sid': second.checkoutSessionId,
      'amt': second.serverAmount,
      'reused': second.reused,
    }, lens: 'AT2');

    final row0 = await c.orderRow(orders[0]);
    final row1 = await c.orderRow(orders[1]);
    final sid1 = first.checkoutSessionId;
    final sid2 = second.checkoutSessionId;
    final alive1 = await c.checkoutAlive(first.checkoutUrl);
    c.note('AT2.alive', '1.ª Session após 2.º POST', {
      'alive': alive1,
      'sid1': sid1,
      'sid2': sid2,
      'row0': row0?['stripe_checkout_session_id'],
      'row1': row1?['stripe_checkout_session_id'],
    }, lens: 'AT2');

    final twoOpen = sid1 != null &&
        sid2 != null &&
        sid1 != sid2 &&
        !second.reused &&
        (alive1 ?? '').startsWith('alive');
    if (twoOpen) {
      c.hold(
        id: 'AT2-01',
        lens: 'AT2',
        severity: 'P1',
        title:
            'Compact UUID: 2.º checkout do saco cria 2.ª Session com a 1.ª ainda viva',
        actor: 'buyer JWT',
        pre: 'saco 2 orders; metadata bag_order_ids compacta (sem hífens)',
        repro:
            'POST create-payment-intent bag 2×; repetir; GET checkoutUrl da 1.ª',
        expected: 'reuse da mesma cs_ ou expire da 1.ª antes da 2.ª',
        obtained:
            'sid1=$sid1 sid2=$sid2 reused=${second.reused} alive1=$alive1',
        evidence: {
          'row0_sid': row0?['stripe_checkout_session_id'],
          'row1_sid': row1?['stripe_checkout_session_id'],
        },
      );
    } else if (sid1 != null && sid2 != null && sid1 != sid2 && !second.reused) {
      c.hold(
        id: 'AT2-01b',
        lens: 'AT2',
        severity: 'P3',
        title:
            'Compact UUID: reuse do saco nunca acerta (metadata sem hífens ≠ ids com hífens); expire ainda mata a 1.ª',
        actor: 'buyer JWT',
        pre: 'saco 2 orders; 2.º POST',
        repro: '2× bag_checkout; comparar cs_ e GET checkoutUrl',
        expected: 'reused_session=true mesma cs_',
        obtained:
            'sid1≠sid2 reused=false alive1=$alive1 (expire OK, reuse quebrado)',
        proven: true,
        evidence: {
          'sid1': sid1,
          'sid2': sid2,
          'alive1': alive1,
        },
      );
    } else {
      c.block('AT2-01', 'AT2', 'saco 2.º POST reuse/expire',
          'sid1=$sid1 sid2=$sid2 reused=${second.reused} alive=$alive1');
    }

    // product_id drift nas bag_lines
    final drift = await c.bagCpi([
      {'order_id': orders[0], 'product_id': products[1], 'seller_id': c.sellerId},
      {'order_id': orders[1], 'product_id': products[0], 'seller_id': c.sellerId},
    ]);
    if (drift.ok) {
      c.hold(
        id: 'AT2-02',
        lens: 'AT2',
        severity: 'P2',
        title: 'bag_lines product_id trocado entre orders aceite no quote',
        actor: 'buyer JWT',
        pre: 'order0→prod0, order1→prod1; body inverte product_id',
        repro: 'bag_checkout lines com product_id cruzado',
        expected: 'Checkout blocked: bag product does not match order',
        obtained: drift.brief,
      );
    } else {
      c.block('AT2-02', 'AT2', 'product_id drift bloqueado', drift);
    }

    // legacy bag_orders_json no body (settle path ainda parseia metadata; body não deve ir parar ao Stripe)
    final legacy = await c.bagCpi(lines2, extra: {
      'bag_orders_json':
          '[{"order_id":"${orders[0]}","line_total_cents":1}]',
    });
    c.note('AT2.legacy', 'body bag_orders_json extra', {
      'http': legacy.status,
      'amt': legacy.serverAmount,
      'sid': legacy.checkoutSessionId,
    }, lens: 'AT2');
    if (legacy.ok &&
        legacy.serverAmount != null &&
        first.serverAmount != null &&
        legacy.serverAmount! + 2 < first.serverAmount!) {
      c.hold(
        id: 'AT2-03',
        lens: 'AT2',
        severity: 'P1',
        title: 'body bag_orders_json altera o total da Session',
        actor: 'buyer JWT',
        pre: 'mesmo saco 2 linhas',
        repro: 'CPI bag + extra bag_orders_json line_total_cents=1',
        expected: 'campo ignorado; mesmo server_amount',
        obtained: 'legacy=${legacy.serverAmount} base=${first.serverAmount}',
      );
    } else {
      c.block('AT2-03', 'AT2', 'bag_orders_json no body ignorado',
          'legacy=${legacy.serverAmount} base=${first.serverAmount}');
    }
  }

  if (orders.length >= 15) {
    final lines15 = [
      for (var i = 0; i < 15; i++)
        {'order_id': orders[i], 'product_id': products[i]},
    ];
    final cpi15 = await c.bagCpi(lines15);
    c.note('AT2.15', 'saco 15 UUIDs compactos (~494 chars)', {
      'http': cpi15.status,
      'amt': cpi15.serverAmount,
      'err': cpi15.err,
    }, lens: 'AT2');
    if (cpi15.ok) {
      c.block('AT2-04', 'AT2', 'saco 15 linhas cabe em metadata compacta',
          'amt=${cpi15.serverAmount}');
    } else {
      c.note('AT2.15.block', '15 linhas recusado', cpi15.brief, lens: 'AT2');
    }
  }
  if (orders.length >= 16) {
    final lines16 = [
      for (var i = 0; i < 16; i++)
        {'order_id': orders[i], 'product_id': products[i]},
    ];
    final cpi16 = await c.bagCpi(lines16);
    if (cpi16.ok) {
      c.hold(
        id: 'AT2-05',
        lens: 'AT2',
        severity: 'P2',
        title: 'Saco 16 linhas cria Session apesar do tecto 500 chars',
        actor: 'buyer JWT',
        pre: '16 UUIDs compactos = 527 chars',
        repro: 'bag_checkout 16 order_id',
        expected: 'Checkout blocked: bag too large for payment metadata',
        obtained: cpi16.brief,
      );
    } else {
      c.block('AT2-05', 'AT2', 'saco 16 linhas bloqueado (500 chars)', cpi16);
    }
  } else {
    c.skip('AT2-05', 'AT2', 'menos de 16 orders criadas', orders.length);
  }
}

Future<void> _at5Stock(Rtat c) async {
  final pid = await c.insertProduct(price: 5.0, qty: 1, title: '$prefix-stk1');
  if (pid == null) {
    c.skip('AT5.prod', 'AT5', 'produto stock=1', 'null');
    return;
  }
  final o1 = await c.insertOrder(productId: pid, qty: 1);
  final o2 = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pid,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  if (o2.firstId != null) c.createdOrderIds.add(o2.firstId!);
  if (o1 != null && o2.ok) {
    c.hold(
      id: 'AT5-01',
      lens: 'AT5',
      severity: 'P1',
      title: 'Duas orders hold em stock=1 do mesmo buyer',
      actor: 'buyer JWT',
      pre: 'produto quantity=1',
      repro: 'POST /orders ×2 quantity=1',
      expected: '2.ª INSERT order_hold_exceeds_stock',
      obtained: 'o1=$o1 o2=${o2.firstId} ${o2.brief}',
    );
  } else {
    c.block('AT5-01', 'AT5', '2.ª hold stock=1 bloqueada', o2);
  }

  if (c.buyer2Jwt != null && c.buyer2Id != null) {
    final oB2 = await c.rest('POST', 'orders', jwt: c.buyer2Jwt, body: {
      'buyer_id': c.buyer2Id,
      'seller_id': c.sellerId,
      'product_id': pid,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    if (oB2.firstId != null) c.createdOrderIds.add(oB2.firstId!);
    await c.expectDenied(
      id: 'AT5-02',
      lens: 'AT5',
      title: 'B2 hold no mesmo stock=1 já segurado por B1',
      hit: oB2,
      actor: 'buyer2 JWT',
      pre: 'B1 já tem order hold qty=1',
      repro: 'POST /orders buyer2 product stock=1',
      severityIfOpen: 'P1',
    );
  }

  final inflate = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pid,
    'quantity': 9,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  if (inflate.firstId != null) c.createdOrderIds.add(inflate.firstId!);
  await c.expectDenied(
    id: 'AT5-03',
    lens: 'AT5',
    title: 'INSERT qty=9 em stock=1',
    hit: inflate,
    actor: 'buyer JWT',
    pre: 'produto quantity=1',
    repro: 'POST /orders quantity=9',
    severityIfOpen: 'P1',
  );
}

Future<void> _at6Race(Rtat c) async {
  final p = await c.insertProduct(price: 6.0, qty: 2, title: '$prefix-race');
  if (p == null) {
    c.skip('AT6.prod', 'AT6', 'produto race', 'null');
    return;
  }
  final o = await c.insertOrder(productId: p);
  if (o == null) {
    c.skip('AT6.ord', 'AT6', 'order race', 'null');
    return;
  }
  final r = await Future.wait([
    c.singleCpi(o),
    c.singleCpi(o),
  ]);
  final sids = r.map((h) => h.checkoutSessionId).whereType<String>().toSet();
  c.note('AT6.parallel', 'Future.wait 2× CPI same order', {
    'http': r.map((h) => h.status).toList(),
    'sids': sids.toList(),
    'reused': r.map((h) => h.reused).toList(),
    'amts': r.map((h) => h.serverAmount).toList(),
  }, lens: 'AT6');
  if (sids.length > 1) {
    c.hold(
      id: 'AT6-01',
      lens: 'AT6',
      severity: 'P1',
      title: 'Corrida: 2 Checkout Sessions na mesma order',
      actor: 'buyer JWT',
      pre: '1 order pending',
      repro: 'Future.wait 2× create-payment-intent order_id',
      expected: '1 cs_ (claim/reuse)',
      obtained: 'sids=$sids',
    );
  } else {
    c.block('AT6-01', 'AT6', 'corrida single → 1 Session', sids.toList());
  }

  final pBag = await c.insertProduct(price: 4.0, qty: 3, title: '$prefix-raceb');
  final pBag2 = await c.insertProduct(price: 4.0, qty: 3, title: '$prefix-raceb2');
  final ob1 = pBag == null ? null : await c.insertOrder(productId: pBag);
  final ob2 = pBag2 == null ? null : await c.insertOrder(productId: pBag2);
  if (ob1 != null && ob2 != null) {
    final lines = [
      {'order_id': ob1, 'product_id': pBag},
      {'order_id': ob2, 'product_id': pBag2},
    ];
    final br = await Future.wait([
      c.bagCpi(lines),
      c.bagCpi(lines),
    ]);
    final bsids = br.map((h) => h.checkoutSessionId).whereType<String>().toSet();
    c.note('AT6.bag', 'Future.wait 2× bag CPI', {
      'http': br.map((h) => h.status).toList(),
      'sids': bsids.toList(),
      'reused': br.map((h) => h.reused).toList(),
    }, lens: 'AT6');
    if (bsids.length > 1) {
      c.hold(
        id: 'AT6-02',
        lens: 'AT6',
        severity: 'P1',
        title: 'Corrida: 2 Sessions no mesmo saco',
        actor: 'buyer JWT',
        pre: 'saco 2 orders',
        repro: 'Future.wait 2× bag_checkout',
        expected: '1 cs_ partilhada',
        obtained: 'sids=$bsids',
      );
    } else {
      c.block('AT6-02', 'AT6', 'corrida bag → 1 Session', bsids.toList());
    }
  }
}

Future<void> _at4Captured(Rtat c) async {
  final paid = await c.e2e('setup_paid_order', {'initial_qty': 2});
  c.note('AT4.paid', 'setup_paid_order Stripe TEST', paid.brief, lens: 'AT4');
  final oid = (paid.map?['order_id'] ??
          (paid.map?['order'] is Map ? (paid.map!['order'] as Map)['id'] : null))
      ?.toString();
  final pid = paid.map?['product_id']?.toString();
  if (pid != null) c.createdProductIds.add(pid);
  if (oid == null) {
    c.skip('AT4.fixture', 'AT4', 'setup_paid_order sem order_id', paid.brief);
    return;
  }
  c.createdOrderIds.add(oid);
  final row = await c.orderRow(oid);
  c.note('AT4.row', 'order paga', row, lens: 'AT4');

  final hop = await c.singleCpi(oid);
  if (hop.ok) {
    c.hold(
      id: 'AT4-01',
      lens: 'AT4',
      severity: 'P1',
      title: 'CPI cria Session em order já paga',
      actor: 'buyer JWT',
      pre: 'setup_paid_order status=pago',
      repro: 'POST create-payment-intent order_id pago',
      expected: 'Checkout blocked: order already captured',
      obtained: hop.brief,
    );
  } else {
    c.block('AT4-01', 'AT4', 'CPI pós-pago bloqueado', hop);
  }

  final cancel = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'status': 'cancelado'},
  );
  await c.expectDenied(
    id: 'AT4-02',
    lens: 'AT4',
    title: 'Buyer PATCH cancelado após pago',
    hit: cancel,
    actor: 'buyer JWT',
    pre: 'order paga Stripe TEST',
    repro: 'PATCH orders status=cancelado',
    severityIfOpen: 'P1',
  );

  final buyerRefund = await c.edge('refund-order', {
    'order_id': oid,
  }, jwt: c.buyerJwt);
  if (buyerRefund.ok && buyerRefund.map?['skipped'] != true) {
    final refundId = buyerRefund.map?['refund_id'] ?? buyerRefund.map?['id'];
    if (refundId != null) {
      c.hold(
        id: 'AT4-03',
        lens: 'AT4',
        severity: 'P0',
        title: 'Buyer JWT dispara refund-order',
        actor: 'buyer JWT',
        pre: 'order paga; refund é seller-only',
        repro: 'POST refund-order order_id',
        expected: '403 Sem permissão',
        obtained: buyerRefund.brief,
      );
    } else {
      c.block('AT4-03', 'AT4', 'buyer refund sem refund_id', buyerRefund);
    }
  } else {
    c.block('AT4-03', 'AT4', 'buyer refund-order recusado', buyerRefund);
  }

  if (c.buyer2Jwt != null) {
    final b2r = await c.edge('refund-order', {
      'order_id': oid,
    }, jwt: c.buyer2Jwt);
    await c.expectDenied(
      id: 'AT7-01',
      lens: 'AT7',
      title: 'B2 refund-order da venda B1',
      hit: b2r,
      actor: 'buyer2 JWT',
      pre: 'order paga de B1',
      repro: 'POST refund-order como B2',
      severityIfOpen: 'P0',
    );
  }
}

Future<void> _at7SecondActor(Rtat c) async {
  if (c.buyer2Jwt == null || c.buyer2Id == null) {
    c.skip('AT7.b2', 'AT7', 'buyer2 ausente', 'null');
    return;
  }
  final p = await c.insertProduct(price: 7.0, qty: 3, title: '$prefix-b2');
  if (p == null) return;
  final o = await c.insertOrder(productId: p);
  if (o == null) return;

  final b2cpi = await c.singleCpi(o, jwt: c.buyer2Jwt);
  if (b2cpi.ok) {
    c.hold(
      id: 'AT7-02',
      lens: 'AT7',
      severity: 'P1',
      title: 'B2 cria Checkout Session da order de B1',
      actor: 'buyer2 JWT',
      pre: 'order buyer_id=B1',
      repro: 'POST create-payment-intent order_id (JWT B2)',
      expected: '4xx order does not belong to buyer',
      obtained: b2cpi.brief,
    );
  } else {
    c.block('AT7-02', 'AT7', 'B2 CPI order B1 bloqueado', b2cpi);
  }

  final b2patch = await c.rest(
    'PATCH',
    'orders?id=eq.$o',
    jwt: c.buyer2Jwt,
    body: {'shipping_method': 'carrier'},
  );
  await c.expectDenied(
    id: 'AT7-03',
    lens: 'AT7',
    title: 'B2 PATCH order de B1',
    hit: b2patch,
    actor: 'buyer2 JWT',
    pre: 'order buyer=B1',
    repro: 'PATCH orders shipping_method',
    severityIfOpen: 'P2',
  );

  if (c.seller2Jwt != null) {
    final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_ids': [p],
      'status': 'pending',
    });
    if (bun.firstId != null) c.createdBundleIds.add(bun.firstId!);
    if (bun.firstId != null) {
      final s2acc = await c.rest(
        'PATCH',
        'product_bundles?id=eq.${bun.firstId}',
        jwt: c.seller2Jwt,
        body: {'status': 'accepted', 'discount_pct': 50},
      );
      await c.expectDenied(
        id: 'AT7-04',
        lens: 'AT7',
        title: 'S2 aceita bundle de S1',
        hit: s2acc,
        actor: 'seller2 JWT',
        pre: 'bundle seller_id=S1',
        repro: 'PATCH product_bundles status=accepted JWT S2',
        severityIfOpen: 'P1',
      );
    }
  }
}

Future<void> _at8Caixa(Rtat c, Map<String, num?> w0) async {
  final bag = await c.e2e('setup_paid_bag', {});
  c.note('AT8.bag', 'setup_paid_bag Stripe TEST', bag.brief, lens: 'AT8');
  final w1 = await c.wallets();
  c.note('AT8.wallets', 'Δ wallet após bag pago', {'before': w0, 'after': w1},
      lens: 'AT8');
  final oa = bag.map?['order_a_id']?.toString();
  final ob = bag.map?['order_b_id']?.toString();
  final pa = bag.map?['product_a_id']?.toString();
  final pb = bag.map?['product_b_id']?.toString();
  if (oa != null) c.createdOrderIds.add(oa);
  if (ob != null) c.createdOrderIds.add(ob);
  if (pa != null) c.createdProductIds.add(pa);
  if (pb != null) c.createdProductIds.add(pb);

  if (!bag.ok) {
    c.note('AT8.bag.fail', 'setup_paid_bag não ok', bag.brief, lens: 'AT8');
  } else {
    final paidA = numOf(bag.map?['paid_a']);
    final paidB = numOf(bag.map?['paid_b']);
    final piAmt = numOf(bag.map?['pi_amount_cents']);
    if (paidA != null && piAmt != null && paidA >= piAmt) {
      c.hold(
        id: 'AT8-01',
        lens: 'AT8',
        severity: 'P1',
        title: 'Linha A do saco gravou o PI completo em amount_paid_cents',
        actor: 'e2e settle (observação)',
        pre: 'setup_paid_bag 2 linhas',
        repro: 'probe setup_paid_bag',
        expected: 'cada linha < PI; soma = PI',
        obtained: 'paidA=$paidA paidB=$paidB pi=$piAmt',
      );
    } else {
      c.block('AT8-01', 'AT8', 'amount_paid_cents proporcional no saco pago', {
        'paidA': paidA,
        'paidB': paidB,
        'pi': piAmt,
      });
    }
  }

  if (oa != null) {
    final row = await c.orderRow(oa);
    final hop = await c.singleCpi(oa);
    if (hop.ok) {
      c.hold(
        id: 'AT4-04',
        lens: 'AT4',
        severity: 'P1',
        title: '2.ª Session em linha de saco já paga',
        actor: 'buyer JWT',
        pre: 'setup_paid_bag linha A pago',
        repro: 'CPI single na order A paga',
        expected: 'blocked already captured',
        obtained: '${hop.brief} row=$row',
      );
    } else {
      c.block('AT4-04', 'AT4', 'CPI saco-pago bloqueado', hop);
    }
  }
}
