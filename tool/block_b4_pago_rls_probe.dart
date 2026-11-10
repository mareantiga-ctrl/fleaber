// ignore_for_file: avoid_print
/// Block B4 — hostile probe: forge `pago` + financial columns (staging only).
/// dart run tool/block_b4_pago_rls_probe.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String url,
  Map<String, String> h, [
  Object? body,
]) async {
  final r = method == 'POST'
      ? await http.post(Uri.parse(url), headers: h, body: jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(url), headers: h, body: jsonEncode(body))
          : await http.get(Uri.parse(url), headers: h);
  dynamic p;
  try {
    p = jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p};
}

Map<String, dynamic>? row(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  return null;
}

String msgOf(dynamic body) {
  if (body is Map) {
    return '${body['message'] ?? body['code'] ?? body}';
  }
  return '$body';
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: staging only');
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
  void add(String id, bool pass, Object detail) {
    results.add({'id': id, 'pass': pass, 'detail': detail});
    print('${pass ? 'PASS' : 'FAIL'} $id — $detail');
  }

  // Seed product owned by seller (service).
  final prodIns = await req('POST', '$url/rest/v1/products', SVC, {
    'seller_id': sellerId,
    'title': 'B4 probe ${DateTime.now().toUtc().toIso8601String()}',
    'price': 7,
    'quantity': 5,
    'list_on_marketplace': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final productId = row(prodIns['body'])?['id']?.toString();
  if (productId == null || productId.isEmpty) {
    stderr.writeln('seed product failed: ${prodIns['body']}');
    exit(1);
  }

  Future<String?> insertOrder({
    required Map<String, String> headers,
    required String status,
    required String paymentMethod,
    double priceTotal = 7,
    String shipping = 'Envio Transportadora (€3.50)',
  }) async {
    final r = await req('POST', '$url/rest/v1/orders', headers, {
      'product_id': productId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'price_total': priceTotal,
      'quantity': 1,
      'status': status,
      'payment_method': paymentMethod,
      'shipping_method': shipping,
      'is_reservation': true,
    });
    return row(r['body'])?['id']?.toString();
  }

  Future<Map<String, dynamic>> patchOrder(
    Map<String, String> headers,
    String orderId,
    Map<String, dynamic> data,
  ) =>
      req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', headers, data);

  Future<Map<String, dynamic>?> fetchOrder(String orderId) async {
    final r = await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$orderId&select=id,status,price_total,amount_paid_cents,stripe_payment_intent_id,shipping_method,payment_method,proof_url',
      SVC,
    );
    return row(r['body']);
  }

  // --- B4-1 buyer forges pago on own unpaid order ---
  final o1 = await insertOrder(
    headers: BH,
    status: 'reserva_pendente',
    paymentMethod: 'Pagamento na App',
  );
  if (o1 == null) {
    add('B4_1_BUYER_FORGE_PAGO', false, 'insert failed');
  } else {
    final p = await patchOrder(BH, o1, {'status': 'pago'});
    final after = await fetchOrder(o1);
    final blocked = after?['status'] != 'pago';
    add(
      'B4_1_BUYER_FORGE_PAGO',
      blocked,
      {
        'http': p['http'],
        'msg': msgOf(p['body']),
        'status': after?['status'],
      },
    );
  }

  // --- B4-2 buyer forges amount_paid_cents / PI ---
  final o2 = await insertOrder(
    headers: BH,
    status: 'reserva_pendente',
    paymentMethod: 'Pagamento na App',
  );
  if (o2 == null) {
    add('B4_2_BUYER_FORGE_CAPTURE', false, 'insert failed');
  } else {
    final p = await patchOrder(BH, o2, {
      'amount_paid_cents': 99900,
      'stripe_payment_intent_id': 'pi_forged_b4',
      'status': 'pago',
    });
    final after = await fetchOrder(o2);
    final blocked = after?['status'] != 'pago' &&
        after?['amount_paid_cents'] == null &&
        (after?['stripe_payment_intent_id'] == null ||
            '${after?['stripe_payment_intent_id']}'.isEmpty);
    add(
      'B4_2_BUYER_FORGE_CAPTURE',
      blocked,
      {
        'http': p['http'],
        'msg': msgOf(p['body']),
        'status': after?['status'],
        'amount_paid_cents': after?['amount_paid_cents'],
        'pi': after?['stripe_payment_intent_id'],
      },
    );
  }

  // --- B4-3 buyer mutates price_total ---
  final o3 = await insertOrder(
    headers: BH,
    status: 'reserva_pendente',
    paymentMethod: 'Pagamento na App',
    priceTotal: 7,
  );
  if (o3 == null) {
    add('B4_3_BUYER_MUTATE_PRICE', false, 'insert failed');
  } else {
    final before = await fetchOrder(o3);
    final p = await patchOrder(BH, o3, {'price_total': 0.01});
    final after = await fetchOrder(o3);
    final unchanged =
        (after?['price_total'] as num?)?.toDouble() ==
            (before?['price_total'] as num?)?.toDouble();
    add(
      'B4_3_BUYER_MUTATE_PRICE',
      unchanged,
      {
        'http': p['http'],
        'msg': msgOf(p['body']),
        'before': before?['price_total'],
        'after': after?['price_total'],
      },
    );
  }

  // --- B4-4 other user cannot update foreign order ---
  final o4 = await insertOrder(
    headers: BH,
    status: 'reserva_pendente',
    paymentMethod: 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
  );
  // Sign in as buyer again is fine; forge as seller trying buyer-only fields is separate.
  // Use a third-party: anon without party — patch should affect 0 rows / RLS.
  final strangerTok = buyerTok; // same buyer is party; use seller patch on buyer forge below.
  if (o4 == null) {
    add('B4_4_STRANGER_PAGO', false, 'insert failed');
  } else {
    // Create "other" by using seller JWT to mark pago without proof (should fail).
    final pSeller = await patchOrder(SH, o4, {'status': 'pago'});
    final afterSeller = await fetchOrder(o4);
    final sellerBlocked = afterSeller?['status'] != 'pago';
    add(
      'B4_4_SELLER_MBWAY_PAGO_WITHOUT_PROOF',
      sellerBlocked,
      {
        'http': pSeller['http'],
        'msg': msgOf(pSeller['body']),
        'status': afterSeller?['status'],
      },
    );

    // Promote to aguarda_confirmacao + proof via service, then seller pago should work
    // (authorized path — not a vulnerability).
    await req('PATCH', '$url/rest/v1/orders?id=eq.$o4', SVC, {
      'status': 'aguarda_confirmacao',
      'proof_url': 'https://example.com/b4-proof.png',
      'payment_method': 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
    });
    final pOk = await patchOrder(SH, o4, {'status': 'pago'});
    final afterOk = await fetchOrder(o4);
    add(
      'B4_4b_SELLER_MBWAY_PAGO_WITH_PROOF_OK',
      afterOk?['status'] == 'pago',
      {
        'http': pOk['http'],
        'msg': msgOf(pOk['body']),
        'status': afterOk?['status'],
      },
    );
  }

  // --- B4-5 buyer cannot mark foreign seller order (create as svc with other buyer) ---
  final o5Ins = await req('POST', '$url/rest/v1/orders', SVC, {
    'product_id': productId,
    'buyer_id': sellerId, // seller as "buyer" of own product — odd but foreign to test buyer
    'seller_id': sellerId,
    'price_total': 7,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na App',
    'shipping_method': 'Entrega em Mão (€0.00)',
    'is_reservation': true,
  });
  final o5 = row(o5Ins['body'])?['id']?.toString();
  if (o5 == null) {
    add('B4_5_FOREIGN_ORDER', false, {'insert': o5Ins['body']});
  } else {
    final p = await patchOrder(BH, o5, {'status': 'pago', 'price_total': 1});
    final after = await fetchOrder(o5);
    final blocked = after?['status'] != 'pago' &&
        ((after?['price_total'] as num?)?.toDouble() ?? -1) != 1.0;
    add(
      'B4_5_FOREIGN_ORDER',
      blocked,
      {
        'http': p['http'],
        'msg': msgOf(p['body']),
        'status': after?['status'],
        'price_total': after?['price_total'],
        'note': 'buyer JWT must not mutate seller-as-buyer order',
      },
    );
  }

  // silence unused
  strangerTok;

  final outPath =
      'tool/reports/block_b_fix_2026-09-27/evidence/b4_pago_rls_probe.json';
  await Directory('tool/reports/block_b_fix_2026-09-27/evidence')
      .create(recursive: true);
  final fails = results.where((r) => r['pass'] != true).length;
  await File(outPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'at': DateTime.now().toUtc().toIso8601String(),
      'project': 'fxdknzrqjenzqcvnwqqq',
      'product_id': productId,
      'fails': fails,
      'results': results,
    }),
  );
  print('evidence -> $outPath (fails=$fails)');
  exit(fails == 0 ? 0 : 1);
}
