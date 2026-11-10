// ignore_for_file: avoid_print
/// Pass 4 — verificação anti-FP + superfícies em falta + checkout reserva_pendente.
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

void row(String surface, String attack, String identity, String result, String impact, String severity, [Object? evidence]) {
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

String clip(Object? v, [int n = 600]) {
  final s = v is String ? v : jsonEncode(v);
  return s.length <= n ? s : '${s.substring(0, n)}…';
}

Future<Map<String, dynamic>> req(String method, String u, Map<String, String> h, [Object? body]) async {
  late http.Response r;
  switch (method) {
    case 'POST':
      r = await http.post(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body));
      break;
    case 'PATCH':
      r = await http.patch(Uri.parse(u), headers: h, body: body == null ? null : jsonEncode(body));
      break;
    case 'GET':
      r = await http.get(Uri.parse(u), headers: h);
      break;
    default:
      r = await http.delete(Uri.parse(u), headers: h);
  }
  dynamic p;
  try {
    p = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    p = r.body;
  }
  return {'http': r.statusCode, 'body': p, 'text': r.body};
}

Map<String, String> hdr(String apikey, String bearer) => {
      'apikey': apikey,
      'Authorization': 'Bearer $bearer',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

String? idOf(dynamic body) {
  if (body is List && body.isNotEmpty && body.first is Map) {
    final s = '${(body.first as Map)['id'] ?? ''}'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }
  if (body is Map && body['id'] != null) {
    final s = '${body['id']}'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }
  return null;
}

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) exit(2);
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final c = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerJwt = await c.signIn(email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'), password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'));
  final sellerJwt = await c.signIn(email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'), password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'));
  final bUid = await c.userIdForAccessToken(buyerJwt);
  final sUid = await c.userIdForAccessToken(sellerJwt);
  final buyH = hdr(anon, buyerJwt);
  final selH = hdr(anon, sellerJwt);
  final anonH = hdr(anon, anon);
  final svcH = hdr(svc, svc);
  final outDir = Directory('tool/redteam_cega_indep_20260830T1605/out');

  // OpenAPI with service apikey=service
  final oa = await http.get(Uri.parse('$url/rest/v1/'), headers: {
    ...svcH,
    'Accept': 'application/openapi+json',
  });
  var rpcs = <String>[];
  var tables = <String>[];
  try {
    final spec = jsonDecode(oa.body);
    if (spec is Map && spec['paths'] is Map) {
      final paths = (spec['paths'] as Map).keys.map((k) => '$k').toList();
      tables = paths.where((p) => !p.startsWith('/rpc/') && p != '/').map((p) => p.replaceFirst('/', '')).toList()..sort();
      rpcs = paths.where((p) => p.startsWith('/rpc/')).map((p) => p.substring(5)).toList()..sort();
    } else {
      notes.add('openapi body ${clip(oa.body, 200)}');
    }
  } catch (err) {
    notes.add('oa ${oa.statusCode} $err ${clip(oa.body, 150)}');
  }
  File('${outDir.path}/openapi_svc2.json').writeAsStringSync(jsonEncode({'http': oa.statusCode, 'nTables': tables.length, 'nRpcs': rpcs.length, 'rpcs': rpcs, 'tables': tables}));

  // Offer row
  final offer = await req('GET', '$url/rest/v1/product_offers?id=eq.65c6e28c-e42b-43dd-b481-2872f6da77f0&select=id,status,amount,responded_at,offered_by,buyer_id,seller_id', buyH);
  row('OFFERS', 'GET offer after accepted-insert', 'buyer', clip(offer['body'], 300), 'status real', 'info', offer['body']);

  // stripe_checkout_events leak
  final evB = await req('GET', '$url/rest/v1/stripe_checkout_events?select=id,session_id,order_id,buyer_id,event,created_at&limit=30', buyH);
  final evB2email = 'rt1605-b2-$stamp@staging.fleaber.invalid';
  String? b2Jwt;
  String? b2Uid;
  try {
    b2Jwt = await c.signIn(email: evB2email, password: 'Rt1605!pass');
    b2Uid = await c.userIdForAccessToken(b2Jwt);
  } catch (err) {
    notes.add('b2 $err');
  }
  final ev2 = b2Jwt == null ? null : await req('GET', '$url/rest/v1/stripe_checkout_events?select=id,session_id,order_id,buyer_id,event&limit=30', hdr(anon, b2Jwt));
  final evA = await req('GET', '$url/rest/v1/stripe_checkout_events?select=id,order_id,buyer_id,event&limit=10', anonH);
  var foreignEv = 0;
  if (evB['body'] is List) {
    for (final r in evB['body'] as List) {
      if (r is! Map) continue;
      final bid = '${r['buyer_id'] ?? ''}';
      if (bid.isNotEmpty && bid != 'null' && bid != bUid) foreignEv++;
    }
  }
  var b2n = ev2 != null && ev2['body'] is List ? (ev2['body'] as List).length : -1;
  row('STRIPE SESSION', 'buyer SELECT stripe_checkout_events', 'buyer', 'http=${evB['http']} n=${evB['body'] is List ? (evB['body'] as List).length : 0} foreign_buyer_id=$foreignEv sample=${clip(evB['body'], 250)}', foreignEv > 0 ? 'eventos alheios' : 'próprios ou buyer_id nulo', foreignEv > 0 ? 'P1' : 'info');
  row('STRIPE SESSION', 'B2 SELECT stripe_checkout_events', 'buyer2', 'http=${ev2?['http']} n=$b2n ${clip(ev2?['body'], 200)}', b2n > 0 ? 'conta nova viu events' : 'vazio', b2n > 0 ? 'P1' : 'info');
  row('STRIPE SESSION', 'anon SELECT events', 'anon', 'http=${evA['http']} ${clip(evA['body'], 120)}', 'anon', 'info');
  if (foreignEv > 0) {
    find(id: 'P1-STRIPE-EVENTS-LEAK', sev: 'P1', title: 'Buyer lê stripe_checkout_events de outros buyer_id', actor: 'buyer', pre: 'eventos existentes', repro: 'GET /stripe_checkout_events', impact: 'session/order IDs alheios', state: 'ABERTO', evidence: evB['body']);
  }
  if (b2n > 0) {
    find(id: 'P1-STRIPE-EVENTS-B2', sev: 'P1', title: 'Conta nova lê stripe_checkout_events', actor: 'buyer2', pre: 'B2 sem compras', repro: 'GET /stripe_checkout_events', impact: 'telemetria checkout alheia', state: 'ABERTO', evidence: ev2?['body']);
  }

  // INSERT fake checkout event
  final evIns = await req('POST', '$url/rest/v1/stripe_checkout_events', buyH, {
    'session_id': 'cs_test_hostile_$stamp',
    'order_id': '6c4e2d3c-eb97-474c-94ea-cd22cd48cc03',
    'buyer_id': bUid,
    'event': 'checkout.session.completed',
    'detail': {'hostile': true},
  });
  row('STRIPE SESSION', 'INSERT fake event completed', 'buyer', 'http=${evIns['http']} ${clip(evIns['text'], 160)}', idOf(evIns['body']) != null ? 'evento forjado' : 'bloqueado', idOf(evIns['body']) != null ? 'P1' : 'info');
  if (idOf(evIns['body']) != null) {
    find(id: 'P1-STRIPE-EVENT-INSERT', sev: 'P1', title: 'JWT inseriu stripe_checkout_events', actor: 'buyer', pre: 'tabela events', repro: 'POST event=checkout.session.completed', impact: 'falsificar settle signal', state: 'ABERTO', evidence: evIns['body']);
  }

  // user_notifications + seller_device_tokens + chats
  for (final t in ['user_notifications', 'seller_device_tokens', 'seller_helpers', 'staff_action_logs', 'live_reservation_requests', 'live_raffles', 'live_raffle_winners', 'live_raffle_tickets', 'ps_pairing_sessions']) {
    final g = await req('GET', '$url/rest/v1/$t?select=*&limit=10', buyH);
    final g2 = b2Jwt == null ? null : await req('GET', '$url/rest/v1/$t?select=*&limit=10', hdr(anon, b2Jwt));
    final ga = await req('GET', '$url/rest/v1/$t?select=*&limit=5', anonH);
    row(t, 'SELECT *', 'buyer', 'http=${g['http']} ${clip(g['text'], 140)}', 'scope', 'info');
    row(t, 'SELECT *', 'buyer2', 'http=${g2?['http']} ${clip(g2?['text'], 120)}', 'scope', 'info');
    row(t, 'SELECT *', 'anon', 'http=${ga['http']} ${clip(ga['text'], 100)}', 'scope', 'info');
  }

  // Checkout reserva_pendente + server_amount_cents
  final prod = await req('POST', '$url/rest/v1/products', selH, {
    'seller_id': sUid,
    'title': 'RT1605ck $stamp',
    'price': 30.00,
    'quantity': 3,
    'list_on_marketplace': true,
    'image_urls': <dynamic>[],
  });
  final pid = idOf(prod['body']);
  String? oid;
  if (pid != null) {
    final o = await req('POST', '$url/rest/v1/orders', buyH, {
      'buyer_id': bUid,
      'seller_id': sUid,
      'product_id': pid,
      'quantity': 1,
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
      'status': 'reserva_pendente',
    });
    oid = idOf(o['body']);
    final st = await req('GET', '$url/rest/v1/orders?id=eq.$oid&select=id,status,contract_unit_cents,price_total,quantity,shipping_method', buyH);
    row('ORDERS', 'INSERT reserva_pendente 30€', 'buyer', '${clip(st['body'], 200)}', 'contrato', 'info', st['body']);
    if (oid != null) {
      final ck = await req('POST', '$url/functions/v1/create-payment-intent', buyH, {
        'buyer_id': bUid,
        'order_id': oid,
        'amount': 50,
        'item_price': 0.01,
        'quantity': 99,
        'shipping_method': 'hand',
        'protection_fee': 0,
        'shipping': 0,
      });
      final body = ck['body'];
      row('CHECKOUT', 'reserva_pendente amount=50', 'buyer', 'http=${ck['http']} ${clip(ck['text'], 400)}', 'server vs client', 'info', body);
      num? serverAmt;
      if (body is Map) {
        serverAmt = num.tryParse('${body['server_amount_cents'] ?? body['amount_total'] ?? ''}');
      }
      notes.add('serverAmt=$serverAmt keys=${body is Map ? body.keys.toList() : ck['http']}');
      if (serverAmt != null && serverAmt < 2000) {
        find(id: 'P0-UNDERPAY-SESSION', sev: 'P0', title: 'Session <20€ para artigo 30€', actor: 'buyer', pre: 'order 30€', repro: 'amount=50', impact: 'pagar menos', state: 'ABERTO', evidence: body);
      }
      // 10 concurrent checkout
      final burst = await Future.wait(List.generate(8, (_) => req('POST', '$url/functions/v1/create-payment-intent', buyH, {
            'buyer_id': bUid,
            'order_id': oid,
            'shipping_method': 'hand',
          })));
      final oks = burst.where((x) => x['http'] == 200).toList();
      final sids = oks.map((x) => x['body'] is Map ? '${(x['body'] as Map)['checkoutSessionId']}' : '').toSet();
      row('CHECKOUT', '8x concurrent same order', 'buyer', 'ok=${oks.length} sids=$sids reused=${oks.map((x) => x['body'] is Map ? (x['body'] as Map)['reused_session'] : null).toList()}', '1 session?', 'info');
    }
  }

  // Pass1 order observe
  final old = await req('GET', '$url/rest/v1/orders?id=eq.6c4e2d3c-eb97-474c-94ea-cd22cd48cc03&select=id,status,price_total,contract_unit_cents,amount_paid_cents,stripe_checkout_session_id,stripe_payment_intent_id,quantity', svcH);
  row('STRIPE SESSION', 'observe pass1 order', 'service_observe', clip(old['body'], 300), 'captura?', 'info', old['body']);

  // Storage download as B2 of buyer proof folder object
  if (b2Jwt != null) {
    final list = await req('POST', '$url/storage/v1/object/list/fleaber_private', hdr(anon, b2Jwt), {
      'prefix': 'order_proofs/$bUid/',
      'limit': 5,
    });
    row('STORAGE', 'B2 list order_proofs of buyer1', 'buyer2', 'http=${list['http']} ${clip(list['text'], 180)}', 'list alheio', (list['body'] is List && (list['body'] as List).isNotEmpty) ? 'P1' : 'info');
    if (list['body'] is List && (list['body'] as List).isNotEmpty) {
      find(id: 'P1-STORAGE-LIST-FOREIGN', sev: 'P1', title: 'B2 listou provas do buyer1', actor: 'buyer2', pre: 'order_proofs prefix', repro: 'storage list order_proofs/{buyer1}/', impact: 'provas alheias', state: 'ABERTO', evidence: list['body']);
    }
  }

  // Live reservation
  final li = await req('GET', '$url/rest/v1/live_items?select=id,live_id,quantity,price&limit=5', selH);
  row('LIVE ITEMS', 'SELECT', 'seller', 'http=${li['http']} ${clip(li['text'], 180)}', 'items', 'info');
  if (li['body'] is List && (li['body'] as List).isNotEmpty) {
    final item = li['body'] as List;
    final iid = '${item.first['id']}';
    final lid = '${item.first['live_id']}';
    final resIns = await req('POST', '$url/rest/v1/live_reservation_requests', buyH, {
      'live_item_id': iid,
      'live_id': lid,
      'buyer_id': bUid,
      'requested_qty': 99,
      'status': 'accepted',
    });
    row('WAITLIST / QUEUE', 'INSERT reservation qty=99 accepted', 'buyer', 'http=${resIns['http']} ${clip(resIns['text'], 180)}', 'bypass fila', idOf(resIns['body']) != null ? 'P1' : 'info', clip(resIns['body'], 200));
  }

  // create-mux-live as seller
  final mux = await req('POST', '$url/functions/v1/create-mux-live', selH, {'title': 'RT1605 $stamp live'});
  row('MUX', 'create-mux-live seller', 'seller', 'http=${mux['http']} ${clip(mux['text'], 250)}', 'stream key no body?', 'info', mux['body'] is Map ? (mux['body'] as Map).keys.toList() : mux['http']);
  final muxB = await req('POST', '$url/functions/v1/create-mux-live', buyH, {'title': 'RT1605 buyer live'});
  row('MUX', 'create-mux-live buyer', 'buyer', 'http=${muxB['http']} ${clip(muxB['text'], 160)}', 'buyer live', 'info');

  // RPC names from a static sensitive set extra
  const extra = [
    'batata_accept_product_offer',
    'batata_accept_reservation',
    'batata_confirm_order_received',
    'batata_seller_mark_paid',
    'batata_apply_bundle',
    'batata_wallet_payout_finish',
    'batata_settle_order_from_stripe',
    'batata_ingest_ocr_reservation',
    'batata_ps_create_pairing',
    'batata_validate_seller_device_token',
    'batata_live_reservation_force_pending_manual',
    'batata_create_live_tip_pending',
    'batata_staff_has_permission',
    'batata_is_admin',
    'batata_order_wallet_base_eur',
  ];
  for (final fn in extra) {
    final r = await req('POST', '$url/rest/v1/rpc/$fn', buyH, {
      'p_order_id': oid ?? '00000000-0000-0000-0000-000000000001',
      'p_offer_id': '00000000-0000-0000-0000-000000000001',
      'p_live_id': '00000000-0000-0000-0000-000000000001',
      'p_live_item_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 1,
      'p_permission': 'can_manage_payouts',
      'p_seller_id': sUid,
      'p_token': 'aaaa',
    });
    row('RPC', fn, 'buyer', 'http=${r['http']} ${clip(r['text'], 120)}', r['http'] == 200 ? 'exec' : 'negado', 'info');
  }

  // Dual payout same key
  final k = 'rt1605-samekey-$stamp-xx';
  final p1 = await req('POST', '$url/functions/v1/create-connect-account', selH, {'amount': 1, 'idempotency_key': k});
  final p2 = await req('POST', '$url/functions/v1/create-connect-account', selH, {'amount': 1, 'idempotency_key': k});
  row('PAYOUT', 'retry same idempotency_key 1c', 'seller', 'a=${p1['http']} ${clip(p1['text'], 120)} b=${p2['http']} ${clip(p2['text'], 120)}', 'idempotent?', 'info');

  final frozen = {
    'FROZEN_AT': DateTime.now().toUtc().toIso8601String(),
    'pass': 4,
    'project': projectMust,
    'findings': findings,
    'matrix': matrix,
    'notes': notes,
    'openapi_tables': tables.length,
    'openapi_rpcs': rpcs.length,
  };
  File('${outDir.path}/pass4.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(frozen));
  stdout.writeln('PASS4 findings=${findings.length} tables=${tables.length} rpcs=${rpcs.length}');
  for (final f in findings) {
    stdout.writeln('${f['severity']} ${f['id']} ${f['title']}');
  }
}
