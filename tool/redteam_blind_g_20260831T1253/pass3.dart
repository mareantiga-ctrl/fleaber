/// PASS 3 — G3 replay · G4 ordem invertida · Stripe TEST pago · refund race.
import 'dart:io';
import '_rtg.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rtg.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();

  final out = <String, Object?>{'pass': 3, 'prefix': prefix};
  final w0 = await c.wallets();
  out['wallets_before'] = w0;

  // ---- G2-003 follow-up: checkout on hold that won vs sold+unlist ----
  const ghostOid = '3390f39c-9c9f-43c6-9c8e-8b55850b56b7';
  final ghostPay = await c.edge('create-payment-intent', {
    'order_id': ghostOid,
    'buyer_id': c.buyerId,
    'shipping_method': 'entrega em mão',
  }, jwt: c.buyerJwt);
  c.note('p3.g2.ghost_checkout', 'checkout hold vs sold+unlist', ghostPay.brief,
      lens: 'G2');
  if (ghostPay.ok && ghostPay.map?['checkoutUrl'] != null) {
    c.hold(
      id: 'RTG-G2-003b',
      lens: 'G2',
      severity: 'P1',
      title: 'Checkout Session abre para hold criado em corrida com SKU sold+unlist',
      actor: 'buyer JWT',
      pre: 'order 3390f39c reserva_pendente; product is_sold+unlisted',
      repro: 'POST create-payment-intent',
      expected: 'Checkout blocked: not listed / sold',
      obtained: ghostPay.brief,
    );
  }

  // ---- Seller cancel hold isolation ----
  final pCan = await c.insertProduct(title: '$prefix seller-cancel', qty: 1);
  final oCan = await c.insertOrder(productId: pCan!, jwt: c.buyerJwt);
  final cancelS = await c.rest(
    'PATCH',
    'orders?id=eq.$oCan',
    jwt: c.sellerJwt,
    body: {'status': 'cancelado'},
  );
  final cancelB = await c.rest(
    'PATCH',
    'orders?id=eq.$oCan',
    jwt: c.buyerJwt,
    body: {'status': 'cancelado'},
  );
  final afterCan = await c.orderRow(oCan!);
  c.note('p3.g6.cancel_hold', 'seller/buyer cancel hold', {
    'seller': cancelS.brief,
    'buyer': cancelB.brief,
    'row': afterCan,
  }, lens: 'G6');
  if (!cancelS.ok &&
      cancelS.body.contains('wallet_release') &&
      '${afterCan?['status']}'.toLowerCase().contains('pendente')) {
    c.hold(
      id: 'RTG-G6-006',
      lens: 'G6',
      severity: 'P1',
      title: 'Seller não consegue cancelar hold (trigger wallet_release em reserva_pendente)',
      actor: 'seller JWT',
      pre: 'order reserva_pendente sem captura',
      repro: 'PATCH status=cancelado',
      expected: 'cancelado',
      obtained: {'http': cancelS.brief, 'buyer_cancel': cancelB.brief, 'row': afterCan},
    );
  }

  // ---- True G6: INSERT order AFTER listing price change (stale UI amount) ----
  final pNow = await c.insertProduct(
    title: '$prefix stale-insert',
    qty: 1,
    price: 99.0,
  );
  final insStale = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pNow,
    'price_total': 8.5,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  if (insStale.firstId != null) c.createdOrderIds.add(insStale.firstId!);
  c.note('p3.g6.stale_insert', 'POST order 8.50 em SKU 99€', insStale.brief,
      lens: 'G6');
  if (insStale.ok) {
    final payStale = await c.edge('create-payment-intent', {
      'order_id': insStale.firstId,
      'buyer_id': c.buyerId,
      'shipping_method': 'entrega em mão',
    }, jwt: c.buyerJwt);
    final cents = payStale.map?['server_amount_cents'];
    c.note('p3.g6.stale_insert_pay', 'checkout da order 8.50/SKU99', {
      'cents': cents,
      'pay': payStale.brief,
    }, lens: 'G6');
    final n = cents is num ? cents.round() : int.tryParse('$cents') ?? -1;
    if (payStale.ok && n > 0 && n < 5000) {
      c.hold(
        id: 'RTG-G6-007',
        lens: 'G6',
        severity: 'P1',
        title: 'POST order com price_total velho 8,50€ num SKU a 99€ e checkout honra o velho',
        actor: 'buyer JWT',
        pre: 'product.price=99; cliente envia 8.50',
        repro: 'POST orders price_total=8.5 → create-payment-intent',
        expected: 'seal ao preço de catálogo ou recusa',
        obtained: {
          'insert': insStale.brief,
          'cents': n,
          'pay': payStale.brief,
        },
      );
    }
  }

  // ---- G3: webhook without signature ----
  final wh = await c.edge('stripe-webhook', {
    'type': 'checkout.session.completed',
    'id': 'evt_rtg_replay',
    'data': {
      'object': {'id': 'cs_test_rtg', 'payment_status': 'paid'},
    },
  }, jwt: c.buyerJwt);
  c.note('p3.g3.wh_nosig', 'POST stripe-webhook sem stripe-signature', wh.brief,
      lens: 'G3');
  if (wh.ok) {
    c.hold(
      id: 'RTG-G3-001',
      lens: 'G3',
      severity: 'P0',
      title: 'stripe-webhook aceita replay sem assinatura Stripe',
      actor: 'buyer JWT',
      pre: 'sem header stripe-signature',
      repro: 'POST functions/v1/stripe-webhook body evento fake',
      expected: '400 invalid_signature',
      obtained: wh.brief,
    );
  }

  // ---- G3: GET settle unpaid / fake session ----
  final settleFake = await c.req(
    'GET',
    '/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_rtg_unpaid',
    jwt: c.buyerJwt,
  );
  c.note('p3.g3.settle_fake', 'GET settle cs fake', settleFake.brief, lens: 'G3');
  if (settleFake.ok &&
      (settleFake.body.toLowerCase().contains('pago') ||
          (settleFake.location ?? '').contains('stripe-success'))) {
    c.hold(
      id: 'RTG-G3-002',
      lens: 'G3',
      severity: 'P1',
      title: 'GET settle trata Session inexistente/não paga como sucesso',
      actor: 'buyer JWT',
      pre: 'cs_test_rtg_unpaid',
      repro: 'GET create-payment-intent?checkout_return=success&session_id=',
      expected: '400 / ainda não confirmado',
      obtained: settleFake.brief,
    );
  }

  // ---- G4: refund before pago ----
  final pPend = await c.insertProduct(title: '$prefix refund-prepay', qty: 2);
  final oPend = await c.insertOrder(productId: pPend!, jwt: c.buyerJwt);
  final rfPre = await c.edge('refund-order', {'order_id': oPend}, jwt: c.sellerJwt);
  c.note('p3.g4.refund_unpaid', 'refund hold não pago', rfPre.brief, lens: 'G4');
  final afterPre = await c.orderRow(oPend!);
  if (rfPre.ok && afterPre != null) {
    final st = '${afterPre['status']}'.toLowerCase();
    if (st.contains('cancel') || afterPre['stripe_refund_id'] != null) {
      c.note('p3.g4.refund_unpaid_okish', 'refund unpaid mudou estado', afterPre,
          lens: 'G4');
    }
  }

  // ---- G4: buyer PATCH concluido on unpaid ----
  final concUnpaid = await c.rest(
    'PATCH',
    'orders?id=eq.$oPend',
    jwt: c.buyerJwt,
    body: {'status': 'concluido'},
  );
  final afterConc = await c.orderRow(oPend);
  c.note('p3.g4.conc_unpaid', 'buyer concluido sem captura', concUnpaid.brief,
      lens: 'G4');
  if ('${afterConc?['status']}'.toLowerCase() == 'concluido') {
    c.hold(
      id: 'RTG-G4-001',
      lens: 'G4',
      severity: 'P1',
      title: 'Comprador marca concluido numa order ainda não paga',
      actor: 'buyer JWT',
      pre: 'reserva_pendente sem amount_paid',
      repro: 'PATCH status=concluido',
      expected: 'bloqueado',
      obtained: afterConc,
    );
  }

  // ---- Stripe TEST paid fixture (service_role = fixture, not actor) ----
  final paid = await c.e2e('setup_paid_order', {'initial_qty': 3});
  c.note('p3.fixture.paid', 'setup_paid_order', paid.brief, lens: 'G3');
  out['setup_paid'] = paid.map ?? paid.snippet;
  final paidMap = paid.map ?? {};
  final paidOrderId = (paidMap['order_id'] ??
          (paidMap['order'] is Map ? (paidMap['order'] as Map)['id'] : null))
      ?.toString();
  final paidProductId = paidMap['product_id']?.toString();
  final paidPi = (paidMap['payment_intent_id'] ??
          paidMap['pi_id'] ??
          (paidMap['payment_intent'] is Map
              ? (paidMap['payment_intent'] as Map)['id']
              : null))
      ?.toString();
  if (paidProductId != null) c.createdProductIds.add(paidProductId);
  if (paidOrderId != null) c.createdOrderIds.add(paidOrderId);

  Map<String, dynamic>? paidRow;
  if (paidOrderId != null) {
    paidRow = await c.orderRow(paidOrderId);
    out['paid_order'] = paidRow;
  }

  // ---- G3: GET settle replay on paid order if session exists ----
  final sid = paidRow?['stripe_checkout_session_id']?.toString();
  if (sid != null && sid.isNotEmpty) {
    final g1 = c.req(
      'GET',
      '/functions/v1/create-payment-intent?checkout_return=success&session_id=$sid',
      jwt: c.buyerJwt,
    );
    final g2 = c.req(
      'GET',
      '/functions/v1/create-payment-intent?checkout_return=success&session_id=$sid',
      jwt: c.buyerJwt,
    );
    final gs = await parallel([g1, g2]);
    final afterReplay = await c.orderRow(paidOrderId!);
    final wReplay = await c.wallets();
    c.note('p3.g3.settle_replay', 'GET settle 2× paralelo', {
      'a': gs[0].brief,
      'b': gs[1].brief,
      'order': afterReplay,
      'wallets': wReplay,
    }, lens: 'G3');
    final paidCents = afterReplay?['amount_paid_cents'];
    final n = paidCents is num ? paidCents : num.tryParse('$paidCents') ?? 0;
    if (n > (paidRow?['amount_paid_cents'] is num
            ? (paidRow!['amount_paid_cents'] as num)
            : 0) *
        1.5) {
      c.hold(
        id: 'RTG-G3-003',
        lens: 'G3',
        severity: 'P0',
        title: 'Replay GET settle duplica amount_paid / crédito',
        actor: 'buyer GET settle ∥',
        pre: 'order já pago',
        repro: '2× GET checkout_return=success',
        expected: 'idempotente, sem 2.º crédito',
        obtained: {'order': afterReplay, 'wallets': wReplay},
      );
    }
  } else {
    // Dedicated settle_get_replay fixture
    final replayFx = await c.e2e('settle_get_replay', {});
    c.note('p3.g3.settle_replay_fx', 'e2e settle_get_replay', replayFx.brief,
        lens: 'G3');
    out['settle_get_replay'] = replayFx.map ?? replayFx.snippet;
    final fx = replayFx.map ?? {};
    final fxOid = fx['order_id']?.toString();
    final fxPid = fx['product_id']?.toString();
    if (fxPid != null) c.createdProductIds.add(fxPid);
    if (fxOid != null) {
      c.createdOrderIds.add(fxOid);
      final fxRow = await c.orderRow(fxOid);
      final refunded = '${fxRow?['stripe_refund_id'] ?? ''}'.trim();
      final st = '${fxRow?['status']}'.toLowerCase();
      if (refunded.isNotEmpty && (st == 'pago' || st == 'cancelado')) {
        // refund on replay of already-paid is P0 if it voids a good sale
        if (st.contains('cancel')) {
          c.hold(
            id: 'RTG-G3-004',
            lens: 'G3',
            severity: 'P1',
            title: 'Replay settle anula venda já paga (refund/cancel)',
            actor: 'GET settle fixture',
            pre: 'order pago + replay GET',
            repro: 'sec-fase2-e2e-oversell probe settle_get_replay',
            expected: 'permanece pago, sem refund',
            obtained: fxRow,
          );
        }
      }
    }
  }

  // ---- G1: 2× refund-order paralelo na order paga ----
  if (paidOrderId != null &&
      '${paidRow?['status']}'.toLowerCase() == 'pago') {
    final extra = c.e2eSecret.isEmpty
        ? null
        : {
            'x-fleaber-crash-inject-secret': c.e2eSecret,
          };
    final rfs = await parallel([
      c.edge('refund-order', {'order_id': paidOrderId}, jwt: c.sellerJwt),
      c.edge('refund-order', {'order_id': paidOrderId}, jwt: c.sellerJwt,
          extra: extra),
    ]);
    final afterRf = await c.orderRow(paidOrderId);
    final w1 = await c.wallets();
    c.note('p3.g1.refund_parallel', '2× refund-order ∥', {
      'a': rfs[0].brief,
      'b': rfs[1].brief,
      'order': afterRf,
      'wallets': w1,
    }, lens: 'G1');
    // Stripe refunds list via fixture
    if (paidPi != null) {
      final listed = await c.e2e('list_stripe_refunds', {
        'payment_intent_id': paidPi,
      });
      c.note('p3.g1.stripe_refunds', 'refunds no PI', listed.brief, lens: 'G1');
      final cnt = listed.map?['refund_count'];
      final n = cnt is num ? cnt.round() : int.tryParse('$cnt') ?? 0;
      if (n >= 2) {
        c.hold(
          id: 'RTG-G1-003',
          lens: 'G1',
          severity: 'P0',
          title: 'Dois refunds Stripe no mesmo PI após double-submit paralelo',
          actor: 'seller JWT ×2',
          pre: 'order pago TEST',
          repro: 'Future.wait 2× POST refund-order',
          expected: '1 refund; 2.º already_refunded',
          obtained: {
            'a': rfs[0].brief,
            'b': rfs[1].brief,
            'stripe': listed.map,
            'order': afterRf,
            'wallets': w1,
          },
        );
      }
    }
  }

  // ---- G2: seller enviado ∥ seller refund (need a FRESH paid order) ----
  final paid2 = await c.e2e('setup_paid_order', {'initial_qty': 2});
  c.note('p3.fixture.paid2', 'setup_paid_order #2', paid2.brief, lens: 'G2');
  final p2m = paid2.map ?? {};
  final oid2 = (p2m['order_id'] ??
          (p2m['order'] is Map ? (p2m['order'] as Map)['id'] : null))
      ?.toString();
  final pid2 = p2m['product_id']?.toString();
  if (pid2 != null) c.createdProductIds.add(pid2);
  if (oid2 != null) {
    c.createdOrderIds.add(oid2);
    final race = await parallel([
      c.rest('PATCH', 'orders?id=eq.$oid2', jwt: c.sellerJwt, body: {
        'status': 'enviado',
        'shipping_method': 'CTT',
      }),
      c.edge('refund-order', {'order_id': oid2}, jwt: c.sellerJwt),
    ]);
    final after = await c.orderRow(oid2);
    c.note('p3.g2.ship_refund', 'enviado ∥ refund', {
      'ship': race[0].brief,
      'refund': race[1].brief,
      'order': after,
    }, lens: 'G2');
    final st = '${after?['status']}'.toLowerCase();
    final hasRefund = '${after?['stripe_refund_id'] ?? ''}'.trim().isNotEmpty;
    if (st == 'enviado' && hasRefund) {
      c.hold(
        id: 'RTG-G2-005',
        lens: 'G2',
        severity: 'P1',
        title: 'Order fica enviado e reembolsada na mesma corrida',
        actor: 'seller PATCH enviado ∥ refund-order',
        pre: 'order pago Stripe TEST',
        repro: 'Future.wait PATCH enviado ∥ POST refund-order',
        expected: 'refund bloqueado após enviado, ou enviado bloqueado após refund',
        obtained: after,
      );
    }
  }

  // ---- G4: settle after concluido (stale session) ----
  if (oid2 != null) {
    // try mark concluido then GET settle if session
    final row2 = await c.orderRow(oid2);
    final sid2 = row2?['stripe_checkout_session_id']?.toString();
    await c.rest(
      'PATCH',
      'orders?id=eq.$oid2',
      jwt: c.buyerJwt,
      body: {'status': 'concluido'},
    );
    if (sid2 != null && sid2.isNotEmpty) {
      final late = await c.req(
        'GET',
        '/functions/v1/create-payment-intent?checkout_return=success&session_id=$sid2',
        jwt: c.buyerJwt,
      );
      c.note('p3.g4.settle_after_done', 'GET settle pós-concluido', late.brief,
          lens: 'G4');
    }
  }

  // ---- G6: PATCH amount_paid / stripe ids from stale client ----
  if (paidOrderId != null) {
    final money = await c.rest(
      'PATCH',
      'orders?id=eq.$paidOrderId',
      jwt: c.buyerJwt,
      body: {
        'amount_paid_cents': 1,
        'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    c.note('p3.g6.money_patch', 'buyer PATCH money/release flags', money.brief,
        lens: 'G6');
    if (money.ok) {
      final row = await c.orderRow(paidOrderId);
      if (row?['amount_paid_cents'] == 1 ||
          row?['wallet_release_processed_at'] != null) {
        c.hold(
          id: 'RTG-G6-004',
          lens: 'G6',
          severity: 'P0',
          title: 'JWT grava amount_paid_cents ou wallet_release_processed_at',
          actor: 'buyer JWT',
          pre: 'order pago',
          repro: 'PATCH amount_paid_cents=1 + release flag',
          expected: 'order_money_fields_immutable',
          obtained: row,
        );
      }
    }
  }

  // ---- G7: buyer2 JWT on seller refund / foreign order ----
  if (paidOrderId != null) {
    final x = await c.edge(
      'refund-order',
      {'order_id': paidOrderId},
      jwt: c.buyer2Jwt,
    );
    c.note('p3.g7.foreign_refund', 'buyer2 refund order alheia', x.brief,
        lens: 'G7');
    if (x.ok) {
      c.hold(
        id: 'RTG-G7-002',
        lens: 'G7',
        severity: 'P0',
        title: '2.º buyer reembolsa encomenda que não é dele',
        actor: 'buyer2 JWT',
        pre: 'order pago buyer1/seller',
        repro: 'POST refund-order',
        expected: '403',
        obtained: x.brief,
      );
    }
  }

  out['findings'] = c.findings;
  out['notes'] = c.notes;
  out['wallets_after'] = await c.wallets();
  out['created'] = {
    'products': c.createdProductIds,
    'orders': c.createdOrderIds,
  };
  await dumpJson('tool/redteam_blind_g_20260831T1253/pass3.json', out);
  stdout.writeln('PASS3 findings=${c.findings.length}');
}
