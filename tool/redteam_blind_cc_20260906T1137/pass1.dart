/// RED TEAM CEGO CC — pass 1. Staging only. Não corrige.
/// Lentes CC1 pedido_devolucao · CC2 FSM · CC7 2.º actor.
/// Exactos BW/BQ (observar, NÃO contar): seller pago→pedido_devolucao.
import '_rtcc.dart';

Future<void> main() async {
  final c = Rtcc.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
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

  final p1 = await mustPay('CC1');
  var o = await c.orderRow(p1.oid);
  c.note('CC1.fixture', 'pago Stripe TEST', {
    'oid': p1.oid,
    'pid': p1.pid,
    'status': o?['status'],
    'paid': o?['amount_paid_cents'],
    'pi': p1.pi,
    'stock': (await c.productRow(p1.pid))?['quantity'],
  }, lens: 'CC1');

  final sellerPedido = await c.patchOrder(
    p1.oid,
    {'status': 'pedido_devolucao'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(p1.oid);
  c.note('exacto.BW.seller_pedido',
      'BW/BQ exacto seller pago→pedido_devolucao (NÃO contar)', {
    'hit': sellerPedido.brief,
    'status': o?['status'],
  }, lens: 'CC1');

  await expectBlock(
    'CC7.b2_insert_on_b1_pago',
    'CC7',
    'B2 INSERT disputa em encomenda B1 (pago)',
    await c.insertDispute(
      orderId: p1.oid,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    ),
  );
  await expectBlock(
    'CC7.b2_insert_spoof_buyer_id',
    'CC7',
    'B2 INSERT disputa buyer_id=B1 JWT=B2',
    await c.insertDispute(
      orderId: p1.oid,
      jwt: c.buyer2Jwt,
      buyer: c.buyerId,
    ),
  );
  await expectBlock(
    'CC7.seller2_insert',
    'CC7',
    'S2 INSERT disputa em encomenda S1',
    await c.insertDispute(
      orderId: p1.oid,
      jwt: c.seller2Jwt,
      buyer: c.seller2Id,
    ),
  );
  await expectBlock(
    'CC7.anon_insert',
    'CC7',
    'anon INSERT disputa',
    await c.insertDispute(orderId: p1.oid, jwt: ''),
  );
  await expectBlock(
    'CC1.buyer_pedido_from_pago_no_dispute',
    'CC1',
    'Buyer pedido_devolucao a partir de pago sem disputa',
    await c.patchOrder(p1.oid, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt),
  );
  await expectBlock(
    'CC1.dispute_on_pago',
    'CC1',
    'Buyer abre disputa em pago',
    await c.insertDispute(orderId: p1.oid),
  );

  await expectBlock(
    'CC2.seller_pago_entregue',
    'CC2',
    'Seller marca entregue a partir de pago',
    await c.patchOrder(p1.oid, {'status': 'entregue'}, jwt: c.sellerJwt),
  );
  await expectBlock(
    'CC2.seller_pago_concluido',
    'CC2',
    'Seller marca concluido a partir de pago',
    await c.patchOrder(p1.oid, {'status': 'concluido'}, jwt: c.sellerJwt),
  );
  await expectBlock(
    'CC2.seller_devolvida_from_pago',
    'CC2',
    'Seller marca devolvida a partir de pago',
    await c.patchOrder(p1.oid, {'status': 'devolvida'}, jwt: c.sellerJwt),
  );
  await expectBlock(
    'CC2.buyer_concluido_from_pago_carrier',
    'CC2',
    'Buyer concluido a partir de pago (carrier, sem mão)',
    await c.patchOrder(p1.oid, {'status': 'concluido'}, jwt: c.buyerJwt),
  );

  final envOk = await c.toEnviado(p1.oid);
  if (!envOk) {
    c.skip('CC2.enviado', 'CC2', 'seller enviado não colou',
        await c.orderRow(p1.oid));
  }

  await expectBlock(
    'CC1.dispute_on_enviado',
    'CC1',
    'Buyer abre disputa em enviado',
    await c.insertDispute(orderId: p1.oid),
  );

  final concOk = await c.toConcluido(p1.oid);
  o = await c.orderRow(p1.oid);
  if (!concOk) {
    c.skip('CC2.concluido', 'CC2', 'buyer concluido não colou', o);
  }

  await expectBlock(
    'CC7.b2_insert_on_concluido',
    'CC7',
    'B2 INSERT disputa em encomenda B1 (concluido)',
    await c.insertDispute(
      orderId: p1.oid,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    ),
  );

  final d1 = await c.insertDispute(orderId: p1.oid);
  final did = d1.firstId;
  o = await c.orderRow(p1.oid);
  c.note('CC1.dispute_open', '1.ª disputa em concluido', {
    'hit': d1.brief,
    'did': did,
    'status': d1.map?['status'],
    'order': o?['status'],
  }, lens: 'CC1');
  if (!d1.ok || did == null) {
    c.skip('CC1.dispute_open', 'CC1', 'INSERT disputa falhou em concluido', d1);
    await c.dumpAll('pass1.json');
    return;
  }

  final d2 = await c.insertDispute(orderId: p1.oid);
  if (d2.ok) {
    c.hold(
      id: 'CC1.second_dispute',
      lens: 'CC1',
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
    c.block('CC1.second_dispute', 'CC1', '2.ª disputa recusada', d2);
  }

  final raced = await parallel([
    c.insertDispute(orderId: p1.oid),
    c.insertDispute(orderId: p1.oid),
  ]);
  final raceOk = raced.where((h) => h.ok).length;
  if (raceOk > 0) {
    c.hold(
      id: 'CC1.second_dispute_race',
      lens: 'CC1',
      severity: 'P1',
      title: 'Race 2× POST disputa criou linha extra',
      actor: 'buyer JWT',
      pre: 'disputa $did já aberta',
      repro: 'Future.wait 2× POST order_disputes',
      expected: '0 sucessos',
      obtained: raced.map((h) => h.brief).toList(),
    );
  } else {
    c.block('CC1.second_dispute_race', 'CC1', 'race 2.ª disputa',
        raced.map((h) => h.brief).toList());
  }

  final close = await c.patchDispute(did, {'status': 'resolvida'});
  var drow = await c.disputeRow(did);
  c.note('CC1.close', 'buyer fecha disputa resolvida', {
    'hit': close.brief,
    'status': drow?['status'],
  }, lens: 'CC1');

  final reopen = await c.insertDispute(orderId: p1.oid);
  if (reopen.ok) {
    c.hold(
      id: 'CC1.reopen_after_resolvida',
      lens: 'CC1',
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
    c.block('CC1.reopen_after_resolvida', 'CC1', 'reopen após resolvida', reopen);
  }

  if ('${drow?['status']}' == 'resolvida') {
    final unclose = await c.patchDispute(did, {'status': 'aberta'});
    drow = await c.disputeRow(did);
    c.note('CC1.unclose', 'reabrir aberta para cadeia devolução', {
      'hit': unclose.brief,
      'status': drow?['status'],
    }, lens: 'CC1');
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
  c.note('CC1.pedido', 'buyer pedido_devolucao a partir de concluido+disputa', {
    'hit': pedido.brief,
    'status': o?['status'],
  }, lens: 'CC1');
  if (o?['status']?.toString() != 'pedido_devolucao') {
    c.skip('CC1.pedido', 'CC1', 'pedido_devolucao não colou', {
      'hit': pedido.brief,
      'status': o?['status'],
    });
  }

  await expectBlock(
    'CC2.buyer_concluido_mid_return',
    'CC2',
    'Buyer concluido a meio da devolução (pedido_devolucao)',
    await c.patchOrder(p1.oid, {'status': 'concluido'}, jwt: c.buyerJwt),
  );
  await expectBlock(
    'CC2.seller_enviado_mid_return',
    'CC2',
    'Seller aborta devolução com PATCH enviado',
    await c.patchOrder(p1.oid, {'status': 'enviado'}, jwt: c.sellerJwt),
  );
  await expectBlock(
    'CC2.seller_devolvida_early_from_pedido',
    'CC2',
    'Seller marca devolvida cedo (ainda pedido_devolucao)',
    await c.patchOrder(p1.oid, {'status': 'devolvida'}, jwt: c.sellerJwt),
  );
  await expectBlock(
    'CC2.seller_pago_mid_return',
    'CC2',
    'Seller PATCH pago a meio da devolução',
    await c.patchOrder(p1.oid, {'status': 'pago'}, jwt: c.sellerJwt),
  );

  final emDev = await c.patchOrder(
    p1.oid,
    {'status': 'em_devolucao'},
    jwt: c.buyerJwt,
  );
  o = await c.orderRow(p1.oid);
  c.note('CC2.em_devolucao', 'buyer em_devolucao', {
    'hit': emDev.brief,
    'status': o?['status'],
  }, lens: 'CC2');

  await expectBlock(
    'CC2.buyer_concluido_em_devolucao',
    'CC2',
    'Buyer concluido em em_devolucao',
    await c.patchOrder(p1.oid, {'status': 'concluido'}, jwt: c.buyerJwt),
  );
  await expectBlock(
    'CC2.seller_devolvida_from_em_devolucao',
    'CC2',
    'Seller devolvida a partir de em_devolucao (salta devolucao_entregue)',
    await c.patchOrder(p1.oid, {'status': 'devolvida'}, jwt: c.sellerJwt),
  );

  final entDev = await c.patchOrder(
    p1.oid,
    {'status': 'devolucao_entregue'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(p1.oid);
  c.note('CC2.devolucao_entregue', 'seller devolucao_entregue', {
    'hit': entDev.brief,
    'status': o?['status'],
  }, lens: 'CC2');

  await expectBlock(
    'CC2.buyer_devolvida',
    'CC2',
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
  c.note('CC5.devolvida', 'seller devolvida (captura Stripe viva)', {
    'hit': dev.brief,
    'status': o?['status'],
    'qty_before': qtyBefore,
    'qty_after': qtyAfter,
    'refund_id': o?['stripe_refund_id'],
    'stock_units': o?['stock_units_applied'],
    'wallets_before': walletsBefore,
    'wallets_after': walletsAfter,
  }, lens: 'CC5');

  final restoredEarly = (qtyAfter ?? 0) > (qtyBefore ?? 0) &&
      (o?['stripe_refund_id'] == null || '${o?['stripe_refund_id']}' == '');
  if (o?['status']?.toString() == 'devolvida' && restoredEarly) {
    c.hold(
      id: 'CC5.devolvida_stock_without_refund',
      lens: 'CC5',
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
        'delta_wallet_buyer':
            (walletsAfter['buyer'] ?? 0) - (walletsBefore['buyer'] ?? 0),
      },
    );
  } else if (o?['status']?.toString() == 'devolvida') {
    c.block('CC5.devolvida_stock_without_refund', 'CC5',
        'stock não restaurou em devolvida sem refund', {
      'qty_before': qtyBefore,
      'qty_after': qtyAfter,
      'refund': o?['stripe_refund_id'],
    });
  } else {
    c.skip('CC5.devolvida', 'CC5', 'devolvida não colou', {
      'hit': dev.brief,
      'status': o?['status'],
    });
  }

  await expectBlock(
    'CC2.buyer_concluido_after_devolvida',
    'CC2',
    'Buyer concluido depois de devolvida',
    await c.patchOrder(p1.oid, {'status': 'concluido'}, jwt: c.buyerJwt),
  );

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
