// ignore_for_file: avoid_print
/// Passagem B — variantes + prova de efeito (não 200 vazio).
/// dart run tool/sec_sat_indep_passB_20260827.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

typedef Json = Map<String, dynamic>;

Future<Json> req(String method, String url, Map<String, String> h, [Object? body]) async {
  late http.Response r;
  try {
    r = method == 'POST'
        ? await http.post(Uri.parse(url), headers: h, body: body == null ? null : jsonEncode(body))
        : method == 'PATCH'
            ? await http.patch(Uri.parse(url), headers: h, body: jsonEncode(body))
            : method == 'DELETE'
                ? await http.delete(Uri.parse(url), headers: h)
                : await http.get(Uri.parse(url), headers: h);
  } catch (e) {
    return {'http': 0, 'body': '$e'};
  }
  dynamic p;
  try {
    p = jsonDecode(r.body);
  } catch (_) {
    p = r.body.length > 3000 ? r.body.substring(0, 3000) : r.body;
  }
  return {'http': r.statusCode, 'body': p, 'len': r.body.length};
}

Json? row(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Json.from(body.first as Map);
  }
  if (body is Map) return Json.from(body);
  return null;
}

int nRows(dynamic body) => body is List ? body.length : 0;
String snip(dynamic b, [int m = 600]) {
  final s = b is String ? b : jsonEncode(b);
  return s.length <= m ? s : s.substring(0, m);
}

void main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SH = {
    'apikey': anon,
    'Authorization': 'Bearer $sellerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final AN = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final out = <String, dynamic>{};
  void rec(String id, Object? v) {
    out[id] = v;
    stdout.writeln('$id ${v is Map ? jsonEncode(v) : v}');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final pids = <String>[];
  final oids = <String>[];

  Future<Json> mkP(num price, int qty) async {
    final p = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'SATB $stamp $price',
      'price': price,
      'quantity': qty,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    pids.add('${p['id']}');
    return p;
  }

  // buyer profile restored?
  rec('buyer_user_type', row((await req('GET', '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type,iban,phone_verified_at', SVC))['body']));

  // OpenAPI with user jwt
  final oa = await http.get(Uri.parse('$url/rest/v1/'), headers: {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Accept': 'application/openapi+json',
  });
  rec('openapi_http', oa.statusCode);
  rec('openapi_len', oa.body.length);

  // Anon SELECT with Prefer count
  final anonTables = [
    'chats',
    'chat_messages',
    'orders',
    'wallets',
    'wallet_transactions',
    'live_tips',
    'live_reservation_requests',
    'live_raffle_winners',
    'live_raffles',
    'order_disputes',
    'reviews',
    'product_offers',
    'product_bundles',
    'stripe_checkout_events',
    'ps_ingest_audit',
    'products',
    'profiles',
  ];
  for (final t in anonTables) {
    final r = await req('GET', '$url/rest/v1/$t?select=*&limit=5', {
      ...AN,
      'Prefer': 'count=exact',
    });
    rec('anon_$t', {
      'http': r['http'],
      'n': nRows(r['body']),
      'sample_keys': row(r['body'])?.keys.toList(),
      'sample': snip(row(r['body']), 400),
    });
  }

  // Buyer reads seller wallet / other orders
  rec('buyer_wallets', {
    'http': (await req('GET', '$url/rest/v1/wallets?select=*&limit=10', BH))['http'],
    'n': nRows((await req('GET', '$url/rest/v1/wallets?select=id,balance,pending_balance,available_balance&limit=10', BH))['body']),
    'body': snip((await req('GET', '$url/rest/v1/wallets?select=id,balance&limit=10', BH))['body'], 500),
  });
  rec('buyer_wallet_tx', snip((await req('GET', '$url/rest/v1/wallet_transactions?select=*&limit=5', BH))['body'], 500));
  rec('buyer_events', {
    'n': nRows((await req('GET', '$url/rest/v1/stripe_checkout_events?select=id,event,order_id,buyer_id,session_id&limit=8', BH))['body']),
    'sample': snip(row((await req('GET', '$url/rest/v1/stripe_checkout_events?select=id,event,order_id,buyer_id,detail&limit=3', BH))['body']), 500),
  });
  rec('seller_events', {
    'n': nRows((await req('GET', '$url/rest/v1/stripe_checkout_events?select=id,event,order_id,buyer_id&limit=8', SH))['body']),
  });
  rec('buyer_ingest_audit', {
    'n': nRows((await req('GET', '$url/rest/v1/ps_ingest_audit?select=*&limit=5', BH))['body']),
    'sample': snip(row((await req('GET', '$url/rest/v1/ps_ingest_audit?select=*&limit=1', BH))['body']), 400),
  });
  rec('buyer_tips', {
    'n': nRows((await req('GET', '$url/rest/v1/live_tips?select=id,buyer_id,seller_id,amount,status&limit=8', BH))['body']),
    'sample': snip(row((await req('GET', '$url/rest/v1/live_tips?select=id,buyer_id,seller_id,amount,status&limit=3', BH))['body']), 400),
  });
  rec('buyer_reservations_all', {
    'n': nRows((await req('GET', '$url/rest/v1/live_reservation_requests?select=id,buyer_id,status,requested_qty&limit=10', BH))['body']),
    'foreign': nRows((await req('GET', '$url/rest/v1/live_reservation_requests?buyer_id=neq.$buyerId&select=id,buyer_id,status&limit=10', BH))['body']),
  });
  rec('lives_safe_buyer', await req('GET', '$url/rest/v1/lives?select=id,status,is_active,title,mux_playback_id&limit=3', BH));
  rec('lives_safe_anon', await req('GET', '$url/rest/v1/lives?select=id,status,is_active,title&limit=3', AN));

  // price_total insert vs contract vs checkout
  final p40 = await mkP(40, 3);
  final oCheap = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': p40['id'],
    'quantity': 1,
    'price_total': 0.5,
    'contract_unit_cents': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
    'shipping_method': 'entrega em mão',
  });
  final oc = row(oCheap['body']);
  if (oc?['id'] != null) oids.add('${oc!['id']}');
  rec('price_insert', {
    'http': oCheap['http'],
    'cuc': oc?['contract_unit_cents'],
    'cq': oc?['contract_qty'],
    'pt': oc?['price_total'],
    'qty': oc?['quantity'],
    'status': oc?['status'],
    'paid': oc?['amount_paid_cents'],
  });
  if (oc?['id'] != null) {
    final ck = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'buyer_id': buyerId,
      'order_id': oc!['id'],
      'amount': 50,
      'shipping_method': 'entrega em mão',
    });
    rec('checkout_vs_pt05', {
      'http': ck['http'],
      'body': snip(ck['body'], 400),
    });
    final after = row((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.${oc['id']}&select=price_total,contract_unit_cents,amount_paid_cents,stripe_checkout_session_id',
      SVC,
    ))['body']);
    rec('order_after_checkout_create', after);
  }

  // admin user_type variant
  final ut0 = row((await req('GET', '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type', SVC))['body']);
  for (final v in ['admin', 'admim', 'administrador', 'staff']) {
    await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', BH, {'user_type': v});
    final a = row((await req('GET', '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type', SVC))['body']);
    rec('user_type_$v', {'before': ut0?['user_type'], 'after': a?['user_type']});
  }
  await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', SVC, {'user_type': ut0?['user_type']});

  // anon cancel on FRESH order
  final pC = await mkP(9, 2);
  final oFresh = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pC['id'],
    'quantity': 1,
    'price_total': 9,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  final of = row(oFresh['body']);
  if (of?['id'] != null) oids.add('${of!['id']}');
  final anonCan = await req('PATCH', '$url/rest/v1/orders?id=eq.${of?['id']}', AN, {'status': 'cancelado'});
  final afterAnon = row((await req('GET', '$url/rest/v1/orders?id=eq.${of?['id']}&select=status', SVC))['body']);
  rec('anon_cancel_fresh', {
    'http': anonCan['http'],
    'body': snip(anonCan['body'], 200),
    'status_after': afterAnon?['status'],
  });
  final buyerCan = await req('PATCH', '$url/rest/v1/orders?id=eq.${of?['id']}', BH, {'status': 'cancelado'});
  final afterB = row((await req('GET', '$url/rest/v1/orders?id=eq.${of?['id']}&select=status', SVC))['body']);
  rec('buyer_cancel_unpaid', {'http': buyerCan['http'], 'status_after': afterB?['status']});

  // reservation insert status
  final lives = row((await req('GET', '$url/rest/v1/lives?select=id,seller_id&limit=1', SVC))['body']);
  if (lives?['id'] != null) {
    final li = row((await req('GET', '$url/rest/v1/live_items?live_id=eq.${lives!['id']}&select=id,price,product_id&limit=1', SVC))['body']);
    if (li?['id'] != null) {
      final ins = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
        'live_id': lives['id'],
        'live_item_id': li!['id'],
        'buyer_id': buyerId,
        'seller_id': lives['seller_id'],
        'requested_qty': 3,
        'status': 'accepted',
      });
      rec('res_insert', {'http': ins['http'], 'row': snip(row(ins['body']), 400)});
      final rid = row(ins['body'])?['id'];
      if (rid != null) {
        await req('PATCH', '$url/rest/v1/live_reservation_requests?id=eq.$rid', BH, {
          'status': 'accepted',
          'requested_qty': 9,
        });
        rec('res_after_buyer_patch', row((await req(
          'GET',
          '$url/rest/v1/live_reservation_requests?id=eq.$rid&select=status,requested_qty,buyer_id',
          SVC,
        ))['body']));
        await req('DELETE', '$url/rest/v1/live_reservation_requests?id=eq.$rid', SVC);
      }
    }
  }

  // bag amounts
  final pa = await mkP(10, 4);
  final pb = await mkP(7, 4);
  final oa1 = row((await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pa['id'],
    'quantity': 1,
    'price_total': 10,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
    'shipping_method': 'entrega em mão',
  }))['body']);
  final oa2 = row((await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pb['id'],
    'quantity': 1,
    'price_total': 7,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
    'shipping_method': 'entrega em mão',
  }))['body']);
  if (oa1?['id'] != null) oids.add('${oa1!['id']}');
  if (oa2?['id'] != null) oids.add('${oa2!['id']}');
  rec('bag_contracts', {
    'a': {'cuc': oa1?['contract_unit_cents'], 'pt': oa1?['price_total']},
    'b': {'cuc': oa2?['contract_unit_cents'], 'pt': oa2?['price_total']},
  });
  final bag = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
    'buyer_id': buyerId,
    'order_id': oa1?['id'],
    'bag_checkout': true,
    'shipping_method': 'entrega em mão',
    'bag_lines': [
      {'order_id': oa1?['id'], 'line_total_cents': 1},
      {'order_id': oa2?['id'], 'line_total_cents': 1},
    ],
    'amount': 2,
  });
  rec('bag_quote', {'http': bag['http'], 'body': bag['body']});

  // oversell bag qty=1 two orders
  final po = await mkP(5, 1);
  final x1 = row((await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': po['id'],
    'quantity': 1,
    'price_total': 5,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
    'shipping_method': 'entrega em mão',
  }))['body']);
  final x2 = row((await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': po['id'],
    'quantity': 1,
    'price_total': 5,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
    'shipping_method': 'entrega em mão',
  }))['body']);
  if (x1?['id'] != null) oids.add('${x1!['id']}');
  if (x2?['id'] != null) oids.add('${x2!['id']}');
  final bagO = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
    'buyer_id': buyerId,
    'order_id': x1?['id'],
    'bag_checkout': true,
    'shipping_method': 'entrega em mão',
    'bag_lines': [
      {'order_id': x1?['id']},
      {'order_id': x2?['id']},
    ],
  });
  rec('bag_oversell_quote', {'http': bagO['http'], 'body': bagO['body']});

  // payout buyer body
  rec('payout_buyer', snip((await req('POST', '$url/functions/v1/create-connect-account', BH, {}))['body'], 500));
  rec('payout_buyer_amt', snip((await req('POST', '$url/functions/v1/create-connect-account', BH, {
    'amount': 1,
    'idempotency_key': 'satb-$stamp-xxxx',
  }))['body'], 400));

  // storage list names
  for (final b in ['chat_media', 'fleaber_private']) {
    final r = await req('POST', '$url/storage/v1/object/list/$b', AN, {'prefix': '', 'limit': 8});
    rec('stor_anon_$b', {
      'http': r['http'],
      'n': nRows(r['body']),
      'names': (r['body'] is List)
          ? (r['body'] as List).take(8).map((e) => e is Map ? e['name'] : e).toList()
          : snip(r['body'], 200),
    });
    final rb = await req('POST', '$url/storage/v1/object/list/$b', BH, {
      'prefix': 'order_proofs/',
      'limit': 8,
    });
    rec('stor_buyer_${b}_proofs', {
      'http': rb['http'],
      'n': nRows(rb['body']),
      'names': (rb['body'] is List)
          ? (rb['body'] as List).take(8).map((e) => e is Map ? e['name'] : e).toList()
          : snip(rb['body'], 200),
    });
  }

  // chat messages foreign
  rec('buyer_msgs', {
    'n': nRows((await req('GET', '$url/rest/v1/chat_messages?select=id,chat_id,sender_id,content&limit=5', BH))['body']),
    'sample': snip(row((await req('GET', '$url/rest/v1/chat_messages?select=id,sender_id,content&limit=2', BH))['body']), 300),
  });
  rec('anon_msgs', {
    'http': (await req('GET', '$url/rest/v1/chat_messages?select=id,content&limit=5', AN))['http'],
    'n': nRows((await req('GET', '$url/rest/v1/chat_messages?select=id,content&limit=5', AN))['body']),
  });

  // reviews public
  rec('anon_reviews', {
    'n': nRows((await req('GET', '$url/rest/v1/reviews?select=id,stars,comment,buyer_id,target_id&limit=5', AN))['body']),
    'sample': snip(row((await req('GET', '$url/rest/v1/reviews?select=id,stars,comment,buyer_id&limit=2', AN))['body']), 300),
  });

  // orders anon columns
  rec('anon_orders_cols', {
    'n': nRows((await req('GET', '$url/rest/v1/orders?select=id,status,price_total,buyer_id,seller_id&limit=5', AN))['body']),
    'sample': snip(row((await req('GET', '$url/rest/v1/orders?select=id,status,price_total,buyer_id&limit=2', AN))['body']), 300),
  });

  // wallet grant: release on REAL concluido MB WAY as seller (not buyer)
  final pW = await mkP(8, 2);
  final oW = row((await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pW['id'],
    'quantity': 1,
    'price_total': 8,
    'status': 'reserva_pendente',
    'payment_method': 'MB WAY',
    'shipping_method': 'entrega em mão',
  }))['body']);
  if (oW?['id'] != null) {
    oids.add('${oW!['id']}');
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oW['id']}', SH, {'status': 'pago'});
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oW['id']}', SH, {'status': 'enviado'});
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oW['id']}', BH, {'status': 'concluido'});
    final st = row((await req('GET', '$url/rest/v1/orders?id=eq.${oW['id']}&select=status,wallet_release_processed_at,amount_paid_cents', SVC))['body']);
    rec('mbway_concluido', st);
    final relS = await req('POST', '$url/rest/v1/rpc/batata_release_seller_wallet_for_order', SH, {'p_order_id': oW['id']});
    final relB = await req('POST', '$url/rest/v1/rpc/batata_release_seller_wallet_for_order', BH, {'p_order_id': oW['id']});
    rec('release_seller_on_own_sale', {'http': relS['http'], 'body': relS['body']});
    rec('release_buyer_on_mbway', {'http': relB['http'], 'body': relB['body']});
    final st2 = row((await req('GET', '$url/rest/v1/orders?id=eq.${oW['id']}&select=wallet_release_processed_at', SVC))['body']);
    rec('release_flag_after', st2);
    final wS = await req('GET', '$url/rest/v1/wallets?id=eq.$sellerId&select=id,balance', SVC);
    rec('seller_wallet_after_release', snip(wS['body'], 300));
  }

  // pix/empty pago confirmation
  final pPix = await mkP(6, 2);
  final oPix = row((await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pPix['id'],
    'quantity': 1,
    'price_total': 6,
    'payment_method': 'pix',
    'status': 'reserva_pendente',
    'shipping_method': 'entrega em mão',
  }))['body']);
  if (oPix?['id'] != null) {
    oids.add('${oPix!['id']}');
    rec('pix_insert_pm', oPix?['payment_method']);
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oPix['id']}', SH, {'status': 'pago'});
    rec('pix_after_seller_pago', row((await req('GET', '$url/rest/v1/orders?id=eq.${oPix['id']}&select=status,stock_units_applied', SVC))['body']));
  }

  // RPC list via PostgREST error
  rec('rpc_list_hint', (await req('POST', '$url/rest/v1/rpc/batata_no_such', BH, {}))['body']);

  for (final oid in oids) {
    await req('DELETE', '$url/rest/v1/orders?id=eq.$oid', SVC);
  }
  for (final pid in pids) {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  }

  File('tool/reports/SAT_INDEP_PASSB_20260827.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('wrote tool/reports/SAT_INDEP_PASSB_20260827.json');
}
