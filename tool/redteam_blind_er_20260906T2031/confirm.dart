/// Confirm A1 bag∥single t=0 e A2 bag first t=50. Sem pagar as duas. Sem correções.
import 'dart:io';

import '_rter.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer3();
  c.buyerId = c.buyer3Id;
  c.buyerJwt = c.buyer3Jwt;
  stdout.writeln('ER confirm staging=${c.url}');

  Future<List<({String oid, String pid, double price})>> mk(
    int n,
    String tag,
  ) async {
    final out = <({String oid, String pid, double price})>[];
    for (var i = 0; i < n; i++) {
      final p = 8.0 + i;
      final pid =
          await c.createProduct(title: '$prefix-cf-$tag-$i', qty: 2, price: p);
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

  final a1 = await mk(5, 'a1');
  Map<String, Object?> a1out = {'n': a1.length};
  if (a1.length == 5) {
    final mid = a1[2];
    final hits = await parallel([
      c.checkoutBag(lines: lines(a1), amount: 1),
      c.checkout(orderId: mid.oid, productId: mid.pid, amount: 1),
    ]);
    a1out = await pack(a1, hits);
  }

  await Future<void>.delayed(const Duration(milliseconds: 700));
  final a2 = await mk(5, 'a2');
  Map<String, Object?> a2out = {'n': a2.length};
  if (a2.length == 5) {
    final mid = a2[2];
    final hits = await parallel([
      c.checkoutBag(lines: lines(a2), amount: 1),
      Future<HttpHit>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return c.checkout(orderId: mid.oid, productId: mid.pid, amount: 1);
      }),
    ]);
    a2out = await pack(a2, hits);
  }

  final out = {
    'stamp': stamp,
    'prefix': prefix,
    'A1_bag_single_t0': a1out,
    'A2_bag_first_50ms': a2out,
    'paid_both': false,
  };
  await dumpJson('${outDir()}/confirm.json', out);
  stdout.writeln(
    'CONFIRM A1 dual=${a1out['dual_create']} sids=${a1out['sids']} '
    'A2 dual=${a2out['dual_create']} sids=${a2out['sids']}',
  );
}
