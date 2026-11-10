/// RED TEAM CEGO EJ pass2 — fechar C1 settle amount + A1 UPSERT sem order_id fake + oráculo C3.
/// Staging only. NÃO CORRIGIR.
import 'dart:io';
import '_rtej.dart';

Future<void> main() async {
  final c = Rtej.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final s1 = c.sellerId!;
  final b2 = c.buyer2Id!;

  try {
    await confirmC3(c, s1);
    await pass2A1(c, s1);
    await pass2C1(c, s1, b2);
  } finally {
    await c.endLives();
  }

  await c.dumpAll('pass2.json');
  stdout.writeln(
    'EJ pass2 probes=${c.probes.length} findings=${c.findings.where((f) => f['count'] == true).length}',
  );
}

Future<void> confirmC3(Rtej c, String s1) async {
  const tr = 'tr_1UCkZEH7FWYUN3jh0RAyXfgG';
  final bal = await c.walletBal(s1);
  final row = await c.walletRow(s1);
  final led = await c.payoutLedger(s1, limit: 8);
  final match = led.where((r) => '${r['stripe_transfer_id']}' == tr).toList();
  final cents = match.isEmpty ? null : numOf(match.first['amount_cents']);
  stdout.writeln('CONFIRM C3 bal=$bal acct=${row?['stripe_account_id']} led=$match');
  c.note('confirm.C3', 'wallet vs Transfer $tr', {
    'balance': bal,
    'ledger': match,
    'amount_cents': cents,
  }, lens: 'EJ7');
  final leak = match.isNotEmpty && cents != null && cents > 0 && bal >= 18;
  // leak only if debit clearly skipped: transfer exists AND balance did not drop.
  // Cannot prove skip without pre-balance; document ledger+balance pair.
  c.probe(
    id: 'C3-confirm',
    lens: 'EJ7',
    edgeRpc: 'GET wallets + wallet_payout_ledger tr_ C3',
    payload: tr,
    http: 'bal=$bal n_led=${match.length} cents=$cents',
    stripeBd: match,
    result: leak ? 'HOLD' : 'HOLD',
    classeNova: false,
    countFinding: false,
  );
}

Future<void> pass2A1(Rtej c, String s1) async {
  final a0 = await c.walletBal(s1);
  final existing = await c.walletTxns(s1, limit: 1);
  final existId = existing.isEmpty ? null : '${existing.first['id']}';
  final upsert = await c.rest(
    'POST',
    'wallet_transactions',
    jwt: c.buyerJwt,
    prefer: 'resolution=merge-duplicates,return=representation',
    body: {
      if (existId != null) 'id': existId,
      'wallet_id': s1,
      'amount': 4444.44,
      'type': 'venda',
      'description': '$prefix upsert-no-oid',
    },
  );
  final insNew = await c.rest(
    'POST',
    'wallet_transactions',
    jwt: c.sellerJwt,
    prefer: 'return=representation',
    body: {
      'wallet_id': s1,
      'amount': 12.34,
      'type': 'venda',
      'description': '$prefix insert-no-oid seller',
    },
  );
  final a1 = await c.walletBal(s1);
  final open = (a1 - a0).abs() > 0.001 ||
      (upsert.ok && upsert.list.isNotEmpty) ||
      (insNew.ok && insNew.firstId != null);
  c.probe(
    id: 'A1b',
    lens: 'EJ1',
    edgeRpc: 'UPSERT/INSERT wallet_transactions JWT sem order_id fake',
    payload: 'merge id=$existId amount=4444 · INSERT seller 12.34',
    http: 'upsert ${upsert.brief} | ins ${insNew.brief}',
    stripeBd: 'Δ=${a1 - a0}',
    result: open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: open,
  );
  if (open) {
    c.hold(
      id: 'A1b-upsert-noid',
      lens: 'EJ1',
      severity: 'P0',
      title: 'JWT UPSERT/INSERT txn sem order_id mintou',
      actor: 'buyer/seller JWT',
      pre: 'RLS deny',
      repro: 'POST wallet_transactions sem order_id Prefer merge',
      expected: '403 / 0 rows',
      obtained: {'upsert': upsert.brief, 'ins': insNew.brief, 'Δ': a1 - a0},
    );
  } else {
    c.block('A1b', 'EJ1', 'UPSERT/INSERT sem oid preso', upsert);
  }
}

Future<void> pass2C1(Rtej c, String s1, String b2) async {
  const price = 12.0;
  final pid = await c.createProduct(
    seller: s1,
    title: '$prefix c1-bag',
    qty: 3,
    price: price,
  );
  if (pid == null) {
    c.skipped.add({'id': 'C1b', 'title': 'SKU fail'});
    return;
  }
  final oid = await c.insertOrder(
    productId: pid,
    buyer: b2,
    seller: s1,
    price: price,
  );
  if (oid == null) {
    c.skipped.add({'id': 'C1b', 'title': 'order fail'});
    return;
  }
  final bag = await c.bagCheckout(
    lines: [
      {
        'order_id': oid,
        'product_id': pid,
        'seller_id': s1,
        'quantity': 1,
        'line_total_cents': 1,
      },
    ],
    jwt: c.buyer2Jwt,
    buyer: b2,
    amount: 1,
    extra: {
      'amount_total': 1,
      'total': 1,
      'server_amount_cents': 1,
    },
  );
  final quoted = numOf(bag.map?['server_amount_cents'])?.round();
  final stripeAmt = numOf(bag.map?['amount_total'])?.round();
  final sid = bag.sessionId;
  HttpHit put = HttpHit(0, 'no sid', {'error': 'no sid'});
  HttpHit get = HttpHit(0, 'no sid', {'error': 'no sid'});
  if (sid != null && sid.startsWith('cs_')) {
    put = await c.settlePost(
      sid,
      method: 'PUT',
      extraQs: 'amount=1&amount_total=1',
      body: {
        'checkout_return': 'success',
        'session_id': sid,
        'amount': 1,
        'amount_total': 1,
      },
      jwt: c.buyer2Jwt,
    );
    get = await c.settleGet(sid, extraQs: 'amount=1', jwt: c.buyer2Jwt);
  }
  final row = await c.orderRow(oid);
  final clientWon = bag.ok &&
      ((quoted != null && quoted <= 50) ||
          (stripeAmt != null && stripeAmt <= 50));
  final paid = c.orderPaid(row);
  final open = clientWon || paid;
  c.probe(
    id: 'C1b',
    lens: 'EJ2',
    edgeRpc: 'bag_checkout amount=1 + PUT settle + GET amount=1',
    payload: 'oid $oid SKU 12€ body amount=1 line_total_cents=1',
    http: 'bag ${bag.brief} | put ${put.brief} | get ${get.brief}',
    stripeBd:
        'quoted=$quoted stripeAmt=$stripeAmt sid=$sid status=${row?['status']} paid=$paid',
    result: open ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: open,
  );
  if (open) {
    c.hold(
      id: 'C1b-amount',
      lens: 'EJ2',
      severity: 'P0',
      title: 'Bag/settle confiou amount=1 vs SKU 12€',
      actor: 'buyer2 JWT',
      pre: 'servidor ganha quote',
      repro: 'POST bag_checkout amount=1; PUT settle amount=1',
      expected: '400 ou server_amount≈1325; unpaid',
      obtained: {
        'quoted': quoted,
        'stripeAmt': stripeAmt,
        'status': row?['status'],
        'bag': bag.brief,
      },
    );
  } else {
    c.block('C1b-amount', 'EJ2', 'servidor ganha amount; PUT não liquida', bag);
  }
}
