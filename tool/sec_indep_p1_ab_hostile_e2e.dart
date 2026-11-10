// ignore_for_file: avoid_print
/// P1-A bag refund + P1-B price_total freeze — staging Stripe TEST.
/// dart run tool/sec_indep_p1_ab_hostile_e2e.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> postJson(
  String url,
  Map<String, String> headers,
  Object body,
) async {
  final r = await http.post(
    Uri.parse(url),
    headers: headers,
    body: jsonEncode(body),
  );
  dynamic parsed;
  try {
    parsed = jsonDecode(r.body);
  } catch (_) {
    parsed = r.body;
  }
  return {'http': r.statusCode, 'body': parsed};
}

void main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT staging only');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final e2e = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
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
  final E2E = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    if (e2e.length >= 16) 'x-fleaber-e2e-secret': e2e,
  };

  final results = <Map<String, dynamic>>[];
  void add(String id, bool ok, Object detail) {
    results.add({'id': id, 'ok': ok, 'detail': detail});
    stdout.writeln('${ok ? "PASS" : "FAIL"} $id — $detail');
  }

  // ---------- P1-B: price_total freeze ----------
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final prod = await sb.insert('products', {
    'seller_id': sellerId,
    'title': 'P1B price $stamp',
    'price': 6.66,
    'quantity': 3,
    'list_on_marketplace': false,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final ordRes = await http.post(
    Uri.parse('$url/rest/v1/orders'),
    headers: BH,
    body: jsonEncode({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': prod['id'],
      'quantity': 1,
      'price_total': 6.66,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    }),
  );
  final ordList = jsonDecode(ordRes.body) as List;
  final oid = ordList.first['id'] as String;
  final before = Number(ordList.first['price_total']);

  final patch = await http.patch(
    Uri.parse('$url/rest/v1/orders?id=eq.$oid'),
    headers: BH,
    body: jsonEncode({'price_total': 0.01}),
  );
  final afterRows = jsonDecode(patch.body);
  final after = afterRows is List && afterRows.isNotEmpty
      ? Number(afterRows.first['price_total'])
      : null;
  // Prefer representation may return updated row with frozen value, or empty.
  final check = await http.get(
    Uri.parse('$url/rest/v1/orders?id=eq.$oid&select=price_total'),
    headers: BH,
  );
  final livePrice = Number((jsonDecode(check.body) as List).first['price_total']);
  final p1bOk = (livePrice - before).abs() < 0.001 && livePrice != 0.01;
  add('P1_B_PRICE_TOTAL_FROZEN', p1bOk, {
    'http': patch.statusCode,
    'before': before,
    'patch_body_price': after,
    'live': livePrice,
  });

  // service_role still can align (Edge path)
  final svcPatch = await http.patch(
    Uri.parse('$url/rest/v1/orders?id=eq.$oid'),
    headers: {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    },
    body: jsonEncode({'price_total': 7.64}),
  );
  final svcLive = await http.get(
    Uri.parse('$url/rest/v1/orders?id=eq.$oid&select=price_total'),
    headers: {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
    },
  );
  final svcPrice =
      Number((jsonDecode(svcLive.body) as List).first['price_total']);
  add('P1_B_SERVICE_ROLE_CAN_ALIGN', (svcPrice - 7.64).abs() < 0.001, {
    'http': svcPatch.statusCode,
    'live': svcPrice,
  });

  await http.delete(
    Uri.parse('$url/rest/v1/orders?id=eq.$oid'),
    headers: {'apikey': svc, 'Authorization': 'Bearer $svc'},
  );
  try {
    await http.delete(
      Uri.parse('$url/rest/v1/chats?product_id=eq.${prod['id']}'),
      headers: {'apikey': svc, 'Authorization': 'Bearer $svc'},
    );
  } catch (_) {}
  await http.delete(
    Uri.parse('$url/rest/v1/products?id=eq.${prod['id']}'),
    headers: {'apikey': svc, 'Authorization': 'Bearer $svc'},
  );

  // ---------- P1-A: bag dual refund ----------
  final bag = await postJson(
    '$url/functions/v1/sec-fase2-e2e-oversell',
    E2E,
    {
      'probe': 'setup_paid_bag',
      'buyer_id': buyerId,
      'seller_id': sellerId,
    },
  );
  final bagBody = bag['body'];
  final bagOk = bag['http'] == 200 &&
      bagBody is Map &&
      bagBody['ok'] == true;
  add('P1_A_SETUP_BAG', bagOk, {
    'http': bag['http'],
    'pi': bagBody is Map ? bagBody['payment_intent_id'] : null,
    'paid_a': bagBody is Map ? bagBody['paid_a'] : null,
    'paid_b': bagBody is Map ? bagBody['paid_b'] : null,
  });

  String? refundAId;
  String? refundBId;
  if (bagOk && bagBody is Map) {
    final oa = bagBody['order_a_id']?.toString() ?? '';
    final ob = bagBody['order_b_id']?.toString() ?? '';
    final paidA = (bagBody['paid_a'] as num?)?.toInt() ?? 0;
    final paidB = (bagBody['paid_b'] as num?)?.toInt() ?? 0;
    final piId = bagBody['payment_intent_id']?.toString() ?? '';

    final ra = await postJson(
      '$url/functions/v1/refund-order',
      SH,
      {'order_id': oa},
    );
    final raBody = ra['body'];
    refundAId = raBody is Map ? raBody['refund_id']?.toString() : null;
    final raOk = ra['http'] == 200 &&
        raBody is Map &&
        raBody['ok'] == true &&
        (raBody['amount_cents'] == paidA ||
            Number(raBody['amount_cents']) == paidA);
    add('P1_A_REFUND_LINE_A', raOk, {
      'http': ra['http'],
      'refund_id': refundAId,
      'amount': raBody is Map ? raBody['amount_cents'] : null,
      'expect': paidA,
    });

    final rb = await postJson(
      '$url/functions/v1/refund-order',
      SH,
      {'order_id': ob},
    );
    final rbBody = rb['body'];
    refundBId = rbBody is Map ? rbBody['refund_id']?.toString() : null;
    final distinct = refundBId != null &&
        refundAId != null &&
        refundBId != refundAId;
    final rbAmtOk = rbBody is Map &&
        (rbBody['amount_cents'] == paidB ||
            Number(rbBody['amount_cents']) == paidB);
    final rbOk = rb['http'] == 200 &&
        rbBody is Map &&
        rbBody['ok'] == true &&
        distinct &&
        rbAmtOk;
    add('P1_A_REFUND_LINE_B_DISTINCT', rbOk, {
      'http': rb['http'],
      'refund_a': refundAId,
      'refund_b': refundBId,
      'amount_b': rbBody is Map ? rbBody['amount_cents'] : null,
      'expect_b': paidB,
      'distinct': distinct,
      'err': rbBody is Map ? rbBody['error'] : null,
    });

    // Stripe list via harness
    final listed = await postJson(
      '$url/functions/v1/sec-fase2-e2e-oversell',
      E2E,
      {'probe': 'list_stripe_refunds', 'payment_intent_id': piId},
    );
    final listedBody = listed['body'];
    var sumRefunds = 0;
    var count = 0;
    if (listedBody is Map) {
      final refunds = listedBody['refunds'];
      if (refunds is List) {
        count = refunds.length;
        for (final r in refunds) {
          if (r is Map) sumRefunds += (r['amount'] as num?)?.toInt() ?? 0;
        }
      }
    }
    final piAmt = (bagBody['pi_amount_cents'] as num?)?.toInt() ?? 1115;
    add('P1_A_STRIPE_SUM_EQ_CAPTURE', count >= 2 && sumRefunds == piAmt, {
      'count': count,
      'sum': sumRefunds,
      'pi': piAmt,
      'listed_http': listed['http'],
    });

    // Order statuses
    final oaRow = await http.get(
      Uri.parse(
        '$url/rest/v1/orders?id=eq.$oa&select=status,stripe_refund_id,amount_paid_cents',
      ),
      headers: {'apikey': svc, 'Authorization': 'Bearer $svc'},
    );
    final obRow = await http.get(
      Uri.parse(
        '$url/rest/v1/orders?id=eq.$ob&select=status,stripe_refund_id,amount_paid_cents',
      ),
      headers: {'apikey': svc, 'Authorization': 'Bearer $svc'},
    );
    final aMap = (jsonDecode(oaRow.body) as List).first as Map;
    final bMap = (jsonDecode(obRow.body) as List).first as Map;
    add('P1_A_ORDERS_CANCELLED_DISTINCT_REFUNDS', 
      '${aMap['status']}'.toLowerCase().contains('cancel') &&
      '${bMap['status']}'.toLowerCase().contains('cancel') &&
      aMap['stripe_refund_id'] != bMap['stripe_refund_id'],
      {'a': aMap, 'b': bMap},
    );

    await postJson(
      '$url/functions/v1/sec-fase2-e2e-oversell',
      E2E,
      {
        'probe': 'cleanup_bag_fixture',
        'product_a_id': bagBody['product_a_id'],
        'product_b_id': bagBody['product_b_id'],
      },
    );
  }

  final fail = results.where((r) => r['ok'] != true).length;
  final evidence = {
    'test': 'INDEP_P1_A_B',
    'at': DateTime.now().toUtc().toIso8601String(),
    'staging_ref': 'fxdknzrqjenzqcvnwqqq',
    'ok': fail == 0,
    'fail': fail,
    'results': results,
  };
  final path = 'tool/reports/HARDENING_INDEP_P1_AB_HOSTILE.json';
  await File(path).writeAsString(
    const JsonEncoder.withIndent('  ').convert(evidence),
  );
  stdout.writeln('evidence -> $path ($fail fail)');
  exit(fail == 0 ? 0 : 1);
}

num Number(Object? v) {
  if (v is num) return v;
  return num.tryParse('$v') ?? -1;
}
