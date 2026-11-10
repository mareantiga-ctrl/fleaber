/// PASS 1 — BD payout/wallet/refund pós-ANAS. Variantes novas. Não corrige.
/// dart run tool/redteam_blind_bd_20260902T1608/pass1.dart
import '_rtbd.dart';

bool moneyMoved(HttpHit h) =>
    h.ok &&
    (h.transferId != null ||
        h.map?['success'] == true ||
        h.map?['ok'] == true && h.map?['transferId'] != null);

Future<void> main() async {
  final c = Rtbd.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.walletsSnap();
  c.note('actors', 'login', {
    'buyer': c.buyerId,
    'seller': c.sellerId,
    'buyer2': c.buyer2Id,
    'seller2': c.seller2Id,
    'w0': w0,
  });

  // -------------------------------------------------------------------------
  // BD1 — destination / identidade (não prefixo-64, não Stripe-Account só)
  // -------------------------------------------------------------------------
  final destSteal = await c.payout(
    amount: 100,
    key: '${prefix}-dest-s2',
    jwt: c.sellerJwt,
    userId: c.seller2Id,
  );
  c.note('bd1.user_id.s2', 'payout user_id=seller2', destSteal.brief,
      lens: 'BD1');
  if (moneyMoved(destSteal) && destSteal.map?['error'] == null) {
    c.finding(
      id: 'BD1-userid-other',
      lens: 'BD1',
      severity: 'P0',
      title: 'Payout JWT vendedor A com user_id de B criou Transfer',
      actor: 'seller JWT',
      pre: 'seller1 Connect; body.user_id=seller2',
      repro: 'POST create-connect-account amount=100 user_id=seller2',
      expected: '400/403 sem Transfer',
      obtained: destSteal.brief,
    );
  } else {
    c.block('BD1.user_id.s2', 'BD1', 'user_id alheio recusado', destSteal);
  }

  final s2acct = (await c.walletRow(c.seller2Id))?['stripe_account_id'];
  final s1acct = (await c.walletRow(c.sellerId))?['stripe_account_id'];
  final patchOwnDest = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {
      'stripe_account_id': s2acct ?? 'acct_1BdHijackVictim',
    },
  );
  final afterOwn = await c.walletRow(c.sellerId);
  c.note('bd1.patch.own_dest', 'PATCH stripe_account_id próprio → conta alheia',
      {
        'http': patchOwnDest.brief,
        'before': s1acct,
        'after': afterOwn?['stripe_account_id'],
      },
      lens: 'BD1');
  if (afterOwn?['stripe_account_id'] != s1acct &&
      afterOwn?['stripe_account_id'] == (s2acct ?? 'acct_1BdHijackVictim')) {
    c.finding(
      id: 'BD1-patch-own-dest',
      lens: 'BD1',
      severity: 'P1',
      title: 'JWT actualizou stripe_account_id da própria carteira para destino alheio',
      actor: 'seller JWT',
      pre: 'wallets.stripe_account_id do seller1',
      repro: 'PATCH wallets stripe_account_id=seller2',
      expected: 'RLS sem UPDATE / valor imutável',
      obtained: afterOwn?['stripe_account_id'],
    );
  } else {
    c.block('BD1.patch.own_dest', 'BD1', 'stripe_account_id próprio imutável',
        patchOwnDest);
  }

  final patchOther = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.seller2Id}',
    jwt: c.sellerJwt,
    body: {'stripe_account_id': s1acct},
  );
  final s2after = await c.walletRow(c.seller2Id);
  c.note('bd1.patch.other', 'PATCH wallet seller2 via JWT seller1', {
    'http': patchOther.brief,
    'acct': s2after?['stripe_account_id'],
  }, lens: 'BD1');
  if (s2after?['stripe_account_id'] == s1acct && s1acct != null) {
    c.finding(
      id: 'BD1-patch-other-wallet',
      lens: 'BD1',
      severity: 'P0',
      title: 'JWT vendedor A alterou stripe_account_id da carteira B',
      actor: 'seller JWT',
      pre: 'seller2 wallet',
      repro: 'PATCH wallets?id=eq.seller2',
      expected: '0 rows / RLS',
      obtained: s2after?['stripe_account_id'],
    );
  } else {
    c.block('BD1.patch.other', 'BD1', 'wallet alheia não PATCH', patchOther);
  }

  for (final amt in <Object>[1.5, -5, 0, 1e21, 2147483647]) {
    final h = await c.payout(
      amount: amt,
      key: '${prefix}-amt-${amt.toString().replaceAll(RegExp(r'[^0-9A-Za-z]'), '')}',
    );
    c.note('bd1.amount.$amt', 'payout amount=$amt', h.brief, lens: 'BD1');
    final huge = (amt is num && amt > 100000) || amt == 1e21;
    if (moneyMoved(h) && (huge || (amt is num && amt <= 0) || amt == 1.5)) {
      c.finding(
        id: 'BD1-amount-$amt',
        lens: 'BD1',
        severity: huge ? 'P0' : 'P1',
        title: 'Payout aceitou amount hostil $amt e criou Transfer',
        actor: 'seller JWT',
        pre: 'Connect seller',
        repro: 'POST create-connect-account amount=$amt',
        expected: '400 sem Transfer',
        obtained: h.brief,
      );
    } else {
      c.block('BD1.amount.$amt', 'BD1', 'amount $amt recusado/sem Transfer', h);
    }
  }
  final sci = await c.payout(amount: '1e2', key: '${prefix}-amt-sci');
  c.note('bd1.amount.sci', 'payout amount="1e2" (coerção)', sci.brief, lens: 'BD1');
  c.block('BD1.amount.sci', 'BD1', 'string 1e2 observado (não P0 se=100¢)', sci);

  final destBody = await c.payout(
    amount: 100,
    key: '${prefix}-body-dest',
    extra: {
      'destination': s2acct,
      'stripe_account_id': s2acct,
      'currency': 'usd',
    },
  );
  c.note('bd1.body.dest', 'payout extra destination/currency', destBody.brief,
      lens: 'BD1');
  if (moneyMoved(destBody)) {
    c.finding(
      id: 'BD1-body-destination',
      lens: 'BD1',
      severity: 'P0',
      title: 'Cliente forçou destination/currency no payout',
      actor: 'seller JWT',
      pre: 'extra destination=acct seller2 currency=usd',
      repro: 'POST create-connect-account destination+currency',
      expected: 'ignorar campos; ou 400',
      obtained: destBody.brief,
    );
  } else {
    c.block('BD1.body.dest', 'BD1', 'destination/currency cliente ignorados',
        destBody);
  }

  // -------------------------------------------------------------------------
  // BD2 — ledger REST / mint RPC
  // -------------------------------------------------------------------------
  final insLed = await c.rest('POST', 'wallet_payout_ledger', jwt: c.sellerJwt,
      body: {
        'idempotency_key': '${prefix}-fake-led',
        'user_id': c.sellerId,
        'amount_cents': 99900,
        'amount_eur': 999,
        'status': 'transferred',
        'stripe_transfer_id': 'tr_fake_bd_$stamp',
      });
  c.note('bd2.ledger.insert', 'INSERT ledger JWT', insLed.brief, lens: 'BD2');
  if (insLed.ok && insLed.firstId != null) {
    c.finding(
      id: 'BD2-ledger-insert',
      lens: 'BD2',
      severity: 'P0',
      title: 'JWT inseriu wallet_payout_ledger transferred',
      actor: 'seller JWT',
      pre: 'sem INSERT policy',
      repro: 'POST wallet_payout_ledger status=transferred',
      expected: '401/403 RLS',
      obtained: insLed.brief,
    );
  } else {
    c.block('BD2.ledger.insert', 'BD2', 'INSERT ledger recusado', insLed);
  }

  final patchBal = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {'balance': 8888.88},
  );
  final balAfter = await c.walletBal(c.sellerId);
  c.note('bd2.wallet.patch', 'PATCH wallets.balance', {
    'http': patchBal.brief,
    'before': w0['seller'],
    'after': balAfter,
  }, lens: 'BD2');
  if ((balAfter - (w0['seller'] ?? 0)).abs() > 100) {
    c.finding(
      id: 'BD2-wallet-balance-patch',
      lens: 'BD2',
      severity: 'P0',
      title: 'JWT mintou saldo PATCH wallets.balance',
      actor: 'seller JWT',
      pre: 'saldo ${w0['seller']}',
      repro: 'PATCH wallets balance=8888.88',
      expected: 'sem UPDATE policy',
      obtained: balAfter,
    );
  } else {
    c.block('BD2.wallet.patch', 'BD2', 'balance imutável via JWT', patchBal);
  }

  final insTxn = await c.rest('POST', 'wallet_transactions', jwt: c.sellerJwt,
      body: {
        'wallet_id': c.sellerId,
        'amount': 77.77,
        'type': 'venda',
        'description': '$prefix mint txn',
      });
  c.note('bd2.txn.insert', 'INSERT wallet_transactions', insTxn.brief,
      lens: 'BD2');
  if (insTxn.ok && insTxn.firstId != null) {
    c.finding(
      id: 'BD2-txn-insert',
      lens: 'BD2',
      severity: 'P1',
      title: 'JWT inseriu wallet_transactions',
      actor: 'seller JWT',
      pre: 'só SELECT own',
      repro: 'POST wallet_transactions type=venda 77.77',
      expected: 'RLS deny',
      obtained: insTxn.brief,
    );
  } else {
    c.block('BD2.txn.insert', 'BD2', 'INSERT txn recusado', insTxn);
  }

  final readOtherLed = await c.rest(
    'GET',
    'wallet_payout_ledger?user_id=eq.${c.seller2Id}&select=idempotency_key,amount_cents,status',
    jwt: c.sellerJwt,
  );
  c.note('bd2.ledger.read_other', 'SELECT ledger seller2 via seller1',
      readOtherLed.brief,
      lens: 'BD2');
  if (readOtherLed.ok && readOtherLed.list.isNotEmpty) {
    c.finding(
      id: 'BD2-ledger-cross-read',
      lens: 'BD2',
      severity: 'P2',
      title: 'JWT leu wallet_payout_ledger de outro user',
      actor: 'seller JWT',
      pre: 'ledger seller2',
      repro: 'GET wallet_payout_ledger?user_id=eq.seller2',
      expected: '[]',
      obtained: '${readOtherLed.list.length} rows',
    );
  } else {
    c.block('BD2.ledger.read_other', 'BD2', 'ledger alheio vazio/403',
        readOtherLed);
  }

  final debitJwt = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': c.sellerId,
    'p_amount_cents': 100,
    'p_idempotency_key': '${prefix}-jwt-debit',
  }, jwt: c.sellerJwt);
  c.note('bd2.debit.jwt', 'rpc debit JWT', debitJwt.brief, lens: 'BD2');
  if (!rpcDenied(debitJwt) && debitJwt.ok && debitJwt.map?['ok'] == true) {
    c.finding(
      id: 'BD2-debit-jwt',
      lens: 'BD2',
      severity: 'P0',
      title: 'JWT executou batata_wallet_payout_debit',
      actor: 'seller JWT',
      pre: 'GRANT deveria ser service_role',
      repro: 'POST rpc/batata_wallet_payout_debit',
      expected: '403',
      obtained: debitJwt.brief,
    );
  } else {
    c.block('BD2.debit.jwt', 'BD2', 'debit JWT negado', debitJwt);
  }

  final finishJwt = await c.rpc('batata_wallet_payout_finish', {
    'p_idempotency_key': '${prefix}-jwt-debit',
    'p_stripe_transfer_id': 'tr_fake_finish',
    'p_failed': false,
  }, jwt: c.sellerJwt);
  c.note('bd2.finish.jwt', 'rpc finish JWT', finishJwt.brief, lens: 'BD2');
  if (!rpcDenied(finishJwt) && finishJwt.ok && finishJwt.map?['ok'] == true) {
    c.finding(
      id: 'BD2-finish-jwt',
      lens: 'BD2',
      severity: 'P0',
      title: 'JWT executou batata_wallet_payout_finish',
      actor: 'seller JWT',
      pre: 'GRANT service_role',
      repro: 'POST rpc/batata_wallet_payout_finish',
      expected: '403',
      obtained: finishJwt.brief,
    );
  } else {
    c.block('BD2.finish.jwt', 'BD2', 'finish JWT negado', finishJwt);
  }

  final creditJwt = await c.rpc('batata_credit_wallet_once', {
    'p_wallet_id': c.sellerId,
    'p_order_id': '00000000-0000-0000-0000-000000000001',
    'p_amount': 50.00,
    'p_type': 'venda',
    'p_description': '$prefix mint',
  }, jwt: c.sellerJwt);
  c.note('bd2.credit.jwt', 'rpc credit JWT', creditJwt.brief, lens: 'BD2');
  if (!rpcDenied(creditJwt) &&
      (creditJwt.map == true || creditJwt.body.trim() == 'true')) {
    c.finding(
      id: 'BD2-credit-jwt',
      lens: 'BD2',
      severity: 'P0',
      title: 'JWT mintou via batata_credit_wallet_once',
      actor: 'seller JWT',
      pre: 'GRANT service_role',
      repro: 'POST rpc/batata_credit_wallet_once 50€',
      expected: '403',
      obtained: creditJwt.brief,
    );
  } else {
    c.block('BD2.credit.jwt', 'BD2', 'credit JWT negado', creditJwt);
  }

  final clawJwt = await c.rpc('batata_clawback_seller_wallet_for_order', {
    'p_order_id': '00000000-0000-0000-0000-000000000001',
  }, jwt: c.sellerJwt);
  c.note('bd2.claw.jwt', 'rpc clawback JWT', clawJwt.brief, lens: 'BD2');
  if (!rpcDenied(clawJwt) &&
      (clawJwt.map == true || clawJwt.body.trim() == 'true')) {
    c.finding(
      id: 'BD2-clawback-jwt',
      lens: 'BD2',
      severity: 'P1',
      title: 'JWT executou clawback',
      actor: 'seller JWT',
      pre: 'GRANT service_role',
      repro: 'POST rpc/batata_clawback_seller_wallet_for_order',
      expected: '403',
      obtained: clawJwt.brief,
    );
  } else {
    c.block('BD2.claw.jwt', 'BD2', 'clawback JWT negado', clawJwt);
  }

  final finRef = await c.rpc('batata_finalize_stripe_order_refund', {
    'p_order_id': '00000000-0000-0000-0000-000000000001',
    'p_refund_id': 're_fake_bd',
    'p_amount_cents': 99900,
  }, jwt: c.sellerJwt);
  c.note('bd2.finalize.jwt', 'rpc finalize refund JWT', finRef.brief,
      lens: 'BD2');
  if (!rpcDenied(finRef) && finRef.map?['ok'] == true) {
    c.finding(
      id: 'BD2-finalize-refund-jwt',
      lens: 'BD2',
      severity: 'P0',
      title: 'JWT finalizou refund Stripe forjado',
      actor: 'seller JWT',
      pre: 'GRANT service_role',
      repro: 'POST rpc/batata_finalize_stripe_order_refund',
      expected: '403',
      obtained: finRef.brief,
    );
  } else {
    c.block('BD2.finalize.jwt', 'BD2', 'finalize refund JWT negado', finRef);
  }

  // -------------------------------------------------------------------------
  // BD5 — Connect bind / return origin
  // -------------------------------------------------------------------------
  final origins = <String>[
    'https://evil.com',
    'https://fleaber.pt.evil.com',
    'https://evil.com/fleaber.pt',
    'https://fleaber.pt%00.evil.com',
    'javascript:alert(1)',
    '//evil.com',
    'https://user:pass@fleaber.pt',
    'http://fleaber.pt',
    'https://127.0.0.1.nip.io',
    'https://fleaber.pt.attacker.tld',
  ];
  for (final o in origins) {
    final g = await c.connectGet(
      qs: '?web_return_origin=${Uri.encodeQueryComponent(o)}',
      ua: 'Mozilla/5.0 (Windows NT 10.0; Chrome/120)',
    );
    c.note('bd5.get.$o', 'GET connect origin', '${g.status} loc=${g.location}',
        lens: 'BD5');
    final loc = (g.location ?? '').toLowerCase();
    if (g.status >= 300 &&
        g.status < 400 &&
        loc.isNotEmpty &&
        !loc.contains('fleaber.pt') &&
        !loc.contains('fleaber.app') &&
        !loc.contains('fleaber.com') &&
        !loc.contains('localhost') &&
        !loc.contains('127.0.0.1')) {
      c.finding(
        id: 'BD5-open-redirect-$o',
        lens: 'BD5',
        severity: 'P2',
        title: 'GET create-connect-account redireccionou para origem hostil',
        actor: 'anon',
        pre: 'web_return_origin=$o',
        repro: 'GET create-connect-account?web_return_origin=',
        expected: 'HTML wallet / sem Location hostil',
        obtained: g.location,
      );
    } else {
      c.block('BD5.get.$o', 'BD5', 'origin $o não redireccionou hostil',
          '${g.status} ${g.location}');
    }
  }

  final onbOther = await c.edge('create-connect-account', {
    'user_id': c.seller2Id,
    'web_return_origin': 'https://evil.com',
  }, jwt: c.sellerJwt);
  c.note('bd5.onboard.other', 'onboarding user_id=seller2', onbOther.brief,
      lens: 'BD5');
  if (onbOther.ok && onbOther.map?['url'] != null) {
    c.finding(
      id: 'BD5-onboard-other',
      lens: 'BD5',
      severity: 'P1',
      title: 'Seller A obteve Account Link de B',
      actor: 'seller JWT',
      pre: 'user_id=seller2',
      repro: 'POST create-connect-account user_id=seller2 (sem amount)',
      expected: '400 Cannot create another user',
      obtained: onbOther.brief,
    );
  } else {
    c.block('BD5.onboard.other', 'BD5', 'onboarding alheio recusado', onbOther);
  }

  final crashNoSecret = await c.payout(
    amount: 100,
    key: '${prefix}-crash-nosec',
    extra: {'crash_inject': 'after_debit_before_stripe'},
  );
  c.note('bd6.crash.nosecret', 'crash_inject sem secret', crashNoSecret.brief,
      lens: 'BD6');
  if (crashNoSecret.needsReconcile ||
      '${crashNoSecret.body}'.contains('crash_inject')) {
    c.finding(
      id: 'BD6-crash-no-secret',
      lens: 'BD6',
      severity: 'P2',
      title: 'crash_inject activo sem secret',
      actor: 'seller JWT',
      pre: 'sem header x-fleaber-crash-inject-secret',
      repro: 'POST payout crash_inject=after_debit_before_stripe',
      expected: 'ignorar inject',
      obtained: crashNoSecret.brief,
    );
  } else {
    c.block('BD6.crash.nosecret', 'BD6', 'crash_inject ignorado sem secret',
        crashNoSecret);
  }

  final w1 = await c.walletsSnap();
  c.note('wallets.end.p1', 'saldos após pass1', {'before': w0, 'after': w1});
  await c.dumpAll('pass1.json');
}
