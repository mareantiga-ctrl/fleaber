/// Parallel C — Pass 1: Poço 1 caixa + autoridade JWT + captura TEST.
import 'dart:convert';
import 'dart:io';
import '_rtc.dart';

String jclip(Object? v, [int n = 220]) => clip('$v', n);

Future<void> main() async {
  final c = Rtc(loadEnv());
  await c.boot();
  stdout.writeln('boot ${c.notes}');

  final bJwt = c.buyerJwt!;
  final sJwt = c.sellerJwt!;
  final bId = c.buyerId!;
  final sId = c.sellerId!;

  // -------------------------------------------------------------------------
  // A — anon / JWT mint wallet / money cols
  // -------------------------------------------------------------------------
  for (final ident in [
    ['anon', null],
    ['buyer', bJwt],
    ['seller', sJwt],
    if (c.freshJwt != null) ['fresh', c.freshJwt],
  ]) {
    final name = ident[0] as String;
    final tok = ident[1] as String?;
    final wPatch = await c.rest(
      'PATCH',
      'wallets',
      token: tok,
      query: 'id=eq.$bId',
      prefer: 'return=representation',
      body: {'balance': 9999},
    );
    c.rec(
      id: 'A.wallet.patch.$name',
      surface: 'wallets',
      attack: 'PATCH balance=9999',
      identity: name,
      httpCode: wPatch['http'] as int,
      result: clip('${wPatch['raw']}', 160),
      impact: (wPatch['http'] as int) < 300 && '${wPatch['raw']}'.contains('9999')
          ? 'POSSÍVEL mint'
          : 'sem persistência',
      evidence: clip('${wPatch['raw']}', 180),
    );
    final tx = await c.rest(
      'POST',
      'wallet_transactions',
      token: tok,
      prefer: 'return=representation',
      body: {
        'wallet_id': bId,
        'amount': 50,
        'type': 'reembolso',
        'description': '$prefix mint',
      },
    );
    c.rec(
      id: 'A.wallet.tx.$name',
      surface: 'wallet_transactions',
      attack: 'INSERT reembolso 50€',
      identity: name,
      httpCode: tx['http'] as int,
      result: clip('${tx['raw']}', 160),
      impact: (tx['http'] as int) < 300 ? 'INSERT aceite' : 'bloqueado',
      evidence: clip('${tx['raw']}', 180),
    );
  }

  final rpcs = <String, Object?>{
    'batata_credit_wallet_once': {
      'p_user_id': bId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 10,
      'p_type': 'reembolso',
      'p_description': prefix,
    },
    'batata_release_seller_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_refund_buyer_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_wallet_payout_debit': {
      'p_user_id': sId,
      'p_amount_cents': 100,
      'p_idempotency_key': '${prefix}_payout',
    },
    'batata_admin_resolve_dispute': {
      'p_dispute_id': '00000000-0000-0000-0000-000000000001',
      'p_resolution': 'aprovada',
      'p_note': prefix,
    },
    'batata_process_partial_refund_dispute': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 5,
    },
    'batata_send_live_tip_from_wallet': {
      'p_live_id': '00000000-0000-0000-0000-000000000001',
      'p_seller_id': sId,
      'p_amount': 1,
    },
    'batata_create_live_tip_pending': {
      'p_live_id': '00000000-0000-0000-0000-000000000001',
      'p_seller_id': sId,
      'p_amount': 1,
      'p_message': prefix,
    },
  };

  for (final e in rpcs.entries) {
    for (final ident in [
      ['anon', null],
      ['buyer', bJwt],
      ['seller', sJwt],
    ]) {
      final name = ident[0] as String;
      final tok = ident[1] as String?;
      final r = await c.rpc(e.key, e.value, token: tok);
      final http = r['http'] as int;
      c.rec(
        id: 'A.rpc.${e.key}.$name',
        surface: 'rpc/${e.key}',
        attack: 'EXECUTE JWT/anon',
        identity: name,
        httpCode: http,
        result: clip('${r['raw']}', 160),
        impact: http == 200 ? 'RPC executou' : 'negado/erro',
        evidence: clip('${r['raw']}', 180),
      );
    }
  }

  // -------------------------------------------------------------------------
  // B — produto + order hostil (preço, qty, status, PI, offer)
  // -------------------------------------------------------------------------
  final pid = await c.createProduct(
    token: sJwt,
    seller: sId,
    title: '$prefix caixa 12€',
    price: 12,
    qty: 3,
  );
  if (pid == null) {
    c.gaps.add('seller não criou produto — abort caixa JWT');
    await c.dump(
        'tool/redteam_parallel_c_20260831T0734/out/pass1.json');
    stdout.writeln('FAIL create product');
    return;
  }

  final hostileOrder = await c.createOrder(
    token: bJwt,
    buyer: bId,
    seller: sId,
    productId: pid,
    qty: 1,
    status: 'pago',
    payment: 'Pagamento na app',
    extra: {
      'price_total': 0.5,
      'amount_paid_cents': 50,
      'contract_unit_cents': 50,
      'contract_qty': 1,
      'stripe_payment_intent_id': 'pi_rtc_fake',
      'quantity': 1,
    },
  );
  final oidHostile = c.createdOrderIds.isNotEmpty
      ? (hostileOrder['json'] is List
          ? (hostileOrder['json'] as List).first['id']?.toString()
          : (hostileOrder['json'] is Map
              ? (hostileOrder['json'] as Map)['id']?.toString()
              : null))
      : null;
  Map<String, dynamic> rowH = {};
  if (oidHostile != null) {
    rowH = await c.observeOrder(oidHostile);
  }
  c.rec(
    id: 'B.order.insert.hostile',
    surface: 'orders',
    attack: 'INSERT status=pago amount_paid=50 contract=50¢ price=0.50',
    identity: 'buyer',
    httpCode: hostileOrder['http'] as int,
    result:
        'status=${rowH['status']} paid=${rowH['amount_paid_cents']} unit=${rowH['contract_unit_cents']} total=${rowH['price_total']} pi=${rowH['stripe_payment_intent_id']}',
    impact: 'selo vs hostil',
    evidence: jsonEncode(rowH),
  );

  final qty9 = await c.createOrder(
    token: bJwt,
    buyer: bId,
    seller: sId,
    productId: pid,
    qty: 9,
    extra: {'price_total': 1},
  );
  final oidQty = (qty9['json'] is List && (qty9['json'] as List).isNotEmpty)
      ? (qty9['json'] as List).first['id']?.toString()
      : null;
  final rowQ = oidQty != null ? await c.observeOrder(oidQty) : {};
  c.rec(
    id: 'B.order.insert.qty9',
    surface: 'orders',
    attack: 'INSERT qty=9 stock=3',
    identity: 'buyer',
    httpCode: qty9['http'] as int,
    result: oidQty == null
        ? clip('${qty9['raw']}', 160)
        : 'qty=${rowQ['quantity']} contract_qty=${rowQ['contract_qty']} status=${rowQ['status']}',
    impact: oidQty != null && (rowQ['quantity'] == 9)
        ? 'qty 9 persistida em stock 3'
        : 'bloqueado ou selado',
    evidence: oidQty == null ? clip('${qty9['raw']}') : jsonEncode(rowQ),
  );

  final proposta = await c.createOrder(
    token: bJwt,
    buyer: bId,
    seller: sId,
    productId: pid,
    extra: {
      'payment_method': 'proposta aceite',
      'price_total': 0.5,
    },
  );
  final oidProp = (proposta['json'] is List &&
          (proposta['json'] as List).isNotEmpty)
      ? (proposta['json'] as List).first['id']?.toString()
      : null;
  final rowP = oidProp != null ? await c.observeOrder(oidProp) : {};
  c.rec(
    id: 'B.order.insert.proposta',
    surface: 'orders',
    attack: 'INSERT payment_method=proposta aceite price_total=0.50 sem oferta',
    identity: 'buyer',
    httpCode: proposta['http'] as int,
    result: oidProp == null
        ? clip('${proposta['raw']}', 160)
        : 'unit=${rowP['contract_unit_cents']} total=${rowP['price_total']} pm=${rowP['payment_method']}',
    impact: (asNum(rowP['contract_unit_cents']) ?? 0) < 1200 && oidProp != null
        ? 'contrato abaixo do catálogo'
        : 'catálogo prevaleceu ou bloqueado',
    evidence: oidProp == null ? clip('${proposta['raw']}') : jsonEncode(rowP),
  );

  // seller ghost: order for lab buyer
  final ghost = await c.createOrder(
    token: sJwt,
    buyer: bId,
    seller: sId,
    productId: pid,
    status: 'pago',
    extra: {'amount_paid_cents': 1200, 'price_total': 12},
  );
  c.rec(
    id: 'B.order.seller.ghost',
    surface: 'orders',
    attack: 'seller INSERT buyer=lab status=pago',
    identity: 'seller',
    httpCode: ghost['http'] as int,
    result: clip('${ghost['raw']}', 180),
    impact: (ghost['http'] as int) < 300 ? 'ghost insert' : 'bloqueado',
    evidence: clip('${ghost['raw']}', 200),
  );

  // PATCH money as buyer/seller
  if (oidHostile != null) {
    final patchB = await c.rest(
      'PATCH',
      'orders',
      token: bJwt,
      query: 'id=eq.$oidHostile',
      prefer: 'return=representation',
      body: {'amount_paid_cents': 1, 'status': 'pago', 'price_total': 0.01},
    );
    c.rec(
      id: 'B.order.patch.buyer.money',
      surface: 'orders',
      attack: 'PATCH amount_paid/status/price',
      identity: 'buyer',
      httpCode: patchB['http'] as int,
      result: clip('${patchB['raw']}', 160),
      impact: (patchB['http'] as int) < 300 && '${patchB['raw']}'.contains('"pago"')
          ? 'PATCH money'
          : 'bloqueado',
      evidence: clip('${patchB['raw']}', 180),
    );
    final patchPm = await c.rest(
      'PATCH',
      'orders',
      token: bJwt,
      query: 'id=eq.$oidHostile',
      prefer: 'return=representation',
      body: {'payment_method': 'MB WAY'},
    );
    c.rec(
      id: 'B.order.patch.pm',
      surface: 'orders',
      attack: 'PATCH payment_method → MB WAY',
      identity: 'buyer',
      httpCode: patchPm['http'] as int,
      result: clip('${patchPm['raw']}', 160),
      impact: (patchPm['http'] as int) < 300 ? 'trocou método' : 'bloqueado',
      evidence: clip('${patchPm['raw']}', 180),
    );
  }

  // -------------------------------------------------------------------------
  // C — checkout quote vs body hostil + catálogo depois do contrato
  // -------------------------------------------------------------------------
  final oidPay = await () async {
    final r = await c.createOrder(
      token: bJwt,
      buyer: bId,
      seller: sId,
      productId: pid,
      shipping: 'entrega em mão',
    );
    if (r['json'] is List && (r['json'] as List).isNotEmpty) {
      return (r['json'] as List).first['id']?.toString();
    }
    return null;
  }();

  if (oidPay != null) {
    final ckLow = await c.checkout(
      token: bJwt,
      buyer: bId,
      orderId: oidPay,
      extra: {
        'amount': 50,
        'quantity': 99,
        'item_price': 0.5,
        'shipping': 0,
        'protection_fee': 0,
        'shipping_method': 'hand',
        'product_id': pid,
      },
    );
    final amtLow = c.serverAmount(ckLow);
    c.rec(
      id: 'C.checkout.underpay.body',
      surface: 'create-payment-intent',
      attack: 'POST amount=50 qty=99 item_price=0.5',
      identity: 'buyer',
      httpCode: ckLow['http'] as int,
      result: 'server=${amtLow ?? 'n/a'} ${clip('${ckLow['raw']}', 140)}',
      impact: (amtLow != null && amtLow <= 100)
          ? 'Session barata'
          : 'quote servidor',
      evidence: clip('${ckLow['raw']}', 220),
    );

    final ckShip = await c.checkout(
      token: bJwt,
      buyer: bId,
      orderId: oidPay,
      extra: {'shipping_method': 'hand', 'amount': 1},
    );
    c.rec(
      id: 'C.checkout.ship.hand_vs_sealed',
      surface: 'create-payment-intent',
      attack: 'body shipping=hand (order já selada mão)',
      identity: 'buyer',
      httpCode: ckShip['http'] as int,
      result: 'server=${c.serverAmount(ckShip)} ${clip('${ckShip['raw']}', 120)}',
      impact: 'quote',
      evidence: clip('${ckShip['raw']}', 200),
    );

    // seller drops catalog price after contract
    final drop = await c.rest(
      'PATCH',
      'products',
      token: sJwt,
      query: 'id=eq.$pid',
      prefer: 'return=representation',
      body: {'price': 1},
    );
    c.rec(
      id: 'C.catalog.drop.after.contract',
      surface: 'products',
      attack: 'seller PATCH price 12→1 após order',
      identity: 'seller',
      httpCode: drop['http'] as int,
      result: clip('${drop['raw']}', 120),
      impact: 'catálogo mutado',
      evidence: clip('${drop['raw']}', 160),
    );
    final ckAfter = await c.checkout(
      token: bJwt,
      buyer: bId,
      orderId: oidPay,
      extra: {'shipping_method': 'hand'},
    );
    final amtAfter = c.serverAmount(ckAfter);
    final rowAfter = await c.observeOrder(oidPay);
    c.rec(
      id: 'C.checkout.after.catalog.drop',
      surface: 'create-payment-intent',
      attack: 'checkout após price=1€ (contrato 12€)',
      identity: 'buyer',
      httpCode: ckAfter['http'] as int,
      result:
          'server=$amtAfter contract_unit=${rowAfter['contract_unit_cents']}',
      impact: (amtAfter != null && amtAfter < 500)
          ? 'cobrou catálogo vivo'
          : 'cobrou contrato',
      evidence:
          'ck=${clip('${ckAfter['raw']}', 180)} order=${jsonEncode(rowAfter)}',
    );

    // restore catalog for later
    await c.rest(
      'PATCH',
      'products',
      token: sJwt,
      query: 'id=eq.$pid',
      body: {'price': 12},
      service: false,
    );

    // foreign buyer_id
    final ckForeign = await c.checkout(
      token: bJwt,
      buyer: sId,
      orderId: oidPay,
    );
    c.rec(
      id: 'C.checkout.foreign.buyer_id',
      surface: 'create-payment-intent',
      attack: 'JWT buyer + body.buyer_id=seller',
      identity: 'buyer',
      httpCode: ckForeign['http'] as int,
      result: clip('${ckForeign['raw']}', 160),
      impact: (ckForeign['http'] as int) == 200
          ? 'confused deputy'
          : 'rejeitado',
      evidence: clip('${ckForeign['raw']}', 180),
    );

    // prize_shipping false order
    final ckPrize = await c.checkout(
      token: bJwt,
      buyer: bId,
      orderId: oidPay,
      extra: {'prize_shipping': true, 'shipping_method': 'carrier'},
    );
    c.rec(
      id: 'C.checkout.fake.prize',
      surface: 'create-payment-intent',
      attack: 'prize_shipping=true em order não-rifa',
      identity: 'buyer',
      httpCode: ckPrize['http'] as int,
      result: 'server=${c.serverAmount(ckPrize)} ${clip('${ckPrize['raw']}', 120)}',
      impact: (c.serverAmount(ckPrize) != null &&
              (c.serverAmount(ckPrize)! < 500))
          ? 'prize quote barata'
          : 'bloqueado ou full quote',
      evidence: clip('${ckPrize['raw']}', 180),
    );

    // GET settle fake / unpaid
    final getFake = await c.edge(
      'create-payment-intent',
      method: 'GET',
      query: 'checkout_return=success&session_id=cs_test_rtc_fake',
    );
    c.rec(
      id: 'C.settle.get.fake',
      surface: 'create-payment-intent GET',
      attack: 'session_id inventado',
      identity: 'anon',
      httpCode: getFake['http'] as int,
      result: clip('${getFake['raw']}', 160),
      impact: (getFake['http'] as int) < 400 ? 'settle sem Session' : 'fail-closed',
      evidence: clip('${getFake['raw']}', 180),
    );

    final sid = c.sessionId(ckAfter) ?? c.sessionId(ckLow);
    if (sid != null && sid.startsWith('cs_')) {
      final g1 = await c.edge(
        'create-payment-intent',
        method: 'GET',
        query: 'checkout_return=success&session_id=$sid',
      );
      final before = await c.observeOrder(oidPay);
      final g2 = await c.edge(
        'create-payment-intent',
        method: 'GET',
        query: 'checkout_return=success&session_id=$sid',
      );
      final after = await c.observeOrder(oidPay);
      c.rec(
        id: 'C.settle.get.unpaid.replay',
        surface: 'create-payment-intent GET',
        attack: 'GET settle Session não paga ×2',
        identity: 'anon',
        httpCode: g1['http'] as int,
        result:
            'g1=${g1['http']} g2=${g2['http']} status=${before['status']}→${after['status']} paid=${after['amount_paid_cents']}',
        impact: after['status'] == 'pago'
            ? 'marcou pago sem captura'
            : 'não liquidou unpaid',
        evidence:
            'g1=${clip('${g1['raw']}', 80)} g2=${clip('${g2['raw']}', 80)}',
      );
    }

    // fase2 settle as buyer JWT
    final e2eJwt = await c.edge(
      'create-payment-intent',
      query: 'fase2_e2e_settle=1',
      token: bJwt,
      body: {
        'order_id': oidPay,
        'payment_intent_id': 'pi_rtc_fake',
        'product_id': pid,
      },
    );
    c.rec(
      id: 'C.settle.e2e.as.buyer',
      surface: 'create-payment-intent?fase2_e2e_settle',
      attack: 'POST settle com JWT buyer',
      identity: 'buyer',
      httpCode: e2eJwt['http'] as int,
      result: clip('${e2eJwt['raw']}', 160),
      impact: (e2eJwt['http'] as int) == 200 ? 'buyer settle' : 'negado',
      evidence: clip('${e2eJwt['raw']}', 180),
    );
  }

  // off-platform then stripe
  final offPid = await c.createProduct(
    token: sJwt,
    seller: sId,
    title: '$prefix offplat',
    price: 8,
    qty: 1,
  );
  if (offPid != null) {
    final offOrd = await c.createOrder(
      token: bJwt,
      buyer: bId,
      seller: sId,
      productId: offPid,
      payment: 'MB WAY',
    );
    final oidOff = (offOrd['json'] is List &&
            (offOrd['json'] as List).isNotEmpty)
        ? (offOrd['json'] as List).first['id']?.toString()
        : null;
    if (oidOff != null) {
      final ckOff = await c.checkout(
        token: bJwt,
        buyer: bId,
        orderId: oidOff,
      );
      c.rec(
        id: 'C.offplatform.then.stripe',
        surface: 'create-payment-intent',
        attack: 'order MB WAY → Checkout Stripe',
        identity: 'buyer',
        httpCode: ckOff['http'] as int,
        result: clip('${ckOff['raw']}', 160),
        impact: (ckOff['http'] as int) == 200
            ? 'Stripe em off-platform'
            : 'bloqueado',
        evidence: clip('${ckOff['raw']}', 180),
      );
      final markPaid = await c.rest(
        'PATCH',
        'orders',
        token: sJwt,
        query: 'id=eq.$oidOff',
        prefer: 'return=representation',
        body: {'status': 'pago'},
      );
      final rowOff = await c.observeOrder(oidOff);
      final wb = await c.walletBalance(sId);
      c.rec(
        id: 'C.offplatform.seller.pago',
        surface: 'orders',
        attack: 'seller PATCH status=pago (MB WAY)',
        identity: 'seller',
        httpCode: markPaid['http'] as int,
        result:
            'status=${rowOff['status']} paid=${rowOff['amount_paid_cents']} wallet_seller=$wb ${clip('${markPaid['raw']}', 80)}',
        impact: rowOff['status'] == 'pago'
            ? 'seller liquidou off-platform'
            : 'FSM bloqueou ou outro estado',
        evidence: jsonEncode(rowOff),
      );
    }
  }

  // -------------------------------------------------------------------------
  // D — captura TEST real via e2e + contabilidade + refund
  // -------------------------------------------------------------------------
  final wBuyer0 = await c.walletBalance(bId);
  final wSeller0 = await c.walletBalance(sId);
  final paid = await c.e2e({
    'probe': 'setup_paid_order',
    'buyer_id': bId,
    'seller_id': sId,
    'initial_qty': 2,
  });
  c.rec(
    id: 'D.e2e.setup_paid_order',
    surface: 'sec-fase2-e2e-oversell',
    attack: 'PI pm_card_visa + settle',
    identity: 'service_fixture',
    httpCode: paid['http'] as int,
    result: clip('${paid['raw']}', 200),
    impact: 'captura TEST',
    evidence: clip('${paid['raw']}', 240),
  );
  final paidJson = paid['json'];
  String? paidOrderId;
  String? paidProductId;
  String? paidPi;
  if (paidJson is Map) {
    paidOrderId = paidJson['order_id']?.toString();
    paidProductId = paidJson['product_id']?.toString();
    paidPi = paidJson['payment_intent_id']?.toString();
    if (paidOrderId != null) c.createdOrderIds.add(paidOrderId);
    if (paidProductId != null) c.createdProductIds.add(paidProductId);
  }

  Map<String, dynamic> paidRow = {};
  Map<String, dynamic> paidProd = {};
  if (paidOrderId != null) {
    paidRow = await c.observeOrder(paidOrderId);
    if (paidProductId != null) paidProd = await c.observeProduct(paidProductId);
    final txs = await c.walletTx(orderId: paidOrderId);
    c.rec(
      id: 'D.accounting.after.capture',
      surface: 'orders+wallet',
      attack: 'observar pós-captura',
      identity: 'service_observe',
      httpCode: 200,
      result:
          'status=${paidRow['status']} paid_cents=${paidRow['amount_paid_cents']} stock_applied=${paidRow['stock_units_applied']} prod_qty=${paidProd['quantity']} is_sold=${paidProd['is_sold']} txs=${txs.length}',
      impact: 'contabilidade',
      evidence:
          'order=${jsonEncode(paidRow)} product=${jsonEncode(paidProd)} tx=${jsonEncode(txs)} wallets b=$wBuyer0→${await c.walletBalance(bId)} s=$wSeller0→${await c.walletBalance(sId)}',
    );
  }

  // refund as buyer
  if (paidOrderId != null) {
    final refB = await c.edge(
      'refund-order',
      token: bJwt,
      body: {'order_id': paidOrderId},
    );
    c.rec(
      id: 'D.refund.as.buyer',
      surface: 'refund-order',
      attack: 'POST order pago como buyer',
      identity: 'buyer',
      httpCode: refB['http'] as int,
      result: clip('${refB['raw']}', 180),
      impact: (refB['http'] as int) == 200 && '${refB['raw']}'.contains('"ok":true')
          ? 'buyer refund'
          : 'negado',
      evidence: clip('${refB['raw']}', 200),
    );

    final relB = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': paidOrderId},
      token: bJwt,
    );
    c.rec(
      id: 'D.release.while.pago',
      surface: 'rpc/batata_release_seller_wallet_for_order',
      attack: 'release em status pago (não concluido)',
      identity: 'buyer',
      httpCode: relB['http'] as int,
      result: clip('${relB['raw']}', 160),
      impact: '${relB['json']}' == 'true' ? 'creditou seller cedo' : 'false/erro',
      evidence: clip('${relB['raw']}', 180),
    );

    final relS = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': paidOrderId},
      token: sJwt,
    );
    c.rec(
      id: 'D.release.as.seller.pago',
      surface: 'rpc/batata_release_seller_wallet_for_order',
      attack: 'seller release em pago',
      identity: 'seller',
      httpCode: relS['http'] as int,
      result: clip('${relS['raw']}', 160),
      impact: '${relS['json']}' == 'true' ? 'seller mintou' : 'false/erro',
      evidence: clip('${relS['raw']}', 180),
    );

    // buyer dispute
    final disp = await c.rest(
      'POST',
      'order_disputes',
      token: bJwt,
      prefer: 'return=representation',
      body: {
        'order_id': paidOrderId,
        'buyer_id': bId,
        'seller_id': sId,
        'reason': prefix,
        'status': 'aberta',
      },
    );
    c.rec(
      id: 'D.dispute.insert.buyer',
      surface: 'order_disputes',
      attack: 'INSERT disputa em order pago',
      identity: 'buyer',
      httpCode: disp['http'] as int,
      result: clip('${disp['raw']}', 180),
      impact: (disp['http'] as int) < 300 ? 'disputa aberta' : 'bloqueado',
      evidence: clip('${disp['raw']}', 200),
    );
    String? dispId;
    if (disp['json'] is List && (disp['json'] as List).isNotEmpty) {
      dispId = (disp['json'] as List).first['id']?.toString();
    } else if (disp['json'] is Map) {
      dispId = (disp['json'] as Map)['id']?.toString();
    }

    if (dispId != null) {
      final resolveBuyer = await c.rpc(
        'batata_admin_resolve_dispute',
        {
          'p_dispute_id': dispId,
          'p_resolution': 'aprovada',
          'p_note': prefix,
        },
        token: bJwt,
      );
      c.rec(
        id: 'D.dispute.resolve.buyer',
        surface: 'rpc/batata_admin_resolve_dispute',
        attack: 'buyer resolve aprovada',
        identity: 'buyer',
        httpCode: resolveBuyer['http'] as int,
        result: clip('${resolveBuyer['raw']}', 160),
        impact: (resolveBuyer['http'] as int) == 200
            ? 'buyer admin'
            : 'negado',
        evidence: clip('${resolveBuyer['raw']}', 180),
      );
      final partial = await c.rpc(
        'batata_process_partial_refund_dispute',
        {'p_order_id': paidOrderId, 'p_amount': 100},
        token: bJwt,
      );
      c.rec(
        id: 'D.dispute.partial.100eur',
        surface: 'rpc/batata_process_partial_refund_dispute',
        attack: 'p_amount=100 (acima captura ~5.90)',
        identity: 'buyer',
        httpCode: partial['http'] as int,
        result: clip('${partial['raw']}', 180),
        impact: (partial['http'] as int) == 200
            ? 'partial executou'
            : 'erro/cap',
        evidence: clip('${partial['raw']}', 200),
      );
    }

    final wB1 = await c.walletBalance(bId);
    final wS1 = await c.walletBalance(sId);
    final txs2 = await c.walletTx(orderId: paidOrderId);
    c.rec(
      id: 'D.wallets.after.dispute.attempts',
      surface: 'wallets',
      attack: 'Δwallet após disputa/refund tentativas',
      identity: 'service_observe',
      httpCode: 200,
      result: 'buyer $wBuyer0→$wB1 seller $wSeller0→$wS1 txs=${jsonEncode(txs2)}',
      impact: 'contabilidade',
      evidence:
          'order=${jsonEncode(await c.observeOrder(paidOrderId))} pi=$paidPi',
    );

    // seller refund (real Stripe TEST)
    final refS = await c.edge(
      'refund-order',
      token: sJwt,
      body: {'order_id': paidOrderId},
    );
    final afterRef = await c.observeOrder(paidOrderId);
    final wB2 = await c.walletBalance(bId);
    final wS2 = await c.walletBalance(sId);
    c.rec(
      id: 'D.refund.as.seller',
      surface: 'refund-order',
      attack: 'seller refund order pago TEST',
      identity: 'seller',
      httpCode: refS['http'] as int,
      result:
          'http=${refS['http']} ${clip('${refS['raw']}', 140)} status=${afterRef['status']} refund_id=${afterRef['stripe_refund_id']} wallets b=$wB1→$wB2 s=$wS1→$wS2',
      impact: 'refund Stripe',
      evidence: clip('${refS['raw']}', 220),
    );

    // refund replay
    final refS2 = await c.edge(
      'refund-order',
      token: sJwt,
      body: {'order_id': paidOrderId},
    );
    c.rec(
      id: 'D.refund.replay',
      surface: 'refund-order',
      attack: '2º refund mesma order',
      identity: 'seller',
      httpCode: refS2['http'] as int,
      result: clip('${refS2['raw']}', 180),
      impact: 'idempotência',
      evidence: clip('${refS2['raw']}', 200),
    );

    // release after refund
    final relAfter = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': paidOrderId},
      token: bJwt,
    );
    final wS3 = await c.walletBalance(sId);
    c.rec(
      id: 'D.release.after.refund',
      surface: 'rpc/release',
      attack: 'release após refund Stripe',
      identity: 'buyer',
      httpCode: relAfter['http'] as int,
      result: 'rpc=${clip('${relAfter['raw']}', 80)} seller_wallet=$wS2→$wS3',
      impact: (wS3 != null && wS2 != null && wS3 > wS2)
          ? 'mint após refund'
          : 'sem mint',
      evidence: clip('${relAfter['raw']}', 160),
      sev: (wS3 != null && wS2 != null && wS3 > wS2) ? 'P0' : '—',
    );
  }

  // bag paid accounting
  final bag = await c.e2e({
    'probe': 'setup_paid_bag',
    'buyer_id': bId,
    'seller_id': sId,
  });
  c.rec(
    id: 'D.e2e.setup_paid_bag',
    surface: 'sec-fase2-e2e-oversell',
    attack: 'bag 2 linhas PI único',
    identity: 'service_fixture',
    httpCode: bag['http'] as int,
    result: clip('${bag['raw']}', 220),
    impact: 'captura bag',
    evidence: clip('${bag['raw']}', 260),
  );
  if (bag['json'] is Map) {
    final bj = bag['json'] as Map;
    final orders = bj['orders'] ?? bj['settle_body'];
    c.notes.add('bag invariant ${bj['invariant_sum_eq_pi']} orders=$orders');
    // try refund one line
    String? lineA;
    if (bj['order_a_id'] != null) lineA = bj['order_a_id'].toString();
    if (lineA == null && bj['orders'] is List && (bj['orders'] as List).isNotEmpty) {
      lineA = (bj['orders'] as List).first['id']?.toString();
    }
    if (lineA != null) {
      c.createdOrderIds.add(lineA);
      final refLine = await c.edge(
        'refund-order',
        token: sJwt,
        body: {'order_id': lineA},
      );
      c.rec(
        id: 'D.bag.refund.one.line',
        surface: 'refund-order',
        attack: 'refund 1 linha de bag partilhando PI',
        identity: 'seller',
        httpCode: refLine['http'] as int,
        result: clip('${refLine['raw']}', 180),
        impact: 'parcial bag',
        evidence: clip('${refLine['raw']}', 200),
      );
    }
  }

  // payout
  final pay0 = await c.edge(
    'create-connect-account',
    token: bJwt,
    body: {
      'user_id': sId,
      'amount': 500,
      'idempotency_key': '${prefix}_po_cross',
    },
  );
  c.rec(
    id: 'D.payout.buyer.as.seller',
    surface: 'create-connect-account',
    attack: 'buyer JWT user_id=seller amount=500¢',
    identity: 'buyer',
    httpCode: pay0['http'] as int,
    result: clip('${pay0['raw']}', 180),
    impact: (pay0['http'] as int) == 200 && '${pay0['raw']}'.contains('transfer')
        ? 'payout cruzado'
        : 'negado/onboarding',
    evidence: clip('${pay0['raw']}', 200),
  );
  final payNeg = await c.edge(
    'create-connect-account',
    token: sJwt,
    body: {'amount': -100, 'idempotency_key': '${prefix}_neg'},
  );
  c.rec(
    id: 'D.payout.negative',
    surface: 'create-connect-account',
    attack: 'amount=-100',
    identity: 'seller',
    httpCode: payNeg['http'] as int,
    result: clip('${payNeg['raw']}', 160),
    impact: 'validação',
    evidence: clip('${payNeg['raw']}', 180),
  );
  final payHuge = await c.edge(
    'create-connect-account',
    token: sJwt,
    body: {
      'amount': 99999999,
      'idempotency_key': '${prefix}_huge',
    },
  );
  c.rec(
    id: 'D.payout.huge',
    surface: 'create-connect-account',
    attack: 'amount=99999999¢ vs saldo',
    identity: 'seller',
    httpCode: payHuge['http'] as int,
    result: clip('${payHuge['raw']}', 180),
    impact: 'over-debit?',
    evidence: clip('${payHuge['raw']}', 200),
  );

  // tip without live
  final tip = await c.edge(
    'create-live-tip-checkout',
    token: bJwt,
    body: {
      'seller_id': sId,
      'amount_eur': 1,
      'live_id': '00000000-0000-0000-0000-000000000001',
    },
  );
  c.rec(
    id: 'D.tip.fake.live',
    surface: 'create-live-tip-checkout',
    attack: 'tip 1€ live UUID inventado',
    identity: 'buyer',
    httpCode: tip['http'] as int,
    result: clip('${tip['raw']}', 160),
    impact: (tip['http'] as int) == 200 ? 'Session tip órfã' : 'bloqueado',
    evidence: clip('${tip['raw']}', 180),
  );

  // webhook without sig
  final wh = await c.edge(
    'stripe-webhook',
    body: {
      'type': 'checkout.session.completed',
      'data': {
        'object': {'id': 'cs_test_x', 'payment_status': 'paid'}
      }
    },
  );
  c.rec(
    id: 'D.webhook.no.sig',
    surface: 'stripe-webhook',
    attack: 'POST sem stripe-signature',
    identity: 'anon',
    httpCode: wh['http'] as int,
    result: clip('${wh['raw']}', 140),
    impact: (wh['http'] as int) == 200 ? 'webhook aberto' : 'assinatura',
    evidence: clip('${wh['raw']}', 160),
  );

  Directory('tool/redteam_parallel_c_20260831T0734/out')
      .createSync(recursive: true);
  await c.dump('tool/redteam_parallel_c_20260831T0734/out/pass1.json');
  stdout.writeln(
      'pass1 hits=${c.hits.length} findings=${c.findings.length} gaps=${c.gaps}');
  for (final h in c.hits) {
    if (h.impact.contains('POSSÍVEL') ||
        h.impact.contains('mint') ||
        h.impact.contains('ghost') ||
        h.impact.contains('Session barata') ||
        h.impact.contains('cobrou catálogo') ||
        h.impact.contains('confused') ||
        h.impact.contains('buyer refund') ||
        h.impact.contains('payout cruzado') ||
        h.impact.contains('marcou pago') ||
        h.sev == 'P0' ||
        h.sev == 'P1') {
      stdout.writeln('!! ${h.id} ${h.http} ${h.impact} ${h.result}');
    }
  }
}
