/// PASS 3 — I3 release+refund+clawback líquido · I5 · I6 residual · I7.
import 'dart:io';
import '_rti.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rti.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();

  final out = <String, Object?>{'pass': 3, 'prefix': prefix};
  final wStart = await c.wallets();
  out['wallets_start'] = wStart;

  final oid = await c.payAndComplete(lens: 'I3');
  if (oid == null) {
    out['fatal'] = 'no paid order';
    await dumpJson('tool/redteam_blind_i_20260831T1706/pass3.json', out);
    return;
  }
  final buyerBefore = await c.walletBal(c.buyerId);
  final sellerBefore = await c.walletBal(c.sellerId);

  var rel = await c.tryRelease(oid, jwt: c.buyerJwt);
  if (!(rel.ok && rel.json == true)) {
    rel = await c.tryRelease(oid, service: true);
  }
  c.note('p3.release', 'release', rel.brief, lens: 'I3');
  final sellerAfterRel = await c.walletBal(c.sellerId);
  final credited = sellerAfterRel - sellerBefore;
  out['credited_eur'] = credited;

  // Drain: tentar payout real do montante libertado
  final drainCents = credited > 0
      ? (credited * 100).round().clamp(1, 100000)
      : 0;
  HttpHit? payout;
  if (drainCents >= 50) {
    payout = await c.edge(
      'create-connect-account',
      {
        'amount': drainCents,
        'idempotency_key': '${prefix}_drain_${oid.substring(0, 8)}',
      },
      jwt: c.sellerJwt,
    );
    c.note('p3.i7.payout_drain', 'payout do release', payout.brief, lens: 'I7');
  }
  var sellerAfterDrain = await c.walletBal(c.sellerId);
  var drainedViaPayout = payout != null &&
      payout.ok &&
      payout.map?['success'] == true;
  out['payout_drain'] = {
    'hit': payout?.brief,
    'drained': drainedViaPayout,
    'seller_after': sellerAfterDrain,
  };

  // Se Connect não está pronto: simular payout (saldo=0) SÓ para observar
  // o clawback clamp — fixture, não é o ataque.
  var simulatedDrain = false;
  if (!drainedViaPayout && credited > 0.01) {
    final zero = await c.rest(
      'PATCH',
      'wallets?id=eq.${c.sellerId}',
      service: true,
      body: {'balance': 0},
    );
    simulatedDrain = zero.ok;
    sellerAfterDrain = await c.walletBal(c.sellerId);
    c.note('p3.i7.sim_drain', 'fixture balance=0 (Connect não transferiu)', {
      'patch': zero.brief,
      'seller': sellerAfterDrain,
    }, lens: 'I7');
  }

  // I6: buyer força reembolso parcial sem oferta do seller
  final disputeIns = await c.rest('POST', 'order_disputes', jwt: c.buyerJwt, body: {
    'order_id': oid,
    'buyer_id': c.buyerId,
    'reason': 'item_not_as_described',
    'status': 'aberta',
    'seller_refund_percent': 100,
    'seller_offer_type': 'partial_refund',
    'seller_offer_set_by': c.sellerId,
  });
  c.note('p3.i6.dispute_insert', 'buyer INSERT disputa com oferta forjada',
      disputeIns.brief,
      lens: 'I6');
  if (disputeIns.ok && disputeIns.firstId != null) {
    final forgedId = disputeIns.firstId!;
    final pct = disputeIns.map?['seller_refund_percent'];
    final setBy = disputeIns.map?['seller_offer_set_by'];
    if (pct == 100 || setBy == c.sellerId) {
      c.hold(
        id: 'RTI-I6-006',
        lens: 'I6',
        severity: 'P1',
        title: 'Comprador gravou oferta de reembolso como se fosse o vendedor',
        actor: 'buyer JWT',
        pre: 'INSERT order_disputes seller_refund_percent=100',
        repro: 'POST order_disputes',
        expected: 'percent/set_by stripped ou 403',
        obtained: disputeIns.map,
      );
    }
    final partial = await c.rpc(
      'batata_process_partial_refund_dispute',
      {'p_order_id': oid, 'p_refund_percent': 100},
      jwt: c.buyerJwt,
    );
    c.note('p3.i6.partial_rpc', 'buyer process_partial_refund', partial.brief,
        lens: 'I6');
    if (partial.ok && partial.json == true) {
      c.hold(
        id: 'RTI-I6-007',
        lens: 'I6',
        severity: 'P0',
        title: 'Comprador executou reembolso parcial com oferta forjada',
        actor: 'buyer JWT',
        pre: 'disputa inserida pelo próprio buyer',
        repro: 'rpc batata_process_partial_refund_dispute',
        expected: 'dispute_refund_offer_required / false',
        obtained: {
          'rpc': partial.brief,
          'buyer_wallet': await c.walletBal(c.buyerId),
          'seller_wallet': await c.walletBal(c.sellerId),
        },
      );
    }
    out['forged_dispute'] = {'id': forgedId, 'partial': partial.brief};
  }

  // I5: refund-order ainda após release
  final ref = await c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt);
  c.note('p3.i5.refund', 'seller refund-order', ref.brief, lens: 'I5');

  // I3: forçar devolvida (caminho disputa/admin) e medir líquido
  final toDev = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    service: true,
    body: {'status': 'devolvida'},
  );
  c.note('p3.i3.devolvida', 'service_role status=devolvida', toDev.brief,
      lens: 'I3');
  final afterDev = await c.orderRow(oid);
  final buyerAfter = await c.walletBal(c.buyerId);
  final sellerAfter = await c.walletBal(c.sellerId);
  final txns = await c.walletTxns(orderId: oid, limit: 30);
  out['after_devolvida'] = {
    'order': afterDev,
    'buyer_before': buyerBefore,
    'buyer_after': buyerAfter,
    'seller_before': sellerBefore,
    'seller_after_rel': sellerAfterRel,
    'seller_after_drain': sellerAfterDrain,
    'seller_after_dev': sellerAfter,
    'delta_buyer': buyerAfter - buyerBefore,
    'delta_seller_net': sellerAfter - sellerBefore,
    'drained_via_payout': drainedViaPayout,
    'simulated_drain': simulatedDrain,
    'txns': txns,
  };

  final buyerGained = buyerAfter - buyerBefore;
  final sellerNet = sellerAfter - sellerBefore;
  // Líquido de plataforma: se buyer ganhou wallet E seller ficou >= 0 após
  // já ter levado o release (payout/sim), a soma buyer_gain + max(seller_kept,0)
  // + transfer Stripe > 0 relativamente ao PI.
  final estorno = txns.where((e) {
    return e is Map && '${e['type']}' == 'estorno';
  }).toList();
  final venda = txns.where((e) {
    return e is Map && '${e['type']}' == 'venda';
  }).toList();
  final reemb = txns.where((e) {
    return e is Map && '${e['type']}' == 'reembolso';
  }).toList();

  c.note('p3.i7.books', 'livro após devolvida', {
    'buyer_gain': buyerGained,
    'seller_net': sellerNet,
    'venda_n': venda.length,
    'estorno_n': estorno.length,
    'reemb_n': reemb.length,
    'release_flag': afterDev?['wallet_release_processed_at'],
    'refund_flag': afterDev?['wallet_refund_processed_at'],
    'stripe_refund': afterDev?['stripe_refund_id'],
  }, lens: 'I7');

  // P0: buyer wallet minted AND seller still has the released money
  // (payout success OR clamp left seller at 0 but estorno didn't recover
  //  because money already left / balance was 0).
  if (buyerGained > 0.05 &&
      (drainedViaPayout || simulatedDrain) &&
      sellerAfter > -0.01) {
    final vendaAmt = venda.fold<num>(0, (a, e) {
      final n = (e as Map)['amount'];
      return a + (n is num ? n : num.tryParse('$n') ?? 0);
    });
    final estornoAmt = estorno.fold<num>(0, (a, e) {
      final n = (e as Map)['amount'];
      return a + (n is num ? n : num.tryParse('$n') ?? 0);
    });
    // Se o livro diz estorno=venda mas o saldo não desceu (já estava 0),
    // o clawback mentiu — dinheiro já saiu.
    if (estornoAmt + 0.01 >= vendaAmt && sellerAfterDrain < 0.05) {
      c.hold(
        id: 'RTI-I3-005',
        lens: 'I3',
        severity: drainedViaPayout ? 'P0' : 'P1',
        title: drainedViaPayout
            ? 'Após payout Connect, devolvida mintou o comprador sem recuperar o Transfer'
            : 'Clawback após saldo 0: livro estorna mas carteira não fica negativa; comprador é creditado',
        actor: 'seller payout + trigger devolvida',
        pre:
            'release Δ=$credited; drain payout=$drainedViaPayout sim=$simulatedDrain',
        repro:
            'setup_paid_order → concluido → release → payout/drain → PATCH devolvida',
        expected:
            'buyer não recebe wallet se Stripe não foi refundido e seller já levantou; ou Connect reverse',
        obtained: {
          'buyer_gain': buyerGained,
          'seller_after': sellerAfter,
          'venda': vendaAmt,
          'estorno': estornoAmt,
          'payout': payout?.brief,
          'stripe_refund_id': afterDev?['stripe_refund_id'],
        },
      );
    }
  }

  // I6 residual: buyer2 tenta refund RPC da order já devolvida
  final rpcB2 = await c.rpc(
    'batata_refund_buyer_wallet_for_order',
    {'p_order_id': oid},
    jwt: c.buyer2Jwt,
  );
  c.note('p3.i6.refund_rpc_b2_after', 'buyer2 refund rpc pós-devolvida',
      rpcB2.brief,
      lens: 'I6');
  final buyer2After = await c.walletBal(c.buyer2Id);
  if (rpcB2.ok && rpcB2.json == true) {
    c.hold(
      id: 'RTI-I6-008',
      lens: 'I6',
      severity: 'P0',
      title: '2.º buyer reprocessou refund wallet de order alheia',
      actor: 'buyer2 JWT',
      pre: 'já devolvida',
      repro: 'rpc batata_refund_buyer_wallet_for_order',
      expected: 'false',
      obtained: rpcB2.brief,
    );
  }
  if ((buyer2After - (wStart['buyer2'] ?? 0)).abs() > 0.05) {
    c.hold(
      id: 'RTI-I6-009',
      lens: 'I6',
      severity: 'P0',
      title: 'Carteira do 2.º buyer mudou no refund alheio',
      actor: 'buyer2',
      pre: 'order buyer1',
      repro: 'observar wallets.buyer2',
      expected: 'Δ=0',
      obtained: {'before': wStart['buyer2'], 'after': buyer2After},
    );
  }

  // Double refund RPC pelo buyer legítimo
  final rpcAgain = await c.rpc(
    'batata_refund_buyer_wallet_for_order',
    {'p_order_id': oid},
    jwt: c.buyerJwt,
  );
  final buyerDouble = await c.walletBal(c.buyerId);
  c.note('p3.i3.refund_replay', 'buyer 2.º refund_wallet', {
    'rpc': rpcAgain.brief,
    'buyer': buyerDouble,
  }, lens: 'I3');
  if (buyerDouble - buyerAfter > 0.05) {
    c.hold(
      id: 'RTI-I3-006',
      lens: 'I3',
      severity: 'P0',
      title: '2.º refund_buyer_wallet mintou outra vez',
      actor: 'buyer JWT',
      pre: 'já wallet_refund_processed_at',
      repro: 'rpc batata_refund_buyer_wallet_for_order ×2',
      expected: 'false, Δ=0',
      obtained: {'after_first': buyerAfter, 'after_second': buyerDouble},
    );
  }

  // Restaurar saldo seller se sim_drain (não deixar staging a 0 por fixture)
  if (simulatedDrain) {
    await c.rest(
      'PATCH',
      'wallets?id=eq.${c.sellerId}',
      service: true,
      body: {'balance': sellerBefore},
      prefer: 'return=minimal',
    );
    c.note('p3.restore', 'restauro saldo seller pós-sim', sellerBefore,
        lens: 'I7');
  }

  out['wallets_end'] = await c.wallets();
  out['findings'] = c.findings;
  out['notes'] = c.notes;
  await dumpJson('tool/redteam_blind_i_20260831T1706/pass3.json', out);
  stdout.writeln('PASS3 findings=${c.findings.length}');
}
