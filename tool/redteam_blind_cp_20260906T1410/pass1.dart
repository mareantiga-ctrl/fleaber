/// RED TEAM CEGO CP pass1 — marketplace pós-allowlist.
/// Matriz A1–A5 · B1–B4 · C1–C3 + allowlist extra. Sem correções.
import 'dart:io';

import '_rtcp.dart';

Future<void> main() async {
  final c = Rtcp.fromEnv(loadEnv());
  stdout.writeln('CP pass1 staging=${c.url} prefix=$prefix');
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
  c.note('CP7.wallet.pre', 'baseline', wallets0, lens: 'CP7', well: 'CP-C');

  await cpAClaimSession(c);
  await cpBBagRace(c);
  await cpCPricePaid(c, wallets0);

  final wallets1 = await c.wallets();
  c.note('CP7.wallet.post', 'após probes', {
    'pre': wallets0,
    'post': wallets1,
  }, lens: 'CP7', well: 'CP-C');

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
  Rtcp c, {
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

Future<int> openPayableCount(Rtcp c, Iterable<String> sids) async {
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
  required Rtcp c,
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
}) {
  if (isHold) {
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

/// CP-A Claim / Session / cs_
Future<void> cpAClaimSession(Rtcp c) async {
  c.wellsTried.add('CP-A');

  // A1 reclaim Session Stripe morta — 2.º actor + retry dono
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
    }, lens: 'CP1', well: 'CP-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A1',
      poco: 'CP-A',
      lens: 'CP1',
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
      expected: 'buyer2 403; owner reclaim + nova cs_',
      obtained: {
        'actor2': actor2.brief,
        'retry': retry.brief,
        'stored': sid,
        'jwtPlant': jwtPlant.status,
      },
      blockId: 'A1-DEAD-CS',
      blockTitle: deadStuck
          ? 'cs_ morta stuck'
          : 'cs_ morta reclaim OK / 2.º actor negado',
    );
  } else {
    c.skip('A1', 'CP1', 'não criou SKU', 'mkSkus empty');
    c.probe(
      id: 'A1',
      poco: 'CP-A',
      payload: 'cs_ morta reclaim',
      http: 'skip fixture',
      bd: '-',
      verdict: 'SKIP',
      lens: 'CP1',
    );
  }

  // A2 claiming timestamp futuro (+1 ano)
  final a2 = await mkSkus(c, n: 1, tag: 'a2-future', qty: 2);
  if (a2.length == 1) {
    final futureMs = DateTime.now().millisecondsSinceEpoch + 365 * 24 * 3600 * 1000;
    final tok = 'claiming:$futureMs:futuretoken12ab';
    await c.plantClaim(a2.first.oid, tok);
    final rpcJwt = await c.rpc(
      'batata_bag_checkout_claim',
      {
        'p_order_ids': [a2.first.oid],
        'p_claim_token': 'claiming:${DateTime.now().millisecondsSinceEpoch}:jwttry12abcd',
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
    c.note('A2.future', 'claiming futuro', {
      'tok': tok,
      'rpcJwt': rpcJwt.brief,
      'hit': hit.brief,
      'stored': sid,
    }, lens: 'CP2', well: 'CP-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A2',
      poco: 'CP-A',
      lens: 'CP2',
      payload: 'claiming:<now+1y>:futuretoken12ab + CPI',
      http: {'rpcJwt': rpcJwt.brief, 'cpi': hit.brief},
      bd: sid,
      isHold: stuck,
      holdId: 'P2-A2',
      severity: 'P2',
      title: 'claiming futuro prende o cadeado',
      actor: 'buyer JWT (plant service_role observação)',
      pre: tok,
      repro: 'CPI após claiming futuro',
      expected: 'reclaim (futuro=órfão) + cs_',
      obtained: {'hit': hit.brief, 'stored': sid, 'rpcJwt': rpcJwt.status},
      blockId: 'A2-FUTURE',
      blockTitle: 'claiming futuro reclaim/contention sem DoS permanente',
    );
  }

  // A3 claiming malformado / sem ms / ms passado extremo
  final a3 = await mkSkus(c, n: 3, tag: 'a3-malform', qty: 2);
  if (a3.length == 3) {
    final toks = [
      'claiming:malformedtoken12',
      'claiming:',
      'claiming:1000:extremepast12ab',
    ];
    final briefs = <String>[];
    final stored = <String>[];
    var anyStuck = false;
    var anyCs = 0;
    for (var i = 0; i < 3; i++) {
      await c.plantClaim(a3[i].oid, toks[i]);
      final hit = await c.checkout(
        orderId: a3[i].oid,
        productId: a3[i].pid,
        amount: 1,
      );
      c.trackSession(hit);
      briefs.add(hit.brief);
      final row = await c.orderRow(a3[i].oid);
      final sid = '${row?['stripe_checkout_session_id'] ?? ''}';
      stored.add(sid);
      if (sid.startsWith('claiming:') && !hit.ok) anyStuck = true;
      if (hit.ok && sid.startsWith('cs_')) anyCs++;
    }
    c.note('A3.malform', 'claiming malform/sem ms/passado extremo', {
      'toks': toks,
      'briefs': briefs,
      'stored': stored,
    }, lens: 'CP2', well: 'CP-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A3',
      poco: 'CP-A',
      lens: 'CP2',
      payload: 'claiming:malformed | claiming: | claiming:1000:extremepast',
      http: briefs,
      bd: stored,
      isHold: anyStuck,
      holdId: 'P2-A3',
      severity: 'P2',
      title: 'claiming malformado/passado extremo prende slot',
      actor: 'buyer JWT',
      pre: toks.join(' | '),
      repro: 'plant + CPI ×3',
      expected: 'legado/órfão reclaim + cs_',
      obtained: {'briefs': briefs, 'stored': stored, 'anyCs': anyCs},
      blockId: 'A3-MALFORM',
      blockTitle: 'malform/sem ms/passado extremo reclaim',
    );
  }

  // A4 Session expire mid-checkout → 2.ª Session mesma order
  final a4skus = await mkSkus(c, n: 2, tag: 'a4-expire', qty: 2, price: 10);
  if (a4skus.length == 2) {
    final first = await c.checkout(
      orderId: a4skus[0].oid,
      productId: a4skus[0].pid,
      amount: 1,
    );
    c.trackSession(first);
    final sid0 = first.sessionId ?? '';
    HttpHit expireHit;
    var path = 'stripe.expire';
    if (sid0.startsWith('cs_') && c.stripeTestKey != null) {
      expireHit = await c.stripeExpire(sid0);
    } else {
      // sem sk_test_: overlap bag força expire da Session single (amount ≠)
      path = 'bag overlap expire da Session single';
      expireHit = await c.checkoutBag(
        lines: bagLines(a4skus),
        amount: 1,
      );
      c.trackSession(expireHit);
    }
    final second = await c.checkout(
      orderId: a4skus[0].oid,
      productId: a4skus[0].pid,
      amount: 1,
    );
    c.trackSession(second);
    final row = await c.orderRow(a4skus[0].oid);
    final sid1 = '${row?['stripe_checkout_session_id'] ?? ''}';
    final sids = {
      if (sid0.startsWith('cs_')) sid0,
      if ((expireHit.sessionId ?? '').startsWith('cs_')) expireHit.sessionId!,
      if (sid1.startsWith('cs_')) sid1,
      if ((second.sessionId ?? '').startsWith('cs_')) second.sessionId!,
    };
    final payable = await openPayableCount(c, sids);
    c.note('A4.expire', 'expire mid → 2.ª Session', {
      'path': path,
      'first': first.brief,
      'expire': expireHit.brief,
      'second': second.brief,
      'stored': sid1,
      'payable': payable,
      'sids': sids.toList(),
    }, lens: 'CP1', well: 'CP-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A4',
      poco: 'CP-A',
      lens: 'CP1',
      payload: '$path; 2.º CPI mesma order',
      http: {
        'first': first.brief,
        'expire': expireHit.brief,
        'second': second.brief,
      },
      bd: {'stored': sid1, 'payable': payable, 'sids': sids.toList()},
      isHold: payable >= 2,
      holdId: 'P0-A4',
      severity: 'P0',
      title: 'Após expire, 2 Sessions pagáveis na mesma order',
      actor: 'buyer JWT',
      pre: 'cs_ open',
      repro: path,
      expected: '≤1 open payable',
      obtained: {'sids': sids.toList(), 'payable': payable},
      blockId: 'A4-EXPIRE',
      blockTitle: 'expire/overlap não deixou 2 pagáveis',
    );
  }

  // A5 crash/timeout mid-claim + retry idempotente
  final a5 = await mkSkus(c, n: 2, tag: 'a5-crash', qty: 2);
  if (a5.length == 2) {
    final lines = bagLines(a5);
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
      '${(await c.orderRow(a5[0].oid))?['stripe_checkout_session_id'] ?? ''}',
      '${(await c.orderRow(a5[1].oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final sids = {
      ...openCs(pair),
      ...stored.where((s) => s.startsWith('cs_')),
    };
    final payable = await openPayableCount(c, sids);
    final briefs = pair.map((h) => h.brief).toList();
    c.note('A5.timeout', 'timeout 250ms ∥ retry', {
      'briefs': briefs,
      'stored': stored,
      'payable': payable,
    }, lens: 'CP6', well: 'CP-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A5',
      poco: 'CP-A',
      lens: 'CP6',
      payload: 'Future.wait bag timeout 250ms ∥ retry',
      http: briefs,
      bd: {'stored': stored, 'payable': payable},
      isHold: payable >= 2,
      holdId: 'P0-A5',
      severity: 'P0',
      title: 'Timeout mid-claim + retry = 2 cs_ pagáveis',
      actor: 'buyer JWT',
      pre: '2-line bag',
      repro: 'Future.wait checkoutBag timeout 250ms ∥ retry',
      expected: '≤1 cs_ (idempotente)',
      obtained: {'sids': sids.toList(), 'stored': stored, 'payable': payable},
      blockId: 'A5-TIMEOUT',
      blockTitle: 'timeout∥retry ≤1 Session',
    );
  }
}

/// CP-B Bag overlap / race
Future<void> cpBBagRace(Rtcp c) async {
  c.wellsTried.add('CP-B');

  // B1 bag 4-line ∥ bag 2-line overlap parcial (obrigatório)
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
    c.note('B1.4x2', 'bag 4-line ∥ 2-line overlap', {
      'sids': sids.toList(),
      'payable': payable,
      'briefs': briefs,
      'stored': stored,
    }, lens: 'CP3', well: 'CP-B');
    recordHoldOrFail(
      c: c,
      probeId: 'B1',
      poco: 'CP-B',
      lens: 'CP3',
      payload: 'Future.wait bag 4-line ∥ bag 2-line overlap CD',
      http: briefs,
      bd: {'sids': sids.toList(), 'stored': stored, 'payable': payable},
      isHold: payable >= 2,
      holdId: 'P1-B1',
      severity: 'P1',
      title: 'Overlap 4∥2: 2 Sessions pagáveis',
      actor: 'buyer JWT',
      pre: '4 SKUs; bag ABCD ∥ bag CD',
      repro: 'Future.wait bag 4-line ∥ bag 2-line',
      expected: '≤1 cs_ open (intersect)',
      obtained: {'sids': sids.toList(), 'payable': payable, 'stored': stored},
      blockId: 'B1-4x2',
      blockTitle: 'overlap 4∥2 ≤1 pagável',
    );
  } else {
    c.skip('B1', 'CP3', 'não criou 4 SKUs', 'mkSkus');
    c.probe(
      id: 'B1',
      poco: 'CP-B',
      payload: 'bag 4∥2',
      http: 'skip',
      bd: '-',
      verdict: 'SKIP',
      lens: 'CP3',
    );
  }

  // B2 2 buyers última unidade Future.wait
  final pid = await c.createProduct(title: '$prefix-b2-last', qty: 1, price: 11);
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
      c.note('B2.last', '2 buyers última unidade', {
        'ok': ok,
        'payable': payable,
        'briefs': briefs,
      }, lens: 'CP4', well: 'CP-B');
      recordHoldOrFail(
        c: c,
        probeId: 'B2',
        poco: 'CP-B',
        lens: 'CP4',
        payload: 'Future.wait 2 buyers CPI última unidade',
        http: briefs,
        bd: {'ok': ok, 'payable': payable},
        isHold: ok >= 2 || payable >= 2,
        holdId: 'P0-B2',
        severity: 'P0',
        title: '2 buyers Session na última unidade',
        actor: 'buyer + buyer2 JWT',
        pre: 'quantity=1; 2 orders',
        repro: 'Future.wait 2× CPI',
        expected: '1 Session + 1 stock block',
        obtained: {'ok': ok, 'payable': payable, 'briefs': briefs},
        blockId: 'B2-LAST',
        blockTitle: 'última unidade ≤1 Session',
      );
    }
  }

  // B3 checkout ∥ unlist / soft-delete
  final ul = await mkSkus(c, n: 1, tag: 'b3-unlist', qty: 1, price: 13);
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
    final prod = await c.productRow(u.pid);
    final ck = hits[0];
    final dual = ck.ok &&
        prod?['list_on_marketplace'] == false &&
        numOf(prod?['quantity']) == 0;
    c.note('B3.unlist', 'checkout ∥ unlist+qty0', {
      'ck': ck.brief,
      'patch': hits[1].brief,
      'listed': prod?['list_on_marketplace'],
      'qty': prod?['quantity'],
    }, lens: 'CP4', well: 'CP-B');
    // Dual Session oversell só se CPI 200 E stock já 0/unlisted — P1 se Session
    // pagável sobre SKU unlisted qty=0 (settle pode ainda debitar).
    recordHoldOrFail(
      c: c,
      probeId: 'B3',
      poco: 'CP-B',
      lens: 'CP4',
      payload: 'Future.wait CPI ∥ unlist+qty=0',
      http: {'ck': ck.brief, 'patch': hits[1].brief},
      bd: prod,
      isHold: dual && (ck.sessionId ?? '').startsWith('cs_'),
      holdId: 'P1-B3',
      severity: 'P1',
      title: 'Session aberta sobre SKU unlisted qty=0',
      actor: 'buyer JWT ∥ seller JWT',
      pre: 'qty=1 listed',
      repro: 'Future.wait CPI ∥ PATCH unlist+qty0',
      expected: 'CPI 400 not listed / stock 0 OU unlist perde a corrida',
      obtained: {
        'ck': ck.brief,
        'listed': prod?['list_on_marketplace'],
        'qty': prod?['quantity'],
      },
      blockId: 'B3-UNLIST',
      blockTitle: 'unlist∥checkout sem Session+qty0 simultâneos, ou CPI bloqueou',
    );
  }

  // B4 bag qty hostil / cross-seller bag
  final qMine = await c.rpc('batata_live_bag_update_qty', {
    'p_request_id': '00000000-0000-4000-8000-000000000099',
    'p_qty': 9999,
  }, jwt: c.buyerJwt);
  final fat = await mkSkus(c, n: 1, tag: 'b4-qty', qty: 2, price: 8);
  HttpHit? fatCk;
  if (fat.isNotEmpty) {
    fatCk = await c.checkoutBag(
      lines: [
        {
          'order_id': fat.first.oid,
          'product_id': fat.first.pid,
          'qty': 9999,
          'quantity': 9999,
          'line_total_cents': 1,
        },
      ],
      amount: 1,
      extra: {'quantity': 9999},
    );
    c.trackSession(fatCk);
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
  final qtyRpcOk = qMine.ok &&
      (qMine.map?['ok'] == true || '${qMine.body}'.contains('"ok":true'));
  final fatInflated = fatCk != null &&
      fatCk.ok &&
      fatCk.amountTotal != null &&
      fatCk.amountTotal! > 50000;
  final crossOk = cross != null && cross.ok;
  c.note('B4.qty-cross', 'qty 9999 + cross-seller', {
    'rpc': qMine.brief,
    'fat': fatCk?.brief,
    'fatAmt': fatCk?.amountTotal,
    'cross': cross?.brief,
  }, lens: 'CP3', well: 'CP-B');
  recordHoldOrFail(
    c: c,
    probeId: 'B4',
    poco: 'CP-B',
    lens: 'CP3',
    payload: 'bag qty 9999 + cross-seller bag 2 sellers',
    http: {
      'rpc': qMine.brief,
      'fat': fatCk?.brief,
      'cross': cross?.brief,
    },
    bd: {'fatAmt': fatCk?.amountTotal, 'crossOk': crossOk},
    isHold: qtyRpcOk || fatInflated || crossOk,
    holdId: crossOk ? 'P1-B4' : 'P1-B4',
    severity: 'P1',
    title: crossOk
        ? 'bag cross-seller criou Session'
        : (qtyRpcOk
            ? 'bag_update_qty aceitou 9999'
            : 'qty 9999 inflacionou amount_total'),
    actor: 'buyer JWT',
    pre: 'SKU seller1 + SKU seller2; bag_lines quantity=9999',
    repro: 'rpc qty 9999; bag CPI; bag 2 sellers',
    expected: 'qty rejeitada; 400 must share one seller',
    obtained: {
      'rpc': qMine.brief,
      'fatAmt': fatCk?.amountTotal,
      'cross': cross?.brief,
    },
    blockId: 'B4-QTY-CROSS',
    blockTitle: 'qty 9999 não inflacionou; cross-seller 400',
  );
}

/// CP-C Preço / pago + allowlist
Future<void> cpCPricePaid(Rtcp c, Map<String, num> wallets0) async {
  c.wellsTried.add('CP-C');

  // C1 underpay / body total_eur hostil (NÃO exacto CDCI bundle 0.01+discount 99)
  // Vectores: item_price/protection/shipping/amount=0 + total_eur string + CTT selo vs body mão
  final c1ctt = await mkSkus(
    c,
    n: 1,
    tag: 'c1-ctt',
    qty: 2,
    price: 18,
    shipping: 'ctt',
  );
  HttpHit? cttHit;
  if (c1ctt.isNotEmpty) {
    cttHit = await c.checkout(
      orderId: c1ctt.first.oid,
      productId: c1ctt.first.pid,
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
  final homoglyph = await mkSkus(
    c,
    n: 1,
    tag: 'c1-homo',
    qty: 2,
    price: 18,
    shipping: 'entregа em mão', // Cyrillic а
  );
  HttpHit? homoHit;
  if (homoglyph.isNotEmpty) {
    homoHit = await c.checkout(
      orderId: homoglyph.first.oid,
      productId: homoglyph.first.pid,
      amount: 1,
    );
    c.trackSession(homoHit);
  }
  final missAllow = await mkSkus(
    c,
    n: 1,
    tag: 'c1-ship3.5',
    qty: 2,
    price: 18,
    shipping: 'envio transportadora (€3.5)',
  );
  HttpHit? missHit;
  if (missAllow.isNotEmpty) {
    missHit = await c.checkout(
      orderId: missAllow.first.oid,
      productId: missAllow.first.pid,
      amount: 1,
      shipping: 'carrier',
    );
    c.trackSession(missHit);
  }
  // off-platform allowlist false-negative: ZWSP / lookalike
  final zwspPay = await mkSkus(
    c,
    n: 1,
    tag: 'c1-zwsp-pay',
    qty: 2,
    price: 18,
    payment: 'mbway\u200b',
  );
  HttpHit? zwspHit;
  if (zwspPay.isNotEmpty) {
    zwspHit = await c.checkout(
      orderId: zwspPay.first.oid,
      productId: zwspPay.first.pid,
      amount: 1,
    );
    c.trackSession(zwspHit);
  }
  final legitMb = await mkSkus(
    c,
    n: 1,
    tag: 'c1-mbway-ok',
    qty: 2,
    price: 18,
    payment: 'mb way',
  );
  HttpHit? mbHit;
  if (legitMb.isNotEmpty) {
    mbHit = await c.checkout(
      orderId: legitMb.first.oid,
      productId: legitMb.first.pid,
      amount: 1,
    );
  }

  final cttAmt = cttHit?.amountTotal;
  final cttUnder = cttHit != null &&
      cttHit.ok &&
      cttAmt != null &&
      cttAmt < 1800;
  final homoZero = homoHit != null &&
      homoHit.ok &&
      (homoHit.amountTotal ?? 9999) < 1900;
  final missZero = missHit != null &&
      missHit.ok &&
      (missHit.amountTotal ?? 9999) < 1800;
  final zwspStripe = zwspHit != null &&
      zwspHit.ok &&
      (zwspHit.sessionId ?? '').startsWith('cs_');
  final mbBlocked = mbHit != null && !mbHit.ok;

  c.note('C1.underpay-allow', 'total_eur/item_price + shipping/pay allowlist', {
    'ctt': cttHit?.brief,
    'cttAmt': cttAmt,
    'homo': homoHit?.brief,
    'miss': missHit?.brief,
    'zwsp': zwspHit?.brief,
    'mb': mbHit?.brief,
    'mbBlocked': mbBlocked,
  }, lens: 'CP5', well: 'CP-C');

  recordHoldOrFail(
    c: c,
    probeId: 'C1',
    poco: 'CP-C',
    lens: 'CP5',
    payload:
        'body total_eur=0.00 item_price=0.01 shipping=0 + selo CTT; homoglyph portes; €3.5; mbway ZWSP',
    http: {
      'ctt': cttHit?.brief,
      'homo': homoHit?.brief,
      'miss': missHit?.brief,
      'zwsp': zwspHit?.brief,
      'mb': mbHit?.brief,
    },
    bd: {
      'cttAmt': cttAmt,
      'homoAmt': homoHit?.amountTotal,
      'missAmt': missHit?.amountTotal,
      'zwspSid': zwspHit?.sessionId,
    },
    isHold: cttUnder || homoZero || missZero || zwspStripe,
    holdId: zwspStripe
        ? 'P1-C1'
        : (cttUnder || missZero || homoZero ? 'P0-C1' : 'P1-C1'),
    severity: (cttUnder || missZero || homoZero) ? 'P0' : 'P1',
    title: zwspStripe
        ? 'allowlist off-platform: mbway+ZWSP abriu Session Stripe'
        : 'body/selo hostil baixou amount_total abaixo do catálogo+CTT',
    actor: 'buyer JWT',
    pre: 'SKU 18€ selo ctt / homoglyph / €3.5 / mbway ZWSP',
    repro: 'CPI extras total_eur/item_price; CPI selos allowlist',
    expected:
        'amount ≈ 18€+CTT+protecção; portes inválidos 400; mbway ZWSP tratado como off-platform',
    obtained: {
      'cttAmt': cttAmt,
      'homo': homoHit?.brief,
      'miss': missHit?.brief,
      'zwsp': zwspHit?.brief,
    },
    blockId: 'C1-UNDERPAY-ALLOW',
    blockTitle:
        'total_eur ignorado; CTT selado; homoglyph/€3.5 400; ZWSP não abriu Stripe (ou mb way 400)',
  );

  // C2 coupon/portes hostis com Session open
  final c2 = await mkSkus(
    c,
    n: 1,
    tag: 'c2-open',
    qty: 2,
    price: 20,
    shipping: 'ctt',
  );
  if (c2.isNotEmpty) {
    final open = await c.checkout(
      orderId: c2.first.oid,
      productId: c2.first.pid,
      amount: 1,
      shipping: 'ctt',
    );
    c.trackSession(open);
    final amt0 = open.amountTotal;
    final coupon = await c.checkout(
      orderId: c2.first.oid,
      productId: c2.first.pid,
      amount: 1,
      shipping: 'mao',
      extra: {
        'coupon': 'FREESHIP',
        'discount_cents': 2000,
        'discount_pct': 99,
        'shipping_cents': 0,
        'protection_fee': 0,
      },
    );
    c.trackSession(coupon);
    final amt1 = coupon.amountTotal;
    final row = await c.orderRow(c2.first.oid);
    c.note('C2.coupon-open', 'coupon/portes com Session open', {
      'open': open.brief,
      'coupon': coupon.brief,
      'amt0': amt0,
      'amt1': amt1,
      'ship': row?['shipping_method'],
    }, lens: 'CP5', well: 'CP-C');
    final dropped = open.ok &&
        coupon.ok &&
        amt0 != null &&
        amt1 != null &&
        amt1 < amt0 - 50;
    recordHoldOrFail(
      c: c,
      probeId: 'C2',
      poco: 'CP-C',
      lens: 'CP5',
      payload: 'Session open CTT; 2.º CPI coupon FREESHIP + shipping=mao',
      http: {'open': open.brief, 'coupon': coupon.brief},
      bd: {'amt0': amt0, 'amt1': amt1, 'ship': row?['shipping_method']},
      isHold: dropped,
      holdId: 'P0-C2',
      severity: 'P0',
      title: 'coupon/portes hostis baixaram Session já aberta',
      actor: 'buyer JWT',
      pre: 'cs_ open selo CTT',
      repro: 'CPI; CPI extra coupon+mao',
      expected: 'amount_total estável (selo CTT) ou reuse mesma Session',
      obtained: {'amt0': amt0, 'amt1': amt1, 'coupon': coupon.brief},
      blockId: 'C2-COUPON-OPEN',
      blockTitle: 'Session open: coupon/mao não baixou amount',
    );
  }

  // C3 Stripe TEST pago 4242 + ordem/caixa
  final paid = await c.payToPago(lens: 'CP7', initialQty: 2);
  if (paid == null) {
    c.skip('C3', 'CP7', 'setup_paid_order falhou', 'null');
    c.probe(
      id: 'C3',
      poco: 'CP-C',
      payload: 'setup_paid_order Stripe TEST 4242',
      http: 'null',
      bd: '-',
      verdict: 'SKIP',
      lens: 'CP7',
    );
  } else {
    final row = await c.orderRow(paid.oid);
    final prod = await c.productRow(paid.pid);
    final wallets1 = await c.wallets();
    final st = '${row?['status']}';
    final cents = numOf(row?['amount_paid_cents']);
    final applied = numOf(row?['stock_units_applied']);
    final qty = numOf(prod?['quantity']);
    final pi = '${row?['stripe_payment_intent_id'] ?? ''}';
    final coherent = st == 'pago' &&
        pi.startsWith('pi_') &&
        cents != null &&
        cents >= 50 &&
        applied == 1 &&
        qty == 1;
    c.note('C3.paid', 'Stripe TEST pago + caixa', {
      'oid': paid.oid,
      'pid': paid.pid,
      'pi': pi,
      'status': st,
      'cents': cents,
      'applied': applied,
      'qty': qty,
      'wallets0': wallets0,
      'wallets1': wallets1,
    }, lens: 'CP7', well: 'CP-C');
    if (!coherent) {
      c.hold(
        id: 'P1-C3',
        lens: 'CP7',
        severity: 'P1',
        title: 'Stripe TEST pago mas ordem/caixa incoerente',
        actor: 'e2e setup_paid_order (pm_card_visa / 4242)',
        pre: 'qty=2',
        repro: 'setup_paid_order',
        expected: 'status=pago PI amount_paid stock 2→1 applied=1',
        obtained: row,
      );
      c.probe(
        id: 'C3',
        poco: 'CP-C',
        payload: 'Stripe TEST pago 4242 + contabilidade order',
        http: {'oid': paid.oid, 'pi': pi},
        bd: {
          'status': st,
          'cents': cents,
          'applied': applied,
          'qty': qty,
        },
        verdict: 'HOLD',
        lens: 'CP7',
      );
    } else {
      c.block('C3-PAID', 'CP7', 'pago + caixa coerente', {
        'oid': paid.oid,
        'pi': pi,
        'cents': cents,
        'qty': qty,
      });
      c.probe(
        id: 'C3',
        poco: 'CP-C',
        payload: 'Stripe TEST pago 4242 + contabilidade order',
        http: {'oid': paid.oid, 'pi': pi},
        bd: {
          'status': st,
          'cents': cents,
          'applied': applied,
          'qty': qty,
          'wallets0': wallets0,
          'wallets1': wallets1,
        },
        verdict: 'FAIL',
        lens: 'CP7',
      );
    }
  }
}
