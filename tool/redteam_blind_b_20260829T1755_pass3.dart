// dart run tool/redteam_blind_b_20260829T1755_pass3.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

const stamp = '20260829T1755';
const stagingRef = 'fxdknzrqjenzqcvnwqqq';
typedef Json = Map<String, dynamic>;

final findings = <Json>[];
final probes = <Json>[];

Json snap(http.Response r, {int max = 800}) {
  var b = r.body;
  if (b.length > max) b = '${b.substring(0, max)}…';
  return {'status': r.statusCode, 'body': b};
}

Future<http.Response> rest(
  String url,
  String key,
  String bearer, {
  String method = 'GET',
  required String path,
  Object? body,
}) {
  final h = {
    'apikey': key,
    'Authorization': 'Bearer $bearer',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final uri = Uri.parse('$url$path');
  if (method == 'POST') return http.post(uri, headers: h, body: jsonEncode(body));
  if (method == 'PATCH') return http.patch(uri, headers: h, body: jsonEncode(body));
  return http.get(uri, headers: h);
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(stagingRef)) throw StateError('not staging');
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final client = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
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

  // Surviving offer-reuse orders from pass2 (may have been cleaned)
  const offerOrders = [
    'dfba40f6-e14b-46ff-89fc-c7cf486cd4d1',
    'ecc3b712-e310-4610-b699-01aa6426e5aa',
  ];
  const paidMb = 'd8abac50-bbc1-4160-8cab-16363382b794';
  const productId = '1f12cda0-6a92-4d7b-839c-51b87ddeff98';

  final prod = await rest(
    url,
    svc,
    svc,
    path: '/rest/v1/products?id=eq.$productId&select=id,quantity,is_sold',
  );
  probes.add({'id': 'p3.product', ...snap(prod)});

  for (final oid in offerOrders) {
    final row = await rest(
      url,
      svc,
      svc,
      path:
          '/rest/v1/orders?id=eq.$oid&select=id,status,price_total,contract_unit_cents,stock_units_applied,product_offer_id',
    );
    probes.add({'id': 'p3.offer_order.$oid', ...snap(row)});
    final pago = await rest(
      url,
      anon,
      sellerJwt,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$oid',
      body: {'status': 'pago'},
    );
    probes.add({'id': 'p3.second_pago.$oid', ...snap(pago)});
  }

  final prodAfter = await rest(
    url,
    svc,
    svc,
    path: '/rest/v1/products?id=eq.$productId&select=id,quantity,is_sold',
  );
  probes.add({'id': 'p3.product_after_pagos', ...snap(prodAfter)});

  // Checkout an offer-order after stock 0
  for (final oid in offerOrders) {
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
      }),
    );
    probes.add({'id': 'p3.ck_after_stock.$oid', ...snap(ck)});
  }

  // live_messages of live buyer does not own
  final lm = await rest(
    url,
    anon,
    buyerJwt,
    path:
        '/rest/v1/live_messages?select=id,live_id,sender_label,body,channel&live_id=eq.cf880adf-ea1e-42d2-946b-2214c264fd16&limit=3',
  );
  probes.add({'id': 'p3.live_msg_foreign', ...snap(lm)});
  if (lm.statusCode == 200 && lm.body.contains('sender_label') && lm.body.contains('"id"')) {
    findings.add({
      'id': 'RTB-B-1755-P2-LIVE-MSG',
      'title': 'Buyer lê live_messages (nomes Facebook) de live alheia',
      'severity': 'P2',
      'actor': 'buyer JWT',
      'preconditions': 'live_id conhecido',
      'request': 'GET live_messages?live_id=eq.{id}',
      'result': snap(lm),
      'impact': 'comentários OCR/Facebook de terceiros visíveis a qualquer autenticado',
      'reproduction': 'SELECT live_messages por live_id sem ser vendedor/viewer da sessão',
    });
  }

  // Reviews of others
  final rev = await rest(
    url,
    anon,
    buyerJwt,
    path: '/rest/v1/reviews?buyer_id=neq.$buyerId&select=id,buyer_id,target_id,stars,comment,order_id&limit=5',
  );
  probes.add({'id': 'p3.reviews_cross', ...snap(rev)});

  // chats schema
  final chats = await rest(url, anon, buyerJwt, path: '/rest/v1/chats?select=*&limit=2');
  probes.add({'id': 'p3.chats', ...snap(chats)});

  // Confirm offer still accepted after N orders
  final offers = await rest(
    url,
    svc,
    svc,
    path:
        '/rest/v1/product_offers?id=eq.e1f1eae0-8dd5-4cb5-ad7a-0cdb18bcfb92&select=id,status,amount,product_id',
  );
  probes.add({'id': 'p3.offer_still', ...snap(offers)});

  // New order still binds leftover offer?
  final freshP = await rest(
    url,
    anon,
    sellerJwt,
    method: 'POST',
    path: '/rest/v1/products',
    body: {
      'seller_id': sellerId,
      'title': 'RTB-B-p3 leftover-offer',
      'price': 20.0,
      'quantity': 3,
      'is_sold': false,
      'list_on_marketplace': true,
    },
  );
  probes.add({'id': 'p3.fresh_product', ...snap(freshP)});
  String? pid;
  try {
    pid = ((jsonDecode(freshP.body) as List).first as Json)['id']?.toString();
  } catch (_) {}
  if (pid != null) {
    final off = await rest(
      url,
      anon,
      buyerJwt,
      method: 'POST',
      path: '/rest/v1/product_offers',
      body: {
        'product_id': pid,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'amount': 2.0,
        'offered_by': 'buyer',
      },
    );
    probes.add({'id': 'p3.new_offer', ...snap(off)});
    String? oid;
    try {
      oid = ((jsonDecode(off.body) as List).first as Json)['id']?.toString();
    } catch (_) {}
    if (oid != null) {
      await rest(
        url,
        anon,
        sellerJwt,
        method: 'PATCH',
        path: '/rest/v1/product_offers?id=eq.$oid',
        body: {
          'status': 'accepted',
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      final o1 = await rest(
        url,
        anon,
        buyerJwt,
        method: 'POST',
        path: '/rest/v1/orders',
        body: {
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'product_id': pid,
          'quantity': 1,
          'price_total': 20,
          'payment_method': 'Pagamento na app',
          'shipping_method': 'hand',
        },
      );
      final o2 = await rest(
        url,
        anon,
        buyerJwt,
        method: 'POST',
        path: '/rest/v1/orders',
        body: {
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'product_id': pid,
          'quantity': 1,
          'price_total': 20,
          'payment_method': 'Pagamento na app',
          'shipping_method': 'hand',
        },
      );
      probes.add({'id': 'p3.bind_o1', ...snap(o1)});
      probes.add({'id': 'p3.bind_o2', ...snap(o2)});
      try {
        final a = (jsonDecode(o1.body) as List).first as Json;
        final b = (jsonDecode(o2.body) as List).first as Json;
        if (a['contract_unit_cents'] == 200 && b['contract_unit_cents'] == 200) {
          findings.add({
            'id': 'RTB-B-1755-P1-OFFER-MULTI-BIND',
            'title': 'Oferta aceite liga-se a N orders seguintes (não é one-shot)',
            'severity': 'P1',
            'actor': 'buyer JWT',
            'preconditions': 'product_offers accepted; product qty=3 price=20',
            'request': '2x POST /orders sem product_offer_id após aceite de 2.00€',
            'before': {'list_price_cents': 2000, 'offer_cents': 200},
            'result': {
              'o1': {'id': a['id'], 'contract_unit_cents': a['contract_unit_cents'], 'offer': a['product_offer_id']},
              'o2': {'id': b['id'], 'contract_unit_cents': b['contract_unit_cents'], 'offer': b['product_offer_id']},
            },
            'after': {'both_contract_cents': 200},
            'impact': 'desconto de proposta reutilizável; checkout cobra 2€+taxas em vez de 20€ por unidade',
            'reproduction': 'aceitar oferta; criar duas orders novas do mesmo SKU sem reenviar offer id',
          });
        }
      } catch (_) {}
      try {
        await client.deleteWhere('orders', 'product_id=eq.$pid');
        await client.deleteWhere('product_offers', 'id=eq.$oid');
        await client.deleteWhere('products', 'id=eq.$pid');
      } catch (_) {}
    }
  }

  final paid = await rest(
    url,
    svc,
    svc,
    path: '/rest/v1/orders?id=eq.$paidMb&select=id,status,stock_units_applied,amount_paid_cents',
  );
  probes.add({'id': 'p3.paid_mb_observe', ...snap(paid)});

  File('tool/redteam_blind_b_${stamp}_pass3.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'pass': 3,
      'frozen_at': DateTime.now().toUtc().toIso8601String(),
      'findings': findings,
      'probes': probes,
    }),
  );
  stdout.writeln('pass3 findings=${findings.length}');
}
