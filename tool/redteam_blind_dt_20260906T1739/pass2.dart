/// Confirm B1 6∥4, B3 ABCDE∥idx2, B5 bag∥single∥bag, B6/B7 stagger 50ms. Sem correções.
import 'dart:io';

import '_rtdt.dart';

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

  Set<String> openCs(List<HttpHit> hits) => hits
      .map((h) => h.sessionId ?? '')
      .where((s) => s.startsWith('cs_'))
      .toSet();

  Future<Map<String, Object?>> pack(
    List<({String oid, String pid, double price})> skus,
    List<HttpHit> hits,
  ) async {
    final stored = <String>[];
    for (final r in skus) {
      stored.add(
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
      );
    }
    return {
      'status': hits.map((h) => h.status).toList(),
      'sids': openCs(hits).toList(),
      'reused': hits.map((h) => h.reused).toList(),
      'stored': stored,
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
    final idx2 = b3[1];
    final hits = await parallel([
      c.checkoutBag(lines: lines(b3), amount: 1),
      c.checkout(orderId: idx2.oid, productId: idx2.pid, amount: 1),
    ]);
    b3out = await pack(b3, hits);
  }

  await Future<void>.delayed(const Duration(milliseconds: 500));
  final b5 = await mk(3, 'b5');
  Map<String, Object?> b5out = {'n': b5.length};
  if (b5.length == 3) {
    final three = lines(b5);
    final mid = b5[1];
    final hits = await parallel([
      c.checkoutBag(lines: three, amount: 1),
      Future<HttpHit>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return c.checkout(orderId: mid.oid, productId: mid.pid, amount: 1);
      }),
      c.checkoutBag(lines: three, amount: 1),
    ]);
    b5out = await pack(b5, hits);
  }

  await Future<void>.delayed(const Duration(milliseconds: 500));
  final b6 = await mk(4, 'b6');
  Map<String, Object?> b6out = {'n': b6.length};
  if (b6.length == 4) {
    final hits = await parallel([
      c.checkoutBag(lines: lines(b6), amount: 1),
      Future<HttpHit>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return c.checkoutBag(lines: lines(b6.sublist(0, 2)), amount: 1);
      }),
    ]);
    b6out = await pack(b6, hits);
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
    'B1_6x4': b1out,
    'B3_abcde_idx2': b3out,
    'B5_bag_single_bag': b5out,
    'B6_stag50_full_subset': b6out,
    'B7_stag50_subset_super': b7out,
  });
  stdout.writeln('PASS2 B1=$b1out');
  stdout.writeln('PASS2 B3=$b3out');
  stdout.writeln('PASS2 B5=$b5out');
  stdout.writeln('PASS2 B6=$b6out');
  stdout.writeln('PASS2 B7=$b7out');
}
