/// RED TEAM CEGO DZ pass1 — saco/mutex/expand re-claim/preço/stock pós-DTDY.
/// Matriz A1–A5 · B1–B7 · C1–C5 · D1–D3. Sem correções. Oráculo cs_ open/payable.
import 'dart:io';

import '_rtdz.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('DZ pass1 staging=${c.url} prefix=$prefix');
  if (c.stripeTestKey == null) {
    stdout.writeln('WARN no sk_test_ — oráculo via checkout URL + settle');
  }
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.ensureBuyer3();
  final liveOpsBuyerId = envRequire(loadEnv(), 'LIVE_OPS_TEST_BUYER_ID');
  // Buyer fresco — LIVE_OPS / DT buyer3 podem estar no tecto 60/h.
  c.buyerId = c.buyer3Id;
  c.buyerJwt = c.buyer3Jwt;
  c.note('actors', 'ids', {
    'b': c.buyerId,
    's': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
    'b3': c.buyer3Id,
    'liveOpsBuyer': liveOpsBuyerId,
    'cpi_actor': 'buyer3-rtdz',
  });
  final wallets0 = await c.wallets();
  c.note('DZ8.wallet.pre', 'baseline', wallets0, lens: 'DZ8', well: 'DZ-D');

  await dzAClaimMutex(c);
  await dzBOverlapRaces(c);
  await dzCPriceStockOff(c);
  await dzDCaixaCross(c, wallets0);

  final wallets1 = await c.wallets();
  c.note('DZ8.wallet.post', 'após probes', {
    'pre': wallets0,
    'post': wallets1,
  }, lens: 'DZ8', well: 'DZ-D');

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

/// DZ-A Claim / mutex (≥5)
Future<void> dzAClaimMutex(Rtdb c) async {
  c.wellsTried.add('DZ-A');

  // A1 reclaim cs_ morta + buyer2 CPI
  final a1 = await mkSkus(c, n: 1, tag: 'a1-dead-cs', qty: 2);
  if (a1.length == 1) {
    final first = await c.checkout(
      orderId: a1.first.oid,
      productId: a1.first.pid,
      amount: 1,
    );
    c.trackSession(first);
    final plant = await c.plantClaim(
      a1.first.oid,
      'cs_test_deaddeaddeaddeaddead12',
    );
    final actor2 = await c.checkout(
      orderId: a1.first.oid,
      productId: a1.first.pid,
      amount: 1,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    );
    final retry = await c.checkout(
      orderId: a1.first.oid,
      productId: a1.first.pid,
      amount: 1,
    );
    c.trackSession(retry);
    final row = await c.orderRow(a1.first.oid);
    final sid = '${row?['stripe_checkout_session_id'] ?? ''}';
    final deadStuck = sid.contains('deaddead') && !retry.ok;
    final stolen = actor2.ok && (actor2.sessionId ?? '').startsWith('cs_');
    c.note('A1.dead', 'cs_ morta reclaim + actor2', {
      'first': first.brief,
      'plant': plant.brief,
      'actor2': actor2.brief,
      'retry': retry.brief,
      'stored': sid,
    }, lens: 'DZ7', well: 'DZ-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A1',
      poco: 'DZ-A',
      lens: 'DZ7',
      payload: 'plant cs_test_dead; buyer2 CPI; owner retry',
      http: {'actor2': actor2.brief, 'retry': retry.brief},
      bd: sid,
      isHold: deadStuck || stolen,
      holdId: stolen ? 'P1-A1' : 'P2-A1',
      severity: stolen ? 'P1' : 'P2',
      title: stolen
          ? '2.º actor reclaimou cs_ morta de order alheia'
          : 'cs_ morta bloqueia reclaim (DoS checkout)',
      actor: 'buyer JWT + buyer2',
      pre: 'stripe_checkout_session_id=cs_test_dead…',
      repro: 'CPI buyer2; CPI owner',
      expected: 'buyer2 400; owner reclaim + nova cs_',
      obtained: {
        'actor2': actor2.brief,
        'retry': retry.brief,
        'stored': sid,
      },
      blockId: 'A1-DEAD-CS',
      blockTitle: 'cs_ morta reclaim OK / 2.º actor negado',
    );
  } else {
    skipProbe(c, id: 'A1', poco: 'DZ-A', lens: 'DZ7', payload: 'cs_ morta', why: 'mkSkus empty');
  }
  await pause();

  // A2 claiming futuro / malform (TTL exacto = anti-atrofia, 1 residual)
  final a2 = await mkSkus(c, n: 1, tag: 'a2-malform', qty: 2);
  if (a2.length == 1) {
    final futureMs =
        DateTime.now().millisecondsSinceEpoch + 365 * 24 * 3600 * 1000;
    await c.plantClaim(a2.first.oid, 'claiming:$futureMs:malformtok12ab');
    final rpcJwt = await c.rpc(
      'batata_bag_checkout_claim',
      {
        'p_order_ids': [a2.first.oid],
        'p_claim_token':
            'claiming:${DateTime.now().millisecondsSinceEpoch}:jwttry12abcd',
      },
      jwt: c.buyerJwt,
    );
    final hit = await c.checkout(
      orderId: a2.first.oid,
      productId: a2.first.pid,
      amount: 1,
    );
    c.trackSession(hit);
    final row = await c.orderRow(a2.first.oid);
    final sid = '${row?['stripe_checkout_session_id'] ?? ''}';
    final stuck = sid.startsWith('claiming:') && !hit.ok;
    final incoherent = hit.ok &&
        (hit.sessionId ?? '').startsWith('cs_') &&
        sid.startsWith('claiming:');
    recordHoldOrFail(
      c: c,
      probeId: 'A2',
      poco: 'DZ-A',
      lens: 'DZ7',
      payload: 'claiming:<now+1y>:malformtok12ab + CPI; RPC JWT',
      http: {'rpcJwt': rpcJwt.brief, 'cpi': hit.brief},
      bd: sid,
      isHold: stuck || incoherent,
      holdId: 'P2-A2',
      severity: 'P2',
      title: stuck
          ? 'claiming futuro/malform prende o cadeado'
          : 'claiming futuro: CPI cs_ mas ledger ainda claiming',
      actor: 'buyer JWT (plant service_role observação)',
      pre: 'claiming futuro malform',
      repro: 'CPI após claiming futuro',
      expected: 'futuro=órfão; reclaim + cs_ coerente; RPC JWT 403',
      obtained: {'hit': hit.brief, 'stored': sid, 'rpcJwt': rpcJwt.status},
      blockId: 'A2-FUTURE',
      blockTitle: 'claiming futuro/malform reclaim coerente',
    );
  } else {
    skipProbe(c, id: 'A2', poco: 'DZ-A', lens: 'DZ7', payload: 'claiming malform', why: 'mkSkus');
  }
  await pause();

  // A3 timeout cliente 100ms ∥ server completa ∥ retry 800ms (órfãs)
  final a3 = await mkSkus(c, n: 2, tag: 'a3-to100', qty: 2);
  if (a3.length == 2) {
    final lines = bagLines(a3);
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
      '${(await c.orderRow(a3[0].oid))?['stripe_checkout_session_id'] ?? ''}',
      '${(await c.orderRow(a3[1].oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final sids = {
      ...openCs(triple),
      ...stored.where((s) => s.startsWith('cs_')),
    };
    final payablePack = await openPayableCount(c, sids, urls: urlsFromHits(triple));
    final payable = payablePack.$1;
    final payableDetail = payablePack.$2;
    final briefs = triple.map((h) => h.brief).toList();
    c.note('A3.timeout100', 'timeout 100ms ∥ complete ∥ retry 800ms', {
      'briefs': briefs,
      'stored': stored,
      'payable': payable,
      'payableDetail': payableDetail,
      'sids': sids.toList(),
      'reused': triple.map((h) => h.reused).toList(),
    }, lens: 'DZ4', well: 'DZ-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A3',
      poco: 'DZ-A',
      lens: 'DZ4',
      payload:
          'Future.wait bag timeout 100ms ∥ server complete ∥ retry +800ms',
      http: briefs,
      bd: {
        'stored': stored,
        'payable': payable,
        'sids': sids.toList(),
        'oracle': payableDetail,
      },
      isHold: payable >= 2,
      holdId: payable >= 2 ? 'P0-A3' : 'P1-A3',
      severity: payable >= 2 ? 'P0' : 'P1',
      title: 'Timeout 100ms∥complete∥retry 800ms = ≥2 cs_ open/payable',
      actor: 'buyer JWT',
      pre: '2-line bag; client abort 100ms while server continues (DTDY wait 40×200ms)',
      repro: 'Future.wait timeout 100ms ∥ bag complete ∥ retry 800ms',
      expected: '≤1 cs_ open/payable; órfãs expired; 2.º reuse/contention',
      obtained: {'sids': sids.toList(), 'stored': stored, 'payable': payable},
      blockId: 'A3-TIMEOUT100',
      blockTitle: 'timeout 100ms∥complete∥retry ≤1 Session open/payable',
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A3',
      poco: 'DZ-A',
      lens: 'DZ4',
      payload: 'Future.wait timeout 100ms∥complete∥retry',
      why: 'mkSkus',
      classeNova: true,
    );
  }
  await pause();

  // A4 2 bags disjuntos paralelo (2 cs_ OK se sem overlap)
  final a4a = await mkSkus(c, n: 2, tag: 'a4-disj-a', qty: 2, price: 7);
  final a4b = await mkSkus(c, n: 2, tag: 'a4-disj-b', qty: 2, price: 8);
  if (a4a.length == 2 && a4b.length == 2) {
    final jwtMutex = await c.mutexPeek(jwt: c.buyerJwt);
    final hits = await parallel([
      c.checkoutBag(lines: bagLines(a4a), amount: 1),
      c.checkoutBag(lines: bagLines(a4b), amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    final sids = openCs(hits);
    final payablePack = await openPayableCount(c, sids, urls: urlsFromHits(hits));
    final payable = payablePack.$1;
    final briefs = hits.map((h) => h.brief).toList();
    final storedA = [
      for (final r in a4a)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final storedB = [
      for (final r in a4b)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final svcMutex = await c.mutexPeek(service: true);
    final mutexReadable = jwtMutex.ok && jwtMutex.list.isNotEmpty;
    c.note('A4.disjoint', '2 bags disjuntos mesmo buyer ∥', {
      'briefs': briefs,
      'sids': sids.toList(),
      'payable': payable,
      'storedA': storedA,
      'storedB': storedB,
      'jwtMutex': jwtMutex.brief,
      'svcMutex': svcMutex.brief,
    }, lens: 'DZ2', well: 'DZ-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A4',
      poco: 'DZ-A',
      lens: 'DZ2',
      payload: 'Future.wait 2 bags disjuntos mesmo buyer (2+2 SKUs)',
      http: {'briefs': briefs, 'jwtMutex': jwtMutex.brief},
      bd: {
        'sids': sids.toList(),
        'payable': payable,
        'storedA': storedA,
        'storedB': storedB,
        'svcMutex': svcMutex.brief,
      },
      isHold: mutexReadable,
      holdId: 'P2-A4',
      severity: 'P2',
      title: 'JWT lê batata_checkout_mutex (RLS/GRANT)',
      actor: 'buyer JWT',
      pre: '2 bags sem linhas em comum',
      repro: 'Future.wait checkoutBag A ∥ checkoutBag B',
      expected:
          'mutex serializa; JWT sem GRANT; 2 cs_ só após release é documentado',
      obtained: {
        'sids': sids.toList(),
        'payable': payable,
        'jwtMutex': jwtMutex.status,
        'briefs': briefs,
      },
      blockId: 'A4-DISJOINT',
      blockTitle: 'bags disjuntos: mutex serializou; JWT sem GRANT',
    );
  } else {
    skipProbe(c, id: 'A4', poco: 'DZ-A', lens: 'DZ2', payload: 'bags disjuntos', why: 'mkSkus');
  }
  await pause();

  // A5 JWT PATCH cs_ + RPC claim token alheio
  final a5 = await mkSkus(c, n: 1, tag: 'a5-steal-claim', qty: 2);
  if (a5.length == 1) {
    final tok =
        'claiming:${DateTime.now().millisecondsSinceEpoch}:stealclaim12ab';
    await c.plantClaim(a5.first.oid, tok);
    final jwtPatch = await c.rest(
      'PATCH',
      'orders?id=eq.${a5.first.oid}',
      jwt: c.buyerJwt,
      body: {'stripe_checkout_session_id': 'cs_test_jwtwritewithoutclaim99'},
    );
    final stealRpc = await c.rpc(
      'batata_bag_checkout_claim',
      {
        'p_order_ids': [a5.first.oid],
        'p_claim_token': tok,
      },
      jwt: c.buyer2Jwt,
    );
    final stealCpi = await c.checkout(
      orderId: a5.first.oid,
      productId: a5.first.pid,
      amount: 1,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    );
    final owner = await c.checkout(
      orderId: a5.first.oid,
      productId: a5.first.pid,
      amount: 1,
    );
    c.trackSession(owner);
    final row = await c.orderRow(a5.first.oid);
    final sid = '${row?['stripe_checkout_session_id'] ?? ''}';
    final jwtWrote = jwtPatch.ok;
    final stolen = stealCpi.ok && (stealCpi.sessionId ?? '').startsWith('cs_');
    final rpcOk = stealRpc.ok;
    recordHoldOrFail(
      c: c,
      probeId: 'A5',
      poco: 'DZ-A',
      lens: 'DZ7',
      payload: 'JWT PATCH cs_ sem claim; buyer2 RPC claim token alheio + CPI',
      http: {
        'jwtPatch': jwtPatch.brief,
        'stealRpc': stealRpc.brief,
        'stealCpi': stealCpi.brief,
        'owner': owner.brief,
      },
      bd: sid,
      isHold: jwtWrote || stolen || rpcOk,
      holdId: (jwtWrote || stolen) ? 'P1-A5' : 'P2-A5',
      severity: (jwtWrote || stolen) ? 'P1' : 'P2',
      title: jwtWrote
          ? 'JWT escreveu cs_ sem claim próprio'
          : stolen
              ? 'buyer2 CPI com claim token alheio'
              : 'buyer2 RPC claim token alheio aceite',
      actor: 'buyer JWT + buyer2',
      pre: 'claiming plantado no owner',
      repro: 'JWT PATCH cs_; RPC claim buyer2; CPI buyer2',
      expected: 'JWT PATCH 403; RPC buyer2 403; CPI buyer2 400; owner cs_ coerente',
      obtained: {
        'jwtPatch': jwtPatch.status,
        'stealRpc': stealRpc.status,
        'stealCpi': stealCpi.brief,
        'owner': owner.brief,
        'stored': sid,
      },
      blockId: 'A5-STEAL',
      blockTitle: 'JWT write negado; claim alheio negado',
    );
  } else {
    skipProbe(c, id: 'A5', poco: 'DZ-A', lens: 'DZ7', payload: 'claim alheio', why: 'mkSkus');
  }
}

/// DZ-B Overlaps novos (≥7) — classe_nova
Future<void> dzBOverlapRaces(Rtdb c) async {
  c.wellsTried.add('DZ-B');

  Future<void> overlapProbe({
    required String id,
    required String payload,
    required List<({String oid, String pid, double price})> skus,
    required List<HttpHit> hits,
    required String pre,
    required String titleIfTwo,
    String lens = 'DZ3',
    bool classeNova = true,
  }) async {
    for (final h in hits) {
      c.trackSession(h);
    }
    if (hits.isNotEmpty && hits.every(rateLimited)) {
      skipProbe(
        c,
        id: id,
        poco: 'DZ-B',
        lens: lens,
        payload: payload,
        why: '429 rate limit — não é prova mutex',
        classeNova: classeNova,
      );
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    final sids = openCs(hits);
    final payablePack = await openPayableCount(c, sids, urls: urlsFromHits(hits));
    final payable = payablePack.$1;
    final payableDetail = payablePack.$2;
    final briefs = hits.map((h) => h.brief).toList();
    final stored = [
      for (final r in skus)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final dualOpen = payable >= 2;
    c.note('$id.overlap', payload, {
      'sids': sids.toList(),
      'payable': payable,
      'oracle': payableDetail,
      'briefs': briefs,
      'stored': stored,
      'reused': hits.map((h) => h.reused).toList(),
      'http200': hits.map((h) => h.status).toList(),
    }, lens: lens, well: 'DZ-B');
    recordHoldOrFail(
      c: c,
      probeId: id,
      poco: 'DZ-B',
      lens: lens,
      payload: payload,
      http: briefs,
      bd: {
        'sids': sids.toList(),
        'stored': stored,
        'payable': payable,
        'oracle': payableDetail,
        'reused': hits.map((h) => h.reused).toList(),
        'contention': hits.map(contention).toList(),
      },
      isHold: dualOpen,
      holdId: dualOpen ? 'P1-1' : 'P1-$id',
      severity: 'P1',
      title: titleIfTwo,
      actor: 'buyer JWT',
      pre: pre,
      repro: payload,
      expected:
          '≤1 cs_ ainda open/payable; 2.º contention/reuse/400; expand: menor expired',
      obtained: {
        'sids': sids.toList(),
        'payable': payable,
        'stored': stored,
        'briefs': briefs,
        'oracle': payableDetail,
      },
      blockId: '$id-OVERLAP',
      blockTitle: '$id ≤1 cs_ open/payable / 2.º contention',
      classeNova: classeNova,
      countFinding: dualOpen && !c.findings.any((f) => f['id'] == 'P1-1'),
    );
  }

  // B1 bag 6∥4 stagger 0ms E 50ms (reteste DT — oráculo open/payable por timing)
  await pause();
  final b1 = await mkSkus(c, n: 6, tag: 'b1-6x4-0ms', qty: 2, price: 9);
  List<HttpHit> b1hits0 = const [];
  List<HttpHit> b1hits50 = const [];
  if (b1.length == 6) {
    final six = bagLines(b1);
    final mid4 = bagLines(b1.sublist(1, 5));
    b1hits0 = await parallel([
      c.checkoutBag(lines: six, amount: 1),
      c.checkoutBag(lines: mid4, amount: 1),
    ]);
    for (final h in b1hits0) {
      c.trackSession(h);
    }
  }
  await pause();
  final b1b = await mkSkus(c, n: 6, tag: 'b1-6x4-50ms', qty: 2, price: 9);
  if (b1b.length == 6) {
    final six = bagLines(b1b);
    final mid4 = bagLines(b1b.sublist(1, 5));
    final first = c.checkoutBag(lines: six, amount: 1);
    final second = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkoutBag(lines: mid4, amount: 1);
    });
    b1hits50 = await parallel([first, second]);
    for (final h in b1hits50) {
      c.trackSession(h);
    }
  }
  if (b1hits0.isEmpty && b1hits50.isEmpty) {
    skipProbe(
      c,
      id: 'B1',
      poco: 'DZ-B',
      lens: 'DZ1',
      payload: 'Future.wait bag 6∥4 0ms+50ms',
      why: 'mkSkus',
      classeNova: true,
    );
  } else if ([...b1hits0, ...b1hits50].every(rateLimited) &&
      [...b1hits0, ...b1hits50].isNotEmpty) {
    skipProbe(
      c,
      id: 'B1',
      poco: 'DZ-B',
      lens: 'DZ1',
      payload: 'Future.wait bag 6∥4 0ms+50ms',
      why: '429 rate limit — não é prova mutex',
      classeNova: true,
    );
  } else {
    await Future<void>.delayed(const Duration(seconds: 2));
    final pack0 = await openPayableCount(
      c,
      openCs(b1hits0),
      urls: urlsFromHits(b1hits0),
    );
    final pack50 = await openPayableCount(
      c,
      openCs(b1hits50),
      urls: urlsFromHits(b1hits50),
    );
    final dual = pack0.$1 >= 2 || pack50.$1 >= 2;
    final stored0 = [
      for (final r in b1)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final stored50 = [
      for (final r in b1b)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    recordHoldOrFail(
      c: c,
      probeId: 'B1',
      poco: 'DZ-B',
      lens: 'DZ1',
      payload:
          'Future.wait bag 6∥4 stagger 0ms E 50ms (BCDE subset; reteste DT)',
      http: {
        't0': b1hits0.map((h) => h.brief).toList(),
        't50': b1hits50.map((h) => h.brief).toList(),
      },
      bd: {
        'payable0': pack0.$1,
        'payable50': pack50.$1,
        'oracle0': pack0.$2,
        'oracle50': pack50.$2,
        'sids0': openCs(b1hits0).toList(),
        'sids50': openCs(b1hits50).toList(),
        'stored0': stored0,
        'stored50': stored50,
      },
      isHold: dual,
      holdId: 'P1-1',
      severity: 'P1',
      title: 'Overlap 6∥4 (0ms e/ou 50ms): 2 cs_ ainda open/payable',
      actor: 'buyer JWT',
      pre: '6+6 SKUs; ABCDEF∥BCDE a t=0 e t=50ms',
      repro: 'Future.wait 6∥4 0ms; depois 6∥4 stagger 50ms',
      expected: 'cada timing ≤1 cs_ open/payable (reuse/contention/400)',
      obtained: {
        'payable0': pack0.$1,
        'payable50': pack50.$1,
        'sids0': openCs(b1hits0).toList(),
        'sids50': openCs(b1hits50).toList(),
      },
      blockId: 'B1-OVERLAP',
      blockTitle: 'B1 6∥4 0ms+50ms ≤1 cs_ open/payable',
      classeNova: true,
      countFinding: dual && !c.findings.any((f) => f['id'] == 'P1-1'),
    );
  }

  // B2 bag AB∥BC∥CA (triângulo — 3 CPI)
  await pause();
  final b2 = await mkSkus(c, n: 3, tag: 'b2-tri', qty: 2, price: 10);
  if (b2.length == 3) {
    final ab = bagLines([b2[0], b2[1]]);
    final bc = bagLines([b2[1], b2[2]]);
    final ca = bagLines([b2[2], b2[0]]);
    final hits = await parallel([
      c.checkoutBag(lines: ab, amount: 1),
      c.checkoutBag(lines: bc, amount: 1),
      c.checkoutBag(lines: ca, amount: 1),
    ]);
    await overlapProbe(
      id: 'B2',
      payload: 'Future.wait bag AB ∥ bag BC ∥ bag CA (triângulo 3 CPI)',
      skus: b2,
      hits: hits,
      pre: '3 SKUs; AB∥BC∥CA — cada par partilha 1 linha',
      titleIfTwo: 'Triângulo AB∥BC∥CA: ≥2 Sessions úteis',
    );
  } else {
    skipProbe(
      c,
      id: 'B2',
      poco: 'DZ-B',
      lens: 'DZ3',
      payload: 'Future.wait AB∥BC∥CA',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B3 bag ABCDE∥ single C (índice do meio)
  await pause();
  final b3 = await mkSkus(c, n: 5, tag: 'b3-mid-c', qty: 2, price: 8);
  if (b3.length == 5) {
    final five = bagLines(b3);
    final midC = b3[2]; // A=0 B=1 C=2 — meio
    final hits = await parallel([
      c.checkoutBag(lines: five, amount: 1),
      c.checkout(orderId: midC.oid, productId: midC.pid, amount: 1),
    ]);
    await overlapProbe(
      id: 'B3',
      payload: 'Future.wait bag ABCDE ∥ CPI single C (índice do meio)',
      skus: b3,
      hits: hits,
      pre: '5 SKUs; bag ABCDE ∥ CPI C (meio)',
      titleIfTwo: 'ABCDE∥single-C meio: 2 cs_ ainda open/payable',
    );
  } else {
    skipProbe(
      c,
      id: 'B3',
      poco: 'DZ-B',
      lens: 'DZ3',
      payload: 'Future.wait ABCDE∥single C meio',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B4 2× bag idêntico (mesmo set, ordem UUID invertida)
  await pause();
  final b4 = await mkSkus(c, n: 3, tag: 'b4-uuid-inv', qty: 2, price: 11);
  if (b4.length == 3) {
    final sorted = [...b4]
      ..sort((a, b) => a.oid.compareTo(b.oid));
    final fwd = bagLines(sorted);
    final rev = bagLines(sorted.reversed);
    final hits = await parallel([
      c.checkoutBag(lines: fwd, amount: 1),
      c.checkoutBag(lines: rev, amount: 1),
    ]);
    await overlapProbe(
      id: 'B4',
      payload:
          'Future.wait 2× bag idêntico ordem UUID invertida (delay 0)',
      skus: b4,
      hits: hits,
      pre: '3 SKUs; mesmo set sorted vs reversed UUID',
      titleIfTwo: '2× bag UUID invertido: 2 Sessions úteis',
    );
  } else {
    skipProbe(
      c,
      id: 'B4',
      poco: 'DZ-B',
      lens: 'DZ3',
      payload: 'Future.wait 2× bag UUID invertido',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B5 bag∥single∥bag (3 corrotinas; single stagger 200ms)
  await pause();
  final b5 = await mkSkus(c, n: 3, tag: 'b5-bsb', qty: 2, price: 12);
  if (b5.length == 3) {
    final three = bagLines(b5);
    final mid = b5[1];
    final bag1 = c.checkoutBag(lines: three, amount: 1);
    final single = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return c.checkout(
        orderId: mid.oid,
        productId: mid.pid,
        amount: 1,
      );
    });
    final bag2 = c.checkoutBag(lines: three, amount: 1);
    final hits = await parallel([bag1, single, bag2]);
    await overlapProbe(
      id: 'B5',
      payload:
          'Future.wait bag ∥ single +200ms ∥ bag (3 corrotinas mesmo set)',
      skus: b5,
      hits: hits,
      pre: '3 SKUs; bag∥single-B@200ms∥bag',
      titleIfTwo: 'bag∥single∥bag: ≥2 Sessions úteis',
      lens: 'DZ4',
    );
  } else {
    skipProbe(
      c,
      id: 'B5',
      poco: 'DZ-B',
      lens: 'DZ4',
      payload: 'Future.wait bag∥single∥bag',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B6 staggered: bag full → sleep 50ms → subset
  await pause();
  final b6 = await mkSkus(c, n: 4, tag: 'b6-stag50', qty: 2, price: 13);
  if (b6.length == 4) {
    final full = bagLines(b6);
    final sub = bagLines(b6.sublist(0, 2));
    final first = c.checkoutBag(lines: full, amount: 1);
    final second = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkoutBag(lines: sub, amount: 1);
    });
    final hits = await parallel([first, second]);
    await overlapProbe(
      id: 'B6',
      payload: 'Future.wait bag full → sleep 50ms → subset 2-line',
      skus: b6,
      hits: hits,
      pre: '4 SKUs; bag ABCD t=0 ∥ bag AB t=50ms',
      titleIfTwo: 'Stagger 50ms full→subset: 2 Sessions úteis',
      lens: 'DZ4',
    );
  } else {
    skipProbe(
      c,
      id: 'B6',
      poco: 'DZ-B',
      lens: 'DZ4',
      payload: 'Future.wait staggered 50ms full→subset',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B7 staggered: subset first → sleep 50ms → superset (expand)
  await pause();
  final b7 = await mkSkus(c, n: 4, tag: 'b7-expand50', qty: 2, price: 14);
  if (b7.length == 4) {
    final sub = bagLines(b7.sublist(0, 2));
    final full = bagLines(b7);
    final first = c.checkoutBag(lines: sub, amount: 1);
    final second = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkoutBag(lines: full, amount: 1);
    });
    final hits = await parallel([first, second]);
    await overlapProbe(
      id: 'B7',
      payload:
          'Future.wait subset first → sleep 50ms → superset expand + re-claim',
      skus: b7,
      hits: hits,
      pre: '4 SKUs; bag AB t=0 ∥ bag ABCD t=50ms (expand; menor tem de expirar)',
      titleIfTwo: 'Expand 50ms subset→superset: 2 cs_ ainda open/payable',
      lens: 'DZ3',
    );
  } else {
    skipProbe(
      c,
      id: 'B7',
      poco: 'DZ-B',
      lens: 'DZ4',
      payload: 'Future.wait staggered 50ms subset→superset',
      why: 'mkSkus',
      classeNova: true,
    );
  }
}

/// DZ-C Preço / stock / off (≥5)
Future<void> dzCPriceStockOff(Rtdb c) async {
  c.wellsTried.add('DZ-C');

  // C1 underpay body vs catálogo
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
    poco: 'DZ-C',
    lens: 'DZ6',
    payload: 'body total_eur=0 item_price=0.01 amount=0 (SKU 18€ CTT)',
    http: underHit?.brief,
    bd: {'amt': amt},
    isHold: under,
    holdId: 'P0-C1',
    severity: 'P0',
    title: 'body hostil baixou amount_total abaixo do catálogo',
    actor: 'buyer JWT',
    pre: 'SKU 18€',
    repro: 'CPI extras total_eur/item_price',
    expected: 'amount ≈ catálogo (18€+portes+protecção); extras ignorados',
    obtained: {'amt': amt, 'hit': underHit?.brief},
    blockId: 'C1-UNDERPAY',
    blockTitle: 'total_eur/item_price ignorados; amount catálogo',
  );

  // C2 coupon / portes PATCH com Session open
  await pause();
  final c2sku = await mkSkus(
    c,
    n: 2,
    tag: 'c2-ship',
    qty: 2,
    price: 15,
    shipping: 'entrega em mão',
  );
  HttpHit? openHit;
  HttpHit? patchShip;
  HttpHit? recpiCtt;
  HttpHit? couponHit;
  int? openAmt;
  int? recpiAmt;
  int? couponAmt;
  String? shipAfter;
  if (c2sku.length == 2) {
    openHit = await c.checkoutBag(
      lines: bagLines(c2sku),
      amount: 1,
      shipping: 'mao',
    );
    c.trackSession(openHit);
    openAmt = openHit.amountTotal;
    patchShip = await c.rest(
      'PATCH',
      'orders?id=eq.${c2sku.first.oid}',
      jwt: c.buyerJwt,
      body: {'shipping_method': 'ctt'},
    );
    final rowAfter = await c.orderRow(c2sku.first.oid);
    shipAfter = '${rowAfter?['shipping_method'] ?? ''}';
    recpiCtt = await c.checkoutBag(
      lines: bagLines(c2sku),
      amount: 1,
      shipping: 'ctt',
    );
    c.trackSession(recpiCtt);
    recpiAmt = recpiCtt.amountTotal;
    couponHit = await c.checkoutBag(
      lines: bagLines(c2sku),
      amount: 1,
      extra: {
        'discount_pct': 90,
        'coupon': 'SAVE90',
        'promo_code': 'SAVE90',
        'total_eur': 0.01,
      },
    );
    c.trackSession(couponHit);
    couponAmt = couponHit.amountTotal;
  }
  final shipReallyChanged = (shipAfter ?? '').toLowerCase().contains('ctt') &&
      !(shipAfter ?? '').toLowerCase().contains('mão') &&
      !(shipAfter ?? '').toLowerCase().contains('mao');
  final cheaper = (couponAmt != null &&
          openAmt != null &&
          couponAmt < openAmt * 0.7) ||
      (recpiAmt != null && openAmt != null && recpiAmt + 50 < openAmt);
  c.note('C2.session-open', 'portes/coupon com Session open', {
    'open': openHit?.brief,
    'openAmt': openAmt,
    'patchShip': patchShip?.brief,
    'shipAfter': shipAfter,
    'recpi': recpiCtt?.brief,
    'recpiAmt': recpiAmt,
    'coupon': couponHit?.brief,
    'couponAmt': couponAmt,
  }, lens: 'DZ6', well: 'DZ-C');
  recordHoldOrFail(
    c: c,
    probeId: 'C2',
    poco: 'DZ-C',
    lens: 'DZ6',
    payload: 'Session open → JWT PATCH shipping=ctt; re-CPI ctt; coupon SAVE90',
    http: {
      'open': openHit?.brief,
      'patch': patchShip?.brief,
      'recpi': recpiCtt?.brief,
      'coupon': couponHit?.brief,
    },
    bd: {
      'openAmt': openAmt,
      'recpiAmt': recpiAmt,
      'couponAmt': couponAmt,
      'shipAfter': shipAfter,
      'shipReallyChanged': shipReallyChanged,
    },
    isHold: shipReallyChanged || cheaper,
    holdId: cheaper ? 'P0-C2' : 'P2-C2',
    severity: cheaper ? 'P0' : 'P2',
    title: cheaper
        ? 'coupon/desconto baixou Session com cs_ já aberta'
        : 'JWT alterou shipping_method com Session open',
    actor: 'buyer JWT',
    pre: 'bag 2 linhas Session open (mão)',
    repro: 'PATCH shipping; CPI coupon/discount_pct',
    expected: 'shipping immutable na BD; amount estável ou expire+requote',
    obtained: {
      'openAmt': openAmt,
      'recpiAmt': recpiAmt,
      'couponAmt': couponAmt,
      'patch': patchShip?.status,
      'shipAfter': shipAfter,
    },
    blockId: 'C2-SHIP-COUPON',
    blockTitle: 'Session open: shipping immutable na BD; coupon ignorado',
  );

  // C3 2 buyers última unidade
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
      final payablePack = await openPayableCount(c, openCs(hits), urls: urlsFromHits(hits));
      final payable = payablePack.$1;
      recordHoldOrFail(
        c: c,
        probeId: 'C3',
        poco: 'DZ-C',
        lens: 'DZ5',
        payload: 'Future.wait 2 buyers CPI última unidade qty=1',
        http: briefs,
        bd: {'ok': ok, 'payable': payable, 'o1': o1, 'o2': o2},
        isHold: ok >= 2 || payable >= 2,
        holdId: 'P0-C3',
        severity: 'P0',
        title: '2 buyers Session na última unidade',
        actor: 'buyer + buyer2 JWT',
        pre: 'quantity=1; 2 orders',
        repro: 'Future.wait 2× CPI',
        expected: '1 Session + 1 stock block (insert ou CPI)',
        obtained: {'ok': ok, 'payable': payable, 'briefs': briefs},
        blockId: 'C3-LAST',
        blockTitle: 'última unidade ≤1 Session',
      );
    } else {
      recordHoldOrFail(
        c: c,
        probeId: 'C3',
        poco: 'DZ-C',
        lens: 'DZ5',
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
    skipProbe(c, id: 'C3', poco: 'DZ-C', lens: 'DZ5', payload: '2 buyers qty=1', why: 'createProduct');
  }

  // C4 unlist∥CPI
  await pause();
  final ul = await mkSkus(c, n: 1, tag: 'c4-unlist', qty: 1, price: 13);
  if (ul.length == 1) {
    final u = ul.first;
    final hits = await parallel([
      c.checkout(orderId: u.oid, productId: u.pid, amount: 1),
      c.rest(
        'PATCH',
        'products?id=eq.${u.pid}',
        jwt: c.sellerJwt,
        body: {'list_on_marketplace': false, 'quantity': 0},
      ),
    ]);
    c.trackSession(hits[0]);
    final ck = hits[0];
    final patch = hits[1];
    final prod = await c.productRow(u.pid);
    final dual = ck.ok &&
        prod?['list_on_marketplace'] == false &&
        numOf(prod?['quantity']) == 0 &&
        (ck.sessionId ?? '').startsWith('cs_');
    recordHoldOrFail(
      c: c,
      probeId: 'C4',
      poco: 'DZ-C',
      lens: 'DZ5',
      payload: 'Future.wait CPI ∥ unlist+qty=0',
      http: {'ck': ck.brief, 'patch': patch.brief},
      bd: prod,
      isHold: dual,
      holdId: 'P1-C4',
      severity: 'P1',
      title: 'Session aberta sobre SKU unlisted qty=0',
      actor: 'buyer JWT ∥ seller JWT',
      pre: 'qty=1 listed',
      repro: 'Future.wait CPI ∥ PATCH unlist qty=0',
      expected:
          'CPI 400 not listed OU unlist perde a corrida (Session ok, still listed)',
      obtained: {
        'ck': ck.brief,
        'listed': prod?['list_on_marketplace'],
        'qty': prod?['quantity'],
      },
      blockId: 'C4-UNLIST',
      blockTitle: 'unlist∥checkout sem Session+qty0 simultâneo',
    );
  } else {
    skipProbe(c, id: 'C4', poco: 'DZ-C', lens: 'DZ5', payload: 'unlist∥CPI', why: 'mkSkus');
  }

  // C5 off-platform NOVO: multibanco / objecto ifthenpay / contra_reembolso
  // (não wrap x/via, não array ["MB WAY"])
  await pause();
  HttpHit? mbHit;
  HttpHit? objHit;
  HttpHit? codHit;
  String? mbPm;
  String? objPm;
  String? codPm;
  String? mbSid;
  String? objSid;
  String? codSid;
  final mbPid = await c.createProduct(
    title: '$prefix-c5-multibanco',
    qty: 2,
    price: 17,
  );
  if (mbPid != null) {
    var oid = await c.insertOrder(
      productId: mbPid,
      price: 17,
      jwt: c.buyerJwt,
      payment: 'multibanco',
    );
    if (oid == null) {
      final svcIns = await c.rest('POST', 'orders', service: true, body: {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': mbPid,
        'price_total': 17,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'multibanco',
        'shipping_method': 'entrega em mão',
      });
      oid = svcIns.firstId;
      if (oid != null) c.createdOrderIds.add(oid);
    }
    if (oid != null) {
      mbPm = '${(await c.orderRow(oid))?['payment_method'] ?? ''}';
      mbHit = await c.checkout(orderId: oid, productId: mbPid, amount: 1);
      c.trackSession(mbHit);
      mbSid = mbHit.sessionId;
    }
  }
  final objPid = await c.createProduct(
    title: '$prefix-c5-ifthenpay',
    qty: 2,
    price: 17,
  );
  if (objPid != null) {
    final svcIns = await c.rest('POST', 'orders', service: true, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': objPid,
      'price_total': 17,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': '{"psp":"ifthenpay","entity":"11234"}',
      'shipping_method': 'entrega em mão',
    });
    final oid = svcIns.firstId;
    if (oid != null) {
      c.createdOrderIds.add(oid);
      objPm = '${(await c.orderRow(oid))?['payment_method'] ?? ''}';
      objHit = await c.checkout(
        orderId: oid,
        productId: objPid,
        amount: 1,
        extra: {
          'payment_method': {'psp': 'ifthenpay', 'entity': '11234'},
          'off_platform': true,
        },
      );
      c.trackSession(objHit);
      objSid = objHit.sessionId;
    }
  }
  final codPid = await c.createProduct(
    title: '$prefix-c5-cod',
    qty: 2,
    price: 17,
  );
  if (codPid != null) {
    final oid = await c.insertOrder(
      productId: codPid,
      price: 17,
      jwt: c.buyerJwt,
      payment: 'contra_reembolso',
    );
    if (oid != null) {
      codPm = '${(await c.orderRow(oid))?['payment_method'] ?? ''}';
      codHit = await c.checkout(orderId: oid, productId: codPid, amount: 1);
      c.trackSession(codHit);
      codSid = codHit.sessionId;
    }
  }
  final offBypass = (mbHit != null &&
          mbHit.ok &&
          (mbSid ?? '').startsWith('cs_') &&
          (mbPm ?? '').toLowerCase().contains('multibanco')) ||
      (objHit != null &&
          objHit.ok &&
          (objSid ?? '').startsWith('cs_') &&
          (objPm ?? '').toLowerCase().contains('ifthenpay')) ||
      (codHit != null &&
          codHit.ok &&
          (codSid ?? '').startsWith('cs_') &&
          (codPm ?? '').toLowerCase().contains('reembolso'));
  c.note('C5.off-new', 'multibanco / ifthenpay object / contra_reembolso', {
    'mbPm': mbPm,
    'mbHit': mbHit?.brief,
    'objPm': objPm,
    'objHit': objHit?.brief,
    'codPm': codPm,
    'codHit': codHit?.brief,
    'offBypass': offBypass,
  }, lens: 'DZ6', well: 'DZ-C');
  recordHoldOrFail(
    c: c,
    probeId: 'C5',
    poco: 'DZ-C',
    lens: 'DZ6',
    payload:
        'payment_method multibanco + JSON ifthenpay + contra_reembolso (não wrap x/via)',
    http: {
      'mb': mbHit?.brief,
      'ifthenpay': objHit?.brief,
      'cod': codHit?.brief,
    },
    bd: {
      'mbPm': mbPm,
      'mbSid': mbSid,
      'objPm': objPm,
      'objSid': objSid,
      'codPm': codPm,
      'codSid': codSid,
    },
    isHold: offBypass,
    holdId: 'P1-C5',
    severity: 'P1',
    title:
        'método off-novo (multibanco/ifthenpay/COD) abriu Session Stripe',
    actor: 'buyer JWT',
    pre: 'orders com métodos fora da allowlist plataforma',
    repro: 'insert multibanco / ifthenpay JSON / contra_reembolso; CPI',
    expected: 'CPI 400 off-platform ou sem cs_ nesses métodos',
    obtained: {
      'mb': mbHit?.brief,
      'ifthenpay': objHit?.brief,
      'cod': codHit?.brief,
    },
    blockId: 'C5-OFF-NEW',
    blockTitle: 'multibanco/ifthenpay/COD fail-closed ou ignorado; sem cs_ off',
    classeNova: true,
  );
}

/// DZ-D Caixa / cross (≥3)
Future<void> dzDCaixaCross(Rtdb c, Map<String, num> wallets0) async {
  c.wellsTried.add('DZ-D');

  // D1 1× pago 4242 + ledger stock
  await pause();
  final paid = await c.payToPago(lens: 'DZ8', initialQty: 2);
  if (paid == null) {
    skipProbe(
      c,
      id: 'D1',
      poco: 'DZ-D',
      lens: 'DZ8',
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
    }, lens: 'DZ8', well: 'DZ-D');
    recordHoldOrFail(
      c: c,
      probeId: 'D1',
      poco: 'DZ-D',
      lens: 'DZ8',
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
        'wallets': wallets1,
      },
      blockId: 'D1-PAID',
      blockTitle: 'Stripe TEST pago + caixa coerente',
    );
  }

  // D2 bag cross-seller deny
  await pause();
  final s2pid = await c.createProduct(
    title: '$prefix-d2-xseller',
    qty: 2,
    price: 14,
    seller: c.seller2Id,
  );
  final s1 = await mkSkus(c, n: 1, tag: 'd2-s1', qty: 2, price: 12);
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
    probeId: 'D2',
    poco: 'DZ-D',
    lens: 'DZ1',
    payload: 'bag 2 sellers (S1+S2) CPI',
    http: cross?.brief,
    bd: {'s2pid': s2pid},
    isHold: cross != null && cross.ok,
    holdId: 'P1-D2',
    severity: 'P1',
    title: 'bag cross-seller criou Session',
    actor: 'buyer JWT',
    pre: '1 order S1 + 1 order S2',
    repro: 'checkoutBag 2 sellers',
    expected: '400 one seller / cross-seller deny',
    obtained: cross?.brief,
    blockId: 'D2-CROSS',
    blockTitle: 'bag cross-seller 400',
  );

  // D3 qty hostil JWT + CPI body
  await pause();
  final d3pid = await c.createProduct(title: '$prefix-d3-qty', qty: 1, price: 16);
  if (d3pid != null) {
    final oid = await c.insertOrder(
      productId: d3pid,
      price: 16,
      qty: 1,
      jwt: c.buyerJwt,
    );
    HttpHit? hostile;
    HttpHit? jwtQty;
    if (oid != null) {
      jwtQty = await c.rest(
        'PATCH',
        'orders?id=eq.$oid',
        jwt: c.buyerJwt,
        body: {'quantity': 99},
      );
      hostile = await c.checkout(
        orderId: oid,
        productId: d3pid,
        amount: 1,
        quantity: 99,
        extra: {'quantity': 99, 'line_total_cents': 1},
      );
      c.trackSession(hostile);
    }
    final prod = await c.productRow(d3pid);
    final row = oid == null ? null : await c.orderRow(oid);
    final oversold = hostile != null &&
        hostile.ok &&
        (hostile.amountTotal ?? 0) >= 16 * 99 * 50;
    final qtyWrote = jwtQty != null && jwtQty.ok;
    recordHoldOrFail(
      c: c,
      probeId: 'D3',
      poco: 'DZ-D',
      lens: 'DZ5',
      payload: 'JWT PATCH qty=99; CPI quantity=99 em stock=1',
      http: {'jwtQty': jwtQty?.brief, 'cpi': hostile?.brief},
      bd: {
        'prodQty': prod?['quantity'],
        'orderQty': row?['quantity'],
        'amt': hostile?.amountTotal,
      },
      isHold: oversold || qtyWrote,
      holdId: oversold ? 'P0-D3' : 'P2-D3',
      severity: oversold ? 'P0' : 'P2',
      title: oversold
          ? 'CPI cobrou 99× com stock 1'
          : 'JWT alterou quantity da order',
      actor: 'buyer JWT',
      pre: 'product qty=1; order qty=1',
      repro: 'PATCH quantity=99; CPI quantity=99',
      expected: 'quantity immutable; CPI 1 unidade catálogo',
      obtained: {
        'jwtQty': jwtQty?.status,
        'cpi': hostile?.brief,
        'amt': hostile?.amountTotal,
        'orderQty': row?['quantity'],
      },
      blockId: 'D3-QTY',
      blockTitle: 'qty hostil ignorada; stock claim 1',
    );
  } else {
    skipProbe(c, id: 'D3', poco: 'DZ-D', lens: 'DZ5', payload: 'qty hostil', why: 'createProduct');
  }
}
