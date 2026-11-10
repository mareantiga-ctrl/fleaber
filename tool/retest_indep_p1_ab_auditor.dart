// ignore_for_file: avoid_print
/// Auditor independente — reteste P1-A / P1-B. Não usa JSON do C1.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

final out = <String, dynamic>{};
void rec(String id, Object? v) {
  out[id] = v;
  print('$id: ${jsonEncode(v)}');
}

Future<Map<String, dynamic>> req(
  String method,
  String url,
  Map<String, String> headers, [
  Object? body,
]) async {
  late http.Response r;
  final b = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      r = await http.get(Uri.parse(url), headers: headers);
      break;
    case 'POST':
      r = await http.post(Uri.parse(url), headers: headers, body: b);
      break;
    case 'PATCH':
      r = await http.patch(Uri.parse(url), headers: headers, body: b);
      break;
    case 'DELETE':
      r = await http.delete(Uri.parse(url), headers: headers);
      break;
    default:
      throw StateError(method);
  }
  Object? parsed;
  try {
    parsed = jsonDecode(r.body);
  } catch (_) {
    parsed = r.body;
  }
  return {'ok': r.statusCode >= 200 && r.statusCode < 300, 'status': r.statusCode, 'body': parsed};
}

String? rowId(Object? body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return (body.first as Map)['id']?.toString();
  }
  if (body is Map) return body['id']?.toString();
  return null;
}

Map<String, dynamic>? rowMap(Object? body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
}

num? priceOf(Object? body) => rowMap(body)?['price_total'] as num?;

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    throw StateError('staging only');
  }
  rec('meta', {
    'at': DateTime.now().toUtc().toIso8601String(),
    'staging': 'fxdknzrqjenzqcvnwqqq',
    'c1_json_used_as_proof': false,
    'production_touched': false,
  });
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final e2e = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final c = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerJwt = await c.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await c.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  Map<String, String> u(String jwt) => {
        'apikey': anon,
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  final BH = u(buyerJwt);
  final SH = u(sellerJwt);
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final e2eHdr = {
    ...SVC,
    if (e2e.length >= 16) 'x-fleaber-e2e-secret': e2e,
  };

  final p = await req('POST', '$url/rest/v1/products', SH, {
    'seller_id': sellerId,
    'title': 'AUD P1B ${DateTime.now().millisecondsSinceEpoch}',
    'price': 6.66,
    'quantity': 4,
    'list_on_marketplace': false,
    'available_for_live': false,
    'is_sold': false,
  });
  final pid = rowId(p['body']);
  rec('prod', {'status': p['status'], 'id': pid});

  final o = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 1,
    'price_total': 6.66,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
  });
  final oid = rowId(o['body']);
  rec('ord_insert', {'status': o['status'], 'id': oid, 'price': priceOf(o['body'])});

  rec(
    'buyer_patch_001',
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {'price_total': 0.01}),
  );
  rec(
    'after_buyer_patch',
    await req('GET', '$url/rest/v1/orders?select=id,price_total,status&id=eq.$oid', BH),
  );
  rec(
    'seller_patch_999',
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {'price_total': 999}),
  );
  rec(
    'after_seller_patch',
    await req('GET', '$url/rest/v1/orders?select=id,price_total&id=eq.$oid', BH),
  );
  rec(
    'svc_align_764',
    await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SVC, {'price_total': 7.64}),
  );
  rec(
    'after_svc',
    await req('GET', '$url/rest/v1/orders?select=id,price_total&id=eq.$oid', BH),
  );

  final oLow = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 1,
    'price_total': 0.01,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
  });
  rec('insert_deflated', {
    'status': oLow['status'],
    'id': rowId(oLow['body']),
    'price': priceOf(oLow['body']),
  });

  // P1-A: own bag + refund A then B + retry + reverse bag (B then A)
  rec(
    'bag_ab',
    await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', e2eHdr, {
      'probe': 'setup_paid_bag',
      'buyer_id': buyerId,
      'seller_id': sellerId,
    }),
  );
  final bagAb = (out['bag_ab'] as Map)['body'];
  if (bagAb is Map && bagAb['ok'] == true) {
    final oa = bagAb['order_a_id']?.toString();
    final ob = bagAb['order_b_id']?.toString();
    rec('refund_a', await req('POST', '$url/functions/v1/refund-order', SH, {'order_id': oa}));
    rec('refund_b', await req('POST', '$url/functions/v1/refund-order', SH, {'order_id': ob}));
    rec('refund_a_retry', await req('POST', '$url/functions/v1/refund-order', SH, {'order_id': oa}));
    rec(
      'orders_ab',
      await req(
        'GET',
        '$url/rest/v1/orders?select=id,status,amount_paid_cents,stripe_refund_id,price_total&id=in.($oa,$ob)',
        SVC,
      ),
    );
    rec(
      'buyer_refund_blocked',
      await req('POST', '$url/functions/v1/refund-order', BH, {'order_id': oa}),
    );
    rec(
      'cleanup_ab',
      await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', e2eHdr, {
        'probe': 'cleanup_bag_fixture',
        'product_a_id': bagAb['product_a_id'],
        'product_b_id': bagAb['product_b_id'],
      }),
    );
  }

  rec(
    'bag_ba',
    await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', e2eHdr, {
      'probe': 'setup_paid_bag',
      'buyer_id': buyerId,
      'seller_id': sellerId,
    }),
  );
  final bagBa = (out['bag_ba'] as Map)['body'];
  if (bagBa is Map && bagBa['ok'] == true) {
    final oa = bagBa['order_a_id']?.toString();
    final ob = bagBa['order_b_id']?.toString();
    rec('refund_b_first', await req('POST', '$url/functions/v1/refund-order', SH, {'order_id': ob}));
    rec('refund_a_second', await req('POST', '$url/functions/v1/refund-order', SH, {'order_id': oa}));
    rec(
      'orders_ba',
      await req(
        'GET',
        '$url/rest/v1/orders?select=id,status,amount_paid_cents,stripe_refund_id&id=in.($oa,$ob)',
        SVC,
      ),
    );
    rec(
      'cleanup_ba',
      await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', e2eHdr, {
        'probe': 'cleanup_bag_fixture',
        'product_a_id': bagBa['product_a_id'],
        'product_b_id': bagBa['product_b_id'],
      }),
    );
  }

  rec(
    'wallets',
    await req(
      'GET',
      '$url/rest/v1/wallets?select=id,balance&id=in.($buyerId,$sellerId)',
      SVC,
    ),
  );

  if (pid != null) {
    await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid', SVC);
    await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
  }

  final path = 'tool/reports/RETEST_INDEP_P1_AB_AUDITOR.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  print('WROTE $path');
}
