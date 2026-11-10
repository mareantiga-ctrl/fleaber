/// Red Team cego independente — PASS 1 cobertura LIVE staging.
/// NÃO usa service_role para demonstrar exploits (só fixture/observação).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const outDir = 'tool/redteam_blind_f_20260829';

final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];
final rpcInventory = <String>[];
final tableInventory = <String>[];
final notes = <String>[];
final cleanup = <String, dynamic>{
  'order_ids': <String>[],
  'product_ids': <String>[],
  'user_ids': <String>[],
};

String clip(Object? v, [int n = 400]) {
  final s = v?.toString() ?? '';
  if (s.length <= n) return s;
  return '${s.substring(0, n)}…';
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
    'evidence': clip(evidence, 800),
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
    'evidence': clip(evidence, 1200),
  });
}

Future<http.Response> rest(
  LiveOpsStagingClient c, {
  required String method,
  required String path,
  String? token,
  bool service = false,
  Object? body,
  Map<String, String>? extraHeaders,
}) async {
  final headers = <String, String>{
    'apikey': service ? c.serviceRoleKey : c.anonKey,
    'Authorization':
        'Bearer ${service ? c.serviceRoleKey : (token ?? c.anonKey)}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  if (extraHeaders != null) headers.addAll(extraHeaders);
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
    case 'HEAD':
      return http.head(uri, headers: headers);
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

Future<http.Response> edgeRaw(
  LiveOpsStagingClient c,
  String fn, {
  String? token,
  Object? body,
  String method = 'POST',
  String query = '',
  Map<String, String>? extraHeaders,
}) async {
  final headers = <String, String>{
    'apikey': c.anonKey,
    'Authorization': 'Bearer ${token ?? c.anonKey}',
    'Content-Type': 'application/json',
  };
  if (extraHeaders != null) headers.addAll(extraHeaders);
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

Future<void> main() async {
  Directory(outDir).createSync(recursive: true);
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(stagingRef)) {
    stderr.writeln('ABORT: not staging $stagingRef');
    exit(2);
  }
  final c = LiveOpsStagingClient(
    url: url,
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  stdout.writeln('PASS1 login…');
  final buyerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerUid = await c.userIdForAccessToken(buyerTok);
  final sellerUid = await c.userIdForAccessToken(sellerTok);
  if (buyerUid != buyerId || sellerUid != sellerId) {
    notes.add('JWT uid mismatch expected=$buyerId/$sellerId got=$buyerUid/$sellerUid');
  }

  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  final freshEmail = 'rtf.blind.$stamp@fleaber.test';
  final freshPass = 'Teste${stamp}Aa!';
  final freshId = await c.createAdminUser(email: freshEmail, password: freshPass);
  (cleanup['user_ids'] as List).add(freshId);
  final freshTok = await c.signIn(email: freshEmail, password: freshPass);

  rec(
    surface: 'AUTH',
    attack: 'password grant lab accounts',
    identity: 'buyer/seller/fresh',
    result: 'OK',
    impact: 'lab identities ready',
    evidence: 'buyer=$buyerUid seller=$sellerUid fresh=$freshId',
  );

  // --- OpenAPI ---
  stdout.writeln('PASS1 OpenAPI…');
  final oa = await http.get(
    Uri.parse('${c.url}/rest/v1/'),
    headers: {
      'apikey': c.anonKey,
      'Authorization': 'Bearer ${c.anonKey}',
      'Accept': 'application/openapi+json',
    },
  );
  rec(
    surface: 'POSTGREST',
    attack: 'OpenAPI dump anon',
    identity: 'anon',
    result: '${oa.statusCode} bytes=${oa.body.length}',
    impact: oa.statusCode == 200 ? 'schema exposed to anon' : 'openapi blocked',
    evidence: clip(oa.body, 200),
  );
  if (oa.statusCode == 200) {
    final spec = asMap(oa.body) ?? {};
    final paths = spec['paths'];
    if (paths is Map) {
      for (final k in paths.keys) {
        final p = k.toString();
        if (p.startsWith('/rpc/')) {
          rpcInventory.add(p.substring(5));
        } else if (p != '/' && !p.startsWith('/rpc')) {
          tableInventory.add(p.replaceFirst('/', ''));
        }
      }
    }
  }
  rpcInventory.sort();
  tableInventory.sort();
  File('$outDir/openapi_rpc.txt').writeAsStringSync(rpcInventory.join('\n'));
  File('$outDir/openapi_tables.txt').writeAsStringSync(tableInventory.join('\n'));
  notes.add('tables=${tableInventory.length} rpcs=${rpcInventory.length}');

  // --- Sensitive table RLS ---
  stdout.writeln('PASS1 RLS matrix…');
  final sensitiveTables = <String>[
    'orders',
    'products',
    'wallets',
    'wallet_transactions',
    'wallet_ledger',
    'wallet_payout_ledger',
    'fleaber_commissions',
    'reviews',
    'order_disputes',
    'dispute_messages',
    'dispute_evidence',
    'chats',
    'chat_messages',
    'lives',
    'live_items',
    'live_tips',
    'live_raffles',
    'live_raffle_winners',
    'live_reservation_requests',
    'profiles',
    'product_offers',
    'seller_bundle_discounts',
    'stripe_checkout_events',
    'app_logs',
    'ps_ingest_audit',
    'ps_pairing_sessions',
    'ps_devices',
    'seller_payout_details',
    'banking_details',
    'user_banking_details',
    'payout_details',
    'complete',
    'storage.objects',
  ];

  Future<void> probeTable(String table, String ident, String? tok) async {
    final sel = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/$table?select=*&limit=5',
      token: tok,
    );
    rec(
      surface: 'RLS/$table',
      attack: 'SELECT * limit 5',
      identity: ident,
      result: '${sel.statusCode} n=${asList(sel.body).length} ${clip(sel.body, 120)}',
      impact: sel.statusCode == 200 && asList(sel.body).isNotEmpty
          ? 'rows visible'
          : 'blocked_or_empty',
      evidence: clip(sel.body, 300),
    );
  }

  for (final t in sensitiveTables) {
    if (t.contains('.')) continue;
    if (tableInventory.isNotEmpty && !tableInventory.contains(t)) {
      // still try — OpenAPI may omit
    }
    await probeTable(t, 'anon', null);
    await probeTable(t, 'buyer', buyerTok);
    await probeTable(t, 'seller', sellerTok);
    await probeTable(t, 'fresh', freshTok);
  }

  // Cross-user order SELECT
  final otherOrders = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/orders?select=id,buyer_id,seller_id,status,price_total,amount_paid_cents,stripe_payment_intent_id&buyer_id=neq.$buyerUid&limit=20',
    token: buyerTok,
  );
  rec(
    surface: 'ORDERS',
    attack: 'SELECT orders where buyer_id != self',
    identity: 'buyer',
    result: '${otherOrders.statusCode} n=${asList(otherOrders.body).length}',
    impact: asList(otherOrders.body).isNotEmpty
        ? 'CROSS-USER order rows'
        : 'no foreign buyer rows',
    severity: asList(otherOrders.body).isNotEmpty ? 'P1' : 'info',
    evidence: clip(otherOrders.body, 400),
  );
  if (asList(otherOrders.body).isNotEmpty) {
    finding(
      id: 'F-ORD-XUSER-SEL',
      severity: 'P1',
      title: 'Buyer lê orders de outros buyers',
      actor: 'buyer JWT',
      preconditions: 'JWT buyer lab',
      reproduction: 'GET /orders?buyer_id=neq.<self>',
      impact: 'Exposição de transacções alheias',
      evidence: otherOrders.body,
    );
  }

  // Lives stream keys
  for (final ident in [
    ['anon', null],
    ['buyer', buyerTok],
    ['seller', sellerTok],
  ]) {
    final r = await rest(
      c,
      method: 'GET',
      path:
          '/rest/v1/lives?select=id,seller_id,status,mux_stream_key,mux_playback_id,stream_key,livekit_room_name&limit=5',
      token: ident[1] as String?,
    );
    final rows = asList(r.body);
    final leaked = rows.any((e) {
      for (final k in ['mux_stream_key', 'stream_key']) {
        final v = (e[k] ?? '').toString().trim();
        if (v.isNotEmpty && v != 'null') return true;
      }
      return false;
    });
    rec(
      surface: 'MUX/LIVE',
      attack: 'SELECT stream keys',
      identity: ident[0] as String,
      result: '${r.statusCode} leaked=$leaked n=${rows.length}',
      impact: leaked ? 'stream key exposure' : 'keys hidden or empty',
      severity: leaked ? 'P1' : 'info',
      evidence: clip(r.body, 400),
    );
    if (leaked) {
      finding(
        id: 'F-MUX-KEY-${ident[0]}',
        severity: 'P1',
        title: 'Stream key Mux visível via PostgREST',
        actor: ident[0] as String,
        preconditions: 'JWT ou anon',
        reproduction: 'GET /lives?select=mux_stream_key',
        impact: 'Hijack ingest RTMP',
        evidence: r.body,
      );
    }
  }

  // Wallet UPDATE as JWT
  stdout.writeln('PASS1 wallet/order mutations…');
  final wSel = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/wallets?select=id,balance,stripe_account_id&id=eq.$buyerUid',
    token: buyerTok,
  );
  rec(
    surface: 'WALLET',
    attack: 'SELECT own wallet',
    identity: 'buyer',
    result: '${wSel.statusCode} ${clip(wSel.body, 200)}',
    impact: 'read own wallet',
    evidence: wSel.body,
  );
  final wPatch = await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/wallets?id=eq.$buyerUid',
    token: buyerTok,
    body: {'balance': 99999.99},
  );
  rec(
    surface: 'WALLET',
    attack: 'PATCH own balance=99999',
    identity: 'buyer',
    result: '${wPatch.statusCode} ${clip(wPatch.body, 200)}',
    impact: wPatch.statusCode < 300 && wPatch.body.contains('99999')
        ? 'JWT minted balance'
        : 'blocked or unchanged',
    severity: wPatch.statusCode < 300 && wPatch.body.contains('99999')
        ? 'P0'
        : 'info',
    evidence: wPatch.body,
  );
  if (wPatch.statusCode < 300) {
    final after = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/wallets?select=id,balance&id=eq.$buyerUid',
      service: true,
    );
    final bal = asList(after.body).isEmpty
        ? null
        : asList(after.body).first['balance'];
    rec(
      surface: 'WALLET',
      attack: 'observe balance after JWT PATCH (service observe)',
      identity: 'service_observe',
      result: '$bal',
      impact: (bal is num && bal >= 99999) ? 'PERSISTED mint' : 'not persisted',
      severity: (bal is num && bal >= 99999) ? 'P0' : 'info',
      evidence: after.body,
    );
    if (bal is num && bal >= 99999) {
      finding(
        id: 'F-WAL-JWT-MINT',
        severity: 'P0',
        title: 'JWT altera wallets.balance',
        actor: 'buyer JWT',
        preconditions: 'wallet row exists',
        reproduction: 'PATCH /wallets?id=eq.self {balance:99999}',
        impact: 'Criação de fundos sem captura',
        evidence: after.body,
      );
    }
  }

  final wIns = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/wallets',
    token: freshTok,
    body: {'id': freshId, 'balance': 5000},
  );
  rec(
    surface: 'WALLET',
    attack: 'INSERT wallet balance=5000',
    identity: 'fresh',
    result: '${wIns.statusCode} ${clip(wIns.body, 200)}',
    impact: wIns.statusCode < 300 ? 'insert attempted' : 'blocked',
    evidence: wIns.body,
  );

  final wX = await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/wallets?id=eq.$sellerUid',
    token: buyerTok,
    body: {'balance': 1},
  );
  rec(
    surface: 'WALLET',
    attack: 'PATCH seller wallet as buyer',
    identity: 'buyer',
    result: '${wX.statusCode} ${clip(wX.body, 180)}',
    impact: wX.statusCode < 300 && asList(wX.body).isNotEmpty
        ? 'cross-user wallet write'
        : 'blocked',
    severity: wX.statusCode < 300 && asList(wX.body).isNotEmpty ? 'P0' : 'info',
    evidence: wX.body,
  );

  // Product as seller (JWT) then hostile order as buyer
  final prodIns = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/products',
    token: sellerTok,
    body: {
      'seller_id': sellerUid,
      'title': 'RTF-BLIND-$stamp',
      'price': 25.00,
      'quantity': 1,
      'list_on_marketplace': true,
      'is_sold': false,
    },
  );
  rec(
    surface: 'PRODUCTS',
    attack: 'INSERT product qty=1 price=25',
    identity: 'seller',
    result: '${prodIns.statusCode} ${clip(prodIns.body, 200)}',
    impact: prodIns.statusCode < 300 ? 'fixture product created via JWT' : 'seller cannot insert product',
    evidence: prodIns.body,
  );
  String? productId;
  if (prodIns.statusCode < 300) {
    final prow = asList(prodIns.body).isNotEmpty
        ? asList(prodIns.body).first
        : asMap(prodIns.body);
    productId = prow?['id']?.toString();
    if (productId != null) (cleanup['product_ids'] as List).add(productId);
  }
  if (productId == null) {
    // fixture via service
    try {
      final row = await c.insert('products', {
        'seller_id': sellerUid,
        'title': 'RTF-BLIND-SVC-$stamp',
        'price': 25.00,
        'quantity': 1,
        'list_on_marketplace': true,
        'is_sold': false,
      });
      productId = row['id']?.toString();
      if (productId != null) (cleanup['product_ids'] as List).add(productId);
      notes.add('product fixture via service_role');
    } catch (e) {
      notes.add('product fixture failed: $e');
    }
  }

  if (productId != null) {
    // Buyer tries insert paid order
    final hostilePaid = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/orders',
      token: buyerTok,
      body: {
        'product_id': productId,
        'buyer_id': buyerUid,
        'seller_id': sellerUid,
        'price_total': 0.01,
        'status': 'pago',
        'quantity': 1,
        'payment_method': 'Seguro Fleaber',
        'shipping_method': 'hand',
        'amount_paid_cents': 999999,
        'stripe_payment_intent_id': 'pi_fake_$stamp',
      },
    );
    rec(
      surface: 'ORDERS',
      attack: 'INSERT status=pago amount_paid huge fake PI',
      identity: 'buyer',
      result: '${hostilePaid.statusCode} ${clip(hostilePaid.body, 250)}',
      impact: hostilePaid.statusCode < 300
          ? 'INSERT accepted — inspect row'
          : 'blocked',
      evidence: hostilePaid.body,
    );
    String? oid;
    if (hostilePaid.statusCode < 300) {
      final orow = asList(hostilePaid.body).isNotEmpty
          ? asList(hostilePaid.body).first
          : asMap(hostilePaid.body);
      oid = orow?['id']?.toString();
      if (oid != null) (cleanup['order_ids'] as List).add(oid);
      final obs = await rest(
        c,
        method: 'GET',
        path:
            '/rest/v1/orders?select=id,status,price_total,amount_paid_cents,stripe_payment_intent_id,stock_units_applied,quantity&id=eq.$oid',
        service: true,
      );
      rec(
        surface: 'ORDERS',
        attack: 'observe hostile INSERT row',
        identity: 'service_observe',
        result: clip(obs.body, 400),
        impact: 'final row after triggers',
        evidence: obs.body,
      );
      final st = asList(obs.body).isEmpty
          ? ''
          : (asList(obs.body).first['status'] ?? '').toString();
      final paid = asList(obs.body).isEmpty
          ? 0
          : Number(asList(obs.body).first['amount_paid_cents']);
      if (st.toLowerCase() == 'pago' || paid > 0) {
        finding(
          id: 'F-ORD-INSERT-PAID',
          severity: 'P0',
          title: 'Buyer INSERT cria order paga / amount_paid',
          actor: 'buyer JWT',
          preconditions: 'produto do seller',
          reproduction: 'POST /orders status=pago amount_paid_cents=999999',
          impact: 'Falsificação de pagamento plataforma',
          evidence: obs.body,
        );
      }
    }

    // Legit pending order then PATCH to pago
    final pending = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/orders',
      token: buyerTok,
      body: {
        'product_id': productId,
        'buyer_id': buyerUid,
        'seller_id': sellerUid,
        'price_total': 1.00,
        'status': 'reserva_pendente',
        'quantity': 1,
        'payment_method': 'Seguro Fleaber',
        'shipping_method': 'hand',
        'is_reservation': true,
      },
    );
    rec(
      surface: 'ORDERS',
      attack: 'INSERT reserva_pendente',
      identity: 'buyer',
      result: '${pending.statusCode} ${clip(pending.body, 200)}',
      impact: pending.statusCode < 300 ? 'pending created' : 'insert blocked',
      evidence: pending.body,
    );
    String? pendingId;
    if (pending.statusCode < 300) {
      final orow = asList(pending.body).isNotEmpty
          ? asList(pending.body).first
          : asMap(pending.body);
      pendingId = orow?['id']?.toString();
      if (pendingId != null) (cleanup['order_ids'] as List).add(pendingId);
    }

    if (pendingId != null) {
      for (final patch in [
        {'status': 'pago'},
        {'status': 'concluido'},
        {'status': 'enviado'},
        {'price_total': 0.50},
        {'quantity': 99},
        {'amount_paid_cents': 12345},
        {'stripe_payment_intent_id': 'pi_injected'},
        {'buyer_id': sellerUid},
        {'seller_id': buyerUid},
        {'contract_unit_cents': 1},
        {'contract_qty': 99},
      ]) {
        final r = await rest(
          c,
          method: 'PATCH',
          path: '/rest/v1/orders?id=eq.$pendingId',
          token: buyerTok,
          body: patch,
        );
        rec(
          surface: 'ORDER FSM',
          attack: 'buyer PATCH $patch',
          identity: 'buyer',
          result: '${r.statusCode} ${clip(r.body, 180)}',
          impact: r.statusCode < 300 && asList(r.body).isNotEmpty
              ? 'PATCH persisted'
              : 'blocked',
          evidence: r.body,
        );
      }
      final after = await rest(
        c,
        method: 'GET',
        path:
            '/rest/v1/orders?select=id,status,price_total,quantity,amount_paid_cents,stripe_payment_intent_id,buyer_id,seller_id,contract_unit_cents,contract_qty&id=eq.$pendingId',
        service: true,
      );
      rec(
        surface: 'ORDER FSM',
        attack: 'final row after buyer patches',
        identity: 'service_observe',
        result: clip(after.body, 500),
        impact: 'authoritative state',
        evidence: after.body,
      );

      // Seller patches
      for (final patch in [
        {'status': 'pago'},
        {'status': 'cancelado'},
        {'price_total': 0.01},
        {'amount_paid_cents': 8888},
      ]) {
        final r = await rest(
          c,
          method: 'PATCH',
          path: '/rest/v1/orders?id=eq.$pendingId',
          token: sellerTok,
          body: patch,
        );
        rec(
          surface: 'ORDER FSM',
          attack: 'seller PATCH $patch',
          identity: 'seller',
          result: '${r.statusCode} ${clip(r.body, 180)}',
          impact: r.statusCode < 300 && asList(r.body).isNotEmpty
              ? 'seller write'
              : 'blocked',
          evidence: r.body,
        );
      }

      // Checkout amount undercut
      final ckLow = await edgeRaw(
        c,
        'create-payment-intent',
        token: buyerTok,
        body: {
          'order_id': pendingId,
          'buyer_id': buyerUid,
          'seller_id': sellerUid,
          'product_id': productId,
          'amount': 50,
          'quantity': 1,
          'item_price': 0.01,
          'shipping': 0,
          'shipping_method': 'hand',
        },
      );
      rec(
        surface: 'CHECKOUT',
        attack: 'create-payment-intent amount=50c vs product 25€',
        identity: 'buyer',
        result: '${ckLow.statusCode} ${clip(ckLow.body, 300)}',
        impact: 'compare server_amount_cents',
        evidence: ckLow.body,
      );
      final ckMap = asMap(ckLow.body);
      final serverAmt = ckMap?['server_amount_cents'];
      if (ckLow.statusCode == 200 && serverAmt is num && serverAmt <= 100) {
        finding(
          id: 'F-CK-UNDERPRICE',
          severity: 'P0',
          title: 'Checkout Session com montante inferior ao contrato',
          actor: 'buyer JWT',
          preconditions: 'order reserva_pendente product 25€',
          reproduction: 'POST create-payment-intent amount=50',
          impact: 'Pagar menos que o preço legítimo',
          evidence: ckLow.body,
        );
      }

      final ckQty = await edgeRaw(
        c,
        'create-payment-intent',
        token: buyerTok,
        body: {
          'order_id': pendingId,
          'buyer_id': buyerUid,
          'quantity': 99,
          'shipping_method': 'hand',
        },
      );
      rec(
        surface: 'CHECKOUT',
        attack: 'create-payment-intent qty=99 in body',
        identity: 'buyer',
        result: '${ckQty.statusCode} ${clip(ckQty.body, 250)}',
        impact: 'qty from body must not win',
        evidence: ckQty.body,
      );

      final ckPrize = await edgeRaw(
        c,
        'create-payment-intent',
        token: buyerTok,
        body: {
          'order_id': pendingId,
          'buyer_id': buyerUid,
          'prize_shipping': true,
          'shipping_method': 'carrier',
        },
      );
      rec(
        surface: 'CHECKOUT',
        attack: 'prize_shipping=true on non-raffle order',
        identity: 'buyer',
        result: '${ckPrize.statusCode} ${clip(ckPrize.body, 250)}',
        impact: ckPrize.statusCode == 200
            ? 'possible prize underpay'
            : 'blocked',
        evidence: ckPrize.body,
      );

      final ckXBuyer = await edgeRaw(
        c,
        'create-payment-intent',
        token: freshTok,
        body: {
          'order_id': pendingId,
          'buyer_id': freshId,
          'shipping_method': 'hand',
        },
      );
      rec(
        surface: 'CHECKOUT',
        attack: 'fresh JWT checkout foreign order claiming self as buyer_id',
        identity: 'fresh',
        result: '${ckXBuyer.statusCode} ${clip(ckXBuyer.body, 250)}',
        impact: ckXBuyer.statusCode == 200 ? 'cross-user checkout' : 'blocked',
        severity: ckXBuyer.statusCode == 200 ? 'P0' : 'info',
        evidence: ckXBuyer.body,
      );

      final ckAnon = await edgeRaw(
        c,
        'create-payment-intent',
        body: {
          'order_id': pendingId,
          'buyer_id': buyerUid,
          'shipping_method': 'hand',
        },
      );
      rec(
        surface: 'CHECKOUT',
        attack: 'anon create-payment-intent',
        identity: 'anon',
        result: '${ckAnon.statusCode} ${clip(ckAnon.body, 200)}',
        impact: ckAnon.statusCode == 200 ? 'unauth checkout' : 'blocked',
        evidence: ckAnon.body,
      );

      final ckSeller = await edgeRaw(
        c,
        'create-payment-intent',
        token: sellerTok,
        body: {
          'order_id': pendingId,
          'buyer_id': sellerUid,
          'shipping_method': 'hand',
        },
      );
      rec(
        surface: 'CHECKOUT',
        attack: 'seller JWT pay buyer order as self',
        identity: 'seller',
        result: '${ckSeller.statusCode} ${clip(ckSeller.body, 200)}',
        impact: 'party swap',
        evidence: ckSeller.body,
      );

      // fase2_e2e_settle as JWT
      final e2e = await edgeRaw(
        c,
        'create-payment-intent',
        token: buyerTok,
        query: '?fase2_e2e_settle=1',
        body: {
          'order_id': pendingId,
          'payment_intent_id': 'pi_1fake',
          'product_id': productId,
        },
      );
      rec(
        surface: 'CHECKOUT',
        attack: 'fase2_e2e_settle as buyer JWT',
        identity: 'buyer',
        result: '${e2e.statusCode} ${clip(e2e.body, 220)}',
        impact: e2e.statusCode == 200 ? 'settle bypass' : 'blocked',
        severity: e2e.statusCode == 200 ? 'P0' : 'info',
        evidence: e2e.body,
      );
    }

    // Product price drop then checkout (catalog vs contract)
    final drop = await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/products?id=eq.$productId',
      token: sellerTok,
      body: {'price': 1.00},
    );
    rec(
      surface: 'CATALOG',
      attack: 'seller drop price 25→1 after order',
      identity: 'seller',
      result: '${drop.statusCode} ${clip(drop.body, 180)}',
      impact: 'catalog change',
      evidence: drop.body,
    );
  }

  // Reviews
  stdout.writeln('PASS1 reviews/disputes/rpc…');
  final revIns = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/reviews',
    token: buyerTok,
    body: {
      'target_id': sellerUid,
      'buyer_id': buyerUid,
      'stars': 1,
      'comment': 'RTF forged no order',
      'target_type': 'seller',
      'author_role': 'comprador',
    },
  );
  rec(
    surface: 'REVIEWS',
    attack: 'INSERT review without order_id',
    identity: 'buyer',
    result: '${revIns.statusCode} ${clip(revIns.body, 220)}',
    impact: revIns.statusCode < 300 ? 'forged review' : 'blocked',
    severity: revIns.statusCode < 300 ? 'P1' : 'info',
    evidence: revIns.body,
  );
  if (revIns.statusCode < 300) {
    finding(
      id: 'F-REV-NO-TX',
      severity: 'P1',
      title: 'Review sem transacção',
      actor: 'buyer JWT',
      preconditions: 'none',
      reproduction: 'POST /reviews without order_id',
      impact: 'Fraude reputacional',
      evidence: revIns.body,
    );
    final rid = asList(revIns.body).isNotEmpty
        ? asList(revIns.body).first['id']
        : asMap(revIns.body)?['id'];
    if (rid != null) {
      await rest(
        c,
        method: 'DELETE',
        path: '/rest/v1/reviews?id=eq.$rid',
        service: true,
      );
    }
  }

  final revAsSeller = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/reviews',
    token: buyerTok,
    body: {
      'target_id': buyerUid,
      'buyer_id': sellerUid,
      'stars': 5,
      'comment': 'RTF spoof seller role',
      'target_type': 'buyer',
      'author_role': 'vendedor',
    },
  );
  rec(
    surface: 'REVIEWS',
    attack: 'buyer INSERT as author_role=vendedor buyer_id=seller',
    identity: 'buyer',
    result: '${revAsSeller.statusCode} ${clip(revAsSeller.body, 220)}',
    impact: revAsSeller.statusCode < 300 ? 'role spoof' : 'blocked',
    evidence: revAsSeller.body,
  );
  if (revAsSeller.statusCode < 300) {
    final rid = asList(revAsSeller.body).isNotEmpty
        ? asList(revAsSeller.body).first['id']
        : asMap(revAsSeller.body)?['id'];
    if (rid != null) {
      await rest(
        c,
        method: 'DELETE',
        path: '/rest/v1/reviews?id=eq.$rid',
        service: true,
      );
    }
  }

  // Profiles user_type
  final pPatch = await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/profiles?id=eq.$buyerUid',
    token: buyerTok,
    body: {'user_type': 'admin', 'is_admin': true, 'role': 'admin'},
  );
  rec(
    surface: 'AUTH/PROFILES',
    attack: 'PATCH user_type=admin',
    identity: 'buyer',
    result: '${pPatch.statusCode} ${clip(pPatch.body, 200)}',
    impact: 'privilege escalation attempt',
    evidence: pPatch.body,
  );

  final adminRpc = await rpcRaw(
    c,
    'batata_admin_list_profiles',
    {'p_limit': 5},
    token: buyerTok,
  );
  rec(
    surface: 'RPC',
    attack: 'batata_admin_list_profiles as buyer',
    identity: 'buyer',
    result: '${adminRpc.statusCode} ${clip(adminRpc.body, 220)}',
    impact: adminRpc.statusCode == 200 ? 'admin RPC as user' : 'blocked',
    severity: adminRpc.statusCode == 200 ? 'P1' : 'info',
    evidence: adminRpc.body,
  );

  // Sensitive RPCs
  final rpcAttacks = <String, Map<String, dynamic>>{
    'batata_ensure_wallet': {'p_user_id': sellerUid},
    'batata_release_seller_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_refund_buyer_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_send_live_tip_from_wallet': {
      'p_live_id': null,
      'p_seller_id': sellerUid,
      'p_amount': 1,
      'p_message': 'rtf',
    },
    'batata_process_partial_refund_dispute': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_refund_percent': 100,
    },
    'batata_wallet_payout_debit': {
      'p_user_id': buyerUid,
      'p_amount_cents': 1,
      'p_idempotency_key': 'rtf_$stamp',
    },
    'batata_wallet_payout_finish': {
      'p_idempotency_key': 'rtf_$stamp',
      'p_stripe_transfer_id': 'tr_fake',
      'p_failed': false,
    },
    'batata_finalize_stripe_order_refund': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_refund_id': 're_fake',
      'p_payment_intent_id': 'pi_fake',
      'p_session_id': 'cs_fake',
      'p_amount_cents': 100,
    },
    'batata_settle_live_tip_from_stripe': {
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
      'p_stripe_session_id': 'cs_test',
      'p_paid_amount_cents': 100,
    },
    'batata_create_live_tip_pending': {
      'p_live_id': null,
      'p_seller_id': sellerUid,
      'p_amount': 1,
      'p_message': 'x',
    },
    'batata_live_reservation_stripe_convert': {
      'p_request_id': '00000000-0000-0000-0000-000000000001',
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'exec_sql': {'query': 'select 1'},
    'sql': {'q': 'select 1'},
  };

  for (final e in rpcAttacks.entries) {
    final r = await rpcRaw(c, e.key, e.value, token: buyerTok);
    rec(
      surface: 'RPC',
      attack: '${e.key} ${e.value}',
      identity: 'buyer',
      result: '${r.statusCode} ${clip(r.body, 220)}',
      impact: r.statusCode == 200 ? 'EXECUTE permitted' : 'denied_or_errored',
      evidence: r.body,
    );
  }

  // Call ALL OpenAPI RPCs with {} as buyer — inventory grants
  stdout.writeln('PASS1 RPC grant sweep ${rpcInventory.length}…');
  final rpcGrant = <String, int>{};
  for (final fn in rpcInventory) {
    if (rpcAttacks.containsKey(fn)) continue;
    final r = await rpcRaw(c, fn, {}, token: buyerTok);
    rpcGrant[fn] = r.statusCode;
    if (r.statusCode == 200) {
      rec(
        surface: 'RPC',
        attack: '$fn {}',
        identity: 'buyer',
        result: '200 ${clip(r.body, 160)}',
        impact: 'EXECUTE+empty-ok',
        evidence: r.body,
      );
    }
  }
  File('$outDir/rpc_grant_buyer.json').writeAsStringSync(jsonEncode(rpcGrant));

  // Edge functions
  stdout.writeln('PASS1 Edge…');
  final edges = [
    'stripe-webhook',
    'refund-order',
    'create-live-tip-checkout',
    'create-connect-account',
    'create-mux-live',
    'complete-mux-live',
    'livekit-mux-publish',
    'livekit-egress-cleanup',
    'ingest-ocr-reservation',
    'ps-pairing-claim',
    'ps-heartbeat',
    'ps-panel-log',
    'delete-test-account',
    'meta-data-deletion',
    'sec-fase2-e2e-oversell',
    'send-sms-bulkgate',
    'resolve-mux-playback',
  ];
  for (final fn in edges) {
    final r = await edgeRaw(
      c,
      fn,
      token: buyerTok,
      body: {'order_id': '00000000-0000-0000-0000-000000000001', 'amount': 1},
    );
    rec(
      surface: 'EDGE/$fn',
      attack: 'POST hostile minimal body',
      identity: 'buyer',
      result: '${r.statusCode} ${clip(r.body, 180)}',
      impact: r.statusCode == 200 ? 'accepted' : 'rejected_or_auth',
      evidence: r.body,
    );
  }

  final wh = await edgeRaw(
    c,
    'stripe-webhook',
    body: {
      'type': 'checkout.session.completed',
      'data': {
        'object': {'id': 'cs_test', 'payment_status': 'paid'},
      },
    },
  );
  rec(
    surface: 'WEBHOOK',
    attack: 'POST without stripe-signature',
    identity: 'anon',
    result: '${wh.statusCode} ${clip(wh.body, 180)}',
    impact: wh.statusCode == 200 ? 'unsigned webhook accepted' : 'blocked',
    severity: wh.statusCode == 200 ? 'P0' : 'info',
    evidence: wh.body,
  );

  final ocr = await edgeRaw(
    c,
    'ingest-ocr-reservation',
    body: {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'ocr_line_hash': 'abcdefghijkl',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ref_number': 1,
    },
    extraHeaders: {'x-device-token': 'totally-fake-token'},
  );
  rec(
    surface: 'PS/OCR',
    attack: 'ingest with fake device token',
    identity: 'anon+header',
    result: '${ocr.statusCode} ${clip(ocr.body, 220)}',
    impact: ocr.statusCode == 200 ? 'OCR ingest without pairing' : 'blocked',
    evidence: ocr.body,
  );

  final pair = await edgeRaw(
    c,
    'ps-pairing-claim',
    body: {'code': '000000', 'device_id': 'rtf'},
  );
  rec(
    surface: 'PS/OCR',
    attack: 'claim pairing code 000000',
    identity: 'anon',
    result: '${pair.statusCode} ${clip(pair.body, 220)}',
    impact: pair.statusCode == 200 ? 'pairing brute' : 'blocked',
    evidence: pair.body,
  );

  final tip = await edgeRaw(
    c,
    'create-live-tip-checkout',
    token: buyerTok,
    body: {
      'tip_id': '00000000-0000-0000-0000-000000000001',
      'seller_id': sellerUid,
      'amount_eur': 1,
    },
  );
  rec(
    surface: 'TIPS',
    attack: 'client tip_id + amount 1',
    identity: 'buyer',
    result: '${tip.statusCode} ${clip(tip.body, 220)}',
    impact: 'tip_id must be rejected',
    evidence: tip.body,
  );

  final refundX = await edgeRaw(
    c,
    'refund-order',
    token: buyerTok,
    body: {'order_id': pendingOrderOrDummy()},
  );
  rec(
    surface: 'REFUNDS',
    attack: 'buyer refund-order',
    identity: 'buyer',
    result: '${refundX.statusCode} ${clip(refundX.body, 200)}',
    impact: refundX.statusCode == 200 ? 'buyer refunded' : 'seller-only expected',
    evidence: refundX.body,
  );

  // Chats cross-user
  final chats = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/chats?select=id,user_a,user_b,product_id,last_message&limit=20',
    token: buyerTok,
  );
  rec(
    surface: 'CHAT',
    attack: 'SELECT chats',
    identity: 'buyer',
    result: '${chats.statusCode} n=${asList(chats.body).length}',
    impact: 'scope of chat list',
    evidence: clip(chats.body, 300),
  );
  final foreignChats = asList(chats.body).where((e) {
    final a = e['user_a']?.toString();
    final b = e['user_b']?.toString();
    return a != buyerUid && b != buyerUid;
  }).toList();
  rec(
    surface: 'CHAT',
    attack: 'filter foreign chats in SELECT result',
    identity: 'buyer',
    result: 'foreign=${foreignChats.length}',
    impact: foreignChats.isNotEmpty ? 'cross-user chat metadata' : 'own only',
    severity: foreignChats.isNotEmpty ? 'P1' : 'info',
    evidence: clip(jsonEncode(foreignChats.take(3).toList()), 300),
  );

  final msgs = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/chat_messages?select=id,chat_id,sender_id,receiver_id,text&limit=10',
    token: buyerTok,
  );
  rec(
    surface: 'CHAT',
    attack: 'SELECT chat_messages unlimited',
    identity: 'buyer',
    result: '${msgs.statusCode} n=${asList(msgs.body).length}',
    impact: 'message leakage?',
    evidence: clip(msgs.body, 250),
  );

  // Storage
  final stor = await http.get(
    Uri.parse('${c.url}/storage/v1/bucket'),
    headers: {
      'apikey': c.anonKey,
      'Authorization': 'Bearer $buyerTok',
    },
  );
  rec(
    surface: 'STORAGE',
    attack: 'list buckets',
    identity: 'buyer',
    result: '${stor.statusCode} ${clip(stor.body, 250)}',
    impact: 'bucket inventory',
    evidence: stor.body,
  );
  for (final b in ['chat_media', 'product_photos', 'avatars', 'proofs', 'disputes']) {
    final ls = await http.post(
      Uri.parse('${c.url}/storage/v1/object/list/$b'),
      headers: {
        'apikey': c.anonKey,
        'Authorization': 'Bearer $buyerTok',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'prefix': '', 'limit': 10}),
    );
    rec(
      surface: 'STORAGE',
      attack: 'list $b prefix empty',
      identity: 'buyer',
      result: '${ls.statusCode} ${clip(ls.body, 200)}',
      impact: ls.statusCode == 200 ? 'listing' : 'blocked',
      evidence: ls.body,
    );
  }

  // Disputes INSERT
  final disp = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/order_disputes',
    token: buyerTok,
    body: {
      'order_id': '00000000-0000-0000-0000-000000000001',
      'status': 'aberta',
      'buyer_id': buyerUid,
    },
  );
  rec(
    surface: 'DISPUTES',
    attack: 'INSERT dispute fake order',
    identity: 'buyer',
    result: '${disp.statusCode} ${clip(disp.body, 200)}',
    impact: 'orphan dispute',
    evidence: disp.body,
  );

  // Offers
  if (productId != null) {
    final off = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/product_offers',
      token: buyerTok,
      body: {
        'product_id': productId,
        'buyer_id': buyerUid,
        'seller_id': sellerUid,
        'offered_price': 0.01,
        'status': 'accepted',
      },
    );
    rec(
      surface: 'OFFERS',
      attack: 'INSERT offer status=accepted price=0.01',
      identity: 'buyer',
      result: '${off.statusCode} ${clip(off.body, 220)}',
      impact: off.statusCode < 300 ? 'self-accept offer?' : 'blocked',
      evidence: off.body,
    );
  }

  // Bundle discounts as buyer
  final bun = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/seller_bundle_discounts',
    token: buyerTok,
    body: {
      'seller_id': sellerUid,
      'enabled': true,
      'tier_2_pct': 90,
    },
  );
  rec(
    surface: 'BUNDLES',
    attack: 'buyer INSERT 90% discount on seller',
    identity: 'buyer',
    result: '${bun.statusCode} ${clip(bun.body, 200)}',
    impact: bun.statusCode < 300 ? 'discount hijack' : 'blocked',
    evidence: bun.body,
  );

  // Banking details
  for (final t in [
    'seller_payout_details',
    'banking_details',
    'user_banking_details',
    'payout_details',
  ]) {
    final r = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/$t?select=*&limit=5',
      token: buyerTok,
    );
    rec(
      surface: 'PAYOUT/BANK',
      attack: 'SELECT $t',
      identity: 'buyer',
      result: '${r.statusCode} ${clip(r.body, 180)}',
      impact: r.statusCode == 200 && asList(r.body).isNotEmpty
          ? 'PII?'
          : 'empty_or_missing',
      evidence: r.body,
    );
  }

  // GraphQL
  final gql = await http.post(
    Uri.parse('${c.url}/graphql/v1'),
    headers: {
      'apikey': c.anonKey,
      'Authorization': 'Bearer $buyerTok',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'query': '{ __schema { types { name } } }',
    }),
  );
  rec(
    surface: 'GRAPHQL',
    attack: 'introspection',
    identity: 'buyer',
    result: '${gql.statusCode} ${clip(gql.body, 160)}',
    impact: gql.statusCode == 200 ? 'graphql on' : 'off',
    evidence: gql.body,
  );

  // Real order for wallet RPCs if we have pendingId stored in cleanup
  final oids = (cleanup['order_ids'] as List).cast<String>();
  if (oids.isNotEmpty) {
    final rel = await rpcRaw(
      c,
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oids.first},
      token: buyerTok,
    );
    rec(
      surface: 'LEDGER',
      attack: 'release wallet on unpaid/hostile order',
      identity: 'buyer',
      result: '${rel.statusCode} ${clip(rel.body, 220)}',
      impact: rel.body.contains('true') ? 'possible mint' : 'no mint or error',
      evidence: rel.body,
    );
    final ref = await rpcRaw(
      c,
      'batata_refund_buyer_wallet_for_order',
      {'p_order_id': oids.first},
      token: buyerTok,
    );
    rec(
      surface: 'LEDGER',
      attack: 'refund wallet RPC on lab order',
      identity: 'buyer',
      result: '${ref.statusCode} ${clip(ref.body, 220)}',
      impact: ref.body.contains('true') ? 'possible mint' : 'no mint or error',
      evidence: ref.body,
    );
    final part = await rpcRaw(
      c,
      'batata_process_partial_refund_dispute',
      {'p_order_id': oids.first, 'p_refund_percent': 100},
      token: buyerTok,
    );
    rec(
      surface: 'REFUNDS',
      attack: 'partial refund RPC 100% on lab order',
      identity: 'buyer',
      result: '${part.statusCode} ${clip(part.body, 250)}',
      impact: 'money movement?',
      evidence: part.body,
    );
  }

  // Observe wallets after RPCs
  final wAfter = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/wallets?select=id,balance&id=in.($buyerUid,$sellerUid,$freshId)',
    service: true,
  );
  rec(
    surface: 'WALLET',
    attack: 'observe balances after pass1',
    identity: 'service_observe',
    result: clip(wAfter.body, 400),
    impact: 'detect mint',
    evidence: wAfter.body,
  );

  final report = {
    'pass': 1,
    'project': stagingRef,
    'started': DateTime.now().toUtc().toIso8601String(),
    'tables': tableInventory.length,
    'rpcs': rpcInventory.length,
    'matrix_n': matrix.length,
    'findings': findings,
    'notes': notes,
    'cleanup': cleanup,
    'rpc_inventory': rpcInventory,
    'table_inventory': tableInventory,
    'matrix': matrix,
  };
  File('$outDir/pass1_raw.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  stdout.writeln(
    'PASS1 done findings=${findings.length} matrix=${matrix.length}',
  );
}

String pendingOrderOrDummy() {
  final oids = (cleanup['order_ids'] as List);
  if (oids.isNotEmpty) return oids.first.toString();
  return '00000000-0000-0000-0000-000000000001';
}

num Number(Object? v) {
  if (v is num) return v;
  return num.tryParse('$v') ?? 0;
}
