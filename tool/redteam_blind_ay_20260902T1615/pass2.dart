/// RED TEAM CEGO AY — pass 2. Reprobe hops com orderRow válido. Não corrige.
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

String? st(Map<String, dynamic>? row) => row?['status']?.toString();

Future<void> main() async {
  final c = Rtay.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  Future<Map<String, dynamic>> books(String oid, String pid) async => {
        'order': await c.orderRow(oid),
        'product': await c.productRow(pid),
        'wallets': await c.wallets(),
        'stock': (await c.stockCheck(pid)).map,
      };

  Future<({String oid, String pid, String? pi})> mustPay(String lens) async {
    final paid = await c.payToPago(lens: lens, initialQty: 1);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    final row = await c.orderRow(paid.oid);
    if (st(row) != 'pago') {
      throw StateError('not pago ${paid.oid} ${st(row)}');
    }
    return paid;
  }

  bool releasedTrue(HttpHit h) => h.body == 'true' || h.json == true;

  // Sanity orderRow
  final sanity = await mustPay('AY1');
  c.note('P2.sanity', 'orderRow pago', await c.orderRow(sanity.oid), lens: 'AY1');

  // =========================================================================
  // Cadeia completa envio → disputa → devolução → refund (táctica 2)
  // =========================================================================
  final chain = await mustPay('AY3');
  final oid = chain.oid;
  final pid = chain.pid;
  final env = await c.patchOrder(oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  var row = await c.orderRow(oid);
  c.note('P2.env', 'enviado', {'hit': env.brief, 'st': st(row)}, lens: 'AY2');

  final ent = await c.patchOrder(oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  row = await c.orderRow(oid);
  c.note('P2.ent', 'entregue', {'hit': ent.brief, 'st': st(row)}, lens: 'AY2');

  final disp = await c.insertDispute(orderId: oid);
  final did = disp.firstId;
  c.note('P2.disp', 'disputa', disp.brief, lens: 'AY1');

  // Seller skip pedido_devolucao: entregue → em_devolucao
  final skipPed = await c.patchOrder(
    oid,
    {'status': 'em_devolucao'},
    jwt: c.sellerJwt,
  );
  row = await c.orderRow(oid);
  c.note('P2.skip_pedido', 'seller entregue→em_devolucao', {
    'hit': skipPed.brief,
    'st': st(row),
  }, lens: 'AY3');
  if (skipPed.ok && st(row) == 'em_devolucao') {
    c.hold(
      id: 'AY3.seller_em_devolucao_sem_pedido',
      lens: 'AY3',
      severity: 'P1',
      title: 'Seller força em_devolucao sem pedido_devolucao do comprador',
      actor: 'seller JWT',
      pre: 'entregue + disputa aberta, buyer nunca pediu devolução',
      repro: 'PATCH status=em_devolucao JWT=seller',
      expected: 'denied — hop só após pedido_devolucao',
      obtained: {'hit': skipPed.brief, 'status': st(row)},
    );
  } else {
    c.block('AY3.seller_em_devolucao_sem_pedido', 'AY3',
        'seller não salta pedido', {'hit': skipPed.brief, 'st': st(row)});
  }

  // Se o skip falhou, caminho feliz pedido_devolucao
  if (st(row) == 'entregue' || st(row) == 'concluido') {
    final ped = await c.patchOrder(
      oid,
      {'status': 'pedido_devolucao'},
      jwt: c.buyerJwt,
    );
    row = await c.orderRow(oid);
    c.note('P2.pedido', 'buyer pedido_devolucao', {
      'hit': ped.brief,
      'st': st(row),
    }, lens: 'AY3');
    await c.patchOrder(oid, {'status': 'em_devolucao'}, jwt: c.sellerJwt);
    row = await c.orderRow(oid);
  }

  // Seller skip em_devolucao → devolvida (ANAS)
  if (st(row) == 'em_devolucao') {
    final skipDev = await c.patchOrder(
      oid,
      {'status': 'devolvida'},
      jwt: c.sellerJwt,
    );
    final afterSkip = await c.orderRow(oid);
    if (skipDev.ok && st(afterSkip) == 'devolvida') {
      c.hold(
        id: 'AY3.regress_devolvida_skip_entregue_return',
        lens: 'AY3',
        severity: 'P1',
        title: 'REGRESSÃO ANAS: devolvida a partir de em_devolucao',
        actor: 'seller JWT',
        pre: 'em_devolucao',
        repro: 'PATCH status=devolvida',
        expected: 'order_devolvida_denied',
        obtained: {'hit': skipDev.brief, 'st': st(afterSkip)},
      );
    } else {
      c.block('AY3.anas_devolvida_hop', 'AY3',
          'devolvida exige devolucao_entregue', skipDev);
    }
    await c.patchOrder(
      oid,
      {'status': 'devolucao_entregue'},
      jwt: c.sellerJwt,
    );
    row = await c.orderRow(oid);
  }

  if (st(row) == 'devolucao_entregue') {
    final toDev =
        await c.patchOrder(oid, {'status': 'devolvida'}, jwt: c.sellerJwt);
    row = await c.orderRow(oid);
    c.note('P2.devolvida', 'hop devolucao_entregue→devolvida', {
      'hit': toDev.brief,
      'st': st(row),
    }, lens: 'AY3');
  }

  var bDev = await books(oid, pid);
  c.note('P2.books_devolvida', 'caixa em devolvida', bDev, lens: 'AY8');
  final qtyDev = (bDev['product'] as Map?)?['quantity'];
  final applied = (bDev['order'] as Map?)?['stock_units_applied'];
  final refId = (bDev['order'] as Map?)?['stripe_refund_id'];
  if (st(row) == 'devolvida' && '${refId ?? ''}'.isEmpty) {
    if (qtyDev == 1 || applied == null) {
      c.hold(
        id: 'AY3.am3_regress_stock',
        lens: 'AY3',
        severity: 'P1',
        title: 'REGRESSÃO AM3: devolvida restaurou stock sem refund',
        actor: 'triggers',
        pre: 'captura viva',
        repro: 'hops até devolvida',
        expected: 'qty 0, applied set',
        obtained: {'qty': qtyDev, 'applied': applied},
      );
    } else {
      c.block('AY3.am3_verify', 'AY3', 'stock preso', {
        'qty': qtyDev,
        'applied': applied,
      });
    }
  }

  final avail = await c.stockCheck(pid);
  final b2o = await c.insertOrderHit(
    productId: pid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    price: 5.0,
  );
  final chk = await c.checkout(
    orderId: b2o.firstId ?? oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    productId: pid,
    seller: c.sellerId,
    amount: 5.9,
  );
  c.note('P2.checkout_viva', 'B2 session com captura viva', {
    'avail': avail.brief,
    'hold': b2o.brief,
    'chk': chk.brief,
    'qty': qtyDev,
  }, lens: 'AY8');
  if (chk.ok &&
      chk.sessionId != null &&
      st(row) == 'devolvida' &&
      qtyDev == 0) {
    c.hold(
      id: 'AY8.second_session_captura_viva',
      lens: 'AY8',
      severity: 'P1',
      title: '2.ª Session no SKU com 1.ª captura viva e qty 0',
      actor: 'buyer2 JWT',
      pre: 'devolvida sem refund',
      repro: 'create-payment-intent B2',
      expected: 'recusa available=0',
      obtained: chk.brief,
    );
  }

  // refund-order só se devolvida
  if (st(row) == 'devolvida') {
    final ref1 = await c.refund(oid, jwt: c.sellerJwt);
    final after1 = await books(oid, pid);
    final st1 = st(after1['order'] as Map<String, dynamic>?);
    final qty1 = (after1['product'] as Map?)?['quantity'];
    c.note('P2.refund1', 'refund-order em devolvida', {
      'hit': ref1.brief,
      'st': st1,
      'qty': qty1,
      'rid': (after1['order'] as Map?)?['stripe_refund_id'],
    }, lens: 'AY4');
    final ok = ref1.ok && ref1.map?['ok'] != false;
    if (!ok && ref1.body.contains('order_refund_blocked_shipped')) {
      c.hold(
        id: 'AY4.am4_regress',
        lens: 'AY4',
        severity: 'P1',
        title: 'REGRESSÃO AM4: refund-order em devolvida blocked shipped',
        actor: 'seller JWT',
        pre: 'status=devolvida',
        repro: 'POST refund-order',
        expected: 'ok terminal',
        obtained: ref1.brief,
      );
    } else if (ok) {
      c.block('AY4.am4_verify', 'AY4', 'refund em devolvida ok', ref1);
      if (st1 == 'cancelado') {
        c.hold(
          id: 'AY4.regress_cancelado',
          lens: 'AY4',
          severity: 'P2',
          title: 'REGRESSÃO ANAS: refund reescreve devolvida→cancelado',
          actor: 'Edge',
          pre: 'devolvida',
          repro: 'POST refund-order',
          expected: 'permanece devolvida',
          obtained: {'hit': ref1.brief, 'st': st1},
        );
      }
      if (qty1 is num && qty1 >= 2) {
        c.hold(
          id: 'AY3.double_stock',
          lens: 'AY3',
          severity: 'P1',
          title: 'Refund qty≥2',
          actor: 'triggers',
          pre: '1 unidade',
          repro: 'refund-order',
          expected: 'qty=1',
          obtained: after1,
        );
      }
    } else {
      c.note('P2.refund1_fail', 'refund não ok', ref1.brief, lens: 'AY4');
    }

    final ref2 = await c.refund(oid, jwt: c.sellerJwt);
    final after2 = await books(oid, pid);
    final qty2 = (after2['product'] as Map?)?['quantity'];
    c.note('P2.refund2', 'refund duplo', {
      'hit': ref2.brief,
      'qty': qty2,
      'st': st(after2['order'] as Map<String, dynamic>?),
    }, lens: 'AY4');
    if (qty1 is num && qty2 is num && qty2 > qty1) {
      c.hold(
        id: 'AY4.double_refund_stock',
        lens: 'AY4',
        severity: 'P1',
        title: '2.º refund-order incrementou stock',
        actor: 'Edge ×2',
        pre: 'já reembolsado',
        repro: 'POST refund-order 2×',
        expected: 'idempotente',
        obtained: {'q1': qty1, 'q2': qty2, 'hit': ref2.brief},
      );
    } else {
      c.block('AY4.double_refund_idempotent', 'AY4', '2.º refund idempotente',
          ref2);
    }
  } else {
    c.note('P2.no_devolvida', 'não chegou a devolvida', st(row), lens: 'AY3');
  }

  // =========================================================================
  // Fresh: seller entregue→devolucao_entregue directo
  // =========================================================================
  final pSkip = await mustPay('AY3');
  await c.patchOrder(pSkip.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(pSkip.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  final dSkip = await c.insertDispute(orderId: pSkip.oid);
  final hopEntregue = await c.patchOrder(
    pSkip.oid,
    {'status': 'devolucao_entregue'},
    jwt: c.sellerJwt,
  );
  final stSkip = st(await c.orderRow(pSkip.oid));
  c.note('P2.skip_to_dev_entregue', 'entregue→devolucao_entregue', {
    'disp': dSkip.brief,
    'hit': hopEntregue.brief,
    'st': stSkip,
  }, lens: 'AY3');
  if (hopEntregue.ok && stSkip == 'devolucao_entregue') {
    c.hold(
      id: 'AY3.seller_skip_to_devolucao_entregue',
      lens: 'AY3',
      severity: 'P1',
      title:
          'Seller salta pedido_devolucao e em_devolucao: entregue→devolucao_entregue',
      actor: 'seller JWT',
      pre: 'entregue + disputa',
      repro: 'PATCH status=devolucao_entregue',
      expected: 'cadeia pedido→em_devolucao obrigatória',
      obtained: {'hit': hopEntregue.brief, 'st': stSkip},
    );
    final toDev2 = await c.patchOrder(
      pSkip.oid,
      {'status': 'devolvida'},
      jwt: c.sellerJwt,
    );
    final stDev2 = st(await c.orderRow(pSkip.oid));
    if (toDev2.ok && stDev2 == 'devolvida') {
      c.note('P2.skip_then_devolvida', 'completa atalho até devolvida', {
        'hit': toDev2.brief,
        'st': stDev2,
      }, lens: 'AY3');
    }
  } else {
    c.block('AY3.seller_skip_devolucao_entregue', 'AY3',
        'seller não salta para devolucao_entregue', hopEntregue);
  }

  // Buyer em_devolucao from entregue (fresh)
  final pB = await mustPay('AY3');
  await c.patchOrder(pB.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(pB.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  await c.insertDispute(orderId: pB.oid);
  final bEm = await c.patchOrder(
    pB.oid,
    {'status': 'em_devolucao'},
    jwt: c.buyerJwt,
  );
  final stB = st(await c.orderRow(pB.oid));
  if (bEm.ok && stB == 'em_devolucao') {
    c.hold(
      id: 'AY3.buyer_marca_em_devolucao',
      lens: 'AY3',
      severity: 'P2',
      title: 'Buyer marca em_devolucao a partir de entregue',
      actor: 'buyer JWT',
      pre: 'entregue + disputa',
      repro: 'PATCH em_devolucao JWT=buyer',
      expected: 'hop do seller após pedido_devolucao',
      obtained: {'hit': bEm.brief, 'st': stB},
    );
  } else {
    c.block('AY3.buyer_em_devolucao', 'AY3', 'buyer em_devolucao', {
      'hit': bEm.brief,
      'st': stB,
    });
  }

  // Buyer pedido_devolucao SEM disputa (entregue real)
  final pNo = await mustPay('AY3');
  await c.patchOrder(pNo.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(pNo.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  final noD = await c.patchOrder(
    pNo.oid,
    {'status': 'pedido_devolucao'},
    jwt: c.buyerJwt,
  );
  final stNo = st(await c.orderRow(pNo.oid));
  if (noD.ok && stNo == 'pedido_devolucao') {
    c.hold(
      id: 'AY3.pedido_sem_disputa',
      lens: 'AY3',
      severity: 'P1',
      title: 'Buyer pedido_devolucao em entregue sem disputa',
      actor: 'buyer JWT',
      pre: 'entregue, 0 disputas',
      repro: 'PATCH pedido_devolucao',
      expected: 'order_pedido_devolucao_requires_dispute',
      obtained: {'hit': noD.brief, 'st': stNo},
    );
  } else {
    c.block('AY3.pedido_sem_disputa', 'AY3', 'pedido exige disputa', noD);
  }

  // =========================================================================
  // AY5 — enviado→concluido (design?) + release; disputa após concluido
  // =========================================================================
  final p5 = await mustPay('AY5');
  await c.patchOrder(p5.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final hopC = await c.patchOrder(
    p5.oid,
    {'status': 'concluido'},
    jwt: c.buyerJwt,
  );
  final r5 = await c.orderRow(p5.oid);
  c.note('P2.enviado_concluido', 'buyer salta entregue', {
    'hit': hopC.brief,
    'st': st(r5),
    'completed_at': r5?['completed_at'],
    'shipped_at': r5?['shipped_at'],
  }, lens: 'AY5');
  if (hopC.ok && st(r5) == 'concluido') {
    final w0 = await c.wallets();
    final rel = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': p5.oid},
      jwt: c.buyerJwt,
    );
    final w1 = await c.wallets();
    final dAfter = await c.insertDispute(orderId: p5.oid);
    c.note('P2.release_concluido', 'release + disputa pós concluido', {
      'rpc': rel.brief,
      'd_seller': (w1['seller'] ?? 0) - (w0['seller'] ?? 0),
      'dispute': dAfter.brief,
      'release_at': (await c.orderRow(p5.oid))?['wallet_release_processed_at'],
    }, lens: 'AY5');
    // Design: buyer confirma receção via concluido. Só finding se disputa
    // ficar bloqueada pelo release (buyer perde via JWT) SEM entregue.
    if (releasedTrue(rel) && !dAfter.ok) {
      c.hold(
        id: 'AY5.release_fecha_disputa',
        lens: 'AY5',
        severity: 'P2',
        title:
            'Buyer enviado→concluido+release: disputa RLS 403 (wallet_release_processed_at)',
        actor: 'buyer JWT',
        pre: 'nunca passou por entregue; relógio 48h arrancado',
        repro: 'PATCH concluido; rpc release; POST order_disputes',
        expected: 'janela de disputa antes do release / 48h',
        obtained: {
          'release': rel.brief,
          'dispute': dAfter.brief,
          'delta': (w1['seller'] ?? 0) - (w0['seller'] ?? 0),
        },
      );
    }
  }

  // Race entregue∥disputa com orderRow
  final pR = await mustPay('AY2');
  await c.patchOrder(pR.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final raced = await parallel([
    c.patchOrder(pR.oid, {'status': 'entregue'}, jwt: c.buyerJwt),
    c.insertDispute(orderId: pR.oid),
  ]);
  final rRace = await c.orderRow(pR.oid);
  c.note('P2.race', 'entregue∥disputa', {
    'entregue': raced[0].brief,
    'disp': raced[1].brief,
    'st': st(rRace),
  }, lens: 'AY2');
  if (raced[1].ok && st(rRace) != 'entregue' && st(rRace) != 'concluido') {
    c.hold(
      id: 'AY2.race_dispute_before_entregue',
      lens: 'AY2',
      severity: 'P1',
      title: 'Race: disputa 201 sem entregue/concluido',
      actor: 'buyer JWT paralelo',
      pre: 'enviado',
      repro: 'parallel PATCH entregue + POST disputa',
      expected: 'disputa só após entregue',
      obtained: {
        'disp': raced[1].brief,
        'st': st(rRace),
      },
    );
  }

  // INSERT resolvida em entregue (agora com entregue real)
  final pRes = await mustPay('AY1');
  await c.patchOrder(pRes.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  await c.patchOrder(pRes.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  final insRes =
      await c.insertDispute(orderId: pRes.oid, status: 'resolvida');
  if (insRes.ok && '${insRes.map?['status']}' == 'resolvida') {
    c.hold(
      id: 'AY1.insert_resolvida_entregue',
      lens: 'AY1',
      severity: 'P2',
      title: 'INSERT disputa resolvida persistiu em entregue',
      actor: 'buyer JWT',
      pre: 'entregue',
      repro: 'POST status=resolvida',
      expected: 'forçado aberta',
      obtained: insRes.brief,
    );
  } else if (insRes.ok) {
    c.block('AY1.insert_resolvida_forced', 'AY1',
        'INSERT resolvida reescrito', insRes);
  } else {
    c.block('AY1.insert_resolvida', 'AY1', 'INSERT resolvida recusado', insRes);
  }

  // Proof photos other order_id (disputa real pRes ou chain)
  final photoDid = insRes.firstId ?? did;
  final paidS2 = await c.e2e('setup_paid_order', {'initial_qty': 1},
      seller: c.seller2Id, buyer: c.buyerId);
  final oidS2 = c.parseE2eOrderId(paidS2);
  if (oidS2 != null) c.createdOrderIds.add(oidS2);
  if (oidS2 != null && photoDid != null) {
    await c.patchOrder(oidS2, {'status': 'enviado'}, jwt: c.seller2Jwt);
    await c.patchOrder(oidS2, {'status': 'entregue'}, jwt: c.buyerJwt);
    await c.insertDispute(orderId: oidS2);
    final otherUrl =
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/authenticated/fleaber_private/order_disputes/${c.buyerId}/$oidS2/x.png';
    final photo = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$photoDid',
      jwt: c.buyerJwt,
      body: {
        'proof_photos': [otherUrl],
      },
    );
    final persisted = await c.rest(
      'GET',
      'order_disputes?id=eq.$photoDid&select=id,proof_photos',
      service: true,
    );
    c.note('P2.proof_other', 'proof_photos outro order_id', {
      'hit': photo.brief,
      'row': persisted.map,
    }, lens: 'AY7');
    final photos = '${persisted.map?['proof_photos'] ?? photo.body}';
    if ((photo.ok || persisted.ok) && photos.contains(oidS2)) {
      c.hold(
        id: 'AY7.proof_photos_other_order',
        lens: 'AY7',
        severity: 'P2',
        title:
            'proof_photos aceita URL authenticated de outra encomenda (S2) na disputa S1',
        actor: 'buyer JWT',
        pre: 'disputa B1–S1',
        repro: 'PATCH proof_photos=[…/order_disputes/{B1}/{oidS2}/…]',
        expected: 'deny path desta order_id',
        obtained: {'hit': photo.brief, 'photos': photos},
      );
    } else {
      c.block('AY7.proof_photos_other_order', 'AY7', 'proof outro order',
          photo);
    }

    // Prefix GET S2
    final prefixPath =
        'object/fleaber_private/order_disputes/${c.buyerId}/$oidS2-extra.png';
    final up = await c.storage(
      'POST',
      prefixPath,
      jwt: c.buyerJwt,
      bytes: png,
      contentType: 'image/png',
    );
    final s1 = await c.storage('GET', prefixPath, jwt: c.sellerJwt);
    final s2 = await c.storage('GET', prefixPath, jwt: c.seller2Jwt);
    c.note('P2.prefix', 'LIKE order_id% sem slash', {
      'up': up.brief,
      's1': s1.brief,
      's2': s2.brief,
    }, lens: 'AY7');
    if (s1.ok) {
      c.hold(
        id: 'AY7.s1_reads_prefix',
        lens: 'AY7',
        severity: 'P1',
        title: 'S1 lê order_disputes/{B1}/{oidS2}-extra',
        actor: 'seller JWT S1',
        pre: 'policy LIKE …/order_id%',
        repro: 'GET JWT=S1',
        expected: '404',
        obtained: s1.brief,
      );
    } else {
      c.block('AY7.prefix_s1', 'AY7', 'S1 prefix 404', {
        's1': s1.brief,
        's2': s2.brief,
      });
    }
  }

  // Partial refund RPC buyer after shipped+dispute
  if (did != null) {
    final partB = await c.rpc(
      'batata_process_partial_refund_dispute',
      {'p_order_id': oid, 'p_refund_percent': 50},
      jwt: c.buyerJwt,
    );
    c.note('P2.partial_buyer', 'partial RPC buyer pós-envio', partB.brief,
        lens: 'AY4');
    if (partB.ok &&
        partB.body != 'false' &&
        !partB.brief.contains('requires_stripe') &&
        !partB.brief.contains('not_allowed')) {
      final afterP = await c.orderRow(oid);
      c.hold(
        id: 'AY4.partial_buyer_rpc',
        lens: 'AY4',
        severity: 'P1',
        title: 'Buyer partial refund RPC após envio sem Stripe',
        actor: 'buyer JWT',
        pre: 'cadeia devolução',
        repro: 'rpc percent=50',
        expected: 'dispute_partial_refund_requires_stripe / recusa',
        obtained: {'hit': partB.brief, 'st': st(afterP)},
      );
    } else {
      c.block('AY4.partial_buyer', 'AY4', 'partial buyer gated', partB);
    }
  }

  await c.dumpAll('pass2.json');
  stdout.writeln(
    'PASS2 done findings=${c.findings.length} blocked=${c.blocked.length}',
  );
}
