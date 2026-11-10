/// RED TEAM CEGO EJ pass1 — wallet + Edge pós-pago POS_OPEN_MVP.
/// Staging only. Stripe TEST. NÃO CORRIGIR. Fase 4 não.
/// Anti-atrofia: NÃO Coptic · NÃO charset 400.
/// Residual 1 linha: B6 buyer refund 403 (seller OK na mesma linha).
/// B2 0ms clássico 1 efeito fica DENTRO do probe B2 (dispute-first 25ms = classe_nova).
import 'dart:io';
import '_rtej.dart';

Future<({String oid, String pid, String? pi})> mustPay(
  Rtej c,
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
  Rtej c, {
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
    pre: 'sem crédito líquido E disputa aberta; clawback se release já processou',
    repro: repro,
    expected: 'net≤0 OU disputa inexistente/fechada',
    obtained: oracle,
  );
}

Future<void> main() async {
  final c = Rtej.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final s1 = c.sellerId!;
  final b1 = c.buyerId!;
  final s2 = c.seller2Id;
  final fakeOid = '00000000-0000-0000-0000-00000000ej01';

  stdout.writeln('actors B1=$b1 S1=$s1 B2=${c.buyer2Id} S2=$s2');

  c.skipped.add({
    'id': 'HOLD-anti-atrofia',
    'title':
        'Coptic payout key · charset 400 — não corridos; B6 buyer 403 = 1 residual',
  });

  try {
    await runForge(c, s1, b1, fakeOid, s2);
    await runReleaseRefund(c, s1, s2);
    await runEdgeTipPayout(c, s1, b1, s2);
  } finally {
    await c.endLives();
  }

  await c.dumpAll('pass1.json');
  stdout.writeln(
    'EJ DONE probes=${c.probes.length} findings=${c.findings.where((f) => f['count'] == true).length} '
    'lenses=${c.lensesHit.toList()..sort()} nova=${c.classeNova} '
    'races=${c.probes.where((p) => p['race'] == true).length}',
  );
}

Future<void> runForge(
  Rtej c,
  String s1,
  String b1,
  String fakeOid,
  String? s2,
) async {
  final a0s = await c.walletBal(s1);
  final a0b = await c.walletBal(b1);

  final existing = await c.walletTxns(s1, limit: 1);
  final existId = existing.isEmpty ? null : '${existing.first['id']}';
  final upsertId = existId ?? '00000000-0000-0000-0000-00000000ejtx';
  final upsert = await c.rest(
    'POST',
    'wallet_transactions',
    jwt: c.buyerJwt,
    prefer: 'resolution=merge-duplicates,return=representation',
    body: {
      'id': upsertId,
      'wallet_id': s1,
      'amount': 7777.77,
      'type': 'venda',
      'description': '$prefix upsert-merge poison',
      'order_id': fakeOid,
    },
  );
  final delTxn = await c.rest(
    'DELETE',
    'wallet_transactions?wallet_id=eq.$s1&limit=1',
    jwt: c.buyerJwt,
    prefer: 'return=representation',
  );
  final a1s = await c.walletBal(s1);
  final a1b = await c.walletBal(b1);
  final a1Open = (a1s - a0s).abs() > 0.001 ||
      (a1b - a0b).abs() > 0.001 ||
      minted(upsert, 0) ||
      (delTxn.ok && delTxn.list.isNotEmpty);
  c.probe(
    id: 'A1',
    lens: 'EJ1',
    edgeRpc: 'UPSERT merge-duplicates + DELETE wallet_transactions JWT',
    payload:
        'Prefer resolution=merge-duplicates id=$upsertId amount=7777 · DELETE limit=1',
    http: 'upsert ${upsert.brief} | del ${delTxn.brief}',
    stripeBd: 'ΔB=${a1b - a0b} ΔS=${a1s - a0s}',
    result: a1Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a1Open,
  );
  await c.expectDenied(
    id: 'A1-upsert-merge',
    lens: 'EJ1',
    title: 'JWT UPSERT merge-duplicates wallet_transactions',
    hit: upsert,
    actor: 'buyer JWT',
    pre: 'RLS sem INSERT/UPDATE authenticated',
    repro: 'POST Prefer: resolution=merge-duplicates amount=7777',
    delta: a1s - a0s,
  );

  final finishJwt = await c.rpc('batata_wallet_payout_finish', {
    'p_user_id': s1,
    'p_idempotency_key': 'rtejFinishJwt1905xxxx',
    'p_stripe_transfer_id': 'tr_rtej_fake',
    'p_amount_cents': 9999,
  }, jwt: c.sellerJwt);
  final creditProfile = await c.req(
    'POST',
    '/rest/v1/rpc/batata_credit_wallet_once',
    jwt: c.buyerJwt,
    body: {
      'p_wallet_id': s1,
      'p_order_id': fakeOid,
      'p_amount': '999',
      'p_type': 'venda',
      'p_description': '$prefix credit string',
    },
    extra: {
      'Content-Profile': 'public',
      'Accept-Profile': 'public',
    },
  );
  final clawJwt = await c.tryClawbackJwt(fakeOid, jwt: c.buyerJwt);
  final debitJwt = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': s1,
    'p_amount_cents': 100,
    'p_idempotency_key': 'rtejDebitJwt1905keyxx',
  }, jwt: c.sellerJwt);
  final a2s = await c.walletBal(s1);
  final a2Open = minted(finishJwt, 0) ||
      minted(creditProfile, 0) ||
      minted(clawJwt, 0) ||
      minted(debitJwt, 0) ||
      (a2s - a1s).abs() > 0.001;
  c.probe(
    id: 'A2',
    lens: 'EJ1',
    edgeRpc: 'rpc payout_finish + credit Content-Profile + clawback/debit JWT',
    payload: 'finish tr_fake 9999¢ · credit amount="999" · claw/debit JWT',
    http:
        'finish ${finishJwt.brief} | credit ${creditProfile.brief} | claw ${clawJwt.brief} | debit ${debitJwt.brief}',
    stripeBd: 'ΔS=${a2s - a1s}',
    result: a2Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a2Open,
  );
  await c.expectDenied(
    id: 'A2-payout-finish-jwt',
    lens: 'EJ1',
    title: 'JWT batata_wallet_payout_finish',
    hit: finishJwt,
    actor: 'seller JWT',
    pre: 'GRANT service_role',
    repro: 'POST rpc batata_wallet_payout_finish JWT seller',
    delta: a2s - a1s,
  );

  final alien = (await c.otherConnectAccounts(s1));
  final alienAcct = alien.isEmpty
      ? 'acct_1UChokHOSTILEEJ'
      : '${alien.first['stripe_account_id']}';
  final ownBefore = '${(await c.walletRow(s1))?['stripe_account_id'] ?? ''}';
  final patchOr = await c.rest(
    'PATCH',
    'wallets?or=(id.eq.$s1,id.eq.${s2 ?? fakeOid})',
    jwt: c.buyerJwt,
    body: {
      'stripe_account_id': alienAcct,
      'balance': 8888.88,
    },
  );
  final patchAvail = await c.rest(
    'PATCH',
    'wallets?id=eq.$s1',
    jwt: c.sellerJwt,
    body: {
      'available_balance': 9999,
      'pending_balance': 1,
      'stripe_account_id': alienAcct,
    },
  );
  final ownAfter = '${(await c.walletRow(s1))?['stripe_account_id'] ?? ''}';
  final a3s = await c.walletBal(s1);
  final destChanged =
      ownAfter.isNotEmpty && ownAfter != ownBefore && ownAfter == alienAcct;
  final a3Open = destChanged ||
      (a3s - a2s).abs() > 0.001 ||
      (patchOr.ok && patchOr.list.isNotEmpty) ||
      (patchAvail.ok && patchAvail.list.isNotEmpty);
  c.probe(
    id: 'A3',
    lens: 'EJ1',
    edgeRpc: 'PATCH wallets or=(id.eq.S1) dest alheio + available_balance',
    payload: 'or-filter dest=$alienAcct · available_balance JWT seller',
    http: 'or ${patchOr.brief} | avail ${patchAvail.brief}',
    stripeBd: 'acct $ownBefore → $ownAfter ΔS=${a3s - a2s}',
    result: a3Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a3Open,
  );
  if (a3Open) {
    c.hold(
      id: 'A3-patch-or-dest',
      lens: 'EJ1',
      severity: 'P0',
      title: 'PATCH wallets or-filter mudou dest/balance JWT',
      actor: 'buyer/seller JWT',
      pre: 'RLS 0 rows; acct próprio',
      repro: 'PATCH wallets?or=(id.eq.S1) stripe_account_id alheio',
      expected: '200 [] / 400 coluna; dest inalterado',
      obtained: {
        'or': patchOr.brief,
        'avail': patchAvail.brief,
        'acct': ownAfter,
      },
    );
  } else {
    c.block('A3-or', 'EJ1', 'PATCH or-filter dest preso', patchOr);
  }

  final liveId = await c.insertLive(title: '$prefix tip-unpaid');
  HttpHit tipCreate = HttpHit(0, 'no live', {'error': 'no live'});
  HttpHit tipPatch = HttpHit(0, 'no tip', {'error': 'no tip'});
  HttpHit tipSettle = HttpHit(0, 'no sid', {'error': 'no sid'});
  String? tipId;
  String? tipSid;
  final a4s0 = await c.walletBal(s1);
  if (liveId != null) {
    tipCreate = await c.tipCheckout(
      liveId: liveId,
      seller: s1,
      amountEur: 2,
      jwt: c.buyerJwt,
    );
    tipId = tipCreate.tipId ?? tipCreate.map?['tip_id']?.toString();
    tipSid = tipCreate.sessionId;
    if (tipId != null) {
      c.createdTipIds.add(tipId);
      tipPatch = await c.rest(
        'PATCH',
        'live_tips?id=eq.$tipId',
        jwt: c.buyerJwt,
        body: {
          'status': 'paid',
          'amount': 99,
          'seller_amount': 99,
        },
      );
    }
    if (tipSid != null && tipSid.startsWith('cs_')) {
      tipSettle = await c.tipSettleGet(tipSid, jwt: c.buyerJwt);
    }
  }
  final a4s1 = await c.walletBal(s1);
  final tipRow = tipId == null ? null : await c.tipRow(tipId);
  final tipPaid = '${tipRow?['status'] ?? ''}'.toLowerCase() == 'paid' ||
      '${tipRow?['status'] ?? ''}'.toLowerCase() == 'completed';
  final a4Open = (a4s1 - a4s0).abs() > 0.001 ||
      (tipPatch.ok && tipPatch.list.isNotEmpty && tipPaid);
  c.probe(
    id: 'A4',
    lens: 'EJ2',
    edgeRpc: 'tip unpaid + PATCH live_tips status=paid JWT + GET settle',
    payload: 'live $liveId 2€ · PATCH paid 99 · GET unpaid sid',
    http:
        'create ${tipCreate.brief} | patch ${tipPatch.brief} | settle ${tipSettle.brief}',
    stripeBd: 'ΔS=${a4s1 - a4s0} tip=$tipRow',
    result: a4Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a4Open,
  );
  if (a4Open) {
    c.hold(
      id: 'A4-tip-patch-paid',
      lens: 'EJ2',
      severity: 'P0',
      title: 'PATCH live_tips paid JWT creditou ou marcou paid',
      actor: 'buyer JWT',
      pre: 'tip unpaid Δ=0; status paid só webhook',
      repro: 'POST tip-checkout; PATCH status=paid amount=99',
      expected: 'PATCH 0 rows; Δ=0; pending',
      obtained: {'Δ': a4s1 - a4s0, 'row': tipRow, 'patch': tipPatch.brief},
    );
  } else {
    c.block('A4-unpaid', 'EJ2', 'tip unpaid + PATCH paid Δ=0', tipCreate);
  }

  final gql = await c.graphql(
    'mutation { insertIntowallet_transactionsCollection(objects: [{wallet_id: "$s1", amount: 50, type: "venda"}]) { records { id amount } } }',
    jwt: c.buyerJwt,
  );
  final gqlOpen = gql.ok &&
      (gql.body.contains('"amount"') &&
          !gql.body.toLowerCase().contains('error'));
  c.probe(
    id: 'A5',
    lens: 'EJ1',
    edgeRpc: 'POST /graphql/v1 insert wallet_transactions',
    payload: 'mutation insertIntowallet_transactionsCollection amount=50',
    http: gql,
    stripeBd: 'Δ vs A4 ${await c.walletBal(s1) - a4s1}',
    result: gqlOpen ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: gqlOpen,
  );
  await c.expectDenied(
    id: 'A5-graphql',
    lens: 'EJ1',
    title: 'GraphQL insert wallet_transactions JWT',
    hit: gql,
    actor: 'buyer JWT',
    pre: 'graphql off ou RLS',
    repro: 'POST /graphql/v1 mutation insert',
    openIf: (h) =>
        h.ok &&
        h.body.contains('wallet_transactions') &&
        !h.body.toLowerCase().contains('error'),
  );
}

Future<void> runReleaseRefund(Rtej c, String s1, String? s2) async {
  // D1a + B1 + B5 + D1 + D2 partilham a mesma order paga.
  final d1 = await mustPay(c, 'EJ7');
  final d1s0 = await c.walletBal(s1);
  final b1relB = await c.tryRelease(d1.oid, jwt: c.buyerJwt);
  final b1relS = await c.tryRelease(d1.oid, jwt: c.sellerJwt);
  final b1patch = await c.rest(
    'PATCH',
    'orders?id=eq.${d1.oid}',
    jwt: c.buyerJwt,
    body: {
      'status': 'concluido',
      'completed_at': DateTime.now().toUtc().toIso8601String(),
    },
  );
  final d1rowPago = await c.orderRow(d1.oid);
  final d1s1 = await c.walletBal(s1);
  final b1Open = (b1relB.json == true || b1relS.json == true) &&
          (d1s1 - d1s0) > 0.001 ||
      (b1patch.ok &&
          b1patch.list.isNotEmpty &&
          '${d1rowPago?['status']}' == 'concluido');
  c.probe(
    id: 'B1',
    lens: 'EJ3',
    edgeRpc: 'release cedo em pago + PATCH orders concluido JWT buyer',
    payload: 'oid ${d1.oid} ainda pago; buyer/seller rpc; PATCH concluido JWT',
    http:
        'relB ${b1relB.brief} | relS ${b1relS.brief} | patch ${b1patch.brief}',
    stripeBd: 'Δ=${d1s1 - d1s0} status=${d1rowPago?['status']}',
    result: b1Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: b1Open,
  );
  if (b1Open) {
    c.hold(
      id: 'B1-early-release',
      lens: 'EJ3',
      severity: 'P0',
      title: 'Release cedo ou PATCH concluido JWT creditou',
      actor: 'buyer/seller JWT',
      pre: 'status pago sem receção → release false; PATCH status 0 rows',
      repro: 'rpc release em pago; PATCH status=concluido JWT buyer',
      expected: 'false; PATCH []; Δ=0',
      obtained: {
        'relB': b1relB.brief,
        'patch': b1patch.brief,
        'status': d1rowPago?['status'],
      },
    );
  } else {
    c.block('B1-cedo', 'EJ3', 'release cedo + PATCH JWT preso', b1relB);
  }

  HttpHit b5rel = HttpHit(0, 'no seller2', {'error': 'no s2'});
  HttpHit b5disp = HttpHit(0, 'no seller2', {'error': 'no s2'});
  HttpHit b5flag = HttpHit(0, 'no seller2', {'error': 'no s2'});
  if (s2 != null) {
    b5flag = await c.rest(
      'PATCH',
      'orders?id=eq.${d1.oid}',
      jwt: c.seller2Jwt,
      body: {
        'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    b5rel = await c.tryRelease(d1.oid, jwt: c.seller2Jwt);
    b5disp = await c.insertDispute(
      orderId: d1.oid,
      jwt: c.seller2Jwt,
      buyer: s2,
      description: '$prefix seller2 alheio',
    );
  }
  final d1s2 = await c.walletBal(s1);
  final b5Open = (b5rel.json == true && (d1s2 - d1s1) > 0) ||
      (b5disp.ok && b5disp.firstId != null) ||
      (b5flag.ok && b5flag.list.isNotEmpty);
  c.probe(
    id: 'B5',
    lens: 'EJ6',
    edgeRpc: 'seller2 PATCH wallet_release_processed_at + release + disputa',
    payload: 'S2 flag/release/disputa order ${d1.oid}',
    http:
        'flag ${b5flag.brief} | rel ${b5rel.brief} | disp ${b5disp.brief}',
    stripeBd: 'ΔS=${d1s2 - d1s1}',
    result: b5Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: b5Open,
  );
  await c.expectDenied(
    id: 'B5-s2-flag',
    lens: 'EJ6',
    title: 'seller2 PATCH wallet_release_processed_at order alheia',
    hit: b5flag,
    actor: 'seller2 JWT',
    pre: 'RLS 0 rows',
    repro: 'PATCH orders wallet_release_processed_at JWT S2',
    openIf: (h) => h.ok && h.list.isNotEmpty,
  );

  await c.markConcluidoMao(d1.oid);
  final d1s3 = await c.walletBal(s1);
  final d1rel = await c.tryRelease(d1.oid, jwt: c.buyerJwt);
  final d1s4 = await c.walletBal(s1);
  final d1or = await c.oracleWalletDispute(d1.oid, s1);
  final d1Credited = d1rel.json == true && (d1s4 - d1s3) > 0;
  c.probe(
    id: 'D1',
    lens: 'EJ7',
    edgeRpc: 'pago 4242 + release legítimo concluido+mão',
    payload: 'order ${d1.oid} PI ${d1.pi} buyer rpc release',
    http: d1rel,
    stripeBd: 'Δ=${d1s4 - d1s3} oracle=$d1or credited=$d1Credited',
    result: d1Credited ? 'HOLD' : 'FAIL',
    classeNova: false,
    countFinding: !d1Credited,
  );
  if (!d1Credited) {
    c.hold(
      id: 'D1-legit-release',
      lens: 'EJ7',
      severity: 'P1',
      title: 'Release legítimo não creditou (oráculo caixa falhou)',
      actor: 'buyer JWT',
      pre: 'concluido + mão → crédito venda',
      repro: 'fixture concluido+mão; rpc release',
      expected: 'true + Δ>0',
      obtained: '${d1rel.brief} Δ=${d1s4 - d1s3}',
    );
  } else {
    c.block('D1-caixa', 'EJ7', 'pago 4242 + release Δ observado', d1rel);
  }

  // D2 — disputa após release (clawback ou deny; sem crédito líquido+claim).
  final d2ins = await c.insertDispute(
    orderId: d1.oid,
    jwt: c.buyerJwt,
    description: '$prefix disputa após release',
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
  final d2or = await c.oracleWalletDispute(d1.oid, s1);
  final d2both = d2or['both'] == true;
  c.probe(
    id: 'D2',
    lens: 'EJ5',
    edgeRpc: 'INSERT disputa após release (clawback / deny)',
    payload: 'oid ${d1.oid} após D1 crédito',
    http: d2ins,
    stripeBd: 'oracle=$d2or',
    result: d2both ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: d2both,
  );
  if (d2both) {
    markBothFail(
      c,
      id: 'D2-claim-after-release',
      lens: 'EJ5',
      title: 'Disputa aberta após release sem clawback (crédito líquido+claim)',
      oracle: d2or,
      repro: 'release; POST order_disputes',
      severity: 'P1',
    );
  } else {
    c.block('D2-claw', 'EJ5', 'pós-release sem (net>0 ∧ open)', d2or);
  }

  // A6 — PATCH wallet_release_processed_at null JWT + 2.º release.
  final a6patch = await c.rest(
    'PATCH',
    'orders?id=eq.${d1.oid}',
    jwt: c.buyerJwt,
    body: {'wallet_release_processed_at': null},
  );
  final a6s0 = await c.walletBal(s1);
  final a6rel2 = await c.tryRelease(d1.oid, jwt: c.buyerJwt);
  final a6s1 = await c.walletBal(s1);
  final a6Open = a6rel2.json == true && (a6s1 - a6s0) > 0.001;
  c.probe(
    id: 'A6',
    lens: 'EJ3',
    edgeRpc: 'PATCH wallet_release_processed_at=null JWT + 2.º release',
    payload: 'reabrir flag após D1 ${d1.oid}',
    http: 'patch ${a6patch.brief} | rel2 ${a6rel2.brief}',
    stripeBd: 'Δ=${a6s1 - a6s0}',
    result: a6Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: a6Open,
  );
  if (a6Open) {
    c.hold(
      id: 'A6-reopen-flag',
      lens: 'EJ3',
      severity: 'P0',
      title: 'JWT limpou flag e 2.º release creditou de novo',
      actor: 'buyer JWT',
      pre: 'coluna flag só service_role',
      repro: 'PATCH wallet_release_processed_at=null; rpc release',
      expected: 'PATCH []; 2.º false; Δ=0',
      obtained: {'patch': a6patch.brief, 'rel2': a6rel2.brief, 'Δ': a6s1 - a6s0},
    );
  } else {
    c.block('A6-flag', 'EJ3', '2.º release após PATCH flag preso', a6rel2);
  }

  // B4 — triple release paralelo buyer+seller+seller2.
  final b4 = await mustPay(c, 'EJ3');
  await c.markConcluidoMao(b4.oid);
  final b4s0 = await c.walletBal(s1);
  final b4pair = await Future.wait([
    c.tryRelease(b4.oid, jwt: c.buyerJwt),
    c.tryRelease(b4.oid, jwt: c.sellerJwt),
    if (s2 != null)
      c.tryRelease(b4.oid, jwt: c.seller2Jwt)
    else
      Future.value(HttpHit(0, 'no s2', {'error': 'no s2'})),
  ]);
  final b4s1 = await c.walletBal(s1);
  final trueCount = b4pair.where((h) => h.json == true).length;
  final b4Open = (b4s1 - b4s0) > 5.05 || trueCount > 1;
  c.probe(
    id: 'B4',
    lens: 'EJ3',
    edgeRpc: 'double/triple release ∥ buyer+seller+seller2',
    payload: 'Future.wait 3 rpc ${b4.oid}',
    http: b4pair.map((h) => h.brief).toList(),
    stripeBd: 'Δ=${b4s1 - b4s0} trueCount=$trueCount',
    result: b4Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: b4Open,
    race: true,
  );
  if (b4Open) {
    c.hold(
      id: 'B4-triple-release',
      lens: 'EJ3',
      severity: 'P0',
      title: 'Triple release creditou >1×',
      actor: 'buyer+seller+seller2 JWT',
      pre: '1 crédito / order',
      repro: 'Future.wait 3× rpc release',
      expected: 'trueCount=1 Δ≈5',
      obtained: 'trueCount=$trueCount Δ=${b4s1 - b4s0}',
    );
  } else {
    c.block('B4-idem', 'EJ3', 'triple release 1 crédito', b4pair[0]);
  }

  // B3 — refund ∥ release APÓS concluido (classe_nova vs EC em pago).
  final b3 = await mustPay(c, 'EJ4');
  await c.markConcluidoMao(b3.oid);
  final b3s0 = await c.walletBal(s1);
  final b3pair = await Future.wait([
    c.refundOrder(b3.oid, jwt: c.sellerJwt),
    c.tryRelease(b3.oid, jwt: c.buyerJwt),
  ]);
  final b3s1 = await c.walletBal(s1);
  final b3row = await c.orderRow(b3.oid);
  final b3or = await c.oracleWalletDispute(b3.oid, s1);
  final refunded = '${b3row?['stripe_refund_id'] ?? ''}'.startsWith('re_');
  final credited = (numOf(b3or['net']) ?? 0) > 0.01;
  final b3Open = refunded && credited;
  c.probe(
    id: 'B3',
    lens: 'EJ4',
    edgeRpc: 'refund ∥ release após concluido+mão',
    payload: 'Future.wait seller refund + buyer release ${b3.oid}',
    http: 'ref ${b3pair[0].brief} | rel ${b3pair[1].brief}',
    stripeBd: 'Δ=${b3s1 - b3s0} refund=${b3row?['stripe_refund_id']} or=$b3or',
    result: b3Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: b3Open,
    race: true,
  );
  if (b3Open) {
    c.hold(
      id: 'B3-refund-release-concluido',
      lens: 'EJ4',
      severity: 'P0',
      title: 'Race refund∥release em concluido: crédito + re_',
      actor: 'seller refund + buyer release',
      pre: 'um efeito; se refund, net≤0',
      repro: 'markConcluido; Future.wait refund-order + release',
      expected: 'refund OU crédito; não ambos',
      obtained: b3or,
    );
  } else {
    c.block('B3-race', 'EJ4', 'refund∥release concluido sem double', b3pair[0]);
  }

  // B2 — 0ms clássico (1 efeito residual) + dispute-first 25ms (classe_nova).
  final b20 = await mustPay(c, 'EJ4');
  await c.markConcluidoMao(b20.oid);
  final b20s0 = await c.walletBal(s1);
  final b20pair = await c.raceReleaseDispute(b20.oid, delayMs: 0);
  final b20or = await c.oracleWalletDispute(b20.oid, s1);
  final b20both = b20or['both'] == true;

  final b225 = await mustPay(c, 'EJ4');
  await c.markConcluidoMao(b225.oid);
  final b225s0 = await c.walletBal(s1);
  final b225pair = await c.raceReleaseDispute(
    b225.oid,
    delayMs: 25,
    disputeFirst: true,
  );
  final b225or = await c.oracleWalletDispute(b225.oid, s1);
  final b225both = b225or['both'] == true;
  final b2Open = b20both || b225both;
  c.probe(
    id: 'B2',
    lens: 'EJ4',
    edgeRpc: 'release ∥ disputa 0ms + dispute-first 25ms',
    payload: '0ms ${b20.oid} · dispute-first 25ms ${b225.oid}',
    http:
        '0ms rel ${b20pair[0].brief} disp ${b20pair[1].brief} | 25ms ${b225pair[0].brief} ${b225pair[1].brief}',
    stripeBd:
        'Δ0=${await c.walletBal(s1) - b20s0} or0=$b20or or25=$b225or Δ25start=$b225s0',
    result: b2Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: b2Open,
    race: true,
  );
  if (b2Open) {
    markBothFail(
      c,
      id: 'B2-rel-disp',
      lens: 'EJ4',
      title: 'Release∥disputa 0ms ou 25ms dispute-first: crédito+claim',
      oracle: {'0ms': b20or, '25ms': b225or},
      repro: 'Future.wait 0ms; dispute-first delay=25ms',
    );
  } else {
    c.block(
      'B2-race',
      'EJ4',
      '0ms 1 efeito (residual) + 25ms dispute-first sem both',
      {'0ms': b20or, '25ms': b225or},
    );
  }

  // B6 — buyer refund 403 (1 residual) + seller refund OK mesma linha.
  final b6 = await mustPay(c, 'EJ4');
  final b6s0 = await c.walletBal(s1);
  final b6buyer = await c.refundOrder(b6.oid, jwt: c.buyerJwt);
  final b6seller = await c.refundOrder(b6.oid, jwt: c.sellerJwt);
  final b6s1 = await c.walletBal(s1);
  final b6row = await c.orderRow(b6.oid);
  final buyerMinted = b6buyer.ok &&
      (b6buyer.map?['refundId'] != null ||
          '${b6row?['stripe_refund_id'] ?? ''}'.startsWith('re_') &&
              b6buyer.status == 200);
  final buyerOk = b6buyer.status == 200;
  c.probe(
    id: 'B6',
    lens: 'EJ4',
    edgeRpc: 'refund-order buyer 403 + seller OK mesma order',
    payload: 'oid ${b6.oid} PI ${b6.pi}',
    http: 'buyer ${b6buyer.brief} | seller ${b6seller.brief}',
    stripeBd: 'Δ=${b6s1 - b6s0} refund=${b6row?['stripe_refund_id']}',
    result: buyerOk ? 'FAIL' : 'HOLD',
    classeNova: false,
    countFinding: buyerOk,
  );
  if (buyerOk || buyerMinted) {
    c.hold(
      id: 'B6-buyer-refund',
      lens: 'EJ4',
      severity: 'P0',
      title: 'Buyer refund-order não 403 (seller-only aberto)',
      actor: 'buyer JWT',
      pre: 'refund seller-only',
      repro: 'POST refund-order JWT buyer',
      expected: '403',
      obtained: b6buyer.brief,
    );
  } else {
    c.block('B6-residual', 'EJ4', 'buyer 403 + seller refund linha única', b6buyer);
  }
}

Future<void> runEdgeTipPayout(
  Rtej c,
  String s1,
  String b1,
  String? s2,
) async {
  const price = 12.0;
  final pidUnpaid = await c.createProduct(
    seller: s1,
    title: '$prefix settle-unpaid',
    qty: 2,
    price: price,
  );
  final oidUnpaid = pidUnpaid == null
      ? null
      : await c.insertOrder(
          productId: pidUnpaid,
          buyer: b1,
          seller: s1,
          price: price,
        );
  final paidC1 = await mustPay(c, 'EJ2');
  final paidRow = await c.orderRow(paidC1.oid);
  final paidPi = paidRow?['stripe_payment_intent_id']?.toString() ?? paidC1.pi;

  HttpHit ck = HttpHit(0, 'no oid', {'error': 'no unpaid'});
  HttpHit putSettle = HttpHit(0, 'no sid', {'error': 'no sid'});
  HttpHit getAmt = HttpHit(0, 'no sid', {'error': 'no sid'});
  HttpHit getPi = HttpHit(0, 'no pi', {'error': 'no pi'});
  String? sid;
  num? quoted;
  if (oidUnpaid != null) {
    ck = await c.checkout(
      orderId: oidUnpaid,
      jwt: c.buyerJwt,
      buyer: b1,
      amount: 1,
      productId: pidUnpaid,
      extra: {
        'amount_total': 1,
        'server_amount_cents': 1,
        'total': 1,
      },
    );
    sid = ck.sessionId;
    quoted = numOf(ck.map?['server_amount_cents']) ??
        numOf(ck.map?['amount_total']);
    if (sid != null) {
      putSettle = await c.settlePost(
        sid,
        method: 'PUT',
        extraQs: 'amount=1&amount_total=1',
        body: {
          'checkout_return': 'success',
          'session_id': sid,
          'amount': 1,
          'amount_total': 1,
        },
        jwt: c.buyerJwt,
      );
      getAmt = await c.settleGet(sid, extraQs: 'amount=1', jwt: c.buyerJwt);
    }
    if (paidPi != null && paidPi.startsWith('pi_')) {
      getPi = await c.settleGet(paidPi, extraQs: 'order_id=$oidUnpaid', jwt: c.buyerJwt);
    }
  }
  final unpaidRow =
      oidUnpaid == null ? null : await c.orderRow(oidUnpaid);
  final paidStill = await c.orderRow(paidC1.oid);
  final clientWon = ck.ok && quoted != null && quoted <= 50;
  final unpaidPaid = c.orderPaid(unpaidRow);
  final c1Open = clientWon || unpaidPaid || putSettle.ok && unpaidPaid;
  c.probe(
    id: 'C1',
    lens: 'EJ2',
    edgeRpc: 'CPI amount hostil + PUT settle + GET pi_ como session_id',
    payload:
        'unpaid $oidUnpaid amount=1 · PUT settle · GET $paidPi as sid',
    http:
        'ck ${ck.brief} | put ${putSettle.brief} | get ${getAmt.brief} | pi ${getPi.brief}',
    stripeBd:
        'quoted=$quoted unpaid=${unpaidRow?['status']} paidA=${paidStill?['status']} pi=$paidPi',
    result: c1Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: c1Open,
  );
  if (c1Open) {
    c.hold(
      id: 'C1-settle-amount',
      lens: 'EJ2',
      severity: 'P0',
      title: 'Settle/CPI confiou amount cliente ou pi_ como session',
      actor: 'buyer JWT',
      pre: 'servidor ganha amount; pi_ não é session',
      repro: 'POST CPI amount=1; PUT settle; GET session_id=pi_',
      expected: '400/402; unpaid reserva_pendente; paid intacto',
      obtained: {
        'quoted': quoted,
        'unpaid': unpaidRow?['status'],
        'put': putSettle.brief,
        'pi': getPi.brief,
      },
    );
  } else {
    c.block('C1-settle', 'EJ2', 'amount hostil + PUT + pi_ sid presos', ck);
  }

  final live2 = await c.insertLive(title: '$prefix tip-unpub');
  HttpHit tipC2 = HttpHit(0, 'no live', {'error': 'no live'});
  HttpHit unpub = HttpHit(0, 'no live', {'error': 'no live'});
  HttpHit tipGet = HttpHit(0, 'no sid', {'error': 'no sid'});
  final c2s0 = await c.walletBal(s1);
  if (live2 != null) {
    final raced = await Future.wait([
      c.tipCheckout(
        liveId: live2,
        seller: s1,
        amountEur: 2,
        jwt: c.buyerJwt,
        extra: {
          'captured': true,
          'status': 'paid',
          'payment_status': 'paid',
        },
      ),
      c.rest(
        'PATCH',
        'lives?id=eq.$live2',
        jwt: c.buyerJwt,
        body: {'is_active': false, 'status': 'ended'},
      ),
    ]);
    tipC2 = raced[0];
    unpub = raced[1];
    final sid2 = tipC2.sessionId;
    if (sid2 != null && sid2.startsWith('cs_')) {
      tipGet = await c.tipSettleGet(sid2, jwt: c.buyerJwt);
    }
    if (tipC2.tipId != null) c.createdTipIds.add(tipC2.tipId!);
  }
  final c2s1 = await c.walletBal(s1);
  final tipC2row =
      tipC2.tipId == null ? null : await c.tipRow(tipC2.tipId!);
  final c2Open = (c2s1 - c2s0).abs() > 0.001 ||
      '${tipC2row?['status'] ?? ''}'.toLowerCase() == 'paid';
  c.probe(
    id: 'C2',
    lens: 'EJ2',
    edgeRpc: 'tip captured=true ∥ PATCH lives ended JWT buyer + GET settle',
    payload: 'live $live2 Future.wait tip+unpublish JWT buyer',
    http: 'tip ${tipC2.brief} | unpub ${unpub.brief} | get ${tipGet.brief}',
    stripeBd: 'Δ=${c2s1 - c2s0} tip=$tipC2row',
    result: c2Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: c2Open,
    race: true,
  );
  if (c2Open) {
    c.hold(
      id: 'C2-tip-unpub',
      lens: 'EJ2',
      severity: 'P0',
      title: 'Tip captured=true ∥ unpublish creditou',
      actor: 'buyer JWT',
      pre: 'tip unpaid pending; captured body ignorado',
      repro: 'Future.wait tip-checkout captured=true + PATCH lives ended JWT',
      expected: 'pending Δ=0',
      obtained: {'Δ': c2s1 - c2s0, 'tip': tipC2row},
    );
  } else {
    c.block('C2-tip', 'EJ2', 'tip∥unpublish JWT Δ=0', tipC2);
  }

  await c.ensureWalletBalance(s1, 6);
  final c3s0 = await c.walletBal(s1);
  final tids0 = await c.transferIds(s1);
  final over = await c.connect({
    'amount': 99999999,
    'idempotency_key': 'rtejOverbal1905keyxxx',
  });
  final destHit = await c.connect({
    'amount': 100,
    'idempotency_key': 'rtejDestAlien1905keyx',
    'destination': '${(await c.walletRow(s2 ?? s1))?['stripe_account_id']}',
    'stripe_account_id': '${(await c.walletRow(s2 ?? s1))?['stripe_account_id']}',
    'user_id': s2,
  });
  const sameKey = 'rtejParallelSame1905k';
  final pairSame = await Future.wait([
    c.connect({
      'amount': 100,
      'idempotency_key': sameKey,
    }, extra: {'Idempotency-Key': 'rtej-header-other-1905'}),
    c.connect({'amount': 100, 'idempotency_key': sameKey}),
  ]);
  final c3s1 = await c.walletBal(s1);
  final newTr = (await c.transferIds(s1)).difference(tids0);
  final c3Open = over.payoutOk || newTr.length > 1 || (c3s0 - c3s1) > 2.05;
  c.probe(
    id: 'C3',
    lens: 'EJ6',
    edgeRpc: 'payout over + dest alheio + ∥ mesma key vs Idempotency-Key header',
    payload:
        '99999999 · dest S2 · Future.wait body key=$sameKey vs header outra',
    http:
        'over ${over.brief} | dest ${destHit.brief} | a ${pairSame[0].brief} | b ${pairSame[1].brief}',
    stripeBd: 'Δ=${c3s1 - c3s0} tr=${newTr.toList()} n=${newTr.length}',
    result: c3Open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: c3Open,
    race: true,
  );
  if (c3Open) {
    c.hold(
      id: 'C3-payout-header',
      lens: 'EJ6',
      severity: 'P0',
      title: 'Over/dest/header Idempotency duplicou Transfer',
      actor: 'seller JWT',
      pre: 'over 400; dest JWT; 1 tr_ por body key',
      repro: 'over; dest S2; Future.wait mesma body key + header distinta',
      expected: 'over 400; ≤1 tr_',
      obtained: {'n': newTr.length, 'tr': newTr.toList(), 'Δ': c3s1 - c3s0},
    );
  } else {
    c.block('C3-payout', 'EJ6', 'over/dest/idem header ≤1 tr_', pairSame[0]);
  }

  c.probe(
    id: 'D3',
    lens: 'EJ7',
    edgeRpc: 'Transfer count pós-C3 (ledger stripe_transfer_id)',
    payload: 'newTr após over/dest/∥',
    http: 'n=${newTr.length}',
    stripeBd: 'tr=${newTr.toList()} Δwallet=${c3s1 - c3s0}',
    result: newTr.length > 1 ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: newTr.length > 1,
  );
  if (newTr.length > 1) {
    c.hold(
      id: 'D3-transfer-count',
      lens: 'EJ7',
      severity: 'P0',
      title: 'Caixa: >1 Transfer novo no C3',
      actor: 'seller JWT',
      pre: '≤1 tr_ por corrida idempotente',
      repro: 'contar stripe_transfer_id após C3',
      expected: 'n≤1',
      obtained: newTr.toList(),
    );
  } else {
    c.block('D3-count', 'EJ7', 'Transfer count ≤1', newTr.toList());
  }
}
