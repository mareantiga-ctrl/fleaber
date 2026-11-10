/// Pass 3 — variantes extra no P0 stale live + confirmar qty2/bundle. Não corrigir.
import '_rtae.dart';

Future<void> main() async {
  final c = Rtae.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureSeller2();

  try {
    await _crossSellerLiveItem(c);
    await _patchLiveAfterSeal(c);
    await _pickCheapestHistorical(c);
    await _bundleStatusQty2(c);
  } catch (e, st) {
    c.note('crash', 'pass3', '$e\n$st');
  } finally {
    await c.dumpAll('pass3_findings.json');
  }
}

Future<void> _crossSellerLiveItem(Rtae c) async {
  final p1 = await c.createProduct(title: '$prefix-p3-s1', price: 40, qty: 2);
  final p2 = await c.createProduct(
    title: '$prefix-p3-s2',
    price: 5,
    qty: 2,
    seller: c.seller2Id,
  );
  if (p1 == null || p2 == null) return;
  final live2 = await c.insertLive(seller: c.seller2Id);
  if (live2 == null) return;
  final li2 = await c.insertMarketItem(
    liveId: live2,
    productId: p2,
    price: 5,
    jwt: c.seller2Jwt,
  );
  if (li2 == null) return;
  final o = await c.insertOrderHit(
    productId: p1,
    jwt: c.buyerJwt,
    liveItemId: li2,
    liveId: live2,
    price: 40,
  );
  c.note('p3.cross', 'live_item S2 em produto S1', o.brief, lens: 'AE1');
  if (o.ok) {
    final ck = await c.checkout(orderId: o.firstId!);
    c.note('p3.cross.ck', 'checkout cross', ck.brief, lens: 'AE1');
    if (ck.ok && (ck.amountTotal ?? 9999) < 2000) {
      c.hold(
        id: 'AE1-CROSS-SELLER-LIVE-ITEM',
        lens: 'AE1',
        severity: 'P0',
        title: 'live_item de outro vendedor baixou o checkout',
        actor: 'buyer JWT',
        pre: 'SKU S1 40€ + live_item S2 5€',
        repro: 'POST orders product=S1 live_item=S2',
        expected: 'coherence block',
        obtained: ck.amountTotal,
      );
    }
  } else {
    c.block('AE1-CROSS', 'AE1', 'cross-seller live_item recusado', o);
  }
}

Future<void> _patchLiveAfterSeal(Rtae c) async {
  final p = await c.createProduct(title: '$prefix-p3-patch', price: 40, qty: 2);
  if (p == null) return;
  final liveId = await c.insertLive();
  final li = liveId == null
      ? null
      : await c.insertMarketItem(
          liveId: liveId,
          productId: p,
          price: 5,
          jwt: c.sellerJwt,
        );
  final o = await c.insertOrder(productId: p, jwt: c.buyerJwt, price: 40);
  if (o == null || li == null) return;
  final row0 = await c.orderRow(o);
  final patch = await c.rest(
    'PATCH',
    'orders?id=eq.$o',
    jwt: c.buyerJwt,
    body: {'live_item_id': li, 'live_id': liveId},
  );
  final row1 = await c.orderRow(o);
  final ck = await c.checkout(orderId: o);
  c.note('p3.patch.li', 'PATCH live_item após selo 40€', {
    'c0': row0?['contract_unit_cents'],
    'c1': row1?['contract_unit_cents'],
    'li1': row1?['live_item_id'],
    'patch': patch.brief,
    'amt': ck.amountTotal,
    'want40': expectedQuoteCents(unitEur: 40),
  }, lens: 'AE1');
  if (ck.ok && (ck.amountTotal ?? 0) < 2000) {
    c.hold(
      id: 'AE1-PATCH-LIVE-ITEM-AFTER-SEAL',
      lens: 'AE1',
      severity: 'P0',
      title: 'PATCH live_item_id após INSERT rebaixa Session',
      actor: 'buyer JWT',
      pre: 'order selada a 40€',
      repro: 'PATCH live_item_id; create-payment-intent',
      expected: '4265 ou live_item immutable',
      obtained: ck.amountTotal,
    );
  } else {
    c.block('AE1-PATCH-LI', 'AE1', 'selo 40€ mantém-se após PATCH', ck);
  }
}

Future<void> _pickCheapestHistorical(Rtae c) async {
  final p = await c.createProduct(title: '$prefix-p3-hist', price: 40, qty: 3);
  if (p == null) return;
  final l1 = await c.insertLive();
  final l2 = await c.insertLive();
  if (l1 == null || l2 == null) return;
  final liHigh = await c.insertMarketItem(
    liveId: l1,
    productId: p,
    price: 25,
    jwt: c.sellerJwt,
  );
  final liLow = await c.insertMarketItem(
    liveId: l2,
    productId: p,
    price: 6,
    jwt: c.sellerJwt,
  );
  await c.rest('PATCH', 'lives?id=in.($l1,$l2)', service: true, body: {
    'is_active': false,
    'status': 'ended',
  }, prefer: 'return=minimal');
  if (liLow == null || liHigh == null) return;
  final o = await c.insertOrder(
    productId: p,
    jwt: c.buyerJwt,
    liveItemId: liLow,
    liveId: l2,
    price: 40,
  );
  if (o == null) return;
  final ck = await c.checkout(orderId: o);
  c.note('p3.hist', 'escolhe live_item histórico mais barato', {
    'amt': ck.amountTotal,
    'want6': expectedQuoteCents(unitEur: 6),
    'want25': expectedQuoteCents(unitEur: 25),
    'want40': expectedQuoteCents(unitEur: 40),
    'liLow': liLow,
    'liHigh': liHigh,
  }, lens: 'AE1');
  if (ck.ok && (ck.amountTotal ?? 0) == expectedQuoteCents(unitEur: 6)) {
    c.hold(
      id: 'AE1-PICK-CHEAPEST-ENDED-LIVE-ITEM',
      lens: 'AE1',
      severity: 'P0',
      title: 'Buyer escolhe o live_item ended mais barato de entre vários',
      actor: 'buyer JWT',
      pre: 'dois lives ended 25€ e 6€ no mesmo SKU 40€',
      repro: 'POST orders live_item_id=o mais barato; create-payment-intent',
      expected: 'catálogo 40€ após lives ended',
      obtained: ck.amountTotal,
    );
  }
}

Future<void> _bundleStatusQty2(Rtae c) async {
  final bun = await c.rest(
    'GET',
    'product_bundles?id=eq.05a60f77-4f39-4aaf-90cd-1ad6ed4e7e2e&select=id,status,total_eur,buyer_id,product_ids',
    service: true,
  );
  final o = await c.orderRow('106a762e-ea1e-42ef-be4d-f11fd4605311');
  final stock = o == null
      ? null
      : await c.productRow(o['product_id'].toString());
  c.note('p3.qty2.ctx', 'bundle+stock da order qty=2', {
    'bundle': bun.map,
    'order_qty': o?['quantity'],
    'stock': stock,
  }, lens: 'AE3');
}
