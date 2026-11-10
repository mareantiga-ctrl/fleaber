// Pass 3 — composition, Stripe TEST capture, live capacity, RPC signatures.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';
late String base, anon, service, buyerId, sellerId, buyerJwt, sellerJwt, freshId, freshJwt;

final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];
final stripe = <Map<String, dynamic>>[];
final notes = <String>[];

Map<String, String> h(String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
Map<String, String> hs() => {
      'apikey': service,
      'Authorization': 'Bearer $service',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

String clip(String s, [int n = 700]) =>
    s.length <= n ? s : '${s.substring(0, n)}…';

Future<Map<String, dynamic>> call(String method, String url,
    {Map<String, String>? headers, Object? body}) async {
  final hdr = headers ?? h(buyerJwt);
  final uri = Uri.parse(url);
  final enc = body == null ? null : jsonEncode(body);
  late http.Response r;
  switch (method) {
    case 'GET':
      r = await http.get(uri, headers: hdr);
      break;
    case 'POST':
      r = await http.post(uri, headers: hdr, body: enc);
      break;
    case 'PATCH':
      r = await http.patch(uri, headers: hdr, body: enc);
      break;
    default:
      r = await http.delete(uri, headers: hdr, body: enc);
  }
  dynamic parsed;
  try {
    parsed = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    parsed = r.body;
  }
  return {'http': r.statusCode, 'body': parsed, 'raw': clip(r.body)};
}

void rec(String s, String a, String id, Map<String, dynamic> r) {
  matrix.add({'surface': s, 'attack': a, 'identity': id, 'http': r['http'], 'result': r['raw']});
}

void find(String id, String sev, String title, String actor, String impact, Map ev) {
  findings.add({
    'id': id,
    'severity': sev,
    'title': title,
    'actor': actor,
    'impact': impact,
    'state': 'OPEN',
    'evidence': ev,
  });
}

dynamic row(dynamic b) => b is List && b.isNotEmpty ? b.first : (b is Map ? b : null);
int? nn(dynamic v) => v is num ? v.round() : int.tryParse('$v');

Future<Map<String, dynamic>> rest(String m, String t,
        {String jwt = '', bool svc = false, String qs = '', Object? body}) =>
    call(m, '$base/rest/v1/$t${qs.isEmpty ? '' : '?$qs'}',
        headers: svc ? hs() : h(jwt.isEmpty ? buyerJwt : jwt), body: body);

Future<Map<String, dynamic>> rpc(String fn, Map p, {String jwt = '', bool svc = false}) =>
    call('POST', '$base/rest/v1/rpc/$fn',
        headers: svc ? hs() : h(jwt.isEmpty ? buyerJwt : jwt), body: p);

Future<Map<String, dynamic>> edge(String fn, Object body, {required String jwt}) =>
    call('POST', '$base/functions/v1/$fn', headers: h(jwt), body: body);

int? amt(dynamic body) =>
    body is Map ? nn(body['server_amount_cents'] ?? body['amount_total']) : null;

Future<void> boot() async {
  final env = loadLiveOpsStagingEnv();
  base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final c = LiveOpsStagingClient(url: base, anonKey: anon, serviceRoleKey: service);
  buyerJwt = await c.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'));
  sellerJwt = await c.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'));
  final nonce = DateTime.now().millisecondsSinceEpoch;
  final email = 'rte3.$nonce@fleaber.staging.invalid';
  final pass = 'RtE3_${nonce}_Aa1!';
  freshId = await c.createAdminUser(email: email, password: pass);
  freshJwt = await c.signIn(email: email, password: pass);
}

Future<void> liveCapacity() async {
  const item = '639da624-cc5a-44fe-a821-9f2ae55c6858';
  const rA = '018e0ead-42b9-49cd-95aa-6ffc2e595ca3';
  const rB = '18160611-1054-45d9-b703-632114f93088';

  final before = await rpc('batata_live_item_stock', {'p_live_item_id': item}, svc: true);
  rec('LIVE', 'stock before accept-patch', 'service_observe', before);

  // Buyer tries to consume capacity: pending → accepted, qty 99
  final acc = await rest('PATCH', 'live_reservation_requests',
      jwt: buyerJwt, qs: 'id=eq.$rA', body: {'status': 'accepted'});
  rec('LIVE RESERVATIONS', 'buyer PATCH pending→accepted qty99', 'buyer', acc);
  final accRow = row(acc['body']);
  if (accRow is Map && '${accRow['status']}' == 'accepted') {
    find('RT-E-LIVE-ACCEPT', 'P1', 'Buyer auto-aceita reserva qty=99', 'buyer',
        'Consome capacidade live sem o vendedor.', {'row': accRow, 'http': acc['http']});
  }

  final accS = await rest('PATCH', 'live_reservation_requests',
      jwt: sellerJwt, qs: 'id=eq.$rA', body: {'status': 'accepted'});
  rec('LIVE RESERVATIONS', 'seller PATCH pending→accepted qty99', 'seller', accS);
  final accSRow = row(accS['body']);
  if (accSRow is Map && '${accSRow['status']}' == 'accepted' && nn(accSRow['requested_qty']) == 99) {
    find('RT-E-LIVE-SELLER-99', 'P1', 'Seller accept persiste qty=99 > stock', 'seller',
        'Reserva aceite acima do stock físico.', {'row': accSRow});
  }

  final mid = await rpc('batata_live_item_stock', {'p_live_item_id': item}, svc: true);
  rec('LIVE', 'stock after accept attempts', 'service_observe', mid);

  // Convert RPC as buyer
  final conv = await rpc('batata_live_reservation_stripe_convert', {
    'p_request_id': rA,
    'p_order_id': '00000000-0000-0000-0000-000000000001',
  }, jwt: buyerJwt);
  rec('rpc:convert', 'buyer convert qty99', 'buyer', conv);

  // Restore live: expire probe reservations (valid status)
  for (final id in [rA, rB, 'c61bca30-5a82-4ce3-8e72-37ba9a183420', 'cbfe925f-9c20-451c-a354-3d4a9db007af']) {
    final ex = await rest('PATCH', 'live_reservation_requests',
        svc: true, qs: 'id=eq.$id', body: {'status': 'expired', 'requested_qty': 1});
    rec('LIVE RESERVATIONS', 'expire $id', 'service_cleanup', ex);
  }
  final after = await rpc('batata_live_item_stock', {'p_live_item_id': item}, svc: true);
  rec('LIVE', 'stock after expire cleanup', 'service_observe', after);
  notes.add('live_stock_restored=${after['raw']}');
}

Future<String> product(int qty, double price) async {
  final r = await rest('POST', 'products', jwt: sellerJwt, body: {
    'seller_id': sellerId,
    'title': 'RT-E3 ${DateTime.now().millisecondsSinceEpoch}',
    'price': price,
    'quantity': qty,
    'list_on_marketplace': true,
    'image_urls': [],
  });
  rec('products', 'insert', 'seller', r);
  return '${row(r['body'])['id']}';
}

Future<Map<String, dynamic>?> order({
  required String jwt,
  required String bid,
  required String pid,
  required Object price,
  required Object qty,
  String status = 'reserva_pendente',
  String ship = 'hand',
  String pay = 'Pagamento na App',
  Map<String, dynamic>? extra,
}) async {
  final r = await rest('POST', 'orders', jwt: jwt, body: {
    'product_id': pid,
    'buyer_id': bid,
    'seller_id': sellerId,
    'price_total': price,
    'status': status,
    'payment_method': pay,
    'shipping_method': ship,
    'quantity': qty,
    'is_reservation': true,
    ...?extra,
  });
  rec('orders', 'INSERT qty=$qty price=$price status=$status', bid == buyerId ? 'buyer' : 'fresh', r);
  final m = row(r['body']);
  return m is Map ? Map<String, dynamic>.from(m) : null;
}

Future<void> priceAuthority() async {
  final pid = await product(3, 20.0);
  final o = await order(jwt: buyerJwt, bid: buyerId, pid: pid, price: 0.5, qty: 1);
  if (o == null) return;
  notes.add('underprice_insert status=${o['status']} qty=${o['quantity']} contract_qty=${o['contract_qty']} unit=${o['contract_unit_cents']} total=${o['price_total']}');

  final c1 = await edge('create-payment-intent', {
    'amount': 50,
    'buyer_id': buyerId,
    'order_id': o['id'],
    'shipping_method': 'hand',
    'quantity': 1,
    'item_price': 0.5,
  }, jwt: buyerJwt);
  rec('CHECKOUT', 'client amount=50 item=20', 'buyer', c1);
  stripe.add({'probe': 'underpay', 'http': c1['http'], 'raw': c1['raw'], 'amt': amt(c1['body'])});
  final a = amt(c1['body']);
  if ((c1['http'] as int) < 300 && a != null && a < 1500) {
    find('RT-E-UNDERPAY', 'P0', 'Checkout abaixo do catálogo/contrato', 'buyer',
        'Session Stripe < preço legítimo.', {'amt': a, 'raw': c1['raw']});
  }

  final prize = await edge('create-payment-intent', {
    'buyer_id': buyerId,
    'order_id': o['id'],
    'shipping_method': 'carrier',
    'prize_shipping': true,
  }, jwt: buyerJwt);
  rec('CHECKOUT', 'prize_shipping on 20€ item', 'buyer', prize);
  stripe.add({'probe': 'prize', 'http': prize['http'], 'raw': prize['raw'], 'amt': amt(prize['body'])});

  final pt = await rest('PATCH', 'orders', jwt: buyerJwt, qs: 'id=eq.${o['id']}', body: {
    'contract_unit_cents': 1,
    'contract_qty': 1,
    'price_total': 0.01,
    'quantity': 1,
    'status': 'pago',
    'amount_paid_cents': 1,
  });
  rec('orders', 'PATCH contract+pago', 'buyer', pt);
  final obs = await rest('GET', 'orders', svc: true,
      qs: 'id=eq.${o['id']}&select=id,status,contract_unit_cents,contract_qty,price_total,amount_paid_cents,quantity');
  rec('orders', 'observe patch', 'service_observe', obs);
  final ar = row(obs['body']);
  if (ar is Map) {
    if ('${ar['status']}'.toLowerCase() == 'pago') {
      find('RT-E-PATCH-PAGO', 'P0', 'Buyer PATCH pago persiste', 'buyer', 'Estado pago sem Stripe.', {'row': ar});
    }
    if (nn(ar['contract_unit_cents']) == 1) {
      find('RT-E-PATCH-UNIT', 'P0', 'Buyer altera contract_unit_cents', 'buyer', 'Contrato reescrito.', {'row': ar});
    }
  }

  await rest('PATCH', 'products', jwt: sellerJwt, qs: 'id=eq.$pid', body: {'price': 1.0});
  final c2 = await edge('create-payment-intent', {
    'buyer_id': buyerId,
    'order_id': o['id'],
    'shipping_method': 'hand',
  }, jwt: buyerJwt);
  rec('CHECKOUT', 'after seller drops catalog to 1€', 'buyer', c2);
  stripe.add({'probe': 'catalog_drop', 'http': c2['http'], 'raw': c2['raw'], 'amt': amt(c2['body'])});
}

Future<void> stock1Capture() async {
  final pid = await product(1, 8.0);
  final oa = await order(jwt: buyerJwt, bid: buyerId, pid: pid, price: 8, qty: 1);
  final ob = await order(jwt: freshJwt, bid: freshId, pid: pid, price: 8, qty: 1);
  notes.add('stock1_orders a=${oa?['id']} b=${ob?['id']}');
  if (oa == null || ob == null) {
    notes.add('stock1 one order missing');
    return;
  }
  final sa = await edge('create-payment-intent', {
    'buyer_id': buyerId,
    'order_id': oa['id'],
    'shipping_method': 'hand',
  }, jwt: buyerJwt);
  final sb = await edge('create-payment-intent', {
    'buyer_id': freshId,
    'order_id': ob['id'],
    'shipping_method': 'hand',
  }, jwt: freshJwt);
  rec('CHECKOUT', 'stock1 session A', 'buyer', sa);
  rec('CHECKOUT', 'stock1 session B', 'fresh', sb);
  stripe.add({
    'probe': 'stock1_A',
    'http': sa['http'],
    'raw': sa['raw'],
    'order_id': oa['id'],
    'product_id': pid,
    'amt': amt(sa['body']),
    'session': sa['body'] is Map ? sa['body']['checkoutSessionId'] : null,
    'url': sa['body'] is Map ? sa['body']['checkoutUrl'] : null,
  });
  stripe.add({
    'probe': 'stock1_B',
    'http': sb['http'],
    'raw': sb['raw'],
    'order_id': ob['id'],
    'product_id': pid,
    'amt': amt(sb['body']),
    'session': sb['body'] is Map ? sb['body']['checkoutSessionId'] : null,
    'url': sb['body'] is Map ? sb['body']['checkoutUrl'] : null,
  });
  File('tool/redteam_indep_e_20260829/stripe_sessions_to_pay.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'product_id': pid,
      'orders': [oa['id'], ob['id']],
      'sessions': stripe.where((e) => '${e['probe']}'.startsWith('stock1_')).toList(),
      'note': 'DO NOT cancel these orders before TEST pay',
    }),
  );
}

Future<void> rpcSignatures() async {
  final attempts = <Map<String, dynamic>>[
    {
      'fn': 'batata_credit_wallet_once',
      'p': {
        'p_wallet_id': sellerId,
        'p_amount': 10,
        'p_type': 'venda',
        'p_description': 'hostile',
        'p_order_id': null,
      }
    },
    {
      'fn': 'batata_debit_wallet_once',
      'p': {
        'p_wallet_id': sellerId,
        'p_amount': 1,
        'p_type': 'levantamento',
        'p_description': 'hostile',
        'p_order_id': null,
      }
    },
    {
      'fn': 'batata_release_seller_wallet_for_order',
      'p': {'p_order_id': '00000000-0000-0000-0000-000000000001'}
    },
    {
      'fn': 'batata_clawback_seller_wallet_for_order',
      'p': {'p_order_id': '00000000-0000-0000-0000-000000000001'}
    },
    {
      'fn': 'batata_refund_buyer_wallet_for_order',
      'p': {'p_order_id': '00000000-0000-0000-0000-000000000001'}
    },
    {
      'fn': 'batata_process_partial_refund_dispute',
      'p': {
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_amount_cents': 100,
      }
    },
    {
      'fn': 'batata_admin_resolve_dispute',
      'p': {
        'p_dispute_id': '00000000-0000-0000-0000-000000000001',
        'p_action': 'refund',
      }
    },
    {
      'fn': 'batata_wallet_apply_tip_once',
      'p': {
        'p_tip_id': '00000000-0000-0000-0000-000000000001',
        'p_amount': 5,
      }
    },
    {
      'fn': 'staging_restore_stock_before_nuke',
      'p': {'p_product_id': '00000000-0000-0000-0000-000000000001'}
    },
    {
      'fn': 'batata_send_live_tip_from_wallet',
      'p': {
        'p_seller_id': sellerId,
        'p_amount': 1,
        'p_live_id': null,
      }
    },
  ];
  for (final a in attempts) {
    final r = await rpc('${a['fn']}', Map<String, dynamic>.from(a['p'] as Map), jwt: buyerJwt);
    rec('rpc:${a['fn']}', 'buyer full args', 'buyer', r);
    final raw = '${r['raw']}';
    if ((r['http'] as int) < 300 &&
        (raw.contains('"ok":true') || raw.contains('balance') || !raw.contains('denied'))) {
      if (!raw.contains('permission') &&
          !raw.contains('Acesso') &&
          !raw.contains('not found') &&
          !raw.contains('PGRST') &&
          (r['http'] as int) != 404) {
        notes.add('RPC_INTERESTING ${a['fn']} ${r['http']} $raw');
      }
    }
  }
}

Future<void> storageGet() async {
  final list = await call('POST', '$base/storage/v1/object/list/chat_media',
      headers: h(freshJwt),
      body: {'prefix': 'product_photos/980f4fa1-0004-42f9-abca-69f1a9c29588', 'limit': 10});
  rec('storage', 'list seller product_photos', 'fresh', list);
  if (list['body'] is List && (list['body'] as List).isNotEmpty) {
    final first = (list['body'] as List).first;
    if (first is Map && first['name'] != null) {
      final path =
          'product_photos/980f4fa1-0004-42f9-abca-69f1a9c29588/${first['name']}';
      final get = await call('GET', '$base/storage/v1/object/chat_media/$path',
          headers: h(freshJwt));
      rec('storage', 'GET seller object', 'fresh', {
        'http': get['http'],
        'raw': 'http=${get['http']} len=${'${get['raw']}'.length}',
        'body': get['http'],
      });
    }
  }
}

void main() async {
  await boot();
  try {
    await liveCapacity();
    await priceAuthority();
    await stock1Capture();
    await rpcSignatures();
    await storageGet();
  } finally {
    // Always try expire leftovers
    try {
      await liveCapacity();
    } catch (_) {}
  }
  final out = {
    'pass': '3',
    'frozen_at': DateTime.now().toUtc().toIso8601String(),
    'findings': findings,
    'matrix': matrix,
    'stripe': stripe,
    'notes': notes,
  };
  File('tool/redteam_indep_e_20260829/pass3_raw.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('FINDINGS=${findings.length}');
  for (final f in findings) {
    stdout.writeln('${f['severity']} ${f['id']} ${f['title']}');
  }
  stdout.writeln('STRIPE=${jsonEncode(stripe.map((e) => {
        'probe': e['probe'],
        'http': e['http'],
        'amt': e['amt'],
        'session': e['session'],
      }).toList())}');
}
