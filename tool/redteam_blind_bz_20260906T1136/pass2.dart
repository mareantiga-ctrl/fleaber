/// REDTEAM_BLIND_BZ_LIVE_POS_BRBW_v1 — pass2 hitch product_id + paused/inactive + qty.
/// Staging only. No fixes.
import 'dart:io';

import '_rtbz.dart';

Future<void> main() async {
  final c = Rtbz.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final liveA = await c.createLive(title: '$prefix p2A');
  final sku = await c.createProduct(title: '$prefix hitch sku', qty: 1, live: true);
  if (liveA == null || sku == null) {
    stderr.writeln('fixture fail');
    exit(4);
  }

  // Unique (live_id, product_id) impede dois marketplace no mesmo SKU.
  // Hitch novo: marketplace product_id=SKU checkout anulado
  //            + live_only checkout=SKU product_id null, logical null.
  final li1 = await c.createLiveItem(
    liveId: liveA,
    title: '$prefix hitch A',
    ref: 'RTBZ-HA',
    kind: 'marketplace_product',
    productId: sku,
  );
  final li2 = await c.createLiveItem(
    liveId: liveA,
    title: '$prefix hitch B',
    ref: 'RTBZ-HB',
    kind: 'live_only',
    checkoutProductId: sku,
    quantity: 1,
  );
  if (li1 != null) {
    final n1 = await c.rest(
      'PATCH',
      'live_items?id=eq.$li1',
      service: true,
      body: {'checkout_product_id': null, 'logical_item_id': null},
    );
    c.note('p2.hitch.null_checkout.mp', 'anular checkout marketplace', n1.brief,
        lens: 'BZ4');
  }
  if (li1 == null || li2 == null) {
    stderr.writeln('hitch items fail ${c.notes}');
    await c.endAllCreatedLives();
    exit(4);
  }

  final st1 = await c.stock(li1);
  final st2 = await c.stock(li2);
  c.note('p2.hitch.stock.before', 'stock antes product_id-only',
      {'a': st1, 'b': st2},
      lens: 'BZ4');

  final r1 = await c.insertReservation(
    liveId: liveA,
    liveItemId: li1,
    jwt: c.buyerJwt,
    buyer: c.buyerId,
  );
  HttpHit? a1;
  if (r1 != null) {
    a1 = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$r1',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    c.note('p2.hitch.accept1', 'accept LI1 product_id', a1.brief, lens: 'BZ4');
  }
  final stAfter1 = await c.stock(li2);
  c.note('p2.hitch.stock.after1', 'stock LI2 após accept LI1', stAfter1,
      lens: 'BZ4');

  final r2 = await c.insertReservation(
    liveId: liveA,
    liveItemId: li2,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  HttpHit? a2;
  if (r2 != null) {
    a2 = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$r2',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    c.note('p2.hitch.accept2', 'accept LI2 product_id', a2.brief, lens: 'BZ4');
  }
  final row1 = r1 == null
      ? null
      : (await c.rest(
          'GET',
          'live_reservation_requests?id=eq.$r1&select=id,status,requested_qty',
          service: true,
        ))
          .map;
  final row2 = r2 == null
      ? null
      : (await c.rest(
          'GET',
          'live_reservation_requests?id=eq.$r2&select=id,status,requested_qty',
          service: true,
        ))
          .map;
  if (row1?['status'] == 'accepted' && row2?['status'] == 'accepted') {
    c.hold(
      id: 'p2.hitch.product_id.null_checkout',
      lens: 'BZ4',
      severity: 'P1',
      title:
          'Dois accepts no mesmo product_id (checkout null, logical null, refs distintas)',
      actor: 'seller JWT',
      pre: 'live_only qty=1 cada; pool deveria ser 1 unidade',
      repro: 'accept LI1 depois LI2 partilhando product_id',
      expected: '2º accept qty_exceeds_stock',
      obtained: {
        'r1': row1,
        'r2': row2,
        'stock2': stAfter1,
        'accept2': a2?.brief,
      },
    );
  } else {
    c.block('p2.hitch.product_id.null_checkout', 'BZ4',
        '2º accept recusado (HOLD hitch product_id)', {
      'r1': row1,
      'r2': row2,
      'accept2': a2?.brief,
      'stock2': stAfter1,
    });
  }

  // --- Null pool: product_id e checkout null, refs distintas (não devem hitch) ---
  final liveN = await c.createLive(title: '$prefix p2 nullpool');
  final liN1 = liveN == null
      ? null
      : await c.createLiveItem(
          liveId: liveN,
          title: '$prefix null A',
          ref: 'RTBZ-NA',
          kind: 'live_only',
          quantity: 1,
        );
  final liN2 = liveN == null
      ? null
      : await c.createLiveItem(
          liveId: liveN,
          title: '$prefix null B',
          ref: 'RTBZ-NB',
          kind: 'live_only',
          quantity: 1,
        );
  if (liveN != null && liN1 != null && liN2 != null) {
    final rn1 = await c.insertReservation(
      liveId: liveN,
      liveItemId: liN1,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    if (rn1 != null) {
      await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$rn1',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
    }
    final rn2 = await c.insertReservation(
      liveId: liveN,
      liveItemId: liN2,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    );
    HttpHit? an2;
    if (rn2 != null) {
      an2 = await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$rn2',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
    }
    final nn1 = rn1 == null
        ? null
        : (await c.rest(
            'GET',
            'live_reservation_requests?id=eq.$rn1&select=id,status',
            service: true,
          ))
            .map;
    final nn2 = rn2 == null
        ? null
        : (await c.rest(
            'GET',
            'live_reservation_requests?id=eq.$rn2&select=id,status',
            service: true,
          ))
            .map;
    c.note('p2.nullpool.two_units', 'dois live_only sem product (2 unidades)', {
      'n1': nn1,
      'n2': nn2,
      'a2': an2?.brief,
    }, lens: 'BZ4');
  }

  // --- paused sequential (exacto BRBW — não contar se bloquear) ---
  final liveP = await c.createLive(title: '$prefix p2 paused');
  final skuP =
      await c.createProduct(title: '$prefix paused sku', qty: 1, live: true);
  final liP = (liveP == null || skuP == null)
      ? null
      : await c.createLiveItem(
          liveId: liveP,
          title: '$prefix paused item',
          ref: 'RTBZ-PA',
          kind: 'live_only',
          checkoutProductId: skuP,
          quantity: 1,
        );
  if (liveP != null && liP != null) {
    final pause = await c.rest(
      'PATCH',
      'live_items?id=eq.$liP',
      jwt: c.sellerJwt,
      body: {'status': 'paused'},
    );
    c.note('p2.paused.patch', 'seller pause item', pause.brief, lens: 'BZ3');
    final hub = await c.rest(
      'GET',
      'hub_live_items_public?id=eq.$liP&select=id,status',
      jwt: c.buyerJwt,
    );
    c.note('p2.paused.hub', 'Hub após pause', hub.brief, lens: 'BZ3');
    final rp = await c.insertReservation(
      liveId: liveP,
      liveItemId: liP,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    HttpHit? ap;
    if (rp != null) {
      ap = await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$rp',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
    }
    final prow = rp == null
        ? null
        : (await c.rest(
            'GET',
            'live_reservation_requests?id=eq.$rp&select=id,status',
            service: true,
          ))
            .map;
    if (rp != null && prow?['status'] == 'accepted') {
      c.hold(
        id: 'p2.paused.still.accepts',
        lens: 'BZ3',
        severity: 'P2',
        title: 'item paused: buyer pending + seller accept (regressão BRBW)',
        actor: 'buyer+seller JWT',
        pre: 'status=paused',
        repro: 'POST pending; PATCH accepted',
        expected: 'live_item_not_sellable',
        obtained: {'pending': rp, 'accept': ap?.brief, 'row': prow},
      );
    } else {
      c.block('p2.paused.still.accepts', 'BZ3',
          'paused recusado (exacto BRBW, não contar)', {
        'pending': rp,
        'accept': ap?.brief,
        'row': prow,
        'hub': hub.brief,
      });
    }

    // pending ANTES do pause, depois accept.
    final liP2 = await c.createLiveItem(
      liveId: liveP,
      title: '$prefix pause-after-pending',
      ref: 'RTBZ-PB',
      kind: 'live_only',
      quantity: 1,
    );
    if (liP2 != null) {
      final rPend = await c.insertReservation(
        liveId: liveP,
        liveItemId: liP2,
        jwt: c.buyer2Jwt,
        buyer: c.buyer2Id,
      );
      await c.rest(
        'PATCH',
        'live_items?id=eq.$liP2',
        jwt: c.sellerJwt,
        body: {'status': 'paused'},
      );
      HttpHit? accAfterPause;
      if (rPend != null) {
        accAfterPause = await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$rPend',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
      }
      final afterPauseRow = rPend == null
          ? null
          : (await c.rest(
              'GET',
              'live_reservation_requests?id=eq.$rPend&select=id,status',
              service: true,
            ))
              .map;
      if (afterPauseRow?['status'] == 'accepted') {
        c.hold(
          id: 'p2.paused.accept_after_pending',
          lens: 'BZ3',
          severity: 'P2',
          title: 'pending criado, item paused, seller ainda aceita',
          actor: 'seller JWT',
          pre: 'pending em available; depois status=paused',
          repro: 'PATCH item paused; PATCH res accepted',
          expected: 'live_item_not_sellable no accept',
          obtained: {'row': afterPauseRow, 'accept': accAfterPause?.brief},
        );
      } else {
        c.block('p2.paused.accept_after_pending', 'BZ3',
            'accept após pause recusado', {
          'row': afterPauseRow,
          'accept': accAfterPause?.brief,
        });
      }
    }
  }

  // --- is_active=false com status=available (inactive vs paused) ---
  final liveI = await c.createLive(title: '$prefix p2 inactive');
  final liI = liveI == null
      ? null
      : await c.createLiveItem(
          liveId: liveI,
          title: '$prefix inactive flag',
          ref: 'RTBZ-IA',
          kind: 'live_only',
          quantity: 1,
          active: true,
        );
  if (liveI != null && liI != null) {
    final off = await c.rest(
      'PATCH',
      'live_items?id=eq.$liI',
      jwt: c.sellerJwt,
      body: {'is_active': false},
    );
    c.note('p2.inactive.flag', 'is_active=false status=available', off.brief,
        lens: 'BZ3');
    final ri = await c.insertReservation(
      liveId: liveI,
      liveItemId: liI,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    HttpHit? ai;
    if (ri != null) {
      ai = await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$ri',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
    }
    final irow = ri == null
        ? null
        : (await c.rest(
            'GET',
            'live_reservation_requests?id=eq.$ri&select=id,status',
            service: true,
          ))
            .map;
    if (ri != null && irow?['status'] == 'accepted') {
      c.hold(
        id: 'p2.inactive_flag.still.accepts',
        lens: 'BZ3',
        severity: 'P2',
        title: 'is_active=false (status=available): ainda aceita reserva',
        actor: 'buyer+seller JWT',
        pre: 'trigger BRBW v_active is not true',
        repro: 'PATCH is_active=false; pending; accept',
        expected: 'live_item_not_sellable',
        obtained: {'pending': ri, 'accept': ai?.brief, 'row': irow},
      );
    } else {
      c.block('p2.inactive_flag.still.accepts', 'BZ3',
          'is_active=false recusado', {
        'pending': ri,
        'accept': ai?.brief,
        'row': irow,
      });
    }

    final inactStatus = await c.rest(
      'PATCH',
      'live_items?id=eq.$liI',
      jwt: c.sellerJwt,
      body: {'status': 'inactive', 'is_active': true},
    );
    c.note('p2.inactive.status', 'PATCH status=inactive', inactStatus.brief,
        lens: 'BZ3');
  }

  // --- Cross-live hitch: mesmo product_id em duas lives ---
  final liveB = await c.createLive(title: '$prefix p2B');
  final liX1 = liveB == null
      ? null
      : await c.createLiveItem(
          liveId: liveB,
          title: '$prefix hitch liveB',
          ref: 'RTBZ-HX',
          kind: 'marketplace_product',
          productId: sku,
        );
  if (liveB != null && liX1 != null && row1?['status'] == 'accepted') {
    final rx = await c.insertReservation(
      liveId: liveB,
      liveItemId: liX1,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    );
    HttpHit? ax;
    if (rx != null) {
      ax = await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$rx',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
    }
    final xrow = rx == null
        ? null
        : (await c.rest(
            'GET',
            'live_reservation_requests?id=eq.$rx&select=id,status',
            service: true,
          ))
            .map;
    if (xrow?['status'] == 'accepted') {
      c.hold(
        id: 'p2.hitch.cross_live.product_id',
        lens: 'BZ4',
        severity: 'P1',
        title: 'Accept do mesmo SKU em live B depois de accept na live A',
        actor: 'seller JWT',
        pre: 'marketplace product_id partilhado; qty produto=1',
        repro: 'accept live A; accept live B mesmo product_id',
        expected: '2º accept qty_exceeds_stock',
        obtained: {'liveA': row1, 'liveB': xrow, 'acceptB': ax?.brief},
      );
    } else {
      c.block('p2.hitch.cross_live.product_id', 'BZ4',
          'cross-live 2º accept recusado', {
        'liveB': xrow,
        'acceptB': ax?.brief,
      });
    }
  }

  // --- qty após accept (live_only dedicado) ---
  final liveQ = await c.createLive(title: '$prefix p2 qty');
  final liQ = liveQ == null
      ? null
      : await c.createLiveItem(
          liveId: liveQ,
          title: '$prefix qty item',
          ref: 'RTBZ-QTY',
          kind: 'live_only',
          quantity: 1,
        );
  if (liveQ != null && liQ != null) {
    final rq = await c.insertReservation(
      liveId: liveQ,
      liveItemId: liQ,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    if (rq != null) {
      await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$rq',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
    }
    final qItem = await c.rest(
      'PATCH',
      'live_items?id=eq.$liQ',
      jwt: c.sellerJwt,
      body: {'quantity': 9},
    );
    final liAfter = await c.rest(
      'GET',
      'live_items?id=eq.$liQ&select=id,quantity,status',
      service: true,
    );
    final qn = numOf(liAfter.map?['quantity']);
    if (qItem.ok && qn != null && qn > 1) {
      c.hold(
        id: 'p2.patch.item.qty.after_accept',
        lens: 'BZ5',
        severity: 'P1',
        title: 'PATCH live_items.quantity aumentou após accept',
        actor: 'seller JWT',
        pre: 'accept qty=1 live_only',
        repro: 'PATCH quantity=9',
        expected: 'live_item_qty_increase_not_allowed',
        obtained: {'patch': qItem.brief, 'row': liAfter.map},
      );
    } else {
      c.block('p2.patch.item.qty.after_accept', 'BZ5',
          'aumento qty item recusado', qItem.brief);
    }
  }

  await dumpJson('${outDir()}/pass2.json', {
    'auditor': 'REDTEAM_BLIND_BZ_LIVE_POS_BRBW_v1',
    'prefix': prefix,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'pass2 done findings=${c.findings.length} blocked=${c.blocked.length}');
}
