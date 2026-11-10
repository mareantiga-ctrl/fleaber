/// T1 T2 T4 T6 T7 — live reserva / convert / stock / race / 2.º actor
import 'dart:io';

import '_rtt.dart';

Future<void> main() async {
  final c = Rtt.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  stdout.writeln('actors B=${c.buyerId} S=${c.sellerId} B2=${c.buyer2Id} S2=${c.seller2Id}');

  try {
    await t1NullItemAccepted(c);
    await t1MoveItemAfterReserve(c);
    await t1StaffConvertNoPi(c);
    await t1QtyRaceTwoBuyers(c);
    await t1S2ProductOnS1Live(c);
    await t2ConvertWithoutPi(c);
    await t2StripeConvertGrant(c);
    await t2ReconcileCrossPool(c);
    await t2CheckoutAlienReservation(c);
    await t4InflateWhileLiveHold(c);
    await t4InflateLiveItemQty(c);
    await t6ConvertExpireRace(c);
    await t7B2SameItem(c);
  } finally {
    await c.endLives();
  }

  await dumpJson('${outDir()}/pass1.json', {
    'pass': 1,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
  });
  stdout.writeln('pass1 findings=${c.findings.length} blocked=${c.blocked.length}');
}

Future<void> t1NullItemAccepted(Rtt c) async {
  final live = await c.insertLive();
  if (live == null) return;
  final ins = await c.rest('POST', 'live_reservation_requests', jwt: c.sellerJwt, body: {
    'live_id': live,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'requested_qty': 1,
    'source': 'facebook_manual',
    'status': 'accepted',
  });
  c.note('T1.null_item', 'seller facebook_manual accepted sem live_item_id', ins.brief,
      lens: 'T1');
  if (ins.ok && ins.firstId != null) {
    c.createdReservationIds.add(ins.firstId!);
    final row = await c.reservationRow(ins.firstId!);
    if (row?['status'] == 'accepted' && row?['live_item_id'] == null) {
      c.hold(
        id: 'T1-01',
        lens: 'T1',
        severity: 'P1',
        title: 'facebook_manual accepted sem live_item_id (Q1 só valida item quando preenchido)',
        actor: 'seller JWT',
        pre: 'live broadcasting S1',
        repro:
            'POST live_reservation_requests source=facebook_manual status=accepted sem live_item_id',
        expected: 'bloqueado — accepted exige live_item ∈ live',
        obtained: row,
      );
    } else {
      c.closed('T1-01', 'null item accepted recusado ou forçado pending', row, lens: 'T1');
    }
  } else {
    c.closed('T1-01', 'null item accepted HTTP fail', ins.brief, lens: 'T1');
  }
}

Future<void> t1MoveItemAfterReserve(Rtt c) async {
  final liveA = await c.insertLive();
  final liveB = await c.insertLive();
  if (liveA == null || liveB == null) return;
  final item = await c.insertLiveItem(liveId: liveA, title: '$prefix move-item', qty: 2);
  if (item == null) return;
  final rid = await c.insertReservation(
    liveId: liveA,
    liveItemId: item,
    jwt: c.buyerJwt,
  );
  if (rid == null) return;
  final acc = await c.rpc('batata_process_live_reservation_request', {
    'p_request_id': rid,
    'p_action': 'accept',
  }, jwt: c.sellerJwt);
  c.note('T1.move.accept', 'accept before move', acc.brief, lens: 'T1');
  final mv = await c.rest('PATCH', 'live_items?id=eq.$item', jwt: c.sellerJwt, body: {
    'live_id': liveB,
  });
  final itemAfter = await c.liveItemRow(item);
  final resAfter = await c.reservationRow(rid);
  c.note('T1.move.item', 'PATCH live_items.live_id A→B', mv.brief, lens: 'T1');
  if (mv.ok &&
      itemAfter?['live_id'] == liveB &&
      resAfter?['live_id'] == liveA &&
      resAfter?['live_item_id'] == item &&
      resAfter?['status'] == 'accepted') {
    c.hold(
      id: 'T1-02',
      lens: 'T1',
      severity: 'P1',
      title: 'Mover live_item para outra live depois de aceite — reserva fica órfã (Q1 só no INSERT/UPDATE reserva)',
      actor: 'seller JWT',
      pre: 'reserva accepted no live A; item movido para live B (mesmo vendedor)',
      repro: 'PATCH live_items live_id=B após accept no live A',
      expected: 'item.live_id imutável enquanto há reservas que consomem capacidade',
      obtained: {'item': itemAfter, 'res': resAfter},
    );
  } else {
    c.closed('T1-02', 'move item after reserve blocked or no orphan', {
      'mv': mv.brief,
      'item': itemAfter,
      'res': resAfter,
    }, lens: 'T1');
  }
}

Future<void> t1StaffConvertNoPi(Rtt c) async {
  final live = await c.insertLive();
  if (live == null) return;
  final item = await c.insertLiveItem(liveId: live, title: '$prefix staff-item', qty: 1);
  if (item == null) return;
  final hid = await c.inviteHelper(helperId: c.seller2Id!, seller: c.sellerId!);
  c.note('T1.staff.invite', 'S2 helper can_manage_reservations', hid, lens: 'T1');
  final rid = await c.insertReservation(
    liveId: live,
    liveItemId: item,
    jwt: c.buyerJwt,
  );
  if (rid == null) return;
  final acc = await c.rpc('batata_process_live_reservation_request', {
    'p_request_id': rid,
    'p_action': 'accept',
  }, jwt: c.seller2Jwt);
  final conv = await c.rpc('batata_process_live_reservation_request', {
    'p_request_id': rid,
    'p_action': 'convert',
  }, jwt: c.seller2Jwt);
  final row = await c.reservationRow(rid);
  final li = await c.liveItemRow(item);
  c.note('T1.staff.accept', 'helper accept', acc.brief, lens: 'T1');
  c.note('T1.staff.convert', 'helper convert sem PI', conv.brief, lens: 'T1');
  if (row?['status'] == 'converted') {
    c.hold(
      id: 'T1-03',
      lens: 'T1',
      severity: 'P2',
      title: 'Staff helper converte reserva live sem pagamento (convert sem PI)',
      actor: 'seller2 JWT helper',
      pre: 'S2 helper de S1; reserva pending do buyer',
      repro: 'rpc process_live_reservation_request action=convert JWT helper',
      expected: 'convert só após PI pago / reconcile Stripe',
      obtained: {'res': row, 'item': li, 'acc': acc.brief, 'conv': conv.brief},
    );
  } else {
    c.closed('T1-03', 'helper convert sem PI recusado', {
      'acc': acc.brief,
      'conv': conv.brief,
      'res': row,
    }, lens: 'T1');
  }
}

Future<void> t1QtyRaceTwoBuyers(Rtt c) async {
  final live = await c.insertLive();
  if (live == null) return;
  final item = await c.insertLiveItem(liveId: live, title: '$prefix qty-race', qty: 1);
  if (item == null) return;
  final r1 = await c.insertReservation(liveId: live, liveItemId: item, jwt: c.buyerJwt, qty: 1);
  final r2 = await c.insertReservation(
    liveId: live,
    liveItemId: item,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    qty: 1,
  );
  if (r1 == null || r2 == null) return;
  final raced = await parallel([
    c.rpc('batata_process_live_reservation_request', {
      'p_request_id': r1,
      'p_action': 'accept',
    }, jwt: c.sellerJwt),
    c.rpc('batata_process_live_reservation_request', {
      'p_request_id': r2,
      'p_action': 'accept',
    }, jwt: c.sellerJwt),
  ]);
  final a = await c.reservationRow(r1);
  final b = await c.reservationRow(r2);
  final accepted = [a, b].where((r) => r?['status'] == 'accepted').length;
  c.note('T1.qty.race', 'accept∥accept qty=1 item', {
    'h1': raced[0].brief,
    'h2': raced[1].brief,
    'accepted': accepted,
  }, lens: 'T6');
  if (accepted >= 2) {
    c.hold(
      id: 'T1-04',
      lens: 'T6',
      severity: 'P0',
      title: 'Race accept∥accept sobrevende qty=1 (dois accepted)',
      actor: 'seller JWT ×2',
      pre: 'live_item qty=1; duas pending B1 e B2',
      repro: 'Future.wait process accept r1 ∥ accept r2',
      expected: 'só 1 accepted',
      obtained: {'r1': a, 'r2': b, 'http': [raced[0].brief, raced[1].brief]},
    );
  } else {
    c.closed('T1-04', 'qty race capped at 1 accepted', {
      'accepted': accepted,
      'r1': a,
      'r2': b,
    }, lens: 'T6');
  }
}

Future<void> t1S2ProductOnS1Live(Rtt c) async {
  final liveS1 = await c.insertLive();
  final prodS2 = await c.insertProduct(title: '$prefix s2-sku', seller: c.seller2Id, qty: 5);
  if (liveS1 == null || prodS2 == null) return;
  final item = await c.insertLiveItem(
    liveId: liveS1,
    title: '$prefix cross-prod',
    productId: prodS2,
    kind: 'marketplace_product',
    seller: c.seller2Id,
    qty: 5,
  );
  c.note('T1.cross.item', 'live_item S1.live + product S2', item, lens: 'T1');
  if (item == null) {
    c.closed('T1-05', 'não criou live_item com product S2', 'insert fail', lens: 'T1');
    return;
  }
  final rid = await c.insertReservation(
    liveId: liveS1,
    liveItemId: item,
    jwt: c.buyerJwt,
  );
  if (rid == null) {
    c.closed('T1-05', 'reserva recusada no item cross-seller', 'no id', lens: 'T1');
    return;
  }
  final acc = await c.rpc('batata_process_live_reservation_request', {
    'p_request_id': rid,
    'p_action': 'accept',
  }, jwt: c.sellerJwt);
  final row = await c.reservationRow(rid);
  if (row?['status'] == 'accepted' && row?['seller_id'] == c.sellerId) {
    c.hold(
      id: 'T1-05',
      lens: 'T1',
      severity: 'P1',
      title: 'live_item no live S1 aponta a product S2 — reserva aceite desconta stock alheio',
      actor: 'service fixture + seller JWT accept',
      pre: 'live S1 + product S2 ligado via live_items.product_id',
      repro: 'accept reserva no item; observar products.quantity S2',
      expected: 'live_item.product_id tem de ser do dono do live',
      obtained: {'res': row, 'acc': acc.brief, 'item': await c.liveItemRow(item)},
    );
  } else {
    c.closed('T1-05', 'cross-seller product item não aceite', {
      'acc': acc.brief,
      'res': row,
    }, lens: 'T1');
  }
}

Future<void> t2ConvertWithoutPi(Rtt c) async {
  final live = await c.insertLive();
  if (live == null) return;
  final item = await c.insertLiveItem(liveId: live, title: '$prefix conv-nopi', qty: 1);
  if (item == null) return;
  final rid = await c.insertReservation(liveId: live, liveItemId: item, jwt: c.buyerJwt);
  if (rid == null) return;
  await c.rpc('batata_process_live_reservation_request', {
    'p_request_id': rid,
    'p_action': 'accept',
  }, jwt: c.sellerJwt);
  final conv = await c.rpc('batata_process_live_reservation_request', {
    'p_request_id': rid,
    'p_action': 'convert',
  }, jwt: c.sellerJwt);
  final row = await c.reservationRow(rid);
  if (row?['status'] == 'converted' && conv.ok) {
    c.hold(
      id: 'T2-01',
      lens: 'T2',
      severity: 'P2',
      title: 'Seller convert reserva fleaber_live sem PI / encomenda paga',
      actor: 'seller JWT',
      pre: 'reserva accepted origem fleaber_live',
      repro: 'rpc process_live_reservation_request action=convert',
      expected: 'convert Stripe só via service_role após pagamento',
      obtained: {'res': row, 'conv': conv.brief},
    );
  } else {
    c.closed('T2-01', 'seller convert sem PI recusado', conv.brief, lens: 'T2');
  }
}

Future<void> t2StripeConvertGrant(Rtt c) async {
  final live = await c.insertLive();
  if (live == null) return;
  final item = await c.insertLiveItem(liveId: live, title: '$prefix grant-conv', qty: 1);
  if (item == null) return;
  final rid = await c.insertReservation(liveId: live, liveItemId: item, jwt: c.buyerJwt);
  if (rid == null) return;
  final buyerCall = await c.rpc('batata_live_reservation_stripe_convert', {
    'p_request_id': rid,
    'p_order_id': null,
  }, jwt: c.buyerJwt);
  final anonCall = await c.rpc('batata_live_reservation_stripe_convert', {
    'p_request_id': rid,
  });
  c.note('T2.grant.buyer', 'stripe_convert JWT buyer', buyerCall.brief, lens: 'T2');
  c.note('T2.grant.anon', 'stripe_convert anon', anonCall.brief, lens: 'T2');
  final row = await c.reservationRow(rid);
  if (buyerCall.ok && row?['status'] == 'converted') {
    c.hold(
      id: 'T2-02',
      lens: 'T2',
      severity: 'P0',
      title: 'Comprador executa stripe_convert sem pagar',
      actor: 'buyer JWT',
      pre: 'reserva pending',
      repro: 'rpc batata_live_reservation_stripe_convert',
      expected: 'revoke authenticated — só service_role',
      obtained: {'http': buyerCall.brief, 'res': row},
    );
  } else {
    c.closed('T2-02', 'stripe_convert authenticated blocked', buyerCall.brief,
        lens: 'T2');
  }
}

Future<void> t2ReconcileCrossPool(Rtt c) async {
  final live = await c.insertLive();
  if (live == null) return;
  final item = await c.insertLiveItem(liveId: live, title: '$prefix recon', qty: 1);
  if (item == null) return;
  final rid = await c.insertReservation(liveId: live, liveItemId: item, jwt: c.buyerJwt);
  if (rid == null) return;
  await c.rpc('batata_process_live_reservation_request', {
    'p_request_id': rid,
    'p_action': 'accept',
  }, jwt: c.sellerJwt);
  final paid = await c.setupPaidStripe();
  final oid = paid['order_id'];
  if (oid == null) {
    c.closed('T2-03', 'sem order Stripe para reconcile', paid, lens: 'T2');
    return;
  }
  final patch = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
    'live_id': live,
    'live_item_id': item,
  });
  c.note('T2.recon.patch', 'buyer PATCH live_id em order marketplace paga', patch.brief,
      lens: 'T2');
  var order = await c.orderRow(oid);
  if (order?['live_id'] != live) {
    final svcPatch = await c.rest('PATCH', 'orders?id=eq.$oid', service: true, body: {
      'live_id': live,
      'live_item_id': item,
    });
    c.note('T2.recon.svc_observe', 'observe-only: JWT patch failed, not used as actor',
        svcPatch.brief,
        lens: 'T2');
  }
  final recon = await c.rpc('batata_live_reconcile_stripe_order', {
    'p_order_id': oid,
    'p_reservation_request_id': rid,
  }, jwt: c.buyerJwt);
  final res = await c.reservationRow(rid);
  order = await c.orderRow(oid);
  c.note('T2.recon.rpc', 'reconcile marketplace PI → reserva live', recon.brief, lens: 'T2');
  if (res?['status'] == 'converted' && patch.ok) {
    c.hold(
      id: 'T2-03',
      lens: 'T2',
      severity: 'P0',
      title: 'Buyer cola live_id numa encomenda marketplace paga e reconcilia reserva live',
      actor: 'buyer JWT',
      pre: 'order Stripe TEST paga (marketplace) + reserva live accepted',
      repro: 'PATCH orders.live_id + rpc batata_live_reconcile_stripe_order',
      expected: 'live_id selado; reconcile não converte reserva de outro canal',
      obtained: {'patch': patch.brief, 'recon': recon.brief, 'res': res, 'order': order},
    );
  } else if (res?['status'] == 'converted' && !patch.ok) {
    c.closed('T2-03', 'reconcile converteu mas PATCH JWT falhou — sem actor path', {
      'patch': patch.brief,
      'recon': recon.brief,
      'res': res,
    }, lens: 'T2');
  } else {
    c.closed('T2-03', 'cross-pool reconcile não converteu', {
      'patch': patch.brief,
      'recon': recon.brief,
      'res': res,
    }, lens: 'T2');
  }
}

Future<void> t2CheckoutAlienReservation(Rtt c) async {
  final live = await c.insertLive();
  if (live == null) return;
  final prod = await c.insertProduct(title: '$prefix ck-sku', qty: 3, price: 9);
  if (prod == null) return;
  final item = await c.insertLiveItem(
    liveId: live,
    title: '$prefix ck-item',
    productId: prod,
    kind: 'marketplace_product',
    qty: 3,
    price: 9,
  );
  if (item == null) return;
  final rid = await c.insertReservation(liveId: live, liveItemId: item, jwt: c.buyerJwt);
  if (rid == null) return;
  await c.rpc('batata_process_live_reservation_request', {
    'p_request_id': rid,
    'p_action': 'accept',
  }, jwt: c.sellerJwt);
  final oid = await c.insertOrder(
    productId: prod,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
    liveId: live,
    liveItemId: item,
    price: 9,
  );
  final ck = await c.edge('create-payment-intent', {
    'order_id': oid,
    'buyer_id': c.buyer2Id,
    'shipping_method': 'mao',
    'reservation_request_id': rid,
    'live_item_id': item,
    'live_id': live,
  }, jwt: c.buyer2Jwt);
  c.note('T2.ck.alien', 'B2 checkout com reservation_request_id de B1', ck.brief, lens: 'T2');
  if (ck.ok) {
    c.hold(
      id: 'T2-04',
      lens: 'T2',
      severity: 'P1',
      title: 'Checkout B2 aceita reservation_request_id de B1 no body',
      actor: 'buyer2 JWT',
      pre: 'reserva B1 accepted; order B2 no mesmo item',
      repro: 'POST create-payment-intent reservation_request_id=<B1>',
      expected: 'reservation tem de ser do buyer autenticado',
      obtained: ck.brief,
      evidence: {'order': await c.orderRow(oid ?? '')},
    );
  } else {
    c.closed('T2-04', 'checkout alien reservation blocked', ck.brief, lens: 'T2');
  }
}

Future<void> t4InflateWhileLiveHold(Rtt c) async {
  final live = await c.insertLive();
  final prod = await c.insertProduct(title: '$prefix hold-sku', qty: 1, price: 7);
  if (live == null || prod == null) return;
  final item = await c.insertLiveItem(
    liveId: live,
    title: '$prefix hold-item',
    productId: prod,
    kind: 'marketplace_product',
    qty: 1,
    price: 7,
  );
  if (item == null) return;
  final rid = await c.insertReservation(liveId: live, liveItemId: item, jwt: c.buyerJwt);
  if (rid == null) return;
  await c.rpc('batata_process_live_reservation_request', {
    'p_request_id': rid,
    'p_action': 'accept',
  }, jwt: c.sellerJwt);
  final before = await c.productRow(prod);
  final infl = await c.rest('PATCH', 'products?id=eq.$prod', jwt: c.sellerJwt, body: {
    'quantity': 9,
  });
  final after = await c.productRow(prod);
  c.note('T4.inflate.livehold', 'PATCH products.quantity com reserva live accepted',
      infl.brief,
      lens: 'T4');
  final bq = before?['quantity'];
  final aq = after?['quantity'];
  if (infl.ok && aq is num && bq is num && aq > bq) {
    c.hold(
      id: 'T4-01',
      lens: 'T4',
      severity: 'P1',
      title: 'Inflacionar products.quantity com hold live accepted (Q6 só olha orders.stock_units_applied)',
      actor: 'seller JWT',
      pre: 'live reserva accepted qty=1; sem order paga',
      repro: 'PATCH products.quantity 1→9',
      expected: 'bloqueado enquanto reserva live consome capacidade',
      obtained: {'before': before, 'after': after, 'http': infl.brief},
    );
  } else {
    c.closed('T4-01', 'inflate with live hold blocked', {
      'http': infl.brief,
      'before': before,
      'after': after,
    }, lens: 'T4');
  }
}

Future<void> t4InflateLiveItemQty(Rtt c) async {
  final live = await c.insertLive();
  if (live == null) return;
  final item = await c.insertLiveItem(liveId: live, title: '$prefix li-qty', qty: 1);
  if (item == null) return;
  final rid = await c.insertReservation(liveId: live, liveItemId: item, jwt: c.buyerJwt);
  if (rid == null) return;
  await c.rpc('batata_process_live_reservation_request', {
    'p_request_id': rid,
    'p_action': 'accept',
  }, jwt: c.sellerJwt);
  final infl = await c.rest('PATCH', 'live_items?id=eq.$item', jwt: c.sellerJwt, body: {
    'quantity': 20,
  });
  final after = await c.liveItemRow(item);
  c.note('T4.inflate.li', 'PATCH live_items.quantity 1→20 com accepted', infl.brief,
      lens: 'T4');
  if (infl.ok && (after?['quantity'] == 20 || after?['quantity'] == 20.0)) {
    final r2 = await c.insertReservation(
      liveId: live,
      liveItemId: item,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    );
    HttpHit? acc2;
    if (r2 != null) {
      acc2 = await c.rpc('batata_process_live_reservation_request', {
        'p_request_id': r2,
        'p_action': 'accept',
      }, jwt: c.sellerJwt);
    }
    final row2 = r2 == null ? null : await c.reservationRow(r2);
    if (row2?['status'] == 'accepted') {
      c.hold(
        id: 'T4-02',
        lens: 'T4',
        severity: 'P1',
        title: 'Inflacionar live_items.quantity permite segundo accept',
        actor: 'seller JWT',
        pre: 'qty=1 accepted B1; PATCH quantity=20; accept B2',
        repro: 'PATCH live_items.quantity + process accept B2',
        expected: 'quantity do item live-only não sobe com hold activo',
        obtained: {'item': after, 'b2': row2, 'acc2': acc2?.brief},
      );
    } else {
      c.closed('T4-02', 'qty inflate não permitiu 2.º accept', {
        'item': after,
        'b2': row2,
        'acc2': acc2?.brief,
      }, lens: 'T4');
    }
  } else {
    c.closed('T4-02', 'live_items.quantity inflate blocked', infl.brief, lens: 'T4');
  }
}

Future<void> t6ConvertExpireRace(Rtt c) async {
  final live = await c.insertLive();
  if (live == null) return;
  final item = await c.insertLiveItem(liveId: live, title: '$prefix conv-exp', qty: 1);
  if (item == null) return;
  final rid = await c.insertReservation(liveId: live, liveItemId: item, jwt: c.buyerJwt);
  if (rid == null) return;
  await c.rpc('batata_process_live_reservation_request', {
    'p_request_id': rid,
    'p_action': 'accept',
  }, jwt: c.sellerJwt);
  final raced = await parallel([
    c.rpc('batata_process_live_reservation_request', {
      'p_request_id': rid,
      'p_action': 'convert',
    }, jwt: c.sellerJwt),
    c.rpc('batata_process_live_reservation_request', {
      'p_request_id': rid,
      'p_action': 'expire',
    }, jwt: c.sellerJwt),
  ]);
  final row = await c.reservationRow(rid);
  final li = await c.liveItemRow(item);
  c.note('T6.convert_expire', 'convert∥expire', {
    'c': raced[0].brief,
    'e': raced[1].brief,
    'res': row,
    'item': li,
  }, lens: 'T6');
  final st = row?['status']?.toString();
  final bothOk = raced[0].ok && raced[1].ok;
  if (bothOk && st == 'converted') {
    c.note('T6.convert_expire.win', 'convert ganhou; expire HTTP 200 sem efeito final',
        st,
        lens: 'T6');
  }
  if (bothOk && st == 'expired' && li?['status'] == 'sold') {
    c.hold(
      id: 'T6-01',
      lens: 'T6',
      severity: 'P1',
      title: 'Race convert∥expire: reserva expired mas item sold',
      actor: 'seller JWT ×2',
      pre: 'accepted qty=1',
      repro: 'Future.wait convert ∥ expire',
      expected: 'estado reserva e item coerentes',
      obtained: {'res': row, 'item': li, 'http': [raced[0].brief, raced[1].brief]},
    );
  } else {
    c.closed('T6-01', 'convert∥expire sem split estado', {
      'res': row,
      'item': li,
    }, lens: 'T6');
  }
}

Future<void> t7B2SameItem(Rtt c) async {
  final live = await c.insertLive();
  if (live == null) return;
  final item = await c.insertLiveItem(liveId: live, title: '$prefix b2-item', qty: 1);
  if (item == null) return;
  final r1 = await c.insertReservation(liveId: live, liveItemId: item, jwt: c.buyerJwt);
  if (r1 == null) return;
  await c.rpc('batata_process_live_reservation_request', {
    'p_request_id': r1,
    'p_action': 'accept',
  }, jwt: c.sellerJwt);
  final steal = await c.rest('PATCH', 'live_reservation_requests?id=eq.$r1', jwt: c.buyer2Jwt, body: {
    'buyer_id': c.buyer2Id,
    'status': 'accepted',
  });
  final row = await c.reservationRow(r1);
  c.note('T7.steal.res', 'B2 PATCH reserva B1', steal.brief, lens: 'T7');
  if (steal.ok && row?['buyer_id'] == c.buyer2Id) {
    c.hold(
      id: 'T7-01',
      lens: 'T7',
      severity: 'P0',
      title: 'B2 assume reserva accepted de B1',
      actor: 'buyer2 JWT',
      pre: 'reserva B1 accepted',
      repro: 'PATCH live_reservation_requests buyer_id=B2',
      expected: 'RLS update só seller/staff; buyer_id imutável',
      obtained: {'http': steal.brief, 'res': row},
    );
  } else {
    c.closed('T7-01', 'B2 não rouba reserva', steal.brief, lens: 'T7');
  }
}
