import '_rtch.dart';

/// Pass 3 — composição Δwallet ↔ Stripe · crash after_finish · refund crash
void main() async {
  final c = Rtch.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final buyerW = await c.walletRow(c.buyerId);
  c.note('rls.buyer.wallet', 'buyer wallet após PATCH alheio pass1 (esperado ≠66666)', buyerW,
      lens: 'CH5');
  if (buyerW != null && (numOf(buyerW['balance']) ?? 0) >= 66600) {
    c.hold(
      id: 'CH-P0-WALLET-PATCH-OTHER-CONFIRMED',
      lens: 'CH5',
      severity: 'P0',
      title: 'PATCH alheio persistiu balance≈66666',
      actor: 'seller JWT',
      pre: 'pass1 PATCH wallets buyer',
      repro: 'GET wallets buyer após PATCH',
      expected: 'saldo inalterado, ≠66666',
      obtained: buyerW,
    );
  } else {
    c.block('rls.buyer.wallet', 'CH5',
        'buyer balance ≠66666 — PATCH 200 [] foi 0 rows (falso positivo pass1)', buyerW);
  }

  await c.ensureWalletBalance(c.sellerId!, 20);
  final led0 = await c.payoutLedger(c.sellerId!, limit: 40);
  final tids0 = led0
      .map((r) => '${r['stripe_transfer_id']}')
      .where((s) => s.startsWith('tr_'))
      .toSet();
  final w0 = await c.walletBal(c.sellerId);
  c.note('comp.start', 'ledger+wallet início pass3', {
    'wallet': w0,
    'tids': tids0.length,
  }, lens: 'CH7');

  // crash after_finish_before_response
  if (c.crashSecret.length >= 16) {
    final key = '${prefix}_fincrash';
    final hCrash = await c.connect(
      {
        'amount': 100,
        'idempotency_key': key,
        'crash_inject': 'after_finish_before_response',
      },
      extra: {'x-fleaber-crash-inject-secret': c.crashSecret},
    );
    final retry = await c.connect({
      'amount': 100,
      'idempotency_key': key,
    });
    final tids = <String>{
      if ((hCrash.transferId ?? '').startsWith('tr_')) hCrash.transferId!,
      if ((retry.transferId ?? '').startsWith('tr_')) retry.transferId!,
    };
    c.note('crash.finish', 'after_finish + retry', {
      'crash': hCrash.brief,
      'retry': retry.brief,
      'tids': tids.toList(),
    }, lens: 'CH4');
    if (tids.length >= 2) {
      c.hold(
        id: 'CH-P0-CRASH-FINISH',
        lens: 'CH4',
        severity: 'P0',
        title: 'crash after_finish_before_response + retry → 2 Transfers',
        actor: 'seller JWT + secret',
        pre: 'ledger já transferred; retry idempotente',
        repro: 'crash after_finish_before_response; retry mesma key',
        expected: '1 Transfer',
        obtained: {'crash': hCrash.brief, 'retry': retry.brief, 'tids': tids.toList()},
      );
    } else {
      c.block('crash.finish', 'CH4', 'after_finish retry 1 Transfer', {
        'crash': hCrash.brief,
        'retry': retry.brief,
        'tids': tids.toList(),
      });
    }
  }

  // Composição: se pass1 abriu homóglifo, reconfirmar Δ vs nº Transfers desta corrida
  final led1 = await c.payoutLedger(c.sellerId!, limit: 50);
  final tids1 = led1
      .map((r) => '${r['stripe_transfer_id']}')
      .where((s) => s.startsWith('tr_'))
      .toSet();
  final newTids = tids1.difference(tids0);
  final w1 = await c.walletBal(c.sellerId);
  final delta = w1 - w0;
  c.note('comp.delta', 'Δwallet vs novos Transfers desta sessão pass3', {
    'wallet0': w0,
    'wallet1': w1,
    'delta_eur': delta,
    'new_tids': newTids.toList(),
    'new_count': newTids.length,
    'expected_delta_if_100c': -0.01 * newTids.length,
  }, lens: 'CH7');
  final expected = -1.0 * newTids.length; // 100 cents each = 1 EUR? amount=100 cents = 1.00 EUR
  // Wait: amount=100 means 100 cents = 1.00 EUR. CB used 100 cents = 1.00 EUR? 
  // CB report: wallet 76.33 → 74.33 (−2,00 €) for 2 transfers of 100 cents.
  // 100 cents = 1.00 EUR. Yes expected = -1.0 * count.
  if (newTids.isNotEmpty && (delta + newTids.length).abs() > 0.05) {
    c.hold(
      id: 'CH-P0-DELTA-MISMATCH',
      lens: 'CH7',
      severity: 'P0',
      title: 'Δwallet ≠ −1€ × nº Transfers Stripe novos',
      actor: 'seller JWT',
      pre: 'cada Transfer 100c = 1,00 € no ledger',
      repro: 'comparar wallet Δ com wallet_payout_ledger stripe_transfer_id novos',
      expected: 'delta_eur == -1.00 * new_transfer_count',
      obtained: {
        'delta': delta,
        'new_count': newTids.length,
        'new_tids': newTids.toList(),
      },
    );
  } else {
    c.block('comp.delta', 'CH7', 'Δwallet coerente com Transfers (ou 0 novos)', {
      'delta': delta,
      'new_count': newTids.length,
    });
  }

  // refund crash_inject + retry (não duplicar refund Stripe)
  final paid = await c.payToPago(lens: 'CH3');
  if (paid != null && c.crashSecret.length >= 16) {
    final h1 = await c.refundOrder(
      paid.oid,
      extra: {'x-fleaber-crash-inject-secret': c.crashSecret},
      extraBody: {'crash_inject': 'after_stripe_before_db'},
    );
    final h2 = await c.refundOrder(paid.oid);
    final row = await c.orderRow(paid.oid);
    c.note('refund.crash', 'refund crash + retry', {
      'c1': h1.brief,
      'c2': h2.brief,
      'order': row,
    }, lens: 'CH3');
    final ids = <String>{
      if ('${h1.map?['refund_id'] ?? ''}'.startsWith('re_'))
        '${h1.map?['refund_id']}',
      if ('${h2.map?['refund_id'] ?? ''}'.startsWith('re_'))
        '${h2.map?['refund_id']}',
    };
    if (ids.length >= 2) {
      c.hold(
        id: 'CH-P0-REFUND-CRASH-DUP',
        lens: 'CH3',
        severity: 'P0',
        title: 'crash refund after_stripe_before_db + retry → 2 refunds Stripe',
        actor: 'seller JWT + secret',
        pre: 'idempotency fleaber_order_refund_{orderId}',
        repro: 'crash after_stripe_before_db; retry refund-order',
        expected: '1 re_',
        obtained: {'ids': ids.toList(), 'c1': h1.brief, 'c2': h2.brief},
      );
    } else {
      c.block('refund.crash', 'CH3', 'refund crash retry 1 re_', {
        'ids': ids.toList(),
        'c1': h1.brief,
        'c2': h2.brief,
      });
    }
  } else if (paid == null) {
    c.skip('refund.crash', 'CH3', 'setup_paid_order falhou', null);
  }

  // JWT finalize
  if (paid != null) {
    final finJwt = await c.rpc('batata_finalize_stripe_order_refund', {
      'p_order_id': paid.oid,
      'p_refund_id': 're_fake_rtch',
      'p_amount_cents': 999999,
    }, jwt: c.sellerJwt);
    await c.expectDenied(
      id: 'CH-P0-FINALIZE-JWT',
      lens: 'CH6',
      title: 'JWT executou batata_finalize_stripe_order_refund',
      hit: finJwt,
      actor: 'seller JWT',
      pre: 'GRANT só service_role',
      repro: 'POST rpc/batata_finalize_stripe_order_refund',
      severityIfOpen: 'P0',
      openIf: (h) => h.ok && h.map?['ok'] == true,
    );
  }

  await c.dumpAll('pass3.json');
}
