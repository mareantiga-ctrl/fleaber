/// RED TEAM CEGO EN pass1 — saco + Hub + composição reteste POS_OPEN_GATE.
/// Quota ≥14. Staging only. NÃO corrigir. NÃO produção. NÃO Fase 4.
/// Obrigatório: 6∥4 / expand / bag∥single / shrink + Hub leftover. Fail-closed.
import 'dart:io';

import '_rten.dart';

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
  c.note('fix.s1', 'S1 published', await c.profile(s1), lens: 'EN1');
  c.note('fix.b3', 'B3 fresco CPI saco', b3, lens: 'EN6');
  c.note('sk', 'stripe test key', c.stripeTestKey != null, lens: 'EN8');

  try {
    await runA(c, s1: s1, b1: b1, b3: b3);
    await runB(c, s1: s1, b1: b1, b2: b2, b3: b3);
    await runC(c, s1: s1, b1: b1, b2: b2);
  } finally {
    await c.endAllCreatedLives();
    await c.restoreSeller1Published();
    for (final rid in c.createdRaffleIds) {
      await c.rest(
        'PATCH',
        'live_raffles?id=eq.$rid',
        service: true,
        body: {'status': 'closed'},
        prefer: 'return=minimal',
      );
    }
  }

  await dumpJson('${outDir()}/pass1.json', {
    'auditor': 'REDTEAM_BLIND_EN_BAG_COMPOSICAO_RETEST_POS_OPEN_v1',
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
      'lives': c.createdLiveIds,
      'items': c.createdLiveItemIds,
      'res': c.createdResIds,
      'offers': c.createdOfferIds,
      'raffles': c.createdRaffleIds,
      'disputes': c.createdDisputeIds,
      'sessions': c.createdSessionIds,
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
  if (a.reused == true && b.reused == true) return false;
  return a.reused != true && b.reused != true;
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

/// EN-A Bag gate (≥5)
Future<void> runA(
  Rten c, {
  required String s1,
  required String b1,
  required String b3,
}) async {
  // ----- A1 6∥4 + Hub leftover pós-pago -----
  final paidA1 = await c.payToPago(lens: 'EN8', initialQty: 2, buyer: b1);
  HttpHit? hubPaid;
  Map<String, dynamic>? prodPaid;
  Map<String, dynamic>? ordPaid;
  if (paidA1 != null) {
    ordPaid = await c.orderRow(paidA1.oid);
    prodPaid = await c.productRow(paidA1.pid);
    hubPaid = await c.hubSku(paidA1.pid, jwt: c.buyerJwt);
  }
  final bag = await mkBag(c, n: 6, buyer: b3, jwt: c.buyer3Jwt!, tag: 'A1');
  HttpHit? bag6;
  HttpHit? bag4;
  Map<String, Object?>? s6or;
  Map<String, Object?>? s4or;
  if (bag.oids.length == 6) {
    final raced = await Future.wait([
      c.checkoutBag(
        lines: bagLines(bag.oids, bag.skus, [0, 1, 2, 3, 4, 5]),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
      ),
      c.checkoutBag(
        lines: bagLines(bag.oids, bag.skus, [1, 2, 3, 4]),
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
  final hubA1 = await hubNs(c, bag.skus, jwt: c.buyer3Jwt);
  final ledA1 = await ledgerSids(c, bag.oids);
  final dualA1 = dualCreate(c, bag6, bag4);
  final leftoverHub = hubPaid?.list.length ?? -1;
  final leftoverQty = numOf(prodPaid?['quantity']) ?? -1;
  String a1r;
  if (paidA1 == null || bag.oids.length < 6) {
    a1r = 'SKIP';
    c.skip('A1', 'EN6', 'fixture 6∥4/pago', {
      'paid': paidA1?.hit.brief,
      'oids': bag.oids.length,
    });
  } else if (dualA1) {
    a1r = 'HOLD';
    c.hold(
      id: 'P1-A1-64-BAG-HUB',
      lens: 'EN6',
      severity: 'P1',
      title: '6∥4: duas Sessions úteis após leftover Hub pago',
      actor: 'B3 bag 6∥4; leftover pago B1',
      pre: 'SKU pago leftover Hub; 6 linhas B3',
      repro: 'setup_paid_order + Future.wait bag6 ∥ bag4',
      expected: '≤1 cs_ útil (200+400 ou reused); leftover Hub n=1 qty=1',
      obtained: {
        'bag6': bag6?.brief,
        'bag4': bag4?.brief,
        's6': s6or,
        's4': s4or,
        'leftover_hub': leftoverHub,
        'leftover_qty': leftoverQty,
        'hub': hubA1,
        'ledger': ledA1,
      },
    );
  } else {
    a1r = 'FAIL';
    c.block('A1', 'EN6', '6∥4 fail-closed + leftover Hub coerente', {
      'bag6': bag6?.brief,
      'bag4': bag4?.brief,
      's6': s6or,
      's4': s4or,
      'leftover_hub': leftoverHub,
      'leftover_qty': leftoverQty,
      'hub': hubA1,
      'paid': ordPaid?['status'],
    });
  }
  c.probe(
    id: 'A1',
    surfaces: 'bag 6∥4 + Hub leftover + orders',
    action: 'pago leftover + Future.wait ABCDEF ∥ BCDE',
    http: {'paid': paidA1?.hit.brief, 'bag6': bag6?.brief, 'bag4': bag4?.brief},
    oracles: {
      'dual': dualA1,
      's6': s6or,
      's4': s4or,
      'leftover_hub': leftoverHub,
      'leftover_qty': leftoverQty,
      'hub': hubA1,
      'ledger': ledA1,
      'pi': paidA1?.pi,
    },
    result: a1r,
    lens: 'EN6',
    classeNova: true,
    countFinding: a1r == 'HOLD',
  );

  // ----- A2 expand subset→50ms→superset + Hub -----
  final exp = await mkBag(
    c,
    n: 4,
    buyer: b3,
    jwt: c.buyer3Jwt!,
    tag: 'A2',
    price: 14,
  );
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
  final hubA2 = await hubNs(c, exp.skus, jwt: c.buyer3Jwt);
  final dualA2 = dualCreate(c, sub, sup);
  String a2r;
  if (exp.oids.length < 4) {
    a2r = 'SKIP';
    c.skip('A2', 'EN6', 'fixture expand', exp.oids.length);
  } else if (dualA2) {
    a2r = 'HOLD';
    c.hold(
      id: 'P1-A2-EXPAND-OPEN',
      lens: 'EN6',
      severity: 'P1',
      title: 'Expand subset→superset: duas Sessions úteis',
      actor: 'B3 bag AB t=0 ∥ ABCD t=50ms',
      pre: '4 SKUs qty=2 Hub visíveis',
      repro: 'Future.wait bag AB + sleep 50ms bag ABCD',
      expected: '2.º 400 overlapping OU reuse; nunca 2 creates',
      obtained: {
        'sub': sub?.brief,
        'super': sup?.brief,
        'subOr': subOr,
        'superOr': supOr,
        'hub': hubA2,
      },
    );
  } else {
    a2r = 'FAIL';
    c.block('A2', 'EN6', 'expand fail-closed (sem 2.ª Session)', {
      'sub': sub?.brief,
      'super': sup?.brief,
      'subOr': subOr,
      'superOr': supOr,
      'hub': hubA2,
    });
  }
  c.probe(
    id: 'A2',
    surfaces: 'bag expand + Hub + Stripe Session',
    action: 'subset AB →50ms superset ABCD + Hub',
    http: {'sub': sub?.brief, 'super': sup?.brief},
    oracles: {
      'dual': dualA2,
      'sub': subOr,
      'super': supOr,
      'hub': hubA2,
    },
    result: a2r,
    lens: 'EN6',
    classeNova: true,
    countFinding: a2r == 'HOLD',
  );

  // ----- A3 bag∥single + Hub -----
  final bs = await mkBag(c, n: 3, buyer: b3, jwt: c.buyer3Jwt!, tag: 'A3');
  HttpHit? bagHit;
  HttpHit? singleHit;
  Map<String, Object?>? bagOr;
  Map<String, Object?>? singleOr;
  if (bs.oids.length == 3) {
    final raced = await Future.wait([
      c.checkoutBag(
        lines: bagLines(bs.oids, bs.skus, [0, 1, 2]),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
      ),
      c.checkout(
        orderId: bs.oids[1],
        productId: bs.skus[1],
        jwt: c.buyer3Jwt,
        buyer: b3,
      ),
    ]);
    bagHit = raced[0];
    singleHit = raced[1];
    track(c, bagHit);
    track(c, singleHit);
    bagOr = await c.sessionOracle(bagHit.sessionId);
    singleOr = await c.sessionOracle(singleHit.sessionId);
  }
  final hubA3 = await hubNs(c, bs.skus, jwt: c.buyer3Jwt);
  final ledA3 = await ledgerSids(c, bs.oids);
  final dualA3 = dualCreate(c, bagHit, singleHit);
  String a3r;
  if (bs.oids.length < 3) {
    a3r = 'SKIP';
    c.skip('A3', 'EN6', 'fixture bag∥single', bs.oids.length);
  } else if (dualA3) {
    a3r = 'HOLD';
    c.hold(
      id: 'P1-A3-BAG-SINGLE-HUB',
      lens: 'EN6',
      severity: 'P1',
      title: 'Saco de 3 e pagamento avulso da linha do meio: dois links',
      actor: 'B3 bag ABC ∥ CPI linha B',
      pre: '3 SKUs qty=2 Hub visíveis',
      repro: 'Future.wait checkoutBag ABC ∥ checkout single B',
      expected: '≤1 cs_ útil; Hub coerente',
      obtained: {
        'bag': bagHit?.brief,
        'single': singleHit?.brief,
        'bagOr': bagOr,
        'singleOr': singleOr,
        'hub': hubA3,
        'ledger': ledA3,
      },
    );
  } else {
    a3r = 'FAIL';
    c.block('A3', 'EN6', 'bag∥single fail-closed + Hub', {
      'bag': bagHit?.brief,
      'single': singleHit?.brief,
      'hub': hubA3,
      'ledger': ledA3,
    });
  }
  c.probe(
    id: 'A3',
    surfaces: 'bag + single CPI + Hub + orders',
    action: 'Future.wait saco ABC ∥ avulso B; Hub',
    http: {'bag': bagHit?.brief, 'single': singleHit?.brief},
    oracles: {
      'dual': dualA3,
      'bag': bagOr,
      'single': singleOr,
      'hub': hubA3,
      'ledger': ledA3,
    },
    result: a3r,
    lens: 'EN6',
    classeNova: true,
    countFinding: a3r == 'HOLD',
  );

  // ----- A4 shrink full→50ms→subset + Hub -----
  final sh = await mkBag(c, n: 4, buyer: b3, jwt: c.buyer3Jwt!, tag: 'A4');
  HttpHit? full;
  HttpHit? small;
  Map<String, Object?>? fullOr;
  Map<String, Object?>? smallOr;
  if (sh.oids.length == 4) {
    final raced = await Future.wait([
      c.checkoutBag(
        lines: bagLines(sh.oids, sh.skus, [0, 1, 2, 3]),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
      ),
      Future(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return c.checkoutBag(
          lines: bagLines(sh.oids, sh.skus, [0, 1]),
          jwt: c.buyer3Jwt,
          buyer: b3,
          seller: s1,
        );
      }),
    ]);
    full = raced[0];
    small = raced[1];
    track(c, full);
    track(c, small);
    fullOr = await c.sessionOracle(full.sessionId);
    smallOr = await c.sessionOracle(small.sessionId);
  }
  final hubA4 = await hubNs(c, sh.skus, jwt: c.buyer3Jwt);
  final dualA4 = dualCreate(c, full, small);
  String a4r;
  if (sh.oids.length < 4) {
    a4r = 'SKIP';
    c.skip('A4', 'EN6', 'fixture shrink', sh.oids.length);
  } else if (dualA4) {
    a4r = 'HOLD';
    c.hold(
      id: 'P1-A4-SHRINK-OPEN',
      lens: 'EN6',
      severity: 'P1',
      title: 'Shrink 4→2: duas Sessions úteis',
      actor: 'B3 bag ABCD t=0 ∥ AB t=50ms',
      pre: '4 SKUs qty=2 Hub visíveis',
      repro: 'Future.wait bag full + sleep 50ms subset',
      expected: 'reuse do maior OU 400; nunca 2 creates',
      obtained: {
        'full': full?.brief,
        'small': small?.brief,
        'fullOr': fullOr,
        'smallOr': smallOr,
        'hub': hubA4,
      },
    );
  } else {
    a4r = 'FAIL';
    c.block('A4', 'EN6', 'shrink fail-closed + Hub', {
      'full': full?.brief,
      'small': small?.brief,
      'fullOr': fullOr,
      'smallOr': smallOr,
      'hub': hubA4,
    });
  }
  c.probe(
    id: 'A4',
    surfaces: 'bag shrink + Hub + Stripe Session',
    action: 'full ABCD →50ms subset AB + Hub',
    http: {'full': full?.brief, 'small': small?.brief},
    oracles: {
      'dual': dualA4,
      'full': fullOr,
      'small': smallOr,
      'hub': hubA4,
    },
    result: a4r,
    lens: 'EN6',
    classeNova: true,
    countFinding: a4r == 'HOLD',
  );

  // ----- A5 2× idêntico + Hub -----
  final idn = await mkBag(c, n: 3, buyer: b3, jwt: c.buyer3Jwt!, tag: 'A5');
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
  final hubA5 = await hubNs(c, idn.skus, jwt: c.buyer3Jwt);
  final dualA5 = dualCreate(c, same1, same2);
  final sidsA5 = {
    if (c.usefulCs(same1)) same1!.sessionId!,
    if (c.usefulCs(same2)) same2!.sessionId!,
  };
  final reusedOk = sidsA5.length <= 1 &&
      (same1?.reused == true || same2?.reused == true || sidsA5.length == 1);
  String a5r;
  if (idn.oids.length < 3) {
    a5r = 'SKIP';
    c.skip('A5', 'EN6', 'fixture idêntico', idn.oids.length);
  } else if (dualA5) {
    a5r = 'HOLD';
    c.hold(
      id: 'P1-A5-IDENTICAL-DUAL',
      lens: 'EN6',
      severity: 'P1',
      title: '2× saco idêntico: duas Sessions distintas',
      actor: 'B3 2× checkoutBag ABC paralelo',
      pre: '3 SKUs qty=2 Hub visíveis',
      repro: 'Future.wait mesmo bag_lines ×2',
      expected: '1 cs_ + reused',
      obtained: {
        'h1': same1?.brief,
        'h2': same2?.brief,
        'sids': sidsA5.toList(),
        'hub': hubA5,
      },
    );
  } else {
    a5r = 'FAIL';
    c.block('A5', 'EN6', '2× idêntico → 1 cs_ reused + Hub', {
      'h1': same1?.brief,
      'h2': same2?.brief,
      'sids': sidsA5.toList(),
      'reused_ok': reusedOk,
      'hub': hubA5,
    });
  }
  c.probe(
    id: 'A5',
    surfaces: 'bag idêntico + Hub + orders',
    action: 'Future.wait 2× mesmo saco ABC + Hub',
    http: {'h1': same1?.brief, 'h2': same2?.brief},
    oracles: {
      'dual': dualA5,
      'sids': sidsA5.toList(),
      'reused': [same1?.reused, same2?.reused],
      'hub': hubA5,
    },
    result: a5r,
    lens: 'EN6',
    classeNova: true,
    countFinding: a5r == 'HOLD',
  );
}

/// EN-B Stock / live (≥4)
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
    c.skip('B1', 'EN5', 'sku B1 fail', 'null');
  } else if (twoCs >= 2) {
    b1r = 'HOLD';
    c.hold(
      id: 'P1-B1-TWO-BUYERS',
      lens: 'EN5',
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
    c.block('B1', 'EN5', '2 buyers Hub: ≤1 cs_', {
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
    lens: 'EN5',
    countFinding: b1r == 'HOLD',
  );

  // ----- B2 rifa drawn + Hub + live_item -----
  final skuB2 = await c.createProduct(
    title: '$prefix B2 raffle-prize',
    qty: 1,
    listed: true,
    live: true,
  );
  final liveB2 = await c.createLive(title: '$prefix B2 raffle');
  String? liB2;
  HttpHit? rafB2;
  HttpHit? drawB2;
  HttpHit? hubB2;
  HttpHit? insB2;
  Map<String, dynamic>? prodB2;
  List<Map<String, dynamic>> winB2 = const [];
  if (liveB2 != null && skuB2 != null) {
    liB2 = await c.createLiveItem(
      liveId: liveB2,
      title: '$prefix B2 prize-li',
      kind: 'marketplace_product',
      productId: skuB2,
    );
    rafB2 = await c.createRaffle(
      liveId: liveB2,
      seller: s1,
      liveItemId: liB2,
      title: '$prefix B2 prize',
    );
    final rafId = rafB2.firstId;
    if (rafId != null) {
      await c.awardTickets(rafId, b1, src: 'b2');
      await c.closeRaffle(rafId);
      drawB2 = await c.drawRaffle(rafId);
      winB2 = await c.raffleWinners(rafId);
      prodB2 = await c.productRow(skuB2);
      hubB2 = await c.hubSku(skuB2, jwt: c.buyerJwt);
      insB2 = await c.insertOrderHit(
        productId: skuB2,
        jwt: c.buyer2Jwt,
        buyer: b2,
        price: 12,
      );
    }
  }
  final liRow = liB2 == null ? null : await c.liveItemRow(liB2);
  final itemSt = '${liRow?['status'] ?? ''}';
  final hubN = hubB2?.list.length ?? -1;
  final liveItemStale = winB2.isNotEmpty && hubN == 0 && itemSt == 'available';
  final sealedOpen = winB2.isNotEmpty && hubN == 0 && (insB2?.ok == true);
  String b2r;
  if (skuB2 == null || liveB2 == null || rafB2?.firstId == null) {
    b2r = 'SKIP';
    c.skip('B2', 'EN7', 'raffle fixture', rafB2?.brief ?? 'null');
  } else if (liveItemStale || sealedOpen) {
    b2r = 'HOLD';
    c.hold(
      id: liveItemStale ? 'P2-B2-LIVEITEM-AVAILABLE' : 'P2-B2-SEAL-STOCK',
      lens: 'EN7',
      severity: 'P2',
      title: liveItemStale
          ? 'Rifa drawn: Hub 0 mas live_item continua available'
          : 'Hub ocultou o prémio mas insert marketplace ainda abre',
      actor: 'S1 draw + Hub + live_item + B2 insert',
      pre: 'rifa drawn winner B1; qty=1',
      repro: 'draw + hub_products_public + live_items.status + POST orders',
      expected: 'live_item ≠ available; Hub 0; insert deny',
      obtained: {
        'hub_n': hubN,
        'qty': prodB2?['quantity'],
        'ins': insB2?.brief,
        'winners': winB2.length,
        'item': itemSt,
      },
    );
  } else {
    b2r = 'FAIL';
    c.block('B2', 'EN7', 'rifa drawn + Hub + live_item selados', {
      'hub_n': hubN,
      'qty': prodB2?['quantity'],
      'ins': insB2?.brief,
      'winners': winB2.length,
      'item': itemSt,
      'item_active': liRow?['is_active'],
    });
  }
  c.probe(
    id: 'B2',
    surfaces: 'rifa + Hub + live_item + insert',
    action: 'draw winner + Hub + live_item ≠ available',
    http: {'raf': rafB2?.brief, 'draw': drawB2?.brief, 'ins': insB2?.brief},
    oracles: {
      'hub_n': hubN,
      'qty': prodB2?['quantity'],
      'winners': winB2.length,
      'ins_ok': insB2?.ok,
      'item': itemSt,
      'item_active': liRow?['is_active'],
    },
    result: b2r,
    lens: 'EN7',
    classeNova: true,
    countFinding: b2r == 'HOLD',
  );

  // ----- B3 hitch A + bag B -----
  final skuA = await c.createProduct(
    title: '$prefix B3 hitch-A',
    qty: 1,
    listed: true,
    live: true,
  );
  final skuB = await c.createProduct(
    title: '$prefix B3 bag-B',
    qty: 1,
    listed: true,
    live: false,
  );
  final liveB3 = await c.createLive(title: '$prefix B3 raffle-bag');
  String? liA;
  String? resA;
  HttpHit? acc;
  HttpHit? bagB;
  HttpHit? hubA;
  HttpHit? hubB;
  HttpHit? rafB3;
  String? oidB;
  if (liveB3 != null && skuA != null) {
    liA = await c.createLiveItem(
      liveId: liveB3,
      title: '$prefix B3 li-A',
      kind: 'marketplace_product',
      productId: skuA,
    );
    rafB3 = await c.createRaffle(
      liveId: liveB3,
      seller: s1,
      liveItemId: liA,
      title: '$prefix B3 raffle-A',
    );
    if (rafB3.firstId != null) {
      await c.awardTickets(rafB3.firstId!, b2, src: 'b3');
    }
    if (liA != null) {
      resA = await c.insertReservation(
        liveId: liveB3,
        liveItemId: liA,
        jwt: c.buyer2Jwt,
        buyer: b2,
      );
      if (resA != null) acc = await c.acceptRes(resA);
    }
  }
  if (skuB != null) {
    oidB = await c.insertOrder(
      productId: skuB,
      jwt: c.buyerJwt,
      price: 12,
    );
    if (oidB != null) {
      bagB = await c.checkoutBag(
        lines: [
          {'order_id': oidB, 'product_id': skuB, 'quantity': 1, 'price': 12.0},
        ],
        jwt: c.buyerJwt,
        seller: s1,
      );
      track(c, bagB);
    }
  }
  if (skuA != null) hubA = await c.hubSku(skuA, jwt: c.buyerJwt);
  if (skuB != null) hubB = await c.hubSku(skuB, jwt: c.buyerJwt);
  final resRow = resA == null ? null : await c.resRow(resA);
  final accepted = '${resRow?['status']}' == 'accepted';
  final bagOk = c.usefulCs(bagB);
  String b3r;
  if (skuA == null || skuB == null || liveB3 == null) {
    b3r = 'SKIP';
    c.skip('B3', 'EN2', 'fixture hitch+bag', 'null');
  } else if (accepted && !bagOk && denied(bagB ?? HttpHit(0, '', {}))) {
    b3r = 'HOLD';
    c.hold(
      id: 'P2-B3-CROSS-LINE',
      lens: 'EN2',
      severity: 'P2',
      title: 'Accept live SKU-A (com rifa) bloqueou saco da OUTRA linha SKU-B',
      actor: 'S1 accept + B1 bag',
      pre: 'SKU-A hitch+rifa accepted; SKU-B stock independente',
      repro: 'accept A + bag CPI B',
      expected: 'saco B abre cs_',
      obtained: {
        'acc': acc?.brief,
        'bag': bagB?.brief,
        'hubA': hubA?.list.length,
        'hubB': hubB?.list.length,
      },
    );
  } else {
    b3r = 'FAIL';
    c.block('B3', 'EN2', 'rifa+accept A não cega bag B; Hub A/B', {
      'accepted': accepted,
      'bag_cs': bagB?.sessionId,
      'hubA': hubA?.list.length,
      'hubB': hubB?.list.length,
    });
  }
  c.probe(
    id: 'B3',
    surfaces: 'rifa + live accept + bag outra linha + Hub',
    action: 'rifa activa A + accept hitch A + bag CPI SKU-B',
    http: {'acc': acc?.brief, 'bag': bagB?.brief, 'raf': rafB3?.brief},
    oracles: {
      'res': resRow?['status'],
      'bag_cs': bagB?.sessionId,
      'hubA_n': hubA?.list.length,
      'hubB_n': hubB?.list.length,
    },
    result: b3r,
    lens: 'EN2',
    classeNova: true,
    countFinding: b3r == 'HOLD',
  );

  // ----- B4 unlist∥CPI -----
  final skuUl = await c.createProduct(
    title: '$prefix B4 unlist',
    qty: 1,
    listed: true,
    live: false,
    price: 13,
  );
  HttpHit? ckUl;
  HttpHit? patchUl;
  HttpHit? hubUl;
  Map<String, dynamic>? prodUl;
  String? oidUl;
  if (skuUl != null) {
    oidUl = await c.insertOrder(
      productId: skuUl,
      jwt: c.buyerJwt,
      price: 13,
    );
    if (oidUl != null) {
      final raced = await Future.wait([
        c.checkout(orderId: oidUl, productId: skuUl, amount: 1),
        c.rest(
          'PATCH',
          'products?id=eq.$skuUl',
          jwt: c.sellerJwt,
          body: {'list_on_marketplace': false, 'quantity': 0},
        ),
      ]);
      ckUl = raced[0];
      patchUl = raced[1];
      track(c, ckUl);
    }
    prodUl = await c.productRow(skuUl);
    hubUl = await c.hubSku(skuUl, jwt: c.buyerJwt);
  }
  final dualUl = ckUl != null &&
      ckUl.ok &&
      (ckUl.sessionId ?? '').startsWith('cs_') &&
      prodUl?['list_on_marketplace'] == false &&
      numOf(prodUl?['quantity']) == 0;
  String b4r;
  if (skuUl == null || oidUl == null) {
    b4r = 'SKIP';
    c.skip('B4', 'EN5', 'fixture unlist', 'null');
  } else if (dualUl) {
    b4r = 'HOLD';
    c.hold(
      id: 'P1-B4-UNLIST-CPI',
      lens: 'EN5',
      severity: 'P1',
      title: 'Session aberta sobre SKU unlisted qty=0',
      actor: 'B1 CPI ∥ S1 unlist',
      pre: 'qty=1 listed Hub visível',
      repro: 'Future.wait CPI ∥ PATCH unlist qty=0',
      expected: 'CPI 400 not listed OU unlist perde (ainda listed)',
      obtained: {
        'ck': ckUl?.brief,
        'patch': patchUl?.brief,
        'listed': prodUl?['list_on_marketplace'],
        'qty': prodUl?['quantity'],
        'hub_n': hubUl?.list.length,
      },
    );
  } else {
    b4r = 'FAIL';
    c.block('B4', 'EN5', 'unlist∥CPI sem Session+qty0 simultâneo', {
      'ck': ckUl?.brief,
      'patch': patchUl?.brief,
      'listed': prodUl?['list_on_marketplace'],
      'qty': prodUl?['quantity'],
      'hub_n': hubUl?.list.length,
    });
  }
  c.probe(
    id: 'B4',
    surfaces: 'Hub + CPI + products unlist',
    action: 'Future.wait CPI ∥ unlist+qty=0 + Hub',
    http: {'ck': ckUl?.brief, 'patch': patchUl?.brief},
    oracles: {
      'dual': dualUl,
      'listed': prodUl?['list_on_marketplace'],
      'qty': prodUl?['quantity'],
      'hub_n': hubUl?.list.length,
      'cs': ckUl?.sessionId,
    },
    result: b4r,
    lens: 'EN5',
    classeNova: true,
    countFinding: b4r == 'HOLD',
  );
}

/// EN-C Caixa composição (≥5)
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
      lens: 'EN8');
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
    c.skip('C1', 'EN8', 'setup_paid_bag fail', paidBag.brief);
  } else if (!bothPago) {
    c1r = 'HOLD';
    c.hold(
      id: 'P1-C1-BAG-NOT-PAGO',
      lens: 'EN8',
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
      lens: 'EN8',
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
      lens: 'EN8',
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
    c.block('C1', 'EN8', 'bag pago único: 4 sítios observados', {
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
    lens: 'EN8',
    classeNova: true,
    countFinding: c1r == 'HOLD',
  );

  // ----- C2 oferta underpay selo -----
  final skuC2 = await c.createProduct(
    title: '$prefix C2 offer',
    qty: 2,
    price: 18,
    listed: true,
    live: false,
  );
  HttpHit? off;
  HttpHit? acc;
  HttpHit? cpiC2;
  HttpHit? hubC2;
  String? oidC2;
  String? offId;
  Map<String, dynamic>? offRow;
  Map<String, dynamic>? ordC2;
  if (skuC2 != null) {
    off = await c.insertOffer(
      productId: skuC2,
      amount: 8,
      listPrice: 18,
      jwt: c.buyerJwt,
    );
    offId = off.firstId;
    if (offId != null) {
      acc = await c.acceptOffer(offId);
      offRow = await c.offerRow(offId);
      oidC2 = await c.insertOrder(
        productId: skuC2,
        jwt: c.buyerJwt,
        price: 8,
        offerId: offId,
      );
      if (oidC2 != null) {
        cpiC2 = await c.checkout(
          orderId: oidC2,
          productId: skuC2,
          jwt: c.buyerJwt,
          amount: 1,
        );
        track(c, cpiC2);
      }
    }
    hubC2 = await c.hubSku(skuC2, jwt: c.buyerJwt);
    if (oidC2 != null) ordC2 = await c.orderRow(oidC2);
  }
  final sealed = cpiC2?.amountTotal;
  final under = c.usefulCs(cpiC2) && sealed != null && sealed < 800;
  String c2r;
  if (skuC2 == null || offId == null) {
    c2r = 'SKIP';
    c.skip('C2', 'EN6', 'offer fail', off?.brief ?? 'null');
  } else if (under) {
    c2r = 'HOLD';
    c.hold(
      id: 'P0-C2-UNDERPAY',
      lens: 'EN6',
      severity: 'P0',
      title: 'CPI selou underpay da oferta aceite',
      actor: 'B1 CPI amount=1 vs oferta 8€',
      pre: 'oferta aceite 8€ list 18€',
      repro: 'create-payment-intent amount=1',
      expected: 'selo ≥800¢ (oferta) ou deny',
      obtained: {
        'sealed': sealed,
        'offer': offRow,
        'cpi': cpiC2?.brief,
        'hub_n': hubC2?.list.length,
      },
    );
  } else {
    c2r = 'FAIL';
    c.block('C2', 'EN6', 'oferta aceite: selo servidor vs amount=1', {
      'offer': offRow?['amount'],
      'status': offRow?['status'],
      'sealed': sealed,
      'hub_n': hubC2?.list.length,
      'cpi': cpiC2?.brief,
    });
  }
  c.probe(
    id: 'C2',
    surfaces: 'offer + CPI + Hub + orders',
    action: 'oferta 8€ aceite + CPI amount=1 (selo servidor)',
    http: {'off': off?.brief, 'acc': acc?.brief, 'cpi': cpiC2?.brief},
    oracles: {
      'offer_amt': offRow?['amount'],
      'offer_st': offRow?['status'],
      'sealed_cents': sealed,
      'hub_n': hubC2?.list.length,
      'order': ordC2?['status'],
    },
    result: c2r,
    lens: 'EN6',
    classeNova: true,
    countFinding: c2r == 'HOLD',
  );

  // ----- C3 release∥disputa clawback (1 efeito) -----
  final paidC3 = await c.payToPago(lens: 'EN4', initialQty: 2);
  HttpHit? plantC3;
  HttpHit? relC3;
  HttpHit? dispC3;
  HttpHit? hubC3;
  Map<String, dynamic>? ordC3;
  Map<String, dynamic>? dispRow;
  final wS0c3 = await c.walletBal(s1);
  if (paidC3 != null) {
    plantC3 = await c.plantConcluidoMao(paidC3.oid);
    final raced = await Future.wait([
      c.tryRelease(paidC3.oid, jwt: c.buyerJwt),
      c.insertDispute(orderId: paidC3.oid),
    ]);
    relC3 = raced[0];
    dispC3 = raced[1];
    ordC3 = await c.orderRow(paidC3.oid);
    if (dispC3.firstId != null) dispRow = await c.disputeRow(dispC3.firstId!);
    hubC3 = await c.hubSku(paidC3.pid, jwt: c.buyerJwt);
  }
  final wS1c3 = await c.walletBal(s1);
  final releasedC3 = c.releasedTrue(relC3);
  final dWalletC3 = wS1c3 - wS0c3;
  final dispOpen = dispC3 != null &&
      dispC3.ok &&
      '${dispRow?['status'] ?? ''}' == 'aberta';
  final twoEffects = releasedC3 && dWalletC3 > 0 && dispOpen;
  String c3r;
  if (paidC3 == null) {
    c3r = 'SKIP';
    c.skip('C3', 'EN4', 'paid C3 fail', 'null');
  } else if (twoEffects) {
    c3r = 'HOLD';
    c.hold(
      id: 'P1-C3-RELEASE-DISPUTE',
      lens: 'EN4',
      severity: 'P1',
      title: 'Release creditou E disputa aberta (2 efeitos dinheiro)',
      actor: 'B1 release ∥ disputa',
      pre: 'pago Stripe; plant concluido+mão',
      repro: 'Future.wait release + POST disputa',
      expected: '1 efeito (crédito XOR disputa)',
      obtained: {
        'rel': relC3?.brief,
        'disp': dispC3?.brief,
        'dWallet': dWalletC3,
        'status': ordC3?['status'],
        'hub_n': hubC3?.list.length,
      },
    );
  } else {
    c3r = 'FAIL';
    c.block('C3', 'EN4', 'release∥disputa: 1 efeito (anti-atrofia)', {
      'rel': relC3?.brief,
      'disp': dispC3?.brief,
      'dWallet': dWalletC3,
      'released': releasedC3,
      'disp_open': dispOpen,
      'status': ordC3?['status'],
      'hub_n': hubC3?.list.length,
      'plant': plantC3?.brief,
    });
  }
  c.probe(
    id: 'C3',
    surfaces: 'wallet + disputa + Hub leftover',
    action: 'Future.wait release∥disputa em concluido+mão',
    http: {
      'plant': plantC3?.brief,
      'rel': relC3?.brief,
      'disp': dispC3?.brief,
    },
    oracles: {
      'released': releasedC3,
      'dWallet': dWalletC3,
      'disp_open': dispOpen,
      'disp_st': dispRow?['status'],
      'status': ordC3?['status'],
      'hub_n': hubC3?.list.length,
      'pi': paidC3?.pi,
    },
    result: c3r,
    lens: 'EN4',
    classeNova: true,
    countFinding: twoEffects,
  );

  // ----- C4 leftover qty 2→1 -----
  final paidC4 = await c.payToPago(lens: 'EN8', initialQty: 2, buyer: b1);
  HttpHit? hubC4;
  HttpHit? leftoverCpi;
  Map<String, dynamic>? prodC4;
  Map<String, dynamic>? ordC4;
  String? oidLeft;
  if (paidC4 != null) {
    ordC4 = await c.orderRow(paidC4.oid);
    prodC4 = await c.productRow(paidC4.pid);
    hubC4 = await c.hubSku(paidC4.pid, jwt: c.buyerJwt);
    oidLeft = await c.insertOrder(
      productId: paidC4.pid,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 12,
    );
    if (oidLeft != null) {
      leftoverCpi = await c.checkout(
        orderId: oidLeft,
        productId: paidC4.pid,
        jwt: c.buyer2Jwt,
        buyer: b2,
      );
      track(c, leftoverCpi);
    }
  }
  final qtyC4 = numOf(prodC4?['quantity']) ?? -1;
  final hubC4n = hubC4?.list.length ?? -1;
  final leftoverBuyable = c.usefulCs(leftoverCpi);
  final leftoverBroken =
      '${ordC4?['status']}' == 'pago' && qtyC4 == 1 && hubC4n != 1;
  String c4r;
  if (paidC4 == null) {
    c4r = 'SKIP';
    c.skip('C4', 'EN1', 'paid leftover fail', 'null');
  } else if (leftoverBroken) {
    c4r = 'HOLD';
    c.hold(
      id: 'P1-C4-LEFTOVER-HUB',
      lens: 'EN1',
      severity: 'P1',
      title: 'Pago qty 2→1: Hub não mostra a unidade que sobra',
      actor: 'B1 pago + Hub + B2 leftover CPI',
      pre: 'qty inicial 2 compra 1',
      repro: 'setup_paid_order + hub_products_public + CPI leftover',
      expected: 'status pago; qty=1; Hub n=1; leftover comprável',
      obtained: {
        'status': ordC4?['status'],
        'qty': qtyC4,
        'hub_n': hubC4n,
        'cpi': leftoverCpi?.brief,
      },
    );
  } else {
    c4r = 'FAIL';
    c.block('C4', 'EN1', 'leftover qty 2→1 Hub+CPI observados', {
      'status': ordC4?['status'],
      'qty': qtyC4,
      'hub_n': hubC4n,
      'leftover_cs': leftoverCpi?.sessionId,
      'buyable': leftoverBuyable,
      'pi': paidC4.pi,
    });
  }
  c.probe(
    id: 'C4',
    surfaces: 'Hub + orders + CPI leftover',
    action: 'leftover após pago parcial qty 2→1',
    http: {'paid': paidC4?.hit.brief, 'cpi': leftoverCpi?.brief},
    oracles: {
      'status': ordC4?['status'],
      'qty': qtyC4,
      'hub_n': hubC4n,
      'leftover_cs': leftoverCpi?.sessionId,
      'buyable': leftoverBuyable,
      'pi': paidC4?.pi,
    },
    result: c4r,
    lens: 'EN1',
    countFinding: c4r == 'HOLD',
  );

  // ----- C5 bizum sem cs_ -----
  HttpHit? bizHit;
  String? bizPm;
  String? bizSid;
  final bizPid = await c.createProduct(
    title: '$prefix C5 bizum',
    qty: 2,
    price: 17,
    listed: true,
    live: false,
  );
  if (bizPid != null) {
    var oid = await c.insertOrder(
      productId: bizPid,
      price: 17,
      jwt: c.buyerJwt,
      payment: 'bizum',
    );
    if (oid == null) {
      final svcIns = await c.rest('POST', 'orders', service: true, body: {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': bizPid,
        'price_total': 17,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'bizum',
        'shipping_method': 'entrega em mão',
      });
      oid = svcIns.firstId;
      if (oid != null) c.createdOrderIds.add(oid);
    }
    if (oid != null) {
      bizPm = '${(await c.orderRow(oid))?['payment_method'] ?? ''}';
      bizHit = await c.checkout(orderId: oid, productId: bizPid, amount: 1);
      track(c, bizHit);
      bizSid = bizHit.sessionId;
    }
  }
  final offBypass = bizHit != null &&
      bizHit.ok &&
      (bizSid ?? '').startsWith('cs_') &&
      (bizPm ?? '').toLowerCase().contains('bizum');
  String c5r;
  if (bizPid == null) {
    c5r = 'SKIP';
    c.skip('C5', 'EN6', 'bizum fixture', 'null');
  } else if (offBypass) {
    c5r = 'HOLD';
    c.hold(
      id: 'P2-C5-BIZUM',
      lens: 'EN6',
      severity: 'P2',
      title: 'método off residual bizum abriu Session Stripe',
      actor: 'B1 JWT',
      pre: 'order payment_method=bizum',
      repro: 'insert bizum; CPI',
      expected: 'CPI 400 off-platform ou sem cs_',
      obtained: {'hit': bizHit?.brief, 'pm': bizPm, 'sid': bizSid},
    );
  } else {
    c5r = 'FAIL';
    c.block('C5', 'EN6', 'bizum fail-closed; sem cs_ off', {
      'hit': bizHit?.brief,
      'pm': bizPm,
      'sid': bizSid,
    });
  }
  c.probe(
    id: 'C5',
    surfaces: 'orders + CPI denylist',
    action: 'payment_method bizum (1 linha) → sem cs_',
    http: bizHit?.brief ?? 'n/a',
    oracles: {'pm': bizPm, 'sid': bizSid, 'off_bypass': offBypass},
    result: c5r,
    lens: 'EN6',
    classeNova: true,
    countFinding: c5r == 'HOLD',
  );
}
