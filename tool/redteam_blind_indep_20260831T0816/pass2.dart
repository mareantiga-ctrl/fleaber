import 'dart:convert';
import 'dart:io';

import '_rti4.dart';

Future<void> main() async {
  final c = Rti4(loadEnv());
  await c.boot();
  final e2eSecret = (c.env['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();

  Future<HttpR> e2e(Map<String, dynamic> body) {
    return c.edge(
      'sec-fase2-e2e-oversell',
      body,
      service: true,
      extra: e2eSecret.isEmpty
          ? null
          : {'x-fleaber-e2e-secret': e2eSecret},
    );
  }

  Future<Map<String, dynamic>?> walletOf(String uid) async {
    return c.getOne('wallets', uid, select: 'id,balance,available_balance');
  }

  final wBuyer0 = await walletOf(c.buyerId);
  final wSeller0 = await walletOf(c.sellerId);
  c.note('p2.wallet.before', 'wallets', {
    'buyer': wBuyer0,
    'seller': wSeller0,
  }, well: '2');

  // Fixture: paid order (TEST PI pm_card_visa) — service as fixture only
  final paid = await e2e({
    'probe': 'setup_paid_order',
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'initial_qty': 2,
  });
  c.note('p2.setup_paid', 'harness paid order', paid.brief, well: '2');
  final paidMap = paid.map ?? {};
  final oid = paidMap['order_id']?.toString();
  final pid = paidMap['product_id']?.toString();
  final pi = paidMap['payment_intent_id']?.toString();
  if (oid == null || oid.isEmpty) {
    stderr.writeln('FATAL no paid order fixture ${paid.brief}');
    await c.dump('pass2');
    exit(2);
  }
  c.createdOrderIds.add(oid);
  if (pid != null) c.createdProductIds.add(pid);

  var order = await c.getOne(
    'orders',
    oid,
    select:
        'id,status,buyer_id,seller_id,amount_paid_cents,stripe_payment_intent_id,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,shipping_method,completed_at,quantity,product_id,stock_units_applied,payment_method',
  );
  c.note('p2.order.pago', 'order after fixture', order, well: '2');

  // Capture check
  final captured = (order?['status'] ?? '').toString().toLowerCase() == 'pago' &&
      (int.tryParse('${order?['amount_paid_cents'] ?? 0}') ?? 0) > 0;
  if (!captured) {
    c.note('p2.capture.gap', 'fixture not pago', order, well: '2');
  } else {
    c.hold('p2.capture.fixture', 'captura TEST via harness PI succeeded', {
      'pi': pi,
      'amount_paid_cents': order?['amount_paid_cents'],
    }, well: '2');
  }

  // Buyer mutate shipping after paid → mão
  final ship = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    token: c.buyerJwt,
    body: {'shipping_method': 'Entrega em mão (€0.00)'},
  );
  final afterShip = await c.getOne('orders', oid, select: 'id,status,shipping_method');
  c.note('p2.ship.patch', 'buyer shipping after paid',
      '${ship.brief} after=${afterShip?['shipping_method']}', well: '2');
  final shipNow = (afterShip?['shipping_method'] ?? '').toString().toLowerCase();
  if (ship.ok &&
      (shipNow.contains('mão') ||
          shipNow.contains('mao') ||
          shipNow.contains('hand'))) {
    c.finding(
      id: 'RTI4-P2-SHIP-UNSEAL',
      title: 'buyer muda shipping para mão após pago',
      actor: 'buyer',
      sev: 'P1',
      well: '2',
      pre: 'order pago (captura TEST)',
      request: 'PATCH shipping_method=mão',
      before: order?['shipping_method'],
      after: afterShip,
      impact: 'Abre salto pago→concluido sem enviado (janela disputa).',
      repro: 'setup_paid_order + PATCH shipping',
    );
  } else {
    c.hold('p2.ship.frozen', 'shipping pós-pago imutável ou vazio selado', afterShip,
        well: '2');
  }

  // Buyer jump pago→concluido (carrier path)
  final jump = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    token: c.buyerJwt,
    body: {
      'status': 'concluido',
      'completed_at': '2020-01-01T00:00:00Z',
    },
  );
  var afterJump = await c.getOne(
    'orders',
    oid,
    select: 'id,status,completed_at,wallet_release_processed_at',
  );
  c.note('p2.buyer.concluido', 'buyer pago→concluido',
      '${jump.brief} after=${afterJump?['status']} completed=${afterJump?['completed_at']}',
      well: '2');
  if ((afterJump?['status'] ?? '').toString().toLowerCase() == 'concluido') {
    c.finding(
      id: 'RTI4-P2-EARLY-CONCLUÍDO',
      title: 'buyer marca concluido a partir de pago (sem enviado)',
      actor: 'buyer',
      sev: 'P1',
      well: '2',
      pre: 'pago / shipping não-mão',
      request: 'PATCH status=concluido + completed_at 2020',
      before: order?['status'],
      after: afterJump,
      impact: 'Salta hold de envio / janela disputa; completed_at pode acelerar cron.',
      repro: 'PATCH orders status=concluido',
    );
  } else {
    c.hold('p2.early.concluido', 'pago→concluido bloqueado', afterJump, well: '2');
  }

  // Seller jump concluido
  final sellerDone = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    token: c.sellerJwt,
    body: {'status': 'concluido'},
  );
  afterJump = await c.getOne('orders', oid, select: 'id,status');
  c.note('p2.seller.concluido', 'seller PATCH concluido',
      '${sellerDone.brief} after=${afterJump?['status']}', well: '2');
  if ((afterJump?['status'] ?? '').toString().toLowerCase() == 'concluido' &&
      (order?['status'] ?? '').toString().toLowerCase() != 'concluido') {
    c.finding(
      id: 'RTI4-P2-SELLER-CONCLUÍDO',
      title: 'seller marca concluido',
      actor: 'seller',
      sev: 'P1',
      well: '2',
      pre: 'order pago',
      request: 'PATCH status=concluido seller JWT',
      before: order?['status'],
      after: afterJump,
      impact: 'Seller fecha ciclo e pode disparar release.',
      repro: 'PATCH orders seller',
    );
  }

  // Seller marks enviado from pago (legitimate path)
  final shipIt = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    token: c.sellerJwt,
    body: {'status': 'enviado'},
  );
  var afterEnv = await c.getOne('orders', oid, select: 'id,status');
  c.note('p2.seller.enviado', 'seller enviado',
      '${shipIt.brief} after=${afterEnv?['status']}', well: '2');

  // Fresh JWT tries to PATCH this order
  if (c.freshJwt != null) {
    final fr = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      token: c.freshJwt,
      body: {'status': 'concluido'},
    );
    final afterFr = await c.getOne('orders', oid, select: 'id,status');
    c.note('p2.fresh.patch', 'fresh PATCH concluido',
        '${fr.brief} after=${afterFr?['status']}', well: '2');
    if ((afterFr?['status'] ?? '') != (afterEnv?['status'] ?? '') &&
        (afterFr?['status'] ?? '').toString().toLowerCase() == 'concluido') {
      c.finding(
        id: 'RTI4-P2-FRESH-STATUS',
        title: 'buyer fresco altera status de order alheia',
        actor: 'fresh buyer',
        sev: 'P0',
        well: '2',
        pre: 'order de outro buyer',
        request: 'PATCH status',
        before: afterEnv,
        after: afterFr,
        impact: 'Autoridade de ciclo de vida cross-user.',
        repro: 'signup JWT PATCH orders?id=eq',
      );
    }
  }

  // Buyer confirm after enviado
  if ((afterEnv?['status'] ?? '').toString().toLowerCase() == 'enviado') {
    final conf = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      token: c.buyerJwt,
      body: {'status': 'concluido'},
    );
    afterJump = await c.getOne(
      'orders',
      oid,
      select: 'id,status,completed_at,wallet_release_processed_at',
    );
    c.note('p2.buyer.confirm', 'buyer confirm enviado→concluido',
        '${conf.brief} after=${afterJump?['status']}', well: '2');
  }

  // Dual release race + alien JWT
  final wS1 = await walletOf(c.sellerId);
  final relCalls = await Future.wait([
    c.rpc('batata_release_seller_wallet_for_order', {'p_order_id': oid},
        token: c.buyerJwt),
    c.rpc('batata_release_seller_wallet_for_order', {'p_order_id': oid},
        token: c.buyerJwt),
    c.rpc('batata_release_seller_wallet_for_order', {'p_order_id': oid},
        token: c.sellerJwt),
    if (c.freshJwt != null)
      c.rpc('batata_release_seller_wallet_for_order', {'p_order_id': oid},
          token: c.freshJwt),
  ]);
  for (var i = 0; i < relCalls.length; i++) {
    c.note('p2.release.$i', 'release parallel', relCalls[i].brief, well: '2');
  }
  final wS2 = await walletOf(c.sellerId);
  final orderRel = await c.getOne(
    'orders',
    oid,
    select:
        'id,status,wallet_release_processed_at,amount_paid_cents,stripe_refund_id',
  );
  c.note('p2.wallet.after.release', 'seller wallet Δ', {
    'before': wS1,
    'after': wS2,
    'order': orderRel,
  }, well: '2');

  num n(dynamic v) => num.tryParse('$v') ?? 0;
  final dSeller = n(wS2?['balance']) - n(wS1?['balance']);
  final trueCount = relCalls.where((r) => r.body.trim() == 'true' || r.body.contains('true')).length;
  if (trueCount >= 2 && dSeller > 0.01) {
    // need txs count
  }
  final txs = await c.rest(
    'GET',
    'wallet_transactions?order_id=eq.$oid&select=id,user_id,amount,kind,created_at',
    service: true,
  );
  c.note('p2.txs.release', 'wallet txs', txs.brief, well: '2');
  final creditTx = txs.list.whereType<Map>().where((m) {
    final k = (m['kind'] ?? '').toString().toLowerCase();
    return k.contains('venda') || k.contains('credit') || n(m['amount']) > 0;
  }).toList();
  if (creditTx.length >= 2) {
    c.finding(
      id: 'RTI4-P2-DOUBLE-RELEASE',
      title: 'dois créditos wallet no mesmo order',
      actor: 'buyer/seller JWT race',
      sev: 'P0',
      well: '2',
      pre: 'order concluido captura TEST',
      request: 'N x batata_release_seller_wallet_for_order',
      before: wS1,
      after: {'wallet': wS2, 'txs': creditTx.length, 'delta': dSeller},
      impact: 'Mint líquido no release.',
      repro: 'parallel RPC release',
    );
  } else {
    c.hold('p2.release.once', '≤1 crédito wallet', {
      'delta': dSeller,
      'txs': creditTx.length,
      'trueCount': trueCount,
    }, well: '2');
  }

  // Fresh release should be false without credit
  if (c.freshJwt != null && dSeller > 0 && trueCount == 0) {
    // nothing
  }

  // Dispute as seller, as fresh, as buyer
  final dispSeller = await c.rest(
    'POST',
    'order_disputes',
    token: c.sellerJwt,
    body: {
      'order_id': oid,
      'buyer_id': c.buyerId,
      'status': 'aberta',
      'reason': '$prefix seller opens',
    },
  );
  c.note('p2.disp.seller', 'seller INSERT dispute', dispSeller.brief, well: '2');

  final dispFresh = c.freshJwt == null
      ? null
      : await c.rest(
          'POST',
          'order_disputes',
          token: c.freshJwt,
          body: {
            'order_id': oid,
            'buyer_id': c.freshId,
            'status': 'aberta',
            'reason': '$prefix fresh',
          },
        );
  if (dispFresh != null) {
    c.note('p2.disp.fresh', 'fresh INSERT dispute', dispFresh.brief, well: '2');
    if (dispFresh.ok) {
      c.finding(
        id: 'RTI4-P2-DISPUTE-XUSER',
        title: 'buyer fresco abre disputa em order alheia',
        actor: 'fresh',
        sev: 'P1',
        well: '2',
        pre: 'order de outro buyer',
        request: 'POST order_disputes',
        before: oid,
        after: dispFresh.brief,
        impact: 'Autoridade de disputa cross-user.',
        repro: 'POST order_disputes',
      );
    }
  }

  final dispBuyer = await c.rest(
    'POST',
    'order_disputes',
    token: c.buyerJwt,
    body: {
      'order_id': oid,
      'buyer_id': c.buyerId,
      'status': 'aberta',
      'reason': '$prefix buyer dispute',
    },
  );
  c.note('p2.disp.buyer', 'buyer INSERT dispute', dispBuyer.brief, well: '2');
  String? did;
  if (dispBuyer.ok && dispBuyer.list.isNotEmpty) {
    did = (dispBuyer.list.first as Map)['id']?.toString();
  } else if (dispSeller.ok && dispSeller.list.isNotEmpty) {
    did = (dispSeller.list.first as Map)['id']?.toString();
  }

  if (did != null) {
    final close = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      token: c.sellerJwt,
      body: {'status': 'resolvida'},
    );
    final dAfter = await c.getOne('order_disputes', did, select: 'id,status');
    c.note('p2.disp.seller.close', 'seller fecha disputa',
        '${close.brief} after=${dAfter?['status']}', well: '2');
    if ((dAfter?['status'] ?? '').toString().toLowerCase() == 'resolvida') {
      c.finding(
        id: 'RTI4-P2-SELLER-CLOSE-DISPUTE',
        title: 'seller fecha disputa (resolvida)',
        actor: 'seller',
        sev: 'P1',
        well: '2',
        pre: 'disputa aberta',
        request: 'PATCH order_disputes status=resolvida',
        before: did,
        after: dAfter,
        impact: 'Seller auto-absolve; pode desbloquear release/refund.',
        repro: 'PATCH order_disputes',
      );
    } else {
      c.hold('p2.disp.seller.close', 'seller não fecha disputa', dAfter, well: '2');
    }
  }

  // Release during/after dispute
  final relDisp = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': oid},
    token: c.buyerJwt,
  );
  c.note('p2.release.during.disp', 'release with dispute', relDisp.brief, well: '2');

  // Refund Edge after concluido / with dispute
  final refundBuyer = await c.edge(
    'refund-order',
    {'order_id': oid},
    token: c.buyerJwt,
  );
  c.note('p2.refund.buyer', 'buyer refund-order', refundBuyer.brief, well: '2');
  final refundSeller = await c.edge(
    'refund-order',
    {'order_id': oid},
    token: c.sellerJwt,
  );
  c.note('p2.refund.seller', 'seller refund-order', refundSeller.brief, well: '2');

  final orderRf = await c.getOne(
    'orders',
    oid,
    select:
        'id,status,amount_paid_cents,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at',
  );
  final wS3 = await walletOf(c.sellerId);
  final wB3 = await walletOf(c.buyerId);
  c.note('p2.after.refund', 'state after refund attempts', {
    'order': orderRf,
    'seller': wS3,
    'buyer': wB3,
  }, well: '2');

  final refunded = (orderRf?['stripe_refund_id'] ?? '').toString().isNotEmpty;
  final released = orderRf?['wallet_release_processed_at'] != null;
  if (refunded && released && dSeller > 0.01) {
    // net mint if seller kept credit AND stripe refunded buyer
    c.finding(
      id: 'RTI4-P2-RELEASE-AND-REFUND',
      title: 'release wallet + refund Stripe no mesmo order',
      actor: 'buyer+seller JWT',
      sev: 'P0',
      well: '2',
      pre: 'captura TEST + concluido',
      request: 'release RPC + refund-order Edge',
      before: {'seller': wS1, 'paid': order?['amount_paid_cents']},
      after: {'seller': wS3, 'order': orderRf, 'refund': refundSeller.brief},
      impact: 'Dinheiro líquido: captura reembolsada e seller creditado.',
      repro: 'concluido → release → refund-order',
    );
  }

  // Review after whatever status
  final review = await c.rest(
    'POST',
    'reviews',
    token: c.buyerJwt,
    body: {
      'order_id': oid,
      'buyer_id': c.buyerId,
      'target_id': c.sellerId,
      'stars': 5,
      'comment': '$prefix postpay review',
    },
  );
  c.note('p2.review', 'review on paid order', review.brief, well: '2');
  final review2 = await c.rest(
    'POST',
    'reviews',
    token: c.buyerJwt,
    body: {
      'order_id': oid,
      'buyer_id': c.buyerId,
      'target_id': c.sellerId,
      'stars': 1,
      'comment': '$prefix dup',
    },
  );
  c.note('p2.review.dup', 'duplicate review', review2.brief, well: '2');
  if (review.ok && review2.ok) {
    c.finding(
      id: 'RTI4-P2-REVIEW-DUP',
      title: 'duas reviews no mesmo order',
      actor: 'buyer',
      sev: 'P1',
      well: '2',
      pre: 'order pago/concluido',
      request: '2x POST reviews',
      before: oid,
      after: [review.brief, review2.brief],
      impact: 'Reputação duplicada.',
      repro: 'POST reviews twice',
    );
  }

  if (c.freshJwt != null) {
    final steal = await c.rest(
      'POST',
      'reviews',
      token: c.freshJwt,
      body: {
        'order_id': oid,
        'buyer_id': c.freshId,
        'target_id': c.sellerId,
        'stars': 5,
        'comment': '$prefix stolen',
      },
    );
    c.note('p2.review.fresh', 'fresh reviews alien order', steal.brief, well: '2');
    if (steal.ok) {
      c.finding(
        id: 'RTI4-P2-REVIEW-XUSER',
        title: 'buyer fresco reviewa order alheia',
        actor: 'fresh',
        sev: 'P1',
        well: '2',
        pre: 'order de outro',
        request: 'POST reviews order_id alheio',
        before: oid,
        after: steal.brief,
        impact: 'Reputação forjada cross-user.',
        repro: 'POST reviews',
      );
    }
  }

  // Dual settle GET on PI session (unpaid cs vs paid pi)
  final settleGet = await c.call(
    'GET',
    '/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_$stamp',
    token: c.buyerJwt,
  );
  c.note('p2.settle.get.fake', 'GET settle fake cs', settleGet.brief, well: '2');

  // App Checkout Session on a NEW listed product (SESSION ≠ CAPTURE)
  final prod = await c.insertProduct(listed: true, sold: false, qty: 1, price: 4.5);
  if (prod != null) {
    final hold = await c.insertOrder(
      token: c.buyerJwt,
      productId: prod['id'].toString(),
      shipping: 'Entrega em mão (€0.00)',
    );
    c.note('p2.app.hold', 'app-path hold', hold.brief, well: '2');
    if (hold.ok && hold.list.isNotEmpty) {
      final aoid = (hold.list.first as Map)['id'].toString();
      c.createdOrderIds.add(aoid);
      final ck = await c.edge(
        'create-payment-intent',
        {
          'order_id': aoid,
          'product_id': prod['id'],
          'amount': 1,
          'shipping_method': 'Entrega em mão (€0.00)',
        },
        token: c.buyerJwt,
      );
      c.note('p2.app.session', 'create-payment-intent', ck.brief, well: '2');
      final cs = ck.map?['checkoutSessionId']?.toString();
      final urlCk = ck.map?['checkoutUrl']?.toString();
      File('tool/redteam_blind_indep_$stamp/out/checkout_url.txt')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'order_id': aoid,
          'checkoutSessionId': cs,
          'checkoutUrl': urlCk,
          'http': ck.brief,
        }));
      if (cs != null && cs.isNotEmpty) {
        final getSettle = await c.call(
          'GET',
          '/functions/v1/create-payment-intent?checkout_return=success&session_id=$cs',
        );
        final o2 = await c.getOne('orders', aoid, select: 'id,status,amount_paid_cents');
        c.note('p2.app.get.unpaid', 'GET settle unpaid session', {
          'http': getSettle.brief,
          'order': o2,
        }, well: '2');
        if ((o2?['status'] ?? '').toString().toLowerCase() == 'pago') {
          c.finding(
            id: 'RTI4-P2-SETTLE-UNPAID-CS',
            title: 'GET settle marca pago em Session não paga',
            actor: 'anon GET',
            sev: 'P0',
            well: '2',
            pre: 'cs_test criado, não pago',
            request: 'GET create-payment-intent checkout_return=success',
            before: aoid,
            after: o2,
            impact: 'Pago sem captura.',
            repro: 'GET settle unpaid cs',
          );
        } else {
          c.hold('p2.settle.unpaid', 'GET settle unpaid ≠ pago', o2, well: '2');
        }
      }
    }
  }

  // Off-platform collusion: new product, buyer hold, seller marks pago
  final offP = await c.insertProduct(listed: true, sold: false, qty: 1);
  if (offP != null) {
    final offO = await c.insertOrder(
      token: c.buyerJwt,
      productId: offP['id'].toString(),
      payment: 'Dinheiro em mão',
      shipping: 'Entrega em mão (€0.00)',
    );
    c.note('p2.off.insert', 'off-platform hold', offO.brief, well: '2');
    if (offO.ok && offO.list.isNotEmpty) {
      final oid2 = (offO.list.first as Map)['id'].toString();
      c.createdOrderIds.add(oid2);
      final sp = await c.rest(
        'PATCH',
        'orders?id=eq.$oid2',
        token: c.sellerJwt,
        body: {'status': 'pago'},
      );
      var oOff = await c.getOne(
        'orders',
        oid2,
        select: 'id,status,stock_units_applied,amount_paid_cents',
      );
      c.note('p2.off.seller.pago', 'seller marca pago off-platform',
          '${sp.brief} after=$oOff', well: '2');
      final bc = await c.rest(
        'PATCH',
        'orders?id=eq.$oid2',
        token: c.buyerJwt,
        body: {'status': 'concluido'},
      );
      oOff = await c.getOne('orders', oid2,
          select: 'id,status,stock_units_applied,amount_paid_cents');
      c.note('p2.off.buyer.concluido', 'buyer concluido off-platform',
          '${bc.brief} after=$oOff', well: '2');
      final wSOff0 = await walletOf(c.sellerId);
      final relOff = await c.rpc(
        'batata_release_seller_wallet_for_order',
        {'p_order_id': oid2},
        token: c.buyerJwt,
      );
      final wSOff1 = await walletOf(c.sellerId);
      c.note('p2.off.release', 'release off-platform', {
        'rpc': relOff.brief,
        'dSeller': n(wSOff1?['balance']) - n(wSOff0?['balance']),
        'order': oOff,
      }, well: '2');
      final dOff = n(wSOff1?['balance']) - n(wSOff0?['balance']);
      if (dOff > 0.01) {
        c.finding(
          id: 'RTI4-P2-OFFPLATFORM-MINT',
          title: 'release credita wallet em pagamento off-platform sem captura',
          actor: 'buyer+seller collusion',
          sev: 'P0',
          well: '2',
          pre: 'Dinheiro em mão, sem Stripe',
          request: 'seller pago → buyer concluido → release',
          before: wSOff0,
          after: {'wallet': wSOff1, 'delta': dOff, 'order': oOff},
          impact: 'Mint de saldo plataforma sem fundos Stripe.',
          repro: 'off-platform status chain + release RPC',
        );
      } else {
        c.hold('p2.off.mint', 'off-platform release sem crédito', dOff, well: '2');
      }
      final rv = await c.rest(
        'POST',
        'reviews',
        token: c.buyerJwt,
        body: {
          'order_id': oid2,
          'buyer_id': c.buyerId,
          'target_id': c.sellerId,
          'stars': 5,
          'comment': '$prefix off-platform review',
        },
      );
      c.note('p2.off.review', 'review off-platform', rv.brief, well: '2');
    }
  }

  // Accounting close on captured order
  c.note('p2.accounting', 'captura vs Δ', {
    'amount_paid_cents': order?['amount_paid_cents'],
    'seller_delta_on_release_attempt': dSeller,
    'refund_id': orderRf?['stripe_refund_id'],
    'release_at': orderRf?['wallet_release_processed_at'],
    'final_status': orderRf?['status'],
  }, well: '2');

  await c.dump('pass2');
  stdout.writeln(
      'PASS2 done findings=${c.findings.length} holds=${c.holds.length}');
}
