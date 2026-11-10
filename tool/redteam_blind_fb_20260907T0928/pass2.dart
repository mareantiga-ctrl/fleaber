/// RED TEAM CEGO FB pass2 — fechar D2 SKIP + C3 paid settle 2× + B3 bag e2e 2 linhas.
/// Sem correções. Stripe TEST.
import 'dart:io';

import '_rtfb.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('FB pass2 staging=${c.url} prefix=$prefix');
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.restoreSeller1Published();
  final fresh = await c.mintBuyer('d2x');
  c.buyerId = fresh.id;
  c.buyerJwt = fresh.jwt;

  await passD2(c);
  await passC3paid(c);
  await passB3e2e(c);

  await c.dumpAll('pass2_findings.json');
  await dumpJson('${outDir()}/pass2_probes.json', {
    'stamp': stamp,
    'prefix': prefix,
    'probes': c.probes,
    'findings': c.findings,
    'n': c.probes.length,
  });
  stdout.writeln(
    'PASS2 probes=${c.probes.length} findings=${c.findings.length} '
    'blocked=${c.blocked.length} skip=${c.skipped.length}',
  );
}

Future<void> passD2(Rtdb c) async {
  final pid = await c.createProduct(
    title: '$prefix-d2x-unpaid',
    qty: 2,
    price: 9,
  );
  HttpHit? cpi;
  HttpHit? settle;
  if (pid != null) {
    final oid = await c.insertOrder(
      productId: pid,
      price: 9,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    if (oid != null) {
      cpi = await c.checkout(
        orderId: oid,
        productId: pid,
        amount: 1,
        jwt: c.buyerJwt,
        buyer: c.buyerId,
      );
      c.trackSession(cpi);
      final sid = cpi.sessionId;
      if (sid != null && sid.startsWith('cs_')) {
        settle = await c.settleGet(sid);
      }
    }
  }
  final credited = settle != null &&
      settle.ok &&
      '${settle.map?['status'] ?? ''}'.toLowerCase().contains('pago');
  if (cpi == null || settle == null) {
    c.skip('D2', 'FB-D', 'sem cs_ unpaid pass2', {
      'cpi': cpi?.brief,
      'settle': settle?.brief,
    });
  } else if (credited) {
    c.hold(
      id: 'P0-D2',
      lens: 'FB-D',
      severity: 'P0',
      title: 'GET settle unpaid creditou/liquidou',
      actor: 'buyer d2x JWT',
      pre: 'Session unpaid',
      repro: 'CPI; GET settle sem pagar',
      expected: '402 / sem pago',
      obtained: settle.brief,
    );
  } else {
    c.block('D2', 'FB-D', 'settle unpaid 402 residual pass2', {
      'cpi': cpi.brief,
      'settle': settle.brief,
    });
  }
  c.probe(
    id: 'D2',
    poco: 'FB-D',
    payload: 'settle unpaid Session (anti-atrofia residual ≤1) pass2 fresco',
    http: {'cpi': cpi?.brief, 'settle': settle?.brief},
    bd: {'settle_status': settle?.status, 'credited': credited},
    verdict: (cpi == null || settle == null)
        ? 'SKIP'
        : (credited ? 'HOLD' : 'FAIL'),
    lens: 'FB-D',
    classeNova: false,
  );
}

Future<void> passC3paid(Rtdb c) async {
  const oid = '2a112865-03b8-4eea-8055-d4a35d3271c3';
  const pid = 'f6866de1-b0e4-4195-b2d8-eb762e3f7489';
  const pi = 'pi_3UCxztH7FWYUN3jh0I9oohI0';
  final w0 = await c.walletBal(c.sellerId);
  final before = await c.orderRow(oid);
  final prod0 = await c.productRow(pid);
  final s1 = await c.fase2Settle(pi: pi, orderId: oid, productId: pid);
  final s2 = await c.fase2Settle(pi: pi, orderId: oid, productId: pid);
  await Future<void>.delayed(const Duration(seconds: 2));
  final after = await c.orderRow(oid);
  final prod1 = await c.productRow(pid);
  final w1 = await c.walletBal(c.sellerId);
  final q0 = numOf(prod0?['quantity']);
  final q1 = numOf(prod1?['quantity']);
  final dW = w1 - w0;
  final qtyDrop = q1 != null && q0 != null && q1 < q0;
  final two = (dW.abs() > 0.001) || qtyDrop;
  if (two) {
    c.hold(
      id: 'P0-C3',
      lens: 'FB-C',
      severity: 'P0',
      title: '2× settle PI pago: 2.º efeito (wallet/qty)',
      actor: 'fase2_e2e_settle ×2',
      pre: 'PI succeeded leftover já pago+released',
      repro: '2× POST fase2_e2e_settle mesmo pi_',
      expected: '1 efeito; Δwallet=0; qty estável',
      obtained: {
        's1': s1.brief,
        's2': s2.brief,
        'dW': dW,
        'q0': q0,
        'q1': q1,
        'st0': before?['status'],
        'st1': after?['status'],
      },
    );
  } else {
    c.block('C3-paid', 'FB-C', '2× settle PI pago 1 efeito', {
      's1': s1.brief,
      's2': s2.brief,
      'dW': dW,
      'q0': q0,
      'q1': q1,
      'st0': before?['status'],
      'st1': after?['status'],
    });
  }
  c.probe(
    id: 'C3-paid',
    poco: 'FB-C',
    payload: '2× fase2Settle mesma PI paga leftover → 1 efeito',
    http: {'s1': s1.brief, 's2': s2.brief},
    bd: {
      'dW': dW,
      'q0': q0,
      'q1': q1,
      'st0': before?['status'],
      'st1': after?['status'],
      'applied0': before?['stock_units_applied'],
      'applied1': after?['stock_units_applied'],
    },
    verdict: two ? 'HOLD' : 'FAIL',
    lens: 'FB-C',
    classeNova: true,
  );
}

Future<void> passB3e2e(Rtdb c) async {
  final bag = await c.setupPaidBag();
  final m = bag.map ?? {};
  final oidA = m['order_a_id']?.toString();
  final oidB = m['order_b_id']?.toString();
  if (oidA != null) c.createdOrderIds.add(oidA);
  if (oidB != null) c.createdOrderIds.add(oidB);
  final pidA = m['product_a_id']?.toString();
  final pidB = m['product_b_id']?.toString();
  if (pidA != null) c.createdProductIds.add(pidA);
  if (pidB != null) c.createdProductIds.add(pidB);
  Map<String, dynamic>? a;
  Map<String, dynamic>? b;
  if (oidA != null) a = await c.orderRow(oidA);
  if (oidB != null) b = await c.orderRow(oidB);
  final stA = '${a?['status'] ?? ''}';
  final stB = '${b?['status'] ?? ''}';
  final both = stA.toLowerCase() == 'pago' && stB.toLowerCase() == 'pago';
  final none = stA.toLowerCase() != 'pago' && stB.toLowerCase() != 'pago';
  final half = !both && !none && oidA != null && oidB != null;
  if (!bag.ok || oidA == null) {
    c.skip('B3e2e', 'FB-B', 'setup_paid_bag fail', bag.brief);
  } else if (half) {
    c.hold(
      id: 'P0-B3',
      lens: 'FB-B',
      severity: 'P0',
      title: 'Saco e2e meia liquidação',
      actor: 'setup_paid_bag 4242',
      pre: '2 linhas mesmo PI',
      repro: 'setup_paid_bag; orders.status',
      expected: 'ambas pago ou nenhuma',
      obtained: {'stA': stA, 'stB': stB, 'bag': bag.brief},
    );
  } else {
    c.block('B3e2e', 'FB-B', 'saco e2e 2 linhas atómico', {
      'stA': stA,
      'stB': stB,
      'both': both,
      'pi': m['payment_intent_id'],
      'paid_a': m['paid_a'],
      'paid_b': m['paid_b'],
    });
  }
  c.probe(
    id: 'B3e2e',
    poco: 'FB-B',
    payload: 'setup_paid_bag 2 lines (apoio B3: captura 4-line sem sk_test_)',
    http: bag.brief,
    bd: {
      'stA': stA,
      'stB': stB,
      'both': both,
      'half': half,
      'pi': m['payment_intent_id'],
      'pi_amt': m['pi_amount_cents'],
      'paid_a': m['paid_a'],
      'paid_b': m['paid_b'],
    },
    verdict: (!bag.ok || oidA == null)
        ? 'SKIP'
        : (half ? 'HOLD' : 'FAIL'),
    lens: 'FB-B',
    classeNova: false,
  );
}
