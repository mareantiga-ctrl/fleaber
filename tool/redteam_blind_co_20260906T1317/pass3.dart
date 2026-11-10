/// RED TEAM CEGO CO — pass 3. Staging only. Não corrige.
/// CO-D refund/stock/release ≥4 · cadeia Stripe medida · lentes CO4 CO5 CO6 CO8.
import '_rtco.dart';

Future<void> main() async {
  final c = Rtci.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.well('CO-D');

  Future<({String oid, String pid, String? pi})> mustPay(String lens,
      {int qty = 2}) async {
    final paid = await c.payToPago(lens: lens, initialQty: qty);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  int? stripeFirstCents(HttpHit? h) {
    if (h?.json is Map) {
      final data = (h!.json as Map)['data'];
      if (data is List && data.isNotEmpty && data.first is Map) {
        return numOf((data.first as Map)['amount'])?.round();
      }
    }
    return null;
  }

  // CO-D1 amount body
  final amt = await mustPay('CO4', qty: 2);
  var o = await c.orderRow(amt.oid);
  final paidCents = numOf(o?['amount_paid_cents']) ?? 0;
  final wBeforeAmt = await c.wallets();

  final buyerRf = await c.refund(amt.oid, jwt: c.buyerJwt);
  final buyerOk = buyerRf.ok &&
      buyerRf.body != 'false' &&
      !buyerRf.brief.toLowerCase().contains('403') &&
      buyerRf.status != 403;
  if (buyerOk) {
    c.hold(
      id: 'CO-D4.buyer_refund_seguro',
      lens: 'CO4',
      severity: 'P1',
      title: 'Buyer chama refund-order (Seguro Fleaber seller-only)',
      actor: 'buyer JWT',
      pre: 'pago ${amt.oid}',
      repro: 'POST refund-order JWT buyer',
      expected: '403',
      obtained: buyerRf.brief,
    );
    c.probe(
      id: 'CO-D4.buyer_refund_seguro',
      matrix: 'CO-D',
      payload: 'buyer JWT POST refund-order',
      http: buyerRf.brief,
      result: 'HOLD',
    );
  } else {
    c.block('CO-D4.buyer_refund_seguro', 'CO4', 'buyer refund 403', buyerRf);
    c.probe(
      id: 'CO-D4.buyer_refund_seguro',
      matrix: 'CO-D',
      payload: 'buyer JWT POST refund-order',
      http: buyerRf.brief,
      result: 'FAIL',
    );
  }

  final tiny = await c.refund(amt.oid, extra: {'amount': 1, 'amount_cents': 1});
  o = await c.orderRow(amt.oid);
  final refundsTiny = amt.pi == null ? null : await c.stripeRefunds(amt.pi!);
  final stripeRefundCents = stripeFirstCents(refundsTiny);
  c.note('CO-D1.amount_1', 'refund-order amount=1 no body', {
    'hit': tiny.brief,
    'paid_cents': paidCents,
    'stripe_refund_cents': stripeRefundCents,
    'edge_amount_cents': tiny.map?['amount_cents'],
  }, lens: 'CO4');
  if (tiny.ok &&
      stripeRefundCents != null &&
      stripeRefundCents < paidCents &&
      stripeRefundCents <= 1) {
    c.hold(
      id: 'CO-D1.amount_body',
      lens: 'CO4',
      severity: 'P1',
      title: 'Edge refund-order honra amount=1 no body',
      actor: 'seller JWT',
      pre: 'pago capturado ${paidCents}¢',
      repro: 'POST refund-order {amount:1}',
      expected: 'ignorar amount; refund = amount_paid_cents',
      obtained: {
        'stripe_refund_cents': stripeRefundCents,
        'paid_cents': paidCents,
      },
    );
    c.probe(
      id: 'CO-D1.amount_body',
      matrix: 'CO-D',
      payload: 'refund-order amount=1 amount_cents=1',
      http: tiny.brief,
      bd: 'stripe=${stripeRefundCents} paid=$paidCents',
      result: 'HOLD',
    );
  } else {
    c.block('CO-D1.amount_body', 'CO4', 'amount=1 ignorado', {
      'stripe_refund_cents': stripeRefundCents,
      'paid_cents': paidCents,
      'hit': tiny.brief,
    });
    c.probe(
      id: 'CO-D1.amount_body',
      matrix: 'CO-D',
      payload: 'refund-order amount=1 amount_cents=1',
      http: tiny.brief,
      bd: 'stripe=${stripeRefundCents} paid=$paidCents',
      result: 'FAIL',
    );
  }

  final wAfterAmt = await c.wallets();
  c.note('CO8.wallets_unshipped', 'Δwallet após refund unshipped', {
    'before': wBeforeAmt,
    'after': wAfterAmt,
    'dBuyer': (wAfterAmt['buyer'] ?? 0) - (wBeforeAmt['buyer'] ?? 0),
    'dSeller': (wAfterAmt['seller'] ?? 0) - (wBeforeAmt['seller'] ?? 0),
  }, lens: 'CO8');

  // CO-D2 restore×2 (refund + cancelado)
  final cancel = await mustPay('CO5', qty: 1);
  final qtyC0 = numOf((await c.productRow(cancel.pid))?['quantity']) ?? 0;
  final rfCancel = await c.refund(cancel.oid);
  o = await c.orderRow(cancel.oid);
  final qtyC1 = numOf((await c.productRow(cancel.pid))?['quantity']) ?? 0;
  final cancelPatch = await c.patchOrder(
    cancel.oid,
    {'status': 'cancelado'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(cancel.oid);
  final qtyC2 = numOf((await c.productRow(cancel.pid))?['quantity']) ?? 0;
  c.note('CO-D2.restore_x2', 'refund + PATCH cancelado', {
    'qty0': qtyC0,
    'qty1': qtyC1,
    'qty2': qtyC2,
    'refund': rfCancel.brief,
    'cancel': cancelPatch.brief,
  }, lens: 'CO5');
  if ((qtyC2 - qtyC0) >= 2) {
    c.hold(
      id: 'CO-D2.restore_x2',
      lens: 'CO5',
      severity: 'P1',
      title: 'Stock restaurou 2× (refund + PATCH cancelado)',
      actor: 'seller JWT',
      pre: 'qty=$qtyC0 após venda',
      repro: 'refund-order; PATCH status=cancelado',
      expected: '+1 unidade no total',
      obtained: {'qty0': qtyC0, 'qty1': qtyC1, 'qty2': qtyC2},
    );
    c.probe(
      id: 'CO-D2.restore_x2',
      matrix: 'CO-D',
      payload: 'refund-order depois PATCH cancelado',
      http: 'refund=${rfCancel.brief} cancel=${cancelPatch.brief}',
      bd: 'qty0=$qtyC0 qty1=$qtyC1 qty2=$qtyC2',
      result: 'HOLD',
    );
  } else {
    c.block('CO-D2.restore_x2', 'CO5', 'restore ≤1', {
      'qty0': qtyC0,
      'qty1': qtyC1,
      'qty2': qtyC2,
    });
    c.probe(
      id: 'CO-D2.restore_x2',
      matrix: 'CO-D',
      payload: 'refund-order depois PATCH cancelado',
      http: 'refund=${rfCancel.brief} cancel=${cancelPatch.brief}',
      bd: 'qty0=$qtyC0 qty1=$qtyC1 qty2=$qtyC2',
      result: 'FAIL',
    );
  }

  // Cadeia disputa → devolvida → refund Stripe + stock (obrigatório ≥1)
  final chain = await mustPay('CO5', qty: 1);
  if (!await c.toEnviado(chain.oid)) throw StateError('enviado chain');
  if (!await c.toConcluido(chain.oid)) throw StateError('concluido chain');
  final dHit = await c.insertDispute(orderId: chain.oid);
  final did = dHit.firstId;
  if (!dHit.ok || did == null) {
    c.skip('CO5.dispute', 'CO5', 'disputa chain falhou', dHit);
    await c.dumpAll('pass3.json');
    return;
  }
  await c.patchOrder(chain.oid, {'status': 'pedido_devolucao'}, jwt: c.buyerJwt);
  await c.patchOrder(chain.oid, {'status': 'em_devolucao'}, jwt: c.buyerJwt);
  await c.patchOrder(chain.oid, {'status': 'devolucao_entregue'},
      jwt: c.sellerJwt);

  final qtyBefore = numOf((await c.productRow(chain.pid))?['quantity']) ?? 0;
  final wBeforeDev = await c.wallets();
  final dev = await c.patchOrder(chain.oid, {'status': 'devolvida'},
      jwt: c.sellerJwt);
  o = await c.orderRow(chain.oid);
  var qtyMid = numOf((await c.productRow(chain.pid))?['quantity']) ?? 0;

  final raced = await parallel([c.refund(chain.oid), c.refund(chain.oid)]);
  o = await c.orderRow(chain.oid);
  var qtyAfter = numOf((await c.productRow(chain.pid))?['quantity']) ?? 0;
  final wAfter = await c.wallets();
  final refunds = chain.pi == null ? null : await c.stripeRefunds(chain.pi!);
  var stripeRefundN = 0;
  var stripeRefundSum = 0;
  if (refunds?.json is Map) {
    final data = (refunds!.json as Map)['data'];
    if (data is List) {
      stripeRefundN = data.length;
      for (final e in data) {
        if (e is Map) stripeRefundSum += numOf(e['amount'])?.round() ?? 0;
      }
    }
  }
  final paidChain = numOf(o?['amount_paid_cents']) ?? 0;
  c.note('CO8.chain_stripe', 'cadeia disputa→devolvida→2× refund-order', {
    'oid': chain.oid,
    'pi': chain.pi,
    'paid': paidChain,
    'qty_before': qtyBefore,
    'qty_mid': qtyMid,
    'qty_after': qtyAfter,
    'stripe_n': stripeRefundN,
    'stripe_sum': stripeRefundSum,
    'hits': raced.map((h) => h.brief).toList(),
    'dBuyer': (wAfter['buyer'] ?? 0) - (wBeforeDev['buyer'] ?? 0),
    'dSeller': (wAfter['seller'] ?? 0) - (wBeforeDev['seller'] ?? 0),
  }, lens: 'CO8');
  c.probe(
    id: 'CO8.stripe_refund_chain',
    matrix: 'CO-D',
    payload: 'disputa→devolvida→2× refund-order Stripe TEST',
    http: raced.map((h) => h.brief).join(' | '),
    bd: 'paid=$paidChain stripe_n=$stripeRefundN stripe_sum=$stripeRefundSum '
        'qty $qtyBefore→$qtyAfter Δbuyer=${(wAfter['buyer'] ?? 0) - (wBeforeDev['buyer'] ?? 0)} '
        'Δseller=${(wAfter['seller'] ?? 0) - (wBeforeDev['seller'] ?? 0)}',
    result: (qtyAfter - qtyBefore) >= 2 ||
            (stripeRefundN > 1 && stripeRefundSum > paidChain)
        ? 'HOLD'
        : 'FAIL',
  );
  if ((qtyAfter - qtyBefore) >= 2) {
    c.hold(
      id: 'CO-D2.stock_restore_dup_chain',
      lens: 'CO5',
      severity: 'P1',
      title: 'Restore de stock duplicado no refund após devolvida',
      actor: 'seller JWT',
      pre: 'qty=$qtyBefore',
      repro: 'Future.wait 2× refund-order',
      expected: '+1 unidade',
      obtained: {
        'qty_before': qtyBefore,
        'qty_after': qtyAfter,
        'stripe_n': stripeRefundN,
      },
    );
  } else {
    c.block('CO-D2.stock_restore_dup_chain', 'CO5', 'stock restore uma vez', {
      'qty_before': qtyBefore,
      'qty_after': qtyAfter,
    });
  }
  if (stripeRefundN > 1 && stripeRefundSum > paidChain) {
    c.hold(
      id: 'CO-D1.refund_race_double_stripe',
      lens: 'CO4',
      severity: 'P0',
      title: 'Race 2× refund-order criou dois refunds Stripe',
      actor: 'seller JWT',
      pre: 'devolvida + PI ${chain.pi}',
      repro: 'Future.wait 2× POST refund-order',
      expected: '1 refund ≤ captura',
      obtained: {'n': stripeRefundN, 'sum': stripeRefundSum, 'paid': paidChain},
    );
  } else {
    c.block('CO-D1.refund_race_double_stripe', 'CO4', 'refund race idempotente', {
      'n': stripeRefundN,
      'sum': stripeRefundSum,
      'paid': paidChain,
    });
  }

  // CO-D3 release ∥ disputa
  final rel2 = await mustPay('CO6', qty: 1);
  if (!await c.toEnviado(rel2.oid)) throw StateError('env rel2');
  if (!await c.toConcluido(rel2.oid)) throw StateError('conc rel2');
  final dOpen = await c.insertDispute(orderId: rel2.oid);
  final wRel2a = await c.wallets();
  final relBlocked = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': rel2.oid},
    jwt: c.buyerJwt,
  );
  final wRel2b = await c.wallets();
  final dSellerOpen = (wRel2b['seller'] ?? 0) - (wRel2a['seller'] ?? 0);
  final releasedAnyway = relBlocked.ok &&
      relBlocked.body != 'false' &&
      relBlocked.map?['ok'] != false &&
      dSellerOpen > 0;
  c.note('CO-D3.release_open_dispute', 'release com disputa aberta', {
    'dispute': dOpen.brief,
    'release': relBlocked.brief,
    'dSeller': dSellerOpen,
  }, lens: 'CO6');
  if (releasedAnyway) {
    c.hold(
      id: 'CO-D3.release_with_open_dispute',
      lens: 'CO6',
      severity: 'P0',
      title: 'Release da carteira com disputa aberta',
      actor: 'buyer JWT',
      pre: 'concluido + disputa ${dOpen.firstId}',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false / sem Δseller',
      obtained: {'hit': relBlocked.brief, 'dSeller': dSellerOpen},
    );
    c.probe(
      id: 'CO-D3.release_with_open_dispute',
      matrix: 'CO-D',
      payload: 'release RPC com disputa aberta',
      http: relBlocked.brief,
      bd: 'Δseller=$dSellerOpen',
      result: 'HOLD',
    );
  } else {
    c.block('CO-D3.release_with_open_dispute', 'CO6',
        'release bloqueado com disputa aberta', {
      'hit': relBlocked.brief,
      'dSeller': dSellerOpen,
    });
    c.probe(
      id: 'CO-D3.release_with_open_dispute',
      matrix: 'CO-D',
      payload: 'release RPC com disputa aberta',
      http: relBlocked.brief,
      bd: 'Δseller=$dSellerOpen',
      result: 'FAIL',
    );
  }

  final rel3 = await mustPay('CO6', qty: 1);
  if (!await c.toEnviado(rel3.oid)) throw StateError('env rel3');
  if (!await c.toConcluido(rel3.oid)) throw StateError('conc rel3');
  final wR3a = await c.wallets();
  final raceRel = await Future.wait([
    c.rpc('batata_release_seller_wallet_for_order', {'p_order_id': rel3.oid},
        jwt: c.buyerJwt),
    c.insertDispute(orderId: rel3.oid),
  ]);
  final wR3b = await c.wallets();
  final dRace = (wR3b['seller'] ?? 0) - (wR3a['seller'] ?? 0);
  o = await c.orderRow(rel3.oid);
  final dispRace = await c.rest(
    'GET',
    'order_disputes?order_id=eq.${rel3.oid}&select=id,status',
    service: true,
  );
  final disputeOpen = dispRace.list.isNotEmpty;
  final released = o?['wallet_release_processed_at'] != null && dRace > 0;
  c.note('CO-D3.race_release_dispute', 'race release ∥ INSERT disputa', {
    'hits': raceRel.map((h) => h.brief).toList(),
    'dSeller': dRace,
    'release_at': o?['wallet_release_processed_at'],
    'disputes': dispRace.brief,
  }, lens: 'CO6');
  if (disputeOpen && released) {
    c.hold(
      id: 'CO-D3.race_release_and_dispute',
      lens: 'CO6',
      severity: 'P0',
      title: 'Race: release creditou E disputa ficou aberta',
      actor: 'buyer JWT',
      pre: 'concluido ${rel3.oid}',
      repro: 'Future.wait release + POST disputa',
      expected: 'release XOR disputa',
      obtained: {
        'dSeller': dRace,
        'disputes': dispRace.brief,
      },
    );
    c.probe(
      id: 'CO-D3.race_release_dispute',
      matrix: 'CO-D',
      payload: 'parallel release RPC ∥ INSERT disputa',
      http: raceRel.map((h) => h.brief).join(' | '),
      bd: 'Δseller=$dRace dispute_open=$disputeOpen released=$released',
      result: 'HOLD',
    );
  } else {
    c.block('CO-D3.race_release_dispute', 'CO6',
        'race release∥disputa XOR', {
      'dSeller': dRace,
      'dispute_open': disputeOpen,
      'released': released,
    });
    c.probe(
      id: 'CO-D3.race_release_dispute',
      matrix: 'CO-D',
      payload: 'parallel release RPC ∥ INSERT disputa',
      http: raceRel.map((h) => h.brief).join(' | '),
      bd: 'Δseller=$dRace dispute_open=$disputeOpen released=$released',
      result: 'FAIL',
    );
  }

  c.note('CO8.wallets_final', 'wallets fim pass3', await c.wallets(),
      lens: 'CO8');
  await c.dumpAll('pass3.json');
}
