/// RED TEAM CEGO CA pass1 — Hub/FOMO, REST lives cols, dono JWT vs anon, embed, resolve-mux.
import 'dart:io';
import '_rtca.dart';

const muxCols =
    'id,status,is_active,seller_id,title,mux_playback_id,mux_vod_playback_id,mux_asset_id,mux_stream_key,stream_key,mux_live_id,playback_id,livekit_room_name';
const safeCols = 'id,status,is_active,seller_id,title,viewer_count';

Future<void> main() async {
  final c = Rtca.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final s1 = c.sellerId!;
  final s2 = c.seller2Id!;
  final s1p = await c.profile(s1);
  final s2p = await c.profile(s2);
  c.note('fix.s1', 'S1 profile', s1p, lens: 'CA1');
  c.note('fix.s2', 'S2 unpublished', s2p, lens: 'CA1');

  if (s1p?['hub_published'] != true) {
    await c.rest('PATCH', 'profiles?id=eq.$s1', service: true, body: {
      'hub_published': true,
    }, prefer: 'return=minimal');
    c.note('fix.s1.publish', 'S1 lab marked hub_published for contrast', true,
        lens: 'CA1');
  }

  // Steal a real Mux playback id from staging (service observe only) for CDN proof.
  String? realPb;
  String? realVod;
  final real = await c.rest(
    'GET',
    'lives?mux_playback_id=not.is.null&select=id,mux_playback_id,mux_vod_playback_id,status&limit=8',
    service: true,
  );
  for (final row in real.list) {
    if (row is Map) {
      final pb = '${row['mux_playback_id'] ?? ''}'.trim();
      final vod = '${row['mux_vod_playback_id'] ?? ''}'.trim();
      if (realPb == null && pb.length > 8 && !pb.startsWith('rtca')) {
        realPb = pb;
      }
      if (realVod == null && vod.length > 8 && !vod.startsWith('rtca')) {
        realVod = vod;
      }
    }
  }
  c.note('fix.realmux', 'copied real mux ids present', {
    'has_pb': realPb != null,
    'has_vod': realVod != null,
    'pb_len': realPb?.length,
    'vod_len': realVod?.length,
  }, lens: 'CA5');

  const fakePb = 'rtcaPbLive1137aaaa';
  const fakeVod = 'rtcaPbVod1137bbbb';
  const fakeStream = 'rtcaStreamKey1137secret';
  final pbAir = realPb ?? fakePb;
  final vodEnded = realVod ?? fakeVod;

  final liveAirPub = await c.insertLive(
    seller: s1,
    active: true,
    status: 'live',
    muxPlayback: pbAir,
    muxVod: fakeVod,
    muxStreamKey: fakeStream,
    muxLiveId: 'muxLiveAir1137',
    viewers: 4,
    title: '$prefix air-pub',
  );
  final liveAirUnpub = await c.insertLive(
    seller: s2,
    active: true,
    status: 'live',
    muxPlayback: pbAir,
    muxVod: fakeVod,
    muxStreamKey: fakeStream,
    muxLiveId: 'muxLiveUnpubAir1137',
    viewers: 2,
    title: '$prefix air-unpub',
  );
  final liveSchedUnpub = await c.insertLive(
    seller: s2,
    active: false,
    status: 'scheduled',
    muxPlayback: pbAir,
    muxVod: fakeVod,
    muxStreamKey: fakeStream,
    muxLiveId: 'muxLiveUnpubSched1137',
    title: '$prefix sched-unpub',
  );
  final liveEndedUnpub = await c.insertLive(
    seller: s2,
    active: false,
    status: 'ended',
    muxPlayback: 'rtcaEndedLivePb',
    muxVod: vodEnded,
    muxAssetId: 'assetUnpub1137',
    title: '$prefix ended-unpub',
  );
  final liveEndedPub = await c.insertLive(
    seller: s1,
    active: false,
    status: 'ended',
    muxPlayback: 'rtcaEndedPubPb',
    muxVod: vodEnded,
    title: '$prefix ended-pub',
  );
  final liveInactivePub = await c.insertLive(
    seller: s1,
    active: false,
    status: 'live',
    muxPlayback: 'rtcaInactivePb',
    muxVod: fakeVod,
    title: '$prefix inactive-pub',
  );
  final liveSchedPub = await c.insertLive(
    seller: s1,
    active: false,
    status: 'scheduled',
    muxPlayback: pbAir,
    title: '$prefix sched-pub',
  );

  c.note('fix.ids', 'fixture lives', {
    'airPub': liveAirPub,
    'airUnpub': liveAirUnpub,
    'schedUnpub': liveSchedUnpub,
    'endedUnpub': liveEndedUnpub,
    'endedPub': liveEndedPub,
    'inactivePub': liveInactivePub,
    'schedPub': liveSchedPub,
  }, lens: 'CA1');

  final itemUnpub = await c.insertLiveOnlyItem(liveId: liveAirUnpub ?? '');
  c.note('fix.item.unpub', 'item on unpublished air', itemUnpub, lens: 'CA1');

  Future<HttpHit> livesGet(String id, {String? jwt, String cols = muxCols}) {
    return c.rest('GET', 'lives?id=eq.$id&select=$cols', jwt: jwt);
  }

  Future<void> probeLives(String label, String? id) async {
    if (id == null) return;
    final anonMux = await livesGet(id);
    final anonSafe = await livesGet(id, cols: safeCols);
    final anonPb = await livesGet(id, cols: 'id,playback_id,mux_playback_id,mux_vod_playback_id');
    final b1 = await livesGet(id, jwt: c.buyerJwt);
    final b1pb = await livesGet(id,
        jwt: c.buyerJwt, cols: 'id,playback_id,mux_playback_id,mux_vod_playback_id,title,status');
    final s2 = await livesGet(id, jwt: c.seller2Jwt);
    final s1 = await livesGet(id, jwt: c.sellerJwt);
    c.note('ca1.lives.anon.mux.$label', 'anon mux cols', anonMux, lens: 'CA1');
    c.note('ca1.lives.anon.safe.$label', 'anon safe cols', anonSafe, lens: 'CA1');
    c.note('ca1.lives.anon.pb.$label', 'anon playback_id', anonPb, lens: 'CA5');
    c.note('ca1.lives.b1.$label', 'B1 mux cols', b1, lens: 'CA7');
    c.note('ca1.lives.b1pb.$label', 'B1 playback cols', b1pb, lens: 'CA7');
    c.note('ca1.lives.s2.$label', 'S2 mux cols', s2, lens: 'CA7');
    c.note('ca1.lives.s1.$label', 'S1 mux cols', s1, lens: 'CA7');

    void maybeLeak({
      required String idCode,
      required String actor,
      required HttpHit h,
      required String colName,
      required String expected,
    }) {
      final v = col(h.map, colName);
      if (h.ok && v != null) {
        c.hold(
          id: idCode,
          lens: 'CA7',
          severity: 'P2',
          title: '$actor lê $colName em $label',
          actor: actor,
          pre: 'live=$id label=$label',
          repro: 'GET /rest/v1/lives?id=eq.$id&select=$colName',
          expected: expected,
          obtained: {colName: v, 'status': h.status, 'keys': h.map?.keys.toList()},
          evidence: {'live_id': id, 'label': label, 'brief': h.brief},
        );
      } else {
        c.block(
          'ca1.lives.$actor.$colName.$label',
          'CA5',
          '$actor sem $colName $label',
          h,
        );
      }
    }

    if (label == 'airUnpub' || label == 'schedUnpub' || label == 'endedUnpub') {
      maybeLeak(
        idCode: 'CA5-ANON-PBCOL-$label',
        actor: 'anon',
        h: anonPb,
        colName: 'playback_id',
        expected: 'coluna playback_id / mux_* recusada (Hub unpublished)',
      );
      maybeLeak(
        idCode: 'CA5-ANON-MUXPB-$label',
        actor: 'anon',
        h: anonPb,
        colName: 'mux_playback_id',
        expected: 'anon sem mux_playback_id (exacto VOD/cols se só VOD)',
      );
      maybeLeak(
        idCode: 'CA5-B1-MUXPB-$label',
        actor: 'B1',
        h: b1pb,
        colName: 'mux_playback_id',
        expected: 'B1 não-dono sem playback de loja unpublished',
      );
      maybeLeak(
        idCode: 'CA5-B1-PBCOL-$label',
        actor: 'B1',
        h: b1pb,
        colName: 'playback_id',
        expected: 'B1 não-dono sem playback_id de loja unpublished',
      );
      maybeLeak(
        idCode: 'CA5-ANON-VOD-$label',
        actor: 'anon',
        h: anonPb,
        colName: 'mux_vod_playback_id',
        expected: 'anon sem VOD (exacto se só isto)',
      );
      maybeLeak(
        idCode: 'CA5-B1-VOD-$label',
        actor: 'B1',
        h: b1pb,
        colName: 'mux_vod_playback_id',
        expected: 'B1 sem VOD alheio unpublished',
      );
    }
  }

  await probeLives('airPub', liveAirPub);
  await probeLives('airUnpub', liveAirUnpub);
  await probeLives('schedUnpub', liveSchedUnpub);
  await probeLives('endedUnpub', liveEndedUnpub);
  await probeLives('endedPub', liveEndedPub);
  await probeLives('inactivePub', liveInactivePub);
  await probeLives('schedPub', liveSchedPub);

  // Exactos BRBW: discovery / hub page / FOMO unpublished + scheduled inactive.
  Future<HttpHit> viewGet(String view, String id) {
    return c.rest(
      'GET',
      '$view?id=eq.$id&select=id,status,is_active,mux_playback_id,mux_vod_playback_id,seller_handle',
    );
  }

  for (final e in {
    'airUnpub': liveAirUnpub,
    'schedUnpub': liveSchedUnpub,
    'endedUnpub': liveEndedUnpub,
    'airPub': liveAirPub,
    'endedPub': liveEndedPub,
    'schedPub': liveSchedPub,
    'inactivePub': liveInactivePub,
  }.entries) {
    if (e.value == null) continue;
    final pub = await viewGet('hub_lives_public', e.value!);
    final disc = await viewGet('hub_lives_discovery_public', e.value!);
    c.note('ca1.pub.${e.key}', 'hub_lives_public', pub, lens: 'CA1');
    c.note('ca1.disc.${e.key}', 'hub_lives_discovery_public', disc, lens: 'CA1');
    final unpub = e.key.contains('Unpub');
    if (unpub && disc.list.isNotEmpty) {
      c.hold(
        id: 'CA1-DISC-UNPUB-${e.key}',
        lens: 'CA1',
        severity: 'P2',
        title: 'discovery lista live unpublished (${e.key})',
        actor: 'anon',
        pre: 'S2 hub_published=false',
        repro: 'GET hub_lives_discovery_public?id=eq.${e.value}',
        expected: '[] (exacto BRBW se air/sched unpublished)',
        obtained: disc.brief,
        countExactClosed: true,
      );
    } else if (unpub) {
      c.block('ca1.disc.unpub.${e.key}', 'CA1', 'discovery esconde unpublished', disc);
    }
    if (unpub && pub.list.isNotEmpty) {
      c.hold(
        id: 'CA1-HUBPAGE-UNPUB-${e.key}',
        lens: 'CA1',
        severity: 'P2',
        title: 'hub_lives_public lista unpublished (${e.key})',
        actor: 'anon',
        pre: 'S2 hub_published=false',
        repro: 'GET hub_lives_public?id=eq.${e.value}',
        expected: '[]',
        obtained: pub.brief,
      );
    }
  }

  Future<void> fomo(String label, String? id) async {
    if (id == null) return;
    final h = await c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': id});
    c.note('ca1.fomo.$label', 'FOMO $label', h, lens: 'CA1');
    final err = '${h.map?['error'] ?? ''}';
    final ok = h.map?['ok'] == true;
    final unpubOrInactive = label.contains('Unpub') ||
        label == 'inactivePub' ||
        label == 'schedUnpub' ||
        label == 'schedPub';
    if (unpubOrInactive && ok) {
      final exacto = label == 'schedUnpub' ||
          label == 'schedPub' ||
          label == 'inactivePub';
      c.hold(
        id: 'CA1-FOMO-$label',
        lens: 'CA1',
        severity: 'P3',
        title: 'FOMO ok em $label',
        actor: 'anon',
        pre: id,
        repro: 'POST batata_hub_live_fomo_snapshot',
        expected: 'live_not_public',
        obtained: h.brief,
        countExactClosed: exacto,
      );
    } else if (!ok && err.contains('live_not_public')) {
      c.block('ca1.fomo.$label', 'CA1', 'FOMO not_public $label', h);
    }
  }

  await fomo('airUnpub', liveAirUnpub);
  await fomo('schedUnpub', liveSchedUnpub);
  await fomo('endedUnpub', liveEndedUnpub);
  await fomo('inactivePub', liveInactivePub);
  await fomo('schedPub', liveSchedPub);
  await fomo('airPub', liveAirPub);

  // resolve-mux: anon / B1 / owner S2 / S1 cruzado
  Future<void> resolve(String label, String? id) async {
    if (id == null) return;
    final anon = await c.edge('resolve-mux-playback', body: {'live_id': id});
    final b1 = await c.edge(
      'resolve-mux-playback',
      body: {'live_id': id},
      jwt: c.buyerJwt,
    );
    final s2 = await c.edge(
      'resolve-mux-playback',
      body: {'live_id': id},
      jwt: c.seller2Jwt,
    );
    final s1 = await c.edge(
      'resolve-mux-playback',
      body: {'live_id': id},
      jwt: c.sellerJwt,
    );
    c.note('ca5.resolve.anon.$label', 'resolve anon', anon, lens: 'CA5');
    c.note('ca5.resolve.b1.$label', 'resolve B1', b1, lens: 'CA5');
    c.note('ca5.resolve.s2.$label', 'resolve S2 owner-or-not', s2, lens: 'CA7');
    c.note('ca5.resolve.s1.$label', 'resolve S1', s1, lens: 'CA5');

    String? pidOf(HttpHit h) {
      if (!h.ok) return null;
      final p = '${h.map?['playback_id'] ?? ''}'.trim();
      return p.isEmpty || p == 'null' ? null : p;
    }

    final unpub = label.contains('Unpub');
    final anonPid = pidOf(anon);
    final b1Pid = pidOf(b1);
    final s2Pid = pidOf(s2);
    final s1Pid = pidOf(s1);

    if (unpub && anonPid != null) {
      c.hold(
        id: 'CA5-RESOLVE-ANON-$label',
        lens: 'CA5',
        severity: 'P2',
        title: 'resolve-mux anon playback unpublished $label',
        actor: 'anon',
        pre: 'S2 hub_published=false $label',
        repro: 'POST resolve-mux-playback live_id=$id',
        expected: '404 live_not_public (exacto BRBW)',
        obtained: anon.brief,
        countExactClosed: true,
      );
    } else if (unpub) {
      c.block('ca5.resolve.anon.$label', 'CA5', 'resolve anon recusa unpublished', anon);
    }

    if (unpub && b1Pid != null) {
      c.hold(
        id: 'CA5-RESOLVE-B1-$label',
        lens: 'CA7',
        severity: 'P2',
        title: 'resolve-mux B1 (não-dono) playback unpublished $label',
        actor: 'B1',
        pre: 'S2 unpublished; B1 JWT',
        repro: 'POST resolve-mux-playback JWT B1 live_id=$id',
        expected: '404 live_not_public (só dono JWT ou published)',
        obtained: b1.brief,
      );
    } else if (unpub) {
      c.block('ca5.resolve.b1.$label', 'CA7', 'resolve B1 recusa unpublished', b1);
    }

    if (label == 'airUnpub' && s2Pid != null && anonPid == null) {
      // Owner split: studio preview. Not a finding unless B1/anon also get it.
      c.note('ca7.owner.split', 'S2 dono obtém playback unpublished; anon não', {
        's2': s2.brief,
        'anon': anon.brief,
        'b1': b1.brief,
      }, lens: 'CA7');
    }

    if (unpub && s1Pid != null && label != 'airPub') {
      c.hold(
        id: 'CA5-RESOLVE-S1CROSS-$label',
        lens: 'CA5',
        severity: 'P1',
        title: 'S1 resolve playback de live S2 unpublished',
        actor: 'S1',
        pre: 'S1 ≠ owner S2',
        repro: 'POST resolve-mux-playback JWT S1',
        expected: '404',
        obtained: s1.brief,
      );
    }

    final pid = anonPid ?? b1Pid ?? s2Pid;
    if (pid != null && pid.length > 8) {
      final cdn = await c.rawGet('https://stream.mux.com/$pid.m3u8');
      c.note('ca5.cdn.$label', 'CDN mux $label', {
        'status': cdn.status,
        'watchable': muxWatchable(cdn),
        'loc': cdn.location,
        'len': cdn.body.length,
      }, lens: 'CA5');
      if (unpub && muxWatchable(cdn) && (anonPid != null || b1Pid != null)) {
        c.hold(
          id: 'CA5-CDN-UNPUB-$label',
          lens: 'CA5',
          severity: 'P1',
          title: 'CDN Mux serve HLS de unpublished $label',
          actor: anonPid != null ? 'anon' : 'B1',
          pre: 'playback_id obtido sem ser dono',
          repro: 'GET https://stream.mux.com/{id}.m3u8',
          expected: 'sem HLS se política Hub unpublished',
          obtained: {'status': cdn.status, 'watchable': true, 'pid_len': pid.length},
        );
      }
    }
  }

  await resolve('airUnpub', liveAirUnpub);
  await resolve('schedUnpub', liveSchedUnpub);
  await resolve('endedUnpub', liveEndedUnpub);
  await resolve('airPub', liveAirPub);
  await resolve('endedPub', liveEndedPub);
  await resolve('inactivePub', liveInactivePub);

  // Embed lives(*) noutro REST
  if (itemUnpub != null) {
    final embedAnon = await c.rest(
      'GET',
      'live_items?id=eq.$itemUnpub&select=id,title,lives($muxCols)',
    );
    final embedB1 = await c.rest(
      'GET',
      'live_items?id=eq.$itemUnpub&select=id,title,lives($muxCols)',
      jwt: c.buyerJwt,
    );
    c.note('ca5.embed.anon', 'embed lives(*) anon', embedAnon, lens: 'CA5');
    c.note('ca5.embed.b1', 'embed lives(*) B1', embedB1, lens: 'CA5');
    final nested = embedB1.map?['lives'];
    Map<String, dynamic>? nestMap;
    if (nested is Map) nestMap = Map<String, dynamic>.from(nested);
    final nestPb = col(nestMap, 'mux_playback_id') ?? col(nestMap, 'playback_id');
    if (nestPb != null) {
      c.hold(
        id: 'CA5-EMBED-LIVES-UNPUB',
        lens: 'CA5',
        severity: 'P2',
        title: 'embed live_items→lives(*) devolve playback unpublished',
        actor: 'B1',
        pre: 'item em live unpublished air',
        repro: 'GET live_items?select=id,lives(mux_playback_id)',
        expected: 'sem mux cols / 403',
        obtained: embedB1.brief,
      );
    } else {
      c.block('ca5.embed.b1', 'CA5', 'embed não vaza mux cols', embedB1);
    }
  }

  final hubItems = await c.rest(
    'GET',
    'hub_live_items_public?live_id=eq.$liveAirUnpub&select=id,title,live_id',
  );
  final hubItemsDisc = await c.rest(
    'GET',
    'hub_live_items_discovery_public?live_id=eq.$liveAirUnpub&select=id,title,live_id',
  );
  c.note('ca1.items.pub', 'hub items unpublished air', hubItems, lens: 'CA1');
  c.note('ca1.items.disc', 'hub items discovery unpublished', hubItemsDisc, lens: 'CA1');
  if (hubItems.list.isNotEmpty || hubItemsDisc.list.isNotEmpty) {
    c.hold(
      id: 'CA1-HUBITEMS-UNPUB',
      lens: 'CA1',
      severity: 'P2',
      title: 'Hub items de directo unpublished visíveis',
      actor: 'anon',
      pre: 'S2 unpublished air + item',
      repro: 'GET hub_live_items_public / discovery',
      expected: '[]',
      obtained: {'pub': hubItems.brief, 'disc': hubItemsDisc.brief},
    );
  } else {
    c.block('ca1.items.unpub', 'CA1', 'Hub items escondem unpublished', hubItems);
  }

  // resolve_handle unpublished
  final handleS2 = '${s2p?['handle'] ?? 'rtca1137s2'}';
  final rhAnon = await c.rpc('batata_resolve_handle', {'p_handle': handleS2});
  final rhB1 = await c.rpc(
    'batata_resolve_handle',
    {'p_handle': handleS2},
    jwt: c.buyerJwt,
  );
  c.note('ca1.resolve_handle.anon', 'resolve_handle S2 unpublished', rhAnon,
      lens: 'CA1');
  c.note('ca1.resolve_handle.b1', 'resolve_handle B1', rhB1, lens: 'CA1');
  if (rhAnon.map?['found'] == true) {
    c.hold(
      id: 'CA1-RESOLVE-HANDLE-UNPUB',
      lens: 'CA1',
      severity: 'P2',
      title: 'resolve_handle encontra loja unpublished (tem lives)',
      actor: 'anon',
      pre: 'S2 hub_published=false handle=$handleS2 com lives',
      repro: 'POST batata_resolve_handle',
      expected: 'found=false not_found se Hub desligado',
      obtained: rhAnon.brief,
    );
  } else {
    c.block('ca1.resolve_handle.unpub', 'CA1', 'resolve_handle esconde unpublished',
        rhAnon);
  }

  // Hub profiles
  final profPub = await c.rest(
    'GET',
    'hub_profiles_public?id=eq.$s2&select=id,handle',
  );
  final profDisc = await c.rest(
    'GET',
    'hub_profiles_discovery_public?id=eq.$s2&select=id,handle,hub_published',
  );
  c.note('ca1.prof.pub', 'hub_profiles_public S2', profPub, lens: 'CA1');
  c.note('ca1.prof.disc', 'hub_profiles_discovery S2', profDisc, lens: 'CA1');

  // Enumerate scheduled globally as B1 (directory)
  final schedDir = await c.rest(
    'GET',
    'lives?status=eq.scheduled&select=id,title,seller_id,mux_playback_id,playback_id&limit=5',
    jwt: c.buyerJwt,
  );
  c.note('ca1.sched.dir', 'B1 lista scheduled globais', {
    'status': schedDir.status,
    'n': schedDir.list.length,
    'sample_keys': schedDir.map?.keys.toList(),
    'has_mux': col(schedDir.map, 'mux_playback_id') != null,
    'has_pb': col(schedDir.map, 'playback_id') != null,
  }, lens: 'CA1');
  if (schedDir.ok &&
      schedDir.list.isNotEmpty &&
      (col(schedDir.map, 'mux_playback_id') != null ||
          col(schedDir.map, 'playback_id') != null)) {
    c.hold(
      id: 'CA5-B1-SCHED-DIRECTORY',
      lens: 'CA5',
      severity: 'P2',
      title: 'B1 lista scheduled globais com playback_id',
      actor: 'B1',
      pre: 'GET lives?status=eq.scheduled',
      repro: 'GET /rest/v1/lives?status=eq.scheduled&select=mux_playback_id',
      expected: 'sem playback / só published via views',
      obtained: {
        'n': schedDir.list.length,
        'brief': schedDir.brief,
      },
    );
  } else {
    c.block('ca1.sched.dir', 'CA5', 'B1 scheduled sem playback ou vazio', schedDir);
  }

  await dumpJson('${outDir()}/pass1.json', {
    'prefix': prefix,
    'lenses': c.lensesHit.toList()..sort(),
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'skipped': c.skipped,
    'ids': {
      'airPub': liveAirPub,
      'airUnpub': liveAirUnpub,
      'schedUnpub': liveSchedUnpub,
      'endedUnpub': liveEndedUnpub,
      'endedPub': liveEndedPub,
      'inactivePub': liveInactivePub,
      'schedPub': liveSchedPub,
      'itemUnpub': itemUnpub,
      's2': s2,
      's1': s1,
    },
  });
  stdout.writeln('WROTE pass1.json findings=${c.findings.length}');
}
