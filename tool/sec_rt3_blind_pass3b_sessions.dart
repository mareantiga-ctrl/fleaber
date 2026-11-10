/// RT3 pass 3b — duas Sessions vs 1 unidade. Staging. Sem correcções.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

void main() async {
  final env = loadLiveOpsStagingEnv();
  final base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!base.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT');
    exit(2);
  }
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final c = LiveOpsStagingClient(url: base, anonKey: anon, serviceRoleKey: service);
  final buyerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerId = await c.userIdForAccessToken(buyerTok);
  final sellerId = await c.userIdForAccessToken(sellerTok);
  Map<String, String> hu(String t) => {
        'apikey': anon,
        'Authorization': 'Bearer $t',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  Map<String, String> hs() => {
        'apikey': service,
        'Authorization': 'Bearer $service',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  final p = await http.post(Uri.parse('$base/rest/v1/products'), headers: hu(sellerTok), body: jsonEncode({
    'seller_id': sellerId,
    'title': 'RT3P3B last-unit sessions',
    'price': 6.0,
    'quantity': 1,
    'list_on_marketplace': true,
  }));
  final pid = ((jsonDecode(p.body) as List).first as Map)['id'];
  Future<String> mkOrder() async {
    final r = await http.post(Uri.parse('$base/rest/v1/orders'), headers: hu(buyerTok), body: jsonEncode({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'seguro fleaber',
      'shipping_method': 'entrega em mao',
      'price_total': 6.0,
    }));
    stdout.writeln('order ${r.statusCode} ${r.body.substring(0, r.body.length.clamp(0, 180))}');
    return ((jsonDecode(r.body) as List).first as Map)['id'].toString();
  }

  final a = await mkOrder();
  final b = await mkOrder();
  Future<http.Response> chk(String oid) => http.post(
        Uri.parse('$base/functions/v1/create-payment-intent'),
        headers: hu(buyerTok),
        body: jsonEncode({
          'buyer_id': buyerId,
          'order_id': oid,
          'shipping_method': 'hand',
        }),
      );
  final c1 = await chk(a);
  final c2 = await chk(b);
  stdout.writeln('c1 ${c1.statusCode} ${c1.body}');
  stdout.writeln('c2 ${c2.statusCode} ${c2.body}');
  final parallel = await Future.wait([chk(a), chk(b)]);
  stdout.writeln('par0 ${parallel[0].statusCode} ${parallel[0].body}');
  stdout.writeln('par1 ${parallel[1].statusCode} ${parallel[1].body}');

  await http.delete(Uri.parse('$base/rest/v1/orders?id=eq.$a'), headers: hs());
  await http.delete(Uri.parse('$base/rest/v1/orders?id=eq.$b'), headers: hs());
  await http.patch(Uri.parse('$base/rest/v1/products?id=eq.$pid'), headers: hs(), body: jsonEncode({
    'list_on_marketplace': false,
    'title': 'RT3P3B CLEANED',
  }));
}
