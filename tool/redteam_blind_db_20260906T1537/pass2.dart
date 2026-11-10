/// RED TEAM CEGO DB pass2 — confirmação HOLDs B1/C3. Sem correções.
import 'dart:io';

import '_rtdb.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('DB pass2 staging=${c.url}');
  await c.loginActors();

  const b1sids = [
    'cs_test_a1J8bKh2admEHS6gze2Qx356rDipjf7A7WcAJv5eqDSUx4ILthvQa2IhY1',
    'cs_test_a12JE4xaLRDe45BDRU8NNOd85517ZppzRrRtJGbOtvSkBCBK0U5Nai2s9h',
  ];
  const b2sids = [
    'cs_test_a1SDTJ36ZiXg38015ZLWV3BVzMtqKFhjfLLqbXnBNRxRDTgixyEz6e3A8X',
    'cs_test_a1zSy0pY1qZUDO5IGjdh975iPVDJxxvIIrS8nh1w4w0L0zgozUcazAgt2j',
  ];
  const b5sids = [
    'cs_test_a1RGXgZHb17ZIOfBLXkZAJgsmH8qpKyoqbp0JPWaFmi4ERfEg2PhdR30y2',
    'cs_test_a1ctgmiGqXfvrtD2daLLSYmFQN7NJYIsWCZxDspCMGVJXRxvzkugQpPsRw',
  ];

  Future<Map<String, Object?>> peek(String sid) async {
    final settle = await c.settleGet(sid);
    final page = await c.req('GET', 'https://checkout.stripe.com/c/pay/$sid');
    final page2 = await c.req('GET', 'https://checkout.stripe.com/pay/$sid');
    return {
      'sid': sid.substring(0, 28),
      'settle': settle.brief,
      'page_c_pay': page.status,
      'page_pay': page2.status,
      'expired_c': page.body.toLowerCase().contains('expired') ||
          page.body.toLowerCase().contains('expirou'),
    };
  }

  final b1peeks = [for (final s in b1sids) await peek(s)];
  final b2peeks = [for (final s in b2sids) await peek(s)];
  final b5peeks = [for (final s in b5sids) await peek(s)];
  c.note('pass2.b1peeks', 'B1 sessions', b1peeks, lens: 'DB3', well: 'DB-B');
  c.note('pass2.b2peeks', 'B2 sessions', b2peeks, lens: 'DB3', well: 'DB-B');
  c.note('pass2.b5peeks', 'B5 sessions', b5peeks, lens: 'DB3', well: 'DB-B');

  // Repro 4∥2
  final skus = <({String oid, String pid, double price})>[];
  for (var i = 0; i < 4; i++) {
    final p = 9.0 + i;
    final pid = await c.createProduct(title: '$prefix-p2-4x2-$i', qty: 2, price: p);
    if (pid == null) continue;
    final oid = await c.insertOrder(
      productId: pid,
      price: p,
      jwt: c.buyerJwt,
    );
    if (oid == null) continue;
    skus.add((oid: oid, pid: pid, price: p));
  }
  Map<String, Object?>? repro;
  if (skus.length == 4) {
    final four = [
      for (final r in skus) {'order_id': r.oid, 'product_id': r.pid},
    ];
    final two = [
      for (final r in skus.sublist(2)) {'order_id': r.oid, 'product_id': r.pid},
    ];
    final hits = await parallel([
      c.checkoutBag(lines: four, amount: 1),
      c.checkoutBag(lines: two, amount: 1),
    ]);
    final sids = hits
        .map((h) => h.sessionId ?? '')
        .where((s) => s.startsWith('cs_'))
        .toSet();
    final stored = [
      for (final r in skus)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    repro = {
      'http': hits.map((h) => h.status).toList(),
      'sids': sids.toList(),
      'n_cs': sids.length,
      'stored': stored,
      'briefs': hits.map((h) => h.brief).toList(),
    };
    c.note('pass2.b1repro', '4∥2 repeat', repro, lens: 'DB3', well: 'DB-B');
  }

  Future<Map<String, Object?>> enc(String tag, String payment) async {
    final sql = await c.rpc(
      'batata_is_off_platform_payment',
      {'p_method': payment},
      service: true,
    );
    final pid = await c.createProduct(title: '$prefix-p2-$tag', qty: 2, price: 18);
    if (pid == null) return {'tag': tag, 'err': 'no sku'};
    final oid = await c.insertOrder(
      productId: pid,
      price: 18,
      payment: payment,
      service: true,
    );
    if (oid == null) return {'tag': tag, 'sql': sql.json, 'err': 'no order'};
    final cpi = await c.checkout(orderId: oid, productId: pid, amount: 1);
    final row = await c.orderRow(oid);
    return {
      'tag': tag,
      'sql': sql.json,
      'cpi': cpi.brief,
      'sid': cpi.sessionId,
      'pm_codes': '${row?['payment_method'] ?? ''}'
          .runes
          .map((r) => r.toRadixString(16))
          .toList(),
      'status': row?['status'],
    };
  }

  final omega = await enc('omega', 'mb\u03C9ay');
  final math = await enc(
    'math',
    String.fromCharCodes(
        const [0x1D5DC, 0x1D5D5, 0x1D5E0, 0x1D5D4, 0x1D5E2]),
  );
  final coptic = await enc('copt', '\u2C99bway');
  c.note('pass2.omega', 'C3-OMEGA repro', omega, lens: 'DB4', well: 'DB-C');
  c.note('pass2.math', 'C3-MATH repro', math, lens: 'DB4', well: 'DB-C');
  c.note('pass2.copt', 'C3-COPT repro', coptic, lens: 'DB4', well: 'DB-C');

  final paidOid = '328bd13e-6f16-44b2-8f62-b1f73a6bd30d';
  final paidRow = await c.orderRow(paidOid);
  c.note('pass2.paid', 'C5 caixa', paidRow, lens: 'DB7', well: 'DB-C');

  await dumpJson('${outDir()}/pass2.json', {
    'stamp': stamp,
    'b1peeks': b1peeks,
    'b2peeks': b2peeks,
    'b5peeks': b5peeks,
    'b1repro': repro,
    'omega': omega,
    'math': math,
    'copt': coptic,
    'paid': paidRow,
  });
  stdout.writeln('DONE pass2 n_cs_repro=${repro?['n_cs']}');
}
