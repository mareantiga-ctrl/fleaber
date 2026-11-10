/// PASS 2 — Stripe TEST pago + release + payout Edge (I1/I4/I7).
import 'dart:io';
import '_rti.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rti.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();

  final out = <String, Object?>{'pass': 2, 'prefix': prefix};
  final wStart = await c.wallets();
  out['wallets_start'] = wStart;
  c.note('p2.start', 'saldos', wStart, lens: 'I7');

  final oid = await c.payAndComplete(lens: 'I3');
  if (oid == null) {
    stderr.writeln('setup_paid_order failed');
    out['fatal'] = 'no paid order';
    await dumpJson('tool/redteam_blind_i_20260831T1706/pass2.json', out);
    return;
  }
  final rowPaid = await c.orderRow(oid);
  out['order_paid'] = rowPaid;
  c.note('p2.order', 'após enviado+concluido', rowPaid, lens: 'I3');

  final sellerBeforeRelease = await c.walletBal(c.sellerId);
  final relB2 = await c.tryRelease(oid, jwt: c.buyer2Jwt);
  c.note('p2.i3.release_b2', 'buyer2 tenta release alheio', relB2.brief,
      lens: 'I3');
  if (relB2.ok && relB2.json == true) {
    c.hold(
      id: 'RTI-I3-002',
      lens: 'I3',
      severity: 'P0',
      title: '2.º comprador libertou carteira do vendedor',
      actor: 'buyer2 JWT',
      pre: 'order concluido buyer1',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false',
      obtained: relB2.brief,
    );
  }
  final relS = await c.tryRelease(oid, jwt: c.sellerJwt);
  c.note('p2.i3.release_seller', 'seller tenta self-release', relS.brief,
      lens: 'I3');
  if (relS.ok && relS.json == true) {
    c.hold(
      id: 'RTI-I3-003',
      lens: 'I3',
      severity: 'P1',
      title: 'Vendedor libertou a própria carteira (JWT)',
      actor: 'seller JWT',
      pre: 'concluido, release só buyer/admin/service',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false',
      obtained: relS.brief,
    );
  }

  final relB = await c.tryRelease(oid, jwt: c.buyerJwt);
  c.note('p2.i3.release_buyer', 'buyer JWT release', relB.brief, lens: 'I3');
  var released = relB.ok && relB.json == true;
  if (!released) {
    final relSvc = await c.tryRelease(oid, service: true);
    c.note('p2.i3.release_svc', 'service_role release', relSvc.brief,
        lens: 'I3');
    released = relSvc.ok && relSvc.json == true;
  }
  final rowRel = await c.orderRow(oid);
  final sellerAfterRelease = await c.walletBal(c.sellerId);
  final deltaRel = sellerAfterRelease - sellerBeforeRelease;
  out['release'] = {
    'buyer': relB.brief,
    'released': released,
    'order': rowRel,
    'seller_before': sellerBeforeRelease,
    'seller_after': sellerAfterRelease,
    'delta': deltaRel,
  };
  c.note('p2.i7.delta_release', 'Δ seller após release', deltaRel, lens: 'I7');

  final relAgain = await c.tryRelease(oid, jwt: c.buyerJwt);
  final relAgain2 = await c.tryRelease(oid, service: true);
  c.note('p2.i3.release_replay', '2.º release JWT+svc', {
    'jwt': relAgain.brief,
    'svc': relAgain2.brief,
    'seller_now': await c.walletBal(c.sellerId),
  }, lens: 'I3');
  final sellerAfterReplay = await c.walletBal(c.sellerId);
  if (sellerAfterReplay - sellerAfterRelease > 0.05) {
    c.hold(
      id: 'RTI-I3-004',
      lens: 'I3',
      severity: 'P0',
      title: 'Release replay creditou o vendedor outra vez',
      actor: 'buyer JWT + service_role',
      pre: 'já wallet_release_processed_at',
      repro: '2.º batata_release_seller_wallet_for_order',
      expected: 'Δ=0',
      obtained: {
        'after_first': sellerAfterRelease,
        'after_replay': sellerAfterReplay,
      },
    );
  }

  // I5: seller refund-order APÓS release/concluido
  final refAfter = await c.edge(
    'refund-order',
    {'order_id': oid},
    jwt: c.sellerJwt,
  );
  c.note('p2.i5.refund_after_release', 'seller refund-order pós-concluido',
      refAfter.brief,
      lens: 'I5');
  final rowAfterRef = await c.orderRow(oid);
  if (refAfter.ok &&
      refAfter.map?['ok'] == true &&
      refAfter.map?['skipped'] != true &&
      (rowAfterRef?['stripe_refund_id'] != null &&
          '${rowAfterRef?['stripe_refund_id']}'.isNotEmpty)) {
    c.hold(
      id: 'RTI-I5-001',
      lens: 'I5',
      severity: 'P0',
      title: 'Vendedor reembolsou Stripe após já ter release',
      actor: 'seller JWT',
      pre: 'concluido + wallet_release_processed_at',
      repro: 'POST refund-order',
      expected: '403 order_refund_blocked_status',
      obtained: {
        'edge': refAfter.brief,
        'stripe_refund_id': rowAfterRef?['stripe_refund_id'],
      },
    );
  }

  // I1/I4: payout Edge — mesma key ∥ e keys distintas
  final cents = (deltaRel * 100).round();
  final payAmt = cents > 0 ? (cents < 100 ? cents : 100) : 50;
  final sameKey = '${prefix}_payout_same';
  final crashHdr = c.e2eSecret.isEmpty
      ? null
      : {
          'x-fleaber-crash-inject-secret': c.e2eSecret,
        };

  final pSame = await parallel([
    c.edge(
      'create-connect-account',
      {'amount': payAmt, 'idempotency_key': sameKey},
      jwt: c.sellerJwt,
    ),
    c.edge(
      'create-connect-account',
      {'amount': payAmt, 'idempotency_key': sameKey},
      jwt: c.sellerJwt,
    ),
  ]);
  c.note('p2.i4.same_key', '2× payout mesma key', {
    'a': pSame[0].brief,
    'b': pSame[1].brief,
  }, lens: 'I4');

  final sellerMid = await c.walletBal(c.sellerId);
  final k1 = '${prefix}_payout_d1';
  final k2 = '${prefix}_payout_d2';
  final pDiff = await parallel([
    c.edge(
      'create-connect-account',
      {'amount': payAmt, 'idempotency_key': k1},
      jwt: c.sellerJwt,
    ),
    c.edge(
      'create-connect-account',
      {'amount': payAmt, 'idempotency_key': k2},
      jwt: c.sellerJwt,
    ),
  ]);
  c.note('p2.i4.diff_keys', '2× payout keys distintas amount=$payAmt', {
    'a': pDiff[0].brief,
    'b': pDiff[1].brief,
    'seller_before': sellerMid,
    'seller_after': await c.walletBal(c.sellerId),
  }, lens: 'I4');

  final ledger = await c.payoutLedger(userId: c.sellerId, limit: 8);
  out['payout_ledger'] = ledger;
  final newTransfers = ledger.where((e) {
    if (e is! Map) return false;
    final k = '${e['idempotency_key']}';
    return k.contains(prefix);
  }).toList();
  final transferred = newTransfers
      .where((e) => e is Map && e['status'] == 'transferred')
      .toList();
  if (transferred.length >= 2 &&
      sellerMid < (payAmt * 2) / 100.0 - 0.01) {
    final sums = transferred.fold<int>(0, (a, e) {
      final n = (e as Map)['amount_cents'];
      return a + (n is int ? n : int.tryParse('$n') ?? 0);
    });
    c.hold(
      id: 'RTI-I4-001',
      lens: 'I4',
      severity: 'P1',
      title: 'Dois Transfers Stripe quando o saldo não cobria 2× amount',
      actor: 'seller JWT Edge',
      pre: 'Δ release=$deltaRel, amount=$payAmt¢ cada, saldo=$sellerMid',
      repro: 'Future.wait 2× create-connect-account keys diferentes',
      expected: '1 transfer + 1 insufficient_balance',
      obtained: {
        'ledger': newTransfers,
        'transferred_n': transferred.length,
        'sum_cents': sums,
      },
    );
  }

  // Replay same key after success should be idempotent
  if (pSame[0].ok || pSame[1].ok) {
    final replay = await c.edge(
      'create-connect-account',
      {'amount': payAmt + 50, 'idempotency_key': sameKey},
      jwt: c.sellerJwt,
    );
    c.note('p2.i4.replay_higher', 'replay same key amount maior', replay.brief,
        lens: 'I4');
    if (replay.ok && replay.map?['success'] == true && replay.map?['idempotent'] != true) {
      // If it created a NEW transfer with higher amount on same key — P0
      final led2 = await c.payoutLedger(userId: c.sellerId, limit: 3);
      final row = led2.cast<dynamic>().where((e) {
        return e is Map && e['idempotency_key'] == sameKey;
      }).toList();
      if (row.isNotEmpty && row.first is Map) {
        final amt = (row.first as Map)['amount_cents'];
        if (amt is num && amt > payAmt) {
          c.hold(
            id: 'RTI-I4-002',
            lens: 'I4',
            severity: 'P0',
            title: 'Replay da mesma key debitou amount maior',
            actor: 'seller JWT',
            pre: 'key já usada com $payAmt¢',
            repro: 'POST create-connect-account amount+50 mesma key',
            expected: 'idempotent, amount original',
            obtained: row.first,
          );
        }
      }
    }
  }

  // Crash inject after_debit if secret present
  if (c.e2eSecret.length >= 16) {
    final crashKey = '${prefix}_crash_debit';
    final crash = await c.edge(
      'create-connect-account',
      {
        'amount': 50,
        'idempotency_key': crashKey,
        'crash_inject': 'after_debit_before_stripe',
      },
      jwt: c.sellerJwt,
      extra: crashHdr,
    );
    c.note('p2.i4.crash_debit', 'crash_inject after_debit_before_stripe',
        crash.brief,
        lens: 'I4');
    final retryCrash = await c.edge(
      'create-connect-account',
      {'amount': 50, 'idempotency_key': crashKey},
      jwt: c.sellerJwt,
    );
    c.note('p2.i4.crash_retry', 'retry mesma key após crash', retryCrash.brief,
        lens: 'I4');
  }

  out['wallets_end'] = await c.wallets();
  out['order_end'] = await c.orderRow(oid);
  out['txns_order'] = await c.walletTxns(orderId: oid);
  out['findings'] = c.findings;
  out['notes'] = c.notes;
  await dumpJson('tool/redteam_blind_i_20260831T1706/pass2.json', out);
  stdout.writeln('PASS2 findings=${c.findings.length}');
}
