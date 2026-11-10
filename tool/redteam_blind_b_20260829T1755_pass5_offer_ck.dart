// dart run tool/redteam_blind_b_20260829T1755_pass5_offer_ck.dart
// Prova: leftover-offer → duas orders → duas cotações Stripe
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

  await http.delete(
    Uri.parse(
      '$url/rest/v1/products?title=eq.${Uri.encodeQueryComponent('RTB-B-p5 leftover ck')}',
    ),
    headers: hSvc,
  );

  Future<http.Response> ck(String oid) => http.post(
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
          'amount': 2000,
        }),
      );

  final prod = await http.post(
    Uri.parse('$url/rest/v1/products'),
    headers: hSeller,
    body: jsonEncode({
      'seller_id': sellerId,
      'title': 'RTB-B-p5 leftover ck',
      'price': 20.0,
      'quantity': 2,
      'list_on_marketplace': true,
    }),
  );
  if (prod.statusCode >= 300) {
    stdout.writeln('prod_fail ${prod.statusCode} ${prod.body}');
    return;
  }
  final pid = (jsonDecode(prod.body) as List).first['id'] as String;

  final offerIns = await http.post(
    Uri.parse('$url/rest/v1/product_offers'),
    headers: hBuyer,
    body: jsonEncode({
      'product_id': pid,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 2.00,
      'offered_by': 'buyer',
    }),
  );
  if (offerIns.statusCode >= 300) {
    stdout.writeln('offer_fail ${offerIns.statusCode} ${offerIns.body}');
    await http.delete(Uri.parse('$url/rest/v1/products?id=eq.$pid'), headers: hSvc);
    return;
  }
  final offerId = (jsonDecode(offerIns.body) as List).first['id'] as String;
  await http.patch(
    Uri.parse('$url/rest/v1/product_offers?id=eq.$offerId'),
    headers: hSeller,
    body: jsonEncode({
      'status': 'accepted',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    }),
  );

  Future<Json> newOrder() async {
    final r = await http.post(
      Uri.parse('$url/rest/v1/orders'),
      headers: hBuyer,
      body: jsonEncode({
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pid,
        'quantity': 1,
        'price_total': 20,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'hand',
      }),
    );
    return (jsonDecode(r.body) as List).first as Json;
  }

  final o1 = await newOrder();
  final o2 = await newOrder();
  final ck1 = await ck(o1['id'] as String);
  final ck2 = await ck(o2['id'] as String);

  final out = {
    'product_id': pid,
    'offer_id': offerId,
    'o1': {
      'id': o1['id'],
      'price_total': o1['price_total'],
      'contract_unit_cents': o1['contract_unit_cents'],
      'product_offer_id': o1['product_offer_id'],
      'checkout': jsonDecode(ck1.body),
    },
    'o2': {
      'id': o2['id'],
      'price_total': o2['price_total'],
      'contract_unit_cents': o2['contract_unit_cents'],
      'product_offer_id': o2['product_offer_id'],
      'checkout': jsonDecode(ck2.body),
    },
  };
  File('tool/redteam_blind_b_20260829T1755_pass5_offer_ck.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));

  await http.delete(
    Uri.parse('$url/rest/v1/orders?id=eq.${o1['id']}'),
    headers: hSvc,
  );
  await http.delete(
    Uri.parse('$url/rest/v1/orders?id=eq.${o2['id']}'),
    headers: hSvc,
  );
  await http.delete(
    Uri.parse('$url/rest/v1/product_offers?id=eq.$offerId'),
    headers: hSvc,
  );
  await http.delete(
    Uri.parse('$url/rest/v1/products?id=eq.$pid'),
    headers: hSvc,
  );
}
