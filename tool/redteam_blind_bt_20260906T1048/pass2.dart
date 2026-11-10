/// REDTEAM_BLIND_BT_LIVE_POS_BLBQ_v1 — pass2 hitch / qty / paused / live_id.
/// Staging only. No fixes.
import 'dart:io';

import '_rtbt.dart';

Future<void> main() async {
  final c = Rtbt.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final liveA = await c.createLive(title: '$prefix p2A');
  final liveB = await c.createLive(title: '$prefix p2B');
  final sku = await c.createProduct(title: '$prefix hitch sku', qty: 1, live: true);
  if (liveA == null || liveB == null || sku == null) {
    stderr.writeln('fixture fail');
    exit(4);
  }

  // --- Hitch checkout_product_id, refs distintas, logical null ---
  final li1 = await c.createLiveItem(
    liveId: liveA,
    title: '$prefix hitch A',
    ref: 'RTBT-HA',
    kind: 'live_only',
    checkoutProductId: sku,
    quantity: 1,
  );
  final li2 = await c.createLiveItem(
    liveId: liveA,
    title: '$prefix hitch B',
    ref: 'RTBT-HB',
    kind: 'live_only',
    checkoutProductId: sku,
    quantity: 1,
  );
  if (li1 == null || li2 == null) {
    stderr.writeln('hitch items fail ${c.notes}');
    await c.endAllCreatedLives();
    exit(4);
  }

  final st1 = await c.stock(li1);
  final st2 = await c.stock(li2);
  c.note('p2.hitch.stock.before', 'stock antes', {'a': st1, 'b': st2},
      lens: 'BT4');

  final r1 = await c.insertReservation(
    liveId: liveA,
    liveItemId: li1,
    jwt: c.buyerJwt,
    buyer: c.buyerId,
  );
  if (r1 != null) {
    final a1 = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$r1',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    c.note('p2.hitch.accept1', 'accept LI1', a1.brief, lens: 'BT4');
  }
  final stAfter1 = await c.stock(li2);
  c.note('p2.hitch.stock.after1', 'stock LI2 após accept LI1', stAfter1,
      lens: 'BT4');

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
    c.note('p2.hitch.accept2', 'accept LI2', a2.brief, lens: 'BT4');
  }
  final row1 = r1 == null
      ? null
      : (await c.rest(
          'GET',
          'live_reservation_requests?id=eq.$r1&select=id,status,requested_qty,live_item_id',
          service: true,
        )).map;
  final row2 = r2 == null
      ? null
      : (await c.rest(
          'GET',
          'live_reservation_requests?id=eq.$r2&select=id,status,requested_qty,live_item_id',
          service: true,
        )).map;
  final twoAccepted =
      row1?['status'] == 'accepted' && row2?['status'] == 'accepted';
  final avail2 = numOf(stAfter1?['available_qty']);
  if (twoAccepted) {
    c.hold(
      id: 'p2.hitch.checkout_product_id',
      lens: 'BT4',
      severity: 'P1',
      title:
          'Dois accepts em live_only com o mesmo checkout_product_id, refs distintas, logical null',
      actor: 'seller JWT + 2 buyers',
      pre: 'SKU qty=1; LI1/LI2 checkout=SKU; logical_item_id null; refs HA/HB',
      repro: 'pending+accept LI1 depois pending+accept LI2',
      expected: '2º accept qty_exceeds_stock; available_qty LI2 = 0',
      obtained: {
        'row1': row1,
        'row2': row2,
        'stock_li2_after1': stAfter1,
        'accept2': a2?.brief,
      },
    );
  } else {
    c.block(
      'p2.hitch.checkout_product_id',
      'BT4',
      '2º accept bloqueado ou stock 0',
      {
        'row1': row1,
        'row2': row2,
        'avail2': avail2,
        'accept2': a2?.brief,
      },
    );
  }

  // Hitch cruzado: product_id vs checkout_product_id (coalesce mismatch).
  final skuA = await c.createProduct(title: '$prefix skuA', qty: 1, live: true);
  final skuB = await c.createProduct(title: '$prefix skuB', qty: 1, live: true);
  if (skuA != null && skuB != null) {
    final lx1 = await c.createLiveItem(
      liveId: liveA,
      title: '$prefix cross1',
      ref: 'RTBT-CX1',
      kind: 'marketplace_product',
      productId: skuA,
      checkoutProductId: skuB,
    );
    final lx2 = await c.createLiveItem(
      liveId: liveA,
      title: '$prefix cross2',
      ref: 'RTBT-CX2',
      kind: 'marketplace_product',
      productId: skuB,
      checkoutProductId: skuA,
    );
    if (lx1 != null && lx2 != null) {
      final sx1 = await c.stock(lx1);
      final sx2 = await c.stock(lx2);
      c.note('p2.cross.stock', 'coalesce mismatch stock', {'x1': sx1, 'x2': sx2},
          lens: 'BT4');
      final rx1 = await c.insertReservation(
        liveId: liveA,
        liveItemId: lx1,
        jwt: c.buyerJwt,
        buyer: c.buyerId,
      );
      if (rx1 != null) {
        await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$rx1',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
      }
      final rx2 = await c.insertReservation(
        liveId: liveA,
        liveItemId: lx2,
        jwt: c.buyer2Jwt,
        buyer: c.buyer2Id,
      );
      HttpHit? ax2;
      if (rx2 != null) {
        ax2 = await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$rx2',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
      }
      final xrow1 = rx1 == null
          ? null
          : (await c.rest(
              'GET',
              'live_reservation_requests?id=eq.$rx1&select=id,status',
              service: true,
            )).map;
      final xrow2 = rx2 == null
          ? null
          : (await c.rest(
              'GET',
              'live_reservation_requests?id=eq.$rx2&select=id,status',
              service: true,
            )).map;
      if (xrow1?['status'] == 'accepted' && xrow2?['status'] == 'accepted') {
        c.hold(
          id: 'p2.hitch.product_vs_checkout_coalesce',
          lens: 'BT4',
          severity: 'P1',
          title:
              'Accept duplo: product_id=A/checkout=B vs product_id=B/checkout=A',
          actor: 'seller JWT',
          pre: 'coalesce(product,checkout) não cruza; logical null; refs distintas',
          repro: 'accept ambos marketplace_product cruzados',
          expected: '2º accept recusado se o SKU real é o mesmo pool',
          obtained: {
            'x1': xrow1,
            'x2': xrow2,
            'stock1': sx1,
            'stock2': sx2,
            'accept2': ax2?.brief,
          },
        );
      } else {
        c.block('p2.hitch.product_vs_checkout_coalesce', 'BT4',
            'cruzado não aceitou os dois', {
          'x1': xrow1,
          'x2': xrow2,
          'accept2': ax2?.brief,
        });
      }
    }
  }

  // --- PATCH quantity após accept ---
  if (r1 != null && row1?['status'] == 'accepted') {
    final qItem = await c.rest(
      'PATCH',
      'live_items?id=eq.$li1',
      jwt: c.sellerJwt,
      body: {'quantity': 9},
    );
    final liAfter = await c.rest(
      'GET',
      'live_items?id=eq.$li1&select=id,quantity,status',
      service: true,
    );
    final qn = numOf(liAfter.map?['quantity']);
    if (qItem.ok && qn != null && qn > 1) {
      c.hold(
        id: 'p2.patch.item.qty.after_accept',
        lens: 'BT5',
        severity: 'P1',
        title: 'PATCH live_items.quantity aumentou após accept (live_only)',
        actor: 'seller JWT',
        pre: 'accept qty=1 em live_only',
        repro: 'PATCH live_items quantity=9',
        expected: 'live_item_qty_increase_not_allowed',
        obtained: {'patch': qItem.brief, 'row': liAfter.map},
      );
    } else {
      c.block('p2.patch.item.qty.after_accept', 'BT5',
          'aumento qty item recusado', qItem.brief);
    }

    final qRes = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$r1',
      jwt: c.sellerJwt,
      body: {'requested_qty': 5},
    );
    final resAfter = await c.rest(
      'GET',
      'live_reservation_requests?id=eq.$r1&select=id,status,requested_qty',
      service: true,
    );
    final rq = numOf(resAfter.map?['requested_qty']);
    if (qRes.ok && rq != null && rq > 1) {
      c.hold(
        id: 'p2.patch.res.qty.after_accept',
        lens: 'BT5',
        severity: 'P1',
        title: 'PATCH requested_qty aumentou após accept',
        actor: 'seller JWT',
        pre: 'accepted qty=1, item qty=1',
        repro: 'PATCH live_reservation_requests requested_qty=5',
        expected: 'qty_exceeds_stock ou revert',
        obtained: {'patch': qRes.brief, 'row': resAfter.map},
      );
    } else {
      c.block('p2.patch.res.qty.after_accept', 'BT5',
          'aumento requested_qty recusado', qRes.brief);
    }

    final qBuyer = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$r1',
      jwt: c.buyerJwt,
      body: {'requested_qty': 4},
    );
    final resB = await c.rest(
      'GET',
      'live_reservation_requests?id=eq.$r1&select=id,requested_qty',
      service: true,
    );
    final rqb = numOf(resB.map?['requested_qty']);
    if (qBuyer.ok && rqb != null && rqb > 1) {
      c.hold(
        id: 'p2.patch.res.qty.buyer',
        lens: 'BT5',
        severity: 'P1',
        title: 'Buyer aumentou requested_qty após accept',
        actor: 'buyer JWT',
        pre: 'accepted',
        repro: 'PATCH requested_qty=4 buyer',
        expected: 'revert / 403',
        obtained: {'patch': qBuyer.brief, 'row': resB.map},
      );
    } else {
      c.block('p2.patch.res.qty.buyer', 'BT5', 'buyer qty recusado/revert',
          {'patch': qBuyer.brief, 'qty': rqb});
    }
  }

  // --- Pending fantasma noutra live (ended) ---
  final skuP = await c.createProduct(title: '$prefix phantom', qty: 1, live: true);
  final liB = await c.createLiveItem(
    liveId: liveB,
    title: '$prefix phantom B',
    ref: 'RTBT-PHB',
    kind: 'live_only',
    checkoutProductId: skuP,
    quantity: 1,
  );
  if (skuP != null && liB != null) {
    final rp = await c.insertReservation(
      liveId: liveB,
      liveItemId: liB,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    await c.endLive(liveB);
    final liveC = await c.createLive(title: '$prefix p2C');
    final liC = liveC == null
        ? null
        : await c.createLiveItem(
            liveId: liveC,
            title: '$prefix phantom C',
            ref: 'RTBT-PHC',
            kind: 'live_only',
            checkoutProductId: skuP,
            quantity: 1,
          );
    if (liveC != null && liC != null) {
      final stC = await c.stock(liC);
      final availC = numOf(stC?['available_qty'])?.toInt() ?? -1;
      final pendB = rp == null
          ? null
          : (await c.rest(
              'GET',
              'live_reservation_requests?id=eq.$rp&select=id,status,live_id',
              service: true,
            )).map;
      c.note('p2.phantom.stock', 'stock live C com pending ended B', {
        'stockC': stC,
        'pendingB': pendB,
      }, lens: 'BT3');
      final rC = await c.insertReservation(
        liveId: liveC,
        liveItemId: liC,
        jwt: c.buyer2Jwt,
        buyer: c.buyer2Id,
      );
      HttpHit? aC;
      if (rC != null) {
        aC = await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$rC',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
      }
      final rowC = rC == null
          ? null
          : (await c.rest(
              'GET',
              'live_reservation_requests?id=eq.$rC&select=id,status',
              service: true,
            )).map;
      final pendStill = pendB?['status'] == 'pending';
      if (pendStill && rowC?['status'] == 'accepted') {
        c.hold(
          id: 'p2.phantom.pending.ended.oversell',
          lens: 'BT3',
          severity: 'P1',
          title:
              'Pending em live ended não bloqueou accept na live nova (mesmo checkout)',
          actor: 'seller JWT',
          pre: 'pending live B ended; live C mesmo checkout_product_id qty=1',
          repro: 'end B; accept C',
          expected:
              'pending ended expira OU available C=0 e 2º accept recusado',
          obtained: {
            'pendingB': pendB,
            'stockC': stC,
            'rowC': rowC,
            'acceptC': aC?.brief,
          },
        );
      } else if (pendStill && availC <= 0 && rowC?['status'] != 'accepted') {
        c.note(
          'p2.phantom.pending.blocks',
          'pending ended ainda congela stock da live nova (não oversell)',
          {'availC': availC, 'pendingB': pendB},
          lens: 'BT3',
        );
      } else {
        c.block('p2.phantom.pending.ended', 'BT3', 'pending ended tratado', {
          'pendingB': pendB,
          'availC': availC,
          'rowC': rowC,
        });
      }
    }
  }

  // --- paused / inactive ainda aceita ---
  final liveP = await c.createLive(title: '$prefix paused');
  final skuPause =
      await c.createProduct(title: '$prefix pause sku', qty: 1, live: true);
  final liP = (liveP == null || skuPause == null)
      ? null
      : await c.createLiveItem(
          liveId: liveP,
          title: '$prefix paused item',
          ref: 'RTBT-PA',
          kind: 'live_only',
          checkoutProductId: skuPause,
          quantity: 1,
          status: 'available',
        );
  if (liveP != null && liP != null) {
    final pause = await c.rest(
      'PATCH',
      'live_items?id=eq.$liP',
      jwt: c.sellerJwt,
      body: {'status': 'paused'},
    );
    c.note('p2.pause.patch', 'item paused', pause.brief, lens: 'BT5');
    final hub = await c.rest(
      'GET',
      'hub_live_items_public?id=eq.$liP&select=id,status',
      jwt: c.buyerJwt,
    );
    final pendingP = await c.insertReservation(
      liveId: liveP,
      liveItemId: liP,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    HttpHit? accP;
    Map<String, dynamic>? rowP;
    if (pendingP != null) {
      accP = await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$pendingP',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
      rowP = (await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$pendingP&select=id,status',
        service: true,
      ))
          .map;
    }
    final inactive = await c.createLiveItem(
      liveId: liveP,
      title: '$prefix inactive item',
      ref: 'RTBT-IN',
      kind: 'live_only',
      checkoutProductId: skuPause,
      quantity: 1,
      status: 'inactive',
    );
    String? pendingI;
    Map<String, dynamic>? rowI;
    if (inactive != null) {
      pendingI = await c.insertReservation(
        liveId: liveP,
        liveItemId: inactive,
        jwt: c.buyer2Jwt,
        buyer: c.buyer2Id,
      );
      if (pendingI != null) {
        await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$pendingI',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
        rowI = (await c.rest(
          'GET',
          'live_reservation_requests?id=eq.$pendingI&select=id,status',
          service: true,
        ))
            .map;
      }
    }
    if (rowP?['status'] == 'accepted') {
      c.hold(
        id: 'p2.paused.still.accepts',
        lens: 'BT5',
        severity: 'P2',
        title: 'Item paused: buyer entra na fila e seller aceita',
        actor: 'buyer JWT + seller JWT',
        pre: 'live_items.status=paused; Hub não lista o card',
        repro: 'PATCH status=paused; POST pending; PATCH accepted',
        expected: 'pending/accept recusados (item não está à venda)',
        obtained: {
          'pause': pause.brief,
          'hub': hub.brief,
          'row': rowP,
          'accept': accP?.brief,
        },
      );
    } else {
      c.block('p2.paused.still.accepts', 'BT5', 'paused não aceitou', {
        'pending': pendingP,
        'row': rowP,
        'hub': hub.brief,
      });
    }
    if (rowI?['status'] == 'accepted') {
      c.hold(
        id: 'p2.inactive.still.accepts',
        lens: 'BT5',
        severity: 'P2',
        title: 'Item inactive: fila+accept',
        actor: 'buyer2 + seller',
        pre: 'status=inactive',
        repro: 'INSERT pending + PATCH accepted',
        expected: 'recusa',
        obtained: {'row': rowI},
      );
    } else {
      c.block('p2.inactive.still.accepts', 'BT5', 'inactive não aceitou', rowI);
    }
  }

  // --- live_id swap no accept ---
  final liveSwap = await c.createLive(title: '$prefix swap');
  final skuS =
      await c.createProduct(title: '$prefix swap sku', qty: 1, live: true);
  final liS = (liveSwap == null || skuS == null)
      ? null
      : await c.createLiveItem(
          liveId: liveSwap,
          title: '$prefix swap item',
          ref: 'RTBT-SW',
          kind: 'live_only',
          checkoutProductId: skuS,
          quantity: 1,
        );
  if (liveSwap != null && liS != null) {
    final rs = await c.insertReservation(
      liveId: liveSwap,
      liveItemId: liS,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    if (rs != null) {
      final swap = await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$rs',
        jwt: c.sellerJwt,
        body: {'live_id': liveA, 'status': 'accepted'},
      );
      final afterSwap = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$rs&select=id,status,live_id,live_item_id',
        service: true,
      );
      if (swap.ok && afterSwap.map?['live_id']?.toString() == liveA) {
        c.hold(
          id: 'p2.live_id.swap.accept',
          lens: 'BT5',
          severity: 'P1',
          title: 'Accept com live_id trocado para outra live',
          actor: 'seller JWT',
          pre: 'reserva na live Swap; PATCH live_id=liveA + accepted',
          repro: 'PATCH live_reservation_requests live_id+status',
          expected: 'live_item_live_mismatch',
          obtained: {'patch': swap.brief, 'row': afterSwap.map},
        );
      } else {
        c.block('p2.live_id.swap.accept', 'BT5', 'swap live_id recusado',
            swap.brief);
      }

      final bc = await c.rpc(
        'batata_live_reservation_accept_broadcast',
        {
          'p_live_id': liveA,
          'p_buyer_id': c.buyerId,
          'p_live_item_id': liS,
          'p_requested_qty': 1,
        },
        jwt: c.sellerJwt,
      );
      if (bc.json == true) {
        c.hold(
          id: 'p2.accept_broadcast.live_id.swap',
          lens: 'BT1',
          severity: 'P2',
          title: 'accept_broadcast com live_id de outra live',
          actor: 'seller JWT',
          pre: 'item pertence a liveSwap; p_live_id=liveA',
          repro: 'rpc accept_broadcast live mismatch',
          expected: 'false',
          obtained: bc.brief,
        );
      } else {
        c.block('p2.accept_broadcast.live_id.swap', 'BT1',
            'broadcast live mismatch recusado', bc.brief);
      }
    }
  }

  await c.endAllCreatedLives();
  await dumpJson('${outDir()}/pass2.json', {
    'prefix': prefix,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'PASS2 done findings=${c.findings.length} blocked=${c.blocked.length}');
}
