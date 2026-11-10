/// BF pass2 — aprofundar dual Session 2 bags + dup line sem product_id. Não corrige.
library;

import 'dart:convert';
import 'dart:io';

import '_rtbf.dart';

Future<HttpHit> getNoAuth(String url) async {
  final client = HttpClient();
  try {
    final rq = await client.getUrl(Uri.parse(url));
    rq.followRedirects = true;
    rq.headers.removeAll('authorization');
    final rs = await rq.close();
    final text = await rs.transform(utf8Decoder).join();
    return HttpHit(rs.statusCode, text, null, rs.headers.value('location'));
  } finally {
    client.close(force: true);
  }
}

const utf8Decoder = Utf8Decoder();

Future<void> main() async {
  final c = Rtbf.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  await dupLineNoProduct(c);
  await recreateTwoBags(c);
  await observeExpireUrls(c);

  await dumpJson('${outDir()}/pass2.json', {
    'stamp': stamp,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln('PASS2 findings=${c.findings.length} blocked=${c.blocked.length}');
}

Future<void> dupLineNoProduct(Rtbf c) async {
  final sku = await c.createProduct(title: '$prefix p2-dup', qty: 4, price: 15);
  if (sku == null) return;
  final oid = await c.insertOrder(productId: sku, jwt: c.buyerJwt, qty: 1, price: 15);
  if (oid == null) return;
  final single = expectedCheckoutCents(1500);

  final ck = await c.checkoutBag(
    lines: [
      {'order_id': oid},
      {'order_id': compactUuid(oid)},
    ],
    amount: 1,
  );
  final amt = ck.serverAmount;
  c.note('p2.dup.noprod', 'hífen+compact SEM product_id', {
    'oid': oid,
    'amt': amt,
    'single': single,
    'sid': ck.checkoutSessionId,
    'brief': ck.brief,
    'reused': ck.map?['reused_session'],
  }, lens: 'BF2');

  if (ck.ok && amt != null && amt != single) {
    c.hold(
      id: 'RTBF-BF2-dup-hyphen-compact-noprod',
      lens: 'BF2',
      severity: amt < single ? 'P0' : 'P2',
      title: 'Mesma order hífen+compact (sem product_id) altera o total do saco',
      actor: 'buyer JWT',
      pre: '1 order 15€',
      repro: 'bag_lines: [{order_id: hífen}, {order_id: compact}]',
      expected: '1 linha $single',
      obtained: {'amt': amt, 'single': single, 'sid': ck.checkoutSessionId, 'brief': ck.brief},
    );
  } else {
    c.block('RTBF-BF2-dup-hyphen-compact-noprod', 'BF2', 'dup sem product_id colapsado/recusado', ck.brief);
  }
}

Future<void> recreateTwoBags(Rtbf c) async {
  final a = await c.createProduct(title: '$prefix p2-a', qty: 2, price: 14);
  final b = await c.createProduct(title: '$prefix p2-b', qty: 2, price: 11);
  final d = await c.createProduct(title: '$prefix p2-c', qty: 2, price: 7);
  if (a == null || b == null || d == null) return;
  final oa = await c.insertOrder(productId: a, jwt: c.buyerJwt, qty: 1, price: 14);
  final ob = await c.insertOrder(productId: b, jwt: c.buyerJwt, qty: 1, price: 11);
  final oc = await c.insertOrder(productId: d, jwt: c.buyerJwt, qty: 1, price: 7);
  if (oa == null || ob == null || oc == null) return;

  final jobs = await parallel([
    c.checkoutBag(lines: [
      {'order_id': oa},
      {'order_id': ob},
    ], amount: 1),
    c.checkoutBag(lines: [
      {'order_id': oa},
      {'order_id': oc},
    ], amount: 1),
  ]);

  final urls = <String>[];
  final sids = <String>[];
  for (final h in jobs) {
    final sid = h.checkoutSessionId;
    final url = h.map?['checkoutUrl']?.toString();
    if (sid != null && sid.startsWith('cs_')) sids.add(sid);
    if (url != null && url.startsWith('http')) urls.add(url.split('#').first);
  }

  final ra = await c.orderRow(oa);
  final rb = await c.orderRow(ob);
  final rc = await c.orderRow(oc);

  final probes = <Map<String, Object?>>[];
  for (final url in urls) {
    final hit = await getNoAuth(url);
    final body = hit.body.toLowerCase();
    probes.add({
      'url': url,
      'status': hit.status,
      'expired': body.contains('expired') || body.contains('session has expired'),
      'has_pay': body.contains('card') || body.contains('pay') || body.contains('stripe'),
      'snippet': clip(hit.body, 220),
    });
  }

  c.note('p2.two-bags', 'race + GET urls sem Authorization', {
    'oa': oa,
    'ob': ob,
    'oc': oc,
    'sids': sids,
    'urls': urls,
    'amts': jobs.map((h) => h.serverAmount).toList(),
    'stored': {
      'A': ra?['stripe_checkout_session_id'],
      'B': rb?['stripe_checkout_session_id'],
      'C': rc?['stripe_checkout_session_id'],
    },
    'probes': probes,
    'briefs': jobs.map((h) => h.brief).toList(),
  }, lens: 'BF2');

  final live = probes.where((p) => p['expired'] != true && (p['status'] as int) < 400).length;
  if (sids.toSet().length >= 2 && live >= 2) {
    c.hold(
      id: 'RTBF-BF2-two-bags-both-urls-live',
      lens: 'BF2',
      severity: 'P1',
      title: 'Dois checkout Stripe do saco sobreposto continuam servíveis',
      actor: 'buyer JWT',
      pre: 'race bag(A,B) ∥ bag(A,C)',
      repro: 'GET checkoutUrl sem Authorization nas duas cs_',
      expected: 'uma URL expired',
      obtained: {'sids': sids, 'urls': urls, 'probes': probes, 'stored': {
        'A': ra?['stripe_checkout_session_id'],
        'B': rb?['stripe_checkout_session_id'],
        'C': rc?['stripe_checkout_session_id'],
      }},
    );
  }
}

Future<void> observeExpireUrls(Rtbf c) async {
  final p1 = await c.createProduct(title: '$prefix p2-e1', qty: 2, price: 13);
  final p2 = await c.createProduct(title: '$prefix p2-e2', qty: 2, price: 9);
  final p3 = await c.createProduct(title: '$prefix p2-e3', qty: 2, price: 6);
  if (p1 == null || p2 == null || p3 == null) return;
  final o1 = await c.insertOrder(productId: p1, jwt: c.buyerJwt, qty: 1, price: 13);
  final o2 = await c.insertOrder(productId: p2, jwt: c.buyerJwt, qty: 1, price: 9);
  final o3 = await c.insertOrder(productId: p3, jwt: c.buyerJwt, qty: 1, price: 6);
  if (o1 == null || o2 == null || o3 == null) return;

  final s1 = await c.checkoutBag(lines: [
    {'order_id': o1},
    {'order_id': o2},
  ], amount: 1);
  final url1 = (s1.map?['checkoutUrl']?.toString() ?? '').split('#').first;
  final sid1 = s1.checkoutSessionId;

  final s2 = await c.checkoutBag(lines: [
    {'order_id': o1},
    {'order_id': o3},
  ], amount: 1);
  final url2 = (s2.map?['checkoutUrl']?.toString() ?? '').split('#').first;
  final sid2 = s2.checkoutSessionId;

  HttpHit? u1;
  HttpHit? u2;
  if (url1.startsWith('http')) u1 = await getNoAuth(url1);
  if (url2.startsWith('http')) u2 = await getNoAuth(url2);

  String classify(HttpHit? h) {
    if (h == null) return 'none';
    final b = h.body.toLowerCase();
    if (b.contains('expired') || b.contains('session has expired')) return 'expired';
    return 'status=${h.status}';
  }

  c.note('p2.expire.urls', 'S1 vs S2 após troca de composição', {
    'sid1': sid1,
    'sid2': sid2,
    'url1': url1,
    'url2': url2,
    'class1': classify(u1),
    'class2': classify(u2),
    'snip1': u1 == null ? null : clip(u1.body, 200),
    'snip2': u2 == null ? null : clip(u2.body, 200),
    'same_sid': sid1 == sid2,
  }, lens: 'BF2');

  if (sid1 != null && sid2 != null && sid1 != sid2 && classify(u1) != 'expired') {
    c.hold(
      id: 'RTBF-BF2-s1-alive-after-composition-change',
      lens: 'BF2',
      severity: 'P1',
      title: 'Session S1 do saco anterior continua servível depois de S2 noutra composição',
      actor: 'buyer JWT',
      pre: 'S1 bag(1,2); S2 bag(1,3)',
      repro: 'GET checkoutUrl S1 sem Authorization',
      expected: 'S1 expired',
      obtained: {
        'sid1': sid1,
        'sid2': sid2,
        'class1': classify(u1),
        'class2': classify(u2),
      },
    );
  } else {
    c.block(
      'RTBF-BF2-s1-alive-after-composition-change',
      'BF2',
      'S1 expirada ou mesma Session',
      {'sid1': sid1, 'sid2': sid2, 'class1': classify(u1), 'class2': classify(u2)},
    );
  }
}
