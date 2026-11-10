import 'dart:io';

import '_rtak.dart';

/// Pass 1 — Hub/Edge/deeplink. NEW variants only.
/// Not primary: Hub paused items, invite enum, pairing ended,
/// dual Session classic, mint pós-payout, plain→JSON.
void main() async {
  final c = Rtak.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final out = <String, Object?>{
    'auditor': 'REDTEAM_BLIND_AK_HUB_EDGE_POS_AEAFAG_v1',
    'stamp': stamp,
    'staging': projectMust,
    'seller': c.sellerId,
    'buyer': c.buyerId,
    'seller2': c.seller2Id,
    'buyer2': c.buyer2Id,
  };

  // ---- fixtures (published seller + unpublished seller2) ----
  await c.rest('PATCH', 'profiles?id=eq.${c.sellerId}', service: true, body: {
    'hub_published': true,
    'handle': 'rtak-pub-seller',
  }, prefer: 'return=minimal');

  final sku = await c.insertProduct(
    title: '$prefix sku-40',
    price: 40,
    qty: 3,
    listed: true,
    live: true,
  );

  final unlistedSku = await c.insertProduct(
    title: '$prefix unlisted-secret',
    seller: c.seller2Id,
    listed: false,
    qty: 9,
    price: 99,
    images: [
      'https://$projectMust.supabase.co/storage/v1/object/public/chat_media/rtak-secret-$stamp.jpg',
    ],
  );

  // Published seller: ENDED live with still-active cheap item (AE composition via Hub)
  final endedPub = await c.insertLive(
    seller: c.sellerId,
    status: 'ended',
    active: false,
    muxPlayback: 'rtak_ended_pub_pb_$stamp',
    muxVod: 'rtak_ended_pub_vod_$stamp',
    title: '$prefix ended-pub',
  );
  String? endedCheapItem;
  String? endedHiddenAlias;
  String? endedReservedFull;
  if (endedPub != null) {
    endedCheapItem = await c.insertLiveItem(
      liveId: endedPub,
      title: '$prefix cheap-ended',
      status: 'available',
      active: true,
      qty: 2,
      price: 5,
      productId: sku,
      itemKind: 'marketplace_product',
    );
    endedHiddenAlias = await c.insertLiveItem(
      liveId: endedPub,
      title: '$prefix hidden-alias',
      status: 'hidden',
      active: true,
      qty: 1,
      price: 3,
    );
    endedReservedFull = await c.insertLiveItem(
      liveId: endedPub,
      title: '$prefix reserved-full-qty1',
      status: 'reserved_full',
      active: true,
      qty: 1,
      price: 7,
    );
  }

  // Unpublished seller2: leftover is_active + status=ended (discovery gate)
  final leftoverEnded = await c.insertLive(
    seller: c.seller2Id,
    status: 'ended',
    active: true,
    muxPlayback: 'rtak_leftover_ended_$stamp',
    muxVod: 'rtak_leftover_vod_$stamp',
    title: '$prefix leftover-ended-unpub',
  );
  String? leftoverItem;
  if (leftoverEnded != null) {
    leftoverItem = await c.insertLiveItem(
      liveId: leftoverEnded,
      title: '$prefix leftover-item',
      status: 'available',
      active: true,
      qty: 4,
      price: 2,
    );
  }

  final scheduledUnpub = await c.insertLive(
    seller: c.seller2Id,
    status: 'scheduled',
    active: false,
    muxPlayback: 'rtak_sched_unpub_$stamp',
    title: '$prefix scheduled-unpub',
  );

  final draftUnpub = await c.insertLive(
    seller: c.seller2Id,
    status: 'draft',
    active: false,
    muxPlayback: 'rtak_draft_unpub_$stamp',
    title: '$prefix draft-unpub',
  );

  final activeUnpub = await c.insertLive(
    seller: c.seller2Id,
    status: 'live',
    active: true,
    muxPlayback: 'rtak_active_unpub_$stamp',
    muxLiveId: 'rtak_muxlive_unpub_$stamp',
    streamKey: 'rtak_sk_unpub_$stamp',
    title: '$prefix active-unpub',
  );
  String? activeUnpubItem;
  if (activeUnpub != null) {
    activeUnpubItem = await c.insertLiveItem(
      liveId: activeUnpub,
      title: '$prefix active-unpub-item',
      status: 'available',
      active: true,
      qty: 5,
      price: 11,
    );
    await c.rest('POST', 'live_messages', service: true, body: {
      'live_id': activeUnpub,
      'kind': 'chat',
      'body': '$prefix secret-chat-unpub',
      'sender_label': 'staff',
      'channel': 'fleaber',
    });
    await c.rest('POST', 'live_messages', service: true, body: {
      'live_id': activeUnpub,
      'kind': 'tip',
      'body': 'tipped',
      'tip_amount': 25,
      'sender_label': 'anon',
    });
  }

  // Handle redirect towards unpublished seller2
  if (c.seller2Id != null) {
    await c.rest('POST', 'profile_handle_redirects', service: true, body: {
      'old_handle': 'rtak-old-redirect',
      'new_handle': 'rtak-s2-suggested',
    });
  }

  // ============================================================
  // AK1 — Hub views / FOMO / handle (anon) — beyond published
  // ============================================================
  Future<HttpHit> anonView(String qs) =>
      c.rest('GET', qs, jwt: c.anon, prefer: 'return=representation');

  final hubEndedItems = await anonView(
    'hub_live_items_public?live_id=eq.$endedPub&select=id,title,price,status,is_active',
  );
  c.note('ak1.ended_pub_items', 'Hub items on ENDED published live',
      hubEndedItems.brief,
      lens: 'AK1');
  final endedHubIds = hubEndedItems.list
      .whereType<Map>()
      .map((e) => e['id']?.toString())
      .toSet();
  if (endedCheapItem != null && endedHubIds.contains(endedCheapItem)) {
    c.finding(
      id: 'RTAK-AK1-ENDED-ACTIVE-ITEM',
      lens: 'AK1',
      severity: 'P1',
      title:
          'Hub público mostra artigo activo (preço histórico) de directo já ended',
      actor: 'anon',
      pre: 'live status=ended is_active=false; item is_active=true price=5',
      repro: 'GET hub_live_items_public?live_id=eq.<ended>',
      expected: '[] — vitrine de gravado não expõe catálogo vivo/preço AE',
      obtained: hubEndedItems.snippet,
      evidence: {
        'live_id': endedPub,
        'cheap_item': endedCheapItem,
        'rows': hubEndedItems.list.length,
      },
    );
  } else {
    c.hold(
      id: 'RTAK-AK1-ENDED-ACTIVE-ITEM',
      lens: 'AK1',
      title: 'Hub NÃO lista item activo de live ended',
      actor: 'anon',
      pre: 'ended live + active item',
      repro: 'GET hub_live_items_public',
      expected: 'hidden',
      obtained: hubEndedItems.brief,
    );
  }
  if (endedHiddenAlias != null && endedHubIds.contains(endedHiddenAlias)) {
    c.finding(
      id: 'RTAK-AK1-HIDDEN-ALIAS',
      lens: 'AK1',
      severity: 'P2',
      title: 'Hub lista live_item status=hidden (alias fora de paused/sold)',
      actor: 'anon',
      pre: 'status=hidden is_active=true qty=1',
      repro: 'GET hub_live_items_public',
      expected: 'filtrado como paused',
      obtained: hubEndedItems.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK1-HIDDEN-ALIAS',
      lens: 'AK1',
      title: 'status=hidden não aparece no Hub',
      actor: 'anon',
      pre: 'hidden item',
      repro: 'GET hub_live_items_public',
      expected: 'hidden',
      obtained: 'absent from ${endedHubIds.length} rows',
    );
  }
  if (endedReservedFull != null && endedHubIds.contains(endedReservedFull)) {
    c.finding(
      id: 'RTAK-AK1-RESERVED-FULL-HUB',
      lens: 'AK1',
      severity: 'P2',
      title: 'Hub lista reserved_full (AEAFAG esconde no REST, não na view?)',
      actor: 'anon',
      pre: 'status=reserved_full qty=1',
      repro: 'GET hub_live_items_public',
      expected: 'oculto (available_qty/status)',
      obtained: hubEndedItems.snippet,
    );
  }

  final discLeftover = await anonView(
    'hub_lives_discovery_public?id=eq.$leftoverEnded&select=id,status,is_active,seller_handle,mux_playback_id,mux_vod_playback_id',
  );
  c.note('ak1.leftover_ended_disc', 'discovery leftover is_active+ended unpub',
      discLeftover.brief,
      lens: 'AK1');
  if (discLeftover.list.isNotEmpty) {
    c.finding(
      id: 'RTAK-AK1-LEFTOVER-ENDED-DISCOVERY',
      lens: 'AK1',
      severity: 'P2',
      title:
          'Discovery lista directo unpublished status=ended com is_active leftover + mux ids',
      actor: 'anon',
      pre: 'seller2 hub_published=false; live ended+is_active=true',
      repro: 'GET hub_lives_discovery_public?id=eq.<leftover>',
      expected: '[] (ended só se hub_published)',
      obtained: discLeftover.snippet,
      evidence: {'live_id': leftoverEnded, 'item': leftoverItem},
    );
  } else {
    c.hold(
      id: 'RTAK-AK1-LEFTOVER-ENDED-DISCOVERY',
      lens: 'AK1',
      title: 'leftover ended+is_active unpublished fora da discovery',
      actor: 'anon',
      pre: 'ended+is_active unpub',
      repro: 'GET hub_lives_discovery_public',
      expected: '[]',
      obtained: discLeftover.brief,
    );
  }

  final discSched = await anonView(
    'hub_lives_discovery_public?id=eq.$scheduledUnpub&select=id,status,mux_playback_id',
  );
  final hubSched = await anonView(
    'hub_lives_public?id=eq.$scheduledUnpub&select=id,status,mux_playback_id',
  );
  c.note('ak1.sched_unpub', 'scheduled unpublished',
      'disc=${discSched.brief} hub=${hubSched.brief}',
      lens: 'AK1');
  if (discSched.list.isNotEmpty || hubSched.list.isNotEmpty) {
    c.finding(
      id: 'RTAK-AK1-SCHEDULED-UNPUB',
      lens: 'AK1',
      severity: 'P2',
      title: 'Scheduled unpublished visível em Hub/discovery',
      actor: 'anon',
      pre: 'seller2 unpublished scheduled',
      repro: 'GET hub_lives_*',
      expected: '[]',
      obtained: 'disc=${discSched.snippet} hub=${hubSched.snippet}',
    );
  } else {
    c.hold(
      id: 'RTAK-AK1-SCHEDULED-UNPUB',
      lens: 'AK1',
      title: 'scheduled unpublished oculto',
      actor: 'anon',
      pre: 'scheduled unpub',
      repro: 'GET hub_lives_*',
      expected: '[]',
      obtained: 'ok',
    );
  }

  final discActive = await anonView(
    'hub_lives_discovery_public?id=eq.$activeUnpub&select=id,seller_handle,mux_playback_id,status,is_active',
  );
  final discItems = await anonView(
    'hub_live_items_discovery_public?live_id=eq.$activeUnpub&select=id,title,price,status',
  );
  final hubActive = await anonView(
    'hub_lives_public?id=eq.$activeUnpub&select=id',
  );
  c.note('ak1.active_unpub', 'active unpublished discovery vs hub',
      'disc=${discActive.brief} items=${discItems.brief} hub=${hubActive.brief}',
      lens: 'AK1');
  // Control: discovery of ACTIVE unpublished is known E0817 product.
  // Finding only if Hub *published* view also shows it, or items leak extra cols.
  if (hubActive.list.isNotEmpty) {
    c.finding(
      id: 'RTAK-AK1-ACTIVE-UNPUB-HUB-PUBLIC',
      lens: 'AK1',
      severity: 'P1',
      title: 'hub_lives_public lista directo de vitrine desligada',
      actor: 'anon',
      pre: 'hub_published=false live active',
      repro: 'GET hub_lives_public?id=eq.<activeUnpub>',
      expected: '[] (só discovery, não vitrine)',
      obtained: hubActive.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK1-ACTIVE-UNPUB-HUB-PUBLIC',
      lens: 'AK1',
      title: 'hub_lives_public recusa activo unpublished (só discovery)',
      actor: 'anon',
      pre: 'active unpub',
      repro: 'GET hub_lives_public',
      expected: '[]',
      obtained: hubActive.brief,
    );
  }

  final fomoUnpub = await c.rpc('batata_hub_live_fomo_snapshot', {
    'p_live_id': activeUnpub,
  });
  c.note('ak1.fomo_unpub', 'FOMO on unpublished active', fomoUnpub.brief,
      lens: 'AK1');
  final fomoOk = fomoUnpub.map?['ok'] == true;
  final fomoItems = fomoUnpub.map?['items'];
  if (fomoOk && fomoItems is List && fomoItems.isNotEmpty) {
    c.finding(
      id: 'RTAK-AK1-FOMO-UNPUB',
      lens: 'AK1',
      severity: 'P1',
      title: 'FOMO devolve stock exacto de directo unpublished',
      actor: 'anon',
      pre: 'FOMO usa hub_lives_public; live só em discovery',
      repro: 'POST rpc/batata_hub_live_fomo_snapshot p_live_id=<unpub active>',
      expected: 'live_not_public',
      obtained: fomoUnpub.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK1-FOMO-UNPUB',
      lens: 'AK1',
      title: 'FOMO recusa unpublished (live_not_public)',
      actor: 'anon',
      pre: 'active unpub',
      repro: 'rpc fomo',
      expected: 'live_not_public',
      obtained: fomoUnpub.brief,
    );
  }

  final fomoEnded = await c.rpc('batata_hub_live_fomo_snapshot', {
    'p_live_id': endedPub,
  });
  c.note('ak1.fomo_ended', 'FOMO on published ended', fomoEnded.brief,
      lens: 'AK1');
  if (fomoEnded.map?['ok'] == true &&
      fomoEnded.map?['items'] is List &&
      (fomoEnded.map!['items'] as List).isNotEmpty) {
    c.finding(
      id: 'RTAK-AK1-FOMO-ENDED-QTY',
      lens: 'AK1',
      severity: 'P2',
      title: 'FOMO em gravado ended devolve available_qty / fila (oráculo stock)',
      actor: 'anon',
      pre: 'live ended published',
      repro: 'rpc batata_hub_live_fomo_snapshot',
      expected: 'items=[] em gravado, ou sem qty exacta',
      obtained: fomoEnded.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK1-FOMO-ENDED-QTY',
      lens: 'AK1',
      title: 'FOMO ended sem items/qty',
      actor: 'anon',
      pre: 'ended pub',
      repro: 'rpc fomo',
      expected: 'empty or live_not_public',
      obtained: fomoEnded.brief,
    );
  }

  final stockRpc = endedCheapItem == null
      ? null
      : await c.rpc('batata_live_item_stock', {
          'p_live_item_id': endedCheapItem,
        });
  if (stockRpc != null) {
    c.note('ak1.stock_rpc_anon', 'anon batata_live_item_stock', stockRpc.brief,
        lens: 'AK1');
    if (stockRpc.ok && stockRpc.map != null) {
      c.finding(
        id: 'RTAK-AK1-STOCK-RPC-ANON',
        lens: 'AK1',
        severity: 'P2',
        title: 'Anon executa batata_live_item_stock (qty exacta) com UUID',
        actor: 'anon',
        pre: 'item id conhecido via Hub ou guess',
        repro: 'POST rpc/batata_live_item_stock',
        expected: '42501 / not granted to anon',
        obtained: stockRpc.snippet,
      );
    } else {
      c.hold(
        id: 'RTAK-AK1-STOCK-RPC-ANON',
        lens: 'AK1',
        title: 'anon stock RPC recusado',
        actor: 'anon',
        pre: 'uuid',
        repro: 'rpc stock',
        expected: 'denied',
        obtained: stockRpc.brief,
      );
    }
  }

  // handle_suggested (NOT name-slug exact M)
  final resolveSuggested = await c.rpc('batata_resolve_handle', {
    'p_handle': 'rtak-s2-suggested',
  });
  final discProfile = await anonView(
    'hub_profiles_discovery_public?id=eq.${c.seller2Id}&select=id,handle,hub_published,location,phone_verified,external_payments_enabled',
  );
  final hubProfile = await anonView(
    'hub_profiles_public?id=eq.${c.seller2Id}&select=id,handle',
  );
  c.note('ak1.resolve_suggested', 'resolve handle_suggested unpublished',
      'rpc=${resolveSuggested.brief} disc=${discProfile.brief} hub=${hubProfile.brief}',
      lens: 'AK1');
  final foundSuggested = resolveSuggested.map?['found'] == true;
  final suggestedPub = resolveSuggested.map?['hub_published'];
  if (foundSuggested && suggestedPub != true && discProfile.list.isEmpty) {
    c.finding(
      id: 'RTAK-AK1-HANDLE-SUGGESTED',
      lens: 'AK1',
      severity: 'P1',
      title:
          'batata_resolve_handle enumera UUID via handle_suggested com vitrine e discovery vazias',
      actor: 'anon',
      pre: 'handle=null handle_suggested=rtak-s2-suggested hub_published=false, sem live na discovery (após leftover?)',
      repro: 'POST rpc/batata_resolve_handle p_handle=rtak-s2-suggested',
      expected: 'found=false se discovery não mostra o perfil',
      obtained: resolveSuggested.snippet,
      evidence: {
        'discovery_rows': discProfile.list.length,
        'hub_rows': hubProfile.list.length,
      },
    );
  } else if (foundSuggested && suggestedPub != true) {
    c.note('ak1.resolve_suggested_with_disc',
        'resolve suggested mas discovery também tem linha (E0817 live)',
        resolveSuggested.brief,
        lens: 'AK1');
  } else {
    c.hold(
      id: 'RTAK-AK1-HANDLE-SUGGESTED',
      lens: 'AK1',
      title: 'handle_suggested unpublished não resolve (ou publicado)',
      actor: 'anon',
      pre: 'suggested slug',
      repro: 'rpc resolve',
      expected: 'not_found OR discovery visible',
      obtained: resolveSuggested.brief,
    );
  }

  final resolveRedirect = await c.rpc('batata_resolve_handle', {
    'p_handle': 'rtak-old-redirect',
  });
  c.note('ak1.redirect', 'handle redirect', resolveRedirect.brief, lens: 'AK1');
  if (resolveRedirect.map?['found'] == true) {
    c.finding(
      id: 'RTAK-AK1-HANDLE-REDIRECT',
      lens: 'AK1',
      severity: 'P2',
      title: 'Redirect de handle antigo resolve perfil unpublished',
      actor: 'anon',
      pre: 'profile_handle_redirects old→suggested',
      repro: 'rpc batata_resolve_handle p_handle=rtak-old-redirect',
      expected: 'not_found se destino unpublished',
      obtained: resolveRedirect.snippet,
    );
  }

  // PostgREST embed
  final embedLives = await anonView(
    'hub_lives_public?id=eq.$endedPub&select=id,title,live_items(id,price,quantity,status),lives(mux_stream_key,stream_key)',
  );
  c.note('ak1.embed', 'PostgREST embed hub_lives_public', embedLives.brief,
      lens: 'AK1');
  final embedTxt = embedLives.body.toLowerCase();
  if (embedTxt.contains('stream_key') ||
      embedTxt.contains('quantity') ||
      embedTxt.contains('mux_stream')) {
    c.finding(
      id: 'RTAK-AK1-EMBED',
      lens: 'AK1',
      severity: 'P1',
      title: 'Embed PostgREST vaza quantity/stream_key via view Hub',
      actor: 'anon',
      pre: 'select=*,live_items(*),lives(*)',
      repro: 'GET hub_lives_public?select=...',
      expected: 'PGRST200 / sem cols internas',
      obtained: embedLives.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK1-EMBED',
      lens: 'AK1',
      title: 'embed não vaza stream_key/quantity',
      actor: 'anon',
      pre: 'embed',
      repro: 'GET select embed',
      expected: 'error or whitelist',
      obtained: embedLives.brief,
    );
  }

  final msgsUnpub = await anonView(
    'hub_live_messages_public?live_id=eq.$activeUnpub&select=id,kind,body,tip_amount',
  );
  c.note('ak1.msgs_unpub', 'Hub messages unpublished live', msgsUnpub.brief,
      lens: 'AK1');
  if (msgsUnpub.list.isNotEmpty) {
    c.finding(
      id: 'RTAK-AK1-MSGS-UNPUB',
      lens: 'AK1',
      severity: 'P2',
      title: 'hub_live_messages_public lê chat de directo unpublished',
      actor: 'anon',
      pre: 'messages on unpublished active live',
      repro: 'GET hub_live_messages_public?live_id=',
      expected: '[] (join hub_lives_public)',
      obtained: msgsUnpub.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK1-MSGS-UNPUB',
      lens: 'AK1',
      title: 'mensagens unpublished ocultas (join hub_lives_public)',
      actor: 'anon',
      pre: 'unpub live msgs',
      repro: 'GET hub_live_messages_public',
      expected: '[]',
      obtained: msgsUnpub.brief,
    );
  }

  final restItemsBuyer = endedCheapItem == null
      ? null
      : await c.rest(
          'GET',
          'live_items?id=eq.$endedCheapItem&select=id,price,quantity,status,is_active',
          jwt: c.buyerJwt,
        );
  if (restItemsBuyer != null) {
    c.note('ak1.rest_items_ended', 'buyer REST live_items ended cheap',
        restItemsBuyer.brief,
        lens: 'AK1');
    if (restItemsBuyer.list.isNotEmpty) {
      c.finding(
        id: 'RTAK-AK1-REST-ENDED-ITEM',
        lens: 'AK1',
        severity: 'P2',
        title:
            'REST live_items ainda devolve artigo de directo ended (preço histórico AE)',
        actor: 'buyer JWT',
        pre: 'AEAFAG RLS: broadcasting OR hub_lives_public; ended published está na view lives',
        repro: 'GET live_items?id=eq.<ended item>',
        expected: '[] se não broadcasting e item não deveria ser catálogo',
        obtained: restItemsBuyer.snippet,
      );
    } else {
      c.hold(
        id: 'RTAK-AK1-REST-ENDED-ITEM',
        lens: 'AK1',
        title: 'REST esconde item de live ended',
        actor: 'buyer JWT',
        pre: 'ended item',
        repro: 'GET live_items',
        expected: '[]',
        obtained: restItemsBuyer.brief,
      );
    }
  }

  final unlistedHub = await anonView(
    'hub_products_public?id=eq.$unlistedSku&select=id,title,price',
  );
  final unlistedRest = await c.rest(
    'GET',
    'products?id=eq.$unlistedSku&select=id,title,price,quantity',
    jwt: c.buyerJwt,
  );
  c.note('ak1.unlisted', 'unlisted product hub vs rest',
      'hub=${unlistedHub.brief} rest=${unlistedRest.brief}',
      lens: 'AK1');
  if (unlistedHub.list.isNotEmpty) {
    c.finding(
      id: 'RTAK-AK1-UNLISTED-HUB',
      lens: 'AK1',
      severity: 'P1',
      title: 'hub_products_public mostra produto unlisted',
      actor: 'anon',
      pre: 'list_on_marketplace=false',
      repro: 'GET hub_products_public',
      expected: '[]',
      obtained: unlistedHub.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK1-UNLISTED-HUB',
      lens: 'AK1',
      title: 'unlisted fora do Hub',
      actor: 'anon',
      pre: 'unlisted',
      repro: 'GET hub_products_public',
      expected: '[]',
      obtained: 'ok',
    );
  }

  // OpenAPI / schema
  final openapi = await c.req('GET', '/rest/v1/', extra: {
    'Accept': 'application/openapi+json',
  });
  c.note('ak1.openapi', 'PostgREST openapi', '${openapi.status} ${clip(openapi.body, 80)}',
      lens: 'AK1');

  // ============================================================
  // AK2 — CORS / web_return_origin / Connect
  // ============================================================
  Future<Map<String, String?>> corsProbe(String origin, String edge,
      {String method = 'OPTIONS'}) async {
    final h = await c.edge(
      edge,
      method: method,
      extra: {
        'Origin': origin,
        'Access-Control-Request-Method': 'POST',
      },
    );
    return {
      'origin': origin,
      'edge': edge,
      'status': '${h.status}',
      'acao': h.acao,
      'loc': h.location,
    };
  }

  final corsOrigins = [
    'https://evil.com',
    'https://attacker.fleaber.pt',
    'https://fleaber.pt.evil.com',
    'https://fleaber.pt:443',
    'https://fleaber.pt.',
    'https://FLEABER.PT',
    'https://fleaber.app',
    'null',
    'file://',
    'chrome-extension://abcdefghijklmnopqrstuvwxyz',
    'https://127.0.0.1:4173',
  ];
  final corsRows = <Map<String, String?>>[];
  for (final o in corsOrigins) {
    corsRows.add(await corsProbe(o, 'resolve-mux-playback'));
    corsRows.add(await corsProbe(o, 'create-live-tip-checkout'));
  }
  out['cors'] = corsRows;
  for (final row in corsRows) {
    final o = row['origin'] ?? '';
    final acao = row['acao'] ?? '';
    final allowedExact = {
      'https://fleaber.pt',
      'https://www.fleaber.pt',
      'https://fleaber.app',
      'https://www.fleaber.app',
    };
    final isLocal = o.contains('127.0.0.1') || o.contains('localhost');
    if (acao == o && !allowedExact.contains(o) && !isLocal) {
      c.finding(
        id: 'RTAK-AK2-CORS-${o.hashCode.abs()}',
        lens: 'AK2',
        severity: 'P2',
        title: 'CORS reflecte origem fora da allowlist exacta: $o',
        actor: 'browser Origin',
        pre: 'OPTIONS Edge',
        repro: 'Origin: $o',
        expected: 'https://fleaber.pt (não reflecte)',
        obtained: acao,
      );
    }
  }

  final connectOrigins = [
    'https://evil.com/steal',
    'https://fleaber.pt.evil.com',
    'https://evil.com#https://fleaber.pt',
    'https://fleaber.pt/@evil.com',
    'https://user:pass@fleaber.pt',
    'http://fleaber.pt',
    'https://fleaber.pt:443',
    'https://fleaber.app',
    'javascript:alert(1)',
    '//evil.com',
  ];
  final connectRows = <Map<String, String?>>[];
  for (final o in connectOrigins) {
    final h = await c.edge(
      'create-connect-account',
      method: 'GET',
      qs:
          '?web_return_origin=${Uri.encodeQueryComponent(o)}&wallet_return=1',
      extra: {'Origin': 'https://evil.com'},
    );
    connectRows.add({
      'o': o,
      'status': '${h.status}',
      'loc': h.location,
      'acao': h.acao,
      'body': clip(h.body, 80),
    });
    final loc = h.location ?? '';
    if (loc.contains('evil.com') ||
        loc.toLowerCase().startsWith('javascript:') ||
        loc.startsWith('//')) {
      c.finding(
        id: 'RTAK-AK2-CONNECT-REDIRECT',
        lens: 'AK2',
        severity: 'P1',
        title: 'Connect GET Location hostil',
        actor: 'anon GET',
        pre: 'web_return_origin=$o',
        repro: 'GET create-connect-account?web_return_origin=',
        expected: 'sem Location evil',
        obtained: loc,
      );
    }
  }
  out['connect_get'] = connectRows;

  // ============================================================
  // AK5 — Mux/LiveKit (before ending lives)
  // ============================================================
  final muxDraft = await c.edge('resolve-mux-playback', body: {
    'live_id': draftUnpub,
  });
  c.note('ak5.mux_draft', 'resolve-mux draft unpublished', muxDraft.brief,
      lens: 'AK5');
  if (muxDraft.ok && (muxDraft.body.contains('playback') || muxDraft.map?['playback_url'] != null)) {
    c.finding(
      id: 'RTAK-AK5-MUX-DRAFT',
      lens: 'AK5',
      severity: 'P2',
      title: 'resolve-mux-playback devolve HLS de draft unpublished',
      actor: 'anon',
      pre: 'status=draft hub_published=false',
      repro: 'POST resolve-mux-playback {live_id}',
      expected: '404 live_not_public',
      obtained: muxDraft.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK5-MUX-DRAFT',
      lens: 'AK5',
      title: 'resolve-mux recusa draft unpublished',
      actor: 'anon',
      pre: 'draft',
      repro: 'POST resolve-mux-playback',
      expected: 'live_not_public',
      obtained: muxDraft.brief,
    );
  }

  final muxLeftover = await c.edge('resolve-mux-playback', body: {
    'live_id': leftoverEnded,
  });
  c.note('ak5.mux_leftover', 'resolve-mux leftover ended+is_active',
      muxLeftover.brief,
      lens: 'AK5');
  if (muxLeftover.ok && muxLeftover.map?['playback_url'] != null) {
    c.finding(
      id: 'RTAK-AK5-MUX-LEFTOVER',
      lens: 'AK5',
      severity: 'P2',
      title: 'resolve-mux playback de ended unpublished com is_active leftover',
      actor: 'anon',
      pre: 'ended+is_active unpub',
      repro: 'POST resolve-mux-playback',
      expected: 'live_not_public',
      obtained: muxLeftover.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK5-MUX-LEFTOVER',
      lens: 'AK5',
      title: 'resolve-mux recusa leftover ended unpublished',
      actor: 'anon',
      pre: 'leftover',
      repro: 'POST resolve-mux-playback',
      expected: 'denied',
      obtained: muxLeftover.brief,
    );
  }

  final muxActiveUnpub = await c.edge('resolve-mux-playback', body: {
    'live_id': activeUnpub,
  });
  c.note('ak5.mux_active_unpub', 'resolve-mux active unpublished (isLiveNow)',
      muxActiveUnpub.brief,
      lens: 'AK5');
  if (muxActiveUnpub.ok && muxActiveUnpub.map?['playback_url'] != null) {
    c.finding(
      id: 'RTAK-AK5-MUX-ACTIVE-UNPUB',
      lens: 'AK5',
      severity: 'P2',
      title:
          'resolve-mux HLS de directo activo com vitrine desligada (gate isLiveNow, não hub_published)',
      actor: 'anon',
      pre: 'status=live is_active=true hub_published=false',
      repro: 'POST resolve-mux-playback',
      expected: 'só se discovery for o contrato; leak se FOMO/hub_public recusam mas mux aceita',
      obtained: muxActiveUnpub.snippet,
      evidence: {
        'hub_public': hubActive.list.length,
        'discovery': discActive.list.length,
        'fomo_ok': fomoOk,
      },
    );
  }

  final muxBuyerCreate = await c.edge(
    'create-mux-live',
    jwt: c.buyerJwt,
    body: {'title': '$prefix hijack', 'live_id': endedPub, 'seller_id': c.sellerId},
  );
  c.note('ak5.mux_buyer_create', 'buyer create-mux-live', muxBuyerCreate.brief,
      lens: 'AK5');
  if (muxBuyerCreate.status == 200) {
    c.finding(
      id: 'RTAK-AK5-MUX-BUYER-CREATE',
      lens: 'AK5',
      severity: 'P1',
      title: 'Comprador cria stream Mux',
      actor: 'buyer JWT',
      pre: 'user_type comprador + live_id alheio no body',
      repro: 'POST create-mux-live',
      expected: '403 authz',
      obtained: muxBuyerCreate.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK5-MUX-BUYER-CREATE',
      lens: 'AK5',
      title: 'buyer create-mux recusado',
      actor: 'buyer JWT',
      pre: 'buyer',
      repro: 'POST create-mux-live',
      expected: '403',
      obtained: muxBuyerCreate.brief,
    );
  }

  final muxCompleteX = await c.edge(
    'complete-mux-live',
    jwt: c.seller2Jwt,
    body: {'live_id': endedPub},
  );
  c.note('ak5.complete_x', 'seller2 complete seller1 live', muxCompleteX.brief,
      lens: 'AK5');
  if (muxCompleteX.status == 200) {
    c.finding(
      id: 'RTAK-AK5-COMPLETE-CROSS',
      lens: 'AK5',
      severity: 'P0',
      title: 'seller2 complete-mux-live em directo alheio',
      actor: 'seller2 JWT',
      pre: 'live do seller1',
      repro: 'POST complete-mux-live live_id alheio',
      expected: '403',
      obtained: muxCompleteX.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK5-COMPLETE-CROSS',
      lens: 'AK5',
      title: 'complete-mux cross-user recusado',
      actor: 'seller2 JWT',
      pre: 'live alheia',
      repro: 'POST complete-mux-live',
      expected: '403',
      obtained: muxCompleteX.brief,
    );
  }

  final lkToken = await c.edge(
    'livekit-mux-publish',
    jwt: c.buyerJwt,
    body: {'step': 'token', 'live_id': activeUnpub},
  );
  c.note('ak5.lk_token', 'buyer LiveKit token live unpublished', lkToken.brief,
      lens: 'AK5');
  if (lkToken.ok && (lkToken.body.contains('token') || lkToken.map?['token'] != null)) {
    c.finding(
      id: 'RTAK-AK5-LIVEKIT-TOKEN',
      lens: 'AK5',
      severity: 'P1',
      title: 'Buyer obtém token LiveKit de directo alheio unpublished',
      actor: 'buyer JWT',
      pre: 'live seller2',
      repro: 'POST livekit-mux-publish step=token',
      expected: '403',
      obtained: lkToken.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK5-LIVEKIT-TOKEN',
      lens: 'AK5',
      title: 'buyer LiveKit token recusado',
      actor: 'buyer JWT',
      pre: 'live alheia',
      repro: 'livekit-mux-publish token',
      expected: '403',
      obtained: lkToken.brief,
    );
  }

  // ============================================================
  // AK4 — Edge body spoof
  // ============================================================
  final tipSpoof = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyerJwt,
    extra: {'Origin': 'https://attacker.fleaber.pt'},
    body: {
      'seller_id': c.buyerId,
      'live_id': activeUnpub,
      'amount_eur': 1,
      'tip_id': '00000000-0000-0000-0000-000000000001',
      'web_return_origin': 'https://attacker.fleaber.pt',
    },
  );
  c.note('ak4.tip_spoof', 'tip seller=self tip_id spoof origin hostil',
      tipSpoof.brief,
      lens: 'AK4');
  if (tipSpoof.hasCheckout) {
    c.finding(
      id: 'RTAK-AK4-TIP-SPOOF',
      lens: 'AK4',
      severity: 'P1',
      title: 'create-live-tip-checkout aceitou tip_id/seller_id hostil',
      actor: 'buyer JWT',
      pre: 'seller_id=buyer tip_id forjado',
      repro: 'POST create-live-tip-checkout',
      expected: '400 Client tip_id / mismatch',
      obtained: tipSpoof.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK4-TIP-SPOOF',
      lens: 'AK4',
      title: 'tip spoof recusado',
      actor: 'buyer JWT',
      pre: 'tip_id+seller self',
      repro: 'POST create-live-tip-checkout',
      expected: '400',
      obtained: tipSpoof.brief,
    );
  }

  final tipOtherSeller = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyerJwt,
    extra: {'Origin': 'https://fleaber.pt'},
    body: {
      'seller_id': c.seller2Id,
      'live_id': endedPub,
      'amount_eur': 1,
      'web_return_origin': 'https://fleaber.pt',
    },
  );
  c.note('ak4.tip_ended_cross', 'tip ended live + unpublished seller',
      tipOtherSeller.brief,
      lens: 'AK4');
  String? tipSession;
  if (tipOtherSeller.hasCheckout) {
    tipSession = (tipOtherSeller.map?['sessionId'] ??
            tipOtherSeller.map?['session_id'] ??
            tipOtherSeller.map?['id'])
        ?.toString();
    final m = RegExp(r'cs_test_[A-Za-z0-9]+').firstMatch(tipOtherSeller.body);
    tipSession ??= m?.group(0);
    c.finding(
      id: 'RTAK-AK4-TIP-ENDED-UNPUB',
      lens: 'AK4',
      severity: 'P2',
      title: 'Gorjeta Session em directo ended / seller unpublished',
      actor: 'buyer JWT',
      pre: 'live ended published, seller_id=seller2 unpublished',
      repro: 'POST create-live-tip-checkout',
      expected: 'recusar live ended / seller mismatch',
      obtained: tipOtherSeller.snippet,
      evidence: {'session': tipSession},
    );
  } else {
    c.hold(
      id: 'RTAK-AK4-TIP-ENDED-UNPUB',
      lens: 'AK4',
      title: 'tip ended/unpub recusado',
      actor: 'buyer JWT',
      pre: 'ended live',
      repro: 'POST create-live-tip-checkout',
      expected: '400',
      obtained: tipOtherSeller.brief,
    );
  }

  final refundX = await c.edge(
    'refund-order',
    jwt: c.buyerJwt,
    body: {'order_id': '00000000-0000-0000-0000-000000000099'},
  );
  c.note('ak4.refund', 'refund forged order', refundX.brief, lens: 'AK4');

  final ingest = await c.edge(
    'ingest-ocr-reservation',
    jwt: c.buyerJwt,
    extra: {'x-device-token': 'rtak-fake-token'},
    body: {
      'live_id': activeUnpub,
      'requested_qty': 99,
      'ref_slug': 'RTAK1',
    },
  );
  c.note('ak4.ingest', 'ingest-ocr qty 99 fake token', ingest.brief, lens: 'AK4');
  if (ingest.status == 200 && ingest.map?['ok'] == true) {
    c.finding(
      id: 'RTAK-AK4-INGEST',
      lens: 'AK4',
      severity: 'P1',
      title: 'ingest-ocr aceita token fake e qty 99',
      actor: 'buyer JWT',
      pre: 'x-device-token fake',
      repro: 'POST ingest-ocr-reservation',
      expected: '401',
      obtained: ingest.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK4-INGEST',
      lens: 'AK4',
      title: 'ingest-ocr recusado',
      actor: 'buyer JWT',
      pre: 'fake token',
      repro: 'POST ingest-ocr-reservation',
      expected: '401',
      obtained: ingest.brief,
    );
  }

  final delAcc = await c.edge(
    'delete-test-account',
    jwt: c.buyerJwt,
    body: {'user_id': c.sellerId},
  );
  c.note('ak4.delete', 'delete-test-account seller', delAcc.brief, lens: 'AK4');
  if (delAcc.status == 200) {
    c.finding(
      id: 'RTAK-AK4-DELETE-ACCOUNT',
      lens: 'AK4',
      severity: 'P0',
      title: 'delete-test-account apaga seller alheio',
      actor: 'buyer JWT',
      pre: 'user_id=seller',
      repro: 'POST delete-test-account',
      expected: '403 allowlist',
      obtained: delAcc.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK4-DELETE-ACCOUNT',
      lens: 'AK4',
      title: 'delete-test-account recusado',
      actor: 'buyer JWT',
      pre: 'seller id',
      repro: 'POST delete-test-account',
      expected: '403',
      obtained: delAcc.brief,
    );
  }

  // ============================================================
  // AK7 / AK1 composition — Hub cheap item → checkout Session
  // ============================================================
  if (endedCheapItem != null && sku != null) {
    final orderIns = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': sku,
      'live_item_id': endedCheapItem,
      'live_id': endedPub,
      'quantity': 1,
      'status': 'pendente',
      'payment_method': 'stripe',
      'shipping_method': 'ctt',
    });
    c.note('ak7.order', 'buyer order with ended cheap live_item', orderIns.brief,
        lens: 'AK7');
    final oid = orderIns.firstId;
    if (oid != null) c.createdOrderIds.add(oid);
    if (oid != null) {
      final pi = await c.edge(
        'create-payment-intent',
        jwt: c.buyerJwt,
        extra: {'Origin': 'https://fleaber.pt'},
        body: {
          'order_id': oid,
          'product_id': sku,
          'web_return_origin': 'https://fleaber.pt',
        },
      );
      c.note('ak7.pi', 'create-payment-intent ended cheap item', pi.brief,
          lens: 'AK7');
      final amt = pi.map?['amount_total'] ??
          pi.map?['amount'] ??
          pi.map?['total'];
      final url = (pi.map?['url'] ?? pi.map?['checkoutUrl'] ?? '').toString();
      final cs = RegExp(r'cs_test_[A-Za-z0-9]+').firstMatch(pi.body)?.group(0);
      out['ak7_session'] = {
        'order': oid,
        'http': pi.status,
        'amount': amt,
        'cs': cs,
        'url': clip(url, 80),
        'brief': pi.brief,
      };
      // Catalog 40€ + fees vs live_item 5€. Finding if Session ~590 cents.
      final bodyLow = pi.body.toLowerCase();
      final looksCheap = bodyLow.contains('"amount_total":590') ||
          bodyLow.contains('"amount":590') ||
          bodyLow.contains('5.90') ||
          (amt is num && amt <= 700);
      if (pi.hasCheckout && looksCheap) {
        c.finding(
          id: 'RTAK-AK7-HUB-ENDED-PRICE-SESSION',
          lens: 'AK7',
          severity: 'P0',
          title:
              'Hub/REST expõe live_item ended a 5€; Edge cobra Session a esse preço (não catálogo 40€)',
          actor: 'buyer JWT + anon Hub',
          pre: 'SKU 40€; item ended 5€ visível ou UUID conhecido',
          repro: 'POST orders live_item_id=<ended> → create-payment-intent',
          expected: 'recusar live_item de directo ended / cobrar catálogo',
          obtained: pi.snippet,
          evidence: {'order': oid, 'cs': cs, 'amount': amt},
        );
      } else if (orderIns.ok && pi.hasCheckout) {
        c.hold(
          id: 'RTAK-AK7-HUB-ENDED-PRICE-SESSION',
          lens: 'AK7',
          title: 'Session criada mas não parece 5€ (ou recusou preço live_item)',
          actor: 'buyer JWT',
          pre: 'ended item',
          repro: 'create-payment-intent',
          expected: 'catálogo 40€ ou recusa',
          obtained: pi.brief,
        );
      } else if (!orderIns.ok) {
        c.hold(
          id: 'RTAK-AK7-HUB-ENDED-PRICE-SESSION',
          lens: 'AK7',
          title: 'INSERT order com live_item ended recusado',
          actor: 'buyer JWT',
          pre: 'ended item',
          repro: 'POST orders',
          expected: 'denied',
          obtained: orderIns.brief,
        );
      }
    }
  }

  // ============================================================
  // AK3 — settle GET alheio / forjado
  // ============================================================
  final settleForged = await c.edge(
    'create-payment-intent',
    method: 'GET',
    qs: '?checkout_return=success&session_id=cs_test_rtak_forged_$stamp',
    extra: {'Origin': 'https://evil.com'},
  );
  c.note('ak3.settle_forged', 'GET settle forged cs', settleForged.brief,
      lens: 'AK3');
  if (settleForged.body.toLowerCase().contains('pagamento recebido') ||
      settleForged.status == 303) {
    c.finding(
      id: 'RTAK-AK3-SETTLE-FORGED',
      lens: 'AK3',
      severity: 'P0',
      title: 'GET settle Session forjada confirma pagamento',
      actor: 'anon',
      pre: 'cs_test_rtak_forged',
      repro: 'GET create-payment-intent?session_id=',
      expected: 'não confirmado / 400',
      obtained: settleForged.brief,
    );
  } else {
    c.hold(
      id: 'RTAK-AK3-SETTLE-FORGED',
      lens: 'AK3',
      title: 'settle forjado não captura',
      actor: 'anon',
      pre: 'forged cs',
      repro: 'GET settle',
      expected: '400/não confirmado',
      obtained: settleForged.brief,
    );
  }

  // Existing paid session from env? Probe a known unpaid if AK7 created one.
  final csAk7 = (out['ak7_session'] is Map)
      ? (out['ak7_session'] as Map)['cs']?.toString()
      : null;
  if (csAk7 != null && csAk7.startsWith('cs_test_')) {
    final settleOwnUnpaid = await c.edge(
      'create-payment-intent',
      method: 'GET',
      qs: '?checkout_return=success&session_id=$csAk7',
      extra: {'Origin': 'https://attacker.fleaber.pt'},
    );
    c.note('ak3.settle_unpaid', 'GET settle unpaid own session',
        settleOwnUnpaid.brief,
        lens: 'AK3');
    final loc = settleOwnUnpaid.location ?? '';
    if (loc.contains('attacker.fleaber.pt')) {
      c.finding(
        id: 'RTAK-AK3-SETTLE-EVIL-RETURN',
        lens: 'AK3',
        severity: 'P1',
        title: 'GET settle redirecciona para origin hostil',
        actor: 'anon',
        pre: 'Origin attacker.fleaber.pt, session unpaid',
        repro: 'GET create-payment-intent?session_id=',
        expected: 'sem Location evil; não captura',
        obtained: settleOwnUnpaid.brief,
      );
    }
    if (settleOwnUnpaid.body.toLowerCase().contains('pagamento recebido')) {
      c.finding(
        id: 'RTAK-AK3-SETTLE-UNPAID-AS-PAID',
        lens: 'AK3',
        severity: 'P0',
        title: 'GET settle Session unpaid marca como pago',
        actor: 'anon',
        pre: 'Session criada sem pagamento',
        repro: 'GET checkout_return=success',
        expected: 'ainda não confirmado; status unpaid',
        obtained: settleOwnUnpaid.brief,
      );
    } else {
      c.hold(
        id: 'RTAK-AK3-SETTLE-UNPAID',
        lens: 'AK3',
        title: 'GET settle unpaid não captura',
        actor: 'anon',
        pre: 'unpaid cs',
        repro: 'GET settle',
        expected: 'não confirmado',
        obtained: settleOwnUnpaid.brief,
      );
    }
  }

  if (tipSession != null) {
    final tipSettle = await c.edge(
      'create-live-tip-checkout',
      method: 'GET',
      qs: '?checkout_return=success&session_id=$tipSession',
    );
    c.note('ak3.tip_settle', 'GET tip settle unpaid', tipSettle.brief,
        lens: 'AK3');
    if (tipSettle.body.toLowerCase().contains('pagamento recebido')) {
      c.finding(
        id: 'RTAK-AK3-TIP-SETTLE-UNPAID',
        lens: 'AK3',
        severity: 'P0',
        title: 'GET tip settle unpaid credita gorjeta',
        actor: 'anon',
        pre: 'tip Session unpaid',
        repro: 'GET create-live-tip-checkout?session_id=',
        expected: 'não confirmado',
        obtained: tipSettle.brief,
      );
    } else {
      c.hold(
        id: 'RTAK-AK3-TIP-SETTLE-UNPAID',
        lens: 'AK3',
        title: 'tip settle unpaid não credita',
        actor: 'anon',
        pre: 'unpaid tip cs',
        repro: 'GET tip settle',
        expected: 'não confirmado',
        obtained: tipSettle.brief,
      );
    }
  }

  // Cross-user: B2 GET settle of B1 session if any
  if (csAk7 != null) {
    final b2settle = await c.edge(
      'create-payment-intent',
      method: 'GET',
      jwt: c.buyer2Jwt,
      qs: '?checkout_return=success&session_id=$csAk7',
    );
    c.note('ak3.b2_settle', 'B2 GET settle B1 session', b2settle.brief,
        lens: 'AK3');
  }

  // ============================================================
  // AK6 — Storage (not chat_uploads)
  // ============================================================
  final buckets = [
    'chat_media',
    'fleaber_private',
    'avatars',
    'product-images',
    'products',
    'recordings',
    'mux',
    'live-recordings',
    'public',
  ];
  final storageRows = <Map<String, Object?>>[];
  for (final b in buckets) {
    final list = await c.req(
      'POST',
      '/storage/v1/object/list/$b',
      body: {'prefix': '', 'limit': 20},
    );
    storageRows.add({
      'bucket': b,
      'status': list.status,
      'n': list.list.length,
      'brief': clip(list.body, 120),
    });
    // chat_media listing is exact M — control only, do not re-file as primary
    if (b != 'chat_media' && list.ok && list.list.isNotEmpty) {
      c.finding(
        id: 'RTAK-AK6-LIST-$b',
        lens: 'AK6',
        severity: 'P1',
        title: 'Anon lista bucket $b',
        actor: 'anon',
        pre: 'POST object/list',
        repro: 'POST /storage/v1/object/list/$b prefix=',
        expected: '[] / 400 / RLS',
        obtained: list.snippet,
      );
    }
  }
  out['storage'] = storageRows;

  final upload = await c.req(
    'POST',
    '/storage/v1/object/chat_media/rtak-anon-$stamp.txt',
    body: 'rtak-anon-upload',
    extra: {'Content-Type': 'text/plain', 'x-upsert': 'true'},
  );
  c.note('ak6.upload', 'anon upload chat_media', upload.brief, lens: 'AK6');
  if (upload.ok) {
    c.finding(
      id: 'RTAK-AK6-ANON-UPLOAD',
      lens: 'AK6',
      severity: 'P2',
      title: 'Anon faz upload para chat_media',
      actor: 'anon',
      pre: 'sem JWT user',
      repro: 'POST /storage/v1/object/chat_media/...',
      expected: '403',
      obtained: upload.brief,
    );
  } else {
    c.hold(
      id: 'RTAK-AK6-ANON-UPLOAD',
      lens: 'AK6',
      title: 'anon upload recusado',
      actor: 'anon',
      pre: 'upload',
      repro: 'POST object',
      expected: '403',
      obtained: upload.brief,
    );
  }

  // End fixture lives (no leftover broadcast)
  await c.endLives();

  out['findings'] = c.findings;
  out['holds'] = c.holds;
  out['notes'] = c.notes;
  out['created'] = {
    'lives': c.createdLiveIds,
    'items': c.createdLiveItemIds,
    'products': c.createdProductIds,
    'orders': c.createdOrderIds,
  };
  out['exact_m_repeated'] = {
    'hub_paused_items': false,
    'invite_enum': false,
    'pairing_ended': false,
    'dual_session_classic': false,
    'mint_pos_payout': false,
    'plain_to_json': false,
  };

  final path =
      '${repoRoot()}/tool/redteam_blind_ak_$stamp/pass1.json';
  await dumpJson(path, out);
  stdout.writeln(
      'WROTE $path findings=${c.findings.length} holds=${c.holds.length}');
}
