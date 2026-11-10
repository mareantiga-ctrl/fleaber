/// RED TEAM CEGO BW — pass 3. Staging only. Não corrige.
/// Lentes BW4 refund · BW5 stock dup · BW6 release · BW8 caixa.
/// Novas: Edge amount no body · refund parcial · stock restore dup.
import '_rtbw.dart';

Future<void> main() async {
  final c = Rtbw.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  Future<({String oid, String pid, String? pi})> mustPay(String lens,
      {int qty = 2}) async {
    final paid = await c.payToPago(lens: lens, initialQty: qty);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  Future<void> expectBlock(
    String id,
    String lens,
    String title,
    HttpHit hit, {
    String severity = 'P1',
  }) async {
    final truthy = hit.ok &&
        hit.body != 'false' &&
        hit.body != 'null' &&
        hit.map?['ok'] != false;
    if (truthy) {
      c.hold(
        id: id,
        lens: lens,
        severity: severity,
        title: title,
        actor: 'JWT',
        pre: id,
        repro: id,
        expected: '401/403/false',
        obtained: hit.brief,
      );
    } else {
      c.block(id, lens, title, hit);
    }
  }

  // =========================================================================
  // BW4 — Edge amount no body (pago, sem enviado)
  // =========================================================================
  final amt = await mustPay('BW4', qty: 2);
  var o = await c.orderRow(amt.oid);
  final paidCents = numOf(o?['amount_paid_cents']) ?? 0;
  final wBeforeAmt = await c.wallets();

  await expectBlock(
    'BW4.buyer_refund_order',
    'BW4',
    'Buyer chama refund-order',
    await c.refund(amt.oid, jwt: c.buyerJwt),
  );

  final tiny = await c.refund(amt.oid, extra: {'amount': 1, 'amount_cents': 1});
  o = await c.orderRow(amt.oid);
  final refundsTiny = amt.pi == null
      ? null
      : await c.stripeRefunds(amt.pi!);
  int? stripeRefundCents;
  if (refundsTiny?.json is Map) {
    final data = (refundsTiny!.json as Map)['data'];
    if (data is List && data.isNotEmpty && data.first is Map) {
      stripeRefundCents = numOf((data.first as Map)['amount'])?.round();
    }
  }
  c.note('BW4.amount_1', 'refund-order amount=1 no body', {
    'hit': tiny.brief,
    'order_refund': o?['stripe_refund_id'],
    'order_status': o?['status'],
    'paid_cents': paidCents,
    'stripe_refund_cents': stripeRefundCents,
    'edge_amount_cents': tiny.map?['amount_cents'],
  }, lens: 'BW4');

  if (tiny.ok && stripeRefundCents != null && stripeRefundCents < paidCents && stripeRefundCents <= 1) {
    c.hold(
      id: 'BW4.edge_amount_body_partial',
      lens: 'BW4',
      severity: 'P1',
      title: 'Edge refund-order honra amount=1 no body (parcial não autorizado)',
      actor: 'seller JWT',
      pre: 'pago capturado ${paidCents}¢, sem enviado',
      repro: 'POST refund-order {order_id, amount:1, amount_cents:1}',
      expected: 'ignorar amount do cliente; refund = amount_paid_cents',
      obtained: {
        'hit': tiny.brief,
        'stripe_refund_cents': stripeRefundCents,
        'paid_cents': paidCents,
      },
    );
  } else if (tiny.ok &&
      stripeRefundCents != null &&
      stripeRefundCents > paidCents) {
    c.hold(
      id: 'BW4.edge_amount_over_capture',
      lens: 'BW4',
      severity: 'P0',
      title: 'refund-order reembolsou mais que a captura via amount no body',
      actor: 'seller JWT',
      pre: 'pago ${paidCents}¢',
      repro: 'POST refund-order amount no body',
      expected: '≤ captura',
      obtained: {
        'stripe_refund_cents': stripeRefundCents,
        'paid_cents': paidCents,
        'hit': tiny.brief,
      },
    );
  } else if (tiny.ok) {
    // ignored client amount — design. Prove oversize also ignored on a NEW order.
    c.block('BW4.edge_amount_body_partial', 'BW4',
        'amount=1 ignorado (refund autoridade servidor)', {
      'stripe_refund_cents': stripeRefundCents,
      'paid_cents': paidCents,
      'edge_amount_cents': tiny.map?['amount_cents'],
      'status': o?['status'],
    });
  } else {
    c.block('BW4.edge_amount_1', 'BW4', 'refund amount=1 recusado', tiny);
  }

  // Oversize amount on a fresh PI
  final over = await mustPay('BW4', qty: 2);
  final oOver = await c.orderRow(over.oid);
  final paidOver = numOf(oOver?['amount_paid_cents']) ?? 0;
  final huge = await c.refund(over.oid, extra: {
    'amount': 999999,
    'amount_cents': 99999900,
    'amount_total': 999999,
  });
  final refundsHuge = over.pi == null ? null : await c.stripeRefunds(over.pi!);
  int? hugeCents;
  if (refundsHuge?.json is Map) {
    final data = (refundsHuge!.json as Map)['data'];
    if (data is List && data.isNotEmpty && data.first is Map) {
      hugeCents = numOf((data.first as Map)['amount'])?.round();
    }
  }
  c.note('BW4.amount_huge', 'refund-order amount=999999 no body', {
    'hit': huge.brief,
    'paid_cents': paidOver,
    'stripe_refund_cents': hugeCents,
    'edge_amount_cents': huge.map?['amount_cents'],
    'status': (await c.orderRow(over.oid))?['status'],
  }, lens: 'BW4');

  if (huge.ok && hugeCents != null && hugeCents > paidOver) {
    c.hold(
      id: 'BW4.edge_amount_huge',
      lens: 'BW4',
      severity: 'P0',
      title: 'refund-order amount enorme no body excede captura',
      actor: 'seller JWT',
      pre: 'pago ${paidOver}¢',
      repro: 'POST refund-order amount=999999',
      expected: '≤ captura / ignorar body',
      obtained: {'stripe': hugeCents, 'paid': paidOver, 'hit': huge.brief},
    );
  } else {
    c.block('BW4.edge_amount_huge', 'BW4', 'amount enorme ignorado/limitado', {
      'hit': huge.brief,
      'stripe': hugeCents,
      'paid': paidOver,
    });
  }

  // String / array amount
  final weird = await mustPay('BW4', qty: 1);
  final weirdHit = await c.refund(weird.oid, extra: {
    'amount': '100',
    'amount_cents': [100],
  });
  c.note('BW4.amount_weird_types', 'amount string/array no body', weirdHit.brief,
      lens: 'BW4');
  if (weirdHit.ok) {
    final wr = weird.pi == null ? null : await c.stripeRefunds(weird.pi!);
    int? wc;
    if (wr?.json is Map) {
      final data = (wr!.json as Map)['data'];
      if (data is List && data.isNotEmpty && data.first is Map) {
        wc = numOf((data.first as Map)['amount'])?.round();
      }
    }
    final paidW = numOf((await c.orderRow(weird.oid))?['amount_paid_cents']) ?? 0;
    if (wc != null && wc != paidW && wc == 100) {
      c.hold(
        id: 'BW4.edge_amount_string',
        lens: 'BW4',
        severity: 'P1',
        title: 'refund-order interpreta amount string/array do body',
        actor: 'seller JWT',
        pre: 'pago ${paidW}¢',
        repro: 'POST refund-order amount="100" amount_cents=[100]',
        expected: 'ignorar; refund = amount_paid_cents',
        obtained: {'stripe': wc, 'paid': paidW, 'hit': weirdHit.brief},
      );
    } else {
      c.block('BW4.edge_amount_string', 'BW4', 'tipos amount ignorados', {
        'stripe': wc,
        'paid': paidW,
        'hit': weirdHit.brief,
      });
    }
  } else {
    c.block('BW4.amount_weird', 'BW4', 'amount string recusado', weirdHit);
  }

  final wAfterAmt = await c.wallets();
  c.note('BW4.wallets', 'Δwallet após refunds unshipped', {
    'before': wBeforeAmt,
    'after': wAfterAmt,
  }, lens: 'BW4');

  // =========================================================================
  // BW4/BW5/BW8 — cadeia concluido → disputa → return → stock + parcial
  // =========================================================================
  final chain = await mustPay('BW5', qty: 1);
  if (!await c.toEnviado(chain.oid)) {
    throw StateError('enviado chain');
  }
  if (!await c.toConcluido(chain.oid)) {
    throw StateError('concluido chain');
  }
  final dHit = await c.insertDispute(orderId: chain.oid);
  final did = dHit.firstId;
  if (!dHit.ok || did == null) {
    c.skip('BW5.dispute', 'BW5', 'disputa chain falhou', dHit);
    await c.dumpAll('pass3.json');
    return;
  }

  // Partial refund: seller offer 50, buyer RPC, percent 200 no arg
  final offer = await c.patchDispute(did, {
    'seller_offer_type': 'partial_refund',
    'seller_refund_percent': 50,
  }, jwt: c.sellerJwt);
  c.note('BW4.offer50', 'seller oferta 50%', {
    'hit': offer.brief,
    'row': await c.disputeRow(did),
  }, lens: 'BW4');

  final partBuyer = await c.rpc(
    'batata_process_partial_refund_dispute',
    {'p_order_id': chain.oid, 'p_refund_percent': 50},
    jwt: c.buyerJwt,
  );
  final wPart = await c.wallets();
  o = await c.orderRow(chain.oid);
  c.note('BW4.partial_buyer', 'buyer RPC parcial 50 com PI vivo pós-envio', {
    'hit': partBuyer.brief,
    'wallets': wPart,
    'refund_id': o?['stripe_refund_id'],
    'wallet_refund': o?['wallet_refund_processed_at'],
  }, lens: 'BW4');

  final partOk = partBuyer.ok &&
      partBuyer.body != 'false' &&
      !partBuyer.brief.toLowerCase().contains('not_allowed') &&
      !partBuyer.brief.toLowerCase().contains('requires_stripe') &&
      !partBuyer.brief.toLowerCase().contains('dispute_refund');
  if (partOk) {
    c.hold(
      id: 'BW4.partial_wallet_with_live_pi',
      lens: 'BW4',
      severity: 'P1',
      title: 'Refund parcial wallet com captura Stripe viva (pós-envio)',
      actor: 'buyer JWT',
      pre: 'concluido+disputa+oferta 50%, PI ${chain.pi}',
      repro: 'rpc batata_process_partial_refund_dispute percent=50',
      expected: 'dispute_partial_refund_requires_stripe / false',
      obtained: {
        'hit': partBuyer.brief,
        'stripe_refund_id': o?['stripe_refund_id'],
        'wallet_refund_at': o?['wallet_refund_processed_at'],
      },
    );
  } else {
    c.block('BW4.partial_wallet_with_live_pi', 'BW4',
        'parcial wallet bloqueado pós-envio', partBuyer);
  }

  final part200 = await c.rpc(
    'batata_process_partial_refund_dispute',
    {'p_order_id': chain.oid, 'p_refund_percent': 200},
    jwt: c.buyerJwt,
  );
  if (part200.ok &&
      part200.body != 'false' &&
      !part200.brief.toLowerCase().contains('not_allowed') &&
      !part200.brief.toLowerCase().contains('requires_stripe')) {
    c.hold(
      id: 'BW4.partial_percent_200',
      lens: 'BW4',
      severity: 'P1',
      title: 'RPC parcial aceita p_refund_percent=200',
      actor: 'buyer JWT',
      pre: 'oferta seller 50%',
      repro: 'rpc p_refund_percent=200',
      expected: 'usa % da oferta (≤100) ou recusa',
      obtained: part200.brief,
    );
  } else {
    c.block('BW4.partial_percent_200', 'BW4', 'percent 200 recusado/ignorado',
        part200);
  }

  final partSeller = await c.rpc(
    'batata_process_partial_refund_dispute',
    {'p_order_id': chain.oid, 'p_refund_percent': 50},
    jwt: c.sellerJwt,
  );
  await expectBlock(
    'BW4.partial_seller_rpc',
    'BW4',
    'Seller executa RPC refund parcial',
    partSeller,
  );

  // Walk return
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
  c.note('BW5.devolvida_chain', 'devolvida pré-refund', {
    'hit': dev.brief,
    'status': o?['status'],
    'qty_before': qtyBefore,
    'qty_mid': qtyMid,
    'units': o?['stock_units_applied'],
    'refund': o?['stripe_refund_id'],
  }, lens: 'BW5');

  // Race refund ∥ second devolvida (idempotent) + refund twice
  final r1 = c.refund(chain.oid);
  final r2 = c.refund(chain.oid);
  final raced = await parallel([r1, r2]);
  o = await c.orderRow(chain.oid);
  final qtyAfter = numOf((await c.productRow(chain.pid))?['quantity']) ?? 0;
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
  c.note('BW5.refund_race', '2× refund-order após devolvida', {
    'hits': raced.map((h) => h.brief).toList(),
    'qty_before': qtyBefore,
    'qty_mid': qtyMid,
    'qty_after': qtyAfter,
    'units': o?['stock_units_applied'],
    'stripe_n': stripeRefundN,
    'stripe_sum': stripeRefundSum,
    'paid': o?['amount_paid_cents'],
    'wallets_before': wBeforeDev,
    'wallets_after': wAfter,
  }, lens: 'BW5');

  final stockDup = (qtyAfter - qtyBefore) >
      ((numOf(o?['stock_units_applied']) ?? 0) > 0
          ? 0
          : (numOf((await c.orderRow(chain.oid))?['quantity']) ?? 1));
  // restored twice if qty jumped by > original units (typically 1)
  final unitsExpected = 1;
  if ((qtyAfter - qtyBefore) > unitsExpected) {
    c.hold(
      id: 'BW5.stock_restore_dup',
      lens: 'BW5',
      severity: 'P1',
      title: 'Stock restaurou em duplicado (devolvida + refund)',
      actor: 'seller JWT',
      pre: 'qty=$qtyBefore units aplicadas, depois devolvida+2× refund-order',
      repro: 'PATCH devolvida; Future.wait 2× refund-order',
      expected: '+1 unidade no máximo',
      obtained: {
        'qty_before': qtyBefore,
        'qty_mid': qtyMid,
        'qty_after': qtyAfter,
        'delta': qtyAfter - qtyBefore,
        'stripe_n': stripeRefundN,
        'stripe_sum': stripeRefundSum,
      },
    );
  } else {
    c.block('BW5.stock_restore_dup', 'BW5', 'stock restore não duplicou', {
      'qty_before': qtyBefore,
      'qty_mid': qtyMid,
      'qty_after': qtyAfter,
      'stripe_n': stripeRefundN,
    });
  }

  if (stripeRefundN > 1 &&
      stripeRefundSum > (numOf(o?['amount_paid_cents']) ?? 0)) {
    c.hold(
      id: 'BW4.double_stripe_refund',
      lens: 'BW4',
      severity: 'P0',
      title: '2 refunds Stripe somam mais que a captura',
      actor: 'seller JWT',
      pre: 'devolvida + race refund-order',
      repro: 'Future.wait 2× POST refund-order',
      expected: '1 refund ≤ captura',
      obtained: {
        'n': stripeRefundN,
        'sum': stripeRefundSum,
        'paid': o?['amount_paid_cents'],
        'hits': raced.map((h) => h.brief).toList(),
      },
    );
  } else {
    c.block('BW4.double_stripe_refund', 'BW4', 'refund Stripe não duplicou', {
      'n': stripeRefundN,
      'sum': stripeRefundSum,
    });
  }

  // =========================================================================
  // BW6 — release ∩ disputa / refund
  // =========================================================================
  final rel = await mustPay('BW6', qty: 1);
  if (!await c.toEnviado(rel.oid)) throw StateError('enviado rel');
  if (!await c.toConcluido(rel.oid)) throw StateError('concluido rel');

  final wRel0 = await c.wallets();
  final relOpen = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': rel.oid},
    jwt: c.buyerJwt,
  );
  final wRel1 = await c.wallets();
  c.note('BW6.release_no_dispute', 'release em concluido sem disputa', {
    'hit': relOpen.brief,
    'delta_seller': (wRel1['seller'] ?? 0) - (wRel0['seller'] ?? 0),
  }, lens: 'BW6');

  final dRel = await c.insertDispute(orderId: rel.oid);
  c.note('BW6.dispute_after_release', 'abrir disputa após release', dRel.brief,
      lens: 'BW6');
  if (dRel.ok) {
    c.hold(
      id: 'BW6.dispute_after_release',
      lens: 'BW6',
      severity: 'P1',
      title: 'Buyer abre disputa depois do release da carteira do vendedor',
      actor: 'buyer JWT',
      pre: 'concluido + release true, wallet_release_processed_at set',
      repro: 'POST order_disputes após batata_release_seller_wallet_for_order',
      expected: 'RLS recusa (wallet_release_processed_at is null exigido)',
      obtained: {
        'release': relOpen.brief,
        'dispute': dRel.brief,
        'order': await c.orderRow(rel.oid),
      },
    );
  } else {
    c.block('BW6.dispute_after_release', 'BW6', 'disputa após release recusada',
        dRel);
  }

  // Release com disputa aberta (encomenda nova)
  final rel2 = await mustPay('BW6', qty: 1);
  if (!await c.toEnviado(rel2.oid)) throw StateError('enviado rel2');
  if (!await c.toConcluido(rel2.oid)) throw StateError('concluido rel2');
  final d2 = await c.insertDispute(orderId: rel2.oid);
  final wRel2a = await c.wallets();
  final relBlocked = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': rel2.oid},
    jwt: c.buyerJwt,
  );
  final wRel2b = await c.wallets();
  final deltaSeller =
      (wRel2b['seller'] ?? 0) - (wRel2a['seller'] ?? 0);
  c.note('BW6.release_open_dispute', 'release com disputa aberta', {
    'dispute': d2.brief,
    'release': relBlocked.brief,
    'delta_seller': deltaSeller,
  }, lens: 'BW6');
  if (relBlocked.ok &&
      relBlocked.body != 'false' &&
      deltaSeller > 0) {
    c.hold(
      id: 'BW6.release_with_open_dispute',
      lens: 'BW6',
      severity: 'P0',
      title: 'Release credita vendedor com disputa aberta',
      actor: 'buyer JWT',
      pre: 'concluido + disputa aberta',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false / Δseller=0',
      obtained: {
        'hit': relBlocked.brief,
        'delta_seller': deltaSeller,
      },
    );
  } else {
    c.block('BW6.release_with_open_dispute', 'BW6',
        'release bloqueado com disputa aberta', {
      'hit': relBlocked.brief,
      'delta_seller': deltaSeller,
    });
  }

  // Seller S2 release on B1 order
  await expectBlock(
    'BW7.seller2_release',
    'BW7',
    'S2 tenta release da encomenda S1',
    await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': rel2.oid},
      jwt: c.seller2Jwt ?? c.sellerJwt,
    ),
  );

  // Refund shipped (should 403) then after — already tested on unshipped.
  final shipRef = await c.refund(rel2.oid);
  c.note('BW4.refund_shipped_open_dispute', 'refund-order enviado/concluido+disputa',
      shipRef.brief,
      lens: 'BW4');
  if (shipRef.ok && shipRef.map?['ok'] == true && shipRef.map?['skipped'] != true) {
    c.hold(
      id: 'BW4.refund_while_shipped_dispute',
      lens: 'BW4',
      severity: 'P1',
      title: 'refund-order anula Stripe com disputa/enviado',
      actor: 'seller JWT',
      pre: 'concluido+disputa aberta',
      repro: 'POST refund-order',
      expected: '403 order_refund_blocked_*',
      obtained: shipRef.brief,
    );
  } else {
    c.block('BW4.refund_while_shipped_dispute', 'BW4',
        'refund bloqueado em enviado/disputa', shipRef);
  }

  await c.dumpAll('pass3.json');
}
