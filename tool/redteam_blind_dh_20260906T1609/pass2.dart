/// RED TEAM CEGO DH pass2 — confirmar HOLDs B1/B3/C2/C3. Sem correções.
import 'dart:io';

import '_rtdh.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('DH pass2 confirm');
  await c.loginActors();

  Future<List<({String oid, String pid, double price})>> mk(
    String tag,
    int n, {
    double price = 9,
  }) async {
    final out = <({String oid, String pid, double price})>[];
    for (var i = 0; i < n; i++) {
      final p = price + i;
      final pid = await c.createProduct(title: '$prefix-p2-$tag-$i', qty: 2, price: p);
      if (pid == null) continue;
      final oid = await c.insertOrder(
        productId: pid,
        price: p,
        jwt: c.buyerJwt,
      );
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

  // B1 repeat 4∥2
  final b1 = await mk('b1', 4);
  Map<String, Object?> b1out = {'n': b1.length};
  if (b1.length == 4) {
    final hits = await parallel([
      c.checkoutBag(lines: lines(b1), amount: 1),
      c.checkoutBag(lines: lines(b1.sublist(2)), amount: 1),
    ]);
    final sids = hits
        .map((h) => h.sessionId ?? '')
        .where((s) => s.startsWith('cs_'))
        .toSet()
        .toList();
    final stored = [
      for (final r in b1)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    b1out = {
      'briefs': hits.map((h) => h.brief).toList(),
      'sids': sids,
      'n_cs': sids.length,
      'stored': stored,
    };
  }
  stdout.writeln('CONFIRM B1 $b1out');

  // B3 repeat bag∥single
  final b3 = await mk('b3', 4, price: 8);
  Map<String, Object?> b3out = {'n': b3.length};
  if (b3.length == 4) {
    final hits = await parallel([
      c.checkoutBag(lines: lines(b3), amount: 1),
      c.checkout(orderId: b3[2].oid, productId: b3[2].pid, amount: 1),
    ]);
    final sids = hits
        .map((h) => h.sessionId ?? '')
        .where((s) => s.startsWith('cs_'))
        .toSet()
        .toList();
    final stored = [
      for (final r in b3)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    b3out = {
      'briefs': hits.map((h) => '${h.status} ${h.sessionId}'),
      'sids': sids,
      'n_cs': sids.length,
      'stored': stored,
    };
  }
  stdout.writeln('CONFIRM B3 $b3out');

  // C2 shipping persist
  final c2 = await mk('c2', 1, price: 15);
  Map<String, Object?> c2out = {'n': c2.length};
  if (c2.length == 1) {
    final before = await c.orderRow(c2.first.oid);
    final open = await c.checkout(
      orderId: c2.first.oid,
      productId: c2.first.pid,
      amount: 1,
      shipping: 'mao',
    );
    final patch = await c.rest(
      'PATCH',
      'orders?id=eq.${c2.first.oid}',
      jwt: c.buyerJwt,
      body: {'shipping_method': 'ctt'},
    );
    final afterJwt = patch.map;
    final afterSvc = await c.orderRow(c2.first.oid);
    c2out = {
      'before_ship': before?['shipping_method'],
      'open': '${open.status} amt=${open.amountTotal} sid=${open.sessionId}',
      'patch_http': patch.status,
      'patch_ship': afterJwt?['shipping_method'],
      'svc_ship': afterSvc?['shipping_method'],
      'changed': '${afterSvc?['shipping_method']}' != '${before?['shipping_method']}',
    };
  }
  stdout.writeln('CONFIRM C2 $c2out');

  // C3-SUFFIX + C3-VIA + C3-BIZUM
  Future<Map<String, Object?>> enc(String tag, String pm) async {
    final sql = await c.rpc(
      'batata_is_off_platform_payment',
      {'p_method': pm},
      service: true,
    );
    final skus = await mk(tag, 1, price: 18);
    HttpHit? cpi;
    Map<String, dynamic>? row;
    if (skus.isNotEmpty) {
      cpi = await c.checkout(
        orderId: skus.first.oid,
        productId: skus.first.pid,
        amount: 1,
      );
      row = await c.orderRow(skus.first.oid);
    }
    return {
      'pm': pm,
      'sql': sql.json,
      'cpi': cpi?.brief,
      'opened': cpi != null && cpi.ok && (cpi.sessionId ?? '').startsWith('cs_'),
      'stored_pm': row?['payment_method'],
      'sid': cpi?.sessionId,
    };
  }

  final suffix = await enc('sfx', 'mb way x');
  final via = await enc('via', 'via mb way');
  final bizum = await enc('bzm', 'bizum');
  stdout.writeln('CONFIRM C3-SUFFIX $suffix');
  stdout.writeln('CONFIRM C3-VIA $via');
  stdout.writeln('CONFIRM C3-BIZUM $bizum');

  await dumpJson('${outDir()}/pass2.json', {
    'B1': b1out,
    'B3': b3out,
    'C2': c2out,
    'C3-SUFFIX': suffix,
    'C3-VIA': via,
    'C3-BIZUM': bizum,
  });
}
