/// Pass 3 — mesma classe noutro módulo + RPCs com IDs reais + saturação.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stamp = '20260829T1635';
const stagingRef = 'fxdknzrqjenzqcvnwqqq';

final probes = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];

void note(String s) => stderr.writeln('[B3] $s');
String clip(String s, [int n = 500]) =>
    s.length <= n ? s : '${s.substring(0, n)}…';

void probe(String id, String title, Map<String, dynamic> d) =>
    probes.add({'id': id, 'title': title, ...d});

void finding(Map<String, dynamic> f) {
  findings.add(f);
  note('FINDING ${f['severity']} ${f['id']} ${f['title']}');
}

Future<http.Response> rest(
  LiveOpsStagingClient c, {
  required String method,
  required String path,
  required String token,
  Object? body,
  bool service = false,
}) {
  final headers = <String, String>{
    'apikey': service ? c.serviceRoleKey : c.anonKey,
    'Authorization': 'Bearer ${service ? c.serviceRoleKey : token}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final uri = Uri.parse('${c.url}$path');
  final enc = body == null ? null : jsonEncode(body);
  if (method == 'GET') return http.get(uri, headers: headers);
  if (method == 'PATCH') return http.patch(uri, headers: headers, body: enc);
  return http.post(uri, headers: headers, body: enc);
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final c = LiveOpsStagingClient(
    url: normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL')),
    anonKey: envRequire(env, 'SUPABASE_ANON_KEY'),
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  if (!c.url.contains(stagingRef)) exit(2);
  final buyerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  const liveItemId = 'a4e89203-f0d6-4df2-a76a-e01435065b5f';
  const liveId = '5dd5cfd2-63b1-4cd8-82b1-c888e9dc5234';
  const victimId = '78129954-383e-4b69-8dad-f81ae5c692d8';
  const forcedOrder = '59f1272e-6e50-430c-b574-6698a693b54f';

  // Buyer mark sold on real live item
  final mk = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_mark_live_item_sold',
    token: buyerTok,
    body: {'p_live_item_id': liveItemId},
  );
  probe('p3.mark.buyer', 'buyer mark_live_item_sold ID real', {
    'status': mk.statusCode,
    'body': clip(mk.body),
  });
  if (mk.statusCode == 200 && mk.body.contains('"ok": true')) {
    finding({
      'id': 'RTB-B-AUTH-05',
      'title': 'Buyer marca live_item vendido',
      'severity': 'P1',
      'actor': 'buyer JWT',
      'request': 'RPC batata_mark_live_item_sold',
      'result': clip(mk.body),
      'impact': 'Stock live destruído por não-dono.',
    });
  }

  final raffles = await c.select('live_raffles', limit: 5);
  probe('p3.raffles', 'raffles observe', {
    'n': raffles.length,
    'ids': raffles.map((e) => e['id']).toList(),
  });
  if (raffles.isNotEmpty) {
    final rid = raffles.first['id'];
    final draw = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/rpc/batata_draw_live_raffle_winners',
      token: buyerTok,
      body: {'p_raffle_id': rid},
    );
    final act = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/rpc/batata_activate_live_raffle',
      token: buyerTok,
      body: {'p_raffle_id': rid},
    );
    probe('p3.draw.buyer', 'buyer draw raffle real', {
      'status': draw.statusCode,
      'body': clip(draw.body),
    });
    probe('p3.activate.buyer', 'buyer activate raffle real', {
      'status': act.statusCode,
      'body': clip(act.body),
    });
    if (draw.statusCode == 200 && !draw.body.toLowerCase().contains('not')) {
      finding({
        'id': 'RTB-B-AUTH-06',
        'title': 'Buyer sorteia rifa alheia',
        'severity': 'P1',
        'actor': 'buyer JWT',
        'request': 'RPC batata_draw_live_raffle_winners',
        'result': clip(draw.body),
        'impact': 'Autoridade de rifa.',
      });
    }
  }

  // Seller reservation accepted for victim (same identity class)
  final resIns = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/live_reservation_requests',
    token: sellerTok,
    body: {
      'live_id': liveId,
      'live_item_id': liveItemId,
      'seller_id': sellerId,
      'buyer_id': victimId,
      'requested_qty': 1,
      'status': 'accepted',
      'source': 'fleaber_live',
    },
  );
  probe('p3.res.victim', 'seller INSERT reservation accepted para vítima', {
    'status': resIns.statusCode,
    'body': clip(resIns.body),
  });

  // Seller reviews the victim on forced order
  final srv = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/reviews',
    token: sellerTok,
    body: {
      'order_id': forcedOrder,
      'target_id': victimId,
      'buyer_id': sellerId,
      'stars': 1,
      'comment': 'seller-on-forced-victim',
      'author_role': 'vendedor',
      'target_type': 'buyer',
    },
  );
  probe('p3.review.seller_on_victim', 'seller 1★ na vítima da venda forçada', {
    'status': srv.statusCode,
    'body': clip(srv.body),
  });
  if (srv.statusCode < 300) {
    finding({
      'id': 'RTB-B-REP-04',
      'title': 'Seller deixa 1★ na vítima de venda forçada',
      'severity': 'P1',
      'actor': 'seller JWT',
      'request': 'POST reviews author_role=vendedor',
      'result': clip(srv.body),
      'impact': 'Dano reputacional à conta que nunca comprou.',
    });
  }

  // lives INSERT as buyer
  final liveIns = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/lives',
    token: buyerTok,
    body: {
      'seller_id': buyerId,
      'title': 'rtb-b hijack',
      'status': 'live',
      'is_active': true,
    },
  );
  probe('p3.lives.insert.buyer', 'buyer INSERT lives', {
    'status': liveIns.statusCode,
    'body': clip(liveIns.body),
  });

  // process reservation as buyer accept
  final proc = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_process_live_reservation_request',
    token: buyerTok,
    body: {
      'p_request_id': '4a013d5d-3110-4520-9662-f708c752cd80',
      'p_action': 'accept',
    },
  );
  probe('p3.res.process.buyer', 'buyer process accept reserva', {
    'status': proc.statusCode,
    'body': clip(proc.body),
  });

  // system message on real live
  final sys = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/rpc/batata_live_system_message',
    token: buyerTok,
    body: {'p_live_id': liveId, 'p_body': 'rtb-b fomo'},
  );
  probe('p3.sysmsg', 'buyer system message em live alheia', {
    'status': sys.statusCode,
    'body': clip(sys.body),
  });

  // join raffle
  if (raffles.isNotEmpty) {
    final join = await rest(
      c,
      method: 'POST',
      path: '/rest/v1/rpc/batata_join_live_raffle',
      token: buyerTok,
      body: {'p_raffle_id': raffles.first['id']},
    );
    probe('p3.raffle.join', 'buyer join raffle', {
      'status': join.statusCode,
      'body': clip(join.body),
    });
  }

  // bundles write
  final bun = await rest(
    c,
    method: 'POST',
    path: '/rest/v1/product_bundles',
    token: buyerTok,
    body: {
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'status': 'accepted',
    },
  );
  probe('p3.bundle.insert', 'buyer INSERT bundle accepted loja alheia', {
    'status': bun.statusCode,
    'body': clip(bun.body),
  });

  File('tool/redteam_blind_b_${stamp}_pass3.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'pass': 3,
      'findings': findings,
      'probes': probes,
    }),
  );
  note('pass3 findings=${findings.length}');
}
