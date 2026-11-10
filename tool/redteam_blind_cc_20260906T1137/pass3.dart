/// RED TEAM CEGO CC — pass 3. Staging only. Não corrige.
/// Lentes CC4 refund · CC5 stock dup · CC6 release · CC8 caixa.
/// Novas: Edge amount no body · refund parcial · stock restore dup.
import '_rtcc.dart';

Future<void> main() async {
  final c = Rtcc.fromEnv(loadEnv());
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

  int? stripeFirstCents(HttpHit? h) {
    if (h?.json is Map) {
      final data = (h!.json as Map)['data'];
      if (data is List && data.isNotEmpty && data.first is Map) {
        return numOf((data.first as Map)['amount'])?.round();
      }
    }
    return null;
  }

  // CC4 — Edge amount no body (pago, sem enviado)
  final amt = await mustPay('CC4', qty: 2);
  var o = await c.orderRow(amt.oid);
  final paidCents = numOf(o?['amount_paid_cents']) ?? 0;
  final wBeforeAmt = await c.wallets();

  await expectBlock(
    'CC4.buyer_refund_order',
    'CC4',
    'Buyer chama refund-order',
    await c.refund(amt.oid, jwt: c.buyerJwt),
  );

  final tiny = await c.refund(amt.oid, extra: {'amount': 1, 'amount_cents': 1});
  o = await c.orderRow(amt.oid);
  final refundsTiny = amt.pi == null ? null : await c.stripeRefunds(amt.pi!);
  final stripeRefundCents = stripeFirstCents(refundsTiny);
  c.note('CC4.amount_1', 'refund-order amount=1 no body', {
    'hit': tiny.brief,
    'order_refund': o?['stripe_refund_id'],
    'order_status': o?['status'],
    'paid_cents': paidCents,
    'stripe_refund_cents': stripeRefundCents,
    'edge_amount_cents': tiny.map?['amount_cents'],
  }, lens: 'CC4');

  if (tiny.ok &&
      stripeRefundCents != null &&
      stripeRefundCents < paidCents &&
      stripeRefundCents <= 1) {
    c.hold(
      id: 'CC4.edge_amount_body_partial',
      lens: 'CC4',
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
      id: 'CC4.edge_amount_over_capture',
      lens: 'CC4',
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
    c.block('CC4.edge_amount_body_partial', 'CC4',
        'amount=1 ignorado (refund autoridade servidor)', {
      'stripe_refund_cents': stripeRefundCents,
      'paid_cents': paidCents,
      'edge_amount_cents': tiny.map?['amount_cents'],
      'status': o?['status'],
    });
  } else {
    c.block('CC4.edge_amount_1', 'CC4', 'refund amount=1 recusado', tiny);
  }

  final over = await mustPay('CC4', qty: 2);
  final oOver = await c.orderRow(over.oid);
  final paidOver = numOf(oOver?['amount_paid_cents']) ?? 0;
  final huge = await c.refund(over.oid, extra: {
    'amount': 999999,
    'amount_cents': 99999900,
    'amount_total': 999999,
  });
  final hugeCents = stripeFirstCents(
      over.pi == null ? null : await c.stripeRefunds(over.pi!));
  c.note('CC4.amount_huge', 'refund-order amount=999999 no body', {
    'hit': huge.brief,
    'paid_cents': paidOver,
    'stripe_refund_cents': hugeCents,
    'edge_amount_cents': huge.map?['amount_cents'],
    'status': (await c.orderRow(over.oid))?['status'],
  }, lens: 'CC4');

  if (huge.ok && hugeCents != null && hugeCents > paidOver) {
    c.hold(
      id: 'CC4.edge_amount_huge',
      lens: 'CC4',
      severity: 'P0',
      title: 'refund-order amount enorme no body excede captura',
      actor: 'seller JWT',
      pre: 'pago ${paidOver}¢',
      repro: 'POST refund-order amount=999999',
      expected: '≤ captura / ignorar body',
      obtained: {'stripe': hugeCents, 'paid': paidOver, 'hit': huge.brief},
    );
  } else {
    c.block('CC4.edge_amount_huge', 'CC4', 'amount enorme ignorado/limitado', {
      'hit': huge.brief,
      'stripe': hugeCents,
      'paid': paidOver,
    });
  }

  final weird = await mustPay('CC4', qty: 1);
  final weirdHit = await c.refund(weird.oid, extra: {
    'amount': '100',
    'amount_cents': [100],
  });
  c.note('CC4.amount_weird_types', 'amount string/array no body', weirdHit.brief,
      lens: 'CC4');
  if (weirdHit.ok) {
    final wc = stripeFirstCents(
        weird.pi == null ? null : await c.stripeRefunds(weird.pi!));
    final paidW = numOf((await c.orderRow(weird.oid))?['amount_paid_cents']) ?? 0;
    if (wc != null && wc != paidW && wc == 100) {
      c.hold(
        id: 'CC4.edge_amount_string',
        lens: 'CC4',
        severity: 'P1',
        title: 'refund-order interpreta amount string/array do body',
        actor: 'seller JWT',
        pre: 'pago ${paidW}¢',
        repro: 'POST refund-order amount="100" amount_cents=[100]',
        expected: 'ignorar; refund = amount_paid_cents',
        obtained: {'stripe': wc, 'paid': paidW, 'hit': weirdHit.brief},
      );
    } else {
      c.block('CC4.edge_amount_string', 'CC4', 'tipos amount ignorados', {
        'stripe': wc,
        'paid': paidW,
        'hit': weirdHit.brief,
      });
    }
  } else {
    c.block('CC4.amount_weird', 'CC4', 'amount string recusado', weirdHit);
  }

  final wAfterAmt = await c.wallets();
  c.note('CC4.wallets', 'Δwallet após refunds unshipped', {
    'before': wBeforeAmt,
    'after': wAfterAmt,
  }, lens: 'CC4');

  // CC4/CC5/CC8 — cadeia concluido → disputa → return → stock + parcial
  final chain = await mustPay('CC5', qty: 1);
  if (!await c.toEnviado(chain.oid)) {
    throw StateError('enviado chain');
  }
  if (!await c.toConcluido(chain.oid)) {
    throw StateError('concluido chain');
  }
  final dHit = await c.insertDispute(orderId: chain.oid);
  final did = dHit.firstId;
  if (!dHit.ok || did == null) {
    c.skip('CC5.dispute', 'CC5', 'disputa chain falhou', dHit);
    await c.dumpAll('pass3.json');
    return;
  }

  final offer = await c.patchDispute(did, {
    'seller_offer_type': 'partial_refund',
    'seller_refund_percent': 50,
  }, jwt: c.sellerJwt);
  c.note('CC4.offer50', 'seller oferta 50%', {
    'hit': offer.brief,
    'row': await c.disputeRow(did),
  }, lens: 'CC4');

  final partBuyer = await c.rpc(
    'batata_process_partial_refund_dispute',
    {'p_order_id': chain.oid, 'p_refund_percent': 50},
    jwt: c.buyerJwt,
  );
  final wPart = await c.wallets();
  o = await c.orderRow(chain.oid);
  c.note('CC4.partial_buyer', 'buyer RPC parcial 50 com PI vivo pós-envio', {
    'hit': partBuyer.brief,
    'wallets': wPart,
    'refund_id': o?['stripe_refund_id'],
    'wallet_refund': o?['wallet_refund_processed_at'],
  }, lens: 'CC4');

  final partOk = partBuyer.ok &&
      partBuyer.body != 'false' &&
      !partBuyer.brief.toLowerCase().contains('not_allowed') &&
      !partBuyer.brief.toLowerCase().contains('requires_stripe') &&
      !partBuyer.brief.toLowerCase().contains('dispute_refund');
  if (partOk) {
    c.hold(
      id: 'CC4.partial_wallet_with_live_pi',
      lens: 'CC4',
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
    c.block('CC4.partial_wallet_with_live_pi', 'CC4',
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
      id: 'CC4.partial_percent_200',
      lens: 'CC4',
      severity: 'P1',
      title: 'RPC parcial aceita p_refund_percent=200',
      actor: 'buyer JWT',
      pre: 'oferta seller 50%',
      repro: 'rpc p_refund_percent=200',
      expected: 'usa % da oferta (≤100) ou recusa',
      obtained: part200.brief,
    );
  } else {
    c.block('CC4.partial_percent_200', 'CC4', 'percent 200 recusado/ignorado',
        part200);
  }

  final partSeller = await c.rpc(
    'batata_process_partial_refund_dispute',
    {'p_order_id': chain.oid, 'p_refund_percent': 50},
    jwt: c.sellerJwt,
  );
  await expectBlock(
    'CC4.partial_seller_rpc',
    'CC4',
    'Seller executa RPC refund parcial',
    partSeller,
  );

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
  c.note('CC5.devolvida_chain', 'devolvida pré-refund', {
    'hit': dev.brief,
    'status': o?['status'],
    'qty_before': qtyBefore,
    'qty_mid': qtyMid,
    'units': o?['stock_units_applied'],
    'refund': o?['stripe_refund_id'],
  }, lens: 'CC5');

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
  c.note('CC5.refund_race', '2× refund-order após devolvida', {
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
  }, lens: 'CC5');

  final paidChain = numOf(o?['amount_paid_cents']) ?? 0;
  final stockDup = (qtyAfter - qtyBefore) >= 2;
  if (stockDup) {
    c.hold(
      id: 'CC5.stock_restore_dup',
      lens: 'CC5',
      severity: 'P1',
      title: 'Restore de stock duplicado no refund após devolvida',
      actor: 'seller JWT',
      pre: 'qty=$qtyBefore antes do refund',
      repro: 'Future.wait 2× refund-order',
      expected: '+1 unidade',
      obtained: {
        'qty_before': qtyBefore,
        'qty_mid': qtyMid,
        'qty_after': qtyAfter,
        'stripe_n': stripeRefundN,
      },
    );
  } else {
    c.block('CC5.stock_restore_dup', 'CC5', 'stock restore uma vez', {
      'qty_before': qtyBefore,
      'qty_after': qtyAfter,
      'delta': qtyAfter - qtyBefore,
    });
  }

  if (stripeRefundN > 1 && stripeRefundSum > paidChain) {
    c.hold(
      id: 'CC4.refund_race_double_stripe',
      lens: 'CC4',
      severity: 'P0',
      title: 'Race 2× refund-order criou dois refunds Stripe',
      actor: 'seller JWT',
      pre: 'devolvida + PI ${chain.pi}',
      repro: 'Future.wait 2× POST refund-order',
      expected: '1 refund ≤ captura',
      obtained: {
        'n': stripeRefundN,
        'sum': stripeRefundSum,
        'paid': paidChain,
        'hits': raced.map((h) => h.brief).toList(),
      },
    );
  } else {
    c.block('CC4.refund_race_double_stripe', 'CC4', 'refund race idempotente', {
      'n': stripeRefundN,
      'sum': stripeRefundSum,
      'paid': paidChain,
    });
  }

  // CC6 — release ∩ disputa
  final rel = await mustPay('CC6', qty: 1);
  if (!await c.toEnviado(rel.oid)) throw StateError('env rel');
  if (!await c.toConcluido(rel.oid)) throw StateError('conc rel');
  final wRel0 = await c.wallets();
  final relOpen = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': rel.oid},
    jwt: c.buyerJwt,
  );
  final wRel1 = await c.wallets();
  c.note('CC6.release_no_dispute', 'release em concluido sem disputa', {
    'hit': relOpen.brief,
    'dSeller': (wRel1['seller'] ?? 0) - (wRel0['seller'] ?? 0),
    'release_at': (await c.orderRow(rel.oid))?['wallet_release_processed_at'],
  }, lens: 'CC6');

  final dRel = await c.insertDispute(orderId: rel.oid);
  c.note('CC6.dispute_after_release', 'abrir disputa após release', dRel.brief,
      lens: 'CC6');
  if (dRel.ok) {
    c.hold(
      id: 'CC6.dispute_after_release',
      lens: 'CC6',
      severity: 'P1',
      title: 'Buyer abre disputa depois do release da carteira do vendedor',
      actor: 'buyer JWT',
      pre: 'concluido + release true, wallet_release_processed_at set',
      repro: 'POST order_disputes após batata_release_seller_wallet_for_order',
      expected: 'RLS recusa (wallet_release_processed_at is null exigido)',
      obtained: {
        'release': relOpen.brief,
        'dispute': dRel.brief,
        'did': dRel.firstId,
      },
    );
  } else {
    c.block('CC6.dispute_after_release', 'CC6', 'disputa após release recusada',
        dRel);
  }

  final rel2 = await mustPay('CC6', qty: 1);
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
  c.note('CC6.release_open_dispute', 'release com disputa aberta', {
    'dispute': dOpen.brief,
    'release': relBlocked.brief,
    'dSeller': dSellerOpen,
  }, lens: 'CC6');
  final releasedAnyway = relBlocked.ok &&
      relBlocked.body != 'false' &&
      relBlocked.map?['ok'] != false &&
      dSellerOpen > 0;
  if (releasedAnyway) {
    c.hold(
      id: 'CC6.release_with_open_dispute',
      lens: 'CC6',
      severity: 'P0',
      title: 'Release da carteira com disputa aberta',
      actor: 'buyer JWT',
      pre: 'concluido + disputa ${dOpen.firstId}',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false / sem Δseller',
      obtained: {
        'hit': relBlocked.brief,
        'dSeller': dSellerOpen,
      },
    );
  } else {
    c.block('CC6.release_with_open_dispute', 'CC6',
        'release bloqueado com disputa aberta', {
      'hit': relBlocked.brief,
      'dSeller': dSellerOpen,
    });
  }

  await expectBlock(
    'CC7.seller2_release',
    'CC7',
    'S2 tenta release da encomenda S1',
    await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': rel2.oid},
      jwt: c.seller2Jwt,
    ),
  );

  final happyDelta = (wRel1['seller'] ?? 0) - (wRel0['seller'] ?? 0);
  if (relOpen.ok &&
      relOpen.body != 'false' &&
      happyDelta > 0 &&
      dSellerOpen == 0) {
    c.block('CC8.release_vs_dispute', 'CC8',
        'release feliz credita; disputa segura o PI', {
      'happy_dSeller': happyDelta,
      'open_dSeller': dSellerOpen,
    });
  }

  c.note('CC8.wallets_final', 'wallets fim pass3', await c.wallets(),
      lens: 'CC8');
  await c.dumpAll('pass3.json');
}
