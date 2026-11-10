/// Parallel C — Pass 2: Poço 2 unidade/races + Poço 3 composição + off-platform wallet.
import 'dart:convert';
import 'dart:io';
import '_rtc.dart';

String? csFrom(Map<String, dynamic> ck) {
  final j = ck['json'];
  if (j is Map) {
    final url = '${j['checkoutUrl'] ?? j['url'] ?? ''}';
    final m = RegExp(r'cs_test_[A-Za-z0-9]+').firstMatch(url);
    if (m != null) return m.group(0);
    final sid = j['sessionId'] ?? j['session_id'];
    if (sid != null) return '$sid';
  }
  final raw = '${ck['raw']}';
  return RegExp(r'cs_test_[A-Za-z0-9]+').firstMatch(raw)?.group(0);
}

Future<void> main() async {
  final c = Rtc(loadEnv());
  await c.boot();
  final bJwt = c.buyerJwt!;
  final sJwt = c.sellerJwt!;
  final bId = c.buyerId!;
  final sId = c.sellerId!;
  final fJwt = c.freshJwt;
  final fId = c.freshId;

  Directory('tool/redteam_parallel_c_20260831T0734/out')
      .createSync(recursive: true);

  // -----------------------------------------------------------------------
  // E — off-platform pago → concluido → release (mint sem captura?)
  // -----------------------------------------------------------------------
  final offPid = await c.createProduct(
    token: sJwt,
    seller: sId,
    title: '$prefix off-wallet',
    price: 9,
    qty: 1,
  );
  if (offPid != null) {
    final offO = await c.createOrder(
      token: bJwt,
      buyer: bId,
      seller: sId,
      productId: offPid,
      payment: 'MB WAY',
      shipping: 'entrega em mão',
    );
    final oid = (offO['json'] is List && (offO['json'] as List).isNotEmpty)
        ? (offO['json'] as List).first['id']?.toString()
        : null;
    if (oid != null) {
      final wS0 = await c.walletBalance(sId);
      final wB0 = await c.walletBalance(bId);
      final pPago = await c.rest(
        'PATCH',
        'orders',
        token: sJwt,
        query: 'id=eq.$oid',
        prefer: 'return=representation',
        body: {'status': 'pago'},
      );
      final pConc = await c.rest(
        'PATCH',
        'orders',
        token: bJwt,
        query: 'id=eq.$oid',
        prefer: 'return=representation',
        body: {'status': 'concluido'},
      );
      final rel = await c.rpc(
        'batata_release_seller_wallet_for_order',
        {'p_order_id': oid},
        token: bJwt,
      );
      final row = await c.observeOrder(oid);
      final wS1 = await c.walletBalance(sId);
      final wB1 = await c.walletBalance(bId);
      final txs = await c.walletTx(orderId: oid);
      final minted = (wS1 ?? 0) > (wS0 ?? 0);
      c.rec(
        id: 'E.offplat.concluido.release',
        surface: 'orders+wallet',
        attack: 'MB WAY seller pago → buyer concluido → release',
        identity: 'conluio B+V',
        httpCode: rel['http'] as int,
        result:
            'pago_http=${pPago['http']} conc_http=${pConc['http']} status=${row['status']} paid=${row['amount_paid_cents']} rel=${rel['json']} Δs=${wS0}→$wS1 Δb=${wB0}→$wB1 txs=${txs.length}',
        impact: minted ? 'MINT wallet off-platform' : 'sem mint (funds=0)',
        sev: minted ? 'P0' : '—',
        evidence:
            'row=${jsonEncode(row)} conc=${clip('${pConc['raw']}', 120)} rel=${clip('${rel['raw']}', 80)} txs=${jsonEncode(txs)}',
      );
      if (minted) {
        c.finding(Finding(
          id: 'RTC-C-E01',
          sev: 'P0',
          title: 'Release credita wallet em encomenda MB WAY sem captura Stripe',
          actor: 'conluio buyer+seller JWT',
          pre: 'order MB WAY mão, seller marca pago, buyer concluido',
          repro:
              'PATCH seller status=pago; PATCH buyer status=concluido; RPC batata_release_seller_wallet_for_order',
          impact: 'Δseller ${(wS1 ?? 0) - (wS0 ?? 0)} € sem amount_paid_cents',
        ));
      }
    }
  }

  // Stripe paid + hand → concluido → release (contabilidade legítima)
  final cap = await c.e2e({
    'probe': 'setup_paid_order',
    'buyer_id': bId,
    'seller_id': sId,
    'initial_qty': 2,
  });
  String? capOid;
  String? capPid;
  if (cap['json'] is Map) {
    capOid = (cap['json'] as Map)['order_id']?.toString();
    capPid = (cap['json'] as Map)['product_id']?.toString();
    if (capOid != null) c.createdOrderIds.add(capOid);
    if (capPid != null) c.createdProductIds.add(capPid);
  }
  if (capOid != null) {
    // fixture: selar mão para permitir pago→concluido
    await c.rest(
      'PATCH',
      'orders',
      service: true,
      query: 'id=eq.$capOid',
      body: {'shipping_method': 'entrega em mão'},
    );
    final wS0 = await c.walletBalance(sId);
    final wB0 = await c.walletBalance(bId);
    final conc = await c.rest(
      'PATCH',
      'orders',
      token: bJwt,
      query: 'id=eq.$capOid',
      prefer: 'return=representation',
      body: {'status': 'concluido'},
    );
    final rel = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': capOid},
      token: bJwt,
    );
    final rel2 = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': capOid},
      token: bJwt,
    );
    final row = await c.observeOrder(capOid);
    final wS1 = await c.walletBalance(sId);
    final wB1 = await c.walletBalance(bId);
    final txs = await c.walletTx(orderId: capOid);
    c.rec(
      id: 'E.stripe.concluido.release',
      surface: 'wallet',
      attack: 'captura 590¢ + concluido mão + release ×2',
      identity: 'buyer',
      httpCode: rel['http'] as int,
      result:
          'conc=${conc['http']} rel=${rel['json']} rel2=${rel2['json']} status=${row['status']} Δs=$wS0→$wS1 Δb=$wB0→$wB1 txs=${jsonEncode(txs.map((t) => '${t['type']}:${t['amount']}').toList())}',
      impact: 'contabilidade captura→release',
      evidence:
          'row=${jsonEncode(row)} conc=${clip('${conc['raw']}', 100)}',
    );
    // refund after release
    final ref = await c.edge(
      'refund-order',
      token: sJwt,
      body: {'order_id': capOid},
    );
    final wS2 = await c.walletBalance(sId);
    final wB2 = await c.walletBalance(bId);
    final txs2 = await c.walletTx(orderId: capOid);
    c.rec(
      id: 'E.refund.after.release',
      surface: 'refund-order+wallet',
      attack: 'refund Stripe após release seller',
      identity: 'seller',
      httpCode: ref['http'] as int,
      result:
          '${clip('${ref['raw']}', 140)} Δs=$wS1→$wS2 Δb=$wB1→$wB2 txs=${jsonEncode(txs2.map((t) => '${t['type']}:${t['amount']}').toList())}',
      impact: ((wS2 ?? 0) > (wS1 ?? 0) && (wB2 ?? 0) > (wB1 ?? 0))
          ? 'release+refund mint líquido'
          : 'clawback ou skip',
      sev: ((asNum(wS2) ?? 0) + (asNum(wB2) ?? 0) >
              (asNum(wS1) ?? 0) + (asNum(wB1) ?? 0) + 0.01)
          ? 'P0'
          : '—',
      evidence: clip('${ref['raw']}', 220),
    );
  }

  // -----------------------------------------------------------------------
  // F — stock=1 races (JWT)
  // -----------------------------------------------------------------------
  final racePid = await c.createProduct(
    token: sJwt,
    seller: sId,
    title: '$prefix stock1',
    price: 6,
    qty: 1,
  );
  if (racePid != null) {
    final inserts = await Future.wait(List.generate(10, (i) {
      final tok = (i.isEven || fJwt == null) ? bJwt : fJwt;
      final bid = (i.isEven || fId == null) ? bId : fId;
      return c.createOrder(
        token: tok,
        buyer: bid,
        seller: sId,
        productId: racePid,
        qty: 1,
      );
    }));
    final okIds = <String>[];
    final codes = <int>[];
    for (final r in inserts) {
      codes.add(r['http'] as int);
      if (r['json'] is List && (r['json'] as List).isNotEmpty) {
        final id = (r['json'] as List).first['id']?.toString();
        if (id != null) okIds.add(id);
      }
    }
    final prod = await c.observeProduct(racePid);
    c.rec(
      id: 'F.race.insert.stock1.x10',
      surface: 'orders INSERT',
      attack: '10 INSERT paralelos qty=1 stock=1 (buyer+fresh)',
      identity: 'buyer+fresh',
      httpCode: okIds.isEmpty ? 400 : 201,
      result:
          'accepted=${okIds.length} codes=$codes prod_qty=${prod['quantity']} is_sold=${prod['is_sold']}',
      impact: okIds.length >= 2
          ? '2+ holds em stock=1'
          : '1 hold ou zero',
      sev: okIds.length >= 2 ? 'P1' : '—',
      evidence: 'ids=$okIds',
    );

    // checkout all accepted in parallel
    if (okIds.isNotEmpty) {
      final cks = await Future.wait(okIds.map((oid) {
        final isFresh = false; // lab buyer owns even; mixed
        return c.checkout(token: bJwt, buyer: bId, orderId: oid);
      }));
      final ckOk = cks.where((e) => e['http'] == 200).length;
      c.rec(
        id: 'F.race.checkout.accepted',
        surface: 'create-payment-intent',
        attack: 'checkout paralelo das orders aceites',
        identity: 'buyer',
        httpCode: 200,
        result:
            'sessions=$ckOk/${okIds.length} bodies=${cks.map((e) => '${e['http']}:${clip('${e['raw']}', 40)}').join(' | ')}',
        impact: ckOk >= 2 ? '2 Sessions stock=1' : '1 Session',
        sev: ckOk >= 2 ? 'P1' : '—',
        evidence: cks.map((e) => clip('${e['raw']}', 80)).join(' || '),
      );
    }

    // seller is_sold while another order tries checkout
    final pid2 = await c.createProduct(
      token: sJwt,
      seller: sId,
      title: '$prefix sold-gate',
      price: 7,
      qty: 1,
    );
    if (pid2 != null) {
      final o = await c.createOrder(
        token: bJwt,
        buyer: bId,
        seller: sId,
        productId: pid2,
      );
      final oid = (o['json'] is List && (o['json'] as List).isNotEmpty)
          ? (o['json'] as List).first['id']?.toString()
          : null;
      await c.rest(
        'PATCH',
        'products',
        token: sJwt,
        query: 'id=eq.$pid2',
        body: {'is_sold': true},
      );
      if (oid != null) {
        final ck = await c.checkout(token: bJwt, buyer: bId, orderId: oid);
        c.rec(
          id: 'F.checkout.after.is_sold',
          surface: 'create-payment-intent',
          attack: 'seller is_sold=true depois da order',
          identity: 'conluio',
          httpCode: ck['http'] as int,
          result: clip('${ck['raw']}', 160),
          impact: ck['http'] == 200 ? 'Session após sold' : 'bloqueado',
          sev: ck['http'] == 200 ? 'P1' : '—',
          evidence: clip('${ck['raw']}', 180),
        );
      }
    }

    // unlist after order
    final pid3 = await c.createProduct(
      token: sJwt,
      seller: sId,
      title: '$prefix unlist',
      price: 7,
      qty: 1,
    );
    if (pid3 != null) {
      final o = await c.createOrder(
        token: bJwt,
        buyer: bId,
        seller: sId,
        productId: pid3,
      );
      final oid = (o['json'] is List && (o['json'] as List).isNotEmpty)
          ? (o['json'] as List).first['id']?.toString()
          : null;
      await c.rest(
        'PATCH',
        'products',
        token: sJwt,
        query: 'id=eq.$pid3',
        body: {'list_on_marketplace': false},
      );
      if (oid != null) {
        final ck = await c.checkout(token: bJwt, buyer: bId, orderId: oid);
        c.rec(
          id: 'F.checkout.after.unlist',
          surface: 'create-payment-intent',
          attack: 'unlist após order (sem live)',
          identity: 'conluio',
          httpCode: ck['http'] as int,
          result: clip('${ck['raw']}', 160),
          impact: ck['http'] == 200 ? 'Session unlisted' : 'bloqueado',
          sev: ck['http'] == 200 ? 'P1' : '—',
          evidence: clip('${ck['raw']}', 180),
        );
      }
    }
  }

  // e2e oversell 2 PI stock=1 (estado final)
  final ov = await c.e2e({
    'buyer_id': bId,
    'seller_id': sId,
  });
  c.rec(
    id: 'F.e2e.oversell.two.pi',
    surface: 'sec-fase2-e2e-oversell',
    attack: '2 PI succeeded stock=1',
    identity: 'service_fixture',
    httpCode: ov['http'] as int,
    result: clip('${ov['raw']}', 240),
    impact: 'oversell refund?',
    evidence: clip('${ov['raw']}', 280),
  );

  // -----------------------------------------------------------------------
  // G — GET settle unpaid + burst + bag leftover
  // -----------------------------------------------------------------------
  final pCk = await c.createProduct(
    token: sJwt,
    seller: sId,
    title: '$prefix settle-get',
    price: 5,
    qty: 2,
  );
  if (pCk != null) {
    final o = await c.createOrder(
      token: bJwt,
      buyer: bId,
      seller: sId,
      productId: pCk,
      shipping: 'entrega em mão',
    );
    final oid = (o['json'] is List && (o['json'] as List).isNotEmpty)
        ? (o['json'] as List).first['id']?.toString()
        : null;
    if (oid != null) {
      final ck = await c.checkout(token: bJwt, buyer: bId, orderId: oid);
      final sid = csFrom(ck);
      c.notes.add('settle_cs=$sid ck_http=${ck['http']}');
      if (sid != null) {
        final burst = await Future.wait(List.generate(
          8,
          (_) => c.edge(
            'create-payment-intent',
            method: 'GET',
            query: 'checkout_return=success&session_id=$sid',
          ),
        ));
        final row = await c.observeOrder(oid);
        c.rec(
          id: 'G.settle.get.unpaid.burst8',
          surface: 'create-payment-intent GET',
          attack: '8× GET settle Session não paga',
          identity: 'anon',
          httpCode: burst.first['http'] as int,
          result:
              'codes=${burst.map((e) => e['http']).toList()} status=${row['status']} paid=${row['amount_paid_cents']}',
          impact: row['status'] == 'pago'
              ? 'liquidou unpaid'
              : 'não liquidou',
          sev: row['status'] == 'pago' ? 'P0' : '—',
          evidence: burst.map((e) => '${e['http']}').join(','),
        );
      }

      // 2nd session same order (slot)
      final ck2 = await c.checkout(token: bJwt, buyer: bId, orderId: oid);
      c.rec(
        id: 'G.checkout.second.session.same.order',
        surface: 'create-payment-intent',
        attack: '2ª Session mesma order',
        identity: 'buyer',
        httpCode: ck2['http'] as int,
        result: 'cs1=$sid cs2=${csFrom(ck2)} ${clip('${ck2['raw']}', 80)}',
        impact: (csFrom(ck2) != null && csFrom(ck2) != sid)
            ? '2 Sessions'
            : 'slot único',
        evidence: clip('${ck2['raw']}', 160),
      );

      // shipping body carrier vs sealed hand
      final ckCar = await c.checkout(
        token: bJwt,
        buyer: bId,
        orderId: oid,
        extra: {'shipping_method': 'carrier'},
      );
      c.rec(
        id: 'G.checkout.carrier.vs.sealed.hand',
        surface: 'create-payment-intent',
        attack: 'body carrier, order selada mão',
        identity: 'buyer',
        httpCode: ckCar['http'] as int,
        result:
            'server=${c.serverAmount(ckCar) ?? 'n/a'} ${clip('${ckCar['raw']}', 100)}',
        impact: 'portes',
        evidence: clip('${ckCar['raw']}', 160),
      );
    }

    // order SEM shipping seal → body manda
    final o2 = await c.createOrder(
      token: bJwt,
      buyer: bId,
      seller: sId,
      productId: pCk,
      shipping: '',
    );
    // empty shipping might fail; try without key
    final oid2 = (o2['json'] is List && (o2['json'] as List).isNotEmpty)
        ? (o2['json'] as List).first['id']?.toString()
        : null;
    if (oid2 != null) {
      final row = await c.observeOrder(oid2);
      final ckH = await c.checkout(
        token: bJwt,
        buyer: bId,
        orderId: oid2,
        extra: {'shipping_method': 'hand'},
      );
      final ckC = await c.checkout(
        token: bJwt,
        buyer: bId,
        orderId: oid2,
        extra: {'shipping_method': 'carrier'},
      );
      c.rec(
        id: 'G.checkout.unsealed.ship.body',
        surface: 'create-payment-intent',
        attack: 'order.shipping vazio/fraco; body hand vs carrier',
        identity: 'buyer',
        httpCode: ckC['http'] as int,
        result:
            'sealed=${row['shipping_method']} hand=${c.serverAmount(ckH)}/${ckH['http']} carrier=${c.serverAmount(ckC)}/${ckC['http']}',
        impact: 'body portes',
        evidence:
            'row=${jsonEncode(row)} h=${clip('${ckH['raw']}', 80)} c=${clip('${ckC['raw']}', 80)}',
      );
    }
  }

  // observe leftover bag lines from pass1 if still in DB — new bag + refund A observe B
  final bag = await c.e2e({
    'probe': 'setup_paid_bag',
    'buyer_id': bId,
    'seller_id': sId,
  });
  if (bag['json'] is Map) {
    final bj = Map<String, dynamic>.from(bag['json'] as Map);
    final orders = (bj['orders'] as List?) ?? [];
    String? a;
    String? b;
    if (orders.length >= 2) {
      a = (orders[0] as Map)['id']?.toString();
      b = (orders[1] as Map)['id']?.toString();
    }
    if (a != null) {
      final ref = await c.edge('refund-order', token: sJwt, body: {'order_id': a});
      final ra = await c.observeOrder(a);
      final rb = b != null ? await c.observeOrder(b) : {};
      c.rec(
        id: 'G.bag.refund.A.observe.B',
        surface: 'refund-order bag',
        attack: 'refund linha A, estado B',
        identity: 'seller',
        httpCode: ref['http'] as int,
        result:
            'A status=${ra['status']} paid=${ra['amount_paid_cents']} refund=${ra['stripe_refund_id']} | B status=${rb['status']} paid=${rb['amount_paid_cents']} refund=${rb['stripe_refund_id']}',
        impact: (rb['status'] == 'cancelado' && ra['status'] == 'cancelado')
            ? 'refund A cancelou B'
            : 'isolamento linhas',
        sev: (rb['status'] == 'cancelado' && '${ref['raw']}'.contains('ok'))
            ? 'P1'
            : '—',
        evidence:
            'ref=${clip('${ref['raw']}', 160)} A=${jsonEncode(ra)} B=${jsonEncode(rb)}',
      );
    }
  }

  // -----------------------------------------------------------------------
  // H — offers, bundles, payout race, refund race, dispute cols
  // -----------------------------------------------------------------------
  final offerPid = await c.createProduct(
    token: sJwt,
    seller: sId,
    title: '$prefix offer 20€',
    price: 20,
    qty: 2,
  );
  if (offerPid != null) {
    final ins = await c.rest(
      'POST',
      'product_offers',
      token: bJwt,
      prefer: 'return=representation',
      body: {
        'product_id': offerPid,
        'buyer_id': bId,
        'seller_id': sId,
        'amount': 5,
        'quantity': 2,
        'status': 'pending',
      },
    );
    c.rec(
      id: 'H.offer.insert.buyer',
      surface: 'product_offers',
      attack: 'INSERT oferta 5€ qty=2 (catálogo 20€)',
      identity: 'buyer',
      httpCode: ins['http'] as int,
      result: clip('${ins['raw']}', 180),
      impact: (ins['http'] as int) < 300 ? 'oferta criada' : 'bloqueado',
      evidence: clip('${ins['raw']}', 200),
    );
    String? offerId;
    if (ins['json'] is List && (ins['json'] as List).isNotEmpty) {
      offerId = (ins['json'] as List).first['id']?.toString();
    }
    if (offerId != null) {
      final acc = await c.rest(
        'PATCH',
        'product_offers',
        token: sJwt,
        query: 'id=eq.$offerId',
        prefer: 'return=representation',
        body: {'status': 'accepted'},
      );
      c.rec(
        id: 'H.offer.accept.seller',
        surface: 'product_offers',
        attack: 'seller PATCH accepted',
        identity: 'seller',
        httpCode: acc['http'] as int,
        result: clip('${acc['raw']}', 160),
        impact: 'accept',
        evidence: clip('${acc['raw']}', 180),
      );
      final ord = await c.createOrder(
        token: bJwt,
        buyer: bId,
        seller: sId,
        productId: offerPid,
        qty: 2,
        extra: {'product_offer_id': offerId, 'price_total': 5},
      );
      final oid = (ord['json'] is List && (ord['json'] as List).isNotEmpty)
          ? (ord['json'] as List).first['id']?.toString()
          : null;
      final row = oid != null ? await c.observeOrder(oid) : {};
      c.rec(
        id: 'H.offer.order.contract',
        surface: 'orders',
        attack: 'order com offer aceite 5€ qty=2',
        identity: 'buyer',
        httpCode: ord['http'] as int,
        result: oid == null
            ? clip('${ord['raw']}', 160)
            : 'unit=${row['contract_unit_cents']} qty=${row['quantity']} total=${row['price_total']} offer=${row['product_offer_id']}',
        impact: (asNum(row['contract_unit_cents']) == 500)
            ? 'contrato=oferta'
            : 'contrato≠oferta ou fail',
        evidence: oid == null ? clip('${ord['raw']}') : jsonEncode(row),
      );
      if (oid != null) {
        final ck = await c.checkout(
          token: bJwt,
          buyer: bId,
          orderId: oid,
          extra: {'amount': 50, 'quantity': 1},
        );
        c.rec(
          id: 'H.offer.checkout.underpay',
          surface: 'create-payment-intent',
          attack: 'checkout oferta + amount=50 qty=1',
          identity: 'buyer',
          httpCode: ck['http'] as int,
          result: 'server=${c.serverAmount(ck)} ${clip('${ck['raw']}', 100)}',
          impact: 'quote oferta',
          evidence: clip('${ck['raw']}', 180),
        );
        // consume twice
        final ord2 = await c.createOrder(
          token: bJwt,
          buyer: bId,
          seller: sId,
          productId: offerPid,
          extra: {'product_offer_id': offerId},
        );
        c.rec(
          id: 'H.offer.reuse.consumed',
          surface: 'orders',
          attack: '2ª order mesma oferta aceite',
          identity: 'buyer',
          httpCode: ord2['http'] as int,
          result: clip('${ord2['raw']}', 160),
          impact: (ord2['http'] as int) < 300
              ? 'oferta reutilizada'
              : 'oneshot',
          sev: (ord2['http'] as int) < 300 ? 'P1' : '—',
          evidence: clip('${ord2['raw']}', 180),
        );
      }
    }
  }

  // payout race
  final keysSame = await Future.wait(List.generate(
    5,
    (_) => c.edge(
      'create-connect-account',
      token: sJwt,
      body: {
        'amount': 100,
        'idempotency_key': '${prefix}_pay_same',
      },
    ),
  ));
  c.rec(
    id: 'H.payout.race.same.key.x5',
    surface: 'create-connect-account',
    attack: '5× amount=100¢ mesma idempotency_key',
    identity: 'seller',
    httpCode: keysSame.first['http'] as int,
    result: keysSame.map((e) => '${e['http']}:${clip('${e['raw']}', 50)}').join(' | '),
    impact: 'idempotência payout',
    evidence: keysSame.map((e) => clip('${e['raw']}', 80)).join(' || '),
  );
  final keysDiff = await Future.wait(List.generate(
    5,
    (i) => c.edge(
      'create-connect-account',
      token: sJwt,
      body: {
        'amount': 50,
        'idempotency_key': '${prefix}_pay_diff_$i',
      },
    ),
  ));
  c.rec(
    id: 'H.payout.race.diff.keys.x5',
    surface: 'create-connect-account',
    attack: '5× amount=50¢ keys distintas (saldo limitado)',
    identity: 'seller',
    httpCode: keysDiff.first['http'] as int,
    result: keysDiff.map((e) => '${e['http']}:${clip('${e['raw']}', 50)}').join(' | '),
    impact: 'over-debit?',
    evidence: keysDiff.map((e) => clip('${e['raw']}', 80)).join(' || '),
  );

  // refund race on new paid order
  final paidR = await c.e2e({
    'probe': 'setup_paid_order',
    'buyer_id': bId,
    'seller_id': sId,
    'initial_qty': 2,
  });
  String? roid;
  if (paidR['json'] is Map) {
    roid = (paidR['json'] as Map)['order_id']?.toString();
    if (roid != null) c.createdOrderIds.add(roid);
  }
  if (roid != null) {
    final refs = await Future.wait(List.generate(
      6,
      (_) => c.edge('refund-order', token: sJwt, body: {'order_id': roid}),
    ));
    final row = await c.observeOrder(roid);
    c.rec(
      id: 'H.refund.race.x6',
      surface: 'refund-order',
      attack: '6 refund paralelos mesma order paga',
      identity: 'seller',
      httpCode: refs.first['http'] as int,
      result:
          'codes=${refs.map((e) => e['http']).toList()} status=${row['status']} refund=${row['stripe_refund_id']} paid=${row['amount_paid_cents']}',
      impact: 'idempotência refund',
      evidence: refs.map((e) => clip('${e['raw']}', 60)).join(' || '),
    );
  }

  // dispute schema
  final dispCols = await c.rest(
    'GET',
    'order_disputes',
    token: bJwt,
    query: 'select=*&limit=1',
  );
  c.rec(
    id: 'H.dispute.select.schema',
    surface: 'order_disputes',
    attack: 'GET select=* (colunas)',
    identity: 'buyer',
    httpCode: dispCols['http'] as int,
    result: clip('${dispCols['raw']}', 180),
    impact: 'schema',
    evidence: clip('${dispCols['raw']}', 200),
  );
  if (roid != null) {
    final d = await c.rest(
      'POST',
      'order_disputes',
      token: bJwt,
      prefer: 'return=representation',
      body: {
        'order_id': roid,
        'reason': prefix,
        'status': 'aberta',
      },
    );
    c.rec(
      id: 'H.dispute.insert.minimal',
      surface: 'order_disputes',
      attack: 'INSERT order_id+reason em order (talvez já cancelada)',
      identity: 'buyer',
      httpCode: d['http'] as int,
      result: clip('${d['raw']}', 180),
      impact: (d['http'] as int) < 300 ? 'disputa criada' : 'bloqueado',
      evidence: clip('${d['raw']}', 200),
    );
  }

  // bag composition: 2 products, mutate price of B after orders before checkout
  final ba = await c.createProduct(
      token: sJwt, seller: sId, title: '$prefix bagA', price: 4, qty: 2);
  final bb = await c.createProduct(
      token: sJwt, seller: sId, title: '$prefix bagB', price: 8, qty: 2);
  if (ba != null && bb != null) {
    final oa = await c.createOrder(
        token: bJwt, buyer: bId, seller: sId, productId: ba);
    final ob = await c.createOrder(
        token: bJwt, buyer: bId, seller: sId, productId: bb);
    final ida = (oa['json'] is List && (oa['json'] as List).isNotEmpty)
        ? (oa['json'] as List).first['id']?.toString()
        : null;
    final idb = (ob['json'] is List && (ob['json'] as List).isNotEmpty)
        ? (ob['json'] as List).first['id']?.toString()
        : null;
    await c.rest(
      'PATCH',
      'products',
      token: sJwt,
      query: 'id=eq.$bb',
      body: {'price': 1},
    );
    if (ida != null && idb != null) {
      final ck = await c.edge(
        'create-payment-intent',
        token: bJwt,
        body: {
          'buyer_id': bId,
          'bag_checkout': true,
          'shipping_method': 'hand',
          'bag_lines': [
            {'order_id': ida, 'line_total_cents': 1, 'quantity': 9},
            {
              'order_id': idb,
              'seller_id': sId,
              'line_total_cents': 1,
              'product_id': bb
            },
          ],
          'amount': 50,
        },
      );
      c.rec(
        id: 'H.bag.mutate.price.plus.hostile.lines',
        surface: 'create-payment-intent bag',
        attack: 'bag 2 orders; B price 8→1; line_total=1 qty=9 amount=50',
        identity: 'buyer',
        httpCode: ck['http'] as int,
        result: 'server=${c.serverAmount(ck)} ${clip('${ck['raw']}', 140)}',
        impact: (c.serverAmount(ck) != null && (c.serverAmount(ck)! < 500))
            ? 'bag underpay'
            : 'quote contrato',
        evidence: clip('${ck['raw']}', 200),
      );
    }
  }

  // Cross-user: fresh tries checkout of lab buyer order
  if (fJwt != null && c.createdOrderIds.isNotEmpty) {
    final victim = c.createdOrderIds.first;
    final ck = await c.checkout(
      token: fJwt,
      buyer: fId!,
      orderId: victim,
    );
    c.rec(
      id: 'H.checkout.foreign.order',
      surface: 'create-payment-intent',
      attack: 'fresh JWT checkout order do lab buyer',
      identity: 'fresh',
      httpCode: ck['http'] as int,
      result: clip('${ck['raw']}', 160),
      impact: ck['http'] == 200 ? 'paga order alheia' : 'bloqueado',
      sev: ck['http'] == 200 ? 'P1' : '—',
      evidence: clip('${ck['raw']}', 180),
    );
  }

  await c.dump('tool/redteam_parallel_c_20260831T0734/out/pass2.json');
  stdout.writeln(
      'pass2 hits=${c.hits.length} findings=${c.findings.length}');
  for (final h in c.hits) {
    stdout.writeln(
        '${h.sev == '—' ? '  ' : '!!'} ${h.id} http=${h.http} ${h.impact} :: ${h.result}');
  }
}
