import 'dart:io';

import '_rtak.dart';

/// Pass 3 — 23514 diagnosis, REST vs Hub reserved_full, tip settle, live_only item.
void main() async {
  final c = Rtak.fromEnv(loadEnv());
  await c.loginActors();

  const endedPub = '7148ec4f-395d-476e-9ba5-bdee9a6738b2';
  const reservedFullItem = '386a1d58-8834-4731-9f8e-c24aeda8c95f';
  const sku = 'e1369e47-7985-43d1-874d-326ae2d6930b';
  const tipCs =
      'cs_test_a1dDiPJUomxH9P8xUrgLOhO2cwUPXKfHncYbn1TUcIMXZpFvfBSbXMsuLO';

  final out = <String, Object?>{'pass': 3, 'stamp': stamp};

  // Full 23514 on marketplace hitch
  final live = await c.insertLive(
    seller: c.sellerId,
    status: 'live',
    active: true,
    muxPlayback: 'rtak_p3_live_$stamp',
    title: '$prefix p3-live',
  );

  String? lastItemId;
  Future<void> tryItem(String tag, Map<String, dynamic> body) async {
    final h = await c.rest('POST', 'live_items', service: true, body: body);
    c.note('p3.item.$tag', tag, h.brief, lens: 'AK7');
    out['item_$tag'] = '${h.status} ${h.body}';
    final id = h.firstId;
    if (id != null) {
      c.createdLiveItemIds.add(id);
      lastItemId = id;
    }
  }

  if (live != null) {
    await tryItem('mp_full', {
      'live_id': live,
      'seller_id': c.sellerId,
      'title': '$prefix p3-mp',
      'status': 'available',
      'is_active': true,
      'price': 5,
      'quantity': 2,
      'item_kind': 'marketplace_product',
      'product_id': sku,
      'ref_code': 'RTAKP3A',
    });
    await tryItem('live_only', {
      'live_id': live,
      'seller_id': c.sellerId,
      'title': '$prefix p3-lo',
      'status': 'available',
      'is_active': true,
      'price': 5,
      'quantity': 2,
      'item_kind': 'live_only',
      'ref_code': 'RTAKP3B',
    });
    await tryItem('no_kind', {
      'live_id': live,
      'seller_id': c.sellerId,
      'title': '$prefix p3-nk',
      'status': 'available',
      'is_active': true,
      'price': 5,
      'quantity': 1,
      'ref_code': 'RTAKP3C',
    });
  }

  // REST live_items reserved_full as buyer vs seller vs anon
  final restB = await c.rest(
    'GET',
    'live_items?id=eq.$reservedFullItem&select=id,price,status,quantity,is_active',
    jwt: c.buyerJwt,
  );
  final restS = await c.rest(
    'GET',
    'live_items?id=eq.$reservedFullItem&select=id,price,status,quantity',
    jwt: c.sellerJwt,
  );
  final restA = await c.rest(
    'GET',
    'live_items?id=eq.$reservedFullItem&select=id,price,status',
  );
  c.note('p3.rest_rf', 'REST reserved_full B/S/anon',
      'B=${restB.brief} S=${restS.brief} A=${restA.brief}',
      lens: 'AK1');
  out['rest_rf'] = {
    'buyer': restB.brief,
    'seller': restS.brief,
    'anon': restA.brief,
  };
  if (restB.list.isNotEmpty) {
    c.finding(
      id: 'RTAK-AK1-REST-RESERVED-FULL',
      lens: 'AK1',
      severity: 'P2',
      title: 'Buyer REST ainda vê reserved_full (AEAFAG deveria esconder)',
      actor: 'buyer JWT',
      pre: 'status=reserved_full',
      repro: 'GET live_items?id=',
      expected: '[]',
      obtained: restB.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK1-REST-RESERVED-FULL',
      lens: 'AK1',
      title: 'REST buyer esconde reserved_full; Hub JWT ainda mostra',
      actor: 'buyer JWT',
      pre: 'reserved_full',
      repro: 'GET live_items',
      expected: '[]',
      obtained: restB.brief,
    );
  }

  // FOMO still after pass2
  final fomo = await c.rpc('batata_hub_live_fomo_snapshot', {
    'p_live_id': endedPub,
  });
  c.note('p3.fomo', 'FOMO ended still', fomo.brief, lens: 'AK1');
  out['fomo'] = fomo.map;

  // Tip settle unpaid
  final settle = await c.edge(
    'create-live-tip-checkout',
    method: 'GET',
    qs: '?checkout_return=success&session_id=$tipCs',
    extra: {'Origin': 'https://evil.com'},
  );
  c.note('p3.tip_settle', 'GET tip settle unpaid', settle.brief, lens: 'AK3');
  out['tip_settle'] = settle.brief;
  final tips = await c.rest(
    'GET',
    'live_tips?stripe_session_id=eq.$tipCs&select=id,status,amount,buyer_id,seller_id,live_id',
    service: true,
  );
  c.note('p3.tip_row', 'live_tips after GET settle', tips.brief, lens: 'AK3');
  out['tip_row'] = tips.snippet;
  final st = (tips.map?['status'] ?? '').toString().toLowerCase();
  if (st == 'paid' ||
      st == 'settled' ||
      settle.body.toLowerCase().contains('pagamento recebido')) {
    c.finding(
      id: 'RTAK-AK3-TIP-SETTLE-CREDIT',
      lens: 'AK3',
      severity: 'P0',
      title: 'GET settle gorjeta unpaid creditou',
      actor: 'anon',
      pre: 'Session created on ended live, unpaid',
      repro: 'GET create-live-tip-checkout?session_id=',
      expected: 'pending / não confirmado',
      obtained: 'settle=${settle.brief} row=${tips.snippet}',
    );
  } else {
    c.hold(
      id: 'RTAK-AK3-TIP-SETTLE-UNPAID',
      lens: 'AK3',
      title: 'Session gorjeta created ≠ captura (GET settle unpaid)',
      actor: 'anon',
      pre: 'cs unpaid',
      repro: 'GET tip settle',
      expected: 'pending',
      obtained: 'http=${settle.brief} status=$st',
    );
  }

  // If live_only item created, try order without product then PI
  final loId = lastItemId;
  if (loId != null && live != null) {
    await c.rest('PATCH', 'lives?id=eq.$live', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
    final orderIns = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'live_item_id': loId,
      'live_id': live,
      'quantity': 1,
      'status': 'pendente',
      'payment_method': 'stripe',
      'shipping_method': 'ctt',
    });
    c.note('p3.order_lo', 'order live_only after end', orderIns.brief,
        lens: 'AK7');
    out['order_lo'] = orderIns.brief;
    if (orderIns.ok) {
      c.finding(
        id: 'RTAK-AK7-ORDER-ENDED-LIVE-ONLY',
        lens: 'AK7',
        severity: 'P2',
        title: 'Buyer cria order em live_item de directo já ended',
        actor: 'buyer JWT',
        pre: 'live ended after item insert',
        repro: 'POST orders live_item_id',
        expected: 'recusar live ended',
        obtained: orderIns.snippet,
      );
    } else {
      c.hold(
        id: 'RTAK-AK7-ORDER-ENDED-LIVE-ONLY',
        lens: 'AK7',
        title: 'order live_only ended recusado',
        actor: 'buyer JWT',
        pre: 'ended',
        repro: 'POST orders',
        expected: 'denied',
        obtained: orderIns.brief,
      );
    }
  }

  await c.endLives();

  out['findings'] = c.findings;
  out['holds'] = c.holds;
  out['notes'] = c.notes;
  final path = '${repoRoot()}/tool/redteam_blind_ak_$stamp/pass3.json';
  await dumpJson(path, out);
  stdout.writeln(
      'WROTE $path findings=${c.findings.length} holds=${c.holds.length}');
}
