/// RED TEAM CEGO CI — pass 1. Staging only. Não corrige.
/// Poço CI-B FSM · CI-D 2.º actor · lentes CI1 CI2 CI7.
/// Exactos BXCC (observar, NÃO contar): seller pago→pedido_devolucao.
import '_rtci.dart';

Future<void> main() async {
  final c = Rtci.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.well('CI-B');
  c.well('CI-D');
  c.note('actors', 'JWT B1/S1/B2/S2', {
    'b1': c.buyerId,
    's1': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
  });

  Future<void> expectBlock(
    String id,
    String lens,
    String title,
    HttpHit hit, {
    String? severity,
  }) async {
    final empty = hit.body.trim() == '[]' || hit.body.trim().isEmpty;
    if (hit.ok && !empty) {
      c.hold(
        id: id,
        lens: lens,
        severity: severity ?? 'P1',
        title: title,
        actor: 'JWT',
        pre: id,
        repro: id,
        expected: '401/403/empty/42501',
        obtained: hit.brief,
      );
    } else {
      c.block(id, lens, title, hit);
    }
  }

  Future<({String oid, String pid, String? pi})> mustPay(String lens,
      {int qty = 2}) async {
    final paid = await c.payToPago(lens: lens, initialQty: qty);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  final p1 = await mustPay('CI1');
  var o = await c.orderRow(p1.oid);
  c.note('CI1.fixture', 'pago Stripe TEST', {
    'oid': p1.oid,
    'pid': p1.pid,
    'status': o?['status'],
    'paid': o?['amount_paid_cents'],
    'pi': p1.pi,
    'stock': (await c.productRow(p1.pid))?['quantity'],
  }, lens: 'CI1');

  final sellerPedido = await c.patchOrder(
    p1.oid,
    {'status': 'pedido_devolucao'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(p1.oid);
  c.note('exacto.BXCC.seller_pedido',
      'BXCC exacto seller pago→pedido_devolucao (NÃO contar)', {
    'hit': sellerPedido.brief,
    'status': o?['status'],
  }, lens: 'CI1');

  await expectBlock(
    'CI7.b2_insert_on_b1_pago',
    'CI7',
    'B2 INSERT disputa em encomenda B1 (pago)',
    await c.insertDispute(
      orderId: p1.oid,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    ),
  );
  await expectBlock(
    'CI7.b2_insert_spoof_buyer_id',
    'CI7',
    'B2 INSERT disputa buyer_id=B1 JWT=B2',
    await c.insertDispute(
      orderId: p1.oid,
      jwt: c.buyer2Jwt,
      buyer: c.buyerId,
    ),
  );
  await expectBlock(
    'CI7.seller2_insert',
    'CI7',
    'S2 INSERT disputa em encomenda S1',
    await c.insertDispute(
      orderId: p1.oid,
      jwt: c.seller2Jwt,
      buyer: c.seller2Id,
    ),
  );
  await expectBlock(
    'CI7.anon_insert',
    'CI7',
    'anon INSERT disputa',
    await c.insertDispute(orderId: p1.oid, jwt: ''),
  );
  await expectBlock(
    'CI1.buyer_pedido_from_pago_no_dispute',
    'CI1',
    'Buyer pedido_devolucao a partir de pago sem disputa',
    await c.patchOrder(p1.oid, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt),
  );
  await expectBlock(
    'CI1.dispute_on_pago',
    'CI1',
    'Buyer abre disputa em pago',
    await c.insertDispute(orderId: p1.oid),
  );
  await expectBlock(
    'CI2.seller_devolvida_from_pago',
    'CI2',
    'Seller marca devolvida a partir de pago',
    await c.patchOrder(p1.oid, {'status': 'devolvida'}, jwt: c.sellerJwt),
  );
  await expectBlock(
    'CI2.buyer_concluido_from_pago_carrier',
    'CI2',
    'Buyer concluido a partir de pago (carrier, sem mão)',
    await c.patchOrder(p1.oid, {'status': 'concluido'}, jwt: c.buyerJwt),
  );

  final envOk = await c.toEnviado(p1.oid);
  if (!envOk) {
    c.skip('CI2.enviado', 'CI2', 'seller enviado não colou',
        await c.orderRow(p1.oid));
  }

  // CI-B: carrier “delivered” early — seller enviado→entregue
  final entregueEarly = await c.patchOrder(
    p1.oid,
    {'status': 'entregue'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(p1.oid);
  c.note('CI2.carrier_entregue_early', 'seller enviado→entregue (carrier early)', {
    'hit': entregueEarly.brief,
    'status': o?['status'],
  }, lens: 'CI2');
  if (o?['status']?.toString() == 'entregue') {
    c.hold(
      id: 'CI2.carrier_entregue_early',
      lens: 'CI2',
      severity: 'P1',
      title: 'Seller marca entregue cedo (carrier delivered sem confirmação B)',
      actor: 'seller JWT',
      pre: 'status era enviado',
      repro: 'PATCH orders status=entregue a partir de enviado',
      expected: '403 / status permanece enviado',
      obtained: {'hit': entregueEarly.brief, 'status': o?['status']},
    );
  } else {
    c.block('CI2.carrier_entregue_early', 'CI2',
        'enviado→entregue recusado', entregueEarly);
  }

  // CI-B: race buyer confirma receção ∥ abre disputa (ainda enviado)
  final raceRecv = await parallel([
    c.patchOrder(p1.oid, {'status': 'concluido'}, jwt: c.buyerJwt),
    c.insertDispute(orderId: p1.oid),
  ]);
  o = await c.orderRow(p1.oid);
  final raceDisp = await c.rest(
    'GET',
    'order_disputes?order_id=eq.${p1.oid}&select=id,status',
    service: true,
  );
  c.note('CI2.race_concluido_dispute', 'race concluido ∥ INSERT disputa', {
    'hits': raceRecv.map((h) => h.brief).toList(),
    'status': o?['status'],
    'disputes': raceDisp.brief,
  }, lens: 'CI2');
  final disputeOnEnviado = o?['status']?.toString() != 'concluido' &&
      raceRecv.any((h) => h.ok && '${h.brief}'.contains('order_disputes') ||
          (h.firstId != null && h.ok));
  final bothWon = o?['status']?.toString() == 'concluido' &&
      raceRecv.where((h) => h.ok).length >= 2;
  if (disputeOnEnviado && o?['status']?.toString() != 'concluido') {
    c.hold(
      id: 'CI2.dispute_while_enviado_race',
      lens: 'CI2',
      severity: 'P1',
      title: 'Race: disputa aberta sem concluido (ainda enviado)',
      actor: 'buyer JWT',
      pre: 'enviado, parallel concluido ∥ INSERT disputa',
      repro: 'Future.wait PATCH concluido + POST order_disputes',
      expected: 'disputa só após concluido; enviado sem disputa',
      obtained: {
        'status': o?['status'],
        'hits': raceRecv.map((h) => h.brief).toList(),
      },
    );
  } else {
    c.block('CI2.race_concluido_dispute', 'CI2',
        'race: disputa não ficou em enviado', {
      'status': o?['status'],
      'both_ok': bothWon,
      'hits': raceRecv.map((h) => h.brief).toList(),
    });
  }

  if (o?['status']?.toString() != 'concluido') {
    await c.toConcluido(p1.oid);
    o = await c.orderRow(p1.oid);
  }

  await expectBlock(
    'CI7.b2_insert_on_concluido',
    'CI7',
    'B2 INSERT disputa em encomenda B1 (concluido)',
    await c.insertDispute(
      orderId: p1.oid,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    ),
  );

  final existing = await c.rest(
    'GET',
    'order_disputes?order_id=eq.${p1.oid}&select=id,status',
    jwt: c.buyerJwt,
  );
  String? did;
  for (final e in existing.list) {
    if (e is Map && e['id'] != null) {
      did = e['id'].toString();
      break;
    }
  }
  HttpHit? d1;
  if (did == null) {
    d1 = await c.insertDispute(orderId: p1.oid);
    did = d1.firstId;
    c.note('CI1.dispute_open', '1.ª disputa em concluido', {
      'hit': d1.brief,
      'did': did,
    }, lens: 'CI1');
  } else {
    c.note('CI1.dispute_open', 'disputa já existia pós-race', {
      'did': did,
      'list': existing.brief,
    }, lens: 'CI1');
  }
  if (did == null) {
    c.skip('CI1.dispute_open', 'CI1', 'INSERT disputa falhou', d1 ?? existing);
    await c.dumpAll('pass1.json');
    return;
  }

  final d2 = await c.insertDispute(orderId: p1.oid);
  if (d2.ok) {
    c.hold(
      id: 'CI1.second_dispute',
      lens: 'CI1',
      severity: 'P1',
      title: '2.ª disputa INSERT na mesma encomenda',
      actor: 'buyer JWT',
      pre: 'já existe order_disputes em $did',
      repro: 'POST order_disputes 2× no mesmo order_id',
      expected: '409/23505 dispute_already_exists_for_order',
      obtained: d2.brief,
      evidence: {'first': did, 'second': d2.firstId},
    );
  } else {
    c.block('CI1.second_dispute', 'CI1', '2.ª disputa recusada', d2);
  }

  final raced = await parallel([
    c.insertDispute(orderId: p1.oid),
    c.insertDispute(orderId: p1.oid),
  ]);
  final raceOk = raced.where((h) => h.ok).length;
  if (raceOk > 0) {
    c.hold(
      id: 'CI1.second_dispute_race',
      lens: 'CI1',
      severity: 'P1',
      title: 'Race 2× POST disputa criou linha extra',
      actor: 'buyer JWT',
      pre: 'disputa $did já aberta',
      repro: 'Future.wait 2× POST order_disputes',
      expected: '0 sucessos',
      obtained: raced.map((h) => h.brief).toList(),
    );
  } else {
    c.block('CI1.second_dispute_race', 'CI1', 'race 2.ª disputa',
        raced.map((h) => h.brief).toList());
  }

  // CI-D: B2 mete-se na disputa A (reply + PATCH)
  final b2reply = await c.insertReply(
    disputeId: did,
    jwt: c.buyer2Jwt,
    sender: c.buyer2Id,
    message: 'RTCI B2 reply na disputa A',
  );
  await expectBlock(
    'CI7.b2_reply_on_dispute_a',
    'CI7',
    'B2 reply na disputa do B1',
    b2reply,
  );
  final b2patch = await c.patchDispute(did, {
    'status': 'resolvida',
    'description': 'RTCI B2 fecha disputa A',
  }, jwt: c.buyer2Jwt);
  await expectBlock(
    'CI7.b2_patch_dispute_a',
    'CI7',
    'B2 PATCH fecha disputa A',
    b2patch,
  );
  final s2patch = await c.patchDispute(did, {
    'seller_refund_percent': 1,
  }, jwt: c.seller2Jwt);
  await expectBlock(
    'CI7.s2_patch_dispute_a',
    'CI7',
    'S2 PATCH disputa da venda S1',
    s2patch,
  );

  final close = await c.patchDispute(did, {'status': 'resolvida'});
  var drow = await c.disputeRow(did);
  c.note('CI1.close', 'buyer fecha disputa resolvida', {
    'hit': close.brief,
    'status': drow?['status'],
  }, lens: 'CI1');

  final reopen = await c.insertDispute(orderId: p1.oid);
  if (reopen.ok) {
    c.hold(
      id: 'CI1.reopen_after_resolvida',
      lens: 'CI1',
      severity: 'P1',
      title: '2.ª disputa após resolvida (reopen)',
      actor: 'buyer JWT',
      pre: 'disputa $did status=${drow?['status']}',
      repro: 'POST order_disputes depois de PATCH resolvida',
      expected: '409 unique / insert_once',
      obtained: reopen.brief,
      evidence: {'new_id': reopen.firstId},
    );
  } else {
    c.block('CI1.reopen_after_resolvida', 'CI1', 'reopen após resolvida', reopen);
  }

  if ('${drow?['status']}' == 'resolvida') {
    final unclose = await c.patchDispute(did, {'status': 'aberta'});
    drow = await c.disputeRow(did);
    c.note('CI1.unclose', 'reabrir aberta para cadeia devolução', {
      'hit': unclose.brief,
      'status': drow?['status'],
    }, lens: 'CI1');
  }

  var activeDid = did;
  if (reopen.ok && reopen.firstId != null) {
    activeDid = reopen.firstId!;
  }

  final pedido = await c.patchOrder(
    p1.oid,
    {'status': 'pedido_devolucao'},
    jwt: c.buyerJwt,
  );
  o = await c.orderRow(p1.oid);
  c.note('CI1.pedido', 'buyer pedido_devolucao a partir de concluido+disputa', {
    'hit': pedido.brief,
    'status': o?['status'],
  }, lens: 'CI1');

  // CI-B: 2.ª pedido_devolucao (PATCH de novo no mesmo estado / re-pedido)
  final pedido2 = await c.patchOrder(
    p1.oid,
    {'status': 'pedido_devolucao', 'quantity': 0},
    jwt: c.buyerJwt,
  );
  o = await c.orderRow(p1.oid);
  c.note('CI1.second_pedido_devolucao', '2.ª PATCH pedido_devolucao + qty=0', {
    'hit': pedido2.brief,
    'status': o?['status'],
    'qty': o?['quantity'],
  }, lens: 'CI1');
  final qtyZero = numOf(o?['quantity']) == 0;
  if (qtyZero) {
    c.hold(
      id: 'CI1.second_pedido_qty0',
      lens: 'CI1',
      severity: 'P1',
      title: '2.ª pedido_devolucao alterou quantity da encomenda para 0',
      actor: 'buyer JWT',
      pre: 'já pedido_devolucao',
      repro: 'PATCH status=pedido_devolucao quantity=0',
      expected: 'quantity imutável / 403',
      obtained: {'hit': pedido2.brief, 'qty': o?['quantity']},
    );
  } else {
    c.block('CI1.second_pedido_devolucao', 'CI1',
        '2.ª pedido recusada ou qty imutável', {
      'hit': pedido2.brief,
      'qty': o?['quantity'],
      'status': o?['status'],
    });
  }

  await expectBlock(
    'CI2.seller_devolvida_early_from_pedido',
    'CI2',
    'Seller marca devolvida cedo (ainda pedido_devolucao)',
    await c.patchOrder(p1.oid, {'status': 'devolvida'}, jwt: c.sellerJwt),
  );

  // CI-B: carrier/return delivered_at cedo
  final earlyDelivered = await c.patchOrder(
    p1.oid,
    {'return_delivered_at': DateTime.now().toUtc().toIso8601String()},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(p1.oid);
  c.note('CI2.return_delivered_at_early', 'seller return_delivered_at em pedido', {
    'hit': earlyDelivered.brief,
    'status': o?['status'],
  }, lens: 'CI2');
  if (earlyDelivered.ok && earlyDelivered.body.trim() != '[]') {
    c.hold(
      id: 'CI2.return_delivered_at_early',
      lens: 'CI2',
      severity: 'P1',
      title: 'Seller grava return_delivered_at ainda em pedido_devolucao',
      actor: 'seller JWT',
      pre: 'status=pedido_devolucao (antes de devolucao_entregue)',
      repro: 'PATCH orders return_delivered_at=now()',
      expected: 'order_return_delivered_at_denied',
      obtained: {
        'hit': earlyDelivered.brief,
        'return_delivered_at': o?['return_delivered_at'],
      },
    );
  } else {
    c.block('CI2.return_delivered_at_early', 'CI2',
        'return_delivered_at cedo recusado', earlyDelivered);
  }

  await expectBlock(
    'CI2.buyer_concluido_mid_return',
    'CI2',
    'Buyer concluido a meio da devolução (pedido_devolucao)',
    await c.patchOrder(p1.oid, {'status': 'concluido'}, jwt: c.buyerJwt),
  );
  await expectBlock(
    'CI2.seller_enviado_mid_return',
    'CI2',
    'Seller aborta devolução com PATCH enviado',
    await c.patchOrder(p1.oid, {'status': 'enviado'}, jwt: c.sellerJwt),
  );

  final emDev = await c.patchOrder(
    p1.oid,
    {'status': 'em_devolucao'},
    jwt: c.buyerJwt,
  );
  o = await c.orderRow(p1.oid);
  c.note('CI2.em_devolucao', 'buyer em_devolucao', {
    'hit': emDev.brief,
    'status': o?['status'],
  }, lens: 'CI2');

  await expectBlock(
    'CI2.seller_devolvida_from_em_devolucao',
    'CI2',
    'Seller devolvida a partir de em_devolucao (salta devolucao_entregue)',
    await c.patchOrder(p1.oid, {'status': 'devolvida'}, jwt: c.sellerJwt),
  );

  final entDev = await c.patchOrder(
    p1.oid,
    {'status': 'devolucao_entregue'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(p1.oid);
  c.note('CI2.devolucao_entregue', 'seller devolucao_entregue', {
    'hit': entDev.brief,
    'status': o?['status'],
  }, lens: 'CI2');

  await expectBlock(
    'CI2.buyer_devolvida',
    'CI2',
    'Buyer marca devolvida',
    await c.patchOrder(p1.oid, {'status': 'devolvida'}, jwt: c.buyerJwt),
  );

  final qtyBefore = numOf((await c.productRow(p1.pid))?['quantity']);
  final walletsBefore = await c.wallets();
  final dev = await c.patchOrder(
    p1.oid,
    {'status': 'devolvida'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(p1.oid);
  final qtyAfter = numOf((await c.productRow(p1.pid))?['quantity']);
  final walletsAfter = await c.wallets();
  c.note('CI5.devolvida', 'seller devolvida (captura Stripe viva)', {
    'hit': dev.brief,
    'status': o?['status'],
    'qty_before': qtyBefore,
    'qty_after': qtyAfter,
    'refund_id': o?['stripe_refund_id'],
    'stock_units': o?['stock_units_applied'],
    'wallets_before': walletsBefore,
    'wallets_after': walletsAfter,
  }, lens: 'CI5');

  final restoredEarly = (qtyAfter ?? 0) > (qtyBefore ?? 0) &&
      (o?['stripe_refund_id'] == null || '${o?['stripe_refund_id']}' == '');
  if (o?['status']?.toString() == 'devolvida' && restoredEarly) {
    c.hold(
      id: 'CI5.devolvida_stock_without_refund',
      lens: 'CI5',
      severity: 'P1',
      title: 'devolvida relista stock com captura Stripe viva (sem refund)',
      actor: 'seller JWT',
      pre: 'PI capturado, stripe_refund_id null, qty=$qtyBefore',
      repro: 'PATCH status=devolvida',
      expected: 'qty inalterada até stripe_refund_id',
      obtained: {
        'status': o?['status'],
        'qty_before': qtyBefore,
        'qty_after': qtyAfter,
        'refund_id': o?['stripe_refund_id'],
      },
    );
  } else if (o?['status']?.toString() == 'devolvida') {
    c.block('CI5.devolvida_stock_without_refund', 'CI5',
        'stock não restaurou em devolvida sem refund', {
      'qty_before': qtyBefore,
      'qty_after': qtyAfter,
      'refund': o?['stripe_refund_id'],
    });
  } else {
    c.skip('CI5.devolvida', 'CI5', 'devolvida não colou', {
      'hit': dev.brief,
      'status': o?['status'],
    });
  }

  c.note('pass1.ids', 'IDs para pass 2/3', {
    'oid': p1.oid,
    'pid': p1.pid,
    'did': activeDid,
    'pi': p1.pi,
  });

  await dumpJson('${outDir()}/pass1_ids.json', {
    'oid': p1.oid,
    'pid': p1.pid,
    'did': activeDid,
    'pi': p1.pi,
    'status': o?['status'],
  });
  await c.dumpAll('pass1.json');
}
