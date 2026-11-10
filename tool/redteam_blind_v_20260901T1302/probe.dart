/// RED TEAM CEGO V — pós T0850/U0855. Staging only. Não corrige.
import 'dart:convert';
import 'dart:io';

import '_rtv.dart';

Future<void> main() async {
  final c = Rtv.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.wallets();
  c.note('wallets.start', 'saldos iniciais', w0, lens: 'V8');

  try {
    await _v1v2v8(c);
    await _v3offers(c);
    await _v4bundles(c);
    await _v5stock(c);
    await _v6races(c);
    await _v7actors(c);
    await _v8walletRpc(c);
  } finally {
    await c.endLives();
  }

  final wEnd = await c.wallets();
  final out = {
    'auditor': 'REDTEAM_BLIND_V_POS_TU_v1',
    'stamp': stamp,
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
    'wallets_start': w0,
    'wallets_end': wEnd,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
  };
  final path = '${outDir()}/probe.json';
  await dumpJson(path, out);
  stdout.writeln('WROTE $path findings=${c.findings.length} blocked=${c.blocked.length}');
}

Future<void> _v1v2v8(Rtv c) async {
  final paid = await c.setupPaidStripe();
  final oid = paid['order_id'];
  final pi = paid['pi'];
  if (oid == null) {
    c.note('V1.no-paid', 'setup_paid_order falhou', paid, lens: 'V1');
    return;
  }
  var o = await c.orderRow(oid);
  c.note('V1.paid', 'pedido Stripe TEST pago', {
    'status': o?['status'],
    'pi': pi,
    'amount_paid_cents': o?['amount_paid_cents'],
    'stock_units_applied': o?['stock_units_applied'],
  }, lens: 'V1');

  // Controlo: refund-order em pago ANTES de enviar (não partir).
  final rfPre = await c.refundOrder('__skip__');
  c.note('V2.refund.bad-id', 'refund-order id inventado', rfPre.brief, lens: 'V2');

  final ship = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
    'status': 'enviado',
  });
  o = await c.orderRow(oid);
  c.note('V1.ship', 'seller PATCH enviado', {
    'http': ship.brief,
    'status': o?['status'],
  }, lens: 'V1');

  // Controlo exacto (atrofia se for o único): enviado → pago
  final direct = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
    'status': 'pago',
  });
  o = await c.orderRow(oid);
  if ('${o?['status']}' == 'pago') {
    c.hold(
      id: 'RTV-V1-direct-reopen-pago',
      lens: 'V1',
      severity: 'P0',
      title: 'Seller reabre pago directo após enviado',
      actor: 'seller JWT',
      pre: 'order Stripe pago + enviado',
      repro: 'PATCH orders status=pago',
      expected: 'order_cannot_reopen_pago / status fica enviado',
      obtained: {'http': direct.brief, 'status': o?['status']},
    );
  } else {
    c.closed('V1.direct-pago', 'enviado→pago directo bloqueado', {
      'http': direct.brief,
      'status': o?['status'],
    }, lens: 'V1');
  }

  // Variante nova: hop enviado → reserva_pendente (não é →pago)
  final hop = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
    'status': 'reserva_pendente',
  });
  o = await c.orderRow(oid);
  final hopped = '${o?['status']}' == 'reserva_pendente';
  c.note('V1.hop.rp', 'seller enviado→reserva_pendente', {
    'http': hop.brief,
    'status': o?['status'],
  }, lens: 'V1');

  if (hopped) {
    c.hold(
      id: 'RTV-V1-unship-reserva-pendente',
      lens: 'V1',
      severity: 'P0',
      title: 'Após envio o vendedor volta o estado para reserva_pendente',
      actor: 'seller JWT',
      pre: 'pedido Stripe capturado + enviado; guard só bloqueia *→pago',
      repro: 'PATCH orders status=reserva_pendente (não pago)',
      expected: 'estado permanece enviado',
      obtained: {'http': hop.brief, 'status': o?['status']},
      evidence: {'pi': pi, 'amount_paid_cents': o?['amount_paid_cents']},
    );

    // refund-order no estado pré-pago após envio real
    final wA = await c.wallets();
    final rf = await c.refundOrder(oid);
    final oRf = await c.orderRow(oid);
    final wB = await c.wallets();
    final refunded = '${oRf?['stripe_refund_id'] ?? ''}'.trim().isNotEmpty ||
        (rf.map?['ok'] == true && rf.map?['skipped'] != true);
    c.note('V8.refund.after.hop', 'refund-order após unship', {
      'http': rf.brief,
      'status': oRf?['status'],
      'stripe_refund_id': oRf?['stripe_refund_id'],
      'wallets': {'before': wA, 'after': wB},
    }, lens: 'V8');
    if (refunded) {
      c.hold(
        id: 'RTV-V8-refund-after-unship',
        lens: 'V8',
        severity: 'P0',
        title: 'refund-order Stripe depois de unship enviado→reserva_pendente',
        actor: 'seller JWT',
        pre: 'Stripe capturado, enviado, hop para reserva_pendente',
        repro: 'PATCH status=reserva_pendente; POST refund-order',
        expected: 'order_refund_blocked_status (já enviada)',
        obtained: {
          'http': rf.brief,
          'status': oRf?['status'],
          'stripe_refund_id': oRf?['stripe_refund_id'],
        },
        evidence: {
          'pi': pi,
          'wallets_before': wA,
          'wallets_after': wB,
          'amount_paid_cents': oRf?['amount_paid_cents'],
        },
      );
    } else {
      c.closed('V8.refund.unship', 'refund-order recusado após unship', rf.brief,
          lens: 'V8');
    }

    // segundo hop: reserva_pendente → pago
    final hop2 = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
      'status': 'pago',
    });
    final o2 = await c.orderRow(oid);
    if ('${o2?['status']}' == 'pago') {
      c.hold(
        id: 'RTV-V1-hop-then-pago',
        lens: 'V1',
        severity: 'P0',
        title: 'Dois passos: enviado→reserva_pendente→pago fura o guard de reabrir pago',
        actor: 'seller JWT',
        pre: 'guard só vê old=enviado quando o PATCH é directo para pago',
        repro: 'PATCH reserva_pendente; PATCH pago',
        expected: 'não regressar a pago',
        obtained: {'http': hop2.brief, 'status': o2?['status']},
      );
    } else {
      c.closed('V1.hop2-pago', 'reserva_pendente→pago bloqueado', {
        'http': hop2.brief,
        'status': o2?['status'],
      }, lens: 'V1');
    }
  } else {
    c.closed('V1.hop.rp', 'enviado→reserva_pendente bloqueado', {
      'http': hop.brief,
      'status': o?['status'],
    }, lens: 'V1');
  }

  // Pedido pago fresco para hops alternativos + disputa (não reutilizar se já refunded)
  final paid2 = await c.setupPaidStripe();
  final oid2 = paid2['order_id'];
  if (oid2 == null) return;
  await c.rest('PATCH', 'orders?id=eq.$oid2', jwt: c.sellerJwt, body: {
    'status': 'enviado',
  });

  for (final st in [
    'pendente',
    'reservado',
    'aguarda_pagamento',
    'aguarda_confirmacao',
    'cancelado',
    'paid',
    'PAGO',
  ]) {
    final h = await c.rest('PATCH', 'orders?id=eq.$oid2', jwt: c.sellerJwt, body: {
      'status': st,
    });
    final row = await c.orderRow(oid2);
    final now = '${row?['status']}';
    if (now == st || now.toLowerCase() == st.toLowerCase()) {
      c.hold(
        id: 'RTV-V1-alias-unship-$st',
        lens: 'V1',
        severity: 'P1',
        title: 'Após enviado o estado mudou para $st',
        actor: 'seller JWT',
        pre: 'pedido Stripe enviado',
        repro: 'PATCH status=$st',
        expected: 'permanece enviado',
        obtained: {'http': h.brief, 'status': now},
      );
      break;
    } else {
      c.note('V1.alias.$st', 'hop $st recusado', '${h.brief} now=$now', lens: 'V1');
    }
  }

  // Buyer hop
  final bHop = await c.rest('PATCH', 'orders?id=eq.$oid2', jwt: c.buyerJwt, body: {
    'status': 'reserva_pendente',
  });
  final bRow = await c.orderRow(oid2);
  if ('${bRow?['status']}' == 'reserva_pendente') {
    c.hold(
      id: 'RTV-V1-buyer-unship',
      lens: 'V1',
      severity: 'P0',
      title: 'Comprador unship enviado→reserva_pendente',
      actor: 'buyer JWT',
      pre: 'pedido Stripe enviado',
      repro: 'PATCH status=reserva_pendente',
      expected: 'buyer não altera para pré-pago',
      obtained: {'http': bHop.brief, 'status': bRow?['status']},
    );
  } else {
    c.closed('V1.buyer-unship', 'buyer hop bloqueado', {
      'http': bHop.brief,
      'status': bRow?['status'],
    }, lens: 'V1');
  }

  // Entregue → hop
  final paid3 = await c.setupPaidStripe();
  final oid3 = paid3['order_id'];
  if (oid3 != null) {
    await c.rest('PATCH', 'orders?id=eq.$oid3', jwt: c.sellerJwt, body: {
      'status': 'enviado',
    });
    final ent = await c.rest('PATCH', 'orders?id=eq.$oid3', jwt: c.buyerJwt, body: {
      'status': 'entregue',
    });
    var r3 = await c.orderRow(oid3);
    c.note('V1.entregue', 'buyer marca entregue', {
      'http': ent.brief,
      'status': r3?['status'],
    }, lens: 'V1');
    if ('${r3?['status']}' == 'entregue') {
      final hopE = await c.rest(
        'PATCH',
        'orders?id=eq.$oid3',
        jwt: c.sellerJwt,
        body: {'status': 'reserva_pendente'},
      );
      r3 = await c.orderRow(oid3);
      if ('${r3?['status']}' == 'reserva_pendente') {
        c.hold(
          id: 'RTV-V1-unship-from-entregue',
          lens: 'V1',
          severity: 'P0',
          title: 'Após entregue o vendedor volta a reserva_pendente',
          actor: 'seller JWT',
          pre: 'Stripe pago → enviado → entregue',
          repro: 'PATCH status=reserva_pendente',
          expected: 'permanece entregue',
          obtained: {'http': hopE.brief, 'status': r3?['status']},
        );
        final rfE = await c.refundOrder(oid3);
        final r3b = await c.orderRow(oid3);
        if ('${r3b?['stripe_refund_id'] ?? ''}'.trim().isNotEmpty ||
            (rfE.map?['ok'] == true && rfE.map?['skipped'] != true)) {
          c.hold(
            id: 'RTV-V8-refund-after-entregue-unship',
            lens: 'V8',
            severity: 'P0',
            title: 'refund-order após entregue unshipado',
            actor: 'seller JWT',
            pre: 'entregue + hop reserva_pendente',
            repro: 'PATCH reserva_pendente; POST refund-order',
            expected: 'bloqueado (já recebido)',
            obtained: {
              'http': rfE.brief,
              'stripe_refund_id': r3b?['stripe_refund_id'],
            },
          );
        } else {
          c.closed('V8.refund.entregue', 'refund após entregue-unship recusado',
              rfE.brief, lens: 'V8');
        }
      } else {
        c.closed('V1.entregue-unship', 'entregue→reserva_pendente bloqueado', {
          'http': hopE.brief,
          'status': r3?['status'],
        }, lens: 'V1');
      }

      // Disputa × parcial em entregue (sem hop) — Stripe-required
      if ('${(await c.orderRow(oid3))?['status']}' == 'entregue') {
        await _disputePartial(c, oid3, lensNote: 'entregue-no-hop');
      }
    }
  }

  // Disputa + parcial + refund race num pedido AINDA pago (pré-envio) — contabilidade
  final paid4 = await c.setupPaidStripe();
  final oid4 = paid4['order_id'];
  if (oid4 != null) {
    await _disputePartial(c, oid4, lensNote: 'pago-pre-ship', allowMintOnPago: true);
    final wC = await c.wallets();
    final rf4 = await c.refundOrder(oid4);
    final o4 = await c.orderRow(oid4);
    final wD = await c.wallets();
    final minted = (wD['buyer'] ?? 0) > (wC['buyer'] ?? 0);
    final stripeRf = '${o4?['stripe_refund_id'] ?? ''}'.trim().isNotEmpty;
    c.note('V2.pago.partial.then.refund', 'parcial em pago depois refund-order', {
      'refund_http': rf4.brief,
      'stripe_refund_id': o4?['stripe_refund_id'],
      'wallet_refund_processed_at': o4?['wallet_refund_processed_at'],
      'wallets_before': wC,
      'wallets_after': wD,
    }, lens: 'V2');
    if (minted && stripeRf) {
      c.hold(
        id: 'RTV-V2-wallet-and-stripe-same-order',
        lens: 'V2',
        severity: 'P0',
        title: 'Parcial mintou carteira e refund-order devolveu Stripe no mesmo pedido',
        actor: 'buyer RPC + seller Edge',
        pre: 'pedido Stripe ainda pago (antes de enviar)',
        repro: 'rpc batata_process_partial_refund_dispute; POST refund-order',
        expected: 'só um dos dois (wallet residual no cartão)',
        obtained: {
          'minted': minted,
          'stripe_refund_id': o4?['stripe_refund_id'],
          'refund': rf4.brief,
        },
        evidence: {'wallets_before': wC, 'wallets_after': wD, 'order': o4},
      );
    }

    // Race real: outro pedido pago, partial ∥ refund-order
    final paid5 = await c.setupPaidStripe();
    final oid5 = paid5['order_id'];
    if (oid5 != null) {
      final d5 = await c.insertDispute(orderId: oid5);
      if (d5.firstId != null) c.createdDisputeIds.add(d5.firstId!);
      await c.rest('PATCH', 'order_disputes?order_id=eq.$oid5', jwt: c.sellerJwt, body: {
        'seller_offer_type': 'partial_refund',
        'seller_refund_percent': 50,
      });
      final wE = await c.wallets();
      final raced = await parallel([
        c.rpc('batata_process_partial_refund_dispute', {'p_order_id': oid5},
            jwt: c.buyerJwt),
        c.refundOrder(oid5),
      ]);
      final o5 = await c.orderRow(oid5);
      final wF = await c.wallets();
      final dBuyer = (wF['buyer'] ?? 0) - (wE['buyer'] ?? 0);
      final stripe = '${o5?['stripe_refund_id'] ?? ''}'.trim().isNotEmpty;
      c.note('V6.race.partial-refund', 'Future.wait partial ∥ refund-order', {
        'partial': raced[0].brief,
        'refund': raced[1].brief,
        'delta_buyer': dBuyer,
        'stripe_refund_id': o5?['stripe_refund_id'],
        'wallet_refund_processed_at': o5?['wallet_refund_processed_at'],
      }, lens: 'V6');
      if (dBuyer > 0 && stripe) {
        c.hold(
          id: 'RTV-V6-race-wallet-and-stripe',
          lens: 'V6',
          severity: 'P0',
          title: 'Corrida parcial∥refund-order creditou carteira e Stripe',
          actor: 'buyer RPC ∥ seller Edge',
          pre: 'pedido Stripe pago, disputa 50%',
          repro: 'Future.wait process_partial_refund_dispute + refund-order',
          expected: 'um só canal de dinheiro',
          obtained: {
            'delta_buyer': dBuyer,
            'stripe': stripe,
            'partial': raced[0].brief,
            'refund': raced[1].brief,
          },
          evidence: {'wallets_before': wE, 'wallets_after': wF, 'order': o5},
        );
      }
    }
  }
}

Future<void> _disputePartial(
  Rtv c,
  String oid, {
  required String lensNote,
  bool allowMintOnPago = false,
}) async {
  var o = await c.orderRow(oid);
  final st = '${o?['status']}';
  final d = await c.insertDispute(orderId: oid);
  c.note('V2.dispute.$lensNote', 'INSERT disputa', d.brief, lens: 'V2');
  if (d.firstId != null) c.createdDisputeIds.add(d.firstId!);
  final offer = await c.rest(
    'PATCH',
    'order_disputes?order_id=eq.$oid',
    jwt: c.sellerJwt,
    body: {
      'seller_offer_type': 'partial_refund',
      'seller_refund_percent': 50,
    },
  );
  c.note('V2.offer.$lensNote', 'seller oferta 50%', offer.brief, lens: 'V2');
  final wA = await c.wallets();
  final part = await c.rpc(
    'batata_process_partial_refund_dispute',
    {'p_order_id': oid},
    jwt: c.buyerJwt,
  );
  o = await c.orderRow(oid);
  final wB = await c.wallets();
  final minted = (wB['buyer'] ?? 0) > (wA['buyer'] ?? 0);
  final noStripe = '${o?['stripe_refund_id'] ?? ''}'.trim().isEmpty;
  c.note('V2.partial.$lensNote', 'process_partial', {
    'http': part.brief,
    'status': o?['status'],
    'minted': minted,
    'stripe_refund_id': o?['stripe_refund_id'],
    'wallets': {'before': wA, 'after': wB},
  }, lens: 'V2');
  final postShip = ['enviado', 'entregue', 'concluido', 'pedido_devolucao']
      .contains(st);
  if (minted && noStripe && postShip) {
    c.hold(
      id: 'RTV-V2-partial-mint-post-ship-$lensNote',
      lens: 'V2',
      severity: 'P0',
      title: 'Parcial pós-envio mintou carteira sem Stripe refund',
      actor: 'buyer JWT',
      pre: 'status=$st Stripe capturado',
      repro: 'rpc batata_process_partial_refund_dispute',
      expected: 'dispute_partial_refund_requires_stripe',
      obtained: part.brief,
      evidence: {'wallets_before': wA, 'wallets_after': wB, 'order': o},
    );
  } else if (minted && noStripe && allowMintOnPago && st == 'pago') {
    c.note('V2.partial.pago.mint', 'parcial em pago mintou (caminho pré-envio)', {
      'delta': (wB['buyer'] ?? 0) - (wA['buyer'] ?? 0),
    }, lens: 'V2');
  } else if (!minted && postShip) {
    c.closed('V2.partial.post-ship.$lensNote', 'parcial pós-envio sem mint',
        part.brief, lens: 'V2');
  }
}

Future<void> _v3offers(Rtv c) async {
  final p = await c.insertProduct(title: '$prefix offer', qty: 5, price: 20);
  if (p == null) return;
  final chat = await c.rest('POST', 'chats', service: true, body: {
    'user_a': c.buyerId,
    'user_b': c.sellerId,
    'product_id': p,
  });
  final offer = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': p,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': 12,
    'status': 'pending',
    'offered_by': 'buyer',
    if (chat.firstId != null) 'chat_id': chat.firstId,
  });
  c.note('V3.offer.ins', 'buyer cria oferta 12€', offer.brief, lens: 'V3');
  final oidOffer = offer.firstId;
  if (oidOffer == null) return;
  c.createdOfferIds.add(oidOffer);
  final acc = await c.rest('PATCH', 'product_offers?id=eq.$oidOffer',
      jwt: c.sellerJwt, body: {'status': 'accepted'});
  c.note('V3.offer.acc', 'seller aceita', acc.brief, lens: 'V3');

  // Exact: qty=2 no INSERT (controlo)
  final q2 = await c.insertOrder(
    productId: p,
    jwt: c.buyerJwt,
    qty: 2,
    price: 12,
    offerId: oidOffer,
  );
  if (q2 != null) {
    final row = await c.orderRow(q2);
    if ((row?['quantity'] as num?) != null &&
        (row!['quantity'] as num) > 1 &&
        row['product_offer_id'] != null) {
      c.hold(
        id: 'RTV-V3-insert-qty2',
        lens: 'V3',
        severity: 'P0',
        title: 'Oferta aceite inserida com quantity>1',
        actor: 'buyer JWT',
        pre: 'product_offer accepted',
        repro: 'POST orders quantity=2 product_offer_id=…',
        expected: 'offer_quantity_must_be_one',
        obtained: row,
      );
    } else {
      c.closed('V3.insert.qty2', 'INSERT oferta qty>1 bloqueado ou qty selada a 1',
          q2, lens: 'V3');
    }
  } else {
    c.closed('V3.insert.qty2', 'INSERT oferta qty=2 recusado', 'no id', lens: 'V3');
  }

  final o1 = await c.insertOrder(
    productId: p,
    jwt: c.buyerJwt,
    qty: 1,
    price: 12,
    offerId: oidOffer,
  );
  if (o1 == null) {
    c.note('V3.order1', 'primeira order oferta falhou', 'null', lens: 'V3');
    return;
  }
  final r1 = await c.orderRow(o1);
  c.note('V3.order1', 'order oferta qty1', r1, lens: 'V3');

  // Variante nova: UPDATE quantity após INSERT
  final up = await c.rest('PATCH', 'orders?id=eq.$o1', jwt: c.buyerJwt, body: {
    'quantity': 5,
  });
  final r1b = await c.orderRow(o1);
  if ((r1b?['quantity'] as num?) != null && (r1b!['quantity'] as num) > 1) {
    c.hold(
      id: 'RTV-V3-update-qty-after-insert',
      lens: 'V3',
      severity: 'P0',
      title: 'Oferta: INSERT qty=1 depois PATCH quantity=5 (guard só no INSERT)',
      actor: 'buyer JWT',
      pre: 'order com product_offer_id qty=1',
      repro: 'PATCH orders quantity=5',
      expected: 'order_money_fields_immutable / qty=1',
      obtained: {'http': up.brief, 'quantity': r1b['quantity']},
    );
  } else {
    c.closed('V3.update.qty', 'PATCH qty oferta bloqueado', up.brief, lens: 'V3');
  }

  // Segunda order na mesma oferta
  final o2 = await c.insertOrder(
    productId: p,
    jwt: c.buyerJwt,
    qty: 1,
    price: 12,
    offerId: oidOffer,
  );
  if (o2 != null) {
    final r2 = await c.orderRow(o2);
    final stillOffer = r2?['product_offer_id']?.toString() == oidOffer;
    if (stillOffer) {
      c.hold(
        id: 'RTV-V3-second-order-same-offer',
        lens: 'V3',
        severity: 'P1',
        title: 'Duas encomendas na mesma oferta aceite',
        actor: 'buyer JWT',
        pre: 'oferta já ligada à order 1',
        repro: 'POST orders product_offer_id=mesma',
        expected: 'offer_already_consumed',
        obtained: r2,
      );
    } else {
      c.closed('V3.second.offer', '2.ª order sem offer_id (consumida)', r2,
          lens: 'V3');
    }
  } else {
    c.closed('V3.second.offer', '2.ª order mesma oferta recusada', 'no id',
        lens: 'V3');
  }

  // Checkout da oferta (marketplace) — montante
  final ck = await c.checkoutSingle(orderId: o1, productId: p);
  final cents = ck.amountCents;
  c.note('V3.checkout.offer', 'create-payment-intent oferta', {
    'http': ck.brief,
    'amount_cents': cents,
  }, lens: 'V3');
  if (ck.ok && cents != null && cents < 1200) {
    // 12€ = 1200 cents items; portes+proteção podem somar. Items too low = steal.
    // server_amount_cents inclui portes. Se < 1200, pagou menos que a oferta.
    c.hold(
      id: 'RTV-V3-checkout-under-offer',
      lens: 'V3',
      severity: 'P0',
      title: 'Checkout da oferta abaixo do valor aceite',
      actor: 'buyer JWT',
      pre: 'oferta aceite 12€',
      repro: 'POST create-payment-intent',
      expected: '≥ 12€ de artigos',
      obtained: {'amount_cents': cents, 'http': ck.brief},
    );
  }

  // Offer + bundle no mesmo order
  final pB = await c.insertProduct(title: '$prefix offer-bun-b', qty: 2, price: 15);
  if (pB != null) {
    final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'product_ids': [p, pB],
      'subtotal_eur': 35,
      'discount_pct': 0,
      'discount_eur': 0,
      'total_eur': 35,
      'status': 'pending',
    });
    c.note('V3.bundle+offer.ins', 'bundle 2 SKUs', bun.brief, lens: 'V3');
    if (bun.firstId != null) {
      c.createdBundleIds.add(bun.firstId!);
      await c.rest('PATCH', 'product_bundles?id=eq.${bun.firstId}',
          jwt: c.sellerJwt, body: {'status': 'accepted'});
      final mix = await c.insertOrder(
        productId: p,
        jwt: c.buyerJwt,
        qty: 1,
        price: 12,
        offerId: oidOffer,
        bundleId: bun.firstId,
      );
      c.note('V3.bundle+offer.order', 'order oferta+bundle', mix, lens: 'V3');
    }
  }
}

Future<void> _v4bundles(Rtv c) async {
  final p1 = await c.insertProduct(title: '$prefix bun1', qty: 3, price: 10);
  final p2 = await c.insertProduct(title: '$prefix bun2', qty: 2, price: 10);
  final p3 = await c.insertProduct(title: '$prefix bun3', qty: 2, price: 10);
  if (p1 == null || p2 == null || p3 == null) return;

  final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
    'seller_id': c.sellerId,
    'buyer_id': c.buyerId,
    'product_ids': [p1, p2, p3],
    'subtotal_eur': 30,
    'discount_pct': 0,
    'discount_eur': 0,
    'total_eur': 18,
    'status': 'pending',
  });
  c.note('V4.bundle.ins', 'conjunto 3 SKUs (total cliente 18)', bun.brief, lens: 'V4');
  final bid = bun.firstId;
  if (bid == null) return;
  c.createdBundleIds.add(bid);
  final acc = await c.rest('PATCH', 'product_bundles?id=eq.$bid', jwt: c.sellerJwt, body: {
    'status': 'accepted',
    'discount_pct': 40,
  });
  c.note('V4.bundle.acc', 'seller aceita+40%', acc.brief, lens: 'V4');
  final bRow = await c.rest(
    'GET',
    'product_bundles?id=eq.$bid&select=id,status,total_eur,subtotal_eur,discount_pct,product_ids',
    service: true,
  );
  final total = (bRow.map?['total_eur'] as num?) ?? 0;
  c.note('V4.bundle.row', 'total_eur selado', bRow.map, lens: 'V4');

  // Buyer tenta baixar total_eur
  final cheap = await c.rest('PATCH', 'product_bundles?id=eq.$bid', jwt: c.buyerJwt, body: {
    'total_eur': 1,
  });
  final bRow2 = await c.rest(
    'GET',
    'product_bundles?id=eq.$bid&select=total_eur,status',
    service: true,
  );
  if ((bRow2.map?['total_eur'] as num?) != null &&
      (bRow2.map!['total_eur'] as num) <= 1) {
    c.hold(
      id: 'RTV-V4-buyer-lowers-total',
      lens: 'V4',
      severity: 'P0',
      title: 'Comprador baixa total_eur do conjunto aceite',
      actor: 'buyer JWT',
      pre: 'bundle accepted',
      repro: 'PATCH product_bundles total_eur=1',
      expected: 'total congelado',
      obtained: {'http': cheap.brief, 'row': bRow2.map},
    );
  } else {
    c.closed('V4.total.patch', 'buyer total_eur aceite congelado', cheap.brief,
        lens: 'V4');
  }

  // Controlo: saco incompleto (2 de 3)
  final oA = await c.insertOrder(productId: p1, jwt: c.buyerJwt, price: 10, bundleId: bid);
  final oB = await c.insertOrder(productId: p2, jwt: c.buyerJwt, price: 10, bundleId: bid);
  final incomplete = await c.checkoutBag(lines: [
    {'order_id': oA, 'product_id': p1},
    {'order_id': oB, 'product_id': p2},
  ]);
  if (incomplete.ok) {
    c.hold(
      id: 'RTV-V4-incomplete-bag',
      lens: 'V4',
      severity: 'P0',
      title: 'Checkout do conjunto aceite sem todos os artigos',
      actor: 'buyer JWT',
      pre: 'bundle 3 SKUs accepted',
      repro: 'POST create-payment-intent bag 2/3',
      expected: 'bag must include all items',
      obtained: incomplete.brief,
    );
  } else {
    c.closed('V4.incomplete', 'saco incompleto bloqueado', incomplete.brief, lens: 'V4');
  }

  // Variante nova: 4.ª linha do mesmo SKU (P1 qty extra) no saco "completo"
  final oC = await c.insertOrder(productId: p3, jwt: c.buyerJwt, price: 10, bundleId: bid);
  final oDup = await c.insertOrder(productId: p1, jwt: c.buyerJwt, price: 10, bundleId: bid);
  final extra = await c.checkoutBag(lines: [
    {'order_id': oA, 'product_id': p1},
    {'order_id': oB, 'product_id': p2},
    {'order_id': oC, 'product_id': p3},
    {'order_id': oDup, 'product_id': p1},
  ]);
  final extraCents = extra.amountCents;
  final expectedBundleCents = (total * 100).round();
  c.note('V4.extra-sku', 'saco completo + 2.ª unidade P1', {
    'http': extra.brief,
    'amount_cents': extraCents,
    'bundle_total_cents': expectedBundleCents,
  }, lens: 'V4');
  if (extra.ok && extraCents != null && expectedBundleCents > 0) {
    // Se pagou só o total do conjunto de 3 mas leva 4 unidades
    final catalog4 = 4000; // 4×10€ sem portes
    if (extraCents < catalog4 && extraCents <= expectedBundleCents + 800) {
      c.hold(
        id: 'RTV-V4-extra-line-same-sku',
        lens: 'V4',
        severity: 'P0',
        title: 'Saco com SKU extra (2×P1+P2+P3) cobra o total do conjunto de 3',
        actor: 'buyer JWT',
        pre: 'bundle aceite [P1,P2,P3]; P1 tem stock≥2',
        repro: 'POST create-payment-intent 4 orders (P1 duplicado)',
        expected: 'recusar ou cobrar 4× catálogo / 4.ª linha fora do total',
        obtained: {
          'amount_cents': extraCents,
          'bundle_total_cents': expectedBundleCents,
        },
      );
    }
  }

  // Dois bundle_id no mesmo saco (skip complete)
  final bun2 = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
    'seller_id': c.sellerId,
    'buyer_id': c.buyerId,
    'product_ids': [p1, p2],
    'subtotal_eur': 20,
    'discount_pct': 0,
    'discount_eur': 0,
    'total_eur': 20,
    'status': 'pending',
  });
  if (bun2.firstId != null) {
    c.createdBundleIds.add(bun2.firstId!);
    await c.rest('PATCH', 'product_bundles?id=eq.${bun2.firstId}',
        jwt: c.sellerJwt, body: {'status': 'accepted', 'discount_pct': 50});
    final oX = await c.insertOrder(
        productId: p1, jwt: c.buyerJwt, price: 10, bundleId: bid);
    final oY = await c.insertOrder(
        productId: p2, jwt: c.buyerJwt, price: 10, bundleId: bun2.firstId);
    final two = await c.checkoutBag(lines: [
      {'order_id': oX, 'product_id': p1},
      {'order_id': oY, 'product_id': p2},
    ]);
    c.note('V4.two-bundle-ids', 'saco com 2 bundle_id (skip complete?)', {
      'http': two.brief,
      'amount_cents': two.amountCents,
    }, lens: 'V4');
    if (two.ok) {
      c.hold(
        id: 'RTV-V4-two-bundle-ids-skip-complete',
        lens: 'V4',
        severity: 'P1',
        title: 'Dois bundle_id no saco: Edge não exige conjunto completo',
        actor: 'buyer JWT',
        pre: 'bundle A=3 SKUs, bundle B=2 SKUs, ambos accepted',
        repro: 'bag 2 linhas com bundle_id diferentes',
        expected: 'falhar closed (ids misturados) ou exigir complete de ambos',
        obtained: {'http': two.brief, 'amount_cents': two.amountCents},
      );
    } else {
      c.closed('V4.two-ids', 'dois bundle_id recusados ou incompleto A', two.brief,
          lens: 'V4');
    }
  }
}

Future<void> _v5stock(Rtv c) async {
  // Hub qty=0 exact (controlo) vs REST products (variante)
  final z = await c.insertProduct(title: '$prefix qty0', qty: 1, price: 7);
  if (z != null) {
    final dec = await c.rest('PATCH', 'products?id=eq.$z', jwt: c.sellerJwt, body: {
      'quantity': 0,
    });
    final prow = await c.productRow(z);
    c.note('V5.qty0.patch', 'seller qty→0', {
      'http': dec.brief,
      'qty': prow?['quantity'],
    }, lens: 'V5');
    final hub = await c.rest(
      'GET',
      'hub_products_public?id=eq.$z&select=id,title',
      jwt: c.buyerJwt,
    );
    final anonP = await c.rest(
      'GET',
      'products?id=eq.$z&select=id,title,quantity,list_on_marketplace,is_sold',
    );
    c.note('V5.qty0.surfaces', 'Hub view vs REST products', {
      'hub': hub.brief,
      'anon_products': anonP.brief,
    }, lens: 'V5');
    if (hub.list.isNotEmpty) {
      c.hold(
        id: 'RTV-V5-hub-qty0',
        lens: 'V5',
        severity: 'P2',
        title: 'hub_products_public mostra artigo com quantity=0',
        actor: 'buyer JWT',
        pre: 'seller pôs qty=0, listed',
        repro: 'GET hub_products_public?id=eq',
        expected: 'vazio (qty>0)',
        obtained: hub.brief,
      );
    } else {
      c.closed('V5.hub.qty0', 'Hub esconde qty=0', hub.brief, lens: 'V5');
    }
    final shown = anonP.list.isNotEmpty || anonP.map != null;
    final aq = anonP.map?['quantity'];
    if (shown && (aq == 0 || aq == '0')) {
      c.hold(
        id: 'RTV-V5-products-rest-qty0',
        lens: 'V5',
        severity: 'P2',
        title: 'REST products (anon) ainda lista anúncio com quantity=0',
        actor: 'anon',
        pre: 'qty=0 listed not sold; Hub view filtra',
        repro: 'GET /rest/v1/products?id=eq (anon)',
        expected: 'oculto ou is_sold',
        obtained: anonP.brief,
      );
    }
  }

  // live_only inflate
  final live = await c.insertLive();
  if (live == null) return;
  final li = await c.insertLiveItem(liveId: live, title: '$prefix lo', qty: 1);
  if (li == null) return;
  final inf = await c.rest('PATCH', 'live_items?id=eq.$li', jwt: c.sellerJwt, body: {
    'quantity': 99,
  });
  final liRow = await c.liveItemRow(li);
  c.note('V5.live-only.inflate', 'seller PATCH live_item qty 1→99', {
    'http': inf.brief,
    'qty': liRow?['quantity'],
  }, lens: 'V5');
  if ((liRow?['quantity'] as num?) != null && (liRow!['quantity'] as num) >= 99) {
    c.hold(
      id: 'RTV-V5-live-only-inflate',
      lens: 'V5',
      severity: 'P1',
      title: 'live_only: vendedor inflaciona quantity sem tecto de produto',
      actor: 'seller JWT',
      pre: 'live_item sem product_id qty=1',
      repro: 'PATCH live_items quantity=99',
      expected: 'qty imutável ou tecto razoável',
      obtained: {'http': inf.brief, 'quantity': liRow['quantity']},
    );
    final res = await c.insertReservation(
      liveId: live,
      liveItemId: li,
      jwt: c.buyerJwt,
      qty: 40,
    );
    c.note('V5.res.inflate', 'reserva qty=40 após inflate', res, lens: 'V5');
  } else {
    c.closed('V5.live-only.inflate', 'inflate live_only bloqueado', inf.brief,
        lens: 'V5');
  }

  // Hub live items qty=0 ainda visível
  if (li != null) {
    await c.rest('PATCH', 'live_items?id=eq.$li', jwt: c.sellerJwt, body: {
      'quantity': 0,
    });
    final hubLi = await c.rest(
      'GET',
      'hub_live_items_public?id=eq.$li&select=id,title,is_active,status',
      jwt: c.buyerJwt,
    );
    c.note('V5.hub-live.qty0', 'hub_live_items_public com qty=0', hubLi.brief,
        lens: 'V5');
    if (hubLi.list.isNotEmpty || hubLi.map != null) {
      c.hold(
        id: 'RTV-V5-hub-live-item-qty0',
        lens: 'V5',
        severity: 'P2',
        title: 'Hub de artigos de directo não filtra quantity=0',
        actor: 'buyer JWT',
        pre: 'live_item activo qty=0',
        repro: 'GET hub_live_items_public',
        expected: 'oculto (espelho qty>0 do Hub produtos)',
        obtained: hubLi.brief,
      );
    }
  }

  // Decrease product abaixo de held
  final heldP = await c.insertProduct(title: '$prefix held', qty: 2, price: 9);
  if (heldP != null) {
    final paid = await c.setupPaidStripe();
    // setup cria produto próprio; usar heldP com order reserva
    final ho = await c.insertOrder(productId: heldP, jwt: c.buyerJwt, price: 9);
    c.note('V5.held.order', 'order reserva no SKU held', ho, lens: 'V5');
    final down = await c.rest(
      'PATCH',
      'products?id=eq.$heldP',
      jwt: c.sellerJwt,
      body: {'quantity': 0},
    );
    final after = await c.productRow(heldP);
    c.note('V5.held.down', 'seller qty→0 com order aberta', {
      'http': down.brief,
      'qty': after?['quantity'],
      'paid_fixture': paid['order_id'],
    }, lens: 'V5');
    if (after?['quantity'] == 0) {
      // só finding se a order tem hold real (stock_units_applied). reserva_pendente pode não contar.
      final orow = ho == null ? null : await c.orderRow(ho);
      if ((orow?['stock_units_applied'] as num?) != null &&
          (orow!['stock_units_applied'] as num) > 0) {
        c.hold(
          id: 'RTV-V5-qty0-with-held',
          lens: 'V5',
          severity: 'P1',
          title: 'Seller pôs quantity=0 com unidades já em encomenda activa',
          actor: 'seller JWT',
          pre: 'order com stock_units_applied>0',
          repro: 'PATCH products quantity=0',
          expected: 'product_quantity_below_held',
          obtained: {'qty': after?['quantity'], 'order': orow},
        );
      }
    }
  }
}

Future<void> _v6races(Rtv c) async {
  final p = await c.insertProduct(title: '$prefix race-offer', qty: 3, price: 11);
  if (p == null) return;
  final off = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': p,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': 9,
    'status': 'pending',
    'offered_by': 'buyer',
  });
  if (off.firstId == null) return;
  c.createdOfferIds.add(off.firstId!);
  await c.rest('PATCH', 'product_offers?id=eq.${off.firstId}', jwt: c.sellerJwt, body: {
    'status': 'accepted',
  });
  final raced = await parallel([
    c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': p,
      'price_total': 9,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
      'product_offer_id': off.firstId,
    }),
    c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': p,
      'price_total': 9,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
      'product_offer_id': off.firstId,
    }),
  ]);
  final ids = <String>[];
  for (final h in raced) {
    final id = h.firstId;
    if (id != null) {
      ids.add(id);
      c.createdOrderIds.add(id);
    }
  }
  var consumed = 0;
  for (final id in ids) {
    final row = await c.orderRow(id);
    if (row?['product_offer_id']?.toString() == off.firstId) consumed++;
  }
  c.note('V6.race.offer-orders', 'duas INSERT paralelas mesma oferta', {
    'a': raced[0].brief,
    'b': raced[1].brief,
    'ids': ids,
    'with_offer_id': consumed,
  }, lens: 'V6');
  if (consumed >= 2) {
    c.hold(
      id: 'RTV-V6-race-two-orders-one-offer',
      lens: 'V6',
      severity: 'P1',
      title: 'Corrida: duas encomendas ficaram com a mesma oferta aceite',
      actor: 'buyer JWT ×2',
      pre: 'oferta accepted oneshot',
      repro: 'Future.wait POST orders product_offer_id',
      expected: 'só uma consome a oferta',
      obtained: {'ids': ids, 'with_offer_id': consumed},
    );
  } else {
    c.closed('V6.race.offer', 'corrida oferta: no máximo 1 consumida', consumed,
        lens: 'V6');
  }
}

Future<void> _v7actors(Rtv c) async {
  final paid = await c.setupPaidStripe();
  final oid = paid['order_id'];
  if (oid == null) return;

  final b2patch = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyer2Jwt, body: {
    'status': 'enviado',
  });
  final row = await c.orderRow(oid);
  c.note('V7.b2.patch', 'B2 PATCH order de B1', {
    'http': b2patch.brief,
    'status': row?['status'],
  }, lens: 'V7');
  if (b2patch.ok && '${row?['status']}' == 'enviado') {
    c.hold(
      id: 'RTV-V7-b2-patch-b1-order',
      lens: 'V7',
      severity: 'P0',
      title: '2.º comprador altera encomenda do 1.º',
      actor: 'buyer2 JWT',
      pre: 'order B1/S1 pago',
      repro: 'PATCH orders status=enviado',
      expected: 'RLS 0 rows / 401',
      obtained: {'http': b2patch.brief, 'status': row?['status']},
    );
  } else {
    c.closed('V7.b2.patch', 'B2 não escreve order B1', b2patch.brief, lens: 'V7');
  }

  final d = await c.insertDispute(
    orderId: oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  c.note('V7.b2.dispute', 'B2 abre disputa no pedido B1', d.brief, lens: 'V7');
  if (d.ok && d.firstId != null) {
    c.createdDisputeIds.add(d.firstId!);
    c.hold(
      id: 'RTV-V7-b2-dispute-b1-order',
      lens: 'V7',
      severity: 'P1',
      title: '2.º comprador abre disputa na encomenda do 1.º',
      actor: 'buyer2 JWT',
      pre: 'order B1',
      repro: 'POST order_disputes order_id=B1 buyer_id=B2',
      expected: 'recusado',
      obtained: d.brief,
    );
  } else {
    c.closed('V7.b2.dispute', 'B2 disputa B1 recusada', d.brief, lens: 'V7');
  }

  final s2 = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.seller2Jwt, body: {
    'status': 'enviado',
  });
  c.note('V7.s2.patch', 'S2 PATCH order S1', s2.brief, lens: 'V7');
  if (s2.ok) {
    final r2 = await c.orderRow(oid);
    if ('${r2?['status']}' == 'enviado' && '${row?['status']}' != 'enviado') {
      c.hold(
        id: 'RTV-V7-s2-patch-s1-order',
        lens: 'V7',
        severity: 'P0',
        title: '2.º vendedor altera encomenda do 1.º',
        actor: 'seller2 JWT',
        pre: 'order S1',
        repro: 'PATCH orders',
        expected: 'RLS bloqueia',
        obtained: {'http': s2.brief, 'status': r2?['status']},
      );
    }
  } else {
    c.closed('V7.s2.patch', 'S2 não escreve order S1', s2.brief, lens: 'V7');
  }

  // B2 checkout da order B1
  final ck = await c.checkoutSingle(
    orderId: oid,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  c.note('V7.b2.checkout', 'B2 create-payment-intent order B1', ck.brief, lens: 'V7');
  if (ck.ok) {
    c.hold(
      id: 'RTV-V7-b2-checkout-b1',
      lens: 'V7',
      severity: 'P0',
      title: '2.º comprador inicia checkout da encomenda do 1.º',
      actor: 'buyer2 JWT',
      pre: 'order buyer=B1',
      repro: 'POST create-payment-intent buyer_id=B2 order_id=B1',
      expected: 'Invalid checkout user / not owner',
      obtained: ck.brief,
    );
  } else {
    c.closed('V7.b2.checkout', 'B2 checkout B1 recusado', ck.brief, lens: 'V7');
  }
}

Future<void> _v8walletRpc(Rtv c) async {
  final credit = await c.rpc(
    'batata_credit_wallet_once',
    {
      'p_wallet_id': c.buyerId,
      'p_order_id': null,
      'p_amount': 50,
      'p_type': 'reembolso',
      'p_description': '$prefix mint',
    },
    jwt: c.buyerJwt,
  );
  c.note('V8.credit.rpc', 'buyer chama batata_credit_wallet_once', credit.brief,
      lens: 'V8');
  if (credit.ok && credit.map?['ok'] != false) {
    // may return boolean
    final body = credit.body;
    if (!body.contains('permission') && credit.status < 400) {
      c.hold(
        id: 'RTV-V8-credit-wallet-jwt',
        lens: 'V8',
        severity: 'P0',
        title: 'JWT chama batata_credit_wallet_once',
        actor: 'buyer JWT',
        pre: 'RPC grant?',
        repro: 'POST rpc/batata_credit_wallet_once',
        expected: '42501 / not granted',
        obtained: credit.brief,
      );
    }
  } else {
    c.closed('V8.credit.rpc', 'credit_wallet_once JWT recusado', credit.brief,
        lens: 'V8');
  }

  final ins = await c.rest('POST', 'wallet_transactions', jwt: c.buyerJwt, body: {
    'wallet_id': c.buyerId,
    'amount': 10,
    'type': 'reembolso',
    'description': prefix,
  });
  c.note('V8.wallet.ins', 'buyer INSERT wallet_transactions', ins.brief, lens: 'V8');
  if (ins.ok) {
    c.hold(
      id: 'RTV-V8-wallet-txn-insert',
      lens: 'V8',
      severity: 'P0',
      title: 'Buyer INSERT directo em wallet_transactions',
      actor: 'buyer JWT',
      pre: 'RLS wallet',
      repro: 'POST wallet_transactions',
      expected: 'bloqueado',
      obtained: ins.brief,
    );
  } else {
    c.closed('V8.wallet.ins', 'INSERT wallet_transactions bloqueado', ins.brief,
        lens: 'V8');
  }
}
