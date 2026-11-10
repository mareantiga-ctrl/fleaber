import 'dart:convert';
import 'dart:io';

import '_rtaq.dart';

/// Pass 1 — Hub/Edge pós-AHAM. Variantes NOVAS (não exactos AK/M).
void main() async {
  final c = Rtaq.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final out = <String, Object?>{
    'auditor': 'REDTEAM_BLIND_AQ_HUB_EDGE_POS_AHAM_v1',
    'stamp': stamp,
    'staging': projectMust,
    'seller': c.sellerId,
    'buyer': c.buyerId,
    'seller2': c.seller2Id,
    'buyer2': c.buyer2Id,
  };

  // Keep QA handle; use a dedicated published handle only if needed.
  final origHandle = await c.rest(
    'GET',
    'profiles?id=eq.${c.sellerId}&select=handle,hub_published',
    service: true,
  );
  out['orig_seller_profile'] = origHandle.brief;

  await c.rest('PATCH', 'profiles?id=eq.${c.sellerId}', service: true, body: {
    'hub_published': true,
    'handle': 'fleahub-demo-ux',
  }, prefer: 'return=minimal');

  final sku = await c.insertProduct(
    title: '$prefix sku-40',
    price: 40,
    qty: 3,
    listed: true,
    live: true,
  );
  final unlisted = await c.insertProduct(
    title: '$prefix unlisted',
    seller: c.seller2Id,
    listed: false,
    qty: 9,
    price: 99,
  );

  const zwsp = '\u200b';
  const nbsp = '\u00a0';

  // ---- published seller: ENDED (verify AHAM closed exacts; hunt leftovers) ----
  final endedPub = await c.insertLive(
    seller: c.sellerId,
    status: 'ended',
    active: false,
    muxPlayback: 'rtaq_ended_pub_pb_$stamp',
    muxVod: 'rtaq_ended_pub_vod_$stamp',
    title: '$prefix ended-pub',
  );
  String? endedAvail;
  String? endedRf;
  String? endedHidden;
  if (endedPub != null) {
    endedAvail = await c.insertLiveItem(
      liveId: endedPub,
      title: '$prefix cheap-ended',
      status: 'available',
      qty: 2,
      price: 5,
      productId: sku,
      itemKind: 'marketplace_product',
    );
    endedRf = await c.insertLiveItem(
      liveId: endedPub,
      title: '$prefix rf-ended',
      status: 'reserved_full',
      qty: 1,
      price: 7,
    );
    endedHidden = await c.insertLiveItem(
      liveId: endedPub,
      title: '$prefix hidden-ended',
      status: 'hidden',
      qty: 1,
      price: 3,
    );
  }

  // ---- published seller: LIVE broadcasting (new item statuses) ----
  final livePub = await c.insertLive(
    seller: c.sellerId,
    status: 'live',
    active: true,
    muxPlayback: 'rtaq_live_pub_pb_$stamp',
    title: '$prefix live-pub',
  );
  String? liveAvail;
  String? liveReserved;
  String? liveHidden;
  String? livePausedItem;
  String? liveRfZwsp;
  String? liveSoldZwsp;
  String? liveHitchNullQty;
  if (livePub != null) {
    liveAvail = await c.insertLiveItem(
      liveId: livePub,
      title: '$prefix live-avail',
      status: 'available',
      qty: 2,
      price: 6,
    );
    liveReserved = await c.insertLiveItem(
      liveId: livePub,
      title: '$prefix live-reserved-partial',
      status: 'reserved',
      qty: 2,
      price: 8,
    );
    liveHidden = await c.insertLiveItem(
      liveId: livePub,
      title: '$prefix live-hidden',
      status: 'hidden',
      qty: 1,
      price: 4,
    );
    livePausedItem = await c.insertLiveItem(
      liveId: livePub,
      title: '$prefix live-paused-item',
      status: 'paused',
      qty: 1,
      price: 9,
    );
    liveRfZwsp = await c.insertLiveItem(
      liveId: livePub,
      title: '$prefix rf-zwsp',
      status: 'reserved_full$zwsp',
      qty: 1,
      price: 11,
    );
    liveSoldZwsp = await c.insertLiveItem(
      liveId: livePub,
      title: '$prefix sold-nbsp',
      status: 'sold$nbsp',
      qty: 1,
      price: 12,
    );
    liveHitchNullQty = await c.insertLiveItem(
      liveId: livePub,
      title: '$prefix hitch-null-qty',
      status: 'available',
      qty: null,
      price: 5,
      productId: sku,
      itemKind: 'marketplace_product',
      seller: c.sellerId,
    );
  }

  // paused live still is_active (tip / mux bypass of "ended")
  final pausedActive = await c.insertLive(
    seller: c.sellerId,
    status: 'paused',
    active: true,
    muxPlayback: 'rtaq_paused_pb_$stamp',
    title: '$prefix paused-active',
  );
  if (pausedActive != null) {
    await c.insertLiveItem(
      liveId: pausedActive,
      title: '$prefix paused-live-item',
      qty: 1,
      price: 15,
    );
  }

  final scheduledActive = await c.insertLive(
    seller: c.sellerId,
    status: 'scheduled',
    active: true,
    muxPlayback: 'rtaq_sched_act_pb_$stamp',
    title: '$prefix scheduled-active',
  );

  final scheduledPub = await c.insertLive(
    seller: c.sellerId,
    status: 'scheduled',
    active: false,
    muxPlayback: 'rtaq_sched_pub_pb_$stamp',
    muxVod: 'rtaq_sched_pub_vod_$stamp',
    title: '$prefix scheduled-pub',
  );

  final endedZwspActive = await c.insertLive(
    seller: c.sellerId,
    status: 'ended$zwsp',
    active: true,
    muxPlayback: 'rtaq_ended_zwsp_pb_$stamp',
    title: '$prefix ended-zwsp-active',
  );

  final aoVivo = await c.insertLive(
    seller: c.sellerId,
    status: 'ao_vivo',
    active: true,
    muxPlayback: 'rtaq_aovivo_pb_$stamp',
    title: '$prefix ao-vivo',
  );

  // unpublished seller2
  final leftoverEnded = await c.insertLive(
    seller: c.seller2Id,
    status: 'ended',
    active: true,
    muxPlayback: 'rtaq_leftover_ended_$stamp',
    title: '$prefix leftover-ended-unpub',
  );
  String? leftoverItem;
  if (leftoverEnded != null) {
    leftoverItem = await c.insertLiveItem(
      liveId: leftoverEnded,
      title: '$prefix leftover-item',
      qty: 4,
      price: 2,
    );
  }

  final activeUnpub = await c.insertLive(
    seller: c.seller2Id,
    status: 'live',
    active: true,
    muxPlayback: 'rtaq_active_unpub_$stamp',
    streamKey: 'rtaq_sk_unpub_$stamp',
    title: '$prefix active-unpub',
  );
  String? unpubItem;
  if (activeUnpub != null) {
    unpubItem = await c.insertLiveItem(
      liveId: activeUnpub,
      title: '$prefix unpub-item',
      qty: 3,
      price: 13,
    );
  }

  final draftUnpub = await c.insertLive(
    seller: c.seller2Id,
    status: 'draft',
    active: false,
    muxPlayback: 'rtaq_draft_unpub_$stamp',
    streamKey: 'rtaq_sk_draft_$stamp',
    title: '$prefix draft-unpub',
  );

  out['ids'] = {
    'sku': sku,
    'unlisted': unlisted,
    'endedPub': endedPub,
    'endedAvail': endedAvail,
    'endedRf': endedRf,
    'endedHidden': endedHidden,
    'livePub': livePub,
    'liveAvail': liveAvail,
    'liveReserved': liveReserved,
    'liveHidden': liveHidden,
    'livePausedItem': livePausedItem,
    'liveRfZwsp': liveRfZwsp,
    'liveSoldZwsp': liveSoldZwsp,
    'liveHitchNullQty': liveHitchNullQty,
    'pausedActive': pausedActive,
    'scheduledActive': scheduledActive,
    'scheduledPub': scheduledPub,
    'endedZwspActive': endedZwspActive,
    'aoVivo': aoVivo,
    'leftoverEnded': leftoverEnded,
    'leftoverItem': leftoverItem,
    'activeUnpub': activeUnpub,
    'unpubItem': unpubItem,
    'draftUnpub': draftUnpub,
  };

  Future<HttpHit> anonGet(String qs) => c.rest('GET', qs);
  Future<HttpHit> buyerGet(String qs) => c.rest('GET', qs, jwt: c.buyerJwt);

  // =====================================================================
  // AQ1 — Hub views / FOMO / handle / GRANT oracles
  // =====================================================================
  final hubSurfaces = <String, Object?>{};
  for (final e in {
    'hub_items_ended': 'hub_live_items_public?live_id=eq.$endedPub&select=id,title,price,status',
    'hub_items_live':
        'hub_live_items_public?live_id=eq.$livePub&select=id,title,price,status',
    'hub_disc_live':
        'hub_live_items_discovery_public?live_id=eq.$livePub&select=id,title,price,status',
    'hub_disc_unpub':
        'hub_live_items_discovery_public?live_id=eq.$activeUnpub&select=id,title,price,status',
    'hub_lives_ended':
        'hub_lives_public?id=eq.$endedPub&select=id,status,is_active,mux_playback_id,mux_vod_playback_id,title',
    'hub_lives_live':
        'hub_lives_public?id=eq.$livePub&select=id,status,is_active,mux_playback_id',
    'hub_lives_paused':
        'hub_lives_public?id=eq.$pausedActive&select=id,status,is_active,mux_playback_id',
    'hub_lives_sched':
        'hub_lives_public?id=eq.$scheduledPub&select=id,status,is_active,mux_playback_id,mux_vod_playback_id',
    'hub_lives_zwsp':
        'hub_lives_public?id=eq.$endedZwspActive&select=id,status,is_active,mux_playback_id',
    'hub_disc_unpub_live':
        'hub_lives_discovery_public?id=eq.$activeUnpub&select=id,status,is_active,seller_handle,mux_playback_id',
    'hub_disc_leftover':
        'hub_lives_discovery_public?id=eq.$leftoverEnded&select=id,status,is_active,mux_playback_id',
    'hub_disc_draft':
        'hub_lives_discovery_public?id=eq.$draftUnpub&select=id,status,is_active',
    'hub_products_unlisted': 'hub_products_public?id=eq.$unlisted&select=id,title,price',
    'hub_profiles_s2': 'hub_profiles_public?id=eq.${c.seller2Id}&select=id,handle',
    'hub_profiles_disc_s2':
        'hub_profiles_discovery_public?id=eq.${c.seller2Id}&select=id,handle,location',
  }.entries) {
    final a = await anonGet(e.value);
    final b = await buyerGet(e.value);
    hubSurfaces[e.key] = {'anon': a.brief, 'buyer': b.brief, 'n_anon': a.list.length};
  }
  out['hub_surfaces'] = hubSurfaces;

  final hubItemsLive = await anonGet(
    'hub_live_items_public?live_id=eq.$livePub&select=id,title,price,status',
  );
  out['hub_items_live_rows'] = hubItemsLive.json;
  if (hubItemsLive.status == 401 ||
      hubItemsLive.body.contains('batata_live_item_stock')) {
    c.note('exact-AK-GRANT', 'hub items still 401 — exact AK1-HUB-ITEMS-GRANT',
        hubItemsLive.brief,
        lens: 'AQ1');
  } else {
    c.hold(
      id: 'RTAQ-AQ1-HUB-ITEMS-GRANT-CLOSED',
      lens: 'AQ1',
      title: 'anon lê hub_live_items_public (GRANT AHAM)',
      actor: 'anon',
      pre: 'AHAM GRANT stock/broadcasting',
      repro: 'GET hub_live_items_public live pub',
      expected: '200 não 401',
      obtained: hubItemsLive.brief,
    );
  }

  final liveIdsShown = hubItemsLive.list
      .whereType<Map>()
      .map((m) => m['id']?.toString())
      .toSet();
  void flagIfShown(String? id, String code, String title, String why) {
    if (id != null && liveIdsShown.contains(id)) {
      c.finding(
        id: code,
        lens: 'AQ1',
        severity: 'P2',
        title: title,
        actor: 'anon',
        pre: why,
        repro: 'GET hub_live_items_public?live_id=eq.<live-broadcasting>',
        expected: 'item excluído da vitrine',
        obtained: hubItemsLive.json,
        evidence: {'id': id},
      );
    }
  }

  flagIfShown(liveRfZwsp, 'RTAQ-AQ1-RF-ZWSP-IN-HUB',
      'Hub anon lista reserved_full + ZWSP (denylist exact-match)',
      'status reserved_full\\u200b não casa com reserved_full');
  flagIfShown(liveSoldZwsp, 'RTAQ-AQ1-SOLD-NBSP-IN-HUB',
      'Hub anon lista sold + NBSP', 'status sold\\u00a0 não casa com sold');
  flagIfShown(liveHidden, 'RTAQ-AQ1-HIDDEN-IN-HUB',
      'Hub anon lista item status=hidden em directo no ar',
      'denylist sem hidden');
  flagIfShown(livePausedItem, 'RTAQ-AQ1-PAUSED-ITEM-IN-HUB',
      'Hub lista item paused', 'paused deveria estar na denylist');
  flagIfShown(liveReserved, 'RTAQ-AQ1-RESERVED-PARTIAL-IN-HUB',
      'Hub lista status=reserved (não reserved_full) com qty>0',
      'parcialmente reservado ainda na vitrine');

  if (liveAvail != null && liveIdsShown.contains(liveAvail)) {
    c.hold(
      id: 'RTAQ-AQ1-LIVE-AVAIL-OK',
      lens: 'AQ1',
      title: 'item available aparece no Hub durante broadcasting',
      actor: 'anon',
      pre: 'directo live+is_active',
      repro: 'GET hub_live_items_public',
      expected: 'linha available',
      obtained: 'shown',
    );
  }

  // FOMO
  Future<HttpHit> fomo(String? id) =>
      c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': id});
  final fomos = <String, Object?>{};
  for (final e in {
    'endedPub': endedPub,
    'livePub': livePub,
    'pausedActive': pausedActive,
    'scheduledPub': scheduledPub,
    'endedZwsp': endedZwspActive,
    'activeUnpub': activeUnpub,
    'draftUnpub': draftUnpub,
    'leftover': leftoverEnded,
    'aoVivo': aoVivo,
  }.entries) {
    fomos[e.key] = (await fomo(e.value)).brief;
  }
  out['fomo'] = fomos;
  final fomoEnded = await fomo(endedPub);
  final fomoLive = await fomo(livePub);
  out['fomo_ended_json'] = fomoEnded.json;
  out['fomo_live_json'] = fomoLive.json;

  bool fomoHas(HttpHit h, String? itemId) {
    if (itemId == null || h.json is! Map) return false;
    final items = (h.json as Map)['items'];
    if (items is! List) return false;
    return items.any((x) => x is Map && x['live_item_id']?.toString() == itemId);
  }

  if (fomoHas(fomoEnded, endedRf)) {
    c.note('exact-AK-FOMO-RF', 'FOMO ended reserved_full — exact AK1-FOMO',
        fomoEnded.brief,
        lens: 'AQ1');
  } else {
    c.hold(
      id: 'RTAQ-AQ1-FOMO-ENDED-RF-CLOSED',
      lens: 'AQ1',
      title: 'FOMO ended não devolve reserved_full',
      actor: 'anon',
      pre: 'AHAM view filtra RF + broadcasting',
      repro: 'rpc batata_hub_live_fomo_snapshot ended',
      expected: 'sem item RF',
      obtained: fomoEnded.brief,
    );
  }

  if (fomoHas(fomoLive, liveRfZwsp)) {
    c.finding(
      id: 'RTAQ-AQ1-FOMO-RF-ZWSP',
      lens: 'AQ1',
      severity: 'P2',
      title: 'FOMO devolve reserved_full+ZWSP em directo no ar',
      actor: 'anon',
      pre: 'item status reserved_full\\u200b',
      repro: 'rpc batata_hub_live_fomo_snapshot',
      expected: 'ausente',
      obtained: fomoLive.json,
    );
  }

  // REST hitch ended (exact AK — note only)
  if (endedAvail != null) {
    final restEnded = await buyerGet(
      'live_items?id=eq.$endedAvail&select=id,price,status,quantity',
    );
    out['rest_ended_hitch'] = restEnded.brief;
    if (restEnded.list.isNotEmpty) {
      c.note('exact-AK-REST-HITCH', 'REST hitch ended ainda visível — exact AK1-REST',
          restEnded.brief,
          lens: 'AQ1');
    } else {
      c.hold(
        id: 'RTAQ-AQ1-REST-ENDED-HITCH-CLOSED',
        lens: 'AQ1',
        title: 'REST buyer esconde hitch de gravado',
        actor: 'buyer JWT',
        pre: 'AHAM policy broadcasting',
        repro: 'GET live_items hitch ended',
        expected: '[]',
        obtained: restEnded.brief,
      );
    }
  }

  // GRANT oracles — NEW vs AK P3 JWT-only
  final stockTargets = {
    'endedRf': endedRf,
    'endedAvail': endedAvail,
    'unpubItem': unpubItem,
    'leftoverItem': leftoverItem,
    'liveRfZwsp': liveRfZwsp,
    'unlisted_not_item': unlisted,
  };
  final stockAnon = <String, Object?>{};
  final stockBuyer = <String, Object?>{};
  for (final e in stockTargets.entries) {
    if (e.value == null) continue;
    final a = await c.rpc('batata_live_item_stock', {'p_live_item_id': e.value});
    final b = await c.rpc('batata_live_item_stock', {'p_live_item_id': e.value},
        jwt: c.buyerJwt);
    stockAnon[e.key] = a.brief;
    stockBuyer[e.key] = b.brief;
  }
  out['stock_anon'] = stockAnon;
  out['stock_buyer'] = stockBuyer;

  final stockEndedRfAnon = endedRf == null
      ? null
      : await c.rpc('batata_live_item_stock', {'p_live_item_id': endedRf});
  if (stockEndedRfAnon != null &&
      stockEndedRfAnon.ok &&
      (stockEndedRfAnon.map?['ok'] == true ||
          stockEndedRfAnon.map?['available_qty'] != null)) {
    c.finding(
      id: 'RTAQ-AQ1-STOCK-RPC-ANON',
      lens: 'AQ1',
      severity: 'P2',
      title:
          'Anon executa batata_live_item_stock em item de gravado (GRANT AHAM) e lê qty/preço',
      actor: 'anon',
      pre: 'AHAM GRANT EXECUTE a anon; UUID do item (não na vitrine)',
      repro: 'POST rpc/batata_live_item_stock p_live_item_id=<ended RF>',
      expected: '42501 ou recusa se o item não é público/broadcasting',
      obtained: stockEndedRfAnon.brief,
      evidence: {'json': stockEndedRfAnon.json},
    );
  } else if (stockEndedRfAnon != null) {
    c.hold(
      id: 'RTAQ-AQ1-STOCK-RPC-ANON-DENIED',
      lens: 'AQ1',
      title: 'anon stock RPC recusado no gravado',
      actor: 'anon',
      pre: 'item ended RF',
      repro: 'rpc batata_live_item_stock',
      expected: '42501/erro',
      obtained: stockEndedRfAnon.brief,
    );
  }

  final bcTargets = {
    'endedPub': endedPub,
    'livePub': livePub,
    'activeUnpub': activeUnpub,
    'pausedActive': pausedActive,
    'scheduledActive': scheduledActive,
    'endedZwsp': endedZwspActive,
    'aoVivo': aoVivo,
    'draftUnpub': draftUnpub,
  };
  final bcAnon = <String, Object?>{};
  for (final e in bcTargets.entries) {
    final h = await c.rpc('batata_live_is_broadcasting', {'p_live_id': e.value});
    bcAnon[e.key] = h.brief;
  }
  out['broadcasting_anon'] = bcAnon;
  final bcUnpub = await c.rpc('batata_live_is_broadcasting', {
    'p_live_id': activeUnpub,
  });
  if (bcUnpub.ok && (bcUnpub.json == true || bcUnpub.body.contains('true'))) {
    c.finding(
      id: 'RTAQ-AQ1-BROADCAST-ORACLE-UNPUB',
      lens: 'AQ1',
      severity: 'P3',
      title:
          'Anon oráculo batata_live_is_broadcasting em directo de vitrine desligada',
      actor: 'anon',
      pre: 'GRANT EXECUTE a anon; UUID live unpublished',
      repro: 'POST rpc/batata_live_is_broadcasting',
      expected: '42501 ou false sem revelar estado interno',
      obtained: bcUnpub.brief,
    );
  }

  final draftFn = await c.rpc('batata_live_is_draft', {'p_live_id': draftUnpub});
  out['draft_fn_anon'] = draftFn.brief;

  bool foundTrue(HttpHit h) =>
      h.json is Map && (h.json as Map)['found'] == true;

  // while unpublished HAS active live — KLM 2A design (descoberta)
  final resolveWhileLive = await c.rpc('batata_resolve_handle', {
    'p_handle': 'rtaq-s2-suggested',
  });
  final resolveNameLive = await c.rpc('batata_resolve_handle', {
    'p_handle': 'rtaqhiddens2',
  });
  out['resolve_while_unpub_live'] = resolveWhileLive.json;
  out['resolve_name_while_live'] = resolveNameLive.json;
  c.note('AQ1-handle-while-unpub-live', 'resolve during unpublished broadcasting',
      resolveWhileLive.brief,
      lens: 'AQ1');

  // OpenAPI / graphql / lives table
  final openapi = await c.req('GET', '/rest/v1/', extra: {
    'Accept': 'application/openapi+json',
  });
  out['openapi'] = {
    'status': openapi.status,
    'bytes': openapi.headers['x-rtaq-bytes'],
    'has_lives': openapi.body.contains('"lives"'),
    'has_stream_key': openapi.body.contains('stream_key'),
    'has_stock': openapi.body.contains('batata_live_item_stock'),
  };
  final graphql = await c.req('POST', '/graphql/v1', body: {
    'query': '{ __typename }',
  });
  out['graphql'] = graphql.brief;
  final livesAnon = await anonGet('lives?select=id,mux_stream_key&limit=1');
  out['lives_anon'] = livesAnon.brief;
  final embed = await anonGet(
    'hub_live_items_public?live_id=eq.$livePub&select=*,lives(*)',
  );
  out['embed_lives'] = embed.brief;

  // =====================================================================
  // AQ2 — CORS / web_return_origin
  // =====================================================================
  final corsOrigins = [
    'https://evil.com',
    'https://attacker.fleaber.pt',
    'chrome-extension://abcdefghijklmnopqrstuvwxyz',
    'https://fleaber.app',
    'https://fleaber.pt',
    'http://127.0.0.1:4173',
    'http://localhost:9999',
    'https://fleaber.pt.',
    'https://fleaber.pt:443',
    'http://[::1]:4173',
    'http://0.0.0.0:4173',
    'null',
    'https://fleaber.pt.evil.com',
    'https://www.fleaber.pt.attacker.com',
    'capacitor://localhost',
    'ionic://localhost',
    'file://',
    'https://127.0.0.1',
    'http://localhost.evil.com',
  ];
  final cors = <String, Object?>{};
  for (final o in corsOrigins) {
    final h = await c.edge(
      'resolve-mux-playback',
      body: {'live_id': livePub},
      extra: {'Origin': o},
    );
    cors[o] = {'status': h.status, 'acao': h.acao};
    final reflected = h.acao == o &&
        o != 'https://fleaber.pt' &&
        o != 'https://fleaber.app' &&
        !o.startsWith('http://127.0.0.1') &&
        !o.startsWith('http://localhost:');
    if (reflected &&
        o != 'https://127.0.0.1' &&
        o != 'https://fleaber.pt:443') {
      c.finding(
        id: 'RTAQ-AQ2-CORS-${o.hashCode.abs()}',
        lens: 'AQ2',
        severity: 'P2',
        title: 'CORS reflecte origin hostil $o',
        actor: 'browser Origin',
        pre: 'KLM exact hosts',
        repro: 'POST resolve-mux-playback Origin=$o',
        expected: 'ACAO fleaber.pt (não reflecte)',
        obtained: h.acao,
      );
    }
  }
  out['cors'] = cors;

  final connectOrigins = [
    'https://evil.com/steal',
    'https://fleaber.pt.evil.com',
    'https://fleaber.pt/@evil.com',
    'https://user:pass@fleaber.pt',
    'http://127.0.0.1:9',
    'http://localhost:9999',
    'http://[::1]:4173',
    'https://fleaber.pt/../../evil.com',
    'https://fleaber.pt%2f%2fevil.com',
    'javascript:alert(1)',
    '//evil.com',
    'https://127.0.0.1.nip.io',
    'https://fleaber.app/wallet?next=https://evil.com',
  ];
  final connectGet = <String, Object?>{};
  for (final o in connectOrigins) {
    final h = await c.edge(
      'create-connect-account',
      method: 'GET',
      qs: '?web_return_origin=${Uri.encodeQueryComponent(o)}',
    );
    connectGet[o] = h.brief;
    final loc = h.location ?? '';
    final evilLoc = loc.contains('evil.com') ||
        loc.contains('javascript:') ||
        loc.contains('nip.io') ||
        (loc.contains('[::1]') && loc.contains('4173'));
    if (evilLoc) {
      c.finding(
        id: 'RTAQ-AQ2-CONNECT-LOC-${o.hashCode.abs()}',
        lens: 'AQ2',
        severity: 'P1',
        title: 'Connect GET Location segue origin hostil',
        actor: 'anon GET',
        pre: 'web_return_origin=$o',
        repro: 'GET create-connect-account?web_return_origin=',
        expected: 'sem Location hostil',
        obtained: h.brief,
      );
    }
  }
  out['connect_get'] = connectGet;

  final localhostRet = connectGet['http://127.0.0.1:9'];
  if ('$localhostRet'.contains('127.0.0.1:9')) {
    c.finding(
      id: 'RTAQ-AQ2-CONNECT-LOCALHOST-PORT',
      lens: 'AQ2',
      severity: 'P3',
      title: 'Connect GET 303 para http://127.0.0.1:9/wallet (allowlist localhost)',
      actor: 'anon',
      pre: 'sanitize permite 127.0.0.1 qualquer porta',
      repro: 'GET create-connect-account?web_return_origin=http://127.0.0.1:9',
      expected: 'só origens de produto, ou localhost sem porta arbitrária em staging web',
      obtained: localhostRet,
    );
  }

  // =====================================================================
  // AQ4/AQ3/AQ7 — tips + settle (não exact ended-published)
  // =====================================================================
  Future<HttpHit> tipCreate(String? liveId, {String? seller, double amt = 1}) {
    return c.edge('create-live-tip-checkout', jwt: c.buyerJwt, body: {
      'live_id': liveId,
      'seller_id': seller ?? c.sellerId,
      'amount_eur': amt,
    });
  }

  final tips = <String, Object?>{};
  final tipCases = {
    'endedPub': endedPub,
    'livePub': livePub,
    'pausedActive': pausedActive,
    'scheduledActive': scheduledActive,
    'scheduledPub': scheduledPub,
    'endedZwsp': endedZwspActive,
    'aoVivo': aoVivo,
    'activeUnpub': activeUnpub,
    'leftoverEnded': leftoverEnded,
    'draftUnpub': draftUnpub,
  };
  String? unpaidSession;
  String? tipOnBypassLive;
  for (final e in tipCases.entries) {
    final seller =
        (e.key == 'activeUnpub' || e.key == 'leftoverEnded' || e.key == 'draftUnpub')
            ? c.seller2Id
            : c.sellerId;
    final h = await tipCreate(e.value, seller: seller);
    tips[e.key] = h.brief;
    final opened = h.ok && h.hasCheckout;
    if (e.key == 'endedPub') {
      if (opened) {
        c.note('exact-AK-TIP-ENDED', 'tip ended published ainda abre Session — exact AK4',
            h.brief,
            lens: 'AQ4');
      } else {
        c.hold(
          id: 'RTAQ-AQ4-TIP-ENDED-CLOSED',
          lens: 'AQ4',
          title: 'tip em gravado recusada',
          actor: 'buyer JWT',
          pre: 'AHAM tips only broadcasting',
          repro: 'POST create-live-tip-checkout ended',
          expected: '400',
          obtained: h.brief,
        );
      }
    } else if (e.key != 'livePub' && e.key != 'aoVivo' && opened) {
      c.finding(
        id: 'RTAQ-AQ4-TIP-${e.key.toUpperCase()}',
        lens: 'AQ4',
        severity: 'P2',
        title: 'create-live-tip-checkout abre Session em live ${e.key}',
        actor: 'buyer JWT',
        pre: 'status/is_active de ${e.key} não é broadcasting clássico live+ended-gate',
        repro: 'POST create-live-tip-checkout live_id=${e.value}',
        expected: 'recusa (só directo no ar)',
        obtained: h.brief,
        evidence: {'session': h.checkoutId},
      );
      unpaidSession ??= h.checkoutId;
      tipOnBypassLive ??= e.key;
    } else if (e.key == 'livePub' && opened) {
      unpaidSession ??= h.checkoutId;
      c.hold(
        id: 'RTAQ-AQ4-TIP-LIVE-OK',
        lens: 'AQ4',
        title: 'tip em directo live+active cria Session (happy path)',
        actor: 'buyer',
        pre: 'broadcasting',
        repro: 'POST create-live-tip-checkout',
        expected: '200 checkout',
        obtained: h.brief,
      );
    }
  }
  out['tips'] = tips;

  final tipIdSpoof = await c.edge('create-live-tip-checkout', jwt: c.buyerJwt, body: {
    'live_id': livePub,
    'seller_id': c.sellerId,
    'amount_eur': 1,
    'tip_id': '00000000-0000-0000-0000-000000000001',
  });
  out['tip_id_spoof'] = tipIdSpoof.brief;
  if (tipIdSpoof.hasCheckout) {
    c.finding(
      id: 'RTAQ-AQ4-TIP-ID-SPOOF',
      lens: 'AQ4',
      severity: 'P1',
      title: 'Edge aceita tip_id do cliente',
      actor: 'buyer',
      pre: 'body tip_id',
      repro: 'POST create-live-tip-checkout tip_id=',
      expected: '400 Client tip_id is not allowed',
      obtained: tipIdSpoof.brief,
    );
  } else {
    c.hold(
      id: 'RTAQ-AQ4-TIP-ID-DENIED',
      lens: 'AQ4',
      title: 'tip_id cliente recusado',
      actor: 'buyer',
      pre: 'body tip_id',
      repro: 'POST create-live-tip-checkout',
      expected: '400',
      obtained: tipIdSpoof.brief,
    );
  }

  final tipWrongSeller = await tipCreate(livePub, seller: c.seller2Id);
  out['tip_wrong_seller'] = tipWrongSeller.brief;
  final tipSelf = await tipCreate(livePub, seller: c.buyerId);
  out['tip_self'] = tipSelf.brief;
  final tipAmt = await c.edge('create-live-tip-checkout', jwt: c.buyerJwt, body: {
    'live_id': livePub,
    'seller_id': c.sellerId,
    'amount_eur': 0.01,
  });
  out['tip_amt_low'] = tipAmt.brief;
  final tipAmtHi = await c.edge('create-live-tip-checkout', jwt: c.buyerJwt, body: {
    'live_id': livePub,
    'seller_id': c.sellerId,
    'amount_eur': 9999,
  });
  out['tip_amt_hi'] = tipAmtHi.brief;
  final tipBuyerId = await c.edge('create-live-tip-checkout', jwt: c.buyerJwt, body: {
    'live_id': livePub,
    'seller_id': c.sellerId,
    'amount_eur': 1,
    'buyer_id': c.sellerId,
  });
  out['tip_buyer_id_spoof'] = tipBuyerId.brief;

  // settle
  final settleForged = await c.edge(
    'create-live-tip-checkout',
    method: 'GET',
    qs: '?checkout_return=success&session_id=cs_test_rtaq_forged_$stamp',
    extra: {'Origin': 'https://evil.com'},
  );
  out['settle_forged'] = settleForged.brief;
  c.hold(
    id: 'RTAQ-AQ3-SETTLE-FORGED',
    lens: 'AQ3',
    title: 'GET settle session forjada não captura',
    actor: 'anon',
    pre: 'cs_test_rtaq_forged',
    repro: 'GET create-live-tip-checkout?session_id=',
    expected: 'não confirmado / 400',
    obtained: settleForged.brief,
  );

  if (unpaidSession != null) {
    final settleUnpaid = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs: '?checkout_return=success&session_id=$unpaidSession',
      extra: {'Origin': 'https://attacker.fleaber.pt'},
    );
    out['settle_unpaid'] = settleUnpaid.brief;
    final settleB2 = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs: '?checkout_return=success&session_id=$unpaidSession',
      jwt: c.buyer2Jwt,
    );
    out['settle_unpaid_b2'] = settleB2.brief;
    final settleOnPi = await c.edge(
      'create-payment-intent',
      method: 'GET',
      qs: '?checkout_return=success&session_id=$unpaidSession',
    );
    out['settle_tip_on_pi'] = settleOnPi.brief;
    if (settleUnpaid.body.toLowerCase().contains('recebido') &&
        !settleUnpaid.body.toLowerCase().contains('ainda não')) {
      c.finding(
        id: 'RTAQ-AQ3-SETTLE-UNPAID-SUCCESS-UI',
        lens: 'AQ3',
        severity: 'P3',
        title: 'GET settle de Session unpaid mostra sucesso',
        actor: 'anon',
        pre: 'Session TEST unpaid',
        repro: 'GET create-live-tip-checkout checkout_return=success',
        expected: 'não confirmado',
        obtained: settleUnpaid.brief,
      );
    } else {
      c.hold(
        id: 'RTAQ-AQ3-SETTLE-UNPAID-NO-CAPTURE',
        lens: 'AQ3',
        title: 'GET settle unpaid não captura',
        actor: 'anon',
        pre: 'Session unpaid',
        repro: 'GET settle',
        expected: 'não confirmado',
        obtained: settleUnpaid.brief,
      );
    }
  }

  // evil web_return on real tip create
  final tipEvilOrigin = await c.edge('create-live-tip-checkout', jwt: c.buyerJwt, body: {
    'live_id': livePub,
    'seller_id': c.sellerId,
    'amount_eur': 1,
    'web_return_origin': 'https://evil.com/steal',
  });
  out['tip_evil_origin'] = tipEvilOrigin.brief;

  // =====================================================================
  // AQ5 — Mux / LiveKit
  // =====================================================================
  final mux = <String, Object?>{};
  for (final e in {
    'draftUnpub': draftUnpub,
    'scheduledPub': scheduledPub,
    'scheduledActive': scheduledActive,
    'activeUnpub': activeUnpub,
    'pausedActive': pausedActive,
    'endedPub': endedPub,
    'endedZwsp': endedZwspActive,
    'leftoverEnded': leftoverEnded,
    'livePub': livePub,
  }.entries) {
    mux[e.key] = (await c.edge('resolve-mux-playback', body: {'live_id': e.value}))
        .brief;
  }
  out['mux'] = mux;

  final muxDraft = await c.edge('resolve-mux-playback', body: {'live_id': draftUnpub});
  if (muxDraft.ok && muxDraft.body.contains('playback')) {
    c.finding(
      id: 'RTAQ-AQ5-MUX-DRAFT',
      lens: 'AQ5',
      severity: 'P2',
      title: 'resolve-mux-playback devolve HLS de draft unpublished',
      actor: 'anon',
      pre: 'status=draft hub_published=false',
      repro: 'POST resolve-mux-playback',
      expected: '404 live_not_public',
      obtained: muxDraft.brief,
    );
  } else {
    c.hold(
      id: 'RTAQ-AQ5-MUX-DRAFT-CLOSED',
      lens: 'AQ5',
      title: 'mux draft unpublished recusado',
      actor: 'anon',
      pre: 'draft',
      repro: 'resolve-mux-playback',
      expected: '404',
      obtained: muxDraft.brief,
    );
  }

  final muxSched = await c.edge('resolve-mux-playback', body: {'live_id': scheduledPub});
  if (muxSched.ok && muxSched.body.contains('stream.mux.com')) {
    c.finding(
      id: 'RTAQ-AQ5-MUX-SCHEDULED-PUB',
      lens: 'AQ5',
      severity: 'P2',
      title: 'resolve-mux-playback devolve HLS/VOD de directo scheduled (ainda não no ar)',
      actor: 'anon',
      pre: 'hub_lives_public inclui scheduled; Edge trata is_active=false como ended e serve playback',
      repro: 'POST resolve-mux-playback scheduled published',
      expected: '404 até ir ao ar (ou só após ended com VOD real)',
      obtained: muxSched.brief,
    );
  }

  final createMuxBuyer = await c.edge('create-mux-live', jwt: c.buyerJwt, body: {
    'title': '$prefix buyer-mux',
  });
  out['create_mux_buyer'] = createMuxBuyer.brief;
  if (createMuxBuyer.status == 200) {
    c.finding(
      id: 'RTAQ-AQ5-BUYER-CREATE-MUX',
      lens: 'AQ5',
      severity: 'P1',
      title: 'comprador cria Mux live',
      actor: 'buyer',
      pre: 'user_type comprador',
      repro: 'POST create-mux-live',
      expected: '403',
      obtained: createMuxBuyer.brief,
    );
  } else {
    c.hold(
      id: 'RTAQ-AQ5-BUYER-CREATE-MUX-DENIED',
      lens: 'AQ5',
      title: 'buyer create-mux-live 403',
      actor: 'buyer',
      pre: 'comprador',
      repro: 'POST create-mux-live',
      expected: '403',
      obtained: createMuxBuyer.brief,
    );
  }

  // buyer PATCH user_type then mux
  final ut = await c.rest('PATCH', 'profiles?id=eq.${c.buyerId}', jwt: c.buyerJwt, body: {
    'user_type': 'vendedor',
  });
  out['buyer_patch_user_type'] = ut.brief;
  final createMuxAfter = await c.edge('create-mux-live', jwt: c.buyerJwt, body: {
    'title': '$prefix buyer-as-seller',
  });
  out['create_mux_after_type'] = createMuxAfter.brief;
  if (createMuxAfter.status == 200) {
    c.finding(
      id: 'RTAQ-AQ5-BUYER-TYPE-ESCALATE-MUX',
      lens: 'AQ5',
      severity: 'P1',
      title: 'buyer PATCH user_type=vendedor e cria Mux',
      actor: 'buyer JWT',
      pre: 'RLS profiles permite mudar user_type',
      repro: 'PATCH profiles user_type; POST create-mux-live',
      expected: 'user_type imutável / create 403',
      obtained: createMuxAfter.brief,
    );
  }
  // revert type
  await c.rest('PATCH', 'profiles?id=eq.${c.buyerId}', service: true, body: {
    'user_type': 'comprador',
  }, prefer: 'return=minimal');

  final completeX = await c.edge('complete-mux-live', jwt: c.seller2Jwt, body: {
    'live_id': livePub,
  });
  out['complete_cross'] = completeX.brief;
  if (completeX.status == 200) {
    c.finding(
      id: 'RTAQ-AQ5-COMPLETE-CROSS',
      lens: 'AQ5',
      severity: 'P1',
      title: 'seller2 complete-mux-live de live A',
      actor: 'seller2',
      pre: 'live de seller1',
      repro: 'POST complete-mux-live',
      expected: '403',
      obtained: completeX.brief,
    );
  } else {
    c.hold(
      id: 'RTAQ-AQ5-COMPLETE-CROSS-DENIED',
      lens: 'AQ5',
      title: 'complete-mux cruzado recusado',
      actor: 'seller2',
      pre: 'live A',
      repro: 'POST complete-mux-live',
      expected: '403',
      obtained: completeX.brief,
    );
  }

  final lk = await c.edge('livekit-mux-publish', jwt: c.buyerJwt, body: {
    'step': 'token',
    'live_id': livePub,
  });
  out['livekit_buyer'] = lk.brief;
  if (lk.status == 200 && lk.body.contains('token')) {
    c.finding(
      id: 'RTAQ-AQ5-LIVEKIT-BUYER-TOKEN',
      lens: 'AQ5',
      severity: 'P1',
      title: 'buyer obtém token LiveKit de live alheia',
      actor: 'buyer',
      pre: 'step=token',
      repro: 'POST livekit-mux-publish',
      expected: '403',
      obtained: lk.brief,
    );
  } else {
    c.hold(
      id: 'RTAQ-AQ5-LIVEKIT-BUYER-DENIED',
      lens: 'AQ5',
      title: 'buyer LiveKit token recusado',
      actor: 'buyer',
      pre: 'live alheia',
      repro: 'livekit-mux-publish step=token',
      expected: '403',
      obtained: lk.brief,
    );
  }

  // =====================================================================
  // AQ6 — storage
  // =====================================================================
  Future<HttpHit> storageList(String bucket, String prefix) {
    return c.req(
      'POST',
      '/storage/v1/object/list/$bucket',
      body: {'prefix': prefix, 'limit': 20},
    );
  }

  final buckets = await c.req('GET', '/storage/v1/bucket');
  out['storage_buckets'] = buckets.brief;
  final lists = <String, Object?>{};
  for (final b in [
    'chat_media',
    'fleaber_private',
    'avatars',
    'product_photos',
    'live_recordings',
    'mux',
  ]) {
    lists['$b/'] = (await storageList(b, '')).brief;
    lists['$b/product_photos'] = (await storageList(b, 'product_photos')).brief;
  }
  out['storage_lists'] = lists;
  final listRoot = await storageList('chat_media', '');
  if (listRoot.ok && listRoot.list.isNotEmpty) {
    c.finding(
      id: 'RTAQ-AQ6-CHAT-MEDIA-LIST',
      lens: 'AQ6',
      severity: 'P1',
      title: 'Anon lista árvore chat_media',
      actor: 'anon',
      pre: 'KLM deny list',
      repro: 'POST /storage/v1/object/list/chat_media prefix=',
      expected: '[] / 400',
      obtained: listRoot.brief,
    );
  } else {
    c.hold(
      id: 'RTAQ-AQ6-CHAT-MEDIA-LIST-CLOSED',
      lens: 'AQ6',
      title: 'anon não lista chat_media',
      actor: 'anon',
      pre: 'KLM policy',
      repro: 'storage list',
      expected: '[]',
      obtained: listRoot.brief,
    );
  }

  final up = await c.req(
    'POST',
    '/storage/v1/object/chat_media/rtaq-anon-$stamp.txt',
    body: 'anon',
    extra: {'Content-Type': 'text/plain', 'x-upsert': 'true'},
  );
  out['storage_upload_anon'] = up.brief;

  // =====================================================================
  // AQ4 extras — refund / webhook / delete / ocr / hitch order during LIVE
  // =====================================================================
  final refund = await c.edge('refund-order', jwt: c.buyerJwt, body: {
    'order_id': '00000000-0000-0000-0000-000000000099',
  });
  out['refund_fake'] = refund.brief;
  final webhook = await c.edge('stripe-webhook', body: {'type': 'ping'});
  out['webhook_nosig'] = webhook.brief;
  final del = await c.edge('delete-test-account', jwt: c.buyerJwt, body: {
    'user_id': c.sellerId,
  });
  out['delete_seller'] = del.brief;
  final ocr = await c.edge('ingest-ocr-reservation', jwt: c.buyerJwt, extra: {
    'x-device-token': 'rtaq-fake',
  }, body: {
    'live_id': livePub,
    'qty': 99,
  });
  out['ocr'] = ocr.brief;

  if (liveHitchNullQty != null && sku != null && livePub != null) {
    final restHitchLive = await buyerGet(
      'live_items?id=eq.$liveHitchNullQty&select=id,price,status,quantity,item_kind',
    );
    out['rest_hitch_during_live'] = restHitchLive.brief;
    final hubHitch = await anonGet(
      'hub_live_items_public?id=eq.$liveHitchNullQty&select=id,price,status',
    );
    out['hub_hitch_during_live'] = hubHitch.brief;
    final order = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': sku,
      'live_item_id': liveHitchNullQty,
      'live_id': livePub,
      'quantity': 1,
      'status': 'pendente',
      'payment_method': 'stripe',
      'shipping_method': 'ctt',
    });
    out['order_hitch_live'] = order.brief;
    if (order.firstId != null) c.createdOrderIds.add(order.firstId!);
    final contract = order.map;
    out['order_hitch_contract'] = {
      'unit': contract?['contract_unit_cents'],
      'total': contract?['price_total'],
      'status': order.status,
    };
  }

  final pi = await c.edge('create-payment-intent', jwt: c.buyerJwt, body: {
    'product_id': sku,
    'quantity': 1,
    'live_item_id': liveAvail,
    'live_id': livePub,
  });
  out['pi_live_item'] = pi.brief;

  // realtime
  final rt = await c.req('GET', '/realtime/v1/api/usage');
  out['realtime'] = rt.brief;

  // end lives + re-probe handle without broadcasting + restore handle
  await c.endLives();

  final resolveS2 = await c.rpc('batata_resolve_handle', {
    'p_handle': 'rtaq-s2-suggested',
  });
  final resolveName = await c.rpc('batata_resolve_handle', {
    'p_handle': 'rtaqhiddens2',
  });
  out['resolve_s2_after_end'] = resolveS2.json;
  out['resolve_name_after_end'] = resolveName.json;
  if (foundTrue(resolveS2) || foundTrue(resolveName)) {
    c.finding(
      id: 'RTAQ-AQ1-HANDLE-UNPUB-NO-LIVE',
      lens: 'AQ1',
      severity: 'P1',
      title: 'resolve_handle devolve UUID de vitrine desligada sem directo',
      actor: 'anon',
      pre: 'seller2 hub_published=false; lives ended',
      repro: 'POST rpc/batata_resolve_handle após endLives',
      expected: 'found=false',
      obtained: {'suggested': resolveS2.json, 'name': resolveName.json},
    );
  } else {
    c.hold(
      id: 'RTAQ-AQ1-HANDLE-UNPUB-CLOSED',
      lens: 'AQ1',
      title: 'resolve_handle não enumera seller2 sem vitrine (KLM 2A)',
      actor: 'anon',
      pre: 'hub_published=false, lives ended',
      repro: 'rpc batata_resolve_handle',
      expected: 'found=false',
      obtained: resolveS2.brief,
    );
  }

  await c.restoreQaSellerHandle();
  final after = await c.rest(
    'GET',
    'profiles?id=eq.${c.sellerId}&select=handle,hub_published',
    service: true,
  );
  out['seller_handle_restored'] = after.brief;

  out['findings'] = c.findings;
  out['holds'] = c.holds;
  out['notes'] = c.notes;
  out['finding_ids'] = c.findings.map((f) => f['id']).toList();
  out['hold_ids'] = c.holds.map((h) => h['id']).toList();

  final path =
      '${Directory.current.path}/tool/redteam_blind_aq_20260902T1006/pass1.json';
  await dumpJson(path, out);
  stdout.writeln('WROTE $path findings=${c.findings.length} holds=${c.holds.length}');
}
