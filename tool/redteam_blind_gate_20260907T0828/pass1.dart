/// RED TEAM CEGO GATE pass1 — bag∥single may_create (Fase 4).
/// Matriz A1–A6 · B1–B3 · C1–C3. Sem correções. Stripe TEST 4242.
import 'dart:io';

import '_rtgate.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('GATE pass1 staging=${c.url} prefix=$prefix');
  stdout.writeln(
    c.stripeTestKey == null
        ? 'WARN no sk_test_ — pay via pk/payment_pages + settle'
        : 'sk_test_ present — native retrieve+confirm',
  );
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.ensureBuyer3();
  await c.restoreSeller1Published();
  c.buyerId = c.buyer3Id;
  c.buyerJwt = c.buyer3Jwt;
  c.note('actors', 'ids', {
    'b': c.buyerId,
    's': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
    'b3': c.buyer3Id,
    'seller_hub': (await c.profile(c.sellerId!))?['hub_published'],
    'sk': c.stripeTestKey != null,
  });
  final wallets0 = await c.wallets();
  c.note('wallet.pre', 'baseline', wallets0, lens: 'G-C', well: 'G-C');

  await gateA(c);
  await gateB(c);
  await gateC(c, wallets0);

  final wallets1 = await c.wallets();
  c.note('wallet.post', 'após probes', {
    'pre': wallets0,
    'post': wallets1,
  }, lens: 'G-C', well: 'G-C');

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
    'auditor': 'REDTEAM_BLIND_GATE_BAG_SINGLE_v1',
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
    'lines': bagLines(skus),
  };
}

void maybeHoldDual(Rtdb c, String id, Map<String, Object?> pack) {
  if (pack['dual_create'] != true) return;
  if (c.findings.any((f) => f['id'] == 'P1-1')) return;
  c.hold(
    id: 'P1-1',
    lens: 'G-A',
    severity: 'P1',
    title:
        'Saco e artigo avulso ao mesmo tempo: duas Sessions (gate may_create não actuou)',
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
      '$id-GATE',
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

/// G-A Bag∥single (gate) ≥6
Future<void> gateA(Rtdb c) async {
  c.wellsTried.add('G-A');

  // A1 bag ABCDE ∥ single C t=0
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
      poco: 'G-A',
      lens: 'G-A',
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
      poco: 'G-A',
      lens: 'G-A',
      payload: 'Future.wait bag ABCDE ∥ single C t=0',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // A2 bag first →50ms→ single C
  await pause();
  await asFresh(c, 'a2');
  final a2 = await mkSkus(c, n: 5, tag: 'a2-bag-50-c', qty: 2, price: 8);
  if (a2.length == 5) {
    final midC = a2[2];
    final bag = c.checkoutBag(lines: bagLines(a2), amount: 1);
    final single = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkout(orderId: midC.oid, productId: midC.pid, amount: 1);
    });
    final hits = await parallel([bag, single]);
    await overlapProbe(
      c: c,
      id: 'A2',
      poco: 'G-A',
      lens: 'G-A',
      payload: 'Future.wait bag first → 50ms → single C (fresco)',
      skus: a2,
      hits: hits,
      expected: '≤1 cs_ útil; never 2 creates reused=false',
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A2',
      poco: 'G-A',
      lens: 'G-A',
      payload: 'Future.wait bag first → 50ms → single C',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // A3 single C first →50ms→ bag
  await pause();
  await asFresh(c, 'a3');
  final a3 = await mkSkus(c, n: 5, tag: 'a3-single-50-bag', qty: 2, price: 8);
  if (a3.length == 5) {
    final midC = a3[2];
    final single = c.checkout(orderId: midC.oid, productId: midC.pid, amount: 1);
    final bag = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkoutBag(lines: bagLines(a3), amount: 1);
    });
    final hits = await parallel([single, bag]);
    await overlapProbe(
      c: c,
      id: 'A3',
      poco: 'G-A',
      lens: 'G-A',
      payload: 'Future.wait single C first → 50ms → bag ABCDE (fresco)',
      skus: a3,
      hits: hits,
      expected: '≤1 cs_ útil; bag reuse da Session avulsa',
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A3',
      poco: 'G-A',
      lens: 'G-A',
      payload: 'Future.wait single C first → 50ms → bag',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // A4 bag ABC ∥ single B t=0
  await pause();
  await asFresh(c, 'a4');
  final a4 = await mkSkus(c, n: 3, tag: 'a4-abc-b', qty: 2, price: 9);
  if (a4.length == 3) {
    final midB = a4[1];
    final hits = await parallel([
      c.checkoutBag(lines: bagLines(a4), amount: 1),
      c.checkout(orderId: midB.oid, productId: midB.pid, amount: 1),
    ]);
    await overlapProbe(
      c: c,
      id: 'A4',
      poco: 'G-A',
      lens: 'G-A',
      payload: 'Future.wait bag ABC ∥ single B (meio) t=0 (fresco)',
      skus: a4,
      hits: hits,
      expected: '≤1 cs_ útil',
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A4',
      poco: 'G-A',
      lens: 'G-A',
      payload: 'Future.wait bag ABC ∥ single B t=0',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // A5 bag∥single∥bag @200 ms
  await pause();
  await asFresh(c, 'a5');
  final a5 = await mkSkus(c, n: 3, tag: 'a5-bsb-200', qty: 2, price: 11);
  if (a5.length == 3) {
    final three = bagLines(a5);
    final mid = a5[1];
    final bag1 = c.checkoutBag(lines: three, amount: 1);
    final single = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return c.checkout(orderId: mid.oid, productId: mid.pid, amount: 1);
    });
    final bag2 = c.checkoutBag(lines: three, amount: 1);
    final hits = await parallel([bag1, single, bag2]);
    await overlapProbe(
      c: c,
      id: 'A5',
      poco: 'G-A',
      lens: 'G-A',
      payload: 'Future.wait bag ∥ single +200ms ∥ bag (fresco)',
      skus: a5,
      hits: hits,
      expected: '≤1 create; extras 400 overlapping ou reused mesmo sid',
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A5',
      poco: 'G-A',
      lens: 'G-A',
      payload: 'Future.wait bag∥single∥bag @200ms',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // A6 bag de 2 first →200ms→ single
  await pause();
  await asFresh(c, 'a6');
  final a6 = await mkSkus(c, n: 2, tag: 'a6-2-1-200', qty: 2, price: 10);
  if (a6.length == 2) {
    final one = a6[0];
    final bag = c.checkoutBag(lines: bagLines(a6), amount: 1);
    final single = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return c.checkout(orderId: one.oid, productId: one.pid, amount: 1);
    });
    final hits = await parallel([bag, single]);
    await overlapProbe(
      c: c,
      id: 'A6',
      poco: 'G-A',
      lens: 'G-A',
      payload: 'Future.wait bag de 2 first → 200ms → single (fresco)',
      skus: a6,
      hits: hits,
      expected: '≤1 cs_ útil',
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A6',
      poco: 'G-A',
      lens: 'G-A',
      payload: 'Future.wait bag de 2 first → 200ms → single',
      why: 'mkSkus',
      classeNova: true,
    );
  }
}

/// G-B Regressão ≥3
Future<void> gateB(Rtdb c) async {
  c.wellsTried.add('G-B');
  c.buyerId = c.buyer3Id;
  c.buyerJwt = c.buyer3Jwt;

  // B1 6∥4
  await pause();
  final b1 = await mkSkus(c, n: 6, tag: 'b1-6x4', qty: 2, price: 9);
  if (b1.length == 6) {
    final hits = await parallel([
      c.checkoutBag(lines: bagLines(b1), amount: 1),
      c.checkoutBag(lines: bagLines(b1.sublist(1, 5)), amount: 1),
    ]);
    await overlapProbe(
      c: c,
      id: 'B1',
      poco: 'G-B',
      lens: 'G-B',
      payload: 'Future.wait bag 6∥4 t=0 regressão ≤1',
      skus: b1,
      hits: hits,
      expected: '≤1 / 400 overlapping — nunca 2 creates',
      classeNova: false,
      regression: true,
    );
  } else {
    skipProbe(
      c,
      id: 'B1',
      poco: 'G-B',
      lens: 'G-B',
      payload: 'Future.wait bag 6∥4 t=0',
      why: 'mkSkus',
    );
  }

  // B2 expand subset→50ms→superset
  await pause();
  final b2 = await mkSkus(c, n: 4, tag: 'b2-expand', qty: 2, price: 14);
  if (b2.length == 4) {
    final first = c.checkoutBag(lines: bagLines(b2.sublist(0, 2)), amount: 1);
    final second = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkoutBag(lines: bagLines(b2), amount: 1);
    });
    final hits = await parallel([first, second]);
    await overlapProbe(
      c: c,
      id: 'B2',
      poco: 'G-B',
      lens: 'G-B',
      payload: 'Future.wait subset → 50ms → superset expand',
      skus: b2,
      hits: hits,
      expected: '400 no 2.º — nunca 2.ª cs_',
      classeNova: false,
      regression: true,
    );
  } else {
    skipProbe(
      c,
      id: 'B2',
      poco: 'G-B',
      lens: 'G-B',
      payload: 'Future.wait expand 50ms',
      why: 'mkSkus',
    );
  }

  // B3 2× bag idêntico
  await pause();
  final b3 = await mkSkus(c, n: 3, tag: 'b3-ident', qty: 2, price: 9);
  if (b3.length == 3) {
    final lines = bagLines(b3);
    final hits = await parallel([
      c.checkoutBag(lines: lines, amount: 1),
      c.checkoutBag(lines: lines, amount: 1),
    ]);
    await overlapProbe(
      c: c,
      id: 'B3',
      poco: 'G-B',
      lens: 'G-B',
      payload: 'Future.wait 2× bag idêntico mesma ordem',
      skus: b3,
      hits: hits,
      expected: '1 cs_ reused mesmo sid',
      classeNova: false,
    );
  } else {
    skipProbe(
      c,
      id: 'B3',
      poco: 'G-B',
      lens: 'G-B',
      payload: 'Future.wait 2× bag idêntico',
      why: 'mkSkus',
    );
  }
}

Map<String, Object?>? pickPayTarget(Rtdb c) {
  for (final id in ['A1', 'A2', 'A3', 'A4']) {
    final cap = c.overlapCaptures[id];
    if (cap == null) continue;
    if (cap['dual_create'] == true) {
      final sids = (cap['sids'] as List?)?.map((e) => '$e').toList() ?? [];
      final distinct = sids.where((s) => s.startsWith('cs_')).toSet();
      if (distinct.length >= 2) {
        return {'from': id, ...cap, 'sids': distinct.toList()};
      }
    }
  }
  for (final id in ['A1', 'A2', 'A3', 'A4', 'A5', 'A6']) {
    final cap = c.overlapCaptures[id];
    if (cap == null) continue;
    final sids = (cap['sids'] as List?)
            ?.map((e) => '$e')
            .where((s) => s.startsWith('cs_'))
            .toList() ??
        [];
    if (sids.isNotEmpty) {
      return {'from': id, ...cap, 'sids': sids.toSet().toList()};
    }
  }
  return null;
}

String? ledgerWinnerSid(Map<String, Object?> cap) {
  final stored = (cap['stored'] as List?)?.map((e) => '$e').toList() ?? [];
  final counts = <String, int>{};
  for (final s in stored) {
    if (s.startsWith('cs_')) counts[s] = (counts[s] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted.first.key;
}

/// G-C Caixa ≥3
Future<void> gateC(Rtdb c, Map<String, num> wallets0) async {
  c.wellsTried.add('G-C');
  final dual = pickPayTarget(c);
  c.note('C.pick', 'overlap escolhido para pagar', dual,
      lens: 'G-C', well: 'G-C');
  await dumpJson('${outDir()}/pay_urls.json', {
    'picked': dual?['from'],
    'sids': dual?['sids'],
    'urls': dual?['urls'],
    'dual_create': dual?['dual_create'],
    'status': dual?['status'],
    'reused': dual?['reused'],
    'skus': dual?['skus'],
    'stored': dual?['stored'],
  });

  final allSids = (dual?['sids'] as List?)?.map((e) => '$e').toList() ?? [];
  final urls = Map<String, String?>.from(
    (dual?['urls'] as Map?)?.map((k, v) => MapEntry('$k', v?.toString())) ?? {},
  );
  final skusRaw = (dual?['skus'] as List?) ?? [];
  final skus = [
    for (final r in skusRaw)
      if (r is Map)
        (
          oid: '${r['oid']}',
          pid: '${r['pid']}',
          price: (r['price'] as num?)?.toDouble() ?? 0,
        ),
  ];
  final lines = [
    for (final r in skus) {'order_id': r.oid, 'product_id': r.pid},
  ];
  final winner = ledgerWinnerSid(dual ?? {}) ??
      (allSids.isNotEmpty ? allSids.first : null);
  final orphan = allSids.where((s) => s != winner).toList();
  final twoOpen = allSids.length >= 2;

  Map<String, Object?> pay1 = {'skipped': true};
  Map<String, Object?> pay2 = {'skipped': true};
  Map<String, Object?> snap1 = {};
  Map<String, Object?> snap2 = {};

  if (skus.isNotEmpty) {
    c.note('C.ledger.pre', 'antes de pagar', await c.ledgerSnap(skus),
        lens: 'G-C', well: 'G-C');
  }

  // C1 pagar link útil + Hub leftover
  if (winner != null && winner.startsWith('cs_')) {
    c.note('C1.pay.useful', 'pagar cs_ útil 4242', winner,
        lens: 'G-C', well: 'G-C');
    pay1 = await c.payCheckout4242(winner, checkoutUrl: urls[winner]);
    final pi1 = pay1['pi']?.toString();
    if (pi1 != null && pi1.startsWith('pi_') && lines.isNotEmpty) {
      final stl = await c.fase2Settle(
        pi: pi1,
        sessionId: winner,
        lines: lines,
        bag: true,
      );
      pay1['fase2'] = stl.brief;
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    snap1 = await c.ledgerSnap(skus);
  }

  final paid1 = pay1['paid'] == true;
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
        final q = numOf(p['qty']) ?? -99;
        return q == 1;
      });
  final hubLists = hub1.every((h) {
    if (h is! Map) return false;
    return (numOf(h['n']) ?? 0) >= 1;
  });

  var c1ok = paid1 && pagos1 == skus.length && leftoverOk;
  if (!paid1) {
    final e2e = await c.payToPago(lens: 'G-C', initialQty: 2);
    Map<String, Object?> leftover = {};
    var leftoverPago = false;
    if (e2e != null) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final prod = await c.productRow(e2e.pid);
      final hub = await c.hubSku(e2e.pid);
      final ord = await c.orderRow(e2e.oid);
      leftoverPago = '${ord?['status']}'.toLowerCase() == 'pago' &&
          (numOf(prod?['quantity']) ?? -1) == 1;
      leftover = {
        'via': 'e2e setup_paid_order fallback',
        'oid': e2e.oid,
        'pid': e2e.pid,
        'pi': e2e.pi,
        'order_status': ord?['status'],
        'qty': prod?['quantity'],
        'hub_n': hub.list.length,
      };
      c1ok = leftoverPago;
    }
    c.probe(
      id: 'C1',
      poco: 'G-C',
      payload:
          'pago 4242 do link útil + Hub leftover (fallback e2e se API 4242 falhou)',
      http: {'pay_useful': pay1, 'winner': winner, 'from': dual?['from']},
      bd: {
        'snap': snap1,
        'leftover_e2e': leftover,
        'pagos': pagos1,
        'leftover_ok': leftoverOk,
        'hub_lists': hubLists,
      },
      verdict: c1ok ? 'FAIL' : 'HOLD',
      lens: 'G-C',
      classeNova: true,
    );
    if (!c1ok && !c.findings.any((f) => f['id'] == 'P1-C1')) {
      c.hold(
        id: 'P1-C1',
        lens: 'G-C',
        severity: 'P1',
        title: 'pago 4242 do link útil / leftover Hub incoerente',
        actor: 'buyer JWT + Stripe TEST 4242',
        pre: 'overlap ${dual?['from']} qty=2',
        repro: 'payCheckout4242 winner; ledgerSnap Hub',
        expected: 'pago; qty leftover=1; Hub lista resto',
        obtained: {'pay1': pay1, 'snap': snap1, 'leftover': leftover},
      );
    }
  } else {
    c.probe(
      id: 'C1',
      poco: 'G-C',
      payload: 'pago 4242 do link útil (${dual?['from']}) + Hub leftover qty 2→1',
      http: pay1,
      bd: {
        'winner': winner,
        'pagos': pagos1,
        'leftover_ok': leftoverOk,
        'hub_lists': hubLists,
        'orders': orders1,
        'products': products1,
        'hub': hub1,
      },
      verdict: c1ok ? 'FAIL' : 'HOLD',
      lens: 'G-C',
      classeNova: true,
    );
    if (!c1ok && !c.findings.any((f) => f['id'] == 'P1-C1')) {
      c.hold(
        id: 'P1-C1',
        lens: 'G-C',
        severity: 'P1',
        title: 'link útil pago mas leftover Hub/stock incoerente',
        actor: 'buyer JWT + Stripe TEST 4242',
        pre: 'overlap ${dual?['from']} qty=2',
        repro: 'payCheckout4242 winner; ledgerSnap',
        expected: 'todas linhas pago; qty=1 leftover; Hub n≥1',
        obtained: snap1,
      );
    }
  }

  // C2 se dual: pagar 2.ª (caça P0)
  if (twoOpen && orphan.isNotEmpty) {
    final sid2 = orphan.first;
    c.note('C2.pay.second', 'pagar 2.ª cs_ 4242 (caça P0)', sid2,
        lens: 'G-C', well: 'G-C');
    pay2 = await c.payCheckout4242(sid2, checkoutUrl: urls[sid2]);
    final pi2 = pay2['pi']?.toString();
    if (pi2 != null && pi2.startsWith('pi_') && lines.isNotEmpty) {
      final stl = await c.fase2Settle(
        pi: pi2,
        sessionId: sid2,
        lines: lines,
        bag: true,
      );
      pay2['fase2'] = stl.brief;
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    snap2 = await c.ledgerSnap(skus);
    final paid2 = pay2['paid'] == true;
    final orders2 = (snap2['orders'] as List?) ?? [];
    final products2 = (snap2['products'] as List?) ?? [];
    final pagos2 = orders2.where((o) {
      if (o is! Map) return false;
      return '${o['status']}'.toLowerCase() == 'pago';
    }).length;
    var oversold = false;
    for (final p in products2) {
      if (p is! Map) continue;
      final q = numOf(p['qty']) ?? 0;
      if (q < 0) oversold = true;
    }
    final p0 = paid1 && paid2 && (oversold || pagos2 >= skus.length);
    c.probe(
      id: 'C2',
      poco: 'G-C',
      payload: 'se dual: pagar 2.ª cs_ 4242 (caça P0) from ${dual?['from']}',
      http: pay2,
      bd: {
        'sid2': sid2,
        'paid1': paid1,
        'paid2': paid2,
        'pagos': pagos2,
        'oversold': oversold,
        'products': products2,
      },
      verdict: p0 ? 'HOLD' : 'FAIL',
      lens: 'G-C',
      classeNova: true,
    );
    if (p0) {
      c.findings.removeWhere((f) => f['id'] == 'P1-1');
      c.hold(
        id: 'P0-1',
        lens: 'G-C',
        severity: 'P0',
        title:
            'Duas Sessions bag∥single capturadas + stock/caixa inconsistente',
        actor: 'buyer JWT + Stripe TEST 4242',
        pre: 'overlap ${dual?['from']} 2 cs_ qty=2',
        repro: 'payCheckout4242 winner; payCheckout4242 orphan; ledgerSnap',
        expected: '2.ª captura falha; leftover qty=1; sem oversell',
        obtained: {
          'pay1': pay1,
          'pay2': pay2,
          'pagos': pagos2,
          'products': products2,
        },
      );
    } else if (paid2 && !c.findings.any((f) => f['id'] == 'P1-1')) {
      c.hold(
        id: 'P1-1',
        lens: 'G-C',
        severity: 'P1',
        title: '2.ª Session bag∥single pagável (sem 2.ª captura P0)',
        actor: 'buyer JWT + Stripe TEST 4242',
        pre: 'overlap ${dual?['from']}',
        repro: 'payCheckout4242 2.ª',
        expected: '2.ª captura falha',
        obtained: pay2,
      );
    }
  } else {
    c.probe(
      id: 'C2',
      poco: 'G-C',
      payload:
          'se dual: pagar 2.ª — só ${allSids.length} cs_; sem 2.ª captura a caçar',
      http: {
        'sids': allSids,
        'from': dual?['from'],
        'status': dual?['status'],
        'overlap_400': dual?['overlap_400'],
        'reused': dual?['reused'],
        'creates': dual?['creates'],
      },
      bd: {'dual_create': dual?['dual_create']},
      verdict: 'FAIL',
      lens: 'G-C',
      classeNova: true,
    );
  }

  // C3 2 buyers qty=1 sem oversell
  await pause();
  final pid = await c.createProduct(title: '$prefix-c3-last', qty: 1, price: 11);
  if (pid != null) {
    final o1 = await c.insertOrder(
      productId: pid,
      price: 11,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    final o2 = await c.insertOrder(
      productId: pid,
      price: 11,
      buyer: c.buyer2Id,
      jwt: c.buyer2Jwt,
    );
    if (o1 != null && o2 != null) {
      final hits = await parallel([
        c.checkout(
          orderId: o1,
          productId: pid,
          amount: 1,
          jwt: c.buyerJwt,
          buyer: c.buyerId,
        ),
        c.checkout(
          orderId: o2,
          productId: pid,
          amount: 1,
          jwt: c.buyer2Jwt,
          buyer: c.buyer2Id,
        ),
      ]);
      for (final h in hits) {
        c.trackSession(h);
      }
      final ok = hits.where((h) => h.ok).length;
      final briefs = hits.map((h) => h.brief).toList();
      final prod = await c.productRow(pid);
      final dualLast = ok >= 2;
      c.probe(
        id: 'C3',
        poco: 'G-C',
        payload: 'Future.wait 2 buyers CPI última unidade qty=1',
        http: briefs,
        bd: {
          'ok': ok,
          'o1': o1,
          'o2': o2,
          'qty': prod?['quantity'],
        },
        verdict: dualLast ? 'HOLD' : 'FAIL',
        lens: 'G-C',
        classeNova: false,
      );
      if (dualLast) {
        c.hold(
          id: 'P0-C3',
          lens: 'G-C',
          severity: 'P0',
          title: '2 buyers Session na última unidade',
          actor: 'buyer + buyer2 JWT',
          pre: 'quantity=1; 2 orders',
          repro: 'Future.wait 2× CPI',
          expected: '1 Session + 1 stock block',
          obtained: {'ok': ok, 'briefs': briefs, 'qty': prod?['quantity']},
        );
      } else {
        c.block('C3-LAST', 'G-C', 'última unidade ≤1 Session', {
          'ok': ok,
          'briefs': briefs,
        });
      }
    } else {
      c.probe(
        id: 'C3',
        poco: 'G-C',
        payload: '2 buyers qty=1 (insert 2.º)',
        http: {'o1': o1, 'o2': o2},
        bd: {'o1': o1, 'o2': o2},
        verdict: o2 == null ? 'FAIL' : 'HOLD',
        lens: 'G-C',
        classeNova: false,
      );
      if (o2 != null) {
        c.hold(
          id: 'P0-C3',
          lens: 'G-C',
          severity: 'P0',
          title: '2.º buyer inseriu hold na última unidade',
          actor: 'buyer + buyer2 JWT',
          pre: 'quantity=1',
          repro: '2× insertOrder',
          expected: '2.º insert 400 stock',
          obtained: {'o1': o1, 'o2': o2},
        );
      } else {
        c.block('C3-LAST', 'G-C', '2.º insert bloqueado no last-unit', {
          'o1': o1,
          'o2': o2,
        });
      }
    }
  } else {
    skipProbe(
      c,
      id: 'C3',
      poco: 'G-C',
      lens: 'G-C',
      payload: '2 buyers qty=1',
      why: 'createProduct',
    );
  }

  c.overlapCaptures['PAY'] = {
    'from': dual?['from'],
    'sids': allSids,
    'winner': winner,
    'orphan': orphan,
    'paid1': paid1,
    'paid2': pay2['paid'] == true,
    'pay1': pay1,
    'pay2': pay2,
    'two_open': twoOpen,
  };
}
