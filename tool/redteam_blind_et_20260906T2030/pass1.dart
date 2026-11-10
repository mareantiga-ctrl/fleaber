/// RED TEAM CEGO ET pass1 — bag∥single + Hub GATE FASE 4.
/// Quota ≥12. Staging only. NÃO corrigir. NÃO produção. NÃO Fase 4.
import 'dart:io';

import '_rtet.dart';

Future<void> main() async {
  final c = Rten.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureBuyer3();
  await c.ensureSeller2();

  final s1 = c.sellerId!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;
  final b3 = c.buyer3Id!;
  final s2 = c.seller2Id!;

  await c.restoreSeller1Published();
  await c.setHub(s2, false);
  c.note('fix.s1', 'S1 published', await c.profile(s1), lens: 'ET-A');
  c.note('fix.b3', 'B3 fresco CPI saco', b3, lens: 'ET-A');
  c.note('sk', 'stripe test key', c.stripeTestKey != null, lens: 'ET-C');

  try {
    await runA(c, s1: s1, b1: b1, b3: b3);
    await runB(c, s1: s1, b1: b1, b2: b2, b3: b3);
    await runC(c, s1: s1, b1: b1, b2: b2);
  } finally {
    await c.endAllCreatedLives();
    await c.restoreSeller1Published();
  }

  await dumpJson('${outDir()}/pass1.json', {
    'auditor': 'REDTEAM_BLIND_ET_BAG_SINGLE_HUB_RETEST_v1',
    'prefix': prefix,
    'staging': projectMust,
    'probes': c.probes,
    'findings': c.findings,
    'blocked': c.blocked,
    'skipped': c.skipped,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
    'classe_nova': c.classeNova.toList()..sort(),
    'actors': {'b1': b1, 's1': s1, 'b2': b2, 's2': s2, 'b3': b3},
    'created': {
      'products': c.createdProductIds,
      'orders': c.createdOrderIds,
      'sessions': c.createdSessionIds,
      'offers': c.createdOfferIds,
      'disputes': c.createdDisputeIds,
    },
  });
  stdout.writeln(
    'WROTE ${outDir()}/pass1.json probes=${c.probes.length} '
    'findings=${c.findings.length} nova=${c.classeNova.length}',
  );
}

Future<({List<String> skus, List<String> oids})> mkBag(
  Rten c, {
  required int n,
  required String buyer,
  required String jwt,
  required String tag,
  int qty = 2,
  double price = 12,
}) async {
  final skus = <String>[];
  final oids = <String>[];
  for (var i = 0; i < n; i++) {
    final pid = await c.createProduct(
      title: '$prefix $tag-$i',
      qty: qty,
      listed: true,
      live: false,
      price: price,
    );
    if (pid == null) continue;
    skus.add(pid);
    final oid = await c.insertOrder(
      productId: pid,
      jwt: jwt,
      buyer: buyer,
      price: price,
    );
    if (oid != null) oids.add(oid);
  }
  return (skus: skus, oids: oids);
}

List<Map<String, Object?>> bagLines(
  List<String> oids,
  List<String> skus,
  List<int> idx, {
  double price = 12,
}) {
  return [
    for (final i in idx)
      if (i < oids.length && i < skus.length)
        {
          'order_id': oids[i],
          'product_id': skus[i],
          'quantity': 1,
          'price': price,
        },
  ];
}

void track(Rten c, HttpHit? h) {
  if (c.usefulCs(h)) c.createdSessionIds.add(h!.sessionId!);
}

bool dualCreate(Rten c, HttpHit? a, HttpHit? b) {
  if (!c.usefulCs(a) || !c.usefulCs(b)) return false;
  final sa = a!.sessionId!;
  final sb = b!.sessionId!;
  if (sa == sb) return false;
  return a.reused != true && b.reused != true;
}

int distinctCreates(Rten c, List<HttpHit?> hits) {
  final sids = <String>{};
  for (final h in hits) {
    if (!c.usefulCs(h)) continue;
    if (h!.reused == true) continue;
    sids.add(h.sessionId!);
  }
  return sids.length;
}

Future<List<int>> hubNs(Rten c, List<String> skus, {String? jwt}) async {
  final out = <int>[];
  for (final pid in skus) {
    out.add((await c.hubSku(pid, jwt: jwt)).list.length);
  }
  return out;
}

Future<List<String>> ledgerSids(Rten c, List<String> oids) async {
  final out = <String>[];
  for (final oid in oids) {
    out.add('${(await c.orderRow(oid))?['stripe_checkout_session_id'] ?? ''}');
  }
  return out;
}

Future<void> holdDual({
  required Rten c,
  required String id,
  required String title,
  required String actor,
  required String pre,
  required String repro,
  required Object obtained,
}) {
  c.hold(
    id: id,
    lens: 'ET-A',
    severity: 'P1',
    title: title,
    actor: actor,
    pre: pre,
    repro: repro,
    expected: '≤1 cs_ útil (200+400 / reused); Hub coerente; sem oversell',
    obtained: obtained,
  );
  return Future.value();
}

/// ET-A Bag∥single + Hub (≥5)
Future<void> runA(
  Rten c, {
  required String s1,
  required String b1,
  required String b3,
}) async {
  // ----- A1 bag ABC ∥ single B + Hub t=0 -----
  final a1 = await mkBag(c, n: 3, buyer: b3, jwt: c.buyer3Jwt!, tag: 'A1');
  HttpHit? a1bag;
  HttpHit? a1single;
  Map<String, Object?>? a1bagOr;
  Map<String, Object?>? a1singleOr;
  if (a1.oids.length == 3) {
    final raced = await Future.wait([
      c.checkoutBag(
        lines: bagLines(a1.oids, a1.skus, [0, 1, 2]),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
      ),
      c.checkout(
        orderId: a1.oids[1],
        productId: a1.skus[1],
        jwt: c.buyer3Jwt,
        buyer: b3,
      ),
    ]);
    a1bag = raced[0];
    a1single = raced[1];
    track(c, a1bag);
    track(c, a1single);
    a1bagOr = await c.sessionOracle(a1bag.sessionId);
    a1singleOr = await c.sessionOracle(a1single.sessionId);
  }
  final hubA1 = await hubNs(c, a1.skus, jwt: c.buyer3Jwt);
  final ledA1 = await ledgerSids(c, a1.oids);
  final dualA1 = dualCreate(c, a1bag, a1single);
  String a1r;
  if (a1.oids.length < 3) {
    a1r = 'SKIP';
    c.skip('A1', 'ET-A', 'fixture bag∥single', a1.oids.length);
  } else if (dualA1) {
    a1r = 'HOLD';
    await holdDual(
      c: c,
      id: 'P1-A1-BAG-SINGLE-HUB',
      title: 'Saco ABC e avulso da linha B ao mesmo tempo: dois links',
      actor: 'B3 bag ABC ∥ CPI B t=0',
      pre: '3 SKUs qty=2 Hub visíveis',
      repro: 'Future.wait checkoutBag ABC ∥ checkout single B',
      obtained: {
        'bag': a1bag?.brief,
        'single': a1single?.brief,
        'bagOr': a1bagOr,
        'singleOr': a1singleOr,
        'hub': hubA1,
        'ledger': ledA1,
      },
    );
  } else {
    a1r = 'FAIL';
    c.block('A1', 'ET-A', 'bag∥single t=0 fail-closed + Hub', {
      'bag': a1bag?.brief,
      'single': a1single?.brief,
      'hub': hubA1,
      'ledger': ledA1,
    });
  }
  c.probe(
    id: 'A1',
    surfaces: 'bag ABC + single B + Hub + orders',
    action: 'Future.wait saco ABC ∥ avulso B t=0; Hub',
    http: {'bag': a1bag?.brief, 'single': a1single?.brief},
    oracles: {
      'dual': dualA1,
      'bag': a1bagOr,
      'single': a1singleOr,
      'hub': hubA1,
      'ledger': ledA1,
    },
    result: a1r,
    lens: 'ET-A',
    classeNova: true,
    countFinding: a1r == 'HOLD',
  );

  // ----- A2 bag∥single t=50 + Hub leftover pós-pago -----
  final paidA2 = await c.payToPago(lens: 'ET-C', initialQty: 2, buyer: b1);
  HttpHit? hubPaid;
  Map<String, dynamic>? prodPaid;
  Map<String, dynamic>? ordPaid;
  if (paidA2 != null) {
    ordPaid = await c.orderRow(paidA2.oid);
    prodPaid = await c.productRow(paidA2.pid);
    hubPaid = await c.hubSku(paidA2.pid, jwt: c.buyerJwt);
  }
  final a2 = await mkBag(c, n: 3, buyer: b3, jwt: c.buyer3Jwt!, tag: 'A2');
  HttpHit? a2bag;
  HttpHit? a2single;
  Map<String, Object?>? a2bagOr;
  Map<String, Object?>? a2singleOr;
  if (a2.oids.length == 3) {
    final raced = await Future.wait([
      c.checkoutBag(
        lines: bagLines(a2.oids, a2.skus, [0, 1, 2]),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
      ),
      Future(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return c.checkout(
          orderId: a2.oids[1],
          productId: a2.skus[1],
          jwt: c.buyer3Jwt,
          buyer: b3,
        );
      }),
    ]);
    a2bag = raced[0];
    a2single = raced[1];
    track(c, a2bag);
    track(c, a2single);
    a2bagOr = await c.sessionOracle(a2bag.sessionId);
    a2singleOr = await c.sessionOracle(a2single.sessionId);
  }
  final hubA2 = await hubNs(c, a2.skus, jwt: c.buyer3Jwt);
  final ledA2 = await ledgerSids(c, a2.oids);
  final dualA2 = dualCreate(c, a2bag, a2single);
  final leftoverHub = hubPaid?.list.length ?? -1;
  final leftoverQty = numOf(prodPaid?['quantity']) ?? -1;
  String a2r;
  if (paidA2 == null || a2.oids.length < 3) {
    a2r = 'SKIP';
    c.skip('A2', 'ET-A', 'fixture leftover+bag∥single t=50', {
      'paid': paidA2?.hit.brief,
      'oids': a2.oids.length,
    });
  } else if (dualA2) {
    a2r = 'HOLD';
    await holdDual(
      c: c,
      id: 'P1-A2-BAG-SINGLE-T50-HUB',
      title: 'Saco first + avulso t=50ms: dois links; leftover Hub pós-pago',
      actor: 'B3 bag first →50ms single B; leftover pago B1',
      pre: 'SKU pago leftover Hub; 3 linhas B3',
      repro: 'setup_paid_order + Future.wait bag + sleep 50ms single',
      obtained: {
        'bag': a2bag?.brief,
        'single': a2single?.brief,
        'bagOr': a2bagOr,
        'singleOr': a2singleOr,
        'leftover_hub': leftoverHub,
        'leftover_qty': leftoverQty,
        'leftover_status': ordPaid?['status'],
        'hub': hubA2,
        'ledger': ledA2,
      },
    );
  } else {
    a2r = 'FAIL';
    c.block('A2', 'ET-A', 'bag∥single t=50 fail-closed + leftover Hub', {
      'bag': a2bag?.brief,
      'single': a2single?.brief,
      'leftover_hub': leftoverHub,
      'leftover_qty': leftoverQty,
      'hub': hubA2,
      'paid': ordPaid?['status'],
    });
  }
  c.probe(
    id: 'A2',
    surfaces: 'bag∥single t=50 + Hub leftover + orders',
    action: 'pago leftover + bag first →50ms single B; Hub',
    http: {
      'paid': paidA2?.hit.brief,
      'bag': a2bag?.brief,
      'single': a2single?.brief,
    },
    oracles: {
      'dual': dualA2,
      'leftover_hub': leftoverHub,
      'leftover_qty': leftoverQty,
      'hub': hubA2,
      'ledger': ledA2,
      'pi': paidA2?.pi,
    },
    result: a2r,
    lens: 'ET-A',
    classeNova: true,
    countFinding: a2r == 'HOLD',
  );

  // ----- A3 single first → bag + Hub -----
  final a3 = await mkBag(c, n: 3, buyer: b3, jwt: c.buyer3Jwt!, tag: 'A3');
  HttpHit? a3single;
  HttpHit? a3bag;
  Map<String, Object?>? a3singleOr;
  Map<String, Object?>? a3bagOr;
  if (a3.oids.length == 3) {
    final raced = await Future.wait([
      c.checkout(
        orderId: a3.oids[1],
        productId: a3.skus[1],
        jwt: c.buyer3Jwt,
        buyer: b3,
      ),
      Future(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return c.checkoutBag(
          lines: bagLines(a3.oids, a3.skus, [0, 1, 2]),
          jwt: c.buyer3Jwt,
          buyer: b3,
          seller: s1,
        );
      }),
    ]);
    a3single = raced[0];
    a3bag = raced[1];
    track(c, a3single);
    track(c, a3bag);
    a3singleOr = await c.sessionOracle(a3single.sessionId);
    a3bagOr = await c.sessionOracle(a3bag.sessionId);
  }
  final hubA3 = await hubNs(c, a3.skus, jwt: c.buyer3Jwt);
  final ledA3 = await ledgerSids(c, a3.oids);
  final dualA3 = dualCreate(c, a3single, a3bag);
  String a3r;
  if (a3.oids.length < 3) {
    a3r = 'SKIP';
    c.skip('A3', 'ET-A', 'fixture single-first', a3.oids.length);
  } else if (dualA3) {
    a3r = 'HOLD';
    await holdDual(
      c: c,
      id: 'P1-A3-SINGLE-THEN-BAG-HUB',
      title: 'Avulso first depois saco t=50ms: dois links',
      actor: 'B3 single B first →50ms bag ABC',
      pre: '3 SKUs qty=2 Hub visíveis',
      repro: 'Future.wait checkout single B + sleep 50ms bag ABC',
      obtained: {
        'single': a3single?.brief,
        'bag': a3bag?.brief,
        'singleOr': a3singleOr,
        'bagOr': a3bagOr,
        'hub': hubA3,
        'ledger': ledA3,
      },
    );
  } else {
    a3r = 'FAIL';
    c.block('A3', 'ET-A', 'single-first→bag fail-closed + Hub', {
      'single': a3single?.brief,
      'bag': a3bag?.brief,
      'hub': hubA3,
      'ledger': ledA3,
    });
  }
  c.probe(
    id: 'A3',
    surfaces: 'single first + bag + Hub + orders',
    action: 'avulso B first →50ms saco ABC; Hub',
    http: {'single': a3single?.brief, 'bag': a3bag?.brief},
    oracles: {
      'dual': dualA3,
      'single': a3singleOr,
      'bag': a3bagOr,
      'hub': hubA3,
      'ledger': ledA3,
    },
    result: a3r,
    lens: 'ET-A',
    classeNova: true,
    countFinding: a3r == 'HOLD',
  );

  // ----- A4 bag∥single∥bag + Hub (3 corrotinas) -----
  final a4 = await mkBag(c, n: 3, buyer: b3, jwt: c.buyer3Jwt!, tag: 'A4');
  HttpHit? a4bag1;
  HttpHit? a4single;
  HttpHit? a4bag2;
  if (a4.oids.length == 3) {
    final raced = await Future.wait([
      c.checkoutBag(
        lines: bagLines(a4.oids, a4.skus, [0, 1, 2]),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
      ),
      c.checkout(
        orderId: a4.oids[1],
        productId: a4.skus[1],
        jwt: c.buyer3Jwt,
        buyer: b3,
      ),
      c.checkoutBag(
        lines: bagLines(a4.oids, a4.skus, [0, 1, 2]),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
      ),
    ]);
    a4bag1 = raced[0];
    a4single = raced[1];
    a4bag2 = raced[2];
    track(c, a4bag1);
    track(c, a4single);
    track(c, a4bag2);
  }
  final hubA4 = await hubNs(c, a4.skus, jwt: c.buyer3Jwt);
  final ledA4 = await ledgerSids(c, a4.oids);
  final createsA4 = distinctCreates(c, [a4bag1, a4single, a4bag2]);
  final dualA4 = createsA4 >= 2;
  String a4r;
  if (a4.oids.length < 3) {
    a4r = 'SKIP';
    c.skip('A4', 'ET-A', 'fixture 3-way', a4.oids.length);
  } else if (dualA4) {
    a4r = 'HOLD';
    await holdDual(
      c: c,
      id: 'P1-A4-BAG-SINGLE-BAG-HUB',
      title: 'Saco ∥ avulso ∥ saco: duas ou mais Sessions úteis',
      actor: 'B3 bag∥single∥bag t=0',
      pre: '3 SKUs qty=2 Hub visíveis',
      repro: 'Future.wait bag ABC ∥ single B ∥ bag ABC',
      obtained: {
        'bag1': a4bag1?.brief,
        'single': a4single?.brief,
        'bag2': a4bag2?.brief,
        'creates': createsA4,
        'hub': hubA4,
        'ledger': ledA4,
      },
    );
  } else {
    a4r = 'FAIL';
    c.block('A4', 'ET-A', '3-way bag∥single∥bag fail-closed + Hub', {
      'bag1': a4bag1?.brief,
      'single': a4single?.brief,
      'bag2': a4bag2?.brief,
      'creates': createsA4,
      'hub': hubA4,
    });
  }
  c.probe(
    id: 'A4',
    surfaces: 'bag∥single∥bag + Hub + orders',
    action: 'Future.wait 3 corrotinas bag ABC ∥ single B ∥ bag ABC; Hub',
    http: {
      'bag1': a4bag1?.brief,
      'single': a4single?.brief,
      'bag2': a4bag2?.brief,
    },
    oracles: {
      'dual': dualA4,
      'creates': createsA4,
      'hub': hubA4,
      'ledger': ledA4,
      'reused': [a4bag1?.reused, a4single?.reused, a4bag2?.reused],
    },
    result: a4r,
    lens: 'ET-A',
    classeNova: true,
    countFinding: a4r == 'HOLD',
  );

  // ----- A5 6∥4 + Hub (regressão ≤1) -----
  final a5 = await mkBag(c, n: 6, buyer: b3, jwt: c.buyer3Jwt!, tag: 'A5');
  HttpHit? bag6;
  HttpHit? bag4;
  Map<String, Object?>? s6or;
  Map<String, Object?>? s4or;
  if (a5.oids.length == 6) {
    final raced = await Future.wait([
      c.checkoutBag(
        lines: bagLines(a5.oids, a5.skus, [0, 1, 2, 3, 4, 5]),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
      ),
      c.checkoutBag(
        lines: bagLines(a5.oids, a5.skus, [1, 2, 3, 4]),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
      ),
    ]);
    bag6 = raced[0];
    bag4 = raced[1];
    track(c, bag6);
    track(c, bag4);
    s6or = await c.sessionOracle(bag6.sessionId);
    s4or = await c.sessionOracle(bag4.sessionId);
  }
  final hubA5 = await hubNs(c, a5.skus, jwt: c.buyer3Jwt);
  final ledA5 = await ledgerSids(c, a5.oids);
  final dualA5 = dualCreate(c, bag6, bag4);
  String a5r;
  if (a5.oids.length < 6) {
    a5r = 'SKIP';
    c.skip('A5', 'ET-A', 'fixture 6∥4', a5.oids.length);
  } else if (dualA5) {
    a5r = 'HOLD';
    await holdDual(
      c: c,
      id: 'P1-A5-64-REGRESSION',
      title: 'Regressão 6∥4: duas Sessions úteis',
      actor: 'B3 bag 6∥4',
      pre: '6 SKUs qty=2 Hub visíveis',
      repro: 'Future.wait bag6 ∥ bag4',
      obtained: {
        'bag6': bag6?.brief,
        'bag4': bag4?.brief,
        's6': s6or,
        's4': s4or,
        'hub': hubA5,
        'ledger': ledA5,
      },
    );
  } else {
    a5r = 'FAIL';
    c.block('A5', 'ET-A', '6∥4 regressão fail-closed + Hub', {
      'bag6': bag6?.brief,
      'bag4': bag4?.brief,
      'hub': hubA5,
    });
  }
  c.probe(
    id: 'A5',
    surfaces: 'bag 6∥4 + Hub + orders',
    action: 'Future.wait ABCDEF ∥ BCDE (regressão ≤1); Hub',
    http: {'bag6': bag6?.brief, 'bag4': bag4?.brief},
    oracles: {
      'dual': dualA5,
      's6': s6or,
      's4': s4or,
      'hub': hubA5,
      'ledger': ledA5,
    },
    result: a5r,
    lens: 'ET-A',
    countFinding: a5r == 'HOLD',
  );
}

/// ET-B Stock / live (≥3)
Future<void> runB(
  Rten c, {
  required String s1,
  required String b1,
  required String b2,
  required String b3,
}) async {
  // ----- B1 2 buyers qty=1 + Hub -----
  final skuB1 = await c.createProduct(
    title: '$prefix B1 two-buyers',
    qty: 1,
    listed: true,
    live: false,
  );
  HttpHit? hub0;
  HttpHit? cpi1;
  HttpHit? cpi2;
  HttpHit? hub1;
  String? o1;
  String? o2;
  if (skuB1 != null) {
    hub0 = await c.hubSku(skuB1, anon: true);
    o1 = await c.insertOrder(
      productId: skuB1,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 12,
    );
    o2 = await c.insertOrder(
      productId: skuB1,
      jwt: c.buyer3Jwt,
      buyer: b3,
      price: 12,
    );
    final raced = await Future.wait([
      if (o1 != null)
        c.checkout(
          orderId: o1,
          productId: skuB1,
          jwt: c.buyer2Jwt,
          buyer: b2,
        )
      else
        Future.value(HttpHit(0, 'no_o1', {})),
      if (o2 != null)
        c.checkout(
          orderId: o2,
          productId: skuB1,
          jwt: c.buyer3Jwt,
          buyer: b3,
        )
      else
        Future.value(HttpHit(0, 'no_o2', {})),
    ]);
    cpi1 = raced[0];
    cpi2 = raced[1];
    track(c, cpi1);
    track(c, cpi2);
    hub1 = await c.hubSku(skuB1, jwt: c.buyer2Jwt);
  }
  final twoCs = [cpi1, cpi2].where(c.usefulCs).length;
  String b1r;
  if (skuB1 == null) {
    b1r = 'SKIP';
    c.skip('B1', 'ET-B', 'sku B1 fail', 'null');
  } else if (twoCs >= 2) {
    b1r = 'HOLD';
    c.hold(
      id: 'P1-B1-TWO-BUYERS',
      lens: 'ET-B',
      severity: 'P1',
      title: '2 buyers Hub-visível: 2 cs_ no qty=1',
      actor: 'B2∥B3 CPI',
      pre: 'Hub lista SKU qty=1',
      repro: 'Future.wait insert+CPI B2 ∥ B3',
      expected: '≤1 cs_ útil; 2.º insert ou CPI deny',
      obtained: {
        'hub0': hub0?.list.length,
        'hub1': hub1?.list.length,
        'b2': cpi1?.brief,
        'b3': cpi2?.brief,
        'o1': o1,
        'o2': o2,
      },
    );
  } else {
    b1r = 'FAIL';
    c.block('B1', 'ET-B', '2 buyers Hub: ≤1 cs_', {
      'hub0': hub0?.list.length,
      'hub1': hub1?.list.length,
      'cs_n': twoCs,
      'o2': o2,
      'b2': cpi1?.brief,
      'b3': cpi2?.brief,
    });
  }
  c.probe(
    id: 'B1',
    surfaces: 'Hub + CPI B2 + CPI B3 + orders',
    action: 'Future.wait 2 buyers qty=1 Hub-visível',
    http: {'hub': hub0?.brief, 'b2': cpi1?.brief, 'b3': cpi2?.brief},
    oracles: {
      'hub0': hub0?.list.length,
      'hub1': hub1?.list.length,
      'cs_n': twoCs,
      'sid1': cpi1?.sessionId,
      'sid2': cpi2?.sessionId,
      'o2_ok': o2 != null,
    },
    result: b1r,
    lens: 'ET-B',
    residual: true,
    countFinding: b1r == 'HOLD',
  );

  // ----- B2 expand 400 + Hub -----
  final exp = await mkBag(c, n: 4, buyer: b3, jwt: c.buyer3Jwt!, tag: 'B2', price: 14);
  HttpHit? sub;
  HttpHit? sup;
  Map<String, Object?>? subOr;
  Map<String, Object?>? supOr;
  if (exp.oids.length == 4) {
    final raced = await Future.wait([
      c.checkoutBag(
        lines: bagLines(exp.oids, exp.skus, [0, 1], price: 14),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
      ),
      Future(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return c.checkoutBag(
          lines: bagLines(exp.oids, exp.skus, [0, 1, 2, 3], price: 14),
          jwt: c.buyer3Jwt,
          buyer: b3,
          seller: s1,
        );
      }),
    ]);
    sub = raced[0];
    sup = raced[1];
    track(c, sub);
    track(c, sup);
    subOr = await c.sessionOracle(sub.sessionId);
    supOr = await c.sessionOracle(sup.sessionId);
  }
  final hubB2 = await hubNs(c, exp.skus, jwt: c.buyer3Jwt);
  final dualB2 = dualCreate(c, sub, sup);
  String b2r;
  if (exp.oids.length < 4) {
    b2r = 'SKIP';
    c.skip('B2', 'ET-B', 'fixture expand', exp.oids.length);
  } else if (dualB2) {
    b2r = 'HOLD';
    c.hold(
      id: 'P1-B2-EXPAND-REGRESSION',
      lens: 'ET-B',
      severity: 'P1',
      title: 'Regressão expand: duas Sessions úteis',
      actor: 'B3 subset AB →50ms superset ABCD',
      pre: '4 SKUs qty=2 Hub visíveis',
      repro: 'Future.wait bag AB + sleep 50ms ABCD',
      expected: '2.º 400 overlapping; ≤1 cs_',
      obtained: {
        'sub': sub?.brief,
        'sup': sup?.brief,
        'subOr': subOr,
        'supOr': supOr,
        'hub': hubB2,
      },
    );
  } else {
    b2r = 'FAIL';
    c.block('B2', 'ET-B', 'expand 400 + Hub', {
      'sub': sub?.brief,
      'sup': sup?.brief,
      'hub': hubB2,
    });
  }
  c.probe(
    id: 'B2',
    surfaces: 'bag expand + Hub + Session',
    action: 'subset AB →50ms superset ABCD; Hub (regressão 400)',
    http: {'sub': sub?.brief, 'sup': sup?.brief},
    oracles: {
      'dual': dualB2,
      'sub': subOr,
      'sup': supOr,
      'hub': hubB2,
    },
    result: b2r,
    lens: 'ET-B',
    residual: true,
    countFinding: b2r == 'HOLD',
  );

  // ----- B3 2× idêntico 1 cs_ + Hub -----
  final idn = await mkBag(c, n: 3, buyer: b3, jwt: c.buyer3Jwt!, tag: 'B3');
  HttpHit? same1;
  HttpHit? same2;
  if (idn.oids.length == 3) {
    final lines = bagLines(idn.oids, idn.skus, [0, 1, 2]);
    final raced = await Future.wait([
      c.checkoutBag(lines: lines, jwt: c.buyer3Jwt, buyer: b3, seller: s1),
      c.checkoutBag(lines: lines, jwt: c.buyer3Jwt, buyer: b3, seller: s1),
    ]);
    same1 = raced[0];
    same2 = raced[1];
    track(c, same1);
    track(c, same2);
  }
  final hubB3 = await hubNs(c, idn.skus, jwt: c.buyer3Jwt);
  final dualB3 = dualCreate(c, same1, same2);
  final sidsB3 = {
    if (c.usefulCs(same1)) same1!.sessionId!,
    if (c.usefulCs(same2)) same2!.sessionId!,
  };
  String b3r;
  if (idn.oids.length < 3) {
    b3r = 'SKIP';
    c.skip('B3', 'ET-B', 'fixture idêntico', idn.oids.length);
  } else if (dualB3) {
    b3r = 'HOLD';
    c.hold(
      id: 'P1-B3-IDENTICAL-DUAL',
      lens: 'ET-B',
      severity: 'P1',
      title: '2× saco idêntico: duas Sessions distintas',
      actor: 'B3 2× checkoutBag ABC paralelo',
      pre: '3 SKUs qty=2 Hub visíveis',
      repro: 'Future.wait mesmo bag_lines ×2',
      expected: '1 cs_ + reused',
      obtained: {
        'h1': same1?.brief,
        'h2': same2?.brief,
        'sids': sidsB3.toList(),
        'hub': hubB3,
      },
    );
  } else {
    b3r = 'FAIL';
    c.block('B3', 'ET-B', '2× idêntico → 1 cs_ reused + Hub', {
      'h1': same1?.brief,
      'h2': same2?.brief,
      'sids': sidsB3.toList(),
      'hub': hubB3,
    });
  }
  c.probe(
    id: 'B3',
    surfaces: 'bag idêntico + Hub + orders',
    action: 'Future.wait 2× mesmo saco ABC + Hub',
    http: {'h1': same1?.brief, 'h2': same2?.brief},
    oracles: {
      'dual': dualB3,
      'sids': sidsB3.toList(),
      'reused': [same1?.reused, same2?.reused],
      'hub': hubB3,
    },
    result: b3r,
    lens: 'ET-B',
    residual: true,
    countFinding: b3r == 'HOLD',
  );
}

/// ET-C Caixa (≥4)
Future<void> runC(
  Rten c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // ----- C1 bag pago único 4 sítios -----
  final wS0 = await c.walletBal(s1);
  final wB0 = await c.walletBal(b1);
  final paidBag = await c.payBag(seller: s1, buyer: b1);
  c.note('fixture.bag', 'setup_paid_bag Stripe TEST 4242', paidBag.brief,
      lens: 'ET-C');
  final bagMap = paidBag.map ?? {};
  final oidA = bagMap['order_a_id']?.toString();
  final oidB = bagMap['order_b_id']?.toString();
  final pidA = bagMap['product_a_id']?.toString();
  final pidB = bagMap['product_b_id']?.toString();
  if (oidA != null) c.createdOrderIds.add(oidA);
  if (oidB != null) c.createdOrderIds.add(oidB);
  if (pidA != null) c.createdProductIds.add(pidA);
  if (pidB != null) c.createdProductIds.add(pidB);
  Map<String, dynamic>? ordA;
  Map<String, dynamic>? ordB;
  Map<String, dynamic>? prodA;
  Map<String, dynamic>? prodB;
  HttpHit? hubA;
  HttpHit? hubB;
  HttpHit? cardA;
  HttpHit? cardB;
  if (oidA != null) ordA = await c.orderRow(oidA);
  if (oidB != null) ordB = await c.orderRow(oidB);
  if (pidA != null) {
    prodA = await c.productRow(pidA);
    hubA = await c.hubSku(pidA, jwt: c.buyerJwt);
    final chatA = await c.ensureChat(pidA);
    if (chatA != null && oidA != null) {
      cardA = await c.postCard(chatA, {
        'kind': 'reservation_payment_submitted',
        'order_id': oidA,
        'notes': 'bag',
      });
    }
  }
  if (pidB != null) {
    prodB = await c.productRow(pidB);
    hubB = await c.hubSku(pidB, jwt: c.buyerJwt);
    final chatB = await c.ensureChat(pidB);
    if (chatB != null && oidB != null) {
      cardB = await c.postCard(chatB, {
        'kind': 'reservation_payment_submitted',
        'order_id': oidB,
        'notes': 'bag',
      });
    }
  }
  final wS1 = await c.walletBal(s1);
  final wB1 = await c.walletBal(b1);
  final bothPago =
      '${ordA?['status']}' == 'pago' && '${ordB?['status']}' == 'pago';
  final paidAc = numOf(ordA?['amount_paid_cents']) ?? 0;
  final paidBc = numOf(ordB?['amount_paid_cents']) ?? 0;
  final piAmt = numOf(bagMap['pi_amount_cents']) ?? 0;
  final lineHasFull = piAmt > 0 && (paidAc == piAmt || paidBc == piAmt);
  final qtyDrop =
      (numOf(prodA?['quantity']) ?? 3) < 3 && (numOf(prodB?['quantity']) ?? 3) < 3;
  String c1r;
  if (!paidBag.ok || oidA == null || oidB == null) {
    c1r = 'SKIP';
    c.skip('C1', 'ET-C', 'setup_paid_bag fail', paidBag.brief);
  } else if (!bothPago) {
    c1r = 'HOLD';
    c.hold(
      id: 'P1-C1-BAG-NOT-PAGO',
      lens: 'ET-C',
      severity: 'P1',
      title: 'Saco Stripe TEST succeeded mas uma linha ≠ pago',
      actor: 'e2e setup_paid_bag 4242',
      pre: '2 linhas mesmo PI',
      repro: 'setup_paid_bag + Hub/order/chat/wallet',
      expected: 'ambas pago; Hub leftover; wallet sem mint',
      obtained: {
        'ordA': ordA?['status'],
        'ordB': ordB?['status'],
        'hubA': hubA?.list.length,
        'hubB': hubB?.list.length,
      },
    );
  } else if (lineHasFull) {
    c1r = 'HOLD';
    c.hold(
      id: 'P0-C1-BAG-FULL-LINE',
      lens: 'ET-C',
      severity: 'P0',
      title: 'Uma linha do saco ficou com o PI inteiro',
      actor: 'setup_paid_bag',
      pre: '2 linhas mesmo PI',
      repro: 'amount_paid_cents vs pi_amount',
      expected: 'nenhuma linha = PI completo; soma = PI',
      obtained: {'paidA': paidAc, 'paidB': paidBc, 'pi': piAmt},
    );
  } else if (!qtyDrop) {
    c1r = 'HOLD';
    c.hold(
      id: 'P1-C1-BAG-STOCK',
      lens: 'ET-C',
      severity: 'P1',
      title: 'Saco pago sem baixar stock nas duas linhas',
      actor: 'settle bag',
      pre: 'qty inicial 3 cada',
      repro: 'setup_paid_bag + products.quantity',
      expected: 'qty 3→2 em A e B',
      obtained: {'qtyA': prodA?['quantity'], 'qtyB': prodB?['quantity']},
    );
  } else {
    c1r = 'FAIL';
    c.block('C1', 'ET-C', 'bag pago único: 4 sítios observados', {
      'both_pago': bothPago,
      'paidA': paidAc,
      'paidB': paidBc,
      'pi': piAmt,
      'hubA': hubA?.list.length,
      'hubB': hubB?.list.length,
      'qtyA': prodA?['quantity'],
      'qtyB': prodB?['quantity'],
      'dSeller': wS1 - wS0,
      'dBuyer': wB1 - wB0,
      'cardA': cardA?.brief,
      'cardB': cardB?.brief,
      'pi_id': bagMap['payment_intent_id'],
    });
  }
  c.probe(
    id: 'C1',
    surfaces: 'Hub + orders + chat + wallet',
    action: 'saco pago Stripe TEST 4242 → 4 oráculos',
    http: paidBag.brief,
    oracles: {
      'both_pago': bothPago,
      'paidA': paidAc,
      'paidB': paidBc,
      'pi_amt': piAmt,
      'hubA_n': hubA?.list.length,
      'hubB_n': hubB?.list.length,
      'qtyA': prodA?['quantity'],
      'qtyB': prodB?['quantity'],
      'dSeller': wS1 - wS0,
      'dBuyer': wB1 - wB0,
      'cardA_ok': cardA?.ok,
      'cardB_ok': cardB?.ok,
      'pi': bagMap['payment_intent_id'],
    },
    result: c1r,
    lens: 'ET-C',
    classeNova: true,
    countFinding: c1r == 'HOLD',
  );

  // ----- C2 leftover qty 2→1 -----
  final paidC2 = await c.payToPago(lens: 'ET-C', initialQty: 2, buyer: b1);
  HttpHit? hubC2;
  HttpHit? leftoverCpi;
  Map<String, dynamic>? prodC2;
  Map<String, dynamic>? ordC2;
  String? oidLeft;
  if (paidC2 != null) {
    ordC2 = await c.orderRow(paidC2.oid);
    prodC2 = await c.productRow(paidC2.pid);
    hubC2 = await c.hubSku(paidC2.pid, jwt: c.buyerJwt);
    oidLeft = await c.insertOrder(
      productId: paidC2.pid,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 12,
    );
    if (oidLeft != null) {
      leftoverCpi = await c.checkout(
        orderId: oidLeft,
        productId: paidC2.pid,
        jwt: c.buyer2Jwt,
        buyer: b2,
      );
      track(c, leftoverCpi);
    }
  }
  final qtyC2 = numOf(prodC2?['quantity']) ?? -1;
  final hubC2n = hubC2?.list.length ?? -1;
  final leftoverBuyable = c.usefulCs(leftoverCpi);
  final leftoverBroken =
      '${ordC2?['status']}' == 'pago' && qtyC2 == 1 && hubC2n != 1;
  String c2r;
  if (paidC2 == null) {
    c2r = 'SKIP';
    c.skip('C2', 'ET-C', 'paid leftover fail', 'null');
  } else if (leftoverBroken) {
    c2r = 'HOLD';
    c.hold(
      id: 'P1-C2-LEFTOVER-HUB',
      lens: 'ET-C',
      severity: 'P1',
      title: 'Pago qty 2→1: Hub não mostra a unidade que sobra',
      actor: 'B1 pago + Hub + B2 leftover CPI',
      pre: 'qty inicial 2 compra 1',
      repro: 'setup_paid_order + hub_products_public + CPI leftover',
      expected: 'status pago; qty=1; Hub n=1; leftover comprável',
      obtained: {
        'status': ordC2?['status'],
        'qty': qtyC2,
        'hub_n': hubC2n,
        'cpi': leftoverCpi?.brief,
      },
    );
  } else {
    c2r = 'FAIL';
    c.block('C2', 'ET-C', 'leftover qty 2→1 Hub+CPI observados', {
      'status': ordC2?['status'],
      'qty': qtyC2,
      'hub_n': hubC2n,
      'leftover_cs': leftoverCpi?.sessionId,
      'buyable': leftoverBuyable,
      'pi': paidC2.pi,
    });
  }
  c.probe(
    id: 'C2',
    surfaces: 'Hub + orders + CPI leftover',
    action: 'leftover após pago parcial qty 2→1',
    http: {'paid': paidC2?.hit.brief, 'cpi': leftoverCpi?.brief},
    oracles: {
      'status': ordC2?['status'],
      'qty': qtyC2,
      'hub_n': hubC2n,
      'leftover_cs': leftoverCpi?.sessionId,
      'buyable': leftoverBuyable,
      'pi': paidC2?.pi,
    },
    result: c2r,
    lens: 'ET-C',
    residual: true,
    countFinding: c2r == 'HOLD',
  );

  // ----- C3 oferta underpay selo -----
  final skuC3 = await c.createProduct(
    title: '$prefix C3 offer',
    qty: 2,
    price: 18,
    listed: true,
    live: false,
  );
  HttpHit? off;
  HttpHit? acc;
  HttpHit? cpiC3;
  HttpHit? hubC3;
  String? oidC3;
  String? offId;
  Map<String, dynamic>? offRow;
  Map<String, dynamic>? ordC3off;
  if (skuC3 != null) {
    off = await c.insertOffer(
      productId: skuC3,
      amount: 8,
      listPrice: 18,
      jwt: c.buyerJwt,
    );
    offId = off.firstId;
    if (offId != null) {
      acc = await c.acceptOffer(offId);
      offRow = await c.offerRow(offId);
      oidC3 = await c.insertOrder(
        productId: skuC3,
        jwt: c.buyerJwt,
        price: 8,
        offerId: offId,
      );
      if (oidC3 != null) {
        cpiC3 = await c.checkout(
          orderId: oidC3,
          productId: skuC3,
          jwt: c.buyerJwt,
          amount: 1,
        );
        track(c, cpiC3);
      }
    }
    hubC3 = await c.hubSku(skuC3, jwt: c.buyerJwt);
    if (oidC3 != null) ordC3off = await c.orderRow(oidC3);
  }
  final sealed = cpiC3?.amountTotal;
  final under = c.usefulCs(cpiC3) && sealed != null && sealed < 800;
  String c3r;
  if (skuC3 == null || offId == null) {
    c3r = 'SKIP';
    c.skip('C3', 'ET-C', 'offer fail', off?.brief ?? 'null');
  } else if (under) {
    c3r = 'HOLD';
    c.hold(
      id: 'P0-C3-UNDERPAY',
      lens: 'ET-C',
      severity: 'P0',
      title: 'CPI selou underpay da oferta aceite',
      actor: 'B1 CPI amount=1 vs oferta 8€',
      pre: 'oferta aceite 8€ list 18€',
      repro: 'create-payment-intent amount=1',
      expected: 'selo ≥800¢ (oferta) ou deny',
      obtained: {
        'sealed': sealed,
        'offer': offRow,
        'cpi': cpiC3?.brief,
        'hub_n': hubC3?.list.length,
      },
    );
  } else {
    c3r = 'FAIL';
    c.block('C3', 'ET-C', 'oferta aceite: selo servidor vs amount=1', {
      'offer': offRow?['amount'],
      'status': offRow?['status'],
      'sealed': sealed,
      'hub_n': hubC3?.list.length,
      'cpi': cpiC3?.brief,
    });
  }
  c.probe(
    id: 'C3',
    surfaces: 'offer + CPI + Hub + orders',
    action: 'oferta 8€ aceite + CPI amount=1 (selo servidor)',
    http: {'off': off?.brief, 'acc': acc?.brief, 'cpi': cpiC3?.brief},
    oracles: {
      'offer_amt': offRow?['amount'],
      'offer_st': offRow?['status'],
      'sealed_cents': sealed,
      'hub_n': hubC3?.list.length,
      'order': ordC3off?['status'],
    },
    result: c3r,
    lens: 'ET-C',
    classeNova: true,
    countFinding: c3r == 'HOLD',
  );

  // ----- C4 release∥disputa 1 efeito -----
  final paidC4 = await c.payToPago(lens: 'ET-C', initialQty: 2);
  HttpHit? plantC4;
  HttpHit? relC4;
  HttpHit? dispC4;
  HttpHit? hubC4;
  Map<String, dynamic>? ordC4;
  Map<String, dynamic>? dispRow;
  final wS0c4 = await c.walletBal(s1);
  if (paidC4 != null) {
    plantC4 = await c.plantConcluidoMao(paidC4.oid);
    final raced = await Future.wait([
      c.tryRelease(paidC4.oid, jwt: c.buyerJwt),
      c.insertDispute(orderId: paidC4.oid),
    ]);
    relC4 = raced[0];
    dispC4 = raced[1];
    ordC4 = await c.orderRow(paidC4.oid);
    if (dispC4.firstId != null) dispRow = await c.disputeRow(dispC4.firstId!);
    hubC4 = await c.hubSku(paidC4.pid, jwt: c.buyerJwt);
  }
  final wS1c4 = await c.walletBal(s1);
  final releasedC4 = c.releasedTrue(relC4);
  final dWalletC4 = wS1c4 - wS0c4;
  final dispOpen = dispC4 != null &&
      dispC4.ok &&
      '${dispRow?['status'] ?? ''}' == 'aberta';
  final twoEffects = releasedC4 && dWalletC4 > 0 && dispOpen;
  String c4r;
  if (paidC4 == null) {
    c4r = 'SKIP';
    c.skip('C4', 'ET-C', 'paid C4 fail', 'null');
  } else if (twoEffects) {
    c4r = 'HOLD';
    c.hold(
      id: 'P1-C4-RELEASE-DISPUTE',
      lens: 'ET-C',
      severity: 'P1',
      title: 'Release creditou E disputa aberta (2 efeitos dinheiro)',
      actor: 'B1 release ∥ disputa',
      pre: 'pago Stripe; plant concluido+mão',
      repro: 'Future.wait release + POST disputa',
      expected: '1 efeito (crédito XOR disputa)',
      obtained: {
        'rel': relC4?.brief,
        'disp': dispC4?.brief,
        'dWallet': dWalletC4,
        'status': ordC4?['status'],
        'hub_n': hubC4?.list.length,
      },
    );
  } else {
    c4r = 'FAIL';
    c.block('C4', 'ET-C', 'release∥disputa: 1 efeito (anti-atrofia)', {
      'rel': relC4?.brief,
      'disp': dispC4?.brief,
      'dWallet': dWalletC4,
      'released': releasedC4,
      'disp_open': dispOpen,
      'status': ordC4?['status'],
      'hub_n': hubC4?.list.length,
      'plant': plantC4?.brief,
    });
  }
  c.probe(
    id: 'C4',
    surfaces: 'wallet + disputa + Hub leftover',
    action: 'Future.wait release∥disputa em concluido+mão (1 linha)',
    http: {
      'plant': plantC4?.brief,
      'rel': relC4?.brief,
      'disp': dispC4?.brief,
    },
    oracles: {
      'released': releasedC4,
      'dWallet': dWalletC4,
      'disp_open': dispOpen,
      'disp_st': dispRow?['status'],
      'status': ordC4?['status'],
      'hub_n': hubC4?.list.length,
      'pi': paidC4?.pi,
    },
    result: c4r,
    lens: 'ET-C',
    classeNova: true,
    countFinding: twoEffects,
  );
}
