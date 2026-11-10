/// Reprobe T1-02 / T2-01 / T2-03 / T6-01 after select bug
import 'dart:io';

import '_rtt.dart';

Future<void> main() async {
  final c = Rtt.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  try {
    await reproMoveItem(c);
    await reproSellerConvertNoPi(c);
    await reproReconcileCross(c);
    await reproConvertExpire(c);
    await reproCheckoutAlien(c);
  } finally {
    await c.endLives();
  }

  await dumpJson('${outDir()}/pass1b.json', {
    'pass': '1b',
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
  });
  stdout.writeln('pass1b findings=${c.findings.length} blocked=${c.blocked.length}');
}

Future<void> reproMoveItem(Rtt c) async {
  final liveA = await c.insertLive();
  final liveB = await c.insertLive();
  if (liveA == null || liveB == null) return;
  final item = await c.insertLiveItem(liveId: liveA, title: '$prefix move2', qty: 2);
  if (item == null) return;
  final rid = await c.insertReservation(liveId: liveA, liveItemId: item, jwt: c.buyerJwt);
  if (rid == null) return;
  await c.rpc('batata_process_live_reservation_request', {
    'p_request_id': rid,
    'p_action': 'accept',
  }, jwt: c.sellerJwt);
  final mv = await c.rest('PATCH', 'live_items?id=eq.$item', jwt: c.sellerJwt, body: {
    'live_id': liveB,
  });
  final itemAfter = await c.liveItemRow(item);
  final resAfter = await c.reservationRow(rid);
  c.note('T1.move2', 'move item A→B', {
    'mv': mv.brief,
    'item': itemAfter,
    'res': resAfter,
  }, lens: 'T1');
  if (mv.ok &&
      itemAfter?['live_id'] == liveB &&
      resAfter?['live_id'] == liveA &&
      resAfter?['live_item_id'] == item) {
    final ck = await c.edge('create-payment-intent', {
      'buyer_id': c.buyerId,
      'shipping_method': 'mao',
      'live_id': liveA,
      'live_item_id': item,
      'reservation_request_id': rid,
    }, jwt: c.buyerJwt);
    c.note('T1.move2.ck', 'checkout após item noutro live', ck.brief, lens: 'T1');
    c.hold(
      id: 'T1-02',
      lens: 'T1',
      severity: 'P1',
      title: 'Seller move live_item para outro live; reserva accepted fica com live_id antigo',
      actor: 'seller JWT',
      pre: 'reserva accepted live A; PATCH item.live_id=B',
      repro: 'PATCH live_items.live_id após accept',
      expected: 'bloquear move enquanto reservas consomem o item',
      obtained: {'item': itemAfter, 'res': resAfter, 'checkout': ck.brief},
    );
  } else {
    c.closed('T1-02', 'move não deixou órfã', {
      'item': itemAfter,
      'res': resAfter,
      'mv': mv.brief,
    }, lens: 'T1');
  }
}

Future<void> reproSellerConvertNoPi(Rtt c) async {
  final live = await c.insertLive();
  if (live == null) return;
  final item = await c.insertLiveItem(liveId: live, title: '$prefix conv2', qty: 1);
  if (item == null) return;
  final rid = await c.insertReservation(
    liveId: live,
    liveItemId: item,
    jwt: c.buyerJwt,
    source: 'fleaber_live',
  );
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
  final li = await c.liveItemRow(item);
  c.note('T2.conv2', 'seller convert fleaber_live sem PI', {
    'conv': conv.brief,
    'res': row,
    'item': li,
  }, lens: 'T2');
  if (row?['status'] == 'converted' && li?['status'] == 'sold') {
    c.hold(
      id: 'T2-01',
      lens: 'T2',
      severity: 'P1',
      title: 'Seller converte reserva fleaber_live (saco) sem PaymentIntent',
      actor: 'seller JWT',
      pre: 'accepted origem fleaber_live, sem order paga',
      repro: 'rpc process_live_reservation_request action=convert',
      expected: 'convert de fleaber_live só após Stripe/reconcile',
      obtained: {'res': row, 'item': li, 'conv': conv.brief},
    );
  } else {
    c.closed('T2-01', 'convert sem PI não marcou converted+sold', {
      'res': row,
      'item': li,
    }, lens: 'T2');
  }
}

Future<void> reproReconcileCross(Rtt c) async {
  final live = await c.insertLive();
  if (live == null) return;
  final item = await c.insertLiveItem(liveId: live, title: '$prefix recon2', qty: 1);
  if (item == null) return;
  final rid = await c.insertReservation(liveId: live, liveItemId: item, jwt: c.buyerJwt);
  if (rid == null) return;
  await c.rpc('batata_process_live_reservation_request', {
    'p_request_id': rid,
    'p_action': 'accept',
  }, jwt: c.sellerJwt);
  final paid = await c.setupPaidStripe();
  final oid = paid['order_id'];
  if (oid == null) return;
  final orderBefore = await c.orderRow(oid);
  final recon = await c.rpc('batata_live_reconcile_stripe_order', {
    'p_order_id': oid,
    'p_reservation_request_id': rid,
  }, jwt: c.buyerJwt);
  final res = await c.reservationRow(rid);
  final li = await c.liveItemRow(item);
  final orderAfter = await c.orderRow(oid);
  c.note('T2.recon2', 'reconcile PI marketplace → reserva live', {
    'recon': recon.brief,
    'res': res,
    'item': li,
    'orderLive': orderAfter?['live_id'],
    'orderItem': orderAfter?['live_item_id'],
    'pi': paid['pi'],
  }, lens: 'T2');
  if (res?['status'] == 'converted') {
    c.hold(
      id: 'T2-03',
      lens: 'T2',
      severity: 'P0',
      title: 'Buyer reconcilia PI marketplace pago com reserva live — converte sem pagar o artigo do directo',
      actor: 'buyer JWT',
      pre: 'order Stripe TEST marketplace paga; reserva live accepted noutro product',
      repro:
          'rpc batata_live_reconcile_stripe_order p_order_id=<marketplace> p_reservation_request_id=<live>',
      expected: 'reservation_request_id tem de pertencer à order (mesmo product/live_item/PI metadata)',
      obtained: {
        'recon': recon.brief,
        'res': res,
        'item': li,
        'orderBefore': {
          'live_id': orderBefore?['live_id'],
          'live_item_id': orderBefore?['live_item_id'],
          'product_id': orderBefore?['product_id'],
          'status': orderBefore?['status'],
          'pi': orderBefore?['stripe_payment_intent_id'],
        },
        'orderAfter': {
          'live_id': orderAfter?['live_id'],
          'live_item_id': orderAfter?['live_item_id'],
          'product_id': orderAfter?['product_id'],
          'status': orderAfter?['status'],
        },
      },
    );
  } else {
    c.closed('T2-03', 'reconcile cross-pool não converteu', {
      'recon': recon.brief,
      'res': res,
    }, lens: 'T2');
  }
}

Future<void> reproConvertExpire(Rtt c) async {
  final live = await c.insertLive();
  if (live == null) return;
  final item = await c.insertLiveItem(liveId: live, title: '$prefix ce2', qty: 1);
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
  c.note('T6.ce2', 'convert∥expire', {
    'c': raced[0].brief,
    'e': raced[1].brief,
    'res': row,
    'item': li,
  }, lens: 'T6');
  final st = '${row?['status']}';
  final ist = '${li?['status']}';
  final split = (st == 'converted' && ist == 'available') ||
      (st == 'expired' && ist == 'sold') ||
      (st == 'converted' && ist != 'sold');
  if (split) {
    c.hold(
      id: 'T6-01',
      lens: 'T6',
      severity: 'P1',
      title: 'Race convert∥expire deixa reserva e live_item incoerentes',
      actor: 'seller JWT ×2',
      pre: 'accepted qty=1',
      repro: 'Future.wait convert ∥ expire',
      expected: 'um vencedor; item.sold iff reserva.converted',
      obtained: {
        'res': row,
        'item': li,
        'http': [raced[0].brief, raced[1].brief],
      },
    );
  } else {
    c.closed('T6-01', 'convert∥expire coerente', {'res': row, 'item': li}, lens: 'T6');
  }
}

Future<void> reproCheckoutAlien(Rtt c) async {
  final live = await c.insertLive();
  if (live == null) return;
  final item = await c.insertLiveItem(liveId: live, title: '$prefix alien2', qty: 2, price: 9);
  if (item == null) return;
  final rid = await c.insertReservation(liveId: live, liveItemId: item, jwt: c.buyerJwt);
  if (rid == null) return;
  await c.rpc('batata_process_live_reservation_request', {
    'p_request_id': rid,
    'p_action': 'accept',
  }, jwt: c.sellerJwt);
  final prod = await c.insertProduct(title: '$prefix alien-sku', qty: 2, price: 9);
  if (prod == null) return;
  final oid = await c.insertOrder(
    productId: prod,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
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
  c.note('T2.alien2', 'B2 PI com reservation B1 (order marketplace B2)', ck.brief, lens: 'T2');
  if (ck.ok) {
    c.hold(
      id: 'T2-04',
      lens: 'T2',
      severity: 'P1',
      title: 'Checkout B2 aceita reservation_request_id de B1',
      actor: 'buyer2 JWT',
      pre: 'reserva B1 accepted; order B2 marketplace',
      repro: 'POST create-payment-intent reservation_request_id=<B1>',
      expected: 'ignorar/recusar reservation de outro buyer',
      obtained: ck.brief,
    );
  } else {
    c.closed('T2-04', 'checkout alien reservation blocked', ck.brief, lens: 'T2');
  }
}
