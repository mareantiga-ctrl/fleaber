// dart run tool/redteam_blind_b_20260829T1755_pass5_align.dart
// Anti-FP: price_total após create-payment-intent (alinhamento Edge)
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

typedef Json = Map<String, dynamic>;

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final client = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final hBuyer = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerJwt',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final hSeller = {
    'apikey': anon,
    'Authorization': 'Bearer $sellerJwt',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final hSvc = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final prod = await http.post(
    Uri.parse('$url/rest/v1/products'),
    headers: hSeller,
    body: jsonEncode({
      'seller_id': sellerId,
      'title': 'RTB-B-p5 price_total align',
      'price': 6.5,
      'quantity': 1,
      'list_on_marketplace': true,
    }),
  );
  final pid = (jsonDecode(prod.body) as List).first['id'] as String;

  final ord = await http.post(
    Uri.parse('$url/rest/v1/orders'),
    headers: hBuyer,
    body: jsonEncode({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 0.01,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
    }),
  );
  final before = (jsonDecode(ord.body) as List).first as Json;
  final oid = before['id'] as String;

  final ck = await http.post(
    Uri.parse('$url/functions/v1/create-payment-intent'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'buyer_id': buyerId,
      'order_id': oid,
      'shipping_method': 'hand',
      'amount': 1,
    }),
  );

  final after = await http.get(
    Uri.parse(
      '$url/rest/v1/orders?id=eq.$oid&select=id,status,price_total,contract_unit_cents,amount_paid_cents,stripe_checkout_session_id',
    ),
    headers: hSvc,
  );

  final out = {
    'insert': {
      'price_total': before['price_total'],
      'contract_unit_cents': before['contract_unit_cents'],
      'order_id': oid,
    },
    'checkout': jsonDecode(ck.body),
    'after_checkout': jsonDecode(after.body),
  };

  File('tool/redteam_blind_b_20260829T1755_pass5_align.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));

  await http.delete(
    Uri.parse('$url/rest/v1/orders?id=eq.$oid'),
    headers: hSvc,
  );
  await http.delete(
    Uri.parse('$url/rest/v1/products?id=eq.$pid'),
    headers: hSvc,
  );
}
