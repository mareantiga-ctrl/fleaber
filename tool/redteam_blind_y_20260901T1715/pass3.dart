// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import '_rty.dart';

/// Pass 3 — liquidar quote hostil (Stripe TEST / e2e settle) + hop re-checkout + disputa.
Future<void> main() async {
  final c = Rty.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();

  await hopRecheckout(c);
  await liquidateBundleExtraQty(c);
  await disputeCorrectSchema(c);
  await ghostHold(c);

  await dumpJson('${outDir()}/pass3.json', {
    'prefix': prefix,
    'findings': c.findings,
    'closed': c.closed,
    'notes': c.notes,
  });
  stdout.writeln(
      'PASS3 DONE findings=${c.findings.length} closed=${c.closed.length}');
}

Future<Map<String, dynamic>?> paidFixture(Rty c) async {
  final h = await c.setupPaidOrder();
  final oid = '${h.map?['order_id'] ?? ''}'.trim();
  if (oid.isEmpty) return null;
  c.createdOrderIds.add(oid);
  await c.rest('PATCH', 'orders?id=eq.$oid', service: true, body: {
    'shipping_method': 'mao',
    'payment_method': 'pagamento na app',
  }, prefer: 'return=minimal');
  return h.map;
}

Future<void> hopRecheckout(Rty c) async {
  final fx = await paidFixture(c);
  final oid = '${fx?['order_id'] ?? ''}'.trim();
  if (oid.isEmpty) return;
  final before = await c.orderRow(oid);
  final prodBefore = await c.rest(
    'GET',
    'products?id=eq.${before?['product_id']}&select=id,quantity,is_sold',
    service: true,
  );
  final hop = await c.rest('PATCH', 'orders?id=eq.$oid',
      jwt: c.sellerJwt, body: {'status': 'reserva_pendente'});
  final mid = await c.orderRow(oid);
  final q = await c.checkout(orderId: oid);
  c.note('Y8.hop_recheckout', 'pago→RP→checkout', {
    'before': before,
    'hop': hop.brief,
    'mid': mid,
    'quote': q.brief,
    'prod_before': prodBefore.map,
  }, lens: 'Y8');

  final newCs = '${q.map?['checkoutSessionId'] ?? ''}';
  final oldPi = '${before?['stripe_payment_intent_id'] ?? ''}';
  if (q.ok && newCs.startsWith('cs_')) {
    final sidOnOrder = '${(await c.orderRow(oid))?['stripe_checkout_session_id']}';
    c.finding(
      id: 'RTY-Y8-010',
      lens: 'Y8',
      severity: 'P1',
      title: 'Order já capturada: hop para reserva_pendente permite nova Checkout Session',
      actor: 'seller JWT + buyer checkout',
      pre: 'Stripe TEST pago amount_paid_cents>0 PI=$oldPi',
      repro: 'PATCH status=reserva_pendente → POST create-payment-intent',
      expected: 'checkout blocked: already captured / pago',
      obtained: {
        'new_cs': newCs,
        'sid_on_order': sidOnOrder,
        'old_pi': oldPi,
        'status': mid?['status'],
        'amount_paid_cents': mid?['amount_paid_cents'],
      },
      impact: '2.ª captura possível sobre a mesma linha; stock pode re-aplicar',
    );

    // Tentar pagar a 2.ª session (fixture Stripe TEST)
    if (c.stripeSk != null) {
      final sess = await c.stripeForm('GET', 'checkout/sessions/$newCs');
      final pi = '${sess.map?['payment_intent'] ?? ''}';
      c.note('Y8.sess2', 'stripe session', sess.brief, lens: 'Y8');
      HttpHit? confirm;
      if (pi.startsWith('pi_')) {
        confirm = await c.stripeForm('POST', 'payment_intents/$pi/confirm', {
          'payment_method': 'pm_card_visa',
        });
        c.note('Y8.confirm2', 'confirm PI2', confirm.brief, lens: 'Y8');
      }
      final settle = await c.edge(
        'create-payment-intent',
        method: 'GET',
        qs: '?checkout_return=success&session_id=$newCs',
        jwt: c.buyerJwt,
      );
      final after = await c.orderRow(oid);
      final tx = await c.rest(
        'GET',
        'wallet_transactions?order_id=eq.$oid&select=wallet_id,amount,type,description',
        service: true,
      );
      c.note('Y8.after_second', 'após 2.º pay/settle', {
        'settle': settle.brief,
        'order': after,
        'tx': tx.brief,
        'confirm': confirm?.brief,
      }, lens: 'Y8');
      final pi2paid = confirm != null &&
          (confirm.map?['status'] == 'succeeded' ||
              '${confirm.map?['error']}' == '');
      if (after?['stripe_payment_intent_id'] != null &&
          '${after?['stripe_payment_intent_id']}' != oldPi &&
          oldPi.isNotEmpty) {
        c.finding(
          id: 'RTY-Y8-011',
          lens: 'Y8',
          severity: 'P0',
          title: '2.ª captura substitui PI; PI original pode ficar órfão (dinheiro Stripe líquido)',
          actor: 'B1 checkout após hop S1',
          pre: 'PI1 succeeded + hop RP + Session2',
          repro: 'pagar cs_ nova / settle GET',
          expected: 'recusar 2.ª Session ou refund órfão PI1',
          obtained: {
            'pi1': oldPi,
            'pi2': after?['stripe_payment_intent_id'],
            'status': after?['status'],
            'amount_paid': after?['amount_paid_cents'],
          },
        );
      } else if (pi2paid) {
        c.note('Y8.pi2', 'confirm result without PI swap', confirm?.brief,
            lens: 'Y8');
      }
    }
  } else if (!q.ok) {
    c.closedPath('Y8.hop_recheckout', 'checkout recusou order capturada', q,
        lens: 'Y8');
  }
}

Future<void> liquidateBundleExtraQty(Rty c) async {
  final pa = await c.insertProduct(title: '$prefix liqA', qty: 8, price: 20);
  final pb = await c.insertProduct(title: '$prefix liqB', qty: 8, price: 20);
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
  final oa = await c.insertOrder(productId: pa, qty: 3, bundleId: bid);
  final ob = await c.insertOrder(productId: pb, qty: 1, bundleId: bid);
  if (oa == null || ob == null) return;
  final q = await c.checkout(bag: true, bagLines: [
    {'order_id': oa},
    {'order_id': ob},
  ]);
  final cents =
      int.tryParse('${q.map?['server_amount_cents'] ?? q.map?['amount_total'] ?? ''}');
  final cs = '${q.map?['checkoutSessionId'] ?? ''}';
  c.note('Y2.liq.quote', 'bag extra qty', {
    'cents': cents,
    'cs': cs,
    'q': q.brief,
  }, lens: 'Y2');
  if (!q.ok || cents == null || cents >= 4000) {
    c.closedPath('Y2.liq', 'já não subcota', q, lens: 'Y2');
    return;
  }

  final stockA0 = await c.rest(
    'GET',
    'products?id=eq.$pa&select=quantity',
    service: true,
  );
  final stockB0 = await c.rest(
    'GET',
    'products?id=eq.$pb&select=quantity',
    service: true,
  );
  final wa0 = await c.walletBal(c.buyerId!);
  final ws0 = await c.walletBal(c.sellerId!);

  // Fixture: PI TEST no montante que o Edge quotou (o exploit é o quote JWT).
  final pi = await c.stripeForm('POST', 'payment_intents', {
    'amount': '$cents',
    'currency': 'eur',
    'confirm': 'true',
    'payment_method': 'pm_card_visa',
    'automatic_payment_methods[enabled]': 'true',
    'automatic_payment_methods[allow_redirects]': 'never',
    'metadata[fleaber_order_id]': oa,
    'metadata[rty]': prefix,
  });
  final piId = '${pi.map?['id'] ?? ''}';
  c.note('Y2.liq.pi', 'PI TEST no quote hostil', pi.brief, lens: 'Y2');
  if (!piId.startsWith('pi_')) {
    c.note('Y2.liq.no_pi', 'não criou PI', pi.brief, lens: 'Y2');
    return;
  }

  final settle = await c.edge(
    'create-payment-intent',
    qs: '?fase2_e2e_settle=1',
    service: true,
    extra: {
      if (c.crashSecret != null) 'x-fleaber-e2e-secret': c.crashSecret!,
    },
    body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'payment_intent_id': piId,
      'session_id': cs,
      'bag_checkout': true,
      'bag_lines': [
        {'order_id': oa},
        {'order_id': ob},
      ],
    },
  );
  final ra = await c.orderRow(oa);
  final rb = await c.orderRow(ob);
  final stockA1 = await c.rest(
    'GET',
    'products?id=eq.$pa&select=quantity,is_sold',
    service: true,
  );
  final stockB1 = await c.rest(
    'GET',
    'products?id=eq.$pb&select=quantity,is_sold',
    service: true,
  );
  final wa1 = await c.walletBal(c.buyerId!);
  final ws1 = await c.walletBal(c.sellerId!);
  c.note('Y2.liq.settle', 'e2e settle bag', {
    'settle': settle.brief,
    'oa': ra,
    'ob': rb,
    'stockA0': stockA0.map,
    'stockA1': stockA1.map,
    'stockB0': stockB0.map,
    'stockB1': stockB1.map,
    'wallet_b': [wa0, wa1],
    'wallet_s': [ws0, ws1],
    'pi_amount': cents,
    'invariant': settle.map?['invariant_sum_eq_pi'],
  }, lens: 'Y2');

  final appliedA = ra?['stock_units_applied'];
  final appliedB = rb?['stock_units_applied'];
  final paidA = ra?['amount_paid_cents'];
  final paidB = rb?['amount_paid_cents'];
  final qtyA0 = stockA0.map?['quantity'];
  final qtyA1 = stockA1.map?['quantity'];
  final bothPago =
      '${ra?['status']}' == 'pago' && '${rb?['status']}' == 'pago';
  if (bothPago &&
      (appliedA == 3 || ra?['quantity'] == 3) &&
      cents < 4000) {
    c.finding(
      id: 'RTY-Y2-001L',
      lens: 'Y2',
      severity: 'P0',
      title: 'Liquidação: 4 unidades a preço de conjunto de 2 (Stripe TEST)',
      actor: 'buyer JWT (quote) + settle fixture',
      pre: 'bundle total 20€; orders qty 3+1; quote $cents cêntimos',
      repro:
          'bag create-payment-intent → PI TEST amount=quote → fase2_e2e_settle bag',
      expected: 'recusar qty extra ou cobrar 80€+taxas; stock 3+1 só se pago ~80€',
      obtained: {
        'pi': piId,
        'pi_cents': cents,
        'oa': ra,
        'ob': rb,
        'stockA': [qtyA0, qtyA1],
        'applied': [appliedA, appliedB],
        'paid_cents': [paidA, paidB],
        'settle': settle.brief,
      },
      impact:
          'Captura Stripe ~21.65€ vs 4 un. a 20€; stock desce 3+1',
      evidence: {
        'wallet_buyer': [wa0, wa1],
        'wallet_seller': [ws0, ws1],
      },
    );
  } else {
    c.closedPath('Y2.liq.settle', 'não liquidou 3+1 a preço de 2', {
      'bothPago': bothPago,
      'appliedA': appliedA,
      'settle': settle.brief,
    }, lens: 'Y2');
  }
}

Future<void> disputeCorrectSchema(Rty c) async {
  final fx = await paidFixture(c);
  final oid = '${fx?['order_id'] ?? ''}'.trim();
  if (oid.isEmpty) return;
  final d = await c.rest('POST', 'order_disputes', jwt: c.buyerJwt, body: {
    'order_id': oid,
    'buyer_id': c.buyerId,
    'reason': 'outro',
    'description': prefix,
    'status': 'aberta',
  });
  c.note('Y5.disp2', 'insert disputa schema', d, lens: 'Y5');
  final did = d.firstId;
  if (did == null) {
    c.closedPath('Y5.disp.insert', 'não criou disputa em pago', d, lens: 'Y5');
    return;
  }
  final offer = await c.rest('PATCH', 'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {
        'seller_refund_percent': 40,
        'seller_offer_type': 'partial_refund',
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
  c.note('Y5.disp2.rpc', 'partial', {
    'offer': offer.brief,
    'rpc': wr.brief,
    'tx': tx.brief,
    'row': row,
  }, lens: 'Y5');
  final minted = tx.list.any((e) => e is Map && '${e['type']}' == 'reembolso');
  if (minted) {
    c.finding(
      id: 'RTY-Y5-010',
      lens: 'Y5',
      severity: 'P0',
      title: 'Disputa parcial minta wallet em pago Stripe sem refund cartão',
      actor: 'B1+S1',
      pre: 'captura Stripe, disputa aberta, offer 40%',
      repro: 'POST order_disputes + PATCH offer + rpc process_partial_refund_dispute',
      expected: 'exige stripe_refund residual ou bloqueia plataforma capturada',
      obtained: {'rpc': wr.brief, 'tx': tx.brief, 'order': row},
    );
  } else {
    c.closedPath('Y5.disp2.mint', 'não mintou', wr, lens: 'Y5');
  }
  final ref = await c.refundOrder(oid);
  if (d.ok &&
      ref.ok &&
      ref.map?['ok'] == true &&
      '${ref.map?['code']}' != 'order_refund_blocked_open_dispute') {
    c.finding(
      id: 'RTY-Y5-011',
      lens: 'Y5',
      severity: 'P1',
      title: 'refund-order ignora disputa aberta em pago',
      actor: 'seller JWT',
      pre: 'disputa aberta',
      repro: 'POST refund-order',
      expected: '403 open_dispute',
      obtained: ref,
    );
  } else {
    c.closedPath('Y5.disp2.refund', 'refund vs disputa', ref, lens: 'Y5');
  }
}

Future<void> ghostHold(Rty c) async {
  final p = await c.insertProduct(title: '$prefix ghost', qty: 1, price: 11);
  if (p == null) return;
  final o1 = await c.insertOrder(productId: p, qty: 1);
  final o2 = await c.insertOrder(productId: p, qty: 1);
  c.note('Y4.two_holds', 'stock=1 duas orders', {
    'o1': o1,
    'o2': o2,
    'r1': o1 != null ? await c.orderRow(o1) : null,
    'r2': o2 != null ? await c.orderRow(o2) : null,
  }, lens: 'Y4');
  if (o1 != null && o2 != null) {
    final q1 = await c.checkout(orderId: o1);
    final q2 = await c.checkout(orderId: o2);
    c.note('Y4.two_checkout', 'duas sessions stock=1', {
      'q1': q1.brief,
      'q2': q2.brief,
    }, lens: 'Y4');
    if (q1.ok && q2.ok) {
      c.finding(
        id: 'RTY-Y4-001',
        lens: 'Y4',
        severity: 'P1',
        title: 'Stock=1: duas Checkout Sessions abertas',
        actor: 'buyer JWT',
        pre: 'produto quantity=1, duas reserva_pendente',
        repro: '2× POST orders qty=1 + 2× create-payment-intent',
        expected: '2.ª order ou 2.º checkout bloqueado',
        obtained: {
          'cs1': q1.map?['checkoutSessionId'],
          'cs2': q2.map?['checkoutSessionId'],
        },
      );
    } else {
      c.closedPath('Y4.two_checkout', '2.º checkout/order recusado', {
        'q1': q1.brief,
        'q2': q2.brief,
        'o2': o2,
      }, lens: 'Y4');
    }
  } else if (o2 == null) {
    c.closedPath('Y4.second_order', '2.ª order stock=1 recusada', 'no o2',
        lens: 'Y4');
  }
}
