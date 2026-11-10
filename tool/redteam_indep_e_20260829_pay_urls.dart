import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

void main() async {
  final env = loadLiveOpsStagingEnv();
  final base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final c = LiveOpsStagingClient(url: base, anonKey: anon, serviceRoleKey: service);
  final buyer = await c.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'));
  final nonce = DateTime.now().millisecondsSinceEpoch;
  final email = 'rtepay.$nonce@fleaber.staging.invalid';
  final pass = 'RtEpay_${nonce}_Aa1!';
  final freshId = await c.createAdminUser(email: email, password: pass);
  final fresh = await c.signIn(email: email, password: pass);

  Map<String, String> h(String jwt) => {
        'apikey': anon,
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  final hs = {
    'apikey': service,
    'Authorization': 'Bearer $service',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  Future<Map> rest(String method, String path, {String? jwt, Object? body, bool svc = false}) async {
    final uri = Uri.parse('$base/rest/v1/$path');
    final hdr = svc ? hs : h(jwt!);
    final r = method == 'GET'
        ? await http.get(uri, headers: hdr)
        : method == 'PATCH'
            ? await http.patch(uri, headers: hdr, body: jsonEncode(body))
            : await http.post(uri, headers: hdr, body: jsonEncode(body));
    return {'http': r.statusCode, 'body': jsonDecode(r.body)};
  }

  Future<Map> edge(String jwt, Map body) async {
    final r = await http.post(Uri.parse('$base/functions/v1/create-payment-intent'),
        headers: h(jwt), body: jsonEncode(body));
    return {'http': r.statusCode, 'raw': r.body, 'body': jsonDecode(r.body)};
  }

  final prod = await rest('POST', 'products', jwt: buyer /* will fail */, body: {});
  // seller insert
  final sellerJwt = await c.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'));
  final p = await rest('POST', 'products', jwt: sellerJwt, body: {
    'seller_id': sellerId,
    'title': 'RT-E PAY $nonce',
    'price': 8.0,
    'quantity': 1,
    'list_on_marketplace': true,
    'image_urls': [],
  });
  final pid = (p['body'] as List).first['id'];
  Future<String> mkOrder(String jwt, String bid) async {
    final o = await rest('POST', 'orders', jwt: jwt, body: {
      'product_id': pid,
      'buyer_id': bid,
      'seller_id': sellerId,
      'price_total': 8,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na App',
      'shipping_method': 'hand',
      'quantity': 1,
      'is_reservation': true,
    });
    return (o['body'] as List).first['id'] as String;
  }

  final oa = await mkOrder(buyer, buyerId);
  final ob = await mkOrder(fresh, freshId);
  final sa = await edge(buyer, {
    'buyer_id': buyerId,
    'order_id': oa,
    'shipping_method': 'hand',
  });
  final sb = await edge(fresh, {
    'buyer_id': freshId,
    'order_id': ob,
    'shipping_method': 'hand',
  });

  final out = {
    'product_id': pid,
    'order_a': oa,
    'order_b': ob,
    'session_a': sa['body'] is Map ? sa['body'] : sa['raw'],
    'session_b': sb['body'] is Map ? sb['body'] : sb['raw'],
    'url_a_len': sa['body'] is Map ? '${sa['body']['checkoutUrl']}'.length : 0,
    'url_b_len': sb['body'] is Map ? '${sb['body']['checkoutUrl']}'.length : 0,
  };
  File('tool/redteam_indep_e_20260829/stripe_full_urls.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('url_a_len=${out['url_a_len']} url_b_len=${out['url_b_len']}');
  stdout.writeln('sid_a=${sa['body'] is Map ? sa['body']['checkoutSessionId'] : '?'}');
  stdout.writeln('sid_b=${sb['body'] is Map ? sb['body']['checkoutSessionId'] : '?'}');
}
