// ignore_for_file: avoid_print
/// RTBB-B-2012: unpaid pending hold DoS + MB WAY×Stripe compose.
/// dart run tool/sec_rtbb_b2012_hold_compose_hostile.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
]) async {
  final r = method == 'POST'
      ? await http.post(Uri.parse(u), headers: h, body: jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(u), headers: h, body: jsonEncode(body))
          : method == 'DELETE'
              ? await http.delete(Uri.parse(u), headers: h)
              : await http.get(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

String clip(Object? v, [int n = 280]) {
  final s = '$v';
  return s.length <= n ? s : s.substring(0, n);
}

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
}

bool textHas(dynamic body, String needle) {
  return '$body'.toLowerCase().contains(needle.toLowerCase());
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT staging');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
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
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final cleanup = <Future Function()>[];
  final stamp = DateTime.now().millisecondsSinceEpoch;

  // ---- HOLD: pending não trava; 2.º accept trava ----
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'B2012 hold $stamp',
    'price': 8.0,
    'quantity': 1,
    'ref_code': 'B2012H-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(prod['body']);
  add('fixture_product', pid != null, {'id': pid});
  if (pid == null) exit(1);
  cleanup.add(() async {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  });

  final p1 = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 8.0,
    'payment_method': 'MB WAY',
  });
  final oid1 = idOf(p1['body']);
  add('HOLD_first_pending_ok', oid1 != null, {'id': oid1, 'http': p1['http']});

  final avail = await req(
    'POST',
    '$url/rest/v1/rpc/batata_product_checkout_available',
    SVC,
    {
      'p_product_id': pid,
      'p_exclude_order_id': oid1,
      'p_need_qty': 1,
    },
  );
  final availOk = avail['body'] is Map &&
      (avail['body'] as Map)['ok'] == true &&
      ((avail['body'] as Map)['available'] == 1 ||
          (avail['body'] as Map)['held'] == 0);
  add('HOLD_pending_does_not_consume_stock', availOk, {
    'body': clip(avail['body']),
  });

  final p2 = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 8.0,
  });
  final oid2 = idOf(p2['body']);
  add(
    'HOLD_second_pending_still_ok',
    oid2 != null && (p2['http'] as int) < 300,
    {'id': oid2, 'http': p2['http'], 'body': clip(p2['body'])},
  );

  if (oid1 != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid1', SH, {
      'status': 'reservado',
    });
  }
  if (oid2 != null) {
    final acc2 = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid2', SH, {
      'status': 'reservado',
    });
    add(
      'HOLD_second_accept_blocked',
      (acc2['http'] as int) >= 400 ||
          textHas(acc2['body'], 'order_hold_exceeds_stock'),
      {'http': acc2['http'], 'body': clip(acc2['body'])},
    );
  }

  // ---- COMPOSE: MB WAY order não abre Stripe Session ----
  final prodM = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'B2012 mbway $stamp',
    'price': 12.5,
    'quantity': 1,
    'ref_code': 'B2012M-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pidM = idOf(prodM['body']);
  add('fixture_mbway_product', pidM != null, {'id': pidM});
  if (pidM != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pidM', SVC);
      await req('DELETE', '$url/rest/v1/products?id=eq.$pidM', SVC);
    });
    final om = await req('POST', '$url/rest/v1/orders', BH, {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'product_id': pidM,
      'status': 'reserva_pendente',
      'quantity': 1,
      'price_total': 12.5,
      'payment_method': 'MB WAY',
    });
    final oidM = idOf(om['body']);
    add('COMPOSE_mbway_order', oidM != null, {'id': oidM});
    if (oidM != null) {
      final cpi = await req(
        'POST',
        '$url/functions/v1/create-payment-intent',
        BH,
        {
          'buyer_id': buyerId,
          'order_id': oidM,
          'shipping_method': 'carrier',
        },
      );
      final blocked = (cpi['http'] as int) >= 400 &&
          (textHas(cpi['body'], 'off-platform') ||
              textHas(cpi['body'], 'off_platform') ||
              textHas(cpi['text'], 'off-platform'));
      add('COMPOSE_stripe_blocked_on_mbway', blocked, {
        'http': cpi['http'],
        'body': clip(cpi['body'] ?? cpi['text']),
      });

      // Seller ainda pode marcar pago off-platform (happy path MB WAY).
      await req('PATCH', '$url/rest/v1/orders?id=eq.$oidM', SH, {
        'status': 'reservado',
      });
      final pago = await req('PATCH', '$url/rest/v1/orders?id=eq.$oidM', SH, {
        'status': 'pago',
      });
      final after = await req(
        'GET',
        '$url/rest/v1/orders?select=id,status,stripe_checkout_session_id&id=eq.$oidM',
        SVC,
      );
      final st = '${(after['body'] is List && (after['body'] as List).isNotEmpty) ? (after['body'] as List).first['status'] : ''}';
      final sess = '${(after['body'] is List && (after['body'] as List).isNotEmpty) ? (after['body'] as List).first['stripe_checkout_session_id'] : ''}';
      add(
        'HAPPY_mbway_seller_pago_no_stripe_session',
        st == 'pago' && (sess.isEmpty || sess == 'null') && (pago['http'] as int) < 300,
        {'status': st, 'session': sess, 'pago_http': pago['http']},
      );
    }
  }

  // Platform order (sem payment_method off) → Session OK
  final prodP = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'B2012 plat $stamp',
    'price': 5.0,
    'quantity': 1,
    'ref_code': 'B2012P-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pidP = idOf(prodP['body']);
  if (pidP != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pidP', SVC);
      await req('DELETE', '$url/rest/v1/products?id=eq.$pidP', SVC);
    });
    final op = await req('POST', '$url/rest/v1/orders', BH, {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'product_id': pidP,
      'status': 'reserva_pendente',
      'quantity': 1,
      'price_total': 5.0,
    });
    final oidP = idOf(op['body']);
    if (oidP != null) {
      await req('PATCH', '$url/rest/v1/orders?id=eq.$oidP', SH, {
        'status': 'reservado',
      });
      final cpi = await req(
        'POST',
        '$url/functions/v1/create-payment-intent',
        BH,
        {
          'buyer_id': buyerId,
          'order_id': oidP,
          'shipping_method': 'hand',
        },
      );
      final urlOk = cpi['body'] is Map &&
          '${(cpi['body'] as Map)['checkoutUrl'] ?? ''}'.contains('checkout.stripe');
      add('HAPPY_platform_checkout_ok', (cpi['http'] as int) == 200 && urlOk, {
        'http': cpi['http'],
      });
    }
  }

  for (final f in cleanup.reversed) {
    try {
      await f();
    } catch (_) {}
  }

  final pass = results.where((r) => r['ok'] == true).length;
  final fail = results.where((r) => r['ok'] != true).length;
  final outPath =
      'tool/reports/sec_rtbb_b2012_hold_compose_hostile_$stamp.json';
  await File(outPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'stamp': stamp,
      'pass': pass,
      'fail': fail,
      'results': results,
    }),
  );
  stdout.writeln('\n$pass/${results.length} PASS → $outPath');
  exit(fail == 0 ? 0 : 1);
}
