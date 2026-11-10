/// BO pass 1 — Hub/FOMO, origin/CORS, tip, Edge body, Mux, storage, composição.
import 'dart:io';

import '_rtbo.dart';

bool _hasPlayback(HttpHit h) {
  final m = h.map;
  if (m == null) return false;
  final vod = '${m['mux_vod_playback_id'] ?? ''}'.trim();
  final live = '${m['mux_playback_id'] ?? ''}'.trim();
  final pb = '${m['playback_id'] ?? ''}'.trim();
  return vod.isNotEmpty || live.isNotEmpty || pb.isNotEmpty;
}

String? _vod(HttpHit h) {
  final v = h.map?['mux_vod_playback_id']?.toString().trim();
  if (v == null || v.isEmpty) return null;
  return v;
}

bool _corsReflected(HttpHit h, String origin) {
  final a = (h.acao ?? '').trim();
  if (a.isEmpty || a == '*') return false;
  return a == origin || a.toLowerCase() == origin.toLowerCase();
}

bool _locationHostile(String? loc) {
  if (loc == null || loc.isEmpty) return false;
  Uri? u;
  try {
    u = Uri.parse(loc);
  } catch (_) {
    return loc.contains('evil') || loc.contains('nip.io') || loc.contains('localtest');
  }
  final host = u.host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
  const allowed = {
    'fleaber.pt',
    'www.fleaber.pt',
    'fleaber.app',
    'www.fleaber.app',
    'localhost',
    '127.0.0.1',
  };
  if (allowed.contains(host)) return false;
  if (host.isEmpty) return false;
  return true;
}

Future<void> main() async {
  final c = Rtbo.fromEnv(loadEnv());
  try {
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2Unpublished();
  await c.pickPlantedPlayback();
  final plant = c.plantedPlaybackId!;

  // Ensure lab seller is hub_published so vitrine fixtures work.
  await c.rest('PATCH', 'profiles?id=eq.${c.sellerId}', service: true, body: {
    'hub_published': true,
  }, prefer: 'return=minimal');

  final liveAir = await c.insertLive(
    status: 'live',
    active: true,
    title: '$prefix-air',
    muxLiveId: 'muxlive-air-$stamp',
    muxPlaybackId: 'play-air-$stamp',
    muxVodPlaybackId: plant,
    streamKey: 'sk-air-$stamp',
  );
  final liveSched = await c.insertLive(
    status: 'scheduled',
    active: false,
    title: '$prefix-sched',
    muxLiveId: 'muxlive-sched-$stamp',
    muxPlaybackId: 'play-sched-$stamp',
    muxVodPlaybackId: plant,
    streamKey: 'sk-sched-$stamp',
  );
  final liveDraft = await c.insertLive(
    status: 'draft',
    active: false,
    title: '$prefix-draft',
    muxLiveId: 'muxlive-draft-$stamp',
    muxPlaybackId: 'play-draft-$stamp',
    muxVodPlaybackId: plant,
    streamKey: 'sk-draft-$stamp',
  );
  final liveEndedPub = await c.insertLive(
    status: 'ended',
    active: false,
    title: '$prefix-ended-pub',
    muxLiveId: 'muxlive-ended-$stamp',
    muxPlaybackId: 'play-ended-$stamp',
    muxVodPlaybackId: plant,
    streamKey: 'sk-ended-$stamp',
  );
  final livePaused = await c.insertLive(
    status: 'paused',
    active: true,
    title: '$prefix-paused',
    muxLiveId: 'muxlive-paused-$stamp',
    muxPlaybackId: 'play-paused-$stamp',
    muxVodPlaybackId: plant,
    streamKey: 'sk-paused-$stamp',
  );
  final liveLiveInactive = await c.insertLive(
    status: 'live',
    active: false,
    title: '$prefix-live-inactive',
    muxLiveId: 'muxlive-linact-$stamp',
    muxPlaybackId: 'play-linact-$stamp',
    muxVodPlaybackId: plant,
    streamKey: 'sk-linact-$stamp',
  );
  final liveEndedUnpub = await c.insertLive(
    seller: c.seller2Id,
    status: 'ended',
    active: false,
    title: '$prefix-ended-unpub',
    muxLiveId: 'muxlive-unpub-end-$stamp',
    muxPlaybackId: 'play-unpub-end-$stamp',
    muxVodPlaybackId: plant,
    streamKey: 'sk-unpub-end-$stamp',
  );
  final liveAirUnpub = await c.insertLive(
    seller: c.seller2Id,
    status: 'live',
    active: true,
    title: '$prefix-air-unpub',
    muxLiveId: 'muxlive-unpub-air-$stamp',
    muxPlaybackId: 'play-unpub-air-$stamp',
    muxVodPlaybackId: plant,
    streamKey: 'sk-unpub-air-$stamp',
  );
  final liveSchedUnpub = await c.insertLive(
    seller: c.seller2Id,
    status: 'scheduled',
    active: false,
    title: '$prefix-sched-unpub',
    muxLiveId: 'muxlive-unpub-sched-$stamp',
    muxPlaybackId: 'play-unpub-sched-$stamp',
    muxVodPlaybackId: plant,
    streamKey: 'sk-unpub-sched-$stamp',
  );
  if (liveAir != null) await c.insertLiveItem(liveId: liveAir, qty: 3);

  Future<HttpHit> view(String name, String? id) {
    if (id == null) {
      return Future.value(HttpHit(0, 'no-id', null));
    }
    return c.rest(
      'GET',
      '$name?id=eq.$id&select=*',
    );
  }

  // ---------------------------------------------------------------------------
  // BO1 Hub / FOMO / handle_suggested / outras views
  // ---------------------------------------------------------------------------
  final views = <String, String?>{
    'air': liveAir,
    'sched': liveSched,
    'draft': liveDraft,
    'ended_pub': liveEndedPub,
    'paused': livePaused,
    'live_inactive': liveLiveInactive,
    'ended_unpub': liveEndedUnpub,
    'air_unpub': liveAirUnpub,
    'sched_unpub': liveSchedUnpub,
  };

  for (final e in views.entries) {
    for (final vn in [
      'hub_lives_public',
      'hub_lives_discovery_public',
      'hub_live_items_public',
      'hub_live_items_discovery_public',
    ]) {
      final h = await view(vn, e.value);
      c.note('bo1.$vn.${e.key}', '$vn ${e.key}', h, lens: 'BO1');
      final vod = _vod(h);
      final premature = vod != null &&
          e.key != 'ended_pub' &&
          !(e.key == 'ended_unpub');
      if (vn == 'hub_lives_discovery_public' &&
          e.key == 'sched' &&
          vod != null) {
        c.hold(
          id: 'bo1.disc.sched.vod',
          lens: 'BO1',
          severity: 'P2',
          title: 'discovery scheduled+VOD (exacto BI — não contar)',
          actor: 'anon',
          pre: 'live scheduled com mux_vod plantado',
          repro: 'GET hub_lives_discovery_public?id=eq.$liveSched',
          expected: 'mux_vod_playback_id null',
          obtained: h.brief,
          count: false,
        );
      } else if (premature && _hasPlayback(h) && vod != null) {
        c.hold(
          id: 'bo1.$vn.${e.key}.vod',
          lens: 'BO1',
          severity: 'P2',
          title: '$vn expõe VOD em estado ${e.key}',
          actor: 'anon',
          pre: 'live ${e.key} com mux_vod plantado=$plant',
          repro: 'GET $vn?id=eq.${e.value}&select=*',
          expected: 'sem mux_vod_playback_id fora de ended público',
          obtained: h.brief,
        );
      }
    }
  }

  // JWT base table lives — outra superfície de playback
  for (final e in {
    'sched': liveSched,
    'draft': liveDraft,
    'paused': livePaused,
    'live_inactive': liveLiveInactive,
    'ended_unpub': liveEndedUnpub,
    'sched_unpub': liveSchedUnpub,
  }.entries) {
    final jwtRow = await c.rest(
      'GET',
      'lives?id=eq.${e.value}&select=id,status,is_active,mux_playback_id,mux_vod_playback_id,mux_asset_id,playback_id,livekit_room_name,mux_stream_key,stream_key,mux_live_id',
      jwt: c.buyerJwt,
    );
    c.note('bo1.lives.jwt.${e.key}', 'buyer GET lives ${e.key}', jwtRow,
        lens: 'BO1');
    final sk = jwtRow.map?['mux_stream_key'] ?? jwtRow.map?['stream_key'];
    if (sk != null && '$sk'.trim().isNotEmpty) {
      c.hold(
        id: 'bo1.lives.jwt.streamkey.${e.key}',
        lens: 'BO1',
        severity: 'P1',
        title: 'buyer JWT lê stream_key da live ${e.key}',
        actor: 'buyer JWT',
        pre: 'coluna RTMP plantada',
        repro: 'GET lives?id=eq.${e.value}&select=mux_stream_key,stream_key',
        expected: 'omitida / 403',
        obtained: jwtRow.brief,
      );
    }
    final vod = _vod(jwtRow);
    if (vod != null && e.key != 'ended_pub') {
      final cdn = await c.muxCdn(vod);
      c.note('bo1.lives.jwt.cdn.${e.key}', 'CDN vod ${e.key}', cdn, lens: 'BO1');
      final watches = cdn.ok &&
          (cdn.body.contains('#EXTM3U') || cdn.status == 200);
      c.hold(
        id: 'bo1.lives.jwt.vod.${e.key}',
        lens: 'BO1',
        severity: watches ? 'P2' : 'P3',
        title:
            'buyer JWT lê mux_vod_playback_id de live ${e.key} (não é a view discovery)',
        actor: 'buyer JWT',
        pre: 'lives RLS feed_or_owner + grant colunas vod',
        repro: 'GET /rest/v1/lives?id=eq.${e.value}&select=mux_vod_playback_id',
        expected: 'VOD só via hub ended / Edge resolve-mux público',
        obtained: '${jwtRow.brief} cdn=${cdn.brief}',
        evidence: {'cdn_status': cdn.status, 'watches': watches, 'vod': vod},
      );
    }
    final anonLives = await c.rest(
      'GET',
      'lives?id=eq.${e.value}&select=id,mux_vod_playback_id,mux_stream_key',
    );
    c.note('bo1.lives.anon.${e.key}', 'anon GET lives', anonLives, lens: 'BO1');
    if (anonLives.ok && _hasPlayback(anonLives)) {
      c.hold(
        id: 'bo1.lives.anon.vod.${e.key}',
        lens: 'BO1',
        severity: 'P2',
        title: 'anon lê playback na tabela lives ${e.key}',
        actor: 'anon',
        pre: 'revoke all lives from anon (esperado)',
        repro: 'GET lives anon',
        expected: '401/403 ou []',
        obtained: anonLives.brief,
      );
    } else {
      c.block('bo1.lives.anon.${e.key}', 'BO1', 'anon lives ${e.key}', anonLives);
    }
  }

  // handle_suggested unpublished
  final resolveSug = await c.rpc('batata_resolve_handle', {
    'p_handle': 'rtbo1905s2sug',
  });
  c.note('bo1.handle.sug', 'resolve handle_suggested unpublished', resolveSug,
      lens: 'BO1');
  final sugFound = resolveSug.map?['found'] == true;
  final sugPid = resolveSug.map?['profile_id']?.toString();
  if (sugFound && sugPid != null && sugPid == c.seller2Id) {
    final vitrine = await view('hub_profiles_public', c.seller2Id);
    final emptyVitrine = !vitrine.ok || vitrine.list.isEmpty || vitrine.map == null;
    c.hold(
      id: 'bo1.handle.sug.unpub',
      lens: 'BO1',
      severity: emptyVitrine ? 'P3' : 'P2',
      title:
          'batata_resolve_handle enumera UUID de loja desligada via handle_suggested',
      actor: 'anon',
      pre: 'S2 hub_published=false handle=null handle_suggested=rtbo1905s2sug',
      repro: 'POST rpc/batata_resolve_handle p_handle=rtbo1905s2sug',
      expected: 'not_found (vitrine e discovery vazias)',
      obtained: '${resolveSug.brief} vitrine=${vitrine.brief}',
    );
  } else {
    c.block('bo1.handle.sug', 'BO1', 'handle_suggested unpublished não resolve',
        resolveSug);
  }

  final resolveEmpty = await c.rpc('batata_resolve_handle', {'p_handle': ''});
  c.block('bo1.handle.empty', 'BO1', 'handle vazio', resolveEmpty);

  // FOMO RPC
  for (final e in views.entries) {
    final fomoAnon = await c.rpc('batata_hub_live_fomo_snapshot', {
      'p_live_id': e.value,
    });
    c.note('bo1.fomo.anon.${e.key}', 'FOMO anon ${e.key}', fomoAnon, lens: 'BO1');
    final fomoBuyer = await c.rpc('batata_hub_live_fomo_snapshot', {
      'p_live_id': e.value,
    }, jwt: c.buyerJwt);
    c.note('bo1.fomo.buyer.${e.key}', 'FOMO buyer ${e.key}', fomoBuyer,
        lens: 'BO1');
    bool fomoOpen(HttpHit h) {
      final m = h.map;
      if (m == null) return false;
      if (m['ok'] == false) return false;
      if (m['ok'] == true && e.key != 'air' && e.key != 'ended_pub') {
        // snapshot de live que não deveria ser vitrine
        if (e.key == 'air_unpub' ||
            e.key == 'draft' ||
            e.key == 'paused' ||
            e.key == 'ended_unpub' ||
            e.key == 'sched_unpub' ||
            e.key == 'live_inactive') {
          return true;
        }
      }
      return false;
    }

    await c.expectDenied(
      id: 'bo1.fomo.${e.key}',
      lens: 'BO1',
      title: 'FOMO snapshot em estado ${e.key}',
      hit: fomoAnon,
      actor: 'anon',
      pre: 'live ${e.key}',
      repro: 'rpc batata_hub_live_fomo_snapshot',
      severityIfOpen: 'P3',
      openIf: fomoOpen,
    );
  }

  final fomoGhost = await c.rpc('batata_hub_live_fomo_snapshot', {
    'p_live_id': '00000000-0000-0000-0000-000000000001',
  });
  await c.expectDenied(
    id: 'bo1.fomo.ghost',
    lens: 'BO1',
    title: 'FOMO UUID inexistente',
    hit: fomoGhost,
    actor: 'anon',
    pre: 'uuid ghost',
    repro: 'rpc batata_hub_live_fomo_snapshot',
    openIf: (h) => h.map?['ok'] == true,
  );

  final bcAnon = await c.rpc('batata_live_is_broadcasting', {
    'p_live_id': liveAir,
  });
  c.note('bo1.bcast.anon', 'anon batata_live_is_broadcasting', bcAnon,
      lens: 'BO1');
  if (bcAnon.ok && (bcAnon.json == true || bcAnon.json == false)) {
    c.hold(
      id: 'bo1.bcast.anon',
      lens: 'BO1',
      severity: 'P3',
      title: 'anon executa batata_live_is_broadcasting (fecho BFBK invertido?)',
      actor: 'anon',
      pre: 'revoke execute from anon',
      repro: 'rpc batata_live_is_broadcasting',
      expected: '401/403',
      obtained: bcAnon.brief,
    );
  } else {
    c.block('bo1.bcast.anon', 'BO1', 'anon broadcasting recusado', bcAnon);
  }

  // ---------------------------------------------------------------------------
  // BO2 origin / CORS / Connect IPv6 + DNS rebinding
  // ---------------------------------------------------------------------------
  const origins = [
    'https://evil.com',
    'http://evil.com',
    'https://fleaber.pt.evil.com',
    'https://evil.fleaber.pt',
    'https://attacker.fleaber.pt',
    'http://[::1]:3000',
    'http://[::ffff:127.0.0.1]:8080',
    'https://[::ffff:127.0.0.1]',
    'null',
    'https://fleaber.pt',
    'http://localhost:5173',
    'http://127.0.0.1:4173',
    'chrome-extension://abcdef',
    'https://localtest.me',
    'https://lvh.me',
  ];
  for (final origin in origins) {
    final opt = await c.edge(
      'create-connect-account',
      null,
      method: 'OPTIONS',
      extra: {
        'Origin': origin,
        'Access-Control-Request-Method': 'POST',
        'Access-Control-Request-Headers': 'authorization,content-type,x-webhook-secret',
      },
    );
    final post = await c.edge(
      'resolve-mux-playback',
      {'live_id': liveDraft},
      extra: {'Origin': origin},
    );
    c.note('bo2.cors.$origin', 'CORS Origin=$origin', {
      'opt': opt.brief,
      'post': post.brief,
      'opt_acao': opt.acao,
      'post_acao': post.acao,
      'acah': opt.acah,
    }, lens: 'BO2');
    final hostile = origin != 'https://fleaber.pt' &&
        origin != 'http://localhost:5173' &&
        origin != 'http://127.0.0.1:4173';
    if (hostile && (_corsReflected(opt, origin) || _corsReflected(post, origin))) {
      c.hold(
        id: 'bo2.cors.reflect',
        lens: 'BO2',
        severity: 'P2',
        title: 'CORS reflecte Origin hostil $origin',
        actor: 'browser Origin',
        pre: 'allowlist exact + localhost port',
        repro: 'OPTIONS/POST functions com Origin=$origin',
        expected: 'ACAO=https://fleaber.pt ou omitido (não reflectir)',
        obtained: 'opt=${opt.acao} post=${post.acao}',
      );
    } else if (hostile) {
      c.block('bo2.cors.$origin', 'BO2', 'CORS não reflecte $origin',
          'opt=${opt.acao} post=${post.acao}');
    }
  }

  const returnOrigins = [
    'https://[::1]/wallet',
    'https://[::ffff:127.0.0.1]/x',
    'http://[::ffff:127.0.0.1]/x',
    'https://[::ffff:7f00:1]/',
    'http://[::1]',
    'https://localtest.me',
    'https://lvh.me',
    'https://127.0.0.1.nip.io',
    'https://spoofed.localhost',
    'https://fleaber.pt.evil.com',
    'https://evil.fleaber.pt',
    'https://localhost.evil.com',
    'https://fleaber.pt',
    'http://localhost',
    'http://127.0.0.1',
    'https://2130706433',
    'https://127.1',
    'https://0x7f000001',
    'https://0177.0.0.1',
    'https://0.0.0.0',
    r'https://fleaber.pt@evil.com',
    'https://fleaber.pt%00.evil.com',
    'javascript:alert(1)',
    'https://127.0.0.1.xip.io',
    'https://[::ffff:8.8.8.8]/',
  ];
  for (final origin in returnOrigins) {
    final qs = 'web_return_origin=${Uri.encodeQueryComponent(origin)}';
    final get = await c.edge(
      'create-connect-account',
      null,
      method: 'GET',
      qs: qs,
    );
    c.note('bo2.wr.get', 'GET web_return_origin=$origin', get, lens: 'BO2');
    final exactClosed = origin == 'https://2130706433' ||
        origin == 'https://127.1' ||
        origin == 'https://0x7f000001';
    final open = get.status == 303 && _locationHostile(get.location);
    if (open) {
      c.hold(
        id: 'bo2.wr.ipv6',
        lens: 'BO2',
        severity: 'P2',
        title: 'web_return 303 para host hostil ($origin)',
        actor: 'anon GET Connect',
        pre: 'GET create-connect-account sem JWT',
        repro: 'GET create-connect-account?web_return_origin=$origin',
        expected: 'sem Location hostil (HTML/Intent wallet)',
        obtained: get.brief,
        count: !exactClosed,
      );
    } else if (exactClosed) {
      c.block('bo2.wr.exact', 'BO2', 'exacto BC $origin recusado', get);
    } else {
      c.block('bo2.wr.$origin', 'BO2', 'web_return recusado $origin', get);
    }

    final post = await c.edge(
      'create-connect-account',
      {
        'action': 'onboarding',
        'web_return_origin': origin,
      },
      jwt: c.sellerJwt,
    );
    c.note('bo2.wr.post', 'POST onboarding origin=$origin', post, lens: 'BO2');
    final url = '${post.map?['url'] ?? ''}';
    if (url.contains('evil') ||
        url.contains('nip.io') ||
        url.contains('localtest') ||
        url.contains('%5B::') ||
        url.contains('[::')) {
      c.hold(
        id: 'bo2.wr.postembed',
        lens: 'BO2',
        severity: 'P2',
        title: 'AccountLink URL embute origin hostil',
        actor: 'seller JWT',
        pre: 'POST create-connect-account onboarding',
        repro: 'body web_return_origin=$origin',
        expected: 'return_url só função Edge / allowlist',
        obtained: post.brief,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // BO3 tip unpaid B2 + BO4 body spoof
  // ---------------------------------------------------------------------------
  if (liveAir != null) {
    final tipOk = await c.edge(
      'create-live-tip-checkout',
      {
        'live_id': liveAir,
        'seller_id': c.sellerId,
        'amount_eur': 1.5,
      },
      jwt: c.buyerJwt,
    );
    c.note('bo3.tip.create', 'buyer tip checkout live air', tipOk, lens: 'BO3');
    final tipId = tipOk.map?['tipId']?.toString();
    final csId = tipOk.map?['checkoutSessionId']?.toString();
    if (tipId != null) c.createdTipIds.add(tipId);

    if (csId != null && c.buyer2Jwt != null) {
      final b2settle = await c.edge(
        'create-live-tip-checkout',
        null,
        method: 'GET',
        qs:
            'checkout_return=success&session_id=${Uri.encodeQueryComponent(csId)}',
        jwt: c.buyer2Jwt,
      );
      c.note('bo3.tip.b2settle', 'B2 GET settle unpaid session', b2settle,
          lens: 'BO3');
      final row = tipId == null ? null : await c.tipRow(tipId);
      final sellerW = await c.walletBal(c.sellerId);
      c.note('bo3.tip.row', 'tip após B2 settle unpaid', {
        'row': row,
        'seller_wallet': sellerW,
        'http': b2settle.brief,
      }, lens: 'BO3');
      final completed = row?['status']?.toString() == 'completed';
      if (completed) {
        c.hold(
          id: 'bo3.tip.unpaid.b2',
          lens: 'BO3',
          severity: 'P0',
          title: 'B2 settle GET credita tip unpaid',
          actor: 'buyer2 JWT GET',
          pre: 'Session Stripe criada, payment_status unpaid',
          repro:
              'GET create-live-tip-checkout?checkout_return=success&session_id=',
          expected: 'pending / sem Δ wallet',
          obtained: '$row ${b2settle.brief}',
        );
      } else {
        c.block('bo3.tip.unpaid.b2', 'BO3', 'B2 unpaid não credita', {
          'status': row?['status'],
          'http': b2settle.brief,
        });
      }
      if ('${b2settle.body}'.contains('No such checkout')) {
        c.hold(
          id: 'bo3.tip.oracle',
          lens: 'BO3',
          severity: 'P3',
          title: 'tip settle ecoa No such checkout (exacto BC — não contar)',
          actor: 'anon/B2 GET',
          pre: 'session unpaid ou forjada',
          repro: 'GET create-live-tip-checkout?session_id=',
          expected: 'mensagem genérica',
          obtained: b2settle.brief,
          count: false,
        );
      }
    }

    if (tipId != null && c.buyer2Jwt != null) {
      final steal = await c.edge(
        'create-live-tip-checkout',
        {
          'live_id': liveAir,
          'seller_id': c.sellerId,
          'amount_eur': 1.5,
          'tip_id': tipId,
        },
        jwt: c.buyer2Jwt,
      );
      await c.expectDenied(
        id: 'bo4.tip_id.client',
        lens: 'BO4',
        title: 'B2 POST com tip_id do cliente (B1)',
        hit: steal,
        actor: 'buyer2 JWT',
        pre: 'tip pending B1',
        repro: 'POST create-live-tip-checkout tip_id alheio',
        openIf: (h) => h.ok && h.map?['checkoutSessionId'] != null,
      );
    }

    final forged = await c.edge(
      'create-live-tip-checkout',
      null,
      method: 'GET',
      qs: 'checkout_return=success&session_id=cs_test_aaa_forged',
    );
    c.note('bo3.tip.forged', 'GET session forjada', forged, lens: 'BO3');
    if ('${forged.body}'.contains('No such checkout')) {
      c.hold(
        id: 'bo3.tip.oracle.forged',
        lens: 'BO3',
        severity: 'P3',
        title: 'oráculo Stripe No such checkout (exacto BC — não contar)',
        actor: 'anon GET',
        pre: 'session_id forjado',
        repro: 'GET session_id=cs_test_aaa_forged',
        expected: 'mensagem genérica',
        obtained: forged.brief,
        count: false,
      );
    } else {
      c.block('bo3.tip.forged', 'BO3', 'forged sem oráculo Stripe', forged);
    }

    final rpcSettle = await c.rpc('batata_settle_live_tip_from_stripe', {
      'p_tip_id': tipId ?? '00000000-0000-0000-0000-000000000001',
      'p_stripe_session_id': csId ?? 'cs_test_fake',
      'p_paid_amount_cents': 150,
    }, jwt: c.buyerJwt);
    await c.expectDenied(
      id: 'bo4.tip.rpc.jwt',
      lens: 'BO4',
      title: 'JWT chama batata_settle_live_tip_from_stripe',
      hit: rpcSettle,
      actor: 'buyer JWT',
      pre: 'GRANT só service_role',
      repro: 'rpc batata_settle_live_tip_from_stripe',
      severityIfOpen: 'P0',
      openIf: (h) => h.ok && (h.json == true || h.map?['ok'] == true),
    );

    final tipSched = await c.edge(
      'create-live-tip-checkout',
      {
        'live_id': liveSched,
        'seller_id': c.sellerId,
        'amount_eur': 1,
      },
      jwt: c.buyerJwt,
    );
    await c.expectDenied(
      id: 'bo3.tip.sched',
      lens: 'BO3',
      title: 'tip checkout em scheduled',
      hit: tipSched,
      actor: 'buyer JWT',
      pre: 'live scheduled not broadcasting',
      repro: 'POST create-live-tip-checkout live scheduled',
      openIf: (h) => h.ok && h.map?['checkoutSessionId'] != null,
    );

    final tipEnded = await c.edge(
      'create-live-tip-checkout',
      {
        'live_id': liveEndedPub,
        'seller_id': c.sellerId,
        'amount_eur': 1,
      },
      jwt: c.buyerJwt,
    );
    await c.expectDenied(
      id: 'bo3.tip.ended',
      lens: 'BO3',
      title: 'tip checkout em ended',
      hit: tipEnded,
      actor: 'buyer JWT',
      pre: 'live ended',
      repro: 'POST create-live-tip-checkout ended',
      openIf: (h) => h.ok && h.map?['checkoutSessionId'] != null,
    );

    final tipWrongSeller = await c.edge(
      'create-live-tip-checkout',
      {
        'live_id': liveAir,
        'seller_id': c.seller2Id,
        'amount_eur': 1,
      },
      jwt: c.buyerJwt,
    );
    await c.expectDenied(
      id: 'bo4.tip.seller.mismatch',
      lens: 'BO4',
      title: 'tip seller_id alheio vs live',
      hit: tipWrongSeller,
      actor: 'buyer JWT',
      pre: 'live do seller lab, body seller_id=S2',
      repro: 'POST create-live-tip-checkout seller_id alheio',
      openIf: (h) => h.ok && h.map?['checkoutSessionId'] != null,
    );

    final tipBuyerId = await c.edge(
      'create-live-tip-checkout',
      {
        'live_id': liveAir,
        'seller_id': c.sellerId,
        'amount_eur': 1,
        'buyer_id': c.sellerId,
      },
      jwt: c.buyerJwt,
    );
    c.note('bo4.tip.buyer_id', 'body buyer_id spoof', tipBuyerId, lens: 'BO4');
    if (tipBuyerId.ok) {
      final tid = tipBuyerId.map?['tipId']?.toString();
      if (tid != null) {
        c.createdTipIds.add(tid);
        final tr = await c.tipRow(tid);
        if (tr?['buyer_id'] == c.sellerId) {
          c.hold(
            id: 'bo4.tip.buyer_id',
            lens: 'BO4',
            severity: 'P1',
            title: 'body buyer_id spoof grava tip no seller',
            actor: 'buyer JWT',
            pre: 'body buyer_id=seller',
            repro: 'POST create-live-tip-checkout buyer_id spoof',
            expected: 'buyer_id = JWT',
            obtained: '$tr',
          );
        } else {
          c.block('bo4.tip.buyer_id', 'BO4', 'buyer_id JWT ganha', tr);
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // BO5 Mux / LiveKit / resolve estados / complete cruzado
  // ---------------------------------------------------------------------------
  for (final e in views.entries) {
    final mux = await c.edge('resolve-mux-playback', {'live_id': e.value});
    c.note('bo5.resolve.${e.key}', 'resolve-mux ${e.key}', mux, lens: 'BO5');
    final serves = mux.ok &&
        (mux.body.contains('stream.mux.com') ||
            (mux.map?['playback_id'] != null &&
                '${mux.map?['playback_id']}'.isNotEmpty));
    final allowedKeys = {'air', 'ended_pub', 'air_unpub'};
    if (serves && !allowedKeys.contains(e.key)) {
      final pid = mux.map?['playback_id']?.toString() ?? '';
      HttpHit? cdn;
      if (pid.isNotEmpty) cdn = await c.muxCdn(pid);
      c.hold(
        id: 'bo5.resolve.${e.key}',
        lens: 'BO5',
        severity: (cdn != null && cdn.ok) ? 'P2' : 'P3',
        title: 'resolve-mux-playback devolve playback em estado ${e.key}',
        actor: 'anon',
        pre: 'live ${e.key}',
        repro: 'POST resolve-mux-playback live_id=${e.value}',
        expected: '404 live_not_public',
        obtained: '${mux.brief} cdn=${cdn?.brief}',
      );
    } else if (!serves) {
      c.block('bo5.resolve.${e.key}', 'BO5', 'resolve-mux ${e.key} recusado', mux);
    } else {
      c.block('bo5.resolve.${e.key}.ok', 'BO5',
          'resolve-mux ${e.key} esperado público', mux);
    }
  }

  if (liveAir != null && c.seller2Jwt != null) {
    final completeX = await c.edge(
      'complete-mux-live',
      {'live_id': liveAir},
      jwt: c.seller2Jwt,
    );
    await c.expectDenied(
      id: 'bo5.complete.s2',
      lens: 'BO5',
      title: 'Seller2 complete-mux-live da live A',
      hit: completeX,
      actor: 'seller2 JWT',
      pre: 'live A do seller lab, mux_live_id fake',
      repro: 'POST complete-mux-live live_id=A',
      severityIfOpen: 'P1',
      openIf: (h) => h.ok || h.status == 502,
    );

    final lkX = await c.edge(
      'livekit-mux-publish',
      {'step': 'token', 'live_id': liveAir},
      jwt: c.seller2Jwt,
    );
    await c.expectDenied(
      id: 'bo5.livekit.s2',
      lens: 'BO5',
      title: 'Seller2 livekit token da live A',
      hit: lkX,
      actor: 'seller2 JWT',
      pre: 'live A alheia',
      repro: 'POST livekit-mux-publish step=token',
      severityIfOpen: 'P1',
      openIf: (h) =>
          h.ok && (h.map?['token'] != null || h.map?['accessToken'] != null),
    );
  }

  if (liveAir != null) {
    final completeB = await c.edge(
      'complete-mux-live',
      {'live_id': liveAir},
      jwt: c.buyerJwt,
    );
    await c.expectDenied(
      id: 'bo5.complete.buyer',
      lens: 'BO5',
      title: 'Buyer complete-mux-live',
      hit: completeB,
      actor: 'buyer JWT',
      pre: 'não owner',
      repro: 'POST complete-mux-live',
      severityIfOpen: 'P1',
      openIf: (h) => h.ok || (h.status == 502 && h.map?['ended_marked'] == true),
    );
    final completeAnon = await c.edge('complete-mux-live', {'live_id': liveAir});
    await c.expectDenied(
      id: 'bo5.complete.anon',
      lens: 'BO5',
      title: 'Anon complete-mux-live',
      hit: completeAnon,
      actor: 'anon',
      pre: 'sem JWT user',
      repro: 'POST complete-mux-live anon',
      severityIfOpen: 'P1',
      openIf: (h) => h.ok,
    );
  }

  final createBuyer = await c.edge(
    'create-mux-live',
    {'title': 'BO hijack stream'},
    jwt: c.buyerJwt,
  );
  await c.expectDenied(
    id: 'bo5.create.buyer',
    lens: 'BO5',
    title: 'Buyer create-mux-live',
    hit: createBuyer,
    actor: 'buyer JWT',
    pre: 'user_type comprador',
    repro: 'POST create-mux-live',
    severityIfOpen: 'P1',
    openIf: (h) => h.ok && h.map?['stream_key'] != null,
  );

  // embed keys: player.mux.com with planted vod from scheduled leak
  if (liveSched != null) {
    final disc = await view('hub_lives_discovery_public', liveSched);
    final pub = await view('hub_lives_public', liveSched);
    c.note('bo5.embed.disc', 'discovery sched raw', disc, lens: 'BO5');
    c.note('bo5.embed.pub', 'hub_lives_public sched raw', pub, lens: 'BO5');
  }

  // ---------------------------------------------------------------------------
  // BO6 storage
  // ---------------------------------------------------------------------------
  final buckets = await c.req('GET', '/storage/v1/bucket');
  c.note('bo6.buckets.anon', 'list buckets anon', buckets, lens: 'BO6');
  if (buckets.ok && buckets.list.any((b) {
        if (b is! Map) return false;
        return b['public'] == true &&
            '${b['id']}'.contains(RegExp(r'private|chat|mux|live', caseSensitive: false));
      })) {
    c.hold(
      id: 'bo6.buckets.public',
      lens: 'BO6',
      severity: 'P2',
      title: 'bucket privado listado como public',
      actor: 'anon',
      pre: 'GET /storage/v1/bucket',
      repro: 'GET storage/v1/bucket',
      expected: 'sem fleaber_private/chat_media public=true',
      obtained: buckets.brief,
    );
  } else {
    c.block('bo6.buckets.anon', 'BO6', 'list buckets', buckets);
  }

  for (final path in [
    'fleaber_private/${c.sellerId}/stream_key.txt',
    'fleaber_private/${c.sellerId}/id',
    'chat_media/${c.sellerId}/x.jpg',
    'mux/${liveAir ?? "x"}/stream',
  ]) {
    final get = await c.req('GET', '/storage/v1/object/$path');
    c.note('bo6.get.$path', 'GET object', get, lens: 'BO6');
    if (get.ok && get.status == 200 && get.body.isNotEmpty) {
      c.hold(
        id: 'bo6.object',
        lens: 'BO6',
        severity: 'P1',
        title: 'anon lê objecto storage $path',
        actor: 'anon',
        pre: 'path adivinhado',
        repro: 'GET /storage/v1/object/$path',
        expected: '400/403',
        obtained: get.brief,
      );
    } else {
      c.block('bo6.get.$path', 'BO6', 'object recusado', get);
    }
  }

  final up = await c.req(
    'POST',
    '/storage/v1/object/fleaber_private/$prefix-pwn.txt',
    body: 'pwn',
    extra: {'Content-Type': 'text/plain'},
  );
  await c.expectDenied(
    id: 'bo6.upload.private',
    lens: 'BO6',
    title: 'anon upload fleaber_private',
    hit: up,
    actor: 'anon',
    pre: 'bucket privado',
    repro: 'POST storage/v1/object/fleaber_private/',
    severityIfOpen: 'P1',
    openIf: (h) => h.ok,
  );

  // ---------------------------------------------------------------------------
  // BO7 composição: JWT vod + CDN + resolve-mux + FOMO
  // ---------------------------------------------------------------------------
  if (liveSched != null) {
    final jwtVod = await c.rest(
      'GET',
      'lives?id=eq.$liveSched&select=mux_vod_playback_id,status',
      jwt: c.buyerJwt,
    );
    final vod = _vod(jwtVod);
    if (vod != null) {
      final cdn = await c.muxCdn(vod);
      final embed = await c.muxEmbed(vod);
      final edge = await c.edge('resolve-mux-playback', {'live_id': liveSched});
      c.note('bo7.comp.sched', 'JWT+CDN+embed+edge scheduled', {
        'jwt': jwtVod.brief,
        'cdn': cdn.brief,
        'embed': '${embed.status}',
        'edge': edge.brief,
      }, lens: 'BO7');
      final watches = cdn.ok && cdn.body.contains('#EXTM3U');
      if (watches && !edge.ok) {
        c.hold(
          id: 'bo7.vod.bypass.edge',
          lens: 'BO7',
          severity: 'P2',
          title:
              'assisto VOD scheduled via tabela lives+CDN sem passar no Edge/Hub view',
          actor: 'buyer JWT + CDN Mux',
          pre: 'scheduled com vod plantado; Edge resolve-mux recusa',
          repro:
              'GET lives mux_vod_playback_id; GET https://stream.mux.com/{id}.m3u8',
          expected: 'sem ID VOD fora de ended público',
          obtained:
              'jwt=${jwtVod.brief} cdn=${cdn.status} edge=${edge.brief}',
        );
      }
    }
  }

  } finally {
    await c.endAllLives();
    await c.dumpAll('pass1.json');
    stdout.writeln(
        'PASS1 done findings=${c.findings.length} blocked=${c.blocked.length}');
  }
}
