/// RED TEAM CEGO CI — pass 3. Staging only. Não corrige.
/// Poço CI-C refund/stock/release · CI-D cadeia · lentes CI4 CI5 CI6 CI8.
/// Exactos BXCC amount body / ／ path: observar, NÃO contar se iguais.
import '_rtci.dart';

Future<void> main() async {
  final c = Rtci.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.well('CI-C');
  c.well('CI-D');

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

  // CI4 — Edge amount no body (pago, sem enviado)
  final amt = await mustPay('CI4', qty: 2);
  var o = await c.orderRow(amt.oid);
  final paidCents = numOf(o?['amount_paid_cents']) ?? 0;
  final wBeforeAmt = await c.wallets();

  await expectBlock(
    'CI4.buyer_refund_order',
    'CI4',
    'Buyer chama refund-order (Seguro Fleaber seller-only)',
    await c.refund(amt.oid, jwt: c.buyerJwt),
  );

  final finJwt = await c.rpc('batata_finalize_stripe_order_refund', {
    'p_order_id': amt.oid,
    'p_refund_id': 're_rtci_fake',
    'p_payment_intent_id': amt.pi,
    'p_session_id': null,
    'p_amount_cents': 999999,
  }, jwt: c.buyerJwt);
  await expectBlock(
    'CI4.buyer_finalize_rpc',
    'CI4',
    'Buyer JWT batata_finalize_stripe_order_refund amount enorme',
    finJwt,
    severity: 'P0',
  );

  final tiny = await c.refund(amt.oid, extra: {'amount': 1, 'amount_cents': 1});
  o = await c.orderRow(amt.oid);
  final refundsTiny = amt.pi == null ? null : await c.stripeRefunds(amt.pi!);
  final stripeRefundCents = stripeFirstCents(refundsTiny);
  c.note('CI4.amount_1', 'refund-order amount=1 no body', {
    'hit': tiny.brief,
    'order_refund': o?['stripe_refund_id'],
    'order_status': o?['status'],
    'paid_cents': paidCents,
    'stripe_refund_cents': stripeRefundCents,
    'edge_amount_cents': tiny.map?['amount_cents'],
  }, lens: 'CI4');

  if (tiny.ok &&
      stripeRefundCents != null &&
      stripeRefundCents < paidCents &&
      stripeRefundCents <= 1) {
    c.hold(
      id: 'CI4.edge_amount_body_partial',
      lens: 'CI4',
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
      id: 'CI4.edge_amount_over_capture',
      lens: 'CI4',
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
    c.block('CI4.edge_amount_body_partial', 'CI4',
        'amount=1 ignorado (refund autoridade servidor)', {
      'stripe_refund_cents': stripeRefundCents,
      'paid_cents': paidCents,
      'edge_amount_cents': tiny.map?['amount_cents'],
      'status': o?['status'],
    });
  } else {
    c.block('CI4.edge_amount_1', 'CI4', 'refund amount=1 recusado', tiny);
  }

  final over = await mustPay('CI4', qty: 2);
  final oOver = await c.orderRow(over.oid);
  final paidOver = numOf(oOver?['amount_paid_cents']) ?? 0;
  final huge = await c.refund(over.oid, extra: {
    'amount': 999999,
    'amount_cents': 99999900,
    'refund_amount': 999999,
  });
  final hugeCents = stripeFirstCents(
      over.pi == null ? null : await c.stripeRefunds(over.pi!));
  c.note('CI4.amount_huge', 'refund-order amount=999999 no body', {
    'hit': huge.brief,
    'paid_cents': paidOver,
    'stripe_refund_cents': hugeCents,
    'edge_amount_cents': huge.map?['amount_cents'],
    'status': (await c.orderRow(over.oid))?['status'],
  }, lens: 'CI4');

  if (huge.ok && hugeCents != null && hugeCents > paidOver) {
    c.hold(
      id: 'CI4.edge_amount_huge',
      lens: 'CI4',
      severity: 'P0',
      title: 'refund-order amount enorme no body excede captura',
      actor: 'seller JWT',
      pre: 'pago ${paidOver}¢',
      repro: 'POST refund-order amount=999999',
      expected: '≤ captura / ignorar body',
      obtained: {'stripe': hugeCents, 'paid': paidOver, 'hit': huge.brief},
    );
  } else {
    c.block('CI4.edge_amount_huge', 'CI4', 'amount enorme ignorado/limitado', {
      'hit': huge.brief,
      'stripe': hugeCents,
      'paid': paidOver,
    });
  }

  final wAfterAmt = await c.wallets();
  c.note('CI4.wallets', 'Δwallet após refunds unshipped', {
    'before': wBeforeAmt,
    'after': wAfterAmt,
    'dBuyer': (wAfterAmt['buyer'] ?? 0) - (wBeforeAmt['buyer'] ?? 0),
    'dSeller': (wAfterAmt['seller'] ?? 0) - (wBeforeAmt['seller'] ?? 0),
  }, lens: 'CI8');

  // CI5 — cancel × disputa: refund unshipped restaura; 2.º restore via cancelado?
  final cancel = await mustPay('CI5', qty: 1);
  final qtyC0 = numOf((await c.productRow(cancel.pid))?['quantity']) ?? 0;
  final rfCancel = await c.refund(cancel.oid);
  o = await c.orderRow(cancel.oid);
  final qtyC1 = numOf((await c.productRow(cancel.pid))?['quantity']) ?? 0;
  c.note('CI5.cancel_refund', 'refund unshipped (1.º restore)', {
    'hit': rfCancel.brief,
    'qty0': qtyC0,
    'qty1': qtyC1,
    'status': o?['status'],
    'units': o?['stock_units_applied'],
  }, lens: 'CI5');
  final cancelPatch = await c.patchOrder(
    cancel.oid,
    {'status': 'cancelado'},
    jwt: c.sellerJwt,
  );
  o = await c.orderRow(cancel.oid);
  final qtyC2 = numOf((await c.productRow(cancel.pid))?['quantity']) ?? 0;
  c.note('CI5.cancel_after_refund', 'PATCH cancelado após refund', {
    'hit': cancelPatch.brief,
    'qty1': qtyC1,
    'qty2': qtyC2,
    'status': o?['status'],
  }, lens: 'CI5');
  if ((qtyC2 - qtyC0) >= 2) {
    c.hold(
      id: 'CI5.stock_restore_cancel_x_refund',
      lens: 'CI5',
      severity: 'P1',
      title: 'Stock restaurou 2× (refund + PATCH cancelado)',
      actor: 'seller JWT',
      pre: 'qty=$qtyC0 após venda',
      repro: 'refund-order; PATCH status=cancelado',
      expected: '+1 unidade no total',
      obtained: {'qty0': qtyC0, 'qty1': qtyC1, 'qty2': qtyC2},
    );
  } else {
    c.block('CI5.stock_restore_cancel_x_refund', 'CI5',
        'restore refund+cancel ≤1', {
      'qty0': qtyC0,
      'qty1': qtyC1,
      'qty2': qtyC2,
    });
  }

  // CI4/CI5/CI8 — cadeia concluido → disputa → return → stock + parcial
  final chain = await mustPay('CI5', qty: 1);
  if (!await c.toEnviado(chain.oid)) {
    throw StateError('enviado chain');
  }
  if (!await c.toConcluido(chain.oid)) {
    throw StateError('concluido chain');
  }
  final dHit = await c.insertDispute(orderId: chain.oid);
  final did = dHit.firstId;
  if (!dHit.ok || did == null) {
    c.skip('CI5.dispute', 'CI5', 'disputa chain falhou', dHit);
    await c.dumpAll('pass3.json');
    return;
  }

  // Conluio buyer+seller: seller oferta 1% + buyer RPC 100
  final offer = await c.patchDispute(did, {
    'seller_offer_type': 'partial_refund',
    'seller_refund_percent': 1,
  }, jwt: c.sellerJwt);
  c.note('CI4.offer1', 'seller oferta 1% (conluio mint parcial)', {
    'hit': offer.brief,
    'row': await c.disputeRow(did),
  }, lens: 'CI4');

  final partBuyer = await c.rpc(
    'batata_process_partial_refund_dispute',
    {'p_order_id': chain.oid, 'p_refund_percent': 100},
    jwt: c.buyerJwt,
  );
  final wPart = await c.wallets();
  o = await c.orderRow(chain.oid);
  c.note('CI4.partial_buyer_100_vs_offer1',
      'buyer RPC parcial 100% contra oferta 1% PI vivo', {
    'hit': partBuyer.brief,
    'wallets': wPart,
    'refund_id': o?['stripe_refund_id'],
    'wallet_refund': o?['wallet_refund_processed_at'],
  }, lens: 'CI4');

  final partOk = partBuyer.ok &&
      partBuyer.body != 'false' &&
      !partBuyer.brief.toLowerCase().contains('not_allowed') &&
      !partBuyer.brief.toLowerCase().contains('requires_stripe') &&
      !partBuyer.brief.toLowerCase().contains('dispute_refund');
  if (partOk) {
    c.hold(
      id: 'CI4.partial_wallet_with_live_pi',
      lens: 'CI4',
      severity: 'P1',
      title: 'Refund parcial wallet com captura Stripe viva (pós-envio)',
      actor: 'buyer JWT',
      pre: 'concluido+disputa+oferta 1%, PI ${chain.pi}',
      repro: 'rpc batata_process_partial_refund_dispute percent=100',
      expected: 'dispute_partial_refund_requires_stripe / false',
      obtained: {
        'hit': partBuyer.brief,
        'stripe_refund_id': o?['stripe_refund_id'],
        'wallet_refund_at': o?['wallet_refund_processed_at'],
      },
    );
  } else {
    c.block('CI4.partial_wallet_with_live_pi', 'CI4',
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
      id: 'CI4.partial_percent_200',
      lens: 'CI4',
      severity: 'P1',
      title: 'RPC parcial aceita p_refund_percent=200',
      actor: 'buyer JWT',
      pre: 'oferta seller 1%',
      repro: 'rpc p_refund_percent=200',
      expected: 'usa % da oferta (≤100) ou recusa',
      obtained: part200.brief,
    );
  } else {
    c.block('CI4.partial_percent_200', 'CI4', 'percent 200 recusado/ignorado',
        part200);
  }

  final partSeller = await c.rpc(
    'batata_process_partial_refund_dispute',
    {'p_order_id': chain.oid, 'p_refund_percent': 50},
    jwt: c.sellerJwt,
  );
  await expectBlock(
    'CI4.partial_seller_rpc',
    'CI4',
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
  c.note('CI5.devolvida_chain', 'devolvida pré-refund', {
    'hit': dev.brief,
    'status': o?['status'],
    'qty_before': qtyBefore,
    'qty_mid': qtyMid,
    'units': o?['stock_units_applied'],
    'refund': o?['stripe_refund_id'],
  }, lens: 'CI5');

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
  c.note('CI5.refund_race', '2× refund-order após devolvida', {
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
  }, lens: 'CI5');

  final paidChain = numOf(o?['amount_paid_cents']) ?? 0;
  if ((qtyAfter - qtyBefore) >= 2) {
    c.hold(
      id: 'CI5.stock_restore_dup',
      lens: 'CI5',
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
    c.block('CI5.stock_restore_dup', 'CI5', 'stock restore uma vez', {
      'qty_before': qtyBefore,
      'qty_after': qtyAfter,
      'delta': qtyAfter - qtyBefore,
    });
  }

  if (stripeRefundN > 1 && stripeRefundSum > paidChain) {
    c.hold(
      id: 'CI4.refund_race_double_stripe',
      lens: 'CI4',
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
    c.block('CI4.refund_race_double_stripe', 'CI4', 'refund race idempotente', {
      'n': stripeRefundN,
      'sum': stripeRefundSum,
      'paid': paidChain,
    });
  }

  // 2.º restore: PATCH cancelado / relist após refund da cadeia
  final cancel2 = await c.patchOrder(
    chain.oid,
    {'status': 'cancelado'},
    jwt: c.sellerJwt,
  );
  final qtyAfterCancel = numOf((await c.productRow(chain.pid))?['quantity']) ?? 0;
  c.note('CI5.cancel_after_dispute_refund', 'cancelado após refund disputa', {
    'hit': cancel2.brief,
    'qty_after_refund': qtyAfter,
    'qty_after_cancel': qtyAfterCancel,
    'status': (await c.orderRow(chain.oid))?['status'],
  }, lens: 'CI5');
  if ((qtyAfterCancel - qtyBefore) >= 2) {
    c.hold(
      id: 'CI5.stock_restore_dispute_x_cancel',
      lens: 'CI5',
      severity: 'P1',
      title: 'Stock restaurou 2× (refund disputa + cancelado)',
      actor: 'seller JWT',
      pre: 'qty=$qtyBefore; já refundido',
      repro: 'refund-order após devolvida; PATCH cancelado',
      expected: '+1 no total',
      obtained: {
        'qty_before': qtyBefore,
        'qty_after_refund': qtyAfter,
        'qty_after_cancel': qtyAfterCancel,
      },
    );
  } else {
    c.block('CI5.stock_restore_dispute_x_cancel', 'CI5',
        '2.º restore cancelado não duplicou', {
      'qty_before': qtyBefore,
      'qty_after_refund': qtyAfter,
      'qty_after_cancel': qtyAfterCancel,
    });
  }

  // CI6 — release ∩ disputa
  final rel = await mustPay('CI6', qty: 1);
  if (!await c.toEnviado(rel.oid)) throw StateError('env rel');
  if (!await c.toConcluido(rel.oid)) throw StateError('conc rel');
  final wRel0 = await c.wallets();
  final relOpen = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': rel.oid},
    jwt: c.buyerJwt,
  );
  final wRel1 = await c.wallets();
  c.note('CI6.release_no_dispute', 'release em concluido sem disputa', {
    'hit': relOpen.brief,
    'dSeller': (wRel1['seller'] ?? 0) - (wRel0['seller'] ?? 0),
    'release_at': (await c.orderRow(rel.oid))?['wallet_release_processed_at'],
  }, lens: 'CI6');

  final dRel = await c.insertDispute(orderId: rel.oid);
  c.note('CI6.dispute_after_release', 'abrir disputa após release', dRel.brief,
      lens: 'CI6');
  if (dRel.ok) {
    c.hold(
      id: 'CI6.dispute_after_release',
      lens: 'CI6',
      severity: 'P1',
      title: 'Buyer abre disputa depois do release da carteira do vendedor',
      actor: 'buyer JWT',
      pre: 'concluido + release true, wallet_release_processed_at set',
      repro: 'POST order_disputes após batata_release_seller_wallet_for_order',
      expected: 'RLS recusa',
      obtained: {
        'release': relOpen.brief,
        'dispute': dRel.brief,
        'did': dRel.firstId,
      },
    );
  } else {
    c.block('CI6.dispute_after_release', 'CI6', 'disputa após release recusada',
        dRel);
  }

  final rel2 = await mustPay('CI6', qty: 1);
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
  c.note('CI6.release_open_dispute', 'release com disputa aberta', {
    'dispute': dOpen.brief,
    'release': relBlocked.brief,
    'dSeller': dSellerOpen,
  }, lens: 'CI6');
  final releasedAnyway = relBlocked.ok &&
      relBlocked.body != 'false' &&
      relBlocked.map?['ok'] != false &&
      dSellerOpen > 0;
  if (releasedAnyway) {
    c.hold(
      id: 'CI6.release_with_open_dispute',
      lens: 'CI6',
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
    c.block('CI6.release_with_open_dispute', 'CI6',
        'release bloqueado com disputa aberta', {
      'hit': relBlocked.brief,
      'dSeller': dSellerOpen,
    });
  }

  await expectBlock(
    'CI7.seller2_release',
    'CI7',
    'S2 tenta release da encomenda S1',
    await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': rel2.oid},
      jwt: c.seller2Jwt,
    ),
  );

  // Race release ∥ INSERT disputa
  final rel3 = await mustPay('CI6', qty: 1);
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
  c.note('CI6.race_release_dispute', 'race release ∥ INSERT disputa', {
    'hits': raceRel.map((h) => h.brief).toList(),
    'dSeller': dRace,
    'release_at': o?['wallet_release_processed_at'],
    'disputes': dispRace.brief,
  }, lens: 'CI6');
  final disputeOpen = dispRace.list.isNotEmpty;
  final released = o?['wallet_release_processed_at'] != null && dRace > 0;
  if (disputeOpen && released) {
    c.hold(
      id: 'CI6.race_release_and_dispute',
      lens: 'CI6',
      severity: 'P0',
      title: 'Race: release creditou E disputa ficou aberta',
      actor: 'buyer JWT',
      pre: 'concluido ${rel3.oid}',
      repro: 'Future.wait release + POST disputa',
      expected: 'um dos dois: release XOR disputa',
      obtained: {
        'dSeller': dRace,
        'release_at': o?['wallet_release_processed_at'],
        'disputes': dispRace.brief,
        'hits': raceRel.map((h) => h.brief).toList(),
      },
    );
  } else {
    c.block('CI6.race_release_dispute', 'CI6',
        'race release∥disputa não creditou com disputa', {
      'dSeller': dRace,
      'dispute_open': disputeOpen,
      'released': released,
    });
  }

  final happyDelta = (wRel1['seller'] ?? 0) - (wRel0['seller'] ?? 0);
  if (relOpen.ok &&
      relOpen.body != 'false' &&
      happyDelta > 0 &&
      dSellerOpen == 0) {
    c.block('CI8.release_vs_dispute', 'CI8',
        'release feliz credita; disputa segura o PI', {
      'happy_dSeller': happyDelta,
      'open_dSeller': dSellerOpen,
    });
  }

  c.note('CI8.wallets_final', 'wallets fim pass3', await c.wallets(),
      lens: 'CI8');
  c.note('CI8.chain_money', 'cadeia disputa→devolvida→refund Stripe+stock', {
    'oid': chain.oid,
    'pid': chain.pid,
    'pi': chain.pi,
    'paid': paidChain,
    'stripe_n': stripeRefundN,
    'stripe_sum': stripeRefundSum,
    'qty_before': qtyBefore,
    'qty_after': qtyAfter,
    'dBuyer': (wAfter['buyer'] ?? 0) - (wBeforeDev['buyer'] ?? 0),
    'dSeller': (wAfter['seller'] ?? 0) - (wBeforeDev['seller'] ?? 0),
  }, lens: 'CI8');
  await c.dumpAll('pass3.json');
}
