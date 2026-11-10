/// BR pass2 — retract FP, anon real, bag 9+9 quote, persist SIDs da corrida.
import 'dart:convert';
import 'dart:io';

import '_rtbr.dart';

Future<void> main() async {
  final c = Rtbr.fromEnv(loadEnv());
  stdout.writeln('BR pass2 staging=${c.url}');
  await c.loginActors();
  await c.ensureBuyer2();

  await p2AnonReal(c);
  await p2BagNineNine(c);
  await p2HyphenDump(c);
  await p2TripleRacePersist(c);
  await p2RetractReopen(c);
  await p2MissingAuth(c);

  await c.dumpAll('findings_pass2.json');
  stdout.writeln(
    'PASS2 findings=${c.findings.length} blocked=${c.blocked.length}',
  );
}

Map<String, Object?> bagLine(String orderId, String productId) => {
      'order_id': orderId,
      'product_id': productId,
    };

Future<void> p2AnonReal(Rtbr c) async {
  const lens = 'BR7';
  final pid = await c.createProduct(price: 10, qty: 1, title: '$prefix-anon2');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 10);
  if (oid == null) return;
  final body = {
    'buyer_id': c.buyerId,
    'order_id': oid,
    'amount': 50,
    'currency': 'eur',
    'shipping_method': 'mao',
  };
  final anonKey = await c.checkoutRaw(body, asAnon: true);
  final junk = await c.checkoutRaw(body, noAuthUser: true);
  c.note('P2.ANON.key', 'Bearer=anon key', anonKey.brief, lens: lens);
  c.note('P2.ANON.junk', 'Bearer=not-a-jwt', junk.brief, lens: lens);
  if (anonKey.ok) {
    c.hold(
      id: 'BR7-ANON-KEY-CHECKOUT',
      lens: lens,
      severity: 'P1',
      title: 'Bearer anon key (sem user) criou Session',
      actor: 'anon apikey',
      pre: 'order buyer',
      repro: 'POST CPI Authorization=anon key',
      expected: '401 Invalid checkout user',
      obtained: anonKey.brief,
    );
  } else {
    c.block('BR7-ANON-KEY-CHECKOUT', lens, 'anon key recusado', anonKey.brief);
  }
  if (junk.ok) {
    c.hold(
      id: 'BR7-JUNK-JWT-CHECKOUT',
      lens: lens,
      severity: 'P1',
      title: 'JWT lixo criou Session',
      actor: 'unauth',
      pre: 'order buyer',
      repro: 'POST CPI Authorization=not-a-jwt',
      expected: '401',
      obtained: junk.brief,
    );
  } else {
    c.block('BR7-JUNK-JWT-CHECKOUT', lens, 'jwt lixo recusado', junk.brief);
  }
}

Future<void> p2BagNineNine(Rtbr c) async {
  const lens = 'BR1';
  final p1 = await c.createProduct(price: 9, qty: 2, title: '$prefix-99a');
  final p2 = await c.createProduct(price: 9, qty: 2, title: '$prefix-99b');
  if (p1 == null || p2 == null) return;
  final o1 = await c.insertOrder(productId: p1, jwt: c.buyerJwt, price: 9);
  final o2 = await c.insertOrder(productId: p2, jwt: c.buyerJwt, price: 9);
  if (o1 == null || o2 == null) return;
  final r1 = await c.orderRow(o1);
  final r2 = await c.orderRow(o2);
  final ck = await c.checkoutBag(lines: [bagLine(o1, p1), bagLine(o2, p2)]);
  final items = 900 + 900;
  final expect = items + protectionFeeCents(items, 0);
  c.note('P2.99.quote', 'saco limpo 9+9', {
    'c1': r1?['contract_unit_cents'],
    'c2': r2?['contract_unit_cents'],
    'amt': ck.amountTotal,
    'expect': expect,
    'raw': ck.map,
    'brief': ck.brief,
  }, lens: lens);
  if (ck.ok && ck.amountTotal != null && ck.amountTotal! < expect - 40) {
    c.hold(
      id: 'BR1-BAG-9-9-UNDERPAY',
      lens: lens,
      severity: 'P0',
      title: 'Saco 9€+9€ Session abaixo de 19,55 €',
      actor: 'buyer JWT',
      pre: '2 SKUs 9€',
      repro: 'POST CPI bag_checkout 2 linhas',
      expected: expect,
      obtained: ck.amountTotal,
      evidence: {'contracts': [r1, r2], 'map': ck.map},
    );
  } else {
    c.block('BR1-BAG-9-9-UNDERPAY', lens, 'saco 9+9 ao contrato',
        'amt=${ck.amountTotal} expect=$expect');
  }
}

Future<void> p2HyphenDump(Rtbr c) async {
  const lens = 'BR2';
  final p1 = await c.createProduct(price: 9, qty: 2, title: '$prefix-h2a');
  final p2 = await c.createProduct(price: 9, qty: 2, title: '$prefix-h2b');
  if (p1 == null || p2 == null) return;
  final o1 = await c.insertOrder(productId: p1, jwt: c.buyerJwt, price: 9);
  final o2 = await c.insertOrder(productId: p2, jwt: c.buyerJwt, price: 9);
  if (o1 == null || o2 == null) return;
  final compact = o1.replaceAll('-', '');
  final ck = await c.checkoutBag(lines: [
    bagLine(o1, p1),
    {'order_id': compact, 'product_id': p1},
    bagLine(o2, p2),
  ]);
  final items = 1800;
  final expect = items + protectionFeeCents(items, 0);
  c.note('P2.HYPHEN.dump', 'hífen+compact dump completo', {
    'amt': ck.amountTotal,
    'expect2': expect,
    'reused': ck.reused,
    'map': ck.map,
    'o1': o1,
    'compact': compact,
  }, lens: lens);
  // exact BF — não hold mesmo se amt≠expect
  c.block('BR2-HYPHEN-DUMP', lens, 'exact hífen (n/c) dump',
      'amt=${ck.amountTotal} expect=$expect reused=${ck.reused}');
}

Future<void> p2TripleRacePersist(Rtbr c) async {
  const lens = 'BR6';
  final pa = await c.createProduct(price: 7, qty: 2, title: '$prefix-rA');
  final pb = await c.createProduct(price: 7, qty: 2, title: '$prefix-rB');
  final pc = await c.createProduct(price: 7, qty: 2, title: '$prefix-rC');
  if (pa == null || pb == null || pc == null) return;
  final oa = await c.insertOrder(productId: pa, jwt: c.buyerJwt, price: 7);
  final ob = await c.insertOrder(productId: pb, jwt: c.buyerJwt, price: 7);
  final oc = await c.insertOrder(productId: pc, jwt: c.buyerJwt, price: 7);
  if (oa == null || ob == null || oc == null) return;
  final hits = await parallel([
    c.checkoutBag(lines: [bagLine(oa, pa), bagLine(ob, pb)]),
    c.checkoutBag(lines: [bagLine(ob, pb), bagLine(oc, pc)]),
    c.checkoutBag(lines: [bagLine(oc, pc), bagLine(oa, pa)]),
  ]);
  final rows = {
    'oa': await c.orderRow(oa),
    'ob': await c.orderRow(ob),
    'oc': await c.orderRow(oc),
  };
  final returned = hits
      .map((h) => h.sessionId)
      .whereType<String>()
      .where((s) => s.startsWith('cs_'))
      .toSet()
      .toList();
  final onOrders = rows.values
      .map((r) => (r?['stripe_checkout_session_id'] ?? '').toString())
      .where((s) => s.startsWith('cs_'))
      .toSet()
      .toList();
  c.note('P2.TRIPLE.persist', 'corrida 3 sacos SIDs vs BD', {
    'returned': returned,
    'on_orders': onOrders,
    'rows': rows.map((k, v) => MapEntry(k, {
          'status': v?['status'],
          'sid': v?['stripe_checkout_session_id'],
          'amt_paid': v?['amount_paid_cents'],
        })),
    'amts': hits.map((h) => h.amountTotal).toList(),
    'reused': hits.map((h) => h.reused).toList(),
  }, lens: lens);
  if (returned.length > 1) {
    c.hold(
      id: 'BR6-TRIPLE-BAG-RACE',
      lens: lens,
      severity: 'P1',
      title:
          'Corrida 3 sacos A∩B∩C criou ${returned.length} Sessions (BD ficou com ${onOrders.length})',
      actor: 'buyer JWT',
      pre: '3 orders; bags AB∥BC∥CA paralelo',
      repro: 'Future.wait 3× bag_checkout',
      expected: '1 cs_ (claim+expire overlap)',
      obtained: {'returned': returned, 'on_orders': onOrders},
      evidence: {'rows': rows},
    );
  } else {
    c.block('BR6-TRIPLE-BAG-RACE', lens, 'corrida devolveu ≤1 cs_',
        'returned=$returned on_orders=$onOrders');
  }
}

Future<void> p2RetractReopen(Rtbr c) async {
  const lens = 'BR2';
  c.note(
    'P2.RETRACT.reopen',
    'BR2-SESSION-REOPEN-AFTER-EXPIRE é FP: sem sk_test não houve expire; ck2 reusou Session ABERTA (desenho 1-order-1-session)',
    'retracted',
    lens: lens,
  );
  c.block(
    'BR2-SESSION-REOPEN-AFTER-EXPIRE',
    lens,
    'FP retract — reuse de cs_ open, expire Stripe não executado',
    'no sk_test_',
  );
}

Future<void> p2MissingAuth(Rtbr c) async {
  const lens = 'BR7';
  final pid = await c.createProduct(price: 10, qty: 1, title: '$prefix-noauth');
  if (pid == null) return;
  final oid = await c.insertOrder(productId: pid, jwt: c.buyerJwt, price: 10);
  if (oid == null) return;
  final uri = Uri.parse(
    '${c.url}/functions/v1/create-payment-intent',
  );
  final client = HttpClient();
  try {
    final rq = await client.postUrl(uri);
    rq.headers.set('apikey', c.anon);
    rq.headers.set('Content-Type', 'application/json');
    rq.add(utf8.encode(jsonEncode({
      'buyer_id': c.buyerId,
      'order_id': oid,
      'amount': 50,
      'currency': 'eur',
      'shipping_method': 'mao',
    })));
    final rs = await rq.close();
    final text = await rs.transform(utf8.decoder).join();
    c.note('P2.NOAUTH', 'CPI sem Authorization', '${rs.statusCode} $text',
        lens: lens);
    if (rs.statusCode >= 200 && rs.statusCode < 300) {
      c.hold(
        id: 'BR7-NO-AUTHORIZATION',
        lens: lens,
        severity: 'P1',
        title: 'CPI sem header Authorization criou Session',
        actor: 'anon',
        pre: 'só apikey',
        repro: 'POST CPI sem Bearer',
        expected: '401 Missing authorization',
        obtained: '${rs.statusCode} $text',
      );
    } else {
      c.block('BR7-NO-AUTHORIZATION', lens, 'sem Authorization recusado',
          '${rs.statusCode} ${text.length > 180 ? text.substring(0, 180) : text}');
    }
  } finally {
    client.close(force: true);
  }
}
