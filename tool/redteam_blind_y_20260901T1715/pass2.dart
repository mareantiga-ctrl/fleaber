// ignore_for_file: avoid_print
import 'dart:io';
import '_rty.dart';

/// Pass 2 — checkout real (buyer_id), TOCTOU refund∥ship, status allowlist, disputa.
Future<void> main() async {
  final c = Rty.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  await allowlistRefund(c);
  await toctouRefundThenShip(c);
  await bundleExtraQty(c);
  await stealBundle(c);
  await twoBundles(c);
  await sessionReuse(c);
  await racePi(c);
  await offerWrong(c);
  await offerQty2(c);
  await disputeOnPago(c);
  await happyRefund(c);

  await dumpJson('${outDir()}/pass2.json', {
    'prefix': prefix,
    'findings': c.findings,
    'closed': c.closed,
    'notes': c.notes,
  });
  stdout.writeln(
      'PASS2 DONE findings=${c.findings.length} closed=${c.closed.length}');
}

Future<Map<String, dynamic>?> paidFixture(Rty c) async {
  final h = await c.setupPaidOrder();
  final oid = '${h.map?['order_id'] ?? ''}'.trim();
  if (oid.isEmpty) {
    c.note('fixture.fail', 'setup_paid_order', h, lens: 'Y1');
    return null;
  }
  c.createdOrderIds.add(oid);
  final pid = '${h.map?['product_id'] ?? ''}'.trim();
  if (pid.isNotEmpty) c.createdProductIds.add(pid);
  await c.rest('PATCH', 'orders?id=eq.$oid', service: true, body: {
    'shipping_method': 'mao',
    'payment_method': 'pagamento na app',
  }, prefer: 'return=minimal');
  return h.map;
}

Future<void> allowlistRefund(Rty c) async {
  for (final st in [
    'premio_rifa',
    'aguarda_confirmacao',
    'reservado',
    'pendente',
    'reserva_pendente',
  ]) {
    final fx = await paidFixture(c);
    final oid = '${fx?['order_id'] ?? ''}'.trim();
    if (oid.isEmpty) continue;
    final patch = await c.rest('PATCH', 'orders?id=eq.$oid',
        jwt: c.sellerJwt, body: {'status': st});
    final row = await c.orderRow(oid);
    c.note('Y1.allow.$st', 'PATCH allowlist', {
      'http': patch.status,
      'status': row?['status'],
      'shipped_at': row?['shipped_at'],
    }, lens: 'Y1');
    if ('${row?['status']}' != st) {
      c.closedPath('Y1.allow.$st', 'não persistiu', patch, lens: 'Y1');
      continue;
    }
    final ref = await c.refundOrder(oid);
    final after = await c.orderRow(oid);
    final refunded = '${after?['stripe_refund_id'] ?? ''}'.trim().isNotEmpty ||
        '${after?['status']}' == 'cancelado';
    if (refunded) {
      c.finding(
        id: 'RTY-Y1-010-$st',
        lens: 'Y1',
        severity: 'P1',
        title: 'Hop pago→$st depois refund Stripe (sem shipped_at)',
        actor: 'seller JWT',
        pre: 'Stripe TEST pago',
        repro: 'PATCH status=$st → POST refund-order',
        expected: 'refund só em pago pré-envio, ou bloqueio do hop',
        obtained: {'patch': patch.brief, 'refund': ref.brief, 'after': after},
        impact:
            'Estado fora de enviado mas refund ainda possível — se o hop for pós-envio conceptual, fura o selo',
      );
    } else {
      c.closedPath('Y1.allow.$st.refund', 'refund não liquidou', ref, lens: 'Y1');
    }
  }
}

Future<void> toctouRefundThenShip(Rty c) async {
  final fx = await paidFixture(c);
  final oid = '${fx?['order_id'] ?? ''}'.trim();
  if (oid.isEmpty) return;
  // Refund starts first (gate on pago); ship mid-flight.
  final refundF = c.refundOrder(oid);
  await Future<void>.delayed(const Duration(milliseconds: 250));
  final ship = c.rest('PATCH', 'orders?id=eq.$oid',
      jwt: c.sellerJwt, body: {'status': 'enviado'});
  final refundF2 = c.refundOrder(oid);
  final results = await Future.wait([refundF, ship, refundF2]);
  final row = await c.orderRow(oid);
  c.note('Y6.toctou', 'refund +250ms ship + refund', {
    'r1': results[0].brief,
    'ship': results[1].brief,
    'r2': results[2].brief,
    'row': row,
  }, lens: 'Y6');
  final shipped = row?['shipped_at'] != null;
  final refunded = '${row?['stripe_refund_id'] ?? ''}'.trim().isNotEmpty ||
      '${row?['status']}' == 'cancelado';
  if (shipped && refunded) {
    c.finding(
      id: 'RTY-Y6-002',
      lens: 'Y6',
      severity: 'P0',
      title: 'TOCTOU: refund-order passa o gate em pago e finaliza após enviado',
      actor: 'seller JWT concurrent',
      pre: 'pago Stripe',
      repro: 'POST refund-order; delay 250ms; PATCH enviado; 2.º refund',
      expected: 'finalize recusa se shipped_at já selado',
      obtained: row,
      impact: 'Stripe refund + stock restore em encomenda já enviada',
    );
  } else {
    c.closedPath('Y6.toctou', 'não ficou shipped+refund', row, lens: 'Y6');
  }
}

Future<void> bundleExtraQty(Rty c) async {
  final pa = await c.insertProduct(title: '$prefix A', qty: 8, price: 20);
  final pb = await c.insertProduct(title: '$prefix B', qty: 8, price: 20);
  if (pa == null || pb == null) return;
  final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_ids': [pa, pb],
  });
  final bid = bun.firstId;
  if (bid == null) return;
  await c.rest('PATCH', 'product_bundles?id=eq.$bid',
      jwt: c.sellerJwt, body: {'status': 'accepted', 'discount_pct': 50});
  final bunRow = await c.rest(
    'GET',
    'product_bundles?id=eq.$bid&select=total_eur,status',
    service: true,
  );
  final bundleTotal = bunRow.map?['total_eur'];
  final oa = await c.insertOrder(productId: pa, qty: 3, bundleId: bid);
  final ob = await c.insertOrder(productId: pb, qty: 1, bundleId: bid);
  c.note('Y2.orders', 'qty 3+1', {
    'oa': await c.orderRow(oa ?? ''),
    'ob': await c.orderRow(ob ?? ''),
    'bundleTotal': bundleTotal,
  }, lens: 'Y2');
  if (oa == null || ob == null) return;
  final q = await c.checkout(bag: true, bagLines: [
    {'order_id': oa},
    {'order_id': ob},
  ]);
  final cents = num.tryParse('${q.map?['server_amount_cents'] ?? q.map?['amount_total'] ?? ''}');
  c.note('Y2.extra_qty', 'quote', {'cents': cents, 'q': q.brief}, lens: 'Y2');
  // Honest 4×20=80 + prot. Bundle-of-2 = 20 + prot (~21.7€ = 2170c). Cap 4000c ≈ 40€.
  if (q.ok && cents != null && cents < 4000) {
    c.finding(
      id: 'RTY-Y2-001',
      lens: 'Y2',
      severity: 'P0',
      title: 'Conjunto aceite: total_eur ignora quantity extra',
      actor: 'buyer JWT',
      pre: 'bundle A+B total=$bundleTotal; orders 3+1',
      repro: 'bag create-payment-intent',
      expected: 'cobrar 3A+1B ou recusar qty≠1',
      obtained: {'cents': cents, 'bundle_total': bundleTotal, 'quote': q.brief},
      impact: 'Pagar ~2 unidades, hold/settle 4',
    );
  } else if (!q.ok) {
    c.closedPath('Y2.extra_qty', 'checkout recusou', q, lens: 'Y2');
  } else {
    c.closedPath('Y2.extra_qty.priced', 'cents=$cents não é preço de 2 un.', q,
        lens: 'Y2');
  }
}

Future<void> stealBundle(Rty c) async {
  final pa = await c.insertProduct(title: '$prefix sA', qty: 4, price: 25);
  final pb = await c.insertProduct(title: '$prefix sB', qty: 4, price: 25);
  if (pa == null || pb == null) return;
  final bun = await c.rest('POST', 'product_bundles', jwt: c.buyer2Jwt, body: {
    'buyer_id': c.buyer2Id,
    'seller_id': c.sellerId,
    'product_ids': [pa, pb],
  });
  final bid = bun.firstId;
  if (bid == null) return;
  await c.rest('PATCH', 'product_bundles?id=eq.$bid',
      jwt: c.sellerJwt, body: {'status': 'accepted', 'discount_pct': 50});
  final oa = await c.insertOrder(productId: pa, qty: 1);
  final ob = await c.insertOrder(productId: pb, qty: 1);
  if (oa == null || ob == null) return;
  final attA = await c.rest('PATCH', 'orders?id=eq.$oa',
      jwt: c.buyerJwt, body: {'bundle_id': bid});
  final attB = await c.rest('PATCH', 'orders?id=eq.$ob',
      jwt: c.buyerJwt, body: {'bundle_id': bid});
  final rowA = await c.orderRow(oa);
  final q = await c.checkout(bag: true, bagLines: [
    {'order_id': oa},
    {'order_id': ob},
  ]);
  final cents = num.tryParse('${q.map?['server_amount_cents'] ?? ''}');
  c.note('Y2.steal', 'B1+bundle B2', {
    'attA': attA.brief,
    'attB': attB.brief,
    'bundle_id': rowA?['bundle_id'],
    'cents': cents,
    'q': q.brief,
  }, lens: 'Y2');
  final attached = rowA?['bundle_id']?.toString() == bid;
  // 25+25=50 list; 50% = 25 + prot ~27€. If attached and cents < 4000 (40€) vs ~53€ list.
  if (attached && q.ok && cents != null && cents < 4000) {
    c.finding(
      id: 'RTY-Y2-002',
      lens: 'Y2',
      severity: 'P1',
      title: 'B1 anexa bundle aceite de B2 e checkout usa total_eur alheio',
      actor: 'buyer JWT',
      pre: 'bundle B2 aceite 50%',
      repro: 'PATCH orders.bundle_id=bundle_B2 → bag checkout',
      expected: 'bundle.buyer_id tem de coincidir com order.buyer_id',
      obtained: {'cents': cents, 'bundle': bid, 'quote': q.brief},
    );
  } else if (!attached) {
    c.closedPath('Y2.steal.patch', 'não anexou', attA, lens: 'Y2');
  } else {
    c.closedPath('Y2.steal.quote', 'anexou sem subcotar / checkout fail', q,
        lens: 'Y2');
  }
}

Future<void> twoBundles(Rty c) async {
  final pa = await c.insertProduct(title: '$prefix 2A', qty: 3, price: 12);
  final pb = await c.insertProduct(title: '$prefix 2B', qty: 3, price: 12);
  if (pa == null || pb == null) return;
  final b1 = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_ids': [pa, pb],
  });
  final b2 = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_ids': [pa, pb],
  });
  final id1 = b1.firstId;
  final id2 = b2.firstId;
  if (id1 == null || id2 == null) return;
  await c.rest('PATCH', 'product_bundles?id=eq.$id1',
      jwt: c.sellerJwt, body: {'status': 'accepted', 'discount_pct': 10});
  await c.rest('PATCH', 'product_bundles?id=eq.$id2',
      jwt: c.sellerJwt, body: {'status': 'accepted', 'discount_pct': 40});
  final o1 = await c.insertOrder(productId: pa, qty: 1, bundleId: id1);
  final o2 = await c.insertOrder(productId: pb, qty: 1, bundleId: id2);
  if (o1 == null || o2 == null) return;
  final q = await c.checkout(bag: true, bagLines: [
    {'order_id': o1},
    {'order_id': o2},
  ]);
  if (q.ok) {
    c.finding(
      id: 'RTY-Y2-003',
      lens: 'Y2',
      severity: 'P1',
      title: 'Saco com 2 bundle_id distintos cria Session',
      actor: 'buyer JWT',
      pre: 'duas orders, dois conjuntos aceites',
      repro: 'bag create-payment-intent',
      expected: 'blocked multiple bundle contracts',
      obtained: q,
    );
  } else {
    c.closedPath('Y2.two_bundles', 'recusou 2 bundle_id', q, lens: 'Y2');
  }
}

Future<void> sessionReuse(Rty c) async {
  final p1 = await c.insertProduct(title: '$prefix cheap', qty: 4, price: 8);
  final p2 = await c.insertProduct(title: '$prefix dear', qty: 4, price: 40);
  if (p1 == null || p2 == null) return;
  final o1 = await c.insertOrder(productId: p1, qty: 1);
  if (o1 == null) return;
  final s1 = await c.checkout(orderId: o1);
  final sid1 = '${s1.map?['checkoutSessionId'] ?? ''}';
  final amt1 = s1.map?['server_amount_cents'] ?? s1.map?['amount_total'];
  final o2 = await c.insertOrder(productId: p2, qty: 1);
  if (o2 == null) return;
  final s2 = await c.checkout(bag: true, bagLines: [
    {'order_id': o1},
    {'order_id': o2},
  ]);
  c.note('Y3.reuse', 'A then A+B', {
    's1': s1.brief,
    's2': s2.brief,
    'sid1': sid1,
    'sid2': s2.map?['checkoutSessionId'],
    'amt1': amt1,
    'amt2': s2.map?['server_amount_cents'],
    'amount_total': s2.map?['amount_total'],
    'reused': s2.map?['reused_session'],
  }, lens: 'Y3');
  final sid2 = '${s2.map?['checkoutSessionId'] ?? ''}';
  final reused = s2.map?['reused_session'] == true || (sid1.startsWith('cs_') && sid1 == sid2);
  final a1 = num.tryParse('$amt1') ?? 0;
  final a2 = num.tryParse('${s2.map?['server_amount_cents']}') ?? 0;
  final at = num.tryParse('${s2.map?['amount_total']}') ?? 0;
  if (s2.ok && reused && a1 > 0 && (at == a1 && a2 > a1 + 200 || at < a2 - 200 && at == a1)) {
    c.finding(
      id: 'RTY-Y3-001',
      lens: 'Y3',
      severity: 'P1',
      title: 'Reuse Session barata quando o saco já é A+B',
      actor: 'buyer JWT',
      pre: 'cs_ da order 8€ ainda open',
      repro: 'checkout A; bag A+B',
      expected: 'nova Session com total A+B',
      obtained: {
        'sid1': sid1,
        'sid2': sid2,
        'amt1': amt1,
        'server_amount_cents': s2.map?['server_amount_cents'],
        'amount_total': s2.map?['amount_total'],
      },
    );
  } else if (!s2.ok) {
    c.closedPath('Y3.reuse', 'bag checkout falhou', s2, lens: 'Y3');
  } else {
    c.closedPath('Y3.reuse.ok', 'sem reuse barato', {
      'reused': reused,
      'a1': a1,
      'a2': a2,
      'at': at,
    }, lens: 'Y3');
  }
}

Future<void> racePi(Rty c) async {
  final p = await c.insertProduct(title: '$prefix race', qty: 2, price: 9);
  final o = await c.insertOrder(productId: p!, qty: 1);
  if (o == null) return;
  final raced = await Future.wait([
    c.checkout(orderId: o),
    c.checkout(orderId: o),
    c.checkout(orderId: o),
  ]);
  final sids = raced
      .map((h) => '${h.map?['checkoutSessionId'] ?? ''}')
      .where((s) => s.startsWith('cs_'))
      .toSet()
      .toList();
  c.note('Y3.race3', '3× checkout', {
    'briefs': raced.map((e) => e.brief).toList(),
    'sids': sids,
  }, lens: 'Y3');
  if (sids.length > 1) {
    c.finding(
      id: 'RTY-Y3-002',
      lens: 'Y3',
      severity: 'P1',
      title: 'Race 3× POST cria >1 Checkout Session',
      actor: 'buyer JWT',
      pre: 'order pendente',
      repro: 'Future.wait 3× create-payment-intent',
      expected: '1 cs_',
      obtained: sids,
    );
  } else {
    c.closedPath('Y3.race3', '1 session', sids, lens: 'Y3');
  }
}

Future<void> offerWrong(Rty c) async {
  final pA = await c.insertProduct(title: '$prefix offA', qty: 3, price: 30);
  final pB = await c.insertProduct(title: '$prefix offB', qty: 3, price: 30);
  if (pA == null || pB == null) return;
  final off = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pA,
    'offer_price': 6,
  });
  final oid = off.firstId;
  if (oid == null) return;
  await c.rest('PATCH', 'product_offers?id=eq.$oid',
      jwt: c.sellerJwt, body: {'status': 'accepted'});
  final orderB = await c.insertOrder(productId: pB, qty: 1, offerId: oid);
  if (orderB == null) {
    c.closedPath('Y2.offer.wrong', 'INSERT recusado', 'no order', lens: 'Y2');
    return;
  }
  final row = await c.orderRow(orderB);
  final q = await c.checkout(orderId: orderB);
  final cents = num.tryParse('${q.map?['server_amount_cents'] ?? ''}');
  c.note('Y2.offer.wrong', 'offer A on B', {
    'row': row,
    'cents': cents,
    'q': q.brief,
  }, lens: 'Y2');
  final used = row?['product_offer_id']?.toString() == oid;
  if (used && q.ok && cents != null && cents < 1500) {
    c.finding(
      id: 'RTY-Y2-004',
      lens: 'Y2',
      severity: 'P0',
      title: 'Oferta do produto A aplica-se ao checkout de B',
      actor: 'buyer JWT',
      pre: 'oferta 6€ em A',
      repro: 'POST orders product_id=B product_offer_id=A → checkout',
      expected: 'limpar offer ou recusar',
      obtained: {'cents': cents, 'contract': row?['contract_unit_cents']},
    );
  } else {
    c.closedPath('Y2.offer.wrong', 'não subcotou B', {
      'used': used,
      'cents': cents,
      'unit': row?['contract_unit_cents'],
    }, lens: 'Y2');
  }
}

Future<void> offerQty2(Rty c) async {
  final pA = await c.insertProduct(title: '$prefix oq', qty: 4, price: 18);
  if (pA == null) return;
  final off = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pA,
    'offer_price': 10,
  });
  final oid = off.firstId;
  if (oid == null) return;
  await c.rest('PATCH', 'product_offers?id=eq.$oid',
      jwt: c.sellerJwt, body: {'status': 'accepted'});
  final o = await c.insertOrder(productId: pA, qty: 2, offerId: oid);
  if (o != null) {
    c.finding(
      id: 'RTY-Y2-005',
      lens: 'Y2',
      severity: 'P1',
      title: 'Oferta com quantity=2 na INSERT',
      actor: 'buyer JWT',
      pre: 'offer accepted',
      repro: 'POST orders quantity=2 product_offer_id',
      expected: 'offer_quantity_must_be_one',
      obtained: await c.orderRow(o),
    );
  } else {
    c.closedPath('Y2.offer.qty2', 'qty=2 recusado', 'no order', lens: 'Y2');
  }
}

Future<void> disputeOnPago(Rty c) async {
  final fx = await paidFixture(c);
  final oid = '${fx?['order_id'] ?? ''}'.trim();
  if (oid.isEmpty) return;
  final d = await c.rest('POST', 'order_disputes', jwt: c.buyerJwt, body: {
    'order_id': oid,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'reason': '$prefix pago dispute',
    'status': 'aberta',
  });
  c.note('Y5.disp', 'insert disputa em pago', d, lens: 'Y5');
  final did = d.firstId;
  if (did != null) {
    await c.rest('PATCH', 'order_disputes?id=eq.$did', jwt: c.sellerJwt, body: {
      'seller_refund_percent': 30,
      'seller_offer_type': 'partial_refund',
      'seller_offer_set_by': c.sellerId,
    });
    final wr = await c.rpc(
      'batata_process_partial_refund_dispute',
      {'p_order_id': oid},
      jwt: c.buyerJwt,
    );
    final tx = await c.rest(
      'GET',
      'wallet_transactions?order_id=eq.$oid&select=wallet_id,amount,type,description',
      service: true,
    );
    final row = await c.orderRow(oid);
    c.note('Y5.rpc', 'partial on pago', {
      'rpc': wr.brief,
      'tx': tx.brief,
      'row': row,
    }, lens: 'Y5');
    final minted = tx.list.any((e) => e is Map && '${e['type']}' == 'reembolso');
    if (wr.ok && minted) {
      c.finding(
        id: 'RTY-Y5-001',
        lens: 'Y5',
        severity: 'P1',
        title: 'Disputa parcial minta wallet em pago sem Stripe refund',
        actor: 'B1+S1',
        pre: 'Stripe capturado, status pago',
        repro: 'disputa + offer 30% + batata_process_partial_refund_dispute',
        expected: 'exige stripe_refund_id ou bloqueia plataforma capturada',
        obtained: {'rpc': wr.brief, 'tx': tx.brief},
        impact: 'Δwallet + captura Stripe (double)',
      );
    } else {
      c.closedPath('Y5.mint', 'não mintou', wr, lens: 'Y5');
    }
  }
  final ref = await c.refundOrder(oid);
  if (ref.ok && ref.map?['ok'] == true && ref.map?['skipped'] != true) {
    c.finding(
      id: 'RTY-Y5-002',
      lens: 'Y5',
      severity: 'P1',
      title: 'refund-order com disputa aberta',
      actor: 'seller JWT',
      pre: 'pago + disputa',
      repro: 'POST refund-order',
      expected: '403 open_dispute',
      obtained: ref,
    );
  } else {
    c.closedPath('Y5.refund_disp', 'refund bloqueado', ref, lens: 'Y5');
  }
}

Future<void> happyRefund(Rty c) async {
  final fx = await paidFixture(c);
  final oid = '${fx?['order_id'] ?? ''}'.trim();
  if (oid.isEmpty) return;
  final ref = await c.refundOrder(oid);
  final after = await c.orderRow(oid);
  c.note('happy', 'refund pré-envio', {
    'ref': ref.brief,
    'after': after,
  }, lens: 'Y1');
  if (after?['stripe_refund_id'] == null && '${after?['status']}' != 'cancelado') {
    c.finding(
      id: 'RTY-REG-001',
      lens: 'Y1',
      severity: 'P2',
      title: 'Regressão: refund antes de enviar falhou',
      actor: 'seller JWT',
      pre: 'pago',
      repro: 'POST refund-order',
      expected: 'cancelado + stripe_refund_id',
      obtained: {'ref': ref.brief, 'after': after},
    );
  } else {
    c.closedPath('happy', 'refund pré-envio OK', after, lens: 'Y1');
  }
}
