/// BX pass2 — verificar dual URLs (URL completa) + anon real + BD após race.
import 'dart:io';

import '_rtbx.dart';

Future<void> main() async {
  final c = Rtbx.fromEnv(loadEnv());
  await c.loginActors();

  await realAnon(c);
  await ringFullUrls(c);
  await bagSingleFullUrls(c);

  await c.dumpAll('pass2_findings.json');
  stdout.writeln('PASS2 findings=${c.findings.length} blocked=${c.blocked.length}');
}

Future<void> realAnon(Rtbx c) async {
  final p = await c.createProduct(title: '$prefix-anon2', price: 11, qty: 2);
  if (p == null) return;
  final o = await c.insertOrder(productId: p, jwt: c.buyerJwt, price: 11);
  if (o == null) return;
  final hit = await c.edge('create-payment-intent', {
    'buyer_id': c.buyerId,
    'order_id': o,
    'amount': 1,
    'currency': 'eur',
    'product_id': p,
    'shipping_method': 'mao',
  }, jwt: c.anon);
  c.note('BX7.anon2', 'checkout Authorization=anon key', hit.brief, lens: 'BX7');
  if (hit.ok) {
    c.hold(
      id: 'RTBX-BX7-ANON-CHECKOUT',
      lens: 'BX7',
      severity: 'P1',
      title: 'Anon key criou Checkout Session',
      actor: 'anon',
      pre: 'order do buyer',
      repro: 'POST create-payment-intent Bearer=anon',
      expected: '401/400 Invalid checkout user',
      obtained: hit.brief,
    );
  } else {
    c.block('BX7.anon2', 'BX7', 'anon key recusado', hit.brief);
  }
}

Future<void> ringFullUrls(Rtbx c) async {
  final prices = [12.0, 13.0, 14.0, 15.0];
  final pids = <String>[];
  final oids = <String>[];
  for (var i = 0; i < 4; i++) {
    final p = await c.createProduct(
      title: '$prefix-r2-$i',
      price: prices[i],
      qty: 5,
    );
    if (p == null) return;
    pids.add(p);
    final o = await c.insertOrder(productId: p, jwt: c.buyerJwt, price: prices[i]);
    if (o == null) return;
    oids.add(o);
  }
  List<Map<String, Object?>> pair(int a, int b) => [
        {'order_id': oids[a], 'product_id': pids[a]},
        {'order_id': oids[b], 'product_id': pids[b]},
      ];
  final bags = [pair(0, 1), pair(1, 2), pair(2, 3), pair(3, 0)];
  final labels = ['AB', 'BC', 'CD', 'DA'];
  final jobs = <Future<HttpHit>>[];
  for (var r = 0; r < 2; r++) {
    for (final b in bags) {
      jobs.add(c.checkoutBag(lines: b, amount: 1));
    }
  }
  final hits = await parallel(jobs);
  final urls = <Map<String, Object?>>[];
  for (var i = 0; i < hits.length; i++) {
    final m = hits[i].map ?? {};
    urls.add({
      'bag': labels[i % 4],
      'ok': hits[i].ok,
      'sid': hits[i].sessionId,
      'amt': hits[i].amountTotal,
      'reused': hits[i].reused,
      'url': m['checkoutUrl'],
    });
  }
  final rows = [
    for (final id in oids) await c.orderRow(id) ?? {'id': id},
  ];
  final kept = rows
      .map((r) => '${r['stripe_checkout_session_id'] ?? ''}')
      .where((s) => s.startsWith('cs_'))
      .toSet();
  final leftover = urls
      .where((u) =>
          u['ok'] == true &&
          '${u['sid']}'.startsWith('cs_') &&
          !kept.contains('${u['sid']}'))
      .toList();

  await dumpJson('${outDir()}/pass2_ring_urls.json', {
    'oids': oids,
    'kept': kept.toList(),
    'urls': urls,
    'leftover': leftover,
    'rows': rows
        .map((r) => {
              'id': r['id'],
              'sid': r['stripe_checkout_session_id'],
              'status': r['status'],
            })
        .toList(),
  });
  c.note('BX2.ring2', 'anel URLs completas', {
    'kept': kept.toList(),
    'leftover_n': leftover.length,
    'leftover_sids': leftover.map((e) => e['sid']).toSet().toList(),
    'leftover_urls': leftover.map((e) => e['url']).toSet().toList(),
  }, lens: 'BX2');
}

Future<void> bagSingleFullUrls(Rtbx c) async {
  final p0 = await c.createProduct(title: '$prefix-bs20', price: 16, qty: 4);
  final p1 = await c.createProduct(title: '$prefix-bs21', price: 9, qty: 4);
  if (p0 == null || p1 == null) return;
  final o0 = await c.insertOrder(productId: p0, jwt: c.buyerJwt, price: 16);
  final o1 = await c.insertOrder(productId: p1, jwt: c.buyerJwt, price: 9);
  if (o0 == null || o1 == null) return;
  final bagLines = [
    {'order_id': o0, 'product_id': p0},
    {'order_id': o1, 'product_id': p1},
  ];
  final hits = await parallel([
    c.checkoutBag(lines: bagLines, amount: 1),
    c.checkout(orderId: o0, productId: p0, amount: 1),
    c.checkoutBag(lines: bagLines, amount: 1),
    c.checkout(orderId: o0, productId: p0, amount: 1),
    c.checkout(orderId: o1, productId: p1, amount: 1),
    c.checkoutBag(lines: bagLines, amount: 1),
  ]);
  final r0 = await c.orderRow(o0);
  final r1 = await c.orderRow(o1);
  final kept = {
    '${r0?['stripe_checkout_session_id'] ?? ''}',
    '${r1?['stripe_checkout_session_id'] ?? ''}',
  }..removeWhere((s) => !s.startsWith('cs_'));
  final urls = [
    for (final h in hits)
      {
        'ok': h.ok,
        'sid': h.sessionId,
        'amt': h.amountTotal,
        'reused': h.reused,
        'url': h.map?['checkoutUrl'],
      }
  ];
  final leftover = urls
      .where((u) =>
          u['ok'] == true &&
          '${u['sid']}'.startsWith('cs_') &&
          !kept.contains('${u['sid']}'))
      .toList();
  await dumpJson('${outDir()}/pass2_bagsingle_urls.json', {
    'o0': r0,
    'o1': r1,
    'kept': kept.toList(),
    'urls': urls,
    'leftover': leftover,
  });
  c.note('BX2.bs2', 'bag+single URLs', {
    'kept': kept.toList(),
    'bd_same': r0?['stripe_checkout_session_id'] == r1?['stripe_checkout_session_id'],
    'leftover_n': leftover.length,
    'leftover_sids': leftover.map((e) => e['sid']).toSet().toList(),
    'leftover_urls': leftover.map((e) => e['url']).toSet().toList(),
    'amts': urls.map((e) => e['amt']).toList(),
  }, lens: 'BX2');
}
