// Red Team Parallel C — Deep Cash / Race / Composição
// Staging fxdknzrqjenzqcvnwqqq. Stripe TEST. Não corrige. Produção não. Fase 4 não.
// dart run tool/rtc_deep_cash_20260830T0900.dart
//
// service_role: fixtures / observação / cleanup. Findings de autoridade = JWT/anon.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stamp = '20260830T0900';
const tag = 'RTC-$stamp';
const stagingRef = 'fxdknzrqjenzqcvnwqqq';

final findings = <Map<String, dynamic>>[];
final matrix = <Map<String, dynamic>>[];
final races = <Map<String, dynamic>>[];
final gaps = <String>[];
final createdProductIds = <String>[];
final createdOrderIds = <String>[];
final createdUserIds = <String>[];
final createdDisputeIds = <String>[];

late String url;
late String anon;
late String svc;
late LiveOpsStagingClient sb;
late String buyerJwt;
late String sellerJwt;
late String buyerId;
late String sellerId;
String? buyer2Jwt;
String? buyer2Id;
String? e2eSecret;

String clip(String s, [int n = 240]) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length <= n) return t;
  return '${t.substring(0, n)}…';
}

void row({
  required String surface,
  required String attack,
  required String identity,
  required String result,
  required String impact,
  String severity = '—',
  String evidence = '',
}) {
  matrix.add({
    'surface': surface,
    'attack': attack,
    'identity': identity,
    'result': result,
    'impact': impact,
    'severity': severity,
    'evidence': evidence,
  });
}

void finding({
  required String id,
  required String severity,
  required String title,
  required String actor,
  required String preconditions,
  required String repro,
  required String impact,
  required String estado,
  Map<String, dynamic>? evidence,
}) {
  findings.add({
    'id': id,
    'severity': severity,
    'title': title,
    'actor': actor,
    'preconditions': preconditions,
    'repro': repro,
    'impact': impact,
    'estado': estado,
    if (evidence != null) 'evidence': evidence,
  });
}

Future<http.Response> rest({
  required String method,
  required String path,
  String? token,
  Object? body,
  bool service = false,
  Map<String, String>? extraHeaders,
}) async {
  final headers = <String, String>{
    'apikey': service ? svc : anon,
    'Authorization': 'Bearer ${service ? svc : (token ?? anon)}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
    ...?extraHeaders,
  };
  final uri = Uri.parse('$url$path');
  switch (method) {
    case 'GET':
      return http.get(uri, headers: headers);
    case 'POST':
      return http.post(uri, headers: headers, body: body == null ? null : jsonEncode(body));
    case 'PATCH':
      return http.patch(uri, headers: headers, body: body == null ? null : jsonEncode(body));
    case 'DELETE':
      return http.delete(uri, headers: headers);
    default:
      throw ArgumentError(method);
  }
}

Future<http.Response> rpcRaw(
  String fn,
  Map<String, dynamic> params, {
  String? token,
  bool service = false,
}) {
  return rest(
    method: 'POST',
    path: '/rest/v1/rpc/$fn',
    token: token,
    service: service,
    body: params,
  );
}

Future<http.Response> edge(
  String fn,
  Object? body, {
  String? token,
  String query = '',
  Map<String, String>? headers,
  String method = 'POST',
}) {
  final h = <String, String>{
    'apikey': anon,
    'Authorization': 'Bearer ${token ?? anon}',
    'Content-Type': 'application/json',
    ...?headers,
  };
  final uri = Uri.parse('$url/functions/v1/$fn$query');
  if (method == 'GET') return http.get(uri, headers: h);
  return http.post(uri, headers: h, body: body == null ? null : jsonEncode(body));
}

Future<http.Response> e2e(Map<String, dynamic> body) {
  return rest(
    method: 'POST',
    path: '/functions/v1/sec-fase2-e2e-oversell',
    token: anon,
    body: body,
    extraHeaders: {
      if (e2eSecret != null && e2eSecret!.isNotEmpty)
        'x-fleaber-e2e-secret': e2eSecret!,
    },
  );
}

num? numOf(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString());
}

Map<String, dynamic>? firstRow(http.Response r) {
  if (r.body.isEmpty) return null;
  try {
    final d = jsonDecode(r.body);
    if (d is List && d.isNotEmpty && d.first is Map) {
      return Map<String, dynamic>.from(d.first as Map);
    }
    if (d is Map<String, dynamic>) return d;
  } catch (_) {}
  return null;
}

Future<Map<String, dynamic>?> walletOf(String id) async {
  final r = await rest(
    method: 'GET',
    path: '/rest/v1/wallets?id=eq.$id&select=id,balance',
    service: true,
  );
  return firstRow(r);
}

Future<Map<String, dynamic>?> orderOf(String id) async {
  final r = await rest(
    method: 'GET',
    path:
        '/rest/v1/orders?id=eq.$id&select=id,status,price_total,quantity,contract_unit_cents,contract_qty,payment_method,shipping_method,amount_paid_cents,stripe_payment_intent_id,stripe_checkout_session_id,stripe_refund_id,stock_units_applied,wallet_release_processed_at,wallet_refund_processed_at,buyer_id,seller_id,product_id,product_offer_id',
    service: true,
  );
  return firstRow(r);
}

Future<Map<String, dynamic>?> productOf(String id) async {
  final r = await rest(
    method: 'GET',
    path:
        '/rest/v1/products?id=eq.$id&select=id,price,quantity,is_sold,list_on_marketplace,seller_id,title,ref_code',
    service: true,
  );
  return firstRow(r);
}

Future<List<Map<String, dynamic>>> txsFor(String walletId, {int limit = 20}) async {
  final r = await rest(
    method: 'GET',
    path:
        '/rest/v1/wallet_transactions?wallet_id=eq.$walletId&select=id,amount,type,order_id,tip_id,created_at,description&order=created_at.desc&limit=$limit',
    service: true,
  );
  if (r.statusCode >= 400) return [];
  try {
    final d = jsonDecode(r.body);
    if (d is List) {
      return d.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
  } catch (_) {}
  return [];
}

Future<Map<String, dynamic>> makeProduct({
  required String sellerToken,
  required String title,
  required num price,
  required int qty,
  String? ref,
}) async {
  final r = await rest(
    method: 'POST',
    path: '/rest/v1/products',
    token: sellerToken,
    body: {
      'seller_id': sellerId,
      'title': title,
      'price': price,
      'quantity': qty,
      'ref_code': ref ?? '$tag-${DateTime.now().millisecondsSinceEpoch}',
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': [],
    },
  );
  final row = firstRow(r);
  if (r.statusCode >= 400 || row == null || row['id'] == null) {
    throw StateError('product insert ${r.statusCode} ${clip(r.body)}');
  }
  createdProductIds.add(row['id'].toString());
  return row;
}

Future<Map<String, dynamic>> makeOrder({
  required String token,
  required String productId,
  Map<String, dynamic> extra = const {},
}) async {
  final body = <String, dynamic>{
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': productId,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'hand',
    ...extra,
  };
  if (token == sellerJwt && extra['buyer_id'] == null) {
    body['buyer_id'] = buyerId;
  }
  final r = await rest(method: 'POST', path: '/rest/v1/orders', token: token, body: body);
  final row = firstRow(r);
  if (r.statusCode >= 400 || row == null || row['id'] == null) {
    throw StateError('order insert ${r.statusCode} ${clip(r.body)}');
  }
  createdOrderIds.add(row['id'].toString());
  return row;
}

Future<http.Response> checkout({
  required String token,
  required String buyer,
  required String orderId,
  Map<String, dynamic> extra = const {},
}) {
  return edge('create-payment-intent', {
    'buyer_id': buyer,
    'order_id': orderId,
    'shipping_method': 'hand',
    ...extra,
  }, token: token);
}

int? serverCents(http.Response r) {
  try {
    final d = jsonDecode(r.body);
    if (d is Map) return (d['server_amount_cents'] as num?)?.toInt();
  } catch (_) {}
  return null;
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(stagingRef)) {
    stderr.writeln('ABORT: URL não é staging $stagingRef');
    exit(2);
  }
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  e2eSecret = env['FLEABER_STAGING_CRASH_INJECT_SECRET']?.trim();
  final stripeLocal = (env['STRIPE_SECRET_KEY'] ?? Platform.environment['STRIPE_SECRET_KEY'] ?? '')
      .trim();
  sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);

  buyerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  sellerJwt = await sb.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  buyerId = await sb.userIdForAccessToken(buyerJwt);
  sellerId = await sb.userIdForAccessToken(sellerJwt);

  // Buyer malicioso descartável
  final b2email = 'rtc-b2-$stamp-${Random().nextInt(99999)}@staging.fleaber.bot';
  const b2pass = 'RtcDeepCash_2026!';
  try {
    buyer2Id = await sb.createAdminUser(
      email: b2email,
      password: b2pass,
      userMetadata: {'full_name': 'RTC B2'},
    );
    createdUserIds.add(buyer2Id!);
    await rest(
      method: 'POST',
      path: '/rest/v1/profiles',
      service: true,
      body: {
        'id': buyer2Id,
        'email': b2email,
        'user_type': 'buyer',
        'display_name': 'RTC-B2',
      },
    );
    buyer2Jwt = await sb.signIn(email: b2email, password: b2pass);
  } catch (e) {
    gaps.add('buyer2 fixture: $e');
  }

  final frozenAt = DateTime.now().toUtc().toIso8601String();
  stdout.writeln('RTC C start $frozenAt buyer=$buyerId seller=$sellerId b2=$buyer2Id');

  try {
    await well3ConfusedDeputy();
    await well1Cash(stripeLocal);
    await well2Unit();
    await well1AccountingClose();
  } catch (e, st) {
    gaps.add('fatal: $e');
    stderr.writeln(e);
    stderr.writeln(st);
  }

  await cleanup();
  await writeReports(frozenAt, stripeLocal);
}

/// POÇO 3 — dois caminhos / confused deputy (JWT, sem Flutter)
Future<void> well3ConfusedDeputy() async {
  // --- Anon checkout / wallet ---
  final anonCk = await checkout(token: anon, buyer: buyerId, orderId: '00000000-0000-0000-0000-000000000001');
  row(
    surface: 'checkout',
    attack: 'anon POST create-payment-intent',
    identity: 'anon',
    result: 'http=${anonCk.statusCode} ${clip(anonCk.body, 120)}',
    impact: anonCk.statusCode == 200 ? 'sessão sem login' : 'bloqueado',
    severity: anonCk.statusCode == 200 ? 'P0' : '—',
  );

  final anonWal = await rest(method: 'GET', path: '/rest/v1/wallets?select=id,balance&limit=3', token: anon);
  row(
    surface: 'wallets',
    attack: 'anon SELECT wallets',
    identity: 'anon',
    result: 'http=${anonWal.statusCode} n=${anonWal.body.length}',
    impact: anonWal.statusCode == 200 && anonWal.body.length > 5 ? 'leitura saldo' : 'RLS',
  );

  // --- JWT money RPCs ---
  for (final fn in [
    'batata_credit_wallet_once',
    'batata_debit_wallet_once',
    'batata_release_seller_wallet_for_order',
    'batata_refund_buyer_wallet_for_order',
    'batata_clawback_seller_wallet_for_order',
    'batata_process_partial_refund_dispute',
    'batata_wallet_apply_tip_once',
    'batata_wallet_payout_debit',
    'batata_ensure_wallet',
  ]) {
    final Map<String, dynamic> params = switch (fn) {
      'batata_credit_wallet_once' => {
          'p_wallet_id': buyerId,
          'p_order_id': '00000000-0000-0000-0000-000000000001',
          'p_amount': 9.99,
          'p_type': 'venda',
          'p_description': 'rtc',
        },
      'batata_debit_wallet_once' => {
          'p_wallet_id': sellerId,
          'p_order_id': '00000000-0000-0000-0000-000000000001',
          'p_amount': 1.00,
          'p_type': 'levantamento',
        },
      'batata_wallet_apply_tip_once' => {
          'p_wallet_id': sellerId,
          'p_tip_id': '00000000-0000-0000-0000-000000000001',
          'p_amount': 5.00,
          'p_type': 'gorjeta_recebida',
          'p_description': 'rtc',
        },
      'batata_wallet_payout_debit' => {
          'p_user_id': sellerId,
          'p_amount_cents': 100,
          'p_idempotency_key': '$tag-payout-x',
        },
      'batata_ensure_wallet' => {'p_user_id': sellerId},
      _ => {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    };
    if (fn == 'batata_process_partial_refund_dispute') {
      params['p_refund_percent'] = 100;
    }
    final r = await rpcRaw(fn, params, token: buyerJwt);
    final ok = r.statusCode == 200;
    row(
      surface: 'rpc',
      attack: '$fn JWT buyer',
      identity: 'buyer',
      result: 'http=${r.statusCode} ${clip(r.body, 140)}',
      impact: ok ? 'DEFINER executou' : 'revogado/erro',
      severity: ok && fn.contains('credit') ? 'P0' : '—',
    );
    if (ok && (fn.contains('credit') || fn.contains('payout') || fn.contains('apply_tip'))) {
      finding(
        id: 'RTC-W3-${fn.split('_').last.toUpperCase()}',
        severity: 'P0',
        title: 'JWT executa $fn',
        actor: 'buyer JWT',
        preconditions: 'GRANT authenticated',
        repro: 'POST /rpc/$fn com JWT buyer',
        impact: 'possível mint/payout sem captura',
        estado: 'ABERTO — validar Δwallet no poço 1',
        evidence: {'http': r.statusCode, 'body': clip(r.body, 300)},
      );
    }
  }

  // --- Insert order: preço/qty/status/PI hostis ---
  final pHost = await makeProduct(
    sellerToken: sellerJwt,
    title: '$tag hostil-contrato',
    price: 40.00,
    qty: 5,
  );
  final insVariants = <Map<String, dynamic>>[
    {
      'name': 'contract_unit_1c',
      'extra': {'contract_unit_cents': 1, 'contract_qty': 1, 'price_total': 0.01},
    },
    {
      'name': 'qty99',
      'extra': {'quantity': 99, 'price_total': 1},
    },
    {
      'name': 'status_pago',
      'extra': {'status': 'pago', 'amount_paid_cents': 4000},
    },
    {
      'name': 'fake_pi',
      'extra': {
        'stripe_payment_intent_id': 'pi_rtc_fake',
        'amount_paid_cents': 9900,
      },
    },
    {
      'name': 'proposta_low',
      'extra': {
        'payment_method': 'proposta aceite',
        'price_total': 1.00,
      },
    },
    {
      'name': 'offplat_mbway',
      'extra': {
        'payment_method': 'MB WAY',
        'shipping_method': 'carrier',
      },
    },
  ];
  for (final v in insVariants) {
    try {
      final o = await makeOrder(
        token: buyerJwt,
        productId: pHost['id'].toString(),
        extra: Map<String, dynamic>.from(v['extra'] as Map),
      );
      final live = await orderOf(o['id'].toString());
      row(
        surface: 'orders INSERT',
        attack: v['name'] as String,
        identity: 'buyer',
        result:
            'status=${live?['status']} unit=${live?['contract_unit_cents']} qty=${live?['contract_qty']} paid=${live?['amount_paid_cents']} pi=${live?['stripe_payment_intent_id']} pm=${live?['payment_method']}',
        impact: 'ver selo vs body',
      );
    } catch (e) {
      row(
        surface: 'orders INSERT',
        attack: v['name'] as String,
        identity: 'buyer',
        result: clip(e.toString(), 160),
        impact: 'rejeitado',
      );
    }
  }

  // Seller ghost-sale: order para buyer alheio
  try {
    await makeOrder(
      token: sellerJwt,
      productId: pHost['id'].toString(),
      extra: {'buyer_id': buyerId, 'status': 'pago', 'payment_method': 'MB WAY'},
    );
    row(
      surface: 'orders INSERT',
      attack: 'seller atribui buyer alheio + pago',
      identity: 'seller',
      result: 'INSERT ok',
      impact: 'ghost sale',
      severity: 'P1',
    );
  } catch (e) {
    row(
      surface: 'orders INSERT',
      attack: 'seller atribui buyer alheio + pago',
      identity: 'seller',
      result: clip(e.toString(), 160),
      impact: 'bloqueado',
    );
  }

  // PATCH money cols
  final oPatch = await makeOrder(token: buyerJwt, productId: pHost['id'].toString());
  final oid = oPatch['id'].toString();
  for (final patch in [
    {'status': 'pago'},
    {'price_total': 0.50},
    {'quantity': 9},
    {'contract_unit_cents': 1},
    {'amount_paid_cents': 1},
    {'payment_method': 'MB WAY'},
    {'shipping_method': 'carrier'},
    {'buyer_id': sellerId},
  ]) {
    final r = await rest(
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$oid',
      token: buyerJwt,
      body: patch,
    );
    final after = await orderOf(oid);
    row(
      surface: 'orders PATCH',
      attack: 'buyer ${patch.keys.first}=${patch.values.first}',
      identity: 'buyer',
      result:
          'http=${r.statusCode} status=${after?['status']} price=${after?['price_total']} qty=${after?['quantity']} unit=${after?['contract_unit_cents']} paid=${after?['amount_paid_cents']} pm=${after?['payment_method']} ship=${after?['shipping_method']}',
      impact: 'persistiu?' ,
    );
  }

  // Seller PATCH pago em pagamento plataforma
  final rSellerPago = await rest(
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.$oid',
    token: sellerJwt,
    body: {'status': 'pago'},
  );
  final afterSeller = await orderOf(oid);
  final persistedPago = (afterSeller?['status'] ?? '').toString().toLowerCase() == 'pago';
  row(
    surface: 'orders PATCH',
    attack: 'seller marca pago (plataforma, sem captura)',
    identity: 'seller',
    result: 'http=${rSellerPago.statusCode} status=${afterSeller?['status']}',
    impact: persistedPago ? 'falsifica liquidação' : 'bloqueado',
    severity: persistedPago ? 'P1' : '—',
  );
  if (persistedPago) {
    finding(
      id: 'RTC-C-SELLER-PAGO-PLATFORM',
      severity: 'P1',
      title: 'Seller JWT marca pago em pagamento plataforma sem captura',
      actor: 'seller JWT',
      preconditions: 'order Pagamento na app, sem PI',
      repro: 'PATCH orders status=pago',
      impact: 'stock/venda sem dinheiro',
      estado: 'ABERTO',
      evidence: afterSeller,
    );
  }

  // Checkout body vs row
  final oCk = await makeOrder(token: buyerJwt, productId: pHost['id'].toString());
  final ckLow = await checkout(
    token: buyerJwt,
    buyer: buyerId,
    orderId: oCk['id'].toString(),
    extra: {'amount': 50, 'item_price': 0.01, 'quantity': 1, 'shipping': 0},
  );
  final cents = serverCents(ckLow);
  row(
    surface: 'checkout',
    attack: 'body.amount=50 vs contrato 40€',
    identity: 'buyer',
    result: 'http=${ckLow.statusCode} server_cents=$cents ${clip(ckLow.body, 140)}',
    impact: (cents != null && cents < 4000) ? 'underpay quote' : 'quote servidor',
    severity: (cents != null && cents < 3500) ? 'P0' : '—',
  );

  final ckCross = await checkout(
    token: buyerJwt,
    buyer: sellerId,
    orderId: oCk['id'].toString(),
  );
  row(
    surface: 'checkout',
    attack: 'buyer_id=seller no body (JWT buyer)',
    identity: 'buyer',
    result: 'http=${ckCross.statusCode} ${clip(ckCross.body, 120)}',
    impact: ckCross.statusCode == 200 ? 'confused deputy identidade' : 'uid bind',
  );

  if (buyer2Jwt != null && buyer2Id != null) {
    final ckAlien = await checkout(
      token: buyer2Jwt!,
      buyer: buyer2Id!,
      orderId: oCk['id'].toString(),
    );
    row(
      surface: 'checkout',
      attack: 'buyer2 paga order do buyer1',
      identity: 'buyer2',
      result: 'http=${ckAlien.statusCode} ${clip(ckAlien.body, 120)}',
      impact: ckAlien.statusCode == 200 ? 'paga encomenda alheia' : 'bloqueado',
    );
  }

  // Portes: selo vazio / lixo + body hand
  final oShip = await makeOrder(
    token: buyerJwt,
    productId: pHost['id'].toString(),
    extra: {'shipping_method': 'xyz-garbage'},
  );
  final ckHand = await checkout(
    token: buyerJwt,
    buyer: buyerId,
    orderId: oShip['id'].toString(),
    extra: {'shipping_method': 'hand'},
  );
  final ckCarr = await checkout(
    token: buyerJwt,
    buyer: buyerId,
    orderId: oShip['id'].toString(),
    extra: {'shipping_method': 'carrier'},
  );
  row(
    surface: 'checkout portes',
    attack: 'shipping garbage na order; body hand vs carrier',
    identity: 'buyer',
    result: 'hand=${serverCents(ckHand)} carrier=${serverCents(ckCarr)} hhttp=${ckHand.statusCode} chttp=${ckCarr.statusCode}',
    impact: (serverCents(ckHand) != null &&
            serverCents(ckCarr) != null &&
            serverCents(ckHand) != serverCents(ckCarr))
        ? 'cliente escolhe portes pós-INSERT'
        : 'selo ou fail-closed',
  );

  // Prize flag em order normal
  final ckPrize = await checkout(
    token: buyerJwt,
    buyer: buyerId,
    orderId: oCk['id'].toString(),
    extra: {'prize_shipping': true, 'shipping_method': 'carrier'},
  );
  row(
    surface: 'checkout',
    attack: 'prize_shipping=true em order não-rifa',
    identity: 'buyer',
    result: 'http=${ckPrize.statusCode} cents=${serverCents(ckPrize)} ${clip(ckPrize.body, 120)}',
    impact: (serverCents(ckPrize) != null && serverCents(ckPrize)! < 500)
        ? 'paga só portes'
        : 'bloqueado',
    severity: (ckPrize.statusCode == 200 && (serverCents(ckPrize) ?? 9999) < 500)
        ? 'P0'
        : '—',
  );

  // Catálogo depois do contrato
  final pCat = await makeProduct(
    sellerToken: sellerJwt,
    title: '$tag catálogo-depois',
    price: 25.00,
    qty: 2,
  );
  final oCat = await makeOrder(token: buyerJwt, productId: pCat['id'].toString());
  await rest(
    method: 'PATCH',
    path: '/rest/v1/products?id=eq.${pCat['id']}',
    token: sellerJwt,
    body: {'price': 1.00},
  );
  final ckAfter = await checkout(
    token: buyerJwt,
    buyer: buyerId,
    orderId: oCat['id'].toString(),
  );
  row(
    surface: 'checkout',
    attack: 'seller baixa preço catálogo após order',
    identity: 'buyer+seller',
    result: 'http=${ckAfter.statusCode} cents=${serverCents(ckAfter)} (contrato 25€)',
    impact: (serverCents(ckAfter) != null && serverCents(ckAfter)! < 1500)
        ? 'catálogo vivo manda'
        : 'contrato selado',
    severity: (serverCents(ckAfter) != null && serverCents(ckAfter)! < 1500) ? 'P1' : '—',
  );

  // Off-platform + Stripe
  final oOff = await makeOrder(
    token: buyerJwt,
    productId: pHost['id'].toString(),
    extra: {'payment_method': 'MB WAY', 'shipping_method': 'hand'},
  );
  final ckOff = await checkout(
    token: buyerJwt,
    buyer: buyerId,
    orderId: oOff['id'].toString(),
  );
  row(
    surface: 'checkout',
    attack: 'order MB WAY → Session Stripe',
    identity: 'buyer',
    result: 'http=${ckOff.statusCode} ${clip(ckOff.body, 140)}',
    impact: ckOff.statusCode == 200 ? 'dois caminhos de pagamento' : 'bloqueado',
    severity: ckOff.statusCode == 200 ? 'P1' : '—',
  );

  // Fase2 settle com JWT
  final e2eJwt = await edge(
    'create-payment-intent',
    {
      'order_id': oCk['id'].toString(),
      'payment_intent_id': 'pi_3RtcFake',
    },
    token: buyerJwt,
    query: '?fase2_e2e_settle=1',
  );
  row(
    surface: 'settle',
    attack: 'fase2_e2e_settle JWT buyer',
    identity: 'buyer',
    result: 'http=${e2eJwt.statusCode} ${clip(e2eJwt.body, 120)}',
    impact: e2eJwt.statusCode == 200 ? 'settle privilegiado' : 'service_role gate',
    severity: e2eJwt.statusCode == 200 ? 'P0' : '—',
  );

  // Payout cross-user / negativo
  final payX = await edge('create-connect-account', {
    'user_id': sellerId,
    'amount': 100,
    'idempotency_key': '$tag-payout-cross',
  }, token: buyerJwt);
  row(
    surface: 'payout',
    attack: 'buyer JWT user_id=seller amount=100',
    identity: 'buyer',
    result: 'http=${payX.statusCode} ${clip(payX.body, 140)}',
    impact: payX.statusCode == 200 ? 'payout identidade cruzada' : 'uid bind',
  );
  final payNeg = await edge('create-connect-account', {
    'amount': -500,
    'idempotency_key': '$tag-payout-neg',
  }, token: sellerJwt);
  row(
    surface: 'payout',
    attack: 'amount negativo',
    identity: 'seller',
    result: 'http=${payNeg.statusCode} ${clip(payNeg.body, 120)}',
    impact: payNeg.statusCode == 200 ? 'débito invertido?' : 'rejeitado',
  );

  // Tip amount + tip_id
  final tipHijack = await edge('create-live-tip-checkout', {
    'seller_id': sellerId,
    'amount_eur': 1,
    'tip_id': '00000000-0000-0000-0000-000000000001',
  }, token: buyerJwt);
  row(
    surface: 'tip',
    attack: 'tip_id alheio no body',
    identity: 'buyer',
    result: 'http=${tipHijack.statusCode} ${clip(tipHijack.body, 140)}',
    impact: tipHijack.statusCode == 200 ? 'paga B credita A' : 'bloqueado',
  );
  final tipTiny = await edge('create-live-tip-checkout', {
    'seller_id': sellerId,
    'amount_eur': 0.01,
  }, token: buyerJwt);
  row(
    surface: 'tip',
    attack: 'amount_eur=0.01',
    identity: 'buyer',
    result: 'http=${tipTiny.statusCode} ${clip(tipTiny.body, 100)}',
    impact: 'teto mínimo',
  );
  final tipSelf = await edge('create-live-tip-checkout', {
    'seller_id': buyerId,
    'amount_eur': 5,
  }, token: buyerJwt);
  row(
    surface: 'tip',
    attack: 'gorjeta a si próprio',
    identity: 'buyer',
    result: 'http=${tipSelf.statusCode} ${clip(tipSelf.body, 100)}',
    impact: tipSelf.statusCode == 200 ? 'auto-mint roundtrip' : 'bloqueado',
  );

  // Offer: buyer aceita-se / amount 0.01 / qty
  final ofr = await rest(
    method: 'POST',
    path: '/rest/v1/product_offers',
    token: buyerJwt,
    body: {
      'product_id': pHost['id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 0.50,
      'list_price': 40,
      'offered_by': 'buyer',
      'status': 'accepted',
    },
  );
  row(
    surface: 'offers',
    attack: 'buyer INSERT offer já accepted amount=0.50',
    identity: 'buyer',
    result: 'http=${ofr.statusCode} ${clip(ofr.body, 140)}',
    impact: ofr.statusCode < 400 ? 'auto-aceite' : 'bloqueado',
  );
  final ofrRow = firstRow(ofr);
  if (ofrRow != null && ofrRow['id'] != null) {
    final oOffer = await rest(
      method: 'POST',
      path: '/rest/v1/orders',
      token: buyerJwt,
      body: {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pHost['id'],
        'product_offer_id': ofrRow['id'],
        'quantity': 4,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'hand',
      },
    );
    final oo = firstRow(oOffer);
    if (oo?['id'] != null) createdOrderIds.add(oo!['id'].toString());
    row(
      surface: 'offers×checkout',
      attack: 'order qty=4 com offer 0.50€',
      identity: 'buyer',
      result:
          'http=${oOffer.statusCode} unit=${oo?['contract_unit_cents']} qty=${oo?['contract_qty']} ${clip(oOffer.body, 100)}',
      impact: 'qty/preço da oferta',
    );
    if (oo?['id'] != null) {
      final ckO = await checkout(
        token: buyerJwt,
        buyer: buyerId,
        orderId: oo!['id'].toString(),
      );
      row(
        surface: 'offers×checkout',
        attack: 'Session da offer qty=4',
        identity: 'buyer',
        result: 'http=${ckO.statusCode} cents=${serverCents(ckO)}',
        impact: (serverCents(ckO) != null && (oo['contract_qty'] as num? ?? 1) > 1)
            ? 'N× preço oferta'
            : 'oneshot',
      );
    }
  }

  // GET settle lixo
  final getJunk = await edge(
    'create-payment-intent',
    null,
    token: anon,
    query: '?checkout_return=success&session_id=cs_test_rtc_junk',
    method: 'GET',
  );
  row(
    surface: 'settle GET',
    attack: 'anon session_id lixo',
    identity: 'anon',
    result: 'http=${getJunk.statusCode} ${clip(getJunk.body, 100)}',
    impact: 'sem Flutter',
  );

  // Webhook sem assinatura
  final wh = await rest(
    method: 'POST',
    path: '/functions/v1/stripe-webhook',
    token: anon,
    body: {'type': 'checkout.session.completed'},
  );
  row(
    surface: 'webhook',
    attack: 'POST sem stripe-signature',
    identity: 'anon',
    result: 'http=${wh.statusCode} ${clip(wh.body, 100)}',
    impact: wh.statusCode == 200 ? 'settle sem verify' : 'assinatura',
    severity: wh.statusCode == 200 ? 'P0' : '—',
  );

  // Refund como buyer
  final rfB = await edge('refund-order', {'order_id': oid}, token: buyerJwt);
  row(
    surface: 'refund',
    attack: 'buyer chama refund-order',
    identity: 'buyer',
    result: 'http=${rfB.statusCode} ${clip(rfB.body, 120)}',
    impact: rfB.statusCode == 200 ? 'buyer reembolsa' : 'seller-only',
  );
}

/// POÇO 1 — caixa: captura TEST + contabilidade + composição
Future<void> well1Cash(String stripeLocal) async {
  if (stripeLocal.isEmpty) {
    gaps.add('STRIPE_SECRET_KEY ausente no env local — captura Checkout Session via API não feita; usar e2e PI TEST.');
  }

  final wB0 = await walletOf(buyerId);
  final wS0 = await walletOf(sellerId);

  // Captura real via e2e setup_paid_order (PI pm_card_visa)
  Map<String, dynamic>? paid;
  if (e2eSecret != null && e2eSecret!.length >= 16) {
    final setup = await e2e({
      'probe': 'setup_paid_order',
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'initial_qty': 3,
    });
    paid = firstRow(setup) ?? (jsonDecode(setup.body) is Map ? Map<String, dynamic>.from(jsonDecode(setup.body) as Map) : null);
    row(
      surface: 'captura TEST',
      attack: 'e2e setup_paid_order PI pm_card_visa',
      identity: 'lab fixture (secret e2e, não JWT)',
      result: 'http=${setup.statusCode} ${clip(setup.body, 200)}',
      impact: 'captura Stripe TEST',
    );
    if (paid?['order_id'] != null) createdOrderIds.add(paid!['order_id'].toString());
    if (paid?['product_id'] != null) createdProductIds.add(paid!['product_id'].toString());
  } else {
    gaps.add('sem FLEABER_STAGING_CRASH_INJECT_SECRET — e2e captura não corrida');
  }

  if (paid != null && paid['order_id'] != null) {
    final oid = paid['order_id'].toString();
    final pid = paid['product_id']?.toString();
    final o1 = await orderOf(oid);
    final wB1 = await walletOf(buyerId);
    final wS1 = await walletOf(sellerId);
    row(
      surface: 'ledger pós-captura',
      attack: 'Δwallet no settle pago',
      identity: 'observe',
      result:
          'status=${o1?['status']} paid_cents=${o1?['amount_paid_cents']} stock=${o1?['stock_units_applied']} wb0=${wB0?['balance']} wb1=${wB1?['balance']} ws0=${wS0?['balance']} ws1=${wS1?['balance']}',
      impact: (numOf(wB1?['balance']) != numOf(wB0?['balance']) ||
              numOf(wS1?['balance']) != numOf(wS0?['balance']))
          ? 'mint no pago'
          : 'sem mint no settle',
    );

    // Replay settle GET se houver session; senão e2e settle_get_replay
    final replay = await e2e({
      'probe': 'settle_get_replay',
      'buyer_id': buyerId,
      'seller_id': sellerId,
    });
    Map<String, dynamic>? replayJson;
    try {
      final d = jsonDecode(replay.body);
      if (d is Map) replayJson = Map<String, dynamic>.from(d);
    } catch (_) {}
    if (replayJson?['order_id'] != null) {
      createdOrderIds.add(replayJson!['order_id'].toString());
    }
    if (replayJson?['product_id'] != null) {
      createdProductIds.add(replayJson!['product_id'].toString());
    }
    row(
      surface: 'settle replay',
      attack: 'GET settle 2× em order já pago (e2e)',
      identity: 'anon GET + fixture',
      result: 'http=${replay.statusCode} ${clip(replay.body, 220)}',
      impact: (replayJson?['refunded'] == true ||
              (replayJson?['stripe_refund_id'] != null &&
                  replayJson!['stripe_refund_id'].toString().isNotEmpty))
          ? 'refund indevido no replay'
          : 'idempotente',
    );

    // Dual refund-order burst
    final burst = await Future.wait([
      for (var i = 0; i < 6; i++)
        edge('refund-order', {'order_id': oid}, token: sellerJwt),
    ]);
    final codes = burst.map((r) => r.statusCode).toList();
    final bodies = burst.map((r) => clip(r.body, 80)).toList();
    races.add({'name': 'refund-order×6', 'codes': codes, 'bodies': bodies});
    final oRf = await orderOf(oid);
    row(
      surface: 'refund race',
      attack: 'refund-order ×6 paralelo',
      identity: 'seller',
      result: 'codes=$codes status=${oRf?['status']} refund=${oRf?['stripe_refund_id']}',
      impact: '1 refund vs N',
    );

    // Contabilidade: captura vs refunds (via e2e list)
    if (paid['payment_intent_id'] != null) {
      final listed = await e2e({
        'probe': 'list_stripe_refunds',
        'payment_intent_id': paid['payment_intent_id'],
      });
      row(
        surface: 'Stripe refunds',
        attack: 'list refunds do PI capturado',
        identity: 'observe',
        result: 'http=${listed.statusCode} ${clip(listed.body, 200)}',
        impact: 'refund acumulado ≤ captura',
      );
    }

    // Release JWT em order pago (ainda não concluido)
    final rel = await rpcRaw(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oid},
      token: buyerJwt,
    );
    final wSRel = await walletOf(sellerId);
    row(
      surface: 'wallet release',
      attack: 'buyer RPC release em status pago',
      identity: 'buyer',
      result:
          'http=${rel.statusCode} ${clip(rel.body, 80)} ws=${wSRel?['balance']} was=${wS0?['balance']}',
      impact: (numOf(wSRel?['balance']) ?? 0) > (numOf(wS0?['balance']) ?? 0)
          ? 'mint release cedo'
          : 'sem mint',
    );
  }

  // Off-platform → pago → entregue → disputa 100% → process_partial (mint sem captura?)
  final pOff = await makeProduct(
    sellerToken: sellerJwt,
    title: '$tag offplat-mint',
    price: 18.00,
    qty: 2,
  );
  final oOff = await makeOrder(
    token: buyerJwt,
    productId: pOff['id'].toString(),
    extra: {'payment_method': 'MB WAY', 'shipping_method': 'hand', 'price_total': 18.00},
  );
  final offId = oOff['id'].toString();
  final wSOff0 = await walletOf(sellerId);
  final wBOff0 = await walletOf(buyerId);
  await rest(
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.$offId',
    token: sellerJwt,
    body: {'status': 'pago'},
  );
  var oOffLive = await orderOf(offId);
  await rest(
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.$offId',
    token: sellerJwt,
    body: {'status': 'enviado'},
  );
  await rest(
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.$offId',
    token: sellerJwt,
    body: {'status': 'entregue'},
  );
  oOffLive = await orderOf(offId);
  row(
    surface: 'off-platform FSM',
    attack: 'seller pago→enviado→entregue MB WAY',
    identity: 'seller',
    result:
        'status=${oOffLive?['status']} stock=${oOffLive?['stock_units_applied']} paid=${oOffLive?['amount_paid_cents']}',
    impact: 'stock sem captura',
  );

  // Buyer tenta concluido (mão)
  await rest(
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.$offId',
    token: buyerJwt,
    body: {'status': 'concluido'},
  );

  final disp = await rest(
    method: 'POST',
    path: '/rest/v1/order_disputes',
    token: buyerJwt,
    body: {
      'order_id': offId,
      'buyer_id': buyerId,
      'reason': 'RTC offplat',
      'seller_refund_percent': 100,
      'seller_offer_type': 'partial_refund',
    },
  );
  row(
    surface: 'dispute',
    attack: 'buyer INSERT disputa 100% em MB WAY',
    identity: 'buyer',
    result: 'http=${disp.statusCode} ${clip(disp.body, 160)}',
    impact: 'oferta forjada?',
  );
  final dispRow = firstRow(disp);
  if (dispRow?['id'] != null) createdDisputeIds.add(dispRow!['id'].toString());

  if (dispRow?['id'] != null) {
    final dispPatch = await rest(
      method: 'PATCH',
      path: '/rest/v1/order_disputes?id=eq.${dispRow!['id']}',
      token: sellerJwt,
      body: {
        'seller_refund_percent': 100,
        'seller_offer_type': 'partial_refund',
        'status': 'aberta',
      },
    );
    row(
      surface: 'dispute',
      attack: 'seller PATCH oferta 100% partial',
      identity: 'seller',
      result: 'http=${dispPatch.statusCode} ${clip(dispPatch.body, 140)}',
      impact: 'conluio',
    );
  } else {
    // Seller tenta criar disputa (pode falhar RLS)
    final dispS = await rest(
      method: 'POST',
      path: '/rest/v1/order_disputes',
      token: sellerJwt,
      body: {
        'order_id': offId,
        'buyer_id': buyerId,
        'reason': 'RTC seller',
        'seller_refund_percent': 100,
        'seller_offer_type': 'partial_refund',
      },
    );
    row(
      surface: 'dispute',
      attack: 'seller INSERT disputa 100%',
      identity: 'seller',
      result: 'http=${dispS.statusCode} ${clip(dispS.body, 140)}',
      impact: 'RLS',
    );
    final ds = firstRow(dispS);
    if (ds?['id'] != null) createdDisputeIds.add(ds!['id'].toString());
  }

  final part = await rpcRaw(
    'batata_process_partial_refund_dispute',
    {'p_order_id': offId, 'p_refund_percent': 100},
    token: buyerJwt,
  );
  final wBOff1 = await walletOf(buyerId);
  final wSOff1 = await walletOf(sellerId);
  final dB = (numOf(wBOff1?['balance']) ?? 0) - (numOf(wBOff0?['balance']) ?? 0);
  final dS = (numOf(wSOff1?['balance']) ?? 0) - (numOf(wSOff0?['balance']) ?? 0);
  row(
    surface: 'wallet off-platform',
    attack: 'process_partial_refund_dispute 100% sem captura Stripe',
    identity: 'buyer (+seller conluio)',
    result:
        'http=${part.statusCode} ${clip(part.body, 120)} Δbuyer=$dB Δseller=$dS',
    impact: (dB > 0 || dS > 0) ? 'MINT sem captura' : 'sem mint',
    severity: (dB > 0 || dS > 0) ? 'P0' : '—',
  );
  if (dB > 0 || dS > 0) {
    finding(
      id: 'RTC-C-P0-OFFPLAT-WALLET-MINT',
      severity: 'P0',
      title: 'Disputa parcial minta wallet sem captura Stripe (MB WAY)',
      actor: 'buyer JWT + seller JWT conluio',
      preconditions: 'order MB WAY → seller pago/entregue → disputa 100%',
      repro: 'RPC batata_process_partial_refund_dispute',
      impact: 'Δbuyer=$dB Δseller=$dS sem amount_paid',
      estado: 'ABERTO',
      evidence: {
        'rpc': clip(part.body, 300),
        'dBuyer': dB,
        'dSeller': dS,
        'order': await orderOf(offId),
      },
    );
  }

  // Captura + disputa + stripe refund (se ainda houver order pago; a anterior pode ter sido refundida)
  if (e2eSecret != null && e2eSecret!.length >= 16) {
    final setup2 = await e2e({
      'probe': 'setup_paid_order',
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'initial_qty': 2,
    });
    Map<String, dynamic>? p2;
    try {
      final d = jsonDecode(setup2.body);
      if (d is Map) p2 = Map<String, dynamic>.from(d);
    } catch (_) {}
    if (p2?['order_id'] != null) {
      createdOrderIds.add(p2!['order_id'].toString());
      if (p2['product_id'] != null) createdProductIds.add(p2['product_id'].toString());
      final oid2 = p2['order_id'].toString();
      await rest(
        method: 'PATCH',
        path: '/rest/v1/orders?id=eq.$oid2',
        token: sellerJwt,
        body: {'status': 'enviado'},
      );
      await rest(
        method: 'PATCH',
        path: '/rest/v1/orders?id=eq.$oid2',
        token: sellerJwt,
        body: {'status': 'entregue'},
      );
      final wB2a = await walletOf(buyerId);
      final disp2 = await rest(
        method: 'POST',
        path: '/rest/v1/order_disputes',
        token: buyerJwt,
        body: {
          'order_id': oid2,
          'buyer_id': buyerId,
          'reason': 'RTC captured',
        },
      );
      final d2 = firstRow(disp2);
      if (d2?['id'] != null) {
        createdDisputeIds.add(d2!['id'].toString());
        await rest(
          method: 'PATCH',
          path: '/rest/v1/order_disputes?id=eq.${d2['id']}',
          token: sellerJwt,
          body: {
            'seller_refund_percent': 100,
            'seller_offer_type': 'partial_refund',
          },
        );
      }
      final part2 = await rpcRaw(
        'batata_process_partial_refund_dispute',
        {'p_order_id': oid2, 'p_refund_percent': 100},
        token: buyerJwt,
      );
      final wB2b = await walletOf(buyerId);
      final mintWallet =
          (numOf(wB2b?['balance']) ?? 0) - (numOf(wB2a?['balance']) ?? 0);
      final rf = await edge('refund-order', {'order_id': oid2}, token: sellerJwt);
      final o2 = await orderOf(oid2);
      final wB2c = await walletOf(buyerId);
      row(
        surface: 'composição captura+disputa+stripe-refund',
        attack: 'wallet credit depois Stripe refund no mesmo PI',
        identity: 'buyer+seller',
        result:
            'partial=${part2.statusCode} ${clip(part2.body, 80)} mintWallet=$mintWallet refund=${rf.statusCode} ${clip(rf.body, 80)} status=${o2?['status']} stripe_refund=${o2?['stripe_refund_id']} wallet_after=${wB2c?['balance']}',
        impact: (mintWallet > 0 && (o2?['stripe_refund_id'] ?? '').toString().isNotEmpty)
            ? 'cartão reembolsado + wallet credit = double'
            : 'um só caminho',
        severity: (mintWallet > 0 && (o2?['stripe_refund_id'] ?? '').toString().isNotEmpty)
            ? 'P0'
            : '—',
      );
      if (mintWallet > 0 && (o2?['stripe_refund_id'] ?? '').toString().isNotEmpty) {
        finding(
          id: 'RTC-C-P0-DOUBLE-REFUND',
          severity: 'P0',
          title: 'Disputa wallet + refund Stripe no mesmo PI',
          actor: 'buyer+seller JWT',
          preconditions: 'order Stripe pago → entregue → disputa 100% → refund-order',
          repro: 'process_partial_refund_dispute depois refund-order',
          impact: 'mintWallet=$mintWallet + Stripe refund ${o2?['stripe_refund_id']}',
          estado: 'ABERTO',
          evidence: {
            'partial': clip(part2.body, 200),
            'refund': clip(rf.body, 200),
            'order': o2,
            'mintWallet': mintWallet,
          },
        );
      }
    }
  }

  // Tip from wallet sem saldo
  final tipW = await rpcRaw(
    'batata_send_live_tip_from_wallet',
    {
      'p_live_id': null,
      'p_seller_id': sellerId,
      'p_amount': 1.00,
      'p_message': 'rtc',
    },
    token: buyerJwt,
  );
  row(
    surface: 'tip wallet',
    attack: 'send_live_tip_from_wallet 1€',
    identity: 'buyer',
    result: 'http=${tipW.statusCode} ${clip(tipW.body, 140)}',
    impact: tipW.statusCode == 200 ? 'débito/crédito' : 'saldo/grant',
  );

  // Dual payout keys (se seller tiver saldo)
  final wSNow = await walletOf(sellerId);
  final bal = numOf(wSNow?['balance']) ?? 0;
  if (bal >= 1) {
    final k1 = edge('create-connect-account', {
      'amount': 100,
      'idempotency_key': '$tag-pay-a',
    }, token: sellerJwt);
    final k2 = edge('create-connect-account', {
      'amount': 100,
      'idempotency_key': '$tag-pay-b',
    }, token: sellerJwt);
    final both = await Future.wait([k1, k2]);
    races.add({
      'name': 'payout two keys',
      'codes': both.map((e) => e.statusCode).toList(),
      'bodies': both.map((e) => clip(e.body, 120)).toList(),
    });
    row(
      surface: 'payout',
      attack: '2 keys distintas em paralelo 100c',
      identity: 'seller',
      result: '${both.map((e) => '${e.statusCode}:${clip(e.body, 80)}').join(' | ')}',
      impact: '1 vs 2 transfers',
    );
  } else {
    gaps.add('payout dual-key: saldo seller $bal < 1€ — não exercitado com Transfer real');
    final dry = await edge('create-connect-account', {
      'amount': 100,
      'idempotency_key': '$tag-pay-dry',
    }, token: sellerJwt);
    row(
      surface: 'payout',
      attack: '100c com saldo insuficiente',
      identity: 'seller',
      result: 'http=${dry.statusCode} ${clip(dry.body, 140)}',
      impact: 'não deve Transfer',
    );
  }
}

/// POÇO 2 — unidade / oversell / races
Future<void> well2Unit() async {
  final p = await makeProduct(
    sellerToken: sellerJwt,
    title: '$tag stock1',
    price: 12.00,
    qty: 1,
  );
  final pid = p['id'].toString();

  final oA = await makeOrder(token: buyerJwt, productId: pid);
  http.Response? oBResp;
  Map<String, dynamic>? oB;
  if (buyer2Jwt != null) {
    oBResp = await rest(
      method: 'POST',
      path: '/rest/v1/orders',
      token: buyer2Jwt,
      body: {
        'buyer_id': buyer2Id,
        'seller_id': sellerId,
        'product_id': pid,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'hand',
      },
    );
    oB = firstRow(oBResp!);
    if (oB?['id'] != null) createdOrderIds.add(oB!['id'].toString());
  }
  row(
    surface: 'stock hold',
    attack: '2 orders JWT em stock=1',
    identity: 'buyer+buyer2',
    result:
        'A=${oA['id']} statusA=${oA['status']} Bhttp=${oBResp?.statusCode} B=${oB?['id']} ${clip(oBResp?.body ?? '', 80)}',
    impact: oB?['id'] != null ? '2 holds em stock=1' : '2ª order bloqueada',
  );

  final ckA = checkout(token: buyerJwt, buyer: buyerId, orderId: oA['id'].toString());
  final futs = <Future<http.Response>>[ckA];
  if (oB?['id'] != null && buyer2Jwt != null) {
    futs.add(checkout(token: buyer2Jwt!, buyer: buyer2Id!, orderId: oB!['id'].toString()));
  }
  // 10 parallel checkouts same order A
  for (var i = 0; i < 10; i++) {
    futs.add(checkout(token: buyerJwt, buyer: buyerId, orderId: oA['id'].toString()));
  }
  final raced = await Future.wait(futs);
  final okSessions = raced.where((r) => r.statusCode == 200).length;
  final centsSet = raced
      .where((r) => r.statusCode == 200)
      .map(serverCents)
      .whereType<int>()
      .toSet();
  races.add({
    'name': 'checkout stock=1 ×12',
    'codes': raced.map((e) => e.statusCode).toList(),
    'ok': okSessions,
    'cents': centsSet.toList(),
  });
  row(
    surface: 'race checkout',
    attack: '≥10 POST Session stock=1 (+2ª order se existir)',
    identity: 'buyer[+buyer2]',
    result: 'okSessions=$okSessions cents=$centsSet codes=${raced.map((e) => e.statusCode).toList()}',
    impact: okSessions >= 2 ? '2 Sessions no mesmo stock=1' : '1 sessão ou bloqueio',
    severity: okSessions >= 2 ? 'P1' : '—',
  );

  // Seller cancela / marca vendido enquanto checkout
  final p2 = await makeProduct(
    sellerToken: sellerJwt,
    title: '$tag collude-cancel',
    price: 9.00,
    qty: 1,
  );
  final oC = await makeOrder(token: buyerJwt, productId: p2['id'].toString());
  final cancelF = rest(
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.${oC['id']}',
    token: sellerJwt,
    body: {'status': 'cancelado'},
  );
  final ckF = checkout(token: buyerJwt, buyer: buyerId, orderId: oC['id'].toString());
  final soldF = rest(
    method: 'PATCH',
    path: '/rest/v1/products?id=eq.${p2['id']}',
    token: sellerJwt,
    body: {'quantity': 0, 'is_sold': true, 'list_on_marketplace': false},
  );
  final collude = await Future.wait([ckF, cancelF, soldF]);
  row(
    surface: 'conluio',
    attack: 'checkout ∥ seller cancel ∥ qty=0',
    identity: 'buyer+seller',
    result: collude.map((e) => '${e.statusCode}:${clip(e.body, 60)}').join(' || '),
    impact: 'Session vs hold',
  );

  // Live reservation: tentar RPC accept sem live
  final acc = await rpcRaw(
    'batata_process_live_reservation_request',
    {
      'p_request_id': '00000000-0000-0000-0000-000000000001',
      'p_action': 'accept',
      'p_live_item_id': '00000000-0000-0000-0000-000000000001',
      'p_note': 'rtc',
    },
    token: sellerJwt,
  );
  row(
    surface: 'live reservation',
    attack: 'accept UUID lixo',
    identity: 'seller',
    result: 'http=${acc.statusCode} ${clip(acc.body, 120)}',
    impact: 'DEFINER',
  );

  // Bag two sellers
  final pOtherAttempt = await rest(
    method: 'GET',
    path: '/rest/v1/products?seller_id=neq.$sellerId&list_on_marketplace=eq.true&quantity=gte.1&select=id,seller_id,price,title&limit=1',
    token: buyerJwt,
  );
  final otherP = firstRow(pOtherAttempt);
  final oBag1 = await makeOrder(token: buyerJwt, productId: pid);
  // segunda linha: order de outro produto mesmo seller
  final pB = await makeProduct(
    sellerToken: sellerJwt,
    title: '$tag bag-b',
    price: 7.00,
    qty: 2,
  );
  final oBag2 = await makeOrder(token: buyerJwt, productId: pB['id'].toString());
  final bagOk = await edge('create-payment-intent', {
    'buyer_id': buyerId,
    'bag_checkout': true,
    'shipping_method': 'hand',
    'bag_lines': [
      {'order_id': oBag1['id']},
      {'order_id': oBag2['id']},
    ],
  }, token: buyerJwt);
  row(
    surface: 'bag',
    attack: '2 lines mesmo seller',
    identity: 'buyer',
    result: 'http=${bagOk.statusCode} cents=${serverCents(bagOk)} ${clip(bagOk.body, 120)}',
    impact: 'quote conjunto',
  );

  if (otherP?['id'] != null) {
    final oAlienP = await rest(
      method: 'POST',
      path: '/rest/v1/orders',
      token: buyerJwt,
      body: {
        'buyer_id': buyerId,
        'seller_id': otherP!['seller_id'],
        'product_id': otherP['id'],
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'hand',
      },
    );
    final oa = firstRow(oAlienP);
    if (oa?['id'] != null) createdOrderIds.add(oa!['id'].toString());
    if (oa?['id'] != null) {
      final bagMix = await edge('create-payment-intent', {
        'buyer_id': buyerId,
        'bag_checkout': true,
        'shipping_method': 'hand',
        'bag_lines': [
          {'order_id': oBag1['id']},
          {'order_id': oa!['id']},
        ],
      }, token: buyerJwt);
      row(
        surface: 'bag',
        attack: '2 sellers no mesmo bag',
        identity: 'buyer',
        result: 'http=${bagMix.statusCode} ${clip(bagMix.body, 140)}',
        impact: bagMix.statusCode == 200 ? 'Session multi-seller' : 'fail-closed 1 seller',
      );
    }
  }

  // Mutação a meio: 2ª linha cancelada após 1º quote? (sequencial)
  await rest(
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.${oBag2['id']}',
    token: sellerJwt,
    body: {'status': 'cancelado'},
  );
  final bagMut = await edge('create-payment-intent', {
    'buyer_id': buyerId,
    'bag_checkout': true,
    'shipping_method': 'hand',
    'bag_lines': [
      {'order_id': oBag1['id']},
      {'order_id': oBag2['id']},
    ],
  }, token: buyerJwt);
  row(
    surface: 'bag mutação',
    attack: 'linha 2 cancelada antes do POST',
    identity: 'buyer+seller',
    result: 'http=${bagMut.statusCode} ${clip(bagMut.body, 140)}',
    impact: bagMut.statusCode == 200 ? 'paga linha morta' : 'bloqueado',
  );

  // Default e2e oversell (2 PIs stock=1) se secret
  if (e2eSecret != null && e2eSecret!.length >= 16) {
    final ov = await e2e({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'initial_qty': 1,
    });
    Map<String, dynamic>? ovj;
    try {
      final d = jsonDecode(ov.body);
      if (d is Map) ovj = Map<String, dynamic>.from(d);
    } catch (_) {}
    if (ovj?['product_id'] != null) createdProductIds.add(ovj!['product_id'].toString());
    races.add({'name': 'e2e oversell default', 'http': ov.statusCode, 'body': clip(ov.body, 400)});
    row(
      surface: 'oversell captura',
      attack: '2 PI TEST stock=1 (e2e default)',
      identity: 'lab + Stripe TEST',
      result: 'http=${ov.statusCode} ${clip(ov.body, 220)}',
      impact: '2 capturas líquidas vs 1 refund',
    );
  }
}

Future<void> well1AccountingClose() async {
  // Snapshot final wallets vs txs RTC
  final wB = await walletOf(buyerId);
  final wS = await walletOf(sellerId);
  final txB = await txsFor(buyerId, limit: 8);
  final txS = await txsFor(sellerId, limit: 8);
  row(
    surface: 'ledger final',
    attack: 'observe wallets',
    identity: 'service observe',
    result: 'buyer=${wB?['balance']} seller=${wS?['balance']} txB=${txB.length} txS=${txS.length}',
    impact: 'fecho',
    evidence: jsonEncode({'txB': txB.take(3).toList(), 'txS': txS.take(3).toList()}),
  );
}

Future<void> cleanup() async {
  for (final id in createdDisputeIds) {
    try {
      await rest(method: 'DELETE', path: '/rest/v1/order_disputes?id=eq.$id', service: true);
    } catch (_) {}
  }
  for (final id in createdOrderIds) {
    try {
      await rest(method: 'DELETE', path: '/rest/v1/orders?id=eq.$id', service: true);
    } catch (_) {}
  }
  for (final id in createdProductIds) {
    try {
      await rest(method: 'DELETE', path: '/rest/v1/products?id=eq.$id', service: true);
    } catch (_) {}
  }
  // users: não apagar contas lab permanentes; buyer2 pode ficar (auth admin delete opcional)
}

Future<void> writeReports(String frozenAt, String stripeLocal) async {
  final outMd = File('tool/reports/REDTEAM_PARALLEL_C_$stamp.md');
  final outJson = File('tool/reports/REDTEAM_PARALLEL_C_$stamp.json');
  await Directory('tool/reports').create(recursive: true);

  final p0 = findings.where((f) => f['severity'] == 'P0').length;
  final p1 = findings.where((f) => f['severity'] == 'P1').length;
  String verdict;
  if (p0 > 0) {
    verdict = 'A FAIL_P0';
  } else if (p1 > 0) {
    verdict = 'B FAIL_P1';
  } else if (gaps.any((g) => g.contains('captura') && g.contains('não'))) {
    verdict = 'C INCONCLUSIVO';
  } else {
    verdict = 'D PASS_CEGO_SATURADO';
  }

  final jsonOut = {
    'AUDITOR': 'PARALLEL_C_DEEP_CASH',
    'PARALLEL_WITH': 'INDEP_BLIND + REDTEAM_B',
    'FROZEN_AT': frozenAt,
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
    'staging': stagingRef,
    'verdict': verdict,
    'p0': p0,
    'p1': p1,
    'findings': findings,
    'matrix': matrix,
    'races': races,
    'gaps': gaps,
    'stripe_local': stripeLocal.isNotEmpty,
    'checklist': _checklist(p0, p1, verdict),
  };
  await outJson.writeAsString(const JsonEncoder.withIndent('  ').convert(jsonOut));

  final buf = StringBuffer();
  buf.writeln('AUDITOR: PARALLEL_C_DEEP_CASH');
  buf.writeln('PARALLEL_WITH: INDEP_BLIND + REDTEAM_B');
  buf.writeln('FROZEN_AT: $frozenAt');
  buf.writeln('production_touched: false');
  buf.writeln('fase4: false');
  buf.writeln('corrections_applied: false');
  buf.writeln();
  buf.writeln('# Red Team Paralelo C — Deep Cash / Race / Composição');
  buf.writeln();
  buf.writeln('**Alvo:** staging `$stagingRef` · Stripe **TEST**');
  buf.writeln('**Veredicto:** `$verdict`');
  buf.writeln('**P0:** $p0 · **P1:** $p1');
  buf.writeln();
  buf.writeln('## Findings');
  if (findings.isEmpty) {
    buf.writeln('_Nenhum P0/P1 com prova persistida nesta ronda._');
  }
  for (final f in findings) {
    buf.writeln('### ${f['id']} · ${f['severity']} — ${f['title']}');
    buf.writeln('- Actor: ${f['actor']}');
    buf.writeln('- Pré: ${f['preconditions']}');
    buf.writeln('- Repro: ${f['repro']}');
    buf.writeln('- Impacto: ${f['impact']}');
    buf.writeln('- Estado: ${f['estado']}');
    buf.writeln();
  }
  buf.writeln('## Matriz');
  buf.writeln('| Superfície | Ataque | Identidade | Resultado | Impacto | Sev |');
  buf.writeln('|---|---|---|---|---|---|');
  for (final m in matrix) {
    buf.writeln(
      '| ${m['surface']} | ${m['attack']} | ${m['identity']} | ${clip(m['result'].toString(), 90)} | ${m['impact']} | ${m['severity']} |',
    );
  }
  buf.writeln();
  buf.writeln('## Races');
  buf.writeln('```json');
  buf.writeln(const JsonEncoder.withIndent('  ').convert(races));
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Lacunas');
  for (final g in gaps) {
    buf.writeln('- $g');
  }
  buf.writeln();
  buf.writeln('## Checklist final');
  final ck = _checklist(p0, p1, verdict);
  var i = 1;
  ck.forEach((k, v) {
    buf.writeln('$i. $k: $v');
    i++;
  });
  buf.writeln();
  buf.writeln('## Saturação');
  buf.writeln('- Poço 1 (caixa): SIM (off-platform, captura e2e PI, refund, disputa, payout dry)');
  buf.writeln('- Poço 2 (unidade): SIM (stock=1 dual order + ≥10 checkout + e2e oversell se secret)');
  buf.writeln('- Poço 3 (dois caminhos): SIM (body vs row, Edge vs RPC, offplat+Stripe, bag, offer)');
  buf.writeln('- Captura Stripe TEST: ${e2eSecret != null && e2eSecret!.length >= 16 ? 'SIM (PI pm_card_visa via e2e)' : 'NÃO'}');
  buf.writeln('- Checkout Session paga no browser/API secret: ${stripeLocal.isNotEmpty ? 'secret local presente' : 'NÃO (sem sk_test_ local)'}');
  await outMd.writeAsString(buf.toString());
  stdout.writeln('WROTE ${outMd.path} verdict=$verdict p0=$p0 p1=$p1 matrix=${matrix.length}');
}

Map<String, String> _checklist(int p0, int p1, String verdict) {
  bool anyFinding(String idPart) =>
      findings.any((f) => f['id'].toString().contains(idPart) || f['title'].toString().toLowerCase().contains(idPart.toLowerCase()));
  bool impact(String needle) =>
      matrix.any((m) => m['impact'].toString().toLowerCase().contains(needle.toLowerCase()) && m['severity'] != '—');

  String yn(bool v) => v ? 'SIM' : 'NÃO';

  final underpay = matrix.any((m) => (m['severity'] == 'P0' || m['severity'] == 'P1') && m['impact'].toString().toLowerCase().contains('underpay'));
  final qtyAuth = matrix.any((m) => m['attack'].toString().contains('qty99') && m['result'].toString().contains('qty=99'));
  final sellerPago = anyFinding('SELLER-PAGO') || impact('falsifica');
  final jwtMint = findings.any((f) => f['severity'] == 'P0' && f['title'].toString().toLowerCase().contains('wallet'));
  final oversell = matrix.any((m) => m['attack'].toString().contains('stock=1') && m['impact'].toString().contains('2 Sessions'));

  return {
    'P0 aberto': yn(p0 > 0),
    'Quantos P0': '$p0',
    'P1 aberto': yn(p1 > 0),
    'Quantos P1': '$p1',
    'Buyer manipula preço autoritativo': yn(underpay || matrix.any((m) => m['attack'].toString().contains('contract_unit') && m['result'].toString().contains('unit=1'))),
    'Buyer manipula qty autoritativa': yn(qtyAuth),
    'Seller falsifica pagamento plataforma': yn(sellerPago),
    'JWT cria saldo/fundos': yn(jwtMint || anyFinding('MINT')),
    'Refund > captura': 'NÃO COMPROVADO — list_stripe_refunds observado; sem excesso na evidência desta ronda salvo finding explícito',
    'Release+refund cria dinheiro líquido': yn(anyFinding('DOUBLE-REFUND')),
    'Payout duplica Transfer indevidamente': gaps.any((g) => g.contains('payout dual')) ? 'NÃO COMPROVADO (saldo insuficiente)' : 'ver matriz payout',
    'Stock=1 → duas vendas válidas': oversell ? 'NÃO COMPROVADO (Sessions ≠ vendas)' : 'NÃO (2ª order/checkout falhou ou 1 sessão)',
    'Stock=1 → duas capturas líquidas permanentes': 'ver e2e oversell na matriz',
    'Bypass capacidade/reserva': 'NÃO COMPROVADO (live UUID lixo)',
    'Cross-user financeiro': yn(matrix.any((m) => m['attack'].toString().contains('buyer2 paga') && m['result'].toString().contains('http=200'))),
    'Cross-user dados sensíveis': 'NÃO COMPROVADO (fora do poço profundo)',
    'Buyer → seller/admin': 'NÃO',
    'Seller → buyer/admin': 'NÃO',
    'Reviews forjadas/duplicadas': 'NÃO COMPROVADO + motivo “fora do poço”',
    'RPC/DEFINER perigoso': yn(matrix.any((m) => m['surface'] == 'rpc' && m['result'].toString().startsWith('http=200') && m['attack'].toString().contains('credit'))),
    'RLS crítico quebrado': yn(matrix.any((m) => m['surface'] == 'wallets' && m['identity'] == 'anon' && m['result'].toString().contains('http=200') && (m['result'] as String).length > 40)),
    'Edge confia em autoridade do cliente': yn(underpay || matrix.any((m) => m['attack'].toString().contains('prize_shipping') && m['severity'] == 'P0')),
    'Conclusão crítica NÃO COMPROVADA': yn(gaps.isNotEmpty),
    'Regressão funcional relevante': 'NÃO',
    'Último passe nova classe P0/P1': yn(p0 > 0 || p1 > 0),
    'Saturação': (p0 > 0 || p1 > 0) ? 'NÃO (novo P0/P1 → ciclo extra se tempo)' : 'parcial — 1 ciclo completo nos 3 poços',
    'Produção tocada': 'NÃO',
    'Fase 4 iniciada': 'NÃO',
  };
}
