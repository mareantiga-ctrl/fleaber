// Independent blind red-team probe — staging only.
// Does not consult prior audit reports. Does not patch. Does not touch production.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stamp = '20260830T1443';
const tag = 'RTI-$stamp';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];
final raceResults = <Map<String, dynamic>>[];
final stripeResults = <Map<String, dynamic>>[];
final gaps = <String>[];

String url = '';
String anon = '';
String svc = '';
String buyerId = '';
String sellerId = '';
String buyerTok = '';
String sellerTok = '';
String? extraTok;
String? extraId;
late LiveOpsStagingClient admin;

String outDir = 'tool/redteam_indep_cega_20260830T1443';

void rec({
  required String surface,
  required String attack,
  required String identity,
  required String result,
  String impact = '',
  String severity = '',
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
  required String pre,
  required String repro,
  required String impact,
  String estado = 'CONFIRMADO',
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
  });
}

Map<String, String> hAnon() => {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Map<String, String> hUser(String tok) => {
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

Future<http.Response> rest(
  String method,
  String path, {
  Map<String, String>? headers,
  Object? body,
}) {
  final uri = Uri.parse('$url$path');
  final hdr = headers ?? hAnon();
  final encoded = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      return http.get(uri, headers: hdr);
    case 'POST':
      return http.post(uri, headers: hdr, body: encoded);
    case 'PATCH':
      return http.patch(uri, headers: hdr, body: encoded);
    case 'DELETE':
      return http.delete(uri, headers: hdr, body: encoded);
    default:
      throw ArgumentError(method);
  }
}

Future<http.Response> rpcRaw(
  String fn,
  Map<String, dynamic> params, {
  Map<String, String>? headers,
}) {
  return rest('POST', '/rest/v1/rpc/$fn', headers: headers, body: params);
}

Future<http.Response> edgeRaw(
  String fn,
  Object body, {
  String? token,
  Map<String, String>? extraHeaders,
  String method = 'POST',
  String query = '',
}) {
  final uri = Uri.parse('$url/functions/v1/$fn$query');
  final hdr = <String, String>{
    'apikey': anon,
    'Authorization': 'Bearer ${token ?? anon}',
    'Content-Type': 'application/json',
    ...?extraHeaders,
  };
  if (method == 'GET') return http.get(uri, headers: hdr);
  return http.post(uri, headers: hdr, body: jsonEncode(body));
}

String clip(String s, [int n = 240]) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= n ? t : '${t.substring(0, n)}…';
}

bool httpOk(int c) => c >= 200 && c < 300;
bool maybeDenied(int c) => c == 401 || c == 403 || c == 425;

List<dynamic> asList(http.Response r) {
  if (r.body.isEmpty) return [];
  try {
    final d = jsonDecode(r.body);
    if (d is List) return d;
    return [d];
  } catch (_) {
    return [];
  }
}

Map<String, dynamic>? asMap(http.Response r) {
  if (r.body.isEmpty) return null;
  try {
    final d = jsonDecode(r.body);
    if (d is Map<String, dynamic>) return d;
    if (d is List && d.isNotEmpty && d.first is Map) {
      return Map<String, dynamic>.from(d.first as Map);
    }
  } catch (_) {}
  return null;
}

Future<Map<String, dynamic>?> svcRow(String table, String filter) async {
  final r = await rest(
    'GET',
    '/rest/v1/$table?$filter&select=*&limit=1',
    headers: hSvc(),
  );
  final list = asList(r);
  if (list.isEmpty || list.first is! Map) return null;
  return Map<String, dynamic>.from(list.first as Map);
}

Future<void> dumpJson(String name, Object data) async {
  final dir = Directory(outDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File('$outDir/$name').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(data),
  );
}

Future<String> createProduct({
  required String seller,
  required double price,
  required int qty,
  String? title,
}) async {
  final row = await admin.insert('products', {
    'seller_id': seller,
    'title': title ?? '$tag ${DateTime.now().toIso8601String()}',
    'price': price,
    'quantity': qty,
    'is_sold': false,
    'list_on_marketplace': true,
    'available_for_live': false,
    'description': 'redteam disposable $tag',
  });
  return row['id'].toString();
}

Future<void> buryProduct(String id) async {
  try {
    await admin.patch('products', 'id=eq.$id', {
      'list_on_marketplace': false,
      'is_sold': true,
      'quantity': 0,
    });
  } catch (_) {}
}

Future<void> cancelOrder(String id) async {
  try {
    await admin.patch('orders', 'id=eq.$id', {'status': 'cancelado'});
  } catch (_) {}
}

Future<Map<String, dynamic>> insertOrderBuyer(Map<String, dynamic> row) async {
  final r = await rest(
    'POST',
    '/rest/v1/orders',
    headers: hUser(buyerTok),
    body: row,
  );
  return {
    'status': r.statusCode,
    'body': clip(r.body, 400),
    'row': asMap(r),
  };
}

void main() async {
  final env = loadLiveOpsStagingEnv();
  url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) {
    stderr.writeln('REFUSED: not staging $projectMust');
    exit(2);
  }
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  admin = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: svc,
  );
  buyerTok = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  sellerTok = await admin.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  stdout.writeln('$tag staging $projectMust signed in');

  await pass1Coverage();
  await dumpJson('pass1.json', {
    'stamp': stamp,
    'project': projectMust,
    'matrix': matrix,
    'findings': findings,
  });

  await pass2Variants();
  await dumpJson('pass2.json', {
    'stamp': stamp,
    'matrix_len': matrix.length,
    'findings': findings,
    'stripe': stripeResults,
  });

  await pass3ComposeRaces();
  await dumpJson('pass3.json', {
    'stamp': stamp,
    'races': raceResults,
    'stripe': stripeResults,
    'findings': findings,
    'matrix': matrix,
    'gaps': gaps,
  });

  stdout.writeln(
    '$tag done matrix=${matrix.length} findings=${findings.length} races=${raceResults.length}',
  );
}

Future<void> pass1Coverage() async {
  stdout.writeln('PASS1 coverage');

  // OpenAPI inventory
  final oa = await http.get(
    Uri.parse('$url/rest/v1/'),
    headers: {
      ...hSvc(),
      'Accept': 'application/openapi+json',
    },
  );
  final tables = <String>[];
  final rpcs = <String>[];
  if (httpOk(oa.statusCode)) {
    try {
      final spec = jsonDecode(oa.body) as Map<String, dynamic>;
      final paths = spec['paths'] as Map<String, dynamic>? ?? {};
      for (final p in paths.keys) {
        if (p.startsWith('/rpc/')) {
          rpcs.add(p.substring(5));
        } else if (p.startsWith('/') && !p.contains('{')) {
          tables.add(p.substring(1));
        }
      }
    } catch (e) {
      gaps.add('openapi_parse: $e');
    }
  } else {
    gaps.add('openapi ${oa.statusCode}');
  }
  rpcs.sort();
  tables.sort();
  await dumpJson('openapi_tables.json', tables);
  await dumpJson('openapi_rpcs.json', rpcs);
  rec(
    surface: 'SCHEMA',
    attack: 'OpenAPI dump',
    identity: 'service_observe',
    result: 'tables=${tables.length} rpcs=${rpcs.length}',
    evidence: 'openapi_tables.json / openapi_rpcs.json',
  );

  final sensitiveTables = [
    'orders',
    'products',
    'wallets',
    'wallet_transactions',
    'wallet_payout_ledger',
    'live_tips',
    'lives',
    'live_items',
    'live_reservation_requests',
    'live_raffles',
    'live_raffle_entries',
    'live_raffle_winners',
    'live_messages',
    'chats',
    'chat_messages',
    'order_disputes',
    'reviews',
    'profiles',
    'stripe_checkout_events',
    'product_offers',
    'notifications',
    'ps_ingest_audit',
    'ps_devices',
    'order_items',
    'bag_items',
    'bags',
  ];

  for (final t in sensitiveTables) {
    if (tables.isNotEmpty && !tables.contains(t)) continue;
    for (final ident in ['anon', 'buyer', 'seller']) {
      final hdr = ident == 'anon'
          ? hAnon()
          : ident == 'buyer'
              ? hUser(buyerTok)
              : hUser(sellerTok);
      final r = await rest('GET', '/rest/v1/$t?select=*&limit=5', headers: hdr);
      final rows = asList(r);
      rec(
        surface: 'RLS/$t',
        attack: 'SELECT * limit 5',
        identity: ident,
        result: '${r.statusCode} n=${rows.length}',
        evidence: clip(r.body, 160),
      );
    }
  }

  // Stream keys column oracle
  for (final ident in ['anon', 'buyer', 'seller']) {
    final hdr = ident == 'anon'
        ? hAnon()
        : ident == 'buyer'
            ? hUser(buyerTok)
            : hUser(sellerTok);
    final r = await rest(
      'GET',
      '/rest/v1/lives?select=id,mux_stream_key,stream_key,mux_live_id&limit=3',
      headers: hdr,
    );
    final leak = r.body.contains('mux_stream_key') &&
        !r.body.contains('permission denied') &&
        httpOk(r.statusCode);
    rec(
      surface: 'LIVE/stream_key',
      attack: 'SELECT mux_stream_key,stream_key',
      identity: ident,
      result: '${r.statusCode} leak_hint=$leak',
      evidence: clip(r.body, 200),
      severity: leak ? 'P1' : '',
    );
    if (leak && ident != 'seller') {
      finding(
        id: 'RTI-STREAM-01',
        severity: 'P1',
        title: 'Stream key readable via PostgREST',
        actor: ident,
        pre: 'lives row exists',
        repro: 'GET /rest/v1/lives?select=mux_stream_key,stream_key',
        impact: 'Hijack ingest / impersonate seller stream',
      );
    }
  }

  // Cross-user order read
  final foreignOrders = await rest(
    'GET',
    '/rest/v1/orders?select=id,buyer_id,seller_id,price_total,status,stripe_payment_intent_id&buyer_id=neq.$buyerId&seller_id=neq.$buyerId&limit=10',
    headers: hUser(buyerTok),
  );
  rec(
    surface: 'ORDERS',
    attack: 'SELECT orders of other parties',
    identity: 'buyer',
    result: '${foreignOrders.statusCode} n=${asList(foreignOrders).length}',
    evidence: clip(foreignOrders.body, 200),
  );

  // Wallet INSERT / UPDATE as JWT
  final wIns = await rest(
    'POST',
    '/rest/v1/wallets',
    headers: hUser(buyerTok),
    body: {'id': buyerId, 'balance': 9999.99},
  );
  rec(
    surface: 'WALLET',
    attack: 'INSERT wallet balance 9999',
    identity: 'buyer',
    result: '${wIns.statusCode}',
    evidence: clip(wIns.body, 180),
  );
  final wUpd = await rest(
    'PATCH',
    '/rest/v1/wallets?id=eq.$buyerId',
    headers: hUser(buyerTok),
    body: {'balance': 8888.88},
  );
  rec(
    surface: 'WALLET',
    attack: 'PATCH own balance 8888',
    identity: 'buyer',
    result: '${wUpd.statusCode}',
    evidence: clip(wUpd.body, 180),
  );
  final afterW = await svcRow('wallets', 'id=eq.$buyerId');
  final bal = afterW == null ? null : afterW['balance'];
  rec(
    surface: 'WALLET',
    attack: 'observe balance after JWT PATCH',
    identity: 'service_observe',
    result: 'balance=$bal',
  );
  if (bal != null && (num.tryParse('$bal') ?? 0) >= 8888) {
    finding(
      id: 'RTI-WALLET-01',
      severity: 'P0',
      title: 'JWT patched wallet balance',
      actor: 'buyer',
      pre: 'authenticated buyer',
      repro: 'PATCH /wallets?id=eq.self {balance:8888.88}',
      impact: 'Arbitrary funds creation',
    );
  }

  final wtIns = await rest(
    'POST',
    '/rest/v1/wallet_transactions',
    headers: hUser(buyerTok),
    body: {
      'wallet_id': buyerId,
      'amount': 500,
      'type': 'venda',
      'description': '$tag mint',
    },
  );
  rec(
    surface: 'LEDGER',
    attack: 'INSERT wallet_transactions credit',
    identity: 'buyer',
    result: '${wtIns.statusCode}',
    evidence: clip(wtIns.body, 180),
  );

  // Privileged RPCs
  final privileged = <String, Map<String, dynamic>>{
    'batata_credit_wallet_once': {
      'p_user_id': buyerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 10,
      'p_type': 'venda',
      'p_description': tag,
    },
    'batata_debit_wallet_once': {
      'p_user_id': sellerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 1,
      'p_type': 'clawback',
    },
    'batata_wallet_payout_debit': {
      'p_user_id': sellerId,
      'p_amount_cents': 100,
      'p_idempotency_key': 'rti-$stamp-payout-x',
    },
    'batata_wallet_apply_tip_once': {
      'p_wallet_id': buyerId,
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 50,
      'p_type': 'gorjeta_recebida',
      'p_description': tag,
    },
    'batata_ensure_wallet': {'p_user_id': sellerId},
    'batata_settle_live_tip_from_stripe': {
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
      'p_stripe_session_id': 'cs_test_fake',
      'p_paid_amount_cents': 500,
    },
    'batata_clawback_seller_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
  };

  // credit_wallet_once signature variants
  for (final e in privileged.entries) {
    for (final ident in ['anon', 'buyer', 'seller']) {
      final hdr = ident == 'anon'
          ? hAnon()
          : ident == 'buyer'
              ? hUser(buyerTok)
              : hUser(sellerTok);
      var r = await rpcRaw(e.key, e.value, headers: hdr);
      // retry credit with alternate arg names if 404/PGRST
      if (e.key == 'batata_credit_wallet_once' &&
          (r.statusCode == 400 || r.statusCode == 404)) {
        r = await rpcRaw(
          e.key,
          {
            'p_wallet_id': buyerId,
            'p_order_id': '00000000-0000-0000-0000-000000000001',
            'p_amount': 10,
            'p_type': 'venda',
            'p_description': tag,
          },
          headers: hdr,
        );
      }
      rec(
        surface: 'RPC/${e.key}',
        attack: 'direct execute',
        identity: ident,
        result: '${r.statusCode}',
        evidence: clip(r.body, 160),
      );
      if (httpOk(r.statusCode) && ident != 'service') {
        finding(
          id: 'RTI-RPC-${e.key}',
          severity: e.key.contains('wallet') || e.key.contains('payout')
              ? 'P0'
              : 'P1',
          title: 'JWT/anon executed privileged RPC ${e.key}',
          actor: ident,
          pre: 'knows function name',
          repro: 'POST /rpc/${e.key}',
          impact: 'Privileged financial or state change',
        );
      }
    }
  }

  // Release wallet as buyer (granted authenticated)
  final rel = await rpcRaw(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    headers: hUser(buyerTok),
  );
  rec(
    surface: 'RPC/release_seller_wallet',
    attack: 'call with random UUID',
    identity: 'buyer',
    result: '${rel.statusCode} ${clip(rel.body, 120)}',
  );

  // Email oracle
  final em = await rpcRaw(
    'batata_find_user_id_by_email',
    {'p_email': envRequire(loadLiveOpsStagingEnv(), 'LIVE_OPS_TEST_SELLER_EMAIL')},
    headers: hUser(buyerTok),
  );
  rec(
    surface: 'PRIVACY/email_oracle',
    attack: 'email → uuid',
    identity: 'buyer',
    result: '${em.statusCode} ${clip(em.body, 120)}',
  );

  // Draw raffle as buyer
  final dr = await rpcRaw(
    'batata_draw_live_raffle_winners',
    {'p_raffle_id': '00000000-0000-0000-0000-000000000001'},
    headers: hUser(buyerTok),
  );
  rec(
    surface: 'RAFFLE',
    attack: 'draw winners as buyer',
    identity: 'buyer',
    result: '${dr.statusCode}',
    evidence: clip(dr.body, 160),
  );

  // Profile escalation
  final pe = await rest(
    'PATCH',
    '/rest/v1/profiles?id=eq.$buyerId',
    headers: hUser(buyerTok),
    body: {'user_type': 'admin', 'is_admin': true},
  );
  rec(
    surface: 'AUTH/profiles',
    attack: 'PATCH user_type=admin is_admin=true',
    identity: 'buyer',
    result: '${pe.statusCode}',
    evidence: clip(pe.body, 180),
  );
  final prof = await svcRow('profiles', 'id=eq.$buyerId');
  rec(
    surface: 'AUTH/profiles',
    attack: 'observe user_type after PATCH',
    identity: 'service_observe',
    result: 'user_type=${prof?['user_type']} is_admin=${prof?['is_admin']}',
  );

  // Edges
  final edgeBodies = <String, Object>{
    'create-payment-intent': {
      'order_id': '00000000-0000-0000-0000-000000000001',
      'amount': 1,
      'quantity': 99,
      'buyer_id': sellerId,
      'seller_id': buyerId,
    },
    'refund-order': {'order_id': '00000000-0000-0000-0000-000000000001'},
    'create-live-tip-checkout': {
      'tip_id': '00000000-0000-0000-0000-000000000001',
      'live_id': '00000000-0000-0000-0000-000000000001',
      'seller_id': sellerId,
      'amount_eur': 1,
    },
    'create-connect-account': {
      'user_id': sellerId,
      'amount': 100,
      'idempotency_key': 'rti-foreign-payout-key',
    },
    'create-mux-live': {'title': '$tag mux hijack attempt'},
    'livekit-mux-publish': {
      'step': 'token',
      'live_id': '00000000-0000-0000-0000-000000000001',
      'stream_key': 'injected',
    },
    'sec-fase2-e2e-oversell': {'probe': true},
    'delete-test-account': {'confirm': 'APAGAR TUDO'},
    'ingest-ocr-reservation': {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'ocr_line_hash': 'abcdefghijkl',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ref_number': 1,
    },
    'ps-pairing-claim': {'code': '000000', 'device_id': 'rti'},
    'stripe-webhook': {'type': 'checkout.session.completed'},
    'send-sms-bulkgate': {
      'user': {'phone': '+351910000000'},
    },
  };

  for (final e in edgeBodies.entries) {
    final rAnon = await edgeRaw(e.key, e.value, token: anon);
    rec(
      surface: 'EDGE/${e.key}',
      attack: 'POST hostile body',
      identity: 'anon',
      result: '${rAnon.statusCode}',
      evidence: clip(rAnon.body, 160),
    );
    final rB = await edgeRaw(e.key, e.value, token: buyerTok);
    rec(
      surface: 'EDGE/${e.key}',
      attack: 'POST hostile body',
      identity: 'buyer',
      result: '${rB.statusCode}',
      evidence: clip(rB.body, 160),
    );
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
        'object': {'id': 'cs_test_fake', 'payment_status': 'paid'}
      }
    }),
  );
  rec(
    surface: 'WEBHOOK',
    attack: 'POST without Stripe signature',
    identity: 'anon',
    result: '${wh.statusCode}',
    evidence: clip(wh.body, 160),
  );

  // Storage list
  for (final bucket in ['fleaber_private', 'chat_media', 'product_media']) {
    final r = await http.get(
      Uri.parse('$url/storage/v1/object/list/$bucket'),
      headers: hUser(buyerTok),
    );
    rec(
      surface: 'STORAGE/$bucket',
      attack: 'list root',
      identity: 'buyer',
      result: '${r.statusCode}',
      evidence: clip(r.body, 160),
    );
  }
}

Future<void> pass2Variants() async {
  stdout.writeln('PASS2 variants / financial authority');
  final catalogPrice = 19.99;
  final pid = await createProduct(
    seller: sellerId,
    price: catalogPrice,
    qty: 3,
    title: '$tag catalog 19.99',
  );

  // A. Hostile price + qty + stripe IDs on INSERT
  final insA = await insertOrderBuyer({
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 99,
    'price_total': 0.01,
    'status': 'pago',
    'payment_method': 'pagamento na app',
    'contract_unit_cents': 1,
    'contract_qty': 1,
    'amount_paid_cents': 1,
    'stripe_payment_intent_id': 'pi_injected_by_client',
    'stripe_checkout_session_id': 'cs_injected_by_client',
  });
  rec(
    surface: 'ORDERS/INSERT',
    attack: 'hostile price/qty/status/stripe/contract',
    identity: 'buyer',
    result: '${insA['status']}',
    evidence: clip('${insA['body']}', 280),
  );
  final rowA = insA['row'] as Map<String, dynamic>?;
  if (rowA != null) {
    final id = rowA['id']?.toString();
    final live = id == null ? rowA : (await svcRow('orders', 'id=eq.$id')) ?? rowA;
    rec(
      surface: 'ORDERS/INSERT',
      attack: 'row after seal (hostile INSERT)',
      identity: 'service_observe',
      result:
          'status=${live['status']} qty=${live['quantity']} price=${live['price_total']} unit=${live['contract_unit_cents']} cq=${live['contract_qty']} pi=${live['stripe_payment_intent_id']} paid=${live['amount_paid_cents']}',
    );
    final unit = int.tryParse('${live['contract_unit_cents']}') ?? 0;
    final qty = int.tryParse('${live['quantity']}') ?? 0;
    final st = '${live['status']}'.toLowerCase();
    if (unit > 0 && unit < (catalogPrice * 100).round() - 1) {
      finding(
        id: 'RTI-PRICE-01',
        severity: 'P0',
        title: 'Buyer sealed contract below catalog',
        actor: 'buyer',
        pre: 'product $pid price $catalogPrice',
        repro: 'INSERT orders with contract_unit_cents=1 / price_total=0.01',
        impact:
            'Authoritative unit=$unit qty=$qty vs catalog ${(catalogPrice * 100).round()}',
      );
    }
    if (qty >= 90) {
      finding(
        id: 'RTI-QTY-01',
        severity: 'P1',
        title: 'Buyer set authoritative qty far above stock',
        actor: 'buyer',
        pre: 'product qty=3',
        repro: 'INSERT orders quantity=99',
        impact: 'qty=$qty persisted',
      );
    }
    if (st == 'pago' || '${live['stripe_payment_intent_id']}' == 'pi_injected_by_client') {
      finding(
        id: 'RTI-PAY-01',
        severity: 'P0',
        title: 'Buyer forged paid/Stripe IDs on INSERT',
        actor: 'buyer',
        pre: 'JWT insert',
        repro: 'INSERT status=pago + stripe_payment_intent_id',
        impact: 'status=$st pi=${live['stripe_payment_intent_id']}',
      );
    }
    if (id != null) await cancelOrder(id);
  }

  // B. payment_method proposta without accepted offer
  final insB = await insertOrderBuyer({
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 1,
    'price_total': 0.50,
    'status': 'pendente',
    'payment_method': 'proposta',
  });
  rec(
    surface: 'ORDERS/PROPOSTA',
    attack: 'INSERT payment_method=proposta price_total=0.50 no offer',
    identity: 'buyer',
    result: '${insB['status']}',
    evidence: clip('${insB['body']}', 280),
  );
  final rowB = insB['row'] as Map<String, dynamic>?;
  String? orderB;
  if (rowB != null) {
    orderB = rowB['id']?.toString();
    final live =
        orderB == null ? rowB : (await svcRow('orders', 'id=eq.$orderB')) ?? rowB;
    rec(
      surface: 'ORDERS/PROPOSTA',
      attack: 'observe sealed contract',
      identity: 'service_observe',
      result:
          'unit=${live['contract_unit_cents']} price=${live['price_total']} offer=${live['product_offer_id']}',
    );
    final unit = int.tryParse('${live['contract_unit_cents']}') ?? 0;
    if (unit > 0 && unit < 1999) {
      finding(
        id: 'RTI-PRICE-02',
        severity: 'P0',
        title: 'Fake proposta string lowered contract without accepted offer',
        actor: 'buyer',
        pre: 'no product_offers accepted',
        repro: 'INSERT orders payment_method=proposta price_total=0.50',
        impact: 'contract_unit_cents=$unit vs catalog 1999',
      );
    }
  }

  // C. Self-accept offer as buyer (insert accepted)
  final offIns = await rest(
    'POST',
    '/rest/v1/product_offers',
    headers: hUser(buyerTok),
    body: {
      'product_id': pid,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 0.50,
      'list_price': catalogPrice,
      'offered_by': 'buyer',
      'status': 'accepted',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    },
  );
  rec(
    surface: 'OFFERS',
    attack: 'INSERT offer already accepted at 0.50',
    identity: 'buyer',
    result: '${offIns.statusCode}',
    evidence: clip(offIns.body, 200),
  );
  final offRow = asMap(offIns);
  if (offRow != null) {
    final oid = offRow['id']?.toString();
    rec(
      surface: 'OFFERS',
      attack: 'observe insert status',
      identity: 'service_observe',
      result: 'status=${offRow['status']} amount=${offRow['amount']}',
    );
    if (oid != null) {
      final acc = await rest(
        'PATCH',
        '/rest/v1/product_offers?id=eq.$oid',
        headers: hUser(buyerTok),
        body: {'status': 'accepted'},
      );
      rec(
        surface: 'OFFERS',
        attack: 'buyer self-accept pending offer',
        identity: 'buyer',
        result: '${acc.statusCode}',
        evidence: clip(acc.body, 180),
      );
    }
  }

  // D. Checkout with hostile amount on a legit-looking order
  final insD = await insertOrderBuyer({
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'quantity': 1,
    'price_total': 0.01,
    'status': 'pendente',
    'payment_method': 'pagamento na app',
  });
  final rowD = insD['row'] as Map<String, dynamic>?;
  String? orderD = rowD?['id']?.toString();
  if (orderD != null) {
    final before = await svcRow('orders', 'id=eq.$orderD');
    final chk = await edgeRaw(
      'create-payment-intent',
      {
        'order_id': orderD,
        'amount': 1,
        'quantity': 50,
        'price_total': 0.01,
        'buyer_id': sellerId,
        'seller_id': buyerId,
        'product_id': pid,
      },
      token: buyerTok,
    );
    rec(
      surface: 'CHECKOUT',
      attack: 'create session with amount=1 qty=50 swapped parties',
      identity: 'buyer',
      result: '${chk.statusCode}',
      evidence: clip(chk.body, 280),
    );
    final body = asMap(chk);
    final amt = body?['amount_total'];
    stripeResults.add({
      'kind': 'SESSION_CREATED',
      'order_id': orderD,
      'http': chk.statusCode,
      'amount_total': amt,
      'contract_unit': before?['contract_unit_cents'],
      'catalog_cents': 1999,
    });
    if (amt is num && amt < 1500) {
      finding(
        id: 'RTI-PRICE-03',
        severity: 'P0',
        title: 'Checkout Session amount below catalog',
        actor: 'buyer',
        pre: 'order $orderD product $pid catalog 19.99',
        repro: 'POST create-payment-intent amount=1',
        impact: 'SESSION amount_total=$amt cents vs catalog 1999',
      );
    }
  }

  // E. Qty authority via PATCH then checkout
  if (orderD != null) {
    final p = await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.$orderD',
      headers: hUser(buyerTok),
      body: {'quantity': 3, 'price_total': 0.01, 'contract_qty': 3},
    );
    rec(
      surface: 'ORDERS/PATCH',
      attack: 'raise qty / lower price on pending order',
      identity: 'buyer',
      result: '${p.statusCode}',
      evidence: clip(p.body, 200),
    );
    final after = await svcRow('orders', 'id=eq.$orderD');
    rec(
      surface: 'ORDERS/PATCH',
      attack: 'observe after PATCH',
      identity: 'service_observe',
      result:
          'qty=${after?['quantity']} cq=${after?['contract_qty']} price=${after?['price_total']} unit=${after?['contract_unit_cents']}',
    );
  }

  // F. Catalog mutation after order (invariant K)
  if (orderD != null) {
    await admin.patch('products', 'id=eq.$pid', {'price': 1.00});
    final chk2 = await edgeRaw(
      'create-payment-intent',
      {'order_id': orderD},
      token: buyerTok,
    );
    rec(
      surface: 'CATALOG×CHECKOUT',
      attack: 'lower catalog price after order then checkout',
      identity: 'seller_collude+buyer',
      result: '${chk2.statusCode}',
      evidence: clip(chk2.body, 220),
    );
    final b2 = asMap(chk2);
    stripeResults.add({
      'kind': 'SESSION_CREATED_AFTER_CATALOG_DROP',
      'order_id': orderD,
      'amount_total': b2?['amount_total'],
    });
    await admin.patch('products', 'id=eq.$pid', {'price': catalogPrice});
  }

  // G. Seller PATCH other product / buyer PATCH seller product
  final pB = await rest(
    'PATCH',
    '/rest/v1/products?id=eq.$pid',
    headers: hUser(buyerTok),
    body: {'price': 0.01, 'quantity': 999},
  );
  rec(
    surface: 'PRODUCTS',
    attack: 'buyer PATCH seller product price/qty',
    identity: 'buyer',
    result: '${pB.statusCode}',
    evidence: clip(pB.body, 160),
  );

  // H. Reviews forge
  final rv = await rest(
    'POST',
    '/rest/v1/reviews',
    headers: hUser(buyerTok),
    body: {
      'buyer_id': sellerId,
      'target_id': sellerId,
      'rating': 5,
      'comment': '$tag forged',
      'author_role': 'comprador',
      'is_automatic': false,
    },
  );
  rec(
    surface: 'REVIEWS',
    attack: 'INSERT review without order, swapped buyer',
    identity: 'buyer',
    result: '${rv.statusCode}',
    evidence: clip(rv.body, 200),
  );

  // I. Dispute on random order
  final dp = await rest(
    'POST',
    '/rest/v1/order_disputes',
    headers: hUser(buyerTok),
    body: {
      'order_id': '00000000-0000-0000-0000-000000000001',
      'opened_by': buyerId,
      'reason': tag,
      'status': 'aberta',
    },
  );
  rec(
    surface: 'DISPUTES',
    attack: 'INSERT dispute on foreign UUID',
    identity: 'buyer',
    result: '${dp.statusCode}',
    evidence: clip(dp.body, 180),
  );

  // J. Refund as buyer
  if (orderD != null) {
    final rf = await edgeRaw('refund-order', {'order_id': orderD}, token: buyerTok);
    rec(
      surface: 'REFUND',
      attack: 'buyer calls refund-order on own unpaid order',
      identity: 'buyer',
      result: '${rf.statusCode}',
      evidence: clip(rf.body, 180),
    );
    final rfS = await edgeRaw(
      'refund-order',
      {'order_id': orderD},
      token: sellerTok,
    );
    rec(
      surface: 'REFUND',
      attack: 'seller refund unpaid order',
      identity: 'seller',
      result: '${rfS.statusCode}',
      evidence: clip(rfS.body, 180),
    );
  }

  // K. Tip pending + stolen session via RPC
  var liveId = '';
  try {
    final liveRow = await admin.insert('lives', {
      'seller_id': sellerId,
      'title': '$tag dummy ended',
      'status': 'ended',
      'is_active': false,
    });
    liveId = liveRow['id'].toString();
  } catch (e) {
    rec(
      surface: 'LIVE',
      attack: 'fixture ended live',
      identity: 'service_fixture',
      result: 'FAIL $e',
    );
  }
  if (liveId.isNotEmpty) {
    final tipRpc = await rpcRaw(
      'batata_create_live_tip_pending',
      {
        'p_live_id': liveId,
        'p_seller_id': sellerId,
        'p_amount': 1,
        'p_message': tag,
        'p_stripe_session_id': 'cs_test_stolen_session',
      },
      headers: hUser(buyerTok),
    );
    rec(
      surface: 'TIPS',
      attack: 'RPC create pending tip with stolen session id',
      identity: 'buyer',
      result: '${tipRpc.statusCode}',
      evidence: clip(tipRpc.body, 200),
    );
    final tipEdge = await edgeRaw(
      'create-live-tip-checkout',
      {
        'live_id': liveId,
        'seller_id': buyerId,
        'amount_eur': 1,
        'tip_id': '00000000-0000-0000-0000-000000000001',
      },
      token: buyerTok,
    );
    rec(
      surface: 'TIPS/EDGE',
      attack: 'checkout with client tip_id + seller=self',
      identity: 'buyer',
      result: '${tipEdge.statusCode}',
      evidence: clip(tipEdge.body, 200),
    );
    final tipOk = await edgeRaw(
      'create-live-tip-checkout',
      {
        'live_id': liveId,
        'seller_id': sellerId,
        'amount_eur': 1,
      },
      token: buyerTok,
    );
    rec(
      surface: 'TIPS/EDGE',
      attack: 'legitimate-shape tip checkout 1€',
      identity: 'buyer',
      result: '${tipOk.statusCode}',
      evidence: clip(tipOk.body, 200),
    );
    try {
      await admin.patch('lives', 'id=eq.$liveId', {
        'status': 'ended',
        'is_active': false,
      });
    } catch (_) {}
  }

  // L. Wallet tip without funds
  final tipW = await rpcRaw(
    'batata_send_live_tip_from_wallet',
    {
      'p_live_id': liveId.isEmpty
          ? '00000000-0000-0000-0000-000000000001'
          : liveId,
      'p_seller_id': sellerId,
      'p_amount': 1,
    },
    headers: hUser(buyerTok),
  );
  rec(
    surface: 'TIPS/WALLET',
    attack: 'send tip from wallet',
    identity: 'buyer',
    result: '${tipW.statusCode}',
    evidence: clip(tipW.body, 180),
  );

  // M. Payout other user via connect edge
  final po = await edgeRaw(
    'create-connect-account',
    {
      'user_id': sellerId,
      'amount': 50,
      'idempotency_key': 'rti-$stamp-xuser',
    },
    token: buyerTok,
  );
  rec(
    surface: 'PAYOUT',
    attack: 'buyer payout to seller user_id 50 cents',
    identity: 'buyer',
    result: '${po.statusCode}',
    evidence: clip(po.body, 200),
  );

  // N. Cross-chat
  final chats = await rest(
    'GET',
    '/rest/v1/chats?select=*&limit=20',
    headers: hUser(buyerTok),
  );
  rec(
    surface: 'CHAT',
    attack: 'SELECT chats',
    identity: 'buyer',
    result: '${chats.statusCode} n=${asList(chats).length}',
  );
  final msgs = await rest(
    'GET',
    '/rest/v1/chat_messages?select=id,chat_id,sender_id,content&limit=20',
    headers: hUser(buyerTok),
  );
  rec(
    surface: 'CHAT',
    attack: 'SELECT chat_messages',
    identity: 'buyer',
    result: '${msgs.statusCode} n=${asList(msgs).length}',
    evidence: clip(msgs.body, 160),
  );

  // O. FSM jump pending → concluido
  if (orderD != null) {
    for (final st in ['pago', 'enviado', 'entregue', 'concluido', 'devolvida']) {
      final u = await rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$orderD',
        headers: hUser(buyerTok),
        body: {'status': st},
      );
      rec(
        surface: 'FSM',
        attack: 'buyer PATCH status=$st',
        identity: 'buyer',
        result: '${u.statusCode}',
        evidence: clip(u.body, 140),
      );
    }
    final afterFsm = await svcRow('orders', 'id=eq.$orderD');
    rec(
      surface: 'FSM',
      attack: 'observe status after jumps',
      identity: 'service_observe',
      result: '${afterFsm?['status']}',
    );
    if ('${afterFsm?['status']}'.toLowerCase() == 'concluido' ||
        '${afterFsm?['status']}'.toLowerCase() == 'pago') {
      finding(
        id: 'RTI-FSM-01',
        severity: 'P1',
        title: 'Buyer jumped order into paid/completed without payment',
        actor: 'buyer',
        pre: 'pending order $orderD',
        repro: 'PATCH status=pago/concluido',
        impact: 'status=${afterFsm?['status']}',
      );
    }
  }

  // P. Settle GET unpaid / garbage session
  final g1 = await edgeRaw(
    'create-payment-intent',
    {},
    token: anon,
    method: 'GET',
    query: '?checkout_return=success&session_id=cs_test_not_real',
  );
  rec(
    surface: 'SETTLE/GET',
    attack: 'success return fake session',
    identity: 'anon',
    result: '${g1.statusCode}',
    evidence: clip(g1.body, 160),
  );

  if (orderB != null) await cancelOrder(orderB);
  if (orderD != null) await cancelOrder(orderD);
  await buryProduct(pid);
}

Future<void> pass3ComposeRaces() async {
  stdout.writeln('PASS3 composition + races');

  // Stock=1 dual order
  final pid = await createProduct(
    seller: sellerId,
    price: 12.00,
    qty: 1,
    title: '$tag stock1',
  );

  Future<Map<String, dynamic>> mkOrder() {
    return insertOrderBuyer({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 12.00,
      'status': 'pendente',
      'payment_method': 'pagamento na app',
    });
  }

  final dual = await Future.wait(List.generate(10, (_) => mkOrder()));
  final okOrders = <String>[];
  for (final d in dual) {
    final row = d['row'] as Map<String, dynamic>?;
    if (d['status'] == 201 || d['status'] == 200) {
      final id = row?['id']?.toString();
      if (id != null) okOrders.add(id);
    }
  }
  raceResults.add({
    'name': 'stock1_10x_order_insert',
    'http_ok': okOrders.length,
    'attempts': 10,
    'order_ids': okOrders,
  });
  rec(
    surface: 'STOCK×ORDERS',
    attack: '10 concurrent INSERT qty=1 product stock=1',
    identity: 'buyer',
    result: 'accepted=${okOrders.length}/10',
    evidence: okOrders.join(','),
  );

  // Dual checkout sessions on two accepted orders (or same)
  final sessions = <Map<String, dynamic>>[];
  final targets = okOrders.take(2).toList();
  if (targets.length >= 2) {
    final r = await Future.wait([
      edgeRaw('create-payment-intent', {'order_id': targets[0]}, token: buyerTok),
      edgeRaw('create-payment-intent', {'order_id': targets[1]}, token: buyerTok),
    ]);
    for (var i = 0; i < r.length; i++) {
      final b = asMap(r[i]);
      sessions.add({
        'order_id': targets[i],
        'http': r[i].statusCode,
        'session': b?['checkoutSessionId'],
        'amount_total': b?['amount_total'],
        'err': clip(r[i].body, 160),
      });
    }
  } else if (okOrders.isNotEmpty) {
    final r = await Future.wait(List.generate(
      2,
      (_) => edgeRaw(
        'create-payment-intent',
        {'order_id': okOrders.first},
        token: buyerTok,
      ),
    ));
    for (final x in r) {
      final b = asMap(x);
      sessions.add({
        'order_id': okOrders.first,
        'http': x.statusCode,
        'session': b?['checkoutSessionId'],
        'amount_total': b?['amount_total'],
      });
    }
  }
  raceResults.add({'name': 'dual_checkout_sessions', 'sessions': sessions});
  rec(
    surface: 'STOCK×SESSIONS',
    attack: 'two concurrent Checkout Sessions on stock=1 capacity',
    identity: 'buyer',
    result:
        'sessions=${sessions.where((s) => s['session'] != null).length} http=${sessions.map((s) => s['http']).toList()}',
  );

  // Two checkouts same order different keys
  if (okOrders.isNotEmpty) {
    final same = okOrders.first;
    final rr = await Future.wait([
      edgeRaw('create-payment-intent', {'order_id': same}, token: buyerTok),
      edgeRaw('create-payment-intent', {'order_id': same}, token: buyerTok),
    ]);
    raceResults.add({
      'name': 'dual_session_same_order',
      'a': clip(rr[0].body, 180),
      'b': clip(rr[1].body, 180),
      'http': [rr[0].statusCode, rr[1].statusCode],
    });
  }

  // Dual refund
  if (okOrders.isNotEmpty) {
    final oid = okOrders.first;
    final rr = await Future.wait([
      edgeRaw('refund-order', {'order_id': oid}, token: sellerTok),
      edgeRaw('refund-order', {'order_id': oid}, token: sellerTok),
    ]);
    raceResults.add({
      'name': 'dual_refund',
      'http': [rr[0].statusCode, rr[1].statusCode],
      'a': clip(rr[0].body, 140),
      'b': clip(rr[1].body, 140),
    });
  }

  // Dual reviews
  if (okOrders.isNotEmpty) {
    final oid = okOrders.first;
    try {
      await admin.patch('orders', 'id=eq.$oid', {'status': 'concluido'});
    } catch (_) {}
    final rr = await Future.wait(List.generate(
      2,
      (_) => rest(
        'POST',
        '/rest/v1/reviews',
        headers: hUser(buyerTok),
        body: {
          'order_id': oid,
          'buyer_id': buyerId,
          'target_id': sellerId,
          'rating': 5,
          'comment': '$tag race',
        },
      ),
    ));
    raceResults.add({
      'name': 'dual_review',
      'http': [rr[0].statusCode, rr[1].statusCode],
      'a': clip(rr[0].body, 140),
      'b': clip(rr[1].body, 140),
    });
    rec(
      surface: 'REVIEWS×RACE',
      attack: 'two concurrent reviews same order',
      identity: 'buyer',
      result: '${rr[0].statusCode}/${rr[1].statusCode}',
      evidence: '${clip(rr[0].body, 80)} | ${clip(rr[1].body, 80)}',
    );
  }

  // Dual payout (buyer, likely insufficient)
  final pay = await Future.wait([
    edgeRaw(
      'create-connect-account',
      {'amount': 100, 'idempotency_key': 'rti-$stamp-pay-a'},
      token: sellerTok,
    ),
    edgeRaw(
      'create-connect-account',
      {'amount': 100, 'idempotency_key': 'rti-$stamp-pay-b'},
      token: sellerTok,
    ),
  ]);
  raceResults.add({
    'name': 'dual_payout_distinct_keys',
    'http': [pay[0].statusCode, pay[1].statusCode],
    'a': clip(pay[0].body, 160),
    'b': clip(pay[1].body, 160),
  });
  final paySame = await Future.wait([
    edgeRaw(
      'create-connect-account',
      {'amount': 100, 'idempotency_key': 'rti-$stamp-pay-same'},
      token: sellerTok,
    ),
    edgeRaw(
      'create-connect-account',
      {'amount': 100, 'idempotency_key': 'rti-$stamp-pay-same'},
      token: sellerTok,
    ),
  ]);
  raceResults.add({
    'name': 'dual_payout_same_key',
    'http': [paySame[0].statusCode, paySame[1].statusCode],
    'a': clip(paySame[0].body, 160),
    'b': clip(paySame[1].body, 160),
  });

  // Release + refund composition on a concluded fixture (no capture)
  if (okOrders.isNotEmpty) {
    final oid = okOrders.first;
    final rel = await rpcRaw(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oid},
      headers: hUser(buyerTok),
    );
    final rf = await edgeRaw('refund-order', {'order_id': oid}, token: sellerTok);
    raceResults.add({
      'name': 'release_then_refund_unpaid',
      'release': '${rel.statusCode} ${clip(rel.body, 100)}',
      'refund': '${rf.statusCode} ${clip(rf.body, 100)}',
    });
    rec(
      surface: 'RELEASE×REFUND',
      attack: 'release then refund on unpaid/forced concluido',
      identity: 'buyer+seller',
      result: 'rel=${rel.statusCode} rf=${rf.statusCode}',
      evidence: '${clip(rel.body, 80)} | ${clip(rf.body, 80)}',
    );
  }

  // Live reservation race if table exists
  try {
    final item = await admin.insert('live_items', {
      'seller_id': sellerId,
      'title': '$tag item',
      'price': 8.0,
      'quantity': 1,
      'status': 'available',
    });
    final iid = item['id'].toString();
    final rr = await Future.wait(List.generate(
      8,
      (_) => rest(
        'POST',
        '/rest/v1/live_reservation_requests',
        headers: hUser(buyerTok),
        body: {
          'live_item_id': iid,
          'buyer_id': buyerId,
          'requested_qty': 1,
          'status': 'accepted',
        },
      ),
    ));
    raceResults.add({
      'name': 'reservation_last_unit',
      'http': rr.map((e) => e.statusCode).toList(),
      'bodies': rr.map((e) => clip(e.body, 80)).toList(),
    });
  } catch (e) {
    rec(
      surface: 'RESERVATIONS',
      attack: 'fixture live_item',
      identity: 'service_fixture',
      result: 'skip $e',
    );
  }

  // Extra identity: disposable user reads seller PII
  try {
    extraId = await admin.createAdminUser(
      email: 'rti-$stamp@staging.fleaber.bot',
      password: 'Rti${stamp}Aa1!',
    );
    extraTok = await admin.signIn(
      email: 'rti-$stamp@staging.fleaber.bot',
      password: 'Rti${stamp}Aa1!',
    );
    final xord = await rest(
      'GET',
      '/rest/v1/orders?select=id,buyer_id,seller_id,price_total,stripe_payment_intent_id&limit=20',
      headers: hUser(extraTok!),
    );
    rec(
      surface: 'CROSS-USER',
      attack: 'fresh user SELECT orders',
      identity: 'extra_jwt',
      result: '${xord.statusCode} n=${asList(xord).length}',
      evidence: clip(xord.body, 160),
    );
    final xw = await rest(
      'GET',
      '/rest/v1/wallets?select=id,balance,stripe_account_id&limit=20',
      headers: hUser(extraTok!),
    );
    rec(
      surface: 'CROSS-USER',
      attack: 'fresh user SELECT wallets',
      identity: 'extra_jwt',
      result: '${xw.statusCode} n=${asList(xw).length}',
      evidence: clip(xw.body, 160),
    );
  } catch (e) {
    gaps.add('extra_user: $e');
  }

  final prodAfter = await svcRow('products', 'id=eq.$pid');
  rec(
    surface: 'STOCK',
    attack: 'observe product after races',
    identity: 'service_observe',
    result:
        'qty=${prodAfter?['quantity']} sold=${prodAfter?['is_sold']} holds_unknown',
  );

  if (okOrders.length >= 2) {
    finding(
      id: 'RTI-STOCK-01',
      severity: 'P1',
      title: 'Multiple pending orders accepted against stock=1',
      actor: 'buyer',
      pre: 'product qty=1',
      repro: '10 parallel INSERT orders quantity=1',
      impact:
          '${okOrders.length} orders persisted; sessions=${sessions.where((s) => s['session'] != null).length}',
      estado: 'CONFIRMADO_PENDING_CAPTURE',
    );
  }

  for (final id in okOrders) {
    await cancelOrder(id);
  }
  await buryProduct(pid);

  // Cleanup extra user best-effort
  if (extraId != null) {
    try {
      await http.delete(
        Uri.parse('$url/auth/v1/admin/users/$extraId'),
        headers: hSvc(),
      );
    } catch (_) {}
  }
}
