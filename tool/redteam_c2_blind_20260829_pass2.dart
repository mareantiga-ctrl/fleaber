/// Pass 2 — verificar efeito real e cadeias compostas (sem service_role).
import 'dart:convert';
import 'dart:io';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const base = 'https://fxdknzrqjenzqcvnwqqq.supabase.co';
final httpClient = HttpClient();
late String anon, buyerJwt, sellerJwt, extraJwt, extraEmail;
late String buyerId, sellerId, extraId;
final out = <Map<String, dynamic>>[];

Map<String, String> loadEnv(String path) {
  final m = <String, String>{};
  for (final raw in File(path).readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final i = line.indexOf('=');
    if (i <= 0) continue;
    m[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  return m;
}

Future<Map<String, dynamic>> signIn(String email, String password) async {
  final uri = Uri.parse('$base/auth/v1/token?grant_type=password');
  final r = await httpClient.postUrl(uri);
  r.headers.set('apikey', anon);
  r.headers.set('Authorization', 'Bearer $anon');
  r.headers.set('Content-Type', 'application/json');
  r.add(utf8.encode(jsonEncode({'email': email, 'password': password})));
  final resp = await r.close();
  final txt = await utf8.decodeStream(resp);
  if (resp.statusCode >= 300) throw StateError('signin $email ${resp.statusCode} $txt');
  return jsonDecode(txt) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> req(
  String jwt,
  String method,
  String path, {
  Object? body,
  bool fn = false,
}) async {
  final uri = Uri.parse(fn ? '$base/functions/v1/$path' : '$base/rest/v1/$path');
  final r = await httpClient.openUrl(method, uri);
  r.headers.set('apikey', anon);
  r.headers.set('Authorization', 'Bearer $jwt');
  r.headers.set('Accept', 'application/json');
  if (!fn) r.headers.set('Prefer', 'return=representation');
  if (body != null) {
    r.headers.set('Content-Type', 'application/json');
    r.add(utf8.encode(jsonEncode(body)));
  }
  final resp = await r.close().timeout(const Duration(seconds: 40));
  final txt = await utf8.decodeStream(resp);
  dynamic parsed;
  try {
    parsed = txt.isEmpty ? null : jsonDecode(txt);
  } catch (_) {
    parsed = txt;
  }
  return {'status': resp.statusCode, 'body': parsed, 'raw': txt.length > 2000 ? txt.substring(0, 2000) : txt};
}

void note(String id, String kind, String title, dynamic ev, {String sev = ''}) {
  out.add({'id': id, 'kind': kind, 'severity': sev, 'title': title, 'evidence': ev});
  stdout.writeln('$kind ${sev.isEmpty ? '' : sev } $id $title');
}

List asList(dynamic v) => v is List ? v : const [];
Map<String, dynamic>? asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

Future<void> main() async {
  final env = loadEnv('${Directory.current.path}/tool/live_ops_staging.env');
  anon = env['SUPABASE_ANON_KEY']!;
  final b = await signIn(env['LIVE_OPS_TEST_BUYER_EMAIL']!, env['LIVE_OPS_TEST_BUYER_PASSWORD']!);
  final s = await signIn(env['LIVE_OPS_TEST_SELLER_EMAIL']!, env['LIVE_OPS_TEST_SELLER_PASSWORD']!);
  buyerJwt = b['access_token'] as String;
  sellerJwt = s['access_token'] as String;
  buyerId = (b['user'] as Map)['id'] as String;
  sellerId = (s['user'] as Map)['id'] as String;

  extraEmail = 'c2p2${DateTime.now().millisecondsSinceEpoch}@axinoquaa.pt';
  final su = await httpClient.postUrl(Uri.parse('$base/auth/v1/signup'));
  su.headers.set('apikey', anon);
  su.headers.set('Authorization', 'Bearer $anon');
  su.headers.set('Content-Type', 'application/json');
  su.add(utf8.encode(jsonEncode({'email': extraEmail, 'password': 'testeteste123'})));
  final suResp = await su.close();
  final suJson = jsonDecode(await utf8.decodeStream(suResp)) as Map<String, dynamic>;
  extraJwt = (suJson['access_token'] ?? '') as String;
  extraId = ((suJson['user'] as Map?)?['id'] ?? '') as String;

  // --- wallets unchanged ---
  final wB = await req(buyerJwt, 'GET', 'wallets?select=id,balance');
  final wS = await req(sellerJwt, 'GET', 'wallets?select=id,balance');
  note('V-WALLET', 'INFO', 'saldos actuais', {'buyer': wB['body'], 'seller': wS['body']});

  // --- credit with hinted signature ---
  final credit = await req(buyerJwt, 'POST', 'rpc/batata_credit_wallet_once', body: {
    'p_wallet_id': buyerId,
    'p_order_id': '00000000-0000-0000-0000-000000000001',
    'p_amount': 12.34,
    'p_type': 'reembolso',
    'p_description': 'c2p2',
  });
  final wAfterCredit = await req(buyerJwt, 'GET', 'wallets?select=id,balance');
  note(
    'V-CREDIT-HINT',
    (credit['status'] == 200 && credit['body'] == true) ? 'FINDING' : 'BLOCKED',
    'credit_wallet_once com p_wallet_id',
    {'rpc': credit, 'wallet_after': wAfterCredit['body']},
    sev: (credit['status'] == 200 && credit['body'] == true) ? 'P0' : '',
  );

  // --- order 773b6677 MB WAY skip to concluido + wallet release ---
  const mbOid = '773b6677-4b56-4439-b1da-7613017b7dcf';
  final mb = await req(
    buyerJwt,
    'GET',
    'orders?id=eq.$mbOid&select=id,status,payment_method,price_total,amount_paid_cents,quantity,contract_unit_cents,contract_qty,stock_units_applied,wallet_release_processed_at,wallet_refund_processed_at,stripe_payment_intent_id',
  );
  note('V-MB-STATE', 'INFO', 'estado order MB WAY skip', mb['body']);
  final rel = await req(buyerJwt, 'POST', 'rpc/batata_release_seller_wallet_for_order', body: {'p_order_id': mbOid});
  final wS2 = await req(sellerJwt, 'GET', 'wallets?select=id,balance');
  final mb2 = await req(
    buyerJwt,
    'GET',
    'orders?id=eq.$mbOid&select=id,status,wallet_release_processed_at,amount_paid_cents',
  );
  note(
    'V-MB-RELEASE',
    rel['body'] == true ? 'FINDING' : 'BLOCKED',
    'release wallet após buyer PATCH concluido (MB WAY)',
    {
      'rpc': rel,
      'seller_wallet_after': wS2['body'],
      'order_after': mb2['body'],
    },
    sev: rel['body'] == true ? 'P0' : '',
  );

  // seller also tries release
  final relS = await req(sellerJwt, 'POST', 'rpc/batata_release_seller_wallet_for_order', body: {'p_order_id': mbOid});
  note('V-MB-RELEASE-SELLER', relS['body'] == true ? 'FINDING' : 'BLOCKED', 'seller release mesma order', relS, sev: relS['body'] == true ? 'P0' : '');

  // --- Stripe paid → buyer PATCH concluido → release ---
  const stripePaid = 'ff715140-e028-4cf5-a433-93b63c0124ce';
  final beforeSp = await req(buyerJwt, 'GET', 'orders?id=eq.$stripePaid&select=id,status,amount_paid_cents,wallet_release_processed_at');
  final patchCon = await req(buyerJwt, 'PATCH', 'orders?id=eq.$stripePaid', body: {'status': 'concluido'});
  final afterSp = await req(buyerJwt, 'GET', 'orders?id=eq.$stripePaid&select=id,status,wallet_release_processed_at,amount_paid_cents');
  final patchedRow = asList(afterSp['body']);
  final st = patchedRow.isEmpty ? '' : '${asMap(patchedRow.first)?['status']}';
  note(
    'V-STRIPE-SKIP-CONCLUIDO',
    st == 'concluido' ? 'FINDING' : 'BLOCKED',
    'buyer PATCH pago Stripe → concluido',
    {'before': beforeSp['body'], 'patch_http': patchCon['status'], 'patch_raw': patchCon['raw'], 'after': afterSp['body']},
    sev: st == 'concluido' ? 'P1' : '',
  );
  if (st == 'concluido') {
    final rel2 = await req(buyerJwt, 'POST', 'rpc/batata_release_seller_wallet_for_order', body: {'p_order_id': stripePaid});
    final wS3 = await req(sellerJwt, 'GET', 'wallets?select=id,balance');
    note(
      'V-STRIPE-RELEASE-AFTER-SKIP',
      rel2['body'] == true ? 'FINDING' : 'BLOCKED',
      'release wallet após skip concluido em Stripe pago',
      {'rpc': rel2, 'seller_wallet': wS3['body']},
      sev: rel2['body'] == true ? 'P0' : '',
    );
  }

  // extra buyer skip unpaid → concluido
  if (extraJwt.isNotEmpty) {
    final ins = await req(extraJwt, 'POST', 'orders', body: {
      'product_id': '7fde1403-5a3c-47cd-8fe6-dab6ad863016',
      'buyer_id': extraId,
      'seller_id': sellerId,
      'price_total': 5,
      'shipping_method': 'Entrega em mão (€0.00)',
      'payment_method': 'MB WAY',
      'status': 'reserva_pendente',
      'quantity': 1,
    });
    final insRows = asList(ins['body']);
    final eoid = insRows.isEmpty ? null : asMap(insRows.first)?['id'];
    note('V-EXTRA-INS', 'INFO', 'extra INSERT MB WAY', {'http': ins['status'], 'raw': ins['raw']});
    if (eoid != null) {
      final p = await req(extraJwt, 'PATCH', 'orders?id=eq.$eoid', body: {'status': 'concluido'});
      final g = await req(extraJwt, 'GET', 'orders?id=eq.$eoid&select=id,status');
      final gst = asList(g['body']).isEmpty ? '' : '${asMap(asList(g['body']).first)?['status']}';
      note(
        'V-EXTRA-SKIP-UNPAID-CONCLUIDO',
        gst == 'concluido' ? 'FINDING' : 'BLOCKED',
        'extra PATCH reserva_pendente → concluido sem seller pago',
        {'patch': p['raw'], 'after': g['body']},
        sev: gst == 'concluido' ? 'P1' : '',
      );
    }
  }

  // --- patched order f756d43a fields ---
  const probeOid = 'f756d43a-8d04-4a41-b231-4447a2a2d223';
  final probe = await req(
    buyerJwt,
    'GET',
    'orders?id=eq.$probeOid&select=id,status,price_total,quantity,amount_paid_cents,contract_unit_cents,contract_qty,stripe_payment_intent_id',
  );
  note('V-PROBE-ORDER-FIELDS', 'INFO', 'campos após PATCHes', probe['body']);

  // --- live mix order ---
  const mixOid = '3f3f6001-a7d0-41d9-9680-24fa21f5e073';
  final mix = await req(
    buyerJwt,
    'GET',
    'orders?id=eq.$mixOid&select=id,status,live_id,live_item_id,product_id,price_total,contract_unit_cents',
  );
  note('V-LIVE-MIX-FIELDS', 'INFO', 'order live_id vs live_item_id', mix['body']);
  final mixRows = asList(mix['body']);
  if (mixRows.isNotEmpty) {
    final m = asMap(mixRows.first)!;
    final liveA = '${m['live_id']}';
    final itemB = '${m['live_item_id']}';
    final item = await req(buyerJwt, 'GET', 'live_items?id=eq.$itemB&select=id,live_id,price,product_id');
    final related = asList(item['body']).isEmpty
        ? false
        : '${asMap(asList(item['body']).first)?['live_id']}' == liveA;
    note(
      'V-LIVE-MIX-RELATION',
      related ? 'BLOCKED' : 'FINDING',
      'relação live_item.live_id vs order.live_id',
      {'order': m, 'item': item['body']},
      sev: related ? '' : 'P2',
    );
    final ck = await req(buyerJwt, 'create-payment-intent', 'POST', body: {
      'buyer_id': buyerId,
      'order_id': mixOid,
      'shipping_method': 'hand',
    }, fn: true);
    // oops - path wrong. fix below via edge helper
    note('V-LIVE-MIX-CHECKOUT-ATTEMPT', 'INFO', 'placeholder', ck);
  }

  // proper checkout of mixed order
  final mixCk = await req(
    buyerJwt,
    'POST',
    'create-payment-intent',
    body: {
      'buyer_id': buyerId,
      'order_id': mixOid,
      'shipping_method': 'hand',
    },
    fn: true,
  );
  note('V-LIVE-MIX-CHECKOUT', 'CHAIN', 'checkout order com live cruzado', mixCk);

  // --- banking oracle: extra (no relationship) vs buyer (counterparty) ---
  if (extraJwt.isNotEmpty) {
    final bankX = await req(extraJwt, 'POST', 'rpc/batata_seller_direct_payment_details', body: {'p_seller_id': sellerId});
    final leaked = asList(bankX['body']).isNotEmpty;
    note(
      'V-BANK-NO-RELATION',
      leaked ? 'FINDING' : 'BLOCKED',
      'extra sem encomendas lê IBAN/MB WAY do seller',
      bankX,
      sev: leaked ? 'P1' : '',
    );
  }
  final bankB = await req(buyerJwt, 'POST', 'rpc/batata_seller_direct_payment_details', body: {'p_seller_id': sellerId});
  note('V-BANK-COUNTERPARTY', 'INFO', 'buyer com relação comercial', bankB);

  // other seller (69104e91) as extra
  if (extraJwt.isNotEmpty) {
    final bankY = await req(extraJwt, 'POST', 'rpc/batata_seller_direct_payment_details', body: {
      'p_seller_id': '69104e91-6a00-40d9-a7c9-b1571422ae43',
    });
    note(
      'V-BANK-STRANGER-SELLER',
      asList(bankY['body']).isNotEmpty ? 'FINDING' : 'BLOCKED',
      'extra lê payout de seller sem relação',
      bankY,
      sev: asList(bankY['body']).isNotEmpty ? 'P1' : '',
    );
  }

  // --- events of other buyers ---
  final ev = await req(
    buyerJwt,
    'GET',
    'stripe_checkout_events?select=event,order_id,session_id,buyer_id&buyer_id=neq.$buyerId&limit=5',
  );
  note('V-EV-FOREIGN-BUYER-ID', 'INFO', 'events com buyer_id alheio', {'http': ev['status'], 'n': asList(ev['body']).length, 'body': ev['body']});

  final evNull = await req(
    buyerJwt,
    'GET',
    'stripe_checkout_events?select=event,order_id,session_id,buyer_id&order_id=not.is.null&limit=8',
  );
  note('V-EV-ANY', 'INFO', 'events sample', {'n': asList(evNull['body']).length, 'sample': ev['status'] == 200 || ev['status'] == 206 ? evNull['body'] : evNull['raw']});

  // --- qty patch then checkout ---
  final hold = await req(buyerJwt, 'POST', 'orders', body: {
    'product_id': '7fde1403-5a3c-47cd-8fe6-dab6ad863016',
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'price_total': 5,
    'shipping_method': 'Entrega em mão (€0.00)',
    'payment_method': 'Seguro Fleaber',
    'status': 'reserva_pendente',
    'quantity': 1,
  });
  final hRows = asList(hold['body']);
  if (hRows.isNotEmpty) {
    final hid = asMap(hRows.first)!['id'];
    final qPatch = await req(buyerJwt, 'PATCH', 'orders?id=eq.$hid', body: {'quantity': 6});
    final afterQ = await req(buyerJwt, 'GET', 'orders?id=eq.$hid&select=id,quantity,contract_qty,status');
    note('V-QTY-PATCH', 'INFO', 'PATCH quantity próprio', {'patch': qPatch['raw'], 'after': afterQ['body']});
    final qAfter = asList(afterQ['body']);
    final qty = qAfter.isEmpty ? null : asMap(qAfter.first)?['quantity'];
    if (qty == 6) {
      final ck = await req(buyerJwt, 'POST', 'create-payment-intent', body: {
        'buyer_id': buyerId,
        'order_id': hid,
        'shipping_method': 'hand',
        'quantity': 6,
      }, fn: true);
      note(
        'V-QTY-CHECKOUT',
        'CHAIN',
        'checkout após inflar quantity',
        ck,
      );
    }
  }

  // --- raffle join other seller then prize order insert ---
  const otherRaffle = 'c54e3007-8ccb-4afc-98f3-0c61823b7348';
  final prizeIns = await req(buyerJwt, 'POST', 'orders', body: {
    'product_id': '7fde1403-5a3c-47cd-8fe6-dab6ad863016',
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'price_total': 0,
    'shipping_method': 'Envio transportadora (€3.50)',
    'payment_method': 'premio_rifa',
    'status': 'premio_rifa',
    'live_raffle_id': otherRaffle,
    'quantity': 1,
  });
  note('V-PRIZE-FORGE', asList(prizeIns['body']).isNotEmpty ? 'FINDING' : 'BLOCKED', 'INSERT order premio_rifa rifa alheia', prizeIns, sev: asList(prizeIns['body']).isNotEmpty ? 'P1' : '');
  final prizeRows = asList(prizeIns['body']);
  if (prizeRows.isNotEmpty) {
    final poid = asMap(prizeRows.first)!['id'];
    final pck = await req(buyerJwt, 'POST', 'create-payment-intent', body: {
      'buyer_id': buyerId,
      'order_id': poid,
      'prize_shipping': true,
      'shipping_method': 'carrier',
    }, fn: true);
    note(
      'V-PRIZE-CHECKOUT',
      (pck['status'] == 200) ? 'FINDING' : 'BLOCKED',
      'checkout portes prémio sem ser winner',
      pck,
      sev: pck['status'] == 200 ? 'P0' : '',
    );
  }

  // profiles phone of seller
  final ph = await req(buyerJwt, 'GET', 'profiles?id=eq.$sellerId&select=id,phone');
  note('V-PHONE', 'INFO', 'phone seller', ph);

  File('tool/reports/REDTEAM_C2_BLIND_20260829_PASS2.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'frozen_at': DateTime.now().toUtc().toIso8601String(),
      'extra_id': extraId,
      'extra_email': extraEmail,
      'results': out,
    }),
  );
  stdout.writeln('WROTE pass2 n=${out.length}');
}
