/// RED TEAM CEGO CY pass1 — CY-A follow/favorite published (≥6).
import 'dart:io';
import '_rtcy.dart';

Future<void> main() async {
  final c = Rtcy.fromEnv(loadEnv());
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
  }, prefer: 'return=minimal');
  await c.rest('PATCH', 'profiles?id=eq.$b2', service: true, body: {
    'user_type': 'comprador',
    'hub_published': false,
  }, prefer: 'return=minimal');

  final s1p = await c.profile(s1);
  final s2p = await c.profile(s2);
  final b2p = await c.profile(b2);
  c.note('fix.s1', 'S1 published', s1p, lens: 'CY1');
  c.note('fix.s2', 'S2 unpublished vendedor', s2p, lens: 'CY1');
  c.note('fix.b2', 'B2 comprador', b2p, lens: 'CY1');

  final livePub = await c.insertLive(
    seller: s1,
    active: true,
    status: 'live',
    muxPlayback: 'rtcyPbLive1450aaaa',
    title: '$prefix air-pub',
  );
  final liveUnpub = await c.insertLive(
    seller: s2,
    active: true,
    status: 'live',
    muxPlayback: 'rtcyPbLive1450bbbb',
    muxLiveId: 'rtcyMuxLiveUnpub1450',
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
  c.note('fix.raffle', 'raffle S2 unpublished', raffle, lens: 'CY7');

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

  // ----- A1 follow published -----
  await delFollow(b1, s1);
  final a1 = await follow(b1, s1);
  if (a1.firstId != null) c.createdFollowIds.add(a1.firstId!);
  final a1ok = a1.ok && a1.firstId != null;
  c.probe(
    id: 'A1',
    poco: 'CY-A',
    payload: 'B1 POST follows following_id=S1 published',
    http: a1,
    bd: {'s1_hub': true, 'follow_id': a1.firstId},
    result: a1ok ? 'HOLD' : 'FAIL',
    lens: 'CY1',
  );
  if (!a1ok) {
    c.hold(
      id: 'CY-A1-FOLLOW-PUB-REGRESSION',
      lens: 'CY1',
      severity: 'P2',
      title: 'follow published recusado (happy path partido)',
      actor: 'B1',
      pre: 'S1 hub_published=true',
      repro: 'POST /rest/v1/follows follower=B1 following=S1',
      expected: '201',
      obtained: a1.brief,
    );
  }

  // ----- A2 follow unpublished (controlo clássico, 1 linha) -----
  await delFollow(b1, s2);
  final a2 = await follow(b1, s2);
  if (a2.firstId != null) c.createdFollowIds.add(a2.firstId!);
  var ticketsA2 = 0;
  if (raffleId != null) ticketsA2 = await c.raffleTickets(raffleId, b1);
  final a2ok = a2.ok && a2.firstId != null;
  c.probe(
    id: 'A2',
    poco: 'CY-A',
    payload: 'B1 POST follows following_id=S2 unpublished (controlo clássico)',
    http: a2,
    bd: {'tickets': ticketsA2, 'raffle': raffleId},
    result: a2ok ? 'FAIL' : 'HOLD',
    lens: 'CY1',
    residual: true,
    countFinding: a2ok,
  );
  if (a2ok) {
    c.hold(
      id: 'CY-A2-FOLLOW-UNPUB',
      lens: 'CY1',
      severity: ticketsA2 > 0 ? 'P1' : 'P1',
      title: 'follows aceita loja unpublished (CJCO regressão)',
      actor: 'B1',
      pre: 'S2 hub_published=false; raffle active',
      repro: 'POST /rest/v1/follows following_id=S2',
      expected: '403/42501 deny',
      obtained: {'http': a2.brief, 'tickets': ticketsA2},
    );
  }

  // ----- A3 favorite published -----
  await c.rest(
    'DELETE',
    'favorites?user_id=eq.$b1&product_id=eq.$prodPub',
    jwt: c.buyerJwt,
    prefer: 'return=minimal',
  );
  final a3 = await fav(b1, prodPub!);
  final a3ok = a3.ok && a3.firstId != null;
  c.probe(
    id: 'A3',
    poco: 'CY-A',
    payload: 'B1 POST favorites product S1 published listável',
    http: a3,
    bd: {'product': prodPub},
    result: a3ok ? 'HOLD' : 'FAIL',
    lens: 'CY2',
  );
  if (!a3ok) {
    c.hold(
      id: 'CY-A3-FAV-PUB-REGRESSION',
      lens: 'CY2',
      severity: 'P2',
      title: 'favorite published recusado (happy path partido)',
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
  final a4ok = a4.ok && a4.firstId != null;
  c.probe(
    id: 'A4',
    poco: 'CY-A',
    payload: 'B1 POST favorites SKU loja unpublished',
    http: a4,
    bd: {'product': prodUnpub},
    result: a4ok ? 'FAIL' : 'HOLD',
    lens: 'CY2',
    residual: true,
    countFinding: a4ok,
  );
  if (a4ok) {
    c.hold(
      id: 'CY-A4-FAV-UNPUB',
      lens: 'CY2',
      severity: 'P2',
      title: 'favorites aceita SKU de loja unpublished',
      actor: 'B1',
      pre: 'S2 hub_published=false; SKU listável qty=5',
      repro: 'POST /rest/v1/favorites product_id=unpub',
      expected: '403/42501 deny',
      obtained: a4.brief,
    );
  }

  // ----- A5 UUID inválido / outro seller / spoof follower -----
  const ghost = '00000000-0000-4000-a000-0000000000c1';
  final a5ghost = await follow(b1, ghost);
  final a5self = await follow(b1, b1);
  final a5spoof = await follow(b2, s1, jwt: c.buyerJwt);
  final a5b2 = await follow(b1, b2);
  final a5hit = a5ghost.ok || a5self.ok || a5spoof.ok;
  c.probe(
    id: 'A5',
    poco: 'CY-A',
    payload: 'follow ghost UUID / self / follower_id=B2 spoof / following=B2',
    http: {
      'ghost': a5ghost.brief,
      'self': a5self.brief,
      'spoofFollower': a5spoof.brief,
      'followingB2': a5b2.brief,
    },
    result: a5hit ? 'FAIL' : 'HOLD',
    lens: 'CY1',
    countFinding: a5hit,
  );
  if (a5ghost.ok) {
    c.hold(
      id: 'CY-A5-FOLLOW-GHOST',
      lens: 'CY1',
      severity: 'P2',
      title: 'follows aceita UUID inexistente',
      actor: 'B1',
      pre: 'following_id ghost',
      repro: 'POST follows following_id=0000…c1',
      expected: 'deny (exists profiles hub_published)',
      obtained: a5ghost.brief,
    );
  }
  if (a5self.ok) {
    c.hold(
      id: 'CY-A5-FOLLOW-SELF',
      lens: 'CY1',
      severity: 'P3',
      title: 'follows aceita seguir a si próprio',
      actor: 'B1',
      pre: 'following_id = follower_id',
      repro: 'POST follows self',
      expected: 'deny distinct from auth.uid()',
      obtained: a5self.brief,
    );
  }
  if (a5spoof.ok) {
    c.hold(
      id: 'CY-A5-FOLLOW-SPOOF',
      lens: 'CY1',
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
  final hubAfter = s2afterRace?['hub_published'] == true;
  if (hubAfter) await c.setHub(s2, false);
  final raceWon = raceFollow.ok && raceFollow.firstId != null;
  c.probe(
    id: 'A6',
    poco: 'CY-A',
    payload: 'race PATCH hub_published=false ∥ POST follow S2',
    http: {'unpub': raceUnpub.brief, 'follow': raceFollow.brief},
    bd: {
      'hub_after': s2afterRace?['hub_published'],
      'tickets': ticketsRace,
      'follow_id': raceFollow.firstId,
    },
    result: raceWon ? 'FAIL' : 'HOLD',
    lens: 'CY6',
    countFinding: raceWon,
  );
  if (raceWon) {
    c.hold(
      id: 'CY-A6-FOLLOW-RACE-UNPUB',
      lens: 'CY6',
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

  // ----- A7 favorite sold published -----
  final a7 = await fav(b1, prodSold!);
  c.probe(
    id: 'A7',
    poco: 'CY-A',
    payload: 'B1 favorite SKU is_sold=true loja published',
    http: a7,
    bd: {'product': prodSold},
    result: a7.ok ? 'FAIL' : 'HOLD',
    lens: 'CY2',
    countFinding: a7.ok,
  );
  if (a7.ok) {
    c.hold(
      id: 'CY-A7-FAV-SOLD',
      lens: 'CY2',
      severity: 'P3',
      title: 'favorites aceita produto já vendido',
      actor: 'B1',
      pre: 'S1 published; is_sold=true',
      repro: 'POST favorites product sold',
      expected: 'deny (CJCO is_sold=false)',
      obtained: a7.brief,
    );
  }

  // ----- A8 favorite qty=0 published -----
  final a8 = await fav(b1, prodQty0!);
  c.probe(
    id: 'A8',
    poco: 'CY-A',
    payload: 'B1 favorite SKU quantity=0 loja published',
    http: a8,
    bd: {'product': prodQty0},
    result: a8.ok ? 'FAIL' : 'HOLD',
    lens: 'CY2',
    countFinding: a8.ok,
  );
  if (a8.ok) {
    c.hold(
      id: 'CY-A8-FAV-QTY0',
      lens: 'CY2',
      severity: 'P3',
      title: 'favorites aceita produto qty=0',
      actor: 'B1',
      pre: 'S1 published; quantity=0',
      repro: 'POST favorites qty0',
      expected: 'deny (CJCO qty>0)',
      obtained: a8.brief,
    );
  }

  // ----- A9 favorite unlisted published -----
  final a9 = await fav(b1, prodUnlisted!);
  c.probe(
    id: 'A9',
    poco: 'CY-A',
    payload: 'B1 favorite SKU list_on_marketplace=false loja published',
    http: a9,
    bd: {'product': prodUnlisted},
    result: a9.ok ? 'FAIL' : 'HOLD',
    lens: 'CY2',
    countFinding: a9.ok,
  );
  if (a9.ok) {
    c.hold(
      id: 'CY-A9-FAV-UNLISTED',
      lens: 'CY2',
      severity: 'P2',
      title: 'favorites aceita SKU não listado no marketplace',
      actor: 'B1',
      pre: 'S1 published; list_on_marketplace=false',
      repro: 'POST favorites unlisted',
      expected: 'deny',
      obtained: a9.brief,
    );
  }

  // ----- A10 PATCH follow retarget unpublished + UPSERT -----
  String? followPubId = a1.firstId;
  if (followPubId == null) {
    final again = await follow(b1, s1);
    followPubId = again.firstId;
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
  final a10fail = (patchRetarget?.ok ?? false) ||
      (upsert.ok && upsert.firstId != null);
  c.probe(
    id: 'A10',
    poco: 'CY-A',
    payload: 'PATCH follow published→unpublished + POST upsert unpublished',
    http: {
      'patch': patchRetarget?.brief,
      'upsert': upsert.brief,
    },
    result: a10fail ? 'FAIL' : 'HOLD',
    lens: 'CY7',
    countFinding: a10fail,
  );
  if (patchRetarget != null && patchRetarget.ok) {
    c.hold(
      id: 'CY-A10-PATCH-FOLLOW-UNPUB',
      lens: 'CY7',
      severity: 'P1',
      title: 'PATCH follows retarget para loja unpublished',
      actor: 'B1',
      pre: 'follow S1 published existente',
      repro: 'PATCH follows following_id=S2 unpublished',
      expected: 'sem UPDATE policy / deny',
      obtained: patchRetarget.brief,
    );
  }
  if (upsert.ok && upsert.firstId != null) {
    c.hold(
      id: 'CY-A10-UPSERT-FOLLOW-UNPUB',
      lens: 'CY7',
      severity: 'P1',
      title: 'UPSERT follows cria aresta unpublished',
      actor: 'B1',
      pre: 'on_conflict + resolution=merge-duplicates',
      repro: 'POST follows?on_conflict=follower_id,following_id',
      expected: 'deny mesma política insert',
      obtained: upsert.brief,
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
  stdout.writeln('PASS1 done probes=${c.probes.length} findings=${c.findings.length}');
}
