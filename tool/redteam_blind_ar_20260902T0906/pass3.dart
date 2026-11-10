/// PASS 3 — AR composição Δwallet / Stripe net / residual. Não corrige.
import 'dart:io';
import '_rtar.dart';

Future<void> main() async {
  final c = Rtar.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.wallets();
  c.note('p3.snap', 'saldos', w0, lens: 'AR7');

  // Cross-user GET ledger / wallets
  final led = await c.rest(
    'GET',
    'wallet_payout_ledger?user_id=eq.${c.sellerId}&select=idempotency_key,amount_cents,status,stripe_transfer_id&limit=5',
    jwt: c.buyerJwt,
  );
  c.note('ar7.get.ledger', 'buyer GET ledger seller', {
    'http': led.status,
    'n': led.list.length,
    'brief': led.brief,
  }, lens: 'AR7');
  if (led.ok && led.list.isNotEmpty) {
    c.hold(
      id: 'AR7-buyer-reads-seller-ledger',
      lens: 'AR7',
      severity: 'P2',
      title: 'Buyer leu wallet_payout_ledger do vendedor',
      actor: 'buyer JWT',
      pre: 'ledger seller',
      repro: 'GET wallet_payout_ledger?user_id=eq.seller',
      expected: '200 []',
      obtained: {'n': led.list.length, 'brief': led.brief},
    );
  } else {
    c.block('AR7.ledger-cross', 'AR7', 'GET ledger cruzado', led);
  }

  final wal = await c.rest(
    'GET',
    'wallets?id=eq.${c.sellerId}&select=id,balance,stripe_account_id',
    jwt: c.buyerJwt,
  );
  c.note('ar7.get.wallet', 'buyer GET wallet seller', wal.brief, lens: 'AR7');
  if (wal.ok && wal.map?['stripe_account_id'] != null) {
    c.hold(
      id: 'AR7-buyer-reads-connect-id',
      lens: 'AR7',
      severity: 'P2',
      title: 'Buyer leu stripe_account_id do vendedor',
      actor: 'buyer JWT',
      pre: 'wallets seller',
      repro: 'GET wallets?id=eq.seller',
      expected: '200 []',
      obtained: wal.brief,
    );
  } else {
    c.block('AR7.wallet-cross', 'AR7', 'GET wallet cruzado', wal);
  }

  // Seller2 reusa key do seller1 (AL não chegou: S2 sem IBAN)
  final foreign = await c.payout(
    amountCents: 100,
    key: '${prefix}_s1_shared_k',
    jwt: c.seller2Jwt,
    userId: c.sellerId,
  );
  c.note('ar4.foreign.key', 'seller2 key+user_id seller1', foreign.brief,
      lens: 'AR4');
  if (foreign.ok && foreign.transferId != null) {
    c.hold(
      id: 'AR4-seller2-inherits-transfer',
      lens: 'AR4',
      severity: 'P0',
      title: 'Seller2 obteve Transfer com key/user_id do seller1',
      actor: 'seller2 JWT',
      pre: 'key nova; user_id=S1',
      repro: 'POST create-connect-account',
      expected: '400 user cruzado / Connect próprio / IBAN',
      obtained: foreign.brief,
    );
  } else {
    c.block('AR4.foreign-key', 'AR4', 'S2 não herda Transfer', foreign);
  }

  // Race: hop devolvida ∥ buyer concluido+release
  final paidRace = await c.payToPago(lens: 'AR7', initialQty: 1);
  if (paidRace != null) {
    await c.patchOrder(paidRace.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
    await c.patchOrder(paidRace.oid, {'status': 'entregue'}, jwt: c.buyerJwt);
    await c.insertDispute(paidRace.oid);
    await c.patchOrder(paidRace.oid, {'status': 'pedido_devolucao'},
        jwt: c.buyerJwt);
    await c.patchOrder(paidRace.oid, {'status': 'em_devolucao'},
        jwt: c.sellerJwt);
    await c.patchOrder(paidRace.oid, {'status': 'devolucao_entregue'},
        jwt: c.sellerJwt);

    final wR0 = await c.wallets();
    final raced = await parallel([
      c.patchOrder(paidRace.oid, {'status': 'devolvida'}, jwt: c.sellerJwt),
      c.patchOrder(paidRace.oid, {'status': 'concluido'}, jwt: c.buyerJwt),
    ]);
    final rel = await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': paidRace.oid,
    }, jwt: c.buyerJwt);
    final rowR = await c.orderRow(paidRace.oid);
    final refR = await c.refund(paidRace.oid);
    final wR1 = await c.wallets();
    final listed = paidRace.pi == null
        ? null
        : await c.listStripeRefunds(paidRace.pi!);
    c.note('ar7.race.dev-conc', 'devolvida ∥ concluido + release + refund', {
      'dev': raced[0].brief,
      'conc': raced[1].brief,
      'rel': rel.brief,
      'status': rowR?['status'],
      'released': rowR?['wallet_release_processed_at'],
      'rid': rowR?['stripe_refund_id'],
      'refund': refR.brief,
      'dSeller': (wR1['seller'] ?? 0) - (wR0['seller'] ?? 0),
      'dBuyer': (wR1['buyer'] ?? 0) - (wR0['buyer'] ?? 0),
      'stripe': listed?.brief,
    }, lens: 'AR7');

    final dS = (wR1['seller'] ?? 0) - (wR0['seller'] ?? 0);
    final dB = (wR1['buyer'] ?? 0) - (wR0['buyer'] ?? 0);
    final stripeRefunded =
        (listed?.map?['refund_count'] is num) &&
            (listed!.map!['refund_count'] as num) > 0;
    if (dS > 0.05 && (refundSucceeded(refR) || stripeRefunded)) {
      c.hold(
        id: 'AR7-release-and-stripe-refund',
        lens: 'AR7',
        severity: 'P0',
        title: 'Release seller + refund Stripe no mesmo pedido (race)',
        actor: 'seller hops ∥ buyer concluido',
        pre: 'devolucao_entregue',
        repro: 'PATCH devolvida ∥ PATCH concluido; release; refund-order',
        expected: 'um dos lados; sem Δseller se Stripe reembolsou',
        obtained: {
          'status': rowR?['status'],
          'dSeller': dS,
          'dBuyer': dB,
          'refund': refR.brief,
          'rel': rel.brief,
        },
      );
    } else {
      c.block('AR7.race-dev-conc', 'AR7', 'race sem líquido duplo', {
        'status': rowR?['status'],
        'dSeller': dS,
        'dBuyer': dB,
        'refund': refR.brief,
      });
    }
  }

  // Finalize JWT com re_ inventado em order real
  final paidFin = await c.payToPago(lens: 'AR6');
  if (paidFin != null) {
    final fin = await c.rpc('batata_finalize_stripe_order_refund', {
      'p_order_id': paidFin.oid,
      'p_refund_id': 're_AR_forged',
      'p_amount_cents': 590,
    }, jwt: c.sellerJwt);
    final rowF = await c.orderRow(paidFin.oid);
    c.note('ar6.finalize.forged', 'finalize JWT re_ forjado', {
      'rpc': fin.brief,
      'status': rowF?['status'],
      'rid': rowF?['stripe_refund_id'],
    }, lens: 'AR6');
    if (rowF?['stripe_refund_id'] == 're_AR_forged' ||
        rowF?['status'] == 'cancelado') {
      c.hold(
        id: 'AR6-finalize-forged-refund',
        lens: 'AR6',
        severity: 'P0',
        title: 'JWT finalize selou refund inventado e cancelou',
        actor: 'seller JWT',
        pre: 'pago',
        repro: 'rpc batata_finalize_stripe_order_refund p_refund_id=re_AR_forged',
        expected: '403',
        obtained: {'rpc': fin.brief, 'row': rowF},
      );
    } else {
      c.block('AR6.finalize-forged', 'AR6', 'finalize forjado', fin);
    }
  }

  final wEnd = await c.wallets();
  c.note('p3.end', 'saldos finais pass3', {
    'start': w0,
    'end': wEnd,
    'dBuyer': (wEnd['buyer'] ?? 0) - (w0['buyer'] ?? 0),
    'dSeller': (wEnd['seller'] ?? 0) - (w0['seller'] ?? 0),
  }, lens: 'AR7');

  final orphan = await c.rest(
    'GET',
    'wallet_payout_ledger?status=eq.debited&user_id=eq.${c.sellerId}&select=idempotency_key,amount_cents,status,stripe_transfer_id&limit=10',
    service: true,
  );
  c.note('ar4.orphan.debited', 'ledger debited órfão seller', {
    'n': orphan.list.length,
    'rows': orphan.list,
  }, lens: 'AR4');

  await c.dumpAll('pass3.json');
  stdout.writeln(
      'PASS3 done findings=${c.findings.length} blocked=${c.blocked.length}');
  exit(0);
}
