// ignore_for_file: avoid_print
/// D1858 + E1859 — dart run tool/sec_d1858_e1859_hostile.dart
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
      ? await http.post(
          Uri.parse(u),
          headers: h,
          body: body == null ? null : jsonEncode(body),
        )
      : method == 'PATCH'
          ? await http.patch(
              Uri.parse(u),
              headers: h,
              body: body == null ? null : jsonEncode(body),
            )
          : method == 'DELETE'
              ? await http.delete(Uri.parse(u), headers: h)
              : await http.get(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p};
}

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  if (body is Map) {
    final s = '${body['id'] ?? body['order_id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  return null;
}

Map<String, dynamic>? firstMap(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
}

Future<void> main() async {
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
  final crashSecret = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final E2E = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    if (crashSecret.length >= 16) 'x-fleaber-e2e-secret': crashSecret,
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object? d) {
    results.add({'id': id, 'ok': ok, 'detail': d});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $d');
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;

  // ---- D1: paid + null shipping → cannot set mão ----
  final paid = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'probe': 'setup_paid_order',
      'initial_qty': 2,
    },
  );
  final oid = idOf(paid['body']);
  add('fixture_paid', oid != null, {'id': oid, 'http': paid['http']});

  if (oid != null) {
    await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$oid',
      SVC,
      {'shipping_method': null},
    );
    final ship = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$oid',
      BH,
      {'shipping_method': 'entrega em mão'},
    );
    final row = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$oid&select=shipping_method,status',
      SVC,
    ))['body']);
    final frozen = (ship['http'] as int) >= 400 ||
        (row?['shipping_method'] == null ||
            '${row?['shipping_method']}'.trim().isEmpty);
    add('P1_ship_frozen_after_pago', frozen, {
      'http': ship['http'],
      'ship': row?['shipping_method'],
      'body': ship['body'],
    });

    final early = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$oid',
      BH,
      {'status': 'concluido'},
    );
    final st = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$oid&select=status',
      SVC,
    ))['body']);
    add(
      'P1_concluido_still_requires_ship_or_hand',
      '${st?['status']}' == 'pago' || (early['http'] as int) >= 400,
      {'http': early['http'], 'status': st?['status']},
    );
  }

  // ---- E6: hold listed → unlist → bag blocked ----
  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'E6 bag $stamp',
    'price': 11.0,
    'quantity': 2,
    'ref_code': 'E6B-$stamp',
    'list_on_marketplace': true,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(prod['body']);
  final ord = await req('POST', '$url/rest/v1/orders', BH, {
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'quantity': 1,
    'price_total': 11.0,
    'shipping_method': 'mao',
    'payment_method': 'Pagamento na app',
  });
  final bagOid = idOf(ord['body']);
  add('fixture_bag_order', bagOid != null, {'id': bagOid});

  await req(
    'PATCH',
    '$url/rest/v1/products?id=eq.$pid',
    SVC,
    {'list_on_marketplace': false},
  );

  final single = await req(
    'POST',
    '$url/functions/v1/create-payment-intent',
    BH,
    {
      'order_id': bagOid,
      'buyer_id': buyerId,
      'shipping_method': 'mao',
    },
  );
  add(
    'P1_single_unlist_blocked',
    (single['http'] as int) >= 400,
    {'http': single['http'], 'body': single['body']},
  );

  final bag = await req(
    'POST',
    '$url/functions/v1/create-payment-intent',
    BH,
    {
      'bag_checkout': true,
      'buyer_id': buyerId,
      'shipping_method': 'mao',
      'bag_lines': [
        {'order_id': bagOid},
      ],
    },
  );
  add(
    'P1_bag_unlist_blocked',
    (bag['http'] as int) >= 400,
    {'http': bag['http'], 'body': bag['body']},
  );

  // Hand path still: listed product + mão after pay via setup with shipping
  final paidHand = await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'probe': 'setup_paid_order',
      'initial_qty': 2,
      'shipping_method': 'mao',
    },
  );
  final hOid = idOf(paidHand['body']);
  if (hOid != null) {
    await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$hOid',
      SVC,
      {'shipping_method': 'mao'},
    );
    final conf = await req(
      'PATCH',
      '$url/rest/v1/orders?id=eq.$hOid',
      BH,
      {'status': 'concluido'},
    );
    final hs = firstMap((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$hOid&select=status',
      SVC,
    ))['body']);
    add('anti_reg_hand_concluido_ok', '${hs?['status']}' == 'concluido', {
      'http': conf['http'],
      'status': hs?['status'],
    });
  } else {
    add('anti_reg_hand_concluido_ok', false, paidHand);
  }

  if (bagOid != null) {
    await req('DELETE', '$url/rest/v1/orders?id=eq.$bagOid', SVC);
  }
  if (pid != null) {
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  }

  final failed = results.where((r) => r['ok'] != true).length;
  final out = 'tool/reports/sec_d1858_e1859_hostile_$stamp.json';
  await File(out).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'stamp': stamp,
      'pass': results.length - failed,
      'fail': failed,
      'results': results,
    }),
  );
  stdout.writeln('Wrote $out (${results.length - failed}/${results.length})');
  exit(failed == 0 ? 0 : 1);
}
