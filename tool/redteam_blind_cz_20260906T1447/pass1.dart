import '_rtcz.dart';

/// Pass 1 — CZ-A charset ≥4 (novos: Hangul/tag/`+`/fullwidth digit/ligadura)
/// · CZ-B I/i + wd_uuid · CZ-C dest/amount
/// Coptic residual 1 linha count=false. Não chase Coptic/Cherokee/💰.
void main() async {
  final c = Rtcz.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureSeller2();

  final w0 = await c.walletRow(c.sellerId);
  c.note('wallet0', 'seller wallet before', w0, lens: 'CZ6');
  await c.ensureWalletBalance(c.sellerId!, 25);
  c.note('wallet.funded', 'seller after fixture', await c.walletRow(c.sellerId),
      lens: 'CZ6');

  final ownAcct = '${w0?['stripe_account_id'] ?? ''}';
  final others = await c.otherConnectAccounts(c.sellerId!);
  final otherAcct = others.isNotEmpty
      ? '${others.first['stripe_account_id']}'
      : 'acct_1RTCZOtherSellerXXXX';

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
    String lens = 'CZ1',
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
        pre: 'allowlist /^[a-zA-Z0-9_-]+\$/ após NFKC → 400',
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
    String lens = 'CZ1',
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

  // --- CZ-A charset allowlist ≥4 (novos, não chase Coptic) ---
  await charsetDeny(
    id: 'CZ-A1-HANGUL',
    key: 'rtcz\uD55CAllow01',
    payload: 'key Hangul 한 U+D55C (script novo; não Coptic)',
  );

  await charsetDeny(
    id: 'CZ-A1-COPTIC',
    key: 'rtcz\u2C9FAllow01',
    payload: 'residual Coptic ⲟ U+2C9F — 1 linha; não contar se HOLD',
    countFinding: false,
  );

  await charsetDeny(
    id: 'CZ-A2-LATIN-ACCENT',
    key: 'wd_caf\u00E9Cz047x',
    payload: 'key Latin acento wd_caféCz047x',
  );

  await nfkcPair(
    id: 'CZ-A2-FW-DIGIT',
    ascii: 'rtczFw1Allowx',
    twin: 'rtczFw\uFF11Allowx',
    payload: 'rtczFw1Allowx vs fullwidth １ U+FF11 (NFKC→1)',
  );

  await charsetDeny(
    id: 'CZ-A3-ZWSP',
    key: 'rtczAl\u200Bow05xx',
    payload: 'ZWSP U+200B no meio rtczAl<ZWSP>ow05xx',
  );

  await charsetDeny(
    id: 'CZ-A3-BIDI',
    key: 'rtczAl\u202Eow06xx',
    payload: 'bidi RLO U+202E no meio',
  );

  await charsetDeny(
    id: 'CZ-A3-TAG',
    key: 'rtczAl\u{E0061}ow07xx',
    payload: 'TAG LATIN SMALL A U+E0061 no meio (novo vs CT)',
  );

  await charsetDeny(
    id: 'CZ-A4-PLUS',
    key: 'rtczAllow08+xx',
    payload: 'key ASCII com + (novo vs CT %/space/newline)',
  );

  await charsetDeny(
    id: 'CZ-A4-PERCENT',
    key: 'rtczAllow09%xx',
    payload: 'key com %',
  );

  await nfkcPair(
    id: 'CZ-A5-SOFT-HYPHEN',
    ascii: 'rtczShyphen1',
    twin: 'rtczS\u00ADhyphen1',
    payload: 'soft hyphen U+00AD no meio vs ASCII (NFKC pode apagar)',
  );

  await nfkcPair(
    id: 'CZ-A6-LIGATURE',
    ascii: 'rtczfikeyxx1',
    twin: 'rtcz\uFB01keyxx1',
    payload: 'ligadura ﬁ U+FB01 NFKC→fi vs ASCII fi',
  );

  final typeHit = await c.connect({
    'amount': 100,
    'idempotency_key': 12345678,
  });
  final typeOpened = typeHit.payoutOk || typeHit.status == 200;
  c.probe(
    id: 'CZ-A8-TYPE-NUM',
    lens: 'CZ1',
    payload: 'idempotency_key JSON number 12345678 (type confusion)',
    httpBd: typeHit.brief,
    result: typeOpened ? 'FAIL' : 'HOLD',
  );
  if (typeOpened) {
    c.hold(
      id: 'CZ-A8-TYPE-NUM',
      lens: 'CZ1',
      severity: 'P2',
      title: 'idempotency_key numérica aceite (type confusion)',
      actor: 'seller JWT',
      pre: 'typeof !== string → key em falta → 400',
      repro: 'POST {amount:100, idempotency_key:12345678}',
      expected: '400 em falta/inválida; 0 tr_',
      obtained: typeHit.brief,
    );
  } else {
    c.block('A8.type', 'CZ1', 'key number recusada', typeHit);
  }

  // --- CZ-B case / canónica ≥3 ---
  final b1 = await c.pairPayout(
    'B1-Ii',
    'RTCZCASEIKEY9',
    'rtczcaseikey9',
    lens: 'CZ2',
  );
  final b1n = (b1['new_transfer_count'] as int?) ?? 0;
  c.probe(
    id: 'CZ-B1-CASE-Ii',
    lens: 'CZ2',
    payload: 'RTCZCASEIKEY9 vs rtczcaseikey9 (ASCII I/i)',
    httpBd:
        'n_tr=$b1n tids=${b1['new_transfer_ids']} Δ=${b1['delta_eur']} A=${b1['hitA']} B=${b1['hitB']}',
    result: b1n == 1 ? 'HOLD' : (b1n >= 2 ? 'FAIL' : 'HOLD'),
  );
  if (b1n >= 2) {
    c.hold(
      id: 'CZ-P2-CASE-Ii',
      lens: 'CZ2',
      severity: 'P2',
      title: 'I vs i ASCII → 2 Transfers (toLowerCase partido)',
      actor: 'seller JWT',
      pre: 'payoutIdempotencyKey toLowerCase após allowlist ASCII',
      repro: 'POST RTCZCASEIKEY9 depois rtczcaseikey9 amount=100',
      expected: '1 Transfer',
      obtained: b1,
    );
  } else {
    c.block('B1.Ii', 'CZ2', 'I vs i n_tr=$b1n', b1);
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
    id: 'CZ-B2-WD-UUID',
    lens: 'CZ3',
    payload: 'wd_<sellerUuid>_100_<ms> ASCII canónica',
    httpBd:
        'http=${b2.status} n_tr=${b2New.length} tids=$b2New Δ=${balB2_1 - balB2_0} ${b2.brief}',
    result: b2Ok ? 'HOLD' : 'FAIL',
  );
  if (!b2Ok) {
    c.hold(
      id: 'CZ-P1-WD-UUID',
      lens: 'CZ3',
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
    c.block('B2.wd', 'CZ3', 'wd_uuid Transfer OK ${b2New.toList()}', b2);
  }

  final tB3_0 = await tids();
  final balB3_0 = await c.walletBal(c.sellerId);
  final b3 = await c.connect({'amount': 100, 'idempotency_key': wdKey});
  final tB3_1 = await tids();
  final balB3_1 = await c.walletBal(c.sellerId);
  final b3New = tB3_1.difference(tB3_0);
  c.probe(
    id: 'CZ-B3-WD-RETRY',
    lens: 'CZ4',
    payload: 'retry mesma wd_<uuid> B2',
    httpBd:
        'http=${b3.status} n_tr=${b3New.length} tids=$b3New Δ=${balB3_1 - balB3_0} idempotent=${b3.map?['idempotent']} ${b3.brief}',
    result: b3New.isNotEmpty ? 'FAIL' : 'HOLD',
  );
  if (b3New.isNotEmpty) {
    c.hold(
      id: 'CZ-P0-WD-RETRY',
      lens: 'CZ4',
      severity: 'P0',
      title: 'retry wd_<uuid> criou 2.ª Transfer',
      actor: 'seller JWT',
      pre: 'mesma idempotency_key = 1 Transfer',
      repro: 'POST 2× mesma wd_<uuid>_100_<ms>',
      expected: '0 tr_ novos; Δ=0',
      obtained: {'b2': b2.brief, 'b3': b3.brief, 'new': b3New.toList()},
    );
  } else {
    c.block('B3.retry', 'CZ4', 'retry idempotente n_tr=0', b3);
  }

  // --- CZ-C hostil ---
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
        id: 'CZ-P0-DEST-SWAP',
        lens: 'CZ4',
        severity: 'P0',
        title: 'Transfer destination = conta Stripe de outro seller',
        actor: 'seller JWT',
        pre: 'destination do body ignorado; usa Connect do JWT',
        repro: 'POST connect {amount:100, destination:acct_outro, currency:usd}',
        expected: 'Transfer para Connect próprio',
        obtained: destBody.brief,
      );
    } else {
      c.block('dest.body', 'CZ4', 'Transfer própria; dest/currency ignorados',
          destBody);
    }
  } else {
    c.block('dest.body', 'CZ4', 'destination body não criou Transfer', destBody);
  }
  c.probe(
    id: 'CZ-C1-DEST',
    lens: 'CZ4',
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
    id: 'CZ-C1b-OVERBAL',
    lens: 'CZ6',
    payload: 'amount=99999999 vs saldo $balNow',
    httpBd: '${huge.brief} Δ=${balAfterHuge - balNow}',
    result: mintOpen ? 'FAIL' : 'HOLD',
  );
  if (mintOpen) {
    c.hold(
      id: 'CZ-P0-MINT-OVER',
      lens: 'CZ6',
      severity: 'P0',
      title: 'payout > available balance debitou/mintou',
      actor: 'seller JWT',
      pre: 'debit condicional balance >= amount',
      repro: 'POST connect amount=99999999',
      expected: 'insufficient_balance, Δ=0, sem Transfer',
      obtained: huge.brief,
    );
  } else {
    c.block('mint.huge', 'CZ6', 'payout>balance recusado Δ≈0', huge);
  }

  final wEnd = await c.walletRow(c.sellerId);
  c.note('wallet.end.p1', 'seller wallet end pass1', wEnd, lens: 'CZ6');
  await c.dumpAll('pass1.json');
}
