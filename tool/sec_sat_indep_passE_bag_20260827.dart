// ignore_for_file: avoid_print
/// Passagem E — saco multi-vendedor + restauração user_type.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

typedef Json = Map<String, dynamic>;
Future<Json> req(String m, String u, Map<String, String> h, [Object? b]) async {
  final r = m == 'POST'
      ? await http.post(Uri.parse(u), headers: h, body: jsonEncode(b))
      : await http.patch(Uri.parse(u), headers: h, body: jsonEncode(b));
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
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final stamp = DateTime.now().millisecondsSinceEpoch;
  // Produto do seller
  final pS = await sb.insert('products', {
    'seller_id': sellerId,
    'title': 'SATE S $stamp',
    'price': 10,
    'quantity': 3,
    'list_on_marketplace': false,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  // Produto cujo dono é o próprio buyer (segundo comerciante)
  final pB = await sb.insert('products', {
    'seller_id': buyerId,
    'title': 'SATE B $stamp',
    'price': 8,
    'quantity': 3,
    'list_on_marketplace': false,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
  });
  final oS = row((await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pS['id'],
    'quantity': 1,
    'price_total': 10,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
    'shipping_method': 'entrega em mão',
  }))['body']);
  final oB = row((await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': buyerId,
    'product_id': pB['id'],
    'quantity': 1,
    'price_total': 8,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
    'shipping_method': 'entrega em mão',
  }))['body']);
  stdout.writeln('orders S=${oS?['id']} seller=${oS?['seller_id']} B=${oB?['id']} seller=${oB?['seller_id']}');

  final ck = await req('POST', '$url/functions/v1/create-payment-intent', BH, {
    'buyer_id': buyerId,
    'order_id': oS?['id'],
    'bag_checkout': true,
    'shipping_method': 'entrega em mão',
    'bag_lines': [
      {'order_id': oS?['id']},
      {'order_id': oB?['id']},
    ],
  });
  stdout.writeln('multi_seller_bag http=${ck['http']} body=${jsonEncode(ck['body'])}');

  await req('DELETE', '$url/rest/v1/orders?id=eq.${oS?['id']}', SVC);
  await req('DELETE', '$url/rest/v1/orders?id=eq.${oB?['id']}', SVC);
  await req('DELETE', '$url/rest/v1/products?id=eq.${pS['id']}', SVC);
  await req('DELETE', '$url/rest/v1/products?id=eq.${pB['id']}', SVC);
}
