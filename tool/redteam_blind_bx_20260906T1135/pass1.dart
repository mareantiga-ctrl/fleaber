/// RED TEAM CEGO BX pass1 — variantes novas pós-BRBW.
/// Exactos a NÃO contar: 3 sacos A∩B∩C · AB∥AC dual · hífen+compact.
/// Novas: anel 4 sacos · bag+single paralelo · metadata drift pós-claim ·
/// currency ZWJ · offer freeze Unicode · settle Session orphan list.
import 'dart:io';

import '_rtbx.dart';

Future<void> main() async {
  final c = Rtbx.fromEnv(loadEnv());
  stdout.writeln('BX pass1 staging=${c.url} prefix=$prefix');
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('actors', 'ids', {
    'b': c.buyerId,
    's': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
  });

  await bx8PaidBaseline(c);
  await bx1AmountIgnored(c);
  await bx7AnonAndBuyer2(c);
  await bx2ClaimRpcJwt(c);
  await bx2Ring4(c);
  await bx2BagPlusSingle(c);
  await bx2MetadataDrift(c);
  await bx1CurrencyZwj(c);
  await bx3OfferFreezeUnicode(c);
  await bx2SettleOrphanList(c);
  await bx3BundlePartial(c);
  await bx4FsmPago(c);
  await bx5StockAndCrossSeller(c);

  await c.dumpAll('pass1_findings.json');
  stdout.writeln(
    'DONE findings=${c.findings.length} blocked=${c.blocked.length} '
    'lenses=${c.lensesHit.toList()..sort()}',
  );
}

Future<void> bx8PaidBaseline(Rtbx c) async {
  final w0 = await c.walletBal(c.sellerId);
  final paid = await c.payToPago(lens: 'BX8', initialQty: 2);
  if (paid == null) {
    c.skip('BX8.paid', 'BX8', 'setup_paid_order falhou', 'null');
    return;
  }
  final row = await c.orderRow(paid.oid);
  final w1 = await c.walletBal(c.sellerId);
  final st = '${row?['status']}';
  final applied = row?['stock_units_applied'];
  c.note('BX8.paid.row', 'order pago Stripe TEST', {
    'oid': paid.oid,
    'status': st,
    'pi': paid.pi,
    'stock_units_applied': applied,
    'amount_paid_cents': row?['amount_paid_cents'],
    'wallet_delta': (w1 - w0),
  }, lens: 'BX8');
  if (st.toLowerCase() != 'pago') {
    c.hold(
      id: 'RTBX-BX8-PAID-STATUS',
      lens: 'BX8',
      severity: 'P2',
      title: 'setup_paid_order não deixou status=pago',
      actor: 'service_role fixture',
      pre: 'E2E Stripe TEST',
      repro: 'sec-fase2-e2e-oversell setup_paid_order',
      expected: 'pago + PI',
      obtained: row,
    );
  } else {
    c.block('BX8.paid', 'BX8', 'compra Stripe TEST liquidada', {
      'oid': paid.oid,
      'pi': paid.pi,
      'status': st,
    });
  }
}

Future<void> bx1AmountIgnored(Rtbx c) async {
  final p = await c.createProduct(title: '$prefix-amt', price: 18, qty: 2);
  if (p == null) return;
  final o = await c.insertOrder(
    productId: p,
    jwt: c.buyerJwt,
    price: 18,
  );
  if (o == null) return;
  final hit = await c.checkout(orderId: o, productId: p, amount: 1);
  final amt = hit.amountTotal ?? 0;
  c.note('BX1.amt', 'body amount=1 vs server', {
    'hit': hit.brief,
    'server': amt,
  }, lens: 'BX1');
  if (hit.ok && amt > 0 && amt < 500) {
    c.hold(
      id: 'RTBX-BX1-UNDERPAY-AMOUNT',
      lens: 'BX1',
      severity: 'P0',
      title: 'Session abaixo do catálogo com amount=1',
      actor: 'buyer JWT',
      pre: 'SKU 18 €',
      repro: 'POST create-payment-intent amount=1',
      expected: 'quote ≥ 18 € + protecção',
      obtained: hit.brief,
    );
  } else if (hit.ok && amt >= 1800) {
    c.block('BX1.amount', 'BX1', 'amount=1 ignorado, quote servidor', amt);
  } else {
    c.block('BX1.amount.deny', 'BX1', 'amount=1 não criou underpay', hit.brief);
  }
}

Future<void> bx7AnonAndBuyer2(Rtbx c) async {
  final p = await c.createProduct(title: '$prefix-xuser', price: 11, qty: 2);
  if (p == null) return;
  final o = await c.insertOrder(productId: p, jwt: c.buyerJwt, price: 11);
  if (o == null) return;
  final anon = await c.checkout(orderId: o, productId: p, jwt: null, buyer: c.buyerId);
  if (anon.ok) {
    c.hold(
      id: 'RTBX-BX7-ANON-CHECKOUT',
      lens: 'BX7',
      severity: 'P1',
      title: 'Anon criou Checkout Session',
      actor: 'anon',
      pre: 'order do buyer',
      repro: 'POST create-payment-intent sem JWT user',
      expected: '401/400',
      obtained: anon.brief,
    );
  } else {
    c.block('BX7.anon', 'BX7', 'anon recusado', anon.brief);
  }
  final b2 = await c.checkout(
    orderId: o,
    productId: p,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  if (b2.ok) {
    c.hold(
      id: 'RTBX-BX7-B2-ALIEN-ORDER',
      lens: 'BX7',
      severity: 'P1',
      title: 'B2 fez checkout de order do B1',
      actor: 'buyer2 JWT',
      pre: 'order buyer1',
      repro: 'POST create-payment-intent buyer_id=B2 order=B1',
      expected: 'recusar',
      obtained: b2.brief,
    );
  } else {
    c.block('BX7.b2', 'BX7', 'B2 recusado na order alheia', b2.brief);
  }
}

Future<void> bx2ClaimRpcJwt(Rtbx c) async {
  final p = await c.createProduct(title: '$prefix-claim', price: 10, qty: 2);
  if (p == null) return;
  final o = await c.insertOrder(productId: p, jwt: c.buyerJwt, price: 10);
  if (o == null) return;
  final jwtHit = await c.rpc('batata_bag_checkout_claim', {
    'p_order_ids': [o],
    'p_claim_token': 'claiming:rtbx-jwt-should-fail-xx',
  }, jwt: c.buyerJwt);
  final anonHit = await c.rpc('batata_bag_checkout_claim', {
    'p_order_ids': [o],
    'p_claim_token': 'claiming:rtbx-anon-should-fail-x',
  });
  c.note('BX2.claim.jwt', 'RPC claim JWT', jwtHit.brief, lens: 'BX2');
  c.note('BX2.claim.anon', 'RPC claim anon', anonHit.brief, lens: 'BX2');
  if (jwtHit.ok) {
    c.hold(
      id: 'RTBX-BX2-CLAIM-JWT',
      lens: 'BX2',
      severity: 'P1',
      title: 'buyer JWT executa batata_bag_checkout_claim',
      actor: 'buyer JWT',
      pre: 'GRANT esperado só service_role',
      repro: 'POST /rest/v1/rpc/batata_bag_checkout_claim',
      expected: '403/404',
      obtained: jwtHit.brief,
    );
  } else {
    c.block('BX2.claim.jwt', 'BX2', 'claim RPC negado a JWT', jwtHit.brief);
  }
  if (anonHit.ok) {
    c.hold(
      id: 'RTBX-BX2-CLAIM-ANON',
      lens: 'BX2',
      severity: 'P1',
      title: 'anon executa batata_bag_checkout_claim',
      actor: 'anon',
      pre: 'GRANT esperado só service_role',
      repro: 'POST rpc batata_bag_checkout_claim anon',
      expected: '403/404',
      obtained: anonHit.brief,
    );
  } else {
    c.block('BX2.claim.anon', 'BX2', 'claim RPC negado a anon', anonHit.brief);
  }
}

Future<void> bx2Ring4(Rtbx c) async {
  final prices = [12.0, 13.0, 14.0, 15.0];
  final pids = <String>[];
  final oids = <String>[];
  for (var i = 0; i < 4; i++) {
    final p = await c.createProduct(
      title: '$prefix-ring$i',
      price: prices[i],
      qty: 5,
    );
    if (p == null) {
      c.skip('BX2.ring4', 'BX2', 'produto ring falhou', i);
      return;
    }
    pids.add(p);
    final o = await c.insertOrder(
      productId: p,
      jwt: c.buyerJwt,
      price: prices[i],
    );
    if (o == null) {
      c.skip('BX2.ring4.o', 'BX2', 'order ring falhou', i);
      return;
    }
    oids.add(o);
  }

  List<Map<String, Object?>> pair(int a, int b) => [
        {'order_id': oids[a], 'product_id': pids[a]},
        {'order_id': oids[b], 'product_id': pids[b]},
      ];
  final bags = <List<Map<String, Object?>>>[
    pair(0, 1),
    pair(1, 2),
    pair(2, 3),
    pair(3, 0),
  ];
  final labels = ['AB', 'BC', 'CD', 'DA'];
  final jobs = <Future<HttpHit>>[];
  for (var round = 0; round < 2; round++) {
    for (final b in bags) {
      jobs.add(c.checkoutBag(lines: b, amount: 1));
    }
  }
  final hits = await parallel(jobs);
  final byBag = <String, List<Map<String, Object?>>>{};
  for (var i = 0; i < hits.length; i++) {
    final lab = labels[i % 4];
    byBag.putIfAbsent(lab, () => []).add({
      'ok': hits[i].ok,
      'sid': hits[i].sessionId,
      'amt': hits[i].amountTotal,
      'reused': hits[i].reused,
      'brief': hits[i].brief,
    });
  }

  final rows = <Map<String, dynamic>>[];
  for (var i = 0; i < 4; i++) {
    rows.add(await c.orderRow(oids[i]) ?? {'id': oids[i]});
  }
  final sidsOnOrders = rows
      .map((r) => '${r['stripe_checkout_session_id'] ?? ''}')
      .where((s) => s.startsWith('cs_'))
      .toSet();
  final sidsFromHits = hits
      .where((h) => h.ok && (h.sessionId ?? '').startsWith('cs_'))
      .map((h) => h.sessionId!)
      .toSet();

  // Overlap pairs: AB∩DA=A, AB∩BC=B, BC∩CD=C, CD∩DA=D.
  final okSidsByBag = <String, Set<String>>{};
  for (final e in byBag.entries) {
    okSidsByBag[e.key] = e.value
        .map((m) => '${m['sid'] ?? ''}')
        .where((s) => s.startsWith('cs_'))
        .toSet();
  }
  final overlapDual = <String, Object?>{};
  void checkOverlap(String a, String b, String shared) {
    final sa = okSidsByBag[a] ?? {};
    final sb = okSidsByBag[b] ?? {};
    final inter = sa.intersection(sb);
    final union = {...sa, ...sb};
    if (union.length > 1 && inter.length != union.length) {
      overlapDual['$a∩$b($shared)'] = {
        'sids_$a': sa.toList(),
        'sids_$b': sb.toList(),
        'distinct': union.toList(),
      };
    }
  }

  checkOverlap('AB', 'DA', 'A');
  checkOverlap('AB', 'BC', 'B');
  checkOverlap('BC', 'CD', 'C');
  checkOverlap('CD', 'DA', 'D');

  // Split-brain: a pair checked out together ends with different SIDs on the two orders.
  final split = <String>[];
  final pairs = [
    [0, 1, 'AB'],
    [1, 2, 'BC'],
    [2, 3, 'CD'],
    [3, 0, 'DA'],
  ];
  for (final pr in pairs) {
    final sa = '${rows[pr[0] as int]['stripe_checkout_session_id'] ?? ''}';
    final sb = '${rows[pr[1] as int]['stripe_checkout_session_id'] ?? ''}';
    if (sa.startsWith('cs_') && sb.startsWith('cs_') && sa != sb) {
      split.add('${pr[2]} $sa vs $sb');
    }
  }

  c.note('BX2.ring4', 'anel 4 sacos AB-BC-CD-DA ×2', {
    'oids': oids,
    'byBag': byBag.map((k, v) => MapEntry(k, v.map((m) => {
          'ok': m['ok'],
          'sid': m['sid'],
          'amt': m['amt'],
          'reused': m['reused'],
        }).toList())),
    'order_sids': rows
        .map((r) => {
              'id': r['id'],
              'sid': r['stripe_checkout_session_id'],
              'price_total': r['price_total'],
            })
        .toList(),
    'distinct_order_sids': sidsOnOrders.length,
    'distinct_hit_sids': sidsFromHits.length,
    'overlap_dual_responses': overlapDual,
    'split_brain_pairs': split,
  }, lens: 'BX6');

  if (split.isNotEmpty) {
    c.hold(
      id: 'RTBX-BX2-RING4-SPLIT-SID',
      lens: 'BX2',
      severity: 'P1',
      title: 'Anel de 4 sacos: par sobreposto ficou com 2 Session IDs na BD',
      actor: 'buyer JWT paralelo',
      pre: '4 orders, bags AB,BC,CD,DA ×2 POST',
      repro: 'Future.wait 8 bag checkouts em anel',
      expected: 'no máximo 1 cs_ por order; pares do mesmo saco partilham SID',
      obtained: {'split': split, 'order_sids': sidsOnOrders.toList()},
      evidence: {'rows': rows.map((r) => '${r['id']}:${r['stripe_checkout_session_id']}').toList()},
    );
  } else if (overlapDual.isNotEmpty) {
    // Two overlapping bags returned different live session IDs (URLs). BD may have unified.
    c.hold(
      id: 'RTBX-BX2-RING4-DUAL-URL',
      lens: 'BX2',
      severity: 'P1',
      title: 'Anel de 4: sacos que partilham order devolveram Session IDs distintos',
      actor: 'buyer JWT paralelo',
      pre: 'bags AB∩DA etc.',
      repro: '8 POST bag_checkout em paralelo',
      expected: 'reuse/expire — 1 URL por recurso sobreposto',
      obtained: overlapDual,
      proven: true,
    );
  } else {
    c.block('BX2.ring4', 'BX2', 'anel 4 sem dual SID sobreposto', {
      'order_sids': sidsOnOrders.length,
      'hit_sids': sidsFromHits.length,
    });
  }

  // Residual control: do NOT count 3-bag A∩B∩C (exact BR). Not run.
}

Future<void> bx2BagPlusSingle(Rtbx c) async {
  final p0 = await c.createProduct(title: '$prefix-bs0', price: 16, qty: 4);
  final p1 = await c.createProduct(title: '$prefix-bs1', price: 9, qty: 4);
  if (p0 == null || p1 == null) return;
  final o0 = await c.insertOrder(productId: p0, jwt: c.buyerJwt, price: 16);
  final o1 = await c.insertOrder(productId: p1, jwt: c.buyerJwt, price: 9);
  if (o0 == null || o1 == null) return;
  final bagLines = [
    {'order_id': o0, 'product_id': p0},
    {'order_id': o1, 'product_id': p1},
  ];
  final jobs = <Future<HttpHit>>[
    c.checkoutBag(lines: bagLines, amount: 1),
    c.checkout(orderId: o0, productId: p0, amount: 1),
    c.checkoutBag(lines: bagLines, amount: 1),
    c.checkout(orderId: o0, productId: p0, amount: 1),
    c.checkout(orderId: o1, productId: p1, amount: 1),
    c.checkoutBag(lines: bagLines, amount: 1),
  ];
  final hits = await parallel(jobs);
  final r0 = await c.orderRow(o0);
  final r1 = await c.orderRow(o1);
  final sid0 = '${r0?['stripe_checkout_session_id'] ?? ''}';
  final sid1 = '${r1?['stripe_checkout_session_id'] ?? ''}';
  final okSids = hits
      .where((h) => h.ok)
      .map((h) => '${h.sessionId}|${h.amountTotal}|reused=${h.reused}')
      .toList();
  final distinctOk = hits
      .where((h) => h.ok && (h.sessionId ?? '').startsWith('cs_'))
      .map((h) => h.sessionId!)
      .toSet();

  c.note('BX2.bag+single', 'bag∥single mesma order', {
    'hits': hits.map((h) => h.brief).toList(),
    'ok': okSids,
    'distinct_ok_sids': distinctOk.toList(),
    'o0': {'sid': sid0, 'price_total': r0?['price_total'], 'contract': r0?['contract_unit_cents']},
    'o1': {'sid': sid1, 'price_total': r1?['price_total'], 'contract': r1?['contract_unit_cents']},
  }, lens: 'BX6');

  if (sid0.startsWith('cs_') && sid1.startsWith('cs_') && sid0 != sid1) {
    c.hold(
      id: 'RTBX-BX2-BAG-SINGLE-SPLIT',
      lens: 'BX2',
      severity: 'P1',
      title: 'Bag+single paralelo: as 2 linhas do saco ficaram com Session IDs diferentes',
      actor: 'buyer JWT',
      pre: '2 orders, 3 bag + 2 single o0 + 1 single o1 em paralelo',
      repro: 'Future.wait bag_checkout ∥ create-payment-intent single',
      expected: '1 Session no saco, ou single substitui e limpa a outra linha',
      obtained: {'o0': sid0, 'o1': sid1, 'hits': okSids},
    );
  } else if (distinctOk.length > 1) {
    c.hold(
      id: 'RTBX-BX2-BAG-SINGLE-DUAL-URL',
      lens: 'BX2',
      severity: 'P1',
      title: 'Bag+single paralelo devolveu mais do que 1 Checkout Session',
      actor: 'buyer JWT',
      pre: 'mesma order o0 no saco e no single',
      repro: '6 POST paralelos',
      expected: 'reuse/expire — 1 cs_ vivo',
      obtained: {'distinct': distinctOk.toList(), 'bd_o0': sid0, 'bd_o1': sid1},
    );
  } else {
    c.block('BX2.bag+single', 'BX2', 'bag∥single unificou Session', {
      'distinct_ok': distinctOk.length,
      'o0': sid0,
      'o1': sid1,
    });
  }
}

Future<void> bx2MetadataDrift(Rtbx c) async {
  final p0 = await c.createProduct(title: '$prefix-md0', price: 20, qty: 3);
  final p1 = await c.createProduct(title: '$prefix-md1', price: 8, qty: 3);
  final pCheap = await c.createProduct(title: '$prefix-mdc', price: 2, qty: 3);
  if (p0 == null || p1 == null || pCheap == null) return;
  final o0 = await c.insertOrder(productId: p0, jwt: c.buyerJwt, price: 20);
  final o1 = await c.insertOrder(productId: p1, jwt: c.buyerJwt, price: 8);
  if (o0 == null || o1 == null) return;

  final first = await c.checkoutBag(lines: [
    {'order_id': o0, 'product_id': p0},
    {'order_id': o1, 'product_id': p1},
  ], amount: 1);
  c.note('BX2.md.first', 'bag session inicial', first.brief, lens: 'BX2');
  final sid0 = first.sessionId;
  final amt0 = first.amountTotal;

  // Swap product_ids vs orders (client metadata lie).
  final swapped = await c.checkoutBag(lines: [
    {'order_id': o0, 'product_id': p1},
    {'order_id': o1, 'product_id': p0},
  ], amount: 1);
  if (swapped.ok) {
    c.hold(
      id: 'RTBX-BX2-META-SWAP-PID',
      lens: 'BX2',
      severity: 'P1',
      title: 'Checkout do saco aceitou product_id trocado vs order',
      actor: 'buyer JWT',
      pre: 'session já criada; bag_lines com product_ids invertidos',
      repro: 'POST bag_checkout product_id≠order.product_id',
      expected: 'Checkout blocked: bag product does not match order',
      obtained: swapped.brief,
    );
  } else {
    c.block('BX2.meta.swap', 'BX2', 'product_id trocado recusado', swapped.brief);
  }

  // Extra compact metadata keys after claim.
  final extraMeta = await c.checkoutBag(
    lines: [
      {'order_id': o0, 'product_id': p0},
      {'order_id': o1, 'product_id': p1},
    ],
    amount: 1,
    extra: {
      'bag_product_ids': '${pCheap.replaceAll('-', '')},${pCheap.replaceAll('-', '')}',
      'bag_order_ids': '${o0.replaceAll('-', '')}',
    },
  );
  c.note('BX2.md.extra', 'body bag_product_ids extra pós-claim', extraMeta.brief,
      lens: 'BX2');
  if (extraMeta.ok &&
      extraMeta.amountTotal != null &&
      amt0 != null &&
      extraMeta.amountTotal! < amt0 - 50) {
    c.hold(
      id: 'RTBX-BX2-META-DRIFT-UNDERPAY',
      lens: 'BX1',
      severity: 'P0',
      title: 'Metadata extra no body baixou o total após claim',
      actor: 'buyer JWT',
      pre: 'bag AB já com Session',
      repro: 'POST bag_checkout + bag_product_ids baratos no body',
      expected: 'ignorar metadata cliente; manter quote',
      obtained: {'first': amt0, 'drift': extraMeta.amountTotal, 'hit': extraMeta.brief},
    );
  } else if (extraMeta.ok) {
    c.block('BX2.meta.extra', 'BX2', 'metadata extra no body não baixou total', {
      'first': amt0,
      'again': extraMeta.amountTotal,
    });
  } else {
    c.block('BX2.meta.extra.deny', 'BX2', 'metadata extra recusada', extraMeta.brief);
  }

  // Buyer PATCH product_id after claim.
  final patchPid = await c.rest(
    'PATCH',
    'orders?id=eq.$o0',
    jwt: c.buyerJwt,
    body: {'product_id': pCheap},
  );
  c.note('BX2.md.patch_pid', 'buyer PATCH product_id pós-claim', patchPid.brief,
      lens: 'BX2');
  final afterPatch = await c.orderRow(o0);
  if (patchPid.ok &&
      patchPid.list.isNotEmpty &&
      '${afterPatch?['product_id']}' == pCheap) {
    c.hold(
      id: 'RTBX-BX2-META-PATCH-PID',
      lens: 'BX4',
      severity: 'P1',
      title: 'Buyer alterou product_id da order depois do claim da Session',
      actor: 'buyer JWT',
      pre: 'Session bag criada',
      repro: 'PATCH orders.product_id → SKU barato',
      expected: '0 linhas / imutável',
      obtained: {
        'patch': patchPid.brief,
        'product_id': afterPatch?['product_id'],
        'contract': afterPatch?['contract_unit_cents'],
      },
    );
  } else {
    c.block('BX2.meta.patch_pid', 'BX2', 'PATCH product_id pós-claim não pegou', {
      'status': patchPid.status,
      'rows': patchPid.list.length,
      'pid': afterPatch?['product_id'],
    });
  }

  // Catalog price drop after claim — contract should hold (K).
  final sealed = afterPatch?['contract_unit_cents'];
  await c.rest(
    'PATCH',
    'products?id=eq.$p0',
    jwt: c.sellerJwt,
    body: {'price': 1},
  );
  final afterDrop = await c.checkoutBag(lines: [
    {'order_id': o0, 'product_id': p0},
    {'order_id': o1, 'product_id': p1},
  ], amount: 1);
  c.note('BX2.md.price_drop', 'catálogo 20→1 € após claim', {
    'sealed': sealed,
    'hit': afterDrop.brief,
    'amt': afterDrop.amountTotal,
  }, lens: 'BX1');
  if (afterDrop.ok &&
      afterDrop.amountTotal != null &&
      afterDrop.amountTotal! < 1500) {
    c.hold(
      id: 'RTBX-BX2-META-CATALOG-DROP',
      lens: 'BX1',
      severity: 'P0',
      title: 'Após claim, baixar preço de catálogo reduziu a Session',
      actor: 'seller JWT price + buyer checkout',
      pre: 'contract selado; Session bag existente',
      repro: 'PATCH products.price=1; POST bag_checkout',
      expected: 'cobrar contrato selado (20 € + 8 €) ou recusar',
      obtained: {'sealed_o0': sealed, 'session': afterDrop.amountTotal},
    );
  } else {
    c.block('BX2.meta.catalog', 'BX1', 'drop de catálogo não reabriu contrato', {
      'sealed': sealed,
      'amt': afterDrop.amountTotal,
      'ok': afterDrop.ok,
    });
  }

  c.note('BX2.md.sid', 'sid inicial vs actual o0', {
    'first_sid': sid0,
    'now': (await c.orderRow(o0))?['stripe_checkout_session_id'],
  }, lens: 'BX2');
}

Future<void> bx1CurrencyZwj(Rtbx c) async {
  final p = await c.createProduct(title: '$prefix-ccy', price: 12, qty: 2);
  if (p == null) return;
  final o = await c.insertOrder(productId: p, jwt: c.buyerJwt, price: 12);
  if (o == null) return;
  const zwj = '\u200d';
  const zwnj = '\u200c';
  const bom = '\ufeff';
  const nbsp = '\u00a0';
  const cyrE = '\u0435'; // Cyrillic е
  final variants = <String, Object?>{
    'eur+zwj': 'eur$zwj',
    'zwj+eur': '${zwj}eur',
    'eu+zwj+r': 'eu${zwj}r',
    'eur+zwnj': 'eur$zwnj',
    'eur+bom': 'eur$bom',
    'bom+eur': '${bom}eur',
    'eur+nbsp': 'eur$nbsp',
    'cyr_eur': '${cyrE}ur',
    'EUR': 'EUR',
    'eur ': 'eur ',
    'usd': 'usd',
  };
  for (final e in variants.entries) {
    final hit = await c.checkout(
      orderId: o,
      productId: p,
      amount: 1,
      currency: e.value,
    );
    c.note('BX1.ccy.${e.key}', 'currency=${e.key}', hit.brief, lens: 'BX1');
    final under = hit.ok && (hit.amountTotal ?? 99999) < 500;
    if (under) {
      c.hold(
        id: 'RTBX-BX1-CCY-${e.key.toUpperCase()}',
        lens: 'BX1',
        severity: 'P0',
        title: 'Currency ${e.key} criou Session abaixo do contrato',
        actor: 'buyer JWT',
        pre: 'SKU 12 €',
        repro: 'POST create-payment-intent currency=${e.key}',
        expected: 'EUR quote ou recusa',
        obtained: hit.brief,
      );
    } else if (e.key == 'EUR' || e.key == 'eur ') {
      if (hit.ok) {
        c.block('BX1.ccy.${e.key}', 'BX1', 'EUR canónico aceite', hit.amountTotal);
      } else {
        c.note('BX1.ccy.${e.key}.deny', 'EUR canónico recusado', hit.brief, lens: 'BX1');
      }
    } else if (hit.ok) {
      // Non-eur accepted — only a finding if Stripe currency ≠ eur or underpay.
      c.note('BX1.ccy.${e.key}.ok', 'variante aceite (verificar se continua EUR)', {
        'amt': hit.amountTotal,
        'sid': hit.sessionId,
      }, lens: 'BX1');
      c.block('BX1.ccy.${e.key}.no_underpay', 'BX1',
          'variante ${e.key} não underpay', hit.amountTotal);
    } else {
      c.block('BX1.ccy.${e.key}', 'BX1', 'currency ${e.key} recusada', hit.brief);
    }
  }
}

Future<void> bx3OfferFreezeUnicode(Rtbx c) async {
  final p = await c.createProduct(title: '$prefix-off', price: 25, qty: 3);
  if (p == null) return;

  Future<HttpHit> ins(Object amount) {
    return c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
      'product_id': p,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'amount': amount,
      'offered_by': 'buyer',
      'status': 'pending',
    });
  }

  final zwjAmt = await ins('6\u200d');
  final fwAmt = await ins('６');
  final nbspAmt = await ins('6\u00a0');
  final legit = await ins(6);
  c.note('BX3.off.zwj', 'INSERT amount 6+ZWJ', zwjAmt.brief, lens: 'BX3');
  c.note('BX3.off.fw', 'INSERT amount fullwidth ６', fwAmt.brief, lens: 'BX3');
  c.note('BX3.off.nbsp', 'INSERT amount 6+NBSP', nbspAmt.brief, lens: 'BX3');
  c.note('BX3.off.legit', 'INSERT amount 6', legit.brief, lens: 'BX3');

  for (final hit in [zwjAmt, fwAmt, nbspAmt]) {
    if (hit.ok && hit.firstId != null) {
      c.createdOfferIds.add(hit.firstId!);
      final amt = numOf(hit.map?['amount']);
      if (amt != null && amt > 0 && amt < 1) {
        c.hold(
          id: 'RTBX-BX3-OFFER-UNICODE-TINY',
          lens: 'BX3',
          severity: 'P1',
          title: 'Oferta Unicode inseriu amount < 1 €',
          actor: 'buyer JWT',
          pre: 'SKU 25 €',
          repro: 'POST product_offers amount unicode',
          expected: 'rejeitar ou 6.00',
          obtained: hit.brief,
        );
      }
    } else {
      c.block('BX3.off.unicode.deny', 'BX3', 'amount unicode recusado', hit.brief);
    }
  }

  final offerId = legit.firstId;
  if (offerId == null) {
    c.skip('BX3.off.accept', 'BX3', 'oferta 6 € não inseriu', legit.brief);
    return;
  }
  c.createdOfferIds.add(offerId);
  final acc = await c.rest(
    'PATCH',
    'product_offers?id=eq.$offerId',
    jwt: c.sellerJwt,
    body: {'status': 'accepted'},
  );
  c.note('BX3.off.accept', 'seller accept', acc.brief, lens: 'BX3');

  final freezeZwj = await c.rest(
    'PATCH',
    'product_offers?id=eq.$offerId',
    jwt: c.buyerJwt,
    body: {'amount': '1\u200d'},
  );
  final freezeSeller = await c.rest(
    'PATCH',
    'product_offers?id=eq.$offerId',
    jwt: c.sellerJwt,
    body: {'amount': 1},
  );
  c.note('BX3.off.freeze.b', 'buyer PATCH amount unicode pós-accept', freezeZwj.brief,
      lens: 'BX3');
  c.note('BX3.off.freeze.s', 'seller PATCH amount=1 pós-accept', freezeSeller.brief,
      lens: 'BX3');

  final offRow = await c.rest(
    'GET',
    'product_offers?id=eq.$offerId&select=id,amount,status',
    service: true,
  );
  final frozenAmt = numOf(offRow.map?['amount']);
  if (frozenAmt != null && frozenAmt != 6) {
    c.hold(
      id: 'RTBX-BX3-OFFER-UNFREEZE',
      lens: 'BX3',
      severity: 'P1',
      title: 'Amount da oferta aceite foi alterado',
      actor: 'buyer/seller JWT',
      pre: 'oferta 6 € accepted',
      repro: 'PATCH amount unicode/1',
      expected: '6.00 imutável',
      obtained: offRow.brief,
    );
  } else {
    c.block('BX3.off.freeze', 'BX3', 'amount aceite imutável', offRow.brief);
  }

  final o = await c.insertOrder(
    productId: p,
    jwt: c.buyerJwt,
    price: 6,
    offerId: offerId,
  );
  if (o == null) {
    c.skip('BX3.off.order', 'BX3', 'order com oferta falhou', 'null');
    return;
  }
  final orow = await c.orderRow(o);
  final ck = await c.checkout(orderId: o, productId: p, amount: 1);
  c.note('BX3.off.checkout', 'checkout oferta selada', {
    'contract': orow?['contract_unit_cents'],
    'qty': orow?['contract_qty'],
    'hit': ck.brief,
    'amt': ck.amountTotal,
  }, lens: 'BX3');
  final contract = numOf(orow?['contract_unit_cents'])?.round() ?? 0;
  if (ck.ok && (ck.amountTotal ?? 0) > 0 && (ck.amountTotal ?? 0) < 400) {
    c.hold(
      id: 'RTBX-BX3-OFFER-CHECKOUT-UNDER',
      lens: 'BX3',
      severity: 'P0',
      title: 'Checkout da oferta selada cobrou abaixo do freeze',
      actor: 'buyer JWT',
      pre: 'oferta 6 € accepted, contract selado',
      repro: 'POST create-payment-intent',
      expected: '≥ 6 € + protecção',
      obtained: {'contract': contract, 'session': ck.amountTotal},
    );
  } else if (contract == 600 || (ck.ok && (ck.amountTotal ?? 0) >= 600)) {
    c.block('BX3.off.seal', 'BX3', 'oferta selada 6 € no contrato/session', {
      'contract': contract,
      'amt': ck.amountTotal,
    });
  }

  // qty>1 with offer should fail (closed class) — residual, do not count if blocked.
  final oQty = await c.insertOrder(
    productId: p,
    jwt: c.buyerJwt,
    price: 6,
    qty: 3,
    offerId: offerId,
  );
  if (oQty != null) {
    final qrow = await c.orderRow(oQty);
    final qck = await c.checkout(orderId: oQty, productId: p, amount: 1);
    c.note('BX3.off.qty3', 'oferta + qty=3 (residual, não contar se exacto)', {
      'oid': oQty,
      'contract_qty': qrow?['contract_qty'],
      'contract_unit': qrow?['contract_unit_cents'],
      'ck': qck.brief,
    }, lens: 'BX3');
  } else {
    c.block('BX3.off.qty3', 'BX3', 'order oferta qty=3 recusada', 'insert fail');
  }
}

Future<void> bx2SettleOrphanList(Rtbx c) async {
  final p0 = await c.createProduct(title: '$prefix-st0', price: 12, qty: 2);
  final p1 = await c.createProduct(title: '$prefix-st1', price: 12, qty: 2);
  if (p0 == null || p1 == null) return;
  final o0 = await c.insertOrder(productId: p0, jwt: c.buyerJwt, price: 12);
  final o1 = await c.insertOrder(productId: p1, jwt: c.buyerJwt, price: 12);
  if (o0 == null || o1 == null) return;
  final bag = await c.checkoutBag(lines: [
    {'order_id': o0, 'product_id': p0},
    {'order_id': o1, 'product_id': p1},
  ]);
  final sid = bag.sessionId ?? '';
  c.note('BX2.settle.bag', 'session para settle list', bag.brief, lens: 'BX2');

  final comma = await c.settleGet('$sid,cs_test_orphanlistbx001');
  final amp = await c.settleGet(sid, extraQs: 'session_id=cs_test_orphanlistbx002');
  final jsonish = await c.settleGet('["$sid"]');
  final spaced = await c.settleGet('$sid%20cs_test_orphan');
  final jwtE2e = await c.edge(
    'create-payment-intent',
    {
      'order_id': o0,
      'payment_intent_id': 'pi_test_orphan_bx',
      'session_id': sid,
      'bag_checkout': true,
      'bag_lines': [
        {'order_id': o0, 'product_id': p0},
        {'order_id': o1, 'product_id': p1},
      ],
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
    },
    jwt: c.buyerJwt,
    qs: 'fase2_e2e_settle=1',
  );

  c.note('BX2.settle.comma', 'GET session_id=cs,cs_orphan', comma.brief, lens: 'BX2');
  c.note('BX2.settle.amp', 'GET dois session_id', amp.brief, lens: 'BX2');
  c.note('BX2.settle.json', 'GET session_id JSON array', jsonish.brief, lens: 'BX2');
  c.note('BX2.settle.space', 'GET session_id com espaço', spaced.brief, lens: 'BX2');
  c.note('BX2.settle.e2e.jwt', 'fase2_e2e_settle JWT', jwtE2e.brief, lens: 'BX4');

  bool markedPago(HttpHit h) =>
      h.ok &&
      (h.body.toLowerCase().contains('"pago"') ||
          h.body.toLowerCase().contains('settled') ||
          h.body.toLowerCase().contains('já está pago'));

  final o0b = await c.orderRow(o0);
  final o1b = await c.orderRow(o1);
  final st0 = '${o0b?['status']}'.toLowerCase();
  final st1 = '${o1b?['status']}'.toLowerCase();

  if (st0 == 'pago' || st1 == 'pago') {
    c.hold(
      id: 'RTBX-BX2-SETTLE-ORPHAN-PAGO',
      lens: 'BX4',
      severity: 'P0',
      title: 'Settle com lista/órfão marcou order pago sem captura',
      actor: 'anon GET / buyer JWT e2e',
      pre: 'Session aberta não paga',
      repro: 'GET checkout_return=success session_id=lista; POST fase2 JWT',
      expected: 'não liquidar',
      obtained: {
        'o0': st0,
        'o1': st1,
        'comma': comma.brief,
        'e2e': jwtE2e.brief,
      },
    );
  } else {
    c.block('BX2.settle.no_pago', 'BX4', 'lista/órfão não liquidou orders', {
      'o0': st0,
      'o1': st1,
    });
  }

  if (jwtE2e.ok && jwtE2e.status != 401) {
    c.hold(
      id: 'RTBX-BX4-E2E-SETTLE-JWT',
      lens: 'BX4',
      severity: 'P1',
      title: 'fase2_e2e_settle aceitou JWT buyer (não service_role)',
      actor: 'buyer JWT',
      pre: 'settle E2E deveria ser service_role',
      repro: 'POST create-payment-intent?fase2_e2e_settle=1 JWT',
      expected: '401',
      obtained: jwtE2e.brief,
    );
  } else {
    c.block('BX4.e2e.jwt', 'BX4', 'e2e settle JWT recusado', jwtE2e.brief);
  }

  if (comma.ok && markedPago(comma)) {
    c.hold(
      id: 'RTBX-BX2-SETTLE-COMMA-OK',
      lens: 'BX2',
      severity: 'P1',
      title: 'GET settle com session_id em lista CSV devolveu sucesso',
      actor: 'anon GET',
      pre: 'session aberta + órfão CSV',
      repro: 'GET session_id=cs_real,cs_orphan',
      expected: '400/402',
      obtained: comma.brief,
    );
  } else {
    c.block('BX2.settle.comma', 'BX2', 'CSV session_id não settled', comma.brief);
  }

  // Paid bag then settle extra orphan order in e2e list (service_role = fixture observation).
  final paidBag = await c.e2e('setup_paid_bag', {
    'lines': [
      {'price': 10, 'qty': 1},
      {'price': 10, 'qty': 1},
    ],
  });
  c.note('BX8.paid_bag', 'setup_paid_bag', paidBag.brief, lens: 'BX8');
  final orphanOid = o0;
  final paidMap = paidBag.map ?? {};
  final paidLines = paidMap['orders'] ?? paidMap['bag_orders'] ?? paidMap['lines'];
  c.note('BX2.settle.paid_bag.shape', 'keys setup_paid_bag', paidMap.keys.toList(),
      lens: 'BX2');

  // Replay GET on a known paid session if present.
  final paidSid = '${paidMap['checkoutSessionId'] ?? paidMap['session_id'] ?? ''}';
  if (paidSid.startsWith('cs_')) {
    final replayList = await c.settleGet('$paidSid,cs_test_orphan_after_paid');
    c.note('BX2.settle.replay_list', 'GET paid+orphan CSV', replayList.brief, lens: 'BX2');
  }

  // Try e2e settle bag_lines including unpaid orphan (service_role — observatory).
  final pi = '${paidMap['payment_intent_id'] ?? paidMap['payment_intent'] ?? ''}';
  if (pi.startsWith('pi_')) {
    final extra = await c.edge(
      'create-payment-intent',
      {
        'payment_intent_id': pi,
        'session_id': paidSid,
        'bag_checkout': true,
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'bag_lines': [
          if (paidLines is List)
            ...paidLines.whereType<Map>().map((m) => {
                  'order_id': m['id'] ?? m['order_id'],
                }),
          {'order_id': orphanOid, 'product_id': p0},
        ],
      },
      service: true,
      qs: 'fase2_e2e_settle=1',
    );
    final orphanAfter = await c.orderRow(orphanOid);
    c.note('BX2.settle.e2e.extra', 'service_role bag_lines + órfão', {
      'hit': extra.brief,
      'orphan_status': orphanAfter?['status'],
      'orphan_paid': orphanAfter?['amount_paid_cents'],
    }, lens: 'BX4');
    if ('${orphanAfter?['status']}'.toLowerCase() == 'pago') {
      // service_role E2E is fixture authority — document as P2 hygiene of settle list
      // only if JWT could do it. JWT already tested. Mark P2: settle aplica PI a line extra.
      c.hold(
        id: 'RTBX-BX2-SETTLE-ORPHAN-LINE',
        lens: 'BX4',
        severity: 'P2',
        title: 'Settle bag aplicou PI pago a order órfã extra na lista',
        actor: 'service_role E2E (observatório; JWT já recusado)',
        pre: 'bag pago + order não paga no bag_lines',
        repro: 'POST fase2_e2e_settle bag_lines inclui órfão',
        expected: 'ignorar order que não está na Session',
        obtained: {
          'orphan': orphanAfter?['status'],
          'amount_paid_cents': orphanAfter?['amount_paid_cents'],
          'hit': extra.brief,
        },
      );
    } else {
      c.block('BX2.settle.orphan_line', 'BX4', 'órfão extra não liquidado', extra.brief);
    }
  }
}

Future<void> bx3BundlePartial(Rtbx c) async {
  final pA = await c.createProduct(title: '$prefix-ba', price: 20, qty: 2);
  final pB = await c.createProduct(title: '$prefix-bb', price: 4, qty: 2);
  final pC = await c.createProduct(title: '$prefix-bc', price: 4, qty: 2);
  if (pA == null || pB == null || pC == null) return;
  final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_ids': [pA, pB, pC],
    'status': 'pending',
  });
  final bid = bun.firstId;
  c.note('BX3.bun.ins', 'INSERT bundle', bun.brief, lens: 'BX3');
  if (bid == null) {
    c.skip('BX3.bun', 'BX3', 'bundle insert falhou', bun.brief);
    return;
  }
  c.createdBundleIds.add(bid);
  final acc = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.sellerJwt,
    body: {'status': 'accepted', 'discount_pct': 50, 'total_eur': 14},
  );
  c.note('BX3.bun.acc', 'seller accept+total_eur', acc.brief, lens: 'BX3');
  final onlyA = await c.insertOrder(
    productId: pA,
    jwt: c.buyerJwt,
    price: 20,
    bundleId: bid,
  );
  if (onlyA == null) {
    c.block('BX3.bun.partial.ins', 'BX3', 'order parcial do conjunto recusada', 'insert fail');
    return;
  }
  final ck = await c.checkoutBag(lines: [
    {'order_id': onlyA, 'product_id': pA},
  ], amount: 1);
  c.note('BX3.bun.ck', 'saco só com 1/3 do conjunto', ck.brief, lens: 'BX3');
  if (ck.ok && (ck.amountTotal ?? 0) > 0 && (ck.amountTotal ?? 9999) < 1800) {
    c.hold(
      id: 'RTBX-BX3-BUNDLE-PARTIAL',
      lens: 'BX3',
      severity: 'P0',
      title: 'Saco com 1 artigo do conjunto cobrou o desconto do conjunto',
      actor: 'buyer JWT',
      pre: 'bundle 3 SKUs accepted total_eur=14; saco só SKU 20 €',
      repro: 'POST bag_checkout 1 linha',
      expected: '20 € + protecção ou recusar saco incompleto',
      obtained: ck.brief,
    );
  } else {
    c.block('BX3.bun.partial', 'BX3', 'conjunto parcial não underpay', ck.brief);
  }
}

Future<void> bx4FsmPago(Rtbx c) async {
  final paid = await c.payToPago(lens: 'BX4', initialQty: 2);
  if (paid == null) {
    c.skip('BX4.fsm', 'BX4', 'sem order pago', 'null');
    return;
  }
  final ck = await c.checkout(orderId: paid.oid, productId: paid.pid, amount: 1);
  c.note('BX4.reopen', 'checkout order já pago', ck.brief, lens: 'BX4');
  if (ck.ok && ck.reused != true) {
    // New session on already-paid order.
    c.hold(
      id: 'RTBX-BX4-REOPEN-PAGO',
      lens: 'BX4',
      severity: 'P1',
      title: 'Checkout criou Session nova em order já pago',
      actor: 'buyer JWT',
      pre: 'order pago Stripe TEST',
      repro: 'POST create-payment-intent na order liquidada',
      expected: 'bloquear / already paid',
      obtained: ck.brief,
    );
  } else {
    c.block('BX4.reopen', 'BX4', 'order pago não reabriu checkout', ck.brief);
  }
}

Future<void> bx5StockAndCrossSeller(Rtbx c) async {
  final p = await c.createProduct(title: '$prefix-stk', price: 10, qty: 1);
  if (p == null) return;
  final o1 = await c.insertOrder(productId: p, jwt: c.buyerJwt, price: 10);
  final o2 = await c.insertOrder(
    productId: p,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    price: 10,
  );
  c.note('BX5.hold', '2 buyers stock=1', {'o1': o1, 'o2': o2}, lens: 'BX5');
  if (o1 != null && o2 != null) {
    c.hold(
      id: 'RTBX-BX5-DOUBLE-HOLD',
      lens: 'BX5',
      severity: 'P1',
      title: 'Stock=1 aceitou 2 holds (2 buyers)',
      actor: 'buyer + buyer2 JWT',
      pre: 'quantity=1',
      repro: '2 INSERT orders',
      expected: '2.º INSERT recusado',
      obtained: {'o1': o1, 'o2': o2},
    );
  } else {
    c.block('BX5.hold', 'BX5', '2.º hold stock=1 recusado', {'o1': o1, 'o2': o2});
  }

  final pMine = await c.createProduct(title: '$prefix-xs', price: 11, qty: 2);
  final pOther = await c.createProduct(
    title: '$prefix-xs2',
    price: 11,
    qty: 2,
    seller: c.seller2Id,
  );
  if (pMine == null || pOther == null) return;
  final om = await c.insertOrder(productId: pMine, jwt: c.buyerJwt, price: 11);
  final oo = await c.insertOrder(
    productId: pOther,
    jwt: c.buyerJwt,
    seller: c.seller2Id,
    price: 11,
  );
  if (om == null || oo == null) {
    c.note('BX5.xs.ins', 'cross-seller orders', {'om': om, 'oo': oo}, lens: 'BX5');
    if (oo == null) {
      c.block('BX5.xs.ins', 'BX7', 'order seller2 insert falhou ou ok', 'oo=null');
    }
    return;
  }
  final bag = await c.checkoutBag(lines: [
    {'order_id': om, 'product_id': pMine},
    {'order_id': oo, 'product_id': pOther},
  ]);
  if (bag.ok) {
    c.hold(
      id: 'RTBX-BX7-CROSS-SELLER-BAG',
      lens: 'BX7',
      severity: 'P1',
      title: 'Saco com dois vendedores criou Session',
      actor: 'buyer JWT',
      pre: 'S1 + S2 no mesmo bag_checkout',
      repro: 'POST bag_checkout 2 sellers',
      expected: 'recusar',
      obtained: bag.brief,
    );
  } else {
    c.block('BX7.xs.bag', 'BX7', 'saco cross-seller recusado', bag.brief);
  }
}
