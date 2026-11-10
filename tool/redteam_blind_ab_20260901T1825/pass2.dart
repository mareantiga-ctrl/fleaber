/// RED TEAM CEGO AB pass2 — confirmar currency + bag reuse amount. Não corrige.
library;

import 'dart:io';

import '_rtab.dart';

Future<void> main() async {
  final c = Rtab.fromEnv(loadEnv());
  stdout.writeln('RTAB pass2 $stamp ${c.url}');
  await c.loginActors();
  await c.ensureBuyer2();

  await confirmUsd(c);
  await confirmJpyFresh(c);
  await confirmGbpFresh(c);
  await poisonUsdThenEur(c);
  await bagReuseAmount(c);
  await bagReuseCheapThenExpensivePayDelta(c);

  await dumpJson('${outDir()}/pass2.json', {
    'stamp': stamp,
    'pass': 2,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln('PASS2 findings=${c.findings.length} lenses=${c.lensesHit}');
  await c.cleanup();
}

Map<String, Object?> extractCurrency(String html) {
  final found = <String>{};
  for (final m in RegExp(r'"currency"\s*:\s*"([a-zA-Z]+)"').allMatches(html)) {
    found.add(m.group(1)!.toLowerCase());
  }
  for (final m in RegExp(r'"currencyCode"\s*:\s*"([a-zA-Z]+)"').allMatches(html)) {
    found.add(m.group(1)!.toLowerCase());
  }
  final amt = <String>[];
  for (final m in RegExp(r'"amount_total"\s*:\s*(\d+)').allMatches(html)) {
    amt.add(m.group(1)!);
  }
  final display = <String>[];
  for (final m in RegExp(r'\$[\d.,]+|€[\d.,]+|¥[\d.,]+|£[\d.,]+').allMatches(html)) {
    display.add(m.group(0)!);
    if (display.length >= 8) break;
  }
  return {
    'currency_json': found.toList()..sort(),
    'amount_total_hits': amt.take(6).toList(),
    'money_display': display,
    'len': html.length,
  };
}

Future<void> confirmUsd(Rtab c) async {
  final sku = await c.createProduct(title: '$prefix p2usd', qty: 2, price: 17);
  if (sku == null) return;
  final oid = await c.insertOrder(productId: sku, jwt: c.buyerJwt, qty: 1, price: 17);
  if (oid == null) return;
  final q = await c.checkout(orderId: oid, currency: 'usd');
  c.note('p2.usd.edge', 'fresh usd', {
    'ok': q.ok,
    'sid': q.checkoutSessionId,
    'server': q.serverAmount,
    'amount_total': q.map?['amount_total'],
    'reused': q.map?['reused_session'],
  }, lens: 'AB3');
  if (!q.ok || q.checkoutUrl == null) {
    c.closedPath('P2.usd', 'usd recusado', q, lens: 'AB3');
    return;
  }
  final html = await c.peekCheckoutPage(q.checkoutUrl!);
  final ex = extractCurrency(html);
  c.note('p2.usd.extract', 'currency json na página', ex, lens: 'AB3');
  final codes = (ex['currency_json'] as List).cast<String>();
  final usdOnly = codes.contains('usd') && !codes.contains('eur');
  final usdPresent = codes.contains('usd');
  if (q.ok && (usdOnly || usdPresent)) {
    c.hold(
      id: 'RTAB-AB3-currency-usd',
      lens: 'AB3',
      severity: 'P0',
      title: 'Checkout Session Stripe em USD (body.currency sem allowlist)',
      actor: 'buyer JWT',
      pre: 'order marketplace selada em EUR',
      repro: 'POST create-payment-intent currency=usd (1ª Session da order)',
      expected: 'currency=eur obrigatório',
      obtained: {
        'sid': q.checkoutSessionId,
        'server_amount_cents': q.serverAmount,
        'amount_total': q.map?['amount_total'],
        'page': ex,
      },
    );
  } else {
    c.closedPath('P2.usd_not_in_page', 'página sem prova USD', ex, lens: 'AB3');
  }
}

Future<void> confirmJpyFresh(Rtab c) async {
  final sku = await c.createProduct(title: '$prefix p2jpy', qty: 2, price: 17);
  if (sku == null) return;
  final oid = await c.insertOrder(productId: sku, jwt: c.buyerJwt, qty: 1, price: 17);
  if (oid == null) return;
  final q = await c.checkout(orderId: oid, currency: 'jpy');
  c.note('p2.jpy.edge', 'fresh jpy', {
    'ok': q.ok,
    'sid': q.checkoutSessionId,
    'server': q.serverAmount,
    'amount_total': q.map?['amount_total'],
    'reused': q.map?['reused_session'],
  }, lens: 'AB3');
  if (!q.ok) {
    c.closedPath('P2.jpy', 'jpy recusado', q, lens: 'AB3');
    return;
  }
  String? pageInfo;
  if (q.checkoutUrl != null) {
    final html = await c.peekCheckoutPage(q.checkoutUrl!);
    final ex = extractCurrency(html);
    c.note('p2.jpy.extract', 'jpy page', ex, lens: 'AB3');
    pageInfo = jsonish(ex);
  }
  c.hold(
    id: 'RTAB-AB3-currency-jpy',
    lens: 'AB3',
    severity: 'P0',
    title: 'Checkout Session aceite com currency=jpy (zero-decimal)',
    actor: 'buyer JWT',
    pre: 'order nova sem Session prévia',
    repro: 'POST create-payment-intent currency=jpy',
    expected: 'recusar',
    obtained: {
      'sid': q.checkoutSessionId,
      'server': q.serverAmount,
      'amount_total': q.map?['amount_total'],
      'page': pageInfo,
    },
  );
}

Future<void> confirmGbpFresh(Rtab c) async {
  final sku = await c.createProduct(title: '$prefix p2gbp', qty: 2, price: 17);
  if (sku == null) return;
  final oid = await c.insertOrder(productId: sku, jwt: c.buyerJwt, qty: 1, price: 17);
  if (oid == null) return;
  final q = await c.checkout(orderId: oid, currency: 'gbp');
  c.note('p2.gbp', 'fresh gbp', {
    'ok': q.ok,
    'sid': q.checkoutSessionId,
    'amount_total': q.map?['amount_total'],
  }, lens: 'AB3');
  if (q.ok) {
    Map<String, Object?>? ex;
    if (q.checkoutUrl != null) {
      ex = extractCurrency(await c.peekCheckoutPage(q.checkoutUrl!));
      c.note('p2.gbp.extract', 'gbp page', ex, lens: 'AB3');
    }
    c.hold(
      id: 'RTAB-AB3-currency-gbp',
      lens: 'AB3',
      severity: 'P0',
      title: 'Checkout Session aceite com currency=gbp',
      actor: 'buyer JWT',
      pre: 'order nova',
      repro: 'currency=gbp',
      expected: 'recusar / forçar eur',
      obtained: {
        'sid': q.checkoutSessionId,
        'amount_total': q.map?['amount_total'],
        'page': ex,
      },
    );
  } else {
    c.closedPath('P2.gbp', 'gbp recusado', q, lens: 'AB3');
  }
}

Future<void> poisonUsdThenEur(Rtab c) async {
  final sku = await c.createProduct(title: '$prefix p2poison', qty: 2, price: 18);
  if (sku == null) return;
  final oid = await c.insertOrder(productId: sku, jwt: c.buyerJwt, qty: 1, price: 18);
  if (oid == null) return;
  final usd = await c.checkout(orderId: oid, currency: 'usd');
  final eur = await c.checkout(orderId: oid, currency: 'eur');
  c.note('p2.poison', 'usd depois eur', {
    'usd_sid': usd.checkoutSessionId,
    'eur_sid': eur.checkoutSessionId,
    'usd_reused': usd.map?['reused_session'],
    'eur_reused': eur.map?['reused_session'],
    'same': usd.checkoutSessionId != null &&
        usd.checkoutSessionId == eur.checkoutSessionId,
    'usd_amt': usd.map?['amount_total'],
    'eur_amt': eur.map?['amount_total'],
  }, lens: 'AB3');
  if (usd.ok &&
      eur.ok &&
      usd.checkoutSessionId != null &&
      usd.checkoutSessionId == eur.checkoutSessionId) {
    Map<String, Object?>? page;
    if (eur.checkoutUrl != null) {
      page = extractCurrency(await c.peekCheckoutPage(eur.checkoutUrl!));
    }
    c.hold(
      id: 'RTAB-AB3-usd-poisons-eur-reuse',
      lens: 'AB3',
      severity: 'P0',
      title: '1ª Session USD é reutilizada no 2º POST currency=eur',
      actor: 'buyer JWT',
      pre: 'order sem cs_; POST usd; POST eur',
      repro: 'checkout currency=usd → checkout currency=eur (mesmo amount)',
      expected: '2ª chamada cria Session EUR ou recusa reuse se currency ≠ eur',
      obtained: {
        'sid': usd.checkoutSessionId,
        'eur_reused': eur.map?['reused_session'],
        'page': page,
      },
    );
  }
}

Future<void> bagReuseAmount(Rtab c) async {
  final a = await c.createProduct(title: '$prefix p2ba', qty: 4, price: 20);
  final b = await c.createProduct(title: '$prefix p2bb', qty: 4, price: 24);
  final e = await c.createProduct(title: '$prefix p2be', qty: 4, price: 40);
  if (a == null || b == null || e == null) return;
  final oA = await c.insertOrder(productId: a, jwt: c.buyerJwt, qty: 1, price: 20);
  final oB = await c.insertOrder(productId: b, jwt: c.buyerJwt, qty: 1, price: 24);
  final oE = await c.insertOrder(productId: e, jwt: c.buyerJwt, qty: 1, price: 40);
  if (oA == null || oB == null || oE == null) return;

  final q2 = await c.checkoutBag(lines: [
    {'order_id': oA, 'product_id': a},
    {'order_id': oB, 'product_id': b},
  ]);
  final q3 = await c.checkoutBag(lines: [
    {'order_id': oA, 'product_id': a},
    {'order_id': oB, 'product_id': b},
    {'order_id': oE, 'product_id': e},
  ]);
  c.note('p2.bag', 'reuse amount fields', {
    'q2': {
      'sid': q2.checkoutSessionId,
      'server': q2.serverAmount,
      'amount_total': q2.map?['amount_total'],
      'reused': q2.map?['reused_session'],
    },
    'q3': {
      'sid': q3.checkoutSessionId,
      'server': q3.serverAmount,
      'amount_total': q3.map?['amount_total'],
      'reused': q3.map?['reused_session'],
    },
  }, lens: 'AB3');

  if (q2.ok &&
      q3.ok &&
      q2.checkoutSessionId == q3.checkoutSessionId &&
      q2.checkoutSessionId != null) {
    final stripeAmt = numOf(q3.map?['amount_total']) ?? 0;
    final advertised = q3.serverAmount ?? 0;
    c.hold(
      id: 'RTAB-AB3-bag-reuse-no-amount-check',
      lens: 'AB3',
      severity: 'P1',
      title: 'Saco: reuse Session ignora amount_total (2 SKUs vs 3)',
      actor: 'buyer JWT',
      pre: 'Session aberta A+B; 2º POST A+B+E',
      repro: 'bag 2 linhas → bag 3 linhas overlap',
      expected: 'nova Session se o quote mudou, ou recusar',
      obtained: {
        'sid': q2.checkoutSessionId,
        'stripe_amount_total_q3': stripeAmt,
        'server_amount_cents_q3': advertised,
        'q2_server': q2.serverAmount,
        'same_sid': true,
        'reused': q3.map?['reused_session'],
      },
    );
  }
}

Future<void> bagReuseCheapThenExpensivePayDelta(Rtab c) async {
  // Composição: se pagar a Session dos 2 SKUs, o 3º não deve liquidar.
  // Observação: não pagamos a Session hostil; só documentamos o delta.
  c.note('p2.ab8.note', 'não completar pagamento da Session reuse (Stripe TEST)',
      'webhook settle usa metadata da Session original (2 linhas), não o 2º bag',
      lens: 'AB8');
}

String jsonish(Object? v) {
  if (v is Map || v is List) return v.toString();
  return '$v';
}
