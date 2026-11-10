/// ES pass2 — confirmar bag∥single dual create + ledger A1 após 4242.
import 'dart:io';
import '_rtes.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer3();
  c.buyerId = c.buyer3Id;
  c.buyerJwt = c.buyer3Jwt;

  final skus = <({String oid, String pid, double price})>[];
  for (var i = 0; i < 5; i++) {
    final p = 7.0 + i;
    final pid = await c.createProduct(
      title: '$prefix-p2-a1-$i',
      qty: 1,
      price: p,
    );
    if (pid == null) continue;
    final oid = await c.insertOrder(
      productId: pid,
      price: p,
      jwt: c.buyerJwt,
    );
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
      ),
      c.checkout(orderId: mid.oid, productId: mid.pid, amount: 1),
    ]);
    for (final h in hits) {
      c.trackSession(h);
    }
    final sids = hits
        .map((h) => h.sessionId ?? '')
        .where((s) => s.startsWith('cs_'))
        .toSet()
        .toList();
    final stored = <String>[];
    for (final r in skus) {
      stored.add(
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
      );
    }
    confirm = {
      'status': hits.map((h) => h.status).toList(),
      'briefs': hits.map((h) => h.brief).toList(),
      'sids': sids,
      'reused': hits.map((h) => h.reused).toList(),
      'distinct': sids.length,
      'dual_create':
          sids.length >= 2 && hits.where((h) => h.ok && !h.reused).length >= 2,
      'stored': stored,
    };
  }

  const a1oids = [
    '57f314f7-174e-412f-8234-67dd390db974',
    'f6dd4643-801f-4fd8-b3b5-2ccbb00ab5c2',
    '1262e966-c44d-41f4-8286-396364e59252',
    '7620d26d-6f82-4c54-9569-e25f7e7b466e',
    'a1129fa5-57d6-4b9e-9318-5e176da6f752',
  ];
  final a1 = <Map<String, Object?>>[];
  for (final id in a1oids) {
    final o = await c.orderRow(id);
    final p = await c.productRow('${o?['product_id']}');
    a1.add({
      'oid': id,
      'status': o?['status'],
      'cs': o?['stripe_checkout_session_id'],
      'pi': o?['stripe_payment_intent_id'],
      'paid': o?['amount_paid_cents'],
      'applied': o?['stock_units_applied'],
      'product_qty': p?['quantity'],
      'sold': p?['is_sold'],
    });
  }

  final s1 = await c.settleGet(
    'cs_test_a1SquR0ij7572tUfHaF7EHVzm2HOl0JzplaOObmSD3L08qZ5gGZoq8rNjo',
  );
  final s2 = await c.settleGet(
    'cs_test_a1XyXJBEnGIq55JKBYZRv702rwFEjjLpYJU1fXrS2yLQEjH4preBePQIXb',
  );

  const c3pid = '481210ed-75f0-4245-a251-604e33cc63b1';
  const c3oid = '2b244d10-0629-49d3-9814-eda4ad2a590b';
  final hub = await c.hubSku(c3pid);
  final prod = await c.productRow(c3pid);
  final ord = await c.orderRow(c3oid);

  final out = {
    'confirm_a1_bag_single': confirm,
    'a1_ledger_after_pay_attempt': a1,
    'settle_a1': {'s1': s1.brief, 's2': s2.brief},
    'c3_hub': {
      'http': hub.status,
      'n': hub.list.length,
      'row': hub.map,
      'product_qty': prod?['quantity'],
      'order_status': ord?['status'],
      'applied': ord?['stock_units_applied'],
    },
    'wallets': await c.wallets(),
  };
  await dumpJson('${outDir()}/pass2.json', out);
  stdout.writeln(
    'confirm dual=${confirm['dual_create']} distinct=${confirm['distinct']} '
    'status=${confirm['status']}',
  );
  stdout.writeln(
    'A1 statuses=${a1.map((e) => e['status']).toSet()} '
    'qtys=${a1.map((e) => e['product_qty']).toSet()} '
    'pagos=${a1.where((e) => e['paid'] != null).length}',
  );
  stdout.writeln('settle ${s1.status} ${s2.status}');
  stdout.writeln(
    'C3 hub ${hub.status} n=${hub.list.length} qty=${prod?['quantity']} '
    'status=${ord?['status']}',
  );
}
