/// PASS 2 — AX webhook / crash hash / methods / Connect S2. Não corrige.
import 'dart:io';
import '_rtax.dart';

Future<void> main() async {
  final c = Rtax.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final top = await c.ensureMinBalance(c.sellerId, 20);
  c.note('fixture.balance', 'service_role top-up seller ≥20€', top.brief,
      lens: 'AX1');
  final w0 = await c.wallets();
  c.note('p2.snap', 'saldos', w0, lens: 'AX7');

  // ---------------------------------------------------------------------------
  // AX4 — webhook Transfer / refund / payout (tipos que o handler IGNORA
  //        excepto checkout.session.*) + assinatura lixo / replay
  // ---------------------------------------------------------------------------
  for (final type in [
    'transfer.created',
    'transfer.reversed',
    'payout.paid',
    'payout.failed',
    'charge.refunded',
    'charge.dispute.created',
    'account.updated',
    'checkout.session.completed',
  ]) {
    final body = {
      'id': 'evt_ax_$type',
      'object': 'event',
      'type': type,
      'data': {
        'object': {
          'id': 'tr_ax_fake',
          'object': 'transfer',
          'amount': 99999,
          'destination': 'acct_evil',
          'metadata': {'fleaber_user_id': c.buyerId},
          'payment_status': 'paid',
          'metadata_order': c.buyerId,
        },
      },
    };
    final noSig = await c.req(
      'POST',
      '/functions/v1/stripe-webhook',
      body: body,
    );
    final junk = await c.stripeWebhook(body, signature: 't=1,v1=cafebabe');
    c.note('ax4.wh.$type', 'webhook $type', {
      'nosig': noSig.brief,
      'junk': junk.brief,
    }, lens: 'AX4');
    if ((noSig.ok && noSig.map?['ok'] == true && type != 'checkout.session.completed') ||
        (junk.ok && junk.map?['ok'] == true && junk.map?['ignored'] == null &&
            type.startsWith('transfer'))) {
      c.hold(
        id: 'AX4-webhook-$type',
        lens: 'AX4',
        severity: 'P0',
        title: 'Webhook $type aceite sem assinatura válida',
        actor: 'anon POST',
        pre: 'sem whsec',
        repro: 'POST stripe-webhook type=$type',
        expected: '400 missing/invalid_signature',
        obtained: {'nosig': noSig.brief, 'junk': junk.brief},
      );
    } else {
      c.block('AX4.wh-$type', 'AX4', 'webhook $type', {
        'nosig': noSig.status,
        'junk': junk.status,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // AX1 — crash_inject after_stripe + retry mesma key (hash) vs key nova
  // ---------------------------------------------------------------------------
  if (c.e2eSecret.length >= 16) {
    final crashKey = '${prefix}_crashk8';
    final crash = await c.edge(
      'create-connect-account',
      {
        'amount': 100,
        'idempotency_key': crashKey,
        'crash_inject': 'after_stripe_before_finish',
      },
      jwt: c.sellerJwt,
      extra: {'x-fleaber-crash-inject-secret': c.e2eSecret},
    );
    c.note('ax1.crash', 'crash after_stripe', crash.brief, lens: 'AX1');
    final retry = await c.payout(amountCents: 100, key: crashKey);
    c.note('ax1.crash.retry', 'retry mesma key', retry.brief, lens: 'AX1');
    if (crash.transferId != null &&
        retry.transferId != null &&
        crash.transferId != retry.transferId &&
        retry.needsReconcile != true) {
      c.hold(
        id: 'AX1-crash-retry-new-transfer',
        lens: 'AX1',
        severity: 'P0',
        title: 'Retry pós-crash mesma key criou 2.ª Transfer',
        actor: 'seller JWT',
        pre: 'crash_inject after_stripe + mesma raw key (hash)',
        repro: 'POST crash; POST retry',
        expected: 'mesmo tr_ / idempotent',
        obtained: {'crash': crash.brief, 'retry': retry.brief},
      );
    } else {
      c.block('AX1.crash-retry', 'AX1', 'crash retry mesma Transfer', {
        'crash': crash.transferId,
        'retry': retry.transferId,
      });
    }
  } else {
    c.skip('AX1.crash', 'AX1', 'sem crash secret staging', 'skip');
  }

  // Replay mesma key com amount maior (hash: deve idempotente no débito original)
  final growK = '${prefix}_growkey8';
  final g1 = await c.payout(amountCents: 100, key: growK);
  final g2 = await c.payout(amountCents: 500, key: growK);
  c.note('ax1.grow-amount', 'mesma key 100 depois 500', {
    'g1': g1.brief,
    'g2': g2.brief,
    'same': g1.transferId != null && g1.transferId == g2.transferId,
  }, lens: 'AX1');
  if (g2.ok &&
      g2.transferId != null &&
      g1.transferId != null &&
      g2.transferId != g1.transferId) {
    c.hold(
      id: 'AX1-key-reuse-higher-amount',
      lens: 'AX1',
      severity: 'P0',
      title: 'Mesma key com amount 500 criou Transfer nova',
      actor: 'seller JWT',
      pre: 'já debitado 100¢',
      repro: 'POST amount=500 mesma key',
      expected: 'idempotent mesmo tr_ / 400',
      obtained: {'g1': g1.brief, 'g2': g2.brief},
    );
  } else {
    c.block('AX1.grow', 'AX1', 'amount maior idempotente', g2);
  }

  // Methods hostis
  for (final m in ['PUT', 'PATCH', 'DELETE']) {
    final hit = await c.edge(
      'create-connect-account',
      {'amount': 100, 'idempotency_key': '${prefix}_${m}key8'},
      jwt: c.sellerJwt,
      method: m,
    );
    c.note('ax1.method.$m', '$m payout', hit.brief, lens: 'AX1');
    if (hit.ok && hit.transferId != null) {
      c.hold(
        id: 'AX1-method-$m-payout',
        lens: 'AX1',
        severity: 'P2',
        title: '$m create-connect-account criou Transfer',
        actor: 'seller JWT',
        pre: 'method $m',
        repro: '$m functions/v1/create-connect-account',
        expected: '405',
        obtained: hit.brief,
      );
    }
  }

  // Seller2 user_id = seller1 (Connect hijack)
  final hijack = await c.payout(
    amountCents: 100,
    key: '${prefix}_hijack08',
    jwt: c.seller2Jwt,
    userId: c.sellerId,
  );
  c.note('ax2.s2.userid', 'S2 user_id=S1', hijack.brief, lens: 'AX2');
  if (hijack.ok && hijack.transferId != null) {
    c.hold(
      id: 'AX2-s2-userid-s1',
      lens: 'AX2',
      severity: 'P0',
      title: 'Seller2 payout com user_id do seller1',
      actor: 'seller2 JWT',
      pre: 'body user_id=S1',
      repro: 'POST create-connect-account',
      expected: '400 Cannot create another user',
      obtained: hijack.brief,
    );
  } else {
    c.block('AX2.s2-userid', 'AX2', 'user_id cruzado', hijack);
  }

  // PATCH Connect id JWT
  final patchAcct = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.buyerJwt,
    body: {'stripe_account_id': 'acct_1EVEL11111111111'},
  );
  c.note('ax2.patch.acct', 'PATCH stripe_account_id', patchAcct.brief,
      lens: 'AX2');
  final row = await c.walletRow(c.sellerId);
  if (row?['stripe_account_id'] == 'acct_1EVEL11111111111') {
    c.hold(
      id: 'AX2-patch-connect-id',
      lens: 'AX2',
      severity: 'P0',
      title: 'JWT alterou stripe_account_id',
      actor: 'buyer JWT',
      pre: 'PATCH wallets',
      repro: 'PATCH stripe_account_id=acct_evil',
      expected: '200 [] / inalterado',
      obtained: {'hit': patchAcct.brief, 'acct': row?['stripe_account_id']},
    );
  } else {
    c.block('AX2.patch-acct', 'AX2', 'Connect id imutável JWT', patchAcct);
  }

  final w1 = await c.wallets();
  c.note('p2.wallets.end', 'saldos', {
    'w0': w0,
    'w1': w1,
    'dSeller': (w1['seller'] ?? 0) - (w0['seller'] ?? 0),
  }, lens: 'AX7');

  await c.dumpAll('pass2.json');
  stdout.writeln(
      'PASS2 done findings=${c.findings.length} blocked=${c.blocked.length}');
}
