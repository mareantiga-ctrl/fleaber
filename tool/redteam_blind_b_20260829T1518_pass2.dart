// ignore_for_file: avoid_print
/// Red Team Cego B — pass 2 (schema-correct + laterais + composição).
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stamp = '20260829T1518';
const tag = 'RTBB1518';

final findings = <Map<String, dynamic>>[];
final blocked = <Map<String, dynamic>>[];
final evidence = <String, dynamic>{};

void finding({
  required String id,
  required String severity,
  required String title,
  required String actor,
  dynamic result,
  String? impact,
  String? request,
  String? repro,
}) {
  findings.add({
    'id': id,
    'severity': severity,
    'title': title,
    'actor': actor,
    if (request != null) 'request': request,
    'result': result,
    if (impact != null) 'impact': impact,
    if (repro != null) 'reproduction': repro,
  });
}

void harden(String id, String title, dynamic result) {
  blocked.add({'id': id, 'title': title, 'result': result});
}

dynamic clip(dynamic v, [int max = 700]) {
  final s = v is String ? v : jsonEncode(v);
  if (s.length <= max) return v is String ? v : jsonDecode(jsonEncode(v));
  return '${s.substring(0, max)}…';
}

Map<String, dynamic> snap(http.Response r) =>
    {'status': r.statusCode, 'body': clip(r.body, 500)};

Future<http.Response> rest(
  LiveOpsStagingClient c, {
  required String method,
  required String path,
  String? token,
  Object? body,
  bool service = false,
}) {
  final headers = <String, String>{
    'apikey': service ? c.serviceRoleKey : c.anonKey,
    'Authorization':
        'Bearer ${service ? c.serviceRoleKey : (token ?? c.anonKey)}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final uri = Uri.parse('${c.url}$path');
  final enc = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      return http.get(uri, headers: headers);
    case 'POST':
      return http.post(uri, headers: headers, body: enc);
    case 'PATCH':
      return http.patch(uri, headers: headers, body: enc);
    case 'DELETE':
      return http.delete(uri, headers: headers);
    default:
      throw ArgumentError(method);
  }
}

Future<http.Response> edge(
  LiveOpsStagingClient c,
  String fn, {
  String? token,
  Object? body,
  String method = 'POST',
  String query = '',
}) {
  final headers = <String, String>{
    'apikey': c.anonKey,
    'Authorization': 'Bearer ${token ?? c.anonKey}',
    'Content-Type': 'application/json',
  };
  final uri = Uri.parse('${c.url}/functions/v1/$fn$query');
  if (method == 'GET') return http.get(uri, headers: headers);
  return http.post(
    uri,
    headers: headers,
    body: body == null ? null : jsonEncode(body),
  );
}

String? rowId(http.Response r) {
  if (r.statusCode >= 300) return null;
  try {
    final d = jsonDecode(r.body);
    final row = d is List ? d.first : d;
    return (row as Map)['id']?.toString();
  } catch (_) {
    return null;
  }
}

String? rowField(http.Response r, String k) {
  if (r.statusCode >= 300) return null;
  try {
    final d = jsonDecode(r.body);
    final row = d is List ? d.first : d;
    return (row as Map)[k]?.toString();
  } catch (_) {
    return null;
  }
}

int rowN(http.Response r) {
  if (r.statusCode >= 400) return -1;
  try {
    final d = jsonDecode(r.body);
    if (d is List) return d.length;
  } catch (_) {}
  return -2;
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final buyerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  await _lateralTables(c, buyerTok, buyerId);
  await _banking(c, buyerTok, sellerTok, buyerId, sellerId);
  await _stockDual(c, buyerTok, sellerTok, buyerId, sellerId);
  await _existingOrderMutations(c, buyerTok, sellerTok, buyerId, sellerId);
  await _reviewsRep(c, buyerTok, buyerId, sellerId);
  await _stripeReplay(c, buyerTok);
  await _storageProofs(c, sellerTok, buyerId);
  await _raffleAndLive(c, buyerTok, buyerId);
  await _closedEconomy(c, buyerId, sellerId);
  await _hubViews(c);
  await _paymentIntentRealOrder(c, buyerTok, buyerId, sellerId);
  await _tipPendingSettle(c, buyerTok, sellerId);

  final prevFile =
      File('tool/reports/redteam_blind_b_$stamp/REDTEAM_BLIND_B_$stamp.json');
  final prev = jsonDecode(prevFile.readAsStringSync()) as Map<String, dynamic>;
  final prevFindings = (prev['findings'] as List).cast<dynamic>();
  final merged = [...prevFindings, ...findings];
  final out = {
    ...prev,
    'pass2_at': DateTime.now().toUtc().toIso8601String(),
    'findings': merged,
    'pass2_blocked': blocked,
    'pass2_evidence': evidence,
    'counts': {
      'P0': merged.where((f) => (f as Map)['severity'] == 'P0').length,
      'P1': merged.where((f) => (f as Map)['severity'] == 'P1').length,
      'P2': merged.where((f) => (f as Map)['severity'] == 'P2').length,
      'P3': merged.where((f) => (f as Map)['severity'] == 'P3').length,
    },
  };
  prevFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  File('tool/reports/redteam_blind_b_$stamp/pass2.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'findings': findings,
      'blocked': blocked,
    }),
  );
  print('PASS2 new=${findings.length} blocked=${blocked.length}');
  for (final f in findings) {
    print('  [${f['severity']}] ${f['id']} ${f['title']}');
  }
}

Future<void> _lateralTables(
  LiveOpsStagingClient c,
  String buyerTok,
  String buyerId,
) async {
  const tables = [
    'batata_anon_rate_limits',
    'seller_device_tokens',
    'ps_ingest_audit',
    'ps_pairing_sessions',
    'live_vendor_studio_logs',
    'live_messages',
    'live_private_messages',
    'staff_action_logs',
    'live_raffle_entries',
    'reviews_gerais',
    'user_notifications',
    'app_logs',
    'profile_handle_claim_log',
  ];
  final map = <String, dynamic>{};
  for (final t in tables) {
    final anon = await rest(c, method: 'GET', path: '/rest/v1/$t?select=*&limit=5');
    final buyer = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/$t?select=*&limit=5',
      token: buyerTok,
    );
    map[t] = {
      'anon': {'status': anon.statusCode, 'n': rowN(anon), 'body': clip(anon.body, 160)},
      'buyer': {
        'status': buyer.statusCode,
        'n': rowN(buyer),
        'body': clip(buyer.body, 160),
      },
    };
    if (anon.statusCode == 200 && rowN(anon) > 0) {
      finding(
        id: 'RTB-B-PRIV-ANON-$t',
        severity: 'P1',
        title: 'anon SELECT $t devolve linhas',
        actor: 'anon',
        result: map[t]['anon'],
      );
    }
  }
  evidence['lateral'] = map;

  final ev = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/stripe_checkout_events?buyer_id=neq.$buyerId&select=id,buyer_id,order_id,session_id,event&limit=10',
    token: buyerTok,
  );
  evidence['stripe_events_foreign'] = snap(ev);
  if (ev.statusCode == 200 && rowN(ev) > 0) {
    finding(
      id: 'RTB-B-PRIV-11',
      severity: 'P1',
      title: 'Buyer lê stripe_checkout_events de outros buyers',
      actor: 'buyer JWT',
      result: snap(ev),
      impact: 'session_id / order_id de checkout de terceiros.',
    );
  } else {
    harden('PRIV-11', 'stripe events foreign', snap(ev));
  }

  final tips = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/live_tips?select=id,buyer_id,seller_id,amount,status,message&limit=30',
    token: buyerTok,
  );
  if (tips.statusCode == 200) {
    try {
      final list = jsonDecode(tips.body) as List;
      final foreign = list.where((e) {
        final m = e as Map;
        return m['buyer_id'] != buyerId && m['seller_id'] != buyerId;
      }).toList();
      if (foreign.isNotEmpty) {
        finding(
          id: 'RTB-B-PRIV-12',
          severity: 'P1',
          title: 'Buyer lê live_tips alheias',
          actor: 'buyer JWT',
          result: {'n': foreign.length, 'sample': clip(foreign.first)},
        );
      } else {
        harden('PRIV-12', 'tips own parties', {'n': list.length});
      }
    } catch (_) {}
  }
}

Future<String> _productId(
  LiveOpsStagingClient c,
  String sellerTok,
  String sellerId,
) async {
  final ex = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/products?seller_id=eq.$sellerId&title=like.$tag*&select=id&limit=1',
    service: true,
  );
  final id = rowId(ex);
  if (id != null) return id;
  final ins = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/products',
    token: sellerTok,
    body: {
      'seller_id': sellerId,
      'title': '$tag p2',
      'price': 8.2,
      'quantity': 1,
      'list_on_marketplace': true,
    },
  );
  return rowId(ins)!;
}

Future<void> _banking(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/profiles?id=eq.$sellerId',
    service: true,
    body: {
      'iban': 'PT50000201231234567890154',
      'mb_way': '910000000',
      'external_payments_enabled': true,
    },
  );
  final pid = await _productId(c, sellerTok, sellerId);
  final matrix = <String, dynamic>{};
  const statuses = [
    'reserva_pendente',
    'pendente',
    'reservado',
    'aguarda_confirmacao',
    'aguarda_pagamento',
    'pago',
  ];
  for (final st in statuses) {
    final ins = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/orders',
      token: buyerTok,
      body: {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pid,
        'quantity': 1,
        'price_total': 8.2,
        'status': st,
        'payment_method': 'MB WAY',
      },
    );
    final oid = rowId(ins);
    final persisted = rowField(ins, 'status');
    var leaked = false;
    Map<String, dynamic>? det;
    if (oid != null) {
      final rpc = await rest(
        c,
        method: 'POST',
        path: '/rest/v1/rpc/batata_seller_direct_payment_details',
        token: buyerTok,
        body: {'p_seller_id': sellerId},
      );
      det = snap(rpc);
      leaked = rpc.body.contains('PT50') || rpc.body.contains('910000000');
      await rest(
        c,
        method: 'DELETE',
        path: '/rest/v1/orders?id=eq.$oid',
        service: true,
      );
    }
    matrix[st] = {
      'insert': snap(ins),
      'persisted': persisted,
      'leaked': leaked,
      'details': det,
    };
    if (leaked) {
      final accepted =
          persisted == 'reservado' || persisted == 'aguarda_pagamento';
      finding(
        id: 'RTB-B-BANK-$st',
        severity: accepted ? 'P2' : 'P1',
        title:
            'Oráculo bancário INSERT status=$st persistiu=$persisted leaked=$leaked',
        actor: 'buyer JWT',
        request:
            'POST orders MB WAY status=$st → batata_seller_direct_payment_details',
        result: matrix[st],
        impact: accepted
            ? 'Revelação em estado de aceitação.'
            : 'IBAN/MB WAY sem aceitação do vendedor.',
        repro:
            'INSERT order MB WAY status $st; RPC batata_seller_direct_payment_details.',
      );
    }
  }
  evidence['banking_matrix'] = matrix;

  final base = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/orders',
    token: buyerTok,
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 8.2,
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
    },
  );
  evidence['bank_base_insert'] = snap(base);
  final oid = rowId(base);
  if (oid == null) return;
  for (final st in [
    'aguarda_confirmacao',
    'reservado',
    'aguarda_pagamento',
    'pago',
  ]) {
    await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$oid',
      token: buyerTok,
      body: {'status': st},
    );
    final read = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/orders?id=eq.$oid&select=id,status',
      token: buyerTok,
    );
    final rpc = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/rpc/batata_seller_direct_payment_details',
      token: buyerTok,
      body: {'p_seller_id': sellerId},
    );
    final leaked = rpc.body.contains('PT50') || rpc.body.contains('910000000');
    evidence['bank_patch_$st'] = {
      'read': clip(read.body),
      'leaked': leaked,
      'rpc': snap(rpc),
    };
    if (read.body.contains(st) &&
        leaked &&
        st != 'reservado' &&
        st != 'aguarda_pagamento') {
      finding(
        id: 'RTB-B-BANK-PATCH-$st',
        severity: 'P1',
        title: 'Buyer PATCH → $st revelou dados bancários',
        actor: 'buyer JWT',
        result: evidence['bank_patch_$st'],
      );
    }
  }
  await rest(
    c,
    method: 'DELETE',
    path: '/rest/v1/orders?id=eq.$oid',
    service: true,
  );
}

Future<void> _stockDual(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  final pid = await _productId(c, sellerTok, sellerId);
  await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/products?id=eq.$pid',
    service: true,
    body: {'quantity': 1, 'is_sold': false},
  );

  Future<String?> mk() async {
    final r = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/orders',
      token: buyerTok,
      body: {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pid,
        'quantity': 1,
        'price_total': 8.2,
        'status': 'reserva_pendente',
        'payment_method': 'MB WAY',
      },
    );
    evidence['last_order_insert'] ??= snap(r);
    return rowId(r);
  }

  final a = await mk();
  final b = await mk();
  if (a != null) {
    await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$a',
      token: sellerTok,
      body: {'status': 'reservado'},
    );
    await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$a',
      token: sellerTok,
      body: {'status': 'pago'},
    );
  }
  if (b != null) {
    await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$b',
      token: sellerTok,
      body: {'status': 'reservado'},
    );
    await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$b',
      token: sellerTok,
      body: {'status': 'pago'},
    );
  }
  Future<http.Response?> read(String? id) async {
    if (id == null) return null;
    return rest(
      c,
      method: 'GET',
      path:
          '/rest/v1/orders?id=eq.$id&select=id,status,stock_units_applied,amount_paid_cents',
      service: true,
    );
  }

  final oA = await read(a);
  final oB = await read(b);
  final prod = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/products?id=eq.$pid&select=id,quantity,is_sold',
    service: true,
  );
  evidence['dual_pago'] = {
    'a': oA == null ? null : clip(oA.body),
    'b': oB == null ? null : clip(oB.body),
    'product': clip(prod.body),
  };
  final aPago = (oA?.body ?? '').contains('"pago"');
  final bPago = (oB?.body ?? '').contains('"pago"');
  var qty = 1;
  try {
    final p = jsonDecode(prod.body);
    final row = p is List ? p.first : p;
    qty = int.tryParse('${(row as Map)['quantity']}') ?? 1;
  } catch (_) {}
  if (aPago && bPago) {
    finding(
      id: 'RTB-B-STOCK-DUAL',
      severity: qty < 0 ? 'P1' : 'P2',
      title:
          'Duas orders MB WAY → pago no mesmo produto qty=1 (qty_final=$qty)',
      actor: 'buyer+seller collusion',
      result: evidence['dual_pago'],
      impact:
          'Off-platform: sem captura Stripe. Unidade física pode ficar oversold se ambas pago.',
    );
  } else {
    harden('STOCK-DUAL', 'second pago blocked', evidence['dual_pago']);
  }

  await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/products?id=eq.$pid',
    service: true,
    body: {'quantity': 1, 'is_sold': false},
  );
  final ids = <String>[];
  final created = await Future.wait(List.generate(6, (_) => mk()));
  for (final id in created) {
    if (id != null) ids.add(id);
  }
  await Future.wait(ids.map(
    (id) => rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$id',
      token: sellerTok,
      body: {'status': 'reservado'},
    ),
  ));
  await Future.wait(ids.map(
    (id) => rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$id',
      token: sellerTok,
      body: {'status': 'pago'},
    ),
  ));
  var paid = 0;
  for (final id in ids) {
    final r = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/orders?id=eq.$id&select=status,stock_units_applied',
      service: true,
    );
    if (r.body.contains('"pago"')) paid++;
  }
  final prod2 = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/products?id=eq.$pid&select=quantity,is_sold',
    service: true,
  );
  evidence['race_pago'] = {
    'created': ids.length,
    'paid': paid,
    'product': clip(prod2.body),
  };
  if (paid >= 2) {
    finding(
      id: 'RTB-B-RACE-PAGO',
      severity: 'P2',
      title: 'Burst seller→pago: $paid pago em stock=1',
      actor: 'seller JWT race',
      result: evidence['race_pago'],
    );
  } else {
    harden('RACE-PAGO', 'burst pago', evidence['race_pago']);
  }

  for (final id in [a, b, ...ids]) {
    if (id == null) continue;
    await rest(
      c,
      method: 'DELETE',
      path: '/rest/v1/orders?id=eq.$id',
      service: true,
    );
  }
  await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/products?id=eq.$pid',
    service: true,
    body: {'quantity': 1, 'is_sold': false},
  );
}

Future<void> _existingOrderMutations(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  final mine = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/orders?buyer_id=eq.$buyerId&select=id,status,payment_method,quantity&limit=8',
    token: buyerTok,
  );
  evidence['buyer_orders'] = clip(mine.body, 800);
  if (mine.statusCode != 200) return;
  List list;
  try {
    list = jsonDecode(mine.body) as List;
  } catch (_) {
    return;
  }
  for (final raw in list.take(4)) {
    final m = raw as Map;
    final id = m['id'].toString();
    final st = m['status']?.toString() ?? '';
    await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$id',
      token: buyerTok,
      body: {'quantity': 77},
    );
    final qr = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/orders?id=eq.$id&select=id,quantity,status',
      token: buyerTok,
    );
    if (qr.body.contains('77')) {
      finding(
        id: 'RTB-B-QTY',
        severity: 'P1',
        title: 'Buyer PATCH quantity=77 em order $st',
        actor: 'buyer JWT',
        result: clip(qr.body),
      );
    }
    if (st != 'pago' && st != 'cancelado' && st != 'concluido') {
      await rest(
        c,
        method: 'PATCH',
        path: '/rest/v1/orders?id=eq.$id',
        token: buyerTok,
        body: {'status': 'pago'},
      );
      final pr = await rest(
        c,
        method: 'GET',
        path: '/rest/v1/orders?id=eq.$id&select=id,status',
        token: buyerTok,
      );
      if (pr.body.contains('"pago"') && st != 'pago') {
        finding(
          id: 'RTB-B-PAGO-SELF',
          severity: 'P0',
          title: 'Buyer forçou status pago a partir de $st',
          actor: 'buyer JWT',
          result: clip(pr.body),
        );
      }
    }
  }

  final vis = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/orders?seller_id=neq.$sellerId&select=id,seller_id,buyer_id,status&limit=5',
    token: sellerTok,
  );
  evidence['seller_sees_others'] = snap(vis);
  if (vis.statusCode == 200 && rowN(vis) > 0) {
    finding(
      id: 'RTB-B-PRIV-13',
      severity: 'P1',
      title: 'Seller SELECT orders de outros sellers',
      actor: 'seller JWT',
      result: snap(vis),
    );
  } else {
    harden('PRIV-13', 'seller orders scoped', snap(vis));
  }
}

Future<void> _reviewsRep(
  LiveOpsStagingClient c,
  String buyerTok,
  String buyerId,
  String sellerId,
) async {
  final mine = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/orders?buyer_id=eq.$buyerId&select=id,status&limit=8',
    token: buyerTok,
  );
  String? oid;
  String? st;
  try {
    for (final raw in jsonDecode(mine.body) as List) {
      final m = raw as Map;
      oid = m['id']?.toString();
      st = m['status']?.toString();
      if (oid != null) break;
    }
  } catch (_) {}
  final rev = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/reviews',
    token: buyerTok,
    body: {
      'buyer_id': buyerId,
      'target_id': sellerId,
      'stars': 5,
      'comment': '$tag review',
      'target_type': 'seller',
      'author_role': 'buyer',
      if (oid != null) 'order_id': oid,
    },
  );
  evidence['review_insert'] = {'order_status': st, ...snap(rev)};
  if (rev.statusCode < 300) {
    final verified = rev.body.contains('"purchase_verified":true');
    finding(
      id: 'RTB-B-REP-REV',
      severity: verified ? 'P1' : 'P2',
      title: 'INSERT review order=$st purchase_verified=$verified',
      actor: 'buyer JWT',
      result: snap(rev),
    );
    final id = rowId(rev);
    if (id != null) {
      await rest(
        c,
        method: 'DELETE',
        path: '/rest/v1/reviews?id=eq.$id',
        service: true,
      );
    }
  } else {
    harden('REP-REV', 'review insert', snap(rev));
  }
}

Future<void> _stripeReplay(
  LiveOpsStagingClient c,
  String buyerTok,
) async {
  final ev = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/stripe_checkout_events?select=session_id,event&limit=8',
    token: buyerTok,
  );
  String? session;
  try {
    for (final raw in jsonDecode(ev.body) as List) {
      final s = (raw as Map)['session_id']?.toString() ?? '';
      if (s.startsWith('cs_')) {
        session = s;
        break;
      }
    }
  } catch (_) {}
  if (session == null) {
    harden('EDGE-REPLAY', 'no session', snap(ev));
    return;
  }
  final settle = await edge(
    c,
    'create-payment-intent',
    token: c.anonKey,
    method: 'GET',
    query: '?checkout_return=success&session_id=${Uri.encodeComponent(session)}',
  );
  evidence['replay_settle'] = snap(settle);
  harden('EDGE-REPLAY', 'settle replay', snap(settle));
}

Future<void> _storageProofs(
  LiveOpsStagingClient c,
  String sellerTok,
  String buyerId,
) async {
  final list = await http.post(
    Uri.parse('${c.url}/storage/v1/object/list/fleaber_private'),
    headers: {
      'apikey': c.anonKey,
      'Authorization': 'Bearer $sellerTok',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'prefix': 'order_proofs/$buyerId', 'limit': 30}),
  );
  List names = [];
  try {
    names = jsonDecode(list.body) as List;
  } catch (_) {}
  final files = <String>[];
  for (final n in names.take(4)) {
    final name = (n as Map)['name']?.toString() ?? '';
    if (name.isEmpty) continue;
    final child = await http.post(
      Uri.parse('${c.url}/storage/v1/object/list/fleaber_private'),
      headers: {
        'apikey': c.anonKey,
        'Authorization': 'Bearer $sellerTok',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'prefix': 'order_proofs/$buyerId/$name',
        'limit': 20,
      }),
    );
    try {
      for (final f in jsonDecode(child.body) as List) {
        final fn = (f as Map)['name']?.toString() ?? '';
        if (fn.isNotEmpty) files.add('order_proofs/$buyerId/$name/$fn');
      }
    } catch (_) {}
  }
  evidence['proof_files_n'] = files.length;
  if (files.isEmpty) return;
  final path = files.first;
  final get = await http.get(
    Uri.parse(
      '${c.url}/storage/v1/object/fleaber_private/${Uri.encodeFull(path)}',
    ),
    headers: {
      'apikey': c.anonKey,
      'Authorization': 'Bearer $sellerTok',
    },
  );
  evidence['proof_get'] = {
    'path': path,
    'status': get.statusCode,
    'bytes': get.bodyBytes.length,
  };
  if (get.statusCode == 200 && get.bodyBytes.isNotEmpty) {
    finding(
      id: 'RTB-B-PRIV-PROOF-GET',
      severity: 'P2',
      title: 'Seller GET object de order_proofs do buyer',
      actor: 'seller JWT',
      result: evidence['proof_get'],
    );
  }
}

Future<void> _raffleAndLive(
  LiveOpsStagingClient c,
  String buyerTok,
  String buyerId,
) async {
  final tickets = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_award_live_raffle_tickets',
    token: buyerTok,
    body: {
      'p_raffle_id': '00000000-0000-0000-0000-000000000030',
      'p_user_id': buyerId,
      'p_reason': 'share',
      'p_tickets': 50,
      'p_source': 'x',
    },
  );
  evidence['award_tickets'] = snap(tickets);
  if (tickets.statusCode == 200) {
    finding(
      id: 'RTB-B-RAFFLE-01',
      severity: 'P1',
      title: 'JWT award raffle tickets',
      actor: 'buyer JWT',
      result: snap(tickets),
    );
  } else {
    harden('RAFFLE-01', 'award tickets', snap(tickets));
  }

  final prize = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_create_raffle_prize_order',
    token: buyerTok,
    body: {
      'p_raffle_id': '00000000-0000-0000-0000-000000000030',
      'p_winner_id': buyerId,
      'p_qty': 1,
    },
  );
  evidence['prize_order'] = snap(prize);
  if (prize.statusCode == 200) {
    finding(
      id: 'RTB-B-RAFFLE-02',
      severity: 'P1',
      title: 'JWT create raffle prize order',
      actor: 'buyer JWT',
      result: snap(prize),
    );
  } else {
    harden('RAFFLE-02', 'prize order', snap(prize));
  }

  final conv = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_live_reservation_stripe_convert',
    token: buyerTok,
    body: {
      'p_reservation_request_id': '00000000-0000-0000-0000-000000000031',
    },
  );
  evidence['stripe_convert'] = snap(conv);
  if (conv.statusCode == 200) {
    finding(
      id: 'RTB-B-CONV-01',
      severity: 'P1',
      title: 'JWT stripe_convert reserva',
      actor: 'buyer JWT',
      result: snap(conv),
    );
  } else {
    harden('CONV-01', 'stripe convert', snap(conv));
  }

  final msg = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/live_messages?select=*&limit=10',
    token: buyerTok,
  );
  evidence['live_messages'] = {'status': msg.statusCode, 'n': rowN(msg)};
}

Future<void> _closedEconomy(
  LiveOpsStagingClient c,
  String buyerId,
  String sellerId,
) async {
  final wB = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/wallets?id=eq.$buyerId&select=id,balance',
    service: true,
  );
  final wS = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/wallets?id=eq.$sellerId&select=id,balance',
    service: true,
  );
  evidence['economy'] = {
    'buyer_wallet': clip(wB.body),
    'seller_wallet': clip(wS.body),
  };
}

Future<void> _hubViews(LiveOpsStagingClient c) async {
  for (final v in [
    'hub_profiles_public',
    'hub_products_public',
    'hub_lives_public',
    'hub_reviews_public',
  ]) {
    final anon = await rest(c, method: 'GET', path: '/rest/v1/$v?select=*&limit=2');
    evidence['hub_$v'] = {
      'status': anon.statusCode,
      'n': rowN(anon),
      'body': clip(anon.body, 220),
    };
    if (anon.body.contains('iban') ||
        anon.body.contains('stream_key') ||
        anon.body.contains('mb_way')) {
      finding(
        id: 'RTB-B-HUB-$v',
        severity: 'P1',
        title: 'View $v expõe PII/credenciais',
        actor: 'anon',
        result: clip(anon.body, 400),
      );
    }
  }
}

Future<void> _paymentIntentRealOrder(
  LiveOpsStagingClient c,
  String buyerTok,
  String buyerId,
  String sellerId,
) async {
  final o = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/orders?buyer_id=eq.$buyerId&status=eq.reserva_pendente&select=id,product_id,seller_id,status,quantity,price_total&limit=1',
    token: buyerTok,
  );
  final oid = rowId(o);
  if (oid == null) {
    harden('PI-REAL', 'no pending order', snap(o));
    return;
  }
  final pi = await edge(
    c,
    'create-payment-intent',
    token: buyerTok,
    body: {
      'order_id': oid,
      'product_id': rowField(o, 'product_id'),
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'quantity': 99,
      'item_price': 0.01,
      'amount': 1,
      'shipping_method': 'hand',
    },
  );
  evidence['pi_real'] = snap(pi);
  if (pi.statusCode == 200 && pi.body.contains('checkoutUrl')) {
    finding(
      id: 'RTB-B-PI-MUT',
      severity: 'P1',
      title: 'Checkout criado com quantity/amount hostis no body',
      actor: 'buyer JWT',
      result: snap(pi),
    );
  } else {
    harden('PI-MUT', 'pi real order', snap(pi));
  }
}

Future<void> _tipPendingSettle(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerId,
) async {
  final pending = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_create_live_tip_pending',
    token: buyerTok,
    body: {
      'p_seller_id': sellerId,
      'p_amount': 2,
      'p_message': tag,
    },
  );
  evidence['tip_pending'] = snap(pending);
  if (pending.statusCode >= 300) {
    harden('TIP-PENDING', 'create pending', snap(pending));
    return;
  }
  String? tipId;
  try {
    tipId = jsonDecode(pending.body)?.toString();
  } catch (_) {}
  if (tipId == null || tipId.isEmpty) return;
  final settle = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_settle_live_tip_from_stripe',
    token: buyerTok,
    body: {
      'p_tip_id': tipId,
      'p_stripe_session_id': 'cs_test_fake',
      'p_paid_amount_cents': 200,
    },
  );
  evidence['tip_jwt_settle'] = snap(settle);
  if (settle.statusCode == 200 && settle.body.contains('true')) {
    finding(
      id: 'RTB-B-TIP-SETTLE',
      severity: 'P0',
      title: 'JWT settle tip Stripe sem pagamento',
      actor: 'buyer JWT',
      result: snap(settle),
    );
  } else {
    harden('TIP-SETTLE', 'jwt settle', snap(settle));
  }
}
