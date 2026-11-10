/// RED TEAM CEGO BU pass1 — Hub/FOMO, CORS/origin, tip unpaid, Edge, Mux, storage, composição.
import 'dart:io';
import '_rtbu.dart';

const muxCols =
    'id,status,is_active,seller_id,mux_playback_id,mux_vod_playback_id,mux_asset_id,mux_stream_key,stream_key,mux_live_id,livekit_room_name';

String? col(Map<String, dynamic>? m, String k) {
  if (m == null) return null;
  final v = m[k];
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

bool bodyHasCol(HttpHit h, String name) {
  return h.body.contains('"$name"') && !h.body.contains('"$name":null');
}

bool muxWatchable(HttpHit h) {
  final t = h.body.toLowerCase();
  return h.status == 200 &&
      (t.contains('#extm3u') || t.contains('#ext-x-'));
}

Future<void> main() async {
  final c = Rtbu.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final s1 = c.sellerId!;
  final s2 = c.seller2Id!;
  final s1p = await c.profile(s1);
  final s2p = await c.profile(s2);
  c.note('fix.s1', 'S1 profile', s1p, lens: 'BU1');
  c.note('fix.s2', 'S2 unpublished', s2p, lens: 'BU1');

  const pbLive = 'rtbuPbLive1046aaa';
  const pbVod = 'rtbuPbVod1046bbbb';
  const pbInactive = 'rtbuPbInactive1046';
  const pbSched = 'rtbuPbSched1046ccc';
  const streamKey = 'rtbuStreamKey1046secret';

  final liveAir = await c.insertLive(
    seller: s1,
    active: true,
    status: 'live',
    muxPlayback: pbLive,
    muxVod: pbVod,
    muxStreamKey: streamKey,
    muxLiveId: 'muxLiveAir1046',
    viewers: 7,
    title: '$prefix air',
  );
  final liveInactive = await c.insertLive(
    seller: s1,
    active: false,
    status: 'live',
    muxPlayback: pbInactive,
    muxVod: pbVod,
    muxStreamKey: streamKey,
    muxLiveId: 'muxLiveInact1046',
    viewers: 3,
    title: '$prefix inactive',
  );
  final liveSched = await c.insertLive(
    seller: s1,
    active: false,
    status: 'scheduled',
    muxPlayback: pbSched,
    muxVod: pbVod,
    muxStreamKey: streamKey,
    title: '$prefix sched',
  );
  final liveEndedPub = await c.insertLive(
    seller: s1,
    active: false,
    status: 'ended',
    muxPlayback: 'rtbuEndedLivePb',
    muxVod: pbVod,
    title: '$prefix ended-pub',
  );
  final liveSchedUnpub = await c.insertLive(
    seller: s2,
    active: false,
    status: 'scheduled',
    muxPlayback: 'rtbuUnpubSchedPb',
    muxVod: 'rtbuUnpubSchedVod',
    title: '$prefix unpub-sched',
  );
  final liveEndedUnpub = await c.insertLive(
    seller: s2,
    active: false,
    status: 'ended',
    muxPlayback: 'rtbuUnpubEndedPb',
    muxVod: 'rtbuUnpubEndedVod',
    title: '$prefix unpub-ended',
  );
  final liveAirUnpub = await c.insertLive(
    seller: s2,
    active: true,
    status: 'live',
    muxPlayback: 'rtbuUnpubAirPb',
    title: '$prefix unpub-air',
  );

  final itemInactive = liveInactive == null
      ? null
      : await c.insertLiveOnlyItem(liveId: liveInactive, qty: 4);
  final itemAir = liveAir == null
      ? null
      : await c.insertLiveOnlyItem(liveId: liveAir, qty: 3);
  c.note('fix.ids', 'fixtures', {
    'air': liveAir,
    'inactive': liveInactive,
    'sched': liveSched,
    'endedPub': liveEndedPub,
    'schedUnpub': liveSchedUnpub,
    'endedUnpub': liveEndedUnpub,
    'airUnpub': liveAirUnpub,
    'itemInactive': itemInactive,
    'itemAir': itemAir,
  }, lens: 'BU1');

  // ---------- BU1 Hub / FOMO ----------
  Future<void> fomo(String tag, String? id) async {
    if (id == null) return;
    final anon = await c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': id});
    final b1 = await c.rpc(
      'batata_hub_live_fomo_snapshot',
      {'p_live_id': id},
      jwt: c.buyerJwt,
    );
    c.note('bu1.fomo.anon.$tag', 'FOMO anon $tag', anon, lens: 'BU1');
    c.note('bu1.fomo.b1.$tag', 'FOMO B1 $tag', b1, lens: 'BU1');
    final m = anon.map ?? b1.map;
    final ok = m?['ok'] == true;
    final active = m?['is_active'];
    final items = m?['items'];
    final itemLen = items is List ? items.length : 0;
    if (tag == 'inactive' || tag == 'sched' || tag == 'endedUnpub') {
      if (ok && active == false && itemLen > 0) {
        c.hold(
          id: 'BU1-FOMO-$tag',
          lens: 'BU1',
          severity: 'P1',
          title: 'FOMO snapshot is_active=false devolve items/stock',
          actor: 'anon',
          pre: 'live $tag id=$id is_active=false',
          repro: 'POST /rest/v1/rpc/batata_hub_live_fomo_snapshot {"p_live_id":"$id"}',
          expected: 'ok=false live_not_public OU items=[]',
          obtained: anon.brief,
        );
      } else if (ok && active == false && itemLen == 0) {
        c.hold(
          id: 'BU1-FOMO-$tag-empty',
          lens: 'BU1',
          severity: 'P3',
          title: 'FOMO aceita live is_active=false (sem items)',
          actor: 'anon',
          pre: 'live $tag id=$id',
          repro: 'RPC batata_hub_live_fomo_snapshot',
          expected: 'live_not_public para inactiva',
          obtained: anon.brief,
        );
      } else {
        c.block('bu1.fomo.$tag', 'BU1', 'FOMO $tag recusado/vazio', anon);
      }
    }
  }

  await fomo('air', liveAir);
  await fomo('inactive', liveInactive);
  await fomo('sched', liveSched);
  await fomo('endedPub', liveEndedPub);
  await fomo('endedUnpub', liveEndedUnpub);
  await fomo('airUnpub', liveAirUnpub);

  Future<HttpHit> viewGet(String view, String? id, {String? jwt}) {
    return c.rest(
      'GET',
      '$view?id=eq.$id&select=id,status,is_active,mux_playback_id,mux_vod_playback_id,seller_handle,seller_id,title',
      jwt: jwt,
    );
  }

  for (final e in {
    'air': liveAir,
    'inactive': liveInactive,
    'sched': liveSched,
    'endedPub': liveEndedPub,
    'schedUnpub': liveSchedUnpub,
    'endedUnpub': liveEndedUnpub,
    'airUnpub': liveAirUnpub,
  }.entries) {
    final pub = await viewGet('hub_lives_public', e.value);
    final disc = await viewGet('hub_lives_discovery_public', e.value);
    c.note('bu1.pub.${e.key}', 'hub_lives_public ${e.key}', pub, lens: 'BU1');
    c.note('bu1.disc.${e.key}', 'hub_lives_discovery_public ${e.key}', disc, lens: 'BU1');
    final discPb = col(disc.map, 'mux_playback_id');
    final discVod = col(disc.map, 'mux_vod_playback_id');
    final pubPb = col(pub.map, 'mux_playback_id');
    final pubVod = col(pub.map, 'mux_vod_playback_id');
    final inactive = e.key == 'inactive' || e.key == 'sched' || e.key == 'schedUnpub';
    if (inactive && discPb != null) {
      c.hold(
        id: 'BU1-DISC-PB-${e.key}',
        lens: 'BU1',
        severity: 'P1',
        title: 'discovery expõe mux_playback_id em live inactiva (${e.key})',
        actor: 'anon',
        pre: 'live ${e.key} is_active=false',
        repro: 'GET hub_lives_discovery_public?id=eq.${e.value}&select=mux_playback_id',
        expected: 'mux_playback_id null',
        obtained: disc.brief,
      );
    } else if (inactive) {
      c.block('bu1.disc.pb.${e.key}', 'BU1', 'discovery sem mux_playback inactiva', disc);
    }
    if (e.key != 'endedPub' && discVod != null) {
      c.hold(
        id: 'BU1-DISC-VOD-${e.key}',
        lens: 'BU1',
        severity: e.key.contains('sched') ? 'P2' : 'P1',
        title: 'discovery expõe mux_vod_playback_id fora de ended publicado (${e.key})',
        actor: 'anon',
        pre: 'live ${e.key}',
        repro: 'GET hub_lives_discovery_public mux_vod_playback_id',
        expected: 'null excepto ended publicado',
        obtained: disc.brief,
        countExactClosed: e.key == 'sched',
      );
    }
    if (inactive && pubPb != null) {
      c.hold(
        id: 'BU1-PUB-PB-${e.key}',
        lens: 'BU1',
        severity: 'P1',
        title: 'hub_lives_public mux_playback_id em inactiva',
        actor: 'anon',
        pre: e.key,
        repro: 'GET hub_lives_public mux_playback_id',
        expected: 'null',
        obtained: pub.brief,
      );
    }
    if (e.key == 'schedUnpub' && disc.map != null) {
      c.hold(
        id: 'BU1-DISC-UNPUB-SCHED',
        lens: 'BU1',
        severity: 'P2',
        title: 'discovery lista scheduled de vendedor unpublished',
        actor: 'anon',
        pre: 'S2 hub_published=false scheduled live',
        repro: 'GET hub_lives_discovery_public?id=eq.$liveSchedUnpub',
        expected: '0 rows (só Hub publicado / sem montra)',
        obtained: disc.brief,
      );
    } else if (e.key == 'schedUnpub') {
      c.block('bu1.disc.unpub.sched', 'BU1', 'discovery omite scheduled unpublished', disc);
    }
    if (e.key == 'airUnpub' && (discPb != null || pubPb != null)) {
      c.hold(
        id: 'BU1-UNPUB-AIR-PB',
        lens: 'BU1',
        severity: 'P1',
        title: 'mux_playback_id de directo unpublished visível na view pública',
        actor: 'anon',
        pre: 'S2 hub_published=false status=live is_active=true',
        repro: 'GET hub_lives_discovery_public / hub_lives_public',
        expected: 'sem row ou mux_playback_id null',
        obtained: 'pub=${pub.brief} disc=${disc.brief}',
      );
    }
    if (e.key == 'inactive' && (pub.map != null || disc.map != null)) {
      c.hold(
        id: 'BU1-INACTIVE-IN-HUB',
        lens: 'BU1',
        severity: 'P2',
        title: 'live status=live is_active=false aparece em view Hub',
        actor: 'anon',
        pre: 'inactive live',
        repro: 'GET hub_lives_public / discovery',
        expected: '0 rows (live exige is_active)',
        obtained: 'pub=${pub.brief} disc=${disc.brief}',
      );
    } else if (e.key == 'inactive') {
      c.block('bu1.inactive.hub', 'BU1', 'views omitem live inactiva', pub);
    }
  }

  final itemsAnonInactive = await c.rest(
    'GET',
    'hub_live_items_public?live_id=eq.$liveInactive&select=id,title,price,is_active',
  );
  c.note('bu1.items.inactive', 'hub items inactive', itemsAnonInactive, lens: 'BU1');
  if (itemsAnonInactive.list.isNotEmpty) {
    c.hold(
      id: 'BU1-ITEMS-INACTIVE',
      lens: 'BU1',
      severity: 'P1',
      title: 'hub_live_items_public lista artigos de live is_active=false',
      actor: 'anon',
      pre: 'item em live inactive',
      repro: 'GET hub_live_items_public?live_id=eq.$liveInactive',
      expected: '[] (200 vazio)',
      obtained: itemsAnonInactive.brief,
    );
  } else {
    c.block('bu1.items.inactive', 'BU1', 'items Hub omitidos em live inactiva',
        itemsAnonInactive);
  }

  // ---------- BU5 Mux via REST + embed + CDN ----------
  Future<void> livesSelect(String tag, String? id, {String? jwt, required String actor}) async {
    if (id == null) return;
    final h = await c.rest('GET', 'lives?id=eq.$id&select=$muxCols', jwt: jwt);
    c.note('bu5.lives.$actor.$tag', 'GET lives $actor $tag', h, lens: 'BU5');
    final pb = col(h.map, 'mux_playback_id');
    final vod = col(h.map, 'mux_vod_playback_id');
    final sk = col(h.map, 'mux_stream_key') ?? col(h.map, 'stream_key');
    final inactive = tag == 'inactive' || tag == 'sched' || tag == 'schedUnpub';
    if (sk != null) {
      c.hold(
        id: 'BU5-STREAMKEY-$actor-$tag',
        lens: 'BU5',
        severity: 'P0',
        title: 'stream_key Mux lido por $actor em $tag',
        actor: actor,
        pre: 'coluna mux_stream_key/stream_key',
        repro: 'GET /rest/v1/lives?id=eq.$id&select=mux_stream_key,stream_key',
        expected: 'coluna recusada / null',
        obtained: h.brief,
      );
    }
    if (actor == 'anon' && (pb != null || vod != null)) {
      c.hold(
        id: 'BU5-ANON-MUX-$tag',
        lens: 'BU5',
        severity: 'P1',
        title: 'anon lê mux_playback/vod em lives ($tag)',
        actor: 'anon',
        pre: 'REVOKE mux cols from anon (BLBQ exact — contar só se ainda aberto)',
        repro: 'GET lives?select=mux_playback_id,mux_vod_playback_id',
        expected: 'sem colunas Mux',
        obtained: h.brief,
        countExactClosed: true,
      );
    }
    if (actor == 'B1' && inactive && pb != null) {
      c.hold(
        id: 'BU5-B1-INACTIVE-PB-$tag',
        lens: 'BU5',
        severity: 'P1',
        title: 'buyer JWT lê mux_playback_id de live inactiva via REST lives',
        actor: 'B1',
        pre: 'live $tag is_active=false; Hub view anula playback',
        repro: 'GET /rest/v1/lives?id=eq.$id&select=mux_playback_id (JWT buyer)',
        expected: 'null / coluna recusada para não-dono',
        obtained: h.brief,
      );
    } else if (actor == 'B1' && inactive && pb == null) {
      c.block('bu5.b1.pb.$tag', 'BU5', 'B1 sem mux_playback inactiva', h);
    }
    if (actor == 'B1' && tag != 'endedPub' && tag != 'air' && vod != null && inactive) {
      c.hold(
        id: 'BU5-B1-INACTIVE-VOD-$tag',
        lens: 'BU5',
        severity: 'P1',
        title: 'buyer JWT lê mux_vod_playback_id de live inactiva',
        actor: 'B1',
        pre: 'Hub anula VOD fora de ended',
        repro: 'GET lives mux_vod_playback_id JWT B1',
        expected: 'null',
        obtained: h.brief,
      );
    }
  }

  for (final e in {
    'air': liveAir,
    'inactive': liveInactive,
    'sched': liveSched,
    'endedPub': liveEndedPub,
    'schedUnpub': liveSchedUnpub,
    'endedUnpub': liveEndedUnpub,
  }.entries) {
    await livesSelect(e.key, e.value, actor: 'anon');
    await livesSelect(e.key, e.value, jwt: c.buyerJwt, actor: 'B1');
    await livesSelect(e.key, e.value, jwt: c.buyer2Jwt, actor: 'B2');
  }

  // Embed lives(*) noutro REST
  for (final parent in [
    'live_items',
    'live_tips',
    'live_messages',
    'live_reservation_requests',
    'orders',
    'live_raffles',
  ]) {
    final q =
        '$parent?select=id,live_id,lives($muxCols)&live_id=eq.$liveInactive&limit=3';
    final anon = await c.rest('GET', q);
    final b1 = await c.rest('GET', q, jwt: c.buyerJwt);
    c.note('bu5.embed.anon.$parent', 'embed lives(*) $parent anon', anon, lens: 'BU5');
    c.note('bu5.embed.b1.$parent', 'embed lives(*) $parent B1', b1, lens: 'BU5');
    for (final hit in [anon, b1]) {
      final nested = hit.map?['lives'];
      Map<String, dynamic>? nest;
      if (nested is Map) nest = Map<String, dynamic>.from(nested);
      final pb = col(nest, 'mux_playback_id');
      final vod = col(nest, 'mux_vod_playback_id');
      final sk = col(nest, 'mux_stream_key');
      if (pb != null || vod != null || sk != null) {
        c.hold(
          id: 'BU5-EMBED-$parent',
          lens: 'BU5',
          severity: sk != null ? 'P0' : 'P1',
          title: 'embed $parent.lives(*) vaza Mux de live inactiva',
          actor: hit == anon ? 'anon' : 'B1',
          pre: 'live inactive $liveInactive',
          repro: 'GET /rest/v1/$q',
          expected: 'sem nested mux ids / 400 embed recusado',
          obtained: hit.brief,
        );
      }
    }
  }

  // Real Mux IDs already in staging (CDN)
  final real = await c.rest(
    'GET',
    'lives?mux_playback_id=not.is.null&select=id,status,is_active,mux_playback_id,mux_vod_playback_id&limit=8',
    service: true,
  );
  c.note('bu5.real.mux', 'lives with mux ids (svc obs)', '${real.list.length}',
      lens: 'BU5');
  for (final row in real.list.take(5)) {
    if (row is! Map) continue;
    final m = Map<String, dynamic>.from(row);
    final id = '${m['id']}';
    final st = '${m['status']}';
    final active = m['is_active'] == true;
    final pb = col(m, 'mux_playback_id');
    final vod = col(m, 'mux_vod_playback_id');
    final b1 = await c.rest(
      'GET',
      'lives?id=eq.$id&select=id,status,is_active,mux_playback_id,mux_vod_playback_id',
      jwt: c.buyerJwt,
    );
    final anon = await c.rest(
      'GET',
      'lives?id=eq.$id&select=id,status,is_active,mux_playback_id,mux_vod_playback_id',
    );
    c.note('bu5.real.b1.$id', 'B1 real live', b1, lens: 'BU5');
    final b1pb = col(b1.map, 'mux_playback_id');
    final b1vod = col(b1.map, 'mux_vod_playback_id');
    if (!active && st.toLowerCase() != 'ended' && b1pb != null && pb != null) {
      final cdn = await c.rawGet('https://stream.mux.com/$b1pb.m3u8');
      c.note('bu5.cdn.inactive.$id', 'CDN HLS inactive', cdn.brief, lens: 'BU5');
      if (muxWatchable(cdn) || cdn.status == 200) {
        c.hold(
          id: 'BU5-CDN-INACTIVE-$id',
          lens: 'BU5',
          severity: 'P1',
          title: 'assisto HLS Mux de live inactiva sem Edge (playback lido por B1)',
          actor: 'B1 + CDN Mux',
          pre: 'status=$st is_active=$active',
          repro:
              'GET lives mux_playback_id JWT B1; GET https://stream.mux.com/{id}.m3u8',
          expected: 'sem playback id; CDN 403/404',
          obtained: 'rest=${b1.brief} cdn=${cdn.brief}',
          evidence: {'playback_id': b1pb, 'cdn_status': cdn.status},
        );
      } else {
        c.note('bu5.cdn.nohls.$id', 'CDN não serve (id fixture/expirado)', cdn.brief,
            lens: 'BU5');
      }
    }
    if (anon.map != null &&
        (col(anon.map, 'mux_playback_id') != null ||
            col(anon.map, 'mux_vod_playback_id') != null)) {
      c.hold(
        id: 'BU5-ANON-REAL-$id',
        lens: 'BU5',
        severity: 'P1',
        title: 'anon lê Mux cols em live real',
        actor: 'anon',
        pre: 'BLBQ exact GET lives mux_vod — só contar se aberto',
        repro: 'GET lives mux cols anon',
        expected: 'sem colunas',
        obtained: anon.brief,
        countExactClosed: true,
      );
    }
    if (b1vod != null && !active && st.toLowerCase() != 'ended') {
      final cdnV = await c.rawGet('https://stream.mux.com/$b1vod.m3u8');
      c.note('bu5.cdn.vodprem.$id', 'CDN VOD prematuro', cdnV.brief, lens: 'BU5');
      if (muxWatchable(cdnV) || cdnV.status == 200) {
        c.hold(
          id: 'BU5-VOD-PREMATURE-$id',
          lens: 'BU5',
          severity: 'P1',
          title: 'VOD Mux assistível antes de ended (sem Edge)',
          actor: 'B1 + CDN',
          pre: 'status=$st is_active=$active',
          repro: 'GET mux_vod_playback_id; GET stream.mux.com/{vod}.m3u8',
          expected: 'VOD só ended público',
          obtained: cdnV.brief,
        );
      }
    }
  }

  // resolve-mux-playback on inactive / scheduled
  for (final e in {
    'inactive': liveInactive,
    'sched': liveSched,
    'air': liveAir,
    'endedUnpub': liveEndedUnpub,
    'endedPub': liveEndedPub,
  }.entries) {
    final r = await c.edge('resolve-mux-playback', body: {'live_id': e.value});
    c.note('bu5.resolve.${e.key}', 'resolve-mux ${e.key}', r, lens: 'BU5');
    final pid = r.map?['playback_id']?.toString();
    if ((e.key == 'inactive' || e.key == 'sched' || e.key == 'endedUnpub') &&
        pid != null &&
        pid.isNotEmpty) {
      c.hold(
        id: 'BU5-RESOLVE-${e.key}',
        lens: 'BU5',
        severity: 'P1',
        title: 'resolve-mux-playback devolve playback em ${e.key}',
        actor: 'anon',
        pre: 'live ${e.key}',
        repro: 'POST resolve-mux-playback {"live_id":"${e.value}"}',
        expected: '404 live_not_public',
        obtained: r.brief,
      );
    } else if (e.key == 'inactive' || e.key == 'sched' || e.key == 'endedUnpub') {
      c.block('bu5.resolve.${e.key}', 'BU5', 'resolve recusa ${e.key}', r);
    }
  }

  // ---------- BU2 CORS + web_return IPv6 / nip.io ----------
  final origins = <String, String>{
    'ipv6mapped': 'https://[::ffff:127.0.0.1]',
    'ipv6mapped_http': 'http://[::ffff:127.0.0.1]',
    'ipv6loop': 'https://[::1]',
    'nip': 'https://127.0.0.1.nip.io',
    'nip_http': 'http://127.0.0.1.nip.io',
    'sslip': 'https://127.0.0.1.sslip.io',
    'localtest': 'https://localtest.me',
    'lvh': 'https://lvh.me',
    'decimal': 'https://2130706433',
    'evil': 'https://evil.example',
    'sub': 'https://attacker.fleaber.pt',
    'userinfo': 'https://evil.com@fleaber.pt',
    'localhost': 'http://localhost:5173',
    'allowed': 'https://fleaber.pt',
  };
  for (final e in origins.entries) {
    final qs =
        'web_return_origin=${Uri.encodeQueryComponent(e.value)}';
    final get = await c.edge('create-connect-account', method: 'GET', qs: qs);
    c.note('bu2.wr.get.${e.key}', 'GET web_return ${e.value}', get, lens: 'BU2');
    final loc = get.location ?? '';
    final hostile = loc.isNotEmpty &&
        !loc.startsWith('https://fleaber.pt') &&
        !loc.startsWith('https://www.fleaber.pt') &&
        !loc.startsWith('https://fleaber.app') &&
        !loc.startsWith('https://www.fleaber.app') &&
        !loc.startsWith('http://localhost') &&
        !loc.startsWith('http://127.0.0.1') &&
        !loc.startsWith('fleaber://') &&
        !loc.startsWith('intent://');
    final loopbackCollapse = loc.contains('127.0.0.1') ||
        loc.contains('localhost') ||
        loc.contains('[::1]') ||
        loc.contains('0.0.0.0');
    final exactDecimal = e.key == 'decimal';
    if (get.status == 303 && (hostile || (loopbackCollapse && e.key != 'localhost'))) {
      c.hold(
        id: 'BU2-WR-${e.key}',
        lens: 'BU2',
        severity: 'P1',
        title: 'web_return 303 para origem hostil (${e.key})',
        actor: 'anon GET',
        pre: 'sanitizeWebReturnOrigin',
        repro: 'GET create-connect-account?web_return_origin=${e.value}',
        expected: 'sem 303 para host não allowlist (HTML/intent wallet)',
        obtained: get.brief,
        countExactClosed: exactDecimal,
      );
    } else {
      c.block('bu2.wr.${e.key}', 'BU2', 'web_return recusado/seguro ${e.key}', get);
    }

    final opt = await c.req(
      'OPTIONS',
      '/functions/v1/create-connect-account',
      extra: {
        'Origin': e.value,
        'Access-Control-Request-Method': 'POST',
        'Access-Control-Request-Headers': 'authorization,content-type,apikey',
      },
      auth: true,
    );
    c.note('bu2.cors.opt.${e.key}', 'OPTIONS Origin=${e.value}', opt, lens: 'BU2');
    final acao = opt.acao ?? '';
    final reflected = acao == e.value &&
        e.key != 'allowed' &&
        e.key != 'localhost';
    if (reflected) {
      c.hold(
        id: 'BU2-CORS-${e.key}',
        lens: 'BU2',
        severity: 'P1',
        title: 'CORS reflecte Origin hostil (${e.key})',
        actor: 'browser Origin',
        pre: 'buildCorsHeaders',
        repro: 'OPTIONS Origin=${e.value} create-connect-account',
        expected: 'ACAO fleaber.pt ou omitido — nunca o Origin hostil',
        obtained: opt.brief,
      );
    } else {
      c.block('bu2.cors.${e.key}', 'BU2', 'CORS não reflecte ${e.key}', opt);
    }

    final postMux = await c.edge(
      'resolve-mux-playback',
      body: {'live_id': liveAir},
      extra: {'Origin': e.value},
    );
    if ((postMux.acao ?? '') == e.value &&
        e.key != 'allowed' &&
        e.key != 'localhost') {
      c.hold(
        id: 'BU2-CORS-POST-${e.key}',
        lens: 'BU2',
        severity: 'P2',
        title: 'POST resolve-mux ACAO=Origin hostil',
        actor: 'anon',
        pre: e.value,
        repro: 'POST resolve-mux-playback Origin=${e.value}',
        expected: 'ACAO https://fleaber.pt',
        obtained: postMux.brief,
      );
    }
  }

  // POST body web_return on tip + connect
  final wrBody = await c.edge(
    'create-connect-account',
    jwt: c.sellerJwt,
    body: {
      'action': 'onboarding',
      'web_return_origin': 'https://[::ffff:127.0.0.1]',
    },
  );
  c.note('bu2.wr.post.ipv6', 'POST connect ipv6 mapped', wrBody, lens: 'BU2');

  // ---------- BU4 / BU5 complete-mux + livekit cruzado ----------
  final xComplete = await c.edge(
    'complete-mux-live',
    jwt: c.buyer2Jwt,
    body: {'live_id': liveAir},
  );
  c.note('bu4.complete.b2', 'complete-mux B2 vs S1 live', xComplete, lens: 'BU4');
  if (xComplete.ok || xComplete.status == 200) {
    c.hold(
      id: 'BU4-COMPLETE-CROSS',
      lens: 'BU4',
      severity: 'P0',
      title: 'B2 completa Mux de live S1',
      actor: 'B2',
      pre: 'live S1 $liveAir',
      repro: 'POST complete-mux-live {"live_id":"$liveAir"} JWT B2',
      expected: '403 Sem permissão',
      obtained: xComplete.brief,
    );
  } else {
    c.block('bu4.complete.b2', 'BU4', 'complete-mux cruzado recusado', xComplete);
  }

  final xLk = await c.edge(
    'livekit-mux-publish',
    jwt: c.buyer2Jwt,
    body: {'step': 'token', 'live_id': liveAir},
  );
  c.note('bu4.lk.b2', 'livekit token B2 vs S1', xLk, lens: 'BU4');
  if (xLk.ok && (xLk.map?['token'] != null)) {
    c.hold(
      id: 'BU4-LIVEKIT-TOKEN-CROSS',
      lens: 'BU4',
      severity: 'P0',
      title: 'B2 obtém token LiveKit da live S1',
      actor: 'B2',
      pre: liveAir ?? '',
      repro: 'POST livekit-mux-publish step=token live_id S1 JWT B2',
      expected: '403',
      obtained: xLk.brief,
    );
  } else {
    c.block('bu4.lk.b2', 'BU4', 'livekit token cruzado recusado', xLk);
  }

  final xEgress = await c.edge(
    'livekit-mux-publish',
    jwt: c.buyer2Jwt,
    body: {
      'step': 'egress',
      'live_id': liveAir,
      'stream_key': 'stolen',
    },
  );
  c.note('bu4.egress.b2', 'egress cruzado', xEgress, lens: 'BU4');
  if (xEgress.ok) {
    c.hold(
      id: 'BU4-EGRESS-CROSS',
      lens: 'BU4',
      severity: 'P0',
      title: 'B2 inicia egress Mux de live S1',
      actor: 'B2',
      pre: liveAir ?? '',
      repro: 'POST livekit-mux-publish step=egress',
      expected: '403',
      obtained: xEgress.brief,
    );
  } else {
    c.block('bu4.egress.b2', 'BU4', 'egress cruzado recusado', xEgress);
  }

  final buyerMux = await c.edge(
    'create-mux-live',
    jwt: c.buyerJwt,
    body: {'title': '$prefix buyer mux'},
  );
  c.note('bu4.create.buyer', 'create-mux as buyer', buyerMux, lens: 'BU4');
  if (buyerMux.ok) {
    c.hold(
      id: 'BU4-CREATE-MUX-BUYER',
      lens: 'BU4',
      severity: 'P1',
      title: 'comprador cria stream Mux',
      actor: 'B1',
      pre: 'user_type comprador',
      repro: 'POST create-mux-live JWT buyer',
      expected: '403 só vendedor',
      obtained: buyerMux.brief,
    );
  } else {
    c.block('bu4.create.buyer', 'BU4', 'buyer não cria Mux', buyerMux);
  }

  final cleanup = await c.edge(
    'livekit-egress-cleanup',
    body: {},
    extra: {'x-cleanup-secret': 'wrong', 'Origin': 'https://evil.example'},
  );
  c.note('bu4.cleanup', 'egress-cleanup secret errado', cleanup, lens: 'BU4');
  if (cleanup.ok) {
    c.hold(
      id: 'BU4-CLEANUP-UNAUTH',
      lens: 'BU4',
      severity: 'P1',
      title: 'livekit-egress-cleanup aceita sem segredo',
      actor: 'anon',
      pre: 'x-cleanup-secret=wrong',
      repro: 'POST livekit-egress-cleanup',
      expected: '401',
      obtained: cleanup.brief,
    );
  } else {
    c.block('bu4.cleanup', 'BU4', 'cleanup sem segredo recusado', cleanup);
  }

  // ---------- BU3 tip unpaid B2 ----------
  final balSBefore = await c.walletBal(s1);
  final balB1Before = await c.walletBal(c.buyerId);
  final tipCreate = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveAir,
      'seller_id': s1,
      'amount_eur': 2,
      'message': '$prefix tip',
      'web_return_origin': 'https://127.0.0.1.nip.io',
      'tip_id': '00000000-0000-0000-0000-000000000001',
    },
  );
  c.note('bu3.tip.create.tipid', 'tip com tip_id cliente', tipCreate, lens: 'BU3');
  if (tipCreate.ok) {
    c.hold(
      id: 'BU3-CLIENT-TIP-ID',
      lens: 'BU3',
      severity: 'P1',
      title: 'Edge aceita tip_id do cliente',
      actor: 'B1',
      pre: 'body.tip_id forjado',
      repro: 'POST create-live-tip-checkout tip_id=uuid',
      expected: 'erro Client tip_id is not allowed',
      obtained: tipCreate.brief,
    );
  } else {
    c.block('bu3.tip.tipid', 'BU3', 'tip_id cliente recusado', tipCreate);
  }

  final tipOk = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveAir,
      'seller_id': s1,
      'amount_eur': 2,
      'message': '$prefix tip-ok',
      'web_return_origin': 'https://[::ffff:127.0.0.1]',
    },
  );
  c.note('bu3.tip.create', 'tip checkout unpaid', tipOk, lens: 'BU3');
  final cs = tipOk.map?['checkoutSessionId']?.toString();
  final tipId = tipOk.map?['tipId']?.toString();
  if (tipId != null) c.createdTipIds.add(tipId);

  if (cs != null && cs.isNotEmpty) {
    final settleB2 = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs:
          'checkout_return=success&session_id=${Uri.encodeQueryComponent(cs)}',
      jwt: c.buyer2Jwt,
    );
    c.note('bu3.settle.b2', 'GET settle unpaid B2', settleB2, lens: 'BU3');
    final settleAnon = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs:
          'checkout_return=success&session_id=${Uri.encodeQueryComponent(cs)}',
    );
    c.note('bu3.settle.anon', 'GET settle unpaid anon', settleAnon, lens: 'BU3');
  } else {
    c.skip('bu3.settle.no-cs', 'BU3', 'sem Checkout Session (tip create falhou?)',
        tipOk);
  }

  if (tipId != null) {
    final rpcB2 = await c.rpc(
      'batata_settle_live_tip_from_stripe',
      {
        'p_tip_id': tipId,
        'p_stripe_session_id': cs ?? 'cs_test_forged',
        'p_paid_amount_cents': 200,
      },
      jwt: c.buyer2Jwt,
    );
    c.note('bu3.rpc.b2', 'RPC settle B2 unpaid', rpcB2, lens: 'BU3');
    final rpcB1 = await c.rpc(
      'batata_settle_live_tip_from_stripe',
      {
        'p_tip_id': tipId,
        'p_stripe_session_id': cs ?? 'cs_test_forged',
        'p_paid_amount_cents': 200,
      },
      jwt: c.buyerJwt,
    );
    c.note('bu3.rpc.b1', 'RPC settle B1 unpaid', rpcB1, lens: 'BU3');
    final rpcAnon = await c.rpc(
      'batata_settle_live_tip_from_stripe',
      {
        'p_tip_id': tipId,
        'p_stripe_session_id': cs ?? 'cs_test_forged',
        'p_paid_amount_cents': 200,
      },
    );
    c.note('bu3.rpc.anon', 'RPC settle anon', rpcAnon, lens: 'BU3');

    final tipRow = await c.rest(
      'GET',
      'live_tips?id=eq.$tipId&select=id,status,amount,buyer_id,seller_id,stripe_session_id',
      service: true,
    );
    c.note('bu3.tip.row', 'tip row após settle unpaid', tipRow, lens: 'BU3');
    final st = '${tipRow.map?['status'] ?? ''}';
    final balSAfter = await c.walletBal(s1);
    final balB1After = await c.walletBal(c.buyerId);
    c.note('bu3.wallet', 'Δ wallets unpaid', {
      'seller_before': balSBefore,
      'seller_after': balSAfter,
      'buyer_before': balB1Before,
      'buyer_after': balB1After,
    }, lens: 'BU3');
    if (st.toLowerCase() == 'completed' || balSAfter > balSBefore) {
      c.hold(
        id: 'BU3-TIP-UNPAID-SETTLE',
        lens: 'BU3',
        severity: 'P0',
        title: 'gorjeta settled/creditada sem pagamento Stripe',
        actor: 'B2/B1 JWT ou GET return',
        pre: 'Checkout Session criada, NÃO paga',
        repro:
            'GET create-live-tip-checkout?checkout_return=success&session_id=cs_… JWT B2; RPC batata_settle_live_tip_from_stripe',
        expected: 'status=pending; Δwallet=0',
        obtained:
            'status=$st seller $balSBefore→$balSAfter tip=${tipRow.brief}',
      );
    } else {
      c.block(
        'bu3.unpaid',
        'BU3',
        'unpaid não settled Δwallet=0',
        'status=$st Δs=${balSAfter - balSBefore}',
      );
    }
  }

  final tipWrongSeller = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveAir,
      'seller_id': s2,
      'amount_eur': 2,
    },
  );
  c.note('bu3.tip.wrong-seller', 'tip seller ≠ owner', tipWrongSeller, lens: 'BU3');
  if (tipWrongSeller.ok) {
    c.hold(
      id: 'BU3-TIP-SELLER-SWAP',
      lens: 'BU3',
      severity: 'P0',
      title: 'tip Checkout para seller que não é dono da live',
      actor: 'B1',
      pre: 'live S1, seller_id=S2',
      repro: 'POST create-live-tip-checkout seller_id=S2 live_id=S1',
      expected: 'erro Tip seller does not own this live',
      obtained: tipWrongSeller.brief,
    );
  } else {
    c.block('bu3.seller.swap', 'BU3', 'seller swap recusado', tipWrongSeller);
  }

  final tipInactive = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveInactive,
      'seller_id': s1,
      'amount_eur': 2,
    },
  );
  c.note('bu3.tip.inactive', 'tip em live inactiva', tipInactive, lens: 'BU3');
  if (tipInactive.ok) {
    c.hold(
      id: 'BU3-TIP-INACTIVE',
      lens: 'BU3',
      severity: 'P1',
      title: 'tip Checkout em live is_active=false',
      actor: 'B1',
      pre: 'live inactive',
      repro: 'POST create-live-tip-checkout live_id inactiva',
      expected: 'Tips only allowed while broadcasting',
      obtained: tipInactive.brief,
    );
  } else {
    c.block('bu3.tip.inactive', 'BU3', 'tip inactiva recusado', tipInactive);
  }

  // ---------- BU6 storage ----------
  final buckets = await c.req('GET', '/storage/v1/bucket');
  c.note('bu6.buckets.anon', 'list buckets anon', buckets, lens: 'BU6');
  final bucketsB1 = await c.req('GET', '/storage/v1/bucket', jwt: c.buyerJwt);
  c.note('bu6.buckets.b1', 'list buckets B1', bucketsB1, lens: 'BU6');
  final bucketsSvc = await c.req('GET', '/storage/v1/bucket', service: true);
  c.note('bu6.buckets.svc', 'list buckets svc (obs)', '${bucketsSvc.list.length} buckets',
      lens: 'BU6');

  final publicNames = <String>[];
  for (final row in bucketsSvc.list) {
    if (row is! Map) continue;
    final name = '${row['name'] ?? row['id'] ?? ''}';
    final isPub = row['public'] == true;
    if (isPub) publicNames.add(name);
  }
  c.note('bu6.public.names', 'buckets public=true', publicNames, lens: 'BU6');

  for (final b in [
    'fleaber_private',
    'chat_media',
    'product_images',
    'avatars',
    'hub_media',
    ...publicNames,
  ]) {
    final listed = await c.req(
      'POST',
      '/storage/v1/object/list/$b',
      jwt: c.buyerJwt,
      body: {'prefix': '', 'limit': 5},
    );
    c.note('bu6.list.$b', 'list $b B1', listed, lens: 'BU6');
    final pubGet = await c.req(
      'GET',
      '/storage/v1/object/public/$b/rtbu-does-not-exist.png',
      auth: true,
    );
    c.note('bu6.publicget.$b', 'GET public $b missing', pubGet, lens: 'BU6');
    if (b == 'fleaber_private' && (listed.ok && listed.list.isNotEmpty)) {
      c.hold(
        id: 'BU6-PRIVATE-LIST',
        lens: 'BU6',
        severity: 'P1',
        title: 'B1 lista objectos fleaber_private',
        actor: 'B1',
        pre: 'bucket private',
        repro: 'POST /storage/v1/object/list/fleaber_private',
        expected: '[] / 400 / 403',
        obtained: listed.brief,
      );
    }
  }

  // Upload anon to public bucket
  for (final b in publicNames.take(4)) {
    final up = await c.req(
      'POST',
      '/storage/v1/object/$b/rtbu/$prefix.txt',
      extra: {'Content-Type': 'text/plain', 'x-upsert': 'true'},
      body: 'rtbu-public-write',
    );
    c.note('bu6.upload.anon.$b', 'anon upload $b', up, lens: 'BU6');
    if (up.ok) {
      c.hold(
        id: 'BU6-ANON-WRITE-$b',
        lens: 'BU6',
        severity: 'P2',
        title: 'anon escreve em bucket público $b',
        actor: 'anon',
        pre: 'public=$b',
        repro: 'POST /storage/v1/object/$b/rtbu/...',
        expected: '401/403',
        obtained: up.brief,
      );
    }
  }

  // fleaber_private public URL
  final privPub = await c.req(
    'GET',
    '/storage/v1/object/public/fleaber_private/order_proofs/x.png',
  );
  c.note('bu6.private.public-url', 'public URL fleaber_private', privPub, lens: 'BU6');
  if (privPub.status == 200) {
    c.hold(
      id: 'BU6-PRIVATE-VIA-PUBLIC',
      lens: 'BU6',
      severity: 'P1',
      title: 'object/public serve fleaber_private',
      actor: 'anon',
      pre: 'bucket public=false',
      repro: 'GET /storage/v1/object/public/fleaber_private/...',
      expected: '400/404',
      obtained: privPub.brief,
    );
  } else {
    c.block('bu6.private.public', 'BU6', 'public URL não serve private', privPub);
  }

  // ---------- cleanup (end lives only; no code fixes) ----------
  await c.endLives();

  final counted = c.findings
      .where((f) => f['count_exact_closed'] != true && f['proven'] == true)
      .toList();
  final out = {
    'auditor': 'REDTEAM_BLIND_BU_HUB_EDGE_POS_BLBQ_v1',
    'stamp': stamp,
    'prefix': prefix,
    'lenses': c.lensesHit.toList()..sort(),
    'findings_all': c.findings,
    'findings_countable': counted,
    'blocked': c.blocked,
    'skipped': c.skipped,
    'notes': c.notes,
    'created_lives': c.createdLiveIds,
  };
  await dumpJson('${outDir()}/pass1.json', out);
  stdout.writeln(
      'DONE findings=${c.findings.length} countable=${counted.length} blocked=${c.blocked.length}');
}
