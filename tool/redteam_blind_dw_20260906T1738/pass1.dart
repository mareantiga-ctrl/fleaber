/// RED TEAM CEGO DW pass1 — wallet forge · release · payout · Connect · caixa.
/// Staging only. Stripe TEST. NÃO CORRIGIR. Fase 4 não.
/// Anti-atrofia: NÃO correr buyer refund-order 403 · Coptic payout key · charset 400.
import 'dart:io';
import '_rtdw.dart';

Future<({String oid, String pid, String? pi})> mustPay(
  Rtdw c,
  String lens,
) async {
  final paid = await c.payToPago(lens: lens);
  if (paid == null) throw StateError('setup_paid_order failed $lens');
  return paid;
}

bool minted(HttpHit h, num delta) {
  if (delta > 0) return true;
  if (h.payoutOk) return true;
  if (h.rpcTrue && h.ok) return true;
  if (h.ok && h.firstId != null && h.status == 201) return true;
  if (h.ok && h.json == true) return true;
  return false;
}

Future<void> main() async {
  final c = Rtdw.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final s1 = c.sellerId!;
  final b1 = c.buyerId!;
  final s2 = c.seller2Id;
  final fakeOid = '00000000-0000-0000-0000-00000000dw01';

  stdout.writeln('actors B1=$b1 S1=$s1 B2=${c.buyer2Id} S2=$s2');

  // =========================================================================
  // DW-A Forge — ângulos novos vs DP (UPSERT/UPDATE, finish RPC, profiles,
  // reembolso negativo, PATCH tips, webhook sem assinatura).
  // =========================================================================
  final a0s = await c.walletBal(s1);
  final a0b = await c.walletBal(b1);

  final insCredit = await c.rest('POST', 'wallet_transactions', jwt: c.buyerJwt,
      body: {
        'wallet_id': s1,
        'amount': 50,
        'type': 'venda',
        'description': '$prefix buyer credit alien',
      });
  final insDebit = await c.rest('POST', 'wallet_transactions', jwt: c.sellerJwt,
      body: {
        'wallet_id': s1,
        'amount': -80,
        'type': 'levantamento',
        'description': '$prefix seller debit self',
      });
  final upsert = await c.rest(
    'POST',
    'wallets?on_conflict=id',
    jwt: c.buyerJwt,
    prefer: 'resolution=merge-duplicates,return=representation',
    body: {'id': s1, 'balance': 9999.99},
  );
  final existing = await c.walletTxns(s1, limit: 1);
  HttpHit? patchTxn;
  if (existing.isNotEmpty) {
    final tid = existing.first['id'];
    patchTxn = await c.rest(
      'PATCH',
      'wallet_transactions?id=eq.$tid',
      jwt: c.sellerJwt,
      body: {'amount': 777, 'type': 'venda'},
    );
  } else {
    patchTxn = HttpHit(0, 'no txn', {'error': 'no txn'});
  }
  final a1s = await c.walletBal(s1);
  final a1b = await c.walletBal(b1);
  final a1Open = minted(insCredit, a1s - a0s) ||
      minted(insDebit, a1s - a0s) ||
      minted(upsert, a1s - a0s) ||
      (a1s - a0s).abs() > 0.001 ||
      (a1b - a0b).abs() > 0.001;
  c.probe(
    id: 'A1',
    lens: 'DW1',
    edgeRpc: 'POST wallet_transactions JWT + UPSERT wallets + PATCH txn',
    payload: 'buyer credit alien 50 · seller debit -80 · UPSERT bal=9999 · PATCH amount=777',
    http:
        'credit ${insCredit.brief} | debit ${insDebit.brief} | upsert ${upsert.brief} | patchTxn ${patchTxn.brief}',
    stripeBd: 'ΔB=${a1b - a0b} ΔS=${a1s - a0s}',
    result: a1Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a1Open,
  );
  await c.expectDenied(
    id: 'A1-credit-alien',
    lens: 'DW1',
    title: 'Buyer JWT INSERT credit na wallet do seller',
    hit: insCredit,
    actor: 'buyer JWT',
    pre: 'RLS sem INSERT authenticated',
    repro: 'POST wallet_transactions wallet_id=S1 amount=50',
    delta: a1s - a0s,
  );

  final finishJwt = await c.rpc('batata_wallet_payout_finish', {
    'p_idempotency_key': 'p_rtdw_fake_finish_key_1738',
    'p_stripe_transfer_id': 'tr_rtdw_fake',
    'p_failed': true,
  }, jwt: c.sellerJwt);
  final reembCents = await c.rpc('batata_order_wallet_reembolso_cents', {
    'p_order_id': fakeOid,
  }, jwt: c.buyerJwt);
  final remainEur = await c.rpc('batata_order_wallet_remaining_eur', {
    'p_order_id': fakeOid,
  }, jwt: c.sellerJwt);
  final creditReemb = await c.rpc('batata_credit_wallet_once', {
    'p_wallet_id': s1,
    'p_order_id': fakeOid,
    'p_amount': 33,
    'p_type': 'reembolso',
    'p_description': '$prefix reembolso forge',
  }, jwt: c.buyerJwt);
  final adjust = await c.rpc('batata_adjust_wallet_balance', {
    'p_wallet_id': s1,
    'p_delta': 100,
  }, jwt: c.sellerJwt);
  final a2s = await c.walletBal(s1);
  final a2Open = minted(finishJwt, a2s - a1s) ||
      minted(creditReemb, a2s - a1s) ||
      (a2s - a1s).abs() > 0.001 ||
      (finishJwt.ok && finishJwt.map?['ok'] == true);
  c.probe(
    id: 'A2',
    lens: 'DW1',
    edgeRpc: 'rpc payout_finish / reembolso_cents / remaining / credit reembolso / adjust',
    payload:
        'finish p_failed=true tr_fake · reembolso_cents fakeOid · remaining · credit type=reembolso 33 · adjust +100',
    http:
        'finish ${finishJwt.brief} | reemb ${reembCents.brief} | remain ${remainEur.brief} | credit ${creditReemb.brief} | adj ${adjust.brief}',
    stripeBd: 'ΔS=${a2s - a1s}',
    result: a2Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a2Open,
  );
  await c.expectDenied(
    id: 'A2-payout-finish',
    lens: 'DW1',
    title: 'JWT batata_wallet_payout_finish p_failed=true',
    hit: finishJwt,
    actor: 'seller JWT',
    pre: 'GRANT service_role only',
    repro: 'rpc batata_wallet_payout_finish p_failed=true',
    openIf: (h) => h.ok && h.map?['ok'] == true,
    delta: a2s - a1s,
  );

  final patchProfBal = await c.rest(
    'PATCH',
    'profiles?id=eq.$s1',
    jwt: c.sellerJwt,
    body: {'wallet_balance': 8888, 'balance': 8888, 'available_balance': 8888},
  );
  final patchProfStripe = await c.rest(
    'PATCH',
    'profiles?id=eq.$s1',
    jwt: c.buyerJwt,
    body: {'stripe_account_id': 'acct_1UB7nWHKe5ETfHI5'},
  );
  final delWallet = await c.rest(
    'DELETE',
    'wallets?id=eq.$s1',
    jwt: c.buyerJwt,
    prefer: 'return=representation',
  );
  final insAlienWallet = await c.rest('POST', 'wallets', jwt: c.buyerJwt, body: {
    'id': s2 ?? fakeOid,
    'balance': 500,
  });
  final a3s = await c.walletBal(s1);
  final a3row = await c.walletRow(s1);
  final a3Open = (a3s - a2s).abs() > 0.001 ||
      a3row == null ||
      minted(insAlienWallet, 0);
  c.probe(
    id: 'A3',
    lens: 'DW1',
    edgeRpc: 'PATCH profiles + DELETE/INSERT wallets JWT',
    payload:
        'profiles wallet_balance/stripe_account_id · DELETE wallets S1 · INSERT wallets S2 bal=500',
    http:
        'profBal ${patchProfBal.brief} | profStripe ${patchProfStripe.brief} | del ${delWallet.brief} | ins ${insAlienWallet.brief}',
    stripeBd: 'ΔS=${a3s - a2s} wallet_exists=${a3row != null}',
    result: a3Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a3Open,
  );
  if (a3Open) {
    c.hold(
      id: 'A3-profiles-wallets',
      lens: 'DW1',
      severity: 'P0',
      title: 'JWT PATCH profiles / DELETE wallets / INSERT wallet alheia',
      actor: 'buyer/seller JWT',
      pre: 'profiles sem campos de saldo; wallets sem DELETE/INSERT authenticated',
      repro: 'PATCH profiles; DELETE wallets; POST wallets id=S2',
      expected: '400 coluna / 0 rows / 403',
      obtained: 'Δ=${a3s - a2s} exists=${a3row != null} ${delWallet.brief}',
    );
  } else {
    c.block('A3-profiles', 'DW1', 'PATCH profiles / DELETE wallets recusado',
        patchProfBal);
  }

  num a4s0 = await c.walletBal(s1);
  HttpHit? tipCk;
  HttpHit? tipSettle;
  HttpHit? tipPatch;
  String? tipSid;
  String? tipId;
  String? liveId;
  try {
    liveId = await c.insertLive(seller: s1, title: '$prefix tip-unpaid');
    if (liveId != null) {
      tipCk = await c.tipCheckout(
        liveId: liveId,
        seller: s1,
        amountEur: 2,
        jwt: c.buyerJwt,
      );
      tipSid = tipCk.map?['checkoutSessionId']?.toString() ??
          tipCk.map?['sessionId']?.toString() ??
          tipCk.map?['session_id']?.toString();
      tipId = tipCk.map?['tipId']?.toString() ??
          tipCk.map?['tip_id']?.toString();
      if (tipId != null) c.createdTipIds.add(tipId);
      if (tipSid != null && tipSid.startsWith('cs_')) {
        tipSettle = await c.tipSettleGet(tipSid, jwt: c.buyerJwt);
      }
      if (tipId != null) {
        tipPatch = await c.rest(
          'PATCH',
          'live_tips?id=eq.$tipId',
          jwt: c.buyerJwt,
          body: {'status': 'paid', 'amount': 99, 'seller_amount': 99},
        );
      }
    }
  } catch (e) {
    c.note('A4.err', 'tip unpaid error', '$e', lens: 'DW7');
  }
  final a4s1 = await c.walletBal(s1);
  final tipSt = tipId == null ? null : await c.tipRow(tipId);
  final a4Credited = (a4s1 - a4s0) > 0 ||
      '${tipSt?['status'] ?? ''}'.toLowerCase() == 'paid' ||
      '${tipSt?['status'] ?? ''}'.toLowerCase() == 'completed';
  c.probe(
    id: 'A4',
    lens: 'DW7',
    edgeRpc: 'create-live-tip-checkout unpaid + PATCH live_tips status=paid',
    payload: 'live $liveId amount_eur=2 sem pagar; PATCH status=paid amount=99',
    http:
        '${tipCk?.brief} settle=${tipSettle?.brief} patch=${tipPatch?.brief}',
    stripeBd:
        'sid=$tipSid tip=$tipId status=${tipSt?['status']} amt=${tipSt?['amount']} ΔS=${a4s1 - a4s0}',
    result: a4Credited ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a4Credited,
  );
  if (a4Credited) {
    c.hold(
      id: 'A4-unpaid-tip-mint',
      lens: 'DW7',
      severity: 'P0',
      title: 'Tip unpaid / PATCH live_tips creditou wallet',
      actor: 'buyer JWT',
      pre: 'settle GET unpaid + PATCH tips não minta',
      repro: 'POST tip-checkout + GET unpaid + PATCH status=paid',
      expected: 'tip pending Δwallet 0',
      obtained: 'status=${tipSt?['status']} Δ=${a4s1 - a4s0}',
    );
  } else {
    c.block('A4-unpaid', 'DW7', 'tip unpaid/PATCH Δ=0',
        tipPatch ?? tipCk ?? HttpHit(0, 'no tip', null));
  }
  await c.endLives();

  // D1 cedo: caixa 4242 + order real para A5 reorder / B1.
  final d1s0 = await c.walletBal(s1);
  final d1b0 = await c.walletBal(b1);
  final d1 = await mustPay(c, 'DW7');
  final d1row = await c.orderRow(d1.oid);
  final d1s1 = await c.walletBal(s1);
  final d1b1 = await c.walletBal(b1);
  final d1Paid = c.orderPaid(d1row);
  final d1Pi = d1.pi ?? '${d1row?['stripe_payment_intent_id'] ?? ''}';
  final d1MintOnPay = (d1s1 - d1s0) > 0;
  c.probe(
    id: 'D1',
    lens: 'DW7',
    edgeRpc: 'e2e setup_paid_order (4242 / pm_card_visa)',
    payload: 'PI TEST confirm order=${d1.oid}',
    http:
        'status=${d1row?['status']} pi=$d1Pi paid_cents=${d1row?['amount_paid_cents']}',
    stripeBd:
        'ΔS=${d1s1 - d1s0} ΔB=${d1b1 - d1b0} release_at=${d1row?['wallet_release_processed_at']}',
    result: (!d1Paid || d1MintOnPay) ? 'FAIL' : 'HOLD',
    countFinding: !d1Paid || d1MintOnPay,
  );
  if (!d1Paid) {
    c.hold(
      id: 'D1-not-paid',
      lens: 'DW7',
      severity: 'P1',
      title: 'setup_paid_order não ficou pago',
      actor: 'service fixture',
      pre: 'PI pm_card_visa confirm',
      repro: 'e2e setup_paid_order',
      expected: 'status=pago + pi_',
      obtained: '${d1row?['status']} pi=$d1Pi',
    );
  } else if (d1MintOnPay) {
    c.hold(
      id: 'D1-mint-on-pago',
      lens: 'DW7',
      severity: 'P0',
      title: 'Pago creditou wallet antes de release',
      actor: 'webhook/trigger',
      pre: 'release só em concluido',
      repro: 'setup_paid_order → wallets.balance',
      expected: 'Δwallet 0 até release',
      obtained: 'ΔS=${d1s1 - d1s0}',
    );
  } else {
    c.block('D1-pago', 'DW7', 'pago Δwallet 0 até release', d1row ?? {});
  }

  // A5 reorder / negative / type typo reembolso (matriz; classe nova vs DP venda).
  final a5s0 = await c.walletBal(s1);
  final a5b0 = await c.walletBal(b1);
  final insReemb = await c.rest('POST', 'wallet_transactions', jwt: c.buyerJwt,
      body: {
        'wallet_id': b1,
        'amount': 40,
        'type': 'reembolso',
        'description': '$prefix reembolso forge',
        'order_id': d1.oid,
      });
  final insNeg = await c.rest('POST', 'wallet_transactions', jwt: c.sellerJwt,
      body: {
        'wallet_id': s1,
        'amount': -25.5,
        'type': 'reembolso',
        'description': '$prefix negative reembolso',
        'order_id': d1.oid,
      });
  final insTypo = await c.rest('POST', 'wallet_transactions', jwt: c.sellerJwt,
      body: {
        'wallet_id': s1,
        'amount': 12,
        'type': 'Reembolso',
        'description': '$prefix type typo',
        'order_id': d1.oid,
      });
  final a5s1 = await c.walletBal(s1);
  final a5b1 = await c.walletBal(b1);
  final a5Open = (a5s1 - a5s0).abs() > 0.001 ||
      (a5b1 - a5b0).abs() > 0.001 ||
      minted(insReemb, a5b1 - a5b0);
  c.probe(
    id: 'A5',
    lens: 'DW1',
    edgeRpc: 'POST wallet_transactions type=reembolso / negativo / typo',
    payload:
        'buyer reembolso 40 order=${d1.oid} · seller amount=-25.5 · type=Reembolso 12',
    http:
        'reemb ${insReemb.brief} | neg ${insNeg.brief} | typo ${insTypo.brief}',
    stripeBd: 'ΔS=${a5s1 - a5s0} ΔB=${a5b1 - a5b0}',
    result: a5Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a5Open,
  );
  await c.expectDenied(
    id: 'A5-reembolso-forge',
    lens: 'DW1',
    title: 'JWT INSERT type=reembolso em order paga',
    hit: insReemb,
    actor: 'buyer JWT',
    pre: 'RLS sem INSERT; type reembolso não minta',
    repro: 'POST wallet_transactions type=reembolso order_id=pago',
    delta: a5b1 - a5b0,
  );

  // =========================================================================
  // DW-B Release / retenção
  // =========================================================================
  final flagPatch = await c.rest(
    'PATCH',
    'orders?id=eq.${d1.oid}',
    jwt: c.buyerJwt,
    body: {
      'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
    },
  );
  final b1relB = await c.tryRelease(d1.oid, jwt: c.buyerJwt);
  final b1relS = await c.tryRelease(d1.oid, jwt: c.sellerJwt);
  final d1s2 = await c.walletBal(s1);
  final d1AfterFlag = await c.orderRow(d1.oid);
  final flagStuck =
      d1AfterFlag?['wallet_release_processed_at'] != null && flagPatch.ok;
  final b1Open = ((b1relB.json == true || b1relS.json == true) &&
          (d1s2 - d1s1) > 0) ||
      (flagStuck && flagPatch.list.isNotEmpty);
  c.probe(
    id: 'B1',
    lens: 'DW2',
    edgeRpc: 'PATCH wallet_release_processed_at JWT + release em pago',
    payload: 'buyer PATCH flag + release em status=pago ${d1.oid}',
    http:
        'flag ${flagPatch.brief} | buyer ${b1relB.brief} | seller ${b1relS.brief}',
    stripeBd:
        'ΔS=${d1s2 - d1s1} flag=${d1AfterFlag?['wallet_release_processed_at']} status=${d1AfterFlag?['status']}',
    result: b1Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: b1Open,
  );
  if (b1Open) {
    c.hold(
      id: 'B1-early-or-flag',
      lens: 'DW2',
      severity: 'P0',
      title: 'Release cedo ou PATCH flag wallet_release_processed_at',
      actor: 'buyer/seller JWT',
      pre: 'flag imutável; release exige concluido',
      repro: 'PATCH orders.wallet_release_processed_at; rpc release em pago',
      expected: '0 rows; release false; Δ=0',
      obtained: 'flag=${flagPatch.brief} Δ=${d1s2 - d1s1}',
    );
  } else {
    c.block('B1-early', 'DW2', 'release pago + PATCH flag recusados', b1relB);
  }

  HttpHit? b3hit;
  if (s2 != null && c.seller2Jwt != null) {
    b3hit = await c.tryRelease(d1.oid, jwt: c.seller2Jwt);
  } else {
    b3hit = HttpHit(0, 'no seller2', {'error': 'no seller2'});
  }
  final d1s3 = await c.walletBal(s1);
  final b3Open = b3hit.json == true && (d1s3 - d1s2) > 0;
  c.probe(
    id: 'B3',
    lens: 'DW5',
    edgeRpc: 'batata_release_seller_wallet_for_order JWT seller2',
    payload: 'seller2 release order S1/B1 ${d1.oid}',
    http: b3hit,
    stripeBd: 'ΔS=${d1s3 - d1s2}',
    result: b3Open ? 'FAIL' : 'HOLD',
    countFinding: b3Open,
  );
  await c.expectDenied(
    id: 'B3-seller2',
    lens: 'DW5',
    title: 'seller2 release order alheia',
    hit: b3hit,
    actor: 'seller2 JWT',
    pre: 'auth.uid deve ser buyer_id',
    repro: 'rpc release JWT seller2',
    openIf: (h) => h.json == true,
    delta: d1s3 - d1s2,
  );

  // B4: concluido+mão, 2× paralelo + 1 sequencial.
  final b4 = await mustPay(c, 'DW6');
  await c.rest('PATCH', 'orders?id=eq.${b4.oid}', service: true, body: {
    'status': 'concluido',
    'shipping_method': 'entrega em mão',
    'shipped_at': DateTime.now().toUtc().toIso8601String(),
    'completed_at': DateTime.now().toUtc().toIso8601String(),
  }, prefer: 'return=minimal');
  final b4s0 = await c.walletBal(s1);
  final pairRel = await Future.wait([
    c.tryRelease(b4.oid, jwt: c.buyerJwt),
    c.tryRelease(b4.oid, jwt: c.buyerJwt),
  ]);
  final b4s1 = await c.walletBal(s1);
  final rel3 = await c.tryRelease(b4.oid, jwt: c.sellerJwt);
  final b4s2 = await c.walletBal(s1);
  final trueCount =
      pairRel.where((h) => h.json == true).length + (rel3.json == true ? 1 : 0);
  final doubleCredit = (b4s2 - b4s0) > 5.05 || trueCount > 1 && (b4s2 - b4s1) > 0;
  c.probe(
    id: 'B4',
    lens: 'DW6',
    edgeRpc: 'release ∥ ×2 buyer + 1× seller sequencial (concluido+mão)',
    payload: 'Future.wait 2× buyer + seller seq order ${b4.oid}',
    http:
        'p0 ${pairRel[0].brief} | p1 ${pairRel[1].brief} | seq ${rel3.brief}',
    stripeBd:
        'Δpar=${b4s1 - b4s0} Δseq=${b4s2 - b4s1} trueCount=$trueCount',
    result: doubleCredit ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: doubleCredit,
  );
  if (doubleCredit) {
    c.hold(
      id: 'B4-double-release-parallel',
      lens: 'DW3',
      severity: 'P0',
      title: 'Release paralelo creditou mais que uma vez',
      actor: 'buyer JWT ×2 ∥ + seller seq',
      pre: 'wallet_release_processed_at + unique (wallet,order,type)',
      repro: 'Future.wait 2× rpc release em concluido; depois 3.º',
      expected: '1 crédito; gémeos false; Δseq=0',
      obtained: 'trueCount=$trueCount Δpar=${b4s1 - b4s0} Δseq=${b4s2 - b4s1}',
    );
  } else {
    c.block('B4-idem-par', 'DW6', 'release∥ sem double credit', pairRel[0]);
  }

  // D2 seller refund 1×
  final d2 = await mustPay(c, 'DW7');
  final prodBefore = await c.productRow(d2.pid);
  final d2s0 = await c.walletBal(s1);
  final qtyBefore = numOf(prodBefore?['quantity']) ?? 0;
  final ref1 = await c.refundOrder(d2.oid, jwt: c.sellerJwt);
  final d2row = await c.orderRow(d2.oid);
  final prodAfter = await c.productRow(d2.pid);
  final d2s1 = await c.walletBal(s1);
  final qtyAfter = numOf(prodAfter?['quantity']) ?? 0;
  final refunded = ref1.ok &&
      ref1.map?['ok'] != false &&
      (d2row?['stripe_refund_id'] != null &&
          '${d2row?['stripe_refund_id']}'.isNotEmpty);
  final d2WalletBad = (d2s1 - d2s0) > 0;
  final d2Fail = !refunded || d2WalletBad;
  c.probe(
    id: 'D2',
    lens: 'DW7',
    edgeRpc: 'refund-order seller 1×',
    payload: 'seller JWT order pago ${d2.oid}',
    http: ref1,
    stripeBd:
        'refund_id=${d2row?['stripe_refund_id']} status=${d2row?['status']} qty $qtyBefore→$qtyAfter ΔS=${d2s1 - d2s0}',
    result: d2Fail ? 'FAIL' : 'HOLD',
    countFinding: d2Fail,
  );
  if (d2Fail) {
    c.hold(
      id: 'D2-refund',
      lens: 'DW7',
      severity: d2WalletBad ? 'P0' : 'P1',
      title: d2WalletBad
          ? 'Seller refund 1× aumentou wallet'
          : 'Seller refund 1× falhou',
      actor: 'seller JWT',
      pre: 'refund seller-only; stock volta; Δwallet ≤0',
      repro: 'POST refund-order',
      expected: 're_ + stock restore + Δwallet≤0',
      obtained: ref1.brief,
    );
  } else {
    c.block('D2-refund', 'DW7', 'refund 1× coerente', {
      'refund_id': d2row?['stripe_refund_id'],
      'qty': '$qtyBefore→$qtyAfter',
      'delta': d2s1 - d2s0,
    });
  }

  // B2 race release∥refund
  final race = await mustPay(c, 'DW3');
  final raceS0 = await c.walletBal(s1);
  final raced = await Future.wait([
    c.refundOrder(race.oid, jwt: c.sellerJwt),
    c.tryRelease(race.oid, jwt: c.buyerJwt),
    c.tryRelease(race.oid, jwt: c.sellerJwt),
  ]);
  final raceS1 = await c.walletBal(s1);
  final raceRow = await c.orderRow(race.oid);
  final raceRefunded = raced[0].ok && raced[0].map?['ok'] != false;
  final raceReleased = raced[1].json == true || raced[2].json == true;
  final raceOpen = raceReleased && (raceS1 - raceS0) > 0;
  c.probe(
    id: 'B2',
    lens: 'DW3',
    edgeRpc: 'refund-order ∥ release',
    payload: 'Future.wait seller refund + buyer/seller release ${race.oid}',
    http: raced.map((h) => h.brief).toList(),
    stripeBd:
        'refunded=$raceRefunded released=$raceReleased Δ=${raceS1 - raceS0} refund_id=${raceRow?['stripe_refund_id']}',
    result: raceOpen ? 'FAIL' : 'HOLD',
    countFinding: raceOpen,
  );
  if (raceOpen) {
    c.hold(
      id: 'B2-race-rel-refund',
      lens: 'DW3',
      severity: 'P0',
      title: 'Race refund∥release: crédito + refund',
      actor: 'seller refund + buyer release',
      pre: 'release inelegível em pago; refund seller-only',
      repro: 'Future.wait refund-order + release',
      expected: 'refund OU nada; release false; Δ≤0',
      obtained: 'Δ=${raceS1 - raceS0} released=$raceReleased',
    );
  } else {
    c.block('B2-race', 'DW3', 'race sem double credit', raced[0]);
  }

  // B5 classe_nova: release∥disputa em concluido+mão (crédito vs disputa aberta).
  final b5 = await mustPay(c, 'DW3');
  await c.rest('PATCH', 'orders?id=eq.${b5.oid}', service: true, body: {
    'status': 'concluido',
    'shipping_method': 'entrega em mão',
    'shipped_at': DateTime.now().toUtc().toIso8601String(),
    'completed_at': DateTime.now().toUtc().toIso8601String(),
  }, prefer: 'return=minimal');
  final b5s0 = await c.walletBal(s1);
  final b5pair = await Future.wait([
    c.tryRelease(b5.oid, jwt: c.buyerJwt),
    c.insertDispute(orderId: b5.oid, jwt: c.buyerJwt),
  ]);
  final b5s1 = await c.walletBal(s1);
  final b5row = await c.orderRow(b5.oid);
  final b5released = b5pair[0].json == true;
  final b5dispOk = b5pair[1].ok && b5pair[1].firstId != null;
  // FAIL só se crédito E disputa aberta no mesmo instante (dinheiro+claim).
  final b5Open = b5released && (b5s1 - b5s0) > 0 && b5dispOk;
  c.probe(
    id: 'B5',
    lens: 'DW3',
    edgeRpc: 'release ∥ POST order_disputes (concluido+mão)',
    payload: 'Future.wait buyer release + disputa ${b5.oid}',
    http: 'rel ${b5pair[0].brief} | disp ${b5pair[1].brief}',
    stripeBd:
        'Δ=${b5s1 - b5s0} released=$b5released disp=$b5dispOk status=${b5row?['status']}',
    result: b5Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: b5Open,
  );
  if (b5Open) {
    c.hold(
      id: 'B5-release-disputa',
      lens: 'DW3',
      severity: 'P1',
      title: 'Release creditou com disputa aberta em paralelo',
      actor: 'buyer release ∥ disputa',
      pre: 'disputa aberta deve bloquear crédito ou a disputa recusa',
      repro: 'Future.wait release + POST order_disputes em concluido',
      expected: 'não (crédito E disputa aberta)',
      obtained: 'Δ=${b5s1 - b5s0} disp=${b5pair[1].brief}',
    );
  } else {
    c.block('B5-rel-disp', 'DW3', 'release∥disputa sem crédito+claim',
        b5pair[0]);
  }

  // =========================================================================
  // DW-C Payout / Connect — forges novas: amount negativo, case-fold ASCII,
  // GET amount qs, crash_inject sem secret. NÃO Coptic/charset.
  // =========================================================================
  await c.ensureWalletBalance(s1, 8);
  final c0 = await c.walletBal(s1);
  final tids0 = await c.transferIds(s1);
  final ownBefore = await c.walletRow(s1);
  final ownAcct = '${ownBefore?['stripe_account_id'] ?? ''}';
  final others = await c.otherConnectAccounts(s1);
  final alienAcct = others.isNotEmpty
      ? '${others.first['stripe_account_id']}'
      : 'acct_1UB7nWHKe5ETfHI5';

  final over = await c.connect({
    'amount': 99999999,
    'idempotency_key': 'rtdwOverbal1738keyxx',
  });
  final negAmt = await c.connect({
    'amount': -100,
    'idempotency_key': 'rtdwNegAmt1738keyxxx',
  });
  final arrAmt = await c.connect({
    'amount': [100],
    'idempotency_key': 'rtdwArrAmt1738keyxxx',
  });
  final c1bal = await c.walletBal(s1);
  final tidsOver = await c.transferIds(s1);
  final overXfer = tidsOver.difference(tids0);
  final c1Open = over.payoutOk ||
      negAmt.payoutOk ||
      arrAmt.payoutOk ||
      overXfer.isNotEmpty;
  c.probe(
    id: 'C1',
    lens: 'DW4',
    edgeRpc: 'create-connect-account overbalance / amount=-100 / amount=[100]',
    payload: '99999999 vs saldo $c0 · negativo · array (não charset/Coptic)',
    http: 'over ${over.brief} | neg ${negAmt.brief} | arr ${arrAmt.brief}',
    stripeBd: 'Δ=${c1bal - c0} new_tr=${overXfer.toList()}',
    result: c1Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: c1Open,
  );
  if (c1Open) {
    c.hold(
      id: 'C1-over-neg-arr',
      lens: 'DW4',
      severity: 'P0',
      title: 'Payout overbalance / negativo / array criou Transfer',
      actor: 'seller JWT',
      pre: 'amount≤0 / array inválido; overbalance insufficient',
      repro: 'POST amount=99999999; amount=-100; amount=[100]',
      expected: '400 Δ=0 0 tr_',
      obtained: '${over.brief} ${negAmt.brief} ${arrAmt.brief}',
    );
  } else {
    c.block('C1-over', 'DW4', 'over/neg/array recusados', over);
  }

  final destHit = await c.connect({
    'amount': 100,
    'idempotency_key': 'rtdwDestAlien1738keyx',
    'destination': alienAcct,
    'stripe_account_id': alienAcct,
    'account': alienAcct,
    'on_behalf_of': alienAcct,
    'iban': 'PT50000201231234567890154',
    'transfer_data': {'destination': alienAcct},
    'currency': 'usd',
    'metadata': {'fleaber_user_id': s2 ?? 'hostile-dw'},
  });
  final c2bal = await c.walletBal(s1);
  final tidsDest = await c.transferIds(s1);
  final destNew = tidsDest.difference(tidsOver);
  c.probe(
    id: 'C2',
    lens: 'DW4',
    edgeRpc: 'create-connect-account dest/IBAN/on_behalf_of/transfer_data',
    payload:
        'dest=$alienAcct iban PT50… on_behalf_of transfer_data usd amount=100 (sem user_id)',
    http: destHit,
    stripeBd:
        'Δ=${c2bal - c1bal} new_tr=${destNew.toList()} own_acct=$ownAcct',
    result: destNew.length > 1 ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: destNew.length > 1,
  );
  if (destNew.length > 1) {
    c.hold(
      id: 'C2-dest',
      lens: 'DW4',
      severity: 'P0',
      title: 'Destination/IBAN alheio criou Transfer extra',
      actor: 'seller JWT',
      pre: 'Transfer usa accountId resolvido do JWT',
      repro: 'POST dest+iban+on_behalf_of+transfer_data alheio',
      expected: '≤1 Transfer própria',
      obtained: destHit.brief,
    );
  } else {
    c.block('C2-dest', 'DW4', 'dest/IBAN hostil ignorado ou 1 própria', destHit);
  }

  await c.ensureWalletBalance(s1, 5);
  final par0 = await c.walletBal(s1);
  final tidsP0 = await c.transferIds(s1);
  const sameKey = 'rtdwParallelSame1738k';
  final pairSame = await Future.wait([
    c.connect({'amount': 100, 'idempotency_key': sameKey}),
    c.connect({'amount': 100, 'idempotency_key': sameKey}),
  ]);
  final par1 = await c.walletBal(s1);
  final tidsP1 = await c.transferIds(s1);
  final newSame = tidsP1.difference(tidsP0);
  final c3Open = newSame.length > 1 || (par0 - par1) > 1.05;
  c.probe(
    id: 'C3',
    lens: 'DW3',
    edgeRpc: 'create-connect-account ∥ mesma idempotency_key',
    payload: 'Future.wait amount=100 key=$sameKey',
    http: pairSame.map((h) => h.brief).toList(),
    stripeBd: 'Δ=${par1 - par0} new_tr=${newSame.toList()} n=${newSame.length}',
    result: c3Open ? 'FAIL' : 'HOLD',
    countFinding: c3Open,
  );
  if (c3Open) {
    c.hold(
      id: 'C3-dual-payout',
      lens: 'DW3',
      severity: 'P0',
      title: 'Payout paralelo mesma key → 2 Transfers',
      actor: 'seller JWT ×2',
      pre: 'hash SHA-256 userId+key; ledger unique',
      repro: 'Future.wait POST mesma idempotency_key',
      expected: '1 tr_',
      obtained: 'n=${newSame.length} ${pairSame.map((h) => h.brief).toList()}',
    );
  } else {
    c.block('C3-idem', 'DW6', 'payout∥ mesma key ≤1 tr_', pairSame[0]);
  }

  // C4: keys ASCII case-fold (NÃO Coptic) em paralelo com saldo=1€.
  await c.setWalletBalance(s1, 1.00);
  final fold0 = await c.walletBal(s1);
  final tidsF0 = await c.transferIds(s1);
  final pairFold = await Future.wait([
    c.connect({'amount': 100, 'idempotency_key': 'rtdwFold1738keyAA'}),
    c.connect({'amount': 100, 'idempotency_key': 'RTDWFOLD1738KEYAA'}),
  ]);
  final fold1 = await c.walletBal(s1);
  final tidsF1 = await c.transferIds(s1);
  final newFold = tidsF1.difference(tidsF0);
  final foldOpen = newFold.length > 1 || fold1 < -0.001;
  c.probe(
    id: 'C4',
    lens: 'DW6',
    edgeRpc: 'payout∥ keys ASCII case-fold distintas saldo=1,00',
    payload:
        'Future.wait 100¢ rtdwFold1738keyAA vs RTDWFOLD1738KEYAA (sem Coptic/charset)',
    http: pairFold.map((h) => h.brief).toList(),
    stripeBd:
        'bal $fold0→$fold1 new_tr=${newFold.toList()} n=${newFold.length}',
    result: foldOpen ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: foldOpen,
  );
  if (foldOpen) {
    c.hold(
      id: 'C4-casefold-double',
      lens: 'DW6',
      severity: 'P0',
      title: 'Keys ASCII case-fold geraram 2 Transfers / saldo negativo',
      actor: 'seller JWT ×2',
      pre: 'idempotency toLowerCase; 1€ não paga 2×',
      repro: 'saldo 1€; 2 POST 100¢ keys só diferem em maiúsculas',
      expected: '≤1 Transfer; saldo≥0',
      obtained: 'n=${newFold.length} bal=$fold1',
    );
  } else {
    c.block('C4-casefold', 'DW6', 'case-fold ≤1 tr_ saldo≥0', pairFold[0]);
  }

  // C5 onboarding reuse + GET amount qs + crash_inject SEM secret.
  final onb1 = await c.connect(<String, Object?>{});
  final url1 = onb1.onboardingUrl;
  final acct1 = onb1.map?['stripeAccountId']?.toString();
  final onb2 = await c.connect(<String, Object?>{});
  HttpHit? urlGet;
  if (url1 != null && url1.startsWith('http')) {
    urlGet = await c.httpGetExternal(url1);
  }
  final onbGetAmt = await c.connect(
    <String, Object?>{},
    method: 'GET',
    qs: 'wallet_return=1&amount=100&idempotency_key=rtdwGetAmt1738xxxx',
  );
  final crashNoSecret = await c.connect({
    'amount': 100,
    'idempotency_key': 'rtdwCrashNoSec1738xx',
    'crash_inject': 'after_debit_before_stripe',
  });
  final onbAnon = await c.connect(<String, Object?>{}, auth: false);
  final reuseBody = await c.connect({
    'url': url1,
    'account_link': url1,
    'stripeAccountId': acct1,
    'account': acct1,
  }, jwt: c.seller2Jwt ?? c.buyerJwt);
  final getPaidOut = onbGetAmt.payoutOk;
  final anonOnboarded = onbAnon.ok && onbAnon.onboardingUrl != null;
  final crashWorked = crashNoSecret.map?['crash_inject'] == true ||
      '${crashNoSecret.map?['code']}' == 'payout_pending_reconcile';
  final c5Open = getPaidOut || anonOnboarded || crashWorked;
  c.probe(
    id: 'C5',
    lens: 'DW4',
    edgeRpc: 'onboarding reuse + GET amount=100 + crash_inject sem secret',
    payload:
        'POST {} ×2 · GET url · GET ?amount=100 · crash_inject after_debit sem header secret · anon · S2 reuse',
    http:
        'onb1 ${onb1.brief} | onb2 ${onb2.brief} | getUrl ${urlGet?.brief} | GET ${onbGetAmt.brief} | crash ${crashNoSecret.brief} | anon ${onbAnon.brief} | reuse ${reuseBody.brief}',
    stripeBd: 'acct1=$acct1 crashWorked=$crashWorked getPaidOut=$getPaidOut',
    result: c5Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: c5Open,
  );
  if (c5Open) {
    c.hold(
      id: 'C5-onboard-get-crash',
      lens: 'DW4',
      severity: 'P1',
      title: 'GET amount payout / anon onboard / crash_inject sem secret',
      actor: 'anon/seller2/seller',
      pre: 'GET não cria Transfer; crash_inject exige secret; anon deny',
      repro: 'GET ?amount=100; POST crash_inject sem secret; anon POST {}',
      expected: 'GET sem payout; crash ignorado; anon 400',
      obtained:
          'GET=${onbGetAmt.brief} crash=${crashNoSecret.brief} anon=${onbAnon.brief}',
    );
  } else {
    c.block('C5-onboard', 'DW4', 'onboarding/GET/crash presos', onb1);
  }

  // Extra classe_nova: stripe-webhook sem assinatura (tip/order mint).
  final a4sWh0 = await c.walletBal(s1);
  final wh = await c.stripeWebhookForge({
    'id': 'evt_rtdw_fake_1738',
    'object': 'event',
    'type': 'checkout.session.completed',
    'data': {
      'object': {
        'id': tipSid ?? 'cs_test_rtdw_fake',
        'object': 'checkout.session',
        'payment_status': 'paid',
        'amount_total': 9900,
        'metadata': {
          'fleaber_tip_id': tipId ?? fakeOid,
          'seller_id': s1,
        },
      },
    },
  });
  final a4sWh1 = await c.walletBal(s1);
  final whOpen = (a4sWh1 - a4sWh0) > 0 ||
      (wh.ok && wh.map?['ok'] == true && wh.map?['error'] == null);
  c.probe(
    id: 'A6',
    lens: 'DW1',
    edgeRpc: 'POST stripe-webhook sem stripe-signature válida',
    payload: 'checkout.session.completed tip fake 99€',
    http: wh,
    stripeBd: 'ΔS=${a4sWh1 - a4sWh0}',
    result: whOpen && (a4sWh1 - a4sWh0) > 0 ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: (a4sWh1 - a4sWh0) > 0,
  );
  if ((a4sWh1 - a4sWh0) > 0) {
    c.hold(
      id: 'A6-webhook-forge',
      lens: 'DW1',
      severity: 'P0',
      title: 'Webhook sem assinatura creditou wallet',
      actor: 'anon/apikey',
      pre: 'constructEventAsync exige whsec',
      repro: 'POST stripe-webhook sem signature',
      expected: '400 missing/invalid_signature Δ=0',
      obtained: '${wh.brief} Δ=${a4sWh1 - a4sWh0}',
    );
  } else {
    c.block('A6-webhook', 'DW1', 'webhook forge recusado', wh);
  }

  // Extra: credit∥debit — payout JWT ∥ RPC credit (deve 403) em paralelo.
  await c.ensureWalletBalance(s1, 3);
  final cd0 = await c.walletBal(s1);
  final tidsCd0 = await c.transferIds(s1);
  final cdPair = await Future.wait([
    c.connect({
      'amount': 100,
      'idempotency_key': 'rtdwCreditDebit1738k',
    }),
    c.rpc('batata_credit_wallet_once', {
      'p_wallet_id': s1,
      'p_order_id': fakeOid,
      'p_amount': 50,
      'p_type': 'venda',
      'p_description': '$prefix credit||debit',
    }, jwt: c.buyerJwt),
  ]);
  final cd1 = await c.walletBal(s1);
  final tidsCd1 = await c.transferIds(s1);
  final newCd = tidsCd1.difference(tidsCd0);
  final creditHit = cdPair[1];
  final cdOpen = minted(creditHit, cd1 - cd0) && (cd1 - cd0) > 0 ||
      newCd.length > 1 ||
      cd1 > cd0 + 0.001;
  c.probe(
    id: 'C6',
    lens: 'DW3',
    edgeRpc: 'payout ∥ rpc credit_wallet_once',
    payload: 'Future.wait connect 100¢ + JWT credit 50 type=venda',
    http: 'pay ${cdPair[0].brief} | credit ${creditHit.brief}',
    stripeBd: 'Δ=${cd1 - cd0} new_tr=${newCd.toList()}',
    result: cdOpen ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: cdOpen,
  );
  if (cdOpen) {
    c.hold(
      id: 'C6-credit-debit-race',
      lens: 'DW3',
      severity: 'P0',
      title: 'Race payout∥credit mintou saldo',
      actor: 'seller payout + buyer RPC',
      pre: 'credit GRANT service_role; payout próprio',
      repro: 'Future.wait create-connect-account + credit_wallet_once',
      expected: '≤1 tr_ própria; credit 403; Δ≤0 relativamente ao payout',
      obtained: 'Δ=${cd1 - cd0} credit=${creditHit.brief}',
    );
  } else {
    c.block('C6-cd-race', 'DW3', 'payout∥credit sem mint', cdPair[0]);
  }

  await c.endLives();
  await c.dumpAll('pass1.json');
  stdout.writeln(
      'DONE probes=${c.probes.length} findings=${c.findings.where((f) => f['count'] == true).length} classe_nova=${c.classeNova}');
}
