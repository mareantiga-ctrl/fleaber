import '_rtcb.dart';

/// Pass 1 — CB1 Connect/HTTP · CB2 return · CB4 Transfer/idempotency · CB6 actor · CB7 Δwallet
/// Novas: grego lookalike · fullwidth digits · ZW no meio (não ZWJ) · crash · webhook · dest · amount array.
/// Exactos BV/BP NÃO contar: cirílico а→a · NBSP mid-key · ZWJ · NFC/NFD.
void main() async {
  final c = Rtcb.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final w0 = await c.walletRow(c.sellerId);
  c.note('wallet0', 'seller wallet before', w0, lens: 'CB7');
  await c.ensureWalletBalance(c.sellerId!, 30);
  c.note('wallet.funded', 'seller wallet after fixture', await c.walletRow(c.sellerId),
      lens: 'CB7');

  // --- CB1 methods ---
  final put = await c.connect(
    {'amount': 100, 'idempotency_key': '${prefix}_putxxxxx'},
    method: 'PUT',
  );
  await c.expectDenied(
    id: 'cb1.put',
    lens: 'CB1',
    title: 'PUT create-connect-account cria Transfer',
    hit: put,
    actor: 'seller JWT',
    pre: 'Connect POST-only',
    repro: 'PUT /functions/v1/create-connect-account {amount:100}',
    severityIfOpen: 'P1',
    openIf: (h) => h.payoutOk,
  );

  final del = await c.connect(
    {'amount': 100, 'idempotency_key': '${prefix}_delxxxxx'},
    method: 'DELETE',
  );
  await c.expectDenied(
    id: 'cb1.del',
    lens: 'CB1',
    title: 'DELETE create-connect-account cria Transfer',
    hit: del,
    actor: 'seller JWT',
    pre: 'só POST cria levantamento',
    repro: 'DELETE create-connect-account',
    severityIfOpen: 'P1',
    openIf: (h) => h.payoutOk,
  );

  // --- CB6 destination / user_id ---
  final dest = await c.connect({
    'amount': 100,
    'idempotency_key': '${prefix}_destspoof',
    'destination': 'acct_1FakeAttackerDestXXXX',
    'stripe_account_id': 'acct_1FakeAttackerDestXXXX',
    'account': 'acct_1FakeAttackerDestXXXX',
  });
  c.note('dest.spoof', 'body destination spoof', dest.brief, lens: 'CB6');
  if (dest.payoutOk) {
    final wOwn = await c.walletRow(c.sellerId);
    final destId = dest.transferId;
    c.note('dest.spoof.ok', 'Transfer criada — confirmar se destino é o Connect do JWT', {
      'hit': dest.brief,
      'wallet': wOwn,
      'tid': destId,
    }, lens: 'CB6');
    // Transfer própria (destino cliente ignorado) = HOLD, não mint cross-user.
    c.block('dest.spoof', 'CB6', 'destination no body: Transfer (destino cliente ignorado ou Connect próprio)', dest);
  } else {
    c.block('dest.spoof', 'CB6', 'destination spoof não criou Transfer', dest);
  }

  final uidSpoof = await c.connect({
    'user_id': c.buyerId,
    'amount': 100,
    'idempotency_key': '${prefix}_uidspoof',
  });
  await c.expectDenied(
    id: 'cb6.uid',
    lens: 'CB6',
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
  c.note('buyer.payout', 'buyer JWT payout 100c', buyerPay.brief, lens: 'CB6');
  if (buyerPay.payoutOk) {
    c.note('buyer.payout.ok', 'buyer levantou da PRÓPRIA carteira (não é cross-user)',
        buyerPay.brief, lens: 'CB6');
  } else {
    c.block('buyer.payout', 'CB6', 'buyer payout recusado/sem Connect', buyerPay);
  }

  final debitJwt = await c.rpc('batata_wallet_payout_debit', {
    'p_user_id': c.sellerId,
    'p_amount_cents': 100,
    'p_idempotency_key': '${prefix}_jwtdebit',
  }, jwt: c.sellerJwt);
  await c.expectDenied(
    id: 'cb6.debit.jwt',
    lens: 'CB6',
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
    'p_stripe_transfer_id': 'tr_fake_rtcb',
    'p_failed': false,
  }, jwt: c.sellerJwt);
  await c.expectDenied(
    id: 'cb6.finish.jwt',
    lens: 'CB6',
    title: 'JWT autenticado executou batata_wallet_payout_finish',
    hit: finishJwt,
    actor: 'seller JWT',
    pre: 'GRANT só service_role',
    repro: 'POST rpc/batata_wallet_payout_finish',
    severityIfOpen: 'P0',
    openIf: (h) => h.ok && h.map?['ok'] == true,
  );

  // amount array (nova listada) + tipos hostis
  Future<void> amountCase(String id, Object amount, {String sev = 'P1'}) async {
    final h = await c.connect({
      'amount': amount,
      'idempotency_key': '${prefix}_$id'.padRight(12, 'x'),
    });
    c.note('amt.$id', 'amount=$amount', h.brief, lens: 'CB4');
    await c.expectDenied(
      id: 'cb4.amt.$id',
      lens: 'CB4',
      title: 'amount=$amount criou Transfer',
      hit: h,
      actor: 'seller JWT',
      pre: 'validação estrita number integer cents',
      repro: 'POST connect {amount: $amount}',
      severityIfOpen: sev,
      openIf: (h2) => h2.payoutOk,
    );
  }

  await amountCase('arr', [100]);
  await amountCase('nested', [
    [100]
  ]);
  await amountCase('obj', {'cents': 100});
  await amountCase('neg', -100);
  await amountCase('hex', '0x64');
  await amountCase('fwstr', '１００'); // fullwidth digits as amount string

  final amtStr = await c.connect({
    'amount': '100',
    'idempotency_key': '${prefix}_str100xx',
  });
  c.note('amt.str100', 'amount="100" desenho JS', amtStr.brief, lens: 'CB4');
  if (amtStr.payoutOk) {
    c.block('amt.str100', 'CB4', 'amount "100" aceite como 100 cents (desenho)', amtStr);
  } else {
    c.block('amt.str100', 'CB4', 'amount "100" recusado', amtStr);
  }

  // crash_inject SEM secret
  final crashNo = await c.connect({
    'amount': 100,
    'idempotency_key': '${prefix}_crashnos',
    'crash_inject': 'after_debit_before_stripe',
  });
  c.note('crash.nosec', 'crash_inject sem header secret', crashNo.brief, lens: 'CB4');
  if (crashNo.crashInjected) {
    c.hold(
      id: 'CB-P1-CRASH',
      lens: 'CB4',
      severity: 'P1',
      title: 'crash_inject activo sem secret de staging',
      actor: 'seller JWT',
      pre: 'allowPayoutCrashInject exige header secret ≥16 + sk_test',
      repro: 'POST crash_inject=after_debit_before_stripe sem x-fleaber-crash-inject-secret',
      expected: 'payout normal ou erro Connect, não 500 crash_inject',
      obtained: crashNo.brief,
    );
  } else {
    c.block('crash.nosec', 'CB4', 'crash_inject ignorado sem secret', crashNo);
  }

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
    c.note('crash.secret', 'crash_inject COM secret', hCrash.brief, lens: 'CB4');
    if (hCrash.crashInjected) {
      final retry = await c.connect({
        'amount': 100,
        'idempotency_key': keyCrash,
      });
      c.note('crash.retry', 'retry mesma key após crash debit', retry.brief, lens: 'CB4');
      if (retry.payoutOk &&
          hCrash.payoutOk &&
          retry.transferId != null &&
          hCrash.transferId != null &&
          retry.transferId != hCrash.transferId) {
        c.hold(
          id: 'CB-P0-CRASH-DUP',
          lens: 'CB4',
          severity: 'P0',
          title: 'crash_inject after_debit + retry mesma key criou 2ª Transfer',
          actor: 'seller JWT + secret staging',
          pre: 'retry deve retomar débito órfão, 1 Transfer',
          repro: 'crash after_debit_before_stripe; retry mesma idempotency_key',
          expected: '1 Transfer',
          obtained: {'crash': hCrash.brief, 'retry': retry.brief},
        );
      } else {
        c.block('crash.retry', 'CB4', 'retry após crash não duplicou Transfer', {
          'crash': hCrash.brief,
          'retry': retry.brief,
        });
      }
    } else {
      c.note('crash.secret.noop', 'secret presente mas crash não injectou', hCrash.brief,
          lens: 'CB4');
    }
  }

  // --- webhook Transfer replay ---
  final whNo = await c.edge('stripe-webhook', body: {
    'type': 'transfer.created',
    'data': {
      'object': {
        'id': 'tr_rtcb_fake',
        'object': 'transfer',
        'amount': 10000,
        'currency': 'eur',
        'destination': 'acct_fake',
        'metadata': {'fleaber_user_id': c.sellerId, 'type': 'wallet_withdrawal'},
      }
    }
  }, jwt: c.buyerJwt);
  c.note('wh.nosig', 'transfer.created sem stripe-signature', whNo.brief, lens: 'CB4');
  if (whNo.ok &&
      whNo.map?['ok'] == true &&
      whNo.map?['ignored'] == null &&
      whNo.map?['error'] == null) {
    c.hold(
      id: 'CB-P0-WH',
      lens: 'CB4',
      severity: 'P0',
      title: 'webhook transfer.created sem assinatura aceite',
      actor: 'buyer JWT / unsigned',
      pre: 'constructEventAsync exige stripe-signature',
      repro: 'POST stripe-webhook {type:transfer.created} sem Stripe-Signature',
      expected: '400 missing_signature',
      obtained: whNo.brief,
    );
  } else {
    c.block('wh.nosig', 'CB4', 'webhook recusou replay sem assinatura', whNo);
  }

  final whRefund = await c.edge('stripe-webhook', body: {
    'type': 'charge.refunded',
    'data': {
      'object': {
        'id': 'ch_rtcb_fake',
        'amount_refunded': 999999,
        'metadata': {'fleaber_order_id': '00000000-0000-0000-0000-000000000001'},
      }
    }
  });
  c.note('wh.refund.nosig', 'charge.refunded sem assinatura', whRefund.brief, lens: 'CB4');
  if (whRefund.ok && whRefund.map?['error'] == null && whRefund.map?['ignored'] == null) {
    c.hold(
      id: 'CB-P0-WH-REFUND',
      lens: 'CB4',
      severity: 'P0',
      title: 'webhook charge.refunded sem assinatura aceite',
      actor: 'anon/unsigned',
      pre: 'signature obrigatória',
      repro: 'POST stripe-webhook {type:charge.refunded} sem Stripe-Signature',
      expected: '400 missing_signature',
      obtained: whRefund.brief,
    );
  } else {
    c.block('wh.refund.nosig', 'CB4', 'charge.refunded recusado sem assinatura', whRefund);
  }

  final whBad = await c.req(
    'POST',
    '/functions/v1/stripe-webhook',
    jwt: c.sellerJwt,
    body: '{"type":"transfer.created","data":{"object":{"id":"tr_x"}}}',
    extra: {'stripe-signature': 't=1,v1=deadbeef'},
  );
  if (whBad.ok) {
    c.hold(
      id: 'CB-P0-WH-BADSIG',
      lens: 'CB4',
      severity: 'P0',
      title: 'webhook transfer.created com assinatura inválida aceite',
      actor: 'seller JWT',
      pre: 'signature fail → 400',
      repro: 'POST stripe-webhook Stripe-Signature=t=1,v1=deadbeef',
      expected: '400 invalid_signature',
      obtained: whBad.brief,
    );
  } else {
    c.block('wh.badsig', 'CB4', 'assinatura inválida recusada', whBad);
  }

  final whGet = await c.edge('stripe-webhook', method: 'GET', jwt: c.sellerJwt);
  c.note('wh.get', 'GET stripe-webhook', whGet.brief, lens: 'CB4');
  if (whGet.ok && whGet.map?['ok'] == true && whGet.map?['error'] == null) {
    c.hold(
      id: 'CB-P2-WH-GET',
      lens: 'CB4',
      severity: 'P2',
      title: 'GET stripe-webhook processou evento sem body/assinatura',
      actor: 'seller JWT GET',
      pre: 'só POST + signature',
      repro: 'GET /functions/v1/stripe-webhook',
      expected: '405 method_not_allowed',
      obtained: whGet.brief,
    );
  } else {
    c.block('wh.get', 'CB4', 'GET webhook recusado', whGet);
  }

  // --- CB2 web_return NEW (não contar 2130706433) ---
  final wrOrigins = <String, String>{
    'trail': 'https://fleaber.pt.',
    'httpallow': 'http://fleaber.pt',
    'zero': 'https://0.0.0.0',
    'v6loop': 'https://[::1]',
    'short127': 'https://127.1',
    'meta': 'https://169.254.169.254',
    'suffix': 'https://fleaber.pt.evil.com',
    'prefix': 'https://notfleaber.pt',
    'userinfo': 'https://evil.com@fleaber.pt',
    'atcolon': 'https://fleaber.pt:443@evil.com',
    'data': 'data:text/html,hi',
    'blob': 'blob:https://fleaber.pt/uuid',
    'about': 'about:blank',
    'encodedslash': 'https://fleaber.pt%2F%2Fevil.com',
  };
  for (final e in wrOrigins.entries) {
    final get = await c.edge(
      'create-connect-account',
      method: 'GET',
      qs: 'web_return_origin=${Uri.encodeQueryComponent(e.value)}',
      jwt: c.sellerJwt,
    );
    c.note('wr.get.${e.key}', 'GET ${e.value}', get.brief, lens: 'CB2');
    final loc = (get.location ?? '').toLowerCase();
    final hostile = loc.contains('evil') ||
        loc.contains('169.254') ||
        loc.contains('0.0.0.0') ||
        loc.contains('javascript') ||
        loc.startsWith('data:') ||
        loc.startsWith('blob:') ||
        loc.startsWith('file:') ||
        (loc.contains('127.0.0.1') && !e.value.contains('127.0.0.1') && e.key != 'short127' && e.key != 'v6loop') ||
        loc.contains('::1');
    if (get.status == 303 && hostile) {
      c.hold(
        id: 'CB-P2-WR-${e.key}',
        lens: 'CB2',
        severity: 'P2',
        title: 'web_return_origin ${e.value} → Location hostil',
        actor: 'seller JWT GET',
        pre: 'sanitizeWebReturnOrigin allowlist + authority cru',
        repro: 'GET create-connect-account?web_return_origin=${e.value}',
        expected: 'sem 303 hostil (HTML wallet / ignore)',
        obtained: get.brief,
      );
    } else {
      c.block('wr.get.${e.key}', 'CB2', 'web_return ${e.value} sem Location hostil', get);
    }
  }

  // --- CB4 NEW unicode pairs ---
  Future<void> judgePair({
    required String id,
    required String lens,
    required String sev,
    required String title,
    required String keyA,
    required String keyB,
    required String pre,
    required String repro,
    bool count = true,
    String designNote = '',
  }) async {
    final ev = await c.pairPayout(id, keyA, keyB, lens: lens);
    final n = (ev['new_transfer_count'] as int?) ?? 0;
    if (n >= 2) {
      if (designNote.isNotEmpty) {
        c.note('$id.design', designNote, ev, lens: lens);
      }
      c.hold(
        id: id,
        lens: lens,
        severity: sev,
        title: title,
        actor: 'seller JWT',
        pre: pre,
        repro: repro,
        expected: '1 Transfer (mesma intenção visual / fold) OU desenho documentado',
        obtained: ev,
        count: count,
      );
    } else {
      c.block(id, lens, '$title — não gerou 2 Transfers', ev);
    }
  }

  // Exactos BV/BP — HOLD, não contar
  await judgePair(
    id: 'CB-HOLD-CYR',
    lens: 'CB4',
    sev: 'P2',
    title: 'exacto cirílico а→a (não contar)',
    keyA: 'rtcblatinx1',
    keyB: 'rtcbl\u0430tinx1',
    pre: 'BRBW fold [аА]→a',
    repro: 'rtcbа vs a (U+0430)',
    count: false,
  );
  await judgePair(
    id: 'CB-HOLD-NBSP',
    lens: 'CB4',
    sev: 'P2',
    title: 'exacto NBSP mid-key (não contar)',
    keyA: 'rtcbnbsp88x',
    keyB: 'rtcb\u00A0nbsp88x',
    pre: 'BRBW strip whitespace interior incl. NBSP',
    repro: 'rtcbnbsp88x vs rtcb\\u00A0nbsp88x',
    count: false,
  );

  // Casefold — só contar se mudar desenho (app continua wd_uuid ASCII)
  await judgePair(
    id: 'CB-DESIGN-CASEFOLD',
    lens: 'CB4',
    sev: 'P3',
    title: 'casefold Payout vs payout (desenho; só contar se app mudou)',
    keyA: 'PayoutRtcb1',
    keyB: 'payoutRtcb1',
    pre: 'Edge sem toLowerCase; Flutter wd_{uuid}_{cents}_{ms}',
    repro: 'PayoutRtcb1 vs payoutRtcb1',
    count: false,
    designNote: '2 Transfers = desenho case-sensitive; app não gera mixed-case lookalike',
  );

  // NOVA: grego lookalike (α→a visual; ο→o; ρ→p)
  await judgePair(
    id: 'CB-P2-GREEK-ALPHA',
    lens: 'CB4',
    sev: 'P2',
    title: 'homóglifo grego α vs a na idempotency_key → 2 Transfers',
    keyA: 'rtcbGREEKa1',
    keyB: 'rtcbGREEK\u03B11', // GREEK SMALL LETTER ALPHA
    pre: 'payoutIdempotencyKey fold só cirílico; resto non-ASCII stripped (α≠a)',
    repro: 'rtcbGREEKa1 vs rtcbGREEK\alpha1 (U+03B1)',
  );
  await judgePair(
    id: 'CB-P2-GREEK-OMICRON',
    lens: 'CB4',
    sev: 'P2',
    title: 'homóglifo grego ο vs o na key → 2 Transfers',
    keyA: 'rtcbGREEKo1',
    keyB: 'rtcbGREEK\u03BF1', // GREEK SMALL LETTER OMICRON
    pre: 'mesma classe: strip ≠ confusable fold',
    repro: 'rtcbGREEKo1 vs rtcbGREEK\omicron1 (U+03BF)',
  );

  // NOVA: fullwidth digit substitui ASCII 1
  await judgePair(
    id: 'CB-P2-FULLWIDTH-DIGIT',
    lens: 'CB4',
    sev: 'P2',
    title: 'fullwidth １ substitui ASCII 1 na key → 2 Transfers',
    keyA: 'rtcbkeyn1xx',
    keyB: 'rtcbkeyn\uFF11xx',
    pre: 'NFKC U+FF11 → ASCII 1; se 2 Transfers, NFKC não colapsou',
    repro: 'rtcbkeyn1xx vs rtcbkeyn１xx',
  );

  // NOVA: zero-width no meio (NÃO ZWJ/ZWSP/ZWNJ 200B-200D / BOM)
  await judgePair(
    id: 'CB-P2-WJ',
    lens: 'CB4',
    sev: 'P2',
    title: 'WORD JOINER U+2060 no meio da key → 2 Transfers',
    keyA: 'rtcbwjkey88',
    keyB: 'rtcb\u2060wjkey88',
    pre: 'strip actual é ZWJ/BOM + whitespace; U+2060 é Cf; catch-all non-ASCII deve colapsar',
    repro: 'rtcbwjkey88 vs rtcb\\u2060wjkey88',
  );
  await judgePair(
    id: 'CB-P2-SOFT-HYPHEN',
    lens: 'CB4',
    sev: 'P2',
    title: 'SOFT HYPHEN U+00AD no meio da key → 2 Transfers',
    keyA: 'rtcbshykey8',
    keyB: 'rtcb\u00ADshykey8',
    pre: 'U+00AD não está no strip ZWJ/whitespace; catch-all [^\x20-\x7E] deve remover',
    repro: 'rtcbshykey8 vs rtcb\\u00ADshykey8',
  );
  await judgePair(
    id: 'CB-P2-HANGUL-FILL',
    lens: 'CB4',
    sev: 'P2',
    title: 'Hangul filler U+3164 no meio da key → 2 Transfers',
    keyA: 'rtcbhgfill8',
    keyB: 'rtcb\u3164hgfill8',
    pre: 'U+3164 invisível; catch-all deve colapsar',
    repro: 'rtcbhgfill8 vs rtcb\\u3164hgfill8',
  );

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
  }, lens: 'CB4');
  if (raceTids.length >= 2) {
    c.hold(
      id: 'CB-P0-RACE',
      lens: 'CB4',
      severity: 'P0',
      title: 'race 3× mesma idempotency_key criou ≥2 Transfers',
      actor: 'seller JWT paralelo',
      pre: 'debit ledger + Stripe fleaber_wd_{hash}',
      repro: 'Future.wait 3 POST mesma key amount=100',
      expected: '1 Transfer',
      obtained: {
        'tids': raceTids.toList(),
        'hits': raceHits.map((h) => h.brief).toList(),
      },
    );
  } else {
    c.block('race.same', 'CB4', 'race mesma key ≤1 Transfer', {
      'tids': raceTids.toList(),
      'hits': raceHits.map((h) => h.brief).toList(),
    });
  }

  final wEnd = await c.walletRow(c.sellerId);
  c.note('wallet.end.p1', 'seller wallet end pass1', wEnd, lens: 'CB7');

  await c.dumpAll('pass1.json');
}
