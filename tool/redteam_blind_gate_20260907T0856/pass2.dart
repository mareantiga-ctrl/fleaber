/// GATE pass2 — B2/B3 + C1–C3. A1–A6+B1 já fecharam na pass1 (mesmo stamp).
import 'dart:io';

import '_rtgate.dart';
import 'pass1.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('GATE pass2 staging=${c.url} prefix=$prefix');
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.ensureBuyer3();
  await c.restoreSeller1Published();

  await seedPass1Closed(c);
  await attachLedgers(c);
  await dumpJson('${outDir()}/first_run_seed.json', {
    'from': 'pass1 stdout 20260907T0856',
    'probes': ['A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'B1'],
    'dual_create': false,
  });

  final wallets0 = await c.wallets();
  c.note('wallet.pre2', 'baseline pass2', wallets0, lens: 'G-C', well: 'G-C');

  await runB2(c);
  await runB3(c);
  await runC(c, wallets0);

  final wallets1 = await c.wallets();
  c.note('wallet.post2', 'após pass2', {
    'pre': wallets0,
    'post': wallets1,
  }, lens: 'G-C', well: 'G-C');

  await c.dumpAll('pass2_findings.json');
  final races = c.probes
      .where((p) => '${p['payload']}'.contains('Future.wait'))
      .map((p) => p['probe_id'])
      .toList();
  final novas = c.probes
      .where((p) => p['classe_nova'] == 'SIM')
      .map((p) => p['probe_id'])
      .toList();
  final duals = c.probes.where((p) => p['verdict'] == 'HOLD').toList();
  await dumpJson('${outDir()}/probes.json', {
    'stamp': stamp,
    'prefix': prefix,
    'auditor': 'REDTEAM_BLIND_GATE_BAG_SINGLE_v1',
    'probes': c.probes,
    'n': c.probes.length,
    'races': races,
    'classes_novas': novas,
    'findings': c.findings.length,
    'findings_ids': c.findings.map((f) => f['id']).toList(),
    'overlaps': c.overlapCaptures,
    'dual_holds': duals.map((p) => p['probe_id']).toList(),
  });
  stdout.writeln(
    'DONE probes=${c.probes.length} findings=${c.findings.length} '
    'blocked=${c.blocked.length} skip=${c.skipped.length} '
    'races=${races.length} classe_nova=${novas.length} '
    'overlaps=${c.overlapCaptures.keys.toList()}',
  );
}

void closed({
  required Rtdb c,
  required String id,
  required String poco,
  required String lens,
  required String payload,
  required List<int> status,
  required List<String> sids,
  required List<bool> reused,
  required bool overlap400,
  required String buyer,
  bool classeNova = true,
}) {
  final pack = {
    'status': status,
    'sids': sids,
    'reused': reused,
    'overlap_400': overlap400,
    'creates': 1,
    'dual_create': false,
    'distinct_cs': sids.toSet().length,
    'buyer': buyer,
    'source': 'pass1_live',
  };
  c.overlapCaptures[id] = pack;
  c.note('$id.pack', payload, pack, lens: lens, well: poco);
  c.probe(
    id: id,
    poco: poco,
    payload: payload,
    http: status,
    bd: pack,
    verdict: 'FAIL',
    lens: lens,
    classeNova: classeNova,
  );
  c.block(
    '$id-GATE',
    lens,
    '$id ≤1 create (400 overlapping / reused / may_create)',
    pack,
  );
}

Future<void> seedPass1Closed(Rtdb c) async {
  closed(
    c: c,
    id: 'A1',
    poco: 'G-A',
    lens: 'G-A',
    payload: 'Future.wait bag ABCDE ∥ single C t=0 (fresco)',
    status: [400, 200],
    sids: [
      'cs_test_a17m5I9UkkvFnIjJEM5wEDFksomC06fO6aH8z4LhSyR1sin36qHB8bztlO',
    ],
    reused: [false, false],
    overlap400: true,
    buyer: '0a38d638-f34b-4481-8f64-d581abb9e7b1',
  );
  closed(
    c: c,
    id: 'A2',
    poco: 'G-A',
    lens: 'G-A',
    payload: 'Future.wait bag first → 50ms → single C (fresco)',
    status: [400, 200],
    sids: [
      'cs_test_a1eNnqBNlJuIRSokwdFMerVDWnHYKyDEPU0H5GU7bChDs9YhaRtCnEiPYR',
    ],
    reused: [false, false],
    overlap400: true,
    buyer: 'ccd92fc2-f66e-473a-bd01-c2ab3d768735',
  );
  closed(
    c: c,
    id: 'A3',
    poco: 'G-A',
    lens: 'G-A',
    payload: 'Future.wait single C first → 50ms → bag ABCDE (fresco)',
    status: [200, 400],
    sids: [
      'cs_test_a1Wh51232KTgSatkyYGoLsBMQqj5fh2rbAScjojVMjifnUvSWuZ2GdcA7l',
    ],
    reused: [false, false],
    overlap400: true,
    buyer: 'b8cd1d83-390e-4899-a59b-9bb42548e06b',
  );
  closed(
    c: c,
    id: 'A4',
    poco: 'G-A',
    lens: 'G-A',
    payload: 'Future.wait bag ABC ∥ single B (meio) t=0 (fresco)',
    status: [200, 200],
    sids: [
      'cs_test_a1vVQOAqpeqyKG7E58nePcgnYZq5JmSl3sRc0UBVI0TonoUQnhCY5Ab31W',
    ],
    reused: [true, false],
    overlap400: false,
    buyer: '8122198d-4352-4202-a86c-74ba910c706b',
  );
  closed(
    c: c,
    id: 'A5',
    poco: 'G-A',
    lens: 'G-A',
    payload: 'Future.wait bag ∥ single +200ms ∥ bag (fresco)',
    status: [200, 200, 400],
    sids: [
      'cs_test_a1oJU3AslU34AaGm0GL4A3tBqqkq7UXtiVZMAYmzSf5WXvTRswJEXSod86',
    ],
    reused: [true, false, false],
    overlap400: true,
    buyer: 'fc029260-75f4-4215-b384-bef967a7abf3',
  );
  closed(
    c: c,
    id: 'A6',
    poco: 'G-A',
    lens: 'G-A',
    payload: 'Future.wait bag de 2 first → 200ms → single (fresco)',
    status: [200, 200],
    sids: [
      'cs_test_a10pm1KuyP2NF6FNAZgG7nLDrkrCEtQe6XJ51nKG7qHExsbIW874KBUUKN',
    ],
    reused: [true, false],
    overlap400: false,
    buyer: 'ce5d080f-6abe-403a-9296-c405284aef4a',
  );
  closed(
    c: c,
    id: 'B1',
    poco: 'G-B',
    lens: 'G-B',
    payload: 'Future.wait bag 6∥4 t=0 regressão ≤1',
    status: [400, 200],
    sids: [
      'cs_test_a1yqVBUgNSIlHxL9kTnOiVf2kqiiJZ0fVAZeYUSSN9sEnFBYvfauSq6EZw',
    ],
    reused: [false, false],
    overlap400: true,
    buyer: 'd8e27aef-f5b2-49e7-ab8c-158f0bf7870c',
    classeNova: false,
  );
}

Future<Map<String, Object?>> ordersForSid(Rtdb c, String sid) async {
  final h = await c.rest(
    'GET',
    'orders?stripe_checkout_session_id=eq.$sid&select=id,status,product_id,buyer_id,price_total,stripe_checkout_session_id,stripe_payment_intent_id,amount_paid_cents',
    service: true,
  );
  return {
    'http': h.status,
    'n': h.list.length,
    'rows': [
      for (final raw in h.list)
        if (raw is Map)
          {
            'id': raw['id'],
            'status': raw['status'],
            'pid': raw['product_id'],
            'cs': raw['stripe_checkout_session_id'],
            'pi': raw['stripe_payment_intent_id'],
          },
    ],
  };
}

Future<void> attachLedgers(Rtdb c) async {
  for (final id in ['A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'B1']) {
    final cap = c.overlapCaptures[id];
    if (cap == null) continue;
    final sids = (cap['sids'] as List?)?.map((e) => '$e').toList() ?? [];
    final ledgers = <Map<String, Object?>>[];
    for (final sid in sids) {
      ledgers.add(await ordersForSid(c, sid));
    }
    cap['ledger'] = ledgers;
    c.note('$id.ledger', 'orders por cs_', ledgers, lens: cap['buyer'] == null ? 'G-A' : 'G-A');
  }
}

Future<void> runB2(Rtdb c) async {
  await pause();
  await asFresh(c, 'bxp');
  final b2 = await mkSkus(c, n: 4, tag: 'b2-expand', qty: 2, price: 14);
  if (b2.length == 4) {
    final first = c.checkoutBag(lines: bagLines(b2.sublist(0, 2)), amount: 1);
    final second = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkoutBag(lines: bagLines(b2), amount: 1);
    });
    final hits = await parallel([first, second]);
    await overlapProbe(
      c: c,
      id: 'B2',
      poco: 'G-B',
      lens: 'G-B',
      payload: 'Future.wait subset → 50ms → superset expand (fresco)',
      skus: b2,
      hits: hits,
      expected: '400 no 2.º — nunca 2.ª cs_',
      classeNova: false,
      regression: true,
    );
  } else {
    skipProbe(
      c,
      id: 'B2',
      poco: 'G-B',
      lens: 'G-B',
      payload: 'Future.wait expand 50ms',
      why: 'mkSkus',
    );
  }
}

Future<void> runB3(Rtdb c) async {
  await pause();
  await asFresh(c, 'bid');
  final b3 = await mkSkus(c, n: 3, tag: 'b3-ident', qty: 2, price: 9);
  if (b3.length == 3) {
    final lines = bagLines(b3);
    final hits = await parallel([
      c.checkoutBag(lines: lines, amount: 1),
      c.checkoutBag(lines: lines, amount: 1),
    ]);
    await overlapProbe(
      c: c,
      id: 'B3',
      poco: 'G-B',
      lens: 'G-B',
      payload: 'Future.wait 2× bag idêntico mesma ordem (fresco)',
      skus: b3,
      hits: hits,
      expected: '1 cs_ reused mesmo sid',
      classeNova: false,
    );
  } else {
    skipProbe(
      c,
      id: 'B3',
      poco: 'G-B',
      lens: 'G-B',
      payload: 'Future.wait 2× bag idêntico',
      why: 'mkSkus',
    );
  }
}

Future<void> runC(Rtdb c, Map<String, num> wallets0) async {
  c.wellsTried.add('G-C');
  await asFresh(c, 'c1p');
  final skus = await mkSkus(c, n: 2, tag: 'c1-happy', qty: 2, price: 13);
  Map<String, Object?> pay1 = {'skipped': true};
  Map<String, Object?> snap1 = {};
  String? winner;
  String? url;

  if (skus.length == 2) {
    final hit = await c.checkoutBag(lines: bagLines(skus), amount: 1);
    c.trackSession(hit);
    winner = hit.sessionId;
    url = hit.checkoutUrl;
    c.note('C1.open', 'saco 2 linhas qty=2', hit.brief, lens: 'G-C', well: 'G-C');
    if (winner != null && winner.startsWith('cs_')) {
      pay1 = await c.payCheckout4242(winner, checkoutUrl: url);
      final pi1 = pay1['pi']?.toString();
      if (pi1 != null && pi1.startsWith('pi_')) {
        final stl = await c.fase2Settle(
          pi: pi1,
          sessionId: winner,
          lines: bagLines(skus),
          bag: true,
        );
        pay1['fase2'] = stl.brief;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
      snap1 = await c.ledgerSnap(skus);
    }
  }

  final paid1 = pay1['paid'] == true;
  final orders1 = (snap1['orders'] as List?) ?? [];
  final products1 = (snap1['products'] as List?) ?? [];
  final hub1 = (snap1['hub'] as List?) ?? [];
  final pagos1 = orders1.where((o) {
    if (o is! Map) return false;
    return '${o['status']}'.toLowerCase() == 'pago';
  }).length;
  final leftoverOk = products1.isNotEmpty &&
      products1.every((p) {
        if (p is! Map) return false;
        final q = numOf(p['qty']) ?? -99;
        return q == 1;
      });
  final hubLists = hub1.isNotEmpty &&
      hub1.every((h) {
        if (h is! Map) return false;
        return (numOf(h['n']) ?? 0) >= 1;
      });

  var c1ok = paid1 && pagos1 == skus.length && leftoverOk;
  if (!paid1) {
    final e2e = await c.payToPago(lens: 'G-C', initialQty: 2);
    Map<String, Object?> leftover = {};
    if (e2e != null) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final prod = await c.productRow(e2e.pid);
      final hub = await c.hubSku(e2e.pid);
      final ord = await c.orderRow(e2e.oid);
      leftover = {
        'via': 'e2e setup_paid_order fallback',
        'oid': e2e.oid,
        'pid': e2e.pid,
        'pi': e2e.pi,
        'order_status': ord?['status'],
        'qty': prod?['quantity'],
        'hub_n': hub.list.length,
      };
      c1ok = '${ord?['status']}'.toLowerCase() == 'pago' &&
          (numOf(prod?['quantity']) ?? -1) == 1;
    }
    c.probe(
      id: 'C1',
      poco: 'G-C',
      payload:
          'pago 4242 do link útil + Hub leftover (fallback e2e se API 4242 falhou)',
      http: {'pay_useful': pay1, 'winner': winner, 'wallets0': wallets0},
      bd: {
        'snap': snap1,
        'leftover_e2e': leftover,
        'pagos': pagos1,
        'leftover_ok': leftoverOk,
        'hub_lists': hubLists,
      },
      verdict: c1ok ? 'FAIL' : 'HOLD',
      lens: 'G-C',
      classeNova: true,
    );
    if (!c1ok && !c.findings.any((f) => f['id'] == 'P1-C1')) {
      c.hold(
        id: 'P1-C1',
        lens: 'G-C',
        severity: 'P1',
        title: 'pago 4242 do link útil / leftover Hub incoerente',
        actor: 'buyer JWT + Stripe TEST 4242',
        pre: 'saco 2 linhas qty=2',
        repro: 'payCheckout4242 / setup_paid_order; ledgerSnap Hub',
        expected: 'pago; qty leftover=1; Hub lista resto',
        obtained: {'pay1': pay1, 'snap': snap1, 'leftover': leftover},
      );
    }
  } else {
    c.probe(
      id: 'C1',
      poco: 'G-C',
      payload: 'pago 4242 do link útil (saco 2) + Hub leftover qty 2→1',
      http: pay1,
      bd: {
        'winner': winner,
        'pagos': pagos1,
        'leftover_ok': leftoverOk,
        'hub_lists': hubLists,
        'orders': orders1,
        'products': products1,
        'hub': hub1,
      },
      verdict: c1ok ? 'FAIL' : 'HOLD',
      lens: 'G-C',
      classeNova: true,
    );
    if (!c1ok && !c.findings.any((f) => f['id'] == 'P1-C1')) {
      c.hold(
        id: 'P1-C1',
        lens: 'G-C',
        severity: 'P1',
        title: 'link útil pago mas leftover Hub/stock incoerente',
        actor: 'buyer JWT + Stripe TEST 4242',
        pre: 'saco 2 qty=2',
        repro: 'payCheckout4242 winner; ledgerSnap',
        expected: 'todas linhas pago; qty=1 leftover; Hub n≥1',
        obtained: snap1,
      );
    }
  }

  // C2: dual inexistente nesta ronda — caça P0 N/A
  c.probe(
    id: 'C2',
    poco: 'G-C',
    payload:
        'se dual: pagar 2.ª — A1–A6+B1 fecharam com ≤1 cs_ (400 overlapping / reused); sem 2.ª captura',
    http: {
      'A1': c.overlapCaptures['A1']?['status'],
      'A2': c.overlapCaptures['A2']?['status'],
      'A3': c.overlapCaptures['A3']?['status'],
      'A4': c.overlapCaptures['A4']?['sids'],
      'dual_any': false,
    },
    bd: {
      'dual_create': false,
      'sids_A1': c.overlapCaptures['A1']?['sids'],
    },
    verdict: 'FAIL',
    lens: 'G-C',
    classeNova: true,
  );

  // C3 2 buyers qty=1
  await pause();
  c.buyerId = c.buyer3Id;
  c.buyerJwt = c.buyer3Jwt;
  final pid = await c.createProduct(title: '$prefix-c3-last', qty: 1, price: 11);
  if (pid != null) {
    final o1 = await c.insertOrder(
      productId: pid,
      price: 11,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
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
      final prod = await c.productRow(pid);
      final dualLast = ok >= 2;
      c.probe(
        id: 'C3',
        poco: 'G-C',
        payload: 'Future.wait 2 buyers CPI última unidade qty=1',
        http: briefs,
        bd: {
          'ok': ok,
          'o1': o1,
          'o2': o2,
          'qty': prod?['quantity'],
        },
        verdict: dualLast ? 'HOLD' : 'FAIL',
        lens: 'G-C',
        classeNova: false,
      );
      if (dualLast) {
        c.hold(
          id: 'P0-C3',
          lens: 'G-C',
          severity: 'P0',
          title: '2 buyers Session na última unidade',
          actor: 'buyer + buyer2 JWT',
          pre: 'quantity=1; 2 orders',
          repro: 'Future.wait 2× CPI',
          expected: '1 Session + 1 stock block',
          obtained: {'ok': ok, 'briefs': briefs, 'qty': prod?['quantity']},
        );
      } else {
        c.block('C3-LAST', 'G-C', 'última unidade ≤1 Session', {
          'ok': ok,
          'briefs': briefs,
        });
      }
    } else {
      c.probe(
        id: 'C3',
        poco: 'G-C',
        payload: '2 buyers qty=1 (insert 2.º)',
        http: {'o1': o1, 'o2': o2},
        bd: {'o1': o1, 'o2': o2},
        verdict: o2 == null ? 'FAIL' : 'HOLD',
        lens: 'G-C',
        classeNova: false,
      );
      if (o2 != null) {
        c.hold(
          id: 'P0-C3',
          lens: 'G-C',
          severity: 'P0',
          title: '2.º buyer inseriu hold na última unidade',
          actor: 'buyer + buyer2 JWT',
          pre: 'quantity=1',
          repro: '2× insertOrder',
          expected: '2.º insert 400 stock',
          obtained: {'o1': o1, 'o2': o2},
        );
      } else {
        c.block('C3-LAST', 'G-C', '2.º insert bloqueado no last-unit', {
          'o1': o1,
          'o2': o2,
        });
      }
    }
  } else {
    skipProbe(
      c,
      id: 'C3',
      poco: 'G-C',
      lens: 'G-C',
      payload: '2 buyers qty=1',
      why: 'createProduct',
    );
  }
}
