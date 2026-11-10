/// Confirm B1 5∥3 e B5 bag∥single-meio. Sem correções.
import 'dart:io';

import '_rtdn.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();

  Future<List<({String oid, String pid, double price})>> mk(
    int n,
    String tag,
  ) async {
    final out = <({String oid, String pid, double price})>[];
    for (var i = 0; i < n; i++) {
      final p = 9.0 + i;
      final pid = await c.createProduct(title: '$prefix-p2-$tag-$i', qty: 2, price: p);
      if (pid == null) continue;
      final oid = await c.insertOrder(productId: pid, price: p, jwt: c.buyerJwt);
      if (oid == null) continue;
      out.add((oid: oid, pid: pid, price: p));
    }
    return out;
  }

  List<Map<String, Object?>> lines(
    Iterable<({String oid, String pid, double price})> rows,
  ) =>
      [
        for (final r in rows) {'order_id': r.oid, 'product_id': r.pid},
      ];

  Set<String> openCs(List<HttpHit> hits) => hits
      .map((h) => h.sessionId ?? '')
      .where((s) => s.startsWith('cs_'))
      .toSet();

  final b1 = await mk(5, 'b1');
  Map<String, Object?> b1out = {'n': b1.length};
  if (b1.length == 5) {
    final hits = await parallel([
      c.checkoutBag(lines: lines(b1), amount: 1),
      c.checkoutBag(lines: lines(b1.sublist(1, 4)), amount: 1),
    ]);
    b1out = {
      'status': hits.map((h) => h.status).toList(),
      'sids': openCs(hits).toList(),
      'reused': hits.map((h) => h.reused).toList(),
      'stored': [
        for (final r in b1)
          '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
      ],
    };
  }

  await Future<void>.delayed(const Duration(milliseconds: 500));
  final b5 = await mk(5, 'b5');
  Map<String, Object?> b5out = {'n': b5.length};
  if (b5.length == 5) {
    final mid = b5[2];
    final hits = await parallel([
      c.checkoutBag(lines: lines(b5), amount: 1),
      c.checkout(orderId: mid.oid, productId: mid.pid, amount: 1),
    ]);
    b5out = {
      'status': hits.map((h) => h.status).toList(),
      'sids': openCs(hits).toList(),
      'reused': hits.map((h) => h.reused).toList(),
      'stored': [
        for (final r in b5)
          '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
      ],
    };
  }

  await dumpJson('${outDir()}/pass2.json', {
    'stamp': stamp,
    'B1_5x3': b1out,
    'B5_bag_single_mid': b5out,
  });
  stdout.writeln('PASS2 B1=$b1out');
  stdout.writeln('PASS2 B5=$b5out');
}
