/// GATE confirm — expand fresco (B2 limpo) + settle A1 dual.
import 'dart:io';

import '_rtgate.dart';

Future<void> main() async {
  final c = Rtdb.fromEnv(loadEnv());
  stdout.writeln('GATE confirm expand+settle prefix=$prefix');
  await c.loginActors();

  final actor = await c.mintBuyer('bxp');
  c.buyerId = actor.id;
  c.buyerJwt = actor.jwt;

  final skus = <({String oid, String pid, double price})>[];
  for (var i = 0; i < 4; i++) {
    final p = 14.0 + i;
    final pid = await c.createProduct(
      title: '$prefix-bxp-$i',
      qty: 2,
      price: p,
    );
    if (pid == null) continue;
    final oid = await c.insertOrder(productId: pid, price: p, jwt: c.buyerJwt);
    if (oid == null) continue;
    skus.add((oid: oid, pid: pid, price: p));
  }

  Map<String, Object?> pack = {'n': skus.length};
  if (skus.length == 4) {
    final first = c.checkoutBag(
      lines: [
        for (final r in skus.take(2))
          {'order_id': r.oid, 'product_id': r.pid},
      ],
      amount: 1,
    );
    final second = Future<HttpHit>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c.checkoutBag(
        lines: [
          for (final r in skus) {'order_id': r.oid, 'product_id': r.pid},
        ],
        amount: 1,
      );
    });
    final hits = await Future.wait([first, second]);
    final sids = hits
        .map((h) => h.sessionId ?? '')
        .where((s) => s.startsWith('cs_'))
        .toSet();
    final stored = [
      for (final r in skus)
        '${(await c.orderRow(r.oid))?['stripe_checkout_session_id'] ?? ''}',
    ];
    pack = {
      'status': hits.map((h) => h.status).toList(),
      'briefs': hits.map((h) => h.brief).toList(),
      'reused': hits.map((h) => h.reused).toList(),
      'sids': sids.toList(),
      'creates': hits
          .where((h) =>
              h.ok &&
              (h.sessionId ?? '').startsWith('cs_') &&
              h.reused != true)
          .map((h) => h.sessionId!)
          .toSet()
          .length,
      'stored': stored,
      'overlap_400': hits.any((h) =>
          h.status == 400 &&
          h.body.toLowerCase().contains('overlapping')),
      'dual': sids.length >= 2 &&
          hits.where((h) => h.ok && h.reused != true).length >= 2,
    };
  }

  const bag =
      'cs_test_a1ympYGgBlhEwfOPPbI3HQ6Zwy8gn5VXGthckbPQdStrtPMFKjBJn4tuQ5';
  const orph =
      'cs_test_a1H6uUC0rhH7D5KugVK0jckYjZIEoGrEjZgkoDp0qFGntv07Uqyu1N5rYL';
  final settleBag = await c.settleGet(bag);
  final settleOrph = await c.settleGet(orph);

  final a1oids = [
    '52942cb7-94d9-4df9-8ba7-f22c903b687b',
    'f999200d-cdf6-42ca-bc66-ed306028fe5e',
    '66f711d8-86f3-4001-8950-73234688826f',
    '193c0928-ea03-48c4-bae2-e5b39a8c10fc',
    '8898cd2b-c9bb-4bf1-ac70-9a9d06241ff1',
  ];
  final a1ledger = <Map<String, Object?>>[];
  for (final id in a1oids) {
    final o = await c.orderRow(id);
    final p = o == null ? null : await c.productRow('${o['product_id']}');
    final hub = o == null
        ? null
        : await c.hubSku('${o['product_id']}');
    a1ledger.add({
      'oid': id,
      'status': o?['status'],
      'cs': o?['stripe_checkout_session_id'],
      'pi': o?['stripe_payment_intent_id'],
      'paid': o?['amount_paid_cents'],
      'qty': p?['quantity'],
      'sold': p?['is_sold'],
      'hub_n': hub?.list.length,
    });
  }

  final out = {
    'expand_fresh': pack,
    'a1_settle_bag': settleBag.brief,
    'a1_settle_orph': settleOrph.brief,
    'a1_ledger': a1ledger,
  };
  await dumpJson('${outDir()}/confirm.json', out);
  stdout.writeln('EXPAND $pack');
  stdout.writeln('SETTLE bag=${settleBag.brief}');
  stdout.writeln('SETTLE orph=${settleOrph.brief}');
  stdout.writeln(
    'A1 statuses=${a1ledger.map((e) => e['status']).toSet()} '
    'qty=${a1ledger.map((e) => e['qty']).toSet()}',
  );
}
