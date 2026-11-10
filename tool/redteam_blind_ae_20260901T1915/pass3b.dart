/// Pass 3b — bundle realmente accepted + qty=2. Não corrigir.
import '_rtae.dart';

Future<void> main() async {
  final c = Rtae.fromEnv(loadEnv());
  await c.loginActors();
  try {
    final a = await c.createProduct(title: '$prefix-3b-a', price: 8, qty: 5);
    final b = await c.createProduct(title: '$prefix-3b-b', price: 30, qty: 5);
    if (a == null || b == null) return;
    final bun = await c.rest('POST', 'product_bundles', jwt: c.sellerJwt, body: {
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'product_ids': [a, b],
      'status': 'pending',
      'discount_pct': 10,
    });
    final bid = bun.firstId;
    c.note('3b.ins', 'seller bundle', bun.brief, lens: 'AE3');
    if (bid == null) return;
    c.createdBundleIds.add(bid);
    final acc = await c.rest(
      'PATCH',
      'product_bundles?id=eq.$bid',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    final row = await c.rest(
      'GET',
      'product_bundles?id=eq.$bid&select=id,status,total_eur,discount_pct',
      service: true,
    );
    c.note('3b.acc', 'seller accept', {
      'patch': acc.brief,
      'row': row.map,
    }, lens: 'AE3');
    final q2 = await c.insertOrderHit(
      productId: a,
      jwt: c.buyerJwt,
      qty: 2,
      price: 16,
      bundleId: bid,
    );
    c.note('3b.q2', 'qty=2 on accepted', q2.brief, lens: 'AE3');
    if (q2.ok && '${row.map?['status']}'.toLowerCase() == 'accepted') {
      c.hold(
        id: 'AE3-ACCEPTED-BUNDLE-QTY2',
        lens: 'AE3',
        severity: 'P1',
        title: 'Bundle accepted de verdade ainda aceita order quantity=2',
        actor: 'buyer JWT',
        pre: 'seller PATCH status=accepted',
        repro: 'POST orders quantity=2 bundle_id',
        expected: 'bundle_order_quantity_must_be_one',
        obtained: q2.map,
      );
      if (q2.firstId != null) {
        final ck = await c.checkout(orderId: q2.firstId!);
        c.note('3b.ck', 'checkout qty2 accepted', {
          'amt': ck.amountTotal,
          'want2': expectedQuoteCents(unitEur: 8, qty: 2),
          'want1': expectedQuoteCents(unitEur: 8, qty: 1),
        }, lens: 'AE3');
      }
    } else if (!q2.ok) {
      c.block('AE3-ACC-QTY2', 'AE3', 'qty=2 recusado em accepted real', q2);
    } else {
      c.skip('AE3-ACC', 'AE3', 'bundle não ficou accepted', row.map);
    }

    final q1 = await c.insertOrderHit(
      productId: a,
      jwt: c.buyerJwt,
      qty: 1,
      price: 8,
      bundleId: bid,
    );
    final q1b = await c.insertOrderHit(
      productId: b,
      jwt: c.buyerJwt,
      qty: 1,
      price: 30,
      bundleId: bid,
    );
    if (q1.firstId != null && q1b.firstId != null) {
      final bag = await c.checkoutBag(lines: [
        {'order_id': q1.firstId},
        {'order_id': q1b.firstId},
      ]);
      c.note('3b.bag', 'saco conjunto accepted', {
        'amt': bag.amountTotal,
        'catalog': expectedQuoteCents(unitEur: 38),
        'bundle_total': row.map?['total_eur'],
      }, lens: 'AE3');
    }
  } catch (e, st) {
    c.note('crash', '3b', '$e\n$st');
  } finally {
    await c.dumpAll('pass3b_findings.json');
  }
}
