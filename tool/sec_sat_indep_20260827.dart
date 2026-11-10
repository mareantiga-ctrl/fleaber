// ignore_for_file: avoid_print
/// Auditoria cega independente — saturação 2026-08-27
/// dart run tool/sec_sat_indep_20260827.dart
/// STAGING only. Não aplica SQL, não altera Flutter, não toca produção.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'live_ops_staging_client.dart';

typedef Json = Map<String, dynamic>;

Future<Json> req(
  String method,
  String url,
  Map<String, String> h, [
  Object? body,
]) async {
  late http.Response r;
  try {
    switch (method) {
      case 'POST':
        r = await http.post(Uri.parse(url), headers: h, body: body == null ? null : jsonEncode(body));
        break;
      case 'PATCH':
        r = await http.patch(Uri.parse(url), headers: h, body: jsonEncode(body));
        break;
      case 'PUT':
        r = await http.put(Uri.parse(url), headers: h, body: body is List<int> ? body : jsonEncode(body));
        break;
      case 'DELETE':
        r = await http.delete(Uri.parse(url), headers: h);
        break;
      default:
        r = await http.get(Uri.parse(url), headers: h);
    }
  } catch (e) {
    return {'http': 0, 'body': '$e', 'error': true};
  }
  dynamic p;
  try {
    p = jsonDecode(r.body);
  } catch (_) {
    p = r.body.length > 4000 ? r.body.substring(0, 4000) : r.body;
  }
  return {'http': r.statusCode, 'body': p};
}

Json? row(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Json.from(body.first as Map);
  }
  if (body is Map) return Json.from(body);
  return null;
}

num n(Object? v) => v is num ? v : num.tryParse('$v') ?? -1;

bool leaked(Json r) => r['http'] == 200 || r['http'] == 201;
bool denied(Json r) {
  final c = r['http'] as int;
  return c == 401 || c == 403 || c == 404 || c == 409 || c == 425 || c >= 400;
}

String snippet(dynamic body, [int max = 500]) {
  final s = body is String ? body : jsonEncode(body);
  return s.length <= max ? s : s.substring(0, max);
}

void main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: não é staging fxdknzrqjenzqcvnwqqq');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final stripeKey = (e['STRIPE_SECRET_KEY'] ?? '').trim();
  if (stripeKey.isNotEmpty && !stripeKey.startsWith('sk_test_')) {
    stderr.writeln('ABORT: Stripe não é TEST');
    exit(2);
  }

  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  final BH = {
    'apikey': anon,
    'Authorization': 'Bearer $buyerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SH = {
    'apikey': anon,
    'Authorization': 'Bearer $sellerTok',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final AN = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final SVC = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final productIds = <String>[];
  final orderIds = <String>[];
  final findings = <Json>[];
  final notes = <String>[];
  final probes = <Json>[];
  final coverage = <String, String>{};
  final passNewClasses = <int, Set<String>>{};
  var pass = 1;

  void mark(String k, String v) {
    final prev = coverage[k];
    const rank = {
      'NÃO TESTADA': 0,
      'PARCIAL': 1,
      'TESTADA': 2,
      'TESTADA COM VARIANTES': 3,
    };
    if (prev == null || (rank[v] ?? 0) > (rank[prev] ?? 0)) {
      coverage[k] = v;
    }
  }

  void probe(String id, String surface, String identity, Json resp, {String? note}) {
    probes.add({
      'id': id,
      'surface': surface,
      'identity': identity,
      'http': resp['http'],
      'body': snippet(resp['body'], 800),
      if (note != null) 'note': note,
    });
    stdout.writeln('PROBE $id [$identity] http=${resp['http']} ${note ?? ''}');
  }

  void finding({
    required String id,
    required String sev,
    required String surface,
    required String identity,
    required String impact,
    required String request,
    required dynamic response,
    required String confidence,
    String variant = '-',
    String pre = '-',
    String post = '-',
    String fp = 'considerado: UI não é trust boundary; 200 vazio ≠ vuln',
    String precond = 'staging JWT/anon',
  }) {
    findings.add({
      'id': id,
      'sev': sev,
      'surface': surface,
      'identity': identity,
      'precondicoes': precond,
      'request': request,
      'resposta': snippet(response, 1200),
      'estado_antes': pre,
      'estado_depois': post,
      'impacto': impact,
      'confianca': confidence,
      'variante': variant,
      'falso_positivo_considerado': fp,
      'pass': pass,
    });
    passNewClasses.putIfAbsent(pass, () => {}).add('$sev:$surface');
    stdout.writeln('FINDING $sev $id — $impact');
  }

  Future<Json> mkProduct({required num price, int qty = 8, String? title}) async {
    final p = await sb.insert('products', {
      'seller_id': sellerId,
      'title': title ?? 'SATI $stamp $price',
      'price': price,
      'quantity': qty,
      'list_on_marketplace': false,
      'available_for_live': false,
      'is_sold': false,
      'image_urls': <String>[],
    });
    productIds.add('${p['id']}');
    return p;
  }

  Future<Json?> buyerOrder(Json fields) async {
    final r = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
      'quantity': 1,
      ...fields,
    });
    final o = row(r['body']);
    if (o != null && o['id'] != null) orderIds.add('${o['id']}');
    return o == null ? {'__http': r['http'], '__body': r['body']} : o;
  }

  Future<void> cleanup() async {
    for (final oid in orderIds) {
      await req('DELETE', '$url/rest/v1/order_disputes?order_id=eq.$oid', SVC);
      await req('DELETE', '$url/rest/v1/reviews?order_id=eq.$oid', SVC);
      await req('DELETE', '$url/rest/v1/orders?id=eq.$oid', SVC);
    }
    for (final pid in productIds) {
      await req('DELETE', '$url/rest/v1/orders?product_id=eq.$pid', SVC);
      await req('DELETE', '$url/rest/v1/product_offers?product_id=eq.$pid', SVC);
      await req('DELETE', '$url/rest/v1/reviews?product_id=eq.$pid', SVC);
      await req('DELETE', '$url/rest/v1/products?id=eq.$pid', SVC);
    }
  }

  // =====================================================================
  // PASSAGEM 1 — cobertura
  // =====================================================================
  stdout.writeln('\n======== PASSAGEM 1 ========');

  // --- OpenAPI inventory ---
  mark('RPC/DEFINER', 'TESTADA');
  mark('RLS', 'TESTADA');
  final oa = await http.get(
    Uri.parse('$url/rest/v1/'),
    headers: {'apikey': anon, 'Authorization': 'Bearer $anon', 'Accept': 'application/openapi+json'},
  );
  Json openapi = {};
  try {
    openapi = Json.from(jsonDecode(oa.body) as Map);
  } catch (_) {}
  final paths = (openapi['paths'] as Map?)?.keys.map((k) => '$k').toList() ?? [];
  final tables = paths.where((p) => !p.contains('/rpc/') && p != '/').map((p) => p.replaceFirst('/', '')).toList();
  final rpcs = paths.where((p) => p.contains('/rpc/')).map((p) => p.split('/').last).toList()..sort();
  notes.add('openapi_tables=${tables.length} rpcs=${rpcs.length} http=${oa.statusCode}');

  final sensitiveRpc = [
    'batata_credit_wallet_once',
    'batata_debit_wallet_once',
    'batata_clawback_seller_wallet_for_order',
    'batata_ensure_wallet',
    'ensure_wallet',
    'credit_wallet_once',
    'debit_wallet_once',
    'batata_release_seller_wallet_for_order',
    'batata_refund_buyer_wallet_for_order',
    'batata_wallet_payout_debit',
    'batata_wallet_payout_finish',
    'batata_process_partial_refund_dispute',
    'batata_finalize_stripe_order_refund',
    'batata_wallet_apply_tip_once',
    'batata_settle_live_tip_from_stripe',
    'batata_create_live_tip_pending',
    'batata_assert_wallet_rpc_grants',
    'batata_generate_auto_feedback',
    'batata_lab_clear_all_fm_pending',
    'batata_lab_clear_fm_pending',
    'staging_nuke_user_data',
    'staging_restore_stock_before_nuke',
    'batata_ingest_ocr_reservation_v2',
    'batata_ps_claim_pairing',
    'batata_mark_raffle_winner',
    'batata_award_raffle_ticket',
    'batata_draw_live_raffle',
  ];

  // --- AUTH ---
  mark('AUTH', 'TESTADA COM VARIANTES');
  final signupEnum = await req('POST', '$url/auth/v1/signup', {
    'apikey': anon,
    'Content-Type': 'application/json',
  }, {
    'email': envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    'password': 'WrongPass_sat_$stamp',
  });
  probe('AUTH_SIGNUP_EXISTING', 'AUTH', 'anon', signupEnum);
  // 200 with user vs 422 vs identical messages
  final recoverBuyer = await req('POST', '$url/auth/v1/recover', {
    'apikey': anon,
    'Content-Type': 'application/json',
  }, {'email': envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL')});
  final recoverGhost = await req('POST', '$url/auth/v1/recover', {
    'apikey': anon,
    'Content-Type': 'application/json',
  }, {'email': 'ghost-sati-$stamp@example.invalid'});
  probe('AUTH_RECOVER_EXISTING', 'AUTH', 'anon', recoverBuyer);
  probe('AUTH_RECOVER_GHOST', 'AUTH', 'anon', recoverGhost);
  if (recoverBuyer['http'] != recoverGhost['http'] ||
      jsonEncode(recoverBuyer['body']) != jsonEncode(recoverGhost['body'])) {
    finding(
      id: 'SATI-AUTH-01',
      sev: 'P3',
      surface: 'AUTH',
      identity: 'anon',
      impact: 'Recuperação de password distingue email existente vs inexistente (enumeração).',
      request: 'POST /auth/v1/recover existing vs ghost',
      response: {'existing': recoverBuyer['http'], 'ghost': recoverGhost['http']},
      confidence: 'alta',
      variant: 'recover',
      fp: 'GoTrue default; impacto enumeração contas, não takeover',
    );
  }

  final jwtUser = await req('GET', '$url/auth/v1/user', BH);
  probe('AUTH_JWT_USER', 'AUTH', 'buyer', jwtUser);
  final claims = row(jwtUser['body']);
  if (claims != null && (claims['role'] == 'service_role' || claims['is_admin'] == true)) {
    finding(
      id: 'SATI-AUTH-02',
      sev: 'P0',
      surface: 'AUTH',
      identity: 'buyer',
      impact: 'JWT de buyer contém claims privilegiados.',
      request: 'GET /auth/v1/user',
      response: claims,
      confidence: 'alta',
    );
  }

  // --- PROFILES / PII ---
  mark('PROFILES', 'TESTADA COM VARIANTES');
  final ownStar = await req('GET', '$url/rest/v1/profiles?id=eq.$buyerId&select=*', BH);
  probe('PROF_OWN_STAR', 'PROFILES', 'buyer', ownStar);
  final ownRow = row(ownStar['body']);
  if (ownRow != null) {
    for (final col in ['iban', 'mb_way', 'mbway', 'iban_encrypted', 'stripe_account_id']) {
      if (ownRow.containsKey(col) && ownRow[col] != null && '${ownRow[col]}'.isNotEmpty) {
        notes.add('own_profile_has_col=$col (própria linha; PII own-row)');
      }
    }
  }
  final otherStar = await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$sellerId&select=id,display_name,full_name,iban,mb_way,phone,email,user_type,phone_verified_at,stripe_account_id',
    BH,
  );
  probe('PROF_OTHER_PII', 'PROFILES', 'buyer', otherStar);
  final other = row(otherStar['body']);
  if (other != null) {
    final piiHits = <String>[];
    for (final col in ['iban', 'mb_way', 'phone', 'email', 'stripe_account_id']) {
      final v = other[col];
      if (v != null && '$v'.trim().isNotEmpty) piiHits.add('$col=$v');
    }
    if (piiHits.isNotEmpty) {
      finding(
        id: 'SATI-PROF-01',
        sev: 'P1',
        surface: 'PROFILES',
        identity: 'buyer JWT',
        impact: 'Comprador lê PII privilegiada do vendedor: $piiHits',
        request: 'GET profiles?id=eq.seller select iban,mb_way,phone',
        response: other,
        confidence: 'alta',
        variant: 'cross-row PII',
      );
    }
  }
  final anonDir = await req('GET', '$url/rest/v1/profiles?select=id,iban,mb_way,phone&limit=5', AN);
  probe('PROF_ANON_DIR', 'PROFILES', 'anon', anonDir);
  if (anonDir['http'] == 200 && anonDir['body'] is List && (anonDir['body'] as List).isNotEmpty) {
    final sample = row(anonDir['body']);
    final pii = ['iban', 'mb_way', 'phone'].where((c) => sample?[c] != null && '${sample?[c]}'.isNotEmpty);
    if (pii.isNotEmpty) {
      finding(
        id: 'SATI-PROF-02',
        sev: 'P1',
        surface: 'PROFILES',
        identity: 'anon',
        impact: 'Directório anónimo expõe PII: ${pii.toList()}',
        request: 'GET profiles select iban,mb_way,phone',
        response: sample,
        confidence: 'alta',
      );
    }
  }

  final buyerProf0 = row((await req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type,phone_verified_at,iban,display_name',
    SVC,
  ))['body']);
  for (final patch in [
    {'user_type': 'admin'},
    {'user_type': 'vendedor'},
    {'user_type': 'admim'},
    {'phone_verified_at': DateTime.now().toUtc().toIso8601String()},
    {'is_admin': true},
    {'iban': 'PT50000000000000000000000'},
  ]) {
    final before = await req('GET', '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type,phone_verified_at,iban', BH);
    final r = await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', BH, patch);
    probe('PROF_PATCH_${patch.keys.first}', 'PROFILES', 'buyer', r);
    final after = await req('GET', '$url/rest/v1/profiles?id=eq.$buyerId&select=user_type,phone_verified_at,iban', SVC);
    final a = row(after['body']);
    final b = row(before['body']);
    if (patch.containsKey('user_type') && a != null && a['user_type'] == patch['user_type'] && b?['user_type'] != patch['user_type']) {
      finding(
        id: 'SATI-PROF-03',
        sev: 'P0',
        surface: 'PROFILES',
        identity: 'buyer JWT',
        impact: 'Buyer elevou user_type para ${patch['user_type']} (Mux/admin).',
        request: 'PATCH profiles user_type',
        response: {'http': r['http'], 'after': a},
        confidence: 'alta',
        pre: '${b?['user_type']}',
        post: '${a['user_type']}',
      );
    }
    if (patch.containsKey('phone_verified_at') && a != null && a['phone_verified_at'] != b?['phone_verified_at'] && a['phone_verified_at'] != null) {
      finding(
        id: 'SATI-PROF-04',
        sev: 'P2',
        surface: 'PROFILES',
        identity: 'buyer JWT',
        impact: 'Buyer forjou phone_verified_at.',
        request: 'PATCH profiles phone_verified_at',
        response: {'http': r['http'], 'after': a},
        confidence: 'alta',
        pre: '${b?['phone_verified_at']}',
        post: '${a['phone_verified_at']}',
      );
    }
  }
  if (buyerProf0 != null) {
    await req('PATCH', '$url/rest/v1/profiles?id=eq.$buyerId', SVC, {
      'user_type': buyerProf0['user_type'],
      'phone_verified_at': buyerProf0['phone_verified_at'],
      if (buyerProf0.containsKey('iban')) 'iban': buyerProf0['iban'],
    });
  }
  final beforeDn = row((await req('GET', '$url/rest/v1/profiles?id=eq.$sellerId&select=display_name', SVC))['body']);
  final xPatch = await req('PATCH', '$url/rest/v1/profiles?id=eq.$sellerId', BH, {'display_name': 'hacked-$stamp'});
  probe('PROF_CROSS_UPDATE', 'PROFILES', 'buyer', xPatch);
  if (xPatch['http'] == 200 || xPatch['http'] == 204) {
    final chk = await req('GET', '$url/rest/v1/profiles?id=eq.$sellerId&select=display_name', SVC);
    final dn = row(chk['body'])?['display_name'];
    if ('$dn'.contains('hacked-$stamp')) {
      finding(
        id: 'SATI-PROF-05',
        sev: 'P1',
        surface: 'PROFILES',
        identity: 'buyer JWT',
        impact: 'Buyer alterou perfil do vendedor.',
        request: 'PATCH profiles?id=eq.seller',
        response: xPatch,
        confidence: 'alta',
        post: '$dn',
      );
      await req('PATCH', '$url/rest/v1/profiles?id=eq.$sellerId', SVC, {
        'display_name': beforeDn?['display_name'],
      });
    }
  }

  // --- TABLES RLS sweep ---
  mark('RLS', 'TESTADA COM VARIANTES');
  final extraTables = [
    'orders', 'products', 'profiles', 'chats', 'chat_messages', 'reviews',
    'order_disputes', 'wallets', 'wallet_ledger', 'wallet_transactions',
    'payouts', 'payout_intents', 'wallet_payouts', 'live_tips', 'lives',
    'live_items', 'live_reservation_requests', 'live_raffles', 'live_raffle_winners',
    'live_raffle_tickets', 'product_offers', 'product_bundles', 'bundle_items',
    'stripe_checkout_events', 'ps_pairing_codes', 'ps_devices', 'ps_ingest_audit',
    'staff_permissions', 'admin_users',
  ];
  final allTables = {...tables, ...extraTables}.toList()..sort();
  for (final t in allTables) {
    if (t.isEmpty || t.contains('{')) continue;
    for (final ident in [
      ['anon', AN],
      ['buyer', BH],
      ['seller', SH],
    ]) {
      final r = await req('GET', '$url/rest/v1/$t?select=*&limit=3', ident[1] as Map<String, String>);
      probe('RLS_SEL_${t}_${ident[0]}', 'RLS', ident[0] as String, r);
    }
  }

  // stream keys
  mark('MUX', 'TESTADA COM VARIANTES');
  mark('LIVEKIT', 'TESTADA');
  for (final col in ['mux_stream_key', 'stream_key', 'mux_live_id', 'livekit_egress_id']) {
    for (final ident in [
      ['anon', AN],
      ['buyer', BH],
      ['seller', SH],
    ]) {
      final r = await req('GET', '$url/rest/v1/lives?select=id,$col&limit=3', ident[1] as Map<String, String>);
      probe('LIVE_COL_${col}_${ident[0]}', 'MUX', ident[0] as String, r);
      if (r['http'] == 200 && r['body'] is List) {
        for (final item in r['body'] as List) {
          if (item is Map && item[col] != null && '${item[col]}'.trim().isNotEmpty) {
            finding(
              id: 'SATI-MUX-01',
              sev: col.contains('stream') ? 'P0' : 'P2',
              surface: 'MUX',
              identity: ident[0] as String,
              impact: 'Coluna $col legível via PostgREST.',
              request: 'GET lives?select=id,$col',
              response: item,
              confidence: 'alta',
              variant: col,
            );
            break;
          }
        }
      }
    }
  }

  // wallets table
  mark('WALLET', 'TESTADA COM VARIANTES');
  for (final t in ['wallets', 'wallet_ledger', 'wallet_transactions', 'payouts', 'payout_intents', 'wallet_payouts']) {
    final ins = await req('POST', '$url/rest/v1/$t', BH, {
      'user_id': buyerId,
      'owner_id': buyerId,
      'balance': 9999,
      'available': 9999,
      'amount': 9999,
    });
    probe('WALLET_INS_${t}_buyer', 'WALLET', 'buyer', ins);
    if (ins['http'] == 201) {
      finding(
        id: 'SATI-WALLET-01',
        sev: 'P0',
        surface: 'WALLET',
        identity: 'buyer JWT',
        impact: 'INSERT directo em $t criou fundos/ledger.',
        request: 'POST /$t balance=9999',
        response: ins,
        confidence: 'alta',
        variant: t,
      );
    }
    final upd = await req(
      'PATCH',
      '$url/rest/v1/$t?id=eq.00000000-0000-0000-0000-000000000099',
      BH,
      {'balance': 9999, 'available': 9999, 'amount': 1},
    );
    probe('WALLET_UPD_${t}_buyer', 'WALLET', 'buyer', upd);
  }

  // --- RPC GRANT sweep ---
  for (final name in [...sensitiveRpc, ...rpcs.where((r) => r.startsWith('batata_') || r.contains('wallet') || r.contains('payout') || r.contains('refund') || r.contains('raffle'))]) {
    for (final ident in [
      ['anon', AN],
      ['buyer', BH],
      ['seller', SH],
    ]) {
      final args = _rpcGuessArgs(name, buyerId, sellerId);
      final r = await req('POST', '$url/rest/v1/rpc/$name', ident[1] as Map<String, String>, args);
      probe('RPC_${name}_${ident[0]}', 'RPC/DEFINER', ident[0] as String, r);
      final httpCode = r['http'] as int;
      final bodyStr = snippet(r['body']).toLowerCase();
      final execOk = httpCode == 200 || httpCode == 201;
      final money = name.contains('wallet') || name.contains('credit') || name.contains('debit') || name.contains('payout') || name.contains('refund') || name.contains('clawback') || name.contains('nuke') || name.contains('lab_');
      if (execOk && money && ident[0] != 'service') {
        // 200 with error json still counts as execute
        if (!bodyStr.contains('permission denied') && !bodyStr.contains('42501')) {
          finding(
            id: 'SATI-RPC-01',
            sev: name.contains('credit') || name.contains('nuke') || name.contains('payout') || name.contains('clawback') ? 'P0' : 'P1',
            surface: 'RPC/DEFINER',
            identity: ident[0] as String,
            impact: 'RPC monetária $name executável por ${ident[0]} (http $httpCode).',
            request: 'POST /rpc/$name $args',
            response: r,
            confidence: 'média',
            variant: name,
            fp: '200 com erro de negócio interno ainda é EXECUTE; P0 só se efeito financeiro. Verificar estado.',
          );
        }
      }
    }
  }

  // --- ORDERS + PRICING ---
  mark('ORDERS', 'TESTADA COM VARIANTES');
  mark('PRICING', 'TESTADA COM VARIANTES');
  mark('STOCK', 'TESTADA COM VARIANTES');
  final p40 = await mkProduct(price: 40, qty: 5, title: 'SATI-P40');
  final p1 = await mkProduct(price: 12, qty: 1, title: 'SATI-Q1');
  final pBagA = await mkProduct(price: 10, qty: 4, title: 'SATI-BAGA');
  final pBagB = await mkProduct(price: 7, qty: 4, title: 'SATI-BAGB');
  final pHike = await mkProduct(price: 15, qty: 3, title: 'SATI-HIKE');

  // contract override
  final c1 = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': p40['id'],
    'quantity': 1,
    'price_total': 0.5,
    'contract_unit_cents': 50,
    'contract_qty': 9,
    'amount_paid_cents': 50,
    'status': 'pago',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
    'stripe_payment_intent_id': 'pi_fake_$stamp',
  });
  probe('ORD_CONTRACT_OVERRIDE', 'PRICING', 'buyer', c1);
  final c1r = row(c1['body']);
  if (c1r != null) {
    orderIds.add('${c1r['id']}');
    if (n(c1r['contract_unit_cents']) == 50 || n(c1r['price_total']) == 0.5) {
      finding(
        id: 'SATI-PRICE-01',
        sev: 'P0',
        surface: 'PRICING',
        identity: 'buyer JWT',
        impact: 'JWT selou contrato a 50 cêntimos / 0.50€ em produto de 40€.',
        request: 'POST orders contract_unit_cents=50 price_total=0.5',
        response: c1r,
        confidence: 'alta',
        post: 'cuc=${c1r['contract_unit_cents']} pt=${c1r['price_total']} st=${c1r['status']}',
      );
    }
    if (c1r['status'] == 'pago' || n(c1r['amount_paid_cents']) > 0 || c1r['stripe_payment_intent_id'] != null) {
      finding(
        id: 'SATI-ORD-01',
        sev: 'P0',
        surface: 'ORDERS',
        identity: 'buyer JWT',
        impact: 'INSERT JWT fabricou pago/Stripe/amount_paid.',
        request: 'POST orders status=pago amount_paid_cents=50 pi=fake',
        response: c1r,
        confidence: 'alta',
      );
    }
    if (n(c1r['contract_qty']) == 9 && n(c1r['quantity']) == 9) {
      finding(
        id: 'SATI-PRICE-02',
        sev: 'P1',
        surface: 'PRICING',
        identity: 'buyer JWT',
        impact: 'contract_qty JWT 9 sobrepôs quantity 1.',
        request: 'POST orders quantity=1 contract_qty=9',
        response: c1r,
        confidence: 'alta',
      );
    }
  }

  // spoof buyer_id
  final spoofBuyer = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': sellerId,
    'seller_id': sellerId,
    'product_id': p40['id'],
    'quantity': 1,
    'price_total': 40,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  probe('ORD_SPOOF_BUYER', 'ORDERS', 'buyer', spoofBuyer);
  final sbuy = row(spoofBuyer['body']);
  if (sbuy != null) {
    orderIds.add('${sbuy['id']}');
    if (sbuy['buyer_id'] == sellerId) {
      finding(
        id: 'SATI-ORD-02',
        sev: 'P1',
        surface: 'ORDERS',
        identity: 'buyer JWT',
        impact: 'Buyer criou order com buyer_id = vendedor (H: ownership).',
        request: 'POST orders buyer_id=seller',
        response: sbuy,
        confidence: 'alta',
      );
    }
  }

  // seller/product mismatch
  final pOther = await mkProduct(price: 9, qty: 2);
  final mismatch = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': buyerId,
    'product_id': pOther['id'],
    'quantity': 1,
    'price_total': 9,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  probe('ORD_SELLER_MISMATCH', 'ORDERS', 'buyer', mismatch);
  final mm = row(mismatch['body']);
  if (mm != null) {
    orderIds.add('${mm['id']}');
    if (mm['seller_id'] == buyerId && mm['product_id'] == pOther['id']) {
      finding(
        id: 'SATI-ORD-03',
        sev: 'P1',
        surface: 'ORDERS',
        identity: 'buyer JWT',
        impact: 'Order com seller_id ≠ product.seller_id (stock/payout cross-account).',
        request: 'POST orders seller_id=buyer product=seller',
        response: mm,
        confidence: 'alta',
      );
    }
  }

  // qty extremes
  for (final q in [0, -1, 100, 999]) {
    final r = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': p40['id'],
      'quantity': q,
      'price_total': 40,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    probe('ORD_QTY_$q', 'PRICING', 'buyer', r);
    final o = row(r['body']);
    if (o != null) {
      orderIds.add('${o['id']}');
      if (q <= 0 && n(o['quantity']) <= 0) {
        finding(
          id: 'SATI-PRICE-03',
          sev: 'P1',
          surface: 'PRICING',
          identity: 'buyer JWT',
          impact: 'Order com quantity=$q aceite.',
          request: 'POST orders quantity=$q',
          response: o,
          confidence: 'alta',
          variant: '$q',
        );
      }
      if (q > 99 && n(o['quantity']) == q) {
        finding(
          id: 'SATI-PRICE-04',
          sev: 'P2',
          surface: 'PRICING',
          identity: 'buyer JWT',
          impact: 'Quantity $q acima do teto 99 aceite.',
          request: 'POST orders quantity=$q',
          response: o,
          confidence: 'alta',
        );
      }
    }
  }

  // cross-user order select/update
  final victim = await buyerOrder({'product_id': p40['id'], 'price_total': 40, 'quantity': 1});
  if (victim?['id'] != null) {
    final asAnon = await req('GET', '$url/rest/v1/orders?id=eq.${victim!['id']}&select=*', AN);
    probe('ORD_ANON_SEL', 'ORDERS', 'anon', asAnon);
    if (asAnon['http'] == 200 && asAnon['body'] is List && (asAnon['body'] as List).isNotEmpty) {
      finding(
        id: 'SATI-ORD-04',
        sev: 'P2',
        surface: 'ORDERS',
        identity: 'anon',
        impact: 'Anon lê order alheia.',
        request: 'GET orders?id=eq.victim',
        response: asAnon,
        confidence: 'alta',
      );
    }
    for (final patch in [
      {'status': 'pago'},
      {'status': 'concluido'},
      {'status': 'entregue'},
      {'price_total': 1},
      {'quantity': 9},
      {'seller_id': buyerId},
      {'amount_paid_cents': 1},
      {'payment_method': 'MB WAY'},
    ]) {
      final r = await req('PATCH', '$url/rest/v1/orders?id=eq.${victim['id']}', BH, patch);
      probe('ORD_PATCH_${patch.keys.first}', 'ORDERS', 'buyer', r);
      final live = row((await req('GET', '$url/rest/v1/orders?id=eq.${victim['id']}&select=*', SVC))['body']);
      if (patch.containsKey('status') && live?['status'] == patch['status'] && patch['status'] != 'reserva_pendente') {
        finding(
          id: 'SATI-ORD-05',
          sev: 'P0',
          surface: 'ORDERS',
          identity: 'buyer JWT',
          impact: 'Buyer saltou estado para ${patch['status']} sem captura.',
          request: 'PATCH orders status=${patch['status']}',
          response: live,
          confidence: 'alta',
          variant: '${patch['status']}',
          pre: '${victim['status']}',
          post: '${live?['status']}',
        );
      }
      if (patch.containsKey('price_total') && n(live?['price_total']) == 1) {
        finding(
          id: 'SATI-PRICE-05',
          sev: 'P1',
          surface: 'PRICING',
          identity: 'buyer JWT',
          impact: 'JWT alterou price_total após INSERT.',
          request: 'PATCH price_total=1',
          response: live,
          confidence: 'alta',
        );
      }
      if (patch.containsKey('seller_id') && live?['seller_id'] == buyerId) {
        finding(
          id: 'SATI-ORD-06',
          sev: 'P0',
          surface: 'ORDERS',
          identity: 'buyer JWT',
          impact: 'JWT mudou seller_id (invariante H).',
          request: 'PATCH seller_id=buyer',
          response: live,
          confidence: 'alta',
        );
      }
    }
    // seller hike after order
    await req('PATCH', '$url/rest/v1/products?id=eq.${pHike['id']}', SH, {'price': 15});
    final hikeOrd = await buyerOrder({'product_id': pHike['id'], 'price_total': 15, 'quantity': 1});
    await req('PATCH', '$url/rest/v1/products?id=eq.${pHike['id']}', SH, {'price': 90});
    final hikeLive = row((await req(
      'GET',
      '$url/rest/v1/orders?id=eq.${hikeOrd?['id']}&select=contract_unit_cents,price_total,quantity',
      SVC,
    ))['body']);
    probe('ORD_HIKE_AFTER', 'PRICING', 'seller', {'http': 200, 'body': hikeLive});
    if (n(hikeLive?['contract_unit_cents']) == 9000) {
      finding(
        id: 'SATI-PRICE-06',
        sev: 'P0',
        surface: 'PRICING',
        identity: 'seller JWT',
        impact: 'Hike de catálogo alterou contrato já selado.',
        request: 'PATCH product.price 15→90 after order',
        response: hikeLive,
        confidence: 'alta',
        pre: '1500',
        post: '${hikeLive?['contract_unit_cents']}',
      );
    }

    // payment_method pix / empty / platform seller→pago
    final pix = await buyerOrder({
      'product_id': p40['id'],
      'price_total': 40,
      'payment_method': 'pix',
    });
    if (pix?['id'] != null) {
      final sp = await req('PATCH', '$url/rest/v1/orders?id=eq.${pix!['id']}', SH, {'status': 'pago'});
      probe('ORD_PIX_SELLER_PAGO', 'ORDERS', 'seller', sp);
      final after = row((await req('GET', '$url/rest/v1/orders?id=eq.${pix['id']}&select=status,stock_units_applied', SVC))['body']);
      if (after?['status'] == 'pago') {
        finding(
          id: 'SATI-ORD-07',
          sev: 'P0',
          surface: 'ORDERS',
          identity: 'seller JWT',
          impact: 'Seller marcou pago em método pix (não allowlist) sem captura — mint stock/wallet.',
          request: 'PATCH status=pago payment_method=pix',
          response: after,
          confidence: 'alta',
          variant: 'pix',
        );
      }
    }
    final emptyPm = await buyerOrder({
      'product_id': p40['id'],
      'price_total': 40,
      'payment_method': '',
    });
    if (emptyPm?['id'] != null) {
      final sp = await req('PATCH', '$url/rest/v1/orders?id=eq.${emptyPm!['id']}', SH, {'status': 'pago'});
      probe('ORD_EMPTYPM_SELLER_PAGO', 'ORDERS', 'seller', sp);
      final after = row((await req('GET', '$url/rest/v1/orders?id=eq.${emptyPm['id']}&select=status', SVC))['body']);
      if (after?['status'] == 'pago') {
        finding(
          id: 'SATI-ORD-08',
          sev: 'P0',
          surface: 'ORDERS',
          identity: 'seller JWT',
          impact: 'Seller→pago com payment_method vazio (plataforma fail-open).',
          request: 'PATCH status=pago empty payment_method',
          response: after,
          confidence: 'alta',
        );
      }
    }
    // MB WAY seller pago (positivo — deve funcionar)
    final mb = await buyerOrder({
      'product_id': p1['id'],
      'price_total': 12,
      'quantity': 1,
      'payment_method': 'MB WAY',
    });
    if (mb?['id'] != null) {
      final stockBefore = n(row((await req('GET', '$url/rest/v1/products?id=eq.${p1['id']}&select=quantity', SVC))['body'])?['quantity']);
      final sp = await req('PATCH', '$url/rest/v1/orders?id=eq.${mb!['id']}', SH, {'status': 'pago'});
      probe('ORD_MBWAY_SELLER_PAGO', 'ORDERS', 'seller', sp);
      final after = row((await req('GET', '$url/rest/v1/orders?id=eq.${mb['id']}&select=status,stock_units_applied,quantity', SVC))['body']);
      final stockAfter = n(row((await req('GET', '$url/rest/v1/products?id=eq.${p1['id']}&select=quantity', SVC))['body'])?['quantity']);
      if (after?['status'] != 'pago') {
        notes.add('MB WAY seller→pago BLOQUEADO (regressão produto) http=${sp['http']} st=${after?['status']}');
      } else {
        notes.add('MB WAY seller→pago OK stock $stockBefore→$stockAfter applied=${after?['stock_units_applied']}');
        if (stockAfter != stockBefore - 1) {
          finding(
            id: 'SATI-STOCK-01',
            sev: 'P1',
            surface: 'STOCK',
            identity: 'seller JWT',
            impact: 'Pago MB WAY não consumiu 1 unidade (antes $stockBefore depois $stockAfter).',
            request: 'PATCH MB WAY → pago',
            response: {'order': after, 'stockAfter': stockAfter},
            confidence: 'alta',
            pre: '$stockBefore',
            post: '$stockAfter',
          );
        }
      }
      // restore for later tests
      if (after?['status'] == 'pago') {
        await req('PATCH', '$url/rest/v1/orders?id=eq.${mb['id']}', SVC, {'status': 'cancelado'});
        await req('PATCH', '$url/rest/v1/products?id=eq.${p1['id']}', SVC, {'quantity': 1, 'is_sold': false});
      }
    }
  }

  // offer spoof
  mark('PRICING', 'TESTADA COM VARIANTES');
  final offerIns = await req('POST', '$url/rest/v1/product_offers', BH, {
    'product_id': p40['id'],
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 1,
    'status': 'accepted',
    'offered_by': 'buyer',
    'responded_at': DateTime.now().toUtc().toIso8601String(),
  });
  probe('OFFER_SELF_ACCEPT', 'PRICING', 'buyer', offerIns);
  final ofr = row(offerIns['body']);
  if (ofr != null && ofr['status'] == 'accepted') {
    finding(
      id: 'SATI-PRICE-07',
      sev: 'P1',
      surface: 'PRICING',
      identity: 'buyer JWT',
      impact: 'Buyer inseriu proposta já accepted a 1€.',
      request: 'POST product_offers status=accepted amount=1',
      response: ofr,
      confidence: 'alta',
    );
    final cheap = await buyerOrder({
      'product_id': p40['id'],
      'price_total': 1,
      'product_offer_id': ofr['id'],
    });
    if (n(cheap?['contract_unit_cents']) == 100) {
      finding(
        id: 'SATI-PRICE-08',
        sev: 'P0',
        surface: 'PRICING',
        identity: 'buyer JWT',
        impact: 'Order selada a 1€ via oferta self-accepted (catálogo 40€).',
        request: 'POST orders product_offer_id=self-accepted',
        response: cheap,
        confidence: 'alta',
      );
    }
  } else if (ofr != null) {
    // pending → buyer tries accept
    final acc = await req('PATCH', '$url/rest/v1/product_offers?id=eq.${ofr['id']}', BH, {'status': 'accepted', 'amount': 1});
    probe('OFFER_BUYER_ACCEPT', 'PRICING', 'buyer', acc);
    final of2 = row((await req('GET', '$url/rest/v1/product_offers?id=eq.${ofr['id']}', SVC))['body']);
    if (of2?['status'] == 'accepted') {
      finding(
        id: 'SATI-PRICE-07b',
        sev: 'P1',
        surface: 'PRICING',
        identity: 'buyer JWT',
        impact: 'Buyer aceitou a própria proposta.',
        request: 'PATCH product_offers status=accepted',
        response: of2,
        confidence: 'alta',
      );
    }
  }

  // --- CHECKOUT ---
  mark('CHECKOUT', 'TESTADA COM VARIANTES');
  mark('SETTLE', 'PARCIAL');
  mark('WEBHOOK', 'TESTADA');
  final payOrd = await buyerOrder({
    'product_id': pHike['id'],
    'price_total': 15,
    'quantity': 1,
    'shipping_method': 'entrega em mão',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
  });
  Future<Json> checkout(Map<String, String> hdr, Json body) =>
      req('POST', '$url/functions/v1/create-payment-intent', {
        ...hdr,
        'apikey': anon,
      }, body);

  final ckAnon = await checkout(AN, {'buyer_id': buyerId, 'order_id': payOrd?['id'], 'amount': 50});
  probe('CK_ANON', 'CHECKOUT', 'anon', ckAnon);
  if (ckAnon['http'] == 200 && (ckAnon['body'] is Map && (ckAnon['body'] as Map)['checkoutUrl'] != null)) {
    finding(
      id: 'SATI-CK-01',
      sev: 'P0',
      surface: 'CHECKOUT',
      identity: 'anon',
      impact: 'Checkout sem JWT criou Session Stripe.',
      request: 'POST create-payment-intent anon',
      response: ckAnon,
      confidence: 'alta',
    );
  }
  final ckSeller = await checkout(SH, {
    'buyer_id': buyerId,
    'order_id': payOrd?['id'],
    'amount': 50,
  });
  probe('CK_SELLER_AS_BUYER', 'CHECKOUT', 'seller', ckSeller);
  if (ckSeller['http'] == 200 && ckSeller['body'] is Map && (ckSeller['body'] as Map)['checkoutUrl'] != null) {
    finding(
      id: 'SATI-CK-02',
      sev: 'P0',
      surface: 'CHECKOUT',
      identity: 'seller JWT',
      impact: 'Seller iniciou checkout da order do buyer.',
      request: 'POST create-payment-intent buyer_id=victim',
      response: ckSeller,
      confidence: 'alta',
    );
  }
  final ckAmt = await checkout(BH, {
    'buyer_id': buyerId,
    'order_id': payOrd?['id'],
    'amount': 50,
    'shipping_method': 'entrega em mão',
  });
  probe('CK_BODY_AMOUNT_50', 'CHECKOUT', 'buyer', ckAmt);
  if (ckAmt['http'] == 200 && ckAmt['body'] is Map) {
    final served = n((ckAmt['body'] as Map)['server_amount_cents']);
    final total = n((ckAmt['body'] as Map)['amount_total']);
    if (served == 50 || total == 50) {
      finding(
        id: 'SATI-CK-03',
        sev: 'P0',
        surface: 'CHECKOUT',
        identity: 'buyer JWT',
        impact: 'body.amount=50 ditou Session (contrato ~15€+fees).',
        request: 'POST create-payment-intent amount=50',
        response: ckAmt['body'],
        confidence: 'alta',
      );
    } else {
      notes.add('checkout ignora body.amount served=$served total=$total');
    }
  }
  // product swap in body
  final ckSwap = await checkout(BH, {
    'buyer_id': buyerId,
    'order_id': payOrd?['id'],
    'product_id': p40['id'],
    'seller_id': sellerId,
    'amount': 4000,
    'shipping_method': 'entrega em mão',
  });
  probe('CK_PRODUCT_SWAP', 'CHECKOUT', 'buyer', ckSwap);
  // shipping garbage
  final ckShip = await checkout(BH, {
    'buyer_id': buyerId,
    'order_id': payOrd?['id'],
    'shipping_method': 'gratis_hack',
    'amount': 1,
  });
  probe('CK_SHIP_GARBAGE', 'CHECKOUT', 'buyer', ckShip);
  if (ckShip['http'] == 200) {
    finding(
      id: 'SATI-CK-04',
      sev: 'P1',
      surface: 'CHECKOUT',
      identity: 'buyer JWT',
      impact: 'shipping_method lixo aceite (portes 0?).',
      request: 'shipping_method=gratis_hack',
      response: ckShip,
      confidence: 'média',
    );
  }
  // prize_shipping spoof
  final ckPrize = await checkout(BH, {
    'buyer_id': buyerId,
    'order_id': payOrd?['id'],
    'prize_shipping': true,
    'shipping_method': 'transportadora',
  });
  probe('CK_PRIZE_SPOOF', 'CHECKOUT', 'buyer', ckPrize);
  if (ckPrize['http'] == 200 && ckPrize['body'] is Map) {
    final amt = n((ckPrize['body'] as Map)['server_amount_cents']);
    if (amt > 0 && amt <= 500) {
      finding(
        id: 'SATI-CK-05',
        sev: 'P0',
        surface: 'CHECKOUT',
        identity: 'buyer JWT',
        impact: 'prize_shipping=true cobrou só portes ($amt cents) em order não-rifa.',
        request: 'prize_shipping true on normal order',
        response: ckPrize['body'],
        confidence: 'alta',
      );
    }
  }
  // buyer_id swap
  final ckBuySwap = await checkout(BH, {
    'buyer_id': sellerId,
    'order_id': payOrd?['id'],
    'shipping_method': 'entrega em mão',
  });
  probe('CK_BUYER_SWAP', 'CHECKOUT', 'buyer', ckBuySwap);
  if (ckBuySwap['http'] == 200 && ckBuySwap['body'] is Map && (ckBuySwap['body'] as Map)['checkoutUrl'] != null) {
    finding(
      id: 'SATI-CK-06',
      sev: 'P0',
      surface: 'CHECKOUT',
      identity: 'buyer JWT',
      impact: 'Checkout com buyer_id ≠ JWT aceite.',
      request: 'buyer_id=seller order=own',
      response: ckBuySwap,
      confidence: 'alta',
    );
  }
  // order swap: seller's? we only have buyer orders. Try random uuid
  final ckGhost = await checkout(BH, {
    'buyer_id': buyerId,
    'order_id': '00000000-0000-0000-0000-000000000001',
    'shipping_method': 'entrega em mão',
  });
  probe('CK_GHOST_ORDER', 'CHECKOUT', 'buyer', ckGhost);

  // hike after session: create session, hike catalog, compare session amount
  await req('PATCH', '$url/rest/v1/products?id=eq.${pHike['id']}', SH, {'price': 15});
  final ckBefore = await checkout(BH, {
    'buyer_id': buyerId,
    'order_id': payOrd?['id'],
    'shipping_method': 'entrega em mão',
  });
  await req('PATCH', '$url/rest/v1/products?id=eq.${pHike['id']}', SH, {'price': 88});
  final ckAfter = await checkout(BH, {
    'buyer_id': buyerId,
    'order_id': payOrd?['id'],
    'shipping_method': 'entrega em mão',
  });
  probe('CK_HIKE_SESSION', 'CHECKOUT', 'buyer', ckAfter, note: 'before=${snippet(ckBefore['body'], 200)}');
  if (ckBefore['http'] == 200 && ckAfter['http'] == 200) {
    final a1 = n((ckBefore['body'] as Map?)?['server_amount_cents']);
    final a2 = n((ckAfter['body'] as Map?)?['server_amount_cents']);
    if (a1 > 0 && a2 > 0 && (a2 - a1).abs() > 50) {
      finding(
        id: 'SATI-CK-07',
        sev: 'P0',
        surface: 'CHECKOUT',
        identity: 'seller JWT + buyer checkout',
        impact: 'Hike de catálogo mudou Session ($a1 → $a2) — invariante K.',
        request: 'product.price 15→88 then checkout same order',
        response: {'before': a1, 'after': a2},
        confidence: 'alta',
      );
    }
  }

  // webhook unsigned
  final wh = await req('POST', '$url/functions/v1/stripe-webhook', AN, {'type': 'checkout.session.completed'});
  probe('WH_UNSIGNED', 'WEBHOOK', 'anon', wh);
  if (wh['http'] == 200) {
    finding(
      id: 'SATI-WH-01',
      sev: 'P0',
      surface: 'WEBHOOK',
      identity: 'anon',
      impact: 'Webhook Stripe aceitou corpo sem assinatura.',
      request: 'POST stripe-webhook unsigned',
      response: wh,
      confidence: 'média',
      fp: '200 vazio/ignore ≠ settle; só P0 se marcar order paga',
    );
  }

  // --- BAG ---
  mark('BAG', 'TESTADA COM VARIANTES');
  final bag1 = await buyerOrder({'product_id': pBagA['id'], 'price_total': 10, 'quantity': 1, 'payment_method': 'Pagamento na app (Seguro Fleaber)'});
  final bag2 = await buyerOrder({'product_id': pBagB['id'], 'price_total': 7, 'quantity': 1, 'payment_method': 'Pagamento na app (Seguro Fleaber)'});
  final ckBag = await checkout(BH, {
    'buyer_id': buyerId,
    'order_id': bag1?['id'],
    'bag_checkout': true,
    'shipping_method': 'entrega em mão',
    'bag_lines': [
      {'order_id': bag1?['id'], 'line_total_cents': 1, 'quantity': 1},
      {'order_id': bag2?['id'], 'line_total_cents': 1, 'quantity': 1},
    ],
    'amount': 2,
  });
  probe('BAG_LINE_TOTAL_SPOOF', 'BAG', 'buyer', ckBag);
  if (ckBag['http'] == 200 && ckBag['body'] is Map) {
    final served = n((ckBag['body'] as Map)['server_amount_cents']);
    if (served == 2) {
      finding(
        id: 'SATI-BAG-01',
        sev: 'P0',
        surface: 'BAG',
        identity: 'buyer JWT',
        impact: 'Saco cobrou 2 cents via line_total_cents (catálogo 10+7).',
        request: 'bag_lines line_total_cents=1,1 amount=2',
        response: ckBag['body'],
        confidence: 'alta',
      );
    }
    notes.add('bag served=$served (expect ~1700+fees or items+prot)');
  }
  // bag with foreign order
  final ckBagX = await checkout(BH, {
    'buyer_id': buyerId,
    'order_id': bag1?['id'],
    'bag_checkout': true,
    'shipping_method': 'entrega em mão',
    'bag_lines': [
      {'order_id': bag1?['id']},
      {'order_id': '00000000-0000-0000-0000-000000000099'},
    ],
  });
  probe('BAG_FOREIGN_LINE', 'BAG', 'buyer', ckBagX);

  // --- LIVE RESERVATIONS ---
  mark('LIVE', 'TESTADA COM VARIANTES');
  mark('RESERVATIONS', 'TESTADA COM VARIANTES');
  final lives = await req('GET', '$url/rest/v1/lives?select=id,seller_id,status,is_active&limit=5', SVC);
  final liveRow = row(lives['body']);
  final liveId = liveRow?['id'];
  Json? liveItem;
  if (liveId != null) {
    final items = await req('GET', '$url/rest/v1/live_items?live_id=eq.$liveId&select=id,price,product_id,quantity&limit=3', SVC);
    liveItem = row(items['body']);
  }
  if (liveItem != null && liveId != null) {
    final resIns = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
      'live_id': liveId,
      'live_item_id': liveItem['id'],
      'buyer_id': buyerId,
      'seller_id': liveRow?['seller_id'] ?? sellerId,
      'requested_qty': 9,
      'status': 'accepted',
    });
    probe('RES_INSERT_ACCEPTED', 'RESERVATIONS', 'buyer', resIns);
    final rr = row(resIns['body']);
    if (rr != null && rr['status'] == 'accepted') {
      finding(
        id: 'SATI-RES-01',
        sev: 'P1',
        surface: 'RESERVATIONS',
        identity: 'buyer JWT',
        impact: 'Buyer inseriu reserva accepted qty=9.',
        request: 'POST live_reservation_requests status=accepted qty=9',
        response: rr,
        confidence: 'alta',
      );
    }
    if (rr != null && rr['status'] == 'pending') {
      final up = await req('PATCH', '$url/rest/v1/live_reservation_requests?id=eq.${rr['id']}', BH, {
        'status': 'accepted',
        'requested_qty': 9,
      });
      probe('RES_BUYER_ACCEPT', 'RESERVATIONS', 'buyer', up);
      final after = row((await req('GET', '$url/rest/v1/live_reservation_requests?id=eq.${rr['id']}', SVC))['body']);
      if (after?['status'] == 'accepted') {
        finding(
          id: 'SATI-RES-02',
          sev: 'P1',
          surface: 'RESERVATIONS',
          identity: 'buyer JWT',
          impact: 'Buyer auto-aceitou reserva.',
          request: 'PATCH status=accepted',
          response: after,
          confidence: 'alta',
        );
      }
    }
    // order qty > reservation
    final liveOrd = await req('POST', '$url/rest/v1/orders', BH, {
      'buyer_id': buyerId,
      'seller_id': liveRow?['seller_id'] ?? sellerId,
      'product_id': liveItem['product_id'],
      'live_item_id': liveItem['id'],
      'live_id': liveId,
      'quantity': 8,
      'price_total': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    probe('RES_ORDER_QTY_EXCEED', 'RESERVATIONS', 'buyer', liveOrd);
    final lo = row(liveOrd['body']);
    if (lo != null) {
      orderIds.add('${lo['id']}');
      if (n(lo['quantity']) >= 8) {
        finding(
          id: 'SATI-RES-03',
          sev: 'P1',
          surface: 'RESERVATIONS',
          identity: 'buyer JWT',
          impact: 'Order live qty=${lo['quantity']} sem reserva aceite correspondente.',
          request: 'POST orders live_item qty=8',
          response: lo,
          confidence: 'média',
          fp: 'FAIL se não houver reserva; P1 se cria venda > stock live',
        );
      }
    }
  } else {
    notes.add('LIVE/RESERVATIONS: sem live_item em staging neste momento — variantes de INSERT ainda corridas se tabela vazia');
    final ghostRes = await req('POST', '$url/rest/v1/live_reservation_requests', BH, {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'buyer_id': buyerId,
      'requested_qty': 2,
      'status': 'accepted',
    });
    probe('RES_GHOST_LIVE', 'RESERVATIONS', 'buyer', ghostRes);
  }

  // --- CHAT ---
  mark('CHAT', 'TESTADA COM VARIANTES');
  final chatIns = await req('POST', '$url/rest/v1/chats', BH, {
    'user_a': buyerId,
    'user_b': sellerId,
    'product_id': p40['id'],
  });
  probe('CHAT_CREATE', 'CHAT', 'buyer', chatIns);
  final chat = row(chatIns['body']);
  if (chat?['id'] != null) {
    final msg = await req('POST', '$url/rest/v1/chat_messages', BH, {
      'chat_id': chat!['id'],
      'sender_id': sellerId,
      'receiver_id': buyerId,
      'content': 'spoof-$stamp',
      'is_system': true,
      'system_message': true,
    });
    probe('CHAT_SPOOF_SENDER', 'CHAT', 'buyer', msg);
    final m = row(msg['body']);
    if (m != null && m['sender_id'] == sellerId) {
      finding(
        id: 'SATI-CHAT-01',
        sev: 'P1',
        surface: 'CHAT',
        identity: 'buyer JWT',
        impact: 'Buyer inseriu mensagem com sender_id do vendedor.',
        request: 'POST chat_messages sender_id=seller',
        response: m,
        confidence: 'alta',
      );
    }
    if (m != null && (m['is_system'] == true || m['system_message'] == true)) {
      finding(
        id: 'SATI-CHAT-02',
        sev: 'P2',
        surface: 'CHAT',
        identity: 'buyer JWT',
        impact: 'Buyer forjou mensagem de sistema.',
        request: 'is_system true',
        response: m,
        confidence: 'alta',
      );
    }
    final xchat = await req('GET', '$url/rest/v1/chats?select=*&limit=20', AN);
    probe('CHAT_ANON_LIST', 'CHAT', 'anon', xchat);
    if (xchat['http'] == 200 && xchat['body'] is List && (xchat['body'] as List).isNotEmpty) {
      finding(
        id: 'SATI-CHAT-03',
        sev: 'P1',
        surface: 'CHAT',
        identity: 'anon',
        impact: 'Anon lista chats.',
        request: 'GET chats',
        response: {'n': (xchat['body'] as List).length, 'sample': (xchat['body'] as List).first},
        confidence: 'alta',
      );
    }
  }

  // --- REVIEWS ---
  mark('REVIEWS', 'TESTADA COM VARIANTES');
  final unpaid = await buyerOrder({'product_id': p40['id'], 'price_total': 40, 'status': 'reserva_pendente'});
  if (unpaid?['id'] != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.${unpaid!['id']}', BH, {'status': 'concluido'});
    final rv = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': unpaid['id'],
      'buyer_id': buyerId,
      'target_id': sellerId,
      'stars': 5,
      'comment': 'sati',
      'is_automatic': true,
      'author_role': 'comprador',
    });
    probe('REV_UNPAID', 'REVIEWS', 'buyer', rv);
    if (rv['http'] == 201) {
      finding(
        id: 'SATI-REV-01',
        sev: 'P1',
        surface: 'REVIEWS',
        identity: 'buyer JWT',
        impact: 'Review em order não paga (release wallet?).',
        request: 'POST reviews on reserva_pendente',
        response: rv,
        confidence: 'alta',
      );
    }
    final rv2 = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': unpaid['id'],
      'buyer_id': sellerId,
      'target_id': buyerId,
      'stars': 1,
    });
    probe('REV_SPOOF_IDS', 'REVIEWS', 'buyer', rv2);
  }

  // --- DISPUTES ---
  mark('DISPUTE', 'TESTADA COM VARIANTES');
  mark('REFUND', 'TESTADA COM VARIANTES');
  if (unpaid?['id'] != null) {
    final d = await req('POST', '$url/rest/v1/order_disputes', BH, {
      'order_id': unpaid!['id'],
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'seller_refund_percent': 100,
      'seller_offer_set_by': buyerId,
      'status': 'aberta',
      'reason': 'sati',
    });
    probe('DIS_INSERT_PERCENT', 'DISPUTE', 'buyer', d);
    final dr = row(d['body']);
    if (dr != null && n(dr['seller_refund_percent']) == 100 && dr['seller_offer_set_by'] == buyerId) {
      finding(
        id: 'SATI-DIS-01',
        sev: 'P1',
        surface: 'DISPUTE',
        identity: 'buyer JWT',
        impact: 'Buyer criou disputa com 100% e seller_offer_set_by=self.',
        request: 'POST order_disputes percent=100 set_by=buyer',
        response: dr,
        confidence: 'alta',
      );
    }
    if (dr?['id'] != null) {
      final up = await req('PATCH', '$url/rest/v1/order_disputes?id=eq.${dr!['id']}', BH, {
        'seller_refund_percent': 100,
        'seller_offer_set_by': sellerId,
        'seller_offer_type': 'full_refund',
      });
      probe('DIS_BUYER_SET_OFFER', 'DISPUTE', 'buyer', up);
      final after = row((await req('GET', '$url/rest/v1/order_disputes?id=eq.${dr['id']}', SVC))['body']);
      if (after != null && n(after['seller_refund_percent']) == 100 && after['seller_offer_set_by'] == sellerId) {
        finding(
          id: 'SATI-DIS-02',
          sev: 'P0',
          surface: 'DISPUTE',
          identity: 'buyer JWT',
          impact: 'Buyer forjou oferta do vendedor 100% (refund RPC pode honrar).',
          request: 'PATCH seller_refund_percent=100 set_by=seller',
          response: after,
          confidence: 'alta',
        );
      }
    }
  }
  final refBuyer = await req('POST', '$url/functions/v1/refund-order', BH, {'order_id': payOrd?['id']});
  probe('REFUND_AS_BUYER', 'REFUND', 'buyer', refBuyer);
  if (refBuyer['http'] == 200 && refBuyer['body'] is Map && (refBuyer['body'] as Map)['ok'] == true && (refBuyer['body'] as Map)['skipped'] != true) {
    finding(
      id: 'SATI-REF-01',
      sev: 'P0',
      surface: 'REFUND',
      identity: 'buyer JWT',
      impact: 'Buyer executou refund-order da própria compra.',
      request: 'POST refund-order',
      response: refBuyer,
      confidence: 'alta',
    );
  }
  final refAnon = await req('POST', '$url/functions/v1/refund-order', AN, {'order_id': payOrd?['id']});
  probe('REFUND_ANON', 'REFUND', 'anon', refAnon);

  // --- STORAGE ---
  mark('STORAGE', 'TESTADA COM VARIANTES');
  final buckets = ['chat_media', 'fleaber_private', 'product-images', 'products', 'avatars'];
  for (final b in buckets) {
    final listAnon = await req('POST', '$url/storage/v1/object/list/$b', AN, {'prefix': '', 'limit': 10});
    probe('STOR_LIST_${b}_anon', 'STORAGE', 'anon', listAnon);
    final listB = await req('POST', '$url/storage/v1/object/list/$b', BH, {'prefix': '', 'limit': 10});
    probe('STOR_LIST_${b}_buyer', 'STORAGE', 'buyer', listB);
    if (listAnon['http'] == 200 && listAnon['body'] is List && (listAnon['body'] as List).isNotEmpty) {
      notes.add('anon list $b n=${(listAnon['body'] as List).length}');
    }
  }
  final upCross = await http.post(
    Uri.parse('$url/storage/v1/object/chat_media/order_proofs/$sellerId/sati-$stamp.txt'),
    headers: {'apikey': anon, 'Authorization': 'Bearer $buyerTok', 'Content-Type': 'text/plain'},
    body: 'sati-cross',
  );
  probe('STOR_UPLOAD_CROSS', 'STORAGE', 'buyer', {'http': upCross.statusCode, 'body': upCross.body});
  if (upCross.statusCode == 200 || upCross.statusCode == 201) {
    finding(
      id: 'SATI-STOR-01',
      sev: 'P1',
      surface: 'STORAGE',
      identity: 'buyer JWT',
      impact: 'Buyer escreveu em order_proofs/{seller}/…',
      request: 'POST storage chat_media/order_proofs/seller/…',
      response: upCross.body,
      confidence: 'alta',
    );
    await http.delete(
      Uri.parse('$url/storage/v1/object/chat_media/order_proofs/$sellerId/sati-$stamp.txt'),
      headers: SVC,
    );
  }
  final upPriv = await http.post(
    Uri.parse('$url/storage/v1/object/fleaber_private/order_proofs/$sellerId/sati-$stamp.txt'),
    headers: {'apikey': anon, 'Authorization': 'Bearer $buyerTok', 'Content-Type': 'text/plain'},
    body: 'sati-priv',
  );
  probe('STOR_PRIV_CROSS', 'STORAGE', 'buyer', {'http': upPriv.statusCode, 'body': upPriv.body});
  if (upPriv.statusCode == 200 || upPriv.statusCode == 201) {
    finding(
      id: 'SATI-STOR-02',
      sev: 'P1',
      surface: 'STORAGE',
      identity: 'buyer JWT',
      impact: 'Upload fleaber_private no prefixo do vendedor.',
      request: 'POST fleaber_private/order_proofs/seller',
      response: upPriv.body,
      confidence: 'alta',
    );
    await http.delete(
      Uri.parse('$url/storage/v1/object/fleaber_private/order_proofs/$sellerId/sati-$stamp.txt'),
      headers: SVC,
    );
  }
  final trav = await http.post(
    Uri.parse('$url/storage/v1/object/fleaber_private/order_proofs/$buyerId/../$sellerId/sati-trav-$stamp.txt'),
    headers: {'apikey': anon, 'Authorization': 'Bearer $buyerTok', 'Content-Type': 'text/plain'},
    body: 'trav',
  );
  probe('STOR_TRAV', 'STORAGE', 'buyer', {'http': trav.statusCode, 'body': trav.body});
  final pub = await req('GET', '$url/storage/v1/object/public/fleaber_private/order_proofs/$buyerId/nope.txt', AN);
  probe('STOR_PUBLIC_PRIV', 'STORAGE', 'anon', pub);

  // --- RAFFLE ---
  mark('RAFFLE', 'TESTADA COM VARIANTES');
  final raffIns = await req('POST', '$url/rest/v1/live_raffle_winners', BH, {
    'raffle_id': '00000000-0000-0000-0000-000000000001',
    'buyer_id': buyerId,
    'winner_id': buyerId,
  });
  probe('RAF_WINNER_INS', 'RAFFLE', 'buyer', raffIns);
  if (raffIns['http'] == 201) {
    finding(
      id: 'SATI-RAF-01',
      sev: 'P0',
      surface: 'RAFFLE',
      identity: 'buyer JWT',
      impact: 'Buyer inseriu-se como vencedor de rifa.',
      request: 'POST live_raffle_winners',
      response: raffIns,
      confidence: 'alta',
    );
  }
  final tickets = await req('POST', '$url/rest/v1/live_raffle_tickets', BH, {
    'raffle_id': '00000000-0000-0000-0000-000000000001',
    'buyer_id': buyerId,
    'user_id': buyerId,
  });
  probe('RAF_TICKET_INS', 'RAFFLE', 'buyer', tickets);

  // --- TIPS ---
  mark('TIPS', 'TESTADA COM VARIANTES');
  final tipEdge = await req('POST', '$url/functions/v1/create-live-tip-checkout', BH, {
    'seller_id': sellerId,
    'amount_eur': 1,
    'tip_id': '00000000-0000-0000-0000-000000000042',
    'live_id': liveId,
  });
  probe('TIP_CLIENT_ID', 'TIPS', 'buyer', tipEdge);
  final tipHi = await req('POST', '$url/functions/v1/create-live-tip-checkout', BH, {
    'seller_id': sellerId,
    'amount_eur': 99999,
  });
  probe('TIP_MAX', 'TIPS', 'buyer', tipHi);
  if (tipHi['http'] == 200) {
    finding(
      id: 'SATI-TIP-01',
      sev: 'P1',
      surface: 'TIPS',
      identity: 'buyer JWT',
      impact: 'Gorjeta 99999€ aceite.',
      request: 'amount_eur=99999',
      response: tipHi,
      confidence: 'alta',
    );
  }
  final tipNeg = await req('POST', '$url/functions/v1/create-live-tip-checkout', BH, {
    'seller_id': sellerId,
    'amount_eur': -5,
  });
  probe('TIP_NEG', 'TIPS', 'buyer', tipNeg);
  final tipAnon = await req('POST', '$url/functions/v1/create-live-tip-checkout', AN, {
    'seller_id': sellerId,
    'amount_eur': 2,
  });
  probe('TIP_ANON', 'TIPS', 'anon', tipAnon);
  if (tipAnon['http'] == 200) {
    finding(
      id: 'SATI-TIP-02',
      sev: 'P0',
      surface: 'TIPS',
      identity: 'anon',
      impact: 'Checkout de gorjeta anónimo.',
      request: 'create-live-tip-checkout anon',
      response: tipAnon,
      confidence: 'alta',
    );
  }

  // --- MUX / LIVEKIT / PS ---
  mark('MUX', 'TESTADA COM VARIANTES');
  mark('LIVEKIT', 'TESTADA COM VARIANTES');
  mark('PS/OCR', 'TESTADA COM VARIANTES');
  final muxBuyer = await req('POST', '$url/functions/v1/create-mux-live', BH, {'title': 'sati-buyer-live'});
  probe('MUX_CREATE_BUYER', 'MUX', 'buyer', muxBuyer);
  if (muxBuyer['http'] == 200) {
    finding(
      id: 'SATI-MUX-02',
      sev: 'P1',
      surface: 'MUX',
      identity: 'buyer JWT',
      impact: 'Buyer criou live Mux (custo + stream).',
      request: 'POST create-mux-live',
      response: muxBuyer,
      confidence: 'alta',
    );
  }
  final muxAnon = await req('POST', '$url/functions/v1/create-mux-live', AN, {'title': 'sati-anon'});
  probe('MUX_CREATE_ANON', 'MUX', 'anon', muxAnon);
  if (liveId != null) {
    final cmpl = await req('POST', '$url/functions/v1/complete-mux-live', BH, {'live_id': liveId});
    probe('MUX_COMPLETE_FOREIGN', 'MUX', 'buyer', cmpl);
    if (cmpl['http'] == 200) {
      finding(
        id: 'SATI-MUX-03',
        sev: 'P1',
        surface: 'MUX',
        identity: 'buyer JWT',
        impact: 'Buyer complete-mux-live em live alheia.',
        request: 'POST complete-mux-live live_id=foreign',
        response: cmpl,
        confidence: 'alta',
      );
    }
    final lkp = await req('POST', '$url/functions/v1/livekit-mux-publish', BH, {'step': 'token', 'live_id': liveId});
    probe('LK_TOKEN_FOREIGN', 'LIVEKIT', 'buyer', lkp);
    final play = await req('POST', '$url/functions/v1/resolve-mux-playback', AN, {'live_id': liveId});
    probe('MUX_PLAYBACK_ANON', 'MUX', 'anon', play);
    if (play['http'] == 200 && snippet(play['body']).contains('stream_key')) {
      finding(
        id: 'SATI-MUX-04',
        sev: 'P0',
        surface: 'MUX',
        identity: 'anon',
        impact: 'resolve-mux-playback devolveu stream_key.',
        request: 'POST resolve-mux-playback',
        response: play,
        confidence: 'alta',
      );
    }
  }
  final eg = await req('POST', '$url/functions/v1/livekit-egress-cleanup', AN, {});
  probe('LK_EGRESS_ANON', 'LIVEKIT', 'anon', eg);
  if (eg['http'] == 200) {
    finding(
      id: 'SATI-LK-01',
      sev: 'P1',
      surface: 'LIVEKIT',
      identity: 'anon',
      impact: 'livekit-egress-cleanup sem secret.',
      request: 'POST livekit-egress-cleanup',
      response: eg,
      confidence: 'alta',
    );
  }

  final pair = await req('POST', '$url/functions/v1/ps-pairing-claim', AN, {'code': '000000', 'device_id': 'sati'});
  probe('PS_PAIR_000000', 'PS/OCR', 'anon', pair);
  // rate: 5 codes
  var pairHits = 0;
  for (var i = 0; i < 8; i++) {
    final code = (100000 + Random(stamp + i).nextInt(900000)).toString();
    final r = await req('POST', '$url/functions/v1/ps-pairing-claim', AN, {'code': code, 'device_id': 'sati-$i'});
    if (r['http'] == 200) pairHits++;
    if (i == 0) probe('PS_PAIR_RAND', 'PS/OCR', 'anon', r);
    if (r['http'] == 429) {
      notes.add('PS pairing rate-limited at i=$i');
      break;
    }
  }
  if (pairHits > 0) {
    finding(
      id: 'SATI-PS-01',
      sev: 'P1',
      surface: 'PS/OCR',
      identity: 'anon',
      impact: 'Pairing claim 200 com código aleatório ($pairHits hits).',
      request: 'POST ps-pairing-claim random 6-digit',
      response: {'hits': pairHits},
      confidence: 'média',
    );
  }
  final ocr = await req('POST', '$url/functions/v1/ingest-ocr-reservation', AN, {
    'live_id': liveId ?? '00000000-0000-0000-0000-000000000001',
    'ocr_line_hash': 'abcdef123456',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
    'requested_qty': 5,
    'ref_slug': 'x1',
  });
  probe('OCR_NO_TOKEN', 'PS/OCR', 'anon', ocr);
  if (ocr['http'] == 200) {
    finding(
      id: 'SATI-PS-02',
      sev: 'P0',
      surface: 'PS/OCR',
      identity: 'anon',
      impact: 'OCR ingest sem device token.',
      request: 'POST ingest-ocr-reservation no token',
      response: ocr,
      confidence: 'alta',
    );
  }
  final ocrTok = await req('POST', '$url/functions/v1/ingest-ocr-reservation', {
    ...AN,
    'x-device-token': 'deadbeef-sati-token',
  }, {
    'live_id': liveId ?? '00000000-0000-0000-0000-000000000001',
    'ocr_line_hash': 'abcdef1234567890',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
    'requested_qty': 4,
    'ref_slug': 'hack',
    'external_display_name': 'HACKER',
  });
  probe('OCR_GARBAGE_TOKEN', 'PS/OCR', 'anon', ocrTok);
  if (ocrTok['http'] == 200 && ocrTok['body'] is Map && (ocrTok['body'] as Map)['ok'] == true) {
    finding(
      id: 'SATI-PS-03',
      sev: 'P0',
      surface: 'PS/OCR',
      identity: 'anon',
      impact: 'OCR ingest com token lixo criou reserva.',
      request: 'x-device-token=garbage',
      response: ocrTok,
      confidence: 'alta',
    );
  }

  // --- remaining edges ---
  mark('RPC/DEFINER', 'TESTADA COM VARIANTES');
  final edges = [
    ['create-connect-account', BH, {'amount_eur': 1}],
    ['create-connect-account', AN, {'amount_eur': 1}],
    ['delete-test-account', BH, {'confirm': 'NO'}],
    ['delete-test-account', AN, {'confirm': 'NO'}],
    ['sec-fase2-e2e-oversell', BH, {}],
    ['sec-fase2-e2e-oversell', AN, {}],
    ['meta-data-deletion', AN, {}],
    ['send-sms-bulkgate', AN, {'phone': '+351900000000', 'text': 'hi'}],
    ['ps-heartbeat', AN, {'device_id': 'sati'}],
    ['ps-panel-log', AN, {}],
  ];
  for (final ed in edges) {
    final r = await req('POST', '$url/functions/v1/${ed[0]}', ed[1] as Map<String, String>, ed[2]);
    probe('EDGE_${ed[0]}_${(ed[1] as Map)['Authorization'] == 'Bearer $anon' || ((ed[1] as Map)['Authorization'] as String).contains(anon.substring(0, 12)) ? 'anon' : 'jwt'}', 'RPC/DEFINER', 'edge', r);
    final name = ed[0] as String;
    if (r['http'] == 200 && (name == 'delete-test-account' || name == 'sec-fase2-e2e-oversell' || name == 'send-sms-bulkgate')) {
      // don't auto-P0 delete-test-account 200 if it deleted OUR test buyer — check body
      finding(
        id: 'SATI-EDGE-01',
        sev: name == 'delete-test-account' ? 'P0' : 'P1',
        surface: 'RPC/DEFINER',
        identity: 'probe',
        impact: 'Edge $name respondeu 200 a identidade não privilegiada.',
        request: 'POST $name',
        response: r,
        confidence: 'média',
        variant: name,
        fp: '200 skipped/error json pode ser fail-closed; confirmar efeito',
      );
    }
  }

  // =====================================================================
  // PASSAGEM 2 — invariantes (com Stripe TEST se possível)
  // =====================================================================
  pass = 2;
  stdout.writeln('\n======== PASSAGEM 2 INVARIANTES ========');
  mark('CHECKOUT', 'TESTADA COM VARIANTES');
  mark('SETTLE', 'TESTADA COM VARIANTES');
  mark('RACES', 'TESTADA COM VARIANTES');
  mark('COMPOSITION', 'TESTADA COM VARIANTES');
  mark('PAYOUT', 'TESTADA COM VARIANTES');

  Json? paidSession;
  int? quoted;
  if (payOrd?['id'] != null) {
    final q = await checkout(BH, {
      'buyer_id': buyerId,
      'order_id': payOrd!['id'],
      'shipping_method': 'entrega em mão',
    });
    probe('INV_A_QUOTE', 'CHECKOUT', 'buyer', q);
    if (q['http'] == 200 && q['body'] is Map) {
      quoted = n((q['body'] as Map)['server_amount_cents']).toInt();
      final sid = (q['body'] as Map)['checkoutSessionId']?.toString();
      notes.add('invA quote=$quoted session=$sid contract_unit=${payOrd['contract_unit_cents']}');
      // duplicate session
      final q2 = await checkout(BH, {
        'buyer_id': buyerId,
        'order_id': payOrd['id'],
        'shipping_method': 'entrega em mão',
      });
      probe('INV_DUP_SESSION', 'CHECKOUT', 'buyer', q2);
      final sid2 = (q2['body'] as Map?)?['checkoutSessionId']?.toString();
      notes.add('dup session $sid vs $sid2');

      if (stripeKey.isNotEmpty && sid != null && sid.isNotEmpty) {
        paidSession = await _stripePaySession(stripeKey, sid);
        probe('INV_STRIPE_PAY', 'SETTLE', 'stripe_test', {'http': paidSession['http'] as int, 'body': paidSession['body']});
        notes.add('stripe pay ${snippet(paidSession)}');
      }
    }
  }

  // concurrent qty=1
  final pRace = await mkProduct(price: 6, qty: 1, title: 'SATI-RACE');
  final oA = await buyerOrder({'product_id': pRace['id'], 'price_total': 6, 'quantity': 1, 'payment_method': 'MB WAY'});
  // second order same product
  final oB = await buyerOrder({'product_id': pRace['id'], 'price_total': 6, 'quantity': 1, 'payment_method': 'MB WAY'});
  if (oA?['id'] != null && oB?['id'] != null) {
    final f1 = req('PATCH', '$url/rest/v1/orders?id=eq.${oA!['id']}', SH, {'status': 'pago'});
    final f2 = req('PATCH', '$url/rest/v1/orders?id=eq.${oB!['id']}', SH, {'status': 'pago'});
    final rs = await Future.wait([f1, f2]);
    probe('RACE_QTY1_A', 'STOCK', 'seller', rs[0]);
    probe('RACE_QTY1_B', 'STOCK', 'seller', rs[1]);
    final stA = row((await req('GET', '$url/rest/v1/orders?id=eq.${oA['id']}&select=status,stock_units_applied', SVC))['body']);
    final stB = row((await req('GET', '$url/rest/v1/orders?id=eq.${oB['id']}&select=status,stock_units_applied', SVC))['body']);
    final pq = row((await req('GET', '$url/rest/v1/products?id=eq.${pRace['id']}&select=quantity', SVC))['body']);
    notes.add('race A=${stA?['status']}/${stA?['stock_units_applied']} B=${stB?['status']}/${stB?['stock_units_applied']} stock=${pq?['quantity']}');
    final paidCount = [stA, stB].where((x) => x?['status'] == 'pago').length;
    if (paidCount == 2) {
      finding(
        id: 'SATI-STOCK-02',
        sev: 'P0',
        surface: 'STOCK',
        identity: 'seller JWT concurrent',
        impact: 'Duas orders pago em produto qty=1 (invariante D).',
        request: 'parallel PATCH pago on two MB WAY orders',
        response: {'A': stA, 'B': stB, 'stock': pq},
        confidence: 'alta',
        variant: 'concurrent',
      );
    }
    // cleanup stock
    await req('PATCH', '$url/rest/v1/products?id=eq.${pRace['id']}', SVC, {'quantity': 0, 'is_sold': true});
  }

  // wallet RPCs again as composition with order
  if (payOrd?['id'] != null) {
    for (final ident in [
      ['buyer', BH],
      ['seller', SH],
    ]) {
      final rel = await req('POST', '$url/rest/v1/rpc/batata_release_seller_wallet_for_order', ident[1] as Map<String, String>, {
        'p_order_id': payOrd!['id'],
      });
      probe('INV_E_RELEASE_${ident[0]}', 'WALLET', ident[0] as String, rel);
      final refw = await req('POST', '$url/rest/v1/rpc/batata_refund_buyer_wallet_for_order', ident[1] as Map<String, String>, {
        'p_order_id': payOrd['id'],
      });
      probe('INV_E_REFUNDW_${ident[0]}', 'WALLET', ident[0] as String, refw);
      final cred = await req('POST', '$url/rest/v1/rpc/batata_credit_wallet_once', ident[1] as Map<String, String>, {
        'p_wallet_id': sellerId,
        'p_order_id': payOrd['id'],
        'p_amount': 50,
        'p_reason': 'sati',
        'p_idempotency_key': 'sati-$stamp',
      });
      probe('INV_E_CREDIT_${ident[0]}', 'WALLET', ident[0] as String, cred);
      if (cred['http'] == 200) {
        finding(
          id: 'SATI-WALLET-02',
          sev: 'P0',
          surface: 'WALLET',
          identity: ident[0] as String,
          impact: 'JWT credit_wallet_once (invariante E).',
          request: 'rpc batata_credit_wallet_once 50',
          response: cred,
          confidence: 'alta',
        );
      }
    }
  }

  // payout edge as buyer vs seller
  final poB = await req('POST', '$url/functions/v1/create-connect-account', BH, {});
  probe('PAYOUT_BUYER', 'PAYOUT', 'buyer', poB);
  final poA = await req('POST', '$url/functions/v1/create-connect-account', AN, {});
  probe('PAYOUT_ANON', 'PAYOUT', 'anon', poA);
  final poS = await req('POST', '$url/functions/v1/create-connect-account', SH, {'idempotency_key': 'sati-$stamp'});
  probe('PAYOUT_SELLER_PROBE', 'PAYOUT', 'seller', poS, note: 'não força transfer se faltar stripe connect');

  // =====================================================================
  // PASSAGEM 3 — composição
  // =====================================================================
  pass = 3;
  stdout.writeln('\n======== PASSAGEM 3 COMPOSIÇÃO ========');
  // proposal + catalog + order
  final pProp = await mkProduct(price: 25, qty: 3, title: 'SATI-PROP');
  final pend = await req('POST', '$url/rest/v1/product_offers', BH, {
    'product_id': pProp['id'],
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 20,
    'offered_by': 'buyer',
    'status': 'pending',
  });
  probe('COMP_OFFER_CREATE', 'PRICING', 'buyer', pend);
  final po = row(pend['body']);
  if (po?['id'] != null) {
    final acc = await req('PATCH', '$url/rest/v1/product_offers?id=eq.${po!['id']}', SH, {'status': 'accepted'});
    probe('COMP_OFFER_ACC', 'PRICING', 'seller', acc);
    await req('PATCH', '$url/rest/v1/products?id=eq.${pProp['id']}', SH, {'price': 80});
    final ordP = await buyerOrder({
      'product_id': pProp['id'],
      'product_offer_id': po['id'],
      'price_total': 20,
    });
    probe('COMP_OFFER_AFTER_HIKE', 'PRICING', 'buyer', {'http': 201, 'body': ordP});
    final cuc = n(ordP?['contract_unit_cents']);
    if (cuc == 8000) {
      finding(
        id: 'SATI-COMP-01',
        sev: 'P1',
        surface: 'PRICING',
        identity: 'composition offer+catalog',
        impact: 'Após oferta aceite, hike de catálogo selou 80€ em vez de 20€ (ou o inverso).',
        request: 'accepted offer 20 then product 80 then order',
        response: ordP,
        confidence: 'alta',
        variant: 'invariante L',
      );
    }
    if (cuc == 2000) {
      notes.add('COMP offer 20€ selada após hike catálogo 80€ — contrato da oferta prevalece (esperado)');
    }
    // seller tries to change accepted offer amount
    final ch = await req('PATCH', '$url/rest/v1/product_offers?id=eq.${po['id']}', SH, {'amount': 5});
    probe('COMP_OFFER_AMOUNT_AFTER_ACC', 'PRICING', 'seller', ch);
    final po2 = row((await req('GET', '$url/rest/v1/product_offers?id=eq.${po['id']}', SVC))['body']);
    if (n(po2?['amount']) == 5) {
      finding(
        id: 'SATI-COMP-02',
        sev: 'P1',
        surface: 'PRICING',
        identity: 'seller JWT',
        impact: 'Seller alterou amount de oferta já aceite.',
        request: 'PATCH product_offers amount=5 after accepted',
        response: po2,
        confidence: 'alta',
      );
    }
  }

  // review + release: try review on MB WAY concluido without capture
  final pRev = await mkProduct(price: 8, qty: 2, title: 'SATI-REV');
  final oRev = await buyerOrder({'product_id': pRev['id'], 'price_total': 8, 'payment_method': 'MB WAY'});
  if (oRev?['id'] != null) {
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oRev!['id']}', SH, {'status': 'pago'});
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oRev['id']}', SH, {'status': 'enviado'});
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oRev['id']}', BH, {'status': 'entregue'});
    await req('PATCH', '$url/rest/v1/orders?id=eq.${oRev['id']}', BH, {'status': 'concluido'});
    final st = row((await req('GET', '$url/rest/v1/orders?id=eq.${oRev['id']}&select=status,wallet_release_processed_at,amount_paid_cents', SVC))['body']);
    probe('COMP_MBWAY_FSM', 'ORDERS', 'buyer+seller', {'http': 200, 'body': st});
    final rv = await req('POST', '$url/rest/v1/reviews', BH, {
      'order_id': oRev['id'],
      'stars': 5,
      'comment': 'ok',
    });
    probe('COMP_REVIEW_AFTER_MBWAY', 'REVIEWS', 'buyer', rv);
    final st2 = row((await req('GET', '$url/rest/v1/orders?id=eq.${oRev['id']}&select=status,wallet_release_processed_at', SVC))['body']);
    notes.add('mbway fsm ${st?['status']} review_http=${rv['http']} release=${st2?['wallet_release_processed_at']}');
  }

  // dispute + refund RPC
  if (oRev?['id'] != null) {
    final d = await req('POST', '$url/rest/v1/order_disputes', BH, {
      'order_id': oRev!['id'],
      'reason': 'comp',
    });
    probe('COMP_DISPUTE', 'DISPUTE', 'buyer', d);
    final part = await req('POST', '$url/rest/v1/rpc/batata_process_partial_refund_dispute', BH, {
      'p_order_id': oRev['id'],
      'p_percent': 100,
    });
    probe('COMP_PARTIAL_RPC_BUYER', 'REFUND', 'buyer', part);
    if (part['http'] == 200) {
      finding(
        id: 'SATI-COMP-03',
        sev: 'P0',
        surface: 'REFUND',
        identity: 'buyer JWT',
        impact: 'Buyer disparou refund parcial RPC.',
        request: 'rpc batata_process_partial_refund_dispute 100%',
        response: part,
        confidence: 'alta',
      );
    }
  }

  // chat + storage + dispute composition already covered

  // bag oversell one line
  final pOver = await mkProduct(price: 5, qty: 1, title: 'SATI-OVER');
  final o1 = await buyerOrder({'product_id': pOver['id'], 'price_total': 5, 'quantity': 1, 'payment_method': 'Pagamento na app (Seguro Fleaber)'});
  final o2 = await buyerOrder({'product_id': pOver['id'], 'price_total': 5, 'quantity': 1, 'payment_method': 'Pagamento na app (Seguro Fleaber)'});
  final bagOver = await checkout(BH, {
    'buyer_id': buyerId,
    'order_id': o1?['id'],
    'bag_checkout': true,
    'shipping_method': 'entrega em mão',
    'bag_lines': [
      {'order_id': o1?['id']},
      {'order_id': o2?['id']},
    ],
  });
  probe('COMP_BAG_OVERSELL', 'BAG', 'buyer', bagOver);
  if (bagOver['http'] == 200) {
    notes.add('bag two lines qty=1 product checkout http 200 served=${(bagOver['body'] as Map?)?['server_amount_cents']} — settle may oversell');
  }

  // =====================================================================
  // PASSAGEM 4 — races / retries / state abuse extra
  // =====================================================================
  pass = 4;
  stdout.writeln('\n======== PASSAGEM 4 RACES / FSM ========');
  mark('RACES', 'TESTADA COM VARIANTES');
  // double checkout same order
  if (payOrd?['id'] != null) {
    final d1 = checkout(BH, {'buyer_id': buyerId, 'order_id': payOrd!['id'], 'shipping_method': 'entrega em mão'});
    final d2 = checkout(BH, {'buyer_id': buyerId, 'order_id': payOrd['id'], 'shipping_method': 'entrega em mão'});
    final both = await Future.wait([d1, d2]);
    probe('RACE_CK_1', 'RACES', 'buyer', both[0]);
    probe('RACE_CK_2', 'RACES', 'buyer', both[1]);
  }
  // FSM jumps as buyer/seller/anon
  final pFsm = await mkProduct(price: 11, qty: 2, title: 'SATI-FSM');
  final oFsm = await buyerOrder({'product_id': pFsm['id'], 'price_total': 11, 'payment_method': 'Pagamento na app (Seguro Fleaber)'});
  if (oFsm?['id'] != null) {
    final states = [
      'pago', 'enviado', 'entregue', 'concluido', 'devolvida', 'cancelado',
      'pedido_devolucao', 'em_devolucao', 'premio_rifa',
    ];
    for (final st in states) {
      for (final ident in [
        ['buyer', BH],
        ['seller', SH],
        ['anon', AN],
      ]) {
        final r = await req('PATCH', '$url/rest/v1/orders?id=eq.${oFsm!['id']}', ident[1] as Map<String, String>, {'status': st});
        final live = row((await req('GET', '$url/rest/v1/orders?id=eq.${oFsm['id']}&select=status', SVC))['body']);
        if (live?['status'] == st && ident[0] != 'service') {
          final sev = (st == 'pago' || st == 'concluido' || st == 'premio_rifa') ? 'P0' : 'P1';
          finding(
            id: 'SATI-FSM-01',
            sev: sev,
            surface: 'ORDERS',
            identity: ident[0] as String,
            impact: '${ident[0]} transicionou unpaid → $st.',
            request: 'PATCH status=$st from reserva_pendente',
            response: live,
            confidence: 'alta',
            variant: '${ident[0]}:$st',
          );
        }
      }
    }
  }

  // return URL settle probe (GET without session)
  final ret = await req('GET', '$url/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_fake', AN);
  probe('SETTLE_FAKE_RETURN', 'SETTLE', 'anon', ret);

  // =====================================================================
  // PASSAGEM 5 — re-sweep crítico (última passagem sem novas classes?)
  // =====================================================================
  pass = 5;
  stdout.writeln('\n======== PASSAGEM 5 RE-SWEEP ========');
  final before5 = Set<String>.from(findings.map((f) => '${f['sev']}:${f['surface']}'));
  // repeat contract, wallet, stream key, webhook, profiles user_type
  final p5 = await mkProduct(price: 18, qty: 2, title: 'SATI-P5');
  final c5 = await req('POST', '$url/rest/v1/orders', BH, {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': p5['id'],
    'quantity': 1,
    'contract_unit_cents': 1,
    'price_total': 0.01,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  probe('P5_CONTRACT', 'PRICING', 'buyer', c5);
  final c5r = row(c5['body']);
  if (c5r != null) orderIds.add('${c5r['id']}');
  if (c5r != null && n(c5r['contract_unit_cents']) == 1) {
    finding(
      id: 'SATI-P5-PRICE',
      sev: 'P0',
      surface: 'PRICING',
      identity: 'buyer JWT',
      impact: 'Passagem 5: contrato JWT 1 cêntimo ainda aceite.',
      request: 'POST orders contract_unit_cents=1',
      response: c5r,
      confidence: 'alta',
    );
  }
  final w5 = await req('POST', '$url/rest/v1/rpc/batata_credit_wallet_once', BH, {
    'p_wallet_id': buyerId,
    'p_order_id': c5r?['id'] ?? payOrd?['id'],
    'p_amount': 1,
    'p_reason': 'p5',
    'p_idempotency_key': 'p5-$stamp',
  });
  probe('P5_CREDIT', 'WALLET', 'buyer', w5);
  final sk5 = await req('GET', '$url/rest/v1/lives?select=mux_stream_key&limit=1', BH);
  probe('P5_STREAM', 'MUX', 'buyer', sk5);
  final after5 = Set<String>.from(findings.map((f) => '${f['sev']}:${f['surface']}'));
  final newIn5 = after5.difference(before5);
  notes.add('pass5_new_classes=$newIn5');

  // coverage fill
  for (final k in [
    'AUTH', 'PROFILES', 'ORDERS', 'PRICING', 'CHECKOUT', 'SETTLE', 'WEBHOOK',
    'BAG', 'REFUND', 'DISPUTE', 'WALLET', 'PAYOUT', 'STOCK', 'LIVE', 'RESERVATIONS',
    'RAFFLE', 'TIPS', 'CHAT', 'REVIEWS', 'STORAGE', 'MUX', 'LIVEKIT', 'PS/OCR',
    'RPC/DEFINER', 'RLS', 'RACES', 'COMPOSITION',
  ]) {
    coverage.putIfAbsent(k, () => 'NÃO TESTADA');
  }

  await cleanup();

  final out = {
    'when': DateTime.now().toUtc().toIso8601String(),
    'staging': 'fxdknzrqjenzqcvnwqqq',
    'production_touched': false,
    'fixes_applied': false,
    'openapi_tables': tables,
    'openapi_rpcs': rpcs,
    'coverage': coverage,
    'notes': notes,
    'findings': findings,
    'probes': probes.length,
    'quoted_cents': quoted,
    'stripe_pay': paidSession == null ? 'not_attempted_or_no_key' : snippet(paidSession),
    'pass_classes': passNewClasses.map((k, v) => MapEntry('$k', v.toList())),
    'new_classes_pass5': newIn5.toList(),
  };
  final jsonFile = File('tool/reports/SAT_INDEP_RAW_20260827.json');
  jsonFile.parent.createSync(recursive: true);
  jsonFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('\nWrote ${jsonFile.path}');
  stdout.writeln('Findings: ${findings.length}');
  for (final f in findings) {
    stdout.writeln('  ${f['sev']} ${f['id']} ${f['surface']} — ${f['impacto']}');
  }
}

Json _rpcGuessArgs(String name, String buyerId, String sellerId) {
  if (name.contains('payout')) {
    return {'p_seller_id': sellerId, 'p_amount': 1, 'p_idempotency_key': 'x', 'p_wallet_id': sellerId};
  }
  if (name.contains('credit') || name.contains('debit')) {
    return {
      'p_wallet_id': sellerId,
      'p_user_id': sellerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 1,
      'p_reason': 'sati',
      'p_idempotency_key': 'sati',
    };
  }
  if (name.contains('ensure')) return {'p_wallet_id': sellerId, 'p_user_id': sellerId};
  if (name.contains('order')) return {'p_order_id': '00000000-0000-0000-0000-000000000001'};
  if (name.contains('tip')) {
    return {
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
      'p_session_id': 'cs_test_x',
      'p_paid_amount_cents': 100,
      'p_live_id': null,
      'p_seller_id': sellerId,
      'p_amount': 1,
    };
  }
  if (name.contains('pairing')) return {'p_code': '000000', 'p_device_id': 'x'};
  return {};
}

Future<Json> _stripePaySession(String sk, String sessionId) async {
  final auth = {'Authorization': 'Bearer $sk'};
  final s = await http.get(Uri.parse('https://api.stripe.com/v1/checkout/sessions/$sessionId'), headers: auth);
  Json sess = {};
  try {
    sess = Json.from(jsonDecode(s.body) as Map);
  } catch (_) {}
  final pi = sess['payment_intent']?.toString() ?? '';
  if (pi.isEmpty) {
    return {'http': s.statusCode, 'body': sess, 'step': 'no_pi'};
  }
  final conf = await http.post(
    Uri.parse('https://api.stripe.com/v1/payment_intents/$pi/confirm'),
    headers: {...auth, 'Content-Type': 'application/x-www-form-urlencoded'},
    body: 'payment_method=pm_card_visa',
  );
  dynamic cbody;
  try {
    cbody = jsonDecode(conf.body);
  } catch (_) {
    cbody = conf.body;
  }
  return {
    'http': conf.statusCode,
    'body': cbody,
    'session_amount_total': sess['amount_total'],
    'currency': sess['currency'],
    'payment_intent': pi,
  };
}
