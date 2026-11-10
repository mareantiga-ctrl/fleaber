/// RED TEAM CEGO DE pass1 — DE-A follow/favorite (≥6) + ângulos novos.
import 'dart:io';
import '_rtde.dart';

bool insertOk(HttpHit h) =>
    h.ok ||
    h.status == 409 ||
    h.body.contains('23505') ||
    h.body.toLowerCase().contains('duplicate');

Future<void> main() async {
  final c = Rtde.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final s1 = c.sellerId!;
  final s2 = c.seller2Id!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;

  await c.restoreSeller1Published();
  await c.setHub(s2, false);
  await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'user_type': 'vendedor',
    'is_live': true,
    'handle': 'rtde1538s2',
  }, prefer: 'return=minimal');
  await c.rest('PATCH', 'profiles?id=eq.$b2', service: true, body: {
    'user_type': 'comprador',
    'hub_published': false,
  }, prefer: 'return=minimal');

  final s1p = await c.profile(s1);
  final s2p = await c.profile(s2);
  final b2p = await c.profile(b2);
  c.note('fix.s1', 'S1 published', s1p, lens: 'DE1');
  c.note('fix.s2', 'S2 unpublished vendedor', s2p, lens: 'DE1');
  c.note('fix.b2', 'B2 comprador', b2p, lens: 'DE1');

  final livePub = await c.insertLive(
    seller: s1,
    active: true,
    status: 'live',
    muxPlayback: 'rtdePbLive1538aaaa',
    title: '$prefix air-pub',
  );
  final liveUnpub = await c.insertLive(
    seller: s2,
    active: true,
    status: 'live',
    muxPlayback: 'rtdePbLive1538bbbb',
    muxLiveId: 'rtdeMuxLiveUnpub1538',
    title: '$prefix air-unpub',
  );

  final prodPub = await c.createProduct(
    seller: s1,
    title: '$prefix pub-mkt',
    qty: 4,
    price: 18.0,
    listed: true,
    sold: false,
  );
  final prodUnpub = await c.createProduct(
    seller: s2,
    title: '$prefix unpub-mkt',
    qty: 5,
    price: 22.0,
    listed: true,
    sold: false,
  );
  final prodSold = await c.createProduct(
    seller: s1,
    title: '$prefix sold-pub',
    qty: 1,
    price: 15.0,
    listed: true,
    sold: true,
  );
  final prodQty0 = await c.createProduct(
    seller: s1,
    title: '$prefix qty0-pub',
    qty: 0,
    price: 16.0,
    listed: true,
    sold: false,
  );
  final prodUnlisted = await c.createProduct(
    seller: s1,
    title: '$prefix unlist-pub',
    qty: 3,
    price: 19.0,
    listed: false,
    sold: false,
  );

  final raffle = await c.rest('POST', 'live_raffles', service: true, body: {
    'live_id': liveUnpub,
    'seller_id': s2,
    'title': '$prefix raffle unpub',
    'status': 'active',
    'winner_count': 1,
  });
  final raffleId = raffle.firstId;
  if (raffleId != null) c.createdRaffleIds.add(raffleId);
  c.note('fix.raffle', 'raffle S2 unpublished', raffle, lens: 'DE7');

  await dumpJson('${outDir()}/pass1_ids.json', {
    's1': s1,
    's2': s2,
    'b1': b1,
    'b2': b2,
    'airPub': livePub,
    'airUnpub': liveUnpub,
    'prodPub': prodPub,
    'prodUnpub': prodUnpub,
    'prodSold': prodSold,
    'prodQty0': prodQty0,
    'prodUnlisted': prodUnlisted,
    'raffle': raffleId,
    's1_hub': s1p?['hub_published'],
    's2_hub': s2p?['hub_published'],
    'b2_type': b2p?['user_type'],
  });

  Future<void> delFollow(String follower, String following) async {
    await c.rest(
      'DELETE',
      'follows?follower_id=eq.$follower&following_id=eq.$following',
      jwt: c.buyerJwt,
      prefer: 'return=minimal',
    );
    await c.rest(
      'DELETE',
      'follows?follower_id=eq.$follower&following_id=eq.$following',
      service: true,
      prefer: 'return=minimal',
    );
  }

  Future<HttpHit> follow(String follower, String following, {String? jwt}) {
    return c.rest('POST', 'follows', jwt: jwt ?? c.buyerJwt, body: {
      'follower_id': follower,
      'following_id': following,
    });
  }

  Future<HttpHit> fav(String userId, String productId, {String? jwt}) {
    return c.rest('POST', 'favorites', jwt: jwt ?? c.buyerJwt, body: {
      'user_id': userId,
      'product_id': productId,
    });
  }

  // ----- A1 follow published (obrigatório feliz) -----
  await delFollow(b1, s1);
  final a1 = await follow(b1, s1);
  if (a1.firstId != null) c.createdFollowIds.add(a1.firstId!);
  final a1ok = insertOk(a1);
  c.probe(
    id: 'A1',
    poco: 'DE-A',
    payload: 'B1 POST follows following_id=S1 published (CVDA DEFINER)',
    http: a1,
    bd: {'s1_hub': s1p?['hub_published'], 'follow_id': a1.firstId},
    result: a1ok ? 'HOLD' : 'FAIL',
    lens: 'DE1',
  );
  if (!a1ok) {
    c.hold(
      id: 'DE-A1-FOLLOW-PUB-REGRESSION',
      lens: 'DE1',
      severity: 'P2',
      title: 'follow published recusado após CVDA',
      actor: 'B1',
      pre: 'S1 hub_published=true; batata_profile_is_hub_published DEFINER',
      repro: 'POST /rest/v1/follows follower=B1 following=S1',
      expected: '201',
      obtained: a1.brief,
    );
  }

  // ----- A2 follow unpublished (controlo clássico, 1 linha, residual) -----
  await delFollow(b1, s2);
  final a2 = await follow(b1, s2);
  if (a2.firstId != null) c.createdFollowIds.add(a2.firstId!);
  var ticketsA2 = 0;
  if (raffleId != null) ticketsA2 = await c.raffleTickets(raffleId, b1);
  final a2ok = insertOk(a2) && a2.status != 409;
  c.probe(
    id: 'A2',
    poco: 'DE-A',
    payload: 'B1 POST follows following_id=S2 unpublished (controlo clássico)',
    http: a2,
    bd: {'tickets': ticketsA2, 'raffle': raffleId, 's2_hub': s2p?['hub_published']},
    result: a2ok ? 'FAIL' : 'HOLD',
    lens: 'DE1',
    residual: true,
    countFinding: a2ok,
  );
  if (a2ok) {
    c.hold(
      id: 'DE-A2-FOLLOW-UNPUB',
      lens: 'DE1',
      severity: ticketsA2 > 0 ? 'P1' : 'P1',
      title: 'follows aceita loja unpublished',
      actor: 'B1',
      pre: 'S2 hub_published=false; raffle active',
      repro: 'POST /rest/v1/follows following_id=S2',
      expected: '403/42501 deny',
      obtained: {'http': a2.brief, 'tickets': ticketsA2},
    );
  }

  // ----- A3 favorite published SKU Hub -----
  await c.rest(
    'DELETE',
    'favorites?user_id=eq.$b1&product_id=eq.$prodPub',
    jwt: c.buyerJwt,
    prefer: 'return=minimal',
  );
  await c.rest(
    'DELETE',
    'favorites?user_id=eq.$b1&product_id=eq.$prodPub',
    service: true,
    prefer: 'return=minimal',
  );
  final a3 = await fav(b1, prodPub!);
  final a3ok = insertOk(a3);
  c.probe(
    id: 'A3',
    poco: 'DE-A',
    payload: 'B1 POST favorites product S1 published listável',
    http: a3,
    bd: {'product': prodPub},
    result: a3ok ? 'HOLD' : 'FAIL',
    lens: 'DE2',
  );
  if (!a3ok) {
    c.hold(
      id: 'DE-A3-FAV-PUB-REGRESSION',
      lens: 'DE2',
      severity: 'P2',
      title: 'favorite published recusado após CVDA',
      actor: 'B1',
      pre: 'S1 published; SKU list_on_marketplace qty>0',
      repro: 'POST /rest/v1/favorites',
      expected: '201',
      obtained: a3.brief,
    );
  }

  // ----- A4 favorite unpublished -----
  await c.rest(
    'DELETE',
    'favorites?user_id=eq.$b1&product_id=eq.$prodUnpub',
    jwt: c.buyerJwt,
    prefer: 'return=minimal',
  );
  final a4 = await fav(b1, prodUnpub!);
  final a4ok = insertOk(a4) && a4.status != 409;
  c.probe(
    id: 'A4',
    poco: 'DE-A',
    payload: 'B1 POST favorites SKU loja unpublished',
    http: a4,
    bd: {'product': prodUnpub},
    result: a4ok ? 'FAIL' : 'HOLD',
    lens: 'DE2',
    residual: true,
    countFinding: a4ok,
  );
  if (a4ok) {
    c.hold(
      id: 'DE-A4-FAV-UNPUB',
      lens: 'DE2',
      severity: 'P2',
      title: 'favorites aceita SKU de loja unpublished',
      actor: 'B1',
      pre: 'S2 hub_published=false; SKU listável qty=5',
      repro: 'POST /rest/v1/favorites product_id=unpub',
      expected: '403/42501 deny',
      obtained: a4.brief,
    );
  }

  // ----- A5 UUID inválido / self / spoof -----
  const ghost = '00000000-0000-4000-a000-0000000000d1';
  final a5ghost = await follow(b1, ghost);
  final a5self = await follow(b1, b1);
  final a5spoof = await follow(b2, s1, jwt: c.buyerJwt);
  final a5b2 = await follow(b1, b2);
  final a5hit = insertOk(a5ghost) || insertOk(a5self) || insertOk(a5spoof);
  c.probe(
    id: 'A5',
    poco: 'DE-A',
    payload: 'follow ghost UUID / self / follower_id=B2 spoof / following=B2',
    http: {
      'ghost': a5ghost.brief,
      'self': a5self.brief,
      'spoofFollower': a5spoof.brief,
      'followingB2': a5b2.brief,
    },
    result: a5hit ? 'FAIL' : 'HOLD',
    lens: 'DE1',
    countFinding: a5hit,
  );
  if (insertOk(a5ghost)) {
    c.hold(
      id: 'DE-A5-FOLLOW-GHOST',
      lens: 'DE1',
      severity: 'P2',
      title: 'follows aceita UUID inexistente',
      actor: 'B1',
      pre: 'following_id ghost',
      repro: 'POST follows following_id=0000…d1',
      expected: 'deny',
      obtained: a5ghost.brief,
    );
  }
  if (insertOk(a5self)) {
    c.hold(
      id: 'DE-A5-FOLLOW-SELF',
      lens: 'DE1',
      severity: 'P3',
      title: 'follows aceita seguir a si próprio',
      actor: 'B1',
      pre: 'following_id = follower_id',
      repro: 'POST follows self',
      expected: 'deny distinct from auth.uid()',
      obtained: a5self.brief,
    );
  }
  if (insertOk(a5spoof)) {
    c.hold(
      id: 'DE-A5-FOLLOW-SPOOF',
      lens: 'DE1',
      severity: 'P1',
      title: 'B1 insere follow com follower_id=B2',
      actor: 'B1',
      pre: 'JWT B1; body.follower_id=B2',
      repro: 'POST follows follower_id=B2 following=S1',
      expected: 'deny follower_id = auth.uid()',
      obtained: a5spoof.brief,
    );
  }

  // ----- A6 race follow ∥ unpublish -----
  await delFollow(b1, s2);
  await c.setHub(s2, true);
  final race = await Future.wait<HttpHit>([
    c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
      'hub_published': false,
    }, prefer: 'return=representation'),
    follow(b1, s2),
  ]);
  final raceUnpub = race[0];
  final raceFollow = race[1];
  if (raceFollow.firstId != null) c.createdFollowIds.add(raceFollow.firstId!);
  final s2afterRace = await c.profile(s2);
  var ticketsRace = 0;
  if (raffleId != null) ticketsRace = await c.raffleTickets(raffleId, b1);
  if (s2afterRace?['hub_published'] == true) await c.setHub(s2, false);
  final raceWon = insertOk(raceFollow) && raceFollow.status != 409;
  c.probe(
    id: 'A6',
    poco: 'DE-A',
    payload: 'race PATCH hub_published=false ∥ POST follow S2',
    http: {'unpub': raceUnpub.brief, 'follow': raceFollow.brief},
    bd: {
      'hub_after': s2afterRace?['hub_published'],
      'tickets': ticketsRace,
      'follow_id': raceFollow.firstId,
    },
    result: raceWon ? 'FAIL' : 'HOLD',
    lens: 'DE6',
    countFinding: raceWon,
  );
  if (raceWon) {
    c.hold(
      id: 'DE-A6-FOLLOW-RACE-UNPUB',
      lens: 'DE6',
      severity: ticketsRace > 0 ? 'P1' : 'P2',
      title: 'follow ganha corrida ao unpublish',
      actor: 'B1',
      pre: 'S2 published no arranque; PATCH false em paralelo com POST follow',
      repro: 'Future.wait unpublish ∥ follow',
      expected: 'deny se hub já false; ou TOCTOU documentado',
      obtained: {
        'follow': raceFollow.brief,
        'hub_after': s2afterRace?['hub_published'],
        'tickets': ticketsRace,
      },
    );
  }

  // ----- A7 DEFINER RPC oracle (ângulo novo, não residual clássico) -----
  final rpcPub = await c.rpc(
    'batata_profile_is_hub_published',
    {'p_id': s1},
    jwt: c.buyerJwt,
  );
  final rpcUnpub = await c.rpc(
    'batata_profile_is_hub_published',
    {'p_id': s2},
    jwt: c.buyerJwt,
  );
  final rpcGhost = await c.rpc(
    'batata_profile_is_hub_published',
    {'p_id': ghost},
    jwt: c.buyerJwt,
  );
  final rpcAnon = await c.rpc(
    'batata_profile_is_hub_published',
    {'p_id': s1},
  );
  final rpcFavPub = await c.rpc(
    'batata_product_is_favorite_allowed',
    {'p_product_id': prodPub},
    jwt: c.buyerJwt,
  );
  final rpcFavUnpub = await c.rpc(
    'batata_product_is_favorite_allowed',
    {'p_product_id': prodUnpub},
    jwt: c.buyerJwt,
  );
  // Oracle extra: se anon executa, ou se unpublished devolve true, ou leak não-boolean.
  final anonExec = rpcAnon.ok && rpcAnon.status != 401 && rpcAnon.status != 403;
  final unpubTrue = rpcUnpub.json == true;
  final extraLeak = (rpcUnpub.map != null && rpcUnpub.map!.keys.length > 1);
  final a7fail = anonExec || unpubTrue || extraLeak;
  c.probe(
    id: 'A7',
    poco: 'DE-A',
    payload:
        'RPC DEFINER batata_profile_is_hub_published + favorite_allowed (B1/anon)',
    http: {
      'pub': rpcPub.brief,
      'unpub': rpcUnpub.brief,
      'ghost': rpcGhost.brief,
      'anon': rpcAnon.brief,
      'favPub': rpcFavPub.brief,
      'favUnpub': rpcFavUnpub.brief,
    },
    bd: {
      'unpubTrue': unpubTrue,
      'anonExec': anonExec,
    },
    result: a7fail ? 'FAIL' : 'HOLD',
    lens: 'DE7',
    countFinding: a7fail,
  );
  if (anonExec) {
    c.hold(
      id: 'DE-A7-DEFINER-ANON',
      lens: 'DE7',
      severity: 'P2',
      title: 'anon executa batata_profile_is_hub_published',
      actor: 'anon',
      pre: 'GRANT só authenticated/service_role',
      repro: 'POST /rest/v1/rpc/batata_profile_is_hub_published',
      expected: '401/403',
      obtained: rpcAnon.brief,
    );
  }
  if (unpubTrue) {
    c.hold(
      id: 'DE-A7-DEFINER-UNPUB-TRUE',
      lens: 'DE7',
      severity: 'P1',
      title: 'DEFINER diz published=true para loja unpublished',
      actor: 'B1',
      pre: 'S2 hub_published=false',
      repro: 'RPC batata_profile_is_hub_published(S2)',
      expected: 'false',
      obtained: rpcUnpub.brief,
    );
  }

  // ----- A8 favorite sold / qty0 / unlisted (isolável se A3 HOLD) -----
  final a8sold = await fav(b1, prodSold!);
  final a8qty = await fav(b1, prodQty0!);
  final a8unlist = await fav(b1, prodUnlisted!);
  final a8hit = (insertOk(a8sold) && a8sold.status != 409) ||
      (insertOk(a8qty) && a8qty.status != 409) ||
      (insertOk(a8unlist) && a8unlist.status != 409);
  c.probe(
    id: 'A8',
    poco: 'DE-A',
    payload: 'favorite SKU sold / qty=0 / unlisted loja published',
    http: {
      'sold': a8sold.brief,
      'qty0': a8qty.brief,
      'unlisted': a8unlist.brief,
    },
    bd: {'sold': prodSold, 'qty0': prodQty0, 'unlisted': prodUnlisted},
    result: a8hit ? 'FAIL' : 'HOLD',
    lens: 'DE2',
    countFinding: a8hit,
  );
  if (insertOk(a8sold) && a8sold.status != 409) {
    c.hold(
      id: 'DE-A8-FAV-SOLD',
      lens: 'DE2',
      severity: 'P3',
      title: 'favorites aceita produto já vendido',
      actor: 'B1',
      pre: 'S1 published; is_sold=true',
      repro: 'POST favorites product sold',
      expected: 'deny',
      obtained: a8sold.brief,
    );
  }
  if (insertOk(a8qty) && a8qty.status != 409) {
    c.hold(
      id: 'DE-A8-FAV-QTY0',
      lens: 'DE2',
      severity: 'P3',
      title: 'favorites aceita produto qty=0',
      actor: 'B1',
      pre: 'S1 published; quantity=0',
      repro: 'POST favorites qty0',
      expected: 'deny',
      obtained: a8qty.brief,
    );
  }
  if (insertOk(a8unlist) && a8unlist.status != 409) {
    c.hold(
      id: 'DE-A8-FAV-UNLISTED',
      lens: 'DE2',
      severity: 'P2',
      title: 'favorites aceita SKU não listado no marketplace',
      actor: 'B1',
      pre: 'S1 published; list_on_marketplace=false',
      repro: 'POST favorites unlisted',
      expected: 'deny',
      obtained: a8unlist.brief,
    );
  }

  // ----- A9 PATCH retarget unpublished + UPSERT (isolável se A1 201) -----
  String? followPubId = a1.firstId;
  if (followPubId == null && a1ok) {
    final listed = await c.rest(
      'GET',
      'follows?follower_id=eq.$b1&following_id=eq.$s1&select=id',
      jwt: c.buyerJwt,
    );
    followPubId = listed.firstId;
  }
  HttpHit? patchRetarget;
  if (followPubId != null) {
    patchRetarget = await c.rest(
      'PATCH',
      'follows?id=eq.$followPubId',
      jwt: c.buyerJwt,
      body: {'following_id': s2},
    );
  }
  final upsert = await c.req(
    'POST',
    '/rest/v1/follows?on_conflict=follower_id,following_id',
    jwt: c.buyerJwt,
    body: {
      'follower_id': b1,
      'following_id': s2,
    },
    extra: {
      'Prefer': 'return=representation,resolution=merge-duplicates',
    },
  );
  final a9fail = (patchRetarget?.ok ?? false) ||
      (insertOk(upsert) && upsert.status != 409 && upsert.firstId != null);
  c.probe(
    id: 'A9',
    poco: 'DE-A',
    payload: 'PATCH follow published→unpublished + POST upsert unpublished',
    http: {
      'patch': patchRetarget?.brief ?? 'n/a (sem row A1)',
      'upsert': upsert.brief,
      'followPubId': followPubId,
    },
    result: a9fail ? 'FAIL' : 'HOLD',
    lens: 'DE7',
    countFinding: a9fail,
  );
  if (patchRetarget != null && patchRetarget.ok) {
    c.hold(
      id: 'DE-A9-PATCH-FOLLOW-UNPUB',
      lens: 'DE7',
      severity: 'P1',
      title: 'PATCH follows retarget para loja unpublished',
      actor: 'B1',
      pre: 'follow S1 published existente',
      repro: 'PATCH follows following_id=S2 unpublished',
      expected: 'sem UPDATE policy / deny',
      obtained: patchRetarget.brief,
    );
  }
  if (insertOk(upsert) && upsert.status != 409 && upsert.firstId != null) {
    c.hold(
      id: 'DE-A9-UPSERT-FOLLOW-UNPUB',
      lens: 'DE7',
      severity: 'P1',
      title: 'UPSERT follows cria aresta unpublished',
      actor: 'B1',
      pre: 'on_conflict + resolution=merge-duplicates',
      repro: 'POST follows?on_conflict=follower_id,following_id',
      expected: 'deny mesma política insert',
      obtained: upsert.brief,
    );
  }

  // ----- A10 favorite user_id spoof (ângulo novo) -----
  await c.rest(
    'DELETE',
    'favorites?user_id=eq.$b2&product_id=eq.$prodPub',
    service: true,
    prefer: 'return=minimal',
  );
  final a10spoof = await fav(b2, prodPub, jwt: c.buyerJwt);
  final a10hit = insertOk(a10spoof) && a10spoof.status != 409;
  c.probe(
    id: 'A10',
    poco: 'DE-A',
    payload: 'B1 JWT POST favorites user_id=B2 SKU published',
    http: a10spoof,
    bd: {'product': prodPub, 'spoof_user': b2},
    result: a10hit ? 'FAIL' : 'HOLD',
    lens: 'DE2',
    countFinding: a10hit,
  );
  if (a10hit) {
    c.hold(
      id: 'DE-A10-FAV-SPOOF-USER',
      lens: 'DE2',
      severity: 'P1',
      title: 'B1 insere favorite em nome de B2',
      actor: 'B1',
      pre: 'JWT B1; body.user_id=B2; SKU published',
      repro: 'POST /rest/v1/favorites user_id=B2',
      expected: 'deny user_id = auth.uid()',
      obtained: a10spoof.brief,
    );
  }

  await c.setHub(s2, false);
  await c.restoreSeller1Published();
  await dumpJson('${outDir()}/pass1.json', {
    'probes': c.probes,
    'findings': c.findings,
    'notes': c.notes,
    'skipped': c.skipped,
    'lenses': c.lensesHit.toList()..sort(),
    'lives': c.createdLiveIds,
  });
  stdout.writeln(
    'PASS1 done probes=${c.probes.length} findings=${c.findings.length}',
  );
}
