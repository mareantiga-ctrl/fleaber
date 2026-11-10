/// REDTEAM_BLIND_P_COMPOSICAO_CAIXA_v1 — dart run tool/redteam_blind_p_20260831T2020/probe.dart
/// Staging only. No production. No SQL/Edge/Flutter patches.
import 'dart:convert';
import 'dart:io';

import '_rtp.dart';

String jsonCard(String kind, [Map<String, dynamic>? extra]) {
  final m = <String, dynamic>{'kind': kind, ...?extra};
  return 'FLEABER_JSON_V1:${jsonEncode(m)}';
}

num? numOf(dynamic v) {
  if (v is num) return v;
  return num.tryParse('$v');
}

void main() async {
  final env = loadEnv();
  final c = Rtp.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final w0 = await c.wallets();
  c.note('w0', 'wallets t0', w0, lens: 'P10');

  final pid = await c.createProduct(title: '$prefix sku-a', qty: 4, price: 8.5);
  final pidB = await c.createProduct(
    title: '$prefix sku-b',
    qty: 1,
    price: 12.0,
    seller: c.seller2Id,
  );
  if (pid == null || pidB == null) {
    stderr.writeln('FAIL product fixture');
    exit(4);
  }
  final chatId = await c.ensureChat(pid);

  // =====================================================================
  // P3+P9 — hold → mutar catálogo / portes / body hostil → checkout quote
  // =====================================================================
  final oidP3 = await c.insertOrder(
    productId: pid,
    jwt: c.buyerJwt,
    price: 8.5,
    shipping: 'entrega em mão',
  );
  c.note('p3.hold', 'hold 8,50 € mão', oidP3, lens: 'P3');

  final dropPrice = await c.rest(
    'PATCH',
    'products?id=eq.$pid',
    jwt: c.sellerJwt,
    body: {'price': 1.0},
  );
  c.note('p3.price.drop', 'seller PATCH price 1.00', dropPrice.brief, lens: 'P3');

  final ckP3 = await c.checkout(
    orderId: oidP3 ?? '',
    amount: 50,
    productId: pidB,
    seller: c.seller2Id,
    prize: true,
    shipping: 'mao',
  );
  final amtP3 = numOf(ckP3.map?['amount_total'] ?? ckP3.map?['server_amount_cents']);
  c.note('p3.checkout', 'checkout após price=1 + body hostil', {
    'http': ckP3.brief,
    'amount_total': ckP3.map?['amount_total'],
    'server_amount_cents': ckP3.map?['server_amount_cents'],
    'sid': ckP3.map?['checkoutSessionId'],
  }, lens: 'P3');

  // Contrato original ~8,50 + protecção mão. Underpay se Stripe < ~500¢ (itens 1€).
  if (ckP3.ok && amtP3 != null && amtP3 < 400) {
    c.hold(
      id: 'RTP-P3-001',
      lens: 'P3+P9',
      severity: 'P1',
      title: 'Catálogo depois do hold baixa o amount Stripe (underpay path)',
      actor: 'seller PATCH price + buyer checkout body hostil',
      pre: 'hold 8,50 €; product price→1,00; body amount=50 prize_shipping product/seller alheios',
      repro: 'checkout order $oidP3 amount_total=$amtP3',
      expected: 'quote selado no contrato (~8,50 + protecção) ou recusa',
      obtained: ckP3.map,
      evidence: {'amount_total': amtP3, 'order': oidP3, 'product': pid},
    );
  }

  // P3 shipping: nova order (1 Session/order). Hold carrier → PATCH mão → checkout.
  final pidShip = await c.createProduct(title: '$prefix sku-ship', qty: 2, price: 8.5);
  final oidShip = await c.insertOrder(
    productId: pidShip ?? pid,
    jwt: c.buyerJwt,
    price: 8.5,
    shipping: 'envio transportadora (€3.50)',
  );
  final patchMao = await c.rest(
    'PATCH',
    'orders?id=eq.$oidShip',
    jwt: c.buyerJwt,
    body: {'shipping_method': 'entrega em mão'},
  );
  final ckShip = await c.checkout(
    orderId: oidShip ?? '',
    amount: 50,
    shipping: 'mao',
  );
  final amtShip = numOf(ckShip.map?['amount_total'] ?? ckShip.map?['server_amount_cents']);
  c.note('p3.ship', 'carrier hold → PATCH mão → checkout', {
    'patch': patchMao.brief,
    'checkout': ckShip.brief,
    'amount': amtShip,
  }, lens: 'P3');
  // Carrier 350¢ + protecção extra. Se amount ≈ hold mão (sem 350), underpay portes.
  if (ckShip.ok && amtShip != null && patchMao.ok && amtShip < 700) {
    c.hold(
      id: 'RTP-P3-002',
      lens: 'P3',
      severity: 'P1',
      title: 'PATCH portes mão depois do hold carrier reduz Stripe',
      actor: 'buyer JWT',
      pre: 'hold carrier 8,50+3,50; PATCH shipping=mão',
      repro: 'checkout $oidShip amount=$amtShip',
      expected: 'portes selados no contrato / PATCH recusado',
      obtained: {'patch': patchMao.brief, 'amount': amtShip},
      evidence: {'order': oidShip},
    );
  }

  // P3 unlist + live_id no body (não é bag unlist clássico — cadeia hold→unlist→checkout).
  final pidUl = await c.createProduct(title: '$prefix sku-ul', qty: 2, price: 8.5);
  final oidUl = await c.insertOrder(
    productId: pidUl ?? pid,
    jwt: c.buyerJwt,
    price: 8.5,
  );
  final unlist = await c.rest(
    'PATCH',
    'products?id=eq.$pidUl',
    jwt: c.sellerJwt,
    body: {'list_on_marketplace': false, 'is_sold': true},
  );
  final ckUl = await c.checkout(
    orderId: oidUl ?? '',
    amount: 50,
    liveId: '00000000-0000-0000-0000-000000000001',
  );
  c.note('p3.unlist', 'unlist+sold + live_id forjado → checkout', {
    'unlist': unlist.brief,
    'checkout': ckUl.brief,
    'amount': ckUl.map?['amount_total'],
  }, lens: 'P3');
  if (ckUl.ok && ckUl.map?['checkoutSessionId'] != null) {
    c.hold(
      id: 'RTP-P3-003',
      lens: 'P3+P8',
      severity: 'P1',
      title: 'Hold + unlist/sold + live_id body ainda abre Session Stripe',
      actor: 'seller unlist + buyer checkout',
      pre: 'hold marketplace; product list=false is_sold=true; body live_id forjado',
      repro: 'checkout $oidUl → ${ckUl.map?['checkoutSessionId']}',
      expected: 'recusa (produto morto, live inactiva)',
      obtained: ckUl.map,
      evidence: {'order': oidUl, 'product': pidUl},
    );
  }

  // =====================================================================
  // P2 — stock=1, dois buyers, dois caminhos (INSERT hold paralelo)
  // =====================================================================
  final pid1 = await c.createProduct(title: '$prefix sku-1', qty: 1, price: 8.5);
  final holds = await Future.wait([
    c.insertOrder(productId: pid1 ?? pid, jwt: c.buyerJwt, price: 8.5),
    c.insertOrder(
      productId: pid1 ?? pid,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
      price: 8.5,
    ),
  ]);
  final h1 = holds[0];
  final h2 = holds[1];
  c.note('p2.dual.hold', '2 holds stock=1', {'b1': h1, 'b2': h2}, lens: 'P2');
  final ckH1 = h1 == null
      ? null
      : await c.checkout(orderId: h1, jwt: c.buyerJwt, buyer: c.buyerId);
  final ckH2 = h2 == null
      ? null
      : await c.checkout(orderId: h2, jwt: c.buyer2Jwt, buyer: c.buyer2Id);
  c.note('p2.dual.ck', 'checkout ambos holds', {
    'b1': ckH1?.brief,
    'b2': ckH2?.brief,
    'sid1': ckH1?.map?['checkoutSessionId'],
    'sid2': ckH2?.map?['checkoutSessionId'],
  }, lens: 'P2');
  if (ckH1?.ok == true &&
      ckH2?.ok == true &&
      ckH1?.map?['checkoutSessionId'] != null &&
      ckH2?.map?['checkoutSessionId'] != null) {
    c.hold(
      id: 'RTP-P2-001',
      lens: 'P2',
      severity: 'P1',
      title: 'Stock=1: dois buyers obtêm Session Stripe em paralelo',
      actor: 'buyer + buyer2',
      pre: 'product qty=1; dois INSERT reserva_pendente; dois checkout',
      repro: 'sids ${ckH1?.map?['checkoutSessionId']} + ${ckH2?.map?['checkoutSessionId']}',
      expected: '2.º hold ou 2.º checkout recusado',
      obtained: {'h1': h1, 'h2': h2},
      evidence: {
        'sid1': ckH1?.map?['checkoutSessionId'],
        'sid2': ckH2?.map?['checkoutSessionId'],
        'product': pid1,
      },
    );
  }

  // =====================================================================
  // P6 — off-platform pago + Stripe na mesma order
  // =====================================================================
  final pidMb = await c.createProduct(title: '$prefix sku-mb', qty: 2, price: 8.5);
  final oidMb = await c.insertOrder(
    productId: pidMb ?? pid,
    jwt: c.buyerJwt,
    price: 8.5,
    payment: 'MB WAY',
    shipping: 'entrega em mão',
  );
  final sellerPago = await c.rest(
    'PATCH',
    'orders?id=eq.$oidMb',
    jwt: c.sellerJwt,
    body: {'status': 'pago'},
  );
  final ckMb = await c.checkout(orderId: oidMb ?? '', amount: 50);
  final rowMb = await c.orderRow(oidMb ?? '');
  c.note('p6.dual.rail', 'MB WAY pago + checkout Stripe', {
    'patch': sellerPago.brief,
    'checkout': ckMb.brief,
    'status': rowMb?['status'],
    'sid': ckMb.map?['checkoutSessionId'],
    'pi': rowMb?['stripe_payment_intent_id'],
  }, lens: 'P6');
  if (sellerPago.ok &&
      (rowMb?['status'] ?? '').toString().toLowerCase() == 'pago' &&
      ckMb.ok &&
      ckMb.map?['checkoutSessionId'] != null) {
    c.hold(
      id: 'RTP-P6-001',
      lens: 'P6',
      severity: 'P1',
      title: 'Order já pago off-platform ainda abre Session Stripe',
      actor: 'seller PATCH pago + buyer checkout',
      pre: 'hold MB WAY; seller marca pago sem PI',
      repro: 'checkout $oidMb → ${ckMb.map?['checkoutSessionId']}',
      expected: 'checkout recusado em status pago',
      obtained: {'status': rowMb?['status'], 'sid': ckMb.map?['checkoutSessionId']},
      evidence: {'order': oidMb},
    );
  }

  // =====================================================================
  // P1 — mentira chat → refund-order (caixa)
  // =====================================================================
  if (chatId != null && oidMb != null) {
    final insCard = await c.rest('POST', 'chat_messages', jwt: c.buyerJwt, body: {
      'chat_id': chatId,
      'sender_id': c.buyerId,
      'text': jsonCard('seguro_fleaber_paid', {
        'order_id': oidMb,
        'total': 8888.88,
      }),
    });
    c.note('p1.card', 'INSERT seguro_fleaber_paid (elo, não finding isolado)',
        insCard.brief,
        lens: 'P1');
    final refundOnLie = await c.edge('refund-order', {'order_id': oidMb}, jwt: c.sellerJwt);
    c.note('p1.refund', 'refund-order após card pago falso', refundOnLie.brief,
        lens: 'P1');
    final rowAfterLie = await c.orderRow(oidMb);
    final wLie = await c.wallets();
    if (refundOnLie.ok &&
        (rowAfterLie?['stripe_refund_id'] != null ||
            wLie['buyer'] != w0['buyer'])) {
      c.hold(
        id: 'RTP-P1-001',
        lens: 'P1',
        severity: 'P0',
        title: 'Card «pago» falso + refund-order move dinheiro',
        actor: 'buyer INSERT card + seller refund-order',
        pre: 'MB WAY pago sem PI + JSON seguro_fleaber_paid',
        repro: 'refund-order $oidMb',
        expected: 'recusa sem PaymentIntent / sem Δwallet',
        obtained: {
          'refund': refundOnLie.brief,
          'order': rowAfterLie,
          'wallets': wLie,
        },
      );
    }
  }

  // Buyer força pago Stripe sem captura
  final oidFakePago = await c.insertOrder(
    productId: pid,
    jwt: c.buyerJwt,
    price: 8.5,
    payment: 'Pagamento na app',
  );
  final buyerPago = await c.rest(
    'PATCH',
    'orders?id=eq.$oidFakePago',
    jwt: c.buyerJwt,
    body: {'status': 'pago', 'amount_paid_cents': 888888},
  );
  final rowFake = await c.orderRow(oidFakePago ?? '');
  c.note('p1.buyer.pago', 'buyer PATCH pago+amount', {
    'http': buyerPago.brief,
    'status': rowFake?['status'],
    'paid': rowFake?['amount_paid_cents'],
  }, lens: 'P1');
  if (buyerPago.ok &&
      (rowFake?['status'] ?? '').toString().toLowerCase() == 'pago') {
    c.hold(
      id: 'RTP-P1-002',
      lens: 'P1',
      severity: 'P1',
      title: 'Buyer PATCH status=pago + amount_paid_cents sem captura',
      actor: 'buyer JWT',
      pre: 'hold Pagamento na app',
      repro: 'PATCH orders $oidFakePago pago / 888888¢',
      expected: 'money fields + status pago imutáveis pelo buyer',
      obtained: rowFake,
    );
  }

  // =====================================================================
  // P4 — identidade cruzada
  // =====================================================================
  final oidA = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 8.5);
  final ckA = await c.checkout(orderId: oidA ?? '');
  final sidA = ckA.map?['checkoutSessionId']?.toString();
  final ckCross = await c.checkout(
    orderId: oidA ?? '',
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    productId: pidB,
    seller: c.seller2Id,
  );
  c.note('p4.ck.cross', 'buyer2 checkout order do buyer1', ckCross.brief, lens: 'P4');

  final refundCross = await c.edge(
    'refund-order',
    {'order_id': oidA},
    jwt: c.buyer2Jwt,
  );
  final refundS2 = await c.edge(
    'refund-order',
    {'order_id': oidA},
    jwt: c.seller2Jwt,
  );
  c.note('p4.refund.cross', 'refund JWT alheio', {
    'b2': refundCross.brief,
    's2': refundS2.brief,
  }, lens: 'P4');

  final settleAlien = sidA == null
      ? null
      : await c.edge(
          'create-payment-intent?checkout_return=success&session_id=$sidA&order_id=${oidMb ?? oidA}',
          null,
          method: 'GET',
          jwt: c.buyer2Jwt,
        );
  c.note('p4.settle.get', 'GET settle session A + order_id B', settleAlien?.brief,
      lens: 'P4');

  final e2eJwtSettle = await c.req(
    'POST',
    '/functions/v1/create-payment-intent?fase2_e2e_settle=1',
    jwt: c.buyerJwt,
    body: {
      'order_id': oidA,
      'payment_intent_id': 'pi_3fakeRTP2020xxxxxxxxxxxxxx',
      'product_id': pid,
    },
  );
  c.note('p4.e2e.jwt', 'fase2_e2e_settle com JWT (não service)', e2eJwtSettle.brief,
      lens: 'P4');

  // =====================================================================
  // P9 — wallet mint JWT · RPCs crédito
  // =====================================================================
  final wIns = await c.rest('POST', 'wallet_transactions', jwt: c.buyerJwt, body: {
    'wallet_id': c.buyerId,
    'amount': 99.0,
    'type': 'credit',
    'description': '$prefix mint',
  });
  final wPatch = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.buyerId}',
    jwt: c.buyerJwt,
    body: {'balance': 9999},
  );
  final creditRpc = await c.rpc('batata_credit_wallet_once', {
    'p_user_id': c.buyerId,
    'p_amount': 50,
    'p_order_id': oidA,
    'p_reason': 'rtp',
  }, jwt: c.buyerJwt);
  c.note('p9.wallet', 'INSERT txn / PATCH balance / credit RPC', {
    'ins': wIns.brief,
    'patch': wPatch.brief,
    'rpc': creditRpc.brief,
  }, lens: 'P9');
  final wAfterMint = await c.wallets();
  if (wIns.ok || wPatch.ok || creditRpc.ok) {
    final dB = (wAfterMint['buyer'] ?? 0) - (w0['buyer'] ?? 0);
    if (dB > 0.01) {
      c.hold(
        id: 'RTP-P9-001',
        lens: 'P9',
        severity: 'P0',
        title: 'JWT mintou wallet (INSERT/PATCH/RPC)',
        actor: 'buyer JWT',
        pre: 'w0 buyer=${w0['buyer']}',
        repro: 'wallet_transactions / wallets PATCH / batata_credit_wallet_once',
        expected: '403 / sem Δ',
        obtained: {'w': wAfterMint, 'ins': wIns.brief, 'rpc': creditRpc.brief},
      );
    }
  }

  // =====================================================================
  // P8 — tip checkout body hostil (seller alheio / amount)
  // =====================================================================
  final tip = await c.edge('create-live-tip-checkout', {
    'seller_id': c.seller2Id,
    'amount_eur': 0.5,
    'live_id': '00000000-0000-0000-0000-000000000001',
    'tip_id': oidA,
  }, jwt: c.buyerJwt);
  c.note('p8.tip', 'tip checkout seller2 + live forjado', tip.brief, lens: 'P8');

  // =====================================================================
  // P5+P10 — Stripe TEST pago → race refund ∥ release ∥ refund wallet
  // =====================================================================
  final paid = await c.e2e('setup_paid_order', {'initial_qty': 2});
  c.note('p5.paid', 'setup_paid_order Stripe TEST', paid.brief, lens: 'P5');
  final paidOid = c.parseE2eOrderId(paid);
  final paidPid = c.parseE2eProductId(paid);
  if (paidPid != null) c.createdProductIds.add(paidPid);
  if (paidOid != null) c.createdOrderIds.add(paidOid);

  Map<String, dynamic>? paidRow;
  Map<String, num>? wPaid;
  if (paidOid != null) {
    await c.ensureChat(paidPid ?? pid);
    await c.rest('PATCH', 'orders?id=eq.$paidOid', jwt: c.sellerJwt, body: {
      'shipping_method': 'entrega em mão',
    });
    await c.rest(
      'PATCH',
      'orders?id=eq.$paidOid',
      jwt: c.sellerJwt,
      body: {'status': 'enviado'},
    );
    await c.rest(
      'PATCH',
      'orders?id=eq.$paidOid',
      jwt: c.buyerJwt,
      body: {'status': 'concluido'},
    );
    paidRow = await c.orderRow(paidOid);
    wPaid = await c.wallets();
    c.note('p5.concluido', 'após mão concluido', paidRow, lens: 'P5');

    final rel = c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': paidOid,
    }, jwt: c.sellerJwt);
    final refW = c.rpc('batata_refund_buyer_wallet_for_order', {
      'p_order_id': paidOid,
    }, jwt: c.buyerJwt);
    final refE = c.edge('refund-order', {'order_id': paidOid}, jwt: c.sellerJwt);
    final relB2 = c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': paidOid,
    }, jwt: c.buyer2Jwt);
    final raced = await Future.wait([rel, refW, refE, relB2]);
    c.note('p5.race', 'release∥refund-wallet∥refund-order∥release B2', {
      'rel': raced[0].brief,
      'refW': raced[1].brief,
      'refE': raced[2].brief,
      'relB2': raced[3].brief,
    }, lens: 'P5');

    final afterRace = await c.orderRow(paidOid);
    final w1 = await c.wallets();
    final dBuyer = (w1['buyer'] ?? 0) - (wPaid['buyer'] ?? 0);
    final dSeller = (w1['seller'] ?? 0) - (wPaid['seller'] ?? 0);
    c.note('p5.delta', 'Δwallet race', {
      'dBuyer': dBuyer,
      'dSeller': dSeller,
      'refund_id': afterRace?['stripe_refund_id'],
      'release_at': afterRace?['wallet_release_processed_at'],
      'refund_at': afterRace?['wallet_refund_processed_at'],
    }, lens: 'P10');

    // P0 se seller creditado E buyer reembolsado Stripe/wallet no mesmo ciclo sem clawback.
    final stripeRefunded = (afterRace?['stripe_refund_id'] ?? '').toString().isNotEmpty;
    final sellerReleased =
        (afterRace?['wallet_release_processed_at'] ?? '').toString().isNotEmpty;
    if (stripeRefunded && sellerReleased && dSeller > 0.01 && dBuyer >= 0) {
      c.hold(
        id: 'RTP-P5-001',
        lens: 'P5+P10',
        severity: 'P0',
        title: 'Race refund Stripe + release wallet: dinheiro nos dois lados',
        actor: 'seller refund-order ∥ release RPC',
        pre: 'order Stripe TEST concluido mão $paidOid',
        repro: 'Future.wait release + refund-wallet + refund-order',
        expected: 'um lado só; clawback se ambos',
        obtained: {
          'dBuyer': dBuyer,
          'dSeller': dSeller,
          'order': afterRace,
        },
      );
    }

    // P4: buyer2 confirma / disputa a order paga de buyer1
    final concB2 = await c.rest(
      'PATCH',
      'orders?id=eq.$paidOid',
      jwt: c.buyer2Jwt,
      body: {'status': 'concluido'},
    );
    c.note('p4.patch.b2', 'buyer2 PATCH concluido order alheia', concB2.brief,
        lens: 'P4');
  }

  // =====================================================================
  // P7 — saco pago: refund 1 linha
  // =====================================================================
  final bag = await c.e2e('setup_paid_bag', {});
  c.note('p7.bag', 'setup_paid_bag', bag.brief, lens: 'P7');
  final bagMap = bag.map ?? {};
  String? bagOidA = (bagMap['order_a_id'] ??
          bagMap['order_id_a'] ??
          (bagMap['orders'] is List && (bagMap['orders'] as List).isNotEmpty
              ? ((bagMap['orders'] as List).first as Map)['id']
              : null))
      ?.toString();
  if (bagOidA == null && bagMap['order_id'] != null) {
    bagOidA = bagMap['order_id'].toString();
  }
  List<dynamic> bagOrders = [];
  if (bagMap['orders'] is List) bagOrders = bagMap['orders'] as List;
  if (bagOrders.length >= 2) {
    final oa = (bagOrders[0] as Map)['id']?.toString();
    final ob = (bagOrders[1] as Map)['id']?.toString();
    if (oa != null) c.createdOrderIds.add(oa);
    if (ob != null) c.createdOrderIds.add(ob);
    final refLine = oa == null
        ? null
        : await c.edge('refund-order', {'order_id': oa}, jwt: c.sellerJwt);
    c.note('p7.refund.line', 'refund linha A do saco', refLine?.brief, lens: 'P7');
    final oaAfter = oa == null ? null : await c.orderRow(oa);
    final obAfter = ob == null ? null : await c.orderRow(ob);
    if (refLine?.ok == true &&
        (oaAfter?['stripe_refund_id'] ?? '').toString().isNotEmpty &&
        (obAfter?['status'] ?? '').toString().toLowerCase() != 'pago' &&
        (obAfter?['stripe_refund_id'] ?? '').toString().isNotEmpty) {
      c.hold(
        id: 'RTP-P7-001',
        lens: 'P7',
        severity: 'P1',
        title: 'Refund linha A do saco anula também a linha B',
        actor: 'seller refund-order A',
        pre: 'setup_paid_bag A+B mesmo PI',
        repro: 'refund-order $oa',
        expected: 'só A reembolsada; B continua paga',
        obtained: {'A': oaAfter, 'B': obAfter},
      );
    }
  }

  // Disputa JWT em order paga
  if (paidOid != null) {
    final disp = await c.rest('POST', 'disputes', jwt: c.buyerJwt, body: {
      'order_id': paidOid,
      'opened_by': c.buyerId,
      'reason': '$prefix chain',
      'status': 'aberta',
    });
    c.note('p5.dispute', 'INSERT dispute', disp.brief, lens: 'P5');
    final refDisp = await c.edge(
      'refund-order',
      {'order_id': paidOid},
      jwt: c.sellerJwt,
    );
    c.note('p5.refund.disp', 'refund com disputa', refDisp.brief, lens: 'P5');
  }

  // Offer accept + checkout (P2/P8)
  final offer = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': pid,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': 1.0,
    'status': 'pending',
  });
  c.note('p8.offer.ins', 'INSERT offer 1€', offer.brief, lens: 'P8');
  if (offer.firstId != null) {
    final acc = await c.rest(
      'PATCH',
      'product_offers?id=eq.${offer.firstId}',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    c.note('p8.offer.acc', 'seller accept 1€', acc.brief, lens: 'P8');
  }

  final wEnd = await c.wallets();
  c.note('wEnd', 'wallets fim', {'w0': w0, 'wEnd': wEnd}, lens: 'P10');

  final out = {
    'auditor': 'REDTEAM_BLIND_P_COMPOSICAO_CAIXA_v1',
    'prefix': prefix,
    'frozen_at': DateTime.now().toUtc().toIso8601String(),
    'actors': {
      'buyer': c.buyerId,
      'seller': c.sellerId,
      'buyer2': c.buyer2Id,
      'seller2': c.seller2Id,
    },
    'w0': w0,
    'wEnd': wEnd,
    'findings': c.findings,
    'notes': c.notes,
    'products': c.createdProductIds,
    'orders': c.createdOrderIds,
    'paid_order': paidOid,
    'bag': bagMap.keys.toList(),
  };
  await dumpJson('${outDir()}/probe.json', out);
  stdout.writeln('FINDINGS ${c.findings.length}');
  for (final f in c.findings) {
    stdout.writeln('  ${f['severity']} ${f['id']} ${f['title']}');
  }
}
