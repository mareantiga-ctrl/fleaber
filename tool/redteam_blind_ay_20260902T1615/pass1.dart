/// RED TEAM CEGO AY — pass 1. Staging only. Não corrige.
/// Lentes AY1–AY8. Não redescobrir exactos AS/AM da lista do prompt.
import 'dart:io';
import '_rtay.dart';

const png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
];

Future<void> main() async {
  final c = Rtay.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('actors', 'JWT B1/S1/B2/S2', {
    'b1': c.buyerId,
    's1': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
    'sk': c.stripeTestKey != null,
  });

  Future<Map<String, dynamic>> books(String oid, String pid) async => {
        'order': await c.orderRow(oid),
        'product': await c.productRow(pid),
        'wallets': await c.wallets(),
        'stock': (await c.stockCheck(pid)).map,
      };

  Future<({String oid, String pid, String? pi})> mustPay(String lens) async {
    final paid = await c.payToPago(lens: lens, initialQty: 1);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
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

  bool releasedTrue(HttpHit h) => h.body == 'true' || h.json == true;

  Future<HttpHit> release(String oid, {String? jwt}) => c.rpc(
        'batata_release_seller_wallet_for_order',
        {'p_order_id': oid},
        jwt: jwt ?? c.buyerJwt,
      );

  // =========================================================================
  // AY1 — disputa vs FSM (estados errados; NÃO exactos AS-P1-02/05)
  // =========================================================================
  final p1 = await mustPay('AY1');
  var o = await c.orderRow(p1.oid);
  c.note('AY1.fixture', 'pago Stripe TEST', {
    'oid': p1.oid,
    'pid': p1.pid,
    'status': o?['status'],
    'paid': o?['amount_paid_cents'],
    'ship': o?['shipping_method'],
    'pi': p1.pi,
  }, lens: 'AY1');

  await expectBlock(
    'AY1.alien_insert',
    'AY1',
    'B2 abre disputa em encomenda B1',
    await c.insertDispute(
      orderId: p1.oid,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    ),
  );
  await expectBlock(
    'AY1.dispute_on_pago',
    'AY1',
    'Buyer abre disputa em pago',
    await c.insertDispute(orderId: p1.oid),
  );
  await expectBlock(
    'AY1.seller_insert',
    'AY1',
    'Seller insere disputa',
    await c.insertDispute(
      orderId: p1.oid,
      jwt: c.sellerJwt,
      buyer: c.sellerId,
    ),
  );

  // Verify ANAS: seller pago→entregue (exact AS-P1-02) — must BLOCK, not finding
  final sellerEntPago = await c.patchOrder(
    p1.oid,
    {'status': 'entregue'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(p1.oid);
  if (sellerEntPago.ok && o?['status'] == 'entregue') {
    c.hold(
      id: 'AY1.regress_seller_pago_entregue',
      lens: 'AY1',
      severity: 'P1',
      title: 'REGRESSÃO ANAS: seller pago→entregue voltou a persistir',
      actor: 'seller JWT',
      pre: 'pago capturado',
      repro: 'PATCH status=entregue JWT=seller',
      expected: '403 order_seller_cannot_mark_entregue',
      obtained: {'hit': sellerEntPago.brief, 'status': o?['status']},
    );
  } else {
    c.block('AY1.anas_seller_entregue', 'AY1', 'ANAS: seller não marca entregue',
        sellerEntPago);
  }

  // NEW: buyer entregue sem enviado
  final buyerEntPago = await c.patchOrder(
    p1.oid,
    {'status': 'entregue'},
    jwt: c.buyerJwt,
  );
  o = await c.orderRow(p1.oid);
  if (buyerEntPago.ok && o?['status'] == 'entregue') {
    c.hold(
      id: 'AY2.buyer_entregue_sem_enviado',
      lens: 'AY2',
      severity: 'P1',
      title: 'Buyer marca entregue a partir de pago (nunca enviado)',
      actor: 'buyer JWT',
      pre: 'pago, shipped_at null',
      repro: 'PATCH status=entregue JWT=buyer',
      expected: 'order_entregue_requires_enviado',
      obtained: {
        'hit': buyerEntPago.brief,
        'status': o?['status'],
        'shipped_at': o?['shipped_at'],
      },
    );
  } else {
    c.block('AY2.buyer_entregue_sem_enviado', 'AY2',
        'buyer entregue sem enviado', buyerEntPago);
  }

  // NEW: buyer concluido from pago with non-hand shipping
  final buyerConclPago = await c.patchOrder(
    p1.oid,
    {'status': 'concluido'},
    jwt: c.buyerJwt,
  );
  o = await c.orderRow(p1.oid);
  if (buyerConclPago.ok && o?['status'] == 'concluido') {
    c.hold(
      id: 'AY5.buyer_concluido_pago_carrier',
      lens: 'AY5',
      severity: 'P1',
      title: 'Buyer pago→concluido sem enviado (carrier / shipping vazio)',
      actor: 'buyer JWT',
      pre: 'pago, shipping não-mão ou vazio',
      repro: 'PATCH status=concluido',
      expected: 'order_concluido_requires_shipped se não for mão',
      obtained: {
        'hit': buyerConclPago.brief,
        'status': o?['status'],
        'ship': o?['shipping_method'],
        'shipped_at': o?['shipped_at'],
      },
    );
  } else {
    c.block('AY5.buyer_concluido_pago_carrier', 'AY5',
        'buyer concluido em pago carrier', buyerConclPago);
  }

  final adminRpc = await c.rpc(
    'batata_admin_resolve_dispute',
    {
      'p_dispute_id': '00000000-0000-0000-0000-000000000001',
      'p_resolution': 'favor_buyer_refund',
      'p_note': 'RTAY',
    },
    jwt: c.buyerJwt,
  );
  final adminBrief = adminRpc.brief.toLowerCase();
  if (adminRpc.ok &&
      !adminBrief.contains('admin') &&
      adminRpc.body != 'false' &&
      adminRpc.body != 'null') {
    c.hold(
      id: 'AY1.admin_rpc',
      lens: 'AY1',
      severity: 'P0',
      title: 'Buyer executa batata_admin_resolve_dispute',
      actor: 'buyer JWT',
      pre: 'não-admin',
      repro: 'rpc batata_admin_resolve_dispute',
      expected: 'admin only',
      obtained: adminRpc.brief,
    );
  } else {
    c.block('AY1.admin_rpc', 'AY1', 'admin resolve recusado', adminRpc);
  }

  // Enviado legítimo
  final toEnv = await c.patchOrder(
    p1.oid,
    {'status': 'enviado'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(p1.oid);
  c.note('AY2.enviado', 'seller → enviado', {
    'hit': toEnv.brief,
    'status': o?['status'],
    'shipped_at': o?['shipped_at'],
  }, lens: 'AY2');

  // NEW: seller enviado→entregue hop (prompt: não é exacto pago→entregue)
  final sellerEnvEnt = await c.patchOrder(
    p1.oid,
    {'status': 'entregue'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(p1.oid);
  if (sellerEnvEnt.ok && o?['status'] == 'entregue') {
    c.hold(
      id: 'AY2.seller_enviado_to_entregue',
      lens: 'AY2',
      severity: 'P1',
      title: 'Seller hop enviado→entregue (confirma receção no lugar do buyer)',
      actor: 'seller JWT',
      pre: 'enviado capturado',
      repro: 'PATCH status=entregue JWT=seller',
      expected: 'order_seller_cannot_mark_entregue',
      obtained: {'hit': sellerEnvEnt.brief, 'status': o?['status']},
    );
  } else {
    c.block('AY2.seller_enviado_to_entregue', 'AY2',
        'seller enviado→entregue', sellerEnvEnt);
  }

  await expectBlock(
    'AY1.dispute_on_enviado',
    'AY1',
    'Buyer abre disputa em enviado',
    await c.insertDispute(orderId: p1.oid),
  );

  // NEW: buyer pedido_devolucao SEM disputa (ainda em enviado / depois entregue)
  final pedidoNoDispEnv = await c.patchOrder(
    p1.oid,
    {'status': 'pedido_devolucao'},
    jwt: c.buyerJwt,
  );
  if (pedidoNoDispEnv.ok &&
      (await c.orderRow(p1.oid))?['status'] == 'pedido_devolucao') {
    c.hold(
      id: 'AY3.pedido_devolucao_sem_disputa_enviado',
      lens: 'AY3',
      severity: 'P1',
      title: 'Buyer pedido_devolucao a partir de enviado sem disputa',
      actor: 'buyer JWT',
      pre: 'enviado, zero disputas',
      repro: 'PATCH status=pedido_devolucao',
      expected: 'denied (exige entregue/concluido + disputa)',
      obtained: pedidoNoDispEnv.brief,
    );
  } else {
    c.block('AY3.pedido_sem_disputa_enviado', 'AY3',
        'pedido_devolucao em enviado sem disputa', pedidoNoDispEnv);
  }

  // Race entregue ∥ disputa
  final pRace = await mustPay('AY2');
  await c.patchOrder(pRace.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final raced = await parallel([
    c.patchOrder(pRace.oid, {'status': 'entregue'}, jwt: c.buyerJwt),
    c.insertDispute(orderId: pRace.oid),
  ]);
  final raceOrder = await c.orderRow(pRace.oid);
  c.note('AY2.race_entregue_dispute', 'entregue∥POST disputa', {
    'entregue': raced[0].brief,
    'dispute': raced[1].brief,
    'status': raceOrder?['status'],
  }, lens: 'AY2');
  if (raced[1].ok && raceOrder?['status'] != 'entregue') {
    c.hold(
      id: 'AY2.race_dispute_before_entregue',
      lens: 'AY2',
      severity: 'P1',
      title: 'Race: disputa 201 sem entregue persistido',
      actor: 'buyer JWT paralelo',
      pre: 'enviado; Future.wait entregue∥disputa',
      repro: 'parallel PATCH entregue + POST order_disputes',
      expected: 'disputa só se status entregue/concluido',
      obtained: {
        'dispute': raced[1].brief,
        'entregue': raced[0].brief,
        'status': raceOrder?['status'],
      },
    );
  }

  // Buyer entregue (feliz) no p1
  o = await c.orderRow(p1.oid);
  if (o?['status'] == 'enviado') {
    await c.patchOrder(p1.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  }
  o = await c.orderRow(p1.oid);

  // NEW: pedido_devolucao em entregue SEM disputa
  final pedidoNoDisp = await c.patchOrder(
    p1.oid,
    {'status': 'pedido_devolucao'},
    jwt: c.buyerJwt,
  );
  o = await c.orderRow(p1.oid);
  if (pedidoNoDisp.ok && o?['status'] == 'pedido_devolucao') {
    c.hold(
      id: 'AY3.pedido_devolucao_sem_disputa',
      lens: 'AY3',
      severity: 'P1',
      title: 'Buyer pedido_devolucao em entregue sem abrir disputa',
      actor: 'buyer JWT',
      pre: 'entregue, zero disputas',
      repro: 'PATCH status=pedido_devolucao',
      expected: 'order_pedido_devolucao_requires_dispute',
      obtained: {'hit': pedidoNoDisp.brief, 'status': o?['status']},
    );
  } else {
    c.block('AY3.pedido_devolucao_sem_disputa', 'AY3',
        'pedido sem disputa em entregue', pedidoNoDisp);
  }

  // INSERT resolvida em entregue (AM3-P3 era em pago — estado diferente)
  final insRes = await c.insertDispute(orderId: p1.oid, status: 'resolvida');
  if (insRes.ok && '${insRes.map?['status']}' == 'resolvida') {
    c.hold(
      id: 'AY1.insert_resolvida_entregue',
      lens: 'AY1',
      severity: 'P2',
      title: 'INSERT disputa status=resolvida persistiu em entregue',
      actor: 'buyer JWT',
      pre: 'entregue',
      repro: 'POST order_disputes status=resolvida',
      expected: 'forçado aberta ou 403',
      obtained: insRes.brief,
    );
  } else if (insRes.ok) {
    c.block('AY1.insert_resolvida_forced', 'AY1',
        'INSERT resolvida forçado a outro status', insRes);
  } else {
    c.block('AY1.insert_resolvida_entregue', 'AY1',
        'INSERT resolvida recusado', insRes);
  }

  final dIns = insRes.ok
      ? insRes
      : await c.insertDispute(orderId: p1.oid);
  final did = dIns.firstId;
  c.note('AY1.dispute_entregue', 'disputa em entregue', dIns.brief, lens: 'AY1');

  // =========================================================================
  // AY5 — receção ∩ disputa / cron 48h / release sem receção real
  // =========================================================================
  final p5 = await mustPay('AY5');
  await c.patchOrder(p5.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  // NEW: buyer concluido from enviado (salta entregue) + release
  final skipEnt = await c.patchOrder(
    p5.oid,
    {'status': 'concluido'},
    jwt: c.buyerJwt,
  );
  var o5 = await c.orderRow(p5.oid);
  c.note('AY5.enviado_to_concluido', 'buyer salta entregue', {
    'hit': skipEnt.brief,
    'status': o5?['status'],
    'completed_at': o5?['completed_at'],
    'shipped_at': o5?['shipped_at'],
  }, lens: 'AY5');

  if (skipEnt.ok && o5?['status'] == 'concluido') {
    final wBefore = await c.wallets();
    final relSkip = await release(p5.oid);
    final wAfter = await c.wallets();
    final dSkip = await c.insertDispute(orderId: p5.oid);
    c.note('AY5.release_sem_entregue', 'release após concluido sem entregue', {
      'rpc': relSkip.brief,
      'w_before': wBefore,
      'w_after': wAfter,
      'dispute_after': dSkip.brief,
    }, lens: 'AY5');
    if (releasedTrue(relSkip)) {
      final ds = (wAfter['seller'] ?? 0) - (wBefore['seller'] ?? 0);
      c.hold(
        id: 'AY5.buyer_release_sem_rececao',
        lens: 'AY5',
        severity: ds > 0 ? 'P1' : 'P2',
        title:
            'Buyer enviado→concluido (sem entregue) + release credita vendedor',
        actor: 'buyer JWT',
        pre: 'enviado; comprador nunca confirmou entregue',
        repro: 'PATCH concluido; rpc batata_release_seller_wallet_for_order',
        expected:
            'release só após receção real (entregue) ou disputa fechada com prova',
        obtained: {
          'hop': skipEnt.brief,
          'release': relSkip.brief,
          'delta_seller': ds,
          'completed_at': o5?['completed_at'],
        },
      );
    } else {
      c.block('AY5.release_sem_entregue_denied', 'AY5',
          'release recusado sem entregue', relSkip);
    }
  } else {
    c.block('AY5.enviado_to_concluido', 'AY5', 'buyer enviado→concluido',
        skipEnt);
  }

  // Cron 48h: JWT p_now futuro + backdate completed_at
  final cronJwt = await c.rpc(
    'batata_generate_auto_feedback',
    {
      'p_now': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 49))
          .toIso8601String(),
    },
    jwt: c.sellerJwt,
  );
  if (cronJwt.ok &&
      cronJwt.body != 'false' &&
      cronJwt.body != 'null' &&
      !cronJwt.brief.toLowerCase().contains('permission') &&
      !cronJwt.brief.toLowerCase().contains('42501')) {
    c.hold(
      id: 'AY5.cron_jwt_pnow',
      lens: 'AY5',
      severity: 'P1',
      title: 'JWT chama batata_generate_auto_feedback com p_now +49h',
      actor: 'seller JWT',
      pre: 'função SECURITY DEFINER; grant deveria ser service_role',
      repro: 'rpc batata_generate_auto_feedback p_now=now+49h',
      expected: '42501 / revoke authenticated',
      obtained: cronJwt.brief,
    );
  } else {
    c.block('AY5.cron_jwt_pnow', 'AY5', 'cron JWT recusado', cronJwt);
  }

  if (o5?['status'] == 'concluido') {
    final backdate = await c.patchOrder(
      p5.oid,
      {
        'completed_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 49))
            .toIso8601String(),
      },
      jwt: c.sellerJwt,
    );
    final afterBd = await c.orderRow(p5.oid);
    final oldC = '${o5?['completed_at']}';
    final newC = '${afterBd?['completed_at']}';
    if (backdate.ok && newC != oldC && newC != 'null') {
      final shifted = DateTime.tryParse(newC);
      final orig = DateTime.tryParse(oldC);
      if (shifted != null &&
          orig != null &&
          shifted.isBefore(orig.subtract(const Duration(hours: 24)))) {
        c.hold(
          id: 'AY5.completed_at_backdate',
          lens: 'AY5',
          severity: 'P1',
          title: 'Seller atrasa completed_at 49h (dispara cron auto-feedback)',
          actor: 'seller JWT',
          pre: 'concluido',
          repro: 'PATCH completed_at=now-49h',
          expected: 'immutable / revertido',
          obtained: {'hit': backdate.brief, 'before': oldC, 'after': newC},
        );
      } else {
        c.block('AY5.completed_at_backdate', 'AY5', 'completed_at não recuou',
            {'hit': backdate.brief, 'before': oldC, 'after': newC});
      }
    } else {
      c.block('AY5.completed_at_backdate', 'AY5', 'completed_at backdate',
          {'hit': backdate.brief, 'row': afterBd?['completed_at']});
    }
  }

  // Verify ANAS: seller concluido
  final p5s = await mustPay('AY5');
  await c.patchOrder(p5s.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final sellerConcl = await c.patchOrder(
    p5s.oid,
    {'status': 'concluido'},
    jwt: c.sellerJwt,
  );
  if (sellerConcl.ok &&
      (await c.orderRow(p5s.oid))?['status'] == 'concluido') {
    c.hold(
      id: 'AY5.regress_seller_concluido',
      lens: 'AY5',
      severity: 'P1',
      title: 'REGRESSÃO ANAS: seller marca concluido',
      actor: 'seller JWT',
      pre: 'enviado',
      repro: 'PATCH status=concluido JWT=seller',
      expected: 'order_seller_cannot_mark_concluido',
      obtained: sellerConcl.brief,
    );
  } else {
    c.block('AY5.anas_seller_concluido', 'AY5', 'ANAS: seller não concluido',
        sellerConcl);
  }

  // =========================================================================
  // AY3 / AY4 / AY8 — devolução + stock + refund caos
  // =========================================================================
  final pRet = await mustPay('AY3');
  final oid = pRet.oid;
  final pid = pRet.pid;
  final w0 = await c.wallets();
  await c.patchOrder(oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  final dRet = await c.insertDispute(orderId: oid);
  final didRet = dRet.firstId;

  // NEW: seller salta pedido_devolucao → em_devolucao directo
  final skipPedido = await c.patchOrder(
    oid,
    {'status': 'em_devolucao'},
    jwt: c.sellerJwt,
  );
  var bSkip = await books(oid, pid);
  c.note('AY3.seller_skip_pedido', 'seller entregue→em_devolucao', {
    'hit': skipPedido.brief,
    'status': (bSkip['order'] as Map?)?['status'],
  }, lens: 'AY3');
  if (skipPedido.ok &&
      (bSkip['order'] as Map?)?['status'] == 'em_devolucao') {
    c.hold(
      id: 'AY3.seller_em_devolucao_sem_pedido',
      lens: 'AY3',
      severity: 'P1',
      title: 'Seller força em_devolucao sem pedido_devolucao do comprador',
      actor: 'seller JWT',
      pre: 'entregue + disputa aberta',
      repro: 'PATCH status=em_devolucao',
      expected: 'só após pedido_devolucao do buyer',
      obtained: {'hit': skipPedido.brief, 'status': 'em_devolucao'},
    );
  } else {
    c.block('AY3.seller_em_devolucao_sem_pedido', 'AY3',
        'seller não salta pedido', skipPedido);
  }

  // Buyer hops
  final hopPedido =
      await c.patchOrder(oid, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt);
  var bPedido = await books(oid, pid);
  c.note('AY3.pedido', 'após pedido_devolucao', {
    'hit': hopPedido.brief,
    'status': (bPedido['order'] as Map?)?['status'],
  }, lens: 'AY3');

  // NEW: buyer em_devolucao / devolucao_entregue / concluido durante return
  final buyerEm = await c.patchOrder(
    oid,
    {'status': 'em_devolucao'},
    jwt: c.buyerJwt,
  );
  if (buyerEm.ok && (await c.orderRow(oid))?['status'] == 'em_devolucao') {
    c.hold(
      id: 'AY3.buyer_marca_em_devolucao',
      lens: 'AY3',
      severity: 'P2',
      title: 'Buyer marca em_devolucao (papel do vendedor/carrier)',
      actor: 'buyer JWT',
      pre: 'pedido_devolucao',
      repro: 'PATCH status=em_devolucao JWT=buyer',
      expected: 'hop do seller',
      obtained: buyerEm.brief,
    );
  } else {
    c.block('AY3.buyer_em_devolucao', 'AY3', 'buyer em_devolucao', buyerEm);
  }

  final buyerBackConcl = await c.patchOrder(
    oid,
    {'status': 'concluido'},
    jwt: c.buyerJwt,
  );
  if (buyerBackConcl.ok &&
      (await c.orderRow(oid))?['status'] == 'concluido') {
    c.hold(
      id: 'AY5.regress_concluido_durante_devolucao',
      lens: 'AY5',
      severity: 'P1',
      title: 'REGRESSÃO ANAS: buyer concluido a meio da devolução',
      actor: 'buyer JWT',
      pre: 'return FSM',
      repro: 'PATCH status=concluido',
      expected: 'order_concluido_denied_during_return',
      obtained: buyerBackConcl.brief,
    );
  } else {
    c.block('AY5.anas_concluido_durante_return', 'AY5',
        'ANAS: buyer não conclui em devolução', buyerBackConcl);
  }

  // Seller hops clássicos (se ainda não em_devolucao)
  o = await c.orderRow(oid);
  if (o?['status'] == 'pedido_devolucao') {
    await c.patchOrder(oid, {'status': 'em_devolucao'}, jwt: c.sellerJwt);
  }
  o = await c.orderRow(oid);
  if (o?['status'] == 'em_devolucao') {
    // Verify ANAS: devolvida shortcut from em_devolucao (exact AS-P2-03 variant)
    final skipHop = await c.patchOrder(
      oid,
      {'status': 'devolvida'},
      jwt: c.sellerJwt,
    );
    if (skipHop.ok && (await c.orderRow(oid))?['status'] == 'devolvida') {
      c.hold(
        id: 'AY3.regress_devolvida_sem_entregue_return',
        lens: 'AY3',
        severity: 'P1',
        title: 'REGRESSÃO ANAS: devolvida a partir de em_devolucao',
        actor: 'seller JWT',
        pre: 'em_devolucao',
        repro: 'PATCH status=devolvida',
        expected: 'order_devolvida_denied (só após devolucao_entregue)',
        obtained: skipHop.brief,
      );
    } else {
      c.block('AY3.anas_devolvida_hop', 'AY3',
          'ANAS: devolvida exige devolucao_entregue', skipHop);
    }
    await c.patchOrder(
      oid,
      {'status': 'devolucao_entregue'},
      jwt: c.sellerJwt,
    );
  }

  // NEW: return_delivered_at no hop (gated ANAS — verify + side path)
  o = await c.orderRow(oid);
  final fakeRetAt = await c.patchOrder(
    oid,
    {'return_delivered_at': DateTime.now().toUtc().toIso8601String()},
    jwt: c.sellerJwt,
  );
  final afterFakeRet = await c.orderRow(oid);
  c.note('AY5.return_delivered_at', 'PATCH return_delivered_at', {
    'hit': fakeRetAt.brief,
    'status': afterFakeRet?['status'],
    'at': afterFakeRet?['return_delivered_at'],
  }, lens: 'AY5');
  if (fakeRetAt.ok &&
      afterFakeRet?['return_delivered_at'] != null &&
      o?['status'] != 'devolucao_entregue') {
    c.hold(
      id: 'AY5.return_delivered_at_fora_hop',
      lens: 'AY5',
      severity: 'P2',
      title: 'Seller sela return_delivered_at fora do hop devolucao_entregue',
      actor: 'seller JWT',
      pre: 'status=${o?['status']}',
      repro: 'PATCH return_delivered_at=now()',
      expected: 'order_return_delivered_at_denied',
      obtained: {
        'hit': fakeRetAt.brief,
        'at': afterFakeRet?['return_delivered_at'],
      },
    );
  }

  o = await c.orderRow(oid);
  if (o?['status'] == 'devolucao_entregue') {
    await c.patchOrder(oid, {'status': 'devolvida'}, jwt: c.sellerJwt);
  }
  var bDev = await books(oid, pid);
  final stDev = (bDev['order'] as Map?)?['status'];
  final qtyDev = (bDev['product'] as Map?)?['quantity'];
  final appliedDev = (bDev['order'] as Map?)?['stock_units_applied'];
  final refundDev = (bDev['order'] as Map?)?['stripe_refund_id'];
  c.note('AY3.devolvida', 'após hops até devolvida', bDev, lens: 'AY3');

  // AM3 verify: stock NÃO restaura sem refund
  if (stDev == 'devolvida' && '${refundDev ?? ''}'.isEmpty) {
    if (qtyDev == 1 || appliedDev == null) {
      c.hold(
        id: 'AY3.am3_regress_stock',
        lens: 'AY3',
        severity: 'P1',
        title: 'REGRESSÃO AM3/AHAM: devolvida restaurou stock sem refund',
        actor: 'triggers',
        pre: 'captura viva',
        repro: 'hops até devolvida',
        expected: 'qty 0, applied set',
        obtained: {
          'qty': qtyDev,
          'applied': appliedDev,
          'refund': refundDev,
        },
      );
    } else {
      c.block('AY3.am3_verify', 'AY3', 'stock preso até refund', {
        'qty': qtyDev,
        'applied': appliedDev,
      });
    }
  }

  // 2.º checkout DURANTE devolvida com captura viva
  final availDev = await c.stockCheck(pid);
  final b2Hold = await c.insertOrderHit(
    productId: pid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    price: 5.0,
  );
  final chkHeld = await c.checkout(
    orderId: b2Hold.firstId ?? oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    productId: pid,
    seller: c.sellerId,
    amount: 5.9,
  );
  c.note('AY3.second_checkout_devolvida', 'B2 checkout com captura 1 viva', {
    'avail': availDev.brief,
    'hold': b2Hold.brief,
    'checkout': chkHeld.brief,
    'qty': qtyDev,
  }, lens: 'AY8');
  final chkOk = chkHeld.ok && chkHeld.sessionId != null;
  if (chkOk && (qtyDev == 0 || (appliedDev != null && qtyDev != 1))) {
    c.hold(
      id: 'AY8.second_session_captura_viva',
      lens: 'AY8',
      severity: 'P1',
      title: '2.ª Checkout Session no SKU com 1.ª captura viva e stock preso',
      actor: 'buyer2 JWT',
      pre: 'devolvida sem stripe_refund_id, qty 0',
      repro: 'create-payment-intent B2 mesmo product_id',
      expected: 'available=0 / recusa',
      obtained: {
        'avail': availDev.brief,
        'checkout': chkHeld.brief,
        'qty': qtyDev,
      },
    );
  }

  // Fake money fields
  final fakeRef = await c.patchOrder(
    oid,
    {'stripe_refund_id': 're_RTAY_fake'},
    jwt: c.sellerJwt,
  );
  if (fakeRef.ok &&
      '${(await c.orderRow(oid))?['stripe_refund_id']}' == 're_RTAY_fake') {
    c.hold(
      id: 'AY4.fake_stripe_refund_id',
      lens: 'AY4',
      severity: 'P0',
      title: 'Seller PATCH stripe_refund_id falso',
      actor: 'seller JWT',
      pre: 'devolvida',
      repro: 'PATCH stripe_refund_id=re_RTAY_fake',
      expected: 'order_money_fields_immutable',
      obtained: fakeRef.brief,
    );
  } else {
    c.block('AY4.fake_stripe_refund_id', 'AY4', 'fake refund id', fakeRef);
  }

  // AY4 — refund-order em devolvida (ANAS: terminal permanece devolvida)
  final beforeRef = await books(oid, pid);
  final ref1 = await c.refund(oid, jwt: c.sellerJwt);
  final afterRef1 = await books(oid, pid);
  c.note('AY4.refund1', 'refund-order #1', {
    'hit': ref1.brief,
    'before': (beforeRef['order'] as Map?)?['status'],
    'after': (afterRef1['order'] as Map?)?['status'],
    'refund_id': (afterRef1['order'] as Map?)?['stripe_refund_id'],
    'qty': (afterRef1['product'] as Map?)?['quantity'],
  }, lens: 'AY4');

  final refOk = ref1.ok && ref1.map?['ok'] != false;
  final afterSt = (afterRef1['order'] as Map?)?['status'];
  final afterQty = (afterRef1['product'] as Map?)?['quantity'];

  if (!refOk && ref1.body.contains('order_refund_blocked_shipped')) {
    c.hold(
      id: 'AY4.am4_regress',
      lens: 'AY4',
      severity: 'P1',
      title: 'REGRESSÃO AM4: refund-order em devolvida blocked shipped',
      actor: 'seller JWT',
      pre: 'devolvida + shipped_at',
      repro: 'POST refund-order',
      expected: 'ok (gate terminal)',
      obtained: ref1.brief,
    );
  } else if (refOk) {
    c.block('AY4.am4_verify', 'AY4', 'refund-order em devolvida ok', ref1);
    if (afterSt == 'cancelado') {
      c.hold(
        id: 'AY4.regress_devolvida_to_cancelado',
        lens: 'AY4',
        severity: 'P2',
        title: 'REGRESSÃO ANAS: refund reescreve devolvida→cancelado',
        actor: 'Edge refund-order',
        pre: 'devolvida',
        repro: 'POST refund-order',
        expected: 'terminal permanece devolvida',
        obtained: {'hit': ref1.brief, 'status': afterSt},
      );
    }
    if (afterQty is num && afterQty >= 2) {
      c.hold(
        id: 'AY3.double_stock_restore',
        lens: 'AY3',
        severity: 'P1',
        title: 'Refund restaurou qty≥2 (era 1)',
        actor: 'triggers',
        pre: 'qty 0 applied 1',
        repro: 'refund-order',
        expected: 'qty=1',
        obtained: afterRef1,
      );
    }
  }

  // NEW: webhook/refund duplo — 2.º refund-order
  final ref2 = await c.refund(oid, jwt: c.sellerJwt);
  final afterRef2 = await books(oid, pid);
  c.note('AY4.refund2', 'refund-order #2 (duplo)', {
    'hit': ref2.brief,
    'qty': (afterRef2['product'] as Map?)?['quantity'],
    'status': (afterRef2['order'] as Map?)?['status'],
    'refund_id': (afterRef2['order'] as Map?)?['stripe_refund_id'],
  }, lens: 'AY4');
  final qty2 = (afterRef2['product'] as Map?)?['quantity'];
  if (qty2 is num && afterQty is num && qty2 > afterQty) {
    c.hold(
      id: 'AY4.double_refund_stock',
      lens: 'AY4',
      severity: 'P1',
      title: '2.º refund-order incrementou stock outra vez',
      actor: 'Edge refund-order ×2',
      pre: 'já reembolsado',
      repro: 'POST refund-order segunda vez',
      expected: 'idempotente, qty inalterada',
      obtained: {
        'first_qty': afterQty,
        'second_qty': qty2,
        'hit': ref2.brief,
      },
    );
  } else {
    c.block('AY4.double_refund_idempotent', 'AY4', '2.º refund idempotente',
        ref2);
  }

  // Buyer refund-order
  final pBuy = await mustPay('AY4');
  final buyerRef = await c.refund(pBuy.oid, jwt: c.buyerJwt);
  if (buyerRef.ok && buyerRef.map?['ok'] == true) {
    c.hold(
      id: 'AY4.buyer_refund_order',
      lens: 'AY4',
      severity: 'P1',
      title: 'Buyer chama refund-order com sucesso',
      actor: 'buyer JWT',
      pre: 'pago',
      repro: 'POST refund-order JWT=buyer',
      expected: '403 seller-only',
      obtained: buyerRef.brief,
    );
  } else {
    c.block('AY4.buyer_refund_order', 'AY4', 'buyer refund-order', buyerRef);
  }

  // Partial RPC seller
  final partSeller = await c.rpc(
    'batata_process_partial_refund_dispute',
    {'p_order_id': oid, 'p_refund_percent': 50},
    jwt: c.sellerJwt,
  );
  if (partSeller.ok &&
      partSeller.body != 'false' &&
      !partSeller.brief.toLowerCase().contains('not_allowed')) {
    c.hold(
      id: 'AY4.partial_seller_rpc',
      lens: 'AY4',
      severity: 'P1',
      title: 'Seller executa partial refund RPC',
      actor: 'seller JWT',
      pre: 'cadeia devolução',
      repro: 'rpc percent=50',
      expected: 'not_allowed',
      obtained: partSeller.brief,
    );
  } else {
    c.block('AY4.partial_seller_rpc', 'AY4', 'partial seller', partSeller);
  }

  // =========================================================================
  // AY4/AY8 — Stripe TEST refund FORA da Edge + release (mint?)
  // =========================================================================
  final pStr = await mustPay('AY4');
  await c.patchOrder(pStr.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(pStr.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  await c.patchOrder(pStr.oid, {'status': 'concluido'}, jwt: c.buyerJwt);
  final oStr = await c.orderRow(pStr.oid);
  final piStr = oStr?['stripe_payment_intent_id']?.toString();
  final wStr0 = await c.wallets();

  if (piStr != null && piStr.isNotEmpty && c.stripeTestKey != null) {
    final stRef = await c.stripeRefund(piStr);
    c.note('AY4.stripe_direct_refund', 'Stripe API refund PI (fora Edge)', {
      'pi': piStr,
      'hit': stRef.brief,
    }, lens: 'AY4');
    final oAfterSt = await c.orderRow(pStr.oid);
    final relAfterSt = await release(pStr.oid);
    final wStr1 = await c.wallets();
    final dSeller = (wStr1['seller'] ?? 0) - (wStr0['seller'] ?? 0);
    c.note('AY8.stripe_refund_then_release', 'caixa pós refund Stripe directo', {
      'order': oAfterSt,
      'release': relAfterSt.brief,
      'w0': wStr0,
      'w1': wStr1,
      'delta_seller': dSeller,
    }, lens: 'AY8');
    final stripeOk = stRef.ok;
    final stillNoRefundId =
        '${oAfterSt?['stripe_refund_id'] ?? ''}'.isEmpty;
    if (stripeOk && releasedTrue(relAfterSt) && dSeller > 0) {
      c.hold(
        id: 'AY8.release_apos_stripe_refund_directo',
        lens: 'AY8',
        severity: 'P0',
        title:
            'Stripe já reembolsou o PI; release JWT ainda credita a carteira do vendedor',
        actor: 'buyer JWT (release) · Stripe TEST (refund)',
        pre: 'concluido; refund Stripe API directo no PI',
        repro:
            'POST /v1/refunds payment_intent=PI; rpc batata_release_seller_wallet_for_order',
        expected:
            'release false (stripe_refund_id ou evento refund); sem Δseller',
        obtained: {
          'stripe': stRef.brief,
          'order_refund_id': oAfterSt?['stripe_refund_id'],
          'status': oAfterSt?['status'],
          'release': relAfterSt.brief,
          'delta_seller': dSeller,
          'still_no_refund_id': stillNoRefundId,
        },
      );
    } else if (stripeOk && stillNoRefundId) {
      c.note(
        'AY4.db_desync_stripe_refund',
        'PI reembolsado na Stripe; stripe_refund_id continua null (webhook não cobre charge.refunded)',
        {
          'pi': piStr,
          'db_refund_id': oAfterSt?['stripe_refund_id'],
          'status': oAfterSt?['status'],
          'release': relAfterSt.brief,
        },
        lens: 'AY4',
      );
    }

    // Partial refund noutro PI
    final pPart = await mustPay('AY4');
    await c.patchOrder(pPart.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
    await c.patchOrder(pPart.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
    final dPart = await c.insertDispute(orderId: pPart.oid);
    await c.patchOrder(
      pPart.oid,
      {'status': 'pedido_devolucao'},
      jwt: c.buyerJwt,
    );
    await c.patchOrder(
      pPart.oid,
      {'status': 'em_devolucao'},
      jwt: c.sellerJwt,
    );
    await c.patchOrder(
      pPart.oid,
      {'status': 'devolucao_entregue'},
      jwt: c.sellerJwt,
    );
    await c.patchOrder(pPart.oid, {'status': 'devolvida'}, jwt: c.sellerJwt);
    final oPart = await c.orderRow(pPart.oid);
    final piPart = oPart?['stripe_payment_intent_id']?.toString();
    if (piPart != null) {
      final partStripe = await c.stripeRefund(piPart, amountCents: 100);
      final oPartAfter = await c.orderRow(pPart.oid);
      final bPart = await books(pPart.oid, pPart.pid);
      c.note('AY4.partial_stripe', 'refund Stripe 100¢ de 590¢', {
        'hit': partStripe.brief,
        'status': oPartAfter?['status'],
        'refund_id': oPartAfter?['stripe_refund_id'],
        'qty': (bPart['product'] as Map?)?['quantity'],
        'dispute': dPart.brief,
      }, lens: 'AY4');
      final edgeAfterPart = await c.refund(pPart.oid, jwt: c.sellerJwt);
      final bPart2 = await books(pPart.oid, pPart.pid);
      c.note('AY4.partial_then_edge', 'refund-order após partial Stripe', {
        'hit': edgeAfterPart.brief,
        'status': (bPart2['order'] as Map?)?['status'],
        'qty': (bPart2['product'] as Map?)?['quantity'],
        'refund_id': (bPart2['order'] as Map?)?['stripe_refund_id'],
      }, lens: 'AY4');
      if (partStripe.ok &&
          '${oPartAfter?['status']}' == 'devolvida' &&
          ((bPart['product'] as Map?)?['quantity'] == 1) &&
          '${oPartAfter?['stripe_refund_id'] ?? ''}'.isEmpty) {
        c.note(
          'AY4.partial_no_db',
          'partial Stripe não selou stripe_refund_id nem restaurou stock (esperado se webhook não escuta refunds)',
          oPartAfter,
          lens: 'AY4',
        );
      }
      // Se Edge depois marcar refund_id de um refund PARCIAL e restaurar stock
      // total + status cancelado — finding.
      final st2 = (bPart2['order'] as Map?)?['status'];
      final qtyAfterEdge = (bPart2['product'] as Map?)?['quantity'];
      if (edgeAfterPart.ok &&
          edgeAfterPart.map?['ok'] != false &&
          qtyAfterEdge == 1 &&
          partStripe.ok) {
        c.hold(
          id: 'AY4.partial_then_full_stock',
          lens: 'AY4',
          severity: 'P2',
          title:
              'Partial Stripe 100¢ + refund-order: stock restaurou unidade inteira (ledger Stripe parcial)',
          actor: 'Stripe TEST + Edge',
          pre: 'devolvida, captura 590¢, refund 100¢ depois Edge',
          repro: 'POST /v1/refunds amount=100; POST refund-order',
          expected:
              'stock só após refund residual completo; status não mentir total',
          obtained: {
            'partial': partStripe.brief,
            'edge': edgeAfterPart.brief,
            'status': st2,
            'qty': qtyAfterEdge,
          },
        );
      }
    }
  } else {
    c.skip('AY4.stripe_direct', 'AY4', 'sem sk_test_ ou PI', {
      'pi': piStr,
      'sk': c.stripeTestKey != null,
    });
  }

  // Release + refund: após crédito, tentar refund-order em concluido
  final pRel = await mustPay('AY8');
  await c.patchOrder(pRel.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(pRel.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  await c.patchOrder(pRel.oid, {'status': 'concluido'}, jwt: c.buyerJwt);
  final wRel0 = await c.wallets();
  final relHappy = await release(pRel.oid);
  final wRel1 = await c.wallets();
  final refAfterRel = await c.refund(pRel.oid, jwt: c.sellerJwt);
  final wRel2 = await c.wallets();
  c.note('AY8.release_then_refund', 'release feliz + refund-order', {
    'release': relHappy.brief,
    'refund': refAfterRel.brief,
    'd1': (wRel1['seller'] ?? 0) - (wRel0['seller'] ?? 0),
    'd2_buyer': (wRel2['buyer'] ?? 0) - (wRel1['buyer'] ?? 0),
    'd2_seller': (wRel2['seller'] ?? 0) - (wRel1['seller'] ?? 0),
  }, lens: 'AY8');
  if (releasedTrue(relHappy) &&
      refAfterRel.ok &&
      refAfterRel.map?['ok'] == true) {
    final keepSeller = (wRel2['seller'] ?? 0) >= (wRel1['seller'] ?? 0);
    c.hold(
      id: 'AY8.release_and_refund',
      lens: 'AY8',
      severity: keepSeller ? 'P0' : 'P1',
      title: 'Release credita seller e refund-order ainda corre no mesmo PI',
      actor: 'buyer release · seller refund-order',
      pre: 'concluido após envio',
      repro: 'rpc release; POST refund-order',
      expected: 'refund blocked shipped em concluido',
      obtained: {
        'release': relHappy.brief,
        'refund': refAfterRel.brief,
        'seller_kept_credit': keepSeller,
      },
    );
  } else {
    c.block('AY8.release_then_refund_blocked', 'AY8',
        'refund após release recusado ou release false', {
      'release': relHappy.brief,
      'refund': refAfterRel.brief,
    });
  }

  // =========================================================================
  // AY6 — etiqueta / carrier / captura
  // =========================================================================
  final unpaid =
      await c.createProduct(qty: 1, price: 8, title: '$prefix-unpaid');
  if (unpaid != null) {
    final uo = await c.insertOrder(
      productId: unpaid,
      jwt: c.buyerJwt,
      price: 8,
      shipping: 'CTT',
    );
    if (uo != null) {
      final shipUnpaid = await c.patchOrder(
        uo,
        {'status': 'enviado'},
        jwt: c.sellerJwt,
      );
      final urow = await c.orderRow(uo);
      if (shipUnpaid.ok && urow?['status'] == 'enviado') {
        c.hold(
          id: 'AY6.enviado_without_capture',
          lens: 'AY6',
          severity: 'P1',
          title: 'Seller marca enviado sem captura plataforma',
          actor: 'seller JWT',
          pre: 'reserva_pendente, Pagamento na app, sem PI',
          repro: 'PATCH status=enviado',
          expected: 'order_status_requires_capture',
          obtained: {'hit': shipUnpaid.brief, 'row': urow},
        );
      } else {
        c.block('AY6.enviado_without_capture', 'AY6', 'enviado sem captura',
            shipUnpaid);
      }
    }
  }

  final freezeShip = await c.patchOrder(
    p1.oid,
    {'shipping_method': 'mão'},
    jwt: c.buyerJwt,
  );
  if (freezeShip.ok) {
    final fr = await c.orderRow(p1.oid);
    if ('${fr?['shipping_method']}'.contains('mão')) {
      c.hold(
        id: 'AY6.shipping_unfrozen',
        lens: 'AY6',
        severity: 'P1',
        title: 'Buyer altera shipping_method após pagamento',
        actor: 'buyer JWT',
        pre: 'pós-pago',
        repro: 'PATCH shipping_method=mão',
        expected: 'order_shipping_frozen_after_payment',
        obtained: freezeShip.brief,
      );
    } else {
      c.block('AY6.shipping_unfrozen', 'AY6', 'shipping freeze no-change',
          freezeShip);
    }
  } else {
    c.block('AY6.shipping_frozen', 'AY6', 'shipping freeze', freezeShip);
  }

  if (didRet != null) {
    final evilLabel =
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/order_disputes/dead/label.pdf';
    final lab = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$didRet',
      jwt: c.sellerJwt,
      body: {'return_label_url': evilLabel},
    );
    final labRow = await c.rest(
      'GET',
      'order_disputes?id=eq.$didRet&select=id,return_label_url',
      service: true,
    );
    if ('${labRow.map?['return_label_url'] ?? ''}' == evilLabel) {
      c.hold(
        id: 'AY6.label_sign_alheio',
        lens: 'AY6',
        severity: 'P2',
        title: 'return_label_url aceita path sign fleaber_private alheio',
        actor: 'seller JWT',
        pre: 'disputa return',
        repro: 'PATCH return_label_url=…/sign/fleaber_private/order_disputes/dead/…',
        expected: 'só etiqueta da encomenda',
        obtained: lab.brief,
      );
    } else {
      c.block('AY6.label_sign_alheio', 'AY6', 'label path alheio', {
        'hit': lab.brief,
        'url': labRow.map?['return_label_url'],
      });
    }
  }

  // =========================================================================
  // AY7 — prova disputa: path alheio, authenticated outro order_id, chat_media
  // =========================================================================
  final shallowPath =
      'object/fleaber_private/order_proofs/${c.buyerId}/rtay-shallow.png';
  final upShallow = await c.storage(
    'POST',
    shallowPath,
    jwt: c.buyerJwt,
    bytes: png,
    contentType: 'image/png',
  );
  c.note('AY7.upload_shallow', 'upload order_proofs raso (ANAS deve 4xx ou SELECT 404)',
      upShallow.brief,
      lens: 'AY7');

  final paidS2 = await c.e2e('setup_paid_order', {'initial_qty': 1},
      seller: c.seller2Id, buyer: c.buyerId);
  final oidS2 = c.parseE2eOrderId(paidS2);
  final pidS2 = c.parseE2eProductId(paidS2);
  if (pidS2 != null) c.createdProductIds.add(pidS2);
  if (oidS2 != null) c.createdOrderIds.add(oidS2);

  if (oidS2 != null) {
    await c.patchOrder(oidS2, {'status': 'enviado'}, jwt: c.seller2Jwt);
    await c.patchOrder(oidS2, {'status': 'entregue'}, jwt: c.buyerJwt);
    final dS2 = await c.insertDispute(orderId: oidS2);

    final pathDisp =
        'object/fleaber_private/order_disputes/${c.buyerId}/$oidS2/rtay-disp.png';
    final upDisp = await c.storage(
      'POST',
      pathDisp,
      jwt: c.buyerJwt,
      bytes: png,
      contentType: 'image/png',
    );
    final s1Disp = await c.storage('GET', pathDisp, jwt: c.sellerJwt);
    final s2Disp = await c.storage('GET', pathDisp, jwt: c.seller2Jwt);
    c.note('AY7.dispute_path', 'S1 vs S2 lê disputa B1–S2', {
      'upload': upDisp.brief,
      's1': s1Disp.brief,
      's2': s2Disp.brief,
      'dispute': dS2.brief,
    }, lens: 'AY7');
    if (s1Disp.ok) {
      c.hold(
        id: 'AY7.s1_reads_s2_dispute',
        lens: 'AY7',
        severity: 'P1',
        title: 'S1 lê provas disputa B1–S2 (path com order_id)',
        actor: 'seller JWT S1',
        pre: 'order_disputes/{B1}/{orderS2}/…',
        repro: 'GET storage JWT=S1',
        expected: '403 — só S2',
        obtained: s1Disp.brief,
      );
    } else {
      c.block('AY7.am7_still_closed', 'AY7', 'S1 não lê disputa S2',
          {'s1': s1Disp.brief, 's2': s2Disp.brief});
    }

    // Prefix leak: ficheiro order_disputes/{B1}/{oidS2}-extra.png (sem slash)
    final prefixPath =
        'object/fleaber_private/order_disputes/${c.buyerId}/$oidS2-extra.png';
    final upPref = await c.storage(
      'POST',
      prefixPath,
      jwt: c.buyerJwt,
      bytes: png,
      contentType: 'image/png',
    );
    final s1Pref = await c.storage('GET', prefixPath, jwt: c.sellerJwt);
    final s2Pref = await c.storage('GET', prefixPath, jwt: c.seller2Jwt);
    c.note('AY7.prefix_path', 'path order_id + sufixo sem /', {
      'up': upPref.brief,
      's1': s1Pref.brief,
      's2': s2Pref.brief,
    }, lens: 'AY7');
    if (s1Pref.ok) {
      c.hold(
        id: 'AY7.s1_reads_prefix_dispute',
        lens: 'AY7',
        severity: 'P1',
        title: 'S1 lê order_disputes/{B1}/{oidS2}-extra (LIKE prefix sem /)',
        actor: 'seller JWT S1',
        pre: 'policy name like …/{order_id}%',
        repro: 'GET …/{oidS2}-extra.png JWT=S1',
        expected: '403',
        obtained: s1Pref.brief,
      );
    } else {
      c.block('AY7.prefix_s1', 'AY7', 'S1 prefix 403', s1Pref);
    }

    // Shallow SELECT verify ANAS
    final s1Shallow = await c.storage('GET', shallowPath, jwt: c.sellerJwt);
    final s2Shallow = await c.storage('GET', shallowPath, jwt: c.seller2Jwt);
    if (s1Shallow.ok || s2Shallow.ok) {
      c.hold(
        id: 'AY7.regress_shallow_order_proofs',
        lens: 'AY7',
        severity: 'P1',
        title: 'REGRESSÃO ANAS: seller lê order_proofs raso',
        actor: 'seller JWT',
        pre: 'order_proofs/{B1}/ficheiro',
        repro: 'GET storage raso',
        expected: '404/403',
        obtained: {'s1': s1Shallow.brief, 's2': s2Shallow.brief},
      );
    } else {
      c.block('AY7.anas_shallow', 'AY7', 'ANAS: raso ilegível', {
        's1': s1Shallow.brief,
        's2': s2Shallow.brief,
        'up': upShallow.brief,
      });
    }

    // NEW: proof_photos authenticated URL de OUTRO order_id
    final otherUrl =
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/authenticated/fleaber_private/order_disputes/${c.buyerId}/$oidS2/rtay-disp.png';
    final photoOther = did == null
        ? HttpHit(0, 'no_did', null)
        : await c.rest(
            'PATCH',
            'order_disputes?id=eq.$did',
            jwt: c.buyerJwt,
            body: {
              'proof_photos': [otherUrl],
            },
          );
    if (photoOther.ok && photoOther.body.contains(oidS2 ?? 'no')) {
      c.hold(
        id: 'AY7.proof_photos_other_order',
        lens: 'AY7',
        severity: 'P2',
        title:
            'proof_photos aceita URL authenticated de outra encomenda (S2) na disputa S1',
        actor: 'buyer JWT',
        pre: 'disputa B1–S1; ficheiro em pasta order S2',
        repro:
            'PATCH proof_photos=[authenticated/fleaber_private/order_disputes/{B1}/{oidS2}/…]',
        expected: 'deny — path tem de ser desta order_id',
        obtained: photoOther.brief,
      );
    } else {
      c.block('AY7.proof_photos_other_order', 'AY7',
          'proof outro order_id', photoOther);
    }

    // chat_media public (ANAS deve negar) + GET público
    final pubUrl =
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/chat_media/rtay.png';
    final pubPhoto = did == null
        ? HttpHit(0, 'no_did', null)
        : await c.rest(
            'PATCH',
            'order_disputes?id=eq.$did',
            jwt: c.buyerJwt,
            body: {
              'proof_photos': [pubUrl],
            },
          );
    if (pubPhoto.ok && pubPhoto.body.contains('chat_media')) {
      c.hold(
        id: 'AY7.regress_proof_public',
        lens: 'AY7',
        severity: 'P2',
        title: 'REGRESSÃO ANAS: proof_photos aceita object/public/chat_media',
        actor: 'buyer JWT',
        pre: 'disputa',
        repro: 'PATCH public chat_media',
        expected: 'dispute_proof_url_denied',
        obtained: pubPhoto.brief,
      );
    } else {
      c.block('AY7.anas_public_proof', 'AY7', 'public proof denied', pubPhoto);
    }

    // Upload chat_media e GET anon (leak se disputa apontar)
    final chatUp = await c.storage(
      'POST',
      'object/chat_media/rtay-leak.png',
      jwt: c.buyerJwt,
      bytes: png,
      contentType: 'image/png',
    );
    final anonGet = await c.storage(
      'GET',
      'object/public/chat_media/rtay-leak.png',
    );
    c.note('AY7.chat_media', 'upload+GET público chat_media', {
      'up': chatUp.brief,
      'anon': anonGet.brief,
    }, lens: 'AY7');
    if (anonGet.ok) {
      c.note(
        'AY7.chat_media_public_get',
        'GET public/chat_media funciona (bucket público) — só finding se proof_photos aceitar',
        anonGet.brief,
        lens: 'AY7',
      );
    }

    // B2 hijack write pasta B1
    final hijack = await c.storage(
      'POST',
      'object/fleaber_private/order_disputes/${c.buyerId}/$oidS2/hijack.png',
      jwt: c.buyer2Jwt,
      bytes: png,
      contentType: 'image/png',
    );
    if (hijack.ok) {
      c.hold(
        id: 'AY7.b2_write_b1_folder',
        lens: 'AY7',
        severity: 'P1',
        title: 'B2 escreve na pasta order_disputes de B1',
        actor: 'buyer2 JWT',
        pre: 'path B1',
        repro: 'POST storage pasta alheia',
        expected: '403',
        obtained: hijack.brief,
      );
    } else {
      c.block('AY7.b2_write_b1', 'AY7', 'write hijack 403', hijack);
    }

    // Replies com authenticated outro order
    if (didRet != null) {
      final replyOther = await c.rest(
        'POST',
        'order_dispute_replies',
        jwt: c.buyerJwt,
        body: {
          'dispute_id': didRet,
          'sender_id': c.buyerId,
          'message': 'prova alheia',
          'proof_photos': [otherUrl],
        },
      );
      if (replyOther.ok) {
        c.hold(
          id: 'AY7.reply_other_order_url',
          lens: 'AY7',
          severity: 'P2',
          title: 'reply proof_photos aceita authenticated de outra order',
          actor: 'buyer JWT',
          pre: 'disputa return',
          repro: 'POST replies proof_photos URL order S2',
          expected: 'path desta disputa/order',
          obtained: replyOther.brief,
        );
      } else {
        c.block('AY7.reply_other_order', 'AY7', 'reply other order',
            replyOther);
      }
    }
  }

  // Webhook sem assinatura
  final wh = await c.edge('stripe-webhook', {
    'type': 'charge.refunded',
    'data': {
      'object': {'id': 're_fake', 'payment_intent': p1.pi}
    },
  }, jwt: c.buyerJwt);
  if (wh.ok && wh.map?['ok'] == true) {
    c.hold(
      id: 'AY4.webhook_no_sig',
      lens: 'AY4',
      severity: 'P0',
      title: 'stripe-webhook aceita charge.refunded sem assinatura',
      actor: 'buyer JWT',
      pre: 'sem stripe-signature',
      repro: 'POST functions/v1/stripe-webhook JSON',
      expected: '400 missing_signature',
      obtained: wh.brief,
    );
  } else {
    c.block('AY4.webhook_no_sig', 'AY4', 'webhook sem sig', wh);
  }

  await c.dumpAll('pass1.json');
  stdout.writeln(
    'PASS1 done findings=${c.findings.length} blocked=${c.blocked.length} notes=${c.notes.length}',
  );
}
