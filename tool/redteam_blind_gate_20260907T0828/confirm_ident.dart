/// GATE confirm B3 — 2× bag idêntico num comprador fresco.
import 'dart:io';

import '_rtgate.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  final actor = await c.mintBuyer('b3id');
  c.buyerId = actor.id;
  c.buyerJwt = actor.jwt;
  final skus = <({String oid, String pid, double price})>[];
  for (var i = 0; i < 3; i++) {
    final p = 9.0 + i;
    final pid = await c.createProduct(
      title: '$prefix-b3id-$i',
      qty: 2,
      price: p,
    );
    if (pid == null) continue;
    final oid = await c.insertOrder(productId: pid, price: p, jwt: c.buyerJwt);
    if (oid == null) continue;
    skus.add((oid: oid, pid: pid, price: p));
  }
  final lines = [
    for (final r in skus) {'order_id': r.oid, 'product_id': r.pid},
  ];
  final hits = await Future.wait([
    c.checkoutBag(lines: lines, amount: 1),
    c.checkoutBag(lines: lines, amount: 1),
  ]);
  final sids = hits
      .map((h) => h.sessionId ?? '')
      .where((s) => s.startsWith('cs_'))
      .toSet();
  final stored = [
    for (final r in skus)
      '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
  ];
  final out = {
    'status': hits.map((h) => h.status).toList(),
    'briefs': hits.map((h) => h.brief).toList(),
    'reused': hits.map((h) => h.reused).toList(),
    'sids': sids.toList(),
    'creates': hits
        .where((h) =>
            h.ok &&
            (h.sessionId ?? '').startsWith('cs_') &&
            h.reused != true)
        .map((h) => h.sessionId!)
        .toSet()
        .length,
    'stored': stored,
    'dual': sids.length >= 2,
  };
  await dumpJson('${outDir()}/confirm_ident.json', out);
  stdout.writeln('IDENT $out');
}
