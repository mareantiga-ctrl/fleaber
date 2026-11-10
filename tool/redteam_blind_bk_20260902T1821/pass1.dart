/// REDTEAM_BLIND_BK pass1 — FSM devolução, 2.ª disputa, B2, hops. Staging. Não corrigir.
import 'dart:io';
import '_rtbk.dart';

Future<void> main() async {
  final c = Rtbk.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.wallets();
  c.note('actors', 'JWT B1/S1/B2/S2', {
    'b1': c.buyerId,
    's1': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
    'wallets0': w0,
  });

  await _bk2ExactosAyBe(c);
  await _bk1PedidoSemDisputa(c);
  await _bk1PedidoComDisputa(c);
  await _bk2HopsNovos(c);
  await _bk7SecondActor(c);
  await _bk7SecondDispute(c);

  await c.dumpAll('pass1.json');
  stdout.writeln(
    'pass1 done findings=${c.findings.length} blocked=${c.blocked.length} '
    'residuals=${c.residuals.length} lenses=${c.lensesHit.toList()..sort()}',
  );
}

/// Exactos AY/BE: seller pago→em_devolucao; buyer devolucao_entregue. Não contar.
Future<void> _bk2ExactosAyBe(Rtbk c) async {
  final paid = await c.setupPaid();
  if (paid == null) {
    c.skip('BK2.aybe', 'BK2', 'setup_paid falhou', 'no fixture');
    return;
  }
  final oid = paid['order_id'].toString();

  final sEm = await c.patchOrder(oid, {'status': 'em_devolucao'}, jwt: c.sellerJwt);
  final afterS = await c.orderRow(oid);
  if ('${afterS?['status']}'.toLowerCase() == 'em_devolucao') {
    c.residual('AYBE.seller_em_devolucao', 'seller pago→em_devolucao ainda aberto', {
      'patch': sEm.brief,
      'status': afterS?['status'],
    });
  } else {
    c.block('AYBE.seller_em_devolucao', 'BK2', 'seller pago→em_devolucao', sEm);
  }

  final bEnt = await c.patchOrder(
    oid,
    {'status': 'devolucao_entregue'},
    jwt: c.buyerJwt,
  );
  final afterB = await c.orderRow(oid);
  if ('${afterB?['status']}'.toLowerCase() == 'devolucao_entregue') {
    c.residual('AYBE.buyer_devolucao_entregue', 'buyer marca devolucao_entregue', {
      'patch': bEnt.brief,
      'status': afterB?['status'],
    });
  } else {
    c.block('AYBE.buyer_devolucao_entregue', 'BK2', 'buyer devolucao_entregue', bEnt);
  }
}

/// BK1 — pedido_devolucao sem disputa / fora de concluido.
Future<void> _bk1PedidoSemDisputa(Rtbk c) async {
  final paid = await c.setupPaid();
  if (paid == null) {
    c.skip('BK1.nodisp', 'BK1', 'setup_paid falhou', 'no fixture');
    return;
  }
  final oid = paid['order_id'].toString();

  final fromPago = await c.patchOrder(
    oid,
    {'status': 'pedido_devolucao'},
    jwt: c.buyerJwt,
  );
  await c.expectDenied(
    id: 'BK1.buyer_pedido_from_pago',
    lens: 'BK1',
    title: 'Buyer pedido_devolucao a partir de pago sem disputa',
    hit: fromPago,
    actor: 'buyer JWT',
    pre: 'order pago capturado, sem order_disputes',
    repro: 'PATCH status=pedido_devolucao',
    severityIfOpen: 'P1',
    evidence: {'after': await c.orderRow(oid)},
  );

  final sellerPedido = await c.patchOrder(
    oid,
    {'status': 'pedido_devolucao'},
    jwt: c.sellerJwt,
  );
  final afterSeller = await c.orderRow(oid);
  final st = '${afterSeller?['status']}'.toLowerCase();
  if (st == 'pedido_devolucao') {
    c.hold(
      id: 'BK1.seller_pedido_from_pago',
      lens: 'BK1',
      severity: 'P1',
      title: 'Seller inicia pedido_devolucao a partir de pago sem disputa',
      actor: 'seller JWT',
      pre: 'order pago capturado, sem disputa',
      repro: 'PATCH status=pedido_devolucao',
      expected: '403 / sem mutação',
      obtained: {'patch': sellerPedido.brief, 'status': st},
      evidence: {'row': afterSeller},
    );
  } else {
    c.block('BK1.seller_pedido_from_pago', 'BK1', 'seller pedido from pago', sellerPedido);
  }

  final okConc = await c.toConcluido(oid);
  if (!okConc) {
    c.skip('BK1.pedido_concluido', 'BK1', 'não chegou a concluido', await c.orderRow(oid));
    return;
  }

  final pedidoNoDisp = await c.patchOrder(
    oid,
    {'status': 'pedido_devolucao'},
    jwt: c.buyerJwt,
  );
  await c.expectDenied(
    id: 'BK1.buyer_pedido_concluido_sem_disputa',
    lens: 'BK1',
    title: 'Buyer pedido_devolucao em concluido sem disputa',
    hit: pedidoNoDisp,
    actor: 'buyer JWT',
    pre: 'concluido, sem order_disputes',
    repro: 'PATCH status=pedido_devolucao',
    severityIfOpen: 'P1',
    evidence: {'after': await c.orderRow(oid)},
  );
}

/// BK1 — caminho honesto pedido após disputa; depois hops.
Future<void> _bk1PedidoComDisputa(Rtbk c) async {
  final paid = await c.setupPaid();
  if (paid == null) {
    c.skip('BK1.disp', 'BK1', 'setup_paid falhou', 'no fixture');
    return;
  }
  final oid = paid['order_id'].toString();
  if (!await c.toConcluido(oid)) {
    c.skip('BK1.disp.conc', 'BK1', 'concluido falhou', await c.orderRow(oid));
    return;
  }

  final dispPago = await c.openDispute(oid);
  if (!dispPago.ok) {
    c.note('BK1.open_fail', 'open disputa concluido', dispPago.brief, lens: 'BK1');
    c.skip('BK1.disp.open', 'BK1', 'INSERT disputa falhou', dispPago);
    return;
  }
  c.block('BK1.open_on_concluido', 'BK1', 'INSERT disputa em concluido (happy)', dispPago);

  final pedido = await c.patchOrder(
    oid,
    {'status': 'pedido_devolucao'},
    jwt: c.buyerJwt,
  );
  final after = await c.orderRow(oid);
  if ('${after?['status']}'.toLowerCase() != 'pedido_devolucao') {
    c.hold(
      id: 'BK1.happy_pedido_blocked',
      lens: 'BK1',
      severity: 'P3',
      title: 'Happy-path pedido_devolucao com disputa bloqueado (regressão)',
      actor: 'buyer JWT',
      pre: 'concluido + disputa aberta',
      repro: 'PATCH pedido_devolucao',
      expected: 'status=pedido_devolucao',
      obtained: {'patch': pedido.brief, 'row': after},
    );
    return;
  }
  c.note('BK1.happy_pedido', 'pedido_devolucao OK', after?['status'], lens: 'BK1');

  // Buyer em_devolucao após pedido — é o comprador a marcar envio de volta?
  final bEm = await c.patchOrder(oid, {'status': 'em_devolucao'}, jwt: c.buyerJwt);
  final afterEm = await c.orderRow(oid);
  if ('${afterEm?['status']}'.toLowerCase() == 'em_devolucao') {
    c.note('BK1.buyer_em', 'buyer pode marcar em_devolucao após pedido', bEm.brief,
        lens: 'BK1');
  } else {
    c.block('BK1.buyer_em', 'BK1', 'buyer em_devolucao após pedido', bEm);
  }
}

/// BK2 — hops novos: seller devolvida cedo, buyer concluido mid-return.
Future<void> _bk2HopsNovos(Rtbk c) async {
  final paid = await c.setupPaid();
  if (paid == null) {
    c.skip('BK2.hops', 'BK2', 'setup_paid falhou', 'no fixture');
    return;
  }
  final oid = paid['order_id'].toString();

  final sDev = await c.patchOrder(oid, {'status': 'devolvida'}, jwt: c.sellerJwt);
  await c.expectDenied(
    id: 'BK2.seller_devolvida_from_pago',
    lens: 'BK2',
    title: 'Seller devolvida cedo a partir de pago',
    hit: sDev,
    actor: 'seller JWT',
    pre: 'pago, sem ciclo devolução',
    repro: 'PATCH status=devolvida',
    severityIfOpen: 'P1',
    evidence: {'after': await c.orderRow(oid)},
  );

  final sEnt = await c.patchOrder(
    oid,
    {'status': 'devolucao_entregue'},
    jwt: c.sellerJwt,
  );
  await c.expectDenied(
    id: 'BK2.seller_entregue_from_pago',
    lens: 'BK2',
    title: 'Seller devolucao_entregue a partir de pago',
    hit: sEnt,
    actor: 'seller JWT',
    pre: 'pago',
    repro: 'PATCH devolucao_entregue',
    severityIfOpen: 'P1',
    evidence: {'after': await c.orderRow(oid)},
  );

  if (!await c.toConcluido(oid)) {
    c.skip('BK2.mid.conc', 'BK2', 'concluido falhou', await c.orderRow(oid));
    return;
  }
  final d = await c.openDispute(oid);
  if (!d.ok) {
    c.skip('BK2.mid.disp', 'BK2', 'disputa falhou', d);
    return;
  }
  await c.patchOrder(oid, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt);
  var row = await c.orderRow(oid);
  if ('${row?['status']}'.toLowerCase() != 'pedido_devolucao') {
    c.skip('BK2.mid.pedido', 'BK2', 'pedido_devolucao falhou', row);
    return;
  }

  final bConc = await c.patchOrder(oid, {'status': 'concluido'}, jwt: c.buyerJwt);
  row = await c.orderRow(oid);
  if ('${row?['status']}'.toLowerCase() == 'concluido') {
    c.hold(
      id: 'BK2.buyer_concluido_mid_return',
      lens: 'BK2',
      severity: 'P1',
      title: 'Buyer força concluido a meio da devolução',
      actor: 'buyer JWT',
      pre: 'pedido_devolucao + disputa aberta',
      repro: 'PATCH status=concluido',
      expected: 'order_concluido_denied_during_return',
      obtained: {'patch': bConc.brief, 'status': row?['status']},
      evidence: {'row': row},
    );
  } else {
    c.block('BK2.buyer_concluido_mid_return', 'BK2', 'buyer concluido mid-return', bConc);
  }

  // Seller hop pedido → devolvida (salta em_devolucao e entregue)
  final sSkip = await c.patchOrder(oid, {'status': 'devolvida'}, jwt: c.sellerJwt);
  row = await c.orderRow(oid);
  if ('${row?['status']}'.toLowerCase() == 'devolvida') {
    c.hold(
      id: 'BK2.seller_devolvida_skip_fsm',
      lens: 'BK2',
      severity: 'P1',
      title: 'Seller marca devolvida saltando em_devolucao/entregue',
      actor: 'seller JWT',
      pre: 'pedido_devolucao',
      repro: 'PATCH devolvida',
      expected: 'order_devolvida_denied',
      obtained: {'patch': sSkip.brief, 'status': row?['status']},
      evidence: {'row': row},
    );
  } else {
    c.block('BK2.seller_devolvida_skip_fsm', 'BK2', 'seller devolvida skip', sSkip);
  }

  // Seller pedido → em_devolucao (honesto) depois devolvida ainda cedo
  final sEm = await c.patchOrder(oid, {'status': 'em_devolucao'}, jwt: c.sellerJwt);
  row = await c.orderRow(oid);
  c.note('BK2.seller_em', 'seller em_devolucao após pedido', {
    'patch': sEm.brief,
    'status': row?['status'],
  }, lens: 'BK2');

  if ('${row?['status']}'.toLowerCase() == 'em_devolucao') {
    final sDevCedo = await c.patchOrder(oid, {'status': 'devolvida'}, jwt: c.sellerJwt);
    row = await c.orderRow(oid);
    if ('${row?['status']}'.toLowerCase() == 'devolvida') {
      c.hold(
        id: 'BK2.seller_devolvida_from_em',
        lens: 'BK2',
        severity: 'P1',
        title: 'Seller devolvida a partir de em_devolucao (sem entregue)',
        actor: 'seller JWT',
        pre: 'em_devolucao',
        repro: 'PATCH devolvida',
        expected: 'order_devolvida_denied',
        obtained: {'patch': sDevCedo.brief, 'status': row?['status']},
        evidence: {'row': row},
      );
    } else {
      c.block('BK2.seller_devolvida_from_em', 'BK2', 'seller devolvida from em', sDevCedo);
    }
  }
}

/// BK7 — B2 disputa na order de B1; S2 hops.
Future<void> _bk7SecondActor(Rtbk c) async {
  if (c.buyer2Jwt == null || c.seller2Jwt == null) {
    c.skip('BK7.actors', 'BK7', 'B2/S2 em falta', {
      'b2': c.buyer2Id,
      's2': c.seller2Id,
    });
    return;
  }
  final paid = await c.setupPaid();
  if (paid == null) {
    c.skip('BK7.paid', 'BK7', 'setup_paid falhou', 'no fixture');
    return;
  }
  final oid = paid['order_id'].toString();
  if (!await c.toConcluido(oid)) {
    c.skip('BK7.conc', 'BK7', 'concluido falhou', await c.orderRow(oid));
    return;
  }

  final b2Disp = await c.openDispute(oid, jwt: c.buyer2Jwt, buyer: c.buyer2Id);
  await c.expectDenied(
    id: 'BK7.b2_dispute_foreign_order',
    lens: 'BK7',
    title: 'B2 abre disputa na encomenda de B1',
    hit: b2Disp,
    actor: 'buyer2 JWT',
    pre: 'order B1↔S1 concluido',
    repro: 'POST order_disputes order_id=B1 buyer_id=B2',
    severityIfOpen: 'P1',
    evidence: {'after': await c.disputeByOrder(oid)},
  );

  final b2AsB1 = await c.openDispute(oid, jwt: c.buyer2Jwt, buyer: c.buyerId);
  await c.expectDenied(
    id: 'BK7.b2_spoof_buyer_id',
    lens: 'BK7',
    title: 'B2 INSERT disputa com buyer_id de B1',
    hit: b2AsB1,
    actor: 'buyer2 JWT',
    pre: 'order B1 concluido',
    repro: 'POST order_disputes buyer_id=B1',
    severityIfOpen: 'P1',
  );

  final s2Hop = await c.patchOrder(oid, {'status': 'enviado'}, jwt: c.seller2Jwt);
  await c.expectDenied(
    id: 'BK7.s2_enviado',
    lens: 'BK7',
    title: 'S2 marca enviado na order de S1',
    hit: s2Hop,
    actor: 'seller2 JWT',
    pre: 'concluido B1↔S1',
    repro: 'PATCH enviado',
    severityIfOpen: 'P1',
    evidence: {'after': await c.orderRow(oid)},
  );

  final s2Dev = await c.patchOrder(oid, {'status': 'devolvida'}, jwt: c.seller2Jwt);
  await c.expectDenied(
    id: 'BK7.s2_devolvida',
    lens: 'BK7',
    title: 'S2 marca devolvida na order de S1',
    hit: s2Dev,
    actor: 'seller2 JWT',
    pre: 'concluido B1↔S1',
    repro: 'PATCH devolvida',
    severityIfOpen: 'P1',
  );

  final anonDisp = await c.openDispute(oid, jwt: null);
  // anon uses anon key without user jwt — req() with jwt null uses anon
  await c.expectDenied(
    id: 'BK7.anon_dispute',
    lens: 'BK7',
    title: 'anon abre disputa',
    hit: anonDisp,
    actor: 'anon',
    pre: 'concluido',
    repro: 'POST order_disputes sem JWT user',
    severityIfOpen: 'P1',
  );
}

/// BK7 — 2.ª disputa no mesmo order (unique / recusar+reabrir).
Future<void> _bk7SecondDispute(Rtbk c) async {
  final paid = await c.setupPaid();
  if (paid == null) {
    c.skip('BK7.2nd', 'BK7', 'setup_paid falhou', 'no fixture');
    return;
  }
  final oid = paid['order_id'].toString();
  if (!await c.toConcluido(oid)) {
    c.skip('BK7.2nd.conc', 'BK7', 'concluido falhou', await c.orderRow(oid));
    return;
  }
  final d1 = await c.openDispute(oid);
  if (!d1.ok) {
    c.skip('BK7.2nd.d1', 'BK7', '1.ª disputa falhou', d1);
    return;
  }
  final did = d1.firstId;

  final d2 = await c.openDispute(oid);
  await c.expectDenied(
    id: 'BK7.second_dispute_insert',
    lens: 'BK7',
    title: '2.ª disputa INSERT no mesmo order',
    hit: d2,
    actor: 'buyer JWT',
    pre: 'já existe order_disputes',
    repro: 'POST order_disputes outra vez',
    severityIfOpen: 'P1',
    evidence: {'d1': did, 'd2': d2.brief, 'rows': await c.disputeByOrder(oid)},
  );

  if (did != null) {
    final close = await c.patchDispute(did, {'status': 'recusada'}, jwt: c.buyerJwt);
    c.note('BK7.close', 'buyer recusa 1.ª', close.brief, lens: 'BK7');
    final d3 = await c.openDispute(oid);
    final after = await c.rest(
      'GET',
      'order_disputes?order_id=eq.$oid&select=id,status&order=created_at.desc',
      service: true,
    );
    final n = after.list.length;
    if (d3.ok && n >= 2) {
      c.hold(
        id: 'BK7.reopen_after_recusada',
        lens: 'BK7',
        severity: 'P1',
        title: 'Reabrir disputa após recusada (2 linhas)',
        actor: 'buyer JWT',
        pre: '1.ª disputa recusada',
        repro: 'POST order_disputes',
        expected: 'dispute_already_exists_for_order',
        obtained: {'insert': d3.brief, 'count': n, 'rows': after.list},
      );
    } else {
      c.block('BK7.reopen_after_recusada', 'BK7', 'reopen após recusada', {
        'close': close.brief,
        'insert': d3.brief,
        'count': n,
      });
    }

    final del = await c.rest(
      'DELETE',
      'order_disputes?id=eq.$did',
      jwt: c.buyerJwt,
      prefer: 'return=representation',
    );
    await c.expectDenied(
      id: 'BK7.buyer_delete_dispute',
      lens: 'BK7',
      title: 'Buyer DELETE disputa para reabrir',
      hit: del,
      actor: 'buyer JWT',
      pre: 'disputa existente',
      repro: 'DELETE order_disputes',
      severityIfOpen: 'P2',
    );
  }
}
