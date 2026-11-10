/// PASS 5 — I3/I7 carteira vazia: release → payout total → devolvida (clamp).
import 'dart:io';
import '_rti.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rti.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final out = <String, Object?>{'pass': 5, 'prefix': prefix};
  final wStart = await c.wallets();
  out['wallets_start'] = wStart;
  c.note('p5.start', 'saldos', wStart, lens: 'I7');

  // Order paga com seller2 (saldo 0) para o clawback não ter pool extra.
  final paid = await c.e2e('setup_paid_order', {
    'initial_qty': 2,
    'seller_id': c.seller2Id,
  });
  c.note('p5.paid', 'setup_paid_order seller2', paid.brief, lens: 'I3');
  final oid = c.parseE2eOrderId(paid);
  final pid = c.parseE2eProductId(paid);
  if (pid != null) c.createdProductIds.add(pid);
  if (oid == null) {
    out['fatal'] = 'no order';
    await dumpJson('tool/redteam_blind_i_20260831T1706/pass5.json', out);
    return;
  }
  c.createdOrderIds.add(oid);

  await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.seller2Jwt, body: {
    'shipping_method': 'entrega em mão',
  });
  final envio = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.seller2Jwt,
    body: {'status': 'enviado'},
  );
  c.note('p5.envio', 'seller2 enviado', envio.brief, lens: 'I3');
  final conc = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'status': 'concluido'},
  );
  c.note('p5.conc', 'buyer concluido', conc.brief, lens: 'I3');

  final s2Before = await c.walletBal(c.seller2Id);
  final bBefore = await c.walletBal(c.buyerId);
  var rel = await c.tryRelease(oid, jwt: c.buyerJwt);
  if (!(rel.ok && rel.json == true)) {
    rel = await c.tryRelease(oid, service: true);
  }
  c.note('p5.release', 'release seller2', rel.brief, lens: 'I3');
  final s2AfterRel = await c.walletBal(c.seller2Id);
  final credited = s2AfterRel - s2Before;
  out['credited'] = credited;

  HttpHit? payout;
  var drained = false;
  if (credited >= 0.5) {
    final cents = (credited * 100).round();
    payout = await c.edge(
      'create-connect-account',
      {
        'amount': cents,
        'idempotency_key': '${prefix}_s2drain_${oid.substring(0, 8)}',
      },
      jwt: c.seller2Jwt,
    );
    c.note('p5.payout', 'seller2 payout full credit', payout.brief, lens: 'I1');
    drained = payout.ok && payout.map?['success'] == true;
  }
  var s2AfterDrain = await c.walletBal(c.seller2Id);
  var simulated = false;
  if (!drained) {
    final z = await c.rest(
      'PATCH',
      'wallets?id=eq.${c.seller2Id}',
      service: true,
      body: {'balance': 0},
    );
    simulated = z.ok;
    s2AfterDrain = await c.walletBal(c.seller2Id);
    c.note('p5.sim', 'seller2 balance=0 fixture (Connect não pronto)', {
      'patch': z.brief,
      'bal': s2AfterDrain,
      'payout': payout?.brief,
    }, lens: 'I7');
  }

  final toDev = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    service: true,
    body: {'status': 'devolvida'},
  );
  c.note('p5.devolvida', 'devolvida', toDev.brief, lens: 'I3');
  final row = await c.orderRow(oid);
  final s2End = await c.walletBal(c.seller2Id);
  final bEnd = await c.walletBal(c.buyerId);
  final tx = await c.walletTxns(orderId: oid, limit: 20);
  final vendaAmt = tx.where((e) => e is Map && e['type'] == 'venda').fold<num>(0,
      (a, e) {
    final n = (e as Map)['amount'];
    return a + (n is num ? n : num.tryParse('$n') ?? 0);
  });
  final estornoAmt = tx
      .where((e) => e is Map && e['type'] == 'estorno')
      .fold<num>(0, (a, e) {
    final n = (e as Map)['amount'];
    return a + (n is num ? n : num.tryParse('$n') ?? 0);
  });
  final reembAmt = tx
      .where((e) => e is Map && e['type'] == 'reembolso')
      .fold<num>(0, (a, e) {
    final n = (e as Map)['amount'];
    return a + (n is num ? n : num.tryParse('$n') ?? 0);
  });

  final books = {
    'order': row,
    's2_before': s2Before,
    's2_after_rel': s2AfterRel,
    's2_after_drain': s2AfterDrain,
    's2_end': s2End,
    'buyer_before': bBefore,
    'buyer_end': bEnd,
    'buyer_gain': bEnd - bBefore,
    'credited': credited,
    'drained_payout': drained,
    'simulated_drain': simulated,
    'payout': payout?.brief,
    'venda': vendaAmt,
    'estorno': estornoAmt,
    'reembolso': reembAmt,
    'stripe_refund_id': row?['stripe_refund_id'],
    'pi': row?['stripe_payment_intent_id'],
    'txns': tx,
  };
  out['books'] = books;
  c.note('p5.books', 'contabilidade seller2 vazio', books, lens: 'I7');

  final buyerGain = bEnd - bBefore;
  final stripeRefund = '${row?['stripe_refund_id'] ?? ''}';
  // Buraco: comprador mintado, PI não reembolsado, seller já sem saldo,
  // estorno no livro mas carteira continua ~0 (clamp).
  if (buyerGain > 0.05 &&
      s2End < 0.05 &&
      stripeRefund.isEmpty &&
      (drained || simulated)) {
    c.hold(
      id: 'RTI-I3-007',
      lens: 'I3',
      severity: drained ? 'P0' : 'P1',
      title: drained
          ? 'Seller2 levantou o release para Connect; devolvida mintou o comprador sem Stripe refund nem saldo para clawback'
          : 'Após saldo seller=0, devolvida credita o comprador; clawback clampa a 0 (estorno no livro, sem fundos)',
      actor: 'seller2 payout/drain + service_role devolvida',
      pre:
          'seller2 saldo inicial $s2Before; release $credited; drain payout=$drained sim=$simulated',
      repro:
          'setup_paid_order seller2 → concluido → release → payout total → PATCH devolvida',
      expected:
          'sem mint wallet se o PI não foi refundido e o vendedor já levantou; ou reverse Transfer / saldo negativo',
      obtained: books,
    );
  }

  // I7-P0: seller1 COM Connect — payout do saldo INTEIRO, depois devolvida.
  final paid1 = await c.e2e('setup_paid_order', {'initial_qty': 2});
  c.note('p5.paid1', 'setup_paid_order seller1', paid1.brief, lens: 'I7');
  final oid1 = c.parseE2eOrderId(paid1);
  if (oid1 != null) {
    c.createdOrderIds.add(oid1);
    final pid1 = c.parseE2eProductId(paid1);
    if (pid1 != null) c.createdProductIds.add(pid1);
    await c.rest('PATCH', 'orders?id=eq.$oid1', jwt: c.sellerJwt, body: {
      'shipping_method': 'entrega em mão',
    });
    await c.rest('PATCH', 'orders?id=eq.$oid1', jwt: c.sellerJwt, body: {
      'status': 'enviado',
    });
    await c.rest('PATCH', 'orders?id=eq.$oid1', jwt: c.buyerJwt, body: {
      'status': 'concluido',
    });
    final s1b = await c.walletBal(c.sellerId);
    final b1b = await c.walletBal(c.buyerId);
    var r1 = await c.tryRelease(oid1, jwt: c.buyerJwt);
    if (!(r1.ok && r1.json == true)) {
      r1 = await c.tryRelease(oid1, service: true);
    }
    final s1rel = await c.walletBal(c.sellerId);
    final allCents = (s1rel * 100).round();
    c.note('p5.s1.pre_full', 'seller1 pré-payout total', {
      'release': r1.brief,
      'bal': s1rel,
      'cents': allCents,
    }, lens: 'I7');
    HttpHit? fullPay;
    if (allCents >= 50) {
      fullPay = await c.edge(
        'create-connect-account',
        {
          'amount': allCents,
          'idempotency_key': '${prefix}_full_${oid1.substring(0, 8)}',
        },
        jwt: c.sellerJwt,
      );
      c.note('p5.s1.full_payout', 'payout saldo inteiro', fullPay.brief,
          lens: 'I7');
    }
    final s1drain = await c.walletBal(c.sellerId);
    final fullOk = fullPay != null &&
        fullPay.ok &&
        fullPay.map?['success'] == true;
    await c.rest(
      'PATCH',
      'orders?id=eq.$oid1',
      service: true,
      body: {'status': 'devolvida'},
    );
    final s1end = await c.walletBal(c.sellerId);
    final b1end = await c.walletBal(c.buyerId);
    final row1 = await c.orderRow(oid1);
    final tx1 = await c.walletTxns(orderId: oid1);
    final fullBooks = {
      'full_payout_ok': fullOk,
      'payout': fullPay?.brief,
      's1_before': s1b,
      's1_after_rel': s1rel,
      's1_after_drain': s1drain,
      's1_end': s1end,
      'buyer_gain': b1end - b1b,
      'stripe_refund': row1?['stripe_refund_id'],
      'pi': row1?['stripe_payment_intent_id'],
      'txns': tx1,
    };
    out['full_drain_books'] = fullBooks;
    c.note('p5.s1.books', 'seller1 payout total + devolvida', fullBooks,
        lens: 'I7');
    final rf = '${row1?['stripe_refund_id'] ?? ''}';
    if (fullOk && (b1end - b1b) > 0.05 && s1end < 0.05 && rf.isEmpty) {
      c.hold(
        id: 'RTI-I3-008',
        lens: 'I3',
        severity: 'P0',
        title:
            'Levantamento total Connect + devolvida: comprador mintado, PI sem refund, vendedor a 0',
        actor: 'seller JWT payout all + trigger devolvida',
        pre: 'seller Connect pronto; saldo $s1rel → transfer ${fullPay?.map?['transferId']}',
        repro:
            'release → create-connect-account amount=saldo_cêntimos → PATCH devolvida',
        expected: 'sem crédito wallet ao comprador se o dinheiro já saiu e o PI não foi anulado',
        obtained: fullBooks,
      );
    }
  }

  out['wallets_end'] = await c.wallets();
  out['findings'] = c.findings;
  out['notes'] = c.notes;
  await dumpJson('tool/redteam_blind_i_20260831T1706/pass5.json', out);
  stdout.writeln('PASS5 findings=${c.findings.length}');
}
