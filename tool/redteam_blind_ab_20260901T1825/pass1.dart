/// RED TEAM CEGO AB pass1 — variantes novas pós-YZAA. Não corrige.
library;

import 'dart:io';

import '_rtab.dart';

Future<void> main() async {
  final c = Rtab.fromEnv(loadEnv());
  stdout.writeln('RTAB $stamp ${c.url}');
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('actors', 'login', {
    'buyer': c.buyerId,
    'seller': c.sellerId,
    'buyer2': c.buyer2Id,
    'seller2': c.seller2Id,
  });

  await lensAb1(c);
  await lensAb2(c);
  await lensAb3(c);
  await lensAb4(c);
  await lensAb5(c);
  await lensAb6(c);
  await lensAb7(c);
  await lensAb8(c);

  await dumpJson('${outDir()}/pass1.json', {
    'stamp': stamp,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
  });
  stdout.writeln(
    'DONE findings=${c.findings.length} blocked=${c.blocked.length} lenses=${c.lensesHit}',
  );
  await c.cleanup();
}

List<Map<String, Object?>> bagLines(List<({String oid, String pid})> rows) {
  return [
    for (final r in rows) {'order_id': r.oid, 'product_id': r.pid},
  ];
}

Future<void> lensAb1(Rtab c) async {
  // Variante: 2 orders qty=1 do MESMO SKU dentro de conjunto aceite de 2 SKUs distintos.
  final a = await c.createProduct(title: '$prefix ab1a', qty: 4, price: 11);
  final b = await c.createProduct(title: '$prefix ab1b', qty: 4, price: 22);
  if (a == null || b == null) return;
  await c.ensureChat(a);
  final bun = await c.createBundle(productIds: [a, b]);
  if (bun == null) return;
  final acc = await c.acceptBundle(bun);
  c.note('ab1.accept', 'accept 2-sku', acc.brief, lens: 'AB1');

  final oA = await c.insertOrder(
      productId: a, jwt: c.buyerJwt, qty: 1, bundleId: bun, price: 11);
  final oB = await c.insertOrder(
      productId: b, jwt: c.buyerJwt, qty: 1, bundleId: bun, price: 22);
  final oA2 = await c.insertOrder(
      productId: a, jwt: c.buyerJwt, qty: 1, bundleId: bun, price: 11);
  c.note('ab1.dupsku', '2ª order mesmo SKU no conjunto aceite', {
    'oA': oA,
    'oB': oB,
    'oA2': oA2,
    'oA2row': oA2 == null ? null : await c.orderRow(oA2),
  }, lens: 'AB1');

  if (oA != null && oB != null && oA2 != null) {
    final q = await c.checkoutBag(lines: bagLines([
      (oid: oA, pid: a),
      (oid: oB, pid: b),
      (oid: oA2, pid: a),
    ]));
    final bunRow = await c.bundleRow(bun);
    final total = numOf(bunRow?['total_eur']);
    if (q.ok) {
      c.hold(
        id: 'RTAB-AB1-dup-sku-bag',
        lens: 'AB1',
        severity: 'P0',
        title: 'Saco com 2 linhas do mesmo SKU num conjunto aceite cria Session',
        actor: 'buyer JWT',
        pre: 'conjunto aceite [A,B]; orders A,B + A extra qty=1',
        repro: 'bag_checkout 3 linhas (A,B,A) após accept',
        expected: 'recusar (qty efectiva 2 no SKU A, ou bag ≠ product_ids)',
        obtained: q.brief,
        evidence: {
          'server_amount_cents': q.serverAmount,
          'bundle_total_eur': total,
          'session': q.checkoutSessionId,
        },
      );
    } else {
      c.closedPath('AB1.dup_sku', 'saco SKU duplicado recusado', q, lens: 'AB1');
    }
  }

  // Variante: qty=2 com bundle AINDA pending, depois accept.
  final cSku = await c.createProduct(title: '$prefix ab1c', qty: 5, price: 15);
  final dSku = await c.createProduct(title: '$prefix ab1d', qty: 5, price: 18);
  if (cSku == null || dSku == null) return;
  final bunP = await c.createBundle(productIds: [cSku, dSku]);
  if (bunP == null) return;
  final oC2 = await c.insertOrder(
      productId: cSku, jwt: c.buyerJwt, qty: 2, bundleId: bunP, price: 15);
  c.note('ab1.pending_qty2', 'qty=2 em bundle pending', {
    'oid': oC2,
    'row': oC2 == null ? null : await c.orderRow(oC2),
  }, lens: 'AB1');
  final accP = await c.acceptBundle(bunP);
  c.note('ab1.accept_after_qty2', 'accept após qty=2', accP.brief, lens: 'AB1');
  if (oC2 != null) {
    final oD = await c.insertOrder(
        productId: dSku, jwt: c.buyerJwt, qty: 1, bundleId: bunP, price: 18);
    final q2 = await c.checkoutBag(lines: [
      {'order_id': oC2, 'product_id': cSku, 'quantity': 2},
      if (oD != null) {'order_id': oD, 'product_id': dSku, 'quantity': 1},
    ]);
    final rowC = await c.orderRow(oC2);
    if (q2.ok && (numOf(rowC?['quantity']) ?? 0) > 1) {
      c.hold(
        id: 'RTAB-AB1-qty2-then-accept',
        lens: 'AB1',
        severity: 'P0',
        title: 'qty=2 selada em pending sobrevive ao accept e gera Session',
        actor: 'buyer JWT',
        pre: 'INSERT qty=2 + bundle pending → seller accept',
        repro: 'bag checkout das linhas após accept',
        expected: 'qty=1 no conjunto aceite / recusar checkout',
        obtained: {
          'checkout': q2.brief,
          'qty': rowC?['quantity'],
          'contract_qty': rowC?['contract_qty'],
          'amount': q2.serverAmount,
        },
      );
    } else if (q2.ok) {
      c.note('ab1.qty2_ok_but_qty1', 'session mas qty já 1', q2.brief, lens: 'AB1');
    } else {
      c.closedPath('AB1.qty2_accept', 'qty=2+accept não abre checkout', q2,
          lens: 'AB1');
    }
  }

  // bag_lines.quantity hostil (body) vs order qty=1
  if (oA != null && oB != null) {
    final qBody = await c.checkoutBag(lines: [
      {'order_id': oA, 'product_id': a, 'quantity': 7},
      {'order_id': oB, 'product_id': b, 'quantity': 7},
    ]);
    if (qBody.ok) {
      final bunRow = await c.bundleRow(bun);
      final expectedMin = ((numOf(bunRow?['total_eur']) ?? 0) * 100).round();
      c.note('ab1.body_qty7', 'body qty=7 ignorado?', {
        'amount': qBody.serverAmount,
        'bundle_cents': expectedMin,
        'reused': qBody.map?['reused_session'],
      }, lens: 'AB1');
      final amt = qBody.serverAmount ?? 0;
      if (amt > expectedMin + 400 && expectedMin > 0) {
        c.hold(
          id: 'RTAB-AB1-body-qty7',
          lens: 'AB1',
          severity: 'P1',
          title: 'bag_lines.quantity=7 inflaciona o total',
          actor: 'buyer JWT',
          pre: 'orders qty=1, body quantity=7',
          repro: 'bag_checkout quantity=7 nas lines',
          expected: 'qty autoritativa da order (=1) / total conjunto',
          obtained: qBody.brief,
        );
      } else {
        c.closedPath('AB1.body_qty7', 'body qty não manda no total', qBody,
            lens: 'AB1');
      }
    } else {
      c.closedPath('AB1.body_qty7_block', 'body qty=7 recusado', qBody, lens: 'AB1');
    }
  }

  // INSERT qty=0 / frac / negativo
  final z = await c.createProduct(title: '$prefix ab1z', qty: 3, price: 9);
  if (z != null) {
    for (final qv in [0, -1]) {
      final oid = await c.insertOrder(
          productId: z, jwt: c.buyerJwt, qty: qv, price: 9);
      if (oid != null) {
        final row = await c.orderRow(oid);
        final stored = numOf(row?['quantity']) ?? 0;
        if (stored != 1 && stored < 1) {
          c.hold(
            id: 'RTAB-AB1-qty-$qv',
            lens: 'AB1',
            severity: 'P2',
            title: 'Hold aceita quantity=$qv',
            actor: 'buyer JWT',
            pre: 'SKU qty=3',
            repro: 'POST orders quantity=$qv',
            expected: 'recusar ou forçar ≥1',
            obtained: row,
          );
        } else {
          c.closedPath('AB1.qty_$qv', 'quantity=$qv normalizado/recusado', row,
              lens: 'AB1');
        }
      } else {
        c.closedPath('AB1.qty_$qv', 'quantity=$qv recusado', 'no row', lens: 'AB1');
      }
    }
  }
}

Future<void> lensAb2(Rtab c) async {
  final a = await c.createProduct(title: '$prefix ab2a', qty: 3, price: 14);
  final b = await c.createProduct(title: '$prefix ab2b', qty: 3, price: 16);
  if (a == null || b == null) return;
  await c.ensureChat(a);
  await c.ensureChat(a, buyer: c.buyer2Id);

  final bunB1 = await c.createBundle(productIds: [a, b]);
  final bunB2 = await c.createBundle(
      productIds: [a, b], buyer: c.buyer2Id, jwt: c.buyer2Jwt);
  if (bunB1 == null || bunB2 == null) return;
  await c.acceptBundle(bunB1);
  await c.acceptBundle(bunB2);

  final o1a = await c.insertOrder(
      productId: a, jwt: c.buyerJwt, qty: 1, bundleId: bunB1, price: 14);
  final o1b = await c.insertOrder(
      productId: b, jwt: c.buyerJwt, qty: 1, bundleId: bunB1, price: 16);

  // Variante nova: B2 faz bag checkout com order_ids do B1 (sem PATCH bundle_id).
  if (o1a != null && o1b != null) {
    final q = await c.checkoutBag(
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
      lines: bagLines([(oid: o1a, pid: a), (oid: o1b, pid: b)]),
    );
    if (q.ok) {
      c.hold(
        id: 'RTAB-AB2-b2-checkout-b1-bag',
        lens: 'AB2',
        severity: 'P0',
        title: 'B2 abre Checkout no saco do B1',
        actor: 'buyer2 JWT',
        pre: 'orders B1 + conjunto aceite B1',
        repro: 'create-payment-intent bag_lines=orders B1, JWT B2',
        expected: 'recusar (order does not belong to buyer)',
        obtained: q.brief,
      );
    } else {
      c.closedPath('AB2.b2_bag_b1', 'B2 não checkout saco B1', q, lens: 'AB2');
    }
  }

  // INSERT B1 order com bundle_id do B2
  final stealIns = await c.insertOrder(
      productId: a, jwt: c.buyerJwt, qty: 1, bundleId: bunB2, price: 14);
  if (stealIns != null) {
    final row = await c.orderRow(stealIns);
    if (row?['bundle_id']?.toString() == bunB2) {
      c.hold(
        id: 'RTAB-AB2-insert-alien-bundle',
        lens: 'AB2',
        severity: 'P0',
        title: 'B1 INSERT order com bundle_id do B2',
        actor: 'buyer JWT',
        pre: 'conjunto aceite buyer=B2',
        repro: 'POST orders bundle_id=<bundle B2>',
        expected: 'order_bundle_buyer_mismatch',
        obtained: row,
      );
    } else {
      c.closedPath('AB2.insert_alien', 'INSERT bundle alheio não colou', row,
          lens: 'AB2');
    }
  } else {
    c.closedPath('AB2.insert_alien', 'INSERT bundle B2 recusado', 'no row',
        lens: 'AB2');
  }

  // Trocar buyer_id do conjunto aceite
  final stealBuyer = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bunB1',
    jwt: c.buyerJwt,
    body: {'buyer_id': c.buyer2Id},
  );
  final after = await c.bundleRow(bunB1);
  if (after?['buyer_id']?.toString() == c.buyer2Id) {
    c.hold(
      id: 'RTAB-AB2-bundle-buyer-swap',
      lens: 'AB2',
      severity: 'P0',
      title: 'JWT troca product_bundles.buyer_id após accept',
      actor: 'buyer JWT',
      pre: 'conjunto aceite buyer=B1',
      repro: 'PATCH product_bundles.buyer_id=B2',
      expected: 'buyer_id imutável',
      obtained: {'patch': stealBuyer.brief, 'row': after},
    );
  } else {
    c.closedPath('AB2.buyer_swap', 'buyer_id do conjunto congelado', {
      'patch': stealBuyer.brief,
      'buyer': after?['buyer_id'],
    }, lens: 'AB2');
  }

  // Seller INSERT order em nome do B1 com bundle B1 (ghost attach)
  final ghost = await c.insertOrder(
    productId: a,
    jwt: c.sellerJwt,
    buyer: c.buyerId,
    qty: 1,
    bundleId: bunB1,
    price: 14,
  );
  c.note('ab2.seller_insert_as_b1', 'seller INSERT order buyer=B1', {
    'oid': ghost,
    'row': ghost == null ? null : await c.orderRow(ghost),
  }, lens: 'AB2');

  // Anon
  final anonAtt = await c.rest('PATCH', 'orders?id=eq.${o1a ?? 'x'}', body: {
    'bundle_id': bunB2,
  });
  c.closedPath('AB2.anon_patch', 'anon PATCH bundle', anonAtt, lens: 'AB2');
}

Future<void> lensAb3(Rtab c) async {
  final a = await c.createProduct(title: '$prefix ab3a', qty: 5, price: 20);
  final b = await c.createProduct(title: '$prefix ab3b', qty: 5, price: 24);
  final e = await c.createProduct(title: '$prefix ab3e', qty: 5, price: 40);
  if (a == null || b == null || e == null) return;

  final oA = await c.insertOrder(productId: a, jwt: c.buyerJwt, qty: 1, price: 20);
  final oB = await c.insertOrder(productId: b, jwt: c.buyerJwt, qty: 1, price: 24);
  final oE = await c.insertOrder(productId: e, jwt: c.buyerJwt, qty: 1, price: 40);
  if (oA == null || oB == null || oE == null) return;

  // 1) Session saco 2 itens
  final q2 = await c.checkoutBag(lines: bagLines([
    (oid: oA, pid: a),
    (oid: oB, pid: b),
  ]));
  c.note('ab3.bag2', 'saco 2 itens', {
    'amount': q2.serverAmount,
    'sid': q2.checkoutSessionId,
    'reused': qBodyFlag(q2),
  }, lens: 'AB3');

  // 2) Variante nova: reusar session do saco 2 ao pedir saco 3 (SKU extra caro)
  //    — Edge bag reuse NÃO compara amount_total.
  final q3 = await c.checkoutBag(lines: bagLines([
    (oid: oA, pid: a),
    (oid: oB, pid: b),
    (oid: oE, pid: e),
  ]));
  c.note('ab3.bag3_overlap', 'saco 3 sobreposto ao 2', {
    'amount': q3.serverAmount,
    'sid': q3.checkoutSessionId,
    'sid2': q2.checkoutSessionId,
    'reused': q3.map?['reused_session'],
    'ok': q3.ok,
    'brief': q3.brief,
  }, lens: 'AB3');

  if (q2.ok && q3.ok) {
    final sid2 = q2.checkoutSessionId;
    final sid3 = q3.checkoutSessionId;
    final amt2 = q2.serverAmount ?? 0;
    final amt3 = q3.serverAmount ?? 0;
    final reusedSame = sid2 != null && sid2 == sid3;
    if (reusedSame && amt2 > 0 && amt3 == amt2) {
      c.hold(
        id: 'RTAB-AB3-bag-reuse-no-amount',
        lens: 'AB3',
        severity: 'P1',
        title: 'Saco 3 SKUs reutiliza Session do saco 2 sem comparar amount_total',
        actor: 'buyer JWT',
        pre: 'Session aberta no saco A+B; 2º POST com A+B+E',
        repro: 'bag checkout 2 linhas → bag checkout 3 linhas (overlap)',
        expected: 'nova Session com total dos 3 SKUs, ou recusar misturar',
        obtained: {
          'sid2': sid2,
          'sid3': sid3,
          'amt2': amt2,
          'amt3': amt3,
          'reused_session': q3.map?['reused_session'],
        },
      );
    } else if (reusedSame && amt3 != amt2) {
      c.note('ab3.reuse_diff_amt_in_json', 'mesmo sid mas json amount mudou', {
        'amt2': amt2,
        'amt3': amt3,
      }, lens: 'AB3');
    } else if (!reusedSame && q3.ok && amt3 > amt2) {
      c.closedPath('AB3.bag3_new_session', 'saco 3 criou Session nova', q3,
          lens: 'AB3');
    }
  }

  // currency=usd / jpy (variante nova vs reuse montante)
  final oCur = await c.insertOrder(
      productId: a, jwt: c.buyerJwt, qty: 1, price: 20);
  if (oCur != null) {
    final usd = await c.checkout(
      orderId: oCur,
      currency: 'usd',
      amount: 50,
    );
    c.note('ab3.usd', 'currency=usd', usd.brief, lens: 'AB3');
    if (usd.ok && usd.checkoutUrl != null) {
      final html = await c.peekCheckoutPage(usd.checkoutUrl!);
      final hints = c.currencyHints(html);
      c.note('ab3.usd.page', 'peek Stripe page', hints, lens: 'AB3');
      final pageSaysUsd = hints['has_usd'] == true && hints['has_eur'] != true;
      if (pageSaysUsd || html.toLowerCase().contains('"usd"')) {
        c.hold(
          id: 'RTAB-AB3-currency-usd',
          lens: 'AB3',
          severity: 'P0',
          title: 'Checkout Session criada em USD (não EUR)',
          actor: 'buyer JWT',
          pre: 'order marketplace EUR selada',
          repro: 'POST create-payment-intent currency=usd',
          expected: 'forçar eur / recusar currency',
          obtained: {
            'edge': usd.brief,
            'amount': usd.serverAmount,
            'hints': hints,
          },
        );
      } else {
        c.closedPath('AB3.usd_page_eur', 'página Stripe não prova USD', hints,
            lens: 'AB3');
      }
    } else if (usd.ok) {
      c.hold(
        id: 'RTAB-AB3-currency-usd-session',
        lens: 'AB3',
        severity: 'P1',
        title: 'Edge aceita currency=usd e devolve Session',
        actor: 'buyer JWT',
        pre: 'order EUR',
        repro: 'currency=usd',
        expected: 'recusar ou ignorar e forçar eur (prova na Session)',
        obtained: usd.brief,
        proven: false,
      );
    } else {
      c.closedPath('AB3.usd', 'currency=usd recusado', usd, lens: 'AB3');
    }

    final jpy = await c.checkout(orderId: oCur, currency: 'jpy', amount: 50);
    c.note('ab3.jpy', 'currency=jpy', jpy.brief, lens: 'AB3');
    if (jpy.ok) {
      c.hold(
        id: 'RTAB-AB3-currency-jpy',
        lens: 'AB3',
        severity: 'P0',
        title: 'Checkout Session aceite com currency=jpy (zero-decimal)',
        actor: 'buyer JWT',
        pre: 'order EUR',
        repro: 'POST create-payment-intent currency=jpy',
        expected: 'recusar',
        obtained: jpy.brief,
      );
    } else {
      c.closedPath('AB3.jpy', 'currency=jpy recusado', jpy, lens: 'AB3');
    }
  }

  // seller JWT checkout
  final sellerCk = await c.checkout(
    orderId: oA,
    jwt: c.sellerJwt,
    buyer: c.sellerId,
  );
  if (sellerCk.ok) {
    c.hold(
      id: 'RTAB-AB3-seller-checkout',
      lens: 'AB3',
      severity: 'P0',
      title: 'Seller JWT cria Checkout da order do buyer',
      actor: 'seller JWT',
      pre: 'order B1',
      repro: 'create-payment-intent JWT seller buyer_id=seller',
      expected: 'Invalid checkout user / order not belong',
      obtained: sellerCk.brief,
    );
  } else {
    c.closedPath('AB3.seller_ck', 'seller não checkout order B1', sellerCk,
        lens: 'AB3');
  }

  // anon
  final anonCk = await c.edge('create-payment-intent', {
    'buyer_id': c.buyerId,
    'order_id': oA,
    'amount': 50,
    'shipping_method': 'mao',
  });
  c.closedPath('AB3.anon', 'anon checkout', anonCk, lens: 'AB3');
}

Object? qBodyFlag(HttpHit h) => h.map?['reused_session'];

Future<void> lensAb4(Rtab c) async {
  final paid = await c.payToPago(lens: 'AB4', initialQty: 2);
  if (paid == null) {
    c.note('ab4.no_paid', 'setup_paid_order falhou', 'skip', lens: 'AB4');
    return;
  }
  final oid = paid.oid;
  final before = await c.orderRow(oid);
  c.note('ab4.paid_row', 'order capturada', {
    'status': before?['status'],
    'pi': before?['stripe_payment_intent_id'],
    'paid_cents': before?['amount_paid_cents'],
  }, lens: 'AB4');

  // Variante: aliases de estado (não hop directo pago→RP)
  for (final st in [
    'pendente',
    'Paid',
    'capturado',
    'complete',
    'aguarda_pagamento',
    'pedido_devolucao',
    'cancelado',
  ]) {
    final p = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
      'status': st,
    });
    final row = await c.orderRow(oid);
    c.note('ab4.alias.$st', 'buyer PATCH status=$st', {
      'patch': p.brief,
      'status': row?['status'],
    }, lens: 'AB4');
  }

  final afterAliases = await c.orderRow(oid);
  final stNow = '${afterAliases?['status']}'.toLowerCase();
  if (stNow.contains('reserva') ||
      stNow == 'pendente' ||
      stNow == 'aguarda_pagamento' ||
      stNow == 'aguardapagamento') {
    c.hold(
      id: 'RTAB-AB4-alias-reopen',
      lens: 'AB4',
      severity: 'P0',
      title: 'Estado capturado reaberto via alias ($stNow)',
      actor: 'buyer JWT',
      pre: 'order Stripe TEST pago',
      repro: 'PATCH status aliases (pendente/Paid/capturado/…)',
      expected: 'permanecer pago/enviado/…',
      obtained: afterAliases,
    );
  }

  // 2ª Checkout após captura (não hop RP exact — tenta directo no estado actual)
  final q = await c.checkout(orderId: oid);
  if (q.ok) {
    c.hold(
      id: 'RTAB-AB4-second-checkout-captured',
      lens: 'AB4',
      severity: 'P0',
      title: '2ª Checkout Session com order já capturada',
      actor: 'buyer JWT',
      pre: 'setup_paid_order Stripe TEST',
      repro: 'create-payment-intent na order paga (status actual)',
      expected: 'Checkout blocked: already captured',
      obtained: {
        'checkout': q.brief,
        'status': (await c.orderRow(oid))?['status'],
      },
    );
  } else {
    c.closedPath('AB4.captured_checkout', 'capturado bloqueia 2ª Session', q,
        lens: 'AB4');
  }

  // Seller hop enviado → reserva_pendente
  final env = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
    'status': 'enviado',
  });
  final back = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
    'status': 'reserva_pendente',
  });
  final row2 = await c.orderRow(oid);
  c.note('ab4.ship_hop', 'enviado→RP', {
    'env': env.brief,
    'back': back.brief,
    'status': row2?['status'],
  }, lens: 'AB4');
  if ('${row2?['status']}'.toLowerCase().contains('reserva')) {
    c.hold(
      id: 'RTAB-AB4-ship-to-hold',
      lens: 'AB4',
      severity: 'P0',
      title: 'Seller reabre hold após enviado',
      actor: 'seller JWT',
      pre: 'order paga',
      repro: 'PATCH enviado → reserva_pendente',
      expected: 'bloquear',
      obtained: row2,
    );
  } else {
    c.closedPath('AB4.ship_rp', 'enviado não volta a hold', row2, lens: 'AB4');
  }

  // premio_rifa INSERT (alias de estado na criação)
  final sku = await c.createProduct(title: '$prefix ab4prize', qty: 2, price: 30);
  if (sku != null) {
    final prize = await c.insertOrder(
      productId: sku,
      jwt: c.buyerJwt,
      qty: 1,
      status: 'premio_rifa',
      price: 30,
    );
    final prow = prize == null ? null : await c.orderRow(prize);
    c.note('ab4.premio_insert', 'INSERT status=premio_rifa', {
      'oid': prize,
      'status': prow?['status'],
    }, lens: 'AB4');
    if (prize != null && prow != null && '${prow['status']}' == 'premio_rifa') {
      final pq = await c.checkout(orderId: prize, prize: true);
      c.note('ab4.premio_checkout', 'prize_shipping em falso prémio', pq.brief,
          lens: 'AB4');
      if (pq.ok) {
        final amt = pq.serverAmount ?? 0;
        if (amt < 2000) {
          c.hold(
            id: 'RTAB-AB4-fake-prize-shipping',
            lens: 'AB4',
            severity: 'P0',
            title: 'INSERT premio_rifa + prize_shipping cobra só portes',
            actor: 'buyer JWT',
            pre: 'SKU 30€ sem rifa',
            repro: 'POST orders status=premio_rifa → checkout prize_shipping',
            expected: 'recusar / cobra 30€+taxas',
            obtained: pq.brief,
          );
        }
      }
    } else {
      c.closedPath('AB4.premio_insert', 'premio_rifa revertido no INSERT', prow,
          lens: 'AB4');
    }
  }
}

Future<void> lensAb5(Rtab c) async {
  final sku = await c.createProduct(title: '$prefix ab5', qty: 1, price: 12);
  if (sku == null) return;
  final o1 = await c.insertOrder(productId: sku, jwt: c.buyerJwt, qty: 1, price: 12);
  // Inflate: seller sobe quantity com hold activo
  final inf = await c.rest('PATCH', 'products?id=eq.$sku', jwt: c.sellerJwt, body: {
    'quantity': 9,
  });
  final prow = await c.productRow(sku);
  c.note('ab5.inflate', 'seller PATCH quantity=9 com hold', {
    'patch': inf.brief,
    'qty': prow?['quantity'],
    'hold': o1,
  }, lens: 'AB5');

  final o2 = await c.insertOrder(
      productId: sku, jwt: c.buyer2Jwt, buyer: c.buyer2Id, qty: 1, price: 12);
  c.note('ab5.second_hold', 'B2 hold após inflate', {
    'oid': o2,
    'row': o2 == null ? null : await c.orderRow(o2),
  }, lens: 'AB5');

  if (o1 != null && o2 != null) {
    final q1 = await c.checkout(orderId: o1);
    final q2 = await c.checkout(
        orderId: o2, jwt: c.buyer2Jwt, buyer: c.buyer2Id);
    c.note('ab5.two_checkouts', '2 Sessions stock original=1', {
      'q1': q1.brief,
      'q2': q2.brief,
    }, lens: 'AB5');
    if (q1.ok && q2.ok) {
      c.hold(
        id: 'RTAB-AB5-inflate-two-sessions',
        lens: 'AB5',
        severity: 'P1',
        title: 'Seller infla stock=1→9 e dois buyers abrem Checkout',
        actor: 'seller JWT + B1/B2',
        pre: 'SKU quantity=1, hold B1, PATCH quantity=9, hold B2',
        repro: 'checkout B1 e B2 em paralelo lógico',
        expected: 'quantity não sobe acima do hold, ou 2º checkout recusado',
        obtained: {
          'product': prow,
          'q1': q1.checkoutSessionId,
          'q2': q2.checkoutSessionId,
        },
      );
    } else {
      c.closedPath('AB5.two_ck', 'inflate não deu 2 Sessions', {
        'q1': q1.brief,
        'q2': q2.brief,
      }, lens: 'AB5');
    }
  }

  // Ghost hold: seller INSERT order em nome B1
  final sku2 = await c.createProduct(title: '$prefix ab5g', qty: 1, price: 13);
  if (sku2 != null) {
    final ghost = await c.insertOrder(
      productId: sku2,
      jwt: c.sellerJwt,
      buyer: c.buyerId,
      qty: 1,
      price: 13,
    );
    final b2try = await c.insertOrder(
      productId: sku2,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
      qty: 1,
      price: 13,
    );
    c.note('ab5.ghost', 'seller hold em nome B1 vs B2', {
      'ghost': ghost,
      'b2': b2try,
    }, lens: 'AB5');
    if (ghost != null && b2try == null) {
      c.hold(
        id: 'RTAB-AB5-seller-ghost-hold',
        lens: 'AB5',
        severity: 'P2',
        title: 'Seller cria hold em nome do buyer e trava stock=1',
        actor: 'seller JWT',
        pre: 'SKU qty=1',
        repro: 'POST orders seller JWT buyer_id=B1 → B2 não consegue hold',
        expected: 'seller não INSERT order com buyer alheio, ou não consome hold',
        obtained: {'ghost': ghost, 'b2': 'blocked'},
      );
    }
  }

  // Conjunto aceite + hold extra do mesmo SKU (sem 3+1 exact: 2-SKU bundle + 3ª order mesmo A)
  final x = await c.createProduct(title: '$prefix ab5x', qty: 3, price: 10);
  final y = await c.createProduct(title: '$prefix ab5y', qty: 3, price: 11);
  if (x != null && y != null) {
    final bun = await c.createBundle(productIds: [x, y]);
    if (bun != null) {
      await c.acceptBundle(bun);
      final ox = await c.insertOrder(
          productId: x, jwt: c.buyerJwt, qty: 1, bundleId: bun, price: 10);
      final oy = await c.insertOrder(
          productId: y, jwt: c.buyerJwt, qty: 1, bundleId: bun, price: 11);
      final extra = await c.insertOrder(
          productId: x, jwt: c.buyer2Jwt, buyer: c.buyer2Id, qty: 1, price: 10);
      c.note('ab5.bundle_plus_b2', 'hold B2 no SKU do conjunto B1', {
        'ox': ox,
        'oy': oy,
        'extra': extra,
        'prod': await c.productRow(x),
      }, lens: 'AB5');
    }
  }
}

Future<void> lensAb6(Rtab c) async {
  final sku = await c.createProduct(title: '$prefix ab6', qty: 2, price: 19);
  if (sku == null) return;
  final o = await c.insertOrder(productId: sku, jwt: c.buyerJwt, qty: 1, price: 19);
  if (o == null) return;

  final hits = await parallel([
    c.checkout(orderId: o, amount: 50),
    c.checkout(orderId: o, amount: 50),
  ]);
  final sids = hits.map((h) => h.checkoutSessionId).whereType<String>().toSet();
  c.note('ab6.race2', 'Future.wait 2× checkout mesma order', {
    'h0': hits[0].brief,
    'h1': hits[1].brief,
    'unique_sids': sids.length,
  }, lens: 'AB6');
  if (hits.every((h) => h.ok) && sids.length >= 2) {
    c.hold(
      id: 'RTAB-AB6-dual-session',
      lens: 'AB6',
      severity: 'P0',
      title: 'Future.wait 2× checkout cria 2 Sessions',
      actor: 'buyer JWT',
      pre: '1 order RP',
      repro: 'Future.wait 2 POST create-payment-intent',
      expected: '1 Session (claim)',
      obtained: {
        'sids': sids.toList(),
        'amt0': hits[0].serverAmount,
        'amt1': hits[1].serverAmount,
      },
    );
  } else {
    c.closedPath('AB6.dual', 'race 2× não gerou 2 cs_', {
      'sids': sids.toList(),
      'ok': hits.map((h) => h.ok).toList(),
    }, lens: 'AB6');
  }

  // stock=1 dois buyers
  final sku1 = await c.createProduct(title: '$prefix ab6s', qty: 1, price: 21);
  if (sku1 == null) return;
  final oB1 = await c.insertOrder(
      productId: sku1, jwt: c.buyerJwt, qty: 1, price: 21);
  final oB2 = await c.insertOrder(
      productId: sku1, jwt: c.buyer2Jwt, buyer: c.buyer2Id, qty: 1, price: 21);
  c.note('ab6.stock1_holds', '2 holds stock=1', {'b1': oB1, 'b2': oB2},
      lens: 'AB6');
  if (oB1 != null && oB2 != null) {
    final race = await parallel([
      c.checkout(orderId: oB1),
      c.checkout(orderId: oB2, jwt: c.buyer2Jwt, buyer: c.buyer2Id),
    ]);
    if (race.every((h) => h.ok)) {
      c.hold(
        id: 'RTAB-AB6-stock1-two-checkouts',
        lens: 'AB6',
        severity: 'P0',
        title: 'stock=1 duas holds e duas Sessions',
        actor: 'B1+B2 JWT',
        pre: 'SKU qty=1, 2 orders inseridas',
        repro: 'Future.wait checkout B1 e B2',
        expected: '2º hold ou 2º checkout recusado',
        obtained: {
          'h0': race[0].brief,
          'h1': race[1].brief,
        },
      );
    } else {
      c.closedPath('AB6.stock1', 'stock=1 não deu 2 Sessions', {
        'h0': race[0].brief,
        'h1': race[1].brief,
        'oB2': oB2,
      }, lens: 'AB6');
    }
  } else {
    c.closedPath('AB6.stock1_hold', '2º hold stock=1 recusado', {'b1': oB1, 'b2': oB2},
        lens: 'AB6');
  }
}

Future<void> lensAb7(Rtab c) async {
  final s1 = await c.createProduct(title: '$prefix ab7s1', qty: 2, price: 12);
  final s2 = await c.createProduct(
      title: '$prefix ab7s2', qty: 2, price: 13, seller: c.seller2Id);
  if (s1 == null || s2 == null) return;
  final o1 = await c.insertOrder(productId: s1, jwt: c.buyerJwt, qty: 1, price: 12);
  final o2 = await c.insertOrder(
    productId: s2,
    jwt: c.buyerJwt,
    seller: c.seller2Id,
    qty: 1,
    price: 13,
  );
  if (o1 == null || o2 == null) {
    c.note('ab7.mix_insert', 'mix S1/S2 insert', {'o1': o1, 'o2': o2}, lens: 'AB7');
    return;
  }
  final q = await c.checkoutBag(lines: bagLines([
    (oid: o1, pid: s1),
    (oid: o2, pid: s2),
  ]));
  if (q.ok) {
    c.hold(
      id: 'RTAB-AB7-two-sellers-bag',
      lens: 'AB7',
      severity: 'P0',
      title: 'Saco mistura S1 e S2 e cria Session',
      actor: 'buyer JWT',
      pre: '1 order por vendedor',
      repro: 'bag_checkout linhas de dois sellers',
      expected: 'Pay each seller separately',
      obtained: q.brief,
    );
  } else {
    c.closedPath('AB7.two_sellers', 'saco 2 sellers recusado', q, lens: 'AB7');
  }

  // B2 line no saco B1 (order B2 + order B1)
  final oB2 = await c.insertOrder(
      productId: s1, jwt: c.buyer2Jwt, buyer: c.buyer2Id, qty: 1, price: 12);
  if (o1 != null && oB2 != null) {
    final mix = await c.checkoutBag(lines: bagLines([
      (oid: o1, pid: s1),
      (oid: oB2, pid: s1),
    ]));
    if (mix.ok) {
      c.hold(
        id: 'RTAB-AB7-b2-line-in-b1-bag',
        lens: 'AB7',
        severity: 'P0',
        title: 'Saco B1 inclui order do B2',
        actor: 'buyer JWT',
        pre: 'order B1 + order B2 mesmo seller',
        repro: 'bag_lines com order_id B2 no JWT B1',
        expected: 'recusar order does not belong',
        obtained: mix.brief,
      );
    } else {
      c.closedPath('AB7.b2_line', 'linha B2 no saco B1 recusada', mix, lens: 'AB7');
    }
  }
}

Future<void> lensAb8(Rtab c) async {
  final w0 = await c.wallets();
  c.note('ab8.wallets_before', 'saldos', w0, lens: 'AB8');

  // Encadear: se currency usd criou Session, não pagamos (Stripe TEST ainda mexeria caixa).
  // Fixture pago legítimo + 2ª tentativa refund-order pelo BUYER (não seller).
  final paid = await c.payToPago(lens: 'AB8', initialQty: 2);
  if (paid == null) return;
  final w1 = await c.wallets();
  final row = await c.orderRow(paid.oid);
  c.note('ab8.paid', 'compra Stripe TEST', {
    'oid': paid.oid,
    'status': row?['status'],
    'paid_cents': row?['amount_paid_cents'],
    'wallets': w1,
    'delta_seller': (w1['seller'] ?? 0) - (w0['seller'] ?? 0),
    'delta_buyer': (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0),
  }, lens: 'AB8');

  final buyerRefund = await c.edge('refund-order', {
    'order_id': paid.oid,
  }, jwt: c.buyerJwt);
  c.note('ab8.buyer_refund', 'buyer chama refund-order', buyerRefund.brief,
      lens: 'AB8');
  if (buyerRefund.ok && (buyerRefund.map?['ok'] == true)) {
    final w2 = await c.wallets();
    c.hold(
      id: 'RTAB-AB8-buyer-refund',
      lens: 'AB8',
      severity: 'P0',
      title: 'Buyer JWT executa refund-order',
      actor: 'buyer JWT',
      pre: 'order Stripe TEST paga',
      repro: 'POST refund-order JWT buyer',
      expected: '403 Sem permissão',
      obtained: {
        'edge': buyerRefund.brief,
        'wallets': w2,
      },
    );
  } else {
    c.closedPath('AB8.buyer_refund', 'buyer refund recusado', buyerRefund,
        lens: 'AB8');
  }

  // Seller refund duplo
  final r1 = await c.edge('refund-order', {'order_id': paid.oid}, jwt: c.sellerJwt);
  final r2 = await c.edge('refund-order', {'order_id': paid.oid}, jwt: c.sellerJwt);
  c.note('ab8.double_refund', 'seller refund 2×', {
    'r1': r1.brief,
    'r2': r2.brief,
  }, lens: 'AB8');
  final w3 = await c.wallets();
  final rowAfter = await c.orderRow(paid.oid);
  if (r1.ok && r2.ok && r2.map?['ok'] == true) {
    final sameRefund = '${r1.map?['refund_id']}' == '${r2.map?['refund_id']}';
    if (!sameRefund) {
      c.hold(
        id: 'RTAB-AB8-double-refund',
        lens: 'AB8',
        severity: 'P0',
        title: 'Dois refunds Stripe na mesma order',
        actor: 'seller JWT',
        pre: 'order paga',
        repro: 'refund-order 2×',
        expected: '2º idempotente / recusar',
        obtained: {'r1': r1.brief, 'r2': r2.brief, 'wallets': w3},
      );
    } else {
      c.closedPath('AB8.refund_idem', '2º refund idempotente', r2, lens: 'AB8');
    }
  }

  // custom_tiers pct=90 (Edge min 50?) — pagar menos no conjunto sem accept
  final d = await c.rest(
    'POST',
    'seller_bundle_discounts',
    jwt: c.sellerJwt,
    body: {
      'seller_id': c.sellerId,
      'enabled': true,
      'tier_2_pct': 10,
      'custom_tiers': [
        {'min_items': 2, 'pct': 90},
      ],
    },
  );
  if (!d.ok) {
    await c.rest('PATCH', 'seller_bundle_discounts?seller_id=eq.${c.sellerId}',
        jwt: c.sellerJwt, body: {
      'enabled': true,
      'tier_2_pct': 10,
      'custom_tiers': [
        {'min_items': 2, 'pct': 90},
      ],
    });
  }
  final p1 = await c.createProduct(title: '$prefix ab8t1', qty: 3, price: 20);
  final p2 = await c.createProduct(title: '$prefix ab8t2', qty: 3, price: 20);
  if (p1 != null && p2 != null) {
    final oa = await c.insertOrder(productId: p1, jwt: c.buyerJwt, qty: 1, price: 20);
    final ob = await c.insertOrder(productId: p2, jwt: c.buyerJwt, qty: 1, price: 20);
    if (oa != null && ob != null) {
      final q = await c.checkoutBag(lines: bagLines([
        (oid: oa, pid: p1),
        (oid: ob, pid: p2),
      ]));
      c.note('ab8.custom90', 'custom_tiers pct=90', {
        'amount': q.serverAmount,
        'ok': q.ok,
        'brief': q.brief,
      }, lens: 'AB8');
      // 2×20€ = 4000 + prot. 50% cap → ~2000+prot; 90% → ~400+prot
      final amt = q.serverAmount ?? 0;
      if (q.ok && amt > 0 && amt < 1200) {
        c.hold(
          id: 'RTAB-AB8-custom-tier-90',
          lens: 'AB8',
          severity: 'P0',
          title: 'custom_tiers pct=90 reduz o saco abaixo do cap 50%',
          actor: 'seller JWT (desconto) + buyer checkout',
          pre: 'seller_bundle_discounts custom_tiers 90%',
          repro: 'bag 2 SKUs 20€+20€',
          expected: 'desconto ≤50% (items ≥2000 cents + taxas)',
          obtained: q.brief,
        );
      } else if (q.ok) {
        c.closedPath('AB8.tier90_capped', 'pct 90 capado no quote', q, lens: 'AB8');
      }
    }
  }
  await c.rest(
    'PATCH',
    'seller_bundle_discounts?seller_id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {
      'enabled': false,
      'custom_tiers': <Object>[],
    },
  );

  c.note('ab8.wallets_after', 'saldos finais', w3, lens: 'AB8');
  c.note('ab8.row_after_refund', 'order após refunds', rowAfter, lens: 'AB8');
}
