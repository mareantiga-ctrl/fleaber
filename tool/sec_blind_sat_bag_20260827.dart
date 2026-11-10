// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

void main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final tok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $tok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  Future<Map<String, dynamic>> insP(String t, num price) async {
    return sb.insert('products', {
      'seller_id': sellerId,
      'title': t,
      'price': price,
      'quantity': 3,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
  }

  final pA = await insP('SAT-BAG-A', 40);
  final pB = await insP('SAT-BAG-B', 25);
  final oA = await http.post(Uri.parse('$url/rest/v1/orders'), headers: BH, body: jsonEncode({
    'buyer_id': buyerId, 'seller_id': sellerId, 'product_id': pA['id'],
    'quantity': 1, 'price_total': 40, 'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app', 'shipping_method': 'entrega em mão',
  }));
  final oB = await http.post(Uri.parse('$url/rest/v1/orders'), headers: BH, body: jsonEncode({
    'buyer_id': buyerId, 'seller_id': sellerId, 'product_id': pB['id'],
    'quantity': 1, 'price_total': 1, 'status': 'reserva_pendente',
    'payment_method': 'proposta aceite', 'shipping_method': 'entrega em mão',
  }));
  final a = (jsonDecode(oA.body) as List).first as Map;
  final b = (jsonDecode(oB.body) as List).first as Map;
  stdout.writeln('A cuc=${a['contract_unit_cents']} B cuc=${b['contract_unit_cents']}');
  final ck = await http.post(
    Uri.parse('$url/functions/v1/create-payment-intent'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $tok',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'buyer_id': buyerId,
      'order_id': a['id'],
      'product_id': pA['id'],
      'bag_checkout': true,
      'bag_lines': [
        {'order_id': a['id']},
        {'order_id': b['id']},
      ],
      'shipping_method': 'entrega em mão',
    }),
  );
  stdout.writeln('BAG ${ck.statusCode} ${ck.body}');
  await http.delete(Uri.parse('$url/rest/v1/orders?id=eq.${a['id']}'), headers: SVC);
  await http.delete(Uri.parse('$url/rest/v1/orders?id=eq.${b['id']}'), headers: SVC);
  await http.delete(Uri.parse('$url/rest/v1/chats?product_id=eq.${pA['id']}'), headers: SVC);
  await http.delete(Uri.parse('$url/rest/v1/chats?product_id=eq.${pB['id']}'), headers: SVC);
  await http.delete(Uri.parse('$url/rest/v1/products?id=eq.${pA['id']}'), headers: SVC);
  await http.delete(Uri.parse('$url/rest/v1/products?id=eq.${pB['id']}'), headers: SVC);
}
