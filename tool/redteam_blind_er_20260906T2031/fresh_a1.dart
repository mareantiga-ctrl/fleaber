/// A1 em buyer fresco (sem mutex prévio). Sem pagar. Sem correções.
import 'dart:io';

import '_rter.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();
  final email = '${prefix.toLowerCase()}-b4@fleaber.test';
  const pass = 'Rter2031b4!xK';
  final id = await c.ensureNamed(
    email: email,
    pass: pass,
    handle: 'rter2031b4',
    name: '$prefix-B4',
  );
  final jwt = await c.signIn(email, pass);
  c.buyerId = id;
  c.buyerJwt = jwt;
  stdout.writeln('ER fresh-buyer A1 buyer=$id');

  final skus = <({String oid, String pid, double price})>[];
  for (var i = 0; i < 5; i++) {
    final p = 8.0 + i;
    final pid =
        await c.createProduct(title: '$prefix-fresh-$i', qty: 2, price: p);
    if (pid == null) continue;
    final oid = await c.insertOrder(productId: pid, price: p, jwt: jwt);
    if (oid == null) continue;
    skus.add((oid: oid, pid: pid, price: p));
  }
  if (skus.length != 5) {
    stderr.writeln('mkSkus ${skus.length}');
    exit(2);
  }
  final mid = skus[2];
  final lines = [
    for (final s in skus) {'order_id': s.oid, 'product_id': s.pid},
  ];
  final hits = await parallel([
    c.checkoutBag(lines: lines, amount: 1, jwt: jwt, buyer: id),
    c.checkout(
      orderId: mid.oid,
      productId: mid.pid,
      amount: 1,
      jwt: jwt,
      buyer: id,
    ),
  ]);
  await Future<void>.delayed(const Duration(seconds: 2));
  final stored = [
    for (final s in skus)
      '${(await c.orderRow(s.oid))?['stripe_checkout_session_id'] ?? ''}',
  ];
  final sids = hits
      .map((h) => h.sessionId ?? '')
      .where((s) => s.startsWith('cs_'))
      .toSet();
  final created = hits
      .where((h) =>
          h.ok && (h.sessionId ?? '').startsWith('cs_') && h.reused != true)
      .map((h) => h.sessionId!)
      .toSet();
  final out = {
    'buyer': id,
    'status': hits.map((h) => h.status).toList(),
    'reused': hits.map((h) => h.reused).toList(),
    'sids': sids.toList(),
    'created': created.toList(),
    'dual': created.length >= 2 || sids.length >= 2,
    'stored': stored,
    'briefs': hits.map((h) => h.brief).toList(),
  };
  await dumpJson('${outDir()}/fresh_buyer_a1.json', out);
  stdout.writeln(
    'FRESH dual=${out['dual']} http=${out['status']} reused=${out['reused']} '
    'cs_n=${sids.length}',
  );
}
