/// REDTEAM_BLIND_AT pass3 — corrida saco com URLs completas, verificação imediata.
import 'dart:io';
import '_rtat.dart';

Future<void> main() async {
  final c = Rtat.fromEnv(loadEnv());
  await c.loginActors();

  final p1 = await c.insertProduct(price: 4.5, qty: 3, title: '$prefix-r3a');
  final p2 = await c.insertProduct(price: 4.5, qty: 3, title: '$prefix-r3b');
  final o1 = p1 == null ? null : await c.insertOrder(productId: p1);
  final o2 = p2 == null ? null : await c.insertOrder(productId: p2);
  if (o1 == null || o2 == null) {
    c.skip('AT6.p3', 'AT6', 'fixture race', 'null');
    await c.dumpAll('pass3.json');
    return;
  }
  final lines = [
    {'order_id': o1, 'product_id': p1},
    {'order_id': o2, 'product_id': p2},
  ];
  final br = await Future.wait([c.bagCpi(lines), c.bagCpi(lines)]);
  final urls = br.map((h) => h.checkoutUrl).toList();
  final sids = br.map((h) => h.checkoutSessionId).toList();
  final alive = <String?>[];
  for (final u in urls) {
    alive.add(await c.checkoutAlive(u));
  }
  final row1 = await c.orderRow(o1);
  final row2 = await c.orderRow(o2);
  c.note('AT6.p3', 'corrida imediata', {
    'http': br.map((h) => h.status).toList(),
    'sids': sids,
    'reused': br.map((h) => h.reused).toList(),
    'amts': br.map((h) => h.serverAmount).toList(),
    'alive': alive,
    'row1': row1?['stripe_checkout_session_id'],
    'row2': row2?['stripe_checkout_session_id'],
  }, lens: 'AT6');

  final distinct = sids.whereType<String>().toSet();
  final aliveN = alive.where((a) => (a ?? '').startsWith('alive')).length;
  if (distinct.length > 1 && aliveN >= 2) {
    c.hold(
      id: 'AT6-03',
      lens: 'AT6',
      severity: 'P1',
      title: 'Corrida saco: 2 cs_ distintas ambas pagáveis no instante T+0',
      actor: 'buyer JWT',
      pre: '2 orders mesmo saco',
      repro: 'Future.wait 2× bag_checkout; GET checkoutUrl imediato',
      expected: '1 Session viva',
      obtained: 'sids=$distinct alive=$alive',
      evidence: {
        'urls': urls,
        'row1': row1?['stripe_checkout_session_id'],
        'row2': row2?['stripe_checkout_session_id'],
      },
    );
  } else if (distinct.length > 1) {
    c.hold(
      id: 'AT6-03',
      lens: 'AT6',
      severity: 'P3',
      title: 'Corrida saco emite 2 cs_ mas só $aliveN pagável(eis) no T+0',
      actor: 'buyer JWT',
      pre: 'Future.wait 2× bag',
      repro: '2× bag_checkout paralelo; GET URLs',
      expected: '1 cs_ reused',
      obtained: 'sids=$distinct alive=$alive reused=${br.map((h) => h.reused).toList()}',
      evidence: {'sids': sids, 'alive': alive},
    );
  } else {
    c.block('AT6-03', 'AT6', 'corrida saco 1 Session', {
      'sids': sids,
      'alive': alive,
    });
  }

  await c.dumpAll('pass3.json');
  stdout.writeln(
      'PASS3 findings=${c.findings.length} blocked=${c.blocked.length}');
}
