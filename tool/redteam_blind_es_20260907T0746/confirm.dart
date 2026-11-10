/// ES confirm — bag∥single t=0 num buyer fresco (não reutilizar IDs da ronda anterior).
import 'dart:io';
import '_rtes.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();
  final email = '${prefix.toLowerCase()}-b5@fleaber.test';
  const pass = 'Rtes0746b5!xK';
  final id = await c.ensureNamed(
    email: email,
    pass: pass,
    handle: 'rtes0746b5',
    name: '$prefix-B5',
  );
  final jwt = await c.signIn(email, pass);
  c.buyerId = id;
  c.buyerJwt = jwt;
  stdout.writeln('ES confirm fresh buyer5=$id');

  final skus = <({String oid, String pid, double price})>[];
  for (var i = 0; i < 5; i++) {
    final p = 7.0 + i;
    final pid =
        await c.createProduct(title: '$prefix-p2-a1-$i', qty: 1, price: p);
    if (pid == null) continue;
    final oid = await c.insertOrder(productId: pid, price: p, jwt: jwt);
    if (oid == null) continue;
    skus.add((oid: oid, pid: pid, price: p));
  }

  Map<String, Object?> confirm = {'mk': skus.length};
  if (skus.length == 5) {
    final mid = skus[2];
    final hits = await parallel([
      c.checkoutBag(
        lines: [
          for (final r in skus) {'order_id': r.oid, 'product_id': r.pid},
        ],
        amount: 1,
        jwt: jwt,
        buyer: id,
      ),
      c.checkout(
        orderId: mid.oid,
        productId: mid.pid,
        amount: 1,
        jwt: jwt,
        buyer: id,
      ),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
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
    final stored = <String>[];
    for (final r in skus) {
      stored.add(
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
      );
    }
    confirm = {
      'buyer': id,
      'status': hits.map((h) => h.status).toList(),
      'briefs': hits.map((h) => h.brief).toList(),
      'sids': sids,
      'urls': urls,
      'reused': hits.map((h) => h.reused).toList(),
      'distinct': sids.length,
      'creates': hits.where((h) => h.ok && !h.reused).length,
      'dual_create':
          sids.length >= 2 && hits.where((h) => h.ok && !h.reused).length >= 2,
      'stored': stored,
      'skus': [
        for (final s in skus) {'oid': s.oid, 'pid': s.pid, 'price': s.price},
      ],
      'ledger': await c.ledgerSnap(skus),
    };
  }

  await dumpJson('${outDir()}/confirm.json', confirm);
  stdout.writeln(
    'confirm dual=${confirm['dual_create']} distinct=${confirm['distinct']} '
    'creates=${confirm['creates']} status=${confirm['status']}',
  );
}
