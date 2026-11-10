/// RED TEAM CEGO EM pass1 — reteste saco + pagar (POS_OPEN_GATE).
/// Matriz A1–A4 · B1–B4 · C1–C4. Sem correções. Stripe TEST 4242.
import 'dart:io';

import '_rtem.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('EM pass1 staging=${c.url} prefix=$prefix');
  stdout.writeln(
    c.stripeTestKey == null
        ? 'WARN no sk_test_ — pay via pk/payment_pages + settle'
        : 'sk_test_ present — native retrieve+confirm',
  );
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.ensureBuyer3();
  c.buyerId = c.buyer3Id;
  c.buyerJwt = c.buyer3Jwt;
  c.note('actors', 'ids', {
    'b': c.buyerId,
    's': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
    'b3': c.buyer3Id,
    'cpi_actor': 'buyer3-rtem',
    'sk': c.stripeTestKey != null,
  });
  final wallets0 = await c.wallets();
  c.note('C1.wallet.pre', 'baseline', wallets0, lens: 'EM-C', well: 'EM-C');

  await emAGenerate(c);
  await emBPay(c);
  await emCCaixa(c, wallets0);

  final wallets1 = await c.wallets();
  c.note('C1.wallet.post', 'após probes', {
    'pre': wallets0,
    'post': wallets1,
  }, lens: 'EM-C', well: 'EM-C');

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
    'overlaps': c.overlapCaptures,
  });
  stdout.writeln(
    'DONE probes=${c.probes.length} findings=${c.findings.length} '
    'blocked=${c.blocked.length} skip=${c.skipped.length} '
    'races=${races.length} classe_nova=${novas.length} '
    'overlaps=${c.overlapCaptures.keys.toList()} '
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
  int qty = 1,
  double price = 12,
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
      jwt: c.buyerJwt,
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

bool overlappingBlocked(HttpHit h) {
  final b = h.body.toLowerCase();
  return h.status == 400 &&
      (b.contains('overlapping bag session') || b.contains('overlapping'));
}

Map<String, String?> urlsFromHits(List<HttpHit> hits) {
  final m = <String, String?>{};
  for (final h in hits) {
    final sid = h.sessionId;
    if (sid != null && sid.startsWith('cs_')) m[sid] = h.checkoutUrl;
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
  for (final r in skus) {
    stored.add(
      '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    );
  }
  final creates = hits.where((h) => h.ok && !h.reused).length;
  return {
    'status': hits.map((h) => h.status).toList(),
    'sids': sids.toList(),
    'reused': hits.map((h) => h.reused).toList(),
    'urls': urls,
    'payable_open': payable,
    'oracle': oracle,
    'stored': stored,
    'briefs': hits.map((h) => h.brief).toList(),
    'distinct_cs': sids.length,
    'creates': creates,
    'overlap_400': hits.any(overlappingBlocked),
    'dual_create': sids.length >= 2 && creates >= 2,
  };
}

void storeOverlap(
  Rtdb c,
  String id,
  List<({String oid, String pid, double price})> skus,
  List<HttpHit> hits,
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
    'lines': bagLines(skus),
  };
}

void maybeHoldDual(Rtdb c, String id, Map<String, Object?> pack) {
  final dual = pack['dual_create'] == true;
  if (!dual) return;
  if (c.findings.any((f) => f['id'] == 'P1-1')) return;
  c.hold(
    id: 'P1-1',
    lens: 'EM-A',
    severity: 'P1',
    title:
        'Overlap de conjuntos diferentes: duas Sessions (fail-closed POS_OPEN_GATE não actuou)',
    actor: 'buyer JWT fresco',
    pre: '≤1 create; 2.º HTTP 400 overlapping bag session',
    repro: 'Future.wait $id',
    expected: '200+400 ou 400+200 ou 1 cs_ reused — nunca 2 creates',
    obtained: {
      'probe': id,
      'sids': pack['sids'],
      'status': pack['status'],
      'reused': pack['reused'],
    },
  );
}

Future<void> emAGenerate(Rtdb c) async {
  c.wellsTried.add('EM-A');

  Future<void> overlapProbe({
    required String id,
    required String payload,
    required List<({String oid, String pid, double price})> skus,
    required List<HttpHit> hits,
    required bool classeNova,
    bool expectSingle = false,
  }) async {
    if (hits.isEmpty) {
      skipProbe(
        c,
        id: id,
        poco: 'EM-A',
        lens: 'EM-A',
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
        poco: 'EM-A',
        lens: 'EM-A',
        payload: payload,
        why: '429 rate limit',
        classeNova: classeNova,
      );
      return;
    }
    final pack = await packHits(c, hits, skus);
    storeOverlap(c, id, skus, hits, pack);
    final dual = pack['dual_create'] == true ||
        ((pack['distinct_cs'] as int? ?? 0) >= 2);
    c.note('$id.pack', 'overlap', pack, lens: 'EM-A', well: 'EM-A');
    c.probe(
      id: id,
      poco: 'EM-A',
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
      },
      verdict: dual ? 'HOLD' : 'FAIL',
      lens: 'EM-A',
      classeNova: classeNova,
    );
    if (dual) {
      maybeHoldDual(c, id, pack);
      c.note(
        '$id.dual',
        '2 cs_ — B1/B2 vão tentar pagar ambas',
        pack['sids'],
        lens: 'EM-A',
        well: 'EM-A',
      );
    }
    if (expectSingle && dual) {
      c.note('$id.identical_broke', 'idêntico deveria 1 cs_', pack['sids'],
          lens: 'EM-A', well: 'EM-A');
    }
  }

  // A1 6∥4 t=0
  final a1 = await mkSkus(c, n: 6, tag: 'a1-6x4', qty: 1, price: 8);
  if (a1.length == 6) {
    final hits = await parallel([
      c.checkoutBag(lines: bagLines(a1), amount: 1),
      c.checkoutBag(lines: bagLines(a1.sublist(1, 5)), amount: 1),
    ]);
    await overlapProbe(
      id: 'A1',
      payload: 'Future.wait bag 6∥4 t=0 (qty=1, mesmas orders)',
      skus: a1,
      hits: hits,
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A1',
      poco: 'EM-A',
      lens: 'EM-A',
      payload: '6∥4 t=0',
      why: 'mkSkus',
      classeNova: true,
    );
  }
  await pause();

  // A2 expand subset→superset
  final a2 = await mkSkus(c, n: 4, tag: 'a2-exp', qty: 1, price: 9);
  if (a2.length == 4) {
    final subset = bagLines(a2.sublist(0, 2));
    final superSet = bagLines(a2);
    final first = c.checkoutBag(lines: subset, amount: 1);
    final second = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkoutBag(lines: superSet, amount: 1);
    });
    final hits = await parallel([first, second]);
    await overlapProbe(
      id: 'A2',
      payload: 'Future.wait subset→50ms→superset expand (qty=1)',
      skus: a2,
      hits: hits,
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A2',
      poco: 'EM-A',
      lens: 'EM-A',
      payload: 'expand subset→superset',
      why: 'mkSkus',
      classeNova: true,
    );
  }
  await pause();

  // A3 bag∥single meio
  final a3 = await mkSkus(c, n: 5, tag: 'a3-mid', qty: 1, price: 7);
  if (a3.length == 5) {
    final mid = a3[2];
    final hits = await parallel([
      c.checkoutBag(lines: bagLines(a3), amount: 1),
      c.checkout(orderId: mid.oid, productId: mid.pid, amount: 1),
    ]);
    await overlapProbe(
      id: 'A3',
      payload: 'Future.wait bag ABCDE ∥ CPI single C meio (qty=1)',
      skus: a3,
      hits: hits,
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A3',
      poco: 'EM-A',
      lens: 'EM-A',
      payload: 'bag∥single meio',
      why: 'mkSkus',
      classeNova: true,
    );
  }
  await pause();

  // A4 2× idêntico → 1 cs_
  final a4 = await mkSkus(c, n: 3, tag: 'a4-id', qty: 1, price: 11);
  if (a4.length == 3) {
    final fwd = bagLines(a4);
    final rev = bagLines(a4.reversed);
    final hits = await parallel([
      c.checkoutBag(lines: fwd, amount: 1),
      c.checkoutBag(lines: rev, amount: 1),
    ]);
    await overlapProbe(
      id: 'A4',
      payload: 'Future.wait 2× bag idêntico ordem invertida (deve 1 cs_)',
      skus: a4,
      hits: hits,
      classeNova: false,
      expectSingle: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A4',
      poco: 'EM-A',
      lens: 'EM-A',
      payload: '2× bag idêntico',
      why: 'mkSkus',
    );
  }
}

Map<String, Object?>? pickDual(Rtdb c) {
  for (final id in ['A1', 'A2', 'A3']) {
    final cap = c.overlapCaptures[id];
    if (cap == null) continue;
    final sids = (cap['sids'] as List?)?.map((e) => '$e').toList() ?? [];
    final distinct = sids.where((s) => s.startsWith('cs_')).toSet();
    if (distinct.length >= 2) {
      return {'from': id, ...cap, 'sids': distinct.toList()};
    }
  }
  for (final id in ['A1', 'A2', 'A3', 'A4']) {
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

Future<void> emBPay(Rtdb c) async {
  c.wellsTried.add('EM-B');
  final dual = pickDual(c);
  c.note('B.pick', 'overlap escolhido para pagar', dual,
      lens: 'EM-B', well: 'EM-B');

  final sids = (dual?['sids'] as List?)?.map((e) => '$e').toList() ?? [];
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
  final twoOpen = sids.length >= 2;

  Map<String, Object?> pay1 = {'skipped': true};
  Map<String, Object?> pay2 = {'skipped': true};
  Map<String, Object?> snap1 = {};
  Map<String, Object?> snap2 = {};

  if (skus.isNotEmpty) {
    c.note('B.ledger.pre', 'antes de pagar', await c.ledgerSnap(skus),
        lens: 'EM-B', well: 'EM-B');
  }

  if (sids.isNotEmpty) {
    c.note('B1.pay.first', 'pagar primeira cs_ 4242', sids.first,
        lens: 'EM-B', well: 'EM-B');
    pay1 = await c.payCheckout4242(sids.first, checkoutUrl: urls[sids.first]);
    final pi1 = pay1['pi']?.toString();
    if (pi1 != null && pi1.startsWith('pi_') && lines.isNotEmpty) {
      final stl = await c.fase2Settle(
        pi: pi1,
        sessionId: sids.first,
        lines: lines,
        bag: true,
      );
      pay1['fase2'] = stl.brief;
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    snap1 = await c.ledgerSnap(skus);
  }

  if (twoOpen) {
    c.note('B2.pay.second', 'pagar segunda cs_ 4242', sids[1],
        lens: 'EM-B', well: 'EM-B');
    pay2 = await c.payCheckout4242(sids[1], checkoutUrl: urls[sids[1]]);
    final pi2 = pay2['pi']?.toString();
    if (pi2 != null && pi2.startsWith('pi_') && lines.isNotEmpty) {
      final stl = await c.fase2Settle(
        pi: pi2,
        sessionId: sids[1],
        lines: lines,
        bag: true,
      );
      pay2['fase2'] = stl.brief;
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    snap2 = await c.ledgerSnap(skus);
  } else if (sids.length == 1) {
    final stored = (dual?['stored'] as List?)?.map((e) => '$e').toList() ?? [];
    final orphans = stored
        .where((s) => s.startsWith('cs_') && s != sids.first)
        .toSet();
    final orphanTries = <Map<String, Object?>>[];
    for (final oidSid in orphans.take(2)) {
      final stl = await c.settleGet(oidSid);
      orphanTries.add({'sid': oidSid, 'settle': stl.brief});
    }
    if (orphanTries.isEmpty) {
      final stl = await c.settleGet(sids.first);
      orphanTries.add({
        'sid': sids.first,
        'settle_after_pay': stl.brief,
        'path': '400-path: único cs_ (2.º overlap bloqueado)',
      });
    }
    pay2 = {
      'skipped': false,
      'path': 'B4-single-open-400-path',
      'orphans': orphanTries,
      'from_status': dual?['status'],
      'overlap_400': dual?['overlap_400'],
    };
    snap2 = await c.ledgerSnap(skus);
  }

  final paid1 = pay1['paid'] == true;
  final paid2 = pay2['paid'] == true;
  final orders2 = (snap2['orders'] as List?) ?? (snap1['orders'] as List?) ?? [];
  final pagos = orders2.where((o) {
    if (o is! Map) return false;
    return '${o['status']}'.toLowerCase() == 'pago';
  }).length;
  final products2 = (snap2['products'] as List?) ?? [];
  var oversold = false;
  for (final p in products2) {
    if (p is! Map) continue;
    final q = numOf(p['qty']) ?? 0;
    if (q < 0) oversold = true;
  }
  if (paid1 && paid2 && pagos >= 2) {
    oversold = oversold ||
        products2.any((p) {
          if (p is! Map) return false;
          final q = numOf(p['qty']) ?? 99;
          return q <= 0 && pagos >= 2;
        });
  }

  final p0 = paid1 && paid2 && (pagos >= 1) && (oversold || pagos == skus.length);

  if (sids.isEmpty) {
    skipProbe(
      c,
      id: 'B1',
      poco: 'EM-B',
      lens: 'EM-B',
      payload: 'pagar primeira cs_ 4242',
      why: 'nenhum cs_ no overlap A',
      classeNova: true,
    );
  } else {
    c.probe(
      id: 'B1',
      poco: 'EM-B',
      payload: 'pagar primeira cs_ Stripe TEST 4242 (${dual?['from']})',
      http: pay1,
      bd: snap1,
      verdict: 'FAIL',
      lens: 'EM-B',
      classeNova: true,
    );
  }

  if (!twoOpen) {
    c.probe(
      id: 'B2',
      poco: 'EM-B',
      payload:
          'pagar segunda cs_ 4242 — só ${sids.length} open; documentar 2.º 400',
      http: pay2,
      bd: {
        'sids': sids,
        'from': dual?['from'],
        'status': dual?['status'],
        'overlap_400': dual?['overlap_400'],
      },
      verdict: 'FAIL',
      lens: 'EM-B',
      classeNova: true,
    );
  } else {
    final secondFailed = paid1 && paid2 != true;
    final bothPaid = paid1 && paid2;
    c.probe(
      id: 'B2',
      poco: 'EM-B',
      payload: 'pagar segunda cs_ Stripe TEST 4242 (mesmo overlap)',
      http: pay2,
      bd: snap2,
      verdict: bothPaid ? 'HOLD' : (secondFailed ? 'FAIL' : 'HOLD'),
      lens: 'EM-B',
      classeNova: true,
    );
    if (bothPaid) {
      c.findings.removeWhere((f) => f['id'] == 'P1-1');
      c.hold(
        id: p0 ? 'P0-1' : 'P1-1',
        lens: 'EM-B',
        severity: p0 ? 'P0' : 'P1',
        title: p0
            ? 'Duas Sessions overlap capturadas + stock/caixa inconsistente'
            : 'Duas Sessions overlap pagáveis; 2.ª captura ocorreu',
        actor: 'buyer JWT + Stripe TEST 4242',
        pre: 'overlap ${dual?['from']} 2 cs_ qty=1',
        repro: 'payCheckout4242 sid1; payCheckout4242 sid2; ledgerSnap',
        expected: '2.ª captura falha; ≤1 order pago; stock coerente',
        obtained: {
          'pay1': pay1,
          'pay2': pay2,
          'pagos': pagos,
          'products': products2,
        },
      );
    } else if (paid1 && !paid2) {
      c.note(
        'B2.second_fail',
        '2.ª paga falhou (defesa residual após dual link)',
        pay2,
        lens: 'EM-B',
        well: 'EM-B',
      );
    }
  }

  final snapB3 = snap2.isEmpty ? snap1 : snap2;
  final hub = (snapB3['hub'] as List?) ?? [];
  final prod = (snapB3['products'] as List?) ?? [];
  final ords = (snapB3['orders'] as List?) ?? [];
  final twoPaid = ords.where((o) {
    if (o is! Map) return false;
    return '${o['status']}'.toLowerCase() == 'pago';
  }).length;
  final hubIncoherent = paid1 &&
      prod.any((p) {
        if (p is! Map) return false;
        final q = numOf(p['qty']) ?? 0;
        return q < 0;
      });
  c.probe(
    id: 'B3',
    poco: 'EM-B',
    payload: 'oráculo stock Hub + products + orders após B1/B2',
    http: {
      'paid1': paid1,
      'paid2': paid2,
      'two_open': twoOpen,
    },
    bd: {
      'orders': ords,
      'products': prod,
      'hub': hub,
      'pagos': twoPaid,
    },
    verdict: (p0 || hubIncoherent) ? 'HOLD' : 'FAIL',
    lens: 'EM-B',
    classeNova: true,
  );
  if (hubIncoherent && !c.findings.any((f) => f['id'] == 'P0-1')) {
    c.hold(
      id: 'P0-1',
      lens: 'EM-B',
      severity: 'P0',
      title: 'Stock negativo / oversell após captura overlap',
      actor: 'oráculo products+Hub',
      pre: 'qty=1 SKUs overlap',
      repro: 'ledgerSnap após B1/B2',
      expected: 'qty≥0; ≤1 pago por unidade',
      obtained: snapB3,
    );
  }

  if (!twoOpen && sids.length == 1) {
    c.probe(
      id: 'B4',
      poco: 'EM-B',
      payload:
          'só 1 open: pagar essa + settle do 400-path (não contar 402 clássico)',
      http: {'pay1': pay1, 'orphan': pay2},
      bd: snapB3,
      verdict: 'FAIL',
      lens: 'EM-B',
      classeNova: true,
    );
  } else if (twoOpen) {
    c.probe(
      id: 'B4',
      poco: 'EM-B',
      payload: 'B4 N/A — 2 open; caminho B1/B2 usado (caça P0)',
      http: {'two_open': true, 'from': dual?['from']},
      bd: {'sids': sids},
      verdict: 'FAIL',
      lens: 'EM-B',
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'B4',
      poco: 'EM-B',
      lens: 'EM-B',
      payload: '1 open + settle 400-path',
      why: 'sem cs_',
      classeNova: true,
    );
  }

  c.overlapCaptures['PAY'] = {
    'from': dual?['from'],
    'sids': sids,
    'paid1': paid1,
    'paid2': paid2,
    'pagos': pagos,
    'p0': p0,
    'pay1': pay1,
    'pay2': pay2,
    'two_open': twoOpen,
  };
}

Future<void> emCCaixa(Rtdb c, Map<String, num> wallets0) async {
  c.wellsTried.add('EM-C');
  final wallets1 = await c.wallets();
  final dBuyer = (wallets1['buyer3'] ?? 0) - (wallets0['buyer3'] ?? 0);
  final dSeller = (wallets1['seller'] ?? 0) - (wallets0['seller'] ?? 0);
  final pay = c.overlapCaptures['PAY'] ?? {};
  final paid1 = pay['paid1'] == true;
  final paid2 = pay['paid2'] == true;

  c.probe(
    id: 'C1',
    poco: 'EM-C',
    payload: 'wallet Δ após B1/B2',
    http: {'paid1': paid1, 'paid2': paid2},
    bd: {
      'pre': wallets0,
      'post': wallets1,
      'd_buyer3': dBuyer,
      'd_seller': dSeller,
    },
    verdict: 'FAIL',
    lens: 'EM-C',
    classeNova: true,
  );

  // C2 happy bag único pago
  final bag = await c.setupPaidBag();
  c.note('C2.bag', 'setup_paid_bag', bag.brief, lens: 'EM-C', well: 'EM-C');
  final oa = bag.map?['order_a_id']?.toString();
  final ob = bag.map?['order_b_id']?.toString();
  final pa = bag.map?['product_a_id']?.toString();
  final pb = bag.map?['product_b_id']?.toString();
  if (oa != null) c.createdOrderIds.add(oa);
  if (ob != null) c.createdOrderIds.add(ob);
  if (pa != null) c.createdProductIds.add(pa);
  if (pb != null) c.createdProductIds.add(pb);
  final bothPago = bag.map?['checks'] is Map &&
      (bag.map!['checks'] as Map)['both_pago'] == true;
  c.probe(
    id: 'C2',
    poco: 'EM-C',
    payload: '1× happy bag único pago (setup_paid_bag 4242/pm_card_visa)',
    http: bag.brief,
    bd: {
      'ok': bag.map?['ok'],
      'pi': bag.map?['payment_intent_id'],
      'checks': bag.map?['checks'],
      'orders': bag.map?['orders'],
    },
    verdict: (bag.ok && (bag.map?['ok'] == true || bothPago)) ? 'FAIL' : 'HOLD',
    lens: 'EM-C',
    classeNova: false,
  );
  if (!(bag.ok && (bag.map?['ok'] == true || bothPago))) {
    c.hold(
      id: 'P1-C2',
      lens: 'EM-C',
      severity: 'P1',
      title: 'Happy bag único não liquidou as duas linhas',
      actor: 'e2e setup_paid_bag',
      pre: '2 SKUs mesmo seller',
      repro: 'setup_paid_bag',
      expected: 'ambas pago; soma amount_paid = PI',
      obtained: bag.brief,
    );
  }

  // C3 Hub leftover coerente — SKU qty=2 pago 1
  Map<String, Object?> c3bd = {};
  var c3ok = false;
  final paid = await c.payToPago(lens: 'EM-C', initialQty: 2);
  if (paid != null) {
    await Future<void>.delayed(const Duration(seconds: 2));
    final prod = await c.productRow(paid.pid);
    final hub = await c.hubSku(paid.pid);
    final ord = await c.orderRow(paid.oid);
    final q = numOf(prod?['quantity']) ?? -1;
    c3ok = '${ord?['status']}'.toLowerCase() == 'pago' && q == 1;
    c3bd = {
      'oid': paid.oid,
      'pid': paid.pid,
      'pi': paid.pi,
      'order': ord,
      'product_qty': q,
      'hub': {'http': hub.status, 'n': hub.list.length, 'row': hub.map},
    };
  } else {
    c3bd = {'e2e': 'setup_paid_order fail'};
  }
  c.probe(
    id: 'C3',
    poco: 'EM-C',
    payload: 'Hub leftover coerente após pago qty 2→1',
    http: c3bd['pi'],
    bd: c3bd,
    verdict: c3ok ? 'FAIL' : 'HOLD',
    lens: 'EM-C',
    classeNova: true,
  );
  if (!c3ok) {
    c.hold(
      id: 'P2-C3',
      lens: 'EM-C',
      severity: 'P2',
      title: 'Hub leftover incoerente após pago 2→1',
      actor: 'e2e setup_paid_order + hub_products_public',
      pre: 'SKU qty=2',
      repro: 'setup_paid_order; GET products + hub_products_public',
      expected: 'pago; qty=1 leftover; Hub lista resto',
      obtained: c3bd,
    );
  }

  // C4 bags disjuntos 2 cs_: pagar 1 — outro intacto
  await pause();
  final left = await mkSkus(c, n: 2, tag: 'c4-l', qty: 2, price: 6);
  final right = await mkSkus(c, n: 2, tag: 'c4-r', qty: 2, price: 16);
  if (left.length == 2 && right.length == 2) {
    final hits = await parallel([
      c.checkoutBag(lines: bagLines(left), amount: 1),
      c.checkoutBag(lines: bagLines(right), amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    final sL = hits[0].sessionId;
    final sR = hits[1].sessionId;
    Map<String, Object?> payL = {'skipped': true};
    if (sL != null && sL.startsWith('cs_')) {
      payL = await c.payCheckout4242(sL, checkoutUrl: hits[0].checkoutUrl);
      final pi = payL['pi']?.toString();
      if (pi != null && pi.startsWith('pi_')) {
        final stl = await c.fase2Settle(
          pi: pi,
          sessionId: sL,
          lines: bagLines(left),
          bag: true,
        );
        payL['fase2'] = stl.brief;
      }
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    final snapL = await c.ledgerSnap(left);
    final snapR = await c.ledgerSnap(right);
    var rStillOpen = false;
    if (sR != null && sR.startsWith('cs_')) {
      final o = await c.sessionOracle(sR, checkoutUrl: hits[1].checkoutUrl);
      rStillOpen = o['open_payable'] == true;
    }
    final rightPago = ((snapR['orders'] as List?) ?? []).any((o) {
      if (o is! Map) return false;
      return '${o['status']}'.toLowerCase() == 'pago';
    });
    final intact = !rightPago && (rStillOpen || (sR ?? '').startsWith('cs_'));
    c.probe(
      id: 'C4',
      poco: 'EM-C',
      payload:
          'Future.wait bags disjuntos 2 cs_; pagar 1 — outro intacto (OK)',
      http: {
        'hits': hits.map((h) => h.brief).toList(),
        'pay_left': payL,
      },
      bd: {'left': snapL, 'right': snapR, 'right_open': rStillOpen},
      verdict: intact ? 'FAIL' : 'HOLD',
      lens: 'EM-C',
      classeNova: true,
    );
    if (!intact) {
      c.hold(
        id: 'P1-C4',
        lens: 'EM-C',
        severity: 'P1',
        title: 'Bag disjunto: pagar um afectou o outro',
        actor: 'buyer JWT',
        pre: '2 bags sem overlap de linhas',
        repro: 'CPI paralelo; payCheckout4242 só o da esquerda',
        expected: 'direita intacta (cs_ open / não pago)',
        obtained: {
          'rightPago': rightPago,
          'right_open': rStillOpen,
          'sR': sR,
        },
      );
    }
  } else {
    skipProbe(
      c,
      id: 'C4',
      poco: 'EM-C',
      lens: 'EM-C',
      payload: 'bags disjuntos',
      why: 'mkSkus',
      classeNova: true,
    );
  }
}
