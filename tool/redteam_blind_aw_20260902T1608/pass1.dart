import 'dart:io';

import '_rtaw.dart';

/// Pass 1 — Hub/Edge pós-ANAS. Variantes NOVAS (não exactos AQ/AK).
void main() async {
  final c = Rtaw.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final out = <String, Object?>{
    'auditor': 'REDTEAM_BLIND_AW_HUB_EDGE_POS_ANAS_v1',
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

  final sku = await c.insertProduct(
    title: '$prefix sku-40',
    price: 40,
    qty: 4,
    listed: true,
    live: true,
  );
  final skuZero = await c.insertProduct(
    title: '$prefix sku-zero',
    price: 1,
    qty: 2,
    listed: true,
    live: true,
  );

  const zwsp = '\u200b';

  // ---- broadcasting live (on air) ----
  final livePub = await c.insertLive(
    seller: c.sellerId,
    status: 'live',
    active: true,
    muxPlayback: 'rtaw_live_pb_$stamp',
    muxLiveId: 'rtaw_mux_live_$stamp',
    title: '$prefix live-pub',
  );
  String? liveAvail;
  String? liveHidden;
  String? hitchZero;
  String? hitchAvailCase;
  String? hitchPausedItem;
  if (livePub != null) {
    liveAvail = await c.insertLiveItem(
      liveId: livePub,
      title: '$prefix live-avail',
      status: 'available',
      qty: 2,
      price: 6,
    );
    liveHidden = await c.insertLiveItem(
      liveId: livePub,
      title: '$prefix live-showing-only',
      status: 'showing',
      qty: 1,
      price: 4,
    );
    hitchZero = await c.insertLiveItem(
      liveId: livePub,
      title: '$prefix hitch-price0',
      status: 'available',
      qty: null,
      price: 0,
      productId: skuZero,
      itemKind: 'marketplace_product',
      seller: c.sellerId,
    );
    hitchAvailCase = await c.insertLiveItem(
      liveId: livePub,
      title: '$prefix hitch-showing',
      status: 'showing',
      qty: null,
      price: 3,
      productId: sku,
      itemKind: 'marketplace_product',
      seller: c.sellerId,
    );
    hitchPausedItem = await c.insertLiveItem(
      liveId: livePub,
      title: '$prefix item-paused',
      status: 'paused',
      qty: 2,
      price: 9,
    );
  }

  // ---- ended published (VOD cache allowed) ----
  final endedPub = await c.insertLive(
    seller: c.sellerId,
    status: 'ended',
    active: false,
    muxPlayback: 'rtaw_ended_pb_$stamp',
    muxVod: 'rtaw_ended_vod_$stamp',
    title: '$prefix ended-pub',
  );
  String? endedAvail;
  String? endedHidden;
  if (endedPub != null) {
    endedAvail = await c.insertLiveItem(
      liveId: endedPub,
      title: '$prefix cheap-ended',
      status: 'available',
      qty: 2,
      price: 5,
    );
    endedHidden = await c.insertLiveItem(
      liveId: endedPub,
      title: '$prefix rf-ended',
      status: 'reserved_full',
      qty: 1,
      price: 3,
    );
  }

  // ---- inactive live WITH vod (paused analogue — status=live is_active=false) ----
  final inactiveVod = await c.insertLive(
    seller: c.sellerId,
    status: 'live',
    active: false,
    muxPlayback: 'rtaw_inactive_pb_$stamp',
    muxVod: 'rtaw_inactive_vod_$stamp',
    title: '$prefix inactive-vod',
  );

  // ---- draft + is_active (Hub OR is_active) ----
  final draftActive = await c.insertLive(
    seller: c.sellerId,
    status: 'draft',
    active: true,
    muxPlayback: 'rtaw_draft_pb_$stamp',
    muxVod: 'rtaw_draft_vod_$stamp',
    title: '$prefix draft-active',
  );
  if (draftActive != null) {
    await c.insertLiveItem(
      liveId: draftActive,
      title: '$prefix draft-item',
      qty: 1,
      price: 15,
    );
  }

  final draftUnpub = await c.insertLive(
    seller: c.seller2Id,
    status: 'draft',
    active: false,
    muxVod: 'rtaw_draft_unpub_vod_$stamp',
    title: '$prefix draft-unpub',
  );

  final errorActive = await c.insertLive(
    seller: c.sellerId,
    status: 'error',
    active: true,
    muxPlayback: 'rtaw_error_pb_$stamp',
    muxVod: 'rtaw_error_vod_$stamp',
    title: '$prefix error-active',
  );

  // try statuses the check may reject (prompt: paused / ao_vivo)
  final pausedTry = await c.insertLive(
    seller: c.sellerId,
    status: 'paused',
    active: true,
    muxPlayback: 'rtaw_paused_pb_$stamp',
    muxVod: 'rtaw_paused_vod_$stamp',
    title: '$prefix paused-try',
  );
  final aoVivoTry = await c.insertLive(
    seller: c.sellerId,
    status: 'ao_vivo',
    active: true,
    muxPlayback: 'rtaw_aovivo_pb_$stamp',
    title: '$prefix aovivo-try',
  );
  final activeTypoTry = await c.insertLive(
    seller: c.sellerId,
    status: 'active',
    active: true,
    title: '$prefix active-typo',
  );
  out['status_inserts'] = {
    'paused': pausedTry,
    'ao_vivo': aoVivoTry,
    'active': activeTypoTry,
    'notes': c.notes
        .where((n) => n['id'] == 'fix.live')
        .map((n) => n['ev'])
        .toList()
        .reversed
        .take(8)
        .toList(),
  };

  // race live (flip is_active)
  final raceLive = await c.insertLive(
    seller: c.sellerId,
    status: 'live',
    active: true,
    muxPlayback: 'rtaw_race_pb_$stamp',
    title: '$prefix race-live',
  );

  Future<HttpHit> anonGet(String qs) => c.rest('GET', qs);
  Future<HttpHit> tipCreate(String? liveId, {String? seller, double amt = 1, Map<String, Object?> extra = const {}}) {
    return c.edge('create-live-tip-checkout', jwt: c.buyerJwt, body: {
      'live_id': liveId,
      'seller_id': seller ?? c.sellerId,
      'amount_eur': amt,
      ...extra,
    });
  }

  Future<HttpHit> mux(String? id) =>
      c.edge('resolve-mux-playback', body: {'live_id': id});

  Future<Map<String, Object?>> surfacesForItem(String? id, String? liveId) async {
    if (id == null) return {'skip': true};
    final hub = await anonGet(
      'hub_live_items_public?id=eq.$id&select=id,price,status,title',
    );
    final disc = await anonGet(
      'hub_live_items_discovery_public?id=eq.$id&select=id,price,status,title',
    );
    final restB = await c.rest(
      'GET',
      'live_items?id=eq.$id&select=id,price,status,quantity,is_active,item_kind',
      jwt: c.buyerJwt,
    );
    final stockAnon = await c.rpc('batata_live_item_stock', {
      'p_live_item_id': id,
    });
    final qtyAnon = await c.rpc('batata_live_item_total_qty', {
      'p_live_item_id': id,
    });
    final fomo = liveId == null
        ? null
        : await c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': liveId});
    return {
      'hub': hub.brief,
      'hub_n': hub.list.length,
      'disc': disc.brief,
      'disc_n': disc.list.length,
      'rest_buyer': restB.brief,
      'rest_n': restB.list.length,
      'stock_anon': stockAnon.brief,
      'qty_anon': qtyAnon.brief,
      if (fomo != null) 'fomo': fomo.brief,
    };
  }

  String? unpaidSession;
  String? raceSession;

  // =====================================================================
  // AW1 — Hub / FOMO / handle / stock oracle variants
  // =====================================================================
  try {
  final hubGrant = await anonGet(
    'hub_live_items_public?live_id=eq.$livePub&select=id,price,status,title&limit=20',
  );
  out['hub_items_grant'] = {
    'status': hubGrant.status,
    'n': hubGrant.list.length,
    'brief': hubGrant.brief,
  };
  if (hubGrant.status == 401 || hubGrant.status == 403) {
    c.note('exact-AK-GRANT', 'Hub items anon 401 — exact AK1 reopened', hubGrant.brief,
        lens: 'AW1');
  } else {
    c.hold(
      id: 'RTAW-AW1-HUB-GRANT-CLOSED',
      lens: 'AW1',
      title: 'Hub items anon GRANT 200 (AK1 fechado)',
      actor: 'anon',
      pre: 'ANAS Hub GRANT mantido',
      repro: 'GET hub_live_items_public',
      expected: '200',
      obtained: '${hubGrant.status} n=${hubGrant.list.length}',
    );
  }

  final hiddenSurf = await surfacesForItem(liveHidden, livePub);
  out['showing_on_air'] = hiddenSurf;
  final showingInHub = (hiddenSurf['hub_n'] as int? ?? 0) > 0;
  final showingInDisc = (hiddenSurf['disc_n'] as int? ?? 0) > 0;
  final showingRest = (hiddenSurf['rest_n'] as int? ?? 0) > 0;
  if (showingInHub != showingInDisc || showingInHub != showingRest) {
    c.finding(
      id: 'RTAW-AW1-SHOWING-DISC-VS-PLAYER',
      lens: 'AW1',
      severity: 'P3',
      title:
          'Item status=showing: Hub / discovery / REST buyer desalinhados',
      actor: 'anon Hub vs buyer REST',
      pre: 'live broadcasting; live_items.status=showing',
      repro: 'GET hub_live_items_public vs discovery vs live_items REST',
      expected: 'três superfícies iguais (todas listam ou todas escondem)',
      obtained: hiddenSurf,
    );
  } else {
    c.hold(
      id: 'RTAW-AW1-SHOWING-ALIGNED',
      lens: 'AW1',
      title: 'showing alinhado Hub/discovery/REST',
      actor: 'anon + buyer',
      pre: 'status=showing broadcasting',
      repro: 'Hub + discovery + REST',
      expected: 'alinhado',
      obtained: hiddenSurf,
    );
  }

  final hitch0 = await surfacesForItem(hitchZero, livePub);
  out['hitch_price0'] = hitch0;
  final hitch0Hub = (hitch0['hub_n'] as int? ?? 0) > 0;
  final hitch0Rest = (hitch0['rest_n'] as int? ?? 0) > 0;
  if (hitch0Hub || hitch0Rest) {
    c.note('AW1-hitch0-visible', 'hitch price=0 qty=1 visível', hitch0, lens: 'AW1');
  }

  final hitchCase = await surfacesForItem(hitchAvailCase, livePub);
  out['hitch_Available'] = hitchCase;

  final pausedItemSurf = await surfacesForItem(hitchPausedItem, livePub);
  out['paused_item'] = pausedItemSurf;

  final endedStock = await surfacesForItem(endedAvail, endedPub);
  out['ended_avail_stock'] = endedStock;
  final endedStockOk = '${endedStock['stock_anon']}'.contains('"ok":true') ||
      '${endedStock['stock_anon']}'.contains('"ok": true');
  if (endedStockOk) {
    c.note('exact-AQ-STOCK-ENDED', 'anon stock ended still ok — exact AQ-P3-01',
        endedStock['stock_anon'],
        lens: 'AW1');
  } else {
    c.hold(
      id: 'RTAW-AW1-STOCK-ENDED-GATED',
      lens: 'AW1',
      title: 'anon stock ended → not_found (ANAS)',
      actor: 'anon',
      pre: 'item available em gravado',
      repro: 'rpc batata_live_item_stock',
      expected: 'live_item_not_found',
      obtained: endedStock['stock_anon'],
    );
  }

  // total_qty: GRANT anon SEM gate de vitrine (variante ≠ stock ended)
  final qtyEnded = endedAvail == null
      ? null
      : await c.rpc('batata_live_item_total_qty', {'p_live_item_id': endedAvail});
  final qtyHiddenEnded = endedHidden == null
      ? null
      : await c.rpc('batata_live_item_total_qty', {'p_live_item_id': endedHidden});
  final qtyHiddenAir = liveHidden == null
      ? null
      : await c.rpc('batata_live_item_total_qty', {'p_live_item_id': liveHidden});
  final qtyRand = await c.rpc('batata_live_item_total_qty', {
    'p_live_item_id': '00000000-0000-0000-0000-000000000001',
  });
  out['total_qty_anon'] = {
    'ended_avail': qtyEnded?.brief,
    'ended_hidden': qtyHiddenEnded?.brief,
    'hidden_on_air': qtyHiddenAir?.brief,
    'rand': qtyRand.brief,
  };
  int? parseQty(HttpHit? h) {
    if (h == null) return null;
    if (h.json is num) return (h.json as num).toInt();
    if (h.body.trim().startsWith(RegExp(r'\d'))) {
      return int.tryParse(h.body.trim());
    }
    return int.tryParse('${h.json}');
  }

  final qEnded = parseQty(qtyEnded);
  final qHiddenEnded = parseQty(qtyHiddenEnded);
  final qHiddenAir = parseQty(qtyHiddenAir);
  if ((qEnded != null && qEnded > 0) ||
      (qHiddenEnded != null && qHiddenEnded > 0) ||
      (qHiddenAir != null && qHiddenAir > 0 && !showingInHub)) {
    c.finding(
      id: 'RTAW-AW1-TOTAL-QTY-ANON',
      lens: 'AW1',
      severity: 'P3',
      title:
          'anon batata_live_item_total_qty devolve qty de item oculto/gravado (sem gate de vitrine)',
      actor: 'anon',
      pre: 'GRANT EXECUTE total_qty a anon; stock gated not_found',
      repro: 'POST rpc/batata_live_item_total_qty UUID ended/hidden',
      expected: '0 ou 42501 / not_found alinhado ao stock',
      obtained: {
        'ended_avail': qEnded,
        'ended_hidden': qHiddenEnded,
        'hidden_on_air': qHiddenAir,
        'rand': qtyRand.brief,
      },
    );
  } else {
    c.hold(
      id: 'RTAW-AW1-TOTAL-QTY-HELD',
      lens: 'AW1',
      title: 'total_qty anon não oráculo de ocultos',
      actor: 'anon',
      pre: 'UUID ended/hidden',
      repro: 'rpc total_qty',
      expected: '0',
      obtained: out['total_qty_anon'],
    );
  }

  // Hub lives: draft+active / inactive vod leak playback
  final hubLives = await anonGet(
    'hub_lives_public?id=in.(${[livePub, endedPub, inactiveVod, draftActive, errorActive].whereType<String>().join(',')})&select=id,status,is_active,mux_playback_id,mux_vod_playback_id,title',
  );
  out['hub_lives'] = hubLives.brief;
  final hubLiveRows = hubLives.list.whereType<Map>().toList();
  final draftInHub = hubLiveRows.any((r) => r['id'] == draftActive);
  final inactiveInHub = hubLiveRows.any((r) => r['id'] == inactiveVod);
  final errorInHub = hubLiveRows.any((r) => r['id'] == errorActive);
  if (draftInHub) {
    c.finding(
      id: 'RTAW-AW1-DRAFT-ACTIVE-HUB-LIVES',
      lens: 'AW1',
      severity: 'P3',
      title:
          'hub_lives_public lista draft+is_active (OR is_active) com mux_playback_id',
      actor: 'anon',
      pre: 'status=draft is_active=true seller publicado',
      repro: 'GET hub_lives_public',
      expected: 'draft fora da vitrine (só scheduled/live/ended)',
      obtained: hubLives.brief,
    );
  } else {
    c.hold(
      id: 'RTAW-AW1-DRAFT-HUB-HELD',
      lens: 'AW1',
      title: 'draft+active não entra em hub_lives_public',
      actor: 'anon',
      pre: 'draft is_active',
      repro: 'GET hub_lives_public',
      expected: 'ausente',
      obtained: 'draftInHub=$draftInHub inactive=$inactiveInHub error=$errorInHub',
    );
  }

  final fomoLive = await c.rpc('batata_hub_live_fomo_snapshot', {
    'p_live_id': livePub,
  });
  final fomoDraft = await c.rpc('batata_hub_live_fomo_snapshot', {
    'p_live_id': draftActive,
  });
  final fomoEnded = await c.rpc('batata_hub_live_fomo_snapshot', {
    'p_live_id': endedPub,
  });
  out['fomo'] = {
    'live': fomoLive.brief,
    'draft': fomoDraft.brief,
    'ended': fomoEnded.brief,
  };

  final bc = await c.rpc('batata_live_is_broadcasting', {'p_live_id': livePub});
  final bcDraft = await c.rpc('batata_live_is_broadcasting', {
    'p_live_id': draftActive,
  });
  final bcInactive = await c.rpc('batata_live_is_broadcasting', {
    'p_live_id': inactiveVod,
  });
  out['broadcasting'] = {
    'live': bc.brief,
    'draft': bcDraft.brief,
    'inactive': bcInactive.brief,
  };

  final graphql = await c.req('POST', '/graphql/v1', body: {
    'query':
        '{ live_itemsCollection(first: 3) { edges { node { id price status } } } }',
  });
  out['graphql'] = graphql.brief;
  if (graphql.ok &&
      graphql.body.contains('"price"') &&
      !graphql.body.contains('not enabled')) {
    c.finding(
      id: 'RTAW-AW1-GRAPHQL-LIVE-ITEMS',
      lens: 'AW1',
      severity: 'P2',
      title: 'GraphQL devolve live_items (preço/status) fora da vitrine Hub',
      actor: 'anon',
      pre: 'pg_graphql',
      repro: 'POST /graphql/v1 live_itemsCollection',
      expected: 'desligado ou filtrado',
      obtained: graphql.brief,
    );
  } else {
    c.hold(
      id: 'RTAW-AW1-GRAPHQL-OFF',
      lens: 'AW1',
      title: 'GraphQL não enumera live_items',
      actor: 'anon',
      pre: 'query live_itemsCollection',
      repro: 'POST /graphql/v1',
      expected: 'disabled / error',
      obtained: graphql.brief,
    );
  }

  final openapi = await c.req('GET', '/rest/v1/', extra: {
    'Accept': 'application/openapi+json',
  });
  out['openapi'] = {
    'status': openapi.status,
    'bytes': openapi.headers['x-rtaw-bytes'],
    'has_stream_key': openapi.body.contains('stream_key'),
    'has_total_qty': openapi.body.contains('batata_live_item_total_qty'),
  };

  final embed = await anonGet(
    'hub_live_items_public?live_id=eq.$livePub&select=*,lives(*)',
  );
  out['embed_lives'] = embed.brief;

  final handle = await c.rpc('batata_resolve_handle', {
    'p_handle': 'fleahub-demo-ux',
  });
  final handleS2 = await c.rpc('batata_resolve_handle', {
    'p_handle': 'rtawhiddens2',
  });
  out['handles'] = {'pub': handle.brief, 's2': handleS2.brief};

  // =====================================================================
  // AW2 — CORS / web_return_origin (origens NÃO na lista exacta AQ)
  // =====================================================================
  final corsOrigins = [
    'https://fleaber.app.evil.com',
    'https://www.fleaber.pt.attacker.net',
    'https://fleaber.pt%00.evil.com',
    'https://xn--fleber-yxa.pt',
    'moz-extension://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    'https://2130706433',
    'https://0x7f000001',
    'https://hub.fleaber.pt',
    'https://staging.fleaber.app',
    'https://fleaber.pt\\@evil.com',
    'blob:https://fleaber.pt/uuid',
    'https://fleaber.pt:8443',
    'http://[::ffff:127.0.0.1]:4173',
  ];
  final cors = <String, Object?>{};
  for (final o in corsOrigins) {
    final h = await c.edge(
      'resolve-mux-playback',
      body: {'live_id': livePub},
      extra: {'Origin': o},
    );
    cors[o] = {'status': h.status, 'acao': h.acao};
    final reflected = h.acao == o;
    if (reflected &&
        o != 'https://fleaber.pt' &&
        o != 'https://fleaber.app') {
      c.finding(
        id: 'RTAW-AW2-CORS-${o.hashCode.abs()}',
        lens: 'AW2',
        severity: 'P2',
        title: 'CORS reflecte origin hostil $o',
        actor: 'browser Origin',
        pre: 'allowlist exact hosts',
        repro: 'POST resolve-mux-playback Origin=$o',
        expected: 'ACAO fleaber.pt (não reflecte)',
        obtained: h.acao,
      );
    }
  }
  out['cors'] = cors;

  final connectOrigins = [
    'https://fleaber.app.evil.com/steal',
    'https://fleаber.pt',
    'https://xn--fleber-yxa.pt',
    'https://2130706433',
    'data:text/html,https://evil.com',
    'https://fleaber.pt%09.evil.com',
    'https://127.1',
    'https://fleaber.app/wallet?next=https://evil.com',
    'http://localhost.evil.com',
    'https://fleaber.pt\\\\@evil.com',
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
    if (loc.contains('evil.com') ||
        loc.contains('xn--') ||
        loc.contains('2130706433') ||
        loc.startsWith('data:')) {
      c.finding(
        id: 'RTAW-AW2-CONNECT-${o.hashCode.abs()}',
        lens: 'AW2',
        severity: 'P1',
        title: 'Connect GET Location segue origin hostil',
        actor: 'anon GET',
        pre: 'web_return_origin=$o',
        repro: 'GET create-connect-account',
        expected: 'sem Location hostil',
        obtained: h.brief,
      );
    }
  }
  out['connect_get'] = connectGet;

  final tipEvilOrigin = await tipCreate(livePub, extra: {
    'web_return_origin': 'https://fleaber.app.evil.com',
  });
  out['tip_evil_origin'] = tipEvilOrigin.brief;

  // =====================================================================
  // AW4 — tip gates (paused/draft/ao_vivo/race) + body spoof
  // =====================================================================
  final tips = <String, Object?>{};
  final tipCases = <String, String?>{
    'livePub': livePub,
    'endedPub': endedPub,
    'draftActive': draftActive,
    'draftUnpub': draftUnpub,
    'inactiveVod': inactiveVod,
    'errorActive': errorActive,
    'pausedTry': pausedTry,
    'aoVivoTry': aoVivoTry,
    'activeTypo': activeTypoTry,
  };
  unpaidSession = null;
  for (final e in tipCases.entries) {
    final seller = e.key == 'draftUnpub' ? c.seller2Id : c.sellerId;
    final h = await tipCreate(e.value, seller: seller);
    tips[e.key] = h.brief;
    final opened = h.ok && h.hasCheckout;
    if (e.key == 'endedPub') {
      if (opened) {
        c.note('exact-AK-TIP-ENDED', 'tip ended still 200 — exact AK4', h.brief,
            lens: 'AW4');
      } else {
        c.hold(
          id: 'RTAW-AW4-TIP-ENDED-CLOSED',
          lens: 'AW4',
          title: 'tip gravado recusada (AK4 fechado)',
          actor: 'buyer JWT',
          pre: 'ended published',
          repro: 'POST create-live-tip-checkout',
          expected: '400 broadcasting',
          obtained: h.brief,
        );
      }
    } else if (e.key == 'livePub') {
      if (opened) {
        unpaidSession = h.checkoutId;
        c.hold(
          id: 'RTAW-AW4-TIP-LIVE-OK',
          lens: 'AW4',
          title: 'tip live+active happy path 200',
          actor: 'buyer JWT',
          pre: 'broadcasting',
          repro: 'POST create-live-tip-checkout',
          expected: '200 Session',
          obtained: h.brief,
        );
      }
    } else if (opened) {
      unpaidSession ??= h.checkoutId;
      c.finding(
        id: 'RTAW-AW4-TIP-${e.key.toUpperCase()}',
        lens: 'AW4',
        severity: 'P2',
        title: 'create-live-tip-checkout abre Session sem broadcasting (${e.key})',
        actor: 'buyer JWT',
        pre: 'live ${e.key} broadcasting() deve ser false',
        repro: 'POST create-live-tip-checkout',
        expected: '400 Tips only allowed while broadcasting',
        obtained: h.brief,
        evidence: {'checkout': h.checkoutId},
      );
    } else {
      c.hold(
        id: 'RTAW-AW4-TIP-${e.key.toUpperCase()}-HELD',
        lens: 'AW4',
        title: 'tip ${e.key} recusada',
        actor: 'buyer JWT',
        pre: e.key,
        repro: 'POST create-live-tip-checkout',
        expected: '400',
        obtained: h.brief,
      );
    }
  }
  out['tips'] = tips;

  // body spoof
  final spoof = <String, Object?>{};
  spoof['tip_id'] = (await tipCreate(livePub, extra: {
    'tip_id': '00000000-0000-0000-0000-000000000009',
  }))
      .brief;
  spoof['buyer_id'] = (await tipCreate(livePub, extra: {
    'buyer_id': c.buyer2Id,
  }))
      .brief;
  spoof['amount_0'] = (await tipCreate(livePub, amt: 0.01)).brief;
  spoof['amount_9999'] = (await tipCreate(livePub, amt: 9999)).brief;
  spoof['order_id'] = (await tipCreate(livePub, extra: {
    'order_id': '00000000-0000-0000-0000-000000000008',
  }))
      .brief;
  spoof['seller_self'] = (await tipCreate(livePub, seller: c.buyerId)).brief;
  spoof['seller_s2'] = (await tipCreate(livePub, seller: c.seller2Id)).brief;
  out['spoof'] = spoof;
  for (final e in spoof.entries) {
    final s = '${e.value}';
    final opened = s.contains('cs_test') && s.startsWith('200');
    if (e.key == 'tip_id' && opened) {
      c.finding(
        id: 'RTAW-AW4-SPOOF-TIP-ID',
        lens: 'AW4',
        severity: 'P1',
        title: 'Edge aceita tip_id do cliente',
        actor: 'buyer JWT',
        pre: 'tip_id forjado',
        repro: 'POST create-live-tip-checkout tip_id=',
        expected: '400 Client tip_id is not allowed',
        obtained: e.value,
      );
    } else if (e.key == 'amount_0' && opened) {
      c.finding(
        id: 'RTAW-AW4-SPOOF-AMOUNT-MIN',
        lens: 'AW4',
        severity: 'P2',
        title: 'tip amount_eur=0.01 abre Session',
        actor: 'buyer JWT',
        pre: 'mínimo de gorjeta',
        repro: 'amount_eur=0.01',
        expected: '400',
        obtained: e.value,
      );
    } else if (e.key == 'seller_s2' && opened) {
      c.finding(
        id: 'RTAW-AW4-SPOOF-SELLER',
        lens: 'AW4',
        severity: 'P1',
        title: 'tip seller_id alheio na live do seller A',
        actor: 'buyer JWT',
        pre: 'seller_id=seller2 live=seller A',
        repro: 'POST create-live-tip-checkout',
        expected: '400 owner mismatch',
        obtained: e.value,
      );
    }
  }

  // is_active flip race
  raceSession = null;
  if (raceLive != null) {
    final tipRace = tipCreate(raceLive);
    final flip = c.rest('PATCH', 'lives?id=eq.$raceLive', service: true, body: {
      'is_active': false,
    }, prefer: 'return=representation');
    final raced = await Future.wait([tipRace, flip]);
    final tipH = raced[0];
    final flipH = raced[1];
    out['race_flip'] = {
      'tip': tipH.brief,
      'flip': flipH.brief,
      'checkout': tipH.checkoutId,
    };
    raceSession = tipH.checkoutId;
    if (tipH.ok && tipH.hasCheckout) {
      final afterBc = await c.rpc('batata_live_is_broadcasting', {
        'p_live_id': raceLive,
      });
      out['race_after_bc'] = afterBc.brief;
      if (afterBc.json == false || '${afterBc.json}' == 'false') {
        c.finding(
          id: 'RTAW-AW4-TIP-IS-ACTIVE-FLIP-RACE',
          lens: 'AW4',
          severity: 'P2',
          title:
              'tip Session criada em corrida com PATCH is_active=false (broadcasting já false)',
          actor: 'buyer JWT + service fixture',
          pre: 'live broadcasting; flip is_active em paralelo com checkout',
          repro: 'Future.wait tip + PATCH is_active=false',
          expected: '400 se o flip ganhar; sem Session órfã',
          obtained: {
            'tip': tipH.brief,
            'after_bc': afterBc.brief,
            'session': tipH.checkoutId,
          },
          evidence: {'session': tipH.checkoutId},
        );
      } else {
        c.note('AW4-race-flip-still-broadcasting', 'flip não desligou a tempo',
            afterBc.brief,
            lens: 'AW4');
      }
    } else {
      c.hold(
        id: 'RTAW-AW4-RACE-HELD',
        lens: 'AW4',
        title: 'tip recusada na corrida is_active',
        actor: 'buyer JWT',
        pre: 'parallel flip',
        repro: 'Future.wait',
        expected: '400 ou 200 só se ainda broadcasting',
        obtained: tipH.brief,
      );
    }
    // pós-flip: tip deve falhar
    final afterTip = await tipCreate(raceLive);
    out['race_after_tip'] = afterTip.brief;
    if (afterTip.ok && afterTip.hasCheckout) {
      c.finding(
        id: 'RTAW-AW4-TIP-AFTER-INACTIVE',
        lens: 'AW4',
        severity: 'P2',
        title: 'tip ainda abre Session após is_active=false (status=live)',
        actor: 'buyer JWT',
        pre: 'status=live is_active=false',
        repro: 'POST create-live-tip-checkout',
        expected: '400 broadcasting',
        obtained: afterTip.brief,
      );
    }
  }

  // =====================================================================
  // AW3 — settle GET alheio / forjado / mix tip↔PI
  // =====================================================================
  final settleForged = await c.edge(
    'create-live-tip-checkout',
    method: 'GET',
    qs: '?checkout_return=success&session_id=cs_test_rtaw_forged_$stamp',
  );
  out['settle_forged'] = settleForged.brief;
  if (settleForged.status == 200 &&
      settleForged.body.toLowerCase().contains('confirmado') &&
      !settleForged.body.contains('não confirmado') &&
      !settleForged.body.contains('nao confirmado')) {
    c.finding(
      id: 'RTAW-AW3-SETTLE-FORGED-PAID',
      lens: 'AW3',
      severity: 'P0',
      title: 'GET settle forjado afirma pagamento confirmado',
      actor: 'anon',
      pre: 'cs_test_rtaw_forged',
      repro: 'GET create-live-tip-checkout session_id forjado',
      expected: '400 Stripe / não confirmado',
      obtained: settleForged.brief,
    );
  } else {
    c.hold(
      id: 'RTAW-AW3-SETTLE-FORGED-HELD',
      lens: 'AW3',
      title: 'settle forjado não captura',
      actor: 'anon',
      pre: 'session_id forjado',
      repro: 'GET tip settle',
      expected: '400 / não confirmado',
      obtained: settleForged.brief,
    );
  }

  final settleIds = [
    unpaidSession,
    raceSession,
  ].whereType<String>().toSet();
  final settles = <String, Object?>{};
  for (final sid in settleIds) {
    final own = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs: '?checkout_return=success&session_id=$sid',
    );
    final b2 = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      jwt: c.buyer2Jwt,
      qs: '?checkout_return=success&session_id=$sid',
    );
    final asPi = await c.edge(
      'create-payment-intent',
      method: 'GET',
      qs: '?checkout_return=success&session_id=$sid',
    );
    settles[sid] = {
      'anon_tip': own.brief,
      'b2_tip': b2.brief,
      'pi_mix': asPi.brief,
    };
    final credited = own.body.toLowerCase().contains('crédito') ||
        own.body.toLowerCase().contains('credito') ||
        (own.location ?? '').contains('stripe-success');
    if (credited && own.status == 303) {
      c.note('AW3-settle-redirect', 'settle unpaid 303?', own.brief, lens: 'AW3');
    }
  }
  out['settles'] = settles;

  // =====================================================================
  // AW5 — Mux VOD ended vs inactive/paused-analogue + cross-user
  // =====================================================================
  final muxes = <String, Object?>{};
  muxes['live'] = (await mux(livePub)).brief;
  muxes['ended'] = (await mux(endedPub)).brief;
  muxes['inactive_vod'] = (await mux(inactiveVod)).brief;
  muxes['draft_active'] = (await mux(draftActive)).brief;
  muxes['draft_unpub'] = (await mux(draftUnpub)).brief;
  muxes['error'] = (await mux(errorActive)).brief;
  muxes['paused_try'] = (await mux(pausedTry)).brief;
  out['mux'] = muxes;

  bool muxOk(Object? b) => '$b'.startsWith('200') && '$b'.contains('playback');

  if (muxOk(muxes['inactive_vod'])) {
    c.finding(
      id: 'RTAW-AW5-MUX-VOD-INACTIVE',
      lens: 'AW5',
      severity: 'P2',
      title:
          'resolve-mux-playback serve VOD de live inactiva (status=live is_active=false) — não ended',
      actor: 'anon',
      pre: 'mux_vod_playback_id em live não broadcasting e não ended',
      repro: 'POST resolve-mux-playback',
      expected: '404 live_not_public (VOD só ended real)',
      obtained: muxes['inactive_vod'],
    );
  } else {
    c.hold(
      id: 'RTAW-AW5-MUX-VOD-INACTIVE-HELD',
      lens: 'AW5',
      title: 'VOD inactiva recusada (ended≠paused/inactive)',
      actor: 'anon',
      pre: 'live is_active=false + vod cache',
      repro: 'resolve-mux-playback',
      expected: '404',
      obtained: muxes['inactive_vod'],
    );
  }
  if (muxOk(muxes['draft_active'])) {
    c.finding(
      id: 'RTAW-AW5-MUX-DRAFT-ACTIVE',
      lens: 'AW5',
      severity: 'P2',
      title: 'Mux serve playback de draft+is_active',
      actor: 'anon',
      pre: 'draft broadcasting=false',
      repro: 'resolve-mux-playback',
      expected: '404',
      obtained: muxes['draft_active'],
    );
  }
  if (muxOk(muxes['ended']) && '${muxes['ended']}'.contains('cache')) {
    c.hold(
      id: 'RTAW-AW5-MUX-ENDED-VOD-OK',
      lens: 'AW5',
      title: 'ended published serve VOD cache (esperado)',
      actor: 'anon',
      pre: 'ended + mux_vod + hub public',
      repro: 'resolve-mux-playback',
      expected: '200 source=cache',
      obtained: muxes['ended'],
    );
  }

  final createMuxBuyer = await c.edge('create-mux-live', jwt: c.buyerJwt, body: {
    'title': '$prefix buyer-mux',
  });
  out['create_mux_buyer'] = createMuxBuyer.brief;
  if (createMuxBuyer.status == 200) {
    c.finding(
      id: 'RTAW-AW5-CREATE-MUX-BUYER',
      lens: 'AW5',
      severity: 'P1',
      title: 'buyer cria Mux live',
      actor: 'buyer JWT',
      pre: 'user_type comprador',
      repro: 'POST create-mux-live',
      expected: '403',
      obtained: createMuxBuyer.brief,
    );
  } else {
    c.hold(
      id: 'RTAW-AW5-CREATE-MUX-BUYER-HELD',
      lens: 'AW5',
      title: 'buyer create-mux-live recusado',
      actor: 'buyer JWT',
      pre: 'comprador',
      repro: 'POST create-mux-live',
      expected: '403',
      obtained: createMuxBuyer.brief,
    );
  }

  final completeX = await c.edge('complete-mux-live', jwt: c.seller2Jwt, body: {
    'live_id': livePub,
  });
  out['complete_mux_x'] = completeX.brief;
  if (completeX.status == 200) {
    c.finding(
      id: 'RTAW-AW5-COMPLETE-MUX-CROSS',
      lens: 'AW5',
      severity: 'P1',
      title: 'seller2 complete-mux-live da live A',
      actor: 'seller2 JWT',
      pre: 'live do seller A',
      repro: 'POST complete-mux-live',
      expected: '403',
      obtained: completeX.brief,
    );
  } else {
    c.hold(
      id: 'RTAW-AW5-COMPLETE-CROSS-HELD',
      lens: 'AW5',
      title: 'complete-mux cruzado recusado',
      actor: 'seller2',
      pre: 'live A',
      repro: 'POST complete-mux-live',
      expected: '403',
      obtained: completeX.brief,
    );
  }

  final lk = await c.edge('livekit-mux-publish', jwt: c.buyerJwt, body: {
    'live_id': livePub,
    'step': 'token',
  });
  out['livekit_buyer'] = lk.brief;
  if (lk.status == 200) {
    c.finding(
      id: 'RTAW-AW5-LIVEKIT-BUYER',
      lens: 'AW5',
      severity: 'P1',
      title: 'buyer obtém token LiveKit da live alheia',
      actor: 'buyer JWT',
      pre: 'step=token',
      repro: 'POST livekit-mux-publish',
      expected: '403',
      obtained: lk.brief,
    );
  } else {
    c.hold(
      id: 'RTAW-AW5-LIVEKIT-HELD',
      lens: 'AW5',
      title: 'LiveKit token buyer recusado',
      actor: 'buyer JWT',
      pre: 'live alheia',
      repro: 'step=token',
      expected: '403',
      obtained: lk.brief,
    );
  }

  // =====================================================================
  // AW6 — storage
  // =====================================================================
  final buckets = [
    'chat_media',
    'product_photos',
    'avatars',
    'fleaber_private',
    'mux-assets',
    'live-recordings',
    'hub_media',
  ];
  final storage = <String, Object?>{};
  for (final b in buckets) {
    final list = await c.req(
      'POST',
      '/storage/v1/object/list/$b',
      body: {'prefix': '', 'limit': 10},
    );
    storage['list_$b'] = list.brief;
    if (list.ok && list.list.isNotEmpty) {
      c.finding(
        id: 'RTAW-AW6-LIST-$b',
        lens: 'AW6',
        severity: b == 'fleaber_private' ? 'P1' : 'P3',
        title: 'anon lista objectos em $b',
        actor: 'anon',
        pre: 'prefix vazio',
        repro: 'POST /storage/v1/object/list/$b',
        expected: '[] ou 400/403',
        obtained: list.brief,
      );
    }
  }
  final bucketList = await c.req('GET', '/storage/v1/bucket');
  storage['buckets'] = bucketList.brief;
  final up = await c.req(
    'POST',
    '/storage/v1/object/chat_media/rtaw-anon-$stamp.txt',
    body: 'rtaw',
    extra: {'Content-Type': 'text/plain'},
  );
  storage['upload_anon'] = up.brief;
  if (up.ok) {
    c.finding(
      id: 'RTAW-AW6-UPLOAD-ANON',
      lens: 'AW6',
      severity: 'P2',
      title: 'anon faz upload chat_media',
      actor: 'anon',
      pre: 'sem JWT',
      repro: 'POST object/chat_media',
      expected: '403 RLS',
      obtained: up.brief,
    );
  } else {
    c.hold(
      id: 'RTAW-AW6-UPLOAD-HELD',
      lens: 'AW6',
      title: 'upload anon recusado',
      actor: 'anon',
      pre: 'chat_media',
      repro: 'POST object',
      expected: '403',
      obtained: up.brief,
    );
  }
  out['storage'] = storage;

  // extra edges
  final webhook = await c.edge('stripe-webhook', body: {'type': 'ping'});
  out['webhook_nosig'] = webhook.brief;
  final delAcc = await c.edge('delete-test-account', jwt: c.buyerJwt, body: {
    'user_id': c.sellerId,
  });
  out['delete_account'] = delAcc.brief;
  final ocr = await c.edge('ingest-ocr-reservation', jwt: c.buyerJwt, body: {
    'token': 'fake',
    'live_id': livePub,
  });
  out['ocr'] = ocr.brief;

  // =====================================================================
  // AW7 — composição: hitch 0 € → contrato; hidden → order; session ≠ captura
  // =====================================================================
  if (hitchZero != null && skuZero != null) {
    final order0 = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': skuZero,
      'live_item_id': hitchZero,
      'live_id': livePub,
      'quantity': 1,
      'status': 'pendente',
      'payment_method': 'stripe',
      'shipping_method': 'ctt',
    });
    out['order_hitch0'] = {
      'brief': order0.brief,
      'unit': order0.map?['contract_unit_cents'],
      'total': order0.map?['price_total'],
    };
    if (order0.firstId != null) c.createdOrderIds.add(order0.firstId!);
    final unit = order0.map?['contract_unit_cents'];
    if (order0.ok && (unit == 0 || unit == '0')) {
      c.finding(
        id: 'RTAW-AW7-HITCH-PRICE0-CONTRACT',
        lens: 'AW7',
        severity: 'P2',
        title: 'pedido hitch price=0 sela contract_unit_cents=0',
        actor: 'buyer JWT',
        pre: 'marketplace_product price=0 qty=1 no ar; catálogo SKU 1 €',
        repro: 'POST orders live_item hitch zero',
        expected: 'rejeitar 0 ou selar preço catálogo >0',
        obtained: out['order_hitch0'],
      );
    } else if (order0.ok) {
      c.hold(
        id: 'RTAW-AW7-HITCH0-CONTRACT-HELD',
        lens: 'AW7',
        title: 'contrato hitch 0 € não selou zero',
        actor: 'buyer JWT',
        pre: 'price=0',
        repro: 'POST orders',
        expected: 'catálogo ou 400',
        obtained: out['order_hitch0'],
      );
    }
    final pi0 = await c.edge('create-payment-intent', jwt: c.buyerJwt, body: {
      'product_id': skuZero,
      'quantity': 1,
      'live_item_id': hitchZero,
      'live_id': livePub,
      'buyer_id': c.buyer2Id,
      'amount': 0.01,
    });
    out['pi_hitch0'] = pi0.brief;
    if (pi0.hasCheckout || (pi0.ok && pi0.body.contains('cs_test'))) {
      c.finding(
        id: 'RTAW-AW7-PI-HITCH0',
        lens: 'AW7',
        severity: 'P1',
        title: 'create-payment-intent abre Session no hitch 0 € / amount spoof',
        actor: 'buyer JWT',
        pre: 'hitch price=0 + amount 0.01 + buyer_id alheio',
        repro: 'POST create-payment-intent',
        expected: '400 metadata / preço autoritativo',
        obtained: pi0.brief,
        evidence: {'checkout': pi0.checkoutId},
      );
    }
  }

  if (liveHidden != null) {
    final orderH = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'live_item_id': liveHidden,
      'live_id': livePub,
      'quantity': 1,
      'status': 'pendente',
      'payment_method': 'stripe',
      'shipping_method': 'ctt',
    });
    out['order_hidden'] = {
      'brief': orderH.brief,
      'unit': orderH.map?['contract_unit_cents'],
    };
    if (orderH.firstId != null) c.createdOrderIds.add(orderH.firstId!);
    if (orderH.ok) {
      c.finding(
        id: 'RTAW-AW7-ORDER-HIDDEN',
        lens: 'AW7',
        severity: 'P2',
        title: 'buyer cria pedido de item hidden no ar',
        actor: 'buyer JWT',
        pre: 'live_items.status=hidden',
        repro: 'POST orders live_item_id hidden',
        expected: '400 item não vitrine',
        obtained: out['order_hidden'],
      );
    } else {
      c.hold(
        id: 'RTAW-AW7-ORDER-HIDDEN-HELD',
        lens: 'AW7',
        title: 'order hidden recusado',
        actor: 'buyer JWT',
        pre: 'hidden',
        repro: 'POST orders',
        expected: '400',
        obtained: orderH.brief,
      );
    }
  }

  // refund cruzado
  if (c.createdOrderIds.isNotEmpty) {
    final ref = await c.edge('refund-order', jwt: c.buyer2Jwt, body: {
      'order_id': c.createdOrderIds.first,
    });
    out['refund_x'] = ref.brief;
    if (ref.status == 200) {
      c.finding(
        id: 'RTAW-AW4-REFUND-CROSS',
        lens: 'AW4',
        severity: 'P0',
        title: 'buyer2 refund do pedido de B1',
        actor: 'buyer2 JWT',
        pre: 'order B1',
        repro: 'POST refund-order',
        expected: '403',
        obtained: ref.brief,
      );
    }
  }

  // mark_sold / settle tip rpc anon
  final mark = await c.rpc('batata_mark_live_item_sold', {
    'p_live_item_id': liveAvail,
  });
  out['mark_sold_anon'] = mark.brief;
  final settleTipRpc = await c.rpc('batata_settle_live_tip_from_stripe', {
    'p_tip_id': '00000000-0000-0000-0000-000000000007',
    'p_stripe_session_id': 'cs_test_x',
    'p_paid_amount_cents': 100,
  });
  out['settle_tip_rpc_anon'] = settleTipRpc.brief;

  } catch (e, st) {
    out['crash'] = '$e\n$st';
    stderr.writeln('CRASH $e');
  } finally {
  try {
    await c.endLives();
    await c.restoreQaSellerHandle();
  } catch (e) {
    stderr.writeln('cleanup err $e');
  }

  out['findings'] = c.findings;
  out['holds'] = c.holds;
  out['notes'] = c.notes;
  out['created'] = {
    'lives': c.createdLiveIds,
    'items': c.createdLiveItemIds,
    'products': c.createdProductIds,
    'orders': c.createdOrderIds,
    'livePub': livePub,
    'endedPub': endedPub,
    'inactiveVod': inactiveVod,
    'draftActive': draftActive,
    'raceLive': raceLive,
    'liveHidden': liveHidden,
    'hitchZero': hitchZero,
    'unpaidSession': unpaidSession,
    'raceSession': raceSession,
  };

  final dir = Directory.current.path.contains('redteam_blind_aw_')
      ? Directory.current.path
      : '${Directory.current.path}/tool/redteam_blind_aw_$stamp';
  await dumpJson('$dir/pass1.json', out);
  stdout.writeln(
    'DONE findings=${c.findings.length} holds=${c.holds.length} unpaid=$unpaidSession',
  );
  }
}
