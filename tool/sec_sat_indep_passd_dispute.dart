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
  final crash = e['FLEABER_STAGING_CRASH_INJECT_SECRET']!;
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyer = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final seller = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  Map<String, String> h(String t) => {
        'apikey': anon,
        'Authorization': 'Bearer $t',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  Map<String, String> hs() => {
        'apikey': svc,
        'Authorization': 'Bearer $svc',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  final paid = await http.post(
    Uri.parse('$url/functions/v1/sec-fase2-e2e-oversell'),
    headers: {
      ...hs(),
      'x-fleaber-e2e-secret': crash,
    },
    body: jsonEncode({
      'probe': 'setup_paid_order',
      'buyer_id': buyerId,
      'seller_id': sellerId,
    }),
  );
  final body = jsonDecode(paid.body) as Map;
  final oid = body['order_id'];
  print('oid=$oid');
  await http.patch(Uri.parse('$url/rest/v1/orders?id=eq.$oid'),
      headers: h(seller), body: jsonEncode({'status': 'enviado'}));
  await http.patch(Uri.parse('$url/rest/v1/orders?id=eq.$oid'),
      headers: h(buyer), body: jsonEncode({'status': 'concluido'}));

  Future<void> tryIns(String who, String tok, Map row) async {
    final r = await http.post(Uri.parse('$url/rest/v1/order_disputes'),
        headers: h(tok), body: jsonEncode(row));
    print('INS $who ${r.statusCode} ${r.body}');
  }

  await tryIns('buyer', buyer, {
    'order_id': oid,
    'buyer_id': buyerId,
    'reason': 'outro',
    'description': 'satd',
  });
  await tryIns('buyer-pct', buyer, {
    'order_id': oid,
    'buyer_id': buyerId,
    'reason': 'danificado',
    'description': 'satd',
    'seller_refund_percent': 100,
    'status': 'aceite',
  });
  await tryIns('seller', seller, {
    'order_id': oid,
    'buyer_id': buyerId,
    'reason': 'outro',
    'description': 'seller forged',
  });

  final list = await http.get(
    Uri.parse('$url/rest/v1/order_disputes?order_id=eq.$oid&select=*'),
    headers: h(buyer),
  );
  print('LIST ${list.statusCode} ${list.body}');
  if (list.body.contains('"id"')) {
    final id = (jsonDecode(list.body) as List).first['id'];
    final sp = await http.patch(
      Uri.parse('$url/rest/v1/order_disputes?id=eq.$id'),
      headers: h(seller),
      body: jsonEncode({'seller_refund_percent': 100, 'seller_offer_type': 'refund'}),
    );
    print('SELLER PATCH ${sp.statusCode} ${sp.body}');
    final bp = await http.patch(
      Uri.parse('$url/rest/v1/order_disputes?id=eq.$id'),
      headers: h(buyer),
      body: jsonEncode({'seller_refund_percent': 1}),
    );
    print('BUYER PATCH pct ${bp.statusCode} ${bp.body}');
  }

  await http.post(Uri.parse('$url/functions/v1/refund-order'),
      headers: h(seller), body: jsonEncode({'order_id': oid}));
  await http.delete(Uri.parse('$url/rest/v1/order_disputes?order_id=eq.$oid'),
      headers: hs());
  await http.delete(Uri.parse('$url/rest/v1/orders?id=eq.$oid'), headers: hs());
  if (body['product_id'] != null) {
    await http.delete(
        Uri.parse('$url/rest/v1/products?id=eq.${body['product_id']}'),
        headers: hs());
  }
}
