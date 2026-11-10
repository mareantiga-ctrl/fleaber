/// RED TEAM CEGO CD pass1 — marketplace / saco / checkout pós-BXCC.
/// Variantes novas: 4+ lines, crash mid-claim, overlap parcial ≠ triângulo,
/// encoding amount, offer freeze, unlist∥checkout, FSM MB WAY, caixa.
import 'dart:io';

import '_rtcd.dart';

Future<void> main() async {
  final c = Rtcd.fromEnv(loadEnv());
  stdout.writeln('CD pass1 staging=${c.url} prefix=$prefix');
  if (c.stripeTestKey == null) {
    stdout.writeln('WARN no sk_test_ — Stripe retrieve/expire/list limitado');
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
  c.note('CD8.wallet.pre', 'baseline', wallets0, lens: 'CD8', well: 'CD-E');

  await cdALockSessions(c);
  await cdBPriceEncoding(c);
  await cdCStockOversell(c);
  await cdDFsmMbway(c);
  await cdECaixa(c, wallets0);

  // Controlo: compra single-item legítima ainda abre Session.
  await cdControlLegitSingle(c);

  final wallets1 = await c.wallets();
  c.note('CD8.wallet.post', 'após probes', {
    'pre': wallets0,
    'post': wallets1,
  }, lens: 'CD8', well: 'CD-E');

  await c.dumpAll('pass1_findings.json');
  stdout.writeln(
    'DONE findings=${c.findings.length} blocked=${c.blocked.length} '
    'notes=${c.notes.length} lenses=${c.lensesHit.toList()..sort()} '
    'wells=${c.wellsTried.toList()..sort()}',
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
  Rtcd c, {
  required int n,
  required String tag,
  int qty = 3,
  double price = 12,
  String? buyer,
  String? jwt,
}) async {
  final out = <({String oid, String pid, double price})>[];
  for (var i = 0; i < n; i++) {
    final p = price + i;
    final pid = await c.createProduct(
      title: '$prefix-$tag-$i',
      qty: qty,
      price: p,
    );
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

Set<String> openCs(List<HttpHit> hits) {
  return hits
      .map((h) => h.sessionId ?? '')
      .where((s) => s.startsWith('cs_'))
      .toSet();
}

Future<int> openPayableCount(Rtcd c, Iterable<String> sids) async {
  var n = 0;
  for (final sid in sids) {
    final s = await c.stripeSession(sid);
    final st = '${s.map?['status']}';
    final pay = '${s.map?['payment_status']}';
    if (st == 'open' && pay != 'paid' && (s.map?['url'] != null)) n++;
  }
  return n;
}

/// POÇO CD-A — LOCK / SESSIONS
Future<void> cdALockSessions(Rtcd c) async {
  c.wellsTried.add('CD-A');

  // A.1 residual bag∥single mesma order (NÃO contar se fail clássico)
  final residual = await mkSkus(c, n: 1, tag: 'a1-bagsingle', qty: 2);
  if (residual.length == 1) {
    final r = residual.first;
    final hits = await parallel([
      c.checkoutBag(lines: bagLines([r]), amount: 1),
      c.checkout(orderId: r.oid, productId: r.pid, amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    final sids = openCs(hits);
    final payable = await openPayableCount(c, sids);
    c.note('A1.bagsingle', 'bag∥single residual', {
      'sids': sids.toList(),
      'statuses': hits.map((h) => h.brief).toList(),
      'open_payable': payable,
    }, lens: 'CD2', well: 'CD-A');
    if (payable >= 2) {
      c.hold(
        id: 'P0-RESIDUAL-BAG-SINGLE',
        lens: 'CD2',
        severity: 'P0',
        title: 'RESIDUAL bag∥single: 2 Sessions open pagáveis',
        actor: 'buyer JWT',
        pre: '1 order marketplace',
        repro: 'Future.wait bag_checkout ∥ create-payment-intent single',
        expected: '≤1 cs_ open',
        obtained: {'sids': sids.toList(), 'open_payable': payable},
      );
    } else {
      c.block('A1-BAG-SINGLE', 'CD2', 'bag∥single ≤1 Session (residual fechado)', {
        'sids': sids.toList(),
        'payable': payable,
      });
    }
  }

  // A.2 4+ lines → 1 claim / N Sessions?
  final five = await mkSkus(c, n: 5, tag: 'a2-five', qty: 2, price: 8);
  if (five.length == 5) {
    final lines = bagLines(five);
    final hits = await parallel([
      c.checkoutBag(lines: lines, amount: 1),
      c.checkoutBag(lines: lines, amount: 1),
      c.checkoutBag(lines: lines, amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    final sids = openCs(hits);
    final payable = await openPayableCount(c, sids);
    c.note('A2.five', '5-line bag ×3 paralelo', {
      'sids': sids.toList(),
      'open_payable': payable,
      'briefs': hits.map((h) => h.brief).toList(),
    }, lens: 'CD2', well: 'CD-A');
    if (payable >= 2) {
      c.hold(
        id: 'P0-1',
        lens: 'CD2',
        severity: 'P0',
        title: 'Saco 5 linhas: 2+ Sessions open pagáveis no mesmo claim',
        actor: 'buyer JWT',
        pre: '5 orders mesmo seller',
        repro: 'Future.wait 3× bag_checkout 5 lines',
        expected: '1 cs_ open',
        obtained: {'sids': sids.toList(), 'open_payable': payable},
      );
    } else {
      c.block('A2-FIVE-LINES', 'CD2', '5-line bag 3× paralelo ≤1 Session', {
        'sids': sids.toList(),
        'payable': payable,
      });
    }
  }

  // A.3 crash mid-claim: timeout cliente + 2.º POST; + claiming: stuck fixture
  final crash = await mkSkus(c, n: 2, tag: 'a3-crash', qty: 2);
  if (crash.length == 2) {
    final lines = bagLines(crash);
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
    final rows = <Map<String, dynamic>?>[
      await c.orderRow(crash[0].oid),
      await c.orderRow(crash[1].oid),
    ];
    final stored = rows
        .map((r) => '${r?['stripe_checkout_session_id'] ?? ''}')
        .toList();
    final sids = {
      ...openCs(pair),
      ...stored.where((s) => s.startsWith('cs_')),
    };
    final payable = await openPayableCount(c, sids);
    c.note('A3.timeout', 'crash mid-claim timeout∥retry', {
      'hits': pair.map((h) => h.brief).toList(),
      'stored': stored,
      'sids': sids.toList(),
      'open_payable': payable,
    }, lens: 'CD2', well: 'CD-A');
    if (payable >= 2) {
      c.hold(
        id: 'P0-2',
        lens: 'CD2',
        severity: 'P0',
        title: 'Crash mid-claim (timeout cliente) deixou 2 cs_ open',
        actor: 'buyer JWT',
        pre: '2-line bag; 1.º POST timeout 250ms; 2.º retry',
        repro: 'checkoutBag timeout∥checkoutBag',
        expected: '≤1 cs_ open',
        obtained: {'sids': sids.toList(), 'stored': stored, 'payable': payable},
      );
    } else {
      c.block('A3-TIMEOUT-RETRY', 'CD2', 'timeout∥retry ≤1 Session', {
        'sids': sids.toList(),
        'payable': payable,
        'stored': stored,
      });
    }
  }

  // A.3b claiming: órfão (simula crash após lock, antes de cs_)
  final stuck = await mkSkus(c, n: 1, tag: 'a3-stuck', qty: 2);
  if (stuck.length == 1) {
    final token = 'claiming:deadbeefcafebabe';
    await c.rest(
      'PATCH',
      'orders?id=eq.${stuck.first.oid}',
      service: true,
      body: {'stripe_checkout_session_id': token},
      prefer: 'return=minimal',
    );
    final hit = await c.checkout(
      orderId: stuck.first.oid,
      productId: stuck.first.pid,
      amount: 1,
    );
    c.trackSession(hit);
    final after = await c.orderRow(stuck.first.oid);
    final sid = '${after?['stripe_checkout_session_id'] ?? ''}';
    c.note('A3.stuck', 'claiming: órfão + CPI', {
      'hit': hit.brief,
      'stored': sid,
    }, lens: 'CD2', well: 'CD-A');
    if (hit.ok && (hit.sessionId ?? '').startsWith('cs_') && sid.startsWith('cs_')) {
      c.block('A3-STUCK-RECLAIM', 'CD2', 'claiming órfão foi reclamado (esperado ou wait)', {
        'hit': hit.brief,
        'stored': sid,
      });
    } else if (!hit.ok && sid.startsWith('claiming:')) {
      c.hold(
        id: 'P2-1',
        lens: 'CD2',
        severity: 'P2',
        title: 'claiming: órfão bloqueia checkout para sempre (DoS)',
        actor: 'buyer JWT (fixture claiming: via service observação)',
        pre: 'order.stripe_checkout_session_id=claiming:deadbeef…',
        repro: 'POST create-payment-intent após crash simulado',
        expected: 'reclaim ou expire do slot claiming:',
        obtained: {'hit': hit.brief, 'stored': sid},
      );
    } else {
      c.block('A3-STUCK-CLAIM', 'CD2', 'claiming órfão não criou dual Session', {
        'hit': hit.brief,
        'stored': sid,
      });
    }
  }

  // A.4 overlap parcial 5-line vs 3-line partilhando 2 SKUs (≠ triângulo AB∥AC)
  final pool = await mkSkus(c, n: 6, tag: 'a4-overlap', qty: 2, price: 9);
  if (pool.length == 6) {
    final bagBig = pool.sublist(0, 5);
    final bagPart = [pool[3], pool[4], pool[5]]; // C,D,E de ABCDE vs DEF — 2 partilhados
    final hits = await parallel([
      c.checkoutBag(lines: bagLines(bagBig), amount: 1),
      c.checkoutBag(lines: bagLines(bagPart), amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    final sids = openCs(hits);
    final payable = await openPayableCount(c, sids);
    c.note('A4.partial', 'bag 5-line ∥ bag 3-line overlap 2 SKUs', {
      'sids': sids.toList(),
      'open_payable': payable,
      'briefs': hits.map((h) => h.brief).toList(),
    }, lens: 'CD2', well: 'CD-A');
    if (payable >= 2) {
      c.hold(
        id: 'P0-3',
        lens: 'CD2',
        severity: 'P0',
        title: 'Overlap parcial 5∥3 (2 SKUs partilhados): 2 Sessions pagáveis',
        actor: 'buyer JWT',
        pre: '6 SKUs; bag ABCDE ∥ bag DEF',
        repro: 'Future.wait 2× bag_checkout overlap parcial',
        expected: '≤1 cs_ open (expire intersect)',
        obtained: {'sids': sids.toList(), 'open_payable': payable},
      );
    } else {
      c.block('A4-PARTIAL-OVERLAP', 'CD2', 'overlap 5∥3 ≤1 Session pagável', {
        'sids': sids.toList(),
        'payable': payable,
      });
    }
  }

  // A.5 metadata drift pós-claim: PATCH qty/price com Session open
  final drift = await mkSkus(c, n: 1, tag: 'a5-drift', qty: 5, price: 15);
  if (drift.length == 1) {
    final d = drift.first;
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
    c.note('A5.drift', 'PATCH qty/price com Session open', {
      'ck0': ck.brief,
      'patchQty': patchQty.brief,
      'patchPrice': patchPrice.brief,
      'ck2': ck2.brief,
      'amt0': amt0,
      'amt1': amt1,
      'contract': row?['contract_unit_cents'],
      'qty': row?['quantity'],
    }, lens: 'CD1', well: 'CD-A');
    if (ck.ok && ck2.ok && amt0 != null && amt1 != null && amt1 < amt0 - 50) {
      c.hold(
        id: 'P0-4',
        lens: 'CD1',
        severity: 'P0',
        title: 'Drift qty/price pós-claim baixou amount_total da Session',
        actor: 'buyer JWT + seller JWT',
        pre: 'Session open; PATCH order.quantity + product.price',
        repro: 'POST CPI; PATCH; POST CPI',
        expected: 'amount_total estável (contrato selado)',
        obtained: {'amt0': amt0, 'amt1': amt1, 'ck2': ck2.brief},
      );
    } else {
      c.block('A5-DRIFT', 'CD1', 'drift pós-claim não baixou Session', {
        'amt0': amt0,
        'amt1': amt1,
        'patchQty': patchQty.status,
        'patchPrice': patchPrice.status,
      });
    }
  }

  // A.6 list Stripe Sessions órfãs (order sem PI / 2 PI 1 order)
  if (c.stripeTestKey != null) {
    final listed = await c.stripeListSessions(limit: 40);
    final ours = <Map<String, dynamic>>[];
    for (final item in listed.list.isNotEmpty
        ? listed.list
        : ((listed.map?['data'] as List?) ?? const [])) {
      if (item is! Map) continue;
      final meta = item['metadata'];
      final created = item['created'];
      ours.add({
        'id': item['id'],
        'status': item['status'],
        'payment_status': item['payment_status'],
        'amount_total': item['amount_total'],
        'pi': item['payment_intent'],
        'meta_order': meta is Map ? meta['order_id'] ?? meta['fleaber_order_id'] : null,
        'created': created,
      });
    }
    final byOrder = <String, List<String>>{};
    for (final oid in c.createdOrderIds) {
      final row = await c.orderRow(oid);
      final sid = '${row?['stripe_checkout_session_id'] ?? ''}';
      final pi = '${row?['stripe_payment_intent_id'] ?? ''}';
      if (sid.startsWith('cs_')) {
        byOrder.putIfAbsent(oid, () => []).add(sid);
      }
      if (sid.startsWith('cs_') && pi.isEmpty) {
        c.note('A6.order-no-pi', 'order com cs_ sem PI', {
          'oid': oid,
          'sid': sid,
          'status': row?['status'],
        }, lens: 'CD2', well: 'CD-A');
      }
    }
    final dual = byOrder.entries.where((e) => e.value.toSet().length > 1).toList();
    c.note('A6.orphan-list', 'Stripe sessions recentes + orders fixture', {
      'stripe_n': ours.length,
      'dual_sid_orders': dual.map((e) => {'oid': e.key, 'sids': e.value}).toList(),
    }, lens: 'CD2', well: 'CD-A');
    if (dual.isNotEmpty) {
      c.hold(
        id: 'P1-1',
        lens: 'CD2',
        severity: 'P1',
        title: '1 order com 2 stripe_checkout_session_id distintos no ledger',
        actor: 'observação',
        pre: 'após matriz A',
        repro: 'SELECT orders.stripe_checkout_session_id',
        expected: '1 sid / order',
        obtained: dual.map((e) => {'oid': e.key, 'sids': e.value}).toList(),
      );
    } else {
      c.block('A6-ORPHAN-LIST', 'CD2', 'sem 2 sid por order no ledger fixture', {
        'n_orders': c.createdOrderIds.length,
      });
    }
  } else {
    c.skip('A6.orphan', 'CD2', 'sem sk_test_ para list Sessions', 'no_sk_test');
  }
}

/// POÇO CD-B — PREÇO / CURRENCY / ENCODING
Future<void> cdBPriceEncoding(Rtcd c) async {
  c.wellsTried.add('CD-B');
  final sku = await mkSkus(c, n: 1, tag: 'b-enc', qty: 2, price: 12);
  if (sku.isEmpty) return;
  final o = sku.first;

  final encodings = <String, Object?>{
    'zwj_eur': 'eu\u200Dr',
    'bidi_eur': '\u202Eeur',
    'fullwidth_eur': 'ｅｕｒ',
    'nbsp_amount': '1\u00A000',
    'fullwidth_amount': '１２',
    'zwj_amount': '1\u200B2',
    'bidi_amount': '\u202E21',
  };
  for (final e in encodings.entries) {
    final hit = e.key.contains('amount')
        ? await c.checkout(
            orderId: o.oid,
            productId: o.pid,
            amount: e.value,
            currency: 'eur',
          )
        : await c.checkout(
            orderId: o.oid,
            productId: o.pid,
            amount: 1,
            currency: e.value,
          );
    c.trackSession(hit);
    final amt = hit.amountTotal;
    c.note('B1.${e.key}', 'encoding $e.key', {
      'hit': hit.brief,
      'amt': amt,
    }, lens: 'CD1', well: 'CD-B');
    if (hit.ok && amt != null && amt < 500) {
      c.hold(
        id: 'P0-5',
        lens: 'CD1',
        severity: 'P0',
        title: 'Encoding ${e.key} criou Session abaixo do contrato (≥12€)',
        actor: 'buyer JWT',
        pre: 'SKU 12€',
        repro: 'POST create-payment-intent ${e.key}=${e.value}',
        expected: 'bloquear non-EUR / ignorar amount hostil; Session ≥1200¢',
        obtained: {'amt': amt, 'hit': hit.brief},
      );
    } else if (!hit.ok && e.key.contains('eur')) {
      c.block('B1-${e.key}', 'CD1', 'currency hostil rejeitada', hit.brief);
    } else {
      c.block('B1-${e.key}', 'CD1', 'encoding não baixou amount_total', {
        'amt': amt,
        'status': hit.status,
      });
    }
  }

  // B.2 portes / desconto / bundle vs amount_total
  final b2 = await mkSkus(c, n: 3, tag: 'b2-bundle', qty: 2, price: 10);
  if (b2.length == 3) {
    final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'status': 'pending',
      'subtotal_eur': 30,
      'discount_pct': 50,
      'total_eur': 1,
    });
    final bid = bun.firstId;
    if (bid != null) c.createdBundleIds.add(bid);
    if (bid != null) {
      await c.rest(
        'PATCH',
        'product_bundles?id=eq.$bid',
        jwt: c.sellerJwt,
        body: {'status': 'accepted', 'total_eur': 1, 'discount_pct': 90},
      );
      for (final row in b2) {
        await c.rest(
          'PATCH',
          'orders?id=eq.${row.oid}',
          jwt: c.buyerJwt,
          body: {'bundle_id': bid},
        );
      }
    }
    final shipCtt = await c.checkoutBag(
      lines: bagLines(b2),
      amount: 1,
      shipping: 'ctt',
    );
    c.trackSession(shipCtt);
    final shipMao = await c.checkoutBag(
      lines: bagLines(b2),
      amount: 1,
      shipping: 'mao',
    );
    c.trackSession(shipMao);
    c.note('B2.portes-bundle', 'portes CTT vs mão + bundle total_eur=1', {
      'bundle': bun.brief,
      'ctt': shipCtt.brief,
      'mao': shipMao.brief,
      'ctt_amt': shipCtt.amountTotal,
      'mao_amt': shipMao.amountTotal,
    }, lens: 'CD3', well: 'CD-B');
    final catalogCents = 10 * 100 * 3; // 30€ items; portes CTT > mão
    if (shipCtt.ok &&
        shipCtt.amountTotal != null &&
        shipCtt.amountTotal! < 500) {
      c.hold(
        id: 'P0-6',
        lens: 'CD3',
        severity: 'P0',
        title: 'Bundle total_eur=1 / portes reflectidos na Session abaixo do catálogo',
        actor: 'buyer JWT',
        pre: '3 SKUs 10€; bundle PATCH total_eur=1',
        repro: 'POST bag_checkout shipping=ctt',
        expected: 'quote servidor (catálogo ± portes), não total_eur hostil',
        obtained: {
          'amt': shipCtt.amountTotal,
          'catalog_items_cents': catalogCents,
        },
      );
    } else {
      c.block('B2-BUNDLE-PORTES', 'CD3', 'Session não usou total_eur=1 hostil', {
        'ctt': shipCtt.amountTotal,
        'mao': shipMao.amountTotal,
      });
    }
  }

  // B.3 offer aceite → freeze Unicode no amount
  final offSku = await c.createProduct(title: '$prefix-b3-offer', price: 20, qty: 2);
  if (offSku != null) {
    final ins = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
      'product_id': offSku,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'amount': '８.００',
      'list_price': 20,
      'offered_by': 'buyer',
      'status': 'pending',
    });
    final ins2 = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
      'product_id': offSku,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'amount': 8,
      'list_price': 20,
      'offered_by': 'buyer',
      'status': 'pending',
    });
    final oidOffer = ins.firstId ?? ins2.firstId;
    if (oidOffer != null) c.createdOfferIds.add(oidOffer);
    c.note('B3.offer-ins', 'POST offer unicode/numeric', {
      'unicode': ins.brief,
      'numeric': ins2.brief,
    }, lens: 'CD3', well: 'CD-B');
    if (oidOffer != null) {
      final acc = await c.rest(
        'PATCH',
        'product_offers?id=eq.$oidOffer',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
      final order = await c.insertOrder(
        productId: offSku,
        price: 8,
        offerId: oidOffer,
        jwt: c.buyerJwt,
      );
      if (order != null) {
        final ck = await c.checkout(orderId: order, productId: offSku, amount: 1);
        c.trackSession(ck);
        c.note('B3.offer-ck', 'checkout após offer aceite', {
          'acc': acc.brief,
          'ck': ck.brief,
          'amt': ck.amountTotal,
        }, lens: 'CD3', well: 'CD-B');
        if (ck.ok && ck.amountTotal != null && ck.amountTotal! < 700) {
          // 8€ offer is legitimate if accepted — only finding if unicode collapsed to <<8
          if (ins.ok && ck.amountTotal! < 200) {
            c.hold(
              id: 'P1-2',
              lens: 'CD3',
              severity: 'P1',
              title: 'Offer Unicode freeze → Session << 8€',
              actor: 'buyer JWT',
              pre: 'offer amount fullwidth ８.００ aceite',
              repro: 'POST product_offers amount=８.００; accept; CPI',
              expected: 'rejeitar unicode ou freeze 8.00€',
              obtained: {'amt': ck.amountTotal, 'ins': ins.brief},
            );
          } else {
            c.block('B3-OFFER-8EUR', 'CD3', 'Session no freeze 8€ (oferta negociada)', {
              'amt': ck.amountTotal,
            });
          }
        } else {
          c.block('B3-OFFER-CATALOG', 'CD3', 'checkout usou catálogo ou bloqueou', {
            'amt': ck.amountTotal,
            'status': ck.status,
          });
        }
      }
    }
  }

  // B.4 ensure_checkout_product hostil (buyer JWT / anon)
  final fakeLi = '00000000-0000-4000-8000-000000000001';
  final buyHit = await c.rpc('batata_ensure_checkout_product', {
    'p_live_item_id': fakeLi,
  }, jwt: c.buyerJwt);
  final anonHit = await c.rpc('batata_ensure_checkout_product', {
    'p_live_item_id': fakeLi,
  });
  c.note('B4.ensure', 'ensure_checkout_product buyer/anon', {
    'buyer': buyHit.brief,
    'anon': anonHit.brief,
  }, lens: 'CD1', well: 'CD-B');
  if (buyHit.ok && buyHit.map?['ok'] == true) {
    c.hold(
      id: 'P1-3',
      lens: 'CD1',
      severity: 'P1',
      title: 'buyer JWT executa ensure_checkout_product (não seller da live)',
      actor: 'buyer JWT',
      pre: 'live_item fake',
      repro: 'POST rpc batata_ensure_checkout_product',
      expected: 'not_allowed / 403',
      obtained: buyHit.brief,
    );
  } else {
    c.block('B4-ENSURE-BUYER', 'CD1', 'buyer não cria checkout product', buyHit.brief);
  }
  if (anonHit.ok) {
    c.hold(
      id: 'P1-4',
      lens: 'CD1',
      severity: 'P1',
      title: 'anon executa ensure_checkout_product',
      actor: 'anon',
      pre: 'sem JWT',
      repro: 'POST rpc batata_ensure_checkout_product anon',
      expected: '403/401',
      obtained: anonHit.brief,
    );
  } else {
    c.block('B4-ENSURE-ANON', 'CD1', 'anon bloqueado', anonHit.brief);
  }
}

/// POÇO CD-C — STOCK / OVERSELL / UNLIST
Future<void> cdCStockOversell(Rtcd c) async {
  c.wellsTried.add('CD-C');

  // C.1 race 2 buyers última unidade
  final pid = await c.createProduct(title: '$prefix-c1-last', qty: 1, price: 11);
  if (pid != null) {
    final o1 = await c.insertOrder(
      productId: pid,
      price: 11,
      jwt: c.buyerJwt,
    );
    final o2 = await c.insertOrder(
      productId: pid,
      price: 11,
      buyer: c.buyer2Id,
      jwt: c.buyer2Jwt,
    );
    if (o1 != null && o2 != null) {
      final hits = await parallel([
        c.checkout(orderId: o1, productId: pid, amount: 1, jwt: c.buyerJwt, buyer: c.buyerId),
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
      c.note('C1.last-unit', '2 buyers última unidade', {
        'ok': ok,
        'briefs': hits.map((h) => h.brief).toList(),
      }, lens: 'CD6', well: 'CD-C');
      if (ok >= 2) {
        c.hold(
          id: 'P0-7',
          lens: 'CD5',
          severity: 'P0',
          title: '2 buyers abriram Session na última unidade',
          actor: 'buyer JWT + buyer2 JWT',
          pre: 'product.quantity=1; 2 orders',
          repro: 'Future.wait 2× create-payment-intent',
          expected: '1 Session + 1 bloqueio stock',
          obtained: hits.map((h) => h.brief).toList(),
        );
      } else {
        c.block('C1-LAST-UNIT', 'CD5', 'race última unidade: ≤1 Session', {
          'ok': ok,
        });
      }
    }
  }

  // C.2 checkout ∥ unlist
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
    final ck = hits[0];
    final prod = await c.productRow(u.pid);
    c.note('C2.unlist', 'checkout ∥ list_on_marketplace=false', {
      'ck': ck.brief,
      'listed': prod?['list_on_marketplace'],
    }, lens: 'CD5', well: 'CD-C');
    if (ck.ok && prod?['list_on_marketplace'] == false) {
      c.block(
        'C2-UNLIST-RACE',
        'CD5',
        'unlist paralelo: Session pode ter ganho a corrida (stock ainda listado no quote)',
        {'ck': ck.brief, 'listed': prod?['list_on_marketplace']},
      );
      // Não é P0 se o quote leu listed=true antes do PATCH. Oversell só se qty/sold.
    } else if (!ck.ok) {
      c.block('C2-UNLIST-BLOCK', 'CD5', 'unlist ganhou a corrida / checkout bloqueado', ck.brief);
    }
    // Soft-delete / sold
    final soldSku = await mkSkus(c, n: 1, tag: 'c2-sold', qty: 1, price: 13);
    if (soldSku.length == 1) {
      final s = soldSku.first;
      await c.rest(
        'PATCH',
        'products?id=eq.${s.pid}',
        jwt: c.sellerJwt,
        body: {'is_sold': true},
      );
      final ckSold = await c.checkout(orderId: s.oid, productId: s.pid, amount: 1);
      c.note('C2.sold', 'checkout produto is_sold', ckSold.brief, lens: 'CD5', well: 'CD-C');
      if (ckSold.ok) {
        c.hold(
          id: 'P1-5',
          lens: 'CD5',
          severity: 'P1',
          title: 'Checkout abre Session em produto is_sold=true',
          actor: 'buyer JWT',
          pre: 'seller marcou is_sold',
          repro: 'PATCH is_sold=true; POST CPI',
          expected: 'Checkout blocked: product is marked sold',
          obtained: ckSold.brief,
        );
      } else {
        c.block('C2-SOLD', 'CD5', 'sold bloqueia checkout', ckSold.brief);
      }
    }
  }

  // C.3 live+marketplace mesmo SKU (fixture mínima, sem directo activo)
  final liveSku = await c.createProduct(
    title: '$prefix-c3-live-mkt',
    qty: 1,
    price: 14,
    live: true,
    listed: true,
  );
  if (liveSku != null) {
    final liveIns = await c.rest('POST', 'lives', service: true, body: {
      'seller_id': c.sellerId,
      'vendedor_id': c.sellerId,
      'title': '$prefix-c3-no-stream',
      'status': 'ended',
      'is_active': false,
    });
    c.note('C3.live-ins', 'live ended fixture (sem stream)', liveIns.brief,
        lens: 'CD5', well: 'CD-C');
    final lid = liveIns.firstId;
    if (lid != null) {
      final li = await c.rest('POST', 'live_items', service: true, body: {
        'live_id': lid,
        'product_id': liveSku,
        'seller_id': c.sellerId,
        'price': 14,
        'quantity': 1,
      });
      c.note('C3.live-item', 'live_item mesmo SKU', li.brief, lens: 'CD5', well: 'CD-C');
      final oMkt = await c.insertOrder(productId: liveSku, price: 14, jwt: c.buyerJwt);
      if (oMkt != null) {
        final ck = await c.checkout(orderId: oMkt, productId: liveSku, amount: 1);
        c.trackSession(ck);
        c.note('C3.mkt-with-live-item', 'checkout marketplace SKU com live_item ended',
            ck.brief,
            lens: 'CD5', well: 'CD-C');
        if (!ck.ok) {
          c.block('C3-MKT-LIVE-ENDED', 'CD5', 'marketplace bloqueado com live ended (inesperado?)',
              ck.brief);
        } else {
          c.block('C3-MKT-OK', 'CD5', 'marketplace OK com live ended (sem oversell live activo)',
              ck.brief);
        }
      }
    } else {
      c.skip('C3.live', 'CD5', 'não criou live ended (schema)', liveIns.brief);
    }
  }

  // C.4 bag_update_qty 9999 / qty alheia
  final qtyMine = await c.rpc('batata_live_bag_update_qty', {
    'p_request_id': '00000000-0000-4000-8000-000000000099',
    'p_qty': 9999,
  }, jwt: c.buyerJwt);
  final qtyAnon = await c.rpc('batata_live_bag_update_qty', {
    'p_request_id': '00000000-0000-4000-8000-000000000099',
    'p_qty': 2,
  });
  c.note('C4.bag-qty', 'bag_update_qty 9999 / anon', {
    'mine': qtyMine.brief,
    'anon': qtyAnon.brief,
  }, lens: 'CD5', well: 'CD-C');
  final okHigh = qtyMine.ok &&
      (qtyMine.map?['ok'] == true || '${qtyMine.body}'.contains('"ok":true'));
  if (okHigh) {
    c.hold(
      id: 'P1-6',
      lens: 'CD5',
      severity: 'P1',
      title: 'bag_update_qty aceitou 9999',
      actor: 'buyer JWT',
      pre: 'request fake',
      repro: 'rpc batata_live_bag_update_qty p_qty=9999',
      expected: 'qty_too_high / not_allowed',
      obtained: qtyMine.brief,
    );
  } else {
    c.block('C4-QTY-9999', 'CD5', 'qty 9999 rejeitada', qtyMine.brief);
  }
  if (qtyAnon.ok && qtyAnon.map?['ok'] == true) {
    c.hold(
      id: 'P1-7',
      lens: 'CD7',
      severity: 'P1',
      title: 'anon altera qty de saco alheio',
      actor: 'anon',
      pre: 'sem JWT',
      repro: 'rpc batata_live_bag_update_qty anon',
      expected: '401/403',
      obtained: qtyAnon.brief,
    );
  } else {
    c.block('C4-QTY-ANON', 'CD7', 'anon bloqueado em bag_update_qty', qtyAnon.brief);
  }

  // Cross-seller bag
  final s1 = await mkSkus(c, n: 1, tag: 'c4-s1', qty: 2, price: 10);
  final p2 = await c.createProduct(
    seller: c.seller2Id,
    title: '$prefix-c4-s2',
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
    c.note('C4.cross-seller', 'bag 2 sellers', hit.brief, lens: 'CD7', well: 'CD-C');
    if (hit.ok) {
      c.hold(
        id: 'P1-8',
        lens: 'CD7',
        severity: 'P1',
        title: 'bag_checkout aceita 2 sellers numa Session',
        actor: 'buyer JWT',
        pre: 'order S1 + order S2',
        repro: 'POST bag_checkout 2 sellers',
        expected: 'Checkout blocked: bag lines must share one seller',
        obtained: hit.brief,
      );
    } else {
      c.block('C4-CROSS-SELLER', 'CD7', 'bag 2 sellers bloqueado', hit.brief);
    }
  }
}

/// POÇO CD-D — FSM / MB WAY / PÓS-PAGO
Future<void> cdDFsmMbway(Rtcd c) async {
  c.wellsTried.add('CD-D');

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
      c.note('D1.seller-pago-noproof', 'seller marca pago MB WAY sem proof',
          sellerPago.brief,
          lens: 'CD4', well: 'CD-D');
      if (sellerPago.ok && '${(await c.orderRow(mbOid))?['status']}' == 'pago') {
        c.hold(
          id: 'P0-8',
          lens: 'CD4',
          severity: 'P0',
          title: 'Seller marcou MB WAY como pago sem prova',
          actor: 'seller JWT',
          pre: 'order MB WAY reserva_pendente, proof_url vazio',
          repro: 'PATCH orders.status=pago',
          expected: 'order_mbway_pago_requires_proof',
          obtained: sellerPago.brief,
        );
      } else {
        c.block('D1-MBWAY-NOPROOF', 'CD4', 'seller pago sem prova bloqueado',
            sellerPago.brief);
      }

      final buyerConcl = await c.rest(
        'PATCH',
        'orders?id=eq.$mbOid',
        jwt: c.buyerJwt,
        body: {'status': 'concluido'},
      );
      c.note('D1.buyer-concluido-cedo', 'buyer concluido cedo', buyerConcl.brief,
          lens: 'CD4', well: 'CD-D');
      if (buyerConcl.ok &&
          '${(await c.orderRow(mbOid))?['status']}'.toLowerCase() == 'concluido') {
        c.hold(
          id: 'P1-9',
          lens: 'CD4',
          severity: 'P1',
          title: 'Buyer marcou concluido antes de pago/enviado',
          actor: 'buyer JWT',
          pre: 'MB WAY ainda não pago',
          repro: 'PATCH status=concluido',
          expected: 'order_concluido_denied',
          obtained: buyerConcl.brief,
        );
      } else {
        c.block('D1-CONCLUIDO-CEDO', 'CD4', 'buyer concluido cedo bloqueado',
            buyerConcl.brief);
      }
    }
  }

  // D.2 cancel pós-pago / restock / refund buyer JWT Seguro
  final paid = await c.payToPago(lens: 'CD4', initialQty: 3);
  if (paid == null) {
    c.skip('D2.paid', 'CD4', 'setup_paid_order falhou', 'null');
  } else {
    final before = await c.productRow(paid.pid);
    final qty0 = numOf(before?['quantity']);
    final cancel = await c.rest(
      'PATCH',
      'orders?id=eq.${paid.oid}',
      jwt: c.buyerJwt,
      body: {'status': 'cancelado'},
    );
    final cancelS = await c.rest(
      'PATCH',
      'orders?id=eq.${paid.oid}',
      jwt: c.sellerJwt,
      body: {'status': 'cancelado'},
    );
    final afterCancel = await c.productRow(paid.pid);
    c.note('D2.cancel-postpay', 'cancel JWT após pago', {
      'buyer': cancel.brief,
      'seller': cancelS.brief,
      'qty0': qty0,
      'qty1': afterCancel?['quantity'],
      'status': (await c.orderRow(paid.oid))?['status'],
    }, lens: 'CD4', well: 'CD-D');
    final st = '${(await c.orderRow(paid.oid))?['status']}'.toLowerCase();
    if (st == 'cancelado' || st == 'cancelled') {
      c.hold(
        id: 'P0-9',
        lens: 'CD4',
        severity: 'P0',
        title: 'Cancel JWT pós-pago aceite',
        actor: 'buyer/seller JWT',
        pre: 'setup_paid_order status=pago',
        repro: 'PATCH status=cancelado',
        expected: 'order_cancel_denied_post_pay',
        obtained: {'buyer': cancel.brief, 'seller': cancelS.brief, 'status': st},
      );
    } else {
      c.block('D2-CANCEL-POSTPAY', 'CD4', 'cancel pós-pago bloqueado', {
        'buyer': cancel.status,
        'seller': cancelS.status,
        'status': st,
      });
    }

    final refBuyer = await c.refund(paid.oid, jwt: c.buyerJwt);
    c.note('D2.refund-buyer', 'refund-order JWT buyer Seguro', refBuyer.brief,
        lens: 'CD7', well: 'CD-D');
    if (refBuyer.ok && refBuyer.map?['ok'] != false) {
      c.hold(
        id: 'P0-10',
        lens: 'CD7',
        severity: 'P0',
        title: 'Buyer JWT reembolsou Seguro (seller-only)',
        actor: 'buyer JWT',
        pre: 'order pago Stripe TEST',
        repro: 'POST refund-order JWT buyer',
        expected: '403 Sem permissão',
        obtained: refBuyer.brief,
      );
    } else {
      c.block('D2-REFUND-BUYER', 'CD7', 'buyer refund bloqueado', refBuyer.brief);
    }

    // Restock duplo: 2× refund seller (se ainda pago)
    final rowNow = await c.orderRow(paid.oid);
    if ('${rowNow?['status']}' == 'pago') {
      final r1 = await c.refund(paid.oid, jwt: c.sellerJwt);
      final r2 = await c.refund(paid.oid, jwt: c.sellerJwt);
      final prod = await c.productRow(paid.pid);
      c.note('D2.double-refund', '2× refund seller', {
        'r1': r1.brief,
        'r2': r2.brief,
        'qty': prod?['quantity'],
        'qty0': qty0,
      }, lens: 'CD5', well: 'CD-D');
      final q1 = numOf(prod?['quantity']);
      if (qty0 != null && q1 != null && q1 > qty0 + 1) {
        c.hold(
          id: 'P1-10',
          lens: 'CD5',
          severity: 'P1',
          title: 'Restock duplo após 2× refund',
          actor: 'seller JWT',
          pre: 'order pago; 2 POST refund-order',
          repro: 'refund; refund',
          expected: '2.º refund idempotente; stock +1',
          obtained: {'qty0': qty0, 'qty': q1, 'r1': r1.brief, 'r2': r2.brief},
        );
      } else {
        c.block('D2-DOUBLE-REFUND', 'CD5', '2.º refund não duplicou stock', {
          'qty0': qty0,
          'qty': q1,
        });
      }
    }
  }

  // D.3 settle return URL vs webhook invertido: GET settle em Session unpaid, depois paid
  final setl = await mkSkus(c, n: 1, tag: 'd3-settle', qty: 2, price: 12);
  if (setl.length == 1) {
    final s = setl.first;
    final ck = await c.checkout(orderId: s.oid, productId: s.pid, amount: 1);
    c.trackSession(ck);
    final sid = ck.sessionId;
    if (sid != null) {
      final g1 = await c.settleGet(sid);
      final row1 = await c.orderRow(s.oid);
      c.note('D3.settle-unpaid', 'GET checkout_return em Session unpaid', {
        'g1': g1.brief,
        'status': row1?['status'],
      }, lens: 'CD8', well: 'CD-D');
      if ('${row1?['status']}'.toLowerCase() == 'pago') {
        c.hold(
          id: 'P0-11',
          lens: 'CD8',
          severity: 'P0',
          title: 'GET settle marcou pago sem captura Stripe',
          actor: 'anon GET',
          pre: 'Session open unpaid',
          repro: 'GET create-payment-intent?checkout_return=success&session_id=',
          expected: '402 / não pago',
          obtained: {'g1': g1.brief, 'status': row1?['status']},
        );
      } else {
        c.block('D3-SETTLE-UNPAID', 'CD8', 'settle unpaid não marcou pago', {
          'status': g1.status,
          'order': row1?['status'],
        });
      }
    }
  }
}

/// POÇO CD-E — composição até caixa
Future<void> cdECaixa(Rtcd c, Map<String, num> wallets0) async {
  c.wellsTried.add('CD-E');
  final wBefore = await c.wallets();
  final paid = await c.payToPago(lens: 'CD8', initialQty: 2);
  if (paid == null) {
    c.skip('E.paid', 'CD8', 'setup_paid_order falhou — sem composição caixa', 'null');
    return;
  }
  final row = await c.orderRow(paid.oid);
  final prod = await c.productRow(paid.pid);
  final wAfter = await c.wallets();
  final dSeller = (wAfter['seller'] ?? 0) - (wBefore['seller'] ?? 0);
  final dBuyer = (wAfter['buyer'] ?? 0) - (wBefore['buyer'] ?? 0);
  c.note('E.compose', 'caixa order pago', {
    'oid': paid.oid,
    'pid': paid.pid,
    'pi': paid.pi,
    'status': row?['status'],
    'amount_paid_cents': row?['amount_paid_cents'],
    'stock_units_applied': row?['stock_units_applied'],
    'product_qty': prod?['quantity'],
    'dSeller': dSeller,
    'dBuyer': dBuyer,
  }, lens: 'CD8', well: 'CD-E');

  final status = '${row?['status']}'.toLowerCase();
  final paidCents = numOf(row?['amount_paid_cents']) ?? 0;
  final applied = numOf(row?['stock_units_applied']) ?? 0;
  if (status != 'pago' && status != 'enviado' && status != 'concluido') {
    c.hold(
      id: 'P1-11',
      lens: 'CD8',
      severity: 'P1',
      title: 'setup_paid_order Stripe TEST não deixou status=pago',
      actor: 'observação',
      pre: 'PI 4242 succeeded + settle',
      repro: 'sec-fase2-e2e-oversell setup_paid_order',
      expected: 'status=pago + amount_paid_cents>0 + stock aplicado',
      obtained: {
        'status': status,
        'amount_paid_cents': paidCents,
        'stock_units_applied': applied,
      },
    );
  } else {
    c.block('E-PAID-OK', 'CD8', 'Stripe TEST 4242 → pago + PI + stock', {
      'status': status,
      'pi': paid.pi,
      'amount_paid_cents': paidCents,
      'stock_units_applied': applied,
      'product_qty': prod?['quantity'],
    });
  }

  // Δwallet: hold só se dinheiro apareceu sem PI / ou seller recebeu e buyer perdeu sem ordem
  if (dSeller != 0 || dBuyer != 0) {
    c.note('E.wallet-delta', 'Δwallet na composição', {
      'dSeller': dSeller,
      'dBuyer': dBuyer,
      'status': status,
      'pi': paid.pi,
    }, lens: 'CD8', well: 'CD-E');
  }

  // Bag pago (se e2e existir)
  final bagPaid = await c.e2e('setup_paid_bag', {'n_lines': 2});
  c.note('E.bag-paid', 'setup_paid_bag', bagPaid.brief, lens: 'CD8', well: 'CD-E');
}

Future<void> cdControlLegitSingle(Rtcd c) async {
  final rows = await mkSkus(c, n: 1, tag: 'ctrl-single', qty: 2, price: 12);
  if (rows.isEmpty) return;
  final r = rows.first;
  final ck = await c.checkout(orderId: r.oid, productId: r.pid, amount: 1);
  c.trackSession(ck);
  c.note('CTRL.single', 'compra single-item legítima', ck.brief, lens: 'CD1');
  if (!ck.ok || (ck.sessionId ?? '').isEmpty) {
    c.hold(
      id: 'P1-12',
      lens: 'CD1',
      severity: 'P1',
      title: 'Checkout single-item legítimo partido',
      actor: 'buyer JWT',
      pre: '1 SKU listado 12€ qty=2',
      repro: 'POST create-payment-intent order_id',
      expected: '200 + cs_ + amount_total≥1200',
      obtained: ck.brief,
    );
  } else {
    c.block('CTRL-SINGLE', 'CD1', 'single-item legítimo abre Session', {
      'sid': ck.sessionId,
      'amt': ck.amountTotal,
    });
  }
}
