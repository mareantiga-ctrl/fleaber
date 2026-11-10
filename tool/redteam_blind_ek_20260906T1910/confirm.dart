/// Confirm obrigatório EK: B1 6∥4, B2 expand, B3 bag∥single. Staging. NÃO corrigir.
import 'dart:io';
import '_rtek.dart';

Future<void> main() async {
  final c = Rtek.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer3();
  final s1 = c.sellerId!;
  final b3 = c.buyer3Id!;
  final out = <String, Object?>{};

  out['b1'] = await confirmOverlap(
    c,
    s1,
    b3,
    tag: 'b1-64',
    n: 6,
    first: [0, 1, 2, 3, 4, 5],
    second: [1, 2, 3, 4],
    delayMs: 0,
  );
  out['b2'] = await confirmOverlap(
    c,
    s1,
    b3,
    tag: 'b2-expand',
    n: 4,
    first: [0, 1],
    second: [0, 1, 2, 3],
    delayMs: 50,
  );
  out['b3'] = await confirmBagSingle(c, s1, b3);

  await c.endAllCreatedLives();
  await c.restoreSeller1Published();
  await dumpJson('${outDir()}/confirm.json', out);
  stdout.writeln('WROTE confirm.json');
}

Future<Map<String, Object?>> confirmOverlap(
  Rtek c,
  String s1,
  String b3, {
  required String tag,
  required int n,
  required List<int> first,
  required List<int> second,
  required int delayMs,
}) async {
  final skus = <String>[];
  final oids = <String>[];
  for (var i = 0; i < n; i++) {
    final pid = await c.createProduct(
      title: '$prefix p2-$tag-$i',
      qty: 2,
      listed: true,
      live: false,
    );
    if (pid == null) continue;
    skus.add(pid);
    final oid = await c.insertOrder(
      productId: pid,
      jwt: c.buyer3Jwt,
      buyer: b3,
      price: 12.0,
    );
    if (oid != null) oids.add(oid);
  }
  List<Map<String, Object?>> lines(List<int> idx) => [
        for (final i in idx)
          if (i < oids.length && i < skus.length)
            {
              'order_id': oids[i],
              'product_id': skus[i],
              'quantity': 1,
              'price': 12.0,
            },
      ];
  if (oids.length < n) return {'skip': 'oids ${oids.length}'};
  final raced = await Future.wait([
    c.checkoutBag(
        lines: lines(first), jwt: c.buyer3Jwt, buyer: b3, seller: s1),
    Future(() async {
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
      return c.checkoutBag(
          lines: lines(second), jwt: c.buyer3Jwt, buyer: b3, seller: s1);
    }),
  ]);
  final sids = raced
      .map((h) => h.sessionId ?? '')
      .where((s) => s.startsWith('cs_'))
      .toSet();
  final stored = <String>[];
  final hub = <int>[];
  for (final oid in oids) {
    stored.add('${(await c.orderRow(oid))?['stripe_checkout_session_id'] ?? ''}');
  }
  for (final pid in skus) {
    hub.add((await c.hubSku(pid, jwt: c.buyer3Jwt)).list.length);
  }
  stdout.writeln('$tag confirm cs=${sids.length} $sids hub=$hub');
  return {
    'http': raced.map((h) => h.brief).toList(),
    'sids': sids.toList(),
    'cs_n': sids.length,
    'ledger': stored,
    'reused': raced.map((h) => h.reused).toList(),
    'hub_ns': hub,
  };
}

Future<Map<String, Object?>> confirmBagSingle(
    Rtek c, String s1, String b3) async {
  final skus = <String>[];
  final oids = <String>[];
  for (var i = 0; i < 3; i++) {
    final pid = await c.createProduct(
      title: '$prefix p2-b3-$i',
      qty: 2,
      listed: true,
      live: false,
    );
    if (pid == null) continue;
    skus.add(pid);
    final oid = await c.insertOrder(
      productId: pid,
      jwt: c.buyer3Jwt,
      buyer: b3,
      price: 12.0,
    );
    if (oid != null) oids.add(oid);
  }
  if (oids.length < 3) return {'skip': 'oids ${oids.length}'};
  final raced = await Future.wait([
    c.checkoutBag(
      lines: [
        for (var i = 0; i < 3; i++)
          {
            'order_id': oids[i],
            'product_id': skus[i],
            'quantity': 1,
            'price': 12.0,
          },
      ],
      jwt: c.buyer3Jwt,
      buyer: b3,
      seller: s1,
    ),
    c.checkout(
      orderId: oids[1],
      productId: skus[1],
      jwt: c.buyer3Jwt,
      buyer: b3,
    ),
  ]);
  final sids = raced
      .map((h) => h.sessionId ?? '')
      .where((s) => s.startsWith('cs_'))
      .toSet();
  final stored = <String>[];
  for (final oid in oids) {
    stored.add('${(await c.orderRow(oid))?['stripe_checkout_session_id'] ?? ''}');
  }
  stdout.writeln('b3 confirm cs=${sids.length} $sids stored=$stored');
  return {
    'http': raced.map((h) => h.brief).toList(),
    'sids': sids.toList(),
    'cs_n': sids.length,
    'ledger': stored,
    'reused': raced.map((h) => h.reused).toList(),
  };
}
