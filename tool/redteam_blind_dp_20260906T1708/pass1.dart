/// RED TEAM CEGO DP pass1 — wallet forge · release · payout · Connect · caixa.
/// Staging only. Stripe TEST. NÃO CORRIGIR. Fase 4 não.
import 'dart:io';
import '_rtdp.dart';

Future<({String oid, String pid, String? pi})> mustPay(
  Rtdp c,
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
  final c = Rtdp.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final s1 = c.sellerId!;
  final b1 = c.buyerId!;
  final s2 = c.seller2Id;
  final fakeOid = '00000000-0000-0000-0000-000000000001';

  stdout.writeln('actors B1=$b1 S1=$s1 B2=${c.buyer2Id} S2=$s2');

  // ---------------------------------------------------------------------------
  // DP-A Wallet forge
  // ---------------------------------------------------------------------------
  final a0s = await c.walletBal(s1);
  final a0b = await c.walletBal(b1);

  final insBuyer = await c.rest('POST', 'wallet_transactions', jwt: c.buyerJwt,
      body: {
        'wallet_id': b1,
        'amount': 50,
        'type': 'venda',
        'description': '$prefix buyer mint',
      });
  final insSeller = await c.rest('POST', 'wallet_transactions', jwt: c.sellerJwt,
      body: {
        'wallet_id': s1,
        'amount': 80,
        'type': 'venda',
        'description': '$prefix seller mint',
      });
  final a1s = await c.walletBal(s1);
  final a1b = await c.walletBal(b1);
  final a1Open = minted(insBuyer, a1b - a0b) || minted(insSeller, a1s - a0s);
  c.probe(
    id: 'A1',
    lens: 'DP1',
    edgeRpc: 'POST wallet_transactions JWT',
    payload: 'buyer+seller INSERT credit 50/80 type=venda',
    http: 'B ${insBuyer.brief} | S ${insSeller.brief}',
    stripeBd: 'ΔB=${a1b - a0b} ΔS=${a1s - a0s}',
    result: a1Open ? 'FAIL' : 'HOLD',
    countFinding: a1Open,
  );
  await c.expectDenied(
    id: 'A1-buyer-insert',
    lens: 'DP1',
    title: 'Buyer JWT INSERT wallet_transactions',
    hit: insBuyer,
    actor: 'buyer JWT',
    pre: 'RLS sem INSERT authenticated',
    repro: 'POST wallet_transactions amount=50',
    delta: a1b - a0b,
  );
  await c.expectDenied(
    id: 'A1-seller-insert',
    lens: 'DP1',
    title: 'Seller JWT INSERT wallet_transactions',
    hit: insSeller,
    actor: 'seller JWT',
    pre: 'RLS sem INSERT authenticated',
    repro: 'POST wallet_transactions amount=80',
    delta: a1s - a0s,
  );

  final creditJwt = await c.rpc('batata_credit_wallet_once', {
    'p_wallet_id': s1,
    'p_order_id': fakeOid,
    'p_amount': 40,
    'p_type': 'venda',
    'p_description': '$prefix credit',
  }, jwt: c.buyerJwt);
  final debitJwt = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': s1,
    'p_amount_cents': 100,
    'p_idempotency_key': 'rtdpdebitforge1708xx',
  }, jwt: c.sellerJwt);
  final tipApply = await c.rpc('batata_wallet_apply_tip_once', {
    'p_wallet_id': s1,
    'p_tip_id': fakeOid,
    'p_amount': 12,
    'p_type': 'gorjeta_recebida',
    'p_description': '$prefix tip forge',
  }, jwt: c.buyerJwt);
  final ensureAlien = await c.rpc('batata_ensure_wallet', {
    'p_user_id': s2 ?? fakeOid,
  }, jwt: c.buyerJwt);
  final a2s = await c.walletBal(s1);
  final a2Open = minted(creditJwt, a2s - a1s) ||
      (debitJwt.ok && debitJwt.map?['ok'] == true) ||
      minted(tipApply, 0);
  c.probe(
    id: 'A2',
    lens: 'DP1',
    edgeRpc: 'rpc credit/debit/tip/ensure JWT',
    payload:
        'credit_wallet_once + payout_debit + apply_tip_once + ensure_wallet alheio',
    http:
        'credit ${creditJwt.brief} | debit ${debitJwt.brief} | tip ${tipApply.brief} | ensure ${ensureAlien.brief}',
    stripeBd: 'ΔS=${a2s - a1s}',
    result: a2Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a2Open,
  );
  await c.expectDenied(
    id: 'A2-credit',
    lens: 'DP1',
    title: 'JWT batata_credit_wallet_once',
    hit: creditJwt,
    actor: 'buyer JWT',
    pre: 'GRANT service_role only',
    repro: 'rpc batata_credit_wallet_once amount=40',
    delta: a2s - a1s,
  );
  await c.expectDenied(
    id: 'A2-payout-debit',
    lens: 'DP1',
    title: 'JWT batata_wallet_payout_debit',
    hit: debitJwt,
    actor: 'seller JWT',
    pre: 'GRANT service_role only',
    repro: 'rpc batata_wallet_payout_debit 100¢',
    openIf: (h) => h.ok && h.map?['ok'] == true,
  );

  final patchBal = await c.rest(
    'PATCH',
    'wallets?id=eq.$s1',
    jwt: c.sellerJwt,
    body: {'balance': 9999.99},
  );
  final patchAvail = await c.rest(
    'PATCH',
    'wallets?id=eq.$s1',
    jwt: c.buyerJwt,
    body: {'balance': 1, 'available': 9999},
  );
  final others = await c.otherConnectAccounts(s1);
  final alienAcct = others.isNotEmpty
      ? '${others.first['stripe_account_id']}'
      : 'acct_1UB7nWHKe5ETfHI5';
  final ownBefore = await c.walletRow(s1);
  final ownAcct = '${ownBefore?['stripe_account_id'] ?? ''}';
  final patchDest = await c.rest(
    'PATCH',
    'wallets?id=eq.$s1',
    jwt: c.sellerJwt,
    body: {'stripe_account_id': alienAcct},
  );
  final a3s = await c.walletBal(s1);
  final destAfter = await c.walletRow(s1);
  final destHijack = '${destAfter?['stripe_account_id']}' == alienAcct &&
      alienAcct.isNotEmpty &&
      alienAcct != ownAcct;
  final a3Open = (a3s - a2s).abs() > 0.001 || destHijack;
  c.probe(
    id: 'A3',
    lens: 'DP1',
    edgeRpc: 'PATCH wallets JWT',
    payload:
        'balance=9999.99 + available=9999 + stripe_account_id=$alienAcct',
    http:
        'bal ${patchBal.brief} | avail ${patchAvail.brief} | dest ${patchDest.brief}',
    stripeBd:
        'ΔS=${a3s - a2s} dest_before=$ownAcct dest_after=${destAfter?['stripe_account_id']} hijack=$destHijack',
    result: a3Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a3Open,
  );
  if (a3Open) {
    c.hold(
      id: 'A3-patch-wallet',
      lens: 'DP1',
      severity: 'P0',
      title: 'JWT PATCH wallets alterou saldo ou dest Connect',
      actor: 'seller/buyer JWT',
      pre: 'RLS wallets sem UPDATE authenticated',
      repro: 'PATCH wallets balance / stripe_account_id',
      expected: '0 rows / 401',
      obtained:
          'Δ=${a3s - a2s} destHijack=$destHijack ${patchBal.brief} ${patchDest.brief}',
    );
  } else {
    c.block('A3-patch', 'DP1', 'PATCH wallets recusado', patchDest);
  }

  // A4 unpaid tip → Δwallet 0
  num a4s0 = await c.walletBal(s1);
  HttpHit? tipCk;
  HttpHit? tipSettle;
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
    }
  } catch (e) {
    c.note('A4.err', 'tip unpaid error', '$e', lens: 'DP7');
  }
  final a4s1 = await c.walletBal(s1);
  final tipSt = tipId == null ? null : await c.tipRow(tipId);
  final a4Credited = (a4s1 - a4s0) > 0 ||
      '${tipSt?['status'] ?? ''}'.toLowerCase() == 'paid' ||
      '${tipSt?['status'] ?? ''}'.toLowerCase() == 'completed';
  c.probe(
    id: 'A4',
    lens: 'DP7',
    edgeRpc: 'create-live-tip-checkout POST+GET unpaid',
    payload: 'live $liveId amount_eur=2 sem pagar Session',
    http: '${tipCk?.brief} settle=${tipSettle?.brief}',
    stripeBd:
        'sid=$tipSid tip=$tipId status=${tipSt?['status']} ΔS=${a4s1 - a4s0}',
    result: a4Credited ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a4Credited,
  );
  if (a4Credited) {
    c.hold(
      id: 'A4-unpaid-tip-mint',
      lens: 'DP7',
      severity: 'P0',
      title: 'Tip unpaid creditou wallet',
      actor: 'buyer JWT',
      pre: 'settle GET unpaid não minta',
      repro: 'POST tip-checkout + GET unpaid session',
      expected: 'tip pending Δwallet 0',
      obtained: 'status=${tipSt?['status']} Δ=${a4s1 - a4s0}',
    );
  } else {
    c.block('A4-unpaid', 'DP7', 'tip unpaid Δ=0', tipCk ?? HttpHit(0, 'no tip', null));
  }

  // classe_nova extra: wallet-funded tip overbalance + self
  final tipOver = await c.rpc('batata_send_live_tip_from_wallet', {
    'p_live_id': liveId ?? fakeOid,
    'p_seller_id': s1,
    'p_amount': 99999,
    'p_message': '$prefix over',
  }, jwt: c.buyerJwt);
  final tipSelf = await c.rpc('batata_send_live_tip_from_wallet', {
    'p_live_id': liveId ?? fakeOid,
    'p_seller_id': s1,
    'p_amount': 2,
    'p_message': '$prefix self',
  }, jwt: c.sellerJwt);
  final a4s2 = await c.walletBal(s1);
  final overOpen = minted(tipOver, a4s2 - a4s1) || minted(tipSelf, a4s2 - a4s1);
  c.probe(
    id: 'A4b',
    lens: 'DP1',
    edgeRpc: 'rpc batata_send_live_tip_from_wallet',
    payload: 'buyer amount=99999 (overbalance) · seller self-tip 2€',
    http: 'over ${tipOver.brief} | self ${tipSelf.brief}',
    stripeBd: 'ΔS=${a4s2 - a4s1}',
    result: overOpen ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: overOpen,
  );
  await c.expectDenied(
    id: 'A4b-over',
    lens: 'DP1',
    title: 'wallet tip amount > saldo',
    hit: tipOver,
    actor: 'buyer JWT',
    pre: 'insufficient_wallet_balance',
    repro: 'rpc send_live_tip_from_wallet 99999',
    openIf: (h) => h.ok && h.firstId != null,
    delta: a4s2 - a4s1,
  );

  final ledIns = await c.rest('POST', 'wallet_payout_ledger', jwt: c.sellerJwt,
      body: {
        'user_id': s1,
        'amount_cents': 100,
        'amount_eur': 1,
        'idempotency_key': 'rtdpledgerforge1708xxxxxxxx',
        'status': 'transferred',
        'stripe_transfer_id': 'tr_rtdp_fake',
      });
  c.probe(
    id: 'A5',
    lens: 'DP1',
    edgeRpc: 'POST wallet_payout_ledger JWT',
    payload: 'seller INSERT ledger transferred tr_fake',
    http: ledIns,
    stripeBd: '',
    result: minted(ledIns, 0) ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: minted(ledIns, 0),
  );
  await c.expectDenied(
    id: 'A5-ledger-insert',
    lens: 'DP1',
    title: 'JWT INSERT wallet_payout_ledger',
    hit: ledIns,
    actor: 'seller JWT',
    pre: 'RLS select-own only',
    repro: 'POST wallet_payout_ledger status=transferred',
  );

  await c.endLives();

  // ---------------------------------------------------------------------------
  // DP-D caixa feliz + DP-B release
  // ---------------------------------------------------------------------------
  final d1s0 = await c.walletBal(s1);
  final d1b0 = await c.walletBal(b1);
  final d1 = await mustPay(c, 'DP7');
  final d1row = await c.orderRow(d1.oid);
  final d1s1 = await c.walletBal(s1);
  final d1b1 = await c.walletBal(b1);
  final d1Paid = c.orderPaid(d1row);
  final d1Pi = d1.pi ?? '${d1row?['stripe_payment_intent_id'] ?? ''}';
  final d1MintOnPay = (d1s1 - d1s0) > 0;
  c.probe(
    id: 'D1',
    lens: 'DP7',
    edgeRpc: 'e2e setup_paid_order (4242 / pm_card_visa)',
    payload: 'PI TEST confirm order=${d1.oid}',
    http: 'status=${d1row?['status']} pi=$d1Pi paid_cents=${d1row?['amount_paid_cents']}',
    stripeBd:
        'ΔS=${d1s1 - d1s0} ΔB=${d1b1 - d1b0} release_at=${d1row?['wallet_release_processed_at']}',
    result: (!d1Paid || d1MintOnPay) ? 'FAIL' : 'HOLD',
    countFinding: !d1Paid || d1MintOnPay,
  );
  if (!d1Paid) {
    c.hold(
      id: 'D1-not-paid',
      lens: 'DP7',
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
      lens: 'DP7',
      severity: 'P0',
      title: 'Pago creditou wallet antes de release',
      actor: 'webhook/trigger',
      pre: 'release só em concluido',
      repro: 'setup_paid_order → wallets.balance',
      expected: 'Δwallet 0 até release',
      obtained: 'ΔS=${d1s1 - d1s0}',
    );
  } else {
    c.block('D1-pago', 'DP7', 'pago Δwallet 0 até release', d1row ?? {});
  }

  // B1 release antes de janela (pago, sem receção)
  final b1relB = await c.tryRelease(d1.oid, jwt: c.buyerJwt);
  final b1relS = await c.tryRelease(d1.oid, jwt: c.sellerJwt);
  final d1s2 = await c.walletBal(s1);
  final b1Open = (b1relB.json == true || b1relS.json == true) &&
      (d1s2 - d1s1) > 0;
  c.probe(
    id: 'B1',
    lens: 'DP2',
    edgeRpc: 'batata_release_seller_wallet_for_order',
    payload: 'release em status=pago sem receção / sem concluido',
    http: 'buyer ${b1relB.brief} | seller ${b1relS.brief}',
    stripeBd: 'ΔS=${d1s2 - d1s1} status=${d1row?['status']}',
    result: b1Open ? 'FAIL' : 'HOLD',
    countFinding: b1Open,
  );
  if (b1Open) {
    c.hold(
      id: 'B1-early-release',
      lens: 'DP2',
      severity: 'P0',
      title: 'Release em pago creditou wallet',
      actor: 'buyer/seller JWT',
      pre: 'release exige concluido + envio/mão',
      repro: 'rpc release na order paga',
      expected: 'false Δ=0',
      obtained: 'buyer=${b1relB.brief} Δ=${d1s2 - d1s1}',
    );
  } else {
    c.block('B1-early', 'DP2', 'release pago recusado', b1relB);
  }

  // B3 seller2 release order alheia
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
    lens: 'DP5',
    edgeRpc: 'batata_release_seller_wallet_for_order JWT seller2',
    payload: 'seller2 release order S1/B1 ${d1.oid}',
    http: b3hit,
    stripeBd: 'ΔS=${d1s3 - d1s2}',
    result: b3Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: b3Open,
  );
  await c.expectDenied(
    id: 'B3-seller2',
    lens: 'DP5',
    title: 'seller2 release order alheia',
    hit: b3hit,
    actor: 'seller2 JWT',
    pre: 'auth.uid deve ser buyer_id',
    repro: 'rpc release JWT seller2',
    openIf: (h) => h.json == true,
    delta: d1s3 - d1s2,
  );

  // B4 double release: fixture concluido + mão, buyer 2×
  final b4 = await mustPay(c, 'DP6');
  await c.rest('PATCH', 'orders?id=eq.${b4.oid}', service: true, body: {
    'status': 'concluido',
    'shipping_method': 'entrega em mão',
    'shipped_at': DateTime.now().toUtc().toIso8601String(),
    'completed_at': DateTime.now().toUtc().toIso8601String(),
  }, prefer: 'return=minimal');
  final b4s0 = await c.walletBal(s1);
  final rel1 = await c.tryRelease(b4.oid, jwt: c.buyerJwt);
  final b4s1 = await c.walletBal(s1);
  final rel2 = await c.tryRelease(b4.oid, jwt: c.buyerJwt);
  final b4s2 = await c.walletBal(s1);
  final doubleCredit = (b4s2 - b4s1) > 0 && rel2.json == true;
  c.probe(
    id: 'B4',
    lens: 'DP6',
    edgeRpc: 'release ×2 JWT buyer (concluido+mão fixture)',
    payload: 'order ${b4.oid} 2× batata_release',
    http: '1 ${rel1.brief} | 2 ${rel2.brief}',
    stripeBd: 'Δ1=${b4s1 - b4s0} Δ2=${b4s2 - b4s1}',
    result: doubleCredit ? 'FAIL' : 'HOLD',
    countFinding: doubleCredit,
  );
  if (doubleCredit) {
    c.hold(
      id: 'B4-double-release',
      lens: 'DP6',
      severity: 'P0',
      title: '2.º release creditou outra vez',
      actor: 'buyer JWT ×2',
      pre: 'wallet_release_processed_at + unique (wallet,order,type)',
      repro: 'rpc release duas vezes em concluido',
      expected: '2.º false Δ=0',
      obtained: 'Δ2=${b4s2 - b4s1} ${rel2.brief}',
    );
  } else {
    c.block('B4-idem', 'DP6', '2.º release sem crédito', rel2);
  }

  // FSM bypass classe_nova: seller PATCH status=concluido then self-release
  final fsm = await mustPay(c, 'DP2');
  final patchConcl = await c.rest(
    'PATCH',
    'orders?id=eq.${fsm.oid}',
    jwt: c.sellerJwt,
    body: {'status': 'concluido'},
  );
  final fsmRel = await c.tryRelease(fsm.oid, jwt: c.sellerJwt);
  final fsmRow = await c.orderRow(fsm.oid);
  final fsmOpen = '${fsmRow?['status']}'.toLowerCase() == 'concluido' &&
      patchConcl.ok &&
      (patchConcl.list.isNotEmpty || patchConcl.map != null);
  c.probe(
    id: 'B5',
    lens: 'DP2',
    edgeRpc: 'PATCH orders.status JWT seller + release',
    payload: 'seller força concluido na order paga ${fsm.oid}',
    http: 'patch ${patchConcl.brief} | rel ${fsmRel.brief}',
    stripeBd: 'status=${fsmRow?['status']}',
    result: fsmOpen ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: fsmOpen,
  );
  if (fsmOpen) {
    c.hold(
      id: 'B5-seller-concluido',
      lens: 'DP2',
      severity: 'P0',
      title: 'Seller JWT PATCH status=concluido',
      actor: 'seller JWT',
      pre: 'buyer/seller não fabricam concluido',
      repro: 'PATCH orders status=concluido',
      expected: '0 rows',
      obtained: '${patchConcl.brief} status=${fsmRow?['status']}',
    );
  } else {
    c.block('B5-fsm', 'DP2', 'seller não força concluido', patchConcl);
  }

  // D2 seller refund 1×
  final d2 = await mustPay(c, 'DP7');
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
  final stockRestored = qtyAfter >= qtyBefore;
  // wallet should not increase; may stay same (never released)
  final d2WalletBad = (d2s1 - d2s0) > 0;
  final d2Fail = !refunded || d2WalletBad;
  c.probe(
    id: 'D2',
    lens: 'DP7',
    edgeRpc: 'refund-order seller 1×',
    payload: 'seller JWT order pago ${d2.oid}',
    http: ref1,
    stripeBd:
        'refund_id=${d2row?['stripe_refund_id']} status=${d2row?['status']} qty $qtyBefore→$qtyAfter ΔS=${d2s1 - d2s0} stock_ok=$stockRestored',
    result: d2Fail ? 'FAIL' : 'HOLD',
    countFinding: d2Fail,
  );
  if (d2Fail) {
    c.hold(
      id: 'D2-refund',
      lens: 'DP7',
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
    c.block('D2-refund', 'DP7', 'refund 1× coerente', {
      'refund_id': d2row?['stripe_refund_id'],
      'qty': '$qtyBefore→$qtyAfter',
      'delta': d2s1 - d2s0,
    });
  }

  // B2 race release∥refund
  final race = await mustPay(c, 'DP3');
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
    lens: 'DP3',
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
      lens: 'DP3',
      severity: 'P0',
      title: 'Race refund∥release: crédito + refund',
      actor: 'seller refund + buyer release',
      pre: 'release inelegível em pago; refund seller-only',
      repro: 'Future.wait refund-order + release',
      expected: 'refund OU nada; release false; Δ≤0',
      obtained: 'Δ=${raceS1 - raceS0} released=$raceReleased',
    );
  } else {
    c.block('B2-race', 'DP3', 'race sem double credit', raced[0]);
  }

  // ---------------------------------------------------------------------------
  // DP-C Payout / Connect
  // ---------------------------------------------------------------------------
  await c.ensureWalletBalance(s1, 8);
  final c0 = await c.walletBal(s1);
  final tids0 = await c.transferIds(s1);

  final over = await c.connect({
    'amount': 99999999,
    'idempotency_key': 'rtdpOverbal1708keyxx',
  });
  final c1bal = await c.walletBal(s1);
  final tidsOver = await c.transferIds(s1);
  final overBalOpen =
      over.payoutOk || (c1bal - c0) < -1 && tidsOver.length > tids0.length;
  // overbalance success would drain more than available — FAIL if transfer created
  final overXfer = tidsOver.difference(tids0);
  c.probe(
    id: 'C1',
    lens: 'DP4',
    edgeRpc: 'create-connect-account amount>available',
    payload: 'amount=99999999 vs saldo $c0',
    http: over,
    stripeBd: 'Δ=${c1bal - c0} new_tr=${overXfer.toList()}',
    result: (over.payoutOk || overXfer.isNotEmpty) ? 'FAIL' : 'HOLD',
    countFinding: over.payoutOk || overXfer.isNotEmpty,
  );
  if (over.payoutOk || overXfer.isNotEmpty) {
    c.hold(
      id: 'C1-overbal',
      lens: 'DP4',
      severity: 'P0',
      title: 'Payout amount > available criou Transfer',
      actor: 'seller JWT',
      pre: 'batata_wallet_payout_debit insufficient_balance',
      repro: 'POST create-connect-account amount=99999999',
      expected: '400 Δ=0 0 tr_',
      obtained: over.brief,
    );
  } else {
    c.block('C1-over', 'DP4', 'payout > saldo recusado', over);
  }

  final destHit = await c.connect({
    'amount': 100,
    'idempotency_key': 'rtdpDestAlien1708keyx',
    'destination': alienAcct,
    'stripe_account_id': alienAcct,
    'account': alienAcct,
    'user_id': s2,
    'currency': 'usd',
    'metadata': {'fleaber_user_id': s2 ?? 'hostile'},
  });
  final c2bal = await c.walletBal(s1);
  final tidsDest = await c.transferIds(s1);
  final destNew = tidsDest.difference(tidsOver);
  // dest alheio no body deve ir para conta própria (HOLD) — FAIL só se 2 dest ou mint
  final destOkOwn = destHit.payoutOk && destNew.length <= 1 && (c2bal - c1bal) >= -1.05;
  c.probe(
    id: 'C2',
    lens: 'DP4',
    edgeRpc: 'create-connect-account dest/metadata hostil',
    payload: 'dest=$alienAcct user_id=$s2 currency=usd amount=100',
    http: destHit,
    stripeBd:
        'Δ=${c2bal - c1bal} new_tr=${destNew.toList()} own_acct=$ownAcct',
    result: destHit.payoutOk && destNew.length > 1 ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: destNew.length > 1,
  );
  if (destNew.length > 1) {
    c.hold(
      id: 'C2-dest',
      lens: 'DP4',
      severity: 'P0',
      title: 'Destination alheio criou Transfer extra',
      actor: 'seller JWT',
      pre: 'Transfer usa accountId resolvido do JWT',
      repro: 'POST dest=acct alheio',
      expected: '≤1 Transfer própria',
      obtained: destHit.brief,
    );
  } else {
    c.block('C2-dest', 'DP4', destOkOwn ? 'dest hostil ignorado (própria)' : 'dest hostil',
        destHit);
  }

  // C3 2× payout paralelo mesma key
  await c.ensureWalletBalance(s1, 5);
  final par0 = await c.walletBal(s1);
  final tidsP0 = await c.transferIds(s1);
  const sameKey = 'rtdpParallelSame1708k';
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
    lens: 'DP3',
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
      lens: 'DP3',
      severity: 'P0',
      title: 'Payout paralelo mesma key → 2 Transfers',
      actor: 'seller JWT ×2',
      pre: 'hash SHA-256 userId+key; ledger unique',
      repro: 'Future.wait POST mesma idempotency_key',
      expected: '1 tr_',
      obtained: 'n=${newSame.length} ${pairSame.map((h) => h.brief).toList()}',
    );
  } else {
    c.block('C3-idem', 'DP6', 'payout∥ mesma key ≤1 tr_', pairSame[0]);
  }

  // C3b classe_nova: duas keys distintas com saldo = 1,00 (overbalance race)
  await c.setWalletBalance(s1, 1.00);
  final ob0 = await c.walletBal(s1);
  final tidsOb0 = await c.transferIds(s1);
  final pairDiff = await Future.wait([
    c.connect({'amount': 100, 'idempotency_key': 'rtdpDiffKeyA1708xxx'}),
    c.connect({'amount': 100, 'idempotency_key': 'rtdpDiffKeyB1708xxx'}),
  ]);
  final ob1 = await c.walletBal(s1);
  final tidsOb1 = await c.transferIds(s1);
  final newDiff = tidsOb1.difference(tidsOb0);
  final obOpen = newDiff.length > 1 || ob1 < -0.001;
  c.probe(
    id: 'C3b',
    lens: 'DP3',
    edgeRpc: 'payout∥ keys distintas saldo=1,00',
    payload: 'Future.wait 100¢ keyA vs keyB com available=1€',
    http: pairDiff.map((h) => h.brief).toList(),
    stripeBd: 'bal $ob0→$ob1 new_tr=${newDiff.toList()} n=${newDiff.length}',
    result: obOpen ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: obOpen,
  );
  if (obOpen) {
    c.hold(
      id: 'C3b-over-race',
      lens: 'DP3',
      severity: 'P0',
      title: 'Race 2 keys debitou mais que o saldo',
      actor: 'seller JWT ×2',
      pre: 'advisory lock / debit atómico',
      repro: 'saldo 1€; 2 POST 100¢ keys distintas em paralelo',
      expected: '≤1 Transfer; saldo≥0',
      obtained: 'n=${newDiff.length} bal=$ob1',
    );
  } else {
    c.block('C3b-over-race', 'DP3', '2 keys ≤1 tr_ saldo≥0', pairDiff[0]);
  }

  // C4 Connect onboarding token reuse
  final onb1 = await c.connect(<String, Object?>{});
  final url1 = onb1.onboardingUrl;
  final acct1 = onb1.map?['stripeAccountId']?.toString();
  final onb2 = await c.connect(<String, Object?>{});
  final url2 = onb2.onboardingUrl;
  HttpHit? urlGet;
  if (url1 != null && url1.startsWith('http')) {
    urlGet = await c.httpGetExternal(url1);
  }
  final onbBuyer = await c.connect(<String, Object?>{}, jwt: c.buyerJwt);
  final onbAnon = await c.connect(<String, Object?>{}, auth: false);
  final onbGet = await c.connect(
    <String, Object?>{},
    method: 'GET',
    qs: 'wallet_return=1',
  );
  final reuseBody = await c.connect({
    'url': url1,
    'account_link': url1,
    'stripeAccountId': acct1,
    'account': acct1,
  }, jwt: c.seller2Jwt ?? c.buyerJwt);
  final c4bal = await c.walletBal(s1);
  // FAIL if GET wallet_return created payout, or anon created account, or buyer got seller acct
  final buyerGotSellerAcct = onbBuyer.ok &&
      onbBuyer.map?['stripeAccountId'] != null &&
      '${onbBuyer.map?['stripeAccountId']}' == acct1 &&
      acct1 != null &&
      acct1.isNotEmpty;
  final anonOnboarded = onbAnon.ok && onbAnon.onboardingUrl != null;
  final getPaidOut = onbGet.payoutOk;
  final c4Open = buyerGotSellerAcct || anonOnboarded || getPaidOut;
  c.probe(
    id: 'C4',
    lens: 'DP4',
    edgeRpc: 'create-connect-account onboarding',
    payload:
        'POST {} ×2 · GET url Stripe · buyer POST {} · anon · GET wallet_return · S2 reuse url/acct',
    http:
        'onb1 ${onb1.brief} | onb2 ${onb2.brief} | getUrl ${urlGet?.brief} | buyer ${onbBuyer.brief} | anon ${onbAnon.brief} | GET ${onbGet.brief} | reuse ${reuseBody.brief}',
    stripeBd:
        'acct1=$acct1 url1==url2=${url1 == url2} ΔS_end=$c4bal vs par1=$par1',
    result: c4Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: c4Open,
  );
  if (c4Open) {
    c.hold(
      id: 'C4-onboarding-reuse',
      lens: 'DP4',
      severity: 'P1',
      title: 'Onboarding Connect reutilizado / anon / GET payout',
      actor: 'buyer/anon/seller2',
      pre: 'AccountLink do JWT; GET não cria Transfer',
      repro: 'POST {} ; GET wallet_return; anon POST; buyer pega acct S1',
      expected: 'anon deny; GET sem payout; acct por JWT',
      obtained:
          'anon=${onbAnon.brief} GET=${onbGet.brief} buyerAcct=${onbBuyer.map?['stripeAccountId']}',
    );
  } else {
    c.block('C4-onboard', 'DP4', 'onboarding preso ao JWT; GET sem payout', onb1);
  }

  // Actor: anon payout amount
  final anonPay = await c.connect({
    'amount': 100,
    'idempotency_key': 'rtdpAnonPay1708keyxxx',
  }, auth: false);
  c.probe(
    id: 'C5',
    lens: 'DP5',
    edgeRpc: 'create-connect-account amount=100 anon',
    payload: 'sem Authorization, amount=100',
    http: anonPay,
    stripeBd: '',
    result: anonPay.payoutOk ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: anonPay.payoutOk,
  );
  await c.expectDenied(
    id: 'C5-anon-payout',
    lens: 'DP5',
    title: 'Anon payout 100¢',
    hit: anonPay,
    actor: 'anon',
    pre: 'Authorization obrigatória',
    repro: 'POST create-connect-account sem JWT',
  );

  await c.endLives();
  await c.dumpAll('pass1.json');
  stdout.writeln(
      'DONE probes=${c.probes.length} findings=${c.findings.where((f) => f['count'] == true).length} classe_nova=${c.classeNova}');
}
