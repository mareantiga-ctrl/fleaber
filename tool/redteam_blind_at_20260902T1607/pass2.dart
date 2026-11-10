/// REDTEAM_BLIND_AT pass2 — confirmar mutação real; demotar 200 []; dual Session bag.
import 'dart:io';
import '_rtat.dart';

Future<void> main() async {
  final c = Rtat.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  // AT6-02: as duas cs_ da corrida do saco ainda vivas?
  const sidA = 'cs_test_a1gZVuung8MKncR4AKFrmE2OPUGSOAZhXDYlqbOcAmXkiB4ikKlj4EdfOd';
  const sidB = 'cs_test_a1WkDAjhRVNMLtRJnVyJviPmQ6AZdJKWJ37oF09r7G6dLXkxLcyNT3pRON';
  final aliveA = await c.checkoutAlive('https://checkout.stripe.com/c/pay/$sidA');
  final aliveB = await c.checkoutAlive('https://checkout.stripe.com/c/pay/$sidB');
  c.note('AT6.dual.alive', 'corrida saco cs_ A/B', {
    'A': aliveA,
    'B': aliveB,
  }, lens: 'AT6');
  final twoAlive = (aliveA ?? '').startsWith('alive') &&
      (aliveB ?? '').startsWith('alive');
  if (twoAlive) {
    c.hold(
      id: 'AT6-02b',
      lens: 'AT6',
      severity: 'P1',
      title: 'Corrida saco: as 2 Checkout Sessions continuam pagáveis',
      actor: 'buyer JWT',
      pre: 'Future.wait 2× bag_checkout',
      repro: 'GET checkout.stripe.com/c/pay/{cs_} nas duas cs_',
      expected: '1 viva (a outra expired)',
      obtained: 'A=$aliveA B=$aliveB',
      evidence: {'sidA': sidA, 'sidB': sidB},
    );
  } else {
    c.block('AT6-02b', 'AT6', 'corrida saco não deixou 2 cs_ pagáveis',
        'A=$aliveA B=$aliveB');
  }

  // AT7-03 / AT7-04: 200 [] — confirmar 0 mutação
  final p = await c.insertProduct(price: 9.0, qty: 2, title: '$prefix-p2');
  if (p != null && c.buyer2Jwt != null) {
    final o = await c.insertOrder(productId: p);
    if (o != null) {
      final before = await c.orderRow(o);
      final patch = await c.rest(
        'PATCH',
        'orders?id=eq.$o',
        jwt: c.buyer2Jwt,
        body: {'shipping_method': 'carrier'},
      );
      final after = await c.orderRow(o);
      final mutated = after?['shipping_method']?.toString() !=
          before?['shipping_method']?.toString();
      if (mutated) {
        c.hold(
          id: 'AT7-03b',
          lens: 'AT7',
          severity: 'P2',
          title: 'B2 alterou shipping da order B1 (mutação)',
          actor: 'buyer2 JWT',
          pre: 'order buyer=B1',
          repro: 'PATCH orders shipping_method=carrier',
          expected: '0 rows',
          obtained: 'before=${before?['shipping_method']} after=${after?['shipping_method']} http=${patch.status}',
        );
      } else {
        c.block('AT7-03b', 'AT7', 'B2 PATCH 200 [] sem mutação',
            'http=${patch.status} ship=${after?['shipping_method']}');
      }
    }

    final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_ids': [p],
      'status': 'pending',
    });
    if (bun.firstId != null) c.createdBundleIds.add(bun.firstId!);
    if (bun.firstId != null && c.seller2Jwt != null) {
      final beforeB = await c.rest(
        'GET',
        'product_bundles?id=eq.${bun.firstId}&select=id,status,discount_pct,total_eur,seller_id',
        service: true,
      );
      final s2 = await c.rest(
        'PATCH',
        'product_bundles?id=eq.${bun.firstId}',
        jwt: c.seller2Jwt,
        body: {'status': 'accepted', 'discount_pct': 50},
      );
      final afterB = await c.rest(
        'GET',
        'product_bundles?id=eq.${bun.firstId}&select=id,status,discount_pct,total_eur,seller_id',
        service: true,
      );
      final st0 = beforeB.map?['status']?.toString();
      final st1 = afterB.map?['status']?.toString();
      if (st1 != st0 && st1?.toLowerCase() == 'accepted') {
        c.hold(
          id: 'AT7-04b',
          lens: 'AT7',
          severity: 'P1',
          title: 'S2 aceitou bundle de S1 (mutação real)',
          actor: 'seller2 JWT',
          pre: 'bundle seller=S1 pending',
          repro: 'PATCH product_bundles status=accepted JWT S2',
          expected: 'status continua pending',
          obtained: '$st0 → $st1 http=${s2.status} pct=${afterB.map?['discount_pct']}',
        );
      } else {
        c.block('AT7-04b', 'AT7', 'S2 PATCH bundle 200 [] sem mutação',
            'http=${s2.status} $st0 → $st1');
      }
    }
  }

  // Ghost hold: cancelar order B1 stock=1, B2 deve conseguir hold
  final g = await c.insertProduct(price: 3.0, qty: 1, title: '$prefix-ghost');
  if (g != null && c.buyer2Jwt != null && c.buyer2Id != null) {
    final hold = await c.insertOrder(productId: g);
    if (hold != null) {
      final cancel = await c.rest(
        'PATCH',
        'orders?id=eq.$hold',
        jwt: c.buyerJwt,
        body: {'status': 'cancelado'},
      );
      final afterC = await c.orderRow(hold);
      final oB2 = await c.rest('POST', 'orders', jwt: c.buyer2Jwt, body: {
        'buyer_id': c.buyer2Id,
        'seller_id': c.sellerId,
        'product_id': g,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'entrega em mão',
      });
      if (oB2.firstId != null) c.createdOrderIds.add(oB2.firstId!);
      c.note('AT5.ghost', 'cancel B1 + hold B2', {
        'cancel': cancel.status,
        'st': afterC?['status'],
        'b2': oB2.status,
        'b2id': oB2.firstId,
        'err': oB2.err,
      }, lens: 'AT5');
      if (afterC?['status']?.toString().toLowerCase() == 'cancelado' &&
          !oB2.ok) {
        c.hold(
          id: 'AT5-04',
          lens: 'AT5',
          severity: 'P2',
          title: 'Hold fantasma: B2 não consegue stock após B1 cancelar',
          actor: 'buyer2 JWT',
          pre: 'stock=1; B1 order cancelada',
          repro: 'PATCH cancelado; POST order B2',
          expected: 'B2 INSERT 201',
          obtained: 'cancel=${afterC?['status']} b2=${oB2.brief}',
        );
      } else {
        c.block('AT5-04', 'AT5', 'após cancel o stock liberta para B2',
            'st=${afterC?['status']} b2=${oB2.status}');
      }
    }
  }

  // AT8 wallets após paid: seller +5€ no bag (3+7 itens). Observação.
  final w = await c.wallets();
  c.note('AT8.wallets.now', 'saldos', w, lens: 'AT8');

  await c.dumpAll('pass2.json');
  stdout.writeln(
      'PASS2 findings=${c.findings.length} blocked=${c.blocked.length}');
}
