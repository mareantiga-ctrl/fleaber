import '_rtdf.dart';

/// Pass 1 — DF-A charset ≥4 NOVOS (não Coptic/💰/café NFC exacto CZ)
/// · DF-B I/i + wd_uuid · DF-C dest/amount
void main() async {
  final c = Rtdf.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureSeller2();

  final w0 = await c.walletRow(c.sellerId);
  c.note('wallet0', 'seller wallet before', w0, lens: 'DF6');
  await c.ensureWalletBalance(c.sellerId!, 25);
  c.note('wallet.funded', 'seller after fixture', await c.walletRow(c.sellerId),
      lens: 'DF6');

  final ownAcct = '${w0?['stripe_account_id'] ?? ''}';
  final others = await c.otherConnectAccounts(c.sellerId!);
  final otherAcct = others.isNotEmpty
      ? '${others.first['stripe_account_id']}'
      : 'acct_1RTDFOtherSellerXXXX';

  Future<Set<String>> tids() async {
    final led = await c.payoutLedger(c.sellerId!);
    return led
        .map((r) => '${r['stripe_transfer_id']}')
        .where((s) => s.startsWith('tr_'))
        .toSet();
  }

  Future<void> charsetDeny({
    required String id,
    required String key,
    required String payload,
    bool countFinding = true,
    String lens = 'DF1',
  }) async {
    final before = await c.walletBal(c.sellerId);
    final t0 = await tids();
    final h = await c.connect({'amount': 100, 'idempotency_key': key});
    final after = await c.walletBal(c.sellerId);
    final t1 = await tids();
    final n = t1.difference(t0).length;
    final delta = after - before;
    final opened = h.payoutOk || n >= 1 || h.status == 200;
    final is400 = h.status == 400;
    c.probe(
      id: id,
      lens: lens,
      payload: payload,
      httpBd:
          'http=${h.status} n_tr=$n Δ=$delta tids=${t1.difference(t0).toList()} ${h.brief}',
      result: opened ? 'FAIL' : (is400 ? 'HOLD' : 'HOLD'),
    );
    if (opened) {
      c.hold(
        id: id,
        lens: lens,
        severity: 'P2',
        title: 'idempotency_key non-ASCII/fora-allowlist aceite',
        actor: 'seller JWT',
        pre: 'allowlist ASCII [A-Za-z0-9_-] após NFKC → 400',
        repro: 'POST create-connect-account {amount:100, idempotency_key: …}',
        expected: '400; 0 Transfer; Δwallet=0',
        obtained: {
          'http': h.brief,
          'n_tr': n,
          'delta': delta,
        },
        count: countFinding,
      );
    } else {
      c.block(id, lens, 'charset deny n_tr=$n Δ=$delta', h);
    }
  }

  Future<void> nfkcPair({
    required String id,
    required String ascii,
    required String twin,
    required String payload,
    String lens = 'DF1',
  }) async {
    final ev = await c.pairPayout(id, ascii, twin, lens: lens);
    final n = (ev['new_transfer_count'] as int?) ?? 0;
    final b400 = '${ev['hitB']}'.startsWith('400');
    c.probe(
      id: id,
      lens: lens,
      payload: payload,
      httpBd:
          'n_tr=$n B400=$b400 tids=${ev['new_transfer_ids']} Δ=${ev['delta_eur']} A=${ev['hitA']} B=${ev['hitB']}',
      result: n >= 2 ? 'FAIL' : 'HOLD',
    );
    if (n >= 2) {
      c.hold(
        id: id,
        lens: lens,
        severity: 'P2',
        title: 'par NFKC/ASCII → 2 Transfers (bypass charset/idempotency)',
        actor: 'seller JWT',
        pre: 'NFKC antes da allowlist; gémeo deve ser 1 hash ou 400',
        repro: payload,
        expected: '1 Transfer ou 400 no gémeo',
        obtained: ev,
      );
    } else {
      c.block(id, lens, 'nfkc pair n_tr=$n B400=$b400', ev);
    }
  }

  // --- DF-A charset allowlist ≥4 NOVOS ---
  // A1 non-ASCII residual novo (não Coptic/Hangul)
  await charsetDeny(
    id: 'DF-A1-ARABIC',
    key: 'rtdf\u064AAllow01',
    payload: 'key Arabic Yeh ي U+064A (script novo; não Coptic/Hangul)',
  );

  // Controlo exacto CZ — não contar se HOLD
  await charsetDeny(
    id: 'DF-A1-CAFE-CTRL',
    key: 'wd_caf\u00E9Df047x',
    payload: 'controlo café NFC exacto CZ — 1 linha; não contar se HOLD',
    countFinding: false,
  );

  // A2 fullwidth/accent NOVO (não café NFC, não digit １, não ｏ)
  await nfkcPair(
    id: 'DF-A2-FW-HYPHEN',
    ascii: 'rtdfHyph-xx1',
    twin: 'rtdfHyph\uFF0Dxx1',
    payload: 'rtdfHyph-xx1 vs fullwidth hyphen － U+FF0D (NFKC→-)',
  );

  await nfkcPair(
    id: 'DF-A2-MATH-BOLD',
    ascii: 'rtdfaMathxx1',
    twin: 'rtdf\u{1D41A}Mathxx1',
    payload: 'rtdfaMathxx1 vs math bold 𝐚 U+1D41A (NFKC→a)',
  );

  await nfkcPair(
    id: 'DF-A2-NFD-ACUTE',
    ascii: 'rtdfcafeNfd1',
    twin: 'rtdfcaf\u0065\u0301Nfd1',
    payload: 'ASCII rtdfcafeNfd1 vs NFD e+U+0301 (accent novo vs café NFC)',
  );

  await nfkcPair(
    id: 'DF-A2-KELVIN',
    ascii: 'rtdfKelvKxx1',
    twin: 'rtdfKelv\u212Axx1',
    payload: 'rtdfKelvKxx1 vs Kelvin K U+212A (NFKC→K)',
  );

  await nfkcPair(
    id: 'DF-A2-CIRCLED',
    ascii: 'rtdfCirc1xxx',
    twin: 'rtdfCirc\u2460xxx',
    payload: 'rtdfCirc1xxx vs circled ① U+2460 (NFKC→1)',
  );

  // A3 ZW / bidi NOVOS (não ZWSP U+200B / RLO U+202E / TAG)
  await charsetDeny(
    id: 'DF-A3-ZWNJ',
    key: 'rtdfAl\u200Cow05xx',
    payload: 'ZWNJ U+200C no meio (novo vs ZWSP U+200B CZ)',
  );

  await charsetDeny(
    id: 'DF-A3-WJ',
    key: 'rtdfAl\u2060ow06xx',
    payload: 'Word Joiner U+2060 no meio',
  );

  await charsetDeny(
    id: 'DF-A3-LRM',
    key: 'rtdfAl\u200Eow07xx',
    payload: 'bidi LRM U+200E no meio (novo vs RLO CZ)',
  );

  await charsetDeny(
    id: 'DF-A3-BOM',
    key: '\uFEFFrtdfBom08xxx',
    payload: 'BOM U+FEFF prefixo da key',
  );

  // A4 punct/ws NOVOS (não % / space / newline / + exactos CZ)
  await charsetDeny(
    id: 'DF-A4-TAB',
    key: 'rtdfAl\tow09xxx',
    payload: 'TAB U+0009 no meio (novo vs space/newline CZ)',
  );

  await charsetDeny(
    id: 'DF-A4-CR',
    key: 'rtdfAl\row10xxx',
    payload: 'CR U+000D no meio',
  );

  await charsetDeny(
    id: 'DF-A4-DOT',
    key: 'rtdfAllow.11xx',
    payload: 'ponto ASCII . na key (fora allowlist [A-Za-z0-9_-])',
  );

  await charsetDeny(
    id: 'DF-A5-TURKISH-I',
    key: 'rtdfTurk\u0130xx1',
    payload: 'Turkish dotted İ U+0130 (toLowerCase JS → i+dot)',
  );

  await charsetDeny(
    id: 'DF-A5-DOTLESS-I',
    key: 'rtdfkey\u0131xx1',
    payload: 'dotless ı U+0131 vs i ASCII',
  );

  final typeArr = await c.connect({
    'amount': 100,
    'idempotency_key': ['rtdfArrKeyxx1'],
  });
  final arrOpened = typeArr.payoutOk || typeArr.status == 200;
  c.probe(
    id: 'DF-A8-TYPE-ARR',
    lens: 'DF1',
    payload: 'idempotency_key JSON array ["rtdfArrKeyxx1"]',
    httpBd: typeArr.brief,
    result: arrOpened ? 'FAIL' : 'HOLD',
  );
  if (arrOpened) {
    c.hold(
      id: 'DF-A8-TYPE-ARR',
      lens: 'DF1',
      severity: 'P2',
      title: 'idempotency_key array aceite (type confusion)',
      actor: 'seller JWT',
      pre: 'typeof !== string → 400',
      repro: 'POST {amount:100, idempotency_key:["rtdfArrKeyxx1"]}',
      expected: '400; 0 tr_',
      obtained: typeArr.brief,
    );
  } else {
    c.block('A8.array', 'DF1', 'key array recusada', typeArr);
  }

  final typeNull = await c.connect({
    'amount': 100,
    'idempotency_key': null,
  });
  final nullOpened = typeNull.payoutOk || typeNull.status == 200;
  c.probe(
    id: 'DF-A8-TYPE-NULL',
    lens: 'DF1',
    payload: 'idempotency_key JSON null',
    httpBd: typeNull.brief,
    result: nullOpened ? 'FAIL' : 'HOLD',
  );
  if (nullOpened) {
    c.hold(
      id: 'DF-A8-TYPE-NULL',
      lens: 'DF1',
      severity: 'P2',
      title: 'idempotency_key null aceite',
      actor: 'seller JWT',
      pre: 'key em falta/null → 400',
      repro: 'POST {amount:100, idempotency_key:null}',
      expected: '400; 0 tr_',
      obtained: typeNull.brief,
    );
  } else {
    c.block('A8.null', 'DF1', 'key null recusada', typeNull);
  }

  // Header Stripe-style vs body
  final tH0 = await tids();
  final balH0 = await c.walletBal(c.sellerId);
  final hdr = await c.connect(
    {'amount': 100, 'idempotency_key': 'rtdfHdrBodyxx1'},
    extra: {'Idempotency-Key': 'rtdfHdrHeadxx1'},
  );
  final tH1 = await tids();
  final balH1 = await c.walletBal(c.sellerId);
  final hdrNew = tH1.difference(tH0);
  final hdrDup = hdrNew.length >= 2;
  c.probe(
    id: 'DF-A9-HEADER',
    lens: 'DF1',
    payload: 'body rtdfHdrBodyxx1 + header Idempotency-Key: rtdfHdrHeadxx1',
    httpBd:
        'http=${hdr.status} n_tr=${hdrNew.length} tids=$hdrNew Δ=${balH1 - balH0} ${hdr.brief}',
    result: hdrDup ? 'FAIL' : 'HOLD',
  );
  if (hdrDup) {
    c.hold(
      id: 'DF-P2-HEADER',
      lens: 'DF1',
      severity: 'P2',
      title: 'header Idempotency-Key criou Transfer extra vs body',
      actor: 'seller JWT',
      pre: 'Edge usa só body.idempotency_key',
      repro: 'POST body key A + header Idempotency-Key B',
      expected: '1 Transfer (body) ou 400; header ignorado',
      obtained: {
        'http': hdr.brief,
        'new': hdrNew.toList(),
      },
    );
  } else {
    c.block('A9.header', 'DF1', 'header não duplicou n_tr=${hdrNew.length}', hdr);
  }

  // --- DF-B case / canónica ≥3 ---
  final b1 = await c.pairPayout(
    'B1-Ii',
    'RTDFCASEIKEY9',
    'rtdfcaseikey9',
    lens: 'DF2',
  );
  final b1n = (b1['new_transfer_count'] as int?) ?? 0;
  c.probe(
    id: 'DF-B1-CASE-Ii',
    lens: 'DF2',
    payload: 'RTDFCASEIKEY9 vs rtdfcaseikey9 (ASCII I/i)',
    httpBd:
        'n_tr=$b1n tids=${b1['new_transfer_ids']} Δ=${b1['delta_eur']} A=${b1['hitA']} B=${b1['hitB']}',
    result: b1n == 1 ? 'HOLD' : (b1n >= 2 ? 'FAIL' : 'HOLD'),
  );
  if (b1n >= 2) {
    c.hold(
      id: 'DF-P2-CASE-Ii',
      lens: 'DF2',
      severity: 'P2',
      title: 'I vs i ASCII → 2 Transfers (toLowerCase partido)',
      actor: 'seller JWT',
      pre: 'payoutIdempotencyKey toLowerCase após allowlist ASCII',
      repro: 'POST RTDFCASEIKEY9 depois rtdfcaseikey9 amount=100',
      expected: '1 Transfer',
      obtained: b1,
    );
  } else {
    c.block('B1.Ii', 'DF2', 'I vs i n_tr=$b1n', b1);
  }

  final ms = DateTime.now().millisecondsSinceEpoch;
  final wdKey = 'wd_${c.sellerId}_100_$ms';
  final tB2_0 = await tids();
  final balB2_0 = await c.walletBal(c.sellerId);
  final b2 = await c.connect({'amount': 100, 'idempotency_key': wdKey});
  final tB2_1 = await tids();
  final balB2_1 = await c.walletBal(c.sellerId);
  final b2New = tB2_1.difference(tB2_0);
  final b2Ok = b2.payoutOk && b2New.length == 1;
  c.probe(
    id: 'DF-B2-WD-UUID',
    lens: 'DF3',
    payload: 'wd_<sellerUuid>_100_<ms> ASCII canónica',
    httpBd:
        'http=${b2.status} n_tr=${b2New.length} tids=$b2New Δ=${balB2_1 - balB2_0} ${b2.brief}',
    result: b2Ok ? 'HOLD' : 'FAIL',
  );
  if (!b2Ok) {
    c.hold(
      id: 'DF-P1-WD-UUID',
      lens: 'DF3',
      severity: b2.payoutOk ? 'P2' : 'P1',
      title: 'key canónica wd_<uuid> não criou 1 Transfer',
      actor: 'seller JWT',
      pre: 'app gera wd_{uuid}_{cents}_{ms}',
      repro:
          'POST create-connect-account {amount:100, idempotency_key: wd_<uuid>_100_<ms>}',
      expected: '200 + 1 tr_ TEST',
      obtained: b2.brief,
    );
  } else {
    c.block('B2.wd', 'DF3', 'wd_uuid Transfer OK ${b2New.toList()}', b2);
  }

  final tB3_0 = await tids();
  final balB3_0 = await c.walletBal(c.sellerId);
  final b3 = await c.connect({'amount': 100, 'idempotency_key': wdKey});
  final tB3_1 = await tids();
  final balB3_1 = await c.walletBal(c.sellerId);
  final b3New = tB3_1.difference(tB3_0);
  c.probe(
    id: 'DF-B3-WD-RETRY',
    lens: 'DF4',
    payload: 'retry mesma wd_<uuid> B2',
    httpBd:
        'http=${b3.status} n_tr=${b3New.length} tids=$b3New Δ=${balB3_1 - balB3_0} idempotent=${b3.map?['idempotent']} ${b3.brief}',
    result: b3New.isNotEmpty ? 'FAIL' : 'HOLD',
  );
  if (b3New.isNotEmpty) {
    c.hold(
      id: 'DF-P0-WD-RETRY',
      lens: 'DF4',
      severity: 'P0',
      title: 'retry wd_<uuid> criou 2.ª Transfer',
      actor: 'seller JWT',
      pre: 'mesma idempotency_key = 1 Transfer',
      repro: 'POST 2× mesma wd_<uuid>_100_<ms>',
      expected: '0 tr_ novos; Δ=0',
      obtained: {'b2': b2.brief, 'b3': b3.brief, 'new': b3New.toList()},
    );
  } else {
    c.block('B3.retry', 'DF4', 'retry idempotente n_tr=0', b3);
  }

  // --- DF-C hostil ---
  final destBody = await c.connect({
    'amount': 100,
    'idempotency_key': '${prefix}_destrealx',
    'destination': otherAcct,
    'stripe_account_id': otherAcct,
    'account': otherAcct,
    'connect_account': otherAcct,
    'currency': 'usd',
  });
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
        id: 'DF-P0-DEST-SWAP',
        lens: 'DF4',
        severity: 'P0',
        title: 'Transfer destination = conta Stripe de outro seller',
        actor: 'seller JWT',
        pre: 'destination do body ignorado; usa Connect do JWT',
        repro: 'POST connect {amount:100, destination:acct_outro, currency:usd}',
        expected: 'Transfer para Connect próprio',
        obtained: destBody.brief,
      );
    } else {
      c.block('dest.body', 'DF4', 'Transfer própria; dest/currency ignorados',
          destBody);
    }
  } else {
    c.block('dest.body', 'DF4', 'destination body não criou Transfer', destBody);
  }
  c.probe(
    id: 'DF-C1-DEST',
    lens: 'DF4',
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
    id: 'DF-C1b-OVERBAL',
    lens: 'DF6',
    payload: 'amount=99999999 vs saldo $balNow',
    httpBd: '${huge.brief} Δ=${balAfterHuge - balNow}',
    result: mintOpen ? 'FAIL' : 'HOLD',
  );
  if (mintOpen) {
    c.hold(
      id: 'DF-P0-MINT-OVER',
      lens: 'DF6',
      severity: 'P0',
      title: 'payout > available balance debitou/mintou',
      actor: 'seller JWT',
      pre: 'debit condicional balance >= amount',
      repro: 'POST connect amount=99999999',
      expected: 'insufficient_balance, Δ=0, sem Transfer',
      obtained: huge.brief,
    );
  } else {
    c.block('mint.huge', 'DF6', 'payout>balance recusado Δ≈0', huge);
  }

  final wEnd = await c.walletRow(c.sellerId);
  c.note('wallet.end.p1', 'seller wallet end pass1', wEnd, lens: 'DF6');
  await c.dumpAll('pass1.json');
}
