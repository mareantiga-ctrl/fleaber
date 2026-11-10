/// PASS 6 — loot da reserva cruzada: convert + checkout Stripe no item de S1.
import 'dart:io';

import '_rtq.dart';

void main() async {
  final env = loadEnv();
  final c = Rtq.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.wallets();

  final liveA = await c.insertLive(seller: c.sellerId, active: true);
  final liveB = await c.insertLive(seller: c.seller2Id, active: true);
  final itemA = await c.insertLiveItem(
    liveId: liveA ?? '',
    title: '$prefix p6 itemA',
    qty: 5,
    price: 12,
  );
  c.note('p6.fix', 'lives', {
    'liveA': liveA,
    'liveB': liveB,
    'itemA': itemA,
    'item': await c.liveItemRow(itemA ?? ''),
  }, lens: 'Q8');

  final pend = await c.rest('POST', 'live_reservation_requests', jwt: c.buyerJwt, body: {
    'live_id': liveB,
    'live_item_id': itemA,
    'buyer_id': c.buyerId,
    'requested_qty': 1,
    'status': 'pending',
    'source': 'fleaber_live',
  });
  final rid = pend.firstId;
  c.note('p6.pend', 'pending', pend.brief, lens: 'Q1');
  HttpHit? acc;
  if (rid != null) {
    acc = await c.rpc('batata_process_live_reservation_request', {
      'p_request_id': rid,
      'p_action': 'accept',
    }, jwt: c.seller2Jwt);
    c.note('p6.accept', 'S2 accept', acc.brief, lens: 'Q1');
    c.note('p6.row.after.accept', 'reserva', await c.reservationRow(rid),
        lens: 'Q1');
    c.note('p6.item.after.accept', 'item A', await c.liveItemRow(itemA ?? ''),
        lens: 'Q1');

    final conv = await c.rpc('batata_process_live_reservation_request', {
      'p_request_id': rid,
      'p_action': 'convert',
    }, jwt: c.seller2Jwt);
    c.note('p6.convert', 'S2 convert', conv.brief, lens: 'Q8');
    final rowC = await c.reservationRow(rid);
    if (rowC?['status'] == 'converted') {
      c.hold(
        id: 'RTQ-Q8-convert-foreign-item',
        lens: 'Q8',
        severity: 'P0',
        title: 'S2 converte stock do artigo de S1 sem pagar',
        actor: 'seller2 JWT',
        pre: 'accept cruzado live_id B / item A',
        repro: 'rpc process convert',
        expected: 'convert recusado — item não é da live B',
        obtained: {'row': rowC, 'item': await c.liveItemRow(itemA ?? '')},
      );
    }
  }

  // Checkout no item A com live_id B (se accept ficou accepted)
  final ck = await c.edge('create-payment-intent', {
    'buyer_id': c.buyerId,
    'amount': 1200,
    'live_id': liveB,
    'live_item_id': itemA,
    'seller_id': c.seller2Id,
    'shipping_method': 'mao',
  }, jwt: c.buyerJwt);
  c.note('p6.checkout.cross', 'PI no item A via live B / seller S2', ck.brief,
      lens: 'Q8');
  final sid = ck.map?['checkoutSessionId'] ?? ck.map?['client_secret'];
  if (ck.ok && sid != null) {
    c.hold(
      id: 'RTQ-Q8-checkout-s2-on-s1-live-item',
      lens: 'Q8',
      severity: 'P0',
      title: 'Checkout Stripe do artigo de S1 cobrado como venda de S2',
      actor: 'buyer JWT + seller2',
      pre: 'reserva cruzada accepted',
      repro:
          'POST create-payment-intent live_item_id=<itemA> live_id=<B> seller_id=<S2>',
      expected: 'seller da live_item / recusa',
      obtained: ck.brief,
      evidence: {
        'session': sid,
        'amount': ck.map?['amount_total'] ?? ck.map?['server_amount_cents'],
      },
    );
  }

  await c.endLives();
  await dumpJson('${outDir()}/pass6.json', {
    'notes': c.notes,
    'findings': c.findings,
    'w0': w0,
    'wEnd': await c.wallets(),
  });
  stdout.writeln('PASS6 findings=${c.findings.length}');
  exit(0);
}
