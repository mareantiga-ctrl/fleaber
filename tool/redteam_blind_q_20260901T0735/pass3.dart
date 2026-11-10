/// PASS 3 — Q4 races (verbos ≠ N/O) · Q6 stock∩refund · Q8 composição.
import 'dart:io';

import '_rtq.dart';

void main() async {
  final env = loadEnv();
  final c = Rtq.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  // ---- Race A: process_partial ∥ refund-order em pedido_devolucao (≠ N/O) ----
  final oid = await c.payToEntregue(lens: 'Q4');
  if (oid == null) {
    stderr.writeln('no paid order');
    exit(1);
  }
  final insD = await c.rest('POST', 'order_disputes', jwt: c.buyerJwt, body: {
    'order_id': oid,
    'buyer_id': c.buyerId,
    'reason': 'danificado',
    'description': '$prefix race',
    'status': 'aberta',
  });
  final did = insD.firstId;
  if (did != null) c.createdDisputeIds.add(did);
  if (did != null) {
    await c.rest('PATCH', 'order_disputes?id=eq.$did', jwt: c.sellerJwt, body: {
      'seller_refund_percent': 40,
      'seller_offer_type': 'partial_refund',
      'seller_offer_set_by': c.sellerId,
    });
  }
  await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
    'status': 'pedido_devolucao',
  });

  final oPre = await c.orderRow(oid);
  final wPre = await c.wallets();
  final race = await parallel([
    c.rpc('batata_process_partial_refund_dispute', {'p_order_id': oid},
        jwt: c.buyerJwt),
    c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt),
  ]);
  final oRace = await c.orderRow(oid);
  final wRace = await c.wallets();
  final txns = await c.walletTxns(orderId: oid);
  c.note('p3.q4.partial.vs.refund', 'process_partial ∥ refund-order', {
    'partial': race[0].brief,
    'refund_order': race[1].brief,
    'w_pre': wPre,
    'w_post': wRace,
    'delta_buyer': (wRace['buyer'] ?? 0) - (wPre['buyer'] ?? 0),
    'order_pre': {
      'status': oPre?['status'],
      'stripe_refund_id': oPre?['stripe_refund_id'],
      'wallet_refund': oPre?['wallet_refund_processed_at'],
    },
    'order_post': {
      'status': oRace?['status'],
      'stripe_refund_id': oRace?['stripe_refund_id'],
      'wallet_refund': oRace?['wallet_refund_processed_at'],
      'pi': oRace?['stripe_payment_intent_id'],
    },
    'txns': txns.take(8).toList(),
  }, lens: 'Q4');

  final dBuy = (wRace['buyer'] ?? 0) - (wPre['buyer'] ?? 0);
  final hasStripeRf = (oRace?['stripe_refund_id'] ?? '').toString().trim().isNotEmpty;
  if (dBuy > 0 && hasStripeRf) {
    c.hold(
      id: 'RTQ-Q4-partial-parallel-refund-order-double',
      lens: 'Q4',
      severity: 'P0',
      title: 'Race: carteira mint + Stripe refund no mesmo PI',
      actor: 'buyer process_partial ∥ seller refund-order',
      pre: 'pedido_devolucao + oferta 40%',
      repro: 'Future.wait rpc process_partial + POST refund-order',
      expected: 'um caminho só; sem Δwallet+stripe_refund_id',
      obtained: {
        'delta_buyer': dBuy,
        'stripe_refund_id': oRace?['stripe_refund_id'],
        'partial': race[0].brief,
        'refund': race[1].brief,
      },
    );
  }

  // ---- Race B: PATCH recusada ∥ process_partial (verbo novo) ----
  final oidB = await c.payToEntregue(lens: 'Q4');
  if (oidB != null) {
    final insB = await c.rest('POST', 'order_disputes', jwt: c.buyerJwt, body: {
      'order_id': oidB,
      'buyer_id': c.buyerId,
      'reason': 'em_falta',
      'description': '$prefix raceB',
    });
    final didB = insB.firstId;
    if (didB != null) {
      c.createdDisputeIds.add(didB);
      await c.rest(
        'PATCH',
        'order_disputes?id=eq.$didB',
        jwt: c.sellerJwt,
        body: {
          'seller_refund_percent': 50,
          'seller_offer_type': 'partial_refund',
          'seller_offer_set_by': c.sellerId,
        },
      );
      await c.rest('PATCH', 'orders?id=eq.$oidB', jwt: c.buyerJwt, body: {
        'status': 'pedido_devolucao',
      });
      final wB0 = await c.wallets();
      final raceB = await parallel([
        c.rest('PATCH', 'order_disputes?id=eq.$didB', jwt: c.sellerJwt, body: {
          'status': 'recusada',
        }),
        c.rpc('batata_process_partial_refund_dispute', {'p_order_id': oidB},
            jwt: c.buyerJwt),
      ]);
      final wB1 = await c.wallets();
      final dB = await c.disputeRow(didB);
      final oB = await c.orderRow(oidB);
      c.note('p3.q4.recusada.vs.partial', 'recusada ∥ process_partial', {
        'recusada': raceB[0].brief,
        'partial': raceB[1].brief,
        'delta_buyer': (wB1['buyer'] ?? 0) - (wB0['buyer'] ?? 0),
        'dispute': dB,
        'order_status': oB?['status'],
        'stripe_refund_id': oB?['stripe_refund_id'],
      }, lens: 'Q4');
      final db = (wB1['buyer'] ?? 0) - (wB0['buyer'] ?? 0);
      if (dB?['status'] == 'recusada' && db > 0) {
        c.hold(
          id: 'RTQ-Q4-recusada-parallel-wallet-mint',
          lens: 'Q4',
          severity: 'P1',
          title: 'Race recusada ∥ process_partial: disputa morta mas carteira creditada',
          actor: 'seller PATCH recusada ∥ buyer RPC',
          pre: 'oferta 50% + pedido_devolucao',
          repro: 'Future.wait PATCH recusada + process_partial',
          expected: 'mutex; recusada sem mint',
          obtained: {
            'delta_buyer': db,
            'dispute': dB?['status'],
            'wallet_refund': oB?['wallet_refund_processed_at'],
          },
        );
      }
    }
  }

  // ---- Race C: accept live ∥ PATCH live ended (Q2∩Q4) ----
  final live = await c.insertLive(seller: c.sellerId);
  final item = await c.insertLiveItem(
    liveId: live ?? '',
    title: '$prefix race-item',
    qty: 2,
  );
  final pend = await c.rest(
    'POST',
    'live_reservation_requests',
    jwt: c.buyerJwt,
    body: {
      'live_id': live,
      'live_item_id': item,
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'requested_qty': 1,
      'status': 'pending',
      'source': 'fleaber_live',
    },
  );
  final rid = pend.firstId;
  if (rid != null) c.createdRequestIds.add(rid);
  if (rid != null && live != null) {
    final raceC = await parallel([
      c.rpc('batata_process_live_reservation_request', {
        'p_request_id': rid,
        'p_action': 'accept',
      }, jwt: c.sellerJwt),
      c.rest('PATCH', 'lives?id=eq.$live', jwt: c.sellerJwt, body: {
        'status': 'ended',
        'is_active': false,
      }),
    ]);
    final resC = await c.reservationRow(rid);
    final liveC = await c.liveRow(live);
    c.note('p3.q4.accept.vs.end', 'RPC accept ∥ PATCH live ended', {
      'accept': raceC[0].brief,
      'end': raceC[1].brief,
      'res': resC,
      'live': {'status': liveC?['status'], 'is_active': liveC?['is_active']},
    }, lens: 'Q4');
  }

  // ---- Q6: stock após refund-order (item relistado, comprador ainda "dono") ----
  final oidC = await c.payToEntregue(lens: 'Q6');
  if (oidC != null) {
    final oC0 = await c.orderRow(oidC);
    final pid = oC0?['product_id']?.toString();
    // refund-order em entregue pode estar bloqueado (pós-envio) — tentar
    final rf = await c.edge('refund-order', {'order_id': oidC}, jwt: c.sellerJwt);
    final oC1 = await c.orderRow(oidC);
    Map<String, dynamic>? p1;
    HttpHit? relist;
    if (pid != null) {
      final p0 = await c.productRow(pid);
      relist = await c.rest(
        'PATCH',
        'products?id=eq.$pid',
        jwt: c.sellerJwt,
        body: {'quantity': 7, 'is_sold': false, 'list_on_marketplace': true},
      );
      p1 = await c.productRow(pid);
      c.note('p3.q6.relist.after.refund', 'relist pós refund-order', {
        'refund': rf.brief,
        'order_status': oC1?['status'],
        'qty0': p0?['quantity'],
        'relist': relist.brief,
        'qty1': p1?['quantity'],
        'is_sold': p1?['is_sold'],
        'buyer_still_order': oC1?['buyer_id'] == c.buyerId,
      }, lens: 'Q6');
    }
    final qtyUp = pid != null &&
        relist != null &&
        relist.ok &&
        (numOf(p1?['quantity']) ?? 0) >= 7;
    final buyerOwns = oC1?['status']?.toString() == 'entregue' ||
        oC1?['status']?.toString() == 'pago' ||
        oC1?['status']?.toString() == 'enviado';
    if (qtyUp && buyerOwns) {
      c.hold(
        id: 'RTQ-Q6-relist-while-buyer-owns',
        lens: 'Q6',
        severity: 'P1',
        title: 'SKU relistado com comprador ainda dono na encomenda',
        actor: 'seller JWT',
        pre: 'ordem entregue; refund-order tentado',
        repro: 'POST refund-order; PATCH products quantity=7 is_sold=false',
        expected: 'sem relist enquanto stock_units_applied>0 e status activo',
        obtained: {
          'order': oC1?['status'],
          'stripe_refund_id': oC1?['stripe_refund_id'],
          'qty': p1?['quantity'],
          'refund': rf.brief,
        },
      );
    }
  }

  // ---- Q8 composição: 2.º disputa INSERT (buyer2) na ordem ----
  if (oid != null) {
    final ins2 = await c.rest('POST', 'order_disputes', jwt: c.buyer2Jwt, body: {
      'order_id': oid,
      'buyer_id': c.buyer2Id,
      'reason': 'outro',
      'description': '$prefix b2 hijack',
    });
    c.note('p3.q7.b2.dispute.insert', 'buyer2 INSERT disputa na ordem alheia',
        ins2.brief,
        lens: 'Q7');
    if (ins2.ok) {
      c.hold(
        id: 'RTQ-Q7-buyer2-insert-dispute-foreign-order',
        lens: 'Q7',
        severity: 'P1',
        title: '2.º comprador abre disputa numa encomenda que não é sua',
        actor: 'buyer2 JWT',
        pre: 'ordem buyer1',
        repro: 'POST order_disputes order_id alheio buyer_id=self',
        expected: 'RLS insert_buyer falha',
        obtained: ins2.brief,
      );
    }
  }

  await dumpJson('${outDir()}/pass3.json', {
    'findings': c.findings,
    'notes': c.notes,
  });
  await c.endLives();
  stdout.writeln('PASS3 findings=${c.findings.length}');
  exit(0);
}
