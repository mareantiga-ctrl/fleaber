/// REDTEAM_BLIND_BZ_LIVE_POS_BRBW_v1 — pass3 race pause∥accept + Mux playback_id + caixa.
/// Staging only. No fixes.
import 'dart:io';

import '_rtbz.dart';

Future<void> main() async {
  final c = Rtbz.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2(hubPublished: false);

  // --- Race pause ∥ accept ---
  final liveR = await c.createLive(title: '$prefix race pause');
  final skuR =
      await c.createProduct(title: '$prefix race sku', qty: 1, live: true);
  final liR = (liveR == null || skuR == null)
      ? null
      : await c.createLiveItem(
          liveId: liveR,
          title: '$prefix race item',
          ref: 'RTBZ-RC',
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
      'live_items?id=eq.$liR',
      jwt: c.sellerJwt,
      body: {'status': 'paused'},
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
  final itemAfter = await c.rest(
    'GET',
    'live_items?id=eq.$liR&select=id,status,is_active',
    service: true,
  );
  c.note('p3.race.raw', 'pause∥accept hits', {
    'accept1': raced[0].brief,
    'pause': raced[1].brief,
    'accept2': raced[2].brief,
    'res': afterRace.map,
    'item': itemAfter.map,
  }, lens: 'BZ6');

  final paused = itemAfter.map?['status']?.toString() == 'paused';
  final accepted = afterRace.map?['status']?.toString() == 'accepted';
  if (paused && accepted) {
    c.hold(
      id: 'p3.race.pause_accept',
      lens: 'BZ6',
      severity: 'P2',
      title: 'Race pause∥accept: item paused e reserva accepted',
      actor: 'seller JWT paralelo',
      pre: 'pending; PATCH paused ∥ PATCH accepted',
      repro: 'Future.wait pause + 2× accept',
      expected: 'accepted XOR paused; não os dois',
      obtained: {
        'res': afterRace.map,
        'item': itemAfter.map,
        'hits': [raced[0].brief, raced[1].brief, raced[2].brief],
      },
    );
  } else {
    c.block('p3.race.pause_accept', 'BZ6', 'race não deixou paused+accepted', {
      'paused': paused,
      'accepted': accepted,
      'res': afterRace.map,
      'item': itemAfter.map,
    });
  }

  // Race is_active=false ∥ accept (outro item).
  final liR2 = await c.createLiveItem(
    liveId: liveR,
    title: '$prefix race inactive',
    ref: 'RTBZ-RI',
    kind: 'live_only',
    quantity: 1,
  );
  if (liR2 != null) {
    final r2 = await c.insertReservation(
      liveId: liveR,
      liveItemId: liR2,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    );
    if (r2 != null) {
      final raced2 = await Future.wait([
        c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$r2',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        ),
        c.rest(
          'PATCH',
          'live_items?id=eq.$liR2',
          jwt: c.sellerJwt,
          body: {'is_active': false},
        ),
      ]);
      final after2 = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$r2&select=id,status',
        service: true,
      );
      final item2 = await c.rest(
        'GET',
        'live_items?id=eq.$liR2&select=id,status,is_active',
        service: true,
      );
      final off = item2.map?['is_active'] == false;
      final acc = after2.map?['status']?.toString() == 'accepted';
      if (off && acc) {
        c.hold(
          id: 'p3.race.inactive_flag_accept',
          lens: 'BZ6',
          severity: 'P2',
          title: 'Race is_active=false∥accept: flag off e accepted',
          actor: 'seller JWT paralelo',
          pre: 'pending; PATCH is_active=false ∥ accepted',
          repro: 'Future.wait',
          expected: 'não accepted se item inactivo',
          obtained: {
            'res': after2.map,
            'item': item2.map,
            'hits': [raced2[0].brief, raced2[1].brief],
          },
        );
      } else {
        c.block('p3.race.inactive_flag_accept', 'BZ6',
            'race inactive não deixou off+accepted', {
          'off': off,
          'accepted': acc,
          'res': after2.map,
          'item': item2.map,
        });
      }
    }
  }

  // Accept paralelo qty=1 dois buyers (HOLD stock).
  final liveQ = await c.createLive(title: '$prefix race qty');
  final liQ = liveQ == null
      ? null
      : await c.createLiveItem(
          liveId: liveQ,
          title: '$prefix qty1',
          ref: 'RTBZ-Q1',
          kind: 'live_only',
          quantity: 1,
        );
  if (liveQ != null && liQ != null) {
    final rq1 = await c.insertReservation(
      liveId: liveQ,
      liveItemId: liQ,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    final rq2 = await c.insertReservation(
      liveId: liveQ,
      liveItemId: liQ,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    );
    if (rq1 != null && rq2 != null) {
      final par = await Future.wait([
        c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$rq1',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        ),
        c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$rq2',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        ),
      ]);
      final g1 = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$rq1&select=id,status',
        service: true,
      );
      final g2 = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$rq2&select=id,status',
        service: true,
      );
      final nAcc = [
        g1.map?['status'],
        g2.map?['status'],
      ].where((s) => s == 'accepted').length;
      if (nAcc >= 2) {
        c.hold(
          id: 'p3.race.double_accept.qty1',
          lens: 'BZ6',
          severity: 'P1',
          title: 'Dois accepts paralelos em qty=1',
          actor: 'seller JWT',
          pre: 'dois pending; qty=1',
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
        c.block('p3.race.double_accept.qty1', 'BZ6', 'só 1 accepted (HOLD)', {
          'nAcc': nAcc,
          'a': g1.map,
          'b': g2.map,
        });
      }
    }
  }

  // --- Mux playback_id alheio ---
  const fakePlayback = 'BZPLAYBACK1136fake0001';
  const fakeVod = 'BZVOD1136fake0001xxxx';
  const fakeAsset = 'BZASSET1136fake0001xxx';

  final liveUnpub = await c.createLive(
    seller: c.seller2Id,
    title: '$prefix mux unpub',
    extra: {
      'mux_playback_id': fakePlayback,
      'mux_vod_playback_id': fakeVod,
      'mux_asset_id': fakeAsset,
    },
  );
  final liveSched = await c.createLive(
    seller: c.seller2Id,
    title: '$prefix mux sched',
    status: 'scheduled',
    active: false,
    extra: {'mux_playback_id': 'BZSCHED1136fake0001'},
  );
  final liveEnded = await c.createLive(
    seller: c.seller2Id,
    title: '$prefix mux ended',
    status: 'ended',
    active: false,
    extra: {
      'mux_playback_id': 'BZENDED1136fake0001',
      'mux_vod_playback_id': fakeVod,
    },
  );
  final livePub = await c.createLive(
    title: '$prefix mux pub seller1',
    extra: {'mux_playback_id': 'BZPUB1136fake0001xxxx'},
  );

  Future<void> probeMux({
    required String id,
    required String? liveId,
    required String? jwt,
    required String actor,
    required String col,
    bool expectDeny = true,
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
      if (expectDeny) {
        c.hold(
          id: id,
          lens: 'BZ7',
          severity: 'P2',
          title: '$actor lê $col de live alheia',
          actor: actor,
          pre: 'BRBW revoke VOD/asset; playback_id ainda granted authenticated',
          repro: 'GET lives?id=eq.$liveId&select=$col',
          expected: 'vazio / 403 coluna',
          obtained: h.brief,
          evidence: {'col': col, 'val': val, 'live': liveId},
        );
      } else {
        c.note(id, '$actor lê $col (esperado dono/Hub)', h.brief, lens: 'BZ7');
      }
    } else {
      c.block(id, 'BZ7', '$actor não lê $col', h.brief);
    }
  }

  await probeMux(
    id: 'p3.mux.buyer.playback.unpub',
    liveId: liveUnpub,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    col: 'mux_playback_id',
  );
  await probeMux(
    id: 'p3.mux.buyer.vod.unpub',
    liveId: liveUnpub,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    col: 'mux_vod_playback_id',
  );
  await probeMux(
    id: 'p3.mux.buyer.asset.unpub',
    liveId: liveUnpub,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    col: 'mux_asset_id',
  );
  await probeMux(
    id: 'p3.mux.buyer.playback.sched',
    liveId: liveSched,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    col: 'mux_playback_id',
  );
  await probeMux(
    id: 'p3.mux.buyer.playback.ended',
    liveId: liveEnded,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    col: 'mux_playback_id',
  );
  await probeMux(
    id: 'p3.mux.buyer.vod.ended',
    liveId: liveEnded,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    col: 'mux_vod_playback_id',
  );
  await probeMux(
    id: 'p3.mux.buyer.playback.pub',
    liveId: livePub,
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    col: 'mux_playback_id',
    expectDeny: true,
  );
  await probeMux(
    id: 'p3.mux.anon.playback.unpub',
    liveId: liveUnpub,
    jwt: null,
    actor: 'anon',
    col: 'mux_playback_id',
  );
  await probeMux(
    id: 'p3.mux.seller2.own.playback',
    liveId: liveUnpub,
    jwt: c.seller2Jwt,
    actor: 'seller2 owner',
    col: 'mux_playback_id',
    expectDeny: false,
  );

  // Hub views.
  if (liveUnpub != null) {
    final hubAnon = await c.rest(
      'GET',
      'hub_lives_public?id=eq.$liveUnpub&select=id,mux_playback_id,mux_vod_playback_id',
    );
    final hubAuth = await c.rest(
      'GET',
      'hub_lives_public?id=eq.$liveUnpub&select=id,mux_playback_id,mux_vod_playback_id',
      jwt: c.buyerJwt,
    );
    final disc = await c.rest(
      'GET',
      'hub_lives_discovery_public?id=eq.$liveUnpub&select=id,mux_playback_id',
      jwt: c.buyerJwt,
    );
    c.note('p3.mux.hub.unpub', 'Hub unpublished', {
      'anon': hubAnon.brief,
      'auth': hubAuth.brief,
      'disc': disc.brief,
    }, lens: 'BZ7');
    final leakedHub = (hubAnon.map?['mux_playback_id'] ??
            hubAuth.map?['mux_playback_id'] ??
            disc.map?['mux_playback_id'])
        ?.toString();
    if (leakedHub != null && leakedHub.isNotEmpty) {
      c.hold(
        id: 'p3.mux.hub.unpub.playback',
        lens: 'BZ7',
        severity: 'P2',
        title: 'Hub expõe mux_playback_id de live unpublished',
        actor: 'anon/buyer',
        pre: 'seller2 hub_published=false',
        repro: 'GET hub_lives_public / discovery',
        expected: '[] / null',
        obtained: {
          'anon': hubAnon.brief,
          'auth': hubAuth.brief,
          'disc': disc.brief,
        },
      );
    } else {
      c.block('p3.mux.hub.unpub.playback', 'BZ7', 'Hub unpublished sem playback',
          hubAuth.brief);
    }
  }

  // resolve-mux-playback
  Future<void> resolveMux(String tag, String? liveId, String? jwt) async {
    if (liveId == null) return;
    final h = await c.edge(
      'resolve-mux-playback',
      {'live_id': liveId},
      jwt: jwt,
    );
    final pid = h.map?['playback_id']?.toString();
    final leaked = h.ok && pid != null && pid.isNotEmpty;
    if (leaked) {
      c.hold(
        id: 'p3.mux.resolve.$tag',
        lens: 'BZ7',
        severity: 'P2',
        title: 'resolve-mux-playback devolveu playback ($tag)',
        actor: jwt == null ? 'anon' : 'JWT',
        pre: 'BRBW exige hub_published ou dono',
        repro: 'POST /functions/v1/resolve-mux-playback',
        expected: '404 live_not_public',
        obtained: h.brief,
      );
    } else {
      c.block('p3.mux.resolve.$tag', 'BZ7', 'resolve recusado/vazio $tag',
          h.brief);
    }
  }

  await resolveMux('unpub.buyer', liveUnpub, c.buyerJwt);
  await resolveMux('unpub.anon', liveUnpub, null);
  await resolveMux('unpub.owner', liveUnpub, c.seller2Jwt);
  await resolveMux('sched.buyer', liveSched, c.buyerJwt);
  await resolveMux('ended.buyer', liveEnded, c.buyerJwt);

  // complete-mux / livekit alheio
  if (liveUnpub != null) {
    final complete = await c.edge(
      'complete-mux-live',
      {'live_id': liveUnpub},
      jwt: c.buyerJwt,
    );
    final publish = await c.edge(
      'livekit-mux-publish',
      {'live_id': liveUnpub},
      jwt: c.buyerJwt,
    );
    if (complete.ok) {
      c.hold(
        id: 'p3.mux.complete.buyer',
        lens: 'BZ7',
        severity: 'P1',
        title: 'Buyer complete-mux-live em live alheia',
        actor: 'buyer JWT',
        pre: 'live seller2',
        repro: 'POST complete-mux-live',
        expected: '403',
        obtained: complete.brief,
      );
    } else {
      c.block('p3.mux.complete.buyer', 'BZ7', 'complete alheio recusado',
          complete.brief);
    }
    if (publish.ok) {
      c.hold(
        id: 'p3.mux.publish.buyer',
        lens: 'BZ7',
        severity: 'P1',
        title: 'Buyer livekit-mux-publish em live alheia',
        actor: 'buyer JWT',
        pre: 'live seller2',
        repro: 'POST livekit-mux-publish',
        expected: '403',
        obtained: publish.brief,
      );
    } else {
      c.block('p3.mux.publish.buyer', 'BZ7', 'publish alheio recusado',
          publish.brief);
    }
  }

  // Caixa: PATCH converted já no pass1; aqui fake order reconcile.
  final liveC = await c.createLive(title: '$prefix caixa');
  final skuC =
      await c.createProduct(title: '$prefix caixa sku', qty: 1, live: true);
  final liC = (liveC == null || skuC == null)
      ? null
      : await c.createLiveItem(
          liveId: liveC,
          title: '$prefix caixa item',
          ref: 'RTBZ-CX',
          kind: 'live_only',
          checkoutProductId: skuC,
          quantity: 1,
        );
  if (liveC != null && liC != null) {
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
      if (fakeOrder.ok && fakeOrder.firstId != null) {
        final rec = await c.rpc(
          'batata_live_reconcile_stripe_order',
          {
            'p_order_id': fakeOrder.firstId,
            'p_reservation_request_id': rc,
          },
          jwt: c.sellerJwt,
        );
        final after = await c.rest(
          'GET',
          'live_reservation_requests?id=eq.$rc&select=id,status',
          service: true,
        );
        if (rec.map?['ok'] == true && after.map?['status'] == 'converted') {
          c.hold(
            id: 'p3.caixa.reconcile.unpaid',
            lens: 'BZ8',
            severity: 'P0',
            title: 'reconcile order pendente → converted',
            actor: 'seller JWT',
            pre: 'order status=pendente sem captura',
            repro: 'rpc batata_live_reconcile_stripe_order',
            expected: 'recusa',
            obtained: {'rpc': rec.brief, 'res': after.map},
          );
        } else {
          c.block('p3.caixa.reconcile.unpaid', 'BZ8',
              'reconcile sem captura recusado', rec.brief);
        }
      } else {
        c.note('p3.caixa.order.insert', 'POST order pendente', fakeOrder.brief,
            lens: 'BZ8');
      }
    }
  }

  await dumpJson('${outDir()}/pass3.json', {
    'auditor': 'REDTEAM_BLIND_BZ_LIVE_POS_BRBW_v1',
    'prefix': prefix,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'pass3 done findings=${c.findings.length} blocked=${c.blocked.length}');
}
