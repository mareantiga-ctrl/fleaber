/// RED TEAM CEGO CG pass1 — Hub discovery matrix, stock Hub vs PostgREST,
/// reviews, follow/favorite, live+hub off, dono JWT vs anon.
import 'dart:io';
import '_rtcg.dart';

Future<void> main() async {
  final c = Rtcg.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final s1 = c.sellerId!;
  final s2 = c.seller2Id!;
  final b1 = c.buyerId!;
  final s1p = await c.profile(s1);
  final s2p = await c.profile(s2);
  c.note('fix.s1', 'S1 profile', s1p, lens: 'CG1');
  c.note('fix.s2', 'S2 unpublished', s2p, lens: 'CG1');

  if (s1p?['hub_published'] != true) {
    await c.rest('PATCH', 'profiles?id=eq.$s1', service: true, body: {
      'hub_published': true,
    }, prefer: 'return=minimal');
  }
  await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'hub_published': false,
    'handle': 'rtcg1235s2',
    'is_live': true,
  }, prefer: 'return=minimal');

  const fakePb = 'rtcgPbLive1235aaaa';
  const fakeVod = 'rtcgPbVod1235bbbb';
  const fakeStream = 'rtcgStreamKey1235secret';

  String? realPb;
  final real = await c.rest(
    'GET',
    'lives?mux_playback_id=not.is.null&select=id,mux_playback_id&limit=4',
    service: true,
  );
  for (final row in real.list) {
    if (row is Map) {
      final pb = '${row['mux_playback_id'] ?? ''}'.trim();
      if (pb.length > 8 && !pb.startsWith('rtcg')) {
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
    muxLiveId: 'muxLiveAirPub1235',
    title: '$prefix air-pub',
  );
  final liveAirUnpub = await c.insertLive(
    seller: s2,
    active: true,
    status: 'live',
    muxPlayback: pbAir,
    muxStreamKey: fakeStream,
    muxLiveId: 'muxLiveAirUnpub1235',
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
  final liveSchedPub = await c.insertLive(
    seller: s1,
    active: false,
    status: 'scheduled',
    title: '$prefix sched-pub',
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
  c.note('fix.review', 'review S2', rev, lens: 'CG1');
  final reviewId = rev.firstId;
  if (reviewId != null) c.createdReviewIds.add(reviewId);

  await dumpJson('${outDir()}/pass1_ids.json', {
    's1': s1,
    's2': s2,
    'b1': b1,
    'b2': c.buyer2Id,
    'airPub': liveAirPub,
    'airUnpub': liveAirUnpub,
    'schedUnpub': liveSchedUnpub,
    'endedUnpub': liveEndedUnpub,
    'schedPub': liveSchedPub,
    'itemUnpub': itemUnpub,
    'itemPub': itemPub,
    'prodUnpub': prodUnpub,
    'prodDead': prodDead,
    'prodOk': prodOk,
    'reviewId': reviewId,
    'handleS2': 'rtcg1235s2',
    'pbAir': pbAir,
  });

  Future<HttpHit> viewGet(String view, String id, {String? jwt}) {
    return c.rest(
      'GET',
      '$view?id=eq.$id&select=*',
      jwt: jwt,
    );
  }

  // ---------- CG-A1 resolve_handle (exact unpublished = residual) ----------
  final resolveUnpub = await c.rpc(
    'batata_resolve_handle',
    {'p_handle': 'rtcg1235s2'},
  );
  c.note('cg1.resolve.unpub', 'resolve unpublished handle', resolveUnpub,
      lens: 'CG1');
  final rf = resolveUnpub.map;
  final foundUnpub = rf?['found'] == true;
  if (foundUnpub) {
    c.hold(
      id: 'CG1-RESOLVE-UNPUB-EXACT',
      lens: 'CG1',
      severity: 'P2',
      title: 'resolve_handle encontra loja unpublished (exacto BXCC)',
      actor: 'anon',
      pre: 'S2 hub_published=false handle=rtcg1235s2',
      repro: 'POST batata_resolve_handle p_handle=rtcg1235s2',
      expected: 'found=false not_found',
      obtained: resolveUnpub.brief,
      countExactClosed: true,
    );
  } else {
    c.block('cg1.resolve.unpub', 'CG1', 'resolve unpublished not_found',
        resolveUnpub);
  }

  final resolveSlug = await c.rpc(
    'batata_resolve_handle',
    {'p_handle': 'rtcg-20260906t1235-s2'},
  );
  c.note('cg1.resolve.slug', 'resolve discovery slug S2', resolveSlug,
      lens: 'CG1');

  // Redirect hole: old handle → unpublished destination
  final redIns = await c.rest('POST', 'profile_handle_redirects', service: true, body: {
    'old_handle': 'rtcg-old-unpub-1235',
    'new_handle': 'rtcg1235s2',
    'profile_id': s2,
  });
  c.note('cg1.redirect.insert', 'redirect to unpublished', redIns, lens: 'CG1');
  final resolveRedir = await c.rpc(
    'batata_resolve_handle',
    {'p_handle': 'rtcg-old-unpub-1235'},
  );
  c.note('cg1.resolve.redirect', 'resolve via redirect unpublished', resolveRedir,
      lens: 'CG1');
  final rrm = resolveRedir.map;
  if (rrm?['found'] == true) {
    c.hold(
      id: 'CG1-RESOLVE-REDIRECT-UNPUB',
      lens: 'CG1',
      severity: 'P2',
      title: 'resolve_handle 301 para loja unpublished via redirect',
      actor: 'anon',
      pre: 'profile_handle_redirects old→rtcg1235s2 unpublished',
      repro: 'POST batata_resolve_handle p_handle=rtcg-old-unpub-1235',
      expected: 'found=false (destino unpublished)',
      obtained: resolveRedir.brief,
    );
  } else {
    c.block('cg1.resolve.redirect', 'CG1', 'redirect unpublished recusado',
        resolveRedir);
  }

  // ---------- views hub_* unpublished ----------
  for (final e in {
    'airUnpub': liveAirUnpub,
    'schedUnpub': liveSchedUnpub,
    'endedUnpub': liveEndedUnpub,
    'airPub': liveAirPub,
  }.entries) {
    final pub = await viewGet('hub_lives_public', e.value!);
    final disc = await viewGet('hub_lives_discovery_public', e.value!);
    c.note('cg1.pub.${e.key}', 'hub_lives_public', pub, lens: 'CG1');
    c.note('cg1.disc.${e.key}', 'hub_lives_discovery_public', disc, lens: 'CG1');
    final unpub = e.key.contains('Unpub');
    if (unpub && leakRow(disc)) {
      c.hold(
        id: 'CG1-DISC-UNPUB-${e.key}',
        lens: 'CG1',
        severity: 'P2',
        title: 'hub_lives_discovery_public lista unpublished ${e.key}',
        actor: 'anon',
        pre: 'S2 hub_published=false ${e.key}',
        repro: 'GET hub_lives_discovery_public?id=eq.${e.value}',
        expected: '[]',
        obtained: disc.brief,
        countExactClosed: true,
      );
    }
    if (unpub && leakRow(pub)) {
      c.hold(
        id: 'CG1-HUBPAGE-UNPUB-${e.key}',
        lens: 'CG1',
        severity: 'P2',
        title: 'hub_lives_public lista unpublished ${e.key}',
        actor: 'anon',
        pre: e.value!,
        repro: 'GET hub_lives_public?id=eq.${e.value}',
        expected: '[]',
        obtained: pub.brief,
        countExactClosed: true,
      );
    }
  }

  final profPub = await c.rest(
    'GET',
    'hub_profiles_public?id=eq.$s2&select=id,handle',
  );
  final profDisc = await c.rest(
    'GET',
    'hub_profiles_discovery_public?id=eq.$s2&select=id,handle,hub_published',
  );
  c.note('cg1.prof.pub', 'hub_profiles_public S2', profPub, lens: 'CG1');
  c.note('cg1.prof.disc', 'hub_profiles_discovery S2', profDisc, lens: 'CG1');
  if (leakRow(profDisc)) {
    c.hold(
      id: 'CG1-PROFDISC-UNPUB-EXACT',
      lens: 'CG1',
      severity: 'P2',
      title: 'hub_profiles_discovery_public mostra unpublished',
      actor: 'anon',
      pre: s2,
      repro: 'GET hub_profiles_discovery_public?id=eq.$s2',
      expected: '[]',
      obtained: profDisc.brief,
      countExactClosed: true,
    );
  } else {
    c.block('cg1.prof.disc', 'CG1', 'profiles discovery esconde unpublished',
        profDisc);
  }

  // ---------- profiles table (entrada ≠ resolve / hub views) ----------
  final profAnon = await c.rest(
    'GET',
    'profiles?id=eq.$s2&select=id,handle,hub_published,full_name,is_live,photo_url',
  );
  final profB1 = await c.rest(
    'GET',
    'profiles?id=eq.$s2&select=id,handle,hub_published,full_name,is_live,photo_url',
    jwt: c.buyerJwt,
  );
  final profSearch = await c.rest(
    'GET',
    'profiles?handle=eq.rtcg1235s2&select=id,handle,hub_published,full_name',
    jwt: c.buyerJwt,
  );
  final profIlike = await c.rest(
    'GET',
    'hub_profiles_discovery_public?handle=ilike.*rtcg1235s2*&select=id,handle',
  );
  c.note('cg1.profiles.anon', 'profiles REST anon S2', profAnon, lens: 'CG1');
  c.note('cg1.profiles.b1', 'profiles REST B1 S2', profB1, lens: 'CG1');
  c.note('cg1.profiles.search', 'profiles handle eq B1', profSearch, lens: 'CG1');
  c.note('cg1.search.ilike', 'discovery ilike handle', profIlike, lens: 'CG1');

  final b1SeesUnpubProfile = leakRow(profB1) &&
      (col(profB1.map, 'handle') != null || col(profB1.map, 'id') == s2);
  final anonSeesUnpubProfile = leakRow(profAnon);
  if (b1SeesUnpubProfile || anonSeesUnpubProfile) {
    c.hold(
      id: 'CG1-PROFILES-REST-UNPUB',
      lens: 'CG1',
      severity: 'P2',
      title: 'tabela profiles expõe loja unpublished (Hub views escondem)',
      actor: anonSeesUnpubProfile ? 'anon' : 'B1',
      pre: 'S2 hub_published=false; hub_profiles_* = []',
      repro: 'GET /rest/v1/profiles?id=eq.$s2&select=id,handle,hub_published',
      expected: '401/403 ou [] alinhado a hub_profiles_public',
      obtained: {
        'anon': profAnon.brief,
        'b1': profB1.brief,
        'search': profSearch.brief,
        'hub_pub': profPub.brief,
        'hub_disc': profDisc.brief,
      },
    );
  } else {
    c.block('cg1.profiles.rest', 'CG1', 'profiles REST esconde unpublished',
        profB1);
  }

  // ---------- follow / favorite unpublished ----------
  final fol = await c.rest('POST', 'follows', jwt: c.buyerJwt, body: {
    'follower_id': b1,
    'following_id': s2,
  });
  c.note('cg1.follow.insert', 'B1 segue S2 unpublished', fol, lens: 'CG1');
  final folGet = await c.rest(
    'GET',
    'follows?following_id=eq.$s2&select=id,follower_id,following_id',
    jwt: c.buyerJwt,
  );
  c.note('cg1.follow.get', 'GET follows S2', folGet, lens: 'CG1');
  if (fol.ok || leakRow(folGet)) {
    c.hold(
      id: 'CG1-FOLLOW-UNPUB',
      lens: 'CG1',
      severity: 'P3',
      title: 'seguir loja unpublished (oráculo de UUID + relação)',
      actor: 'B1',
      pre: 'S2 unpublished UUID conhecido',
      repro: 'POST follows following_id=S2; GET follows',
      expected: 'recusa se loja não é vitrine',
      obtained: {'insert': fol.brief, 'get': folGet.brief},
    );
  } else {
    c.block('cg1.follow', 'CG1', 'follow unpublished recusado', fol);
  }

  if (prodUnpub != null) {
    final fav = await c.rest('POST', 'favorites', jwt: c.buyerJwt, body: {
      'user_id': b1,
      'product_id': prodUnpub,
    });
    c.note('cg1.fav.insert', 'favorite produto unpublished', fav, lens: 'CG1');
    final favGet = await c.rest(
      'GET',
      'favorites?product_id=eq.$prodUnpub&select=id,product_id',
      jwt: c.buyerJwt,
    );
    c.note('cg1.fav.get', 'GET favorites unpublished sku', favGet, lens: 'CG1');
    if (fav.ok || leakRow(favGet)) {
      c.hold(
        id: 'CG1-FAV-UNPUB-SKU',
        lens: 'CG1',
        severity: 'P3',
        title: 'favoritar SKU de loja unpublished',
        actor: 'B1',
        pre: 'produto S2 list_on_marketplace',
        repro: 'POST favorites product_id unpublished',
        expected: 'recusa / produto invisível',
        obtained: {'insert': fav.brief, 'get': favGet.brief},
      );
    } else {
      c.block('cg1.fav', 'CG1', 'favorite unpublished recusado', fav);
    }
  }

  // ---------- reviews unpublished ----------
  final hubRev = await c.rest(
    'GET',
    'hub_reviews_public?target_id=eq.$s2&select=id,stars,comment,author_display',
  );
  final revB1 = await c.rest(
    'GET',
    'reviews_gerais?target_id=eq.$s2&select=id,stars,comment,buyer_id,target_id',
    jwt: c.buyerJwt,
  );
  final revAnon = await c.rest(
    'GET',
    'reviews_gerais?target_id=eq.$s2&select=id,stars,comment',
  );
  c.note('cg1.reviews.hub', 'hub_reviews_public S2', hubRev, lens: 'CG1');
  c.note('cg1.reviews.b1', 'reviews_gerais B1 S2', revB1, lens: 'CG1');
  c.note('cg1.reviews.anon', 'reviews_gerais anon S2', revAnon, lens: 'CG1');
  if (leakRow(hubRev)) {
    c.hold(
      id: 'CG1-HUBREV-UNPUB',
      lens: 'CG1',
      severity: 'P2',
      title: 'hub_reviews_public mostra opiniões de loja unpublished',
      actor: 'anon',
      pre: 'S2 unpublished + review fixture',
      repro: 'GET hub_reviews_public?target_id=eq.$s2',
      expected: '[]',
      obtained: hubRev.brief,
    );
  } else {
    c.block('cg1.hubrev', 'CG1', 'hub_reviews esconde unpublished', hubRev);
  }
  final b1ReviewLeak = leakRow(revB1) && col(revB1.map, 'buyer_id') != null;
  if (b1ReviewLeak && col(revB1.map, 'buyer_id') != b1) {
    c.hold(
      id: 'CG1-REVIEWS-BASE-ALIEN',
      lens: 'CG1',
      severity: 'P2',
      title: 'reviews_gerais vaza buyer_id alheio de loja unpublished',
      actor: 'B1',
      pre: s2,
      repro: 'GET reviews_gerais?target_id=eq.$s2',
      expected: 'só próprias / hub view sem buyer_id',
      obtained: revB1.brief,
    );
  }

  // ---------- stock Hub vs PostgREST ----------
  Future<void> stockProbe(String label, String? prodId, {required bool expectHubHidden}) async {
    if (prodId == null) return;
    final hub = await c.rest(
      'GET',
      'hub_products_public?id=eq.$prodId&select=id,title,price,seller_id,seller_handle,is_sold',
    );
    final restAnon = await c.rest(
      'GET',
      'products?id=eq.$prodId&select=id,title,price,quantity,seller_id,list_on_marketplace,is_sold',
    );
    final restB1 = await c.rest(
      'GET',
      'products?id=eq.$prodId&select=id,title,price,quantity,seller_id,list_on_marketplace,is_sold',
      jwt: c.buyerJwt,
    );
    c.note('cg1.stock.hub.$label', 'hub_products $label', hub, lens: 'CG1');
    c.note('cg1.stock.anon.$label', 'products anon $label', restAnon, lens: 'CG1');
    c.note('cg1.stock.b1.$label', 'products B1 $label', restB1, lens: 'CG1');
    final hubEmpty = !leakRow(hub);
    final restSees = leakRow(restB1) || leakRow(restAnon);
    final qty = restB1.map?['quantity'] ?? restAnon.map?['quantity'];
    if (expectHubHidden && hubEmpty && restSees) {
      c.hold(
        id: 'CG1-STOCK-REST-$label',
        lens: 'CG1',
        severity: 'P2',
        title: 'PostgREST products mostra SKU que Hub esconde ($label)',
        actor: leakRow(restAnon) ? 'anon' : 'B1',
        pre: 'hub_products_public=[] $label prod=$prodId',
        repro:
            'GET hub_products_public vs GET products?id=eq.$prodId&select=...,quantity',
        expected: 'tabela base alinhada à vitrine Hub (sem montra morta)',
        obtained: {
          'hub': hub.brief,
          'anon': restAnon.brief,
          'b1': restB1.brief,
          'qty': qty,
        },
      );
    } else if (expectHubHidden && hubEmpty && !restSees) {
      c.block('cg1.stock.$label', 'CG1', 'products alinhado a Hub $label', restB1);
    } else if (!expectHubHidden && !hubEmpty) {
      c.block('cg1.stock.$label', 'CG1', 'Hub mostra SKU vivo $label', hub);
    }
  }

  await stockProbe('UNPUB', prodUnpub, expectHubHidden: true);
  await stockProbe('QTY0', prodDead, expectHubHidden: true);
  await stockProbe('OK', prodOk, expectHubHidden: false);

  // live items unpublished air vs hub views
  if (itemUnpub != null) {
    final hubItems = await c.rest(
      'GET',
      'hub_live_items_public?id=eq.$itemUnpub&select=id,title,price,live_id',
    );
    final hubItemsDisc = await c.rest(
      'GET',
      'hub_live_items_discovery_public?id=eq.$itemUnpub&select=id,title,price,live_id',
    );
    final liAnon = await c.rest(
      'GET',
      'live_items?id=eq.$itemUnpub&select=id,title,price,quantity,live_id,status',
    );
    final liB1 = await c.rest(
      'GET',
      'live_items?id=eq.$itemUnpub&select=id,title,price,quantity,live_id,status',
      jwt: c.buyerJwt,
    );
    final stockAnon = await c.rpc(
      'batata_live_item_stock',
      {'p_live_item_id': itemUnpub},
    );
    final stockB1 = await c.rpc(
      'batata_live_item_stock',
      {'p_live_item_id': itemUnpub},
      jwt: c.buyerJwt,
    );
    c.note('cg1.li.hub', 'hub_live_items unpublished', hubItems, lens: 'CG1');
    c.note('cg1.li.disc', 'hub_live_items_discovery unpublished', hubItemsDisc,
        lens: 'CG1');
    c.note('cg1.li.anon', 'live_items anon unpublished', liAnon, lens: 'CG1');
    c.note('cg1.li.b1', 'live_items B1 unpublished', liB1, lens: 'CG1');
    c.note('cg1.stockrpc.anon', 'stock RPC anon unpublished', stockAnon,
        lens: 'CG1');
    c.note('cg1.stockrpc.b1', 'stock RPC B1 unpublished', stockB1, lens: 'CG1');

    final hubHides = !leakRow(hubItems) && !leakRow(hubItemsDisc);
    final restShows = leakRow(liB1) || leakRow(liAnon);
    final rpcOk = stockB1.map?['ok'] == true || stockAnon.map?['ok'] == true;
    if (hubHides && (restShows || rpcOk)) {
      c.hold(
        id: 'CG1-LIVEITEM-UNPUB-AIR',
        lens: 'CG1',
        severity: 'P2',
        title: 'stock/preço de directo unpublished no ar via live_items/RPC',
        actor: leakRow(liAnon) || stockAnon.map?['ok'] == true ? 'anon' : 'B1',
        pre: 'S2 hub off + live broadcasting + item qty=4 price=17.5',
        repro:
            'GET hub_live_items_* vs GET live_items vs RPC batata_live_item_stock',
        expected: 'alinhado a Hub (live_not_public / [])',
        obtained: {
          'hub': hubItems.brief,
          'disc': hubItemsDisc.brief,
          'anon': liAnon.brief,
          'b1': liB1.brief,
          'rpc_anon': stockAnon.brief,
          'rpc_b1': stockB1.brief,
        },
      );
    } else {
      c.block('cg1.li.unpub', 'CG1', 'live_items unpublished alinhado', liB1);
    }
  }

  // ---------- lives REST unpublished (mux cols = residual; existence/seller) ----------
  const muxCols =
      'id,status,is_active,seller_id,title,mux_playback_id,mux_vod_playback_id,mux_asset_id,mux_stream_key,playback_id';
  const safeCols = 'id,status,is_active,seller_id,title,viewer_count';
  for (final e in {
    'airUnpub': liveAirUnpub,
    'schedUnpub': liveSchedUnpub,
    'endedUnpub': liveEndedUnpub,
  }.entries) {
    final anonMux = await c.rest('GET', 'lives?id=eq.${e.value}&select=$muxCols');
    final b1Mux = await c.rest(
      'GET',
      'lives?id=eq.${e.value}&select=$muxCols',
      jwt: c.buyerJwt,
    );
    final b1Safe = await c.rest(
      'GET',
      'lives?id=eq.${e.value}&select=$safeCols',
      jwt: c.buyerJwt,
    );
    final s2Mux = await c.rest(
      'GET',
      'lives?id=eq.${e.value}&select=$muxCols',
      jwt: c.seller2Jwt,
    );
    c.note('cg5.anon.mux.${e.key}', 'anon mux cols', anonMux, lens: 'CG5');
    c.note('cg5.b1.mux.${e.key}', 'B1 mux cols', b1Mux, lens: 'CG5');
    c.note('cg5.b1.safe.${e.key}', 'B1 safe cols', b1Safe, lens: 'CG5');
    c.note('cg5.s2.mux.${e.key}', 'S2 owner mux', s2Mux, lens: 'CG5');

    final b1pb = col(b1Mux.map, 'mux_playback_id') ?? col(b1Mux.map, 'playback_id');
    if (b1pb != null) {
      c.hold(
        id: 'CG5-B1-RESTPB-${e.key}',
        lens: 'CG5',
        severity: 'P2',
        title: 'B1 lê playback de unpublished ${e.key} (exacto residual mux)',
        actor: 'B1',
        pre: e.value!,
        repro: 'GET lives select mux_playback_id,playback_id',
        expected: '403 / coluna ausente',
        obtained: b1Mux.brief,
        countExactClosed: true,
      );
    }
    final ownerPb =
        col(s2Mux.map, 'mux_playback_id') ?? col(s2Mux.map, 'playback_id');
    if (ownerPb != null && b1pb == null) {
      c.block('cg5.owner.split.${e.key}', 'CG5',
          'dono lê playback; B1 não (split)', s2Mux);
    }
  }

  final b1Dir = await c.rest(
    'GET',
    'lives?seller_id=eq.$s2&select=$safeCols',
    jwt: c.buyerJwt,
  );
  c.note('cg1.lives.dir.b1', 'B1 directory S2 lives', b1Dir, lens: 'CG1');
  if (leakRow(b1Dir)) {
    c.hold(
      id: 'CG1-LIVES-DIR-UNPUB',
      lens: 'CG1',
      severity: 'P2',
      title: 'JWT lista directos de loja unpublished (Hub discovery [])',
      actor: 'B1',
      pre: 'S2 hub off; lives air+sched+ended',
      repro: 'GET lives?seller_id=eq.$s2&select=id,status,title',
      expected: '[] ou só se Hub publicado',
      obtained: b1Dir.brief,
    );
  } else {
    c.block('cg1.lives.dir', 'CG1', 'directory unpublished vazio', b1Dir);
  }

  // FOMO unpublished
  final fomoUnpub = await c.rpc(
    'batata_hub_live_fomo_snapshot',
    {'p_live_id': liveAirUnpub},
  );
  c.note('cg1.fomo.unpub', 'FOMO unpublished air', fomoUnpub, lens: 'CG1');
  if (fomoUnpub.map?['ok'] == true) {
    c.hold(
      id: 'CG1-FOMO-UNPUB-AIR',
      lens: 'CG1',
      severity: 'P2',
      title: 'FOMO ok em directo unpublished no ar',
      actor: 'anon',
      pre: liveAirUnpub,
      repro: 'POST batata_hub_live_fomo_snapshot',
      expected: 'live_not_public',
      obtained: fomoUnpub.brief,
    );
  } else {
    c.block('cg1.fomo.unpub', 'CG1', 'FOMO unpublished recusado', fomoUnpub);
  }

  // resolve-mux unpublished vs owner
  final rmAnon = await c.edge(
    'resolve-mux-playback',
    body: {'live_id': liveAirUnpub},
  );
  final rmB1 = await c.edge(
    'resolve-mux-playback',
    jwt: c.buyerJwt,
    body: {'live_id': liveAirUnpub},
  );
  final rmS2 = await c.edge(
    'resolve-mux-playback',
    jwt: c.seller2Jwt,
    body: {'live_id': liveAirUnpub},
  );
  c.note('cg5.rm.anon', 'resolve-mux unpublished anon', rmAnon, lens: 'CG5');
  c.note('cg5.rm.b1', 'resolve-mux unpublished B1', rmB1, lens: 'CG5');
  c.note('cg5.rm.s2', 'resolve-mux unpublished owner', rmS2, lens: 'CG5');
  final anonMuxOk = rmAnon.ok && col(rmAnon.map, 'playback_id') != null;
  final b1MuxOk = rmB1.ok && col(rmB1.map, 'playback_id') != null;
  final s2MuxOk = rmS2.ok && col(rmS2.map, 'playback_id') != null;
  if (anonMuxOk || b1MuxOk) {
    c.hold(
      id: 'CG5-RESOLVE-UNPUB-AIR',
      lens: 'CG5',
      severity: 'P2',
      title: 'resolve-mux playback de loja unpublished no ar',
      actor: anonMuxOk ? 'anon' : 'B1',
      pre: liveAirUnpub,
      repro: 'POST resolve-mux-playback live_id unpublished air',
      expected: '404 live_not_public',
      obtained: {'anon': rmAnon.brief, 'b1': rmB1.brief, 's2': rmS2.brief},
      countExactClosed: true,
    );
  } else {
    c.block('cg5.rm.unpub', 'CG5', 'resolve-mux unpublished 404', rmB1);
  }
  if (s2MuxOk && !b1MuxOk && !anonMuxOk) {
    c.block('cg5.rm.owner.split', 'CG5', 'só dono resolve unpublished (studio)',
        rmS2);
  }

  // Embed lives(*)
  final embed = await c.rest(
    'GET',
    'live_items?id=eq.$itemUnpub&select=id,title,lives($muxCols)',
    jwt: c.buyerJwt,
  );
  c.note('cg5.embed', 'embed lives(*) unpublished item', embed, lens: 'CG5');
  final nested = embed.map?['lives'];
  Map<String, dynamic>? nest;
  if (nested is Map) nest = Map<String, dynamic>.from(nested);
  if (col(nest, 'mux_playback_id') != null || col(nest, 'mux_stream_key') != null) {
    c.hold(
      id: 'CG5-EMBED-UNPUB',
      lens: 'CG5',
      severity: col(nest, 'mux_stream_key') != null ? 'P0' : 'P2',
      title: 'embed live_items.lives(*) vaza Mux unpublished',
      actor: 'B1',
      pre: itemUnpub ?? '',
      repro: 'GET live_items?select=lives(mux_*)',
      expected: 'sem nested mux / 400',
      obtained: embed.brief,
    );
  } else {
    c.block('cg5.embed', 'CG5', 'embed sem mux', embed);
  }

  await dumpJson('${outDir()}/pass1.json', {
    'lenses': c.lensesHit.toList()..sort(),
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'skipped': c.skipped,
    'createdLiveIds': c.createdLiveIds,
    'createdItemIds': c.createdItemIds,
    'createdProductIds': c.createdProductIds,
  });
}
