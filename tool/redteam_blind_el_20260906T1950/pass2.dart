/// Confirm A1 idêntico, B1 6∥4 t=0, B3 expand 50ms, B5 bag∥single, B7 triângulo.
/// Oráculo: 2 cs_ distintas HTTP 200 reused=false = dual (GATE). Sem correções.
import 'dart:io';

import '_rtel.dart';

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

  bool dualCreate(List<HttpHit> hits) {
    final created = hits
        .where((h) =>
            h.ok &&
            (h.sessionId ?? '').startsWith('cs_') &&
            h.reused != true)
        .map((h) => h.sessionId!)
        .toSet();
    if (created.length >= 2) return true;
    return csOf(hits).length >= 2;
  }

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
    final settles = <Map<String, Object?>>[];
    for (final sid in csOf(hits)) {
      final s = await c.settleGet(sid);
      settles.add({'sid': sid, 'settle': s.status, 'brief': s.brief});
    }
    return {
      'status': hits.map((h) => h.status).toList(),
      'sids': csOf(hits).toList(),
      'reused': hits.map((h) => h.reused).toList(),
      'stored': stored,
      'dual_create': dualCreate(hits),
      'briefs': hits.map((h) => h.brief).toList(),
      'settle': settles,
    };
  }

  final a1 = await mk(3, 'a1');
  Map<String, Object?> a1out = {'n': a1.length};
  if (a1.length == 3) {
    final same = lines(a1);
    final hits = await parallel([
      c.checkoutBag(lines: same, amount: 1),
      c.checkoutBag(lines: same, amount: 1),
    ]);
    a1out = await pack(a1, hits);
  }

  await Future<void>.delayed(const Duration(milliseconds: 500));
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
  final b3 = await mk(4, 'b3');
  Map<String, Object?> b3out = {'n': b3.length};
  if (b3.length == 4) {
    final hits = await parallel([
      c.checkoutBag(lines: lines(b3.sublist(0, 2)), amount: 1),
      Future<HttpHit>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return c.checkoutBag(lines: lines(b3), amount: 1);
      }),
    ]);
    b3out = await pack(b3, hits);
  }

  await Future<void>.delayed(const Duration(milliseconds: 500));
  final b5 = await mk(5, 'b5');
  Map<String, Object?> b5out = {'n': b5.length};
  if (b5.length == 5) {
    final midC = b5[2];
    final hits = await parallel([
      c.checkoutBag(lines: lines(b5), amount: 1),
      c.checkout(orderId: midC.oid, productId: midC.pid, amount: 1),
    ]);
    b5out = await pack(b5, hits);
  }

  await Future<void>.delayed(const Duration(milliseconds: 500));
  final b7 = await mk(3, 'b7');
  Map<String, Object?> b7out = {'n': b7.length};
  if (b7.length == 3) {
    final hits = await parallel([
      c.checkoutBag(lines: lines([b7[0], b7[1]]), amount: 1),
      c.checkoutBag(lines: lines([b7[1], b7[2]]), amount: 1),
      c.checkoutBag(lines: lines([b7[2], b7[0]]), amount: 1),
    ]);
    b7out = await pack(b7, hits);
  }

  await dumpJson('${outDir()}/pass2.json', {
    'stamp': stamp,
    'A1_identico': a1out,
    'B1_6x4_0ms': b1out,
    'B3_expand50': b3out,
    'B5_bag_single': b5out,
    'B7_triangulo': b7out,
  });
  stdout.writeln('PASS2 A1 $a1out');
  stdout.writeln('PASS2 B1 $b1out');
  stdout.writeln('PASS2 B3 $b3out');
  stdout.writeln('PASS2 B5 $b5out');
  stdout.writeln('PASS2 B7 $b7out');
}
