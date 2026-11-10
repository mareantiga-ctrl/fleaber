import 'dart:convert';
import 'dart:io';

import '_rtn.dart';

/// Pass 1 — live stream surface. No Hub paused, CORS, resolve-mux draft,
/// dual Session, mint payout, plain→JSON, invite enum, pairing ended.
void main() async {
  final c = Rtn.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final out = <String, Object?>{
    'auditor': 'REDTEAM_BLIND_N_LIVE_STREAM_v1',
    'stamp': stamp,
    'staging': projectMust,
    'seller': c.sellerId,
    'buyer': c.buyerId,
    'seller2': c.seller2Id,
    'buyer2': c.buyer2Id,
  };

  final liveA = await c.insertLive(
    seller: c.sellerId,
    status: 'live',
    active: true,
    muxPlayback: 'rtn_a_pb_$stamp',
    muxLiveId: 'rtn_a_mux_$stamp',
    muxVod: 'rtn_a_vod_$stamp',
    streamKey: 'rtn_a_sk_$stamp',
    egressId: 'EG_RTN_A_$stamp',
    roomName: 'fleaber_placeholder_a',
    viewerCount: 3,
  );
  final liveB = await c.insertLive(
    seller: c.seller2Id,
    status: 'live',
    active: true,
    muxPlayback: 'rtn_b_pb_$stamp',
    muxLiveId: 'rtn_b_mux_$stamp',
    streamKey: 'rtn_b_sk_$stamp',
    egressId: 'EG_RTN_B_$stamp',
    roomName: 'fleaber_placeholder_b',
  );
  final draftA = await c.insertLive(
    seller: c.sellerId,
    status: 'draft',
    active: false,
    muxPlayback: 'rtn_draft_pb_$stamp',
    muxLiveId: 'rtn_draft_mux_$stamp',
    streamKey: 'rtn_draft_sk_$stamp',
  );
  final endedA = await c.insertLive(
    seller: c.sellerId,
    status: 'ended',
    active: false,
    muxPlayback: 'rtn_ended_pb_$stamp',
    muxVod: 'rtn_ended_vod_$stamp',
  );
  final prod = await c.insertProduct(title: '$prefix item', qty: 2, price: 9);
  final itemA = liveA == null
      ? null
      : await c.insertLiveItem(
          liveId: liveA,
          title: '$prefix artigo',
          qty: 2,
          productId: prod,
        );
  final raffle = liveA == null
      ? null
      : await c.insertRaffle(liveId: liveA, liveItemId: itemA);
  final reqPending = (liveA != null && itemA != null)
      ? await c.insertReservation(
          liveId: liveA,
          liveItemId: itemA,
          buyer: c.buyerId,
          qty: 1,
        )
      : null;

  out['fixtures'] = {
    'liveA': liveA,
    'liveB': liveB,
    'draftA': draftA,
    'endedA': endedA,
    'itemA': itemA,
    'raffle': raffle,
    'reqPending': reqPending,
    'prod': prod,
  };

  // =====================================================================
  // Catalog — OpenAPI live/raffle paths + columns of a live row
  // =====================================================================
  final oa = await c.req(
    'GET',
    '/rest/v1/',
    extra: {'Accept': 'application/openapi+json'},
    service: true,
  );
  final oaPaths = <String>[];
  if (oa.json is Map) {
    final paths = (oa.json as Map)['paths'];
    if (paths is Map) {
      for (final k in paths.keys) {
        final s = k.toString();
        if (s.contains('live') ||
            s.contains('raffle') ||
            s.contains('mux') ||
            s.contains('viewer') ||
            s.contains('tip')) {
          oaPaths.add(s);
        }
      }
    }
  }
  oaPaths.sort();
  out['openapi_live_paths'] = oaPaths;
  c.note('p1.cat.oa', 'openapi live paths n=${oaPaths.length}', oaPaths.take(40).join(','),
      lens: 'N1');

  final liveCols = await c.rest(
    'GET',
    'lives?id=eq.$liveA&select=*',
    service: true,
  );
  out['live_columns'] = liveCols.map?.keys.toList();
  out['live_row_secrets'] = liveCols.secrets;

  // =====================================================================
  // N1 — stream key / mux id leak via REST + Hub views
  // =====================================================================
  Future<void> probeSelect({
    required String id,
    required String lens,
    required String qs,
    String? jwt,
    required String actor,
    required String title,
  }) async {
    final h = await c.rest('GET', qs, jwt: jwt);
    c.note(id, title, '${h.brief} secrets=${h.secrets}', lens: lens);
    out[id] = {'http': h.status, 'n': h.list.length, 'secrets': h.secrets};
    final leaked = h.secrets.isNotEmpty && h.ok;
    if (leaked && actor != 'seller-own') {
      c.finding(
        id: 'RTN-$id',
        lens: lens,
        severity: h.secrets.keys.any((k) =>
                k.contains('stream_key') || k.contains('mux_stream_key'))
            ? 'P0'
            : 'P1',
        title: '$actor lê segredos de directo: ${h.secrets.keys.join(",")}',
        actor: actor,
        pre: 'live A activa com stream_key fixture',
        repro: 'GET /rest/v1/$qs',
        expected: '403 / [] / sem stream_key mux_live_id egress',
        obtained: h.brief,
        evidence: {'secrets': h.secrets},
      );
    }
  }

  await probeSelect(
    id: 'n1.anon.lives.a',
    lens: 'N1',
    qs:
        'lives?id=eq.$liveA&select=id,status,mux_stream_key,stream_key,mux_live_id,livekit_egress_id,livekit_room_name,mux_playback_id',
    actor: 'anon',
    title: 'anon GET lives A secrets',
  );
  await probeSelect(
    id: 'n1.buyer.lives.a',
    lens: 'N1',
    qs:
        'lives?id=eq.$liveA&select=id,status,mux_stream_key,stream_key,mux_live_id,livekit_egress_id,mux_playback_id,seller_id',
    jwt: c.buyerJwt,
    actor: 'buyer',
    title: 'buyer GET lives A secrets',
  );
  await probeSelect(
    id: 'n1.buyer.lives.active',
    lens: 'N1',
    qs:
        'lives?status=eq.live&select=id,mux_stream_key,stream_key,mux_live_id,livekit_egress_id&limit=5',
    jwt: c.buyerJwt,
    actor: 'buyer',
    title: 'buyer GET all live rows secrets',
  );
  await probeSelect(
    id: 'n1.s2.lives.a',
    lens: 'N1',
    qs:
        'lives?id=eq.$liveA&select=id,mux_stream_key,stream_key,mux_live_id,livekit_egress_id',
    jwt: c.seller2Jwt,
    actor: 'seller2',
    title: 'seller2 GET seller1 live secrets',
  );
  final own = await c.rest(
    'GET',
    'lives?id=eq.$liveA&select=id,mux_stream_key,stream_key,mux_live_id,livekit_egress_id',
    jwt: c.sellerJwt,
  );
  c.note('n1.seller.own', 'owner GET own secrets', '${own.brief} ${own.secrets}',
      lens: 'N1');
  out['n1.seller.own'] = {'http': own.status, 'secrets': own.secrets};

  for (final v in [
    'hub_lives_public',
    'hub_lives_discovery_public',
    'hub_live_items_public',
    'hub_live_items_discovery_public',
    'hub_live_messages_public',
  ]) {
    final h = await c.rest('GET', '$v?id=eq.$liveA&select=*');
    final h2 = await c.rest(
      'GET',
      '$v?select=*&limit=3',
    );
    c.note('n1.hub.$v', 'anon $v', '${h.brief} secrets=${h.secrets} n2=${h2.list.length}',
        lens: 'N1');
    out['hub.$v'] = {
      'http': h.status,
      'secrets': h.secrets,
      'keys': h.map?.keys.toList() ?? h2.map?.keys.toList(),
    };
    if (h.secrets.isNotEmpty || h2.secrets.isNotEmpty) {
      c.finding(
        id: 'RTN-n1.hub.$v',
        lens: 'N1',
        severity: 'P0',
        title: 'view $v expõe segredos de ingest/LiveKit',
        actor: 'anon',
        pre: 'live A na vitrine',
        repro: 'GET $v',
        expected: 'sem stream_key / mux_live_id / egress',
        obtained: '${h.brief} ${h2.brief}',
        evidence: {'a': h.secrets, 'list': h2.secrets},
      );
    }
  }

  final fomo = await c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': liveA});
  c.note('n1.fomo', 'anon FOMO live A', fomo.brief, lens: 'N1');
  out['fomo'] = fomo.json;
  if (fomo.secrets.isNotEmpty) {
    c.finding(
      id: 'RTN-n1.fomo',
      lens: 'N1',
      severity: 'P1',
      title: 'FOMO devolve segredos Mux/LiveKit',
      actor: 'anon',
      pre: 'live A pública',
      repro: 'rpc batata_hub_live_fomo_snapshot',
      expected: 'agregados sem keys',
      obtained: fomo.brief,
      evidence: fomo.secrets,
    );
  }

  // =====================================================================
  // N2 — hijack: PATCH/INSERT/complete/stop_egress
  // =====================================================================
  final patchOther = await c.rest(
    'PATCH',
    'lives?id=eq.$liveA',
    jwt: c.buyerJwt,
    body: {'status': 'ended', 'is_active': false},
  );
  c.note('n2.buyer.patch.a', 'buyer PATCH live A ended', patchOther.brief,
      lens: 'N2');
  if (patchOther.ok && (patchOther.list.isNotEmpty || patchOther.map != null)) {
    c.finding(
      id: 'RTN-n2.buyer.patch',
      lens: 'N2',
      severity: 'P0',
      title: 'comprador termina/altera directo alheio via REST',
      actor: 'buyer',
      pre: 'live A activa do vendedor',
      repro: 'PATCH lives?id=eq.A {status:ended}',
      expected: '403 / 0 rows',
      obtained: patchOther.brief,
    );
  } else {
    c.hold(
      id: 'n2.buyer.patch',
      lens: 'N2',
      title: 'buyer PATCH live alheia recusado',
      actor: 'buyer',
      obtained: patchOther,
    );
  }

  final s2end = await c.rest(
    'PATCH',
    'lives?id=eq.$liveA',
    jwt: c.seller2Jwt,
    body: {'status': 'ended', 'is_active': false},
  );
  c.note('n2.s2.patch.a', 'seller2 PATCH live A', s2end.brief, lens: 'N2');
  if (s2end.ok && (s2end.list.isNotEmpty || s2end.map != null)) {
    c.finding(
      id: 'RTN-n2.s2.patch',
      lens: 'N2',
      severity: 'P0',
      title: 'outro vendedor termina directo alheio',
      actor: 'seller2',
      pre: 'live A de seller1',
      repro: 'PATCH lives seller2 JWT',
      expected: '0 rows',
      obtained: s2end.brief,
    );
  }

  final ownMuxSwap = await c.rest(
    'PATCH',
    'lives?id=eq.$liveA',
    jwt: c.sellerJwt,
    body: {
      'mux_live_id': 'rtn_b_mux_$stamp',
      'mux_stream_key': 'rtn_b_sk_$stamp',
      'stream_key': 'rtn_b_sk_$stamp',
    },
  );
  c.note('n2.owner.muxswap', 'owner PATCH mux ids of B onto A', ownMuxSwap.brief,
      lens: 'N2');
  out['n2.owner.muxswap'] = ownMuxSwap.brief;
  final afterSwap = await c.rest(
    'GET',
    'lives?id=eq.$liveA&select=id,mux_live_id,mux_stream_key',
    service: true,
  );
  final swapped = afterSwap.map?['mux_live_id']?.toString() == 'rtn_b_mux_$stamp';
  if (ownMuxSwap.ok && swapped) {
    c.finding(
      id: 'RTN-n2.owner.muxswap',
      lens: 'N2',
      severity: 'P1',
      title: 'dono reescreve mux_live_id/stream_key da própria row (hijack Mux alheio se conhecer o id)',
      actor: 'seller',
      pre: 'JWT dono; body com mux_live_id do vendedor B',
      repro: 'PATCH lives mux_live_id=<B>',
      expected: 'colunas Mux imutáveis / só Edge escreve',
      obtained: afterSwap.map?['mux_live_id'],
      evidence: {'after': afterSwap.map},
    );
    await c.rest('PATCH', 'lives?id=eq.$liveA', service: true, body: {
      'mux_live_id': 'rtn_a_mux_$stamp',
      'mux_stream_key': 'rtn_a_sk_$stamp',
      'stream_key': 'rtn_a_sk_$stamp',
    }, prefer: 'return=minimal');
  } else {
    c.hold(
      id: 'n2.owner.muxswap',
      lens: 'N2',
      title: 'owner não reescreve mux ids (ou trigger reverte)',
      actor: 'seller',
      obtained: '${ownMuxSwap.brief} after=${afterSwap.map?['mux_live_id']}',
    );
  }

  final insAlien = await c.rest(
    'POST',
    'lives',
    jwt: c.buyerJwt,
    body: {
      'title': '$prefix hijack',
      'status': 'live',
      'is_active': true,
      'seller_id': c.sellerId,
      'vendedor_id': c.sellerId,
      'mux_stream_key': 'rtn_a_sk_$stamp',
    },
  );
  c.note('n2.buyer.insert', 'buyer INSERT live as seller', insAlien.brief,
      lens: 'N2');
  if (insAlien.ok && insAlien.firstId != null) {
    c.createdLiveIds.add(insAlien.firstId!);
    c.finding(
      id: 'RTN-n2.buyer.insert',
      lens: 'N2',
      severity: 'P0',
      title: 'comprador cria row lives em nome do vendedor',
      actor: 'buyer',
      pre: 'JWT comprador, seller_id alheio',
      repro: 'POST lives',
      expected: '403',
      obtained: insAlien.brief,
    );
  } else {
    c.hold(
      id: 'n2.buyer.insert',
      lens: 'N2',
      title: 'buyer INSERT lives recusado',
      actor: 'buyer',
      obtained: insAlien,
    );
  }

  final completeX = await c.edge(
    'complete-mux-live',
    body: {'live_id': liveA},
    jwt: c.buyerJwt,
  );
  c.note('n2.complete.buyer', 'buyer complete-mux live A', completeX.brief,
      lens: 'N2');
  if (completeX.ok) {
    c.finding(
      id: 'RTN-n2.complete.buyer',
      lens: 'N2',
      severity: 'P0',
      title: 'comprador completa/termina Mux de outro',
      actor: 'buyer',
      pre: 'live A do vendedor',
      repro: 'POST complete-mux-live',
      expected: '403',
      obtained: completeX.brief,
    );
  } else {
    c.hold(
      id: 'n2.complete.buyer',
      lens: 'N2',
      title: 'buyer complete-mux 403',
      actor: 'buyer',
      obtained: completeX,
    );
  }

  final completeS2 = await c.edge(
    'complete-mux-live',
    body: {'live_id': liveA},
    jwt: c.seller2Jwt,
  );
  c.note('n2.complete.s2', 'seller2 complete-mux live A', completeS2.brief,
      lens: 'N2');
  if (completeS2.ok) {
    c.finding(
      id: 'RTN-n2.complete.s2',
      lens: 'N2',
      severity: 'P0',
      title: 'seller2 complete-mux da live A',
      actor: 'seller2',
      pre: 'não dono',
      repro: 'POST complete-mux-live live_id=A',
      expected: '403',
      obtained: completeS2.brief,
    );
  }

  final stopForeign = await c.edge(
    'livekit-mux-publish',
    body: {
      'step': 'stop_egress',
      'live_id': liveA,
      'egress_id': 'EG_RTN_B_$stamp',
    },
    jwt: c.sellerJwt,
  );
  c.note('n2.stop.foreign', 'owner A stop_egress id de B', stopForeign.brief,
      lens: 'N4');
  out['n2.stop.foreign'] = stopForeign.brief;
  final bAfter = await c.rest(
    'GET',
    'lives?id=eq.$liveB&select=id,livekit_egress_id,is_active,status',
    service: true,
  );
  out['n2.liveB.after_stop'] = bAfter.map;
  final stillB = bAfter.map?['livekit_egress_id']?.toString();
  if (stopForeign.status == 200 && stillB == null) {
    c.finding(
      id: 'RTN-n2.stop.foreign',
      lens: 'N4',
      severity: 'P1',
      title: 'stop_egress com egress_id alheio apaga/para o de B',
      actor: 'seller',
      pre: 'JWT dono A, body.egress_id = EG de B',
      repro: 'POST livekit-mux-publish step=stop_egress egress_id=<B>',
      expected: 'recusar id que não pertence à live A',
      obtained: '${stopForeign.brief} B.egress=$stillB',
    );
  } else if (stopForeign.status == 200) {
    c.finding(
      id: 'RTN-n2.stop.idor',
      lens: 'N4',
      severity: 'P2',
      title: 'stop_egress aceita egress_id arbitrário (LiveKit API, sem gate de dono do egress)',
      actor: 'seller',
      pre: 'dono A passa egress_id de B (fixture, LiveKit pode 404)',
      repro: 'POST livekit-mux-publish step=stop_egress egress_id=EG_RTN_B',
      expected: '403 se egress não é da live A',
      obtained: stopForeign.brief,
      evidence: {'liveB': bAfter.map},
    );
  } else {
    c.hold(
      id: 'n2.stop.foreign',
      lens: 'N4',
      title: 'stop_egress foreign não 200',
      actor: 'seller',
      obtained: stopForeign,
    );
  }

  // =====================================================================
  // N4 — LiveKit token grants / cross-user
  // =====================================================================
  final tokBuyer = await c.edge(
    'livekit-mux-publish',
    body: {'step': 'token', 'live_id': liveA},
    jwt: c.buyerJwt,
  );
  c.note('n4.token.buyer', 'buyer LiveKit token A', tokBuyer.brief, lens: 'N4');
  if (tokBuyer.ok && (tokBuyer.map?['token'] != null)) {
    c.finding(
      id: 'RTN-n4.token.buyer',
      lens: 'N4',
      severity: 'P0',
      title: 'comprador obtém token publisher LiveKit da live alheia',
      actor: 'buyer',
      pre: 'live A',
      repro: 'POST livekit-mux-publish step=token',
      expected: '403',
      obtained: tokBuyer.brief,
    );
  } else {
    c.hold(
      id: 'n4.token.buyer',
      lens: 'N4',
      title: 'buyer token LiveKit recusado',
      actor: 'buyer',
      obtained: tokBuyer,
    );
  }

  final tokS2 = await c.edge(
    'livekit-mux-publish',
    body: {'step': 'token', 'live_id': liveA},
    jwt: c.seller2Jwt,
  );
  c.note('n4.token.s2', 'seller2 token live A', tokS2.brief, lens: 'N4');
  if (tokS2.ok && tokS2.map?['token'] != null) {
    c.finding(
      id: 'RTN-n4.token.s2',
      lens: 'N4',
      severity: 'P0',
      title: 'seller2 token LiveKit da live A',
      actor: 'seller2',
      pre: 'não dono',
      repro: 'step=token live_id=A',
      expected: '403',
      obtained: tokS2.brief,
    );
  }

  final tokOwn = await c.edge(
    'livekit-mux-publish',
    body: {'step': 'token', 'live_id': liveA},
    jwt: c.sellerJwt,
  );
  c.note('n4.token.own', 'owner token (grants)', tokOwn.brief, lens: 'N4');
  out['n4.token.own.keys'] = tokOwn.map?.keys.toList();
  final jwtTok = tokOwn.map?['token']?.toString();
  if (jwtTok != null && jwtTok.contains('.')) {
    try {
      final payload = jwtTok.split('.')[1];
      var p = payload;
      while (p.length % 4 != 0) {
        p += '=';
      }
      final decoded = utf8.decode(base64Url.decode(p));
      out['n4.token.grants'] = jsonDecode(decoded);
      c.note('n4.token.grants', 'decoded video grant', decoded, lens: 'N4');
    } catch (e) {
      out['n4.token.decode_err'] = e.toString();
    }
  }

  final egressInject = await c.edge(
    'livekit-mux-publish',
    body: {
      'step': 'egress',
      'live_id': liveA,
      'stream_key': 'stolen-other-key',
    },
    jwt: c.sellerJwt,
  );
  c.note('n4.egress.inject', 'owner inject foreign stream_key', egressInject.brief,
      lens: 'N4');
  if (egressInject.ok) {
    c.finding(
      id: 'RTN-n4.egress.inject',
      lens: 'N4',
      severity: 'P1',
      title: 'egress aceita stream_key injectado',
      actor: 'seller',
      pre: 'body.stream_key ≠ key da live',
      repro: 'step=egress stream_key=stolen',
      expected: '403',
      obtained: egressInject.brief,
    );
  } else {
    c.hold(
      id: 'n4.egress.inject',
      lens: 'N4',
      title: 'stream_key inject recusado ou sem key real Mux',
      actor: 'seller',
      obtained: egressInject,
    );
  }

  // create-mux extra fields — buyer only (authz before Mux, no quota)
  final muxBuyer = await c.edge(
    'create-mux-live',
    body: {
      'title': '$prefix mux',
      'seller_id': c.sellerId,
      'stream_key': 'injected',
      'mux_live_id': 'injected',
    },
    jwt: c.buyerJwt,
  );
  c.note('n2.mux.buyer', 'buyer create-mux extra fields', muxBuyer.brief,
      lens: 'N2');
  if (muxBuyer.ok) {
    c.finding(
      id: 'RTN-n2.mux.buyer',
      lens: 'N2',
      severity: 'P0',
      title: 'comprador cria stream Mux',
      actor: 'buyer',
      pre: 'JWT comprador',
      repro: 'POST create-mux-live',
      expected: '403',
      obtained: muxBuyer.brief,
    );
  } else {
    c.hold(
      id: 'n2.mux.buyer',
      lens: 'N2',
      title: 'buyer create-mux-live recusado',
      actor: 'buyer',
      obtained: muxBuyer,
    );
  }

  // =====================================================================
  // N5 — live bag / catalog authority
  // =====================================================================
  final updItem = await c.rpc(
    'batata_update_live_item',
    {'p_live_item_id': itemA, 'p_quantity': 99, 'p_price': 0.01},
    jwt: c.buyerJwt,
  );
  c.note('n5.update.item.buyer', 'buyer update live item qty/price', updItem.brief,
      lens: 'N5');
  out['n5.update.item'] = updItem.json ?? updItem.snippet;
  final itemAfter = await c.rest(
    'GET',
    'live_items?id=eq.$itemA&select=id,quantity,price,status',
    service: true,
  );
  out['n5.item.after'] = itemAfter.map;
  final q = itemAfter.map?['quantity'];
  final p = itemAfter.map?['price'];
  if (updItem.ok && (q == 99 || p == 0.01 || p == 0.01.toString())) {
    c.finding(
      id: 'RTN-n5.update.item',
      lens: 'N5',
      severity: 'P0',
      title: 'comprador altera qty/preço do artigo da live',
      actor: 'buyer',
      pre: 'item A qty=2 price=12',
      repro: 'rpc batata_update_live_item qty=99 price=0.01',
      expected: 'not_allowed',
      obtained: '${updItem.brief} after=$q $p',
    );
  } else {
    c.hold(
      id: 'n5.update.item',
      lens: 'N5',
      title: 'buyer update live item recusado ou sem efeito',
      actor: 'buyer',
      obtained: '${updItem.brief} q=$q p=$p',
    );
  }

  final sold = await c.rpc(
    'batata_mark_live_item_sold',
    {'p_live_item_id': itemA},
    jwt: c.buyerJwt,
  );
  c.note('n5.sold.buyer', 'buyer mark sold', sold.brief, lens: 'N5');
  if (sold.ok &&
      (sold.map?['ok'] == true ||
          itemAfter.map?['status'] == 'sold' /* stale */)) {
    final chk = await c.rest(
      'GET',
      'live_items?id=eq.$itemA&select=status',
      service: true,
    );
    if (chk.map?['status']?.toString() == 'sold') {
      c.finding(
        id: 'RTN-n5.sold.buyer',
        lens: 'N5',
        severity: 'P1',
        title: 'comprador marca artigo da live como vendido',
        actor: 'buyer',
        pre: 'item disponível',
        repro: 'rpc batata_mark_live_item_sold',
        expected: 'not_allowed',
        obtained: '${sold.brief} ${chk.map}',
      );
    } else {
      c.hold(
        id: 'n5.sold.buyer',
        lens: 'N5',
        title: 'buyer mark sold sem persistir',
        actor: 'buyer',
        obtained: sold,
      );
    }
  } else {
    c.hold(
      id: 'n5.sold.buyer',
      lens: 'N5',
      title: 'buyer mark sold recusado',
      actor: 'buyer',
      obtained: sold,
    );
  }

  final draftX = await c.rpc(
    'batata_ensure_draft_live',
    {'p_seller_id': c.sellerId},
    jwt: c.buyerJwt,
  );
  c.note('n5.draft.buyer', 'buyer ensure_draft as seller', draftX.brief,
      lens: 'N5');
  final draftOk = draftX.ok &&
      draftX.body.contains('-') &&
      !draftX.body.toLowerCase().contains('not_allowed') &&
      !draftX.body.toLowerCase().contains('error');
  if (draftOk && draftX.status == 200) {
    c.finding(
      id: 'RTN-n5.draft.buyer',
      lens: 'N5',
      severity: 'P1',
      title: 'comprador cria/obtém draft live do vendedor',
      actor: 'buyer',
      pre: 'p_seller_id alheio',
      repro: 'rpc batata_ensure_draft_live',
      expected: 'not_allowed',
      obtained: draftX.brief,
    );
  } else {
    c.hold(
      id: 'n5.draft.buyer',
      lens: 'N5',
      title: 'buyer ensure_draft recusado',
      actor: 'buyer',
      obtained: draftX,
    );
  }

  final proc = reqPending == null
      ? null
      : await c.rpc(
          'batata_process_live_reservation_request',
          {
            'p_request_id': reqPending,
            'p_action': 'accept',
            'p_processed_by': c.buyerId,
          },
          jwt: c.buyerJwt,
        );
  if (proc != null) {
    c.note('n5.accept.buyer', 'buyer accept own reservation', proc.brief,
        lens: 'N5');
    out['n5.accept'] = proc.json ?? proc.snippet;
    final acc = proc.map?['ok'] == true ||
        (proc.body.contains('accepted') && proc.ok);
    if (acc) {
      c.finding(
        id: 'RTN-n5.accept.buyer',
        lens: 'N5',
        severity: 'P1',
        title: 'comprador aceita a própria reserva (autoridade de vendedor)',
        actor: 'buyer',
        pre: 'pedido pending',
        repro: 'rpc batata_process_live_reservation_request action=accept',
        expected: 'not_allowed',
        obtained: proc.brief,
      );
    } else {
      c.hold(
        id: 'n5.accept.buyer',
        lens: 'N5',
        title: 'buyer accept reserva recusado',
        actor: 'buyer',
        obtained: proc,
      );
    }
  }

  final patchItem = await c.rest(
    'PATCH',
    'live_items?id=eq.$itemA',
    jwt: c.buyerJwt,
    body: {'quantity': 99, 'price': 0.01},
  );
  c.note('n5.rest.patch.item', 'buyer REST PATCH live_items', patchItem.brief,
      lens: 'N5');
  if (patchItem.ok && patchItem.list.isNotEmpty) {
    c.finding(
      id: 'RTN-n5.rest.patch.item',
      lens: 'N5',
      severity: 'P0',
      title: 'comprador PATCH live_items qty/preço',
      actor: 'buyer',
      pre: 'item A',
      repro: 'PATCH live_items',
      expected: '403 / 0 rows',
      obtained: patchItem.brief,
    );
  }

  // =====================================================================
  // N6 — raffle
  // =====================================================================
  final createR = await c.rpc(
    'batata_create_live_raffle',
    {
      'p_live_id': liveA,
      'p_title': '$prefix rifa buyer',
      'p_activate': true,
      'p_winner_count': 1,
    },
    jwt: c.buyerJwt,
  );
  c.note('n6.create.buyer', 'buyer create raffle on A', createR.brief, lens: 'N6');
  if (createR.ok && createR.map?['ok'] == true) {
    c.finding(
      id: 'RTN-n6.create.buyer',
      lens: 'N6',
      severity: 'P1',
      title: 'comprador cria rifa no directo alheio',
      actor: 'buyer',
      pre: 'live A do vendedor',
      repro: 'rpc batata_create_live_raffle',
      expected: 'not seller',
      obtained: createR.brief,
    );
  } else {
    c.hold(
      id: 'n6.create.buyer',
      lens: 'N6',
      title: 'buyer create raffle recusado',
      actor: 'buyer',
      obtained: createR,
    );
  }

  final join = raffle == null
      ? null
      : await c.rpc('batata_join_live_raffle', {'p_raffle_id': raffle},
          jwt: c.buyerJwt);
  if (join != null) {
    c.note('n6.join', 'buyer join raffle', join.brief, lens: 'N6');
    out['n6.join'] = join.json ?? join.snippet;
  }
  final join2 = raffle == null
      ? null
      : await c.rpc('batata_join_live_raffle', {'p_raffle_id': raffle},
          jwt: c.buyerJwt);
  if (join2 != null) {
    c.note('n6.join2', 'buyer join again', join2.brief, lens: 'N6');
    final bal1 = join?.map?['ticket_balance'];
    final bal2 = join2.map?['ticket_balance'];
    if (join2.map?['ok'] == true &&
        bal1 is num &&
        bal2 is num &&
        bal2 > bal1) {
      c.finding(
        id: 'RTN-n6.join.dup',
        lens: 'N6',
        severity: 'P2',
        title: 'join duplicado aumenta tickets',
        actor: 'buyer',
        pre: 'já joined',
        repro: 'rpc batata_join_live_raffle ×2',
        expected: 'duplicate sem +tickets',
        obtained: 'bal $bal1 → $bal2',
      );
    }
  }

  final drawB = raffle == null
      ? null
      : await c.rpc(
          'batata_draw_live_raffle_winners', {'p_raffle_id': raffle},
          jwt: c.buyerJwt);
  if (drawB != null) {
    c.note('n6.draw.buyer', 'buyer draw', drawB.brief, lens: 'N6');
    if (drawB.ok && drawB.map?['ok'] == true) {
      c.finding(
        id: 'RTN-n6.draw.buyer',
        lens: 'N6',
        severity: 'P1',
        title: 'comprador sorteia rifa alheia',
        actor: 'buyer',
        pre: 'rifa do vendedor',
        repro: 'rpc batata_draw_live_raffle_winners',
        expected: 'assert seller',
        obtained: drawB.brief,
      );
    } else {
      c.hold(
        id: 'n6.draw.buyer',
        lens: 'N6',
        title: 'buyer draw recusado',
        actor: 'buyer',
        obtained: drawB,
      );
    }
  }

  final tick = raffle == null
      ? null
      : await c.rpc('batata_tick_live_raffle', {'p_raffle_id': raffle},
          jwt: c.buyerJwt);
  if (tick != null) {
    c.note('n6.tick.buyer', 'buyer tick raffle', tick.brief, lens: 'N6');
  }

  final award = raffle == null
      ? null
      : await c.rpc(
          'batata_award_live_raffle_purchase_bonus',
          {'p_raffle_id': raffle, 'p_order_id': '00000000-0000-0000-0000-000000000001'},
          jwt: c.buyerJwt,
        );
  if (award != null) {
    c.note('n6.award.fake', 'buyer award bonus fake order', award.brief,
        lens: 'N6');
    if (award.ok && award.map?['ok'] == true) {
      c.finding(
        id: 'RTN-n6.award.fake',
        lens: 'N6',
        severity: 'P1',
        title: 'bonus de compra com order forjada',
        actor: 'buyer',
        pre: 'order uuid inexistente',
        repro: 'rpc batata_award_live_raffle_purchase_bonus',
        expected: 'fail',
        obtained: award.brief,
      );
    }
  }

  final restRaffle = await c.rest(
    'POST',
    'live_raffles',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveA,
      'seller_id': c.sellerId,
      'title': '$prefix forged',
      'status': 'active',
      'winner_count': 1,
    },
  );
  c.note('n6.rest.insert', 'buyer INSERT live_raffles', restRaffle.brief,
      lens: 'N6');
  if (restRaffle.ok && restRaffle.firstId != null) {
    c.createdRaffleIds.add(restRaffle.firstId!);
    c.finding(
      id: 'RTN-n6.rest.insert',
      lens: 'N6',
      severity: 'P1',
      title: 'comprador INSERT live_raffles REST',
      actor: 'buyer',
      pre: 'JWT comprador',
      repro: 'POST live_raffles',
      expected: '403',
      obtained: restRaffle.brief,
    );
  }

  // =====================================================================
  // N7 — messages / viewer / tips
  // =====================================================================
  final sys = await c.rpc(
    'batata_live_system_message',
    {
      'p_live_id': liveA,
      'p_body': 'RTN sistema forjado',
      'p_sender_label': 'Sistema',
    },
    jwt: c.buyerJwt,
  );
  c.note('n7.sys.buyer', 'buyer system message', sys.brief, lens: 'N7');
  out['n7.sys'] = sys.json ?? sys.snippet;
  if (sys.ok && sys.map?['ok'] == true) {
    c.finding(
      id: 'RTN-n7.sys.buyer',
      lens: 'N7',
      severity: 'P1',
      title: 'comprador injeta mensagem kind=system no chat do directo',
      actor: 'buyer',
      pre: 'JWT comprador, live A',
      repro: 'rpc batata_live_system_message',
      expected: 'not_allowed (só vendedor/staff)',
      obtained: sys.brief,
    );
  } else {
    c.hold(
      id: 'n7.sys.buyer',
      lens: 'N7',
      title: 'buyer system message recusado',
      actor: 'buyer',
      obtained: sys,
    );
  }

  final msgIns = await c.rest(
    'POST',
    'live_messages',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveA,
      'kind': 'system',
      'body': 'RTN rest system',
      'sender_label': 'Sistema',
      'user_id': c.sellerId,
    },
  );
  c.note('n7.msg.insert', 'buyer INSERT live_messages system', msgIns.brief,
      lens: 'N7');
  if (msgIns.ok && msgIns.firstId != null) {
    c.finding(
      id: 'RTN-n7.msg.insert',
      lens: 'N7',
      severity: 'P1',
      title: 'comprador INSERT live_messages kind=system (user_id do vendedor)',
      actor: 'buyer',
      pre: 'REST live_messages',
      repro: 'POST live_messages kind=system user_id=seller',
      expected: '403 ou kind forçado a chat',
      obtained: msgIns.brief,
    );
  } else {
    c.hold(
      id: 'n7.msg.insert',
      lens: 'N7',
      title: 'buyer INSERT system message recusado',
      actor: 'buyer',
      obtained: msgIns,
    );
  }

  final ping = await c.rpc(
    'batata_live_viewer_ping',
    {'p_live_id': liveA},
    jwt: c.buyerJwt,
  );
  c.note('n7.ping', 'buyer viewer ping', ping.brief, lens: 'N7');
  out['n7.ping'] = ping.json ?? ping.snippet;

  final pingDraft = await c.rpc(
    'batata_live_viewer_ping',
    {'p_live_id': draftA},
    jwt: c.buyerJwt,
  );
  c.note('n7.ping.draft', 'buyer ping draft', pingDraft.brief, lens: 'N7');

  final vcPatch = await c.rest(
    'PATCH',
    'lives?id=eq.$liveA',
    jwt: c.buyerJwt,
    body: {'viewer_count': 99999},
  );
  c.note('n7.vc.patch', 'buyer PATCH viewer_count', vcPatch.brief, lens: 'N7');
  if (vcPatch.ok && vcPatch.list.isNotEmpty) {
    c.finding(
      id: 'RTN-n7.vc.patch',
      lens: 'N7',
      severity: 'P2',
      title: 'comprador PATCH viewer_count',
      actor: 'buyer',
      pre: 'live A',
      repro: 'PATCH lives viewer_count=99999',
      expected: '0 rows',
      obtained: vcPatch.brief,
    );
  }

  final tip = await c.rpc(
    'batata_send_live_tip_from_wallet',
    {
      'p_live_id': liveA,
      'p_seller_id': c.buyerId,
      'p_amount': 0.01,
      'p_message': 'rtn',
    },
    jwt: c.buyerJwt,
  );
  c.note('n7.tip.self', 'tip wallet seller_id=self', tip.brief, lens: 'N7');
  out['n7.tip'] = tip.json ?? tip.snippet;
  if (tip.ok &&
      (tip.map?['ok'] == true || (tip.body.contains('tip') && !tip.body.contains('error')))) {
    // only finding if wallet actually moved — check later pass
    c.note('n7.tip.maybe', 'tip rpc 200 — verificar Δwallet pass2', tip.brief,
        lens: 'N7');
  }

  final tipEdge = await c.edge(
    'create-live-tip-checkout',
    body: {
      'live_id': liveA,
      'seller_id': c.seller2Id,
      'amount_eur': 1.0,
      'buyer_id': c.sellerId,
    },
    jwt: c.buyerJwt,
  );
  c.note('n7.tip.edge.bind', 'tip checkout bind seller2 + buyer_id spoof',
      tipEdge.brief,
      lens: 'N7');
  out['n7.tip.edge'] = tipEdge.brief;

  // ingest OCR without token + with token on alien live
  final ocr = await c.edge(
    'ingest-ocr-reservation',
    body: {
      'live_id': liveA,
      'ocr_line_hash': 'rtn2019hashxxxx',
      'requested_qty': 9,
      'ref_slug': 'RTN1',
    },
    jwt: c.buyerJwt,
  );
  c.note('n7.ocr.jwt', 'OCR JWT sem device token', ocr.brief, lens: 'N5');
  if (ocr.ok && ocr.map?['ok'] == true) {
    c.finding(
      id: 'RTN-n7.ocr.jwt',
      lens: 'N5',
      severity: 'P1',
      title: 'OCR ingest aceita JWT comprador sem device token',
      actor: 'buyer',
      pre: 'sem x-device-token',
      repro: 'POST ingest-ocr-reservation',
      expected: '401 missing_device_token',
      obtained: ocr.brief,
    );
  } else {
    c.hold(
      id: 'n7.ocr.jwt',
      lens: 'N5',
      title: 'OCR sem token recusado',
      actor: 'buyer',
      obtained: ocr,
    );
  }

  // replay resolve-mux only as residual note (not primary)
  final muxPb = await c.edge(
    'resolve-mux-playback',
    body: {'live_id': draftA},
  );
  c.note('n3.mux.draft.residual', 'resolve-mux draft (M residual, não finding novo)',
      muxPb.brief,
      lens: 'N3');

  await c.endLives();

  out['findings'] = c.findings;
  out['holds'] = c.holds;
  out['notes'] = c.notes;
  out['atrofia_pass1_classes'] = {
    'hub_paused_items': false,
    'resolve_mux_draft_primary': false,
    'cors_reflect': false,
    'chat_media_list': false,
    'dual_session': false,
    'mint_pos_payout': false,
    'plain_to_json': false,
    'invite_enum': false,
    'pairing_ended': false,
  };

  await dumpJson('${outDir()}/pass1.json', out);
  stdout.writeln('FINDINGS ${c.findings.length} HOLDS ${c.holds.length}');
  stdout.writeln('WROTE ${outDir()}/pass1.json');
}
