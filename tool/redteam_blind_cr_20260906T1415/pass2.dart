/// REDTEAM_BLIND_CR_LIVE_POS_ALLOW_v1 — pass2 hitch/convert/race/mux residual.
/// Staging only. No fixes.
import 'dart:io';

import '_rtcr.dart';

Future<void> main() async {
  final c = Rtcr.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2(hubPublished: false);

  final liveA = await c.createLive(title: '$prefix p2A');
  final liveB = await c.createLive(title: '$prefix p2B');
  final skuA =
      await c.createProduct(title: '$prefix p2 skuA', qty: 1, live: true);
  final skuB =
      await c.createProduct(title: '$prefix p2 skuB', qty: 1, live: true);
  if (liveA == null || liveB == null || skuA == null || skuB == null) {
    stderr.writeln('fixture fail');
    await c.endAllCreatedLives();
    exit(4);
  }
  final itemA = await c.createLiveItem(
    liveId: liveA,
    title: '$prefix p2 itemA',
    ref: 'RTCR-P2A',
    kind: 'live_only',
    checkoutProductId: skuA,
    quantity: 1,
  );
  final itemB = await c.createLiveItem(
    liveId: liveB,
    title: '$prefix p2 itemB',
    ref: 'RTCR-P2B',
    kind: 'live_only',
    checkoutProductId: skuB,
    quantity: 1,
  );
  if (itemA == null || itemB == null) {
    stderr.writeln('items fail');
    await c.endAllCreatedLives();
    exit(4);
  }

  // --- C2 convert sem PI ---
  final ridA = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA,
    jwt: c.buyerJwt,
    buyer: c.buyerId,
  );
  if (ridA == null) {
    stderr.writeln('pending A fail');
    await c.endAllCreatedLives();
    exit(4);
  }
  await c.rest(
    'PATCH',
    'live_reservation_requests?id=eq.$ridA',
    jwt: c.sellerJwt,
    body: {'status': 'accepted'},
  );
  final convRpc = await c.rpc(
    'batata_live_reservation_stripe_convert',
    {'p_request_id': ridA},
    jwt: c.sellerJwt,
  );
  final afterConv = await c.rest(
    'GET',
    'live_reservation_requests?id=eq.$ridA&select=id,status',
    service: true,
  );
  final st = afterConv.map?['status']?.toString();
  if (convRpc.map?['ok'] == true && st == 'converted') {
    c.hold(
      id: 'C2.convert.nopi',
      lens: 'CR5',
      severity: 'P0',
      title: 'stripe_convert sem PI deixou status=converted',
      actor: 'seller JWT',
      pre: 'accepted, sem order paga',
      repro: 'rpc batata_live_reservation_stripe_convert',
      expected: 'recusa; status≠converted',
      obtained: {'rpc': convRpc.brief, 'row': afterConv.map},
    );
    c.probe(
      id: 'C2.convert.nopi',
      lens: 'CR5',
      payload: 'stripe_convert accepted sem PI',
      http: convRpc.brief,
      verdict: 'FAIL',
    );
  } else {
    c.block('C2.convert.nopi', 'CR5', 'convert sem PI recusado (HOLD)',
        {'rpc': convRpc.brief, 'status': st});
    c.probe(
      id: 'C2.convert.nopi',
      lens: 'CR5',
      payload: 'stripe_convert accepted sem PI',
      http: convRpc.brief,
      verdict: 'HOLD',
      extra: {'status': st},
    );
  }

  // --- C2b convert PI alheio ---
  final ridB = await c.insertReservation(
    liveId: liveB,
    liveItemId: itemB,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  if (ridB != null) {
    await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$ridB',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
  }
  final planted = await c.rest('POST', 'orders', service: true, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': skuA,
    'live_id': liveA,
    'live_item_id': itemA,
    'quantity': 1,
    'price_total': 9,
    'status': 'pago',
    'payment_method': 'MB WAY',
    'shipping_method': 'entrega em mão',
    'stripe_payment_intent_id': 'pi_rtcr_stolen_${stamp}_A',
    'amount_paid_cents': 900,
  });
  if (planted.firstId != null) c.createdOrderIds.add(planted.firstId!);
  if (planted.ok && planted.firstId != null && ridB != null) {
    final recCross = await c.rpc(
      'batata_live_reconcile_stripe_order',
      {
        'p_order_id': planted.firstId,
        'p_reservation_request_id': ridB,
      },
      jwt: c.sellerJwt,
    );
    final afterCross = await c.rest(
      'GET',
      'live_reservation_requests?id=eq.$ridB&select=id,status,buyer_id,live_id',
      service: true,
    );
    if (recCross.map?['ok'] == true &&
        afterCross.map?['status'] == 'converted') {
      c.hold(
        id: 'C2b.convert.pi_alheio',
        lens: 'CR5',
        severity: 'P0',
        title: 'reconcile order live A → reserva live B converted',
        actor: 'seller JWT',
        pre: 'PI/order de outra live e outro item',
        repro: 'rpc batata_live_reconcile_stripe_order orderA + resB',
        expected: 'mismatch recusa',
        obtained: {'rpc': recCross.brief, 'res': afterCross.map},
      );
      c.probe(
        id: 'C2b.convert.pi_alheio',
        lens: 'CR5',
        payload: 'reconcile PI liveA → res liveB',
        http: recCross.brief,
        verdict: 'FAIL',
      );
    } else {
      c.block('C2b.convert.pi_alheio', 'CR5',
          'reconcile PI alheio recusado (HOLD)', recCross.brief);
      c.probe(
        id: 'C2b.convert.pi_alheio',
        lens: 'CR5',
        payload: 'reconcile PI liveA → res liveB',
        http: recCross.brief,
        verdict: 'HOLD',
      );
    }
  } else {
    c.probe(
      id: 'C2b.convert.pi_alheio',
      lens: 'CR5',
      payload: 'reconcile PI liveA → res liveB',
      http: planted.brief,
      verdict: 'HOLD',
      extra: {'reason': 'plant/ridB fail'},
    );
  }

  // --- C1 hitch qty>stock ---
  final liveH = await c.createLive(title: '$prefix p2 hitch');
  final skuH =
      await c.createProduct(title: '$prefix hitch sku', qty: 1, live: true);
  if (liveH != null && skuH != null) {
    final li1 = await c.createLiveItem(
      liveId: liveH,
      title: '$prefix hitch A',
      ref: 'RTCR-HA',
      kind: 'marketplace_product',
      productId: skuH,
    );
    final li2 = await c.createLiveItem(
      liveId: liveH,
      title: '$prefix hitch B',
      ref: 'RTCR-HB',
      kind: 'live_only',
      checkoutProductId: skuH,
      quantity: 1,
    );
    if (li1 != null) {
      await c.rest(
        'PATCH',
        'live_items?id=eq.$li1',
        service: true,
        body: {'checkout_product_id': null, 'logical_item_id': null},
        prefer: 'return=minimal',
      );
    }
    HttpHit? a2;
    Map<String, dynamic>? row1;
    Map<String, dynamic>? row2;
    if (li1 != null && li2 != null) {
      final r1 = await c.insertReservation(
        liveId: liveH,
        liveItemId: li1,
        jwt: c.buyerJwt,
        buyer: c.buyerId,
      );
      if (r1 != null) {
        await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$r1',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
      }
      final r2 = await c.insertReservation(
        liveId: liveH,
        liveItemId: li2,
        jwt: c.buyer2Jwt,
        buyer: c.buyer2Id,
      );
      if (r2 != null) {
        a2 = await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$r2',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
      }
      row1 = r1 == null
          ? null
          : (await c.rest(
              'GET',
              'live_reservation_requests?id=eq.$r1&select=id,status,requested_qty',
              service: true,
            ))
              .map;
      row2 = r2 == null
          ? null
          : (await c.rest(
              'GET',
              'live_reservation_requests?id=eq.$r2&select=id,status,requested_qty',
              service: true,
            ))
              .map;
      if (row1?['status'] == 'accepted' && row2?['status'] == 'accepted') {
        c.hold(
          id: 'C1.hitch.qty_stock',
          lens: 'CR4',
          severity: 'P1',
          title: 'Dois accepts no mesmo SKU hitch (qty=1)',
          actor: 'seller JWT',
          pre: 'qty produto=1; marketplace+live_only',
          repro: 'accept LI1 depois LI2',
          expected: '2º qty_exceeds_stock',
          obtained: {'r1': row1, 'r2': row2, 'a2': a2?.brief},
        );
        c.probe(
          id: 'C1.hitch.qty_stock',
          lens: 'CR4',
          payload: 'hitch marketplace+live_only qty=1 two accepts',
          http: a2?.brief ?? 'n/a',
          verdict: 'FAIL',
          extra: {'r1': row1, 'r2': row2},
        );
      } else {
        c.block('C1.hitch.qty_stock', 'CR4',
            '2º accept recusado (HOLD hitch)', {
          'r1': row1,
          'r2': row2,
          'a2': a2?.brief,
        });
        c.probe(
          id: 'C1.hitch.qty_stock',
          lens: 'CR4',
          payload: 'hitch marketplace+live_only qty=1 two accepts',
          http: a2?.brief ?? 'n/a',
          verdict: 'HOLD',
          extra: {'r1': row1, 'r2': row2},
        );
      }
    }
  }

  // --- C3 end_live ∥ accept ---
  final liveR = await c.createLive(title: '$prefix race end');
  final skuR =
      await c.createProduct(title: '$prefix race sku', qty: 1, live: true);
  final liR = (liveR == null || skuR == null)
      ? null
      : await c.createLiveItem(
          liveId: liveR,
          title: '$prefix race item',
          ref: 'RTCR-RC',
          kind: 'live_only',
          checkoutProductId: skuR,
          quantity: 1,
        );
  if (liveR != null && liR != null) {
    final rRace = await c.insertReservation(
      liveId: liveR,
      liveItemId: liR,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    if (rRace != null) {
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
        'live_reservation_requests?id=eq.$rRace&select=id,status',
        service: true,
      );
      final liveAfter = await c.rest(
        'GET',
        'lives?id=eq.$liveR&select=id,status,is_active',
        service: true,
      );
      final ended = liveAfter.map?['status']?.toString() == 'ended' &&
          liveAfter.map?['is_active'] != true;
      final accepted = afterRace.map?['status']?.toString() == 'accepted';
      c.probe(
        id: 'C3.end_parallel_accept',
        lens: 'CR6',
        payload: 'end_live ∥ PATCH accepted',
        http: raced.map((h) => h.brief).join(' | '),
        verdict: 'HOLD',
        extra: {
          'ended': ended,
          'accepted': accepted,
          'res': afterRace.map,
          'live': liveAfter.map,
        },
      );
      if (ended && accepted) {
        c.note(
          'C3.race.accept.won',
          'accept ganhou a race contra end (anotar; não P0 sem caixa)',
          afterRace.map,
          lens: 'CR6',
        );
      } else {
        c.block('C3.end_parallel_accept', 'CR6',
            'end ganhou ou accept não ficou accepted', {
          'res': afterRace.map,
          'live': liveAfter.map,
        });
      }

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
      if (!accepted && lateRow.map?['status'] == 'accepted') {
        c.hold(
          id: 'C3.accept.after.end',
          lens: 'CR6',
          severity: 'P1',
          title: 'Accept depois de live ended',
          actor: 'seller JWT',
          pre: 'status=ended is_active=false',
          repro: 'PATCH accepted após end',
          expected: 'live_ended',
          obtained: {'patch': accLate.brief, 'row': lateRow.map},
        );
        c.probe(
          id: 'C3.accept.after.end',
          lens: 'CR6',
          payload: 'PATCH accepted após live ended',
          http: accLate.brief,
          verdict: 'FAIL',
        );
      } else {
        c.block('C3.accept.after.end', 'CR6',
            'accept pós-end recusado ou já decided', accLate.brief);
        c.probe(
          id: 'C3.accept.after.end',
          lens: 'CR6',
          payload: 'PATCH accepted após live ended',
          http: accLate.brief,
          verdict: 'HOLD',
        );
      }
    }
  }

  // --- C4 playback/realtime residual (1) ---
  const fakePlayback = 'RTCRPLAY1415fake0001';
  const fakePlaybackCol = 'RTCRPB1415plain0001';
  const fakeRoom = 'RTCRROOM1415livekit';
  final liveUnpub = await c.createLive(
    seller: c.seller2Id,
    title: '$prefix mux unpub',
    extra: {
      'mux_playback_id': fakePlayback,
      'playback_id': fakePlaybackCol,
      'livekit_room_name': fakeRoom,
    },
  );
  if (liveUnpub != null) {
    final pb = await c.rest(
      'GET',
      'lives?id=eq.$liveUnpub&select=id,playback_id,mux_playback_id,livekit_room_name',
      jwt: c.buyerJwt,
    );
    final leaked = pb.ok &&
        ((pb.map?['playback_id']?.toString().isNotEmpty ?? false) ||
            (pb.map?['mux_playback_id']?.toString().isNotEmpty ?? false) ||
            (pb.map?['livekit_room_name']?.toString().isNotEmpty ?? false));
    if (leaked) {
      c.hold(
        id: 'C4.buyer.playback_cols',
        lens: 'CR7',
        severity: 'P2',
        title: 'Buyer lê playback/mux/livekit unpublished',
        actor: 'buyer JWT',
        pre: 'CDCI revoke; unpublished seller2',
        repro: 'GET lives select playback_id,mux_playback_id,livekit_room_name',
        expected: '403 / vazio',
        obtained: pb.brief,
      );
      c.probe(
        id: 'C4.buyer.playback_cols',
        lens: 'CR7',
        payload: 'GET lives playback/mux/livekit unpublished',
        http: pb.brief,
        verdict: 'FAIL',
      );
    } else {
      c.block('C4.buyer.playback_cols', 'CR7',
          'buyer não lê playback unpublished (HOLD)', pb.brief);
      c.probe(
        id: 'C4.buyer.playback_cols',
        lens: 'CR7',
        payload: 'GET lives playback/mux/livekit unpublished',
        http: pb.brief,
        verdict: 'HOLD',
      );
    }

    final rt = await c.probeRealtimeLivesPlayback(
      liveId: liveUnpub,
      jwt: c.buyerJwt!,
    );
    c.note('C4.realtime.raw', 'realtime frames', rt, lens: 'CR7');
    final framesText = '${rt['frames']}'.toLowerCase();
    final payloadLeak = framesText.contains('rtcrpb') ||
        framesText.contains('rtcrmux') ||
        framesText.contains('rtcrroom') ||
        framesText.contains(fakePlaybackCol.toLowerCase()) ||
        framesText.contains(fakePlayback.toLowerCase());
    if (payloadLeak) {
      c.hold(
        id: 'C4.realtime.playback',
        lens: 'CR7',
        severity: 'P2',
        title: 'Realtime postgres_changes vaza playback/mux/livekit',
        actor: 'buyer JWT websocket',
        pre: 'REST SELECT playback_id revogado',
        repro: 'ws realtime:public:lives + PATCH playback',
        expected: 'payload sem playback',
        obtained: {
          'hits': rt['hits'],
          'n_frames': rt['n_frames'],
          'joinAck': rt['joinAck'],
        },
      );
      c.probe(
        id: 'C4.realtime.playback',
        lens: 'CR7',
        payload: 'ws postgres_changes lives unpublished PATCH playback',
        http: 'ws frames=${rt['n_frames']} hits=${rt['hits']}',
        verdict: 'FAIL',
        extra: rt,
      );
    } else {
      c.block('C4.realtime.playback', 'CR7',
          'realtime sem playback no payload (HOLD)', {
        'ok': rt['ok'],
        'error': rt['error'],
        'n_frames': rt['n_frames'],
        'joinAck': rt['joinAck'],
      });
      c.probe(
        id: 'C4.realtime.playback',
        lens: 'CR7',
        payload: 'ws postgres_changes lives unpublished PATCH playback',
        http:
            'ws frames=${rt['n_frames']} join=${rt['joinAck']} err=${rt['error']}',
        verdict: 'HOLD',
      );
    }
  }

  await dumpJson('${outDir()}/pass2.json', {
    'auditor': 'REDTEAM_BLIND_CR_LIVE_POS_ALLOW_v1',
    'prefix': prefix,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'probes': c.probes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  await c.endAllCreatedLives();
  stdout.writeln(
      'pass2 done findings=${c.findings.length} blocked=${c.blocked.length} '
      'probes=${c.probes.length}');
}
