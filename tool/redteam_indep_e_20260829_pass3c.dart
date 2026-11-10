import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

void main() async {
  final env = loadLiveOpsStagingEnv();
  final base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final secret = env['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '';
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  // 1) Unpaid session settle (JWT-created sessions) — must NOT mark pago
  final sess = jsonDecode(
      File('tool/redteam_indep_e_20260829/stripe_full_urls.json').readAsStringSync())
      as Map;
  final sidA = sess['session_a']['checkoutSessionId'];
  final sidB = sess['session_b']['checkoutSessionId'];
  Future<Map> settleGet(String sid) async {
    final r = await http.get(
      Uri.parse(
          '$base/functions/v1/create-payment-intent?checkout_return=success&session_id=$sid'),
      headers: {'apikey': anon, 'Authorization': 'Bearer $anon'},
    );
    return {'http': r.statusCode, 'raw': r.body.substring(0, r.body.length > 400 ? 400 : r.body.length)};
  }

  final unpaidA = await settleGet(sidA);
  final unpaidB = await settleGet(sidB);

  final hs = {
    'apikey': service,
    'Authorization': 'Bearer $service',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  Future<dynamic> obs(String path) async {
    final r = await http.get(Uri.parse('$base/rest/v1/$path'), headers: hs);
    return jsonDecode(r.body);
  }

  final ordersBeforePay = await obs(
      'orders?id=in.(${sess['order_a']},${sess['order_b']})&select=id,status,amount_paid_cents,stripe_refund_id,stock_units_applied');

  // 2) Auditor Stripe TEST harness (crash-inject secret) — dual PI on stock=1
  final e2e = await http.post(
    Uri.parse('$base/functions/v1/sec-fase2-e2e-oversell'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
      'x-fleaber-e2e-secret': secret,
    },
    body: jsonEncode({
      'buyer_id': buyerId,
      'seller_id': sellerId,
    }),
  );

  final out = {
    'unpaid_settle_a': unpaidA,
    'unpaid_settle_b': unpaidB,
    'jwt_orders_after_unpaid_settle': ordersBeforePay,
    'e2e_oversell_http': e2e.statusCode,
    'e2e_oversell': e2e.body.length > 8000 ? e2e.body.substring(0, 8000) : e2e.body,
    'note':
        'e2e_oversell uses staging crash-inject secret (not JWT). JWT dual-session capture remains separate.',
  };
  File('tool/redteam_indep_e_20260829/pass3c_capture.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('unpaid_a=${unpaidA['http']} unpaid_b=${unpaidB['http']}');
  stdout.writeln('orders=$ordersBeforePay');
  stdout.writeln('e2e_http=${e2e.statusCode}');
  stdout.writeln(e2e.body.substring(0, e2e.body.length > 2500 ? 2500 : e2e.body.length));
}
