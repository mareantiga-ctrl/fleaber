/// PASS 5 — converter reserva cruzada; disputa oferta sem skip; pedido_devolucao→devolvida.
import 'dart:io';

import '_rtq.dart';

void main() async {
  final env = loadEnv();
  final c = Rtq.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.wallets();

  // ---- Q1/Q8: live mismatch + convert + stripe_convert ----
  final liveA = await c.insertLive(seller: c.sellerId, active: true);
  final liveB = await c.insertLive(seller: c.seller2Id, active: true);
  final itemA = await c.insertLiveItem(liveId: liveA ?? '', title: '$prefix p5 A', qty: 2);
  final prodA = await c.createProduct(title: '$prefix p5 sku A', qty: 2, live: true);
  c.note('p5.live.fix', 'A/B', {'liveA': liveA, 'liveB': liveB, 'itemA': itemA},
      lens: 'Q1');

  final pend = await c.rest('POST', 'live_reservation_requests', jwt: c.buyerJwt, body: {
    'live_id': liveB,
    'live_item_id': itemA,
    'buyer_id': c.buyerId,
    'requested_qty': 1,
    'status': 'pending',
    'source': 'fleaber_live',
  });
  final rid = pend.firstId;
  c.note('p5.cross.pend', 'pending cruzado', pend.brief, lens: 'Q1');
  if (rid != null) {
    final acc = await c.rpc(
      'batata_process_live_reservation_request',
      {'p_request_id': rid, 'p_action': 'accept'},
      jwt: c.seller2Jwt,
    );
    c.note('p5.cross.accept', 'S2 accept', acc.brief, lens: 'Q1');
    final conv = await c.rpc(
      'batata_process_live_reservation_request',
      {'p_request_id': rid, 'p_action': 'convert'},
      jwt: c.seller2Jwt,
    );
    c.note('p5.cross.convert', 'S2 convert sem pagar', conv.brief, lens: 'Q8');
    final row = await c.reservationRow(rid);
    final item = await c.liveItemRow(itemA ?? '');
    if (row?['status'] == 'converted') {
      c.hold(
        id: 'RTQ-Q8-s2-convert-foreign-item-without-pay',
        lens: 'Q8',
        severity: 'P0',
        title:
            'S2 converte reserva no artigo de S1 (live_id B) sem PaymentIntent',
        actor: 'seller2 JWT',
        pre: 'accept cruzado Q1; convert marca sold/converted',
        repro: 'rpc process action=convert após accept no item alheio',
        expected: 'convert só após Stripe do dono do item / live_item∈live',
        obtained: {'row': row, 'item': item, 'rpc': conv.brief},
      );
    }
    final stripeConv = await c.rpc(
      'batata_live_reservation_stripe_convert',
      {'p_request_id': rid},
      jwt: c.buyer2Jwt,
    );
    c.note('p5.stripe.convert.b2', 'buyer2 stripe_convert id alheio',
        stripeConv.brief,
        lens: 'Q7');
    if (stripeConv.ok && stripeConv.map?['ok'] == true) {
      c.hold(
        id: 'RTQ-Q7-b2-stripe-convert-any-request',
        lens: 'Q7',
        severity: 'P0',
        title: '2.º comprador chama stripe_convert em reserva alheia',
        actor: 'buyer2 JWT',
        pre: 'RPC sem authz',
        repro: 'rpc batata_live_reservation_stripe_convert p_request_id alheio',
        expected: 'not granted / not_allowed',
        obtained: stripeConv.brief,
      );
    }
  }

  // S2 accept race ∥ S1 accept same pending on item A with correct live
  final pend2 = await c.rest('POST', 'live_reservation_requests', jwt: c.buyerJwt, body: {
    'live_id': liveA,
    'live_item_id': itemA,
    'buyer_id': c.buyerId,
    'requested_qty': 2,
    'status': 'pending',
    'source': 'fleaber_live',
  });
  final rid2 = pend2.firstId;
  if (rid2 != null) {
    final race = await parallel([
      c.rpc('batata_process_live_reservation_request',
          {'p_request_id': rid2, 'p_action': 'accept'}, jwt: c.sellerJwt),
      c.rpc('batata_process_live_reservation_request',
          {'p_request_id': rid2, 'p_action': 'reject'}, jwt: c.seller2Jwt),
    ]);
    c.note('p5.q4.race.accept.reject', 'S1 accept ∥ S2 reject mesmo pedido', {
      's1': race[0].brief,
      's2': race[1].brief,
      'row': await c.reservationRow(rid2),
    }, lens: 'Q4');
  }

  await c.endLives();

  // ---- Q3/Q5: disputa limpa, oferta 100%, process_partial vs refund-order ----
  final oid = await c.payToEntregue(lens: 'Q3');
  if (oid == null) {
    stderr.writeln('no paid');
    await dumpJson('${outDir()}/pass5.json',
        {'notes': c.notes, 'findings': c.findings});
    exit(0);
  }
  final o0 = await c.orderRow(oid);
  final pid = o0?['product_id']?.toString();
  final stock0 = pid != null ? await c.productRow(pid) : null;
  final disp = await c.rest('POST', 'order_disputes', jwt: c.buyerJwt, body: {
    'order_id': oid,
    'buyer_id': c.buyerId,
    'reason': 'nao_corresponde',
    'description': '$prefix p5',
  });
  final did = disp.firstId;
  c.note('p5.disp', 'disputa limpa', disp.brief, lens: 'Q5');

  if (did != null) {
    final offer = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {
        'seller_refund_percent': 100,
        'seller_offer_type': 'partial_refund',
        'seller_offer_set_by': c.sellerId,
        'seller_offer_set_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    c.note('p5.offer100', 'oferta 100% com set_by', offer.brief, lens: 'Q3');
    final drow = await c.rest(
      'GET',
      'order_disputes?id=eq.$did&select=id,status,seller_refund_percent,seller_offer_type,seller_offer_set_by,current_turn',
      service: true,
    );
    c.note('p5.offer.row', 'disputa após oferta', drow.map, lens: 'Q3');

    final wBefore = await c.wallets();
    final race = await parallel([
      c.rpc(
        'batata_process_partial_refund_dispute',
        {'p_order_id': oid},
        jwt: c.buyerJwt,
      ),
      c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt),
    ]);
    c.note('p5.q4.partial.vs.refund', 'partial100 ∥ refund-order', {
      'partial': race[0].brief,
      'refund': race[1].brief,
    }, lens: 'Q4');
    final o1 = await c.orderRow(oid);
    final w1 = await c.wallets();
    final stock1 = pid != null ? await c.productRow(pid) : null;
    final buyerGain = (w1['buyer'] ?? 0) - (wBefore['buyer'] ?? 0);
    final hasStripe = (o1?['stripe_refund_id']?.toString() ?? '').isNotEmpty;
    if (race[0].ok && buyerGain > 0.5 && !hasStripe) {
      c.hold(
        id: 'RTQ-Q3-partial100-mint-no-stripe-clean-dispute',
        lens: 'Q3',
        severity: 'P0',
        title: 'Oferta 100% + process_partial minta carteira sem Stripe (disputa aberta)',
        actor: 'buyer JWT',
        pre: 'sem skip FSM; seller_offer_set_by preenchido',
        repro: 'PATCH offer 100% set_by; rpc process_partial',
        expected: 'dispute_full_refund_requires_stripe',
        obtained: {
          'partial': race[0].brief,
          'refund': race[1].brief,
          'buyerGain': buyerGain,
          'order': o1,
          'dispute': drow.map,
        },
      );
    }
    if (buyerGain > 0.5 && hasStripe) {
      c.hold(
        id: 'RTQ-Q4-wallet-plus-stripe-refund',
        lens: 'Q4',
        severity: 'P0',
        title: 'Mesma encomenda: mint carteira e stripe_refund_id',
        actor: 'buyer+seller JWT',
        pre: 'race process_partial ∥ refund-order',
        repro: 'Future.wait',
        expected: 'um único caminho de restituição',
        obtained: {
          'buyerGain': buyerGain,
          'order': o1,
          'partial': race[0].brief,
          'refund': race[1].brief,
        },
      );
    }

    // pedido_devolucao → em_devolucao → devolucao_entregue → devolvida
    final pd = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
      'status': 'pedido_devolucao',
    });
    c.note('p5.pedido_devolucao', 'buyer pedido_devolucao', pd.brief, lens: 'Q3');
    final em = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
      'status': 'em_devolucao',
    });
    c.note('p5.em_devolucao', 'seller em_devolucao', em.brief, lens: 'Q3');
    final de = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
      'status': 'devolucao_entregue',
    });
    c.note('p5.devolucao_entregue', 'seller devolucao_entregue', de.brief,
        lens: 'Q3');
    final dv = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
      'status': 'devolvida',
    });
    c.note('p5.devolvida.after.cycle', 'seller devolvida pós ciclo', dv.brief,
        lens: 'Q3');
    final oEnd = await c.orderRow(oid);
    final stockEnd = pid != null ? await c.productRow(pid) : null;
    final wEnd = await c.wallets();
    final noStripe = (oEnd?['stripe_refund_id']?.toString() ?? '').isEmpty;
    final restock = (numOf(stockEnd?['quantity']) ?? 0) >
        (numOf(stock0?['quantity']) ?? 0);
    if (oEnd?['status'] == 'devolvida' && noStripe) {
      c.hold(
        id: 'RTQ-Q3-devolvida-after-return-cycle-no-stripe',
        lens: 'Q3',
        severity: 'P0',
        title:
            'Ciclo devolução chega a devolvida sem stripe_refund_id (stock/carteira)',
        actor: 'seller JWT',
        pre: 'entregue+disputa; O3 exige refund plataforma capturada',
        repro:
            'PATCH pedido_devolucao→em_devolucao→devolucao_entregue→devolvida',
        expected: 'order_devolvida_requires_refund',
        obtained: {
          'order': oEnd,
          'stock0': stock0,
          'stockEnd': stockEnd,
          'restock': restock,
          'w0': w0,
          'wEnd': wEnd,
        },
      );
    }
  }

  await dumpJson('${outDir()}/pass5.json', {
    'notes': c.notes,
    'findings': c.findings,
    'w0': w0,
    'wEnd': await c.wallets(),
  });
  stdout.writeln('PASS5 findings=${c.findings.length}');
  exit(0);
}
