/// PASS 2b — release sem mão via MB WAY (CPI exact-list não aplica).
import 'dart:io';
import '_rtbj.dart';

Future<void> main() async {
  final c = Rtbj.fromEnv(loadEnv());
  await c.loginActors();

  final pid = await c.insertProduct(price: 7.2, title: '$prefix-mbway-morada');
  if (pid == null) {
    stderr.writeln('no product');
    return;
  }
  final oid = await c.insertOrder(
    productId: pid,
    priceTotal: 7.2,
    shipping: 'entrega em morada',
    payment: 'MB WAY',
  );
  stdout.writeln('OID $oid');
  if (oid == null) return;

  final pago = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
    'status': 'pago',
    'proof_url': 'https://fleaber.pt/proof-bj.png',
  });
  c.note('p2b.pago', 'seller marca pago MB WAY', pago.brief, lens: 'BJ5');
  var row = await c.orderRow(oid);
  c.note('p2b.row.pago', 'row', row, lens: 'BJ5');

  final concl = await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.buyerJwt, body: {
    'status': 'concluido',
  });
  c.note('p2b.concluido', 'buyer concluido sem enviado', concl.brief, lens: 'BJ5');
  row = await c.orderRow(oid);

  if (concl.ok && '${row?['status']}'.toLowerCase() == 'concluido') {
    final before = await c.walletBal(c.sellerId);
    final rel = await c.tryRelease(oid, jwt: c.buyerJwt);
    c.note('p2b.release', 'release após concluido sem shipped', rel.brief,
        lens: 'BJ3');
    var released = rel.ok && rel.json == true;
    if (!released) {
      final relSvc = await c.tryRelease(oid, service: true);
      c.note('p2b.release.svc', 'svc release', relSvc.brief, lens: 'BJ3');
      released = relSvc.ok && relSvc.json == true;
    }
    final after = await c.walletBal(c.sellerId);
    if (released && (after - before) > 0.05) {
      c.hold(
        id: 'BJ3-09-mbway-morada-release',
        lens: 'BJ3',
        severity: 'P0',
        title: 'MB WAY + "entrega em morada": release sem envio creditou seller',
        actor: 'seller pago · buyer concluido · release',
        pre: 'is_hand LIKE; CPI exact-list não cobre MB WAY',
        repro: 'INSERT shipping=entrega em morada payment=MB WAY → pago+proof → concluido → release',
        expected: 'concluido denied / release false / Δ=0',
        obtained: {
          'pago': pago.brief,
          'concluido': concl.brief,
          'release': rel.brief,
          'delta': after - before,
          'shipped_at': row?['shipped_at'],
        },
      );
    } else if (concl.ok) {
      c.hold(
        id: 'BJ5-06-mbway-morada-concluido',
        lens: 'BJ5',
        severity: 'P1',
        title: 'MB WAY + "entrega em morada": buyer concluiu sem envio',
        actor: 'buyer JWT',
        pre: 'is_hand true; shipped_at null',
        repro: 'PATCH status=concluido após pago MB WAY',
        expected: 'order_concluido_requires_shipped',
        obtained: {
          'concluido': concl.brief,
          'status': row?['status'],
          'shipped_at': row?['shipped_at'],
          'release': rel.brief,
          'delta': after - before,
        },
      );
    }
  } else {
    c.block('BJ5-06-mbway-morada-concluido', 'BJ5', 'MB WAY morada concluido',
        {'pago': pago.brief, 'concl': concl.brief, 'row': row});
  }

  // Variante hand-ctt + Pagamento na app (sem CPI — reserva)
  final oid2 = await c.insertOrder(
    productId: pid,
    priceTotal: 7.2,
    shipping: 'hand-ctt',
    payment: 'MB WAY',
  );
  if (oid2 != null) {
    final pago2 = await c.rest('PATCH', 'orders?id=eq.$oid2', jwt: c.sellerJwt, body: {
      'status': 'pago',
      'proof_url': 'https://fleaber.pt/proof-bj2.png',
    });
    final concl2 = await c.rest('PATCH', 'orders?id=eq.$oid2', jwt: c.buyerJwt, body: {
      'status': 'concluido',
    });
    c.note('p2b.handctt', 'hand-ctt MB WAY', {
      'pago': pago2.brief,
      'concl': concl2.brief,
    }, lens: 'BJ5');
    if (concl2.ok) {
      c.hold(
        id: 'BJ5-07-hand-ctt-concluido',
        lens: 'BJ5',
        severity: 'P1',
        title: 'MB WAY + "hand-ctt": buyer concluiu sem envio',
        actor: 'buyer JWT',
        pre: 'is_hand LIKE hand%',
        repro: 'INSERT shipping=hand-ctt payment=MB WAY → pago → concluido',
        expected: 'denied',
        obtained: concl2.brief,
      );
    } else {
      c.block('BJ5-07-hand-ctt-concluido', 'BJ5', 'hand-ctt concluido', concl2);
    }
  }

  // Confirmar BJ5-05: shipped_at da order unship
  final unshipRow = await c.orderRow('65bfdec3-4d90-483f-8a3c-3aa0095f89c7');
  c.note('p2b.unship.check', 'order unship alleged', {
    'status': unshipRow?['status'],
    'shipped_at': unshipRow?['shipped_at'],
    'stripe_refund_id': unshipRow?['stripe_refund_id'],
  }, lens: 'BJ5');

  await c.dumpAll('pass2b.json');
  stdout.writeln('PASS2b findings=${c.findings.length}');
}
