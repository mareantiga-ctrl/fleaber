/// RED TEAM CEGO DH pass1 — marketplace pós-DBDG.
/// Matriz A1–A4 · B1–B5 · C1–C5 · D1–D2. Sem correções.
import 'dart:io';

import '_rtdh.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('DH pass1 staging=${c.url} prefix=$prefix');
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
  c.note('DH8.wallet.pre', 'baseline', wallets0, lens: 'DH8', well: 'DH-C');

  await dhAClaimMutex(c);
  await dhBOverlapRaces(c);
  await dhCPriceOffPaid(c, wallets0);
  await dhDCross(c);

  final wallets1 = await c.wallets();
  c.note('DH8.wallet.post', 'após probes', {
    'pre': wallets0,
    'post': wallets1,
  }, lens: 'DH8', well: 'DH-C');

  await c.dumpAll('pass1_findings.json');
  await dumpJson('${outDir()}/probes.json', {
    'stamp': stamp,
    'prefix': prefix,
    'probes': c.probes,
    'n': c.probes.length,
    'races': c.probes
        .where((p) => '${p['payload']}'.contains('Future.wait'))
        .map((p) => p['probe_id'])
        .toList(),
    'findings': c.findings.length,
  });
  stdout.writeln(
    'DONE probes=${c.probes.length} findings=${c.findings.length} '
    'blocked=${c.blocked.length} skip=${c.skipped.length} '
    'lenses=${c.lensesHit.toList()..sort()} wells=${c.wellsTried.toList()..sort()}',
  );
}

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

bool offDenied(HttpHit h) {
  final raw = h.body.toLowerCase();
  return h.status == 400 &&
      (raw.contains('off-platform') || raw.contains('off platform'));
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
    );
  }
}

Future<Map<String, Object?>> probeEncode(
  Rtdb c, {
  required String tag,
  required String payment,
}) async {
  final sql = await c.rpc(
    'batata_is_off_platform_payment',
    {'p_method': payment},
    service: true,
  );
  final skus = await mkSkus(
    c,
    n: 1,
    tag: tag,
    qty: 2,
    price: 18,
    payment: payment,
  );
  HttpHit? cpi;
  Map<String, dynamic>? row;
  if (skus.isEmpty) {
    final pid =
        await c.createProduct(title: '$prefix-$tag-svc', qty: 2, price: 18);
    if (pid != null) {
      final oid = await c.insertOrder(
        productId: pid,
        price: 18,
        payment: payment,
        service: true,
      );
      if (oid != null) {
        cpi = await c.checkout(orderId: oid, productId: pid, amount: 1);
        c.trackSession(cpi);
        row = await c.orderRow(oid);
      }
    }
  } else {
    cpi = await c.checkout(
      orderId: skus.first.oid,
      productId: skus.first.pid,
      amount: 1,
    );
    c.trackSession(cpi);
    row = await c.orderRow(skus.first.oid);
  }
  final pm = '${row?['payment_method'] ?? ''}';
  final codes = pm.runes.map((r) => r.toRadixString(16)).toList();
  final sid = '${cpi?.sessionId ?? row?['stripe_checkout_session_id'] ?? ''}';
  final opened = cpi != null && cpi.ok && sid.startsWith('cs_');
  final denied = cpi != null && offDenied(cpi);
  return {
    'tag': tag,
    'sql': sql.json,
    'sql_true': sql.json == true,
    'cpi': cpi?.brief,
    'opened': opened,
    'denied': denied,
    'sid': sid,
    'pm_len': pm.length,
    'pm_codes': codes,
    'status': row?['status'],
    'status_http': cpi?.status,
  };
}

/// DH-A Claim / mutex
Future<void> dhAClaimMutex(Rtdb c) async {
  c.wellsTried.add('DH-A');

  // A1 reclaim cs_ morta + 2.º actor + JWT write sem claim
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
    final jwtPlant = await c.rest(
      'PATCH',
      'orders?id=eq.${a1.first.oid}',
      jwt: c.buyerJwt,
      body: {'stripe_checkout_session_id': 'cs_test_deaddeaddeaddeaddead99'},
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
    final jwtWrote = jwtPlant.ok;
    c.note('A1.dead', 'cs_ morta reclaim + write JWT', {
      'first': first.brief,
      'plant': plant.brief,
      'jwtPlant': jwtPlant.brief,
      'actor2': actor2.brief,
      'retry': retry.brief,
      'stored': sid,
    }, lens: 'DH1', well: 'DH-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A1',
      poco: 'DH-A',
      lens: 'DH1',
      payload: 'plant cs_test_dead; JWT PATCH cs_; buyer2 CPI; owner retry',
      http: {
        'jwtPlant': jwtPlant.brief,
        'actor2': actor2.brief,
        'retry': retry.brief,
      },
      bd: sid,
      isHold: deadStuck || stolen || jwtWrote,
      holdId: stolen || jwtWrote ? 'P1-A1' : 'P2-A1',
      severity: stolen || jwtWrote ? 'P1' : 'P2',
      title: jwtWrote
          ? 'JWT escreveu cs_ sem claim próprio'
          : stolen
              ? '2.º actor reclaimou cs_ morta de order alheia'
              : 'cs_ morta bloqueia reclaim (DoS checkout)',
      actor: 'buyer JWT + buyer2',
      pre: 'stripe_checkout_session_id=cs_test_dead…',
      repro: 'JWT PATCH cs_; CPI buyer2; CPI owner',
      expected: 'JWT 403 immutable; buyer2 400; owner reclaim + nova cs_',
      obtained: {
        'actor2': actor2.brief,
        'retry': retry.brief,
        'stored': sid,
        'jwtPlant': jwtPlant.status,
      },
      blockId: 'A1-DEAD-CS',
      blockTitle: 'cs_ morta reclaim OK / JWT write negado / 2.º actor negado',
    );
  } else {
    c.skip('A1', 'DH1', 'não criou SKU', 'mkSkus empty');
    c.probe(
      id: 'A1',
      poco: 'DH-A',
      payload: 'cs_ morta reclaim',
      http: 'skip fixture',
      bd: '-',
      verdict: 'SKIP',
      lens: 'DH1',
    );
  }

  // A2 claiming futuro / malform / TTL
  final a2 = await mkSkus(c, n: 1, tag: 'a2-future', qty: 2);
  if (a2.length == 1) {
    final futureMs =
        DateTime.now().millisecondsSinceEpoch + 365 * 24 * 3600 * 1000;
    final tok = 'claiming:$futureMs:futuretoken12ab';
    await c.plantClaim(a2.first.oid, tok);
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
    c.note('A2.future', 'claiming futuro', {
      'tok': tok,
      'rpcJwt': rpcJwt.brief,
      'hit': hit.brief,
      'stored': sid,
    }, lens: 'DH1', well: 'DH-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A2',
      poco: 'DH-A',
      lens: 'DH1',
      payload: 'claiming:<now+1y>:futuretoken12ab + CPI; RPC JWT',
      http: {'rpcJwt': rpcJwt.brief, 'cpi': hit.brief},
      bd: sid,
      isHold: stuck || incoherent,
      holdId: 'P2-A2',
      severity: 'P2',
      title: stuck
          ? 'claiming futuro prende o cadeado'
          : 'claiming futuro: CPI cs_ mas ledger ainda claiming',
      actor: 'buyer JWT (plant service_role observação)',
      pre: tok,
      repro: 'CPI após claiming futuro',
      expected: 'futuro=órfão; reclaim + cs_ coerente; RPC JWT 403',
      obtained: {'hit': hit.brief, 'stored': sid, 'rpcJwt': rpcJwt.status},
      blockId: 'A2-FUTURE',
      blockTitle: 'claiming futuro reclaim/create coerente',
    );
  }

  final a2m = await mkSkus(c, n: 1, tag: 'a2-malform', qty: 2);
  if (a2m.length == 1) {
    await c.plantClaim(a2m.first.oid, 'claiming:notanumber:malformtok12');
    final hit = await c.checkout(
      orderId: a2m.first.oid,
      productId: a2m.first.pid,
      amount: 1,
    );
    c.trackSession(hit);
    final row = await c.orderRow(a2m.first.oid);
    final sid = '${row?['stripe_checkout_session_id'] ?? ''}';
    final stuck = sid.startsWith('claiming:') && !hit.ok;
    final incoherent = hit.ok &&
        (hit.sessionId ?? '').startsWith('cs_') &&
        sid.startsWith('claiming:');
    recordHoldOrFail(
      c: c,
      probeId: 'A2-MALFORM',
      poco: 'DH-A',
      lens: 'DH1',
      payload: 'plant claiming:notanumber:malformtok12 + CPI',
      http: hit.brief,
      bd: sid,
      isHold: stuck || incoherent,
      holdId: 'P2-A2M',
      severity: 'P2',
      title: 'claiming malform prende/incoerente',
      actor: 'buyer JWT',
      pre: 'claiming:notanumber:…',
      repro: 'CPI',
      expected: 'malform=órfão; cs_ coerente',
      obtained: {'hit': hit.brief, 'stored': sid},
      blockId: 'A2-MALFORM',
      blockTitle: 'claiming malform reclaim coerente',
    );
  }

  final a2t = await mkSkus(c, n: 1, tag: 'a2-ttl', qty: 2);
  if (a2t.length == 1) {
    final oldMs = DateTime.now().millisecondsSinceEpoch - 120000;
    await c.plantClaim(a2t.first.oid, 'claiming:$oldMs:expiredtoken12');
    final hit = await c.checkout(
      orderId: a2t.first.oid,
      productId: a2t.first.pid,
      amount: 1,
    );
    c.trackSession(hit);
    final row = await c.orderRow(a2t.first.oid);
    final sid = '${row?['stripe_checkout_session_id'] ?? ''}';
    final stuck = sid.startsWith('claiming:') && !hit.ok;
    recordHoldOrFail(
      c: c,
      probeId: 'A2-TTL',
      poco: 'DH-A',
      lens: 'DH1',
      payload: 'plant claiming:<now-120s>:expiredtoken12 + CPI',
      http: hit.brief,
      bd: sid,
      isHold: stuck,
      holdId: 'P2-A2T',
      severity: 'P2',
      title: 'claiming TTL expirado prende o cadeado',
      actor: 'buyer JWT',
      pre: 'claiming age 120s > TTL 90s',
      repro: 'CPI',
      expected: 'TTL órfão; nova cs_',
      obtained: {'hit': hit.brief, 'stored': sid},
      blockId: 'A2-TTL',
      blockTitle: 'claiming TTL expirado reclaim',
    );
  }

  // A3 crash mid-claim + retry (Future.wait)
  final a3 = await mkSkus(c, n: 2, tag: 'a3-crash', qty: 2);
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
    final pair = await parallel([timed, late]);
    for (final h in pair) {
      c.trackSession(h);
    }
    await Future<void>.delayed(const Duration(seconds: 4));
    final stored = [
      '${(await c.orderRow(a3[0].oid))?['stripe_checkout_session_id'] ?? ''}',
      '${(await c.orderRow(a3[1].oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final sids = {
      ...openCs(pair),
      ...stored.where((s) => s.startsWith('cs_')),
    };
    final payable = await openPayableCount(c, sids);
    final briefs = pair.map((h) => h.brief).toList();
    c.note('A3.timeout', 'timeout 250ms ∥ retry', {
      'briefs': briefs,
      'stored': stored,
      'payable': payable,
    }, lens: 'DH7', well: 'DH-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A3',
      poco: 'DH-A',
      lens: 'DH7',
      payload: 'Future.wait bag timeout 250ms ∥ retry',
      http: briefs,
      bd: {'stored': stored, 'payable': payable, 'sids': sids.toList()},
      isHold: payable >= 2,
      holdId: 'P0-A3',
      severity: 'P0',
      title: 'Timeout mid-claim + retry = 2 cs_ pagáveis',
      actor: 'buyer JWT',
      pre: '2-line bag',
      repro: 'Future.wait checkoutBag timeout 250ms ∥ retry',
      expected: '≤1 cs_ útil (idempotente ou contention)',
      obtained: {'sids': sids.toList(), 'stored': stored, 'payable': payable},
      blockId: 'A3-TIMEOUT',
      blockTitle: 'timeout∥retry ≤1 Session útil',
    );
  }

  // A4 mutex: 2 CPI mesmo buyer bags DISJUNTOS em paralelo (ângulo novo)
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
    final mutexReadable = jwtMutex.ok;
    c.note('A4.disjoint', '2 bags disjuntos mesmo buyer ∥', {
      'briefs': briefs,
      'sids': sids.toList(),
      'payable': payable,
      'storedA': storedA,
      'storedB': storedB,
      'jwtMutex': jwtMutex.brief,
      'svcMutex': svcMutex.brief,
    }, lens: 'DH2', well: 'DH-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A4',
      poco: 'DH-A',
      lens: 'DH2',
      payload: 'Future.wait 2 bags disjuntos mesmo buyer (2+2 SKUs)',
      http: {
        'briefs': briefs,
        'jwtMutex': jwtMutex.brief,
      },
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
          'mutex serializa; ≤1 create em voo; 2.º wait/reuse/contention ou 2 cs_ só após release',
      obtained: {
        'sids': sids.toList(),
        'payable': payable,
        'briefs': briefs,
      },
      blockId: 'A4-DISJOINT',
      blockTitle: 'bags disjuntos: mutex serializou (documentado)',
    );
  }
}

/// DH-B Overlap races
Future<void> dhBOverlapRaces(Rtdb c) async {
  c.wellsTried.add('DH-B');

  // B1 bag 4∥2 — se ≤1 cs_ é fecho DBDG (FAIL, anti-atrofia não contar HOLD)
  final b1 = await mkSkus(c, n: 4, tag: 'b1-4x2', qty: 2, price: 9);
  if (b1.length == 4) {
    final four = bagLines(b1);
    final two = bagLines(b1.sublist(2));
    final hits = await parallel([
      c.checkoutBag(lines: four, amount: 1),
      c.checkoutBag(lines: two, amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    final sids = openCs(hits);
    final payable = await openPayableCount(c, sids);
    final briefs = hits.map((h) => h.brief).toList();
    final stored = [
      for (final r in b1)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final twoUseful = sids.length >= 2;
    c.note('B1.4x2', 'bag 4-line ∥ 2-line overlap', {
      'sids': sids.toList(),
      'payable': payable,
      'briefs': briefs,
      'stored': stored,
    }, lens: 'DH3', well: 'DH-B');
    recordHoldOrFail(
      c: c,
      probeId: 'B1',
      poco: 'DH-B',
      lens: 'DH3',
      payload: 'Future.wait bag 4-line ∥ bag 2-line overlap CD',
      http: briefs,
      bd: {
        'sids': sids.toList(),
        'stored': stored,
        'payable': payable,
      },
      isHold: twoUseful,
      holdId: 'P1-B1',
      severity: 'P1',
      title: 'Overlap 4∥2: 2 Sessions úteis (mutex DBDG falhou)',
      actor: 'buyer JWT',
      pre: '4 SKUs; bag ABCD ∥ bag CD',
      repro: 'Future.wait bag 4-line ∥ bag 2-line',
      expected: '≤1 cs_ útil ou 2.º blocked/contention',
      obtained: {
        'sids': sids.toList(),
        'payable': payable,
        'stored': stored,
      },
      blockId: 'B1-4x2',
      blockTitle: 'overlap 4∥2 ≤1 cs_ útil / 2.º contention',
      countFinding: twoUseful, // ≤1 = fecho, não contar; ≥2 = finding novo
    );
  } else {
    c.skip('B1', 'DH3', 'não criou 4 SKUs', 'mkSkus');
    c.probe(
      id: 'B1',
      poco: 'DH-B',
      payload: 'bag 4∥2',
      http: 'skip',
      bd: '-',
      verdict: 'SKIP',
      lens: 'DH3',
    );
  }

  // B2 bag 3∥1
  final b2 = await mkSkus(c, n: 3, tag: 'b2-3x1', qty: 2, price: 10);
  if (b2.length == 3) {
    final three = bagLines(b2);
    final one = bagLines([b2[2]]);
    final hits = await parallel([
      c.checkoutBag(lines: three, amount: 1),
      c.checkoutBag(lines: one, amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    final sids = openCs(hits);
    final payable = await openPayableCount(c, sids);
    final briefs = hits.map((h) => h.brief).toList();
    final stored = [
      for (final r in b2)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    recordHoldOrFail(
      c: c,
      probeId: 'B2',
      poco: 'DH-B',
      lens: 'DH3',
      payload: 'Future.wait bag 3-line ∥ 1-line overlap',
      http: briefs,
      bd: {'sids': sids.toList(), 'stored': stored, 'payable': payable},
      isHold: sids.length >= 2,
      holdId: 'P1-B2',
      severity: 'P1',
      title: 'Overlap 3∥1: 2 Sessions úteis',
      actor: 'buyer JWT',
      pre: '3 SKUs; bag ABC ∥ bag C',
      repro: 'Future.wait bag 3-line ∥ 1-line',
      expected: '≤1 cs_ útil ou 2.º contention',
      obtained: {
        'sids': sids.toList(),
        'payable': payable,
        'stored': stored,
      },
      blockId: 'B2-3x1',
      blockTitle: 'overlap 3∥1 ≤1 cs_ útil / 2.º contention',
    );
  }

  // B3 bag∥single mesma linha
  final b3 = await mkSkus(c, n: 4, tag: 'b3-bag-single', qty: 2, price: 8);
  if (b3.length == 4) {
    final four = bagLines(b3);
    final hits = await parallel([
      c.checkoutBag(lines: four, amount: 1),
      c.checkout(orderId: b3[2].oid, productId: b3[2].pid, amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    final sids = openCs(hits);
    final payable = await openPayableCount(c, sids);
    final briefs = hits.map((h) => h.brief).toList();
    recordHoldOrFail(
      c: c,
      probeId: 'B3',
      poco: 'DH-B',
      lens: 'DH3',
      payload: 'Future.wait bag 4-line ∥ CPI single linha C',
      http: briefs,
      bd: {'sids': sids.toList(), 'payable': payable},
      isHold: sids.length >= 2,
      holdId: 'P1-B3',
      severity: 'P1',
      title: 'bag∥CPI-single: 2 Sessions no mesmo artigo',
      actor: 'buyer JWT',
      pre: '4 SKUs; bag ABCD ∥ CPI C',
      repro: 'Future.wait checkoutBag ∥ checkout single',
      expected: '≤1 cs_ útil (mutex buyer cobre single)',
      obtained: {'sids': sids.toList(), 'payable': payable, 'briefs': briefs},
      blockId: 'B3-BAG-SINGLE',
      blockTitle: 'bag∥single ≤1 cs_',
    );
  }

  // B4 2 buyers última unidade
  final pid = await c.createProduct(title: '$prefix-b4-last', qty: 1, price: 11);
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
        probeId: 'B4',
        poco: 'DH-B',
        lens: 'DH4',
        payload: 'Future.wait 2 buyers CPI última unidade',
        http: briefs,
        bd: {'ok': ok, 'payable': payable, 'o2created': o2},
        isHold: ok >= 2 || payable >= 2,
        holdId: 'P0-B4',
        severity: 'P0',
        title: '2 buyers Session na última unidade',
        actor: 'buyer + buyer2 JWT',
        pre: 'quantity=1; 2 orders',
        repro: 'Future.wait 2× CPI',
        expected: '1 Session + 1 stock block (insert ou CPI)',
        obtained: {'ok': ok, 'payable': payable, 'briefs': briefs},
        blockId: 'B4-LAST',
        blockTitle: 'última unidade ≤1 Session',
      );
    } else {
      recordHoldOrFail(
        c: c,
        probeId: 'B4',
        poco: 'DH-B',
        lens: 'DH4',
        payload: '2 buyers última unidade (insert 2.º)',
        http: {'o1': o1, 'o2': o2},
        bd: {'o1': o1, 'o2': o2},
        isHold: o1 != null && o2 != null,
        holdId: 'P0-B4',
        severity: 'P0',
        title: '2.º buyer inseriu hold na última unidade',
        actor: 'buyer + buyer2 JWT',
        pre: 'quantity=1',
        repro: '2× insertOrder',
        expected: '2.º insert 400 stock',
        obtained: {'o1': o1, 'o2': o2},
        blockId: 'B4-LAST',
        blockTitle: '2.º insert/CPI bloqueado no last-unit',
      );
    }
  }

  // B5 checkout ∥ unlist / qty=0
  final ul = await mkSkus(c, n: 1, tag: 'b5-unlist', qty: 1, price: 13);
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
      probeId: 'B5',
      poco: 'DH-B',
      lens: 'DH4',
      payload: 'Future.wait CPI ∥ unlist+qty=0',
      http: {'ck': ck.brief, 'patch': patch.brief},
      bd: prod,
      isHold: dual,
      holdId: 'P1-B5',
      severity: 'P1',
      title: 'Session aberta sobre SKU unlisted qty=0',
      actor: 'buyer JWT ∥ seller JWT',
      pre: 'qty=1 listed',
      repro: 'Future.wait CPI ∥ PATCH unlist qty=0',
      expected: 'CPI 400 not listed OU unlist perde a corrida (Session ok, still listed)',
      obtained: {
        'ck': ck.brief,
        'listed': prod?['list_on_marketplace'],
        'qty': prod?['quantity'],
      },
      blockId: 'B5-UNLIST',
      blockTitle: 'unlist∥checkout sem Session+qty0 simultâneo',
    );
  }
}

/// DH-C Preço / off-platform / pago
Future<void> dhCPriceOffPaid(Rtdb c, Map<String, num> wallets0) async {
  c.wellsTried.add('DH-C');

  // C1 underpay total_eur / item hostil
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
    poco: 'DH-C',
    lens: 'DH5',
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

  // C2 portes / coupon com Session open
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
  Map<String, dynamic>? discRow;
  if (c2sku.length == 2) {
    openHit = await c.checkoutBag(lines: bagLines(c2sku), amount: 1, shipping: 'mao');
    c.trackSession(openHit);
    openAmt = openHit.amountTotal;
    patchShip = await c.rest(
      'PATCH',
      'orders?id=eq.${c2sku.first.oid}',
      jwt: c.buyerJwt,
      body: {'shipping_method': 'ctt'},
    );
    recpiCtt = await c.checkoutBag(
      lines: bagLines(c2sku),
      amount: 1,
      shipping: 'ctt',
    );
    c.trackSession(recpiCtt);
    recpiAmt = recpiCtt.amountTotal;
    final discPrev = await c.rest(
      'GET',
      'seller_bundle_discounts?seller_id=eq.${c.sellerId}&select=*',
      service: true,
    );
    discRow = discPrev.map;
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
  final shipMutated = patchShip != null && patchShip.ok;
  final cheaper = (couponAmt != null &&
          openAmt != null &&
          couponAmt < openAmt * 0.7) ||
      (recpiAmt != null && openAmt != null && recpiAmt + 50 < openAmt);
  c.note('C2.session-open', 'portes/coupon com Session open', {
    'open': openHit?.brief,
    'openAmt': openAmt,
    'patchShip': patchShip?.brief,
    'recpi': recpiCtt?.brief,
    'recpiAmt': recpiAmt,
    'coupon': couponHit?.brief,
    'couponAmt': couponAmt,
    'disc': discRow,
  }, lens: 'DH5', well: 'DH-C');
  recordHoldOrFail(
    c: c,
    probeId: 'C2',
    poco: 'DH-C',
    lens: 'DH5',
    payload: 'Session open → JWT PATCH shipping=ctt; re-CPI ctt; coupon SAVE90 + tier_2 50%',
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
      'shipMutated': shipMutated,
    },
    isHold: shipMutated || cheaper,
    holdId: cheaper ? 'P0-C2' : 'P2-C2',
    severity: cheaper ? 'P0' : 'P2',
    title: cheaper
        ? 'coupon/desconto baixou Session com cs_ já aberta'
        : 'JWT alterou shipping_method com Session open',
    actor: 'buyer JWT',
    pre: 'bag 2 linhas Session open (mão)',
    repro: 'PATCH shipping; CPI coupon/discount_pct; bundle 50%',
    expected: 'shipping immutable; amount estável ou expire+requote catálogo',
    obtained: {
      'openAmt': openAmt,
      'recpiAmt': recpiAmt,
      'couponAmt': couponAmt,
      'patch': patchShip?.status,
    },
    blockId: 'C2-SHIP-COUPON',
    blockTitle: 'Session open: shipping immutable; coupon ignorado',
  );

  // C3 off-platform NOVO encode (não exacto DB: omega/math/coptic)
  final newEncodes = <String, String>{
    'C3-SUFFIX': 'mb way x',
    'C3-PREFIX': 'xxmbway',
    'C3-VIA': 'via mb way',
    'C3-TRANSX': 'transferencia extra',
    'C3-FWCARD': '\uFF43ard', // fullwidth c → fold-to-card exception
    'C3-CYRCARD': '\u0441ard', // cyrillic es
    'C3-BIZUM': 'bizum',
    'C3-PIX': 'pix',
    'C3-MBNET': 'mbnet',
    'C3-VS': 'mbway\uFE0F',
  };
  final encodeHits = <String, Map<String, Object?>>{};
  final openedTags = <String>[];
  for (final e in newEncodes.entries) {
    final r = await probeEncode(
      c,
      tag: 'c3-${e.key.toLowerCase()}',
      payment: e.value,
    );
    encodeHits[e.key] = r;
    c.note(e.key, 'encode novo ${e.key}', r, lens: 'DH6', well: 'DH-C');
    final opened = r['opened'] == true;
    if (opened) openedTags.add(e.key);
    c.probe(
      id: e.key,
      poco: 'DH-C',
      payload:
          'novo encode ${e.key} codes=${e.value.runes.map((x) => x.toRadixString(16)).toList()}',
      http: r['cpi'],
      bd: r,
      verdict: opened ? 'HOLD' : 'FAIL',
      lens: 'DH6',
    );
  }
  // Fold-to-card/stripe é excepção explícita do fail-closed — HOLD se
  // o compacto NÃO é card/stripe e mesmo assim abriu, OU se suffix mbway abriu.
  final countedOpen = openedTags
      .where((t) => t != 'C3-FWCARD' && t != 'C3-CYRCARD')
      .toList();
  if (countedOpen.isNotEmpty) {
    c.hold(
      id: 'P1-C3',
      lens: 'DH6',
      severity: 'P1',
      title: 'off-platform encode novo abriu Stripe: ${countedOpen.join(",")}',
      actor: 'buyer JWT',
      pre: 'payment_method ASCII suffix/prefix/rails novos (não omega/math)',
      repro: 'CPI por encode',
      expected: '400 off-platform nos que compactam para mbway/transfer* ou rails off',
      obtained: {
        'opened': countedOpen,
        for (final t in countedOpen) t: encodeHits[t],
      },
    );
  } else {
    c.block('C3-ENCODES', 'DH6', 'encodes novos negados ou só fold-to-card', {
      'openedAll': openedTags,
      'counted': countedOpen,
    });
  }

  // C4 transferência legítima → off (400 Stripe)
  final c4 = await probeEncode(c, tag: 'c4-transf', payment: 'transferência');
  recordHoldOrFail(
    c: c,
    probeId: 'C4',
    poco: 'DH-C',
    lens: 'DH6',
    payload: 'payment_method=transferência (PT legítimo)',
    http: c4['cpi'],
    bd: c4,
    isHold: c4['opened'] == true || c4['denied'] != true,
    holdId: 'P1-C4',
    severity: 'P1',
    title: 'transferência legítima abriu Stripe',
    actor: 'buyer JWT',
    pre: 'payment_method=transferência',
    repro: 'CPI',
    expected: '400 off-platform; SQL true; sem cs_',
    obtained: c4,
    blockId: 'C4-TRANSFERENCIA',
    blockTitle: 'transferência 400 off-platform',
  );

  // C5 Stripe TEST pago 4242 + caixa
  final paid = await c.payToPago(lens: 'DH8', initialQty: 2);
  if (paid == null) {
    c.skip('C5', 'DH8', 'setup_paid_order falhou', 'null');
    c.probe(
      id: 'C5',
      poco: 'DH-C',
      payload: 'setup_paid_order Stripe TEST 4242',
      http: 'null',
      bd: '-',
      verdict: 'SKIP',
      lens: 'DH8',
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
    }, lens: 'DH8', well: 'DH-C');
    recordHoldOrFail(
      c: c,
      probeId: 'C5',
      poco: 'DH-C',
      lens: 'DH8',
      payload: 'setup_paid_order Stripe TEST 4242',
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

  // Anti-atrofia (≤2 linhas HOLD, não contar): mb way exact, omega, math, Paysafe
  final ctrl = <String, String>{
    'CTRL-MBWAY': 'mb way',
    'CTRL-OMEGA': 'mb\u03C9ay',
    'CTRL-MATH':
        String.fromCharCodes(const [0x1D5DC, 0x1D5D5, 0x1D5E0, 0x1D5D4, 0x1D5E2]),
    'CTRL-PAYSAFE': 'PaysafeCash',
  };
  for (final e in ctrl.entries) {
    final r = await probeEncode(
      c,
      tag: 'ctrl-${e.key.toLowerCase()}',
      payment: e.value,
    );
    c.note(e.key, 'anti-atrofia ${e.key}', r, lens: 'DH6', well: 'DH-C');
    final rateLimited = '${r['cpi']}'.contains('429');
    if (rateLimited) {
      c.skip(e.key, 'DH6', '429 rate-limit', r['cpi']);
      c.probe(
        id: e.key,
        poco: 'DH-C',
        payload: e.key,
        http: r['cpi'],
        bd: r,
        verdict: 'SKIP',
        lens: 'DH6',
      );
      continue;
    }
    recordHoldOrFail(
      c: c,
      probeId: e.key,
      poco: 'DH-C',
      lens: 'DH6',
      payload: 'anti-atrofia ${e.key}',
      http: r['cpi'],
      bd: r,
      isHold: r['opened'] == true,
      holdId: 'P1-${e.key}',
      severity: 'P1',
      title: 'anti-atrofia ${e.key} abriu Stripe',
      actor: 'buyer JWT',
      pre: e.key,
      repro: 'CPI',
      expected: e.key.contains('PAYSAFE')
          ? 'rails residual conhecido'
          : '400 off-platform (DBDG)',
      obtained: r,
      blockId: '${e.key}-BLOCK',
      blockTitle: '${e.key} sem Stripe (ou rails residual)',
      countFinding: false,
    );
  }
}

/// DH-D Cross
Future<void> dhDCross(Rtdb c) async {
  c.wellsTried.add('DH-D');

  // D1 bag cross-seller → deny
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
    poco: 'DH-D',
    lens: 'DH3',
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

  // D2 qty hostil / stock claim
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
      poco: 'DH-D',
      lens: 'DH4',
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
  }
}
