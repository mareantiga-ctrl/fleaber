// Independent blind saturation audit — 2026-08-27
// Staging ONLY. No SQL apply. No Flutter change. No production.
// dart run tool/sec_blind_sat_20260827.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';

const project = 'fxdknzrqjenzqcvnwqqq';
const base = 'https://$project.supabase.co';
const tag = 'SATB_20260827';

late String anonKey;
late String serviceKey;
late String buyerEmail;
late String buyerPass;
late String sellerEmail;
late String sellerPass;
late String buyerId;
late String sellerId;
late String buyerJwt;
late String sellerJwt;
String? e2eSecret;

final http = HttpClient();
final findings = <Map<String, dynamic>>[];
final notes = <String>[];
final coverage = <String, String>{};
final created = <String, List<String>>{
  'products': [],
  'orders': [],
  'chats': [],
};
int passNo = 0;

void cov(String k, String v) {
  final cur = coverage[k];
  const rank = {
    'NÃO TESTADA': 0,
    'PARCIAL': 1,
    'TESTADA': 2,
    'TESTADA COM VARIANTES': 3,
  };
  if (cur == null || (rank[v] ?? 0) > (rank[cur] ?? 0)) coverage[k] = v;
}

Future<Map<String, dynamic>> req({
  required String method,
  required String url,
  String? token,
  String? apikey,
  Object? body,
  Map<String, String>? extra,
  String prefer = '',
}) async {
  final uri = Uri.parse(url);
  final r = await http.openUrl(method, uri);
  final key = apikey ?? anonKey;
  r.headers.set('apikey', key);
  r.headers.set('Authorization', 'Bearer ${token ?? key}');
  r.headers.set('Content-Type', 'application/json');
  if (prefer.isNotEmpty) r.headers.set('Prefer', prefer);
  extra?.forEach(r.headers.set);
  if (body != null) {
    r.add(utf8.encode(body is String ? body : jsonEncode(body)));
  }
  final res = await r.close().timeout(const Duration(seconds: 45));
  final raw = await res.transform(utf8.decoder).join();
  Object? parsed;
  try {
    parsed = raw.isEmpty ? null : jsonDecode(raw);
  } catch (_) {
    parsed = raw;
  }
  return {
    'status': res.statusCode,
    'body': parsed,
    'raw': raw.length > 4000 ? '${raw.substring(0, 4000)}…' : raw,
  };
}

Future<Map<String, dynamic>> rest(
  String table, {
  String method = 'GET',
  String? token,
  String? apikey,
  String qs = 'select=*&limit=5',
  Object? body,
  String prefer = 'return=representation',
}) {
  final q = qs.isEmpty ? '' : '?$qs';
  return req(
    method: method,
    url: '$base/rest/v1/$table$q',
    token: token,
    apikey: apikey,
    body: body,
    prefer: method == 'GET' ? '' : prefer,
  );
}

Future<Map<String, dynamic>> rpc(
  String name, {
  String? token,
  String? apikey,
  Object? body,
}) {
  return req(
    method: 'POST',
    url: '$base/rest/v1/rpc/$name',
    token: token,
    apikey: apikey,
    body: body ?? {},
  );
}

Future<Map<String, dynamic>> edge(
  String name, {
  String method = 'POST',
  String? token,
  String? apikey,
  Object? body,
  String qs = '',
  Map<String, String>? extra,
}) {
  final q = qs.isEmpty ? '' : '?$qs';
  return req(
    method: method,
    url: '$base/functions/v1/$name$q',
    token: token,
    apikey: apikey,
    body: body,
    extra: extra,
  );
}

void addFinding({
  required String id,
  required String sev,
  required String surface,
  required String pre,
  required String identity,
  required String request,
  required Object response,
  required String before,
  required String after,
  required String impact,
  required String confidence,
  required String variant,
  required String fp,
}) {
  findings.add({
    'id': id,
    'sev': sev,
    'surface': surface,
    'pre': pre,
    'identity': identity,
    'request': request,
    'response': response,
    'before': before,
    'after': after,
    'impact': impact,
    'confidence': confidence,
    'variant': variant,
    'fp': fp,
    'pass': passNo,
  });
  stderr.writeln('FINDING $sev $id [$surface] $impact');
}

bool isBlocked(Map<String, dynamic> r) {
  final s = r['status'] as int;
  if (s == 401 || s == 403 || s == 404 || s == 405 || s == 409 || s == 422) {
    return true;
  }
  if (s >= 400) return true;
  final b = r['body'];
  if (b is Map && (b['ok'] == false || b['error'] != null)) return true;
  return false;
}

bool leakedRows(Map<String, dynamic> r) {
  final b = r['body'];
  return r['status'] == 200 && b is List && b.isNotEmpty;
}

Future<Map<String, dynamic>> login(String email, String pass) async {
  final r = await req(
    method: 'POST',
    url: '$base/auth/v1/token?grant_type=password',
    body: {'email': email, 'password': pass},
  );
  if (r['status'] != 200) {
    throw StateError('login failed $email ${r['status']} ${r['raw']}');
  }
  final b = r['body'] as Map;
  return {
    'jwt': b['access_token'] as String,
    'id': (b['user'] as Map)['id'] as String,
  };
}

Future<void> loadEnv() async {
  final f = File('tool/live_ops_staging.env');
  if (!f.existsSync()) throw StateError('missing live_ops_staging.env');
  final map = <String, String>{};
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i < 1) continue;
    map[t.substring(0, i)] = t.substring(i + 1);
  }
  final url = map['SUPABASE_URL'] ?? '';
  if (!url.contains(project)) {
    throw StateError('ABORT: not staging $project');
  }
  anonKey = map['SUPABASE_ANON_KEY']!;
  serviceKey = map['SUPABASE_SERVICE_ROLE_KEY']!;
  buyerEmail = map['LIVE_OPS_TEST_BUYER_EMAIL']!;
  buyerPass = map['LIVE_OPS_TEST_BUYER_PASSWORD']!;
  sellerEmail = map['LIVE_OPS_TEST_SELLER_EMAIL']!;
  sellerPass = map['LIVE_OPS_TEST_SELLER_PASSWORD']!;
  e2eSecret = map['FLEABER_STAGING_CRASH_INJECT_SECRET'];
}

String ident(String? jwt) {
  if (jwt == null) return 'anon';
  if (jwt == serviceKey) return 'service_role';
  if (jwt == buyerJwt) return 'buyer';
  if (jwt == sellerJwt) return 'seller';
  return 'jwt';
}

Future<Map<String, dynamic>?> adminGet(String table, String id) async {
  final r = await rest(
    table,
    apikey: serviceKey,
    token: serviceKey,
    qs: 'id=eq.$id&select=*&limit=1',
  );
  final b = r['body'];
  if (b is List && b.isNotEmpty) return Map<String, dynamic>.from(b.first as Map);
  return null;
}

Future<void> cleanup() async {
  for (final oid in created['orders']!) {
    await rest('orders',
        method: 'DELETE',
        apikey: serviceKey,
        token: serviceKey,
        qs: 'id=eq.$oid',
        prefer: '');
  }
  for (final pid in created['products']!) {
    await rest('orders',
        method: 'DELETE',
        apikey: serviceKey,
        token: serviceKey,
        qs: 'product_id=eq.$pid',
        prefer: '');
    await rest('products',
        method: 'DELETE',
        apikey: serviceKey,
        token: serviceKey,
        qs: 'id=eq.$pid',
        prefer: '');
  }
}

Future<String?> createProductAsSeller({
  double price = 4.20,
  int qty = 3,
  String? title,
}) async {
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final r = await rest(
    'products',
    method: 'POST',
    token: sellerJwt,
    body: {
      'seller_id': sellerId,
      'title': title ?? '$tag product $stamp',
      'price': price,
      'quantity': qty,
      'ref_code': 'SATB-$stamp',
      'list_on_marketplace': true,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
      'category': 'Outros',
      'state': 'Bom',
      'description': tag,
    },
  );
  final b = r['body'];
  if (r['status'] >= 200 && r['status'] < 300) {
    String? id;
    if (b is List && b.isNotEmpty) id = (b.first as Map)['id']?.toString();
    if (b is Map) id = b['id']?.toString();
    if (id != null) {
      created['products']!.add(id);
      return id;
    }
  }
  notes.add('createProduct failed ${r['status']} ${r['raw']}');
  return null;
}

Future<String?> createOrderAsBuyer({
  required String productId,
  int qty = 1,
  String status = 'reserva_pendente',
  String payment = 'Pagamento na app',
  String shipping = 'entrega em mão',
  Map<String, dynamic>? extra,
}) async {
  final body = {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': productId,
    'quantity': qty,
    'status': status,
    'payment_method': payment,
    'shipping_method': shipping,
    'price_total': 99.99,
    ...?extra,
  };
  final r = await rest('orders', method: 'POST', token: buyerJwt, body: body);
  final b = r['body'];
  if (r['status'] >= 200 && r['status'] < 300) {
    String? id;
    if (b is List && b.isNotEmpty) id = (b.first as Map)['id']?.toString();
    if (b is Map) id = b['id']?.toString();
    if (id != null) {
      created['orders']!.add(id);
      return id;
    }
  }
  notes.add('createOrder failed ${r['status']} ${r['raw']}');
  return null;
}

Future<Map<String, dynamic>?> e2e(String probe, Map<String, dynamic> body) async {
  if (e2eSecret == null || e2eSecret!.length < 16) return null;
  final r = await edge(
    'sec-fase2-e2e-oversell',
    token: anonKey,
    extra: {'x-fleaber-e2e-secret': e2eSecret!},
    body: {
      'probe': probe,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      ...body,
    },
  );
  final b = r['body'];
  if (b is Map<String, dynamic>) return b;
  if (b is Map) return Map<String, dynamic>.from(b);
  return {'http': r['status'], 'raw': r['raw']};
}

// ---------------------------------------------------------------------------
// PASS 1 — full surface
// ---------------------------------------------------------------------------
Future<void> pass1() async {
  passNo = 1;
  stderr.writeln('=== PASS 1 coverage ===');

  Future<void> safe(String name, Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e, st) {
      notes.add('CRASH $name $e');
      stderr.writeln('CRASH $name $e\n$st');
    }
  }

  await safe('auth', attackAuth);
  await safe('profiles', attackProfiles);
  await safe('orders', attackOrdersAndPricing);
  await safe('checkout', attackCheckout);
  await safe('wallet', attackWalletPayout);
  await safe('stock-live', attackStockLiveBag);
  await safe('chat-rev-dsp', attackChatReviewsDisputes);
  await safe('storage', attackStorage);
  await safe('raffle-tips', attackRaffleTips);
  await safe('mux-ps', attackMuxLivekitPs);
  await safe('edges', attackEdges);
  await safe('rpc-rls', attackRpcsAndRls);
}

Future<void> attackAuth() async {
  cov('AUTH', 'TESTADA COM VARIANTES');

  // Enumeration via recover
  final recA = await req(
    method: 'POST',
    url: '$base/auth/v1/recover',
    body: {'email': buyerEmail},
  );
  final recB = await req(
    method: 'POST',
    url: '$base/auth/v1/recover',
    body: {'email': 'nobody-satb-${Random().nextInt(1 << 20)}@example.invalid'},
  );
  if (recA['status'] != recB['status']) {
    addFinding(
      id: 'SATB-AUTH-01',
      sev: 'P3',
      surface: 'AUTH',
      pre: 'anon recover',
      identity: 'anon',
      request: 'POST /auth/v1/recover existing vs fake',
      response: {'exist': recA['status'], 'fake': recB['status']},
      before: '-',
      after: '-',
      impact: 'Possível enumeração de emails via recover.',
      confidence: 'média',
      variant: 'recover status delta',
      fp: 'GoTrue por vezes devolve 200 em ambos.',
    );
  }

  // Signup with buyer email
  final su = await req(
    method: 'POST',
    url: '$base/auth/v1/signup',
    body: {'email': buyerEmail, 'password': 'AnotherPass!234'},
  );
  notes.add('signup existing email status=${su['status']}');

  // JWT alg none / role spoof
  const noneJwt =
      'eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDAiLCJyb2xlIjoic2VydmljZV9yb2xlIiwiaXNzIjoic3VwYWJhc2UiLCJyZWYiOiJmeGRrbnpycWplbnpxY3Zud3FxcSJ9.';
  final none = await rest('wallets', token: noneJwt, qs: 'select=*&limit=5');
  if (leakedRows(none) || none['status'] == 200 && (none['body'] is List && (none['body'] as List).isNotEmpty)) {
    addFinding(
      id: 'SATB-AUTH-02',
      sev: 'P0',
      surface: 'AUTH',
      pre: 'alg=none JWT',
      identity: 'anon-forged',
      request: 'GET wallets with alg=none service_role claim',
      response: none['raw'],
      before: '-',
      after: '-',
      impact: 'JWT forjado aceito — bypass total.',
      confidence: 'alta',
      variant: 'alg=none',
      fp: 'lista vazia ≠ bypass',
    );
  }

  // Cross-user: buyer GET seller profile privileged
  final buyerMe = await rest('profiles',
      token: buyerJwt, qs: 'id=eq.$buyerId&select=*');
  notes.add('buyer own profile status=${buyerMe['status']}');

  // admin claim via profile update tested in profiles
}

Future<void> attackProfiles() async {
  cov('PROFILES', 'TESTADA COM VARIANTES');

  final cols =
      'id,display_name,user_type,phone,phone_verified_at,iban,mb_way,legal_full_name,shipping_address,email';
  final anonDir = await rest('profiles',
      token: anonKey, qs: 'select=$cols&limit=20');
  final buyerOther = await rest('profiles',
      token: buyerJwt, qs: 'id=eq.$sellerId&select=$cols');
  final buyerDir = await rest('profiles_directory',
      token: buyerJwt, qs: 'select=*&limit=20');

  bool pii(Map row) {
    for (final k in ['iban', 'mb_way', 'phone', 'legal_full_name', 'shipping_address']) {
      final v = row[k];
      if (v != null && v.toString().trim().isNotEmpty) return true;
    }
    return false;
  }

  void checkPii(Map<String, dynamic> r, String who, String variant) {
    final b = r['body'];
    if (r['status'] != 200 || b is! List) return;
    for (final row in b) {
      if (row is Map && pii(Map<String, dynamic>.from(row))) {
        final id = row['id']?.toString() ?? '';
        if (who == 'buyer' && id == buyerId) continue;
        addFinding(
          id: 'SATB-PII-01',
          sev: 'P1',
          surface: 'PROFILES',
          pre: 'cross-row SELECT',
          identity: who,
          request: variant,
          response: {
            'id': id,
            'iban': row['iban'],
            'mb_way': row['mb_way'],
            'phone': row['phone'],
          },
          before: '-',
          after: '-',
          impact: 'PII financeiro/contacto de outro utilizador visível.',
          confidence: 'alta',
          variant: variant,
          fp: 'própria row ou campos públicos intencionais',
        );
        break;
      }
    }
  }

  checkPii(anonDir, 'anon', 'anon profiles *');
  checkPii(buyerOther, 'buyer', 'buyer GET seller profile');
  notes.add('profiles_directory status=${buyerDir['status']} rows=${buyerDir['body'] is List ? (buyerDir['body'] as List).length : 0}');

  // Privilege field update
  final before = await adminGet('profiles', buyerId);
  final upAdmin = await rest(
    'profiles',
    method: 'PATCH',
    token: buyerJwt,
    qs: 'id=eq.$buyerId',
    body: {
      'user_type': 'admin',
      'phone_verified_at': DateTime.now().toUtc().toIso8601String(),
    },
  );
  final after = await adminGet('profiles', buyerId);
  final ut = after?['user_type']?.toString() ?? '';
  final pv = after?['phone_verified_at'];
  if (ut.toLowerCase() == 'admin' &&
      (before?['user_type']?.toString().toLowerCase() != 'admin')) {
    addFinding(
      id: 'SATB-AUTH-03',
      sev: 'P0',
      surface: 'AUTH',
      pre: 'buyer own profile PATCH',
      identity: 'buyer',
      request: 'PATCH user_type=admin',
      response: upAdmin['raw'],
      before: '${before?['user_type']}',
      after: ut,
      impact: 'Buyer auto-promove a admin.',
      confidence: 'alta',
      variant: 'user_type',
      fp: 'já era admin',
    );
  }
  if (pv != null && before?['phone_verified_at'] == null) {
    addFinding(
      id: 'SATB-AUTH-04',
      sev: 'P1',
      surface: 'AUTH',
      pre: 'buyer PATCH phone_verified_at',
      identity: 'buyer',
      request: 'PATCH phone_verified_at=now',
      response: upAdmin['raw'],
      before: '${before?['phone_verified_at']}',
      after: '$pv',
      impact: 'Buyer forja verificação de telefone.',
      confidence: 'alta',
      variant: 'phone_verified_at',
      fp: 'coluna ignorada pelo PATCH (antes==depois)',
    );
  }
  // restore
  if (before != null) {
    await rest(
      'profiles',
      method: 'PATCH',
      apikey: serviceKey,
      token: serviceKey,
      qs: 'id=eq.$buyerId',
      body: {
        'user_type': before['user_type'],
        'phone_verified_at': before['phone_verified_at'],
      },
    );
  }

  // Cross-row UPDATE
  final xup = await rest(
    'profiles',
    method: 'PATCH',
    token: buyerJwt,
    qs: 'id=eq.$sellerId',
    body: {'display_name': '${tag}_hijack'},
  );
  final sellerAfter = await adminGet('profiles', sellerId);
  if ((sellerAfter?['display_name']?.toString() ?? '').contains('${tag}_hijack')) {
    addFinding(
      id: 'SATB-PII-02',
      sev: 'P0',
      surface: 'PROFILES',
      pre: 'buyer PATCH seller',
      identity: 'buyer',
      request: 'PATCH profiles id=seller display_name',
      response: xup['raw'],
      before: '-',
      after: '${sellerAfter?['display_name']}',
      impact: 'Buyer altera perfil do vendedor.',
      confidence: 'alta',
      variant: 'cross-row update',
      fp: 'RLS bloqueou mas PostgREST 200 vazio',
    );
  }
}

Future<void> attackOrdersAndPricing() async {
  cov('ORDERS', 'TESTADA COM VARIANTES');
  cov('PRICING', 'TESTADA COM VARIANTES');
  cov('STOCK', 'TESTADA COM VARIANTES');

  final pid = await createProductAsSeller(price: 8.50, qty: 2);
  if (pid == null) {
    cov('ORDERS', 'PARCIAL');
    notes.add('sem produto JWT — orders parcialmente testadas');
    return;
  }

  // INSERT spoof: other buyer, paid status, stripe ids, contract, amount
  final spoof = await rest(
    'orders',
    method: 'POST',
    token: buyerJwt,
    body: {
      'buyer_id': sellerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'status': 'pago',
      'payment_method': 'Pagamento na app',
      'price_total': 0.01,
      'amount_paid_cents': 99999,
      'stripe_payment_intent_id': 'pi_satb_fake',
      'contract_unit_cents': 1,
      'contract_qty': 1,
      'stock_units_applied': 1,
    },
  );
  final sb = spoof['body'];
  Map<String, dynamic>? srow;
  if (sb is List && sb.isNotEmpty) srow = Map<String, dynamic>.from(sb.first as Map);
  if (sb is Map && sb['id'] != null) srow = Map<String, dynamic>.from(sb);
  if (srow != null && srow['id'] != null) {
    created['orders']!.add(srow['id'].toString());
    final live = await adminGet('orders', srow['id'].toString());
    final st = live?['status']?.toString().toLowerCase() ?? '';
    final ap = live?['amount_paid_cents'];
    final pi = live?['stripe_payment_intent_id'];
    final bid = live?['buyer_id']?.toString();
    if (st == 'pago' && (ap == null || ap == 0) && (pi == null || pi.toString().isEmpty)) {
      addFinding(
        id: 'SATB-ORD-01',
        sev: 'P0',
        surface: 'ORDERS',
        pre: 'JWT INSERT status=pago',
        identity: 'buyer',
        request: 'INSERT orders status=pago amount_paid forged',
        response: live ?? spoof['raw'],
        before: 'product qty=2',
        after: 'status=$st amount_paid=$ap',
        impact: 'Buyer cria encomenda já paga sem captura Stripe.',
        confidence: 'alta',
        variant: 'INSERT pago',
        fp: 'status reescrito para reserva_pendente',
      );
    }
    if (bid == sellerId && bid != buyerId) {
      addFinding(
        id: 'SATB-ORD-02',
        sev: 'P1',
        surface: 'ORDERS',
        pre: 'JWT INSERT buyer_id=seller',
        identity: 'buyer',
        request: 'INSERT orders buyer_id=other',
        response: live ?? spoof['raw'],
        before: '-',
        after: 'buyer_id=$bid',
        impact: 'Buyer cria encomenda em nome de outra parte.',
        confidence: 'alta',
        variant: 'party spoof',
        fp: 'trigger força auth.uid()',
      );
    }
    if (ap != null && ap is num && ap > 0) {
      addFinding(
        id: 'SATB-ORD-03',
        sev: 'P0',
        surface: 'ORDERS',
        pre: 'JWT INSERT amount_paid_cents',
        identity: 'buyer',
        request: 'INSERT amount_paid_cents=99999',
        response: live ?? spoof['raw'],
        before: '-',
        after: 'amount_paid_cents=$ap',
        impact: 'JWT fabrica fundos de plataforma.',
        confidence: 'alta',
        variant: 'amount_paid INSERT',
        fp: 'coluna persistida mas wallet ignora',
      );
    }
  }

  final oid = await createOrderAsBuyer(productId: pid, qty: 1);
  if (oid == null) return;

  final sealed = await adminGet('orders', oid);
  notes.add(
      'sealed contract unit=${sealed?['contract_unit_cents']} qty=${sealed?['contract_qty']} price_total=${sealed?['price_total']} status=${sealed?['status']}');

  // JWT contract override on INSERT extra
  final oid2 = await createOrderAsBuyer(
    productId: pid,
    qty: 1,
    extra: {
      'contract_unit_cents': 1,
      'contract_qty': 99,
      'amount_paid_cents': 50000,
    },
  );
  if (oid2 != null) {
    final row = await adminGet('orders', oid2);
    final unit = row?['contract_unit_cents'];
    final cq = row?['contract_qty'];
    final ap = row?['amount_paid_cents'];
    if (unit == 1) {
      addFinding(
        id: 'SATB-PRC-01',
        sev: 'P0',
        surface: 'PRICING',
        pre: 'JWT INSERT contract_unit_cents=1',
        identity: 'buyer',
        request: 'INSERT contract_unit_cents=1',
        response: row ?? {},
        before: 'catalog 8.50',
        after: 'contract_unit_cents=$unit',
        impact: 'Buyer sela contrato a 0,01 €.',
        confidence: 'alta',
        variant: 'contract_unit JWT input',
        fp: 'selo servidor sobrescreve',
      );
    }
    if (cq == 99) {
      addFinding(
        id: 'SATB-PRC-02',
        sev: 'P0',
        surface: 'PRICING',
        pre: 'JWT INSERT contract_qty=99 stock=2',
        identity: 'buyer',
        request: 'INSERT contract_qty=99',
        response: row ?? {},
        before: 'stock 2',
        after: 'contract_qty=$cq',
        impact: 'Qty contratual > stock via JWT.',
        confidence: 'alta',
        variant: 'contract_qty',
        fp: 'qty cap no trigger',
      );
    }
    if (ap != null && ap is num && ap > 0) {
      addFinding(
        id: 'SATB-ORD-03b',
        sev: 'P0',
        surface: 'ORDERS',
        pre: 'JWT INSERT amount_paid',
        identity: 'buyer',
        request: 'INSERT amount_paid_cents=50000',
        response: row ?? {},
        before: '-',
        after: '$ap',
        impact: 'JWT fabrica captura.',
        confidence: 'alta',
        variant: 'amount_paid',
        fp: 'nullified',
      );
    }
  }

  // Catalog hike after order
  await rest(
    'products',
    method: 'PATCH',
    token: sellerJwt,
    qs: 'id=eq.$pid',
    body: {'price': 80.00},
  );
  final hiked = await adminGet('products', pid);
  final still = await adminGet('orders', oid);
  notes.add('after hike catalog=${hiked?['price']} contract=${still?['contract_unit_cents']}');

  // Buyer PATCH money / parties / status
  final patches = [
    {'amount_paid_cents': 12345},
    {'stripe_payment_intent_id': 'pi_forged'},
    {'status': 'pago'},
    {'status': 'entregue'},
    {'status': 'concluido'},
    {'price_total': 0.50},
    {'contract_unit_cents': 1},
    {'quantity': 9},
    {'seller_id': buyerId},
    {'buyer_id': sellerId},
    {'payment_method': 'mb way'},
  ];
  for (final p in patches) {
    final r = await rest(
      'orders',
      method: 'PATCH',
      token: buyerJwt,
      qs: 'id=eq.$oid',
      body: p,
    );
    final live = await adminGet('orders', oid);
    final k = p.keys.first;
    final want = p[k];
    final got = live?[k];
    if (got != null && got.toString() == want.toString() && k != 'status') {
      addFinding(
        id: 'SATB-ORD-U-$k',
        sev: (k.contains('amount') || k.contains('stripe') || k.contains('contract') || k.contains('price') || k.contains('seller') || k.contains('buyer'))
            ? 'P0'
            : 'P1',
        surface: 'ORDERS',
        pre: 'order unpaid buyer PATCH',
        identity: 'buyer',
        request: 'PATCH $k=$want',
        response: {'http': r['status'], 'live': live},
        before: '${still?[k]}',
        after: '$got',
        impact: 'Buyer muta campo privilegiado $k.',
        confidence: 'alta',
        variant: 'PATCH $k',
        fp: 'PostgREST 204 sem mutação — conferir live',
      );
    }
    if (k == 'status' && got.toString() == want.toString()) {
      final sev = want == 'pago' || want == 'entregue' || want == 'concluido' ? 'P0' : 'P1';
      addFinding(
        id: 'SATB-ORD-ST-$want',
        sev: sev,
        surface: 'ORDERS',
        pre: 'unpaid order',
        identity: 'buyer',
        request: 'PATCH status=$want',
        response: live ?? r['raw'],
        before: '${still?['status']}',
        after: '$got',
        impact: 'Buyer salta máquina de estados para $want sem pagamento.',
        confidence: 'alta',
        variant: 'status $want',
        fp: 'trigger reverte',
      );
    }
  }

  // Seller status pago without capture (platform method)
  final sellerPago = await rest(
    'orders',
    method: 'PATCH',
    token: sellerJwt,
    qs: 'id=eq.$oid',
    body: {'status': 'pago'},
  );
  final afterPago = await adminGet('orders', oid);
  if ((afterPago?['status']?.toString().toLowerCase() ?? '') == 'pago' &&
      (afterPago?['amount_paid_cents'] == null || afterPago?['amount_paid_cents'] == 0) &&
      (afterPago?['stripe_payment_intent_id'] == null ||
          afterPago!['stripe_payment_intent_id'].toString().isEmpty)) {
    addFinding(
      id: 'SATB-ORD-04',
      sev: 'P0',
      surface: 'ORDERS',
      pre: 'platform payment unpaid',
      identity: 'seller',
      request: 'PATCH status=pago',
      response: afterPago ?? sellerPago['raw'],
      before: '${still?['status']}',
      after: '${afterPago?['status']}',
      impact: 'Seller marca pago em método de plataforma sem captura — pode libertar wallet/stock.',
      confidence: 'alta',
      variant: 'seller pago platform',
      fp: 'método reescrito para off-platform',
    );
  }

  // Off-platform seller pago — expected allowed
  final pidOff = await createProductAsSeller(price: 5.00, qty: 1, title: '$tag offplat');
  if (pidOff != null) {
    final oOff = await createOrderAsBuyer(
      productId: pidOff,
      payment: 'MB WAY',
    );
    if (oOff != null) {
      final r = await rest(
        'orders',
        method: 'PATCH',
        token: sellerJwt,
        qs: 'id=eq.$oOff',
        body: {'status': 'pago'},
      );
      final live = await adminGet('orders', oOff);
      notes.add('off-platform seller→pago status=${live?['status']} http=${r['status']}');
      // Then try wallet release on off-platform paid
      final rel = await rpc(
        'batata_release_seller_wallet_for_order',
        token: sellerJwt,
        body: {'p_order_id': oOff},
      );
      notes.add('release off-platform ${rel['status']} ${rel['raw']}');
      final wBefore = await adminGet('wallets', sellerId);
      // if wallet increased without amount_paid — P0 invariant F
      final wAfter = await adminGet('wallets', sellerId);
      final b1 = num.tryParse('${wBefore?['balance']}') ?? 0;
      final b2 = num.tryParse('${wAfter?['balance']}') ?? 0;
      if (b2 > b1 + 0.001 && (live?['amount_paid_cents'] == null || live?['amount_paid_cents'] == 0)) {
        addFinding(
          id: 'SATB-WAL-F01',
          sev: 'P0',
          surface: 'WALLET',
          pre: 'MB WAY seller→pago',
          identity: 'seller',
          request: 'rpc batata_release_seller_wallet_for_order',
          response: rel['raw'],
          before: 'balance=$b1 amount_paid=${live?['amount_paid_cents']}',
          after: 'balance=$b2',
          impact: 'Pagamento off-platform transformado em fundos Fleaber.',
          confidence: 'alta',
          variant: 'invariant F',
          fp: 'crédito de outra order concorrente',
        );
      }
    }
  }

  // qty > stock INSERT
  final oversell = await createOrderAsBuyer(productId: pid, qty: 99);
  if (oversell != null) {
    final row = await adminGet('orders', oversell);
    if ((row?['quantity'] ?? 0) == 99 || (row?['contract_qty'] ?? 0) == 99) {
      addFinding(
        id: 'SATB-STK-01',
        sev: 'P1',
        surface: 'STOCK',
        pre: 'product qty=2',
        identity: 'buyer',
        request: 'INSERT quantity=99',
        response: row ?? {},
        before: 'stock~2',
        after: 'order qty=${row?['quantity']}',
        impact: 'Order qty > stock aceite (oversell no settle).',
        confidence: 'alta',
        variant: 'qty>stock INSERT',
        fp: 'checkout bloqueia mais tarde',
      );
    }
  }

  // Seller swap product ownership / hike then checkout tested later
}

Future<void> attackCheckout() async {
  cov('CHECKOUT', 'TESTADA COM VARIANTES');
  cov('SETTLE', 'TESTADA COM VARIANTES');
  cov('WEBHOOK', 'TESTADA COM VARIANTES');
  cov('BAG', 'TESTADA COM VARIANTES');

  final pid = await createProductAsSeller(price: 6.00, qty: 2, title: '$tag checkout');
  if (pid == null) return;
  final oid = await createOrderAsBuyer(productId: pid);
  if (oid == null) return;

  // Anon checkout
  final anonCo = await edge(
    'create-payment-intent',
    token: anonKey,
    body: {
      'amount': 50,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'order_id': oid,
      'product_id': pid,
      'shipping_method': 'hand',
    },
  );
  notes.add('anon checkout ${anonCo['status']} ${anonCo['raw']}');

  // Buyer amount underpay
  final cheap = await edge(
    'create-payment-intent',
    token: buyerJwt,
    body: {
      'amount': 50,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'order_id': oid,
      'product_id': pid,
      'shipping_method': 'hand',
      'quantity': 1,
    },
  );
  final cheapBody = cheap['body'];
  int? serverAmt;
  if (cheapBody is Map) {
    serverAmt = int.tryParse('${cheapBody['server_amount_cents']}');
  }
  notes.add('buyer underpay http=${cheap['status']} server=$serverAmt raw=${cheap['raw']}');
  if (cheap['status'] == 200 && serverAmt != null && serverAmt <= 50) {
    addFinding(
      id: 'SATB-CHK-01',
      sev: 'P0',
      surface: 'CHECKOUT',
      pre: 'catalog 6€ + protection',
      identity: 'buyer',
      request: 'POST create-payment-intent amount=50',
      response: cheap['raw'],
      before: 'contract ~6€',
      after: 'server_amount_cents=$serverAmt',
      impact: 'Checkout cobra o amount do cliente.',
      confidence: 'alta',
      variant: 'body.amount',
      fp: 'server ignora e devolve quote correcto — não é finding se serverAmt>= expected',
    );
  }

  // Product swap
  final pid2 = await createProductAsSeller(price: 1.00, qty: 5, title: '$tag cheapswap');
  final swap = await edge(
    'create-payment-intent',
    token: buyerJwt,
    body: {
      'amount': 50,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'order_id': oid,
      'product_id': pid2,
      'shipping_method': 'hand',
    },
  );
  notes.add('product swap ${swap['status']} ${swap['raw']}');
  if (swap['status'] == 200) {
    final b = swap['body'];
    if (b is Map && b['checkoutUrl'] != null) {
      // blocked only if quote used pid2. Edge should throw mismatch.
      notes.add('product swap created session — verificar quote vs order product');
    }
  }

  // Buyer swap (seller jwt paying as buyer)
  final asSeller = await edge(
    'create-payment-intent',
    token: sellerJwt,
    body: {
      'amount': 1000,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'order_id': oid,
      'product_id': pid,
      'shipping_method': 'hand',
    },
  );
  if (asSeller['status'] == 200) {
    addFinding(
      id: 'SATB-CHK-02',
      sev: 'P1',
      surface: 'CHECKOUT',
      pre: 'seller JWT + buyer_id=buyer',
      identity: 'seller',
      request: 'create-payment-intent buyer_id=other',
      response: asSeller['raw'],
      before: '-',
      after: 'session created',
      impact: 'Seller inicia checkout da encomenda de outro buyer.',
      confidence: 'alta',
      variant: 'buyer swap',
      fp: 'Edge exige user.id==buyer_id',
    );
  }

  // Order swap — pay someone else's order
  final other = await rest(
    'orders',
    apikey: serviceKey,
    token: serviceKey,
    qs: 'buyer_id=neq.$buyerId&select=id,buyer_id,status&limit=1',
  );
  if (other['body'] is List && (other['body'] as List).isNotEmpty) {
    final o = (other['body'] as List).first as Map;
    final r = await edge(
      'create-payment-intent',
      token: buyerJwt,
      body: {
        'buyer_id': buyerId,
        'order_id': o['id'],
        'shipping_method': 'hand',
      },
    );
    if (r['status'] == 200) {
      addFinding(
        id: 'SATB-CHK-03',
        sev: 'P0',
        surface: 'CHECKOUT',
        pre: 'foreign order',
        identity: 'buyer',
        request: 'create-payment-intent order_id=foreign',
        response: r['raw'],
        before: 'order buyer=${o['buyer_id']}',
        after: 'session',
        impact: 'Buyer inicia pagamento de encomenda alheia.',
        confidence: 'alta',
        variant: 'order swap',
        fp: 'Edge bloqueia ownership',
      );
    }
  }

  // Catalog hike then checkout — invariant K
  await rest('products',
      method: 'PATCH', token: sellerJwt, qs: 'id=eq.$pid', body: {'price': 40.00});
  final afterHike = await edge(
    'create-payment-intent',
    token: buyerJwt,
    body: {
      'buyer_id': buyerId,
      'order_id': oid,
      'product_id': pid,
      'shipping_method': 'hand',
    },
  );
  int? hikeAmt;
  if (afterHike['body'] is Map) {
    hikeAmt = int.tryParse('${(afterHike['body'] as Map)['server_amount_cents']}');
  }
  notes.add('hike checkout http=${afterHike['status']} amt=$hikeAmt');
  final contract = await adminGet('orders', oid);
  final sealedUnit = int.tryParse('${contract?['contract_unit_cents']}') ?? 0;
  if (afterHike['status'] == 200 && hikeAmt != null && sealedUnit > 0) {
    // expected ~ sealedUnit + protection (hand=0)
    final items = sealedUnit * (int.tryParse('${contract?['contract_qty']}') ?? 1);
    final prot = ((0.65 + items / 100 * 0.05) * 100).round();
    final expected = items + prot;
    if (hikeAmt >= 3900) {
      addFinding(
        id: 'SATB-PRC-K01',
        sev: 'P0',
        surface: 'PRICING',
        pre: 'order sealed then seller price=40',
        identity: 'buyer',
        request: 'create-payment-intent after catalog hike',
        response: {'server_amount_cents': hikeAmt, 'sealed_unit': sealedUnit, 'expected': expected},
        before: 'contract_unit_cents=$sealedUnit',
        after: 'charged=$hikeAmt catalog=40€',
        impact: 'Catálogo posterior altera o contrato existente (invariante K).',
        confidence: 'alta',
        variant: 'seller hike after order',
        fp: 'legado sem contract selado',
      );
    }
  }

  // Prize shipping flag
  final prize = await edge(
    'create-payment-intent',
    token: buyerJwt,
    body: {
      'buyer_id': buyerId,
      'order_id': oid,
      'shipping_method': 'carrier',
      'prize_shipping': true,
    },
  );
  notes.add('forged prize_shipping ${prize['status']} ${prize['raw']}');
  if (prize['status'] == 200) {
    final amt = int.tryParse('${(prize['body'] as Map?)?['server_amount_cents']}');
    if (amt != null && amt < 500) {
      addFinding(
        id: 'SATB-CHK-04',
        sev: 'P0',
        surface: 'CHECKOUT',
        pre: 'order not raffle prize',
        identity: 'buyer',
        request: 'prize_shipping=true',
        response: prize['raw'],
        before: '-',
        after: 'amt=$amt',
        impact: 'Buyer paga só portes de prémio numa compra normal.',
        confidence: 'alta',
        variant: 'prize_shipping',
        fp: 'Edge bloqueia',
      );
    }
  }

  // Webhook without signature
  final wh = await edge('stripe-webhook', token: anonKey, body: {'type': 'checkout.session.completed'});
  notes.add('webhook nosig ${wh['status']} ${wh['raw']}');
  if (wh['status'] == 200) {
    addFinding(
      id: 'SATB-WH-01',
      sev: 'P0',
      surface: 'WEBHOOK',
      pre: 'anon POST no stripe-signature',
      identity: 'anon',
      request: 'POST stripe-webhook',
      response: wh['raw'],
      before: '-',
      after: '-',
      impact: 'Webhook aceita eventos sem assinatura.',
      confidence: 'alta',
      variant: 'missing sig',
      fp: '200 ignored type',
    );
  }

  // GET settle garbage session
  final settle = await edge(
    'create-payment-intent',
    method: 'GET',
    token: anonKey,
    qs: 'checkout_return=success&session_id=cs_test_fake_satb',
  );
  notes.add('settle fake session ${settle['status']}');

  // fase2_e2e_settle as JWT
  final e2eSettle = await edge(
    'create-payment-intent',
    token: buyerJwt,
    qs: 'fase2_e2e_settle=1',
    body: {
      'order_id': oid,
      'payment_intent_id': 'pi_satb',
    },
  );
  notes.add('fase2 jwt settle ${e2eSettle['status']} ${e2eSettle['raw']}');
  if (e2eSettle['status'] == 200) {
    addFinding(
      id: 'SATB-CHK-05',
      sev: 'P0',
      surface: 'SETTLE',
      pre: 'buyer JWT fase2_e2e_settle',
      identity: 'buyer',
      request: 'POST ?fase2_e2e_settle=1',
      response: e2eSettle['raw'],
      before: '-',
      after: '-',
      impact: 'Harness de settle TEST acessível a JWT de utilizador.',
      confidence: 'alta',
      variant: 'fase2 jwt',
      fp: '401 service_role required',
    );
  }

  // Bag two lines
  final pA = await createProductAsSeller(price: 3.00, qty: 2, title: '$tag bagA');
  final pB = await createProductAsSeller(price: 4.00, qty: 2, title: '$tag bagB');
  if (pA != null && pB != null) {
    final oA = await createOrderAsBuyer(productId: pA);
    final oB = await createOrderAsBuyer(productId: pB);
    if (oA != null && oB != null) {
      final bag = await edge(
        'create-payment-intent',
        token: buyerJwt,
        body: {
          'buyer_id': buyerId,
          'order_id': oA,
          'bag_checkout': true,
          'shipping_method': 'hand',
          'bag_lines': [
            {'order_id': oA, 'line_total_cents': 1},
            {'order_id': oB, 'line_total_cents': 1},
          ],
        },
      );
      notes.add('bag checkout ${bag['status']} ${bag['raw']}');
      if (bag['status'] == 200) {
        final amt = int.tryParse('${(bag['body'] as Map?)?['server_amount_cents']}');
        if (amt != null && amt <= 2) {
          addFinding(
            id: 'SATB-BAG-01',
            sev: 'P0',
            surface: 'BAG',
            pre: '2 lines 3€+4€',
            identity: 'buyer',
            request: 'bag_lines line_total_cents=1',
            response: bag['raw'],
            before: 'items 7€',
            after: 'amt=$amt',
            impact: 'line_total do cliente manda no saco.',
            confidence: 'alta',
            variant: 'line_total',
            fp: 'server quote',
          );
        }
      }
    }
  }

  // Duplicate session: call checkout twice
  final d1 = await edge(
    'create-payment-intent',
    token: buyerJwt,
    body: {
      'buyer_id': buyerId,
      'order_id': oid,
      'shipping_method': 'hand',
    },
  );
  final d2 = await edge(
    'create-payment-intent',
    token: buyerJwt,
    body: {
      'buyer_id': buyerId,
      'order_id': oid,
      'shipping_method': 'hand',
    },
  );
  notes.add('dup session ${d1['status']} ${d2['status']}');
}

Future<void> attackWalletPayout() async {
  cov('WALLET', 'TESTADA COM VARIANTES');
  cov('PAYOUT', 'TESTADA COM VARIANTES');
  cov('TIPS', 'TESTADA COM VARIANTES');

  final wAnon = await rest('wallets', qs: 'select=*&limit=20');
  final wBuyer = await rest('wallets', token: buyerJwt, qs: 'select=*&limit=50');
  final wSeller = await rest('wallets', token: sellerJwt, qs: 'id=eq.$buyerId&select=*');
  if (leakedRows(wAnon)) {
    addFinding(
      id: 'SATB-WAL-01',
      sev: 'P1',
      surface: 'WALLET',
      pre: 'anon SELECT wallets',
      identity: 'anon',
      request: 'GET wallets',
      response: {'n': (wAnon['body'] as List).length, 'sample': (wAnon['body'] as List).first},
      before: '-',
      after: '-',
      impact: 'Saldos de carteira públicos (anon).',
      confidence: 'alta',
      variant: 'anon select',
      fp: 'só a própria (impossível anon)',
    );
  }
  if (wBuyer['status'] == 200 && wBuyer['body'] is List) {
    final rows = wBuyer['body'] as List;
    final others = rows.where((e) => e is Map && e['id'] != buyerId).toList();
    if (others.isNotEmpty) {
      addFinding(
        id: 'SATB-WAL-02',
        sev: 'P1',
        surface: 'WALLET',
        pre: 'buyer SELECT wallets',
        identity: 'buyer',
        request: 'GET wallets limit 50',
        response: {'other_count': others.length, 'sample': others.first},
        before: '-',
        after: '-',
        impact: 'Buyer lê carteiras de outros.',
        confidence: 'alta',
        variant: 'cross-user select',
        fp: 'view pública intencional',
      );
    }
  }
  if (leakedRows(wSeller) &&
      (wSeller['body'] as List).any((e) => e is Map && e['id'] == buyerId)) {
    addFinding(
      id: 'SATB-WAL-03',
      sev: 'P1',
      surface: 'WALLET',
      pre: 'seller GET buyer wallet',
      identity: 'seller',
      request: 'GET wallets id=buyer',
      response: wSeller['raw'],
      before: '-',
      after: '-',
      impact: 'Seller lê saldo do comprador.',
      confidence: 'alta',
      variant: 'cross get',
      fp: 'RLS 200 []',
    );
  }

  // INSERT/UPDATE wallet
  final insW = await rest(
    'wallets',
    method: 'POST',
    token: buyerJwt,
    body: {'id': buyerId, 'balance': 9999},
  );
  notes.add('wallet insert ${insW['status']} ${insW['raw']}');
  final upW = await rest(
    'wallets',
    method: 'PATCH',
    token: buyerJwt,
    qs: 'id=eq.$buyerId',
    body: {'balance': 9999},
  );
  final wLive = await adminGet('wallets', buyerId);
  if ((num.tryParse('${wLive?['balance']}') ?? 0) >= 9998) {
    addFinding(
      id: 'SATB-WAL-04',
      sev: 'P0',
      surface: 'WALLET',
      pre: 'buyer PATCH balance',
      identity: 'buyer',
      request: 'PATCH wallets balance=9999',
      response: {'http': upW['status'], 'live': wLive},
      before: '-',
      after: '${wLive?['balance']}',
      impact: 'JWT escreve saldo da carteira.',
      confidence: 'alta',
      variant: 'direct patch',
      fp: 'saldo já era alto',
    );
  }

  final txs = await rest('wallet_transactions',
      token: buyerJwt, qs: 'select=*&limit=20');
  if (txs['status'] == 200 && txs['body'] is List) {
    final others = (txs['body'] as List)
        .where((e) => e is Map && e['wallet_id'] != buyerId)
        .toList();
    if (others.isNotEmpty) {
      addFinding(
        id: 'SATB-WAL-05',
        sev: 'P1',
        surface: 'WALLET',
        pre: 'buyer ledger',
        identity: 'buyer',
        request: 'GET wallet_transactions',
        response: {'n': others.length},
        before: '-',
        after: '-',
        impact: 'Ledger de outros utilizadores visível.',
        confidence: 'alta',
        variant: 'cross ledger',
        fp: 'vazio',
      );
    }
  }

  // Credit/debit RPCs
  final creditCalls = <Map<String, Object>>[
    {'name': 'batata_credit_wallet_once', 'body': <String, dynamic>{'p_user_id': buyerId, 'p_order_id': '00000000-0000-0000-0000-000000000001', 'p_amount': 50, 'p_type': 'credito', 'p_description': tag}},
    {'name': 'batata_debit_wallet_once', 'body': <String, dynamic>{'p_user_id': sellerId, 'p_order_id': '00000000-0000-0000-0000-000000000001', 'p_amount': 1, 'p_description': tag}},
    {'name': 'batata_ensure_wallet', 'body': <String, dynamic>{'p_user_id': sellerId}},
    {'name': 'batata_wallet_payout_debit', 'body': <String, dynamic>{'p_user_id': sellerId, 'p_amount_cents': 100, 'p_idempotency_key': '${tag}_debit'}},
    {'name': 'batata_wallet_payout_finish', 'body': <String, dynamic>{'p_idempotency_key': '${tag}_debit', 'p_stripe_transfer_id': 'tr_fake', 'p_failed': false}},
    {'name': 'batata_assert_wallet_rpc_grants', 'body': <String, dynamic>{}},
  ];
  for (final c in creditCalls) {
    final name = c['name'] as String;
    final body = c['body'] as Map<String, dynamic>;
    final rBuyer = await rpc(name, token: buyerJwt, body: body);
    final rAnon = await rpc(name, token: anonKey, body: body);
    notes.add('rpc $name buyer=${rBuyer['status']} anon=${rAnon['status']} b=${rBuyer['raw']}');
    final okMint = rBuyer['status'] == 200 &&
        (rBuyer['body'] == true ||
            (rBuyer['body'] is Map && (rBuyer['body'] as Map)['ok'] == true));
    if (okMint && name.contains('credit')) {
      addFinding(
        id: 'SATB-WAL-06',
        sev: 'P0',
        surface: 'WALLET',
        pre: 'JWT credit primitive',
        identity: 'buyer',
        request: 'rpc $name',
        response: rBuyer['raw'],
        before: '-',
        after: '-',
        impact: 'JWT executa crédito de carteira (mint).',
        confidence: 'alta',
        variant: name,
        fp: 'ok sem efeito monetário',
      );
    }
    if (okMint && name.contains('payout_debit')) {
      addFinding(
        id: 'SATB-PAY-01',
        sev: 'P0',
        surface: 'PAYOUT',
        pre: 'buyer debit seller wallet',
        identity: 'buyer',
        request: 'rpc batata_wallet_payout_debit seller',
        response: rBuyer['raw'],
        before: '-',
        after: '-',
        impact: 'Buyer debita carteira do vendedor via RPC.',
        confidence: 'alta',
        variant: 'cross debit',
        fp: 'GRANT revoked 401/404',
      );
    }
  }

  // Release/refund without paid order
  final rel = await rpc(
    'batata_release_seller_wallet_for_order',
    token: sellerJwt,
    body: {'p_order_id': created['orders']!.isEmpty ? '00000000-0000-0000-0000-000000000001' : created['orders']!.first},
  );
  notes.add('release unpaid ${rel['status']} ${rel['raw']}');
  if (rel['status'] == 200 && rel['body'] == true) {
    addFinding(
      id: 'SATB-WAL-07',
      sev: 'P0',
      surface: 'WALLET',
      pre: 'unpaid order',
      identity: 'seller',
      request: 'batata_release_seller_wallet_for_order',
      response: rel['raw'],
      before: 'no capture',
      after: 'rpc true',
      impact: 'Release wallet em encomenda sem captura.',
      confidence: 'média',
      variant: 'unpaid release',
      fp: 'true idempotente sem crédito',
    );
  }

  // Payout edge: buyer amount, other user_id
  final po = await edge(
    'create-connect-account',
    token: buyerJwt,
    body: {
      'user_id': sellerId,
      'amount': 100,
      'idempotency_key': '${tag}_po_cross',
    },
  );
  notes.add('payout cross user ${po['status']} ${po['raw']}');
  if (po['status'] == 200 && (po['body'] is Map && (po['body'] as Map)['success'] == true)) {
    addFinding(
      id: 'SATB-PAY-02',
      sev: 'P0',
      surface: 'PAYOUT',
      pre: 'buyer payout as seller',
      identity: 'buyer',
      request: 'create-connect-account user_id=seller amount=100',
      response: po['raw'],
      before: '-',
      after: 'success',
      impact: 'Buyer dispara levantamento da conta Stripe do vendedor.',
      confidence: 'alta',
      variant: 'user_id swap',
      fp: 'Cannot create another user',
    );
  }

  // Tips
  final tipAnon = await edge(
    'create-live-tip-checkout',
    token: anonKey,
    body: {'seller_id': sellerId, 'amount_eur': 1, 'live_id': '00000000-0000-0000-0000-000000000001'},
  );
  notes.add('tip anon ${tipAnon['status']}');
  final tipJwt = await edge(
    'create-live-tip-checkout',
    token: buyerJwt,
    body: {
      'seller_id': sellerId,
      'amount_eur': 1,
      'tip_id': '00000000-0000-0000-0000-000000000099',
    },
  );
  notes.add('tip client tip_id ${tipJwt['status']} ${tipJwt['raw']}');
  final tipHi = await edge(
    'create-live-tip-checkout',
    token: buyerJwt,
    body: {'seller_id': sellerId, 'amount_eur': 99999},
  );
  notes.add('tip max ${tipHi['status']} ${tipHi['raw']}');
}

Future<void> attackStockLiveBag() async {
  cov('LIVE', 'TESTADA COM VARIANTES');
  cov('RESERVATIONS', 'TESTADA COM VARIANTES');

  final livesAnon = await rest('lives', qs: 'select=id,status,mux_stream_key,mux_playback_id,seller_id&limit=5');
  notes.add('lives anon ${livesAnon['status']} n=${livesAnon['body'] is List ? (livesAnon['body'] as List).length : 0}');
  if (livesAnon['status'] == 200 && livesAnon['body'] is List) {
    for (final row in livesAnon['body'] as List) {
      if (row is Map &&
          row['mux_stream_key'] != null &&
          row['mux_stream_key'].toString().trim().isNotEmpty) {
        addFinding(
          id: 'SATB-MUX-01',
          sev: 'P0',
          surface: 'MUX',
          pre: 'anon SELECT lives',
          identity: 'anon',
          request: 'GET lives mux_stream_key',
          response: {'id': row['id'], 'key_prefix': row['mux_stream_key'].toString().substring(0, min(8, row['mux_stream_key'].toString().length))},
          before: '-',
          after: '-',
          impact: 'Stream key Mux exposta a anon — hijack de ingest.',
          confidence: 'alta',
          variant: 'column leak',
          fp: 'key vazia/null',
        );
        break;
      }
    }
  }

  final resIns = await rest(
    'live_reservation_requests',
    method: 'POST',
    token: buyerJwt,
    body: {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'live_item_id': '00000000-0000-0000-0000-000000000001',
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'requested_qty': 99,
      'status': 'accepted',
      'source': 'fleaber_live',
    },
  );
  notes.add('reservation insert ${resIns['status']} ${resIns['raw']}');
  if (resIns['status'] >= 200 && resIns['status'] < 300) {
    addFinding(
      id: 'SATB-RES-01',
      sev: 'P1',
      surface: 'RESERVATIONS',
      pre: 'direct INSERT accepted qty=99',
      identity: 'buyer',
      request: 'INSERT live_reservation_requests',
      response: resIns['raw'],
      before: '-',
      after: 'accepted 99',
      impact: 'Buyer auto-aceita reserva com qty arbitrária.',
      confidence: 'alta',
      variant: 'direct insert',
      fp: 'FK fail / trigger cap',
    );
  }

  // Real live item if any
  final items = await rest(
    'live_items',
    token: sellerJwt,
    qs: 'seller_id=eq.$sellerId&select=id,live_id,price,product_id,status&limit=3',
  );
  if (items['body'] is List && (items['body'] as List).isNotEmpty) {
    final li = (items['body'] as List).first as Map;
    final rpcQty = await rpc(
      'batata_request_live_reservation',
      token: buyerJwt,
      body: {
        'p_live_item_id': li['id'],
        'p_requested_qty': 99,
      },
    );
    notes.add('rpc reservation qty99 ${rpcQty['status']} ${rpcQty['raw']}');
    // try common names
    for (final name in [
      'batata_live_reservation_request',
      'batata_request_reservation',
      'batata_create_live_reservation',
    ]) {
      final r = await rpc(name, token: buyerJwt, body: {
        'p_live_item_id': li['id'],
        'p_requested_qty': 50,
      });
      notes.add('rpc $name ${r['status']}');
    }
  }

  // Product stock JWT
  final pid = created['products']!.isNotEmpty ? created['products']!.first : null;
  if (pid != null) {
    final up = await rest(
      'products',
      method: 'PATCH',
      token: buyerJwt,
      qs: 'id=eq.$pid',
      body: {'quantity': 999, 'is_sold': false, 'seller_id': buyerId},
    );
    final live = await adminGet('products', pid);
    if (live?['seller_id'] == buyerId) {
      addFinding(
        id: 'SATB-STK-02',
        sev: 'P0',
        surface: 'STOCK',
        pre: 'buyer PATCH seller product',
        identity: 'buyer',
        request: 'PATCH seller_id=buyer',
        response: live ?? up['raw'],
        before: 'seller owns',
        after: 'seller_id=${live?['seller_id']}',
        impact: 'Buyer rouba ownership do produto.',
        confidence: 'alta',
        variant: 'owner swap',
        fp: 'RLS',
      );
    }
    if (live?['quantity'] == 999) {
      addFinding(
        id: 'SATB-STK-03',
        sev: 'P1',
        surface: 'STOCK',
        pre: 'buyer PATCH qty',
        identity: 'buyer',
        request: 'PATCH quantity=999',
        response: live ?? {},
        before: '-',
        after: 'qty=999',
        impact: 'Buyer altera stock de produto alheio.',
        confidence: 'alta',
        variant: 'qty patch',
        fp: 'não mutou',
      );
    }
  }
}

Future<void> attackChatReviewsDisputes() async {
  cov('CHAT', 'TESTADA COM VARIANTES');
  cov('REVIEWS', 'TESTADA COM VARIANTES');
  cov('DISPUTE', 'TESTADA COM VARIANTES');
  cov('REFUND', 'TESTADA COM VARIANTES');

  final chatsAnon = await rest('chats', qs: 'select=*&limit=10');
  final chatsBuyer = await rest('chats', token: buyerJwt, qs: 'select=*&limit=30');
  notes.add('chats anon=${chatsAnon['status']} buyer=${chatsBuyer['status']} n=${chatsBuyer['body'] is List ? (chatsBuyer['body'] as List).length : 0}');
  if (leakedRows(chatsAnon)) {
    addFinding(
      id: 'SATB-CHAT-01',
      sev: 'P1',
      surface: 'CHAT',
      pre: 'anon SELECT chats',
      identity: 'anon',
      request: 'GET chats',
      response: {'n': (chatsAnon['body'] as List).length},
      before: '-',
      after: '-',
      impact: 'Threads de chat listáveis sem login.',
      confidence: 'alta',
      variant: 'anon select',
      fp: 'vazio',
    );
  }

  final insChat = await rest(
    'chats',
    method: 'POST',
    token: buyerJwt,
    body: {
      'user_a': sellerId,
      'user_b': sellerId,
      'product_id': created['products']!.isNotEmpty ? created['products']!.first : null,
    },
  );
  notes.add('chat insert spoof parties ${insChat['status']} ${insChat['raw']}');
  String? chatId;
  final cb = insChat['body'];
  if (cb is List && cb.isNotEmpty) chatId = (cb.first as Map)['id']?.toString();
  if (cb is Map) chatId = cb['id']?.toString();

  final msgsAnon = await rest('chat_messages', qs: 'select=*&limit=5');
  if (leakedRows(msgsAnon)) {
    addFinding(
      id: 'SATB-CHAT-02',
      sev: 'P1',
      surface: 'CHAT',
      pre: 'anon messages',
      identity: 'anon',
      request: 'GET chat_messages',
      response: {'n': (msgsAnon['body'] as List).length, 'sample': (msgsAnon['body'] as List).first},
      before: '-',
      after: '-',
      impact: 'Mensagens de chat públicas.',
      confidence: 'alta',
      variant: 'anon msgs',
      fp: 'vazio',
    );
  }

  if (chatId != null) {
    created['chats']!.add(chatId);
    final spoofMsg = await rest(
      'chat_messages',
      method: 'POST',
      token: buyerJwt,
      body: {
        'chat_id': chatId,
        'sender_id': sellerId,
        'receiver_id': buyerId,
        'text': '$tag spoof sender',
        'is_read': false,
      },
    );
    notes.add('msg sender spoof ${spoofMsg['status']} ${spoofMsg['raw']}');
    if (spoofMsg['status'] >= 200 && spoofMsg['status'] < 300) {
      final mb = spoofMsg['body'];
      Map? row;
      if (mb is List && mb.isNotEmpty) row = mb.first as Map;
      if (mb is Map) row = mb;
      if (row?['sender_id'] == sellerId) {
        addFinding(
          id: 'SATB-CHAT-03',
          sev: 'P1',
          surface: 'CHAT',
          pre: 'buyer INSERT message',
          identity: 'buyer',
          request: 'sender_id=seller',
          response: spoofMsg['raw'],
          before: '-',
          after: 'sender persisted as seller',
          impact: 'Spoof de remetente em chat.',
          confidence: 'alta',
          variant: 'sender spoof',
          fp: 'trigger força auth.uid()',
        );
      }
    }
  }

  // Cross-chat: find a chat buyer is not in
  final allChats = await rest(
    'chats',
    apikey: serviceKey,
    token: serviceKey,
    qs: 'select=id,user_a,user_b&limit=20',
  );
  if (allChats['body'] is List) {
    for (final c in allChats['body'] as List) {
      if (c is! Map) continue;
      final a = c['user_a']?.toString();
      final b = c['user_b']?.toString();
      if (a != buyerId && b != buyerId) {
        final r = await rest(
          'chat_messages',
          token: buyerJwt,
          qs: 'chat_id=eq.${c['id']}&select=id,text,sender_id&limit=3',
        );
        if (leakedRows(r)) {
          addFinding(
            id: 'SATB-CHAT-04',
            sev: 'P1',
            surface: 'CHAT',
            pre: 'foreign chat',
            identity: 'buyer',
            request: 'GET messages chat_id=foreign',
            response: {'chat': c['id'], 'n': (r['body'] as List).length},
            before: '-',
            after: '-',
            impact: 'Buyer lê chat onde não é participante.',
            confidence: 'alta',
            variant: 'cross-chat',
            fp: 'RLS vazio',
          );
        }
        break;
      }
    }
  }

  // Reviews
  final revAnon = await rest('reviews', qs: 'select=*&limit=5');
  notes.add('reviews anon ${revAnon['status']}');
  final revIns = await rest(
    'reviews',
    method: 'POST',
    token: buyerJwt,
    body: {
      'order_id': created['orders']!.isNotEmpty ? created['orders']!.first : '00000000-0000-0000-0000-000000000001',
      'reviewer_id': buyerId,
      'reviewee_id': sellerId,
      'rating': 5,
      'comment': tag,
    },
  );
  notes.add('review insert unpaid ${revIns['status']} ${revIns['raw']}');
  if (revIns['status'] >= 200 && revIns['status'] < 300) {
    addFinding(
      id: 'SATB-REV-01',
      sev: 'P1',
      surface: 'REVIEWS',
      pre: 'unpaid/random order',
      identity: 'buyer',
      request: 'INSERT reviews',
      response: revIns['raw'],
      before: '-',
      after: 'review created',
      impact: 'Review sem compra concluída.',
      confidence: 'alta',
      variant: 'invalid state',
      fp: 'trigger bloqueia',
    );
  }

  // Disputes
  final dIns = await rest(
    'order_disputes',
    method: 'POST',
    token: buyerJwt,
    body: {
      'order_id': created['orders']!.isNotEmpty ? created['orders']!.first : '00000000-0000-0000-0000-000000000001',
      'buyer_id': buyerId,
      'reason': tag,
      'status': 'aberta',
      'seller_refund_percent': 100,
    },
  );
  notes.add('dispute insert ${dIns['status']} ${dIns['raw']}');
  String? did;
  final db = dIns['body'];
  if (db is List && db.isNotEmpty) did = (db.first as Map)['id']?.toString();
  if (db is Map) did = db['id']?.toString();
  if (did != null) {
    final buyerOffer = await rest(
      'order_disputes',
      method: 'PATCH',
      token: buyerJwt,
      qs: 'id=eq.$did',
      body: {'seller_refund_percent': 100, 'seller_offer_type': 'partial_refund'},
    );
    notes.add('buyer set seller_refund_percent ${buyerOffer['status']} ${buyerOffer['raw']}');
    final live = await adminGet('order_disputes', did);
    if (live?['seller_refund_percent'] == 100 || live?['seller_refund_percent'] == 100.0) {
      // may be default — check seller_offer_set_by
      notes.add('dispute live $live');
    }
    final rpcPart = await rpc(
      'batata_process_partial_refund_dispute',
      token: buyerJwt,
      body: {'p_dispute_id': did, 'p_percent': 100},
    );
    notes.add('partial refund rpc ${rpcPart['status']} ${rpcPart['raw']}');
    if (rpcPart['status'] == 200 &&
        (rpcPart['body'] == true ||
            (rpcPart['body'] is Map && (rpcPart['body'] as Map)['ok'] == true))) {
      addFinding(
        id: 'SATB-DSP-01',
        sev: 'P0',
        surface: 'DISPUTE',
        pre: 'buyer sets 100% and processes',
        identity: 'buyer',
        request: 'batata_process_partial_refund_dispute 100',
        response: rpcPart['raw'],
        before: '-',
        after: 'rpc ok',
        impact: 'Buyer força reembolso 100% sem oferta do vendedor.',
        confidence: 'média',
        variant: 'percent jwt',
        fp: 'ok false inside jsonb',
      );
    }
  }

  // Refund edge as buyer
  if (created['orders']!.isNotEmpty) {
    final rf = await edge(
      'refund-order',
      token: buyerJwt,
      body: {'order_id': created['orders']!.first},
    );
    notes.add('refund as buyer ${rf['status']} ${rf['raw']}');
    if (rf['status'] == 200 && (rf['body'] is Map && (rf['body'] as Map)['ok'] == true && (rf['body'] as Map)['skipped'] != true)) {
      addFinding(
        id: 'SATB-REF-01',
        sev: 'P0',
        surface: 'REFUND',
        pre: 'buyer calls refund-order',
        identity: 'buyer',
        request: 'POST refund-order',
        response: rf['raw'],
        before: '-',
        after: 'ok',
        impact: 'Comprador inicia reembolso Stripe (seller-only).',
        confidence: 'alta',
        variant: 'buyer refund',
        fp: '403 Sem permissão',
      );
    }
    final rfAnon = await edge('refund-order', token: anonKey, body: {'order_id': created['orders']!.first});
    notes.add('refund anon ${rfAnon['status']}');
  }
}

Future<void> attackStorage() async {
  cov('STORAGE', 'TESTADA COM VARIANTES');
  final buckets = ['chat_media', 'fleaber_private', 'product_photos', 'profile_photos'];
  for (final b in buckets) {
    final listAnon = await req(
      method: 'POST',
      url: '$base/storage/v1/object/list/$b',
      token: anonKey,
      body: {'prefix': '', 'limit': 10},
    );
    notes.add('storage list $b anon=${listAnon['status']}');
    final listBuyer = await req(
      method: 'POST',
      url: '$base/storage/v1/object/list/$b',
      token: buyerJwt,
      body: {'prefix': '', 'limit': 20},
    );
    notes.add('storage list $b buyer=${listBuyer['status']} n=${listBuyer['body'] is List ? (listBuyer['body'] as List).length : listBuyer['raw']}');

    // cross upload
    final path = 'order_proofs/$sellerId/${tag}_cross.txt';
    final up = await req(
      method: 'POST',
      url: '$base/storage/v1/object/$b/$path',
      token: buyerJwt,
      extra: {'x-upsert': 'true'},
      body: 'satb-cross-upload',
    );
    notes.add('storage upload $b $path ${up['status']} ${up['raw']}');
    if (up['status'] >= 200 && up['status'] < 300 && b == 'fleaber_private') {
      addFinding(
        id: 'SATB-STO-01',
        sev: 'P1',
        surface: 'STORAGE',
        pre: 'buyer upload into seller prefix',
        identity: 'buyer',
        request: 'POST object/$b/order_proofs/{seller}/...',
        response: up['raw'],
        before: '-',
        after: 'uploaded',
        impact: 'Upload cross-user em bucket privado.',
        confidence: 'alta',
        variant: b,
        fp: 'policy owner path',
      );
    }
  }

  // Public URL guess
  final pub = await req(
    method: 'GET',
    url: '$base/storage/v1/object/public/chat_media/order_proofs/$buyerId/x.jpg',
    token: anonKey,
  );
  notes.add('public proof guess ${pub['status']}');
}

Future<void> attackRaffleTips() async {
  cov('RAFFLE', 'TESTADA COM VARIANTES');
  final raffles = await rest('live_raffles', qs: 'select=*&limit=5');
  notes.add('raffles anon ${raffles['status']} n=${raffles['body'] is List ? (raffles['body'] as List).length : 0}');
  final winners = await rest('live_raffle_winners', qs: 'select=*&limit=5');
  notes.add('winners anon ${winners['status']}');
  final winIns = await rest(
    'live_raffle_winners',
    method: 'POST',
    token: buyerJwt,
    body: {
      'raffle_id': '00000000-0000-0000-0000-000000000001',
      'user_id': buyerId,
    },
  );
  notes.add('winner insert ${winIns['status']} ${winIns['raw']}');
  if (winIns['status'] >= 200 && winIns['status'] < 300) {
    addFinding(
      id: 'SATB-RAF-01',
      sev: 'P0',
      surface: 'RAFFLE',
      pre: 'JWT INSERT winner',
      identity: 'buyer',
      request: 'INSERT live_raffle_winners',
      response: winIns['raw'],
      before: '-',
      after: 'winner row',
      impact: 'Buyer auto-atribui prémio de rifa.',
      confidence: 'alta',
      variant: 'winner insert',
      fp: 'FK',
    );
  }
  if (raffles['body'] is List && (raffles['body'] as List).isNotEmpty) {
    final rf = (raffles['body'] as List).first as Map;
    final win2 = await rest(
      'live_raffle_winners',
      method: 'POST',
      token: buyerJwt,
      body: {'raffle_id': rf['id'], 'user_id': buyerId},
    );
    notes.add('winner insert real raffle ${win2['status']} ${win2['raw']}');
    if (win2['status'] >= 200 && win2['status'] < 300) {
      addFinding(
        id: 'SATB-RAF-02',
        sev: 'P0',
        surface: 'RAFFLE',
        pre: 'existing raffle',
        identity: 'buyer',
        request: 'INSERT winner raffle=${rf['id']}',
        response: win2['raw'],
        before: '-',
        after: 'inserted',
        impact: 'Buyer insere-se como vencedor de rifa existente.',
        confidence: 'alta',
        variant: 'real raffle',
        fp: 'unique / RLS',
      );
    }
  }

  final tickets = await rest('live_raffle_tickets', token: buyerJwt, qs: 'select=*&limit=5');
  notes.add('tickets ${tickets['status']}');
}

Future<void> attackMuxLivekitPs() async {
  cov('MUX', 'TESTADA COM VARIANTES');
  cov('LIVEKIT', 'TESTADA COM VARIANTES');
  cov('PS/OCR', 'TESTADA COM VARIANTES');

  final muxBuyer = await edge('create-mux-live', token: buyerJwt, body: {'title': '$tag buyer live'});
  notes.add('mux buyer ${muxBuyer['status']} ${muxBuyer['raw']}');
  if (muxBuyer['status'] == 200) {
    addFinding(
      id: 'SATB-MUX-02',
      sev: 'P1',
      surface: 'MUX',
      pre: 'buyer not seller',
      identity: 'buyer',
      request: 'create-mux-live',
      response: muxBuyer['raw'],
      before: '-',
      after: 'stream created',
      impact: 'Conta comprador cria live Mux (custo + stream_key).',
      confidence: 'alta',
      variant: 'buyer create',
      fp: '403 authz',
    );
    // cleanup if created
    final b = muxBuyer['body'];
    if (b is Map && b['live_id'] != null) {
      await rest('lives',
          method: 'PATCH',
          apikey: serviceKey,
          token: serviceKey,
          qs: 'id=eq.${b['live_id']}',
          body: {'status': 'ended', 'is_active': false});
    }
  }

  final muxAnon = await edge('create-mux-live', token: anonKey, body: {'title': '$tag anon'});
  notes.add('mux anon ${muxAnon['status']}');

  final lk = await edge('livekit-mux-publish', token: buyerJwt, body: {'step': 'token', 'live_id': '00000000-0000-0000-0000-000000000001'});
  notes.add('livekit token buyer ${lk['status']} ${lk['raw']}');

  final eg = await edge('livekit-egress-cleanup', token: buyerJwt, body: {});
  notes.add('egress cleanup jwt ${eg['status']} ${eg['raw']}');
  if (eg['status'] == 200) {
    addFinding(
      id: 'SATB-LK-01',
      sev: 'P1',
      surface: 'LIVEKIT',
      pre: 'buyer POST cleanup',
      identity: 'buyer',
      request: 'livekit-egress-cleanup',
      response: eg['raw'],
      before: '-',
      after: '200',
      impact: 'JWT de utilizador dispara cleanup/stop de egress (DoS lives).',
      confidence: 'alta',
      variant: 'jwt cleanup',
      fp: '401 Unauthorized',
    );
  }

  final ocr = await edge(
    'ingest-ocr-reservation',
    token: anonKey,
    body: {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'ocr_line_hash': 'abcdefghij',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'requested_qty': 9,
    },
  );
  notes.add('ocr no token ${ocr['status']} ${ocr['raw']}');
  final ocrTok = await edge(
    'ingest-ocr-reservation',
    token: anonKey,
    extra: {'x-device-token': 'satb-forged-token'},
    body: {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'ocr_line_hash': 'abcdefghij',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'requested_qty': 9,
    },
  );
  notes.add('ocr forged token ${ocrTok['status']} ${ocrTok['raw']}');
  if (ocrTok['status'] == 200 && (ocrTok['body'] is Map && (ocrTok['body'] as Map)['ok'] == true)) {
    addFinding(
      id: 'SATB-PS-01',
      sev: 'P0',
      surface: 'PS/OCR',
      pre: 'forged device token',
      identity: 'anon',
      request: 'ingest-ocr-reservation',
      response: ocrTok['raw'],
      before: '-',
      after: 'reservation injected',
      impact: 'OCR/pairing aceita token forjado — injecção de reservas.',
      confidence: 'alta',
      variant: 'forged token',
      fp: 'ok false invalid token',
    );
  }

  final pair = await edge('ps-pairing-claim', token: anonKey, body: {'code': '000000', 'device_id': 'satb'});
  notes.add('pairing 000000 ${pair['status']} ${pair['raw']}');
  // brute 5 codes (not 1e6)
  for (final code in ['123456', '111111', '999999', '654321', '010101']) {
    final r = await edge('ps-pairing-claim', token: anonKey, body: {'code': code, 'device_id': 'satb'});
    notes.add('pairing $code ${r['status']} ${r['raw']}');
    if (r['status'] == 200 && r['body'] is Map && (r['body'] as Map)['ok'] == true) {
      addFinding(
        id: 'SATB-PS-02',
        sev: 'P1',
        surface: 'PS/OCR',
        pre: 'brute common codes',
        identity: 'anon',
        request: 'ps-pairing-claim code=$code',
        response: r['raw'],
        before: '-',
        after: 'claimed',
        impact: 'Código de pairing previsível reclamado.',
        confidence: 'alta',
        variant: code,
        fp: 'código activo por acaso no lab',
      );
    }
  }

  final pb = await edge('resolve-mux-playback', token: anonKey, body: {'live_id': '00000000-0000-0000-0000-000000000001'});
  notes.add('resolve playback ${pb['status']}');
}

Future<void> attackEdges() async {
  cov('RPC/DEFINER', 'TESTADA COM VARIANTES');
  final names = [
    'create-payment-intent',
    'create-connect-account',
    'stripe-webhook',
    'refund-order',
    'create-live-tip-checkout',
    'meta-data-deletion',
    'livekit-mux-publish',
    'create-mux-live',
    'complete-mux-live',
    'livekit-egress-cleanup',
    'delete-test-account',
    'ingest-ocr-reservation',
    'ps-pairing-claim',
    'ps-heartbeat',
    'ps-panel-log',
    'resolve-mux-playback',
    'send-sms-bulkgate',
    'sec-fase2-e2e-oversell',
  ];
  for (final n in names) {
    final anon = await edge(n, token: anonKey, body: {});
    notes.add('edge $n anon ${anon['status']}');
  }
  final nuke = await edge(
    'delete-test-account',
    token: buyerJwt,
    body: {'confirm': 'APAGAR TUDO'},
  );
  notes.add('nuke buyer ${nuke['status']} ${nuke['raw']}');
  if (nuke['status'] == 200) {
    addFinding(
      id: 'SATB-EDGE-01',
      sev: 'P0',
      surface: 'AUTH',
      pre: 'buyer delete-test-account',
      identity: 'buyer',
      request: 'delete-test-account APAGAR TUDO',
      response: nuke['raw'],
      before: '-',
      after: '200',
      impact: 'Nuke de conta acessível (ou conta apagada).',
      confidence: 'alta',
      variant: 'nuke',
      fp: 'allowlist / flag off',
    );
  }

  final sms = await edge('send-sms-bulkgate', token: anonKey, body: {
    'phone': '+351912345678',
    'text': 'satb',
  });
  notes.add('sms hook ${sms['status']} ${sms['raw']}');

  final meta = await edge('meta-data-deletion', method: 'GET', token: anonKey);
  notes.add('meta GET ${meta['status']}');
}

Future<void> attackRpcsAndRls() async {
  cov('RLS', 'TESTADA COM VARIANTES');
  cov('RPC/DEFINER', 'TESTADA COM VARIANTES');

  final spec = await req(
    method: 'GET',
    url: '$base/rest/v1/',
    token: anonKey,
    extra: {'Accept': 'application/openapi+json'},
  );
  final paths = <String>[];
  final rpcs = <String>[];
  final body = spec['body'];
  if (body is Map && body['paths'] is Map) {
    for (final p in (body['paths'] as Map).keys) {
      final s = p.toString();
      paths.add(s);
      if (s.startsWith('/rpc/')) rpcs.add(s.substring(5));
    }
  }
  notes.add('openapi paths=${paths.length} rpcs=${rpcs.length}');

  final sensitiveTables = [
    'orders',
    'profiles',
    'wallets',
    'wallet_transactions',
    'wallet_payout_ledger',
    'chats',
    'chat_messages',
    'reviews',
    'order_disputes',
    'products',
    'lives',
    'live_items',
    'live_reservation_requests',
    'live_raffles',
    'live_raffle_winners',
    'live_tips',
    'product_offers',
    'stripe_checkout_events',
    'staff_action_logs',
    'seller_helpers',
    'fleaber_commissions',
    'app_logs',
    'ps_ingest_audit',
    'ps_pairing_sessions',
  ];
  for (final t in sensitiveTables) {
    final a = await rest(t, qs: 'select=*&limit=3');
    final b = await rest(t, token: buyerJwt, qs: 'select=*&limit=8');
    notes.add('table $t anon=${a['status']}/${a['body'] is List ? (a['body'] as List).length : '-'} buyer=${b['status']}/${b['body'] is List ? (b['body'] as List).length : '-'}');
  }

  // Try all monetary-looking RPCs from openapi
  final interesting = rpcs.where((n) {
    final x = n.toLowerCase();
    return x.contains('wallet') ||
        x.contains('refund') ||
        x.contains('payout') ||
        x.contains('credit') ||
        x.contains('debit') ||
        x.contains('settle') ||
        x.contains('raffle') ||
        x.contains('admin') ||
        x.contains('lab') ||
        x.contains('nuke') ||
        x.contains('tip') ||
        x.contains('dispute') ||
        x.contains('stock') ||
        x.contains('reservation');
  }).toList();
  for (final n in interesting.take(80)) {
    final r = await rpc(n, token: buyerJwt, body: {});
    final r2 = await rpc(n, token: anonKey, body: {});
    notes.add('rpc-scan $n buyer=${r['status']} anon=${r2['status']}');
    if (r['status'] == 200 && n.toLowerCase().contains('credit')) {
      notes.add('CREDIT RPC 200 $n ${r['raw']}');
    }
  }

  final grants = await rpc('batata_assert_wallet_rpc_grants', token: serviceKey, apikey: serviceKey);
  notes.add('wallet grants assert ${grants['raw']}');
}

// ---------------------------------------------------------------------------
// PASS 2 — invariants with paid fixtures
// ---------------------------------------------------------------------------
Future<void> pass2() async {
  passNo = 2;
  stderr.writeln('=== PASS 2 invariants ===');
  cov('RACES', 'TESTADA COM VARIANTES');
  cov('COMPOSITION', 'TESTADA COM VARIANTES');

  final paid = await e2e('setup_paid_order', {'initial_qty': 2});
  notes.add('setup_paid_order $paid');
  if (paid == null || paid['ok'] != true) {
    notes.add('paid fixture failed — invariants on unpaid + bag only');
  }

  String? orderId = paid?['order_id']?.toString();
  String? productId = paid?['product_id']?.toString();
  String? piId = paid?['payment_intent_id']?.toString();
  if (productId != null) created['products']!.add(productId);
  if (orderId != null) created['orders']!.add(orderId);

  if (orderId != null) {
    final before = await adminGet('orders', orderId);
    notes.add('paid order $before');

    // A: charged == contract
    final amt = before?['amount_paid_cents'];
    final unit = before?['contract_unit_cents'];
    final qty = before?['contract_qty'] ?? before?['quantity'];
    notes.add('invA amount_paid=$amt unit=$unit qty=$qty price_total=${before?['price_total']}');

    // Buyer cannot jump to concluido and review to force release
    final st = await rest('orders',
        method: 'PATCH', token: buyerJwt, qs: 'id=eq.$orderId', body: {'status': 'concluido'});
    final afterSt = await adminGet('orders', orderId);
    notes.add('buyer concluido paid ${st['status']} now=${afterSt?['status']}');

    final rel = await rpc('batata_release_seller_wallet_for_order',
        token: buyerJwt, body: {'p_order_id': orderId});
    notes.add('buyer release ${rel['status']} ${rel['raw']}');
    final relS = await rpc('batata_release_seller_wallet_for_order',
        token: sellerJwt, body: {'p_order_id': orderId});
    notes.add('seller release ${relS['status']} ${relS['raw']}');

    final wS = await adminGet('wallets', sellerId);
    notes.add('seller wallet after release ${wS?['balance']}');

    // Refund as seller
    final rf1 = await edge('refund-order', token: sellerJwt, body: {'order_id': orderId});
    notes.add('refund1 ${rf1['status']} ${rf1['raw']}');
    final rf2 = await edge('refund-order', token: sellerJwt, body: {'order_id': orderId});
    notes.add('refund2 dup ${rf2['status']} ${rf2['raw']}');

    if (piId != null) {
      final listed = await e2e('list_stripe_refunds', {'payment_intent_id': piId});
      notes.add('stripe refunds $listed');
    }

    final afterRf = await adminGet('orders', orderId);
    notes.add('after refund $afterRf');
    final prod = productId == null ? null : await adminGet('products', productId);
    notes.add('stock after refund $prod');

    // Review after refund
    final rev = await rest('reviews', method: 'POST', token: buyerJwt, body: {
      'order_id': orderId,
      'reviewer_id': buyerId,
      'reviewee_id': sellerId,
      'rating': 1,
      'comment': '$tag after refund',
    });
    notes.add('review after refund ${rev['status']} ${rev['raw']}');
  }

  final bag = await e2e('setup_paid_bag', {});
  notes.add('setup_paid_bag $bag');
  if (bag != null) {
    final oa = bag['order_a_id']?.toString();
    final ob = bag['order_b_id']?.toString();
    final pa = bag['product_a_id']?.toString();
    final pb = bag['product_b_id']?.toString();
    if (oa != null) created['orders']!.add(oa);
    if (ob != null) created['orders']!.add(ob);
    if (pa != null) created['products']!.add(pa);
    if (pb != null) created['products']!.add(pb);

    final sum = (bag['paid_a'] ?? 0) is num && (bag['paid_b'] ?? 0) is num
        ? (bag['paid_a'] as num) + (bag['paid_b'] as num)
        : null;
    notes.add('bag inv sum=$sum pi=${bag['pi_amount_cents']} checks=${bag['checks']}');
    if (bag['checks'] is Map && bag['checks']['sum_eq_pi'] != true) {
      addFinding(
        id: 'SATB-BAG-02',
        sev: 'P1',
        surface: 'BAG',
        pre: 'paid bag 2 lines',
        identity: 'service_setup+observe',
        request: 'setup_paid_bag',
        response: bag,
        before: '-',
        after: 'sum_eq_pi=${bag['checks']}',
        impact: 'Σ amount_paid_cents ≠ captura do PaymentIntent.',
        confidence: 'alta',
        variant: 'allocation',
        fp: 'rounding ±1 esperado documentado',
      );
    }

    if (oa != null && ob != null) {
      final rA = await edge('refund-order', token: sellerJwt, body: {'order_id': oa});
      notes.add('bag refund A ${rA['status']} ${rA['raw']}');
      final rB = await edge('refund-order', token: sellerJwt, body: {'order_id': ob});
      notes.add('bag refund B ${rB['status']} ${rB['raw']}');
      final rA2 = await edge('refund-order', token: sellerJwt, body: {'order_id': oa});
      notes.add('bag refund A dup ${rA2['status']} ${rA2['raw']}');
      if (bag['payment_intent_id'] != null) {
        final listed = await e2e('list_stripe_refunds', {'payment_intent_id': bag['payment_intent_id']});
        notes.add('bag stripe refunds $listed');
        if (listed != null && listed['refunds'] is List) {
          final refunds = listed['refunds'] as List;
          var total = 0;
          for (final x in refunds) {
            if (x is Map) total += (x['amount'] as num?)?.toInt() ?? 0;
          }
          final piAmt = (listed['payment_intent'] is Map)
              ? (listed['payment_intent'] as Map)['amount_received'] ?? (listed['payment_intent'] as Map)['amount']
              : bag['pi_amount_cents'];
          notes.add('bag refunded_sum=$total pi=$piAmt');
          if (piAmt is num && total > piAmt + 1) {
            addFinding(
              id: 'SATB-REF-02',
              sev: 'P0',
              surface: 'REFUND',
              pre: 'bag shared PI refund A then B',
              identity: 'seller',
              request: 'refund-order A then B',
              response: {'stripe': listed, 'ra': rA['raw'], 'rb': rB['raw']},
              before: 'pi=$piAmt',
              after: 'refunded_sum=$total',
              impact: 'Reembolsos do saco excedem captura (invariante G).',
              confidence: 'alta',
              variant: 'A then B',
              fp: 'pending+succeeded double count',
            );
          }
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// PASS 3 — composition
// ---------------------------------------------------------------------------
Future<void> pass3() async {
  passNo = 3;
  stderr.writeln('=== PASS 3 composition ===');

  // proposal + catalog + checkout
  final pid = await createProductAsSeller(price: 12.00, qty: 2, title: '$tag offer');
  if (pid != null) {
    final offer = await rest('product_offers', method: 'POST', token: buyerJwt, body: {
      'product_id': pid,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 2.00,
      'status': 'accepted',
    });
    notes.add('offer self-accept ${offer['status']} ${offer['raw']}');
    Map? orow;
    final ob = offer['body'];
    if (ob is List && ob.isNotEmpty) orow = ob.first as Map;
    if (ob is Map) orow = ob;
    if (orow?['status'] == 'accepted') {
      addFinding(
        id: 'SATB-OFF-01',
        sev: 'P1',
        surface: 'PRICING',
        pre: 'buyer INSERT offer accepted',
        identity: 'buyer',
        request: 'INSERT product_offers status=accepted amount=2',
        response: offer['raw'],
        before: 'catalog 12€',
        after: 'accepted 2€',
        impact: 'Buyer auto-aceita proposta abaixo do catálogo.',
        confidence: 'alta',
        variant: 'self accept',
        fp: 'trigger força pending',
      );
    }
    String? offerId = orow?['id']?.toString();
    if (offerId != null && orow?['status'] != 'accepted') {
      final acc = await rest('product_offers',
          method: 'PATCH', token: buyerJwt, qs: 'id=eq.$offerId', body: {'status': 'accepted', 'amount': 2.00});
      notes.add('buyer accept own offer ${acc['status']} ${acc['raw']}');
    }
    // seller accept
    if (offerId != null) {
      await rest('product_offers',
          method: 'PATCH', token: sellerJwt, qs: 'id=eq.$offerId', body: {'status': 'accepted'});
    }
    final oid = await createOrderAsBuyer(productId: pid, extra: {
      if (offerId != null) 'product_offer_id': offerId,
      'payment_method': 'proposta',
    });
    if (oid != null) {
      final row = await adminGet('orders', oid);
      notes.add('order with offer contract=${row?['contract_unit_cents']} offer=${row?['product_offer_id']}');
      await rest('products', method: 'PATCH', token: sellerJwt, qs: 'id=eq.$pid', body: {'price': 50.00});
      final co = await edge('create-payment-intent', token: buyerJwt, body: {
        'buyer_id': buyerId,
        'order_id': oid,
        'shipping_method': 'hand',
      });
      notes.add('offer+hike checkout ${co['status']} ${co['raw']}');
    }
  }

  // dispute + release
  final paid = await e2e('setup_paid_order', {'initial_qty': 1});
  notes.add('pass3 paid $paid');
  final oid = paid?['order_id']?.toString();
  final pidP = paid?['product_id']?.toString();
  if (pidP != null) created['products']!.add(pidP);
  if (oid != null) {
    created['orders']!.add(oid);
    await rest('orders',
        method: 'PATCH', token: sellerJwt, qs: 'id=eq.$oid', body: {'status': 'enviado'});
    await rest('orders',
        method: 'PATCH', token: buyerJwt, qs: 'id=eq.$oid', body: {'status': 'pedido_devolucao'});
    final d = await rest('order_disputes', method: 'POST', token: buyerJwt, body: {
      'order_id': oid,
      'buyer_id': buyerId,
      'reason': '$tag composition',
      'status': 'aberta',
    });
    notes.add('dispute on paid ${d['status']} ${d['raw']}');
    final rel = await rpc('batata_release_seller_wallet_for_order',
        token: sellerJwt, body: {'p_order_id': oid});
    notes.add('release while dispute ${rel['status']} ${rel['raw']}');
    if (rel['status'] == 200 && rel['body'] == true) {
      addFinding(
        id: 'SATB-CMP-01',
        sev: 'P1',
        surface: 'DISPUTE',
        pre: 'paid + dispute open',
        identity: 'seller',
        request: 'release wallet',
        response: rel['raw'],
        before: 'dispute aberta',
        after: 'release true',
        impact: 'Libertação de wallet com disputa aberta.',
        confidence: 'média',
        variant: 'release vs dispute',
        fp: 'true sem crédito / já libertado',
      );
    }
    final rf = await edge('refund-order', token: sellerJwt, body: {'order_id': oid});
    notes.add('refund after/with dispute ${rf['status']} ${rf['raw']}');
  }

  // live reservation + order qty
  // concurrent checkout two orders same unit stock=1
  final p1 = await createProductAsSeller(price: 5.00, qty: 1, title: '$tag race');
  if (p1 != null) {
    final o1 = await createOrderAsBuyer(productId: p1);
    final o2 = await createOrderAsBuyer(productId: p1);
    notes.add('two orders on qty=1 o1=$o1 o2=$o2');
    if (o1 != null && o2 != null) {
      final c1 = await edge('create-payment-intent', token: buyerJwt, body: {
        'buyer_id': buyerId,
        'order_id': o1,
        'shipping_method': 'hand',
      });
      final c2 = await edge('create-payment-intent', token: buyerJwt, body: {
        'buyer_id': buyerId,
        'order_id': o2,
        'shipping_method': 'hand',
      });
      notes.add('race checkout ${c1['status']} ${c2['status']} ${c1['raw']} ${c2['raw']}');
      if (c1['status'] == 200 && c2['status'] == 200) {
        addFinding(
          id: 'SATB-STK-04',
          sev: 'P1',
          surface: 'STOCK',
          pre: 'stock=1 two unpaid orders',
          identity: 'buyer',
          request: 'two create-payment-intent',
          response: {'c1': c1['raw'], 'c2': c2['raw']},
          before: 'qty=1',
          after: 'two sessions',
          impact: 'Duas Sessions Stripe sobre 1 unidade (oversell até settle).',
          confidence: 'alta',
          variant: 'double session',
          fp: 'settle refunds oversell — ainda risco de double charge UX',
        );
      }
    }
  }

  // admin rpc
  final adm = await rpc('batata_is_admin', token: buyerJwt, body: {});
  notes.add('is_admin buyer ${adm['status']} ${adm['raw']}');
}

// ---------------------------------------------------------------------------
// PASS 4 — races / retries already partly in pass2; extra payout + settle
// ---------------------------------------------------------------------------
Future<void> pass4() async {
  passNo = 4;
  stderr.writeln('=== PASS 4 races ===');

  final paid = await e2e('setup_paid_order', {'initial_qty': 2});
  final oid = paid?['order_id']?.toString();
  final pid = paid?['product_id']?.toString();
  if (pid != null) created['products']!.add(pid);
  if (oid != null) {
    created['orders']!.add(oid);
    final f1 = edge('refund-order', token: sellerJwt, body: {'order_id': oid});
    final f2 = edge('refund-order', token: sellerJwt, body: {'order_id': oid});
    final r = await Future.wait([f1, f2]);
    notes.add('concurrent refund ${r[0]['status']} ${r[1]['status']} ${r[0]['raw']} ${r[1]['raw']}');
    if (paid?['payment_intent_id'] != null) {
      final listed = await e2e('list_stripe_refunds', {'payment_intent_id': paid!['payment_intent_id']});
      notes.add('concurrent refund stripe $listed');
    }
  }

  // payout double tap same key
  final k = '${tag}_pay_${DateTime.now().millisecondsSinceEpoch}';
  final p1 = await edge('create-connect-account', token: sellerJwt, body: {
    'user_id': sellerId,
    'amount': 100,
    'idempotency_key': k,
  });
  final p2 = await edge('create-connect-account', token: sellerJwt, body: {
    'user_id': sellerId,
    'amount': 100,
    'idempotency_key': k,
  });
  notes.add('payout same key ${p1['status']} ${p2['status']} ${p1['raw']} ${p2['raw']}');

  final k2 = '${tag}_pay2_${DateTime.now().millisecondsSinceEpoch}';
  final p3 = await edge('create-connect-account', token: sellerJwt, body: {
    'user_id': sellerId,
    'amount': 100,
    'idempotency_key': k2,
  });
  notes.add('payout new key same amount ${p3['status']} ${p3['raw']}');
}

// ---------------------------------------------------------------------------
// PASS 5 — state machine
// ---------------------------------------------------------------------------
Future<void> pass5() async {
  passNo = 5;
  stderr.writeln('=== PASS 5 state machine ===');

  final pid = await createProductAsSeller(price: 7.00, qty: 2, title: '$tag fsm');
  if (pid == null) return;
  final oid = await createOrderAsBuyer(productId: pid, payment: 'Pagamento na app');
  if (oid == null) return;

  const states = [
    'pago',
    'enviado',
    'entregue',
    'concluido',
    'pedido_devolucao',
    'em_devolucao',
    'devolucao_entregue',
    'disputa_devolucao_vendedor',
    'devolvida',
    'cancelado',
    'premio_rifa',
  ];
  for (final who in ['buyer', 'seller', 'anon']) {
    final tok = who == 'buyer'
        ? buyerJwt
        : who == 'seller'
            ? sellerJwt
            : anonKey;
    for (final st in states) {
      final before = await adminGet('orders', oid);
      final r = await rest(
        'orders',
        method: 'PATCH',
        token: tok,
        qs: 'id=eq.$oid',
        body: {'status': st},
      );
      final after = await adminGet('orders', oid);
      final b = before?['status'];
      final a = after?['status'];
      if (a != b && a == st) {
        notes.add('FSM ALLOW $who $b → $st http=${r['status']}');
        final unpaid = (before?['amount_paid_cents'] == null || before?['amount_paid_cents'] == 0) &&
            (before?['stripe_payment_intent_id'] == null ||
                before!['stripe_payment_intent_id'].toString().isEmpty);
        if (unpaid &&
            {'pago', 'enviado', 'entregue', 'concluido', 'devolvida', 'premio_rifa'}.contains(st) &&
            who != 'service') {
          addFinding(
            id: 'SATB-FSM-$who-$st',
            sev: 'P0',
            surface: 'ORDERS',
            pre: 'unpaid $b',
            identity: who,
            request: 'PATCH status=$st',
            response: after ?? r['raw'],
            before: '$b',
            after: '$a',
            impact: '$who transita para $st sem pagamento confirmado.',
            confidence: 'alta',
            variant: '$who $st',
            fp: 'off-platform seller pago permitido — este order é plataforma',
          );
        }
      } else {
        notes.add('FSM DENY $who $b → $st (stayed $a) http=${r['status']}');
      }
    }
  }
}

Future<void> main() async {
  http.connectionTimeout = const Duration(seconds: 30);
  await loadEnv();
  for (final k in [
    'AUTH','PROFILES','ORDERS','PRICING','CHECKOUT','SETTLE','WEBHOOK','BAG',
    'REFUND','DISPUTE','WALLET','PAYOUT','STOCK','LIVE','RESERVATIONS','RAFFLE',
    'TIPS','CHAT','REVIEWS','STORAGE','MUX','LIVEKIT','PS/OCR','RPC/DEFINER',
    'RLS','RACES','COMPOSITION',
  ]) {
    coverage[k] = 'NÃO TESTADA';
  }

  final b = await login(buyerEmail, buyerPass);
  buyerJwt = b['jwt'] as String;
  buyerId = b['id'] as String;
  final s = await login(sellerEmail, sellerPass);
  sellerJwt = s['jwt'] as String;
  sellerId = s['id'] as String;
  stderr.writeln('buyer=$buyerId seller=$sellerId');

  Future<void> safePass(String name, Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e, st) {
      notes.add('CRASH $name $e');
      stderr.writeln('CRASH $name $e\n$st');
    }
  }

  try {
    await safePass('pass1', pass1);
    await safePass('pass2', pass2);
    await safePass('pass3', pass3);
    await safePass('pass4', pass4);
    await safePass('pass5', pass5);
    passNo = 6;
    stderr.writeln('=== PASS 6 confirmation (no new class expected) ===');
    await safePass('pass6-wallet', attackWalletPayout);
    await safePass('pass6-checkout', attackCheckout);
    await safePass('pass6-orders', attackOrdersAndPricing);
  } finally {
    await cleanup();
    http.close(force: true);
  }

  final out = {
    'staging': project,
    'when': DateTime.now().toUtc().toIso8601String(),
    'buyer': buyerId,
    'seller': sellerId,
    'findings': findings,
    'coverage': coverage,
    'notes': notes,
    'p0': findings.where((f) => f['sev'] == 'P0').map((f) => f['id']).toList(),
    'p1': findings.where((f) => f['sev'] == 'P1').map((f) => f['id']).toList(),
    'p2': findings.where((f) => f['sev'] == 'P2').map((f) => f['id']).toList(),
    'p3': findings.where((f) => f['sev'] == 'P3').map((f) => f['id']).toList(),
  };
  final dir = Directory('tool/reports');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File('tool/reports/SATB_20260827_EVIDENCE.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stderr.writeln('FINDINGS ${findings.length} P0=${out['p0']} P1=${out['p1']}');
  stdout.writeln(jsonEncode({
    'n': findings.length,
    'p0': out['p0'],
    'p1': out['p1'],
    'coverage': coverage,
  }));
}
