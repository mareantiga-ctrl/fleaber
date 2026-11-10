/// RED TEAM CEGO BP pass2 — release+refund, unship/FSM, actor cruzado, clawback, webhook.
/// Não corrige. Staging only. Não conta exacto «entrega em morada» LIKE.
import 'dart:io';

import '_rtbp.dart';

Future<void> main() async {
  final c = Rtbp.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  // ---------------------------------------------------------------------------
  // BP5 — is_hand NEW (não contar entrega em morada)
  // ---------------------------------------------------------------------------
  Future<void> probeHand(String method, {bool expectTrue = false}) async {
    final rpc = await c.rpc('batata_shipping_method_is_hand', {'p_method': method});
    c.note('hand.rpc', method, rpc.brief, lens: 'BP5');
    final oid = await c.insertOrder(
      status: 'pago',
      shipping: method,
      payment: 'MB WAY',
      proof: 'https://example.com/p',
      paidCents: 500,
      price: 5,
    );
    if (oid == null) {
      c.note('hand.nooid', method, 'no order', lens: 'BP5');
      return;
    }
    final patch = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
      'status': 'concluido',
    });
    final row = await c.orderRow(oid);
    final st = '${row?['status'] ?? ''}';
    final released = row?['wallet_release_processed_at'];
    c.note('hand.patch', method, {
      'rpc': rpc.brief,
      'patch': patch.brief,
      'status': st,
      'released': released,
    }, lens: 'BP5');

    final becameConcluido = st == 'concluido';
    if (expectTrue) {
      if (becameConcluido) {
        c.block('hand.ok.$method', 'BP5', 'mão legítima → concluido permitido', st);
      } else {
        c.note('hand.legit.blocked', '$method mão na allowlist mas concluido negado',
            patch.brief, lens: 'BP5');
      }
      return;
    }

    if (becameConcluido) {
      // Não contar entrega em morada exacto
      if (method == 'entrega em morada') {
        c.note('hand.morada', 'exacto LIKE — não contar se aberto; se aberto é regressão', row,
            lens: 'BP5');
        return;
      }
      c.hold(
        id: 'P1-BP5-unship-hand-bypass',
        lens: 'BP5',
        severity: 'P1',
        title: 'pago→concluido sem envio com shipping_method="$method"',
        actor: 'buyer JWT',
        pre: 'allowlist exacta is_hand; CTT/não-mão exige shipped',
        repro: 'INSERT pago shipping=$method; PATCH status=concluido',
        expected: 'order_concluido_requires_shipped',
        obtained: {'status': st, 'released': released, 'patch': patch.brief, 'rpc': rpc.brief},
      );
      final rel = await c.rpc('batata_release_seller_wallet_for_order', {
        'p_order_id': oid,
      }, jwt: c.buyerJwt);
      final w = await c.walletOf(c.sellerId!);
      c.note('hand.release', method, {'rel': rel.brief, 'bal': w?['balance']}, lens: 'BP3');
      if (rel.json == true || '${rel.body}'.contains('true')) {
        c.hold(
          id: 'P0-BP3-release-unship-mint',
          lens: 'BP3',
          severity: 'P0',
          title: 'Release mintou carteira sem envio (shipping=$method)',
          actor: 'buyer JWT',
          pre: 'release exige concluido + (shipped_at ou is_hand)',
          repro: 'após concluido indevido, rpc batata_release_seller_wallet_for_order',
          expected: 'false / sem venda',
          obtained: {'rel': rel.brief, 'order': row, 'bal': w?['balance']},
        );
      }
    } else {
      c.block('hand.$method', 'BP5', 'não-mão não passou a concluido', {
        'method': method,
        'status': st,
        'patch': clip(patch.brief, 160),
      });
    }
  }

  await probeHand('entrega em morada'); // exacto — só nota
  await probeHand('handmade');
  await probeHand('hand-to-hand');
  await probeHand('hаnd'); // cyrillic a
  await probeHand('ｈａｎｄ'); // fullwidth
  await probeHand('hand\u00a0'); // nbsp
  await probeHand('entrega em m');
  await probeHand('CTT Expresso');
  await probeHand('FedEx');
  await probeHand('hand', expectTrue: true);
  await probeHand('entrega em mão', expectTrue: true);

  // Shipping freeze after paid
  final oidShip = await c.insertOrder(
    status: 'pago',
    shipping: 'CTT',
    payment: 'MB WAY',
    proof: 'https://example.com/p',
    paidCents: 500,
    price: 5,
  );
  if (oidShip != null) {
    final freeze = await c.rest('PATCH', 'orders?id=eq.$oidShip', jwt: c.buyerJwt, body: {
      'shipping_method': 'hand',
    });
    final rowF = await c.orderRow(oidShip);
    if ('${rowF?['shipping_method']}' == 'hand') {
      c.hold(
        id: 'P1-BP5-shipping-unseal',
        lens: 'BP5',
        severity: 'P1',
        title: 'Buyer mudou CTT→hand após pago',
        actor: 'buyer JWT',
        pre: 'order_shipping_frozen_after_payment',
        repro: 'PATCH shipping_method=hand em order pago CTT',
        expected: '42501 frozen',
        obtained: {'patch': freeze.brief, 'row': rowF},
      );
      final c2 = await c.rest('PATCH', 'orders?id=eq.$oidShip', jwt: c.buyerJwt, body: {
        'status': 'concluido',
      });
      final rowC = await c.orderRow(oidShip);
      if ('${rowC?['status']}' == 'concluido') {
        c.hold(
          id: 'P0-BP5-unseal-then-concluido',
          lens: 'BP5',
          severity: 'P0',
          title: 'Após unseal para hand, buyer marcou concluido sem envio',
          actor: 'buyer JWT',
          pre: 'selo portes + is_hand no OLD',
          repro: 'PATCH ship=hand; PATCH status=concluido',
          expected: 'shipping frozen; concluido denied',
          obtained: {'c2': c2.brief, 'row': rowC},
        );
      }
    } else {
      c.block('ship.freeze', 'BP5', 'CTT→hand após pago bloqueado', {
        'patch': freeze.brief,
        'ship': rowF?['shipping_method'],
      });
    }

    // Seller marca enviado sem shipped_at?
    final env = await c.rest('PATCH', 'orders?id=eq.$oidShip', jwt: c.sellerJwt, body: {
      'status': 'enviado',
    });
    c.note('seller.enviado', 'seller PATCH enviado', env.brief, lens: 'BP5');
    final rowE = await c.orderRow(oidShip);
    if ('${rowE?['status']}' == 'enviado' && rowE?['shipped_at'] == null) {
      c.note('seller.enviado.noship', 'enviado sem shipped_at', rowE, lens: 'BP5');
      final relEarly = await c.rpc('batata_release_seller_wallet_for_order', {
        'p_order_id': oidShip,
      }, jwt: c.buyerJwt);
      if (relEarly.json == true) {
        c.hold(
          id: 'P0-BP3-release-on-enviado',
          lens: 'BP3',
          severity: 'P0',
          title: 'Release true com status enviado (exige concluido no SQL)',
          actor: 'buyer JWT',
          pre: 'release status in (concluido)',
          repro: 'seller PATCH enviado; buyer rpc release',
          expected: 'false',
          obtained: relEarly.brief,
        );
      } else {
        c.block('rel.enviado', 'BP3', 'release recusou enviado (não concluido)', relEarly.brief);
      }
    }
  }

  // Buyer INSERT order já concluido
  final pid = await c.insertProduct();
  final insCon = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pid,
    'status': 'concluido',
    'price_total': 5,
    'quantity': 1,
    'payment_method': 'MB WAY',
    'shipping_method': 'hand',
    'amount_paid_cents': 500,
  });
  final insId = insCon.firstId;
  if (insId != null) {
    final rowI = await c.orderRow(insId);
    if ('${rowI?['status']}' == 'concluido') {
      c.hold(
        id: 'P0-BP5-insert-concluido',
        lens: 'BP5',
        severity: 'P0',
        title: 'Buyer INSERT order já concluido',
        actor: 'buyer JWT',
        pre: 'INSERT buyer força reserva_pendente',
        repro: 'POST orders status=concluido',
        expected: 'reserva_pendente',
        obtained: rowI,
      );
    } else {
      c.block('ins.concluido', 'BP5', 'INSERT concluido rebaixado', rowI?['status']);
    }
  } else {
    c.block('ins.concluido', 'BP5', 'INSERT concluido rejeitado/sem id', insCon.brief);
  }

  // Release early: pago + shipped_at sem concluido
  final oidPaidShip = await c.insertOrder(
    status: 'pago',
    shipping: 'CTT',
    payment: 'Pagamento na app (Seguro Fleaber)',
    paidCents: 700,
    price: 7,
    shippedAt: DateTime.now().toUtc(),
    stripePi: 'pi_test_rtbp_paidship',
  );
  if (oidPaidShip != null) {
    final rel = await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': oidPaidShip,
    }, jwt: c.buyerJwt);
    final row = await c.orderRow(oidPaidShip);
    if (rel.json == true || row?['wallet_release_processed_at'] != null) {
      c.hold(
        id: 'P0-BP3-release-before-concluido',
        lens: 'BP3',
        severity: 'P0',
        title: 'Release com status pago (shipped_at set) — cedo demais',
        actor: 'buyer JWT',
        pre: 'SQL exige status=concluido',
        repro: 'order pago+shipped_at; rpc release',
        expected: 'false e release_processed null',
        obtained: {'rel': rel.brief, 'row': row},
      );
    } else {
      c.block('rel.pago', 'BP3', 'release recusou pago mesmo com shipped_at', rel.brief);
    }
  }

  // Cross actor release
  final oidOther = await c.insertOrder(
    buyer: c.buyer2Id,
    status: 'concluido',
    shipping: 'hand',
    payment: 'MB WAY',
    proof: 'https://example.com/p',
    paidCents: 500,
    price: 5,
  );
  if (oidOther != null) {
    final relB1 = await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': oidOther,
    }, jwt: c.buyerJwt);
    if (relB1.json == true) {
      c.hold(
        id: 'P1-BP6-release-not-buyer',
        lens: 'BP6',
        severity: 'P1',
        title: 'B1 libertou wallet de encomenda do B2',
        actor: 'buyer JWT alheio',
        pre: 'auth.uid deve ser buyer da order',
        repro: 'rpc release order B2 com JWT B1',
        expected: 'false',
        obtained: relB1.brief,
      );
    } else {
      c.block('rel.cross', 'BP6', 'B1 não liberta order B2', relB1.brief);
    }
    final relS = await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': oidOther,
    }, jwt: c.sellerJwt);
    c.note('rel.seller', 'seller chama release (SQL permite só buyer)', relS.brief, lens: 'BP6');
  }

  // ---------------------------------------------------------------------------
  // BP3 / BP6 — refund-order: buyer, amount extra, partial > capture
  // ---------------------------------------------------------------------------
  final oidRef = await c.insertOrder(
    status: 'pago',
    shipping: 'CTT',
    payment: 'Pagamento na app (Seguro Fleaber)',
    paidCents: 700,
    price: 7,
    stripePi: 'pi_test_rtbp_noreal',
  );
  if (oidRef != null) {
    final buyerRef = await c.edge('refund-order', {'order_id': oidRef}, jwt: c.buyerJwt);
    if (buyerRef.status == 403 || buyerRef.body.contains('Sem permissão')) {
      c.block('ref.buyer', 'BP6', 'buyer refund-order 403', buyerRef.brief);
    } else if (buyerRef.ok) {
      c.hold(
        id: 'P0-BP6-buyer-refund-order',
        lens: 'BP6',
        severity: 'P0',
        title: 'Buyer chamou refund-order com sucesso',
        actor: 'buyer JWT',
        pre: 'só seller_id',
        repro: 'POST refund-order {order_id} JWT buyer',
        expected: '403 Sem permissão',
        obtained: buyerRef.brief,
      );
    } else {
      c.note('ref.buyer', 'buyer refund not 403', buyerRef.brief, lens: 'BP6');
    }

    final b2Ref = await c.edge('refund-order', {'order_id': oidRef}, jwt: c.buyer2Jwt);
    if (b2Ref.status == 403 || b2Ref.status == 404) {
      c.block('ref.b2', 'BP6', 'B2 refund order alheia bloqueado', b2Ref.brief);
    } else if (b2Ref.ok) {
      c.hold(
        id: 'P0-BP6-b2-refund-alien',
        lens: 'BP6',
        severity: 'P0',
        title: 'B2 reembolsou encomenda de B1',
        actor: 'buyer2 JWT',
        pre: 'seller_id gate',
        repro: 'POST refund-order order B1 com JWT B2',
        expected: '403',
        obtained: b2Ref.brief,
      );
    }

    final amtRef = await c.edge('refund-order', {
      'order_id': oidRef,
      'amount': 999999,
      'amount_cents': 999999,
    }, jwt: c.sellerJwt);
    c.note('ref.amt', 'seller refund + amount extra (PI fake)', amtRef.brief, lens: 'BP3');
    if (amtRef.ok && (amtRef.map?['amount_cents'] is num) &&
        (amtRef.map!['amount_cents'] as num) > 700) {
      c.hold(
        id: 'P0-BP3-refund-over-capture',
        lens: 'BP3',
        severity: 'P0',
        title: 'refund-order usou amount cliente > captura',
        actor: 'seller JWT',
        pre: 'amount não está no body type; min(rowPaid, remaining)',
        repro: 'POST refund-order amount=999999',
        expected: 'ignorar amount cliente; ≤ captura',
        obtained: amtRef.brief,
      );
    } else {
      c.block('ref.over', 'BP3', 'amount cliente não inflou refund (ou PI inexistente)', amtRef.brief);
    }

    final finJwt = await c.rpc('batata_finalize_stripe_order_refund', {
      'p_order_id': oidRef,
      'p_refund_id': 're_fake_rtbp',
      'p_payment_intent_id': 'pi_fake',
      'p_session_id': null,
      'p_amount_cents': 700,
    }, jwt: c.sellerJwt);
    if (finJwt.denied || finJwt.status == 404) {
      c.block('rpc.finalize', 'BP6', 'JWT não executa finalize refund', finJwt.brief);
    } else if (finJwt.ok) {
      c.hold(
        id: 'P0-BP6-jwt-finalize-refund',
        lens: 'BP6',
        severity: 'P0',
        title: 'JWT executou batata_finalize_stripe_order_refund',
        actor: 'seller JWT',
        pre: 'REVOKE authenticated',
        repro: 'POST rpc finalize refund fake re_ id',
        expected: '42501',
        obtained: finJwt.brief,
      );
    }

    final clawJwt = await c.rpc('batata_clawback_seller_wallet_for_order', {
      'p_order_id': oidRef,
    }, jwt: c.sellerJwt);
    if (clawJwt.denied || clawJwt.status == 404) {
      c.block('rpc.clawback', 'BP6', 'JWT não executa clawback', clawJwt.brief);
    } else if (clawJwt.ok) {
      c.hold(
        id: 'P1-BP6-jwt-clawback',
        lens: 'BP6',
        severity: 'P1',
        title: 'JWT executou batata_clawback_seller_wallet_for_order',
        actor: 'seller JWT',
        pre: 'GRANT só service_role',
        repro: 'POST rpc clawback',
        expected: '42501',
        obtained: clawJwt.brief,
      );
    }
  }

  // Buyer wallet refund mint — status not devolvida
  final oidMint = await c.insertOrder(
    status: 'pago',
    shipping: 'hand',
    payment: 'MB WAY',
    proof: 'https://example.com/p',
    paidCents: 500,
    price: 5,
  );
  if (oidMint != null) {
    final wB0 = await c.walletOf(c.buyerId!);
    final rf = await c.rpc('batata_refund_buyer_wallet_for_order', {
      'p_order_id': oidMint,
    }, jwt: c.buyerJwt);
    final wB1 = await c.walletOf(c.buyerId!);
    final rowM = await c.orderRow(oidMint);
    c.note('buyer.wallet.refund', 'refund wallet em pago (não devolvida)', {
      'rpc': rf.brief,
      'bal0': wB0?['balance'],
      'bal1': wB1?['balance'],
      'flag': rowM?['wallet_refund_processed_at'],
    }, lens: 'BP3');
    final b0 = (wB0?['balance'] is num) ? wB0!['balance'] as num : 0;
    final b1 = (wB1?['balance'] is num) ? wB1!['balance'] as num : 0;
    if (b1 > b0 + 0.01) {
      c.hold(
        id: 'P0-BP3-buyer-wallet-mint-pago',
        lens: 'BP3',
        severity: 'P0',
        title: 'batata_refund_buyer_wallet mintou em status pago',
        actor: 'buyer JWT',
        pre: 'SQL exige devolvida',
        repro: 'rpc refund buyer wallet order pago',
        expected: 'false, Δwallet=0',
        obtained: {'rpc': rf.brief, 'd': b1 - b0, 'row': rowM},
      );
    } else {
      c.block('buyer.mint.pago', 'BP3', 'refund wallet recusou pago', rf.brief);
    }

    // B2 tenta refund wallet da order B1
    final rf2 = await c.rpc('batata_refund_buyer_wallet_for_order', {
      'p_order_id': oidMint,
    }, jwt: c.buyer2Jwt);
    if (rf2.json == true) {
      c.hold(
        id: 'P1-BP6-b2-buyer-wallet-refund',
        lens: 'BP6',
        severity: 'P1',
        title: 'B2 executou refund wallet da order B1',
        actor: 'buyer2 JWT',
        pre: 'uid deve ser buyer ou seller',
        repro: 'rpc refund_buyer_wallet order alheia',
        expected: 'false',
        obtained: rf2.brief,
      );
    } else {
      c.block('buyer.mint.b2', 'BP6', 'B2 não minta refund wallet alheio', rf2.brief);
    }
  }

  // Release + refund composition: concluido hand → release → refund-order
  final oidComp = await c.insertOrder(
    status: 'concluido',
    shipping: 'hand',
    payment: 'Pagamento na app (Seguro Fleaber)',
    paidCents: 700,
    price: 7,
    stripePi: 'pi_test_rtbp_comp',
  );
  if (oidComp != null) {
    final wS0 = await c.walletOf(c.sellerId!);
    final rel = await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': oidComp,
    }, jwt: c.buyerJwt);
    final wS1 = await c.walletOf(c.sellerId!);
    final rowR = await c.orderRow(oidComp);
    c.note('comp.release', 'release on fixture concluido+hand+fake PI', {
      'rel': rel.brief,
      'bal0': wS0?['balance'],
      'bal1': wS1?['balance'],
      'flag': rowR?['wallet_release_processed_at'],
    }, lens: 'BP3');
    final s0 = (wS0?['balance'] is num) ? wS0!['balance'] as num : 0;
    final s1 = (wS1?['balance'] is num) ? wS1!['balance'] as num : 0;
    if (s1 > s0 + 0.01) {
      c.note('comp.minted', 'release mintou (fixture serviço)', {'d': s1 - s0}, lens: 'BP7');
      final ref = await c.edge('refund-order', {'order_id': oidComp}, jwt: c.sellerJwt);
      c.note('comp.refund', 'refund-order após release', ref.brief, lens: 'BP3');
      final wS2 = await c.walletOf(c.sellerId!);
      final s2 = (wS2?['balance'] is num) ? wS2!['balance'] as num : 0;
      // Se refund Stripe falhar (PI fake) mas wallet seller ficou com mint: clawback?
      if (s2 >= s1 - 0.01 && (ref.ok || ref.status == 403)) {
        c.note('comp.no.claw', 'saldo seller não desceu após tentativa refund', {
          's1': s1,
          's2': s2,
          'ref': ref.brief,
        }, lens: 'BP7');
      }
    } else {
      c.block('comp.release', 'BP3', 'release não mintou (refund id / PI / remaining)', {
        'rel': rel.brief,
        'row': rowR,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // BP4 webhook replay
  // ---------------------------------------------------------------------------
  final whNoSig = await c.edge('stripe-webhook', {
    'type': 'transfer.created',
    'data': {
      'object': {'id': 'tr_fake', 'amount': 10000}
    }
  });
  if (whNoSig.status == 400 &&
      (whNoSig.body.contains('signature') || whNoSig.body.contains('missing'))) {
    c.block('wh.nosig', 'BP4', 'webhook sem stripe-signature rejeitado', whNoSig.brief);
  } else if (whNoSig.ok) {
    c.hold(
      id: 'P0-BP4-webhook-no-signature',
      lens: 'BP4',
      severity: 'P0',
      title: 'stripe-webhook aceitou POST sem assinatura',
      actor: 'anon',
      pre: 'constructEventAsync exige stripe-signature',
      repro: 'POST /functions/v1/stripe-webhook JSON transfer.created',
      expected: '400 missing_signature',
      obtained: whNoSig.brief,
    );
  } else {
    c.note('wh.nosig', 'webhook sem sig', whNoSig.brief, lens: 'BP4');
  }

  final whBad = await c.req(
    'POST',
    '/functions/v1/stripe-webhook',
    body: '{"type":"transfer.created"}',
    extra: {'stripe-signature': 't=1,v1=deadbeef'},
  );
  if (whBad.status == 400) {
    c.block('wh.badsig', 'BP4', 'assinatura lixo rejeitada', whBad.brief);
  } else if (whBad.ok) {
    c.hold(
      id: 'P0-BP4-webhook-bad-signature',
      lens: 'BP4',
      severity: 'P0',
      title: 'stripe-webhook aceitou assinatura inválida',
      actor: 'anon',
      pre: 'constructEventAsync',
      repro: 'POST webhook stripe-signature=t=1,v1=deadbeef',
      expected: '400 invalid_signature',
      obtained: whBad.brief,
    );
  }

  final whGet = await c.edge('stripe-webhook', null, method: 'GET');
  if (whGet.status == 405) {
    c.block('wh.get', 'BP4', 'GET webhook 405', whGet.brief);
  } else {
    c.note('wh.get', 'GET webhook', whGet.brief, lens: 'BP4');
  }

  // ensure_wallet alheio
  final ens = await c.rpc('batata_ensure_wallet', {'p_user_id': c.seller2Id}, jwt: c.buyerJwt);
  if (ens.denied || ens.status == 404) {
    c.block('ensure.alien', 'BP6', 'B1 não ensure_wallet S2', ens.brief);
  } else if (ens.ok) {
    c.note('ensure.alien', 'ensure_wallet alheio respondeu ok (pode ser no-op)', ens.brief,
        lens: 'BP6');
  }

  await c.dumpAll('pass2_findings.json');
  stdout.writeln('PASS2 done findings=${c.findings.length} blocked=${c.blocked.length}');
}
