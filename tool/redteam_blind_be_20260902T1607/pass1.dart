/// RED TEAM CEGO BE — pass 1. Staging only. Não corrige.
/// Lentes BE1–BE8. Variantes novas — não exactos AS/AY/AM.
import 'dart:io';
import '_rtbe.dart';

Future<void> main() async {
  final c = Rtbe.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('actors', 'JWT B1/S1/B2/S2', {
    'b1': c.buyerId,
    's1': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
  });

  Future<Map<String, dynamic>> books(String oid, String pid) async => {
        'order': await c.orderRow(oid),
        'product': await c.productRow(pid),
        'wallets': await c.wallets(),
      };

  Future<({String oid, String pid, String? pi})> mustPay(String lens,
      {int qty = 1}) async {
    final paid = await c.payToPago(lens: lens, initialQty: qty);
    if (paid == null) {
      throw StateError('setup_paid_order failed $lens');
    }
    return paid;
  }

  Future<HttpHit> patchDisp(
    String did,
    Map<String, Object?> body, {
    String? jwt,
  }) {
    return c.rest('PATCH', 'order_disputes?id=eq.$did',
        jwt: jwt ?? c.buyerJwt, body: body);
  }

  Future<Map<String, dynamic>?> disputeOf(String oid) async {
    final h = await c.rest(
      'GET',
      'order_disputes?order_id=eq.$oid&select=id,status,buyer_id,proof_photos,seller_refund_percent,seller_offer_type,buyer_decision,current_turn,return_label_url&order=created_at.desc',
      service: true,
    );
    return h.map;
  }

  Future<void> expectBlock(
    String id,
    String lens,
    String title,
    HttpHit hit,
  ) async {
    if (hit.ok) {
      c.hold(
        id: id,
        lens: lens,
        severity: 'P1',
        title: title,
        actor: 'JWT',
        pre: 'ver id',
        repro: id,
        expected: '401/403/empty',
        obtained: hit.brief,
      );
    } else {
      c.block(id, lens, title, hit);
    }
  }

  Future<void> probeStatus({
    required String id,
    required String lens,
    required String title,
    required String oid,
    required String pid,
    required String? jwt,
    required String status,
    String actor = 'JWT',
    bool moneyIfStock = true,
  }) async {
    final before = await books(oid, pid);
    final hit = await c.patchOrder(oid, {'status': status}, jwt: jwt);
    final after = await books(oid, pid);
    final got = '${after['order']?['status'] ?? ''}';
    final qtyB = numOf(before['product']?['quantity']) ?? 0;
    final qtyA = numOf(after['product']?['quantity']) ?? 0;
    final appliedB = numOf(before['order']?['stock_units_applied']);
    final appliedA = numOf(after['order']?['stock_units_applied']);
    final refund = '${after['order']?['stripe_refund_id'] ?? ''}';
    final persisted = got == status ||
        got.toLowerCase() == status.toLowerCase() ||
        got.contains(status.replaceAll('\u00A0', '').trim());
    c.note('$id.hit', title, {
      'patch': hit.brief,
      'status_before': before['order']?['status'],
      'status_after': got,
      'qty': '$qtyB→$qtyA',
      'applied': '$appliedB→$appliedA',
      'refund': refund,
    }, lens: lens);
    if (persisted && got != '${before['order']?['status']}') {
      final stockLie = qtyA > qtyB && refund.isEmpty;
      c.hold(
        id: id,
        lens: lens,
        severity: stockLie && moneyIfStock ? 'P1' : 'P2',
        title: title,
        actor: actor,
        pre: 'pago Stripe TEST status=${before['order']?['status']}',
        repro: 'PATCH orders.status=$status',
        expected: '403 / status inalterado',
        obtained: {
          'status': got,
          'qty': '$qtyB→$qtyA',
          'applied': '$appliedB→$appliedA',
          'refund_id': refund,
          'hit': hit.brief,
        },
      );
    } else if (!hit.ok) {
      c.block(id, lens, title, hit);
    } else {
      c.note('$id.noop', 'PATCH 2xx mas status não ficou $status', got,
          lens: lens);
    }
  }

  // =========================================================================
  // BE1 — disputa vs FSM (grafias / hops / actores)
  // =========================================================================
  final p1 = await mustPay('BE1');
  var o = await c.orderRow(p1.oid);
  c.note('BE1.fixture', 'pago Stripe TEST', {
    'oid': p1.oid,
    'pid': p1.pid,
    'status': o?['status'],
    'paid': o?['amount_paid_cents'],
    'ship': o?['shipping_method'],
    'applied': o?['stock_units_applied'],
    'pi': p1.pi,
  }, lens: 'BE1');

  await expectBlock(
    'BE1.alien_insert',
    'BE1',
    'B2 abre disputa em encomenda B1 (pago)',
    await c.insertDispute(
      orderId: p1.oid,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    ),
  );
  await expectBlock(
    'BE1.seller_insert',
    'BE1',
    'S1 INSERT disputa como se fosse comprador',
    await c.insertDispute(
      orderId: p1.oid,
      jwt: c.sellerJwt,
      buyer: c.sellerId,
    ),
  );
  await expectBlock(
    'BE1.dispute_on_pago',
    'BE1',
    'B1 abre disputa ainda em pago (RLS só concluido/entregue)',
    await c.insertDispute(orderId: p1.oid),
  );

  // Grafias de cancelamento — não exacto «cancelado» pós-pago.
  for (final st in [
    'cancelada',
    'canceled',
    'anulado',
    'anulada',
    'cancelad',
    'xcancelado',
    'pedido_cancelado',
  ]) {
    await probeStatus(
      id: 'BE1.spelling.$st',
      lens: 'BE1',
      title: 'PATCH status=$st pós-pago (variante de cancelado)',
      oid: p1.oid,
      pid: p1.pid,
      jwt: c.sellerJwt,
      status: st,
      actor: 'S1 JWT',
    );
    final now = await c.orderRow(p1.oid);
    if ('${now?['status']}' != '${o?['status']}' &&
        '${now?['status']}' != 'pago') {
      c.note('BE1.spelling.stop', 'estado saiu de pago', now?['status'],
          lens: 'BE1');
      break;
    }
  }

  o = await c.orderRow(p1.oid);
  if ('${o?['status']}' == 'pago') {
    await probeStatus(
      id: 'BE1.nbsp_cancelado',
      lens: 'BE1',
      title: 'PATCH cancelado+NBSP pós-pago',
      oid: p1.oid,
      pid: p1.pid,
      jwt: c.sellerJwt,
      status: 'cancelado\u00A0',
      actor: 'S1 JWT',
    );
    await probeStatus(
      id: 'BE1.accent_concluido',
      lens: 'BE1',
      title: 'S1 PATCH concluído (acento) a partir de pago',
      oid: p1.oid,
      pid: p1.pid,
      jwt: c.sellerJwt,
      status: 'concluído',
      actor: 'S1 JWT',
    );
    await probeStatus(
      id: 'BE1.nbsp_concluido',
      lens: 'BE1',
      title: 'S1 PATCH concluido+NBSP',
      oid: p1.oid,
      pid: p1.pid,
      jwt: c.sellerJwt,
      status: 'concluido\u00A0',
      actor: 'S1 JWT',
    );
    await probeStatus(
      id: 'BE1.buyer_em_devolucao_from_pago',
      lens: 'BE1',
      title: 'B1 salta para em_devolucao desde pago (sem disputa)',
      oid: p1.oid,
      pid: p1.pid,
      jwt: c.buyerJwt,
      status: 'em_devolucao',
      actor: 'B1 JWT',
    );
    await probeStatus(
      id: 'BE1.seller_disputa_vendedor',
      lens: 'BE1',
      title: 'S1 PATCH disputa_devolucao_vendedor desde pago',
      oid: p1.oid,
      pid: p1.pid,
      jwt: c.sellerJwt,
      status: 'disputa_devolucao_vendedor',
      actor: 'S1 JWT',
    );
    await probeStatus(
      id: 'BE1.seller_skip_to_devolucao_entregue',
      lens: 'BE1',
      title: 'S1 salta pago→devolucao_entregue (hop ANAS)',
      oid: p1.oid,
      pid: p1.pid,
      jwt: c.sellerJwt,
      status: 'devolucao_entregue',
      actor: 'S1 JWT',
    );
  }

  // Qty / product swap while still captured.
  o = await c.orderRow(p1.oid);
  final qtyHit = await c.patchOrder(p1.oid, {'quantity': 9}, jwt: c.buyerJwt);
  final qtyAfter = await c.orderRow(p1.oid);
  c.note('BE3.qty.patch', 'B1 PATCH quantity=9 em encomenda paga', {
    'hit': qtyHit.brief,
    'qty': qtyAfter?['quantity'],
  }, lens: 'BE3');
  if (qtyHit.ok && numOf(qtyAfter?['quantity']) == 9) {
    c.hold(
      id: 'BE3.qty_inflate',
      lens: 'BE3',
      severity: 'P1',
      title: 'B1 inflaciona quantity de encomenda paga (restore futuro)',
      actor: 'B1 JWT',
      pre: 'pago qty=1',
      repro: 'PATCH quantity=9',
      expected: '403 / qty inalterada',
      obtained: qtyAfter?['quantity'],
    );
  } else {
    c.block('BE3.qty_inflate', 'BE3', 'PATCH quantity=9', qtyHit);
  }

  final decoy = await c.createProduct(title: '$prefix-decoy', qty: 4);
  if (decoy != null) {
    final swap = await c.patchOrder(p1.oid, {'product_id': decoy}, jwt: c.buyerJwt);
    final swapped = await c.orderRow(p1.oid);
    c.note('BE3.product.swap', 'B1 PATCH product_id alheio/decoy', {
      'hit': swap.brief,
      'pid': swapped?['product_id'],
    }, lens: 'BE3');
    if (swap.ok && '${swapped?['product_id']}' == decoy) {
      c.hold(
        id: 'BE3.product_swap',
        lens: 'BE3',
        severity: 'P1',
        title: 'B1 troca product_id de encomenda paga',
        actor: 'B1 JWT',
        pre: 'pago pid=${p1.pid}',
        repro: 'PATCH product_id=decoy',
        expected: '403 / pid inalterado',
        obtained: swapped?['product_id'],
      );
    } else {
      c.block('BE3.product_swap', 'BE3', 'PATCH product_id', swap);
    }
  }

  // =========================================================================
  // BE2 / BE5 / BE6 — enviado ∥ disputa ∥ receção ∥ etiqueta
  // =========================================================================
  final p2 = await mustPay('BE2');
  final ship = await c.patchOrder(p2.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final o2 = await c.orderRow(p2.oid);
  c.note('BE2.enviado', 'S1 marca enviado', {
    'hit': ship.brief,
    'status': o2?['status'],
    'shipped_at': o2?['shipped_at'],
  }, lens: 'BE2');
  if ('${o2?['status']}' != 'enviado') {
    c.skip('BE2.enviado', 'BE2', 'não ficou enviado', ship);
  }

  await expectBlock(
    'BE2.dispute_on_enviado',
    'BE2',
    'B1 abre disputa em enviado (sem entregue)',
    await c.insertDispute(orderId: p2.oid),
  );

  final unship = await c.patchOrder(
    p2.oid,
    {'shipped_at': null},
    jwt: c.sellerJwt,
  );
  await expectBlock(
    'BE2.unship',
    'BE2',
    'S1 apaga shipped_at após enviado',
    unship,
  );

  final track = await c.patchOrder(
    p2.oid,
    {'tracking_code': 'CTT-BE-ALIEN-999'},
    jwt: c.sellerJwt,
  );
  c.note('BE6.tracking', 'S1 PATCH tracking_code', track.brief, lens: 'BE6');
  if (track.ok) {
    c.note('BE6.tracking.ok', 'coluna aceitou ou ignorou', track.map, lens: 'BE6');
  } else {
    c.block('BE6.tracking', 'BE6', 'PATCH tracking_code', track);
  }

  final shipMao = await c.patchOrder(
    p2.oid,
    {'shipping_method': 'entrega em mão'},
    jwt: c.buyerJwt,
  );
  final o2b = await c.orderRow(p2.oid);
  c.note('BE6.ship_method', 'B1 PATCH shipping_method=mão após enviado', {
    'hit': shipMao.brief,
    'ship': o2b?['shipping_method'],
  }, lens: 'BE6');
  if (shipMao.ok &&
      '${o2b?['shipping_method']}'.toLowerCase().contains('mão')) {
    c.hold(
      id: 'BE6.ship_method_after_sent',
      lens: 'BE6',
      severity: 'P2',
      title: 'B1 muda envio para mão depois de enviado (carrier mentiroso)',
      actor: 'B1 JWT',
      pre: 'enviado',
      repro: 'PATCH shipping_method=entrega em mão',
      expected: '403 / método inalterado',
      obtained: o2b?['shipping_method'],
    );
  } else if (!shipMao.ok) {
    c.block('BE6.ship_method_after_sent', 'BE6', 'PATCH shipping_method', shipMao);
  }

  final entregue = await c.patchOrder(
    p2.oid,
    {'status': 'entregue'},
    jwt: c.buyerJwt,
  );
  c.note('BE5.entregue', 'B1 marca entregue', entregue.brief, lens: 'BE5');

  final disp2 = await c.insertDispute(orderId: p2.oid);
  c.note('BE2.dispute_after_entregue', 'B1 disputa pós-entregue', disp2.brief,
      lens: 'BE2');
  final d2 = await disputeOf(p2.oid);
  final did2 = d2?['id']?.toString();

  if (did2 != null) {
    await expectBlock(
      'BE1.second_dispute',
      'BE1',
      '2.ª disputa aberta no mesmo pedido',
      await c.insertDispute(orderId: p2.oid, description: 'segunda BE'),
    );

    final sClose = await patchDisp(did2, {'status': 'resolvida'}, jwt: c.sellerJwt);
    final dClose = await disputeOf(p2.oid);
    c.note('BE1.seller_resolvida', 'S1 PATCH resolvida', {
      'hit': sClose.brief,
      'status': dClose?['status'],
    }, lens: 'BE1');
    if ('${dClose?['status']}' == 'resolvida') {
      c.hold(
        id: 'BE1.seller_resolvida',
        lens: 'BE1',
        severity: 'P1',
        title: 'S1 fecha disputa resolvida',
        actor: 'S1 JWT',
        pre: 'disputa aberta',
        repro: 'PATCH order_disputes.status=resolvida',
        expected: 'status inalterado aberta',
        obtained: dClose?['status'],
      );
    } else {
      c.block('BE1.seller_resolvida', 'BE1', 'S1 resolvida', sClose);
    }

    final bResolved = await patchDisp(
      did2,
      {'status': 'resolved'},
      jwt: c.buyerJwt,
    );
    c.note('BE1.buyer_resolved_en', 'B1 PATCH status=resolved (EN)',
        bResolved.brief,
        lens: 'BE1');
    final d2b = await disputeOf(p2.oid);
    if ('${d2b?['status']}' == 'resolved') {
      c.hold(
        id: 'BE1.buyer_resolved_en',
        lens: 'BE1',
        severity: 'P2',
        title: 'B1 fecha disputa com status inglês resolved',
        actor: 'B1 JWT',
        pre: 'disputa aberta',
        repro: 'PATCH order_disputes.status=resolved',
        expected: 'check constraint / inalterado',
        obtained: d2b?['status'],
      );
    }

    final offer = await patchDisp(did2, {
      'seller_refund_percent': 100,
      'seller_offer_type': 'partial_refund',
      'seller_offer_set_by': c.buyerId,
    }, jwt: c.buyerJwt);
    c.note('BE4.buyer_forges_offer', 'B1 escreve oferta de reembolso do vendedor',
        offer.brief,
        lens: 'BE4');
    final d2c = await disputeOf(p2.oid);
    if (offer.ok && numOf(d2c?['seller_refund_percent']) == 100) {
      c.hold(
        id: 'BE4.buyer_forges_seller_offer',
        lens: 'BE4',
        severity: 'P1',
        title: 'B1 forja seller_refund_percent=100',
        actor: 'B1 JWT',
        pre: 'disputa aberta',
        repro: 'PATCH seller_refund_percent=100',
        expected: 'campo recusado / só seller',
        obtained: d2c,
      );
    } else if (!offer.ok) {
      c.block('BE4.buyer_forges_seller_offer', 'BE4', 'B1 oferta seller', offer);
    }

    final sOffer = await patchDisp(did2, {
      'seller_refund_percent': 50,
      'seller_offer_type': 'partial_refund',
    }, jwt: c.sellerJwt);
    c.note('BE4.seller_offer', 'S1 oferta parcial 50%', sOffer.brief, lens: 'BE4');

    final rpcB = await c.rpc('batata_process_partial_refund_dispute', {
      'p_order_id': p2.oid,
      'p_refund_percent': 50,
    }, jwt: c.buyerJwt);
    c.note('BE4.partial.buyer', 'RPC parcial JWT buyer', rpcB.brief, lens: 'BE4');
    if (rpcB.ok && rpcB.json == true) {
      final w = await c.wallets();
      c.hold(
        id: 'BE4.partial_wallet_without_stripe',
        lens: 'BE4',
        severity: 'P1',
        title: 'RPC parcial credita carteira sem Stripe refund',
        actor: 'B1 JWT',
        pre: 'enviado+entregue+disputa+oferta',
        repro: 'rpc batata_process_partial_refund_dispute',
        expected: 'false / 42501 Stripe',
        obtained: {'rpc': rpcB.brief, 'wallets': w},
      );
    } else {
      c.block('BE4.partial.buyer', 'BE4', 'RPC parcial buyer', rpcB);
    }

    final rpcS = await c.rpc('batata_process_partial_refund_dispute', {
      'p_order_id': p2.oid,
    }, jwt: c.sellerJwt);
    c.note('BE4.partial.seller', 'S1 RPC parcial', rpcS.brief, lens: 'BE4');
    if (rpcS.ok && rpcS.json == true) {
      c.hold(
        id: 'BE4.partial.seller',
        lens: 'BE4',
        severity: 'P1',
        title: 'S1 executa RPC parcial (só buyer)',
        actor: 'S1 JWT',
        pre: 'disputa',
        repro: 'rpc batata_process_partial_refund_dispute JWT seller',
        expected: '42501 / false',
        obtained: rpcS.brief,
      );
    } else {
      c.block('BE4.partial.seller', 'BE4', 'S1 RPC parcial', rpcS);
    }

    final evilLabel = await patchDisp(did2, {
      'return_label_url': 'javascript:alert(1)',
    }, jwt: c.sellerJwt);
    c.note('BE7.return_label.js', 'S1 return_label_url javascript:',
        evilLabel.brief,
        lens: 'BE7');
    final dLabel = await disputeOf(p2.oid);
    final lab = '${dLabel?['return_label_url'] ?? ''}';
    if (lab.toLowerCase().startsWith('javascript:')) {
      c.hold(
        id: 'BE7.return_label_js',
        lens: 'BE7',
        severity: 'P2',
        title: 'return_label_url aceita javascript:',
        actor: 'S1 JWT',
        pre: 'disputa aberta',
        repro: 'PATCH return_label_url=javascript:',
        expected: 'denied',
        obtained: lab,
      );
    } else {
      c.block('BE7.return_label_js', 'BE7', 'javascript: label', evilLabel);
    }
  } else {
    c.skip('BE2.dispute', 'BE2', 'disputa não criada após entregue', disp2);
  }

  // Hop skip pós-entregue+disputa (não exacto disputa→devolvida).
  await probeStatus(
    id: 'BE3.buyer_skip_em_devolucao',
    lens: 'BE3',
    title: 'B1 salta entregue→em_devolucao (salta pedido_devolucao)',
    oid: p2.oid,
    pid: p2.pid,
    jwt: c.buyerJwt,
    status: 'em_devolucao',
    actor: 'B1 JWT',
  );
  await probeStatus(
    id: 'BE3.buyer_skip_devolucao_entregue',
    lens: 'BE3',
    title: 'B1 salta para devolucao_entregue (falso recebido)',
    oid: p2.oid,
    pid: p2.pid,
    jwt: c.buyerJwt,
    status: 'devolucao_entregue',
    actor: 'B1 JWT',
  );

  final rdAt = await c.patchOrder(
    p2.oid,
    {'return_delivered_at': DateTime.now().toUtc().toIso8601String()},
    jwt: c.buyerJwt,
  );
  await expectBlock(
    'BE5.buyer_return_delivered_at',
    'BE5',
    'B1 selo return_delivered_at',
    rdAt,
  );

  final o2c = await c.orderRow(p2.oid);
  if ('${o2c?['status']}' == 'devolucao_entregue') {
    final dv = await c.patchOrder(
      p2.oid,
      {'status': 'devolvida'},
      jwt: c.sellerJwt,
    );
    final o2d = await c.orderRow(p2.oid);
    c.note('BE3.seller_devolvida_after_buyer_skip', 'S1 devolvida após skip B1', {
      'hit': dv.brief,
      'status': o2d?['status'],
    }, lens: 'BE3');
    if ('${o2d?['status']}' == 'devolvida') {
      c.hold(
        id: 'BE3.buyer_skip_enables_devolvida',
        lens: 'BE3',
        severity: 'P1',
        title: 'B1 finge devolucao_entregue e S1 consegue devolvida',
        actor: 'B1+S1 JWT',
        pre: 'enviado→entregue→disputa; B1 skip hops',
        repro: 'PATCH devolucao_entregue (B1); PATCH devolvida (S1)',
        expected: 'B1 não avança hop; devolvida recusada',
        obtained: o2d,
      );
    }
  }

  final refundEm = await c.refund(p2.oid, jwt: c.sellerJwt);
  c.note('BE4.refund.current', 'refund-order no estado actual', {
    'status': (await c.orderRow(p2.oid))?['status'],
    'hit': refundEm.brief,
  }, lens: 'BE4');

  final refundB = await c.refund(p2.oid, jwt: c.buyerJwt);
  await expectBlock(
    'BE4.refund.buyer',
    'BE4',
    'B1 chama refund-order',
    refundB,
  );
  final refundB2 = await c.refund(p2.oid, jwt: c.buyer2Jwt);
  await expectBlock(
    'BE4.refund.buyer2',
    'BE4',
    'B2 chama refund-order da encomenda B1',
    refundB2,
  );
  final refundAmt = await c.edge('refund-order', {
    'order_id': p2.oid,
    'amount': 99999,
    'amount_cents': 99999,
  }, jwt: c.sellerJwt);
  c.note('BE4.refund.amount_override', 'refund-order com amount cliente',
      refundAmt.brief,
      lens: 'BE4');

  // Receção ∩ disputa: concluido com disputa aberta.
  final p5 = await mustPay('BE5');
  await c.patchOrder(p5.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(p5.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  final disp5 = await c.insertDispute(orderId: p5.oid);
  c.note('BE5.disp', 'disputa em entregue', disp5.brief, lens: 'BE5');
  final conc = await c.patchOrder(
    p5.oid,
    {'status': 'concluido'},
    jwt: c.buyerJwt,
  );
  final o5 = await c.orderRow(p5.oid);
  c.note('BE5.concluido_with_dispute', 'B1 concluido com disputa aberta', {
    'hit': conc.brief,
    'status': o5?['status'],
  }, lens: 'BE5');
  if ('${o5?['status']}' == 'concluido') {
    final rel = await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': p5.oid,
    }, jwt: c.buyerJwt);
    c.note('BE5.release_open_dispute', 'release com disputa aberta', rel.brief,
        lens: 'BE5');
    final w5 = await c.wallets();
    if (rel.ok && rel.json == true) {
      c.hold(
        id: 'BE5.release_while_dispute',
        lens: 'BE5',
        severity: 'P0',
        title: 'Release carteira vendedor com disputa ainda aberta',
        actor: 'B1 JWT',
        pre: 'concluido + disputa aberta',
        repro: 'rpc batata_release_seller_wallet_for_order',
        expected: 'false',
        obtained: {'rpc': rel.brief, 'wallets': w5},
      );
    } else {
      c.block('BE5.release_open_dispute', 'BE5', 'release disputa aberta', rel);
    }

    final past = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 72))
        .toIso8601String();
    final ca = await c.patchOrder(
      p5.oid,
      {'completed_at': past},
      jwt: c.buyerJwt,
    );
    final o5b = await c.orderRow(p5.oid);
    c.note('BE5.completed_at', 'B1 recua completed_at', {
      'hit': ca.brief,
      'completed_at': o5b?['completed_at'],
    }, lens: 'BE5');
    if (ca.ok && '${o5b?['completed_at']}'.contains('2026-08')) {
      c.hold(
        id: 'BE5.backdate_completed_at',
        lens: 'BE5',
        severity: 'P2',
        title: 'B1 recua completed_at (relógio auto-feedback)',
        actor: 'B1 JWT',
        pre: 'concluido',
        repro: 'PATCH completed_at=-72h',
        expected: 'imutável / agora',
        obtained: o5b?['completed_at'],
      );
    } else if (!ca.ok) {
      c.block('BE5.backdate_completed_at', 'BE5', 'PATCH completed_at', ca);
    }

    await probeStatus(
      id: 'BE5.pedido_devolucao_from_concluido',
      lens: 'BE5',
      title: 'B1 pedido_devolucao a partir de concluido+disputa',
      oid: p5.oid,
      pid: p5.pid,
      jwt: c.buyerJwt,
      status: 'pedido_devolucao',
      actor: 'B1 JWT',
      moneyIfStock: false,
    );
  }

  // Mão: pago → concluido (sem enviado) + disputa.
  final pMao = await mustPay('BE5');
  final toMao = await c.patchOrder(
    pMao.oid,
    {'shipping_method': 'entrega em mão'},
    jwt: c.buyerJwt,
  );
  c.note('BE6.mao.patch', 'B1 PATCH mão em pago', toMao.brief, lens: 'BE6');
  final maoConc = await c.patchOrder(
    pMao.oid,
    {'status': 'concluido'},
    jwt: c.buyerJwt,
  );
  final oMao = await c.orderRow(pMao.oid);
  c.note('BE5.mao_concluido', 'B1 concluido em mão (possivelmente após PATCH)', {
    'hit': maoConc.brief,
    'status': oMao?['status'],
    'ship': oMao?['shipping_method'],
    'shipped_at': oMao?['shipped_at'],
  }, lens: 'BE5');
  if ('${oMao?['status']}' == 'concluido') {
    final dMao = await c.insertDispute(orderId: pMao.oid);
    c.note('BE5.mao_dispute', 'disputa após concluido mão', dMao.brief,
        lens: 'BE5');
    final relMao = await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': pMao.oid,
    }, jwt: c.buyerJwt);
    c.note('BE5.mao_release', 'release mão+disputa', relMao.brief, lens: 'BE5');
    if (relMao.ok && relMao.json == true) {
      c.hold(
        id: 'BE5.mao_release_with_dispute_or_no_ship',
        lens: 'BE5',
        severity: 'P1',
        title: 'Release em mão com disputa ou sem shipped_at',
        actor: 'B1 JWT',
        pre: 'pago PATCH mão → concluido',
        repro: 'rpc release',
        expected: 'false se disputa aberta',
        obtained: relMao.brief,
      );
    } else {
      c.block('BE5.mao_release', 'BE5', 'release mão', relMao);
    }
  }

  // =========================================================================
  // BE7 — provas (path alheio / encoding / prefixo LIKE)
  // =========================================================================
  final p7 = await mustPay('BE7');
  await c.patchOrder(p7.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(p7.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  final disp7 = await c.insertDispute(orderId: p7.oid);
  c.note('BE7.disp', 'disputa para storage', disp7.brief, lens: 'BE7');
  final bytes = List<int>.from('BE7'.codeUnits);

  Future<void> tryUpload(String id, String path, {String? jwt}) async {
    final hit = await c.storage(
      'POST',
      'object/fleaber_private/$path',
      jwt: jwt ?? c.buyerJwt,
      bytes: bytes,
      contentType: 'image/jpeg',
    );
    c.note('$id.up', path, hit.brief, lens: 'BE7');
    if (hit.ok) {
      final getS1 = await c.storage(
        'GET',
        'object/fleaber_private/$path',
        jwt: c.sellerJwt,
      );
      final getS2 = await c.storage(
        'GET',
        'object/fleaber_private/$path',
        jwt: c.seller2Jwt,
      );
      final getB2 = await c.storage(
        'GET',
        'object/fleaber_private/$path',
        jwt: c.buyer2Jwt,
      );
      c.note('$id.get', 'GET S1/S2/B2', {
        's1': getS1.status,
        's2': getS2.status,
        'b2': getB2.status,
      }, lens: 'BE7');
      if (getS2.ok || getB2.ok) {
        c.hold(
          id: id,
          lens: 'BE7',
          severity: 'P1',
          title: 'Leitura cruzada de prova disputa',
          actor: getS2.ok ? 'S2 JWT' : 'B2 JWT',
          pre: path,
          repro: 'GET storage fleaber_private/$path',
          expected: '404/403 para S2/B2',
          obtained: {
            's1': getS1.status,
            's2': getS2.status,
            'b2': getB2.status,
            'up': hit.brief,
          },
        );
      } else {
        c.block(id, 'BE7', 'cross GET S2/B2', getS2);
      }
    } else {
      c.block(id, 'BE7', 'upload $path', hit);
    }
  }

  final b1 = c.buyerId!;
  await tryUpload(
    'BE7.path_ok',
    'order_disputes/$b1/${p7.oid}/be7.jpg',
  );
  await tryUpload(
    'BE7.path_prefix_noslash',
    'order_disputes/$b1/${p7.oid}noslash.jpg',
  );
  await tryUpload(
    'BE7.path_dotdot',
    'order_disputes/$b1/${p7.oid}/../../order_proofs/$b1/x.jpg',
  );
  await tryUpload(
    'BE7.path_other_own_order',
    'order_disputes/$b1/${p1.oid}/wrong-order.jpg',
  );
  await tryUpload(
    'BE7.s2_upload_b1_path',
    'order_disputes/$b1/${p7.oid}/s2-plant.jpg',
    jwt: c.seller2Jwt,
  );

  final urlJs = await c.insertDispute(
    orderId: p7.oid,
    photos: [
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/x?x=1',
      'vbscript:msgbox(1)',
    ],
  );
  c.note('BE7.photos.vbscript', '2.ª disputa/update vbscript mix', urlJs.brief,
      lens: 'BE7');

  if (did2 != null) {
    final mix = await patchDisp(did2, {
      'proof_photos': [
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/ok.jpg',
        'mailto:x@evil.test',
      ],
    });
    await expectBlock(
      'BE7.photos.mailto_mix',
      'BE7',
      'proof_photos mix sign + mailto:',
      mix,
    );

    final enc = await patchDisp(did2, {
      'proof_photos': [
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/%2e%2e/object/public/x',
      ],
    });
    c.note('BE7.photos.enc', 'sign path %2e%2e public', enc.brief, lens: 'BE7');
    if (enc.ok) {
      c.hold(
        id: 'BE7.photos_encoded_traversal',
        lens: 'BE7',
        severity: 'P2',
        title: 'proof_photos aceita path URL-encoded ..',
        actor: 'B1 JWT',
        pre: 'disputa',
        repro: 'PATCH proof_photos sign/%2e%2e/object/public',
        expected: 'denied',
        obtained: enc.brief,
      );
    } else {
      c.block('BE7.photos_encoded_traversal', 'BE7', '%2e%2e', enc);
    }
  }

  final admin = await c.rpc('batata_admin_resolve_dispute', {
    'p_dispute_id': did2 ?? p7.oid,
    'p_status': 'resolvida',
  }, jwt: c.buyerJwt);
  c.note('BE1.admin_rpc_buyer', 'B1 rpc admin resolve', admin.brief, lens: 'BE1');
  final adminOk = admin.ok &&
      admin.json != false &&
      !admin.brief.toLowerCase().contains('apenas') &&
      !admin.brief.toLowerCase().contains('admin');
  if (adminOk && admin.status < 300 && admin.json == true) {
    c.hold(
      id: 'BE1.admin_rpc_buyer',
      lens: 'BE1',
      severity: 'P1',
      title: 'B1 rpc admin resolve disputa',
      actor: 'B1 JWT',
      pre: 'disputa',
      repro: 'rpc batata_admin_resolve_dispute',
      expected: 'denied',
      obtained: admin.brief,
    );
  } else {
    c.block('BE1.admin_rpc_buyer', 'BE1', 'B1 admin rpc', admin);
  }

  // =========================================================================
  // BE8 — composição: hop skip + refund + 2.º checkout + wallets
  // =========================================================================
  final p8 = await mustPay('BE8', qty: 2);
  final w0 = await c.wallets();
  final pr0 = await c.productRow(p8.pid);
  await c.patchOrder(p8.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(p8.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  final d8 = await c.insertDispute(orderId: p8.oid);
  c.note('BE8.disp', 'disputa composição', d8.brief, lens: 'BE8');

  final skip1 = await c.patchOrder(
    p8.oid,
    {'status': 'pedido_devolucao'},
    jwt: c.buyerJwt,
  );
  final skip2 = await c.patchOrder(
    p8.oid,
    {'status': 'em_devolucao'},
    jwt: c.sellerJwt,
  );
  final skip3 = await c.patchOrder(
    p8.oid,
    {'status': 'devolucao_entregue'},
    jwt: c.sellerJwt,
  );
  final skip4 = await c.patchOrder(
    p8.oid,
    {'status': 'devolvida'},
    jwt: c.sellerJwt,
  );
  var o8 = await c.orderRow(p8.oid);
  c.note('BE8.hops', 'cadeia hops (pedido→em→entregue→devolvida)', {
    'pedido': skip1.brief,
    'em': skip2.brief,
    'ent': skip3.brief,
    'dev': skip4.brief,
    'status': o8?['status'],
    'applied': o8?['stock_units_applied'],
    'qty_prod': (await c.productRow(p8.pid))?['quantity'],
  }, lens: 'BE8');

  // Variante: S1 salta em_devolucao → devolvida (exacto ANAS hop — verify still closed).
  if ('${o8?['status']}' == 'em_devolucao') {
    final hopSkip = await c.patchOrder(
      p8.oid,
      {'status': 'devolvida'},
      jwt: c.sellerJwt,
    );
    c.note('BE8.hop_skip_devolvida', 'S1 em_devolucao→devolvida', hopSkip.brief,
        lens: 'BE8');
    if (hopSkip.ok &&
        '${(await c.orderRow(p8.oid))?['status']}' == 'devolvida') {
      c.hold(
        id: 'BE8.hop_skip',
        lens: 'BE8',
        severity: 'P1',
        title: 'S1 salta em_devolucao→devolvida (hop ANAS)',
        actor: 'S1 JWT',
        pre: 'em_devolucao',
        repro: 'PATCH devolvida',
        expected: 'order_devolvida_denied',
        obtained: hopSkip.brief,
      );
    } else {
      c.block('BE8.hop_skip', 'BE8', 'em_devolucao→devolvida', hopSkip);
    }
  }

  o8 = await c.orderRow(p8.oid);
  if ('${o8?['status']}' == 'devolucao_entregue') {
    await c.patchOrder(p8.oid, {'status': 'devolvida'}, jwt: c.sellerJwt);
    o8 = await c.orderRow(p8.oid);
  }

  final beforeRefund = await books(p8.oid, p8.pid);
  final rf = await c.refund(p8.oid, jwt: c.sellerJwt);
  final afterRefund = await books(p8.oid, p8.pid);
  c.note('BE8.refund', 'refund-order composição', {
    'hit': rf.brief,
    'before': {
      'status': beforeRefund['order']?['status'],
      'applied': beforeRefund['order']?['stock_units_applied'],
      'qty': beforeRefund['product']?['quantity'],
      'w': beforeRefund['wallets'],
    },
    'after': {
      'status': afterRefund['order']?['status'],
      'applied': afterRefund['order']?['stock_units_applied'],
      'qty': afterRefund['product']?['quantity'],
      'refund': afterRefund['order']?['stripe_refund_id'],
      'w': afterRefund['wallets'],
    },
  }, lens: 'BE8');

  final stAfter = '${afterRefund['order']?['status']}';
  if (rf.ok && stAfter == 'cancelado') {
    c.hold(
      id: 'BE8.refund_rewrites_cancelado',
      lens: 'BE8',
      severity: 'P2',
      title: 'refund em ciclo devolve reescreve status cancelado',
      actor: 'S1 refund-order',
      pre: 'estado ${beforeRefund['order']?['status']}',
      repro: 'POST refund-order',
      expected: 'terminal devolvida se estava devolvida',
      obtained: stAfter,
    );
  }

  // 2.º checkout no mesmo SKU após refund.
  final oid2 = await c.insertOrder(
    productId: p8.pid,
    jwt: c.buyerJwt,
    price: 5,
  );
  if (oid2 != null) {
    final sess = await c.checkout(
      orderId: oid2,
      productId: p8.pid,
      amount: 5,
      jwt: c.buyerJwt,
    );
    c.note('BE8.second_session', '2.ª Session após refund/ciclo', sess.brief,
        lens: 'BE8');
  }

  final qty0 = numOf(pr0?['quantity']) ?? 0;
  final qtyF = numOf(afterRefund['product']?['quantity']) ?? 0;
  c.note('BE8.books', 'Δ stock/wallets', {
    'qty0': qty0,
    'qtyF': qtyF,
    'w0': w0,
    'wF': afterRefund['wallets'],
    'statusF': stAfter,
  }, lens: 'BE8');

  // Refund during enviado (should 403) — dedicated order.
  final pR = await mustPay('BE4');
  await c.patchOrder(pR.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final rfShip = await c.refund(pR.oid, jwt: c.sellerJwt);
  c.note('BE4.refund_enviado', 'refund-order em enviado', rfShip.brief,
      lens: 'BE4');
  if (rfShip.ok) {
    c.hold(
      id: 'BE4.refund_while_enviado',
      lens: 'BE4',
      severity: 'P1',
      title: 'refund-order em enviado (captura anulada com item a caminho)',
      actor: 'S1 JWT',
      pre: 'enviado shipped_at set',
      repro: 'POST refund-order',
      expected: '403 order_refund_blocked_shipped',
      obtained: rfShip.brief,
    );
  } else {
    c.block('BE4.refund_enviado', 'BE4', 'refund enviado', rfShip);
  }

  await c.dumpAll('pass1.json');
  stdout.writeln(
      'DONE pass1 findings=${c.findings.length} blocked=${c.blocked.length} skipped=${c.skipped.length} lenses=${c.lensesHit.toList()..sort()}');
}
