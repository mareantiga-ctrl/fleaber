// ignore_for_file: avoid_print
/// Passagem C — Stripe TEST via harness Edge + restore PII + refund/wallet.
/// dart run tool/sec_sat_indep_passC_20260827.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

typedef Json = Map<String, dynamic>;

Future<Json> req(String method, String url, Map<String, String> h, [Object? body]) async {
  late http.Response r;
  r = method == 'POST'
      ? await http.post(Uri.parse(url), headers: h, body: body == null ? null : jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(url), headers: h, body: jsonEncode(body))
          : method == 'DELETE'
              ? await http.delete(Uri.parse(url), headers: h)
              : await http.get(Uri.parse(url), headers: h);
  dynamic p;
  try {
    p = jsonDecode(r.body);
  } catch (_) {
    p = r.body.length > 2500 ? r.body.substring(0, 2500) : r.body;
  }
  return {'http': r.statusCode, 'body': p};
}

Json? row(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Json.from(body.first as Map);
  }
  if (body is Map) return Json.from(body);
  return null;
}

String snip(dynamic b, [int m = 800]) {
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
  final e2e = (e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
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
    if (e2e.length >= 16) 'x-fleaber-e2e-secret': e2e,
  };

  final out = <String, dynamic>{};
  void rec(String id, Object? v) {
    out[id] = v;
    stdout.writeln('$id ${v is String ? v : jsonEncode(v)}');
  }

  // Restore leftover PII from pass B
  rec('restore_iban', await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', SVC, {
    'iban': null,
    'user_type': 'comprador',
  }));
  rec('profile_after_restore', row((await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type,iban,phone_verified_at',
    SVC,
  ))['body']));

  // Seller reading checkout events of buyer
  rec('seller_events_buyer_filter', await req(
    'GET',
    '$url/rest/v1/stripe_checkout_events?buyer_id=eq.$buyerId&select=id,event,buyer_id,order_id&limit=5',
    SH,
  ));
  rec('seller_wallets_buyer', await req(
    'GET',
    '$url/rest/v1/wallets?id=eq.$buyerId&select=id,balance',
    SH,
  ));
  rec('seller_wallet_tx_buyer', await req(
    'GET',
    '$url/rest/v1/wallet_transactions?wallet_id=eq.$buyerId&select=id,amount,type&limit=3',
    SH,
  ));

  Future<Json> e2eProbe(Json body) =>
      req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', E2E, body);

  rec('e2e_anon_still_denied', await req(
    'POST',
    '$url/functions/v1/sec-fase2-e2e-oversell',
    {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
      'Content-Type': 'application/json',
    },
    {'probe': 'setup_paid_order', 'buyer_id': buyerId, 'seller_id': sellerId},
  ));

  final paid = await e2eProbe({
    'probe': 'setup_paid_order',
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'initial_qty': 2,
  });
  rec('setup_paid_order', {
    'http': paid['http'],
    'ok': (paid['body'] as Map?)?['ok'],
    'keys': (paid['body'] is Map) ? (paid['body'] as Map).keys.toList() : null,
    'snip': snip(paid['body'], 1200),
  });

  final paidBody = paid['body'] is Map ? Json.from(paid['body'] as Map) : <String, dynamic>{};
  final orderId = '${paidBody['order_id'] ?? paidBody['orderId'] ?? ''}';
  final productId = '${paidBody['product_id'] ?? paidBody['productId'] ?? ''}';

  Json? orderLive;
  if (orderId.isNotEmpty && orderId != 'null') {
    orderLive = row((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$orderId&select=id,status,price_total,amount_paid_cents,contract_unit_cents,contract_qty,quantity,stock_units_applied,stripe_payment_intent_id,stripe_checkout_session_id,wallet_release_processed_at',
      SVC,
    ))['body']);
    rec('paid_order_row', orderLive);
    final prod = row((await req(
      'GET',
      '$url/rest/v1/products?id=eq.$productId&select=id,quantity,price,is_sold',
      SVC,
    ))['body']);
    rec('paid_product_stock', prod);

    // buyer cannot mark refund / change amount
    rec('buyer_patch_paid_status', await req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', BH, {
      'status': 'cancelado',
    }));
    rec('buyer_patch_paid_amount', await req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', BH, {
      'amount_paid_cents': 1,
    }));
    rec('after_buyer_patch', row((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$orderId&select=status,amount_paid_cents',
      SVC,
    ))['body']));

    rec('refund_as_buyer', await req('POST', '$url/functions/v1/refund-order', BH, {
      'order_id': orderId,
    }));
    rec('refund_as_anon', await req('POST', '$url/functions/v1/refund-order', {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
    }, {'order_id': orderId}));

    // duplicate refund as seller
    final r1 = await req('POST', '$url/functions/v1/refund-order', SH, {'order_id': orderId});
    rec('refund_seller_1', {'http': r1['http'], 'body': snip(r1['body'], 600)});
    final r2 = await req('POST', '$url/functions/v1/refund-order', SH, {'order_id': orderId});
    rec('refund_seller_2', {'http': r2['http'], 'body': snip(r2['body'], 600)});
    rec('order_after_refunds', row((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$orderId&select=status,amount_paid_cents,stripe_refund_id,stock_units_applied',
      SVC,
    ))['body']));
    rec('stock_after_refund', row((await req(
      'GET',
      '$url/rest/v1/products?id=eq.$productId&select=quantity,is_sold',
      SVC,
    ))['body']));
  }

  final bag = await e2eProbe({
    'probe': 'setup_paid_bag',
    'buyer_id': buyerId,
    'seller_id': sellerId,
  });
  rec('setup_paid_bag', {
    'http': bag['http'],
    'ok': (bag['body'] as Map?)?['ok'],
    'snip': snip(bag['body'], 1500),
  });
  final bagBody = bag['body'] is Map ? Json.from(bag['body'] as Map) : <String, dynamic>{};
  final oa = '${bagBody['order_a_id'] ?? bagBody['orderA'] ?? ''}';
  final ob = '${bagBody['order_b_id'] ?? bagBody['orderB'] ?? ''}';
  final pa = '${bagBody['product_a_id'] ?? bagBody['productA'] ?? ''}';
  final pb = '${bagBody['product_b_id'] ?? bagBody['productB'] ?? ''}';

  Future<Json?> ord(String id) async {
    if (id.isEmpty || id == 'null') return null;
    return row((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$id&select=id,status,price_total,amount_paid_cents,contract_unit_cents,quantity,stock_units_applied,stripe_payment_intent_id',
      SVC,
    ))['body']);
  }

  rec('bag_order_a', await ord(oa));
  rec('bag_order_b', await ord(ob));

  if (oa.isNotEmpty && oa != 'null') {
    final rfA = await req('POST', '$url/functions/v1/refund-order', SH, {'order_id': oa});
    rec('bag_refund_a', {'http': rfA['http'], 'body': snip(rfA['body'], 500)});
    rec('bag_a_after', await ord(oa));
    rec('bag_b_untouched', await ord(ob));
    final rfB = await req('POST', '$url/functions/v1/refund-order', SH, {'order_id': ob});
    rec('bag_refund_b', {'http': rfB['http'], 'body': snip(rfB['body'], 500)});
    rec('bag_b_after', await ord(ob));
    // duplicate A
    final rfA2 = await req('POST', '$url/functions/v1/refund-order', SH, {'order_id': oa});
    rec('bag_refund_a_dup', {'http': rfA2['http'], 'body': snip(rfA2['body'], 400)});
  }

  // cleanup e2e products
  for (final pid in [productId, pa, pb]) {
    if (pid.isEmpty || pid == 'null') continue;
    rec('cleanup_$pid', await e2eProbe({
      'probe': pid == pa || pid == pb ? 'cleanup_bag_fixture' : 'cleanup_fixture',
      'product_id': pid,
      'product_a_id': pa,
      'product_b_id': pb,
    }));
  }

  File('tool/reports/SAT_INDEP_PASSC_20260827.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('wrote tool/reports/SAT_INDEP_PASSC_20260827.json');
}
