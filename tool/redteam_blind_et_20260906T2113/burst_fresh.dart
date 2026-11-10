/// Burst bag∥single t=0 com comprador fresco — 1.º tiro vs reuse.
/// Staging. NÃO corrigir.
import 'dart:io';

import '_rtet.dart';

Future<void> main() async {
  final c = Rten.fromEnv(loadEnv());
  await c.loginActors();
  final email = '${prefix.toLowerCase()}-b4@fleaber.test';
  const pass = 'rtet2113b4!xK';
  await c.req('POST', '/auth/v1/admin/users', service: true, body: {
    'email': email,
    'password': pass,
    'email_confirm': true,
  });
  final jwt = await c.signIn(email, pass);
  final me = await c.req('GET', '/auth/v1/user', jwt: jwt);
  final b4 = (me.json is Map) ? (me.json as Map)['id'] as String? : null;
  if (b4 == null) {
    stderr.writeln('b4 fail');
    exit(4);
  }
  await c.rest(
    'PATCH',
    'profiles?id=eq.$b4',
    service: true,
    body: {
      'full_name': '$prefix-B4',
      'handle': 'rtet2113b4',
      'user_type': 'comprador',
      'hub_published': false,
    },
    prefer: 'return=minimal',
  );
  final s1 = c.sellerId!;
  stdout.writeln('fresh B4 $b4');
  final rounds = <Map<String, Object?>>[];
  for (var i = 0; i < 4; i++) {
    final skus = <String>[];
    final oids = <String>[];
    for (var j = 0; j < 3; j++) {
      final pid = await c.createProduct(
        title: '$prefix fresh-$i-$j',
        qty: 2,
        listed: true,
        live: false,
      );
      if (pid == null) continue;
      skus.add(pid);
      final oid = await c.insertOrder(
        productId: pid,
        jwt: jwt,
        buyer: b4,
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
      c.checkoutBag(lines: lines, jwt: jwt, buyer: b4, seller: s1),
      c.checkout(
        orderId: oids[1],
        productId: skus[1],
        jwt: jwt,
        buyer: b4,
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
      hub.add((await c.hubSku(pid, jwt: jwt)).list.length);
    }
    rounds.add({
      'i': i,
      'cs_n': sids.length,
      'creates_n': creates.length,
      'sids': sids.toList(),
      'reused': raced.map((h) => h.reused).toList(),
      'statuses': raced.map((h) => h.status).toList(),
      'hub': hub,
    });
    stdout.writeln(
      'fresh $i cs=${sids.length} creates=${creates.length} '
      'reused=${raced.map((h) => h.reused).toList()} hub=$hub',
    );
  }
  await dumpJson('${outDir()}/burst_fresh.json', {'b4': b4, 'rounds': rounds});
  stdout.writeln('WROTE burst_fresh.json');
}
