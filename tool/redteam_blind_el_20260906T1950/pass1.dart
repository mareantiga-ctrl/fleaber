/// RED TEAM CEGO EL pass1 — saco fail-closed overlap/expand POS_OPEN_GATE reteste.
/// Matriz A1–A4 · B1–B7 · C1–C4 · D1–D3. Sem correções.
/// Oráculo overlap: 2× HTTP 200 + 2 cs_ distintas reused=false = P1 FAIL.
import 'dart:io';

import '_rtel.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('EL pass1 staging=${c.url} prefix=$prefix');
  if (c.stripeTestKey == null) {
    stdout.writeln('WARN no sk_test_ — oráculo via checkout URL + settle');
  }
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.ensureBuyer3();
  final liveOpsBuyerId = envRequire(loadEnv(), 'LIVE_OPS_TEST_BUYER_ID');
  c.buyerId = c.buyer3Id;
  c.buyerJwt = c.buyer3Jwt;
  c.note('actors', 'ids', {
    'b': c.buyerId,
    's': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
    'b3': c.buyer3Id,
    'liveOpsBuyer': liveOpsBuyerId,
    'cpi_actor': 'buyer3-rtel',
  });
  final wallets0 = await c.wallets();
  c.note('EL8.wallet.pre', 'baseline', wallets0, lens: 'EL8', well: 'EL-D');

  await elAIdentico(c);
  await elBOverlapFailClosed(c);
  await elCDisjuntosPreco(c);
  await elDCaixaDenylist(c, wallets0);

  final wallets1 = await c.wallets();
  c.note('EL8.wallet.post', 'após probes', {
    'pre': wallets0,
    'post': wallets1,
  }, lens: 'EL8', well: 'EL-D');

  await c.dumpAll('pass1_findings.json');
  final races = c.probes
      .where((p) => '${p['payload']}'.contains('Future.wait'))
      .map((p) => p['probe_id'])
      .toList();
  final novas = c.probes
      .where((p) => p['classe_nova'] == 'SIM')
      .map((p) => p['probe_id'])
      .toList();
  await dumpJson('${outDir()}/probes.json', {
    'stamp': stamp,
    'prefix': prefix,
    'probes': c.probes,
    'n': c.probes.length,
    'races': races,
    'classes_novas': novas,
    'findings': c.findings.length,
  });
  stdout.writeln(
    'DONE probes=${c.probes.length} findings=${c.findings.length} '
    'blocked=${c.blocked.length} skip=${c.skipped.length} '
    'races=${races.length} classe_nova=${novas.length} '
    'lenses=${c.lensesHit.toList()..sort()} wells=${c.wellsTried.toList()..sort()}',
  );
}

Future<void> pause([int ms = 450]) =>
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
  int qty = 3,
  double price = 12,
  String? buyer,
  String? jwt,
  String? seller,
  String shipping = 'entrega em mão',
  String payment = 'Pagamento na app',
}) async {
  final out = <({String oid, String pid, double price})>[];
  for (var i = 0; i < n; i++) {
    final p = price + i;
    final pid = await c.createProduct(
      title: '$prefix-$tag-$i',
      qty: qty,
      price: p,
      seller: seller,
    );
    if (pid == null) continue;
    final oid = await c.insertOrder(
      productId: pid,
      price: p,
      buyer: buyer,
      jwt: jwt ?? c.buyerJwt,
      seller: seller,
      shipping: shipping,
      payment: payment,
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

bool contention(HttpHit h) {
  final raw = h.body.toLowerCase();
  return !h.ok &&
      (raw.contains('contention') ||
          raw.contains('claim busy') ||
          raw.contains('lock bag') ||
          raw.contains('advisory') ||
          raw.contains('overlapping') ||
          raw.contains('try again') ||
          h.status == 409);
}

bool overlapping400(HttpHit h) {
  final raw = h.body.toLowerCase();
  return h.status == 400 && raw.contains('overlapping bag session');
}

/// GATE EL: 2× HTTP 200 + 2 cs_ distintas (reused=false no 2.º ou ambos) = dual create.
bool dualCsCreate(List<HttpHit> hits) {
  final created = hits
      .where((h) =>
          h.ok &&
          (h.sessionId ?? '').startsWith('cs_') &&
          h.reused != true)
      .map((h) => h.sessionId!)
      .toSet();
  if (created.length >= 2) return true;
  final sids = hits
      .where((h) => h.ok && (h.sessionId ?? '').startsWith('cs_'))
      .map((h) => h.sessionId!)
      .toSet();
  return sids.length >= 2;
}

Future<(int, List<Map<String, Object?>>)> openPayableCount(
  Rtdb c,
  Iterable<String> sids, {
  Map<String, String?> urls = const {},
}) async {
  var n = 0;
  final detail = <Map<String, Object?>>[];
  for (final sid in sids.toSet()) {
    if (!sid.startsWith('cs_')) continue;
    final o = await c.sessionOracle(sid, checkoutUrl: urls[sid]);
    detail.add(Map<String, Object?>.from(o));
    if (o['open_payable'] == true) n++;
  }
  return (n, detail);
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

void recordHoldOrFail({
  required Rtdb c,
  required String probeId,
  required String poco,
  required String lens,
  required String payload,
  required Object? http,
  required Object? bd,
  required bool isHold,
  required String holdId,
  required String severity,
  required String title,
  required String actor,
  required String pre,
  required String repro,
  required Object? expected,
  required Object? obtained,
  required String blockId,
  required String blockTitle,
  bool countFinding = true,
  bool classeNova = false,
}) {
  if (isHold) {
    if (countFinding) {
      c.hold(
        id: holdId,
        lens: lens,
        severity: severity,
        title: title,
        actor: actor,
        pre: pre,
        repro: repro,
        expected: expected,
        obtained: obtained,
      );
    } else {
      c.note('CTRL.$probeId', 'anti-atrofia HOLD não contado', obtained,
          lens: lens, well: poco);
    }
    c.probe(
      id: probeId,
      poco: poco,
      payload: payload,
      http: http,
      bd: bd,
      verdict: 'HOLD',
      lens: lens,
      classeNova: classeNova,
    );
  } else {
    c.block(blockId, lens, blockTitle, obtained);
    c.probe(
      id: probeId,
      poco: poco,
      payload: payload,
      http: http,
      bd: bd,
      verdict: 'FAIL',
      lens: lens,
      classeNova: classeNova,
    );
  }
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

/// EL-A Idêntico / mutex (≥4)
Future<void> elAIdentico(Rtdb c) async {
  c.wellsTried.add('EL-A');

  // A1 2× bag idêntico paralelo → 1 cs_ reused
  final a1 = await mkSkus(c, n: 3, tag: 'a1-ident', qty: 2, price: 9);
  if (a1.length == 3) {
    final lines = bagLines(a1);
    final hits = await parallel([
      c.checkoutBag(lines: lines, amount: 1),
      c.checkoutBag(lines: lines, amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    final sids = openCs(hits);
    final stored = [
      for (final r in a1)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final briefs = hits.map((h) => h.brief).toList();
    final dual = dualCsCreate(hits);
    c.note('A1.identico', '2× bag idêntico paralelo', {
      'briefs': briefs,
      'sids': sids.toList(),
      'reused': hits.map((h) => h.reused).toList(),
      'stored': stored,
    }, lens: 'EL1', well: 'EL-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A1',
      poco: 'EL-A',
      lens: 'EL1',
      payload: 'Future.wait 2× bag idêntico mesma ordem',
      http: briefs,
      bd: {
        'sids': sids.toList(),
        'stored': stored,
        'reused': hits.map((h) => h.reused).toList(),
      },
      isHold: dual,
      holdId: 'P1-1',
      severity: 'P1',
      title: '2× bag idêntico: 2 cs_ distintas (sem reuse)',
      actor: 'buyer JWT',
      pre: '3-line bag; 2 CPI idênticos t=0',
      repro: 'Future.wait checkoutBag ∥ checkoutBag mesmas linhas',
      expected: '1 cs_; 2.º reused=true mesmo cs_ ou 400',
      obtained: {
        'sids': sids.toList(),
        'reused': hits.map((h) => h.reused).toList(),
        'stored': stored,
      },
      blockId: 'A1-IDENT',
      blockTitle: '2× idêntico: 1 cs_ reused',
      countFinding: dual && !c.findings.any((f) => f['id'] == 'P1-1'),
    );
  } else {
    skipProbe(
      c,
      id: 'A1',
      poco: 'EL-A',
      lens: 'EL1',
      payload: 'Future.wait 2× bag idêntico',
      why: 'mkSkus',
    );
  }
  await pause();

  // A2 3× mesmo bag → 1 cs_
  final a2 = await mkSkus(c, n: 3, tag: 'a2-3x', qty: 2, price: 10);
  if (a2.length == 3) {
    final lines = bagLines(a2);
    final hits = await parallel([
      c.checkoutBag(lines: lines, amount: 1),
      c.checkoutBag(lines: lines, amount: 1),
      c.checkoutBag(lines: lines, amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    final sids = openCs(hits);
    final stored = [
      for (final r in a2)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final briefs = hits.map((h) => h.brief).toList();
    final dual = dualCsCreate(hits);
    recordHoldOrFail(
      c: c,
      probeId: 'A2',
      poco: 'EL-A',
      lens: 'EL1',
      payload: 'Future.wait 3× mesmo bag paralelo',
      http: briefs,
      bd: {
        'sids': sids.toList(),
        'stored': stored,
        'reused': hits.map((h) => h.reused).toList(),
      },
      isHold: dual,
      holdId: 'P1-1',
      severity: 'P1',
      title: '3× mesmo bag: ≥2 cs_ distintas',
      actor: 'buyer JWT',
      pre: '3-line bag; 3 CPI idênticos t=0',
      repro: 'Future.wait 3× checkoutBag',
      expected: '1 cs_; extras reused ou 400',
      obtained: {
        'sids': sids.toList(),
        'reused': hits.map((h) => h.reused).toList(),
        'stored': stored,
      },
      blockId: 'A2-3X',
      blockTitle: '3× mesmo bag: 1 cs_',
      countFinding: dual && !c.findings.any((f) => f['id'] == 'P1-1'),
    );
  } else {
    skipProbe(
      c,
      id: 'A2',
      poco: 'EL-A',
      lens: 'EL1',
      payload: 'Future.wait 3× mesmo bag',
      why: 'mkSkus',
    );
  }
  await pause();

  // A3 UUID invertido → 1 cs_
  final a3 = await mkSkus(c, n: 3, tag: 'a3-uuid-inv', qty: 2, price: 11);
  if (a3.length == 3) {
    final sorted = [...a3]..sort((a, b) => a.oid.compareTo(b.oid));
    final fwd = bagLines(sorted);
    final rev = bagLines(sorted.reversed);
    final hits = await parallel([
      c.checkoutBag(lines: fwd, amount: 1),
      c.checkoutBag(lines: rev, amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    final sids = openCs(hits);
    final stored = [
      for (final r in a3)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final briefs = hits.map((h) => h.brief).toList();
    final dual = dualCsCreate(hits);
    recordHoldOrFail(
      c: c,
      probeId: 'A3',
      poco: 'EL-A',
      lens: 'EL1',
      payload: 'Future.wait 2× bag UUID invertido',
      http: briefs,
      bd: {
        'sids': sids.toList(),
        'stored': stored,
        'reused': hits.map((h) => h.reused).toList(),
      },
      isHold: dual,
      holdId: 'P1-1',
      severity: 'P1',
      title: 'UUID invertido: 2 cs_ distintas',
      actor: 'buyer JWT',
      pre: '3 SKUs; mesmo set sorted vs reversed',
      repro: 'Future.wait checkoutBag fwd ∥ rev',
      expected: '1 cs_ reused',
      obtained: {
        'sids': sids.toList(),
        'reused': hits.map((h) => h.reused).toList(),
        'stored': stored,
      },
      blockId: 'A3-UUID',
      blockTitle: 'UUID invertido: 1 cs_ reused',
      countFinding: dual && !c.findings.any((f) => f['id'] == 'P1-1'),
    );
  } else {
    skipProbe(
      c,
      id: 'A3',
      poco: 'EL-A',
      lens: 'EL1',
      payload: 'Future.wait UUID invertido',
      why: 'mkSkus',
    );
  }
  await pause();

  // A4 timeout 100ms ∥ complete ∥ retry → 1 cs_ (classe_nova timing)
  final a4 = await mkSkus(c, n: 2, tag: 'a4-to100', qty: 2);
  if (a4.length == 2) {
    final lines = bagLines(a4);
    final timed = c.checkoutBag(
      lines: lines,
      amount: 1,
      timeout: const Duration(milliseconds: 100),
    );
    final complete = c.checkoutBag(lines: lines, amount: 1);
    final retry = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      return c.checkoutBag(lines: lines, amount: 1);
    });
    final triple = await parallel([timed, complete, retry]);
    for (final h in triple) {
      c.trackSession(h);
    }
    await Future<void>.delayed(const Duration(seconds: 4));
    final stored = [
      '${(await c.orderRow(a4[0].oid))?['stripe_checkout_session_id'] ?? ''}',
      '${(await c.orderRow(a4[1].oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final sids = {
      ...openCs(triple),
      ...stored.where((s) => s.startsWith('cs_')),
    };
    final briefs = triple.map((h) => h.brief).toList();
    final dual = dualCsCreate(triple) || sids.length >= 2;
    c.note('A4.timeout100', 'timeout 100ms ∥ complete ∥ retry 800ms', {
      'briefs': briefs,
      'stored': stored,
      'sids': sids.toList(),
      'reused': triple.map((h) => h.reused).toList(),
    }, lens: 'EL4', well: 'EL-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A4',
      poco: 'EL-A',
      lens: 'EL4',
      payload:
          'Future.wait bag timeout 100ms ∥ complete ∥ retry +800ms',
      http: briefs,
      bd: {'stored': stored, 'sids': sids.toList()},
      isHold: dual,
      holdId: 'P1-1',
      severity: 'P1',
      title: 'Timeout 100ms∥complete∥retry = ≥2 cs_',
      actor: 'buyer JWT',
      pre: '2-line bag; abort 100ms enquanto server continua',
      repro: 'Future.wait timeout 100ms ∥ bag complete ∥ retry 800ms',
      expected: '1 cs_; retry reused ou 400',
      obtained: {'sids': sids.toList(), 'stored': stored, 'briefs': briefs},
      blockId: 'A4-TIMEOUT100',
      blockTitle: 'timeout 100ms∥complete∥retry ≤1 cs_',
      classeNova: true,
      countFinding: dual && !c.findings.any((f) => f['id'] == 'P1-1'),
    );
  } else {
    skipProbe(
      c,
      id: 'A4',
      poco: 'EL-A',
      lens: 'EL4',
      payload: 'Future.wait timeout 100ms∥complete∥retry',
      why: 'mkSkus',
      classeNova: true,
    );
  }
}

/// EL-B Overlap fail-closed (≥7)
Future<void> elBOverlapFailClosed(Rtdb c) async {
  c.wellsTried.add('EL-B');

  Future<void> overlapProbe({
    required String id,
    required String payload,
    required List<({String oid, String pid, double price})> skus,
    required List<HttpHit> hits,
    required String pre,
    required String titleIfTwo,
    required String expected,
    String lens = 'EL3',
    bool classeNova = true,
  }) async {
    for (final h in hits) {
      c.trackSession(h);
    }
    if (hits.isNotEmpty && hits.every(rateLimited)) {
      skipProbe(
        c,
        id: id,
        poco: 'EL-B',
        lens: lens,
        payload: payload,
        why: '429 rate limit — não é prova mutex',
        classeNova: classeNova,
      );
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    final sids = openCs(hits);
    final payablePack =
        await openPayableCount(c, sids, urls: urlsFromHits(hits));
    final briefs = hits.map((h) => h.brief).toList();
    final stored = [
      for (final r in skus)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final dual = dualCsCreate(hits);
    c.note('$id.overlap', payload, {
      'sids': sids.toList(),
      'payable': payablePack.$1,
      'oracle': payablePack.$2,
      'briefs': briefs,
      'stored': stored,
      'reused': hits.map((h) => h.reused).toList(),
      'http': hits.map((h) => h.status).toList(),
      'overlapping400': hits.map(overlapping400).toList(),
      'contention': hits.map(contention).toList(),
    }, lens: lens, well: 'EL-B');
    recordHoldOrFail(
      c: c,
      probeId: id,
      poco: 'EL-B',
      lens: lens,
      payload: payload,
      http: briefs,
      bd: {
        'sids': sids.toList(),
        'stored': stored,
        'payable': payablePack.$1,
        'oracle': payablePack.$2,
        'reused': hits.map((h) => h.reused).toList(),
        'overlapping400': hits.map(overlapping400).toList(),
      },
      isHold: dual,
      holdId: 'P1-1',
      severity: 'P1',
      title: titleIfTwo,
      actor: 'buyer JWT',
      pre: pre,
      repro: payload,
      expected: expected,
      obtained: {
        'sids': sids.toList(),
        'payable': payablePack.$1,
        'stored': stored,
        'briefs': briefs,
        'oracle': payablePack.$2,
      },
      blockId: '$id-OVERLAP',
      blockTitle: '$id ≤1 create (400 overlapping ou reused)',
      classeNova: classeNova,
      countFinding: dual && !c.findings.any((f) => f['id'] == 'P1-1'),
    );
  }

  // B1 6∥4 t=0
  await pause();
  final b1 = await mkSkus(c, n: 6, tag: 'b1-6x4-0ms', qty: 2, price: 9);
  if (b1.length == 6) {
    final hits = await parallel([
      c.checkoutBag(lines: bagLines(b1), amount: 1),
      c.checkoutBag(lines: bagLines(b1.sublist(1, 5)), amount: 1),
    ]);
    await overlapProbe(
      id: 'B1',
      payload: 'Future.wait bag 6∥4 t=0',
      skus: b1,
      hits: hits,
      pre: '6 SKUs; ABCDEF∥BCDE t=0',
      titleIfTwo: 'Overlap 6∥4 t=0: 2 cs_ distintas reused=false',
      expected: '200+400 overlapping ou 1 cs_ reused — nunca 2 creates',
      lens: 'EL3',
    );
  } else {
    skipProbe(
      c,
      id: 'B1',
      poco: 'EL-B',
      lens: 'EL3',
      payload: 'Future.wait bag 6∥4 t=0',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B2 6∥4 t=50
  await pause();
  final b2 = await mkSkus(c, n: 6, tag: 'b2-6x4-50ms', qty: 2, price: 9);
  if (b2.length == 6) {
    final first = c.checkoutBag(lines: bagLines(b2), amount: 1);
    final second = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkoutBag(lines: bagLines(b2.sublist(1, 5)), amount: 1);
    });
    final hits = await parallel([first, second]);
    await overlapProbe(
      id: 'B2',
      payload: 'Future.wait bag 6∥4 t=50ms',
      skus: b2,
      hits: hits,
      pre: '6 SKUs; ABCDEF t=0 ∥ BCDE t=50ms',
      titleIfTwo: 'Overlap 6∥4 t=50: 2 cs_ distintas reused=false',
      expected: '200+400 overlapping ou 1 cs_ reused — nunca 2 creates',
      lens: 'EL4',
    );
  } else {
    skipProbe(
      c,
      id: 'B2',
      poco: 'EL-B',
      lens: 'EL4',
      payload: 'Future.wait bag 6∥4 t=50',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B3 expand subset→50ms→superset → 2.º 400
  await pause();
  final b3 = await mkSkus(c, n: 4, tag: 'b3-expand50', qty: 2, price: 14);
  if (b3.length == 4) {
    final first = c.checkoutBag(lines: bagLines(b3.sublist(0, 2)), amount: 1);
    final second = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkoutBag(lines: bagLines(b3), amount: 1);
    });
    final hits = await parallel([first, second]);
    await overlapProbe(
      id: 'B3',
      payload: 'Future.wait subset → 50ms → superset expand',
      skus: b3,
      hits: hits,
      pre: '4 SKUs; AB t=0 ∥ ABCD t=50ms',
      titleIfTwo: 'Expand 50ms: 2 cs_ (expire+criar 2.ª)',
      expected: '2.º 400 overlapping bag session — nunca 2.ª cs_',
      lens: 'EL3',
    );
  } else {
    skipProbe(
      c,
      id: 'B3',
      poco: 'EL-B',
      lens: 'EL3',
      payload: 'Future.wait expand 50ms',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B4 shrink full→50ms→subset → reuse maior ou 400
  await pause();
  final b4 = await mkSkus(c, n: 4, tag: 'b4-shrink50', qty: 2, price: 13);
  if (b4.length == 4) {
    final first = c.checkoutBag(lines: bagLines(b4), amount: 1);
    final second = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkoutBag(lines: bagLines(b4.sublist(0, 2)), amount: 1);
    });
    final hits = await parallel([first, second]);
    await overlapProbe(
      id: 'B4',
      payload: 'Future.wait full → 50ms → subset shrink',
      skus: b4,
      hits: hits,
      pre: '4 SKUs; ABCD t=0 ∥ AB t=50ms',
      titleIfTwo: 'Shrink 50ms: 2 cs_ distintas',
      expected: 'reuse do maior ou 400 — nunca 2 creates',
      lens: 'EL4',
    );
  } else {
    skipProbe(
      c,
      id: 'B4',
      poco: 'EL-B',
      lens: 'EL4',
      payload: 'Future.wait shrink 50ms',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B5 bag∥single meio
  await pause();
  final b5 = await mkSkus(c, n: 5, tag: 'b5-mid-c', qty: 2, price: 8);
  if (b5.length == 5) {
    final midC = b5[2];
    final hits = await parallel([
      c.checkoutBag(lines: bagLines(b5), amount: 1),
      c.checkout(orderId: midC.oid, productId: midC.pid, amount: 1),
    ]);
    await overlapProbe(
      id: 'B5',
      payload: 'Future.wait bag ABCDE ∥ CPI single C (meio)',
      skus: b5,
      hits: hits,
      pre: '5 SKUs; bag ABCDE ∥ CPI C meio',
      titleIfTwo: 'bag∥single meio: 2 cs_ distintas',
      expected: '≤1 create; 2.º 400 overlapping ou reused',
      lens: 'EL3',
    );
  } else {
    skipProbe(
      c,
      id: 'B5',
      poco: 'EL-B',
      lens: 'EL3',
      payload: 'Future.wait bag∥single meio',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B6 bag∥single∥bag
  await pause();
  final b6 = await mkSkus(c, n: 3, tag: 'b6-bsb', qty: 2, price: 12);
  if (b6.length == 3) {
    final three = bagLines(b6);
    final mid = b6[1];
    final bag1 = c.checkoutBag(lines: three, amount: 1);
    final single = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return c.checkout(orderId: mid.oid, productId: mid.pid, amount: 1);
    });
    final bag2 = c.checkoutBag(lines: three, amount: 1);
    final hits = await parallel([bag1, single, bag2]);
    await overlapProbe(
      id: 'B6',
      payload: 'Future.wait bag ∥ single +200ms ∥ bag',
      skus: b6,
      hits: hits,
      pre: '3 SKUs; bag∥single-B@200ms∥bag',
      titleIfTwo: 'bag∥single∥bag: ≥2 cs_ distintas',
      expected: '≤1 create; extras 400 overlapping ou reused',
      lens: 'EL4',
    );
  } else {
    skipProbe(
      c,
      id: 'B6',
      poco: 'EL-B',
      lens: 'EL4',
      payload: 'Future.wait bag∥single∥bag',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B7 AB∥BC∥CA
  await pause();
  final b7 = await mkSkus(c, n: 3, tag: 'b7-tri', qty: 2, price: 10);
  if (b7.length == 3) {
    final ab = bagLines([b7[0], b7[1]]);
    final bc = bagLines([b7[1], b7[2]]);
    final ca = bagLines([b7[2], b7[0]]);
    final hits = await parallel([
      c.checkoutBag(lines: ab, amount: 1),
      c.checkoutBag(lines: bc, amount: 1),
      c.checkoutBag(lines: ca, amount: 1),
    ]);
    await overlapProbe(
      id: 'B7',
      payload: 'Future.wait bag AB ∥ BC ∥ CA (triângulo)',
      skus: b7,
      hits: hits,
      pre: '3 SKUs; AB∥BC∥CA cada par partilha 1 linha',
      titleIfTwo: 'Triângulo AB∥BC∥CA: ≥2 cs_ distintas',
      expected: '≤1 create; extras 400 overlapping',
      lens: 'EL3',
    );
  } else {
    skipProbe(
      c,
      id: 'B7',
      poco: 'EL-B',
      lens: 'EL3',
      payload: 'Future.wait AB∥BC∥CA',
      why: 'mkSkus',
      classeNova: true,
    );
  }
}

/// EL-C Disjuntos / preço (≥4)
Future<void> elCDisjuntosPreco(Rtdb c) async {
  c.wellsTried.add('EL-C');

  // C1 2 bags disjuntos → 2 cs_ OK
  await pause();
  final c1a = await mkSkus(c, n: 2, tag: 'c1-disj-a', qty: 2, price: 7);
  final c1b = await mkSkus(c, n: 2, tag: 'c1-disj-b', qty: 2, price: 8);
  if (c1a.length == 2 && c1b.length == 2) {
    final hits = await parallel([
      c.checkoutBag(lines: bagLines(c1a), amount: 1),
      c.checkoutBag(lines: bagLines(c1b), amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    final sids = openCs(hits);
    final briefs = hits.map((h) => h.brief).toList();
    final storedA = [
      for (final r in c1a)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final storedB = [
      for (final r in c1b)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    // Disjuntos: 2 cs_ é o esperado. HOLD só se overlap indevido (mesmo sid nas duas
    // bags) ou ambos 400 sem motivo. 1+400 mutex = conservador, não P1.
    final sameSidOnBothBags = storedA.any((s) =>
            s.startsWith('cs_') && storedB.contains(s)) &&
        storedA.toSet().intersection(storedB.toSet()).any((s) => s.startsWith('cs_'));
    c.note('C1.disjoint', '2 bags disjuntos', {
      'briefs': briefs,
      'sids': sids.toList(),
      'storedA': storedA,
      'storedB': storedB,
    }, lens: 'EL2', well: 'EL-C');
    recordHoldOrFail(
      c: c,
      probeId: 'C1',
      poco: 'EL-C',
      lens: 'EL2',
      payload: 'Future.wait 2 bags disjuntos mesmo buyer',
      http: briefs,
      bd: {'sids': sids.toList(), 'storedA': storedA, 'storedB': storedB},
      isHold: sameSidOnBothBags,
      holdId: 'P2-C1',
      severity: 'P2',
      title: 'bags disjuntos partilharam a mesma cs_',
      actor: 'buyer JWT',
      pre: '2 bags sem linhas em comum',
      repro: 'Future.wait checkoutBag A ∥ checkoutBag B',
      expected: '2 cs_ OK (linhas sem overlap)',
      obtained: {
        'sids': sids.toList(),
        'storedA': storedA,
        'storedB': storedB,
        'briefs': briefs,
      },
      blockId: 'C1-DISJOINT',
      blockTitle: 'bags disjuntos: 2 cs_ (ou mutex serializa)',
    );
  } else {
    skipProbe(
      c,
      id: 'C1',
      poco: 'EL-C',
      lens: 'EL2',
      payload: '2 bags disjuntos',
      why: 'mkSkus',
    );
  }

  // C2 underpay selo
  await pause();
  final c2sku = await mkSkus(
    c,
    n: 1,
    tag: 'c2-under',
    qty: 2,
    price: 18,
    shipping: 'ctt',
  );
  HttpHit? underHit;
  if (c2sku.isNotEmpty) {
    underHit = await c.checkout(
      orderId: c2sku.first.oid,
      productId: c2sku.first.pid,
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
  recordHoldOrFail(
    c: c,
    probeId: 'C2',
    poco: 'EL-C',
    lens: 'EL6',
    payload: 'body total_eur=0 item_price=0.01 amount=0 (SKU 18€)',
    http: underHit?.brief,
    bd: {'amt': amt},
    isHold: under,
    holdId: 'P0-C2',
    severity: 'P0',
    title: 'body hostil baixou amount_total abaixo do catálogo',
    actor: 'buyer JWT',
    pre: 'SKU 18€',
    repro: 'CPI extras total_eur/item_price',
    expected: 'amount ≈ catálogo (selo); extras ignorados',
    obtained: {'amt': amt, 'hit': underHit?.brief},
    blockId: 'C2-UNDERPAY',
    blockTitle: 'underpay ignorado; amount catálogo',
  );

  // C3 2 buyers qty=1
  await pause();
  final pid = await c.createProduct(title: '$prefix-c3-last', qty: 1, price: 11);
  if (pid != null) {
    final o1 = await c.insertOrder(productId: pid, price: 11, jwt: c.buyerJwt);
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
      recordHoldOrFail(
        c: c,
        probeId: 'C3',
        poco: 'EL-C',
        lens: 'EL5',
        payload: 'Future.wait 2 buyers CPI última unidade qty=1',
        http: briefs,
        bd: {'ok': ok, 'o1': o1, 'o2': o2},
        isHold: ok >= 2,
        holdId: 'P0-C3',
        severity: 'P0',
        title: '2 buyers Session na última unidade',
        actor: 'buyer + buyer2 JWT',
        pre: 'quantity=1; 2 orders',
        repro: 'Future.wait 2× CPI',
        expected: '1 Session + 1 stock block',
        obtained: {'ok': ok, 'briefs': briefs},
        blockId: 'C3-LAST',
        blockTitle: 'última unidade ≤1 Session',
      );
    } else {
      recordHoldOrFail(
        c: c,
        probeId: 'C3',
        poco: 'EL-C',
        lens: 'EL5',
        payload: '2 buyers qty=1 (insert 2.º)',
        http: {'o1': o1, 'o2': o2},
        bd: {'o1': o1, 'o2': o2},
        isHold: false,
        holdId: 'P0-C3',
        severity: 'P0',
        title: '2.º buyer inseriu hold na última unidade',
        actor: 'buyer + buyer2 JWT',
        pre: 'quantity=1',
        repro: '2× insertOrder',
        expected: '2.º insert 400 stock',
        obtained: {'o1': o1, 'o2': o2},
        blockId: 'C3-LAST',
        blockTitle: '2.º insert/CPI bloqueado no last-unit',
      );
    }
  } else {
    skipProbe(
      c,
      id: 'C3',
      poco: 'EL-C',
      lens: 'EL5',
      payload: '2 buyers qty=1',
      why: 'createProduct',
    );
  }

  // C4 cross-seller deny
  await pause();
  final s2pid = await c.createProduct(
    title: '$prefix-c4-xseller',
    qty: 2,
    price: 14,
    seller: c.seller2Id,
  );
  final s1 = await mkSkus(c, n: 1, tag: 'c4-s1', qty: 2, price: 12);
  HttpHit? cross;
  if (s2pid != null && s1.isNotEmpty) {
    final o2 = await c.insertOrder(
      productId: s2pid,
      price: 14,
      seller: c.seller2Id,
      jwt: c.buyerJwt,
    );
    if (o2 != null) {
      cross = await c.checkoutBag(
        lines: [
          {'order_id': s1.first.oid, 'product_id': s1.first.pid},
          {'order_id': o2, 'product_id': s2pid, 'seller_id': c.seller2Id},
        ],
        amount: 1,
      );
      c.trackSession(cross);
    }
  }
  recordHoldOrFail(
    c: c,
    probeId: 'C4',
    poco: 'EL-C',
    lens: 'EL1',
    payload: 'bag 2 sellers (S1+S2) CPI',
    http: cross?.brief,
    bd: {'s2pid': s2pid},
    isHold: cross != null && cross.ok,
    holdId: 'P1-C4',
    severity: 'P1',
    title: 'bag cross-seller criou Session',
    actor: 'buyer JWT',
    pre: '1 order S1 + 1 order S2',
    repro: 'checkoutBag 2 sellers',
    expected: '400 one seller / cross-seller deny',
    obtained: cross?.brief,
    blockId: 'C4-CROSS',
    blockTitle: 'bag cross-seller 400',
  );
}

/// EL-D Caixa / denylist (≥3)
Future<void> elDCaixaDenylist(Rtdb c, Map<String, num> wallets0) async {
  c.wellsTried.add('EL-D');

  // D1 pago 4242
  await pause();
  final paid = await c.payToPago(lens: 'EL8', initialQty: 2);
  if (paid == null) {
    skipProbe(
      c,
      id: 'D1',
      poco: 'EL-D',
      lens: 'EL8',
      payload: 'setup_paid_order Stripe TEST 4242',
      why: 'null',
    );
  } else {
    final row = await c.orderRow(paid.oid);
    final prodRow = await c.productRow(paid.pid);
    final wallets1 = await c.wallets();
    final st = '${row?['status']}';
    final cents = numOf(row?['amount_paid_cents']);
    final applied = numOf(row?['stock_units_applied']);
    final qty = numOf(prodRow?['quantity']);
    final pi = '${row?['stripe_payment_intent_id'] ?? ''}';
    final coherent = st == 'pago' &&
        pi.startsWith('pi_') &&
        cents != null &&
        cents >= 50 &&
        applied == 1 &&
        qty == 1;
    c.note('D1.paid', 'Stripe TEST pago + caixa', {
      'oid': paid.oid,
      'pid': paid.pid,
      'pi': pi,
      'status': st,
      'cents': cents,
      'applied': applied,
      'qty': qty,
      'wallets0': wallets0,
      'wallets1': wallets1,
    }, lens: 'EL8', well: 'EL-D');
    recordHoldOrFail(
      c: c,
      probeId: 'D1',
      poco: 'EL-D',
      lens: 'EL8',
      payload: 'setup_paid_order Stripe TEST 4242 + ledger stock/caixa',
      http: 'pago fixture',
      bd: {
        'oid': paid.oid,
        'pi': pi,
        'status': st,
        'cents': cents,
        'applied': applied,
        'qty': qty,
      },
      isHold: !coherent,
      holdId: 'P1-D1',
      severity: 'P1',
      title: 'pago Stripe TEST incoerente (status/stock/cents)',
      actor: 'e2e setup_paid_order (pm_card_visa / 4242)',
      pre: 'qty=2 SKU',
      repro: 'setup_paid_order',
      expected: 'status=pago; pi_; cents≥50; applied=1; qty=1',
      obtained: {
        'status': st,
        'pi': pi,
        'cents': cents,
        'applied': applied,
        'qty': qty,
      },
      blockId: 'D1-PAID',
      blockTitle: 'Stripe TEST pago + caixa coerente',
    );
  }

  // D2 bizum → 400 sem cs_ (1 linha reteste P2)
  await pause();
  HttpHit? bizHit;
  String? bizPm;
  String? bizSid;
  final bizPid = await c.createProduct(
    title: '$prefix-d2-bizum',
    qty: 2,
    price: 17,
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
      c.trackSession(bizHit);
      bizSid = bizHit.sessionId;
    }
  }
  final offBypass = bizHit != null &&
      bizHit.ok &&
      (bizSid ?? '').startsWith('cs_') &&
      (bizPm ?? '').toLowerCase().contains('bizum');
  c.note('D2.bizum', 'bizum 1 linha reteste P2', {
    'pm': bizPm,
    'hit': bizHit?.brief,
    'sid': bizSid,
    'offBypass': offBypass,
  }, lens: 'EL6', well: 'EL-D');
  recordHoldOrFail(
    c: c,
    probeId: 'D2',
    poco: 'EL-D',
    lens: 'EL6',
    payload: 'payment_method bizum (1 linha reteste P2)',
    http: bizHit?.brief,
    bd: {'pm': bizPm, 'sid': bizSid},
    isHold: offBypass,
    holdId: 'P2-1',
    severity: 'P2',
    title: 'método off residual bizum abriu Session Stripe',
    actor: 'buyer JWT',
    pre: 'order payment_method=bizum',
    repro: 'insert bizum; CPI',
    expected: 'CPI 400 off-platform; sem cs_',
    obtained: {'hit': bizHit?.brief, 'pm': bizPm, 'sid': bizSid},
    blockId: 'D2-BIZUM',
    blockTitle: 'bizum 400 sem cs_',
  );

  // D3 Pagamento na App → cs_ OK
  await pause();
  final d3 = await mkSkus(
    c,
    n: 1,
    tag: 'd3-inapp',
    qty: 2,
    price: 15,
    payment: 'Pagamento na app',
  );
  HttpHit? inApp;
  if (d3.isNotEmpty) {
    inApp = await c.checkout(
      orderId: d3.first.oid,
      productId: d3.first.pid,
      amount: 1,
    );
    c.trackSession(inApp);
  }
  final pm = d3.isEmpty
      ? ''
      : '${(await c.orderRow(d3.first.oid))?['payment_method'] ?? ''}';
  final sid = inApp?.sessionId ?? '';
  final inAppOk = inApp != null && inApp.ok && sid.startsWith('cs_');
  recordHoldOrFail(
    c: c,
    probeId: 'D3',
    poco: 'EL-D',
    lens: 'EL8',
    payload: 'Pagamento na App → CPI cs_ OK',
    http: inApp?.brief,
    bd: {'pm': pm, 'sid': sid},
    isHold: !inAppOk,
    holdId: 'P1-D3',
    severity: 'P1',
    title: 'Pagamento na App não abriu cs_',
    actor: 'buyer JWT',
    pre: 'order payment_method=Pagamento na app',
    repro: 'CPI single',
    expected: '200 + cs_',
    obtained: {'hit': inApp?.brief, 'pm': pm, 'sid': sid},
    blockId: 'D3-INAPP',
    blockTitle: 'Pagamento na App: cs_ OK',
  );
}
