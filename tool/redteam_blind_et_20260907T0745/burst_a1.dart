/// Burst bag∥single t=0 — medir taxa dual create. NÃO corrigir.
import 'dart:io';

import '_rtet.dart';

Future<void> main() async {
  final c = Rten.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer3();
  final s1 = c.sellerId!;
  final b3 = c.buyer3Id!;
  final rounds = <Map<String, Object?>>[];
  for (var i = 0; i < 6; i++) {
    final skus = <String>[];
    final oids = <String>[];
    for (var j = 0; j < 3; j++) {
      final pid = await c.createProduct(
        title: '$prefix burst-$i-$j',
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
        price: 12,
      );
      if (oid != null) oids.add(oid);
    }
    if (oids.length < 3) {
      rounds.add({'i': i, 'skip': oids.length});
      continue;
    }
    final lines = [
      for (var j = 0; j < 3; j++)
        {
          'order_id': oids[j],
          'product_id': skus[j],
          'quantity': 1,
          'price': 12.0,
        },
    ];
    final raced = await Future.wait([
      c.checkoutBag(lines: lines, jwt: c.buyer3Jwt, buyer: b3, seller: s1),
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
    final creates = raced
        .where((h) =>
            h.ok &&
            (h.sessionId ?? '').startsWith('cs_') &&
            h.reused != true)
        .map((h) => h.sessionId!)
        .toSet();
    final hub = <int>[];
    for (final pid in skus) {
      hub.add((await c.hubSku(pid, jwt: c.buyer3Jwt)).list.length);
    }
    final row = {
      'i': i,
      'cs_n': sids.length,
      'creates_n': creates.length,
      'sids': sids.toList(),
      'reused': raced.map((h) => h.reused).toList(),
      'statuses': raced.map((h) => h.status).toList(),
      'hub': hub,
    };
    rounds.add(row);
    stdout.writeln(
      'burst $i cs=${sids.length} creates=${creates.length} '
      'reused=${raced.map((h) => h.reused).toList()} hub=$hub',
    );
  }
  await dumpJson('${outDir()}/burst_a1.json', {'rounds': rounds});
  stdout.writeln('WROTE burst_a1.json');
}
