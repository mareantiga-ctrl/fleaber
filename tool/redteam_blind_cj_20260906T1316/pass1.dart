/// RED TEAM CEGO CJ pass1 — marketplace / saco / checkout pós-CDCI.
/// Matriz obrigatória A1–A8 · B1–B5 · C1–C5 · D1–D2. Sem correções.
import 'dart:io';

import '_rtcj.dart';

Future<void> main() async {
  final c = Rtcj.fromEnv(loadEnv());
  stdout.writeln('CJ pass1 staging=${c.url} prefix=$prefix');
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
  c.note('CJ8.wallet.pre', 'baseline', wallets0, lens: 'CJ8', well: 'CJ-D');

  await cjAClaimSession(c);
  await cjBPriceCouponShip(c);
  await cjCStockRace(c);
  await cjDFsmPaid(c, wallets0);

  final wallets1 = await c.wallets();
  c.note('CJ8.wallet.post', 'após probes', {
    'pre': wallets0,
    'post': wallets1,
  }, lens: 'CJ8', well: 'CJ-D');

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
  Rtcj c, {
  required int n,
  required String tag,
  int qty = 3,
  double price = 12,
  String? buyer,
  String? jwt,
  String? seller,
  String shipping = 'entrega em mão',
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

Future<int> openPayableCount(Rtcj c, Iterable<String> sids) async {
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

/// CJ-A Claim / Session
Future<void> cjAClaimSession(Rtcj c) async {
  c.wellsTried.add('CJ-A');

  // A1 TTL−10s dual reclaim A∥B (token ainda válido; NÃO é reclaim clássico órfão)
  final a1 = await mkSkus(c, n: 1, tag: 'a1-ttl-10', qty: 2);
  if (a1.length == 1) {
    final tok = c.claimToken(ageMs: claimTtlMs - 10000, tail: 'ttlminus10aabbcc');
    await c.plantClaim(a1.first.oid, tok);
    final hits = await parallel([
      c.checkout(orderId: a1.first.oid, productId: a1.first.pid, amount: 1),
      c.checkout(orderId: a1.first.oid, productId: a1.first.pid, amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    final row = await c.orderRow(a1.first.oid);
    final sid = '${row?['stripe_checkout_session_id'] ?? ''}';
    final sids = {...openCs(hits), if (sid.startsWith('cs_')) sid};
    final payable = await openPayableCount(c, sids);
    final briefs = hits.map((h) => h.brief).toList();
    c.note('A1.ttl-10', 'TTL-10s dual CPI', {
      'tok': tok,
      'stored': sid,
      'payable': payable,
      'briefs': briefs,
    }, lens: 'CJ2', well: 'CJ-A');
    if (payable >= 2) {
      c.hold(
        id: 'P0-A1',
        lens: 'CJ6',
        severity: 'P0',
        title: 'TTL−10s: 2 Sessions pagáveis no dual reclaim',
        actor: 'buyer JWT ×2',
        pre: 'claiming:<now-80s> plantado (TTL 90s)',
        repro: 'Future.wait 2× create-payment-intent',
        expected: 'wait/contention ≤1 cs_',
        obtained: {'sids': sids.toList(), 'payable': payable, 'briefs': briefs},
      );
      c.probe(
        id: 'A1',
        poco: 'CJ-A',
        payload: 'Future.wait 2×CPI com claiming TTL−10s ($tok)',
        http: briefs,
        bd: {'stored': sid, 'payable': payable},
        verdict: 'HOLD',
        lens: 'CJ6',
      );
    } else {
      c.block('A1-TTL-10', 'CJ2', 'TTL−10s dual ≤1 Session', {
        'stored': sid,
        'payable': payable,
        'briefs': briefs,
      });
      c.probe(
        id: 'A1',
        poco: 'CJ-A',
        payload: 'Future.wait 2×CPI claiming TTL−10s',
        http: briefs,
        bd: {'stored': sid, 'payable': payable},
        verdict: 'FAIL',
        lens: 'CJ2',
      );
    }
  } else {
    c.skip('A1', 'CJ2', 'não criou SKU', 'mkSkus empty');
    c.probe(
      id: 'A1',
      poco: 'CJ-A',
      payload: 'TTL−10s dual reclaim',
      http: 'skip fixture',
      bd: '-',
      verdict: 'SKIP',
      lens: 'CJ2',
    );
  }

  // A2 TTL+1s reclaim (token expirado deve libertar slot)
  final a2 = await mkSkus(c, n: 1, tag: 'a2-ttl-plus', qty: 2);
  if (a2.length == 1) {
    final tok = c.claimToken(ageMs: claimTtlMs + 1000, tail: 'ttlplus1saabbccdd');
    await c.plantClaim(a2.first.oid, tok);
    final hit = await c.checkout(
      orderId: a2.first.oid,
      productId: a2.first.pid,
      amount: 1,
    );
    c.trackSession(hit);
    final row = await c.orderRow(a2.first.oid);
    final sid = '${row?['stripe_checkout_session_id'] ?? ''}';
    c.note('A2.ttl+1', 'TTL+1s reclaim', {
      'tok': tok,
      'hit': hit.brief,
      'stored': sid,
    }, lens: 'CJ2', well: 'CJ-A');
    final reclaimed = hit.ok && sid.startsWith('cs_');
    final stuck = sid.startsWith('claiming:');
    if (stuck && !hit.ok) {
      c.hold(
        id: 'P2-A2',
        lens: 'CJ2',
        severity: 'P2',
        title: 'TTL+1s não reclaim — slot claiming: preso',
        actor: 'buyer JWT',
        pre: 'claiming:<now-91s>',
        repro: 'POST create-payment-intent após TTL+1s',
        expected: 'action create + cs_',
        obtained: {'hit': hit.brief, 'stored': sid},
      );
      c.probe(
        id: 'A2',
        poco: 'CJ-A',
        payload: 'CPI após claiming TTL+1s ($tok)',
        http: hit,
        bd: sid,
        verdict: 'HOLD',
        lens: 'CJ2',
      );
    } else {
      c.block('A2-TTL-PLUS', 'CJ2', reclaimed ? 'TTL+1s reclaim OK' : 'TTL+1s sem cs_ mas não stuck', {
        'hit': hit.brief,
        'stored': sid,
      });
      c.probe(
        id: 'A2',
        poco: 'CJ-A',
        payload: 'CPI após claiming TTL+1s',
        http: hit,
        bd: sid,
        verdict: 'FAIL',
        lens: 'CJ2',
      );
    }
  }

  // A3 Session expire Stripe → 2.ª Session mesma order
  final a3 = await mkSkus(c, n: 1, tag: 'a3-expire', qty: 2);
  if (a3.length == 1) {
    final first = await c.checkout(
      orderId: a3.first.oid,
      productId: a3.first.pid,
      amount: 1,
    );
    c.trackSession(first);
    final sid0 = first.sessionId ?? '';
    HttpHit expireHit;
    var path = 'stripe.expire';
    if (sid0.startsWith('cs_') && c.stripeTestKey != null) {
      expireHit = await c.stripeExpire(sid0);
    } else {
      path = 'plant cs_test_dead + CPI';
      expireHit = await c.plantClaim(
        a3.first.oid,
        'cs_test_deaddeaddeaddeaddead12',
      );
    }
    final second = await c.checkout(
      orderId: a3.first.oid,
      productId: a3.first.pid,
      amount: 1,
    );
    c.trackSession(second);
    final row = await c.orderRow(a3.first.oid);
    final sid1 = '${row?['stripe_checkout_session_id'] ?? ''}';
    final sids = {if (sid0.startsWith('cs_')) sid0, if (sid1.startsWith('cs_')) sid1};
    final payable = await openPayableCount(c, sids);
    c.note('A3.expire', 'expire/dead → 2.ª Session', {
      'path': path,
      'first': first.brief,
      'expire': expireHit.brief,
      'second': second.brief,
      'stored': sid1,
      'payable': payable,
    }, lens: 'CJ2', well: 'CJ-A');
    if (payable >= 2) {
      c.hold(
        id: 'P0-A3',
        lens: 'CJ2',
        severity: 'P0',
        title: 'Após expire/dead, 2 Sessions pagáveis na mesma order',
        actor: 'buyer JWT',
        pre: 'cs_ open depois expire ou cs_ morta',
        repro: path,
        expected: '≤1 open payable',
        obtained: {'sids': sids.toList(), 'payable': payable},
      );
      c.probe(
        id: 'A3',
        poco: 'CJ-A',
        payload: '$path; 2.º CPI mesma order',
        http: {'first': first.brief, 'second': second.brief, 'expire': expireHit.brief},
        bd: {'stored': sid1, 'payable': payable},
        verdict: 'HOLD',
        lens: 'CJ2',
      );
    } else if (!second.ok && sid1.startsWith('cs_test_dead')) {
      c.hold(
        id: 'P2-A3',
        lens: 'CJ2',
        severity: 'P2',
        title: 'cs_ morta bloqueia reclaim (DoS checkout)',
        actor: 'buyer JWT',
        pre: 'stripe_checkout_session_id=cs_test_dead…',
        repro: 'POST create-payment-intent',
        expected: 'reclaim + nova cs_',
        obtained: {'second': second.brief, 'stored': sid1},
      );
      c.probe(
        id: 'A3',
        poco: 'CJ-A',
        payload: 'CPI com cs_ morta plantada',
        http: second,
        bd: sid1,
        verdict: 'HOLD',
        lens: 'CJ2',
      );
    } else {
      c.block('A3-EXPIRE', 'CJ2', 'expire/dead não deixou 2 pagáveis', {
        'second': second.brief,
        'stored': sid1,
        'payable': payable,
      });
      c.probe(
        id: 'A3',
        poco: 'CJ-A',
        payload: '$path; 2.º CPI',
        http: {'first': first.brief, 'second': second.brief},
        bd: {'stored': sid1, 'payable': payable},
        verdict: 'FAIL',
        lens: 'CJ2',
      );
    }
  }

  // A4 crash/timeout mid-claim + retry
  final a4 = await mkSkus(c, n: 2, tag: 'a4-crash', qty: 2);
  if (a4.length == 2) {
    final lines = bagLines(a4);
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
      '${(await c.orderRow(a4[0].oid))?['stripe_checkout_session_id'] ?? ''}',
      '${(await c.orderRow(a4[1].oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final sids = {
      ...openCs(pair),
      ...stored.where((s) => s.startsWith('cs_')),
    };
    final payable = await openPayableCount(c, sids);
    final briefs = pair.map((h) => h.brief).toList();
    c.note('A4.timeout', 'timeout 250ms ∥ retry', {
      'briefs': briefs,
      'stored': stored,
      'payable': payable,
    }, lens: 'CJ6', well: 'CJ-A');
    if (payable >= 2) {
      c.hold(
        id: 'P0-A4',
        lens: 'CJ6',
        severity: 'P0',
        title: 'Timeout mid-claim + retry = 2 cs_ pagáveis',
        actor: 'buyer JWT',
        pre: '2-line bag',
        repro: 'Future.wait checkoutBag timeout 250ms ∥ retry',
        expected: '≤1 cs_',
        obtained: {'sids': sids.toList(), 'stored': stored},
      );
      c.probe(
        id: 'A4',
        poco: 'CJ-A',
        payload: 'Future.wait bag timeout 250ms ∥ retry',
        http: briefs,
        bd: {'stored': stored, 'payable': payable},
        verdict: 'HOLD',
        lens: 'CJ6',
      );
    } else {
      c.block('A4-TIMEOUT', 'CJ6', 'timeout∥retry ≤1 Session', {
        'payable': payable,
        'stored': stored,
      });
      c.probe(
        id: 'A4',
        poco: 'CJ-A',
        payload: 'Future.wait bag timeout 250ms ∥ retry',
        http: briefs,
        bd: {'stored': stored, 'payable': payable},
        verdict: 'FAIL',
        lens: 'CJ6',
      );
    }
  }

  // A5 bag 4-line ∥ bag 2-line overlap parcial (≠ 5∥3 CDCI / ≠ A∩B∩C)
  final a5 = await mkSkus(c, n: 4, tag: 'a5-4x2', qty: 2, price: 9);
  if (a5.length == 4) {
    final four = bagLines(a5);
    final two = bagLines(a5.sublist(2)); // SKUs 2+3 overlap
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
      for (final r in a5)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    c.note('A5.4x2', 'bag 4-line ∥ 2-line overlap', {
      'sids': sids.toList(),
      'payable': payable,
      'briefs': briefs,
      'stored': stored,
    }, lens: 'CJ6', well: 'CJ-A');
    if (payable >= 2) {
      c.hold(
        id: 'P0-A5',
        lens: 'CJ6',
        severity: 'P0',
        title: 'Overlap 4∥2: 2 Sessions pagáveis',
        actor: 'buyer JWT',
        pre: '4 SKUs; bag ABCD ∥ bag CD',
        repro: 'Future.wait bag 4-line ∥ bag 2-line',
        expected: '≤1 cs_ open (intersect)',
        obtained: {'sids': sids.toList(), 'payable': payable, 'stored': stored},
      );
      c.probe(
        id: 'A5',
        poco: 'CJ-A',
        payload: 'Future.wait bag 4-line ∥ bag 2-line overlap CD',
        http: briefs,
        bd: {'sids': sids.toList(), 'stored': stored, 'payable': payable},
        verdict: 'HOLD',
        lens: 'CJ6',
      );
    } else {
      c.block('A5-4x2', 'CJ6', 'overlap 4∥2 ≤1 pagável', {
        'sids': sids.toList(),
        'payable': payable,
      });
      c.probe(
        id: 'A5',
        poco: 'CJ-A',
        payload: 'Future.wait bag 4-line ∥ bag 2-line overlap',
        http: briefs,
        bd: {'sids': sids.toList(), 'payable': payable, 'stored': stored},
        verdict: 'FAIL',
        lens: 'CJ6',
      );
    }
  }

  // A6 PATCH qty/price com Session open
  final a6 = await mkSkus(c, n: 1, tag: 'a6-drift', qty: 5, price: 15);
  if (a6.length == 1) {
    final d = a6.first;
    final ck = await c.checkout(orderId: d.oid, productId: d.pid, amount: 1);
    c.trackSession(ck);
    final amt0 = ck.amountTotal;
    final patchQty = await c.rest(
      'PATCH',
      'orders?id=eq.${d.oid}',
      jwt: c.buyerJwt,
      body: {'quantity': 4, 'price_total': 1},
    );
    final patchPrice = await c.rest(
      'PATCH',
      'products?id=eq.${d.pid}',
      jwt: c.sellerJwt,
      body: {'price': 1},
    );
    final ck2 = await c.checkout(orderId: d.oid, productId: d.pid, amount: 1);
    c.trackSession(ck2);
    final amt1 = ck2.amountTotal;
    final row = await c.orderRow(d.oid);
    c.note('A6.drift', 'PATCH qty/price Session open', {
      'ck0': ck.brief,
      'patchQty': patchQty.brief,
      'patchPrice': patchPrice.brief,
      'ck2': ck2.brief,
      'amt0': amt0,
      'amt1': amt1,
      'contract': row?['contract_unit_cents'],
    }, lens: 'CJ1', well: 'CJ-A');
    if (ck.ok && ck2.ok && amt0 != null && amt1 != null && amt1 < amt0 - 50) {
      c.hold(
        id: 'P0-A6',
        lens: 'CJ1',
        severity: 'P0',
        title: 'Drift qty/price baixou amount_total da Session',
        actor: 'buyer JWT + seller JWT',
        pre: 'Session open',
        repro: 'CPI; PATCH qty/price; CPI',
        expected: 'amount_total estável',
        obtained: {'amt0': amt0, 'amt1': amt1},
      );
      c.probe(
        id: 'A6',
        poco: 'CJ-A',
        payload: 'PATCH order.qty=4 price_total=1 + product.price=1 com Session open',
        http: {'ck0': ck.brief, 'patchQty': patchQty.brief, 'ck2': ck2.brief},
        bd: {'amt0': amt0, 'amt1': amt1, 'contract': row?['contract_unit_cents']},
        verdict: 'HOLD',
        lens: 'CJ1',
      );
    } else {
      c.block('A6-DRIFT', 'CJ1', 'drift não baixou Session', {
        'amt0': amt0,
        'amt1': amt1,
        'patchQty': patchQty.status,
      });
      c.probe(
        id: 'A6',
        poco: 'CJ-A',
        payload: 'PATCH qty/price com Session open',
        http: {'ck0': ck.brief, 'patchQty': patchQty.brief, 'ck2': ck2.brief},
        bd: {'amt0': amt0, 'amt1': amt1},
        verdict: 'FAIL',
        lens: 'CJ1',
      );
    }
  }

  // A7 settle GET unpaid + orphan PI list
  final a7 = await mkSkus(c, n: 1, tag: 'a7-settle', qty: 2);
  if (a7.length == 1) {
    final ck = await c.checkout(
      orderId: a7.first.oid,
      productId: a7.first.pid,
      amount: 1,
    );
    c.trackSession(ck);
    final sid = ck.sessionId ?? '';
    HttpHit settle = HttpHit(0, 'no_sid', {'error': 'no_sid'});
    if (sid.startsWith('cs_')) {
      settle = await c.settleGet(sid);
    }
    final row = await c.orderRow(a7.first.oid);
    var stripeListN = 0;
    var dualPi = false;
    if (c.stripeTestKey != null) {
      final listed = await c.stripeListSessions(limit: 20);
      final data = listed.list.isNotEmpty
          ? listed.list
          : ((listed.map?['data'] as List?) ?? const []);
      stripeListN = data.length;
    }
    final pi = '${row?['stripe_payment_intent_id'] ?? ''}';
    final storedSid = '${row?['stripe_checkout_session_id'] ?? ''}';
    dualPi = storedSid.startsWith('cs_') && pi.startsWith('pi_') &&
        '${row?['status']}' == 'reserva_pendente';
    c.note('A7.settle', 'GET settle unpaid', {
      'ck': ck.brief,
      'settle': settle.brief,
      'pi': pi,
      'sid': storedSid,
      'stripe_list_n': stripeListN,
      'unpaid_with_pi': dualPi,
    }, lens: 'CJ8', well: 'CJ-A');
    final paidViaSettle = settle.ok &&
        '${(await c.orderRow(a7.first.oid))?['status']}' == 'pago';
    if (paidViaSettle) {
      c.hold(
        id: 'P0-A7',
        lens: 'CJ8',
        severity: 'P0',
        title: 'GET settle unpaid marcou order como pago',
        actor: 'anon GET',
        pre: 'Session open unpaid',
        repro: 'GET create-payment-intent?checkout_return=success&session_id=',
        expected: '402 unpaid',
        obtained: settle.brief,
      );
      c.probe(
        id: 'A7',
        poco: 'CJ-A',
        payload: 'GET settle unpaid + list orphan PI',
        http: settle,
        bd: {'status': row?['status'], 'pi': pi, 'sid': storedSid},
        verdict: 'HOLD',
        lens: 'CJ8',
      );
    } else {
      c.block('A7-SETTLE', 'CJ8', 'settle unpaid não pagou', {
        'settle': settle.status,
        'status': row?['status'],
      });
      c.probe(
        id: 'A7',
        poco: 'CJ-A',
        payload: 'GET settle unpaid + orphan PI (ledger cs_ sem captura)',
        http: settle,
        bd: {
          'status': row?['status'],
          'pi': pi,
          'sid': storedSid,
          'stripe_list_n': stripeListN,
        },
        verdict: 'FAIL',
        lens: 'CJ8',
      );
    }
  }

  // A8 claim token malformado — 3 variantes (abc / sem ms / ms futuro)
  await a8Malformed(c, 'A8a', 'claiming:abc', 'claiming:abc legado curto');
  await a8Malformed(c, 'A8b', 'claiming:', 'claiming: sem ms');
  final futureMs = DateTime.now().millisecondsSinceEpoch + 86400000 * 365;
  await a8Malformed(
    c,
    'A8c',
    'claiming:$futureMs:futuretoken12ab',
    'claiming ms futuro +1y',
    futureDos: true,
  );
}

Future<void> a8Malformed(
  Rtcj c,
  String id,
  String token,
  String label, {
  bool futureDos = false,
}) async {
  final sku = await mkSkus(c, n: 1, tag: id.toLowerCase(), qty: 2);
  if (sku.isEmpty) {
    c.probe(
      id: id,
      poco: 'CJ-A',
      payload: label,
      http: 'skip',
      bd: '-',
      verdict: 'SKIP',
      lens: 'CJ2',
    );
    return;
  }
  await c.plantClaim(sku.first.oid, token);
  final rpc = await c.rpc('batata_bag_checkout_claim', {
    'p_order_ids': [sku.first.oid],
    'p_claim_token': 'claiming:${DateTime.now().millisecondsSinceEpoch}:probe$id',
  }, jwt: c.buyerJwt);
  final hit = await c.checkout(
    orderId: sku.first.oid,
    productId: sku.first.pid,
    amount: 1,
  );
  c.trackSession(hit);
  final row = await c.orderRow(sku.first.oid);
  final sid = '${row?['stripe_checkout_session_id'] ?? ''}';
  c.note('$id.malformed', label, {
    'token': token,
    'rpc_jwt': rpc.brief,
    'cpi': hit.brief,
    'stored': sid,
  }, lens: 'CJ2', well: 'CJ-A');
  final stuckClaim = sid.startsWith('claiming:') && !hit.ok;
  if (futureDos && stuckClaim) {
    c.hold(
      id: 'P2-A8C',
      lens: 'CJ2',
      severity: 'P2',
      title: 'claiming: com ms futuro prende o slot (TTL nunca expira)',
      actor: 'buyer JWT (plant observação)',
      pre: token,
      repro: 'POST create-payment-intent',
      expected: 'reclaim ou TTL finito',
      obtained: {'cpi': hit.brief, 'stored': sid, 'rpc_jwt': rpc.brief},
    );
    c.probe(
      id: id,
      poco: 'CJ-A',
      payload: label,
      http: {'rpc_jwt': rpc.brief, 'cpi': hit.brief},
      bd: sid,
      verdict: 'HOLD',
      lens: 'CJ2',
    );
  } else if (rpc.ok && rpc.map?['ok'] == true && rpc.map?['action'] == 'create') {
    c.hold(
      id: 'P1-A8',
      lens: 'CJ7',
      severity: 'P1',
      title: 'buyer JWT executa batata_bag_checkout_claim',
      actor: 'buyer JWT',
      pre: token,
      repro: 'POST rpc batata_bag_checkout_claim',
      expected: '42501 / grant só service_role',
      obtained: rpc.brief,
    );
    c.probe(
      id: id,
      poco: 'CJ-A',
      payload: '$label + rpc JWT',
      http: rpc,
      bd: sid,
      verdict: 'HOLD',
      lens: 'CJ7',
    );
  } else {
    c.block('$id', 'CJ2', '$label: JWT rpc negado / CPI tratado', {
      'rpc': rpc.status,
      'cpi': hit.status,
      'stored': sid,
    });
    c.probe(
      id: id,
      poco: 'CJ-A',
      payload: label,
      http: {'rpc_jwt': rpc.brief, 'cpi': hit.brief},
      bd: sid,
      verdict: 'FAIL',
      lens: 'CJ2',
    );
  }
}

/// CJ-B Preço / coupon / portes
Future<void> cjBPriceCouponShip(Rtcj c) async {
  c.wellsTried.add('CJ-B');

  // B1 coupon outro seller / expirado / Unicode
  final b1 = await mkSkus(c, n: 1, tag: 'b1-coupon', qty: 2, price: 18);
  if (b1.isNotEmpty) {
    final o = b1.first;
    final couponBody = await c.checkout(
      orderId: o.oid,
      productId: o.pid,
      amount: 1,
      extra: {
        'coupon': 'SELLER2-50',
        'coupon_code': 'SELLER2-50',
        'promo_code': 'ＳＥＬＬＥＲ２',
        'discount_cents': 1700,
        'discount_pct': 90,
      },
    );
    c.trackSession(couponBody);
    c.note('B1.coupon-body', 'coupon outro seller + unicode no body', {
      'hit': couponBody.brief,
      'amt': couponBody.amountTotal,
    }, lens: 'CJ1', well: 'CJ-B');
    if (couponBody.ok &&
        couponBody.amountTotal != null &&
        couponBody.amountTotal! < 500) {
      c.hold(
        id: 'P0-B1',
        lens: 'CJ1',
        severity: 'P0',
        title: 'coupon_code/discount_cents baixou Session abaixo do catálogo',
        actor: 'buyer JWT',
        pre: 'SKU 18€',
        repro: 'CPI coupon=SELLER2-50 discount_cents=1700',
        expected: 'ignorar coupon; Session ≥18€+protecção',
        obtained: couponBody.brief,
      );
      c.probe(
        id: 'B1a',
        poco: 'CJ-B',
        payload: 'CPI coupon SELLER2-50 + discount_cents=1700 + promo fullwidth',
        http: couponBody,
        bd: couponBody.amountTotal,
        verdict: 'HOLD',
        lens: 'CJ1',
      );
    } else {
      c.block('B1a-COUPON-BODY', 'CJ1', 'coupon body ignorado/rejeitado', {
        'amt': couponBody.amountTotal,
        'status': couponBody.status,
      });
      c.probe(
        id: 'B1a',
        poco: 'CJ-B',
        payload: 'CPI coupon outro seller + Unicode + discount_cents',
        http: couponBody,
        bd: couponBody.amountTotal,
        verdict: 'FAIL',
        lens: 'CJ1',
      );
    }

    // oferta expirada / rejeitada reutilizada
    final off = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
      'product_id': o.pid,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'amount': 2,
      'list_price': 18,
      'offered_by': 'buyer',
      'status': 'pending',
    });
    final offId = off.firstId;
    if (offId != null) {
      c.createdOfferIds.add(offId);
      await c.rest(
        'PATCH',
        'product_offers?id=eq.$offId',
        jwt: c.sellerJwt,
        body: {'status': 'rejected'},
      );
      final oid2 = await c.insertOrder(
        productId: o.pid,
        price: 2,
        offerId: offId,
        jwt: c.buyerJwt,
      );
      if (oid2 != null) {
        final ck = await c.checkout(orderId: oid2, productId: o.pid, amount: 1);
        c.trackSession(ck);
        c.note('B1.expired-offer', 'offer rejected no checkout', {
          'off': off.brief,
          'ck': ck.brief,
          'amt': ck.amountTotal,
        }, lens: 'CJ3', well: 'CJ-B');
        if (ck.ok && ck.amountTotal != null && ck.amountTotal! < 400) {
          c.hold(
            id: 'P0-B1b',
            lens: 'CJ3',
            severity: 'P0',
            title: 'Offer rejected/expirada ainda congela preço 2€',
            actor: 'buyer JWT',
            pre: 'product_offers.status=rejected amount=2',
            repro: 'INSERT order product_offer_id; CPI',
            expected: 'catálogo 18€ ou bloqueio',
            obtained: ck.brief,
          );
          c.probe(
            id: 'B1b',
            poco: 'CJ-B',
            payload: 'checkout com product_offer rejected amount=2',
            http: ck,
            bd: ck.amountTotal,
            verdict: 'HOLD',
            lens: 'CJ3',
          );
        } else {
          c.block('B1b-OFFER-REJECTED', 'CJ3', 'offer rejected não underpay', {
            'amt': ck.amountTotal,
            'status': ck.status,
          });
          c.probe(
            id: 'B1b',
            poco: 'CJ-B',
            payload: 'offer rejected/expirada no checkout',
            http: ck,
            bd: ck.amountTotal,
            verdict: 'FAIL',
            lens: 'CJ3',
          );
        }
      }
    } else {
      c.probe(
        id: 'B1b',
        poco: 'CJ-B',
        payload: 'offer rejected',
        http: off,
        bd: '-',
        verdict: 'SKIP',
        lens: 'CJ3',
      );
    }

    // coupon/offer de outro seller (seller2 offer id colado na order seller1)
    final p2 = await c.createProduct(
      seller: c.seller2Id,
      title: '$prefix-b1-s2',
      qty: 2,
      price: 40,
    );
    if (p2 != null) {
      final off2 = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
        'product_id': p2,
        'buyer_id': c.buyerId,
        'seller_id': c.seller2Id,
        'amount': 1,
        'list_price': 40,
        'offered_by': 'buyer',
        'status': 'pending',
      });
      final oidOff2 = off2.firstId;
      if (oidOff2 != null) {
        c.createdOfferIds.add(oidOff2);
        await c.rest(
          'PATCH',
          'product_offers?id=eq.$oidOff2',
          jwt: c.seller2Jwt,
          body: {'status': 'accepted'},
        );
        final hijack = await c.insertOrder(
          productId: o.pid,
          price: 1,
          offerId: oidOff2,
          jwt: c.buyerJwt,
        );
        if (hijack != null) {
          final ck = await c.checkout(
            orderId: hijack,
            productId: o.pid,
            amount: 1,
          );
          c.trackSession(ck);
          c.note('B1.cross-seller-offer', 'offer seller2 em SKU seller1', {
            'ck': ck.brief,
            'amt': ck.amountTotal,
          }, lens: 'CJ7', well: 'CJ-B');
          if (ck.ok && ck.amountTotal != null && ck.amountTotal! < 400) {
            c.hold(
              id: 'P0-B1c',
              lens: 'CJ7',
              severity: 'P0',
              title: 'Offer de outro seller baixou preço do SKU',
              actor: 'buyer JWT',
              pre: 'offer aceite seller2 colada em order seller1',
              repro: 'INSERT order product_offer_id alheio; CPI',
              expected: 'ignorar offer / bloqueio',
              obtained: ck.brief,
            );
            c.probe(
              id: 'B1c',
              poco: 'CJ-B',
              payload: 'offer seller2 aceite colada em SKU seller1',
              http: ck,
              bd: ck.amountTotal,
              verdict: 'HOLD',
              lens: 'CJ7',
            );
          } else {
            c.block('B1c-CROSS-OFFER', 'CJ7', 'offer outro seller não underpay', {
              'amt': ck.amountTotal,
              'status': ck.status,
            });
            c.probe(
              id: 'B1c',
              poco: 'CJ-B',
              payload: 'coupon/offer outro seller',
              http: ck,
              bd: ck.amountTotal,
              verdict: 'FAIL',
              lens: 'CJ7',
            );
          }
        }
      }
    }
  }

  // B2 portes 0 / negativo no body (order selada CTT)
  final b2 = await mkSkus(
    c,
    n: 1,
    tag: 'b2-ship',
    qty: 2,
    price: 12,
    shipping: 'envio transportadora (€3.50)',
  );
  if (b2.isNotEmpty) {
    final o = b2.first;
    final hit0 = await c.checkout(
      orderId: o.oid,
      productId: o.pid,
      amount: 1,
      shipping: 'mao',
      extra: {
        'shipping': 0,
        'shipping_cents': -350,
        'shipping_amount': 0,
        'prize_shipping': false,
      },
    );
    c.trackSession(hit0);
    final hitNeg = await c.checkout(
      orderId: o.oid,
      productId: o.pid,
      amount: 1,
      shipping: '-3.50',
      extra: {'shipping_cents': -1},
    );
    c.note('B2.portes', 'portes 0/negativo body vs selo CTT', {
      'mao_body': hit0.brief,
      'neg': hitNeg.brief,
      'amt0': hit0.amountTotal,
      'amtNeg': hitNeg.amountTotal,
    }, lens: 'CJ1', well: 'CJ-B');
    final under = (hit0.ok &&
            hit0.amountTotal != null &&
            hit0.amountTotal! < 1200) ||
        (hitNeg.ok && hitNeg.amountTotal != null && hitNeg.amountTotal! < 500);
    if (under) {
      c.hold(
        id: 'P0-B2',
        lens: 'CJ1',
        severity: 'P0',
        title: 'Body portes 0/negativo baixou Session abaixo do selo CTT',
        actor: 'buyer JWT',
        pre: 'order.shipping_method=CTT 3,50€',
        repro: 'CPI shipping=mao shipping_cents=-350',
        expected: 'portes selados CTT; rejeitar método inválido',
        obtained: {'amt0': hit0.amountTotal, 'neg': hitNeg.brief},
      );
      c.probe(
        id: 'B2',
        poco: 'CJ-B',
        payload: 'portes 0 / shipping_cents=-350 / método -3.50 no body (selo CTT)',
        http: {'zero': hit0.brief, 'neg': hitNeg.brief},
        bd: {'amt0': hit0.amountTotal, 'amtNeg': hitNeg.amountTotal},
        verdict: 'HOLD',
        lens: 'CJ1',
      );
    } else {
      c.block('B2-PORTES', 'CJ1', 'portes hostis não baixaram / rejeitados', {
        'amt0': hit0.amountTotal,
        'neg': hitNeg.status,
      });
      c.probe(
        id: 'B2',
        poco: 'CJ-B',
        payload: 'portes 0 e negativo no body',
        http: {'zero': hit0.brief, 'neg': hitNeg.brief},
        bd: {'amt0': hit0.amountTotal, 'amtNeg': hitNeg.amountTotal},
        verdict: 'FAIL',
        lens: 'CJ1',
      );
    }
  }

  // B3 bundle total_eur hostil
  final b3 = await mkSkus(c, n: 2, tag: 'b3-bundle', qty: 2, price: 10);
  if (b3.length == 2) {
    final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'status': 'pending',
      'subtotal_eur': 20,
      'discount_pct': 50,
      'total_eur': 0.01,
      'product_ids': [b3[0].pid, b3[1].pid],
    });
    final bid = bun.firstId;
    if (bid != null) c.createdBundleIds.add(bid);
    HttpHit acc = HttpHit(0, 'no_bundle', {});
    if (bid != null) {
      acc = await c.rest(
        'PATCH',
        'product_bundles?id=eq.$bid',
        jwt: c.sellerJwt,
        body: {'status': 'accepted', 'total_eur': 0.01, 'discount_pct': 99},
      );
      for (final row in b3) {
        await c.rest(
          'PATCH',
          'orders?id=eq.${row.oid}',
          jwt: c.buyerJwt,
          body: {'bundle_id': bid},
        );
      }
    }
    final ck = await c.checkoutBag(lines: bagLines(b3), amount: 1);
    c.trackSession(ck);
    c.note('B3.bundle', 'total_eur=0.01 hostil', {
      'ins': bun.brief,
      'acc': acc.brief,
      'ck': ck.brief,
      'amt': ck.amountTotal,
    }, lens: 'CJ3', well: 'CJ-B');
    if (ck.ok && ck.amountTotal != null && ck.amountTotal! < 400) {
      c.hold(
        id: 'P0-B3',
        lens: 'CJ3',
        severity: 'P0',
        title: 'bundle total_eur=0.01 reflectido na Session',
        actor: 'buyer JWT',
        pre: '2 SKUs 10€; PATCH total_eur=0.01',
        repro: 'bag_checkout',
        expected: 'catálogo ou desconto seller cap 50%, não 1 cêntimo',
        obtained: ck.brief,
      );
      c.probe(
        id: 'B3',
        poco: 'CJ-B',
        payload: 'bundle total_eur=0.01 + discount_pct=99',
        http: {'ins': bun.brief, 'ck': ck.brief},
        bd: ck.amountTotal,
        verdict: 'HOLD',
        lens: 'CJ3',
      );
    } else {
      c.block('B3-BUNDLE', 'CJ3', 'total_eur hostil não baixou Session', {
        'amt': ck.amountTotal,
        'ins': bun.status,
      });
      c.probe(
        id: 'B3',
        poco: 'CJ-B',
        payload: 'bundle total_eur=0.01 hostil',
        http: {'ins': bun.brief, 'ck': ck.brief},
        bd: ck.amountTotal,
        verdict: 'FAIL',
        lens: 'CJ3',
      );
    }
  }

  // B4 offer amount freeze encoding NOVO (não ZWJ): arábico, científico, circled, NNBSP
  final encodings = <String, Object>{
    'arabic': '٨',
    'scientific': '8e-1',
    'circled': '⑧',
    'nnbsp': '8\u202F00',
    'fraction': '1⁄2',
  };
  var b4Held = false;
  HttpHit? b4Last;
  Object? b4Amt;
  for (final e in encodings.entries) {
    final pid = await c.createProduct(
      title: '$prefix-b4-${e.key}',
      price: 20,
      qty: 2,
    );
    if (pid == null) continue;
    final ins = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
      'product_id': pid,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'amount': e.value,
      'list_price': 20,
      'offered_by': 'buyer',
      'status': 'pending',
    });
    c.note('B4.${e.key}', 'offer encoding ${e.key}', ins.brief,
        lens: 'CJ3', well: 'CJ-B');
    if (ins.ok) {
      final oidOffer = ins.firstId;
      if (oidOffer != null) {
        c.createdOfferIds.add(oidOffer);
        await c.rest(
          'PATCH',
          'product_offers?id=eq.$oidOffer',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
        final order = await c.insertOrder(
          productId: pid,
          price: 0.5,
          offerId: oidOffer,
          jwt: c.buyerJwt,
        );
        if (order != null) {
          final ck = await c.checkout(orderId: order, productId: pid, amount: 1);
          c.trackSession(ck);
          b4Last = ck;
          b4Amt = ck.amountTotal;
          if (ck.ok && ck.amountTotal != null && ck.amountTotal! < 200) {
            b4Held = true;
            c.hold(
              id: 'P0-B4',
              lens: 'CJ3',
              severity: 'P0',
              title: 'Offer encoding ${e.key} → Session << 8€',
              actor: 'buyer JWT',
              pre: 'amount=${e.value}',
              repro: 'POST product_offers; accept; CPI',
              expected: 'rejeitar encoding ou freeze ≥ catálogo negociado honesto',
              obtained: ck.brief,
            );
            break;
          }
        }
      }
    } else {
      b4Last = ins;
    }
  }
  c.probe(
    id: 'B4',
    poco: 'CJ-B',
    payload: 'offer arabic/scientific/circled/NNBSP/fraction (não ZWJ)',
    http: b4Last?.brief ?? 'no hit',
    bd: b4Amt,
    verdict: b4Held ? 'HOLD' : 'FAIL',
    lens: 'CJ3',
  );
  if (!b4Held) {
    c.block('B4-OFFER-ENC', 'CJ3', 'encodings novos rejeitados ou sem underpay',
        b4Last?.brief);
  }

  // B5 currency non-EUR / fullwidth digits
  final b5 = await mkSkus(c, n: 1, tag: 'b5-ccy', qty: 2, price: 12);
  if (b5.isNotEmpty) {
    final o = b5.first;
    final usd = await c.checkout(
      orderId: o.oid,
      productId: o.pid,
      amount: 1,
      currency: 'usd',
    );
    final jpy = await c.checkout(
      orderId: o.oid,
      productId: o.pid,
      amount: 1,
      currency: 'jpy',
    );
    final fw = await c.checkout(
      orderId: o.oid,
      productId: o.pid,
      amount: '１２',
      currency: 'ｅｕｒ',
    );
    c.trackSession(usd);
    c.trackSession(jpy);
    c.trackSession(fw);
    c.note('B5.ccy', 'non-EUR / fullwidth', {
      'usd': usd.brief,
      'jpy': jpy.brief,
      'fw': fw.brief,
    }, lens: 'CJ1', well: 'CJ-B');
    final usdOk = usd.ok && (usd.amountTotal ?? 9999) < 500;
    if (usdOk || (jpy.ok && (jpy.amountTotal ?? 9999) < 200)) {
      c.hold(
        id: 'P0-B5',
        lens: 'CJ1',
        severity: 'P0',
        title: 'currency non-EUR criou Session abaixo do contrato',
        actor: 'buyer JWT',
        pre: 'SKU 12€',
        repro: 'CPI currency=usd|jpy',
        expected: 'only EUR is supported',
        obtained: {'usd': usd.brief, 'jpy': jpy.brief},
      );
      c.probe(
        id: 'B5',
        poco: 'CJ-B',
        payload: 'currency usd/jpy + amount １２ + ｅｕｒ',
        http: {'usd': usd.brief, 'jpy': jpy.brief, 'fw': fw.brief},
        bd: {
          'usd_amt': usd.amountTotal,
          'jpy_amt': jpy.amountTotal,
          'fw_amt': fw.amountTotal,
        },
        verdict: 'HOLD',
        lens: 'CJ1',
      );
    } else {
      c.block('B5-CCY', 'CJ1', 'non-EUR rejeitado / fullwidth não underpay', {
        'usd': usd.status,
        'jpy': jpy.status,
        'fw': fw.amountTotal,
      });
      c.probe(
        id: 'B5',
        poco: 'CJ-B',
        payload: 'currency usd/jpy + fullwidth digits',
        http: {'usd': usd.brief, 'jpy': jpy.brief, 'fw': fw.brief},
        bd: {
          'usd_amt': usd.amountTotal,
          'fw_amt': fw.amountTotal,
        },
        verdict: 'FAIL',
        lens: 'CJ1',
      );
    }
  }
}

/// CJ-C Stock / race
Future<void> cjCStockRace(Rtcj c) async {
  c.wellsTried.add('CJ-C');

  // C1 2 buyers última unidade
  final pid = await c.createProduct(title: '$prefix-c1-last', qty: 1, price: 11);
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
      c.note('C1.last', '2 buyers última unidade', {
        'ok': ok,
        'briefs': briefs,
      }, lens: 'CJ6', well: 'CJ-C');
      if (ok >= 2) {
        c.hold(
          id: 'P0-C1',
          lens: 'CJ5',
          severity: 'P0',
          title: '2 buyers Session na última unidade',
          actor: 'buyer + buyer2 JWT',
          pre: 'quantity=1; 2 orders',
          repro: 'Future.wait 2× CPI',
          expected: '1 Session + 1 stock block',
          obtained: briefs,
        );
        c.probe(
          id: 'C1',
          poco: 'CJ-C',
          payload: 'Future.wait 2 buyers CPI última unidade',
          http: briefs,
          bd: {'ok': ok},
          verdict: 'HOLD',
          lens: 'CJ5',
        );
      } else {
        c.block('C1-LAST', 'CJ5', 'última unidade ≤1 Session', {'ok': ok});
        c.probe(
          id: 'C1',
          poco: 'CJ-C',
          payload: 'Future.wait 2 buyers última unidade',
          http: briefs,
          bd: {'ok': ok},
          verdict: 'FAIL',
          lens: 'CJ5',
        );
      }
    }
  }

  // C2 checkout ∥ unlist
  final ul = await mkSkus(c, n: 1, tag: 'c2-unlist', qty: 2, price: 13);
  if (ul.length == 1) {
    final u = ul.first;
    final hits = await parallel([
      c.checkout(orderId: u.oid, productId: u.pid, amount: 1),
      c.rest(
        'PATCH',
        'products?id=eq.${u.pid}',
        jwt: c.sellerJwt,
        body: {'list_on_marketplace': false},
      ),
    ]);
    c.trackSession(hits[0]);
    final prod = await c.productRow(u.pid);
    c.note('C2.unlist', 'checkout ∥ unlist', {
      'ck': hits[0].brief,
      'listed': prod?['list_on_marketplace'],
    }, lens: 'CJ6', well: 'CJ-C');
    c.block('C2-UNLIST', 'CJ5', 'unlist∥checkout observado', {
      'ck': hits[0].brief,
      'listed': prod?['list_on_marketplace'],
    });
    final ckOkListedFalse = hits[0].ok && prod?['list_on_marketplace'] == false;
    // Dual payable oversell only if Session + listed false AND qty would oversell.
    // Unlist race with qty=2 is not P0 money; record FAIL (ataque não comprovou oversell).
    c.probe(
      id: 'C2',
      poco: 'CJ-C',
      payload: 'Future.wait CPI ∥ PATCH list_on_marketplace=false',
      http: {'ck': hits[0].brief, 'patch': hits[1].brief},
      bd: {'listed': prod?['list_on_marketplace'], 'ck_ok': hits[0].ok},
      verdict: ckOkListedFalse ? 'FAIL' : 'FAIL',
      lens: 'CJ6',
    );
  }

  // C3 checkout ∥ soft-delete (deleted_at) — compensar com qty=0 se coluna falhar
  final sd = await mkSkus(c, n: 1, tag: 'c3-softdel', qty: 2, price: 13);
  if (sd.length == 1) {
    final s = sd.first;
    final hits = await parallel([
      c.checkout(orderId: s.oid, productId: s.pid, amount: 1),
      c.rest(
        'PATCH',
        'products?id=eq.${s.pid}',
        jwt: c.sellerJwt,
        body: {'deleted_at': DateTime.now().toUtc().toIso8601String()},
      ),
    ]);
    var del = hits[1];
    if (del.status >= 400) {
      del = (await parallel([
        Future.value(hits[0]),
        c.rest(
          'PATCH',
          'products?id=eq.${s.pid}',
          jwt: c.sellerJwt,
          body: {'quantity': 0},
        ),
      ]))[1];
    }
    c.trackSession(hits[0]);
    final prod = await c.productRow(s.pid);
    c.note('C3.softdel', 'checkout ∥ deleted_at/qty0', {
      'ck': hits[0].brief,
      'del': del.brief,
      'qty': prod?['quantity'],
    }, lens: 'CJ6', well: 'CJ-C');
    if (hits[0].ok && numOf(prod?['quantity']) == 0) {
      c.block(
        'C3-SOFTDEL',
        'CJ5',
        'Session pode ter ganho a corrida antes do wipe (qty=0 pós-quote)',
        {'ck': hits[0].brief, 'qty': prod?['quantity']},
      );
      c.probe(
        id: 'C3',
        poco: 'CJ-C',
        payload: 'Future.wait CPI ∥ PATCH deleted_at (fallback qty=0)',
        http: {'ck': hits[0].brief, 'del': del.brief},
        bd: prod,
        verdict: 'FAIL',
        lens: 'CJ6',
      );
    } else if (!hits[0].ok) {
      c.block('C3-SOFTDEL-BLOCK', 'CJ5', 'soft-delete/qty0 ganhou', hits[0].brief);
      c.probe(
        id: 'C3',
        poco: 'CJ-C',
        payload: 'Future.wait CPI ∥ soft-delete',
        http: hits[0],
        bd: prod,
        verdict: 'FAIL',
        lens: 'CJ6',
      );
    } else {
      c.probe(
        id: 'C3',
        poco: 'CJ-C',
        payload: 'Future.wait CPI ∥ soft-delete',
        http: {'ck': hits[0].brief, 'del': del.brief},
        bd: prod,
        verdict: 'FAIL',
        lens: 'CJ6',
      );
    }
  }

  // C4 is_sold=true mid-checkout (race, não sequencial CDCI)
  final sold = await mkSkus(c, n: 1, tag: 'c4-sold', qty: 1, price: 13);
  if (sold.length == 1) {
    final s = sold.first;
    final hits = await parallel([
      c.checkout(orderId: s.oid, productId: s.pid, amount: 1),
      c.rest(
        'PATCH',
        'products?id=eq.${s.pid}',
        jwt: c.sellerJwt,
        body: {'is_sold': true},
      ),
    ]);
    c.trackSession(hits[0]);
    final prod = await c.productRow(s.pid);
    c.note('C4.sold-race', 'CPI ∥ is_sold=true', {
      'ck': hits[0].brief,
      'sold': prod?['is_sold'],
    }, lens: 'CJ6', well: 'CJ-C');
    final seq = await c.checkout(
      orderId: s.oid,
      productId: s.pid,
      amount: 1,
    );
    if (seq.ok && prod?['is_sold'] == true) {
      c.hold(
        id: 'P1-C4',
        lens: 'CJ5',
        severity: 'P1',
        title: 'Checkout abre Session com is_sold=true já persistido',
        actor: 'buyer JWT',
        pre: 'race + 2.º CPI após is_sold',
        repro: 'Future.wait CPI ∥ PATCH is_sold; 2.º CPI',
        expected: 'marked sold',
        obtained: seq.brief,
      );
      c.probe(
        id: 'C4',
        poco: 'CJ-C',
        payload: 'Future.wait CPI ∥ is_sold=true; 2.º CPI',
        http: {'race': hits[0].brief, 'second': seq.brief},
        bd: prod,
        verdict: 'HOLD',
        lens: 'CJ5',
      );
    } else {
      c.block('C4-SOLD', 'CJ5', 'is_sold bloqueia 2.º CPI', seq.brief);
      c.probe(
        id: 'C4',
        poco: 'CJ-C',
        payload: 'Future.wait CPI ∥ is_sold=true',
        http: {'race': hits[0].brief, 'second': seq.brief},
        bd: prod,
        verdict: 'FAIL',
        lens: 'CJ5',
      );
    }
  }

  // C5a bag qty 9999
  final qMine = await c.rpc('batata_live_bag_update_qty', {
    'p_request_id': '00000000-0000-4000-8000-000000000099',
    'p_qty': 9999,
  }, jwt: c.buyerJwt);
  final fat = await mkSkus(c, n: 1, tag: 'c5-qty', qty: 2, price: 8);
  HttpHit? fatCk;
  if (fat.isNotEmpty) {
    fatCk = await c.checkoutBag(
      lines: [
        {
          'order_id': fat.first.oid,
          'product_id': fat.first.pid,
          'qty': 9999,
          'quantity': 9999,
        },
      ],
      amount: 1,
      extra: {'quantity': 9999},
    );
    c.trackSession(fatCk);
  }
  c.note('C5.qty9999', 'bag qty 9999', {
    'rpc': qMine.brief,
    'ck': fatCk?.brief,
    'amt': fatCk?.amountTotal,
  }, lens: 'CJ5', well: 'CJ-C');
  final okHigh = qMine.ok &&
      (qMine.map?['ok'] == true || '${qMine.body}'.contains('"ok":true'));
  final fatUnder = fatCk != null &&
      fatCk.ok &&
      fatCk.amountTotal != null &&
      fatCk.amountTotal! > 50000;
  if (okHigh) {
    c.hold(
      id: 'P1-C5a',
      lens: 'CJ5',
      severity: 'P1',
      title: 'bag_update_qty aceitou 9999',
      actor: 'buyer JWT',
      pre: 'request fake',
      repro: 'rpc batata_live_bag_update_qty p_qty=9999',
      expected: 'qty_too_high',
      obtained: qMine.brief,
    );
    c.probe(
      id: 'C5a',
      poco: 'CJ-C',
      payload: 'bag qty 9999 rpc + bag_lines quantity=9999',
      http: {'rpc': qMine.brief, 'ck': fatCk?.brief},
      bd: fatCk?.amountTotal,
      verdict: 'HOLD',
      lens: 'CJ5',
    );
  } else {
    c.block('C5a-QTY', 'CJ5', 'qty 9999 rejeitada / não inflacionou', {
      'rpc': qMine.status,
      'ck': fatCk?.status,
      'fatUnder': fatUnder,
    });
    c.probe(
      id: 'C5a',
      poco: 'CJ-C',
      payload: 'bag qty 9999',
      http: {'rpc': qMine.brief, 'ck': fatCk?.brief},
      bd: fatCk?.amountTotal,
      verdict: 'FAIL',
      lens: 'CJ5',
    );
  }

  // C5b cross-seller bag
  final s1 = await mkSkus(c, n: 1, tag: 'c5-s1', qty: 2, price: 10);
  final p2 = await c.createProduct(
    seller: c.seller2Id,
    title: '$prefix-c5-s2',
    qty: 2,
    price: 10,
  );
  String? o2;
  if (p2 != null) {
    o2 = await c.insertOrder(
      productId: p2,
      seller: c.seller2Id,
      price: 10,
      jwt: c.buyerJwt,
    );
  }
  if (s1.isNotEmpty && o2 != null && p2 != null) {
    final hit = await c.checkoutBag(
      lines: [
        {'order_id': s1.first.oid, 'product_id': s1.first.pid},
        {'order_id': o2, 'product_id': p2},
      ],
      amount: 1,
    );
    c.note('C5.cross', 'bag 2 sellers', hit.brief, lens: 'CJ7', well: 'CJ-C');
    if (hit.ok) {
      c.hold(
        id: 'P1-C5b',
        lens: 'CJ7',
        severity: 'P1',
        title: 'bag_checkout aceita 2 sellers',
        actor: 'buyer JWT',
        pre: 'order S1 + S2',
        repro: 'POST bag_checkout 2 sellers',
        expected: 'must share one seller',
        obtained: hit.brief,
      );
      c.probe(
        id: 'C5b',
        poco: 'CJ-C',
        payload: 'cross-seller bag 2 lines',
        http: hit,
        bd: '-',
        verdict: 'HOLD',
        lens: 'CJ7',
      );
    } else {
      c.block('C5b-CROSS', 'CJ7', 'bag 2 sellers bloqueado', hit.brief);
      c.probe(
        id: 'C5b',
        poco: 'CJ-C',
        payload: 'cross-seller bag',
        http: hit,
        bd: '-',
        verdict: 'FAIL',
        lens: 'CJ7',
      );
    }
  }
}

/// CJ-D FSM / pós-pago + Stripe TEST pago
Future<void> cjDFsmPaid(Rtcj c, Map<String, num> wallets0) async {
  c.wellsTried.add('CJ-D');

  // D1 seller pago MB WAY sem prova
  final mbPid = await c.createProduct(title: '$prefix-d-mbway', price: 16, qty: 2);
  if (mbPid != null) {
    final mbOid = await c.insertOrder(
      productId: mbPid,
      price: 16,
      payment: 'Pagamento Direto ao Vendedor (MB WAY/Transf)',
      jwt: c.buyerJwt,
    );
    if (mbOid != null) {
      final sellerPago = await c.rest(
        'PATCH',
        'orders?id=eq.$mbOid',
        jwt: c.sellerJwt,
        body: {'status': 'pago'},
      );
      final st = '${(await c.orderRow(mbOid))?['status']}';
      c.note('D1.mbway', 'seller pago sem prova', {
        'patch': sellerPago.brief,
        'status': st,
      }, lens: 'CJ4', well: 'CJ-D');
      if (sellerPago.ok && st == 'pago') {
        c.hold(
          id: 'P0-D1',
          lens: 'CJ4',
          severity: 'P0',
          title: 'Seller marcou MB WAY pago sem prova',
          actor: 'seller JWT',
          pre: 'proof_url vazio',
          repro: 'PATCH status=pago',
          expected: 'order_mbway_pago_requires_proof',
          obtained: sellerPago.brief,
        );
        c.probe(
          id: 'D1',
          poco: 'CJ-D',
          payload: 'seller PATCH status=pago MB WAY sem proof_url',
          http: sellerPago,
          bd: st,
          verdict: 'HOLD',
          lens: 'CJ4',
        );
      } else {
        c.block('D1-MBWAY', 'CJ4', 'seller pago sem prova bloqueado',
            sellerPago.brief);
        c.probe(
          id: 'D1',
          poco: 'CJ-D',
          payload: 'seller PATCH pago MB WAY sem prova',
          http: sellerPago,
          bd: st,
          verdict: 'FAIL',
          lens: 'CJ4',
        );
      }
    }
  }

  // Stripe TEST pago + contabilidade (obrigatório)
  final paid = await c.payToPago(lens: 'CJ8', initialQty: 2);
  if (paid == null) {
    c.skip('PAID', 'CJ8', 'setup_paid_order falhou', 'null');
    c.probe(
      id: 'PAID',
      poco: 'CJ-D',
      payload: 'setup_paid_order Stripe TEST 4242',
      http: 'null',
      bd: '-',
      verdict: 'SKIP',
      lens: 'CJ8',
    );
  } else {
    final row = await c.orderRow(paid.oid);
    final prod = await c.productRow(paid.pid);
    final wallets1 = await c.wallets();
    c.note('PAID.acct', 'setup_paid_order caixa', {
      'oid': paid.oid,
      'pi': paid.pi,
      'status': row?['status'],
      'amount_paid_cents': row?['amount_paid_cents'],
      'stock_units_applied': row?['stock_units_applied'],
      'qty': prod?['quantity'],
      'wallets0': wallets0,
      'wallets1': wallets1,
    }, lens: 'CJ8', well: 'CJ-D');
    final okPago = '${row?['status']}' == 'pago' &&
        '${paid.pi ?? ''}'.startsWith('pi_') &&
        numOf(row?['amount_paid_cents']) != null;
    if (!okPago) {
      c.hold(
        id: 'P1-PAID',
        lens: 'CJ8',
        severity: 'P1',
        title: 'setup_paid_order não deixou status=pago + PI',
        actor: 'e2e fixture',
        pre: 'Stripe TEST',
        repro: 'sec-fase2-e2e-oversell setup_paid_order',
        expected: 'pago + pi_ + amount_paid_cents',
        obtained: row,
      );
      c.probe(
        id: 'PAID',
        poco: 'CJ-D',
        payload: 'Stripe TEST pago (setup_paid_order / 4242)',
        http: 'e2e setup_paid_order',
        bd: {
          'status': row?['status'],
          'pi': paid.pi,
          'amount_paid_cents': row?['amount_paid_cents'],
          'qty': prod?['quantity'],
        },
        verdict: 'HOLD',
        lens: 'CJ8',
      );
    } else {
      c.block('PAID-OK', 'CJ8', 'Stripe TEST pago + stock alinhado', {
        'pi': paid.pi,
        'cents': row?['amount_paid_cents'],
        'qty': prod?['quantity'],
      });
      c.probe(
        id: 'PAID',
        poco: 'CJ-D',
        payload: 'Stripe TEST pago 4242 + contabilidade order',
        http: 'e2e setup_paid_order 200',
        bd: {
          'status': row?['status'],
          'pi': paid.pi,
          'amount_paid_cents': row?['amount_paid_cents'],
          'stock_units_applied': row?['stock_units_applied'],
          'qty': prod?['quantity'],
          'wallets': wallets1,
        },
        verdict: 'FAIL',
        lens: 'CJ8',
      );
    }

    // D2 cancel/refund JWT buyer pós-pago
    final cancel = await c.rest(
      'PATCH',
      'orders?id=eq.${paid.oid}',
      jwt: c.buyerJwt,
      body: {'status': 'cancelado'},
    );
    final st = '${(await c.orderRow(paid.oid))?['status']}'.toLowerCase();
    final refBuyer = await c.refund(paid.oid, jwt: c.buyerJwt);
    c.note('D2.postpay', 'cancel+refund buyer pós-pago', {
      'cancel': cancel.brief,
      'status': st,
      'refund': refBuyer.brief,
    }, lens: 'CJ4', well: 'CJ-D');
    final cancelOk = st == 'cancelado' || st == 'cancelled';
    final refundOk = refBuyer.ok && refBuyer.map?['ok'] != false;
    if (cancelOk || refundOk) {
      c.hold(
        id: 'P0-D2',
        lens: 'CJ4',
        severity: 'P0',
        title: 'Buyer JWT cancel/refund pós-pago aceite',
        actor: 'buyer JWT',
        pre: 'order pago Stripe TEST',
        repro: 'PATCH cancelado; POST refund-order',
        expected: 'order_cancel_denied_post_pay / 403',
        obtained: {'cancel': cancel.brief, 'refund': refBuyer.brief, 'status': st},
      );
      c.probe(
        id: 'D2',
        poco: 'CJ-D',
        payload: 'cancel JWT + refund-order JWT buyer pós-pago',
        http: {'cancel': cancel.brief, 'refund': refBuyer.brief},
        bd: st,
        verdict: 'HOLD',
        lens: 'CJ4',
      );
    } else {
      c.block('D2-POSTPAY', 'CJ4', 'cancel/refund buyer pós-pago bloqueado', {
        'cancel': cancel.status,
        'refund': refBuyer.status,
        'status': st,
      });
      c.probe(
        id: 'D2',
        poco: 'CJ-D',
        payload: 'cancel/refund JWT buyer pós-pago',
        http: {'cancel': cancel.brief, 'refund': refBuyer.brief},
        bd: st,
        verdict: 'FAIL',
        lens: 'CJ4',
      );
    }
  }
}
