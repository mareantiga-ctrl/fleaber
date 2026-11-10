/// PASS 1 — AL payout/wallet/refund pós-AEAFAG. Não corrige. Staging only.
import 'dart:io';
import '_rtal.dart';

bool rpcOk(HttpHit h) =>
    h.ok &&
    h.body.trim() != 'false' &&
    !h.body.contains('"ok":false') &&
    !h.body.contains('"ok": false');

bool rpcDenied(HttpHit h) =>
    h.status == 401 ||
    h.status == 403 ||
    h.body.contains('42501') ||
    h.body.toLowerCase().contains('permission denied') ||
    h.body.toLowerCase().contains('not allowed');

Future<void> main() async {
  final c = Rtal.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final w0 = await c.wallets();
  final sellerWallet0 = await c.walletRow(c.sellerId);
  c.note('snap.wallets', 'saldos iniciais', w0, lens: 'AL7');
  c.note('snap.seller.acct', 'Connect seller',
      sellerWallet0?['stripe_account_id'], lens: 'AL2');

  final ledger0 = await c.payoutLedger(userId: c.sellerId, limit: 8);
  c.note('snap.ledger', 'payout ledger seller', ledger0, lens: 'AL4');

  // ---------------------------------------------------------------------------
  // AL1 — JWT nas RPCs de payout / Transfer / refund finalize
  // ---------------------------------------------------------------------------
  final moneyRpcs = <String, Map<String, Object?>>{
    'batata_wallet_payout_debit': {
      'p_user_id': c.sellerId,
      'p_amount_cents': 100,
      'p_idempotency_key': '${prefix}_jwt_debit',
    },
    'batata_wallet_payout_finish': {
      'p_idempotency_key': '${prefix}_jwt_debit',
      'p_stripe_transfer_id': 'tr_fake_al',
      'p_failed': false,
    },
    'batata_clawback_seller_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_credit_wallet_once': {
      'p_wallet_id': c.buyerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 9.99,
      'p_type': 'reembolso',
      'p_description': prefix,
    },
    'batata_refund_buyer_wallet_for_order': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
    },
    'batata_finalize_stripe_order_refund': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_refund_id': 're_fake_al',
      'p_payment_intent_id': 'pi_fake',
      'p_session_id': 'cs_fake',
      'p_amount_cents': 99999,
    },
    'batata_process_partial_refund_dispute': {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_refund_percent': 200,
    },
    'batata_ensure_wallet': {'p_user_id': c.sellerId},
  };

  for (final e in moneyRpcs.entries) {
    final buyerHit = await c.rpc(e.key, e.value, jwt: c.buyerJwt);
    final sellerHit = await c.rpc(e.key, e.value, jwt: c.sellerJwt);
    final anonHit = await c.rpc(e.key, e.value);
    c.note('rpc.${e.key}', 'JWT sweep', {
      'buyer': buyerHit.brief,
      'seller': sellerHit.brief,
      'anon': anonHit.brief,
    }, lens: 'AL1');
    if (e.key == 'batata_ensure_wallet') {
      // buyer a garantir carteira do seller — só hold se criar/alterar saldo alheio
      continue;
    }
    for (final hit in [buyerHit, sellerHit]) {
      if (rpcOk(hit) && !rpcDenied(hit)) {
        c.hold(
          id: 'AL1-${e.key}',
          lens: 'AL1',
          severity: 'P0',
          title: 'JWT autenticado executou ${e.key}',
          actor: 'JWT buyer/seller',
          pre: 'RPC SECURITY DEFINER de saída de dinheiro',
          repro: 'POST rpc/${e.key}',
          expected: '401/403 permission denied',
          obtained: hit.brief,
        );
      }
    }
  }

  // buyer ensure_wallet do seller — saldo seller não pode mudar
  final balEnsure = await c.walletBal(c.sellerId);
  if ((balEnsure - (w0['seller'] ?? 0)).abs() > 0.001) {
    c.hold(
      id: 'AL1-ensure-wallet-cross',
      lens: 'AL1',
      severity: 'P0',
      title: 'ensure_wallet JWT alterou saldo alheio',
      actor: 'buyer JWT',
      pre: 'p_user_id=seller',
      repro: 'rpc batata_ensure_wallet',
      expected: w0['seller'],
      obtained: balEnsure,
    );
  } else {
    c.block('AL1-ensure', 'AL1', 'ensure_wallet cross-user sem Δsaldo',
        balEnsure);
  }

  // debit JWT com p_user_id = self (seller tenta debitar a própria carteira)
  final debitSelf = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': c.sellerId,
    'p_amount_cents': 100,
    'p_idempotency_key': '${prefix}_self_debit',
  }, jwt: c.sellerJwt);
  if (rpcOk(debitSelf) && !rpcDenied(debitSelf)) {
    c.hold(
      id: 'AL1-debit-self-jwt',
      lens: 'AL1',
      severity: 'P0',
      title: 'Seller JWT debitou a própria carteira via RPC',
      actor: 'seller JWT',
      pre: 'p_user_id=self',
      repro: 'POST rpc/batata_wallet_payout_debit',
      expected: '403',
      obtained: debitSelf.brief,
    );
  } else {
    c.block('AL1-debit-self', 'AL1', 'debit JWT self recusado', debitSelf);
  }

  // ---------------------------------------------------------------------------
  // REST — wallets / ledger / txns
  // ---------------------------------------------------------------------------
  final patchBal = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {'balance': 9999.99},
  );
  final balAfterPatch = await c.walletBal(c.sellerId);
  c.note('rest.patch.balance', 'PATCH wallets.balance', {
    'hit': patchBal.brief,
    'bal': balAfterPatch,
  }, lens: 'AL1');
  if ((balAfterPatch - (w0['seller'] ?? 0)).abs() > 0.05) {
    c.hold(
      id: 'AL1-patch-balance',
      lens: 'AL1',
      severity: 'P0',
      title: 'JWT PATCH wallets.balance alterou saldo',
      actor: 'seller JWT',
      pre: 'RLS wallets',
      repro: 'PATCH wallets balance=9999.99',
      expected: w0['seller'],
      obtained: balAfterPatch,
    );
  } else {
    c.block('AL1-patch-bal', 'AL1', 'PATCH balance sem efeito', patchBal);
  }

  final buyerAcct = (await c.walletRow(c.buyerId))?['stripe_account_id'];
  final patchAcct = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {'stripe_account_id': buyerAcct ?? 'acct_hijack_al'},
  );
  final acctAfter = (await c.walletRow(c.sellerId))?['stripe_account_id'];
  c.note('rest.patch.acct', 'PATCH stripe_account_id', {
    'hit': patchAcct.brief,
    'acct': acctAfter,
  }, lens: 'AL2');
  if (acctAfter != sellerWallet0?['stripe_account_id'] &&
      acctAfter == (buyerAcct ?? 'acct_hijack_al')) {
    c.hold(
      id: 'AL2-patch-connect',
      lens: 'AL2',
      severity: 'P1',
      title: 'JWT PATCH stripe_account_id para conta alheia',
      actor: 'seller JWT',
      pre: 'Connect gravado na carteira',
      repro: 'PATCH wallets.stripe_account_id',
      expected: sellerWallet0?['stripe_account_id'],
      obtained: acctAfter,
    );
  } else {
    c.block('AL2-patch-acct', 'AL2', 'PATCH Connect id sem efeito', patchAcct);
  }

  final insTxn = await c.rest('POST', 'wallet_transactions', jwt: c.sellerJwt, body: {
    'wallet_id': c.sellerId,
    'amount': 50,
    'type': 'venda',
    'description': prefix,
  });
  final insLed = await c.rest('POST', 'wallet_payout_ledger', jwt: c.sellerJwt, body: {
    'idempotency_key': '${prefix}_led',
    'user_id': c.sellerId,
    'amount_cents': 100,
    'amount_eur': 1,
    'status': 'transferred',
  });
  c.note('rest.insert.txn', 'INSERT wallet_transactions', insTxn.brief, lens: 'AL1');
  c.note('rest.insert.led', 'INSERT wallet_payout_ledger', insLed.brief, lens: 'AL1');
  if (insTxn.ok && insTxn.firstId != null) {
    c.hold(
      id: 'AL1-insert-txn',
      lens: 'AL1',
      severity: 'P1',
      title: 'JWT inseriu wallet_transactions',
      actor: 'seller JWT',
      pre: 'RLS txns',
      repro: 'POST wallet_transactions',
      expected: '403',
      obtained: insTxn.brief,
    );
  } else {
    c.block('AL1-ins-txn', 'AL1', 'INSERT txn recusado', insTxn);
  }
  if (insLed.ok && insLed.map != null) {
    c.hold(
      id: 'AL1-insert-ledger',
      lens: 'AL1',
      severity: 'P1',
      title: 'JWT inseriu wallet_payout_ledger',
      actor: 'seller JWT',
      pre: 'RLS ledger',
      repro: 'POST wallet_payout_ledger',
      expected: '403',
      obtained: insLed.brief,
    );
  } else {
    c.block('AL1-ins-led', 'AL1', 'INSERT ledger recusado', insLed);
  }

  // ---------------------------------------------------------------------------
  // AL2 — Connect return_url / onboarding hijack
  // ---------------------------------------------------------------------------
  final origins = <String>[
    'https://evil.com',
    'https://fleaber.pt.evil.com',
    'https://evil.com/fleaber.pt',
    'https://fleaber.pt%2e%2eevil.com',
    'javascript:alert(1)',
    'https://fleaber.pt.attacker.tld',
    'http://127.0.0.1',
    'http://localhost',
    'https://localhost',
    'https://fleaber.pt',
    'https://www.fleaber.pt',
    'https://user:pass@fleaber.pt',
    'https://fleaber.pt/wallet?next=https://evil.com',
    '//evil.com',
    'https://fleaber.pt./wallet',
  ];
  for (final o in origins) {
    final g = await c.connectGet(
      qs: '?web_return_origin=${Uri.encodeQueryComponent(o)}',
    );
    final loc = g.location ?? '';
    c.note('al2.get', 'GET Connect origin', {
      'origin': o,
      'status': g.status,
      'location': loc,
    }, lens: 'AL2');
    final hostil = loc.contains('evil') ||
        loc.startsWith('javascript:') ||
        loc.contains('attacker');
    if (hostil) {
      c.hold(
        id: 'AL2-open-redirect',
        lens: 'AL2',
        severity: 'P1',
        title: 'GET Connect redirecciona para origem hostil',
        actor: 'anon GET',
        pre: 'web_return_origin=$o',
        repro: 'GET create-connect-account?web_return_origin=',
        expected: 'sem Location hostil',
        obtained: '${g.status} $loc',
      );
    }
  }

  final onboardBuyer = await c.edge('create-connect-account', {
    'user_id': c.sellerId,
    'web_return_origin': 'https://evil.com',
  }, jwt: c.buyerJwt);
  c.note('al2.onboard.cross', 'buyer cria Connect do seller',
      onboardBuyer.brief, lens: 'AL2');
  if (onboardBuyer.ok &&
      (onboardBuyer.map?['url'] != null ||
          onboardBuyer.map?['stripeAccountId'] != null)) {
    c.hold(
      id: 'AL2-onboard-cross-user',
      lens: 'AL2',
      severity: 'P0',
      title: 'Buyer JWT criou/ligou Connect do vendedor',
      actor: 'buyer JWT',
      pre: 'user_id=seller',
      repro: 'POST create-connect-account user_id=seller',
      expected: '400 Cannot create another user',
      obtained: onboardBuyer.brief,
    );
  } else {
    c.block('AL2-onboard-cross', 'AL2', 'onboard cross-user recusado',
        onboardBuyer);
  }

  final onboardDest = await c.payout(
    amountCents: 100,
    key: '${prefix}_dest_hijack',
    extra: {
      'destination': 'acct_1HijackAl',
      'stripe_account_id': 'acct_1HijackAl',
      'return_url': 'https://evil.com/wallet',
      'refresh_url': 'https://evil.com/wallet',
    },
  );
  c.note('al2.payout.dest', 'payout com destination hostil',
      onboardDest.brief, lens: 'AL2');

  // ---------------------------------------------------------------------------
  // AL4 — webhook Transfer / payout sem assinatura
  // ---------------------------------------------------------------------------
  for (final ev in [
    'transfer.created',
    'payout.paid',
    'charge.refunded',
    'account.updated',
  ]) {
    final wh = await c.edge('stripe-webhook', {
      'type': ev,
      'data': {
        'object': {
          'id': 'tr_fake_al',
          'amount': 99999,
          'destination': sellerWallet0?['stripe_account_id'],
          'metadata': {'fleaber_user_id': c.buyerId},
        }
      },
    });
    c.note('al4.webhook', 'unsigned $ev', wh.brief, lens: 'AL4');
    if (wh.ok) {
      c.hold(
        id: 'AL4-webhook-unsigned-$ev',
        lens: 'AL4',
        severity: 'P0',
        title: 'Webhook $ev aceite sem assinatura',
        actor: 'anon',
        pre: 'sem Stripe-Signature',
        repro: 'POST stripe-webhook type=$ev',
        expected: '400 missing_signature',
        obtained: wh.brief,
      );
    } else {
      c.block('AL4-wh-$ev', 'AL4', 'unsigned $ev recusado', wh);
    }
  }

  // ---------------------------------------------------------------------------
  // Fluxo Stripe TEST pago #1 — refund hostil (AL5/AL6) em `pago`
  // ---------------------------------------------------------------------------
  final paid1 = await c.payToPago(lens: 'AL6');
  if (paid1 == null) {
    c.skip('AL6-paid1', 'AL6', 'setup_paid_order falhou', '');
  } else {
    final oid1 = paid1.oid;
    final row1 = await c.orderRow(oid1);
    c.note('paid1.row', 'order pago', row1, lens: 'AL6');

    final finJwt = await c.rpc('batata_finalize_stripe_order_refund', {
      'p_order_id': oid1,
      'p_refund_id': 're_stolen_al_no_stripe',
      'p_payment_intent_id': paid1.pi,
      'p_amount_cents': 99999,
    }, jwt: c.buyerJwt);
    c.note('al6.finalize.jwt', 'finalize fake refund JWT', finJwt.brief,
        lens: 'AL6');
    if (rpcOk(finJwt) && !rpcDenied(finJwt)) {
      final afterFin = await c.orderRow(oid1);
      c.hold(
        id: 'AL6-finalize-fake-refund',
        lens: 'AL6',
        severity: 'P0',
        title: 'JWT finalize_stripe_order_refund com refund inventado',
        actor: 'buyer JWT',
        pre: 'order pago PI real',
        repro: 'rpc batata_finalize_stripe_order_refund p_refund_id=re_stolen',
        expected: '403',
        obtained: {
          'rpc': finJwt.brief,
          'status': afterFin?['status'],
          'refund': afterFin?['stripe_refund_id'],
        },
      );
    } else {
      c.block('AL6-finalize-jwt', 'AL6', 'finalize JWT recusado', finJwt);
    }

    final refBuyer = await c.refund(oid1, jwt: c.buyerJwt);
    final refB2 = await c.refund(oid1, jwt: c.buyer2Jwt);
    final refAmt = await c.refund(oid1, extra: {
      'amount': 99999,
      'amount_cents': 99999,
    });
    c.note('al6.refund.buyer', 'buyer refund-order alheio', refBuyer.brief,
        lens: 'AL6');
    c.note('al6.refund.b2', 'buyer2 refund-order', refB2.brief, lens: 'AL6');
    c.note('al6.refund.amt', 'seller refund amount extra', refAmt.brief,
        lens: 'AL6');

    if (refBuyer.ok && refBuyer.map?['ok'] == true) {
      c.hold(
        id: 'AL6-buyer-refund-foreign',
        lens: 'AL6',
        severity: 'P0',
        title: 'Buyer forçou refund-order de venda alheia',
        actor: 'buyer JWT',
        pre: 'order pago seller=V',
        repro: 'POST refund-order',
        expected: '403 Sem permissão',
        obtained: refBuyer.brief,
      );
    } else {
      c.block('AL6-buyer-ref', 'AL6', 'buyer refund recusado', refBuyer);
    }
    if (refB2.ok && refB2.map?['ok'] == true) {
      c.hold(
        id: 'AL6-b2-refund-foreign',
        lens: 'AL6',
        severity: 'P0',
        title: '2.º comprador reembolsou encomenda alheia',
        actor: 'buyer2 JWT',
        pre: 'order de B1',
        repro: 'POST refund-order',
        expected: '403',
        obtained: refB2.brief,
      );
    } else {
      c.block('AL6-b2-ref', 'AL6', 'buyer2 refund recusado', refB2);
    }

    // refund extra amount — se Stripe refund > captura
    if (refAmt.ok && refAmt.map?['ok'] == true) {
      final amt = numOf(refAmt.map?['amount_cents']);
      final paidCents = numOf(row1?['amount_paid_cents']) ?? 590;
      if (amt != null && amt > paidCents) {
        c.hold(
          id: 'AL6-refund-gt-capture',
          lens: 'AL6',
          severity: 'P0',
          title: 'refund-order aceitou amount > captura',
          actor: 'seller JWT',
          pre: 'body.amount=99999',
          repro: 'POST refund-order amount extra',
          expected: 'reembolso ≤ amount_paid_cents',
          obtained: refAmt.brief,
        );
      } else {
        c.note('al6.refund.amt.ok', 'amount extra ignorado; refund ≤ captura',
            {'amt': amt, 'paid': paidCents}, lens: 'AL6');
      }
    }

    final patchRefundId = await c.rest(
      'PATCH',
      'orders?id=eq.$oid1',
      jwt: c.sellerJwt,
      body: {'stripe_refund_id': 're_forged_al'},
    );
    final rowAfterPatch = await c.orderRow(oid1);
    c.note('al6.patch.refundid', 'PATCH stripe_refund_id', {
      'hit': patchRefundId.brief,
      'id': rowAfterPatch?['stripe_refund_id'],
    }, lens: 'AL6');
    if (rowAfterPatch?['stripe_refund_id'] == 're_forged_al') {
      c.hold(
        id: 'AL6-patch-refund-id',
        lens: 'AL6',
        severity: 'P0',
        title: 'JWT gravou stripe_refund_id forjado',
        actor: 'seller JWT',
        pre: 'order pago',
        repro: 'PATCH orders.stripe_refund_id',
        expected: 'coluna congelada',
        obtained: rowAfterPatch?['stripe_refund_id'],
      );
    } else {
      c.block('AL6-patch-rf', 'AL6', 'PATCH refund id sem efeito',
          patchRefundId);
    }
  }

  // ---------------------------------------------------------------------------
  // Fluxo Stripe TEST pago #2 — release + payout + refund composição
  // ---------------------------------------------------------------------------
  final wBeforeSale = await c.wallets();
  final paid2 = await c.payToPago(lens: 'AL3');
  if (paid2 == null) {
    c.skip('AL3-paid2', 'AL3', 'setup_paid_order #2 falhou', '');
  } else {
    final oid2 = paid2.oid;
    final released = await c.buyerConcludeAndRelease(oid2, lens: 'AL3');
    final wAfterRel = await c.wallets();
    final dSellerRel =
        (wAfterRel['seller'] ?? 0) - (wBeforeSale['seller'] ?? 0);
    final dBuyerRel = (wAfterRel['buyer'] ?? 0) - (wBeforeSale['buyer'] ?? 0);
    c.note('al3.release.delta', 'Δwallet pós-release', {
      'released': released,
      'dSeller': dSellerRel,
      'dBuyer': dBuyerRel,
      'w': wAfterRel,
    }, lens: 'AL3');

    final rel2 = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oid2},
      jwt: c.buyerJwt,
    );
    final relB2 = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oid2},
      jwt: c.buyer2Jwt,
    );
    c.note('al3.release.replay', '2.º release buyer', rel2.brief, lens: 'AL3');
    c.note('al3.release.b2', 'release buyer2', relB2.brief, lens: 'AL3');
    final wAfterRel2 = await c.wallets();
    if (((wAfterRel2['seller'] ?? 0) - (wAfterRel['seller'] ?? 0)) > 0.05) {
      c.hold(
        id: 'AL3-double-release',
        lens: 'AL3',
        severity: 'P0',
        title: 'Segundo release creditou o vendedor outra vez',
        actor: 'buyer/buyer2 JWT',
        pre: 'já libertado',
        repro: 'rpc batata_release_seller_wallet_for_order ×2',
        expected: 'false / Δ0',
        obtained: {
          'rel2': rel2.brief,
          'relB2': relB2.brief,
          'dSeller':
              (wAfterRel2['seller'] ?? 0) - (wAfterRel['seller'] ?? 0),
        },
      );
    } else {
      c.block('AL3-dbl-rel', 'AL3', '2.º release sem crédito extra', rel2);
    }

    final dispAfterRel = await c.insertDispute(oid2);
    c.note('al3.dispute.after-rel', 'disputa pós-release',
        dispAfterRel.brief, lens: 'AL3');

    final refAfterRel = await c.refund(oid2);
    c.note('al5.refund.after-rel', 'seller refund-order pós-release',
        refAfterRel.brief, lens: 'AL5');

    final patchDev = await c.rest(
      'PATCH',
      'orders?id=eq.$oid2',
      jwt: c.sellerJwt,
      body: {'status': 'devolvida'},
    );
    final patchCan = await c.rest(
      'PATCH',
      'orders?id=eq.$oid2',
      jwt: c.buyerJwt,
      body: {'status': 'cancelado'},
    );
    c.note('al5.patch.devolvida', 'seller PATCH devolvida', patchDev.brief,
        lens: 'AL5');
    c.note('al5.patch.cancel', 'buyer PATCH cancelado', patchCan.brief,
        lens: 'AL5');
    final rowDev = await c.orderRow(oid2);
    if (rowDev?['status'] == 'devolvida' || rowDev?['status'] == 'cancelado') {
      final wMint = await c.wallets();
      final dB = (wMint['buyer'] ?? 0) - (wAfterRel2['buyer'] ?? 0);
      if (dB > 0.05 && rowDev?['stripe_refund_id'] == null) {
        c.hold(
          id: 'AL5-devolvida-mint-no-stripe',
          lens: 'AL5',
          severity: 'P0',
          title: 'devolvida/cancelado mintou buyer sem refund Stripe',
          actor: 'JWT PATCH',
          pre: 'pós-release',
          repro: 'PATCH status devolvida/cancelado',
          expected: 'status imutável ou clawback+Stripe refund',
          obtained: {
            'status': rowDev?['status'],
            'dBuyer': dB,
            'refund': rowDev?['stripe_refund_id'],
          },
        );
      }
    } else {
      c.block('AL5-patch-dev', 'AL5', 'PATCH devolvida/cancelado bloqueado',
          {'dev': patchDev.brief, 'can': patchCan.brief});
    }

    // Payout 100¢ — NÃO drenar saldo inteiro
    final keyA = '${prefix}_wd_100a';
    final keyB = '${prefix}_wd_100b';
    final payA = await c.payout(amountCents: 100, key: keyA);
    c.note('al4.payout.100', 'payout 100¢ key A', payA.brief, lens: 'AL4');

    // mesma key, amount diferente (não é replay clássico do mesmo montante)
    final payA2 = await c.payout(amountCents: 500, key: keyA);
    c.note('al4.payout.samekey.diffamt', 'mesma key amount 500', payA2.brief,
        lens: 'AL4');

    final wAfterPayA = await c.wallets();
    final ledA = await c.payoutLedger(userId: c.sellerId, limit: 5);

    if (payA.ok && payA.map?['success'] == true) {
      final tidA = payA.transferId;
      final tidA2 = payA2.transferId;
      if (payA2.ok &&
          payA2.map?['success'] == true &&
          tidA2 != null &&
          tidA != null &&
          tidA2 != tidA) {
        c.hold(
          id: 'AL4-samekey-diff-amount-second-transfer',
          lens: 'AL4',
          severity: 'P0',
          title: 'Mesma idempotency_key com amount maior criou 2.ª Transfer',
          actor: 'seller JWT Edge',
          pre: 'já transferred 100¢',
          repro: 'POST create-connect-account mesma key amount=500',
          expected: 'idempotent mesmo transferId / recusa',
          obtained: {'t1': tidA, 't2': tidA2, 'a2': payA2.brief},
        );
      } else {
        c.block('AL4-samekey-diffamt', 'AL4',
            'mesma key amount≠ não criou 2.ª Transfer', payA2);
      }
    } else {
      c.note('al4.payout.skip', 'payout 100¢ não saiu (Connect/saldo)',
          payA.brief, lens: 'AL4');
    }

    // 2 keys em paralelo sobre 100¢ cada — só hold se Δwallet < -(transfers)
    final par = await parallel([
      c.payout(amountCents: 100, key: '${prefix}_par1'),
      c.payout(amountCents: 100, key: '${prefix}_par2'),
    ]);
    c.note('al4.payout.par', '2 keys // 100¢',
        {'a': par[0].brief, 'b': par[1].brief}, lens: 'AL4');

    final payNeg = await c.payout(amountCents: -100, key: '${prefix}_neg');
    final payZero = await c.edge('create-connect-account', {
      'amount': 0,
      'idempotency_key': '${prefix}_zero',
    }, jwt: c.sellerJwt);
    final payStr = await c.edge('create-connect-account', {
      'amount': '100',
      'idempotency_key': '${prefix}_str100',
    }, jwt: c.sellerJwt);
    final payEur = await c.edge('create-connect-account', {
      'amount': 5.90,
      'idempotency_key': '${prefix}_eur590',
    }, jwt: c.sellerJwt);
    final payCrash = await c.edge('create-connect-account', {
      'amount': 100,
      'idempotency_key': '${prefix}_crash',
      'crash_inject': 'after_debit_before_stripe',
    }, jwt: c.sellerJwt);
    c.note('al1.payout.neg', 'amount -100', payNeg.brief, lens: 'AL1');
    c.note('al1.payout.zero', 'amount 0', payZero.brief, lens: 'AL1');
    c.note('al1.payout.str', 'amount string 100', payStr.brief, lens: 'AL1');
    c.note('al1.payout.eur', 'amount 5.90 (não inteiro)', payEur.brief,
        lens: 'AL1');
    c.note('al1.payout.crash', 'crash_inject sem secret', payCrash.brief,
        lens: 'AL1');

    if (payNeg.ok && payNeg.map?['success'] == true) {
      c.hold(
        id: 'AL1-payout-negative',
        lens: 'AL1',
        severity: 'P0',
        title: 'Payout com amount negativo',
        actor: 'seller JWT',
        pre: 'amount=-100',
        repro: 'POST create-connect-account',
        expected: '400 inválido',
        obtained: payNeg.brief,
      );
    } else {
      c.block('AL1-neg', 'AL1', 'amount negativo recusado', payNeg);
    }
    if (payEur.ok && payEur.map?['success'] == true) {
      c.hold(
        id: 'AL1-payout-non-integer',
        lens: 'AL1',
        severity: 'P1',
        title: 'Payout aceitou amount não inteiro (5.90)',
        actor: 'seller JWT',
        pre: 'API em cêntimos',
        repro: 'POST amount=5.90',
        expected: '400 cêntimos inteiros',
        obtained: payEur.brief,
      );
    } else {
      c.block('AL1-eur', 'AL1', 'amount 5.90 recusado', payEur);
    }
    if (payCrash.needsReconcile || payCrash.map?['crash_inject'] == true) {
      c.hold(
        id: 'AL1-crash-inject-no-secret',
        lens: 'AL1',
        severity: 'P2',
        title: 'crash_inject armou sem secret de staging',
        actor: 'seller JWT',
        pre: 'sem x-fleaber-crash-inject-secret',
        repro: 'body.crash_inject=after_debit_before_stripe',
        expected: 'ignorado; payout normal ou recusa',
        obtained: payCrash.brief,
      );
    } else {
      c.block('AL1-crash', 'AL1', 'crash_inject sem secret ignorado',
          payCrash);
    }

    // seller2 reutiliza key do seller1
    if (payA.ok && payA.transferId != null) {
      final s2steal = await c.payout(
        amountCents: 100,
        key: keyA,
        jwt: c.seller2Jwt,
        userId: c.seller2Id,
      );
      c.note('al4.s2.reuse-key', 'seller2 reusa key seller1', s2steal.brief,
          lens: 'AL4');
      if (s2steal.ok && s2steal.transferId == payA.transferId) {
        c.hold(
          id: 'AL4-foreign-key-inherits-transfer',
          lens: 'AL4',
          severity: 'P0',
          title: 'Seller2 herdou Transfer do seller1 pela mesma key',
          actor: 'seller2 JWT',
          pre: 'key já transferred no seller1',
          repro: 'POST create-connect-account idempotency_key alheia',
          expected: 'idempotency_key_foreign / Connect próprio',
          obtained: s2steal.brief,
        );
      } else {
        c.block('AL4-s2-key', 'AL4', 'seller2 não herdou Transfer', s2steal);
      }
    }

    final wMid = await c.wallets();
    final refAfterPay = await c.refund(oid2);
    final clawJwt = await c.rpc('batata_clawback_seller_wallet_for_order', {
      'p_order_id': oid2,
    }, jwt: c.buyerJwt);
    final refundWalletJwt = await c.rpc('batata_refund_buyer_wallet_for_order', {
      'p_order_id': oid2,
    }, jwt: c.buyerJwt);
    c.note('al7.refund.after-pay', 'refund-order pós-payout',
        refAfterPay.brief, lens: 'AL7');
    c.note('al7.claw.jwt', 'clawback JWT', clawJwt.brief, lens: 'AL7');
    c.note('al7.refund-wallet.jwt', 'refund buyer wallet JWT',
        refundWalletJwt.brief, lens: 'AL7');

    final wEnd = await c.wallets();
    final rowEnd = await c.orderRow(oid2);
    final txBuyer = await c.walletTxns(walletId: c.buyerId, orderId: oid2);
    final txSeller = await c.walletTxns(walletId: c.sellerId, orderId: oid2);
    c.note('al7.books', 'contabilidade fechada order#2', {
      'wBeforeSale': wBeforeSale,
      'wAfterRel': wAfterRel,
      'wMid': wMid,
      'wEnd': wEnd,
      'order': rowEnd,
      'txBuyer': txBuyer,
      'txSeller': txSeller,
      'dBuyerTotal': (wEnd['buyer'] ?? 0) - (wBeforeSale['buyer'] ?? 0),
      'dSellerTotal': (wEnd['seller'] ?? 0) - (wBeforeSale['seller'] ?? 0),
    }, lens: 'AL7');

    // P0 líquido: buyer creditado E seller manteve release/payout E PI sem refund
    final dBtot = (wEnd['buyer'] ?? 0) - (wBeforeSale['buyer'] ?? 0);
    final refundId = rowEnd?['stripe_refund_id'];
    if (dBtot > 0.05 &&
        (refundId == null || '$refundId'.isEmpty) &&
        released) {
      c.hold(
        id: 'AL3-net-mint-buyer-no-stripe',
        lens: 'AL3',
        severity: 'P0',
        title: 'Buyer ganhou wallet pós-release sem refund Stripe',
        actor: 'composição release+RPC/PATCH',
        pre: 'venda Stripe TEST libertada',
        repro: 'Δbuyer>0 e stripe_refund_id null',
        expected: 'Δbuyer 0 ou refund PI',
        obtained: {
          'dBuyer': dBtot,
          'dSeller': (wEnd['seller'] ?? 0) - (wBeforeSale['seller'] ?? 0),
          'refund': refundId,
          'status': rowEnd?['status'],
        },
      );
    }

    // leftover ledger debited
    final ledEnd = await c.payoutLedger(userId: c.sellerId, limit: 12);
    final orphan = ledEnd.where((e) =>
        e is Map &&
        '${e['status']}' == 'debited' &&
        (e['stripe_transfer_id'] == null ||
            '${e['stripe_transfer_id']}'.isEmpty));
    c.note('al4.orphan-debit', 'ledger debited sem transfer',
        orphan.toList(), lens: 'AL4');
  }

  // ---------------------------------------------------------------------------
  // Fluxo #3 — refund legítimo em pago (controlo) + reuse refund_id noutro pedido
  // ---------------------------------------------------------------------------
  final paid3 = await c.payToPago(lens: 'AL6');
  final paid4 = await c.payToPago(lens: 'AL6');
  if (paid3 != null && paid4 != null) {
    final legit = await c.refund(paid3.oid);
    c.note('al6.refund.legit', 'seller refund-order em pago (controlo)',
        legit.brief, lens: 'AL6');
    final row3 = await c.orderRow(paid3.oid);
    final stolen = row3?['stripe_refund_id']?.toString();
    if (stolen != null && stolen.isNotEmpty) {
      final reuse = await c.rpc('batata_finalize_stripe_order_refund', {
        'p_order_id': paid4.oid,
        'p_refund_id': stolen,
        'p_payment_intent_id': paid4.pi,
        'p_amount_cents': 590,
      }, jwt: c.sellerJwt);
      c.note('al6.finalize.reuse-id', 'finalize order4 com refund de order3',
          reuse.brief, lens: 'AL6');
      if (rpcOk(reuse) && !rpcDenied(reuse)) {
        final row4 = await c.orderRow(paid4.oid);
        c.hold(
          id: 'AL6-refund-id-reuse-other-order',
          lens: 'AL6',
          severity: 'P0',
          title: 'Refund Stripe de um pedido selou outro pedido',
          actor: 'seller JWT finalize',
          pre: 'order3 refundido; order4 pago',
          repro: 'rpc finalize p_refund_id=order3 p_order_id=order4',
          expected: '403',
          obtained: {
            'rpc': reuse.brief,
            'o4': row4?['status'],
            'o4rf': row4?['stripe_refund_id'],
          },
        );
      } else {
        c.block('AL6-reuse-rf', 'AL6', 'reuse refund_id JWT recusado', reuse);
      }
    }
  }

  final wFinal = await c.wallets();
  c.note('snap.wallets.final', 'saldos finais', {
    'start': w0,
    'end': wFinal,
    'dBuyer': (wFinal['buyer'] ?? 0) - (w0['buyer'] ?? 0),
    'dSeller': (wFinal['seller'] ?? 0) - (w0['seller'] ?? 0),
    'dBuyer2': (wFinal['buyer2'] ?? 0) - (w0['buyer2'] ?? 0),
    'dSeller2': (wFinal['seller2'] ?? 0) - (w0['seller2'] ?? 0),
  }, lens: 'AL7');

  await c.dumpAll('pass1.json');
  stdout.writeln(
      'DONE findings=${c.findings.length} blocked=${c.blocked.length} notes=${c.notes.length}');
}
