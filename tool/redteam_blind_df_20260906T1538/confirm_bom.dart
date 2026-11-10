import '_rtdf.dart';

/// Confirm DF-A3-BOM: prefix/suffix/middle U+FEFF vs ASCII twin.
void main() async {
  final c = Rtdf.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureWalletBalance(c.sellerId!, 20);

  final prefixPair = await c.pairPayout(
    'BOM-PREFIX',
    'rtdfBomCnfxx1',
    '\uFEFFrtdfBomCnfxx1',
    lens: 'DF1',
  );
  c.probe(
    id: 'DF-A3-BOM-PREFIX-PAIR',
    lens: 'DF1',
    payload: 'rtdfBomCnfxx1 vs U+FEFF+rtdfBomCnfxx1',
    httpBd:
        'n_tr=${prefixPair['new_transfer_count']} tids=${prefixPair['new_transfer_ids']} Δ=${prefixPair['delta_eur']} A=${prefixPair['hitA']} B=${prefixPair['hitB']}',
    result: ((prefixPair['new_transfer_count'] as int?) ?? 0) >= 2
        ? 'FAIL'
        : 'HOLD',
  );

  final suffixPair = await c.pairPayout(
    'BOM-SUFFIX',
    'rtdfBomSufxx1',
    'rtdfBomSufxx1\uFEFF',
    lens: 'DF1',
  );
  c.probe(
    id: 'DF-A3-BOM-SUFFIX-PAIR',
    lens: 'DF1',
    payload: 'rtdfBomSufxx1 vs rtdfBomSufxx1+U+FEFF',
    httpBd:
        'n_tr=${suffixPair['new_transfer_count']} tids=${suffixPair['new_transfer_ids']} Δ=${suffixPair['delta_eur']} A=${suffixPair['hitA']} B=${suffixPair['hitB']}',
    result: ((suffixPair['new_transfer_count'] as int?) ?? 0) >= 2
        ? 'FAIL'
        : 'HOLD',
  );

  final before = await c.walletBal(c.sellerId);
  final mid = await c.connect({
    'amount': 100,
    'idempotency_key': 'rtdfBo\uFEFFmMidxx1',
  });
  final after = await c.walletBal(c.sellerId);
  c.probe(
    id: 'DF-A3-BOM-MIDDLE',
    lens: 'DF1',
    payload: 'BOM U+FEFF no meio rtdfBo<FEFF>mMidxx1',
    httpBd: '${mid.brief} Δ=${after - before}',
    result: (mid.payoutOk || mid.status == 200) ? 'FAIL' : 'HOLD',
  );

  await c.dumpAll('confirm_bom.json');
}
