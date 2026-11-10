/// REDTEAM_BLIND_BT_LIVE_POS_BLBQ_v1 — pass1 FOMO / convert / broadcast.
/// Staging only. No fixes.
import 'dart:io';

import '_rtbt.dart';

Future<void> main() async {
  final c = Rtbt.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureHelperChatOnly();

  final liveId = await c.createLive(title: '$prefix p1');
  final sku = await c.createProduct(title: '$prefix p1 sku', qty: 1, live: true);
  if (liveId == null || sku == null) {
    stderr.writeln('fixture live/sku fail');
    exit(4);
  }
  final itemId = await c.createLiveItem(
    liveId: liveId,
    title: '$prefix p1 item',
    ref: 'RTBT-P1A',
    kind: 'live_only',
    checkoutProductId: sku,
    quantity: 1,
  );
  if (itemId == null) {
    stderr.writeln('fixture item fail ${c.notes}');
    await c.endAllCreatedLives();
    exit(4);
  }

  Future<void> tryFomo({
    required String id,
    required String lens,
    required String body,
    required String? jwt,
    required String actor,
    bool exactClosed = false,
  }) async {
    final h = await c.rpc(
      'batata_live_system_message',
      {
        'p_live_id': liveId,
        'p_body': body,
        'p_sender_label': 'Sistema',
      },
      jwt: jwt,
    );
    final ok = h.map?['ok'] == true;
    final err = h.map?['error']?.toString() ?? h.brief;
    if (ok) {
      if (exactClosed) {
        c.note(id, 'persistiu (exacto BN/BH, não contar)', h.brief, lens: lens);
      } else {
        c.hold(
          id: id,
          lens: lens,
          severity: 'P2',
          title: 'FOMO anúncio de compra persistiu: $body',
          actor: actor,
          pre: 'denylist BLBQ sem este sinónimo',
          repro: 'rpc batata_live_system_message p_body=$body',
          expected: 'ok=false purchase_announce_via_broadcast_only',
          obtained: h.brief,
          evidence: {'body': body, 'rpc': h.map},
        );
      }
    } else {
      if (exactClosed) {
        c.block(id, lens, 'exacto BN/BH recusado (não contar)', err);
      } else {
        c.block(id, lens, 'sinónimo recusado', err);
      }
    }
  }

  // Exactos BN/BH — provar HOLD, não contar.
  await tryFomo(
    id: 'p1.fomo.claimed',
    lens: 'BT2',
    body: 'claimed',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    exactClosed: true,
  );
  await tryFomo(
    id: 'p1.fomo.snapup',
    lens: 'BT2',
    body: 'snap up',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    exactClosed: true,
  );
  await tryFomo(
    id: 'p1.fomo.levou',
    lens: 'BT2',
    body: 'Ana levou',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    exactClosed: true,
  );
  await tryFomo(
    id: 'p1.fomo.sold',
    lens: 'BT2',
    body: 'sold',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    exactClosed: true,
  );

  // Novos sinónimos (contar se persistirem).
  for (final row in [
    ['gone', 'gone'],
    ['itsmine', "it's mine"],
    ['esgotado', 'esgotado'],
    ['itsmine2', 'its mine'],
    ['gonebang', 'GONE!'],
    ['taken', "that's mine"],
    ['out', 'out of stock'],
    ['lastone', 'last one gone'],
    ['esgotada', 'esgotada'],
    ['acabou', 'acabou'],
    ['noest', 'no stock'],
  ]) {
    await tryFomo(
      id: 'p1.fomo.${row[0]}',
      lens: 'BT2',
      body: row[1],
      jwt: c.sellerJwt,
      actor: 'seller JWT',
    );
  }

  // Helper só can_manage_chat — mesmo poço FOMO.
  await tryFomo(
    id: 'p1.fomo.helper.esgotado',
    lens: 'BT2',
    body: 'esgotado',
    jwt: c.helperJwt,
    actor: 'helper can_manage_chat JWT',
  );
  await tryFomo(
    id: 'p1.fomo.helper.gone',
    lens: 'BT2',
    body: 'gone',
    jwt: c.helperJwt,
    actor: 'helper can_manage_chat JWT',
  );

  // Buyer não deve anunciar via system RPC.
  final buyerSys = await c.rpc(
    'batata_live_system_message',
    {'p_live_id': liveId, 'p_body': 'esgotado', 'p_sender_label': 'Sistema'},
    jwt: c.buyerJwt,
  );
  if (buyerSys.map?['ok'] == true) {
    c.hold(
      id: 'p1.fomo.buyer.system',
      lens: 'BT2',
      severity: 'P1',
      title: 'Buyer JWT enviou system FOMO',
      actor: 'buyer JWT',
      pre: 'accept_broadcast/system só seller/staff',
      repro: 'rpc batata_live_system_message como buyer',
      expected: 'ok=false not_allowed',
      obtained: buyerSys.brief,
    );
  } else {
    c.block('p1.fomo.buyer.system', 'BT2', 'buyer system recusado', buyerSys.brief);
  }

  // INSERT directo kind=system (RLS deve recusar).
  final insSys = await c.rest('POST', 'live_messages', jwt: c.buyerJwt, body: {
    'live_id': liveId,
    'user_id': c.buyerId,
    'kind': 'system',
    'body': 'esgotado',
    'sender_label': 'Sistema',
  });
  if (insSys.ok && insSys.firstId != null) {
    c.hold(
      id: 'p1.fomo.buyer.insert.system',
      lens: 'BT2',
      severity: 'P1',
      title: 'Buyer INSERT live_messages kind=system',
      actor: 'buyer JWT',
      pre: 'policy insert só kind=chat',
      repro: 'POST live_messages kind=system',
      expected: '403/RLS',
      obtained: insSys.brief,
    );
  } else {
    c.block('p1.fomo.buyer.insert.system', 'BT2', 'INSERT system recusado',
        insSys.brief);
  }

  // BT1 — purchase_broadcast sem PI.
  final pbBuyer = await c.rpc(
    'batata_live_purchase_broadcast',
    {
      'p_live_id': liveId,
      'p_buyer_id': c.buyerId,
      'p_live_item_id': itemId,
    },
    jwt: c.buyerJwt,
  );
  final pbSeller = await c.rpc(
    'batata_live_purchase_broadcast',
    {
      'p_live_id': liveId,
      'p_buyer_id': c.buyerId,
      'p_live_item_id': itemId,
    },
    jwt: c.sellerJwt,
  );
  for (final row in [
    ['buyer', pbBuyer],
    ['seller', pbSeller],
  ]) {
    final h = row[1] as HttpHit;
    final persisted = h.json == true || h.map?['ok'] == true;
    if (persisted) {
      c.hold(
        id: 'p1.broadcast.${row[0]}.nopi',
        lens: 'BT1',
        severity: 'P1',
        title: 'purchase_broadcast sem order paga (${row[0]})',
        actor: '${row[0]} JWT',
        pre: 'sem PI / amount_paid',
        repro: 'rpc batata_live_purchase_broadcast',
        expected: 'false',
        obtained: h.brief,
      );
    } else {
      c.block('p1.broadcast.${row[0]}.nopi', 'BT1',
          'broadcast sem PI recusado', h.brief);
    }
  }

  // Mensagem «comprou» persistida?
  final msgs = await c.rest(
    'GET',
    'live_messages?live_id=eq.$liveId&kind=eq.system&select=id,body,user_id,created_at&order=created_at.desc&limit=20',
    service: true,
  );
  c.note('p1.msgs.system', 'system messages após probes', msgs.brief, lens: 'BT1');

  // BT1 — accept_broadcast buyer (exacto BN — não contar se recusar).
  final accBuyer = await c.rpc(
    'batata_live_reservation_accept_broadcast',
    {
      'p_live_id': liveId,
      'p_buyer_id': c.buyerId,
      'p_live_item_id': itemId,
      'p_requested_qty': 1,
    },
    jwt: c.buyerJwt,
  );
  if (accBuyer.json == true) {
    c.hold(
      id: 'p1.accept_broadcast.buyer',
      lens: 'BT1',
      severity: 'P2',
      title: 'Buyer JWT accept_broadcast true (regressão BN)',
      actor: 'buyer JWT',
      pre: 'BLBQ: só seller/staff',
      repro: 'rpc batata_live_reservation_accept_broadcast buyer',
      expected: 'false',
      obtained: accBuyer.brief,
    );
  } else {
    c.block('p1.accept_broadcast.buyer', 'BT1',
        'buyer accept_broadcast recusado (exacto, não contar)', accBuyer.brief);
  }

  // Reserva pending + accept seller, depois convert sem PI.
  final rid = await c.insertReservation(
    liveId: liveId,
    liveItemId: itemId,
    jwt: c.buyerJwt,
    buyer: c.buyerId,
  );
  if (rid != null) {
    final acc = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$rid',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    c.note('p1.accept.seller', 'seller PATCH accepted', acc.brief, lens: 'BT1');

    final convRpc = await c.rpc(
      'batata_live_reservation_stripe_convert',
      {'p_request_id': rid},
      jwt: c.sellerJwt,
    );
    final convOk = convRpc.map?['ok'] == true;
    final afterConv = await c.rest(
      'GET',
      'live_reservation_requests?id=eq.$rid&select=id,status,notes',
      service: true,
    );
    final st = afterConv.map?['status']?.toString();
    if (convOk && st == 'converted') {
      c.hold(
        id: 'p1.convert.seller.nopi',
        lens: 'BT1',
        severity: 'P0',
        title: 'stripe_convert sem PI deixou status=converted',
        actor: 'seller JWT',
        pre: 'reserva accepted, sem order paga',
        repro: 'rpc batata_live_reservation_stripe_convert',
        expected: 'ok=false / convert_requires_paid_order; status≠converted',
        obtained: {'rpc': convRpc.brief, 'row': afterConv.map},
      );
    } else {
      c.block('p1.convert.seller.nopi', 'BT1', 'convert sem PI recusado',
          {'rpc': convRpc.brief, 'status': st});
    }

    final convBuyer = await c.rpc(
      'batata_live_reservation_stripe_convert',
      {'p_request_id': rid},
      jwt: c.buyerJwt,
    );
    final afterB = await c.rest(
      'GET',
      'live_reservation_requests?id=eq.$rid&select=id,status',
      service: true,
    );
    if (convBuyer.map?['ok'] == true && afterB.map?['status'] == 'converted') {
      c.hold(
        id: 'p1.convert.buyer.nopi',
        lens: 'BT1',
        severity: 'P0',
        title: 'Buyer stripe_convert sem PI',
        actor: 'buyer JWT',
        pre: 'accepted sem order',
        repro: 'rpc batata_live_reservation_stripe_convert buyer',
        expected: 'recusa',
        obtained: {'rpc': convBuyer.brief, 'row': afterB.map},
      );
    } else {
      c.block('p1.convert.buyer.nopi', 'BT1', 'buyer convert recusado',
          convBuyer.brief);
    }

    final patchConv = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$rid',
      jwt: c.sellerJwt,
      body: {'status': 'converted'},
    );
    final afterP = await c.rest(
      'GET',
      'live_reservation_requests?id=eq.$rid&select=id,status',
      service: true,
    );
    if (patchConv.ok && afterP.map?['status'] == 'converted') {
      c.hold(
        id: 'p1.patch.converted.nopi',
        lens: 'BT1',
        severity: 'P0',
        title: 'PATCH converted sem order paga',
        actor: 'seller JWT',
        pre: 'accepted, sem PI',
        repro: 'PATCH live_reservation_requests status=converted',
        expected: 'convert_requires_paid_order',
        obtained: {'patch': patchConv.brief, 'row': afterP.map},
      );
    } else {
      c.block('p1.patch.converted.nopi', 'BT8', 'PATCH converted recusado',
          patchConv.brief);
    }

    // Reconcile com order não paga.
    final fakeOrder = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': sku,
      'live_id': liveId,
      'live_item_id': itemId,
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
          'p_reservation_request_id': rid,
        },
        jwt: c.sellerJwt,
      );
      final afterR = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$rid&select=id,status',
        service: true,
      );
      if (rec.map?['ok'] == true && afterR.map?['status'] == 'converted') {
        c.hold(
          id: 'p1.reconcile.unpaid',
          lens: 'BT8',
          severity: 'P0',
          title: 'reconcile converteu reserva com order não paga',
          actor: 'seller JWT',
          pre: 'order pendente sem PI',
          repro: 'rpc batata_live_reconcile_stripe_order',
          expected: 'order_not_captured / order_not_paid',
          obtained: {'rpc': rec.brief, 'row': afterR.map},
        );
      } else {
        c.block('p1.reconcile.unpaid', 'BT8', 'reconcile unpaid recusado',
            rec.brief);
      }
    } else {
      c.note('p1.order.unpaid.fail', 'INSERT order pendente', fakeOrder.brief,
          lens: 'BT8');
    }
  }

  await c.endAllCreatedLives();
  await dumpJson('${outDir()}/pass1.json', {
    'prefix': prefix,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
    'live_id': liveId,
    'item_id': itemId,
  });
  stdout.writeln(
      'PASS1 done findings=${c.findings.length} blocked=${c.blocked.length}');
}
