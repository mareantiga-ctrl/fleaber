// ignore_for_file: avoid_print
/// Passagem D — captura Stripe → concluido → release wallet → clawback/refund.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

typedef Json = Map<String, dynamic>;

Future<Json> req(String method, String url, Map<String, String> h, [Object? body]) async {
  final r = method == 'POST'
      ? await http.post(Uri.parse(url), headers: h, body: jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(url), headers: h, body: jsonEncode(body))
          : method == 'DELETE'
              ? await http.delete(Uri.parse(url), headers: h)
              : await http.get(Uri.parse(url), headers: h);
  dynamic p;
  try {
    p = jsonDecode(r.body);
  } catch (_) {
    p = r.body;
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

void main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
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
  void rec(String k, Object? v) {
    out[k] = v;
    stdout.writeln('$k ${jsonEncode(v)}');
  }

  Future<Json?> wallet(String id) async => row((await req(
        'GET',
        '$url/rest/v1/wallets?id=eq.$id&select=id,balance',
        SVC,
      ))['body']);

  final wS0 = await wallet(sellerId);
  final wB0 = await wallet(buyerId);
  rec('wallets_before', {'seller': wS0, 'buyer': wB0});

  final paid = await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', E2E, {
    'probe': 'setup_paid_order',
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'initial_qty': 2,
  });
  final b = paid['body'] is Map ? Json.from(paid['body'] as Map) : <String, dynamic>{};
  rec('setup', {'http': paid['http'], 'ok': b['ok'], 'order_id': b['order_id']});
  final oid = '${b['order_id']}';
  final pid = '${b['product_id']}';

  rec('seller_enviado', await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', SH, {'status': 'enviado'}));
  rec('buyer_entregue', await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {'status': 'entregue'}));
  rec('buyer_concluido', await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', BH, {'status': 'concluido'}));
  rec('order_fsm', row((await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$oid&select=status,amount_paid_cents,wallet_release_processed_at,stock_units_applied',
    SVC,
  ))['body']));

  rec('release_seller_jwt', await req('POST', '$url/rest/v1/rpc/batata_release_seller_wallet_for_order', SH, {
    'p_order_id': oid,
  }));
  rec('wallets_after_seller_release', {'seller': await wallet(sellerId), 'buyer': await wallet(buyerId)});
  rec('release_buyer_1', await req('POST', '$url/rest/v1/rpc/batata_release_seller_wallet_for_order', BH, {
    'p_order_id': oid,
  }));
  rec('order_after_release1', row((await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$oid&select=status,wallet_release_processed_at',
    SVC,
  ))['body']));
  rec('wallets_after_buyer_release1', {'seller': await wallet(sellerId), 'buyer': await wallet(buyerId)});
  rec('release_buyer_2', await req('POST', '$url/rest/v1/rpc/batata_release_seller_wallet_for_order', BH, {
    'p_order_id': oid,
  }));
  rec('wallets_after_buyer_release2', {'seller': await wallet(sellerId), 'buyer': await wallet(buyerId)});

  rec('refund_after_release', await req('POST', '$url/functions/v1/refund-order', SH, {'order_id': oid}));
  rec('order_after_refund', row((await req(
    'GET',
    '$url/rest/v1/orders?id=eq.$oid&select=status,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,stock_units_applied',
    SVC,
  ))['body']));
  rec('wallets_after_refund', {'seller': await wallet(sellerId), 'buyer': await wallet(buyerId)});

  rec('cleanup', await req('POST', '$url/functions/v1/sec-fase2-e2e-oversell', E2E, {
    'probe': 'cleanup_fixture',
    'product_id': pid,
  }));

  File('tool/reports/SAT_INDEP_PASSD_20260827.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('wrote tool/reports/SAT_INDEP_PASSD_20260827.json');
}
