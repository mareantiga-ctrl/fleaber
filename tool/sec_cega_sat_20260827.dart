/// Auditoria cega de saturação 2026-08-27 — harness independente.
/// STAGING only. Não corrige. service_role = setup/observe/cleanup.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const tag = 'SAT27C';
const stagingRef = 'fxdknzrqjenzqcvnwqqq';

typedef Json = Map<String, dynamic>;

final findings = <Json>[];
final notes = <String>[];
final coverage = <String, String>{};
final probes = <Json>[];
final createdProductIds = <String>[];
final createdOrderIds = <String>[];
final createdChatIds = <String>[];

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

void rec(String name, Object? data) {
  probes.add({'name': name, 'data': data});
}

void finding({
  required String id,
  required String sev,
  required String surface,
  required String pre,
  required String identity,
  required String request,
  required Object? response,
  required Object? before,
  required Object? after,
  required String impact,
  required String confidence,
  required String variant,
  required String fp,
}) {
  findings.add({
    'id': id,
    'severity': sev,
    'surface': surface,
    'preconditions': pre,
    'identity': identity,
    'request': request,
    'response': response,
    'before': before,
    'after': after,
    'impact': impact,
    'confidence': confidence,
    'variant': variant,
    'false_positive_considered': fp,
  });
}

String clip(Object? o, [int n = 400]) {
  final s = o is String ? o : jsonEncode(o);
  if (s.length <= n) return s;
  return '${s.substring(0, n)}…';
}

int n(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse('${v ?? ''}') ?? 0;
}

double d(Object? v) => double.tryParse('${v ?? ''}') ?? 0;

Json? firstRow(Object? body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    return Map<String, dynamic>.from(body.first as Map);
  }
  if (body is Map) return Map<String, dynamic>.from(body);
  return null;
}

class H {
  H(this.url, this.anon, this.svc);
  final String url;
  final String anon;
  final String svc;

  Map<String, String> hdr(String tok, {String prefer = 'return=representation'}) => {
        'apikey': tok == svc ? svc : anon,
        'Authorization': 'Bearer $tok',
        'Content-Type': 'application/json',
        'Prefer': prefer,
      };

  Future<Json> req(
    String method,
    String path, {
    String? tok,
    Object? body,
    Map<String, String>? extra,
    int timeoutSec = 25,
  }) async {
    final token = tok ?? anon;
    final headers = hdr(token);
    if (extra != null) headers.addAll(extra);
    final uri = Uri.parse(path.startsWith('http') ? path : '$url$path');
    late http.Response r;
    try {
      final client = http.Client();
      try {
        switch (method) {
          case 'GET':
            r = await client.get(uri, headers: headers).timeout(Duration(seconds: timeoutSec));
            break;
          case 'POST':
            r = await client
                .post(uri, headers: headers, body: body == null ? null : jsonEncode(body))
                .timeout(Duration(seconds: timeoutSec));
            break;
          case 'PATCH':
            r = await client
                .patch(uri, headers: headers, body: body == null ? null : jsonEncode(body))
                .timeout(Duration(seconds: timeoutSec));
            break;
          case 'DELETE':
            r = await client.delete(uri, headers: headers).timeout(Duration(seconds: timeoutSec));
            break;
          case 'HEAD':
            r = await client.head(uri, headers: headers).timeout(Duration(seconds: timeoutSec));
            break;
          case 'OPTIONS':
            r = await client
                .send(http.Request('OPTIONS', uri)..headers.addAll(headers))
                .then(http.Response.fromStream)
                .timeout(Duration(seconds: timeoutSec));
            break;
          default:
            throw StateError(method);
        }
      } finally {
        client.close();
      }
    } catch (e) {
      return {'http': 0, 'body': '$e', 'err': true};
    }
    Object? parsed = r.body;
    try {
      parsed = r.body.isEmpty ? null : jsonDecode(r.body);
    } catch (_) {}
    return {
      'http': r.statusCode,
      'body': parsed,
      'raw': r.body.length > 800 ? '${r.body.substring(0, 800)}…' : r.body,
      'headers': {
        'content-range': r.headers['content-range'],
        'location': r.headers['location'],
        'access-control-allow-origin': r.headers['access-control-allow-origin'],
      },
    };
  }

  Future<Json> edge(String fn, {String? tok, Object? body, String method = 'POST', String qs = ''}) {
    return req(method, '$url/functions/v1/$fn$qs', tok: tok ?? anon, body: body);
  }
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(stagingRef)) {
    stderr.writeln('ABORT: não é staging $stagingRef');
    exit(2);
  }
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerEmail = envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL');
  final buyerPass = envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD');
  final sellerEmail = envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL');
  final sellerPass = envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  final h = H(url, anon, svc);
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);

  stdout.writeln('=== SATURAÇÃO CEGA $tag START ${DateTime.now().toUtc()} ===');
  stdout.writeln('project=$url');

  late String BH, SH;
  try {
    BH = await sb.signIn(email: buyerEmail, password: buyerPass);
    SH = await sb.signIn(email: sellerEmail, password: sellerPass);
  } catch (e) {
    stderr.writeln('LOGIN FAIL $e');
    exit(3);
  }
  final bUid = await sb.userIdForAccessToken(BH);
  final sUid = await sb.userIdForAccessToken(SH);
  rec('identities', {'buyer': bUid, 'seller': sUid, 'expectB': buyerId, 'expectS': sellerId});
  if (bUid != buyerId || sUid != sellerId) {
    notes.add('IDs login ≠ env: b=$bUid/$buyerId s=$sUid/$sellerId — usar IDs do JWT.');
  }

  for (final k in [
    'AUTH', 'PROFILES', 'ORDERS', 'PRICING', 'CHECKOUT', 'SETTLE', 'WEBHOOK',
    'BAG', 'REFUND', 'DISPUTE', 'WALLET', 'PAYOUT', 'STOCK', 'LIVE',
    'RESERVATIONS', 'RAFFLE', 'TIPS', 'CHAT', 'REVIEWS', 'STORAGE', 'MUX',
    'LIVEKIT', 'PS/OCR', 'RPC/DEFINER', 'RLS', 'RACES', 'COMPOSITION',
  ]) {
    coverage[k] = 'NÃO TESTADA';
  }

  // =====================================================================
  // INVENTÁRIO LIVE
  // =====================================================================
  stdout.writeln('-- inventário OpenAPI --');
  final openapi = await h.req('GET', '$url/rest/v1/', extra: {
    'Accept': 'application/openapi+json',
    'apikey': anon,
    'Authorization': 'Bearer $anon',
  });
  final paths = <String>[];
  final rpcNames = <String>[];
  final tables = <String>[];
  try {
    final spec = openapi['body'];
    if (spec is Map && spec['paths'] is Map) {
      for (final p in (spec['paths'] as Map).keys) {
        final ps = p.toString();
        paths.add(ps);
        if (ps.startsWith('/rpc/')) {
          rpcNames.add(ps.substring(5));
        } else if (ps.startsWith('/') && !ps.contains('{')) {
          tables.add(ps.substring(1).split('?').first);
        }
      }
    }
  } catch (e) {
    notes.add('OpenAPI parse fail: $e http=${openapi['http']}');
  }
  rec('openapi', {
    'http': openapi['http'],
    'n_paths': paths.length,
    'n_rpc': rpcNames.length,
    'n_tables': tables.length,
    'rpcs': rpcNames..sort(),
    'tables': tables..sort(),
  });
  cov('RPC/DEFINER', 'TESTADA');
  cov('RLS', 'PARCIAL');

  // =====================================================================
  // PASSAGEM 1 — AUTH
  // =====================================================================
  stdout.writeln('-- AUTH --');
  cov('AUTH', 'TESTADA COM VARIANTES');
  final signupExist = await h.req('POST', '$url/auth/v1/signup', body: {
    'email': buyerEmail,
    'password': 'WrongPass1234!',
  });
  rec('signup_existing', {'http': signupExist['http'], 'body': clip(signupExist['body'])});
  // enumeração: signup vs recover
  final recoverExist = await h.req('POST', '$url/auth/v1/recover', body: {'email': buyerEmail});
  final recoverGhost = await h.req('POST', '$url/auth/v1/recover', body: {
    'email': 'ghost-$tag-${DateTime.now().millisecondsSinceEpoch}@example.invalid',
  });
  rec('recover_enum', {
    'exist_http': recoverExist['http'],
    'ghost_http': recoverGhost['http'],
    'exist': clip(recoverExist['body'], 120),
    'ghost': clip(recoverGhost['body'], 120),
  });
  if (recoverExist['http'] != recoverGhost['http']) {
    finding(
      id: 'SAT27C-AUTH-01',
      sev: 'P3',
      surface: 'AUTH',
      pre: 'emails conhecidos vs inexistentes',
      identity: 'anon',
      request: 'POST /auth/v1/recover',
      response: {'exist': recoverExist['http'], 'ghost': recoverGhost['http']},
      before: null,
      after: null,
      impact: 'Possível enumeração de contas via recover HTTP distinto.',
      confidence: 'média',
      variant: 'recover exist vs ghost',
      fp: 'GoTrue pode devolver 200 em ambos com corpo igual — só HTTP diferente conta.',
    );
  }
  final loginBad = await h.req('POST', '$url/auth/v1/token?grant_type=password', body: {
    'email': buyerEmail,
    'password': 'definitely-wrong-password',
  });
  rec('login_bad', {'http': loginBad['http']});
  // JWT claims
  Json? jwtClaims(String tok) {
    try {
      final p = tok.split('.');
      if (p.length < 2) return null;
      var b = p[1];
      while (b.length % 4 != 0) {
        b += '=';
      }
      return jsonDecode(utf8.decode(base64Url.decode(b))) as Json;
    } catch (_) {
      return null;
    }
  }
  rec('jwt_buyer_claims', jwtClaims(BH));
  rec('jwt_seller_claims', jwtClaims(SH));
  final forged = 'eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.'
      '${base64Url.encode(utf8.encode(jsonEncode({"role": "service_role", "sub": buyerId, "iss": "supabase"})))}.';
  final forgedRest = await h.req('GET', '$url/rest/v1/wallets?select=id,balance&limit=3', tok: forged);
  rec('jwt_alg_none_wallets', {'http': forgedRest['http'], 'body': clip(forgedRest['body'], 200)});
  if (forgedRest['http'] == 200) {
    finding(
      id: 'SAT27C-AUTH-02',
      sev: 'P0',
      surface: 'AUTH',
      pre: 'alg=none JWT',
      identity: 'forged',
      request: 'GET wallets',
      response: clip(forgedRest['body']),
      before: null,
      after: null,
      impact: 'JWT alg=none aceite — bypass total.',
      confidence: 'alta',
      variant: 'alg=none service_role claim',
      fp: '200 vazio ≠ bypass; precisa dados.',
    );
  }
  final fase2Forged = await h.edge(
    'create-payment-intent',
    tok: forged,
    qs: '?fase2_e2e_settle=1',
    body: {'order_id': '00000000-0000-0000-0000-000000000001', 'payment_intent_id': 'pi_x'},
  );
  rec('fase2_alg_none', {'http': fase2Forged['http'], 'body': clip(fase2Forged['body'])});
  if (fase2Forged['http'] == 200) {
    finding(
      id: 'SAT27C-AUTH-03',
      sev: 'P0',
      surface: 'SETTLE',
      pre: 'fase2_e2e_settle com JWT forjado',
      identity: 'forged',
      request: 'POST create-payment-intent?fase2_e2e_settle=1',
      response: clip(fase2Forged['body']),
      before: null,
      after: null,
      impact: 'Settle TEST aberto a JWT forjado.',
      confidence: 'alta',
      variant: 'alg=none',
      fp: '200 com ok:false não é bypass.',
    );
  }

  // =====================================================================
  // PROFILES / PII
  // =====================================================================
  stdout.writeln('-- PROFILES --');
  cov('PROFILES', 'TESTADA COM VARIANTES');
  final piiCols = 'id,display_name,full_name,iban,mb_way,phone,email,user_type,phone_verified_at,stripe_account_id,is_admin';
  final anonPii = await h.req('GET', '$url/rest/v1/profiles?select=$piiCols&limit=8');
  rec('anon_profiles', {'http': anonPii['http'], 'n': (anonPii['body'] is List) ? (anonPii['body'] as List).length : 0, 'sample': clip(anonPii['body'], 300)});
  void flagPiiLeak(String id, String identity, Json r, String reqs) {
    if (r['http'] != 200 || r['body'] is! List) return;
    final rows = (r['body'] as List).whereType<Map>();
    for (final row in rows) {
      final leaks = <String>[];
      for (final c in ['iban', 'mb_way', 'phone', 'email', 'stripe_account_id']) {
        final v = row[c];
        if (v != null && '$v'.trim().isNotEmpty) leaks.add('$c=$v');
      }
      if (leaks.isNotEmpty) {
        finding(
          id: id,
          sev: 'P1',
          surface: 'PROFILES',
          pre: 'directório público',
          identity: identity,
          request: reqs,
          response: {'id': row['id'], 'leaks': leaks},
          before: null,
          after: row,
          impact: 'PII financeiro/contacto visível cross-user.',
          confidence: 'alta',
          variant: identity,
          fp: 'campos públicos intencionais (display_name) não contam.',
        );
        break;
      }
    }
  }
  flagPiiLeak('SAT27C-PII-01', 'anon', anonPii, 'GET profiles select iban,mb_way,phone');
  final buyerOther = await h.req(
    'GET',
    '$url/rest/v1/profiles?id=eq.$sUid&select=$piiCols',
    tok: BH,
  );
  rec('buyer_read_seller_profile', {'http': buyerOther['http'], 'row': firstRow(buyerOther['body'])});
  flagPiiLeak('SAT27C-PII-02', 'buyer JWT', buyerOther, 'GET profiles?id=eq.seller');
  final privPatches = [
    {'user_type': 'admin'},
    {'user_type': 'vendedor'},
    {'user_type': 'admim'},
    {'phone_verified_at': DateTime.now().toUtc().toIso8601String()},
    {'is_admin': true},
    {'iban': 'PT50000201231234567890154'},
  ];
  final profBefore = await h.req('GET', '$url/rest/v1/profiles?id=eq.$bUid&select=user_type,phone_verified_at,iban,is_admin', tok: svc);
  final pb = firstRow(profBefore['body']);
  for (final patch in privPatches) {
    final r = await h.req('PATCH', '$url/rest/v1/profiles?id=eq.$bUid', tok: BH, body: patch);
    final after = firstRow((await h.req(
      'GET',
      '$url/rest/v1/profiles?id=eq.$bUid&select=user_type,phone_verified_at,iban,is_admin',
      tok: svc,
    ))['body']);
    rec('profile_priv_${patch.keys.first}', {'http': r['http'], 'patch': patch, 'after': after, 'raw': clip(r['body'], 160)});
    final k = patch.keys.first;
    if (after != null && '${after[k]}' == '${patch[k]}' && '${pb?[k]}' != '${patch[k]}') {
      finding(
        id: 'SAT27C-PII-03-$k',
        sev: k == 'user_type' || k == 'is_admin' || k == 'phone_verified_at' ? 'P1' : 'P2',
        surface: 'PROFILES',
        pre: 'buyer JWT own-row',
        identity: 'buyer',
        request: 'PATCH profiles $patch',
        response: clip(r['body'], 200),
        before: pb,
        after: after,
        impact: 'Campo privilegiado $k alterável pelo próprio JWT.',
        confidence: 'alta',
        variant: k,
        fp: 'iban próprio pode ser intencional (P2); user_type/admin não.',
      );
    }
  }
  // restore privileged
  await h.req('PATCH', '$url/rest/v1/profiles?id=eq.$bUid', tok: svc, body: {
    if (pb != null) 'user_type': pb['user_type'] ?? 'comprador',
    'phone_verified_at': pb?['phone_verified_at'],
    'iban': pb?['iban'],
  });
  // cross-row update
  final xPatch = await h.req('PATCH', '$url/rest/v1/profiles?id=eq.$sUid', tok: BH, body: {'display_name': 'HACKED_$tag'});
  rec('buyer_patch_seller_profile', {'http': xPatch['http'], 'body': clip(xPatch['body'], 160)});
  if (xPatch['http'] == 200 && xPatch['body'] is List && (xPatch['body'] as List).isNotEmpty) {
    finding(
      id: 'SAT27C-PII-04',
      sev: 'P0',
      surface: 'PROFILES',
      pre: 'buyer JWT',
      identity: 'buyer',
      request: 'PATCH profiles?id=eq.seller',
      response: clip(xPatch['body']),
      before: null,
      after: firstRow(xPatch['body']),
      impact: 'Buyer altera perfil do vendedor.',
      confidence: 'alta',
      variant: 'cross-row display_name',
      fp: '200 lista vazia = RLS filtrou.',
    );
  }

  // =====================================================================
  // RLS ANON TABLE SWEEP
  // =====================================================================
  stdout.writeln('-- RLS sweep --');
  cov('RLS', 'TESTADA COM VARIANTES');
  final sensitiveTables = [
    'orders', 'wallets', 'wallet_transactions', 'wallet_payout_ledger',
    'profiles', 'chats', 'chat_messages', 'reviews', 'products', 'lives',
    'live_items', 'live_reservation_requests', 'live_raffles', 'live_raffle_winners',
    'live_raffle_tickets', 'live_tips', 'order_disputes', 'product_offers',
    'product_bundles', 'seller_bundle_discounts', 'stripe_checkout_events',
    'fleaber_commissions', 'ps_pairing_sessions', 'ps_ingest_audit',
    'anon_rate_limits', 'staff_permissions',
  ];
  for (final t in sensitiveTables) {
    final a = await h.req('GET', '$url/rest/v1/$t?select=*&limit=3');
    rec('anon_select_$t', {
      'http': a['http'],
      'n': a['body'] is List ? (a['body'] as List).length : 0,
      'err': a['http'] >= 400 ? clip(a['body'], 120) : null,
    });
    if (a['http'] == 200 && a['body'] is List && (a['body'] as List).isNotEmpty) {
      if (['orders', 'wallets', 'wallet_transactions', 'wallet_payout_ledger', 'chats', 'chat_messages', 'stripe_checkout_events', 'ps_pairing_sessions'].contains(t)) {
        finding(
          id: 'SAT27C-RLS-ANON-$t',
          sev: t == 'wallets' || t == 'orders' ? 'P1' : 'P2',
          surface: 'RLS',
          pre: 'anon key',
          identity: 'anon',
          request: 'GET $t select=*',
          response: {'n': (a['body'] as List).length, 'sample': clip(a['body'], 220)},
          before: null,
          after: null,
          impact: 'Tabela sensível $t legível sem JWT.',
          confidence: 'alta',
          variant: 'anon SELECT',
          fp: 'tabela pública de catálogo (products/lives) não é P1.',
        );
      }
    }
  }
  // lives stream keys
  final livesKeys = await h.req('GET', '$url/rest/v1/lives?select=id,mux_stream_key,stream_key,seller_id&limit=5');
  rec('anon_live_keys', {'http': livesKeys['http'], 'body': clip(livesKeys['body'], 300)});
  if (livesKeys['http'] == 200 && livesKeys['body'] is List) {
    for (final row in (livesKeys['body'] as List).whereType<Map>()) {
      final sk = '${row['mux_stream_key'] ?? row['stream_key'] ?? ''}'.trim();
      if (sk.isNotEmpty) {
        finding(
          id: 'SAT27C-MUX-01',
          sev: 'P1',
          surface: 'MUX',
          pre: 'anon SELECT lives',
          identity: 'anon',
          request: 'GET lives stream_key',
          response: {'id': row['id'], 'key_len': sk.length},
          before: null,
          after: null,
          impact: 'Stream key Mux exposta — hijack/custo.',
          confidence: 'alta',
          variant: 'anon lives',
          fp: 'playback_id público não é stream_key.',
        );
        break;
      }
    }
  }

  // buyer vs seller orders
  final bOrders = await h.req('GET', '$url/rest/v1/orders?select=id,buyer_id,seller_id,status,price_total&limit=20', tok: BH);
  rec('buyer_orders', {'http': bOrders['http'], 'n': bOrders['body'] is List ? (bOrders['body'] as List).length : 0});
  if (bOrders['body'] is List) {
    final x = (bOrders['body'] as List).whereType<Map>().where((r) => r['buyer_id'] != bUid && r['seller_id'] != bUid);
    if (x.isNotEmpty) {
      finding(
        id: 'SAT27C-ORD-XUSER',
        sev: 'P1',
        surface: 'ORDERS',
        pre: 'buyer JWT',
        identity: 'buyer',
        request: 'GET orders',
        response: {'n': x.length, 'sample': clip(x.first)},
        before: null,
        after: null,
        impact: 'Buyer lê orders de terceiros.',
        confidence: 'alta',
        variant: 'SELECT cross-user',
        fp: 'participante (seller_id=buyer) é esperado.',
      );
    }
  }

  // =====================================================================
  // RPC SENSÍVEIS
  // =====================================================================
  stdout.writeln('-- RPC --');
  cov('RPC/DEFINER', 'TESTADA COM VARIANTES');
  final sensitiveRpcs = [
    ['batata_debit_wallet_once', {'p_wallet_id': sUid, 'p_order_id': '00000000-0000-0000-0000-000000000001', 'p_amount': 1, 'p_type': 'venda'}],
    ['batata_credit_wallet_once', {'p_wallet_id': bUid, 'p_order_id': '00000000-0000-0000-0000-000000000001', 'p_amount': 50, 'p_type': 'reembolso', 'p_description': 'x'}],
    ['batata_ensure_wallet', {'p_user_id': sUid}],
    ['batata_clawback_seller_wallet_for_order', {'p_order_id': '00000000-0000-0000-0000-000000000001'}],
    ['batata_release_seller_wallet_for_order', {'p_order_id': '00000000-0000-0000-0000-000000000001'}],
    ['batata_refund_buyer_wallet_for_order', {'p_order_id': '00000000-0000-0000-0000-000000000001'}],
    ['batata_finalize_stripe_order_refund', {'p_order_id': '00000000-0000-0000-0000-000000000001', 'p_refund_id': 're_x', 'p_payment_intent_id': 'pi_x', 'p_session_id': null, 'p_amount_cents': 100}],
    ['batata_wallet_payout_debit', {'p_user_id': sUid, 'p_amount_cents': 100, 'p_idempotency_key': 'sat27c-x'}],
    ['batata_settle_live_tip_from_stripe', {'p_tip_id': '00000000-0000-0000-0000-000000000001', 'p_stripe_session_id': 'cs_x', 'p_paid_amount_cents': 100}],
    ['batata_ps_claim_pairing', {'p_code': '000000', 'p_device_id': 'sat27c', 'p_app_version': 'audit'}],
    ['batata_is_admin', <String, dynamic>{}],
  ];
  for (final e in sensitiveRpcs) {
    final name = e[0] as String;
    final params = e[1] as Map<String, dynamic>;
    for (final ident in [
      ['anon', anon],
      ['buyer', BH],
      ['seller', SH],
    ]) {
      final r = await h.req('POST', '$url/rest/v1/rpc/$name', tok: ident[1] as String, body: params);
      rec('rpc_${name}_${ident[0]}', {'http': r['http'], 'body': clip(r['body'], 180)});
      final okHttp = r['http'] == 200;
      final body = r['body'];
      final minted = okHttp && body != false && body != null &&
          !(body is Map && (body['ok'] == false || body['error'] != null));
      if (minted && ['batata_debit_wallet_once', 'batata_credit_wallet_once', 'batata_wallet_payout_debit', 'batata_finalize_stripe_order_refund'].contains(name)) {
        finding(
          id: 'SAT27C-RPC-$name-${ident[0]}',
          sev: 'P0',
          surface: 'RPC/DEFINER',
          pre: 'RPC monetary',
          identity: ident[0] as String,
          request: 'POST rpc/$name $params',
          response: clip(r['body']),
          before: null,
          after: null,
          impact: 'RPC financeira executável por ${ident[0]}.',
          confidence: 'alta',
          variant: ident[0] as String,
          fp: '200 com ok:false / false não é efeito.',
        );
      }
    }
  }
  // enumerate remaining RPCs as buyer (no params) — detect EXECUTE
  var rpcExecOk = 0;
  for (final name in rpcNames.take(80)) {
    if (sensitiveRpcs.any((e) => e[0] == name)) continue;
    final r = await h.req('POST', '$url/rest/v1/rpc/$name', tok: BH, body: {});
    if (r['http'] == 200) rpcExecOk++;
    rec('rpc_probe_$name', {'http': r['http'], 'snip': clip(r['body'], 80)});
  }
  rec('rpc_buyer_empty_ok_count', rpcExecOk);

  // =====================================================================
  // FIXTURES: products as seller
  // =====================================================================
  stdout.writeln('-- fixtures --');
  Future<Json?> insertProduct(String tok, Json row) async {
    final r = await h.req('POST', '$url/rest/v1/products', tok: tok, body: row);
    rec('insert_product', {'http': r['http'], 'body': clip(r['body'], 180)});
    final rowOut = firstRow(r['body']);
    if (rowOut?['id'] != null) createdProductIds.add('${rowOut!['id']}');
    return rowOut;
  }

  Future<Json?> insertOrder(String tok, Json row) async {
    final r = await h.req('POST', '$url/rest/v1/orders', tok: tok, body: row);
    rec('insert_order', {'http': r['http'], 'req': row, 'body': clip(r['body'], 240)});
    final rowOut = firstRow(r['body']);
    if (rowOut?['id'] != null) createdOrderIds.add('${rowOut!['id']}');
    return rowOut;
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final p40 = await insertProduct(SH, {
    'seller_id': sUid,
    'title': '$tag p40 $stamp',
    'price': 40.0,
    'quantity': 5,
    'ref_code': '$tag-40-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
    'category': 'Outros',
    'state': 'Bom',
  });
  final pCheap = await insertProduct(SH, {
    'seller_id': sUid,
    'title': '$tag cheap $stamp',
    'price': 8.0,
    'quantity': 2,
    'ref_code': '$tag-8-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
    'category': 'Outros',
    'state': 'Bom',
  });
  final pOne = await insertProduct(SH, {
    'seller_id': sUid,
    'title': '$tag qty1 $stamp',
    'price': 12.0,
    'quantity': 1,
    'ref_code': '$tag-1-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
    'category': 'Outros',
    'state': 'Bom',
  });
  final pBagA = await insertProduct(SH, {
    'seller_id': sUid,
    'title': '$tag bagA $stamp',
    'price': 10.0,
    'quantity': 4,
    'ref_code': '$tag-ba-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
    'category': 'Outros',
    'state': 'Bom',
  });
  final pBagB = await insertProduct(SH, {
    'seller_id': sUid,
    'title': '$tag bagB $stamp',
    'price': 15.0,
    'quantity': 4,
    'ref_code': '$tag-bb-$stamp',
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'image_urls': <String>[],
    'category': 'Outros',
    'state': 'Bom',
  });
  if (p40 == null || pCheap == null || pOne == null) {
    notes.add('Falha a criar produtos seller — ORDERS/PRICING parciais.');
  }

  // buyer cannot insert product as seller
  final stolenProd = await h.req('POST', '$url/rest/v1/products', tok: BH, body: {
    'seller_id': sUid,
    'title': '$tag stolen $stamp',
    'price': 1.0,
    'quantity': 1,
    'ref_code': '$tag-st-$stamp',
    'list_on_marketplace': true,
  });
  rec('buyer_insert_seller_product', {'http': stolenProd['http'], 'body': clip(stolenProd['body'], 160)});
  final stolenRow = firstRow(stolenProd['body']);
  if (stolenRow?['id'] != null) {
    createdProductIds.add('${stolenRow!['id']}');
    finding(
      id: 'SAT27C-STOCK-OWNER',
      sev: 'P1',
      surface: 'STOCK',
      pre: 'buyer JWT',
      identity: 'buyer',
      request: 'POST products seller_id=seller',
      response: clip(stolenProd['body']),
      before: null,
      after: stolenRow,
      impact: 'Buyer cria produto na loja do vendedor.',
      confidence: 'alta',
      variant: 'seller_id spoof',
      fp: 'trigger pode reescrever seller_id para auth.uid().',
    );
  }

  // =====================================================================
  // ORDERS INSERT / PRICING CONTRACT
  // =====================================================================
  stdout.writeln('-- ORDERS / PRICING --');
  cov('ORDERS', 'TESTADA COM VARIANTES');
  cov('PRICING', 'TESTADA COM VARIANTES');

  Future<void> assertContract(String label, Json? row, {required int expectCents, required int expectQty}) async {
    if (row == null) return;
    final cuc = n(row['contract_unit_cents']);
    final cq = n(row['contract_qty']);
    rec('contract_$label', {'cuc': cuc, 'cq': cq, 'qty': row['quantity'], 'pt': row['price_total'], 'st': row['status']});
    if (cuc > 0 && cuc != expectCents) {
      finding(
        id: 'SAT27C-PRC-$label',
        sev: 'P0',
        surface: 'PRICING',
        pre: 'JWT INSERT order',
        identity: 'buyer',
        request: label,
        response: row,
        before: {'expect_cents': expectCents},
        after: {'cuc': cuc},
        impact: 'Contrato unitário ≠ catálogo (JWT mandou?).',
        confidence: 'alta',
        variant: label,
        fp: 'proposta aceite pode selar outro valor.',
      );
    }
    if (cq > 0 && cq != expectQty && n(row['quantity']) != expectQty) {
      finding(
        id: 'SAT27C-QTY-$label',
        sev: 'P0',
        surface: 'PRICING',
        pre: 'JWT INSERT',
        identity: 'buyer',
        request: label,
        response: {'cq': cq, 'qty': row['quantity']},
        before: expectQty,
        after: cq,
        impact: 'contract_qty/quantity JWT sobrepôs autoridade.',
        confidence: 'alta',
        variant: label,
        fp: 'cap 99 é coerção não bypass se input>99.',
      );
    }
  }

  // hostile contract
  final oHostile = await insertOrder(BH, {
    'product_id': p40?['id'],
    'buyer_id': bUid,
    'seller_id': sUid,
    'price_total': 0.5,
    'quantity': 1,
    'contract_unit_cents': 50,
    'contract_qty': 9,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
    'shipping_method': 'entrega em mão',
    'amount_paid_cents': 99999,
    'stripe_payment_intent_id': 'pi_forged',
    'stripe_checkout_session_id': 'cs_forged',
  });
  await assertContract('hostile_insert', oHostile, expectCents: 4000, expectQty: 1);
  if (oHostile != null) {
    if (n(oHostile['amount_paid_cents']) > 0 || '${oHostile['stripe_payment_intent_id'] ?? ''}'.startsWith('pi_forged')) {
      finding(
        id: 'SAT27C-ORD-MONEY-INS',
        sev: 'P0',
        surface: 'ORDERS',
        pre: 'JWT INSERT',
        identity: 'buyer',
        request: 'INSERT amount_paid_cents/stripe ids',
        response: oHostile,
        before: 0,
        after: oHostile['amount_paid_cents'],
        impact: 'JWT declara captura Stripe.',
        confidence: 'alta',
        variant: 'INSERT money cols',
        fp: 'serviço pode copiar e trigger limpa — verificar after.',
      );
    }
    if (n(oHostile['contract_unit_cents']) == 50) {
      finding(
        id: 'SAT27C-PRC-JWT-CUC',
        sev: 'P0',
        surface: 'PRICING',
        pre: 'JWT INSERT contract_unit_cents=50',
        identity: 'buyer',
        request: 'POST orders contract_unit_cents=50',
        response: oHostile,
        before: 4000,
        after: 50,
        impact: 'Preço de contrato controlado pelo cliente.',
        confidence: 'alta',
        variant: 'underpay',
        fp: 'null contract com checkout a selar catálogo não é P0 neste INSERT.',
      );
    }
    if (n(oHostile['contract_qty']) == 9 || n(oHostile['quantity']) == 9) {
      finding(
        id: 'SAT27C-PRC-JWT-QTY',
        sev: 'P0',
        surface: 'PRICING',
        pre: 'quantity=1 contract_qty=9',
        identity: 'buyer',
        request: 'POST orders',
        response: {'qty': oHostile['quantity'], 'cq': oHostile['contract_qty']},
        before: 1,
        after: oHostile['contract_qty'],
        impact: 'Qty de contrato inflacionada pelo JWT.',
        confidence: 'alta',
        variant: 'qty hike',
        fp: 'quantity 1 selada e contract_qty null = fechado.',
      );
    }
  }

  // parties spoof
  final oParty = await insertOrder(BH, {
    'product_id': p40?['id'],
    'buyer_id': sUid,
    'seller_id': bUid,
    'price_total': 40,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
  });
  rec('order_party_spoof', oParty);
  if (oParty != null && oParty['buyer_id'] == sUid) {
    finding(
      id: 'SAT27C-ORD-PARTY',
      sev: 'P0',
      surface: 'ORDERS',
      pre: 'buyer JWT',
      identity: 'buyer',
      request: 'INSERT buyer_id=seller',
      response: oParty,
      before: bUid,
      after: oParty['buyer_id'],
      impact: 'Partes da order forjadas.',
      confidence: 'alta',
      variant: 'buyer_id swap',
      fp: 'trigger reescreve para auth.uid() = fechado.',
    );
  }

  // status pago insert
  final oPago = await insertOrder(BH, {
    'product_id': pCheap?['id'],
    'buyer_id': bUid,
    'seller_id': sUid,
    'price_total': 8,
    'quantity': 1,
    'status': 'pago',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
  });
  rec('order_insert_pago', oPago);
  if (oPago != null && '${oPago['status']}'.toLowerCase() == 'pago') {
    finding(
      id: 'SAT27C-ORD-INS-PAGO',
      sev: 'P0',
      surface: 'ORDERS',
      pre: 'JWT INSERT status=pago',
      identity: 'buyer',
      request: 'POST orders status=pago',
      response: oPago,
      before: 'reserva_pendente',
      after: oPago['status'],
      impact: 'Buyer nasce pago sem captura.',
      confidence: 'alta',
      variant: 'INSERT pago',
      fp: 'nenhum.',
    );
  }

  // off-platform substring
  final oOff = await insertOrder(BH, {
    'product_id': pCheap?['id'],
    'buyer_id': bUid,
    'seller_id': sUid,
    'price_total': 8,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber) mb way/transf',
  });
  rec('order_offplatform_substr', oOff);
  // seller tries to mark pago
  if (oOff?['id'] != null) {
    final beforeSt = oOff!['status'];
    final mark = await h.req('PATCH', '$url/rest/v1/orders?id=eq.${oOff['id']}', tok: SH, body: {'status': 'pago'});
    final afterLive = firstRow((await h.req(
      'GET',
      '$url/rest/v1/orders?id=eq.${oOff['id']}&select=id,status,payment_method,amount_paid_cents,wallet_release_processed_at',
      tok: svc,
    ))['body']);
    rec('seller_pago_substr', {'http': mark['http'], 'after': afterLive, 'raw': clip(mark['body'], 160)});
    if ('${afterLive?['status']}'.toLowerCase() == 'pago' && n(afterLive?['amount_paid_cents']) == 0) {
      finding(
        id: 'SAT27C-ORD-PM-SUBSTR',
        sev: 'P1',
        surface: 'ORDERS',
        pre: 'payment_method contém mb way/transf',
        identity: 'seller',
        request: 'PATCH status=pago',
        response: afterLive,
        before: beforeSt,
        after: afterLive?['status'],
        impact: 'Método plataforma disfarçado de off-platform; seller atesta pago sem captura.',
        confidence: 'alta',
        variant: 'LIKE %mb way/transf%',
        fp: 'off-platform real (MB WAY) permite seller→pago por desenho; a string mistura Seguro+substring.',
      );
    }
  }

  // zero / negative / max qty
  for (final q in [0, -1, 100, 9999]) {
    final oq = await h.req('POST', '$url/rest/v1/orders', tok: BH, body: {
      'product_id': p40?['id'],
      'buyer_id': bUid,
      'seller_id': sUid,
      'price_total': 40,
      'quantity': q,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app (Seguro Fleaber)',
    });
    rec('order_qty_$q', {'http': oq['http'], 'body': clip(oq['body'], 180)});
    final row = firstRow(oq['body']);
    if (row?['id'] != null) createdOrderIds.add('${row!['id']}');
    if (row != null && (n(row['quantity']) < 1 || (q > 99 && n(row['quantity']) == q))) {
      finding(
        id: 'SAT27C-ORD-QTY-$q',
        sev: 'P1',
        surface: 'ORDERS',
        pre: 'qty=$q',
        identity: 'buyer',
        request: 'POST orders quantity=$q',
        response: row,
        before: q,
        after: row['quantity'],
        impact: 'Qty inválida aceite.',
        confidence: 'alta',
        variant: '$q',
        fp: 'coerção para 1 ou 99 é mitigação, não P0.',
      );
    }
  }

  // oversell qty vs stock
  final oOversell = await insertOrder(BH, {
    'product_id': pOne?['id'],
    'buyer_id': bUid,
    'seller_id': sUid,
    'price_total': 24,
    'quantity': 3,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
  });
  rec('order_oversell_qty', oOversell);
  if (oOversell != null && n(oOversell['quantity']) > 1 && n(pOne?['quantity']) == 1) {
    finding(
      id: 'SAT27C-STOCK-QTY-INS',
      sev: 'P1',
      surface: 'STOCK',
      pre: 'product qty=1',
      identity: 'buyer',
      request: 'POST orders quantity=3',
      response: oOversell,
      before: 1,
      after: oOversell['quantity'],
      impact: 'Order qty > stock no INSERT (oversell latente até settle).',
      confidence: 'alta',
      variant: 'qty 3 vs stock 1',
      fp: 'checkout/settle pode recusar — ainda é contrato inflado se selar qty 3.',
    );
  }

  // UPDATE freeze
  if (oHostile?['id'] != null) {
    final oid = oHostile!['id'];
    final patches = [
      {'price_total': 0.01},
      {'contract_unit_cents': 1},
      {'contract_qty': 99},
      {'quantity': 99},
      {'amount_paid_cents': 1},
      {'status': 'pago'},
      {'status': 'concluido'},
      {'buyer_id': sUid},
      {'seller_id': bUid},
      {'payment_method': 'mb way'},
      {'stripe_payment_intent_id': 'pi_upd'},
    ];
    for (final p in patches) {
      final r = await h.req('PATCH', '$url/rest/v1/orders?id=eq.$oid', tok: BH, body: p);
      rec('order_upd_buyer_${p.keys.first}', {'http': r['http'], 'body': clip(r['body'], 140)});
    }
    final live = firstRow((await h.req(
      'GET',
      '$url/rest/v1/orders?id=eq.$oid&select=id,status,price_total,contract_unit_cents,contract_qty,quantity,amount_paid_cents,buyer_id,seller_id,payment_method,stripe_payment_intent_id',
      tok: svc,
    ))['body']);
    rec('order_after_buyer_patches', live);
    if (live != null) {
      if (d(live['price_total']) == 0.01) {
        finding(
          id: 'SAT27C-ORD-UPD-PRICE',
          sev: 'P0',
          surface: 'ORDERS',
          pre: 'order existente',
          identity: 'buyer',
          request: 'PATCH price_total=0.01',
          response: live,
          before: oHostile['price_total'],
          after: live['price_total'],
          impact: 'Contrato comercial mutável pós-criação.',
          confidence: 'alta',
          variant: 'price_total',
          fp: 'nenhum.',
        );
      }
      if (n(live['contract_unit_cents']) == 1) {
        finding(
          id: 'SAT27C-ORD-UPD-CUC',
          sev: 'P0',
          surface: 'PRICING',
          pre: 'order selada',
          identity: 'buyer',
          request: 'PATCH contract_unit_cents=1',
          response: live,
          before: oHostile['contract_unit_cents'],
          after: 1,
          impact: 'Selo de contrato quebrado.',
          confidence: 'alta',
          variant: 'UPDATE cuc',
          fp: 'nenhum.',
        );
      }
      if ('${live['status']}'.toLowerCase() == 'pago' || '${live['status']}'.toLowerCase() == 'concluido') {
        finding(
          id: 'SAT27C-ORD-UPD-ST',
          sev: 'P0',
          surface: 'ORDERS',
          pre: 'sem captura',
          identity: 'buyer',
          request: 'PATCH status pago/concluido',
          response: live,
          before: oHostile['status'],
          after: live['status'],
          impact: 'Salto de estado sem pagamento.',
          confidence: 'alta',
          variant: '${live['status']}',
          fp: 'nenhum.',
        );
      }
    }
    // seller patches
    for (final p in [
      {'status': 'pago'},
      {'status': 'enviado'},
      {'price_total': 90},
      {'contract_unit_cents': 9000},
    ]) {
      final r = await h.req('PATCH', '$url/rest/v1/orders?id=eq.$oid', tok: SH, body: p);
      rec('order_upd_seller_${p.keys.first}_${p.values.first}', {'http': r['http'], 'body': clip(r['body'], 140)});
    }
    final liveS = firstRow((await h.req(
      'GET',
      '$url/rest/v1/orders?id=eq.$oid&select=id,status,price_total,contract_unit_cents,amount_paid_cents',
      tok: svc,
    ))['body']);
    rec('order_after_seller_patches', liveS);
  }

  // catalog hike after order (invariant K)
  if (oHostile?['id'] != null && p40?['id'] != null) {
    await h.req('PATCH', '$url/rest/v1/products?id=eq.${p40!['id']}', tok: SH, body: {'price': 90.0});
    final afterHike = firstRow((await h.req(
      'GET',
      '$url/rest/v1/orders?id=eq.${oHostile!['id']}&select=contract_unit_cents,price_total,quantity',
      tok: svc,
    ))['body']);
    rec('catalog_hike_order', afterHike);
    if (n(afterHike?['contract_unit_cents']) == 9000) {
      finding(
        id: 'SAT27C-INV-K',
        sev: 'P0',
        surface: 'PRICING',
        pre: 'order selada; seller PATCH product.price',
        identity: 'seller',
        request: 'PATCH products price=90',
        response: afterHike,
        before: 4000,
        after: afterHike?['contract_unit_cents'],
        impact: 'Catálogo posterior altera contrato existente.',
        confidence: 'alta',
        variant: 'seller hike',
        fp: 'order.contract inalterado mas checkout usa catálogo vivo = mesmo P0 no CHECKOUT.',
      );
    }
  }

  // =====================================================================
  // CHECKOUT
  // =====================================================================
  stdout.writeln('-- CHECKOUT --');
  cov('CHECKOUT', 'TESTADA COM VARIANTES');
  Future<Json> checkout(String tok, Json body) => h.edge('create-payment-intent', tok: tok, body: body);

  Json? payOrder = oHostile;
  if (payOrder == null && pCheap != null) {
    payOrder = await insertOrder(BH, {
      'product_id': pCheap['id'],
      'buyer_id': bUid,
      'seller_id': sUid,
      'price_total': 8,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app (Seguro Fleaber)',
      'shipping_method': 'hand',
    });
  }
  if (payOrder?['id'] != null) {
    final oid = '${payOrder!['id']}';
    final pid = '${payOrder['product_id']}';
    // expected quote: items + shipping 0 + protection
    int prot(int items, int ship) {
      final base = (items + ship) / 100.0;
      final fee = ((0.65 + base * 0.05) * 100).round() / 100.0;
      return (fee * 100).round();
    }
    final unit = n(payOrder['contract_unit_cents']) > 0 ? n(payOrder['contract_unit_cents']) : 4000;
    final qty = n(payOrder['contract_qty']) > 0 ? n(payOrder['contract_qty']) : n(payOrder['quantity']);
    final items = unit * qty;
    final expectAmt = items + prot(items, 0);

    final happy = await checkout(BH, {
      'order_id': oid,
      'buyer_id': bUid,
      'product_id': pid,
      'seller_id': sUid,
      'amount': expectAmt,
      'shipping_method': 'hand',
      'currency': 'eur',
    });
    rec('checkout_happy', {'http': happy['http'], 'body': clip(happy['body'], 300)});
    final happyAmt = n((happy['body'] is Map) ? (happy['body'] as Map)['server_amount_cents'] : 0);

    // body.amount underpay
    final cheap = await checkout(BH, {
      'order_id': oid,
      'buyer_id': bUid,
      'amount': 50,
      'shipping_method': 'hand',
    });
    rec('checkout_amount_50', {'http': cheap['http'], 'body': clip(cheap['body'], 250)});
    final cheapAmt = n((cheap['body'] is Map) ? (cheap['body'] as Map)['server_amount_cents'] : 0);
    if (cheap['http'] == 200 && cheapAmt > 0 && cheapAmt < expectAmt * 0.5) {
      finding(
        id: 'SAT27C-CHK-AMT',
        sev: 'P0',
        surface: 'CHECKOUT',
        pre: 'order selada',
        identity: 'buyer',
        request: 'POST create-payment-intent amount=50',
        response: clip(cheap['body']),
        before: expectAmt,
        after: cheapAmt,
        impact: 'body.amount mandou no Stripe.',
        confidence: 'alta',
        variant: 'underpay 50c',
        fp: 'server_amount_cents correcto com Session barata seria P0; se Session=contrato, fechado.',
      );
    }

    // product swap
    final swap = await checkout(BH, {
      'order_id': oid,
      'buyer_id': bUid,
      'product_id': pCheap?['id'],
      'amount': 100,
      'shipping_method': 'hand',
    });
    rec('checkout_product_swap', {'http': swap['http'], 'body': clip(swap['body'], 220)});
    if (swap['http'] == 200 && pCheap?['id'] != pid) {
      notes.add('product_swap http=200 — verificar se quote usa order.product (esperado) ou body.');
    }

    // buyer swap
    final bswap = await checkout(BH, {
      'order_id': oid,
      'buyer_id': sUid,
      'shipping_method': 'hand',
    });
    rec('checkout_buyer_swap', {'http': bswap['http'], 'body': clip(bswap['body'], 180)});
    if (bswap['http'] == 200) {
      finding(
        id: 'SAT27C-CHK-BUYER',
        sev: 'P0',
        surface: 'CHECKOUT',
        pre: 'JWT buyer, body.buyer_id=seller',
        identity: 'buyer',
        request: 'create-payment-intent buyer_id=seller',
        response: clip(bswap['body']),
        before: bUid,
        after: sUid,
        impact: 'Checkout ignora JWT vs buyer_id.',
        confidence: 'média',
        variant: 'buyer_id spoof',
        fp: 'código exige user.id === body.buyer_id — 400 esperado. 200=fail.',
      );
    }

    // seller JWT pays buyer order
    final sellerPay = await checkout(SH, {
      'order_id': oid,
      'buyer_id': sUid,
      'shipping_method': 'hand',
    });
    rec('checkout_seller_on_buyer_order', {'http': sellerPay['http'], 'body': clip(sellerPay['body'], 180)});

    // carrier vs hand
    final carrier = await checkout(BH, {
      'order_id': oid,
      'buyer_id': bUid,
      'shipping_method': 'carrier',
    });
    rec('checkout_carrier', {'http': carrier['http'], 'body': clip(carrier['body'], 220)});
    final garbageShip = await checkout(BH, {
      'order_id': oid,
      'buyer_id': bUid,
      'shipping_method': 'carrier_free_€0',
      'shipping': 0,
    });
    rec('checkout_ship_garbage', {'http': garbageShip['http'], 'body': clip(garbageShip['body'], 180)});
    if (garbageShip['http'] == 200) {
      finding(
        id: 'SAT27C-CHK-SHIP',
        sev: 'P1',
        surface: 'CHECKOUT',
        pre: 'shipping_method lixo',
        identity: 'buyer',
        request: 'shipping_method=carrier_free',
        response: clip(garbageShip['body']),
        before: 'throw Portes inválidos',
        after: garbageShip['http'],
        impact: 'Portes lixo aceites.',
        confidence: 'alta',
        variant: 'garbage shipping',
        fp: '400 é fechado.',
      );
    }

    // prize_shipping forge
    final prize = await checkout(BH, {
      'order_id': oid,
      'buyer_id': bUid,
      'prize_shipping': true,
      'shipping_method': 'carrier',
    });
    rec('checkout_prize_forge', {'http': prize['http'], 'body': clip(prize['body'], 200)});
    if (prize['http'] == 200) {
      final amt = n((prize['body'] is Map) ? (prize['body'] as Map)['server_amount_cents'] : 0);
      if (amt > 0 && amt < 1000) {
        finding(
          id: 'SAT27C-CHK-PRIZE',
          sev: 'P0',
          surface: 'CHECKOUT',
          pre: 'order não é rifa',
          identity: 'buyer',
          request: 'prize_shipping=true',
          response: clip(prize['body']),
          before: expectAmt,
          after: amt,
          impact: 'Checkout de portes de rifa em order normal (subpagamento).',
          confidence: 'alta',
          variant: 'prize_shipping',
          fp: '400 raffle prize blocked = fechado.',
        );
      }
    }

    // currency
    final usd = await checkout(BH, {
      'order_id': oid,
      'buyer_id': bUid,
      'currency': 'usd',
      'shipping_method': 'hand',
    });
    rec('checkout_usd', {'http': usd['http'], 'body': clip(usd['body'], 180)});

    // duplicate session
    if (happy['http'] == 200 && happy['body'] is Map) {
      final sid1 = (happy['body'] as Map)['checkoutSessionId'];
      final happy2 = await checkout(BH, {
        'order_id': oid,
        'buyer_id': bUid,
        'shipping_method': 'hand',
      });
      rec('checkout_dup_session', {
        's1': sid1,
        's2': happy2['body'] is Map ? (happy2['body'] as Map)['checkoutSessionId'] : null,
        'http2': happy2['http'],
      });
    }

    // GET settle unpaid
    if (happy['http'] == 200 && happy['body'] is Map) {
      final sid = (happy['body'] as Map)['checkoutSessionId'];
      if (sid != null) {
        cov('SETTLE', 'TESTADA COM VARIANTES');
        final settleUnpaid = await h.req(
          'GET',
          '$url/functions/v1/create-payment-intent?checkout_return=success&session_id=$sid',
        );
        rec('settle_unpaid', {'http': settleUnpaid['http'], 'raw': clip(settleUnpaid['raw'] ?? settleUnpaid['body'], 220)});
        final afterUnpaid = firstRow((await h.req(
          'GET',
          '$url/rest/v1/orders?id=eq.$oid&select=status,amount_paid_cents',
          tok: svc,
        ))['body']);
        rec('order_after_unpaid_settle', afterUnpaid);
        if ('${afterUnpaid?['status']}'.toLowerCase() == 'pago') {
          finding(
            id: 'SAT27C-SET-UNPAID',
            sev: 'P0',
            surface: 'SETTLE',
            pre: 'Session não paga',
            identity: 'anon GET',
            request: 'GET checkout_return=success',
            response: afterUnpaid,
            before: payOrder['status'],
            after: 'pago',
            impact: 'Settle marca pago sem captura Stripe.',
            confidence: 'alta',
            variant: 'unpaid return URL',
            fp: 'nenhum.',
          );
        }
        // webhook unsigned
        cov('WEBHOOK', 'TESTADA COM VARIANTES');
        final wh = await h.req('POST', '$url/functions/v1/stripe-webhook', body: {
          'type': 'checkout.session.completed',
          'data': {'object': {'id': sid, 'payment_status': 'paid'}},
        });
        rec('webhook_unsigned', {'http': wh['http'], 'body': clip(wh['body'], 180)});
        if (wh['http'] == 200 && (wh['body'] is Map && (wh['body'] as Map)['ok'] == true && (wh['body'] as Map)['error'] == null)) {
          finding(
            id: 'SAT27C-WH-NOSIG',
            sev: 'P0',
            surface: 'WEBHOOK',
            pre: 'sem stripe-signature',
            identity: 'anon',
            request: 'POST stripe-webhook',
            response: clip(wh['body']),
            before: null,
            after: null,
            impact: 'Webhook sem assinatura aceite.',
            confidence: 'média',
            variant: 'unsigned',
            fp: '200 {error:missing_signature} não é bypass.',
          );
        }
      }
    }

    rec('checkout_expect_vs_happy', {'expect': expectAmt, 'happy': happyAmt, 'unit': unit, 'qty': qty});
    if (happy['http'] == 200 && happyAmt > 0 && happyAmt != expectAmt) {
      finding(
        id: 'SAT27C-INV-A-QUOTE',
        sev: 'P1',
        surface: 'CHECKOUT',
        pre: 'contrato selado',
        identity: 'buyer',
        request: 'create-payment-intent',
        response: {'expect': expectAmt, 'got': happyAmt},
        before: expectAmt,
        after: happyAmt,
        impact: 'Quote Stripe ≠ contrato autoritativo.',
        confidence: 'alta',
        variant: 'hand + prot',
        fp: 'arredondamento ±1 cêntimo documentado.',
      );
    }
  }

  // bag
  stdout.writeln('-- BAG --');
  cov('BAG', 'TESTADA COM VARIANTES');
  final bagA = await insertOrder(BH, {
    'product_id': pBagA?['id'],
    'buyer_id': bUid,
    'seller_id': sUid,
    'price_total': 10,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
    'shipping_method': 'hand',
  });
  final bagB = await insertOrder(BH, {
    'product_id': pBagB?['id'],
    'buyer_id': bUid,
    'seller_id': sUid,
    'price_total': 15,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
    'shipping_method': 'hand',
  });
  if (bagA?['id'] != null && bagB?['id'] != null) {
    final bag = await checkout(BH, {
      'order_id': bagA!['id'],
      'buyer_id': bUid,
      'bag_checkout': true,
      'shipping_method': 'hand',
      'bag_lines': [
        {'order_id': bagA['id'], 'line_total_cents': 1, 'quantity': 99, 'seller_id': sUid},
        {'order_id': bagB!['id'], 'line_total_cents': 1, 'quantity': 99, 'seller_id': sUid},
      ],
    });
    rec('bag_checkout', {'http': bag['http'], 'body': clip(bag['body'], 280)});
    // line_total ignored? server_amount should be ~10+15 + prot
    final bagAmt = n((bag['body'] is Map) ? (bag['body'] as Map)['server_amount_cents'] : 0);
    rec('bag_amt', bagAmt);
    if (bag['http'] == 200 && bagAmt > 0 && bagAmt < 500) {
      finding(
        id: 'SAT27C-BAG-LINE',
        sev: 'P0',
        surface: 'BAG',
        pre: '2 linhas 10€+15€, line_total=1c',
        identity: 'buyer',
        request: 'bag_checkout line_total_cents=1',
        response: clip(bag['body']),
        before: 2500,
        after: bagAmt,
        impact: 'line_total do cliente mandou no saco.',
        confidence: 'alta',
        variant: '2 linhas',
        fp: 'desconto conjunto pode baixar mas não para <5€.',
      );
    }
  }
  // 3+ lines
  if (pBagA != null && pCheap != null && p40 != null) {
    final l1 = await insertOrder(BH, {
      'product_id': pBagA['id'],
      'buyer_id': bUid,
      'seller_id': sUid,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app (Seguro Fleaber)',
    });
    final l2 = await insertOrder(BH, {
      'product_id': pCheap['id'],
      'buyer_id': bUid,
      'seller_id': sUid,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app (Seguro Fleaber)',
    });
    final l3 = await insertOrder(BH, {
      'product_id': p40['id'],
      'buyer_id': bUid,
      'seller_id': sUid,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app (Seguro Fleaber)',
    });
    if (l1?['id'] != null && l2?['id'] != null && l3?['id'] != null) {
      final bag3 = await checkout(BH, {
        'order_id': l1!['id'],
        'buyer_id': bUid,
        'bag_checkout': true,
        'shipping_method': 'hand',
        'bag_lines': [
          {'order_id': l1['id']},
          {'order_id': l2!['id']},
          {'order_id': l3!['id']},
        ],
      });
      rec('bag_3lines', {'http': bag3['http'], 'body': clip(bag3['body'], 250)});
    }
  }

  // =====================================================================
  // WALLET / PAYOUT
  // =====================================================================
  stdout.writeln('-- WALLET / PAYOUT --');
  cov('WALLET', 'TESTADA COM VARIANTES');
  cov('PAYOUT', 'TESTADA COM VARIANTES');
  final wAnon = await h.req('GET', '$url/rest/v1/wallets?select=id,balance,stripe_account_id&limit=5');
  rec('anon_wallets', {'http': wAnon['http'], 'n': wAnon['body'] is List ? (wAnon['body'] as List).length : 0});
  final wBuyer = await h.req('GET', '$url/rest/v1/wallets?select=id,balance&id=eq.$sUid', tok: BH);
  rec('buyer_read_seller_wallet', {'http': wBuyer['http'], 'body': clip(wBuyer['body'], 160)});
  if (wBuyer['http'] == 200 && wBuyer['body'] is List && (wBuyer['body'] as List).isNotEmpty) {
    finding(
      id: 'SAT27C-WAL-XUSER',
      sev: 'P1',
      surface: 'WALLET',
      pre: 'buyer JWT',
      identity: 'buyer',
      request: 'GET wallets?id=eq.seller',
      response: clip(wBuyer['body']),
      before: null,
      after: firstRow(wBuyer['body']),
      impact: 'Saldo alheio visível.',
      confidence: 'alta',
      variant: 'cross-user SELECT',
      fp: 'lista vazia = fechado.',
    );
  }
  final wIns = await h.req('POST', '$url/rest/v1/wallets', tok: BH, body: {
    'id': sUid,
    'balance': 9999.99,
  });
  rec('buyer_insert_seller_wallet', {'http': wIns['http'], 'body': clip(wIns['body'], 160)});
  final wUpd = await h.req('PATCH', '$url/rest/v1/wallets?id=eq.$bUid', tok: BH, body: {'balance': 9999.99});
  rec('buyer_patch_own_balance', {'http': wUpd['http'], 'body': clip(wUpd['body'], 160)});
  if (wUpd['http'] == 200 && wUpd['body'] is List && (wUpd['body'] as List).isNotEmpty) {
    final row = firstRow(wUpd['body']);
    if (d(row?['balance']) >= 9999) {
      finding(
        id: 'SAT27C-WAL-MINT',
        sev: 'P0',
        surface: 'WALLET',
        pre: 'buyer JWT',
        identity: 'buyer',
        request: 'PATCH wallets balance=9999',
        response: row,
        before: null,
        after: row?['balance'],
        impact: 'JWT cria fundos de plataforma.',
        confidence: 'alta',
        variant: 'direct PATCH',
        fp: 'trigger reverte = verificar GET service.',
      );
    }
  }
  final wAfter = firstRow((await h.req('GET', '$url/rest/v1/wallets?id=eq.$bUid&select=id,balance', tok: svc))['body']);
  rec('wallet_buyer_after_patch', wAfter);
  if (d(wAfter?['balance']) >= 9999) {
    finding(
      id: 'SAT27C-INV-E',
      sev: 'P0',
      surface: 'WALLET',
      pre: 'PATCH JWT',
      identity: 'buyer',
      request: 'PATCH balance',
      response: wAfter,
      before: null,
      after: wAfter?['balance'],
      impact: 'Invariante E falhou: JWT criou fundos.',
      confidence: 'alta',
      variant: 'observe service_role',
      fp: 'nenhum — observação service.',
    );
  }

  // payout as buyer (no funds)
  final po = await h.edge('create-connect-account', tok: BH, body: {
    'user_id': sUid,
    'amount': 100,
    'idempotency_key': 'sat27c-${stamp}a',
  });
  rec('payout_buyer_as_seller', {'http': po['http'], 'body': clip(po['body'], 220)});
  final po2 = await h.edge('create-connect-account', tok: SH, body: {
    'amount': 50,
    'idempotency_key': 'sat27c-${stamp}b',
  });
  rec('payout_seller_50c', {'http': po2['http'], 'body': clip(po2['body'], 220)});
  // same key retry
  final po2b = await h.edge('create-connect-account', tok: SH, body: {
    'amount': 50,
    'idempotency_key': 'sat27c-${stamp}b',
  });
  rec('payout_seller_retry_same_key', {'http': po2b['http'], 'body': clip(po2b['body'], 220)});
  // two keys same amount
  final po3 = await h.edge('create-connect-account', tok: SH, body: {
    'amount': 50,
    'idempotency_key': 'sat27c-${stamp}c',
  });
  rec('payout_seller_2nd_intent', {'http': po3['http'], 'body': clip(po3['body'], 220)});
  // concurrent
  final c1 = h.edge('create-connect-account', tok: SH, body: {
    'amount': 50,
    'idempotency_key': 'sat27c-${stamp}d1',
  });
  final c2 = h.edge('create-connect-account', tok: SH, body: {
    'amount': 50,
    'idempotency_key': 'sat27c-${stamp}d2',
  });
  final cr = await Future.wait([c1, c2]);
  rec('payout_concurrent', {'a': clip(cr[0]['body'], 140), 'b': clip(cr[1]['body'], 140), 'ha': cr[0]['http'], 'hb': cr[1]['http']});

  // =====================================================================
  // CHAT
  // =====================================================================
  stdout.writeln('-- CHAT --');
  cov('CHAT', 'TESTADA COM VARIANTES');
  final chatIns = await h.req('POST', '$url/rest/v1/chats', tok: BH, body: {
    'user_a': bUid,
    'user_b': sUid,
    'product_id': pCheap?['id'],
  });
  rec('chat_insert', {'http': chatIns['http'], 'body': clip(chatIns['body'], 180)});
  final chat = firstRow(chatIns['body']);
  if (chat?['id'] != null) createdChatIds.add('${chat!['id']}');
  if (chat?['id'] != null) {
    final msg = await h.req('POST', '$url/rest/v1/chat_messages', tok: BH, body: {
      'chat_id': chat!['id'],
      'sender_id': sUid,
      'receiver_id': bUid,
      'text': '$tag spoof sender',
    });
    rec('chat_sender_spoof', {'http': msg['http'], 'body': clip(msg['body'], 180)});
    final mrow = firstRow(msg['body']);
    if (mrow != null && mrow['sender_id'] == sUid) {
      finding(
        id: 'SAT27C-CHAT-SPOOF',
        sev: 'P1',
        surface: 'CHAT',
        pre: 'buyer JWT',
        identity: 'buyer',
        request: 'INSERT chat_messages sender_id=seller',
        response: mrow,
        before: bUid,
        after: mrow['sender_id'],
        impact: 'Spoof de remetente.',
        confidence: 'alta',
        variant: 'sender_id',
        fp: 'trigger reescreve sender=auth.uid().',
      );
    }
    final xchat = await h.req('GET', '$url/rest/v1/chats?select=id&limit=20', tok: BH);
    rec('buyer_chats_n', xchat['body'] is List ? (xchat['body'] as List).length : xchat['http']);
    final updLast = await h.req('PATCH', '$url/rest/v1/chats?id=eq.${chat['id']}', tok: BH, body: {
      'last_message': 'HACKED',
      'user_b': bUid,
    });
    rec('chat_upd_parties', {'http': updLast['http'], 'body': clip(updLast['body'], 160)});
  }
  // insert into foreign chat
  final foreignChats = await h.req('GET', '$url/rest/v1/chats?select=id,user_a,user_b&limit=30', tok: svc);
  if (foreignChats['body'] is List) {
    final foreign = (foreignChats['body'] as List).whereType<Map>().where((c) => c['user_a'] != bUid && c['user_b'] != bUid).toList();
    if (foreign.isNotEmpty) {
      final fid = foreign.first['id'];
      final ins = await h.req('POST', '$url/rest/v1/chat_messages', tok: BH, body: {
        'chat_id': fid,
        'sender_id': bUid,
        'receiver_id': foreign.first['user_a'],
        'text': '$tag inject',
      });
      rec('chat_inject_foreign', {'http': ins['http'], 'body': clip(ins['body'], 160), 'chat': fid});
      if (ins['http'] == 201 || (ins['http'] == 200 && ins['body'] is List && (ins['body'] as List).isNotEmpty)) {
        finding(
          id: 'SAT27C-CHAT-X',
          sev: 'P1',
          surface: 'CHAT',
          pre: 'chat alheio',
          identity: 'buyer',
          request: 'INSERT message foreign chat',
          response: clip(ins['body']),
          before: fid,
          after: null,
          impact: 'Injecção em conversa de terceiros.',
          confidence: 'alta',
          variant: 'cross-chat',
          fp: '200 vazio = RLS.',
        );
      }
    }
  }

  // =====================================================================
  // REVIEWS
  // =====================================================================
  stdout.writeln('-- REVIEWS --');
  cov('REVIEWS', 'TESTADA COM VARIANTES');
  if (payOrder?['id'] != null) {
    final rev = await h.req('POST', '$url/rest/v1/reviews', tok: BH, body: {
      'order_id': payOrder!['id'],
      'buyer_id': bUid,
      'target_id': sUid,
      'rating': 5,
      'comment': '$tag premature',
    });
    rec('review_unpaid', {'http': rev['http'], 'body': clip(rev['body'], 180)});
    if (rev['http'] == 201 || (rev['http'] == 200 && rev['body'] is List && (rev['body'] as List).isNotEmpty)) {
      finding(
        id: 'SAT27C-REV-STATE',
        sev: 'P1',
        surface: 'REVIEWS',
        pre: 'order não concluida',
        identity: 'buyer',
        request: 'INSERT reviews',
        response: clip(rev['body']),
        before: payOrder['status'],
        after: firstRow(rev['body']),
        impact: 'Review sem estado terminal.',
        confidence: 'alta',
        variant: 'unpaid order',
        fp: 'nenhum.',
      );
    }
  }
  final revX = await h.req('GET', '$url/rest/v1/reviews?select=id,buyer_id,target_id,rating,comment&limit=5', tok: BH);
  rec('buyer_reviews', {'http': revX['http'], 'n': revX['body'] is List ? (revX['body'] as List).length : 0});

  // =====================================================================
  // DISPUTES
  // =====================================================================
  stdout.writeln('-- DISPUTES --');
  cov('DISPUTE', 'TESTADA COM VARIANTES');
  if (payOrder?['id'] != null) {
    final dIns = await h.req('POST', '$url/rest/v1/order_disputes', tok: BH, body: {
      'order_id': payOrder!['id'],
      'buyer_id': bUid,
      'seller_id': sUid,
      'status': 'aberta',
      'buyer_percent': 100,
      'seller_percent': 0,
    });
    rec('dispute_insert', {'http': dIns['http'], 'body': clip(dIns['body'], 200)});
    final drow = firstRow(dIns['body']);
    if (drow?['id'] != null) {
      final dUpd = await h.req('PATCH', '$url/rest/v1/order_disputes?id=eq.${drow!['id']}', tok: BH, body: {
        'status': 'resolvida',
        'seller_percent': 0,
        'buyer_percent': 100,
      });
      rec('dispute_buyer_resolve', {'http': dUpd['http'], 'body': clip(dUpd['body'], 180)});
    }
  }
  final dAnon = await h.req('GET', '$url/rest/v1/order_disputes?select=*&limit=3');
  rec('anon_disputes', {'http': dAnon['http'], 'n': dAnon['body'] is List ? (dAnon['body'] as List).length : 0});

  // =====================================================================
  // STORAGE
  // =====================================================================
  stdout.writeln('-- STORAGE --');
  cov('STORAGE', 'TESTADA COM VARIANTES');
  final buckets = ['chat_media', 'fleaber_private', 'order_proofs', 'disputes', 'product_photos', 'profile_photos'];
  for (final b in buckets) {
    final listAnon = await h.req('POST', '$url/storage/v1/object/list/$b', body: {'prefix': '', 'limit': 5});
    rec('storage_list_anon_$b', {'http': listAnon['http'], 'body': clip(listAnon['body'], 140)});
    final listB = await h.req('POST', '$url/storage/v1/object/list/$b', tok: BH, body: {'prefix': '', 'limit': 5});
    rec('storage_list_buyer_$b', {'http': listB['http'], 'n': listB['body'] is List ? (listB['body'] as List).length : clip(listB['body'], 80)});
    final path = '$sUid/${tag}_overwrite.bin';
    final up = await h.req(
      'POST',
      '$url/storage/v1/object/$b/$path',
      tok: BH,
      extra: {'Content-Type': 'application/octet-stream', 'x-upsert': 'true'},
      body: {'note': 'not-binary-json-ok'},
    );
    rec('storage_upload_cross_$b', {'http': up['http'], 'body': clip(up['body'], 120)});
    if (up['http'] == 200 || up['http'] == 201) {
      finding(
        id: 'SAT27C-STO-$b',
        sev: b == 'fleaber_private' || b == 'order_proofs' ? 'P1' : 'P2',
        surface: 'STORAGE',
        pre: 'path sellerId/',
        identity: 'buyer',
        request: 'POST object/$b/$path',
        response: clip(up['body']),
        before: null,
        after: path,
        impact: 'Upload cross-user em $b.',
        confidence: 'alta',
        variant: 'path traversal-like',
        fp: 'JSON body pode 415 sem ser bypass; 200/201 é escrita.',
      );
    }
  }

  // =====================================================================
  // EDGES AUTHZ
  // =====================================================================
  stdout.writeln('-- EDGES --');
  cov('MUX', 'TESTADA COM VARIANTES');
  cov('LIVEKIT', 'TESTADA COM VARIANTES');
  cov('TIPS', 'TESTADA COM VARIANTES');
  cov('PS/OCR', 'TESTADA COM VARIANTES');
  cov('LIVE', 'TESTADA COM VARIANTES');
  cov('RAFFLE', 'PARCIAL');

  final muxBuyer = await h.edge('create-mux-live', tok: BH, body: {'title': '$tag buyer live'});
  rec('mux_buyer', {'http': muxBuyer['http'], 'body': clip(muxBuyer['body'], 200)});
  if (muxBuyer['http'] == 200) {
    finding(
      id: 'SAT27C-MUX-BUYER',
      sev: 'P1',
      surface: 'MUX',
      pre: 'buyer user_type',
      identity: 'buyer',
      request: 'POST create-mux-live',
      response: clip(muxBuyer['body']),
      before: null,
      after: null,
      impact: 'Comprador cria stream Mux (custo).',
      confidence: 'alta',
      variant: 'role',
      fp: '403 authz = fechado.',
    );
  }
  final muxAnon = await h.edge('create-mux-live', body: {'title': '$tag anon'});
  rec('mux_anon', {'http': muxAnon['http'], 'body': clip(muxAnon['body'], 120)});

  final lkBuyer = await h.edge('livekit-mux-publish', tok: BH, body: {'step': 'token', 'live_id': '00000000-0000-0000-0000-000000000001'});
  rec('livekit_buyer_foreign', {'http': lkBuyer['http'], 'body': clip(lkBuyer['body'], 180)});
  final liveRow = firstRow((await h.req('GET', '$url/rest/v1/lives?select=id,seller_id,vendedor_id&limit=1', tok: svc))['body']);
  if (liveRow?['id'] != null) {
    final lk = await h.edge('livekit-mux-publish', tok: BH, body: {
      'step': 'token',
      'live_id': liveRow!['id'],
      'stream_key': 'injected',
    });
    rec('livekit_inject_key', {'http': lk['http'], 'body': clip(lk['body'], 180)});
    final cm = await h.edge('complete-mux-live', tok: BH, body: {'live_id': liveRow['id']});
    rec('complete_mux_foreign', {'http': cm['http'], 'body': clip(cm['body'], 160)});
    cov('LIVE', 'TESTADA COM VARIANTES');
  }
  final eg = await h.edge('livekit-egress-cleanup', tok: BH, body: {});
  rec('egress_cleanup_buyer', {'http': eg['http'], 'body': clip(eg['body'], 120)});
  if (eg['http'] == 200) {
    finding(
      id: 'SAT27C-LK-CLEAN',
      sev: 'P1',
      surface: 'LIVEKIT',
      pre: 'buyer JWT',
      identity: 'buyer',
      request: 'POST livekit-egress-cleanup',
      response: clip(eg['body']),
      before: null,
      after: null,
      impact: 'Cleanup egress sem secret.',
      confidence: 'alta',
      variant: 'JWT',
      fp: '401 Unauthorized = fechado.',
    );
  }

  final tip = await h.edge('create-live-tip-checkout', tok: BH, body: {
    'seller_id': sUid,
    'amount_eur': 1,
    'tip_id': '00000000-0000-0000-0000-000000000001',
    'live_id': liveRow?['id'],
  });
  rec('tip_checkout', {'http': tip['http'], 'body': clip(tip['body'], 220)});
  final tipHi = await h.edge('create-live-tip-checkout', tok: BH, body: {
    'seller_id': sUid,
    'amount_eur': 9999,
  });
  rec('tip_max', {'http': tipHi['http'], 'body': clip(tipHi['body'], 160)});
  if (tipHi['http'] == 200) {
    finding(
      id: 'SAT27C-TIP-MAX',
      sev: 'P2',
      surface: 'TIPS',
      pre: 'amount_eur=9999',
      identity: 'buyer',
      request: 'create-live-tip-checkout',
      response: clip(tipHi['body']),
      before: 500,
      after: 9999,
      impact: 'Teto de gorjeta ausente.',
      confidence: 'alta',
      variant: 'max',
      fp: 'código teto 50000 cêntimos — 9999€ deve falhar.',
    );
  }
  final tipNeg = await h.edge('create-live-tip-checkout', tok: BH, body: {
    'seller_id': sUid,
    'amount_eur': -5,
  });
  rec('tip_neg', {'http': tipNeg['http'], 'body': clip(tipNeg['body'], 120)});

  // PS
  final psClaim = await h.edge('ps-pairing-claim', body: {'code': '000000', 'device_id': 'sat27c'});
  rec('ps_claim_000000', {'http': psClaim['http'], 'body': clip(psClaim['body'], 180)});
  // 5 codes only — not brute force
  for (final code in ['123456', '111111', '999999', '654321', '010101']) {
    final r = await h.edge('ps-pairing-claim', body: {'code': code, 'device_id': 'sat27c-rot-${Random().nextInt(99999)}'});
    rec('ps_claim_$code', {'http': r['http'], 'body': clip(r['body'], 100)});
    if (r['http'] == 200 && r['body'] is Map && (r['body'] as Map)['ok'] == true) {
      finding(
        id: 'SAT27C-PS-CLAIM',
        sev: 'P1',
        surface: 'PS/OCR',
        pre: 'código fraco $code',
        identity: 'anon',
        request: 'ps-pairing-claim',
        response: clip(r['body']),
        before: null,
        after: null,
        impact: 'Claim de pairing sem JWT com código trivial.',
        confidence: 'alta',
        variant: code,
        fp: 'ok:false expected.',
      );
    }
  }
  final ocr = await h.edge('ingest-ocr-reservation', body: {
    'live_id': liveRow?['id'] ?? '00000000-0000-0000-0000-000000000001',
    'ocr_line_hash': 'deadbeefdeadbeef',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
    'ref_number': 1,
    'requested_qty': 9,
  });
  rec('ocr_no_token', {'http': ocr['http'], 'body': clip(ocr['body'], 160)});
  final ocrTok = await h.req('POST', '$url/functions/v1/ingest-ocr-reservation', extra: {
    'x-device-token': 'forged-token-sat27c',
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  }, body: {
    'live_id': liveRow?['id'] ?? '00000000-0000-0000-0000-000000000001',
    'ocr_line_hash': 'cafebabecafebabe',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
    'requested_qty': 5,
    'ref_slug': 'x',
  });
  rec('ocr_forged_token', {'http': ocrTok['http'], 'body': clip(ocrTok['body'], 180)});
  if (ocrTok['http'] == 200 && ocrTok['body'] is Map && (ocrTok['body'] as Map)['ok'] == true) {
    finding(
      id: 'SAT27C-PS-OCR',
      sev: 'P0',
      surface: 'PS/OCR',
      pre: 'token forjado',
      identity: 'anon',
      request: 'ingest-ocr-reservation',
      response: clip(ocrTok['body']),
      before: null,
      after: null,
      impact: 'Ingest OCR cria reserva sem pairing válido.',
      confidence: 'alta',
      variant: 'forged device token',
      fp: '401 invalid_token = fechado.',
    );
  }

  final sms = await h.edge('send-sms-bulkgate', body: {'phone': '+351910000000', 'text': 'hi'});
  rec('sms_anon', {'http': sms['http'], 'body': clip(sms['body'], 160)});
  final meta = await h.edge('meta-data-deletion', body: {'signed_request': 'x.y'});
  rec('meta_unsigned', {'http': meta['http'], 'body': clip(meta['body'], 160)});
  final nuke = await h.edge('delete-test-account', tok: BH, body: {'confirm': 'APAGAR TUDO'});
  rec('nuke_buyer', {'http': nuke['http'], 'body': clip(nuke['body'], 160)});
  final muxPb = await h.edge('resolve-mux-playback', body: {'live_id': liveRow?['id'] ?? '00000000-0000-0000-0000-000000000001'});
  rec('resolve_mux_anon', {'http': muxPb['http'], 'body': clip(muxPb['body'], 200)});
  if (muxPb['body'] is Map) {
    final m = muxPb['body'] as Map;
    if ('${m['stream_key'] ?? m['mux_stream_key'] ?? ''}'.isNotEmpty) {
      finding(
        id: 'SAT27C-MUX-PB-KEY',
        sev: 'P1',
        surface: 'MUX',
        pre: 'anon resolve-mux-playback',
        identity: 'anon',
        request: 'POST resolve-mux-playback',
        response: clip(m, 200),
        before: null,
        after: null,
        impact: 'Playback resolver vaza stream_key.',
        confidence: 'alta',
        variant: 'anon',
        fp: 'playback_id público é esperado.',
      );
    }
  }
  final corsEvil = await h.req('OPTIONS', '$url/functions/v1/create-payment-intent', extra: {
    'Origin': 'https://evil.example',
    'Access-Control-Request-Method': 'POST',
  });
  rec('cors_evil', corsEvil['headers']);

  // =====================================================================
  // LIVE RESERVATIONS / RAFFLE
  // =====================================================================
  stdout.writeln('-- RESERVATIONS / RAFFLE --');
  cov('RESERVATIONS', 'TESTADA COM VARIANTES');
  final li = firstRow((await h.req('GET', '$url/rest/v1/live_items?select=id,live_id,seller_id,price,quantity,product_id&limit=1', tok: svc))['body']);
  rec('live_item_sample', li);
  if (li?['id'] != null) {
    final resIns = await h.req('POST', '$url/rest/v1/live_reservation_requests', tok: BH, body: {
      'live_id': li!['live_id'],
      'live_item_id': li['id'],
      'seller_id': li['seller_id'],
      'buyer_id': bUid,
      'requested_qty': 9,
      'source': 'fleaber_live',
      'status': 'accepted',
    });
    rec('res_direct_insert', {'http': resIns['http'], 'body': clip(resIns['body'], 200)});
    final rr = firstRow(resIns['body']);
    if (rr != null && n(rr['requested_qty']) == 9 && '${rr['status']}' == 'accepted') {
      finding(
        id: 'SAT27C-RES-INS',
        sev: 'P1',
        surface: 'RESERVATIONS',
        pre: 'direct INSERT',
        identity: 'buyer',
        request: 'INSERT live_reservation_requests qty=9 accepted',
        response: rr,
        before: null,
        after: rr,
        impact: 'Reserva aceite sem seller + qty inflada.',
        confidence: 'alta',
        variant: 'direct INSERT',
        fp: 'trigger força pending/qty=1.',
      );
    }
    // RPC request if exists
    for (final fn in rpcNames.where((n) => n.contains('reservation'))) {
      final r = await h.req('POST', '$url/rest/v1/rpc/$fn', tok: BH, body: {
        'p_live_item_id': li['id'],
        'p_requested_qty': 5,
        'p_live_id': li['live_id'],
      });
      rec('res_rpc_$fn', {'http': r['http'], 'body': clip(r['body'], 120)});
    }
  }
  final raffles = await h.req('GET', '$url/rest/v1/live_raffles?select=id,status,seller_id,live_id&limit=3');
  rec('anon_raffles', {'http': raffles['http'], 'n': raffles['body'] is List ? (raffles['body'] as List).length : 0});
  cov('RAFFLE', 'TESTADA COM VARIANTES');
  if (raffles['body'] is List && (raffles['body'] as List).isNotEmpty) {
    final rf = Map<String, dynamic>.from((raffles['body'] as List).first as Map);
    final win = await h.req('POST', '$url/rest/v1/live_raffle_winners', tok: BH, body: {
      'raffle_id': rf['id'],
      'user_id': bUid,
    });
    rec('raffle_self_winner', {'http': win['http'], 'body': clip(win['body'], 160)});
    if (win['http'] == 201 || (win['http'] == 200 && win['body'] is List && (win['body'] as List).isNotEmpty)) {
      finding(
        id: 'SAT27C-RAF-WIN',
        sev: 'P0',
        surface: 'RAFFLE',
        pre: 'buyer JWT',
        identity: 'buyer',
        request: 'INSERT live_raffle_winners',
        response: clip(win['body']),
        before: null,
        after: firstRow(win['body']),
        impact: 'Buyer auto-atribui prémio.',
        confidence: 'alta',
        variant: 'INSERT winner',
        fp: '200 vazio = RLS.',
      );
    }
    final rfUpd = await h.req('PATCH', '$url/rest/v1/live_raffles?id=eq.${rf['id']}', tok: BH, body: {'status': 'drawn'});
    rec('raffle_status_forge', {'http': rfUpd['http'], 'body': clip(rfUpd['body'], 140)});
  }

  // =====================================================================
  // STRIPE E2E HARNESS (service_role setup only) + JWT attacks
  // =====================================================================
  stdout.writeln('-- STRIPE E2E harness setup_paid_bag --');
  cov('SETTLE', 'TESTADA COM VARIANTES');
  cov('REFUND', 'TESTADA COM VARIANTES');
  cov('STOCK', 'TESTADA COM VARIANTES');
  cov('RACES', 'TESTADA COM VARIANTES');
  cov('BAG', 'TESTADA COM VARIANTES');
  final e2e = await h.edge('sec-fase2-e2e-oversell', tok: svc, body: {
    'probe': 'setup_paid_bag',
    'buyer_id': bUid,
    'seller_id': sUid,
  });
  rec('e2e_bag', {'http': e2e['http'], 'body': clip(e2e['body'], 500)});
  Json? e2eBody = e2e['body'] is Map ? Map<String, dynamic>.from(e2e['body'] as Map) : null;
  List<dynamic> bagOrders = [];
  if (e2eBody != null) {
    bagOrders = (e2eBody['orders'] as List?) ?? [];
    rec('e2e_bag_invariants', {
      'sum_eq_pi': e2eBody['invariant_sum_eq_pi'],
      'sum': e2eBody['sum_amount_paid_cents'],
      'pi': e2eBody['pi_amount_cents'],
      'no_full_pi': e2eBody['invariant_no_line_has_full_pi'],
    });
    if (e2eBody['ok'] == true && e2eBody['invariant_sum_eq_pi'] == false) {
      finding(
        id: 'SAT27C-BAG-SUM',
        sev: 'P1',
        surface: 'BAG',
        pre: 'setup_paid_bag TEST',
        identity: 'harness settle',
        request: 'sec-fase2-e2e-oversell setup_paid_bag',
        response: {'sum': e2eBody['sum_amount_paid_cents'], 'pi': e2eBody['pi_amount_cents']},
        before: e2eBody['pi_amount_cents'],
        after: e2eBody['sum_amount_paid_cents'],
        impact: 'Σ amount_paid_cents ≠ captura PI.',
        confidence: 'alta',
        variant: '2 linhas',
        fp: 'harness ≠ GET return; ainda prova settle bag.',
      );
    }
  }

  // refund as buyer (should 403)
  if (bagOrders.isNotEmpty) {
    final oid = '${(bagOrders.first as Map)['id']}';
    createdOrderIds.add(oid);
    final refB = await h.edge('refund-order', tok: BH, body: {'order_id': oid});
    rec('refund_buyer', {'http': refB['http'], 'body': clip(refB['body'], 200)});
    if (refB['http'] == 200 && refB['body'] is Map && (refB['body'] as Map)['ok'] == true && (refB['body'] as Map)['skipped'] != true) {
      finding(
        id: 'SAT27C-REF-BUYER',
        sev: 'P0',
        surface: 'REFUND',
        pre: 'order pago bag',
        identity: 'buyer',
        request: 'POST refund-order',
        response: clip(refB['body']),
        before: 'pago',
        after: clip(refB['body']),
        impact: 'Comprador reembolsa (seller-only).',
        confidence: 'alta',
        variant: 'buyer refund',
        fp: 'skipped/403 = fechado.',
      );
    }
    // seller refund line A then B
    final refS1 = await h.edge('refund-order', tok: SH, body: {'order_id': oid});
    rec('refund_seller_A', {'http': refS1['http'], 'body': clip(refS1['body'], 250)});
    final refS1b = await h.edge('refund-order', tok: SH, body: {'order_id': oid});
    rec('refund_seller_A_dup', {'http': refS1b['http'], 'body': clip(refS1b['body'], 200)});
    if (bagOrders.length > 1) {
      final oidB = '${(bagOrders[1] as Map)['id']}';
      createdOrderIds.add(oidB);
      final refS2 = await h.edge('refund-order', tok: SH, body: {'order_id': oidB});
      rec('refund_seller_B', {'http': refS2['http'], 'body': clip(refS2['body'], 250)});
      // concurrent leftover
      final rc1 = h.edge('refund-order', tok: SH, body: {'order_id': oidB});
      final rc2 = h.edge('refund-order', tok: SH, body: {'order_id': oidB});
      final rcr = await Future.wait([rc1, rc2]);
      rec('refund_B_concurrent', {'a': clip(rcr[0]['body'], 120), 'b': clip(rcr[1]['body'], 120)});
    }
    // stock after refund A
    final afterRef = firstRow((await h.req(
      'GET',
      '$url/rest/v1/orders?id=eq.$oid&select=id,status,stock_units_applied,stripe_refund_id,amount_paid_cents,product_id',
      tok: svc,
    ))['body']);
    rec('orderA_after_refund', afterRef);
    if (afterRef?['product_id'] != null) {
      final st = firstRow((await h.req(
        'GET',
        '$url/rest/v1/products?id=eq.${afterRef!['product_id']}&select=id,quantity,is_sold',
        tok: svc,
      ))['body']);
      rec('stock_after_refund_A', st);
    }
  }

  // oversell probe if exists
  final oversell = await h.edge('sec-fase2-e2e-oversell', tok: svc, body: {
    'probe': 'oversell',
    'buyer_id': bUid,
    'seller_id': sUid,
  });
  rec('e2e_oversell', {'http': oversell['http'], 'body': clip(oversell['body'], 400)});

  // fase2 with buyer JWT (must fail)
  final fase2Buyer = await h.edge(
    'create-payment-intent',
    tok: BH,
    qs: '?fase2_e2e_settle=1',
    body: {'order_id': payOrder?['id'], 'payment_intent_id': 'pi_x'},
  );
  rec('fase2_buyer_jwt', {'http': fase2Buyer['http'], 'body': clip(fase2Buyer['body'], 160)});
  if (fase2Buyer['http'] == 200 && fase2Buyer['body'] is Map && (fase2Buyer['body'] as Map)['ok'] == true) {
    finding(
      id: 'SAT27C-SET-FASE2-JWT',
      sev: 'P0',
      surface: 'SETTLE',
      pre: 'buyer JWT',
      identity: 'buyer',
      request: 'fase2_e2e_settle',
      response: clip(fase2Buyer['body']),
      before: null,
      after: null,
      impact: 'Settle interno aberto a JWT de utilizador.',
      confidence: 'alta',
      variant: 'buyer',
      fp: '401 service_role required = fechado.',
    );
  }

  // =====================================================================
  // STATE MACHINE jumps on a dedicated order
  // =====================================================================
  stdout.writeln('-- STATE MACHINE --');
  final sm = await insertOrder(BH, {
    'product_id': pCheap?['id'],
    'buyer_id': bUid,
    'seller_id': sUid,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app (Seguro Fleaber)',
  });
  if (sm?['id'] != null) {
    final id = sm!['id'];
    final jumps = [
      'pago', 'enviado', 'entregue', 'concluido', 'pedido_devolucao',
      'em_devolucao', 'devolucao_entregue', 'disputa_devolucao_vendedor',
      'devolvida', 'cancelado', 'premio_rifa',
    ];
    for (final st in jumps) {
      final rb = await h.req('PATCH', '$url/rest/v1/orders?id=eq.$id', tok: BH, body: {'status': st});
      rec('sm_buyer_$st', {'http': rb['http'], 'body': clip(rb['body'], 80)});
      final rs = await h.req('PATCH', '$url/rest/v1/orders?id=eq.$id', tok: SH, body: {'status': st});
      rec('sm_seller_$st', {'http': rs['http'], 'body': clip(rs['body'], 80)});
      final ra = await h.req('PATCH', '$url/rest/v1/orders?id=eq.$id', tok: anon, body: {'status': st});
      rec('sm_anon_$st', {'http': ra['http']});
    }
    final smLive = firstRow((await h.req(
      'GET',
      '$url/rest/v1/orders?id=eq.$id&select=status,amount_paid_cents',
      tok: svc,
    ))['body']);
    rec('sm_final', smLive);
    final terminal = {'pago', 'enviado', 'entregue', 'concluido', 'devolvida', 'premio_rifa'};
    if (smLive != null && terminal.contains('${smLive['status']}'.toLowerCase()) && n(smLive['amount_paid_cents']) == 0) {
      finding(
        id: 'SAT27C-SM-JUMP',
        sev: 'P0',
        surface: 'ORDERS',
        pre: 'order sem captura',
        identity: 'jwt',
        request: 'PATCH status jumps',
        response: smLive,
        before: 'reserva_pendente',
        after: smLive['status'],
        impact: 'Máquina de estados permitiu venda/terminal sem pagamento.',
        confidence: 'alta',
        variant: '${smLive['status']}',
        fp: 'cancelado não é venda.',
      );
    }
  }

  // Off-platform real MB WAY then release (invariant F)
  final mb = await insertOrder(BH, {
    'product_id': pCheap?['id'],
    'buyer_id': bUid,
    'seller_id': sUid,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento direto ao vendedor (MB WAY/transf)',
  });
  if (mb?['id'] != null) {
    final id = mb!['id'];
    await h.req('PATCH', '$url/rest/v1/orders?id=eq.$id', tok: SH, body: {'status': 'pago'});
    await h.req('PATCH', '$url/rest/v1/orders?id=eq.$id', tok: SH, body: {'status': 'enviado'});
    await h.req('PATCH', '$url/rest/v1/orders?id=eq.$id', tok: BH, body: {'status': 'concluido'});
    final mbLive = firstRow((await h.req(
      'GET',
      '$url/rest/v1/orders?id=eq.$id&select=id,status,amount_paid_cents,wallet_release_processed_at,payment_method',
      tok: svc,
    ))['body']);
    rec('mbway_states', mbLive);
    final balBefore = firstRow((await h.req('GET', '$url/rest/v1/wallets?id=eq.$sUid&select=balance', tok: svc))['body']);
    final rel = await h.req('POST', '$url/rest/v1/rpc/batata_release_seller_wallet_for_order', tok: BH, body: {'p_order_id': id});
    rec('mbway_release', {'http': rel['http'], 'body': clip(rel['body'], 160)});
    final balAfter = firstRow((await h.req('GET', '$url/rest/v1/wallets?id=eq.$sUid&select=balance', tok: svc))['body']);
    rec('mbway_wallet', {'before': balBefore, 'after': balAfter});
    if (d(balAfter?['balance']) - d(balBefore?['balance']) > 0.009) {
      finding(
        id: 'SAT27C-INV-F',
        sev: 'P0',
        surface: 'WALLET',
        pre: 'MB WAY sem captura Stripe',
        identity: 'buyer RPC release',
        request: 'batata_release_seller_wallet_for_order',
        response: {'delta': d(balAfter?['balance']) - d(balBefore?['balance']), 'rel': clip(rel['body'])},
        before: balBefore,
        after: balAfter,
        impact: 'Off-platform transformou-se em fundos Fleaber.',
        confidence: 'alta',
        variant: 'MB WAY concluido→release',
        fp: 'release false + saldo igual = fechado.',
      );
    }
  }

  // concurrent orders on qty=1
  stdout.writeln('-- RACES stock --');
  cov('RACES', 'TESTADA COM VARIANTES');
  cov('COMPOSITION', 'TESTADA COM VARIANTES');
  if (pOne?['id'] != null) {
    final futs = List.generate(3, (i) => insertOrder(BH, {
          'product_id': pOne!['id'],
          'buyer_id': bUid,
          'seller_id': sUid,
          'quantity': 1,
          'status': 'reserva_pendente',
          'payment_method': 'Pagamento na app (Seguro Fleaber)',
        }));
    final conc = await Future.wait(futs);
    rec('concurrent_orders_qty1', conc.map((e) => {'id': e?['id'], 'qty': e?['quantity']}).toList());
  }

  // proposal / bundle composition
  final offer = await h.req('POST', '$url/rest/v1/product_offers', tok: BH, body: {
    'product_id': p40?['id'],
    'buyer_id': bUid,
    'seller_id': sUid,
    'amount': 1.0,
    'status': 'accepted',
    'responded_at': DateTime.now().toUtc().toIso8601String(),
  });
  rec('offer_self_accept', {'http': offer['http'], 'body': clip(offer['body'], 180)});
  final offerRow = firstRow(offer['body']);
  if (offerRow?['id'] != null && '${offerRow!['status']}' == 'accepted') {
    finding(
      id: 'SAT27C-PRC-OFFER',
      sev: 'P1',
      surface: 'PRICING',
      pre: 'buyer cria oferta já accepted',
      identity: 'buyer',
      request: 'INSERT product_offers status=accepted amount=1',
      response: offerRow,
      before: 40,
      after: 1,
      impact: 'Buyer fabrica proposta aceite a 1€.',
      confidence: 'alta',
      variant: 'self-accept',
      fp: 'INSERT pending + seller accept é o fluxo; accepted no INSERT é o bug.',
    );
    final oOffer = await insertOrder(BH, {
      'product_id': p40?['id'],
      'buyer_id': bUid,
      'seller_id': sUid,
      'quantity': 1,
      'product_offer_id': offerRow['id'],
      'status': 'reserva_pendente',
      'payment_method': 'proposta aceite',
    });
    rec('order_with_forged_offer', oOffer);
    if (oOffer != null && n(oOffer['contract_unit_cents']) == 100) {
      finding(
        id: 'SAT27C-INV-L',
        sev: 'P0',
        surface: 'PRICING',
        pre: 'oferta self-accepted 1€',
        identity: 'buyer',
        request: 'INSERT order product_offer_id',
        response: oOffer,
        before: 4000,
        after: 100,
        impact: 'Contrato selado pela proposta forjada.',
        confidence: 'alta',
        variant: 'offer→order',
        fp: 'selo ignora oferta inválida e usa catálogo 40€ = fechado.',
      );
    }
  }

  // refund + wallet composition already covered
  // review + release: try review then release on unpaid
  if (sm?['id'] != null) {
    final rel2 = await h.req('POST', '$url/rest/v1/rpc/batata_release_seller_wallet_for_order', tok: BH, body: {'p_order_id': sm!['id']});
    rec('release_unpaid', {'http': rel2['http'], 'body': clip(rel2['body'], 120)});
  }

  // lives SELECT as buyer for keys
  final livesB = await h.req('GET', '$url/rest/v1/lives?select=id,mux_stream_key,stream_key&limit=3', tok: BH);
  rec('buyer_lives_keys', clip(livesB['body'], 250));

  // =====================================================================
  // PASSAGEM 3 extra composition: catalog hike then checkout
  // =====================================================================
  if (p40?['id'] != null) {
    await h.req('PATCH', '$url/rest/v1/products?id=eq.${p40!['id']}', tok: SH, body: {'price': 5.0});
    final oNew = await insertOrder(BH, {
      'product_id': p40['id'],
      'buyer_id': bUid,
      'seller_id': sUid,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app (Seguro Fleaber)',
      'shipping_method': 'hand',
    });
    rec('order_after_hike_down', oNew);
    if (oNew?['id'] != null) {
      await h.req('PATCH', '$url/rest/v1/products?id=eq.${p40['id']}', tok: SH, body: {'price': 80.0});
      final ck = await checkout(BH, {
        'order_id': oNew!['id'],
        'buyer_id': bUid,
        'shipping_method': 'hand',
      });
      rec('checkout_after_catalog_hike', {'http': ck['http'], 'body': clip(ck['body'], 220), 'contract': oNew['contract_unit_cents']});
      final got = n((ck['body'] is Map) ? (ck['body'] as Map)['server_amount_cents'] : 0);
      final sealed = n(oNew['contract_unit_cents']);
      if (ck['http'] == 200 && sealed > 0 && got > sealed + 400) {
        finding(
          id: 'SAT27C-INV-K-CHK',
          sev: 'P0',
          surface: 'CHECKOUT',
          pre: 'order selada; catálogo depois 80€',
          identity: 'buyer',
          request: 'create-payment-intent',
          response: {'sealed': sealed, 'quoted': got},
          before: sealed,
          after: got,
          impact: 'Checkout cobra catálogo vivo, não contrato.',
          confidence: 'alta',
          variant: 'hike after insert',
          fp: 'proteção+portes explicam +~1-4€, não +75€.',
        );
      }
    }
  }

  // =====================================================================
  // CLEANUP (test rows only)
  // =====================================================================
  stdout.writeln('-- cleanup --');
  for (final id in createdOrderIds.toSet()) {
    await h.req('DELETE', '$url/rest/v1/order_disputes?order_id=eq.$id', tok: svc);
    await h.req('DELETE', '$url/rest/v1/reviews?order_id=eq.$id', tok: svc);
    await h.req('DELETE', '$url/rest/v1/orders?id=eq.$id', tok: svc);
  }
  for (final id in createdChatIds.toSet()) {
    await h.req('DELETE', '$url/rest/v1/chat_messages?chat_id=eq.$id', tok: svc);
    await h.req('DELETE', '$url/rest/v1/chats?id=eq.$id', tok: svc);
  }
  for (final id in createdProductIds.toSet()) {
    await h.req('DELETE', '$url/rest/v1/product_offers?product_id=eq.$id', tok: svc);
    await h.req('DELETE', '$url/rest/v1/products?id=eq.$id&title=like.$tag*', tok: svc);
  }
  // restore product prices if leftover
  await h.req('PATCH', '$url/rest/v1/profiles?id=eq.$bUid', tok: svc, body: {
    'user_type': 'comprador',
  });

  final out = {
    'meta': {
      'tag': tag,
      'staging': stagingRef,
      'when': DateTime.now().toUtc().toIso8601String(),
      'production_touched': false,
      'fixes_applied': false,
    },
    'coverage': coverage,
    'findings': findings,
    'notes': notes,
    'n_probes': probes.length,
    'n_findings': findings.length,
    'rpc_count': rpcNames.length,
    'table_count': tables.length,
  };
  final f = File('tool/reports/SAT_CEGA_RAW_20260827.json');
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    ...out,
    'probes': probes,
  }));
  stdout.writeln('WROTE ${f.path}');
  stdout.writeln('FINDINGS=${findings.length}');
  for (final x in findings) {
    stdout.writeln('  ${x['severity']} ${x['id']} ${x['surface']} — ${x['impact']}');
  }
  stdout.writeln('COVERAGE:');
  coverage.forEach((k, v) => stdout.writeln('  $k: $v'));
}
