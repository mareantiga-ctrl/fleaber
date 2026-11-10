// ignore_for_file: avoid_print
/// RTB-B-1755 offer one-shot (MULTI-BIND + REUSE).
/// dart run tool/sec_rtb_b_1755_offer_oneshot_hostile.dart
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

String clip(Object? v, [int n = 260]) {
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

Map<String, dynamic>? rowOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  return null;
}

int? centsOf(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
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
  const listPrice = 20.0;
  const offerAmount = 2.0;
  final listCents = (listPrice * 100).round();
  final offerCents = (offerAmount * 100).round();

  final prod = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'Offer oneshot $stamp',
    'price': listPrice,
    'quantity': 3,
    'ref_code': 'OFFER1-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid = idOf(prod['body']);
  add('fixture_product', pid != null, {'id': pid});
  if (pid == null) {
    exit(1);
  }
  cleanup.add(() async {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid', SVC);
    await req('DELETE', '$url/rest/v1/product_offers?product_id=eq.$pid', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  });

  final offerIns = await req('POST', '$url/rest/v1/product_offers', BH, {
    'product_id': pid,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': offerAmount,
    'offered_by': 'buyer',
    'status': 'pending',
    'expires_at': DateTime.now()
        .toUtc()
        .add(const Duration(hours: 48))
        .toIso8601String(),
  });
  final offerId = idOf(offerIns['body']);
  add('fixture_offer', offerId != null, {'id': offerId});
  if (offerId == null) exit(1);

  await req('PATCH', '$url/rest/v1/product_offers?id=eq.$offerId', SH, {
    'status': 'accepted',
    'responded_at': DateTime.now().toUtc().toIso8601String(),
  });
  final offerChk = await req(
    'GET',
    '$url/rest/v1/product_offers?id=eq.$offerId&select=status',
    SVC,
  );
  add(
    'fixture_offer_accepted',
    '${rowOf(offerChk['body'])?['status']}'.toLowerCase() == 'accepted',
    rowOf(offerChk['body']),
  );

  // ---- MULTI-BIND: 1ª order herda oferta; 2ª fica catálogo ----
  Future<Map<String, dynamic>> buyerOrder(num priceTotal) => req(
        'POST',
        '$url/rest/v1/orders',
        BH,
        {
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'product_id': pid,
          'quantity': 1,
          'price_total': priceTotal,
          'status': 'reserva_pendente',
          'payment_method': 'Pagamento na app',
          'shipping_method': 'hand',
        },
      );

  final o1 = await buyerOrder(listPrice);
  final r1 = rowOf(o1['body']);
  final oid1 = idOf(o1['body']);
  if (oid1 != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$oid1', SVC);
    });
  }
  add(
    'MULTI_first_order_binds_offer_price',
    oid1 != null &&
        centsOf(r1?['contract_unit_cents']) == offerCents &&
        '${r1?['product_offer_id']}' == offerId,
    {
      'http': o1['http'],
      'contract_unit_cents': r1?['contract_unit_cents'],
      'product_offer_id': r1?['product_offer_id'],
    },
  );

  final o2 = await buyerOrder(listPrice);
  final r2 = rowOf(o2['body']);
  final oid2 = idOf(o2['body']);
  if (oid2 != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$oid2', SVC);
    });
  }
  add(
    'MULTI_second_order_catalog_price_no_offer',
    oid2 != null &&
        centsOf(r2?['contract_unit_cents']) == listCents &&
        (r2?['product_offer_id'] == null || '${r2?['product_offer_id']}' == 'null'),
    {
      'http': o2['http'],
      'contract_unit_cents': r2?['contract_unit_cents'],
      'product_offer_id': r2?['product_offer_id'],
      'body': clip(o2['text']),
    },
  );

  // Checkout quote: 1ª ≈ offer+taxas; 2ª ≈ list+taxas (server_amount)
  Future<Map<String, dynamic>> cpi(String orderId) async {
    final r = await req(
      'POST',
      '$url/functions/v1/create-payment-intent',
      {
        'apikey': anon,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'application/json',
      },
      {
        'buyer_id': buyerId,
        'order_id': orderId,
        'shipping_method': 'hand',
        'amount': 2000,
      },
    );
    Map<String, dynamic> b = {};
    try {
      b = Map<String, dynamic>.from(jsonDecode(r['text'] as String) as Map);
    } catch (_) {}
    return {'http': r['http'], 'body': b, 'text': r['text']};
  }

  if (oid1 != null && oid2 != null) {
    final c1 = await cpi(oid1);
    final c2 = await cpi(oid2);
    final a1 = centsOf(c1['body']?['server_amount_cents'] ??
        c1['body']?['amount']);
    final a2 = centsOf(c2['body']?['server_amount_cents'] ??
        c2['body']?['amount']);
    // hand: items only + protection; offer line 200 vs list 2000 → a1 < a2
    add(
      'MULTI_checkout_second_not_offer_price',
      (c1['http'] as int) < 300 &&
          (c2['http'] as int) < 300 &&
          a1 != null &&
          a2 != null &&
          a1 < a2 &&
          a1 < 1000 &&
          a2 > 1500,
      {
        'c1_http': c1['http'],
        'c2_http': c2['http'],
        'amount1': a1,
        'amount2': a2,
        'c1': clip(c1['text']),
        'c2': clip(c2['text']),
      },
    );
  }

  // ---- REUSE: seller 2ª INSERT mesmo offer_id → bloqueado ----
  // Usar produto fresco + oferta nova (a anterior já consumida por o1)
  final prod2 = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'Offer reuse $stamp',
    'price': 6.5,
    'quantity': 2,
    'ref_code': 'OFFER2-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final pid2 = idOf(prod2['body']);
  cleanup.add(() async {
    if (pid2 == null) return;
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid2', SVC);
    await req('DELETE', '$url/rest/v1/product_offers?product_id=eq.$pid2', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid2', SVC);
  });

  final offer2Ins = await req('POST', '$url/rest/v1/product_offers', BH, {
    'product_id': pid2,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 3.5,
    'offered_by': 'buyer',
    'status': 'pending',
    'expires_at': DateTime.now()
        .toUtc()
        .add(const Duration(hours: 48))
        .toIso8601String(),
  });
  final offer2 = idOf(offer2Ins['body']);
  await req('PATCH', '$url/rest/v1/product_offers?id=eq.$offer2', SH, {
    'status': 'accepted',
    'responded_at': DateTime.now().toUtc().toIso8601String(),
  });

  final s1 = await req('POST', '$url/rest/v1/orders', SH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid2,
    'product_offer_id': offer2,
    'price_total': 3.5,
    'quantity': 1,
    'payment_method': 'MB WAY',
    'status': 'reservado',
    'is_reservation': true,
  });
  final sr1 = rowOf(s1['body']);
  final sid1 = idOf(s1['body']);
  if (sid1 != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$sid1', SVC);
    });
  }
  add(
    'REUSE_first_seller_insert_ok',
    sid1 != null && centsOf(sr1?['contract_unit_cents']) == 350,
    {
      'http': s1['http'],
      'contract': sr1?['contract_unit_cents'],
      'body': clip(s1['text']),
    },
  );

  final s2 = await req('POST', '$url/rest/v1/orders', SH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid2,
    'product_offer_id': offer2,
    'price_total': 3.5,
    'quantity': 1,
    'payment_method': 'MB WAY',
    'status': 'reservado',
    'is_reservation': true,
  });
  final sid2 = idOf(s2['body']);
  if (sid2 != null) {
    cleanup.add(() async {
      await req('DELETE', '$url/rest/v1/orders?id=eq.$sid2', SVC);
    });
  }
  add(
    'REUSE_second_seller_insert_blocked',
    sid2 == null && (s2['http'] as int) >= 400,
    {
      'http': s2['http'],
      'order_id': sid2,
      'body': clip(s2['text']),
    },
  );

  // Cancel 1ª → oferta pode ligar de novo (reclamação após cancelamento)
  if (sid1 != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.$sid1', SVC, {
      'status': 'cancelado',
    });
    final s3 = await req('POST', '$url/rest/v1/orders', SH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid2,
      'product_offer_id': offer2,
      'price_total': 3.5,
      'quantity': 1,
      'payment_method': 'MB WAY',
      'status': 'reservado',
      'is_reservation': true,
    });
    final sid3 = idOf(s3['body']);
    if (sid3 != null) {
      cleanup.add(() async {
        await req('DELETE', '$url/rest/v1/orders?id=eq.$sid3', SVC);
      });
    }
    add(
      'HAPPY_offer_reusable_after_cancel',
      sid3 != null && centsOf(rowOf(s3['body'])?['contract_unit_cents']) == 350,
      {
        'http': s3['http'],
        'contract': rowOf(s3['body'])?['contract_unit_cents'],
        'body': clip(s3['text']),
      },
    );
  }

  // Regressão ghost: seller sem offer → still denied
  final ghost = await req('POST', '$url/rest/v1/orders', SH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'status': 'pendente',
    'price_total': 7.5,
    'quantity': 1,
    'payment_method': 'mbway',
  });
  add(
    'REG_ghost_sale_still_blocked',
    idOf(ghost['body']) == null && (ghost['http'] as int) >= 400,
    {'http': ghost['http'], 'body': clip(ghost['text'])},
  );

  for (final c in cleanup.reversed) {
    try {
      await c();
    } catch (_) {}
  }

  final failed = results.where((r) => r['ok'] != true).length;
  final out = {
    'tag': 'rtb_b_1755_offer_oneshot',
    'at': DateTime.now().toUtc().toIso8601String(),
    'pass': results.length - failed,
    'fail': failed,
    'total': results.length,
    'results': results,
  };
  final path =
      'tool/reports/sec_rtb_b_1755_offer_oneshot_hostile_${DateTime.now().millisecondsSinceEpoch}.json';
  await Directory('tool/reports').create(recursive: true);
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('\n$failed FAIL / ${results.length} total → $path');
  exit(failed == 0 ? 0 : 1);
}
