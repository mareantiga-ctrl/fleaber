/// Blind independent red-team PASS 2 — variants, money, races.
/// Staging only. No production. No Fase 4. No fixes.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

const projectMust = 'fxdknzrqjenzqcvnwqqq';
const prefix = 'RT1719P2';

final matrix = <Map<String, dynamic>>[];
final findings = <Map<String, dynamic>>[];

void rec(String surface, String attack, String identity, String result,
    {String impact = '', Object? evidence}) {
  matrix.add({
    'surface': surface,
    'attack': attack,
    'identity': identity,
    'result': result,
    'impact': impact,
    'evidence': evidence is String && evidence.length > 900
        ? '${evidence.substring(0, 900)}…'
        : evidence,
  });
}

void finding(String id, String sev, String title, String actor, String impact,
    {Object? evidence}) {
  findings.add({
    'id': id,
    'severity': sev,
    'title': title,
    'actor': actor,
    'impact': impact,
    'estado': 'ABERTO',
    'evidence': evidence,
  });
  stdout.writeln('FINDING $id $sev $title');
}

Map<String, String> hJwt(String anon, String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

String brief(http.Response r) {
  var b = r.body;
  if (b.length > 360) b = '${b.substring(0, 360)}…';
  return '${r.statusCode} $b';
}

Future<http.Response> rest(String url, String method, String path,
    Map<String, String> headers, [Object? body]) {
  final u = Uri.parse('$url/rest/v1/$path');
  final b = body == null ? null : jsonEncode(body);
  return switch (method) {
    'GET' => http.get(u, headers: headers),
    'POST' => http.post(u, headers: headers, body: b),
    'PATCH' => http.patch(u, headers: headers, body: b),
    'DELETE' => http.delete(u, headers: headers, body: b),
    _ => throw ArgumentError(method),
  };
}

Future<http.Response> rpcRaw(
    String url, String fn, Map<String, dynamic> params, Map<String, String> h) {
  return http.post(Uri.parse('$url/rest/v1/rpc/$fn'),
      headers: h, body: jsonEncode(params));
}

Future<http.Response> edge(String url, String fn, Object? body,
    {required String anon, String? jwt}) {
  return http.post(Uri.parse('$url/functions/v1/$fn'),
      headers: {
        'apikey': anon,
        'Authorization': 'Bearer ${jwt ?? anon}',
        'Content-Type': 'application/json',
      },
      body: body == null ? null : jsonEncode(body));
}

int n(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse('$v') ?? 0;
}

double d(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  if (!url.contains(projectMust)) exit(2);
  final anon = envRequire(env, 'SUPABASE_ANON_KEY');
  final svc = envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');
  final admin = LiveOpsStagingClient(
      url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerJwt = await admin.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'));
  final sellerJwt = await admin.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'));
  final hB = hJwt(anon, buyerJwt);
  final hS = hJwt(anon, sellerJwt);
  final hA = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };
  final hSvc = {
    'apikey': svc,
    'Authorization': 'Bearer $svc',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
    'Accept': 'application/openapi+json',
  };

  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  final helperPass = 'Rt1719-P2-Help-9x!';
  final helperEmail = '$prefix-b2-$stamp@fleaber.invalid';
  final helperId =
      await admin.createAdminUser(email: helperEmail, password: helperPass);
  final helperJwt =
      await admin.signIn(email: helperEmail, password: helperPass);
  final hH = hJwt(anon, helperJwt);

  final prod = await admin.insert('products', {
    'seller_id': sellerId,
    'title': '$prefix stock1',
    'price': 20.00,
    'quantity': 1,
    'state': 'Bom',
    'is_sold': false,
    'list_on_marketplace': true,
  });
  final productId = prod['id'].toString();
  final prodHi = await admin.insert('products', {
    'seller_id': sellerId,
    'title': '$prefix hi',
    'price': 40.00,
    'quantity': 5,
    'state': 'Bom',
    'is_sold': false,
    'list_on_marketplace': true,
  });
  final productHi = prodHi['id'].toString();

  Future<Map<String, dynamic>?> order(String? id) async {
    if (id == null) return null;
    final rows = await admin.select('orders', filter: 'id=eq.$id', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  String? idFrom(http.Response r) {
    if (r.statusCode >= 400) return null;
    final b = jsonDecode(r.body);
    if (b is List && b.isNotEmpty) return b.first['id']?.toString();
    if (b is Map) return b['id']?.toString();
    return null;
  }

  Future<http.Response> insOrder(Map<String, String> h, String pid,
      String bid, {String pm = 'Pagamento na app', int qty = 1}) {
    return rest(url, 'POST', 'orders', h, {
      'product_id': pid,
      'buyer_id': bid,
      'seller_id': sellerId,
      'quantity': qty,
      'status': 'reserva_pendente',
      'payment_method': pm,
      'shipping_method': 'Entrega em mão (€0.00)',
    });
  }

  // ---------- OpenAPI via service (observe) ----------
  final oa = await http.get(Uri.parse('$url/rest/v1/'), headers: hSvc);
  final rpcs = <String>[];
  if (oa.statusCode < 400) {
    final spec = jsonDecode(oa.body) as Map<String, dynamic>;
    final paths = spec['paths'] as Map<String, dynamic>? ?? {};
    for (final k in paths.keys) {
      if (k.startsWith('/rpc/')) rpcs.add(k.substring(5));
    }
    rpcs.sort();
  }
  rec('PostgREST', 'OpenAPI service_observe', 'service_observe',
      'rpcs=${rpcs.length}',
      evidence: rpcs);

  // ---------- payout_finish correct signature as JWT ----------
  for (final ident in [
    ['anon', hA],
    ['buyer', hB],
    ['seller', hS],
    ['helper', hH],
  ]) {
    final r = await rpcRaw(
        url,
        'batata_wallet_payout_finish',
        {
          'p_idempotency_key': 'rt1719-buyer-payout-seller',
          'p_stripe_transfer_id': 'tr_forged_1719',
          'p_failed': true,
        },
        ident[1] as Map<String, String>);
    rec('rpc/batata_wallet_payout_finish', 'p_failed=true guessed key',
        ident[0] as String, brief(r));
    if (r.statusCode < 400 && !r.body.contains('permission')) {
      finding('RT1719-10', 'P0', 'JWT can call payout_finish', ident[0] as String,
          'Can reverse or fake-complete Stripe transfers',
          evidence: r.body);
    }
  }

  // ---------- Offer bait-and-switch + checkout ----------
  final offerIns = await rest(url, 'POST', 'product_offers', hB, {
    'product_id': productHi,
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'amount': 25.00,
    'list_price': 40.00,
    'offered_by': 'buyer',
    'status': 'pending',
  });
  final offerId = idFrom(offerIns);
  rec('product_offers', 'INSERT 25€', 'buyer', brief(offerIns));
  if (offerId != null) {
    final patchAmt = await rest(
        url, 'PATCH', 'product_offers?id=eq.$offerId', hB, {'amount': 0.50});
    final offerAfter = await admin
        .select('product_offers', filter: 'id=eq.$offerId', limit: 1);
    rec('product_offers', 'PATCH 25→0.50 before accept', 'buyer',
        brief(patchAmt),
        impact: offerAfter.isEmpty ? '' : 'amount=${offerAfter.first['amount']}',
        evidence: offerAfter);
    final acc = await rest(url, 'PATCH', 'product_offers?id=eq.$offerId', hS, {
      'status': 'accepted',
    });
    final offerAcc = await admin
        .select('product_offers', filter: 'id=eq.$offerId', limit: 1);
    rec('product_offers', 'SELLER accept after buyer amount patch', 'seller',
        brief(acc),
        impact: offerAcc.isEmpty
            ? ''
            : 'status=${offerAcc.first['status']} amount=${offerAcc.first['amount']}',
        evidence: offerAcc);
    if (offerAcc.isNotEmpty &&
        '${offerAcc.first['status']}' == 'accepted' &&
        d(offerAcc.first['amount']) <= 0.50) {
      final o = await insOrder(hB, productHi, buyerId);
      final oid = idFrom(o);
      rec('orders', 'INSERT after cheap accepted offer', 'buyer', brief(o),
          evidence: await order(oid));
      if (oid != null) {
        final row = await order(oid);
        rec('orders', 'contract after cheap offer', 'observe',
            'contract=${row?['contract_unit_cents']} qty=${row?['contract_qty']} price=${row?['price_total']} offer=${row?['product_offer_id']}',
            evidence: row);
        final pay = await edge(url, 'create-payment-intent', {
          'buyer_id': buyerId,
          'order_id': oid,
          'amount': 4000,
          'shipping_method': 'Entrega em mão (€0.00)',
        }, anon: anon, jwt: buyerJwt);
        rec('edge/create-payment-intent', 'checkout after 0.50 accepted offer',
            'buyer', brief(pay),
            evidence: pay.body);
        final cents = jsonDecode(pay.body is String && pay.body.startsWith('{')
            ? pay.body
            : '{}');
        final serverAmt = cents is Map ? n(cents['server_amount_cents']) : 0;
        if (pay.statusCode < 400 && serverAmt > 0 && serverAmt < 2000) {
          finding(
              'RT1719-11',
              'P1',
              'Accepted offer after buyer amount patch drives sub-catalog Stripe charge',
              'buyer+seller',
              'server_amount_cents=$serverAmt vs catalog 40€',
              evidence: {'offer': offerAcc.first, 'checkout': pay.body, 'order': row});
        }
      }
    }
  }

  // ---------- Catalog mutation after seal ----------
  final oSeal = await insOrder(hB, productHi, buyerId);
  final oidSeal = idFrom(oSeal);
  final before = await order(oidSeal);
  await admin.patch('products', 'id=eq.$productHi', {'price': 1.00});
  final payAfterCat = oidSeal == null
      ? null
      : await edge(url, 'create-payment-intent', {
          'buyer_id': buyerId,
          'order_id': oidSeal,
          'shipping_method': 'Entrega em mão (€0.00)',
        }, anon: anon, jwt: buyerJwt);
  rec('catalog×checkout', 'seller drops price after order seal', 'buyer',
      payAfterCat == null ? 'no order' : brief(payAfterCat),
      impact:
          'sealed_contract=${before?['contract_unit_cents']} checkout=${payAfterCat?.body}',
      evidence: before);
  await admin.patch('products', 'id=eq.$productHi', {'price': 40.00});

  // ---------- Dual checkout same order ----------
  final oDup = await insOrder(hB, productHi, buyerId);
  final oidDup = idFrom(oDup);
  if (oidDup != null) {
    final a = edge(url, 'create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': oidDup,
      'shipping_method': 'Entrega em mão (€0.00)',
    }, anon: anon, jwt: buyerJwt);
    final b = edge(url, 'create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': oidDup,
      'shipping_method': 'Entrega em mão (€0.00)',
    }, anon: anon, jwt: buyerJwt);
    final rs = await Future.wait([a, b]);
    rec('checkout race', '2 concurrent Sessions same order', 'buyer',
        '${brief(rs[0])} || ${brief(rs[1])}',
        evidence: await order(oidDup));
  }

  // ---------- Stock=1 two buyers ----------
  final o1 = await insOrder(hB, productId, buyerId);
  final o2 = await insOrder(hH, productId, helperId);
  rec('stock', 'buyer1 INSERT qty=1 stock=1', 'buyer', brief(o1));
  rec('stock', 'helper INSERT qty=1 stock=1', 'helper', brief(o2));
  final id1 = idFrom(o1);
  final id2 = idFrom(o2);
  http.Response? p1;
  http.Response? p2;
  if (id1 != null && id2 != null) {
    final f1 = edge(url, 'create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': id1,
      'shipping_method': 'Entrega em mão (€0.00)',
    }, anon: anon, jwt: buyerJwt);
    final f2 = edge(url, 'create-payment-intent', {
      'buyer_id': helperId,
      'order_id': id2,
      'shipping_method': 'Entrega em mão (€0.00)',
    }, anon: anon, jwt: helperJwt);
    final both = await Future.wait([f1, f2]);
    p1 = both[0];
    p2 = both[1];
    rec('stock×checkout', 'concurrent Sessions last unit', 'buyer+helper',
        'A=${brief(p1)} || B=${brief(p2)}');
    final okA = p1.statusCode < 400;
    final okB = p2.statusCode < 400;
    if (okA && okB) {
      finding(
          'RT1719-12',
          'P1',
          'Stock=1 allowed two Checkout Sessions',
          'buyer+helper',
          'Two Sessions created; capture not yet proven',
          evidence: {'a': p1.body, 'b': p2.body, 'o1': id1, 'o2': id2});
    }
  }

  // qty 2 on stock=1
  final oOver = await insOrder(hB, productId, buyerId, qty: 2);
  rec('stock', 'INSERT qty=2 on stock=1', 'buyer', brief(oOver),
      evidence: await order(idFrom(oOver)));

  // ---------- MB WAY mint ----------
  final w0 = await admin.select('wallets', filter: 'id=eq.$sellerId', limit: 1);
  final bal0 = w0.isEmpty ? 0.0 : d(w0.first['balance']);
  final mb = await insOrder(hB, productHi, buyerId, pm: 'MB WAY');
  final mbId = idFrom(mb);
  rec('orders', 'INSERT MB WAY', 'buyer', brief(mb), evidence: await order(mbId));
  if (mbId != null) {
    final pago = await rest(
        url, 'PATCH', 'orders?id=eq.$mbId', hS, {'status': 'pago'});
    rec('orders', 'SELLER PATCH pago MB WAY', 'seller', brief(pago),
        evidence: await order(mbId));
    final envio = await rest(
        url, 'PATCH', 'orders?id=eq.$mbId', hS, {'status': 'enviado'});
    rec('orders', 'SELLER PATCH enviado', 'seller', brief(envio),
        evidence: await order(mbId));
    final conc = await rest(
        url, 'PATCH', 'orders?id=eq.$mbId', hB, {'status': 'concluido'});
    rec('orders', 'BUYER PATCH concluido', 'buyer', brief(conc),
        evidence: await order(mbId));
    final rel = await rpcRaw(url, 'batata_release_seller_wallet_for_order',
        {'p_order_id': mbId}, hB);
    rec('rpc/release', 'release after off-platform concluido', 'buyer',
        brief(rel));
    final w1 =
        await admin.select('wallets', filter: 'id=eq.$sellerId', limit: 1);
    final bal1 = w1.isEmpty ? 0.0 : d(w1.first['balance']);
    rec('wallets', 'seller balance after MB WAY release', 'observe',
        'before=$bal0 after=$bal1 delta=${(bal1 - bal0).toStringAsFixed(2)}',
        evidence: await order(mbId));
    if (bal1 - bal0 > 0.009) {
      finding('RT1719-13', 'P0', 'Off-platform cycle minted seller wallet',
          'buyer+seller', 'delta=${bal1 - bal0}',
          evidence: {'before': bal0, 'after': bal1, 'order': await order(mbId)});
    }
  }

  // ---------- GET settle without JWT ----------
  if (id1 != null && p1 != null && p1.statusCode < 400) {
    Map body = {};
    try {
      body = jsonDecode(p1.body) as Map;
    } catch (_) {}
    final sid = '${body['checkoutSessionId'] ?? ''}';
    if (sid.startsWith('cs_')) {
      final g = await http.get(Uri.parse(
          '$url/functions/v1/create-payment-intent?checkout_return=success&session_id=$sid'));
      rec('edge/create-payment-intent GET', 'settle unpaid session as anon',
          'anon', '${g.statusCode} ${g.body.length > 200 ? g.body.substring(0, 200) : g.body}');
      rec('orders', 'after GET settle unpaid', 'observe',
          'status=${(await order(id1))?['status']} paid=${(await order(id1))?['amount_paid_cents']}');
    }
  }

  // ---------- Reviews ----------
  final rev1 = await rest(url, 'POST', 'reviews', hB, {
    'target_id': sellerId,
    'buyer_id': buyerId,
    'stars': 1,
    'comment': '$prefix no-order',
    'target_type': 'seller',
    'author_role': 'comprador',
  });
  rec('reviews', 'INSERT no order', 'buyer', brief(rev1));
  if (rev1.statusCode < 400) {
    finding('RT1719-14', 'P1', 'Review without legitimate order', 'buyer',
        'Reputation forge', evidence: rev1.body);
  }
  final rev2 = await rest(url, 'POST', 'reviews', hH, {
    'target_id': sellerId,
    'buyer_id': helperId,
    'stars': 5,
    'comment': '$prefix helper as seller role',
    'target_type': 'seller',
    'author_role': 'vendedor',
    'order_id': mbId,
  });
  rec('reviews', 'helper INSERT author_role=vendedor on others order',
      'helper', brief(rev2));

  // ---------- Cross-user chats / events ----------
  final chatsH = await rest(
      url, 'GET', 'chat_messages?select=id,sender_id,text,chat_id&limit=5', hH);
  rec('chat_messages', 'helper GET unfiltered', 'helper', brief(chatsH));
  final evH = await rest(url, 'GET',
      'stripe_checkout_events?select=id,buyer_id,session_id,event&limit=10', hH);
  rec('stripe_checkout_events', 'helper GET unfiltered', 'helper', brief(evH));
  final evBother = await rest(url, 'GET',
      'stripe_checkout_events?buyer_id=eq.$buyerId&select=id,session_id', hH);
  rec('stripe_checkout_events', 'helper GET buyer events', 'helper',
      brief(evBother));

  // ---------- Disputes ----------
  if (mbId != null) {
    final d1 = await rest(url, 'POST', 'order_disputes', hH, {
      'order_id': mbId,
      'buyer_id': helperId,
      'reason': 'nao_corresponde',
      'description': '$prefix helper dispute on others order',
    });
    rec('order_disputes', 'helper INSERT on buyer order', 'helper', brief(d1));
  }

  // ---------- JWT payout_debit ----------
  final debit = await rpcRaw(
      url,
      'batata_wallet_payout_debit',
      {
        'p_user_id': buyerId,
        'p_amount_cents': 100,
        'p_idempotency_key': 'rt1719p2-buyer-debit-xx',
      },
      hB);
  rec('rpc/payout_debit', 'buyer debit own wallet', 'buyer', brief(debit));

  // ---------- Tip checkout valid (no tip_id) ----------
  final lives = await admin.select('lives', filter: 'seller_id=eq.$sellerId', limit: 1);
  final liveId = lives.isEmpty ? null : lives.first['id']?.toString();
  if (liveId != null) {
    final tip = await edge(url, 'create-live-tip-checkout', {
      'seller_id': sellerId,
      'amount_eur': 1,
      'live_id': liveId,
    }, anon: anon, jwt: buyerJwt);
    rec('edge/tip', 'valid 1€ tip no client tip_id', 'buyer', brief(tip));
    final tipBig = await edge(url, 'create-live-tip-checkout', {
      'seller_id': sellerId,
      'amount_eur': 499,
      'live_id': liveId,
    }, anon: anon, jwt: buyerJwt);
    rec('edge/tip', '499€ tip (under 500 cap)', 'buyer', brief(tipBig));
    final tipNeg = await edge(url, 'create-live-tip-checkout', {
      'seller_id': sellerId,
      'amount_eur': -5,
      'live_id': liveId,
    }, anon: anon, jwt: buyerJwt);
    rec('edge/tip', 'negative amount', 'buyer', brief(tipNeg));
  }

  // ---------- livekit with real live ----------
  if (liveId != null) {
    final lkB = await edge(url, 'livekit-mux-publish', {
      'step': 'token',
      'live_id': liveId,
    }, anon: anon, jwt: buyerJwt);
    rec('edge/livekit', 'buyer token on seller live', 'buyer', brief(lkB));
    final muxKey = await rest(url, 'GET',
        'lives?id=eq.$liveId&select=id,mux_stream_key,stream_key,status', hS);
    rec('lives', 'seller SELECT stream keys own live', 'seller', brief(muxKey));
    final muxB = await rest(url, 'GET',
        'lives?id=eq.$liveId&select=id,mux_stream_key,stream_key', hB);
    rec('lives', 'buyer SELECT stream keys', 'buyer', brief(muxB));
  }

  // ---------- ensure_wallet other user + credit via insert tx ----------
  final ens = await rpcRaw(
      url, 'batata_ensure_wallet', {'p_user_id': helperId}, hB);
  rec('rpc/ensure_wallet', 'buyer ensure helper wallet', 'buyer', brief(ens));
  final tx = await rest(url, 'POST', 'wallet_transactions', hB, {
    'wallet_id': helperId,
    'amount': 50,
    'type': 'ajuste',
    'description': 'forged',
  });
  rec('wallet_transactions', 'buyer INSERT credit helper', 'buyer', brief(tx));

  // ---------- Sensitive RPCs from OpenAPI ----------
  final moneyRpcs = rpcs.where((n) {
    final l = n.toLowerCase();
    return l.contains('wallet') ||
        l.contains('payout') ||
        l.contains('refund') ||
        l.contains('credit') ||
        l.contains('debit') ||
        l.contains('settle') ||
        l.contains('admin') ||
        l.contains('sql') ||
        l.contains('raffle') ||
        l.contains('prize');
  }).toList();
  rec('rpc', 'money-ish names', 'observe', '${moneyRpcs.length}',
      evidence: moneyRpcs);
  for (final fn in moneyRpcs.take(40)) {
    final r = await rpcRaw(url, fn, {}, hB);
    if (r.statusCode < 400 &&
        !r.body.contains('false') &&
        r.body.isNotEmpty &&
        r.body != 'null') {
      rec('rpc/$fn', 'buyer empty-args EXECUTE', 'buyer', brief(r),
          impact: 'EXECUTED');
    }
  }

  // ---------- 10x dual insert stock=1 ----------
  var bothInserted = 0;
  for (var i = 0; i < 10; i++) {
    final p = await admin.insert('products', {
      'seller_id': sellerId,
      'title': '$prefix race $i',
      'price': 8.00,
      'quantity': 1,
      'state': 'Bom',
      'is_sold': false,
      'list_on_marketplace': true,
    });
    final pid = p['id'].toString();
    final ra = insOrder(hB, pid, buyerId);
    final rb = insOrder(hH, pid, helperId);
    final rr = await Future.wait([ra, rb]);
    final ok1 = rr[0].statusCode < 400;
    final ok2 = rr[1].statusCode < 400;
    if (ok1 && ok2) bothInserted++;
  }
  rec('stock race x10', 'two INSERT orders stock=1', 'buyer+helper',
      'both_inserted=$bothInserted/10');
  if (bothInserted > 0) {
    rec('stock race', 'holds vs sold', 'observe',
        'both_insert_ok is not two paid sales');
  }

  final out = Directory('tool/redteam_blind_indep_20260830T1719/out');
  out.createSync(recursive: true);
  File('${out.path}/pass2.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'pass': 2,
      'product_stock1': productId,
      'product_hi': productHi,
      'helper_id': helperId,
      'live_id': liveId,
      'rpc_count': rpcs.length,
      'matrix': matrix,
      'findings': findings,
    }),
  );
  stdout.writeln('PASS2 written findings=${findings.length} matrix=${matrix.length}');
}
