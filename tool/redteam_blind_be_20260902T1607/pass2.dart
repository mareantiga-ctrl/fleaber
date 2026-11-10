/// RED TEAM CEGO BE — pass 2. Observar pass1 (orderRow consertado) + confirmar hops.
import 'dart:io';
import '_rtbe.dart';

Future<void> main() async {
  final c = Rtbe.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  Future<Map<String, dynamic>?> disputeOf(String oid) async {
    final h = await c.rest(
      'GET',
      'order_disputes?order_id=eq.$oid&select=id,status,buyer_id,proof_photos,seller_refund_percent,seller_offer_type,seller_offer_set_by,buyer_decision,current_turn,return_label_url&order=created_at.desc',
      service: true,
    );
    return h.map;
  }

  const pass1Orders = <String, String>{
    'p1_pago': '36b410dd-5df0-47c6-af61-024db928825b',
    'p2_skip': 'fbd46089-ab95-420f-816a-f768584c9552',
    'p5_concluido': 'cc4dbd38-d21a-4a97-aa7b-5a5228086532',
    'pMao': '81e6ac87-b6e9-4339-9a80-41dbe84f8f6b',
    'p7_proof': 'a27a828b-adbb-4014-9d0c-7329b33792a8',
    'p8_comp': '17b4d90a-99e9-4beb-8dc3-c5bf6a1b540f',
    'pR_enviado': '05554fd3-58e6-49a9-9ebd-211e11d52c08',
  };

  for (final e in pass1Orders.entries) {
    final row = await c.orderRow(e.value);
    final prod = row?['product_id'] == null
        ? null
        : await c.productRow('${row!['product_id']}');
    c.note('obs.${e.key}', 'estado pass1', {
      'oid': e.value,
      'status': row?['status'],
      'paid': row?['amount_paid_cents'],
      'refund': row?['stripe_refund_id'],
      'applied': row?['stock_units_applied'],
      'shipped_at': row?['shipped_at'],
      'qty_order': row?['quantity'],
      'qty_prod': prod?['quantity'],
      'pi': row?['stripe_payment_intent_id'],
      'release': row?['wallet_release_processed_at'],
      'ship': row?['shipping_method'],
    }, lens: 'BE8');
  }

  final d2 = await disputeOf(pass1Orders['p2_skip']!);
  c.note('obs.p2.dispute', 'disputa p2 (oferta?)', d2, lens: 'BE4');
  final d8 = await disputeOf(pass1Orders['p8_comp']!);
  c.note('obs.p8.dispute', 'disputa p8', d8, lens: 'BE8');

  final p8 = await c.orderRow(pass1Orders['p8_comp']!);
  final pi8 = p8?['stripe_payment_intent_id']?.toString();
  if (pi8 != null && pi8.isNotEmpty) {
    final listed = await c.stripe('GET', '/v1/refunds?payment_intent=$pi8&limit=5');
    c.note('obs.p8.stripe_refunds', 'refunds Stripe TEST p8', listed.brief,
        lens: 'BE8');
  }

  // ---- Confirmar hop skip B1 → devolucao_entregue (pass1 Edge já disse) ----
  final p2 = await c.orderRow(pass1Orders['p2_skip']!);
  if ('${p2?['status']}' == 'devolucao_entregue') {
    c.hold(
      id: 'BE3.buyer_skip_devolucao_entregue',
      lens: 'BE3',
      severity: 'P1',
      title: 'B1 saltou para devolucao_entregue sem hops de devolução',
      actor: 'B1 JWT',
      pre: 'enviado→entregue→disputa; B1 PATCH devolucao_entregue',
      repro: 'PATCH orders.status=devolucao_entregue JWT buyer',
      expected: '403 / pedido_devolucao denied / inalterado entregue',
      obtained: {
        'status': p2?['status'],
        'shipped_at': p2?['shipped_at'],
        'applied': p2?['stock_units_applied'],
        'refund': p2?['stripe_refund_id'],
        'edge_refund_gate': 'order_refund_blocked_shipped + status devolucao_entregue',
      },
    );
    final dv = await c.patchOrder(
      pass1Orders['p2_skip']!,
      {'status': 'devolvida'},
      jwt: c.sellerJwt,
    );
    final p2b = await c.orderRow(pass1Orders['p2_skip']!);
    c.note('BE3.s1_devolvida_after_skip', 'S1 devolvida após skip B1', {
      'hit': dv.brief,
      'status': p2b?['status'],
    }, lens: 'BE3');
    if ('${p2b?['status']}' == 'devolvida') {
      c.hold(
        id: 'BE3.skip_enables_devolvida',
        lens: 'BE3',
        severity: 'P1',
        title: 'Após B1 fingir devolucao_entregue, S1 marca devolvida',
        actor: 'B1+S1 JWT',
        pre: 'B1 skip hop',
        repro: 'PATCH devolvida JWT seller',
        expected: 'recusado se hop incompleto',
        obtained: p2b,
      );
      final rf = await c.refund(pass1Orders['p2_skip']!, jwt: c.sellerJwt);
      final p2c = await c.orderRow(pass1Orders['p2_skip']!);
      final prod = await c.productRow('${p2c?['product_id']}');
      c.note('BE8.refund_after_skip', 'refund após skip+devolvida', {
        'hit': rf.brief,
        'status': p2c?['status'],
        'refund': p2c?['stripe_refund_id'],
        'qty': prod?['quantity'],
        'applied': p2c?['stock_units_applied'],
        'wallets': await c.wallets(),
      }, lens: 'BE8');
    }
  }

  // ---- Confirmar p5 concluido + disputa + release ----
  final p5 = await c.orderRow(pass1Orders['p5_concluido']!);
  c.note('obs.p5', 'concluido+disputa?', p5?['status'], lens: 'BE5');
  if ('${p5?['status']}' == 'concluido') {
    final rel = await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': pass1Orders['p5_concluido'],
    }, jwt: c.buyerJwt);
    final w = await c.wallets();
    c.note('BE5.release_now', 'release p5', {'rpc': rel.brief, 'w': w},
        lens: 'BE5');
    if (rel.ok && rel.json == true) {
      c.hold(
        id: 'BE5.release_while_dispute',
        lens: 'BE5',
        severity: 'P0',
        title: 'Release carteira com disputa aberta (p5)',
        actor: 'B1 JWT',
        pre: 'status concluido + disputa',
        repro: 'rpc batata_release_seller_wallet_for_order',
        expected: 'false',
        obtained: {'rpc': rel.brief, 'wallets': w, 'dispute': await disputeOf(pass1Orders['p5_concluido']!)},
      );
    } else {
      c.block('BE5.release_while_dispute', 'BE5', 'release p5', rel);
    }
  }

  // ---- p8: refund reescreveu cancelado? stock +1? ----
  if ('${p8?['status']}' == 'cancelado' &&
      '${p8?['stripe_refund_id'] ?? ''}'.isNotEmpty) {
    c.hold(
      id: 'BE8.refund_status_cancelado',
      lens: 'BE8',
      severity: 'P2',
      title: 'Ciclo devolução terminou cancelado (não devolvida) após refund',
      actor: 'S1 refund-order',
      pre: 'hops pedido→em→entregue→devolvida então refund',
      repro: 'POST refund-order (já tinha stripe_refund_id)',
      expected: 'terminal devolvida se hops completos',
      obtained: {
        'status': p8?['status'],
        'refund': p8?['stripe_refund_id'],
        'applied': p8?['stock_units_applied'],
      },
    );
  }

  // =========================================================================
  // Probes novos com orderRow a funcionar
  // =========================================================================
  Future<({String oid, String pid, String? pi})> mustPay(String lens) async {
    final paid = await c.payToPago(lens: lens, initialQty: 1);
    if (paid == null) throw StateError('setup_paid_order $lens');
    return paid;
  }

  // BE1 NBSP / hops from pago with visible status
  final n1 = await mustPay('BE1');
  for (final st in ['cancelado\u00A0', 'concluído', 'em_devolucao', 'devolucao_entregue']) {
    final before = await c.orderRow(n1.oid);
    final hit = await c.patchOrder(n1.oid, {'status': st}, jwt: c.sellerJwt);
    final after = await c.orderRow(n1.oid);
    c.note('BE1.retry.$st', 'S1 PATCH [$st]', {
      'hit': hit.brief,
      'before': before?['status'],
      'after': after?['status'],
    }, lens: 'BE1');
    if ('${after?['status']}' != '${before?['status']}' && hit.ok) {
      c.hold(
        id: 'BE1.persist.$st',
        lens: 'BE1',
        severity: 'P1',
        title: 'S1 persistiu status inesperado $st desde pago',
        actor: 'S1 JWT',
        pre: 'pago',
        repro: 'PATCH status',
        expected: '403 / inalterado',
        obtained: after?['status'],
      );
    } else if (!hit.ok) {
      c.block('BE1.retry.$st', 'BE1', 'PATCH $st', hit);
    }
  }
  final bHop = await c.patchOrder(
    n1.oid,
    {'status': 'devolucao_entregue'},
    jwt: c.buyerJwt,
  );
  final n1b = await c.orderRow(n1.oid);
  c.note('BE1.buyer_from_pago', 'B1 devolucao_entregue desde pago', {
    'hit': bHop.brief,
    'status': n1b?['status'],
  }, lens: 'BE1');
  if ('${n1b?['status']}' == 'devolucao_entregue') {
    c.hold(
      id: 'BE1.buyer_devolucao_entregue_from_pago',
      lens: 'BE1',
      severity: 'P1',
      title: 'B1 marca devolucao_entregue desde pago (sem envio)',
      actor: 'B1 JWT',
      pre: 'pago',
      repro: 'PATCH devolucao_entregue',
      expected: '403',
      obtained: n1b?['status'],
    );
  } else {
    c.block('BE1.buyer_from_pago', 'BE1', 'B1 hop desde pago', bHop);
  }

  // BE3 hop skip reproduzido
  final n3 = await mustPay('BE3');
  await c.patchOrder(n3.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(n3.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  final ins = await c.insertDispute(orderId: n3.oid);
  c.note('BE3.n3.disp', 'disputa', ins.brief, lens: 'BE3');
  final sEnt = await c.orderRow(n3.oid);
  final skipEm = await c.patchOrder(
    n3.oid,
    {'status': 'em_devolucao'},
    jwt: c.buyerJwt,
  );
  final afterEm = await c.orderRow(n3.oid);
  c.note('BE3.n3.em', 'B1 entregue→em_devolucao', {
    'from': sEnt?['status'],
    'hit': skipEm.brief,
    'to': afterEm?['status'],
  }, lens: 'BE3');
  if ('${afterEm?['status']}' == 'em_devolucao') {
    c.hold(
      id: 'BE3.buyer_skip_pedido',
      lens: 'BE3',
      severity: 'P1',
      title: 'B1 salta pedido_devolucao e fica em_devolucao',
      actor: 'B1 JWT',
      pre: 'entregue+disputa',
      repro: 'PATCH em_devolucao',
      expected: 'order_pedido_devolucao_denied / inalterado',
      obtained: afterEm?['status'],
    );
  } else {
    c.block('BE3.buyer_skip_pedido', 'BE3', 'em_devolucao', skipEm);
  }

  final skipEnt = await c.patchOrder(
    n3.oid,
    {'status': 'devolucao_entregue'},
    jwt: c.buyerJwt,
  );
  final afterEnt = await c.orderRow(n3.oid);
  c.note('BE3.n3.ent', 'B1 → devolucao_entregue', {
    'hit': skipEnt.brief,
    'to': afterEnt?['status'],
  }, lens: 'BE3');
  if ('${afterEnt?['status']}' == 'devolucao_entregue') {
    c.hold(
      id: 'BE3.buyer_fake_return_delivered',
      lens: 'BE3',
      severity: 'P1',
      title: 'B1 marca devolucao_entregue (retorno nunca enviado)',
      actor: 'B1 JWT',
      pre: '${afterEm?['status']}+disputa',
      repro: 'PATCH devolucao_entregue JWT buyer',
      expected: 'só seller via hop',
      obtained: afterEnt,
    );
    final dv = await c.patchOrder(n3.oid, {'status': 'devolvida'}, jwt: c.sellerJwt);
    final afterDv = await c.orderRow(n3.oid);
    c.note('BE3.n3.dv', 'S1 devolvida', {
      'hit': dv.brief,
      'to': afterDv?['status'],
    }, lens: 'BE3');
    if ('${afterDv?['status']}' == 'devolvida') {
      final qtyB = numOf((await c.productRow(n3.pid))?['quantity']) ?? 0;
      final rf = await c.refund(n3.oid, jwt: c.sellerJwt);
      final afterRf = await c.orderRow(n3.oid);
      final qtyA = numOf((await c.productRow(n3.pid))?['quantity']) ?? 0;
      c.note('BE8.n3.refund', 'refund pós fake-return', {
        'hit': rf.brief,
        'status': afterRf?['status'],
        'refund': afterRf?['stripe_refund_id'],
        'qty': '$qtyB→$qtyA',
        'wallets': await c.wallets(),
      }, lens: 'BE8');
      if (rf.ok && '${afterRf?['stripe_refund_id'] ?? ''}'.isNotEmpty) {
        c.hold(
          id: 'BE8.fake_return_refund_stock',
          lens: 'BE8',
          severity: 'P1',
          title: 'Refund+stock após B1 fingir devolucao_entregue (item ficou com B1)',
          actor: 'B1 skip + S1 refund-order',
          pre: 'enviado/entregue, sem em_devolucao honesto',
          repro: 'B1 PATCH devolucao_entregue; S1 devolvida; refund-order',
          expected: 'B1 não avança hop; sem refund/stock',
          obtained: {
            'status': afterRf?['status'],
            'refund': afterRf?['stripe_refund_id'],
            'qty': '$qtyB→$qtyA',
            'rf': rf.brief,
          },
        );
      }
    }
  } else {
    c.block('BE3.buyer_fake_return_delivered', 'BE3', 'devolucao_entregue', skipEnt);
  }

  // BE4 — forjar oferta sem overwrite seller
  final n4 = await mustPay('BE4');
  await c.patchOrder(n4.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(n4.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  await c.insertDispute(orderId: n4.oid);
  final d4 = await disputeOf(n4.oid);
  final did4 = d4?['id']?.toString();
  if (did4 != null) {
    final forge = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did4',
      jwt: c.buyerJwt,
      body: {
        'seller_refund_percent': 100,
        'seller_offer_type': 'return_and_partial_refund',
        'seller_offer_set_by': c.sellerId,
      },
    );
    final d4b = await disputeOf(n4.oid);
    c.note('BE4.forge', 'B1 forja oferta 100% atribuída ao seller', {
      'hit': forge.brief,
      'percent': d4b?['seller_refund_percent'],
      'type': d4b?['seller_offer_type'],
      'set_by': d4b?['seller_offer_set_by'],
    }, lens: 'BE4');
    final pct = numOf(d4b?['seller_refund_percent']);
    if (forge.ok && pct != null && pct > 0) {
      c.hold(
        id: 'BE4.buyer_forges_seller_offer',
        lens: 'BE4',
        severity: 'P1',
        title: 'B1 grava seller_refund_percent / offer_type',
        actor: 'B1 JWT',
        pre: 'disputa aberta',
        repro: 'PATCH seller_refund_percent=100, seller_offer_set_by=S1',
        expected: 'campos de oferta só seller',
        obtained: {
          'percent': d4b?['seller_refund_percent'],
          'type': d4b?['seller_offer_type'],
          'set_by': d4b?['seller_offer_set_by'],
        },
      );
      final rpc = await c.rpc('batata_process_partial_refund_dispute', {
        'p_order_id': n4.oid,
      }, jwt: c.buyerJwt);
      c.note('BE4.rpc_after_forge', 'RPC após oferta forjada', rpc.brief,
          lens: 'BE4');
      if (rpc.ok && rpc.json == true) {
        c.hold(
          id: 'BE4.rpc_after_forged_offer',
          lens: 'BE4',
          severity: 'P1',
          title: 'RPC parcial corre com oferta forjada pelo buyer',
          actor: 'B1 JWT',
          pre: 'oferta 100% escrita por B1',
          repro: 'rpc batata_process_partial_refund_dispute',
          expected: 'dispute_refund_offer_required / Stripe',
          obtained: rpc.brief,
        );
      } else {
        c.block('BE4.rpc_after_forge', 'BE4', 'RPC pós-forge', rpc);
      }
    } else {
      c.block('BE4.buyer_forges_seller_offer', 'BE4', 'PATCH oferta', forge);
    }

    // FECHADA/resolvida inglês já bloqueado; tentar cancelada na disputa
    final dCancel = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did4',
      jwt: c.buyerJwt,
      body: {'status': 'cancelada'},
    );
    c.note('BE1.disp_cancelada', 'B1 disputa status=cancelada', dCancel.brief,
        lens: 'BE1');
  }

  // BE7 — S2 lê prova B1? (já 404) / S1 lê path de encomenda S2
  final n7 = await c.e2e('setup_paid_order', {'initial_qty': 1},
      seller: c.seller2Id, buyer: c.buyer2Id);
  c.note('BE7.s2.paid', 'pago B2-S2', n7.brief, lens: 'BE7');
  final oidS2 = c.parseE2eOrderId(n7);
  if (oidS2 != null) {
    c.createdOrderIds.add(oidS2);
    await c.patchOrder(oidS2, {'status': 'enviado'}, jwt: c.seller2Jwt);
    await c.patchOrder(oidS2, {'status': 'entregue'}, jwt: c.buyer2Jwt);
    await c.insertDispute(
      orderId: oidS2,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    );
    final path =
        'order_disputes/${c.buyer2Id}/$oidS2/be7-s2.jpg';
    final up = await c.storage(
      'POST',
      'object/fleaber_private/$path',
      jwt: c.buyer2Jwt,
      bytes: List<int>.from('x'.codeUnits),
      contentType: 'image/jpeg',
    );
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
    c.note('BE7.cross_shop', 'S1 lê prova B2-S2', {
      'up': up.status,
      's1': getS1.status,
      's2': getS2.status,
    }, lens: 'BE7');
    if (getS1.ok) {
      c.hold(
        id: 'BE7.s1_reads_s2_proof',
        lens: 'BE7',
        severity: 'P1',
        title: 'S1 lê prova de disputa B2–S2',
        actor: 'S1 JWT',
        pre: path,
        repro: 'GET storage',
        expected: '404',
        obtained: getS1.status,
      );
    } else {
      c.block('BE7.s1_reads_s2_proof', 'BE7', 'S1 GET S2 path', getS1);
    }
  }

  // BE5 — concluido com disputa + release (fresco)
  final n5 = await mustPay('BE5');
  await c.patchOrder(n5.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(n5.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  await c.insertDispute(orderId: n5.oid);
  final conc = await c.patchOrder(n5.oid, {'status': 'concluido'}, jwt: c.buyerJwt);
  final n5a = await c.orderRow(n5.oid);
  c.note('BE5.n5.conc', 'concluido+disputa', {
    'hit': conc.brief,
    'status': n5a?['status'],
  }, lens: 'BE5');
  if ('${n5a?['status']}' == 'concluido') {
    c.hold(
      id: 'BE5.concluido_with_open_dispute',
      lens: 'BE5',
      severity: 'P2',
      title: 'B1 marca concluido com disputa aberta',
      actor: 'B1 JWT',
      pre: 'entregue+disputa aberta',
      repro: 'PATCH concluido',
      expected: 'bloqueado enquanto disputa aberta (opcional UX)',
      obtained: n5a?['status'],
    );
    final rel = await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': n5.oid,
    }, jwt: c.buyerJwt);
    if (rel.ok && rel.json == true) {
      c.hold(
        id: 'BE5.release_open_dispute',
        lens: 'BE5',
        severity: 'P0',
        title: 'Release com disputa aberta',
        actor: 'B1 JWT',
        pre: 'concluido+disputa',
        repro: 'rpc release',
        expected: 'false',
        obtained: rel.brief,
      );
    } else {
      c.block('BE5.release_open_dispute', 'BE5', 'release', rel);
    }
  } else {
    c.block('BE5.concluido_with_open_dispute', 'BE5', 'PATCH concluido', conc);
  }

  await c.dumpAll('pass2.json');
  stdout.writeln(
      'DONE pass2 findings=${c.findings.length} blocked=${c.blocked.length} lenses=${c.lensesHit.toList()..sort()}');
}
