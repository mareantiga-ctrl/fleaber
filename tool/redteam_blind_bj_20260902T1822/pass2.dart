/// PASS 2 — BJ3 release+refund · BJ5 unship/FSM · BJ6 actor cruzado · BJ7 Δwallet.
/// Novas: release sem mão, refund parcial>captura no body, buyer refund, clawback JWT.
import 'dart:io';
import '_rtbj.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rtbj.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final wStart = await c.wallets();
  c.note('p2.start', 'saldos', wStart, lens: 'BJ7');

  // ---- BJ5: shipping "entrega em morada" classificado como mão? ----
  final pidMorada = await c.insertProduct(
    price: 6.5,
    title: '$prefix-morada',
  );
  String? oidMorada;
  if (pidMorada != null) {
    oidMorada = await c.insertOrder(
      productId: pidMorada,
      priceTotal: 6.5,
      shipping: 'entrega em morada',
    );
  }
  c.note('p2.morada.insert', 'order shipping=entrega em morada', oidMorada,
      lens: 'BJ5');
  if (oidMorada != null) {
    final row0 = await c.orderRow(oidMorada);
    c.note('p2.morada.row', 'row após INSERT', row0, lens: 'BJ5');
    final cpi = await c.edge('create-payment-intent', body: {
      'order_id': oidMorada,
      'shipping_method': 'entrega em morada',
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
    }, jwt: c.buyerJwt);
    c.note('p2.morada.cpi', 'CPI com entrega em morada', cpi.brief, lens: 'BJ5');

    final isHand = await c.rpc(
      'batata_shipping_method_is_hand',
      {'p_method': 'entrega em morada'},
      jwt: c.buyerJwt,
    );
    c.note('p2.morada.is_hand', 'rpc is_hand(entrega em morada)', isHand.brief,
        lens: 'BJ5');
    if (isHand.ok && isHand.json == true) {
      c.hold(
        id: 'BJ5-01-morada-is-hand',
        lens: 'BJ5',
        severity: 'P1',
        title: '"entrega em morada" classificada como entrega em mão',
        actor: 'buyer JWT rpc',
        pre: 'LIKE entrega em m% cobre morada/mail/MRW',
        repro: 'rpc batata_shipping_method_is_hand("entrega em morada")',
        expected: 'false (carrier)',
        obtained: isHand.brief,
        evidence: {
          'order_id': oidMorada,
          'cpi': cpi.brief,
          'shipping': row0?['shipping_method'],
        },
      );
    } else {
      c.block('BJ5-01-morada-is-hand', 'BJ5', 'is_hand morada', isHand);
    }
  }

  // Homoglyph / LIKE extras
  for (final ship in [
    'mao CTT Expresso',
    'hand-ctt',
    'entrega em mota',
    'ENTREGA EM MORADA',
  ]) {
    final h = await c.rpc(
      'batata_shipping_method_is_hand',
      {'p_method': ship},
      jwt: c.buyerJwt,
    );
    c.note('p2.hand.$ship', 'is_hand($ship)', h.brief, lens: 'BJ5');
    if (h.ok && h.json == true) {
      c.hold(
        id: 'BJ5-02-hand-like-$ship',
        lens: 'BJ5',
        severity: 'P1',
        title: 'shipping "$ship" classificado como mão',
        actor: 'buyer JWT',
        pre: 'prefix LIKE mao%/hand%/entrega em m%',
        repro: 'rpc batata_shipping_method_is_hand("$ship")',
        expected: 'false',
        obtained: h.brief,
      );
    } else {
      c.block('BJ5-02-$ship', 'BJ5', 'is_hand $ship', h);
    }
  }

  // ---- Paid order fixture ----
  final oid = await c.payOrder(lens: 'BJ3');
  if (oid == null) {
    stderr.writeln('setup_paid_order failed');
    await c.dumpAll('pass2.json');
    return;
  }
  var row = await c.orderRow(oid);
  c.note('p2.paid', 'order pago', row, lens: 'BJ3');

  // Buyer tenta freeze bypass: PATCH shipping após pago
  final shipAfterPay = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'shipping_method': 'entrega em morada'},
  );
  await c.expectDenied(
    id: 'BJ5-03-ship-after-pay',
    lens: 'BJ5',
    title: 'Buyer muda shipping para morada após pago',
    hit: shipAfterPay,
    actor: 'buyer JWT',
    pre: 'order_shipping_frozen_after_payment',
    repro: 'PATCH shipping_method=entrega em morada status=pago',
    severityIfOpen: 'P1',
  );

  // Release SEM mão / SEM enviado (status ainda pago, shipping null)
  final relPago = await c.tryRelease(oid, jwt: c.buyerJwt);
  c.note('p2.release.pago', 'release em pago sem shipped', relPago.brief,
      lens: 'BJ3');
  if (relPago.ok && relPago.json == true) {
    c.hold(
      id: 'BJ3-01-release-while-pago',
      lens: 'BJ3',
      severity: 'P0',
      title: 'Release creditou seller com encomenda ainda em pago',
      actor: 'buyer JWT',
      pre: 'exige concluido + (shipped_at ou mão)',
      repro: 'rpc batata_release_seller_wallet_for_order em pago',
      expected: 'false',
      obtained: relPago.brief,
    );
  } else {
    c.block('BJ3-01-release-while-pago', 'BJ3', 'release em pago', relPago);
  }

  // Buyer concluido directo de pago (CTT/null — não é mão)
  final conclPago = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'status': 'concluido'},
  );
  await c.expectDenied(
    id: 'BJ5-04-concluido-sem-mao',
    lens: 'BJ5',
    title: 'Buyer marca concluido a partir de pago sem mão/envio',
    hit: conclPago,
    actor: 'buyer JWT',
    pre: 'order_concluido_requires_shipped',
    repro: 'PATCH status=concluido (pago, shipping null/CTT)',
    severityIfOpen: 'P0',
  );

  // Seller unship: shipped_at=null (JWT)
  final unshipJwt = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.sellerJwt,
    body: {'shipped_at': null, 'status': 'pago'},
  );
  c.note('p2.unship.jwt', 'seller unship JWT', unshipJwt.brief, lens: 'BJ5');
  if (unshipJwt.ok) {
    c.hold(
      id: 'BJ5-05-unship-jwt',
      lens: 'BJ5',
      severity: 'P1',
      title: 'Seller JWT apagou shipped_at / reverteu para pago',
      actor: 'seller JWT',
      pre: 'shipped_at imutável ATBE',
      repro: 'PATCH shipped_at=null status=pago',
      expected: '42501',
      obtained: unshipJwt.brief,
    );
  } else {
    c.block('BJ5-05-unship-jwt', 'BJ5', 'unship JWT', unshipJwt);
  }

  // Buyer refund-order (BJ6)
  final buyerRef = await c.refundOrder(oid, jwt: c.buyerJwt);
  await c.expectDenied(
    id: 'BJ6-01-buyer-refund',
    lens: 'BJ6',
    title: 'Buyer disparou refund-order',
    hit: buyerRef,
    actor: 'buyer JWT',
    pre: 'Edge exige seller_id == JWT',
    repro: 'POST refund-order JWT=buyer',
    severityIfOpen: 'P0',
    isSuccess: (h) => h.ok && h.map?['ok'] == true && h.map?['skipped'] != true,
  );

  if (c.buyer2Jwt != null) {
    final b2ref = await c.refundOrder(oid, jwt: c.buyer2Jwt);
    await c.expectDenied(
      id: 'BJ6-02-b2-refund',
      lens: 'BJ6',
      title: 'B2 refund-order da venda B1',
      hit: b2ref,
      actor: 'buyer2 JWT',
      pre: 'cross-user',
      repro: 'POST refund-order JWT=B2',
      severityIfOpen: 'P0',
      isSuccess: (h) =>
          h.ok && h.map?['ok'] == true && h.map?['skipped'] != true,
    );
  }

  if (c.seller2Jwt != null) {
    final s2ref = await c.refundOrder(oid, jwt: c.seller2Jwt);
    await c.expectDenied(
      id: 'BJ6-03-s2-refund',
      lens: 'BJ6',
      title: 'S2 refund-order da venda S1',
      hit: s2ref,
      actor: 'seller2 JWT',
      pre: 'seller_id ≠ S2',
      repro: 'POST refund-order JWT=S2',
      severityIfOpen: 'P0',
      isSuccess: (h) =>
          h.ok && h.map?['ok'] == true && h.map?['skipped'] != true,
    );
  }

  // Refund parcial > captura via body (Edge deve ignorar amount)
  final overRef = await c.refundOrder(oid, extraBody: {
    'amount': 999999,
    'amount_cents': 999999,
    'partial': true,
  });
  c.note('p2.refund.body-amount', 'refund-order amount=999999 no body',
      overRef.brief, lens: 'BJ3');
  row = await c.orderRow(oid);
  final piAmt = numOf(row?['amount_paid_cents']) ?? 0;
  if (overRef.ok &&
      overRef.map?['ok'] == true &&
      (numOf(overRef.map?['amount_cents']) ?? 0) > piAmt &&
      piAmt > 0) {
    c.hold(
      id: 'BJ3-02-refund-gt-capture',
      lens: 'BJ3',
      severity: 'P0',
      title: 'refund-order reembolsou mais do que a captura',
      actor: 'seller JWT',
      pre: 'body amount ignorado; cap remaining',
      repro: 'POST refund-order amount=999999',
      expected: 'amount_cents ≤ amount_paid_cents',
      obtained: {
        'refund': overRef.brief,
        'paid_cents': piAmt,
        'order': row,
      },
    );
  } else if (overRef.ok && overRef.map?['ok'] == true) {
    c.note('p2.refund.pago.ok', 'seller refund em pago (legítimo)', overRef.brief,
        lens: 'BJ3');
    final st = '${row?['status']}'.toLowerCase();
    if (st != 'cancelado' && st != 'cancelled' && st != 'devolvida') {
      c.note('p2.refund.status', 'status pós-refund', st, lens: 'BJ5');
    }
  } else {
    c.note('p2.refund.denied-or-skip', 'refund body amount', overRef.brief,
        lens: 'BJ3');
  }

  // Clawback JWT sobre esta order
  final clawJwt = await c.rpc(
    'batata_clawback_seller_wallet_for_order',
    {'p_order_id': oid},
    jwt: c.buyerJwt,
  );
  c.note('p2.claw.jwt', 'buyer JWT clawback', clawJwt.brief, lens: 'BJ3');
  final clawNum = clawJwt.json is num ? clawJwt.json as num : numOf(clawJwt.json);
  if (clawJwt.ok && clawNum != null && clawNum > 0) {
    c.hold(
      id: 'BJ3-03-jwt-clawback',
      lens: 'BJ3',
      severity: 'P0',
      title: 'JWT clawback debitou carteira do vendedor',
      actor: 'buyer JWT',
      pre: 'GRANT só service_role',
      repro: 'rpc batata_clawback_seller_wallet_for_order',
      expected: '403',
      obtained: clawJwt.brief,
    );
  } else {
    c.block('BJ3-03-jwt-clawback', 'BJ3', 'JWT clawback', clawJwt);
  }

  // ---- 2.ª order: caminho CTT enviado → concluido → release → refund ----
  final oid2 = await c.payOrder(lens: 'BJ3');
  if (oid2 != null) {
    await c.rest('PATCH', 'orders?id=eq.$oid2', jwt: c.sellerJwt, body: {
      'shipping_method': 'CTT Expresso',
    });
    final envio = await c.rest(
      'PATCH',
      'orders?id=eq.$oid2',
      jwt: c.sellerJwt,
      body: {'status': 'enviado'},
    );
    c.note('p2.oid2.enviado', 'seller marca enviado', envio.brief, lens: 'BJ5');
    final afterShip = await c.orderRow(oid2);
    c.note('p2.oid2.shipped_at', 'shipped_at após enviado',
        afterShip?['shipped_at'], lens: 'BJ5');

    final relS = await c.tryRelease(oid2, jwt: c.sellerJwt);
    c.note('p2.oid2.release_seller', 'seller self-release em enviado',
        relS.brief, lens: 'BJ3');
    if (relS.ok && relS.json == true) {
      c.hold(
        id: 'BJ3-04-seller-self-release',
        lens: 'BJ3',
        severity: 'P1',
        title: 'Vendedor libertou a própria carteira (JWT)',
        actor: 'seller JWT',
        pre: 'release só buyer/admin/service; status ainda enviado',
        repro: 'rpc batata_release_seller_wallet_for_order JWT=seller',
        expected: 'false',
        obtained: relS.brief,
      );
    } else {
      c.block('BJ3-04-seller-self-release', 'BJ3', 'seller self-release', relS);
    }

    if (c.buyer2Jwt != null) {
      final relB2 = await c.tryRelease(oid2, jwt: c.buyer2Jwt);
      if (relB2.ok && relB2.json == true) {
        c.hold(
          id: 'BJ6-04-b2-release',
          lens: 'BJ6',
          severity: 'P0',
          title: 'B2 libertou carteira da venda B1',
          actor: 'buyer2 JWT',
          pre: 'auth.uid ≠ buyer_id',
          repro: 'rpc release JWT=B2',
          expected: 'false',
          obtained: relB2.brief,
        );
      } else {
        c.block('BJ6-04-b2-release', 'BJ6', 'B2 release', relB2);
      }
    }

    final concl = await c.rest(
      'PATCH',
      'orders?id=eq.$oid2',
      jwt: c.buyerJwt,
      body: {'status': 'concluido'},
    );
    c.note('p2.oid2.concluido', 'buyer concluido após enviado', concl.brief,
        lens: 'BJ5');

    final sellerBefore = await c.walletBal(c.sellerId);
    final relB = await c.tryRelease(oid2, jwt: c.buyerJwt);
    c.note('p2.oid2.release_buyer', 'buyer release', relB.brief, lens: 'BJ3');
    var released = relB.ok && relB.json == true;
    if (!released) {
      final relSvc = await c.tryRelease(oid2, service: true);
      c.note('p2.oid2.release_svc', 'service_role release', relSvc.brief,
          lens: 'BJ3');
      released = relSvc.ok && relSvc.json == true;
    }
    final sellerAfter = await c.walletBal(c.sellerId);
    final delta = sellerAfter - sellerBefore;
    c.note('p2.oid2.delta', 'Δ seller wallet após release', {
      'before': sellerBefore,
      'after': sellerAfter,
      'delta': delta,
      'released': released,
    }, lens: 'BJ7');

    // Refund após release
    final refAfter = await c.refundOrder(oid2);
    c.note('p2.oid2.refund_after_release', 'refund-order pós-release',
        refAfter.brief, lens: 'BJ3');
    final sellerAfterRef = await c.walletBal(c.sellerId);
    final clawAfter = await c.rpc(
      'batata_clawback_seller_wallet_for_order',
      {'p_order_id': oid2},
      service: true,
    );
    c.note('p2.oid2.claw_svc', 'clawback service_role (observação)',
        clawAfter.brief, lens: 'BJ3');
    final sellerFinal = await c.walletBal(c.sellerId);
    c.note('p2.oid2.net', 'seller após refund+clawback', {
      'after_release': sellerAfter,
      'after_refund_edge': sellerAfterRef,
      'after_claw_svc': sellerFinal,
      'delta_vs_before_release': sellerFinal - sellerBefore,
    }, lens: 'BJ7');

    if (released &&
        refAfter.ok &&
        refAfter.map?['ok'] == true &&
        (sellerFinal - sellerBefore) > 0.05) {
      c.hold(
        id: 'BJ3-05-release-refund-net',
        lens: 'BJ3',
        severity: 'P0',
        title: 'Release + refund deixou seller com saldo líquido positivo da venda',
        actor: 'buyer release · seller refund-order',
        pre: 'clawback deveria anular crédito venda',
        repro: 'concluido → release → refund-order',
        expected: 'Δ seller ≈ 0 após clawback',
        obtained: {
          'delta_final': sellerFinal - sellerBefore,
          'refund': refAfter.brief,
          'claw': clawAfter.brief,
        },
      );
    } else if (released) {
      c.block('BJ3-05-release-refund-net', 'BJ3', 'net seller pós refund', {
        'delta': sellerFinal - sellerBefore,
        'refund': refAfter.brief,
      });
    }

    // Hop pós-refund (ATBE exacto — não contar)
    final hop = await c.rest(
      'PATCH',
      'orders?id=eq.$oid2',
      jwt: c.sellerJwt,
      body: {'status': 'enviado'},
    );
    c.note('p2.exacto.hop', 'ATBE exacto hop enviado pós-refund', hop.brief,
        lens: 'BJ5');
  }

  // Buyer ledger alheio
  final ledgerB = await c.rest(
    'GET',
    'wallet_payout_ledger?user_id=eq.${c.sellerId}&select=idempotency_key,amount_cents,status,stripe_transfer_id&limit=3',
    jwt: c.buyerJwt,
  );
  c.note('p2.ledger.buyer', 'buyer GET ledger seller', ledgerB.brief, lens: 'BJ6');
  if (ledgerB.ok && ledgerB.list.isNotEmpty) {
    c.hold(
      id: 'BJ6-05-buyer-read-payout-ledger',
      lens: 'BJ6',
      severity: 'P2',
      title: 'Buyer leu wallet_payout_ledger do vendedor',
      actor: 'buyer JWT',
      pre: 'RLS user_id = auth.uid()',
      repro: 'GET wallet_payout_ledger?user_id=eq.seller',
      expected: '[] / 401',
      obtained: ledgerB.brief,
    );
  } else {
    c.block('BJ6-05-buyer-read-payout-ledger', 'BJ6', 'buyer ledger seller',
        ledgerB);
  }

  final wEnd = await c.wallets();
  c.note('p2.end', 'saldos fim', wEnd, lens: 'BJ7');
  await c.dumpAll('pass2.json');
  stdout.writeln('PASS2 findings=${c.findings.length} blocked=${c.blocked.length}');
}
