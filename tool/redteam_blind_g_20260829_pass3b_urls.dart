// ignore_for_file: avoid_print
/// Recreate stock=1 dual sessions; write FULL checkout URLs.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
]) async {
  final r = method == 'POST'
      ? await http.post(Uri.parse(u), headers: h, body: jsonEncode(body))
      : method == 'GET'
          ? await http.get(Uri.parse(u), headers: h)
          : await http.patch(Uri.parse(u), headers: h, body: jsonEncode(body));
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return '${(body.first as Map)['id']}';
  }
  if (body is Map) return '${body['id']}';
  return null;
}

Future<void> main() async {
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

  // cancel leftover race product sessions by deleting old orders/product
  await req('DELETE', '$url/rest/v1/orders?product_id=eq.b510dd28-0ec0-40e0-8990-005ac32537d1', SVC);
  await req('DELETE', '$url/rest/v1/products?id=eq.b510dd28-0ec0-40e0-8990-005ac32537d1', SVC);

  final tag = DateTime.now().millisecondsSinceEpoch;
  final prod = await req('POST', '$url/rest/v1/products', SH, {
    'seller_id': sellerId,
    'title': 'RTG3b race $tag',
    'price': 5.00,
    'quantity': 1,
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final pid = idOf(prod['body']);
  stdout.writeln('product=$pid http=${prod['http']}');
  if (pid == null) {
    stdout.writeln(prod['text']);
    exit(1);
  }

  Future<String?> order() async {
    final o = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'price_total': 5,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'pagamento na app (seguro fleaber)',
      'shipping_method': 'hand',
    });
    return idOf(o['body']);
  }

  final ida = await order();
  final idb = await order();
  stdout.writeln('orders $ida $idb');

  Future<Map<String, dynamic>> cpi(String oid) async {
    return req('POST', '$url/functions/v1/create-payment-intent', BH, {
      'order_id': oid,
      'buyer_id': buyerId,
      'shipping_method': 'hand',
    });
  }

  final ca = await cpi(ida!);
  final cb = await cpi(idb!);
  Map<String, dynamic> parse(Map<String, dynamic> r) {
    final m = r['body'] is Map ? Map<String, dynamic>.from(r['body'] as Map) : <String, dynamic>{};
    return {
      'http': r['http'],
      'checkoutUrl': m['checkoutUrl'],
      'checkoutUrl_len': '${m['checkoutUrl'] ?? ''}'.length,
      'checkoutSessionId': m['checkoutSessionId'],
      'server_amount_cents': m['server_amount_cents'],
      'amount_total': m['amount_total'],
    };
  }

  final out = {
    'product_id': pid,
    'order_a': ida,
    'order_b': idb,
    'a': parse(ca),
    'b': parse(cb),
  };
  File('tool/redteam_blind_g_20260829/pass3b_full_urls.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('A url_len=${out['a']}');
  stdout.writeln('B session=${(out['b'] as Map)['checkoutSessionId']} len=${(out['b'] as Map)['checkoutUrl_len']}');
}
