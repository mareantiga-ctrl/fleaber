/// Captura checkoutUrl completas (com hash) do overlap 5∥3.
import 'dart:convert';
import 'dart:io';

import '_rtcd.dart';

Future<void> main() async {
  final c = Rtcd.fromEnv(loadEnv());
  await c.loginActors();
  final pool = <({String oid, String pid, double price})>[];
  for (var i = 0; i < 6; i++) {
    final p = 9.0 + i;
    final pid = await c.createProduct(title: '$prefix-p3-ov-$i', qty: 2, price: p);
    if (pid == null) continue;
    final oid = await c.insertOrder(productId: pid, price: p, jwt: c.buyerJwt);
    if (oid == null) continue;
    pool.add((oid: oid, pid: pid, price: p));
  }
  if (pool.length < 6) {
    stderr.writeln('pool ${pool.length}');
    exit(1);
  }
  final big = pool.sublist(0, 5);
  final part = [pool[3], pool[4], pool[5]];
  final hits = await parallel([
    c.checkoutBag(lines: [
      for (final r in big) {'order_id': r.oid, 'product_id': r.pid},
    ], amount: 1),
    c.checkoutBag(lines: [
      for (final r in part) {'order_id': r.oid, 'product_id': r.pid},
    ], amount: 1),
  ]);
  final out = <Map<String, Object?>>[];
  for (var i = 0; i < hits.length; i++) {
    final h = hits[i];
    out.add({
      'i': i,
      'status': h.status,
      'sid': h.sessionId,
      'url': h.map?['checkoutUrl'],
      'amt': h.amountTotal,
      'reused': h.reused,
      'brief': h.brief,
    });
    stdout.writeln('HIT$i sid=${h.sessionId} reused=${h.reused} amt=${h.amountTotal}');
    stdout.writeln('URL$i ${h.map?['checkoutUrl']}');
  }
  final stored = <Map<String, Object?>>[];
  for (final r in pool) {
    final row = await c.orderRow(r.oid);
    stored.add({
      'oid': r.oid,
      'sid': row?['stripe_checkout_session_id'],
    });
  }
  await dumpJson('${outDir()}/pass3_overlap_urls.json', {
    'hits': out,
    'stored': stored,
  });
}
