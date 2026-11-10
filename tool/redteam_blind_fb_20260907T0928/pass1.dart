/// RED TEAM CEGO FB pass1 — stock / Hub / dinheiro curto smoke pré-P4.
/// Matriz A1–A4 · B1–B3 · C1–C3 · D1–D2. Sem correções. Stripe TEST.
import 'dart:io';

import '_rtfb.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('FB pass1 staging=${c.url} prefix=$prefix');
  stdout.writeln(
    c.stripeTestKey == null
        ? 'WARN no sk_test_ — pay via pk/payment_pages + settle / e2e'
        : 'sk_test_ present — native retrieve+confirm',
  );
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.restoreSeller1Published();
  final fresh = await c.mintBuyer('fb1');
  c.buyerId = fresh.id;
  c.buyerJwt = fresh.jwt;
  c.note('actors', 'ids', {
    'b': c.buyerId,
    's': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
    'seller_hub': (await c.profile(c.sellerId!))?['hub_published'],
    'sk': c.stripeTestKey != null,
  });
  final wallets0 = await c.wallets();
  c.note('wallet.pre', 'baseline', wallets0, lens: 'FB-C', well: 'FB-C');

  await runA(c);
  final leftover = await runB(c);
  await runC(c, leftover, wallets0);
  await runD(c, leftover);

  final wallets1 = await c.wallets();
  c.note('wallet.post', 'após probes', {
    'pre': wallets0,
    'post': wallets1,
    'dSeller': (wallets1['seller'] ?? 0) - (wallets0['seller'] ?? 0),
  }, lens: 'FB-C', well: 'FB-C');

  await c.dumpAll('pass1_findings.json');
  final races = c.probes
      .where((p) => '${p['payload']}'.contains('Future.wait'))
      .map((p) => p['probe_id'])
      .toList();
  final novas = c.probes
      .where((p) => p['classe_nova'] == 'SIM')
      .map((p) => p['probe_id'])
      .toList();
  await dumpJson('${outDir()}/probes.json', {
    'stamp': stamp,
    'prefix': prefix,
    'auditor': 'REDTEAM_BLIND_FB_STOCK_MONEY_SMOKE_PRE_P4_v1',
    'probes': c.probes,
    'n': c.probes.length,
    'races': races,
    'classes_novas': novas,
    'findings': c.findings.length,
    'findings_ids': c.findings.map((f) => f['id']).toList(),
  });
  stdout.writeln(
    'DONE probes=${c.probes.length} findings=${c.findings.length} '
    'blocked=${c.blocked.length} skip=${c.skipped.length} '
    'races=${races.length} classe_nova=${novas.length} '
    'lenses=${c.lensesHit.toList()..sort()}',
  );
}

Future<void> pause([int ms = 400]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

bool isPago(Map<String, dynamic>? row) {
  final st = '${row?['status'] ?? ''}'.toLowerCase();
  return st == 'pago' ||
      st == 'enviado' ||
      st == 'entregue' ||
      st == 'concluido';
}

/// FB-A Stock
Future<void> runA(Rtdb c) async {
  // A1 sequential 2 buyers same SKU qty=1
  await pause();
  final a1pid = await c.createProduct(
    title: '$prefix-a1-last',
    qty: 1,
    price: 11,
  );
  HttpHit? a1h1;
  HttpHit? a1h2;
  if (a1pid != null) {
    a1h1 = await c.insertOrderHit(
      productId: a1pid,
      price: 11,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    a1h2 = await c.insertOrderHit(
      productId: a1pid,
      price: 11,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    );
  }
  final a1secondOk = a1h2?.ok == true;
  final a1oversell = a1h1?.ok == true && a1secondOk;
  if (a1pid == null) {
    c.skip('A1', 'FB-A', 'createProduct', 'null');
  } else if (a1oversell) {
    c.hold(
      id: 'P0-A1',
      lens: 'FB-A',
      severity: 'P0',
      title: '2 buyers inseriram hold na última unidade',
      actor: 'buyer + buyer2 JWT',
      pre: 'quantity=1',
      repro: 'insertOrder B1; insertOrder B2',
      expected: '2.º insert 400 stock',
      obtained: {'h1': a1h1?.brief, 'h2': a1h2?.brief},
    );
  } else {
    c.block('A1', 'FB-A', '2.º insert bloqueado qty=1', {
      'h1': a1h1?.brief,
      'h2': a1h2?.brief,
    });
  }
  c.probe(
    id: 'A1',
    poco: 'FB-A',
    payload: '2 buyers mesmo SKU qty=1 (insert sequencial 2.º)',
    http: {'h1': a1h1?.brief, 'h2': a1h2?.brief},
    bd: {'pid': a1pid, 'o1': a1h1?.firstId, 'o2': a1h2?.firstId},
    verdict: a1pid == null
        ? 'SKIP'
        : (a1oversell ? 'HOLD' : 'FAIL'),
    lens: 'FB-A',
    classeNova: false,
  );

  // A2 reserve∥reserve 0 ms
  await pause();
  final a2pid = await c.createProduct(
    title: '$prefix-a2-race',
    qty: 1,
    price: 11,
  );
  List<HttpHit> a2hits = const [];
  if (a2pid != null) {
    a2hits = await parallel([
      c.insertOrderHit(
        productId: a2pid,
        price: 11,
        jwt: c.buyerJwt,
        buyer: c.buyerId,
      ),
      c.insertOrderHit(
        productId: a2pid,
        price: 11,
        jwt: c.buyer2Jwt,
        buyer: c.buyer2Id,
      ),
    ]);
  }
  final a2ok = a2hits.where((h) => h.ok).length;
  final a2prod = a2pid == null ? null : await c.productRow(a2pid);
  final a2oversell = a2ok >= 2;
  if (a2pid == null) {
    c.skip('A2', 'FB-A', 'createProduct', 'null');
  } else if (a2oversell) {
    c.hold(
      id: 'P0-A2',
      lens: 'FB-A',
      severity: 'P0',
      title: 'reserve∥reserve 0 ms: 2 holds na última unidade',
      actor: 'buyer + buyer2 JWT Future.wait',
      pre: 'quantity=1',
      repro: 'Future.wait 2× insertOrder',
      expected: '1 hold + 1 400 stock',
      obtained: {
        'ok': a2ok,
        'briefs': a2hits.map((h) => h.brief).toList(),
        'qty': a2prod?['quantity'],
      },
    );
  } else {
    c.block('A2', 'FB-A', 'race 0 ms ≤1 hold', {
      'ok': a2ok,
      'briefs': a2hits.map((h) => h.brief).toList(),
    });
  }
  c.probe(
    id: 'A2',
    poco: 'FB-A',
    payload: 'Future.wait reserve∥reserve 0 ms qty=1',
    http: a2hits.map((h) => h.brief).toList(),
    bd: {'ok': a2ok, 'qty': a2prod?['quantity'], 'sold': a2prod?['is_sold']},
    verdict: a2pid == null
        ? 'SKIP'
        : (a2oversell ? 'HOLD' : 'FAIL'),
    lens: 'FB-A',
    classeNova: true,
  );

  // A3 + A4: pago qty=1 → qty↓ is_sold Hub n=0; 2.º CPI bloqueado
  await pause();
  final paid1 = await c.payToPago(lens: 'FB-A', initialQty: 1);
  Map<String, dynamic>? a3ord;
  Map<String, dynamic>? a3prod;
  HttpHit? a3hubB;
  HttpHit? a3hubA;
  HttpHit? a4cpi;
  if (paid1 != null) {
    a3ord = await c.orderRow(paid1.oid);
    a3prod = await c.productRow(paid1.pid);
    a3hubB = await c.hubSku(paid1.pid, jwt: c.buyerJwt);
    a3hubA = await c.hubSku(paid1.pid, anon: true);
    final a4oid = await c.insertOrder(
      productId: paid1.pid,
      price: 5.9,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
    );
    if (a4oid != null) {
      a4cpi = await c.checkout(
        orderId: a4oid,
        productId: paid1.pid,
        amount: 1,
        jwt: c.buyer2Jwt,
        buyer: c.buyer2Id,
      );
      c.trackSession(a4cpi);
    }
  }
  final a3q = numOf(a3prod?['quantity']) ?? -1;
  final a3sold = a3prod?['is_sold'] == true;
  final a3pago = isPago(a3ord);
  final a3hubN = a3hubB?.list.length ?? -1;
  final a3hubAnon = a3hubA?.list.length ?? -1;
  final a3bad = paid1 != null &&
      a3pago &&
      (a3q > 0 || !a3sold || a3hubN > 0 || a3hubAnon > 0);
  if (paid1 == null) {
    c.skip('A3', 'FB-A', 'setup_paid_order qty=1', 'null');
    c.skip('A4', 'FB-A', 'sem pago qty=1', 'null');
  } else if (a3bad) {
    c.hold(
      id: 'P0-A3',
      lens: 'FB-A',
      severity: a3q < 0 ? 'P1' : 'P0',
      title: 'Após pago qty=1 stock/Hub incoerente (possível oversell visível)',
      actor: 'e2e setup_paid_order 4242',
      pre: 'initial_qty=1',
      repro: 'payToPago; products + hub_products_public buyer+anon',
      expected: 'qty=0 is_sold Hub n=0',
      obtained: {
        'qty': a3q,
        'sold': a3sold,
        'hub_b': a3hubN,
        'hub_anon': a3hubAnon,
        'status': a3ord?['status'],
        'pi': paid1.pi,
      },
    );
  } else {
    c.block('A3', 'FB-A', 'pago qty=1 qty↓ is_sold Hub 0', {
      'qty': a3q,
      'sold': a3sold,
      'hub_b': a3hubN,
      'hub_anon': a3hubAnon,
      'pi': paid1.pi,
    });
  }
  c.probe(
    id: 'A3',
    poco: 'FB-A',
    payload: 'após pago A qty=1: qty↓ · is_sold · Hub n (buyer+anon)',
    http: paid1 == null ? 'null' : {'hub_b': a3hubB?.brief, 'hub_a': a3hubA?.brief},
    bd: {
      'status': a3ord?['status'],
      'qty': a3q,
      'sold': a3sold,
      'hub_b': a3hubN,
      'hub_anon': a3hubAnon,
      'pi': paid1?.pi,
      'applied': a3ord?['stock_units_applied'],
    },
    verdict: paid1 == null ? 'SKIP' : (a3bad ? 'HOLD' : 'FAIL'),
    lens: 'FB-A',
    classeNova: true,
  );

  final a4opened = a4cpi?.ok == true && (a4cpi?.sessionId?.startsWith('cs_') ?? false);
  if (paid1 != null) {
    if (a4opened) {
      c.hold(
        id: 'P1-A4',
        lens: 'FB-A',
        severity: 'P1',
        title: '2.º buyer abriu CPI na unidade já paga',
        actor: 'buyer2 JWT CPI',
        pre: 'SKU qty=1 já pago',
        repro: 'insert+CPI B2 no mesmo product_id',
        expected: 'insert 400 ou CPI 400 stock/sold',
        obtained: {
          'cpi': a4cpi?.brief,
          'qty': a3q,
          'sold': a3sold,
        },
      );
    } else {
      c.block('A4', 'FB-A', '2.º CPI/insert na unit paga bloqueado', {
        'cpi': a4cpi?.brief,
        'insert_id': a4cpi == null ? 'insert deny or skip' : a4cpi.firstId,
      });
    }
  }
  c.probe(
    id: 'A4',
    poco: 'FB-A',
    payload: '2.º buyer tenta CPI na mesma unit após pago qty=1',
    http: a4cpi?.brief ?? 'no cpi (insert deny)',
    bd: {'qty': a3q, 'sold': a3sold, 'opened': a4opened},
    verdict: paid1 == null ? 'SKIP' : (a4opened ? 'HOLD' : 'FAIL'),
    lens: 'FB-A',
    classeNova: true,
  );
}

class LeftoverFix {
  LeftoverFix({
    required this.oid,
    required this.pid,
    this.pi,
    this.cs,
    this.qty = -1,
    this.hubB = -1,
    this.hubA = -1,
    this.status = '',
  });
  final String oid;
  final String pid;
  final String? pi;
  final String? cs;
  final num qty;
  final int hubB;
  final int hubA;
  final String status;
}

/// FB-B Hub / composição
Future<LeftoverFix?> runB(Rtdb c) async {
  await pause(600);
  final paid = await c.payToPago(lens: 'FB-B', initialQty: 2);
  Map<String, dynamic>? ord;
  Map<String, dynamic>? prod;
  HttpHit? hubB;
  HttpHit? hubA;
  if (paid != null) {
    ord = await c.orderRow(paid.oid);
    prod = await c.productRow(paid.pid);
    hubB = await c.hubSku(paid.pid, jwt: c.buyerJwt);
    hubA = await c.hubSku(paid.pid, anon: true);
  }
  final q = numOf(prod?['quantity']) ?? -1;
  final hubBn = hubB?.list.length ?? -1;
  final hubAn = hubA?.list.length ?? -1;
  final pago = isPago(ord);
  final leftoverOk = paid != null && pago && q == 1 && hubBn == 1 && hubAn == 1;
  final leftoverWrong = paid != null && pago && q != 1;
  final hubWrong = paid != null &&
      pago &&
      q == 1 &&
      (hubBn != 1 || hubAn != 1);
  if (paid == null) {
    c.skip('B1', 'FB-B', 'setup_paid_order leftover', 'null');
    c.skip('B2', 'FB-B', 'setup_paid_order leftover', 'null');
  } else if (leftoverWrong || hubWrong) {
    c.hold(
      id: leftoverWrong ? 'P0-B2' : 'P1-B1',
      lens: 'FB-B',
      severity: leftoverWrong ? 'P0' : 'P1',
      title: leftoverWrong
          ? 'Pago leftover qty≠1 (oversell ou stock morto)'
          : 'Hub público ≠ leftover qty=1',
      actor: 'e2e setup_paid_order + hub_products_public buyer+anon',
      pre: 'SKU qty=2 listed',
      repro: 'payToPago initial_qty=2; Hub JWT + anon; products.quantity',
      expected: 'pago; qty=1; Hub n=1 buyer e anon',
      obtained: {
        'status': ord?['status'],
        'qty': q,
        'hub_b': hubBn,
        'hub_anon': hubAn,
        'sold': prod?['is_sold'],
        'pi': paid.pi,
      },
    );
  } else {
    c.block('B1', 'FB-B', 'Hub buyer+anon = leftover qty=1', {
      'qty': q,
      'hub_b': hubBn,
      'hub_anon': hubAn,
      'status': ord?['status'],
    });
    c.block('B2', 'FB-B', 'leftover 2→1 visível Hub', {
      'qty': q,
      'hub_b': hubBn,
    });
  }
  c.probe(
    id: 'B1',
    poco: 'FB-B',
    payload: 'Hub público (buyer+anon) vs order+products após pago leftover',
    http: {'hub_b': hubB?.brief, 'hub_a': hubA?.brief},
    bd: {
      'status': ord?['status'],
      'qty': q,
      'hub_b': hubBn,
      'hub_anon': hubAn,
      'sold': prod?['is_sold'],
      'pi': paid?.pi,
      'applied': ord?['stock_units_applied'],
      'sites': 4,
    },
    verdict: paid == null
        ? 'SKIP'
        : (leftoverOk ? 'FAIL' : 'HOLD'),
    lens: 'FB-B',
    classeNova: true,
  );
  c.probe(
    id: 'B2',
    poco: 'FB-B',
    payload: 'leftover qty 2→1 visível Hub (n=1 listed unsold)',
    http: hubB?.brief ?? 'null',
    bd: {'qty': q, 'hub_n': hubBn, 'status': ord?['status']},
    verdict: paid == null
        ? 'SKIP'
        : (leftoverWrong ? 'HOLD' : 'FAIL'),
    lens: 'FB-B',
    classeNova: false,
  );

  // B3 bag 4 lines: todas pago ou nenhuma
  await pause(600);
  final bagBuyer = await c.mintBuyer('bag4');
  final pids = <String>[];
  final oids = <String>[];
  for (var i = 0; i < 4; i++) {
    final pid = await c.createProduct(
      title: '$prefix-b3-$i',
      qty: 2,
      price: 8 + i.toDouble(),
    );
    if (pid == null) continue;
    pids.add(pid);
    final oid = await c.insertOrder(
      productId: pid,
      price: 8 + i.toDouble(),
      jwt: bagBuyer.jwt,
      buyer: bagBuyer.id,
    );
    if (oid != null) oids.add(oid);
  }
  HttpHit? bagHit;
  Map<String, Object?> payBag = {'paid': false};
  if (oids.length == 4 && pids.length == 4) {
    final lines = <Map<String, Object?>>[];
    for (var i = 0; i < 4; i++) {
      lines.add({
        'order_id': oids[i],
        'product_id': pids[i],
        'seller_id': c.sellerId,
        'quantity': 1,
      });
    }
    bagHit = await c.checkoutBag(
      lines: lines,
      jwt: bagBuyer.jwt,
      buyer: bagBuyer.id,
      amount: 1,
      seller: c.sellerId,
    );
    c.trackSession(bagHit);
    final sid = bagHit.sessionId;
    if (sid != null && sid.startsWith('cs_') && bagHit.ok) {
      payBag = await c.payCheckout4242(sid, checkoutUrl: bagHit.checkoutUrl);
      final pi = payBag['pi']?.toString();
      if (pi != null && pi.startsWith('pi_')) {
        final stl = await c.fase2Settle(
          pi: pi,
          sessionId: sid,
          lines: lines,
          bag: true,
        );
        payBag['fase2'] = stl.brief;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }
  final statuses = <String>[];
  var anyPago = false;
  var allPago = true;
  for (final oid in oids) {
    final row = await c.orderRow(oid);
    final st = '${row?['status'] ?? ''}';
    statuses.add(st);
    final p = isPago(row);
    if (p) {
      anyPago = true;
    } else {
      allPago = false;
    }
  }
  final half = anyPago && !allPago && oids.length >= 2;
  final b3skip = oids.length < 4;
  if (b3skip) {
    c.skip('B3', 'FB-B', 'não criou 4 linhas', {'oids': oids.length});
  } else if (half) {
    c.hold(
      id: 'P0-B3',
      lens: 'FB-B',
      severity: 'P0',
      title: 'Saco 4 linhas meia liquidação (umas pago outras não)',
      actor: 'buyer bag4 JWT + Stripe TEST 4242',
      pre: '4 SKUs qty=2; bag_checkout',
      repro: 'checkoutBag 4 lines; payCheckout4242; orders.status',
      expected: 'todas pago ou nenhuma',
      obtained: {
        'statuses': statuses,
        'pay': payBag,
        'cpi': bagHit?.brief,
      },
    );
  } else {
    c.block('B3', 'FB-B', 'saco 4 linhas atómico (todas ou nenhuma)', {
      'statuses': statuses,
      'all_pago': allPago,
      'any_pago': anyPago,
      'cpi': bagHit?.brief,
      'paid_flag': payBag['paid'],
    });
  }
  c.probe(
    id: 'B3',
    poco: 'FB-B',
    payload: 'bag pago 4 lines: todas pago ou nenhuma (sem meia liquidação)',
    http: {'cpi': bagHit?.brief, 'pay': payBag},
    bd: {
      'n': oids.length,
      'statuses': statuses,
      'all_pago': allPago,
      'any_pago': anyPago,
      'half': half,
    },
    verdict: b3skip ? 'SKIP' : (half ? 'HOLD' : 'FAIL'),
    lens: 'FB-B',
    classeNova: true,
  );

  if (paid == null) return null;
  return LeftoverFix(
    oid: paid.oid,
    pid: paid.pid,
    pi: paid.pi,
    cs: ord?['stripe_checkout_session_id']?.toString(),
    qty: q,
    hubB: hubBn,
    hubA: hubAn,
    status: '${ord?['status'] ?? ''}',
  );
}

/// FB-C Dinheiro curto
Future<void> runC(Rtdb c, LeftoverFix? leftover, Map<String, num> wallets0) async {
  // C1 underpay / total_eur=0 → amount catálogo
  await pause();
  const price = 12.0;
  final c1pid = await c.createProduct(
    title: '$prefix-c1-under',
    qty: 2,
    price: price,
  );
  HttpHit? c1cpi;
  String? c1oid;
  if (c1pid != null) {
    c1oid = await c.insertOrder(
      productId: c1pid,
      price: price,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    if (c1oid != null) {
      c1cpi = await c.checkout(
        orderId: c1oid,
        productId: c1pid,
        amount: 0,
        jwt: c.buyerJwt,
        buyer: c.buyerId,
        extra: {
          'total_eur': 0,
          'amount_total': 0,
          'server_amount_cents': 0,
        },
      );
      c.trackSession(c1cpi);
    }
  }
  final quoted = c1cpi?.amountTotal ??
      numOf(c1cpi?.map?['server_amount_cents'])?.round();
  final stripeAmt = numOf(c1cpi?.map?['amount_total'])?.round();
  final clientWon = c1cpi != null &&
      c1cpi.ok &&
      ((quoted != null && quoted <= 50) ||
          (stripeAmt != null && stripeAmt <= 50));
  if (c1pid == null || c1oid == null) {
    c.skip('C1', 'FB-C', 'SKU/order fail', 'null');
  } else if (clientWon) {
    c.hold(
      id: 'P0-C1',
      lens: 'FB-C',
      severity: 'P0',
      title: 'CPI aceitou underpay/total_eur=0 vs catálogo 12€',
      actor: 'buyer JWT',
      pre: 'SKU 12€',
      repro: 'create-payment-intent amount=0 total_eur=0',
      expected: 'server_amount catálogo (não 0)',
      obtained: {
        'cpi': c1cpi!.brief,
        'quoted': quoted,
        'stripeAmt': stripeAmt,
      },
    );
  } else {
    c.block('C1', 'FB-C', 'servidor manda amount (underpay recusado ou quote catálogo)', {
      'cpi': c1cpi?.brief,
      'quoted': quoted,
      'stripeAmt': stripeAmt,
    });
  }
  c.probe(
    id: 'C1',
    poco: 'FB-C',
    payload: 'underpay / total_eur=0 → amount catálogo',
    http: c1cpi?.brief ?? 'null',
    bd: {
      'quoted': quoted,
      'stripeAmt': stripeAmt,
      'status': c1cpi?.status,
      'client_won': clientWon,
    },
    verdict: (c1pid == null || c1oid == null)
        ? 'SKIP'
        : (clientWon ? 'HOLD' : 'FAIL'),
    lens: 'FB-C',
    classeNova: true,
  );

  // C2 seller wallet antes/depois 1 pago
  await pause();
  final wPay0 = await c.walletBal(c.sellerId);
  LeftoverFix? paidForWallet = leftover;
  if (paidForWallet == null) {
    final extra = await c.payToPago(lens: 'FB-C', initialQty: 2);
    if (extra != null) {
      paidForWallet = LeftoverFix(
        oid: extra.oid,
        pid: extra.pid,
        pi: extra.pi,
      );
    }
  }
  final wPay1 = await c.walletBal(c.sellerId);
  final dPago = wPay1 - wPay0;
  HttpHit? rel;
  List<Map<String, dynamic>> txns = const [];
  num wPay2 = wPay1;
  if (paidForWallet != null) {
    await c.markConcluidoMao(paidForWallet.oid);
    rel = await c.tryRelease(paidForWallet.oid, jwt: c.buyerJwt);
    await pause(800);
    wPay2 = await c.walletBal(c.sellerId);
    txns = await c.txnsForOrder(c.sellerId!, paidForWallet.oid);
  }
  final dRelease = wPay2 - wPay1;
  final dTotal = wPay2 - wPay0;
  final doubleCredit = txns.where((t) {
        final ty = '${t['type']}'.toLowerCase();
        return ty.contains('venda') || ty.contains('credit');
      }).length >
      1;
  final leakAtPago = dPago.abs() > 0.001;
  if (paidForWallet == null) {
    c.skip('C2', 'FB-C', 'sem order paga', 'null');
  } else if (doubleCredit || (dRelease.abs() > 0.001 && dRelease < -0.01)) {
    c.hold(
      id: 'P0-C2',
      lens: 'FB-C',
      severity: 'P0',
      title: 'Wallet seller: double credit ou débito anómalo após 1 pago',
      actor: 'setup_paid_order + batata_release',
      pre: '1 PI succeeded',
      repro: 'walletBal; markConcluidoMao; tryRelease',
      expected: 'Δ pago=0; após release ≤1 crédito venda',
      obtained: {
        'dPago': dPago,
        'dRelease': dRelease,
        'txns': txns.length,
        'rel': rel?.brief,
      },
    );
  } else {
    c.block('C2', 'FB-C', 'wallet Δ documentado (pago + release)', {
      'w0': wPay0,
      'w_after_pago': wPay1,
      'w_after_rel': wPay2,
      'dPago': dPago,
      'dRelease': dRelease,
      'dTotal': dTotal,
      'baseline': wallets0['seller'],
      'rel': rel?.brief,
      'txn_n': txns.length,
      'txn_types': txns.map((t) => t['type']).toList(),
      'leak_at_pago': leakAtPago,
    });
  }
  c.probe(
    id: 'C2',
    poco: 'FB-C',
    payload: 'seller wallet antes/depois 1 pago + release mão (Δ esperado)',
    http: rel?.brief ?? 'no release',
    bd: {
      'dPago': dPago,
      'dRelease': dRelease,
      'dTotal': dTotal,
      'w0': wPay0,
      'w1': wPay1,
      'w2': wPay2,
      'txn_n': txns.length,
      'oid': paidForWallet?.oid,
      'pi': paidForWallet?.pi,
    },
    verdict: paidForWallet == null
        ? 'SKIP'
        : ((doubleCredit) ? 'HOLD' : 'FAIL'),
    lens: 'FB-C',
    classeNova: true,
  );

  // C3 2× settle mesma session → 1 efeito
  await pause();
  final replay = await c.e2e('settle_get_replay', {});
  final r1 = numOf(replay.map?['settle1_http'])?.round();
  final r2 = numOf(replay.map?['settle2_http'])?.round();
  final oAfter = replay.map?['order'];
  Map<String, dynamic>? oMap;
  if (oAfter is Map) oMap = Map<String, dynamic>.from(oAfter);
  final pAfter = replay.map?['product'];
  Map<String, dynamic>? pMap;
  if (pAfter is Map) pMap = Map<String, dynamic>.from(pAfter);
  final applied = numOf(oMap?['stock_units_applied']);
  final qtyAfter = numOf(pMap?['quantity']);
  final refunded = '${oMap?['stripe_refund_id'] ?? ''}'.trim().isNotEmpty;
  final c3oid = replay.map?['order_id']?.toString();
  if (c3oid != null) c.createdOrderIds.add(c3oid);
  final c3pid = replay.map?['product_id']?.toString();
  if (c3pid != null) c.createdProductIds.add(c3pid);
  final twoEffects = refunded || (qtyAfter != null && qtyAfter < 0);
  if (!replay.ok && replay.map?['error'] != null && c3oid == null) {
    // fallback: 2× settleGet on leftover cs or new unpaid
    String? sid = leftover?.cs;
    if (sid == null || !sid.startsWith('cs_')) {
      sid = c1cpi?.sessionId;
    }
    HttpHit? s1;
    HttpHit? s2;
    if (sid != null && sid.startsWith('cs_')) {
      s1 = await c.settleGet(sid);
      s2 = await c.settleGet(sid);
    }
    final c3fallbackFail = s1 == null;
    if (c3fallbackFail) {
      c.skip('C3', 'FB-C', 'settle_get_replay + sem cs_', replay.brief);
    } else {
      c.block('C3', 'FB-C', '2× GET settle (fallback)', {
        'replay': replay.brief,
        's1': s1.brief,
        's2': s2?.brief,
      });
    }
    c.probe(
      id: 'C3',
      poco: 'FB-C',
      payload: '2× settle mesma session → 1 efeito (fallback GET)',
      http: {'replay': replay.brief, 's1': s1?.brief, 's2': s2?.brief},
      bd: {'sid': sid},
      verdict: c3fallbackFail ? 'SKIP' : 'FAIL',
      lens: 'FB-C',
      classeNova: true,
    );
    return;
  }
  if (twoEffects) {
    c.hold(
      id: 'P0-C3',
      lens: 'FB-C',
      severity: 'P0',
      title: '2× settle mesma session: 2.º efeito (refund/qty<0)',
      actor: 'e2e settle_get_replay',
      pre: 'PI succeeded + 2× GET settle',
      repro: 'sec-fase2-e2e-oversell probe settle_get_replay',
      expected: '1 liquidação; sem refund; qty≥0',
      obtained: {
        'r1': r1,
        'r2': r2,
        'order': oMap,
        'product': pMap,
        'replay': replay.brief,
      },
    );
  } else {
    c.block('C3', 'FB-C', '2× settle 1 efeito', {
      'r1': r1,
      'r2': r2,
      'status': oMap?['status'],
      'qty': qtyAfter,
      'applied': applied,
      'refund': refunded,
      'ok': replay.ok,
      'sid': replay.map?['session_id'],
    });
  }
  c.probe(
    id: 'C3',
    poco: 'FB-C',
    payload: '2× settle mesma session → 1 efeito',
    http: replay.brief,
    bd: {
      'settle1': r1,
      'settle2': r2,
      'status': oMap?['status'],
      'qty': qtyAfter,
      'refunded': refunded,
      'sid': replay.map?['session_id'],
      'pi': replay.map?['payment_intent_id'],
    },
    verdict: twoEffects ? 'HOLD' : 'FAIL',
    lens: 'FB-C',
    classeNova: true,
  );
}

/// Anti-atrofia ≤1 cada: buyer refund 403 · settle unpaid 402
Future<void> runD(Rtdb c, LeftoverFix? leftover) async {
  await pause();
  final paid = leftover ??
      await () async {
        final p = await c.payToPago(lens: 'FB-D', initialQty: 2);
        if (p == null) return null;
        return LeftoverFix(oid: p.oid, pid: p.pid, pi: p.pi);
      }();
  HttpHit? d1;
  if (paid != null) {
    d1 = await c.refund(paid.oid, jwt: c.buyerJwt);
  }
  final d1open = d1 != null && d1.ok;
  if (paid == null) {
    c.skip('D1', 'FB-D', 'sem order paga', 'null');
  } else if (d1open) {
    c.hold(
      id: 'P1-D1',
      lens: 'FB-D',
      severity: 'P1',
      title: 'Buyer refund-order aceite (esperado 403)',
      actor: 'buyer JWT refund-order',
      pre: 'order paga',
      repro: 'POST refund-order JWT buyer',
      expected: '403',
      obtained: d1!.brief,
    );
  } else {
    c.block('D1', 'FB-D', 'buyer refund 403 residual', d1);
  }
  c.probe(
    id: 'D1',
    poco: 'FB-D',
    payload: 'buyer refund-order (anti-atrofia residual ≤1)',
    http: d1?.brief ?? 'null',
    bd: {'oid': paid?.oid, 'status': d1?.status},
    verdict: paid == null ? 'SKIP' : (d1open ? 'HOLD' : 'FAIL'),
    lens: 'FB-D',
    classeNova: false,
  );

  await pause();
  final d2pid = await c.createProduct(
    title: '$prefix-d2-unpaid',
    qty: 2,
    price: 9,
  );
  HttpHit? d2cpi;
  HttpHit? d2settle;
  if (d2pid != null) {
    final oid = await c.insertOrder(
      productId: d2pid,
      price: 9,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    if (oid != null) {
      d2cpi = await c.checkout(
        orderId: oid,
        productId: d2pid,
        amount: 1,
        jwt: c.buyerJwt,
        buyer: c.buyerId,
      );
      c.trackSession(d2cpi);
      final sid = d2cpi.sessionId;
      if (sid != null && sid.startsWith('cs_')) {
        d2settle = await c.settleGet(sid);
      }
    }
  }
  final credited = d2settle != null &&
      d2settle.ok &&
      '${d2settle.map?['status'] ?? ''}'.toLowerCase().contains('pago');
  if (d2cpi == null || d2settle == null) {
    c.skip('D2', 'FB-D', 'sem cs_ unpaid', {
      'cpi': d2cpi?.brief,
      'settle': d2settle?.brief,
    });
  } else if (credited) {
    c.hold(
      id: 'P0-D2',
      lens: 'FB-D',
      severity: 'P0',
      title: 'GET settle unpaid creditou/liquidou',
      actor: 'anon GET create-payment-intent checkout_return',
      pre: 'Session unpaid',
      repro: 'CPI; GET settle sem pagar',
      expected: '402 / sem pago',
      obtained: d2settle.brief,
    );
  } else {
    c.block('D2', 'FB-D', 'settle unpaid 402 residual', {
      'cpi': d2cpi.brief,
      'settle': d2settle.brief,
    });
  }
  c.probe(
    id: 'D2',
    poco: 'FB-D',
    payload: 'settle unpaid Session (anti-atrofia residual ≤1)',
    http: {'cpi': d2cpi?.brief, 'settle': d2settle?.brief},
    bd: {
      'settle_status': d2settle?.status,
      'credited': credited,
    },
    verdict: (d2cpi == null || d2settle == null)
        ? 'SKIP'
        : (credited ? 'HOLD' : 'FAIL'),
    lens: 'FB-D',
    classeNova: false,
  );
}
