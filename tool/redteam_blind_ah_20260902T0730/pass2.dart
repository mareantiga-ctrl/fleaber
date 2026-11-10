/// RED TEAM CEGO AH pass2 — provar Sessions órfãs via URL Stripe + bundle aceite seller.
import 'dart:convert';
import 'dart:io';

import '_rtah.dart';

Future<void> main() async {
  final c = Rtah.fromEnv(loadEnv());
  stdout.writeln('AH pass2 prefix=$prefix');
  await c.loginActors();
  await c.ensureBuyer2();

  await proveOrphanUrls(c);
  await proveAcceptedBundlePartial(c);
  await proveBagRaceDb(c);

  await c.dumpAll('pass2_findings.json');
  stdout.writeln(
    'PASS2 findings=${c.findings.length} blocked=${c.blocked.length}',
  );
}

Map<String, Object?> bagLine(String orderId, String productId) => {
      'order_id': orderId,
      'product_id': productId,
    };

Future<Map<String, Object?>> probeCheckoutUrl(String sid) async {
  final url = 'https://checkout.stripe.com/c/pay/$sid';
  final client = HttpClient();
  try {
    final rq = await client.getUrl(Uri.parse(url));
    rq.followRedirects = false;
    final rs = await rq.close();
    final body = await rs.transform(utf8.decoder).join();
    final lower = body.toLowerCase();
    final expired = lower.contains('expired') ||
        lower.contains('expirou') ||
        lower.contains('no longer available') ||
        lower.contains('session has been expired');
    final payUi = lower.contains('checkout') ||
        lower.contains('payment') ||
        lower.contains('card');
    return {
      'http': rs.statusCode,
      'len': body.length,
      'expired_copy': expired,
      'pay_ui': payUi,
      'loc': rs.headers.value('location'),
      'snip': clip(body.replaceAll(RegExp(r'\s+'), ' '), 180),
    };
  } finally {
    client.close(force: true);
  }
}

Future<void> proveOrphanUrls(Rtah c) async {
  final lens = 'AH2';
  final pa = await c.createProduct(price: 12, qty: 2, title: '$prefix-p2-a');
  final pb = await c.createProduct(price: 13, qty: 2, title: '$prefix-p2-b');
  final pc = await c.createProduct(price: 21, qty: 2, title: '$prefix-p2-c');
  if (pa == null || pb == null || pc == null) return;
  final oa = await c.insertOrder(productId: pa, jwt: c.buyerJwt, price: 12);
  final ob = await c.insertOrder(productId: pb, jwt: c.buyerJwt, price: 13);
  final oc = await c.insertOrder(productId: pc, jwt: c.buyerJwt, price: 21);
  if (oa == null || ob == null || oc == null) return;

  final bag1 = await c.checkoutBag(lines: [bagLine(oa, pa), bagLine(ob, pb)]);
  final s1 = bag1.sessionId;
  final bag2 = await c.checkoutBag(lines: [bagLine(oa, pa), bagLine(oc, pc)]);
  final s2 = bag2.sessionId;
  final ra = await c.orderRow(oa);
  final rb = await c.orderRow(ob);
  final rc = await c.orderRow(oc);
  Map<String, Object?>? u1;
  Map<String, Object?>? u2;
  if (s1 != null) u1 = await probeCheckoutUrl(s1);
  if (s2 != null) u2 = await probeCheckoutUrl(s2);

  c.note('P2.RECOMPOSE', 'bag A+B then A+C + URL probe', {
    's1': s1,
    's2': s2,
    'reused2': bag2.reused,
    'amt1': bag1.amountTotal,
    'amt2': bag2.amountTotal,
    'oa': ra?['stripe_checkout_session_id'],
    'ob': rb?['stripe_checkout_session_id'],
    'oc': rc?['stripe_checkout_session_id'],
    'url1': u1,
    'url2': u2,
  }, lens: lens);

  final s1StillOnB = rb?['stripe_checkout_session_id'] == s1;
  final twoIds = s1 != null && s2 != null && s1 != s2;
  final s1LooksLive = u1 != null &&
      u1['expired_copy'] != true &&
      ((u1['http'] as int?) ?? 0) >= 200 &&
      ((u1['http'] as int?) ?? 0) < 400;

  if (twoIds && s1StillOnB && s1LooksLive) {
    c.hold(
      id: 'AH2-BAG-RECOMPOSE-ORPHAN',
      lens: lens,
      severity: 'P1',
      title:
          'Saco A+B depois A+C (montantes diferentes): S1 continua na order B e o URL Stripe ainda serve página de pagamento',
      actor: 'buyer JWT',
      pre: '3 orders mesmo seller; bag A+B (12+13) depois bag A+C (12+21)',
      repro:
          'POST create-payment-intent bag A+B; POST bag A+C; GET orders B; GET checkout.stripe.com/c/pay/S1',
      expected: 'S1 expired; stripe_checkout_session_id limpo em B; só S2 viva',
      obtained: {
        's1': s1,
        's2': s2,
        'ob_sid': rb?['stripe_checkout_session_id'],
        'oa_sid': ra?['stripe_checkout_session_id'],
        'oc_sid': rc?['stripe_checkout_session_id'],
        'url1': u1,
        'url2': u2,
        'amt1': bag1.amountTotal,
        'amt2': bag2.amountTotal,
      },
    );
  } else if (twoIds && s1StillOnB) {
    c.hold(
      id: 'AH2-BAG-RECOMPOSE-ORPHAN',
      lens: lens,
      severity: 'P2',
      title:
          'Saco A+B depois A+C: BD deixa S1 na order B (S2 em A e C) — URL Stripe inconclusivo',
      actor: 'buyer JWT',
      pre: 'bag A+B depois A+C',
      repro: '2× bag_checkout; GET orders',
      expected: 'S1 expirada e desligada de B',
      obtained: {
        's1': s1,
        's2': s2,
        'ob': rb?['stripe_checkout_session_id'],
        'url1': u1,
      },
    );
  } else {
    c.block('AH2-BAG-RECOMPOSE-ORPHAN', lens, 'não reproduziu orphan BD+URL', {
      'twoIds': twoIds,
      's1StillOnB': s1StillOnB,
      'url1': u1,
    });
  }

  // Single then bag (inverso AE2 bag→single)
  final pd = await c.createProduct(price: 14, qty: 2, title: '$prefix-p2-d');
  final pe = await c.createProduct(price: 16, qty: 2, title: '$prefix-p2-e');
  if (pd == null || pe == null) return;
  final od = await c.insertOrder(productId: pd, jwt: c.buyerJwt, price: 14);
  final oe = await c.insertOrder(productId: pe, jwt: c.buyerJwt, price: 16);
  if (od == null || oe == null) return;
  final single = await c.checkout(orderId: od, amount: 50);
  final ss1 = single.sessionId;
  final bag = await c.checkoutBag(lines: [bagLine(od, pd), bagLine(oe, pe)]);
  final ss2 = bag.sessionId;
  final rd = await c.orderRow(od);
  Map<String, Object?>? us1;
  if (ss1 != null) us1 = await probeCheckoutUrl(ss1);
  c.note('P2.S2B', 'single then bag URL', {
    'ss1': ss1,
    'ss2': ss2,
    'od': rd?['stripe_checkout_session_id'],
    'url': us1,
  }, lens: lens);
  if (ss1 != null &&
      ss2 != null &&
      ss1 != ss2 &&
      us1 != null &&
      us1['expired_copy'] != true &&
      ((us1['http'] as int?) ?? 0) < 400) {
    c.hold(
      id: 'AH2-SINGLE-THEN-BAG-ORPHAN',
      lens: lens,
      severity: 'P1',
      title:
          'Checkout single depois saco: Session single continua pagável (inverso do fecho bag→single)',
      actor: 'buyer JWT',
      pre: 'order D session; depois bag D+E amount maior',
      repro: 'POST single D; POST bag D+E; GET checkout.stripe.com/c/pay/ss1',
      expected: 'ss1 expired',
      obtained: {
        'ss1': ss1,
        'ss2': ss2,
        'od_now': rd?['stripe_checkout_session_id'],
        'url': us1,
      },
    );
  } else {
    c.block('AH2-SINGLE-THEN-BAG-ORPHAN', lens, 'single não ficou pagável', {
      'ss1': ss1,
      'ss2': ss2,
      'url': us1,
    });
  }

  // Same amount different lines
  final p10a = await c.createProduct(price: 10, qty: 2, title: '$prefix-p2-10a');
  final p10b = await c.createProduct(price: 10, qty: 2, title: '$prefix-p2-10b');
  final p10c = await c.createProduct(price: 10, qty: 2, title: '$prefix-p2-10c');
  if (p10a == null || p10b == null || p10c == null) return;
  final o10a = await c.insertOrder(productId: p10a, jwt: c.buyerJwt, price: 10);
  final o10b = await c.insertOrder(productId: p10b, jwt: c.buyerJwt, price: 10);
  final o10c = await c.insertOrder(productId: p10c, jwt: c.buyerJwt, price: 10);
  if (o10a == null || o10b == null || o10c == null) return;
  final sa = await c.checkoutBag(lines: [bagLine(o10a, p10a), bagLine(o10b, p10b)]);
  final sb = await c.checkoutBag(lines: [bagLine(o10a, p10a), bagLine(o10c, p10c)]);
  final r10b = await c.orderRow(o10b);
  Map<String, Object?>? usa;
  if (sa.sessionId != null) usa = await probeCheckoutUrl(sa.sessionId!);
  c.note('P2.SAMEAMT', 'A+B vs A+C 10€', {
    's1': sa.sessionId,
    's2': sb.sessionId,
    'reused': sb.reused,
    'ob': r10b?['stripe_checkout_session_id'],
    'url': usa,
  }, lens: lens);
  if (sa.sessionId != null &&
      sb.sessionId != null &&
      sa.sessionId != sb.sessionId &&
      sb.reused != true &&
      r10b?['stripe_checkout_session_id'] == sa.sessionId &&
      usa != null &&
      usa['expired_copy'] != true) {
    c.hold(
      id: 'AH2-SAME-AMT-NO-EXPIRE',
      lens: lens,
      severity: 'P1',
      title:
          'Saco A+B vs A+C mesmo montante: não reutiliza (bag_order_ids) mas não expira S1 — B fica com Session do saco antigo',
      actor: 'buyer JWT',
      pre: '3 SKUs 10€',
      repro: 'bag A+B; bag A+C; GET order B; GET Stripe pay URL S1',
      expected: 'S1 expired (não só continue)',
      obtained: {
        's1': sa.sessionId,
        's2': sb.sessionId,
        'ob': r10b?['stripe_checkout_session_id'],
        'url': usa,
      },
    );
  } else if (sa.sessionId == sb.sessionId) {
    c.hold(
      id: 'AH2-SAME-AMT-WRONG-REUSE',
      lens: lens,
      severity: 'P1',
      title: 'Reuse errado mesmo montante linhas diferentes',
      actor: 'buyer JWT',
      pre: '3 SKUs 10€',
      repro: 'bag A+B; bag A+C',
      expected: 'não reuse',
      obtained: sa.sessionId,
    );
  } else {
    c.block('AH2-SAME-AMT-NO-EXPIRE', lens, 'não provou URL+BD', {
      's1': sa.sessionId,
      's2': sb.sessionId,
      'ob': r10b?['stripe_checkout_session_id'],
      'url': usa,
    });
  }
}

Future<void> proveAcceptedBundlePartial(Rtah c) async {
  final lens = 'AH3';
  final p1 = await c.createProduct(price: 12, qty: 1, title: '$prefix-p2-bun1');
  final p2 = await c.createProduct(price: 14, qty: 1, title: '$prefix-p2-bun2');
  if (p1 == null || p2 == null) return;
  final bun = await c.rest('POST', 'product_bundles', jwt: c.sellerJwt, body: {
    'seller_id': c.sellerId,
    'buyer_id': c.buyerId,
    'product_ids': [p1, p2],
    'discount_pct': 10,
    'status': 'pending',
  });
  final bid = bun.firstId;
  if (bid != null) c.createdBundleIds.add(bid);
  c.note('P2.BUN.ins', 'seller cria pending', bun.brief, lens: lens);
  if (bid == null) {
    return c.block('AH3-BUNDLE-PARTIAL', lens, 'seller não criou bundle', bun.brief);
  }
  final acc = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.sellerJwt,
    body: {'status': 'accepted'},
  );
  final row = await c.rest(
    'GET',
    'product_bundles?id=eq.$bid&select=id,status,total_eur,buyer_id,product_ids',
    service: true,
  );
  c.note('P2.BUN.acc', 'seller accept', {
    'patch': acc.brief,
    'row': row.brief,
    'status': row.map?['status'],
    'total': row.map?['total_eur'],
  }, lens: lens);
  final st = (row.map?['status'] ?? '').toString().toLowerCase();
  if (st != 'accepted') {
    return c.block('AH3-BUNDLE-PARTIAL', lens, 'não ficou accepted', row.brief);
  }
  final o1 = await c.insertOrder(
    productId: p1,
    jwt: c.buyerJwt,
    price: 12,
    bundleId: bid,
  );
  final o2 = await c.insertOrder(
    productId: p2,
    jwt: c.buyerJwt,
    price: 14,
    bundleId: bid,
  );
  c.note('P2.BUN.ords', 'orders', {'o1': o1, 'o2': o2}, lens: lens);
  if (o1 == null || o2 == null) {
    return c.block('AH3-BUNDLE-PARTIAL', lens, 'orders bundle falharam', '$o1 $o2');
  }
  final partial = await c.checkoutBag(lines: [bagLine(o1, p1)]);
  final full = await c.checkoutBag(lines: [bagLine(o1, p1), bagLine(o2, p2)]);
  c.note('P2.BUN.ck', 'partial vs full accepted', {
    'partial': partial.brief,
    'full': '${full.ok} amt=${full.amountTotal}',
  }, lens: lens);
  if (partial.ok) {
    c.hold(
      id: 'AH3-BUNDLE-PARTIAL',
      lens: lens,
      severity: 'P1',
      title: 'Conjunto realmente accepted: saco com 1 de 2 SKUs abre Session',
      actor: 'buyer JWT',
      pre: 'seller criou+aceitou bundle 2 SKUs; 2 orders bundle_id',
      repro: 'bag_checkout só order 1',
      expected: 'blocked must include all items',
      obtained: {
        'partial': partial.brief,
        'amt': partial.amountTotal,
        'full_amt': full.amountTotal,
        'bundle_total': row.map?['total_eur'],
      },
    );
  } else {
    c.block('AH3-BUNDLE-PARTIAL', lens, 'parcial accepted bloqueado', partial.brief);
  }
}

Future<void> proveBagRaceDb(Rtah c) async {
  final lens = 'AH6';
  final pa = await c.createProduct(price: 8, qty: 1, title: '$prefix-p2-ra');
  final pb = await c.createProduct(price: 9, qty: 1, title: '$prefix-p2-rb');
  if (pa == null || pb == null) return;
  final oa = await c.insertOrder(productId: pa, jwt: c.buyerJwt, price: 8);
  final ob = await c.insertOrder(productId: pb, jwt: c.buyerJwt, price: 9);
  if (oa == null || ob == null) return;
  final lines = [bagLine(oa, pa), bagLine(ob, pb)];
  final rs = await parallel([
    c.checkoutBag(lines: lines),
    c.checkoutBag(lines: lines),
  ]);
  final sids = rs.map((e) => e.sessionId).whereType<String>().toSet();
  Map<String, Object?> urls = {};
  for (final s in sids) {
    urls[s] = await probeCheckoutUrl(s);
  }
  final ra = await c.orderRow(oa);
  final rb = await c.orderRow(ob);
  c.note('P2.RACE.BAG', 'parallel bag', {
    'unique': sids.length,
    'sids': sids.toList(),
    'oa': ra?['stripe_checkout_session_id'],
    'ob': rb?['stripe_checkout_session_id'],
    'urls': urls,
  }, lens: lens);
  final live = urls.entries
      .where((e) {
        final v = e.value;
        if (v is! Map) return false;
        return v['expired_copy'] != true && ((v['http'] as int?) ?? 0) < 400;
      })
      .length;
  if (sids.length > 1 && live > 1) {
    c.hold(
      id: 'AH6-BAG-RACE-TWO-OPEN',
      lens: lens,
      severity: 'P1',
      title: 'Future.wait 2× bag_checkout emite 2 cs_ com URLs de pagamento vivos',
      actor: 'buyer JWT',
      pre: '2 orders mesmo saco',
      repro: 'Future.wait 2× create-payment-intent bag',
      expected: '1 Session (claim)',
      obtained: {
        'sids': sids.toList(),
        'live_urls': live,
        'oa': ra?['stripe_checkout_session_id'],
        'ob': rb?['stripe_checkout_session_id'],
        'urls': urls,
      },
    );
  } else if (sids.length > 1) {
    c.hold(
      id: 'AH6-BAG-RACE-TWO-OPEN',
      lens: lens,
      severity: 'P2',
      title: 'Bag paralelo cria 2 cs_ (URL live não confirmado em ambas)',
      actor: 'buyer JWT',
      pre: '2 orders',
      repro: 'Future.wait 2× bag',
      expected: '1 cs_',
      obtained: {'sids': sids.toList(), 'urls': urls, 'live': live},
    );
  } else {
    c.block('AH6-BAG-RACE-TWO-OPEN', lens, '1 session', sids.toList());
  }
}
