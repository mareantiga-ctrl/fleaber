/// Confirm A1 fresco + A1 no mesmo comprador após claim. Sem pagar as duas.
import 'dart:io';

import '_rter.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();
  stdout.writeln('ER confirm staging=${c.url}');

  Future<List<({String oid, String pid, double price})>> mk(
    String tag,
    String jwt,
  ) async {
    final out = <({String oid, String pid, double price})>[];
    for (var i = 0; i < 5; i++) {
      final p = 8.0 + i;
      final pid =
          await c.createProduct(title: '$prefix-cf-$tag-$i', qty: 2, price: p);
      if (pid == null) continue;
      final oid = await c.insertOrder(productId: pid, price: p, jwt: jwt);
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
      'created_false': hits
          .where((h) =>
              h.ok &&
              (h.sessionId ?? '').startsWith('cs_') &&
              h.reused != true)
          .map((h) => h.sessionId)
          .toSet()
          .toList(),
      'reused': hits.map((h) => h.reused).toList(),
      'stored': stored,
      'dual_create': dualCreate(hits),
      'briefs': hits.map((h) => h.brief).toList(),
      'settle': settles,
    };
  }

  Future<Map<String, Object?>> raceA1({
    required String tag,
    required String jwt,
    required String buyer,
  }) async {
    c.buyerId = buyer;
    c.buyerJwt = jwt;
    final skus = await mk(tag, jwt);
    final mid = skus[2];
    final hits = await parallel([
      c.checkoutBag(lines: lines(skus), amount: 1, jwt: jwt, buyer: buyer),
      c.checkout(
        orderId: mid.oid,
        productId: mid.pid,
        amount: 1,
        jwt: jwt,
        buyer: buyer,
      ),
    ]);
    return pack(skus, hits);
  }

  final fresh = await c.mintBuyer('cf1');
  final a1Fresh = await raceA1(tag: 'fresh', jwt: fresh.jwt, buyer: fresh.id);

  final a1Again = await raceA1(tag: 'again', jwt: fresh.jwt, buyer: fresh.id);

  final fresh2 = await c.mintBuyer('cf2');
  c.buyerId = fresh2.id;
  c.buyerJwt = fresh2.jwt;
  final skus = await mk('a3', fresh2.jwt);
  final mid = skus[2];
  final single = c.checkout(
    orderId: mid.oid,
    productId: mid.pid,
    amount: 1,
    jwt: fresh2.jwt,
    buyer: fresh2.id,
  );
  final bag = Future<HttpHit>(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return c.checkoutBag(
      lines: lines(skus),
      amount: 1,
      jwt: fresh2.jwt,
      buyer: fresh2.id,
    );
  });
  final a3Hits = await parallel([single, bag]);
  final a3 = await pack(skus, a3Hits);

  final out = {
    'a1_fresh': a1Fresh,
    'a1_same_buyer_again': a1Again,
    'a3_single_first_fresh': a3,
  };
  await dumpJson('${outDir()}/confirm.json', out);
  stdout.writeln(
    'CONFIRM a1_fresh.dual=${a1Fresh['dual_create']} '
    'a1_again.dual=${a1Again['dual_create']} '
    'a3_fresh.dual=${a3['dual_create']}',
  );
}
