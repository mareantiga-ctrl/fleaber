import 'dart:io';

import '_rtm.dart';

/// Pass 1 — Hub/Edge/deeplink discovery. No dual Session, no mint, no invite,
/// no pairing ended, no paused-items as primary, no plain→JSON.
void main() async {
  final c = Rtm.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final out = <String, Object?>{
    'auditor': 'REDTEAM_BLIND_M_HUB_EDGE_v1',
    'stamp': stamp,
    'staging': projectMust,
    'seller': c.sellerId,
    'buyer': c.buyerId,
    'seller2': c.seller2Id,
    'buyer2': c.buyer2Id,
  };

  // ---- fixtures: unpublished seller2 + published seller lives ----
  final unpubLive = await c.insertLive(
    seller: c.seller2Id,
    status: 'scheduled',
    active: false,
    muxPlayback: 'rtm_unpub_playback_$stamp',
    muxLiveId: 'rtm_unpub_muxlive_$stamp',
    streamKey: 'rtm_unpub_sk_$stamp',
  );
  final draftLive = await c.insertLive(
    seller: c.seller2Id,
    status: 'draft',
    active: false,
    muxPlayback: 'rtm_draft_playback_$stamp',
  );
  final ghostLiveFlag = await c.rest(
    'PATCH',
    'profiles?id=eq.${c.seller2Id}',
    service: true,
    body: {'is_live': true, 'hub_published': false},
    prefer: 'return=representation',
  );
  c.note('p1.fix.is_live', 'seller2 is_live=true hub_published=false',
      ghostLiveFlag.brief,
      lens: 'M1');

  final unlisted = await c.insertProduct(
    title: '$prefix unlisted',
    seller: c.seller2Id,
    listed: false,
    qty: 7,
    images: [
      'https://$projectMust.supabase.co/storage/v1/object/public/chat_media/rtm-secret-$stamp.jpg'
    ],
  );
  final pubLive = await c.insertLive(
    seller: c.sellerId,
    status: 'ended',
    active: false,
    muxPlayback: 'rtm_pub_pb_$stamp',
    muxVod: 'rtm_pub_vod_$stamp',
  );
  if (pubLive != null) {
    await c.insertLiveItem(
      liveId: pubLive,
      title: '$prefix item ended',
      status: 'sold',
      active: false,
      qty: 4,
    );
  }
  final activeUnpubLive = await c.insertLive(
    seller: c.seller2Id,
    status: 'live',
    active: true,
    muxPlayback: 'rtm_active_unpub_$stamp',
  );

  out['fixtures'] = {
    'unpubLive': unpubLive,
    'draftLive': draftLive,
    'unlisted': unlisted,
    'pubLive': pubLive,
    'activeUnpubLive': activeUnpubLive,
  };

  // =====================================================================
  // M1 — Hub views / FOMO / handle (anon)
  // =====================================================================
  final views = <String, Object?>{};
  for (final v in [
    'hub_profiles_public',
    'hub_lives_public',
    'hub_products_public',
    'hub_live_items_public',
    'hub_live_messages_public',
    'hub_reviews_public',
    'hub_lives_discovery_public',
    'hub_profiles_discovery_public',
    'hub_live_items_discovery_public',
    'profiles_directory_public',
  ]) {
    final hit = await c.rest(
      'GET',
      '$v?select=*&limit=5',
    );
    views[v] = {'http': hit.status, 'n': hit.list.length, 'snip': hit.snippet};
    c.note('p1.m1.view.$v', 'anon $v', hit.brief, lens: 'M1');
  }
  out['anon_views'] = views;

  // unpublished handle resolve
  final rhUnpub = await c.rpc('batata_resolve_handle', {'p_handle': 'rtm1802s2'});
  c.note('p1.m1.resolve.unpub', 'anon resolve unpublished handle', rhUnpub.brief,
      lens: 'M1');
  out['resolve_unpub'] = rhUnpub.map ?? rhUnpub.snippet;
  final unpubFound = rhUnpub.map?['found'] == true;
  final unpubPid = rhUnpub.map?['profile_id']?.toString();
  if (unpubFound && unpubPid == c.seller2Id) {
    c.hold(
      id: 'RTM-M1-001',
      lens: 'M1',
      severity: 'P2',
      title: 'anon batata_resolve_handle devolve profile_id de vitrine NÃO publicada',
      actor: 'anon',
      pre: 'seller2 hub_published=false handle=rtm1802s2',
      repro: 'POST rpc/batata_resolve_handle p_handle=rtm1802s2',
      expected: 'found=false / 404 — handle não publicado não enumera UUID',
      obtained: rhUnpub.snippet,
      evidence: {'map': rhUnpub.map},
    );
  }

  // slug from full_name "RtmSlug1802" → rtmslug1802
  final rhSlug = await c.rpc('batata_resolve_handle', {'p_handle': 'rtmslug1802'});
  c.note('p1.m1.resolve.slug', 'anon resolve discovery slug', rhSlug.brief,
      lens: 'M1');
  out['resolve_slug'] = rhSlug.map ?? rhSlug.snippet;
  if (rhSlug.map?['found'] == true &&
      rhSlug.map?['profile_id']?.toString() == c.seller2Id) {
    c.hold(
      id: 'RTM-M1-002',
      lens: 'M1',
      severity: 'P2',
      title: 'anon resolve_handle enumera UUID via slug do nome (sem handle publicado)',
      actor: 'anon',
      pre: 'full_name=RtmSlug1802 hub_published=false',
      repro: 'POST rpc/batata_resolve_handle p_handle=rtmslug1802',
      expected: '404 — slug de nome não publicado não resolve',
      obtained: rhSlug.snippet,
      evidence: {'map': rhSlug.map},
    );
  }

  final rhMiss = await c.rpc(
      'batata_resolve_handle', {'p_handle': 'nao-existe-$stamp'});
  c.note('p1.m1.resolve.miss', 'missing handle', rhMiss.brief, lens: 'M1');

  // discovery: unpublished + is_live without real? we also have activeUnpubLive
  final discProf = await c.rest(
    'GET',
    'hub_profiles_discovery_public?id=eq.${c.seller2Id}&select=id,handle,hub_published,is_live,location,phone_verified,external_payments_enabled',
  );
  c.note('p1.m1.disc.prof', 'discovery profile seller2', discProf.brief,
      lens: 'M1');
  out['disc_prof_s2'] = discProf.snippet;

  final discLive = await c.rest(
    'GET',
    'hub_lives_discovery_public?id=eq.$activeUnpubLive&select=id,seller_id,seller_handle,mux_playback_id,status',
  );
  c.note('p1.m1.disc.live', 'discovery unpublished active live', discLive.brief,
      lens: 'M1');
  if (discLive.ok && discLive.list.isNotEmpty) {
    c.hold(
      id: 'RTM-M1-003',
      lens: 'M1',
      severity: 'P2',
      title: 'Hub discovery lista directo de vendedor com vitrine NÃO publicada',
      actor: 'anon',
      pre: 'seller2 hub_published=false + live is_active',
      repro: 'GET hub_lives_discovery_public?id=eq.<live>',
      expected: 'vitrine não publicada não aparece no feed público (só player com link)',
      obtained: discLive.snippet,
      evidence: {'n': discLive.list.length},
    );
  }

  final hubLiveUnpub = await c.rest(
    'GET',
    'hub_lives_public?id=eq.$unpubLive&select=id,mux_playback_id,seller_id',
  );
  c.note('p1.m1.hub.unpub_sched', 'hub_lives_public scheduled unpublished',
      hubLiveUnpub.brief,
      lens: 'M1');

  // base table lives as anon — scheduled unpublished + stream keys
  final livesAnon = await c.rest(
    'GET',
    'lives?id=eq.$unpubLive&select=id,status,seller_id,mux_playback_id,mux_live_id,mux_stream_key,stream_key,mux_asset_id,livekit_room_name,title',
  );
  c.note('p1.m1.lives.anon.unpub', 'anon GET lives unpublished scheduled',
      livesAnon.brief,
      lens: 'M1');
  out['lives_anon_unpub'] = livesAnon.snippet;
  final livesBody = livesAnon.body.toLowerCase();
  if (livesAnon.ok && livesAnon.list.isNotEmpty) {
    final leakedKey = livesBody.contains('rtm_unpub_sk_') ||
        livesBody.contains('mux_stream_key') &&
            (livesAnon.map?['mux_stream_key'] != null ||
                livesAnon.map?['stream_key'] != null);
    if (leakedKey) {
      c.hold(
        id: 'RTM-M1-004',
        lens: 'M1',
        severity: 'P0',
        title: 'anon lê stream_key / mux_stream_key na tabela lives',
        actor: 'anon',
        pre: 'live scheduled unpublished com stream_key fixture',
        repro: 'GET rest/v1/lives?id=eq.<id>&select=mux_stream_key,stream_key',
        expected: 'coluna recusada / omitida',
        obtained: livesAnon.snippet,
      );
    }
    final seesScheduled = livesAnon.map?['id']?.toString() == unpubLive;
    if (seesScheduled) {
      c.hold(
        id: 'RTM-M1-005',
        lens: 'M1',
        severity: 'P1',
        title: 'anon GET lives vê directo scheduled de vitrine NÃO publicada (mux_playback_id)',
        actor: 'anon',
        pre: 'hub_published=false status=scheduled',
        repro: 'GET rest/v1/lives?id=eq.<unpubLive>',
        expected: 'só views Hub / discovery com regras; tabela base não enumera scheduled alheio',
        obtained: livesAnon.snippet,
        evidence: {'playback': livesAnon.map?['mux_playback_id']},
      );
    }
  }

  final draftAnon = await c.rest(
    'GET',
    'lives?id=eq.$draftLive&select=id,status,title,mux_playback_id',
  );
  c.note('p1.m1.lives.draft', 'anon draft live', draftAnon.brief, lens: 'M1');
  if (draftAnon.ok && draftAnon.list.isNotEmpty) {
    c.hold(
      id: 'RTM-M1-006',
      lens: 'M1',
      severity: 'P1',
      title: 'anon GET lives vê rascunho (status=draft) de outro vendedor',
      actor: 'anon',
      pre: 'status=draft is_active=false seller2',
      repro: 'GET rest/v1/lives?id=eq.<draft>',
      expected: 'draft invisível a anon',
      obtained: draftAnon.snippet,
    );
  }

  // FOMO unpublished vs published (not paused-items class)
  final fomoUnpub = await c.rpc(
      'batata_hub_live_fomo_snapshot', {'p_live_id': unpubLive});
  c.note('p1.m1.fomo.unpub', 'FOMO unpublished scheduled', fomoUnpub.brief,
      lens: 'M1');
  final fomoActiveUnpub = await c.rpc(
      'batata_hub_live_fomo_snapshot', {'p_live_id': activeUnpubLive});
  c.note('p1.m1.fomo.active_unpub', 'FOMO unpublished active',
      fomoActiveUnpub.brief,
      lens: 'M1');
  if (fomoActiveUnpub.ok && fomoActiveUnpub.map?['ok'] == true) {
    c.hold(
      id: 'RTM-M1-007',
      lens: 'M1',
      severity: 'P2',
      title: 'FOMO snapshot anon em directo activo de vitrine não publicada',
      actor: 'anon',
      pre: 'hub_lives_public exige publicado; discovery não',
      repro: 'rpc batata_hub_live_fomo_snapshot(activeUnpubLive)',
      expected: 'ok=false live_not_public',
      obtained: fomoActiveUnpub.snippet,
    );
  }
  final fomoPub = await c.rpc(
      'batata_hub_live_fomo_snapshot', {'p_live_id': pubLive});
  c.note('p1.m1.fomo.pub', 'FOMO published ended', fomoPub.brief, lens: 'M1');
  out['fomo_pub'] = fomoPub.map ?? fomoPub.snippet;

  // profiles as anon vs auth — PII beyond Hub whitelist
  final profAnon = await c.rest(
    'GET',
    'profiles?id=eq.${c.seller2Id}&select=id,handle,email,phone,iban,mb_way,stripe_account_id,address,location,hub_published,full_name',
  );
  c.note('p1.m1.profiles.anon', 'anon GET profiles unpublished', profAnon.brief,
      lens: 'M1');
  final profAuth = await c.rest(
    'GET',
    'profiles?id=eq.${c.seller2Id}&select=id,handle,phone,iban,mb_way,stripe_account_id,location,hub_published,full_name,email',
    jwt: c.buyerJwt,
  );
  c.note('p1.m1.profiles.auth', 'buyer JWT GET unpublished seller profile',
      profAuth.brief,
      lens: 'M1');
  out['profiles_anon'] = profAnon.snippet;
  out['profiles_auth'] = profAuth.snippet;
  if (profAuth.ok && profAuth.list.isNotEmpty) {
    final m = profAuth.map!;
    final pii = [
      'iban',
      'mb_way',
      'stripe_account_id',
      'phone',
      'email',
    ].where((k) => m[k] != null && '${m[k]}'.trim().isNotEmpty).toList();
    if (pii.isNotEmpty || m['hub_published'] == false) {
      c.hold(
        id: 'RTM-M1-008',
        lens: 'M1',
        severity: pii.isNotEmpty ? 'P1' : 'P2',
        title: pii.isNotEmpty
            ? 'JWT comprador lê colunas financeiras/PII de perfil não publicado (${pii.join(",")})'
            : 'JWT comprador lê perfil completo de vitrine não publicada (além da view Hub)',
        actor: 'buyer JWT',
        pre: 'resolve_handle + GET profiles?id=eq.seller2',
        repro: 'GET rest/v1/profiles?id=eq.<unpublished>&select=iban,mb_way,phone',
        expected: 'só whitelist Hub / directory publicado',
        obtained: clip(m, 400),
        evidence: {'pii_keys': pii, 'hub_published': m['hub_published']},
      );
    }
  }

  // unlisted product via hub vs base
  final hubProd = await c.rest(
    'GET',
    'hub_products_public?id=eq.$unlisted&select=id,title,price',
  );
  final prodAnon = await c.rest(
    'GET',
    'products?id=eq.$unlisted&select=id,title,quantity,price,list_on_marketplace,image_urls,seller_id',
  );
  final prodAuth = await c.rest(
    'GET',
    'products?id=eq.$unlisted&select=id,title,quantity,price,list_on_marketplace,image_urls',
    jwt: c.buyerJwt,
  );
  c.note('p1.m1.prod.hub', 'hub unlisted', hubProd.brief, lens: 'M1');
  c.note('p1.m1.prod.anon', 'anon products unlisted', prodAnon.brief, lens: 'M1');
  c.note('p1.m1.prod.auth', 'auth products unlisted', prodAuth.brief, lens: 'M1');
  if ((prodAnon.ok && prodAnon.list.isNotEmpty) ||
      (prodAuth.ok && prodAuth.list.isNotEmpty && prodAnon.list.isEmpty)) {
    final hit = prodAnon.list.isNotEmpty ? prodAnon : prodAuth;
    c.hold(
      id: 'RTM-M1-009',
      lens: 'M1',
      severity: 'P1',
      title: 'produto não listado visível fora da view Hub (qty/imagens)',
      actor: prodAnon.list.isNotEmpty ? 'anon' : 'buyer JWT',
      pre: 'list_on_marketplace=false seller2',
      repro: 'GET products?id=eq.<unlisted>',
      expected: 'invisível (só dono)',
      obtained: hit.snippet,
    );
  }

  // resolve-mux-playback on unpublished (no hub gate)
  for (final entry in [
    ['unpub_sched', unpubLive],
    ['draft', draftLive],
    ['active_unpub', activeUnpubLive],
    ['pub_ended', pubLive],
  ]) {
    final mux = await c.edge('resolve-mux-playback', body: {'live_id': entry[1]});
    c.note('p1.m1.mux.${entry[0]}', 'anon resolve-mux-playback', mux.brief,
        lens: 'M1');
    out['mux_${entry[0]}'] = mux.brief;
    if (mux.ok &&
        (entry[0] == 'unpub_sched' || entry[0] == 'draft') &&
        (mux.body.contains('playback') || mux.body.contains('stream.mux.com'))) {
      c.hold(
        id: 'RTM-M1-010',
        lens: 'M1',
        severity: 'P1',
        title: 'Edge resolve-mux-playback anon devolve HLS de live não publicada (${entry[0]})',
        actor: 'anon',
        pre: 'live ${entry[0]} seller2 hub_published=false',
        repro: 'POST functions/v1/resolve-mux-playback {live_id}',
        expected: '404 / live_not_public',
        obtained: mux.snippet,
      );
    }
  }

  // =====================================================================
  // M6 — storage (não chat_uploads J)
  // =====================================================================
  final buckets = await c.req('GET', '/storage/v1/bucket');
  c.note('p1.m6.buckets.anon', 'anon list buckets', buckets.brief, lens: 'M6');
  final bucketsAuth = await c.req('GET', '/storage/v1/bucket', jwt: c.buyerJwt);
  c.note('p1.m6.buckets.auth', 'auth list buckets', bucketsAuth.brief, lens: 'M6');
  final bucketsSvc = await c.req('GET', '/storage/v1/bucket', service: true);
  c.note('p1.m6.buckets.svc', 'svc list buckets',
      '${bucketsSvc.status} n=${bucketsSvc.list.length}',
      lens: 'M6');
  out['buckets_anon'] = buckets.snippet;
  out['buckets_auth'] = bucketsAuth.snippet;
  out['buckets_svc_n'] = bucketsSvc.list.length;
  out['bucket_ids'] = bucketsSvc.list
      .whereType<Map>()
      .map((e) => '${e['id']}:${e['public']}')
      .toList();

  for (final b in ['fleaber_private', 'chat_media', 'product-images', 'products', 'avatars']) {
    final listAnon = await c.req(
      'POST',
      '/storage/v1/object/list/$b',
      body: {'prefix': '', 'limit': 20},
    );
    c.note('p1.m6.list.anon.$b', 'anon list $b', listAnon.brief, lens: 'M6');
    if (listAnon.ok && listAnon.list.isNotEmpty) {
      c.hold(
        id: 'RTM-M6-001-$b',
        lens: 'M6',
        severity: b == 'fleaber_private' ? 'P0' : 'P1',
        title: 'anon lista objectos do bucket $b',
        actor: 'anon',
        pre: 'POST /storage/v1/object/list/$b',
        repro: 'POST storage object/list/$b prefix=',
        expected: 'vazio / 400 / RLS deny',
        obtained: clip(listAnon.snippet, 300),
        evidence: {'n': listAnon.list.length},
      );
    }
  }

  // list fleaber_private as svc then try public GET of first object
  final privList = await c.req(
    'POST',
    '/storage/v1/object/list/fleaber_private',
    service: true,
    body: {'prefix': '', 'limit': 15},
  );
  c.note('p1.m6.priv.svc', 'svc fleaber_private list',
      '${privList.status} n=${privList.list.length} ${privList.snippet}',
      lens: 'M6');
  out['priv_list'] = privList.snippet;
  if (privList.list.isNotEmpty) {
    final first = privList.list.first;
    final name = first is Map ? '${first['name']}' : '';
    if (name.isNotEmpty) {
      final pub = await c.req(
        'GET',
        '/storage/v1/object/public/fleaber_private/$name',
      );
      final authGet = await c.req(
        'GET',
        '/storage/v1/object/fleaber_private/$name',
        jwt: c.buyerJwt,
      );
      c.note('p1.m6.priv.public', 'anon public GET $name', pub.brief, lens: 'M6');
      c.note('p1.m6.priv.auth', 'buyer GET $name', authGet.brief, lens: 'M6');
      if (pub.ok && pub.status != 400) {
        c.hold(
          id: 'RTM-M6-002',
          lens: 'M6',
          severity: 'P0',
          title: 'objecto fleaber_private servido em URL public/',
          actor: 'anon',
          pre: 'bucket public=false',
          repro: 'GET /storage/v1/object/public/fleaber_private/<path>',
          expected: '400/404',
          obtained: pub.brief,
        );
      }
      if (authGet.ok) {
        c.hold(
          id: 'RTM-M6-003',
          lens: 'M6',
          severity: 'P0',
          title: 'comprador JWT lê objecto fleaber_private alheio',
          actor: 'buyer JWT',
          pre: 'ficheiro listado por service_role, sem ser dono',
          repro: 'GET /storage/v1/object/fleaber_private/<path>',
          expected: '403',
          obtained: authGet.brief,
        );
      }
    }
  }

  final chatList = await c.req(
    'POST',
    '/storage/v1/object/list/chat_media',
    service: true,
    body: {'prefix': '', 'limit': 10},
  );
  c.note('p1.m6.chat.svc', 'svc chat_media list',
      '${chatList.status} n=${chatList.list.length}',
      lens: 'M6');
  if (chatList.list.isNotEmpty) {
    final first = chatList.list.first;
    final name = first is Map ? '${first['name']}' : '';
    if (name.isNotEmpty && !name.contains('chat_uploads')) {
      final pub = await c.req(
        'GET',
        '/storage/v1/object/public/chat_media/$name',
      );
      c.note('p1.m6.chat.public', 'anon public chat_media/$name', pub.brief,
          lens: 'M6');
      if (pub.ok && pub.status == 200) {
        c.hold(
          id: 'RTM-M6-004',
          lens: 'M6',
          severity: 'P2',
          title: 'objecto chat_media (não chat_uploads) público via /object/public/',
          actor: 'anon',
          pre: 'path=$name',
          repro: 'GET /storage/v1/object/public/chat_media/$name',
          expected: 'catálogo intencional ou 403',
          obtained: '${pub.status} bytes=${pub.body.length}',
          proven: pub.body.length > 32,
        );
      }
    }
  }

  // =====================================================================
  // M2 — CORS + web_return_origin (2 edges) — verify, not dual-session
  // =====================================================================
  final origins = [
    'https://evil.com',
    'https://attacker.fleaber.pt',
    'https://fleaber.app',
    'https://www.fleaber.app',
    'chrome-extension://abcdefghijklmnopqrstuvwxyz',
    'https://fleaber.pt.evil.com',
    'http://evil.com',
  ];
  final corsMap = <String, Object?>{};
  for (final o in origins) {
    final opt = await c.edge(
      'create-live-tip-checkout',
      method: 'OPTIONS',
      extra: {
        'Origin': o,
        'Access-Control-Request-Method': 'POST',
      },
    );
    corsMap['opt_$o'] = {'status': opt.status, 'acao': opt.acao};
    final post = await c.edge(
      'resolve-mux-playback',
      body: {'live_id': pubLive},
      extra: {'Origin': o},
    );
    corsMap['post_$o'] = {'status': post.status, 'acao': post.acao};
    c.note('p1.m2.cors', 'Origin=$o', 'opt=${opt.status}/${opt.acao} post=${post.status}/${post.acao}',
        lens: 'M2');
    final reflected = post.acao == o || opt.acao == o;
    if (reflected &&
        (o.contains('evil') ||
            o.contains('attacker') ||
            o.startsWith('chrome-extension'))) {
      c.hold(
        id: 'RTM-M2-001',
        lens: 'M2',
        severity: o.contains('attacker') || o.startsWith('chrome-extension')
            ? 'P2'
            : 'P1',
        title: 'CORS reflecte Origin hostil $o',
        actor: 'browser Origin',
        pre: 'OPTIONS/POST Edge',
        repro: 'Origin: $o → Access-Control-Allow-Origin',
        expected: 'não reflectir (fleaber.pt ou omitir)',
        obtained: 'opt=${opt.acao} post=${post.acao}',
      );
    }
  }
  out['cors'] = corsMap;

  for (final o in [
    'https://evil.com/steal',
    'https://attacker.fleaber.pt',
    'https://fleaber.pt.evil.com',
    'https://fleaber.pt/@evil.com',
    'https://fleaber.pt%2f%2fevil.com',
    'https://127.0.0.1',
    'javascript:alert(1)',
    'https://fleaber.app',
  ]) {
    final qs =
        '?web_return_origin=${Uri.encodeQueryComponent(o)}&wallet_return=1';
    final g = await c.edge('create-connect-account', method: 'GET', qs: qs);
    c.note('p1.m2.connect.get', 'GET connect origin=$o', g.brief, lens: 'M2');
    final loc = g.location ?? '';
    if (loc.contains('evil') ||
        loc.contains('attacker') ||
        loc.startsWith('javascript:')) {
      c.hold(
        id: 'RTM-M2-002',
        lens: 'M2',
        severity: 'P0',
        title: 'create-connect-account GET redirecciona para origem hostil',
        actor: 'anon GET',
        pre: 'web_return_origin=$o',
        repro: 'GET create-connect-account?web_return_origin=',
        expected: 'deep link fleaber:// ou /wallet em host allowlist',
        obtained: g.brief,
      );
    }
  }

  final tipEvil = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyerJwt,
    body: {
      'seller_id': c.sellerId,
      'amount_eur': 1,
      'live_id': pubLive,
      'web_return_origin': 'https://evil.com/steal',
      'tip_id': '00000000-0000-0000-0000-000000000001',
    },
  );
  c.note('p1.m2.tip.origin', 'tip checkout evil origin + tip_id spoof',
      tipEvil.brief,
      lens: 'M2');
  out['tip_evil'] = tipEvil.brief;
  // Session created? if 200 with checkout URL despite evil origin + tip_id
  if (tipEvil.ok && tipEvil.hasCheckout) {
    c.hold(
      id: 'RTM-M2-003',
      lens: 'M2',
      severity: 'P2',
      title: 'create-live-tip-checkout criou Session com web_return_origin evil (ou ignorou sem recusar tip_id)',
      actor: 'buyer JWT',
      pre: 'web_return_origin=https://evil.com/steal + tip_id spoof',
      repro: 'POST create-live-tip-checkout',
      expected: 'recusar tip_id cliente; origin hostil sanitizado (não em metadata)',
      obtained: tipEvil.snippet,
      proven: false,
    );
  }

  // =====================================================================
  // M4 — body spoof buyer_id / amount / user_id
  // =====================================================================
  final connectSpoof = await c.edge(
    'create-connect-account',
    jwt: c.buyerJwt,
    body: {
      'user_id': c.sellerId,
      'amount': 100,
      'web_return_origin': 'https://evil.com',
    },
  );
  c.note('p1.m4.connect.user', 'buyer Connect user_id=seller',
      connectSpoof.brief,
      lens: 'M4');
  if (connectSpoof.ok) {
    c.hold(
      id: 'RTM-M4-001',
      lens: 'M4',
      severity: 'P0',
      title: 'create-connect-account aceita user_id alheio',
      actor: 'buyer JWT',
      pre: 'body.user_id=seller',
      repro: 'POST create-connect-account user_id=<seller>',
      expected: 'erro Cannot create another user',
      obtained: connectSpoof.snippet,
    );
  }

  final tipAmt = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyerJwt,
    body: {
      'seller_id': c.buyerId,
      'amount_eur': 0.01,
      'live_id': pubLive,
    },
  );
  c.note('p1.m4.tip.amt', 'tip amount 0.01 seller=buyer', tipAmt.brief,
      lens: 'M4');

  final muxBuyer = await c.edge(
    'create-mux-live',
    jwt: c.buyerJwt,
    body: {'title': '$prefix mux hijack'},
  );
  c.note('p1.m4.mux.buyer', 'buyer create-mux-live', muxBuyer.brief, lens: 'M5');
  if (muxBuyer.ok) {
    c.hold(
      id: 'RTM-M5-001',
      lens: 'M5',
      severity: 'P0',
      title: 'comprador cria stream Mux (create-mux-live)',
      actor: 'buyer JWT',
      pre: 'user_type=comprador',
      repro: 'POST create-mux-live title=...',
      expected: '403 authz',
      obtained: muxBuyer.snippet,
    );
  }

  final completeX = await c.edge(
    'complete-mux-live',
    jwt: c.seller2Jwt,
    body: {'live_id': pubLive},
  );
  c.note('p1.m5.complete.x', 'seller2 complete seller1 live', completeX.brief,
      lens: 'M5');
  if (completeX.ok) {
    c.hold(
      id: 'RTM-M5-002',
      lens: 'M5',
      severity: 'P0',
      title: 'vendedor B termina directo Mux do vendedor A',
      actor: 'seller2 JWT',
      pre: 'live.seller_id=seller1',
      repro: 'POST complete-mux-live live_id=<A>',
      expected: '403 Sem permissão',
      obtained: completeX.snippet,
    );
  }

  final lkX = await c.edge(
    'livekit-mux-publish',
    jwt: c.seller2Jwt,
    body: {'step': 'token', 'live_id': pubLive},
  );
  c.note('p1.m5.livekit.x', 'seller2 LiveKit token live A', lkX.brief, lens: 'M5');
  if (lkX.ok && (lkX.body.contains('token') || lkX.map?['token'] != null)) {
    c.hold(
      id: 'RTM-M5-003',
      lens: 'M5',
      severity: 'P0',
      title: 'LiveKit publish token emitido para live de outro vendedor',
      actor: 'seller2 JWT',
      pre: 'step=token live_id=A',
      repro: 'POST livekit-mux-publish',
      expected: '403',
      obtained: lkX.snippet,
    );
  }

  final ingest = await c.edge(
    'ingest-ocr-reservation',
    body: {
      'live_id': pubLive,
      'ocr_line_hash': 'rtmhash12',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ref_number': 1,
      'requested_qty': 99,
      'external_display_name': 'RTM',
    },
    extra: {'x-device-token': 'rtm-fake-token-$stamp'},
  );
  c.note('p1.m4.ingest', 'ingest OCR fake token qty=99', ingest.brief, lens: 'M4');
  if (ingest.ok && ingest.map?['ok'] == true) {
    c.hold(
      id: 'RTM-M4-002',
      lens: 'M4',
      severity: 'P0',
      title: 'ingest-ocr-reservation aceita device token inventado (qty spoof)',
      actor: 'anon + x-device-token fake',
      pre: 'sem pairing',
      repro: 'POST ingest-ocr-reservation',
      expected: '401 invalid_token',
      obtained: ingest.snippet,
    );
  }

  // =====================================================================
  // M3 — settle GET session alheia / forjada
  // =====================================================================
  final settleFake = await c.edge(
    'create-live-tip-checkout',
    method: 'GET',
    qs: '?checkout_return=success&session_id=cs_test_rtm_forged_$stamp',
  );
  c.note('p1.m3.tip.settle.fake', 'GET tip settle forged cs', settleFake.brief,
      lens: 'M3');
  if (settleFake.ok &&
      (settleFake.location ?? '').contains('stripe-success') &&
      settleFake.body.toLowerCase().contains('recebido')) {
    c.hold(
      id: 'RTM-M3-001',
      lens: 'M3',
      severity: 'P1',
      title: 'GET tip settle trata session_id forjado como sucesso',
      actor: 'anon GET',
      pre: 'cs_test_rtm_forged',
      repro: 'GET create-live-tip-checkout?checkout_return=success&session_id=',
      expected: 'erro / pagamento não confirmado',
      obtained: settleFake.brief,
    );
  }

  final settlePi = await c.req(
    'GET',
    '/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_rtm_alien_$stamp',
  );
  c.note('p1.m3.pi.settle.alien', 'GET PI settle alien cs', settlePi.brief,
      lens: 'M3');

  // steal a real cs from seller orders if any
  final orders = await c.rest(
    'GET',
    'orders?seller_id=eq.${c.sellerId}&select=id,status,stripe_checkout_session_id,buyer_id&stripe_checkout_session_id=not.is.null&order=created_at.desc&limit=3',
    service: true,
  );
  String? stolenCs;
  for (final row in orders.list.whereType<Map>()) {
    final cs = row['stripe_checkout_session_id']?.toString() ?? '';
    if (cs.startsWith('cs_')) {
      stolenCs = cs;
      break;
    }
  }
  out['stolen_cs'] = stolenCs;
  if (stolenCs != null) {
    final stealTip = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs: '?checkout_return=success&session_id=$stolenCs',
    );
    c.note('p1.m3.tip.stolen_cs', 'GET tip settle with order cs', stealTip.brief,
        lens: 'M3');
    final stealPi = await c.req(
      'GET',
      '/functions/v1/create-payment-intent?checkout_return=success&session_id=$stolenCs',
      jwt: c.buyer2Jwt,
    );
    c.note('p1.m3.pi.stolen_cs', 'B2 GET PI settle stolen cs', stealPi.brief,
        lens: 'M3');
    out['steal_tip'] = stealTip.brief;
    out['steal_pi'] = stealPi.brief;
  }

  await c.endLives();

  out['findings'] = c.findings;
  out['notes'] = c.notes;
  out['atrofia_pass1_classes'] = {
    'hub_paused_items': false,
    'invite_enum': false,
    'pairing_ended': false,
    'dual_session': false,
    'mint_pos_payout': false,
    'plain_to_json': false,
  };

  final dir = '${repoRoot()}/tool/redteam_blind_m_$stamp';
  await dumpJson('$dir/pass1.json', out);
  stdout.writeln('FINDINGS ${c.findings.length}');
  stdout.writeln('WROTE $dir/pass1.json');
}
