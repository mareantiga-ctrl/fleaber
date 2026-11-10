/// REDTEAM_BLIND_AT pass4 — detector expire corrigido; 2 cs_ saco sequencial + corrida.
import 'dart:io';
import '_rtat.dart';

Future<void> main() async {
  final c = Rtat.fromEnv(loadEnv());
  await c.loginActors();

  final p1 = await c.insertProduct(price: 3.5, qty: 3, title: '$prefix-p4a');
  final p2 = await c.insertProduct(price: 3.5, qty: 3, title: '$prefix-p4b');
  final o1 = p1 == null ? null : await c.insertOrder(productId: p1);
  final o2 = p2 == null ? null : await c.insertOrder(productId: p2);
  if (o1 == null || o2 == null) {
    await c.dumpAll('pass4.json');
    return;
  }
  final lines = [
    {'order_id': o1, 'product_id': p1},
    {'order_id': o2, 'product_id': p2},
  ];

  final first = await c.bagCpi(lines);
  final second = await c.bagCpi(lines);
  final a1 = await c.checkoutAlive(first.checkoutUrl);
  final a2 = await c.checkoutAlive(second.checkoutUrl);
  final row = await c.orderRow(o1);
  c.note('AT2.seq', 'saco sequencial 2× (detector corrigido)', {
    'sid1': first.checkoutSessionId,
    'sid2': second.checkoutSessionId,
    'reused2': second.reused,
    'alive1': a1,
    'alive2': a2,
    'rowSid': row?['stripe_checkout_session_id'],
  }, lens: 'AT2');

  final twoAliveSeq = (a1 ?? '').startsWith('alive') &&
      (a2 ?? '').startsWith('alive') &&
      first.checkoutSessionId != second.checkoutSessionId;
  if (twoAliveSeq) {
    c.hold(
      id: 'AT2-06',
      lens: 'AT2',
      severity: 'P1',
      title:
          'Compact UUID: 2.º bag checkout deixa a 1.ª Session Stripe ainda pagável',
      actor: 'buyer JWT',
      pre: 'saco 2 orders; metadata bag_order_ids compacta',
      repro: '2× POST bag_checkout sequencial; GET HTML das duas checkoutUrl',
      expected: '1.ª expired ou reused_session',
      obtained:
          'sid1=${first.checkoutSessionId} sid2=${second.checkoutSessionId} reused=${second.reused} alive1=$a1 alive2=$a2',
      evidence: {
        'url1': first.checkoutUrl,
        'url2': second.checkoutUrl,
        'rowSid': row?['stripe_checkout_session_id'],
      },
    );
  } else if (first.checkoutSessionId != second.checkoutSessionId &&
      !second.reused) {
    c.hold(
      id: 'AT2-06',
      lens: 'AT2',
      severity: 'P3',
      title: 'Reuse do saco falha (compact vs hyphen) mas 1.ª já não está pagável',
      actor: 'buyer JWT',
      pre: '2× bag sequencial',
      repro: 'GET checkoutUrl',
      expected: 'reused_session=true',
      obtained: 'alive1=$a1 alive2=$a2 reused=${second.reused}',
    );
  } else {
    c.block('AT2-06', 'AT2', 'saco sequencial reuse/expire OK',
        'alive1=$a1 alive2=$a2 reused=${second.reused}');
  }

  final p3 = await c.insertProduct(price: 3.5, qty: 3, title: '$prefix-p4c');
  final p4 = await c.insertProduct(price: 3.5, qty: 3, title: '$prefix-p4d');
  final o3 = p3 == null ? null : await c.insertOrder(productId: p3);
  final o4 = p4 == null ? null : await c.insertOrder(productId: p4);
  if (o3 != null && o4 != null) {
    final linesR = [
      {'order_id': o3, 'product_id': p3},
      {'order_id': o4, 'product_id': p4},
    ];
    final br = await Future.wait([c.bagCpi(linesR), c.bagCpi(linesR)]);
    final al = [
      await c.checkoutAlive(br[0].checkoutUrl),
      await c.checkoutAlive(br[1].checkoutUrl),
    ];
    final sids = br.map((h) => h.checkoutSessionId).toSet();
    c.note('AT6.race4', 'corrida detector corrigido', {
      'sids': sids.toList(),
      'alive': al,
      'reused': br.map((h) => h.reused).toList(),
    }, lens: 'AT6');
    final nAlive = al.where((x) => (x ?? '').startsWith('alive')).length;
    if (sids.length > 1 && nAlive >= 2) {
      c.hold(
        id: 'AT6-04',
        lens: 'AT6',
        severity: 'P1',
        title: 'Corrida saco: 2 cs_ pagáveis em simultâneo',
        actor: 'buyer JWT',
        pre: 'Future.wait 2× bag',
        repro: 'GET HTML checkoutUrl imediato (frase expire exacta)',
        expected: '1 pagável',
        obtained: 'sids=$sids alive=$al',
      );
    } else if (sids.length > 1) {
      c.block('AT6-04', 'AT6', 'corrida emite 2 cs_ mas pagáveis=$nAlive', al);
    } else {
      c.block('AT6-04', 'AT6', 'corrida 1 sid', sids.toList());
    }
  }

  await c.dumpAll('pass4.json');
  stdout.writeln(
      'PASS4 findings=${c.findings.length} blocked=${c.blocked.length}');
}
