/// REDTEAM_BLIND_R_CONNECT_PAYOUT_v1
/// dart run tool/redteam_blind_r_20260901T0700/probe.dart
/// Staging only. No production. No SQL/Edge/Flutter patches.
import 'dart:io';

import '_rtr.dart';

void main() async {
  final env = loadEnv();
  final c = Rtr.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final w0 = await c.wallets();
  c.note('w0', 'wallets t0', w0, lens: 'R8');

  // =====================================================================
  // R5 — Connect onboarding redirect / account takeover
  // =====================================================================
  Future<HttpHit> getConnect(String origin) {
    return c.edge(
      'create-connect-account',
      null,
      method: 'GET',
      jwt: c.sellerJwt,
      qs: 'web_return_origin=${Uri.encodeQueryComponent(origin)}',
    );
  }

  final r5evil = await getConnect('https://evil.com');
  final r5sub = await getConnect('https://fleaber.pt.evil.com');
  final r5js = await getConnect('javascript:alert(1)');
  final r5proto = await getConnect('https://fleaber.pt/%0d%0aLocation:%20https://evil.com');
  final r5ok = await getConnect('https://fleaber.pt');
  c.note('r5.get', 'GET create-connect-account origins', {
    'evil': '${r5evil.status} loc=${r5evil.location}',
    'sub': '${r5sub.status} loc=${r5sub.location}',
    'js': '${r5js.status} loc=${r5js.location}',
    'crlf': '${r5proto.status} loc=${r5proto.location}',
    'ok': '${r5ok.status} loc=${r5ok.location}',
  }, lens: 'R5');

  bool locHostile(HttpHit h) {
    final loc = (h.location ?? '').toLowerCase();
    if (loc.isEmpty) return false;
    if (loc.contains('evil.com')) return true;
    if (loc.startsWith('javascript:')) return true;
    return false;
  }

  if (locHostile(r5evil) || locHostile(r5sub) || locHostile(r5js)) {
    c.hold(
      id: 'RTR-R5-open-redirect',
      lens: 'R5',
      severity: 'P0',
      title: 'create-connect-account GET redirecciona para origem hostil',
      actor: 'seller JWT GET',
      pre: 'web_return_origin hostil',
      repro: 'GET create-connect-account?web_return_origin=',
      expected: 'sem Location para evil / javascript',
      obtained: {
        'evil': r5evil.location,
        'sub': r5sub.location,
        'js': r5js.location,
      },
    );
  }

  final r5uid = await c.edge('create-connect-account', {
    'user_id': c.sellerId,
  }, jwt: c.buyerJwt);
  c.note('r5.uid', 'buyer POST user_id=seller', r5uid.brief, lens: 'R5');
  if (r5uid.ok && (r5uid.map?['url'] != null || r5uid.map?['stripeAccountId'] != null)) {
    c.hold(
      id: 'RTR-R5-account-takeover',
      lens: 'R5',
      severity: 'P0',
      title: 'JWT alheio cria/liga Connect de outro user',
      actor: 'buyer JWT',
      pre: 'body.user_id = seller',
      repro: 'POST create-connect-account user_id=<seller>',
      expected: 'erro Cannot create another user',
      obtained: r5uid.brief,
    );
  }

  final r5s2 = await c.edge('create-connect-account', {
    'user_id': c.sellerId,
  }, jwt: c.seller2Jwt);
  c.note('r5.s2', 'seller2 POST user_id=seller1', r5s2.brief, lens: 'R5');
  if (r5s2.ok && r5s2.map?['url'] != null) {
    c.hold(
      id: 'RTR-R5-s2-onboard-s1',
      lens: 'R5',
      severity: 'P0',
      title: '2.º seller inicia onboarding da conta Connect do 1.º',
      actor: 'seller2 JWT',
      pre: 'user_id seller1',
      repro: 'POST create-connect-account user_id=seller1',
      expected: 'erro identidade',
      obtained: r5s2.brief,
    );
  }

  // =====================================================================
  // Superfícies JWT — payout debit / ledger / wallets (não atrofia)
  // =====================================================================
  final debitJwt = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': c.sellerId,
    'p_amount_cents': 100,
    'p_idempotency_key': '${prefix}-jwt-debit-xxxxxxxx',
  }, jwt: c.sellerJwt);
  final debitAnon = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': c.sellerId,
    'p_amount_cents': 100,
    'p_idempotency_key': '${prefix}-anon-debit-xxxxxxxx',
  });
  final debitOther = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': c.sellerId,
    'p_amount_cents': 100,
    'p_idempotency_key': '${prefix}-b2-debit-xxxxxxxx',
  }, jwt: c.buyerJwt);
  final finishJwt = await c.rpc('batata_wallet_payout_finish', {
    'p_idempotency_key': '${prefix}-jwt-debit-xxxxxxxx',
    'p_stripe_transfer_id': 'tr_fake_rtr',
    'p_failed': false,
  }, jwt: c.sellerJwt);
  c.note('rpc.payout', 'JWT/anon payout debit+finish', {
    'seller': debitJwt.brief,
    'anon': debitAnon.brief,
    'buyer_other': debitOther.brief,
    'finish': finishJwt.brief,
  }, lens: 'R6');

  if (debitJwt.ok && debitJwt.map?['ok'] == true) {
    c.hold(
      id: 'RTR-R6-jwt-debit',
      lens: 'R6',
      severity: 'P0',
      title: 'JWT autenticado executou batata_wallet_payout_debit',
      actor: 'seller JWT',
      pre: 'RPC payout é service_role',
      repro: 'POST rpc/batata_wallet_payout_debit',
      expected: '42501 / 401',
      obtained: debitJwt.brief,
    );
  }
  if (finishJwt.ok && finishJwt.map?['ok'] == true) {
    c.hold(
      id: 'RTR-R6-jwt-finish',
      lens: 'R6',
      severity: 'P0',
      title: 'JWT autenticado executou batata_wallet_payout_finish',
      actor: 'seller JWT',
      pre: 'finish só Edge/service_role',
      repro: 'POST rpc/batata_wallet_payout_finish',
      expected: '42501',
      obtained: finishJwt.brief,
    );
  }

  final clawJwt = await c.rpc('batata_clawback_seller_wallet_for_order', {
    'p_order_id': '00000000-0000-0000-0000-000000000001',
  }, jwt: c.buyerJwt);
  final creditJwt = await c.rpc('batata_credit_wallet_once', {
    'p_wallet_id': c.buyerId,
    'p_order_id': '00000000-0000-0000-0000-000000000001',
    'p_amount': 50,
    'p_type': 'reembolso',
    'p_description': '$prefix mint',
  }, jwt: c.buyerJwt);
  c.note('rpc.mint', 'JWT clawback/credit', {
    'claw': clawJwt.brief,
    'credit': creditJwt.brief,
  }, lens: 'R2');
  if (creditJwt.ok && creditJwt.body.contains('true')) {
    c.hold(
      id: 'RTR-R2-jwt-credit',
      lens: 'R2',
      severity: 'P0',
      title: 'JWT executou batata_credit_wallet_once e minta',
      actor: 'buyer JWT',
      pre: 'credit_wallet_once service_role',
      repro: 'rpc batata_credit_wallet_once 50€',
      expected: '42501',
      obtained: creditJwt.brief,
    );
  }

  final patchBal = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {'balance': 99999.12},
  );
  final insTxn = await c.rest('POST', 'wallet_transactions', jwt: c.sellerJwt, body: {
    'wallet_id': c.sellerId,
    'amount': 40,
    'type': 'venda',
    'description': '$prefix mint txn',
  });
  final insLed = await c.rest('POST', 'wallet_payout_ledger', jwt: c.sellerJwt, body: {
    'idempotency_key': '${prefix}-led-fake-xxxxxxxx',
    'user_id': c.sellerId,
    'amount_cents': 100,
    'amount_eur': 1,
    'status': 'transferred',
    'stripe_transfer_id': 'tr_rtr_fake',
  });
  final patchAcct = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.buyerJwt,
    body: {'stripe_account_id': 'acct_hijack_rtr'},
  );
  final patchOwnAcct = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {'stripe_account_id': 'acct_self_swap_rtr'},
  );
  c.note('rls.wallet', 'PATCH/INSERT wallets+ledger JWT', {
    'patch_bal': patchBal.brief,
    'ins_txn': insTxn.brief,
    'ins_led': insLed.brief,
    'patch_acct_b': patchAcct.brief,
    'patch_acct_s': patchOwnAcct.brief,
  }, lens: 'R6');

  final balAfterPatch = await c.walletBal(c.sellerId);
  if (patchBal.ok && (balAfterPatch - (w0['seller'] ?? 0)).abs() > 1000) {
    c.hold(
      id: 'RTR-R6-patch-balance',
      lens: 'R6',
      severity: 'P0',
      title: 'JWT alterou wallets.balance',
      actor: 'seller JWT',
      pre: 'sem policy UPDATE',
      repro: 'PATCH wallets balance=99999',
      expected: '0 linhas / 403',
      obtained: '${patchBal.brief} bal=$balAfterPatch',
    );
  }
  if (insTxn.ok && insTxn.firstId != null) {
    c.hold(
      id: 'RTR-R6-insert-txn',
      lens: 'R6',
      severity: 'P0',
      title: 'JWT inseriu wallet_transactions venda',
      actor: 'seller JWT',
      pre: 'sem INSERT policy',
      repro: 'POST wallet_transactions type=venda',
      expected: '403',
      obtained: insTxn.brief,
    );
  }
  if (insLed.ok && insLed.firstId != null) {
    c.hold(
      id: 'RTR-R6-insert-ledger',
      lens: 'R6',
      severity: 'P0',
      title: 'JWT inseriu linha em wallet_payout_ledger',
      actor: 'seller JWT',
      pre: 'ledger só service_role',
      repro: 'POST wallet_payout_ledger status=transferred',
      expected: '403',
      obtained: insLed.brief,
    );
  }

  // =====================================================================
  // R7 — MB WAY / off-platform não contamina wallet plataforma
  // =====================================================================
  final pidMb = await c.createProduct(title: '$prefix mbway', qty: 2, price: 7.5);
  final oidMb = await c.insertOrder(
    productId: pidMb ?? '',
    jwt: c.buyerJwt,
    price: 7.5,
    payment: 'MB WAY',
    shipping: 'entrega em mão',
  );
  final mbPago = await c.rest('PATCH', 'orders?id=eq.$oidMb', jwt: c.sellerJwt, body: {
    'status': 'pago',
  });
  final mbConc = await c.markConcluido(oidMb ?? '');
  final wMb0 = await c.wallets();
  final mbRel = await c.rpc('batata_release_seller_wallet_for_order', {
    'p_order_id': oidMb,
  }, jwt: c.buyerJwt);
  final wMb1 = await c.wallets();
  final mbRef = await c.edge('refund-order', {'order_id': oidMb}, jwt: c.sellerJwt);
  final mbRow = await c.orderRow(oidMb ?? '');
  c.note('r7.mbway', 'MB WAY pago→concluido→release→refund-order', {
    'oid': oidMb,
    'pago': mbPago.brief,
    'conc': mbConc.brief,
    'rel': mbRel.brief,
    'dSeller': (wMb1['seller'] ?? 0) - (wMb0['seller'] ?? 0),
    'dBuyer': (wMb1['buyer'] ?? 0) - (wMb0['buyer'] ?? 0),
    'refund': mbRef.brief,
    'order': mbRow,
  }, lens: 'R7');
  final dMbS = (wMb1['seller'] ?? 0) - (wMb0['seller'] ?? 0);
  final dMbB = (wMb1['buyer'] ?? 0) - (wMb0['buyer'] ?? 0);
  if (dMbS > 0.009 || dMbB > 0.009) {
    c.hold(
      id: 'RTR-R7-mbway-mint',
      lens: 'R7',
      severity: 'P0',
      title: 'MB WAY libertou/creditou carteira de plataforma',
      actor: 'buyer release após seller PATCH pago',
      pre: 'pagamento off-platform sem amount_paid_cents',
      repro: 'MB WAY pago → concluido → batata_release_seller_wallet_for_order',
      expected: 'Δwallet 0',
      obtained: 'Δseller=$dMbS Δbuyer=$dMbB rel=${mbRel.brief}',
      evidence: {'order': mbRow, 'w0': wMb0, 'w1': wMb1},
    );
  }
  if (mbRef.ok && mbRef.map?['skipped'] != true && mbRef.map?['refund_id'] != null) {
    c.hold(
      id: 'RTR-R7-mbway-stripe-refund',
      lens: 'R7',
      severity: 'P1',
      title: 'refund-order em MB WAY criou refund Stripe',
      actor: 'seller JWT',
      pre: 'not_seguro_fleaber',
      repro: 'POST refund-order order MB WAY',
      expected: 'skipped not_seguro_fleaber',
      obtained: mbRef.brief,
    );
  }

  // =====================================================================
  // R4 — race cancelamento (refund-order) ∥ release (pago → concluido)
  // =====================================================================
  final fxRace = await c.payToPago(lens: 'R4');
  if (fxRace != null) {
    await c.markMao(fxRace.oid);
    final wR0 = await c.wallets();
    final raced = await parallel([
      c.edge('refund-order', {'order_id': fxRace.oid}, jwt: c.sellerJwt),
      () async {
        await c.markConcluido(fxRace.oid);
        return c.rpc('batata_release_seller_wallet_for_order', {
          'p_order_id': fxRace.oid,
        }, jwt: c.buyerJwt);
      }(),
    ]);
    final wR1 = await c.wallets();
    final raceRow = await c.orderRow(fxRace.oid);
    final raceTx = await c.walletTxns(orderId: fxRace.oid);
    c.note('r4.race', 'refund-order ∥ concluido+release', {
      'refund': raced[0].brief,
      'rel': raced[1].brief,
      'dSeller': (wR1['seller'] ?? 0) - (wR0['seller'] ?? 0),
      'dBuyer': (wR1['buyer'] ?? 0) - (wR0['buyer'] ?? 0),
      'order': raceRow,
      'pi': fxRace.pi,
    }, lens: 'R4');
    final dRs = (wR1['seller'] ?? 0) - (wR0['seller'] ?? 0);
    final refunded = raced[0].ok &&
        (raced[0].map?['refund_id'] != null ||
            raced[0].map?['ok'] == true && raced[0].map?['skipped'] != true);
    final released = '${raced[1].body}'.contains('true') &&
        (raceRow?['wallet_release_processed_at'] != null) &&
        dRs > 0.009;
    if (refunded && released) {
      c.hold(
        id: 'RTR-R4-refund-and-release',
        lens: 'R4',
        severity: 'P0',
        title: 'Race cancelamento Stripe e libertação carteira no mesmo ciclo',
        actor: 'seller refund-order ∥ buyer concluido+release',
        pre: 'Stripe TEST pago, mão, wallet_release null',
        repro: 'Future.wait refund-order + PATCH concluido + release RPC',
        expected: 'um lado só; clawback se ambos',
        obtained: {
          'refund': raced[0].brief,
          'rel': raced[1].brief,
          'dSeller': dRs,
          'status': raceRow?['status'],
          'stripe_refund_id': raceRow?['stripe_refund_id'],
        },
        evidence: {'order': raceRow, 'tx': raceTx, 'w0': wR0, 'w1': wR1},
      );
    }
  }

  // =====================================================================
  // R1/R2/R6/R8 — venda Stripe → release → payout → refund/clawback
  // =====================================================================
  final oid = await c.payAndComplete(lens: 'R1');
  if (oid == null) {
    stderr.writeln('FAIL payAndComplete');
    await dumpJson('${outDir()}/probe.json', {
      'notes': c.notes,
      'findings': c.findings,
    });
    exit(4);
  }

  final wPreRel = await c.wallets();
  final rel1 = await c.rpc('batata_release_seller_wallet_for_order', {
    'p_order_id': oid,
  }, jwt: c.buyerJwt);
  final rel2 = await c.rpc('batata_release_seller_wallet_for_order', {
    'p_order_id': oid,
  }, jwt: c.buyerJwt);
  final relS = await c.rpc('batata_release_seller_wallet_for_order', {
    'p_order_id': oid,
  }, jwt: c.sellerJwt);
  final relB2 = await c.rpc('batata_release_seller_wallet_for_order', {
    'p_order_id': oid,
  }, jwt: c.buyer2Jwt);
  final wPostRel = await c.wallets();
  final booksRel = await c.books(oid);
  final credited =
      ((wPostRel['seller'] ?? 0) - (wPreRel['seller'] ?? 0));
  c.note('r1.release', 'release seller após concluido', {
    'rel1': rel1.brief,
    'rel2': rel2.brief,
    'relS': relS.brief,
    'relB2': relB2.brief,
    'credited': credited,
    'order': booksRel['order'],
  }, lens: 'R1');
  if (relB2.ok && '${relB2.body}' == 'true') {
    c.hold(
      id: 'RTR-R1-b2-release',
      lens: 'R1',
      severity: 'P1',
      title: '2.º comprador libertou carteira de venda alheia',
      actor: 'buyer2 JWT',
      pre: 'order de B1 concluida',
      repro: 'rpc batata_release_seller_wallet_for_order',
      expected: 'false',
      obtained: relB2.brief,
    );
  }

  // R2 — refund-order pós-release (seller) deve bloquear
  final refPost = await c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt);
  final refBuyer = await c.edge('refund-order', {'order_id': oid}, jwt: c.buyerJwt);
  final refB2 = await c.edge('refund-order', {'order_id': oid}, jwt: c.buyer2Jwt);
  c.note('r2.refund-order', 'refund-order pós-release', {
    'seller': refPost.brief,
    'buyer': refBuyer.brief,
    'b2': refB2.brief,
  }, lens: 'R2');

  final rwBuyer = await c.rpc('batata_refund_buyer_wallet_for_order', {
    'p_order_id': oid,
  }, jwt: c.buyerJwt);
  final rwSeller = await c.rpc('batata_refund_buyer_wallet_for_order', {
    'p_order_id': oid,
  }, jwt: c.sellerJwt);
  c.note('r2.refund-wallet', 'refund buyer wallet em concluido', {
    'buyer': rwBuyer.brief,
    'seller': rwSeller.brief,
  }, lens: 'R2');

  final devB = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
    'status': 'devolvida',
  });
  final devS = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
    'status': 'devolvida',
  });
  c.note('r2.devolvida', 'PATCH devolvida pós-release', {
    'buyer': devB.brief,
    'seller': devS.brief,
    'status': (await c.orderRow(oid))?['status'],
  }, lens: 'R2');

  // R6 — dual payout (keys diferentes, montante = crédito libertado)
  final sellerW = await c.walletRow(c.sellerId);
  final stripeAcct = sellerW?['stripe_account_id'];
  final balCents = ((wPostRel['seller'] ?? 0) * 100).round();
  final payAmt = credited > 0.009
      ? (credited * 100).round()
      : (balCents > 0 ? balCents : 100);
  final keyA = '${prefix}-pay-a-${oid.substring(0, 8)}-xx';
  final keyB = '${prefix}-pay-b-${oid.substring(0, 8)}-xx';
  final wPrePay = await c.wallets();
  final pays = await parallel([
    c.edge('create-connect-account', {
      'amount': payAmt,
      'idempotency_key': keyA,
    }, jwt: c.sellerJwt),
    c.edge('create-connect-account', {
      'amount': payAmt,
      'idempotency_key': keyB,
    }, jwt: c.sellerJwt),
  ]);
  final paySame = await c.edge('create-connect-account', {
    'amount': payAmt,
    'idempotency_key': keyA,
  }, jwt: c.sellerJwt);
  final wPostPay = await c.wallets();
  final led = await c.payoutLedger(userId: c.sellerId);
  c.note('r6.payout', 'payout paralelo keys distintas + replay', {
    'acct': stripeAcct,
    'amount_cents': payAmt,
    'a': pays[0].brief,
    'b': pays[1].brief,
    'replay_a': paySame.brief,
    'dSeller': (wPostPay['seller'] ?? 0) - (wPrePay['seller'] ?? 0),
    'ledger': led.take(6).toList(),
  }, lens: 'R6');

  bool payoutOk(HttpHit h) =>
      h.ok && (h.map?['success'] == true || h.map?['transferId'] != null);
  final okA = payoutOk(pays[0]);
  final okB = payoutOk(pays[1]);
  if (okA && okB) {
    final tidA = '${pays[0].map?['transferId']}';
    final tidB = '${pays[1].map?['transferId']}';
    if (tidA != tidB && tidA.isNotEmpty && tidB.isNotEmpty) {
      c.hold(
        id: 'RTR-R6-double-transfer',
        lens: 'R6',
        severity: 'P0',
        title: 'Dois pedidos de levantamento criaram duas Transfers Stripe',
        actor: 'seller JWT Future.wait',
        pre: 'saldo após release; duas idempotency_key',
        repro: 'Future.wait 2× create-connect-account amount=crédito keys distintas',
        expected: 'uma Transfer; a outra insufficient / idempotente',
        obtained: {'a': pays[0].brief, 'b': pays[1].brief},
        evidence: {'ledger': led, 'w0': wPrePay, 'w1': wPostPay},
      );
    }
  }

  // R1 — depois do payout (ou tentativa), refund-order outra vez
  final refAfterPay = await c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt);
  final wAfterRef = await c.wallets();
  final rowAfterPay = await c.orderRow(oid);
  c.note('r1.post-payout-refund', 'refund-order após tentativa payout', {
    'refund': refAfterPay.brief,
    'order': rowAfterPay,
    'dSeller': (wAfterRef['seller'] ?? 0) - (wPostPay['seller'] ?? 0),
  }, lens: 'R1');

  final stripeRefunded = (rowAfterPay?['stripe_refund_id'] ?? '').toString().isNotEmpty;
  if (stripeRefunded && (okA || okB)) {
    c.hold(
      id: 'RTR-R1-payout-and-buyer-refund',
      lens: 'R1',
      severity: 'P0',
      title: 'Levantamento Connect e refund Stripe do comprador no mesmo pedido',
      actor: 'seller payout + refund-order',
      pre: 'release + payout tentado',
      repro: 'create-connect-account amount>0 → refund-order',
      expected: 'refund-order bloqueado pós-concluido; sem Transfer+refund',
      obtained: {
        'payout_a': pays[0].brief,
        'refund': refAfterPay.brief,
        'stripe_refund_id': rowAfterPay?['stripe_refund_id'],
      },
    );
  }

  // R2 — clawback JWT + drain residual (payout já tentou esvaziar)
  final clawAfter = await c.rpc('batata_clawback_seller_wallet_for_order', {
    'p_order_id': oid,
  }, jwt: c.sellerJwt);
  final clawBuyer = await c.rpc('batata_clawback_seller_wallet_for_order', {
    'p_order_id': oid,
  }, jwt: c.buyerJwt);
  c.note('r2.claw-jwt', 'clawback JWT pós-payout', {
    'seller': clawAfter.brief,
    'buyer': clawBuyer.brief,
  }, lens: 'R2');

  // Tentar drenar o que restar (2.º payout)
  final restCents = ((await c.walletBal(c.sellerId)) * 100).round();
  HttpHit? drain2;
  if (restCents >= 50) {
    drain2 = await c.edge('create-connect-account', {
      'amount': restCents,
      'idempotency_key': '${prefix}-drain2-${oid.substring(0, 8)}-xx',
    }, jwt: c.sellerJwt);
    c.note('r2.drain2', '2.º levantamento saldo residual', drain2.brief, lens: 'R2');
  }

  // =====================================================================
  // R3 — disputa parcial <100% após release (seller ainda com crédito)
  // =====================================================================
  final oidP = await c.payAndComplete(lens: 'R3');
  Map<String, dynamic>? r3ev;
  if (oidP != null) {
    final w3a = await c.wallets();
    final relP = await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': oidP,
    }, jwt: c.buyerJwt);
    final w3b = await c.wallets();
    final disp = await c.insertDispute(oidP);
    final ped = await c.rest(
      'PATCH',
      'orders?id=eq.$oidP',
      jwt: c.buyerJwt,
      body: {'status': 'pedido_devolucao'},
    );
    final offer = await c.rest(
      'PATCH',
      'order_disputes?order_id=eq.$oidP',
      jwt: c.sellerJwt,
      body: {
        'seller_offer_type': 'partial_refund',
        'seller_refund_percent': 40,
      },
    );
    final part = await c.rpc('batata_process_partial_refund_dispute', {
      'p_order_id': oidP,
    }, jwt: c.buyerJwt);
    final partS = await c.rpc('batata_process_partial_refund_dispute', {
      'p_order_id': oidP,
    }, jwt: c.sellerJwt);
    final w3c = await c.wallets();
    final booksP = await c.books(oidP);
    r3ev = {
      'rel': relP.brief,
      'disp': disp.brief,
      'pedido': ped.brief,
      'offer': offer.brief,
      'part_buyer': part.brief,
      'part_seller': partS.brief,
      'dSeller_rel': (w3b['seller'] ?? 0) - (w3a['seller'] ?? 0),
      'dSeller_part': (w3c['seller'] ?? 0) - (w3b['seller'] ?? 0),
      'dBuyer_part': (w3c['buyer'] ?? 0) - (w3b['buyer'] ?? 0),
      'order': booksP['order'],
      'tx': booksP['tx'],
    };
    c.note('r3.partial', 'parcial 40% pós-release', r3ev, lens: 'R3');

    final dB = (w3c['buyer'] ?? 0) - (w3b['buyer'] ?? 0);
    final dSrel = (w3b['seller'] ?? 0) - (w3a['seller'] ?? 0);
    final dSpart = (w3c['seller'] ?? 0) - (w3b['seller'] ?? 0);
    // Seller ficou com mais do que (crédito − 40%) se parcial creditou buyer
    // SEM clawback: dSpart≈0 e dB>0 enquanto seller mantém dSrel.
    if (dB > 0.009 && dSpart > -0.001 && dSrel > 0.009 && part.ok) {
      final netSellerKeep = dSrel + dSpart;
      final capture = numOf((booksP['order'] as Map?)?['amount_paid_cents']) ?? 0;
      final buyerPlusSeller = (dB + netSellerKeep) * 100;
      if (capture > 0 && buyerPlusSeller > capture + 1) {
        c.hold(
          id: 'RTR-R3-partial-over-capture',
          lens: 'R3',
          severity: 'P0',
          title: 'Parcial <100% deixa seller+buyer com mais do que a captura',
          actor: 'buyer RPC parcial após release',
          pre: 'concluido + release; oferta 40%',
          repro: 'release → disputa → seller_refund_percent=40 → process_partial',
          expected: 'clawback + split ≤ captura',
          obtained: {
            'dB': dB,
            'dSrel': dSrel,
            'dSpart': dSpart,
            'capture_cents': capture,
          },
          evidence: r3ev,
        );
      }
    }
  }

  // =====================================================================
  // R8 — composição: venda → release → payout → disputa → refund
  // (reutiliza oid R1 se payout já correu; senão cadeia curta em oidP)
  // =====================================================================
  final dispR8 = await c.insertDispute(oid);
  final pedR8 = await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    jwt: c.buyerJwt,
    body: {'status': 'pedido_devolucao'},
  );
  final offerR8 = await c.rest(
    'PATCH',
    'order_disputes?order_id=eq.$oid',
    jwt: c.sellerJwt,
    body: {
      'seller_offer_type': 'partial_refund',
      'seller_refund_percent': 50,
    },
  );
  final partR8 = await c.rpc('batata_process_partial_refund_dispute', {
    'p_order_id': oid,
  }, jwt: c.buyerJwt);
  final refR8 = await c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt);
  final wR8 = await c.wallets();
  final booksR8 = await c.books(oid);
  c.note('r8.compose', 'release+payout → disputa → parcial → refund-order', {
    'disp': dispR8.brief,
    'pedido': pedR8.brief,
    'offer': offerR8.brief,
    'part': partR8.brief,
    'refund': refR8.brief,
    'wallets': wR8,
    'order': booksR8['order'],
    'tx': booksR8['tx'],
  }, lens: 'R8');

  final rowR8 = booksR8['order'] as Map?;
  final hasTransfer = led.any((e) =>
      e is Map &&
      '${e['status']}' == 'transferred' &&
      '${e['stripe_transfer_id']}'.startsWith('tr_'));
  final hasStripeRefund =
      (rowR8?['stripe_refund_id'] ?? '').toString().isNotEmpty;
  if (hasTransfer && hasStripeRefund) {
    c.hold(
      id: 'RTR-R8-transfer-and-refund',
      lens: 'R8',
      severity: 'P0',
      title: 'Composição: Transfer Connect e refund Stripe na mesma venda',
      actor: 'seller payout + refund/dispute',
      pre: 'R1 release+payout + R8 disputa',
      repro: 'venda → release → payout → disputa/parcial → refund-order',
      expected: 'não coexistir Transfer e stripe_refund_id sem clawback total',
      obtained: {
        'ledger': led.take(4).toList(),
        'stripe_refund_id': rowR8?['stripe_refund_id'],
      },
    );
  }

  // Legítimo: refund-order em pago (não partir o caminho)
  final fxLegit = await c.payToPago(lens: 'R2');
  HttpHit? legitRef;
  if (fxLegit != null) {
    legitRef = await c.edge(
      'refund-order',
      {'order_id': fxLegit.oid},
      jwt: c.sellerJwt,
    );
    c.note('r2.legit', 'refund-order legítimo em pago', {
      'http': legitRef.brief,
      'order': await c.orderRow(fxLegit.oid),
    }, lens: 'R2');
    if (!legitRef.ok ||
        (legitRef.map?['ok'] != true && legitRef.map?['refund_id'] == null)) {
      c.hold(
        id: 'RTR-R2-legit-refund-broken',
        lens: 'R2',
        severity: 'P1',
        title: 'refund-order legítimo pós-venda (pago) falhou',
        actor: 'seller JWT',
        pre: 'Stripe TEST status=pago',
        repro: 'POST refund-order',
        expected: '200 ok + refund_id',
        obtained: legitRef.brief,
      );
    }
  }

  final wEnd = await c.wallets();
  final out = {
    'auditor': 'REDTEAM_BLIND_R_CONNECT_PAYOUT_v1',
    'prefix': prefix,
    'production_touched': false,
    'fase4': false,
    'actors': {
      'buyer': c.buyerId,
      'seller': c.sellerId,
      'buyer2': c.buyer2Id,
      'seller2': c.seller2Id,
    },
    'w0': w0,
    'wEnd': wEnd,
    'orders': c.createdOrderIds,
    'products': c.createdProductIds,
    'notes': c.notes,
    'findings': c.findings,
  };
  await dumpJson('${outDir()}/probe.json', out);
  stdout.writeln('WROTE ${outDir()}/probe.json findings=${c.findings.length}');
}
