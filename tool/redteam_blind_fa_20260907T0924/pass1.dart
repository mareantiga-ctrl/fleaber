/// RED TEAM CEGO FA pass1 — checkout smoke pré-P4.
/// Matriz A1–A4 · B1–B3 · C1–C3. Sem correções. Stripe TEST 4242.
import 'dart:io';

import '_rtfa.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('FA pass1 staging=${c.url} prefix=$prefix');
  stdout.writeln(
    c.stripeTestKey == null
        ? 'WARN no sk_test_ — pay via pk/payment_pages + settle / e2e'
        : 'sk_test_ present — native retrieve+confirm',
  );
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.restoreSeller1Published();
  c.note('actors', 'ids', {
    'b': c.buyerId,
    's': c.sellerId,
    'seller_hub': (await c.profile(c.sellerId!))?['hub_published'],
    'sk': c.stripeTestKey != null,
  });
  final wallets0 = await c.wallets();
  c.note('wallet.pre', 'baseline', wallets0, lens: 'FA-C', well: 'FA-C');

  await faA(c);
  await faB(c);
  await faC(c);

  final wallets1 = await c.wallets();
  c.note('wallet.post', 'após probes', {
    'pre': wallets0,
    'post': wallets1,
  }, lens: 'FA-C', well: 'FA-C');

  await c.dumpAll('pass1_findings.json');
  final races = c.probes
      .where((p) => '${p['payload']}'.contains('Future.wait'))
      .map((p) => p['probe_id'])
      .toList();
  final novas = c.probes
      .where((p) => p['classe_nova'] == 'SIM')
      .map((p) => p['probe_id'])
      .toList();
  final duals = c.probes.where((p) => p['verdict'] == 'HOLD').toList();
  await dumpJson('${outDir()}/probes.json', {
    'stamp': stamp,
    'prefix': prefix,
    'auditor': 'REDTEAM_BLIND_FA_CHECKOUT_SMOKE_PRE_P4_v1',
    'probes': c.probes,
    'n': c.probes.length,
    'races': races,
    'classes_novas': novas,
    'findings': c.findings.length,
    'findings_ids': c.findings.map((f) => f['id']).toList(),
    'overlaps': c.overlapCaptures,
    'dual_holds': duals.map((p) => p['probe_id']).toList(),
  });
  stdout.writeln(
    'DONE probes=${c.probes.length} findings=${c.findings.length} '
    'blocked=${c.blocked.length} skip=${c.skipped.length} '
    'races=${races.length} classe_nova=${novas.length} '
    'overlaps=${c.overlapCaptures.keys.toList()} '
    'lenses=${c.lensesHit.toList()..sort()} wells=${c.wellsTried.toList()..sort()}',
  );
}

Future<void> pause([int ms = 500]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

List<Map<String, Object?>> bagLines(
  Iterable<({String oid, String pid, double price})> rows,
) {
  return [
    for (final r in rows) {'order_id': r.oid, 'product_id': r.pid},
  ];
}

Future<List<({String oid, String pid, double price})>> mkSkus(
  Rtdb c, {
  required int n,
  required String tag,
  int qty = 2,
  double price = 12,
  String? buyer,
  String? jwt,
}) async {
  final out = <({String oid, String pid, double price})>[];
  for (var i = 0; i < n; i++) {
    final p = price + i;
    final pid = await c.createProduct(
      title: '$prefix-$tag-$i',
      qty: qty,
      price: p,
    );
    if (pid == null) continue;
    final oid = await c.insertOrder(
      productId: pid,
      price: p,
      buyer: buyer,
      jwt: jwt ?? c.buyerJwt,
    );
    if (oid == null) continue;
    out.add((oid: oid, pid: pid, price: p));
  }
  return out;
}

Set<String> openCs(List<HttpHit> hits) {
  return hits
      .map((h) => h.sessionId ?? '')
      .where((s) => s.startsWith('cs_'))
      .toSet();
}

bool rateLimited(HttpHit h) {
  return h.status == 429 ||
      h.body.toLowerCase().contains('demasiados checkouts');
}

bool overlapping400(HttpHit h) {
  final raw = h.body.toLowerCase();
  return h.status == 400 &&
      (raw.contains('overlapping bag session') ||
          raw.contains('overlapping') ||
          raw.contains('may_create') ||
          raw.contains('checkout in flight'));
}

bool dualCsCreate(List<HttpHit> hits) {
  final created = hits
      .where((h) =>
          h.ok && (h.sessionId ?? '').startsWith('cs_') && h.reused != true)
      .map((h) => h.sessionId!)
      .toSet();
  if (created.length >= 2) return true;
  final sids = hits
      .where((h) => h.ok && (h.sessionId ?? '').startsWith('cs_'))
      .map((h) => h.sessionId!)
      .toSet();
  return sids.length >= 2;
}

Map<String, String?> urlsFromHits(List<HttpHit> hits) {
  final m = <String, String?>{};
  for (final h in hits) {
    final sid = h.sessionId;
    if (sid != null && sid.startsWith('cs_')) {
      m[sid] = h.checkoutUrl;
    }
  }
  return m;
}

void skipProbe(
  Rtdb c, {
  required String id,
  required String poco,
  required String lens,
  required String payload,
  required Object? why,
  bool classeNova = false,
}) {
  c.skip(id, lens, payload, why);
  c.probe(
    id: id,
    poco: poco,
    payload: payload,
    http: 'skip',
    bd: '$why',
    verdict: 'SKIP',
    lens: lens,
    classeNova: classeNova,
  );
}

Future<Map<String, Object?>> packHits(
  Rtdb c,
  List<HttpHit> hits,
  List<({String oid, String pid, double price})> skus,
) async {
  await Future<void>.delayed(const Duration(seconds: 2));
  for (final h in hits) {
    c.trackSession(h);
  }
  final urls = urlsFromHits(hits);
  final sids = openCs(hits);
  final oracle = <Map<String, Object?>>[];
  var payable = 0;
  for (final sid in sids) {
    final o = await c.sessionOracle(sid, checkoutUrl: urls[sid]);
    oracle.add(Map<String, Object?>.from(o));
    if (o['open_payable'] == true) payable++;
  }
  final stored = <String>[];
  final hub = <Map<String, Object?>>[];
  for (final r in skus) {
    stored.add(
      '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    );
    final h = await c.hubSku(r.pid);
    hub.add({'id': r.pid, 'http': h.status, 'n': h.list.length});
  }
  final creates = hits
      .where((h) =>
          h.ok && (h.sessionId ?? '').startsWith('cs_') && h.reused != true)
      .map((h) => h.sessionId!)
      .toSet()
      .length;
  final dual = dualCsCreate(hits);
  return {
    'status': hits.map((h) => h.status).toList(),
    'sids': sids.toList(),
    'reused': hits.map((h) => h.reused).toList(),
    'urls': urls,
    'payable_open': payable,
    'oracle': oracle,
    'stored': stored,
    'hub': hub,
    'briefs': hits.map((h) => h.brief).toList(),
    'distinct_cs': sids.length,
    'creates': creates,
    'overlap_400': hits.any(overlapping400),
    'dual_create': dual,
    'amounts': hits.map((h) => h.amountTotal).toList(),
  };
}

void storeOverlap(
  Rtdb c,
  String id,
  List<({String oid, String pid, double price})> skus,
  Map<String, Object?> pack,
) {
  c.overlapCaptures[id] = {
    'skus': [
      for (final r in skus) {'oid': r.oid, 'pid': r.pid, 'price': r.price},
    ],
    'sids': pack['sids'],
    'urls': pack['urls'],
    'dual_create': pack['dual_create'],
    'payable_open': pack['payable_open'],
    'stored': pack['stored'],
    'status': pack['status'],
    'overlap_400': pack['overlap_400'],
    'creates': pack['creates'],
    'reused': pack['reused'],
    'amounts': pack['amounts'],
    'lines': bagLines(skus),
  };
}

void maybeHoldDual(Rtdb c, String id, Map<String, Object?> pack) {
  if (pack['dual_create'] != true) return;
  if (c.findings.any((f) => f['id'] == 'P1-1')) return;
  c.hold(
    id: 'P1-1',
    lens: 'FA-A',
    severity: 'P1',
    title:
        'Saco e artigo avulso / cadeado adjacente: duas Sessions (fail-closed não actuou)',
    actor: 'buyer JWT fresco',
    pre: '≤1 create; 2.º HTTP 400 overlapping / reused mesmo sid',
    repro: 'Future.wait $id',
    expected: '200+400 ou 400+200 ou 1 cs_ reused — nunca 2 creates',
    obtained: {
      'probe': id,
      'sids': pack['sids'],
      'status': pack['status'],
      'reused': pack['reused'],
      'creates': pack['creates'],
    },
  );
}

Future<void> overlapProbe({
  required Rtdb c,
  required String id,
  required String poco,
  required String lens,
  required String payload,
  required List<({String oid, String pid, double price})> skus,
  required List<HttpHit> hits,
  required String expected,
  bool classeNova = true,
  bool regression = false,
}) async {
  if (hits.isEmpty) {
    skipProbe(
      c,
      id: id,
      poco: poco,
      lens: lens,
      payload: payload,
      why: 'no hits',
      classeNova: classeNova,
    );
    return;
  }
  if (hits.every(rateLimited)) {
    skipProbe(
      c,
      id: id,
      poco: poco,
      lens: lens,
      payload: payload,
      why: '429 rate limit — não é prova mutex',
      classeNova: classeNova,
    );
    return;
  }
  final pack = await packHits(c, hits, skus);
  storeOverlap(c, id, skus, pack);
  final dual = pack['dual_create'] == true;
  c.note('$id.pack', payload, pack, lens: lens, well: poco);
  c.probe(
    id: id,
    poco: poco,
    payload: payload,
    http: pack['briefs'],
    bd: {
      'sids': pack['sids'],
      'distinct': pack['distinct_cs'],
      'reused': pack['reused'],
      'payable_open': pack['payable_open'],
      'stored': pack['stored'],
      'oracle': pack['oracle'],
      'overlap_400': pack['overlap_400'],
      'creates': pack['creates'],
      'hub': pack['hub'],
      'expected': expected,
    },
    verdict: dual ? 'HOLD' : 'FAIL',
    lens: lens,
    classeNova: classeNova,
  );
  if (dual) {
    maybeHoldDual(c, id, pack);
    if (regression) {
      c.note('$id.regression_broke', 'cadeado deveria ≤1 cs_', pack['sids'],
          lens: lens, well: poco);
    }
  } else {
    c.block(
      '$id-FA',
      lens,
      '$id ≤1 create (400 overlapping / reused / may_create)',
      {
        'sids': pack['sids'],
        'status': pack['status'],
        'reused': pack['reused'],
        'overlap_400': pack['overlap_400'],
      },
    );
  }
}

Future<void> asFresh(Rtdb c, String tag) async {
  final actor = await c.mintBuyer(tag);
  c.buyerId = actor.id;
  c.buyerJwt = actor.jwt;
}

/// FA-A Cadeado (≥4)
Future<void> faA(Rtdb c) async {
  c.wellsTried.add('FA-A');

  // A1 bag ABCDE ∥ single C t=0 fresco — exactamente 1 race bag∥avulso
  await pause();
  await asFresh(c, 'a1');
  final a1 = await mkSkus(c, n: 5, tag: 'a1-abcde-c-0', qty: 2, price: 8);
  if (a1.length == 5) {
    final midC = a1[2];
    final hits = await parallel([
      c.checkoutBag(lines: bagLines(a1), amount: 1),
      c.checkout(orderId: midC.oid, productId: midC.pid, amount: 1),
    ]);
    await overlapProbe(
      c: c,
      id: 'A1',
      poco: 'FA-A',
      lens: 'FA-A',
      payload: 'Future.wait bag ABCDE ∥ single C t=0 (fresco)',
      skus: a1,
      hits: hits,
      expected: '≤1 cs_ útil (200+400 / 400+200 / reused mesmo sid)',
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A1',
      poco: 'FA-A',
      lens: 'FA-A',
      payload: 'Future.wait bag ABCDE ∥ single C t=0',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // A2 6∥4 t=0
  await pause();
  await asFresh(c, 'a2');
  final a2 = await mkSkus(c, n: 6, tag: 'a2-6x4', qty: 2, price: 9);
  if (a2.length == 6) {
    final hits = await parallel([
      c.checkoutBag(lines: bagLines(a2), amount: 1),
      c.checkoutBag(lines: bagLines(a2.sublist(1, 5)), amount: 1),
    ]);
    await overlapProbe(
      c: c,
      id: 'A2',
      poco: 'FA-A',
      lens: 'FA-A',
      payload: 'Future.wait bag 6∥4 t=0',
      skus: a2,
      hits: hits,
      expected: '400+200 · 1 cs_ — nunca 2 creates',
      classeNova: false,
      regression: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A2',
      poco: 'FA-A',
      lens: 'FA-A',
      payload: 'Future.wait bag 6∥4 t=0',
      why: 'mkSkus',
    );
  }

  // A3 expand subset→50ms→superset
  await pause();
  await asFresh(c, 'a3');
  final a3 = await mkSkus(c, n: 4, tag: 'a3-expand', qty: 2, price: 14);
  if (a3.length == 4) {
    final first = c.checkoutBag(lines: bagLines(a3.sublist(0, 2)), amount: 1);
    final second = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkoutBag(lines: bagLines(a3), amount: 1);
    });
    final hits = await parallel([first, second]);
    await overlapProbe(
      c: c,
      id: 'A3',
      poco: 'FA-A',
      lens: 'FA-A',
      payload: 'Future.wait subset → 50ms → superset expand',
      skus: a3,
      hits: hits,
      expected: '400 no 2.º — nunca 2.ª cs_',
      classeNova: false,
      regression: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A3',
      poco: 'FA-A',
      lens: 'FA-A',
      payload: 'Future.wait expand 50ms',
      why: 'mkSkus',
    );
  }

  // A4 2× bag idêntico
  await pause();
  await asFresh(c, 'a4');
  final a4 = await mkSkus(c, n: 3, tag: 'a4-ident', qty: 2, price: 9);
  if (a4.length == 3) {
    final lines = bagLines(a4);
    final hits = await parallel([
      c.checkoutBag(lines: lines, amount: 1),
      c.checkoutBag(lines: lines, amount: 1),
    ]);
    await overlapProbe(
      c: c,
      id: 'A4',
      poco: 'FA-A',
      lens: 'FA-A',
      payload: 'Future.wait 2× bag idêntico mesma ordem',
      skus: a4,
      hits: hits,
      expected: '1 cs_ reused mesmo sid',
      classeNova: false,
    );
  } else {
    skipProbe(
      c,
      id: 'A4',
      poco: 'FA-A',
      lens: 'FA-A',
      payload: 'Future.wait 2× bag idêntico',
      why: 'mkSkus',
    );
  }
}

/// FA-B Happy (≥3)
Future<void> faB(Rtdb c) async {
  c.wellsTried.add('FA-B');

  // B1 CPI saco happy amount catálogo
  await pause();
  await asFresh(c, 'bh');
  final b1 = await mkSkus(c, n: 3, tag: 'b1-happy', qty: 2, price: 12);
  if (b1.length == 3) {
    final catalogCents =
        (b1.fold<double>(0, (s, r) => s + r.price) * 100).round();
    final hit = await c.checkoutBag(lines: bagLines(b1), amount: 1);
    c.trackSession(hit);
    await Future<void>.delayed(const Duration(seconds: 2));
    final pack = await packHits(c, [hit], b1);
    storeOverlap(c, 'B1', b1, pack);
    final amt = hit.amountTotal;
    final sealedLow = hit.ok && amt != null && amt < catalogCents;
    final happy = hit.ok &&
        (hit.sessionId ?? '').startsWith('cs_') &&
        amt != null &&
        amt >= catalogCents;
    c.note('B1.happy', 'CPI saco amount catálogo', {
      'brief': hit.brief,
      'amt': amt,
      'catalog': catalogCents,
      'sid': hit.sessionId,
    }, lens: 'FA-B', well: 'FA-B');
    c.probe(
      id: 'B1',
      poco: 'FA-B',
      payload: 'CPI saco 3 linhas amount=1 (catálogo ${catalogCents}¢)',
      http: hit.brief,
      bd: {
        'amt': amt,
        'catalog_cents': catalogCents,
        'sid': hit.sessionId,
        'reused': hit.reused,
        'stored': pack['stored'],
      },
      verdict: (sealedLow || !happy) ? 'HOLD' : 'FAIL',
      lens: 'FA-B',
      classeNova: true,
    );
    if (sealedLow && !c.findings.any((f) => f['id'] == 'P0-B1')) {
      c.hold(
        id: 'P0-B1',
        lens: 'FA-B',
        severity: 'P0',
        title: 'CPI saco selou amount hostil abaixo do catálogo',
        actor: 'buyer JWT fresco',
        pre: '3 SKUs catálogo ${catalogCents}¢; body amount=1',
        repro: 'checkoutBag amount=1',
        expected: 'amount_total ≥ catálogo',
        obtained: {'amt': amt, 'brief': hit.brief},
      );
    } else if (happy) {
      c.block('B1-HAPPY', 'FA-B', 'saco happy amount catálogo', {
        'amt': amt,
        'catalog': catalogCents,
        'sid': hit.sessionId,
      });
    } else if (!c.findings.any((f) => f['id'] == 'P1-B1')) {
      c.hold(
        id: 'P1-B1',
        lens: 'FA-B',
        severity: 'P1',
        title: 'fail-closed partiu CPI saco feliz',
        actor: 'buyer JWT fresco',
        pre: '3 SKUs catálogo ${catalogCents}¢; body amount=1',
        repro: 'checkoutBag amount=1',
        expected: 'HTTP 200 + cs_ + amount ≥ catálogo',
        obtained: {'amt': amt, 'brief': hit.brief, 'ok': hit.ok},
      );
    }
  } else {
    skipProbe(
      c,
      id: 'B1',
      poco: 'FA-B',
      lens: 'FA-B',
      payload: 'CPI saco happy amount catálogo',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B3 shrink após open (antes de B2 pagar, para não herdar pago)
  await pause();
  await asFresh(c, 'bs');
  final b3 = await mkSkus(c, n: 4, tag: 'b3-shrink', qty: 2, price: 13);
  if (b3.length == 4) {
    final open = await c.checkoutBag(lines: bagLines(b3), amount: 1);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final shrink = await c.checkoutBag(lines: bagLines(b3.sublist(0, 2)), amount: 1);
    await overlapProbe(
      c: c,
      id: 'B3',
      poco: 'FA-B',
      lens: 'FA-B',
      payload: 'shrink após open: full bag → 300ms → subset 2',
      skus: b3,
      hits: [open, shrink],
      expected: '400 overlapping no shrink — nunca 2 creates',
      classeNova: false,
      regression: true,
    );
  } else {
    skipProbe(
      c,
      id: 'B3',
      poco: 'FA-B',
      lens: 'FA-B',
      payload: 'shrink após open',
      why: 'mkSkus',
    );
  }

  // B2 pago 4242 (e2e ou alojado) → pago / qty↓
  await runB2(c);
}

Future<void> runB2(Rtdb c) async {
  final cap = c.overlapCaptures['B1'];
  final sids = (cap?['sids'] as List?)?.map((e) => '$e').toList() ?? [];
  final urls = Map<String, String?>.from(
    (cap?['urls'] as Map?)?.map((k, v) => MapEntry('$k', v?.toString())) ?? {},
  );
  final skusRaw = (cap?['skus'] as List?) ?? [];
  final skus = [
    for (final r in skusRaw)
      if (r is Map)
        (
          oid: '${r['oid']}',
          pid: '${r['pid']}',
          price: (r['price'] as num?)?.toDouble() ?? 0,
        ),
  ];
  final winner = sids.where((s) => s.startsWith('cs_')).isEmpty
      ? null
      : sids.firstWhere((s) => s.startsWith('cs_'));
  Map<String, Object?> pay1 = {'skipped': true};
  Map<String, Object?> snap1 = {};
  var paidVia = 'none';
  var paidOk = false;

  if (winner != null) {
    pay1 = await c.payCheckout4242(winner, checkoutUrl: urls[winner]);
    paidVia = '${pay1['via']}';
    paidOk = pay1['paid'] == true;
    final pi1 = pay1['pi']?.toString();
    if (pi1 != null && pi1.startsWith('pi_') && skus.isNotEmpty) {
      final stl = await c.fase2Settle(
        pi: pi1,
        sessionId: winner,
        lines: bagLines(skus),
        bag: true,
      );
      pay1['fase2'] = stl.brief;
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    if (skus.isNotEmpty) snap1 = await c.ledgerSnap(skus);
  }

  Map<String, Object?> leftover = {};
  if (!paidOk) {
    final e2e = await c.payToPago(lens: 'FA-B', initialQty: 2);
    if (e2e != null) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final prod = await c.productRow(e2e.pid);
      final hub = await c.hubSku(e2e.pid);
      final ord = await c.orderRow(e2e.oid);
      paidOk = '${ord?['status']}'.toLowerCase() == 'pago' &&
          (numOf(prod?['quantity']) ?? -1) == 1;
      paidVia = 'e2e setup_paid_order';
      leftover = {
        'via': paidVia,
        'oid': e2e.oid,
        'pid': e2e.pid,
        'pi': e2e.pi,
        'order_status': ord?['status'],
        'qty': prod?['quantity'],
        'hub_n': hub.list.length,
        'hub_http': hub.status,
      };
      c.overlapCaptures['B2'] = leftover;
    }
  } else {
    leftover = {
      'via': paidVia,
      'winner': winner,
      'snap': snap1,
    };
    c.overlapCaptures['B2'] = leftover;
  }

  final orders1 = (snap1['orders'] as List?) ?? [];
  final products1 = (snap1['products'] as List?) ?? [];
  final hub1 = (snap1['hub'] as List?) ?? [];
  final pagos1 = orders1.where((o) {
    if (o is! Map) return false;
    return '${o['status']}'.toLowerCase() == 'pago';
  }).length;
  final leftoverOk = products1.isNotEmpty &&
      products1.every((p) {
        if (p is! Map) return false;
        return (numOf(p['qty']) ?? -99) == 1;
      });
  if (leftover.containsKey('oid')) {
    // e2e path already set paidOk
  } else {
    paidOk = paidOk && pagos1 == skus.length && leftoverOk;
  }

  c.probe(
    id: 'B2',
    poco: 'FA-B',
    payload: 'pago 4242 (e2e ou alojado) → pago / qty↓',
    http: {'pay': pay1, 'winner': winner, 'via': paidVia},
    bd: {
      'snap': snap1,
      'leftover_e2e': leftover,
      'pagos': pagos1,
      'leftover_ok': leftoverOk,
      'hub': hub1,
    },
    verdict: paidOk ? 'FAIL' : 'HOLD',
    lens: 'FA-B',
    classeNova: true,
  );
  if (paidOk) {
    c.block('B2-PAID', 'FA-B', 'pago 4242 coerente qty↓', leftover);
  } else if (!c.findings.any((f) => f['id'] == 'P1-B2')) {
    c.hold(
      id: 'P1-B2',
      lens: 'FA-B',
      severity: 'P1',
      title: 'pago 4242 / leftover Hub incoerente',
      actor: 'buyer JWT + Stripe TEST 4242',
      pre: 'B1 saco qty=2 ou e2e setup_paid_order',
      repro: 'payCheckout4242 / setup_paid_order; ledgerSnap Hub',
      expected: 'pago; qty leftover=1',
      obtained: {'pay1': pay1, 'snap': snap1, 'leftover': leftover},
    );
  }
}

/// FA-C Caixa (≥3)
Future<void> faC(Rtdb c) async {
  c.wellsTried.add('FA-C');

  // C1 underpay body → amount servidor
  await pause();
  await asFresh(c, 'cu');
  final c1sku = await mkSkus(c, n: 1, tag: 'c1-under', qty: 2, price: 18);
  HttpHit? underHit;
  if (c1sku.isNotEmpty) {
    underHit = await c.checkout(
      orderId: c1sku.first.oid,
      productId: c1sku.first.pid,
      amount: 0,
      extra: {
        'total_eur': '0.00',
        'item_price': 0.01,
        'protection_fee': 0,
        'shipping': 0,
        'server_amount_cents': 1,
        'amount_total': 1,
        'line_total_cents': 1,
      },
      shipping: 'mao',
    );
    c.trackSession(underHit);
  }
  final amt = underHit?.amountTotal;
  final under = underHit != null && underHit.ok && amt != null && amt < 1800;
  c.probe(
    id: 'C1',
    poco: 'FA-C',
    payload: 'body total_eur=0 item_price=0.01 amount=0 (SKU 18€)',
    http: underHit?.brief,
    bd: {'amt': amt, 'catalog_cents': 1800},
    verdict: under ? 'HOLD' : 'FAIL',
    lens: 'FA-C',
    classeNova: true,
  );
  if (under) {
    c.hold(
      id: 'P0-C1',
      lens: 'FA-C',
      severity: 'P0',
      title: 'body hostil baixou amount_total abaixo do catálogo',
      actor: 'buyer JWT fresco',
      pre: 'SKU 18€',
      repro: 'CPI extras total_eur/item_price',
      expected: 'amount ≈ catálogo (selo); extras ignorados',
      obtained: {'amt': amt, 'hit': underHit?.brief},
    );
  } else {
    c.block('C1-UNDERPAY', 'FA-C', 'underpay ignorado; amount catálogo', {
      'amt': amt,
    });
  }

  // C2 disjuntos 2 bags → 2 cs_ OK
  await pause();
  await asFresh(c, 'cd');
  final c2a = await mkSkus(c, n: 2, tag: 'c2-disj-a', qty: 2, price: 7);
  final c2b = await mkSkus(c, n: 2, tag: 'c2-disj-b', qty: 2, price: 8);
  if (c2a.length == 2 && c2b.length == 2) {
    final hits = await parallel([
      c.checkoutBag(lines: bagLines(c2a), amount: 1),
      c.checkoutBag(lines: bagLines(c2b), amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    final sids = openCs(hits);
    final briefs = hits.map((h) => h.brief).toList();
    final storedA = [
      for (final r in c2a)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final storedB = [
      for (final r in c2b)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final shared = storedA
        .toSet()
        .intersection(storedB.toSet())
        .where((s) => s.startsWith('cs_'));
    final sameSidOnBothBags = shared.isNotEmpty;
    c.note('C2.disjoint', '2 bags disjuntos', {
      'briefs': briefs,
      'sids': sids.toList(),
      'storedA': storedA,
      'storedB': storedB,
    }, lens: 'FA-C', well: 'FA-C');
    c.probe(
      id: 'C2',
      poco: 'FA-C',
      payload: 'Future.wait 2 bags disjuntos mesmo buyer',
      http: briefs,
      bd: {
        'sids': sids.toList(),
        'storedA': storedA,
        'storedB': storedB,
        'shared': shared.toList(),
      },
      verdict: sameSidOnBothBags ? 'HOLD' : 'FAIL',
      lens: 'FA-C',
      classeNova: true,
    );
    if (sameSidOnBothBags) {
      c.hold(
        id: 'P2-C2',
        lens: 'FA-C',
        severity: 'P2',
        title: 'bags disjuntos partilharam a mesma cs_',
        actor: 'buyer JWT fresco',
        pre: '2 bags sem linhas em comum',
        repro: 'Future.wait checkoutBag A ∥ checkoutBag B',
        expected: '2 cs_ OK (linhas sem overlap)',
        obtained: {
          'sids': sids.toList(),
          'storedA': storedA,
          'storedB': storedB,
        },
      );
    } else {
      c.block('C2-DISJOINT', 'FA-C', 'bags disjuntos: 2 cs_ (ou mutex serializa)', {
        'sids': sids.toList(),
        'status': hits.map((h) => h.status).toList(),
      });
    }
  } else {
    skipProbe(
      c,
      id: 'C2',
      poco: 'FA-C',
      lens: 'FA-C',
      payload: '2 bags disjuntos',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // C3 Hub n após B2 (1 sítio)
  await runC3(c);
}

Future<void> runC3(Rtdb c) async {
  final b2 = c.overlapCaptures['B2'] ?? {};
  Map<String, Object?> hubObs = {};
  var ok = false;

  if (b2['pid'] != null) {
    final pid = '${b2['pid']}';
    final prod = await c.productRow(pid);
    final hub = await c.hubSku(pid);
    final ord = await c.orderRow('${b2['oid']}');
    hubObs = {
      'pid': pid,
      'qty': prod?['quantity'],
      'sold': prod?['is_sold'],
      'hub_http': hub.status,
      'hub_n': hub.list.length,
      'order_status': ord?['status'],
      'via': b2['via'],
    };
    ok = '${ord?['status']}'.toLowerCase() == 'pago' &&
        (numOf(prod?['quantity']) ?? -1) == 1 &&
        hub.list.length >= 1;
  } else {
    final snap = b2['snap'];
    if (snap is Map) {
      final products = (snap['products'] as List?) ?? [];
      final hub = (snap['hub'] as List?) ?? [];
      final orders = (snap['orders'] as List?) ?? [];
      hubObs = {'snap': snap};
      final leftover = products.isNotEmpty &&
          products.every((p) {
            if (p is! Map) return false;
            return (numOf(p['qty']) ?? -99) == 1;
          });
      final hubLists = hub.isNotEmpty &&
          hub.every((h) {
            if (h is! Map) return false;
            return (numOf(h['n']) ?? 0) >= 1;
          });
      final pagos = orders.where((o) {
        if (o is! Map) return false;
        return '${o['status']}'.toLowerCase() == 'pago';
      }).isNotEmpty;
      ok = leftover && hubLists && pagos;
    }
  }

  c.probe(
    id: 'C3',
    poco: 'FA-C',
    payload: 'Hub n após B2 (1 sítio)',
    http: {'b2_via': b2['via']},
    bd: hubObs,
    verdict: ok ? 'FAIL' : 'HOLD',
    lens: 'FA-C',
    classeNova: true,
  );
  if (ok) {
    c.block('C3-HUB', 'FA-C', 'Hub leftover após pago', hubObs);
  } else if (!c.findings.any((f) => f['id'] == 'P1-C3')) {
    c.hold(
      id: 'P1-C3',
      lens: 'FA-C',
      severity: 'P1',
      title: 'Hub n após pago incoerente com leftover',
      actor: 'observação Hub público',
      pre: 'B2 pago qty 2→1',
      repro: 'hub_products_public após B2',
      expected: 'Hub n≥1 leftover; qty=1',
      obtained: hubObs,
    );
  }
}
