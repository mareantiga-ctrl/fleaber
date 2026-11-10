/// PASS 3 — chave de payout cruzada · crash_inject sem segredo · payout JWT alheio
/// dart run tool/redteam_blind_r_20260901T0700/pass3.dart
import 'dart:io';

import '_rtr.dart';

void main() async {
  final env = loadEnv();
  final c = Rtr.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final shared = '${prefix}-shared-key-xxxxxxxx';

  // Seller2 tenta payout com key já usada pelo seller1 (ledger transferred)
  final stealKey = await c.edge('create-connect-account', {
    'amount': 100,
    'idempotency_key': 'RTR-20260901T0700-full-a-a35dfc25-xx',
  }, jwt: c.seller2Jwt);
  c.note('p3.r6.foreign-key', 'seller2 reutiliza idempotency_key do seller1',
      stealKey.brief,
      lens: 'R6');
  if (stealKey.ok && stealKey.map?['success'] == true) {
    c.hold(
      id: 'RTR-R6-foreign-idempotency',
      lens: 'R6',
      severity: 'P0',
      title: '2.º seller reutilizou idempotency_key e obteve Transfer/saldo alheio',
      actor: 'seller2 JWT',
      pre: 'key já transferred na carteira seller1',
      repro: 'POST create-connect-account idempotency_key=<key seller1>',
      expected: 'idempotency_key_foreign / insufficient',
      obtained: stealKey.brief,
    );
  }

  final newShared = await c.edge('create-connect-account', {
    'amount': 100,
    'idempotency_key': shared,
  }, jwt: c.sellerJwt);
  final s2same = await c.edge('create-connect-account', {
    'amount': 100,
    'idempotency_key': shared,
  }, jwt: c.seller2Jwt);
  c.note('p3.r6.shared-new', 'mesma key seller1 depois seller2', {
    's1': newShared.brief,
    's2': s2same.brief,
  }, lens: 'R6');

  // crash_inject sem secret — não deve debitar/crashar
  final w0 = await c.walletBal(c.sellerId);
  final oid = await c.payAndComplete(lens: 'R6');
  if (oid != null) {
    await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': oid,
    }, jwt: c.buyerJwt);
  }
  final crash = await c.edge(
    'create-connect-account',
    {
      'amount': 100,
      'idempotency_key': '${prefix}-crash-nosecret-xx',
      'crash_inject': 'after_debit_before_stripe',
    },
    jwt: c.sellerJwt,
  );
  final w1 = await c.walletBal(c.sellerId);
  c.note('p3.r6.crash-nosecret', 'crash_inject sem header secret', {
    'http': crash.brief,
    'dSeller': w1 - w0,
    'needs_reconcile': crash.map?['needs_reconcile'],
  }, lens: 'R6');
  if (crash.map?['crash_inject'] == true) {
    c.hold(
      id: 'RTR-R6-crash-inject-open',
      lens: 'R6',
      severity: 'P1',
      title: 'crash_inject de payout aceito sem segredo de staging',
      actor: 'seller JWT',
      pre: 'sem x-fleaber-crash-inject-secret',
      repro: 'POST create-connect-account crash_inject=after_debit_before_stripe',
      expected: 'ignorar inject; fluxo normal',
      obtained: crash.brief,
    );
  }

  final buyerPay = await c.edge('create-connect-account', {
    'amount': 500,
    'idempotency_key': '${prefix}-buyer-pay-xxxxxxxx',
    'user_id': c.sellerId,
  }, jwt: c.buyerJwt);
  c.note('p3.r1.buyer-payout', 'buyer tenta levantar com user_id seller',
      buyerPay.brief,
      lens: 'R1');

  // R1 residual: após payout da venda, refund-order continua bloqueado?
  if (oid != null) {
    final ref = await c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt);
    c.note('p3.r1.refund-after-new-release', 'refund-order pós novo release',
        ref.brief,
        lens: 'R1');
  }

  final out = {
    'pass': 3,
    'wallets': await c.wallets(),
    'notes': c.notes,
    'findings': c.findings,
  };
  await dumpJson('${outDir()}/pass3.json', out);
  stdout.writeln('WROTE pass3.json findings=${c.findings.length}');
}
