/// Red Team cego — PASS 3 composição, RPCs perigosos, Stripe TEST dual-pay.
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
  'checkout_urls': <String>[],
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
    'evidence': clip(evidence, 1000),
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
}) {
  final headers = <String, String>{
    'apikey': service ? c.serviceRoleKey : c.anonKey,
    'Authorization':
        'Bearer ${service ? c.serviceRoleKey : (token ?? c.anonKey)}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
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
}) {
  return http.post(
    Uri.parse('${c.url}/functions/v1/$fn'),
    headers: {
      'apikey': c.anonKey,
      'Authorization': 'Bearer ${token ?? c.anonKey}',
      'Content-Type': 'application/json',
    },
    body: jsonEncode(body ?? {}),
  );
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

Future<void> main() async {
  Directory(outDir).createSync(recursive: true);
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(stagingRef)) exit(2);
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
  final w0 = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/wallets?select=id,balance&id=in.($buyerId,$sellerId)',
    service: true,
  );
  rec(
    surface: 'WALLET',
    attack: 'balances at pass3 start',
    identity: 'service_observe',
    result: clip(w0.body, 200),
    impact: 'baseline',
    evidence: w0.body,
  );

  stdout.writeln('PASS3 privileged RPCs…');
  final rpcTries = <String, Map<String, dynamic>>{
    'batata_credit_wallet_once': {
      'p_user_id': buyerId,
      'p_amount': 100,
      'p_reason': 'rtf3',
    },
    'batata_debit_wallet_once': {
      'p_user_id': sellerId,
      'p_amount': 0.01,
      'p_reason': 'rtf3',
    },
    'batata_wallet_apply_tip_once': {
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_clawback_seller_wallet_for_order': {
      'p_order_id': 'bb56dbbf-589f-4a5b-ba2d-81526e87cc33',
    },
    'batata_create_raffle_prize_order': {
      'p_raffle_id': '00000000-0000-0000-0000-000000000001',
      'p_winner_id': buyerId,
    },
    'batata_admin_resolve_dispute': {
      'p_dispute_id': '00000000-0000-0000-0000-000000000001',
      'p_action': 'refund',
    },
    'batata_find_user_id_by_email': {
      'p_email': envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    },
    'batata_is_admin': {},
    'batata_generate_auto_feedback': {
      'p_order_id': 'bb56dbbf-589f-4a5b-ba2d-81526e87cc33',
    },
    'batata_seller_direct_payment_details': {'p_seller_id': sellerId},
    'batata_get_my_payout_details': {},
    'batata_lab_clear_all_fm_pending': {},
    'batata_lab_clear_fm_pending': {},
    'batata_record_buyer_purchase_ledger': {
      'p_order_id': 'bb56dbbf-589f-4a5b-ba2d-81526e87cc33',
    },
    'batata_record_fleaber_commission_once': {
      'p_order_id': 'bb56dbbf-589f-4a5b-ba2d-81526e87cc33',
    },
    'batata_award_live_raffle_tickets': {
      'p_live_id': '00000000-0000-0000-0000-000000000001',
      'p_user_id': buyerId,
      'p_qty': 10,
    },
    'batata_draw_live_raffle_winners': {
      'p_raffle_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_join_live_raffle': {
      'p_raffle_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_mark_live_item_sold': {
      'p_live_item_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_create_live_raffle': {
      'p_live_id': '00000000-0000-0000-0000-000000000001',
      'p_live_item_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_staging_h_v1_ux_demo_seed': {},
    'batata_send_live_tip_from_wallet': {
      'p_live_id': null,
      'p_seller_id': sellerId,
      'p_amount': 1,
      'p_message': 'rtf3',
    },
  };

  for (final ident in [
    ['buyer', buyerTok],
    ['seller', sellerTok],
  ]) {
    for (final e in rpcTries.entries) {
      final r = await rpcRaw(c, e.key, e.value, token: ident[1] as String);
      final interesting = r.statusCode == 200 &&
          !r.body.trim().startsWith('false') &&
          r.body.trim() != '[]' &&
          r.body.trim() != 'null';
      rec(
        surface: 'RPC',
        attack: '${e.key} as ${ident[0]}',
        identity: ident[0] as String,
        result: '${r.statusCode} ${clip(r.body, 200)}',
        impact: interesting ? 'NONEMPTY EXECUTE' : 'denied_or_false',
        evidence: r.body,
      );
      if (e.key.contains('credit') &&
          r.statusCode == 200 &&
          r.body.contains('true')) {
        finding(
          id: 'F-WAL-CREDIT-RPC',
          severity: 'P0',
          title: 'JWT chama batata_credit_wallet_once',
          actor: ident[0] as String,
          preconditions: 'none',
          reproduction: e.key,
          impact: 'mint saldo',
          evidence: r.body,
        );
      }
      if (e.key.contains('find_user') && r.statusCode == 200) {
        finding(
          id: 'F-PII-EMAIL-LOOKUP',
          severity: 'P2',
          title: 'RPC resolve email→uuid',
          actor: ident[0] as String,
          preconditions: 'know email',
          reproduction: 'batata_find_user_id_by_email',
          impact: 'enumeração de contas',
          evidence: r.body,
        );
      }
      if (e.key.contains('direct_payment') &&
          r.statusCode == 200 &&
          r.body.length > 8 &&
          ident[0] == 'buyer') {
        finding(
          id: 'F-PII-BANK-BUYER',
          severity: 'P1',
          title: 'Buyer lê dados pagamento directo do seller',
          actor: 'buyer',
          preconditions: 'seller UUID',
          reproduction: 'batata_seller_direct_payment_details',
          impact: 'IBAN/MB WAY alheios',
          evidence: r.body,
        );
      }
    }
  }

  final w1 = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/wallets?select=id,balance&id=in.($buyerId,$sellerId)',
    service: true,
  );
  rec(
    surface: 'WALLET',
    attack: 'balances after privileged RPC storm',
    identity: 'service_observe',
    result: clip(w1.body, 220),
    impact: 'detect mint vs start',
    evidence: 'start=${w0.body} after=${w1.body}',
  );

  // Review on MB WAY concluido (collusion composition)
  stdout.writeln('PASS3 review on fake-pago concluido…');
  final rev = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/reviews',
    token: buyerTok,
    body: {
      'target_id': sellerId,
      'buyer_id': buyerId,
      'stars': 5,
      'comment': 'rtf3 mbway collusion',
      'target_type': 'seller',
      'author_role': 'comprador',
      'order_id': 'bb56dbbf-589f-4a5b-ba2d-81526e87cc33',
    },
  );
  rec(
    surface: 'REVIEWS',
    attack: 'review after seller-attested MB WAY concluido',
    identity: 'buyer',
    result: '${rev.statusCode} ${clip(rev.body, 250)}',
    impact: rev.statusCode < 300
        ? 'review from off-platform attest'
        : 'blocked',
    evidence: rev.body,
  );
  if (rev.statusCode < 300) {
    finding(
      id: 'F-REV-OFFPLATFORM-COLLUSION',
      severity: 'P2',
      title: 'Review após MB WAY pago atestado pelo seller (sem Stripe)',
      actor: 'buyer+seller collusion',
      preconditions: 'seller PATCH pago + buyer PATCH concluido',
      reproduction: 'POST reviews on that order',
      impact: 'reputação sem fundos plataforma (off-platform by design; collusion)',
      evidence: rev.body,
    );
    final rid = idOf(rev);
    if (rid != null) {
      await rest(
        c,
        method: 'DELETE',
        path: '/rest/v1/reviews?id=eq.$rid',
        service: true,
      );
    }
  }

  // Duplicate review
  if (rev.statusCode < 300) {
    final rev2 = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/reviews',
      token: buyerTok,
      body: {
        'target_id': sellerId,
        'buyer_id': buyerId,
        'stars': 1,
        'comment': 'rtf3 dup',
        'target_type': 'seller',
        'author_role': 'comprador',
        'order_id': 'bb56dbbf-589f-4a5b-ba2d-81526e87cc33',
      },
    );
    rec(
      surface: 'REVIEWS',
      attack: 'duplicate review same order',
      identity: 'buyer',
      result: '${rev2.statusCode} ${clip(rev2.body, 200)}',
      impact: rev2.statusCode < 300 ? 'dup review' : 'blocked',
      evidence: rev2.body,
    );
  }

  // hub_lives_public stream keys
  stdout.writeln('PASS3 live public + storage GET…');
  final hub = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/hub_lives_public?select=*&limit=3',
    token: buyerTok,
  );
  rec(
    surface: 'LIVE',
    attack: 'SELECT hub_lives_public *',
    identity: 'buyer',
    result: '${hub.statusCode} ${clip(hub.body, 280)}',
    impact: hub.body.contains('stream_key') || hub.body.contains('mux_stream')
        ? 'KEY LEAK'
        : 'no stream key in public view',
    evidence: hub.body,
  );
  final hubAnon = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/hub_lives_public?select=*&limit=3',
  );
  rec(
    surface: 'LIVE',
    attack: 'SELECT hub_lives_public anon',
    identity: 'anon',
    result: '${hubAnon.statusCode} ${clip(hubAnon.body, 220)}',
    impact: 'public live',
    evidence: hubAnon.body,
  );

  final liveItems = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/live_items?select=id,live_id,price,status,seller_id&limit=5',
    token: buyerTok,
  );
  rec(
    surface: 'LIVE ITEMS',
    attack: 'SELECT live_items',
    identity: 'buyer',
    result: '${liveItems.statusCode} n=${asList(liveItems.body).length} ${clip(liveItems.body, 180)}',
    impact: 'scope',
    evidence: liveItems.body,
  );

  final tips = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/live_tips?select=id,buyer_id,seller_id,amount,status&limit=10',
    token: buyerTok,
  );
  rec(
    surface: 'TIPS',
    attack: 'SELECT live_tips',
    identity: 'buyer',
    result: '${tips.statusCode} n=${asList(tips.body).length}',
    impact: asList(tips.body).any((e) => e['buyer_id'] != buyerId)
        ? 'foreign tips'
        : 'own or empty',
    evidence: clip(tips.body, 300),
  );

  final objGet = await http.get(
    Uri.parse(
      '${c.url}/storage/v1/object/chat_media/product_photos/$sellerId/1782914369313_0_scaled_1000003839.jpg',
    ),
    headers: {
      'apikey': c.anonKey,
      'Authorization': 'Bearer ${c.anonKey}',
    },
  );
  rec(
    surface: 'STORAGE',
    attack: 'GET seller product photo as anon',
    identity: 'anon',
    result: '${objGet.statusCode} bytes=${objGet.bodyBytes.length} ct=${objGet.headers['content-type']}',
    impact: objGet.statusCode == 200
        ? 'public catalog image readable (expected if public bucket)'
        : 'denied',
    evidence: 'status=${objGet.statusCode}',
  );

  // Offers with amount
  final off = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/product_offers',
    token: buyerTok,
    body: {
      'product_id': '2ec10908-ca19-4c32-bf95-c4e4546226e0',
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 0.01,
      'status': 'accepted',
    },
  );
  rec(
    surface: 'OFFERS',
    attack: 'INSERT amount=0.01 status=accepted',
    identity: 'buyer',
    result: '${off.statusCode} ${clip(off.body, 220)}',
    impact: off.statusCode < 300 ? 'self-accepted offer' : 'blocked',
    evidence: off.body,
  );

  // Reservation RPCs
  for (final fn in [
    'batata_process_live_reservation_request',
    'batata_live_reservation_accept_available',
    'batata_claim_external_reservations',
    'batata_confirm_ps_reservation',
    'batata_live_bag_update_qty',
  ]) {
    final r = await rpcRaw(
      c,
      fn,
      {
        'p_request_id': '00000000-0000-0000-0000-000000000001',
        'p_live_id': '00000000-0000-0000-0000-000000000001',
        'p_qty': 99,
      },
      token: buyerTok,
    );
    rec(
      surface: 'LIVE RESERVATIONS',
      attack: '$fn qty=99',
      identity: 'buyer',
      result: '${r.statusCode} ${clip(r.body, 180)}',
      impact: 'reservation abuse',
      evidence: r.body,
    );
  }

  // Dual stock=1 Stripe sessions for TEST pay
  stdout.writeln('PASS3 stock=1 dual session fixtures…');
  final prod = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/products',
    token: sellerTok,
    body: {
      'seller_id': sellerId,
      'title': 'RTF3-STOCK1-$stamp',
      'price': 8.0,
      'quantity': 1,
      'list_on_marketplace': true,
      'is_sold': false,
    },
  );
  final pid = idOf(prod)!;
  (cleanup['product_ids'] as List).add(pid);

  Future<String> orderFor(String tok, String bid) async {
    final r = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/orders',
      token: tok,
      body: {
        'product_id': pid,
        'buyer_id': bid,
        'seller_id': sellerId,
        'price_total': 8.0,
        'status': 'reserva_pendente',
        'quantity': 1,
        'payment_method': 'Seguro Fleaber',
        'shipping_method': 'hand',
        'is_reservation': true,
      },
    );
    final id = idOf(r)!;
    (cleanup['order_ids'] as List).add(id);
    return id;
  }

  final oA = await orderFor(buyerTok, buyerId);
  final freshEmail = 'rtf3.$stamp@fleaber.test';
  final freshId = await c.createAdminUser(
    email: freshEmail,
    password: 'Teste${stamp}Aa!',
  );
  final freshTok = await c.signIn(
    email: freshEmail,
    password: 'Teste${stamp}Aa!',
  );
  final oB = await orderFor(freshTok, freshId);

  Future<Map<String, dynamic>> session(String oid, String tok, String bid) async {
    final r = await edge(
      c,
      'create-payment-intent',
      token: tok,
      body: {
        'order_id': oid,
        'buyer_id': bid,
        'shipping_method': 'hand',
      },
    );
    final m = asMap(r.body) ?? {};
    rec(
      surface: 'STRIPE TEST',
      attack: 'create session order=$oid',
      identity: bid == buyerId ? 'buyer' : 'fresh',
      result: '${r.statusCode} amt=${m['server_amount_cents']} sid=${m['checkoutSessionId']}',
      impact: r.statusCode == 200 ? 'SESSION CRIADA' : 'blocked',
      evidence: r.body,
    );
    return m;
  }

  final sA = await session(oA, buyerTok, buyerId);
  final sB = await session(oB, freshTok, freshId);
  File('$outDir/pass3_pay_urls.json').writeAsStringSync(
    jsonEncode({
      'product_id': pid,
      'order_a': oA,
      'order_b': oB,
      'session_a': sA['checkoutSessionId'],
      'session_b': sB['checkoutSessionId'],
      'url_a': sA['checkoutUrl'],
      'url_b': sB['checkoutUrl'],
      'amt_a': sA['server_amount_cents'],
      'amt_b': sB['server_amount_cents'],
      'note':
          'SESSION CRIADA only. Pay both with Stripe TEST 4242 to test two captures on stock=1.',
    }),
  );

  // Partial refund RPC on MB WAY concluido
  final part = await rpcRaw(
    c,
    'batata_process_partial_refund_dispute',
    {
      'p_order_id': 'bb56dbbf-589f-4a5b-ba2d-81526e87cc33',
      'p_refund_percent': 50,
    },
    token: buyerTok,
  );
  rec(
    surface: 'REFUNDS',
    attack: 'partial refund 50% on MB WAY concluido',
    identity: 'buyer',
    result: '${part.statusCode} ${clip(part.body, 250)}',
    impact: 'mint from off-platform?',
    evidence: part.body,
  );
  final w2 = await rest(
    c,
    method: 'GET',
    path: '/rest/v1/wallets?select=id,balance&id=in.($buyerId,$sellerId)',
    service: true,
  );
  rec(
    surface: 'WALLET',
    attack: 'balances after partial refund RPC',
    identity: 'service_observe',
    result: clip(w2.body, 220),
    impact: 'detect mint',
    evidence: w2.body,
  );

  // Dispute insert on own concluido MB WAY
  final disp = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/order_disputes',
    token: buyerTok,
    body: {
      'order_id': 'bb56dbbf-589f-4a5b-ba2d-81526e87cc33',
      'status': 'aberta',
    },
  );
  rec(
    surface: 'DISPUTES',
    attack: 'INSERT dispute on MB WAY concluido',
    identity: 'buyer',
    result: '${disp.statusCode} ${clip(disp.body, 220)}',
    impact: 'dispute without stripe',
    evidence: disp.body,
  );

  // Chat insert into foreign chat
  final chats = asList(
    (await rest(
      c,
      method: 'GET',
      path: '/rest/v1/chats?select=id,user_a,user_b&limit=50',
      service: true,
    ))
        .body,
  );
  final foreign = chats.where((e) {
    return e['user_a'] != buyerId &&
        e['user_b'] != buyerId &&
        e['user_a'] != sellerId &&
        e['user_b'] != sellerId;
  }).toList();
  if (foreign.isNotEmpty) {
    final cid = foreign.first['id'];
    final msg = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/chat_messages',
      token: buyerTok,
      body: {
        'chat_id': cid,
        'sender_id': buyerId,
        'receiver_id': foreign.first['user_a'],
        'text': 'rtf3 inject',
        'is_read': false,
      },
    );
    rec(
      surface: 'CHAT',
      attack: 'INSERT message into foreign chat $cid',
      identity: 'buyer',
      result: '${msg.statusCode} ${clip(msg.body, 200)}',
      impact: msg.statusCode < 300 ? 'cross-chat inject' : 'blocked',
      evidence: msg.body,
    );
    if (msg.statusCode < 300) {
      finding(
        id: 'F-CHAT-INJECT',
        severity: 'P1',
        title: 'Buyer injecta mensagem em chat alheio',
        actor: 'buyer',
        preconditions: 'know chat UUID',
        reproduction: 'POST chat_messages foreign chat_id',
        impact: 'cross-user chat',
        evidence: msg.body,
      );
    }
  } else {
    notes.add('no fully foreign chats for inject test');
  }

  // wallet_transactions insert
  final wt = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/wallet_transactions',
    token: buyerTok,
    body: {
      'wallet_id': buyerId,
      'amount': 50,
      'type': 'credit',
    },
  );
  rec(
    surface: 'LEDGER',
    attack: 'INSERT wallet_transactions credit 50',
    identity: 'buyer',
    result: '${wt.statusCode} ${clip(wt.body, 200)}',
    impact: wt.statusCode < 300 ? 'ledger write' : 'blocked',
    evidence: wt.body,
  );

  final report = {
    'pass': 3,
    'project': stagingRef,
    'at': DateTime.now().toUtc().toIso8601String(),
    'findings': findings,
    'notes': notes,
    'cleanup': cleanup,
    'pay_urls_file': '$outDir/pass3_pay_urls.json',
    'matrix': matrix,
  };
  File('$outDir/pass3_raw.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  stdout.writeln(
    'PASS3 done findings=${findings.length} matrix=${matrix.length}',
  );
}
