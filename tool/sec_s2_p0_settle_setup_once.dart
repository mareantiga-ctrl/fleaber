// ignore_for_file: avoid_print
/// Setup order + Checkout URL for S2-P0 manual/browser pay.
/// dart run tool/sec_s2_p0_settle_setup_once.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final prod = await http.post(
    Uri.parse('$url/rest/v1/products'),
    headers: SVC,
    body: jsonEncode({
      'seller_id': sellerId,
      'title': 'S2 P0 settle $stamp',
      'price': 5.0,
      'quantity': 2,
      'ref_code': 'S2P0-$stamp',
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    }),
  );
  final pid = (jsonDecode(prod.body) as List).first['id'] as String;
  final ord = await http.post(
    Uri.parse('$url/rest/v1/orders'),
    headers: BH,
    body: jsonEncode({
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'product_id': pid,
      'status': 'reserva_pendente',
      'quantity': 1,
      'price_total': 5.0,
      'shipping_method': 'hand',
      'payment_method': 'Pagamento na app',
    }),
  );
  final oid = (jsonDecode(ord.body) as List).first['id'] as String;
  await http.patch(
    Uri.parse('$url/rest/v1/orders?id=eq.$oid'),
    headers: SVC,
    body: jsonEncode({
      'contract_unit_cents': 500,
      'contract_qty': 1,
      'shipping_method': 'hand',
    }),
  );
  final cpi = await http.post(
    Uri.parse('$url/functions/v1/create-payment-intent'),
    headers: BH,
    body: jsonEncode({
      'buyer_id': buyerId,
      'order_id': oid,
      'shipping_method': 'hand',
    }),
  );
  final body = jsonDecode(cpi.body) as Map<String, dynamic>;
  final out = {
    'order_id': oid,
    'product_id': pid,
    'checkoutUrl': body['checkoutUrl'],
    'checkoutSessionId': body['checkoutSessionId'],
    'server_amount_cents': body['server_amount_cents'],
    'supabase_url': url,
    'anon': anon,
  };
  final path = 'tool/reports/sec_s2_p0_settle_setup_$stamp.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln(jsonEncode(out));
  stdout.writeln('WROTE $path');
}
