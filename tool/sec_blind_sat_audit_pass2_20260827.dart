// ignore_for_file: avoid_print
/// Passagem 2 — composição / variantes (staging).
/// dart run tool/sec_blind_sat_audit_pass2_20260827.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

typedef Json = Map<String, dynamic>;

Future<Json> req(
  String method,
  String url,
  Map<String, String> headers, {
  Object? body,
}) async {
  final uri = Uri.parse(url);
  late http.Response r;
  final encoded = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      r = await http.get(uri, headers: headers);
      break;
    case 'POST':
      r = await http.post(uri, headers: headers, body: encoded);
      break;
    case 'PATCH':
      r = await http.patch(uri, headers: headers, body: encoded);
      break;
    case 'DELETE':
      r = await http.delete(uri, headers: headers);
      break;
    default:
      throw ArgumentError(method);
  }
  dynamic parsed;
  try {
    parsed = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    parsed = r.body;
  }
  return {'http': r.statusCode, 'body': parsed, 'raw': r.body};
}

Json? firstRow(Object? body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
}

void main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
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
  Map<String, String> h(String t) => {
        'apikey': anon,
        'Authorization': 'Bearer $t',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  final BH = h(buyerTok);
  final SH = h(sellerTok);
  final ANON = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final out = <String, dynamic>{};
  void log(String k, Object v) {
    out[k] = v;
    stdout.writeln('$k: ${v is String && v.length > 800 ? v.substring(0, 800) : v}');
  }

  // Restore shared buyer phone_verified_at
  final restore = await req(
    'PATCH',
    '$url/rest/v1/profiles?id=eq.$buyerId',
    BH,
    body: {'phone_verified_at': null},
  );
  log('restore_phone_verified', {
    'http': restore['http'],
    'now': firstRow(restore['body'])?['phone_verified_at'],
  });

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final productIds = <String>[];
  final orderIds = <String>[];

  Future<String> prod({num price = 47, int qty = 8}) async {
    final row = await sb.insert('products', {
      'seller_id': sellerId,
      'title': 'SAT-P2 $stamp ${productIds.length}',
      'price': price,
      'quantity': qty,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    productIds.add(row['id'].toString());
    return row['id'].toString();
  }

  Future<Json> insOrder(Json row, [Map<String, String>? hdr]) async {
    final r = await req('POST', '$url/rest/v1/orders', hdr ?? BH, body: row);
    final fr = firstRow(r['body']);
    if (fr?['id'] != null) orderIds.add(fr!['id'].toString());
    return r;
  }

  Future<Json> checkout(Json body) => req(
        'POST',
        '$url/functions/v1/create-payment-intent',
        {
          'apikey': anon,
          'Authorization': 'Bearer $buyerTok',
          'Content-Type': 'application/json',
        },
        body: body,
      );

  try {
    // P0 variant: contract 100 cents (>= Stripe 50) vs catalog 47€
    final pA = await prod(price: 47, qty: 5);
    final cheap = await insOrder({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pA,
      'quantity': 1,
      'price_total': 1.00,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
      'contract_unit_cents': 100,
      'contract_qty': 1,
    });
    final cheapRow = firstRow(cheap['body']);
    log('cheap_100c_insert', {
      'http': cheap['http'],
      'cuc': cheapRow?['contract_unit_cents'],
      'pt': cheapRow?['price_total'],
    });
    if (cheapRow != null) {
      final ck = await checkout({
        'order_id': cheapRow['id'],
        'buyer_id': buyerId,
        'shipping_method': 'entrega em mão',
      });
      log('cheap_100c_checkout', {
        'http': ck['http'],
        'body': ck['body'],
      });
    }

    // Proposta 1.00€ (above min)
    final prop = await insOrder({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pA,
      'quantity': 1,
      'price_total': 1.00,
      'status': 'reserva_pendente',
      'payment_method': 'proposta aceite',
      'shipping_method': 'entrega em mão',
    });
    final propRow = firstRow(prop['body']);
    log('proposta_1eur_insert', {
      'http': prop['http'],
      'cuc': propRow?['contract_unit_cents'],
      'pt': propRow?['price_total'],
    });
    if (propRow != null) {
      final ck = await checkout({
        'order_id': propRow['id'],
        'buyer_id': buyerId,
        'shipping_method': 'entrega em mão',
      });
      log('proposta_1eur_checkout', {'http': ck['http'], 'body': ck['body']});
    }

    // Stock theft: quantity=5 contract_qty=1 → charge 1, stock trigger uses quantity=5
    final pB = await prod(price: 20, qty: 5);
    final steal = await insOrder({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pB,
      'quantity': 5,
      'price_total': 20,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
      'contract_unit_cents': 2000,
      'contract_qty': 1,
    });
    final stealRow = firstRow(steal['body']);
    log('stock_theft_insert', {
      'http': steal['http'],
      'qty': stealRow?['quantity'],
      'cq': stealRow?['contract_qty'],
      'cuc': stealRow?['contract_unit_cents'],
    });
    if (stealRow != null) {
      final ck = await checkout({
        'order_id': stealRow['id'],
        'buyer_id': buyerId,
        'shipping_method': 'entrega em mão',
      });
      log('stock_theft_checkout', {'http': ck['http'], 'body': ck['body']});
    }

    // stock_units_applied skip: insert flag then observe column
    final pC = await prod(price: 15, qty: 3);
    final skip = await insOrder({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pC,
      'quantity': 1,
      'price_total': 15,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
      'stock_units_applied': 1,
      'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
    });
    final skipRow = firstRow(skip['body']);
    log('flags_insert', {
      'http': skip['http'],
      'stock_units_applied': skipRow?['stock_units_applied'],
      'wallet_release_processed_at': skipRow?['wallet_release_processed_at'],
    });
    if (skipRow != null) {
      final ck = await checkout({
        'order_id': skipRow['id'],
        'buyer_id': buyerId,
        'shipping_method': 'entrega em mão',
      });
      log('flags_checkout', {
        'http': ck['http'],
        'amount': (ck['body'] is Map) ? (ck['body'] as Map)['amount_total'] : null,
        'err': (ck['body'] is Map) ? (ck['body'] as Map)['error'] : null,
      });
    }

    // Seller unpaid → concluido → review already existed on other; new order
    final pD = await prod(price: 12, qty: 2);
    final st = await insOrder({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pD,
      'quantity': 1,
      'price_total': 12,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    final stRow = firstRow(st['body']);
    if (stRow != null) {
      final up = await req(
        'PATCH',
        '$url/rest/v1/orders?id=eq.${stRow['id']}',
        SH,
        body: {'status': 'concluido'},
      );
      log('seller_unpaid_concluido', {
        'http': up['http'],
        'status': firstRow(up['body'])?['status'],
      });
      final rev = await req('POST', '$url/rest/v1/reviews', BH, body: {
        'order_id': stRow['id'],
        'stars': 5,
        'comment': 'sat-p2',
        'author_role': 'comprador',
      });
      log('review_after_fake_concluido', {
        'http': rev['http'],
        'body': rev['body'],
      });
    }

    // Empty / whitespace / "cash" payment_method seller pago
    for (final pm in ['', ' ', 'cash', 'other', 'paypal']) {
      final pE = await prod(price: 9, qty: 2);
      final o = await insOrder({
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pE,
        'quantity': 1,
        'price_total': 9,
        'status': 'reserva_pendente',
        'payment_method': pm,
        'shipping_method': 'entrega em mão',
      });
      final row = firstRow(o['body']);
      if (row == null) {
        log('pm_$pm insert', {'http': o['http'], 'body': o['body']});
        continue;
      }
      final before = await sb.select('products', filter: 'id=eq.$pE', limit: 1);
      final up = await req(
        'PATCH',
        '$url/rest/v1/orders?id=eq.${row['id']}',
        SH,
        body: {'status': 'pago'},
      );
      final after = await sb.select('products', filter: 'id=eq.$pE', limit: 1);
      log('pm_${pm.isEmpty ? "empty" : pm}_pago', {
        'insert_pm': row['payment_method'],
        'http': up['http'],
        'status': firstRow(up['body'])?['status'],
        'stock_before': before.first['quantity'],
        'stock_after': after.first['quantity'],
      });
    }

    // Observation: auto_feedback candidates (service_role observe only)
    final cand = await req(
      'GET',
      '$url/rest/v1/orders?status=eq.concluido&wallet_release_processed_at=is.null&amount_paid_cents=gt.0&select=id,amount_paid_cents,buyer_id,seller_id,completed_at&limit=20',
      SVC,
    );
    log('observe_unreleased_paid_concluido', {
      'http': cand['http'],
      'n': cand['body'] is List ? (cand['body'] as List).length : 0,
      'ids': cand['body'] is List
          ? (cand['body'] as List)
              .map((x) => (x as Map)['id'])
              .toList()
          : [],
    });

    // Anon auto_feedback default already tested. Do NOT call p_now=2099.
    // Confirm GRANT: anon execute with empty body
    final af = await req(
      'POST',
      '$url/rest/v1/rpc/batata_generate_auto_feedback',
      ANON,
      body: {},
    );
    log('anon_auto_feedback_now', {'http': af['http'], 'body': af['body']});

    // lab clear GRANT — already ran; confirm still executable (deleted 0 last time)
    // Do NOT re-run if it deletes open orders. Probe via OPTIONS/empty?
    // Calling again is destructive if any pending exists. Skip second call.
    log('lab_clear_skipped_rerun', 'already proven EXECUTE as anon; would delete open holds');

    // Storage list samples
    for (final b in ['chat_media', 'fleaber_private']) {
      final list = await req(
        'POST',
        '$url/storage/v1/object/list/$b',
        {
          'apikey': anon,
          'Authorization': 'Bearer $buyerTok',
          'Content-Type': 'application/json',
        },
        body: {'prefix': '', 'limit': 10},
      );
      log('storage_list_$b', list['body']);
    }

    // lives as seller
    final livesB = await req(
      'GET',
      '$url/rest/v1/lives?select=id,mux_stream_key,stream_key,status&limit=3',
      BH,
    );
    final livesS = await req(
      'GET',
      '$url/rest/v1/lives?select=id,mux_stream_key,stream_key,status&limit=3',
      SH,
    );
    log('lives_buyer', {'http': livesB['http'], 'body': livesB['body']});
    log('lives_seller', {'http': livesS['http'], 'body': livesS['body']});

    // draw raffle as buyer
    final draw = await req(
      'POST',
      '$url/rest/v1/rpc/batata_draw_live_raffle_winners',
      BH,
      body: {'p_raffle_id': '00000000-0000-0000-0000-000000000001'},
    );
    log('draw_raffle_buyer', {'http': draw['http'], 'body': draw['body']});

    // reviews UPDATE stars
    final pF = await prod(price: 11, qty: 1);
    final oF = await insOrder({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pF,
      'quantity': 1,
      'price_total': 11,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    });
    final ofr = firstRow(oF['body']);
    if (ofr != null) {
      await req('PATCH', '$url/rest/v1/orders?id=eq.${ofr['id']}', SH, body: {'status': 'concluido'});
      final r1 = await req('POST', '$url/rest/v1/reviews', BH, body: {
        'order_id': ofr['id'],
        'stars': 1,
        'comment': 'low',
        'author_role': 'comprador',
      });
      final rr = firstRow(r1['body']);
      log('review_1star', {'http': r1['http'], 'id': rr?['id'], 'stars': rr?['stars']});
      if (rr != null) {
        final r2 = await req(
          'PATCH',
          '$url/rest/v1/reviews?id=eq.${rr['id']}',
          BH,
          body: {'stars': 5, 'is_automatic': true, 'comment': 'flipped'},
        );
        log('review_update_stars', {
          'http': r2['http'],
          'row': firstRow(r2['body']),
        });
      }
    }

    // Negative price_total checkout
    final pG = await prod(price: 30, qty: 2);
    final neg = await insOrder({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pG,
      'quantity': 1,
      'price_total': -5,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    final negRow = firstRow(neg['body']);
    log('neg_price_insert', {
      'pt': negRow?['price_total'],
      'cuc': negRow?['contract_unit_cents'],
    });
    if (negRow != null) {
      final ck = await checkout({
        'order_id': negRow['id'],
        'buyer_id': buyerId,
        'shipping_method': 'entrega em mão',
      });
      log('neg_price_checkout', {'http': ck['http'], 'body': ck['body']});
    }
  } finally {
    for (final oid in orderIds) {
      try {
        await http.delete(Uri.parse('$url/rest/v1/reviews?order_id=eq.$oid'), headers: SVC);
      } catch (_) {}
      await http.delete(Uri.parse('$url/rest/v1/orders?id=eq.$oid'), headers: SVC);
    }
    for (final pid in productIds) {
      try {
        await http.delete(Uri.parse('$url/rest/v1/chats?product_id=eq.$pid'), headers: SVC);
      } catch (_) {}
      await http.delete(Uri.parse('$url/rest/v1/orders?product_id=eq.$pid'), headers: SVC);
      await http.delete(Uri.parse('$url/rest/v1/products?id=eq.$pid'), headers: SVC);
    }
  }

  File('tool/reports/SAT_BLIND_PASS2_20260827.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('WROTE tool/reports/SAT_BLIND_PASS2_20260827.json');
}
