/// RED TEAM CEGO CO — pass 1. Staging only. Não corrige.
/// CO-C FSM ≥4 · CO-E carrier/B2 ≥2 · lentes CO1 CO2 CO7.
/// Exactos CDCI/CI (observar, NÃO contar como finding novo): seller pago→pedido_devolucao.
import '_rtco.dart';

Future<void> main() async {
  final c = Rtci.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.well('CO-C');
  c.well('CO-E');
  c.note('actors', 'JWT B1/S1/B2/S2', {
    'b1': c.buyerId,
    's1': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
  });

  void recordBlock(String id, String matrix, String payload, HttpHit hit,
      {String? bd}) {
    final empty = hit.body.trim() == '[]' || hit.body.trim().isEmpty;
    if (hit.ok && !empty) {
      c.hold(
        id: id,
        lens: matrix.startsWith('CO-E') ? 'CO7' : 'CO1',
        severity: 'P1',
        title: id,
        actor: 'JWT',
        pre: payload,
        repro: id,
        expected: '401/403/empty/409',
        obtained: hit.brief,
      );
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: hit.brief,
        bd: bd,
        result: 'HOLD',
      );
    } else {
      c.block(id, matrix.startsWith('CO-E') ? 'CO7' : 'CO2', id, hit);
      c.probe(
        id: id,
        matrix: matrix,
        payload: payload,
        http: hit.brief,
        bd: bd,
        result: 'FAIL',
      );
    }
  }

  Future<({String oid, String pid, String? pi})> mustPay(String lens,
      {int qty = 2}) async {
    final paid = await c.payToPago(lens: lens, initialQty: qty);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  final p1 = await mustPay('CO1');
  var o = await c.orderRow(p1.oid);
  c.note('CO1.fixture', 'pago Stripe TEST', {
    'oid': p1.oid,
    'pid': p1.pid,
    'status': o?['status'],
    'paid': o?['amount_paid_cents'],
    'pi': p1.pi,
  }, lens: 'CO1');

  // CO-C4 seller pedido_devolucao (exacto CDCI/CI — observar)
  final sellerPedido = await c.patchOrder(
    p1.oid,
    {'status': 'pedido_devolucao'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(p1.oid);
  c.note('CO-C4.seller_pedido', 'seller pago→pedido_devolucao', {
    'hit': sellerPedido.brief,
    'status': o?['status'],
  }, lens: 'CO1');
  recordBlock(
    'CO-C4.seller_pedido_devolucao',
    'CO-C',
    'seller JWT PATCH status=pedido_devolucao a partir de pago',
    sellerPedido,
    bd: 'status=${o?['status']}',
  );

  // CO-E2 B2 INSERT disputa A (pago)
  final b2pago = await c.insertDispute(
    orderId: p1.oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  recordBlock(
    'CO-E2.b2_insert_disputa_a_pago',
    'CO-E',
    'B2 INSERT order_disputes em encomenda B1 (pago)',
    b2pago,
  );

  final b2spoof = await c.insertDispute(
    orderId: p1.oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyerId,
  );
  recordBlock(
    'CO-E2.b2_insert_spoof_buyer_id',
    'CO-E',
    'B2 INSERT disputa buyer_id=B1 JWT=B2',
    b2spoof,
  );

  // CO-C4 buyer pedido from pago (sem disputa)
  final buyerPedidoPago = await c.patchOrder(
    p1.oid,
    {'status': 'pedido_devolucao'},
    jwt: c.buyerJwt,
  );
  o = await c.orderRow(p1.oid);
  recordBlock(
    'CO-C4.buyer_pedido_from_pago',
    'CO-C',
    'buyer PATCH pedido_devolucao a partir de pago sem disputa',
    buyerPedidoPago,
    bd: 'status=${o?['status']}',
  );

  // CO-E1 webhook carrier / stripe sem sig + evento antigo
  final whNo = await c.edge('stripe-webhook', {
    'type': 'charge.succeeded',
    'created': 1600000000,
    'data': {
      'object': {
        'id': 'ch_rtco_nosig',
        'object': 'charge',
        'paid': true,
        'status': 'succeeded',
      }
    },
  }, jwt: c.sellerJwt);
  c.note('CO-E1.webhook_nosig', 'stripe-webhook sem Stripe-Signature',
      whNo.brief,
      lens: 'CO7');
  final whOk = whNo.ok &&
      !whNo.brief.toLowerCase().contains('signature') &&
      !whNo.brief.toLowerCase().contains('invalid') &&
      whNo.status != 400 &&
      whNo.status != 401;
  if (whOk) {
    c.hold(
      id: 'CO-E1.webhook_carrier_nosig',
      lens: 'CO7',
      severity: 'P1',
      title: 'Webhook Stripe/carrier aceite sem assinatura',
      actor: 'seller JWT',
      pre: 'POST stripe-webhook sem Stripe-Signature',
      repro: 'POST /functions/v1/stripe-webhook type=charge.succeeded created=1600000000',
      expected: '400/401 invalid signature',
      obtained: whNo.brief,
    );
    c.probe(
      id: 'CO-E1.webhook_carrier_nosig',
      matrix: 'CO-E',
      payload: 'POST stripe-webhook charge.succeeded created=1600000000 sem sig',
      http: whNo.brief,
      result: 'HOLD',
    );
  } else {
    c.block('CO-E1.webhook_carrier_nosig', 'CO7',
        'webhook sem sig recusado', whNo);
    c.probe(
      id: 'CO-E1.webhook_carrier_nosig',
      matrix: 'CO-E',
      payload: 'POST stripe-webhook charge.succeeded created=1600000000 sem sig',
      http: whNo.brief,
      result: 'FAIL',
    );
  }

  final whOld = await c.req(
    'POST',
    '/functions/v1/stripe-webhook',
    jwt: c.sellerJwt,
    body: {
      'type': 'checkout.session.completed',
      'created': 1600000000,
      'data': {
        'object': {
          'id': 'cs_rtco_old',
          'payment_status': 'paid',
          'status': 'complete',
        }
      },
    },
    extra: {'Stripe-Signature': 't=1600000000,v1=deadbeef'},
  );
  c.note('CO-E1.webhook_old_event', 'webhook evento antigo t=2020 sig inválida',
      whOld.brief,
      lens: 'CO7');
  final oldOk = whOld.ok &&
      !whOld.brief.toLowerCase().contains('signature') &&
      !whOld.brief.toLowerCase().contains('invalid') &&
      whOld.status != 400 &&
      whOld.status != 401;
  if (oldOk) {
    c.hold(
      id: 'CO-E1.webhook_old_event',
      lens: 'CO7',
      severity: 'P1',
      title: 'Webhook evento antigo (2020) aceite com assinatura inválida',
      actor: 'seller JWT',
      pre: 'Stripe-Signature t=1600000000,v1=deadbeef',
      repro: 'POST stripe-webhook checkout.session.completed',
      expected: '400/401',
      obtained: whOld.brief,
    );
    c.probe(
      id: 'CO-E1.webhook_old_event',
      matrix: 'CO-E',
      payload: 'POST stripe-webhook t=1600000000,v1=deadbeef',
      http: whOld.brief,
      result: 'HOLD',
    );
  } else {
    c.block('CO-E1.webhook_old_event', 'CO7', 'evento antigo recusado', whOld);
    c.probe(
      id: 'CO-E1.webhook_old_event',
      matrix: 'CO-E',
      payload: 'POST stripe-webhook t=1600000000,v1=deadbeef',
      http: whOld.brief,
      result: 'FAIL',
    );
  }

  if (!await c.toEnviado(p1.oid)) {
    c.skip('CO2.enviado', 'CO2', 'seller enviado não colou',
        await c.orderRow(p1.oid));
  }

  // Carrier spoof: seller enviado→entregue
  final entregueEarly = await c.patchOrder(
    p1.oid,
    {'status': 'entregue'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(p1.oid);
  c.note('CO-E1.carrier_entregue', 'seller enviado→entregue (carrier early)', {
    'hit': entregueEarly.brief,
    'status': o?['status'],
  }, lens: 'CO2');
  if (o?['status']?.toString() == 'entregue') {
    c.hold(
      id: 'CO-E1.carrier_entregue_early',
      lens: 'CO2',
      severity: 'P1',
      title: 'Seller marca entregue cedo (carrier delivered sem confirmação B)',
      actor: 'seller JWT',
      pre: 'status era enviado',
      repro: 'PATCH orders status=entregue',
      expected: '403 / status permanece enviado',
      obtained: {'hit': entregueEarly.brief, 'status': o?['status']},
    );
    c.probe(
      id: 'CO-E1.carrier_entregue_early',
      matrix: 'CO-E',
      payload: 'seller PATCH enviado→entregue',
      http: entregueEarly.brief,
      bd: 'status=${o?['status']}',
      result: 'HOLD',
    );
  } else {
    c.block('CO-E1.carrier_entregue_early', 'CO2',
        'enviado→entregue recusado', entregueEarly);
    c.probe(
      id: 'CO-E1.carrier_entregue_early',
      matrix: 'CO-E',
      payload: 'seller PATCH enviado→entregue',
      http: entregueEarly.brief,
      bd: 'status=${o?['status']}',
      result: 'FAIL',
    );
  }

  if (o?['status']?.toString() != 'concluido') {
    await c.toConcluido(p1.oid);
    o = await c.orderRow(p1.oid);
  }

  final b2conc = await c.insertDispute(
    orderId: p1.oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  recordBlock(
    'CO-E2.b2_insert_disputa_a_concluido',
    'CO-E',
    'B2 INSERT disputa em encomenda B1 (concluido)',
    b2conc,
  );

  final d1 = await c.insertDispute(orderId: p1.oid);
  final did = d1.firstId;
  c.note('CO1.dispute_open', '1.ª disputa em concluido', {
    'hit': d1.brief,
    'did': did,
  }, lens: 'CO1');
  if (did == null) {
    c.skip('CO-C1.dispute_open', 'CO1', 'INSERT disputa falhou', d1);
    await c.dumpAll('pass1.json');
    return;
  }
  c.probe(
    id: 'CO-C1.first_dispute',
    matrix: 'CO-C',
    payload: 'buyer INSERT disputa em concluido',
    http: d1.brief,
    bd: 'did=$did',
    result: d1.ok ? 'FAIL' : 'HOLD',
  );

  // CO-C1 2.ª disputa
  final d2 = await c.insertDispute(orderId: p1.oid);
  if (d2.ok) {
    c.hold(
      id: 'CO-C1.second_dispute',
      lens: 'CO1',
      severity: 'P1',
      title: '2.ª disputa INSERT na mesma encomenda',
      actor: 'buyer JWT',
      pre: 'já existe disputa $did',
      repro: 'POST order_disputes 2× no mesmo order_id',
      expected: '409 dispute_already_exists_for_order',
      obtained: d2.brief,
    );
    c.probe(
      id: 'CO-C1.second_dispute',
      matrix: 'CO-C',
      payload: '2.ª POST order_disputes mesmo order_id',
      http: d2.brief,
      result: 'HOLD',
    );
  } else {
    c.block('CO-C1.second_dispute', 'CO1', '2.ª disputa recusada', d2);
    c.probe(
      id: 'CO-C1.second_dispute',
      matrix: 'CO-C',
      payload: '2.ª POST order_disputes mesmo order_id',
      http: d2.brief,
      result: 'FAIL',
    );
  }

  final pedido = await c.patchOrder(
    p1.oid,
    {'status': 'pedido_devolucao'},
    jwt: c.buyerJwt,
  );
  o = await c.orderRow(p1.oid);
  c.note('CO1.pedido', 'buyer pedido_devolucao a partir de concluido+disputa', {
    'hit': pedido.brief,
    'status': o?['status'],
  }, lens: 'CO1');
  c.probe(
    id: 'CO-C4.buyer_pedido_from_concluido',
    matrix: 'CO-C',
    payload: 'buyer PATCH pedido_devolucao a partir de concluido+disputa',
    http: pedido.brief,
    bd: 'status=${o?['status']}',
    result: o?['status']?.toString() == 'pedido_devolucao' ? 'FAIL' : 'HOLD',
  );

  // CO-C2 partial qty
  final pedido2 = await c.patchOrder(
    p1.oid,
    {'status': 'pedido_devolucao', 'quantity': 0},
    jwt: c.buyerJwt,
  );
  o = await c.orderRow(p1.oid);
  final qtyZero = numOf(o?['quantity']) == 0;
  c.note('CO-C2.qty0', '2.ª PATCH pedido_devolucao + quantity=0', {
    'hit': pedido2.brief,
    'qty': o?['quantity'],
    'status': o?['status'],
  }, lens: 'CO1');
  if (qtyZero) {
    c.hold(
      id: 'CO-C2.partial_qty0',
      lens: 'CO1',
      severity: 'P1',
      title: '2.ª pedido_devolucao alterou quantity da encomenda para 0',
      actor: 'buyer JWT',
      pre: 'já pedido_devolucao',
      repro: 'PATCH status=pedido_devolucao quantity=0',
      expected: 'order_money_fields_immutable',
      obtained: {'hit': pedido2.brief, 'qty': o?['quantity']},
    );
    c.probe(
      id: 'CO-C2.partial_qty0',
      matrix: 'CO-C',
      payload: 'PATCH pedido_devolucao quantity=0',
      http: pedido2.brief,
      bd: 'qty=${o?['quantity']}',
      result: 'HOLD',
    );
  } else {
    c.block('CO-C2.partial_qty0', 'CO1', 'qty imutável', {
      'hit': pedido2.brief,
      'qty': o?['quantity'],
    });
    c.probe(
      id: 'CO-C2.partial_qty0',
      matrix: 'CO-C',
      payload: 'PATCH pedido_devolucao quantity=0',
      http: pedido2.brief,
      bd: 'qty=${o?['quantity']}',
      result: 'FAIL',
    );
  }

  // CO-C3 devolvida cedo
  final earlyDev = await c.patchOrder(
    p1.oid,
    {'status': 'devolvida'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(p1.oid);
  if (o?['status']?.toString() == 'devolvida') {
    c.hold(
      id: 'CO-C3.devolvida_cedo',
      lens: 'CO2',
      severity: 'P1',
      title: 'Seller marca devolvida cedo (ainda pedido_devolucao)',
      actor: 'seller JWT',
      pre: 'status=pedido_devolucao',
      repro: 'PATCH status=devolvida',
      expected: 'order_devolvida_denied',
      obtained: {'hit': earlyDev.brief, 'status': o?['status']},
    );
    c.probe(
      id: 'CO-C3.devolvida_cedo',
      matrix: 'CO-C',
      payload: 'seller PATCH devolvida a partir de pedido_devolucao',
      http: earlyDev.brief,
      bd: 'status=${o?['status']}',
      result: 'HOLD',
    );
  } else {
    c.block('CO-C3.devolvida_cedo', 'CO2', 'devolvida cedo recusada', earlyDev);
    c.probe(
      id: 'CO-C3.devolvida_cedo',
      matrix: 'CO-C',
      payload: 'seller PATCH devolvida a partir de pedido_devolucao',
      http: earlyDev.brief,
      bd: 'status=${o?['status']}',
      result: 'FAIL',
    );
  }

  await dumpJson('${outDir()}/pass1_ids.json', {
    'oid': p1.oid,
    'pid': p1.pid,
    'did': did,
    'pi': p1.pi,
    'status': o?['status'],
  });
  await c.dumpAll('pass1.json');
}
