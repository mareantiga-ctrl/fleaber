import 'dart:convert';
import 'dart:io';

import '_rtbc.dart';

/// Pass 1 — Hub/Edge pós-ANAS. Variantes NOVAS (não exactos AQ/AK).
/// Lentes: BC1 Hub · BC2 origin/CORS · BC3 settle alheio · BC4 body spoof
///         BC5 playback prematuro / Mux/LiveKit · BC6 storage · BC7 composição
void main() async {
  final c = Rtbc.fromEnv(loadEnv());
  try {
    await c.loginActors();
    await c.ensureBuyer2();
    await c.ensureSeller2();
    await _run(c);
  } finally {
    try {
      await c.endLives();
      if (c.sellerId != null) await c.restoreQaSellerHandle();
    } catch (e) {
      stderr.writeln('cleanup: $e');
    }
  }
}

Future<void> _run(Rtbc c) async {

  final out = <String, Object?>{
    'auditor': 'REDTEAM_BLIND_BC_HUB_EDGE_POS_ANAS_v1',
    'stamp': stamp,
    'staging': projectMust,
    'seller': c.sellerId,
    'buyer': c.buyerId,
    'seller2': c.seller2Id,
    'buyer2': c.buyer2Id,
  };

  await c.rest('PATCH', 'profiles?id=eq.${c.sellerId}', service: true, body: {
    'hub_published': true,
    'handle': 'fleahub-demo-ux',
  }, prefer: 'return=minimal');

  // Real Mux IDs already on staging (CDN proof). Never invent.
  final existingMux = await c.rest(
    'GET',
    'lives?mux_vod_playback_id=not.is.null&select=id,status,is_active,mux_playback_id,mux_vod_playback_id,mux_stream_key&limit=3',
    service: true,
  );
  String? realVod;
  String? realLivePb;
  String? realStreamKey;
  for (final row in existingMux.list) {
    if (row is Map) {
      realVod ??= (row['mux_vod_playback_id'] as String?)?.trim();
      realLivePb ??= (row['mux_playback_id'] as String?)?.trim();
      realStreamKey ??= (row['mux_stream_key'] as String?)?.trim();
    }
  }
  out['seed_mux'] = {
    'vod': realVod,
    'live_pb': realLivePb,
    'has_stream_key': realStreamKey != null && realStreamKey.isNotEmpty,
    'src': existingMux.brief,
  };

  final sku = await c.insertProduct(title: '$prefix sku-40', price: 40, qty: 2);

  final liveOn = await c.insertLive(
    active: true,
    status: 'live',
    title: '$prefix ON',
    muxPlayback: realLivePb ?? 'pb_bc_live_placeholder',
    muxVod: realVod,
  );
  final itemOn = await c.insertLiveItem(
    liveId: liveOn!,
    title: '$prefix on-item',
    price: 7,
    qty: 2,
  );
  final hitchNull = await c.insertLiveItem(
    liveId: liveOn,
    title: '$prefix hitch-nullqty',
    price: 5,
    qty: null,
    productId: sku,
    itemKind: 'marketplace_product',
  );

  final schedVod = await c.insertLive(
    active: false,
    status: 'scheduled',
    title: '$prefix SCHED-VOD',
    muxVod: realVod,
    muxPlayback: realLivePb,
    streamKey: 'sk_bc_should_not_leak',
  );
  await c.insertLiveItem(
    liveId: schedVod!,
    title: '$prefix sched-item',
    price: 9,
    qty: 4,
  );

  final idleVod = await c.insertLive(
    active: true,
    status: 'draft',
    title: '$prefix DRAFT-ACT-VOD',
    muxVod: realVod,
    muxPlayback: realLivePb,
  );
  final previewVod = await c.insertLive(
    active: true,
    status: 'error',
    title: '$prefix ERROR-ACT',
    muxVod: realVod,
  );
  final createdVod = await c.insertLive(
    active: true,
    status: 'scheduled',
    title: '$prefix SCHED-ACT',
    muxVod: realVod,
  );
  final endedAct = await c.insertLive(
    active: true,
    status: 'ended',
    title: '$prefix ENDED-ACT-LEFTOVER',
    muxPlayback: realLivePb,
    muxVod: realVod,
  );
  final endedRf = await c.insertLive(
    active: false,
    status: 'ended',
    title: '$prefix ENDED-RF',
    muxVod: realVod,
  );
  final itemRf = await c.insertLiveItem(
    liveId: endedRf!,
    title: '$prefix rf-item',
    status: 'reserved_full',
    price: 11,
    qty: 1,
  );
  final s2Live = await c.insertLive(
    active: true,
    status: 'live',
    seller: c.seller2Id,
    title: '$prefix S2-UNPUB-ON',
    muxPlayback: realLivePb,
    muxVod: realVod,
    streamKey: 'sk_s2_secret',
  );

  out['ids'] = {
    'liveOn': liveOn,
    'itemOn': itemOn,
    'hitchNull': hitchNull,
    'schedVod': schedVod,
    'idleVod': idleVod,
    'previewVod': previewVod,
    'createdVod': createdVod,
    'endedAct': endedAct,
    'endedRf': endedRf,
    'itemRf': itemRf,
    's2Live': s2Live,
  };

  Future<Map<String, Object?>> hubRow(String table, String id) async {
    final h = await c.rest('GET', '$table?id=eq.$id&select=*');
    return {
      'status': h.status,
      'n': h.list.length,
      'row': h.map,
      'keys': h.map?.keys.toList(),
      'brief': h.brief,
    };
  }

  // --------------------------------------------------------------------------
  // BC1 — Hub views / FOMO / handle / oráculos (não exactos AQ/AK)
  // --------------------------------------------------------------------------
  final hubSurfaces = <String, Object?>{};
  for (final e in {
    'on': liveOn,
    'sched': schedVod,
    'idle': idleVod,
    'preview': previewVod,
    'created': createdVod,
    'endedAct': endedAct,
    'endedRf': endedRf,
    's2': s2Live,
  }.entries) {
    if (e.value == null) continue;
    hubSurfaces['lives_${e.key}'] = await hubRow('hub_lives_public', e.value!);
    hubSurfaces['disc_${e.key}'] =
        await hubRow('hub_lives_discovery_public', e.value!);
    hubSurfaces['items_${e.key}'] = (await c.rest(
      'GET',
      'hub_live_items_public?live_id=eq.${e.value}&select=id,title,price,status',
    )).brief;
    hubSurfaces['fomo_${e.key}'] =
        (await c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': e.value}))
            .brief;
  }
  out['bc1.hub'] = hubSurfaces;

  final hubSched = hubSurfaces['lives_sched'] as Map<String, Object?>;
  final schedRow = hubSched['row'] as Map<String, dynamic>?;
  final leakedVod = schedRow?['mux_vod_playback_id']?.toString();
  final leakedPb = schedRow?['mux_playback_id']?.toString();
  final leakedKeys = (hubSched['keys'] as List?)?.map((e) => '$e').toList();
  final sensitiveHubCols = leakedKeys
          ?.where((k) =>
              k.contains('stream') ||
              k.contains('livekit') ||
              k.contains('asset') ||
              k == 'mux_live_id' ||
              k.contains('key'))
          .toList() ??
      [];

  if (hubSched['n'] == 1 &&
      ((leakedVod != null && leakedVod.isNotEmpty) ||
          (leakedPb != null && leakedPb.isNotEmpty))) {
    c.finding(
      id: 'RTBC-BC1-HUB-SCHED-PLAYBACK-COLS',
      lens: 'BC1',
      severity: 'P3',
      title: 'hub_lives_public lista scheduled com mux_playback/vod IDs',
      actor: 'anon',
      pre: 'status=scheduled is_active=false com IDs Mux reais copiados',
      repro: 'GET hub_lives_public?id=eq.<sched>&select=*',
      expected: 'scheduled fora da vitrine OU sem IDs de playback',
      obtained: 'row n=1 vod=$leakedVod pb=$leakedPb keys=$leakedKeys',
      evidence: {'row': schedRow},
    );
  } else {
    c.hold(
      id: 'RTBC-BC1-HUB-SCHED-PLAYBACK-COLS',
      lens: 'BC1',
      title: 'Hub scheduled sem IDs de playback (ou fora da view)',
      actor: 'anon',
      pre: 'scheduled+vod',
      repro: 'GET hub_lives_public',
      expected: 'oculto ou sem IDs',
      obtained: hubSched['brief'],
    );
  }

  if (sensitiveHubCols.isNotEmpty) {
    c.finding(
      id: 'RTBC-BC1-HUB-SENSITIVE-COLS',
      lens: 'BC1',
      severity: 'P2',
      title: 'View Hub expõe colunas de ingest/stream',
      actor: 'anon',
      pre: 'select=* hub_lives_public',
      repro: 'GET hub_lives_public?select=*',
      expected: 'sem stream_key / mux_live_id / livekit',
      obtained: sensitiveHubCols,
    );
  } else {
    c.hold(
      id: 'RTBC-BC1-HUB-SENSITIVE-COLS',
      lens: 'BC1',
      title: 'select=* Hub sem stream keys',
      actor: 'anon',
      pre: 'scheduled row',
      repro: 'GET hub_lives_public select=*',
      expected: 'whitelist',
      obtained: leakedKeys,
    );
  }

  final idleHub = (hubSurfaces['lives_idle'] as Map<String, Object?>?) ??
      {'n': 0, 'brief': 'missing fixture'};
  if (idleHub['n'] == 1) {
    c.finding(
      id: 'RTBC-BC1-HUB-IDLE-ACTIVE',
      lens: 'BC1',
      severity: 'P3',
      title: 'draft+is_active entra em hub_lives_public (não é scheduled|live|ended)',
      actor: 'anon',
      pre: 'status=draft is_active=true',
      repro: 'GET hub_lives_public?id=eq.<idle>',
      expected: 'fora da vitrine (só scheduled|live|ended públicos)',
      obtained: idleHub['brief'],
      evidence: {'row': idleHub['row']},
    );
  } else {
    c.hold(
      id: 'RTBC-BC1-HUB-IDLE-ACTIVE',
      lens: 'BC1',
      title: 'draft+active fora do Hub',
      actor: 'anon',
      pre: 'draft+is_active',
      repro: 'GET hub_lives_public',
      expected: '[]',
      obtained: idleHub['brief'],
    );
  }

  final s2hub = hubSurfaces['lives_s2'] as Map<String, Object?>;
  if (s2hub['n'] != 0) {
    c.finding(
      id: 'RTBC-BC1-HUB-UNPUB-SELLER',
      lens: 'BC1',
      severity: 'P2',
      title: 'Hub lista live de vendedor com vitrine desligada',
      actor: 'anon',
      pre: 'seller2 hub_published=false live+active',
      repro: 'GET hub_lives_public',
      expected: '[]',
      obtained: s2hub['brief'],
    );
  } else {
    c.hold(
      id: 'RTBC-BC1-HUB-UNPUB-SELLER',
      lens: 'BC1',
      title: 'seller2 unpublished fora do Hub',
      actor: 'anon',
      pre: 'hub_published=false',
      repro: 'GET hub_lives_public',
      expected: '[]',
      obtained: s2hub['brief'],
    );
  }

  final embed = await c.rest(
    'GET',
    'hub_lives_public?id=eq.$schedVod&select=*,hub_live_items_public(*)',
  );
  final livesEmbed = await c.rest(
    'GET',
    'hub_lives_public?id=eq.$schedVod&select=*,lives(*)',
  );
  out['bc1.embed'] = {'items': embed.brief, 'lives': livesEmbed.brief};
  final livesEmbedBody = livesEmbed.body.toLowerCase();
  if (livesEmbed.ok &&
      (livesEmbedBody.contains('stream_key') ||
          livesEmbedBody.contains('mux_live_id') ||
          livesEmbedBody.contains('livekit'))) {
    c.finding(
      id: 'RTBC-BC1-EMBED-LIVES',
      lens: 'BC1',
      severity: 'P1',
      title: 'PostgREST embed lives(*) a partir da view Hub vaza ingest',
      actor: 'anon',
      pre: 'hub_lives_public select=*,lives(*)',
      repro: 'GET hub_lives_public?select=*,lives(*)',
      expected: 'embed recusado ou sem keys',
      obtained: livesEmbed.brief,
    );
  } else {
    c.hold(
      id: 'RTBC-BC1-EMBED-LIVES',
      lens: 'BC1',
      title: 'embed lives(*) não vaza ingest',
      actor: 'anon',
      pre: 'select=*,lives(*)',
      repro: 'GET hub_lives_public',
      expected: 'erro ou sem keys',
      obtained: livesEmbed.brief,
    );
  }

  final stockAnonRf = await c.rpc('batata_live_item_stock', {
    'p_live_item_id': itemRf,
  });
  final stockJwtRf = await c.rpc('batata_live_item_stock', {
    'p_live_item_id': itemRf,
  }, jwt: c.buyerJwt);
  final qtyAnonRf = await c.rpc('batata_live_item_total_qty', {
    'p_live_item_id': itemRf,
  });
  final qtyJwtRf = await c.rpc('batata_live_item_total_qty', {
    'p_live_item_id': itemRf,
  }, jwt: c.buyerJwt);
  out['bc1.stock'] = {
    'anon': stockAnonRf.brief,
    'jwt': stockJwtRf.brief,
    'qty_anon': qtyAnonRf.brief,
    'qty_jwt': qtyJwtRf.brief,
    'anon_json': stockAnonRf.json,
    'jwt_json': stockJwtRf.json,
  };

  final anonStockOk = stockAnonRf.map?['ok'] == true;
  if (anonStockOk) {
    c.finding(
      id: 'RTBC-BC1-STOCK-ANON-ENDED',
      lens: 'BC1',
      severity: 'P3',
      title: 'anon oráculo stock/preço de gravado reserved_full (gate ANAS falhou)',
      actor: 'anon',
      pre: 'ended reserved_full',
      repro: 'POST rpc/batata_live_item_stock',
      expected: 'live_item_not_found',
      obtained: stockAnonRf.brief,
      evidence: {'json': stockAnonRf.json},
    );
  } else {
    c.hold(
      id: 'RTBC-BC1-STOCK-ANON-ENDED',
      lens: 'BC1',
      title: 'ANAS: anon stock ended = not_found',
      actor: 'anon',
      pre: 'reserved_full ended',
      repro: 'rpc batata_live_item_stock',
      expected: 'not_found',
      obtained: stockAnonRf.brief,
    );
  }

  final jwtStockOk = stockJwtRf.map?['ok'] == true;
  if (jwtStockOk) {
    c.finding(
      id: 'RTBC-BC1-STOCK-JWT-ENDED',
      lens: 'BC1',
      severity: 'P3',
      title: 'buyer JWT lê stock/preço de gravado reserved_full (gate só anon)',
      actor: 'buyer JWT',
      pre: 'ANAS gated auth.role=anon; authenticated sem gate de vitrine',
      repro: 'POST rpc/batata_live_item_stock JWT buyer',
      expected: 'not_found ou 42501 (mesmo que anon)',
      obtained:
          'ok price=${stockJwtRf.map?['price']} avail=${stockJwtRf.map?['available_qty']} live_status=${stockJwtRf.map?['live_status']}',
      evidence: {'json': stockJwtRf.json},
    );
  } else {
    c.hold(
      id: 'RTBC-BC1-STOCK-JWT-ENDED',
      lens: 'BC1',
      title: 'JWT também gated em gravado',
      actor: 'buyer JWT',
      pre: 'reserved_full ended',
      repro: 'rpc batata_live_item_stock JWT',
      expected: 'not_found',
      obtained: stockJwtRf.brief,
    );
  }

  final qtyAnonN = qtyAnonRf.json;
  final qtyIsNum = qtyAnonN is num && qtyAnonN > 0;
  if (qtyIsNum) {
    c.finding(
      id: 'RTBC-BC1-TOTALQTY-ANON-ENDED',
      lens: 'BC1',
      severity: 'P3',
      title: 'anon batata_live_item_total_qty devolve qty de gravado (sem gate)',
      actor: 'anon',
      pre: 'GRANT anon em total_qty; função sem broadcasting gate',
      repro: 'POST rpc/batata_live_item_total_qty',
      expected: '42501 ou 0',
      obtained: qtyAnonRf.brief,
    );
  } else {
    c.hold(
      id: 'RTBC-BC1-TOTALQTY-ANON-ENDED',
      lens: 'BC1',
      title: 'anon total_qty não oráculo',
      actor: 'anon',
      pre: 'ended item',
      repro: 'rpc total_qty',
      expected: '0/42501',
      obtained: qtyAnonRf.brief,
    );
  }

  final restLives = await c.rest('GET', 'lives?id=eq.$liveOn&select=*');
  final restItemsJwt = await c.rest(
    'GET',
    'live_items?id=eq.$hitchNull&select=id,price,quantity,status',
    jwt: c.buyerJwt,
  );
  out['bc1.rest'] = {
    'lives_anon': restLives.brief,
    'hitch_jwt': restItemsJwt.brief,
    'hitch_json': restItemsJwt.json,
  };
  if (restLives.ok && restLives.list.isNotEmpty) {
    c.finding(
      id: 'RTBC-BC1-REST-LIVES-ANON',
      lens: 'BC1',
      severity: 'P1',
      title: 'anon SELECT lives (tabela base)',
      actor: 'anon',
      pre: 'revoke anon on lives',
      repro: 'GET rest/v1/lives',
      expected: '401/42501/[]',
      obtained: restLives.brief,
    );
  } else {
    c.hold(
      id: 'RTBC-BC1-REST-LIVES-ANON',
      lens: 'BC1',
      title: 'anon sem SELECT lives',
      actor: 'anon',
      pre: 'GET lives',
      repro: 'GET rest/v1/lives',
      expected: 'deny',
      obtained: restLives.brief,
    );
  }
  if (restItemsJwt.ok && restItemsJwt.list.isNotEmpty) {
    c.finding(
      id: 'RTBC-BC1-HITCH-NULLQTY-JWT',
      lens: 'BC1',
      severity: 'P3',
      title: 'buyer REST vê hitch quantity=null durante broadcasting',
      actor: 'buyer JWT',
      pre: 'ANAS policy exige quantity>0; hitch qty null',
      repro: 'GET live_items?id=eq.<hitch>',
      expected: '[]',
      obtained: restItemsJwt.brief,
    );
  } else {
    c.hold(
      id: 'RTBC-BC1-HITCH-NULLQTY-JWT',
      lens: 'BC1',
      title: 'hitch qty null oculto no REST buyer',
      actor: 'buyer JWT',
      pre: 'quantity=null + broadcasting',
      repro: 'GET live_items',
      expected: '[]',
      obtained: restItemsJwt.brief,
    );
  }

  final eventsAnon = await c.rest(
    'GET',
    'stripe_checkout_events?select=session_id,buyer_id,event,live_id&limit=5',
  );
  final eventsJwt = await c.rest(
    'GET',
    'stripe_checkout_events?select=session_id,buyer_id,event,live_id,order_id&limit=8',
    jwt: c.buyerJwt,
  );
  out['bc1.events'] = {'anon': eventsAnon.brief, 'jwt': eventsJwt.brief};
  final alienEvents = eventsJwt.list.where((e) {
    if (e is! Map) return false;
    final bid = '${e['buyer_id'] ?? ''}';
    final sid = '${e['session_id'] ?? ''}';
    return sid.startsWith('cs_') && bid.isNotEmpty && bid != c.buyerId;
  }).toList();
  if (alienEvents.isNotEmpty) {
    c.finding(
      id: 'RTBC-BC1-EVENTS-CROSS-USER',
      lens: 'BC1',
      severity: 'P2',
      title: 'JWT lê stripe_checkout_events de outros (session_id alheio)',
      actor: 'buyer JWT',
      pre: 'GRANT select authenticated; comment diz «próprio»',
      repro: 'GET stripe_checkout_events?limit=8',
      expected: 'só buyer_id próprio ou []',
      obtained: 'n_alien=${alienEvents.length} sample=${clip(alienEvents.first)}',
      evidence: {'n': alienEvents.length, 'sample': alienEvents.take(2).toList()},
    );
  } else {
    c.hold(
      id: 'RTBC-BC1-EVENTS-CROSS-USER',
      lens: 'BC1',
      title: 'events JWT sem session_id alheio visível',
      actor: 'buyer JWT',
      pre: 'GET stripe_checkout_events',
      repro: 'GET stripe_checkout_events',
      expected: 'próprio ou deny',
      obtained: eventsJwt.brief,
    );
  }

  final handleCases = <String, HttpHit>{};
  for (final h in [
    'fleahub-demo-ux',
    'FLEAHUB-DEMO-UX',
    'fleahub-demo-ux ',
    'fleahub‑demo‑ux', // non-breaking hyphen
    'fleahub-demo-ux\u200b',
    'rtbc-s2-suggested',
  ]) {
    handleCases[h] = await c.rpc('batata_resolve_handle', {'p_handle': h});
  }
  out['bc1.handles'] = handleCases.map((k, v) => MapEntry(k, v.brief));
  final s2handle = handleCases['rtbc-s2-suggested'];
  if (s2handle != null && s2handle.ok && '${s2handle.json}'.contains('${c.seller2Id}')) {
    c.finding(
      id: 'RTBC-BC1-HANDLE-SUGGESTED-UNPUB',
      lens: 'BC1',
      severity: 'P3',
      title: 'resolve_handle enumera seller unpublished via handle_suggested',
      actor: 'anon',
      pre: 'seller2 hub_published=false handle_suggested set',
      repro: 'rpc batata_resolve_handle p_handle=rtbc-s2-suggested',
      expected: 'null / not_found',
      obtained: s2handle.brief,
    );
  } else {
    c.hold(
      id: 'RTBC-BC1-HANDLE-SUGGESTED-UNPUB',
      lens: 'BC1',
      title: 'handle_suggested unpublished não resolve',
      actor: 'anon',
      pre: 'seller2',
      repro: 'rpc batata_resolve_handle',
      expected: 'null',
      obtained: s2handle?.brief,
    );
  }

  // --------------------------------------------------------------------------
  // BC2 — CORS / web_return_origin / Connect
  // --------------------------------------------------------------------------
  final corsEvil = await c.edge(
    'resolve-mux-playback',
    extra: {'Origin': 'https://evil.example'},
    body: {'live_id': liveOn},
  );
  final corsSub = await c.edge(
    'create-live-tip-checkout',
    extra: {'Origin': 'https://fleaber.pt.evil.com'},
    body: {
      'live_id': liveOn,
      'seller_id': c.sellerId,
      'amount_eur': 1,
    },
    jwt: c.buyerJwt,
  );
  final corsNull = await c.req(
    'OPTIONS',
    '/functions/v1/create-live-tip-checkout',
    extra: {
      'Origin': 'null',
      'Access-Control-Request-Method': 'POST',
    },
  );
  out['bc2.cors'] = {
    'evil_acao': corsEvil.acao,
    'evil_brief': corsEvil.brief,
    'sub_acao': corsSub.acao,
    'sub_brief': corsSub.brief,
    'null_acao': corsNull.acao,
    'null_brief': corsNull.brief,
  };
  bool corsReflects(String? acao, String needle) =>
      (acao ?? '').toLowerCase().contains(needle);
  if (corsReflects(corsEvil.acao, 'evil.example') ||
      corsReflects(corsSub.acao, 'evil.com') ||
      corsReflects(corsNull.acao, 'null')) {
    c.finding(
      id: 'RTBC-BC2-CORS-REFLECT',
      lens: 'BC2',
      severity: 'P2',
      title: 'CORS reflecte Origin hostil',
      actor: 'anon/browser',
      pre: 'Origin evil / subdomain / null',
      repro: 'POST/OPTIONS Edge com Origin hostil',
      expected: 'ACAO fleaber.pt ou * sem evil',
      obtained:
          'evil=${corsEvil.acao} sub=${corsSub.acao} null=${corsNull.acao}',
    );
  } else {
    c.hold(
      id: 'RTBC-BC2-CORS-REFLECT',
      lens: 'BC2',
      title: 'CORS não reflecte attacker',
      actor: 'browser',
      pre: 'Origin hostil',
      repro: 'Edge Origin header',
      expected: 'allowlist',
      obtained: 'evil=${corsEvil.acao} sub=${corsSub.acao} null=${corsNull.acao}',
    );
  }

  final origins = {
    'evil': 'https://evil.example/steal',
    'sub': 'https://fleaber.pt.evil.com',
    'userinfo': 'https://fleaber.pt@evil.com',
    'js': 'javascript:alert(1)',
    'proto': '//evil.example',
    'dot': 'https://fleaber.pt.',
    'enc': 'https://evil.example%2ffleaber.pt',
  };
  final connectHits = <String, String>{};
  for (final e in origins.entries) {
    final h = await c.edge(
      'create-connect-account',
      method: 'GET',
      qs: '?web_return_origin=${Uri.encodeQueryComponent(e.value)}',
    );
    connectHits[e.key] = h.brief;
    final loc = h.location ?? '';
    if (loc.contains('evil') || loc.startsWith('javascript:')) {
      c.finding(
        id: 'RTBC-BC2-CONNECT-${e.key.toUpperCase()}',
        lens: 'BC2',
        severity: 'P1',
        title: 'Connect GET Location hostil (${e.key})',
        actor: 'anon',
        pre: 'web_return_origin=${e.value}',
        repro: 'GET create-connect-account?web_return_origin=',
        expected: 'sem Location evil',
        obtained: h.brief,
      );
    }
  }
  out['bc2.connect'] = connectHits;
  if (!c.findings.any((f) => '${f['id']}'.startsWith('RTBC-BC2-CONNECT-'))) {
    c.hold(
      id: 'RTBC-BC2-CONNECT-EVIL',
      lens: 'BC2',
      title: 'Connect GET não redirecciona para origem hostil',
      actor: 'anon',
      pre: 'várias origens',
      repro: 'GET create-connect-account',
      expected: 'HTML app / wallet allowlist',
      obtained: connectHits,
    );
  }

  // --------------------------------------------------------------------------
  // BC4 + BC5 + BC3 — tip/mux/settle (variantes novas de estado)
  // --------------------------------------------------------------------------
  Future<HttpHit> tip(String? liveId, {String? seller, double amount = 1, Object? extra}) {
    if (liveId == null) {
      return Future.value(HttpHit(0, 'no-id', null));
    }
    return c.edge('create-live-tip-checkout', jwt: c.buyerJwt, body: {
      'live_id': liveId,
      'seller_id': seller ?? c.sellerId,
      'amount_eur': amount,
      if (extra is Map) ...extra,
    });
  }

  final tipOn = await tip(liveOn);
  final tipSched = await tip(schedVod);
  final tipIdle = await tip(idleVod);
  final tipPreview = await tip(previewVod);
  final tipCreated = await tip(createdVod);
  final tipEndedAct = await tip(endedAct);
  final tipS2mismatch = await tip(liveOn, seller: c.seller2Id);
  final tipIdSpoof = await tip(liveOn, extra: {'tip_id': '00000000-0000-0000-0000-000000000001'});
  final tipAmtLo = await tip(liveOn, amount: 0.5);
  final tipAmtHi = await tip(liveOn, amount: 501);
  final tipPbUnpub = await tip(liveOn, extra: {
    'playback_id': leakedVod ?? realVod ?? 'unpub_pb',
    'web_return_origin': 'https://evil.example',
    'is_live': false,
  });

  out['bc4.tips'] = {
    'on': tipOn.brief,
    'sched': tipSched.brief,
    'idle': tipIdle.brief,
    'preview': tipPreview.brief,
    'created': tipCreated.brief,
    'endedAct': tipEndedAct.brief,
    's2seller': tipS2mismatch.brief,
    'tip_id': tipIdSpoof.brief,
    'amt_lo': tipAmtLo.brief,
    'amt_hi': tipAmtHi.brief,
    'pb_unpub': tipPbUnpub.brief,
    'on_cs': tipOn.checkoutId,
    'pb_cs': tipPbUnpub.checkoutId,
  };

  void tipShouldDeny(String id, HttpHit h, String title) {
    if (h.ok && h.hasCheckout) {
      c.finding(
        id: id,
        lens: 'BC4',
        severity: 'P2',
        title: title,
        actor: 'buyer JWT',
        pre: 'batata_live_is_broadcasting=false ou spoof',
        repro: 'POST create-live-tip-checkout',
        expected: '400 sem Session',
        obtained: h.brief,
        evidence: {'cs': h.checkoutId},
      );
    } else {
      c.hold(
        id: id,
        lens: 'BC4',
        title: '$title — recusado',
        actor: 'buyer JWT',
        pre: 'não broadcasting / spoof',
        repro: 'POST create-live-tip-checkout',
        expected: '400',
        obtained: h.brief,
      );
    }
  }

  tipShouldDeny('RTBC-BC4-TIP-IDLE', tipIdle, 'Tip em draft+is_active abre Session');
  tipShouldDeny('RTBC-BC4-TIP-PREVIEW', tipPreview, 'Tip em error+is_active abre Session');
  tipShouldDeny('RTBC-BC4-TIP-CREATED', tipCreated, 'Tip em scheduled+is_active abre Session');
  tipShouldDeny('RTBC-BC4-TIP-ENDED-ACTIVE', tipEndedAct, 'Tip em ended+is_active leftover abre Session');
  tipShouldDeny('RTBC-BC4-TIP-SCHED', tipSched, 'Tip scheduled (regressão ANAS)');
  tipShouldDeny('RTBC-BC4-TIP-SELLER-SPOOF', tipS2mismatch, 'Tip seller_id ≠ dono da live');
  if (tipIdSpoof.ok && tipIdSpoof.hasCheckout) {
    c.finding(
      id: 'RTBC-BC4-TIP-ID-SPOOF',
      lens: 'BC4',
      severity: 'P1',
      title: 'Edge aceita tip_id do cliente',
      actor: 'buyer JWT',
      pre: 'body.tip_id UUID alheio',
      repro: 'POST create-live-tip-checkout tip_id=',
      expected: '400 Client tip_id is not allowed',
      obtained: tipIdSpoof.brief,
    );
  } else {
    c.hold(
      id: 'RTBC-BC4-TIP-ID-SPOOF',
      lens: 'BC4',
      title: 'tip_id cliente recusado',
      actor: 'buyer JWT',
      pre: 'body.tip_id',
      repro: 'POST tip',
      expected: '400',
      obtained: tipIdSpoof.brief,
    );
  }

  if (tipOn.ok && tipOn.hasCheckout) {
    c.hold(
      id: 'RTBC-BC4-TIP-ON-OK',
      lens: 'BC4',
      title: 'Tip broadcasting cria Session (happy path, sem captura)',
      actor: 'buyer JWT',
      pre: 'live+is_active',
      repro: 'POST create-live-tip-checkout',
      expected: '200 cs_test',
      obtained: tipOn.brief,
    );
  } else {
    c.note('bc4.tip_on_fail', 'tip broadcasting falhou', tipOn.brief, lens: 'BC4');
  }

  // BC3 settle alheio (não pagar)
  final cs = tipOn.checkoutId;
  final settleOwn = cs == null
      ? null
      : await c.edge(
          'create-live-tip-checkout',
          method: 'GET',
          qs: '?session_id=$cs&checkout_return=success',
        );
  final settleB2 = cs == null
      ? null
      : await c.edge(
          'create-live-tip-checkout',
          method: 'GET',
          qs: '?session_id=$cs&checkout_return=success',
          jwt: c.buyer2Jwt,
        );
  final settleForge = await c.edge(
    'create-live-tip-checkout',
    method: 'GET',
    qs: '?session_id=cs_test_${'a' * 40}&checkout_return=success',
  );
  final settleUuid = await c.edge(
    'create-live-tip-checkout',
    method: 'GET',
    qs: '?session_id=${itemOn ?? liveOn}&checkout_return=success',
  );
  final settlePi = await c.edge(
    'create-payment-intent',
    method: 'GET',
    qs: '?session_id=${cs ?? 'cs_test_missing'}&checkout_return=success',
  );
  out['bc3.settle'] = {
    'own': settleOwn?.brief,
    'b2': settleB2?.brief,
    'forge': settleForge.brief,
    'uuid': settleUuid.brief,
    'cross_fn': settlePi.brief,
  };

  bool captured(HttpHit? h) {
    if (h == null) return false;
    final b = h.body.toLowerCase();
    return h.status == 303 ||
        b.contains('pagamento recebido') ||
        b.contains('gorjeta') && b.contains('confirm');
  }

  if (captured(settleOwn) || captured(settleB2)) {
    c.finding(
      id: 'RTBC-BC3-SETTLE-UNPAID-CAPTURE',
      lens: 'BC3',
      severity: 'P0',
      title: 'GET settle trata Session unpaid como paga',
      actor: 'anon/B2',
      pre: 'cs_test criado, NÃO pago com 4242',
      repro: 'GET create-live-tip-checkout?session_id=&checkout_return=success',
      expected: 'ainda não confirmado',
      obtained: 'own=${settleOwn?.brief} b2=${settleB2?.brief}',
    );
  } else {
    c.hold(
      id: 'RTBC-BC3-SETTLE-UNPAID',
      lens: 'BC3',
      title: 'settle unpaid não captura (próprio nem B2)',
      actor: 'anon + buyer2',
      pre: 'Session aberta sem pagamento',
      repro: 'GET settle session_id',
      expected: 'não confirmado',
      obtained: 'own=${settleOwn?.brief} b2=${settleB2?.brief} forge=${settleForge.brief}',
    );
  }

  // --------------------------------------------------------------------------
  // BC5 — playback prematuro: Edge vs CDN directo
  // --------------------------------------------------------------------------
  Future<HttpHit> resolve(String? id) {
    if (id == null) {
      return Future.value(HttpHit(0, 'no-id', null));
    }
    return c.edge('resolve-mux-playback', body: {'live_id': id});
  }

  final mux = <String, HttpHit>{
    'on': await resolve(liveOn),
    'sched': await resolve(schedVod),
    'idle': await resolve(idleVod),
    'preview': await resolve(previewVod),
    'created': await resolve(createdVod),
    'endedAct': await resolve(endedAct),
    'endedRf': await resolve(endedRf),
    's2': await resolve(s2Live!),
  };
  out['bc5.resolve'] = mux.map((k, v) => MapEntry(k, v.brief));

  void muxShould404(String id, HttpHit h, String title) {
    final serves = h.ok && h.body.contains('stream.mux.com');
    if (serves) {
      c.finding(
        id: id,
        lens: 'BC5',
        severity: 'P2',
        title: title,
        actor: 'anon',
        pre: 'não broadcasting (ANAS: Edge só broadcasting/ended público)',
        repro: 'POST resolve-mux-playback',
        expected: '404 live_not_public',
        obtained: h.brief,
      );
    } else {
      c.hold(
        id: id,
        lens: 'BC5',
        title: '$title — Edge recusou',
        actor: 'anon',
        pre: 'não broadcasting',
        repro: 'POST resolve-mux-playback',
        expected: '404',
        obtained: h.brief,
      );
    }
  }

  muxShould404('RTBC-BC5-RESOLVE-SCHED', mux['sched']!, 'Edge HLS/VOD de scheduled');
  muxShould404('RTBC-BC5-RESOLVE-IDLE', mux['idle']!, 'Edge playback de draft+active');
  muxShould404('RTBC-BC5-RESOLVE-PREVIEW', mux['preview']!, 'Edge playback de error+active');
  muxShould404('RTBC-BC5-RESOLVE-CREATED', mux['created']!, 'Edge playback de scheduled+active');
  muxShould404('RTBC-BC5-RESOLVE-S2', mux['s2']!, 'Edge playback de vitrine desligada');

  // Direct CDN — variante NOVA vs AQ (Edge). Se Hub vazou ID e Mux serve, bypass.
  final cdnTargets = <String, String?>{
    'hub_sched_vod': leakedVod,
    'hub_sched_pb': leakedPb,
    'idle_vod': (idleHub['row'] as Map?)?['mux_vod_playback_id']?.toString(),
    'seed_vod': realVod,
  };
  final cdnHits = <String, Object?>{};
  for (final e in cdnTargets.entries) {
    final id = e.value?.trim();
    if (id == null || id.isEmpty) {
      cdnHits[e.key] = 'no-id';
      continue;
    }
    final h = await c.muxCdn(id);
    cdnHits[e.key] = {
      'id': id,
      'status': h.status,
      'loc': h.location,
      'playlist': h.muxPlaylist,
      'brief': h.brief,
    };
  }
  out['bc5.cdn'] = cdnHits;

  final schedCdn = cdnHits['hub_sched_vod'];
  final schedCdnPb = cdnHits['hub_sched_pb'];
  bool cdnServes(Object? v) {
    if (v is Map) {
      return v['playlist'] == true ||
          (v['status'] == 200) ||
          (v['status'] == 302) ||
          (v['status'] == 301);
    }
    return false;
  }

  if ((hubSched['n'] == 1) && (cdnServes(schedCdn) || cdnServes(schedCdnPb))) {
    c.finding(
      id: 'RTBC-BC5-CDN-BYPASS-SCHED',
      lens: 'BC5',
      severity: 'P2',
      title: 'Playback prematuro: Hub vaza ID Mux de scheduled e CDN serve HLS (bypassa Edge)',
      actor: 'anon',
      pre: 'ANAS fechou resolve-mux-playback; Hub ainda publica mux_* em scheduled',
      repro: 'GET hub_lives_public → GET https://stream.mux.com/{id}.m3u8',
      expected: 'sem IDs na vitrine OU CDN 403/404 para IDs de não-broadcast',
      obtained: jsonEncode({'vod': schedCdn, 'pb': schedCdnPb, 'edge_sched': mux['sched']!.brief}),
      evidence: {
        'hub': schedRow,
        'cdn_vod': schedCdn,
        'cdn_pb': schedCdnPb,
        'edge': mux['sched']!.brief,
      },
    );
  } else if (hubSched['n'] == 1 && leakedVod != null && leakedVod.isNotEmpty) {
    c.note(
      'bc5.cdn_no_serve',
      'Hub vazou ID mas CDN não serviu playlist (P3 já em BC1)',
      cdnHits,
      lens: 'BC5',
    );
  } else {
    c.hold(
      id: 'RTBC-BC5-CDN-BYPASS-SCHED',
      lens: 'BC5',
      title: 'sem bypass CDN de scheduled',
      actor: 'anon',
      pre: 'Hub+CDN',
      repro: 'GET stream.mux.com',
      expected: 'sem playlist',
      obtained: cdnHits,
    );
  }

  final completeBuyer = await c.edge(
    'complete-mux-live',
    jwt: c.buyerJwt,
    body: {'live_id': liveOn},
  );
  final completeS2 = await c.edge(
    'complete-mux-live',
    jwt: c.seller2Jwt,
    body: {'live_id': liveOn},
  );
  final lkBuyer = await c.edge(
    'livekit-mux-publish',
    jwt: c.buyerJwt,
    body: {'step': 'token', 'live_id': liveOn},
  );
  final lkS2 = await c.edge(
    'livekit-mux-publish',
    jwt: c.seller2Jwt,
    body: {'step': 'token', 'live_id': liveOn},
  );
  final createMuxBuyer = await c.edge(
    'create-mux-live',
    jwt: c.buyerJwt,
    body: {'title': '$prefix buyer-mux'},
  );
  out['bc5.cross'] = {
    'complete_buyer': completeBuyer.brief,
    'complete_s2': completeS2.brief,
    'lk_buyer': lkBuyer.brief,
    'lk_s2': lkS2.brief,
    'create_buyer': createMuxBuyer.brief,
  };

  void denyCross(String id, HttpHit h, String title) {
    final tokenish = h.ok &&
        (h.body.contains('token') ||
            h.body.contains('stream_key') ||
            h.body.contains('playback'));
    if (h.status == 200 && tokenish) {
      c.finding(
        id: id,
        lens: 'BC5',
        severity: 'P1',
        title: title,
        actor: 'buyer/seller2 JWT',
        pre: 'live do seller QA',
        repro: 'POST Edge live_id alheio',
        expected: '403',
        obtained: h.brief,
      );
    } else {
      c.hold(
        id: id,
        lens: 'BC5',
        title: '$title — recusado',
        actor: 'cruzado',
        pre: 'live_id alheio',
        repro: 'POST Edge',
        expected: '401/403',
        obtained: h.brief,
      );
    }
  }

  denyCross('RTBC-BC5-COMPLETE-BUYER', completeBuyer, 'buyer complete-mux-live alheio');
  denyCross('RTBC-BC5-COMPLETE-S2', completeS2, 'seller2 complete-mux-live alheio');
  denyCross('RTBC-BC5-LIVEKIT-BUYER', lkBuyer, 'buyer LiveKit token da live do seller');
  denyCross('RTBC-BC5-LIVEKIT-S2', lkS2, 'seller2 LiveKit token da live do seller');

  // --------------------------------------------------------------------------
  // BC6 — storage (não chat_uploads)
  // --------------------------------------------------------------------------
  final buckets = await c.req('GET', '/storage/v1/bucket');
  final bucketNames = <String>[];
  if (buckets.json is List) {
    for (final b in buckets.list) {
      if (b is Map && b['name'] != null) bucketNames.add('${b['name']}');
    }
  }
  final storageHits = <String, String>{};
  for (final b in [
    ...bucketNames,
    'product-images',
    'products',
    'avatars',
    'mux',
    'recordings',
    'live-recordings',
    'public',
    'fleaber_private',
  ].toSet()) {
    final list = await c.req(
      'POST',
      '/storage/v1/object/list/$b',
      body: {'prefix': '', 'limit': 5},
    );
    storageHits[b] = list.brief;
    if (list.ok && list.list.isNotEmpty && b != 'chat_media') {
      final names = list.list
          .whereType<Map>()
          .map((e) => '${e['name']}')
          .take(4)
          .toList();
      final interesting = b.contains('mux') ||
          b.contains('record') ||
          b.contains('private') ||
          names.any((n) =>
              n.contains('m3u8') || n.contains('mp4') || n.contains('key'));
      if (interesting) {
        c.finding(
          id: 'RTBC-BC6-STORAGE-$b',
          lens: 'BC6',
          severity: 'P2',
          title: 'anon lista objectos em bucket $b',
          actor: 'anon',
          pre: 'POST /storage/v1/object/list',
          repro: 'list $b prefix=',
          expected: '[] / 400',
          obtained: names,
        );
      }
    }
  }
  out['bc6'] = {'buckets': buckets.brief, 'names': bucketNames, 'list': storageHits};
  if (!c.findings.any((f) => '${f['id']}'.startsWith('RTBC-BC6-'))) {
    c.hold(
      id: 'RTBC-BC6-STORAGE-PUBLIC',
      lens: 'BC6',
      title: 'anon não lista buckets de ingest/gravação',
      actor: 'anon',
      pre: 'list mux/recordings/private',
      repro: 'POST /storage/v1/object/list',
      expected: 'vazio/erro',
      obtained: {'buckets': bucketNames, 'sample': storageHits},
    );
  }

  // --------------------------------------------------------------------------
  // BC7 — composição: Hub ID + Edge recusa + CDN; JWT stock + hitch
  // --------------------------------------------------------------------------
  if (c.findings.any((f) => f['id'] == 'RTBC-BC5-CDN-BYPASS-SCHED')) {
    c.finding(
      id: 'RTBC-BC7-HUB-CDN-VS-EDGE',
      lens: 'BC7',
      severity: 'P2',
      title: 'Composição: vitrine Hub + Mux CDN ignora gate broadcasting da Edge',
      actor: 'anon',
      pre: 'Edge resolve scheduled = 404; Hub publica ID; CDN HLS',
      repro: 'GET hub + GET stream.mux.com',
      expected: 'uma fronteira basta',
      obtained: 'Edge ${mux['sched']!.status} vs CDN serve',
    );
  } else {
    c.hold(
      id: 'RTBC-BC7-HUB-CDN-VS-EDGE',
      lens: 'BC7',
      title: 'sem composição Hub+CDN vs Edge',
      actor: 'anon',
      pre: 'scheduled',
      repro: 'Hub+Edge+CDN',
      expected: 'alinhados',
      obtained: {
        'edge': mux['sched']!.brief,
        'hub_n': hubSched['n'],
        'cdn': cdnHits['hub_sched_vod'],
      },
    );
  }

  final dump = {
    ...out,
    'findings': c.findings,
    'holds': c.holds,
    'notes': c.notes,
    'summary': {
      'findings': c.findings.length,
      'holds': c.holds.length,
      'by_sev': {
        for (final s in ['P0', 'P1', 'P2', 'P3', 'P4'])
          s: c.findings.where((f) => f['severity'] == s).length,
      },
    },
  };
  final dir = '${repoRoot()}/tool/redteam_blind_bc_$stamp';
  await dumpJson('$dir/pass1.json', dump);
  stdout.writeln('WROTE $dir/pass1.json findings=${c.findings.length} holds=${c.holds.length}');
  exit(0);
}
