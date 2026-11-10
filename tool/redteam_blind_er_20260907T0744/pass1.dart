/// RED TEAM CEGO ER pass1 — bag∥avulso reteste GATE FASE 4.
/// Matriz A1–A6 · B1–B4 · C1–C4. Sem correções.
/// Oráculo: 2× HTTP 200 + 2 cs_ distintas reused=false = P1 FAIL.
import 'dart:io';

import '_rter.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('ER pass1 staging=${c.url} prefix=$prefix');
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
    'cpi_actor': 'buyer3-rter',
  });
  final wallets0 = await c.wallets();
  c.note('wallet.pre', 'baseline', wallets0, lens: 'ER-C', well: 'ER-C');

  await erABagSingle(c);
  await erBCadeado(c);
  await erCCaixa(c, wallets0);

  final wallets1 = await c.wallets();
  c.note('wallet.post', 'após probes', {
    'pre': wallets0,
    'post': wallets1,
  }, lens: 'ER-C', well: 'ER-C');

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
    'findings_ids': c.findings.map((f) => f['id']).toList(),
  });
  stdout.writeln(
    'DONE probes=${c.probes.length} findings=${c.findings.length} '
    'blocked=${c.blocked.length} skip=${c.skipped.length} '
    'races=${races.length} classe_nova=${novas.length} '
    'lenses=${c.lensesHit.toList()..sort()} wells=${c.wellsTried.toList()..sort()}',
  );
}

Future<void> pause([int ms = 700]) =>
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

bool overlapping400(HttpHit h) {
  final raw = h.body.toLowerCase();
  return h.status == 400 && raw.contains('overlapping bag session');
}

/// GATE ER: 2× HTTP 200 + 2 cs_ distintas = dual create.
/// Esperado: 200+400 / 400+200 / reused mesmo sid. Nunca 2 creates reused=false.
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

Future<void> overlapProbe({
  required Rtdb c,
  required String id,
  required String poco,
  required String lens,
  required String payload,
  required List<({String oid, String pid, double price})> skus,
  required List<HttpHit> hits,
  required String pre,
  required String titleIfTwo,
  required String expected,
  bool classeNova = true,
}) async {
  for (final h in hits) {
    c.trackSession(h);
  }
  if (hits.isNotEmpty && hits.every(rateLimited)) {
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
    'dual_create': dual,
  }, lens: lens, well: poco);
  recordHoldOrFail(
    c: c,
    probeId: id,
    poco: poco,
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
      'dual_create': dual,
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
      'reused': hits.map((h) => h.reused).toList(),
      'dual_create': dual,
    },
    blockId: '$id-OVERLAP',
    blockTitle: '$id ≤1 create (400 overlapping ou reused mesmo sid)',
    classeNova: classeNova,
    countFinding: dual && !c.findings.any((f) => f['id'] == 'P1-1'),
  );
}

/// ER-A Bag∥single hard (≥6)
/// Cada corrida num comprador fresco (sem claim) — o furo conhecido
/// era só no primeiro checkout paralelo.
Future<void> erABagSingle(Rtdb c) async {
  c.wellsTried.add('ER-A');

  Future<void> asFresh(String tag) async {
    final actor = await c.mintBuyer(tag);
    c.buyerId = actor.id;
    c.buyerJwt = actor.jwt;
  }

  // A1 bag ABCDE ∥ single C t=0
  await pause();
  await asFresh('a1');
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
      poco: 'ER-A',
      lens: 'ER1',
      payload: 'Future.wait bag ABCDE ∥ single C t=0',
      skus: a1,
      hits: hits,
      pre: '5 SKUs; bag ABCDE ∥ CPI C meio t=0',
      titleIfTwo: 'bag∥single C t=0: 2 cs_ distintas reused=false',
      expected: '≤1 cs_ útil (200+400 / 400+200 / reused mesmo sid)',
      classeNova: false,
    );
  } else {
    skipProbe(
      c,
      id: 'A1',
      poco: 'ER-A',
      lens: 'ER1',
      payload: 'Future.wait bag ABCDE ∥ single C t=0',
      why: 'mkSkus',
    );
  }

  // A2 bag first → 50ms → single C
  await pause();
  await asFresh('a2');
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
      poco: 'ER-A',
      lens: 'ER1',
      payload: 'Future.wait bag first → 50ms → single C',
      skus: a2,
      hits: hits,
      pre: '5 SKUs; bag t=0 ∥ CPI C t=50ms',
      titleIfTwo: 'bag first∥single C t=50: 2 cs_ distintas',
      expected: '≤1 cs_ útil; never 2 creates reused=false',
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A2',
      poco: 'ER-A',
      lens: 'ER1',
      payload: 'Future.wait bag first → 50ms → single C',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // A3 single C first → 50ms → bag ABCDE
  await pause();
  await asFresh('a3');
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
      poco: 'ER-A',
      lens: 'ER1',
      payload: 'Future.wait single C first → 50ms → bag ABCDE',
      skus: a3,
      hits: hits,
      pre: '5 SKUs; CPI C t=0 ∥ bag t=50ms',
      titleIfTwo: 'single first∥bag t=50: 2 cs_ distintas',
      expected: '≤1 cs_ útil; bag reuse da Session avulsa que inclui a line',
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A3',
      poco: 'ER-A',
      lens: 'ER1',
      payload: 'Future.wait single C first → 50ms → bag ABCDE',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // A4 bag∥single∥bag (3 corrotinas; single @200ms)
  await pause();
  await asFresh('a4');
  final a4 = await mkSkus(c, n: 3, tag: 'a4-bsb-200', qty: 2, price: 11);
  if (a4.length == 3) {
    final three = bagLines(a4);
    final mid = a4[1];
    final bag1 = c.checkoutBag(lines: three, amount: 1);
    final single = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return c.checkout(orderId: mid.oid, productId: mid.pid, amount: 1);
    });
    final bag2 = c.checkoutBag(lines: three, amount: 1);
    final hits = await parallel([bag1, single, bag2]);
    await overlapProbe(
      c: c,
      id: 'A4',
      poco: 'ER-A',
      lens: 'ER1',
      payload: 'Future.wait bag ∥ single +200ms ∥ bag',
      skus: a4,
      hits: hits,
      pre: '3 SKUs; bag∥single-B@200ms∥bag',
      titleIfTwo: 'bag∥single∥bag: ≥2 cs_ distintas',
      expected: '≤1 create; extras 400 overlapping ou reused mesmo sid',
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A4',
      poco: 'ER-A',
      lens: 'ER1',
      payload: 'Future.wait bag∥single∥bag',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // A5 bag ABC ∥ single B (meio)
  await pause();
  await asFresh('a5');
  final a5 = await mkSkus(c, n: 3, tag: 'a5-abc-b', qty: 2, price: 9);
  if (a5.length == 3) {
    final midB = a5[1];
    final hits = await parallel([
      c.checkoutBag(lines: bagLines(a5), amount: 1),
      c.checkout(orderId: midB.oid, productId: midB.pid, amount: 1),
    ]);
    await overlapProbe(
      c: c,
      id: 'A5',
      poco: 'ER-A',
      lens: 'ER1',
      payload: 'Future.wait bag ABC ∥ single B (meio) t=0',
      skus: a5,
      hits: hits,
      pre: '3 SKUs; bag ABC ∥ CPI B meio',
      titleIfTwo: 'bag ABC∥single B: 2 cs_ distintas',
      expected: '≤1 cs_ útil',
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A5',
      poco: 'ER-A',
      lens: 'ER1',
      payload: 'Future.wait bag ABC ∥ single B',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // A6 bag de 2 ∥ single de 1 linha do saco @200ms (bag first)
  await pause();
  await asFresh('a6');
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
      poco: 'ER-A',
      lens: 'ER1',
      payload: 'Future.wait bag de 2 first → 200ms → single 1 linha',
      skus: a6,
      hits: hits,
      pre: '2 SKUs; bag AB t=0 ∥ CPI A t=200ms',
      titleIfTwo: 'bag2∥single1 t=200: 2 cs_ distintas',
      expected: '≤1 cs_ útil',
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A6',
      poco: 'ER-A',
      lens: 'ER1',
      payload: 'Future.wait bag de 2 ∥ single 1 linha t=200',
      why: 'mkSkus',
      classeNova: true,
    );
  }
}

/// ER-B Regressão cadeado (≥4)
Future<void> erBCadeado(Rtdb c) async {
  c.wellsTried.add('ER-B');
  c.buyerId = c.buyer3Id;
  c.buyerJwt = c.buyer3Jwt;

  // B1 6∥4 t=0
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
      poco: 'ER-B',
      lens: 'ER2',
      payload: 'Future.wait bag 6∥4 t=0',
      skus: b1,
      hits: hits,
      pre: '6 SKUs; ABCDEF∥BCDE t=0',
      titleIfTwo: 'regressão 6∥4: 2 cs_ distintas',
      expected: '≤1 / 400 overlapping — nunca 2 creates',
      classeNova: false,
    );
  } else {
    skipProbe(
      c,
      id: 'B1',
      poco: 'ER-B',
      lens: 'ER2',
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
      poco: 'ER-B',
      lens: 'ER2',
      payload: 'Future.wait subset → 50ms → superset expand',
      skus: b2,
      hits: hits,
      pre: '4 SKUs; AB t=0 ∥ ABCD t=50ms',
      titleIfTwo: 'regressão expand: 2 cs_ (expire+criar 2.ª)',
      expected: '400 no 2.º — nunca 2.ª cs_',
      classeNova: false,
    );
  } else {
    skipProbe(
      c,
      id: 'B2',
      poco: 'ER-B',
      lens: 'ER2',
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
      poco: 'ER-B',
      lens: 'ER2',
      payload: 'Future.wait 2× bag idêntico mesma ordem',
      skus: b3,
      hits: hits,
      pre: '3-line bag; 2 CPI idênticos t=0',
      titleIfTwo: '2× bag idêntico: 2 cs_ distintas (sem reuse)',
      expected: '1 cs_ reused mesmo sid',
      classeNova: false,
    );
  } else {
    skipProbe(
      c,
      id: 'B3',
      poco: 'ER-B',
      lens: 'ER2',
      payload: 'Future.wait 2× bag idêntico',
      why: 'mkSkus',
    );
  }

  // B4 shrink full→50ms→subset
  await pause();
  final b4 = await mkSkus(c, n: 4, tag: 'b4-shrink', qty: 2, price: 13);
  if (b4.length == 4) {
    final first = c.checkoutBag(lines: bagLines(b4), amount: 1);
    final second = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkoutBag(lines: bagLines(b4.sublist(0, 2)), amount: 1);
    });
    final hits = await parallel([first, second]);
    await overlapProbe(
      c: c,
      id: 'B4',
      poco: 'ER-B',
      lens: 'ER2',
      payload: 'Future.wait full → 50ms → subset shrink',
      skus: b4,
      hits: hits,
      pre: '4 SKUs; ABCD t=0 ∥ AB t=50ms',
      titleIfTwo: 'regressão shrink: 2 cs_ distintas',
      expected: 'reuse do maior ou 400 — nunca 2 creates',
      classeNova: false,
    );
  } else {
    skipProbe(
      c,
      id: 'B4',
      poco: 'ER-B',
      lens: 'ER2',
      payload: 'Future.wait shrink 50ms',
      why: 'mkSkus',
    );
  }
}

/// ER-C Caixa (≥4)
Future<void> erCCaixa(Rtdb c, Map<String, num> wallets0) async {
  c.wellsTried.add('ER-C');

  // C1 underpay selo
  await pause();
  final c1sku = await mkSkus(
    c,
    n: 1,
    tag: 'c1-under',
    qty: 2,
    price: 18,
    shipping: 'ctt',
  );
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
  recordHoldOrFail(
    c: c,
    probeId: 'C1',
    poco: 'ER-C',
    lens: 'ER3',
    payload: 'body total_eur=0 item_price=0.01 amount=0 (SKU 18€)',
    http: underHit?.brief,
    bd: {'amt': amt},
    isHold: under,
    holdId: 'P0-C1',
    severity: 'P0',
    title: 'body hostil baixou amount_total abaixo do catálogo',
    actor: 'buyer JWT',
    pre: 'SKU 18€',
    repro: 'CPI extras total_eur/item_price',
    expected: 'amount ≈ catálogo (selo); extras ignorados',
    obtained: {'amt': amt, 'hit': underHit?.brief},
    blockId: 'C1-UNDERPAY',
    blockTitle: 'underpay ignorado; amount catálogo',
  );

  // C2 2 buyers qty=1
  await pause();
  final pid = await c.createProduct(title: '$prefix-c2-last', qty: 1, price: 11);
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
        probeId: 'C2',
        poco: 'ER-C',
        lens: 'ER3',
        payload: 'Future.wait 2 buyers CPI última unidade qty=1',
        http: briefs,
        bd: {'ok': ok, 'o1': o1, 'o2': o2},
        isHold: ok >= 2,
        holdId: 'P0-C2',
        severity: 'P0',
        title: '2 buyers Session na última unidade',
        actor: 'buyer + buyer2 JWT',
        pre: 'quantity=1; 2 orders',
        repro: 'Future.wait 2× CPI',
        expected: '1 Session + 1 stock block',
        obtained: {'ok': ok, 'briefs': briefs},
        blockId: 'C2-LAST',
        blockTitle: 'última unidade ≤1 Session',
      );
    } else {
      recordHoldOrFail(
        c: c,
        probeId: 'C2',
        poco: 'ER-C',
        lens: 'ER3',
        payload: '2 buyers qty=1 (insert 2.º)',
        http: {'o1': o1, 'o2': o2},
        bd: {'o1': o1, 'o2': o2},
        isHold: false,
        holdId: 'P0-C2',
        severity: 'P0',
        title: '2.º buyer inseriu hold na última unidade',
        actor: 'buyer + buyer2 JWT',
        pre: 'quantity=1',
        repro: '2× insertOrder',
        expected: '2.º insert 400 stock',
        obtained: {'o1': o1, 'o2': o2},
        blockId: 'C2-LAST',
        blockTitle: '2.º insert/CPI bloqueado no last-unit',
      );
    }
  } else {
    skipProbe(
      c,
      id: 'C2',
      poco: 'ER-C',
      lens: 'ER3',
      payload: '2 buyers qty=1',
      why: 'createProduct',
    );
  }

  // C3 pago 4242 single OU bag
  await pause();
  var paidVia = 'none';
  var paidOk = false;
  Map<String, Object?> c3bd = {};
  Object? c3http;
  final happy = await mkSkus(c, n: 1, tag: 'c3-4242', qty: 2, price: 16);
  if (happy.isNotEmpty) {
    final hit = await c.checkout(
      orderId: happy.first.oid,
      productId: happy.first.pid,
      amount: 1,
    );
    c.trackSession(hit);
    c3http = hit.brief;
    final sid = hit.sessionId ?? '';
    if (hit.ok && sid.startsWith('cs_')) {
      final pay = await c.payCheckout4242(sid, checkoutUrl: hit.checkoutUrl);
      c3bd['pay'] = pay;
      if (pay['paid'] == true) {
        paidVia = 'cpi+4242';
        await Future<void>.delayed(const Duration(seconds: 3));
        final settle = await c.settleGet(sid);
        final row = await c.orderRow(happy.first.oid);
        final prod = await c.productRow(happy.first.pid);
        c3bd['settle'] = settle.brief;
        c3bd['order'] = {
          'status': row?['status'],
          'cents': row?['amount_paid_cents'],
          'pi': row?['stripe_payment_intent_id'],
          'applied': row?['stock_units_applied'],
        };
        c3bd['qty'] = prod?['quantity'];
        final st = '${row?['status']}';
        paidOk = st == 'pago' || pay['paid'] == true;
      }
    }
  }
  if (!paidOk) {
    final paid = await c.payToPago(lens: 'ER-C', initialQty: 2);
    if (paid == null) {
      skipProbe(
        c,
        id: 'C3',
        poco: 'ER-C',
        lens: 'ER3',
        payload: 'pago 4242 single OU bag',
        why: 'cpi pay fail + setup_paid_order null',
      );
    } else {
      paidVia = 'e2e setup_paid_order';
      final row = await c.orderRow(paid.oid);
      final prodRow = await c.productRow(paid.pid);
      final st = '${row?['status']}';
      final cents = numOf(row?['amount_paid_cents']);
      final applied = numOf(row?['stock_units_applied']);
      final qty = numOf(prodRow?['quantity']);
      final pi = '${row?['stripe_payment_intent_id'] ?? ''}';
      paidOk = st == 'pago' &&
          pi.startsWith('pi_') &&
          cents != null &&
          cents >= 50 &&
          applied == 1 &&
          qty == 1;
      c3http = 'setup_paid_order';
      c3bd = {
        'via': paidVia,
        'oid': paid.oid,
        'pid': paid.pid,
        'pi': pi,
        'status': st,
        'cents': cents,
        'applied': applied,
        'qty': qty,
        'wallets0': wallets0,
      };
      recordHoldOrFail(
        c: c,
        probeId: 'C3',
        poco: 'ER-C',
        lens: 'ER3',
        payload: 'setup_paid_order Stripe TEST 4242 + ledger',
        http: c3http,
        bd: c3bd,
        isHold: !paidOk,
        holdId: 'P1-C3',
        severity: 'P1',
        title: 'pago Stripe TEST incoerente (status/stock/cents)',
        actor: 'e2e setup_paid_order (pm_card_visa / 4242)',
        pre: 'qty=2 SKU',
        repro: 'setup_paid_order',
        expected: 'status=pago; pi_; cents≥50; applied=1; qty=1',
        obtained: c3bd,
        blockId: 'C3-PAID',
        blockTitle: 'Stripe TEST pago + caixa coerente',
      );
    }
  } else {
    c.note('C3.paid', '4242 happy', {
      'via': paidVia,
      ...c3bd,
    }, lens: 'ER3', well: 'ER-C');
    recordHoldOrFail(
      c: c,
      probeId: 'C3',
      poco: 'ER-C',
      lens: 'ER3',
      payload: 'CPI single + payCheckout4242 4242',
      http: c3http,
      bd: {'via': paidVia, ...c3bd},
      isHold: !paidOk,
      holdId: 'P1-C3',
      severity: 'P1',
      title: 'pago 4242 CPI incoerente',
      actor: 'buyer JWT + Stripe TEST 4242',
      pre: 'SKU 16€ qty=2; CPI single',
      repro: 'checkout; payCheckout4242',
      expected: 'pago + caixa coerente',
      obtained: {'via': paidVia, 'paid': paidOk, ...c3bd},
      blockId: 'C3-PAID',
      blockTitle: 'Stripe TEST pago 4242 single',
    );
  }

  // C4 disjuntos 2 bags → 2 cs_ OK
  await pause();
  final c4a = await mkSkus(c, n: 2, tag: 'c4-disj-a', qty: 2, price: 7);
  final c4b = await mkSkus(c, n: 2, tag: 'c4-disj-b', qty: 2, price: 8);
  if (c4a.length == 2 && c4b.length == 2) {
    final hits = await parallel([
      c.checkoutBag(lines: bagLines(c4a), amount: 1),
      c.checkoutBag(lines: bagLines(c4b), amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    final sids = openCs(hits);
    final briefs = hits.map((h) => h.brief).toList();
    final storedA = [
      for (final r in c4a)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final storedB = [
      for (final r in c4b)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final sameSidOnBothBags = storedA.any((s) =>
            s.startsWith('cs_') && storedB.contains(s)) &&
        storedA.toSet().intersection(storedB.toSet()).any((s) => s.startsWith('cs_'));
    c.note('C4.disjoint', '2 bags disjuntos', {
      'briefs': briefs,
      'sids': sids.toList(),
      'storedA': storedA,
      'storedB': storedB,
    }, lens: 'ER3', well: 'ER-C');
    recordHoldOrFail(
      c: c,
      probeId: 'C4',
      poco: 'ER-C',
      lens: 'ER3',
      payload: 'Future.wait 2 bags disjuntos mesmo buyer',
      http: briefs,
      bd: {'sids': sids.toList(), 'storedA': storedA, 'storedB': storedB},
      isHold: sameSidOnBothBags,
      holdId: 'P2-C4',
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
      blockId: 'C4-DISJOINT',
      blockTitle: 'bags disjuntos: 2 cs_ (ou mutex serializa)',
    );
  } else {
    skipProbe(
      c,
      id: 'C4',
      poco: 'ER-C',
      lens: 'ER3',
      payload: '2 bags disjuntos',
      why: 'mkSkus',
    );
  }
}
