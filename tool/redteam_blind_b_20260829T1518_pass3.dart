// ignore_for_file: avoid_print
/// Pass 3 — verificar P1, retract FPs, mesma classe noutros módulos, saturação.
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
final retractions = <Map<String, dynamic>>[];

void finding({
  required String id,
  required String severity,
  required String title,
  required String actor,
  dynamic result,
  String? impact,
  String? request,
}) {
  findings.add({
    'id': id,
    'severity': severity,
    'title': title,
    'actor': actor,
    if (request != null) 'request': request,
    'result': result,
    if (impact != null) 'impact': impact,
  });
}

void harden(String id, String title, dynamic r) {
  blocked.add({'id': id, 'title': title, 'result': r});
}

dynamic clip(dynamic v, [int max = 800]) {
  final s = v is String ? v : jsonEncode(v);
  if (s.length <= max) return v is String ? v : jsonDecode(jsonEncode(v));
  return '${s.substring(0, max)}…';
}

Map<String, dynamic> snap(http.Response r) =>
    {'status': r.statusCode, 'body': clip(r.body, 550)};

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
  final headers = {
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

  // Retract PRIV-13: order seller_id≠me but buyer_id=me (conta vendedora como compradora)
  retractions.add({
    'id': 'RTB-B-PRIV-13',
    'reason':
        'FP: filtro seller_id=neq.self devolveu order onde o JWT é buyer (980f4fa1) noutro seller. RLS correcto, não leak cross-seller.',
  });

  await _verifyPiAmount(c, buyerTok, buyerId, sellerId);
  await _bankingVariants(c, buyerTok, sellerTok, buyerId, sellerId);
  await _payoutOracle(c, buyerTok, sellerTok, sellerId);
  await _raffleCorrectSigs(c, buyerTok, buyerId);
  await _tipCorrectSigs(c, buyerTok, sellerId);
  await _convertCorrectSigs(c, buyerTok);
  await _cleanupBankingOrders(c, buyerId);

  final prevFile =
      File('tool/reports/redteam_blind_b_$stamp/REDTEAM_BLIND_B_$stamp.json');
  final prev = jsonDecode(prevFile.readAsStringSync()) as Map<String, dynamic>;
  var merged = (prev['findings'] as List)
      .cast<Map>()
      .where((f) => f['id'] != 'RTB-B-PRIV-13')
      .map((f) => Map<String, dynamic>.from(f))
      .toList();

  // Downgrade PI-MUT if amount not hostile
  for (final f in merged) {
    if (f['id'] == 'RTB-B-PI-MUT' &&
        evidence['pi_amount_hostile'] != true) {
      f['severity'] = 'P3';
      f['title'] =
          'Checkout criado apesar de quantity/amount hostis no body (servidor ignorou — sessão legítima)';
      f['reclassified'] = 'P1→P3 após follow-the-money no amount Stripe/eventos';
    }
  }
  merged = [...merged, ...findings];

  final out = {
    ...prev,
    'pass3_at': DateTime.now().toUtc().toIso8601String(),
    'retractions': retractions,
    'findings': merged,
    'pass3_blocked': blocked,
    'pass3_evidence': evidence,
    'counts': {
      'P0': merged.where((f) => f['severity'] == 'P0').length,
      'P1': merged.where((f) => f['severity'] == 'P1').length,
      'P2': merged.where((f) => f['severity'] == 'P2').length,
      'P3': merged.where((f) => f['severity'] == 'P3').length,
    },
  };
  prevFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  File('tool/reports/redteam_blind_b_$stamp/pass3.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'findings': findings,
      'blocked': blocked,
      'retractions': retractions,
      'evidence': evidence,
    }),
  );
  print('PASS3 new=${findings.length} blocked=${blocked.length}');
  print('counts ${out['counts']}');
  for (final f in findings) {
    print('  [${f['severity']}] ${f['id']} ${f['title']}');
  }
}

Future<void> _verifyPiAmount(
  LiveOpsStagingClient c,
  String buyerTok,
  String buyerId,
  String sellerId,
) async {
  final ev = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/stripe_checkout_events?buyer_id=eq.$buyerId&select=session_id,event,detail,created_at&order=created_at.desc&limit=8',
    service: true,
  );
  evidence['recent_events'] = clip(ev.body, 900);
  var hostile = false;
  try {
    for (final raw in jsonDecode(ev.body) as List) {
      final d = '${(raw as Map)['detail']}';
      if (d.contains('"amount"') &&
          (d.contains(':1,') || d.contains('"amount":1'))) {
        hostile = true;
      }
    }
  } catch (_) {}
  evidence['pi_amount_hostile'] = hostile;

  // Also inspect order after PI: contract_qty
  final o = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/orders?buyer_id=eq.$buyerId&select=id,quantity,contract_qty,contract_unit_cents,price_total,status,stripe_checkout_session_id&order=created_at.desc&limit=5',
    token: buyerTok,
  );
  evidence['orders_after_pi'] = clip(o.body, 700);
}

Future<void> _bankingVariants(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String buyerId,
  String sellerId,
) async {
  final prod = await rest(
    c,
    method: 'GET',
    path:
        '/rest/v1/products?seller_id=eq.$sellerId&title=like.$tag*&select=id&limit=1',
    service: true,
  );
  final pid = rowId(prod);
  if (pid == null) return;

  // Case / whitespace / semantically adjacent statuses
  const variants = [
    'AGUARDA_CONFIRMACAO',
    ' aguarda_confirmacao ',
    'Aguarda_Confirmacao',
    'aguarda-confirmacao',
    'waiting_confirmation',
    'confirmed',
    'accepted',
  ];
  final matrix = <String, dynamic>{};
  for (final st in variants) {
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
    String? persisted;
    var leaked = false;
    if (oid != null) {
      final read = await rest(
        c,
        method: 'GET',
        path: '/rest/v1/orders?id=eq.$oid&select=id,status',
        token: buyerTok,
      );
      persisted = read.body;
      final rpc = await rest(
        c,
        method: 'POST',
        path: '/rest/v1/rpc/batata_seller_direct_payment_details',
        token: buyerTok,
        body: {'p_seller_id': sellerId},
      );
      leaked = rpc.body.contains('PT50');
      await rest(
        c,
        method: 'DELETE',
        path: '/rest/v1/orders?id=eq.$oid',
        service: true,
      );
    }
    matrix[st] = {
      'insert': snap(ins),
      'persisted': clip(persisted ?? ''),
      'leaked': leaked,
    };
    if (leaked) {
      finding(
        id: 'RTB-B-BANK-VAR-$st',
        severity: 'P1',
        title: 'Oráculo bancário via status variante "$st"',
        actor: 'buyer JWT',
        result: matrix[st],
      );
    }
  }
  evidence['bank_variants'] = matrix;

  // Direct payment details for random seller without relationship
  final strangers = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/profiles?select=id&limit=5',
    service: true,
  );
  try {
    for (final raw in jsonDecode(strangers.body) as List) {
      final id = (raw as Map)['id']?.toString();
      if (id == null || id == buyerId || id == sellerId) continue;
      final rpc = await rest(
        c,
        method: 'POST',
        path: '/rest/v1/rpc/batata_seller_direct_payment_details',
        token: buyerTok,
        body: {'p_seller_id': id},
      );
      evidence['bank_stranger_$id'] = snap(rpc);
      if (rpc.body.contains('iban') && rpc.body.contains('PT')) {
        finding(
          id: 'RTB-B-BANK-STRANGER',
          severity: 'P1',
          title: 'RPC banking revelou IBAN sem order',
          actor: 'buyer JWT',
          result: snap(rpc),
        );
      }
    }
  } catch (_) {}
}

Future<void> _payoutOracle(
  LiveOpsStagingClient c,
  String buyerTok,
  String sellerTok,
  String sellerId,
) async {
  final mine = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_get_my_payout_details',
    token: buyerTok,
    body: <String, dynamic>{},
  );
  evidence['payout_buyer'] = snap(mine);
  final seller = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_get_my_payout_details',
    token: sellerTok,
    body: <String, dynamic>{},
  );
  evidence['payout_seller'] = snap(seller);
  if (mine.body.contains('PT50')) {
    finding(
      id: 'RTB-B-PAYOUT-BUYER-IBAN',
      severity: 'P1',
      title: 'get_my_payout_details devolveu IBAN do seller ao buyer',
      actor: 'buyer JWT',
      result: snap(mine),
    );
  } else {
    harden('PAYOUT-BUYER', 'own payout only', snap(mine));
  }
}

Future<void> _raffleCorrectSigs(
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
      'p_action_type': 'share',
      'p_tickets_delta': 50,
      'p_source_id': 'x',
      'p_metadata': {},
    },
  );
  evidence['award_tickets'] = snap(tickets);
  if (tickets.statusCode == 200) {
    finding(
      id: 'RTB-B-RAFFLE-TICKETS',
      severity: 'P1',
      title: 'JWT award raffle tickets (assinatura correcta)',
      actor: 'buyer JWT',
      result: snap(tickets),
    );
  } else {
    harden('RAFFLE-TICKETS', 'award', snap(tickets));
  }

  final prize = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_create_raffle_prize_order',
    token: buyerTok,
    body: {
      'p_raffle_id': '00000000-0000-0000-0000-000000000030',
      'p_winner_uid': buyerId,
      'p_rank': 1,
    },
  );
  evidence['prize'] = snap(prize);
  if (prize.statusCode == 200) {
    finding(
      id: 'RTB-B-RAFFLE-PRIZE',
      severity: 'P1',
      title: 'JWT create raffle prize order',
      actor: 'buyer JWT',
      result: snap(prize),
    );
  } else {
    harden('RAFFLE-PRIZE', 'prize', snap(prize));
  }
}

Future<void> _tipCorrectSigs(
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
      'p_live_id': null,
      'p_seller_id': sellerId,
      'p_amount': 2,
      'p_message': tag,
      'p_stripe_session_id': null,
    },
  );
  evidence['tip_pending'] = snap(pending);
  if (pending.statusCode >= 300) {
    harden('TIP-PENDING', 'create', snap(pending));
    return;
  }
  String? tipId;
  try {
    tipId = jsonDecode(pending.body)?.toString();
  } catch (_) {}
  if (tipId == null) return;
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
  evidence['tip_settle'] = snap(settle);
  if (settle.statusCode == 200 && settle.body.contains('true')) {
    finding(
      id: 'RTB-B-TIP-MINT',
      severity: 'P0',
      title: 'JWT settle tip sem Stripe paid',
      actor: 'buyer JWT',
      result: snap(settle),
    );
  } else {
    harden('TIP-SETTLE', 'jwt settle denied', snap(settle));
  }
}

Future<void> _convertCorrectSigs(
  LiveOpsStagingClient c,
  String buyerTok,
) async {
  final conv = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_live_reservation_stripe_convert',
    token: buyerTok,
    body: {
      'p_order_id': '00000000-0000-0000-0000-000000000032',
      'p_request_id': '00000000-0000-0000-0000-000000000031',
    },
  );
  evidence['convert'] = snap(conv);
  if (conv.statusCode == 200) {
    finding(
      id: 'RTB-B-CONVERT',
      severity: 'P1',
      title: 'JWT stripe_convert',
      actor: 'buyer JWT',
      result: snap(conv),
    );
  } else {
    harden('CONVERT', 'stripe convert', snap(conv));
  }
}

Future<void> _cleanupBankingOrders(
  LiveOpsStagingClient c,
  String buyerId,
) async {
  await rest(
    c,
    method: 'DELETE',
    path:
        '/rest/v1/orders?buyer_id=eq.$buyerId&status=eq.aguarda_confirmacao&price_total=eq.8.2',
    service: true,
  );
}
