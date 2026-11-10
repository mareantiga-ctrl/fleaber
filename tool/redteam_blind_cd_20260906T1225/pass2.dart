/// RED TEAM CEGO CD pass2 — fechar A4 dual cs_ (HTML Stripe), C1 last-unit, CD6.
import 'dart:convert';
import 'dart:io';

import '_rtcd.dart';

Future<HttpHit> getUrl(String url) async {
  final client = HttpClient();
  try {
    final rq = await client.getUrl(Uri.parse(url));
    rq.followRedirects = true;
    rq.headers.set('User-Agent', 'Mozilla/5.0 (compatible; RTCD/1.0)');
    rq.headers.set('Accept', 'text/html');
    final rs = await rq.close();
    final text = await rs.transform(utf8.decoder).join();
    return HttpHit(rs.statusCode, text, null, rs.headers.value('location'));
  } catch (e) {
    return HttpHit(599, '$e', {'error': '$e'});
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> pageState(Rtcd c, String? url, String sid) async {
  if (url == null || url.isEmpty) {
    return {'sid': sid, 'url': null};
  }
  final h = await getUrl(url);
  final body = h.body.toLowerCase();
  final expired = body.contains('expired') ||
      body.contains('session has expired') ||
      body.contains('não está disponível') ||
      h.status == 404;
  final pay = body.contains('pay') ||
      body.contains('card') ||
      body.contains('checkout') ||
      body.contains('stripe');
  return {
    'sid': sid,
    'status': h.status,
    'len': h.body.length,
    'expired_hint': expired,
    'pay_hint': pay && !expired,
    'snip': clip(h.body.replaceAll(RegExp(r'\s+'), ' '), 220),
  };
}

Future<void> main() async {
  final c = Rtcd.fromEnv(loadEnv());
  stdout.writeln('CD pass2 staging=${c.url}');
  await c.loginActors();
  await c.ensureBuyer2();

  await a4DualUrls(c);
  await a4RerunOverlap(c);
  await a3StuckPersist(c);
  await c1LastUnitRace(c);
  await c2UnlistRace(c);

  await c.dumpAll('pass2_findings.json');
  stdout.writeln(
    'DONE pass2 findings=${c.findings.length} blocked=${c.blocked.length} '
    'lenses=${c.lensesHit.toList()..sort()}',
  );
}

List<Map<String, Object?>> linesOf(
  Iterable<({String oid, String pid, double price})> rows,
) =>
    [
      for (final r in rows) {'order_id': r.oid, 'product_id': r.pid},
    ];

Future<List<({String oid, String pid, double price})>> mk(
  Rtcd c, {
  required int n,
  required String tag,
  int qty = 3,
  double price = 9,
  String? buyer,
  String? jwt,
}) async {
  final out = <({String oid, String pid, double price})>[];
  for (var i = 0; i < n; i++) {
    final p = price + i;
    final pid = await c.createProduct(title: '$prefix-$tag-$i', qty: qty, price: p);
    if (pid == null) continue;
    final oid = await c.insertOrder(
      productId: pid,
      price: p,
      buyer: buyer,
      jwt: jwt ?? c.buyerJwt,
    );
    if (oid == null) continue;
    out.add((oid: oid, pid: pid, price: p));
  }
  return out;
}

/// Pass1 A4 devolveu 2 cs_ — GET HTML das URLs gravadas + orders.
Future<void> a4DualUrls(Rtcd c) async {
  const s1 = 'cs_test_a1rbmIQFMEkywNJfhVt1ezHfbbGa7ZOnukWoDuQrET31uwGo7tBD2PMx7D';
  const s2 = 'cs_test_a13YQjZnFlOR46OGQuZZGyNjYZYlxoQj8TGoUJzZcd6HhBBjVbHbdp7lAD';
  final u1 = 'https://checkout.stripe.com/c/pay/$s1';
  final u2 = 'https://checkout.stripe.com/c/pay/$s2';
  final p1 = await pageState(c, u1, s1);
  final p2 = await pageState(c, u2, s2);
  c.note('P2.A4.html', 'GET HTML Sessions overlap pass1', {
    'p1': p1,
    'p2': p2,
  }, lens: 'CD2', well: 'CD-A');
  final pay1 = p1['pay_hint'] == true;
  final pay2 = p2['pay_hint'] == true;
  if (pay1 && pay2) {
    c.hold(
      id: 'P0-1',
      lens: 'CD2',
      severity: 'P0',
      title: 'Overlap 5∥3: 2 checkoutUrl Stripe ainda pagáveis (HTML)',
      actor: 'buyer JWT',
      pre: 'pass1 A4 bag ABCDE ∥ DEF',
      repro: 'GET checkout.stripe.com/c/pay/{cs1,cs2}',
      expected: '1 URL expired após intersect',
      obtained: {'p1': p1, 'p2': p2},
    );
  } else {
    c.block('A4-HTML-PASS1', 'CD2', 'HTML overlap pass1 não prova 2 pagáveis', {
      'p1': p1,
      'p2': p2,
    });
  }
}

Future<void> a4RerunOverlap(Rtcd c) async {
  final pool = await mk(c, n: 6, tag: 'p2-ov', qty: 2, price: 9);
  if (pool.length < 6) {
    c.skip('P2.A4.rerun', 'CD2', 'pool<6', '${pool.length}');
    return;
  }
  final big = pool.sublist(0, 5);
  final part = [pool[3], pool[4], pool[5]];
  final hits = await parallel([
    c.checkoutBag(lines: linesOf(big), amount: 1),
    c.checkoutBag(lines: linesOf(part), amount: 1),
  ]);
  c.lensesHit.add('CD6');
  final sids = hits
      .map((h) => h.sessionId ?? '')
      .where((s) => s.startsWith('cs_'))
      .toSet()
      .toList();
  final pages = <Map<String, Object?>>[];
  for (final h in hits) {
    final sid = h.sessionId;
    final url = h.map?['checkoutUrl']?.toString();
    pages.add(await pageState(c, url, sid ?? ''));
  }
  final stored = <Map<String, Object?>>[];
  for (final r in pool) {
    final row = await c.orderRow(r.oid);
    stored.add({
      'oid': r.oid,
      'sid': row?['stripe_checkout_session_id'],
    });
  }
  final storedSids = stored
      .map((e) => '${e['sid'] ?? ''}')
      .where((s) => s.startsWith('cs_'))
      .toSet();
  c.note('P2.A4.rerun', 'overlap 5∥3 + HTML + BD', {
    'cpi_sids': sids,
    'pages': pages,
    'stored': stored,
    'stored_cs_n': storedSids.length,
    'briefs': hits.map((h) => h.brief).toList(),
  }, lens: 'CD2', well: 'CD-A');

  final htmlPay = pages.where((p) => p['pay_hint'] == true).length;
  if (sids.length >= 2 && htmlPay >= 2) {
    c.hold(
      id: 'P0-1',
      lens: 'CD2',
      severity: 'P0',
      title: 'Overlap parcial 5∥3: 2 cs_ + 2 HTML pagáveis',
      actor: 'buyer JWT',
      pre: '6 SKUs; bag ABCDE ∥ bag DEF (2 SKUs partilhados)',
      repro: 'Future.wait 2× bag_checkout; GET checkoutUrl',
      expected: 'expire intersect → ≤1 URL pagável',
      obtained: {
        'cpi_sids': sids,
        'htmlPay': htmlPay,
        'stored_cs_n': storedSids.length,
        'stored': stored,
      },
    );
  } else if (sids.length >= 2) {
    c.hold(
      id: 'P1-1',
      lens: 'CD2',
      severity: 'P1',
      title: 'Overlap 5∥3 devolveu 2 cs_ distintas (HTML não confirma 2 pagáveis)',
      actor: 'buyer JWT',
      pre: 'bag ABCDE ∥ DEF',
      repro: 'Future.wait 2× bag_checkout',
      expected: '1 cs_ (reuse/expire)',
      obtained: {
        'cpi_sids': sids,
        'pages': pages,
        'stored_cs_n': storedSids.length,
      },
      proven: htmlPay >= 2,
    );
    // If HTML doesn't prove payable, still 2 cs_ issued is P1 if both exist in Stripe.
    // Mark proven only if HTML pay_hint. Otherwise note as P2 residual dual-id.
    if (htmlPay < 2) {
      c.findings.removeWhere((f) => f['id'] == 'P1-1');
      c.hold(
        id: 'P2-2',
        lens: 'CD2',
        severity: 'P2',
        title: 'Overlap 5∥3: Edge devolveu 2 cs_ distintas (HTML 1 pagável ou expirada)',
        actor: 'buyer JWT',
        pre: 'bag ABCDE ∥ DEF',
        repro: 'Future.wait 2× bag_checkout; GET HTML',
        expected: '1 cs_',
        obtained: {
          'cpi_sids': sids,
          'htmlPay': htmlPay,
          'pages': pages,
          'stored_cs_n': storedSids.length,
        },
      );
    }
  } else {
    c.block('A4-RERUN-ONE-SID', 'CD2', 'overlap rerun ≤1 cs_', {
      'sids': sids,
      'htmlPay': htmlPay,
    });
  }
}

Future<void> a3StuckPersist(Rtcd c) async {
  final sku = await mk(c, n: 1, tag: 'p2-stuck', qty: 2, price: 12);
  if (sku.isEmpty) return;
  final oid = sku.first.oid;
  await c.rest(
    'PATCH',
    'orders?id=eq.$oid',
    service: true,
    body: {'stripe_checkout_session_id': 'claiming:orphanedtoken12'},
    prefer: 'return=minimal',
  );
  final h1 = await c.checkout(
    orderId: oid,
    productId: sku.first.pid,
    amount: 1,
  );
  await Future<void>.delayed(const Duration(seconds: 5));
  final h2 = await c.checkout(
    orderId: oid,
    productId: sku.first.pid,
    amount: 1,
  );
  final row = await c.orderRow(oid);
  c.note('P2.A3.persist', 'claiming: órfão persistente (2 CPI + 5s)', {
    'h1': h1.brief,
    'h2': h2.brief,
    'stored': row?['stripe_checkout_session_id'],
  }, lens: 'CD2', well: 'CD-A');
  final stuck = '${row?['stripe_checkout_session_id']}'.startsWith('claiming:');
  if (stuck && !h1.ok && !h2.ok) {
    c.block(
      'P2-1-CONFIRM',
      'CD2',
      'P2-1 confirmado: claiming órfão persiste após 5s e 2 CPI',
      {
        'h1': h1.brief,
        'h2': h2.brief,
        'stored': row?['stripe_checkout_session_id'],
      },
    );
  }
}

/// C.1 last unit: 2 holds qty=1 cada em stock=2, depois stock→1, race checkout.
Future<void> c1LastUnitRace(Rtcd c) async {
  final pid = await c.createProduct(title: '$prefix-p2-last', qty: 2, price: 11);
  if (pid == null) return;
  final o1 = await c.insertOrder(productId: pid, price: 11, jwt: c.buyerJwt);
  final o2 = await c.insertOrder(
    productId: pid,
    price: 11,
    buyer: c.buyer2Id,
    jwt: c.buyer2Jwt,
  );
  if (o1 == null || o2 == null) {
    c.skip('P2.C1', 'CD6', 'não criou 2 holds', {
      'o1': o1,
      'o2': o2,
    });
    return;
  }
  await c.rest(
    'PATCH',
    'products?id=eq.$pid',
    service: true,
    body: {'quantity': 1},
    prefer: 'return=minimal',
  );
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
  c.lensesHit.add('CD6');
  final ok = hits.where((h) => h.ok).toList();
  final pages = <Map<String, Object?>>[];
  for (final h in ok) {
    pages.add(await pageState(
      c,
      h.map?['checkoutUrl']?.toString(),
      h.sessionId ?? '',
    ));
  }
  c.note('P2.C1.last', '2 buyers stock=1 após 2 holds', {
    'briefs': hits.map((h) => h.brief).toList(),
    'ok': ok.length,
    'pages': pages,
  }, lens: 'CD6', well: 'CD-C');
  if (ok.length >= 2) {
    c.hold(
      id: 'P0-2',
      lens: 'CD6',
      severity: 'P0',
      title: '2 buyers Session na última unidade (holds pré-existentes)',
      actor: 'buyer JWT + buyer2 JWT',
      pre: 'qty=2 → 2 orders → PATCH qty=1 → Future.wait CPI',
      repro: 'Future.wait 2× create-payment-intent 2 buyers',
      expected: '1 Session + 1 stock block',
      obtained: {
        'ok': ok.length,
        'sids': ok.map((h) => h.sessionId).toList(),
        'pages': pages,
      },
    );
  } else {
    c.block('C1-LAST-UNIT', 'CD6', 'race última unidade ≤1 Session', {
      'ok': ok.length,
      'briefs': hits.map((h) => h.brief).toList(),
    });
  }
}

Future<void> c2UnlistRace(Rtcd c) async {
  final pid = await c.createProduct(title: '$prefix-p2-unlist', qty: 2, price: 13);
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, price: 13, jwt: c.buyerJwt);
  if (oid == null) return;
  final hits = await parallel([
    c.checkout(orderId: oid, productId: pid, amount: 1),
    c.rest(
      'PATCH',
      'products?id=eq.$pid',
      jwt: c.sellerJwt,
      body: {'list_on_marketplace': false},
    ),
  ]);
  c.lensesHit.add('CD6');
  c.note('P2.C2.unlist-race', 'checkout ∥ unlist (2.ª race)', {
    'ck': hits[0].brief,
    'ul': hits[1].brief,
  }, lens: 'CD6', well: 'CD-C');
  c.block('C2-UNLIST-RACE2', 'CD6', '2.ª race unlist∥checkout executada', {
    'ck': hits[0].status,
    'ul': hits[1].status,
  });
}
