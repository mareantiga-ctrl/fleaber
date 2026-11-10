/// PASS 2 — Q3 devolução/O34 · Q5 FSM disputa · Q8 composição caixa.
import 'dart:io';

import '_rtq.dart';

Future<String?> openDispute(Rtq c, String oid, {String lens = 'Q5'}) async {
  final ins = await c.rest('POST', 'order_disputes', jwt: c.buyerJwt, body: {
    'order_id': oid,
    'buyer_id': c.buyerId,
    'reason': 'nao_corresponde',
    'description': '$prefix disputa',
    'status': 'aberta',
  });
  c.note('p2.dispute.insert', 'buyer INSERT disputa', ins.brief, lens: lens);
  final id = ins.firstId;
  if (id != null) c.createdDisputeIds.add(id);
  return id;
}

void main() async {
  final env = loadEnv();
  final c = Rtq.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final w0 = await c.wallets();
  c.note('p2.wallets.start', 'saldos iniciais', w0, lens: 'Q8');

  // ---- Stripe TEST pago → enviado → entregue (sem concluido) ----
  final oid = await c.payToEntregue(lens: 'Q3');
  if (oid == null) {
    stderr.writeln('payToEntregue failed');
    await dumpJson('${outDir()}/pass2.json', {'error': 'no_paid_order'});
    exit(1);
  }
  final o0 = await c.orderRow(oid);
  final pid = o0?['product_id']?.toString();
  c.note('p2.order0', 'ordem entregue', o0, lens: 'Q3');

  // Q3: aliases devolvida / returned
  for (final st in ['devolvida', 'returned', 'refunded', 'devolvido']) {
    final h = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: c.sellerJwt,
      body: {'status': st},
    );
    c.note('p2.q3.alias.$st', 'seller PATCH status=$st', h.brief, lens: 'Q3');
  }
  var oNow = await c.orderRow(oid);
  if (oNow?['status'] == 'devolvida' &&
      (oNow?['stripe_refund_id'] == null ||
          '${oNow?['stripe_refund_id']}'.trim().isEmpty)) {
    c.hold(
      id: 'RTQ-Q3-devolvida-direct-no-stripe',
      lens: 'Q3',
      severity: 'P0',
      title: 'devolvida sem stripe_refund_id (O3 aberto)',
      actor: 'seller JWT',
      pre: 'Stripe capturado entregue',
      repro: 'PATCH orders status=devolvida',
      expected: 'order_devolvida_requires_refund',
      obtained: oNow,
    );
  }

  // Q3: fake stripe_refund_id
  final fakeRf = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.sellerJwt,
    body: {'stripe_refund_id': 're_fake_q0735'},
  );
  c.note('p2.q3.fake.refund.id', 'PATCH stripe_refund_id fake', fakeRf.brief,
      lens: 'Q3');
  final flipPm = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.sellerJwt,
    body: {'payment_method': 'transferencia bancaria'},
  );
  c.note('p2.q3.flip.pm', 'PATCH payment_method off-platform', flipPm.brief,
      lens: 'Q3');

  // ---- Disputa ----
  final did = await openDispute(c, oid);
  if (did == null) {
    c.note('p2.dispute.fail', 'INSERT disputa falhou — resto em SKIP', oNow,
        lens: 'Q5');
  } else {
    // Q5: seller English / recusada / resolvida / forge buyer_decision
    final pResolved = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'status': 'resolved'},
    );
    final pFechada = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'status': 'fechada'},
    );
    final pResolvida = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'status': 'resolvida'},
    );
    c.note('p2.q5.seller.close', 'seller tenta fechar disputa', {
      'resolved': pResolved.brief,
      'fechada': pFechada.brief,
      'resolvida': pResolvida.brief,
    }, lens: 'Q5');
    var d1 = await c.disputeRow(did);
    if (d1?['status'] == 'resolvida') {
      c.hold(
        id: 'RTQ-Q5-seller-resolvida-unilateral',
        lens: 'Q5',
        severity: 'P1',
        title: 'Vendedor PATCH resolvida sem decisão do comprador',
        actor: 'seller JWT',
        pre: 'disputa aberta',
        repro: 'PATCH order_disputes status=resolvida',
        expected: 'status permanece aberta',
        obtained: d1,
      );
    }

    // Variante nova: forjar buyer_decision + resolvida no mesmo PATCH
    final forgeClose = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {
        'buyer_decision': 'accepted_partial_refund',
        'status': 'resolvida',
      },
    );
    final dForge = await c.disputeRow(did);
    c.note('p2.q5.forge.decision', 'seller forja buyer_decision+resolvida', {
      'patch': forgeClose.brief,
      'row': dForge,
    }, lens: 'Q5');
    if (dForge?['status'] == 'resolvida' &&
        dForge?['buyer_decision'] == 'accepted_partial_refund') {
      c.hold(
        id: 'RTQ-Q5-seller-forge-buyer-decision-resolvida',
        lens: 'Q5',
        severity: 'P1',
        title: 'Vendedor forja buyer_decision e fecha resolvida no mesmo PATCH',
        actor: 'seller JWT',
        pre: 'Q5 só olha NEW.buyer_decision',
        repro:
            'PATCH order_disputes {buyer_decision:accepted_partial_refund, status:resolvida}',
        expected: 'buyer_decision imutável para o vendedor; sem salto resolvida',
        obtained: dForge,
      );
    }

    // recusada unilateral
    final pRec = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {'status': 'recusada'},
    );
    final dRec = await c.disputeRow(did);
    c.note('p2.q5.recusada', 'seller PATCH recusada', {
      'patch': pRec.brief,
      'row': dRec,
    }, lens: 'Q5');
    if (dRec?['status'] == 'recusada') {
      c.hold(
        id: 'RTQ-Q5-seller-recusada-unilateral',
        lens: 'Q5',
        severity: 'P1',
        title: 'Vendedor recusa a disputa sozinho (FSM terminal)',
        actor: 'seller JWT',
        pre: 'disputa aberta',
        repro: 'PATCH order_disputes status=recusada',
        expected: 'só admin/comprador fecha recusada',
        obtained: dRec,
      );
    }

    // 2.º buyer na disputa
    final dB2 = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.buyer2Jwt,
      body: {'status': 'resolvida', 'buyer_decision': 'accepted_return'},
    );
    c.note('p2.q7.b2.dispute', 'buyer2 PATCH disputa alheia', dB2.brief,
        lens: 'Q7');

    // Buyer forja oferta do vendedor (variante Q3/Q8)
    final forgeOffer = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.buyerJwt,
      body: {
        'seller_refund_percent': 40,
        'seller_offer_type': 'partial_refund',
        'seller_offer_set_by': c.sellerId,
      },
    );
    final dOffer = await c.disputeRow(did);
    c.note('p2.q5.buyer.forge.offer', 'buyer forja oferta 40%', {
      'patch': forgeOffer.brief,
      'row': dOffer,
    }, lens: 'Q5');
    final forged =
        numOf(dOffer?['seller_refund_percent']) == 40 &&
            dOffer?['seller_offer_set_by']?.toString() == c.sellerId;
    if (forged) {
      c.hold(
        id: 'RTQ-Q5-buyer-forge-seller-offer',
        lens: 'Q5',
        severity: 'P1',
        title: 'Comprador escreve seller_refund_percent e seller_offer_set_by',
        actor: 'buyer JWT',
        pre: 'disputa aberta; RLS update_participants',
        repro:
            'PATCH order_disputes seller_refund_percent=40 seller_offer_set_by=seller',
        expected: 'só o vendedor define oferta',
        obtained: dOffer,
      );
    }

    // pedido_devolucao (caminho Q3/Q8 — estado fora da lista Q8 stripe)
    final toPed = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: c.buyerJwt,
      body: {'status': 'pedido_devolucao'},
    );
    c.note('p2.q3.pedido', 'buyer pedido_devolucao', toPed.brief, lens: 'Q3');
    oNow = await c.orderRow(oid);

    final wBeforePart = await c.wallets();
    final part = await c.rpc('batata_process_partial_refund_dispute', {
      'p_order_id': oid,
    }, jwt: c.buyerJwt);
    final partS2 = await c.rpc('batata_process_partial_refund_dispute', {
      'p_order_id': oid,
    }, jwt: c.seller2Jwt);
    final wAfterPart = await c.wallets();
    final oPart = await c.orderRow(oid);
    c.note('p2.q8.partial.pedido', 'process_partial em pedido_devolucao', {
      'buyer': part.brief,
      'seller2': partS2.brief,
      'w_before': wBeforePart,
      'w_after': wAfterPart,
      'delta_buyer': (wAfterPart['buyer'] ?? 0) - (wBeforePart['buyer'] ?? 0),
      'delta_seller': (wAfterPart['seller'] ?? 0) - (wBeforePart['seller'] ?? 0),
      'order': {
        'status': oPart?['status'],
        'stripe_refund_id': oPart?['stripe_refund_id'],
        'wallet_refund_processed_at': oPart?['wallet_refund_processed_at'],
        'pi': oPart?['stripe_payment_intent_id'],
      },
    }, lens: 'Q8');

    final dBuyer = (wAfterPart['buyer'] ?? 0) - (wBeforePart['buyer'] ?? 0);
    final noStripe = oPart?['stripe_refund_id'] == null ||
        '${oPart?['stripe_refund_id']}'.trim().isEmpty;
    if (part.ok && dBuyer > 0 && noStripe) {
      c.hold(
        id: 'RTQ-Q8-partial-wallet-mint-on-return-path',
        lens: 'Q8',
        severity: 'P0',
        title:
            'process_partial em pedido_devolucao minta carteira sem Stripe refund',
        actor: 'buyer JWT',
        pre:
            'pago Stripe + enviado + entregue + disputa + pedido_devolucao; oferta 40%',
        repro: 'rpc batata_process_partial_refund_dispute',
        expected:
            'dispute_partial_refund_requires_stripe / sem Δwallet sem stripe_refund_id',
        obtained: {
          'delta_buyer': dBuyer,
          'delta_seller':
              (wAfterPart['seller'] ?? 0) - (wBeforePart['seller'] ?? 0),
          'stripe_refund_id': oPart?['stripe_refund_id'],
          'rpc': part.brief,
        },
      );
    }

    // Q3 ciclo devolução até devolvida
    await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
      'status': 'em_devolucao',
    });
    await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
      'status': 'devolucao_entregue',
    });
    final toDev = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: c.sellerJwt,
      body: {'status': 'devolvida'},
    );
    final oDev = await c.orderRow(oid);
    c.note('p2.q3.cycle.devolvida', 'ciclo até devolvida', {
      'patch': toDev.brief,
      'order': oDev,
    }, lens: 'Q3');
    if (oDev?['status'] == 'devolvida' &&
        (oDev?['stripe_refund_id'] == null ||
            '${oDev?['stripe_refund_id']}'.trim().isEmpty)) {
      c.hold(
        id: 'RTQ-Q3-return-cycle-devolvida-no-stripe',
        lens: 'Q3',
        severity: 'P0',
        title: 'Ciclo devolução chega a devolvida sem stripe_refund_id',
        actor: 'seller JWT',
        pre: 'pedido_devolucao→em_devolucao→devolucao_entregue',
        repro: 'PATCH status=devolvida',
        expected: 'order_devolvida_requires_refund',
        obtained: oDev,
      );
    }

    // proof_url / label wrap variantes (não clássico evil.com)
    final proof = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: c.buyerJwt,
      body: {
        'proof_url':
            'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/x#https://evil.test/p',
      },
    );
    final label = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: c.sellerJwt,
      body: {
        'return_label_url':
            'https://fleaber.app/l?next=https://evil.test/steal',
      },
    );
    c.note('p2.q3.urls', 'proof fragment + label query wrap', {
      'proof': proof.brief,
      'label': label.brief,
    }, lens: 'Q3');
  }

  // ---- Nova ordem: oferta 100% + process_partial vs refund-order (legítimo) ----
  final oid2 = await c.payToEntregue(lens: 'Q3');
  if (oid2 != null) {
    final did2 = await openDispute(c, oid2, lens: 'Q4');
    if (did2 != null) {
      final offer100 = await c.rest(
        'PATCH',
        'order_disputes?id=eq.$did2',
        jwt: c.sellerJwt,
        body: {
          'seller_refund_percent': 100,
          'seller_offer_type': 'partial_refund',
          'seller_offer_set_by': c.sellerId,
        },
      );
      c.note('p2.legit.offer100', 'seller oferta 100%', offer100.brief,
          lens: 'Q4');
      final wB = await c.wallets();
      final part100 = await c.rpc('batata_process_partial_refund_dispute', {
        'p_order_id': oid2,
      }, jwt: c.buyerJwt);
      c.note('p2.q3.partial100', 'process_partial 100% em entregue',
          part100.brief,
          lens: 'Q3');
      if (part100.ok) {
        final wA = await c.wallets();
        final o2 = await c.orderRow(oid2);
        final db = (wA['buyer'] ?? 0) - (wB['buyer'] ?? 0);
        if (db > 0 &&
            (o2?['stripe_refund_id'] == null ||
                '${o2?['stripe_refund_id']}'.trim().isEmpty)) {
          c.hold(
            id: 'RTQ-Q3-partial100-wallet-no-stripe',
            lens: 'Q3',
            severity: 'P0',
            title: 'process_partial 100% minta carteira sem Stripe',
            actor: 'buyer JWT',
            pre: 'oferta 100% em entregue',
            repro: 'rpc batata_process_partial_refund_dispute',
            expected: 'dispute_full_refund_requires_stripe',
            obtained: {'delta_buyer': db, 'order': o2, 'rpc': part100.brief},
          );
        }
      }
      final rf = await c.edge('refund-order', {'order_id': oid2}, jwt: c.sellerJwt);
      c.note('p2.legit.refund-order', 'refund-order após oferta 100%', rf.brief,
          lens: 'Q8');
      final o2b = await c.orderRow(oid2);
      c.note('p2.legit.refund.result', 'ordem após refund-order', o2b,
          lens: 'Q8');
    }
  }

  // Q6: inflacionar stock com encomenda activa
  if (pid != null) {
    final pBefore = await c.productRow(pid);
    final bump = await c.rest(
      'PATCH',
      'products?id=eq.$pid',
      jwt: c.sellerJwt,
      body: {'quantity': 99, 'is_sold': false, 'list_on_marketplace': true},
    );
    final pAfter = await c.productRow(pid);
    c.note('p2.q6.qty.bump', 'seller PATCH quantity=99 com ordem activa', {
      'before': pBefore?['quantity'],
      'patch': bump.brief,
      'after': pAfter?['quantity'],
      'is_sold': pAfter?['is_sold'],
    }, lens: 'Q6');
    final qb = numOf(pBefore?['quantity']) ?? 0;
    final qa = numOf(pAfter?['quantity']) ?? 0;
    if (bump.ok && qa > qb) {
      c.hold(
        id: 'RTQ-Q6-relist-qty-with-active-order',
        lens: 'Q6',
        severity: 'P1',
        title: 'Vendedor sobe quantity / relista com encomenda activa',
        actor: 'seller JWT',
        pre: 'ordem Stripe com stock_units_applied',
        repro: 'PATCH products quantity=99 is_sold=false',
        expected: 'product_quantity_increase_blocked_active_order',
        obtained: {'before': qb, 'after': qa, 'order_status': oNow?['status']},
      );
    }
  }

  await dumpJson('${outDir()}/pass2.json', {
    'findings': c.findings,
    'notes': c.notes,
    'wallets_end': await c.wallets(),
  });
  stdout.writeln('PASS2 findings=${c.findings.length}');
  exit(0);
}
