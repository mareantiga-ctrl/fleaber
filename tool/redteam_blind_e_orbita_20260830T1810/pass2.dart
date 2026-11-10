/// REDTEAM_BLIND_E_ORBITA_v1 — PASS 2: aprofundar E4/E6/E5/E10 até estado final.
/// Staging only. Stripe TEST. No production. No fixes.
import 'dart:io';

import '_http.dart';

Future<void> main() async {
  final c = await boot();
  stdout.writeln('E PASS2 boot buyer=${c.buyerId}');

  await _e6DeadCheckout(c);
  await _e4SelfAcceptHolds(c);
  await _e5DnsNote(c);
  await _e2WalletOnOwnHold(c);
  await _cleanup(c);

  await dumpJson(
    'tool/redteam_blind_e_orbita_20260830T1810/out/pass2.json',
    {
      'auditor': 'REDTEAM_BLIND_E_ORBITA_v1',
      'project': projectMust,
      'prefix': prefix,
      'pass': 2,
      'production_touched': false,
      'fase4': false,
      'corrections_applied': false,
      'matrix': matrix,
      'findings': findings,
      'gaps': gaps,
    },
  );
  stdout.writeln(
    'PASS2 done matrix=${matrix.length} findings=${findings.length}',
  );
}

Future<void> _e6DeadCheckout(Ctx c) async {
  final p = await rest(
    c.url,
    'POST',
    'products',
    headers: c.svcH,
    body: {
      'seller_id': c.sellerId,
      'title': '$prefix-dead-pay',
      'price': 8.0,
      'quantity': 2,
      'list_on_marketplace': true,
      'is_sold': false,
    },
  );
  rec(
    lens: 'E6',
    surface: 'products',
    attack: 'fixture_dead',
    identity: 'service_role_setup',
    result: brief(p, 160),
  );
  final pj = tryJson(p);
  String? pid;
  if (pj is List && pj.isNotEmpty) pid = pj.first['id']?.toString();
  if (pid == null) {
    gaps.add('E6 pass2 product fail');
    return;
  }

  await rest(
    c.url,
    'PATCH',
    'products',
    headers: c.svcH,
    qs: 'id=eq.$pid',
    body: {'list_on_marketplace': false, 'is_sold': true},
  );

  final b2read = await rest(
    c.url,
    'GET',
    'products',
    headers: c.buyer2H,
    qs: 'id=eq.$pid&select=id,title,is_sold,list_on_marketplace,quantity,price',
  );
  rec(
    lens: 'E6',
    surface: 'products',
    attack: 'buyer2_read_unlisted_never_met',
    identity: 'buyer2',
    result: brief(b2read, 280),
  );
  if (looksOk(b2read) && b2read.body.trim() != '[]') {
    finding(
      id: 'E6-AUTH-READ-UNLISTED',
      severity: 'P2',
      title: 'JWT estranho le produto unlisted+sold (nao marketplace, nao dono)',
      actor: 'buyer2',
      pre: 'RLS list_on_marketplace OR own',
      repro: 'GET products id=eq.dead as buyer2',
      impact: 'Catalogo morto visivel a qualquer autenticado',
      evidence: brief(b2read, 400),
    );
  }

  final before = await rest(
    c.url,
    'GET',
    'products',
    headers: c.svcH,
    qs: 'id=eq.$pid&select=id,quantity,is_sold,list_on_marketplace',
  );

  final ord = await rest(
    c.url,
    'POST',
    'orders',
    headers: c.buyerH,
    body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'price_total': 8.0,
      'status': 'reserva_pendente',
      'quantity': 1,
      'shipping_method': 'Entrega em Mão (€0.00)',
    },
  );
  rec(
    lens: 'E6',
    surface: 'orders',
    attack: 'hold_dead_product',
    identity: 'buyer',
    result: brief(ord, 320),
  );
  String? oid;
  final oj = tryJson(ord);
  if (looksOk(ord) && oj is List && oj.isNotEmpty) {
    oid = oj.first['id']?.toString();
    rec(
      lens: 'E6',
      surface: 'orders',
      attack: 'hold_dead_status',
      identity: 'buyer',
      result:
          'status=${oj.first['status']} qty=${oj.first['quantity']} total=${oj.first['price_total']}',
      evidence: {
        'order_id': oid,
        'status': oj.first['status'],
        'contract_unit_cents': oj.first['contract_unit_cents'],
        'contract_qty': oj.first['contract_qty'],
      },
    );
  }

  final after = await rest(
    c.url,
    'GET',
    'products',
    headers: c.svcH,
    qs: 'id=eq.$pid&select=id,quantity,is_sold,list_on_marketplace',
  );
  rec(
    lens: 'E6',
    surface: 'products',
    attack: 'stock_after_dead_hold',
    identity: 'service_role_observe',
    result: 'before=${brief(before, 120)} after=${brief(after, 120)}',
  );

  if (oid != null) {
    final pay = await edge(
      c.url,
      'create-payment-intent',
      anon: c.anon,
      jwt: c.buyerJwt,
      body: {
        'buyer_id': c.buyerId,
        'order_id': oid,
        'shipping_method': 'Entrega em Mão (€0.00)',
        'currency': 'eur',
      },
    );
    rec(
      lens: 'E6',
      surface: 'create-payment-intent',
      attack: 'checkout_dead_sold_unlisted',
      identity: 'buyer',
      result: brief(pay, 450),
    );
    final payJ = tryJson(pay);
    var hasUrl = false;
    var amount = '';
    if (payJ is Map) {
      hasUrl = (payJ['url'] ?? payJ['checkout_url'] ?? '').toString().isNotEmpty;
      amount = '${payJ['amount'] ?? payJ['amount_cents'] ?? ''}';
    }
    if (looksOk(pay) && (hasUrl || pay.body.contains('cs_'))) {
      finding(
        id: 'E6-DEAD-CHECKOUT-SESSION',
        severity: 'P1',
        title: 'create-payment-intent emite Session Stripe para produto is_sold+unlisted',
        actor: 'buyer',
        pre: 'produto morto com qty>0',
        repro:
            'PATCH is_sold=true list_on_marketplace=false; POST order reserva_pendente; POST create-payment-intent',
        impact: 'Mortos que vendem: captura TEST possivel em artigo despublicado/vendido',
        evidence: {
          'order_id': oid,
          'product_id': pid,
          'has_checkout_url': hasUrl,
          'amount_hint': amount,
          'http': brief(pay, 600),
        },
      );
    }

    final iban = await rpc(
      c.url,
      'batata_seller_direct_payment_details',
      {'p_seller_id': c.sellerId},
      headers: c.buyerH,
    );
    rec(
      lens: 'E10',
      surface: 'batata_seller_direct_payment_details',
      attack: 'iban_after_dead_hold',
      identity: 'buyer',
      result: brief(iban, 220),
    );
  }

  cleanup['products'] = [...(cleanup['products'] ?? []), pid];
  if (oid != null) {
    cleanup['orders'] = [...(cleanup['orders'] ?? []), oid];
  }
}

Future<void> _e4SelfAcceptHolds(Ctx c) async {
  final p1 = await rest(
    c.url,
    'POST',
    'products',
    headers: c.svcH,
    body: {
      'seller_id': c.sellerId,
      'title': '$prefix-bA',
      'price': 11.0,
      'quantity': 2,
      'list_on_marketplace': true,
      'is_sold': false,
    },
  );
  final p2 = await rest(
    c.url,
    'POST',
    'products',
    headers: c.svcH,
    body: {
      'seller_id': c.sellerId,
      'title': '$prefix-bB',
      'price': 13.0,
      'quantity': 2,
      'list_on_marketplace': true,
      'is_sold': false,
    },
  );
  final j1 = tryJson(p1);
  final j2 = tryJson(p2);
  String? id1;
  String? id2;
  if (j1 is List && j1.isNotEmpty) id1 = j1.first['id']?.toString();
  if (j2 is List && j2.isNotEmpty) id2 = j2.first['id']?.toString();
  if (id1 == null || id2 == null) return;

  final bun = await rest(
    c.url,
    'POST',
    'product_bundles',
    headers: c.buyerH,
    body: {
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'product_ids': [id1, id2],
      'subtotal_eur': 24.0,
      'discount_pct': 50.0,
      'discount_eur': 12.0,
      'total_eur': 0.50,
      'status': 'pending',
    },
  );
  final bj = tryJson(bun);
  String? bid;
  if (looksOk(bun) && bj is List && bj.isNotEmpty) {
    bid = bj.first['id']?.toString();
  }
  if (bid == null) return;

  final acc = await rest(
    c.url,
    'PATCH',
    'product_bundles',
    headers: c.buyerH,
    qs: 'id=eq.$bid',
    body: {'status': 'accepted', 'total_eur': 0.50, 'discount_pct': 50},
  );
  rec(
    lens: 'E4',
    surface: 'product_bundles',
    attack: 'repro_self_accept',
    identity: 'buyer',
    result: brief(acc, 280),
  );

  final oids = <String>[];
  for (final pid in [id1, id2]) {
    final ord = await rest(
      c.url,
      'POST',
      'orders',
      headers: c.buyerH,
      body: {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': pid,
        'price_total': 0.50,
        'status': 'reservado',
        'is_reservation': true,
        'payment_method': 'Compra em conjunto aceite',
        'bundle_id': bid,
        'quantity': 1,
        'shipping_method': 'Entrega em Mão (€0.00)',
      },
    );
    rec(
      lens: 'E4',
      surface: 'orders',
      attack: 'hold_line_$pid',
      identity: 'buyer',
      result: brief(ord, 280),
    );
    final oj = tryJson(ord);
    if (looksOk(ord) && oj is List && oj.isNotEmpty) {
      oids.add(oj.first['id'].toString());
    }
  }

  rec(
    lens: 'E4',
    surface: 'orders',
    attack: 'holds_created',
    identity: 'buyer',
    result: 'n=${oids.length}',
    evidence: oids,
  );

  if (oids.length >= 2) {
    final pay = await edge(
      c.url,
      'create-payment-intent',
      anon: c.anon,
      jwt: c.buyerJwt,
      body: {
        'buyer_id': c.buyerId,
        'bag_checkout': true,
        'bag_lines': [
          {'order_id': oids[0]},
          {'order_id': oids[1]},
        ],
        'shipping_method': 'Entrega em Mão (€0.00)',
        'currency': 'eur',
      },
    );
    rec(
      lens: 'E4',
      surface: 'create-payment-intent',
      attack: 'bag_checkout_self_accepted_hostile_total',
      identity: 'buyer',
      result: brief(pay, 500),
    );
    final payJ = tryJson(pay);
    if (looksOk(pay)) {
      finding(
        id: 'E4-BAG-SESSION-AFTER-FORGE-ACCEPT',
        severity: 'P1',
        title: 'Bag Checkout Session apos buyer forjar accepted no conjunto',
        actor: 'buyer',
        pre: 'PATCH product_bundles status=accepted (buyer); 2 holds',
        repro: 'POST create-payment-intent bag_checkout 2 orders',
        impact:
            'Seller nao aceitou; stock em hold; Session Stripe (preco server-side a verificar vs 0.50 hostil)',
        evidence: payJ is Map
            ? {
                'keys': payJ.keys.toList(),
                'amount': payJ['amount'] ?? payJ['amount_cents'],
                'url_present': (payJ['url'] ?? '').toString().isNotEmpty,
                'body': brief(pay, 700),
              }
            : brief(pay, 700),
      );
    }
  }

  cleanup['products'] = [...(cleanup['products'] ?? []), id1, id2];
  cleanup['product_bundles'] = [...(cleanup['product_bundles'] ?? []), bid];
  cleanup['orders'] = [...(cleanup['orders'] ?? []), ...oids];
}

Future<void> _e5DnsNote(Ctx c) async {
  rec(
    lens: 'E5',
    surface: 'create-connect-account',
    attack: 'subdomain_allowlist_note',
    identity: 'anon',
    result:
        '303 Location=https://evil.fleaber.pt/wallet (pass1). Impacto depende de DNS wildcard / takeover.',
  );
}

Future<void> _e2WalletOnOwnHold(Ctx c) async {
  final orders = cleanup['orders'] ?? [];
  if (orders.isEmpty) return;
  final r = await rpc(
    c.url,
    'batata_release_seller_wallet_for_order',
    {'p_order_id': orders.first},
    headers: c.buyerH,
  );
  rec(
    lens: 'E2',
    surface: 'batata_release_seller_wallet_for_order',
    attack: 'fire_on_reserva_not_concluido',
    identity: 'buyer',
    result: brief(r, 200),
  );
}

Future<void> _cleanup(Ctx c) async {
  for (final oid in cleanup['orders'] ?? []) {
    await rest(
      c.url,
      'PATCH',
      'orders',
      headers: c.svcH,
      qs: 'id=eq.$oid',
      body: {'status': 'cancelado'},
    );
  }
  for (final bid in cleanup['product_bundles'] ?? []) {
    await rest(
      c.url,
      'PATCH',
      'product_bundles',
      headers: c.svcH,
      qs: 'id=eq.$bid',
      body: {'status': 'cancelled'},
    );
  }
  // Nao apagar products se orders ainda referenciam; cancelado chega.
}
