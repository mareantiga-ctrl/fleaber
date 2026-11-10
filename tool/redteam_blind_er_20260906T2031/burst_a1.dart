/// Burst 8× A1 bag ABCDE ∥ single C t=0. Sem pagar. Sem correções.
import 'dart:io';

import '_rter.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer3();
  c.buyerId = c.buyer3Id;
  c.buyerJwt = c.buyer3Jwt;
  stdout.writeln('ER burst A1 n=8');

  final rounds = <Map<String, Object?>>[];
  var dualN = 0;

  for (var r = 0; r < 8; r++) {
    final skus = <({String oid, String pid, double price})>[];
    for (var i = 0; i < 5; i++) {
      final p = 7.0 + i;
      final pid = await c.createProduct(
        title: '$prefix-burst$r-$i',
        qty: 2,
        price: p,
      );
      if (pid == null) continue;
      final oid = await c.insertOrder(productId: pid, price: p, jwt: c.buyerJwt);
      if (oid == null) continue;
      skus.add((oid: oid, pid: pid, price: p));
    }
    if (skus.length != 5) {
      rounds.add({'r': r, 'skip': 'mkSkus ${skus.length}'});
      continue;
    }
    final mid = skus[2];
    final lines = [
      for (final s in skus) {'order_id': s.oid, 'product_id': s.pid},
    ];
    final hits = await parallel([
      c.checkoutBag(lines: lines, amount: 1),
      c.checkout(orderId: mid.oid, productId: mid.pid, amount: 1),
    ]);
    final sids = hits
        .map((h) => h.sessionId ?? '')
        .where((s) => s.startsWith('cs_'))
        .toSet();
    final created = hits
        .where((h) =>
            h.ok &&
            (h.sessionId ?? '').startsWith('cs_') &&
            h.reused != true)
        .map((h) => h.sessionId!)
        .toSet();
    final dual = created.length >= 2 || sids.length >= 2;
    if (dual) dualN++;
    await Future<void>.delayed(const Duration(seconds: 1));
    final stored = [
      for (final s in skus)
        '${(await c.orderRow(s.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    final row = {
      'r': r,
      'status': hits.map((h) => h.status).toList(),
      'reused': hits.map((h) => h.reused).toList(),
      'sids': sids.toList(),
      'created': created.toList(),
      'dual': dual,
      'stored_n_cs': stored.where((s) => s.startsWith('cs_')).length,
      'stored_unique': stored.where((s) => s.startsWith('cs_')).toSet().toList(),
    };
    rounds.add(row);
    stdout.writeln(
      'BURST r=$r dual=$dual http=${row['status']} reused=${row['reused']} '
      'cs_n=${sids.length}',
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  await dumpJson('${outDir()}/burst_a1.json', {
    'stamp': stamp,
    'n': rounds.length,
    'dual_n': dualN,
    'rounds': rounds,
  });
  stdout.writeln('BURST DONE dual=$dualN/${rounds.length}');
}
