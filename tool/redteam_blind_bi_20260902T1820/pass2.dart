/// RED TEAM CEGO BI pass2 — confirmar P2, publicar S2, FOMO, storage profundo, IP class.
import 'dart:io';

import '_rtbi.dart';

Future<void> main() async {
  final c = Rtbi.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.ensureSeller3Unpublished();

  final s2prof = await c.rest(
    'GET',
    'profiles?id=eq.${c.seller2Id}&select=id,handle,handle_suggested,hub_published,full_name',
    service: true,
  );
  c.note('p2.s2.raw', 'S2 profile before patch', s2prof.map, lens: 'BI1');

  final pub = await c.rest(
    'PATCH',
    'profiles?id=eq.${c.seller2Id}',
    service: true,
    body: {
      'handle': 'rtbi1820s2',
      'hub_published': true,
      'full_name': '$prefix-S2',
    },
  );
  c.note('p2.s2.patch', 'S2 publish patch', pub.map ?? pub.brief, lens: 'BI1');

  final hubProfAnon = await c.rest(
    'GET',
    'hub_profiles_public?id=eq.${c.seller2Id}&select=id,handle,hub_bio',
  );
  final hubProfDisc = await c.rest(
    'GET',
    'hub_profiles_discovery_public?id=eq.${c.seller2Id}&select=id,handle,hub_published',
  );
  c.note('p2.s2.hub_public', 'hub_profiles_public S2', hubProfAnon, lens: 'BI1');
  c.note('p2.s2.hub_disc', 'hub_profiles_discovery S2', hubProfDisc, lens: 'BI1');

  final vodId = '8cje21NKdUUro21jGdEv2UlfmWLD7TAMIWi2W01H5Gb8';
  final livePb = 'Cap7U300PcqvBmbZj01cL92AT01k401ntf97eCUWynvj9Pc';

  final liveAir = await c.insertLive(
    status: 'live',
    active: true,
    title: '$prefix P2 AIR',
    muxPlayback: livePb,
    muxVod: vodId,
  );
  final liveSched = await c.insertLive(
    status: 'scheduled',
    active: true,
    title: '$prefix P2 SCHED',
    muxPlayback: livePb,
    muxVod: vodId,
  );
  final liveEnded = await c.insertLive(
    status: 'ended',
    active: false,
    title: '$prefix P2 ENDED',
    muxPlayback: livePb,
    muxVod: vodId,
  );
  final liveDraft = await c.insertLive(
    status: 'draft',
    active: true,
    title: '$prefix P2 DRAFT',
    muxPlayback: livePb,
    muxVod: vodId,
  );

  final itemAir = liveAir == null
      ? null
      : await c.insertItem(liveId: liveAir, qty: 4);
  final itemSched = liveSched == null
      ? null
      : await c.insertItem(liveId: liveSched, qty: 5);
  if (liveSched != null && itemSched != null) {
    await c.insertPendingRes(
      liveId: liveSched,
      liveItemId: itemSched,
    );
  }

  Future<HttpHit> view(String name, String? id) => c.rest(
        'GET',
        '$name?id=eq.$id&select=id,status,is_active,mux_playback_id,mux_vod_playback_id,seller_handle',
      );

  final pubAir = await view('hub_lives_public', liveAir);
  final pubSched = await view('hub_lives_public', liveSched);
  final pubEnded = await view('hub_lives_public', liveEnded);
  final pubDraft = await view('hub_lives_public', liveDraft);
  final discAir = await view('hub_lives_discovery_public', liveAir);
  final discSched = await view('hub_lives_discovery_public', liveSched);
  final discEnded = await view('hub_lives_discovery_public', liveEnded);
  final discDraft = await view('hub_lives_discovery_public', liveDraft);

  c.note('p2.pub.air', 'hub_lives_public air', pubAir.map, lens: 'BI1');
  c.note('p2.pub.sched', 'hub_lives_public sched', pubSched.map, lens: 'BI1');
  c.note('p2.pub.ended', 'hub_lives_public ended', pubEnded.map, lens: 'BI1');
  c.note('p2.pub.draft', 'hub_lives_public draft', pubDraft.map, lens: 'BI1');
  c.note('p2.disc.air', 'discovery air', discAir.map, lens: 'BI7');
  c.note('p2.disc.sched', 'discovery sched', discSched.map, lens: 'BI7');
  c.note('p2.disc.ended', 'discovery ended', discEnded.map, lens: 'BI7');
  c.note('p2.disc.draft', 'discovery draft', discDraft.map, lens: 'BI7');

  String? vodOf(HttpHit h) => h.map?['mux_vod_playback_id']?.toString();
  String? pbOf(HttpHit h) => h.map?['mux_playback_id']?.toString();

  final discSchedVod = vodOf(discSched);
  final pubSchedVod = vodOf(pubSched);
  final discAirVod = vodOf(discAir);
  final pubAirVod = vodOf(pubAir);
  final pubAirPb = pbOf(pubAir);

  if (discSched.map != null &&
      discSchedVod != null &&
      discSchedVod.isNotEmpty) {
    final cdn = await c.muxCdn(discSchedVod);
    final edge = await c.edge('resolve-mux-playback', {'live_id': liveSched});
    c.hold(
      id: 'P2-BI1/BI7-disc-sched-vod',
      lens: 'BI7',
      severity: 'P2',
      title:
          'Discovery publica VOD de scheduled; CDN Mux serve HLS; Edge 404 (hub_lives_public anula VOD)',
      actor: 'anon',
      pre:
          'S2 hub_published=${hubProfAnon.map != null}; scheduled+active com mux_vod real',
      repro:
          'GET hub_lives_discovery_public?id=eq.$liveSched ; GET https://stream.mux.com/$discSchedVod.m3u8 ; POST resolve-mux-playback',
      expected:
          'VOD só em ended público; CDN não acessível a partir da grelha scheduled',
      obtained: {
        'hub_public': pubSched.map,
        'discovery': discSched.map,
        'pub_vod': pubSchedVod,
        'cdn': cdn.brief,
        'cdn_extm3u': cdn.hasExtm3u,
        'edge': edge.brief,
        's2_hub_profiles_public': hubProfAnon.map,
      },
      evidence: {'live_id': liveSched, 'vod': discSchedVod},
    );
  }

  if (discAir.map != null &&
      discAirVod != null &&
      discAirVod.isNotEmpty &&
      (pubAirVod == null || pubAirVod.isEmpty)) {
    final cdn = await c.muxCdn(discAirVod);
    c.hold(
      id: 'P2-BI7-disc-air-vod',
      lens: 'BI7',
      severity: 'P2',
      title:
          'Enquanto o directo está no ar, discovery expõe mux_vod_playback_id (gravação anterior) e o CDN serve sem Edge',
      actor: 'anon',
      pre: 'live+active com vod+playback preenchidos; hub_lives_public anula VOD',
      repro: 'GET hub_lives_discovery_public live-air ; CDN vod id',
      expected: 'VOD oculto até status=ended',
      obtained: {
        'discovery': discAir.map,
        'hub_public_vod': pubAirVod,
        'hub_public_pb': pubAirPb,
        'cdn_extm3u': cdn.hasExtm3u,
        'cdn': cdn.brief,
      },
    );
  }

  // Items discovery vs public
  final itemsPubSched = await c.rest(
    'GET',
    'hub_live_items_public?live_id=eq.$liveSched&select=id,title,price,status',
  );
  final itemsDiscSched = await c.rest(
    'GET',
    'hub_live_items_discovery_public?live_id=eq.$liveSched&select=id,title,price,status,ref_code',
  );
  final itemsDiscAir = await c.rest(
    'GET',
    'hub_live_items_discovery_public?live_id=eq.$liveAir&select=id,title,price',
  );
  c.note('p2.items.pub.sched', 'items public sched', itemsPubSched, lens: 'BI1');
  c.note('p2.items.disc.sched', 'items discovery sched', itemsDiscSched,
      lens: 'BI1');
  c.note('p2.items.disc.air', 'items discovery air', itemsDiscAir, lens: 'BI1');

  final fomoSched = await c.rpc(
      'batata_hub_live_fomo_snapshot', {'p_live_id': liveSched});
  final fomoAir =
      await c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': liveAir});
  final fomoEnded =
      await c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': liveEnded});
  c.note('p2.fomo.sched', 'FOMO sched após publish', fomoSched.map, lens: 'BI1');
  c.note('p2.fomo.air', 'FOMO air após publish', fomoAir.map, lens: 'BI1');
  c.note('p2.fomo.ended', 'FOMO ended após publish', fomoEnded.map, lens: 'BI1');

  if (fomoSched.map?['ok'] == true) {
    final items = fomoSched.map?['items'];
    var pending = 0;
    if (items is List && items.isNotEmpty && items.first is Map) {
      pending = ((items.first as Map)['pending_queue_count'] as num?)?.toInt() ??
          0;
    }
    if (pending > 0) {
      c.hold(
        id: 'P2-BI1-fomo-scheduled-queue',
        lens: 'BI1',
        severity: 'P2',
        title:
            'FOMO em scheduled publicado revela pending_queue_count (DEFINER lê reservas)',
        actor: 'anon',
        pre: 'hub_published + scheduled na hub_lives_public + 1 pending',
        repro: 'rpc batata_hub_live_fomo_snapshot',
        expected: 'live_not_public ou sem oráculo de fila',
        obtained: fomoSched.map,
      );
    } else {
      c.note('p2.fomo.sched.no_pending', 'FOMO sched ok sem pending visível',
          fomoSched.map, lens: 'BI1');
    }
  } else {
    c.block('p2.fomo.sched', 'BI1', 'FOMO sched ainda live_not_public',
        fomoSched);
  }

  // Storage deep — prefixos vs objectos alheios
  Future<HttpHit> listPriv(String prefix, {String? jwt}) => c.req(
        'POST',
        '/storage/v1/object/list/fleaber_private',
        jwt: jwt ?? c.buyerJwt,
        body: {'prefix': prefix, 'limit': 50},
      );

  final root = await listPriv('');
  final disputes = await listPriv('order_disputes/');
  final disputesB2 = await listPriv('order_disputes/${c.buyer2Id}/');
  final disputesS1 = await listPriv('order_disputes/${c.sellerId}/');
  final chatUp = await listPriv('chat_uploads/');
  final chatB2 = await listPriv('chat_uploads/${c.buyer2Id}/');
  final mediaProd = await c.req(
    'POST',
    '/storage/v1/object/list/chat_media',
    jwt: c.buyerJwt,
    body: {'prefix': 'product_photos/', 'limit': 20},
  );
  final mediaOther = await c.req(
    'POST',
    '/storage/v1/object/list/chat_media',
    jwt: c.buyerJwt,
    body: {'prefix': 'product_photos/${c.sellerId}/', 'limit': 20},
  );

  c.note('p2.stor.root', 'private root', root, lens: 'BI6');
  c.note('p2.stor.disputes', 'private order_disputes/', disputes, lens: 'BI6');
  c.note('p2.stor.disputes.b2', 'private disputes B2', disputesB2, lens: 'BI6');
  c.note('p2.stor.disputes.s1', 'private disputes S1', disputesS1, lens: 'BI6');
  c.note('p2.stor.chat', 'private chat_uploads/', chatUp, lens: 'BI6');
  c.note('p2.stor.chat.b2', 'private chat B2', chatB2, lens: 'BI6');
  c.note('p2.stor.media.prod', 'chat_media product_photos/', mediaProd,
      lens: 'BI6');
  c.note('p2.stor.media.other', 'chat_media photos S1', mediaOther, lens: 'BI6');

  bool hasAlienFiles(HttpHit h) {
    if (!h.ok) return false;
    for (final row in h.list) {
      if (row is Map) {
        final name = '${row['name'] ?? ''}';
        final meta = row['metadata'];
        if (meta != null && name.isNotEmpty && !name.endsWith('/')) {
          return true;
        }
        if (name.contains('-') && name.length > 20 && row['id'] != null) {
          return true;
        }
      }
    }
    return false;
  }

  if (hasAlienFiles(disputesB2) ||
      hasAlienFiles(disputesS1) ||
      hasAlienFiles(chatB2) ||
      hasAlienFiles(mediaOther)) {
    c.hold(
      id: 'P1-BI6-private-objects',
      lens: 'BI6',
      severity: 'P1',
      title: 'JWT B1 lista objectos de outro uid em fleaber_private/chat_media',
      actor: 'buyer JWT',
      pre: 'prefix order_disputes/{uid}/ ou product_photos/{seller}/',
      repro: 'POST storage object/list',
      expected: '[]',
      obtained: {
        'disputesB2': disputesB2.brief,
        'disputesS1': disputesS1.brief,
        'chatB2': chatB2.brief,
        'mediaOther': mediaOther.brief,
      },
    );
  } else {
    c.block(
      'p2.stor.objects',
      'BI6',
      'prefixos visíveis mas objectos alheios não listados',
      {
        'root_n': root.list.length,
        'disputes': disputes.brief,
        'disputesB2': disputesB2.brief,
        'mediaOther': mediaOther.brief,
      },
    );
  }

  // Connect IP class (uma classe: canonicalização WHATWG → loopback allowlisted)
  final ipClass = <String, String>{
    'decimal': 'https://2130706433',
    '127.1': 'https://127.1',
    '0x7f': 'https://0x7f000001',
    'octal': 'https://0177.0.0.1',
    'dword_alt': 'https://2130706433.fleaber.pt',
  };
  final ipLoc = <String, String?>{};
  for (final e in ipClass.entries) {
    final h = await c.edge(
      'create-connect-account',
      null,
      method: 'GET',
      qs: 'web_return_origin=${Uri.encodeQueryComponent(e.value)}',
    );
    ipLoc[e.key] = h.location;
    c.note('p2.ip.${e.key}', '${e.value} → ${h.location}', h, lens: 'BI2');
  }
  final hijacks = ipLoc.entries
      .where((e) =>
          e.key != 'dword_alt' &&
          (e.value ?? '').contains('127.0.0.1') ||
          (e.value ?? '').contains('localhost'))
      .map((e) => '${e.key}:${e.value}')
      .toList();
  if (hijacks.isNotEmpty) {
    c.hold(
      id: 'P2-BI2-connect-ip-canonical',
      lens: 'BI2',
      severity: 'P2',
      title:
          'sanitizeWebReturnOrigin aceita IPv4 decimal/octal/hex/127.1 e canonicaliza para 127.0.0.1 (allowlisted) — 303 /wallet',
      actor: 'browser (sem JWT)',
      pre: 'GET create-connect-account?web_return_origin=',
      repro:
          'web_return_origin=https://2130706433 | https://127.1 | https://0x7f000001 | https://0177.0.0.1',
      expected:
          'só hosts exactos fleaber.pt / localhost literal — não formas IP alternativas',
      obtained: ipLoc,
    );
  }

  // broadcasting oracle anon
  final bcAnon =
      await c.rpc('batata_live_is_broadcasting', {'p_live_id': liveAir});
  final bcRand = await c.rpc('batata_live_is_broadcasting', {
    'p_live_id': '00000000-0000-0000-0000-000000000001',
  });
  c.note('p2.bc.anon', 'broadcasting anon', {'air': bcAnon.json, 'rand': bcRand.json},
      lens: 'BI1');
  if (bcAnon.ok && bcAnon.json == true) {
    c.hold(
      id: 'P3-BI1-broadcasting-anon',
      lens: 'BI1',
      severity: 'P3',
      title: 'anon executa batata_live_is_broadcasting (oráculo UUID)',
      actor: 'anon',
      pre: 'REVOKE no SQL historic; GRANT live?',
      repro: 'POST rpc/batata_live_is_broadcasting',
      expected: '42501 anon',
      obtained: {'air': bcAnon.json, 'rand': bcRand.json},
    );
  }

  await c.endLives();
  await c.dumpAll('pass2_findings.json');
  stdout.writeln(
      'PASS2 findings=${c.findings.length} blocked=${c.blocked.length}');
}
