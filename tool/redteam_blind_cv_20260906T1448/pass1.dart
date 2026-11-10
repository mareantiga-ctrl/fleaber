/// RED TEAM CEGO CV pass1 — marketplace pós-CPCU.
/// Matriz A1–A4 · B1–B4 · C1–C4 + encodes novos. Sem correções.
import 'dart:io';

import '_rtcv.dart';

Future<void> main() async {
  final c = Rtcv.fromEnv(loadEnv());
  stdout.writeln('CV pass1 staging=${c.url} prefix=$prefix');
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
  c.note('CV7.wallet.pre', 'baseline', wallets0, lens: 'CV7', well: 'CV-C');

  await cvAClaimSession(c);
  await cvBBagRace(c);
  await cvCOffPricePaid(c, wallets0);

  final wallets1 = await c.wallets();
  c.note('CV7.wallet.post', 'após probes', {
    'pre': wallets0,
    'post': wallets1,
  }, lens: 'CV7', well: 'CV-C');

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
  Rtcv c, {
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

Future<int> openPayableCount(Rtcv c, Iterable<String> sids) async {
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

Future<Map<String, Object?>> peekCheckout(Rtcv c, String sid) async {
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
  required Rtcv c,
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

/// CV-A Claim / Session
Future<void> cvAClaimSession(Rtcv c) async {
  c.wellsTried.add('CV-A');

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
    }, lens: 'CV1', well: 'CV-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A1',
      poco: 'CV-A',
      lens: 'CV1',
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
      blockTitle: 'cs_ morta reclaim OK / 2.º actor negado',
    );
  } else {
    c.skip('A1', 'CV1', 'não criou SKU', 'mkSkus empty');
    c.probe(
      id: 'A1',
      poco: 'CV-A',
      payload: 'cs_ morta reclaim',
      http: 'skip fixture',
      bd: '-',
      verdict: 'SKIP',
      lens: 'CV1',
    );
  }

  // A2 claiming timestamp futuro (+1 ano) — CPCU: futuro=órfão reclaim
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
    }, lens: 'CV2', well: 'CV-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A2',
      poco: 'CV-A',
      lens: 'CV2',
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

  // A3 claiming malform / TTL / passado extremo
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
    c.note('A3.malform', 'claiming malform/TTL/passado extremo', {
      'toks': toks,
      'briefs': briefs,
      'stored': stored,
    }, lens: 'CV2', well: 'CV-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A3',
      poco: 'CV-A',
      lens: 'CV2',
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
      blockTitle: 'malform/TTL/passado extremo reclaim',
    );
  }

  // A4 timeout mid-claim + retry (Future.wait)
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
    }, lens: 'CV6', well: 'CV-A');
    recordHoldOrFail(
      c: c,
      probeId: 'A4',
      poco: 'CV-A',
      lens: 'CV6',
      payload: 'Future.wait bag timeout 250ms ∥ retry',
      http: briefs,
      bd: {'stored': stored, 'payable': payable, 'sids': sids.toList()},
      isHold: payable >= 2,
      holdId: 'P0-A4',
      severity: 'P0',
      title: 'Timeout mid-claim + retry = 2 cs_ pagáveis',
      actor: 'buyer JWT',
      pre: '2-line bag',
      repro: 'Future.wait checkoutBag timeout 250ms ∥ retry',
      expected: '≤1 cs_ útil (idempotente ou contention)',
      obtained: {'sids': sids.toList(), 'stored': stored, 'payable': payable},
      blockId: 'A4-TIMEOUT',
      blockTitle: 'timeout∥retry ≤1 Session útil',
    );
  }
}

/// CV-B Bag overlap / race
Future<void> cvBBagRace(Rtcv c) async {
  c.wellsTried.add('CV-B');

  // B1 bag 4-line ∥ bag 2-line overlap (obrigatório) — CPCU: ≤1 cs_ útil
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
    final secondBlocked = hits.any((h) =>
        !h.ok &&
        (h.body.toLowerCase().contains('contention') ||
            h.body.toLowerCase().contains('claim busy') ||
            h.body.toLowerCase().contains('lock bag')));
    final useful = sids.length;
    final twoUseful = useful >= 2;
    c.note('B1.4x2', 'bag 4-line ∥ 2-line overlap', {
      'sids': sids.toList(),
      'payable': payable,
      'briefs': briefs,
      'stored': stored,
      'secondBlocked': secondBlocked,
      'peeks': peeks,
    }, lens: 'CV3', well: 'CV-B');
    recordHoldOrFail(
      c: c,
      probeId: 'B1',
      poco: 'CV-B',
      lens: 'CV3',
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
      title: 'Overlap 4∥2: 2 Sessions úteis',
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
    );
  } else {
    c.skip('B1', 'CV3', 'não criou 4 SKUs', 'mkSkus');
    c.probe(
      id: 'B1',
      poco: 'CV-B',
      payload: 'bag 4∥2',
      http: 'skip',
      bd: '-',
      verdict: 'SKIP',
      lens: 'CV3',
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
      }, lens: 'CV6', well: 'CV-B');
      recordHoldOrFail(
        c: c,
        probeId: 'B2',
        poco: 'CV-B',
        lens: 'CV6',
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

  // B3 checkout ∥ unlist
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
    }, lens: 'CV6', well: 'CV-B');
    recordHoldOrFail(
      c: c,
      probeId: 'B3',
      poco: 'CV-B',
      lens: 'CV6',
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
      blockTitle: 'unlist∥checkout sem Session+qty0 simultâneos',
    );
  }

  // B4 bag 3∥1 overlap + cross-seller
  final b4 = await mkSkus(c, n: 3, tag: 'b4-3x1', qty: 2, price: 10);
  List<String> b4briefs = [];
  Set<String> b4sids = {};
  int b4payable = 0;
  List<String> b4stored = [];
  if (b4.length == 3) {
    final three = bagLines(b4);
    final one = bagLines([b4[2]]);
    final hits = await parallel([
      c.checkoutBag(lines: three, amount: 1),
      c.checkoutBag(lines: one, amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    b4sids = openCs(hits);
    b4payable = await openPayableCount(c, b4sids);
    b4briefs = hits.map((h) => h.brief).toList();
    b4stored = [
      for (final r in b4)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
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
  final crossOk = cross != null && cross.ok;
  final overlapTwo = b4sids.length >= 2;
  c.note('B4.3x1-cross', 'bag 3∥1 + cross-seller', {
    'briefs': b4briefs,
    'sids': b4sids.toList(),
    'payable': b4payable,
    'stored': b4stored,
    'cross': cross?.brief,
  }, lens: 'CV3', well: 'CV-B');
  recordHoldOrFail(
    c: c,
    probeId: 'B4',
    poco: 'CV-B',
    lens: 'CV3',
    payload: 'Future.wait bag 3-line ∥ 1-line overlap + cross-seller',
    http: {'overlap': b4briefs, 'cross': cross?.brief},
    bd: {
      'sids': b4sids.toList(),
      'payable': b4payable,
      'stored': b4stored,
      'crossOk': crossOk,
    },
    isHold: overlapTwo || crossOk,
    holdId: crossOk ? 'P1-B4' : 'P1-B4',
    severity: 'P1',
    title: crossOk
        ? 'bag cross-seller criou Session'
        : 'Overlap 3∥1: 2 Sessions úteis',
    actor: 'buyer JWT',
    pre: '3 SKUs + SKU seller2',
    repro: 'Future.wait bag 3∥1; bag 2 sellers',
    expected: '≤1 cs_ no overlap; 400 one seller no cross',
    obtained: {
      'sids': b4sids.toList(),
      'payable': b4payable,
      'cross': cross?.brief,
    },
    blockId: 'B4-3x1-CROSS',
    blockTitle: '3∥1 ≤1 cs_; cross-seller 400',
  );
}

Future<Map<String, Object?>> probeEncode(
  Rtcv c, {
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
    // JWT insert pode recusar unicode — plant service_role (observação CPI)
    final pid = await c.createProduct(title: '$prefix-$tag-svc', qty: 2, price: 18);
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
  };
}

/// CV-C Off-platform + preço
Future<void> cvCOffPricePaid(Rtcv c, Map<String, num> wallets0) async {
  c.wellsTried.add('CV-C');

  // C1 controlo: mb way exact → 400 off-platform
  final c1 = await probeEncode(c, tag: 'c1-mbway', payment: 'mb way');
  c.note('C1.control', 'mb way exact', c1, lens: 'CV4', well: 'CV-C');
  recordHoldOrFail(
    c: c,
    probeId: 'C1',
    poco: 'CV-C',
    lens: 'CV4',
    payload: 'mb way exact → esperado 400 off-platform',
    http: c1['cpi'],
    bd: c1,
    isHold: c1['opened'] == true || c1['denied'] != true,
    holdId: 'P1-C1',
    severity: 'P1',
    title: 'controlo mb way exact abriu Stripe (regressão CPCU)',
    actor: 'buyer JWT',
    pre: 'payment_method=mb way',
    repro: 'CPI',
    expected: '400 off-platform; sem cs_',
    obtained: c1,
    blockId: 'C1-MBWAY',
    blockTitle: 'mb way exact 400 off-platform',
  );

  // C2 novos encodes — NÃO só ZWSP/fullwidth/м
  final encodes = <String, String>{
    'C2-RLO': 'mb\u202Eway',
    'C2-SHY': 'mb\u00adway',
    'C2-TAG': 'mb\u{E0062}way',
    'C2-TAGS': String.fromCharCodes(const [0xE006D, 0xE0062, 0xE0077, 0xE0061, 0xE0079]),
    'C2-NFKC': '\u3386way', // ㎆way SQUARE MB + way
    'C2-WJ': 'mb\u2060way',
    'C2-MU': '\u03bcbway',
    'C2-WE': 'mb\u051Day',
    'C2-SC': '\u1D0D\u0299\u1D21\u1D00\u028F',
    'C2-HF': 'mb\u3164way',
    'C2-NFD': 'mbwa\u0301y',
  };
  final encodeHits = <String, Map<String, Object?>>{};
  final openedTags = <String>[];
  for (final e in encodes.entries) {
    final r = await probeEncode(
      c,
      tag: 'c2-${e.key.toLowerCase()}',
      payment: e.value,
    );
    encodeHits[e.key] = r;
    c.note(e.key, 'encode ${e.key}', r, lens: 'CV4', well: 'CV-C');
    final opened = r['opened'] == true;
    if (opened) openedTags.add(e.key);
    c.probe(
      id: e.key,
      poco: 'CV-C',
      payload: 'novo encode ${e.key} codes=${e.value.runes.map((x) => x.toRadixString(16)).toList()}',
      http: r['cpi'],
      bd: r,
      verdict: opened ? 'HOLD' : 'FAIL',
      lens: 'CV4',
    );
  }
  if (openedTags.isNotEmpty) {
    c.hold(
      id: 'P1-C2',
      lens: 'CV4',
      severity: 'P1',
      title: 'off-platform encode novo abriu Stripe: ${openedTags.join(",")}',
      actor: 'buyer JWT',
      pre: 'payment_method encodes novos (RLO/SHY/TAG/NFKC/homoglyph)',
      repro: 'CPI por encode',
      expected: '400 off-platform em todos',
      obtained: {
        'opened': openedTags,
        for (final t in openedTags) t: encodeHits[t],
      },
    );
  } else {
    c.block('C2-ENCODES', 'CV4', 'encodes novos negados', {
      'n': encodes.length,
      'tags': encodes.keys.toList(),
    });
  }

  // C3 underpay body / portes hostis
  final c3ctt = await mkSkus(
    c,
    n: 1,
    tag: 'c3-ctt',
    qty: 2,
    price: 18,
    shipping: 'ctt',
  );
  HttpHit? cttHit;
  if (c3ctt.isNotEmpty) {
    cttHit = await c.checkout(
      orderId: c3ctt.first.oid,
      productId: c3ctt.first.pid,
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
    tag: 'c3-homo',
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
    tag: 'c3-ship35',
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
  c.note('C3.underpay', 'body/portes hostis', {
    'ctt': cttHit?.brief,
    'cttAmt': cttAmt,
    'homo': homoHit?.brief,
    'miss': missHit?.brief,
  }, lens: 'CV5', well: 'CV-C');
  recordHoldOrFail(
    c: c,
    probeId: 'C3',
    poco: 'CV-C',
    lens: 'CV5',
    payload: 'body total_eur=0 item_price=0.01; homoglyph portes; €3.5',
    http: {
      'ctt': cttHit?.brief,
      'homo': homoHit?.brief,
      'miss': missHit?.brief,
    },
    bd: {'cttAmt': cttAmt, 'homoAmt': homoHit?.amountTotal, 'missAmt': missHit?.amountTotal},
    isHold: cttUnder || homoZero || missZero,
    holdId: 'P0-C3',
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
    blockId: 'C3-UNDERPAY',
    blockTitle: 'total_eur ignorado; CTT selado; homoglyph/€3.5 400',
  );

  // C4 Stripe TEST pago 4242 + caixa
  final paid = await c.payToPago(lens: 'CV7', initialQty: 2);
  if (paid == null) {
    c.skip('C4', 'CV7', 'setup_paid_order falhou', 'null');
    c.probe(
      id: 'C4',
      poco: 'CV-C',
      payload: 'setup_paid_order Stripe TEST 4242',
      http: 'null',
      bd: '-',
      verdict: 'SKIP',
      lens: 'CV7',
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
    c.note('C4.paid', 'Stripe TEST pago + caixa', {
      'oid': paid.oid,
      'pid': paid.pid,
      'pi': pi,
      'status': st,
      'cents': cents,
      'applied': applied,
      'qty': qty,
      'wallets0': wallets0,
      'wallets1': wallets1,
    }, lens: 'CV7', well: 'CV-C');
    if (!coherent) {
      c.hold(
        id: 'P1-C4',
        lens: 'CV7',
        severity: 'P1',
        title: 'Stripe TEST pago mas ordem/caixa incoerente',
        actor: 'e2e setup_paid_order (pm_card_visa / 4242)',
        pre: 'qty=2',
        repro: 'setup_paid_order',
        expected: 'status=pago PI amount_paid stock 2→1 applied=1',
        obtained: row,
      );
      c.probe(
        id: 'C4',
        poco: 'CV-C',
        payload: 'Stripe TEST pago 4242 + contabilidade order',
        http: {'oid': paid.oid, 'pi': pi},
        bd: {
          'status': st,
          'cents': cents,
          'applied': applied,
          'qty': qty,
        },
        verdict: 'HOLD',
        lens: 'CV7',
      );
    } else {
      c.block('C4-PAID', 'CV7', 'pago + caixa coerente', {
        'oid': paid.oid,
        'pi': pi,
        'cents': cents,
        'qty': qty,
      });
      c.probe(
        id: 'C4',
        poco: 'CV-C',
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
        lens: 'CV7',
      );
    }
  }

  // Anti-atrofia (não contar se HOLD)
  final atrophy = <String, String>{
    'CTRL-ZWSP': 'mbway\u200b',
    'CTRL-FW': 'ｍｂｗａｙ',
    'CTRL-CYR': 'мbway',
    'CTRL-PAYSAFE': 'PaysafeCash',
    'CTRL-PICPAY': 'PicPay',
  };
  for (final e in atrophy.entries) {
    final r = await probeEncode(
      c,
      tag: 'ctrl-${e.key.toLowerCase()}',
      payment: e.value,
    );
    final opened = r['opened'] == true;
    // Paysafe/PicPay: Stripe aberto = residual antigo (não contar).
    // ZWSP/FW/CYR: Stripe aberto = fecho CPCU falhou (não contar como finding novo).
    recordHoldOrFail(
      c: c,
      probeId: e.key,
      poco: 'CV-C',
      lens: 'CV4',
      payload: 'anti-atrofia ${e.key}',
      http: r['cpi'],
      bd: r,
      isHold: opened,
      holdId: 'CTRL-${e.key}',
      severity: 'P1',
      title: 'anti-atrofia ${e.key} abriu Stripe',
      actor: 'buyer JWT',
      pre: e.value.runes.map((x) => x.toRadixString(16)).join(' '),
      repro: 'CPI',
      expected: e.key.contains('PAYSAFE') || e.key.contains('PICPAY')
          ? 'comportamento residual conhecido'
          : '400 off-platform (fecho CPCU)',
      obtained: r,
      blockId: '${e.key}-BLOCK',
      blockTitle: '${e.key} sem Stripe (ou rails residual)',
      countFinding: false,
    );
  }
}
