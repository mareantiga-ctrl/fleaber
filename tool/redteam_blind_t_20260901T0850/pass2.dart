/// T2 / T6 / T8 — convert, checkout live, reconcile alien, races, cross-pool.
/// Staging only. Não corrige.
import 'dart:io';
import '_rtt.dart';

Future<void> main() async {
  final c = Rtt.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final liveA = await c.insertLive();
  final prodA = await c.insertProduct(
    title: '$prefix T2-A',
    qty: 3,
    price: 14,
    listed: true,
    live: true,
  );
  final itemA = await c.insertLiveItem(
    liveId: liveA!,
    title: '$prefix T2 item',
    qty: 1,
    price: 14,
    productId: prodA,
    kind: 'marketplace_product',
  );

  // T2: stripe_convert JWT
  final pend = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA,
    jwt: c.buyerJwt,
  );
  final stripeConvBuyer = await c.rpc(
    'batata_live_reservation_stripe_convert',
    {'p_request_id': pend, 'p_order_id': null},
    jwt: c.buyerJwt,
  );
  c.note('T2.stripe_convert.buyer', 'buyer stripe_convert',
      stripeConvBuyer.brief,
      lens: 'T2');
  if (stripeConvBuyer.ok && stripeConvBuyer.map?['ok'] == true) {
    c.hold(
      id: 'T2-STRIPE-CONVERT-JWT',
      lens: 'T2',
      severity: 'P0',
      title: 'batata_live_reservation_stripe_convert executável por JWT sem PI',
      actor: 'buyer JWT',
      pre: 'reserva pending; sem order',
      repro: 'rpc batata_live_reservation_stripe_convert',
      expected: 'permission denied / só service_role',
      obtained: stripeConvBuyer.json,
    );
  } else {
    c.closed('T2.stripe_convert.buyer', 'stripe_convert revogado a authenticated',
        stripeConvBuyer.brief,
        lens: 'T2');
  }

  // T2: convert fleaber_live sem order pago
  final pend2 = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA,
    jwt: c.buyerJwt,
  );
  final acc = await c.processReservation(pend2 ?? '', 'accept',
      jwt: c.sellerJwt);
  c.note('T2.accept', 'accept fleaber_live', acc.brief, lens: 'T2');
  final convNoPay = await c.processReservation(pend2 ?? '', 'convert',
      jwt: c.sellerJwt);
  final pend2row = pend2 == null ? null : await c.reservationRow(pend2);
  c.note('T2.convert.nopay', 'convert fleaber_live sem PI', {
    'rpc': convNoPay.brief,
    'row': pend2row,
  }, lens: 'T2');
  if (pend2row?['status'] == 'converted' || convNoPay.map?['ok'] == true) {
    c.hold(
      id: 'T2-CONVERT-NOPAY-FLEABER',
      lens: 'T2',
      severity: 'P0',
      title: 'convert fleaber_live sem encomenda paga capturada',
      actor: 'seller JWT',
      pre: 'reserva accepted; zero order/PI',
      repro: 'rpc batata_process_live_reservation_request action=convert',
      expected: 'convert_requires_paid_order',
      obtained: {'rpc': convNoPay.json, 'row': pend2row},
    );
  } else {
    c.closed('T2.convert.nopay', 'convert fleaber_live exige pago',
        convNoPay.brief,
        lens: 'T2');
  }

  // T6: convert ∥ expire (verbos ≠ Q)
  final raceItem = await c.insertLiveItem(
    liveId: liveA,
    title: '$prefix conv-exp',
    qty: 1,
    price: 10,
  );
  final raceReq = await c.insertReservation(
    liveId: liveA,
    liveItemId: raceItem,
    jwt: c.buyerJwt,
  );
  await c.processReservation(raceReq ?? '', 'accept', jwt: c.sellerJwt);
  final ce = await parallel([
    c.processReservation(raceReq ?? '', 'convert', jwt: c.sellerJwt),
    c.processReservation(raceReq ?? '', 'expire', jwt: c.sellerJwt),
  ]);
  final ceRow = raceReq == null ? null : await c.reservationRow(raceReq);
  c.note('T6.convert.expire', 'race convert∥expire', {
    'c': ce[0].brief,
    'e': ce[1].brief,
    'row': ceRow,
  }, lens: 'T6');
  // Ambos ok=true com estados contraditórios = finding
  final bothOk = ce[0].map?['ok'] == true && ce[1].map?['ok'] == true;
  if (bothOk &&
      ceRow != null &&
      (ceRow['status'] == 'converted' || ceRow['status'] == 'expired')) {
    c.note('T6.convert.expire.winner', 'um venceu; outro deveria conflict',
        {'status': ceRow['status'], 'both_ok': bothOk},
        lens: 'T6');
    if (ce[0].map?['ok'] == true &&
        ce[1].map?['ok'] == true &&
        ce[0].map?['error'] == null &&
        ce[1].map?['error'] == null) {
      c.hold(
        id: 'T6-CONVERT-EXPIRE-BOTH-OK',
        lens: 'T6',
        severity: 'P1',
        title: 'convert∥expire ambos ok=true (estado final único mas ACK duplo)',
        actor: 'seller JWT paralelo',
        pre: 'reserva accepted',
        repro: 'Future.wait convert ∥ expire',
        expected: 'um request_state_conflict',
        obtained: {
          'convert': ce[0].json,
          'expire': ce[1].json,
          'final': ceRow,
        },
      );
    }
  }

  // T2: create-payment-intent com reservation_request_id de B2, JWT B1
  final itemPay = await c.insertLiveItem(
    liveId: liveA,
    title: '$prefix pay hijack',
    qty: 1,
    price: 16,
    productId: prodA,
  );
  final b2res = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemPay,
    buyer: c.buyer2Id,
    jwt: c.buyer2Jwt,
  );
  await c.processReservation(b2res ?? '', 'accept', jwt: c.sellerJwt);
  final b1ord = await c.insertOrder(
    productId: prodA!,
    jwt: c.buyerJwt,
    price: 16,
    liveId: liveA,
    liveItemId: itemPay,
  );
  final piHijack = await c.edge('create-payment-intent', {
    'order_id': b1ord,
    'live_id': liveA,
    'live_item_id': itemPay,
    'reservation_request_id': b2res,
    'shipping_method': 'entrega em mão',
    'is_live': true,
  }, jwt: c.buyerJwt);
  c.note('T2.pi.alien.reservation', 'B1 PI com reservation_request_id de B2',
      piHijack.brief,
      lens: 'T2');
  final piUrl = piHijack.map?['url'] ??
      piHijack.map?['checkout_url'] ??
      piHijack.map?['session_id'];
  if (piHijack.ok && piUrl != null) {
    c.hold(
      id: 'T2-PI-ALIEN-RESERVATION',
      lens: 'T2',
      severity: 'P1',
      title: 'Checkout B1 aceita reservation_request_id de B2',
      actor: 'buyer JWT',
      pre: 'B2 accepted no item; B1 cria order+PI',
      repro:
          'POST create-payment-intent reservation_request_id=<B2> order_id=<B1>',
      expected: 'recusar reservation que não é do buyer',
      obtained: {
        'status': piHijack.status,
        'keys': piHijack.map?.keys.toList(),
        'has_url': piUrl != null,
      },
    );
  } else {
    c.closed('T2.pi.alien.reservation', 'PI recusou reservation alheia ou falhou',
        piHijack.brief,
        lens: 'T2');
  }

  // T2/T8: reconcile — order pago marketplace converte reserva live de B2
  final paid = await c.setupPaidStripe();
  final paidOid = paid['order_id'];
  final hijackItem = await c.insertLiveItem(
    liveId: liveA,
    title: '$prefix reconcile hijack',
    qty: 1,
    price: 20,
  );
  final b2live = await c.insertReservation(
    liveId: liveA,
    liveItemId: hijackItem,
    buyer: c.buyer2Id,
    jwt: c.buyer2Jwt,
  );
  await c.processReservation(b2live ?? '', 'accept', jwt: c.sellerJwt);
  final w0 = await c.wallets();
  final rec = await c.rpc(
    'batata_live_reconcile_stripe_order',
    {
      'p_order_id': paidOid,
      'p_reservation_request_id': b2live,
    },
    jwt: c.buyerJwt,
  );
  final b2after = b2live == null ? null : await c.reservationRow(b2live);
  final hijackAfter =
      hijackItem == null ? null : await c.liveItemRow(hijackItem);
  final paidAfter = paidOid == null ? null : await c.orderRow(paidOid);
  final w1 = await c.wallets();
  c.note('T2.reconcile.alien', 'reconcile order B1 pago → reserva B2', {
    'rpc': rec.brief,
    'b2': b2after,
    'item': hijackAfter,
    'order': {
      'id': paidOid,
      'live_item_id': paidAfter?['live_item_id'],
      'live_id': paidAfter?['live_id'],
      'status': paidAfter?['status'],
    },
    'wallets': {'before': w0, 'after': w1},
  }, lens: 'T2');
  if (b2after?['status'] == 'converted' || rec.map?['ok'] == true) {
    c.hold(
      id: 'T2-RECONCILE-ALIEN-REQUEST',
      lens: 'T8',
      severity: 'P0',
      title:
          'Order Stripe pago de B1 converte reserva live de B2 (reconcile sem match buyer/item)',
      actor: 'buyer JWT',
      pre: 'B1 setup_paid_order marketplace; B2 accepted noutro live_item',
      repro:
          'rpc batata_live_reconcile_stripe_order p_order_id=<pago B1> p_reservation_request_id=<B2>',
      expected: 'não converter reserva de outro buyer/item',
      obtained: {
        'rpc': rec.json,
        'b2_reservation': b2after,
        'live_item': hijackAfter,
        'order': paidAfter,
      },
      evidence: {
        'wallets_before': w0,
        'wallets_after': w1,
        'pi': paid['pi'],
      },
    );
  } else {
    c.closed('T2.reconcile.alien', 'reconcile recusou reservation alheia',
        rec.brief,
        lens: 'T2');
  }

  // T2: seller reconcile no mesmo
  final recS = await c.rpc(
    'batata_live_reconcile_stripe_order',
    {
      'p_order_id': paidOid,
      'p_reservation_request_id': b2live,
    },
    jwt: c.sellerJwt,
  );
  c.note('T2.reconcile.seller', 'seller reconcile alien', recS.brief,
      lens: 'T2');

  // T4/T8 cross-pool: produto marketplace + live, vender marketplace (já pago)
  // e ainda aceitar/convert live no mesmo product_id
  final crossProd = await c.insertProduct(
    title: '$prefix cross-pool',
    qty: 1,
    price: 18,
    listed: true,
    live: true,
  );
  final crossItem = await c.insertLiveItem(
    liveId: liveA,
    title: '$prefix cross live',
    qty: 1,
    price: 18,
    productId: crossProd,
    kind: 'marketplace_product',
  );
  final paid2 = await c.e2e('setup_paid_order', {
    'initial_qty': 1,
  });
  // setup_paid cria produto NOVO — ligar manualmente: usar o produto cross
  // via order JWT no produto catalog (não o e2e). Order unpaid + live res.
  final mktOrd = await c.insertOrder(
    productId: crossProd!,
    jwt: c.buyerJwt,
    price: 18,
    qty: 1,
  );
  final liveRes = await c.insertReservation(
    liveId: liveA,
    liveItemId: crossItem,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  await c.processReservation(liveRes ?? '', 'accept', jwt: c.sellerJwt);
  final pCross = await c.productRow(crossProd);
  final liCross = crossItem == null ? null : await c.liveItemRow(crossItem);
  c.note('T8.crosspool.snapshot', 'mesmo product: order B1 + reserva B2 accepted',
      {
        'order': mktOrd,
        'res': liveRes,
        'product': pCross,
        'item': liCross,
        'e2e_extra': paid2.brief,
      },
      lens: 'T8');

  await c.endLives();
  await dumpJson('${outDir()}/pass2.json', {
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'paid': paid,
  });
  stdout.writeln(
      'PASS2 findings=${c.findings.length} closed=${c.blocked.length}');
  exit(0);
}
