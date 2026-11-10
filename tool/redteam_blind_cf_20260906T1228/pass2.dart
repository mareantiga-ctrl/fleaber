/// REDTEAM_BLIND_CF_LIVE_POS_BXCC_v1 — pass2 convert/PI/staff/hitch qty.
/// Staging only. No fixes.
import 'dart:io';

import '_rtcf.dart';

Future<void> main() async {
  final c = Rtcf.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureHelperChatOnly();
  await c.ensureHelperNone();
  await c.ensureHelperSold();

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
    ref: 'RTCF-P2A',
    kind: 'live_only',
    checkoutProductId: skuA,
    quantity: 1,
  );
  final itemB = await c.createLiveItem(
    liveId: liveB,
    title: '$prefix p2 itemB',
    ref: 'RTCF-P2B',
    kind: 'live_only',
    checkoutProductId: skuB,
    quantity: 1,
  );
  if (itemA == null || itemB == null) {
    stderr.writeln('items fail');
    await c.endAllCreatedLives();
    exit(4);
  }

  // CF1 — purchase_broadcast sem PI (HOLD se recusar).
  for (final actor in ['buyer', 'seller', 'helper']) {
    final jwt = actor == 'buyer'
        ? c.buyerJwt
        : actor == 'seller'
            ? c.sellerJwt
            : c.helperJwt;
    final h = await c.rpc(
      'batata_live_purchase_broadcast',
      {
        'p_live_id': liveA,
        'p_buyer_id': c.buyerId,
        'p_live_item_id': itemA,
      },
      jwt: jwt,
    );
    final persisted = h.json == true || h.map?['ok'] == true;
    if (persisted) {
      c.hold(
        id: 'p2.broadcast.$actor.nopi',
        lens: 'CF1',
        severity: 'P1',
        title: 'purchase_broadcast sem order paga ($actor)',
        actor: '$actor JWT',
        pre: 'sem PI',
        repro: 'rpc batata_live_purchase_broadcast',
        expected: 'false',
        obtained: h.brief,
      );
    } else {
      c.block('p2.broadcast.$actor.nopi', 'CF1', 'broadcast sem PI recusado',
          h.brief);
    }
  }

  final accBuyer = await c.rpc(
    'batata_live_reservation_accept_broadcast',
    {
      'p_live_id': liveA,
      'p_buyer_id': c.buyerId,
      'p_live_item_id': itemA,
      'p_requested_qty': 1,
    },
    jwt: c.buyerJwt,
  );
  if (accBuyer.json == true) {
    c.hold(
      id: 'p2.accept_broadcast.buyer',
      lens: 'CF1',
      severity: 'P2',
      title: 'Buyer JWT accept_broadcast true',
      actor: 'buyer JWT',
      pre: 'só seller/staff',
      repro: 'rpc batata_live_reservation_accept_broadcast buyer',
      expected: 'false',
      obtained: accBuyer.brief,
    );
  } else {
    c.block('p2.accept_broadcast.buyer', 'CF1',
        'buyer accept_broadcast recusado (HOLD)', accBuyer.brief);
  }

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
  final accA = await c.rest(
    'PATCH',
    'live_reservation_requests?id=eq.$ridA',
    jwt: c.sellerJwt,
    body: {'status': 'accepted'},
  );
  c.note('p2.accept.A', 'seller accept A', accA.brief, lens: 'CF1');

  // Convert JWT sem PI.
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
      id: 'p2.convert.seller.nopi',
      lens: 'CF1',
      severity: 'P0',
      title: 'stripe_convert sem PI deixou status=converted',
      actor: 'seller JWT',
      pre: 'accepted, sem order paga',
      repro: 'rpc batata_live_reservation_stripe_convert',
      expected: 'recusa; status≠converted',
      obtained: {'rpc': convRpc.brief, 'row': afterConv.map},
    );
  } else {
    c.block('p2.convert.seller.nopi', 'CF1', 'convert sem PI recusado',
        {'rpc': convRpc.brief, 'status': st});
  }

  final patchConv = await c.rest(
    'PATCH',
    'live_reservation_requests?id=eq.$ridA',
    jwt: c.sellerJwt,
    body: {'status': 'converted'},
  );
  final afterP = await c.rest(
    'GET',
    'live_reservation_requests?id=eq.$ridA&select=id,status',
    service: true,
  );
  if (patchConv.ok && afterP.map?['status'] == 'converted') {
    c.hold(
      id: 'p2.patch.converted.nopi',
      lens: 'CF8',
      severity: 'P0',
      title: 'PATCH converted sem order paga',
      actor: 'seller JWT',
      pre: 'accepted, sem PI',
      repro: 'PATCH status=converted',
      expected: 'convert_requires_paid_order',
      obtained: {'patch': patchConv.brief, 'row': afterP.map},
    );
  } else {
    c.block('p2.patch.converted.nopi', 'CF8', 'PATCH converted recusado',
        patchConv.brief);
  }

  // CF1 — PI de outra live / outro buyer.
  // Plant order "pago" com PI em live A (service) e tentar reconciliar na live B.
  final ridB = await c.insertReservation(
    liveId: liveB,
    liveItemId: itemB,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  HttpHit? accB;
  if (ridB != null) {
    accB = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$ridB',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    c.note('p2.accept.B', 'seller accept B', accB.brief, lens: 'CF1');
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
    'stripe_payment_intent_id': 'pi_rtcf_stolen_${stamp}_A',
    'amount_paid_cents': 900,
  });
  if (planted.firstId != null) c.createdOrderIds.add(planted.firstId!);
  c.note('p2.plant.orderA', 'plant pago+PI live A', planted.brief, lens: 'CF1');

  if (planted.ok && planted.firstId != null) {
    // Broadcast live B com buyer da order A.
    final bcStolen = await c.rpc(
      'batata_live_purchase_broadcast',
      {
        'p_live_id': liveB,
        'p_buyer_id': c.buyerId,
        'p_live_item_id': itemB,
      },
      jwt: c.sellerJwt,
    );
    final persistedBc = bcStolen.json == true || bcStolen.map?['ok'] == true;
    if (persistedBc) {
      c.hold(
        id: 'p2.broadcast.pi_other_live',
        lens: 'CF1',
        severity: 'P1',
        title: 'purchase_broadcast live B com PI/order de live A',
        actor: 'seller JWT',
        pre: 'order paga só em live A / item A',
        repro: 'rpc purchase_broadcast live B item B buyer A',
        expected: 'false (PI/live mismatch)',
        obtained: bcStolen.brief,
      );
    } else {
      c.block('p2.broadcast.pi_other_live', 'CF1',
          'broadcast PI live errada recusado', bcStolen.brief);
    }

    if (ridB != null) {
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
          id: 'p2.reconcile.pi_other_live',
          lens: 'CF1',
          severity: 'P0',
          title: 'reconcile order live A → reserva live B converted',
          actor: 'seller JWT',
          pre: 'PI/order de outra live e outro item',
          repro: 'rpc batata_live_reconcile_stripe_order orderA + resB',
          expected: 'mismatch recusa',
          obtained: {'rpc': recCross.brief, 'res': afterCross.map},
        );
      } else {
        c.block('p2.reconcile.pi_other_live', 'CF1',
            'reconcile PI live errada recusado', recCross.brief);
      }
    }

    // Buyer copia PI para order pendente própria noutra live.
    final fakeB = await c.rest('POST', 'orders', jwt: c.buyer2Jwt, body: {
      'buyer_id': c.buyer2Id,
      'seller_id': c.sellerId,
      'product_id': skuB,
      'live_id': liveB,
      'live_item_id': itemB,
      'quantity': 1,
      'price_total': 9,
      'status': 'pendente',
      'payment_method': 'MB WAY',
      'shipping_method': 'entrega em mão',
    });
    if (fakeB.firstId != null) c.createdOrderIds.add(fakeB.firstId!);
    c.note('p2.orderB.pendente', 'POST order B pendente', fakeB.brief,
        lens: 'CF1');
    if (fakeB.ok && fakeB.firstId != null) {
      final copyPi = await c.rest(
        'PATCH',
        'orders?id=eq.${fakeB.firstId}',
        jwt: c.buyer2Jwt,
        body: {
          'stripe_payment_intent_id': 'pi_rtcf_stolen_${stamp}_A',
          'status': 'pago',
          'amount_paid_cents': 900,
        },
      );
      final afterCopy = await c.rest(
        'GET',
        'orders?id=eq.${fakeB.firstId}&select=id,status,stripe_payment_intent_id,amount_paid_cents',
        service: true,
      );
      final copied = afterCopy.map?['status']?.toString() == 'pago' ||
          '${afterCopy.map?['stripe_payment_intent_id']}'.contains('stolen');
      if (copyPi.ok && copied) {
        c.hold(
          id: 'p2.buyer.patch.stolen_pi',
          lens: 'CF1',
          severity: 'P0',
          title: 'Buyer PATCH order com PI/status pago alheio',
          actor: 'buyer2 JWT',
          pre: 'order pendente própria',
          repro: 'PATCH stripe_payment_intent_id + status=pago',
          expected: 'colunas financeiras imutáveis pelo JWT',
          obtained: {'patch': copyPi.brief, 'row': afterCopy.map},
        );
      } else {
        c.block('p2.buyer.patch.stolen_pi', 'CF1',
            'buyer não copia PI/pago', copyPi.brief);
      }
    }
  } else {
    c.note('p2.plant.orderA.fail', 'não plantou order paga', planted.brief,
        lens: 'CF1');
  }

  // Helper self-escalate.
  final hrows = await c.rest(
    'GET',
    'seller_helpers?helper_user_id=eq.${c.helperId}&select=id,permissions,active',
    service: true,
  );
  final hid = hrows.map?['id']?.toString();
  if (hid != null) {
    final before = hrows.map?['permissions'];
    final esc = await c.rest(
      'PATCH',
      'seller_helpers?id=eq.$hid',
      jwt: c.helperJwt,
      body: {
        'permissions': {
          'can_mark_items_sold': true,
          'can_manage_reservations': true,
          'can_manage_chat': true,
        },
      },
    );
    final after = await c.rest(
      'GET',
      'seller_helpers?id=eq.$hid&select=permissions',
      service: true,
    );
    final perms = after.map?['permissions'];
    final got = perms is Map && perms['can_mark_items_sold'] == true;
    final had = before is Map && before['can_mark_items_sold'] == true;
    if (esc.ok && got && !had) {
      c.hold(
        id: 'p2.helper.self_escalate',
        lens: 'CF1',
        severity: 'P1',
        title: 'Helper PATCH permissions self-escalate',
        actor: 'helper chat JWT',
        pre: 'só can_manage_chat',
        repro: 'PATCH seller_helpers permissions',
        expected: 'RLS bloqueia',
        obtained: {'patch': esc.brief, 'before': before, 'after': perms},
      );
    } else {
      c.block('p2.helper.self_escalate', 'CF1', 'helper self-escalate recusado', {
        'patch': esc.brief,
        'before': before,
        'after': perms,
      });
    }
  }

  // Helper zero-perms tenta accept.
  if (ridB != null) {
    final hAcc = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$ridB',
      jwt: c.helperNoneJwt,
      body: {'status': 'accepted'},
    );
    c.note('p2.helper0.accept', 'helper zero accept', hAcc.brief, lens: 'CF1');
  }

  // Helper sold-only tenta convert.
  if (ridA != null) {
    final hConv = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$ridA',
      jwt: c.helperSoldJwt,
      body: {'status': 'converted'},
    );
    final afterH = await c.rest(
      'GET',
      'live_reservation_requests?id=eq.$ridA&select=id,status',
      service: true,
    );
    if (hConv.ok && afterH.map?['status'] == 'converted') {
      c.hold(
        id: 'p2.helper.sold.convert',
        lens: 'CF1',
        severity: 'P0',
        title: 'Helper can_mark_items_sold converteu sem PI',
        actor: 'helper sold JWT',
        pre: 'can_mark_items_sold, sem order paga',
        repro: 'PATCH converted',
        expected: 'convert_requires_paid_order',
        obtained: {'patch': hConv.brief, 'row': afterH.map},
      );
    } else {
      c.block('p2.helper.sold.convert', 'CF1',
          'helper sold convert recusado', hConv.brief);
    }
  }

  // OCR helper / buyer.
  final ocr = await c.edge(
    'ingest-ocr-reservation',
    {
      'live_id': liveA,
      'ocr_line_hash': 'rtcfhash12280001',
      'ocr_raw_line': 'sold last one taken',
    },
    jwt: c.helperJwt,
  );
  if (ocr.ok) {
    c.hold(
      id: 'p2.helper.ocr',
      lens: 'CF1',
      severity: 'P2',
      title: 'Helper chat ingest-ocr sem device token',
      actor: 'helper JWT',
      pre: 'OCR staff device',
      repro: 'POST ingest-ocr-reservation',
      expected: '401/403',
      obtained: ocr.brief,
    );
  } else {
    c.block('p2.helper.ocr', 'CF1', 'OCR helper recusado', ocr.brief);
  }

  // CF5 — qty hitch N>stock.
  final liveQ = await c.createLive(title: '$prefix p2 qty');
  final skuQ =
      await c.createProduct(title: '$prefix p2 qty sku', qty: 1, live: true);
  final liQ = (liveQ == null || skuQ == null)
      ? null
      : await c.createLiveItem(
          liveId: liveQ,
          title: '$prefix qty over',
          ref: 'RTCF-QO',
          kind: 'live_only',
          checkoutProductId: skuQ,
          quantity: 1,
        );
  if (liveQ != null && liQ != null) {
    final over = await c.insertReservation(
      liveId: liveQ,
      liveItemId: liQ,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
      qty: 5,
    );
    if (over != null) {
      final accOver = await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$over',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
      final rowOver = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$over&select=id,status,requested_qty',
        service: true,
      );
      final stOver = await c.stock(liQ);
      if (rowOver.map?['status'] == 'accepted' &&
          (rowOver.map?['requested_qty'] as num? ?? 0) > 1) {
        c.hold(
          id: 'p2.qty.over_stock.accept',
          lens: 'CF5',
          severity: 'P1',
          title: 'Accept qty=5 em item qty=1',
          actor: 'seller JWT',
          pre: 'live_only quantity=1',
          repro: 'POST reservation requested_qty=5 + PATCH accepted',
          expected: 'qty_exceeds_stock / pending recusado',
          obtained: {
            'row': rowOver.map,
            'accept': accOver.brief,
            'stock': stOver,
          },
        );
      } else {
        c.block('p2.qty.over_stock.accept', 'CF5', 'qty>stock não accepted', {
          'row': rowOver.map,
          'accept': accOver.brief,
          'pending_id': over,
        });
      }
    } else {
      c.block('p2.qty.over_stock.pending', 'CF5',
          'pending qty=5 recusado (HOLD)', 'no row');
    }
  }

  // CF4 — 2 hitch mesma unidade (product_id pool). HOLD se 2º recusar.
  final liveH = await c.createLive(title: '$prefix p2 hitch');
  final skuH =
      await c.createProduct(title: '$prefix hitch sku', qty: 1, live: true);
  if (liveH != null && skuH != null) {
    final li1 = await c.createLiveItem(
      liveId: liveH,
      title: '$prefix hitch A',
      ref: 'RTCF-HA',
      kind: 'marketplace_product',
      productId: skuH,
    );
    final li2 = await c.createLiveItem(
      liveId: liveH,
      title: '$prefix hitch B',
      ref: 'RTCF-HB',
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
      HttpHit? a2;
      if (r2 != null) {
        a2 = await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$r2',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
      }
      final row1 = r1 == null
          ? null
          : (await c.rest(
              'GET',
              'live_reservation_requests?id=eq.$r1&select=id,status',
              service: true,
            ))
              .map;
      final row2 = r2 == null
          ? null
          : (await c.rest(
              'GET',
              'live_reservation_requests?id=eq.$r2&select=id,status',
              service: true,
            ))
              .map;
      if (row1?['status'] == 'accepted' && row2?['status'] == 'accepted') {
        c.hold(
          id: 'p2.hitch.two_accepts',
          lens: 'CF4',
          severity: 'P1',
          title: 'Dois accepts no mesmo SKU (hitch product_id)',
          actor: 'seller JWT',
          pre: 'qty produto=1; marketplace+live_only',
          repro: 'accept LI1 depois LI2',
          expected: '2º qty_exceeds_stock',
          obtained: {'r1': row1, 'r2': row2, 'a2': a2?.brief},
        );
      } else {
        c.block('p2.hitch.two_accepts', 'CF4',
            '2º accept recusado (HOLD hitch)', {
          'r1': row1,
          'r2': row2,
          'a2': a2?.brief,
        });
      }
    }
  }

  await dumpJson('${outDir()}/pass2.json', {
    'auditor': 'REDTEAM_BLIND_CF_LIVE_POS_BXCC_v1',
    'prefix': prefix,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'pass2 done findings=${c.findings.length} blocked=${c.blocked.length}');
}
