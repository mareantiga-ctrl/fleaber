// ignore_for_file: avoid_print
/// Auditoria cega independente 20260830T1605 — PASS 1 cobertura.
/// Staging fxdknzrqjenzqcvnwqqq only. Não corrige. Não toca produção. Não Fase 4.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../live_ops_staging_client.dart';

const stamp = '20260830T1605';
const projectMust = 'fxdknzrqjenzqcvnwqqq';

final findings = <Map<String, dynamic>>[];
final matrix = <Map<String, dynamic>>[];
final notes = <String>[];

void find({
  required String id,
  required String sev,
  required String title,
  required String actor,
  required String pre,
  required String repro,
  required String impact,
  required String state,
  Object? evidence,
}) {
  findings.add({
    'id': id,
    'severity': sev,
    'title': title,
    'actor': actor,
    'preconditions': pre,
    'reproduction': repro,
    'impact': impact,
    'state': state,
    'evidence': evidence,
  });
}

void row({
  required String surface,
  required String attack,
  required String identity,
  required String result,
  required String impact,
  required String severity,
  Object? evidence,
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

String clip(Object? v, [int n = 400]) {
  final s = v is String ? v : jsonEncode(v);
  if (s.length <= n) return s;
  return '${s.substring(0, n)}…';
}

Future<Map<String, dynamic>> req(
  String method,
  String u,
  Map<String, String> h, [
  Object? body,
]) async {
  final r = method == 'POST'
      ? await http.post(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body))
      : method == 'PATCH'
          ? await http.patch(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body))
          : method == 'PUT'
              ? await http.put(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body))
              : method == 'GET'
                  ? await http.get(Uri.parse(u), headers: h)
                  : await http.delete(Uri.parse(u), headers: h);
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body, 'headers': r.headers};
}

Map<String, String> hdr(String url, String anon, {String? jwt, String? svc}) {
  final token = svc ?? jwt ?? anon;
  return {
    'apikey': anon,
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
}

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return (s.isEmpty || s == 'null') ? null : s;
  }
  if (body is Map && body['id'] != null) {
    final s = '${body['id']}'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }
  return null;
}

bool persisted(dynamic body) {
  if (body is List && body.isNotEmpty) return true;
  if (body is Map && body['id'] != null) return true;
  return false;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) {
    stderr.writeln('ABORT: URL não é staging $projectMust');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final c = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerJwt = await c.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerJwt = await c.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final bUid = await c.userIdForAccessToken(buyerJwt);
  final sUid = await c.userIdForAccessToken(sellerJwt);
  if (bUid != buyerId || sUid != sellerId) {
    notes.add('JWT uid mismatch env buyer=$buyerId got=$bUid seller=$sellerId got=$sUid');
  }

  final outDir = Directory('tool/redteam_cega_indep_20260830T1605/out');
  outDir.createSync(recursive: true);

  final anonH = hdr(url, anon);
  final buyH = hdr(url, anon, jwt: buyerJwt);
  final selH = hdr(url, anon, jwt: sellerJwt);
  final svcH = hdr(url, anon, svc: svc);

  // ---------- OpenAPI inventory ----------
  final oa = await http.get(
    Uri.parse('$url/rest/v1/'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Accept': 'application/openapi+json',
    },
  );
  final spec = jsonDecode(oa.body) as Map<String, dynamic>;
  final paths = (spec['paths'] as Map?)?.keys.map((k) => '$k').toList() ?? [];
  paths.sort();
  final tables = paths.where((p) => !p.startsWith('/rpc/') && p != '/').map((p) => p.replaceFirst('/', '')).toList();
  final rpcs = paths.where((p) => p.startsWith('/rpc/')).map((p) => p.substring(5)).toList();
  File('${outDir.path}/openapi_paths.json').writeAsStringSync(jsonEncode({
    'http': oa.statusCode,
    'tables': tables,
    'rpcs': rpcs,
  }));
  notes.add('OpenAPI tables=${tables.length} rpcs=${rpcs.length}');

  // ---------- Sensitive table RLS ----------
  const sensitive = [
    'wallets',
    'wallet_transactions',
    'wallet_payout_ledger',
    'fleaber_commissions',
    'orders',
    'products',
    'reviews',
    'order_disputes',
    'chats',
    'chat_messages',
    'messages',
    'profiles',
    'lives',
    'live_items',
    'live_reservation_requests',
    'live_tips',
    'live_raffles',
    'live_raffle_winners',
    'live_raffle_tickets',
    'product_offers',
    'seller_bundle_discounts',
    'seller_helpers',
    'ps_pairing_sessions',
    'ps_reader_heartbeats',
    'ps_ingest_audit',
    'stripe_checkout_events',
    'batata_anon_rate_limits',
    'notifications',
    'device_tokens',
    'follows',
    'favorites',
    'admin_users',
    'staff_members',
    'seller_staff',
    'live_messages',
    'waitlist',
    'live_item_waitlist',
  ];

  Future<void> probeTable(String table) async {
    if (!tables.contains(table) && !tables.contains(table.replaceAll('_', '-'))) {
      // still try — OpenAPI may omit
    }
    for (final ident in [
      {'n': 'anon', 'h': anonH},
      {'n': 'buyer', 'h': buyH},
      {'n': 'seller', 'h': selH},
    ]) {
      final h = ident['h'] as Map<String, String>;
      final n = ident['n'] as String;
      final get = await req('GET', '$url/rest/v1/$table?select=*&limit=5', h);
      final rows = get['body'] is List ? (get['body'] as List).length : 0;
      var leaked = false;
      if (get['http'] == 200 && get['body'] is List) {
        for (final r in get['body'] as List) {
          if (r is! Map) continue;
          final bid = '${r['buyer_id'] ?? ''}';
          final sid = '${r['seller_id'] ?? ''}';
          final uid = '${r['user_id'] ?? r['id'] ?? ''}';
          final own = n == 'buyer'
              ? (bid == bUid || sid == bUid || uid == bUid)
              : n == 'seller'
                  ? (bid == sUid || sid == sUid || uid == sUid)
                  : false;
          if (n == 'anon' && rows > 0) leaked = true;
          if (n != 'anon' && rows > 0 && !own) {
            // may still be public catalog
            if (['wallets', 'wallet_transactions', 'wallet_payout_ledger', 'orders', 'order_disputes', 'chats', 'chat_messages', 'messages', 'ps_pairing_sessions', 'stripe_checkout_events', 'device_tokens'].contains(table)) {
              leaked = true;
            }
          }
        }
      }
      row(
        surface: table,
        attack: 'SELECT * limit 5',
        identity: n,
        result: 'http=${get['http']} rows=$rows',
        impact: leaked ? 'possível leitura alheia/pública' : 'sem leak óbvio neste sample',
        severity: leaked ? 'P2' : 'info',
        evidence: clip(get['body'], 180),
      );
      if (leaked && ['wallets', 'wallet_transactions', 'orders', 'order_disputes', 'ps_pairing_sessions', 'stripe_checkout_events'].contains(table)) {
        find(
          id: 'P1-SEL-$table-$n',
          sev: 'P1',
          title: 'SELECT $table como $n devolve linhas potencialmente alheias',
          actor: n,
          pre: 'JWT/anon válido',
          repro: 'GET /rest/v1/$table?select=*&limit=5',
          impact: 'leitura de dados financeiros/privados',
          state: 'ABERTO',
          evidence: clip(get['body'], 300),
        );
      }
    }
  }

  for (final t in sensitive) {
    try {
      await probeTable(t);
    } catch (err) {
      notes.add('probeTable $t: $err');
    }
  }

  // Stream keys via explicit column
  for (final ident in [
    {'n': 'anon', 'h': anonH},
    {'n': 'buyer', 'h': buyH},
    {'n': 'seller', 'h': selH},
  ]) {
    final get = await req(
      'GET',
      '$url/rest/v1/lives?select=id,mux_stream_key,stream_key,mux_live_id,livekit_egress_id&limit=3',
      ident['h'] as Map<String, String>,
    );
    final body = '${get['text']}';
    final hasKey = body.contains('mux_stream_key') && !body.contains('permission denied') && get['http'] == 200;
    row(
      surface: 'LIVE',
      attack: 'SELECT mux_stream_key,stream_key',
      identity: ident['n'] as String,
      result: 'http=${get['http']} ${clip(get['text'], 120)}',
      impact: hasKey ? 'stream key visível' : 'coluna recusada ou nula',
      severity: hasKey ? 'P1' : 'info',
      evidence: clip(get['text'], 200),
    );
    if (hasKey && get['body'] is List) {
      for (final r in get['body'] as List) {
        if (r is Map && ((r['mux_stream_key'] ?? '').toString().isNotEmpty || (r['stream_key'] ?? '').toString().isNotEmpty)) {
          find(
            id: 'P1-MUX-KEY-${ident['n']}',
            sev: 'P1',
            title: 'Stream key Mux visível via PostgREST',
            actor: ident['n'] as String,
            pre: 'lives existentes',
            repro: 'GET lives?select=mux_stream_key,stream_key',
            impact: 'hijack de ingest RTMP',
            state: 'ABERTO',
            evidence: {'id': r['id'], 'has_mux': (r['mux_stream_key'] ?? '').toString().isNotEmpty},
          );
        }
      }
    }
  }

  // ---------- Wallet mutations ----------
  final wIns = await req('POST', '$url/rest/v1/wallets', buyH, {
    'id': bUid,
    'balance': 9999.99,
    'stripe_account_id': 'acct_hostile_$stamp',
  });
  row(
    surface: 'WALLET',
    attack: 'INSERT wallet balance=9999',
    identity: 'buyer',
    result: 'http=${wIns['http']} ${clip(wIns['text'], 160)}',
    impact: persisted(wIns['body']) ? 'INSERT aceite' : 'bloqueado',
    severity: persisted(wIns['body']) ? 'P0' : 'info',
    evidence: clip(wIns['body'], 200),
  );
  if (persisted(wIns['body'])) {
    find(
      id: 'P0-WALLET-INSERT',
      sev: 'P0',
      title: 'JWT inseriu wallet com saldo inventado',
      actor: 'buyer',
      pre: 'authenticated',
      repro: 'POST /wallets {balance:9999.99}',
      impact: 'criação de fundos',
      state: 'ABERTO',
      evidence: wIns,
    );
  }

  final wPatch = await req('PATCH', '$url/rest/v1/wallets?id=eq.$bUid', buyH, {'balance': 8888.88});
  final wAfter = await req('GET', '$url/rest/v1/wallets?id=eq.$bUid&select=id,balance', buyH);
  var balAfter = 0.0;
  if (wAfter['body'] is List && (wAfter['body'] as List).isNotEmpty) {
    balAfter = double.tryParse('${(wAfter['body'] as List).first['balance']}') ?? 0;
  }
  row(
    surface: 'WALLET',
    attack: 'PATCH balance=8888.88',
    identity: 'buyer',
    result: 'http=${wPatch['http']} persist_balance=$balAfter',
    impact: balAfter >= 8888 ? 'saldo alterado' : 'não persistiu 8888',
    severity: balAfter >= 8888 ? 'P0' : 'info',
    evidence: {'patch': clip(wPatch['text'], 120), 'after': wAfter['body']},
  );
  if (balAfter >= 8888) {
    find(
      id: 'P0-WALLET-PATCH',
      sev: 'P0',
      title: 'JWT alterou wallets.balance',
      actor: 'buyer',
      pre: 'wallet existente',
      repro: 'PATCH /wallets?id=eq.$bUid {balance:8888.88}',
      impact: 'criação/roubo de fundos',
      state: 'ABERTO',
      evidence: wAfter['body'],
    );
  }

  final wtIns = await req('POST', '$url/rest/v1/wallet_transactions', buyH, {
    'wallet_id': bUid,
    'amount': 123.45,
    'type': 'venda',
    'description': 'hostile $stamp',
  });
  row(
    surface: 'LEDGER',
    attack: 'INSERT wallet_transactions venda 123.45',
    identity: 'buyer',
    result: 'http=${wtIns['http']} ${clip(wtIns['text'], 160)}',
    impact: persisted(wtIns['body']) ? 'ledger JWT' : 'bloqueado',
    severity: persisted(wtIns['body']) ? 'P0' : 'info',
  );
  if (persisted(wtIns['body'])) {
    find(
      id: 'P0-LEDGER-INSERT',
      sev: 'P0',
      title: 'JWT inseriu wallet_transactions',
      actor: 'buyer',
      pre: 'authenticated',
      repro: 'POST /wallet_transactions',
      impact: 'ledger privilegiado pelo cliente',
      state: 'ABERTO',
      evidence: wtIns['body'],
    );
  }

  final wOther = await req('GET', '$url/rest/v1/wallets?id=eq.$sUid&select=id,balance,stripe_account_id', buyH);
  row(
    surface: 'WALLET',
    attack: 'SELECT wallet alheia',
    identity: 'buyer→seller',
    result: 'http=${wOther['http']} rows=${wOther['body'] is List ? (wOther['body'] as List).length : "?"}',
    impact: (wOther['body'] is List && (wOther['body'] as List).isNotEmpty) ? 'leu wallet alheia' : 'RLS bloqueou',
    severity: (wOther['body'] is List && (wOther['body'] as List).isNotEmpty) ? 'P1' : 'info',
    evidence: wOther['body'],
  );

  // ---------- Privileged RPCs ----------
  final hostileRpcs = [
    {'fn': 'batata_credit_wallet_once', 'p': {'p_wallet_id': buyerId, 'p_order_id': '00000000-0000-0000-0000-000000000001', 'p_amount': 50, 'p_type': 'venda', 'p_description': 'hostile'}},
    {'fn': 'batata_debit_wallet_once', 'p': {'p_wallet_id': sellerId, 'p_order_id': '00000000-0000-0000-0000-000000000001', 'p_amount': 1, 'p_description': 'hostile'}},
    {'fn': 'batata_wallet_payout_debit', 'p': {'p_user_id': sellerId, 'p_amount_cents': 100, 'p_idempotency_key': 'hostile-$stamp-payout'}},
    {'fn': 'batata_wallet_payout_finish', 'p': {'p_idempotency_key': 'hostile-$stamp-payout', 'p_stripe_transfer_id': 'tr_fake', 'p_failed': false}},
    {'fn': 'batata_ensure_wallet', 'p': {'p_user_id': sellerId}},
    {'fn': 'batata_release_seller_wallet_for_order', 'p': {'p_order_id': '00000000-0000-0000-0000-000000000001'}},
    {'fn': 'batata_clawback_seller_wallet_for_order', 'p': {'p_order_id': '00000000-0000-0000-0000-000000000001'}},
    {'fn': 'batata_find_user_id_by_email', 'p': {'p_email': envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL')}},
    {'fn': 'batata_is_admin', 'p': <String, dynamic>{}},
    {'fn': 'batata_send_live_tip_from_wallet', 'p': {'p_live_id': '00000000-0000-0000-0000-000000000001', 'p_amount': 1}},
    {'fn': 'batata_draw_live_raffle_winners', 'p': {'p_raffle_id': '00000000-0000-0000-0000-000000000001'}},
    {'fn': 'batata_create_raffle_prize_order', 'p': {'p_raffle_id': '00000000-0000-0000-0000-000000000001', 'p_winner_id': buyerId, 'p_qty': 1}},
    {'fn': 'batata_ps_claim_pairing', 'p': {'p_code': '000000', 'p_device_id': 'hostile', 'p_app_version': 'x'}},
    {'fn': 'batata_ps_create_pairing', 'p': {'p_live_id': '00000000-0000-0000-0000-000000000001'}},
    {'fn': 'batata_settle_live_tip_from_stripe', 'p': {'p_tip_id': '00000000-0000-0000-0000-000000000001', 'p_stripe_session_id': 'cs_test_fake', 'p_paid_amount_cents': 500}},
    {'fn': 'batata_live_reconcile_stripe_order', 'p': {'p_order_id': '00000000-0000-0000-0000-000000000001'}},
    {'fn': 'batata_mark_live_item_sold', 'p': {'p_live_item_id': '00000000-0000-0000-0000-000000000001'}},
    {'fn': 'batata_generate_auto_feedback', 'p': <String, dynamic>{}},
    {'fn': 'batata_anon_rate_check', 'p': {'p_rate_key': 'x', 'p_rpc': 'x', 'p_max_hits': 1}},
  ];

  for (final rdef in hostileRpcs) {
    for (final ident in [
      {'n': 'anon', 'h': anonH},
      {'n': 'buyer', 'h': buyH},
      {'n': 'seller', 'h': selH},
    ]) {
      final res = await req(
        'POST',
        '$url/rest/v1/rpc/${rdef['fn']}',
        ident['h'] as Map<String, String>,
        rdef['p'],
      );
      final httpCode = res['http'] as int;
      final interesting = httpCode == 200 || (httpCode < 400 && httpCode >= 200);
      row(
        surface: 'RPC',
        attack: '${rdef['fn']}',
        identity: ident['n'] as String,
        result: 'http=$httpCode ${clip(res['text'], 140)}',
        impact: interesting ? 'EXECUTE aceite' : 'negado/erro',
        severity: interesting ? 'P2' : 'info',
        evidence: clip(res['text'], 180),
      );
      if (interesting &&
          ['batata_credit_wallet_once', 'batata_wallet_payout_debit', 'batata_debit_wallet_once', 'batata_settle_live_tip_from_stripe', 'batata_create_raffle_prize_order'].contains(rdef['fn'])) {
        find(
          id: 'P0-RPC-${rdef['fn']}-${ident['n']}',
          sev: 'P0',
          title: 'RPC privilegiada executável como ${ident['n']}',
          actor: ident['n'] as String,
          pre: 'GRANT EXECUTE',
          repro: 'POST /rpc/${rdef['fn']}',
          impact: 'efeito financeiro/estado via JWT/anon',
          state: 'ABERTO',
          evidence: clip(res['body'], 300),
        );
      }
      if (interesting && rdef['fn'] == 'batata_find_user_id_by_email') {
        find(
          id: 'P2-RPC-FIND-EMAIL-${ident['n']}',
          sev: 'P2',
          title: 'batata_find_user_id_by_email executável',
          actor: ident['n'] as String,
          pre: 'email conhecido',
          repro: 'POST /rpc/batata_find_user_id_by_email',
          impact: 'enumeração de contas',
          state: 'ABERTO',
          evidence: clip(res['body'], 200),
        );
      }
    }
  }

  // Probe ALL remaining RPCs as buyer with empty {} to find GRANT surface
  final rpcGrant = <Map<String, dynamic>>[];
  for (final fn in rpcs) {
    if (hostileRpcs.any((h) => h['fn'] == fn)) continue;
    final res = await req('POST', '$url/rest/v1/rpc/$fn', buyH, <String, dynamic>{});
    final anonRes = await req('POST', '$url/rest/v1/rpc/$fn', anonH, <String, dynamic>{});
    rpcGrant.add({
      'fn': fn,
      'buyer_http': res['http'],
      'anon_http': anonRes['http'],
      'buyer': clip(res['text'], 80),
      'anon': clip(anonRes['text'], 80),
    });
  }
  File('${outDir.path}/rpc_grant_buyer_anon.json').writeAsStringSync(jsonEncode(rpcGrant));
  final anonExec = rpcGrant.where((r) => (r['anon_http'] as int) == 200).map((r) => r['fn']).toList();
  notes.add('RPCs anon HTTP 200 (empty args): $anonExec');

  // ---------- Fixtures: product + order ----------
  final prodIns = await req('POST', '$url/rest/v1/products', selH, {
    'seller_id': sUid,
    'title': 'RT1605 $stamp',
    'price': 42.00,
    'quantity': 1,
    'list_on_marketplace': true,
    'available_for_live': false,
    'description': 'probe $stamp',
    'image_urls': <dynamic>[],
  });
  final productId = idOf(prodIns['body']);
  notes.add('product insert http=${prodIns['http']} id=$productId ${clip(prodIns['text'], 120)}');

  String? orderId;
  if (productId != null) {
    final ordIns = await req('POST', '$url/rest/v1/orders', buyH, {
      'buyer_id': bUid,
      'seller_id': sUid,
      'product_id': productId,
      'quantity': 1,
      'price_total': 0.50,
      'status': 'pago',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
      'contract_unit_cents': 1,
      'contract_qty': 99,
      'amount_paid_cents': 99999,
      'stripe_payment_intent_id': 'pi_hostile_$stamp',
    });
    orderId = idOf(ordIns['body']);
    Map<String, dynamic>? rowFinal;
    if (orderId != null) {
      final got = await req(
        'GET',
        '$url/rest/v1/orders?id=eq.$orderId&select=id,status,price_total,quantity,contract_unit_cents,contract_qty,amount_paid_cents,stripe_payment_intent_id,stripe_checkout_session_id,payment_method,shipping_method,buyer_id,seller_id,product_id',
        buyH,
      );
      if (got['body'] is List && (got['body'] as List).isNotEmpty) {
        rowFinal = Map<String, dynamic>.from((got['body'] as List).first as Map);
      }
    }
    row(
      surface: 'ORDERS',
      attack: 'INSERT pago + PI + contract 1c + qty 99 + price 0.50',
      identity: 'buyer',
      result: 'http=${ordIns['http']} id=$orderId final=$rowFinal',
      impact: 'ver row final vs payload hostil',
      severity: 'info',
      evidence: {'insert': clip(ordIns['body'], 250), 'final': rowFinal},
    );
    if (rowFinal != null) {
      final st = '${rowFinal['status']}'.toLowerCase();
      final pi = '${rowFinal['stripe_payment_intent_id'] ?? ''}';
      final paid = rowFinal['amount_paid_cents'];
      final unit = rowFinal['contract_unit_cents'];
      final qty = rowFinal['contract_qty'];
      if (st == 'pago' || (pi.isNotEmpty && pi != 'null') || (paid is num && paid > 0)) {
        find(
          id: 'P0-ORDER-INSERT-PAID',
          sev: 'P0',
          title: 'JWT criou encomenda já paga / com Stripe ID',
          actor: 'buyer',
          pre: 'produto próprio do seller lab',
          repro: 'POST /orders status=pago amount_paid_cents=99999 stripe_payment_intent_id=pi_hostile',
          impact: 'falsificar pagamento plataforma',
          state: 'ABERTO',
          evidence: rowFinal,
        );
      }
      if (unit is num && unit == 1) {
        find(
          id: 'P1-ORDER-INSERT-CONTRACT-1C',
          sev: 'P1',
          title: 'JWT selou contract_unit_cents=1 no INSERT',
          actor: 'buyer',
          pre: 'produto 42€',
          repro: 'POST /orders contract_unit_cents=1',
          impact: 'preço autoritativo do cliente',
          state: 'ABERTO',
          evidence: rowFinal,
        );
      }
      if (qty is num && qty == 99) {
        find(
          id: 'P1-ORDER-INSERT-QTY-99',
          sev: 'P1',
          title: 'JWT selou contract_qty=99 com stock=1',
          actor: 'buyer',
          pre: 'produto quantity=1',
          repro: 'POST /orders contract_qty=99 quantity=1 (trigger)',
          impact: 'qty autoritativa do cliente',
          state: 'ABERTO',
          evidence: rowFinal,
        );
      }
    }

    if (orderId != null) {
      final patchC = await req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', buyH, {
        'contract_unit_cents': 50,
        'contract_qty': 1,
        'quantity': 1,
        'price_total': 0.50,
        'status': 'pago',
        'amount_paid_cents': 5000,
        'stripe_payment_intent_id': 'pi_patch_$stamp',
        'buyer_id': sUid,
        'seller_id': bUid,
      });
      final got2 = await req(
        'GET',
        '$url/rest/v1/orders?id=eq.$orderId&select=id,status,price_total,quantity,contract_unit_cents,contract_qty,amount_paid_cents,stripe_payment_intent_id,buyer_id,seller_id',
        buyH,
      );
      final after = (got2['body'] is List && (got2['body'] as List).isNotEmpty)
          ? (got2['body'] as List).first
          : got2['body'];
      row(
        surface: 'ORDER FSM',
        attack: 'PATCH contract/status/PI/parties',
        identity: 'buyer',
        result: 'http=${patchC['http']} after=$after',
        impact: 'imutabilidade contrato',
        severity: 'info',
        evidence: after,
      );
      if (after is Map) {
        if ('${after['stripe_payment_intent_id'] ?? ''}'.contains('pi_patch')) {
          find(
            id: 'P0-ORDER-PATCH-PI',
            sev: 'P0',
            title: 'JWT persistiu stripe_payment_intent_id',
            actor: 'buyer',
            pre: 'order própria pendente',
            repro: 'PATCH orders stripe_payment_intent_id',
            impact: 'falsificar captura',
            state: 'ABERTO',
            evidence: after,
          );
        }
        if (after['contract_unit_cents'] == 50) {
          find(
            id: 'P1-ORDER-PATCH-UNIT',
            sev: 'P1',
            title: 'JWT alterou contract_unit_cents após INSERT',
            actor: 'buyer',
            pre: 'order própria',
            repro: 'PATCH contract_unit_cents=50',
            impact: 'preço autoritativo mutável',
            state: 'ABERTO',
            evidence: after,
          );
        }
        if ('${after['buyer_id']}' == sUid) {
          find(
            id: 'P0-ORDER-SWAP-PARTY',
            sev: 'P0',
            title: 'JWT trocou buyer_id da encomenda',
            actor: 'buyer',
            pre: 'order própria',
            repro: 'PATCH buyer_id=seller',
            impact: 'trocar parties',
            state: 'ABERTO',
            evidence: after,
          );
        }
      }

      // Checkout with hostile amount
      final ck = await req('POST', '$url/functions/v1/create-payment-intent', buyH, {
        'buyer_id': bUid,
        'order_id': orderId,
        'amount': 50,
        'quantity': 99,
        'item_price': 0.01,
        'shipping': 0,
        'protection_fee': 0,
        'shipping_method': 'hand',
        'product_id': productId,
        'seller_id': sUid,
        'prize_shipping': false,
      });
      row(
        surface: 'CHECKOUT',
        attack: 'create-payment-intent amount=50 item_price=0.01 qty=99',
        identity: 'buyer',
        result: 'http=${ck['http']} ${clip(ck['text'], 220)}',
        impact: 'Session vs contrato',
        severity: 'info',
        evidence: clip(ck['text'], 300),
      );

      // Cross-user checkout: seller JWT + buyer order
      final ckX = await req('POST', '$url/functions/v1/create-payment-intent', selH, {
        'buyer_id': bUid,
        'order_id': orderId,
        'amount': 4200,
        'shipping_method': 'hand',
      });
      row(
        surface: 'CHECKOUT',
        attack: 'seller JWT checkout order do buyer (buyer_id no body)',
        identity: 'seller',
        result: 'http=${ckX['http']} ${clip(ckX['text'], 180)}',
        impact: ckX['http'] == 200 ? 'seller iniciou pagamento alheio' : 'bloqueado',
        severity: ckX['http'] == 200 ? 'P1' : 'info',
        evidence: clip(ckX['text'], 200),
      );

      // Anon checkout
      final ckA = await req('POST', '$url/functions/v1/create-payment-intent', anonH, {
        'buyer_id': bUid,
        'order_id': orderId,
        'amount': 50,
        'shipping_method': 'hand',
      });
      row(
        surface: 'CHECKOUT',
        attack: 'anon create-payment-intent',
        identity: 'anon',
        result: 'http=${ckA['http']} ${clip(ckA['text'], 160)}',
        impact: ckA['http'] == 200 ? 'checkout sem auth' : 'bloqueado',
        severity: ckA['http'] == 200 ? 'P0' : 'info',
      );

      // prize_shipping on non-prize
      final ckP = await req('POST', '$url/functions/v1/create-payment-intent', buyH, {
        'buyer_id': bUid,
        'order_id': orderId,
        'amount': 350,
        'shipping_method': 'carrier',
        'prize_shipping': true,
      });
      row(
        surface: 'CHECKOUT',
        attack: 'prize_shipping=true em order não-rifa',
        identity: 'buyer',
        result: 'http=${ckP['http']} ${clip(ckP['text'], 180)}',
        impact: ckP['http'] == 200 ? 'pagou só portes' : 'bloqueado',
        severity: ckP['http'] == 200 ? 'P0' : 'info',
        evidence: clip(ckP['text'], 220),
      );
      if (ckP['http'] == 200) {
        find(
          id: 'P0-PRIZE-SHIP-BYPASS',
          sev: 'P0',
          title: 'prize_shipping=true criou Session sem ser rifa',
          actor: 'buyer',
          pre: 'order marketplace',
          repro: 'POST create-payment-intent prize_shipping=true',
          impact: 'pagar só portes em vez do artigo',
          state: 'ABERTO',
          evidence: clip(ckP['text'], 300),
        );
      }

      // Refund as buyer
      final rfB = await req('POST', '$url/functions/v1/refund-order', buyH, {'order_id': orderId});
      row(
        surface: 'REFUNDS',
        attack: 'buyer chama refund-order',
        identity: 'buyer',
        result: 'http=${rfB['http']} ${clip(rfB['text'], 160)}',
        impact: rfB['http'] == 200 && '${rfB['text']}'.contains('"ok":true') && !'${rfB['text']}'.contains('Sem permissão')
            ? 'buyer refund'
            : 'negado ou skip',
        severity: 'info',
      );

      // Refund as seller (no capture)
      final rfS = await req('POST', '$url/functions/v1/refund-order', selH, {'order_id': orderId});
      row(
        surface: 'REFUNDS',
        attack: 'seller refund-order sem captura',
        identity: 'seller',
        result: 'http=${rfS['http']} ${clip(rfS['text'], 180)}',
        impact: 'refund sem PI',
        severity: 'info',
      );

      // Release wallet as buyer
      final rel = await req('POST', '$url/rest/v1/rpc/batata_release_seller_wallet_for_order', buyH, {
        'p_order_id': orderId,
      });
      row(
        surface: 'PAYOUT',
        attack: 'buyer release wallet order pendente',
        identity: 'buyer',
        result: 'http=${rel['http']} ${clip(rel['text'], 160)}',
        impact: rel['body'] == true ? 'crédito sem captura' : 'não creditou',
        severity: rel['body'] == true ? 'P0' : 'info',
        evidence: rel['body'],
      );
      if (rel['body'] == true) {
        find(
          id: 'P0-RELEASE-NO-CAPTURE',
          sev: 'P0',
          title: 'Release wallet em order sem captura',
          actor: 'buyer',
          pre: 'order pendente',
          repro: 'rpc batata_release_seller_wallet_for_order',
          impact: 'criação de saldo',
          state: 'ABERTO',
          evidence: rel,
        );
      }

      // Review without paid
      final rev = await req('POST', '$url/rest/v1/reviews', buyH, {
        'order_id': orderId,
        'buyer_id': bUid,
        'target_id': sUid,
        'stars': 5,
        'comment': 'hostile review $stamp',
        'author_role': 'comprador',
        'purchase_verified': true,
      });
      row(
        surface: 'REVIEWS',
        attack: 'INSERT review order não paga',
        identity: 'buyer',
        result: 'http=${rev['http']} ${clip(rev['text'], 160)}',
        impact: persisted(rev['body']) ? 'review sem transação' : 'bloqueado',
        severity: persisted(rev['body']) ? 'P1' : 'info',
        evidence: clip(rev['body'], 200),
      );
      if (persisted(rev['body'])) {
        find(
          id: 'P1-REVIEW-UNPAID',
          sev: 'P1',
          title: 'Review persistida sem captura',
          actor: 'buyer',
          pre: 'order pendente',
          repro: 'POST /reviews',
          impact: 'fraude reputacional',
          state: 'ABERTO',
          evidence: rev['body'],
        );
      }

      // Review as seller impersonating buyer
      final revS = await req('POST', '$url/rest/v1/reviews', selH, {
        'order_id': orderId,
        'buyer_id': bUid,
        'target_id': sUid,
        'stars': 5,
        'comment': 'seller forged $stamp',
        'author_role': 'comprador',
      });
      row(
        surface: 'REVIEWS',
        attack: 'seller INSERT review como comprador',
        identity: 'seller',
        result: 'http=${revS['http']} ${clip(revS['text'], 140)}',
        impact: persisted(revS['body']) ? 'review forjada' : 'bloqueado',
        severity: persisted(revS['body']) ? 'P1' : 'info',
      );

      // Dispute
      final disp = await req('POST', '$url/rest/v1/order_disputes', buyH, {
        'order_id': orderId,
        'buyer_id': bUid,
        'reason': 'em_falta',
        'description': 'hostile $stamp',
      });
      row(
        surface: 'DISPUTES',
        attack: 'INSERT dispute order pendente',
        identity: 'buyer',
        result: 'http=${disp['http']} ${clip(disp['text'], 160)}',
        impact: persisted(disp['body']) ? 'dispute sem compra' : 'bloqueado/erro',
        severity: 'info',
      );

      // Seller marks pago (platform)
      final payS = await req('PATCH', '$url/rest/v1/orders?id=eq.$orderId', selH, {'status': 'pago'});
      final got3 = await req('GET', '$url/rest/v1/orders?id=eq.$orderId&select=status,amount_paid_cents', buyH);
      row(
        surface: 'ORDER FSM',
        attack: 'seller PATCH status=pago (plataforma)',
        identity: 'seller',
        result: 'http=${payS['http']} ${clip(got3['body'], 120)}',
        impact: 'atestar pagamento Stripe',
        severity: 'info',
        evidence: got3['body'],
      );
    }
  }

  // Cross-user order insert (buyer as seller of others product)
  if (productId != null) {
    final xOrd = await req('POST', '$url/rest/v1/orders', buyH, {
      'buyer_id': bUid,
      'seller_id': bUid,
      'product_id': productId,
      'quantity': 1,
      'price_total': 1,
      'status': 'pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
    });
    row(
      surface: 'ORDERS',
      attack: 'INSERT order seller_id=buyer em produto alheio',
      identity: 'buyer',
      result: 'http=${xOrd['http']} ${clip(xOrd['text'], 160)}',
      impact: persisted(xOrd['body']) ? 'troca de seller' : 'bloqueado',
      severity: persisted(xOrd['body']) ? 'P1' : 'info',
      evidence: clip(xOrd['body'], 200),
    );
    if (persisted(xOrd['body'])) {
      find(
        id: 'P1-ORDER-SELLER-SWAP',
        sev: 'P1',
        title: 'Buyer criou order com seller_id próprio sobre produto alheio',
        actor: 'buyer',
        pre: 'produto do seller lab',
        repro: 'POST /orders seller_id=buyer product_id=alheio',
        impact: 'trocar seller / ghost sale',
        state: 'ABERTO',
        evidence: xOrd['body'],
      );
    }
  }

  // Off-platform collusion path
  if (productId != null) {
    final off = await req('POST', '$url/rest/v1/orders', buyH, {
      'buyer_id': bUid,
      'seller_id': sUid,
      'product_id': productId,
      'quantity': 1,
      'price_total': 42,
      'status': 'pendente',
      'payment_method': 'MB WAY',
      'shipping_method': 'hand',
    });
    final offId = idOf(off['body']);
    if (offId != null) {
      final sPago = await req('PATCH', '$url/rest/v1/orders?id=eq.$offId', selH, {'status': 'pago'});
      final sEnv = await req('PATCH', '$url/rest/v1/orders?id=eq.$offId', selH, {'status': 'enviado'});
      final bCon = await req('PATCH', '$url/rest/v1/orders?id=eq.$offId', buyH, {'status': 'concluido'});
      final relOff = await req('POST', '$url/rest/v1/rpc/batata_release_seller_wallet_for_order', buyH, {
        'p_order_id': offId,
      });
      final wal = await req('GET', '$url/rest/v1/wallets?id=eq.$sUid&select=id,balance', selH);
      final txs = await req(
        'GET',
        '$url/rest/v1/wallet_transactions?order_id=eq.$offId&select=id,amount,type,description',
        selH,
      );
      row(
        surface: 'WALLET',
        attack: 'MB WAY seller pago→enviado buyer concluido + release',
        identity: 'collusion',
        result: 'pago=${sPago['http']} env=${sEnv['http']} con=${bCon['http']} rel=${relOff['body']} txs=${clip(txs['body'], 120)}',
        impact: (txs['body'] is List && (txs['body'] as List).isNotEmpty) ? 'saldo off-platform' : 'sem crédito',
        severity: (txs['body'] is List && (txs['body'] as List).isNotEmpty) ? 'P0' : 'info',
        evidence: {
          'order': offId,
          'release': relOff['body'],
          'wallet': wal['body'],
          'txs': txs['body'],
        },
      );
      if (txs['body'] is List && (txs['body'] as List).isNotEmpty) {
        find(
          id: 'P0-OFFPLATFORM-MINT',
          sev: 'P0',
          title: 'Pagamento off-platform criou movimento de wallet',
          actor: 'buyer+seller',
          pre: 'order MB WAY',
          repro: 'seller pago→enviado; buyer concluido; rpc release',
          impact: 'saldo Fleaber sem fundos plataforma',
          state: 'ABERTO',
          evidence: txs['body'],
        );
      }
    }
  }

  // Product offer self-accept
  if (productId != null) {
    final offIns = await req('POST', '$url/rest/v1/product_offers', buyH, {
      'product_id': productId,
      'buyer_id': bUid,
      'seller_id': sUid,
      'amount': 0.50,
      'status': 'accepted',
      'quantity': 1,
    });
    row(
      surface: 'OFFERS',
      attack: 'buyer INSERT offer já accepted 0.50€',
      identity: 'buyer',
      result: 'http=${offIns['http']} ${clip(offIns['text'], 160)}',
      impact: persisted(offIns['body']) && '${offIns['body']}'.contains('accepted')
          ? 'auto-aceite'
          : 'bloqueado ou pending',
      severity: 'info',
      evidence: clip(offIns['body'], 220),
    );
    final offerId = idOf(offIns['body']);
    if (offerId != null) {
      final acc = await req('PATCH', '$url/rest/v1/product_offers?id=eq.$offerId', buyH, {
        'status': 'accepted',
        'amount': 0.50,
      });
      row(
        surface: 'OFFERS',
        attack: 'buyer PATCH offer accepted',
        identity: 'buyer',
        result: 'http=${acc['http']} ${clip(acc['text'], 140)}',
        impact: 'auto-aceite',
        severity: 'info',
      );
      final ordOffer = await req('POST', '$url/rest/v1/orders', buyH, {
        'buyer_id': bUid,
        'seller_id': sUid,
        'product_id': productId,
        'product_offer_id': offerId,
        'quantity': 1,
        'payment_method': 'proposta',
        'shipping_method': 'hand',
        'status': 'pendente',
      });
      final oid = idOf(ordOffer['body']);
      Map<String, dynamic>? ofinal;
      if (oid != null) {
        final g = await req(
          'GET',
          '$url/rest/v1/orders?id=eq.$oid&select=id,contract_unit_cents,price_total,product_offer_id,payment_method',
          buyH,
        );
        if (g['body'] is List && (g['body'] as List).isNotEmpty) {
          ofinal = Map<String, dynamic>.from((g['body'] as List).first as Map);
        }
      }
      row(
        surface: 'PRICE / CONTRACT',
        attack: 'order com offer auto-accepted 0.50',
        identity: 'buyer',
        result: 'http=${ordOffer['http']} final=$ofinal',
        impact: (ofinal != null && ofinal['contract_unit_cents'] == 50)
            ? 'contrato a 0.50€ sem aceite seller'
            : 'oferta não selou / bloqueada',
        severity: (ofinal != null && ofinal['contract_unit_cents'] == 50) ? 'P0' : 'info',
        evidence: ofinal ?? clip(ordOffer['text'], 200),
      );
      if (ofinal != null && ofinal['contract_unit_cents'] == 50) {
        find(
          id: 'P0-OFFER-SELF-ACCEPT',
          sev: 'P0',
          title: 'Buyer selou contrato a 0,50€ via oferta auto-aceite',
          actor: 'buyer',
          pre: 'produto 42€',
          repro: 'INSERT product_offers status=accepted amount=0.50; POST order product_offer_id',
          impact: 'pagar menos que o preço legítimo',
          state: 'ABERTO',
          evidence: ofinal,
        );
      }
    }
  }

  // Bundle discounts: buyer upsert other seller
  final bun = await req('POST', '$url/rest/v1/seller_bundle_discounts', buyH, {
    'seller_id': sUid,
    'enabled': true,
    'tier_2_pct': 50,
    'tier_3_pct': 50,
    'tier_5_pct': 50,
  });
  row(
    surface: 'BUNDLES / DISCOUNTS',
    attack: 'buyer UPSERT descontos do seller a 50%',
    identity: 'buyer',
    result: 'http=${bun['http']} ${clip(bun['text'], 140)}',
    impact: persisted(bun['body']) ? 'desconto alheio' : 'bloqueado',
    severity: persisted(bun['body']) ? 'P1' : 'info',
  );

  // Staff helper self-insert
  final stf = await req('POST', '$url/rest/v1/seller_helpers', buyH, {
    'seller_id': sUid,
    'helper_id': bUid,
    'permissions': {
      'can_manage_payouts': true,
      'can_manage_raffles': true,
      'can_manage_helpers': true,
      'can_manage_orders': true,
    },
  });
  row(
    surface: 'AUTH / PROFILES',
    attack: 'buyer INSERT seller_helpers em loja alheia',
    identity: 'buyer',
    result: 'http=${stf['http']} ${clip(stf['text'], 160)}',
    impact: persisted(stf['body']) ? 'autoridade seller' : 'bloqueado',
    severity: persisted(stf['body']) ? 'P1' : 'info',
  );
  if (persisted(stf['body'])) {
    find(
      id: 'P1-STAFF-SELF-GRANT',
      sev: 'P1',
      title: 'Buyer gravou-se como helper do seller',
      actor: 'buyer',
      pre: 'tabela seller_helpers',
      repro: 'POST /seller_helpers',
      impact: 'assumir autoridade seller',
      state: 'ABERTO',
      evidence: stf['body'],
    );
  }

  // Profiles admin flags
  final prPatch = await req('PATCH', '$url/rest/v1/profiles?id=eq.$bUid', buyH, {
    'is_admin': true,
    'role': 'admin',
  });
  row(
    surface: 'AUTH / PROFILES',
    attack: 'PATCH is_admin/role',
    identity: 'buyer',
    result: 'http=${prPatch['http']} ${clip(prPatch['text'], 140)}',
    impact: 'escalada admin',
    severity: 'info',
  );

  // ---------- Edge functions ----------
  final edges = <String, Map<String, dynamic>>{
    'create-payment-intent': {'buyer_id': bUid, 'order_id': orderId, 'amount': 50},
    'refund-order': {'order_id': orderId},
    'create-connect-account': {
      'user_id': sUid,
      'amount': 100,
      'idempotency_key': 'hostile-connect-$stamp',
    },
    'create-live-tip-checkout': {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'seller_id': sUid,
      'amount_eur': 1,
    },
    'stripe-webhook': {'type': 'checkout.session.completed', 'data': {}},
    'create-mux-live': {'title': 'hostile $stamp'},
    'complete-mux-live': {'live_id': '00000000-0000-0000-0000-000000000001'},
    'livekit-mux-publish': {'step': 'token', 'live_id': '00000000-0000-0000-0000-000000000001'},
    'ingest-ocr-reservation': {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'ocr_line_hash': 'abcdefghijkl',
      'requested_qty': 99,
    },
    'ps-pairing-claim': {'code': '000000', 'device_id': 'hostile'},
    'ps-heartbeat': {'device_token': 'x'},
    'delete-test-account': {'confirm': 'APAGAR TUDO'},
    'sec-fase2-e2e-oversell': {'buyer_id': bUid, 'seller_id': sUid},
    'resolve-mux-playback': {'playback_id': 'x'},
    'send-sms-bulkgate': {'phone': '+351910000000', 'text': 'hi'},
    'meta-data-deletion': {},
    'livekit-egress-cleanup': {},
  };

  for (final entry in edges.entries) {
    for (final ident in [
      {'n': 'anon', 'h': anonH},
      {'n': 'buyer', 'h': buyH},
    ]) {
      final res = await req(
        'POST',
        '$url/functions/v1/${entry.key}',
        ident['h'] as Map<String, String>,
        entry.value,
      );
      row(
        surface: 'EDGE FUNCTIONS',
        attack: entry.key,
        identity: ident['n'] as String,
        result: 'http=${res['http']} ${clip(res['text'], 140)}',
        impact: res['http'] == 200 ? '200' : 'negado/erro',
        severity: 'info',
        evidence: clip(res['text'], 180),
      );
    }
  }

  // Connect: buyer payout of seller user_id
  final payX = await req('POST', '$url/functions/v1/create-connect-account', buyH, {
    'user_id': sUid,
    'amount': 100,
    'idempotency_key': 'hostile-payout-x-$stamp',
  });
  row(
    surface: 'PAYOUT',
    attack: 'buyer payout user_id=seller amount=100',
    identity: 'buyer',
    result: 'http=${payX['http']} ${clip(payX['text'], 180)}',
    impact: payX['http'] == 200 ? 'payout identidade errada' : 'bloqueado',
    severity: payX['http'] == 200 ? 'P0' : 'info',
    evidence: clip(payX['text'], 220),
  );
  if (payX['http'] == 200 && !'${payX['text']}'.toLowerCase().contains('cannot')) {
    find(
      id: 'P0-PAYOUT-FOREIGN',
      sev: 'P0',
      title: 'Buyer iniciou payout com user_id do seller',
      actor: 'buyer',
      pre: 'create-connect-account',
      repro: 'POST body user_id=seller amount=100',
      impact: 'payout para identidade errada / débito alheio',
      state: 'ABERTO',
      evidence: clip(payX['text'], 300),
    );
  }

  // Storage list
  for (final bucket in ['fleaber_private', 'chat_media', 'product_media']) {
    final list = await req('POST', '$url/storage/v1/object/list/$bucket', buyH, {
      'prefix': '',
      'limit': 20,
    });
    row(
      surface: 'STORAGE',
      attack: 'list $bucket prefix=',
      identity: 'buyer',
      result: 'http=${list['http']} ${clip(list['text'], 140)}',
      impact: list['http'] == 200 ? 'listing' : 'negado',
      severity: 'info',
      evidence: clip(list['text'], 180),
    );
  }

  // Chat leak: select all messages
  for (final t in ['chats', 'chat_messages', 'messages']) {
    final g = await req('GET', '$url/rest/v1/$t?select=*&limit=20', buyH);
    var foreign = 0;
    if (g['body'] is List) {
      for (final r in g['body'] as List) {
        if (r is! Map) continue;
        final ids = '${r['buyer_id'] ?? ''}|${r['seller_id'] ?? ''}|${r['user_id'] ?? ''}|${r['sender_id'] ?? ''}';
        if (!ids.contains(bUid) && ids.replaceAll('|', '').isNotEmpty) foreign++;
      }
    }
    row(
      surface: 'CHAT',
      attack: 'SELECT $t',
      identity: 'buyer',
      result: 'http=${g['http']} rows=${g['body'] is List ? (g['body'] as List).length : 0} foreign=$foreign',
      impact: foreign > 0 ? 'chat alheio' : 'scoped ou vazio',
      severity: foreign > 0 ? 'P1' : 'info',
    );
    if (foreign > 0) {
      find(
        id: 'P1-CHAT-LEAK-$t',
        sev: 'P1',
        title: 'Buyer leu $t de outros',
        actor: 'buyer',
        pre: 'mensagens existentes',
        repro: 'GET /$t?select=*&limit=20',
        impact: 'privacidade chat',
        state: 'ABERTO',
        evidence: {'foreign': foreign, 'sample': clip(g['body'], 200)},
      );
    }
  }

  // Catalog price change after order (invariant K)
  if (productId != null && orderId != null) {
    final before = await req(
      'GET',
      '$url/rest/v1/orders?id=eq.$orderId&select=contract_unit_cents,price_total',
      buyH,
    );
    await req('PATCH', '$url/rest/v1/products?id=eq.$productId', selH, {'price': 1.00});
    final ck2 = await req('POST', '$url/functions/v1/create-payment-intent', buyH, {
      'buyer_id': bUid,
      'order_id': orderId,
      'amount': 100,
      'shipping_method': 'hand',
    });
    row(
      surface: 'PRICE / CONTRACT',
      attack: 'seller baixa preço catálogo após order; checkout',
      identity: 'seller+buyer',
      result: 'before=${clip(before['body'], 80)} ck=${ck2['http']} ${clip(ck2['text'], 160)}',
      impact: 'contrato vs catálogo vivo',
      severity: 'info',
      evidence: {'before': before['body'], 'checkout': clip(ck2['text'], 200)},
    );
    // restore catalog
    await req('PATCH', '$url/rest/v1/products?id=eq.$productId', selH, {'price': 42.00});
  }

  // qty huge insert
  if (productId != null) {
    final qHuge = await req('POST', '$url/rest/v1/orders', buyH, {
      'buyer_id': bUid,
      'seller_id': sUid,
      'product_id': productId,
      'quantity': -1,
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
      'status': 'pendente',
    });
    final qZero = await req('POST', '$url/rest/v1/orders', buyH, {
      'buyer_id': bUid,
      'seller_id': sUid,
      'product_id': productId,
      'quantity': 0,
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
      'status': 'pendente',
    });
    final qBig = await req('POST', '$url/rest/v1/orders', buyH, {
      'buyer_id': bUid,
      'seller_id': sUid,
      'product_id': productId,
      'quantity': 1000000,
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
      'status': 'pendente',
    });
    row(
      surface: 'QUANTITY AUTHORITY',
      attack: 'INSERT qty -1 / 0 / 1e6',
      identity: 'buyer',
      result: 'neg=${qHuge['http']} zero=${qZero['http']} big=${qBig['http']} ${clip(qBig['text'], 100)}',
      impact: persisted(qBig['body']) ? 'qty enorme persistida' : 'rejeitado',
      severity: persisted(qBig['body']) ? 'P1' : 'info',
      evidence: {
        'neg': clip(qHuge['text'], 80),
        'zero': clip(qZero['text'], 80),
        'big': clip(qBig['text'], 120),
      },
    );
  }

  final frozen = {
    'FROZEN_AT': DateTime.now().toUtc().toIso8601String(),
    'pass': 1,
    'project': projectMust,
    'stamp': stamp,
    'production_touched': false,
    'fase4_started': false,
    'buyer_id': bUid,
    'seller_id': sUid,
    'product_id': productId,
    'order_id': orderId,
    'openapi_tables': tables.length,
    'openapi_rpcs': rpcs.length,
    'anon_rpc_200': anonExec,
    'findings': findings,
    'matrix': matrix,
    'notes': notes,
  };
  File('${outDir.path}/pass1.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(frozen));
  stdout.writeln('PASS1 findings=${findings.length} matrix=${matrix.length}');
  stdout.writeln('wrote ${outDir.path}/pass1.json');
  for (final f in findings) {
    stdout.writeln('${f['severity']} ${f['id']} ${f['title']}');
  }
}
