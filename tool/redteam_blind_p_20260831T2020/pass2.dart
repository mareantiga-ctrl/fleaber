/// PASS 2 — cadeias que o Pass 1 não isolou (preço sem product spoof, unlist sem sold,
/// refund∥release no comprador, saco IDs, disputa, credit RPC, qty).
import 'dart:io';

import '_rtp.dart';

num? numOf(dynamic v) {
  if (v is num) return v;
  return num.tryParse('$v');
}

void main() async {
  final env = loadEnv();
  final c = Rtp.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.wallets();
  c.note('p2.w0', 'wallets', w0, lens: 'P10');

  // ---- P3: hold 8,50 → price 1,00 → checkout SEM product_id alheio ----
  final pid = await c.createProduct(title: '$prefix p2-price', qty: 3, price: 8.5);
  final oid = await c.insertOrder(
    productId: pid ?? '',
    jwt: c.buyerJwt,
    price: 8.5,
    shipping: 'entrega em mão',
  );
  await c.rest('PATCH', 'products?id=eq.$pid', jwt: c.sellerJwt, body: {'price': 1.0});
  final prodAfter = await c.productRow(pid ?? '');
  final ck = await c.checkout(orderId: oid ?? '', amount: 50, shipping: 'mao');
  final amt = numOf(ck.map?['amount_total'] ?? ck.map?['server_amount_cents']);
  c.note('p2.p3.price', 'checkout após price=1 (produto coerente)', {
    'order': oid,
    'product_price': prodAfter?['price'],
    'http': ck.brief,
    'amount': amt,
    'sid': ck.map?['checkoutSessionId'],
  }, lens: 'P3');
  // Itens 8,50 + prot ~108 → ~958. Itens 1,00 + prot ~70 → ~170.
  if (ck.ok && amt != null && amt < 400) {
    c.hold(
      id: 'RTP-P3-004',
      lens: 'P3',
      severity: 'P1',
      title: 'Seller baixa preço depois do hold e Stripe cobra o novo',
      actor: 'seller PATCH price + buyer checkout',
      pre: 'hold 8,50 €; product.price→1,00; checkout sem product spoof',
      repro: 'checkout $oid amount=$amt (esperado ~958¢ contrato)',
      expected: 'contract_unit selado ~8,50 + protecção',
      obtained: ck.map,
      evidence: {'product': prodAfter, 'order': oid},
    );
  }

  // ---- P3: unlist SEM is_sold ----
  final pidUl = await c.createProduct(title: '$prefix p2-ul', qty: 2, price: 8.5);
  final oidUl = await c.insertOrder(productId: pidUl ?? '', jwt: c.buyerJwt, price: 8.5);
  await c.rest('PATCH', 'products?id=eq.$pidUl', jwt: c.sellerJwt, body: {
    'list_on_marketplace': false,
  });
  final ckUl = await c.checkout(orderId: oidUl ?? '');
  c.note('p2.p3.unlist', 'unlist sem sold → checkout', {
    'http': ckUl.brief,
    'sid': ckUl.map?['checkoutSessionId'],
    'amount': ckUl.map?['amount_total'],
  }, lens: 'P3');
  if (ckUl.ok && ckUl.map?['checkoutSessionId'] != null) {
    c.hold(
      id: 'RTP-P3-005',
      lens: 'P3',
      severity: 'P1',
      title: 'Hold + unlist (ainda não sold) abre Session Stripe',
      actor: 'seller unlist + buyer checkout',
      pre: 'list_on_marketplace=false, is_sold inalterado',
      repro: 'checkout $oidUl',
      expected: 'recusa (fora da montra)',
      obtained: ckUl.map,
    );
  }

  // ---- P3: qty 1 hold → PATCH qty 5 → checkout amount ----
  final pidQty = await c.createProduct(title: '$prefix p2-qty', qty: 9, price: 8.5);
  final oidQty = await c.insertOrder(
    productId: pidQty ?? '',
    jwt: c.buyerJwt,
    price: 8.5,
    qty: 1,
  );
  final patchQty = await c.rest(
    'PATCH',
    'orders?id=eq.$oidQty',
    jwt: c.buyerJwt,
    body: {'quantity': 5, 'price_total': 42.5},
  );
  final ckQty = await c.checkout(orderId: oidQty ?? '');
  final amtQty = numOf(ckQty.map?['amount_total'] ?? ckQty.map?['server_amount_cents']);
  final rowQty = await c.orderRow(oidQty ?? '');
  c.note('p2.p3.qty', 'PATCH qty 1→5 + checkout', {
    'patch': patchQty.brief,
    'row_qty': rowQty?['quantity'],
    'checkout': ckQty.brief,
    'amount': amtQty,
  }, lens: 'P3');
  if (patchQty.ok &&
      (rowQty?['quantity'] == 5) &&
      ckQty.ok &&
      amtQty != null &&
      amtQty > 2000) {
    c.hold(
      id: 'RTP-P3-006',
      lens: 'P3',
      severity: 'P1',
      title: 'Buyer inflaciona qty depois do hold e Stripe cobra 5×',
      actor: 'buyer JWT',
      pre: 'hold qty=1; PATCH quantity=5',
      repro: 'checkout $oidQty amount=$amtQty',
      expected: 'qty selada / PATCH recusado',
      obtained: {'row': rowQty, 'amount': amtQty},
    );
  }

  // ---- P9: credit_wallet_once assinatura real ----
  final credit = await c.rpc('batata_credit_wallet_once', {
    'p_wallet_id': c.buyerId,
    'p_order_id': oid,
    'p_amount': 50,
    'p_type': 'venda',
    'p_description': '$prefix mint',
  }, jwt: c.buyerJwt);
  final creditAnon = await c.rpc('batata_credit_wallet_once', {
    'p_wallet_id': c.buyerId,
    'p_order_id': oid,
    'p_amount': 50,
    'p_type': 'venda',
    'p_description': '$prefix anon',
  });
  c.note('p2.p9.credit', 'credit_wallet_once JWT/anon', {
    'jwt': credit.brief,
    'anon': creditAnon.brief,
  }, lens: 'P9');
  final wCredit = await c.wallets();
  if ((credit.ok && credit.json == true) ||
      ((wCredit['buyer'] ?? 0) - (w0['buyer'] ?? 0) > 0.01)) {
    c.hold(
      id: 'RTP-P9-002',
      lens: 'P9',
      severity: 'P0',
      title: 'JWT/anon executa batata_credit_wallet_once e minta',
      actor: 'buyer JWT',
      pre: 'w0=${w0['buyer']}',
      repro: 'rpc batata_credit_wallet_once 50€',
      expected: 'REVOKE authenticated',
      obtained: {'rpc': credit.brief, 'w': wCredit},
    );
  }

  // ---- P8 tip amount válido ----
  final tip = await c.edge('create-live-tip-checkout', {
    'seller_id': c.seller2Id,
    'amount_eur': 2.0,
    'live_id': '00000000-0000-0000-0000-000000000001',
  }, jwt: c.buyerJwt);
  c.note('p2.p8.tip', 'tip 2€ seller2 live forjado', tip.brief, lens: 'P8');
  if (tip.ok && tip.map?['checkoutSessionId'] != null) {
    c.hold(
      id: 'RTP-P8-001',
      lens: 'P8',
      severity: 'P1',
      title: 'Tip Checkout Session para seller/live forjados',
      actor: 'buyer JWT',
      pre: 'seller_id=seller2, live_id uuid lixo, 2€',
      repro: 'create-live-tip-checkout',
      expected: 'recusa (live inexistente / seller mismatch)',
      obtained: tip.map,
    );
  }

  // ---- P5: pago (não concluido) refund ∥ release buyer ----
  final paid = await c.e2e('setup_paid_order', {'initial_qty': 2});
  final paidOid = c.parseE2eOrderId(paid);
  c.note('p2.p5.paid', 'pago Stripe TEST (fica pago)', paid.brief, lens: 'P5');
  if (paidOid != null) {
    c.createdOrderIds.add(paidOid);
    final wP = await c.wallets();
    final raced = await Future.wait([
      c.edge('refund-order', {'order_id': paidOid}, jwt: c.sellerJwt),
      c.rpc('batata_release_seller_wallet_for_order', {'p_order_id': paidOid},
          jwt: c.buyerJwt),
      c.rpc('batata_refund_buyer_wallet_for_order', {'p_order_id': paidOid},
          jwt: c.buyerJwt),
    ]);
    final after = await c.orderRow(paidOid);
    final w1 = await c.wallets();
    c.note('p2.p5.race.pago', 'refund∥release∥refund-wallet em pago', {
      'ref': raced[0].brief,
      'rel': raced[1].brief,
      'refW': raced[2].brief,
      'status': after?['status'],
      'refund_id': after?['stripe_refund_id'],
      'release_at': after?['wallet_release_processed_at'],
      'dBuyer': (w1['buyer'] ?? 0) - (wP['buyer'] ?? 0),
      'dSeller': (w1['seller'] ?? 0) - (wP['seller'] ?? 0),
    }, lens: 'P5');
    final dS = (w1['seller'] ?? 0) - (wP['seller'] ?? 0);
    final refunded = (after?['stripe_refund_id'] ?? '').toString().isNotEmpty;
    if (refunded && dS > 0.01) {
      c.hold(
        id: 'RTP-P5-002',
        lens: 'P5+P10',
        severity: 'P0',
        title: 'Em pago: Stripe refund + wallet seller no mesmo instante',
        actor: 'seller refund-order ∥ buyer release',
        pre: 'setup_paid_order $paidOid status=pago',
        repro: 'Future.wait refund-order + release',
        expected: 'refund OU release, não os dois com Δseller>0',
        obtained: after,
      );
    }

    // Disputa na order (se ainda paga) + refund
    final disp = await c.rest('POST', 'order_disputes', jwt: c.buyerJwt, body: {
      'order_id': paidOid,
      'buyer_id': c.buyerId,
      'reason': 'outro',
      'description': '$prefix chain',
    });
    c.note('p2.p5.disp', 'INSERT order_disputes', disp.brief, lens: 'P5');
    final refD = await c.edge('refund-order', {'order_id': paidOid}, jwt: c.sellerJwt);
    c.note('p2.p5.ref.disp', 'refund após disputa', refD.brief, lens: 'P5');
  }

  // ---- P5b: concluido + release pelo COMPRADOR (a RPC exige buyer) ----
  final paid2 = await c.e2e('setup_paid_order', {'initial_qty': 2});
  final oid2 = c.parseE2eOrderId(paid2);
  c.note('p2.p5b.paid', '2.º pago para concluido+release buyer', paid2.brief, lens: 'P5');
  if (oid2 != null) {
    c.createdOrderIds.add(oid2);
    await c.rest('PATCH', 'orders?id=eq.$oid2', jwt: c.sellerJwt, body: {
      'shipping_method': 'entrega em mão',
    });
    await c.rest('PATCH', 'orders?id=eq.$oid2', jwt: c.sellerJwt, body: {
      'status': 'enviado',
    });
    await c.rest('PATCH', 'orders?id=eq.$oid2', jwt: c.buyerJwt, body: {
      'status': 'concluido',
    });
    final wB = await c.wallets();
    final rel = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oid2},
      jwt: c.buyerJwt,
    );
    final rel2 = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oid2},
      jwt: c.buyerJwt,
    );
    final refAfter = await c.edge('refund-order', {'order_id': oid2}, jwt: c.sellerJwt);
    final after2 = await c.orderRow(oid2);
    final wA = await c.wallets();
    c.note('p2.p5b.release', 'buyer release ×2 + refund', {
      'rel1': rel.brief,
      'rel2': rel2.brief,
      'refund': refAfter.brief,
      'dSeller': (wA['seller'] ?? 0) - (wB['seller'] ?? 0),
      'dBuyer': (wA['buyer'] ?? 0) - (wB['buyer'] ?? 0),
      'release_at': after2?['wallet_release_processed_at'],
      'refund_id': after2?['stripe_refund_id'],
    }, lens: 'P5');
    final dSeller = (wA['seller'] ?? 0) - (wB['seller'] ?? 0);
    if (rel.json == true && rel2.json == true && dSeller > 8) {
      c.hold(
        id: 'RTP-P5-003',
        lens: 'P5',
        severity: 'P0',
        title: 'Release buyer JWT duas vezes credita seller 2×',
        actor: 'buyer JWT',
        pre: 'concluido $oid2',
        repro: 'rpc release ×2',
        expected: '2.ª chamada false / Δ uma vez',
        obtained: {'dSeller': dSeller, 'rel1': rel.brief, 'rel2': rel2.brief},
      );
    }
  }

  // ---- P7 saco: IDs correctos + refund A + estado B + Stripe refunds ----
  final bag = await c.e2e('setup_paid_bag', {});
  final bm = bag.map ?? {};
  final oa = bm['order_a_id']?.toString();
  final ob = bm['order_b_id']?.toString();
  final pi = bm['payment_intent_id']?.toString();
  c.note('p2.p7.bag', 'bag ids', {
    'ok': bm['ok'],
    'oa': oa,
    'ob': ob,
    'pi': pi,
    'paid_a': bm['paid_a'],
    'paid_b': bm['paid_b'],
    'pi_cents': bm['pi_amount_cents'],
  }, lens: 'P7');
  if (oa != null && ob != null) {
    final rowA0 = await c.orderRow(oa);
    final rowB0 = await c.orderRow(ob);
    final refA = await c.edge('refund-order', {'order_id': oa}, jwt: c.sellerJwt);
    final rowA1 = await c.orderRow(oa);
    final rowB1 = await c.orderRow(ob);
    final listed = await c.e2e('list_stripe_refunds', {'payment_intent_id': pi});
    c.note('p2.p7.refA', 'refund A; B e PI', {
      'ref': refA.brief,
      'A0': {
        'st': rowA0?['status'],
        'paid': rowA0?['amount_paid_cents'],
        'rid': rowA0?['stripe_refund_id']
      },
      'A1': {
        'st': rowA1?['status'],
        'paid': rowA1?['amount_paid_cents'],
        'rid': rowA1?['stripe_refund_id']
      },
      'B0': {
        'st': rowB0?['status'],
        'paid': rowB0?['amount_paid_cents'],
        'rid': rowB0?['stripe_refund_id']
      },
      'B1': {
        'st': rowB1?['status'],
        'paid': rowB1?['amount_paid_cents'],
        'rid': rowB1?['stripe_refund_id']
      },
      'stripe': listed.map,
    }, lens: 'P7');
    final bKilled = (rowB1?['status'] ?? '').toString().toLowerCase() != 'pago' &&
        (rowB0?['status'] ?? '').toString().toLowerCase() == 'pago';
    final refundCount = numOf(listed.map?['refund_count']) ?? 0;
    final piAmt = numOf(bm['pi_amount_cents']) ?? 1115;
    var refundSum = 0;
    final refunds = listed.map?['refunds'];
    if (refunds is List) {
      for (final r in refunds) {
        if (r is Map) refundSum += (r['amount'] as num?)?.toInt() ?? 0;
      }
    }
    if (bKilled) {
      c.hold(
        id: 'RTP-P7-002',
        lens: 'P7',
        severity: 'P1',
        title: 'Refund da linha A derruba a linha B do saco',
        actor: 'seller refund-order A',
        pre: 'bag pago A+B PI $pi',
        repro: 'refund-order $oa',
        expected: 'B continua pago',
        obtained: {'B1': rowB1, 'A1': rowA1},
      );
    }
    if (refundSum > piAmt + 1) {
      c.hold(
        id: 'RTP-P7-003',
        lens: 'P7',
        severity: 'P0',
        title: 'Refunds Stripe do saco > captura do PI',
        actor: 'seller refund-order A',
        pre: 'PI $pi amount=$piAmt',
        repro: 'list_stripe_refunds sum=$refundSum',
        expected: 'sum refunds ≤ PI',
        obtained: listed.map,
      );
    }
    c.note('p2.p7.sums', 'refundSum vs PI', {
      'refundSum': refundSum,
      'piAmt': piAmt,
      'refundCount': refundCount,
    }, lens: 'P7');
  }

  // ---- P2 sequential stock=1 ----
  final pid1 = await c.createProduct(title: '$prefix p2-stk1', qty: 1, price: 8.5);
  final ins1 = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pid1,
    'price_total': 8.5,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  final ins2 = await c.rest('POST', 'orders', jwt: c.buyer2Jwt, body: {
    'buyer_id': c.buyer2Id,
    'seller_id': c.sellerId,
    'product_id': pid1,
    'price_total': 8.5,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  c.note('p2.p2.seq', 'holds sequenciais qty=1', {
    'b1': ins1.brief,
    'b2': ins2.brief,
    'id1': ins1.firstId,
    'id2': ins2.firstId,
  }, lens: 'P2');
  if (ins1.ok && ins2.ok && ins1.firstId != null && ins2.firstId != null) {
    final ck1 = await c.checkout(orderId: ins1.firstId!, jwt: c.buyerJwt, buyer: c.buyerId);
    final ck2 = await c.checkout(
        orderId: ins2.firstId!, jwt: c.buyer2Jwt, buyer: c.buyer2Id);
    c.note('p2.p2.ck', 'checkout 2 holds qty=1', {
      'c1': ck1.brief,
      'c2': ck2.brief,
    }, lens: 'P2');
    if (ck1.ok &&
        ck2.ok &&
        ck1.map?['checkoutSessionId'] != null &&
        ck2.map?['checkoutSessionId'] != null) {
      c.hold(
        id: 'RTP-P2-002',
        lens: 'P2',
        severity: 'P1',
        title: 'Qty=1: dois holds persistidos e duas Sessions',
        actor: 'buyer + buyer2',
        pre: 'product qty=1',
        repro: '${ins1.firstId} + ${ins2.firstId}',
        expected: '2.º INSERT ou 2.º checkout recusado',
        obtained: {'c1': ck1.map, 'c2': ck2.map},
      );
    }
  }

  final wEnd = await c.wallets();
  c.note('p2.wEnd', 'wallets', {'w0': w0, 'wEnd': wEnd}, lens: 'P10');

  await dumpJson('${outDir()}/pass2.json', {
    'pass': 2,
    'findings': c.findings,
    'notes': c.notes,
    'w0': w0,
    'wEnd': wEnd,
  });
  stdout.writeln('PASS2 FINDINGS ${c.findings.length}');
  for (final f in c.findings) {
    stdout.writeln('  ${f['severity']} ${f['id']} ${f['title']}');
  }
}
