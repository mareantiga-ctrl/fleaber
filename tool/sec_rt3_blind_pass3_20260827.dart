/// RT3 pass 3 — composição / variantes. Staging only. Sem correcções.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const tag = 'RT3P3';

typedef Json = Map<String, dynamic>;

String clip(Object? o, [int n = 400]) {
  final s = o is String ? o : jsonEncode(o);
  return s.length <= n ? s : '${s.substring(0, n)}…';
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!base.contains(stagingRef)) {
    stderr.writeln('ABORT');
    exit(2);
  }
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final c = LiveOpsStagingClient(
    url: base,
    anonKey: anon,
    serviceRoleKey: service,
  );
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

  Future<http.Response> rest(
    String method,
    String path, {
    required Map<String, String> h,
    Object? body,
  }) async {
    final uri = Uri.parse('$base/rest/v1/$path');
    final b = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'GET':
        return http.get(uri, headers: h);
      case 'POST':
        return http.post(uri, headers: h, body: b);
      case 'PATCH':
        return http.patch(uri, headers: h, body: b);
      case 'DELETE':
        return http.delete(uri, headers: h);
      default:
        throw StateError(method);
    }
  }

  Future<http.Response> edge(Object body, {String tok = ''}) => http.post(
        Uri.parse('$base/functions/v1/create-payment-intent'),
        headers: hu(tok.isEmpty ? buyerTok : tok),
        body: jsonEncode(body),
      );

  Future<Json?> svc(String table, String filter) async {
    final r = await rest('GET', '$table?$filter&limit=1', h: hs());
    final j = jsonDecode(r.body);
    if (j is List && j.isNotEmpty) return Map<String, dynamic>.from(j.first as Map);
    return null;
  }

  final out = <String, Object?>{};
  final createdP = <String>[];
  final createdO = <String>[];

  Future<Json> product(double price, int qty, String title) async {
    final r = await rest('POST', 'products', h: hu(sellerTok), body: {
      'seller_id': sellerId,
      'title': title,
      'price': price,
      'quantity': qty,
      'list_on_marketplace': true,
      'description': '$tag fixture',
    });
    final row = Map<String, dynamic>.from((jsonDecode(r.body) as List).first as Map);
    createdP.add(row['id'].toString());
    return row;
  }

  Future<http.Response> order({
    required String pid,
    required String pay,
    int qty = 1,
    Object? extra,
  }) async {
    final body = {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': qty,
      'status': 'reserva_pendente',
      'payment_method': pay,
      'shipping_method': 'entrega em mao',
      'price_total': 10.0,
      if (extra is Map) ...Map<String, dynamic>.from(extra),
    };
    final r = await rest('POST', 'orders', h: hu(buyerTok), body: body);
    if (r.statusCode < 300) {
      createdO.add(((jsonDecode(r.body) as List).first as Map)['id'].toString());
    }
    return r;
  }

  // 1) prize_shipping on normal order
  final p1 = await product(10, 2, '$tag prize-spoof');
  final o1 = await order(pid: p1['id'].toString(), pay: 'seguro fleaber');
  final oid1 = ((jsonDecode(o1.body) as List).first as Map)['id'].toString();
  final prize = await edge({
    'buyer_id': buyerId,
    'order_id': oid1,
    'shipping_method': 'carrier',
    'prize_shipping': true,
  });
  out['prize_shipping_normal'] = {'http': prize.statusCode, 'body': clip(prize.body)};

  // 2) bag two sellers — second product from another seller if buyer can order it
  final other = await rest(
    'GET',
    'products?select=id,seller_id,price,quantity&seller_id=neq.$sellerId&list_on_marketplace=eq.true&quantity=gt.0&limit=1',
    h: hs(),
  );
  out['other_product'] = clip(other.body, 200);
  String? oidOther;
  if (other.statusCode == 200) {
    final list = jsonDecode(other.body);
    if (list is List && list.isNotEmpty) {
      final op = list.first as Map;
      final ox = await rest('POST', 'orders', h: hu(buyerTok), body: {
        'buyer_id': buyerId,
        'seller_id': op['seller_id'],
        'product_id': op['id'],
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'seguro fleaber',
        'shipping_method': 'entrega em mao',
        'price_total': 10.0,
      });
      out['order_other_seller'] = {'http': ox.statusCode, 'body': clip(ox.body, 180)};
      if (ox.statusCode < 300) {
        oidOther = ((jsonDecode(ox.body) as List).first as Map)['id'].toString();
        createdO.add(oidOther);
      }
    }
  }
  if (oidOther != null) {
    final bagMs = await edge({
      'buyer_id': buyerId,
      'order_id': oid1,
      'shipping_method': 'hand',
      'bag_checkout': true,
      'bag_lines': [
        {'order_id': oid1},
        {'order_id': oidOther},
      ],
    });
    out['bag_multi_seller'] = {'http': bagMs.statusCode, 'body': clip(bagMs.body)};
  }

  // 3) offer-sealed checkout
  final pOff = await product(20, 3, '$tag offer-chk');
  final off = await rest('POST', 'product_offers', h: hu(buyerTok), body: {
    'product_id': pOff['id'],
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 2.00,
    'offered_by': 'buyer',
    'status': 'pending',
  });
  String? offId;
  if (off.statusCode < 300) {
    offId = ((jsonDecode(off.body) as List).first as Map)['id'].toString();
    await rest('PATCH', 'product_offers?id=eq.$offId', h: hu(sellerTok), body: {
      'status': 'accepted',
    });
  }
  final oOff = await order(
    pid: pOff['id'].toString(),
    pay: 'seguro fleaber',
    extra: {if (offId != null) 'product_offer_id': offId},
  );
  out['offer_order'] = {'http': oOff.statusCode, 'body': clip(oOff.body, 350)};
  if (oOff.statusCode < 300) {
    final oo = (jsonDecode(oOff.body) as List).first as Map;
    final chk = await edge({
      'buyer_id': buyerId,
      'order_id': oo['id'],
      'shipping_method': 'hand',
      'amount': 2000,
    });
    out['offer_checkout'] = {
      'http': chk.statusCode,
      'body': clip(chk.body),
      'contract_unit': oo['contract_unit_cents'],
    };
  }

  // 4) MB WAY pago then wallet release + review + refund-order
  final pMb = await product(8, 1, '$tag mb-release');
  final oMb = await order(pid: pMb['id'].toString(), pay: 'mb way');
  final oidMb = ((jsonDecode(oMb.body) as List).first as Map)['id'].toString();
  final pago = await rest('PATCH', 'orders?id=eq.$oidMb', h: hu(sellerTok), body: {
    'status': 'pago',
  });
  out['mb_pago'] = {'http': pago.statusCode, 'body': clip(pago.body, 200)};
  final wBefore = await svc('wallets', 'id=eq.$sellerId&select=id,balance');
  final rel = await rest(
    'POST',
    'rpc/batata_release_seller_wallet_for_order',
    h: hu(buyerTok),
    body: {'p_order_id': oidMb},
  );
  final wAfter = await svc('wallets', 'id=eq.$sellerId&select=id,balance');
  out['mb_release'] = {
    'http': rel.statusCode,
    'body': clip(rel.body),
    'wallet_before': wBefore,
    'wallet_after': wAfter,
  };

  await rest('PATCH', 'orders?id=eq.$oidMb', h: hu(sellerTok), body: {
    'status': 'enviado',
  });
  final conc = await rest('PATCH', 'orders?id=eq.$oidMb', h: hu(buyerTok), body: {
    'status': 'concluido',
  });
  out['mb_concluido'] = {
    'http': conc.statusCode,
    'after': await svc('orders', 'id=eq.$oidMb&select=id,status'),
  };

  final rev = await rest('POST', 'reviews', h: hu(buyerTok), body: {
    'buyer_id': buyerId,
    'target_id': sellerId,
    'order_id': oidMb,
    'stars': 5,
    'comment': '$tag mbway review',
    'author_role': 'vendedor',
  });
  out['mb_review'] = {'http': rev.statusCode, 'body': clip(rev.body, 300)};
  final wRev = await svc('wallets', 'id=eq.$sellerId&select=id,balance');
  out['wallet_after_review'] = wRev;

  final rel2 = await rest(
    'POST',
    'rpc/batata_release_seller_wallet_for_order',
    h: hu(buyerTok),
    body: {'p_order_id': oidMb},
  );
  out['mb_release_after_concluido'] = {
    'http': rel2.statusCode,
    'body': clip(rel2.body),
    'wallet': await svc('wallets', 'id=eq.$sellerId&select=id,balance'),
  };

  final ref = await http.post(
    Uri.parse('$base/functions/v1/refund-order'),
    headers: hu(sellerTok),
    body: jsonEncode({'order_id': oidMb}),
  );
  out['mb_refund_seller'] = {'http': ref.statusCode, 'body': clip(ref.body)};

  // 5) review unpaid with stars
  final pU = await product(9, 1, '$tag unpaid-rev');
  final oU = await order(pid: pU['id'].toString(), pay: 'seguro fleaber');
  final oidU = ((jsonDecode(oU.body) as List).first as Map)['id'].toString();
  final revU = await rest('POST', 'reviews', h: hu(buyerTok), body: {
    'buyer_id': buyerId,
    'target_id': sellerId,
    'order_id': oidU,
    'stars': 5,
    'comment': '$tag unpaid',
  });
  out['unpaid_review'] = {'http': revU.statusCode, 'body': clip(revU.body, 250)};

  // 6) hub views anon
  final hubLives = await http.get(
    Uri.parse('$base/rest/v1/hub_lives_public?select=id,status,mux_playback_id&limit=2'),
    headers: {'apikey': anon, 'Authorization': 'Bearer $anon'},
  );
  out['anon_hub_lives'] = {'http': hubLives.statusCode, 'body': clip(hubLives.body, 250)};
  final hubRev = await http.get(
    Uri.parse('$base/rest/v1/hub_reviews_public?select=*&limit=3'),
    headers: {'apikey': anon, 'Authorization': 'Bearer $anon'},
  );
  out['anon_hub_reviews'] = {'http': hubRev.statusCode, 'body': clip(hubRev.body, 250)};

  // cleanup
  for (final id in createdO.reversed) {
    await rest('DELETE', 'orders?id=eq.$id', h: hs());
  }
  for (final id in createdP.reversed) {
    await rest('PATCH', 'products?id=eq.$id', h: hs(), body: {
      'list_on_marketplace': false,
      'title': '$tag CLEANED',
      'quantity': 0,
    });
  }

  File('tool/reports/RT3_BLIND_PASS3_20260827.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'frozen_at': DateTime.now().toUtc().toIso8601String(),
      'out': out,
    }),
  );
  stdout.writeln(jsonEncode(out));
}
