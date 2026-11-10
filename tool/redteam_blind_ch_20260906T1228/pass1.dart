import 'dart:convert';

import '_rtch.dart';

/// Pass 1 — CH-A matriz ≥8 keys · CH-B dest/amount/mint · CH-C crash/webhook · CH-D RLS
/// Exactos BXCC NÃO contar: Greek α/ο/ρ · Cyrillic а · NBSP · dual Transfer clássico residual.
void main() async {
  final c = Rtch.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final w0 = await c.walletRow(c.sellerId);
  c.note('wallet0', 'seller wallet before', w0, lens: 'CH7');
  await c.ensureWalletBalance(c.sellerId!, 50);
  c.note('wallet.funded', 'seller after fixture', await c.walletRow(c.sellerId),
      lens: 'CH7');

  final ownAcct = '${w0?['stripe_account_id'] ?? ''}';
  final others = await c.otherConnectAccounts(c.sellerId!);
  c.note('dest.others', 'outras contas Connect na BD', others, lens: 'CH4');

  // --- CH-D RLS: INSERT/UPDATE wallet JWT ---
  final insOwn = await c.rest('POST', 'wallets', jwt: c.sellerJwt, body: {
    'id': c.sellerId,
    'balance': 99999.99,
  });
  await c.expectDenied(
    id: 'CH-P0-WALLET-INS-OWN',
    lens: 'CH5',
    title: 'JWT INSERT wallets própria com saldo 99999',
    hit: insOwn,
    actor: 'seller JWT',
    pre: 'INSERT wallets revogado; sem policy insert',
    repro: 'POST /rest/v1/wallets {id:self, balance:99999.99}',
    severityIfOpen: 'P0',
    openIf: (h) => h.ok,
  );

  final insOther = await c.rest('POST', 'wallets', jwt: c.sellerJwt, body: {
    'id': c.buyerId,
    'balance': 88888.00,
    'stripe_account_id': 'acct_rtch_mint',
  });
  await c.expectDenied(
    id: 'CH-P0-WALLET-INS-OTHER',
    lens: 'CH5',
    title: 'JWT INSERT wallets do comprador',
    hit: insOther,
    actor: 'seller JWT',
    pre: 'RLS insert dropped + revoke',
    repro: 'POST wallets {id:buyer, balance:88888}',
    severityIfOpen: 'P0',
    openIf: (h) => h.ok,
  );

  final balBeforePatch = await c.walletBal(c.sellerId);
  final updBal = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {'balance': 77777.00},
  );
  final balAfterPatch = await c.walletBal(c.sellerId);
  c.note('rls.patch.bal', 'JWT PATCH balance', {
    'hit': updBal.brief,
    'before': balBeforePatch,
    'after': balAfterPatch,
  }, lens: 'CH5');
  if (updBal.ok && (balAfterPatch - balBeforePatch).abs() > 0.009) {
    c.hold(
      id: 'CH-P0-WALLET-PATCH-BAL',
      lens: 'CH5',
      severity: 'P0',
      title: 'JWT PATCH wallets.balance mintou saldo',
      actor: 'seller JWT',
      pre: 'sem policy UPDATE wallets',
      repro: 'PATCH wallets?id=eq.self {balance:77777}',
      expected: 'denied, Δ=0',
      obtained: {
        'hit': updBal.brief,
        'before': balBeforePatch,
        'after': balAfterPatch,
      },
    );
  } else {
    c.block('rls.patch.bal', 'CH5', 'JWT PATCH balance recusado ou Δ=0', updBal);
  }

  final updOtherBal = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.buyerId}',
    jwt: c.sellerJwt,
    body: {'balance': 66666.00},
  );
  await c.expectDenied(
    id: 'CH-P0-WALLET-PATCH-OTHER',
    lens: 'CH6',
    title: 'JWT PATCH balance da carteira alheia',
    hit: updOtherBal,
    actor: 'seller JWT',
    pre: 'RLS select/update own only',
    repro: 'PATCH wallets?id=eq.buyer {balance:66666}',
    severityIfOpen: 'P0',
    openIf: (h) => h.ok,
  );

  final otherAcct = others.isNotEmpty
      ? '${others.first['stripe_account_id']}'
      : 'acct_1RTCHOtherSellerXXXX';
  final updDest = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {'stripe_account_id': otherAcct},
  );
  final rowAfterDest = await c.walletRow(c.sellerId);
  c.note('rls.patch.dest', 'JWT PATCH stripe_account_id', {
    'hit': updDest.brief,
    'wanted': otherAcct,
    'now': rowAfterDest?['stripe_account_id'],
  }, lens: 'CH4');
  final destHijacked = updDest.ok &&
      '${rowAfterDest?['stripe_account_id']}' == otherAcct &&
      otherAcct != ownAcct &&
      otherAcct.isNotEmpty;
  if (destHijacked) {
    c.hold(
      id: 'CH-P1-WALLET-DEST-PATCH',
      lens: 'CH4',
      severity: 'P1',
      title: 'JWT PATCH stripe_account_id para conta de outro seller',
      actor: 'seller JWT',
      pre: 'sem UPDATE policy; destination vem do wallet gravado',
      repro: 'PATCH wallets {stripe_account_id: acct_outro}',
      expected: 'denied',
      obtained: {
        'hit': updDest.brief,
        'own': ownAcct,
        'now': rowAfterDest?['stripe_account_id'],
      },
    );
  } else {
    c.block('rls.patch.dest', 'CH4', 'JWT não alterou stripe_account_id', {
      'hit': updDest.brief,
      'now': rowAfterDest?['stripe_account_id'],
    });
  }

  final ledJwt = await c.rest('POST', 'wallet_payout_ledger', jwt: c.sellerJwt, body: {
    'idempotency_key': '${prefix}_ledjwtxx',
    'user_id': c.sellerId,
    'amount_cents': 100,
    'amount_eur': 1.00,
    'status': 'transferred',
    'stripe_transfer_id': 'tr_rtch_fake_ledger',
  });
  await c.expectDenied(
    id: 'CH-P0-LEDGER-INS',
    lens: 'CH5',
    title: 'JWT INSERT wallet_payout_ledger transferred',
    hit: ledJwt,
    actor: 'seller JWT',
    pre: 'ledger sem INSERT policy authenticated',
    repro: 'POST wallet_payout_ledger status=transferred',
    severityIfOpen: 'P0',
    openIf: (h) => h.ok,
  );

  // --- CH-B destination body = conta real de outro seller ---
  final destBody = await c.connect({
    'amount': 100,
    'idempotency_key': '${prefix}_destrealx',
    'destination': otherAcct,
    'stripe_account_id': otherAcct,
    'account': otherAcct,
    'connect_account': otherAcct,
    'currency': 'usd',
  });
  c.note('dest.body', 'body destination=acct outro + currency usd', destBody.brief,
      lens: 'CH4');
  if (destBody.payoutOk) {
    final logs = await c.payoutLogs(limit: 6);
    c.note('dest.body.logs', 'app_logs pós dest spoof', logs, lens: 'CH4');
    final diverted = logs.any((row) {
      final blob = '${row['error_message']}${row['device_info']}';
      return blob.contains(otherAcct) &&
          otherAcct.isNotEmpty &&
          otherAcct != ownAcct &&
          blob.contains('payout_start');
    });
    if (diverted) {
      c.hold(
        id: 'CH-P0-DEST-SWAP',
        lens: 'CH4',
        severity: 'P0',
        title: 'Transfer destination = conta Stripe de outro seller',
        actor: 'seller JWT',
        pre: 'destination do body ignorado; usa Connect do JWT',
        repro: 'POST connect {amount:100, destination:acct_outro, currency:usd}',
        expected: 'Transfer para Connect próprio (acct JWT)',
        obtained: {
          'hit': destBody.brief,
          'other': otherAcct,
          'own': ownAcct,
          'logs': logs,
        },
      );
    } else {
      c.block('dest.body', 'CH4', 'Transfer própria; dest/currency body ignorados', {
        'hit': destBody.brief,
        'tid': destBody.transferId,
        'other': otherAcct,
        'own': ownAcct,
      });
    }
  } else {
    c.block('dest.body', 'CH4', 'destination body não criou Transfer', destBody);
  }

  // mint: payout > balance
  final balNow = await c.walletBal(c.sellerId);
  final huge = await c.connect({
    'amount': 99999999,
    'idempotency_key': '${prefix}_mintxxxx',
  });
  final balAfterHuge = await c.walletBal(c.sellerId);
  c.note('mint.huge', 'payout 99999999c vs saldo $balNow', {
    'hit': huge.brief,
    'dBal': balAfterHuge - balNow,
  }, lens: 'CH7');
  if (huge.payoutOk || (balAfterHuge - balNow) < -1) {
    c.hold(
      id: 'CH-P0-MINT-OVER',
      lens: 'CH7',
      severity: 'P0',
      title: 'payout > available balance debitou/mintou',
      actor: 'seller JWT',
      pre: 'debit condicional balance >= amount',
      repro: 'POST connect amount=99999999',
      expected: 'insufficient_balance, Δ=0, sem Transfer',
      obtained: {
        'hit': huge.brief,
        'before': balNow,
        'after': balAfterHuge,
      },
    );
  } else {
    c.block('mint.huge', 'CH7', 'payout>balance recusado Δ≈0', huge);
  }

  Future<void> amountCase(String id, Object amount, {String sev = 'P1'}) async {
    final h = await c.connect({
      'amount': amount,
      'idempotency_key': '${prefix}_$id'.padRight(12, 'x'),
    });
    c.note('amt.$id', 'amount=$amount', h.brief, lens: 'CH4');
    await c.expectDenied(
      id: 'ch4.amt.$id',
      lens: 'CH4',
      title: 'amount=$amount criou Transfer',
      hit: h,
      actor: 'seller JWT',
      pre: 'validação estrita integer cents',
      repro: 'POST connect {amount: $amount}',
      severityIfOpen: sev,
      openIf: (h2) => h2.payoutOk,
    );
  }

  await amountCase('arr', [100]);
  await amountCase('neg', -100);
  await amountCase('flt', 100.5);
  await amountCase('fltstr', '100.5');
  await amountCase('hex', '0x64');
  await amountCase('obj', {'cents': 100, 'currency': 'eur'});

  final amtStr = await c.connect({
    'amount': '100',
    'idempotency_key': '${prefix}_str100xx',
  });
  c.note('amt.str100', 'amount="100" desenho JS', amtStr.brief, lens: 'CH4');
  if (amtStr.payoutOk) {
    c.block('amt.str100', 'CH4', 'amount "100" aceite como 100c (desenho)', amtStr);
  } else {
    c.block('amt.str100', 'CH4', 'amount "100" recusado', amtStr);
  }

  // --- CH-C crash_inject ---
  final crashNo = await c.connect({
    'amount': 100,
    'idempotency_key': '${prefix}_crashnos',
    'crash_inject': 'after_debit_before_stripe',
  });
  c.note('crash.nosec', 'crash_inject sem secret', crashNo.brief, lens: 'CH4');
  if (crashNo.crashInjected) {
    c.hold(
      id: 'CH-P1-CRASH-NOSEC',
      lens: 'CH4',
      severity: 'P1',
      title: 'crash_inject activo sem secret de staging',
      actor: 'seller JWT',
      pre: 'allowPayoutCrashInject exige header secret ≥16 + sk_test',
      repro: 'POST crash_inject=after_debit_before_stripe sem secret',
      expected: 'payout normal, não 500 crash_inject',
      obtained: crashNo.brief,
    );
  } else {
    c.block('crash.nosec', 'CH4', 'crash_inject ignorado sem secret', crashNo);
  }

  if (c.crashSecret.length >= 16 && !crashNo.crashInjected) {
    Future<void> crashRetry(String point) async {
      final keyCrash = '${prefix}_${point.substring(0, 8)}';
      final hCrash = await c.connect(
        {
          'amount': 100,
          'idempotency_key': keyCrash,
          'crash_inject': point,
        },
        extra: {'x-fleaber-crash-inject-secret': c.crashSecret},
      );
      c.note('crash.$point', 'crash_inject $point', hCrash.brief, lens: 'CH4');
      final retry = await c.connect({
        'amount': 100,
        'idempotency_key': keyCrash,
      });
      c.note('crash.$point.retry', 'retry mesma key', retry.brief, lens: 'CH4');
      final tids = <String>{
        if (hCrash.transferId != null &&
            hCrash.transferId!.startsWith('tr_'))
          hCrash.transferId!,
        if (retry.transferId != null && retry.transferId!.startsWith('tr_'))
          retry.transferId!,
      };
      if (tids.length >= 2) {
        c.hold(
          id: 'CH-P0-CRASH-$point',
          lens: 'CH4',
          severity: 'P0',
          title: 'crash_inject $point + retry criou 2 Transfers',
          actor: 'seller JWT + secret staging',
          pre: 'retry retoma débito órfão / Stripe idempotency',
          repro: 'crash $point; retry mesma idempotency_key',
          expected: '≤1 Transfer',
          obtained: {
            'crash': hCrash.brief,
            'retry': retry.brief,
            'tids': tids.toList(),
          },
        );
      } else {
        c.block('crash.$point', 'CH4', 'retry após $point não duplicou', {
          'crash': hCrash.brief,
          'retry': retry.brief,
          'tids': tids.toList(),
        });
      }
    }

    await crashRetry('after_debit_before_stripe');
    await crashRetry('after_stripe_before_finish');
  }

  // --- CH-C webhook ---
  final whNo = await c.edge('stripe-webhook', body: {
    'id': 'evt_rtch_old',
    'object': 'event',
    'created': 1600000000,
    'type': 'transfer.created',
    'data': {
      'object': {
        'id': 'tr_rtch_fake',
        'object': 'transfer',
        'amount': 10000,
        'currency': 'eur',
        'destination': otherAcct,
        'created': 1600000000,
        'metadata': {'fleaber_user_id': c.sellerId, 'type': 'wallet_withdrawal'},
      }
    }
  }, jwt: c.buyerJwt);
  c.note('wh.nosig', 'transfer.created antigo sem sig', whNo.brief, lens: 'CH4');
  if (whNo.ok &&
      whNo.map?['ok'] == true &&
      whNo.map?['ignored'] == null &&
      whNo.map?['error'] == null) {
    c.hold(
      id: 'CH-P0-WH-NOSIG',
      lens: 'CH4',
      severity: 'P0',
      title: 'webhook transfer.created antigo sem assinatura aceite',
      actor: 'buyer JWT / unsigned',
      pre: 'constructEventAsync exige stripe-signature',
      repro: 'POST stripe-webhook event created=1600000000 sem Stripe-Signature',
      expected: '400 missing_signature',
      obtained: whNo.brief,
    );
  } else {
    c.block('wh.nosig', 'CH4', 'webhook recusou replay sem assinatura', whNo);
  }

  final oldTs = 't=1600000000,v1=deadbeefdeadbeef';
  final whOld = await c.req(
    'POST',
    '/functions/v1/stripe-webhook',
    jwt: c.sellerJwt,
    body: jsonEncode({
      'id': 'evt_rtch_replay',
      'type': 'checkout.session.completed',
      'created': 1600000000,
      'data': {
        'object': {
          'id': 'cs_rtch_old',
          'payment_status': 'paid',
          'metadata': {'order_id': '00000000-0000-0000-0000-000000000001'},
        }
      }
    }),
    extra: {'stripe-signature': oldTs},
  );
  c.note('wh.oldsig', 'evento antigo + sig lixo', whOld.brief, lens: 'CH4');
  if (whOld.ok) {
    c.hold(
      id: 'CH-P0-WH-OLD',
      lens: 'CH4',
      severity: 'P0',
      title: 'webhook evento antigo (t=2020) com assinatura inválida aceite',
      actor: 'seller JWT',
      pre: 'signature fail → 400; created antigo irrelevante se sig falha',
      repro: 'POST stripe-webhook Stripe-Signature=t=1600000000,v1=deadbeef',
      expected: '400 invalid_signature',
      obtained: whOld.brief,
    );
  } else {
    c.block('wh.oldsig', 'CH4', 'evento antigo + sig inválida recusado', whOld);
  }

  // --- CH-A idempotency matrix ≥8 keys ---
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
    if (keyA.trim().length < 8 || keyB.trim().length < 8) {
      c.note('$id.short', 'key <8 skipped fold pair', {'a': keyA, 'b': keyB},
          lens: lens);
    }
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
        expected: '1 Transfer (fold/NFKC/strip) OU desenho documentado',
        obtained: ev,
        count: count,
      );
    } else {
      c.block(id, lens, '$title — não gerou 2 Transfers', ev);
    }
  }

  // Exactos BXCC — HOLD, não contar
  await judgePair(
    id: 'CH-HOLD-GREEK-ALPHA',
    lens: 'CH1',
    sev: 'P2',
    title: 'exacto grego α→a (não contar BXCC)',
    keyA: 'rtchGREEKa1',
    keyB: 'rtchGREEK\u03B11',
    pre: 'BXCC fold [αΑ]→a',
    repro: 'rtchGREEKa1 vs rtchGREEK\\u03B11',
    count: false,
  );
  await judgePair(
    id: 'CH-HOLD-CYR',
    lens: 'CH1',
    sev: 'P2',
    title: 'exacto cirílico а→a (não contar)',
    keyA: 'rtchlatinx1',
    keyB: 'rtchl\u0430tinx1',
    pre: 'fold [аА]→a',
    repro: 'a vs U+0430',
    count: false,
  );
  await judgePair(
    id: 'CH-HOLD-NBSP',
    lens: 'CH1',
    sev: 'P2',
    title: 'exacto NBSP mid-key (não contar)',
    keyA: 'rtchnbsp88x',
    keyB: 'rtch\u00A0nbsp88x',
    pre: 'strip whitespace incl. NBSP',
    repro: 'NBSP interior',
    count: false,
  );

  // 1 Armenian օ vs o
  await judgePair(
    id: 'CH-P2-ARMENIAN-OH',
    lens: 'CH1',
    sev: 'P2',
    title: 'homóglifo arménio օ vs o → 2 Transfers',
    keyA: 'rtchoARMN88',
    keyB: 'rtch\u0585ARMN88',
    pre: 'fold sem Armenian; catch-all apaga օ ≠ o',
    repro: 'rtchoARMN88 vs rtchօARMN88 (U+0585)',
  );
  // 2 Georgian ო vs o
  await judgePair(
    id: 'CH-P2-GEORGIAN-ON',
    lens: 'CH1',
    sev: 'P2',
    title: 'homóglifo georgiano ო vs o → 2 Transfers',
    keyA: 'rtchoGEOR88',
    keyB: 'rtch\u10DDGEOR88',
    pre: 'fold sem Georgian; strip ≠ confusable',
    repro: 'rtchoGEOR88 vs rtchოGEOR88 (U+10DD)',
  );
  // 3 Math bold o (NFKC deve colapsar)
  await judgePair(
    id: 'CH-P2-MATH-BOLD-O',
    lens: 'CH1',
    sev: 'P2',
    title: 'Mathematical bold 𝐨 vs o → 2 Transfers',
    keyA: 'rtchoMATH88',
    keyB: 'rtch\u{1D428}MATH88',
    pre: 'NFKC U+1D428 → o; se 2 Transfers, NFKC falhou',
    repro: 'rtchoMATH88 vs 𝐨 (U+1D428)',
  );
  // 4 Math monospace a
  await judgePair(
    id: 'CH-P2-MATH-MONO-A',
    lens: 'CH1',
    sev: 'P2',
    title: 'Mathematical monospace 𝚊 vs a → 2 Transfers',
    keyA: 'rtchaMONO88',
    keyB: 'rtch\u{1D68A}MONO88',
    pre: 'NFKC U+1D68A → a',
    repro: 'rtchaMONO88 vs 𝚊 (U+1D68A)',
  );
  // 5 Fullwidth latin o
  await judgePair(
    id: 'CH-P2-FULLWIDTH-O',
    lens: 'CH1',
    sev: 'P2',
    title: 'fullwidth ｏ vs o → 2 Transfers',
    keyA: 'rtchoFULL88',
    keyB: 'rtch\uFF4FFULL88',
    pre: 'NFKC U+FF4F → o',
    repro: 'rtchoFULL88 vs ｏ (U+FF4F)',
  );
  // 6 Combining acute on o
  await judgePair(
    id: 'CH-P2-COMBINING-ACUTE',
    lens: 'CH1',
    sev: 'P2',
    title: 'o + combining acute vs o → 2 Transfers',
    keyA: 'rtchoCOMB88',
    keyB: 'rtcho\u0301COMB88',
    pre: 'NFKC pode compor ó depois strip; o latino fica',
    repro: 'rtchoCOMB88 vs rtcho\\u0301COMB88',
  );
  // 7 CGJ mid-key
  await judgePair(
    id: 'CH-P2-CGJ',
    lens: 'CH1',
    sev: 'P2',
    title: 'CGJ U+034F no meio da key → 2 Transfers',
    keyA: 'rtchcgjkey8',
    keyB: 'rtch\u034Fcgjkey8',
    pre: 'CGJ não está no strip ZWJ; catch-all non-ASCII deve remover',
    repro: 'rtchcgjkey8 vs rtch\\u034Fcgjkey8',
  );
  // 8 Turkish İ vs I (casefold / strip)
  await judgePair(
    id: 'CH-P2-TURKISH-I',
    lens: 'CH1',
    sev: 'P2',
    title: 'İ (U+0130) vs I na key → 2 Transfers',
    keyA: 'rtchIkeyx88',
    keyB: 'rtch\u0130keyx88',
    pre: 'sem toLowerCase; İ non-ASCII é stripped ≠ I',
    repro: 'rtchIkeyx88 vs rtchİkeyx88',
  );
  // extra: Greek upsilon (NÃO α/ο/ρ BXCC)
  await judgePair(
    id: 'CH-P2-GREEK-UPSILON',
    lens: 'CH1',
    sev: 'P2',
    title: 'homóglifo grego υ vs u (fora do fold α/ο/ρ) → 2 Transfers',
    keyA: 'rtchuUPSL88',
    keyB: 'rtch\u03C5UPSL88',
    pre: 'BXCC fold só α/ο/ρ (+lista); υ não mapeia para u',
    repro: 'rtchuUPSL88 vs υ (U+03C5)',
  );
  // casefold I vs i — CONTA se 2 payouts (pedido CH)
  await judgePair(
    id: 'CH-P2-CASEFOLD-Ii',
    lens: 'CH1',
    sev: 'P2',
    title: 'casefold I vs i → 2 Transfers',
    keyA: 'rtchIcase88',
    keyB: 'rtchicase88',
    pre: 'payoutIdempotencyKey sem toLowerCase; app wd_uuid ASCII',
    repro: 'rtchIcase88 vs rtchicase88',
    designNote: '2 Transfers = gap case-sensitive; contar por pedido CH',
  );
  // length boundary: 7 vs 8
  final short7 = await c.connect({
    'amount': 100,
    'idempotency_key': 'rtch777',
  });
  c.note('key.len7', 'key 7 chars', short7.brief, lens: 'CH1');
  if (short7.payoutOk) {
    c.hold(
      id: 'CH-P1-KEYLEN7',
      lens: 'CH1',
      severity: 'P1',
      title: 'idempotency_key com 7 chars criou Transfer',
      actor: 'seller JWT',
      pre: 'rawKey.length < 8 rejeita',
      repro: 'POST connect idempotency_key=rtch777',
      expected: '400 key em falta',
      obtained: short7.brief,
    );
  } else {
    c.block('key.len7', 'CH1', 'key 7 chars recusada', short7);
  }

  // truncation: keys que diferem só após fold vazio vs ASCII
  await judgePair(
    id: 'CH-P2-STRIP-EMPTY',
    lens: 'CH1',
    sev: 'P2',
    title: '8 marks combining (fold vazio) vs ASCII mínima → 2 Transfers',
    keyA: 'rtchempty8',
    keyB: '\u0301\u0301\u0301\u0301\u0301\u0301\u0301\u0301',
    pre: 'length check no RAW (≥8); fold apaga marks → hash userId+vazio',
    repro: 'rtchempty8 vs 8× U+0301',
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
  }, lens: 'CH1');
  if (raceTids.length >= 2) {
    c.hold(
      id: 'CH-P0-RACE-SAME',
      lens: 'CH1',
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
    c.block('race.same', 'CH1', 'race mesma key ≤1 Transfer', {
      'tids': raceTids.toList(),
      'hits': raceHits.map((h) => h.brief).toList(),
    });
  }

  // race lookalike Armenian (2 intents visuais)
  await c.ensureWalletBalance(c.sellerId!, 10);
  final kLat = 'rtchoRACE88';
  final kArm = 'rtch\u0585RACE88';
  final lookHits = await Future.wait([
    c.connect({'amount': 100, 'idempotency_key': kLat}),
    c.connect({'amount': 100, 'idempotency_key': kArm}),
  ]);
  final lookTids = lookHits
      .map((h) => h.transferId)
      .whereType<String>()
      .where((s) => s.startsWith('tr_'))
      .toSet();
  c.note('race.armenian', 'parallel o vs օ', {
    'hits': lookHits.map((h) => h.brief).toList(),
    'tids': lookTids.toList(),
  }, lens: 'CH1');
  if (lookTids.length >= 2) {
    c.hold(
      id: 'CH-P2-RACE-ARMENIAN',
      lens: 'CH1',
      severity: 'P2',
      title: 'Future.wait o vs օ criou 2 Transfers',
      actor: 'seller JWT paralelo',
      pre: 'mesma classe Armenian; prova race',
      repro: 'Future.wait latin o + Armenian օ',
      expected: '1 Transfer se fold confusable',
      obtained: {
        'tids': lookTids.toList(),
        'hits': lookHits.map((h) => h.brief).toList(),
      },
    );
  } else {
    c.block('race.armenian', 'CH1', 'race o vs օ ≤1 Transfer', lookTids.toList());
  }

  final wEnd = await c.walletRow(c.sellerId);
  c.note('wallet.end.p1', 'seller wallet end pass1', wEnd, lens: 'CH7');

  await c.dumpAll('pass1.json');
}
