/// RED TEAM CEGO DB pass1 — marketplace pós-CVDA.
/// Matriz A1–A3 · B1–B4 · C1–C5 + encodes novos. Sem correções.
import 'dart:io';

import '_rtdb.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('DB pass1 staging=${c.url} prefix=$prefix');
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
  c.note('DB7.wallet.pre', 'baseline', wallets0, lens: 'DB7', well: 'DB-C');

  await dbAClaimSession(c);
  await dbBBagRace(c);
  await dbCOffPricePaid(c, wallets0);

  final wallets1 = await c.wallets();
  c.note('DB7.wallet.post', 'após probes', {
    'pre': wallets0,
    'post': wallets1,
  }, lens: 'DB7', well: 'DB-C');

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

Future<Map<String, Object?>> peekCheckout(Rtdb c, String sid) async {
  final settle = await c.settleGet(sid);
  final page = await c.req('GET', 'https://checkout.stripe.com/c/pay/$sid');
  final raw = page.body.toLowerCase();
  final expired = raw.contains('expired') ||
      raw.contains('expirou') ||
      raw.contains('no longer available') ||
      raw.contains('session is complete') ||
      page.status == 404;
  return {
    'sid': sid.length > 28 ? sid.substring(0, 28) : sid,
    'settle': settle.brief,
    'page_http': page.status,
    'expired_hint': expired,
    'pay_hint': !expired && (page.status == 200 || page.status == 403),
  };
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

/// DB-A Claim / Session
Future<void> dbAClaimSession(Rtdb c) async {
  c.wellsTried.add('DB-A');

  // A1 reclaim Session Stripe morta
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
    c.note('A1.dead', 'cs_ morta reclaim', {
      'first': first.brief,
      'plant': plant.brief,
      'jwtPlant': jwtPlant.brief,
      'actor2': actor2.brief,
      'retry': retry.brief,
      'stored': sid,
    }, lens: 'DB1', well: 'DB-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A1',
      poco: 'DB-A',
      lens: 'DB1',
      payload: 'plant cs_test_dead; buyer2 CPI; owner retry',
      http: {
        'jwtPlant': jwtPlant.brief,
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
      repro: 'plantClaim; CPI buyer2; CPI owner',
      expected: 'buyer2 403/400; owner reclaim + nova cs_',
      obtained: {
        'actor2': actor2.brief,
        'retry': retry.brief,
        'stored': sid,
        'jwtPlant': jwtPlant.status,
      },
      blockId: 'A1-DEAD-CS',
      blockTitle: 'cs_ morta reclaim OK / 2.º actor negado',
    );
  } else {
    c.skip('A1', 'DB1', 'não criou SKU', 'mkSkus empty');
    c.probe(
      id: 'A1',
      poco: 'DB-A',
      payload: 'cs_ morta reclaim',
      http: 'skip fixture',
      bd: '-',
      verdict: 'SKIP',
      lens: 'DB1',
    );
  }

  // A2 claiming timestamp futuro (+1 ano)
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
    }, lens: 'DB2', well: 'DB-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A2',
      poco: 'DB-A',
      lens: 'DB2',
      payload: 'claiming:<now+1y>:futuretoken12ab + CPI',
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
      expected: 'reclaim (futuro=órfão) + cs_ coerente no ledger',
      obtained: {'hit': hit.brief, 'stored': sid, 'rpcJwt': rpcJwt.status},
      blockId: 'A2-FUTURE',
      blockTitle: 'claiming futuro reclaim/create coerente',
    );
  }

  // A3 timeout mid-claim + retry (Future.wait) — matriz DB-A
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
    }, lens: 'DB6', well: 'DB-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A3',
      poco: 'DB-A',
      lens: 'DB6',
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
}

/// DB-B Bag overlap / race
Future<void> dbBBagRace(Rtdb c) async {
  c.wellsTried.add('DB-B');

  // B1 bag 4-line ∥ bag 2-line overlap — CVDA: ≤1 cs_ útil
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
    final peeks = <Map<String, Object?>>[];
    for (final sid in sids) {
      peeks.add(await peekCheckout(c, sid));
    }
    final secondBlocked = hits.any(contention);
    final useful = sids.length;
    final twoUseful = useful >= 2;
    c.note('B1.4x2', 'bag 4-line ∥ 2-line overlap', {
      'sids': sids.toList(),
      'payable': payable,
      'briefs': briefs,
      'stored': stored,
      'secondBlocked': secondBlocked,
      'peeks': peeks,
    }, lens: 'DB3', well: 'DB-B');
    // Se ≤1 cs_ → fecho CVDA (FAIL, não contar). Se 2 → residual P1.
    recordHoldOrFail(
      c: c,
      probeId: 'B1',
      poco: 'DB-B',
      lens: 'DB3',
      payload: 'Future.wait bag 4-line ∥ bag 2-line overlap CD',
      http: briefs,
      bd: {
        'sids': sids.toList(),
        'stored': stored,
        'payable': payable,
        'peeks': peeks,
      },
      isHold: twoUseful,
      holdId: 'P1-B1',
      severity: 'P1',
      title: 'Overlap 4∥2: 2 Sessions úteis (lock CVDA falhou)',
      actor: 'buyer JWT',
      pre: '4 SKUs; bag ABCD ∥ bag CD',
      repro: 'Future.wait bag 4-line ∥ bag 2-line',
      expected: '≤1 cs_ útil ou 2.º blocked/contention',
      obtained: {
        'sids': sids.toList(),
        'payable': payable,
        'stored': stored,
        'secondBlocked': secondBlocked,
        'peeks': peeks,
      },
      blockId: 'B1-4x2',
      blockTitle: 'overlap 4∥2 ≤1 cs_ útil / 2.º contention',
      countFinding: twoUseful,
    );
  } else {
    c.skip('B1', 'DB3', 'não criou 4 SKUs', 'mkSkus');
    c.probe(
      id: 'B1',
      poco: 'DB-B',
      payload: 'bag 4∥2',
      http: 'skip',
      bd: '-',
      verdict: 'SKIP',
      lens: 'DB3',
    );
  }

  // B2 bag 3∥1 race
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
    c.note('B2.3x1', 'bag 3-line ∥ 1-line overlap', {
      'sids': sids.toList(),
      'payable': payable,
      'briefs': briefs,
      'stored': stored,
    }, lens: 'DB3', well: 'DB-B');
    recordHoldOrFail(
      c: c,
      probeId: 'B2',
      poco: 'DB-B',
      lens: 'DB3',
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

  // B3 2 buyers última unidade
  final pid = await c.createProduct(title: '$prefix-b3-last', qty: 1, price: 11);
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
      c.note('B3.last', '2 buyers última unidade', {
        'ok': ok,
        'payable': payable,
        'briefs': briefs,
        'o2': o2,
      }, lens: 'DB6', well: 'DB-B');
      recordHoldOrFail(
        c: c,
        probeId: 'B3',
        poco: 'DB-B',
        lens: 'DB6',
        payload: 'Future.wait 2 buyers CPI última unidade',
        http: briefs,
        bd: {'ok': ok, 'payable': payable, 'o2created': o2},
        isHold: ok >= 2 || payable >= 2,
        holdId: 'P0-B3',
        severity: 'P0',
        title: '2 buyers Session na última unidade',
        actor: 'buyer + buyer2 JWT',
        pre: 'quantity=1; 2 orders',
        repro: 'Future.wait 2× CPI',
        expected: '1 Session + 1 stock block (insert ou CPI)',
        obtained: {'ok': ok, 'payable': payable, 'briefs': briefs},
        blockId: 'B3-LAST',
        blockTitle: 'última unidade ≤1 Session',
      );
    } else {
      // 2.º insert recusado no hold de stock — ainda FAIL (não chegou a 2 Sessions)
      c.note('B3.insert', '2.º order recusado', {
        'o1': o1,
        'o2': o2,
      }, lens: 'DB6', well: 'DB-B');
      recordHoldOrFail(
        c: c,
        probeId: 'B3',
        poco: 'DB-B',
        lens: 'DB6',
        payload: '2 buyers última unidade (insert 2.º)',
        http: {'o1': o1, 'o2': o2},
        bd: {'o1': o1, 'o2': o2},
        isHold: o1 != null && o2 != null,
        holdId: 'P0-B3',
        severity: 'P0',
        title: '2.º buyer inseriu hold na última unidade',
        actor: 'buyer + buyer2 JWT',
        pre: 'quantity=1',
        repro: '2× insertOrder',
        expected: '2.º insert 400 stock',
        obtained: {'o1': o1, 'o2': o2},
        blockId: 'B3-LAST',
        blockTitle: '2.º insert/CPI bloqueado no last-unit',
      );
    }
  }

  // B4 checkout ∥ unlist + cross-seller
  final ul = await mkSkus(c, n: 1, tag: 'b4-unlist', qty: 1, price: 13);
  HttpHit? ck;
  HttpHit? patch;
  Map<String, dynamic>? prod;
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
    ck = hits[0];
    patch = hits[1];
    prod = await c.productRow(u.pid);
  }
  final s2pid = await c.createProduct(
    title: '$prefix-b4-xseller',
    qty: 2,
    price: 14,
    seller: c.seller2Id,
  );
  final s1 = await mkSkus(c, n: 1, tag: 'b4-s1', qty: 2, price: 12);
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
  final dual = ck != null &&
      ck.ok &&
      prod?['list_on_marketplace'] == false &&
      numOf(prod?['quantity']) == 0 &&
      (ck.sessionId ?? '').startsWith('cs_');
  final crossOk = cross != null && cross.ok;
  c.note('B4.unlist-cross', 'checkout ∥ unlist + cross-seller', {
    'ck': ck?.brief,
    'patch': patch?.brief,
    'listed': prod?['list_on_marketplace'],
    'qty': prod?['quantity'],
    'cross': cross?.brief,
  }, lens: 'DB6', well: 'DB-B');
  recordHoldOrFail(
    c: c,
    probeId: 'B4',
    poco: 'DB-B',
    lens: 'DB6',
    payload: 'Future.wait CPI ∥ unlist+qty=0; bag cross-seller',
    http: {'ck': ck?.brief, 'patch': patch?.brief, 'cross': cross?.brief},
    bd: prod,
    isHold: dual || crossOk,
    holdId: 'P1-B4',
    severity: 'P1',
    title: crossOk
        ? 'bag cross-seller criou Session'
        : 'Session aberta sobre SKU unlisted qty=0',
    actor: 'buyer JWT ∥ seller JWT',
    pre: 'qty=1 listed + SKU seller2',
    repro: 'Future.wait CPI ∥ PATCH unlist; bag 2 sellers',
    expected: 'CPI 400 not listed OU unlist perde; cross 400 one seller',
    obtained: {
      'ck': ck?.brief,
      'listed': prod?['list_on_marketplace'],
      'qty': prod?['quantity'],
      'cross': cross?.brief,
    },
    blockId: 'B4-UNLIST-CROSS',
    blockTitle: 'unlist∥checkout sem Session+qty0; cross 400',
  );

  // Residual novo: bag 4-line ∥ CPI single (não bag_checkout) na linha C
  final b5 = await mkSkus(c, n: 4, tag: 'b5-bag-single', qty: 2, price: 8);
  if (b5.length == 4) {
    final four = bagLines(b5);
    final hits = await parallel([
      c.checkoutBag(lines: four, amount: 1),
      c.checkout(orderId: b5[2].oid, productId: b5[2].pid, amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    final sids = openCs(hits);
    final payable = await openPayableCount(c, sids);
    final briefs = hits.map((h) => h.brief).toList();
    c.note('B5.bag-single', 'bag 4 ∥ CPI single linha C', {
      'sids': sids.toList(),
      'payable': payable,
      'briefs': briefs,
    }, lens: 'DB3', well: 'DB-B');
    recordHoldOrFail(
      c: c,
      probeId: 'B5',
      poco: 'DB-B',
      lens: 'DB3',
      payload: 'Future.wait bag 4-line ∥ CPI single (não bag) linha C',
      http: briefs,
      bd: {'sids': sids.toList(), 'payable': payable},
      isHold: sids.length >= 2,
      holdId: 'P1-B5',
      severity: 'P1',
      title: 'bag∥CPI-single: 2 Sessions no mesmo artigo',
      actor: 'buyer JWT',
      pre: '4 SKUs; bag ABCD ∥ CPI C',
      repro: 'Future.wait checkoutBag ∥ checkout single',
      expected: '≤1 cs_ útil (mesmo buyer lock cobre single)',
      obtained: {'sids': sids.toList(), 'payable': payable, 'briefs': briefs},
      blockId: 'B5-BAG-SINGLE',
      blockTitle: 'bag∥single ≤1 cs_',
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

/// DB-C Off-platform + preço
Future<void> dbCOffPricePaid(Rtdb c, Map<String, num> wallets0) async {
  c.wellsTried.add('DB-C');

  // C1 controlo: mb way exact → 400
  final c1 = await probeEncode(c, tag: 'c1-mbway', payment: 'mb way');
  c.note('C1.control', 'mb way exact', c1, lens: 'DB4', well: 'DB-C');
  recordHoldOrFail(
    c: c,
    probeId: 'C1',
    poco: 'DB-C',
    lens: 'DB4',
    payload: 'mb way exact → esperado 400 off-platform',
    http: c1['cpi'],
    bd: c1,
    isHold: c1['opened'] == true || c1['denied'] != true,
    holdId: 'P1-C1',
    severity: 'P1',
    title: 'controlo mb way exact abriu Stripe (regressão CVDA)',
    actor: 'buyer JWT',
    pre: 'payment_method=mb way',
    repro: 'CPI',
    expected: '400 off-platform; sem cs_',
    obtained: c1,
    blockId: 'C1-MBWAY',
    blockTitle: 'mb way exact 400 off-platform',
  );

  // C2 controlo fold CVDA (1–2 linhas; HOLD não contar): μ / small-caps
  final c2encodes = <String, String>{
    'C2-MU': '\u03bcbway',
    'C2-SC': '\u1D0D\u0299\u1D21\u1D00\u028F',
  };
  for (final e in c2encodes.entries) {
    final r = await probeEncode(
      c,
      tag: 'c2-${e.key.toLowerCase()}',
      payment: e.value,
    );
    c.note(e.key, 'controlo fold ${e.key}', r, lens: 'DB4', well: 'DB-C');
    recordHoldOrFail(
      c: c,
      probeId: e.key,
      poco: 'DB-C',
      lens: 'DB4',
      payload:
          'controlo fold ${e.key} codes=${e.value.runes.map((x) => x.toRadixString(16)).toList()}',
      http: r['cpi'],
      bd: r,
      isHold: r['opened'] == true,
      holdId: 'P1-${e.key}',
      severity: 'P1',
      title: 'controlo ${e.key} abriu Stripe (residual CV — não contar)',
      actor: 'buyer JWT',
      pre: e.value.runes.map((x) => x.toRadixString(16)).join(' '),
      repro: 'CPI',
      expected: '400 off-platform (fold CVDA)',
      obtained: r,
      blockId: '${e.key}-BLOCK',
      blockTitle: '${e.key} 400 off-platform',
      countFinding: false,
    );
  }

  // C3 novos confusables — NÃO exactos CV (μ/ԝ/small-caps/NFD/tags)
  final newEncodes = <String, String>{
    'C3-OMEGA': 'mb\u03C9ay', // Greek omega as w
    'C3-COPT': '\u2C99bway', // Coptic m
    'C3-HOOK': 'm\u0253way', // b with hook
    'C3-ROMAN': '\u217Fbway', // small roman m
    'C3-MATH':
        String.fromCharCodes(const [0x1D5DC, 0x1D5D5, 0x1D5E0, 0x1D5D4, 0x1D5E2]),
    'C3-LATN': 'mbw\u0251y', // latin alpha as a
    'C3-CIRC': '\u24DC\u24D1\u24E6\u24D0\u24E8',
    'C3-MVS': 'mb\u180Eway', // Mongolian vowel separator
    'C3-BETA': 'm\u03B2way', // Greek beta as b
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
    c.note(e.key, 'encode novo ${e.key}', r, lens: 'DB4', well: 'DB-C');
    final opened = r['opened'] == true;
    if (opened) openedTags.add(e.key);
    c.probe(
      id: e.key,
      poco: 'DB-C',
      payload:
          'novo confusable ${e.key} codes=${e.value.runes.map((x) => x.toRadixString(16)).toList()}',
      http: r['cpi'],
      bd: r,
      verdict: opened ? 'HOLD' : 'FAIL',
      lens: 'DB4',
    );
  }
  if (openedTags.isNotEmpty) {
    c.hold(
      id: 'P1-C3',
      lens: 'DB4',
      severity: 'P1',
      title: 'off-platform confusable novo abriu Stripe: ${openedTags.join(",")}',
      actor: 'buyer JWT',
      pre: 'payment_method encodes novos (omega/coptic/hook/roman/math/…)',
      repro: 'CPI por encode',
      expected: '400 off-platform em todos',
      obtained: {
        'opened': openedTags,
        for (final t in openedTags) t: encodeHits[t],
      },
    );
  } else {
    c.block('C3-ENCODES', 'DB4', 'confusables novos negados', {
      'n': newEncodes.length,
      'tags': newEncodes.keys.toList(),
    });
  }

  // C4 underpay body / portes hostis
  final c4ctt = await mkSkus(
    c,
    n: 1,
    tag: 'c4-ctt',
    qty: 2,
    price: 18,
    shipping: 'ctt',
  );
  HttpHit? cttHit;
  if (c4ctt.isNotEmpty) {
    cttHit = await c.checkout(
      orderId: c4ctt.first.oid,
      productId: c4ctt.first.pid,
      amount: 0,
      extra: {
        'total_eur': '0.00',
        'item_price': 0.01,
        'protection_fee': 0,
        'shipping': 0,
        'server_amount_cents': 1,
        'amount_total': 1,
      },
      shipping: 'mao',
    );
    c.trackSession(cttHit);
  }
  final homo = await mkSkus(
    c,
    n: 1,
    tag: 'c4-homo',
    qty: 2,
    price: 18,
    shipping: 'entregа em mão',
  );
  HttpHit? homoHit;
  if (homo.isNotEmpty) {
    homoHit = await c.checkout(
      orderId: homo.first.oid,
      productId: homo.first.pid,
      amount: 1,
    );
    c.trackSession(homoHit);
  }
  final miss = await mkSkus(
    c,
    n: 1,
    tag: 'c4-ship35',
    qty: 2,
    price: 18,
    shipping: 'envio transportadora (€3.5)',
  );
  HttpHit? missHit;
  if (miss.isNotEmpty) {
    missHit = await c.checkout(
      orderId: miss.first.oid,
      productId: miss.first.pid,
      amount: 1,
      shipping: 'carrier',
    );
    c.trackSession(missHit);
  }
  final cttAmt = cttHit?.amountTotal;
  final cttUnder = cttHit != null && cttHit.ok && cttAmt != null && cttAmt < 1800;
  final homoZero =
      homoHit != null && homoHit.ok && (homoHit.amountTotal ?? 9999) < 1900;
  final missZero =
      missHit != null && missHit.ok && (missHit.amountTotal ?? 9999) < 1800;
  c.note('C4.underpay', 'body/portes hostis', {
    'ctt': cttHit?.brief,
    'cttAmt': cttAmt,
    'homo': homoHit?.brief,
    'miss': missHit?.brief,
  }, lens: 'DB5', well: 'DB-C');
  recordHoldOrFail(
    c: c,
    probeId: 'C4',
    poco: 'DB-C',
    lens: 'DB5',
    payload: 'body total_eur=0 item_price=0.01; homoglyph portes; €3.5',
    http: {
      'ctt': cttHit?.brief,
      'homo': homoHit?.brief,
      'miss': missHit?.brief,
    },
    bd: {
      'cttAmt': cttAmt,
      'homoAmt': homoHit?.amountTotal,
      'missAmt': missHit?.amountTotal,
    },
    isHold: cttUnder || homoZero || missZero,
    holdId: 'P0-C4',
    severity: 'P0',
    title: 'body/selo hostil baixou amount_total',
    actor: 'buyer JWT',
    pre: 'SKU 18€ selo ctt / homoglyph / €3.5',
    repro: 'CPI extras total_eur/item_price; CPI selos',
    expected: 'amount ≈ 18€+CTT+protecção; portes inválidos 400',
    obtained: {
      'cttAmt': cttAmt,
      'homo': homoHit?.brief,
      'miss': missHit?.brief,
    },
    blockId: 'C4-UNDERPAY',
    blockTitle: 'total_eur ignorado; CTT selado; homoglyph/€3.5 400',
  );

  // C5 Stripe TEST pago 4242 + caixa
  final paid = await c.payToPago(lens: 'DB7', initialQty: 2);
  if (paid == null) {
    c.skip('C5', 'DB7', 'setup_paid_order falhou', 'null');
    c.probe(
      id: 'C5',
      poco: 'DB-C',
      payload: 'setup_paid_order Stripe TEST 4242',
      http: 'null',
      bd: '-',
      verdict: 'SKIP',
      lens: 'DB7',
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
    }, lens: 'DB7', well: 'DB-C');
    recordHoldOrFail(
      c: c,
      probeId: 'C5',
      poco: 'DB-C',
      lens: 'DB7',
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

  // Anti-atrofia exactos (não contar)
  final ctrl = <String, String>{
    'CTRL-NFD': 'mbwa\u0301y',
    'CTRL-ZWSP': 'mbway\u200b',
    'CTRL-PAYSAFE': 'PaysafeCash',
  };
  for (final e in ctrl.entries) {
    final r = await probeEncode(
      c,
      tag: 'ctrl-${e.key.toLowerCase()}',
      payment: e.value,
    );
    final rateLimited = '${r['cpi']}'.contains('429');
    c.note(e.key, 'anti-atrofia ${e.key}', r, lens: 'DB4', well: 'DB-C');
    if (rateLimited) {
      c.skip(e.key, 'DB4', '429 rate-limit', r['cpi']);
      c.probe(
        id: e.key,
        poco: 'DB-C',
        payload: e.key,
        http: r['cpi'],
        bd: r,
        verdict: 'SKIP',
        lens: 'DB4',
      );
      continue;
    }
    recordHoldOrFail(
      c: c,
      probeId: e.key,
      poco: 'DB-C',
      lens: 'DB4',
      payload:
          'anti-atrofia ${e.key} codes=${e.value.runes.map((x) => x.toRadixString(16)).toList()}',
      http: r['cpi'],
      bd: r,
      isHold: r['opened'] == true,
      holdId: 'P1-${e.key}',
      severity: 'P1',
      title: 'anti-atrofia ${e.key} abriu Stripe',
      actor: 'buyer JWT',
      pre: e.value.runes.map((x) => x.toRadixString(16)).join(' '),
      repro: 'CPI',
      expected: e.key.contains('PAYSAFE')
          ? 'comportamento residual conhecido'
          : '400 off-platform (fold CVDA)',
      obtained: r,
      blockId: '${e.key}-BLOCK',
      blockTitle: '${e.key} sem Stripe (ou rails residual)',
      countFinding: false,
    );
  }
}
