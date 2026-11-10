/// Capture full checkoutUrl (no clip) for 6∥4 and expand 50ms.
import 'dart:io';

import '_rtdz.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer3();
  c.buyerId = c.buyer3Id;
  c.buyerJwt = c.buyer3Jwt;

  Future<List<({String oid, String pid, double price})>> mk(int n, String tag) async {
    final out = <({String oid, String pid, double price})>[];
    for (var i = 0; i < n; i++) {
      final p = 8.0 + i;
      final pid = await c.createProduct(title: '$prefix-cap-$tag-$i', qty: 2, price: p);
      if (pid == null) continue;
      final oid = await c.insertOrder(productId: pid, price: p, jwt: c.buyerJwt);
      if (oid == null) continue;
      out.add((oid: oid, pid: pid, price: p));
    }
    return out;
  }

  List<Map<String, Object?>> lines(Iterable<({String oid, String pid, double price})> rows) =>
      [for (final r in rows) {'order_id': r.oid, 'product_id': r.pid}];

  Map<String, Object?> hitMap(HttpHit h) => {
        'status': h.status,
        'sid': h.sessionId,
        'url': h.checkoutUrl,
        'reused': h.reused,
        'body': h.body,
      };

  final b1 = await mk(6, 'b1');
  final b1hits = await parallel([
    c.checkoutBag(lines: lines(b1), amount: 1),
    c.checkoutBag(lines: lines(b1.sublist(1, 5)), amount: 1),
  ]);
  final stored1 = [
    for (final r in b1)
      '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
  ];

  await Future<void>.delayed(const Duration(milliseconds: 400));
  final b7 = await mk(4, 'b7');
  final b7hits = await parallel([
    c.checkoutBag(lines: lines(b7.sublist(0, 2)), amount: 1),
    Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkoutBag(lines: lines(b7), amount: 1);
    }),
  ]);
  final stored7 = [
    for (final r in b7)
      '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
  ];

  final out = {
    'B1': {
      'hits': b1hits.map(hitMap).toList(),
      'stored': stored1,
    },
    'B7': {
      'hits': b7hits.map(hitMap).toList(),
      'stored': stored7,
    },
  };
  await dumpJson('${outDir()}/full_urls.json', out);
  stdout.writeln('B1 sids=${b1hits.map((h) => h.sessionId).toList()} reused=${b1hits.map((h) => h.reused).toList()}');
  stdout.writeln('B1 urls0=${b1hits[0].checkoutUrl}');
  stdout.writeln('B1 urls1=${b1hits[1].checkoutUrl}');
  stdout.writeln('B7 sids=${b7hits.map((h) => h.sessionId).toList()} reused=${b7hits.map((h) => h.reused).toList()}');
  stdout.writeln('B7 urls0=${b7hits[0].checkoutUrl}');
  stdout.writeln('B7 urls1=${b7hits[1].checkoutUrl}');
}
