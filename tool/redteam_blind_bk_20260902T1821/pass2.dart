/// REDTEAM_BLIND_BK pass2 — PI hostage, provas/URLs, refund, stock, release, disputa.
/// Staging. Não corrigir.
import 'dart:io';
import '_rtbk.dart';

Future<void> main() async {
  final c = Rtbk.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.wallets();
  c.note('w0', 'wallets start pass2', w0);

  await _bk6PiHostage(c, w0);
  await _bk3ProofsAndReplies(c);
  await _bk4PartialRefundAndEdge(c, w0);
  await _bk5StockRestore(c);
  await _bk6Release(c, w0);
  await _bk7DisputeAfterFix(c);
  await _bk8Caixa(c, w0);

  await c.dumpAll('pass2.json');
  stdout.writeln(
    'pass2 done findings=${c.findings.length} blocked=${c.blocked.length} '
    'lenses=${c.lensesHit.toList()..sort()}',
  );
}

/// Seller freeze pago→pedido_devolucao: PI hostage, no disputa, no refund Edge.
Future<void> _bk6PiHostage(Rtbk c, Map<String, num?> w0) async {
  final paid = await c.setupPaid(initialQty: 3);
  if (paid == null) {
    c.skip('BK6.hostage', 'BK6', 'setup_paid falhou', 'no fixture');
    return;
  }
  final oid = paid['order_id'].toString();
  final pid = paid['product_id'].toString();
  final pi = paid['payment_intent_id']?.toString();
  final qty0 = await c.productQty(pid);
  final row0 = await c.orderRow(oid);

  final hop = await c.patchOrder(oid, {'status': 'pedido_devolucao'}, jwt: c.sellerJwt);
  var row = await c.orderRow(oid);
  if ('${row?['status']}'.toLowerCase() != 'pedido_devolucao') {
    c.skip('BK6.hostage.hop', 'BK6', 'seller pedido não persistiu (já fechado?)', hop);
    return;
  }

  final buyerDisp = await c.openDispute(oid);
  final buyerConc = await c.patchOrder(oid, {'status': 'concluido'}, jwt: c.buyerJwt);
  final sellerShip = await c.patchOrder(oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final refund = await c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt);
  final rel = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': oid},
    jwt: c.buyerJwt,
  );
  final em = await c.patchOrder(oid, {'status': 'em_devolucao'}, jwt: c.sellerJwt);
  row = await c.orderRow(oid);
  final qty1 = await c.productQty(pid);
  final w1 = await c.wallets();

  final hostage = {
    'oid': oid,
    'pi': pi,
    'status0': row0?['status'],
    'status': row?['status'],
    'hop': hop.brief,
    'buyer_dispute': buyerDisp.brief,
    'buyer_concluido': buyerConc.brief,
    'seller_enviado': sellerShip.brief,
    'refund_edge': refund.brief,
    'release': rel.brief,
    'seller_em': em.brief,
    'qty0': qty0,
    'qty1': qty1,
    'stock_units': row?['stock_units_applied'],
    'stripe_refund_id': row?['stripe_refund_id'],
    'amount_paid_cents': row?['amount_paid_cents'],
    'w0': w0,
    'w1': w1,
  };

  final disputeBlocked = buyerDisp.denied || buyerDisp.noop;
  final concBlocked = buyerConc.denied ||
      buyerConc.noop ||
      '${row?['status']}'.toLowerCase() != 'concluido';
  final refundBlocked = refund.denied || refund.map?['ok'] != true;
  final stillCaptured = (row?['stripe_refund_id'] == null ||
          '${row?['stripe_refund_id']}'.isEmpty) &&
      (numOf(row?['amount_paid_cents']) ?? 0) > 0;
  final stillPedido = '${row?['status']}'.toLowerCase() == 'pedido_devolucao' ||
      '${row?['status']}'.toLowerCase() == 'em_devolucao';

  if (stillPedido && stillCaptured && disputeBlocked && concBlocked && refundBlocked) {
    c.hold(
      id: 'BK6.pi_hostage_seller_pedido',
      lens: 'BK6',
      severity: 'P1',
      title:
          'Seller congela encomenda paga em pedido_devolucao: PI capturado, sem disputa, sem refund Edge, sem concluido',
      actor: 'seller JWT',
      pre: 'pago capturado stock_units_applied=1',
      repro: 'PATCH status=pedido_devolucao; POST disputa; PATCH concluido; Edge refund-order',
      expected: 'hop recusado OU buyer ainda consegue disputa/refund/concluido',
      obtained: hostage,
      evidence: {'row': row, 'qty': qty1},
    );
  } else {
    c.note('BK6.hostage.partial', 'não hostage completo', hostage, lens: 'BK6');
  }

  // Continue chain: em_devolucao → devolucao_entregue → devolvida sem disputa
  if ('${row?['status']}'.toLowerCase() == 'em_devolucao' ||
      '${(await c.orderRow(oid))?['status']}'.toLowerCase() == 'em_devolucao') {
    final ent = await c.patchOrder(
      oid,
      {'status': 'devolucao_entregue'},
      jwt: c.sellerJwt,
    );
    row = await c.orderRow(oid);
    c.note('BK6.ent', 'seller devolucao_entregue', {
      'patch': ent.brief,
      'status': row?['status'],
    }, lens: 'BK2');

    final dev = await c.patchOrder(oid, {'status': 'devolvida'}, jwt: c.sellerJwt);
    final rowDev = await c.orderRow(oid);
    final qty2 = await c.productQty(pid);
    if ('${rowDev?['status']}'.toLowerCase() == 'devolvida') {
      c.hold(
        id: 'BK2.seller_devolvida_sem_disputa',
        lens: 'BK2',
        severity: 'P1',
        title: 'Seller completa FSM até devolvida sem disputa do comprador',
        actor: 'seller JWT',
        pre: 'pedido iniciado pelo seller, sem order_disputes',
        repro: 'em_devolucao → devolucao_entregue → devolvida',
        expected: 'order_devolvida_requires_dispute',
        obtained: {
          'patch': dev.brief,
          'status': rowDev?['status'],
          'qty0': qty0,
          'qty2': qty2,
          'refund': rowDev?['stripe_refund_id'],
        },
        evidence: {'row': rowDev},
      );
    } else {
      c.block('BK2.seller_devolvida_sem_disputa', 'BK2', 'devolvida sem disputa', {
        'ent': ent.brief,
        'dev': dev.brief,
        'status': rowDev?['status'],
      });
    }
  }
}

Future<void> _bk3ProofsAndReplies(Rtbk c) async {
  final paid = await c.setupPaid();
  if (paid == null) {
    c.skip('BK3.paid', 'BK3', 'setup_paid falhou', 'no fixture');
    return;
  }
  final oid = paid['order_id'].toString();
  if (!await c.toConcluido(oid)) {
    c.skip('BK3.conc', 'BK3', 'concluido falhou', await c.orderRow(oid));
    return;
  }
  final d = await c.openDispute(oid);
  if (!d.ok) {
    c.skip('BK3.open', 'BK3', 'disputa falhou', d);
    return;
  }
  final did = d.firstId!;
  final nMine = c.needle(c.buyerId, oid);
  final nOther = c.needle(c.buyer2Id, '00000000-0000-0000-0000-000000000001');

  Future<void> tryUrl(String id, String title, Map<String, Object?> body,
      {String sev = 'P2'}) async {
    final h = await c.patchDispute(did, body, jwt: c.buyerJwt);
    final after = await c.disputeByOrder(oid);
    final persisted = h.ok && !h.noop;
    var stored = false;
    if (body.containsKey('return_label_url')) {
      stored = '${after?['return_label_url']}' == body['return_label_url'];
    }
    if (body.containsKey('proof_photos')) {
      stored = '${after?['proof_photos']}'.contains('${(body['proof_photos'] as List).first}');
    }
    if (persisted && stored) {
      c.hold(
        id: id,
        lens: 'BK3',
        severity: sev,
        title: title,
        actor: 'buyer JWT',
        pre: 'disputa aberta concluido',
        repro: 'PATCH order_disputes $body',
        expected: 'URL recusada (bind/host/wrap)',
        obtained: {'patch': h.brief, 'row': after},
      );
    } else {
      c.block(id, 'BK3', title, h);
    }
  }

  await tryUrl(
    'BK3.label_evil_host',
    'return_label_url host evil com needle no path',
    {'return_label_url': 'https://evil.example/$nMine/x.pdf'},
  );
  await tryUrl(
    'BK3.label_wrap_query',
    'return_label wrap: fleaber.app query com needle (sem 2.º https)',
    {
      'return_label_url':
          'https://fleaber.app/labels?ref=${Uri.encodeComponent(nMine)}'
    },
  );
  await tryUrl(
    'BK3.label_wrap_storage_other',
    'return_label wrap storage alheio + needle em query',
    {
      'return_label_url':
          '${c.storageBase}/$nOther/secret.png?q=$nMine'
    },
    sev: 'P1',
  );
  await tryUrl(
    'BK3.photos_wrap_storage_other',
    'proof_photos wrap storage alheio + needle em query',
    {
      'proof_photos': ['${c.storageBase}/$nOther/secret.png?q=$nMine']
    },
    sev: 'P1',
  );
  await tryUrl(
    'BK3.photos_javascript',
    'proof_photos javascript: com needle',
    {
      'proof_photos': ['javascript:alert(1)//$nMine']
    },
    sev: 'P2',
  );

  // Replies: INSERT limpo, PATCH wrap/javascript
  final ins = await c.rest('POST', 'order_dispute_replies', jwt: c.buyerJwt, body: {
    'dispute_id': did,
    'sender_id': c.buyerId,
    'message': 'ok',
    'proof_photos': <String>[],
  });
  c.note('BK3.reply_ins', 'INSERT reply', ins.brief, lens: 'BK3');
  final rid = ins.firstId;
  if (rid != null) {
    final js = 'javascript:alert(1)//$nMine';
    final p = await c.rest(
      'PATCH',
      'order_dispute_replies?id=eq.$rid',
      jwt: c.buyerJwt,
      body: {
        'proof_photos': [js],
      },
    );
    final after = await c.rest(
      'GET',
      'order_dispute_replies?id=eq.$rid&select=id,proof_photos',
      service: true,
    );
    final stored = '${after.map?['proof_photos']}'.contains('javascript:');
    if ((p.ok && !p.noop) && stored) {
      c.hold(
        id: 'BK3.reply_patch_javascript',
        lens: 'BK3',
        severity: 'P2',
        title: 'PATCH reply proof_photos javascript: (bind só no INSERT)',
        actor: 'buyer JWT',
        pre: 'reply sem fotos',
        repro: 'PATCH proof_photos=[javascript:…needle]',
        expected: 'dispute_proof_url_denied',
        obtained: {'patch': p.brief, 'row': after.map},
      );
    } else {
      c.block('BK3.reply_patch_javascript', 'BK3', 'reply PATCH js', p);
    }

    final wrap =
        '${c.storageBase}/$nOther/x.png?q=$nMine';
    final p2 = await c.rest(
      'PATCH',
      'order_dispute_replies?id=eq.$rid',
      jwt: c.buyerJwt,
      body: {
        'proof_photos': [wrap],
      },
    );
    final after2 = await c.rest(
      'GET',
      'order_dispute_replies?id=eq.$rid&select=id,proof_photos',
      service: true,
    );
    final stored2 = '${after2.map?['proof_photos']}'.contains(nOther);
    if ((p2.ok && !p2.noop) && stored2) {
      c.hold(
        id: 'BK3.reply_patch_wrap',
        lens: 'BK3',
        severity: 'P1',
        title: 'PATCH reply proof_photos wrap URL alheia (needle em query)',
        actor: 'buyer JWT',
        pre: 'reply existente',
        repro: 'PATCH proof_photos=[storage/other?q=needle]',
        expected: 'URL recusada',
        obtained: {'patch': p2.brief, 'row': after2.map},
      );
    } else {
      c.block('BK3.reply_patch_wrap', 'BK3', 'reply PATCH wrap', p2);
    }

    // B2 lê replies
    if (c.buyer2Jwt != null) {
      final leak = await c.rest(
        'GET',
        'order_dispute_replies?id=eq.$rid&select=id,message,proof_photos',
        jwt: c.buyer2Jwt,
      );
      await c.expectDenied(
        id: 'BK7.b2_read_replies',
        lens: 'BK7',
        title: 'B2 lê replies da disputa B1',
        hit: leak,
        actor: 'buyer2 JWT',
        pre: 'reply B1',
        repro: 'GET order_dispute_replies',
        severityIfOpen: 'P2',
      );
    }
  } else {
    c.skip('BK3.reply', 'BK3', 'INSERT reply falhou', ins);
  }
}

Future<void> _bk4PartialRefundAndEdge(Rtbk c, Map<String, num?> w0) async {
  final paid = await c.setupPaid();
  if (paid == null) {
    c.skip('BK4.paid', 'BK4', 'setup_paid falhou', 'no fixture');
    return;
  }
  final oid = paid['order_id'].toString();

  // Edge extra amount / buyer actor
  final buyerRef = await c.edge('refund-order', {
    'order_id': oid,
    'amount': 1,
    'amount_cents': 1,
  }, jwt: c.buyerJwt);
  await c.expectDenied(
    id: 'BK4.buyer_refund_edge',
    lens: 'BK4',
    title: 'Buyer chama refund-order',
    hit: buyerRef,
    actor: 'buyer JWT',
    pre: 'pago capturado',
    repro: 'Edge refund-order',
    severityIfOpen: 'P0',
  );
  // expectDenied treats 200 as open — Edge 403 is denied. 200 skipped:true is ok-ish.
  if (buyerRef.ok && buyerRef.map?['ok'] == true && buyerRef.map?['skipped'] != true) {
    c.hold(
      id: 'BK4.buyer_refund_edge_ok',
      lens: 'BK4',
      severity: 'P0',
      title: 'Buyer refund-order executou Stripe',
      actor: 'buyer JWT',
      pre: 'pago',
      repro: 'Edge refund-order JWT buyer',
      expected: '403 Sem permissão',
      obtained: buyerRef.brief,
    );
  } else if (buyerRef.denied || buyerRef.map?['skipped'] == true) {
    c.block('BK4.buyer_refund_edge', 'BK4', 'buyer refund-order', buyerRef);
  }

  if (c.buyer2Jwt != null) {
    final b2 = await c.edge('refund-order', {'order_id': oid}, jwt: c.buyer2Jwt);
    if (b2.ok && b2.map?['ok'] == true && b2.map?['skipped'] != true) {
      c.hold(
        id: 'BK4.b2_refund_edge',
        lens: 'BK4',
        severity: 'P0',
        title: 'B2 refund-order na order de B1',
        actor: 'buyer2 JWT',
        pre: 'pago B1',
        repro: 'Edge refund-order',
        expected: '403',
        obtained: b2.brief,
      );
    } else {
      c.block('BK4.b2_refund_edge', 'BK4', 'B2 refund-order', b2);
    }
  }

  if (!await c.toConcluido(oid)) {
    c.skip('BK4.conc', 'BK4', 'concluido falhou', await c.orderRow(oid));
    return;
  }
  final d = await c.openDispute(oid);
  if (!d.ok) {
    c.skip('BK4.disp', 'BK4', 'disputa falhou', d);
    return;
  }
  final did = d.firstId!;

  // Seller offer 50% — does it mint wallet via RPC on concluido+PI?
  final offer = await c.patchDispute(did, {
    'seller_offer_type': 'partial_refund',
    'seller_refund_percent': 50,
    'seller_offer_set_by': c.sellerId,
  }, jwt: c.sellerJwt);
  c.note('BK4.offer', 'seller partial 50%', offer.brief, lens: 'BK4');

  final wBefore = await c.wallets();
  final rpcBuyer = await c.rpc(
    'batata_process_partial_refund_dispute',
    {'p_order_id': oid, 'p_refund_percent': 100},
    jwt: c.buyerJwt,
  );
  final wAfter = await c.wallets();
  final row = await c.orderRow(oid);
  final minted = (numOf(wAfter['buyer']) ?? 0) > (numOf(wBefore['buyer']) ?? 0) &&
      (row?['stripe_refund_id'] == null || '${row?['stripe_refund_id']}'.isEmpty);

  if (rpcBuyer.ok && minted) {
    c.hold(
      id: 'BK4.partial_wallet_without_stripe',
      lens: 'BK4',
      severity: 'P0',
      title: 'Partial refund disputa minta wallet sem Stripe (concluido+PI)',
      actor: 'buyer JWT',
      pre: 'concluido capturado + oferta 50%',
      repro: 'rpc batata_process_partial_refund_dispute p_refund_percent=100',
      expected: 'dispute_partial_refund_requires_stripe',
      obtained: {
        'rpc': rpcBuyer.brief,
        'wBefore': wBefore,
        'wAfter': wAfter,
        'row': row,
      },
    );
  } else {
    c.block('BK4.partial_wallet_without_stripe', 'BK4', 'partial RPC', {
      'rpc': rpcBuyer.brief,
      'wBefore': wBefore,
      'wAfter': wAfter,
    });
  }

  // Seller RPC — 200 false / 4xx = HOLD
  final rpcSeller = await c.rpc(
    'batata_process_partial_refund_dispute',
    {'p_order_id': oid, 'p_refund_percent': 50},
    jwt: c.sellerJwt,
  );
  if (rpcSeller.ok && rpcSeller.json == true) {
    c.hold(
      id: 'BK4.seller_partial_rpc',
      lens: 'BK4',
      severity: 'P1',
      title: 'Seller corre partial refund RPC com efeito',
      actor: 'seller JWT',
      pre: 'disputa com oferta',
      repro: 'rpc batata_process_partial_refund_dispute',
      expected: 'not_allowed / false',
      obtained: rpcSeller.brief,
    );
  } else {
    c.block('BK4.seller_partial_rpc', 'BK4', 'seller partial RPC', rpcSeller);
  }

  // Edge refund with open dispute
  final edgeDisp = await c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt);
  final row2 = await c.orderRow(oid);
  if (edgeDisp.ok &&
      edgeDisp.map?['ok'] == true &&
      edgeDisp.map?['skipped'] != true &&
      '${row2?['stripe_refund_id']}'.isNotEmpty) {
    c.hold(
      id: 'BK4.edge_refund_open_dispute',
      lens: 'BK4',
      severity: 'P1',
      title: 'refund-order Stripe com disputa aberta',
      actor: 'seller JWT',
      pre: 'concluido + disputa aberta',
      repro: 'Edge refund-order',
      expected: '403 order_refund_blocked_open_dispute',
      obtained: {'edge': edgeDisp.brief, 'row': row2},
    );
  } else {
    c.block('BK4.edge_refund_open_dispute', 'BK4', 'refund com disputa', edgeDisp);
  }
}

Future<void> _bk5StockRestore(Rtbk c) async {
  final paid = await c.setupPaid(initialQty: 2);
  if (paid == null) {
    c.skip('BK5.paid', 'BK5', 'setup_paid falhou', 'no fixture');
    return;
  }
  final oid = paid['order_id'].toString();
  final pid = paid['product_id'].toString();
  final qtyPago = await c.productQty(pid);

  // Seller pedido then try cancelado
  await c.patchOrder(oid, {'status': 'pedido_devolucao'}, jwt: c.sellerJwt);
  final qtyPedido = await c.productQty(pid);
  final cancel = await c.patchOrder(oid, {'status': 'cancelado'}, jwt: c.sellerJwt);
  final rowC = await c.orderRow(oid);
  final qtyC = await c.productQty(pid);
  if ('${rowC?['status']}'.toLowerCase() == 'cancelado' &&
      (qtyC ?? 0) > (qtyPago ?? 0)) {
    c.hold(
      id: 'BK5.cancel_restores_while_captured',
      lens: 'BK5',
      severity: 'P0',
      title: 'cancelado em pedido_devolucao repõe stock com PI vivo',
      actor: 'seller JWT',
      pre: 'pago→pedido_devolucao, PI capturado',
      repro: 'PATCH cancelado',
      expected: 'order_cancel_denied_post_pay',
      obtained: {
        'patch': cancel.brief,
        'status': rowC?['status'],
        'qtyPago': qtyPago,
        'qtyC': qtyC,
        'pi': rowC?['stripe_payment_intent_id'],
        'refund': rowC?['stripe_refund_id'],
      },
    );
  } else {
    c.block('BK5.cancel_restores_while_captured', 'BK5', 'cancel pós-pago', {
      'patch': cancel.brief,
      'status': rowC?['status'],
      'qtyPago': qtyPago,
      'qtyPedido': qtyPedido,
      'qtyC': qtyC,
    });
  }

  // Honest: refund on a FRESH pago (no dispute) then check stock once
  final paid2 = await c.setupPaid(initialQty: 2);
  if (paid2 == null) return;
  final oid2 = paid2['order_id'].toString();
  final pid2 = paid2['product_id'].toString();
  final qBefore = await c.productQty(pid2);
  final ref = await c.edge('refund-order', {'order_id': oid2}, jwt: c.sellerJwt);
  final rowR = await c.orderRow(oid2);
  final qAfter = await c.productQty(pid2);
  c.note('BK5.refund_stock', 'refund-order em pago', {
    'edge': ref.brief,
    'status': rowR?['status'],
    'qBefore': qBefore,
    'qAfter': qAfter,
    'units': rowR?['stock_units_applied'],
    'refund_id': rowR?['stripe_refund_id'],
  }, lens: 'BK5');

  // Race: two refund-order
  final paid3 = await c.setupPaid(initialQty: 2);
  if (paid3 == null) return;
  final oid3 = paid3['order_id'].toString();
  final pid3 = paid3['product_id'].toString();
  final q3b = await c.productQty(pid3);
  final raced = await Future.wait([
    c.edge('refund-order', {'order_id': oid3}, jwt: c.sellerJwt),
    c.edge('refund-order', {'order_id': oid3}, jwt: c.sellerJwt),
  ]);
  final row3 = await c.orderRow(oid3);
  final q3a = await c.productQty(pid3);
  final restored = (q3a ?? 0) - (q3b ?? 0);
  c.note('BK5.race_refund', '2× refund-order', {
    'a': raced[0].brief,
    'b': raced[1].brief,
    'status': row3?['status'],
    'qBefore': q3b,
    'qAfter': q3a,
    'delta': restored,
    'units': row3?['stock_units_applied'],
  }, lens: 'BK5');
  if (restored >= 2) {
    c.hold(
      id: 'BK5.dup_stock_restore',
      lens: 'BK5',
      severity: 'P0',
      title: 'Race 2× refund-order restaurou stock 2×',
      actor: 'seller JWT ×2',
      pre: 'pago stock applied=1',
      repro: 'Future.wait 2× Edge refund-order',
      expected: 'Δqty ≤ 1',
      obtained: {
        'delta': restored,
        'qBefore': q3b,
        'qAfter': q3a,
        'a': raced[0].brief,
        'b': raced[1].brief,
      },
    );
  } else {
    c.block('BK5.dup_stock_restore', 'BK5', 'race refund stock', {
      'delta': restored,
      'qBefore': q3b,
      'qAfter': q3a,
    });
  }
}

Future<void> _bk6Release(Rtbk c, Map<String, num?> w0) async {
  final paid = await c.setupPaid();
  if (paid == null) {
    c.skip('BK6.rel', 'BK6', 'setup_paid falhou', 'no fixture');
    return;
  }
  final oid = paid['order_id'].toString();
  if (!await c.toConcluido(oid)) {
    c.skip('BK6.rel.conc', 'BK6', 'concluido falhou', await c.orderRow(oid));
    return;
  }
  final d = await c.openDispute(oid);
  if (!d.ok) {
    c.skip('BK6.rel.d', 'BK6', 'disputa falhou', d);
    return;
  }
  final wB = await c.wallets();
  final rel = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': oid},
    jwt: c.buyerJwt,
  );
  final wA = await c.wallets();
  final row = await c.orderRow(oid);
  final credited = (numOf(wA['seller']) ?? 0) > (numOf(wB['seller']) ?? 0);
  if (rel.ok && credited) {
    c.hold(
      id: 'BK6.release_open_dispute',
      lens: 'BK6',
      severity: 'P0',
      title: 'Release wallet com disputa aberta',
      actor: 'buyer JWT',
      pre: 'concluido + disputa aberta',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false / sem Δ seller',
      obtained: {
        'rpc': rel.brief,
        'wB': wB,
        'wA': wA,
        'released_at': row?['wallet_release_processed_at'],
      },
    );
  } else {
    c.block('BK6.release_open_dispute', 'BK6', 'release open dispute', {
      'rpc': rel.brief,
      'wB': wB,
      'wA': wA,
      'released_at': row?['wallet_release_processed_at'],
    });
  }

  // Buyer PATCH pedido then try release
  await c.patchOrder(oid, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt);
  final rel2 = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': oid},
    jwt: c.buyerJwt,
  );
  final st = '${(await c.orderRow(oid))?['status']}';
  if (rel2.ok && rel2.json == true) {
    c.hold(
      id: 'BK6.release_during_return',
      lens: 'BK6',
      severity: 'P0',
      title: 'Release durante pedido_devolucao',
      actor: 'buyer JWT',
      pre: 'pedido_devolucao',
      repro: 'rpc release',
      expected: 'false',
      obtained: {'rpc': rel2.brief, 'status': st},
    );
  } else {
    c.block('BK6.release_during_return', 'BK6', 'release during return', {
      'rpc': rel2.brief,
      'status': st,
    });
  }
}

Future<void> _bk7DisputeAfterFix(Rtbk c) async {
  final paid = await c.setupPaid();
  if (paid == null) return;
  final oid = paid['order_id'].toString();
  if (!await c.toConcluido(oid)) return;
  final d1 = await c.openDispute(oid);
  if (!d1.ok) {
    c.skip('BK7.d1', 'BK7', '1.ª disputa falhou', d1);
    return;
  }
  c.block('BK7.open_ok', 'BK7', 'INSERT disputa concluido', d1);
  final d2 = await c.openDispute(oid);
  await c.expectDenied(
    id: 'BK7.second_dispute_insert',
    lens: 'BK7',
    title: '2.ª disputa INSERT no mesmo order',
    hit: d2,
    actor: 'buyer JWT',
    pre: 'já existe disputa',
    repro: 'POST order_disputes',
    severityIfOpen: 'P1',
  );

  final did = d1.firstId;
  if (did == null) return;
  final close = await c.patchDispute(did, {'status': 'recusada'}, jwt: c.buyerJwt);
  c.note('BK7.recusa', 'buyer recusa', close.brief, lens: 'BK7');
  final d3 = await c.openDispute(oid);
  final all = await c.rest(
    'GET',
    'order_disputes?order_id=eq.$oid&select=id,status',
    service: true,
  );
  if (d3.ok && all.list.length >= 2) {
    c.hold(
      id: 'BK7.reopen_after_recusada',
      lens: 'BK7',
      severity: 'P1',
      title: '2.ª disputa após recusada',
      actor: 'buyer JWT',
      pre: '1.ª recusada',
      repro: 'POST order_disputes',
      expected: 'já existe',
      obtained: {'insert': d3.brief, 'n': all.list.length, 'rows': all.list},
    );
  } else {
    c.block('BK7.reopen_after_recusada', 'BK7', 'reopen', {
      'close': close.brief,
      'insert': d3.brief,
      'n': all.list.length,
    });
  }

  // mid-return concluido now that disputa exists
  await c.patchOrder(oid, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt);
  final conc = await c.patchOrder(oid, {'status': 'concluido'}, jwt: c.buyerJwt);
  final row = await c.orderRow(oid);
  if ('${row?['status']}'.toLowerCase() == 'concluido') {
    c.hold(
      id: 'BK2.buyer_concluido_mid_return',
      lens: 'BK2',
      severity: 'P1',
      title: 'Buyer força concluido a meio da devolução',
      actor: 'buyer JWT',
      pre: 'pedido_devolucao + disputa',
      repro: 'PATCH concluido',
      expected: 'denied',
      obtained: {'patch': conc.brief, 'status': row?['status']},
    );
  } else {
    c.block('BK2.buyer_concluido_mid_return', 'BK2', 'concluido mid-return', conc);
  }

  if (c.buyer2Jwt != null) {
    final b2 = await c.openDispute(oid, jwt: c.buyer2Jwt, buyer: c.buyer2Id);
    await c.expectDenied(
      id: 'BK7.b2_dispute',
      lens: 'BK7',
      title: 'B2 disputa order B1 (reason válido)',
      hit: b2,
      actor: 'buyer2 JWT',
      pre: 'order B1',
      repro: 'POST order_disputes reason=danificado',
      severityIfOpen: 'P1',
    );
  }
}

Future<void> _bk8Caixa(Rtbk c, Map<String, num?> w0) async {
  final w = await c.wallets();
  c.note('BK8.wallets', 'Δ pass2 vs start', {
    'w0': w0,
    'wNow': w,
    'dBuyer': (numOf(w['buyer']) ?? 0) - (numOf(w0['buyer']) ?? 0),
    'dSeller': (numOf(w['seller']) ?? 0) - (numOf(w0['seller']) ?? 0),
  }, lens: 'BK8');
  final dB = (numOf(w['buyer']) ?? 0) - (numOf(w0['buyer']) ?? 0);
  final dS = (numOf(w['seller']) ?? 0) - (numOf(w0['seller']) ?? 0);
  if (dB > 0.009 && dS > 0.009) {
    c.hold(
      id: 'BK8.dual_credit',
      lens: 'BK8',
      severity: 'P0',
      title: 'Δ buyer e Δ seller positivos no mesmo passe (possível mint)',
      actor: 'lab',
      pre: 'pass2 probes',
      repro: 'Δ wallets',
      expected: 'sem crédito duplo',
      obtained: {'w0': w0, 'w': w, 'dB': dB, 'dS': dS},
    );
  }
}
