/// T1/T2/T6 follow-up — facebook_manual convert, same-seller rebind, convert∥expire.
import 'dart:io';
import '_rtt.dart';

Future<void> main() async {
  final c = Rtt.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final live1 = await c.insertLive();
  final live2 = await c.insertLive(); // same seller

  final item = await c.insertLiveItem(
    liveId: live1!,
    title: '$prefix fb-only',
    qty: 1,
    price: 13,
  );
  final fb = await c.rest('POST', 'live_reservation_requests',
      jwt: c.sellerJwt,
      body: {
        'live_id': live1,
        'live_item_id': item,
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'requested_qty': 1,
        'source': 'facebook_manual',
        'status': 'accepted',
      });
  c.note('T1.fb.acc2', 'facebook_manual accepted live_only', fb.brief,
      lens: 'T1');
  if (fb.firstId != null) c.createdReservationIds.add(fb.firstId!);
  final conv = await c.processReservation(fb.firstId ?? '', 'convert',
      jwt: c.sellerJwt);
  final row = fb.firstId == null ? null : await c.reservationRow(fb.firstId!);
  final li = item == null ? null : await c.liveItemRow(item);
  c.note('T2.fb.convert2', 'convert facebook_manual live_only sem PI', {
    'rpc': conv.brief,
    'row': row,
    'item': li,
  }, lens: 'T2');
  if (row?['status'] == 'converted' || conv.map?['ok'] == true) {
    c.hold(
      id: 'T2-FB-CONVERT-NOPAY',
      lens: 'T2',
      severity: 'P1',
      title:
          'convert source=facebook_manual sem encomenda paga (TU só cobre fleaber_live)',
      actor: 'seller JWT',
      pre: 'live_only qty=1; facebook_manual accepted; zero PI',
      repro:
          'rpc batata_process_live_reservation_request action=convert',
      expected: 'convert_requires_paid_order também para facebook_manual',
      obtained: {'rpc': conv.json, 'row': row, 'item': li},
    );
  } else {
    c.closed('T2.fb.convert2', 'facebook_manual convert recusado', conv.brief,
        lens: 'T2');
  }

  // T6 convert∥expire on facebook_manual (convert can succeed)
  final itemR = await c.insertLiveItem(
    liveId: live1,
    title: '$prefix race-fb',
    qty: 1,
    price: 7,
  );
  final fbR = await c.rest('POST', 'live_reservation_requests',
      jwt: c.sellerJwt,
      body: {
        'live_id': live1,
        'live_item_id': itemR,
        'buyer_id': c.buyer2Id,
        'seller_id': c.sellerId,
        'requested_qty': 1,
        'source': 'facebook_manual',
        'status': 'accepted',
      });
  if (fbR.firstId != null) c.createdReservationIds.add(fbR.firstId!);
  final raced = await parallel([
    c.processReservation(fbR.firstId ?? '', 'convert', jwt: c.sellerJwt),
    c.processReservation(fbR.firstId ?? '', 'expire', jwt: c.sellerJwt),
  ]);
  final rr = fbR.firstId == null ? null : await c.reservationRow(fbR.firstId!);
  c.note('T6.fb.convert.expire', 'facebook_manual convert∥expire', {
    'c': raced[0].brief,
    'e': raced[1].brief,
    'row': rr,
  }, lens: 'T6');
  final cOk = raced[0].map?['ok'] == true;
  final eOk = raced[1].map?['ok'] == true;
  if (cOk && eOk) {
    c.hold(
      id: 'T6-FB-CONVERT-EXPIRE-BOTH-OK',
      lens: 'T6',
      severity: 'P1',
      title: 'facebook_manual convert∥expire ambos ok=true',
      actor: 'seller JWT paralelo',
      pre: 'facebook_manual accepted',
      repro: 'Future.wait convert ∥ expire',
      expected: 'um request_state_conflict',
      obtained: {
        'convert': raced[0].json,
        'expire': raced[1].json,
        'final': rr,
      },
    );
  } else {
    c.closed('T6.fb.convert.expire', 'race facebook_manual: um conflito ou um venceu',
        {'c': raced[0].json, 'e': raced[1].json, 'st': rr?['status']},
        lens: 'T6');
  }

  // Same-seller rebind live_id with pending (authority passes; immutability?)
  final itemM = await c.insertLiveItem(
    liveId: live1,
    title: '$prefix rebind-same',
    qty: 2,
    price: 6,
  );
  final pend = await c.insertReservation(
    liveId: live1,
    liveItemId: itemM,
    jwt: c.buyerJwt,
  );
  final reb = await c.patchLiveItem(
    itemM!,
    {'live_id': live2},
    jwt: c.sellerJwt,
  );
  final after = await c.liveItemRow(itemM);
  final pendRow = pend == null ? null : await c.reservationRow(pend);
  c.note('T1.rebind.same.seller', 'S1 move item live1→live2 com pending', {
    'patch': reb.brief,
    'item': after,
    'res': pendRow,
  }, lens: 'T1');
  if (after?['live_id']?.toString() == live2) {
    c.hold(
      id: 'T1-REBIND-SAME-SELLER-PENDING',
      lens: 'T1',
      severity: 'P1',
      title: 'Mesmo vendedor move live_item para outro live com reserva pending',
      actor: 'seller JWT',
      pre: 'dois lives do mesmo seller; reserva pending',
      repro: 'PATCH live_items.live_id=<live2>',
      expected: 'live_item_live_id_immutable',
      obtained: {'item': after, 'reservation': pendRow},
    );
  } else {
    c.closed('T1.rebind.same.seller', 'rebind mesmo seller bloqueado', reb.brief,
        lens: 'T1');
  }

  // T2: create-payment-intent mínimo
  final prod = await c.insertProduct(
    title: '$prefix pi',
    qty: 2,
    price: 12,
    listed: true,
    live: true,
  );
  final liPay = await c.insertLiveItem(
    liveId: live1,
    title: '$prefix pi item',
    price: 12,
    productId: prod,
  );
  final b2r = await c.insertReservation(
    liveId: live1,
    liveItemId: liPay,
    buyer: c.buyer2Id,
    jwt: c.buyer2Jwt,
  );
  await c.processReservation(b2r ?? '', 'accept', jwt: c.sellerJwt);
  final ord = await c.insertOrder(
    productId: prod!,
    jwt: c.buyerJwt,
    price: 12,
    liveId: live1,
    liveItemId: liPay,
    shipping: 'entrega em mão',
  );
  final pi = await c.edge('create-payment-intent', {
    'order_id': ord,
    'product_id': prod,
    'shipping_method': 'entrega em mão',
    'reservation_request_id': b2r,
  }, jwt: c.buyerJwt);
  c.note('T2.pi.b2res.b1order', 'PI B1 + reservation B2 (order alinhado)',
      pi.brief,
      lens: 'T2');
  final hasSess = pi.ok &&
      (pi.map?['url'] != null ||
          pi.map?['checkout_url'] != null ||
          pi.map?['session_id'] != null ||
          pi.map?['id'] != null);
  if (hasSess) {
    c.hold(
      id: 'T2-PI-B1-PAYS-B2-RESERVATION',
      lens: 'T2',
      severity: 'P1',
      title: 'B1 inicia checkout com reservation_request_id de B2',
      actor: 'buyer JWT',
      pre: 'order B1 no mesmo live_item; reserva accepted B2',
      repro:
          'POST create-payment-intent order_id=<B1> reservation_request_id=<B2>',
      expected: 'recusar reservation de outro buyer',
      obtained: pi.json is Map
          ? (pi.map!..remove('url')..remove('checkout_url'))
          : pi.brief,
    );
  } else {
    c.closed('T2.pi.b2res.b1order', 'PI não emitiu sessão com res B2', pi.brief,
        lens: 'T2');
  }

  await c.endLives();
  await dumpJson('${outDir()}/pass2b.json', {
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
  });
  stdout.writeln(
      'PASS2b findings=${c.findings.length} closed=${c.blocked.length}');
  exit(0);
}
