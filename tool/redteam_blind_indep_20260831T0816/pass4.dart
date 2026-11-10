import 'dart:io';

import '_rti4.dart';

Future<void> main() async {
  final c = Rti4(loadEnv());
  await c.boot();
  final e2eSecret = (c.env['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '').trim();
  final liveId = '4d2efb5a-d520-4478-8d8d-1a2a0a92cc5c';
  final paidOid = '7a85e038-c1f6-4df3-a4ef-a0ccd9a86837';
  final freshHold = '247cbc6c-a28f-4de7-a493-5b9afe726cfd';
  final unlistedId = 'bf6c5e1d-f59f-471c-be48-f12d5f36d044';

  // Wallet + txs accounting on captured order
  final wSel = await c.rest(
    'GET',
    'wallets?id=eq.${c.sellerId}&select=*',
    service: true,
  );
  final wBuy = await c.rest(
    'GET',
    'wallets?id=eq.${c.buyerId}&select=*',
    service: true,
  );
  final txs = await c.rest(
    'GET',
    'wallet_transactions?order_id=eq.$paidOid&select=*',
    service: true,
  );
  c.note('p2b.accounting', 'wallet+txs after release', {
    'seller': wSel.list.isNotEmpty ? wSel.list.first : wSel.brief,
    'buyer': wBuy.list.isNotEmpty ? wBuy.list.first : wBuy.brief,
    'txs': txs.list,
  }, well: '2');

  // Fresh Edge session on unlist+live (2nd economic path)
  if (c.freshJwt != null) {
    final ck = await c.edge(
      'create-payment-intent',
      {
        'amount': 450,
        'currency': 'eur',
        'product_id': unlistedId,
        'buyer_id': c.freshId,
        'seller_id': c.sellerId,
        'order_id': freshHold,
        'quantity': 1,
        'item_price': 450,
        'shipping': 0,
        'protection_fee': 0,
        'shipping_method': 'Entrega em mão (€0.00)',
        'live_id': liveId,
      },
      token: c.freshJwt,
    );
    c.note('p1c.fresh.edge', 'fresh edge unlist+live', ck.brief, well: '1');
    final cs = ck.map?['checkoutSessionId']?.toString();
    if (ck.ok && (cs ?? '').isNotEmpty) {
      c.finding(
        id: 'RTI4-P1-DUAL-SESSION-DEAD',
        title: 'duas Checkout Sessions em SKU unlistado (qty=2, 2 holds via live)',
        actor: 'buyer + fresh',
        sev: 'P2',
        well: '1',
        pre: 'quantity=2 unlist; 2 holds com live_id; Hub vazio',
        request: '2x create-payment-intent',
        before: {'qty': 2, 'holds': 2},
        after: {'fresh_cs': cs, 'http': ck.brief},
        impact:
            'Duas SESSION em catálogo morto. Oversell só se qty=1 e ambas capturarem. Aqui qty=2 ⇒ capacidade cheia, não oversell.',
        repro: '2 JWT holds + 2 Sessions',
      );
    }
  }

  // Race: unlist qty=1 + live_id N parallel
  final dead1 = await c.insertProduct(listed: false, sold: false, qty: 1);
  if (dead1 != null) {
    final pid = dead1['id'].toString();
    final rs = await Future.wait(List.generate(
      6,
      (_) => c.insertOrder(
        token: c.buyerJwt,
        productId: pid,
        liveId: liveId,
      ),
    ));
    final ok = rs.where((r) => r.ok && r.list.isNotEmpty).toList();
    for (final r in ok) {
      c.createdOrderIds.add((r.list.first as Map)['id'].toString());
    }
    c.note('p1c.race.dead1', 'unlist qty=1 + live N=6',
        'ok=${ok.length} codes=${rs.map((e) => e.status).toList()}', well: '1');
    if (ok.length >= 2) {
      c.finding(
        id: 'RTI4-P1-RACE-DEAD-QTY1',
        title: 'unlist qty=1 + live_id: ≥2 holds paralelos',
        actor: 'buyer',
        sev: 'P1',
        well: '1',
        pre: 'quantity=1 list_on_marketplace=false live activa',
        request: '6 POST orders paralelo com live_id',
        before: dead1,
        after: {'holds': ok.length},
        impact:
            'Capacidade morta reaberta e race. Duas holds ≠ duas capturas; Sessions a seguir.',
        repro: 'unlist qty=1 + live_id parallel INSERT',
      );
      // dual Edge on first two holds
      final oids = ok
          .map((r) => (r.list.first as Map)['id'].toString())
          .take(2)
          .toList();
      final sessions = <String>[];
      for (final oid in oids) {
        final ck = await c.edge(
          'create-payment-intent',
          {
            'amount': 450,
            'currency': 'eur',
            'product_id': pid,
            'buyer_id': c.buyerId,
            'seller_id': c.sellerId,
            'order_id': oid,
            'quantity': 1,
            'item_price': 450,
            'shipping_method': 'Entrega em mão (€0.00)',
            'live_id': liveId,
          },
          token: c.buyerJwt,
        );
        c.note('p1c.race.ck.$oid', 'edge race hold', ck.brief, well: '1');
        final cs = ck.map?['checkoutSessionId']?.toString();
        if (cs != null && cs.isNotEmpty) sessions.add(cs);
      }
      if (sessions.length >= 2) {
        c.finding(
          id: 'RTI4-P1-RACE-DEAD-DUAL-CS',
          title: 'qty=1 unlist+live: 2 Checkout Sessions',
          actor: 'buyer JWT + Edge',
          sev: 'P1',
          well: '1',
          pre: '2 holds em qty=1 unlist',
          request: '2x create-payment-intent',
          before: oids,
          after: sessions,
          impact:
              'Duas SESSION no mesmo SKU qty=1 morto. Captura dupla NÃO COMPROVADA (sem 4242 nestas cs).',
          repro: 'parallel hold + 2 Sessions',
        );
      }
    } else {
      c.hold('p1c.race.dead1', '≤1 hold qty=1 unlist+live', 'ok=${ok.length}',
          well: '1');
    }
  }

  // New paid order: dispute from enviado (before confirm)
  Future<HttpR> e2e(Map<String, dynamic> body) {
    return c.edge(
      'sec-fase2-e2e-oversell',
      body,
      service: true,
      extra: e2eSecret.isEmpty ? null : {'x-fleaber-e2e-secret': e2eSecret},
    );
  }

  final paid2 = await e2e({
    'probe': 'setup_paid_order',
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'initial_qty': 1,
  });
  c.note('p2b.paid2', 'second paid fixture', paid2.brief, well: '2');
  final oid2 = paid2.map?['order_id']?.toString();
  if (oid2 != null) {
    c.createdOrderIds.add(oid2);
    final env = await c.rest(
      'PATCH',
      'orders?id=eq.$oid2',
      token: c.sellerJwt,
      body: {'status': 'enviado'},
    );
    final oEnv = await c.getOne('orders', oid2, select: 'id,status');
    c.note('p2b.enviado', 'seller enviado paid2',
        '${env.brief} after=${oEnv?['status']}', well: '2');

    // refund while enviado
    final rf = await c.edge('refund-order', {'order_id': oid2}, token: c.sellerJwt);
    c.note('p2b.refund.enviado', 'seller refund enviado', rf.brief, well: '2');
    final oRf = await c.getOne(
      'orders',
      oid2,
      select: 'id,status,stripe_refund_id,amount_paid_cents',
    );

    // dispute from enviado
    final d = await c.rest(
      'POST',
      'order_disputes',
      token: c.buyerJwt,
      body: {
        'order_id': oid2,
        'buyer_id': c.buyerId,
        'status': 'aberta',
        'reason': '$prefix enviado dispute',
      },
    );
    c.note('p2b.disp.enviado', 'buyer dispute from enviado', d.brief, well: '2');
    String? did;
    if (d.ok && d.list.isNotEmpty) {
      did = (d.list.first as Map)['id']?.toString();
    }

    // buyer concluido while dispute? 
    final conf = await c.rest(
      'PATCH',
      'orders?id=eq.$oid2',
      token: c.buyerJwt,
      body: {'status': 'concluido'},
    );
    final oC = await c.getOne('orders', oid2, select: 'id,status');
    c.note('p2b.confirm.disp', 'buyer concluido with/after dispute',
        '${conf.brief} after=${oC?['status']}', well: '2');

    if (did != null) {
      final close = await c.rest(
        'PATCH',
        'order_disputes?id=eq.$did',
        token: c.sellerJwt,
        body: {'status': 'resolvida'},
      );
      final da = await c.getOne('order_disputes', did, select: 'id,status');
      c.note('p2b.seller.close', 'seller close', '${close.brief} ${da?['status']}',
          well: '2');
      if ((da?['status'] ?? '').toString().toLowerCase() == 'resolvida') {
        c.finding(
          id: 'RTI4-P2-SELLER-CLOSE-DISPUTE',
          title: 'seller fecha disputa',
          actor: 'seller',
          sev: 'P1',
          well: '2',
          pre: 'disputa aberta',
          request: 'PATCH resolvida',
          before: did,
          after: da,
          impact: 'Seller auto-absolve.',
          repro: 'PATCH order_disputes',
        );
      } else {
        c.hold('p2b.seller.close', 'seller não fecha', da, well: '2');
      }
    }

    final rel = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oid2},
      token: c.buyerJwt,
    );
    c.note('p2b.release.after.disp', 'release after dispute/refund', {
      'rpc': rel.brief,
      'order': oRf,
      'status': oC?['status'],
    }, well: '2');
  }

  // livekit cleanup JWT
  final lk = await c.edge('livekit-egress-cleanup', {}, token: c.buyerJwt);
  final lkAnon = await c.edge('livekit-egress-cleanup', {});
  c.note('p4.livekit.jwt', 'egress cleanup buyer', lk.brief, well: '4');
  c.note('p4.livekit.anon', 'egress cleanup anon', lkAnon.brief, well: '4');

  // stripe-webhook unsigned
  final wh = await c.call(
    'POST',
    '/functions/v1/stripe-webhook',
    body: {
      'type': 'checkout.session.completed',
      'data': {
        'object': {'id': 'cs_test_forged', 'payment_status': 'paid'}
      }
    },
  );
  c.note('p4.webhook.unsigned', 'stripe-webhook no sig', wh.brief, well: '4');

  await c.dump('pass4');
  stdout.writeln(
      'PASS4 done findings=${c.findings.length} holds=${c.holds.length}');
}
