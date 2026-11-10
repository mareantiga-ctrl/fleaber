/// RED TEAM CEGO AS — pass 2. Aprofundar P1 AS2/AS5/AS7 + composição caixa. Não corrige.
import 'dart:io';
import '_rtas.dart';

Future<void> main() async {
  final c = Rtas.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  Future<({String oid, String pid, String? pi})> mustPay(String lens) async {
    final paid = await c.payToPago(lens: lens, initialQty: 1);
    if (paid == null) throw StateError('setup_paid_order $lens');
    return paid;
  }

  Future<Map<String, dynamic>> books(String oid, String pid) async => {
        'order': await c.orderRow(oid),
        'product': await c.productRow(pid),
        'wallets': await c.wallets(),
      };

  const png = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
    0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
  ];

  // -----------------------------------------------------------------------
  // AS2+AS5+AS8 — seller pago→entregue→concluido + release wallet
  // -----------------------------------------------------------------------
  final pSkip = await mustPay('AS8');
  final w0 = await c.wallets();
  final hEnt = await c.patchOrder(
    pSkip.oid,
    {'status': 'entregue'},
    jwt: c.sellerJwt,
  );
  var oSkip = await c.orderRow(pSkip.oid);
  c.note('AS2.pago_entregue', 'replay seller pago→entregue', {
    'hit': hEnt.brief,
    'order': oSkip,
  }, lens: 'AS2');

  final dSkip = await c.insertDispute(orderId: pSkip.oid);
  c.note('AS1.dispute_after_fake_entregue', 'disputa após entregue sem enviado',
      {'hit': dSkip.brief, 'shipped_at': oSkip?['shipped_at']},
      lens: 'AS1');

  final hCon = await c.patchOrder(
    pSkip.oid,
    {'status': 'concluido'},
    jwt: c.sellerJwt,
  );
  oSkip = await c.orderRow(pSkip.oid);
  final relSkip = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': pSkip.oid},
    jwt: c.buyerJwt,
  );
  final wSkip = await c.wallets();
  c.note('AS8.skip_ship_concluido_release', 'caixa após salto', {
    'concluido': hCon.brief,
    'order': oSkip,
    'release': relSkip.brief,
    'w0': w0,
    'w1': wSkip,
    'delta_seller':
        (wSkip['seller'] ?? 0) - (w0['seller'] ?? 0),
    'dispute': dSkip.brief,
  }, lens: 'AS8');

  if (hEnt.ok && oSkip?['shipped_at'] == null && dSkip.ok) {
    c.hold(
      id: 'AS2.dispute_without_ship',
      lens: 'AS2',
      severity: 'P1',
      title:
          'Seller pago→entregue (shipped_at null) abre a RLS de disputa sem envio',
      actor: 'seller JWT + buyer JWT',
      pre: 'pago capturado, nunca enviado',
      repro: 'PATCH entregue JWT=seller; POST order_disputes JWT=buyer',
      expected: 'entregue exige enviado; disputa só após envio real',
      obtained: {
        'entregue': hEnt.brief,
        'dispute': dSkip.brief,
        'shipped_at': oSkip?['shipped_at'],
        'status': oSkip?['status'],
      },
    );
  }

  final deltaS = ((wSkip['seller'] ?? 0) - (w0['seller'] ?? 0)).toDouble();
  if ((relSkip.json == true || relSkip.body == 'true') && deltaS > 0) {
    c.hold(
      id: 'AS8.release_without_ship',
      lens: 'AS8',
      severity: 'P0',
      title: 'Release wallet seller sem enviado (após salto entregue/concluido)',
      actor: 'buyer JWT release',
      pre: 'seller marcou entregue/concluido a partir de pago',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false — sem shipped_at / sem receção buyer',
      obtained: {
        'release': relSkip.brief,
        'delta_seller': deltaS,
        'order': oSkip,
      },
    );
  } else {
    c.block('AS8.release_without_ship', 'AS8', 'release sem enviado', {
      'release': relSkip.brief,
      'delta_seller': deltaS,
      'status': oSkip?['status'],
    });
  }

  // Seller enviado→concluido + buyer release (sem disputa)
  final pForce = await mustPay('AS5');
  final wF0 = await c.wallets();
  await c.patchOrder(pForce.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final forceCon = await c.patchOrder(
    pForce.oid,
    {'status': 'concluido'},
    jwt: c.sellerJwt,
  );
  final oForce = await c.orderRow(pForce.oid);
  final relForce = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': pForce.oid},
    jwt: c.buyerJwt,
  );
  final wF1 = await c.wallets();
  final dF = await c.insertDispute(orderId: pForce.oid);
  c.note('AS5.seller_concluido_books', 'enviado→concluido seller + release', {
    'hop': forceCon.brief,
    'order': oForce,
    'release': relForce.brief,
    'w0': wF0,
    'w1': wF1,
    'delta_seller': (wF1['seller'] ?? 0) - (wF0['seller'] ?? 0),
    'dispute_after': dF.brief,
  }, lens: 'AS5');

  final deltaForce =
      ((wF1['seller'] ?? 0) - (wF0['seller'] ?? 0)).toDouble();
  if (forceCon.ok &&
      oForce?['status'] == 'concluido' &&
      (relForce.json == true || relForce.body == 'true') &&
      deltaForce > 0) {
    c.hold(
      id: 'AS5.seller_force_concluido_pays_out',
      lens: 'AS5',
      severity: 'P1',
      title:
          'Seller marca concluido a partir de enviado e o buyer RPC liberta a carteira (sem confirmar receção na UI)',
      actor: 'seller JWT hop + buyer JWT release (API)',
      pre: 'enviado, buyer nunca PATCH entregue/concluido',
      repro:
          'PATCH concluido JWT=seller; rpc batata_release_seller_wallet_for_order JWT=buyer',
      expected:
          'seller não marca concluido; release só após buyer confirmar receção',
      obtained: {
        'hop': forceCon.brief,
        'release': relForce.brief,
        'delta_seller_eur': deltaForce,
        'completed_at': oForce?['completed_at'],
        'shipped_at': oForce?['shipped_at'],
      },
    );
  } else if (forceCon.ok && oForce?['status'] == 'concluido') {
    c.hold(
      id: 'AS5.seller_force_concluido_state',
      lens: 'AS5',
      severity: 'P1',
      title:
          'Seller PATCH concluido a partir de enviado persiste (relógio completed_at / auto-feedback 48h)',
      actor: 'seller JWT',
      pre: 'enviado capturado',
      repro: 'PATCH status=concluido',
      expected: '42501 — só comprador',
      obtained: {
        'hop': forceCon.brief,
        'order': oForce,
        'release': relForce.brief,
        'delta_seller': deltaForce,
        'dispute': dF.brief,
      },
    );
  }

  // -----------------------------------------------------------------------
  // AS7 — leak raso: S2 lê prova rasa de B1 feita no contexto S1
  // -----------------------------------------------------------------------
  final shallow =
      'object/fleaber_private/order_proofs/${c.buyerId}/rtas-p2-shallow.png';
  final up = await c.storage(
    'POST',
    shallow,
    jwt: c.buyerJwt,
    bytes: png,
    contentType: 'image/png',
  );
  final s1 = await c.storage('GET', shallow, jwt: c.sellerJwt);
  final s2 = await c.storage('GET', shallow, jwt: c.seller2Jwt);
  final b2 = await c.storage('GET', shallow, jwt: c.buyer2Jwt);
  c.note('AS7.shallow_cross', 'GET raso S1/S2/B2', {
    'upload': up.brief,
    's1': s1.brief,
    's2': s2.brief,
    'b2': b2.brief,
  }, lens: 'AS7');
  if (s2.ok) {
    c.hold(
      id: 'AS7.s2_reads_b1_shallow_s1_proof',
      lens: 'AS7',
      severity: 'P1',
      title:
          'S2 lê order_proofs raso de B1 (ficheiro do contexto S1) só porque S2 também tem venda com B1',
      actor: 'seller2 JWT',
      pre: 'B1–S2 têm order; ficheiro order_proofs/{B1}/rtas-p2-shallow.png',
      repro: 'GET storage JWT=S2',
      expected: '403',
      obtained: {'s1': s1.brief, 's2': s2.brief, 'b2': b2.brief},
    );
  } else if (s1.ok) {
    c.block('AS7.s2_blocked_s1_ok', 'AS7', 'S2 403 mas S1 200 (replay leak S1)',
        {'s1': s1.brief, 's2': s2.brief});
  } else {
    c.block('AS7.shallow_closed', 'AS7', 'shallow leak fechado?', {
      's1': s1.brief,
      's2': s2.brief,
    });
  }

  // XSS prefix em disputa fresca
  final pX = await mustPay('AS7');
  await c.patchOrder(pX.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(pX.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  final xssUrl =
      'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/x" onerror="alert(1)';
  final xss = await c.insertDispute(orderId: pX.oid, photos: [xssUrl]);
  if (xss.ok) {
    c.hold(
      id: 'AS7.proof_xss_prefix',
      lens: 'AS7',
      severity: 'P2',
      title: 'INSERT disputa proof_photos prefixo supabase + breakout HTML',
      actor: 'buyer JWT',
      pre: 'entregue, disputa nova',
      repro: 'POST proof_photos com \\" onerror=',
      expected: 'dispute_proof_url_denied',
      obtained: xss.brief,
    );
  } else {
    c.block('AS7.proof_xss_prefix', 'AS7', 'XSS insert denied', xss);
  }

  // -----------------------------------------------------------------------
  // AS3+AS4+AS8 — refund devolvida: qty, 2.º checkout, wallets
  // -----------------------------------------------------------------------
  final pR = await mustPay('AS8');
  final wR0 = await c.wallets();
  await c.patchOrder(pR.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(pR.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  await c.insertDispute(orderId: pR.oid);
  await c.patchOrder(pR.oid, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt);
  await c.patchOrder(pR.oid, {'status': 'em_devolucao'}, jwt: c.sellerJwt);
  final refMid = await c.refund(pR.oid, jwt: c.sellerJwt);
  if (refMid.ok && refMid.map?['ok'] == true) {
    c.hold(
      id: 'AS4.refund_during_em_devolucao',
      lens: 'AS4',
      severity: 'P1',
      title: 'refund-order durante em_devolucao',
      actor: 'seller JWT',
      pre: 'em_devolucao, captura viva',
      repro: 'POST refund-order',
      expected: '403 order_refund_blocked_status',
      obtained: refMid.brief,
    );
  } else {
    c.block('AS4.refund_during_em_devolucao', 'AS4', 'refund em_devolucao',
        refMid);
  }
  await c.patchOrder(pR.oid, {'status': 'devolucao_entregue'}, jwt: c.sellerJwt);
  await c.patchOrder(pR.oid, {'status': 'devolvida'}, jwt: c.sellerJwt);
  final before = await books(pR.oid, pR.pid);
  final ref = await c.refund(pR.oid, jwt: c.sellerJwt);
  final after = await books(pR.oid, pR.pid);
  final avail = await c.rpc('batata_product_checkout_available', {
    'p_product_id': pR.pid,
    'p_exclude_order_id': pR.oid,
    'p_need_qty': 1,
  }, jwt: c.buyer2Jwt);

  String? oid2;
  final ins2 = await c.insertOrderHit(
    productId: pR.pid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    price: 5.0,
  );
  oid2 = ins2.firstId;
  HttpHit? chk2;
  if (oid2 != null) {
    chk2 = await c.checkout(
      orderId: oid2,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
      productId: pR.pid,
      seller: c.sellerId,
      amount: 5.9,
    );
  }
  c.note('AS8.refund_restore_second', 'contabilidade refund+2.º checkout', {
    'refund': ref.brief,
    'before': before,
    'after': after,
    'avail': avail.brief,
    'b2_order': ins2.brief,
    'b2_checkout': chk2?.brief,
    'w0': wR0,
    'w1': after['wallets'],
  }, lens: 'AS8');

  final qtyAfter = numOf((after['product'] as Map?)?['quantity']);
  final stAfter = (after['order'] as Map?)?['status'];
  if (ref.ok && ref.map?['ok'] != false) {
    if (stAfter == 'cancelado') {
      c.block('AS4.replay_cancelado', 'AS4', 'replay devolvida→cancelado',
          {'status': stAfter, 'qty': qtyAfter, 'refund': ref.brief});
    }
    if (qtyAfter != null && qtyAfter >= 2) {
      c.hold(
        id: 'AS3.double_restore',
        lens: 'AS3',
        severity: 'P1',
        title: 'qty≥2 após um refund de 1 unidade',
        actor: 'triggers',
        pre: 'stock 0 applied 1',
        repro: 'refund-order',
        expected: 'qty=1',
        obtained: after,
      );
    }
  }

  // Buyer recusada é design (comment D1) — não finding. Confirmar lockout 2.ª.
  final pLock = await mustPay('AS1');
  await c.patchOrder(pLock.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(pLock.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  final dLock = await c.insertDispute(orderId: pLock.oid);
  final did = dLock.firstId;
  if (did != null) {
    await c.rest('PATCH', 'order_disputes?id=eq.$did', jwt: c.buyerJwt, body: {
      'status': 'recusada',
    });
    final again = await c.insertDispute(orderId: pLock.oid, reason: 'em_falta');
    c.note('AS1.reopen_after_recusada', '2.ª disputa após recusada (design lock)',
        again.brief,
        lens: 'AS1');
    if (again.ok) {
      c.hold(
        id: 'AS1.reopen_after_recusada',
        lens: 'AS1',
        severity: 'P2',
        title: 'Buyer reabre disputa após recusada (quebra insert_once)',
        actor: 'buyer JWT',
        pre: 'disputa recusada',
        repro: 'POST 2.ª order_disputes',
        expected: 'dispute_already_exists_for_order',
        obtained: again.brief,
      );
    } else {
      c.block('AS1.reopen_after_recusada', 'AS1',
          'insert_once após recusada (design)', again);
    }
  }

  await c.dumpAll('pass2.json');
  stdout.writeln(
      'PASS2 done findings=${c.findings.length} blocked=${c.blocked.length}');
}
