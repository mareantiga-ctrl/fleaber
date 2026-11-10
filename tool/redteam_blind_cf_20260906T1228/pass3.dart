/// REDTEAM_BLIND_CF_LIVE_POS_BXCC_v1 — pass3 race end∥accept + Mux + caixa.
/// Staging only. No fixes.
import 'dart:io';

import '_rtcf.dart';

Future<void> main() async {
  final c = Rtcf.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2(hubPublished: false);

  // --- Race end ∥ accept ---
  final liveR = await c.createLive(title: '$prefix race end');
  final skuR =
      await c.createProduct(title: '$prefix race sku', qty: 1, live: true);
  final liR = (liveR == null || skuR == null)
      ? null
      : await c.createLiveItem(
          liveId: liveR,
          title: '$prefix race item',
          ref: 'RTCF-RC',
          kind: 'live_only',
          checkoutProductId: skuR,
          quantity: 1,
        );
  if (liveR == null || liR == null) {
    stderr.writeln('race fixture fail');
    await c.endAllCreatedLives();
    exit(4);
  }
  final rRace = await c.insertReservation(
    liveId: liveR,
    liveItemId: liR,
    jwt: c.buyerJwt,
    buyer: c.buyerId,
  );
  if (rRace == null) {
    stderr.writeln('race pending fail');
    await c.endAllCreatedLives();
    exit(4);
  }

  final raced = await Future.wait([
    c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$rRace',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    ),
    c.rest(
      'PATCH',
      'lives?id=eq.$liveR',
      service: true,
      body: {'status': 'ended', 'is_active': false},
    ),
    c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$rRace',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    ),
  ]);
  final afterRace = await c.rest(
    'GET',
    'live_reservation_requests?id=eq.$rRace&select=id,status,updated_at',
    service: true,
  );
  final liveAfter = await c.rest(
    'GET',
    'lives?id=eq.$liveR&select=id,status,is_active',
    service: true,
  );
  c.note('p3.race.raw', 'end∥accept hits', {
    'accept1': raced[0].brief,
    'end': raced[1].brief,
    'accept2': raced[2].brief,
    'res': afterRace.map,
    'live': liveAfter.map,
  }, lens: 'CF6');

  final ended = liveAfter.map?['status']?.toString() == 'ended' &&
      liveAfter.map?['is_active'] != true;
  final accepted = afterRace.map?['status']?.toString() == 'accepted';

  final rAfterEnd = await c.insertReservation(
    liveId: liveR,
    liveItemId: liR,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  HttpHit? accAfterEnd;
  Map<String, dynamic>? rowAfterEnd;
  if (rAfterEnd != null) {
    accAfterEnd = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$rAfterEnd',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    rowAfterEnd = (await c.rest(
      'GET',
      'live_reservation_requests?id=eq.$rAfterEnd&select=id,status',
      service: true,
    ))
        .map;
    c.hold(
      id: 'p3.pending.after.end',
      lens: 'CF6',
      severity: 'P1',
      title: 'Pending criado depois da live ended',
      actor: 'buyer2 JWT',
      pre: 'live status=ended is_active=false',
      repro: 'POST live_reservation_requests após end',
      expected: 'live_ended',
      obtained: {
        'res_id': rAfterEnd,
        'accept': accAfterEnd.brief,
        'row': rowAfterEnd,
      },
    );
  } else {
    c.block('p3.pending.after.end', 'CF6', 'pending pós-end recusado',
        'no row');
  }

  if (ended && accepted) {
    c.note(
      'p3.race.accept.won',
      'accept ganhou a race contra end (reserva accepted em live ended)',
      afterRace.map,
      lens: 'CF6',
    );
  }

  if (ended && !accepted) {
    final accLate = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$rRace',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    final lateRow = await c.rest(
      'GET',
      'live_reservation_requests?id=eq.$rRace&select=id,status',
      service: true,
    );
    if (lateRow.map?['status'] == 'accepted') {
      c.hold(
        id: 'p3.accept.after.end',
        lens: 'CF6',
        severity: 'P1',
        title: 'Accept depois da live já ended',
        actor: 'seller JWT',
        pre: 'live ended; reserva ainda pending',
        repro: 'PATCH accepted após end',
        expected: 'live_ended',
        obtained: {'patch': accLate.brief, 'row': lateRow.map},
      );
    } else {
      c.block('p3.accept.after.end', 'CF6', 'accept pós-end recusado',
          accLate.brief);
    }
  }

  // Convert após end.
  if (ended && (accepted || afterRace.map?['status'] == 'accepted')) {
    final convEnd = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$rRace',
      jwt: c.sellerJwt,
      body: {'status': 'converted'},
    );
    final afterConvEnd = await c.rest(
      'GET',
      'live_reservation_requests?id=eq.$rRace&select=id,status',
      service: true,
    );
    if (convEnd.ok && afterConvEnd.map?['status'] == 'converted') {
      c.hold(
        id: 'p3.convert.after.end.nopi',
        lens: 'CF1',
        severity: 'P0',
        title: 'Convert após end sem PI',
        actor: 'seller JWT',
        pre: 'live ended; accepted; sem captura',
        repro: 'PATCH converted',
        expected: 'convert_requires_paid_order',
        obtained: {'patch': convEnd.brief, 'row': afterConvEnd.map},
      );
    } else {
      c.block('p3.convert.after.end.nopi', 'CF1', 'convert pós-end recusado',
          convEnd.brief);
    }
  }

  // Race dois hitch mesma unidade (2 pending ∥ 2 accept).
  final liveH = await c.createLive(title: '$prefix race hitch');
  final skuH =
      await c.createProduct(title: '$prefix race hitch sku', qty: 1, live: true);
  final liH1 = (liveH == null || skuH == null)
      ? null
      : await c.createLiveItem(
          liveId: liveH,
          title: '$prefix hitch1',
          ref: 'RTCF-RH1',
          kind: 'live_only',
          checkoutProductId: skuH,
          quantity: 1,
        );
  final liH2 = (liveH == null || skuH == null)
      ? null
      : await c.createLiveItem(
          liveId: liveH,
          title: '$prefix hitch2',
          ref: 'RTCF-RH2',
          kind: 'live_only',
          checkoutProductId: skuH,
          quantity: 1,
        );
  if (liveH != null && liH1 != null && liH2 != null) {
    final rh1 = await c.insertReservation(
      liveId: liveH,
      liveItemId: liH1,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    final rh2 = await c.insertReservation(
      liveId: liveH,
      liveItemId: liH2,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    );
    if (rh1 != null && rh2 != null) {
      final par = await Future.wait([
        c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$rh1',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        ),
        c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$rh2',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        ),
      ]);
      final g1 = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$rh1&select=id,status',
        service: true,
      );
      final g2 = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$rh2&select=id,status',
        service: true,
      );
      final nAcc = [
        g1.map?['status'],
        g2.map?['status'],
      ].where((s) => s == 'accepted').length;
      if (nAcc >= 2) {
        c.hold(
          id: 'p3.race.hitch.dual_accept',
          lens: 'CF4',
          severity: 'P1',
          title: 'Race 2 hitch mesma unidade: 2 accepted',
          actor: 'seller JWT paralelo',
          pre: 'mesmo checkout_product_id qty=1',
          repro: 'Future.wait 2× PATCH accepted',
          expected: 'só 1 accepted',
          obtained: {
            'nAcc': nAcc,
            'a': g1.map,
            'b': g2.map,
            'hits': [par[0].brief, par[1].brief],
          },
        );
      } else {
        c.block('p3.race.hitch.dual_accept', 'CF4', 'race hitch só 1 accepted', {
          'nAcc': nAcc,
          'a': g1.map,
          'b': g2.map,
        });
      }
    }
  }

  // --- Mux / stream ---
  const fakePlayback = 'CFPLAYBACK1228fake0001';
  const fakeVod = 'CFVOD1228fake0001xxxx';
  const fakeAsset = 'CFASSET1228fake0001xxx';
  const fakeKey = 'CFSTREAMKEY1228secret';
  const fakeRoom = 'CFROOM1228livekit';
  const fakePlaybackCol = 'CFPLAINPB1228fake0001';

  final liveUnpub = await c.createLive(
    seller: c.seller2Id,
    title: '$prefix mux unpub',
    extra: {
      'mux_playback_id': fakePlayback,
      'mux_vod_playback_id': fakeVod,
      'mux_asset_id': fakeAsset,
      'playback_id': fakePlaybackCol,
      'livekit_room_name': fakeRoom,
    },
  );
  final liveSched = await c.createLive(
    seller: c.seller2Id,
    title: '$prefix mux sched',
    status: 'scheduled',
    active: false,
    extra: {
      'mux_playback_id': 'CFSCHED1228fake0001',
      'playback_id': 'CFSCHEDPB1228fake0001',
    },
  );
  final liveEndedU = await c.createLive(
    seller: c.seller2Id,
    title: '$prefix mux ended unpub',
    status: 'ended',
    active: false,
    extra: {
      'mux_playback_id': 'CFENDED1228fake0001',
      'mux_vod_playback_id': fakeVod,
      'playback_id': 'CFENDEDPB1228fake0001',
    },
  );
  final livePub = await c.createLive(
    title: '$prefix mux pub seller1',
    extra: {
      'mux_playback_id': 'CFPUB1228fake0001xxxx',
      'playback_id': 'CFPUBPB1228fake0001xxx',
    },
  );

  // Tentar plant stream_key via service (coluna pode ser blocked no insert).
  if (liveUnpub != null) {
    final sk = await c.rest(
      'PATCH',
      'lives?id=eq.$liveUnpub',
      service: true,
      body: {'mux_stream_key': fakeKey, 'stream_key': fakeKey},
    );
    c.note('p3.mux.plant.key', 'plant stream_key', sk.brief, lens: 'CF7');
  }

  Future<void> probeCol({
    required String id,
    required String? liveId,
    required String? jwt,
    required String actor,
    required String col,
    bool expectDeny = true,
    bool residualBxcc = false,
  }) async {
    if (liveId == null) return;
    final h = await c.rest(
      'GET',
      'lives?id=eq.$liveId&select=id,$col',
      jwt: jwt,
    );
    final val = h.map?[col]?.toString();
    final leaked = h.ok && val != null && val.isNotEmpty;
    if (leaked) {
      if (residualBxcc) {
        c.hold(
          id: id,
          lens: 'CF7',
          severity: 'P2',
          title: 'REGRESSÃO BXCC: $actor lê $col',
          actor: actor,
          pre: 'revoke mux_* authenticated',
          repro: 'GET lives?select=$col',
          expected: '403 coluna / vazio',
          obtained: h.brief,
          evidence: {'col': col, 'val': val, 'live': liveId},
        );
      } else if (expectDeny) {
        c.hold(
          id: id,
          lens: 'CF7',
          severity: col.contains('key') ? 'P1' : 'P2',
          title: '$actor lê $col de live alheia',
          actor: actor,
          pre: 'BXCC revoke mux_playback_id; outras cols?',
          repro: 'GET lives?id=eq.$liveId&select=$col',
          expected: 'vazio / 403 coluna',
          obtained: h.brief,
          evidence: {'col': col, 'val': val, 'live': liveId},
        );
      } else {
        c.note(id, '$actor lê $col (esperado)', h.brief, lens: 'CF7');
      }
    } else {
      c.block(id, 'CF7', '$actor não lê $col', h.brief);
    }
  }

  // Exacto BXCC mux_playback_id — residual se vazar.
  await probeCol(
    id: 'p3.mux.buyer.mux_playback.unpub',
    liveId: liveUnpub,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    col: 'mux_playback_id',
    residualBxcc: true,
  );
  await probeCol(
    id: 'p3.mux.buyer.mux_playback.sched',
    liveId: liveSched,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    col: 'mux_playback_id',
    residualBxcc: true,
  );
  await probeCol(
    id: 'p3.mux.anon.mux_playback.unpub',
    liveId: liveUnpub,
    jwt: null,
    actor: 'anon',
    col: 'mux_playback_id',
    residualBxcc: true,
  );

  // Colunas irmãs (não exacto BXCC).
  for (final col in [
    'playback_id',
    'livekit_room_name',
    'mux_stream_key',
    'stream_key',
    'mux_live_id',
    'mux_vod_playback_id',
    'mux_asset_id',
  ]) {
    await probeCol(
      id: 'p3.mux.buyer.$col.unpub',
      liveId: liveUnpub,
      jwt: c.buyerJwt,
      actor: 'buyer JWT',
      col: col,
    );
  }

  // Owner pode ler playback (HOLD dono).
  await probeCol(
    id: 'p3.mux.owner.playback.unpub',
    liveId: liveUnpub,
    jwt: c.seller2Jwt,
    actor: 'owner seller2',
    col: 'mux_playback_id',
    expectDeny: false,
  );

  // Hub vs REST.
  Future<void> hubProbe(String? liveId, String tag) async {
    if (liveId == null) return;
    final hub = await c.rest(
      'GET',
      'hub_lives_public?id=eq.$liveId&select=id,mux_playback_id,mux_vod_playback_id,status',
      jwt: c.buyerJwt,
    );
    final disc = await c.rest(
      'GET',
      'hub_lives_discovery_public?id=eq.$liveId&select=id,mux_playback_id,status',
      jwt: c.buyerJwt,
    );
    c.note('p3.hub.$tag', 'Hub/discovery', {
      'hub': hub.brief,
      'disc': disc.brief,
    }, lens: 'CF7');
    final hubPb = hub.map?['mux_playback_id']?.toString();
    if (tag.contains('unpub') &&
        hub.ok &&
        hubPb != null &&
        hubPb.isNotEmpty) {
      c.hold(
        id: 'p3.hub.unpub.playback',
        lens: 'CF7',
        severity: 'P2',
        title: 'hub_lives_public expõe playback unpublished',
        actor: 'buyer JWT',
        pre: 'seller2 hub_published=false',
        repro: 'GET hub_lives_public',
        expected: '[] / sem playback',
        obtained: hub.brief,
      );
    }
  }

  await hubProbe(liveUnpub, 'unpub');
  await hubProbe(liveSched, 'sched');
  await hubProbe(liveEndedU, 'ended');
  await hubProbe(livePub, 'pub');

  // resolve-mux-playback: buyer/anon unpublished; ID swap VOD vs live.
  Future<void> resolveMux({
    required String id,
    required String? liveId,
    String? jwt,
    required String actor,
    bool expectDeny = true,
  }) async {
    if (liveId == null) return;
    final h = await c.edge(
      'resolve-mux-playback',
      {'live_id': liveId},
      jwt: jwt,
    );
    final pb = h.map?['playback_id']?.toString() ?? '';
    final url = h.map?['playback_url']?.toString() ?? '';
    final leaked = h.ok && (pb.isNotEmpty || url.contains('mux.com'));
    if (leaked && expectDeny) {
      c.hold(
        id: id,
        lens: 'CF7',
        severity: 'P1',
        title: 'resolve-mux-playback entrega HLS a $actor',
        actor: actor,
        pre: 'live unpublished / não dono',
        repro: 'POST resolve-mux-playback live_id',
        expected: '404 live_not_public',
        obtained: h.brief,
        evidence: {'playback_id': pb, 'url': url},
      );
    } else if (!leaked) {
      c.block(id, 'CF7', 'resolve recusado/vazio ($actor)', h.brief);
    } else {
      c.note(id, 'resolve OK esperado', h.brief, lens: 'CF7');
    }
  }

  await resolveMux(
    id: 'p3.resolve.buyer.unpub',
    liveId: liveUnpub,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
  );
  await resolveMux(
    id: 'p3.resolve.anon.unpub',
    liveId: liveUnpub,
    jwt: null,
    actor: 'anon',
  );
  await resolveMux(
    id: 'p3.resolve.buyer.ended_unpub',
    liveId: liveEndedU,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
  );
  await resolveMux(
    id: 'p3.resolve.owner.unpub',
    liveId: liveUnpub,
    jwt: c.seller2Jwt,
    actor: 'owner',
    expectDeny: false,
  );
  // ID swap: pedir resolve da live ended com JWT, e da live pub.
  await resolveMux(
    id: 'p3.resolve.buyer.pub',
    liveId: livePub,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    expectDeny: false,
  );

  // complete-mux / livekit alheio.
  for (final fn in ['complete-mux-live', 'livekit-mux-publish']) {
    final h = await c.edge(fn, {'live_id': liveUnpub}, jwt: c.buyerJwt);
    if (h.ok) {
      c.hold(
        id: 'p3.edge.$fn.buyer',
        lens: 'CF7',
        severity: 'P1',
        title: '$fn alheio aceitou buyer JWT',
        actor: 'buyer JWT',
        pre: 'não dono',
        repro: 'POST $fn',
        expected: '403',
        obtained: h.brief,
      );
    } else {
      c.block('p3.edge.$fn.buyer', 'CF7', '$fn alheio recusado', h.brief);
    }
  }

  // SELECT * lives — ver se playback_id / room vazam no wildcard.
  final wild = await c.rest(
    'GET',
    'lives?id=eq.$liveUnpub&select=*',
    jwt: c.buyerJwt,
  );
  final wildMap = wild.map ?? {};
  final leakedKeys = wildMap.keys
      .where((k) {
        final v = '${wildMap[k]}';
        return v.contains('CFPLAY') ||
            v.contains('CFVOD') ||
            v.contains('CFSTREAM') ||
            v.contains('CFROOM') ||
            v.contains('CFPLAIN') ||
            k.toString().contains('stream_key') ||
            k.toString().contains('mux_');
      })
      .map((k) => '$k=${wildMap[k]}')
      .toList();
  c.note('p3.mux.wildcard.keys', 'SELECT * keys', wildMap.keys.toList(),
      lens: 'CF7');
  if (leakedKeys.isNotEmpty) {
    c.hold(
      id: 'p3.mux.wildcard.leak',
      lens: 'CF7',
      severity: leakedKeys.any((s) => s.contains('key')) ? 'P1' : 'P2',
      title: 'SELECT * lives vaza playback/stream em live unpublished',
      actor: 'buyer JWT',
      pre: 'column revoke mux_*; wildcard ainda lista irmãs?',
      repro: 'GET lives?select=*',
      expected: 'sem mux/stream/playback alheio',
      obtained: leakedKeys,
      evidence: {'keys': wildMap.keys.toList(), 'hits': leakedKeys},
    );
  } else {
    c.block('p3.mux.wildcard.leak', 'CF7', 'wildcard sem mux/stream',
        wildMap.keys.toList());
  }

  // --- Caixa: FOMO + convert mentiroso ---
  final liveC = await c.createLive(title: '$prefix caixa');
  final skuC =
      await c.createProduct(title: '$prefix caixa sku', qty: 1, live: true);
  final liC = (liveC == null || skuC == null)
      ? null
      : await c.createLiveItem(
          liveId: liveC,
          title: '$prefix caixa item',
          ref: 'RTCF-CX',
          kind: 'live_only',
          checkoutProductId: skuC,
          quantity: 1,
        );
  if (liveC != null && liC != null) {
    final fomo = await c.rpc(
      'batata_live_system_message',
      {'p_live_id': liveC, 'p_body': 'já tem dono'},
      jwt: c.sellerJwt,
    );
    final rc = await c.insertReservation(
      liveId: liveC,
      liveItemId: liC,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    if (rc != null) {
      await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$rc',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
      final fakeOrder = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': skuC,
        'live_id': liveC,
        'live_item_id': liC,
        'quantity': 1,
        'price_total': 9,
        'status': 'pendente',
        'payment_method': 'MB WAY',
        'shipping_method': 'entrega em mão',
      });
      if (fakeOrder.firstId != null) c.createdOrderIds.add(fakeOrder.firstId!);
      HttpHit? rec;
      if (fakeOrder.ok && fakeOrder.firstId != null) {
        rec = await c.rpc(
          'batata_live_reconcile_stripe_order',
          {
            'p_order_id': fakeOrder.firstId,
            'p_reservation_request_id': rc,
          },
          jwt: c.sellerJwt,
        );
      }
      final after = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$rc&select=id,status',
        service: true,
      );
      final orderRow = fakeOrder.firstId == null
          ? null
          : (await c.rest(
              'GET',
              'orders?id=eq.${fakeOrder.firstId}&select=id,status,amount_paid_cents,stripe_payment_intent_id',
              service: true,
            ))
              .map;
      final stC = await c.stock(liC);
      c.note('p3.caixa.chain', 'FOMO→accept→order pendente→reconcile', {
        'fomo': fomo.brief,
        'order': fakeOrder.brief,
        'rec': rec?.brief,
        'res': after.map,
        'order_row': orderRow,
        'stock': stC,
      }, lens: 'CF8');
      final converted = after.map?['status'] == 'converted';
      final paid = orderRow != null &&
          ('${orderRow['status']}'.toLowerCase().contains('pago') ||
              (orderRow['amount_paid_cents'] is num &&
                  (orderRow['amount_paid_cents'] as num) > 0));
      if (converted && (paid || rec?.map?['ok'] == true)) {
        c.hold(
          id: 'p3.caixa.fomo_to_pago',
          lens: 'CF8',
          severity: 'P0',
          title: 'Cadeia FOMO/convert mentiroso chegou a converted/pago',
          actor: 'seller+buyer JWT',
          pre: 'sem captura Stripe TEST',
          repro: 'system_message + accept + order pendente + reconcile',
          expected: 'reserva≠converted; order≠pago',
          obtained: {
            'res': after.map,
            'order': orderRow,
            'rec': rec?.brief,
            'stock': stC,
          },
        );
      } else {
        c.block('p3.caixa.fomo_to_pago', 'CF8',
            'cadeia não chegou a pago/converted', {
          'converted': converted,
          'paid': paid,
          'rec': rec?.brief,
          'order': orderRow,
        });
      }
    }
  }

  await dumpJson('${outDir()}/pass3.json', {
    'auditor': 'REDTEAM_BLIND_CF_LIVE_POS_BXCC_v1',
    'prefix': prefix,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'pass3 done findings=${c.findings.length} blocked=${c.blocked.length}');
}
