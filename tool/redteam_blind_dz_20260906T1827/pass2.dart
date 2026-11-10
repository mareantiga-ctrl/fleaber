/// Confirm B1 6∥4 0ms, B3 ABCDE∥C, B7 expand 50ms. Oráculo open/payable. Sem correções.
import 'dart:io';

import '_rtdz.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer3();
  c.buyerId = c.buyer3Id;
  c.buyerJwt = c.buyer3Jwt;

  Future<List<({String oid, String pid, double price})>> mk(
    int n,
    String tag,
  ) async {
    final out = <({String oid, String pid, double price})>[];
    for (var i = 0; i < n; i++) {
      final p = 9.0 + i;
      final pid =
          await c.createProduct(title: '$prefix-p2-$tag-$i', qty: 2, price: p);
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

  Set<String> csOf(List<HttpHit> hits) => hits
      .map((h) => h.sessionId ?? '')
      .where((s) => s.startsWith('cs_'))
      .toSet();

  Future<Map<String, Object?>> pack(
    List<({String oid, String pid, double price})> skus,
    List<HttpHit> hits,
  ) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final stored = <String>[];
    for (final r in skus) {
      stored.add(
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
      );
    }
    final urls = <String, String?>{};
    for (final h in hits) {
      final sid = h.sessionId;
      if (sid != null && sid.startsWith('cs_')) urls[sid] = h.checkoutUrl;
    }
    var payable = 0;
    final oracle = <Map<String, Object?>>[];
    for (final sid in csOf(hits)) {
      final o = await c.sessionOracle(sid, checkoutUrl: urls[sid]);
      oracle.add(Map<String, Object?>.from(o));
      if (o['open_payable'] == true) payable++;
    }
    return {
      'status': hits.map((h) => h.status).toList(),
      'sids': csOf(hits).toList(),
      'reused': hits.map((h) => h.reused).toList(),
      'stored': stored,
      'payable_open': payable,
      'oracle': oracle,
    };
  }

  final b1 = await mk(6, 'b1');
  Map<String, Object?> b1out = {'n': b1.length};
  if (b1.length == 6) {
    final hits = await parallel([
      c.checkoutBag(lines: lines(b1), amount: 1),
      c.checkoutBag(lines: lines(b1.sublist(1, 5)), amount: 1),
    ]);
    b1out = await pack(b1, hits);
  }

  await Future<void>.delayed(const Duration(milliseconds: 500));
  final b3 = await mk(5, 'b3');
  Map<String, Object?> b3out = {'n': b3.length};
  if (b3.length == 5) {
    final midC = b3[2];
    final hits = await parallel([
      c.checkoutBag(lines: lines(b3), amount: 1),
      c.checkout(orderId: midC.oid, productId: midC.pid, amount: 1),
    ]);
    b3out = await pack(b3, hits);
  }

  await Future<void>.delayed(const Duration(milliseconds: 500));
  final b7 = await mk(4, 'b7');
  Map<String, Object?> b7out = {'n': b7.length};
  if (b7.length == 4) {
    final hits = await parallel([
      c.checkoutBag(lines: lines(b7.sublist(0, 2)), amount: 1),
      Future<HttpHit>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return c.checkoutBag(lines: lines(b7), amount: 1);
      }),
    ]);
    b7out = await pack(b7, hits);
  }

  await dumpJson('${outDir()}/pass2.json', {
    'stamp': stamp,
    'B1_6x4_0ms': b1out,
    'B3_ABCDE_C': b3out,
    'B7_expand50': b7out,
  });
  stdout.writeln('PASS2 $b1out');
  stdout.writeln('PASS2 $b3out');
  stdout.writeln('PASS2 $b7out');
}
