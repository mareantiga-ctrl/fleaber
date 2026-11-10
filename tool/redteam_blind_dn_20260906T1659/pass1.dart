/// RED TEAM CEGO DN pass1 — saco/mutex/claim/preço/stock pós-DHDM.
/// Matriz A1–A5 · B1–B6 · C1–C5 · D1–D2. Sem correções. Overlaps novos.
import 'dart:io';

import '_rtdn.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('DN pass1 staging=${c.url} prefix=$prefix');
  if (c.stripeTestKey == null) {
    stdout.writeln('WARN no sk_test_ — expire/list Stripe limitado');
  }
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('actors', 'ids', {
    'b': c.buyerId,
    's': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
  });
  final wallets0 = await c.wallets();
  c.note('DN8.wallet.pre', 'baseline', wallets0, lens: 'DN8', well: 'DN-C');

  await dnAClaimMutex(c);
  await dnBOverlapRaces(c);
  await dnCPriceStockPaid(c, wallets0);
  await dnDCross(c);

  final wallets1 = await c.wallets();
  c.note('DN8.wallet.post', 'após probes', {
    'pre': wallets0,
    'post': wallets1,
  }, lens: 'DN8', well: 'DN-C');

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

bool contention(HttpHit h) {
  final raw = h.body.toLowerCase();
  return !h.ok &&
      (raw.contains('contention') ||
          raw.contains('claim busy') ||
          raw.contains('lock bag') ||
          raw.contains('advisory') ||
          raw.contains('try again') ||
          h.status == 409);
}

Future<int> openPayableCount(Rtdb c, Iterable<String> sids) async {
  var n = 0;
  for (final sid in sids) {
    if (!sid.startsWith('cs_')) continue;
    final s = await c.stripeSession(sid);
    if (s.status == 0) {
      final settle = await c.settleGet(sid);
      if (settle.status == 402 || settle.ok) n++;
      continue;
    }
    final st = '${s.map?['status']}';
    final pay = '${s.map?['payment_status']}';
    if (st == 'open' && pay != 'paid' && (s.map?['url'] != null)) n++;
  }
  return n;
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

/// DN-A Claim / mutex (≥5)
Future<void> dnAClaimMutex(Rtdb c) async {
  c.wellsTried.add('DN-A');

  // A1 reclaim cs_ morta + actor 2
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
    }, lens: 'DN6', well: 'DN-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A1',
      poco: 'DN-A',
      lens: 'DN6',
      payload: 'plant cs_test_dead; buyer2 CPI; owner retry',
      http: {
        'actor2': actor2.brief,
        'retry': retry.brief,
      },
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
    skipProbe(c, id: 'A1', poco: 'DN-A', lens: 'DN6', payload: 'cs_ morta', why: 'mkSkus empty');
  }
  await pause();

  // A2 claiming malform / futuro — 1 linha (TTL exacto DBDG = anti-atrofia)
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
      poco: 'DN-A',
      lens: 'DN6',
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
    skipProbe(c, id: 'A2', poco: 'DN-A', lens: 'DN6', payload: 'claiming malform', why: 'mkSkus');
  }
  await pause();

  // A3 crash mid-claim + retry + 3.º CPI (triplo — distinto de timeout∥retry DH)
  final a3 = await mkSkus(c, n: 2, tag: 'a3-crash3', qty: 2);
  if (a3.length == 2) {
    final lines = bagLines(a3);
    final timed = c.checkoutBag(
      lines: lines,
      amount: 1,
      timeout: const Duration(milliseconds: 250),
    );
    final late = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      return c.checkoutBag(lines: lines, amount: 1);
    });
    final third = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 160));
      return c.checkout(
        orderId: a3.first.oid,
        productId: a3.first.pid,
        amount: 1,
      );
    });
    final triple = await parallel([timed, late, third]);
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
    final payable = await openPayableCount(c, sids);
    final briefs = triple.map((h) => h.brief).toList();
    c.note('A3.timeout3', 'timeout 250ms ∥ retry bag ∥ 3.º CPI single', {
      'briefs': briefs,
      'stored': stored,
      'payable': payable,
      'sids': sids.toList(),
    }, lens: 'DN7', well: 'DN-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A3',
      poco: 'DN-A',
      lens: 'DN7',
      payload: 'Future.wait bag timeout 250ms ∥ retry bag ∥ 3.º CPI single',
      http: briefs,
      bd: {'stored': stored, 'payable': payable, 'sids': sids.toList()},
      isHold: payable >= 2 || sids.length >= 2,
      holdId: payable >= 2 ? 'P0-A3' : 'P1-A3',
      severity: payable >= 2 ? 'P0' : 'P1',
      title: 'Timeout+retry+3.º CPI = ≥2 cs_ úteis',
      actor: 'buyer JWT',
      pre: '2-line bag + 3.º CPI same buyer',
      repro: 'Future.wait timeout 250ms ∥ bag retry ∥ single',
      expected: '≤1 cs_ útil (idempotente / contention / reuse)',
      obtained: {'sids': sids.toList(), 'stored': stored, 'payable': payable},
      blockId: 'A3-TIMEOUT3',
      blockTitle: 'timeout∥retry∥3.º CPI ≤1 Session útil',
      classeNova: true,
    );
  } else {
    skipProbe(
      c,
      id: 'A3',
      poco: 'DN-A',
      lens: 'DN7',
      payload: 'Future.wait timeout∥retry∥3.º',
      why: 'mkSkus',
      classeNova: true,
    );
  }
  await pause();

  // A4 2 bags disjuntos mesmo buyer em paralelo
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
    final payable = await openPayableCount(c, sids);
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
    }, lens: 'DN2', well: 'DN-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A4',
      poco: 'DN-A',
      lens: 'DN2',
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
    skipProbe(c, id: 'A4', poco: 'DN-A', lens: 'DN2', payload: 'bags disjuntos', why: 'mkSkus');
  }
  await pause();

  // A5 claim token alheio / write cs_ sem claim (JWT PATCH)
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
      poco: 'DN-A',
      lens: 'DN6',
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
    skipProbe(c, id: 'A5', poco: 'DN-A', lens: 'DN6', payload: 'claim alheio', why: 'mkSkus');
  }
}

/// DN-B Overlaps novos (≥6) — classe_nova
Future<void> dnBOverlapRaces(Rtdb c) async {
  c.wellsTried.add('DN-B');

  Future<void> overlapProbe({
    required String id,
    required String payload,
    required List<({String oid, String pid, double price})> skus,
    required List<HttpHit> hits,
    required String pre,
    required String titleIfTwo,
  }) async {
    for (final h in hits) {
      c.trackSession(h);
    }
    final sids = openCs(hits);
    final payable = await openPayableCount(c, sids);
    final briefs = hits.map((h) => h.brief).toList();
    final stored = [
      for (final r in skus)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final twoUseful = sids.length >= 2;
    c.note('$id.overlap', payload, {
      'sids': sids.toList(),
      'payable': payable,
      'briefs': briefs,
      'stored': stored,
    }, lens: 'DN3', well: 'DN-B');
    recordHoldOrFail(
      c: c,
      probeId: id,
      poco: 'DN-B',
      lens: 'DN3',
      payload: payload,
      http: briefs,
      bd: {
        'sids': sids.toList(),
        'stored': stored,
        'payable': payable,
        'reused': hits.map((h) => h.reused).toList(),
        'contention': hits.map(contention).toList(),
      },
      isHold: twoUseful,
      holdId: payable >= 2 ? 'P0-$id' : 'P1-$id',
      severity: payable >= 2 ? 'P0' : 'P1',
      title: titleIfTwo,
      actor: 'buyer JWT',
      pre: pre,
      repro: payload,
      expected: '≤1 cs_ útil ou 2.º contention/reuse/expire órfã',
      obtained: {
        'sids': sids.toList(),
        'payable': payable,
        'stored': stored,
        'briefs': briefs,
      },
      blockId: '$id-OVERLAP',
      blockTitle: '$id ≤1 cs_ útil / 2.º contention',
      classeNova: true,
    );
  }

  // B1 bag 5∥3 (subset no meio — não 4∥2)
  await pause();
  final b1 = await mkSkus(c, n: 5, tag: 'b1-5x3', qty: 2, price: 9);
  if (b1.length == 5) {
    final five = bagLines(b1);
    final mid3 = bagLines(b1.sublist(1, 4)); // B,C,D — meio, não extrema
    final hits = await parallel([
      c.checkoutBag(lines: five, amount: 1),
      c.checkoutBag(lines: mid3, amount: 1),
    ]);
    await overlapProbe(
      id: 'B1',
      payload: 'Future.wait bag 5-line ∥ bag 3-line subset meio (BCD)',
      skus: b1,
      hits: hits,
      pre: '5 SKUs; bag ABCDE ∥ bag BCD (meio)',
      titleIfTwo: 'Overlap 5∥3 meio: 2 Sessions úteis',
    );
  } else {
    skipProbe(
      c,
      id: 'B1',
      poco: 'DN-B',
      lens: 'DN3',
      payload: 'Future.wait bag 5∥3',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B2 bag AB∥BC (overlap 1 linha, nem subset nem superset)
  await pause();
  final b2 = await mkSkus(c, n: 3, tag: 'b2-ab-bc', qty: 2, price: 10);
  if (b2.length == 3) {
    final ab = bagLines(b2.sublist(0, 2));
    final bc = bagLines(b2.sublist(1, 3));
    final hits = await parallel([
      c.checkoutBag(lines: ab, amount: 1),
      c.checkoutBag(lines: bc, amount: 1),
    ]);
    await overlapProbe(
      id: 'B2',
      payload: 'Future.wait bag AB ∥ bag BC (overlap 1 linha B)',
      skus: b2,
      hits: hits,
      pre: '3 SKUs; bag AB ∥ bag BC — partilha B, nem subset',
      titleIfTwo: 'Overlap AB∥BC: 2 Sessions úteis na linha partilhada',
    );
  } else {
    skipProbe(
      c,
      id: 'B2',
      poco: 'DN-B',
      lens: 'DN3',
      payload: 'Future.wait bag AB∥BC',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B3 bag ABC∥CBA (mesmas linhas ordem diferente)
  await pause();
  final b3 = await mkSkus(c, n: 3, tag: 'b3-abc-cba', qty: 2, price: 11);
  if (b3.length == 3) {
    final abc = bagLines(b3);
    final cba = bagLines(b3.reversed);
    final hits = await parallel([
      c.checkoutBag(lines: abc, amount: 1),
      c.checkoutBag(lines: cba, amount: 1),
    ]);
    await overlapProbe(
      id: 'B3',
      payload: 'Future.wait bag ABC ∥ bag CBA (mesmas linhas ordem inversa)',
      skus: b3,
      hits: hits,
      pre: '3 SKUs; ABC ∥ CBA',
      titleIfTwo: 'Overlap ABC∥CBA: 2 Sessions úteis (ordem não canonicaliza)',
    );
  } else {
    skipProbe(
      c,
      id: 'B3',
      poco: 'DN-B',
      lens: 'DN3',
      payload: 'Future.wait bag ABC∥CBA',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B4 2× single paralelo mesma order_id
  await pause();
  final b4 = await mkSkus(c, n: 1, tag: 'b4-2single', qty: 2, price: 12);
  if (b4.length == 1) {
    final hits = await parallel([
      c.checkout(orderId: b4.first.oid, productId: b4.first.pid, amount: 1),
      c.checkout(orderId: b4.first.oid, productId: b4.first.pid, amount: 1),
    ]);
    await overlapProbe(
      id: 'B4',
      payload: 'Future.wait 2× CPI single mesma order_id',
      skus: b4,
      hits: hits,
      pre: '1 order; 2 CPI single em paralelo',
      titleIfTwo: '2× single mesma order: 2 Sessions úteis',
    );
  } else {
    skipProbe(
      c,
      id: 'B4',
      poco: 'DN-B',
      lens: 'DN3',
      payload: 'Future.wait 2× single mesma order',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B5 bag∥single linha do meio (não extrema)
  await pause();
  final b5 = await mkSkus(c, n: 5, tag: 'b5-mid-single', qty: 2, price: 8);
  if (b5.length == 5) {
    final five = bagLines(b5);
    final mid = b5[2]; // linha C, meio
    final hits = await parallel([
      c.checkoutBag(lines: five, amount: 1),
      c.checkout(orderId: mid.oid, productId: mid.pid, amount: 1),
    ]);
    await overlapProbe(
      id: 'B5',
      payload: 'Future.wait bag 5-line ∥ CPI single linha do meio (C)',
      skus: b5,
      hits: hits,
      pre: '5 SKUs; bag ABCDE ∥ CPI C (meio, não extrema)',
      titleIfTwo: 'bag∥single linha do meio: 2 Sessions úteis',
    );
  } else {
    skipProbe(
      c,
      id: 'B5',
      poco: 'DN-B',
      lens: 'DN3',
      payload: 'Future.wait bag∥single meio',
      why: 'mkSkus',
      classeNova: true,
    );
  }

  // B6 CPI bag timeout 200ms ∥ CPI bag full ∥ CPI single (triplo)
  await pause();
  final b6 = await mkSkus(c, n: 3, tag: 'b6-triple', qty: 2, price: 13);
  if (b6.length == 3) {
    final three = bagLines(b6);
    final timed = c.checkoutBag(
      lines: three,
      amount: 1,
      timeout: const Duration(milliseconds: 200),
    );
    final full = c.checkoutBag(lines: three, amount: 1);
    final single = c.checkout(
      orderId: b6[1].oid,
      productId: b6[1].pid,
      amount: 1,
    );
    final hits = await parallel([timed, full, single]);
    await overlapProbe(
      id: 'B6',
      payload:
          'Future.wait bag timeout 200ms ∥ bag full ∥ CPI single linha do meio',
      skus: b6,
      hits: hits,
      pre: '3 SKUs; triplo timeout∥full∥single-meio',
      titleIfTwo: 'Triplo timeout∥bag∥single: ≥2 Sessions úteis',
    );
  } else {
    skipProbe(
      c,
      id: 'B6',
      poco: 'DN-B',
      lens: 'DN3',
      payload: 'Future.wait timeout∥bag∥single',
      why: 'mkSkus',
      classeNova: true,
    );
  }
}

/// DN-C Preço / stock / pago (≥5)
Future<void> dnCPriceStockPaid(Rtdb c, Map<String, num> wallets0) async {
  c.wellsTried.add('DN-C');

  // C1 underpay total_eur / line hostil
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
    poco: 'DN-C',
    lens: 'DN5',
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

  // C2 coupon / portes com Session open — verificar BD, não só HTTP 200
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
  }, lens: 'DN5', well: 'DN-C');
  recordHoldOrFail(
    c: c,
    probeId: 'C2',
    poco: 'DN-C',
    lens: 'DN5',
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
      final payable = await openPayableCount(c, openCs(hits));
      recordHoldOrFail(
        c: c,
        probeId: 'C3',
        poco: 'DN-C',
        lens: 'DN4',
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
        poco: 'DN-C',
        lens: 'DN4',
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
    skipProbe(c, id: 'C3', poco: 'DN-C', lens: 'DN4', payload: '2 buyers qty=1', why: 'createProduct');
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
      poco: 'DN-C',
      lens: 'DN4',
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
    skipProbe(c, id: 'C4', poco: 'DN-C', lens: 'DN4', payload: 'unlist∥CPI', why: 'mkSkus');
  }

  // C5 Stripe TEST pago 4242 + ledger
  await pause();
  final paid = await c.payToPago(lens: 'DN8', initialQty: 2);
  if (paid == null) {
    skipProbe(
      c,
      id: 'C5',
      poco: 'DN-C',
      lens: 'DN8',
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
    c.note('C5.paid', 'Stripe TEST pago + caixa', {
      'oid': paid.oid,
      'pid': paid.pid,
      'pi': pi,
      'status': st,
      'cents': cents,
      'applied': applied,
      'qty': qty,
      'wallets0': wallets0,
      'wallets1': wallets1,
    }, lens: 'DN8', well: 'DN-C');
    recordHoldOrFail(
      c: c,
      probeId: 'C5',
      poco: 'DN-C',
      lens: 'DN8',
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
      holdId: 'P1-C5',
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
      blockId: 'C5-PAID',
      blockTitle: 'Stripe TEST pago + caixa coerente',
    );
  }
}

/// DN-D Cross-seller / qty (≥2)
Future<void> dnDCross(Rtdb c) async {
  c.wellsTried.add('DN-D');

  // D1 bag cross-seller → deny
  await pause();
  final s2pid = await c.createProduct(
    title: '$prefix-d1-xseller',
    qty: 2,
    price: 14,
    seller: c.seller2Id,
  );
  final s1 = await mkSkus(c, n: 1, tag: 'd1-s1', qty: 2, price: 12);
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
    probeId: 'D1',
    poco: 'DN-D',
    lens: 'DN1',
    payload: 'bag 2 sellers (S1+S2) CPI',
    http: cross?.brief,
    bd: {'s2pid': s2pid},
    isHold: cross != null && cross.ok,
    holdId: 'P1-D1',
    severity: 'P1',
    title: 'bag cross-seller criou Session',
    actor: 'buyer JWT',
    pre: '1 order S1 + 1 order S2',
    repro: 'checkoutBag 2 sellers',
    expected: '400 one seller / cross-seller deny',
    obtained: cross?.brief,
    blockId: 'D1-CROSS',
    blockTitle: 'bag cross-seller 400',
  );

  // D2 qty hostil no body vs BD
  await pause();
  final d2pid = await c.createProduct(title: '$prefix-d2-qty', qty: 1, price: 16);
  if (d2pid != null) {
    final oid = await c.insertOrder(
      productId: d2pid,
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
        productId: d2pid,
        amount: 1,
        quantity: 99,
        extra: {'quantity': 99, 'line_total_cents': 1},
      );
      c.trackSession(hostile);
    }
    final prod = await c.productRow(d2pid);
    final row = oid == null ? null : await c.orderRow(oid);
    final oversold = hostile != null &&
        hostile.ok &&
        (hostile.amountTotal ?? 0) >= 16 * 99 * 50;
    final qtyWrote = jwtQty != null && jwtQty.ok;
    recordHoldOrFail(
      c: c,
      probeId: 'D2',
      poco: 'DN-D',
      lens: 'DN4',
      payload: 'JWT PATCH qty=99; CPI quantity=99 em stock=1',
      http: {'jwtQty': jwtQty?.brief, 'cpi': hostile?.brief},
      bd: {
        'prodQty': prod?['quantity'],
        'orderQty': row?['quantity'],
        'amt': hostile?.amountTotal,
      },
      isHold: oversold || qtyWrote,
      holdId: oversold ? 'P0-D2' : 'P2-D2',
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
      blockId: 'D2-QTY',
      blockTitle: 'qty hostil ignorada; stock claim 1',
    );
  } else {
    skipProbe(c, id: 'D2', poco: 'DN-D', lens: 'DN4', payload: 'qty hostil', why: 'createProduct');
  }
}
