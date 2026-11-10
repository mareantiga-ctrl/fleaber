// Pass 2+3 — schema-aligned hostile probes (independent RT-E).
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

const stagingRef = 'fxdknzrqjenzqcvnwqqq';
const tag = 'rtE2';

late String base, anon, service, buyerId, sellerId, buyerJwt, sellerJwt;
late String freshId, freshJwt;

final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];
final races = <Map<String, dynamic>>[];
final stripe = <Map<String, dynamic>>[];
final invariants = <Map<String, dynamic>>[];
final notes = <String>[];
final createdOrders = <String>[];
final createdProducts = <String>[];
final createdReservations = <String>[];

Map<String, String> h(String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
Map<String, String> ha() => {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
Map<String, String> hs() => {
      'apikey': service,
      'Authorization': 'Bearer $service',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

String clip(String s, [int n = 600]) {
  final t = s.replaceAll(RegExp(r'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9._-]{20,}'), '[JWT]');
  return t.length <= n ? t : '${t.substring(0, n)}…';
}

Future<Map<String, dynamic>> call(
  String method,
  String url, {
  Map<String, String>? headers,
  Object? body,
}) async {
  final hdr = headers ?? ha();
  final uri = Uri.parse(url);
  final enc = body == null ? null : (body is String ? body : jsonEncode(body));
  late http.Response r;
  switch (method) {
    case 'GET':
      r = await http.get(uri, headers: hdr);
      break;
    case 'POST':
      r = await http.post(uri, headers: hdr, body: enc);
      break;
    case 'PATCH':
      r = await http.patch(uri, headers: hdr, body: enc);
      break;
    case 'DELETE':
      r = await http.delete(uri, headers: hdr, body: enc);
      break;
    default:
      throw ArgumentError(method);
  }
  dynamic parsed;
  try {
    parsed = r.body.isEmpty ? null : jsonDecode(r.body);
  } catch (_) {
    parsed = r.body;
  }
  return {'http': r.statusCode, 'body': parsed, 'raw': clip(r.body)};
}

void rec(String surface, String attack, String id, Map<String, dynamic> r) {
  matrix.add({
    'surface': surface,
    'attack': attack,
    'identity': id,
    'http': r['http'],
    'result': r['raw'],
  });
}

void find({
  required String id,
  required String sev,
  required String title,
  required String actor,
  required String pre,
  required String repro,
  required String impact,
  Map<String, dynamic>? evidence,
}) {
  findings.add({
    'id': id,
    'severity': sev,
    'title': title,
    'actor': actor,
    'preconditions': pre,
    'reproduction': repro,
    'impact': impact,
    'state': 'OPEN',
    if (evidence != null) 'evidence': evidence,
  });
}

dynamic row(dynamic body) {
  if (body is List && body.isNotEmpty) return body.first;
  if (body is Map) return body;
  return null;
}

int? n(dynamic v) {
  if (v is num) return v.round();
  return int.tryParse('$v');
}

Future<Map<String, dynamic>> rest(
  String method,
  String table, {
  String jwt = '',
  bool asAnon = false,
  bool asSvc = false,
  String qs = '',
  Object? body,
}) {
  final hdr = asSvc
      ? hs()
      : asAnon
          ? ha()
          : h(jwt);
  return call(method, '$base/rest/v1/$table${qs.isEmpty ? '' : '?$qs'}',
      headers: hdr, body: body);
}

Future<Map<String, dynamic>> rpc(
  String fn,
  Map<String, dynamic> p, {
  String jwt = '',
  bool asAnon = false,
  bool asSvc = false,
}) {
  final hdr = asSvc
      ? hs()
      : asAnon
          ? ha()
          : h(jwt);
  return call('POST', '$base/rest/v1/rpc/$fn', headers: hdr, body: p);
}

Future<Map<String, dynamic>> edge(
  String fn,
  Object body, {
  required String jwt,
  String qs = '',
}) {
  return call('POST', '$base/functions/v1/$fn$qs', headers: h(jwt), body: body);
}

Future<void> boot() async {
  final env = loadLiveOpsStagingEnv();
  base = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!base.contains(stagingRef)) throw StateError('not staging');
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  service = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final c = LiveOpsStagingClient(
    url: base,
    anonKey: anon,
    serviceRoleKey: service,
  );
  buyerJwt = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  sellerJwt = await c.signIn(
    email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );
  // reuse last fresh if still valid is hard; create another
  final nonce = DateTime.now().millisecondsSinceEpoch;
  freshId = await c.createAdminUser(
    email: 'rte2.$nonce@fleaber.staging.invalid',
    password: 'RtE2_${nonce}_Aa1!',
    userMetadata: {'full_name': 'RT-E2'},
  );
  freshJwt = await c.signIn(
    email: 'rte2.$nonce@fleaber.staging.invalid',
    password: 'RtE2_${nonce}_Aa1!',
  );
  await rest('POST', 'profiles', jwt: freshJwt, body: {
    'id': freshId,
    'full_name': 'RT-E2',
    'user_type': 'comprador',
  });
}

Future<List<String>> openApiRpcs() async {
  final r = await call(
    'GET',
    '$base/rest/v1/',
    headers: {
      ...hs(),
      'Accept': 'application/openapi+json',
    },
  );
  rec('OPENAPI', 'service fetch', 'service_observe', r);
  final rpcs = <String>[];
  final tables = <String>[];
  final body = r['body'];
  if (body is Map && body['paths'] is Map) {
    for (final k in (body['paths'] as Map).keys) {
      final p = '$k';
      if (p.startsWith('/rpc/')) {
        rpcs.add(p.substring(5));
      } else if (p.startsWith('/') && !p.substring(1).contains('/')) {
        tables.add(p.substring(1));
      }
    }
  }
  notes.add('openapi_tables=${tables.length} rpcs=${rpcs.length}');
  File('tool/redteam_indep_e_20260829/openapi_rpcs.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({'tables': tables, 'rpcs': rpcs}),
  );
  return rpcs;
}

Future<String> makeProduct({required int qty, required double price}) async {
  final r = await rest('POST', 'products', jwt: sellerJwt, body: {
    'seller_id': sellerId,
    'title': 'RT-E2 $qty $price ${DateTime.now().millisecondsSinceEpoch}',
    'price': price,
    'quantity': qty,
    'list_on_marketplace': true,
    'available_for_live': false,
    'description': tag,
    'image_urls': [],
  });
  rec('products', 'insert qty=$qty', 'seller', r);
  var id = '${row(r['body'])?['id'] ?? ''}';
  if (id.isEmpty || id == 'null') {
    final r2 = await rest('POST', 'products', asSvc: true, body: {
      'seller_id': sellerId,
      'title': 'RT-E2svc ${DateTime.now().millisecondsSinceEpoch}',
      'price': price,
      'quantity': qty,
      'list_on_marketplace': true,
      'image_urls': [],
    });
    rec('products', 'insert svc fallback', 'service_fixture', r2);
    id = '${row(r2['body'])?['id'] ?? ''}';
  }
  if (id.isEmpty || id == 'null') {
    throw StateError('product insert failed ${r['raw']}');
  }
  createdProducts.add(id);
  return id;
}

Future<Map<String, dynamic>?> makeOrder({
  required String jwt,
  required String bid,
  required String pid,
  required Object price,
  required Object qty,
  String status = 'reserva_pendente',
  String pay = 'Pagamento na App',
  String ship = 'hand',
  Map<String, dynamic>? extra,
}) async {
  final body = {
    'product_id': pid,
    'buyer_id': bid,
    'seller_id': sellerId,
    'price_total': price,
    'status': status,
    'payment_method': pay,
    'shipping_method': ship,
    'quantity': qty,
    'is_reservation': true,
    ...?extra,
  };
  final r = await rest('POST', 'orders', jwt: jwt, body: body);
  rec('orders', 'INSERT status=$status qty=$qty price=$price',
      bid == buyerId ? 'buyer' : 'fresh', r);
  final m = row(r['body']);
  if (m is Map && m['id'] != null) {
    createdOrders.add('${m['id']}');
    return Map<String, dynamic>.from(m);
  }
  return null;
}

int? amt(dynamic body) {
  if (body is Map) {
    return n(body['server_amount_cents'] ?? body['amount_total']);
  }
  return null;
}

Future<void> cleanupPass1Reservations() async {
  for (final id in [
    'c61bca30-5a82-4ce3-8e72-37ba9a183420',
    'cbfe925f-9c20-451c-a354-3d4a9db007af',
  ]) {
    final r = await rest(
      'PATCH',
      'live_reservation_requests',
      asSvc: true,
      qs: 'id=eq.$id',
      body: {'status': 'cancelled'},
    );
    rec('LIVE RESERVATIONS', 'cleanup $id', 'service_cleanup', r);
  }
}

Future<void> attackRpcs(List<String> rpcs) async {
  final hot = rpcs.where((x) {
    final n = x.toLowerCase();
    return n.contains('wallet') ||
        n.contains('payout') ||
        n.contains('refund') ||
        n.contains('credit') ||
        n.contains('debit') ||
        n.contains('settle') ||
        n.contains('raffle') ||
        n.contains('admin') ||
        n.contains('stripe') ||
        n.contains('release') ||
        n.contains('tip') ||
        n.contains('review') ||
        n.contains('stock') ||
        n.contains('convert') ||
        n.contains('prize') ||
        n.contains('ocr') ||
        n.contains('accept') ||
        n.contains('paid');
  }).toList();
  notes.add('hot_rpcs=${hot.length}');
  File('tool/redteam_indep_e_20260829/hot_rpcs.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(hot));

  final payloads = <String, Map<String, dynamic>>{
    'batata_ensure_wallet': {'p_user_id': sellerId},
    'batata_wallet_payout_debit': {
      'p_user_id': sellerId,
      'p_amount_cents': 50,
      'p_idempotency_key': '${tag}_xdebit',
    },
    'batata_wallet_payout_finish': {
      'p_idempotency_key': '${tag}_xdebit',
      'p_stripe_transfer_id': 'tr_hostile',
      'p_failed': false,
    },
    'batata_finalize_stripe_order_refund': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_refund_id': 're_x',
      'p_payment_intent_id': 'pi_x',
      'p_session_id': 'cs_x',
      'p_amount_cents': 100,
    },
    'batata_settle_live_tip_from_stripe': {
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
      'p_stripe_session_id': 'cs_x',
      'p_paid_amount_cents': 500,
    },
    'batata_credit_wallet_once': {
      'p_wallet_id': sellerId,
      'p_amount': 10,
      'p_type': 'venda',
    },
  };

  for (final name in hot) {
    final p = payloads[name] ?? <String, dynamic>{};
    for (final e in {
      'anon': () => rpc(name, p, asAnon: true),
      'buyer': () => rpc(name, p, jwt: buyerJwt),
      'fresh': () => rpc(name, p, jwt: freshJwt),
    }.entries) {
      final r = await e.value();
      rec('rpc:$name', 'hostile', e.key, r);
      final http = r['http'] as int;
      final raw = '${r['raw']}';
      if (http < 300 &&
          (raw.contains('"ok":true') ||
              raw.contains('debited') ||
              raw.contains('transferred')) &&
          (name.contains('payout') ||
              name.contains('credit') ||
              name.contains('refund') ||
              name.contains('settle'))) {
        find(
          id: 'RT-E-RPC-$name',
          sev: 'P0',
          title: 'RPC privilegiada executada por ${e.key}',
          actor: e.key,
          pre: 'GRANT EXECUTE',
          repro: 'POST /rpc/$name',
          impact: 'Autoridade financeira/estado.',
          evidence: {'http': http, 'raw': raw},
        );
      }
    }
  }
}

Future<void> attackFinance() async {
  final pid = await makeProduct(qty: 5, price: 12.0);

  // Hostile insert
  final o99 = await makeOrder(
    jwt: buyerJwt,
    bid: buyerId,
    pid: pid,
    price: 0.5,
    qty: 99,
  );
  invariants.add({'id': 'B_insert_qty99', 'order': o99});
  if (o99 != null) {
    final q = n(o99['quantity']);
    final cq = n(o99['contract_qty']);
    final unit = n(o99['contract_unit_cents']);
    notes.add('o99 qty=$q contract_qty=$cq unit=$unit status=${o99['status']} pi=${o99['stripe_payment_intent_id']} paid=${o99['amount_paid_cents']}');

    // Checkout underpay
    final c1 = await edge('create-payment-intent', {
      'amount': 50,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'order_id': o99['id'],
      'product_id': pid,
      'quantity': 1,
      'shipping_method': 'hand',
      'prize_shipping': false,
    }, jwt: buyerJwt);
    rec('CHECKOUT', 'underpay qty99', 'buyer', c1);
    stripe.add({'probe': 'underpay', 'http': c1['http'], 'raw': c1['raw'], 'amt': amt(c1['body'])});
    invariants.add({
      'id': 'A_server_quote',
      'client': 50,
      'server': amt(c1['body']),
      'http': c1['http'],
    });
    final a1 = amt(c1['body']);
    if ((c1['http'] as int) < 300 && a1 != null && a1 <= 50) {
      find(
        id: 'RT-E-UNDERPAY',
        sev: 'P0',
        title: 'Checkout honra amount do cliente',
        actor: 'buyer',
        pre: 'order própria',
        repro: 'create-payment-intent amount=50',
        impact: 'Pagar menos que o preço.',
        evidence: {'raw': c1['raw']},
      );
    }

    final prize = await edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': o99['id'],
      'shipping_method': 'carrier',
      'prize_shipping': true,
    }, jwt: buyerJwt);
    rec('CHECKOUT', 'prize_shipping', 'buyer', prize);
    stripe.add({'probe': 'prize', 'http': prize['http'], 'raw': prize['raw']});
    final pa = amt(prize['body']);
    if ((prize['http'] as int) < 300 && pa != null && pa < 1500) {
      find(
        id: 'RT-E-PRIZE',
        sev: 'P0',
        title: 'prize_shipping reduz o total',
        actor: 'buyer',
        pre: 'order não-rifa',
        repro: 'prize_shipping=true',
        impact: 'Pagar só portes.',
        evidence: {'raw': prize['raw']},
      );
    }

    // Patch contract
    final pt = await rest(
      'PATCH',
      'orders',
      jwt: buyerJwt,
      qs: 'id=eq.${o99['id']}',
      body: {
        'quantity': 1,
        'price_total': 0.5,
        'contract_qty': 1,
        'contract_unit_cents': 1,
        'amount_paid_cents': 1,
        'stripe_payment_intent_id': 'pi_hostile',
        'status': 'pago',
      },
    );
    rec('orders', 'PATCH contract+pago+PI', 'buyer', pt);
    final after = await rest(
      'GET',
      'orders',
      asSvc: true,
      qs: 'id=eq.${o99['id']}&select=id,status,quantity,contract_qty,contract_unit_cents,amount_paid_cents,stripe_payment_intent_id,price_total',
    );
    rec('orders', 'observe after hostile patch', 'service_observe', after);
    final ar = row(after['body']);
    if (ar is Map) {
      if ('${ar['status']}'.toLowerCase() == 'pago') {
        find(
          id: 'RT-E-PATCH-PAGO',
          sev: 'P0',
          title: 'Buyer PATCH status=pago persiste',
          actor: 'buyer',
          pre: 'order própria',
          repro: 'PATCH /orders status=pago',
          impact: 'Venda sem Stripe.',
          evidence: {'row': ar},
        );
      }
      if (n(ar['contract_unit_cents']) == 1) {
        find(
          id: 'RT-E-PATCH-CONTRACT',
          sev: 'P0',
          title: 'Buyer altera contract_unit_cents',
          actor: 'buyer',
          pre: 'order própria',
          repro: 'PATCH contract_unit_cents=1',
          impact: 'Contrato reescrito.',
          evidence: {'row': ar},
        );
      }
      if ('${ar['stripe_payment_intent_id']}' == 'pi_hostile') {
        find(
          id: 'RT-E-PATCH-PI',
          sev: 'P1',
          title: 'Buyer grava PI Stripe',
          actor: 'buyer',
          pre: 'order própria',
          repro: 'PATCH stripe_payment_intent_id',
          impact: 'Autoridade Stripe no cliente.',
          evidence: {'row': ar},
        );
      }
    }

    // Catalog drop
    await rest('PATCH', 'products', jwt: sellerJwt, qs: 'id=eq.$pid', body: {'price': 1.0});
    final c2 = await edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': o99['id'],
      'shipping_method': 'hand',
    }, jwt: buyerJwt);
    rec('CHECKOUT', 'after catalog drop', 'buyer', c2);
    stripe.add({'probe': 'catalog_drop', 'http': c2['http'], 'raw': c2['raw'], 'amt': amt(c2['body'])});
    invariants.add({'id': 'K_catalog', 'server': amt(c2['body']), 'http': c2['http']});
  }

  // Paid insert
  final oPaid = await makeOrder(
    jwt: buyerJwt,
    bid: buyerId,
    pid: pid,
    price: 1,
    qty: 1,
    status: 'pago',
    extra: {
      'amount_paid_cents': 100,
      'stripe_payment_intent_id': 'pi_hostile2',
    },
  );
  if (oPaid != null && '${oPaid['status']}'.toLowerCase() == 'pago') {
    find(
      id: 'RT-E-INS-PAGO',
      sev: 'P0',
      title: 'INSERT order já paga',
      actor: 'buyer',
      pre: 'produto',
      repro: 'POST /orders status=pago',
      impact: 'Venda sem pagamento.',
      evidence: {'row': oPaid},
    );
  }

  // Other buyer
  final oX = await makeOrder(
    jwt: buyerJwt,
    bid: freshId,
    pid: pid,
    price: 12,
    qty: 1,
  );
  if (oX != null && '${oX['buyer_id']}' == freshId) {
    find(
      id: 'RT-E-PARTY',
      sev: 'P1',
      title: 'Buyer cria order noutro buyer_id',
      actor: 'buyer',
      pre: 'UUID alheio',
      repro: 'POST /orders buyer_id=fresh',
      impact: 'Troca de parties.',
      evidence: {'row': oX},
    );
  }

  // Seller off-platform pago
  final oMb = await makeOrder(
    jwt: buyerJwt,
    bid: buyerId,
    pid: pid,
    price: 12,
    qty: 1,
    status: 'aguarda_confirmacao',
    pay: 'MB WAY',
  );
  if (oMb != null) {
    final wBefore = await rest('GET', 'wallets', asSvc: true, qs: 'id=eq.$sellerId&select=balance');
    final sPay = await rest(
      'PATCH',
      'orders',
      jwt: sellerJwt,
      qs: 'id=eq.${oMb['id']}',
      body: {'status': 'pago'},
    );
    rec('ORDER FSM', 'seller PATCH pago MB WAY', 'seller', sPay);
    final wAfter = await rest('GET', 'wallets', asSvc: true, qs: 'id=eq.$sellerId&select=balance');
    rec('WALLET', 'after seller self-pago', 'service_observe', wAfter);
    invariants.add({
      'id': 'F_offplatform',
      'patch_http': sPay['http'],
      'wallet_before': wBefore['raw'],
      'wallet_after': wAfter['raw'],
      'order_after': (await rest('GET', 'orders', asSvc: true, qs: 'id=eq.${oMb['id']}&select=id,status'))['raw'],
    });
  }

  // Legitimate checkout for Stripe TEST
  final pOk = await makeProduct(qty: 2, price: 8.0);
  final oOk = await makeOrder(
    jwt: buyerJwt,
    bid: buyerId,
    pid: pOk,
    price: 8,
    qty: 1,
    ship: 'hand',
  );
  if (oOk != null) {
    final sess = await edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': oOk['id'],
      'shipping_method': 'hand',
    }, jwt: buyerJwt);
    rec('CHECKOUT', 'legit session for TEST pay', 'buyer', sess);
    stripe.add({
      'probe': 'legit_session',
      'http': sess['http'],
      'raw': sess['raw'],
      'order_id': oOk['id'],
      'product_id': pOk,
      'amt': amt(sess['body']),
    });
  }
}

Future<void> attackReviews() async {
  // Forge without order
  final r1 = await rest('POST', 'reviews', jwt: freshJwt, body: {
    'target_id': sellerId,
    'buyer_id': freshId,
    'stars': 5,
    'comment': tag,
    'is_automatic': false,
    'target_type': 'seller',
    'author_role': 'comprador',
  });
  rec('reviews', 'INSERT no order', 'fresh', r1);
  if ((r1['http'] as int) < 300) {
    find(
      id: 'RT-E-REV-NOORDER',
      sev: 'P1',
      title: 'Review sem order',
      actor: 'fresh',
      pre: 'sem transacção',
      repro: 'POST /reviews',
      impact: 'Reputação forjada.',
      evidence: {'raw': r1['raw']},
    );
  }

  // As other buyer_id
  final r2 = await rest('POST', 'reviews', jwt: buyerJwt, body: {
    'target_id': sellerId,
    'buyer_id': freshId,
    'stars': 1,
    'comment': tag,
    'target_type': 'seller',
    'author_role': 'comprador',
  });
  rec('reviews', 'INSERT other buyer_id', 'buyer', r2);

  // Duplicate on a real paid order of lab buyer
  final paid = await rest(
    'GET',
    'orders',
    jwt: buyerJwt,
    qs: 'buyer_id=eq.$buyerId&status=in.(pago,enviado,concluido,entregue)&select=id,status&limit=5',
  );
  rec('reviews', 'list own paid orders', 'buyer', paid);
  final po = row(paid['body']);
  if (po is Map) {
    final a = await rest('POST', 'reviews', jwt: buyerJwt, body: {
      'target_id': sellerId,
      'buyer_id': buyerId,
      'stars': 5,
      'comment': '$tag dup a',
      'target_type': 'seller',
      'author_role': 'comprador',
      'order_id': po['id'],
    });
    final b = await rest('POST', 'reviews', jwt: buyerJwt, body: {
      'target_id': sellerId,
      'buyer_id': buyerId,
      'stars': 5,
      'comment': '$tag dup b',
      'target_type': 'seller',
      'author_role': 'comprador',
      'order_id': po['id'],
    });
    rec('reviews', 'dup A', 'buyer', a);
    rec('reviews', 'dup B', 'buyer', b);
    races.add({
      'race': 'two_reviews_same_order',
      'https': [a['http'], b['http']],
      'raws': [a['raw'], b['raw']],
    });
    if ((a['http'] as int) < 300 && (b['http'] as int) < 300) {
      find(
        id: 'RT-E-REV-DUP',
        sev: 'P1',
        title: 'Duas reviews na mesma order',
        actor: 'buyer',
        pre: 'order paga',
        repro: 'dois POST /reviews order_id',
        impact: 'Inflação reputacional.',
        evidence: {'a': a['raw'], 'b': b['raw']},
      );
    }
  }
}

Future<void> attackRacesAndLive() async {
  final p = await makeProduct(qty: 1, price: 8.0);
  final futs = await Future.wait([
    makeOrder(jwt: buyerJwt, bid: buyerId, pid: p, price: 8, qty: 1),
    makeOrder(jwt: freshJwt, bid: freshId, pid: p, price: 8, qty: 1),
  ]);
  races.add({
    'race': 'two_orders_stock1',
    'n': futs.where((e) => e != null).length,
    'ids': futs.map((e) => e?['id']).toList(),
    'qtys': futs.map((e) => e?['quantity']).toList(),
    'status': futs.map((e) => e?['status']).toList(),
  });
  final alive = futs.whereType<Map<String, dynamic>>().toList();
  if (alive.length >= 2) {
    final sessions = await Future.wait([
      for (final o in alive)
        edge('create-payment-intent', {
          'buyer_id': o['buyer_id'],
          'order_id': o['id'],
          'shipping_method': 'hand',
        }, jwt: '${o['buyer_id']}' == buyerId ? buyerJwt : freshJwt),
    ]);
    races.add({
      'race': 'two_sessions_stock1',
      'https': sessions.map((s) => s['http']).toList(),
      'amts': sessions.map((s) => amt(s['body'])).toList(),
      'raws': sessions.map((s) => s['raw']).toList(),
    });
    stripe.addAll([
      for (var i = 0; i < sessions.length; i++)
        {
          'probe': 'stock1_session_$i',
          'http': sessions[i]['http'],
          'raw': sessions[i]['raw'],
          'order_id': alive[i]['id'],
        }
    ]);
    invariants.add({
      'id': 'D_stock1_sessions',
      'orders': alive.length,
      'sessions_ok': sessions.where((s) => (s['http'] as int) < 300 && amt(s['body']) != null).length,
      'note': 'SESSION≠CAPTURA',
    });
  }

  var both = 0;
  for (var i = 0; i < 10; i++) {
    final px = await makeProduct(qty: 1, price: 7.0);
    final pair = await Future.wait([
      makeOrder(jwt: buyerJwt, bid: buyerId, pid: px, price: 7, qty: 1),
      makeOrder(jwt: freshJwt, bid: freshId, pid: px, price: 7, qty: 1),
    ]);
    if (pair.where((e) => e != null).length >= 2) both++;
  }
  races.add({'race': '10x_stock1_orders', 'both_accepted': both});

  // Live reservations on existing live — then cancel
  final lives = await rest(
    'GET',
    'lives',
    asSvc: true,
    qs: 'select=id,seller_id,status,is_active&status=eq.live&is_active=eq.true&limit=1',
  );
  rec('LIVE', 'active?', 'service_observe', lives);
  final live = row(lives['body']);
  if (live is Map) {
    final lid = '${live['id']}';
    final items = await rest(
      'GET',
      'live_items',
      asSvc: true,
      qs: 'live_id=eq.$lid&select=id,product_id,price,status&limit=5',
    );
    rec('LIVE ITEMS', 'list', 'service_observe', items);
    final li = row(items['body']);
    if (li is Map) {
      // stock of item
      final stock = await rpc('batata_live_item_stock', {'p_live_item_id': li['id']}, asSvc: true);
      rec('rpc:batata_live_item_stock', 'observe', 'service_observe', stock);

      final rr = await Future.wait([
        rest('POST', 'live_reservation_requests', jwt: buyerJwt, body: {
          'live_id': lid,
          'live_item_id': li['id'],
          'buyer_id': buyerId,
          'seller_id': live['seller_id'],
          'requested_qty': 99,
          'source': 'fleaber_live',
          'status': 'accepted',
        }),
        rest('POST', 'live_reservation_requests', jwt: freshJwt, body: {
          'live_id': lid,
          'live_item_id': li['id'],
          'buyer_id': freshId,
          'seller_id': live['seller_id'],
          'requested_qty': 99,
          'source': 'fleaber_live',
          'status': 'accepted',
        }),
      ]);
      rec('LIVE RESERVATIONS', 'qty99 accepted buyer', 'buyer', rr[0]);
      rec('LIVE RESERVATIONS', 'qty99 accepted fresh', 'fresh', rr[1]);
      for (final r in rr) {
        final m = row(r['body']);
        if (m is Map && m['id'] != null) createdReservations.add('${m['id']}');
      }
      races.add({
        'race': 'two_reservations_qty99',
        'https': rr.map((e) => e['http']).toList(),
        'raws': rr.map((e) => e['raw']).toList(),
      });
      final stock2 = await rpc('batata_live_item_stock', {'p_live_item_id': li['id']}, asSvc: true);
      rec('rpc:batata_live_item_stock', 'after race', 'service_observe', stock2);
    }
  }

  // Views / stream keys via hub
  for (final t in [
    'hub_lives_public',
    'lives_safe',
    'lives_public',
  ]) {
    final r = await rest('GET', t, jwt: freshJwt, qs: 'select=*&limit=5');
    rec(t, 'SELECT *', 'fresh', r);
    final anonR = await rest('GET', t, asAnon: true, qs: 'select=*&limit=5');
    rec(t, 'SELECT *', 'anon', anonR);
  }

  // PII profiles
  final prof = await rest(
    'GET',
    'profiles',
    jwt: freshJwt,
    qs: 'id=eq.$sellerId&select=id,full_name,iban,mb_way,phone,shipping_line1,user_type',
  );
  rec('profiles', 'SELECT seller PII as fresh', 'fresh', prof);
  final pRow = row(prof['body']);
  if (pRow is Map) {
    final iban = '${pRow['iban'] ?? ''}';
    final phone = '${pRow['phone'] ?? ''}';
    final addr = '${pRow['shipping_line1'] ?? ''}';
    if (iban.length > 4 || (phone.length > 4 && phone != 'null') || (addr.length > 2 && addr != 'null')) {
      find(
        id: 'RT-E-PII-PROFILE',
        sev: 'P1',
        title: 'Fresh lê PII do seller',
        actor: 'fresh',
        pre: 'UUID conhecido',
        repro: 'GET /profiles?id=eq.seller',
        impact: 'IBAN/telefone/morada.',
        evidence: {'row': pRow},
      );
    }
  }

  // refund other seller order as buyer
  final otherPaid = await rest(
    'GET',
    'orders',
    asSvc: true,
    qs: 'seller_id=neq.$sellerId&status=eq.pago&select=id,seller_id&limit=1',
  );
  final oo = row(otherPaid['body']);
  if (oo is Map) {
    final rf = await edge('refund-order', {'order_id': oo['id']}, jwt: buyerJwt);
    rec('refund-order', 'buyer refund other seller order', 'buyer', rf);
  }

  // seller refund unpaid
  if (createdOrders.isNotEmpty) {
    final rf = await edge('refund-order', {'order_id': createdOrders.last}, jwt: sellerJwt);
    rec('refund-order', 'seller refund unpaid fixture', 'seller', rf);
  }
}

Future<void> attackStorageDeep() async {
  for (final prefix in [
    'product_photos',
    'profile_photos',
    'live_item_photos',
    'live_raffle_prize',
  ]) {
    final list = await call(
      'POST',
      '$base/storage/v1/object/list/chat_media',
      headers: h(freshJwt),
      body: {'prefix': prefix, 'limit': 20},
    );
    rec('storage:chat_media', 'list $prefix', 'fresh', list);
  }
  // dispute proofs if any via rest
  final dp = await rest('GET', 'order_disputes', jwt: freshJwt, qs: 'select=*&limit=20');
  rec('order_disputes', 'SELECT *', 'fresh', dp);
}

Future<void> payoutObserve() async {
  final led = await rest(
    'GET',
    'wallet_payout_ledger',
    asSvc: true,
    qs: 'user_id=eq.$sellerId&order=created_at.desc&select=*&limit=8',
  );
  rec('PAYOUT', 'ledger recent', 'service_observe', led);
  final w = await rest('GET', 'wallets', asSvc: true, qs: 'id=eq.$sellerId&select=*');
  rec('WALLET', 'seller now', 'service_observe', w);
}

Future<void> cleanup() async {
  for (final id in createdReservations) {
    await rest(
      'PATCH',
      'live_reservation_requests',
      asSvc: true,
      qs: 'id=eq.$id',
      body: {'status': 'cancelled'},
    );
  }
  for (final id in createdOrders) {
    await rest(
      'PATCH',
      'orders',
      asSvc: true,
      qs: 'id=eq.$id',
      body: {'status': 'cancelado'},
    );
  }
  for (final id in createdProducts) {
    await rest(
      'PATCH',
      'products',
      asSvc: true,
      qs: 'id=eq.$id',
      body: {'list_on_marketplace': false, 'quantity': 0},
    );
  }
}

void main() async {
  await boot();
  await cleanupPass1Reservations();
  final rpcs = await openApiRpcs();
  await attackRpcs(rpcs);
  await attackFinance();
  await attackReviews();
  await attackRacesAndLive();
  await attackStorageDeep();
  await payoutObserve();
  await cleanup();

  final out = {
    'pass': '2_3',
    'project': stagingRef,
    'frozen_at': DateTime.now().toUtc().toIso8601String(),
    'findings': findings,
    'matrix': matrix,
    'races': races,
    'stripe': stripe,
    'invariants': invariants,
    'notes': notes,
    'created_orders': createdOrders,
    'created_products': createdProducts,
    'created_reservations': createdReservations,
  };
  File('tool/redteam_indep_e_20260829/pass2_raw.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(out),
  );
  stdout.writeln('FINDINGS=${findings.length}');
  for (final f in findings) {
    stdout.writeln('${f['severity']} ${f['id']} ${f['title']}');
  }
  stdout.writeln('ORDERS=${createdOrders.length} RACES=${races.length} STRIPE=${stripe.length}');
}
