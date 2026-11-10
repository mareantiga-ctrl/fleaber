/// PASS 2 — money, stock, Stripe TEST, races. Blind independent 20260830T1752.
/// Staging only. No production. No Fase 4. No fixes.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '_http.dart';

Future<void> main() async {
  final c = await boot();
  stdout.writeln('PASS2 boot');

  final product = await _fixtureProduct(c, qty: 1, price: 12.34, tag: 'stock1');
  if (product == null) {
    gaps.add('cannot create product');
    await _flush();
    return;
  }

  await _checkoutAmountAuthority(c, product);
  await _qtyAndStockInsert(c, product);
  await _catalogChangeAfterOrder(c, product);
  await _shippingHandBypass(c, product);
  await _dualOrderStock1(c, product);
  await _dualCheckoutSessions(c, product);
  await _offerPrice(c, product);
  await _walletReleaseRefundRpcs(c);
  await _payoutRace(c);
  await _reviewDup(c);
  await _stripeWebhookForge(c);
  await _collusionOffPlatform(c, product);

  await _flush();
}

Future<void> _flush() async {
  await dumpJson(
    'tool/redteam_blind_indep_20260830T1752/out/pass2.json',
    {
      'project': projectMust,
      'pass': 2,
      'matrix': matrix,
      'findings': findings,
      'gaps': gaps,
    },
  );
  stdout.writeln('PASS2 done matrix=${matrix.length} findings=${findings.length}');
}

Future<Map<String, dynamic>?> _fixtureProduct(
  Ctx c, {
  required int qty,
  required double price,
  required String tag,
}) async {
  final body = {
    'seller_id': c.sellerId,
    'title': '$prefix-$tag',
    'price': price,
    'quantity': qty,
    'list_on_marketplace': true,
  };
  var r = await rest(c.url, 'POST', 'products', headers: c.sellerH, body: body);
  rec(surface: 'products', attack: 'seller INSERT $tag', identity: 'seller', result: brief(r, 240));
  if (!looksOk(r)) {
    r = await rest(c.url, 'POST', 'products', headers: c.svcH, body: body);
    rec(surface: 'products', attack: 'svc fixture $tag', identity: 'service_role_observe', result: brief(r, 240));
  }
  try {
    final j = tryJson(r);
    if (j is List && j.isNotEmpty) return Map<String, dynamic>.from(j[0] as Map);
    if (j is Map) return Map<String, dynamic>.from(j);
  } catch (_) {}
  return null;
}

Future<Map<String, dynamic>?> _insertOrder(
  Ctx c, {
  required String productId,
  int qty = 1,
  Object? priceTotal,
  Object? contractCents,
  String status = 'reserva_pendente',
  String ship = 'hand',
  String pay = 'Pagamento na app',
  Map<String, dynamic>? extra,
}) async {
  final body = {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': productId,
    'quantity': qty,
    'status': status,
    'payment_method': pay,
    'shipping_method': ship,
    if (priceTotal != null) 'price_total': priceTotal,
    if (contractCents != null) 'contract_unit_cents': contractCents,
    ...?extra,
  };
  final r = await rest(c.url, 'POST', 'orders', headers: c.buyerH, body: body);
  rec(surface: 'orders', attack: 'INSERT qty=$qty pt=$priceTotal cuc=$contractCents', identity: 'buyer', result: brief(r, 280));
  if (!looksOk(r)) return null;
  final j = tryJson(r);
  if (j is List && j.isNotEmpty) return Map<String, dynamic>.from(j[0] as Map);
  if (j is Map) return Map<String, dynamic>.from(j);
  return null;
}

Future<Map<String, dynamic>?> _obsOrder(Ctx c, String id) async {
  final r = await rest(
    c.url,
    'GET',
    'orders?id=eq.$id&select=id,status,price_total,contract_unit_cents,contract_qty,quantity,amount_paid_cents,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,stock_units_applied,payment_method,shipping_method,wallet_release_processed_at,wallet_refund_processed_at',
    headers: c.svcH,
  );
  final j = tryJson(r);
  if (j is List && j.isNotEmpty) return Map<String, dynamic>.from(j[0] as Map);
  return null;
}

Future<void> _checkoutAmountAuthority(Ctx c, Map product) async {
  final pid = product['id'].toString();
  final catalog = product['price'];
  final order = await _insertOrder(c, productId: pid, priceTotal: 0.01, contractCents: 1);
  if (order == null) {
    gaps.add('order insert failed for checkout amount test');
    return;
  }
  final oid = order['id'].toString();
  final before = await _obsOrder(c, oid);

  final bodies = [
    {
      'name': 'amount_1',
      'body': {
        'buyer_id': c.buyerId,
        'order_id': oid,
        'amount': 1,
        'quantity': 99,
        'item_price': 1,
        'shipping': 0,
        'protection_fee': 0,
        'shipping_method': 'hand',
        'product_id': pid,
        'seller_id': c.sellerId,
      },
    },
    {
      'name': 'amount_match_catalog_minus',
      'body': {
        'buyer_id': c.buyerId,
        'order_id': oid,
        'amount': 50,
        'shipping_method': 'hand',
      },
    },
    {
      'name': 'prize_shipping',
      'body': {
        'buyer_id': c.buyerId,
        'order_id': oid,
        'prize_shipping': true,
        'shipping_method': 'carrier',
      },
    },
  ];

  for (final b in bodies) {
    final r = await edge(
      c.url,
      'create-payment-intent',
      b['body'],
      anon: c.anon,
      jwt: c.buyerJwt,
    );
    rec(
      surface: 'CHECKOUT',
      attack: b['name'] as String,
      identity: 'buyer',
      result: brief(r, 360),
    );
    final j = tryJson(r);
    if (looksOk(r) && j is Map) {
      rec(
        surface: 'CHECKOUT',
        attack: '${b['name']} session',
        identity: 'buyer',
        result: 'keys=${j.keys.toList()}',
        evidence: {
          'checkoutSessionId': j['checkoutSessionId'] ?? j['sessionId'],
          'amount': j['amount'] ?? j['amount_cents'] ?? j['total'],
        },
      );
    }
  }

  final after = await _obsOrder(c, oid);
  rec(
    surface: 'orders',
    attack: 'checkout amount FINAL vs catalog',
    identity: 'observe',
    result: 'catalog=$catalog before=$before after=$after',
    evidence: {'catalog': catalog, 'before': before, 'after': after},
  );

  final cuc = after?['contract_unit_cents'];
  if (cuc == 1) {
    finding(
      id: 'RT1752-P0-CONTRACT-SEALED-1',
      severity: 'P0',
      title: 'Contrato ficou 1 cêntimo após INSERT+checkout',
      actor: 'buyer JWT',
      pre: 'produto catálogo 12.34',
      repro: 'INSERT contract_unit_cents=1 + create-payment-intent',
      impact: 'autoridade de preço no contrato',
      evidence: after,
    );
  }
}

Future<void> _qtyAndStockInsert(Ctx c, Map product) async {
  final pid = product['id'].toString();
  final o = await _insertOrder(c, productId: pid, qty: 99, priceTotal: 12.34);
  if (o == null) {
    rec(surface: 'STOCK', attack: 'qty=99 insert', identity: 'buyer', result: 'blocked');
    return;
  }
  rec(
    surface: 'STOCK',
    attack: 'qty=99 FINAL',
    identity: 'buyer',
    result: 'qty=${o['quantity']} contract_qty=${o['contract_qty']}',
    evidence: o,
  );
  if (o['quantity'] == 99 || o['contract_qty'] == 99) {
    finding(
      id: 'RT1752-P1-QTY-SEAL',
      severity: 'P1',
      title: 'quantity/contract_qty=99 selado com stock=1',
      actor: 'buyer JWT',
      pre: 'product quantity=1',
      repro: 'POST orders quantity=99',
      impact: 'oversell de contrato',
      evidence: o,
    );
  }
}

Future<void> _catalogChangeAfterOrder(Ctx c, Map product) async {
  final pid = product['id'].toString();
  final o = await _insertOrder(c, productId: pid, priceTotal: 12.34);
  if (o == null) return;
  final oid = o['id'].toString();
  final sealedBefore = (await _obsOrder(c, oid))?['contract_unit_cents'];

  await rest(
    c.url,
    'PATCH',
    'products?id=eq.$pid',
    headers: c.sellerH,
    body: {'price': 0.50},
  );
  final chk = await edge(
    c.url,
    'create-payment-intent',
    {
      'buyer_id': c.buyerId,
      'order_id': oid,
      'amount': 50,
      'shipping_method': 'hand',
    },
    anon: c.anon,
    jwt: c.buyerJwt,
  );
  rec(surface: 'CHECKOUT', attack: 'after seller price=0.50', identity: 'buyer', result: brief(chk, 300));
  final after = await _obsOrder(c, oid);
  rec(
    surface: 'CONTRACT',
    attack: 'catalog change after accept',
    identity: 'observe',
    result: 'sealed_before=$sealedBefore after=${after?['contract_unit_cents']}',
  );

  // restore catalog
  await rest(
    c.url,
    'PATCH',
    'products?id=eq.$pid',
    headers: c.svcH,
    body: {'price': 12.34, 'quantity': 1},
  );
}

Future<void> _shippingHandBypass(Ctx c, Map product) async {
  final pid = product['id'].toString();
  final o = await _insertOrder(c, productId: pid, ship: 'carrier');
  if (o == null) return;
  final r = await edge(
    c.url,
    'create-payment-intent',
    {
      'buyer_id': c.buyerId,
      'order_id': o['id'],
      'shipping_method': 'hand',
      'amount': 1,
    },
    anon: c.anon,
    jwt: c.buyerJwt,
  );
  rec(
    surface: 'CHECKOUT',
    attack: 'order carrier + body hand',
    identity: 'buyer',
    result: brief(r, 300),
  );
}

Future<void> _dualOrderStock1(Ctx c, Map product) async {
  final pid = product['id'].toString();
  await rest(
    c.url,
    'PATCH',
    'products?id=eq.$pid',
    headers: c.svcH,
    body: {'quantity': 1, 'price': 12.34},
  );

  final futs = <Future<http.Response>>[];
  for (var i = 0; i < 10; i++) {
    futs.add(rest(
      c.url,
      'POST',
      'orders',
      headers: c.buyerH,
      body: {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': pid,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'hand',
      },
    ));
  }
  final rs = await Future.wait(futs);
  var ok = 0;
  final ids = <String>[];
  for (final r in rs) {
    if (looksOk(r)) {
      ok++;
      final j = tryJson(r);
      if (j is List && j.isNotEmpty) ids.add(j[0]['id'].toString());
      if (j is Map) ids.add(j['id'].toString());
    }
  }
  rec(
    surface: 'STOCK',
    attack: '10 parallel INSERT qty=1 stock=1',
    identity: 'buyer',
    result: 'ok=$ok/${rs.length} ids=${ids.length}',
  );

  // Observe product quantity
  final p = await rest(
    c.url,
    'GET',
    'products?id=eq.$pid&select=id,quantity',
    headers: c.svcH,
  );
  rec(surface: 'STOCK', attack: 'product qty after race', identity: 'observe', result: brief(p));
}

Future<void> _dualCheckoutSessions(Ctx c, Map product) async {
  final pid = product['id'].toString();
  final o = await _insertOrder(c, productId: pid);
  if (o == null) return;
  final oid = o['id'].toString();
  final futs = <Future<http.Response>>[];
  for (var i = 0; i < 8; i++) {
    futs.add(edge(
      c.url,
      'create-payment-intent',
      {
        'buyer_id': c.buyerId,
        'order_id': oid,
        'shipping_method': 'hand',
      },
      anon: c.anon,
      jwt: c.buyerJwt,
    ));
  }
  final rs = await Future.wait(futs);
  final sessions = <String>{};
  for (final r in rs) {
    rec(surface: 'CHECKOUT', attack: 'parallel session', identity: 'buyer', result: brief(r, 180));
    if (looksOk(r)) {
      final j = tryJson(r);
      if (j is Map) {
        final s = (j['checkoutSessionId'] ?? j['sessionId'] ?? j['id'] ?? '').toString();
        if (s.startsWith('cs_')) sessions.add(s);
      }
    }
  }
  rec(
    surface: 'CHECKOUT',
    attack: '8 parallel sessions unique cs_',
    identity: 'buyer',
    result: 'unique_sessions=${sessions.length}',
    evidence: sessions.toList(),
  );
  if (sessions.length >= 2) {
    finding(
      id: 'RT1752-P1-DUAL-SESSION',
      severity: 'P1',
      title: 'Duas Checkout Sessions distintas para a mesma order',
      actor: 'buyer JWT',
      pre: 'order pendente stock=1',
      repro: '8 POST create-payment-intent em paralelo',
      impact: 'duas intenções de cobrança; captura líquida depende de settle',
      evidence: {'count': sessions.length, 'ids': sessions.take(4).toList()},
    );
  }
}

Future<void> _offerPrice(Ctx c, Map product) async {
  final pid = product['id'].toString();
  final ins = await rest(
    c.url,
    'POST',
    'product_offers',
    headers: c.buyerH,
    body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'amount': 0.50,
      'status': 'pending',
    },
  );
  rec(surface: 'OFFERS', attack: 'buyer INSERT 0.50', identity: 'buyer', result: brief(ins, 240));
  String? offerId;
  try {
    final j = tryJson(ins);
    if (j is List && j.isNotEmpty) offerId = j[0]['id']?.toString();
    if (j is Map) offerId = j['id']?.toString();
  } catch (_) {}
  if (offerId == null) return;

  final self = await rest(
    c.url,
    'PATCH',
    'product_offers?id=eq.$offerId',
    headers: c.buyerH,
    body: {'status': 'accepted'},
  );
  rec(surface: 'OFFERS', attack: 'buyer self-accept', identity: 'buyer', result: brief(self));

  final accS = await rest(
    c.url,
    'PATCH',
    'product_offers?id=eq.$offerId',
    headers: c.sellerH,
    body: {'status': 'accepted'},
  );
  rec(surface: 'OFFERS', attack: 'seller accept 0.50', identity: 'seller', result: brief(accS));

  final ord = await _insertOrder(
    c,
    productId: pid,
    extra: {'product_offer_id': offerId, 'payment_method': 'proposta'},
    priceTotal: 0.50,
  );
  rec(
    surface: 'OFFERS',
    attack: 'order from offer FINAL',
    identity: 'buyer',
    result: 'cuc=${ord?['contract_unit_cents']} pt=${ord?['price_total']}',
    evidence: ord,
  );
}

Future<void> _walletReleaseRefundRpcs(Ctx c) async {
  // Grab a recent buyer order
  final g = await rest(
    c.url,
    'GET',
    'orders?buyer_id=eq.${c.buyerId}&select=id,status&order=created_at.desc&limit=3',
    headers: c.svcH,
  );
  final j = tryJson(g);
  if (j is! List) return;
  for (final row in j) {
    final id = row['id'].toString();
    final rel = await rpcRaw(
      c.url,
      'batata_release_seller_wallet_for_order',
      {'p_order_id': id},
      headers: c.buyerH,
    );
    rec(surface: 'WALLET', attack: 'buyer release $id', identity: 'buyer', result: brief(rel));
    final ref = await rpcRaw(
      c.url,
      'batata_refund_buyer_wallet_for_order',
      {'p_order_id': id},
      headers: c.buyerH,
    );
    rec(surface: 'WALLET', attack: 'buyer refund-wallet $id', identity: 'buyer', result: brief(ref));
    final relS = await rpcRaw(
      c.url,
      'batata_release_seller_wallet_for_order',
      {'p_order_id': id},
      headers: c.sellerH,
    );
    rec(surface: 'WALLET', attack: 'seller release $id', identity: 'seller', result: brief(relS));
  }
}

Future<void> _payoutRace(Ctx c) async {
  final futs = <Future<http.Response>>[];
  for (var i = 0; i < 6; i++) {
    futs.add(edge(
      c.url,
      'create-connect-account',
      {
        'user_id': c.sellerId,
        'amount': 100,
        'idempotency_key': '${prefix}_pay_${i % 2 == 0 ? 'A' : 'B'}',
      },
      anon: c.anon,
      jwt: c.sellerJwt,
    ));
  }
  final rs = await Future.wait(futs);
  for (final r in rs) {
    rec(surface: 'PAYOUT', attack: 'parallel 100 cents two keys', identity: 'seller', result: brief(r, 220));
  }
}

Future<void> _reviewDup(Ctx c) async {
  final futs = <Future<http.Response>>[];
  for (var i = 0; i < 4; i++) {
    futs.add(rest(
      c.url,
      'POST',
      'reviews',
      headers: c.buyerH,
      body: {
        'author_id': c.buyerId,
        'target_id': c.sellerId,
        'stars': 5,
        'comment': '$prefix dup $i',
        'purchase_verified': true,
      },
    ));
  }
  final rs = await Future.wait(futs);
  var ok = 0;
  for (final r in rs) {
    rec(surface: 'REVIEWS', attack: 'parallel insert', identity: 'buyer', result: brief(r, 180));
    if (looksOk(r)) ok++;
  }
  rec(surface: 'REVIEWS', attack: 'dup count', identity: 'buyer', result: 'ok=$ok/4');
}

Future<void> _stripeWebhookForge(Ctx c) async {
  final r = await http.post(
    Uri.parse('${c.url}/functions/v1/stripe-webhook'),
    headers: {
      'apikey': c.anon,
      'Authorization': 'Bearer ${c.anon}',
      'Content-Type': 'application/json',
      'stripe-signature': 't=1,v1=deadbeef',
    },
    body: jsonEncode({
      'type': 'checkout.session.completed',
      'data': {
        'object': {
          'id': 'cs_test_forge',
          'payment_status': 'paid',
          'metadata': {'order_id': 'x', 'buyer_id': c.buyerId},
        }
      },
    }),
  );
  rec(surface: 'WEBHOOK', attack: 'forged signature', identity: 'anon', result: brief(r));
}

Future<void> _collusionOffPlatform(Ctx c, Map product) async {
  final pid = product['id'].toString();
  final o = await _insertOrder(
    c,
    productId: pid,
    pay: 'MB WAY',
    extra: {'status': 'pago'},
  );
  rec(
    surface: 'ORDERS',
    attack: 'off-platform INSERT status pago',
    identity: 'buyer',
    result: 'status=${o?['status']} paid=${o?['amount_paid_cents']}',
    evidence: o,
  );
  if (o == null) return;
  final oid = o['id'].toString();
  final rel = await rpcRaw(
    c.url,
    'batata_release_seller_wallet_for_order',
    {'p_order_id': oid},
    headers: c.sellerH,
  );
  rec(surface: 'WALLET', attack: 'release after off-platform pago', identity: 'seller', result: brief(rel));
  final w = await rest(
    c.url,
    'GET',
    'wallets?id=eq.${c.sellerId}&select=id,balance',
    headers: c.svcH,
  );
  rec(surface: 'WALLET', attack: 'seller balance after release', identity: 'observe', result: brief(w));
}
