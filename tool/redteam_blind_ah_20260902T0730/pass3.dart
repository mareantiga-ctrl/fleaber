/// RED TEAM CEGO AH pass3 — retries 502 + heurística SPA Stripe + bundle accepted já criado.
import 'dart:convert';
import 'dart:io';

import '_rtah.dart';

Future<void> main() async {
  final c = Rtah.fromEnv(loadEnv());
  stdout.writeln('AH pass3 prefix=$prefix');
  await c.loginActors();

  await retryBundlePartial(c);
  await retrySingleThenBag(c);
  await retryBagRace(c);
  await recomposeSpaHeuristic(c);

  await c.dumpAll('pass3_findings.json');
  stdout.writeln(
    'PASS3 findings=${c.findings.length} blocked=${c.blocked.length}',
  );
}

Map<String, Object?> bagLine(String orderId, String productId) => {
      'order_id': orderId,
      'product_id': productId,
    };

Future<HttpHit> ckRetry(Future<HttpHit> Function() fn, {int n = 4}) async {
  HttpHit? last;
  for (var i = 0; i < n; i++) {
    last = await fn();
    if (last.status != 502 && last.status != 429) return last;
    await Future<void>.delayed(Duration(seconds: 2 + i * 2));
  }
  return last!;
}

Future<Map<String, Object?>> probeSpa(String sid) async {
  final url = 'https://checkout.stripe.com/c/pay/$sid';
  final client = HttpClient();
  try {
    final rq = await client.getUrl(Uri.parse(url));
    rq.followRedirects = false;
    final rs = await rq.close();
    final body = await rs.transform(utf8.decoder).join();
    final classic = body.contains('App--classic');
    final tiny = body.length < 8000;
    final expiredPage = tiny &&
        (body.toLowerCase().contains('expired') ||
            body.toLowerCase().contains('no longer'));
    return {
      'http': rs.statusCode,
      'len': body.length,
      'classic_spa': classic,
      'tiny': tiny,
      'expired_page': expiredPage,
      'live_spa': classic && body.length > 100000 && !expiredPage,
    };
  } finally {
    client.close(force: true);
  }
}

Future<void> retryBundlePartial(Rtah c) async {
  const o1 = '95f4a200-22bb-4cd3-a7ff-9fc8b2e1acf1';
  const o2 = 'a74b98c4-49fe-4842-b01c-8b0b79ff0498';
  const bid = '86ab17c5-db98-4268-b9e8-3209b9703a81';
  c.createdOrderIds.addAll([o1, o2]);
  c.createdBundleIds.add(bid);
  final bun = await c.rest(
    'GET',
    'product_bundles?id=eq.$bid&select=id,status,total_eur,product_ids',
    service: true,
  );
  final r1 = await c.orderRow(o1);
  final r2 = await c.orderRow(o2);
  c.note('P3.BUN.pre', 'bundle+orders', {
    'bundle': bun.brief,
    'st': bun.map?['status'],
    'total': bun.map?['total_eur'],
    'o1b': r1?['bundle_id'],
    'o2b': r2?['bundle_id'],
    'o1st': r1?['status'],
  }, lens: 'AH3');
  if ((bun.map?['status'] ?? '').toString().toLowerCase() != 'accepted') {
    return c.block('AH3-BUNDLE-PARTIAL', 'AH3', 'bundle já não accepted', bun.brief);
  }
  final p1 = r1?['product_id']?.toString() ?? '';
  final p2 = r2?['product_id']?.toString() ?? '';
  final partial = await ckRetry(
    () => c.checkoutBag(lines: [bagLine(o1, p1)]),
  );
  await Future<void>.delayed(const Duration(seconds: 2));
  final full = await ckRetry(
    () => c.checkoutBag(lines: [bagLine(o1, p1), bagLine(o2, p2)]),
  );
  c.note('P3.BUN.ck', 'partial/full', {
    'partial': partial.brief,
    'pamt': partial.amountTotal,
    'full': full.brief,
    'famt': full.amountTotal,
  }, lens: 'AH3');
  if (partial.ok) {
    c.hold(
      id: 'AH3-BUNDLE-PARTIAL',
      lens: 'AH3',
      severity: 'P1',
      title: 'Conjunto accepted: bag com 1 de 2 SKUs abre Session',
      actor: 'buyer JWT',
      pre: 'bundle accepted total 23.40; 2 orders',
      repro: 'bag_checkout só o1',
      expected: 'blocked must include all items',
      obtained: {
        'amt': partial.amountTotal,
        'sid': partial.sessionId,
        'full_amt': full.amountTotal,
        'bundle_total': bun.map?['total_eur'],
      },
    );
  } else {
    c.block('AH3-BUNDLE-PARTIAL', 'AH3', 'parcial bloqueado ou 502', partial.brief);
  }
}

Future<void> retrySingleThenBag(Rtah c) async {
  final pd = await c.createProduct(price: 14, qty: 2, title: '$prefix-p3-d');
  final pe = await c.createProduct(price: 16, qty: 2, title: '$prefix-p3-e');
  if (pd == null || pe == null) return;
  final od = await c.insertOrder(productId: pd, jwt: c.buyerJwt, price: 14);
  final oe = await c.insertOrder(productId: pe, jwt: c.buyerJwt, price: 16);
  if (od == null || oe == null) {
    return c.skip('AH2-SINGLE-THEN-BAG', 'AH2', 'no orders', '$od $oe');
  }
  final single = await ckRetry(() => c.checkout(orderId: od, amount: 50));
  await Future<void>.delayed(const Duration(seconds: 1));
  final bag = await ckRetry(
    () => c.checkoutBag(lines: [bagLine(od, pd), bagLine(oe, pe)]),
  );
  final rd = await c.orderRow(od);
  final re = await c.orderRow(oe);
  Map<String, Object?>? spa;
  if (single.sessionId != null) spa = await probeSpa(single.sessionId!);
  c.note('P3.S2B', 'single then bag', {
    's1': single.sessionId,
    's2': bag.sessionId,
    'od': rd?['stripe_checkout_session_id'],
    'oe': re?['stripe_checkout_session_id'],
    'spa': spa,
  }, lens: 'AH2');
  if (single.sessionId != null &&
      bag.sessionId != null &&
      single.sessionId != bag.sessionId &&
      spa?['live_spa'] == true) {
    c.hold(
      id: 'AH2-SINGLE-THEN-BAG-ORPHAN',
      lens: 'AH2',
      severity: 'P1',
      title: 'Single depois saco: Session single continua SPA Stripe viva',
      actor: 'buyer JWT',
      pre: 'checkout single D; bag D+E',
      repro: 'POST single; POST bag; GET checkout.stripe.com SPA',
      expected: 'S1 expired',
      obtained: {
        's1': single.sessionId,
        's2': bag.sessionId,
        'od': rd?['stripe_checkout_session_id'],
        'spa': spa,
      },
    );
  } else {
    c.block('AH2-SINGLE-THEN-BAG-ORPHAN', 'AH2', 'não provou SPA live', {
      's1': single.sessionId,
      's2': bag.sessionId,
      'spa': spa,
    });
  }
}

Future<void> retryBagRace(Rtah c) async {
  final pa = await c.createProduct(price: 8, qty: 1, title: '$prefix-p3-ra');
  final pb = await c.createProduct(price: 9, qty: 1, title: '$prefix-p3-rb');
  if (pa == null || pb == null) return;
  final oa = await c.insertOrder(productId: pa, jwt: c.buyerJwt, price: 8);
  final ob = await c.insertOrder(productId: pb, jwt: c.buyerJwt, price: 9);
  if (oa == null || ob == null) return;
  final lines = [bagLine(oa, pa), bagLine(ob, pb)];
  await Future<void>.delayed(const Duration(seconds: 2));
  final rs = await parallel([
    c.checkoutBag(lines: lines),
    c.checkoutBag(lines: lines),
  ]);
  final sids = rs.map((e) => e.sessionId).whereType<String>().toSet();
  final spas = <String, Object?>{};
  for (final s in sids) {
    spas[s] = await probeSpa(s);
  }
  final live = spas.values.where((v) {
    return v is Map && v['live_spa'] == true;
  }).length;
  c.note('P3.RACE', 'bag parallel', {
    'a': rs[0].brief,
    'b': rs[1].brief,
    'sids': sids.toList(),
    'spas': spas,
    'live': live,
  }, lens: 'AH6');
  if (sids.length > 1 && live > 1) {
    c.hold(
      id: 'AH6-BAG-RACE-TWO-OPEN',
      lens: 'AH6',
      severity: 'P1',
      title: 'Bag paralelo: 2 cs_ com SPA Stripe viva',
      actor: 'buyer JWT',
      pre: '2 orders',
      repro: 'Future.wait 2× bag_checkout; GET SPA',
      expected: '1 cs_',
      obtained: {'sids': sids.toList(), 'live': live, 'spas': spas},
    );
  } else if (sids.length > 1) {
    c.hold(
      id: 'AH6-BAG-RACE-TWO-CS',
      lens: 'AH6',
      severity: 'P2',
      title: 'Bag paralelo emite 2 checkoutSessionId distintos',
      actor: 'buyer JWT',
      pre: '2 orders',
      repro: 'Future.wait 2× bag_checkout',
      expected: '1 cs_',
      obtained: {'sids': sids.toList(), 'live': live, 'spas': spas},
    );
  } else {
    c.block('AH6-BAG-RACE', 'AH6', '1 session ou fail', {
      'a': rs[0].brief,
      'b': rs[1].brief,
    });
  }
}

Future<void> recomposeSpaHeuristic(Rtah c) async {
  const s1 = 'cs_test_a1mMqkh3eWr0dNRkNq7aDeqtQ7jT7pRIAdlG1olC8yu1rjmv2a85wJ56T7';
  const s2 = 'cs_test_a1vDCqYfpR11GL4ZUUX2GFcoCYPvnzPmmUK3Va264aIQA04ME3FJOjXcWQ';
  final u1 = await probeSpa(s1);
  final u2 = await probeSpa(s2);
  c.note('P3.SPA.RECOMPOSE', 'heurística App--classic', {
    'u1': u1,
    'u2': u2,
  }, lens: 'AH2');
  if (u1['live_spa'] == true && u2['live_spa'] == true) {
    c.hold(
      id: 'AH2-BAG-RECOMPOSE-ORPHAN',
      lens: 'AH2',
      severity: 'P1',
      title:
          'Após saco A+C, S1 (ainda na order B) e S2 servem ambos SPA Checkout clássica (>100k) — duas Sessions pagáveis',
      actor: 'buyer JWT',
      pre: 'pass2: oa/oc=S2 ob=S1 amt 2690 vs 3530',
      repro: 'GET checkout.stripe.com/c/pay/{S1,S2}',
      expected: 'S1 expired_page tiny',
      obtained: {'s1': s1, 's2': s2, 'u1': u1, 'u2': u2},
    );
  } else {
    c.note('P3.SPA.not_both_live', 'spa', {'u1': u1, 'u2': u2}, lens: 'AH2');
  }
}
