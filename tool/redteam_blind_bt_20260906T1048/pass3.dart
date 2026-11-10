/// REDTEAM_BLIND_BT_LIVE_POS_BLBQ_v1 — pass3 race / Mux / caixa.
/// Staging only. No fixes.
import 'dart:io';

import '_rtbt.dart';

Future<void> main() async {
  final c = Rtbt.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  // --- Race end ∥ accept ---
  final liveR = await c.createLive(title: '$prefix race');
  final skuR =
      await c.createProduct(title: '$prefix race sku', qty: 1, live: true);
  final liR = (liveR == null || skuR == null)
      ? null
      : await c.createLiveItem(
          liveId: liveR,
          title: '$prefix race item',
          ref: 'RTBT-RC',
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
  }, lens: 'BT6');

  final ended = liveAfter.map?['status']?.toString() == 'ended' &&
      liveAfter.map?['is_active'] != true;
  final accepted = afterRace.map?['status']?.toString() == 'accepted';

  // Segundo pending DEPOIS de ended.
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
  }
  if (ended && rAfterEnd != null) {
    c.hold(
      id: 'p3.race.pending.after.end',
      lens: 'BT6',
      severity: 'P1',
      title: 'Pending criado depois da live ended',
      actor: 'buyer2 JWT',
      pre: 'live status=ended is_active=false',
      repro: 'POST live_reservation_requests após end',
      expected: 'live_ended',
      obtained: {
        'res_id': rAfterEnd,
        'accept': accAfterEnd?.brief,
        'row': rowAfterEnd,
      },
    );
  } else if (ended && rAfterEnd == null) {
    c.block('p3.race.pending.after.end', 'BT6', 'pending pós-end recusado',
        c.notes.where((n) => n['id'] == 'res.fail').toList());
  }

  if (ended && accepted) {
    c.note(
      'p3.race.accept.won',
      'accept ganhou a race contra end (reserva ficou accepted em live ended)',
      afterRace.map,
      lens: 'BT6',
    );
  }

  // Accept depois de end na reserva que já existia (se a race deixou pending).
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
        lens: 'BT6',
        severity: 'P1',
        title: 'Accept depois da live já ended',
        actor: 'seller JWT',
        pre: 'live ended; reserva ainda pending',
        repro: 'PATCH accepted após end',
        expected: 'live_ended',
        obtained: {'patch': accLate.brief, 'row': lateRow.map},
      );
    } else {
      c.block('p3.accept.after.end', 'BT6', 'accept pós-end recusado',
          accLate.brief);
    }
  }

  // Race dois accepts qty=1.
  final liveD = await c.createLive(title: '$prefix dual');
  final skuD =
      await c.createProduct(title: '$prefix dual sku', qty: 1, live: true);
  final liD = (liveD == null || skuD == null)
      ? null
      : await c.createLiveItem(
          liveId: liveD,
          title: '$prefix dual item',
          ref: 'RTBT-DU',
          kind: 'live_only',
          checkoutProductId: skuD,
          quantity: 1,
        );
  if (liveD != null && liD != null) {
    final d1 = await c.insertReservation(
      liveId: liveD,
      liveItemId: liD,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    final d2 = await c.insertReservation(
      liveId: liveD,
      liveItemId: liD,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    );
    if (d1 != null && d2 != null) {
      final dual = await Future.wait([
        for (var i = 0; i < 4; i++)
          c.rest(
            'PATCH',
            'live_reservation_requests?id=eq.$d1',
            jwt: c.sellerJwt,
            body: {'status': 'accepted'},
          ),
        for (var i = 0; i < 4; i++)
          c.rest(
            'PATCH',
            'live_reservation_requests?id=eq.$d2',
            jwt: c.sellerJwt,
            body: {'status': 'accepted'},
          ),
      ]);
      final d1row = (await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$d1&select=id,status,requested_qty',
        service: true,
      ))
          .map;
      final d2row = (await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$d2&select=id,status,requested_qty',
        service: true,
      ))
          .map;
      final both = d1row?['status'] == 'accepted' &&
          d2row?['status'] == 'accepted';
      if (both) {
        c.hold(
          id: 'p3.race.two.accepts.qty1',
          lens: 'BT6',
          severity: 'P1',
          title: 'Dois accepted em paralelo em item qty=1',
          actor: 'seller JWT × N',
          pre: 'duas pending; qty=1',
          repro: '8 PATCH accepted em paralelo',
          expected: 'só 1 accepted',
          obtained: {
            'd1': d1row,
            'd2': d2row,
            'hits': dual.map((h) => h.brief).toList(),
          },
        );
      } else {
        c.block('p3.race.two.accepts.qty1', 'BT6', 'só um accepted', {
          'd1': d1row,
          'd2': d2row,
        });
      }
    }
  }

  // --- Mux owner cruzado ---
  const fakePlayback = 'RTBTfakePlaybk11111111111111111111';
  const fakeStream = 'RTBTfakeStreamKeyDoNotUseInProd';
  const fakeMuxLive = 'RTBTfakeMuxLiveIdxxxxxxxxxxxxxxxx';
  const fakeVod = 'RTBTfakeVodPlaybackIdxxxxxxxxxxxxx';
  final liveMux = await c.createLive(
    title: '$prefix mux owner',
    extra: {
      'mux_playback_id': fakePlayback,
      'mux_stream_key': fakeStream,
      'mux_live_id': fakeMuxLive,
      'mux_vod_playback_id': fakeVod,
      'mux_asset_id': 'RTBTfakeAsset',
      'stream_key': fakeStream,
    },
  );
  if (liveMux != null) {
    final cols =
        'id,status,mux_playback_id,mux_vod_playback_id,mux_asset_id,mux_stream_key,mux_live_id,stream_key,playback_id';
    final anonMux = await c.rest(
      'GET',
      'lives?id=eq.$liveMux&select=$cols',
    );
    final buyerMux = await c.rest(
      'GET',
      'lives?id=eq.$liveMux&select=$cols',
      jwt: c.buyerJwt,
    );
    final s2Mux = await c.rest(
      'GET',
      'lives?id=eq.$liveMux&select=$cols',
      jwt: c.seller2Jwt,
    );
    final ownerMux = await c.rest(
      'GET',
      'lives?id=eq.$liveMux&select=$cols',
      jwt: c.sellerJwt,
    );
    c.note('p3.mux.read', 'leituras Mux', {
      'anon': anonMux.brief,
      'buyer': buyerMux.brief,
      'seller2': s2Mux.brief,
      'owner': ownerMux.brief,
    }, lens: 'BT7');

    bool leakedKey(HttpHit h) {
      final m = h.map;
      if (m == null) return false;
      final sk = '${m['mux_stream_key'] ?? ''}${m['stream_key'] ?? ''}';
      return sk.contains('RTBTfakeStream');
    }

    bool leakedVod(HttpHit h) {
      final m = h.map;
      if (m == null) return false;
      return '${m['mux_vod_playback_id'] ?? ''}'.contains('RTBTfakeVod');
    }

    if (leakedKey(anonMux) || leakedVod(anonMux) && anonMux.ok) {
      // VOD anon foi BO/BLBQ exacto se for mux_vod — BLBQ revoke. Se passar, é regressão.
      if (leakedKey(anonMux)) {
        c.hold(
          id: 'p3.mux.anon.stream_key',
          lens: 'BT7',
          severity: 'P1',
          title: 'Anon leu mux_stream_key / stream_key',
          actor: 'anon',
          pre: 'revoke BLBQ colunas Mux a anon',
          repro: 'GET lives select mux_stream_key',
          expected: '401/403 ou coluna null/ausente',
          obtained: anonMux.brief,
        );
      } else {
        c.note('p3.mux.anon.vod', 'anon VOD (exacto BO/BLBQ se ainda aberto)',
            anonMux.brief,
            lens: 'BT7');
      }
    } else {
      c.block('p3.mux.anon', 'BT7', 'anon sem colunas Mux secretas',
          anonMux.brief);
    }

    if (leakedKey(buyerMux)) {
      c.hold(
        id: 'p3.mux.buyer.stream_key',
        lens: 'BT7',
        severity: 'P1',
        title: 'Buyer JWT leu stream key da live de outro vendedor',
        actor: 'buyer JWT',
        pre: 'live broadcasting alheia; authenticated mantém GRANT Mux',
        repro: 'GET lives?id=eq.ownerLive&select=mux_stream_key,stream_key',
        expected: 'sem stream_key (só owner/staff)',
        obtained: buyerMux.brief,
      );
    } else {
      c.block('p3.mux.buyer.stream_key', 'BT7', 'buyer sem stream_key',
          buyerMux.brief);
    }

    if (leakedKey(s2Mux)) {
      c.hold(
        id: 'p3.mux.seller2.stream_key',
        lens: 'BT7',
        severity: 'P1',
        title: 'Seller2 leu stream key da live do seller1',
        actor: 'seller2 JWT',
        pre: 'RLS select live+active; GRANT authenticated',
        repro: 'GET lives mux_stream_key',
        expected: 'sem stream_key',
        obtained: s2Mux.brief,
      );
    } else {
      c.block('p3.mux.seller2.stream_key', 'BT7', 'seller2 sem stream_key',
          s2Mux.brief);
    }

    final muxLiveIdBuyer = buyerMux.map?['mux_live_id']?.toString() ?? '';
    if (muxLiveIdBuyer.contains('RTBTfakeMuxLive')) {
      c.hold(
        id: 'p3.mux.buyer.mux_live_id',
        lens: 'BT7',
        severity: 'P2',
        title: 'Buyer leu mux_live_id alheio (não estava no revoke BLBQ)',
        actor: 'buyer JWT',
        pre: 'revoke só playback/vod/asset/stream_key',
        repro: 'GET lives select mux_live_id',
        expected: 'coluna oculta a não-owner',
        obtained: buyerMux.brief,
      );
    } else {
      c.block('p3.mux.buyer.mux_live_id', 'BT7', 'buyer sem mux_live_id',
          buyerMux.brief);
    }

    // Plantar mux_live_id alheio na live do seller2.
    final liveS2 = await c.createLive(
      seller: c.seller2Id,
      title: '$prefix mux s2',
    );
    if (liveS2 != null) {
      final plant = await c.rest(
        'PATCH',
        'lives?id=eq.$liveS2',
        jwt: c.seller2Jwt,
        body: {
          'mux_live_id': fakeMuxLive,
          'mux_playback_id': fakePlayback,
        },
      );
      final planted = await c.rest(
        'GET',
        'lives?id=eq.$liveS2&select=id,mux_live_id,mux_playback_id,seller_id',
        service: true,
      );
      if (plant.ok &&
          planted.map?['mux_live_id']?.toString() == fakeMuxLive) {
        c.note('p3.mux.plant.own', 'seller2 plantou mux_live_id na PRÓPRIA live',
            planted.map,
            lens: 'BT7');
        final resolve = await c.edge(
          'resolve-mux-playback',
          {'live_id': liveS2},
          jwt: c.buyerJwt,
        );
        c.note('p3.mux.resolve.planted', 'resolve após plant', resolve.brief,
            lens: 'BT7');
      } else {
        c.block('p3.mux.plant.own', 'BT7', 'PATCH mux_live_id próprio falhou',
            plant.brief);
      }

      final hijack = await c.rest(
        'PATCH',
        'lives?id=eq.$liveMux',
        jwt: c.seller2Jwt,
        body: {'mux_playback_id': 'HACKEDBYSELLER2'},
      );
      final afterH = await c.rest(
        'GET',
        'lives?id=eq.$liveMux&select=id,mux_playback_id,seller_id',
        service: true,
      );
      if (hijack.ok &&
          afterH.map?['mux_playback_id']?.toString() == 'HACKEDBYSELLER2') {
        c.hold(
          id: 'p3.mux.patch.foreign',
          lens: 'BT7',
          severity: 'P1',
          title: 'Seller2 PATCH mux_playback_id da live do seller1',
          actor: 'seller2 JWT',
          pre: 'lives_update_own',
          repro: 'PATCH lives?id=eq.seller1Live',
          expected: '0 rows / 401',
          obtained: {'patch': hijack.brief, 'row': afterH.map},
        );
      } else {
        c.block('p3.mux.patch.foreign', 'BT7', 'PATCH live alheia recusado',
            hijack.brief);
      }
    }

    final completeForeign = await c.edge(
      'complete-mux-live',
      {'live_id': liveMux},
      jwt: c.buyerJwt,
    );
    if (completeForeign.ok) {
      c.hold(
        id: 'p3.mux.complete.foreign',
        lens: 'BT7',
        severity: 'P1',
        title: 'Buyer complete-mux-live de live alheia',
        actor: 'buyer JWT',
        pre: 'owner check Edge',
        repro: 'POST complete-mux-live live_id seller1',
        expected: '403',
        obtained: completeForeign.brief,
      );
    } else {
      c.block('p3.mux.complete.foreign', 'BT7', 'complete alheio recusado',
          completeForeign.brief);
    }

    final publishForeign = await c.edge(
      'livekit-mux-publish',
      {'step': 'token', 'live_id': liveMux},
      jwt: c.buyerJwt,
    );
    if (publishForeign.ok) {
      c.hold(
        id: 'p3.mux.publish.foreign',
        lens: 'BT7',
        severity: 'P1',
        title: 'Buyer livekit-mux-publish token de live alheia',
        actor: 'buyer JWT',
        pre: 'owner check Edge',
        repro: 'POST livekit-mux-publish step=token',
        expected: '403',
        obtained: publishForeign.brief,
      );
    } else {
      c.block('p3.mux.publish.foreign', 'BT7', 'publish alheio recusado',
          publishForeign.brief);
    }
  }

  // --- mark_sold hitch produto alheio ---
  final otherSku = await c.createProduct(
    seller: c.seller2Id,
    title: '$prefix s2 sku',
    qty: 3,
  );
  if (otherSku != null && liveD != null) {
    final hitchItem = await c.createLiveItem(
      liveId: liveD,
      title: '$prefix hitch other sku',
      ref: 'RTBT-HO',
      kind: 'live_only',
      checkoutProductId: otherSku,
      quantity: 1,
    );
    if (hitchItem != null) {
      final ms = await c.rpc(
        'batata_mark_live_item_sold',
        {'p_live_item_id': hitchItem},
        jwt: c.sellerJwt,
      );
      final prod = await c.rest(
        'GET',
        'products?id=eq.$otherSku&select=id,is_sold,list_on_marketplace,seller_id,quantity',
        service: true,
      );
      final sold = prod.map?['is_sold'] == true ||
          prod.map?['list_on_marketplace'] == false;
      if (sold) {
        c.hold(
          id: 'p3.mark_sold.hitch.foreign.sku',
          lens: 'BT4',
          severity: 'P1',
          title: 'mark_sold deslistou SKU do seller2 via checkout hitch',
          actor: 'seller JWT',
          pre: 'live_only checkout_product_id = produto alheio',
          repro: 'rpc batata_mark_live_item_sold',
          expected: 'checkout seller mismatch; SKU s2 intacto',
          obtained: {'rpc': ms.brief, 'product': prod.map},
        );
      } else {
        c.block('p3.mark_sold.hitch.foreign.sku', 'BT4',
            'SKU alheio intacto (insert item ou mark recusado)', {
          'item': hitchItem,
          'rpc': ms.brief,
          'product': prod.map,
        });
      }
    } else {
      c.block('p3.mark_sold.hitch.item', 'BT4',
          'INSERT live_item checkout alheio recusado', c.notes.last);
    }
  }

  await c.endAllCreatedLives();
  await dumpJson('${outDir()}/pass3.json', {
    'prefix': prefix,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'PASS3 done findings=${c.findings.length} blocked=${c.blocked.length}');
}
