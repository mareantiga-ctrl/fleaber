/// ES A1 fresco — bag∥single t=0 + dump URLs para pagar 4242.
import 'dart:io';
import '_rtes.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();
  final email = '${prefix.toLowerCase()}-b4@fleaber.test';
  const pass = 'Rtes2115b4!xK';
  final id = await c.ensureNamed(
    email: email,
    pass: pass,
    handle: 'rtes2115b4',
    name: '$prefix-B4',
  );
  final jwt = await c.signIn(email, pass);
  c.buyerId = id;
  c.buyerJwt = jwt;
  stdout.writeln('ES A1 fresh buyer=$id');

  final skus = <({String oid, String pid, double price})>[];
  for (var i = 0; i < 5; i++) {
    final p = 7.0 + i;
    final pid =
        await c.createProduct(title: '$prefix-a1pay-$i', qty: 1, price: p);
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
      .toSet()
      .toList();
  final urls = <String, String?>{};
  for (final h in hits) {
    final sid = h.sessionId;
    if (sid != null && sid.startsWith('cs_')) urls[sid] = h.checkoutUrl;
  }
  final created = hits
      .where((h) =>
          h.ok && (h.sessionId ?? '').startsWith('cs_') && h.reused != true)
      .map((h) => h.sessionId!)
      .toSet();
  final out = {
    'buyer': id,
    'status': hits.map((h) => h.status).toList(),
    'reused': hits.map((h) => h.reused).toList(),
    'sids': sids,
    'created': created.toList(),
    'urls': urls,
    'dual': created.length >= 2 || sids.length >= 2,
    'stored': stored,
    'skus': [
      for (final s in skus) {'oid': s.oid, 'pid': s.pid, 'price': s.price},
    ],
    'briefs': hits.map((h) => h.brief).toList(),
    'ledger': await c.ledgerSnap(skus),
  };
  await dumpJson('${outDir()}/a1_dual.json', out);
  stdout.writeln(
    'A1 dual=${out['dual']} http=${out['status']} reused=${out['reused']} '
    'cs_n=${sids.length}',
  );
  for (final sid in sids) {
    stdout.writeln('URL $sid ${urls[sid]}');
  }
}
