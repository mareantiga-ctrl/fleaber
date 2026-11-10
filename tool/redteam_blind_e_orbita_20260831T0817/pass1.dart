/// Blind E Órbita pass1 — mapa + lentes E1–E10. Staging only. No fixes.
import 'dart:convert';
import 'dart:io';

import '_rte.dart';

void main() async {
  final env = loadEnv();
  final c = Rte.fromEnv(env);
  await c.loginActors(env);
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final findings = <Map<String, dynamic>>[];
  final map = <String, dynamic>{
    'auditor': 'REDTEAM_BLIND_E_ORBITA_v1',
    'stamp': stamp,
    'prefix': prefix,
    'project': projectMust,
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
  };

  void add(Map<String, dynamic> f) {
    findings.add(f);
    stdout.writeln(
      '${f['proven'] == true ? "HIT" : "try"} ${f['severity']} ${f['id']} ${f['title']}',
    );
  }

  // ---------------------------------------------------------------------------
  // MAPA
  // ---------------------------------------------------------------------------
  const hubViews = [
    'hub_profiles_public',
    'hub_lives_public',
    'hub_products_public',
    'hub_live_items_public',
    'hub_live_messages_public',
    'hub_reviews_public',
    'hub_lives_discovery_public',
    'hub_profiles_discovery_public',
    'hub_live_items_discovery_public',
  ];
  final hubMap = <String, dynamic>{};
  for (final v in hubViews) {
    final anon = await c.rest('GET', '$v?select=*&limit=3');
    final cols = <String>{};
    for (final row in anon.list) {
      if (row is Map) cols.addAll(row.keys.map((k) => k.toString()));
    }
    hubMap[v] = {
      'anon_http': anon.status,
      'anon_n': anon.list.length,
      'cols': cols.toList()..sort(),
      'snip': clip(anon.body, 180),
    };
  }
  map['hub_views'] = hubMap;

  final openapi = await c.req(
    'GET',
    '/rest/v1/',
    extra: {'Accept': 'application/openapi+json'},
  );
  final rpcNames = <String>[];
  if (openapi.json is Map) {
    final paths = (openapi.json as Map)['paths'];
    if (paths is Map) {
      for (final k in paths.keys) {
        final s = k.toString();
        if (s.startsWith('/rpc/')) rpcNames.add(s.substring(5));
      }
    }
  }
  rpcNames.sort();
  final cronish = rpcNames
      .where((n) =>
          n.contains('expire') ||
          n.contains('cron') ||
          n.contains('release') ||
          n.contains('auto_feedback') ||
          n.contains('cleanup') ||
          n.contains('notify') ||
          n.contains('invite') ||
          n.contains('bundle') ||
          n.contains('follow') ||
          n.contains('push') ||
          n.contains('device') ||
          n.contains('connect') ||
          n.contains('handle') ||
          n.contains('hub_'))
      .toList();
  map['rpc_cronish'] = cronish;
  map['rpc_count'] = rpcNames.length;

  final pidListed = await c.insertProduct(title: '$prefix listed', price: 11.0);
  final pidUnlisted = await c.insertProduct(
    title: '$prefix unlisted',
    listed: false,
    price: 22.0,
  );
  final pidSold = await c.insertProduct(
    title: '$prefix sold',
    sold: true,
    price: 33.0,
  );
  final pidListed2 = await c.insertProduct(
    title: '$prefix listed-b',
    price: 14.0,
  );
  map['fixtures'] = {
    'listed': pidListed,
    'unlisted': pidUnlisted,
    'sold': pidSold,
    'listed2': pidListed2,
    'seller2': c.seller2Id,
    'buyer2': c.buyer2Id,
  };

  // ---------------------------------------------------------------------------
  // E1 — vitrine pública
  // ---------------------------------------------------------------------------
  final rhMiss = await c.rpc('batata_resolve_handle', {'p_handle': 'nao-existe-$prefix'});
  add(finding(
    id: 'E1-RESOLVE-MISS',
    lens: 'E1',
    severity: 'info',
    title: 'resolve_handle miss',
    pre: 'anon',
    repro: 'rpc batata_resolve_handle missing',
    proven: false,
    evidence: {'http': rhMiss.status, 'body': rhMiss.snippet},
  ));

  final rhUnpub = await c.rpc('batata_resolve_handle', {'p_handle': 'rte0817s2'});
  final unpubFound = rhUnpub.map?['found'] == true;
  final unpubPub = rhUnpub.map?['hub_published'];
  final unpubPid = rhUnpub.map?['profile_id']?.toString();
  add(finding(
    id: 'E1-RESOLVE-UNPUB',
    lens: 'E1',
    severity: unpubFound && unpubPub != true ? 'P3' : 'info',
    title: 'anon resolve_handle devolve profile_id unpublished',
    pre: 'seller2 hub_published=false',
    repro: 'rpc batata_resolve_handle rte0817s2 as anon',
    proven: unpubFound && unpubPub != true && (unpubPid?.isNotEmpty ?? false),
    evidence: {'http': rhUnpub.status, 'body': rhUnpub.snippet},
    note: 'UUID de vitrine não publicada — enumeração por handle claimado.',
  ));

  // PATCH is_live as unpublished seller2 → discovery leak?
  final livePatch = await c.rest(
    'PATCH',
    'profiles?id=eq.${c.seller2Id}',
    jwt: c.seller2Jwt,
    body: {'is_live': true},
  );
  final discAfter = await c.rest(
    'GET',
    'hub_profiles_discovery_public?id=eq.${c.seller2Id}&select=id,handle,full_name,location,hub_published,is_live',
  );
  final discHit = discAfter.list.any((e) =>
      e is Map && e['id']?.toString() == c.seller2Id);
  add(finding(
    id: 'E1-ISLIVE-DISCOVERY',
    lens: 'E1',
    severity: discHit ? 'P2' : 'info',
    title: 'unpublished PATCH is_live=true entra na discovery Hub anon',
    pre: 'seller2 hub_published=false',
    repro: 'PATCH profiles is_live=true; GET hub_profiles_discovery_public as anon',
    proven: discHit,
    evidence: {
      'patch_http': livePatch.status,
      'disc_http': discAfter.status,
      'disc': discAfter.snippet,
    },
  ));

  // Reset is_live after probe (fixture hygiene, not a product fix)
  await c.rest(
    'PATCH',
    'profiles?id=eq.${c.seller2Id}',
    service: true,
    body: {'is_live': false},
    prefer: 'return=minimal',
  );

  final piiCols = [
    'phone',
    'iban',
    'mb_way',
    'email',
    'legal_full_name',
    'shipping_line1',
    'buyer_id',
    'user_id',
    'mux_stream_key',
    'stream_key',
  ];
  for (final v in hubViews) {
    final cols = (hubMap[v]?['cols'] as List?)?.map((e) => e.toString()).toSet() ?? {};
    final leak = piiCols.where(cols.contains).toList();
    if (leak.isNotEmpty) {
      add(finding(
        id: 'E1-HUB-PII-$v',
        lens: 'E1',
        severity: 'P1',
        title: 'view Hub expõe colunas PII a anon',
        pre: 'anon GET $v',
        repro: 'GET /rest/v1/$v?select=*',
        proven: true,
        evidence: {'cols': leak},
      ));
    }
  }

  // unpublished lives in discovery
  final endedLive = await c.rest('POST', 'lives', service: true, body: {
    'title': '$prefix ended-unpub',
    'status': 'ended',
    'seller_id': c.seller2Id,
    'vendedor_id': c.seller2Id,
    'is_active': false,
    'mux_playback_id': 'rte0817fakeplay',
  });
  final endedId = endedLive.firstId;
  final discLives = await c.rest(
    'GET',
    'hub_lives_discovery_public?seller_id=eq.${c.seller2Id}&select=id,seller_id,seller_handle,seller_name,mux_playback_id,status',
  );
  final unpubLiveLeak = discLives.list.any((e) =>
      e is Map && e['id']?.toString() == endedId);
  add(finding(
    id: 'E1-DISCOVERY-ENDED-UNPUB',
    lens: 'E1',
    severity: unpubLiveLeak ? 'P2' : 'info',
    title: 'hub_lives_discovery_public lista live ended de seller unpublished',
    pre: 'seller2 hub_published=false + live ended',
    repro: 'GET hub_lives_discovery_public?seller_id=eq.seller2 as anon',
    proven: unpubLiveLeak,
    evidence: {'insert': endedLive.status, 'disc': discLives.snippet, 'endedId': endedId},
  ));

  // anon reserve / follow
  final anonFollow = await c.rest('POST', 'follows', body: {
    'follower_id': c.buyerId,
    'following_id': c.sellerId,
  });
  add(finding(
    id: 'E1-ANON-FOLLOW',
    lens: 'E1',
    severity: anonFollow.ok ? 'P1' : 'info',
    title: 'anon consegue seguir sem login',
    pre: 'anon POST follows',
    repro: 'POST follows as anon',
    proven: anonFollow.ok,
    evidence: {'http': anonFollow.status, 'body': anonFollow.snippet},
  ));

  final anonRes = await c.rest('POST', 'live_reservation_requests', body: {
    'buyer_id': c.buyerId,
    'live_item_id': '00000000-0000-0000-0000-000000000001',
    'requested_qty': 1,
    'status': 'pending',
  });
  add(finding(
    id: 'E1-ANON-RESERVE',
    lens: 'E1',
    severity: anonRes.ok ? 'P1' : 'info',
    title: 'anon reserva sem login',
    pre: 'anon POST live_reservation_requests',
    repro: 'POST live_reservation_requests as anon',
    proven: anonRes.ok,
    evidence: {'http': anonRes.status, 'body': anonRes.snippet},
  ));

  // two actors same hub surface
  final hubB1 = await c.rest(
    'GET',
    'hub_profiles_public?select=id,handle,full_name&limit=2',
    jwt: c.buyerJwt,
  );
  final hubB2 = await c.rest(
    'GET',
    'hub_profiles_public?select=id,handle,full_name&limit=2',
    jwt: c.buyer2Jwt,
  );
  map['e1_two_buyers_hub'] = {
    'b1': hubB1.status,
    'b2': hubB2.status,
    'b1n': hubB1.list.length,
    'b2n': hubB2.list.length,
  };

  final fomoGhost = await c.rpc(
    'batata_hub_live_fomo_snapshot',
    {'p_live_id': endedId ?? '00000000-0000-0000-0000-000000000001'},
  );
  add(finding(
    id: 'E1-FOMO-UNPUB-LIVE',
    lens: 'E1',
    severity: (fomoGhost.map?['ok'] == true) ? 'P2' : 'info',
    title: 'FOMO snapshot de live unpublished/ended',
    pre: 'anon rpc fomo',
    repro: 'rpc batata_hub_live_fomo_snapshot',
    proven: fomoGhost.map?['ok'] == true,
    evidence: {'http': fomoGhost.status, 'body': fomoGhost.snippet},
  ));

  // ---------------------------------------------------------------------------
  // E2 — cron
  // ---------------------------------------------------------------------------
  final cronTries = <String, dynamic>{};
  for (final fn in [
    'batata_generate_auto_feedback',
    'batata_expire_product_offers',
    'batata_release_seller_wallet_for_order',
  ]) {
    final asAnon = await c.rpc(fn, {});
    final asBuyer = await c.rpc(fn, {}, jwt: c.buyerJwt);
    cronTries[fn] = {
      'anon': {'http': asAnon.status, 'snip': asAnon.snippet},
      'buyer': {'http': asBuyer.status, 'snip': asBuyer.snippet},
    };
    final hostile = (asAnon.ok || asBuyer.ok);
    add(finding(
      id: 'E2-CRON-$fn',
      lens: 'E2',
      severity: hostile ? 'P1' : 'info',
      title: 'JWT/anon executa job $fn',
      pre: 'rpc $fn',
      repro: 'POST /rest/v1/rpc/$fn as buyer and anon',
      proven: hostile,
      evidence: cronTries[fn] as Map<String, Object?>,
    ));
  }
  final afFuture = await c.rpc(
    'batata_generate_auto_feedback',
    {'p_now': '2099-01-01T00:00:00Z'},
    jwt: c.buyerJwt,
  );
  add(finding(
    id: 'E2-AUTO-FEEDBACK-PNOW',
    lens: 'E2',
    severity: afFuture.ok ? 'P1' : 'info',
    title: 'buyer dispara auto-feedback com p_now futuro',
    pre: 'rpc batata_generate_auto_feedback p_now=2099',
    repro: 'POST rpc batata_generate_auto_feedback',
    proven: afFuture.ok,
    evidence: {'http': afFuture.status, 'body': afFuture.snippet},
  ));
  final egress = await c.edge('livekit-egress-cleanup', body: {});
  add(finding(
    id: 'E2-EGRESS-NOSECRET',
    lens: 'E2',
    severity: egress.ok ? 'P1' : 'info',
    title: 'egress cleanup sem secret',
    pre: 'POST livekit-egress-cleanup anon',
    repro: 'POST /functions/v1/livekit-egress-cleanup',
    proven: egress.ok,
    evidence: {'http': egress.status, 'body': egress.snippet},
  ));
  map['cron_tries'] = cronTries;
  map['cron_exercised'] = true;

  final relEarly = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    jwt: c.buyerJwt,
  );
  map['e2_release_ghost'] = {'http': relEarly.status, 'snip': relEarly.snippet};

  // ---------------------------------------------------------------------------
  // E3 — push / notifications
  // ---------------------------------------------------------------------------
  final notifAlien = await c.rest(
    'GET',
    'user_notifications?select=id,user_id,title,body&limit=5',
    jwt: c.buyer2Jwt,
  );
  final alienNotif = notifAlien.list.any((e) =>
      e is Map && e['user_id']?.toString() != c.buyer2Id);
  add(finding(
    id: 'E3-NOTIF-READ-ALIEN',
    lens: 'E3',
    severity: alienNotif ? 'P1' : 'info',
    title: 'buyer2 lê user_notifications de outro UID',
    pre: 'GET user_notifications',
    repro: 'GET user_notifications as buyer2',
    proven: alienNotif,
    evidence: {'http': notifAlien.status, 'n': notifAlien.list.length, 'snip': notifAlien.snippet},
  ));

  final notifIns = await c.rest('POST', 'user_notifications', jwt: c.buyer2Jwt, body: {
    'user_id': c.sellerId,
    'kind': 'rte_hostile',
    'title': '$prefix push-alheio',
    'body': 'hostile',
  });
  add(finding(
    id: 'E3-NOTIF-INSERT-ALIEN',
    lens: 'E3',
    severity: notifIns.ok ? 'P1' : 'info',
    title: 'buyer2 INSERT notificação no UID do seller',
    pre: 'POST user_notifications user_id=seller',
    repro: 'POST user_notifications as buyer2',
    proven: notifIns.ok,
    evidence: {'http': notifIns.status, 'body': notifIns.snippet},
  ));

  for (final t in [
    'seller_device_tokens',
    'user_push_tokens',
    'device_tokens',
    'fcm_tokens',
    'push_tokens',
  ]) {
    final r = await c.rest('GET', '$t?select=*&limit=3', jwt: c.buyer2Jwt);
    final hasRows = r.ok && r.list.isNotEmpty;
    add(finding(
      id: 'E3-TOKEN-TABLE-$t',
      lens: 'E3',
      severity: hasRows ? 'P1' : 'info',
      title: 'buyer2 lê tabela de tokens $t',
      pre: 'GET $t',
      repro: 'GET /rest/v1/$t as buyer2',
      proven: hasRows,
      evidence: {'http': r.status, 'n': r.list.length, 'snip': r.snippet},
    ));
  }

  // ---------------------------------------------------------------------------
  // E4 — saco / bundle
  // ---------------------------------------------------------------------------
  if (pidListed != null && pidListed2 != null) {
    final hostileBundle = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_ids': [pidListed, pidListed2],
      'status': 'accepted',
      'discount_pct': 50,
      'total_eur': 0.50,
      'subtotal_eur': 0.50,
      'discount_eur': 24.5,
    });
    final tot = hostileBundle.map?['total_eur'];
    final st = hostileBundle.map?['status']?.toString();
    final pct = hostileBundle.map?['discount_pct'];
    final cheap = hostileBundle.ok &&
        (tot is num && tot <= 1.0 || st == 'accepted' || (pct is num && pct > 0));
    add(finding(
      id: 'E4-BUNDLE-HOSTILE-PRICE',
      lens: 'E4',
      severity: cheap ? 'P1' : 'info',
      title: 'buyer INSERT bundle com total/desconto/status hostis',
      pre: 'POST product_bundles discount 50 total 0.50 accepted',
      repro: 'POST product_bundles as buyer',
      proven: cheap,
      evidence: {'http': hostileBundle.status, 'body': hostileBundle.snippet},
    ));
    map['e4_bundle_listed'] = hostileBundle.snippet;
  }

  if (pidUnlisted != null && pidListed != null) {
    final unlistedBundle = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_ids': [pidListed, pidUnlisted],
      'status': 'pending',
      'discount_pct': 0,
      'total_eur': 1,
    });
    final includesUnlisted = unlistedBundle.ok &&
        jsonEncode(unlistedBundle.map?['product_ids']).contains(pidUnlisted);
    add(finding(
      id: 'E4-BUNDLE-UNLISTED',
      lens: 'E4',
      severity: includesUnlisted ? 'P2' : 'info',
      title: 'bundle aceita produto unlistado no saco',
      pre: 'POST product_bundles product_ids=[listed,unlisted]',
      repro: 'POST product_bundles as buyer',
      proven: includesUnlisted,
      evidence: {'http': unlistedBundle.status, 'body': unlistedBundle.snippet},
    ));
    map['e4_bundle_unlisted_id'] = unlistedBundle.firstId;
  }

  if (pidSold != null && pidListed != null) {
    final soldBundle = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_ids': [pidListed, pidSold],
      'status': 'pending',
    });
    add(finding(
      id: 'E4-BUNDLE-SOLD',
      lens: 'E4',
      severity: soldBundle.ok ? 'P2' : 'info',
      title: 'bundle inclui produto is_sold',
      pre: 'POST product_bundles + sold product',
      repro: 'POST product_bundles as buyer',
      proven: soldBundle.ok,
      evidence: {'http': soldBundle.status, 'body': soldBundle.snippet},
    ));
  }

  final catalogOracle = await c.rpc(
    'batata_product_bundles_catalog_subtotal',
    {
      'p_product_ids': [
        if (pidUnlisted != null) pidUnlisted,
        if (pidSold != null) pidSold,
      ],
    },
    jwt: c.buyerJwt,
  );
  add(finding(
    id: 'E4-CATALOG-ORACLE',
    lens: 'E4',
    severity: catalogOracle.ok ? 'P3' : 'info',
    title: 'RPC subtotal devolve preço de unlisted/sold',
    pre: 'rpc batata_product_bundles_catalog_subtotal',
    repro: 'rpc catalog_subtotal [unlisted,sold]',
    proven: catalogOracle.ok && catalogOracle.body.contains('22'),
    evidence: {'http': catalogOracle.status, 'body': catalogOracle.snippet},
  ));

  // ---------------------------------------------------------------------------
  // E5 — Connect / banco
  // ---------------------------------------------------------------------------
  final origins = [
    'https://evil.example',
    'https://attacker.fleaber.pt',
    'https://fleaber.pt.evil.com',
    'https://fleaber.pt%2f%2fevil.com',
    'http://fleaber.pt',
    'https://fleaber.pt',
    'https://localhost',
  ];
  final connectOrigins = <String, dynamic>{};
  for (final o in origins) {
    final r = await c.edge(
      'create-connect-account',
      method: 'GET',
      qs: '?web_return_origin=${Uri.encodeQueryComponent(o)}',
    );
    connectOrigins[o] = {
      'http': r.status,
      'loc': r.location,
      'snip': clip(r.body, 80),
    };
    final loc = r.location ?? '';
    final hostileLoc = loc.isNotEmpty &&
        !loc.contains('fleaber.pt') &&
        !loc.contains('fleaber.app') &&
        !loc.contains('fleaber://') &&
        !loc.contains('localhost') &&
        !loc.contains('127.0.0.1');
    final sub = loc.contains('attacker.fleaber.pt');
    if (hostileLoc || sub) {
      add(finding(
        id: 'E5-CONNECT-REDIRECT',
        lens: 'E5',
        severity: 'P2',
        title: 'create-connect-account 303 para origem hostil',
        pre: 'GET web_return_origin=$o',
        repro: 'GET create-connect-account?web_return_origin=$o',
        proven: true,
        evidence: {'origin': o, 'http': r.status, 'loc': loc},
      ));
    }
  }
  map['e5_connect_origins'] = connectOrigins;

  final connectSpoof = await c.edge('create-connect-account', jwt: c.buyerJwt, body: {
    'user_id': c.sellerId,
  });
  add(finding(
    id: 'E5-CONNECT-USER-SPOOF',
    lens: 'E5',
    severity: connectSpoof.ok ? 'P1' : 'info',
    title: 'buyer cria/liga Connect com user_id do seller',
    pre: 'POST create-connect-account user_id=seller',
    repro: 'POST create-connect-account',
    proven: connectSpoof.ok &&
        !connectSpoof.body.toLowerCase().contains('cannot create another'),
    evidence: {'http': connectSpoof.status, 'body': connectSpoof.snippet},
  ));

  final iban = await c.rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': c.sellerId},
    jwt: c.buyer2Jwt,
  );
  final ibanHit = iban.ok &&
      iban.list.isNotEmpty &&
      iban.list.any((e) =>
          e is Map &&
          ((e['iban'] != null && e['iban'].toString().isNotEmpty) ||
              (e['mb_way'] != null && e['mb_way'].toString().isNotEmpty)));
  add(finding(
    id: 'E5-IBAN-ORACLE',
    lens: 'E5',
    severity: ibanHit ? 'P1' : 'info',
    title: 'buyer2 lê IBAN/MB WAY do seller sem encomenda off-platform',
    pre: 'rpc batata_seller_direct_payment_details',
    repro: 'rpc as buyer2',
    proven: ibanHit,
    evidence: {'http': iban.status, 'body': iban.snippet},
  ));

  final walAlien = await c.rest(
    'GET',
    'wallets?id=eq.${c.sellerId}&select=id,stripe_account_id,balance',
    jwt: c.buyer2Jwt,
  );
  add(finding(
    id: 'E5-WALLET-ALIEN',
    lens: 'E5',
    severity: walAlien.ok && walAlien.list.isNotEmpty ? 'P1' : 'info',
    title: 'buyer2 lê stripe_account_id/balance do seller',
    pre: 'GET wallets?id=seller',
    repro: 'GET wallets as buyer2',
    proven: walAlien.ok && walAlien.list.isNotEmpty,
    evidence: {'http': walAlien.status, 'body': walAlien.snippet},
  ));

  // ---------------------------------------------------------------------------
  // E6 — mortos que vendem
  // ---------------------------------------------------------------------------
  Future<HttpHit> tryHold(String pid, {String? liveId, String? liveItemId, String? raffle}) {
    return c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'quantity': 1,
      'status': 'pendente',
      'price_total': 11.0,
      if (liveId != null) 'live_id': liveId,
      if (liveItemId != null) 'live_item_id': liveItemId,
      if (raffle != null) 'live_raffle_id': raffle,
    });
  }

  if (pidUnlisted != null) {
    final u = await tryHold(pidUnlisted);
    add(finding(
      id: 'E6-UNLIST-HOLD',
      lens: 'E6',
      severity: u.ok ? 'P1' : 'info',
      title: 'hold JWT em produto unlistado',
      pre: 'POST orders unlist',
      repro: 'POST orders product_id=unlisted status=pendente',
      proven: u.ok,
      evidence: {'http': u.status, 'body': u.snippet},
    ));
    // stamp live ended
    final uLive = await tryHold(pidUnlisted, liveId: endedId);
    add(finding(
      id: 'E6-UNLIST-ENDED-LIVE-STAMP',
      lens: 'E6',
      severity: uLive.ok ? 'P1' : 'info',
      title: 'unlist + live_id ended ainda faz hold',
      pre: 'POST orders unlist + live ended',
      repro: 'POST orders live_id=ended',
      proven: uLive.ok,
      evidence: {'http': uLive.status, 'body': uLive.snippet},
    ));
  }
  if (pidSold != null) {
    final s = await tryHold(pidSold);
    add(finding(
      id: 'E6-SOLD-HOLD',
      lens: 'E6',
      severity: s.ok ? 'P1' : 'info',
      title: 'hold JWT em produto is_sold',
      pre: 'POST orders sold',
      repro: 'POST orders product_id=sold',
      proven: s.ok,
      evidence: {'http': s.status, 'body': s.snippet},
    ));
  }

  // Hub still showing sold? create sold listed then check view
  if (pidListed != null) {
    await c.rest(
      'PATCH',
      'products?id=eq.$pidListed',
      service: true,
      body: {'is_sold': true},
      prefer: 'return=minimal',
    );
    final hubSold = await c.rest('GET', 'hub_products_public?id=eq.$pidListed');
    add(finding(
      id: 'E6-HUB-SHOWS-SOLD',
      lens: 'E6',
      severity: hubSold.list.isNotEmpty ? 'P2' : 'info',
      title: 'hub_products_public ainda mostra is_sold',
      pre: 'PATCH is_sold=true; GET hub_products_public',
      repro: 'GET hub_products_public?id=eq.listed',
      proven: hubSold.list.isNotEmpty,
      evidence: {'http': hubSold.status, 'n': hubSold.list.length, 'snip': hubSold.snippet},
    ));
    await c.rest(
      'PATCH',
      'products?id=eq.$pidListed',
      service: true,
      body: {'is_sold': false},
      prefer: 'return=minimal',
    );
  }

  // ---------------------------------------------------------------------------
  // E7 — URL regresso
  // ---------------------------------------------------------------------------
  final payOrigins = [
    'https://evil.example',
    'https://attacker.fleaber.pt',
    'https://fleaber.pt',
  ];
  for (final o in payOrigins) {
    final r = await c.edge('create-payment-intent', jwt: c.buyerJwt, body: {
      'order_id': '00000000-0000-0000-0000-000000000001',
      'web_return_origin': o,
    });
    final accepted = r.ok &&
        (r.body.contains(o) ||
            (o.contains('attacker') && r.body.contains('attacker')));
    add(finding(
      id: 'E7-PAY-ORIGIN-${o.hashCode.abs()}',
      lens: 'E7',
      severity: accepted && o.contains('attacker') ? 'P2' : 'info',
      title: 'create-payment-intent web_return_origin=$o',
      pre: 'POST create-payment-intent',
      repro: 'POST create-payment-intent web_return_origin=$o',
      proven: accepted,
      evidence: {'http': r.status, 'body': clip(r.body, 200)},
    ));
  }
  final alienSession = await c.edge(
    'create-payment-intent',
    method: 'GET',
    qs: '?checkout_return=success&session_id=cs_test_alien_rte0817',
  );
  add(finding(
    id: 'E7-SESSION-ALIEN',
    lens: 'E7',
    severity: alienSession.ok &&
            (alienSession.body.contains('cs_test') ||
                (alienSession.location ?? '').contains('stripe-success'))
        ? 'P2'
        : 'info',
    title: 'checkout_return com session_id inventado',
    pre: 'GET create-payment-intent checkout_return=success',
    repro: 'GET ?checkout_return=success&session_id=cs_test_alien',
    proven: false,
    evidence: {
      'http': alienSession.status,
      'loc': alienSession.location,
      'snip': clip(alienSession.body, 160),
    },
    note: 'Prova mínima = session real alheia. Aqui só oráculo/eco.',
  ));

  // ---------------------------------------------------------------------------
  // E8 — grafo social
  // ---------------------------------------------------------------------------
  final folOther = await c.rest('POST', 'follows', jwt: c.buyer2Jwt, body: {
    'follower_id': c.buyerId,
    'following_id': c.sellerId,
  });
  add(finding(
    id: 'E8-FOLLOW-AS-OTHER',
    lens: 'E8',
    severity: folOther.ok ? 'P1' : 'info',
    title: 'buyer2 segue em nome de buyer1',
    pre: 'POST follows follower_id=buyer1',
    repro: 'POST follows as buyer2',
    proven: folOther.ok,
    evidence: {'http': folOther.status, 'body': folOther.snippet},
  ));

  final folSelf = await c.rest('POST', 'follows', jwt: c.buyer2Jwt, body: {
    'follower_id': c.buyer2Id,
    'following_id': c.sellerId,
  });
  map['e8_follow_ok'] = {'http': folSelf.status, 'id': folSelf.firstId};

  if (pidListed != null) {
    var burstOk = 0;
    String? lastErr;
    for (var i = 0; i < 12; i++) {
      final f = await c.rest('POST', 'favorites', jwt: c.buyer2Jwt, body: {
        'user_id': c.buyer2Id,
        'product_id': pidListed,
      });
      if (f.ok) burstOk++;
      lastErr = f.snippet;
    }
    add(finding(
      id: 'E8-FAV-BURST',
      lens: 'E8',
      severity: burstOk >= 3 ? 'P3' : 'info',
      title: 'favorites permite duplicados (burst ${burstOk}x)',
      pre: 'POST favorites 12x mesmo par',
      repro: 'POST favorites ×12',
      proven: burstOk >= 3,
      evidence: {'ok': burstOk, 'last': lastErr},
    ));
    final favCross = await c.rest('POST', 'favorites', jwt: c.buyer2Jwt, body: {
      'user_id': c.sellerId,
      'product_id': pidListed,
    });
    add(finding(
      id: 'E8-FAV-AS-OTHER',
      lens: 'E8',
      severity: favCross.ok ? 'P2' : 'info',
      title: 'favorite em nome de outro UID',
      pre: 'POST favorites user_id=seller',
      repro: 'POST favorites as buyer2',
      proven: favCross.ok,
      evidence: {'http': favCross.status, 'body': favCross.snippet},
    ));
  }

  for (final t in ['blocks', 'user_blocks', 'blocked_users', 'profile_blocks']) {
    final r = await c.rest('GET', '$t?select=*&limit=1', jwt: c.buyerJwt);
    map['e8_block_$t'] = {'http': r.status, 'snip': clip(r.body, 80)};
  }

  // ---------------------------------------------------------------------------
  // E9 — invite / email
  // ---------------------------------------------------------------------------
  final findEmail = await c.rpc(
    'batata_find_user_id_by_email',
    {'p_email': envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL')},
    jwt: c.buyerJwt,
  );
  add(finding(
    id: 'E9-EMAIL-UUID-ORACLE',
    lens: 'E9',
    severity: findEmail.ok &&
            findEmail.body.contains(c.sellerId ?? 'nope-never')
        ? 'P1'
        : 'info',
    title: 'JWT recebe UUID por email',
    pre: 'rpc batata_find_user_id_by_email',
    repro: 'rpc as buyer',
    proven: findEmail.ok && (findEmail.body.contains('-')),
    evidence: {'http': findEmail.status, 'body': findEmail.snippet},
    note: 'UUID no body (não null) = oracle.',
  ));

  final invMissing = await c.rpc(
    'batata_staff_invite_helper_by_email',
    {
      'p_email': 'naoexiste-$prefix@example.invalid',
      'p_display_name': 'X',
      'p_permissions': <String, dynamic>{},
    },
    jwt: c.sellerJwt,
  );
  final invExists = await c.rpc(
    'batata_staff_invite_helper_by_email',
    {
      'p_email': envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      'p_display_name': 'Y',
      'p_permissions': <String, dynamic>{},
    },
    jwt: c.sellerJwt,
  );
  final oracle = invMissing.status != invExists.status ||
      (!invMissing.body.contains('invite_unavailable') &&
          invExists.body.contains('invite_unavailable')) ||
      (invMissing.body.contains('invite_unavailable') &&
          !invExists.body.contains('invite_unavailable') &&
          invExists.status != invMissing.status);
  add(finding(
    id: 'E9-INVITE-EMAIL-ORACLE',
    lens: 'E9',
    severity: oracle ? 'P3' : 'info',
    title: 'invite distingue email inexistente vs registado',
    pre: 'rpc batata_staff_invite_helper_by_email missing vs buyer email',
    repro: 'two invites as seller',
    proven: oracle,
    evidence: {
      'missing': {'http': invMissing.status, 'snip': invMissing.snippet},
      'exists': {'http': invExists.status, 'snip': invExists.snippet},
    },
    note: 'Rate conhecido; aqui só diferença de erro (enumeração).',
  ));

  // ---------------------------------------------------------------------------
  // E10 — cadeia órbita→caixa (só se E4/E6 hold)
  // ---------------------------------------------------------------------------
  final e4unlistedId = map['e4_bundle_unlisted_id']?.toString();
  if (e4unlistedId != null && e4unlistedId.isNotEmpty && pidUnlisted != null) {
    final accept = await c.rest(
      'PATCH',
      'product_bundles?id=eq.$e4unlistedId',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    final holdFromBundle = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pidUnlisted,
      'bundle_id': e4unlistedId,
      'quantity': 1,
      'status': 'pendente',
      'price_total': 22.0,
    });
    add(finding(
      id: 'E10-BUNDLE-UNLIST-HOLD',
      lens: 'E10',
      severity: holdFromBundle.ok ? 'P1' : 'info',
      title: 'bundle com unlist → order hold permanente',
      pre: 'seller accept bundle; buyer POST order unlist',
      repro: 'POST orders bundle_id + unlisted product',
      proven: holdFromBundle.ok,
      evidence: {
        'accept': accept.snippet,
        'hold_http': holdFromBundle.status,
        'hold': holdFromBundle.snippet,
      },
    ));
  }

  // Race: unlist ∥ hold
  if (pidListed2 != null) {
    final race = await Future.wait([
      c.rest(
        'PATCH',
        'products?id=eq.$pidListed2',
        jwt: c.sellerJwt,
        body: {'list_on_marketplace': false},
      ),
      tryHold(pidListed2),
    ]);
    add(finding(
      id: 'E10-RACE-UNLIST-HOLD',
      lens: 'E10',
      severity: race[1].ok ? 'P1' : 'info',
      title: 'race unlist∥hold no mesmo produto',
      pre: 'PATCH unlist + POST order',
      repro: 'parallel PATCH products list_on_marketplace=false ∥ POST orders',
      proven: race[1].ok,
      evidence: {
        'unlist': race[0].snippet,
        'hold_http': race[1].status,
        'hold': race[1].snippet,
      },
    ));
  }

  map['anon_hub_exercised'] = true;
  map['findings'] = findings;
  map['proven'] = findings.where((f) => f['proven'] == true).toList();

  final outDir = 'tool/redteam_blind_e_orbita_$stamp/out';
  await dumpJson('$outDir/pass1.json', map);
  stdout.writeln('proven ${map['proven'].length} / ${findings.length}');
  stdout.writeln('wrote $outDir/pass1.json');
}
