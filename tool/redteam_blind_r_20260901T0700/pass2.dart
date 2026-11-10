/// PASS 2 — R6 saldo inteiro · R3 disputa antes do release · race disputa∥release
/// dart run tool/redteam_blind_r_20260901T0700/pass2.dart
import 'dart:io';

import '_rtr.dart';

void main() async {
  final env = loadEnv();
  final c = Rtr.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  // =====================================================================
  // R6 — dois levantamentos do SALDO INTEIRO em paralelo
  // =====================================================================
  final oidPay = await c.payAndComplete(lens: 'R6');
  if (oidPay == null) {
    stderr.writeln('FAIL payAndComplete R6');
    exit(4);
  }
  final wRel0 = await c.wallets();
  final rel = await c.rpc('batata_release_seller_wallet_for_order', {
    'p_order_id': oidPay,
  }, jwt: c.buyerJwt);
  final wRel1 = await c.wallets();
  final fullCents = ((wRel1['seller'] ?? 0) * 100).round();
  c.note('p2.r6.pre', 'pré-race saldo inteiro', {
    'rel': rel.brief,
    'credited': (wRel1['seller'] ?? 0) - (wRel0['seller'] ?? 0),
    'full_cents': fullCents,
    'oid': oidPay,
  }, lens: 'R6');

  final key1 = '${prefix}-full-a-${oidPay.substring(0, 8)}-xx';
  final key2 = '${prefix}-full-b-${oidPay.substring(0, 8)}-xx';
  final key3 = '${prefix}-full-c-${oidPay.substring(0, 8)}-xx';
  final raced = await parallel([
    c.edge('create-connect-account', {
      'amount': fullCents,
      'idempotency_key': key1,
    }, jwt: c.sellerJwt),
    c.edge('create-connect-account', {
      'amount': fullCents,
      'idempotency_key': key2,
    }, jwt: c.sellerJwt),
    c.edge('create-connect-account', {
      'amount': fullCents,
      'idempotency_key': key3,
    }, jwt: c.sellerJwt),
  ]);
  final wRel2 = await c.wallets();
  final led = await c.payoutLedger(userId: c.sellerId);
  final newLed = led.where((e) {
    if (e is! Map) return false;
    final k = '${e['idempotency_key']}';
    return k.contains(prefix);
  }).toList();
  c.note('p2.r6.full-race', '3× payout amount=saldo_inteiro', {
    'a': raced[0].brief,
    'b': raced[1].brief,
    'c': raced[2].brief,
    'bal_after': wRel2['seller'],
    'ledger_rtr': newLed,
  }, lens: 'R6');

  bool payOk(HttpHit h) =>
      h.ok && h.map?['success'] == true && h.map?['idempotent'] != true;
  final wins = raced.where(payOk).toList();
  final transferIds = wins
      .map((h) => '${h.map?['transferId']}')
      .where((t) => t.startsWith('tr_'))
      .toSet();
  if (transferIds.length > 1) {
    c.hold(
      id: 'RTR-R6-full-double-transfer',
      lens: 'R6',
      severity: 'P0',
      title: 'Três pedidos do saldo inteiro criaram mais do que uma Transfer',
      actor: 'seller JWT Future.wait',
      pre: 'release + amount=balance_cents keys distintas',
      repro: 'Future.wait 3× create-connect-account amount=saldo_inteiro',
      expected: '1 Transfer; as outras insufficient_balance',
      obtained: {
        'a': raced[0].brief,
        'b': raced[1].brief,
        'c': raced[2].brief,
        'transfers': transferIds.toList(),
      },
      evidence: {'ledger': newLed, 'w1': wRel1, 'w2': wRel2},
    );
  }

  final over = await c.edge('create-connect-account', {
    'amount': fullCents + 10000,
    'idempotency_key': '${prefix}-overpay-${oidPay.substring(0, 8)}-xx',
  }, jwt: c.sellerJwt);
  final noKey = await c.edge('create-connect-account', {
    'amount': 100,
  }, jwt: c.sellerJwt);
  final neg = await c.edge('create-connect-account', {
    'amount': -500,
    'idempotency_key': '${prefix}-neg-xxxxxxxx',
  }, jwt: c.sellerJwt);
  c.note('p2.r6.abuse-amount', 'over/sem key/negativo', {
    'over': over.brief,
    'nokey': noKey.brief,
    'neg': neg.brief,
  }, lens: 'R6');

  // =====================================================================
  // R3 — disputa ANTES do release; parcial 40%; tentativa 100%
  // =====================================================================
  final oidD = await c.payAndComplete(lens: 'R3');
  Map<String, dynamic>? r3;
  if (oidD != null) {
    final row0 = await c.orderRow(oidD);
    final disp = await c.insertDispute(oidD);
    final dispB2 = await c.insertDispute(oidD, jwt: c.buyer2Jwt, buyer: c.buyer2Id);
    final offer40 = await c.rest(
      'PATCH',
      'order_disputes?order_id=eq.$oidD',
      jwt: c.sellerJwt,
      body: {
        'seller_offer_type': 'partial_refund',
        'seller_refund_percent': 40,
      },
    );
    final wA = await c.wallets();
    final part40 = await c.rpc('batata_process_partial_refund_dispute', {
      'p_order_id': oidD,
    }, jwt: c.buyerJwt);
    final wB = await c.wallets();
    final relAfter = await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': oidD,
    }, jwt: c.buyerJwt);
    final refAfter = await c.edge('refund-order', {'order_id': oidD}, jwt: c.sellerJwt);
    final books = await c.books(oidD);

    r3 = {
      'pre_release': row0?['wallet_release_processed_at'],
      'disp': disp.brief,
      'dispB2': dispB2.brief,
      'offer40': offer40.brief,
      'part40': part40.brief,
      'dBuyer': (wB['buyer'] ?? 0) - (wA['buyer'] ?? 0),
      'dSeller': (wB['seller'] ?? 0) - (wA['seller'] ?? 0),
      'rel_after': relAfter.brief,
      'refund_after': refAfter.brief,
      'order': books['order'],
      'tx': books['tx'],
    };
    c.note('p2.r3.pre-release', 'disputa+40% antes do release', r3, lens: 'R3');

    if (dispB2.ok) {
      c.hold(
        id: 'RTR-R3-b2-dispute',
        lens: 'R3',
        severity: 'P0',
        title: '2.º comprador abriu disputa na venda alheia',
        actor: 'buyer2 JWT',
        pre: 'order B1 concluida, release null',
        repro: 'POST order_disputes',
        expected: '403',
        obtained: dispB2.brief,
      );
    }

    final dB = (wB['buyer'] ?? 0) - (wA['buyer'] ?? 0);
    final dS = (wB['seller'] ?? 0) - (wA['seller'] ?? 0);
    final capture = numOf((books['order'] as Map?)?['amount_paid_cents']) ?? 0;
    if (dB > 0 && dS > 0 && capture > 0 && (dB + dS) * 100 > capture + 1) {
      c.hold(
        id: 'RTR-R3-split-over-capture',
        lens: 'R3',
        severity: 'P0',
        title: 'Parcial 40% creditou buyer+seller acima da captura Stripe',
        actor: 'buyer RPC parcial',
        pre: 'concluido, release null, oferta 40%',
        repro: 'process_partial_refund_dispute',
        expected: 'buyer+seller ≤ amount_paid',
        obtained: {'dB': dB, 'dS': dS, 'capture_cents': capture},
        evidence: r3,
      );
    }

    // 100% via carteira (nova order)
    final oid100 = await c.payAndComplete(lens: 'R3');
    if (oid100 != null) {
      final d100 = await c.insertDispute(oid100);
      final off100 = await c.rest(
        'PATCH',
        'order_disputes?order_id=eq.$oid100',
        jwt: c.sellerJwt,
        body: {
          'seller_offer_type': 'partial_refund',
          'seller_refund_percent': 100,
        },
      );
      final wC = await c.wallets();
      final part100 = await c.rpc('batata_process_partial_refund_dispute', {
        'p_order_id': oid100,
      }, jwt: c.buyerJwt);
      final wD = await c.wallets();
      c.note('p2.r3.full-wallet', 'oferta 100% via carteira', {
        'disp': d100.brief,
        'offer': off100.brief,
        'part': part100.brief,
        'dBuyer': (wD['buyer'] ?? 0) - (wC['buyer'] ?? 0),
        'dSeller': (wD['seller'] ?? 0) - (wC['seller'] ?? 0),
        'order': await c.orderRow(oid100),
      }, lens: 'R3');
      final minted = (wD['buyer'] ?? 0) - (wC['buyer'] ?? 0);
      if (part100.ok && minted > 0.009) {
        c.hold(
          id: 'RTR-R3-full-via-wallet',
          lens: 'R3',
          severity: 'P0',
          title: 'Disputa 100% plataforma mintou carteira em vez de exigir Stripe',
          actor: 'buyer RPC parcial 100%',
          pre: 'Stripe capturado, oferta 100%',
          repro: 'seller_refund_percent=100 → process_partial',
          expected: 'dispute_full_refund_requires_stripe',
          obtained: part100.brief,
        );
      }
    }
  }

  // =====================================================================
  // R3/R4 — race disputa INSERT ∥ release
  // =====================================================================
  final oidRace = await c.payAndComplete(lens: 'R4');
  if (oidRace != null) {
    final wX = await c.wallets();
    final jobs = await parallel([
      c.insertDispute(oidRace),
      c.rpc('batata_release_seller_wallet_for_order', {
        'p_order_id': oidRace,
      }, jwt: c.buyerJwt),
    ]);
    final wY = await c.wallets();
    final rowR = await c.orderRow(oidRace);
    final dispRow = await c.rest(
      'GET',
      'order_disputes?order_id=eq.$oidRace&select=id,status,seller_refund_percent',
      service: true,
    );
    c.note('p2.r4.disp-rel', 'disputa ∥ release', {
      'disp': jobs[0].brief,
      'rel': jobs[1].brief,
      'dSeller': (wY['seller'] ?? 0) - (wX['seller'] ?? 0),
      'order': rowR,
      'dispute': dispRow.map,
    }, lens: 'R4');

    final released = '${jobs[1].body}'.contains('true') &&
        ((wY['seller'] ?? 0) - (wX['seller'] ?? 0)) > 0.009;
    final disputed = jobs[0].ok && jobs[0].firstId != null;
    if (released && disputed) {
      // Tentar parcial em cima do release
      await c.rest(
        'PATCH',
        'order_disputes?order_id=eq.$oidRace',
        jwt: c.sellerJwt,
        body: {
          'seller_offer_type': 'partial_refund',
          'seller_refund_percent': 40,
        },
      );
      final wP0 = await c.wallets();
      final part = await c.rpc('batata_process_partial_refund_dispute', {
        'p_order_id': oidRace,
      }, jwt: c.buyerJwt);
      final wP1 = await c.wallets();
      c.note('p2.r4.part-after-both', 'parcial após disputa+release', {
        'part': part.brief,
        'dBuyer': (wP1['buyer'] ?? 0) - (wP0['buyer'] ?? 0),
        'dSeller': (wP1['seller'] ?? 0) - (wP0['seller'] ?? 0),
      }, lens: 'R3');
      final dB = (wP1['buyer'] ?? 0) - (wP0['buyer'] ?? 0);
      final dS = (wP1['seller'] ?? 0) - (wP0['seller'] ?? 0);
      if (part.ok && dB > 0.009 && dS >= -0.001) {
        c.hold(
          id: 'RTR-R3-release-and-partial-no-claw',
          lens: 'R3',
          severity: 'P0',
          title: 'Release e parcial no mesmo pedido sem clawback do seller',
          actor: 'buyer disputa∥release depois 40%',
          pre: 'ambos venceram a race',
          repro: 'Future.wait disputa+release → oferta 40% → process_partial',
          expected: 'clawback do crédito venda antes do mint buyer',
          obtained: {
            'part': part.brief,
            'dB': dB,
            'dS': dS,
            'rel': jobs[1].brief,
          },
        );
      }
    }
  }

  // =====================================================================
  // R2 — após payout total, JWT tenta cancelar / mint / refund
  // =====================================================================
  final oidDrain = await c.payAndComplete(lens: 'R2');
  if (oidDrain != null) {
    await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': oidDrain,
    }, jwt: c.buyerJwt);
    final all = ((await c.walletBal(c.sellerId)) * 100).round();
    HttpHit? drained;
    if (all >= 50) {
      drained = await c.edge('create-connect-account', {
        'amount': all,
        'idempotency_key': '${prefix}-postclaw-drain-${oidDrain.substring(0, 8)}-xx',
      }, jwt: c.sellerJwt);
    }
    final wZ = await c.wallets();
    final cancelJwt = await c.rest(
      'PATCH',
      'orders?id=eq.$oidDrain',
      jwt: c.buyerJwt,
      body: {'status': 'cancelado'},
    );
    final ref = await c.edge('refund-order', {'order_id': oidDrain}, jwt: c.sellerJwt);
    final rw = await c.rpc('batata_refund_buyer_wallet_for_order', {
      'p_order_id': oidDrain,
    }, jwt: c.buyerJwt);
    final wZ2 = await c.wallets();
    c.note('p2.r2.post-drain', 'payout total → cancel/refund/mint', {
      'drain': drained?.brief,
      'bal': wZ['seller'],
      'cancel': cancelJwt.brief,
      'refund-order': ref.brief,
      'refund-wallet': rw.brief,
      'dBuyer': (wZ2['buyer'] ?? 0) - (wZ['buyer'] ?? 0),
      'dSeller': (wZ2['seller'] ?? 0) - (wZ['seller'] ?? 0),
      'order': await c.orderRow(oidDrain),
    }, lens: 'R2');
    if (((wZ2['buyer'] ?? 0) - (wZ['buyer'] ?? 0)) > 0.009) {
      c.hold(
        id: 'RTR-R2-mint-after-drain',
        lens: 'R2',
        severity: 'P0',
        title: 'Após levantamento total, buyer recebeu mint de carteira',
        actor: 'buyer JWT cancel/refund-wallet',
        pre: 'release + payout saldo 0',
        repro: 'PATCH cancelado / rpc refund_buyer_wallet',
        expected: 'Δbuyer 0; clawback fail-closed',
        obtained: {
          'dBuyer': (wZ2['buyer'] ?? 0) - (wZ['buyer'] ?? 0),
          'refund-wallet': rw.brief,
          'cancel': cancelJwt.brief,
        },
      );
    }
  }

  // =====================================================================
  // R5 — webhook Stripe sem assinatura / replay payout
  // =====================================================================
  final wh = await c.edge('stripe-webhook', {
    'type': 'payout.paid',
    'data': {
      'object': {
        'id': 'po_rtr_fake',
        'amount': 999999,
        'status': 'paid',
      },
    },
  }, jwt: c.sellerJwt);
  final whAnon = await c.edge('stripe-webhook', {
    'type': 'transfer.created',
    'data': {
      'object': {'id': 'tr_rtr_fake', 'amount': 999999},
    },
  });
  c.note('p2.r5.webhook', 'webhook payout/transfer sem Stripe-Signature', {
    'seller': wh.brief,
    'anon': whAnon.brief,
  }, lens: 'R5');

  final out = {
    'pass': 2,
    'wallets': await c.wallets(),
    'orders': c.createdOrderIds,
    'notes': c.notes,
    'findings': c.findings,
  };
  await dumpJson('${outDir()}/pass2.json', out);
  stdout.writeln('WROTE pass2.json findings=${c.findings.length}');
}
