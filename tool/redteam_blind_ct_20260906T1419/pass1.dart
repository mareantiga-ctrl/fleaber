import '_rtct.dart';

/// Pass 1 — CT-A charset ≥4 · CT-B I/i + wd_uuid · CT-C dest/amount
/// Coptic HOLD exacto = 1 linha, não contar. Não chase sinónimos Coptic/Cherokee.
void main() async {
  final c = Rtct.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureSeller2();

  final w0 = await c.walletRow(c.sellerId);
  c.note('wallet0', 'seller wallet before', w0, lens: 'CT6');
  await c.ensureWalletBalance(c.sellerId!, 25);
  c.note('wallet.funded', 'seller after fixture', await c.walletRow(c.sellerId),
      lens: 'CT6');

  final ownAcct = '${w0?['stripe_account_id'] ?? ''}';
  final others = await c.otherConnectAccounts(c.sellerId!);
  final otherAcct = others.isNotEmpty
      ? '${others.first['stripe_account_id']}'
      : 'acct_1RTCTOtherSellerXXXX';

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
    String lens = 'CT1',
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
        title: 'idempotency_key non-ASCII aceite (allowlist charset)',
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
      c.block(id, lens, 'charset 400 n_tr=$n Δ=$delta', h);
    }
  }

  // --- CT-A charset allowlist ≥4 ---
  // A1 Coptic exacto — 1 linha só; se HOLD não contar.
  await charsetDeny(
    id: 'CT-A1-COPTIC',
    key: 'rtct\u2C9FAllow01',
    payload: 'key Coptic ⲟ (U+2C9F) rtcn-class; esperar 400',
    countFinding: false,
  );

  await charsetDeny(
    id: 'CT-A1b-EMOJI',
    key: 'rtctAllow02\u{1F4B0}',
    payload: 'key ASCII+emoji U+1F4B0',
  );

  await charsetDeny(
    id: 'CT-A1c-CYRILLIC',
    key: 'rtct\u0435Allow03',
    payload: 'key Cyrillic е U+0435 (não NFKC→e)',
  );

  await charsetDeny(
    id: 'CT-A2-LATIN-ACCENT',
    key: 'wd_caf\u00E9Allow04',
    payload: 'key Latin acento wd_caféAllow04',
  );

  await charsetDeny(
    id: 'CT-A3-ZWSP',
    key: 'rtctAll\u200Bow05x',
    payload: 'ZWSP U+200B no meio rtctAll<ZWSP>ow05x',
  );

  await charsetDeny(
    id: 'CT-A3b-BIDI',
    key: 'rtctAl\u202Eow06xx',
    payload: 'bidi RLO U+202E no meio',
  );

  await charsetDeny(
    id: 'CT-A4-PERCENT',
    key: 'rtctAllow07%xx',
    payload: 'key com %',
  );

  await charsetDeny(
    id: 'CT-A4-SPACE',
    key: 'rtctAllow 08x',
    payload: 'key com espaço',
  );

  await charsetDeny(
    id: 'CT-A4-NEWLINE',
    key: 'rtctAllow09\nxx',
    payload: 'key com newline',
  );

  // --- CT-B case / canónica ≥3 ---
  // B1 I vs i → 1 Transfer
  final b1 = await c.pairPayout(
    'B1-Ii',
    'RTCTCASEIKEY9',
    'rtctcaseikey9',
    lens: 'CT2',
  );
  final b1n = (b1['new_transfer_count'] as int?) ?? 0;
  c.probe(
    id: 'CT-B1-CASE-Ii',
    lens: 'CT2',
    payload: 'RTCTCASEIKEY9 vs rtctcaseikey9 (ASCII I/i)',
    httpBd:
        'n_tr=$b1n tids=${b1['new_transfer_ids']} Δ=${b1['delta_eur']} A=${b1['hitA']} B=${b1['hitB']}',
    result: b1n == 1 ? 'HOLD' : (b1n >= 2 ? 'FAIL' : 'HOLD'),
  );
  if (b1n >= 2) {
    c.hold(
      id: 'CT-P2-CASE-Ii',
      lens: 'CT2',
      severity: 'P2',
      title: 'I vs i ASCII → 2 Transfers (toLowerCase partido)',
      actor: 'seller JWT',
      pre: 'payoutIdempotencyKey toLowerCase após allowlist ASCII',
      repro: 'POST RTCTCASEIKEY9 depois rtctcaseikey9 amount=100',
      expected: '1 Transfer',
      obtained: b1,
    );
  } else {
    c.block('B1.Ii', 'CT2', 'I vs i n_tr=$b1n', b1);
  }

  // B2 key canónica wd_<uuid>_<cents>_<ms>
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
    id: 'CT-B2-WD-UUID',
    lens: 'CT3',
    payload: 'wd_<sellerUuid>_100_<ms> ASCII canónica',
    httpBd:
        'http=${b2.status} n_tr=${b2New.length} tids=$b2New Δ=${balB2_1 - balB2_0} ${b2.brief}',
    result: b2Ok ? 'HOLD' : 'FAIL',
  );
  if (!b2Ok) {
    c.hold(
      id: 'CT-P1-WD-UUID',
      lens: 'CT3',
      severity: b2.payoutOk ? 'P2' : 'P1',
      title: 'key canónica wd_<uuid> não criou 1 Transfer',
      actor: 'seller JWT',
      pre: 'app gera wd_{uuid}_{cents}_{ms}',
      repro: 'POST create-connect-account {amount:100, idempotency_key: wd_<uuid>_100_<ms>}',
      expected: '200 + 1 tr_ TEST',
      obtained: b2.brief,
    );
  } else {
    c.block('B2.wd', 'CT3', 'wd_uuid Transfer OK ${b2New.toList()}', b2);
  }

  // B3 retry mesma wd_<uuid>
  final tB3_0 = await tids();
  final balB3_0 = await c.walletBal(c.sellerId);
  final b3 = await c.connect({'amount': 100, 'idempotency_key': wdKey});
  final tB3_1 = await tids();
  final balB3_1 = await c.walletBal(c.sellerId);
  final b3New = tB3_1.difference(tB3_0);
  final b3Hold = b3New.isEmpty && (balB3_1 - balB3_0).abs() < 0.009;
  c.probe(
    id: 'CT-B3-WD-RETRY',
    lens: 'CT4',
    payload: 'retry mesma wd_<uuid> B2',
    httpBd:
        'http=${b3.status} n_tr=${b3New.length} tids=$b3New Δ=${balB3_1 - balB3_0} idempotent=${b3.map?['idempotent']} ${b3.brief}',
    result: b3Hold || (b3.payoutOk && b3New.isEmpty) || b3.map?['idempotent'] == true
        ? 'HOLD'
        : (b3New.isNotEmpty ? 'FAIL' : 'HOLD'),
  );
  if (b3New.isNotEmpty) {
    c.hold(
      id: 'CT-P0-WD-RETRY',
      lens: 'CT4',
      severity: 'P0',
      title: 'retry wd_<uuid> criou 2.ª Transfer',
      actor: 'seller JWT',
      pre: 'mesma idempotency_key = 1 Transfer',
      repro: 'POST 2× mesma wd_<uuid>_100_<ms>',
      expected: '0 tr_ novos; Δ=0',
      obtained: {'b2': b2.brief, 'b3': b3.brief, 'new': b3New.toList()},
    );
  } else {
    c.block('B3.retry', 'CT4', 'retry idempotente n_tr=0', b3);
  }

  // NFKC fullwidth — atacar allowlist (não Coptic). Se 1 tr com ASCII gémeo = HOLD desenho.
  final fw = await c.pairPayout(
    'A7-fullwidth',
    'rtctoFwAllow1',
    'rtct\uFF4FFwAllow1',
    lens: 'CT1',
  );
  final fwn = (fw['new_transfer_count'] as int?) ?? 0;
  final fwB400 = '${fw['hitB']}'.startsWith('400');
  c.probe(
    id: 'CT-A7-FULLWIDTH-NFKC',
    lens: 'CT1',
    payload: 'rtctoFwAllow1 vs rtctｏFwAllow1 (U+FF4F NFKC→o)',
    httpBd:
        'n_tr=$fwn B400=$fwB400 tids=${fw['new_transfer_ids']} Δ=${fw['delta_eur']} A=${fw['hitA']} B=${fw['hitB']}',
    result: fwn >= 2 ? 'FAIL' : 'HOLD',
  );
  if (fwn >= 2) {
    c.hold(
      id: 'CT-P2-FULLWIDTH',
      lens: 'CT1',
      severity: 'P2',
      title: 'fullwidth ｏ vs o → 2 Transfers (NFKC/allowlist)',
      actor: 'seller JWT',
      pre: 'NFKC antes da allowlist; ｏ→o deveria ser 1 hash',
      repro: 'rtctoFwAllow1 vs rtctｏFwAllow1 U+FF4F',
      expected: '1 Transfer ou 400 no fullwidth',
      obtained: fw,
    );
  } else {
    c.block('A7.fw', 'CT1', 'fullwidth n_tr=$fwn B400=$fwB400', fw);
  }

  // --- CT-C hostil residual ---
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
        id: 'CT-P0-DEST-SWAP',
        lens: 'CT4',
        severity: 'P0',
        title: 'Transfer destination = conta Stripe de outro seller',
        actor: 'seller JWT',
        pre: 'destination do body ignorado; usa Connect do JWT',
        repro: 'POST connect {amount:100, destination:acct_outro, currency:usd}',
        expected: 'Transfer para Connect próprio',
        obtained: destBody.brief,
      );
    } else {
      c.block('dest.body', 'CT4', 'Transfer própria; dest/currency ignorados',
          destBody);
    }
  } else {
    c.block('dest.body', 'CT4', 'destination body não criou Transfer', destBody);
  }
  c.probe(
    id: 'CT-C1-DEST',
    lens: 'CT4',
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
    id: 'CT-C1b-OVERBAL',
    lens: 'CT6',
    payload: 'amount=99999999 vs saldo $balNow',
    httpBd: '${huge.brief} Δ=${balAfterHuge - balNow}',
    result: mintOpen ? 'FAIL' : 'HOLD',
  );
  if (mintOpen) {
    c.hold(
      id: 'CT-P0-MINT-OVER',
      lens: 'CT6',
      severity: 'P0',
      title: 'payout > available balance debitou/mintou',
      actor: 'seller JWT',
      pre: 'debit condicional balance >= amount',
      repro: 'POST connect amount=99999999',
      expected: 'insufficient_balance, Δ=0, sem Transfer',
      obtained: huge.brief,
    );
  } else {
    c.block('mint.huge', 'CT6', 'payout>balance recusado Δ≈0', huge);
  }

  final wEnd = await c.walletRow(c.sellerId);
  c.note('wallet.end.p1', 'seller wallet end pass1', wEnd, lens: 'CT6');
  await c.dumpAll('pass1.json');
}
