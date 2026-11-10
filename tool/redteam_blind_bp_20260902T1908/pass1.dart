/// RED TEAM CEGO BP pass1 — Connect/HTTP, return hijack, Transfer/webhook, Δwallet.
/// Não corrige. Staging only. Não conta exactos NFC/NFD, PUT Transfer, amount:true, entrega em morada LIKE.
import 'dart:io';

import '_rtbp.dart';

Future<void> main() async {
  final c = Rtbp.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final w0 = await c.walletOf(c.sellerId!);
  c.note('wallet.s1', 'seller wallet before', w0, lens: 'BP7');
  final ledger0 = await c.payoutLedger(limit: 5);
  c.note('ledger.s1', 'ledger head', ledger0.map((r) => {
        'k': r['idempotency_key'],
        'st': r['status'],
        'tr': r['stripe_transfer_id'],
        'cents': r['amount_cents'],
      }).toList(), lens: 'BP4');

  // ---------------------------------------------------------------------------
  // BP1 / BP4 — methods, user_id, destination spoof, amount types (array NEW)
  // Exactos NÃO contar: PUT Transfer, amount:true
  // ---------------------------------------------------------------------------
  final put = await c.connect({'amount': 100, 'idempotency_key': '${prefix}_putxxxx'},
      method: 'PUT');
  c.note('http.put', 'PUT connect (exacto AX — não contar)', put.brief, lens: 'BP1');
  if (put.status == 405) {
    c.block('http.put', 'BP1', 'PUT Transfer 405 (exacto, não contar)', put.brief);
  }

  final patch = await c.connect({'amount': 100, 'idempotency_key': '${prefix}_patchxxx'},
      method: 'PATCH');
  if (patch.status == 405 || patch.denied) {
    c.block('http.patch', 'BP1', 'PATCH connect rejeitado', patch.brief);
  } else if (patch.transferId != null) {
    c.hold(
      id: 'P1-BP1-patch-transfer',
      lens: 'BP1',
      severity: 'P1',
      title: 'PATCH create-connect-account criou Transfer',
      actor: 'seller JWT',
      pre: 'Connect POST-only após AX',
      repro: 'PATCH /functions/v1/create-connect-account {amount:100, idempotency_key}',
      expected: '405',
      obtained: patch.brief,
    );
  } else {
    c.note('http.patch', 'PATCH not 405', patch.brief, lens: 'BP1');
  }

  final del = await c.connect(null, method: 'DELETE');
  if (del.status == 405 || del.denied) {
    c.block('http.delete', 'BP1', 'DELETE connect rejeitado', del.brief);
  } else {
    c.note('http.delete', 'DELETE unexpected', del.brief, lens: 'BP1');
  }

  final uidSpoof = await c.connect({
    'user_id': c.buyerId,
    'amount': 100,
    'idempotency_key': '${prefix}_uid_spoof',
  });
  if (uidSpoof.status >= 400) {
    c.block('uid.spoof', 'BP6', 'user_id alheio rejeitado', uidSpoof.brief);
  } else if (uidSpoof.ok) {
    c.hold(
      id: 'P0-BP6-user-id-spoof',
      lens: 'BP6',
      severity: 'P0',
      title: 'Seller JWT + user_id do comprador aceite no Connect/payout',
      actor: 'seller JWT',
      pre: 'body.user_id = buyer',
      repro: 'POST create-connect-account user_id=B1 amount=100',
      expected: '400 Cannot create another user',
      obtained: uidSpoof.brief,
    );
  }

  final destSpoof = await c.connect({
    'amount': 100,
    'idempotency_key': '${prefix}_dest_spoof',
    'destination': 'acct_1EVILDESTINATION000',
    'stripe_account_id': 'acct_1EVILDESTINATION000',
    'account': 'acct_1EVILDESTINATION000',
  });
  c.note('dest.body', 'destination extra fields', destSpoof.brief, lens: 'BP4');
  if (destSpoof.ok && destSpoof.transferId != null) {
    c.note('dest.body.ok', 'payout succeeded — destination field ignored? check ledger dest via Stripe n/a',
        destSpoof.transferId, lens: 'BP4');
  } else if (destSpoof.status >= 400) {
    c.block('dest.body', 'BP4', 'payout with spoof destination did not transfer (or Connect not ready)',
        destSpoof.brief);
  }

  final arrAmt = await c.connect({
    'amount': [100],
    'idempotency_key': '${prefix}_arr_amt',
  });
  if (arrAmt.status >= 400 || arrAmt.body.contains('inválido')) {
    c.block('amt.array', 'BP1', 'amount:[100] rejeitado', arrAmt.brief);
  } else if (arrAmt.ok && arrAmt.transferId != null) {
    c.hold(
      id: 'P1-BP1-array-amount',
      lens: 'BP1',
      severity: 'P1',
      title: 'amount:[100] aceite — Number([100])=100 no JS',
      actor: 'seller JWT',
      pre: 'validação typeof number|string',
      repro: 'POST connect {amount:[100], idempotency_key}',
      expected: 'Valor de levantamento inválido',
      obtained: arrAmt.brief,
    );
  } else {
    c.note('amt.array', 'array amount neither reject nor transfer', arrAmt.brief, lens: 'BP1');
  }

  final objAmt = await c.connect({
    'amount': {'cents': 100},
    'idempotency_key': '${prefix}_obj_amt',
  });
  if (objAmt.status >= 400 || objAmt.body.contains('inválido')) {
    c.block('amt.obj', 'BP1', 'amount object rejeitado', objAmt.brief);
  } else if (objAmt.ok && objAmt.transferId != null) {
    c.hold(
      id: 'P1-BP1-object-amount',
      lens: 'BP1',
      severity: 'P1',
      title: 'amount:{cents:100} aceite',
      actor: 'seller JWT',
      pre: 'typeof não number/string',
      repro: 'POST connect {amount:{cents:100}}',
      expected: 'inválido',
      obtained: objAmt.brief,
    );
  }

  final sciAmt = await c.connect({
    'amount': '1e2',
    'idempotency_key': '${prefix}_sci_amt',
  });
  if (sciAmt.status >= 400 || sciAmt.body.contains('inválido')) {
    c.block('amt.sci', 'BP1', 'amount 1e2 rejeitado', sciAmt.brief);
  } else if (sciAmt.transferId != null) {
    c.hold(
      id: 'P1-BP1-sci-amount',
      lens: 'BP1',
      severity: 'P1',
      title: 'amount "1e2" → 100 aceite',
      actor: 'seller JWT',
      pre: '/e/i deve rejeitar',
      repro: 'POST connect amount="1e2"',
      expected: 'inválido',
      obtained: sciAmt.brief,
    );
  }

  final hexAmt = await c.connect({
    'amount': '0x64',
    'idempotency_key': '${prefix}_hex_amt',
  });
  if (hexAmt.status >= 400 || hexAmt.body.contains('inválido')) {
    c.block('amt.hex', 'BP1', 'amount 0x64 rejeitado', hexAmt.brief);
  } else if (hexAmt.transferId != null) {
    c.hold(
      id: 'P1-BP1-hex-amount',
      lens: 'BP1',
      severity: 'P1',
      title: 'amount "0x64" aceite',
      actor: 'seller JWT',
      pre: '0x rejeitado no código',
      repro: 'POST connect amount="0x64"',
      expected: 'inválido',
      obtained: hexAmt.brief,
    );
  }

  final fracAmt = await c.connect({
    'amount': 100.5,
    'idempotency_key': '${prefix}_frac_amt',
  });
  if (fracAmt.status >= 400) {
    c.block('amt.frac', 'BP1', 'amount 100.5 rejeitado', fracAmt.brief);
  } else if (fracAmt.transferId != null) {
    c.hold(
      id: 'P1-BP1-frac-amount',
      lens: 'BP1',
      severity: 'P1',
      title: 'amount 100.5 (não inteiro) aceite',
      actor: 'seller JWT',
      pre: 'isInteger required',
      repro: 'POST connect amount=100.5',
      expected: 'cêntimos inteiros',
      obtained: fracAmt.brief,
    );
  }

  final boolAmt = await c.connect({
    'amount': true,
    'idempotency_key': '${prefix}_bool_amt',
  });
  c.note('amt.true', 'amount:true (exacto AX — não contar)', boolAmt.brief, lens: 'BP1');
  if (boolAmt.status >= 400) {
    c.block('amt.true', 'BP1', 'amount:true rejeitado (exacto, não contar)', boolAmt.brief);
  }

  final buyerPay = await c.connect({
    'amount': 100,
    'idempotency_key': '${prefix}_buyer_pay',
  }, jwt: c.buyerJwt);
  c.note('buyer.payout', 'buyer tenta levantamento', buyerPay.brief, lens: 'BP6');

  final debitJwt = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': c.sellerId,
    'p_amount_cents': 100,
    'p_idempotency_key': '${prefix}_jwt_debit_xxxxxxxx',
  }, jwt: c.sellerJwt);
  if (debitJwt.denied || debitJwt.status == 404) {
    c.block('rpc.debit', 'BP6', 'JWT não executa batata_wallet_payout_debit', debitJwt.brief);
  } else if (debitJwt.ok) {
    c.hold(
      id: 'P0-BP6-jwt-payout-debit',
      lens: 'BP6',
      severity: 'P0',
      title: 'JWT autenticado executou batata_wallet_payout_debit',
      actor: 'seller JWT',
      pre: 'REVOKE authenticated',
      repro: 'POST rpc/batata_wallet_payout_debit',
      expected: '42501',
      obtained: debitJwt.brief,
    );
  }

  final finishJwt = await c.rpc('batata_wallet_payout_finish', {
    'p_idempotency_key': '${prefix}_jwt_debit_xxxxxxxx',
    'p_stripe_transfer_id': 'tr_fake',
    'p_failed': false,
  }, jwt: c.sellerJwt);
  if (finishJwt.denied || finishJwt.status == 404) {
    c.block('rpc.finish', 'BP6', 'JWT não executa batata_wallet_payout_finish', finishJwt.brief);
  } else if (finishJwt.ok) {
    c.hold(
      id: 'P0-BP6-jwt-payout-finish',
      lens: 'BP6',
      severity: 'P0',
      title: 'JWT autenticado executou batata_wallet_payout_finish',
      actor: 'seller JWT',
      pre: 'REVOKE authenticated',
      repro: 'POST rpc/batata_wallet_payout_finish',
      expected: '42501',
      obtained: finishJwt.brief,
    );
  }

  final debitAnon = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': c.sellerId,
    'p_amount_cents': 100,
    'p_idempotency_key': '${prefix}_anon_debit_xxxxxxx',
  });
  if (debitAnon.denied || debitAnon.status == 401 || debitAnon.status == 404) {
    c.block('rpc.debit.anon', 'BP6', 'anon não executa payout debit', debitAnon.brief);
  } else if (debitAnon.ok) {
    c.hold(
      id: 'P0-BP6-anon-payout-debit',
      lens: 'BP6',
      severity: 'P0',
      title: 'anon executou batata_wallet_payout_debit',
      actor: 'anon',
      pre: 'REVOKE anon',
      repro: 'POST rpc/batata_wallet_payout_debit sem JWT',
      expected: '401/42501',
      obtained: debitAnon.brief,
    );
  }

  // Wallet destination spoof via REST
  final wPatch = await c.rest('PATCH', 'wallets?id=eq.${c.sellerId}', jwt: c.sellerJwt, body: {
    'stripe_account_id': 'acct_1EVILPATCH000000',
    'balance': 9999,
  });
  final wAfterPatch = await c.walletOf(c.sellerId!);
  final patchedAcct = '${wAfterPatch?['stripe_account_id'] ?? ''}';
  final patchedBal = wAfterPatch?['balance'];
  if (wPatch.denied || wPatch.status == 401 || (wPatch.ok && (wPatch.list.isEmpty))) {
    c.block('wallet.patch', 'BP4', 'JWT PATCH wallets stripe_account_id/balance bloqueado', {
      'hit': wPatch.brief,
      'acct_now': patchedAcct,
      'bal_now': patchedBal,
    });
  } else if (patchedAcct.contains('EVIL') || (patchedBal is num && patchedBal >= 9999)) {
    c.hold(
      id: 'P0-BP4-wallet-patch-dest',
      lens: 'BP4',
      severity: 'P0',
      title: 'JWT alterou stripe_account_id ou balance da carteira',
      actor: 'seller JWT',
      pre: 'sem policy UPDATE wallets',
      repro: 'PATCH /rest/v1/wallets stripe_account_id=acct_evil balance=9999',
      expected: '0 rows / 42501',
      obtained: {'hit': wPatch.brief, 'acct': patchedAcct, 'bal': patchedBal},
    );
  } else {
    c.block('wallet.patch', 'BP4', 'PATCH wallets não persistiu spoof', {
      'hit': wPatch.brief,
      'acct': patchedAcct,
      'bal': patchedBal,
    });
  }

  final wIns = await c.rest('POST', 'wallets', jwt: c.seller2Jwt, body: {
    'id': c.seller2Id,
    'stripe_account_id': 'acct_1EVILINSERT00000',
    'balance': 8888,
  });
  if (wIns.denied || wIns.status >= 400) {
    c.block('wallet.insert', 'BP4', 'JWT INSERT wallets bloqueado', wIns.brief);
  } else if (wIns.ok) {
    final w2 = await c.walletOf(c.seller2Id!);
    if ('${w2?['stripe_account_id']}'.contains('EVIL') ||
        (w2?['balance'] is num && (w2!['balance'] as num) >= 8888)) {
      c.hold(
        id: 'P0-BP4-wallet-insert-mint',
        lens: 'BP4',
        severity: 'P0',
        title: 'JWT INSERT wallets com stripe_account_id alheio e saldo inventado',
        actor: 'seller2 JWT',
        pre: 'wallets_insert_own dropado FASE1',
        repro: 'POST /rest/v1/wallets {id:self, stripe_account_id:acct_evil, balance:8888}',
        expected: '42501 / policy denied',
        obtained: {'hit': wIns.brief, 'row': w2},
      );
    } else {
      c.note('wallet.insert', 'insert ok but not evil persist', {'hit': wIns.brief, 'row': w2},
          lens: 'BP4');
    }
  }

  // ---------------------------------------------------------------------------
  // BP2 — return hijack NEW (não contar IP decimal exacto se já baseline)
  // ---------------------------------------------------------------------------
  Future<HttpHit> getReturn(String origin) {
    return c.req(
      'GET',
      '/functions/v1/create-connect-account?web_return_origin=${Uri.encodeQueryComponent(origin)}',
      followRedirects: false,
    );
  }

  final evil = await getReturn('https://evil.com');
  final locEvil = evil.location ?? '';
  if (locEvil.contains('evil.com')) {
    c.hold(
      id: 'P1-BP2-evil-origin',
      lens: 'BP2',
      severity: 'P1',
      title: 'web_return_origin evil.com → Location hostil',
      actor: 'browser sem JWT',
      pre: 'allowlist fleaber.pt',
      repro: 'GET create-connect-account?web_return_origin=https://evil.com',
      expected: 'sem Location evil.com',
      obtained: evil.brief,
    );
  } else {
    c.block('ret.evil', 'BP2', 'evil.com não redirecciona', evil.brief);
  }

  final userinfo = await getReturn('https://evil.com@fleaber.pt');
  if ((userinfo.location ?? '').contains('evil')) {
    c.hold(
      id: 'P1-BP2-userinfo',
      lens: 'BP2',
      severity: 'P1',
      title: 'userinfo @fleaber.pt hijack',
      actor: 'browser',
      pre: 'username rejeitado no sanitizer',
      repro: 'GET web_return_origin=https://evil.com@fleaber.pt',
      expected: 'sem Location hostil',
      obtained: userinfo.brief,
    );
  } else {
    c.block('ret.userinfo', 'BP2', 'userinfo não hijack', userinfo.brief);
  }

  final sub = await getReturn('https://attacker.fleaber.pt');
  if ((sub.location ?? '').contains('attacker.fleaber.pt')) {
    c.hold(
      id: 'P1-BP2-subdomain',
      lens: 'BP2',
      severity: 'P1',
      title: 'subdomínio fleaber.pt aceite no return',
      actor: 'browser',
      pre: 'hosts exactos',
      repro: 'GET web_return_origin=https://attacker.fleaber.pt',
      expected: 'rejeitar',
      obtained: sub.brief,
    );
  } else {
    c.block('ret.sub', 'BP2', 'attacker.fleaber.pt rejeitado', sub.brief);
  }

  final idn = await getReturn('https://ﬂeaber.pt'); // ligature fl
  c.note('ret.idn', 'IDN ligature ﬂeaber.pt', idn.brief, lens: 'BP2');
  if ((idn.location ?? '').contains('evil') ||
      ((idn.location ?? '').contains('xn--') && !(idn.location ?? '').contains('fleaber.pt/wallet'))) {
    c.hold(
      id: 'P2-BP2-idn-ligature',
      lens: 'BP2',
      severity: 'P2',
      title: 'IDN/ligature host no web_return_origin',
      actor: 'browser',
      pre: 'hostAllowed exacto',
      repro: 'GET web_return_origin=https://ﬂeaber.pt (U+FB02)',
      expected: 'rejeitar',
      obtained: idn.brief,
    );
  } else {
    c.block('ret.idn', 'BP2', 'ligature host não hijack', idn.brief);
  }

  final fileUri = await getReturn('file:///etc/passwd');
  if ((fileUri.location ?? '').startsWith('file:')) {
    c.hold(
      id: 'P2-BP2-file-uri',
      lens: 'BP2',
      severity: 'P2',
      title: 'file: aceite no return',
      actor: 'browser',
      pre: 'só http/https',
      repro: 'GET web_return_origin=file:///etc/passwd',
      expected: 'rejeitar',
      obtained: fileUri.brief,
    );
  } else {
    c.block('ret.file', 'BP2', 'file: rejeitado', fileUri.brief);
  }

  final jsUri = await getReturn('javascript:alert(1)');
  if ((jsUri.location ?? '').toLowerCase().contains('javascript:')) {
    c.hold(
      id: 'P1-BP2-javascript',
      lens: 'BP2',
      severity: 'P1',
      title: 'javascript: no Location',
      actor: 'browser',
      pre: 'só http/https',
      repro: 'GET web_return_origin=javascript:alert(1)',
      expected: 'rejeitar',
      obtained: jsUri.brief,
    );
  } else {
    c.block('ret.js', 'BP2', 'javascript: rejeitado', jsUri.brief);
  }

  // IP decimal — baseline fechada; só anotar regressão se AINDA abrir
  final ipDec = await getReturn('https://2130706433');
  c.note('ret.ipdec', 'IP decimal (baseline — só regressão)', ipDec.brief, lens: 'BP2');
  final locIp = ipDec.location ?? '';
  if (locIp.contains('127.0.0.1') || locIp.contains('2130706433')) {
    c.hold(
      id: 'P2-BP2-ip-decimal-regression',
      lens: 'BP2',
      severity: 'P2',
      title: 'web_return IP decimal ainda 303 loopback (regressão do fecho claimed)',
      actor: 'browser',
      pre: 'isSuspiciousHostname no sanitizer',
      repro: 'GET web_return_origin=https://2130706433',
      expected: 'sem Location 127.0.0.1',
      obtained: ipDec.brief,
    );
  } else {
    c.block('ret.ipdec', 'BP2', 'IP decimal rejeitado (fecho ok, não contar)', ipDec.brief);
  }

  final ipv6 = await getReturn('https://[::1]');
  if ((ipv6.location ?? '').contains('::1') || (ipv6.location ?? '').contains('127.0.0.1')) {
    c.hold(
      id: 'P2-BP2-ipv6-loopback',
      lens: 'BP2',
      severity: 'P2',
      title: 'IPv6 [::1] canonicaliza para return loopback',
      actor: 'browser',
      pre: 'hostAllowed sem IPv6',
      repro: 'GET web_return_origin=https://[::1]',
      expected: 'rejeitar',
      obtained: ipv6.brief,
    );
  } else {
    c.block('ret.ipv6', 'BP2', 'IPv6 loopback rejeitado', ipv6.brief);
  }

  final encodedDot = await getReturn('https://127.0.0.1%09.evil.com');
  c.note('ret.tab', 'tab encoded host', encodedDot.brief, lens: 'BP2');

  // ---------------------------------------------------------------------------
  // BP4 — idempotency NEW: NFKC, BOM, ZWJ, casefold (NFC/NFD exacto não contar)
  // ---------------------------------------------------------------------------
  final nfc = 'payout-caf\u00e9-$prefix';
  final nfd = 'payout-cafe\u0301-$prefix';
  final hNfc = await c.connect({'amount': 100, 'idempotency_key': nfc});
  final hNfd = await c.connect({'amount': 100, 'idempotency_key': nfd});
  c.note('idemp.nfc', 'NFC (exacto — não contar)', hNfc.brief, lens: 'BP4');
  c.note('idemp.nfd', 'NFD (exacto — não contar)', hNfd.brief, lens: 'BP4');
  final tNfc = hNfc.transferId;
  final tNfd = hNfd.transferId;
  if (tNfc != null && tNfd != null && tNfc == tNfd) {
    c.block('idemp.nfc-nfd', 'BP4', 'NFC=NFD mesma Transfer (fecho ok, não contar)', tNfc);
  } else if (tNfc != null && tNfd != null && tNfc != tNfd) {
    c.note('idemp.nfc-nfd.reg', 'NFC≠NFD duas Transfers — exacto regressão, anotar mas prompt diz não contar exacto',
        {'nfc': tNfc, 'nfd': tNfd}, lens: 'BP4');
  }

  // NFKC: ligature ﬁ vs fi
  final nfkcA = '${prefix}_nfkc_fidempkey';
  final nfkcB = '${prefix}_nfkc_\uFB01dempkey'; // ﬁ vs fi
  final hA = await c.connect({'amount': 100, 'idempotency_key': nfkcA});
  final hB = await c.connect({'amount': 100, 'idempotency_key': nfkcB});
  c.note('idemp.nfkc.a', 'NFKC ascii fi', hA.brief, lens: 'BP4');
  c.note('idemp.nfkc.b', 'NFKC ligature fi', hB.brief, lens: 'BP4');
  final tA = hA.transferId;
  final tB = hB.transferId;
  final ledNfkc = await c.payoutLedger(limit: 8);
  final nfkcRows = ledNfkc
      .where((r) => '${r['created_at']}'.compareTo('2026-09-02T18:00:00') > 0)
      .toList();
  if (tA != null && tB != null && tA != tB) {
    c.hold(
      id: 'P1-BP4-nfkc-two-transfers',
      lens: 'BP4',
      severity: 'P1',
      title: 'idempotency NFKC (ﬁ vs fi) gerou duas Transfers Stripe',
      actor: 'seller JWT',
      pre: 'normalize só NFC; app gera wd_{uuid}_{cents}_{ms} (sem ligaduras)',
      repro: 'duas POST amount=100 keys NFKC-equivalentes',
      expected: '1 Transfer / 2ª idempotente',
      obtained: {'ta': tA, 'tb': tB, 'a': hA.brief, 'b': hB.brief},
    );
  } else if (tA != null && tB != null && tA == tB) {
    c.block('idemp.nfkc', 'BP4', 'NFKC colapsou para 1 Transfer', tA);
  } else {
    // Sem Transfer: ainda podemos ver 2 hashes se ambos debitaram ou ambos falharam igual
    c.note('idemp.nfkc.notr', 'sem par de Transfers — Connect/saldo?', {
      'a': hA.brief,
      'b': hB.brief,
      'same_err': hA.status == hB.status && clip(hA.body, 80) == clip(hB.body, 80),
    }, lens: 'BP4');
  }

  // BOM — JS trim remove U+FEFF nas pontas → deve colapsar
  final bomKey = '${prefix}_bomkeyxx';
  final bomPref = '\uFEFF$bomKey';
  final hBom1 = await c.connect({'amount': 100, 'idempotency_key': bomKey});
  final hBom2 = await c.connect({'amount': 100, 'idempotency_key': bomPref});
  c.note('idemp.bom.1', 'BOM none', hBom1.brief, lens: 'BP4');
  c.note('idemp.bom.2', 'BOM prefix', hBom2.brief, lens: 'BP4');
  if (hBom1.transferId != null &&
      hBom2.transferId != null &&
      hBom1.transferId != hBom2.transferId) {
    c.hold(
      id: 'P1-BP4-bom-two-transfers',
      lens: 'BP4',
      severity: 'P1',
      title: 'BOM U+FEFF na idempotency_key gerou 2ª Transfer',
      actor: 'seller JWT',
      pre: 'trim() JS deve comer BOM',
      repro: 'key vs BOM+key',
      expected: '1 Transfer',
      obtained: {'t1': hBom1.transferId, 't2': hBom2.transferId},
    );
  } else {
    c.block('idemp.bom', 'BP4', 'BOM não duplicou Transfer (ou ambos falharam igual)', {
      't1': hBom1.transferId,
      't2': hBom2.transferId,
      's1': hBom1.status,
      's2': hBom2.status,
    });
  }

  // ZWJ no meio — trim não remove
  final zwjA = '${prefix}_zwjbasexxxx';
  final zwjB = '${prefix}_zwj\u200dbasexxxx';
  final hZ1 = await c.connect({'amount': 100, 'idempotency_key': zwjA});
  final hZ2 = await c.connect({'amount': 100, 'idempotency_key': zwjB});
  c.note('idemp.zwj.a', 'ZWJ none', hZ1.brief, lens: 'BP4');
  c.note('idemp.zwj.b', 'ZWJ mid', hZ2.brief, lens: 'BP4');
  if (hZ1.transferId != null &&
      hZ2.transferId != null &&
      hZ1.transferId != hZ2.transferId) {
    c.hold(
      id: 'P2-BP4-zwj-two-transfers',
      lens: 'BP4',
      severity: 'P2',
      title: 'ZWJ no meio da key = 2 Transfers (hostile; app não gera ZWJ)',
      actor: 'seller JWT hostil',
      pre: 'normalize NFC sem strip Cf',
      repro: 'key vs key com U+200D',
      expected: 'defesa-em-profundidade: strip ignoráveis',
      obtained: {'t1': hZ1.transferId, 't2': hZ2.transferId},
    );
  } else {
    c.block('idemp.zwj', 'BP4', 'ZWJ não produziu par de Transfers', {
      't1': hZ1.transferId,
      't2': hZ2.transferId,
      's1': hZ1.status,
      's2': hZ2.status,
    });
  }

  // casefold
  final cfA = '${prefix}_CaseFoldK';
  final cfB = '${prefix}_casefoldk';
  final hC1 = await c.connect({'amount': 100, 'idempotency_key': cfA});
  final hC2 = await c.connect({'amount': 100, 'idempotency_key': cfB});
  c.note('idemp.case.a', 'CaseFold', hC1.brief, lens: 'BP4');
  c.note('idemp.case.b', 'casefold', hC2.brief, lens: 'BP4');
  if (hC1.transferId != null &&
      hC2.transferId != null &&
      hC1.transferId != hC2.transferId) {
    c.hold(
      id: 'P2-BP4-casefold-two-transfers',
      lens: 'BP4',
      severity: 'P2',
      title: 'casefold da idempotency_key = 2 Transfers (app gera lowercase wd_)',
      actor: 'seller JWT hostil',
      pre: 'sem casefold no hash',
      repro: 'PREFIX_CaseFoldK vs PREFIX_casefoldk',
      expected: 'defesa: casefold opcional; app já é estável',
      obtained: {'t1': hC1.transferId, 't2': hC2.transferId},
    );
  } else {
    c.block('idemp.case', 'BP4', 'casefold não produziu par de Transfers', {
      't1': hC1.transferId,
      't2': hC2.transferId,
      's1': hC1.status,
      's2': hC2.status,
    });
  }

  // Fullwidth compatibility
  final fwA = '${prefix}_fwkeyxxxx';
  final fwB = '${prefix}_\uFF46\uFF57keyxxxx'; // ｆｗ
  final hF1 = await c.connect({'amount': 100, 'idempotency_key': fwA});
  final hF2 = await c.connect({'amount': 100, 'idempotency_key': fwB});
  c.note('idemp.fw.a', 'fullwidth ascii', hF1.brief, lens: 'BP4');
  c.note('idemp.fw.b', 'fullwidth fw', hF2.brief, lens: 'BP4');
  if (hF1.transferId != null &&
      hF2.transferId != null &&
      hF1.transferId != hF2.transferId) {
    c.hold(
      id: 'P2-BP4-fullwidth-two-transfers',
      lens: 'BP4',
      severity: 'P2',
      title: 'NFKC fullwidth vs ASCII = 2 Transfers',
      actor: 'seller JWT hostil',
      pre: 'só NFC',
      repro: 'fwkey vs ｆｗkey',
      expected: 'NFKC se quiserem colapsar compatibility',
      obtained: {'t1': hF1.transferId, 't2': hF2.transferId},
    );
  } else {
    c.block('idemp.fw', 'BP4', 'fullwidth não produziu par de Transfers', {
      't1': hF1.transferId,
      't2': hF2.transferId,
      's1': hF1.status,
      's2': hF2.status,
    });
  }

  // Race mesma key
  final raceKey = '${prefix}_racewaitx';
  final raced = await Future.wait([
    c.connect({'amount': 100, 'idempotency_key': raceKey}),
    c.connect({'amount': 100, 'idempotency_key': raceKey}),
  ]);
  final raceIds = raced.map((h) => h.transferId).whereType<String>().toSet();
  c.note('idemp.race', 'Future.wait mesma key', {
    'a': raced[0].brief,
    'b': raced[1].brief,
    'uniq': raceIds.toList(),
  }, lens: 'BP4');
  if (raceIds.length >= 2) {
    c.hold(
      id: 'P0-BP4-race-two-transfers',
      lens: 'BP4',
      severity: 'P0',
      title: 'Future.wait mesma idempotency_key = 2 Transfers',
      actor: 'seller JWT',
      pre: 'ledger unique key + Stripe fleaber_wd_{hash}',
      repro: 'duas POST paralelas mesma key amount=100',
      expected: '1 Transfer',
      obtained: {'ids': raceIds.toList(), 'a': raced[0].brief, 'b': raced[1].brief},
    );
  } else {
    c.block('idemp.race', 'BP4', 'race mesma key ≤1 Transfer', {
      'n': raceIds.length,
      'a': raced[0].status,
      'b': raced[1].status,
    });
  }

  // crash_inject SEM secret
  final crashNo = await c.connect({
    'amount': 100,
    'idempotency_key': '${prefix}_crash_nosec',
    'crash_inject': 'after_debit_before_stripe',
  });
  c.note('crash.nosec', 'crash_inject sem header secret', crashNo.brief, lens: 'BP4');
  if (crashNo.body.contains('crash_inject') && crashNo.status == 500) {
    c.hold(
      id: 'P1-BP4-crash-inject-no-secret',
      lens: 'BP4',
      severity: 'P1',
      title: 'crash_inject activo sem secret de staging',
      actor: 'seller JWT',
      pre: 'allowPayoutCrashInject exige header secret ≥16',
      repro: 'POST crash_inject=after_debit_before_stripe sem x-fleaber-crash-inject-secret',
      expected: 'payout normal (ou erro Connect), não 500 crash_inject',
      obtained: crashNo.brief,
    );
  } else {
    c.block('crash.nosec', 'BP4', 'crash_inject ignorado sem secret', crashNo.brief);
  }

  // crash_inject COM secret (staging fixture)
  final secret = c.crashSecret;
  if (secret == null) {
    c.skip('crash.secret', 'BP4', 'sem FLEABER_STAGING_CRASH_INJECT_SECRET no env', null);
  } else {
    final keyCrash = '${prefix}_crash_secxx';
    final wBefore = await c.walletOf(c.sellerId!);
    final hCrash = await c.connect(
      {
        'amount': 100,
        'idempotency_key': keyCrash,
        'crash_inject': 'after_debit_before_stripe',
      },
      extra: {
        'x-fleaber-crash-inject-secret': secret,
        'x-fleaber-crash-inject': 'after_debit_before_stripe',
      },
    );
    c.note('crash.sec', 'crash after_debit_before_stripe', hCrash.brief, lens: 'BP4');
    final ledCrash = await c.payoutLedger(limit: 6);
    final wMid = await c.walletOf(c.sellerId!);
    final retrySame = await c.connect({'amount': 100, 'idempotency_key': keyCrash});
    c.note('crash.retry', 'retry mesma key após crash', retrySame.brief, lens: 'BP4');
    final ledAfter = await c.payoutLedger(limit: 8);
    final crashRows = ledAfter
        .where((r) => '${r['idempotency_key']}'.startsWith('p_'))
        .take(6)
        .toList();
    c.note('crash.ledger', 'ledger após crash+retry', {
      'before_bal': wBefore?['balance'],
      'mid_bal': wMid?['balance'],
      'crash500': hCrash.status == 500 && hCrash.body.contains('crash_inject'),
      'retry': retrySame.brief,
      'rows': crashRows
          .map((r) => {
                'st': r['status'],
                'tr': r['stripe_transfer_id'],
                'cents': r['amount_cents'],
              })
          .toList(),
    }, lens: 'BP7');

    if (hCrash.status == 500 &&
        hCrash.body.contains('crash_inject') &&
        retrySame.transferId != null &&
        hCrash.map?['transferId'] != null &&
        retrySame.transferId != hCrash.map!['transferId']?.toString()) {
      c.hold(
        id: 'P0-BP4-crash-retry-second-transfer',
        lens: 'BP4',
        severity: 'P0',
        title: 'crash_inject after_debit + retry mesma key criou 2ª Transfer',
        actor: 'seller JWT + secret staging',
        pre: 'retry deve finish a mesma intenção',
        repro: 'crash after_debit_before_stripe; POST outra vez mesma key',
        expected: '1 Transfer',
        obtained: {
          'crash': hCrash.brief,
          'retry': retrySame.brief,
        },
      );
    } else if (hCrash.status == 500 && retrySame.ok) {
      c.block('crash.retry', 'BP4', 'retry após crash não criou 2ª Transfer distinta', {
        'crash_tid': hCrash.map?['transferId'],
        'retry_tid': retrySame.transferId,
        'retry_idem': retrySame.map?['idempotent'],
      });
    }

    // after_stripe_before_finish
    final keyCrash2 = '${prefix}_crash_sec2x';
    final hCrash2 = await c.connect(
      {
        'amount': 100,
        'idempotency_key': keyCrash2,
        'crash_inject': 'after_stripe_before_finish',
      },
      extra: {'x-fleaber-crash-inject-secret': secret},
    );
    final retry2 = await c.connect({'amount': 100, 'idempotency_key': keyCrash2});
    c.note('crash2', 'after_stripe_before_finish + retry', {
      'crash': hCrash2.brief,
      'retry': retry2.brief,
    }, lens: 'BP4');
    final tidCrash = hCrash2.map?['transferId']?.toString();
    final tidRetry = retry2.transferId;
    if (tidCrash != null &&
        tidRetry != null &&
        tidCrash.isNotEmpty &&
        tidRetry.isNotEmpty &&
        tidCrash != tidRetry) {
      c.hold(
        id: 'P0-BP4-crash-after-stripe-second-transfer',
        lens: 'BP4',
        severity: 'P0',
        title: 'crash after_stripe_before_finish + retry = 2 Transfers',
        actor: 'seller JWT + secret staging',
        pre: 'Stripe já criou Transfer; retry deve só finish',
        repro: 'crash_inject after_stripe_before_finish; retry mesma key',
        expected: 'mesmo transferId',
        obtained: {'crash': tidCrash, 'retry': tidRetry},
      );
    } else {
      c.block('crash2.retry', 'BP4', 'retry após Transfer não duplicou id', {
        'crash': tidCrash,
        'retry': tidRetry,
        'idem': retry2.map?['idempotent'],
      });
    }
  }

  // Buyer JWT tenta Connect onboarding de S2
  final bOnS2 = await c.connect({
    'user_id': c.seller2Id,
  }, jwt: c.buyerJwt);
  if (bOnS2.status >= 400) {
    c.block('bp6.onboard.s2', 'BP6', 'buyer não cria Connect de S2', bOnS2.brief);
  } else if (bOnS2.ok && (bOnS2.map?['url'] != null || bOnS2.map?['stripeAccountId'] != null)) {
    c.hold(
      id: 'P1-BP6-buyer-onboard-seller',
      lens: 'BP6',
      severity: 'P1',
      title: 'Buyer JWT criou/obteve account link Connect de outro user_id',
      actor: 'buyer JWT',
      pre: 'user_id mismatch throw',
      repro: 'POST connect {user_id:S2} com JWT B1',
      expected: '400',
      obtained: bOnS2.brief,
    );
  }

  await c.dumpAll('pass1_findings.json');
  stdout.writeln('PASS1 done findings=${c.findings.length} blocked=${c.blocked.length}');
}
