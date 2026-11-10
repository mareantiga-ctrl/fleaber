// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import '_rty.dart';

Future<void> main() async {
  final c = Rty.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('actors', 'ids', {
    'B1': c.buyerId,
    'S1': c.sellerId,
    'B2': c.buyer2Id,
    'S2': c.seller2Id,
  });

  await yWalletRpcs(c);
  await yFsmAliasesAndRefund(c);
  await yRaceShipRefund(c);
  await ySecondActor(c);
  await yBundleQtyAndSteal(c);
  await yCheckoutReuseAndRace(c);
  await yOfferWrongProduct(c);
  await yTierHostil(c);
  await yDisputeAlias(c);
  await yHappyPathRefundBeforeShip(c);

  await dumpJson('${outDir()}/probe.json', {
    'prefix': prefix,
    'findings': c.findings,
    'closed': c.closed,
    'holds': c.holds,
    'notes': c.notes,
  });
  stdout.writeln(
      'PROBE DONE findings=${c.findings.length} closed=${c.closed.length}');
}

Future<Map<String, dynamic>?> paidFixture(Rty c) async {
  final h = await c.setupPaidOrder();
  c.note('fixture.paid', 'setup_paid_order', h, lens: 'Y1');
  final m = h.map;
  final oid = '${m?['order_id'] ?? ''}'.trim();
  if (oid.isEmpty) return null;
  c.createdOrderIds.add(oid);
  final pid = '${m?['product_id'] ?? ''}'.trim();
  if (pid.isNotEmpty) c.createdProductIds.add(pid);
  await c.rest('PATCH', 'orders?id=eq.$oid', service: true, body: {
    'shipping_method': 'mao',
    'payment_method': 'pagamento na app',
  }, prefer: 'return=minimal');
  return m;
}

Future<void> yWalletRpcs(Rty c) async {
  final dummyOrder = '00000000-0000-0000-0000-000000000001';
  final credit = await c.rpc(
    'batata_credit_wallet_once',
    {
      'p_wallet_id': c.buyerId,
      'p_order_id': dummyOrder,
      'p_amount': 88.88,
      'p_type': 'reembolso',
      'p_description': '$prefix mint',
    },
    jwt: c.buyerJwt,
  );
  c.note('Y8.credit_jwt', 'batata_credit_wallet_once JWT', credit, lens: 'Y8');
  if (credit.ok && credit.body.toLowerCase().contains('true')) {
    final bal = await c.walletBal(c.buyerId!);
    c.finding(
      id: 'RTY-Y8-001',
      lens: 'Y8',
      severity: 'P0',
      title: 'JWT executa batata_credit_wallet_once e minta carteira',
      actor: 'buyer JWT',
      pre: 'B1 autenticado',
      repro: 'POST /rpc/batata_credit_wallet_once amount=88.88',
      expected: '42501 / grant recusado',
      obtained: credit,
      impact: 'Δwallet comprador sem captura Stripe',
      evidence: {'balance': bal, 'http': credit.brief},
    );
  } else {
    c.closedPath('Y8.credit_jwt', 'credit_wallet JWT recusado', credit,
        lens: 'Y8');
  }

  final debit = await c.rpc(
    'batata_debit_wallet_once',
    {
      'p_wallet_id': c.sellerId,
      'p_order_id': dummyOrder,
      'p_amount': 1.0,
      'p_description': '$prefix debit',
    },
    jwt: c.buyerJwt,
  );
  if (debit.ok && debit.body.toLowerCase().contains('true')) {
    c.finding(
      id: 'RTY-Y8-002',
      lens: 'Y8',
      severity: 'P0',
      title: 'JWT executa batata_debit_wallet_once',
      actor: 'buyer JWT',
      pre: 'B1',
      repro: 'POST /rpc/batata_debit_wallet_once',
      expected: 'grant recusado',
      obtained: debit,
    );
  } else {
    c.closedPath('Y8.debit_jwt', 'debit_wallet JWT recusado', debit, lens: 'Y8');
  }
}

Future<void> yFsmAliasesAndRefund(Rty c) async {
  final aliases = <String>[
    'em_transito',
    'shipped',
    'enviada',
    'enviado\u200b',
    'enviado',
    'Enviado ',
    'expedido',
    'em transito',
  ];

  for (final alias in aliases) {
    final fx = await paidFixture(c);
    final oid = '${fx?['order_id'] ?? ''}'.trim();
    if (oid.isEmpty) continue;
    final before = await c.orderRow(oid);
    final patch = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: c.sellerJwt,
      body: {'status': alias},
    );
    final after = await c.orderRow(oid);
    final st = '${after?['status'] ?? ''}';
    final shipped = after?['shipped_at'];
    c.note('Y1.alias.$alias', 'PATCH status', {
      'http': patch.status,
      'before': before?['status'],
      'after': st,
      'shipped_at': shipped,
      'patch': patch.brief,
    }, lens: 'Y1');

    final storedAlias = st != 'pago' && st != '${before?['status']}';
    if (patch.ok && storedAlias && shipped == null) {
      final ref = await c.refundOrder(oid);
      final afterRef = await c.orderRow(oid);
      final refunded = '${afterRef?['stripe_refund_id'] ?? ''}'.trim().isNotEmpty ||
          '${afterRef?['status']}' == 'cancelado' ||
          (ref.ok && ref.map?['ok'] == true && ref.map?['skipped'] != true);
      if (refunded || (ref.ok && ref.map?['ok'] == true)) {
        c.finding(
          id: 'RTY-Y1-001-$alias',
          lens: 'Y1',
          severity: 'P0',
          title: 'Alias de envio sem shipped_at permite refund Stripe',
          actor: 'seller JWT',
          pre: 'order Stripe TEST pago; PATCH status=$alias',
          repro:
              'PATCH orders status=$alias (shipped_at null) → POST refund-order',
          expected:
              'refund bloqueado (order_refund_blocked_shipped / status)',
          obtained: {
            'status': afterRef?['status'],
            'shipped_at': afterRef?['shipped_at'],
            'stripe_refund_id': afterRef?['stripe_refund_id'],
            'refund': ref.brief,
          },
          impact: 'Reembolso cartão após marcar envio por alias; stock pode restaurar',
          evidence: {
            'alias': alias,
            'after_patch': after,
            'after_refund': afterRef,
          },
        );
      } else if (ref.status == 403 ||
          '${ref.map?['code'] ?? ''}'.contains('refund_blocked')) {
        c.closedPath(
            'Y1.alias.$alias.refund', 'alias guardado mas refund bloqueado', ref,
            lens: 'Y1');
      } else {
        c.note('Y1.alias.$alias.refund', 'refund resultado', ref, lens: 'Y1');
      }
    } else if (patch.ok &&
        '${after?['status']}' == 'enviado' &&
        shipped != null) {
      c.closedPath('Y1.alias.$alias', 'normalizado para enviado+shipped_at', after,
          lens: 'Y1');
    } else if (!patch.ok || !storedAlias) {
      c.closedPath('Y1.alias.$alias', 'alias rejeitado ou não persistido', {
        'patch': patch.brief,
        'status': st,
      }, lens: 'Y1');
    }
  }

  // pago → entregue (salta enviado) → shipped_at?
  final fx2 = await paidFixture(c);
  final oid2 = '${fx2?['order_id'] ?? ''}'.trim();
  if (oid2.isNotEmpty) {
    final p = await c.rest('PATCH', 'orders?id=eq.$oid2',
        jwt: c.sellerJwt, body: {'status': 'entregue'});
    final row = await c.orderRow(oid2);
    c.note('Y1.skip_enviado', 'pago→entregue', {
      'patch': p.brief,
      'status': row?['status'],
      'shipped_at': row?['shipped_at'],
    }, lens: 'Y1');
    if (p.ok &&
        '${row?['status']}' == 'entregue' &&
        row?['shipped_at'] == null) {
      final hop = await c.rest('PATCH', 'orders?id=eq.$oid2',
          jwt: c.sellerJwt, body: {'status': 'em_transito'});
      final row2 = await c.orderRow(oid2);
      final ref = await c.refundOrder(oid2);
      final row3 = await c.orderRow(oid2);
      c.note('Y1.entregue_hop', 'entregue→em_transito→refund', {
        'hop': hop.brief,
        'mid': row2,
        'refund': ref.brief,
        'end': row3,
      }, lens: 'Y1');
      final refunded =
          '${row3?['stripe_refund_id'] ?? ''}'.trim().isNotEmpty ||
              '${row3?['status']}' == 'cancelado';
      if (refunded && row3?['shipped_at'] == null) {
        c.finding(
          id: 'RTY-Y1-002',
          lens: 'Y1',
          severity: 'P0',
          title: 'pago→entregue→em_transito fura shipped_at e refund',
          actor: 'seller JWT',
          pre: 'Stripe TEST pago',
          repro:
              'PATCH entregue (sem enviado) → PATCH em_transito → refund-order',
          expected: 'shipped_at selado ou refund bloqueado',
          obtained: row3,
          impact: 'Refund Stripe após estado de entrega, sem selo shipped_at',
        );
      } else {
        c.closedPath('Y1.entregue_hop', 'hop/refund não liquidou', {
          'refund': ref.brief,
          'end': row3,
        }, lens: 'Y1');
      }
    } else if (p.ok && row?['shipped_at'] != null) {
      c.closedPath('Y1.skip_enviado', 'entregue selou shipped_at', row,
          lens: 'Y1');
    }

    final refBlocked = await c.refundOrder(oid2);
    if ('${row?['status']}' == 'entregue' &&
        (refBlocked.status == 403 ||
            '${refBlocked.map?['code']}'.contains('blocked'))) {
      c.closedPath('Y1.entregue.refund', 'refund bloqueado em entregue',
          refBlocked,
          lens: 'Y1');
    }
  }

  // JWT PATCH shipped_at
  final fx3 = await paidFixture(c);
  final oid3 = '${fx3?['order_id'] ?? ''}'.trim();
  if (oid3.isNotEmpty) {
    await c.rest('PATCH', 'orders?id=eq.$oid3',
        jwt: c.sellerJwt, body: {'status': 'enviado'});
    final clr = await c.rest('PATCH', 'orders?id=eq.$oid3',
        jwt: c.sellerJwt, body: {'shipped_at': null});
    final row = await c.orderRow(oid3);
    if (row?['shipped_at'] == null && '${row?['status']}' == 'enviado') {
      c.finding(
        id: 'RTY-Y1-003',
        lens: 'Y1',
        severity: 'P0',
        title: 'JWT limpa shipped_at',
        actor: 'seller JWT',
        pre: 'enviado com shipped_at',
        repro: 'PATCH shipped_at=null',
        expected: 'selo permanente',
        obtained: row,
      );
    } else {
      c.closedPath('Y1.clear_shipped_at', 'JWT não limpa shipped_at', {
        'patch': clr.brief,
        'row': row,
      }, lens: 'Y1');
    }
    final ref = await c.refundOrder(oid3);
    if (ref.status == 403 || '${ref.map?['code']}'.contains('blocked')) {
      c.closedPath('Y1.enviado.refund', 'refund bloqueado pós-enviado', ref,
          lens: 'Y1');
    } else if (ref.ok && ref.map?['ok'] == true && ref.map?['skipped'] != true) {
      c.finding(
        id: 'RTY-Y1-004',
        lens: 'Y1',
        severity: 'P0',
        title: 'refund-order após enviado real',
        actor: 'seller JWT',
        pre: 'status=enviado shipped_at set',
        repro: 'POST refund-order',
        expected: '403 order_refund_blocked_shipped',
        obtained: ref,
      );
    }
  }
}

Future<void> yRaceShipRefund(Rty c) async {
  final fx = await paidFixture(c);
  final oid = '${fx?['order_id'] ?? ''}'.trim();
  if (oid.isEmpty) return;
  final results = await Future.wait([
    c.rest('PATCH', 'orders?id=eq.$oid',
        jwt: c.sellerJwt, body: {'status': 'enviado'}),
    c.refundOrder(oid),
    c.refundOrder(oid),
  ]);
  final row = await c.orderRow(oid);
  c.note('Y6.ship_refund', 'Future.wait PATCH enviado ∥ 2× refund-order', {
    'patch': results[0].brief,
    'r1': results[1].brief,
    'r2': results[2].brief,
    'row': row,
  }, lens: 'Y6');
  final shipped = row?['shipped_at'] != null;
  final refunded = '${row?['stripe_refund_id'] ?? ''}'.trim().isNotEmpty ||
      '${row?['status']}' == 'cancelado';
  if (shipped && refunded) {
    c.finding(
      id: 'RTY-Y6-001',
      lens: 'Y6',
      severity: 'P0',
      title: 'Race envio ∥ refund: shipped_at E stripe_refund_id',
      actor: 'seller JWT concurrent',
      pre: 'Stripe TEST pago, status pago',
      repro: 'Future.wait PATCH enviado + 2× POST refund-order',
      expected: 'um ganha: ou enviado sem refund, ou refund sem shipped_at',
      obtained: row,
      impact: 'Dinheiro Stripe reembolsado depois do selo de envio (TOCTOU gate)',
    );
  } else {
    c.closedPath('Y6.ship_refund', 'race não deixou shipped+refund', row,
        lens: 'Y6');
  }
}

Future<void> ySecondActor(Rty c) async {
  final fx = await paidFixture(c);
  final oid = '${fx?['order_id'] ?? ''}'.trim();
  if (oid.isEmpty) return;
  final b2 = await c.rest('PATCH', 'orders?id=eq.$oid',
      jwt: c.buyer2Jwt, body: {'status': 'enviado'});
  final s2ref = await c.refundOrder(oid, jwt: c.seller2Jwt);
  final b2ref = await c.refundOrder(oid, jwt: c.buyer2Jwt);
  final row = await c.orderRow(oid);
  c.note('Y7.b2s2', 'B2 PATCH + S2/B2 refund', {
    'b2patch': b2.brief,
    's2ref': s2ref.brief,
    'b2ref': b2ref.brief,
    'row': row,
  }, lens: 'Y7');
  if (b2.ok && '${row?['status']}' == 'enviado' && row?['buyer_id'] == c.buyerId) {
    c.finding(
      id: 'RTY-Y7-001',
      lens: 'Y7',
      severity: 'P1',
      title: 'B2 altera status da order de B1',
      actor: 'buyer2 JWT',
      pre: 'order B1/S1 paga',
      repro: 'PATCH orders status=enviado com JWT B2',
      expected: '403 / status inalterado',
      obtained: row,
    );
  } else {
    c.closedPath('Y7.b2patch', 'B2 não muda order B1', b2, lens: 'Y7');
  }
  final s2ok = s2ref.ok && s2ref.map?['ok'] == true && s2ref.map?['skipped'] != true;
  if (s2ok) {
    c.finding(
      id: 'RTY-Y7-002',
      lens: 'Y7',
      severity: 'P0',
      title: 'S2 reembolsa order de S1',
      actor: 'seller2 JWT',
      pre: 'order S1',
      repro: 'POST refund-order JWT S2',
      expected: '403 Sem permissão',
      obtained: s2ref,
    );
  } else {
    c.closedPath('Y7.s2refund', 'S2 refund recusado', s2ref, lens: 'Y7');
  }
}

Future<void> yBundleQtyAndSteal(Rty c) async {
  final pa = await c.insertProduct(title: '$prefix A', qty: 8, price: 20);
  final pb = await c.insertProduct(title: '$prefix B', qty: 8, price: 20);
  if (pa == null || pb == null) return;

  // B1 bundle 50% aceite
  final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_ids': [pa, pb],
    'status': 'pending',
  });
  final bid = bun.firstId;
  c.note('Y2.bundle.create', 'B1 bundle', bun, lens: 'Y2');
  if (bid == null) return;
  c.createdBundleIds.add(bid);
  final acc = await c.rest('PATCH', 'product_bundles?id=eq.$bid',
      jwt: c.sellerJwt, body: {'status': 'accepted', 'discount_pct': 50});
  final bunRow = await c.rest(
    'GET',
    'product_bundles?id=eq.$bid&select=id,status,total_eur,subtotal_eur,discount_pct,product_ids,buyer_id',
    service: true,
  );
  c.note('Y2.bundle.accept', '50%', {
    'acc': acc.brief,
    'row': bunRow.map,
  }, lens: 'Y2');
  final bundleTotal = (bunRow.map?['total_eur'] as num?) ?? 0;

  // Extra qty on bundle line (NOT extra SKU)
  final oa = await c.insertOrder(productId: pa, qty: 3, bundleId: bid, shipping: 'mao');
  final ob = await c.insertOrder(productId: pb, qty: 1, bundleId: bid, shipping: 'mao');
  if (oa == null || ob == null) return;
  final q = await c.checkout(bag: true, bagLines: [
    {'order_id': oa},
    {'order_id': ob},
  ]);
  c.note('Y2.bundle.extra_qty.quote', 'checkout 3+1 vs bundle 1+1', q,
      lens: 'Y2');
  final cents = (q.map?['server_amount_cents'] as num?) ??
      (q.map?['amount_total'] as num?);
  // list 20*3+20*1=80; bundle 20+20-50%=20. Protection+hand.
  // If charged near bundle-of-2 (~20+prot) instead of 80+prot → underpay
  if (q.ok && cents != null && cents < 4000) {
    c.finding(
      id: 'RTY-Y2-001',
      lens: 'Y2',
      severity: 'P0',
      title: 'Conjunto aceite cobra total_eur ignora qty extra nas linhas',
      actor: 'buyer JWT',
      pre:
          'bundle A+B aceite total_eur=$bundleTotal; orders qty 3 e 1 do mesmo SKU set',
      repro:
          'POST create-payment-intent bag_checkout com as 2 orders (qty 3+1)',
      expected: 'cobrar 3×A+1×B (list ou recusar qty≠1 no conjunto)',
      obtained: {
        'server_amount_cents': cents,
        'bundle_total_eur': bundleTotal,
        'checkout': q.brief,
      },
      impact:
          'Pagar preço de 2 unidades e levar 4; stock descontado no settle',
      evidence: {
        'orders': [await c.orderRow(oa), await c.orderRow(ob)],
        'quote': q.map,
      },
    );
  } else if (!q.ok) {
    c.closedPath('Y2.extra_qty', 'checkout recusou qty extra no conjunto', q,
        lens: 'Y2');
  } else {
    c.note('Y2.extra_qty.amount', 'cents=$cents (não sub-40€)', q, lens: 'Y2');
  }

  // Steal B2 bundle: B2 creates+S1 accepts, B1 attaches
  final bun2 = await c.rest('POST', 'product_bundles', jwt: c.buyer2Jwt, body: {
    'buyer_id': c.buyer2Id,
    'seller_id': c.sellerId,
    'product_ids': [pa, pb],
  });
  final bid2 = bun2.firstId;
  if (bid2 != null) {
    c.createdBundleIds.add(bid2);
    await c.rest('PATCH', 'product_bundles?id=eq.$bid2',
        jwt: c.sellerJwt, body: {'status': 'accepted', 'discount_pct': 50});
    final oa1 = await c.insertOrder(productId: pa, qty: 1, shipping: 'mao');
    final ob1 = await c.insertOrder(productId: pb, qty: 1, shipping: 'mao');
    if (oa1 != null && ob1 != null) {
      final attA = await c.rest('PATCH', 'orders?id=eq.$oa1',
          jwt: c.buyerJwt, body: {'bundle_id': bid2});
      final attB = await c.rest('PATCH', 'orders?id=eq.$ob1',
          jwt: c.buyerJwt, body: {'bundle_id': bid2});
      final q2 = await c.checkout(bag: true, bagLines: [
        {'order_id': oa1},
        {'order_id': ob1},
      ]);
      c.note('Y2.steal_bundle', 'B1 usa bundle de B2', {
        'attA': attA.brief,
        'attB': attB.brief,
        'quote': q2.brief,
      }, lens: 'Y2');
      final rowA = await c.orderRow(oa1);
      final attached = rowA?['bundle_id']?.toString() == bid2;
      final cents2 = (q2.map?['server_amount_cents'] as num?) ??
          (q2.map?['amount_total'] as num?);
      if (attached && q2.ok && cents2 != null && cents2 < 4000) {
        c.finding(
          id: 'RTY-Y2-002',
          lens: 'Y2',
          severity: 'P1',
          title: 'B1 anexa bundle aceite de B2 e paga o total negociado',
          actor: 'buyer JWT',
          pre: 'bundle B2 aceite 50%; orders B1 sem bundle',
          repro: 'PATCH orders.bundle_id=<bundle B2> → bag checkout',
          expected: 'bundle_id só do buyer do contrato / recusar',
          obtained: {
            'attached': attached,
            'server_amount_cents': cents2,
            'quote': q2.brief,
          },
          impact: 'Free-ride no desconto de outro comprador',
        );
      } else if (!attached) {
        c.closedPath('Y2.steal_bundle.patch', 'não anexou bundle B2', attA,
            lens: 'Y2');
      } else {
        c.closedPath('Y2.steal_bundle.quote', 'anexou mas não subcotou', q2,
            lens: 'Y2');
      }
    }
  }

  // Two bundle_ids in one bag
  if (bid2 != null) {
    final oX = await c.insertOrder(productId: pa, qty: 1, bundleId: bid, shipping: 'mao');
    final oY = await c.insertOrder(productId: pb, qty: 1, bundleId: bid2, shipping: 'mao');
    if (oX != null && oY != null) {
      final q3 = await c.checkout(bag: true, bagLines: [
        {'order_id': oX},
        {'order_id': oY},
      ]);
      if (q3.ok) {
        c.finding(
          id: 'RTY-Y2-003',
          lens: 'Y2',
          severity: 'P1',
          title: 'Saco mistura dois bundle_id e cria Session',
          actor: 'buyer JWT',
          pre: 'duas orders com bundle_id distintos',
          repro: 'POST create-payment-intent bag_checkout',
          expected: 'Checkout blocked: multiple bundle contracts',
          obtained: q3,
        );
      } else {
        c.closedPath('Y2.two_bundles', 'Edge recusa 2 bundle_id', q3, lens: 'Y2');
      }
    }
  }
}

Future<void> yCheckoutReuseAndRace(Rty c) async {
  final p1 = await c.insertProduct(title: '$prefix cheap', qty: 4, price: 8);
  final p2 = await c.insertProduct(title: '$prefix dear', qty: 4, price: 40);
  if (p1 == null || p2 == null) return;
  final o1 = await c.insertOrder(productId: p1, qty: 1, shipping: 'mao');
  if (o1 == null) return;
  final s1 = await c.checkout(orderId: o1);
  c.note('Y3.s1', 'checkout barato', s1, lens: 'Y3');
  final sid1 = '${s1.map?['checkoutSessionId'] ?? ''}';
  final amt1 = s1.map?['server_amount_cents'] ?? s1.map?['amount_total'];

  final o2 = await c.insertOrder(productId: p2, qty: 1, shipping: 'mao');
  if (o2 == null) return;
  final s2 = await c.checkout(bag: true, bagLines: [
    {'order_id': o1},
    {'order_id': o2},
  ]);
  c.note('Y3.reuse_expand', 'bag A+B após session A', s2, lens: 'Y3');
  final sid2 = '${s2.map?['checkoutSessionId'] ?? ''}';
  final amt2 = s2.map?['server_amount_cents'];
  final amtTot = s2.map?['amount_total'];
  final reused = s2.map?['reused_session'] == true || (sid1.isNotEmpty && sid1 == sid2);
  if (s2.ok && reused) {
    final a1 = num.tryParse('$amt1') ?? 0;
    final a2 = num.tryParse('$amt2') ?? 0;
    final at = num.tryParse('$amtTot') ?? 0;
    if (a1 > 0 && (at > 0 && at < a2 || a2 > a1 + 500)) {
      c.finding(
        id: 'RTY-Y3-001',
        lens: 'Y3',
        severity: 'P1',
        title: 'Session reuse devolve URL barata com quote de saco expandido',
        actor: 'buyer JWT',
        pre: 'Session aberta na order barata; depois bag A+B',
        repro:
            'POST create-payment-intent order A; depois bag_checkout A+B',
        expected: 'nova Session com total do saco, ou recusar reuse se quote mudou',
        obtained: {
          'sid1': sid1,
          'sid2': sid2,
          'amt1': amt1,
          'server_amount_cents_bag': amt2,
          'amount_total': amtTot,
          'reused': reused,
        },
        impact:
            'Cliente pode pagar Session antiga; settle usa metadata antiga (1 linha) — ou pior se metadata for actualizada',
      );
    } else {
      c.note('Y3.reuse.same_amt', 'reuse sem divergência útil', {
        'amt1': amt1,
        'amt2': amt2,
        'amount_total': amtTot,
        'sid': sid2,
      }, lens: 'Y3');
    }
  } else {
    c.closedPath('Y3.reuse_expand', 'não reutilizou Session da linha A', s2,
        lens: 'Y3');
  }

  // Race 2× PI on a fresh order (not dual-session exact of U: concurrent POST)
  final p3 = await c.insertProduct(title: '$prefix race', qty: 2, price: 9);
  final o3 = await c.insertOrder(productId: p3!, qty: 1, shipping: 'mao');
  if (o3 != null) {
    final raced = await Future.wait([
      c.checkout(orderId: o3),
      c.checkout(orderId: o3),
      c.checkout(orderId: o3),
    ]);
    final sids = raced
        .map((h) => '${h.map?['checkoutSessionId'] ?? ''}')
        .where((s) => s.startsWith('cs_'))
        .toSet();
    c.note('Y3.race3', '3× POST create-payment-intent', {
      'briefs': raced.map((e) => e.brief).toList(),
      'unique_cs': sids.toList(),
    }, lens: 'Y3');
    if (sids.length > 1) {
      c.finding(
        id: 'RTY-Y3-002',
        lens: 'Y3',
        severity: 'P1',
        title: 'Race 3× POST cria mais do que uma Checkout Session',
        actor: 'buyer JWT concurrent',
        pre: 'order reserva_pendente',
        repro: 'Future.wait 3× create-payment-intent',
        expected: '1 cs_ (claim slot)',
        obtained: sids.toList(),
        impact: 'Dois PI abertos — risco de dupla captura se ambos pagos',
      );
    } else {
      c.closedPath('Y3.race3', '1 Session sob race', sids, lens: 'Y3');
    }
  }

  // Client total / amount in body
  if (o3 != null) {
    final hostile = await c.edge('create-payment-intent', jwt: c.buyerJwt, body: {
      'order_id': o3,
      'amount': 0.5,
      'item_price': 0.5,
      'shipping': 0,
      'protection_fee': 0,
      'shipping_method': 'mao',
      'total_eur': 0.5,
    });
    final hcents = hostile.map?['server_amount_cents'] ?? hostile.map?['amount_total'];
    c.note('Y3.body_amount', 'amount/total_eur no body', {
      'http': hostile.status,
      'cents': hcents,
      'brief': hostile.brief,
    }, lens: 'Y3');
    if (hostile.ok) {
      final n = num.tryParse('$hcents') ?? 0;
      if (n > 0 && n < 200) {
        c.finding(
          id: 'RTY-Y3-003',
          lens: 'Y3',
          severity: 'P0',
          title: 'Edge aceita total/amount do cliente',
          actor: 'buyer JWT',
          pre: 'produto ~9€',
          repro: 'POST create-payment-intent amount=0.5 total_eur=0.5',
          expected: 'quote servidor ~9€+taxas',
          obtained: hostile,
        );
      } else {
        c.closedPath('Y3.body_amount', 'quote ignora amount do body', hostile,
            lens: 'Y3');
      }
    }
  }
}

Future<void> yOfferWrongProduct(Rty c) async {
  final pA = await c.insertProduct(title: '$prefix offerA', qty: 3, price: 30);
  final pB = await c.insertProduct(title: '$prefix offerB', qty: 3, price: 30);
  if (pA == null || pB == null) return;
  final off = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pA,
    'offer_price': 6,
    'status': 'pending',
  });
  final oid = off.firstId;
  c.note('Y2.offer.create', 'offer 6€ on A', off, lens: 'Y2');
  if (oid == null) return;
  await c.rest('PATCH', 'product_offers?id=eq.$oid',
      jwt: c.sellerJwt, body: {'status': 'accepted'});
  final orderB = await c.insertOrder(
    productId: pB,
    qty: 1,
    offerId: oid,
    shipping: 'mao',
  );
  if (orderB == null) {
    c.closedPath('Y2.offer.wrong_product', 'INSERT order B com offer A recusado',
        'no order',
        lens: 'Y2');
    return;
  }
  final row = await c.orderRow(orderB);
  final q = await c.checkout(orderId: orderB);
  c.note('Y2.offer.wrong', 'offer A em produto B', {
    'row': row,
    'quote': q.brief,
  }, lens: 'Y2');
  final cents = num.tryParse('${q.map?['server_amount_cents'] ?? ''}') ?? 0;
  final usedOffer = row?['product_offer_id']?.toString() == oid;
  if (usedOffer && q.ok && cents > 0 && cents < 1500) {
    c.finding(
      id: 'RTY-Y2-004',
      lens: 'Y2',
      severity: 'P0',
      title: 'Oferta de A aplica-se a order do produto B',
      actor: 'buyer JWT',
      pre: 'oferta aceite no produto A a 6€',
      repro: 'POST orders product_id=B product_offer_id=ofertaA → checkout',
      expected: 'offer_id limpo ou recusa produto mismatch',
      obtained: {'row': row, 'cents': cents, 'quote': q.brief},
    );
  } else {
    c.closedPath('Y2.offer.wrong_product', 'oferta não baixou B', {
      'usedOffer': usedOffer,
      'cents': cents,
      'contract': row?['contract_unit_cents'],
    }, lens: 'Y2');
  }

  // qty>1 with offer — INSERT (atrophy is qty=1 exact; this is qty=2)
  final o2 = await c.insertOrder(
    productId: pA,
    qty: 2,
    offerId: oid,
    shipping: 'mao',
  );
  if (o2 != null) {
    final r2 = await c.orderRow(o2);
    c.finding(
      id: 'RTY-Y2-005',
      lens: 'Y2',
      severity: 'P1',
      title: 'Oferta aceite com quantity=2 na INSERT',
      actor: 'buyer JWT',
      pre: 'product_offer accepted',
      repro: 'POST orders quantity=2 product_offer_id',
      expected: 'offer_quantity_must_be_one',
      obtained: r2,
    );
  } else {
    c.closedPath('Y2.offer.qty2', 'qty=2 com oferta recusado', 'no order',
        lens: 'Y2');
  }
}

Future<void> yTierHostil(Rty c) async {
  final hostile = await c.rest(
    'POST',
    'seller_bundle_discounts',
    jwt: c.buyerJwt,
    body: {
      'seller_id': c.sellerId,
      'enabled': true,
      'tier_2_pct': 90,
      'custom_tiers': [
        {'min_items': 2, 'pct': 90}
      ],
    },
  );
  c.note('Y2.tier.buyer_write', 'B1 escreve descontos do S1', hostile,
      lens: 'Y2');
  if (hostile.ok) {
    c.finding(
      id: 'RTY-Y2-006',
      lens: 'Y2',
      severity: 'P1',
      title: 'Comprador escreve seller_bundle_discounts de outro seller',
      actor: 'buyer JWT',
      pre: 'S1 loja',
      repro: 'POST seller_bundle_discounts seller_id=S1 tier_2_pct=90',
      expected: 'RLS own-only',
      obtained: hostile,
    );
  } else {
    c.closedPath('Y2.tier.buyer_write', 'B1 não escreve tiers S1', hostile,
        lens: 'Y2');
  }

  final self = await c.rest(
    'POST',
    'seller_bundle_discounts',
    jwt: c.sellerJwt,
    body: {
      'seller_id': c.sellerId,
      'enabled': true,
      'tier_2_pct': 40,
      'custom_tiers': [
        {'min_items': 2, 'pct': 80}
      ],
    },
  );
  c.note('Y2.tier.seller80', 'S1 custom 80% (Edge cap 50?)', self, lens: 'Y2');
  final p1 = await c.insertProduct(title: '$prefix t1', qty: 3, price: 15);
  final p2 = await c.insertProduct(title: '$prefix t2', qty: 3, price: 15);
  if (p1 == null || p2 == null) return;
  final o1 = await c.insertOrder(productId: p1, qty: 1, shipping: 'mao');
  final o2 = await c.insertOrder(productId: p2, qty: 1, shipping: 'mao');
  if (o1 == null || o2 == null) return;
  final q = await c.checkout(bag: true, bagLines: [
    {'order_id': o1},
    {'order_id': o2},
  ]);
  final cents = num.tryParse('${q.map?['server_amount_cents'] ?? ''}') ?? 0;
  c.note('Y2.tier.quote', '2 itens com custom 80%', {
    'cents': cents,
    'quote': q.brief,
  }, lens: 'Y2');
  // 15+15=30, 50% cap → 15 + prot; 80% would be 6 + prot. Hand prot on 15 ≈ 65+75=140 → ~1640c; on 6 ≈ ~1300c?
  if (q.ok && cents > 0 && cents < 1200) {
    c.finding(
      id: 'RTY-Y2-007',
      lens: 'Y2',
      severity: 'P1',
      title: 'custom_tiers pct>50 não é capado no checkout',
      actor: 'seller JWT + buyer checkout',
      pre: 'custom_tiers min_items=2 pct=80',
      repro: 'bag 2 produtos 15€ → create-payment-intent',
      expected: 'desconto máx 50% (itemsCents >= 1500 + prot)',
      obtained: {'cents': cents, 'quote': q.brief},
    );
  }
}

Future<void> yDisputeAlias(Rty c) async {
  final fx = await paidFixture(c);
  final oid = '${fx?['order_id'] ?? ''}'.trim();
  if (oid.isEmpty) return;
  await c.rest('PATCH', 'orders?id=eq.$oid',
      jwt: c.sellerJwt, body: {'status': 'em_transito'});
  final d = await c.rest('POST', 'order_disputes', jwt: c.buyerJwt, body: {
    'order_id': oid,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'reason': '$prefix dispute alias',
    'status': 'aberta',
  });
  c.note('Y5.dispute.insert', 'disputa após alias em_transito', d, lens: 'Y5');
  final did = d.firstId;
  if (did != null) {
    final offer = await c.rest('PATCH', 'order_disputes?id=eq.$did',
        jwt: c.sellerJwt,
        body: {
          'seller_refund_percent': 40,
          'seller_offer_type': 'partial_refund',
          'seller_offer_set_by': c.sellerId,
        });
    c.note('Y5.dispute.offer', 'seller 40%', offer, lens: 'Y5');
    final wr = await c.rpc(
      'batata_process_partial_refund_dispute',
      {'p_order_id': oid, 'p_refund_percent': 40},
      jwt: c.buyerJwt,
    );
    final row = await c.orderRow(oid);
    final tx = await c.rest(
      'GET',
      'wallet_transactions?order_id=eq.$oid&select=wallet_id,amount,type,description',
      service: true,
    );
    c.note('Y5.dispute.rpc', 'partial refund dispute', {
      'rpc': wr.brief,
      'order': row,
      'tx': tx.brief,
    }, lens: 'Y5');
    final minted = tx.list.any((e) =>
        e is Map &&
        '${e['type']}' == 'reembolso' &&
        (e['amount'] is num && (e['amount'] as num) > 0));
    if (wr.ok && minted) {
      c.finding(
        id: 'RTY-Y5-001',
        lens: 'Y5',
        severity: 'P0',
        title: 'Disputa parcial minta wallet após envio-alias (sem Stripe refund)',
        actor: 'buyer JWT + seller collusion',
        pre: 'pago Stripe; status em_transito (shipped_at null)',
        repro:
            'POST order_disputes → seller offer 40% → rpc batata_process_partial_refund_dispute',
        expected: 'dispute_partial_refund_requires_stripe ou recusa estado',
        obtained: {'rpc': wr.brief, 'tx': tx.brief, 'order': row},
        impact: 'Δwallet comprador + captura Stripe intacta (double funds)',
      );
    } else {
      c.closedPath('Y5.dispute.mint', 'disputa não mintou wallet', wr,
          lens: 'Y5');
    }
  }

  // refund-order while dispute open on pago (no alias)
  final fx2 = await paidFixture(c);
  final oid2 = '${fx2?['order_id'] ?? ''}'.trim();
  if (oid2.isNotEmpty) {
    await c.rest('POST', 'order_disputes', jwt: c.buyerJwt, body: {
      'order_id': oid2,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'reason': '$prefix open on pago',
      'status': 'aberta',
    });
    final ref = await c.refundOrder(oid2);
    c.note('Y5.refund_open_dispute', 'refund com disputa aberta em pago', ref,
        lens: 'Y5');
    if (ref.ok && ref.map?['ok'] == true && ref.map?['skipped'] != true) {
      c.finding(
        id: 'RTY-Y5-002',
        lens: 'Y5',
        severity: 'P1',
        title: 'refund-order com disputa aberta em pago',
        actor: 'seller JWT',
        pre: 'pago + order_disputes aberta',
        repro: 'POST refund-order',
        expected: '403 order_refund_blocked_open_dispute',
        obtained: ref,
      );
    } else {
      c.closedPath('Y5.refund_open_dispute', 'refund bloqueado com disputa', ref,
          lens: 'Y5');
    }
  }
}

Future<void> yHappyPathRefundBeforeShip(Rty c) async {
  final fx = await paidFixture(c);
  final oid = '${fx?['order_id'] ?? ''}'.trim();
  if (oid.isEmpty) return;
  final before = await c.orderRow(oid);
  final ref = await c.refundOrder(oid);
  final after = await c.orderRow(oid);
  c.note('happy.refund_before_ship', 'refund em pago (não partir)', {
    'before': before?['status'],
    'refund': ref.brief,
    'after': after,
  }, lens: 'Y1');
  if (!(ref.ok && (ref.map?['ok'] == true || ref.map?['already_refunded'] == true)) &&
      after?['stripe_refund_id'] == null) {
    c.finding(
      id: 'RTY-REG-001',
      lens: 'Y1',
      severity: 'P2',
      title: 'Regressão: refund antes de enviar falhou',
      actor: 'seller JWT',
      pre: 'pago, shipped_at null',
      repro: 'POST refund-order',
      expected: 'ok refund Stripe + cancelado',
      obtained: {'refund': ref.brief, 'after': after},
    );
  } else {
    c.closedPath('happy.refund_before_ship', 'refund pré-envio OK', after,
        lens: 'Y1');
  }
}
