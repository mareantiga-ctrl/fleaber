/// RED TEAM CEGO BI pass1 — Hub / Edge / Mux / tip / CORS / storage / FOMO.
/// Não corrige. Staging only.
import 'dart:io';

import '_rtbi.dart';

Future<void> main() async {
  final c = Rtbi.fromEnv(loadEnv());
  await DirectoryOut.ensure(c);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.ensureSeller3Unpublished();
  c.note('actors', 'jwt ready', {
    'b': c.buyerId,
    's': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
    's3': c.seller3Id,
  });

  // Real Mux playback IDs already in staging (CDN proof). Observation only.
  final existingVod = await c.rest(
    'GET',
    'lives?mux_vod_playback_id=not.is.null&select=id,status,mux_vod_playback_id,mux_playback_id&limit=3',
    service: true,
  );
  final vodId = existingVod.list
      .whereType<Map>()
      .map((m) => m['mux_vod_playback_id']?.toString())
      .whereType<String>()
      .where((s) => s.length > 8)
      .firstOrNull;
  final livePbId = existingVod.list
      .whereType<Map>()
      .map((m) => m['mux_playback_id']?.toString())
      .whereType<String>()
      .where((s) => s.length > 8)
      .firstOrNull;
  c.note('mux.seed', 'existing playback ids', {
    'vod': vodId,
    'livePb': livePbId,
    'n': existingVod.list.length,
  }, lens: 'BI5');

  // ---------------------------------------------------------------------------
  // Fixtures — S2 published Hub
  // ---------------------------------------------------------------------------
  final liveAir = await c.insertLive(
    status: 'live',
    active: true,
    title: '$prefix AIR',
    muxPlayback: livePbId ?? 'pbLiveFakeRtbi',
    muxVod: vodId,
  );
  final liveSched = await c.insertLive(
    status: 'scheduled',
    active: true,
    title: '$prefix SCHED',
    muxPlayback: livePbId ?? 'pbSchedFakeRtbi',
    muxVod: vodId,
  );
  final liveSchedOff = await c.insertLive(
    status: 'scheduled',
    active: false,
    title: '$prefix SCHED-OFF',
    muxPlayback: livePbId,
    muxVod: vodId,
  );
  final liveEnded = await c.insertLive(
    status: 'ended',
    active: false,
    title: '$prefix ENDED',
    muxPlayback: livePbId,
    muxVod: vodId,
  );
  final liveDraftOn = await c.insertLive(
    status: 'draft',
    active: true,
    title: '$prefix DRAFT-ON',
    muxPlayback: livePbId,
    muxVod: vodId,
  );
  final liveErrorOn = await c.insertLive(
    status: 'error',
    active: true,
    title: '$prefix ERROR-ON',
    muxPlayback: livePbId,
    muxVod: vodId,
  );
  final liveAoVivo = await c.insertLive(
    status: 'ao_vivo',
    active: true,
    title: '$prefix AOVIVO',
    muxPlayback: livePbId,
    muxVod: vodId,
  );
  final liveIdle = await c.insertLive(
    status: 'idle',
    active: true,
    title: '$prefix IDLE',
    muxPlayback: livePbId,
    muxVod: vodId,
  );
  final livePaused = await c.insertLive(
    status: 'paused',
    active: false,
    title: '$prefix PAUSED',
    muxPlayback: livePbId,
    muxVod: vodId,
  );
  final liveLiveOff = await c.insertLive(
    status: 'live',
    active: false,
    title: '$prefix LIVE-OFF',
    muxPlayback: livePbId,
    muxVod: vodId,
  );

  final itemAir = liveAir == null
      ? null
      : await c.insertItem(liveId: liveAir, qty: 4);
  final itemSched = liveSched == null
      ? null
      : await c.insertItem(liveId: liveSched, qty: 5);
  final itemEnded = liveEnded == null
      ? null
      : await c.insertItem(liveId: liveEnded, qty: 2);
  if (liveSched != null && itemSched != null) {
    await c.insertPendingRes(
      liveId: liveSched,
      liveItemId: itemSched,
      buyer: c.buyerId,
    );
  }
  if (liveEnded != null && itemEnded != null) {
    await c.insertPendingRes(
      liveId: liveEnded,
      liveItemId: itemEnded,
      buyer: c.buyer2Id,
    );
  }

  Future<Map<String, dynamic>> hubSelect(String view, String? id) async {
    if (id == null) return {'id': null};
    final anon = await c.rest(
      'GET',
      '$view?id=eq.$id&select=id,status,is_active,mux_playback_id,mux_vod_playback_id,title,seller_handle',
    );
    return {
      'status': anon.status,
      'n': anon.list.length,
      'row': anon.map,
    };
  }

  // ===========================================================================
  // BI1 — Hub views + FOMO + handle_suggested + embed
  // ===========================================================================
  final hubCases = <String, String?>{
    'air': liveAir,
    'sched': liveSched,
    'schedOff': liveSchedOff,
    'ended': liveEnded,
    'draftOn': liveDraftOn,
    'errorOn': liveErrorOn,
    'aoVivo': liveAoVivo,
    'idle': liveIdle,
    'paused': livePaused,
    'liveOff': liveLiveOff,
  };

  final hubPublic = <String, dynamic>{};
  final hubDisc = <String, dynamic>{};
  for (final e in hubCases.entries) {
    hubPublic[e.key] = await hubSelect('hub_lives_public', e.value);
    hubDisc[e.key] = await hubSelect('hub_lives_discovery_public', e.value);
  }
  c.note('bi1.hub_public', 'hub_lives_public por estado', hubPublic, lens: 'BI1');
  c.note('bi1.hub_disc', 'hub_lives_discovery_public por estado', hubDisc,
      lens: 'BI1');

  bool listed(Map<String, dynamic> pack) =>
      (pack['n'] as int? ?? 0) > 0 && pack['row'] is Map;
  String? col(Map<String, dynamic> pack, String k) {
    final row = pack['row'];
    if (row is Map) return row[k]?.toString();
    return null;
  }

  // Closed exactos (não contar): draft/error na grelha hub_lives_public; VOD scheduled na view pública.
  if (listed(hubPublic['draftOn'] as Map<String, dynamic>)) {
    c.note('bi1.residual_draft_grid', 'draft ainda na hub_lives_public (exacto fechado)',
        hubPublic['draftOn'], lens: 'BI1');
  } else {
    c.block('bi1.draft_grid', 'BI1', 'draft+active fora de hub_lives_public',
        hubPublic['draftOn']);
  }
  if (listed(hubPublic['errorOn'] as Map<String, dynamic>)) {
    c.note('bi1.residual_error_grid', 'error ainda na hub_lives_public',
        hubPublic['errorOn'], lens: 'BI1');
  } else {
    c.block('bi1.error_grid', 'BI1', 'error+active fora de hub_lives_public',
        hubPublic['errorOn']);
  }

  final schedPubVod =
      col(hubPublic['sched'] as Map<String, dynamic>, 'mux_vod_playback_id');
  if (listed(hubPublic['sched'] as Map<String, dynamic>) &&
      schedPubVod != null &&
      schedPubVod.isNotEmpty &&
      schedPubVod != 'null') {
    c.note('bi1.residual_sched_vod_public',
        'hub_lives_public scheduled ainda expõe VOD (exacto)', schedPubVod,
        lens: 'BI1');
  } else {
    c.block('bi1.sched_vod_public', 'BI1',
        'hub_lives_public scheduled sem mux_vod', schedPubVod ?? 'null');
  }

  // NOVO: discovery feed ainda selecciona playback cru.
  final schedDisc = hubDisc['sched'] as Map<String, dynamic>;
  final schedDiscVod = col(schedDisc, 'mux_vod_playback_id');
  final schedDiscLive = col(schedDisc, 'mux_playback_id');
  if (listed(schedDisc) &&
      schedDiscVod != null &&
      schedDiscVod.isNotEmpty &&
      schedDiscVod != 'null') {
    HttpHit? cdn;
    if (vodId != null && schedDiscVod == vodId) {
      cdn = await c.muxCdn(schedDiscVod);
    } else if (schedDiscVod.length > 8) {
      cdn = await c.muxCdn(schedDiscVod);
    }
    c.hold(
      id: 'P2-BI1/BI7-disc-sched-vod',
      lens: 'BI1',
      severity: 'P2',
      title:
          'hub_lives_discovery_public lista scheduled+active com mux_vod_playback_id cru (vitrine pública já anula)',
      actor: 'anon',
      pre: 'S2 hub_published; live scheduled is_active=true com VOD real copiado',
      repro:
          'GET hub_lives_discovery_public?id=eq.$liveSched&select=mux_vod_playback_id',
      expected:
          'scheduled não publica VOD; playback só via Edge em broadcasting/ended público',
      obtained: {
        'discovery_listed': true,
        'mux_vod': schedDiscVod,
        'mux_playback': schedDiscLive,
        'hub_lives_public_vod': schedPubVod,
        'cdn': cdn?.brief,
        'cdn_extm3u': cdn?.hasExtm3u,
      },
      evidence: {
        'live_id': liveSched,
        'cdn_status': cdn?.status,
      },
    );
  } else if (listed(schedDisc)) {
    c.note('bi1.disc_sched_no_vod', 'discovery lista scheduled sem VOD', schedDisc,
        lens: 'BI1');
  } else {
    c.block('bi1.disc_sched', 'BI1', 'scheduled+active fora de discovery',
        schedDisc);
  }

  // ao_vivo / idle / live-off nas duas views
  for (final k in ['aoVivo', 'idle', 'liveOff', 'paused']) {
    final pub = listed(hubPublic[k] as Map<String, dynamic>);
    final disc = listed(hubDisc[k] as Map<String, dynamic>);
    c.note('bi1.state.$k', 'listed pub=$pub disc=$disc', {
      'pub': hubPublic[k],
      'disc': hubDisc[k],
    }, lens: 'BI1');
  }

  // FOMO RPC — scheduled / ended / air / draft
  Future<HttpHit> fomo(String? id, {String? jwt}) =>
      c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': id}, jwt: jwt);

  final fomoAnonSched = await fomo(liveSched);
  final fomoAnonEnded = await fomo(liveEnded);
  final fomoAnonAir = await fomo(liveAir);
  final fomoAnonDraft = await fomo(liveDraftOn);
  final fomoBuyerEnded = await fomo(liveEnded, jwt: c.buyerJwt);
  final fomoSellerEnded = await fomo(liveEnded, jwt: c.seller2Jwt);
  c.note('bi1.fomo.sched', 'FOMO anon scheduled', fomoAnonSched, lens: 'BI1');
  c.note('bi1.fomo.ended', 'FOMO anon ended', fomoAnonEnded, lens: 'BI1');
  c.note('bi1.fomo.air', 'FOMO anon air', fomoAnonAir, lens: 'BI1');
  c.note('bi1.fomo.draft', 'FOMO anon draft', fomoAnonDraft, lens: 'BI1');
  c.note('bi1.fomo.ended.b', 'FOMO buyer ended', fomoBuyerEnded, lens: 'BI1');
  c.note('bi1.fomo.ended.s2', 'FOMO seller2 ended', fomoSellerEnded, lens: 'BI1');

  Map<String, dynamic>? fomoMap(HttpHit h) => h.map;
  List itemsOf(HttpHit h) {
    final m = fomoMap(h);
    final items = m?['items'];
    return items is List ? items : const [];
  }

  int? pendingOf(HttpHit h) {
    final items = itemsOf(h);
    if (items.isEmpty) return null;
    final first = items.first;
    if (first is Map) return (first['pending_queue_count'] as num?)?.toInt();
    return null;
  }

  // FOMO em scheduled: ok=true + fila pending (DEFINER lê live_reservation_requests)
  if (fomoAnonSched.map?['ok'] == true && (pendingOf(fomoAnonSched) ?? 0) > 0) {
    c.hold(
      id: 'P2-BI1-fomo-scheduled-queue',
      lens: 'BI1',
      severity: 'P2',
      title:
          'FOMO SECURITY DEFINER revela fila de reservas e itens de um directo scheduled (não no ar)',
      actor: 'anon',
      pre: 'scheduled+active na hub_lives_public; 1 pending reservation',
      repro: 'POST rpc/batata_hub_live_fomo_snapshot p_live_id=scheduled',
      expected: 'live_not_public ou itens sem oráculo de fila/stock',
      obtained: fomoAnonSched.map,
    );
  } else if (fomoAnonSched.map?['ok'] == true) {
    c.note('bi1.fomo.sched.ok_no_queue', 'FOMO scheduled ok sem pending',
        fomoAnonSched.map, lens: 'BI1');
  } else {
    c.block('bi1.fomo.sched', 'BI1', 'FOMO scheduled recusado', fomoAnonSched);
  }

  if (fomoAnonEnded.map?['ok'] == true) {
    final leakedStock = itemsOf(fomoAnonEnded).any((it) {
      if (it is! Map) return false;
      final aq = it['available_qty'];
      final st = '${it['status']}';
      return aq is num && aq > 0;
    });
    if (leakedStock) {
      c.hold(
        id: 'P2-BI1-fomo-ended-stock',
        lens: 'BI1',
        severity: 'P2',
        title: 'FOMO anon devolve available_qty real em directo ended',
        actor: 'anon',
        pre: 'ended + live_item qty=2',
        repro: 'rpc batata_hub_live_fomo_snapshot ended',
        expected: 'stock gated (not_found) → 0 / live_not_public',
        obtained: fomoAnonEnded.map,
      );
    } else {
      c.note('bi1.fomo.ended.gated_stock', 'FOMO ended ok mas stock 0/gated', {
        'pending': pendingOf(fomoAnonEnded),
        'items': itemsOf(fomoAnonEnded),
      }, lens: 'BI1');
      if ((pendingOf(fomoAnonEnded) ?? 0) > 0) {
        c.hold(
          id: 'P3-BI1-fomo-ended-queue',
          lens: 'BI1',
          severity: 'P3',
          title: 'FOMO anon em gravado ainda conta pending_queue_count',
          actor: 'anon',
          pre: 'ended + 1 pending B2',
          repro: 'rpc batata_hub_live_fomo_snapshot ended',
          expected: 'sem oráculo de fila em gravado',
          obtained: {
            'pending': pendingOf(fomoAnonEnded),
            'items': itemsOf(fomoAnonEnded),
          },
        );
      }
    }
  }

  // Stock RPC directo
  Future<void> stockProbe(String label, String? itemId, {String? jwt}) async {
    if (itemId == null) return;
    final h = await c.rpc('batata_live_item_stock', {'p_live_item_id': itemId},
        jwt: jwt);
    c.note('bi1.stock.$label', 'stock $label', h, lens: 'BI1');
  }

  await stockProbe('anon.air', itemAir);
  await stockProbe('anon.sched', itemSched);
  await stockProbe('anon.ended', itemEnded);
  await stockProbe('buyer.ended', itemEnded, jwt: c.buyerJwt);
  await stockProbe('s2.ended', itemEnded, jwt: c.seller2Jwt);
  await stockProbe('s1.ended_other', itemEnded, jwt: c.sellerJwt);

  final qtyAnon = itemEnded == null
      ? null
      : await c.rpc('batata_live_item_total_qty', {'p_live_item_id': itemEnded});
  c.note('bi1.total_qty.anon', 'total_qty anon ended (exacto — não contar)',
      qtyAnon, lens: 'BI1');
  if (qtyAnon != null && qtyAnon.ok && qtyAnon.json is num) {
    c.note('bi1.residual_total_qty', 'anon total_qty ainda devolve número',
        qtyAnon.json, lens: 'BI1');
  } else {
    c.block('bi1.total_qty', 'BI1', 'anon total_qty recusado/revogado', qtyAnon);
  }

  // handle_suggested unpublished
  final resolveSug = await c.rpc('batata_resolve_handle', {
    'p_handle': 'rtbi1820s3sug',
  });
  final resolveEmpty = await c.rpc('batata_resolve_handle', {
    'p_handle': 'nao-existe-rtbi-xyz',
  });
  c.note('bi1.handle.sug', 'resolve handle_suggested unpublished', resolveSug,
      lens: 'BI1');
  c.note('bi1.handle.miss', 'resolve missing', resolveEmpty, lens: 'BI1');
  final foundSug = resolveSug.map?['found'] == true;
  final pidSug = resolveSug.map?['profile_id']?.toString();
  if (foundSug && pidSug == c.seller3Id) {
    c.hold(
      id: 'P2-BI1-handle-suggested',
      lens: 'BI1',
      severity: 'P2',
      title:
          'batata_resolve_handle enumera UUID de loja desligada via handle_suggested',
      actor: 'anon',
      pre: 'S3 hub_published=false handle=null handle_suggested=rtbi1820s3sug',
      repro: 'POST rpc/batata_resolve_handle p_handle=rtbi1820s3sug',
      expected: 'found=false (KLM-2A: só publicado ou directo no ar)',
      obtained: resolveSug.map,
    );
  } else {
    c.block('bi1.handle.sug', 'BI1', 'handle_suggested unpublished não resolve',
        resolveSug);
  }

  // Embed lives(*) keys
  final embeds = <String, HttpHit>{
    'hub_lives_lives': await c.rest(
      'GET',
      'hub_lives_public?id=eq.$liveAir&select=id,lives(*)',
    ),
    'hub_items_lives': await c.rest(
      'GET',
      'hub_live_items_public?live_id=eq.$liveAir&select=id,lives(*)',
    ),
    'hub_items_li': await c.rest(
      'GET',
      'hub_live_items_public?live_id=eq.$liveAir&select=id,live_items(*)',
    ),
    'hub_profiles': await c.rest(
      'GET',
      'hub_profiles_public?id=eq.${c.seller2Id}&select=id,profiles(*)',
    ),
    'lives_anon': await c.rest(
      'GET',
      'lives?id=eq.$liveSched&select=id,status,mux_playback_id,mux_vod_playback_id,mux_stream_key,stream_key,mux_live_id',
    ),
    'lives_buyer_sched': await c.rest(
      'GET',
      'lives?id=eq.$liveSched&select=id,status,mux_playback_id,mux_vod_playback_id,mux_stream_key,stream_key,mux_live_id,mux_asset_id,livekit_room_name',
      jwt: c.buyerJwt,
    ),
    'lives_buyer_draft': await c.rest(
      'GET',
      'lives?id=eq.$liveDraftOn&select=id,status,is_active,mux_vod_playback_id,mux_stream_key',
      jwt: c.buyerJwt,
    ),
    'lives_s2_own': await c.rest(
      'GET',
      'lives?id=eq.$liveSched&select=id,mux_stream_key,stream_key,mux_live_id',
      jwt: c.seller2Jwt,
    ),
  };
  for (final e in embeds.entries) {
    c.note('bi1.embed.${e.key}', e.key, e.value, lens: 'BI1');
  }

  bool leakedKey(HttpHit h) {
    final b = h.body.toLowerCase();
    return b.contains('mux_stream_key') &&
        !b.contains('permission denied') &&
        h.ok &&
        (h.map?['mux_stream_key'] != null ||
            h.body.contains('"mux_stream_key":"'));
  }

  final buyerSched = embeds['lives_buyer_sched']!;
  final buyerVod = buyerSched.map?['mux_vod_playback_id']?.toString();
  final buyerLivePb = buyerSched.map?['mux_playback_id']?.toString();
  if (buyerSched.ok &&
      buyerVod != null &&
      buyerVod.isNotEmpty &&
      buyerVod != 'null') {
    final cdn = vodId != null ? await c.muxCdn(buyerVod) : null;
    c.hold(
      id: 'P2-BI1/BI7-lives-jwt-vod',
      lens: 'BI7',
      severity: 'P2',
      title:
          'JWT comprador lê mux_vod_playback_id na tabela lives de um scheduled (CDN não passa na Edge)',
      actor: 'buyer JWT',
      pre: 'RLS lives_select_feed_or_owner inclui scheduled; grant colunas playback',
      repro:
          'GET /rest/v1/lives?id=eq.$liveSched&select=mux_vod_playback_id (JWT B1)',
      expected: 'anon/buyer não lêem VOD de scheduled; só views Hub filtradas',
      obtained: {
        'row': buyerSched.map,
        'cdn': cdn?.brief,
        'cdn_extm3u': cdn?.hasExtm3u,
        'anon_lives': embeds['lives_anon']!.brief,
      },
      evidence: {'live_id': liveSched, 'vod': buyerVod, 'live_pb': buyerLivePb},
    );
  } else {
    c.block('bi1.lives_jwt_vod', 'BI7',
        'buyer JWT não lê VOD scheduled em lives', buyerSched);
  }

  if (leakedKey(embeds['lives_buyer_sched']!) ||
      leakedKey(embeds['lives_s2_own']!) ||
      leakedKey(embeds['lives_anon']!)) {
    c.hold(
      id: 'P1-BI5-stream-key-rest',
      lens: 'BI5',
      severity: 'P1',
      title: 'REST expõe mux_stream_key / stream_key',
      actor: 'jwt/anon',
      pre: 'column grants 003b',
      repro: 'GET lives?select=mux_stream_key',
      expected: '42501 / coluna omitida',
      obtained: {
        'buyer': embeds['lives_buyer_sched']!.brief,
        's2': embeds['lives_s2_own']!.brief,
        'anon': embeds['lives_anon']!.brief,
      },
    );
  } else {
    c.block('bi5.stream_key_rest', 'BI5', 'stream_key REST omitido/denied', {
      'buyer': embeds['lives_buyer_sched']!.brief,
      's2': embeds['lives_s2_own']!.brief,
    });
  }

  final embedBodies = embeds.values.map((h) => h.body).join(' ');
  if (RegExp(r'"mux_stream_key"\s*:\s*"[^"]+"').hasMatch(embedBodies) ||
      RegExp(r'"stream_key"\s*:\s*"[^"]+"').hasMatch(embedBodies)) {
    c.hold(
      id: 'P1-BI5-embed-keys',
      lens: 'BI5',
      severity: 'P1',
      title: 'Embed PostgREST lives(*) / live_items(*) devolve stream key',
      actor: 'anon',
      pre: 'select embed nas views Hub',
      repro: 'GET hub_lives_public?select=id,lives(*)',
      expected: '42501 ou sem colunas secretas',
      obtained: {
        for (final e in embeds.entries) e.key: e.value.brief,
      },
    );
  } else {
    c.block('bi5.embed_keys', 'BI5', 'embed sem stream keys', {
      'hub_lives_lives': embeds['hub_lives_lives']!.brief,
      'hub_items_li': embeds['hub_items_li']!.brief,
    });
  }

  // ===========================================================================
  // BI5 — resolve-mux estados novos + complete-mux cruzado + LiveKit + create
  // ===========================================================================
  Future<HttpHit> resolveMux(String? id, {String? jwt, String? origin}) {
    return c.edge(
      'resolve-mux-playback',
      {'live_id': id, 'buyer_id': c.buyer2Id, 'amount': 1},
      jwt: jwt,
      extra: origin == null ? null : {'Origin': origin},
    );
  }

  final muxHits = <String, HttpHit>{};
  for (final e in hubCases.entries) {
    muxHits[e.key] = await resolveMux(e.value);
    c.note('bi5.resolve.${e.key}', 'resolve-mux ${e.key}', muxHits[e.key],
        lens: 'BI5');
  }

  bool muxGavePlayback(HttpHit h) =>
      h.ok &&
      (h.map?['playback_id'] != null || h.map?['playback_url'] != null);

  for (final k in ['sched', 'schedOff', 'draftOn', 'errorOn', 'idle', 'paused', 'liveOff']) {
    final h = muxHits[k]!;
    if (muxGavePlayback(h)) {
      c.hold(
        id: 'P2-BI5-resolve-$k',
        lens: 'BI5',
        severity: 'P2',
        title: 'resolve-mux-playback devolve playback em estado $k',
        actor: 'anon',
        pre: 'live status=$k',
        repro: 'POST resolve-mux-playback live_id',
        expected: '404 live_not_public',
        obtained: h.map ?? h.brief,
      );
    } else {
      c.block('bi5.resolve.$k', 'BI5', 'resolve-mux $k recusado', h);
    }
  }

  // complete-mux cruzado
  final cmBuyer = await c.edge(
    'complete-mux-live',
    {'live_id': liveAir},
    jwt: c.buyerJwt,
  );
  final cmS1 = await c.edge(
    'complete-mux-live',
    {'live_id': liveAir},
    jwt: c.sellerJwt,
  );
  final cmAnon = await c.edge('complete-mux-live', {'live_id': liveAir});
  c.note('bi5.cm.buyer', 'complete-mux buyer', cmBuyer, lens: 'BI5');
  c.note('bi5.cm.s1', 'complete-mux seller1 vs live S2', cmS1, lens: 'BI5');
  c.note('bi5.cm.anon', 'complete-mux anon', cmAnon, lens: 'BI5');
  if (cmBuyer.ok || cmS1.ok || (cmAnon.ok && cmAnon.status != 401)) {
    c.hold(
      id: 'P1-BI5-complete-mux-cruzado',
      lens: 'BI5',
      severity: 'P1',
      title: 'complete-mux-live aceite por não-dono',
      actor: 'buyer/seller1/anon',
      pre: 'live S2',
      repro: 'POST complete-mux-live live_id S2',
      expected: '401/403',
      obtained: {
        'buyer': cmBuyer.brief,
        's1': cmS1.brief,
        'anon': cmAnon.brief,
      },
    );
  } else {
    c.block('bi5.complete_mux', 'BI5', 'complete-mux cruzado 401/403', {
      'buyer': cmBuyer.brief,
      's1': cmS1.brief,
      'anon': cmAnon.brief,
    });
  }

  final lkBuyer = await c.edge(
    'livekit-mux-publish',
    {'step': 'token', 'live_id': liveAir},
    jwt: c.buyerJwt,
  );
  final lkS1 = await c.edge(
    'livekit-mux-publish',
    {'step': 'token', 'live_id': liveAir},
    jwt: c.sellerJwt,
  );
  c.note('bi5.lk.buyer', 'livekit token buyer', lkBuyer, lens: 'BI5');
  c.note('bi5.lk.s1', 'livekit token seller1', lkS1, lens: 'BI5');
  if (lkBuyer.ok || lkS1.ok) {
    c.hold(
      id: 'P1-BI5-livekit-cruzado',
      lens: 'BI5',
      severity: 'P1',
      title: 'livekit-mux-publish token/egress a não-dono',
      actor: 'buyer/seller1',
      pre: 'live S2',
      repro: 'POST livekit-mux-publish step=token',
      expected: '403',
      obtained: {'buyer': lkBuyer.brief, 's1': lkS1.brief},
    );
  } else {
    c.block('bi5.livekit', 'BI5', 'LiveKit cruzado recusado', {
      'buyer': lkBuyer.brief,
      's1': lkS1.brief,
    });
  }

  final createMuxBuyer = await c.edge(
    'create-mux-live',
    {'title': '$prefix hijack mux'},
    jwt: c.buyerJwt,
  );
  c.note('bi5.create.buyer', 'create-mux buyer', createMuxBuyer, lens: 'BI5');
  if (createMuxBuyer.ok) {
    c.hold(
      id: 'P1-BI5-create-mux-buyer',
      lens: 'BI5',
      severity: 'P1',
      title: 'comprador cria live Mux',
      actor: 'buyer JWT',
      pre: 'user_type buyer',
      repro: 'POST create-mux-live',
      expected: '403',
      obtained: createMuxBuyer.map ?? createMuxBuyer.brief,
    );
  } else {
    c.block('bi5.create_mux_buyer', 'BI5', 'create-mux buyer recusado',
        createMuxBuyer);
  }

  // ===========================================================================
  // BI2 — CORS + Connect web_return_origin IP/decimal
  // ===========================================================================
  final corsOrigins = [
    'https://evil.com',
    'null',
    'https://fleaber.pt.evil.com',
    'https://attacker.fleaber.pt',
    'https://fleaber.pt',
    'http://127.0.0.1:4173',
    'chrome-extension://abc',
  ];
  for (final o in corsOrigins) {
    final h = await c.edge(
      'resolve-mux-playback',
      {'live_id': liveEnded},
      extra: {'Origin': o},
    );
    c.note('bi2.cors.$o', 'CORS Origin=$o', h, lens: 'BI2');
    final acao = h.acao ?? '';
    if (o != 'https://fleaber.pt' &&
        !o.startsWith('http://127.0.0.1') &&
        acao.contains(o) &&
        o != 'null') {
      c.hold(
        id: 'P2-BI2-cors-reflect',
        lens: 'BI2',
        severity: 'P2',
        title: 'CORS reflecte Origin hostil',
        actor: 'browser',
        pre: 'Origin=$o',
        repro: 'POST resolve-mux-playback Origin hostil',
        expected: 'Allow-Origin fleaber.pt ou omitido — nunca evil',
        obtained: h.brief,
      );
    }
  }
  c.block('bi2.cors_baseline', 'BI2', 'CORS origins exercitados (ver notes)',
      corsOrigins.join(','));

  final originVariants = <String, String>{
    'decimal': 'https://2130706433',
    '127.1': 'https://127.1',
    '0x7f': 'https://0x7f000001',
    'octal': 'https://0177.0.0.1',
    'ipv6': 'https://[::1]',
    'localhost': 'https://localhost',
    'loop_https': 'https://127.0.0.1',
    'evil': 'https://evil.com',
    'sub': 'https://attacker.fleaber.pt',
    'userinfo': 'https://fleaber.pt@evil.com',
    'dot': 'https://fleaber.pt.',
  };
  for (final e in originVariants.entries) {
    final h = await c.edge(
      'create-connect-account',
      null,
      method: 'GET',
      jwt: c.seller2Jwt,
      qs: 'web_return_origin=${Uri.encodeQueryComponent(e.value)}',
    );
    c.note('bi2.connect.${e.key}', 'Connect GET ${e.key} loc=${h.location}', h,
        lens: 'BI2');
    final loc = h.location ?? '';
    final hostile = loc.contains('evil.com') ||
        loc.contains('2130706433') ||
        loc.contains('0x7f') ||
        loc.contains('0177') ||
        (e.key == 'decimal' &&
            h.status == 303 &&
            (loc.contains('127.0.0.1') || loc.contains('localhost'))) ||
        (e.key == '127.1' &&
            h.status == 303 &&
            (loc.contains('127.0.0.1') || loc.contains('localhost')));
    // loop_https / localhost are allowlisted on purpose — not a finding unless
    // decimal/127.1 canonicalize into them (open-redirect from non-allowlisted host).
    if (hostile && (e.key == 'decimal' || e.key == '127.1' || e.key == '0x7f' || e.key == 'octal' || e.key == 'evil' || e.key == 'sub' || e.key == 'userinfo')) {
      c.hold(
        id: 'P2-BI2-connect-${e.key}',
        lens: 'BI2',
        severity: 'P2',
        title:
            'Connect GET web_return_origin=${e.value} → Location $loc',
        actor: 'anon/browser',
        pre: 'GET create-connect-account?web_return_origin=',
        repro: 'GET functions/v1/create-connect-account?web_return_origin=${e.value}',
        expected: 'HTML app / sem Location hostil; IP decimal não canonicaliza para loopback allowlisted',
        obtained: h.brief,
      );
    }
  }

  final connectPostEvil = await c.edge(
    'create-connect-account',
    {
      'web_return_origin': 'https://evil.com',
      'return_url': 'https://evil.com/x',
      'refresh_url': 'https://evil.com/y',
      'user_id': c.buyerId,
      'amount': 1,
    },
    jwt: c.seller2Jwt,
  );
  c.note('bi2.connect.post', 'Connect POST evil origin + user_id alheio',
      connectPostEvil, lens: 'BI2');

  // ===========================================================================
  // BI3 / BI4 — tip unpaid B2, tip_id, amount spoof, GET settle oráculo
  // ===========================================================================
  final tipAir = await c.edge(
    'create-live-tip-checkout',
    {
      'live_id': liveAir,
      'seller_id': c.seller2Id,
      'amount_eur': 1,
      'tip_id': '00000000-0000-0000-0000-000000000001',
      'buyer_id': c.buyer2Id,
      'web_return_origin': 'https://evil.com',
    },
    jwt: c.buyerJwt,
  );
  c.note('bi3.tip.tip_id', 'tip com tip_id cliente', tipAir, lens: 'BI3');
  if (tipAir.ok) {
    c.hold(
      id: 'P1-BI3-tip-id-cliente',
      lens: 'BI3',
      severity: 'P1',
      title: 'create-live-tip-checkout aceita tip_id do cliente',
      actor: 'buyer JWT',
      pre: 'live broadcasting S2',
      repro: 'POST create-live-tip-checkout tip_id alheio',
      expected: '400 Client tip_id is not allowed',
      obtained: tipAir.map ?? tipAir.brief,
    );
  } else {
    c.block('bi3.tip_id', 'BI3', 'tip_id cliente recusado', tipAir);
  }

  final tipOk = await c.edge(
    'create-live-tip-checkout',
    {
      'live_id': liveAir,
      'seller_id': c.seller2Id,
      'amount_eur': 1,
      'web_return_origin': 'https://2130706433',
      'playback_id': 'attackerPlayback',
    },
    jwt: c.buyerJwt,
  );
  c.note('bi3.tip.ok', 'tip 1€ broadcasting + decimal origin', tipOk, lens: 'BI3');
  final tipSession = tipOk.map?['checkoutSessionId']?.toString();
  final tipIdCreated = tipOk.map?['tipId']?.toString();
  if (tipIdCreated != null) c.createdTipIds.add(tipIdCreated);

  final tipSched = await c.edge(
    'create-live-tip-checkout',
    {
      'live_id': liveSched,
      'seller_id': c.seller2Id,
      'amount_eur': 1,
    },
    jwt: c.buyerJwt,
  );
  c.note('bi3.tip.sched', 'tip scheduled', tipSched, lens: 'BI3');
  if (tipSched.ok) {
    c.hold(
      id: 'P1-BI3-tip-scheduled',
      lens: 'BI3',
      severity: 'P1',
      title: 'gorjeta Checkout Session com directo scheduled (não broadcasting)',
      actor: 'buyer JWT',
      pre: 'scheduled+active',
      repro: 'POST create-live-tip-checkout live scheduled',
      expected: '400 Tips only allowed while broadcasting',
      obtained: tipSched.map ?? tipSched.brief,
    );
  } else {
    c.block('bi3.tip_sched', 'BI3', 'tip scheduled recusado', tipSched);
  }

  final tipEnded = await c.edge(
    'create-live-tip-checkout',
    {
      'live_id': liveEnded,
      'seller_id': c.seller2Id,
      'amount_eur': 1,
    },
    jwt: c.buyerJwt,
  );
  c.note('bi3.tip.ended', 'tip ended', tipEnded, lens: 'BI3');
  if (tipEnded.ok) {
    c.hold(
      id: 'P1-BI3-tip-ended',
      lens: 'BI3',
      severity: 'P1',
      title: 'gorjeta em directo ended',
      actor: 'buyer JWT',
      pre: 'ended',
      repro: 'POST create-live-tip-checkout ended',
      expected: '400 broadcasting',
      obtained: tipEnded.brief,
    );
  } else {
    c.block('bi3.tip_ended', 'BI3', 'tip ended recusado', tipEnded);
  }

  final tipWrongSeller = await c.edge(
    'create-live-tip-checkout',
    {
      'live_id': liveAir,
      'seller_id': c.sellerId,
      'amount_eur': 1,
    },
    jwt: c.buyerJwt,
  );
  c.note('bi3.tip.wrong_seller', 'tip seller ≠ owner', tipWrongSeller, lens: 'BI3');
  if (tipWrongSeller.ok) {
    c.hold(
      id: 'P1-BI3-tip-seller-swap',
      lens: 'BI3',
      severity: 'P1',
      title: 'gorjeta credita seller_id que não é dono da live',
      actor: 'buyer JWT',
      pre: 'live S2, body seller_id=S1',
      repro: 'POST create-live-tip-checkout seller_id alheio',
      expected: '400 Tip seller does not own this live',
      obtained: tipWrongSeller.brief,
    );
  } else {
    c.block('bi3.tip_seller_swap', 'BI3', 'seller swap recusado', tipWrongSeller);
  }

  if (tipSession != null) {
    final settleB2 = await c.edge(
      'create-live-tip-checkout',
      null,
      method: 'GET',
      jwt: c.buyer2Jwt,
      qs: 'checkout_return=success&session_id=$tipSession',
    );
    final settleAnon = await c.edge(
      'create-live-tip-checkout',
      null,
      method: 'GET',
      qs: 'checkout_return=success&session_id=$tipSession',
    );
    c.note('bi3.settle.b2', 'GET settle unpaid B2', settleB2, lens: 'BI3');
    c.note('bi3.settle.anon', 'GET settle unpaid anon', settleAnon, lens: 'BI3');
    final captured = settleB2.body.toLowerCase().contains('pagamento recebido') ||
        settleB2.status == 303 ||
        settleAnon.status == 303;
    if (captured) {
      c.hold(
        id: 'P0-BI3-tip-unpaid-capture',
        lens: 'BI3',
        severity: 'P0',
        title: 'GET settle captura/regista gorjeta unpaid (B2 ou anon)',
        actor: 'B2 JWT / anon',
        pre: 'Session B1 unpaid',
        repro: 'GET create-live-tip-checkout?checkout_return=success&session_id=',
        expected: 'texto «ainda não confirmado» sem captura',
        obtained: {'b2': settleB2.brief, 'anon': settleAnon.brief},
      );
    } else {
      c.block('bi3.settle_unpaid', 'BI3', 'settle unpaid não captura', {
        'b2': settleB2.brief,
        'anon': settleAnon.brief,
      });
    }

    // Oráculo Stripe (exacto fechado — não contar se «No such checkout.session»)
    final settleFake = await c.edge(
      'create-live-tip-checkout',
      null,
      method: 'GET',
      qs: 'checkout_return=success&session_id=cs_test_aFORGED_RTBI_ORACLE',
    );
    c.note('bi3.settle.fake', 'GET settle session forjada', settleFake, lens: 'BI3');
    if (settleFake.body.contains('No such checkout.session')) {
      c.note('bi3.residual_oracle', 'oráculo Stripe exacto ainda ecoa',
          settleFake.brief, lens: 'BI3');
    } else {
      c.block('bi3.oracle', 'BI3', 'GET settle forjado sem oráculo Stripe',
          settleFake);
    }

    // Pagar TEST e ver Location decimal + B2 settle paid
    if (c.stripeTestKey != null) {
      final sess = await c.stripe('GET', '/v1/checkout/sessions/$tipSession');
      final pi = sess.map?['payment_intent']?.toString();
      c.note('bi3.stripe.session', 'session retrieve', {
        'pi': pi,
        'pay': sess.map?['payment_status'],
      }, lens: 'BI3');
      if (pi != null && pi.startsWith('pi_')) {
        final conf = await c.stripe('POST', '/v1/payment_intents/$pi/confirm',
            fields: {'payment_method': 'pm_card_visa'});
        c.note('bi3.stripe.confirm', 'confirm 4242', conf.brief, lens: 'BI3');
        final settlePaidB2 = await c.edge(
          'create-live-tip-checkout',
          null,
          method: 'GET',
          jwt: c.buyer2Jwt,
          qs: 'checkout_return=success&session_id=$tipSession',
        );
        c.note('bi3.settle.paid.b2', 'GET settle PAID via B2', settlePaidB2,
            lens: 'BI3');
        final loc = settlePaidB2.location ?? '';
        if (settlePaidB2.status == 303 &&
            (loc.contains('127.0.0.1') ||
                loc.contains('2130706433') ||
                loc.contains('evil.com'))) {
          c.hold(
            id: 'P2-BI2/BI3-tip-return-decimal',
            lens: 'BI2',
            severity: 'P2',
            title:
                'Após captura da gorjeta, GET settle redirecciona para origin decimal/loopback',
            actor: 'B2 (sem JWT necessário no GET)',
            pre: 'tip metadata web_return_origin=https://2130706433; PI TEST pago',
            repro: 'GET create-live-tip-checkout?checkout_return=success&session_id=',
            expected: 'deep link app / fleaber.pt — não Location loopback',
            obtained: settlePaidB2.brief,
          );
        }
        // B2 não deve conseguir «roubar» o crédito — settle é da session. Verificar tip buyer.
        if (tipIdCreated != null) {
          final tipRow = await c.rest(
            'GET',
            'live_tips?id=eq.$tipIdCreated&select=id,status,buyer_id,seller_id,amount,stripe_session_id',
            service: true,
          );
          c.note('bi3.tip.row', 'tip após settle B2', tipRow.map, lens: 'BI3');
          final tb = tipRow.map?['buyer_id']?.toString();
          if (tb != null && tb == c.buyer2Id) {
            c.hold(
              id: 'P0-BI3-tip-buyer-swap',
              lens: 'BI3',
              severity: 'P0',
              title: 'Settle B2 reatribui gorjeta ao B2',
              actor: 'B2',
              pre: 'tip criada por B1, paga, settle GET B2',
              repro: 'GET settle session B1 com JWT B2',
              expected: 'buyer_id permanece B1',
              obtained: tipRow.map,
            );
          }
        }
      }
    } else {
      c.skip('bi3.pay', 'BI3', 'sem sk_test — não paguei a Session', 'no_sk_test');
    }
  } else {
    c.skip('bi3.session', 'BI3', 'não houve Session de gorjeta (live air?)',
        tipOk.brief);
  }

  final tipHigh = await c.edge(
    'create-live-tip-checkout',
    {
      'live_id': liveAir,
      'seller_id': c.seller2Id,
      'amount_eur': 999999,
    },
    jwt: c.buyerJwt,
  );
  c.note('bi4.tip.high', 'amount_eur enorme', tipHigh, lens: 'BI4');
  if (tipHigh.ok) {
    c.hold(
      id: 'P1-BI4-tip-amount',
      lens: 'BI4',
      severity: 'P1',
      title: 'cliente define amount_eur acima do teto',
      actor: 'buyer JWT',
      pre: 'broadcasting',
      repro: 'POST tip amount_eur=999999',
      expected: '400 too high',
      obtained: tipHigh.brief,
    );
  } else {
    c.block('bi4.tip_amount', 'BI4', 'teto amount_eur', tipHigh);
  }

  // ===========================================================================
  // BI6 — storage buckets
  // ===========================================================================
  final bucketsAnon = await c.req('GET', '/storage/v1/bucket');
  final bucketsBuyer = await c.req('GET', '/storage/v1/bucket', jwt: c.buyerJwt);
  c.note('bi6.buckets.anon', 'list buckets anon', bucketsAnon, lens: 'BI6');
  c.note('bi6.buckets.buyer', 'list buckets buyer', bucketsBuyer, lens: 'BI6');

  Future<HttpHit> listBucket(String b, {String? jwt}) {
    return c.req(
      'POST',
      '/storage/v1/object/list/$b',
      jwt: jwt,
      body: {'prefix': '', 'limit': 20},
    );
  }

  for (final b in ['chat_media', 'fleaber_private', 'product-images', 'avatars']) {
    final a = await listBucket(b);
    final j = await listBucket(b, jwt: c.buyerJwt);
    c.note('bi6.list.$b.anon', 'list $b anon', a, lens: 'BI6');
    c.note('bi6.list.$b.jwt', 'list $b jwt', j, lens: 'BI6');
    final listedN = j.list.length;
    if (b == 'fleaber_private' && (a.ok && a.list.isNotEmpty || listedN > 0 && j.ok)) {
      c.hold(
        id: 'P2-BI6-private-list',
        lens: 'BI6',
        severity: 'P2',
        title: 'Listagem fleaber_private visível',
        actor: a.ok && a.list.isNotEmpty ? 'anon' : 'buyer JWT',
        pre: 'POST object/list/fleaber_private',
        repro: 'POST /storage/v1/object/list/fleaber_private',
        expected: '[] / 400 RLS',
        obtained: {'anon': a.brief, 'jwt': j.brief},
      );
    }
  }

  // object público chat_media path traversal
  final pubGet = await c.req(
    'GET',
    '/storage/v1/object/public/chat_media/${c.sellerId}/x.jpg',
  );
  c.note('bi6.public.chat', 'GET public chat_media path alheio', pubGet, lens: 'BI6');

  // ===========================================================================
  // BI4 — outros Edges body spoof
  // ===========================================================================
  final refundSpoof = await c.edge(
    'refund-order',
    {
      'order_id': '00000000-0000-0000-0000-000000000099',
      'buyer_id': c.buyerId,
      'amount': 1,
    },
    jwt: c.buyerJwt,
    extra: {'Origin': 'https://evil.com'},
  );
  c.note('bi4.refund', 'refund-order buyer + evil origin', refundSpoof, lens: 'BI4');

  final ocr = await c.edge(
    'ingest-ocr-reservation',
    {
      'live_id': liveAir,
      'buyer_id': c.buyerId,
      'quantity': 99,
    },
    jwt: c.buyerJwt,
  );
  c.note('bi4.ocr', 'ocr body spoof', ocr, lens: 'BI4');

  final piOrigin = await c.edge(
    'create-payment-intent',
    {
      'buyer_id': c.buyer2Id,
      'amount': 1,
      'web_return_origin': 'https://2130706433',
    },
    jwt: c.buyerJwt,
  );
  c.note('bi4.cpi', 'payment-intent buyer_id alheio + decimal origin', piOrigin,
      lens: 'BI4');

  // Broadcasting oracle
  final bcAnon = await c.rpc('batata_live_is_broadcasting', {'p_live_id': liveAir});
  final bcAnonDraft =
      await c.rpc('batata_live_is_broadcasting', {'p_live_id': liveDraftOn});
  c.note('bi1.bc.anon.air', 'broadcasting anon air', bcAnon, lens: 'BI1');
  c.note('bi1.bc.anon.draft', 'broadcasting anon draft', bcAnonDraft, lens: 'BI1');

  await c.endLives();
  await c.dumpAll('pass1_findings.json');
  stdout.writeln('DONE findings=${c.findings.length} blocked=${c.blocked.length}');
}

class DirectoryOut {
  static Future<void> ensure(Rtbi c) async {
    await Directory(outDir()).create(recursive: true);
  }
}
