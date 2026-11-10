/// PASS 2 — variantes, invariantes financeiros, schema correcto, Stripe TEST.
/// Auditoria cega 20260830T1837. Não corrige. Não produção.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '_rt.dart';

Future<void> main() async {
  final c = await boot();
  stdout.writeln('PASS2 boot');

  await _openapiJwt(c);
  await _rpcCorrect(c);
  await _piiProfiles(c);
  await _reviewsChatsDisputes(c);
  await _helpersBundles(c);
  await _contractVsCatalog(c);
  await _checkoutAuthority(c);
  await _offPlatformWallet(c);
  await _fsmJumps(c);
  await _soldUnlist(c);
  await _dualSessions(c);
  await _stripePaidCycle(c);
  await _storageBuckets(c);
  await _reservationLive(c);

  await dumpJson('pass2', {
    'pass': 2,
    'project': projectMust,
    'utc': DateTime.now().toUtc().toIso8601String(),
    'matrix': matrix,
    'findings': findings,
    'gaps': gaps,
    'invariants': invariants,
  });
  stdout.writeln(
    'PASS2 done matrix=${matrix.length} findings=${findings.length}',
  );
}

Future<void> _openapiJwt(Ctx c) async {
  for (final idn in ['buyer', 'svc']) {
    final h = idn == 'svc' ? c.svcH : c.buyerH;
    final r = await http.get(
      Uri.parse('${c.url}/rest/v1/'),
      headers: {...h, 'Accept': 'application/openapi+json'},
    );
    rec(
      surface: 'OPENAPI',
      attack: 'openapi as $idn',
      identity: idn,
      result: '${r.statusCode} bytes=${r.body.length}',
    );
    if (r.statusCode == 200) {
      try {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final paths = (j['paths'] as Map?)?.keys.map((e) => e.toString()).toList() ?? [];
        final rpcs = paths.where((p) => p.startsWith('/rpc/')).map((p) => p.substring(5)).toList();
        await dumpJson('openapi_$idn', {
          'n_paths': paths.length,
          'rpcs': rpcs,
          'tables': paths.where((p) => !p.startsWith('/rpc/')).toList(),
        });
        rec(
          surface: 'OPENAPI',
          attack: 'inventory $idn',
          identity: idn,
          result: 'paths=${paths.length} rpcs=${rpcs.length}',
        );
      } catch (e) {
        gaps.add('openapi $idn parse $e');
      }
    }
  }
}

Future<void> _rpcCorrect(Ctx c) async {
  final credit = await rpc(
    c.url,
    'batata_credit_wallet_once',
    {
      'p_wallet_id': c.buyerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 100,
      'p_type': 'venda',
      'p_description': prefix,
    },
    headers: c.buyerH,
  );
  rec(
    surface: 'RPC',
    attack: 'credit_wallet_once p_wallet_id as buyer',
    identity: 'buyer',
    result: briefBody(credit),
  );
  if (credit.statusCode == 200 && credit.body.toLowerCase().contains('true')) {
    finding(
      id: 'RT1837-P0-CREDIT-RPC',
      severity: 'P0',
      title: 'JWT credita carteira via batata_credit_wallet_once',
      actor: 'buyer',
      pre: 'JWT',
      repro: 'rpc batata_credit_wallet_once',
      impact: 'criação de saldo',
      evidence: briefBody(credit),
    );
  }

  final prize = await rpc(
    c.url,
    'batata_create_raffle_prize_order',
    {
      'p_raffle_id': '00000000-0000-0000-0000-000000000001',
      'p_rank': 1,
      'p_winner_uid': c.buyerId,
    },
    headers: c.buyerH,
  );
  rec(
    surface: 'RAFFLE',
    attack: 'create_raffle_prize_order as buyer',
    identity: 'buyer',
    result: briefBody(prize),
  );

  final pair = await rpc(
    c.url,
    'batata_ps_claim_pairing',
    {
      'p_code': '000000',
      'p_device_id': 'rt1837',
      'p_app_version': '1',
      'p_client_ip': '1.2.3.4',
    },
    headers: c.anonH,
  );
  rec(
    surface: 'PS',
    attack: 'anon rpc claim_pairing 4-arg',
    identity: 'anon',
    result: briefBody(pair),
  );

  final ensure = await rpc(
    c.url,
    'batata_ensure_wallet',
    {'p_user_id': c.buyerId},
    headers: c.buyerH,
  );
  rec(
    surface: 'WALLET',
    attack: 'ensure_wallet self',
    identity: 'buyer',
    result: briefBody(ensure),
  );
}

Future<void> _piiProfiles(Ctx c) async {
  final r = await rest(
    c.url,
    'GET',
    'profiles?select=id,full_name,phone,mb_way,iban,user_type,shipping_line1,nif,email&limit=15',
    headers: c.buyerH,
  );
  rec(
    surface: 'PROFILES',
    attack: 'buyer SELECT PII/banking columns',
    identity: 'buyer',
    result: briefBody(r),
  );
  final rows = asMaps(decode(r));
  final others = rows.where((x) => x['id']?.toString() != c.buyerId).toList();
  final leaked = others.where((x) {
    final iban = '${x['iban'] ?? ''}'.trim();
    final mb = '${x['mb_way'] ?? ''}'.trim();
    final phone = '${x['phone'] ?? ''}'.trim();
    final ship = '${x['shipping_line1'] ?? ''}'.trim();
    return iban.isNotEmpty || mb.isNotEmpty || phone.isNotEmpty || ship.isNotEmpty;
  }).toList();
  if (leaked.isNotEmpty) {
    finding(
      id: 'RT1837-P1-PII-PROFILES',
      severity: 'P1',
      title: 'Buyer lê IBAN/MB WAY/telefone/morada alheios',
      actor: 'buyer',
      pre: 'JWT',
      repro: 'GET /profiles select iban,mb_way,phone,shipping_line1',
      impact: 'PII / dados bancários',
      evidence: {
        'n': leaked.length,
        'sample_ids': leaked.take(3).map((e) => e['id']).toList(),
        'fields_present': leaked.first.keys.where((k) {
          final v = '${leaked.first[k] ?? ''}'.trim();
          return v.isNotEmpty && k != 'id' && k != 'full_name' && k != 'user_type';
        }).toList(),
      },
    );
  }

  final byId = await rest(
    c.url,
    'GET',
    'profiles?id=eq.${c.sellerId}&select=id,iban,mb_way,phone,shipping_line1,nif',
    headers: c.buyerH,
  );
  rec(
    surface: 'PROFILES',
    attack: 'buyer GET seller banking by UUID',
    identity: 'buyer',
    result: briefBody(byId),
  );
}

Future<void> _reviewsChatsDisputes(Ctx c) async {
  final rev = await rest(
    c.url,
    'POST',
    'reviews',
    headers: c.buyerH,
    body: {
      'buyer_id': c.buyerId,
      'target_id': c.sellerId,
      'target_type': 'seller',
      'stars': 5,
      'comment': '$prefix forged no order',
      'author_role': 'buyer',
      'is_automatic': false,
    },
  );
  rec(
    surface: 'REVIEWS',
    attack: 'INSERT review without order_id',
    identity: 'buyer',
    result: briefBody(rev),
  );
  final rRows = asMaps(decode(rev));
  if (rev.statusCode >= 200 &&
      rev.statusCode < 300 &&
      rRows.isNotEmpty &&
      rRows.first['id'] != null) {
    finding(
      id: 'RT1837-P1-REVIEW-NO-TX',
      severity: 'P1',
      title: 'Review persistida sem encomenda',
      actor: 'buyer',
      pre: 'sem order_id',
      repro: 'POST /reviews stars=5 sem order',
      impact: 'reputação falsa',
      evidence: rRows.first,
    );
  }

  final asOther = await rest(
    c.url,
    'POST',
    'reviews',
    headers: c.buyerH,
    body: {
      'buyer_id': c.sellerId,
      'target_id': c.buyerId,
      'target_type': 'buyer',
      'stars': 1,
      'comment': '$prefix as seller',
      'author_role': 'seller',
    },
  );
  rec(
    surface: 'REVIEWS',
    attack: 'buyer INSERT review as seller identity',
    identity: 'buyer',
    result: briefBody(asOther),
  );

  final chats = await rest(
    c.url,
    'GET',
    'chats?select=id,user_a,user_b,product_id,last_message&limit=20',
    headers: c.buyerH,
  );
  rec(
    surface: 'CHAT',
    attack: 'GET chats user_a/user_b',
    identity: 'buyer',
    result: briefBody(chats),
  );
  final clist = asMaps(decode(chats));
  final foreign = clist.where((r) {
    return r['user_a']?.toString() != c.buyerId &&
        r['user_b']?.toString() != c.buyerId;
  }).toList();
  if (foreign.isNotEmpty) {
    finding(
      id: 'RT1837-P1-CHAT-CROSS',
      severity: 'P1',
      title: 'Buyer lista chats onde não é parte',
      actor: 'buyer',
      pre: 'JWT',
      repro: 'GET /chats',
      impact: 'metadados privados',
      evidence: {'n': foreign.length, 'sample': foreign.take(2).toList()},
    );
    final cid = foreign.first['id'].toString();
    final msgs = await rest(
      c.url,
      'GET',
      'chat_messages?chat_id=eq.$cid&select=id,text,sender_id,receiver_id&limit=5',
      headers: c.buyerH,
    );
    rec(
      surface: 'CHAT',
      attack: 'GET messages foreign chat',
      identity: 'buyer',
      result: briefBody(msgs),
    );
    if (msgs.statusCode == 200 && asMaps(decode(msgs)).isNotEmpty) {
      finding(
        id: 'RT1837-P1-CHAT-MSG-CROSS',
        severity: 'P1',
        title: 'Buyer lê mensagens de chat alheio',
        actor: 'buyer',
        pre: 'chat_id alheio',
        repro: 'GET /chat_messages',
        impact: 'conteúdo privado',
        evidence: briefBody(msgs),
      );
    }
  }

  final disp = await rest(
    c.url,
    'GET',
    'order_disputes?select=id,order_id,buyer_id,reason,description,status,proof_photos&limit=15',
    headers: c.buyerH,
  );
  rec(
    surface: 'DISPUTES',
    attack: 'GET disputes',
    identity: 'buyer',
    result: briefBody(disp),
  );
  final dlist = asMaps(decode(disp));
  final dForeign = dlist.where((r) => r['buyer_id']?.toString() != c.buyerId).toList();
  if (dForeign.isNotEmpty) {
    finding(
      id: 'RT1837-P1-DISPUTE-CROSS',
      severity: 'P1',
      title: 'Buyer lê disputas de outros buyers',
      actor: 'buyer',
      pre: 'JWT',
      repro: 'GET /order_disputes',
      impact: 'provas / PII',
      evidence: {'n': dForeign.length},
    );
  }

  final fakeDisp = await rest(
    c.url,
    'POST',
    'order_disputes',
    headers: c.buyerH,
    body: {
      'order_id': '00000000-0000-0000-0000-000000000001',
      'buyer_id': c.buyerId,
      'reason': prefix,
      'description': 'forged',
      'status': 'aberta',
    },
  );
  rec(
    surface: 'DISPUTES',
    attack: 'INSERT dispute fake order',
    identity: 'buyer',
    result: briefBody(fakeDisp),
  );
}

Future<void> _helpersBundles(Ctx c) async {
  final sh = await rest(
    c.url,
    'POST',
    'seller_helpers',
    headers: c.buyerH,
    body: {
      'seller_id': c.sellerId,
      'helper_user_id': c.buyerId,
      'active': true,
      'invitation_status': 'accepted',
      'permissions': {
        'can_manage_reservations': true,
        'can_manage_raffles': true,
      },
    },
  );
  rec(
    surface: 'STAFF',
    attack: 'buyer INSERT helper on seller shop',
    identity: 'buyer',
    result: briefBody(sh),
  );

  final bun = await rest(
    c.url,
    'POST',
    'product_bundles',
    headers: c.buyerH,
    body: {
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'status': 'accepted',
      'total_eur': 0.50,
      'discount_pct': 90,
    },
  );
  rec(
    surface: 'BUNDLES',
    attack: 'buyer INSERT bundle accepted 0.50€ 90%',
    identity: 'buyer',
    result: briefBody(bun),
  );
  final bRows = asMaps(decode(bun));
  if (bRows.isNotEmpty) {
    rec(
      surface: 'BUNDLES',
      attack: 'observe bundle row',
      identity: 'buyer',
      result: 'status=${bRows.first['status']} total=${bRows.first['total_eur']}',
      evidence: bRows.first,
    );
    final id = bRows.first['id']?.toString();
    if (id != null) {
      final acc = await rest(
        c.url,
        'PATCH',
        'product_bundles?id=eq.$id',
        headers: c.buyerH,
        body: {'status': 'accepted', 'total_eur': 0.01},
      );
      rec(
        surface: 'BUNDLES',
        attack: 'buyer PATCH bundle accept+price',
        identity: 'buyer',
        result: briefBody(acc),
      );
    }
  }
}

Future<Map<String, dynamic>?> _prod(Ctx c, {int qty = 5, double price = 8.0}) async {
  try {
    return await c.admin.insert('products', {
      'seller_id': c.sellerId,
      'title': '$prefix ${tag()}',
      'price': price,
      'quantity': qty,
      'list_on_marketplace': true,
      'is_sold': false,
    });
  } catch (e) {
    rec(surface: 'FIXTURE', attack: 'product', identity: 'svc', result: '$e');
    return null;
  }
}

Future<Map<String, dynamic>?> _orderJwt(
  Ctx c,
  String pid, {
  int qty = 1,
  double total = 8,
  String ship = 'hand',
  String pay = 'Seguro Fleaber',
  String status = 'reserva_pendente',
}) async {
  final r = await rest(
    c.url,
    'POST',
    'orders',
    headers: c.buyerH,
    body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'quantity': qty,
      'price_total': total,
      'status': status,
      'payment_method': pay,
      'shipping_method': ship,
    },
  );
  rec(
    surface: 'ORDERS',
    attack: 'JWT INSERT order status=$status pay=$pay',
    identity: 'buyer',
    result: briefBody(r),
  );
  final rows = asMaps(decode(r));
  return rows.isEmpty ? null : rows.first;
}

Future<void> _contractVsCatalog(Ctx c) async {
  final p = await _prod(c, qty: 2, price: 12.0);
  if (p == null) return;
  final pid = p['id'].toString();
  final o = await _orderJwt(c, pid, total: 12);
  if (o == null) return;
  rec(
    surface: 'CONTRACT',
    attack: 'sealed insert',
    identity: 'buyer',
    result:
        'unit=${o['contract_unit_cents']} qty=${o['contract_qty']} total=${o['price_total']}',
    evidence: {
      'contract_unit_cents': o['contract_unit_cents'],
      'contract_qty': o['contract_qty'],
      'price_total': o['price_total'],
      'quantity': o['quantity'],
    },
  );

  try {
    await c.admin.patch('products', 'id=eq.$pid', {'price': 0.50});
  } catch (e) {
    rec(surface: 'CONTRACT', attack: 'drop catalog price', identity: 'svc', result: '$e');
  }

  final ck = await edge(
    c.url,
    'create-payment-intent',
    {
      'buyer_id': c.buyerId,
      'order_id': o['id'],
      'amount': 50,
      'shipping_method': 'hand',
    },
    headers: c.buyerH,
  );
  rec(
    surface: 'CONTRACT',
    attack: 'checkout after catalog price drop to 0.50',
    identity: 'buyer',
    result: briefBody(ck),
  );
  _assertCheckoutNotCheap(ck, 1200, 'catalog drop');
}

void _assertCheckoutNotCheap(http.Response ck, int minCents, String label) {
  final d = decode(ck);
  if (d is! Map) return;
  final amt = d['amount_total'] ?? d['server_amount_cents'];
  final n = amt is num ? amt.toInt() : int.tryParse('$amt') ?? 0;
  rec(
    surface: 'CHECKOUT',
    attack: 'amount after $label',
    identity: 'buyer',
    result: 'http=${ck.statusCode} amount=$n min=$minCents',
    evidence: {'server_amount_cents': d['server_amount_cents'], 'amount_total': d['amount_total']},
  );
  if (ck.statusCode == 200 && n > 0 && n < minCents) {
    finding(
      id: 'RT1837-P0-UNDERPAY-$label',
      severity: 'P0',
      title: 'Checkout cobra abaixo do contrato ($label)',
      actor: 'buyer',
      pre: 'order selada',
      repro: 'POST create-payment-intent',
      impact: 'pagar menos que o preço legítimo',
      evidence: d,
    );
  }
}

Future<void> _checkoutAuthority(Ctx c) async {
  final p = await _prod(c, qty: 2, price: 9.0);
  if (p == null) return;
  final pid = p['id'].toString();
  final o = await _orderJwt(c, pid, total: 9);
  if (o == null) return;
  final oid = o['id'].toString();

  final variants = [
    {'amount': 50, 'quantity': 1, 'item_price': 0.5, 'shipping_method': 'hand'},
    {'amount': 50, 'prize_shipping': true, 'shipping_method': 'hand'},
    {
      'amount': 50,
      'shipping_method': 'hand',
      'seller_id': c.buyerId,
      'product_id': pid,
    },
    {
      'amount': 99999,
      'shipping_method': 'carrier',
    },
  ];
  for (final v in variants) {
    final body = {
      'buyer_id': c.buyerId,
      'order_id': oid,
      ...v,
    };
    final ck = await edge(c.url, 'create-payment-intent', body, headers: c.buyerH);
    rec(
      surface: 'CHECKOUT',
      attack: 'variant ${jsonEncode(v)}',
      identity: 'buyer',
      result: briefBody(ck),
    );
  }

  // Seller checkout of buyer order
  final sk = await edge(
    c.url,
    'create-payment-intent',
    {
      'buyer_id': c.sellerId,
      'order_id': oid,
      'shipping_method': 'hand',
    },
    headers: c.sellerH,
  );
  rec(
    surface: 'CHECKOUT',
    attack: 'seller checkout buyer order claiming seller as buyer_id',
    identity: 'seller',
    result: briefBody(sk),
  );
}

Future<void> _offPlatformWallet(Ctx c) async {
  final p = await _prod(c, qty: 2, price: 7.0);
  if (p == null) return;
  final o = await _orderJwt(
    c,
    p['id'].toString(),
    total: 7,
    pay: 'MB WAY',
    ship: 'hand',
  );
  if (o == null) return;
  final oid = o['id'].toString();

  final wBefore = await rest(
    c.url,
    'GET',
    'wallets?id=eq.${c.sellerId}&select=id,balance',
    headers: c.svcH,
  );
  final bal0 = asMaps(decode(wBefore)).firstOrNull?['balance'];

  final pay = await rest(
    c.url,
    'PATCH',
    'orders?id=eq.$oid',
    headers: c.sellerH,
    body: {'status': 'pago'},
  );
  rec(
    surface: 'OFFPLATFORM',
    attack: 'seller PATCH MB WAY order → pago',
    identity: 'seller',
    result: briefBody(pay),
  );
  final afterPay = await rest(
    c.url,
    'GET',
    'orders?id=eq.$oid&select=id,status,amount_paid_cents,stripe_payment_intent_id',
    headers: c.svcH,
  );
  rec(
    surface: 'OFFPLATFORM',
    attack: 'observe after seller pago',
    identity: 'svc_observe',
    result: briefBody(afterPay),
    evidence: decode(afterPay),
  );

  final done = await rest(
    c.url,
    'PATCH',
    'orders?id=eq.$oid',
    headers: c.buyerH,
    body: {'status': 'concluido'},
  );
  rec(
    surface: 'OFFPLATFORM',
    attack: 'buyer PATCH concluido after off-platform pago',
    identity: 'buyer',
    result: briefBody(done),
  );

  final rel = await rpc(
    c.url,
    'batata_release_seller_wallet_for_order',
    {'p_order_id': oid},
    headers: c.buyerH,
  );
  rec(
    surface: 'OFFPLATFORM',
    attack: 'buyer RPC release wallet',
    identity: 'buyer',
    result: briefBody(rel),
  );

  final wAfter = await rest(
    c.url,
    'GET',
    'wallets?id=eq.${c.sellerId}&select=id,balance',
    headers: c.svcH,
  );
  final bal1 = asMaps(decode(wAfter)).firstOrNull?['balance'];
  rec(
    surface: 'OFFPLATFORM',
    attack: 'seller wallet before/after release',
    identity: 'svc_observe',
    result: 'before=$bal0 after=$bal1 rpc=${rel.body}',
  );
  final n0 = num.tryParse('$bal0') ?? 0;
  final n1 = num.tryParse('$bal1') ?? 0;
  if (n1 > n0 + 0.009) {
    finding(
      id: 'RT1837-P0-OFFPLAT-MINT',
      severity: 'P0',
      title: 'Release wallet após MB WAY sem captura Stripe',
      actor: 'seller+buyer',
      pre: 'order MB WAY hand',
      repro: 'seller pago → buyer concluido → release RPC',
      impact: 'saldo Fleaber sem fundos da plataforma',
      evidence: {'before': bal0, 'after': bal1, 'rpc': rel.body, 'order': decode(afterPay)},
    );
  }
}

Future<void> _fsmJumps(Ctx c) async {
  final p = await _prod(c, qty: 2, price: 6);
  if (p == null) return;
  final o = await _orderJwt(c, p['id'].toString(), total: 6, ship: 'carrier');
  if (o == null) return;
  final oid = o['id'].toString();

  for (final st in ['pago', 'enviado', 'entregue', 'concluido', 'devolvida']) {
    final r = await rest(
      c.url,
      'PATCH',
      'orders?id=eq.$oid',
      headers: c.buyerH,
      body: {'status': st},
    );
    rec(
      surface: 'FSM',
      attack: 'buyer PATCH reserva_pendente → $st',
      identity: 'buyer',
      result: briefBody(r),
    );
  }

  final ship = await rest(
    c.url,
    'PATCH',
    'orders?id=eq.$oid',
    headers: c.buyerH,
    body: {'shipping_method': 'hand'},
  );
  rec(
    surface: 'FSM',
    attack: 'buyer PATCH shipping carrier→hand',
    identity: 'buyer',
    result: briefBody(ship),
  );
  final obs = await rest(
    c.url,
    'GET',
    'orders?id=eq.$oid&select=id,status,shipping_method',
    headers: c.svcH,
  );
  rec(
    surface: 'FSM',
    attack: 'observe shipping after JWT patch',
    identity: 'svc_observe',
    result: briefBody(obs),
    evidence: decode(obs),
  );
}

Future<void> _soldUnlist(Ctx c) async {
  final p = await _prod(c, qty: 2, price: 11);
  if (p == null) return;
  final pid = p['id'].toString();
  final o = await _orderJwt(c, pid, total: 11);
  if (o == null) return;
  try {
    await c.admin.patch('products', 'id=eq.$pid', {
      'is_sold': true,
      'list_on_marketplace': false,
    });
  } catch (e) {
    rec(surface: 'STOCK', attack: 'mark sold', identity: 'svc', result: '$e');
  }
  final ck = await edge(
    c.url,
    'create-payment-intent',
    {
      'buyer_id': c.buyerId,
      'order_id': o['id'],
      'shipping_method': 'hand',
    },
    headers: c.buyerH,
  );
  rec(
    surface: 'STOCK',
    attack: 'checkout after is_sold+unlist',
    identity: 'buyer',
    result: briefBody(ck),
  );
  if (ck.statusCode == 200) {
    finding(
      id: 'RT1837-P1-DEAD-CHECKOUT',
      severity: 'P1',
      title: 'Checkout Session em produto is_sold/unlist',
      actor: 'buyer',
      pre: 'order criada depois marked sold',
      repro: 'create-payment-intent',
      impact: 'venda de unidade morta',
      evidence: briefBody(ck),
    );
  }
}

Future<void> _dualSessions(Ctx c) async {
  final p = await _prod(c, qty: 1, price: 10);
  if (p == null) return;
  final o = await _orderJwt(c, p['id'].toString(), total: 10);
  if (o == null) return;
  final oid = o['id'].toString();
  final body = {
    'buyer_id': c.buyerId,
    'order_id': oid,
    'shipping_method': 'hand',
  };
  final futs = List.generate(
    8,
    (_) => edge(c.url, 'create-payment-intent', body, headers: c.buyerH),
  );
  final rs = await Future.wait(futs);
  final oks = <Map<String, dynamic>>[];
  for (final r in rs) {
    rec(
      surface: 'CHECKOUT',
      attack: 'concurrent session create',
      identity: 'buyer',
      result: briefBody(r),
    );
    if (r.statusCode == 200) {
      final d = decode(r);
      if (d is Map) oks.add(Map<String, dynamic>.from(d));
    }
  }
  final ids = oks.map((e) => '${e['checkoutSessionId']}').toSet();
  rec(
    surface: 'CHECKOUT',
    attack: 'dual session unique ids',
    identity: 'buyer',
    result: 'ok=${oks.length}/8 unique_cs=${ids.length}',
    evidence: {'ids': ids.toList()},
  );
  inv(
    id: 'I-DUAL-SESSION',
    claim: 'Uma order produz no máximo uma Checkout Session efectiva',
    result: ids.length <= 1 ? 'HOLD' : 'BROKEN_SESSIONS=${ids.length}',
    notes: 'Sessions criadas ≠ capturas. ok=${oks.length} unique=${ids.length}',
  );
}

Future<void> _stripePaidCycle(Ctx c) async {
  if (c.crashSecret.isEmpty) {
    gaps.add('sem crash secret — skip setup_paid_order fixture');
    return;
  }
  final r = await http.post(
    Uri.parse('${c.url}/functions/v1/sec-fase2-e2e-oversell'),
    headers: {
      ...c.anonH,
      'x-fleaber-e2e-secret': c.crashSecret,
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'probe': 'setup_paid_order',
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'initial_qty': 2,
    }),
  );
  rec(
    surface: 'STRIPE_TEST',
    attack: 'fixture setup_paid_order',
    identity: 'e2e_secret',
    result: briefBody(r),
  );
  final d = decode(r);
  if (d is! Map || d['ok'] != true) {
    gaps.add('setup_paid_order failed: ${briefBody(r)}');
    return;
  }
  final nestedOrder = d['order'];
  final oid = '${d['order_id'] ?? (nestedOrder is Map ? nestedOrder['id'] : '')}';
  rec(
    surface: 'STRIPE_TEST',
    attack: 'paid order fixture',
    identity: 'e2e_secret',
    result: 'order=$oid keys=${(d).keys.toList()}',
    evidence: d,
  );
  if (oid.length < 8) {
    // try nested
    final nested = d['order'];
    final oid2 = nested is Map ? '${nested['id']}' : oid;
    await _attackPaid(c, oid2.isEmpty ? oid : oid2, d);
    return;
  }
  await _attackPaid(c, oid, d);
}

Future<void> _attackPaid(Ctx c, String oid, Map fixture) async {
  if (oid.length < 8) {
    gaps.add('paid order id missing');
    return;
  }
  final before = await rest(
    c.url,
    'GET',
    'orders?id=eq.$oid&select=id,status,amount_paid_cents,stripe_payment_intent_id,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,quantity,product_id,price_total',
    headers: c.svcH,
  );
  rec(
    surface: 'STRIPE_TEST',
    attack: 'observe paid order',
    identity: 'svc_observe',
    result: briefBody(before),
    evidence: decode(before),
  );

  final w0 = await rest(
    c.url,
    'GET',
    'wallets?id=in.(${c.buyerId},${c.sellerId})&select=id,balance',
    headers: c.svcH,
  );

  // Buyer refund
  final br = await edge(
    c.url,
    'refund-order',
    {'order_id': oid},
    headers: c.buyerH,
  );
  rec(
    surface: 'REFUND',
    attack: 'buyer refund-order',
    identity: 'buyer',
    result: briefBody(br),
  );

  // Dual seller refund
  final futs = List.generate(
    6,
    (_) => edge(c.url, 'refund-order', {'order_id': oid}, headers: c.sellerH),
  );
  final rs = await Future.wait(futs);
  var sellerOk = 0;
  for (final x in rs) {
    rec(
      surface: 'REFUND',
      attack: 'seller concurrent refund',
      identity: 'seller',
      result: briefBody(x),
    );
    if (x.statusCode == 200 && x.body.contains('"ok":true')) sellerOk++;
  }
  rec(
    surface: 'REFUND',
    attack: 'concurrent seller refund count',
    identity: 'seller',
    result: 'ok_true=$sellerOk / 6',
  );

  final rel = await rpc(
    c.url,
    'batata_release_seller_wallet_for_order',
    {'p_order_id': oid},
    headers: c.buyerH,
  );
  rec(
    surface: 'RELEASE',
    attack: 'release after/during refund',
    identity: 'buyer',
    result: briefBody(rel),
  );

  final after = await rest(
    c.url,
    'GET',
    'orders?id=eq.$oid&select=id,status,amount_paid_cents,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,stock_units_applied',
    headers: c.svcH,
  );
  final w1 = await rest(
    c.url,
    'GET',
    'wallets?id=in.(${c.buyerId},${c.sellerId})&select=id,balance',
    headers: c.svcH,
  );
  rec(
    surface: 'STRIPE_TEST',
    attack: 'final order+wallets after refund/release',
    identity: 'svc_observe',
    result: 'order=${briefBody(after)} wallets0=${briefBody(w0)} wallets1=${briefBody(w1)}',
    evidence: {
      'order': decode(after),
      'wallets_before': decode(w0),
      'wallets_after': decode(w1),
      'release_rpc': rel.body,
    },
  );

  // Payout dual
  final payFuts = List.generate(
    4,
    (i) => edge(
      c.url,
      'create-connect-account',
      {
        'user_id': c.sellerId,
        'amount': 100,
        'idempotency_key': i < 2 ? '${prefix}-same' : '${prefix}-alt-$i',
      },
      headers: c.sellerH,
    ),
  );
  final prs = await Future.wait(payFuts);
  for (final x in prs) {
    rec(
      surface: 'PAYOUT',
      attack: 'seller payout 1€',
      identity: 'seller',
      result: briefBody(x),
    );
  }
}

Future<void> _storageBuckets(Ctx c) async {
  final buckets = [
    'fleaber_private',
    'product-images',
    'products',
    'avatars',
    'chat_uploads',
    'chat-uploads',
    'order_proofs',
    'public',
  ];
  for (final b in buckets) {
    final r = await http.post(
      Uri.parse('${c.url}/storage/v1/object/list/$b'),
      headers: {
        'apikey': c.anon,
        'Authorization': 'Bearer ${c.buyerJwt}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'prefix': '', 'limit': 10}),
    );
    rec(
      surface: 'STORAGE',
      attack: 'list bucket $b as buyer',
      identity: 'buyer',
      result: briefBody(r),
    );
  }
}

Future<void> _reservationLive(Ctx c) async {
  final lives = await rest(
    c.url,
    'GET',
    'lives?select=id,seller_id,status,is_active&seller_id=eq.${c.sellerId}&limit=3',
    headers: c.sellerH,
  );
  rec(
    surface: 'LIVE',
    attack: 'seller list own lives',
    identity: 'seller',
    result: briefBody(lives),
  );
  final items = await rest(
    c.url,
    'GET',
    'live_items?select=id,live_id,price,quantity,status&limit=5',
    headers: c.buyerH,
  );
  rec(
    surface: 'LIVE',
    attack: 'buyer GET live_items',
    identity: 'buyer',
    result: briefBody(items),
  );
  final list = asMaps(decode(items));
  if (list.isNotEmpty) {
    final li = list.first;
    final ins = await rest(
      c.url,
      'POST',
      'live_reservation_requests',
      headers: c.buyerH,
      body: {
        'live_item_id': li['id'],
        'live_id': li['live_id'],
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'requested_qty': 99,
        'status': 'accepted',
      },
    );
    rec(
      surface: 'LIVE',
      attack: 'buyer INSERT reservation qty=99 accepted',
      identity: 'buyer',
      result: briefBody(ins),
    );
    final rows = asMaps(decode(ins));
    if (rows.isNotEmpty) {
      rec(
        surface: 'LIVE',
        attack: 'observe reservation row',
        identity: 'buyer',
        result:
            'status=${rows.first['status']} qty=${rows.first['requested_qty']}',
        evidence: rows.first,
      );
    }
  } else {
    gaps.add('sem live_items visíveis ao buyer — skip reservation insert');
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
