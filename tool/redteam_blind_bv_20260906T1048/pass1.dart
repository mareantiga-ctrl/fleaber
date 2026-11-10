import '_rtbv.dart';

/// Pass 1 — BV1 Connect/HTTP · BV2 return · BV4 Transfer/idempotency · BV6 actor · BV7 Δwallet
void main() async {
  final c = Rtbv.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final w0 = await c.walletRow(c.sellerId);
  c.note('wallet0', 'seller wallet before', w0, lens: 'BV7');
  await c.ensureWalletBalance(c.sellerId!, 25);
  final wFunded = await c.walletRow(c.sellerId);
  c.note('wallet.funded', 'seller wallet after fixture credit', wFunded, lens: 'BV7');

  // --- BV1 methods (PUT exact BJ — count:false) ---
  final put = await c.connect(
    {'amount': 100, 'idempotency_key': '${prefix}_putxxxxx'},
    method: 'PUT',
  );
  await c.expectDenied(
    id: 'bv1.put',
    lens: 'BV1',
    title: 'PUT create-connect-account cria Transfer',
    hit: put,
    actor: 'seller JWT',
    pre: 'Connect POST-only (AX1)',
    repro: 'PUT /functions/v1/create-connect-account {amount:100}',
    severityIfOpen: 'P1',
    count: false,
    openIf: (h) => h.payoutOk,
  );

  final patch = await c.connect(
    {'amount': 100, 'idempotency_key': '${prefix}_patchxxx'},
    method: 'PATCH',
  );
  await c.expectDenied(
    id: 'bv1.patch',
    lens: 'BV1',
    title: 'PATCH create-connect-account cria Transfer',
    hit: patch,
    actor: 'seller JWT',
    pre: 'só POST cria levantamento',
    repro: 'PATCH create-connect-account {amount:100}',
    severityIfOpen: 'P1',
    openIf: (h) => h.payoutOk,
  );

  // --- BV6 destination / user_id spoof ---
  final dest = await c.connect({
    'amount': 100,
    'idempotency_key': '${prefix}_destspoof',
    'destination': 'acct_1FakeAttackerDestXXXX',
    'stripe_account_id': 'acct_1FakeAttackerDestXXXX',
    'account': 'acct_1FakeAttackerDestXXXX',
  });
  c.note('dest.spoof', 'body destination spoof', dest.brief, lens: 'BV6');
  if (dest.payoutOk) {
    final led = await c.payoutLedger(c.sellerId!);
    c.hold(
      id: 'BV-P1-DEST',
      lens: 'BV6',
      severity: 'P1',
      title: 'destination spoof no body foi aceite (Transfer criada)',
      actor: 'seller JWT',
      pre: 'Edge deve ignorar destination do cliente e usar Connect do JWT',
      repro: 'POST connect {amount:100, destination:acct_fake}',
      expected: 'ignorar destination ou 4xx',
      obtained: dest.brief,
      evidence: {'ledger_head': led.take(3).toList()},
    );
  } else {
    c.block('dest.spoof', 'BV6', 'destination spoof não criou Transfer (ou falhou Connect)', dest);
  }

  final uidSpoof = await c.connect({
    'user_id': c.buyerId,
    'amount': 100,
    'idempotency_key': '${prefix}_uidspoof',
  });
  await c.expectDenied(
    id: 'bv6.uid',
    lens: 'BV6',
    title: 'seller JWT + user_id=buyer cria levantamento na conta alheia',
    hit: uidSpoof,
    actor: 'seller JWT',
    pre: 'body.user_id deve igualar JWT',
    repro: 'POST connect {user_id:buyer, amount:100}',
    severityIfOpen: 'P0',
    openIf: (h) => h.payoutOk,
  );

  final buyerPay = await c.connect({
    'amount': 100,
    'idempotency_key': '${prefix}_buyerpay',
  }, jwt: c.buyerJwt);
  c.note('buyer.payout', 'buyer JWT payout 100c', buyerPay.brief, lens: 'BV6');
  // Buyer with no Connect may 400 — that is deny. Success Transfer would be own-wallet (ok) unless mint.
  if (buyerPay.payoutOk) {
    c.note('buyer.payout.ok', 'buyer levantou da PRÓPRIA carteira (não é cross-user)', buyerPay.brief, lens: 'BV6');
  } else {
    c.block('buyer.payout', 'BV6', 'buyer payout recusado/sem Connect', buyerPay);
  }

  final debitJwt = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': c.sellerId,
    'p_amount_cents': 100,
    'p_idempotency_key': '${prefix}_jwtdebit',
  }, jwt: c.sellerJwt);
  await c.expectDenied(
    id: 'bv6.debit.jwt',
    lens: 'BV6',
    title: 'JWT autenticado executou batata_wallet_payout_debit',
    hit: debitJwt,
    actor: 'seller JWT',
    pre: 'GRANT só service_role',
    repro: 'POST rpc/batata_wallet_payout_debit',
    severityIfOpen: 'P0',
    openIf: (h) => h.ok && h.map?['ok'] == true,
  );

  final finishJwt = await c.rpc('batata_wallet_payout_finish', {
    'p_idempotency_key': '${prefix}_jwtdebit',
    'p_stripe_transfer_id': 'tr_fake_bv',
    'p_failed': false,
  }, jwt: c.sellerJwt);
  await c.expectDenied(
    id: 'bv6.finish.jwt',
    lens: 'BV6',
    title: 'JWT autenticado executou batata_wallet_payout_finish',
    hit: finishJwt,
    actor: 'seller JWT',
    pre: 'GRANT só service_role',
    repro: 'POST rpc/batata_wallet_payout_finish',
    severityIfOpen: 'P0',
    openIf: (h) => h.ok && h.map?['ok'] == true,
  );

  final debitAnon = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': c.sellerId,
    'p_amount_cents': 100,
    'p_idempotency_key': '${prefix}_anondebit',
  });
  await c.expectDenied(
    id: 'bv6.debit.anon',
    lens: 'BV6',
    title: 'anon executou batata_wallet_payout_debit',
    hit: debitAnon,
    actor: 'anon',
    pre: 'REVOKE anon',
    repro: 'POST rpc/batata_wallet_payout_debit sem JWT seller',
    severityIfOpen: 'P0',
    openIf: (h) => h.ok && h.map?['ok'] == true,
  );

  // --- amount types (amount:true = exact BJ count:false) ---
  Future<void> amountCase(String id, Object amount, {bool count = true, String sev = 'P2'}) async {
    final h = await c.connect({
      'amount': amount,
      'idempotency_key': '${prefix}_$id'.padRight(12, 'x'),
    });
    c.note('amt.$id', 'amount=$amount', h.brief, lens: 'BV4');
    final transferred = h.payoutOk;
    if (id == 'str100' || id == 'float100') {
      // string integer / 100.0 === integer cents — desenho possível
      if (transferred) {
        c.note('amt.$id.design', 'aceite como 100 cêntimos (Number.isInteger)', h.brief, lens: 'BV4');
        c.block('amt.$id', 'BV4', 'amount $amount aceite como 100 cents (desenho JS integer)', h);
      } else {
        c.block('amt.$id', 'BV4', 'amount $amount recusado', h);
      }
      return;
    }
    await c.expectDenied(
      id: 'bv4.amt.$id',
      lens: 'BV4',
      title: 'amount=$amount criou Transfer',
      hit: h,
      actor: 'seller JWT',
      pre: 'validação estrita number/string integer cents',
      repro: 'POST connect {amount: $amount}',
      severityIfOpen: sev,
      count: count,
      openIf: (h2) => h2.payoutOk,
    );
  }

  await amountCase('arr', [100], sev: 'P1');
  await amountCase('obj', {'cents': 100}, sev: 'P1');
  await amountCase('str100', '100');
  await amountCase('float100', 100.0);
  await amountCase('frac', 100.5, sev: 'P2');
  await amountCase('bool', true, count: false, sev: 'P1'); // exact BJ
  await amountCase('neg', -100, sev: 'P1');
  await amountCase('hex', '0x64', sev: 'P1');
  await amountCase('sci', '1e2', sev: 'P1');

  // --- crash_inject SEM secret ---
  final crashNo = await c.connect({
    'amount': 100,
    'idempotency_key': '${prefix}_crashnos',
    'crash_inject': 'after_debit_before_stripe',
  });
  c.note('crash.nosec', 'crash_inject sem header secret', crashNo.brief, lens: 'BV4');
  if (crashNo.crashInjected) {
    c.hold(
      id: 'BV-P1-CRASH',
      lens: 'BV4',
      severity: 'P1',
      title: 'crash_inject activo sem secret de staging',
      actor: 'seller JWT',
      pre: 'allowPayoutCrashInject exige header secret ≥16 + sk_test',
      repro: 'POST crash_inject=after_debit_before_stripe sem x-fleaber-crash-inject-secret',
      expected: 'payout normal ou erro Connect, não 500 crash_inject',
      obtained: crashNo.brief,
    );
  } else {
    c.block('crash.nosec', 'BV4', 'crash_inject ignorado sem secret', crashNo);
  }

  // crash_inject COM secret — só para ver se o ponto existe; retry mesma key
  if (c.crashSecret.length >= 16 && !crashNo.crashInjected) {
    final keyCrash = '${prefix}_crashyes';
    final hCrash = await c.connect(
      {
        'amount': 100,
        'idempotency_key': keyCrash,
        'crash_inject': 'after_debit_before_stripe',
      },
      extra: {'x-fleaber-crash-inject-secret': c.crashSecret},
    );
    c.note('crash.secret', 'crash_inject COM secret', hCrash.brief, lens: 'BV4');
    if (hCrash.crashInjected) {
      final retry = await c.connect({
        'amount': 100,
        'idempotency_key': keyCrash,
      });
      c.note('crash.retry', 'retry mesma key após crash debit', retry.brief, lens: 'BV4');
      final led = await c.payoutLedger(c.sellerId!);
      final rows = led.where((r) {
        final k = '${r['idempotency_key']}';
        return k.contains(keyCrash) || true;
      }).take(8).toList();
      final tids = <String>{};
      if (retry.transferId != null) tids.add(retry.transferId!);
      // 2 transfers on retry of SAME raw key = P0
      final sameKeyRows = led.where((r) => '${r['status']}' == 'transferred').take(10).toList();
      c.note('crash.ledger', 'ledger after crash retry', {'retry': retry.brief, 'head': rows}, lens: 'BV4');
      if (retry.payoutOk && hCrash.payoutOk && retry.transferId != null && hCrash.transferId != null && retry.transferId != hCrash.transferId) {
        c.hold(
          id: 'BV-P0-CRASH-DUP',
          lens: 'BV4',
          severity: 'P0',
          title: 'crash_inject after_debit + retry mesma key criou 2ª Transfer',
          actor: 'seller JWT + secret staging',
          pre: 'retry deve retomar débito órfão, 1 Transfer',
          repro: 'crash after_debit_before_stripe; retry mesma idempotency_key',
          expected: '1 Transfer',
          obtained: {'crash': hCrash.brief, 'retry': retry.brief, 'ledger': sameKeyRows},
        );
      } else {
        c.block('crash.retry', 'BV4', 'retry após crash não duplicou Transfer', {
          'crash': hCrash.brief,
          'retry': retry.brief,
        });
      }
    } else {
      c.note('crash.secret.noop', 'secret presente mas crash não injectou (Connect?)', hCrash.brief, lens: 'BV4');
    }
  }

  // --- webhook Transfer replay ---
  final whNo = await c.edge('stripe-webhook', body: {
    'type': 'transfer.created',
    'data': {
      'object': {
        'id': 'tr_rtbv_fake',
        'object': 'transfer',
        'amount': 10000,
        'currency': 'eur',
        'destination': 'acct_fake',
        'metadata': {'fleaber_user_id': c.sellerId, 'type': 'wallet_withdrawal'},
      }
    }
  }, jwt: c.buyerJwt);
  c.note('wh.nosig', 'transfer.created sem stripe-signature', whNo.brief, lens: 'BV4');
  if (whNo.ok && whNo.map?['ok'] == true && whNo.map?['ignored'] == null && whNo.map?['error'] == null) {
    c.hold(
      id: 'BV-P0-WH',
      lens: 'BV4',
      severity: 'P0',
      title: 'webhook transfer.created sem assinatura aceite',
      actor: 'buyer JWT / unsigned',
      pre: 'constructEventAsync exige stripe-signature',
      repro: 'POST stripe-webhook {type:transfer.created} sem Stripe-Signature',
      expected: '400 missing_signature',
      obtained: whNo.brief,
    );
  } else {
    c.block('wh.nosig', 'BV4', 'webhook recusou replay sem assinatura', whNo);
  }

  final whBad = await c.req(
    'POST',
    '/functions/v1/stripe-webhook',
    jwt: c.sellerJwt,
    body: '{"type":"transfer.created","data":{"object":{"id":"tr_x"}}}',
    extra: {'stripe-signature': 't=1,v1=deadbeef'},
  );
  c.note('wh.badsig', 'transfer.created assinatura lixo', whBad.brief, lens: 'BV4');
  if (whBad.ok) {
    c.hold(
      id: 'BV-P0-WH-BADSIG',
      lens: 'BV4',
      severity: 'P0',
      title: 'webhook transfer.created com assinatura inválida aceite',
      actor: 'seller JWT',
      pre: 'signature fail → 400',
      repro: 'POST stripe-webhook Stripe-Signature=t=1,v1=deadbeef',
      expected: '400 invalid_signature',
      obtained: whBad.brief,
    );
  } else {
    c.block('wh.badsig', 'BV4', 'assinatura inválida recusada', whBad);
  }

  // --- BV2 web_return NEW (não contar 2130706433) ---
  final wrExact = await c.edge(
    'create-connect-account',
    method: 'GET',
    qs: 'web_return_origin=${Uri.encodeQueryComponent('https://2130706433')}',
    jwt: c.sellerJwt,
  );
  c.note('wr.exact.decimal', 'exact BP/BJ https://2130706433 (não contar)', wrExact.brief, lens: 'BV2');

  final wrOrigins = <String, String>{
    'evil': 'https://evil.com',
    'at': 'https://evil.com@fleaber.pt',
    'sub': 'https://attacker.fleaber.pt',
    'idn': 'https://xn--fleaber-xpa.pt',
    'cyr': 'https://fleаber.pt', // cyrillic а
    'file': 'file:///etc/passwd',
    'js': 'javascript:alert(1)',
    'nip': 'https://127.0.0.1.nip.io',
    'localtest': 'https://localtest.me',
    'v6mapped': 'https://[::ffff:127.0.0.1]',
    'octalshort': 'https://0177.0.0.1',
    'hexip': 'https://0x7f000001',
    'dotless': 'https://2130706433.fleaber.pt',
  };
  for (final e in wrOrigins.entries) {
    final get = await c.edge(
      'create-connect-account',
      method: 'GET',
      qs: 'web_return_origin=${Uri.encodeQueryComponent(e.value)}',
      jwt: c.sellerJwt,
    );
    c.note('wr.get.${e.key}', 'GET ${e.value}', get.brief, lens: 'BV2');
    final loc = (get.location ?? '').toLowerCase();
    final hostile = loc.contains('evil') ||
        loc.contains('nip.io') ||
        loc.contains('localtest') ||
        loc.contains('attacker') ||
        loc.contains('javascript') ||
        loc.startsWith('file:') ||
        (e.key != 'exact' && loc.contains('127.0.0.1') && !e.value.contains('127.0.0.1') && e.key != 'octalshort' && e.key != 'hexip' && e.key != 'v6mapped');
    // octal/hex collapse to 127 is the same class as 2130706433 — count:false
    final exactClass = e.key == 'octalshort' || e.key == 'hexip';
    if (get.status == 303 && hostile && !exactClass) {
      c.hold(
        id: 'BV-P2-WR-${e.key}',
        lens: 'BV2',
        severity: 'P2',
        title: 'web_return_origin ${e.value} → Location hostil',
        actor: 'seller JWT GET',
        pre: 'sanitizeWebReturnOrigin allowlist + authority cru',
        repro: 'GET create-connect-account?web_return_origin=${e.value}',
        expected: 'sem 303 hostil (HTML wallet / ignore)',
        obtained: get.brief,
      );
    } else if (get.status == 303 && exactClass) {
      c.hold(
        id: 'BV-P2-WR-${e.key}',
        lens: 'BV2',
        severity: 'P2',
        title: 'web_return ${e.value} 303 loopback (classe exacta decimal — não contar)',
        actor: 'seller JWT GET',
        pre: 'exact BP/BJ IP decimal/octal/hex',
        repro: 'GET web_return_origin=${e.value}',
        expected: 'recusar',
        obtained: get.brief,
        count: false,
      );
    } else {
      c.block('wr.get.${e.key}', 'BV2', 'web_return ${e.value} sem Location hostil', get);
    }
  }

  // --- BV4 casefold / homoglyph / NBSP ---
  Future<Map<String, Object?>> pairPayout(String id, String keyA, String keyB) async {
    await c.ensureWalletBalance(c.sellerId!, 20);
    final before = await c.walletBal(c.sellerId);
    final ledBefore = await c.payoutLedger(c.sellerId!);
    final tidsBefore = ledBefore
        .map((r) => '${r['stripe_transfer_id']}')
        .where((s) => s.startsWith('tr_'))
        .toSet();
    final a = await c.connect({'amount': 100, 'idempotency_key': keyA});
    final b = await c.connect({'amount': 100, 'idempotency_key': keyB});
    final after = await c.walletBal(c.sellerId);
    final ledAfter = await c.payoutLedger(c.sellerId!);
    final tidsAfter = ledAfter
        .map((r) => '${r['stripe_transfer_id']}')
        .where((s) => s.startsWith('tr_'))
        .toSet();
    final newTids = tidsAfter.difference(tidsBefore);
    final delta = after - before;
    final ev = {
      'keyA': keyA.codeUnits.toList(),
      'keyB': keyB.codeUnits.toList(),
      'hitA': a.brief,
      'hitB': b.brief,
      'tidA': a.transferId,
      'tidB': b.transferId,
      'new_transfer_ids': newTids.toList(),
      'new_transfer_count': newTids.length,
      'wallet_before': before,
      'wallet_after': after,
      'delta_eur': delta,
      'payoutOkA': a.payoutOk,
      'payoutOkB': b.payoutOk,
      'idempotentB': b.map?['idempotent'] == true,
    };
    c.note('pair.$id', 'pair $id', ev, lens: 'BV4');
    return ev;
  }

  final casefold = await pairPayout('casefold', 'PayoutRtbv1', 'payoutRtbv1');
  final nCase = (casefold['new_transfer_count'] as int?) ?? 0;
  if (nCase >= 2) {
    c.note(
      'casefold.design',
      'Payout vs payout → $nCase Transfers (app não lowercasa; keys Flutter wd_uuid_…)',
      casefold,
      lens: 'BV4',
    );
    // Desenho documentado no Edge: sem toLowerCase. App gera wd_${uuid}_cents_ms.
    // Duas intenções distintas → Transfers distintas (invariante J). Não contar.
    c.hold(
      id: 'BV-DESIGN-CASEFOLD',
      lens: 'BV4',
      severity: 'P3',
      title: 'casefold Payout vs payout cria 2 Transfers (desenho case-sensitive)',
      actor: 'seller JWT',
      pre: 'payoutIdempotencyKey sem toLowerCase; Flutter wd_uuid_amount_ms',
      repro: 'POST amount=100 key=PayoutRtbv1 depois payoutRtbv1',
      expected: 'documentar: 2 intenções se casing diferente',
      obtained: casefold,
      count: false,
    );
  } else {
    c.block('casefold', 'BV4', 'casefold não gerou 2 Transfers (Connect/saldo/colapso?)', casefold);
  }

  final homo = await pairPayout('homo', 'rtbvlatinx', 'rtbv\u0430tinxx'); // Cyrillic а
  final nHomo = (homo['new_transfer_count'] as int?) ?? 0;
  if (nHomo >= 2) {
    c.hold(
      id: 'BV-P2-HOMO',
      lens: 'BV4',
      severity: 'P2',
      title: 'homóglifo cirílico na key cria 2ª Transfer',
      actor: 'seller JWT',
      pre: 'NFKC não colapsa Cyrillic а → Latin a; ZWJ/BOM já stripped',
      repro: 'key rtbvlatinx vs rtbvаtinxx (U+0430)',
      expected: '1 Transfer se a intenção visual é a mesma, OU desenho Unicode',
      obtained: homo,
    );
  } else {
    c.block('homo', 'BV4', 'homóglifo não gerou 2 Transfers', homo);
  }

  final nbspVsNone = await pairPayout('nbsp-none', 'rtbvkey88', 'rtbv\u00A0key88');
  final nNbspNone = (nbspVsNone['new_transfer_count'] as int?) ?? 0;
  if (nNbspNone >= 2) {
    c.hold(
      id: 'BV-P2-NBSP',
      lens: 'BV4',
      severity: 'P2',
      title: 'NBSP no meio da key vs sem espaço cria 2ª Transfer',
      actor: 'seller JWT',
      pre: 'NFKC U+00A0→espaço; strip só ZWJ/BOM nas extremidades via trim, não compacta o meio',
      repro: 'key rtbvkey88 vs rtbv\\u00A0key88',
      expected: 'colapsar whitespace interior OU 1 Transfer',
      obtained: nbspVsNone,
    );
  } else {
    c.block('nbsp-none', 'BV4', 'NBSP vs sem espaço não gerou 2 Transfers', nbspVsNone);
  }

  final nbspVsSpace = await pairPayout('nbsp-space', 'rtbv k88x', 'rtbv\u00A0k88x');
  final nNbspSp = (nbspVsSpace['new_transfer_count'] as int?) ?? 0;
  if (nNbspSp >= 2) {
    c.hold(
      id: 'BV-P2-NBSP-SPACE',
      lens: 'BV4',
      severity: 'P2',
      title: 'NBSP vs espaço normal no meio não colapsam (NFKC falhou LIVE?)',
      actor: 'seller JWT',
      pre: 'NFKC deve mapear U+00A0 → U+0020',
      repro: 'key "rtbv k88x" vs "rtbv\\u00A0k88x"',
      expected: '1 Transfer (mesma key após NFKC)',
      obtained: nbspVsSpace,
    );
  } else {
    c.block('nbsp-space', 'BV4', 'NBSP vs espaço = 1 intenção (NFKC HOLD)', nbspVsSpace);
  }

  // race mesma key
  await c.ensureWalletBalance(c.sellerId!, 10);
  final raceKey = '${prefix}_racexxxx';
  final raceHits = await Future.wait([
    c.connect({'amount': 100, 'idempotency_key': raceKey}),
    c.connect({'amount': 100, 'idempotency_key': raceKey}),
    c.connect({'amount': 100, 'idempotency_key': raceKey}),
  ]);
  final raceTids = raceHits
      .map((h) => h.transferId)
      .whereType<String>()
      .where((s) => s.startsWith('tr_'))
      .toSet();
  c.note('race.same', '3x mesma key', {
    'hits': raceHits.map((h) => h.brief).toList(),
    'tids': raceTids.toList(),
  }, lens: 'BV4');
  if (raceTids.length >= 2) {
    c.hold(
      id: 'BV-P0-RACE',
      lens: 'BV4',
      severity: 'P0',
      title: 'race 3× mesma idempotency_key criou ≥2 Transfers',
      actor: 'seller JWT paralelo',
      pre: 'debit ledger + Stripe fleaber_wd_{hash}',
      repro: 'Future.wait 3 POST mesma key amount=100',
      expected: '1 Transfer',
      obtained: {'tids': raceTids.toList(), 'hits': raceHits.map((h) => h.brief).toList()},
    );
  } else {
    c.block('race.same', 'BV4', 'race mesma key ≤1 Transfer', {
      'tids': raceTids.toList(),
      'hits': raceHits.map((h) => h.brief).toList(),
    });
  }

  final wEnd = await c.walletRow(c.sellerId);
  c.note('wallet.end.p1', 'seller wallet end pass1', wEnd, lens: 'BV7');

  await c.dumpAll('pass1.json');
}
