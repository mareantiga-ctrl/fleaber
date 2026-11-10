/// PASS 4 — variants, dual-session, Stripe TEST fixture, reviews schema.
/// Staging only. Crash-secret used ONLY as lab fixture (not JWT exploit).
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '_http.dart';

Future<void> main() async {
  final c = await boot();
  stdout.writeln('PASS4 boot crash=${c.crashSecret.length >= 16}');

  await _openapiSvc(c);
  await _livesColumns(c);
  await _checkoutDumpAndRace(c);
  await _reviewsSchema(c);
  await _walletTipDelta(c);
  await _chatForeign(c);
  await _paidFixtureRefundRelease(c);
  await _hubViews(c);
  await _rpcGrantSweep(c);

  await dumpJson(
    'tool/redteam_blind_indep_20260830T1752/out/pass4.json',
    {
      'project': projectMust,
      'pass': 4,
      'matrix': matrix,
      'findings': findings,
      'gaps': gaps,
    },
  );
  stdout.writeln('PASS4 done matrix=${matrix.length} findings=${findings.length}');
}

Future<void> _openapiSvc(Ctx c) async {
  final r = await http.get(
    Uri.parse('${c.url}/rest/v1/'),
    headers: {
      ...c.svcH,
      'Accept': 'application/openapi+json',
    },
  );
  rec(surface: 'POSTGREST', attack: 'openapi service_role', identity: 'observe', result: 'status=${r.statusCode} len=${r.body.length}');
  final rpcs = <String>[];
  try {
    final j = jsonDecode(r.body);
    if (j is Map && j['paths'] is Map) {
      for (final k in (j['paths'] as Map).keys) {
        if (k.toString().startsWith('/rpc/')) {
          rpcs.add(k.toString().replaceFirst('/rpc/', ''));
        }
      }
    }
  } catch (_) {}
  rec(surface: 'RPC', attack: 'inventory', identity: 'observe', result: 'count=${rpcs.length}', evidence: rpcs);
  await dumpJson(
    'tool/redteam_blind_indep_20260830T1752/out/rpc_inventory.json',
    rpcs,
  );
}

Future<void> _livesColumns(Ctx c) async {
  for (final sel in [
    'id,title,status,is_active',
    'id,mux_playback_id',
    'id,mux_stream_key',
    'id,stream_key',
  ]) {
    final r = await rest(
      c.url,
      'GET',
      'lives?select=$sel&limit=3',
      headers: c.buyerH,
    );
    rec(surface: 'lives', attack: 'SELECT $sel', identity: 'buyer', result: brief(r, 220));
    final s = await rest(
      c.url,
      'GET',
      'lives?select=$sel&limit=3',
      headers: c.sellerH,
    );
    rec(surface: 'lives', attack: 'SELECT $sel', identity: 'seller', result: brief(s, 220));
  }
}

Future<Map?> _newProduct(Ctx c, {required int qty, required double price, required String tag}) async {
  final r = await rest(
    c.url,
    'POST',
    'products',
    headers: c.sellerH,
    body: {
      'seller_id': c.sellerId,
      'title': '$prefix-$tag-${DateTime.now().millisecondsSinceEpoch}',
      'price': price,
      'quantity': qty,
      'list_on_marketplace': true,
    },
  );
  rec(surface: 'products', attack: 'INSERT $tag', identity: 'seller', result: brief(r, 180));
  final j = tryJson(r);
  if (j is List && j.isNotEmpty) return j[0] as Map;
  if (j is Map) return j;
  return null;
}

Future<Map?> _newOrder(Ctx c, String pid) async {
  final r = await rest(
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
      'price_total': 0.01,
      'contract_unit_cents': 1,
    },
  );
  rec(surface: 'orders', attack: 'INSERT for checkout', identity: 'buyer', result: brief(r, 180));
  final j = tryJson(r);
  if (j is List && j.isNotEmpty) return j[0] as Map;
  if (j is Map) return j;
  return null;
}

Future<void> _checkoutDumpAndRace(Ctx c) async {
  final p = await _newProduct(c, qty: 5, price: 18.00, tag: 'race');
  if (p == null) return;
  final o = await _newOrder(c, p['id'].toString());
  if (o == null) return;
  final oid = o['id'].toString();

  final one = await edge(
    c.url,
    'create-payment-intent',
    {
      'buyer_id': c.buyerId,
      'order_id': oid,
      'amount': 1,
      'quantity': 99,
      'shipping_method': 'hand',
    },
    anon: c.anon,
    jwt: c.buyerJwt,
  );
  final full = tryJson(one);
  rec(
    surface: 'CHECKOUT',
    attack: 'amount=1 dump',
    identity: 'buyer',
    result: brief(one, 400),
    evidence: full is Map
        ? {
            'server_amount_cents': full['server_amount_cents'],
            'amount_total': full['amount_total'],
            'checkoutSessionId': full['checkoutSessionId'],
            'reused_session': full['reused_session'],
            'contract_unit_cents': o['contract_unit_cents'],
            'catalog_price': p['price'],
          }
        : one.body,
  );
  if (full is Map) {
    final server = full['server_amount_cents'];
    rec(
      surface: 'CHECKOUT',
      attack: 'server vs client 1 cent',
      identity: 'buyer',
      result: 'server_amount_cents=$server client=1 catalog=1800',
    );
    if (server is num && server <= 50) {
      finding(
        id: 'RT1752-P0-CHEAP-SESSION',
        severity: 'P0',
        title: 'Checkout Session cobrou montante cliente (~1 cêntimo)',
        actor: 'buyer JWT',
        pre: 'produto 18€',
        repro: 'POST create-payment-intent amount=1',
        impact: 'pagar menos que o contrato',
        evidence: full,
      );
    }
  }

  // Fresh product for parallel sessions so first bind does not serialize.
  final p2 = await _newProduct(c, qty: 4, price: 9.00, tag: 'par');
  if (p2 == null) return;
  final o2 = await _newOrder(c, p2['id'].toString());
  if (o2 == null) return;
  final oid2 = o2['id'].toString();
  final futs = List.generate(
    10,
    (_) => edge(
      c.url,
      'create-payment-intent',
      {
        'buyer_id': c.buyerId,
        'order_id': oid2,
        'amount': 1,
        'shipping_method': 'hand',
      },
      anon: c.anon,
      jwt: c.buyerJwt,
    ),
  );
  final rs = await Future.wait(futs);
  final sessions = <String>{};
  final amounts = <Object?>{};
  var ok = 0;
  for (final r in rs) {
    if (looksOk(r)) {
      ok++;
      final j = tryJson(r);
      if (j is Map) {
        final s = '${j['checkoutSessionId'] ?? ''}';
        if (s.startsWith('cs_')) sessions.add(s);
        amounts.add(j['server_amount_cents']);
      }
    }
    rec(surface: 'CHECKOUT', attack: 'parallel', identity: 'buyer', result: brief(r, 160));
  }
  rec(
    surface: 'CHECKOUT',
    attack: '10 parallel unique sessions',
    identity: 'buyer',
    result: 'ok=$ok unique=${sessions.length} amounts=$amounts',
    evidence: sessions.toList(),
  );
  if (sessions.length >= 2) {
    finding(
      id: 'RT1752-P1-DUAL-CS',
      severity: 'P1',
      title: 'Duas Checkout Sessions na mesma order',
      actor: 'buyer JWT',
      pre: '10 POST paralelos',
      repro: 'create-payment-intent race',
      impact: 'duas intenções de cobrança; captura líquida a verificar',
      evidence: {'n': sessions.length, 'ids': sessions.take(3).toList()},
    );
  }
}

Future<void> _reviewsSchema(Ctx c) async {
  final payloads = [
    {
      'buyer_id': c.buyerId,
      'target_id': c.sellerId,
      'stars': 5,
      'comment': '$prefix forge',
      'purchase_verified': true,
      'author_role': 'buyer',
      'target_type': 'seller',
      'is_automatic': false,
    },
    {
      'buyer_id': c.sellerId,
      'target_id': c.sellerId,
      'stars': 5,
      'comment': '$prefix as seller id',
      'purchase_verified': true,
      'author_role': 'buyer',
      'target_type': 'seller',
    },
  ];
  for (final body in payloads) {
    final r = await rest(c.url, 'POST', 'reviews', headers: c.buyerH, body: body);
    rec(surface: 'reviews', attack: 'INSERT ${body['comment']}', identity: 'buyer', result: brief(r, 280));
    if (looksOk(r)) {
      final j = tryJson(r);
      Map? m = j is List && j.isNotEmpty ? j[0] as Map : (j is Map ? j : null);
      final pv = m?['purchase_verified'];
      rec(surface: 'reviews', attack: 'FINAL purchase_verified', identity: 'buyer', result: 'pv=$pv', evidence: m);
      if (pv == true) {
        finding(
          id: 'RT1752-P1-REVIEW-VERIFIED',
          severity: 'P1',
          title: 'Review purchase_verified sem captura',
          actor: 'buyer JWT',
          pre: 'sem order_id de compra paga',
          repro: 'POST reviews purchase_verified=true',
          impact: 'reputação pública inflacionada',
          evidence: m,
        );
      }
    }
  }
}

Future<void> _walletTipDelta(Ctx c) async {
  final b = await rest(c.url, 'GET', 'wallets?id=eq.${c.buyerId}&select=id,balance', headers: c.svcH);
  final s = await rest(c.url, 'GET', 'wallets?id=eq.${c.sellerId}&select=id,balance', headers: c.svcH);
  rec(surface: 'WALLET', attack: 'observe balances', identity: 'observe', result: 'buyer=${brief(b, 120)} seller=${brief(s, 120)}');
}

Future<void> _chatForeign(Ctx c) async {
  final all = await rest(
    c.url,
    'GET',
    'chats?select=id,user_a,user_b&limit=20',
    headers: c.buyerH,
  );
  rec(surface: 'chats', attack: 'SELECT 20', identity: 'buyer', result: brief(all, 240));
  final j = tryJson(all);
  if (j is List) {
    for (final row in j) {
      final a = '${row['user_a']}';
      final b = '${row['user_b']}';
      if (a != c.buyerId && b != c.buyerId) {
        finding(
          id: 'RT1752-P1-CHAT-FOREIGN',
          severity: 'P1',
          title: 'Buyer lê chat alheio',
          actor: 'buyer JWT',
          pre: 'SELECT chats',
          repro: 'GET chats',
          impact: 'privacidade',
          evidence: row,
        );
      }
    }
  }
  final svcChats = await rest(
    c.url,
    'GET',
    'chats?select=id,user_a,user_b&user_a=neq.${c.buyerId}&user_b=neq.${c.buyerId}&limit=5',
    headers: c.svcH,
  );
  rec(surface: 'chats', attack: 'observe foreign chats', identity: 'observe', result: brief(svcChats, 200));
  final fj = tryJson(svcChats);
  if (j is List && fj is List && fj.isNotEmpty) {
    final fid = fj[0]['id'];
    final msg = await rest(
      c.url,
      'GET',
      'chat_messages?chat_id=eq.$fid&select=id,text,sender_id&limit=5',
      headers: c.buyerH,
    );
    rec(surface: 'chat_messages', attack: 'SELECT foreign chat_id', identity: 'buyer', result: brief(msg, 220));
    if (looksOk(msg) && msg.body.contains('"id"') && msg.body != '[]') {
      finding(
        id: 'RT1752-P1-MSG-FOREIGN',
        severity: 'P1',
        title: 'Buyer lê mensagens de chat alheio',
        actor: 'buyer JWT',
        pre: 'UUID de chat de terceiros',
        repro: 'GET chat_messages?chat_id=eq.<alheio>',
        impact: 'privacidade de conversas',
        evidence: brief(msg),
      );
    }
  }
}

Future<void> _paidFixtureRefundRelease(Ctx c) async {
  if (c.crashSecret.length < 16) {
    gaps.add('no crash secret — skip Stripe TEST paid fixture');
    return;
  }
  final setup = await edge(
    c.url,
    'sec-fase2-e2e-oversell',
    {
      'probe': 'setup_paid_order',
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'initial_qty': 2,
    },
    anon: c.anon,
    jwt: c.buyerJwt,
    extra: {'x-fleaber-e2e-secret': c.crashSecret},
  );
  rec(
    surface: 'STRIPE_TEST',
    attack: 'fixture setup_paid_order (lab secret, not JWT)',
    identity: 'lab_fixture',
    result: brief(setup, 400),
  );
  final body = tryJson(setup);
  if (body is! Map || body['ok'] != true) {
    gaps.add('setup_paid_order failed: ${brief(setup, 200)}');
    return;
  }
  final orderId = '${body['order_id'] ?? body['order']?['id'] ?? ''}';
  rec(surface: 'STRIPE_TEST', attack: 'paid order id', identity: 'observe', result: orderId, evidence: body);

  String oid = orderId;
  if (oid.isEmpty && body['order'] is Map) {
    oid = '${(body['order'] as Map)['id']}';
  }

  final before = await rest(
    c.url,
    'GET',
    'orders?id=eq.$oid&select=id,status,amount_paid_cents,stripe_payment_intent_id,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,stock_units_applied',
    headers: c.svcH,
  );
  rec(surface: 'STRIPE_TEST', attack: 'order after capture', identity: 'observe', result: brief(before, 300));

  final wb0 = await rest(c.url, 'GET', 'wallets?id=eq.${c.buyerId}&select=balance', headers: c.svcH);
  final ws0 = await rest(c.url, 'GET', 'wallets?id=eq.${c.sellerId}&select=balance', headers: c.svcH);

  final futs = <Future<http.Response>>[
    edge(c.url, 'refund-order', {'order_id': oid}, anon: c.anon, jwt: c.buyerJwt),
    edge(c.url, 'refund-order', {'order_id': oid}, anon: c.anon, jwt: c.sellerJwt),
    edge(c.url, 'refund-order', {'order_id': oid}, anon: c.anon, jwt: c.sellerJwt),
    rpcRaw(c.url, 'batata_release_seller_wallet_for_order', {'p_order_id': oid}, headers: c.sellerH),
    rpcRaw(c.url, 'batata_refund_buyer_wallet_for_order', {'p_order_id': oid}, headers: c.sellerH),
    rpcRaw(c.url, 'batata_release_seller_wallet_for_order', {'p_order_id': oid}, headers: c.buyerH),
  ];
  final rs = await Future.wait(futs);
  for (var i = 0; i < rs.length; i++) {
    rec(surface: 'STRIPE_TEST', attack: 'post-capture op $i', identity: 'mixed', result: brief(rs[i], 240));
  }

  final after = await rest(
    c.url,
    'GET',
    'orders?id=eq.$oid&select=id,status,amount_paid_cents,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,stock_units_applied',
    headers: c.svcH,
  );
  final wb1 = await rest(c.url, 'GET', 'wallets?id=eq.${c.buyerId}&select=balance', headers: c.svcH);
  final ws1 = await rest(c.url, 'GET', 'wallets?id=eq.${c.sellerId}&select=balance', headers: c.svcH);
  rec(surface: 'STRIPE_TEST', attack: 'FINAL order', identity: 'observe', result: brief(after, 300));
  rec(surface: 'STRIPE_TEST', attack: 'FINAL wallets', identity: 'observe', result: 'buyer ${brief(wb0, 80)} -> ${brief(wb1, 80)} seller ${brief(ws0, 80)} -> ${brief(ws1, 80)}');
}

Future<void> _hubViews(Ctx c) async {
  for (final t in [
    'hub_lives',
    'lives_public',
    'reviews_public_ratings',
    'hub_shop',
  ]) {
    final r = await rest(c.url, 'GET', '$t?select=*&limit=5', headers: c.anonH);
    rec(surface: t, attack: 'anon SELECT', identity: 'anon', result: brief(r, 200));
  }
}

Future<void> _rpcGrantSweep(Ctx c) async {
  // Sensitive names from Flutter + SQL, exact signatures where known.
  final calls = <Map<String, dynamic>>[
    {'fn': 'batata_credit_wallet_once', 'p': {'p_wallet_id': c.buyerId, 'p_order_id': '00000000-0000-0000-0000-000000000001', 'p_amount': 10, 'p_kind': 'x', 'p_label': 'x'}},
    {'fn': 'batata_wallet_payout_debit', 'p': {'p_user_id': c.sellerId, 'p_amount_cents': 100, 'p_idempotency_key': '${prefix}_jwt_debit'}},
    {'fn': 'batata_finalize_stripe_order_refund', 'p': {'p_order_id': '00000000-0000-0000-0000-000000000001', 'p_refund_id': 're_x', 'p_payment_intent_id': 'pi_x', 'p_session_id': 'cs_x', 'p_amount_cents': 100}},
    {'fn': 'batata_settle_live_tip_from_stripe', 'p': {'p_tip_id': '00000000-0000-0000-0000-000000000001', 'p_stripe_session_id': 'cs_x', 'p_paid_amount_cents': 100}},
    {'fn': 'batata_generate_auto_feedback', 'p': {}},
    {'fn': 'batata_ps_create_pairing', 'p': {}},
    {'fn': 'batata_ps_claim_pairing', 'p': {'p_code': '000000', 'p_device_id': 'x'}},
  ];
  for (final x in calls) {
    final r = await rpcRaw(c.url, x['fn'] as String, Map<String, dynamic>.from(x['p'] as Map), headers: c.buyerH);
    rec(surface: 'RPC', attack: x['fn'] as String, identity: 'buyer', result: brief(r, 200));
    if (looksOk(r) && (x['fn'] as String).contains('credit')) {
      finding(
        id: 'RT1752-P0-RPC-CREDIT',
        severity: 'P0',
        title: 'JWT credit wallet',
        actor: 'buyer',
        pre: 'RPC',
        repro: '${x['fn']}',
        impact: 'mint',
        evidence: brief(r),
      );
    }
  }
}
