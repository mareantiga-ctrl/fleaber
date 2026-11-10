/// PASS 2 — Stripe TEST pago + release/refund/payout. Variantes novas. Não corrige.
/// dart run tool/redteam_blind_bd_20260902T1608/pass2.dart
import '_rtbd.dart';

Future<void> main() async {
  final c = Rtbd.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final paid = await c.payToPago(lens: 'BD3');
  if (paid == null) {
    c.skip('BD3.fixture', 'BD3', 'setup_paid_order falhou', 'null');
    await c.dumpAll('pass2.json');
    return;
  }
  final oid = paid.oid;
  final pi = paid.pi;
  var row = await c.orderRow(oid);
  c.note('bd3.paid.row', 'order pago', row, lens: 'BD3');
  final wBefore = await c.walletsSnap();

  // BD3 — release mentiroso: freeze shipping, unship, skip ship, seller/buyer2
  final shipFreeze = await c.patchOrder(
    oid,
    {'shipping_method': 'entrega em mão'},
    jwt: c.buyerJwt,
  );
  c.note('bd3.ship.freeze', 'buyer PATCH mão pós-pago', shipFreeze.brief,
      lens: 'BD3');
  final rowShip = await c.orderRow(oid);
  if (c.looksHand(rowShip?['shipping_method']) &&
      !c.looksHand(row?['shipping_method'])) {
    c.finding(
      id: 'BD3-ship-unfreeze',
      lens: 'BD3',
      severity: 'P1',
      title: 'Buyer descongelou shipping_method para mão após captura',
      actor: 'buyer JWT',
      pre: 'order pago shipping=${row?['shipping_method']}',
      repro: 'PATCH orders shipping_method=entrega em mão',
      expected: 'order_shipping_frozen_after_payment',
      obtained: rowShip?['shipping_method'],
    );
  } else {
    c.block('BD3.ship.freeze', 'BD3', 'shipping selado pós-pago', shipFreeze);
  }

  final unship = await c.patchOrder(oid, {'shipped_at': null}, jwt: c.sellerJwt);
  c.note('bd3.unship', 'seller PATCH shipped_at=null', unship.brief, lens: 'BD3');
  if (unship.ok && !unship.body.contains('42501')) {
    final r = await c.orderRow(oid);
    if (r?['shipped_at'] == null && row?['shipped_at'] != null) {
      c.finding(
        id: 'BD3-unship',
        lens: 'BD3',
        severity: 'P1',
        title: 'Seller fez unship (shipped_at=null) via JWT',
        actor: 'seller JWT',
        pre: 'shipped_at selado ANAS',
        repro: 'PATCH orders shipped_at=null',
        expected: 'order_shipped_at_immutable 403',
        obtained: r?['shipped_at'],
      );
    } else {
      c.block('BD3.unship', 'BD3', 'unship sem efeito / 403', unship);
    }
  } else {
    c.block('BD3.unship', 'BD3', 'unship 403', unship);
  }

  final skipConcl = await c.patchOrder(oid, {'status': 'concluido'},
      jwt: c.buyerJwt);
  c.note('bd3.concluido.skip_ship', 'buyer concluido sem enviado',
      skipConcl.brief,
      lens: 'BD3');
  row = await c.orderRow(oid);
  if (row?['status'] == 'concluido' && row?['shipped_at'] == null) {
    c.finding(
      id: 'BD3-concluido-no-ship',
      lens: 'BD3',
      severity: 'P1',
      title: 'Buyer marcou concluido sem envio em encomenda não-mão',
      actor: 'buyer JWT',
      pre: 'pago sem shipped_at',
      repro: 'PATCH status=concluido',
      expected: 'order_concluido_requires_shipped',
      obtained: row?['status'],
    );
  } else {
    c.block('BD3.concluido.skip', 'BD3', 'concluido sem envio bloqueado',
        skipConcl);
  }

  final relEarly = await c.release(oid, jwt: c.buyerJwt);
  c.note('bd3.release.early', 'release ainda não concluido/sem ship',
      relEarly.brief,
      lens: 'BD3');
  final wEarly = await c.walletsSnap();
  final dEarly = (wEarly['seller'] ?? 0) - (wBefore['seller'] ?? 0);
  if (relEarly.body.trim() == 'true' ||
      (relEarly.map == true) ||
      dEarly > 0.009) {
    c.finding(
      id: 'BD3-release-early',
      lens: 'BD3',
      severity: 'P0',
      title: 'Release creditou carteira sem envio/concluido',
      actor: 'buyer JWT',
      pre: 'status=${row?['status']} shipped_at=${row?['shipped_at']}',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false / Δwallet=0',
      obtained: {'rpc': relEarly.brief, 'dSeller': dEarly},
    );
  } else {
    c.block('BD3.release.early', 'BD3', 'release cedo = false', relEarly);
  }

  final relSeller = await c.release(oid, jwt: c.sellerJwt);
  c.note('bd3.release.seller', 'seller chama release (deveria ser buyer)',
      relSeller.brief,
      lens: 'BD3');
  if (relSeller.body.trim() == 'true') {
    c.finding(
      id: 'BD3-release-seller',
      lens: 'BD3',
      severity: 'P1',
      title: 'Seller JWT libertou a própria carteira (autoridade buyer)',
      actor: 'seller JWT',
      pre: 'auth.uid=seller',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false',
      obtained: relSeller.brief,
    );
  } else {
    c.block('BD3.release.seller', 'BD3', 'seller release = false', relSeller);
  }

  final relB2 = await c.release(oid, jwt: c.buyer2Jwt);
  c.note('bd3.release.b2', 'buyer2 release order alheia', relB2.brief,
      lens: 'BD3');
  if (relB2.body.trim() == 'true') {
    c.finding(
      id: 'BD3-release-cross',
      lens: 'BD3',
      severity: 'P0',
      title: 'Buyer2 libertou encomenda alheia',
      actor: 'buyer2 JWT',
      pre: 'order buyer1',
      repro: 'rpc release p_order_id=alheio',
      expected: 'false',
      obtained: relB2.brief,
    );
  } else {
    c.block('BD3.release.b2', 'BD3', 'buyer2 release = false', relB2);
  }

  final fakeRef = await c.patchOrder(
    oid,
    {'stripe_refund_id': 're_fake_bd_$stamp'},
    jwt: c.sellerJwt,
  );
  c.note('bd4.patch.refund_id', 'seller PATCH stripe_refund_id fake',
      fakeRef.brief,
      lens: 'BD4');
  row = await c.orderRow(oid);
  if (row?['stripe_refund_id'] == 're_fake_bd_$stamp') {
    c.finding(
      id: 'BD4-patch-refund-id',
      lens: 'BD4',
      severity: 'P1',
      title: 'Seller selou stripe_refund_id forjado via REST',
      actor: 'seller JWT',
      pre: 'order pago',
      repro: 'PATCH orders stripe_refund_id=re_fake',
      expected: 'campo imutável / 0 rows',
      obtained: row?['stripe_refund_id'],
    );
  } else {
    c.block('BD4.patch.refund_id', 'BD4', 'stripe_refund_id imutável', fakeRef);
  }

  // BD4 — refund mentiroso
  final buyerRef = await c.refund(oid, jwt: c.buyerJwt);
  c.note('bd4.refund.buyer', 'buyer chama refund-order', buyerRef.brief,
      lens: 'BD4');
  if (buyerRef.ok &&
      buyerRef.map?['ok'] == true &&
      buyerRef.map?['skipped'] != true) {
    c.finding(
      id: 'BD4-buyer-refund',
      lens: 'BD4',
      severity: 'P0',
      title: 'Buyer forçou refund-order (seller-only)',
      actor: 'buyer JWT',
      pre: 'order pago PI=$pi',
      repro: 'POST refund-order order_id',
      expected: '403 Sem permissão',
      obtained: buyerRef.brief,
    );
  } else {
    c.block('BD4.refund.buyer', 'BD4', 'buyer refund 403', buyerRef);
  }

  final amtRef = await c.refund(oid, extra: {
    'amount': 99999,
    'amount_cents': 99999,
    'refund_amount': 999.99,
  });
  c.note('bd4.refund.amount', 'refund-order extra amount 99999', amtRef.brief,
      lens: 'BD4');
  if (amtRef.ok &&
      amtRef.map?['ok'] == true &&
      (numOf(amtRef.map?['amount_cents']) ?? 0) > 50000) {
    c.finding(
      id: 'BD4-refund-over-capture',
      lens: 'BD4',
      severity: 'P0',
      title: 'refund-order aceitou amount cliente > captura',
      actor: 'seller JWT',
      pre: 'PI pago',
      repro: 'POST refund-order amount=99999',
      expected: 'ignorar amount; refund ≤ captura',
      obtained: amtRef.brief,
    );
  } else {
    c.block('BD4.refund.amount', 'BD4', 'amount extra ignorado/bloqueado',
        amtRef);
  }

  final b2ref = await c.refund(oid, jwt: c.buyer2Jwt);
  c.note('bd4.refund.b2', 'buyer2 refund alheio', b2ref.brief, lens: 'BD4');
  if (b2ref.ok && b2ref.map?['ok'] == true && b2ref.map?['skipped'] != true) {
    c.finding(
      id: 'BD4-refund-cross',
      lens: 'BD4',
      severity: 'P0',
      title: 'Buyer2 reembolsou encomenda alheia',
      actor: 'buyer2 JWT',
      pre: 'order buyer1/seller1',
      repro: 'POST refund-order',
      expected: '403',
      obtained: b2ref.brief,
    );
  } else {
    c.block('BD4.refund.b2', 'BD4', 'buyer2 refund 403', b2ref);
  }

  // Caminho feliz mínimo: enviado → entregue → concluido → release
  final envio = await c.patchOrder(oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  c.note('bd7.hop.enviado', 'seller enviado', envio.brief, lens: 'BD7');
  final ent = await c.patchOrder(oid, {'status': 'entregue'}, jwt: c.buyerJwt);
  c.note('bd7.hop.entregue', 'buyer entregue', ent.brief, lens: 'BD7');
  final conc = await c.patchOrder(oid, {'status': 'concluido'}, jwt: c.buyerJwt);
  c.note('bd7.hop.concluido', 'buyer concluido', conc.brief, lens: 'BD7');
  row = await c.orderRow(oid);
  c.note('bd7.hop.row', 'após hop', row, lens: 'BD7');

  final wPreRel = await c.walletsSnap();
  final relOk = await c.release(oid, jwt: c.buyerJwt);
  final wPostRel = await c.walletsSnap();
  final dSeller = (wPostRel['seller'] ?? 0) - (wPreRel['seller'] ?? 0);
  c.note('bd7.release.legit', 'release pós-envio', {
    'rpc': relOk.brief,
    'dSeller': dSeller,
    'wPre': wPreRel,
    'wPost': wPostRel,
  }, lens: 'BD7');

  final rel2 = await c.release(oid, jwt: c.buyerJwt);
  c.note('bd7.release.twice', '2º release', rel2.brief, lens: 'BD7');
  final wPost2 = await c.walletsSnap();
  final d2 = (wPost2['seller'] ?? 0) - (wPostRel['seller'] ?? 0);
  if (d2 > 0.009) {
    c.finding(
      id: 'BD7-double-release',
      lens: 'BD7',
      severity: 'P0',
      title: 'Segundo release creditou de novo',
      actor: 'buyer JWT',
      pre: 'já wallet_release_processed_at',
      repro: 'rpc release 2×',
      expected: 'false Δ=0',
      obtained: {'rpc': rel2.brief, 'd': d2},
    );
  } else {
    c.block('BD7.release.twice', 'BD7', '2º release sem mint',
        {'rpc': rel2.brief, 'd': d2});
  }

  // Payout 100¢ se houver saldo
  final bal = await c.walletBal(c.sellerId);
  HttpHit? payTiny;
  if (bal >= 1) {
    payTiny = await c.payout(
      amount: 100,
      key: '${prefix}-after-rel',
    );
    c.note('bd7.payout.after-rel', 'payout 100¢ pós-release', payTiny.brief,
        lens: 'BD7');
  } else {
    c.skip('BD7.payout', 'BD7', 'saldo <1€ — payout skip', bal);
  }

  // Refund após release (+ payout se houve)
  final refAfter = await c.refund(oid);
  c.note('bd7.refund.after-rel', 'refund-order pós-release', refAfter.brief,
      lens: 'BD4');
  final wAfterRef = await c.walletsSnap();
  final stripeRef = pi == null
      ? null
      : await c.e2e('list_stripe_refunds', {'payment_intent_id': pi});
  c.note('bd7.stripe.refunds', 'lista refunds PI', stripeRef?.brief, lens: 'BD4');

  final sellerDeltaTotal =
      (wAfterRef['seller'] ?? 0) - (wBefore['seller'] ?? 0);
  c.note('bd7.accounting', 'Δseller desde pago', {
    'wBefore': wBefore,
    'wAfterRef': wAfterRef,
    'dSeller': sellerDeltaTotal,
    'release': dSeller,
    'payout': payTiny?.brief,
    'refund': refAfter.brief,
  }, lens: 'BD7');

  // Se refund Stripe sucedeu E seller ainda tem o crédito de release → mint líquido
  final refundOk = refAfter.ok &&
      refAfter.map?['ok'] == true &&
      refAfter.map?['skipped'] != true;
  if (refundOk && dSeller > 0.009 && (wAfterRef['seller'] ?? 0) >= wPostRel['seller']!) {
    // clawback should have reduced seller if refund after release
    final clawed = (wPostRel['seller'] ?? 0) - (wAfterRef['seller'] ?? 0);
    if (clawed < 0.009 && payTiny?.transferId == null) {
      c.finding(
        id: 'BD7-refund-no-clawback',
        lens: 'BD7',
        severity: 'P0',
        title: 'Refund Stripe após release sem clawback da carteira vendedor',
        actor: 'seller JWT refund-order',
        pre: 'release Δ=$dSeller',
        repro: 'hop enviado/entregue/concluido; release; refund-order',
        expected: 'clawback ≥ release ou refund 403',
        obtained: {
          'refund': refAfter.brief,
          'dSellerStill': sellerDeltaTotal,
        },
      );
    } else {
      c.block('BD7.refund.clawback', 'BD7', 'refund pós-release clawback/403', {
        'clawed': clawed,
        'refund': refAfter.brief,
      });
    }
  } else {
    c.block('BD7.refund.after', 'BD7', 'refund pós-release bloqueado ou skip',
        refAfter);
  }

  // Webhook unsigned
  final destAcct = (await c.walletRow(c.sellerId))?['stripe_account_id'];
  final wh = await c.edge('stripe-webhook', {
    'type': 'transfer.created',
    'data': {
      'object': {
        'id': 'tr_fake_bd',
        'amount': 50000,
        'destination': destAcct,
      },
    },
  }, jwt: c.sellerJwt);
  c.note('bd7.webhook.unsigned', 'POST stripe-webhook sem assinatura', wh.brief,
      lens: 'BD7');
  if (wh.ok && wh.map?['ok'] == true && wh.map?['error'] == null) {
    c.finding(
      id: 'BD7-webhook-unsigned',
      lens: 'BD7',
      severity: 'P1',
      title: 'stripe-webhook aceitou evento sem assinatura',
      actor: 'seller JWT',
      pre: 'sem stripe-signature',
      repro: 'POST stripe-webhook type=transfer.created',
      expected: '400 missing_signature',
      obtained: wh.brief,
    );
  } else {
    c.block('BD7.webhook.unsigned', 'BD7', 'webhook sem assinatura recusado',
        wh);
  }

  await c.dumpAll('pass2.json');
}

extension on Rtbd {
  bool looksHand(Object? m) {
    final s = '${m ?? ''}'.toLowerCase();
    return s.contains('mão') ||
        s.contains('mao') ||
        s.startsWith('hand') ||
        s.contains('levantamento');
  }
}
