/// EM pass2 — confirmar bag∥single dual create + ledger A3 após 4242.
import 'dart:io';
import '_rtem.dart';

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
      title: '$prefix-p2-a3-$i',
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
      'dual_create': sids.length >= 2 && hits.where((h) => h.ok && !h.reused).length >= 2,
      'stored': stored,
    };
  }

  const a3oids = [
    '0f63ddcd-2a98-4d59-95e9-876cb7375457',
    'e4276711-3693-42ea-a4a5-e348e8d60823',
    '71dae9ec-31a6-402a-b232-d87a0e42f044',
    '75f19f46-b867-4b9d-8811-b1c8da4f5072',
    '4370ec98-62d3-4046-bd55-6cc92404c0a5',
  ];
  final a3 = <Map<String, Object?>>[];
  for (final id in a3oids) {
    final o = await c.orderRow(id);
    final p = await c.productRow('${o?['product_id']}');
    a3.add({
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
    'cs_test_a1dxRQUtKf7xqrwmlScM6tEBTiy2u7N8WiZPFZHX90yB3X0s3HTUt1Hr54',
  );
  final s2 = await c.settleGet(
    'cs_test_a1cvPktwDh77Yqg50zmj7IpRyHI86bKb9GC0JZu4pKC2KxHrmT1T8SnI3h',
  );

  const c3pid = '2bfcb27e-2ae6-41fd-8bf9-c130ceb9704a';
  const c3oid = 'be180552-05ec-4dd7-9c8f-7baeb2b4cdec';
  final hub = await c.hubSku(c3pid);
  final prod = await c.productRow(c3pid);
  final ord = await c.orderRow(c3oid);

  final out = {
    'confirm_a3_bag_single': confirm,
    'a3_ledger_after_pay_attempt': a3,
    'settle_a3': {'s1': s1.brief, 's2': s2.brief},
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
    'A3 statuses=${a3.map((e) => e['status']).toSet()} '
    'qtys=${a3.map((e) => e['product_qty']).toSet()} '
    'pagos=${a3.where((e) => e['paid'] != null).length}',
  );
  stdout.writeln('settle ${s1.status} ${s2.status}');
  stdout.writeln(
    'C3 hub ${hub.status} n=${hub.list.length} qty=${prod?['quantity']} '
    'status=${ord?['status']}',
  );
}
