/// ES pass2 — confirmar bag∥single dual num buyer fresco + ledger A1 pago.
import 'dart:io';
import '_rtes.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  await c.loginActors();
  final email = '${prefix.toLowerCase()}-b5@fleaber.test';
  const pass = 'Rtes2115b5!xK';
  final id = await c.ensureNamed(
    email: email,
    pass: pass,
    handle: 'rtes2115b5',
    name: '$prefix-B5',
  );
  final jwt = await c.signIn(email, pass);
  c.buyerId = id;
  c.buyerJwt = jwt;
  stdout.writeln('ES pass2 fresh buyer5=$id');

  final skus = <({String oid, String pid, double price})>[];
  for (var i = 0; i < 5; i++) {
    final p = 7.0 + i;
    final pid =
        await c.createProduct(title: '$prefix-p2-a1-$i', qty: 1, price: p);
    if (pid == null) continue;
    final oid = await c.insertOrder(productId: pid, price: p, jwt: jwt);
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
        jwt: jwt,
        buyer: id,
      ),
      c.checkout(
        orderId: mid.oid,
        productId: mid.pid,
        amount: 1,
        jwt: jwt,
        buyer: id,
      ),
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
      'buyer': id,
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
    'fada5375-3f06-4350-8c55-acd85c8c3324',
    '863c9782-2fe8-4aff-adf3-867c3cd926bc',
    '3ba83ca8-94eb-41ca-a920-5d602c580916',
    'f59829e0-0451-4a3c-ba42-ec0ee5cf4217',
    'da4ca3e9-a66f-42e1-852c-182467a5bbb3',
  ];
  final a1 = <Map<String, Object?>>[];
  for (final oid in a1oids) {
    final o = await c.orderRow(oid);
    final p = await c.productRow('${o?['product_id']}');
    a1.add({
      'oid': oid,
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
    'cs_test_a1BjYEA3HeSVskzVZ3rhLIXoTnn25bO2invtdwAjDZQSBXjebw1u9tY8PE',
  );
  final s2 = await c.settleGet(
    'cs_test_a1yQ9AkZO1H0FMemGUApbiMCGymvaNfljV3hlfL7JfV6fPilMjxph00KlC',
  );

  final out = {
    'confirm_a1_bag_single': confirm,
    'a1_ledger_after_pay_attempt': a1,
    'settle_a1': {'s1': s1.brief, 's2': s2.brief},
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
}
