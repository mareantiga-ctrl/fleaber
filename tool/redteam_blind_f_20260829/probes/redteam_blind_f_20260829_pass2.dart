/// Red Team cego — PASS 2 variantes + invariantes (orders novas, checkout, races).
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const outDir = 'tool/redteam_blind_f_20260829';

final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];
final notes = <String>[];
final cleanup = <String, dynamic>{
  'order_ids': <String>[],
  'product_ids': <String>[],
};

String clip(Object? v, [int n = 500]) {
  final s = v?.toString() ?? '';
  return s.length <= n ? s : '${s.substring(0, n)}…';
}

void rec({
  required String surface,
  required String attack,
  required String identity,
  required String result,
  required String impact,
  String severity = 'info',
  String evidence = '',
}) {
  matrix.add({
    'surface': surface,
    'attack': attack,
    'identity': identity,
    'result': result,
    'impact': impact,
    'severity': severity,
    'evidence': clip(evidence, 900),
  });
}

void finding({
  required String id,
  required String severity,
  required String title,
  required String actor,
  required String preconditions,
  required String reproduction,
  required String impact,
  String estado = 'COMPROVADO',
  String evidence = '',
}) {
  findings.add({
    'id': id,
    'severity': severity,
    'title': title,
    'actor': actor,
    'preconditions': preconditions,
    'reproduction': reproduction,
    'impact': impact,
    'estado': estado,
    'evidence': clip(evidence, 1500),
  });
}

Future<http.Response> rest(
  LiveOpsStagingClient c, {
  required String method,
  required String path,
  String? token,
  bool service = false,
  Object? body,
  Map<String, String>? extra,
}) {
  final headers = <String, String>{
    'apikey': service ? c.serviceRoleKey : c.anonKey,
    'Authorization':
        'Bearer ${service ? c.serviceRoleKey : (token ?? c.anonKey)}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  if (extra != null) headers.addAll(extra);
  final uri = Uri.parse('${c.url}$path');
  switch (method) {
    case 'GET':
      return http.get(uri, headers: headers);
    case 'POST':
      return http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
    case 'PATCH':
      return http.patch(uri, headers: headers, body: jsonEncode(body ?? {}));
    case 'DELETE':
      return http.delete(uri, headers: headers);
    default:
      throw ArgumentError(method);
  }
}

Future<http.Response> rpcRaw(
  LiveOpsStagingClient c,
  String fn,
  Map<String, dynamic> params, {
  String? token,
  bool service = false,
}) {
  return rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/$fn',
    token: token,
    service: service,
    body: params,
  );
}

Future<http.Response> edge(
  LiveOpsStagingClient c,
  String fn, {
  String? token,
  Object? body,
  String method = 'POST',
  String query = '',
}) {
  final headers = {
    'apikey': c.anonKey,
    'Authorization': 'Bearer ${token ?? c.anonKey}',
    'Content-Type': 'application/json',
  };
  final uri = Uri.parse('${c.url}/functions/v1/$fn$query');
  if (method == 'GET') return http.get(uri, headers: headers);
  return http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
}

List<Map<String, dynamic>> asList(String body) {
  try {
    final d = jsonDecode(body);
    if (d is List) {
      return [for (final e in d) if (e is Map) Map<String, dynamic>.from(e)];
    }
  } catch (_) {}
  return [];
}

Map<String, dynamic>? asMap(String body) {
  try {
    final d = jsonDecode(body);
    if (d is Map) return Map<String, dynamic>.from(d);
  } catch (_) {}
  return null;
}

String? idOf(http.Response r) {
  final list = asList(r.body);
  if (list.isNotEmpty) return list.first['id']?.toString();
  return asMap(r.body)?['id']?.toString();
}

Future<Map<String, dynamic>?> observeOrder(
  LiveOpsStagingClient c,
  String id,
) async {
  final r = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/orders?select=id,status,price_total,quantity,amount_paid_cents,stripe_payment_intent_id,stripe_checkout_session_id,buyer_id,seller_id,contract_unit_cents,contract_qty,payment_method,stock_units_applied,completed_at,wallet_release_processed_at,wallet_refund_processed_at&id=eq.$id',
    service: true,
  );
  final list = asList(r.body);
  return list.isEmpty ? null : list.first;
}

Future<Map<String, dynamic>?> observeProduct(
  LiveOpsStagingClient c,
  String id,
) async {
  final r = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/products?select=id,price,quantity,is_sold,seller_id&id=eq.$id',
    service: true,
  );
  final list = asList(r.body);
  return list.isEmpty ? null : list.first;
}

Future<void> main() async {
  Directory(outDir).createSync(recursive: true);
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(stagingRef)) {
    stderr.writeln('ABORT');
    exit(2);
  }
  final c = LiveOpsStagingClient(
    url: url,
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;

  // OpenAPI via service (observation)
  stdout.writeln('PASS2 OpenAPI service…');
  final oa = await http.get(
    Uri.parse('${c.url}/rest/v1/'),
    headers: {
      'apikey': c.serviceRoleKey,
      'Authorization': 'Bearer ${c.serviceRoleKey}',
      'Accept': 'application/openapi+json',
    },
  );
  final rpcs = <String>[];
  final tables = <String>[];
  if (oa.statusCode == 200) {
    final spec = asMap(oa.body) ?? {};
    final paths = spec['paths'];
    if (paths is Map) {
      for (final k in paths.keys) {
        final p = k.toString();
        if (p.startsWith('/rpc/')) {
          rpcs.add(p.substring(5));
        } else if (p != '/' && !p.startsWith('/rpc')) {
          tables.add(p.replaceFirst('/', ''));
        }
      }
    }
  }
  rpcs.sort();
  tables.sort();
  File('$outDir/openapi_rpc_svc.txt').writeAsStringSync(rpcs.join('\n'));
  File('$outDir/openapi_tables_svc.txt').writeAsStringSync(tables.join('\n'));
  rec(
    surface: 'POSTGREST',
    attack: 'OpenAPI service_observe',
    identity: 'service_observe',
    result: '${oa.statusCode} tables=${tables.length} rpcs=${rpcs.length}',
    impact: 'inventory',
    evidence: 'rpcs_sample=${rpcs.take(30).join(",")}',
  );
  notes.add('svc tables=${tables.length} rpcs=${rpcs.length}');

  // Sensitive RPCs from inventory
  final moneyRpcs = rpcs
      .where(
        (f) =>
            f.contains('wallet') ||
            f.contains('payout') ||
            f.contains('refund') ||
            f.contains('release') ||
            f.contains('settle') ||
            f.contains('tip') ||
            f.contains('admin') ||
            f.contains('paid') ||
            f.contains('credit') ||
            f.contains('ledger') ||
            f.contains('review') ||
            f.contains('raffle') ||
            f.contains('dispute') ||
            f.contains('accept') ||
            f.contains('stock'),
      )
      .toList();
  notes.add('money_rpc_candidates=${moneyRpcs.length}');

  stdout.writeln('PASS2 fixtures…');
  Future<String> makeProduct({
    required double price,
    required int qty,
    String suffix = '',
  }) async {
    final r = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/products',
      token: sellerTok,
      body: {
        'seller_id': sellerId,
        'title': 'RTF2-$stamp$suffix',
        'price': price,
        'quantity': qty,
        'list_on_marketplace': true,
        'is_sold': false,
      },
    );
    if (r.statusCode >= 300) {
      throw HttpException('product ${r.statusCode} ${r.body}');
    }
    final id = idOf(r)!;
    (cleanup['product_ids'] as List).add(id);
    return id;
  }

  Future<String> makeOrder({
    required String productId,
    required String token,
    required String buyer,
    Map<String, dynamic> extra = const {},
  }) async {
    final body = {
      'product_id': productId,
      'buyer_id': buyer,
      'seller_id': sellerId,
      'price_total': extra['price_total'] ?? 25.0,
      'status': extra['status'] ?? 'reserva_pendente',
      'quantity': extra['quantity'] ?? 1,
      'payment_method': extra['payment_method'] ?? 'Seguro Fleaber',
      'shipping_method': extra['shipping_method'] ?? 'hand',
      'is_reservation': extra['is_reservation'] ?? true,
      if (extra.containsKey('contract_unit_cents'))
        'contract_unit_cents': extra['contract_unit_cents'],
      if (extra.containsKey('contract_qty'))
        'contract_qty': extra['contract_qty'],
    };
    final r = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/orders',
      token: token,
      body: body,
    );
    rec(
      surface: 'ORDERS',
      attack: 'INSERT ${jsonEncode(extra)} product=$productId',
      identity: buyer == buyerId ? 'buyer' : 'other',
      result: '${r.statusCode} ${clip(r.body, 180)}',
      impact: r.statusCode < 300 ? 'created' : 'blocked',
      evidence: r.body,
    );
    if (r.statusCode >= 300) {
      return '';
    }
    final id = idOf(r);
    if (id == null || id.isEmpty) return '';
    (cleanup['order_ids'] as List).add(id);
    return id;
  }

  final p25 = await makeProduct(price: 25, qty: 5, suffix: '-a');
  final p1stock = await makeProduct(price: 12, qty: 1, suffix: '-stock1');
  final pMbway = await makeProduct(price: 18, qty: 2, suffix: '-mbway');

  // --- A. Checkout authority ---
  stdout.writeln('PASS2 checkout authority…');
  final oCk = await makeOrder(productId: p25, token: buyerTok, buyer: buyerId);
  var row = await observeOrder(c, oCk);
  rec(
    surface: 'CONTRACT',
    attack: 'observe sealed contract after INSERT 25e',
    identity: 'service_observe',
    result: jsonEncode(row),
    impact: 'contract_unit_cents expected 2500',
    evidence: jsonEncode(row),
  );

  Future<void> checkoutCase(String name, Map<String, dynamic> body) async {
    final r = await edge(
      c,
      'create-payment-intent',
      token: buyerTok,
      body: {
        'order_id': oCk,
        'buyer_id': buyerId,
        'shipping_method': 'hand',
        ...body,
      },
    );
    final m = asMap(r.body);
    rec(
      surface: 'CHECKOUT',
      attack: name,
      identity: 'buyer',
      result: '${r.statusCode} amt=${m?['server_amount_cents']} ${clip(r.body, 220)}',
      impact: r.statusCode == 200
          ? 'SESSION CRIADA amt=${m?['server_amount_cents']}'
          : 'blocked',
      evidence: r.body,
    );
    if (r.statusCode == 200) {
      final amt = m?['server_amount_cents'];
      if (amt is num && amt < 2000) {
        finding(
          id: 'F-CK-LOW-$name',
          severity: 'P0',
          title: 'Checkout abaixo do contrato ($name)',
          actor: 'buyer',
          preconditions: 'order $oCk product 25e',
          reproduction: name,
          impact: 'Pagar menos que o preço legítimo',
          evidence: r.body,
        );
      }
    }
  }

  await checkoutCase('baseline hand', {});
  await checkoutCase('amount=50', {'amount': 50});
  await checkoutCase('qty=99', {'quantity': 99});
  await checkoutCase('item_price=0.01', {'item_price': 0.01});
  await checkoutCase('prize_shipping', {'prize_shipping': true, 'shipping_method': 'carrier'});
  await checkoutCase('shipping carrier', {'shipping_method': 'carrier'});
  await checkoutCase('shipping garbage', {'shipping_method': 'gratis'});
  await checkoutCase('wrong product', {'product_id': p1stock});
  await checkoutCase('wrong seller', {'seller_id': buyerId});

  // INSERT with client contract_unit_cents=1
  stdout.writeln('PASS2 client contract seal…');
  final oLow = await makeOrder(
    productId: p25,
    token: buyerTok,
    buyer: buyerId,
    extra: {
      'price_total': 0.01,
      'contract_unit_cents': 1,
      'contract_qty': 99,
      'quantity': 99,
    },
  );
  if (oLow.isEmpty) {
    notes.add('hostile qty=99 INSERT blocked (order_quantity_exceeds_stock)');
  }
  final oSeal = await makeOrder(
    productId: p25,
    token: buyerTok,
    buyer: buyerId,
    extra: {
      'price_total': 0.01,
      'contract_unit_cents': 1,
      'contract_qty': 1,
      'quantity': 1,
    },
  );
  row = oSeal.isEmpty ? null : await observeOrder(c, oSeal);
  rec(
    surface: 'CONTRACT',
    attack: 'INSERT contract_unit=1 qty=1 price_total=0.01',
    identity: 'service_observe',
    result: jsonEncode(row),
    impact: 'did client seal win?',
    evidence: jsonEncode(row),
  );
  final unit = row?['contract_unit_cents'];
  if (unit is num && unit <= 10) {
    finding(
      id: 'F-CONTRACT-CLIENT-SEAL',
      severity: 'P0',
      title: 'Buyer sela contract_unit_cents=1 no INSERT',
      actor: 'buyer JWT',
      preconditions: 'product 25e',
      reproduction: 'POST orders contract_unit_cents=1',
      impact: 'Autoridade de preço no cliente',
      evidence: jsonEncode(row),
    );
  }
  http.Response? ckLow;
  if (oSeal.isNotEmpty) {
    ckLow = await edge(
      c,
      'create-payment-intent',
      token: buyerTok,
      body: {
        'order_id': oSeal,
        'buyer_id': buyerId,
        'shipping_method': 'hand',
        'amount': 50,
      },
    );
  }
    rec(
      surface: 'CHECKOUT',
      attack: 'checkout order with hostile INSERT contract',
      identity: 'buyer',
      result: ckLow == null
          ? 'skipped no order'
          : '${ckLow.statusCode} ${clip(ckLow.body, 250)}',
      impact: 'server_amount vs 25e',
      evidence: ckLow?.body ?? '',
    );
  final lowAmt = asMap(ckLow?.body ?? '')?['server_amount_cents'];
  if (ckLow != null &&
      ckLow.statusCode == 200 &&
      lowAmt is num &&
      lowAmt < 2000) {
    finding(
      id: 'F-CK-HOSTILE-INSERT-LOW',
      severity: 'P0',
      title: 'Checkout honra contrato hostil do INSERT',
      actor: 'buyer',
      preconditions: 'hostile contract seal',
      reproduction: 'create-payment-intent on oLow',
      impact: 'pagar menos',
      evidence: ckLow.body,
    );
  }

  // Catalog drop after seal
  stdout.writeln('PASS2 catalog vs contract…');
  final oCat = await makeOrder(productId: p25, token: buyerTok, buyer: buyerId);
  await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/products?id=eq.$p25',
    token: sellerTok,
    body: {'price': 1.0},
  );
  final ckCat = await edge(
    c,
    'create-payment-intent',
    token: buyerTok,
    body: {
      'order_id': oCat,
      'buyer_id': buyerId,
      'shipping_method': 'hand',
    },
  );
  rec(
    surface: 'CATALOG',
    attack: 'drop catalog 25->1 then checkout existing order',
    identity: 'buyer',
    result: '${ckCat.statusCode} ${clip(ckCat.body, 250)}',
    impact: 'must stay on sealed 25e not 1e',
    evidence: ckCat.body,
  );
  await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/products?id=eq.$p25',
    token: sellerTok,
    body: {'price': 25.0},
  );
  final catAmt = asMap(ckCat.body)?['server_amount_cents'];
  if (ckCat.statusCode == 200 && catAmt is num && catAmt < 500) {
    finding(
      id: 'F-CK-CATALOG-RETRO',
      severity: 'P1',
      title: 'Checkout usa catálogo vivo após drop',
      actor: 'seller+buyer',
      preconditions: 'order sealed then catalog 1e',
      reproduction: 'PATCH product price then checkout',
      impact: 'contrato retroactivo',
      evidence: ckCat.body,
    );
  }

  // --- B. Off-platform seller pago ---
  stdout.writeln('PASS2 MB WAY false pago…');
  final oMb = await makeOrder(
    productId: pMbway,
    token: buyerTok,
    buyer: buyerId,
    extra: {'payment_method': 'MB WAY', 'price_total': 18.0},
  );
  final wBefore = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/wallets?select=id,balance&id=eq.$sellerId',
    service: true,
  );
  final balBefore = asList(wBefore.body).isEmpty
      ? 0
      : num.tryParse('${asList(wBefore.body).first['balance']}') ?? 0;
  final patchPago = await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/orders?id=eq.$oMb',
    token: sellerTok,
    body: {'status': 'pago'},
  );
  rec(
    surface: 'ORDER FSM',
    attack: 'seller PATCH MB WAY -> pago',
    identity: 'seller',
    result: '${patchPago.statusCode} ${clip(patchPago.body, 220)}',
    impact: 'off-platform attest',
    evidence: patchPago.body,
  );
  row = await observeOrder(c, oMb);
  rec(
    surface: 'ORDER FSM',
    attack: 'observe MB WAY after seller pago',
    identity: 'service_observe',
    result: jsonEncode(row),
    impact: 'status/stock/wallet flags',
    evidence: jsonEncode(row),
  );
  final rel = await rpcRaw(
    c,
    'batata_release_seller_wallet_for_order',
    {'p_order_id': oMb},
    token: sellerTok,
  );
  rec(
    surface: 'LEDGER',
    attack: 'seller release wallet after MB WAY pago',
    identity: 'seller',
    result: '${rel.statusCode} ${clip(rel.body, 220)}',
    impact: 'wallet mint from false pago?',
    evidence: rel.body,
  );
  final relBuyer = await rpcRaw(
    c,
    'batata_release_seller_wallet_for_order',
    {'p_order_id': oMb},
    token: buyerTok,
  );
  rec(
    surface: 'LEDGER',
    attack: 'buyer release after MB WAY',
    identity: 'buyer',
    result: '${relBuyer.statusCode} ${clip(relBuyer.body, 200)}',
    impact: 'buyer mint seller wallet?',
    evidence: relBuyer.body,
  );
  final wAfter = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/wallets?select=id,balance&id=eq.$sellerId',
    service: true,
  );
  final balAfter = asList(wAfter.body).isEmpty
      ? 0
      : num.tryParse('${asList(wAfter.body).first['balance']}') ?? 0;
  rec(
    surface: 'WALLET',
    attack: 'seller balance before/after MB WAY pago+release',
    identity: 'service_observe',
    result: 'before=$balBefore after=$balAfter delta=${balAfter - balBefore}',
    impact: (balAfter - balBefore) > 0.01
        ? 'WALLET MINTED without Stripe'
        : 'no mint',
    severity: (balAfter - balBefore) > 0.01 ? 'P0' : 'info',
    evidence: wAfter.body,
  );
  if ((balAfter - balBefore) > 0.01) {
    finding(
      id: 'F-WAL-OFFPLATFORM-MINT',
      severity: 'P0',
      title: 'Seller MB WAY pago cria saldo wallet sem fundos plataforma',
      actor: 'seller JWT',
      preconditions: 'order MB WAY reserva_pendente',
      reproduction: 'PATCH status=pago + batata_release_seller_wallet_for_order',
      impact: 'criação de saldo sem captura Stripe',
      evidence: 'delta=${balAfter - balBefore} order=$oMb',
    );
  }

  // Buyer PATCH concluido after MB WAY pago
  if ((row?['status'] ?? '').toString().toLowerCase() == 'pago') {
    final pCon = await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$oMb',
      token: buyerTok,
      body: {'status': 'concluido'},
    );
    rec(
      surface: 'ORDER FSM',
      attack: 'buyer PATCH concluido after seller pago MB WAY',
      identity: 'buyer',
      result: '${pCon.statusCode} ${clip(pCon.body, 200)}',
      impact: 'skip logistics',
      evidence: pCon.body,
    );
    final afterC = await observeOrder(c, oMb);
    rec(
      surface: 'ORDER FSM',
      attack: 'observe after buyer concluido',
      identity: 'service_observe',
      result: jsonEncode(afterC),
      impact: 'final status',
      evidence: jsonEncode(afterC),
    );
  }

  // --- C. Reviews on unpaid vs paid ---
  stdout.writeln('PASS2 reviews…');
  final revUnpaid = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/reviews',
    token: buyerTok,
    body: {
      'target_id': sellerId,
      'buyer_id': buyerId,
      'stars': 1,
      'comment': 'rtf unpaid',
      'target_type': 'seller',
      'author_role': 'comprador',
      'order_id': oCk,
    },
  );
  rec(
    surface: 'REVIEWS',
    attack: 'INSERT review on unpaid seguro order',
    identity: 'buyer',
    result: '${revUnpaid.statusCode} ${clip(revUnpaid.body, 220)}',
    impact: revUnpaid.statusCode < 300 ? 'review without pay' : 'blocked',
    evidence: revUnpaid.body,
  );
  if (revUnpaid.statusCode < 300) {
    finding(
      id: 'F-REV-UNPAID',
      severity: 'P1',
      title: 'Review em order não paga',
      actor: 'buyer',
      preconditions: 'reserva_pendente',
      reproduction: 'POST reviews order_id=unpaid',
      impact: 'reputação sem transacção',
      evidence: revUnpaid.body,
    );
    final rid = idOf(revUnpaid);
    if (rid != null) {
      await rest(
        c,
        method: 'DELETE',
        path: '/rest/v1/reviews?id=eq.$rid',
        service: true,
      );
    }
  }

  // Foreign paid order if any
  final paidRows = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/orders?select=id,buyer_id,seller_id,status&status=eq.pago&limit=5',
    service: true,
  );
  final foreignPaid = asList(paidRows.body).where((e) {
    return e['buyer_id'] != buyerId && e['seller_id'] != buyerId;
  }).toList();
  if (foreignPaid.isNotEmpty) {
    final fo = foreignPaid.first;
    final revX = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/reviews',
      token: buyerTok,
      body: {
        'target_id': fo['seller_id'],
        'buyer_id': buyerId,
        'stars': 1,
        'comment': 'rtf foreign order',
        'target_type': 'seller',
        'author_role': 'comprador',
        'order_id': fo['id'],
      },
    );
    rec(
      surface: 'REVIEWS',
      attack: 'INSERT review on foreign paid order',
      identity: 'buyer',
      result: '${revX.statusCode} ${clip(revX.body, 220)}',
      impact: revX.statusCode < 300 ? 'cross-user review' : 'blocked',
      evidence: revX.body,
    );
    if (revX.statusCode < 300) {
      finding(
        id: 'F-REV-FOREIGN',
        severity: 'P1',
        title: 'Review em order alheia',
        actor: 'buyer',
        preconditions: 'know UUID',
        reproduction: 'POST reviews order_id=foreign pago',
        impact: 'fraude reputacional cross-user',
        evidence: revX.body,
      );
      final rid = idOf(revX);
      if (rid != null) {
        await rest(
          c,
          method: 'DELETE',
          path: '/rest/v1/reviews?id=eq.$rid',
          service: true,
        );
      }
    }
  } else {
    notes.add('no foreign paid orders for review cross-user');
  }

  // --- D. Mux as buyer ---
  stdout.writeln('PASS2 mux/tips/sms…');
  final mux = await edge(
    c,
    'create-mux-live',
    token: buyerTok,
    body: {'title': 'RTF2 buyer live hijack'},
  );
  rec(
    surface: 'MUX',
    attack: 'buyer create-mux-live with title',
    identity: 'buyer',
    result: '${mux.statusCode} ${clip(mux.body, 250)}',
    impact: mux.statusCode == 200 ? 'buyer got stream key?' : 'blocked',
    evidence: mux.body,
  );
  if (mux.statusCode == 200 &&
      (mux.body.contains('stream_key') || mux.body.contains('streamKey'))) {
    finding(
      id: 'F-MUX-BUYER-KEY',
      severity: 'P1',
      title: 'Buyer cria live Mux e recebe stream key',
      actor: 'buyer',
      preconditions: 'none',
      reproduction: 'POST create-mux-live title=...',
      impact: 'custo Mux / ingest',
      evidence: mux.body,
    );
  }

  // Tip pending then settle without stripe
  final tipCreate = await rpcRaw(
    c,
    'batata_create_live_tip_pending',
    {
      'p_live_id': null,
      'p_seller_id': sellerId,
      'p_amount': 5,
      'p_message': 'rtf2',
    },
    token: buyerTok,
  );
  rec(
    surface: 'TIPS',
    attack: 'create pending tip amount=5 no live',
    identity: 'buyer',
    result: '${tipCreate.statusCode} ${clip(tipCreate.body, 200)}',
    impact: 'pending tip id',
    evidence: tipCreate.body,
  );
  var tipId = tipCreate.body.replaceAll('"', '').trim();
  if (tipCreate.statusCode == 200 && tipId.length > 10) {
    final settle = await rpcRaw(
      c,
      'batata_settle_live_tip_from_stripe',
      {
        'p_tip_id': tipId,
        'p_stripe_session_id': 'cs_test_fake_$stamp',
        'p_paid_amount_cents': 500,
      },
      token: buyerTok,
    );
    rec(
      surface: 'TIPS',
      attack: 'JWT settle tip with fake session',
      identity: 'buyer',
      result: '${settle.statusCode} ${clip(settle.body, 220)}',
      impact: settle.body.contains('true') ? 'tip minted without stripe' : 'blocked',
      evidence: settle.body,
    );
    if (settle.statusCode == 200 && settle.body.contains('true')) {
      finding(
        id: 'F-TIP-FAKE-SETTLE',
        severity: 'P0',
        title: 'JWT settle tip com session Stripe falsa',
        actor: 'buyer',
        preconditions: 'pending tip',
        reproduction: 'batata_settle_live_tip_from_stripe fake cs',
        impact: 'crédito gorjeta sem captura',
        evidence: settle.body,
      );
    }
    final wTip = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/wallets?select=id,balance&id=eq.$sellerId',
      service: true,
    );
    rec(
      surface: 'TIPS',
      attack: 'seller wallet after fake tip settle',
      identity: 'service_observe',
      result: clip(wTip.body, 200),
      impact: 'detect mint',
      evidence: wTip.body,
    );
    // checkout tip without client tip_id
    final tipCk = await edge(
      c,
      'create-live-tip-checkout',
      token: buyerTok,
      body: {
        'seller_id': sellerId,
        'amount_eur': 1,
        'live_id': null,
      },
    );
    rec(
      surface: 'TIPS',
      attack: 'create-live-tip-checkout amount_eur=1',
      identity: 'buyer',
      result: '${tipCk.statusCode} ${clip(tipCk.body, 250)}',
      impact: tipCk.statusCode == 200 ? 'SESSION CRIADA tip' : 'blocked',
      evidence: tipCk.body,
    );
  }

  final sms = await edge(
    c,
    'send-sms-bulkgate',
    token: buyerTok,
    body: {
      'to': '+351910000000',
      'phone': '+351910000000',
      'message': 'rtf2',
      'text': 'rtf2',
    },
  );
  rec(
    surface: 'EDGE/sms',
    attack: 'send-sms with phone+message',
    identity: 'buyer',
    result: '${sms.statusCode} ${clip(sms.body, 250)}',
    impact: sms.statusCode == 200 && !sms.body.contains('error')
        ? 'SMS sent?'
        : 'blocked_or_hook',
    evidence: sms.body,
  );

  // --- E. Stock race stock=1 two orders ---
  stdout.writeln('PASS2 stock race…');
  final oA = await makeOrder(
    productId: p1stock,
    token: buyerTok,
    buyer: buyerId,
    extra: {'price_total': 12.0},
  );
  // second buyer = fresh
  final freshEmail = 'rtf2.$stamp@fleaber.test';
  final freshPass = 'Teste${stamp}Aa!';
  final freshId = await c.createAdminUser(
    email: freshEmail,
    password: freshPass,
  );
  final freshTok = await c.signIn(email: freshEmail, password: freshPass);
  String? oB;
  try {
    oB = await makeOrder(
      productId: p1stock,
      token: freshTok,
      buyer: freshId,
      extra: {'price_total': 12.0},
    );
  } catch (e) {
    rec(
      surface: 'STOCK',
      attack: 'second buyer INSERT order stock=1',
      identity: 'fresh',
      result: '$e',
      impact: 'second order blocked at insert?',
      evidence: '$e',
    );
  }
  rec(
    surface: 'STOCK',
    attack: 'two orders created against qty=1',
    identity: 'buyer+fresh',
    result: 'oA=$oA oB=$oB',
    impact: oB != null ? 'two holds on last unit' : 'second insert failed',
    evidence: 'product=$p1stock',
  );
  final prodNow = await observeProduct(c, p1stock);
  rec(
    surface: 'STOCK',
    attack: 'product qty after two pending orders',
    identity: 'service_observe',
    result: jsonEncode(prodNow),
    impact: 'capacity consumed at reserve?',
    evidence: jsonEncode(prodNow),
  );

  // Dual checkout
  Future<http.Response> ck(String oid, String tok, String bid) {
    return edge(
      c,
      'create-payment-intent',
      token: tok,
      body: {
        'order_id': oid,
        'buyer_id': bid,
        'shipping_method': 'hand',
      },
    );
  }

  final ckA1 = await ck(oA, buyerTok, buyerId);
  rec(
    surface: 'STOCK',
    attack: 'checkout session A1 stock=1',
    identity: 'buyer',
    result: '${ckA1.statusCode} ${clip(ckA1.body, 220)}',
    impact: ckA1.statusCode == 200 ? 'SESSION CRIADA' : 'blocked',
    evidence: ckA1.body,
  );
  if (oB != null) {
    final ckB1 = await ck(oB, freshTok, freshId);
    rec(
      surface: 'STOCK',
      attack: 'checkout session B1 stock=1 second buyer',
      identity: 'fresh',
      result: '${ckB1.statusCode} ${clip(ckB1.body, 220)}',
      impact: ckB1.statusCode == 200
          ? 'TWO SESSIONS on last unit'
          : 'second session blocked',
      evidence: ckB1.body,
    );
  }
  // Dual sessions same order
  final ckA2 = await ck(oA, buyerTok, buyerId);
  rec(
    surface: 'CHECKOUT',
    attack: 'second session same order A',
    identity: 'buyer',
    result: '${ckA2.statusCode} ${clip(ckA2.body, 220)}',
    impact: ckA2.statusCode == 200 ? 'TWO SESSIONS same order' : 'blocked',
    evidence: ckA2.body,
  );

  // Concurrent 10x checkout same order
  stdout.writeln('PASS2 concurrent checkout…');
  final conc = await Future.wait([
    for (var i = 0; i < 10; i++) ck(oA, buyerTok, buyerId),
  ]);
  final okN = conc.where((r) => r.statusCode == 200).length;
  rec(
    surface: 'CONCURRENCY',
    attack: '10x create-payment-intent same order parallel',
    identity: 'buyer',
    result: 'ok=$okN /10 statuses=${conc.map((e) => e.statusCode).toList()}',
    impact: okN > 1 ? 'multiple sessions' : 'serialized or 1',
    evidence: conc.map((e) => clip(e.body, 80)).join(' | '),
  );

  // Race two INSERT orders stock=1 remaining
  stdout.writeln('PASS2 concurrent insert stock=1 leftover product…');
  final pRace = await makeProduct(price: 9, qty: 1, suffix: '-race');
  final insRace = await Future.wait([
    for (var i = 0; i < 8; i++)
      rest(
        c,
        method: 'POST',
        path: '/rest/v1/orders',
        token: i.isEven ? buyerTok : freshTok,
        body: {
          'product_id': pRace,
          'buyer_id': i.isEven ? buyerId : freshId,
          'seller_id': sellerId,
          'price_total': 9.0,
          'status': 'reserva_pendente',
          'quantity': 1,
          'payment_method': 'Seguro Fleaber',
          'shipping_method': 'hand',
          'is_reservation': true,
        },
      ),
  ]);
  final created = <String>[];
  for (final r in insRace) {
    if (r.statusCode < 300) {
      final id = idOf(r);
      if (id != null) {
        created.add(id);
        (cleanup['order_ids'] as List).add(id);
      }
    }
  }
  rec(
    surface: 'CONCURRENCY',
    attack: '8 parallel INSERT orders on stock=1',
    identity: 'buyer+fresh',
    result:
        'http=${insRace.map((e) => e.statusCode).toList()} created=${created.length}',
    impact: created.length > 1
        ? 'multiple pending on last unit'
        : 'single winner',
    evidence: created.join(','),
  );
  final pAfterRace = await observeProduct(c, pRace);
  rec(
    surface: 'STOCK',
    attack: 'qty after 8 parallel inserts',
    identity: 'service_observe',
    result: jsonEncode(pAfterRace),
    impact: 'oversell at reserve?',
    evidence: jsonEncode(pAfterRace),
  );

  // --- F. Storage other user prefix ---
  stdout.writeln('PASS2 storage/privacy…');
  for (final prefix in [
    '$sellerId/',
    'product_photos/$sellerId/',
    buyerId,
  ]) {
    final ls = await http.post(
      Uri.parse('${c.url}/storage/v1/object/list/chat_media'),
      headers: {
        'apikey': c.anonKey,
        'Authorization': 'Bearer $freshTok',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'prefix': prefix, 'limit': 20}),
    );
    rec(
      surface: 'STORAGE',
      attack: 'fresh list chat_media prefix=$prefix',
      identity: 'fresh',
      result: '${ls.statusCode} ${clip(ls.body, 220)}',
      impact: ls.statusCode == 200 && ls.body.length > 5 && ls.body != '[]'
          ? 'objects listed'
          : 'empty_or_denied',
      evidence: ls.body,
    );
  }

  // lives via views
  for (final t in [
    'lives',
    'lives_public',
    'hub_lives',
    'live_public',
    'v_lives_safe',
  ]) {
    final r = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/$t?select=*&limit=2',
      token: buyerTok,
    );
    rec(
      surface: 'LIVE',
      attack: 'SELECT $t',
      identity: 'buyer',
      result: '${r.statusCode} ${clip(r.body, 180)}',
      impact: r.body.contains('stream_key') ? 'KEY LEAK' : 'ok_or_missing',
      evidence: r.body,
    );
  }

  // Offers schema probe
  final offCols = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/product_offers?select=*&limit=1',
    token: buyerTok,
  );
  rec(
    surface: 'OFFERS',
    attack: 'SELECT product_offers',
    identity: 'buyer',
    result: '${offCols.statusCode} ${clip(offCols.body, 250)}',
    impact: 'schema',
    evidence: offCols.body,
  );

  // Admin profile user_type only
  final pOnly = await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/profiles?id=eq.$buyerId',
    token: buyerTok,
    body: {'user_type': 'admin'},
  );
  rec(
    surface: 'AUTH/PROFILES',
    attack: 'PATCH user_type=admin only',
    identity: 'buyer',
    result: '${pOnly.statusCode} ${clip(pOnly.body, 220)}',
    impact: 'privilege',
    evidence: pOnly.body,
  );
  final pObs = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/profiles?select=id,user_type&id=eq.$buyerId',
    service: true,
  );
  rec(
    surface: 'AUTH/PROFILES',
    attack: 'observe user_type after patch',
    identity: 'service_observe',
    result: clip(pObs.body, 200),
    impact: pObs.body.contains('admin') ? 'ESCALATED' : 'unchanged',
    evidence: pObs.body,
  );

  // Wallet payout 1 cent — may hit Connect; do NOT use huge amounts
  final pay = await edge(
    c,
    'create-connect-account',
    token: buyerTok,
    body: {
      'user_id': sellerId,
      'amount': 1,
      'idempotency_key': 'rtf2_xuser_$stamp',
    },
  );
  rec(
    surface: 'PAYOUT',
    attack: 'buyer payout amount=1 user_id=seller',
    identity: 'buyer',
    result: '${pay.statusCode} ${clip(pay.body, 250)}',
    impact: pay.statusCode == 200 && pay.body.contains('transferId')
        ? 'cross-user payout'
        : 'blocked_or_onboard',
    evidence: pay.body,
  );

  // Bag checkout two orders
  final bag = await edge(
    c,
    'create-payment-intent',
    token: buyerTok,
    body: {
      'buyer_id': buyerId,
      'order_id': oCk,
      'bag_checkout': true,
      'shipping_method': 'hand',
      'bag_lines': [
        {'order_id': oCk, 'line_total_cents': 1},
        if (oSeal.isNotEmpty) {'order_id': oSeal, 'line_total_cents': 1},
      ],
    },
  );
  rec(
    surface: 'BAG',
    attack: 'bag checkout two orders line_total=1',
    identity: 'buyer',
    result: '${bag.statusCode} ${clip(bag.body, 250)}',
    impact: 'bag quote vs line_total',
    evidence: bag.body,
  );

  // Dual refund on cancelled
  final ref1 = await edge(
    c,
    'refund-order',
    token: sellerTok,
    body: {'order_id': oCk},
  );
  rec(
    surface: 'REFUNDS',
    attack: 'seller refund unpaid order',
    identity: 'seller',
    result: '${ref1.statusCode} ${clip(ref1.body, 220)}',
    impact: 'refund without capture',
    evidence: ref1.body,
  );

  // Sweep extra RPCs that look dangerous as buyer
  stdout.writeln('PASS2 rpc sweep money-ish ${moneyRpcs.length}…');
  final rpcHits = <String, String>{};
  for (final fn in moneyRpcs.take(80)) {
    final r = await rpcRaw(c, fn, {}, token: buyerTok);
    rpcHits[fn] = '${r.statusCode} ${clip(r.body, 80)}';
    if (r.statusCode == 200 &&
        !r.body.contains('false') &&
        r.body.trim() != '[]' &&
        r.body.trim() != 'null') {
      rec(
        surface: 'RPC',
        attack: '$fn {}',
        identity: 'buyer',
        result: '${r.statusCode} ${clip(r.body, 180)}',
        impact: 'EXECUTE nonempty',
        evidence: r.body,
      );
    }
  }
  File('$outDir/pass2_rpc_hits.json').writeAsStringSync(jsonEncode(rpcHits));

  // Offers insert with guessed cols
  for (final body in [
    {
      'product_id': p25,
      'buyer_id': buyerId,
      'price': 0.01,
      'status': 'accepted',
    },
    {
      'product_id': p25,
      'buyer_id': buyerId,
      'amount': 0.01,
      'status': 'pending',
    },
  ]) {
    final r = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/product_offers',
      token: buyerTok,
      body: body,
    );
    rec(
      surface: 'OFFERS',
      attack: 'INSERT $body',
      identity: 'buyer',
      result: '${r.statusCode} ${clip(r.body, 200)}',
      impact: r.statusCode < 300 ? 'offer created' : 'blocked',
      evidence: r.body,
    );
  }

  final report = {
    'pass': 2,
    'project': stagingRef,
    'at': DateTime.now().toUtc().toIso8601String(),
    'findings': findings,
    'notes': notes,
    'cleanup': cleanup,
    'rpc_count': rpcs.length,
    'table_count': tables.length,
    'money_rpc_candidates': moneyRpcs,
    'matrix': matrix,
  };
  File('$outDir/pass2_raw.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  stdout.writeln(
    'PASS2 done findings=${findings.length} matrix=${matrix.length}',
  );
}
