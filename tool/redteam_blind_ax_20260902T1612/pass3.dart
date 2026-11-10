/// PASS 3 — AX Stripe TEST pago · FSM return · release · refund · caixa. Não corrige.
import 'dart:io';
import '_rtax.dart';

Future<void> main() async {
  final c = Rtax.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.ensureMinBalance(c.sellerId, 8);
  final w0 = await c.wallets();
  c.note('p3.snap', 'saldos', w0, lens: 'AX7');

  Future<({String oid, String pid, String? pi})> mustPay(String lens) async {
    final paid = await c.payToPago(lens: lens, initialQty: 1);
    if (paid == null) throw StateError('setup_paid_order $lens');
    return paid;
  }

  // Cross-user GET
  final led = await c.rest(
    'GET',
    'wallet_payout_ledger?user_id=eq.${c.sellerId}&select=idempotency_key,amount_cents,status,stripe_transfer_id&limit=5',
    jwt: c.buyerJwt,
  );
  c.note('ax7.ledger', 'buyer GET ledger seller', {
    'http': led.status,
    'n': led.list.length,
    'brief': led.brief,
  }, lens: 'AX7');
  if (led.ok && led.list.isNotEmpty) {
    c.hold(
      id: 'AX7-buyer-reads-seller-ledger',
      lens: 'AX7',
      severity: 'P2',
      title: 'Buyer leu wallet_payout_ledger do vendedor',
      actor: 'buyer JWT',
      pre: 'ledger seller',
      repro: 'GET wallet_payout_ledger?user_id=eq.seller',
      expected: '200 []',
      obtained: {'n': led.list.length, 'brief': led.brief},
    );
  } else {
    c.block('AX7.ledger-cross', 'AX7', 'GET ledger cruzado', led);
  }

  // ===========================================================================
  // AX6 — seller concluido (ANAS: order_seller_cannot_mark_concluido)
  //        + cron 48h via completed_at / generate_auto_feedback
  // ===========================================================================
  final pSellerCon = await mustPay('AX6');
  await c.patchOrder(pSellerCon.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final sellerCon = await c.patchOrder(
    pSellerCon.oid,
    {'status': 'concluido'},
    jwt: c.sellerJwt,
  );
  var oSellerCon = await c.orderRow(pSellerCon.oid);
  final relSellerCon = await c.release(pSellerCon.oid);
  c.note('ax6.seller.concluido', 'seller PATCH concluido após enviado', {
    'hop': sellerCon.brief,
    'status': oSellerCon?['status'],
    'completed_at': oSellerCon?['completed_at'],
    'release': relSellerCon.brief,
  }, lens: 'AX6');
  final mintedSellerCon = (relSellerCon.json == true ||
          relSellerCon.body == 'true') &&
      oSellerCon?['status'] == 'concluido';
  if (sellerCon.ok && oSellerCon?['status'] == 'concluido') {
    c.hold(
      id: 'AX6-seller-concluido',
      lens: 'AX6',
      severity: mintedSellerCon ? 'P1' : 'P1',
      title: 'Seller marcou concluido após enviado (ANAS deveria 403)',
      actor: 'seller JWT',
      pre: 'pago→enviado; buyer nunca confirmou',
      repro: 'PATCH status=concluido JWT=seller',
      expected: '403 order_seller_cannot_mark_concluido',
      obtained: {
        'hop': sellerCon.brief,
        'status': oSellerCon?['status'],
        'completed_at': oSellerCon?['completed_at'],
        'release': relSellerCon.brief,
      },
    );
  } else {
    c.block('AX6.seller-concluido', 'AX6', 'seller concluido recusado', {
      'http': sellerCon.status,
      'db': oSellerCon?['status'],
      'release': relSellerCon.brief,
    });
  }

  // completed_at backdate (48h clock)
  final back = DateTime.now().toUtc().subtract(const Duration(hours: 50)).toIso8601String();
  final patchDone = await c.patchOrder(
    pSellerCon.oid,
    {'completed_at': back},
    jwt: c.sellerJwt,
  );
  oSellerCon = await c.orderRow(pSellerCon.oid);
  final cronJwt = await c.rpc('batata_generate_auto_feedback', {
    'p_now': DateTime.now().toUtc().add(const Duration(days: 3)).toIso8601String(),
  }, jwt: c.sellerJwt);
  c.note('ax6.completed_at', 'backdate + cron JWT', {
    'patch': patchDone.brief,
    'completed_at': oSellerCon?['completed_at'],
    'cron': cronJwt.brief,
  }, lens: 'AX6');
  final ca = '${oSellerCon?['completed_at'] ?? ''}';
  final parsedCa = DateTime.tryParse(ca);
  final backdated = parsedCa != null &&
      DateTime.now().toUtc().difference(parsedCa).inHours >= 40;
  if (patchDone.ok && backdated) {
    c.hold(
      id: 'AX6-backdate-completed-at',
      lens: 'AX6',
      severity: 'P1',
      title: 'Seller gravou completed_at há 50h (relógio 48h)',
      actor: 'seller JWT',
      pre: 'encomenda existente',
      repro: 'PATCH completed_at=now-50h',
      expected: 'silencioso revert / 403',
      obtained: {
        'patch': patchDone.brief,
        'completed_at': ca,
        'cron': cronJwt.brief,
      },
    );
  } else {
    c.block('AX6.backdate', 'AX6', 'completed_at JWT não recuou 50h', {
      'http': patchDone.status,
      'ca': ca,
      'cron': cronJwt.status,
    });
  }

  // Buyer concluido during return — ANAS 403 (não HOLD exact AR7)
  final pRet = await mustPay('AX6');
  await c.markMao(pRet.oid);
  await c.patchOrder(pRet.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(pRet.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  final disp = await c.insertDispute(pRet.oid);
  await c.patchOrder(pRet.oid, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt);
  final buyerConDuring = await c.patchOrder(
    pRet.oid,
    {'status': 'concluido'},
    jwt: c.buyerJwt,
  );
  final oRet = await c.orderRow(pRet.oid);
  c.note('ax6.buyer.concluido-return', 'buyer concluido em devolução (ANAS)', {
    'dispute': disp.brief,
    'hop': buyerConDuring.brief,
    'status': oRet?['status'],
  }, lens: 'AX6');
  if (buyerConDuring.ok && oRet?['status'] == 'concluido') {
    c.hold(
      id: 'AX6-buyer-concluido-during-return-still-open',
      lens: 'AX6',
      severity: 'P1',
      title: 'Buyer ainda marca concluido a meio da devolução (AR7 não fechou)',
      actor: 'buyer JWT',
      pre: 'pedido_devolucao',
      repro: 'PATCH concluido',
      expected: '403 order_concluido_denied_during_return',
      obtained: {'hop': buyerConDuring.brief, 'status': oRet?['status']},
    );
  } else {
    c.block('AX6.buyer-concluido-return', 'AX6', 'ANAS 403 during return', {
      'http': buyerConDuring.status,
      'db': oRet?['status'],
    });
  }

  // Seller concluido during return
  final sellerConRet = await c.patchOrder(
    pRet.oid,
    {'status': 'concluido'},
    jwt: c.sellerJwt,
  );
  final oRet2 = await c.orderRow(pRet.oid);
  c.note('ax6.seller.concluido-return', 'seller concluido em devolução', {
    'hop': sellerConRet.brief,
    'status': oRet2?['status'],
  }, lens: 'AX6');
  if (sellerConRet.ok && oRet2?['status'] == 'concluido') {
    c.hold(
      id: 'AX6-seller-concluido-during-return',
      lens: 'AX6',
      severity: 'P1',
      title: 'Seller marcou concluido durante devolução',
      actor: 'seller JWT',
      pre: 'pedido_devolucao',
      repro: 'PATCH concluido JWT=seller',
      expected: '403 order_return_in_progress / cannot_mark_concluido',
      obtained: sellerConRet.brief,
    );
  } else {
    c.block('AX6.seller-concluido-return', 'AX6', 'seller concluido return',
        sellerConRet.status);
  }

  // Cancel pós-pago — se APPLIED é P0; 200 silencioso = exact AL5 não HOLD
  final can = await c.patchOrder(pRet.oid, {'status': 'cancelado'}, jwt: c.buyerJwt);
  final oCan = await c.orderRow(pRet.oid);
  c.note('ax6.cancel', 'cancel durante return', {
    'http': can.status,
    'db': oCan?['status'],
  }, lens: 'AX6');
  if (can.status == 200 && oCan?['status'] == 'cancelado') {
    c.hold(
      id: 'AX6-cancel-applied-during-return',
      lens: 'AX6',
      severity: 'P0',
      title: 'Buyer cancelou encomenda em devolução (estado mudou)',
      actor: 'buyer JWT',
      pre: 'pedido_devolucao pago',
      repro: 'PATCH cancelado',
      expected: '403 order_cancel_denied_post_pay',
      obtained: {'http': can.status, 'db': oCan?['status']},
    );
  } else if (can.status == 200) {
    c.note('ax6.cancel.silent200', '200 sem mudar (classe AL5) — não HOLD',
        {'db': oCan?['status']},
        lens: 'AX6');
  } else {
    c.block('AX6.cancel', 'AX6', 'cancel 4xx', can.status);
  }

  // ===========================================================================
  // AX5 — status regression + shipped_at JWT / service_role observação
  // ===========================================================================
  final pShip = await mustPay('AX5');
  final env = await c.patchOrder(pShip.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  var oShip = await c.orderRow(pShip.oid);
  c.note('ax5.enviado', 'seller enviado', {
    'hop': env.brief,
    'shipped_at': oShip?['shipped_at'],
  }, lens: 'AX5');

  // unship — ANAS 403 (não HOLD exact AR5 silent 200)
  final unship = await c.patchOrder(
    pShip.oid,
    {'shipped_at': null},
    jwt: c.sellerJwt,
  );
  final oUn = await c.orderRow(pShip.oid);
  c.note('ax5.unship', 'PATCH shipped_at=null', {
    'http': unship.status,
    'raw': clip(unship.body, 180),
    'db': oUn?['shipped_at'],
  }, lens: 'AX5');
  if (unship.ok && oUn?['shipped_at'] == null) {
    c.hold(
      id: 'AX5-unship-applied',
      lens: 'AX5',
      severity: 'P1',
      title: 'Unship persistiu (ANAS immutable falhou)',
      actor: 'seller JWT',
      pre: 'enviado com shipped_at',
      repro: 'PATCH shipped_at=null',
      expected: '403 order_shipped_at_immutable',
      obtained: {'http': unship.status, 'db': oUn?['shipped_at']},
    );
  } else if (unship.status == 200 && oUn?['shipped_at'] != null) {
    c.note('ax5.unship.silent200', '200 representação inalterada (exact AR5) — não HOLD',
        unship.status,
        lens: 'AX5');
  } else {
    c.block('AX5.unship', 'AX5', 'unship 4xx/immutable', unship.status);
  }

  // status regression pago/enviado → pendente
  final regress = await c.patchOrder(
    pShip.oid,
    {'status': 'pendente'},
    jwt: c.buyerJwt,
  );
  final oReg = await c.orderRow(pShip.oid);
  c.note('ax5.regress', 'buyer PATCH pendente após enviado', {
    'http': regress.status,
    'db': oReg?['status'],
  }, lens: 'AX5');
  if (regress.ok && oReg?['status'] == 'pendente') {
    c.hold(
      id: 'AX5-status-regression',
      lens: 'AX5',
      severity: 'P1',
      title: 'Buyer reverteu enviado→pendente',
      actor: 'buyer JWT',
      pre: 'enviado + shipped_at + captura',
      repro: 'PATCH status=pendente',
      expected: '403 order_status_regression_denied',
      obtained: {'http': regress.status, 'db': oReg?['status']},
    );
  } else {
    c.block('AX5.regress', 'AX5', 'regression recusada', {
      'http': regress.status,
      'db': oReg?['status'],
    });
  }

  // shipped_at backdate no mesmo hop enviado (trigger skip)
  final pBack = await mustPay('AX5');
  final past = DateTime.utc(2020, 1, 2).toIso8601String();
  final envBack = await c.patchOrder(
    pBack.oid,
    {'status': 'enviado', 'shipped_at': past},
    jwt: c.sellerJwt,
  );
  final oBack = await c.orderRow(pBack.oid);
  c.note('ax5.shipped_at.backdate', 'enviado + shipped_at 2020', {
    'hop': envBack.brief,
    'shipped_at': oBack?['shipped_at'],
  }, lens: 'AX5');
  final sa = '${oBack?['shipped_at'] ?? ''}';
  if (envBack.ok && sa.startsWith('2020-01')) {
    c.hold(
      id: 'AX5-shipped-at-backdate-on-enviado',
      lens: 'AX5',
      severity: 'P2',
      title: 'Seller selou shipped_at em 2020 ao marcar enviado',
      actor: 'seller JWT',
      pre: 'pago; trigger permite set no hop enviado',
      repro: 'PATCH status=enviado, shipped_at=2020-01-02',
      expected: 'shipped_at := now() (ignorar cliente)',
      obtained: {'hop': envBack.brief, 'shipped_at': sa},
    );
  } else {
    c.block('AX5.backdate-ship', 'AX5', 'shipped_at não recuou a 2020', {
      'http': envBack.status,
      'sa': sa,
    });
  }

  // service_role shipped_at — observação (não actor exploit)
  final pSvc = await mustPay('AX5');
  await c.patchOrder(pSvc.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final svcUnship = await c.patchOrder(
    pSvc.oid,
    {'shipped_at': null},
    service: true,
  );
  final oSvc = await c.orderRow(pSvc.oid);
  c.note('ax5.svc.unship', 'service_role unship (fixture/observe)', {
    'http': svcUnship.status,
    'db': oSvc?['shipped_at'],
    'status': oSvc?['status'],
  }, lens: 'AX5');
  if (svcUnship.ok && oSvc?['shipped_at'] == null) {
    c.note(
      'ax5.svc.unship.leaks',
      'service_role apaga shipped_at — trigger só autentica JWT. Não é actor JWT.',
      {'status': oSvc?['status'], 'shipped_at': oSvc?['shipped_at']},
      lens: 'AX5',
    );
    // Refund gate uses shipped_at null + status enviado → still blocked by status
    final rfSvc = await c.refund(pSvc.oid);
    c.note('ax5.svc.then.refund', 'refund após unship service_role', rfSvc.brief,
        lens: 'AX5');
    if (refundSucceeded(rfSvc)) {
      c.hold(
        id: 'AX5-svc-unship-opens-refund',
        lens: 'AX5',
        severity: 'P2',
        title:
            'Após unship service_role, seller JWT refund-order passou (status ainda enviado)',
        actor: 'service_role fixture + seller JWT refund',
        pre: 'enviado; shipped_at limpo só com service_role',
        repro: 'PATCH shipped_at=null service_role; POST refund-order JWT',
        expected: 'refund ainda bloqueado por status enviado',
        obtained: {
          'unship': svcUnship.brief,
          'refund': rfSvc.brief,
          'order': oSvc,
        },
      );
    }
  }

  // ===========================================================================
  // AX3 — release exige envio ou mão; parcial
  // ===========================================================================
  final pRel = await mustPay('AX3');
  // CTT default — concluido from pago should fail (not mão, no shipped)
  final concNoShip = await c.patchOrder(
    pRel.oid,
    {'status': 'concluido'},
    jwt: c.buyerJwt,
  );
  final relNoShip = await c.release(pRel.oid);
  final oRel0 = await c.orderRow(pRel.oid);
  c.note('ax3.concluido.no-ship', 'buyer concluido sem envio (não mão)', {
    'hop': concNoShip.brief,
    'release': relNoShip.brief,
    'status': oRel0?['status'],
    'shipped_at': oRel0?['shipped_at'],
  }, lens: 'AX3');
  if ((relNoShip.json == true || relNoShip.body == 'true') &&
      oRel0?['shipped_at'] == null) {
    c.hold(
      id: 'AX3-release-without-ship',
      lens: 'AX3',
      severity: 'P1',
      title: 'Release sem shipped_at nem mão',
      actor: 'buyer JWT',
      pre: 'pago CTT; shipped_at null',
      repro: 'PATCH concluido; rpc release',
      expected: 'concluido 403 / release false',
      obtained: {
        'hop': concNoShip.brief,
        'release': relNoShip.brief,
        'status': oRel0?['status'],
      },
    );
  } else {
    c.block('AX3.release-no-ship', 'AX3', 'release sem envio recusado', {
      'hop': concNoShip.status,
      'release': relNoShip.brief,
      'status': oRel0?['status'],
    });
  }

  // Happy path mão → concluido → release (prova Stripe TEST + release)
  final pMao = await mustPay('AX3');
  await c.markMao(pMao.oid);
  final wBeforeRel = await c.wallets();
  final concMao = await c.patchOrder(pMao.oid, {'status': 'concluido'},
      jwt: c.buyerJwt);
  final relMao = await c.release(pMao.oid);
  final relMao2 = await c.release(pMao.oid);
  final wAfterRel = await c.wallets();
  final oMao = await c.orderRow(pMao.oid);
  final dSellerRel =
      (wAfterRel['seller'] ?? 0) - (wBeforeRel['seller'] ?? 0);
  final dBuyerRel = (wAfterRel['buyer'] ?? 0) - (wBeforeRel['buyer'] ?? 0);
  c.note('ax3.happy.release', 'mão + concluido + release ×2', {
    'conc': concMao.brief,
    'rel1': relMao.brief,
    'rel2': relMao2.brief,
    'dSeller': dSellerRel,
    'dBuyer': dBuyerRel,
    'released_at': oMao?['wallet_release_processed_at'],
  }, lens: 'AX3');
  if (relMao2.json == true || relMao2.body == 'true') {
    c.hold(
      id: 'AX3-double-release',
      lens: 'AX3',
      severity: 'P0',
      title: '2.ª release devolveu true (possível mint)',
      actor: 'buyer JWT',
      pre: 'já released',
      repro: 'rpc release ×2',
      expected: '2.ª false',
      obtained: {'r1': relMao.brief, 'r2': relMao2.brief, 'dSeller': dSellerRel},
    );
  } else {
    c.block('AX3.double-release', 'AX3', '2.ª release false', relMao2);
  }

  // Refund após release
  final rfAfter = await c.refund(pMao.oid, extra: {
    'amount': 99999,
    'reverse_transfer': true,
  });
  final piRf = oMao?['stripe_payment_intent_id']?.toString();
  Map<String, dynamic>? stripeRf;
  if (piRf != null && piRf.isNotEmpty) {
    final lr = await c.listStripeRefunds(piRf);
    stripeRf = {'brief': lr.brief, 'json': lr.map};
  }
  c.note('ax5.refund.after-release', 'refund-order após release', {
    'hit': rfAfter.brief,
    'stripe': stripeRf,
  }, lens: 'AX5');
  if (refundSucceeded(rfAfter)) {
    c.hold(
      id: 'AX5-refund-after-release',
      lens: 'AX5',
      severity: 'P0',
      title: 'Seller refund-order após release (possível líquido)',
      actor: 'seller JWT',
      pre: 'concluido + wallet_release_processed_at',
      repro: 'POST refund-order amount=99999 reverse_transfer',
      expected: '403 order_refund_blocked_status',
      obtained: {'hit': rfAfter.brief, 'stripe': stripeRf},
    );
  } else {
    c.block('AX5.refund-after-release', 'AX5', 'refund pós-release 403',
        rfAfter);
  }

  // Buyer / B2 refund alheio
  final pPay = await mustPay('AX6');
  final bRf = await c.refund(pPay.oid, jwt: c.buyerJwt);
  final b2Rf = await c.refund(pPay.oid, jwt: c.buyer2Jwt);
  c.note('ax6.buyer.refund', 'buyer/B2 refund-order', {
    'b': bRf.brief,
    'b2': b2Rf.brief,
  }, lens: 'AX6');
  if (refundSucceeded(bRf) || refundSucceeded(b2Rf)) {
    c.hold(
      id: 'AX6-buyer-refund-order',
      lens: 'AX6',
      severity: 'P0',
      title: 'Buyer forçou refund-order',
      actor: 'buyer/B2 JWT',
      pre: 'pago alheio',
      repro: 'POST refund-order',
      expected: '403',
      obtained: {'b': bRf.brief, 'b2': b2Rf.brief},
    );
  } else {
    c.block('AX6.buyer-refund', 'AX6', 'buyer refund 403', {
      'b': bRf.status,
      'b2': b2Rf.status,
    });
  }

  // Partial > captura via process_partial
  final part = await c.rpc('batata_process_partial_refund_dispute', {
    'p_order_id': pPay.oid,
    'p_refund_percent': 200,
  }, jwt: c.sellerJwt);
  c.note('ax5.partial200', 'process_partial 200%', part.brief, lens: 'AX5');
  if (!rpcDenied(part) &&
      part.ok &&
      (part.body == 'true' || part.body.contains('"ok":true'))) {
    c.hold(
      id: 'AX5-partial-over-capture',
      lens: 'AX5',
      severity: 'P0',
      title: 'process_partial 200% executou',
      actor: 'seller JWT',
      pre: 'pago sem disputa oferta',
      repro: 'rpc p_refund_percent=200',
      expected: '403 / false / requires_stripe',
      obtained: part.brief,
    );
  } else {
    c.block('AX5.partial200', 'AX5', 'parcial 200% recusado', part);
  }

  // Happy refund em pago (prova fluxo Stripe TEST refund)
  final pOkRf = await mustPay('AX5');
  final wRf0 = await c.wallets();
  final okRf = await c.refund(pOkRf.oid);
  final oOkRf = await c.orderRow(pOkRf.oid);
  final wRf1 = await c.wallets();
  c.note('ax5.refund.pago', 'refund-order em pago', {
    'hit': okRf.brief,
    'status': oOkRf?['status'],
    'refund_id': oOkRf?['stripe_refund_id'],
    'dBuyer': (wRf1['buyer'] ?? 0) - (wRf0['buyer'] ?? 0),
    'dSeller': (wRf1['seller'] ?? 0) - (wRf0['seller'] ?? 0),
  }, lens: 'AX5');

  // Refund em ciclo devolução (antes de devolvida)
  final pDev = await mustPay('AX5');
  await c.patchOrder(pDev.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(pDev.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  await c.insertDispute(pDev.oid);
  await c.patchOrder(pDev.oid, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt);
  final rfDev = await c.refund(pDev.oid);
  final oDev = await c.orderRow(pDev.oid);
  c.note('ax5.refund.during-return', 'refund em pedido_devolucao', {
    'hit': rfDev.brief,
    'status': oDev?['status'],
  }, lens: 'AX5');
  if (refundSucceeded(rfDev)) {
    c.hold(
      id: 'AX5-refund-during-return-fsm',
      lens: 'AX5',
      severity: 'P1',
      title: 'Seller refund-order em pedido_devolucao',
      actor: 'seller JWT',
      pre: 'FSM return sem devolvida',
      repro: 'POST refund-order',
      expected: '403 order_refund_blocked_status',
      obtained: {'hit': rfDev.brief, 'status': oDev?['status']},
    );
  } else {
    c.block('AX5.refund-return', 'AX5', 'refund during return 403', rfDev);
  }

  // Skip hop devolvida (ANAS AS3)
  final skipDv = await c.patchOrder(pDev.oid, {'status': 'devolvida'},
      jwt: c.sellerJwt);
  final oSkip = await c.orderRow(pDev.oid);
  c.note('ax6.skip.devolvida', 'seller pedido_devolucao→devolvida', {
    'hop': skipDv.brief,
    'status': oSkip?['status'],
  }, lens: 'AX6');
  if (skipDv.ok && oSkip?['status'] == 'devolvida') {
    c.hold(
      id: 'AX6-skip-to-devolvida',
      lens: 'AX6',
      severity: 'P2',
      title: 'Seller saltou hops até devolvida',
      actor: 'seller JWT',
      pre: 'pedido_devolucao',
      repro: 'PATCH devolvida',
      expected: '403 order_devolvida_denied',
      obtained: skipDv.brief,
    );
  } else {
    c.block('AX6.skip-devolvida', 'AX6', 'skip devolvida recusado', skipDv);
  }

  // Race refund ∥ concluido (mão)
  final pRace = await mustPay('AX7');
  await c.markMao(pRace.oid);
  final wRace0 = await c.wallets();
  final raced = await parallel([
    c.refund(pRace.oid),
    c.patchOrder(pRace.oid, {'status': 'concluido'}, jwt: c.buyerJwt),
  ]);
  final oRace = await c.orderRow(pRace.oid);
  final relRace = await c.release(pRace.oid);
  final wRace1 = await c.wallets();
  c.note('ax7.race', 'refund ∥ concluido', {
    'refund': raced[0].brief,
    'concluido': raced[1].brief,
    'order': oRace,
    'release': relRace.brief,
    'dBuyer': (wRace1['buyer'] ?? 0) - (wRace0['buyer'] ?? 0),
    'dSeller': (wRace1['seller'] ?? 0) - (wRace0['seller'] ?? 0),
  }, lens: 'AX7');
  final bothMoney = refundSucceeded(raced[0]) &&
      (relRace.json == true || relRace.body == 'true');
  if (bothMoney) {
    c.hold(
      id: 'AX7-refund-and-release-same-order',
      lens: 'AX7',
      severity: 'P0',
      title: 'Refund Stripe e release wallet no mesmo pedido (líquido)',
      actor: 'seller refund + buyer concluido/release',
      pre: 'mão pago race',
      repro: 'refund-order ∥ PATCH concluido; rpc release',
      expected: 'um dos dois: refund XOR release',
      obtained: {
        'refund': raced[0].brief,
        'release': relRace.brief,
        'status': oRace?['status'],
        'refund_id': oRace?['stripe_refund_id'],
        'released': oRace?['wallet_release_processed_at'],
      },
    );
  } else {
    c.block('AX7.race', 'AX7', 'sem coexistência refund+release', {
      'rf': raced[0].status,
      'rel': relRace.brief,
      'status': oRace?['status'],
    });
  }

  // Payout 100¢ pós-release (não é mint clássico — levantamento de saldo real)
  final po = await c.payout(amountCents: 100, key: '${prefix}_postrel8');
  c.note('ax7.payout.after-release', 'Transfer 100¢ pós-release', po.brief,
      lens: 'AX7');

  final wEnd = await c.wallets();
  c.note('p3.wallets.end', 'caixa final', {
    'w0': w0,
    'wEnd': wEnd,
    'dBuyer': (wEnd['buyer'] ?? 0) - (w0['buyer'] ?? 0),
    'dSeller': (wEnd['seller'] ?? 0) - (w0['seller'] ?? 0),
  }, lens: 'AX7');

  await c.dumpAll('pass3.json');
  stdout.writeln(
      'PASS3 done findings=${c.findings.length} blocked=${c.blocked.length} notes=${c.notes.length}');
}
