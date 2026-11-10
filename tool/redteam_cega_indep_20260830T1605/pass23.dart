// ignore_for_file: avoid_print
/// Auditoria cega 20260830T1605 — PASS 2 variantes + PASS 3 composição/races.
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

String clip(Object? v, [int n = 500]) {
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

Map<String, String> hdr(String anon, {String? jwt, String? svc}) {
  return {
    'apikey': anon,
    'Authorization': 'Bearer ${svc ?? jwt ?? anon}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
}

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

bool persisted(dynamic body) => idOf(body) != null;

Future<void> main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) {
    stderr.writeln('ABORT');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
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
  final buyH = hdr(anon, jwt: buyerJwt);
  final selH = hdr(anon, jwt: sellerJwt);
  final anonH = hdr(anon);
  final svcH = hdr(anon, svc: svc);
  final outDir = Directory('tool/redteam_cega_indep_20260830T1605/out');
  outDir.createSync(recursive: true);

  // ---- OpenAPI via service_role ----
  final oa = await http.get(Uri.parse('$url/rest/v1/'), headers: {
    ...svcH,
    'Accept': 'application/openapi+json',
  });
  var tables = <String>[];
  var rpcs = <String>[];
  try {
    final spec = jsonDecode(oa.body) as Map<String, dynamic>;
    final paths = (spec['paths'] as Map?)?.keys.map((k) => '$k').toList() ?? [];
    tables = paths.where((p) => !p.startsWith('/rpc/') && p != '/').map((p) => p.replaceFirst('/', '')).toList()..sort();
    rpcs = paths.where((p) => p.startsWith('/rpc/')).map((p) => p.substring(5)).toList()..sort();
  } catch (err) {
    notes.add('openapi parse: $err http=${oa.statusCode} ${clip(oa.body, 120)}');
  }
  File('${outDir.path}/openapi_svc.json').writeAsStringSync(jsonEncode({
    'http': oa.statusCode,
    'tables': tables,
    'rpcs': rpcs,
  }));
  notes.add('OpenAPI svc tables=${tables.length} rpcs=${rpcs.length}');

  // RPC GRANT sweep: empty + dummy uuid as buyer and anon for ALL rpcs
  final rpcSweep = <Map<String, dynamic>>[];
  for (final fn in rpcs) {
    final dummy = {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_user_id': sUid,
      'p_wallet_id': bUid,
      'p_amount': 1,
      'p_amount_cents': 100,
      'p_email': 'x@y.z',
      'p_live_id': '00000000-0000-0000-0000-000000000001',
      'p_product_id': '00000000-0000-0000-0000-000000000001',
    };
    final b = await req('POST', '$url/rest/v1/rpc/$fn', buyH, dummy);
    final a = await req('POST', '$url/rest/v1/rpc/$fn', anonH, dummy);
    rpcSweep.add({'fn': fn, 'buyer': b['http'], 'anon': a['http'], 'bt': clip(b['text'], 80), 'at': clip(a['text'], 80)});
  }
  File('${outDir.path}/rpc_sweep.json').writeAsStringSync(jsonEncode(rpcSweep));
  final privHit = rpcSweep.where((r) {
    final fn = '${r['fn']}';
    final httpB = r['buyer'] as int;
    if (httpB != 200 && httpB != 201) return false;
    return fn.contains('wallet') ||
        fn.contains('payout') ||
        fn.contains('credit') ||
        fn.contains('settle') ||
        fn.contains('refund') ||
        fn.contains('admin') ||
        fn.contains('prize');
  }).toList();
  notes.add('privileged rpc buyer 200: ${privHit.map((e) => e['fn']).toList()}');
  for (final h in privHit) {
    find(
      id: 'P0-RPC-SWEEP-${h['fn']}',
      sev: 'P0',
      title: 'RPC privilegiada ${h['fn']} HTTP 200 JWT buyer',
      actor: 'buyer',
      pre: 'OpenAPI',
      repro: 'POST /rpc/${h['fn']}',
      impact: 'EXECUTE privilegiado',
      state: 'ABERTO',
      evidence: h,
    );
  }

  // ---- New product stock=2 for variants; stock=1 for race ----
  final p2 = await req('POST', '$url/rest/v1/products', selH, {
    'seller_id': sUid,
    'title': 'RT1605p2 $stamp',
    'price': 25.00,
    'quantity': 5,
    'list_on_marketplace': true,
    'image_urls': <dynamic>[],
  });
  final pRace = await req('POST', '$url/rest/v1/products', selH, {
    'seller_id': sUid,
    'title': 'RT1605race $stamp',
    'price': 18.00,
    'quantity': 1,
    'list_on_marketplace': true,
    'image_urls': <dynamic>[],
  });
  final productId = idOf(p2['body']);
  final racePid = idOf(pRace['body']);
  notes.add('p2=$productId race=$racePid');

  // Disposable second buyer
  final b2email = 'rt1605-b2-$stamp@staging.fleaber.invalid';
  const b2pass = 'Rt1605!pass';
  String? b2Uid;
  String? b2Jwt;
  try {
    b2Uid = await c.createAdminUser(email: b2email, password: b2pass);
    await req('POST', '$url/rest/v1/profiles', svcH, {
      'id': b2Uid,
      'display_name': 'RT1605 B2',
      'user_type': 'comprador',
    });
    b2Jwt = await c.signIn(email: b2email, password: b2pass);
  } catch (err) {
    notes.add('b2 create: $err');
    // maybe exists
    try {
      b2Jwt = await c.signIn(email: b2email, password: b2pass);
      b2Uid = await c.userIdForAccessToken(b2Jwt);
    } catch (err2) {
      notes.add('b2 signin: $err2');
    }
  }
  final b2H = b2Jwt == null ? null : hdr(anon, jwt: b2Jwt);

  // ---- Offer self-accept ----
  if (productId != null) {
    final off = await req('POST', '$url/rest/v1/product_offers', buyH, {
      'product_id': productId,
      'buyer_id': bUid,
      'seller_id': sUid,
      'amount': 0.50,
      'list_price': 25.00,
      'offered_by': 'buyer',
      'status': 'accepted',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    });
    row('OFFERS', 'INSERT offer status=accepted amount=0.50', 'buyer', 'http=${off['http']} ${clip(off['text'], 180)}', persisted(off['body']) ? 'persistiu' : 'bloqueado', 'info', clip(off['body'], 220));
    var offerId = idOf(off['body']);
    if (offerId == null) {
      final off2 = await req('POST', '$url/rest/v1/product_offers', buyH, {
        'product_id': productId,
        'buyer_id': bUid,
        'seller_id': sUid,
        'amount': 0.50,
        'list_price': 25.00,
        'offered_by': 'buyer',
        'status': 'pending',
      });
      offerId = idOf(off2['body']);
      row('OFFERS', 'INSERT offer pending 0.50', 'buyer', 'http=${off2['http']} ${clip(off2['text'], 160)}', 'pending', 'info');
      if (offerId != null) {
        final acc = await req('PATCH', '$url/rest/v1/product_offers?id=eq.$offerId', buyH, {
          'status': 'accepted',
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        });
        final got = await req('GET', '$url/rest/v1/product_offers?id=eq.$offerId&select=id,status,amount,responded_at', buyH);
        row('OFFERS', 'buyer PATCH accepted', 'buyer', 'http=${acc['http']} ${clip(got['body'], 160)}', 'auto-aceite?', 'info', got['body']);
        if (got['body'] is List && (got['body'] as List).isNotEmpty) {
          final st = '${(got['body'] as List).first['status']}';
          if (st == 'accepted') {
            find(id: 'P0-OFFER-SELF-ACCEPT', sev: 'P0', title: 'Buyer aceitou a própria oferta', actor: 'buyer', pre: 'product_offers', repro: 'PATCH status=accepted', impact: 'preço 0.50 sem seller', state: 'ABERTO', evidence: got['body']);
          }
        }
      }
    } else {
      final st = off['body'] is List ? '${(off['body'] as List).first['status']}' : '${(off['body'] as Map)['status']}';
      if (st == 'accepted') {
        find(id: 'P0-OFFER-INSERT-ACCEPTED', sev: 'P0', title: 'Buyer inseriu oferta já accepted', actor: 'buyer', pre: 'product_offers', repro: 'POST status=accepted amount=0.50', impact: 'preço cliente', state: 'ABERTO', evidence: off['body']);
      }
    }
    if (offerId != null) {
      final ord = await req('POST', '$url/rest/v1/orders', buyH, {
        'buyer_id': bUid,
        'seller_id': sUid,
        'product_id': productId,
        'product_offer_id': offerId,
        'quantity': 1,
        'payment_method': 'Pagamento na app',
        'shipping_method': 'hand',
        'status': 'pendente',
      });
      final oid = idOf(ord['body']);
      Map<String, dynamic>? fin;
      if (oid != null) {
        final g = await req('GET', '$url/rest/v1/orders?id=eq.$oid&select=id,contract_unit_cents,price_total,product_offer_id,status', buyH);
        if (g['body'] is List && (g['body'] as List).isNotEmpty) {
          fin = Map<String, dynamic>.from((g['body'] as List).first as Map);
        }
      }
      row('PRICE / CONTRACT', 'order com offer hostil', 'buyer', 'http=${ord['http']} final=$fin', (fin != null && fin['contract_unit_cents'] == 50) ? 'contrato 0.50' : 'não selou 0.50', (fin != null && fin['contract_unit_cents'] == 50) ? 'P0' : 'info', fin ?? clip(ord['text'], 180));
      if (fin != null && fin['contract_unit_cents'] == 50) {
        find(id: 'P0-OFFER-CONTRACT-50C', sev: 'P0', title: 'Contrato selado a 50 cêntimos via oferta', actor: 'buyer', pre: 'produto 25€', repro: 'order product_offer_id', impact: 'pagar menos', state: 'ABERTO', evidence: fin);
      }
    }
  }

  // ---- Shipping switch carrier → hand ----
  if (productId != null) {
    final o = await req('POST', '$url/rest/v1/orders', buyH, {
      'buyer_id': bUid,
      'seller_id': sUid,
      'product_id': productId,
      'quantity': 1,
      'payment_method': 'Pagamento na app',
      'shipping_method': 'carrier',
      'status': 'pendente',
    });
    final oid = idOf(o['body']);
    if (oid != null) {
      final patch = await req('PATCH', '$url/rest/v1/orders?id=eq.$oid', buyH, {'shipping_method': 'hand'});
      final got = await req('GET', '$url/rest/v1/orders?id=eq.$oid&select=id,shipping_method,contract_unit_cents', buyH);
      final ship = got['body'] is List && (got['body'] as List).isNotEmpty ? '${(got['body'] as List).first['shipping_method']}' : '?';
      row('CHECKOUT', 'PATCH shipping carrier→hand', 'buyer', 'http=${patch['http']} ship=$ship', ship == 'hand' ? 'selo quebrado' : 'selo manteve', ship == 'hand' ? 'P1' : 'info', got['body']);
      if (ship == 'hand') {
        find(id: 'P1-SHIP-UNSEAL', sev: 'P1', title: 'Buyer mudou portes de transportadora para mão', actor: 'buyer', pre: 'order carrier', repro: 'PATCH shipping_method=hand', impact: 'pagar menos portes/proteção', state: 'ABERTO', evidence: got['body']);
      }
      // checkout capture full JSON
      final ck = await req('POST', '$url/functions/v1/create-payment-intent', buyH, {
        'buyer_id': bUid,
        'order_id': oid,
        'amount': 50,
        'shipping_method': 'hand',
        'item_price': 0.01,
        'quantity': 9,
      });
      row('CHECKOUT', 'full JSON amount=50 vs server', 'buyer', 'http=${ck['http']} ${clip(ck['text'], 280)}', 'autoridade servidor', 'info', ck['body']);
      final amt = ck['body'] is Map ? (ck['body'] as Map)['server_amount_cents'] ?? (ck['body'] as Map)['amount_total'] : null;
      notes.add('checkout server_amount_cents=$amt body_keys=${ck['body'] is Map ? (ck['body'] as Map).keys.toList() : ck['http']}');
      if (amt is num && amt <= 500 && amt > 0) {
        find(id: 'P0-CHECKOUT-UNDERPAY', sev: 'P0', title: 'Session Stripe ≤5€ para artigo 25€', actor: 'buyer', pre: 'order 25€', repro: 'create-payment-intent amount=50', impact: 'pagar menos', state: 'ABERTO', evidence: ck['body']);
      }
    }
  }

  // Unsealed shipping insert
  if (productId != null) {
    final o = await req('POST', '$url/rest/v1/orders', buyH, {
      'buyer_id': bUid,
      'seller_id': sUid,
      'product_id': productId,
      'quantity': 1,
      'payment_method': 'Pagamento na app',
      'shipping_method': 'gratis_hostile',
      'status': 'pendente',
    });
    final oid = idOf(o['body']);
    row('CHECKOUT', 'INSERT shipping=gratis_hostile', 'buyer', 'http=${o['http']} id=$oid ${clip(o['text'], 120)}', 'selo inválido', 'info');
    if (oid != null) {
      final ck = await req('POST', '$url/functions/v1/create-payment-intent', buyH, {
        'buyer_id': bUid,
        'order_id': oid,
        'amount': 50,
        'shipping_method': 'hand',
      });
      row('CHECKOUT', 'checkout order portes lixo + body hand', 'buyer', 'http=${ck['http']} ${clip(ck['text'], 200)}', 'body manda portes?', 'info', clip(ck['body'], 250));
    }
  }

  // ---- Helpers ----
  final help = await req('POST', '$url/rest/v1/seller_helpers', buyH, {
    'seller_id': sUid,
    'helper_user_id': bUid,
    'invited_by': bUid,
    'display_name': 'hostile',
    'active': true,
    'invitation_status': 'accepted',
    'permissions': {'can_manage_payouts': true, 'can_manage_raffles': true},
  });
  row('AUTH / PROFILES', 'buyer INSERT helper na loja alheia', 'buyer', 'http=${help['http']} ${clip(help['text'], 160)}', persisted(help['body']) ? 'staff hijack' : 'bloqueado', persisted(help['body']) ? 'P1' : 'info');
  if (persisted(help['body'])) {
    find(id: 'P1-HELPER-INSERT', sev: 'P1', title: 'Buyer inseriu-se como helper', actor: 'buyer', pre: 'seller_helpers', repro: 'POST helper_user_id=self seller_id=alheio', impact: 'autoridade seller', state: 'ABERTO', evidence: help['body']);
  }

  // Seller invites buyer then buyer escalates permissions
  final inv = await req('POST', '$url/rest/v1/seller_helpers', selH, {
    'seller_id': sUid,
    'helper_user_id': bUid,
    'invited_by': sUid,
    'display_name': 'lab helper',
    'active': true,
    'invitation_status': 'pending',
    'permissions': {'can_manage_reservations': true, 'can_manage_payouts': false},
  });
  final hid = idOf(inv['body']);
  row('AUTH / PROFILES', 'seller invite helper pending', 'seller', 'http=${inv['http']} id=$hid', 'fixture', 'info');
  if (hid != null) {
    final acc = await req('PATCH', '$url/rest/v1/seller_helpers?id=eq.$hid', buyH, {
      'invitation_status': 'accepted',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
      'permissions': {'can_manage_payouts': true, 'can_manage_raffles': true, 'can_manage_helpers': true},
      'active': true,
    });
    final got = await req('GET', '$url/rest/v1/seller_helpers?id=eq.$hid&select=id,invitation_status,permissions,active', buyH);
    row('AUTH / PROFILES', 'helper PATCH permissions payouts=true', 'buyer', 'http=${acc['http']} ${clip(got['body'], 200)}', 'escalada perms', 'info', got['body']);
    if (got['body'] is List && (got['body'] as List).isNotEmpty) {
      final perms = (got['body'] as List).first['permissions'];
      if (perms is Map && perms['can_manage_payouts'] == true) {
        find(id: 'P1-HELPER-PERM-ESCALATE', sev: 'P1', title: 'Helper auto-concedeu can_manage_payouts', actor: 'buyer', pre: 'convite pending', repro: 'PATCH permissions no accept', impact: 'autoridade payout', state: 'ABERTO', evidence: got['body']);
      }
    }
  }

  // ---- Storage deep ----
  for (final prefix in [
    'order_disputes/',
    'order_proofs/',
    'chat_uploads/',
    'order_disputes/$sUid/',
    'order_proofs/$bUid/',
  ]) {
    final list = await req('POST', '$url/storage/v1/object/list/fleaber_private', buyH, {'prefix': prefix, 'limit': 20});
    final n = list['body'] is List ? (list['body'] as List).length : 0;
    row('STORAGE', 'list fleaber_private $prefix', 'buyer', 'http=${list['http']} n=$n ${clip(list['text'], 140)}', n > 0 ? 'object names' : 'vazio/negado', 'info', clip(list['body'], 180));
  }
  if (b2H != null) {
    final list = await req('POST', '$url/storage/v1/object/list/fleaber_private', b2H, {
      'prefix': 'order_disputes/$sUid/',
      'limit': 50,
    });
    row('STORAGE', 'B2 lista order_disputes do seller lab', 'buyer2', 'http=${list['http']} ${clip(list['text'], 160)}', 'cross-user storage', 'info', clip(list['body'], 200));
  }

  // ---- stripe_checkout_events / notifications ----
  for (final t in ['stripe_checkout_events', 'notifications', 'device_tokens', 'ps_pairing_sessions', 'ps_ingest_audit', 'live_tips', 'reviews_public_ratings']) {
    final g = await req('GET', '$url/rest/v1/$t?select=*&limit=5', buyH);
    final a = await req('GET', '$url/rest/v1/$t?select=*&limit=5', anonH);
    row(t, 'SELECT', 'buyer', 'http=${g['http']} ${clip(g['text'], 120)}', 'leitura', 'info');
    row(t, 'SELECT', 'anon', 'http=${a['http']} ${clip(a['text'], 100)}', 'leitura', 'info');
  }

  // lives public cols
  final lives = await req('GET', '$url/rest/v1/lives?select=id,status,seller_id,mux_playback_id,title&limit=3', buyH);
  row('LIVE', 'SELECT lives sem stream_key', 'buyer', 'http=${lives['http']} ${clip(lives['text'], 160)}', 'catalogo', 'info');

  // ---- Cross-user order/dispute with B2 ----
  if (b2H != null && productId != null) {
    final gOrd = await req('GET', '$url/rest/v1/orders?select=id,buyer_id,seller_id,price_total,status&limit=20', b2H);
    var foreign = 0;
    if (gOrd['body'] is List) {
      for (final r in gOrd['body'] as List) {
        if (r is Map && '${r['buyer_id']}' != b2Uid && '${r['seller_id']}' != b2Uid) foreign++;
      }
    }
    row('ORDERS', 'B2 SELECT orders', 'buyer2', 'http=${gOrd['http']} rows=${gOrd['body'] is List ? (gOrd['body'] as List).length : 0} foreign=$foreign', foreign > 0 ? 'cross-user orders' : 'vazio/scoped', foreign > 0 ? 'P1' : 'info');
    if (foreign > 0) {
      find(id: 'P1-ORDER-LEAK-B2', sev: 'P1', title: 'Buyer2 leu orders de outros', actor: 'buyer2', pre: 'conta nova', repro: 'GET /orders', impact: 'privacidade/financeiro', state: 'ABERTO', evidence: clip(gOrd['body'], 250));
    }
    final gD = await req('GET', '$url/rest/v1/order_disputes?select=id,order_id,buyer_id,description&limit=20', b2H);
    var fd = 0;
    if (gD['body'] is List) {
      for (final r in gD['body'] as List) {
        if (r is Map && '${r['buyer_id']}' != b2Uid) fd++;
      }
    }
    row('DISPUTES', 'B2 SELECT disputes', 'buyer2', 'http=${gD['http']} foreign=$fd ${clip(gD['text'], 100)}', fd > 0 ? 'disputas alheias' : 'vazio', fd > 0 ? 'P1' : 'info');
    if (fd > 0) {
      find(id: 'P1-DISPUTE-LEAK-B2', sev: 'P1', title: 'Buyer2 leu disputas alheias', actor: 'buyer2', pre: 'conta nova', repro: 'GET /order_disputes', impact: 'privacidade', state: 'ABERTO', evidence: clip(gD['body'], 250));
    }
    final gC = await req('GET', '$url/rest/v1/chat_messages?select=id,chat_id,sender_id,text&limit=20', b2H);
    row('CHAT', 'B2 SELECT chat_messages', 'buyer2', 'http=${gC['http']} n=${gC['body'] is List ? (gC['body'] as List).length : 0}', 'chat alheio?', (gC['body'] is List && (gC['body'] as List).isNotEmpty) ? 'P1' : 'info', clip(gC['body'], 160));
    if (gC['body'] is List && (gC['body'] as List).isNotEmpty) {
      find(id: 'P1-CHAT-B2', sev: 'P1', title: 'Buyer2 leu chat_messages sem ser parte', actor: 'buyer2', pre: 'conta nova', repro: 'GET /chat_messages', impact: 'privacidade chat', state: 'ABERTO', evidence: clip(gC['body'], 200));
    }
  }

  // ---- Bag checkout two orders ----
  if (productId != null) {
    final o1 = await req('POST', '$url/rest/v1/orders', buyH, {
      'buyer_id': bUid,
      'seller_id': sUid,
      'product_id': productId,
      'quantity': 1,
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
      'status': 'pendente',
    });
    final o2 = await req('POST', '$url/rest/v1/orders', buyH, {
      'buyer_id': bUid,
      'seller_id': sUid,
      'product_id': productId,
      'quantity': 1,
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
      'status': 'pendente',
    });
    final id1 = idOf(o1['body']);
    final id2 = idOf(o2['body']);
    if (id1 != null && id2 != null) {
      final bag = await req('POST', '$url/functions/v1/create-payment-intent', buyH, {
        'buyer_id': bUid,
        'bag_checkout': true,
        'shipping_method': 'hand',
        'amount': 50,
        'bag_lines': [
          {'order_id': id1, 'line_total_cents': 1, 'quantity': 9, 'product_id': productId},
          {'order_id': id1, 'line_total_cents': 1}, // dup
          {'order_id': id2, 'line_total_cents': 1, 'seller_id': bUid},
        ],
      });
      row('BAG / CART', 'bag 2 orders amount=50 dup line', 'buyer', 'http=${bag['http']} ${clip(bag['text'], 280)}', 'saco autoridade', 'info', bag['body']);
    }
  }

  // ---- GET return-path settle ----
  final ret = await req('GET', '$url/functions/v1/create-payment-intent?session_id=cs_test_fake_$stamp&checkout_return=success', anonH);
  row('WEBHOOK', 'GET create-payment-intent fake session settle', 'anon', 'http=${ret['http']} ${clip(ret['text'], 180)}', 'return path', 'info');

  final tipGet = await req('GET', '$url/functions/v1/create-live-tip-checkout?session_id=cs_test_fake&checkout_return=success', anonH);
  row('TIPS', 'GET tip checkout fake session', 'anon', 'http=${tipGet['http']} ${clip(tipGet['text'], 160)}', 'settle fake', 'info');

  // ---- Wallet tip RPC ----
  final tipW = await req('POST', '$url/rest/v1/rpc/batata_send_live_tip_from_wallet', buyH, {
    'p_live_id': '00000000-0000-0000-0000-000000000001',
    'p_amount': 1,
  });
  row('TIPS', 'send_live_tip_from_wallet', 'buyer', 'http=${tipW['http']} ${clip(tipW['text'], 160)}', 'tip wallet', 'info');

  // ---- Payout own as seller small (may fail no connect) ----
  final po = await req('POST', '$url/functions/v1/create-connect-account', selH, {
    'user_id': sUid,
    'amount': 1,
    'idempotency_key': 'rt1605-payout-a-$stamp',
  });
  row('PAYOUT', 'seller payout 1 cent unique key', 'seller', 'http=${po['http']} ${clip(po['text'], 180)}', 'payout', 'info');
  final po2 = await Future.wait([
    req('POST', '$url/functions/v1/create-connect-account', selH, {
      'user_id': sUid,
      'amount': 1,
      'idempotency_key': 'rt1605-payout-race1-$stamp',
    }),
    req('POST', '$url/functions/v1/create-connect-account', selH, {
      'user_id': sUid,
      'amount': 1,
      'idempotency_key': 'rt1605-payout-race2-$stamp',
    }),
  ]);
  row('PAYOUT', 'two different keys concurrent 1c', 'seller', 'a=${po2[0]['http']} ${clip(po2[0]['text'], 80)} b=${po2[1]['http']} ${clip(po2[1]['text'], 80)}', 'dup transfer?', 'info');

  // ========== PASS 3 RACES ==========
  // Stock=1 two orders concurrent
  if (racePid != null && b2H != null) {
    final futs = await Future.wait([
      req('POST', '$url/rest/v1/orders', buyH, {
        'buyer_id': bUid,
        'seller_id': sUid,
        'product_id': racePid,
        'quantity': 1,
        'payment_method': 'Pagamento na app',
        'shipping_method': 'hand',
        'status': 'pendente',
      }),
      req('POST', '$url/rest/v1/orders', b2H, {
        'buyer_id': b2Uid,
        'seller_id': sUid,
        'product_id': racePid,
        'quantity': 1,
        'payment_method': 'Pagamento na app',
        'shipping_method': 'hand',
        'status': 'pendente',
      }),
    ]);
    final idA = idOf(futs[0]['body']);
    final idB = idOf(futs[1]['body']);
    final prod = await req('GET', '$url/rest/v1/products?id=eq.$racePid&select=id,quantity,is_sold', svcH);
    final holds = await req('GET', '$url/rest/v1/orders?product_id=eq.$racePid&select=id,buyer_id,status,quantity,stock_units_applied&status=neq.cancelado', svcH);
    row('STOCK', '2 INSERT concurrent qty=1 stock=1', 'buyer+b2', 'a=${futs[0]['http']} idA=$idA b=${futs[1]['http']} idB=$idB prod=${clip(prod['body'], 80)} holds=${clip(holds['body'], 200)}', 'oversell?', 'info', {'a': clip(futs[0]['text'], 120), 'b': clip(futs[1]['text'], 120), 'product': prod['body'], 'orders': holds['body']});
    final valid = <String>[];
    if (idA != null) valid.add(idA);
    if (idB != null) valid.add(idB);
    if (valid.length >= 2) {
      find(id: 'P1-STOCK-DOUBLE-HOLD', sev: 'P1', title: 'Duas orders válidas para stock=1', actor: 'buyer+buyer2', pre: 'product quantity=1', repro: '2 POST /orders concurrent', impact: 'oversell potencial', state: 'ABERTO', evidence: holds['body']);
      // concurrent checkout sessions
      final cks = await Future.wait([
        req('POST', '$url/functions/v1/create-payment-intent', buyH, {
          'buyer_id': bUid,
          'order_id': idA,
          'shipping_method': 'hand',
        }),
        req('POST', '$url/functions/v1/create-payment-intent', b2H, {
          'buyer_id': b2Uid,
          'order_id': idB,
          'shipping_method': 'hand',
        }),
      ]);
      row('STOCK', '2 Checkout Sessions stock=1', 'buyer+b2', 'a=${cks[0]['http']} ${clip(cks[0]['text'], 120)} b=${cks[1]['http']} ${clip(cks[1]['text'], 120)}', 'duas sessions', 'info', {'a': cks[0]['body'], 'b': cks[1]['body']});
      final sessions = [cks[0], cks[1]].where((x) => x['http'] == 200 && '${x['text']}'.contains('checkoutUrl')).length;
      notes.add('stock1 sessions_created=$sessions orders=${valid.length}');
    }
  }

  // 10x concurrent checkout same order
  if (productId != null) {
    final o = await req('POST', '$url/rest/v1/orders', buyH, {
      'buyer_id': bUid,
      'seller_id': sUid,
      'product_id': productId,
      'quantity': 1,
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
      'status': 'pendente',
    });
    final oid = idOf(o['body']);
    if (oid != null) {
      final burst = await Future.wait(List.generate(10, (i) => req('POST', '$url/functions/v1/create-payment-intent', buyH, {
            'buyer_id': bUid,
            'order_id': oid,
            'shipping_method': 'hand',
            'amount': 50 + i,
          })));
      final oks = burst.where((x) => x['http'] == 200).length;
      final sids = burst
          .where((x) => x['body'] is Map)
          .map((x) => '${(x['body'] as Map)['checkoutSessionId'] ?? (x['body'] as Map)['checkoutUrl']}')
          .toSet();
      row('CHECKOUT', '10x concurrent same order', 'buyer', 'ok=$oks unique_sidish=${sids.length}', 'session dup', 'info', {'https': burst.map((x) => x['http']).toList(), 'keys': burst.map((x) => x['body'] is Map ? (x['body'] as Map).keys.toList() : x['http']).toList()});
      notes.add('burst10 ok=$oks distinct=$sids');
    }
  }

  // 10x order insert stock=1 leftover product if race consumed, make new
  final pRace2 = await req('POST', '$url/rest/v1/products', selH, {
    'seller_id': sUid,
    'title': 'RT1605race10 $stamp',
    'price': 12.00,
    'quantity': 1,
    'list_on_marketplace': true,
    'image_urls': <dynamic>[],
  });
  final rp2 = idOf(pRace2['body']);
  if (rp2 != null) {
    final burst = await Future.wait(List.generate(10, (i) => req('POST', '$url/rest/v1/orders', buyH, {
          'buyer_id': bUid,
          'seller_id': sUid,
          'product_id': rp2,
          'quantity': 1,
          'payment_method': 'Pagamento na app',
          'shipping_method': 'hand',
          'status': 'pendente',
        })));
    final ids = burst.map(idOf).whereType<String>().toSet();
    final prod = await req('GET', '$url/rest/v1/products?id=eq.$rp2&select=id,quantity,is_sold', svcH);
    row('STOCK', '10x INSERT same buyer stock=1', 'buyer', 'created=${ids.length} prod=${clip(prod['body'], 80)}', ids.length > 1 ? 'multi hold' : '1 hold', ids.length > 1 ? 'P1' : 'info', {'ids': ids.toList(), 'https': burst.map((x) => '${x['http']}:${clip(x['text'], 60)}').toList(), 'product': prod['body']});
    if (ids.length > 1) {
      find(id: 'P1-STOCK-10X-SAME-BUYER', sev: 'P1', title: '10 POSTs criaram ${ids.length} orders para stock=1', actor: 'buyer', pre: 'quantity=1', repro: '10 POST /orders parallel', impact: 'capacidade duplicada', state: 'ABERTO', evidence: {'ids': ids.toList(), 'product': prod['body']});
    }
  }

  // Dual review race on unpaid - expect fail
  if (productId != null) {
    final o = await req('POST', '$url/rest/v1/orders', buyH, {
      'buyer_id': bUid,
      'seller_id': sUid,
      'product_id': productId,
      'quantity': 1,
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
      'status': 'concluido',
    });
    final oid = idOf(o['body']);
    if (oid != null) {
      final st = await req('GET', '$url/rest/v1/orders?id=eq.$oid&select=status', buyH);
      final revs = await Future.wait([
        req('POST', '$url/rest/v1/reviews', buyH, {
          'order_id': oid,
          'buyer_id': bUid,
          'target_id': sUid,
          'stars': 5,
          'comment': 'r1 $stamp',
          'author_role': 'comprador',
        }),
        req('POST', '$url/rest/v1/reviews', buyH, {
          'order_id': oid,
          'buyer_id': bUid,
          'target_id': sUid,
          'stars': 1,
          'comment': 'r2 $stamp',
          'author_role': 'comprador',
        }),
      ]);
      row('REVIEWS', '2 reviews concurrent unpaid/status', 'buyer', 'st=${clip(st['body'], 60)} a=${revs[0]['http']} b=${revs[1]['http']}', 'dup review', 'info', {'a': clip(revs[0]['text'], 80), 'b': clip(revs[1]['text'], 80)});
    }
  }

  // Live reservation last unit if table exists
  final li = await req('GET', '$url/rest/v1/live_items?select=id,live_id,quantity,price,seller_id,is_sold&limit=3', selH);
  row('LIVE ITEMS', 'SELECT live_items seller', 'seller', 'http=${li['http']} ${clip(li['text'], 140)}', 'catalogo live', 'info');

  // Refund x2 same order concurrent (no PI)
  final ordersMine = await req('GET', '$url/rest/v1/orders?buyer_id=eq.$bUid&select=id&limit=1', buyH);
  if (ordersMine['body'] is List && (ordersMine['body'] as List).isNotEmpty) {
    final oid = '${(ordersMine['body'] as List).first['id']}';
    final rfs = await Future.wait([
      req('POST', '$url/functions/v1/refund-order', selH, {'order_id': oid}),
      req('POST', '$url/functions/v1/refund-order', selH, {'order_id': oid}),
    ]);
    row('REFUNDS', '2 refund concurrent', 'seller', 'a=${rfs[0]['http']} ${clip(rfs[0]['text'], 80)} b=${rfs[1]['http']} ${clip(rfs[1]['text'], 80)}', 'dup refund', 'info');
  }

  // profiles dump columns
  final prof = await req('GET', '$url/rest/v1/profiles?id=eq.$sUid&select=*', buyH);
  row('AUTH / PROFILES', 'buyer SELECT seller profile *', 'buyer', 'http=${prof['http']} keys=${prof['body'] is List && (prof['body'] as List).isNotEmpty ? (prof['body'] as List).first.keys.toList() : prof['http']}', 'PII', 'info', clip(prof['body'], 250));

  // observe stripe events for our stamp checkouts
  final ev = await req('GET', '$url/rest/v1/stripe_checkout_events?select=session_id,order_id,event,detail&order=created_at.desc&limit=8', svcH);
  row('STRIPE SESSION', 'observe events service', 'service_observe', 'http=${ev['http']} ${clip(ev['text'], 220)}', 'evidência amount', 'info');

  final frozen = {
    'FROZEN_AT': DateTime.now().toUtc().toIso8601String(),
    'pass': '2+3',
    'project': projectMust,
    'stamp': stamp,
    'production_touched': false,
    'fase4_started': false,
    'b2_uid': b2Uid,
    'product_id': productId,
    'race_pid': racePid,
    'openapi_tables': tables.length,
    'openapi_rpcs': rpcs.length,
    'findings': findings,
    'matrix': matrix,
    'notes': notes,
  };
  File('${outDir.path}/pass23.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(frozen));
  stdout.writeln('PASS2+3 findings=${findings.length} matrix=${matrix.length} tables=${tables.length} rpcs=${rpcs.length}');
  for (final f in findings) {
    stdout.writeln('${f['severity']} ${f['id']} ${f['title']}');
  }
}
