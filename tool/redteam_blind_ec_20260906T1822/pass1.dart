/// RED TEAM CEGO EC pass1 — wallet · release · disputa · payout · Connect pós-DTDY.
/// Staging only. Stripe TEST. NÃO CORRIGIR. Fase 4 não.
/// Anti-atrofia: NÃO correr buyer refund-order 403 · Coptic · charset 400
/// (HOLD 1 linha se B3 clássico só 1 efeito).
import 'dart:io';
import '_rtec.dart';

Future<({String oid, String pid, String? pi})> mustPay(
  Rtec c,
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

void markBothFail(
  Rtec c, {
  required String id,
  required String lens,
  required String title,
  required Map<String, dynamic> oracle,
  required String repro,
  String severity = 'P1',
}) {
  c.hold(
    id: id,
    lens: lens,
    severity: severity,
    title: title,
    actor: 'buyer JWT',
    pre: 'DTDY: mesmo lock; sem (crédito líquido E disputa aberta)',
    repro: repro,
    expected: 'net≤0 OU disputa inexistente/fechada; se crédito já saiu, clawback',
    obtained: oracle,
  );
}

Future<void> main() async {
  final c = Rtec.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final s1 = c.sellerId!;
  final b1 = c.buyerId!;
  final s2 = c.seller2Id;
  final fakeOid = '00000000-0000-0000-0000-00000000ec01';

  stdout.writeln('actors B1=$b1 S1=$s1 B2=${c.buyer2Id} S2=$s2');

  c.skipped.add({
    'id': 'HOLD-anti-atrofia',
    'title':
        'buyer refund-order 403 · Coptic payout key · charset 400 — não corridos',
  });

  // =========================================================================
  // EC-A Forge — ângulos novos vs DW: estorno poison, ledger, clawback JWT,
  // PATCH wallets.balance, GET tip settle.
  // =========================================================================
  final a0s = await c.walletBal(s1);
  final a0b = await c.walletBal(b1);

  final insEstorno = await c.rest('POST', 'wallet_transactions', jwt: c.buyerJwt,
      body: {
        'wallet_id': s1,
        'amount': 999,
        'type': 'estorno',
        'description': '$prefix clawback-poison estorno',
        'order_id': fakeOid,
      });
  final insLedger = await c.rest('POST', 'wallet_payout_ledger', jwt: c.sellerJwt,
      body: {
        'user_id': s1,
        'idempotency_key': 'rtecPoisonLedger1822xxxx',
        'amount_cents': 1,
        'amount_eur': 0.01,
        'status': 'paid',
        'stripe_transfer_id': 'tr_rtec_fake',
      });
  final patchBalBuyer = await c.rest(
    'PATCH',
    'wallets?id=eq.$s1',
    jwt: c.buyerJwt,
    body: {'balance': 8888.88},
  );
  final patchBalSeller = await c.rest(
    'PATCH',
    'wallets?id=eq.$s1',
    jwt: c.sellerJwt,
    body: {'balance': 7777.77},
  );
  final a1s = await c.walletBal(s1);
  final a1b = await c.walletBal(b1);
  final a1Open = (a1s - a0s).abs() > 0.001 ||
      (a1b - a0b).abs() > 0.001 ||
      minted(insEstorno, 0) ||
      minted(insLedger, 0) ||
      (patchBalBuyer.ok && (patchBalBuyer.list.isNotEmpty)) ||
      (patchBalSeller.ok && (patchBalSeller.list.isNotEmpty));
  c.probe(
    id: 'A1',
    lens: 'EC1',
    edgeRpc: 'POST txn estorno + POST payout_ledger + PATCH wallets.balance',
    payload:
        'buyer estorno 999 poison · seller ledger tr_fake · PATCH bal JWT B/S',
    http:
        'estorno ${insEstorno.brief} | ledger ${insLedger.brief} | patchB ${patchBalBuyer.brief} | patchS ${patchBalSeller.brief}',
    stripeBd: 'ΔB=${a1b - a0b} ΔS=${a1s - a0s}',
    result: a1Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a1Open,
  );
  await c.expectDenied(
    id: 'A1-estorno-poison',
    lens: 'EC1',
    title: 'JWT INSERT type=estorno (veneno clawback DTDY)',
    hit: insEstorno,
    actor: 'buyer JWT',
    pre: 'RLS sem INSERT authenticated em wallet_transactions',
    repro: 'POST wallet_transactions type=estorno amount=999',
    delta: a1s - a0s,
  );

  final clawJwt = await c.tryClawbackJwt(fakeOid, jwt: c.buyerJwt);
  final clawSeller = await c.rpc('batata_clawback_seller_wallet_for_order', {
    'p_order_id': fakeOid,
  }, jwt: c.sellerJwt);
  final debitJwt = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': s1,
    'p_amount_cents': 100,
    'p_idempotency_key': 'rtecDebitJwt1822keyxx',
  }, jwt: c.sellerJwt);
  final creditJwt = await c.rpc('batata_credit_wallet_once', {
    'p_wallet_id': s1,
    'p_order_id': fakeOid,
    'p_amount': 40,
    'p_type': 'venda',
    'p_description': '$prefix credit hostil',
  }, jwt: c.buyerJwt);
  final a2s = await c.walletBal(s1);
  final a2Open = minted(clawJwt, a2s - a1s) ||
      minted(creditJwt, a2s - a1s) ||
      minted(debitJwt, 0) && debitJwt.ok ||
      (a2s - a1s).abs() > 0.001;
  c.probe(
    id: 'A2',
    lens: 'EC1',
    edgeRpc:
        'rpc clawback_dispute / clawback_order / payout_debit / credit_once JWT',
    payload:
        'buyer clawback DTDY fakeOid · seller clawback_order · debit 100¢ · credit venda 40',
    http:
        'clawD ${clawJwt.brief} | clawO ${clawSeller.brief} | debit ${debitJwt.brief} | credit ${creditJwt.brief}',
    stripeBd: 'ΔS=${a2s - a1s}',
    result: a2Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a2Open,
  );
  await c.expectDenied(
    id: 'A2-clawback-jwt',
    lens: 'EC1',
    title: 'JWT batata_clawback_seller_release_for_dispute',
    hit: clawJwt,
    actor: 'buyer JWT',
    pre: 'GRANT service_role only (DTDY)',
    repro: 'rpc batata_clawback_seller_release_for_dispute',
    openIf: (h) => h.ok && (h.json == true || h.rpcTrue),
    delta: a2s - a1s,
  );

  final others = await c.otherConnectAccounts(s1);
  final alienAcct = others.isNotEmpty
      ? '${others.first['stripe_account_id']}'
      : 'acct_1UB7nWHKe5ETfHI5';
  final patchStripe = await c.rest(
    'PATCH',
    'wallets?id=eq.$s1',
    jwt: c.buyerJwt,
    body: {'stripe_account_id': alienAcct},
  );
  final patchStripeSelf = await c.rest(
    'PATCH',
    'wallets?id=eq.$s1',
    jwt: c.sellerJwt,
    body: {'stripe_account_id': alienAcct},
  );
  final patchProf = await c.rest(
    'PATCH',
    'profiles?id=eq.$s1',
    jwt: c.sellerJwt,
    body: {'wallet_balance': 4321, 'available_balance': 4321},
  );
  final a3row = await c.walletRow(s1);
  final a3s = await c.walletBal(s1);
  final stripeHijack = '${a3row?['stripe_account_id'] ?? ''}' == alienAcct &&
      (patchStripe.list.isNotEmpty || patchStripeSelf.list.isNotEmpty);
  final a3Open = stripeHijack || (a3s - a2s).abs() > 0.001;
  c.probe(
    id: 'A3',
    lens: 'EC1',
    edgeRpc: 'PATCH wallets.stripe_account_id + profiles wallet_balance',
    payload: 'buyer/seller PATCH dest=$alienAcct · profiles wallet_balance',
    http:
        'wB ${patchStripe.brief} | wS ${patchStripeSelf.brief} | prof ${patchProf.brief}',
    stripeBd: 'ΔS=${a3s - a2s} acct=${a3row?['stripe_account_id']}',
    result: a3Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a3Open,
  );
  if (a3Open) {
    c.hold(
      id: 'A3-wallet-dest',
      lens: 'EC1',
      severity: 'P0',
      title: 'PATCH wallets dest/balance JWT',
      actor: 'buyer/seller JWT',
      pre: 'wallets sem UPDATE policy authenticated',
      repro: 'PATCH wallets.stripe_account_id / balance',
      expected: '0 rows; dest inalterado',
      obtained: patchStripe.brief,
    );
  } else {
    c.block('A3-dest', 'EC1', 'PATCH wallets dest/balance recusado', patchStripe);
  }

  final liveId = await c.insertLive(title: '$prefix tip unpaid');
  HttpHit? tipHit;
  String? tipSid;
  String? tipId;
  if (liveId != null) {
    tipHit = await c.tipCheckout(liveId: liveId, seller: s1, amountEur: 2);
    tipSid = tipHit.map?['session_id']?.toString() ??
        tipHit.map?['checkout_session_id']?.toString();
    tipId = tipHit.map?['tip_id']?.toString() ??
        tipHit.map?['id']?.toString();
    if (tipId != null) c.createdTipIds.add(tipId);
  } else {
    tipHit = HttpHit(0, 'no live', {'error': 'no live'});
  }
  HttpHit? tipSettle;
  if (tipSid != null && tipSid.isNotEmpty) {
    tipSettle = await c.tipSettleGet(tipSid, jwt: c.buyerJwt);
  } else {
    tipSettle = HttpHit(0, 'no session', {'error': 'no session'});
  }
  final a4s = await c.walletBal(s1);
  Map<String, dynamic>? tipRow;
  if (tipId != null) tipRow = await c.tipRow(tipId);
  final a4Open = (a4s - a3s) > 0.001 ||
      '${tipRow?['status'] ?? ''}'.toLowerCase() == 'paid';
  c.probe(
    id: 'A4',
    lens: 'EC7',
    edgeRpc: 'create-live-tip-checkout unpaid + GET settle unpaid',
    payload: 'live $liveId 2€ unpaid; GET checkout_return session',
    http: 'tip ${tipHit.brief} | settle ${tipSettle.brief}',
    stripeBd: 'ΔS=${a4s - a3s} tip_status=${tipRow?['status']} sid=$tipSid',
    result: a4Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a4Open,
  );
  if (a4Open) {
    c.hold(
      id: 'A4-tip-unpaid',
      lens: 'EC7',
      severity: 'P0',
      title: 'Tip unpaid / GET settle creditou wallet',
      actor: 'buyer JWT',
      pre: 'settle só Session paid',
      repro: 'POST tip-checkout 2€; GET unpaid session_id',
      expected: 'pending Δ=0',
      obtained: 'Δ=${a4s - a3s} ${tipRow?['status']}',
    );
  } else {
    c.block('A4-tip', 'EC7', 'tip unpaid Δ=0', tipHit);
  }

  final insTypo = await c.rest('POST', 'wallet_transactions', jwt: c.sellerJwt,
      body: {
        'wallet_id': s1,
        'amount': -25.5,
        'type': 'Estorno',
        'description': '$prefix typo Estorno neg',
      });
  final insVendaNeg = await c.rest('POST', 'wallet_transactions', jwt: c.buyerJwt,
      body: {
        'type': 'venda',
        'amount': -12,
        'wallet_id': s1,
        'order_id': fakeOid,
        'description': '$prefix reorder neg venda',
      });
  final insReemb = await c.rest('POST', 'wallet_transactions', jwt: c.buyerJwt,
      body: {
        'wallet_id': b1,
        'amount': 80,
        'type': 'reembolso',
        'description': '$prefix self mint reembolso',
      });
  final a5s = await c.walletBal(s1);
  final a5b = await c.walletBal(b1);
  final a5Open = (a5s - a4s).abs() > 0.001 ||
      (a5b - a1b).abs() > 0.001 ||
      minted(insTypo, 0) ||
      minted(insVendaNeg, 0) ||
      minted(insReemb, 0);
  c.probe(
    id: 'A5',
    lens: 'EC1',
    edgeRpc: 'POST txn Estorno/venda neg/reembolso self (reorder cols)',
    payload: 'type=Estorno −25.5 · venda −12 · buyer reembolso 80',
    http:
        'typo ${insTypo.brief} | neg ${insVendaNeg.brief} | reemb ${insReemb.brief}',
    stripeBd: 'ΔS=${a5s - a4s} ΔB=${a5b - a1b}',
    result: a5Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a5Open,
  );
  await c.expectDenied(
    id: 'A5-typo-neg',
    lens: 'EC1',
    title: 'JWT mint type typo / negativo / reembolso',
    hit: insReemb,
    actor: 'buyer/seller JWT',
    pre: 'RLS INSERT deny',
    repro: 'POST wallet_transactions Estorno/venda neg/reembolso',
    delta: (a5s - a4s).abs() > (a5b - a1b).abs() ? a5s - a4s : a5b - a1b,
  );

  // =========================================================================
  // EC-D caixa D1 — pago 4242 + depois release legítimo (Δ observado).
  // =========================================================================
  final d1 = await mustPay(c, 'EC7');
  final d1s0 = await c.walletBal(s1);
  final d1row0 = await c.orderRow(d1.oid);
  final d1pago = c.orderPaid(d1row0) && d1row0?['wallet_release_processed_at'] == null;
  c.probe(
    id: 'D1a',
    lens: 'EC7',
    edgeRpc: 'setup_paid_order 4242',
    payload: 'PI ${d1.pi} order ${d1.oid}',
    http: 'status=${d1row0?['status']} pi=${d1.pi}',
    stripeBd: 'ΔS=0 até release status=${d1row0?['status']}',
    result: d1pago && (await c.walletBal(s1)) == d1s0 ? 'HOLD' : 'FAIL',
    countFinding: !d1pago,
  );

  final b1relEarly = await c.tryRelease(d1.oid, jwt: c.buyerJwt);
  final b1relS = await c.tryRelease(d1.oid, jwt: c.sellerJwt);
  final d1s1 = await c.walletBal(s1);
  final b1Open = (b1relEarly.json == true || b1relS.json == true) &&
      (d1s1 - d1s0) > 0;
  c.probe(
    id: 'B1',
    lens: 'EC2',
    edgeRpc: 'release cedo em pago (sem receção)',
    payload: 'buyer+seller rpc release status=pago ${d1.oid}',
    http: 'buyer ${b1relEarly.brief} | seller ${b1relS.brief}',
    stripeBd: 'ΔS=${d1s1 - d1s0}',
    result: b1Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: b1Open,
  );
  if (b1Open) {
    c.hold(
      id: 'B1-early',
      lens: 'EC2',
      severity: 'P0',
      title: 'Release cedo em pago creditou',
      actor: 'buyer/seller JWT',
      pre: 'release exige concluido',
      repro: 'rpc release em pago',
      expected: 'false Δ=0',
      obtained: 'Δ=${d1s1 - d1s0}',
    );
  } else {
    c.block('B1-early', 'EC2', 'release pago recusado', b1relEarly);
  }

  HttpHit b4rel;
  HttpHit b4disp;
  if (s2 != null && c.seller2Jwt != null) {
    b4rel = await c.tryRelease(d1.oid, jwt: c.seller2Jwt);
    b4disp = await c.insertDispute(
      orderId: d1.oid,
      jwt: c.seller2Jwt,
      buyer: s2,
      description: '$prefix seller2 disputa alheia',
    );
  } else {
    b4rel = HttpHit(0, 'no seller2', {'error': 'no seller2'});
    b4disp = HttpHit(0, 'no seller2', {'error': 'no seller2'});
  }
  final d1s2 = await c.walletBal(s1);
  final b4Open = (b4rel.json == true && (d1s2 - d1s1) > 0) ||
      (b4disp.ok && b4disp.firstId != null);
  c.probe(
    id: 'B4',
    lens: 'EC6',
    edgeRpc: 'seller2 release + POST disputa order alheia',
    payload: 'S2 rpc release + insertDispute buyer_id=S2 order ${d1.oid}',
    http: 'rel ${b4rel.brief} | disp ${b4disp.brief}',
    stripeBd: 'ΔS=${d1s2 - d1s1}',
    result: b4Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: b4Open,
  );
  await c.expectDenied(
    id: 'B4-seller2-rel',
    lens: 'EC6',
    title: 'seller2 release order alheia',
    hit: b4rel,
    actor: 'seller2 JWT',
    pre: 'auth.uid deve ser buyer_id',
    repro: 'rpc release JWT seller2',
    openIf: (h) => h.json == true,
    delta: d1s2 - d1s1,
  );
  await c.expectDenied(
    id: 'B4-seller2-disp',
    lens: 'EC6',
    title: 'seller2 INSERT disputa order alheia',
    hit: b4disp,
    actor: 'seller2 JWT',
    pre: 'RLS insert buyer_id=auth.uid e order.buyer_id',
    repro: 'POST order_disputes JWT seller2',
    severityIfOpen: 'P1',
  );

  // D1b — release legítimo após fixture concluido (Δ wallet).
  await c.markConcluidoMao(d1.oid);
  final d1s3 = await c.walletBal(s1);
  final d1rel = await c.tryRelease(d1.oid, jwt: c.buyerJwt);
  final d1s4 = await c.walletBal(s1);
  final d1or = await c.oracleWalletDispute(d1.oid, s1);
  final d1Credited = d1rel.json == true && (d1s4 - d1s3) > 0;
  c.probe(
    id: 'D1',
    lens: 'EC7',
    edgeRpc: 'pago 4242 + release legítimo concluido+mão',
    payload: 'order ${d1.oid} PI ${d1.pi} buyer rpc release',
    http: d1rel,
    stripeBd: 'Δ=${d1s4 - d1s3} oracle=$d1or credited=$d1Credited',
    result: d1Credited ? 'HOLD' : 'FAIL',
    countFinding: !d1Credited,
  );
  if (!d1Credited) {
    c.hold(
      id: 'D1-legit-release',
      lens: 'EC7',
      severity: 'P1',
      title: 'Release legítimo não creditou (oráculo caixa falhou)',
      actor: 'buyer JWT',
      pre: 'concluido + mão → crédito venda',
      repro: 'fixture concluido+mão; rpc release',
      expected: 'true + Δ>0',
      obtained: '${d1rel.brief} Δ=${d1s4 - d1s3}',
    );
  } else {
    c.block('D1-caixa', 'EC7', 'pago 4242 + release Δ observado', d1rel);
  }

  // D3 refund após release (deny ou clawback; sem double).
  final d3s0 = await c.walletBal(s1);
  final d3refS = await c.refundOrder(d1.oid, jwt: c.sellerJwt);
  final d3refB = await c.refundOrder(d1.oid, jwt: c.buyerJwt);
  final d3s1 = await c.walletBal(s1);
  final d3row = await c.orderRow(d1.oid);
  final d3KeepCreditAndRefund = d3refS.ok &&
      d3refS.map?['ok'] != false &&
      (d3s1 - d3s0) >= -0.001 &&
      '${d3row?['stripe_refund_id'] ?? ''}'.startsWith('re_');
  // Buyer refund 403 é HOLD anti-atrofia — não contar.
  final d3Fail = d3KeepCreditAndRefund || (d3s1 - d3s0) > 0.001;
  c.probe(
    id: 'D3',
    lens: 'EC5',
    edgeRpc: 'refund-order após release (seller; buyer não contar 403)',
    payload: 'seller refund order já libertada ${d1.oid}',
    http: 'S ${d3refS.brief} | B ${d3refB.brief}',
    stripeBd:
        'Δ=${d3s1 - d3s0} refund_id=${d3row?['stripe_refund_id']} status=${d3row?['status']}',
    result: d3Fail ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: d3Fail,
  );
  if (d3Fail) {
    c.hold(
      id: 'D3-refund-after-release',
      lens: 'EC5',
      severity: 'P0',
      title: 'Refund após release manteve crédito e criou re_',
      actor: 'seller JWT',
      pre: 'após release: deny shipped/concluido OU clawback',
      repro: 'POST refund-order depois de release em concluido',
      expected: '403 deny; Δ≤0; sem re_ + crédito',
      obtained: d3refS.brief,
    );
  } else {
    c.block('D3-claw-deny', 'EC5', 'refund pós-release deny/clawback', d3refS);
  }

  // =========================================================================
  // EC-B races
  // =========================================================================
  final b5 = await mustPay(c, 'EC2');
  await c.markConcluidoMao(b5.oid);
  final b5s0 = await c.walletBal(s1);
  final pairRel = await Future.wait([
    c.tryRelease(b5.oid, jwt: c.buyerJwt),
    c.tryRelease(b5.oid, jwt: c.buyerJwt),
  ]);
  final b5s1 = await c.walletBal(s1);
  final rel3 = await c.tryRelease(b5.oid, jwt: c.sellerJwt);
  final b5s2 = await c.walletBal(s1);
  final trueCount =
      pairRel.where((h) => h.json == true).length + (rel3.json == true ? 1 : 0);
  final doubleCredit =
      (b5s2 - b5s0) > 5.05 || (trueCount > 1 && (b5s2 - b5s1) > 0);
  c.probe(
    id: 'B5',
    lens: 'EC2',
    edgeRpc: 'double release ∥ ×2 + sequencial',
    payload: 'Future.wait 2× buyer + seller seq ${b5.oid}',
    http: 'p0 ${pairRel[0].brief} | p1 ${pairRel[1].brief} | seq ${rel3.brief}',
    stripeBd: 'Δpar=${b5s1 - b5s0} Δseq=${b5s2 - b5s1} trueCount=$trueCount',
    result: doubleCredit ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: doubleCredit,
  );
  if (doubleCredit) {
    c.hold(
      id: 'B5-double-release',
      lens: 'EC2',
      severity: 'P0',
      title: 'Release paralelo creditou mais que uma vez',
      actor: 'buyer JWT ×2',
      pre: '1 crédito; gémeos false',
      repro: 'Future.wait 2× rpc release concluido',
      expected: 'trueCount=1 Δseq=0',
      obtained: 'trueCount=$trueCount Δ=${b5s2 - b5s0}',
    );
  } else {
    c.block('B5-idem', 'EC2', 'double release 1 crédito', pairRel[0]);
  }

  final race = await mustPay(c, 'EC3');
  final raceS0 = await c.walletBal(s1);
  final raced = await Future.wait([
    c.refundOrder(race.oid, jwt: c.sellerJwt),
    c.tryRelease(race.oid, jwt: c.buyerJwt),
  ]);
  final raceS1 = await c.walletBal(s1);
  final raceRow = await c.orderRow(race.oid);
  final raceOpen = (raced[1].json == true) && (raceS1 - raceS0) > 0;
  c.probe(
    id: 'B2',
    lens: 'EC3',
    edgeRpc: 'release ∥ refund mesma order',
    payload: 'Future.wait seller refund + buyer release ${race.oid}',
    http: raced.map((h) => h.brief).toList(),
    stripeBd:
        'Δ=${raceS1 - raceS0} refund_id=${raceRow?['stripe_refund_id']}',
    result: raceOpen ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: raceOpen,
  );
  if (raceOpen) {
    c.hold(
      id: 'B2-rel-refund',
      lens: 'EC3',
      severity: 'P0',
      title: 'Race refund∥release: crédito + refund',
      actor: 'seller refund + buyer release',
      pre: 'um efeito; Δ≤0 se refund',
      repro: 'Future.wait refund-order + release',
      expected: 'refund OU nada; release false',
      obtained: 'Δ=${raceS1 - raceS0}',
    );
  } else {
    c.block('B2-race', 'EC3', 'refund∥release sem crédito', raced[0]);
  }

  // B3 — reteste DW 0ms + 50ms. Oráculo: NÃO (net>0 E disputa aberta).
  final b30 = await mustPay(c, 'EC3');
  await c.markConcluidoMao(b30.oid);
  final b30s0 = await c.walletBal(s1);
  final b30pair = await c.raceReleaseDispute(b30.oid, delayMs: 0);
  final b30s1 = await c.walletBal(s1);
  final b30or = await c.oracleWalletDispute(b30.oid, s1);
  final b30both = b30or['both'] == true;
  c.probe(
    id: 'B3',
    lens: 'EC3',
    edgeRpc: 'release ∥ disputa paralelo 0ms (reteste DW + oráculo net+open)',
    payload: 'Future.wait buyer release + POST disputa ${b30.oid}',
    http: 'rel ${b30pair[0].brief} | disp ${b30pair[1].brief}',
    stripeBd: 'Δ=${b30s1 - b30s0} oracle=$b30or',
    result: b30both ? 'FAIL' : 'HOLD',
    classeNova: false,
    countFinding: b30both,
  );
  if (b30both) {
    markBothFail(
      c,
      id: 'B3-0ms-both',
      lens: 'EC3',
      title: 'Release∥disputa 0ms: crédito líquido + disputa aberta',
      oracle: b30or,
      repro: 'Future.wait release + POST order_disputes delay=0',
    );
  } else {
    c.block('B3-0ms', 'EC3', '0ms sem (net>0 ∧ open) — 1 linha reteste', b30or);
  }

  final b350 = await mustPay(c, 'EC3');
  await c.markConcluidoMao(b350.oid);
  final b350s0 = await c.walletBal(s1);
  final b350pair = await c.raceReleaseDispute(b350.oid, delayMs: 50);
  final b350s1 = await c.walletBal(s1);
  final b350or = await c.oracleWalletDispute(b350.oid, s1);
  final b350both = b350or['both'] == true;
  c.probe(
    id: 'B3b',
    lens: 'EC3',
    edgeRpc: 'release ∥ disputa delay 50ms (release primeiro)',
    payload: 'release imediato; disputa +50ms ${b350.oid}',
    http: 'rel ${b350pair[0].brief} | disp ${b350pair[1].brief}',
    stripeBd: 'Δ=${b350s1 - b350s0} oracle=$b350or',
    result: b350both ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: b350both,
  );
  if (b350both) {
    markBothFail(
      c,
      id: 'B3-50ms-both',
      lens: 'EC3',
      title: 'Release∥disputa 50ms: crédito líquido + disputa aberta',
      oracle: b350or,
      repro: 'release; 50ms; POST disputa',
    );
  } else {
    c.block('B3-50ms', 'EC3', '50ms sem (net>0 ∧ open)', b350or);
  }

  // D2 — estado final após B3 (sem double credit).
  final d2net = (numOf(b30or['net']) ?? 0) + (numOf(b350or['net']) ?? 0);
  final d2double = d2net > 5.05 &&
      (numOf(b30or['venda']) ?? 0) > 5.05;
  final d2incoherent = b30both || b350both || d2double;
  c.probe(
    id: 'D2',
    lens: 'EC7',
    edgeRpc: 'oráculo pós-B3 0ms+50ms (sem double credit / both)',
    payload: 'B3 ${b30.oid} + B3b ${b350.oid}',
    http: 'both0=$b30both both50=$b350both',
    stripeBd: 'or0=$b30or or50=$b350or',
    result: d2incoherent ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: d2incoherent,
  );
  if (d2incoherent) {
    c.hold(
      id: 'D2-pos-B3',
      lens: 'EC7',
      severity: 'P1',
      title: 'Após B3 estado incoerente (both ou double credit)',
      actor: 'buyer JWT',
      pre: '1 efeito por order; clawback se crédito+disputa',
      repro: 'oráculo wallet+disputa nas orders B3',
      expected: 'não (net>0 ∧ open); venda≤1×',
      obtained: {'0ms': b30or, '50ms': b350or},
    );
  } else {
    c.block('D2-coerente', 'EC7', 'pós-B3 coerente', b30or);
  }

  // A6 classe_nova — smuggle recusada → PATCH aberta depois do release.
  final a6 = await mustPay(c, 'EC3');
  await c.markConcluidoMao(a6.oid);
  final a6s0 = await c.walletBal(s1);
  final a6ins = await c.insertDispute(
    orderId: a6.oid,
    jwt: c.buyerJwt,
    status: 'recusada',
    description: '$prefix smuggle recusada',
  );
  final a6rel = await c.tryRelease(a6.oid, jwt: c.buyerJwt);
  HttpHit? a6patch;
  final a6did = a6ins.firstId;
  if (a6did != null) {
    a6patch = await c.patchDispute(a6did, {'status': 'aberta'}, jwt: c.buyerJwt);
  } else {
    a6patch = HttpHit(0, 'no dispute', {'error': 'no insert'});
  }
  final a6s1 = await c.walletBal(s1);
  final a6or = await c.oracleWalletDispute(a6.oid, s1);
  final a6Open = a6or['both'] == true;
  c.probe(
    id: 'A6',
    lens: 'EC3',
    edgeRpc: 'INSERT disputa recusada → release → PATCH aberta',
    payload: 'smuggle status recusada depois crédito ${a6.oid}',
    http:
        'ins ${a6ins.brief} | rel ${a6rel.brief} | patch ${a6patch.brief}',
    stripeBd: 'Δ=${a6s1 - a6s0} oracle=$a6or',
    result: a6Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a6Open,
  );
  if (a6Open) {
    markBothFail(
      c,
      id: 'A6-status-smuggle',
      lens: 'EC3',
      title: 'Disputa recusada→aberta após release: crédito + claim',
      oracle: a6or,
      repro: 'POST status=recusada; rpc release; PATCH status=aberta',
      severity: 'P1',
    );
  } else {
    c.block('A6-smuggle', 'EC3', 'smuggle recusada sem both', a6or);
  }

  // A7 — clawback depois disputa; seller PATCH recusada; 2.º release.
  final a7 = await mustPay(c, 'EC5');
  await c.markConcluidoMao(a7.oid);
  final a7rel1 = await c.tryRelease(a7.oid, jwt: c.buyerJwt);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  final a7disp = await c.insertDispute(
    orderId: a7.oid,
    jwt: c.buyerJwt,
    description: '$prefix seq release then disputa',
  );
  final a7or1 = await c.oracleWalletDispute(a7.oid, s1);
  final a7did = a7disp.firstId;
  HttpHit? a7patch;
  if (a7did != null) {
    a7patch = await c.patchDispute(a7did, {'status': 'recusada'}, jwt: c.sellerJwt);
  } else {
    a7patch = HttpHit(0, 'no dispute', {'error': 'no insert'});
  }
  final a7s0 = await c.walletBal(s1);
  final a7rel2 = await c.tryRelease(a7.oid, jwt: c.buyerJwt);
  final a7s1 = await c.walletBal(s1);
  final a7or2 = await c.oracleWalletDispute(a7.oid, s1);
  final a7ReCredit = a7rel2.json == true && (a7s1 - a7s0) > 0;
  c.probe(
    id: 'A7',
    lens: 'EC5',
    edgeRpc: 'release→disputa (clawback) → PATCH recusada seller → 2.º release',
    payload: 'reabrir janela após clawback DTDY ${a7.oid}',
    http:
        'rel1 ${a7rel1.brief} | disp ${a7disp.brief} | patch ${a7patch.brief} | rel2 ${a7rel2.brief}',
    stripeBd: 'or1=$a7or1 Δrel2=${a7s1 - a7s0} or2=$a7or2',
    result: a7ReCredit ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a7ReCredit,
  );
  if (a7ReCredit) {
    c.hold(
      id: 'A7-rerelease-after-clawback',
      lens: 'EC5',
      severity: 'P1',
      title: 'Seller fechou disputa (recusada) e 2.º release creditou de novo',
      actor: 'seller PATCH + buyer release',
      pre: 'clawback anula flag; PATCH recusada não deve reabrir crédito sozinho sem regra',
      repro: 'release; disputa; PATCH recusada JWT seller; release outra vez',
      expected: '2.º release false; Δ=0',
      obtained: {'rel2': a7rel2.brief, 'delta': a7s1 - a7s0, 'or2': a7or2},
    );
  } else {
    c.block('A7-rerelease', 'EC5', '2.º release após PATCH recusada preso', a7rel2);
  }

  // A8 — triple release∥disputa∥payout (janela clawback).
  final a8 = await mustPay(c, 'EC4');
  await c.markConcluidoMao(a8.oid);
  await c.setWalletBalance(s1, 0.50);
  final a8s0 = await c.walletBal(s1);
  final tidsA80 = await c.transferIds(s1);
  final a8triple = await Future.wait([
    c.tryRelease(a8.oid, jwt: c.buyerJwt),
    c.insertDispute(
      orderId: a8.oid,
      jwt: c.buyerJwt,
      description: '$prefix triple payout window',
    ),
    c.connect({
      'amount': 500,
      'idempotency_key': 'rtecTriplePayout1822k',
    }),
  ]);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  final a8s1 = await c.walletBal(s1);
  final tidsA81 = await c.transferIds(s1);
  final a8newTr = tidsA81.difference(tidsA80);
  final a8or = await c.oracleWalletDispute(a8.oid, s1);
  final a8escaped = a8newTr.isNotEmpty &&
      (a8or['both'] == true ||
          (numOf(a8or['open_n']) ?? 0) > 0 && a8s1 < -0.001 ||
          a8newTr.isNotEmpty && (numOf(a8or['open_n']) ?? 0) > 0);
  c.probe(
    id: 'A8',
    lens: 'EC4',
    edgeRpc: 'release ∥ disputa ∥ payout 5,00 € (janela clawback)',
    payload: 'Future.wait 3 ${a8.oid} saldo pré=0,50',
    http:
        'rel ${a8triple[0].brief} | disp ${a8triple[1].brief} | pay ${a8triple[2].brief}',
    stripeBd:
        'Δ=${a8s1 - a8s0} tr=${a8newTr.toList()} oracle=$a8or bal=$a8s1',
    result: a8escaped ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a8escaped,
  );
  if (a8escaped) {
    c.hold(
      id: 'A8-payout-window',
      lens: 'EC4',
      severity: 'P0',
      title: 'Payout saiu na janela release∥disputa (Connect + claim)',
      actor: 'buyer release/disputa + seller payout',
      pre: 'clawback deve ocorrer antes de levantamento; sem tr_ se disputa aberta',
      repro: 'Future.wait release + disputa + create-connect-account 500¢',
      expected: 'sem Transfer se disputa aberta; saldo≥0; não both',
      obtained: {
        'tr': a8newTr.toList(),
        'bal': a8s1,
        'oracle': a8or,
        'pay': a8triple[2].brief,
      },
    );
  } else {
    c.block('A8-triple', 'EC4', 'triple sem escape Connect+claim', a8triple[2]);
  }

  // Credit∥debit: payout ∥ clawback JWT (GRANT deve 403).
  await c.ensureWalletBalance(s1, 3);
  final cd0 = await c.walletBal(s1);
  final tidsCd0 = await c.transferIds(s1);
  final cdPair = await Future.wait([
    c.connect({
      'amount': 100,
      'idempotency_key': 'rtecCreditDebit1822k',
    }),
    c.tryClawbackJwt(a8.oid, jwt: c.buyerJwt),
  ]);
  final cd1 = await c.walletBal(s1);
  final newCd = (await c.transferIds(s1)).difference(tidsCd0);
  final cdOpen = (cd1 > cd0 + 0.001) || newCd.length > 1;
  c.probe(
    id: 'A9',
    lens: 'EC3',
    edgeRpc: 'payout ∥ clawback JWT (credit∥debit)',
    payload: 'Future.wait connect 100¢ + clawback_dispute JWT',
    http: 'pay ${cdPair[0].brief} | claw ${cdPair[1].brief}',
    stripeBd: 'Δ=${cd1 - cd0} tr=${newCd.toList()}',
    result: cdOpen ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: cdOpen,
  );
  if (cdOpen) {
    c.hold(
      id: 'A9-credit-debit',
      lens: 'EC3',
      severity: 'P0',
      title: 'Race payout∥clawback JWT mintou/duplicou',
      actor: 'seller payout + buyer clawback',
      pre: 'clawback GRANT service_role; ≤1 tr_',
      repro: 'Future.wait payout + clawback JWT',
      expected: '≤1 tr_; clawback 403; Δ≤0 vs payout',
      obtained: 'Δ=${cd1 - cd0}',
    );
  } else {
    c.block('A9-cd', 'EC3', 'credit∥debit clawback 403', cdPair[1]);
  }

  // =========================================================================
  // EC-C Payout / Connect
  // =========================================================================
  await c.ensureWalletBalance(s1, 6);
  final c0 = await c.walletBal(s1);
  final tids0 = await c.transferIds(s1);
  final over = await c.connect({
    'amount': 99999999,
    'idempotency_key': 'rtecOverbal1822keyxxx',
  });
  final destHit = await c.connect({
    'amount': 100,
    'idempotency_key': 'rtecDestAlien1822keyx',
    'destination': alienAcct,
    'stripe_account_id': alienAcct,
    'account': alienAcct,
    'on_behalf_of': alienAcct,
    'iban': 'PT50000201231234567890154',
    'transfer_data': {'destination': alienAcct},
    'user_id': s2,
  });
  final c1bal = await c.walletBal(s1);
  final newC1 = (await c.transferIds(s1)).difference(tids0);
  final c1Open = over.payoutOk || newC1.length > 1;
  c.probe(
    id: 'C1',
    lens: 'EC4',
    edgeRpc: 'payout overbalance + dest alheio (user_id S2)',
    payload: '99999999 vs $c0 · dest=$alienAcct user_id=$s2 amount=100',
    http: 'over ${over.brief} | dest ${destHit.brief}',
    stripeBd: 'Δ=${c1bal - c0} tr=${newC1.toList()}',
    result: c1Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: c1Open,
  );
  if (c1Open) {
    c.hold(
      id: 'C1-over-dest',
      lens: 'EC4',
      severity: 'P0',
      title: 'Overbalance ou dest alheio extra Transfer',
      actor: 'seller JWT',
      pre: 'over deny; dest JWT próprio',
      repro: 'POST amount enorme; dest+user_id S2',
      expected: 'over 400; ≤1 tr_ própria',
      obtained: '${over.brief} ${destHit.brief}',
    );
  } else {
    c.block('C1-over-dest', 'EC4', 'over/dest presos ou 1 própria', destHit);
  }

  await c.ensureWalletBalance(s1, 4);
  final par0 = await c.walletBal(s1);
  final tidsP0 = await c.transferIds(s1);
  const sameKey = 'rtecParallelSame1822k';
  final pairSame = await Future.wait([
    c.connect({'amount': 100, 'idempotency_key': sameKey}),
    c.connect({'amount': 100, 'idempotency_key': sameKey}),
  ]);
  final par1 = await c.walletBal(s1);
  final newSame = (await c.transferIds(s1)).difference(tidsP0);
  final c2Open = newSame.length > 1 || (par0 - par1) > 1.05;
  c.probe(
    id: 'C2',
    lens: 'EC4',
    edgeRpc: 'payout ∥ payout mesma idempotency_key',
    payload: 'Future.wait 100¢ key=$sameKey',
    http: pairSame.map((h) => h.brief).toList(),
    stripeBd: 'Δ=${par1 - par0} tr=${newSame.toList()} n=${newSame.length}',
    result: c2Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: c2Open,
  );
  if (c2Open) {
    c.hold(
      id: 'C2-dual-payout',
      lens: 'EC4',
      severity: 'P0',
      title: 'Payout paralelo mesma key → 2 Transfers',
      actor: 'seller JWT ×2',
      pre: 'ledger unique',
      repro: 'Future.wait mesma idempotency_key',
      expected: '1 tr_',
      obtained: 'n=${newSame.length}',
    );
  } else {
    c.block('C2-idem', 'EC4', 'payout∥ 1 tr_', pairSame[0]);
  }

  final onbS2 = await c.connect(<String, Object?>{}, jwt: c.seller2Jwt);
  final payS2 = await c.connect({
    'amount': 100,
    'idempotency_key': 'rtecS2PayS1bal1822xxx',
    'user_id': s1,
    'destination': '${(await c.walletRow(s1))?['stripe_account_id']}',
  }, jwt: c.seller2Jwt);
  final reuseS2 = await c.connect({
    'stripeAccountId': '${(await c.walletRow(s1))?['stripe_account_id']}',
    'account': '${(await c.walletRow(s1))?['stripe_account_id']}',
  }, jwt: c.seller2Jwt);
  final s1AfterS2 = await c.walletBal(s1);
  final c3PayS1 = payS2.payoutOk;
  c.probe(
    id: 'C3',
    lens: 'EC6',
    edgeRpc: 'Connect onboarding/payout seller2 hostil (user_id S1)',
    payload: 'S2 POST {} · S2 payout user_id=S1 100¢ · reuse acct S1',
    http:
        'onb ${onbS2.brief} | pay ${payS2.brief} | reuse ${reuseS2.brief}',
    stripeBd: 'S1bal=$s1AfterS2 payS1=$c3PayS1',
    result: c3PayS1 ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: c3PayS1,
  );
  if (c3PayS1) {
    c.hold(
      id: 'C3-s2-payout-s1',
      lens: 'EC6',
      severity: 'P0',
      title: 'seller2 levantou saldo S1 via user_id/dest',
      actor: 'seller2 JWT',
      pre: 'payout só wallet do JWT',
      repro: 'POST create-connect-account JWT S2 user_id=S1 amount=100',
      expected: '400/deny; sem tr_ em S1',
      obtained: payS2.brief,
    );
  } else {
    c.block('C3-s2', 'EC6', 'seller2 Connect hostil preso', payS2);
  }

  await c.endLives();
  await c.dumpAll('pass1.json');
  stdout.writeln(
      'DONE probes=${c.probes.length} findings=${c.findings.where((f) => f['count'] == true).length} classe_nova=${c.classeNova}');
}
