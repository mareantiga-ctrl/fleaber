/// RED TEAM CEGO CM pass1 — CM-A discovery/follow/stock/reviews (≥16) + residual ≤3.
import 'dart:io';
import '_rtcm.dart';

Future<void> main() async {
  final c = Rtcm.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final s1 = c.sellerId!;
  final s2 = c.seller2Id!;
  final b1 = c.buyerId!;
  final s1p = await c.profile(s1);
  final s2p = await c.profile(s2);
  c.note('fix.s1', 'S1 profile', s1p, lens: 'CM1');
  c.note('fix.s2', 'S2 unpublished', s2p, lens: 'CM1');

  if (s1p?['hub_published'] != true) {
    await c.rest('PATCH', 'profiles?id=eq.$s1', service: true, body: {
      'hub_published': true,
    }, prefer: 'return=minimal');
  }
  await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'hub_published': false,
    'handle': 'rtcm1318s2',
    'is_live': true,
  }, prefer: 'return=minimal');

  const fakePb = 'rtcmPbLive1318aaaa';
  const fakeVod = 'rtcmPbVod1318bbbb';
  const fakeStream = 'rtcmStreamKey1318secret';

  String? realPb;
  final real = await c.rest(
    'GET',
    'lives?mux_playback_id=not.is.null&select=id,mux_playback_id&limit=6',
    service: true,
  );
  for (final row in real.list) {
    if (row is Map) {
      final pb = '${row['mux_playback_id'] ?? ''}'.trim();
      if (pb.length > 8 && !pb.startsWith('rtcm') && !pb.startsWith('rtcg')) {
        realPb = pb;
        break;
      }
    }
  }
  final pbAir = realPb ?? fakePb;

  final liveAirPub = await c.insertLive(
    seller: s1,
    active: true,
    status: 'live',
    muxPlayback: pbAir,
    muxStreamKey: fakeStream,
    muxLiveId: 'muxLiveAirPub1318',
    title: '$prefix air-pub',
  );
  final liveAirUnpub = await c.insertLive(
    seller: s2,
    active: true,
    status: 'live',
    muxPlayback: pbAir,
    muxStreamKey: fakeStream,
    muxLiveId: 'muxLiveAirUnpub1318',
    title: '$prefix air-unpub',
  );
  final liveSchedUnpub = await c.insertLive(
    seller: s2,
    active: false,
    status: 'scheduled',
    muxPlayback: pbAir,
    title: '$prefix sched-unpub',
  );
  final liveEndedUnpub = await c.insertLive(
    seller: s2,
    active: false,
    status: 'ended',
    muxVod: fakeVod,
    title: '$prefix ended-unpub',
  );

  final itemUnpub = await c.insertLiveOnlyItem(
    liveId: liveAirUnpub!,
    qty: 4,
    price: 17.5,
    title: '$prefix unpub-sku',
  );
  final itemPub = await c.insertLiveOnlyItem(
    liveId: liveAirPub!,
    qty: 3,
    price: 11.0,
    title: '$prefix pub-sku',
  );

  final prodUnpub = await c.createProduct(
    seller: s2,
    title: '$prefix unpub-mkt',
    qty: 5,
    price: 22.0,
  );
  final prodDead = await c.createProduct(
    seller: s1,
    title: '$prefix qty0-dead',
    qty: 0,
    price: 33.0,
  );
  final prodOk = await c.createProduct(
    seller: s1,
    title: '$prefix qty-ok',
    qty: 2,
    price: 14.0,
  );

  final rev = await c.rest('POST', 'reviews', service: true, body: {
    'buyer_id': b1,
    'target_id': s2,
    'target_type': 'seller',
    'stars': 5,
    'comment': '$prefix review unpublished shop',
  });
  c.note('fix.review', 'review S2', rev, lens: 'CM1');
  final reviewId = rev.firstId;
  if (reviewId != null) c.createdReviewIds.add(reviewId);

  final raffle = await c.rest('POST', 'live_raffles', service: true, body: {
    'live_id': liveAirUnpub,
    'seller_id': s2,
    'title': '$prefix raffle unpub',
    'status': 'active',
    'winner_count': 1,
  });
  c.note('fix.raffle', 'raffle S2 unpublished', raffle, lens: 'CM1');
  final raffleId = raffle.firstId;
  if (raffleId != null) c.createdRaffleIds.add(raffleId);

  await dumpJson('${outDir()}/pass1_ids.json', {
    's1': s1,
    's2': s2,
    'b1': b1,
    'b2': c.buyer2Id,
    'airPub': liveAirPub,
    'airUnpub': liveAirUnpub,
    'schedUnpub': liveSchedUnpub,
    'endedUnpub': liveEndedUnpub,
    'itemUnpub': itemUnpub,
    'itemPub': itemPub,
    'prodUnpub': prodUnpub,
    'prodDead': prodDead,
    'prodOk': prodOk,
    'reviewId': reviewId,
    'raffleId': raffleId,
    'handleS2': 'rtcm1318s2',
    'pbAir': pbAir,
  });

  // ----- A1 hub_lives_public unpublished -----
  final a1 = await c.rest(
    'GET',
    'hub_lives_public?id=eq.$liveAirUnpub&select=id,title,seller_id',
  );
  final a1Leak = leakRow(a1);
  c.probe(
    id: 'A1',
    poco: 'CM-A',
    payload: 'GET hub_lives_public unpublished live $liveAirUnpub',
    http: a1,
    result: a1Leak ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );
  if (a1Leak) {
    c.hold(
      id: 'CM-A1-HUB-LIVES-UNPUB',
      lens: 'CM1',
      severity: 'P2',
      title: 'hub_lives_public mostra live unpublished',
      actor: 'anon',
      pre: 'S2 hub_published=false live air',
      repro: 'GET hub_lives_public?id=eq.$liveAirUnpub',
      expected: '[]',
      obtained: a1.brief,
    );
  }

  // ----- A2 hub_lives_discovery_public -----
  final a2 = await c.rest(
    'GET',
    'hub_lives_discovery_public?id=eq.$liveAirUnpub&select=id,title',
  );
  final a2Leak = leakRow(a2);
  c.probe(
    id: 'A2',
    poco: 'CM-A',
    payload: 'GET hub_lives_discovery_public unpublished',
    http: a2,
    result: a2Leak ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );
  if (a2Leak) {
    c.hold(
      id: 'CM-A2-HUB-DISC-UNPUB',
      lens: 'CM1',
      severity: 'P2',
      title: 'hub_lives_discovery_public mostra unpublished',
      actor: 'anon',
      pre: liveAirUnpub,
      repro: 'GET hub_lives_discovery_public?id=eq.$liveAirUnpub',
      expected: '[]',
      obtained: a2.brief,
    );
  }

  // ----- A3 hub_live_items unpublished -----
  final a3 = await c.rest(
    'GET',
    'hub_live_items_public?id=eq.$itemUnpub&select=id,title,price,quantity',
  );
  final a3b = await c.rest(
    'GET',
    'hub_live_items_discovery_public?id=eq.$itemUnpub&select=id,title,price',
  );
  final a3Leak = leakRow(a3) || leakRow(a3b);
  c.probe(
    id: 'A3',
    poco: 'CM-A',
    payload: 'GET hub_live_items_public + discovery unpublished item',
    http: {'pub': a3.brief, 'disc': a3b.brief},
    result: a3Leak ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );
  if (a3Leak) {
    c.hold(
      id: 'CM-A3-HUB-ITEMS-UNPUB',
      lens: 'CM1',
      severity: 'P2',
      title: 'hub_live_items_* mostra item unpublished',
      actor: 'anon',
      pre: '$itemUnpub',
      repro: 'GET hub_live_items_public / discovery',
      expected: '[]',
      obtained: {'pub': a3.brief, 'disc': a3b.brief},
    );
  }

  // ----- A4 hub_products unpublished -----
  final a4 = await c.rest(
    'GET',
    'hub_products_public?id=eq.$prodUnpub&select=id,title,price,quantity',
  );
  final a4Leak = leakRow(a4);
  c.probe(
    id: 'A4',
    poco: 'CM-A',
    payload: 'GET hub_products_public unpublished SKU',
    http: a4,
    result: a4Leak ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );
  if (a4Leak) {
    c.hold(
      id: 'CM-A4-HUB-PROD-UNPUB',
      lens: 'CM1',
      severity: 'P2',
      title: 'hub_products_public mostra SKU unpublished',
      actor: 'anon',
      pre: '$prodUnpub',
      repro: 'GET hub_products_public?id=eq.$prodUnpub',
      expected: '[]',
      obtained: a4.brief,
    );
  }

  // ----- A5 REST lives live+active unpublished (buyer) -----
  final a5 = await c.rest(
    'GET',
    'lives?id=eq.$liveAirUnpub&select=id,status,is_active,title,seller_id',
    jwt: c.buyerJwt,
  );
  final a5feed = await c.rest(
    'GET',
    'lives?status=eq.live&is_active=eq.true&select=id,title,seller_id&limit=80',
    jwt: c.buyerJwt,
  );
  final a5inFeed = a5feed.list.any(
    (r) => r is Map && '${r['id']}' == liveAirUnpub,
  );
  final a5Leak = leakRow(a5) || a5inFeed;
  c.probe(
    id: 'A5',
    poco: 'CM-A',
    payload: 'B1 GET lives live+active unpublished + feed',
    http: {'byId': a5.brief, 'inFeed': a5inFeed, 'feedN': a5feed.list.length},
    bd: {'live': liveAirUnpub, 'hub_published': false},
    result: a5Leak ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );
  if (a5Leak) {
    c.hold(
      id: 'CM-A5-REST-LIVES-UNPUB',
      lens: 'CM1',
      severity: 'P2',
      title: 'REST lives live+active unpublished visível a B1',
      actor: 'B1',
      pre: 'S2 unpublished broadcasting',
      repro: 'GET lives?id=eq.airUnpub JWT B1',
      expected: '[] (CDCI hub_published gate)',
      obtained: {'byId': a5.brief, 'inFeed': a5inFeed},
    );
  }

  // ----- A6 scheduled unpublished -----
  final a6 = await c.rest(
    'GET',
    'lives?id=eq.$liveSchedUnpub&select=id,status,is_active,title',
    jwt: c.buyerJwt,
  );
  final a6Leak = leakRow(a6);
  c.probe(
    id: 'A6',
    poco: 'CM-A',
    payload: 'B1 GET lives scheduled unpublished',
    http: a6,
    result: a6Leak ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );
  if (a6Leak) {
    c.hold(
      id: 'CM-A6-REST-SCHED-UNPUB',
      lens: 'CM1',
      severity: 'P2',
      title: 'REST lives scheduled unpublished visível a B1',
      actor: 'B1',
      pre: '$liveSchedUnpub',
      repro: 'GET lives?id=eq.schedUnpub',
      expected: '[] (só dono)',
      obtained: a6.brief,
    );
  }

  // ----- A7 live_items unpublished -----
  final a7anon = await c.rest(
    'GET',
    'live_items?id=eq.$itemUnpub&select=id,title,price,quantity,live_id',
  );
  final a7b1 = await c.rest(
    'GET',
    'live_items?id=eq.$itemUnpub&select=id,title,price,quantity,live_id',
    jwt: c.buyerJwt,
  );
  final a7Leak = leakRow(a7anon) || leakRow(a7b1);
  c.probe(
    id: 'A7',
    poco: 'CM-A',
    payload: 'GET live_items unpublished anon+B1',
    http: {'anon': a7anon.brief, 'b1': a7b1.brief},
    result: a7Leak ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );
  if (a7Leak) {
    c.hold(
      id: 'CM-A7-LIVEITEMS-UNPUB',
      lens: 'CM1',
      severity: 'P2',
      title: 'live_items unpublished lê título/preço/qty',
      actor: leakRow(a7anon) ? 'anon' : 'B1',
      pre: '$itemUnpub qty=4 price=17.5',
      repro: 'GET live_items?id=eq.itemUnpub',
      expected: '[]',
      obtained: {'anon': a7anon.brief, 'b1': a7b1.brief},
    );
  }

  // ----- A8 batata_live_item_stock unpublished -----
  final a8anon = await c.rpc(
    'batata_live_item_stock',
    {'p_live_item_id': itemUnpub},
  );
  final a8b1 = await c.rpc(
    'batata_live_item_stock',
    {'p_live_item_id': itemUnpub},
    jwt: c.buyerJwt,
  );
  bool stockOk(HttpHit h) {
    final m = h.map;
    if (m == null) return false;
    return m['ok'] == true || m['total_qty'] != null || m['available_qty'] != null;
  }

  final a8Leak = stockOk(a8anon) || stockOk(a8b1);
  c.probe(
    id: 'A8',
    poco: 'CM-A',
    payload: 'RPC batata_live_item_stock unpublished anon+B1',
    http: {'anon': a8anon.brief, 'b1': a8b1.brief},
    result: a8Leak ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );
  if (a8Leak) {
    c.hold(
      id: 'CM-A8-STOCK-RPC-UNPUB',
      lens: 'CM1',
      severity: 'P2',
      title: 'batata_live_item_stock devolve stock unpublished',
      actor: stockOk(a8anon) ? 'anon' : 'B1',
      pre: itemUnpub ?? '',
      repro: 'POST batata_live_item_stock',
      expected: 'ok=false live_item_not_found',
      obtained: {'anon': a8anon.brief, 'b1': a8b1.brief},
    );
  }

  // ----- A9 follow UUID unpublished -----
  await c.rest(
    'DELETE',
    'follows?follower_id=eq.$b1&following_id=eq.$s2',
    jwt: c.buyerJwt,
    prefer: 'return=minimal',
  );
  final a9 = await c.rest('POST', 'follows', jwt: c.buyerJwt, body: {
    'follower_id': b1,
    'following_id': s2,
  });
  if (a9.firstId != null) c.createdFollowIds.add(a9.firstId!);
  var tickets = 0;
  if (raffleId != null) {
    final ent = await c.rest(
      'GET',
      'live_raffle_entries?raffle_id=eq.$raffleId&user_id=eq.$b1&select=id,ticket_balance',
      service: true,
    );
    final tb = ent.map?['ticket_balance'];
    if (tb is num) tickets = tb.toInt();
    c.note('a9.raffle.tickets', 'tickets after follow unpub', ent, lens: 'CM7');
  }
  final a9Ok = a9.ok && a9.firstId != null;
  c.probe(
    id: 'A9',
    poco: 'CM-A',
    payload: 'B1 POST follows following_id=S2 unpublished UUID',
    http: a9,
    bd: {'tickets': tickets, 'raffle': raffleId},
    result: a9Ok ? 'FAIL' : 'HOLD',
    lens: 'CM1',
    countFinding: a9Ok,
  );
  if (a9Ok) {
    c.hold(
      id: 'CM-A9-FOLLOW-UUID-UNPUB',
      lens: 'CM1',
      severity: tickets > 0 ? 'P1' : 'P2',
      title: tickets > 0
          ? 'follow UUID unpublished cria aresta e atribui rifa'
          : 'follow UUID unpublished aceite (oráculo de existência)',
      actor: 'B1',
      pre: 'S2 hub off; UUID conhecido; raffle active=$raffleId',
      repro: 'POST follows following_id=S2',
      expected: '403/404 loja não publicada',
      obtained: {'insert': a9.brief, 'tickets': tickets},
    );
  }

  // ----- A10 follow published (controlo) -----
  await c.rest(
    'DELETE',
    'follows?follower_id=eq.$b1&following_id=eq.$s1',
    jwt: c.buyerJwt,
    prefer: 'return=minimal',
  );
  final a10 = await c.rest('POST', 'follows', jwt: c.buyerJwt, body: {
    'follower_id': b1,
    'following_id': s1,
  });
  if (a10.firstId != null) c.createdFollowIds.add(a10.firstId!);
  c.probe(
    id: 'A10',
    poco: 'CM-A',
    payload: 'B1 POST follows S1 published (controlo)',
    http: a10,
    result: a10.ok ? 'HOLD' : 'SKIP',
    lens: 'CM1',
  );
  if (!a10.ok) {
    c.skip('A10', 'CM1', 'follow published recusado', a10);
  }

  // ----- A11 timing oracle unpublished vs ghost UUID -----
  const ghost = '00000000-0000-4000-a000-0000000000c1';
  await c.rest(
    'DELETE',
    'follows?follower_id=eq.${c.buyer2Id}&following_id=eq.$s2',
    jwt: c.buyer2Jwt,
    prefer: 'return=minimal',
  );
  final tUnpub = await c.rest('POST', 'follows', jwt: c.buyer2Jwt, body: {
    'follower_id': c.buyer2Id,
    'following_id': s2,
  });
  if (tUnpub.firstId != null) c.createdFollowIds.add(tUnpub.firstId!);
  final tGhost = await c.rest('POST', 'follows', jwt: c.buyer2Jwt, body: {
    'follower_id': c.buyer2Id,
    'following_id': ghost,
  });
  final unpubMs = tUnpub.elapsedMs ?? 0;
  final ghostMs = tGhost.elapsedMs ?? 0;
  final statusOracle = tUnpub.ok && !tGhost.ok;
  final timeOracle = (unpubMs - ghostMs).abs() > 80 && statusOracle;
  final a11Fail = statusOracle;
  c.probe(
    id: 'A11',
    poco: 'CM-A',
    payload: 'B2 follow unpublished vs ghost UUID timing/status',
    http: {
      'unpub': tUnpub.brief,
      'ghost': tGhost.brief,
      'unpubMs': unpubMs,
      'ghostMs': ghostMs,
      'statusOracle': statusOracle,
      'timeOracle': timeOracle,
    },
    result: a11Fail ? 'FAIL' : 'HOLD',
    lens: 'CM1',
    countFinding: a11Fail,
  );
  if (a11Fail) {
    c.hold(
      id: 'CM-A11-FOLLOW-TIMING-ORACLE',
      lens: 'CM1',
      severity: 'P2',
      title: 'follow distingue UUID unpublished (201) de UUID fantasma',
      actor: 'B2',
      pre: 'S2 unpublished vs $ghost',
      repro: 'POST follows unpublished; POST follows ghost UUID',
      expected: 'mesma recusa (sem oráculo de existência)',
      obtained: {
        'unpub': tUnpub.brief,
        'ghost': tGhost.brief,
        'deltaMs': unpubMs - ghostMs,
      },
    );
  }

  // ----- A12 anon follow -----
  final a12 = await c.rest('POST', 'follows', body: {
    'follower_id': b1,
    'following_id': s2,
  });
  final a12Ok = a12.ok;
  c.probe(
    id: 'A12',
    poco: 'CM-A',
    payload: 'anon POST follows unpublished',
    http: a12,
    result: a12Ok ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );
  if (a12Ok) {
    c.hold(
      id: 'CM-A12-ANON-FOLLOW',
      lens: 'CM1',
      severity: 'P1',
      title: 'anon consegue seguir UUID unpublished',
      actor: 'anon',
      pre: s2,
      repro: 'POST follows sem JWT',
      expected: '401',
      obtained: a12.brief,
    );
  }

  // ----- A13 favorite unpublished -----
  if (prodUnpub != null) {
    await c.rest(
      'DELETE',
      'favorites?user_id=eq.$b1&product_id=eq.$prodUnpub',
      jwt: c.buyerJwt,
      prefer: 'return=minimal',
    );
    final a13 = await c.rest('POST', 'favorites', jwt: c.buyerJwt, body: {
      'user_id': b1,
      'product_id': prodUnpub,
    });
    final a13get = await c.rest(
      'GET',
      'favorites?product_id=eq.$prodUnpub&select=id,product_id',
      jwt: c.buyerJwt,
    );
    final a13Ok = a13.ok && a13.firstId != null;
    c.probe(
      id: 'A13',
      poco: 'CM-A',
      payload: 'B1 POST favorites product unpublished UUID',
      http: {'insert': a13.brief, 'get': a13get.brief},
      result: a13Ok ? 'FAIL' : 'HOLD',
      lens: 'CM1',
      countFinding: a13Ok,
    );
    if (a13Ok) {
      c.hold(
        id: 'CM-A13-FAV-UNPUB',
        lens: 'CM1',
        severity: 'P2',
        title: 'favorite SKU unpublished aceite (UUID oracle)',
        actor: 'B1',
        pre: prodUnpub,
        repro: 'POST favorites product_id unpublished',
        expected: '403/FK se SKU não visível',
        obtained: {'insert': a13.brief, 'get': a13get.brief},
      );
    }
  } else {
    c.probe(
      id: 'A13',
      poco: 'CM-A',
      payload: 'favorite unpublished — sem produto',
      http: 'SKIP no prodUnpub',
      result: 'SKIP',
      lens: 'CM1',
    );
  }

  // ----- A14 reviews hub unpublished -----
  final a14hub = await c.rest(
    'GET',
    'hub_reviews_public?target_id=eq.$s2&select=id,stars,comment,author_display',
  );
  final a14rg = await c.rest(
    'GET',
    'reviews_gerais?target_id=eq.$s2&select=id,stars,comment,buyer_id',
    jwt: c.buyerJwt,
  );
  final a14anon = await c.rest(
    'GET',
    'reviews_gerais?target_id=eq.$s2&select=id,stars',
  );
  final a14Leak = leakRow(a14hub);
  c.probe(
    id: 'A14',
    poco: 'CM-A',
    payload: 'GET hub_reviews_public + reviews_gerais unpublished shop',
    http: {'hub': a14hub.brief, 'rg': a14rg.brief, 'anon': a14anon.brief},
    result: a14Leak ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );
  if (a14Leak) {
    c.hold(
      id: 'CM-A14-REVIEWS-UNPUB',
      lens: 'CM1',
      severity: 'P2',
      title: 'hub_reviews_public mostra opiniões de loja unpublished',
      actor: 'anon',
      pre: s2,
      repro: 'GET hub_reviews_public?target_id=S2',
      expected: '[]',
      obtained: a14hub.brief,
    );
  }

  // ----- A15 search / RPC handle slug -----
  final a15res = await c.rpc(
    'batata_resolve_handle',
    {'p_handle': 'rtcm1318s2'},
  );
  final a15slug = await c.rpc(
    'batata_resolve_handle',
    {'p_handle': 'rtcm-20260906t1318-s2'},
  );
  final a15ilike = await c.rest(
    'GET',
    'hub_profiles_discovery_public?handle=ilike.*rtcm1318s2*&select=id,handle',
  );
  final a15prof = await c.rest(
    'GET',
    'profiles?handle=eq.rtcm1318s2&select=id,handle,hub_published,full_name',
    jwt: c.buyerJwt,
  );
  await c.rest('POST', 'profile_handle_redirects', service: true, body: {
    'old_handle': 'rtcm-old-unpub-1318',
    'new_handle': 'rtcm1318s2',
    'profile_id': s2,
  });
  final a15redir = await c.rpc(
    'batata_resolve_handle',
    {'p_handle': 'rtcm-old-unpub-1318'},
  );
  final foundDirect = a15res.map?['found'] == true;
  final foundSlug = a15slug.map?['found'] == true;
  final foundRedir = a15redir.map?['found'] == true;
  final foundIlike = leakRow(a15ilike);
  final foundProf = leakRow(a15prof);
  final a15Fail = foundDirect || foundSlug || foundRedir || foundIlike;
  c.probe(
    id: 'A15',
    poco: 'CM-A',
    payload: 'RPC resolve handle/slug/redirect + discovery ilike + profiles eq',
    http: {
      'direct': a15res.brief,
      'slug': a15slug.brief,
      'redir': a15redir.brief,
      'ilike': a15ilike.brief,
      'profiles': a15prof.brief,
    },
    result: a15Fail ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );
  if (foundRedir) {
    c.hold(
      id: 'CM-A15-RESOLVE-REDIRECT-UNPUB',
      lens: 'CM1',
      severity: 'P2',
      title: 'resolve_handle 301 para destino unpublished',
      actor: 'anon',
      pre: 'redirect rtcm-old-unpub-1318 → rtcm1318s2',
      repro: 'POST batata_resolve_handle old handle',
      expected: 'found=false (CDCI)',
      obtained: a15redir.brief,
      countExactClosed: true,
    );
  } else if (foundDirect || foundSlug || foundIlike) {
    c.hold(
      id: 'CM-A15-SEARCH-UNPUB',
      lens: 'CM1',
      severity: 'P2',
      title: 'search/RPC revela handle unpublished',
      actor: 'anon/B1',
      pre: 'rtcm1318s2 unpublished',
      repro: 'resolve / discovery ilike',
      expected: 'not_found / []',
      obtained: {
        'direct': a15res.brief,
        'slug': a15slug.brief,
        'ilike': a15ilike.brief,
      },
    );
  }
  if (foundProf && !foundDirect) {
    c.note('a15.profiles.rest', 'profiles REST B1 unpublished', a15prof,
        lens: 'CM1');
  }

  // ----- A16 products qty=0 + unpublished enum -----
  final a16unpub = await c.rest(
    'GET',
    'products?id=eq.$prodUnpub&select=id,title,price,quantity,list_on_marketplace,seller_id',
    jwt: c.buyerJwt,
  );
  final a16qty0 = await c.rest(
    'GET',
    'products?id=eq.$prodDead&select=id,title,price,quantity,list_on_marketplace',
    jwt: c.buyerJwt,
  );
  final a16enum = await c.rest(
    'GET',
    'products?list_on_marketplace=eq.true&order=created_at.desc&select=id,title,quantity,seller_id&limit=40',
    jwt: c.buyerJwt,
  );
  final hasUnpub = a16enum.list.any((r) => r is Map && '${r['id']}' == prodUnpub);
  final hasQty0 = a16enum.list.any((r) => r is Map && '${r['id']}' == prodDead);
  final a16Fail = leakRow(a16unpub) || leakRow(a16qty0) || hasUnpub || hasQty0;
  c.probe(
    id: 'A16',
    poco: 'CM-A',
    payload: 'B1 GET products unpublished + qty=0 + enum marketplace',
    http: {
      'unpub': a16unpub.brief,
      'qty0': a16qty0.brief,
      'enumHasUnpub': hasUnpub,
      'enumHasQty0': hasQty0,
    },
    result: a16Fail ? 'FAIL' : 'HOLD',
    lens: 'CM1',
  );
  if (a16Fail) {
    c.hold(
      id: 'CM-A16-PRODUCTS-ENUM',
      lens: 'CM1',
      severity: 'P2',
      title: 'REST products mostra SKU unpublished e/ou qty=0',
      actor: 'B1',
      pre: 'prodUnpub qty=5; prodDead qty=0',
      repro: 'GET products by id + list_on_marketplace enum',
      expected: '[] / qty>0 + hub_published (CDCI)',
      obtained: {
        'unpub': a16unpub.brief,
        'qty0': a16qty0.brief,
        'enumHasUnpub': hasUnpub,
        'enumHasQty0': hasQty0,
      },
    );
  }

  // ----- Residual CDCI ≤3 -----
  final r1 = await c.rpc('batata_resolve_handle', {'p_handle': 'rtcm1318s2'});
  final r1Found = r1.map?['found'] == true;
  c.probe(
    id: 'R1',
    poco: 'CDCI-residual',
    payload: 'resolve_handle handle unpublished clássico',
    http: r1,
    result: r1Found ? 'FAIL' : 'HOLD',
    lens: 'CM1',
    residual: true,
  );

  final r2 = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyer2Jwt,
    body: {
      'live_id': liveAirUnpub,
      'seller_id': s2,
      'amount_eur': 2,
    },
  );
  c.probe(
    id: 'R2',
    poco: 'CDCI-residual',
    payload: 'tip unpublished clássico (checkout com loja já off)',
    http: r2,
    result: r2.ok ? 'FAIL' : 'HOLD',
    lens: 'CM3',
    residual: true,
  );
  if (r2.ok) {
    c.hold(
      id: 'CM-R2-TIP-UNPUB-CLASSIC',
      lens: 'CM3',
      severity: 'P2',
      title: 'tip checkout em live unpublished (clássico CG)',
      actor: 'B2',
      pre: 'S2 unpublished air',
      repro: 'POST create-live-tip-checkout',
      expected: 'recusa published-only',
      obtained: r2.brief,
      countExactClosed: true,
    );
  }

  final r3b1 = await c.rest(
    'GET',
    'lives?id=eq.$liveAirUnpub&select=id,mux_playback_id,playback_id,mux_stream_key',
    jwt: c.buyerJwt,
  );
  final r3own = await c.rest(
    'GET',
    'lives?id=eq.$liveAirUnpub&select=id,mux_playback_id,playback_id,mux_stream_key',
    jwt: c.seller2Jwt,
  );
  final r3leak = r3b1.ok &&
      (r3b1.body.contains('mux_playback') ||
          col(r3b1.map, 'mux_playback_id') != null ||
          col(r3b1.map, 'playback_id') != null);
  c.probe(
    id: 'R3',
    poco: 'CDCI-residual',
    payload: 'SELECT mux_playback_id JWT B1 vs dono unpublished',
    http: {'b1': r3b1.brief, 'owner': r3own.brief},
    result: r3leak ? 'FAIL' : 'HOLD',
    lens: 'CM5',
    residual: true,
  );

  await dumpJson('${outDir()}/pass1.json', {
    'lenses': c.lensesHit.toList()..sort(),
    'probes': c.probes,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'skipped': c.skipped,
  });
}
