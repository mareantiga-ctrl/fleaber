// Independent blind Red Team — PASS 2 variants / money / races.
// Staging only. No production. No Fase 4. No fixes.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

const stamp = 'RTI1606P2';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

late String url, anon, svc, buyerId, sellerId, buyerJwt, sellerJwt, helperId, helperJwt;
late LiveOpsStagingClient admin;
final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];
final races = <Map<String, dynamic>>[];
final stripe = <Map<String, dynamic>>[];

void rec(String surface, String attack, String ident, String result, {String sev = 'info', Object? ev}) {
  matrix.add({
    'surface': surface,
    'attack': attack,
    'identity': ident,
    'result': result.length > 2000 ? '${result.substring(0, 2000)}…' : result,
    'severity': sev,
    if (ev != null) 'evidence': ev,
  });
}

void finding({
  required String id,
  required String sev,
  required String title,
  required String actor,
  required String pre,
  required String repro,
  required String impact,
}) {
  findings.add({
    'id': id,
    'severity': sev,
    'title': title,
    'actor': actor,
    'preconditions': pre,
    'reproduction': repro,
    'impact': impact,
    'estado': 'OPEN',
  });
}

Map<String, String> h(String? jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer ${jwt ?? anon}',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Future<http.Response> rest(String method, String path, {String? jwt, Object? body}) async {
  final uri = Uri.parse('$url$path');
  final headers = h(jwt);
  final enc = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      return http.get(uri, headers: headers);
    case 'POST':
      return http.post(uri, headers: headers, body: enc);
    case 'PATCH':
      return http.patch(uri, headers: headers, body: enc);
    case 'DELETE':
      return http.delete(uri, headers: headers, body: enc);
    default:
      throw ArgumentError(method);
  }
}

Future<http.Response> rpc(String fn, Map<String, dynamic> p, {String? jwt}) =>
    rest('POST', '/rest/v1/rpc/$fn', jwt: jwt, body: p);

Future<http.Response> edge(String fn, {String? jwt, Object? body, String method = 'POST', String qs = ''}) async {
  final headers = h(jwt);
  final uri = Uri.parse('$url/functions/v1/$fn$qs');
  if (method == 'GET') return http.get(uri, headers: headers);
  return http.post(uri, headers: headers, body: body == null ? null : jsonEncode(body));
}

String brief(http.Response r) {
  var b = r.body.replaceAll(RegExp(r'\s+'), ' ');
  if (b.length > 280) b = '${b.substring(0, 280)}…';
  return '${r.statusCode} $b';
}

bool ok2(int s) => s >= 200 && s < 300;

Map<String, dynamic>? rowOf(http.Response r) {
  if (!ok2(r.statusCode) || r.body.isEmpty || r.body == '[]') return null;
  final p = jsonDecode(r.body);
  if (p is List && p.isNotEmpty) return Map<String, dynamic>.from(p.first as Map);
  if (p is Map) return Map<String, dynamic>.from(p);
  return null;
}

Future<Map<String, dynamic>> observeOrder(String id) async {
  final rows = await admin.select(
    'orders',
    filter: 'id=eq.$id',
    limit: 1,
  );
  if (rows.isEmpty) return {};
  final o = rows.first;
  return {
    'id': o['id'],
    'status': o['status'],
    'price_total': o['price_total'],
    'qty': o['quantity'],
    'contract_unit_cents': o['contract_unit_cents'],
    'contract_qty': o['contract_qty'],
    'amount_paid_cents': o['amount_paid_cents'],
    'pi': o['stripe_payment_intent_id'],
    'cs': o['stripe_checkout_session_id'],
    'refund': o['stripe_refund_id'],
    'pm': o['payment_method'],
    'ship': o['shipping_method'],
    'buyer': o['buyer_id'],
    'seller': o['seller_id'],
    'wallet_release': o['wallet_release_processed_at'],
    'wallet_refund': o['wallet_refund_processed_at'],
  };
}

Future<Map<String, dynamic>> observeProduct(String id) async {
  final rows = await admin.select('products', filter: 'id=eq.$id', limit: 1);
  if (rows.isEmpty) return {};
  final p = rows.first;
  return {'id': p['id'], 'qty': p['quantity'], 'price': p['price'], 'sold': p['is_sold']};
}

Future<num> walletOf(String uid) async {
  final rows = await admin.select('wallets', filter: 'id=eq.$uid', limit: 1);
  if (rows.isEmpty) return 0;
  return num.tryParse('${rows.first['balance']}') ?? 0;
}

Future<Map<String, dynamic>> insertProduct({
  required num price,
  required int qty,
  String? title,
}) {
  return admin.insert('products', {
    'seller_id': sellerId,
    'title': title ?? '$stamp ${DateTime.now().millisecondsSinceEpoch}',
    'price': price,
    'quantity': qty,
    'ref_code': '$stamp-${Random().nextInt(1 << 20)}',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': [],
  });
}

Future<http.Response> insertOrder({
  required String jwt,
  required String pid,
  required String buyer,
  required String seller,
  num price = 0,
  int qty = 1,
  String status = 'reserva_pendente',
  String pm = 'Pagamento na app',
  String ship = 'entrega em mão',
  Object? extra,
}) {
  final row = <String, dynamic>{
    'buyer_id': buyer,
    'seller_id': seller,
    'product_id': pid,
    'price_total': price,
    'quantity': qty,
    'status': status,
    'payment_method': pm,
    'shipping_method': ship,
    if (extra is Map) ...extra,
  };
  return rest('POST', '/rest/v1/orders', jwt: jwt, body: row);
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) {
    stderr.writeln('REFUSED');
    exit(2);
  }
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  admin = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  buyerJwt = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  sellerJwt = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  final helperEmail =
      'rti1606p2-${DateTime.now().millisecondsSinceEpoch}@fleaber.invalid';
  helperId = await admin.createAdminUser(
    email: helperEmail,
    password: 'Rti1606!Help#x',
  );
  helperJwt = await admin.signIn(email: helperEmail, password: 'Rti1606!Help#x');
  Directory('tool/redteam_blind_indep_20260830T1606/out').createSync(recursive: true);
  stdout.writeln('PASS2 auth ok helper=$helperId');

  await openApiService();
  await paymentMethodSwapAndMbway();
  await checkoutAuthority();
  await stockRace();
  await dualCheckoutRace();
  await reviewsAndDisputes();
  await offers();
  await bankingOracle();
  await chatCrossUser();
  await liveReservation();
  await payoutRetry();
  await storageBuckets();
  await sellerAmountPaid();
  await rpcGrantSweep();

  final payload = {
    'pass': 2,
    'project': projectMust,
    'at': DateTime.now().toUtc().toIso8601String(),
    'matrix': matrix,
    'findings': findings,
    'races': races,
    'stripe': stripe,
  };
  File('tool/redteam_blind_indep_20260830T1606/out/pass2.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(payload),
  );
  stdout.writeln(
    'PASS2 done matrix=${matrix.length} findings=${findings.length} races=${races.length}',
  );
}

Future<void> openApiService() async {
  final r = await http.get(
    Uri.parse('$url/rest/v1/'),
    headers: {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
      'Accept': 'application/openapi+json',
    },
  );
  rec('openapi', 'GET service_role', 'svc', '${r.statusCode} len=${r.body.length}');
  if (!ok2(r.statusCode)) return;
  final spec = jsonDecode(r.body) as Map<String, dynamic>;
  final paths = spec['paths'] as Map<String, dynamic>? ?? {};
  final rpcs = <String>[];
  final tables = <String>[];
  for (final p in paths.keys) {
    if (p.startsWith('/rpc/')) {
      rpcs.add(p.substring(5));
    } else if (p.startsWith('/') && p.length > 1) {
      tables.add(p.substring(1));
    }
  }
  rpcs.sort();
  tables.sort();
  File('tool/redteam_blind_indep_20260830T1606/out/openapi_rpcs.json').writeAsStringSync(
    jsonEncode({'rpcs': rpcs, 'tables': tables, 'rpc_count': rpcs.length, 'table_count': tables.length}),
  );
  rec('openapi', 'inventory', 'svc', 'rpcs=${rpcs.length} tables=${tables.length}');
}

Future<void> paymentMethodSwapAndMbway() async {
  final prod = await insertProduct(price: 18, qty: 2);
  final pid = prod['id'].toString();
  final wSeller0 = await walletOf(sellerId);
  final wBuyer0 = await walletOf(buyerId);

  final o1 = await insertOrder(
    jwt: buyerJwt,
    pid: pid,
    buyer: buyerId,
    seller: sellerId,
    price: 18,
    pm: 'Pagamento na app',
  );
  rec('orders', 'INSERT stripe pm', 'buyer', brief(o1));
  final id1 = rowOf(o1)?['id']?.toString();
  if (id1 != null) {
    final swap = await rest('PATCH', '/rest/v1/orders?id=eq.$id1', jwt: buyerJwt, body: {
      'payment_method': 'MB WAY',
    });
    rec('orders', 'buyer PATCH pm→MB WAY', 'buyer', brief(swap));
    final afterSwap = await observeOrder(id1);
    rec('orders', 'observe pm after swap', 'svc', jsonEncode(afterSwap));
    if ('${afterSwap['pm']}'.toLowerCase().contains('mb')) {
      finding(
        id: 'P1-PM-SWAP-STRIPE-TO-MBWAY',
        sev: 'P1',
        title: 'Buyer changed Stripe order to MB WAY',
        actor: 'buyer',
        pre: 'Own reserva_pendente Pagamento na app',
        repro: 'PATCH payment_method=MB WAY persisted ${afterSwap['pm']}',
        impact: 'Seller can then attest pago without Stripe capture',
      );
      final sellerPago = await rest('PATCH', '/rest/v1/orders?id=eq.$id1', jwt: sellerJwt, body: {
        'status': 'pago',
      });
      rec('orders', 'seller PATCH pago after pm swap', 'seller', brief(sellerPago));
      rec('orders', 'observe after seller pago', 'svc', jsonEncode(await observeOrder(id1)));
    }

    final sellerSwap = await rest('PATCH', '/rest/v1/orders?id=eq.$id1', jwt: sellerJwt, body: {
      'payment_method': 'MB WAY',
    });
    rec('orders', 'seller PATCH pm→MB WAY', 'seller', brief(sellerSwap));
    rec('orders', 'observe pm seller swap', 'svc', jsonEncode(await observeOrder(id1)));
  }

  final prod2 = await insertProduct(price: 22, qty: 1, title: '$stamp mbway');
  final o2 = await insertOrder(
    jwt: buyerJwt,
    pid: prod2['id'].toString(),
    buyer: buyerId,
    seller: sellerId,
    price: 22,
    pm: 'MB WAY',
  );
  rec('orders', 'INSERT MB WAY', 'buyer', brief(o2));
  final id2 = rowOf(o2)?['id']?.toString();
  if (id2 != null) {
    rec('orders', 'MB WAY sealed', 'svc', jsonEncode(await observeOrder(id2)));
    final pQty = await observeProduct(prod2['id'].toString());
    rec('products', 'qty after MB WAY hold', 'svc', jsonEncode(pQty));

    final sellerPago = await rest('PATCH', '/rest/v1/orders?id=eq.$id2', jwt: sellerJwt, body: {
      'status': 'pago',
    });
    rec('orders', 'seller PATCH MB WAY → pago', 'seller', brief(sellerPago));
    final afterPago = await observeOrder(id2);
    rec('orders', 'observe MB WAY pago', 'svc', jsonEncode(afterPago));

    if (afterPago['status'] == 'pago') {
      final buyerConcl = await rest('PATCH', '/rest/v1/orders?id=eq.$id2', jwt: buyerJwt, body: {
        'status': 'concluido',
      });
      rec('orders', 'buyer PATCH concluido from pago MB WAY', 'buyer', brief(buyerConcl));
      rec('orders', 'observe concluido', 'svc', jsonEncode(await observeOrder(id2)));

      final rev = await rest('POST', '/rest/v1/reviews', jwt: buyerJwt, body: {
        'order_id': id2,
        'buyer_id': buyerId,
        'target_id': sellerId,
        'stars': 5,
        'comment': 'rti1606 mbway review',
        'author_role': 'comprador',
        'target_type': 'seller',
      });
      rec('reviews', '5* after MB WAY concluido', 'buyer', brief(rev));
      rec('orders', 'observe after review', 'svc', jsonEncode(await observeOrder(id2)));
      rec('wallets', 'balances after MB WAY cycle', 'svc', jsonEncode({
        'seller0': wSeller0,
        'seller1': await walletOf(sellerId),
        'buyer0': wBuyer0,
        'buyer1': await walletOf(buyerId),
      }));
      final wSeller1 = await walletOf(sellerId);
      if (wSeller1 > wSeller0) {
        finding(
          id: 'P0-MBWAY-WALLET-MINT',
          sev: 'P0',
          title: 'Off-platform MB WAY cycle minted seller wallet',
          actor: 'seller+buyer collusion',
          pre: 'MB WAY order, seller pago, buyer concluido, 5* review',
          repro: 'wallet seller $wSeller0 → $wSeller1',
          impact: 'Platform balance created without Stripe capture',
        );
      }
    }
  }
}

Future<void> checkoutAuthority() async {
  final prod = await insertProduct(price: 15.5, qty: 3, title: '$stamp checkout');
  final pid = prod['id'].toString();
  final o = await insertOrder(
    jwt: buyerJwt,
    pid: pid,
    buyer: buyerId,
    seller: sellerId,
    price: 0.50,
    ship: 'CTT',
  );
  rec('orders', 'INSERT checkout fixture', 'buyer', brief(o));
  final oid = rowOf(o)?['id']?.toString();
  if (oid == null) return;
  rec('orders', 'sealed checkout fixture', 'svc', jsonEncode(await observeOrder(oid)));

  Future<void> tryPay(String label, String? jwt, Map<String, dynamic> body) async {
    final r = await edge('create-payment-intent', jwt: jwt, body: body);
    rec('edge/create-payment-intent', label, jwt == buyerJwt ? 'buyer' : jwt == sellerJwt ? 'seller' : jwt == helperJwt ? 'helper' : 'anon', brief(r));
    Map<String, dynamic>? parsed;
    try {
      parsed = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    stripe.add({'label': label, 'status': r.statusCode, 'body': parsed ?? r.body});
    final urlOut = parsed?['checkoutUrl']?.toString();
    final amt = parsed?['amount'] ?? parsed?['amount_cents'] ?? parsed?['total_cents'];
    if (urlOut != null && urlOut.isNotEmpty) {
      rec('edge/create-payment-intent', '$label SESSION', 'buyer', 'url_host=${Uri.tryParse(urlOut)?.host} amount=$amt session=${parsed?['checkoutSessionId']}');
    }
  }

  await tryPay('amount 50 + buyer_id', buyerJwt, {
    'order_id': oid,
    'buyer_id': buyerId,
    'amount': 50,
    'quantity': 1,
    'item_price': 0.5,
    'shipping_method': 'CTT',
    'product_id': pid,
  });
  await tryPay('helper buyer_id mismatch', helperJwt, {
    'order_id': oid,
    'buyer_id': helperId,
    'shipping_method': 'CTT',
  });
  await tryPay('helper claims buyer_id of owner', helperJwt, {
    'order_id': oid,
    'buyer_id': buyerId,
    'shipping_method': 'CTT',
  });
  await tryPay('seller checkout', sellerJwt, {
    'order_id': oid,
    'buyer_id': sellerId,
    'shipping_method': 'CTT',
  });
  await tryPay('qty 99 in body', buyerJwt, {
    'order_id': oid,
    'buyer_id': buyerId,
    'quantity': 99,
    'shipping_method': 'CTT',
  });

  rec('orders', 'after checkout attempts', 'svc', jsonEncode(await observeOrder(oid)));
}

Future<void> stockRace() async {
  final prod = await insertProduct(price: 9, qty: 1, title: '$stamp stock1');
  final pid = prod['id'].toString();
  rec('products', 'stock=1 before race', 'svc', jsonEncode(await observeProduct(pid)));

  final futs = List.generate(10, (i) {
    return insertOrder(
      jwt: i.isEven ? buyerJwt : helperJwt,
      pid: pid,
      buyer: i.isEven ? buyerId : helperId,
      seller: sellerId,
      price: 9,
      qty: 1,
    );
  });
  final rs = await Future.wait(futs);
  final created = <String>[];
  for (var i = 0; i < rs.length; i++) {
    rec('orders', 'race insert #$i', i.isEven ? 'buyer' : 'helper', brief(rs[i]));
    final id = rowOf(rs[i])?['id']?.toString();
    if (id != null) created.add(id);
  }
  rec('products', 'stock=1 after 10 inserts', 'svc', jsonEncode(await observeProduct(pid)));
  final active = <Map<String, dynamic>>[];
  for (final id in created) {
    final o = await observeOrder(id);
    active.add(o);
  }
  rec('orders', 'race created rows', 'svc', jsonEncode(active));
  final holding = active.where((o) {
    final st = '${o['status']}'.toLowerCase();
    return st != 'cancelado' && st != 'cancelled';
  }).toList();
  races.add({
    'name': 'stock1_10_inserts',
    'created': created.length,
    'holding': holding.length,
    'product': await observeProduct(pid),
  });
  if (holding.length >= 2) {
    finding(
      id: 'P1-STOCK1-TWO-HOLDS',
      sev: 'P1',
      title: 'stock=1 accepted ${holding.length} concurrent holds',
      actor: 'buyer+helper race',
      pre: 'product quantity=1',
      repro: '10 parallel INSERTs → ${holding.length} non-cancelled orders',
      impact: 'Oversell / double reservation of last unit',
    );
  }

  // If two holds, try dual checkout sessions
  if (holding.length >= 2) {
    final a = holding[0]['id'].toString();
    final b = holding[1]['id'].toString();
    final jwtA = holding[0]['buyer'] == buyerId ? buyerJwt : helperJwt;
    final jwtB = holding[1]['buyer'] == buyerId ? buyerJwt : helperJwt;
    final bidA = holding[0]['buyer'].toString();
    final bidB = holding[1]['buyer'].toString();
    final pa = edge('create-payment-intent', jwt: jwtA, body: {
      'order_id': a,
      'buyer_id': bidA,
      'shipping_method': 'entrega em mão',
    });
    final pb = edge('create-payment-intent', jwt: jwtB, body: {
      'order_id': b,
      'buyer_id': bidB,
      'shipping_method': 'entrega em mão',
    });
    final both = await Future.wait([pa, pb]);
    rec('edge/create-payment-intent', 'race session A', 'buyer', brief(both[0]));
    rec('edge/create-payment-intent', 'race session B', 'helper', brief(both[1]));
    races.add({
      'name': 'stock1_dual_session',
      'a': both[0].statusCode,
      'b': both[1].statusCode,
      'a_body': both[0].body.length > 400 ? both[0].body.substring(0, 400) : both[0].body,
      'b_body': both[1].body.length > 400 ? both[1].body.substring(0, 400) : both[1].body,
    });
  }
}

Future<void> dualCheckoutRace() async {
  final prod = await insertProduct(price: 11, qty: 2, title: '$stamp dualcs');
  final o = await insertOrder(
    jwt: buyerJwt,
    pid: prod['id'].toString(),
    buyer: buyerId,
    seller: sellerId,
    price: 11,
  );
  final oid = rowOf(o)?['id']?.toString();
  if (oid == null) return;
  final body = {
    'order_id': oid,
    'buyer_id': buyerId,
    'shipping_method': 'entrega em mão',
  };
  final rs = await Future.wait(List.generate(
    8,
    (_) => edge('create-payment-intent', jwt: buyerJwt, body: body),
  ));
  var sessions = 0;
  final urls = <String>[];
  for (var i = 0; i < rs.length; i++) {
    rec('edge/create-payment-intent', 'same-order burst #$i', 'buyer', brief(rs[i]));
    try {
      final m = jsonDecode(rs[i].body);
      final u = m is Map ? m['checkoutUrl']?.toString() : null;
      final sid = m is Map ? m['checkoutSessionId']?.toString() : null;
      if (u != null && u.isNotEmpty) {
        sessions++;
        urls.add(sid ?? u);
      }
    } catch (_) {}
  }
  rec('orders', 'after dual session burst', 'svc', jsonEncode(await observeOrder(oid)));
  races.add({'name': 'same_order_8_sessions', 'session_ok': sessions, 'ids': urls});
  if (sessions >= 2) {
    finding(
      id: 'P2-DUAL-CHECKOUT-SESSION',
      sev: 'P2',
      title: 'Same order produced $sessions Checkout Sessions',
      actor: 'buyer',
      pre: 'One reserva_pendente order',
      repro: '8 parallel create-payment-intent → $sessions URLs',
      impact: 'Session≠sale; need capture analysis. Possible double charge if both paid.',
    );
  }
}

Future<void> reviewsAndDisputes() async {
  final rev = await rest('POST', '/rest/v1/reviews', jwt: buyerJwt, body: {
    'buyer_id': buyerId,
    'target_id': sellerId,
    'stars': 5,
    'comment': 'rti1606 no order',
    'author_role': 'comprador',
    'target_type': 'seller',
  });
  rec('reviews', 'INSERT no order_id', 'buyer', brief(rev));

  final revHelper = await rest('POST', '/rest/v1/reviews', jwt: helperJwt, body: {
    'buyer_id': buyerId,
    'target_id': sellerId,
    'stars': 1,
    'comment': 'impersonate',
    'author_role': 'comprador',
    'order_id': '00000000-0000-0000-0000-000000000001',
  });
  rec('reviews', 'helper INSERT as buyer', 'helper', brief(revHelper));

  // Existing paid order of buyer if any
  final paid = await admin.select(
    'orders',
    filter: 'buyer_id=eq.$buyerId&status=eq.concluido',
    limit: 3,
  );
  rec('reviews', 'concluido orders for buyer', 'svc', 'count=${paid.length}');
  if (paid.isNotEmpty) {
    final oid = paid.first['id'].toString();
    final dup = await rest('POST', '/rest/v1/reviews', jwt: buyerJwt, body: {
      'order_id': oid,
      'buyer_id': buyerId,
      'target_id': sellerId,
      'stars': 5,
      'comment': 'rti1606 dup',
      'author_role': 'comprador',
    });
    rec('reviews', 'duplicate on concluido order', 'buyer', brief(dup));
    if (ok2(dup.statusCode) && rowOf(dup) != null) {
      finding(
        id: 'P1-REVIEW-DUPLICATE',
        sev: 'P1',
        title: 'Duplicate review on same order',
        actor: 'buyer',
        pre: 'Order $oid already reviewed or concluido',
        repro: 'INSERT reviews → ${dup.body}',
        impact: 'Reputation inflation',
      );
    }
    final sellerRev = await rest('POST', '/rest/v1/reviews', jwt: sellerJwt, body: {
      'order_id': oid,
      'buyer_id': sellerId,
      'target_id': buyerId,
      'stars': 5,
      'comment': 'seller as buyer',
      'author_role': 'comprador',
    });
    rec('reviews', 'seller review impersonating buyer role', 'seller', brief(sellerRev));
  }

  final disp = await rest('POST', '/rest/v1/order_disputes', jwt: helperJwt, body: {
    'order_id': paid.isNotEmpty ? paid.first['id'] : '00000000-0000-0000-0000-000000000001',
    'buyer_id': helperId,
    'reason': 'em_falta',
    'description': 'cross dispute',
  });
  rec('order_disputes', 'helper dispute on buyer order', 'helper', brief(disp));
}

Future<void> offers() async {
  final prod = await insertProduct(price: 40, qty: 1, title: '$stamp offer');
  final pid = prod['id'].toString();
  final chats = await rest('GET', '/rest/v1/chats?or=(user_a.eq.$buyerId,user_b.eq.$buyerId)&limit=1', jwt: buyerJwt);
  rec('chats', 'list for offer', 'buyer', brief(chats));
  String? chatId;
  final crow = rowOf(chats);
  chatId = crow?['id']?.toString();
  if (chatId == null) {
    final c = await rest('POST', '/rest/v1/chats', jwt: buyerJwt, body: {
      'user_a': buyerId,
      'user_b': sellerId,
    });
    rec('chats', 'create', 'buyer', brief(c));
    chatId = rowOf(c)?['id']?.toString();
  }
  final ins = await rest('POST', '/rest/v1/product_offers', jwt: buyerJwt, body: {
    'product_id': pid,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 5.0,
    'list_price': 40.0,
    'offered_by': 'buyer',
    'status': 'pending',
    if (chatId != null) 'chat_id': chatId,
  });
  rec('product_offers', 'INSERT pending 5€ vs 40€', 'buyer', brief(ins));
  final oid = rowOf(ins)?['id']?.toString();
  if (oid == null) return;

  final self = await rest('PATCH', '/rest/v1/product_offers?id=eq.$oid', jwt: buyerJwt, body: {
    'status': 'accepted',
    'responded_at': DateTime.now().toUtc().toIso8601String(),
  });
  rec('product_offers', 'buyer self-accept', 'buyer', brief(self));
  final afterSelf = await admin.select('product_offers', filter: 'id=eq.$oid', limit: 1);
  rec('product_offers', 'after self-accept', 'svc', jsonEncode(afterSelf));

  final acc = await rest('PATCH', '/rest/v1/product_offers?id=eq.$oid', jwt: sellerJwt, body: {
    'status': 'accepted',
    'responded_at': DateTime.now().toUtc().toIso8601String(),
  });
  rec('product_offers', 'seller accept', 'seller', brief(acc));
  final afterAcc = await admin.select('product_offers', filter: 'id=eq.$oid', limit: 1);
  rec('product_offers', 'after seller accept', 'svc', jsonEncode(afterAcc));

  final mutate = await rest('PATCH', '/rest/v1/product_offers?id=eq.$oid', jwt: buyerJwt, body: {
    'amount': 0.50,
  });
  rec('product_offers', 'buyer mutate amount post-accept', 'buyer', brief(mutate));
  rec('product_offers', 'final offer', 'svc', jsonEncode(await admin.select('product_offers', filter: 'id=eq.$oid', limit: 1)));

  final order = await insertOrder(
    jwt: buyerJwt,
    pid: pid,
    buyer: buyerId,
    seller: sellerId,
    price: 0.50,
    pm: 'proposta aceite',
    extra: {'product_offer_id': oid},
  );
  rec('orders', 'INSERT with accepted offer', 'buyer', brief(order));
  final orow = rowOf(order);
  if (orow != null) {
    rec('orders', 'offer contract sealed', 'buyer', jsonEncode({
      'price_total': orow['price_total'],
      'contract_unit_cents': orow['contract_unit_cents'],
      'offer': orow['product_offer_id'],
    }));
    final cents = orow['contract_unit_cents'];
    final amt = afterAcc.isNotEmpty ? afterAcc.first['amount'] : null;
    rec('orders', 'compare offer vs contract', 'svc', jsonEncode({'offer_amount': amt, 'contract_cents': cents, 'price_total': orow['price_total']}));
  }
}

Future<void> bankingOracle() async {
  final b = await rpc('batata_seller_direct_payment_details', {'p_seller_id': sellerId}, jwt: helperJwt);
  rec('rpc/batata_seller_direct_payment_details', 'helper reads seller IBAN', 'helper', brief(b));
  if (ok2(b.statusCode) && b.body.contains('iban')) {
    finding(
      id: 'P2-BANKING-ORACLE',
      sev: 'P2',
      title: 'Any authenticated user can read seller IBAN/MB WAY by UUID',
      actor: 'helper',
      pre: 'Known seller UUID',
      repro: 'rpc batata_seller_direct_payment_details → ${b.body}',
      impact: 'PII/financial identifier enumeration. May be intended for checkout UI.',
    );
  }
  final e1 = await rpc('batata_find_user_id_by_email', {'p_email': 'not-a-user@fleaber.invalid'}, jwt: helperJwt);
  rec('rpc/batata_find_user_id_by_email', 'unknown email', 'helper', brief(e1));
  final env = loadLiveOpsStagingEnv();
  final sellerEmail = env['LIVE_OPS_TEST_SELLER_EMAIL'] ?? '';
  final e2 = await rpc('batata_find_user_id_by_email', {'p_email': sellerEmail}, jwt: helperJwt);
  rec('rpc/batata_find_user_id_by_email', 'seller email as helper', 'helper', brief(e2));
}

Future<void> chatCrossUser() async {
  final chats = await rest(
    'GET',
    '/rest/v1/chats?select=id,user_a,user_b&limit=20',
    jwt: helperJwt,
  );
  rec('chats', 'helper SELECT', 'helper', brief(chats));
  final buyerChats = await rest(
    'GET',
    '/rest/v1/chats?select=id,user_a,user_b&limit=5',
    jwt: buyerJwt,
  );
  rec('chats', 'buyer SELECT', 'buyer', brief(buyerChats));
  final list = jsonDecode(buyerChats.body);
  if (list is List && list.isNotEmpty) {
    final cid = (list.first as Map)['id'];
    final inj = await rest('POST', '/rest/v1/chat_messages', jwt: helperJwt, body: {
      'chat_id': cid,
      'sender_id': helperId,
      'text': 'rti1606 inject',
    });
    rec('chat_messages', 'helper inject into buyer chat', 'helper', brief(inj));
    if (ok2(inj.statusCode) && rowOf(inj) != null) {
      finding(
        id: 'P1-CHAT-INJECT',
        sev: 'P1',
        title: 'Helper injected message into foreign chat',
        actor: 'helper',
        pre: 'Known chat_id $cid',
        repro: 'INSERT chat_messages → ${inj.body}',
        impact: 'Cross-user chat integrity',
      );
    }
    final read = await rest(
      'GET',
      '/rest/v1/chat_messages?chat_id=eq.$cid&select=id,text,sender_id&limit=3',
      jwt: helperJwt,
    );
    rec('chat_messages', 'helper READ buyer chat', 'helper', brief(read));
  }
}

Future<void> liveReservation() async {
  final lives = await admin.select('lives', filter: 'seller_id=eq.$sellerId', limit: 3);
  rec('lives', 'seller lives', 'svc', 'count=${lives.length}');
  if (lives.isEmpty) return;
  final liveId = lives.first['id'].toString();
  final items = await admin.select('live_items', filter: 'live_id=eq.$liveId', limit: 5);
  rec('live_items', 'items', 'svc', 'count=${items.length}');
  if (items.isEmpty) return;
  final li = items.first['id'].toString();

  final r1 = await rpc('batata_live_bag_add', {
    'p_live_item_id': li,
    'p_qty': 1,
  }, jwt: buyerJwt);
  rec('rpc/batata_live_bag_add', 'buyer add', 'buyer', brief(r1));

  final sold = await rpc('batata_mark_live_item_sold', {'p_live_item_id': li}, jwt: buyerJwt);
  rec('rpc/batata_mark_live_item_sold', 'buyer mark sold', 'buyer', brief(sold));

  final raffle = await rpc('batata_create_live_raffle', {
    'p_live_id': liveId,
    'p_live_item_id': li,
  }, jwt: buyerJwt);
  rec('rpc/batata_create_live_raffle', 'buyer create raffle', 'buyer', brief(raffle));

  final pair = await rpc('batata_ps_create_pairing', {'p_live_id': liveId}, jwt: buyerJwt);
  rec('rpc/batata_ps_create_pairing', 'buyer pairing', 'buyer', brief(pair));
}

Future<void> payoutRetry() async {
  final w0 = await walletOf(sellerId);
  rec('wallets', 'seller before payout', 'svc', '$w0');
  final key = 'rti1606-payout-${DateTime.now().millisecondsSinceEpoch}';
  final a = edge('create-connect-account', jwt: sellerJwt, body: {
    'amount': 100,
    'idempotency_key': key,
  });
  final b = edge('create-connect-account', jwt: sellerJwt, body: {
    'amount': 100,
    'idempotency_key': key,
  });
  final c = edge('create-connect-account', jwt: sellerJwt, body: {
    'amount': 100,
    'idempotency_key': '$key-b',
  });
  final rs = await Future.wait([a, b, c]);
  rec('edge/create-connect-account', 'same key A', 'seller', brief(rs[0]));
  rec('edge/create-connect-account', 'same key B', 'seller', brief(rs[1]));
  rec('edge/create-connect-account', 'different key', 'seller', brief(rs[2]));
  rec('wallets', 'seller after payout race', 'svc', '${await walletOf(sellerId)}');
  races.add({
    'name': 'payout_retry',
    'w0': w0,
    'w1': await walletOf(sellerId),
    'same_a': rs[0].statusCode,
    'same_b': rs[1].statusCode,
    'diff': rs[2].statusCode,
  });
}

Future<void> storageBuckets() async {
  final buckets = await http.get(
    Uri.parse('$url/storage/v1/bucket'),
    headers: {
      'apikey': svc,
      'Authorization': 'Bearer $svc',
    },
  );
  rec('storage', 'list buckets svc', 'svc', brief(buckets));
  try {
    final list = jsonDecode(buckets.body);
    if (list is List) {
      for (final b in list.take(12)) {
        final id = (b as Map)['id']?.toString() ?? (b['name']?.toString() ?? '');
        if (id.isEmpty) continue;
        final listed = await http.post(
          Uri.parse('$url/storage/v1/object/list/$id'),
          headers: h(buyerJwt),
          body: jsonEncode({'prefix': '', 'limit': 5}),
        );
        rec('storage/$id', 'LIST as buyer', 'buyer', brief(listed));
        final listedH = await http.post(
          Uri.parse('$url/storage/v1/object/list/$id'),
          headers: h(helperJwt),
          body: jsonEncode({'prefix': '', 'limit': 5}),
        );
        rec('storage/$id', 'LIST as helper', 'helper', brief(listedH));
      }
    }
  } catch (e) {
    rec('storage', 'parse buckets', 'svc', '$e');
  }
}

Future<void> sellerAmountPaid() async {
  final prod = await insertProduct(price: 14, qty: 1, title: '$stamp amt');
  final o = await insertOrder(
    jwt: buyerJwt,
    pid: prod['id'].toString(),
    buyer: buyerId,
    seller: sellerId,
    price: 14,
    pm: 'Pagamento na app',
  );
  final id = rowOf(o)?['id']?.toString();
  if (id == null) return;
  for (final who in [
    ['buyer', buyerJwt],
    ['seller', sellerJwt],
  ]) {
    final r = await rest('PATCH', '/rest/v1/orders?id=eq.$id', jwt: who[1] as String, body: {
      'amount_paid_cents': 1400,
      'stripe_payment_intent_id': 'pi_3FakeRti1606xxxxxxxxxxxx',
      'status': 'pago',
    });
    rec('orders', '${who[0]} PATCH capture fields', who[0] as String, brief(r));
    rec('orders', 'observe after ${who[0]} capture patch', 'svc', jsonEncode(await observeOrder(id)));
  }
}

Future<void> rpcGrantSweep() async {
  final file = File('tool/redteam_blind_indep_20260830T1606/out/openapi_rpcs.json');
  if (!file.existsSync()) return;
  final inv = jsonDecode(file.readAsStringSync()) as Map;
  final rpcs = (inv['rpcs'] as List).cast<String>();
  final interesting = RegExp(
    r'(wallet|payout|credit|settle|refund|admin|stripe|finalize|release|commission|ledger|raffle|review|dispute|convert|sold|pairing|tip|offer|bundle|stock)',
    caseSensitive: false,
  );
  final names = rpcs.where(interesting.hasMatch).take(80).toList();
  for (final fn in names) {
    final r = await rpc(fn, {}, jwt: buyerJwt);
    if (ok2(r.statusCode) ||
        (r.statusCode != 404 &&
            !r.body.contains('PGRST202') &&
            !r.body.contains('permission denied'))) {
      rec('rpc/$fn', '{}', 'buyer', brief(r), sev: ok2(r.statusCode) ? 'watch' : 'info');
    }
  }
}
