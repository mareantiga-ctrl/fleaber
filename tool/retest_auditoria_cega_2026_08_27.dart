/// Reteste dos bloqueadores da auditoria cega — só JWT, dados descartáveis.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

void rec(String id, String result, String detail) {
  stdout.writeln('[$result] $id — $detail');
}

String snip(http.Response r, [int n = 260]) {
  final b = r.body.replaceAll('\n', ' ');
  return 'HTTP ${r.statusCode} ${b.length > n ? '${b.substring(0, n)}…' : b}';
}

void main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  rec('LOGIN', 'OK', 'buyer jwt');

  final h = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerJwt',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final products = await sb.select(
    'products',
    filter: 'seller_id=eq.$sellerId',
    limit: 1,
  );
  final productId = products.first['id']?.toString();

  Future<http.Response> rpc(String fn, Map<String, dynamic> body) {
    return http.post(
      Uri.parse('$url/rest/v1/rpc/$fn'),
      headers: h,
      body: jsonEncode(body),
    );
  }

  Future<http.Response> edge(String fn, Object? body, {String query = ''}) {
    return http.post(
      Uri.parse('$url/functions/v1/$fn$query'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerJwt',
        'Content-Type': 'application/json',
      },
      body: body == null ? null : jsonEncode(body),
    );
  }

  // --- P0-01 mint ---
  final ins = await http.post(
    Uri.parse('$url/rest/v1/orders'),
    headers: h,
    body: jsonEncode({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'price_total': 12.34,
      'quantity': 1,
      'status': 'reserva_pendente',
    }),
  );
  rec('ORDER_INSERT', ins.statusCode < 400 ? 'OK' : 'FAIL', snip(ins));
  String? oid;
  try {
    final list = jsonDecode(ins.body);
    if (list is List && list.isNotEmpty) oid = list.first['id']?.toString();
  } catch (_) {}

  Map<String, dynamic>? wBefore;
  try {
    final w = await sb.select('wallets', filter: 'id=eq.$buyerId', limit: 1);
    wBefore = w.isEmpty ? null : w.first;
  } catch (_) {}

  if (oid != null) {
    final mint = await rpc('batata_process_partial_refund_dispute', {
      'p_order_id': oid,
      'p_refund_percent': 100,
    });
    Map<String, dynamic>? wAfter;
    try {
      final w = await sb.select('wallets', filter: 'id=eq.$buyerId', limit: 1);
      wAfter = w.isEmpty ? null : w.first;
    } catch (_) {}
    final before = num.tryParse('${wBefore?['balance'] ?? 0}') ?? 0;
    final after = num.tryParse('${wAfter?['balance'] ?? 0}') ?? 0;
    final minted = after > before + 0.001;
    rec(
      'P0_MINT',
      minted ? 'STILL_OPEN' : 'BLOCKED',
      'before=$before after=$after ${snip(mint)}',
    );

    // P1-01 checkout cancelled
    try {
      await sb.patch('orders', 'id=eq.$oid', {'status': 'cancelado'});
    } catch (e) {
      rec('CANCEL_SETUP', 'INFO', '$e');
    }
    final cxl = await edge('create-payment-intent', {
      'order_id': oid,
      'buyer_id': buyerId,
      'shipping_method': 'transportadora',
    });
    rec(
      'P1_CHECKOUT_CANCELLED',
      (cxl.statusCode >= 400 &&
              cxl.body.toLowerCase().contains('status'))
          ? 'BLOCKED'
          : (cxl.body.contains('checkoutUrl') ? 'STILL_OPEN' : 'INFO'),
      snip(cxl, 320),
    );

    try {
      await sb.deleteWhere('orders', 'id=eq.$oid');
      rec('CLEANUP', 'OK', oid);
    } catch (e) {
      rec('CLEANUP', 'WARN', '$e');
    }
  }

  // unpaid checkout still allowed (control)
  final ins2 = await http.post(
    Uri.parse('$url/rest/v1/orders'),
    headers: h,
    body: jsonEncode({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId,
      'price_total': 0.01,
      'quantity': 1,
      'status': 'reserva_pendente',
      'shipping_method': 'Transportadora 3,50 €',
    }),
  );
  String? oid2;
  try {
    final list = jsonDecode(ins2.body);
    if (list is List && list.isNotEmpty) oid2 = list.first['id']?.toString();
  } catch (_) {}
  if (oid2 != null) {
    final ok = await edge('create-payment-intent', {
      'order_id': oid2,
      'buyer_id': buyerId,
      'shipping_method': 'transportadora',
    });
    rec(
      'CHECKOUT_UNPAID_OK',
      ok.body.contains('checkoutUrl') ? 'OK' : 'INFO',
      snip(ok, 200),
    );
    try {
      await sb.deleteWhere('orders', 'id=eq.$oid2');
    } catch (_) {}
  }

  // P1-04 forged JWT
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'role': 'service_role'})))
      .replaceAll('=', '');
  final hdr = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})))
      .replaceAll('=', '');
  final fake = '$hdr.$payload.fakesig';
  final e2e = await http.post(
    Uri.parse('$url/functions/v1/create-payment-intent?fase2_e2e_settle=1'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $fake',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'order_id': '00000000-0000-0000-0000-000000000001',
      'payment_intent_id': 'pi_x',
    }),
  );
  rec(
    'P1_FORGED_JWT',
    e2e.statusCode == 401 ? 'BLOCKED' : 'STILL_OPEN',
    snip(e2e),
  );

  final e2eFn = await http.post(
    Uri.parse('$url/functions/v1/sec-fase2-e2e-oversell'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $fake',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'buyer_id': buyerId, 'seller_id': sellerId}),
  );
  rec(
    'P1_E2E_FN_FORGED',
    e2eFn.statusCode == 401 ? 'BLOCKED' : 'STILL_OPEN',
    snip(e2eFn),
  );

  // P2 mux as buyer
  final mux = await edge('create-mux-live', {'title': 'RETEST NAO USAR'});
  rec(
    'P2_MUX_BUYER',
    (mux.statusCode == 403 || mux.body.contains('vendedor'))
        ? 'BLOCKED'
        : (mux.statusCode == 200 ? 'STILL_OPEN' : 'INFO'),
    snip(mux, 220),
  );

  // P2 system message
  final lives = await http.get(
    Uri.parse('$url/rest/v1/lives?select=id&limit=1'),
    headers: h,
  );
  String? liveId;
  try {
    final list = jsonDecode(lives.body);
    if (list is List && list.isNotEmpty) {
      liveId = (list.first as Map)['id']?.toString();
    }
  } catch (_) {}
  if (liveId != null) {
    final sys = await rpc('batata_live_system_message', {
      'p_live_id': liveId,
      'p_body': 'RETEST_IGNORE',
      'p_sender_label': 'Sistema',
    });
    rec(
      'P2_SYSMSG',
      (sys.body.contains('"ok": true')) ? 'STILL_OPEN' : 'BLOCKED',
      snip(sys),
    );
  } else {
    rec('P2_SYSMSG', 'SKIP', 'sem live visível');
  }

  // refund as buyer still 403
  final refB = await edge('refund-order', {
    'order_id': '00000000-0000-0000-0000-000000000001',
  });
  rec(
    'REFUND_BUYER',
    (refB.statusCode == 403 || refB.statusCode == 404) ? 'BLOCKED' : 'INFO',
    snip(refB),
  );
}
