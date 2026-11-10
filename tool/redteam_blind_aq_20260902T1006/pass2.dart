import 'dart:io';

import '_rtaq.dart';

/// Pass 2 — deepen hitch/REST após end, tip scheduled, mux scheduled, RPCs GRANT.
void main() async {
  final c = Rtaq.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  const endedRf = '651de04b-d927-4a3f-8fe7-aadbc936a8a6';
  const endedPub = 'f17816c0-36fa-4cdd-a83f-afcbba8d8208';
  const hitchLive = 'd3ecce71-91a9-494e-bfc7-dbb11c1c66cf';
  const livePubEnded = 'f2da9800-a62d-44b8-9653-ac80ce60cdb0';
  const scheduledActive = '2a266bf9-f4e1-44af-8900-9cee2b384f05';
  const scheduledPub = '6c8e305d-1819-495c-a06f-97ec312f2614';
  const tipSchedSession =
      'cs_test_a1qNEVpyQe8zaK4GqcPUKazOpD5EvLYPVkzBfBMvGbM9piYSbS3DdlMvWW';
  const sku = '517c8138-fb9e-40c1-9774-a67eedaa3d98';

  final out = <String, Object?>{
    'auditor': 'REDTEAM_BLIND_AQ_HUB_EDGE_POS_AHAM_v1',
    'pass': 2,
    'stamp': stamp,
  };

  // ---- hitch AFTER end (pass1 ended lives) ----
  final restHitchEnded = await c.rest(
    'GET',
    'live_items?id=eq.$hitchLive&select=id,price,status,quantity,is_active,item_kind,live_id',
    jwt: c.buyerJwt,
  );
  final hubHitchEnded = await c.rest(
    'GET',
    'hub_live_items_public?id=eq.$hitchLive&select=id,price,status',
  );
  final fomoEndedLive = await c.rpc('batata_hub_live_fomo_snapshot', {
    'p_live_id': livePubEnded,
  });
  final sellerHitch = await c.rest(
    'GET',
    'live_items?id=eq.$hitchLive&select=id,price,status,quantity',
    jwt: c.sellerJwt,
  );
  out['hitch_after_end'] = {
    'buyer_rest': restHitchEnded.brief,
    'hub': hubHitchEnded.brief,
    'fomo': fomoEndedLive.brief,
    'seller_rest': sellerHitch.brief,
  };
  if (restHitchEnded.list.isNotEmpty) {
    c.note('exact-AK-REST-HITCH', 'REST hitch still visible after end',
        restHitchEnded.brief,
        lens: 'AQ1');
  } else {
    c.hold(
      id: 'RTAQ-AQ1-REST-HITCH-ENDED-CLOSED',
      lens: 'AQ1',
      title: 'REST buyer esconde hitch depois de ended (AHAM)',
      actor: 'buyer JWT',
      pre: 'marketplace_product qty null, live ended',
      repro: 'GET live_items hitch',
      expected: '[]',
      obtained: restHitchEnded.brief,
    );
  }

  // recreate hitch ON AIR then immediately compare Hub vs REST vs contract
  final live2 = await c.insertLive(
    status: 'live',
    active: true,
    muxPlayback: 'rtaq_p2_live_$stamp',
    title: '$prefix p2-live',
  );
  final hitch2 = await c.insertLiveItem(
    liveId: live2!,
    title: '$prefix p2-hitch5',
    qty: null,
    price: 5,
    productId: sku,
    itemKind: 'marketplace_product',
    seller: c.sellerId,
  );
  final avail2 = await c.insertLiveItem(
    liveId: live2,
    title: '$prefix p2-avail',
    qty: 1,
    price: 6,
  );
  final restOn = await c.rest(
    'GET',
    'live_items?id=eq.$hitch2&select=id,price,status,quantity',
    jwt: c.buyerJwt,
  );
  final hubOn = await c.rest(
    'GET',
    'hub_live_items_public?id=eq.$hitch2&select=id,price,status',
  );
  final fomoOn = await c.rpc('batata_hub_live_fomo_snapshot', {
    'p_live_id': live2,
  });
  out['hitch_on_air'] = {
    'rest': restOn.brief,
    'hub': hubOn.brief,
    'fomo': fomoOn.brief,
    'hub_empty': hubOn.list.isEmpty,
    'rest_shown': restOn.list.isNotEmpty,
  };
  if (restOn.list.isNotEmpty && hubOn.list.isEmpty) {
    c.finding(
      id: 'RTAQ-AQ1-HITCH-NULLQTY-REST-VS-HUB',
      lens: 'AQ1',
      severity: 'P2',
      title:
          'Hitch marketplace qty=null visível no REST (preço live 5 €) e oculto no Hub/FOMO durante o directo',
      actor: 'buyer JWT vs anon Hub',
      pre: 'item_kind=marketplace_product quantity=null em live broadcasting',
      repro:
          'GET live_items vs GET hub_live_items_public vs FOMO no mesmo UUID',
      expected: 'as três superfícies alinhadas (ou REST também esconde qty null)',
      obtained: {
        'rest': restOn.json,
        'hub': hubOn.json,
        'fomo_items': fomoOn.json,
      },
    );
  }

  // order already created in pass1 at 5€ — confirm row
  final oldOrder = await c.rest(
    'GET',
    'orders?id=eq.431c60ad-cab9-495d-94ae-525eeb8d358d&select=id,status,price_total,contract_unit_cents,live_item_id,amount_paid_cents,stripe_checkout_session_id',
    jwt: c.buyerJwt,
  );
  out['pass1_hitch_order'] = oldOrder.brief;

  // ---- stock RPC: random UUID, live UUID as item, extra fields ----
  final stockRand = await c.rpc('batata_live_item_stock', {
    'p_live_item_id': '00000000-0000-0000-0000-000000000001',
  });
  final stockLiveAsItem = await c.rpc('batata_live_item_stock', {
    'p_live_item_id': endedPub,
  });
  final stockEnded = await c.rpc('batata_live_item_stock', {
    'p_live_item_id': endedRf,
  });
  out['stock_rand'] = stockRand.brief;
  out['stock_live_as_item'] = stockLiveAsItem.brief;
  out['stock_ended_full'] = stockEnded.json;

  // can Hub messages leak item UUIDs of ended?
  final msgs = await c.rest(
    'GET',
    'hub_live_messages_public?live_id=eq.$endedPub&select=id,body,live_id&limit=5',
  );
  out['hub_msgs_ended'] = msgs.brief;

  // other GRANTed definers
  final extraRpc = <String, Object?>{};
  for (final fn in [
    'batata_live_item_total_qty',
    'batata_mark_live_item_sold',
    'batata_live_is_draft',
    'batata_create_live_tip_pending',
    'batata_settle_live_tip_from_stripe',
    'batata_profile_discovery_slug',
  ]) {
    extraRpc[fn] = (await c.rpc(fn, {
      if (fn.contains('item')) 'p_live_item_id': endedRf,
      if (fn.contains('draft')) 'p_live_id': endedPub,
      if (fn.contains('tip_pending')) ...{
        'p_live_id': live2,
        'p_seller_id': c.sellerId,
        'p_amount': 1,
        'p_message': null,
      },
      if (fn.contains('settle')) ...{
        'p_tip_id': '00000000-0000-0000-0000-000000000001',
        'p_stripe_session_id': 'cs_test_x',
        'p_paid_amount_cents': 100,
      },
      if (fn.contains('slug')) ...{
        'p_handle': 'x',
        'p_handle_suggested': 'y',
        'p_full_name': 'z',
      },
    }))
        .brief;
  }
  out['extra_rpc_anon'] = extraRpc;

  // ---- NEW scheduled+is_active (pass1 live was ended) ----
  final schedAct2 = await c.insertLive(
    status: 'scheduled',
    active: true,
    muxPlayback: 'rtaq_p2_sched_act_$stamp',
    title: '$prefix p2-sched-act',
  );
  final schedPub2 = await c.insertLive(
    status: 'scheduled',
    active: false,
    muxPlayback: 'rtaq_p2_sched_pb_$stamp',
    muxVod: 'rtaq_p2_sched_vod_$stamp',
    title: '$prefix p2-sched-pub',
  );

  final schedHub = await c.rest(
    'GET',
    'hub_live_items_public?live_id=eq.$schedAct2&select=id',
  );
  final schedLiveRow = await c.rest(
    'GET',
    'hub_lives_public?id=eq.$schedAct2&select=id,status,is_active,mux_playback_id',
  );
  final schedFomo = await c.rpc('batata_hub_live_fomo_snapshot', {
    'p_live_id': schedAct2,
  });
  final schedBc = await c.rpc('batata_live_is_broadcasting', {
    'p_live_id': schedAct2,
  });
  out['scheduled_active_surfaces'] = {
    'id': schedAct2,
    'hub_items': schedHub.brief,
    'hub_live': schedLiveRow.brief,
    'fomo': schedFomo.brief,
    'broadcasting': schedBc.brief,
  };

  final schedPubRow = await c.rest(
    'GET',
    'hub_lives_public?id=eq.$schedPub2&select=id,status,is_active,mux_playback_id,mux_vod_playback_id,title',
  );
  out['scheduled_pub_hub'] = schedPubRow.json;

  final tipSched2 = await c.edge('create-live-tip-checkout', jwt: c.buyerJwt, body: {
    'live_id': schedAct2,
    'seller_id': c.sellerId,
    'amount_eur': 1,
  });
  out['tip_sched_act2'] = tipSched2.brief;
  if (tipSched2.hasCheckout && '${schedBc.json}' == 'false') {
    c.finding(
      id: 'RTAQ-AQ4-TIP-NOT-BROADCASTING',
      lens: 'AQ4',
      severity: 'P2',
      title:
          'Tip Checkout Session com batata_live_is_broadcasting=false (scheduled+is_active)',
      actor: 'buyer JWT',
      pre: 'Edge usa is_active && status!=ended, não a função broadcasting',
      repro: 'POST create-live-tip-checkout',
      expected: '400 Tips only while broadcasting',
      obtained: {
        'broadcasting': schedBc.json,
        'tip': tipSched2.brief,
        'session': tipSched2.checkoutId,
      },
    );
  }

  final muxSchedAct = await c.edge('resolve-mux-playback', body: {
    'live_id': schedAct2,
  });
  final muxSchedPub = await c.edge('resolve-mux-playback', body: {
    'live_id': schedPub2,
  });
  out['mux_scheduled_active'] = muxSchedAct.json;
  out['mux_scheduled_pub'] = muxSchedPub.json;
  if (muxSchedAct.ok && '${muxSchedAct.map?['source']}'.contains('live')) {
    c.finding(
      id: 'RTAQ-AQ5-MUX-SCHEDULED-ACTIVE',
      lens: 'AQ5',
      severity: 'P2',
      title:
          'resolve-mux-playback trata scheduled+is_active como HLS live (broadcasting()=false)',
      actor: 'anon',
      pre: 'status=scheduled is_active=true em hub_lives_public',
      repro: 'POST resolve-mux-playback',
      expected: '404 até status live/ao_vivo/active',
      obtained: muxSchedAct.json,
    );
  }
  if (muxSchedPub.ok && muxSchedPub.body.contains('stream.mux.com')) {
    c.finding(
      id: 'RTAQ-AQ5-MUX-SCHEDULED-VOD-CACHE',
      lens: 'AQ5',
      severity: 'P2',
      title:
          'resolve-mux-playback serve mux_vod_playback_id de directo scheduled (ainda não ocorreu)',
      actor: 'anon',
      pre: 'is_active=false tratado como ended → cache VOD',
      repro: 'POST resolve-mux-playback scheduled published',
      expected: '404 até ir ao ar / gravado real',
      obtained: muxSchedPub.json,
    );
  }

  // tip row for scheduled session
  final tipRows = await c.rest(
    'GET',
    'live_tips?stripe_session_id=eq.$tipSchedSession&select=id,status,amount,live_id,buyer_id,seller_id,stripe_session_id',
    service: true,
  );
  out['tip_scheduled_row'] = tipRows.json;
  final settleSched = await c.edge(
    'create-live-tip-checkout',
    method: 'GET',
    qs: '?checkout_return=success&session_id=$tipSchedSession',
  );
  out['settle_scheduled_tip'] = settleSched.brief;
  if (tipRows.map?['status'] == 'pending' ||
      (tipRows.list.isNotEmpty &&
          (tipRows.list.first as Map)['status'] == 'pending')) {
    c.hold(
      id: 'RTAQ-AQ7-TIP-SCHED-SESSION-NE-CAPTURE',
      lens: 'AQ7',
      title: 'Session gorjeta scheduled unpaid ≠ crédito',
      actor: 'anon GET settle',
      pre: 'cs_test scheduled+is_active',
      repro: 'GET settle',
      expected: 'pending',
      obtained: {'row': tipRows.json, 'settle': settleSched.brief},
    );
  }

  // stream key columns on hub views
  final hubStar = await c.rest(
    'GET',
    'hub_lives_public?id=eq.$scheduledPub&select=*',
  );
  out['hub_lives_star_keys'] = hubStar.map?.keys.toList();
  final hasKey = '${hubStar.body}'.contains('stream_key') ||
      '${hubStar.body}'.contains('mux_live_id');
  if (hasKey) {
    c.finding(
      id: 'RTAQ-AQ1-HUB-STREAM-KEY',
      lens: 'AQ1',
      severity: 'P1',
      title: 'hub_lives_public select=* inclui stream/mux live id',
      actor: 'anon',
      pre: 'view whitelist',
      repro: 'GET hub_lives_public select=*',
      expected: 'sem stream keys',
      obtained: hubStar.map?.keys.toList(),
    );
  }

  // buyer2 refund of hitch order
  final refundX = await c.edge('refund-order', jwt: c.buyer2Jwt, body: {
    'order_id': '431c60ad-cab9-495d-94ae-525eeb8d358d',
  });
  out['refund_cross'] = refundX.brief;

  // create-payment-intent on hitch while ON AIR
  final pi = await c.edge('create-payment-intent', jwt: c.buyerJwt, body: {
    'product_id': sku,
    'quantity': 1,
    'live_item_id': hitch2,
    'live_id': live2,
  });
  out['pi_hitch_on_air'] = pi.brief;
  if (pi.hasCheckout) {
    c.finding(
      id: 'RTAQ-AQ7-PI-HITCH-NULLQTY',
      lens: 'AQ7',
      severity: 'P2',
      title: 'Edge abre Session no hitch qty=null (preço live) oculto no Hub',
      actor: 'buyer JWT',
      pre: 'Hub [] REST 5€',
      repro: 'POST create-payment-intent live_item hitch',
      expected: '400 / item not public',
      obtained: pi.brief,
      evidence: {'session': pi.checkoutId},
    );
  }

  await c.endLives();
  await c.restoreQaSellerHandle();

  final restHitch2Ended = await c.rest(
    'GET',
    'live_items?id=eq.$hitch2&select=id,price,status',
    jwt: c.buyerJwt,
  );
  out['hitch2_after_end'] = restHitch2Ended.brief;
  if (restHitch2Ended.list.isEmpty) {
    c.hold(
      id: 'RTAQ-AQ1-HITCH2-ENDED-HIDDEN',
      lens: 'AQ1',
      title: 'hitch2 some do REST após ended',
      actor: 'buyer',
      pre: 'endLives',
      repro: 'GET live_items',
      expected: '[]',
      obtained: restHitch2Ended.brief,
    );
  }

  out['findings'] = c.findings;
  out['holds'] = c.holds;
  out['notes'] = c.notes;
  final path =
      '${Directory.current.path}/tool/redteam_blind_aq_20260902T1006/pass2.json';
  await dumpJson(path, out);
  stdout.writeln('WROTE $path findings=${c.findings.length} holds=${c.holds.length}');
}
