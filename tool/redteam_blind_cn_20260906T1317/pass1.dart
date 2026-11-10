import '_rtcn.dart';

/// Pass 1 — CN-A ≥16 keys (Coptic/Cherokee/length/parallel) · CN-B dest/amount · CN-C crash/webhook
/// Residual CDCI ≤3: arménio օ · grego α · I/i. Não contar exactos CDCI.
void main() async {
  final c = Rtcn.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureSeller2();

  final w0 = await c.walletRow(c.sellerId);
  c.note('wallet0', 'seller wallet before', w0, lens: 'CN7');
  await c.ensureWalletBalance(c.sellerId!, 90);
  c.note('wallet.funded', 'seller after fixture', await c.walletRow(c.sellerId),
      lens: 'CN7');

  final ownAcct = '${w0?['stripe_account_id'] ?? ''}';
  final others = await c.otherConnectAccounts(c.sellerId!);
  c.note('dest.others', 'outras contas Connect', others, lens: 'CN4');
  final otherAcct = others.isNotEmpty
      ? '${others.first['stripe_account_id']}'
      : 'acct_1RTCNOtherSellerXXXX';

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
  }) async {
    final ev = await c.pairPayout(id, keyA, keyB, lens: lens);
    final n = (ev['new_transfer_count'] as int?) ?? 0;
    final tids = (ev['new_transfer_ids'] as List?)?.join(',') ?? '';
    c.probe(
      id: id,
      lens: lens,
      payload: 'amount=100 keyA=$keyA keyB=$keyB',
      httpBd: 'n_tr=$n tids=$tids Δ=${ev['delta_eur']} A=${ev['hitA']} B=${ev['hitB']}',
      result: n >= 2 ? 'FAIL' : 'HOLD',
    );
    if (n >= 2) {
      c.hold(
        id: id,
        lens: lens,
        severity: sev,
        title: title,
        actor: 'seller JWT',
        pre: pre,
        repro: repro,
        expected: '1 Transfer (fold CDCI) OU desenho documentado',
        obtained: ev,
        count: count,
      );
    } else {
      c.block(id, lens, '$title — n_tr=$n', ev);
    }
  }

  // --- CN-B Transfer/amount ≥4 ---
  final destBody = await c.connect({
    'amount': 100,
    'idempotency_key': '${prefix}_destrealx',
    'destination': otherAcct,
    'stripe_account_id': otherAcct,
    'account': otherAcct,
    'connect_account': otherAcct,
    'currency': 'usd',
  });
  c.note('dest.body', 'destination alheio + currency usd', destBody.brief,
      lens: 'CN4');
  var destDiverted = false;
  if (destBody.payoutOk) {
    final logs = await c.payoutLogs(limit: 8);
    destDiverted = logs.any((row) {
      final blob = '${row['error_message']}${row['device_info']}';
      return blob.contains(otherAcct) &&
          otherAcct.isNotEmpty &&
          otherAcct != ownAcct &&
          blob.contains('payout_start');
    });
    if (destDiverted) {
      c.hold(
        id: 'CN-P0-DEST-SWAP',
        lens: 'CN4',
        severity: 'P0',
        title: 'Transfer destination = conta Stripe de outro seller',
        actor: 'seller JWT',
        pre: 'destination do body ignorado; usa Connect do JWT',
        repro: 'POST connect {amount:100, destination:acct_outro, currency:usd}',
        expected: 'Transfer para Connect próprio',
        obtained: destBody.brief,
      );
    } else {
      c.block('dest.body', 'CN4', 'Transfer própria; dest/currency ignorados',
          destBody);
    }
  } else {
    c.block('dest.body', 'CN4', 'destination body não criou Transfer', destBody);
  }
  c.probe(
    id: 'CN-B-DEST',
    lens: 'CN4',
    payload: 'destination=$otherAcct currency=usd amount=100',
    httpBd: destBody.brief,
    result: destDiverted ? 'FAIL' : 'HOLD',
  );

  final balNow = await c.walletBal(c.sellerId);
  final huge = await c.connect({
    'amount': 99999999,
    'idempotency_key': '${prefix}_mintxxxx',
  });
  final balAfterHuge = await c.walletBal(c.sellerId);
  final mintOpen = huge.payoutOk || (balAfterHuge - balNow) < -1;
  c.probe(
    id: 'CN-B-OVERBAL',
    lens: 'CN7',
    payload: 'amount=99999999 vs saldo $balNow',
    httpBd: '${huge.brief} Δ=${balAfterHuge - balNow}',
    result: mintOpen ? 'FAIL' : 'HOLD',
  );
  if (mintOpen) {
    c.hold(
      id: 'CN-P0-MINT-OVER',
      lens: 'CN7',
      severity: 'P0',
      title: 'payout > available balance debitou/mintou',
      actor: 'seller JWT',
      pre: 'debit condicional balance >= amount',
      repro: 'POST connect amount=99999999',
      expected: 'insufficient_balance, Δ=0, sem Transfer',
      obtained: huge.brief,
    );
  } else {
    c.block('mint.huge', 'CN7', 'payout>balance recusado Δ≈0', huge);
  }

  Future<void> amountCase(String id, Object amount) async {
    final h = await c.connect({
      'amount': amount,
      'idempotency_key': '${prefix}_$id'.padRight(12, 'x'),
    });
    final opened = h.payoutOk;
    c.probe(
      id: 'CN-B-AMT-$id',
      lens: 'CN4',
      payload: 'amount=$amount',
      httpBd: h.brief,
      result: opened ? 'FAIL' : 'HOLD',
    );
    await c.expectDenied(
      id: 'cn4.amt.$id',
      lens: 'CN4',
      title: 'amount=$amount criou Transfer',
      hit: h,
      actor: 'seller JWT',
      pre: 'validação estrita integer cents',
      repro: 'POST connect {amount: $amount}',
      severityIfOpen: 'P1',
      openIf: (h2) => h2.payoutOk,
    );
  }

  await amountCase('arr', [100]);
  await amountCase('neg', -100);
  await amountCase('usdobj', {'cents': 100, 'currency': 'usd'});

  // --- CN-C webhook/crash ≥2 ---
  final whNo = await c.edge('stripe-webhook', body: {
    'id': 'evt_rtcn_old',
    'object': 'event',
    'created': 1600000000,
    'type': 'transfer.created',
    'data': {
      'object': {
        'id': 'tr_rtcn_fake',
        'object': 'transfer',
        'amount': 10000,
        'currency': 'eur',
        'destination': otherAcct,
        'created': 1600000000,
        'metadata': {'fleaber_user_id': c.sellerId, 'type': 'wallet_withdrawal'},
      }
    }
  }, jwt: c.buyerJwt);
  final whOpen = whNo.ok &&
      whNo.map?['ok'] == true &&
      whNo.map?['ignored'] == null &&
      whNo.map?['error'] == null;
  c.probe(
    id: 'CN-C-WH-NOSIG',
    lens: 'CN4',
    payload: 'POST stripe-webhook transfer.created sem Stripe-Signature',
    httpBd: whNo.brief,
    result: whOpen ? 'FAIL' : 'HOLD',
  );
  if (whOpen) {
    c.hold(
      id: 'CN-P0-WH-NOSIG',
      lens: 'CN4',
      severity: 'P0',
      title: 'webhook transfer.created sem assinatura aceite',
      actor: 'unsigned',
      pre: 'constructEventAsync exige stripe-signature',
      repro: 'POST stripe-webhook sem Stripe-Signature',
      expected: '400 missing_signature',
      obtained: whNo.brief,
    );
  } else {
    c.block('wh.nosig', 'CN4', 'webhook recusou sem assinatura', whNo);
  }

  if (c.crashSecret.length >= 16) {
    final keyCrash = '${prefix}_crashdeb';
    final hCrash = await c.connect(
      {
        'amount': 100,
        'idempotency_key': keyCrash,
        'crash_inject': 'after_debit_before_stripe',
      },
      extra: {'x-fleaber-crash-inject-secret': c.crashSecret},
    );
    final retry = await c.connect({
      'amount': 100,
      'idempotency_key': keyCrash,
    });
    final tids = <String>{
      if ((hCrash.transferId ?? '').startsWith('tr_')) hCrash.transferId!,
      if ((retry.transferId ?? '').startsWith('tr_')) retry.transferId!,
    };
    c.probe(
      id: 'CN-C-CRASH-RETRY',
      lens: 'CN4',
      payload: 'crash after_debit_before_stripe + retry mesma key',
      httpBd: 'crash=${hCrash.brief} retry=${retry.brief} tids=$tids',
      result: tids.length >= 2 ? 'FAIL' : 'HOLD',
    );
    if (tids.length >= 2) {
      c.hold(
        id: 'CN-P0-CRASH-DEBIT',
        lens: 'CN4',
        severity: 'P0',
        title: 'crash after_debit + retry criou 2 Transfers',
        actor: 'seller JWT + secret staging',
        pre: 'retry retoma débito órfão',
        repro: 'crash after_debit_before_stripe; retry mesma key',
        expected: '≤1 Transfer',
        obtained: {'crash': hCrash.brief, 'retry': retry.brief, 'tids': tids.toList()},
      );
    } else {
      c.block('crash.debit', 'CN4', 'retry após debit não duplicou', {
        'crash': hCrash.brief,
        'retry': retry.brief,
        'tids': tids.toList(),
      });
    }
  } else {
    c.skip('CN-C-CRASH-RETRY', 'CN4', 'sem secret crash_inject', 'skip');
    c.probe(
      id: 'CN-C-CRASH-RETRY',
      lens: 'CN4',
      payload: 'crash_inject after_debit',
      httpBd: 'SKIP sem secret',
      result: 'HOLD',
    );
  }

  // --- CN-A Coptic ≥4 pares (6 pares = 12 keys) ---
  await judgePair(
    id: 'CN-A-COPTIC-O',
    lens: 'CN1',
    sev: 'P2',
    title: 'Coptic ⲟ vs o → 2 Transfers',
    keyA: 'rtcnoCopt01',
    keyB: 'rtcn\u2C9FCopt01',
    pre: 'fold CDCI sem Coptic; catch-all apaga ⲟ ≠ o',
    repro: 'rtcnoCopt01 vs rtcnⲟCopt01 (U+2C9F)',
  );
  await judgePair(
    id: 'CN-A-COPTIC-A',
    lens: 'CN1',
    sev: 'P2',
    title: 'Coptic ⲁ vs a → 2 Transfers',
    keyA: 'rtcnaCopt02',
    keyB: 'rtcn\u2C81Copt02',
    pre: 'fold CDCI sem Coptic ⲁ',
    repro: 'rtcnaCopt02 vs rtcnⲁCopt02 (U+2C81)',
  );
  await judgePair(
    id: 'CN-A-COPTIC-P',
    lens: 'CN1',
    sev: 'P2',
    title: 'Coptic ⲣ vs p → 2 Transfers',
    keyA: 'rtcnpCopt03',
    keyB: 'rtcn\u2CA3Copt03',
    pre: 'fold CDCI sem Coptic ⲣ',
    repro: 'rtcnpCopt03 vs rtcnⲣCopt03 (U+2CA3)',
  );
  await judgePair(
    id: 'CN-A-COPTIC-E',
    lens: 'CN1',
    sev: 'P2',
    title: 'Coptic ⲉ vs e → 2 Transfers',
    keyA: 'rtcneCopt04',
    keyB: 'rtcn\u2C89Copt04',
    pre: 'fold CDCI sem Coptic ⲉ',
    repro: 'rtcneCopt04 vs rtcnⲉCopt04 (U+2C89)',
  );
  await judgePair(
    id: 'CN-A-COPTIC-I',
    lens: 'CN1',
    sev: 'P2',
    title: 'Coptic ⲓ vs i → 2 Transfers',
    keyA: 'rtcniCopt05',
    keyB: 'rtcn\u2C93Copt05',
    pre: 'quota 16 keys; ⲓ fora do fold',
    repro: 'rtcniCopt05 vs rtcnⲓCopt05 (U+2C93)',
  );
  await judgePair(
    id: 'CN-A-COPTIC-K',
    lens: 'CN1',
    sev: 'P2',
    title: 'Coptic ⲕ vs k → 2 Transfers',
    keyA: 'rtcnkCopt06',
    keyB: 'rtcn\u2C95Copt06',
    pre: 'quota 16 keys; ⲕ fora do fold',
    repro: 'rtcnkCopt06 vs rtcnk ⲕ (U+2C95)',
  );

  // Cherokee ≥2 pares
  await judgePair(
    id: 'CN-A-CHEROKEE-O',
    lens: 'CN1',
    sev: 'P2',
    title: 'Cherokee Ꮎ vs o → 2 Transfers',
    keyA: 'rtcnoCher07',
    keyB: 'rtcn\u13BECher07',
    pre: 'fold CDCI sem Cherokee; strip Ꮎ ≠ o',
    repro: 'rtcnoCher07 vs rtcnᎾCher07 (U+13BE)',
  );
  await judgePair(
    id: 'CN-A-CHEROKEE-A',
    lens: 'CN1',
    sev: 'P2',
    title: 'Cherokee Ꭺ vs A → 2 Transfers',
    keyA: 'rtcnACher08',
    keyB: 'rtcn\u13AACher08',
    pre: 'toLowerCase A→a; Ꭺ stripped',
    repro: 'rtcnACher08 vs rtcnᎪCher08 (U+13AA)',
  );

  // Residual CDCI ≤3 — NÃO CONTAR
  await judgePair(
    id: 'CN-HOLD-ARMENIAN',
    lens: 'CN1',
    sev: 'P2',
    title: 'residual CDCI arménio օ vs o',
    keyA: 'rtcnoArmR01',
    keyB: 'rtcn\u0585ArmR01',
    pre: 'CDCI fold [օՕო]→o',
    repro: 'rtcnoArmR01 vs rtcnօArmR01',
    count: false,
  );
  await judgePair(
    id: 'CN-HOLD-GREEK-ALPHA',
    lens: 'CN1',
    sev: 'P2',
    title: 'residual CDCI grego α vs a',
    keyA: 'rtcnaGRkR02',
    keyB: 'rtcn\u03B1GRkR02',
    pre: 'CDCI fold [αΑ]→a',
    repro: 'rtcnaGRkR02 vs rtcnαGRkR02',
    count: false,
  );
  await judgePair(
    id: 'CN-HOLD-CASE-Ii',
    lens: 'CN1',
    sev: 'P2',
    title: 'residual CDCI I vs i toLowerCase',
    keyA: 'rtcnIcaseR3',
    keyB: 'rtcnicaseR3',
    pre: 'CDCI toLowerCase',
    repro: 'rtcnIcaseR3 vs rtcnicaseR3',
    count: false,
  );

  // ZWSP vs ASCII ANTES do length probe (8×ZWSP fold-vazio colide consigo).
  final zwspVsAscii = await c.pairPayout(
    'zwsp-vs-ascii',
    'rtcnzwsp088',
    '\u200B' * 8,
    lens: 'CN1',
  );
  final zwspN = (zwspVsAscii['new_transfer_count'] as int?) ?? 0;
  c.probe(
    id: 'CN-A-ZWSP-VS-ASCII',
    lens: 'CN1',
    payload: 'rtcnzwsp088 vs 8×U+200B',
    httpBd: zwspVsAscii,
    result: zwspN >= 2 ? 'FAIL' : 'HOLD',
  );
  if (zwspN >= 2) {
    c.hold(
      id: 'CN-P2-ZWSP-FOLD-EMPTY',
      lens: 'CN1',
      severity: 'P2',
      title: '8×ZWSP (fold vazio) vs ASCII → 2 Transfers',
      actor: 'seller JWT',
      pre: 'length check no RAW; ZW strip depois → hash userId+vazio',
      repro: 'rtcnzwsp088 vs 8× U+200B',
      expected: '1 Transfer se keys equivalentes, ou 400 na ZWSP',
      obtained: zwspVsAscii,
    );
  } else {
    c.block('zwsp.ascii', 'CN1', 'ZWSP vs ASCII n_tr=$zwspN', zwspVsAscii);
  }

  // Length ≥4: max−1 · max · max+1 · empty/ZWSP (Stripe Idempotency-Key 255)
  Future<void> lenKey(String id, String key) async {
    final h = await c.connect({'amount': 100, 'idempotency_key': key});
    c.probe(
      id: id,
      lens: 'CN1',
      payload: 'key_len=${key.length} sample=${clip(key, 40)}',
      httpBd: h.brief,
      result: h.payoutOk ? 'HOLD' : (h.status == 400 ? 'HOLD' : 'HOLD'),
    );
    c.note(id, 'key length ${key.length} payoutOk=${h.payoutOk}', h.brief,
        lens: 'CN1');
    if (id.contains('EMPTY') && h.payoutOk) {
      c.hold(
        id: 'CN-P1-KEY-EMPTY',
        lens: 'CN1',
        severity: 'P1',
        title: 'idempotency_key vazia criou Transfer',
        actor: 'seller JWT',
        pre: 'rawKey.length < 8 rejeita',
        repro: 'POST connect idempotency_key=""',
        expected: '400',
        obtained: h.brief,
      );
    }
  }

  await lenKey('CN-A-LEN-MAX-1', '${prefix}_L254_'.padRight(254, 'x'));
  await lenKey('CN-A-LEN-MAX', '${prefix}_L255_'.padRight(255, 'x'));
  await lenKey('CN-A-LEN-MAX+1', '${prefix}_L256_'.padRight(256, 'x'));
  await lenKey('CN-A-LEN-EMPTY', '');
  await lenKey('CN-A-LEN-ZWSP', '\u200B' * 8);

  // Parallel ≥2: Future.wait key≡fold · key≠fold
  await c.ensureWalletBalance(c.sellerId!, 10);
  final eqHits = await Future.wait([
    c.connect({'amount': 100, 'idempotency_key': 'rtcnaFoldP9'}),
    c.connect({'amount': 100, 'idempotency_key': 'rtcn\u03B1FoldP9'}),
  ]);
  final eqTids = eqHits
      .map((h) => h.transferId)
      .whereType<String>()
      .where((s) => s.startsWith('tr_'))
      .toSet();
  c.probe(
    id: 'CN-A-PAR-EQ-FOLD',
    lens: 'CN1',
    payload: 'Future.wait rtcnaFoldP9 vs rtcnαFoldP9',
    httpBd: 'tids=$eqTids hits=${eqHits.map((h) => h.brief).toList()}',
    result: eqTids.length >= 2 ? 'FAIL' : 'HOLD',
  );
  if (eqTids.length >= 2) {
    c.hold(
      id: 'CN-P2-PAR-EQ-FOLD',
      lens: 'CN1',
      severity: 'P2',
      title: 'Future.wait α vs a (deveria fold) → 2 Transfers',
      actor: 'seller JWT paralelo',
      pre: 'CDCI fold α→a; race mesma intenção',
      repro: 'Future.wait latin a + greek α',
      expected: '1 Transfer',
      obtained: eqTids.toList(),
      count: false,
    );
  } else {
    c.block('par.eq', 'CN1', 'race α vs a ≤1 Transfer', eqTids.toList());
  }

  await c.ensureWalletBalance(c.sellerId!, 10);
  final neHits = await Future.wait([
    c.connect({'amount': 100, 'idempotency_key': 'rtcnoPar10x'}),
    c.connect({'amount': 100, 'idempotency_key': 'rtcn\u2C9FPar10x'}),
  ]);
  final neTids = neHits
      .map((h) => h.transferId)
      .whereType<String>()
      .where((s) => s.startsWith('tr_'))
      .toSet();
  c.probe(
    id: 'CN-A-PAR-NE-FOLD',
    lens: 'CN1',
    payload: 'Future.wait rtcnoPar10x vs rtcnⲟPar10x',
    httpBd: 'tids=$neTids hits=${neHits.map((h) => h.brief).toList()}',
    result: neTids.length >= 2 ? 'FAIL' : 'HOLD',
  );
  if (neTids.length >= 2) {
    c.hold(
      id: 'CN-A-PAR-COPTIC',
      lens: 'CN1',
      severity: 'P2',
      title: 'Future.wait o vs Coptic ⲟ → 2 Transfers',
      actor: 'seller JWT paralelo',
      pre: 'mesma classe Coptic; prova race',
      repro: 'Future.wait latin o + Coptic ⲟ',
      expected: '1 Transfer se fold confusable',
      obtained: {
        'tids': neTids.toList(),
        'hits': neHits.map((h) => h.brief).toList(),
      },
      count: false,
    );
  } else {
    c.block('par.ne', 'CN1', 'race o vs ⲟ ≤1 Transfer', neTids.toList());
  }

  final wEnd = await c.walletRow(c.sellerId);
  c.note('wallet.end.p1', 'seller wallet end pass1', wEnd, lens: 'CN7');
  await c.dumpAll('pass1.json');
}
