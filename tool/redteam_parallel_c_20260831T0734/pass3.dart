/// Parallel C — Pass 3: fecho de poços + oferta + oversell estado final + payout Δ.
import 'dart:convert';
import 'dart:io';
import '_rtc.dart';

Future<void> main() async {
  final c = Rtc(loadEnv());
  await c.boot();
  final bJwt = c.buyerJwt!;
  final sJwt = c.sellerJwt!;
  final bId = c.buyerId!;
  final sId = c.sellerId!;
  Directory('tool/redteam_parallel_c_20260831T0734/out')
      .createSync(recursive: true);

  // ---- Oversell 2 PI: estado FINAL (não HTTP) ----
  final ov = await c.e2e({'buyer_id': bId, 'seller_id': sId});
  final ovj = ov['json'];
  Map<String, dynamic> ovMap = ovj is Map ? Map<String, dynamic>.from(ovj) : {};
  File('tool/redteam_parallel_c_20260831T0734/out/oversell.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(ovMap));
  final oa = ovMap['order_a_after'] ?? ovMap['order_a'];
  final ob = ovMap['order_b_after'] ?? ovMap['order_b'];
  final prod = ovMap['product_after'] ?? ovMap['stock_after_loser'] ?? ovMap['stock_after_winner'];
  c.rec(
    id: 'I.oversell.final.state',
    surface: 'e2e oversell',
    attack: '2 PI succeeded + 2 settle stock=1',
    identity: 'service_fixture',
    httpCode: ov['http'] as int,
    result:
        'ok=${ovMap['ok']} A=$oa B=$ob product=$prod winner=${ovMap['winner_pi']} loser=${ovMap['loser_pi']}',
    impact: '1 pago + 1 refund vs 2 pagos',
    evidence: jsonEncode({
      'ok': ovMap['ok'],
      'order_a_after': ovMap['order_a_after'],
      'order_b_after': ovMap['order_b_after'],
      'stock_after_winner': ovMap['stock_after_winner'],
      'stock_after_loser': ovMap['stock_after_loser'],
      'settle_a': ovMap['settle_a'],
      'settle_b': ovMap['settle_b'],
      'invariant': ovMap['invariant'] ?? ovMap['invariants'],
    }),
  );

  // ---- Offer oneshot (sem quantity) ----
  final opid = await c.createProduct(
    token: sJwt,
    seller: sId,
    title: '$prefix offer20',
    price: 20,
    qty: 2,
  );
  if (opid != null) {
    final ins = await c.rest(
      'POST',
      'product_offers',
      token: bJwt,
      prefer: 'return=representation',
      body: {
        'product_id': opid,
        'buyer_id': bId,
        'seller_id': sId,
        'amount': 5,
        'list_price': 20,
        'offered_by': 'buyer',
        'status': 'pending',
      },
    );
    c.rec(
      id: 'I.offer.insert',
      surface: 'product_offers',
      attack: 'INSERT amount=5 list=20',
      identity: 'buyer',
      httpCode: ins['http'] as int,
      result: clip('${ins['raw']}', 180),
      impact: (ins['http'] as int) < 300 ? 'criada' : 'bloqueado',
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
        body: {
          'status': 'accepted',
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      c.rec(
        id: 'I.offer.accept',
        surface: 'product_offers',
        attack: 'seller accepted+responded_at',
        identity: 'seller',
        httpCode: acc['http'] as int,
        result: clip('${acc['raw']}', 160),
        impact: 'accept',
        evidence: clip('${acc['raw']}', 180),
      );
      final o1 = await c.createOrder(
        token: bJwt,
        buyer: bId,
        seller: sId,
        productId: opid,
        extra: {'product_offer_id': offerId},
      );
      final oid1 = (o1['json'] is List && (o1['json'] as List).isNotEmpty)
          ? (o1['json'] as List).first['id']?.toString()
          : null;
      final r1 = oid1 != null ? await c.observeOrder(oid1) : {};
      c.rec(
        id: 'I.offer.order1.contract',
        surface: 'orders',
        attack: '1ª order da oferta 5€',
        identity: 'buyer',
        httpCode: o1['http'] as int,
        result: oid1 == null
            ? clip('${o1['raw']}', 160)
            : 'unit=${r1['contract_unit_cents']} qty=${r1['quantity']} total=${r1['price_total']}',
        impact: asNum(r1['contract_unit_cents']) == 500
            ? 'contrato=5€'
            : 'não selou oferta',
        evidence: oid1 == null ? clip('${o1['raw']}') : jsonEncode(r1),
      );
      if (oid1 != null) {
        final ck = await c.checkout(token: bJwt, buyer: bId, orderId: oid1);
        File('tool/redteam_parallel_c_20260831T0734/out/offer_checkout.json')
            .writeAsStringSync('${ck['raw']}');
        c.rec(
          id: 'I.offer.checkout',
          surface: 'create-payment-intent',
          attack: 'checkout order oferta',
          identity: 'buyer',
          httpCode: ck['http'] as int,
          result: 'raw_keys=${ck['json'] is Map ? (ck['json'] as Map).keys.toList() : 'n'} ${clip('${ck['raw']}', 140)}',
          impact: 'quote',
          evidence: clip('${ck['raw']}', 220),
        );
      }
      final o2 = await c.createOrder(
        token: bJwt,
        buyer: bId,
        seller: sId,
        productId: opid,
        extra: {'product_offer_id': offerId},
      );
      c.rec(
        id: 'I.offer.order2.reuse',
        surface: 'orders',
        attack: '2ª order mesma oferta',
        identity: 'buyer',
        httpCode: o2['http'] as int,
        result: clip('${o2['raw']}', 180),
        impact: (o2['http'] as int) < 300 ? 'reutilizou oferta' : 'oneshot',
        sev: (o2['http'] as int) < 300 ? 'P1' : '—',
        evidence: clip('${o2['raw']}', 200),
      );
    }
  }

  // ---- Unsealed shipping: DUAS orders independentes ----
  final sp = await c.createProduct(
    token: sJwt,
    seller: sId,
    title: '$prefix ship',
    price: 10,
    qty: 5,
  );
  if (sp != null) {
    Future<String?> mk() async {
      final r = await c.rest(
        'POST',
        'orders',
        token: bJwt,
        prefer: 'return=representation',
        body: {
          'buyer_id': bId,
          'seller_id': sId,
          'product_id': sp,
          'quantity': 1,
          'status': 'reserva_pendente',
          'payment_method': 'Pagamento na app',
        },
      );
      if (r['json'] is List && (r['json'] as List).isNotEmpty) {
        final id = (r['json'] as List).first['id']?.toString();
        if (id != null) c.createdOrderIds.add(id);
        return id;
      }
      c.notes.add('order no-ship fail ${clip('${r['raw']}', 120)}');
      return null;
    }

    final oh = await mk();
    final oc = await mk();
    if (oh != null) {
      final rh = await c.observeOrder(oh);
      final ckh = await c.checkout(
        token: bJwt,
        buyer: bId,
        orderId: oh,
        extra: {'shipping_method': 'hand'},
      );
      File('tool/redteam_parallel_c_20260831T0734/out/ck_hand.json')
          .writeAsStringSync('${ckh['raw']}');
      c.rec(
        id: 'I.ship.unsealed.hand',
        surface: 'create-payment-intent',
        attack: 'order sem shipping_method + body hand',
        identity: 'buyer',
        httpCode: ckh['http'] as int,
        result:
            'seal=${rh['shipping_method']} keys=${ckh['json'] is Map ? (ckh['json'] as Map).keys.toList() : ckh['http']} ${clip('${ckh['raw']}', 100)}',
        impact: 'quote hand',
        evidence: jsonEncode(rh),
      );
    }
    if (oc != null) {
      final rc = await c.observeOrder(oc);
      final ckc = await c.checkout(
        token: bJwt,
        buyer: bId,
        orderId: oc,
        extra: {'shipping_method': 'carrier'},
      );
      File('tool/redteam_parallel_c_20260831T0734/out/ck_carrier.json')
          .writeAsStringSync('${ckc['raw']}');
      c.rec(
        id: 'I.ship.unsealed.carrier',
        surface: 'create-payment-intent',
        attack: 'order SEM shipping + body carrier (order irmã, sem slot)',
        identity: 'buyer',
        httpCode: ckc['http'] as int,
        result:
            'seal=${rc['shipping_method']} ${clip('${ckc['raw']}', 140)}',
        impact: 'quote carrier',
        evidence: jsonEncode(rc),
      );
    }
  }

  // ---- Payout Δwallet vs nº Transfers únicos ----
  final w0 = await c.walletBalance(sId);
  final same = await Future.wait(List.generate(
    5,
    (_) => c.edge(
      'create-connect-account',
      token: sJwt,
      body: {'amount': 100, 'idempotency_key': '${prefix}_p3_same'},
    ),
  ));
  final w1 = await c.walletBalance(sId);
  final transfersSame = <String>{};
  for (final r in same) {
    final j = r['json'];
    if (j is Map && j['transferId'] != null) {
      transfersSame.add('${j['transferId']}');
    }
  }
  c.rec(
    id: 'I.payout.samekey.delta',
    surface: 'create-connect-account',
    attack: '5× 100¢ mesma key; Δwallet',
    identity: 'seller',
    httpCode: same.first['http'] as int,
    result:
        'w=$w0→$w1 unique_tr=${transfersSame.length} $transfersSame codes=${same.map((e) => e['http']).toList()}',
    impact: (transfersSame.length > 1)
        ? '2 Transfers mesma intenção'
        : '≤1 Transfer',
    sev: transfersSame.length > 1 ? 'P0' : '—',
    evidence: same.map((e) => clip('${e['raw']}', 90)).join(' || '),
  );

  final w2 = await c.walletBalance(sId);
  final diff = await Future.wait(List.generate(
    4,
    (i) => c.edge(
      'create-connect-account',
      token: sJwt,
      body: {'amount': 50, 'idempotency_key': '${prefix}_p3_d_$i'},
    ),
  ));
  final w3 = await c.walletBalance(sId);
  final trDiff = <String>{};
  for (final r in diff) {
    final j = r['json'];
    if (j is Map && j['transferId'] != null) trDiff.add('${j['transferId']}');
  }
  final debit = ((w2 ?? 0) - (w3 ?? 0));
  c.rec(
    id: 'I.payout.diffkey.delta',
    surface: 'create-connect-account',
    attack: '4× 50¢ keys distintas; Δwallet vs n Transfers',
    identity: 'seller',
    httpCode: 200,
    result:
        'w=$w2→$w3 debit=$debit unique_tr=${trDiff.length} $trDiff codes=${diff.map((e) => e['http']).toList()}',
    impact: (trDiff.length > 0 && debit > trDiff.length * 0.50 + 0.01)
        ? 'debit > transfers'
        : 'Δ≈n×0.50',
    sev: (debit > trDiff.length * 0.50 + 0.05) ? 'P1' : '—',
    evidence: diff.map((e) => clip('${e['raw']}', 90)).join(' || '),
  );

  // ---- GET settle body ----
  final gp = await c.createProduct(
      token: sJwt, seller: sId, title: '$prefix get', price: 5, qty: 1);
  if (gp != null) {
    final go = await c.createOrder(
      token: bJwt,
      buyer: bId,
      seller: sId,
      productId: gp,
      shipping: 'entrega em mão',
    );
    final gid = (go['json'] is List && (go['json'] as List).isNotEmpty)
        ? (go['json'] as List).first['id']?.toString()
        : null;
    if (gid != null) {
      final ck = await c.checkout(token: bJwt, buyer: bId, orderId: gid);
      final raw = '${ck['raw']}';
      final sid = RegExp(r'cs_test_[A-Za-z0-9]+').firstMatch(raw)?.group(0);
      if (sid != null) {
        final g = await c.edge(
          'create-payment-intent',
          method: 'GET',
          query: 'checkout_return=success&session_id=$sid',
        );
        File('tool/redteam_parallel_c_20260831T0734/out/settle_unpaid_body.txt')
            .writeAsStringSync('${g['http']}\n${g['raw']}');
        final row = await c.observeOrder(gid);
        c.rec(
          id: 'I.settle.unpaid.body',
          surface: 'GET settle',
          attack: '1× GET unpaid; corpo + estado',
          identity: 'anon',
          httpCode: g['http'] as int,
          result:
              'status=${row['status']} paid=${row['amount_paid_cents']} body=${clip('${g['raw']}', 160)}',
          impact: row['status'] == 'pago' ? 'liquidou' : 'não liquidou',
          evidence: clip('${g['raw']}', 200),
        );
      }
    }
  }

  // ---- Dispute on FRESH paid order ----
  final paid = await c.e2e({
    'probe': 'setup_paid_order',
    'buyer_id': bId,
    'seller_id': sId,
    'initial_qty': 2,
  });
  String? poid;
  if (paid['json'] is Map) {
    poid = (paid['json'] as Map)['order_id']?.toString();
    if (poid != null) c.createdOrderIds.add(poid);
  }
  if (poid != null) {
    final d = await c.rest(
      'POST',
      'order_disputes',
      token: bJwt,
      prefer: 'return=representation',
      body: {
        'order_id': poid,
        'buyer_id': bId,
        'reason': 'nao_corresponde',
        'description': prefix,
      },
    );
    c.rec(
      id: 'I.dispute.paid.order',
      surface: 'order_disputes',
      attack: 'INSERT disputa order pago Stripe',
      identity: 'buyer',
      httpCode: d['http'] as int,
      result: clip('${d['raw']}', 180),
      impact: (d['http'] as int) < 300 ? 'aberta' : 'bloqueado',
      evidence: clip('${d['raw']}', 200),
    );
    String? did;
    if (d['json'] is List && (d['json'] as List).isNotEmpty) {
      did = (d['json'] as List).first['id']?.toString();
    }
    if (did != null) {
      final wB0 = await c.walletBalance(bId);
      final close = await c.rest(
        'PATCH',
        'order_disputes',
        token: sJwt,
        query: 'id=eq.$did',
        prefer: 'return=representation',
        body: {'status': 'resolvida'},
      );
      final closeB = await c.rest(
        'PATCH',
        'order_disputes',
        token: bJwt,
        query: 'id=eq.$did',
        prefer: 'return=representation',
        body: {'status': 'resolvida', 'seller_offer_amount': 100},
      );
      final wB1 = await c.walletBalance(bId);
      final txs = await c.walletTx(orderId: poid);
      c.rec(
        id: 'I.dispute.close.wallet',
        surface: 'order_disputes',
        attack: 'seller/buyer PATCH resolvida + offer 100',
        identity: 'conluio',
        httpCode: closeB['http'] as int,
        result:
            'seller=${close['http']} ${clip('${close['raw']}', 60)} buyer=${closeB['http']} ${clip('${closeB['raw']}', 80)} Δb=$wB0→$wB1 txs=${txs.length}',
        impact: ((wB1 ?? 0) > (wB0 ?? 0)) ? 'mint disputa' : 'sem mint',
        sev: ((wB1 ?? 0) > (wB0 ?? 0)) ? 'P0' : '—',
        evidence: 's=${clip('${close['raw']}', 120)} b=${clip('${closeB['raw']}', 120)}',
      );
    }
  }

  // ---- Live tip: procurar live do seller ----
  final lives = await c.rest(
    'GET',
    'lives',
    token: sJwt,
    query: 'seller_id=eq.$sId&select=id,status,is_active&limit=3&order=created_at.desc',
  );
  c.rec(
    id: 'I.lives.list',
    surface: 'lives',
    attack: 'listar lives seller',
    identity: 'seller',
    httpCode: lives['http'] as int,
    result: clip('${lives['raw']}', 180),
    impact: 'enum',
    evidence: clip('${lives['raw']}', 200),
  );
  String? liveId;
  if (lives['json'] is List && (lives['json'] as List).isNotEmpty) {
    liveId = (lives['json'] as List).first['id']?.toString();
  }
  if (liveId != null) {
    final tip = await c.edge(
      'create-live-tip-checkout',
      token: bJwt,
      body: {'seller_id': sId, 'amount_eur': 1, 'live_id': liveId},
    );
    c.rec(
      id: 'I.tip.real.live',
      surface: 'create-live-tip-checkout',
      attack: 'tip 1€ live existente',
      identity: 'buyer',
      httpCode: tip['http'] as int,
      result: clip('${tip['raw']}', 180),
      impact: tip['http'] == 200 ? 'Session tip' : 'bloqueado',
      evidence: clip('${tip['raw']}', 200),
    );
    final tipWal = await c.rpc(
      'batata_send_live_tip_from_wallet',
      {'p_live_id': liveId, 'p_seller_id': sId, 'p_amount': 1},
      token: bJwt,
    );
    c.rec(
      id: 'I.tip.wallet.debit',
      surface: 'rpc/batata_send_live_tip_from_wallet',
      attack: 'tip 1€ da wallet buyer',
      identity: 'buyer',
      httpCode: tipWal['http'] as int,
      result: clip('${tipWal['raw']}', 180),
      impact: 'wallet tip',
      evidence: clip('${tipWal['raw']}', 200),
    );
  }

  // ---- Cleanup RTC fixtures (products we created with prefix; cancel pending orders) ----
  for (final oid in c.createdOrderIds) {
    await c.rest(
      'PATCH',
      'orders',
      service: true,
      query: 'id=eq.$oid',
      body: {'status': 'cancelado'},
    );
  }
  for (final pid in c.createdProductIds) {
    await c.rest(
      'PATCH',
      'products',
      service: true,
      query: 'id=eq.$pid',
      body: {'list_on_marketplace': false, 'is_sold': true},
    );
  }

  await c.dump('tool/redteam_parallel_c_20260831T0734/out/pass3.json');
  stdout.writeln('pass3 hits=${c.hits.length} findings=${c.findings.length}');
  for (final h in c.hits) {
    stdout.writeln(
        '${h.sev == '—' ? '  ' : '!!'} ${h.id} http=${h.http} ${h.impact} :: ${h.result}');
  }
}
