/// T1 / T7 — live reserva v2, staff, facebook_manual, qty race, 2.º actor.
/// Staging only. Não corrige.
import 'dart:io';
import '_rtt.dart';

Future<void> main() async {
  final c = Rtt.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final liveA = await c.insertLive();
  final liveB = await c.insertLive(seller: c.seller2Id);
  final prodA = await c.insertProduct(title: '$prefix T1-A', qty: 2, price: 11);
  final prodS2 = await c.insertProduct(
    title: '$prefix T1-S2',
    seller: c.seller2Id,
    qty: 3,
    price: 9,
  );
  final itemA = await c.insertLiveItem(
    liveId: liveA!,
    title: '$prefix itemA',
    qty: 1,
    price: 11,
    productId: prodA,
  );
  final itemA2 = await c.insertLiveItem(
    liveId: liveA,
    title: '$prefix itemA2 qty3',
    qty: 3,
    price: 12,
  );
  final itemB = await c.insertLiveItem(
    liveId: liveB!,
    title: '$prefix itemB',
    qty: 1,
    price: 9,
    productId: prodS2,
    seller: c.seller2Id,
  );

  // Fingerprint Q1
  final q1 = await c.insertReservation(
    liveId: liveB,
    liveItemId: itemA,
    jwt: c.buyerJwt,
    qty: 1,
  );
  if (q1 == null) {
    c.closed('T1.q1.mismatch', 'Q1 live_item∉live bloqueado', 'insert fail',
        lens: 'T1');
  } else {
    final row = await c.reservationRow(q1);
    if (row?['live_id']?.toString() == liveA) {
      c.closed('T1.q1.coalesce', 'Q1 coalesceu live_id para o item', row,
          lens: 'T1');
    } else if (row?['live_id']?.toString() == liveB) {
      c.hold(
        id: 'T1-Q1-BYPASS',
        lens: 'T1',
        severity: 'P0',
        title: 'Reserva com live_item de A e live_id de B persistiu',
        actor: 'buyer JWT',
        pre: 'itemA ∈ liveA; POST live_id=liveB',
        repro: 'POST live_reservation_requests live_item_id=<A> live_id=<B>',
        expected: 'live_item_live_mismatch ou coalescer para liveA',
        obtained: row,
      );
    }
  }

  // T1: facebook_manual accepted sem live_item_id
  final fbNull = await c.rest('POST', 'live_reservation_requests',
      jwt: c.sellerJwt,
      body: {
        'live_id': liveA,
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'requested_qty': 1,
        'source': 'facebook_manual',
        'status': 'accepted',
      });
  c.note('T1.fb.null_item', 'seller facebook_manual accepted sem live_item_id',
      fbNull.brief,
      lens: 'T1');
  if (fbNull.ok && fbNull.firstId != null) {
    c.createdReservationIds.add(fbNull.firstId!);
    final row = await c.reservationRow(fbNull.firstId!);
    if ((row?['status'] ?? '') == 'accepted' && row?['live_item_id'] == null) {
      c.hold(
        id: 'T1-FB-NULL-ITEM',
        lens: 'T1',
        severity: 'P1',
        title: 'facebook_manual accepted sem live_item_id (Q1 só valida item preenchido)',
        actor: 'seller JWT',
        pre: 'live A broadcasting',
        repro:
            'POST live_reservation_requests source=facebook_manual status=accepted sem live_item_id',
        expected: 'recusar ou forçar pending + item',
        obtained: row,
      );
    }
  }

  // T1: S1 anexa produto de S2 ao próprio live
  final hijackItem = await c.rest('POST', 'live_items', jwt: c.sellerJwt, body: {
    'live_id': liveA,
    'title': '$prefix hijack S2 product',
    'status': 'available',
    'is_active': true,
    'price': 9,
    'quantity': 1,
    'product_id': prodS2,
    'item_kind': 'catalog',
  });
  c.note('T1.s2product.on.s1live', 'S1 live_item com product_id de S2',
      hijackItem.brief,
      lens: 'T1');
  if (hijackItem.ok && hijackItem.firstId != null) {
    c.createdLiveItemIds.add(hijackItem.firstId!);
    c.hold(
      id: 'T1-LIVEITEM-ALIEN-PRODUCT',
      lens: 'T1',
      severity: 'P1',
      title: 'Vendedor A cola produto de S2 no próprio directo',
      actor: 'seller JWT',
      pre: 'prodS2.seller_id=S2; liveA.seller=S1',
      repro: 'POST live_items live_id=<A> product_id=<prodS2>',
      expected: 'live_item_product_seller_mismatch',
      obtained: hijackItem.map,
    );
  } else {
    c.closed('T1.alien.product', 'produto S2 no live S1 recusado',
        hijackItem.brief,
        lens: 'T1');
  }

  // T1: rebind live_id do item com reserva pending
  final pend = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA2,
    jwt: c.buyerJwt,
  );
  final rebind = await c.patchLiveItem(
    itemA2!,
    {'live_id': liveB},
    jwt: c.sellerJwt,
  );
  c.note('T1.rebind.pending', 'PATCH live_items.live_id com pending',
      rebind.brief,
      lens: 'T1');
  final itemAfter = await c.liveItemRow(itemA2);
  if (itemAfter?['live_id']?.toString() == liveB) {
    c.hold(
      id: 'T1-LIVEITEM-REBIND',
      lens: 'T1',
      severity: 'P1',
      title: 'live_item.live_id mudou de live com reserva pending',
      actor: 'seller JWT',
      pre: 'reserva pending no itemA2',
      repro: 'PATCH live_items live_id=<liveB> com reserva pending',
      expected: 'live_item_live_id_immutable ou recusar',
      obtained: {'patch': rebind.brief, 'row': itemAfter, 'pend': pend},
    );
  } else {
    c.closed('T1.rebind.pending', 'live_id imutável com pending/accepted',
        {'patch': rebind.brief, 'row': itemAfter},
        lens: 'T1');
  }

  // T1: rebind sem reserva activa (itemB)
  if (itemB == null) {
    c.note('T1.rebind.empty.skip', 'itemB insert falhou', 'skip', lens: 'T1');
  } else {
    final rebindEmpty = await c.patchLiveItem(
      itemB,
      {'live_id': liveA},
      jwt: c.seller2Jwt,
    );
    final itemBAfter = await c.liveItemRow(itemB);
    c.note('T1.rebind.empty', 'S2 PATCH live_id item sem reserva',
        {'patch': rebindEmpty.brief, 'row': itemBAfter},
        lens: 'T1');
    if (itemBAfter?['live_id']?.toString() == liveA) {
      c.hold(
        id: 'T1-LIVEITEM-REBIND-EMPTY',
        lens: 'T1',
        severity: 'P2',
        title: 'live_item.live_id móvel quando não há reserva activa',
        actor: 'seller2 JWT',
        pre: 'itemB sem reservas',
        repro: 'PATCH live_items.live_id para live de outro vendedor',
        expected: 'item fica no live do dono',
        obtained: itemBAfter,
      );
    }
  }

  // T1: qty seller INSERT accepted > stock
  final over = await c.rest('POST', 'live_reservation_requests',
      jwt: c.sellerJwt,
      body: {
        'live_id': liveA,
        'live_item_id': itemA ?? itemA2,
        'buyer_id': c.buyer2Id,
        'seller_id': c.sellerId,
        'requested_qty': 9,
        'source': 'fleaber_live',
        'status': 'accepted',
      });
  c.note('T1.over.qty', 'seller accepted qty=9 em item qty=1', over.brief,
      lens: 'T1');
  if (over.ok && over.firstId != null) {
    c.createdReservationIds.add(over.firstId!);
    final row = await c.reservationRow(over.firstId!);
    final q = row?['requested_qty'];
    if (q is num && q > 1) {
      c.hold(
        id: 'T1-SELLER-OVERQTY',
        lens: 'T1',
        severity: 'P1',
        title: 'Seller INSERT accepted com qty acima do stock do item',
        actor: 'seller JWT',
        pre: 'itemA qty=1',
        repro: 'POST live_reservation_requests status=accepted requested_qty=9',
        expected: 'qty_exceeds_stock',
        obtained: row,
      );
    } else {
      c.closed('T1.over.qty', 'qty cortada ou recusada', row, lens: 'T1');
    }
  } else {
    c.closed('T1.over.qty', 'INSERT over-qty recusado', over.brief, lens: 'T1');
  }

  // T7: staff helper B2 em S1
  final hid = await c.inviteHelper(helperId: c.buyer2Id!, seller: c.sellerId!);
  c.note('T1.staff.invite', 'B2 helper can_manage_reservations', hid,
      lens: 'T7');
  final staffAccept = await c.processReservation(
    (await c.insertReservation(
          liveId: liveA,
          liveItemId: itemA2,
          jwt: c.buyerJwt,
          qty: 1,
        )) ??
        '',
    'accept',
    jwt: c.buyer2Jwt,
  );
  c.note('T7.staff.accept', 'helper B2 accept reserva de B1', staffAccept.brief,
      lens: 'T7');

  // T1: facebook_manual convert sem PI
  final fbItem = await c.insertLiveItem(
    liveId: liveA,
    title: '$prefix fb convert',
    qty: 1,
    price: 15,
    productId: prodA,
  );
  final fbReq = await c.rest('POST', 'live_reservation_requests',
      jwt: c.sellerJwt,
      body: {
        'live_id': liveA,
        'live_item_id': fbItem,
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'requested_qty': 1,
        'source': 'facebook_manual',
        'status': 'accepted',
      });
  c.note('T1.fb.accepted', 'facebook_manual accepted no item', fbReq.brief,
      lens: 'T1');
  if (fbReq.firstId != null) c.createdReservationIds.add(fbReq.firstId!);
  final prodBefore = await c.productRow(prodA!);
  final convFb = await c.processReservation(fbReq.firstId ?? '', 'convert',
      jwt: c.sellerJwt);
  final fbRow = fbReq.firstId == null
      ? null
      : await c.reservationRow(fbReq.firstId!);
  final itemFb = fbItem == null ? null : await c.liveItemRow(fbItem);
  final prodAfter = await c.productRow(prodA);
  c.note('T1.fb.convert', 'convert facebook_manual sem order pago', {
    'rpc': convFb.brief,
    'res': fbRow,
    'item': itemFb,
    'product_qty_before': prodBefore?['quantity'],
    'product_qty_after': prodAfter?['quantity'],
  }, lens: 'T2');
  final convOk = convFb.map?['ok'] == true ||
      (fbRow?['status']?.toString() == 'converted');
  if (convOk) {
    c.hold(
      id: 'T1-FB-CONVERT-NOPAY',
      lens: 'T2',
      severity: 'P1',
      title: 'convert facebook_manual sem encomenda paga (TU só exige fleaber_live)',
      actor: 'seller JWT',
      pre: 'reserva facebook_manual accepted; zero PI',
      repro:
          'rpc batata_process_live_reservation_request action=convert source=facebook_manual',
      expected: 'convert_requires_paid_order ou equivalente',
      obtained: {
        'rpc': convFb.json,
        'reservation': fbRow,
        'item': itemFb,
        'product': prodAfter,
      },
      evidence: {
        'product_qty_delta': [
          prodBefore?['quantity'],
          prodAfter?['quantity'],
        ],
      },
    );
  } else {
    c.closed('T1.fb.convert', 'convert facebook_manual recusado sem pago',
        convFb.brief,
        lens: 'T2');
  }

  // T1: buyer chama convert
  final bPend = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA2,
    jwt: c.buyerJwt,
  );
  final bConv = await c.processReservation(bPend ?? '', 'convert',
      jwt: c.buyerJwt);
  c.note('T1.buyer.convert', 'buyer RPC convert', bConv.brief, lens: 'T2');
  if (bConv.map?['ok'] == true) {
    c.hold(
      id: 'T1-BUYER-CONVERT',
      lens: 'T2',
      severity: 'P1',
      title: 'Comprador converte reserva sem ser seller/staff',
      actor: 'buyer JWT',
      pre: 'reserva pending própria',
      repro: 'rpc batata_process_live_reservation_request action=convert',
      expected: 'not_allowed',
      obtained: bConv.json,
    );
  } else {
    c.closed('T1.buyer.convert', 'buyer convert bloqueado', bConv.brief,
        lens: 'T2');
  }

  // T1: inflate live_items.quantity
  final qtyTarget = itemA2 ?? itemA;
  final qtyPatch = qtyTarget == null
      ? null
      : await c.patchLiveItem(
          qtyTarget,
          {'quantity': 99},
          jwt: c.sellerJwt,
        );
  final itemQty =
      qtyTarget == null ? null : await c.liveItemRow(qtyTarget);
  c.note('T1.item.qty.inflate', 'PATCH live_items.quantity=99', {
    'patch': qtyPatch?.brief,
    'row': itemQty,
  }, lens: 'T4');
  if ((itemQty?['quantity'] is num) && (itemQty!['quantity'] as num) >= 99) {
    c.hold(
      id: 'T4-LIVEITEM-QTY-INFLATE',
      lens: 'T4',
      severity: 'P2',
      title: 'Seller inflaciona quantidade do live_item livremente',
      actor: 'seller JWT',
      pre: 'itemA qty original 1',
      repro: 'PATCH live_items quantity=99',
      expected: 'tecto / lock se reservas/encomendas activas',
      obtained: itemQty,
    );
  }

  // T6/T7: race accept B1 ∥ B2 em qty=1 item fresco
  final raceItem = await c.insertLiveItem(
    liveId: liveA,
    title: '$prefix race qty1',
    qty: 1,
    price: 8,
  );
  final r1 = await c.insertReservation(
    liveId: liveA,
    liveItemId: raceItem,
    jwt: c.buyerJwt,
  );
  final r2 = await c.insertReservation(
    liveId: liveA,
    liveItemId: raceItem,
    buyer: c.buyer2Id,
    jwt: c.buyer2Jwt,
  );
  final raced = await parallel([
    c.processReservation(r1 ?? '', 'accept', jwt: c.sellerJwt),
    c.processReservation(r2 ?? '', 'accept', jwt: c.sellerJwt),
  ]);
  final rr1 = r1 == null ? null : await c.reservationRow(r1);
  final rr2 = r2 == null ? null : await c.reservationRow(r2);
  final raceLi = raceItem == null ? null : await c.liveItemRow(raceItem);
  c.note('T6.accept.accept', 'race accept B1 ∥ B2 qty=1', {
    'h1': raced[0].brief,
    'h2': raced[1].brief,
    'r1': rr1,
    'r2': rr2,
    'item': raceLi,
  }, lens: 'T6');
  final acc = [rr1, rr2]
      .where((r) =>
          r != null &&
          (r['status'] == 'accepted' || r['status'] == 'converted'))
      .length;
  if (acc >= 2) {
    c.hold(
      id: 'T6-DOUBLE-ACCEPT',
      lens: 'T6',
      severity: 'P0',
      title: 'Duas reservas accepted no mesmo item qty=1 (race accept∥accept)',
      actor: 'seller JWT paralelo',
      pre: 'item qty=1; B1 e B2 pending',
      repro: 'Future.wait process accept B1 ∥ accept B2',
      expected: 'só uma accepted',
      obtained: {'r1': rr1, 'r2': rr2, 'item': raceLi},
    );
  } else {
    c.closed('T6.accept.accept', 'race accept: no máximo uma accepted',
        {'acc': acc, 'r1': rr1?['status'], 'r2': rr2?['status']},
        lens: 'T6');
  }

  await c.endLives();
  await dumpJson('${outDir()}/pass1.json', {
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'ids': {
      'liveA': liveA,
      'liveB': liveB,
      'itemA': itemA,
      'prodA': prodA,
      'prodS2': prodS2,
    },
  });
  stdout.writeln(
      'PASS1 findings=${c.findings.length} closed=${c.blocked.length}');
  exit(0);
}
