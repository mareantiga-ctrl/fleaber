/// Pass 2 — poço nos achados AE. Stripe TEST se houver sk_test_. Não corrigir.
import '_rtae.dart';

Future<void> main() async {
  final c = Rtae.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  c.note('boot2', 'pass2', {
    'stripe': c.stripeTestKey != null,
    'b1': c.buyerId,
  });

  try {
    await _retractDiscountPatch(c);
    await _bundleForgeAndQty2(c);
    await _payStaleLive(c);
    await _buyerLiveItem(c);
    await _bagMetadata(c);
    await _qty2CheckoutAndHold(c);
  } catch (e, st) {
    c.note('crash', 'pass2 exception', '$e\n$st');
  } finally {
    await c.dumpAll('pass2_findings.json');
  }
}

Future<void> _retractDiscountPatch(Rtae c) async {
  final before = await c.rest(
    'GET',
    'seller_bundle_discounts?seller_id=eq.${c.sellerId}&select=seller_id,enabled,tier_2_pct,tier_3_pct,tier_5_pct,custom_tiers',
    service: true,
  );
  final patch = await c.rest(
    'PATCH',
    'seller_bundle_discounts?seller_id=eq.${c.sellerId}',
    jwt: c.buyerJwt,
    body: {
      'tier_2_pct': 49,
      'custom_tiers': [
        {'min_items': 2, 'pct': 90}
      ],
    },
  );
  final after = await c.rest(
    'GET',
    'seller_bundle_discounts?seller_id=eq.${c.sellerId}&select=seller_id,enabled,tier_2_pct,tier_3_pct,tier_5_pct,custom_tiers',
    service: true,
  );
  c.note('p2.disc', 'buyer PATCH vs row', {
    'patch_http': patch.status,
    'patch_len': patch.list.length,
    'before': before.map,
    'after': after.map,
  }, lens: 'AE3');
  final b2b = numOf(before.map?['tier_2_pct']);
  final b2a = numOf(after.map?['tier_2_pct']);
  if (patch.ok && b2a == 49 && b2b != 49) {
    c.hold(
      id: 'AE3-BUYER-PATCH-BUNDLE-DISCOUNT',
      lens: 'AE3',
      severity: 'P0',
      title: 'Buyer alterou de facto seller_bundle_discounts.tier_2_pct',
      actor: 'buyer JWT',
      pre: 'row seller',
      repro: 'PATCH seller_bundle_discounts tier_2_pct=49',
      expected: 'sem alteração',
      obtained: {'before': before.map, 'after': after.map},
    );
  } else {
    c.block(
      'AE3-DISC-NO-WRITE',
      'AE3',
      'PATCH 200 mas 0 rows / valores intactos — P0 pass1 falso',
      {
        'http': patch.status,
        'repr': patch.list.length,
        'tier_before': b2b,
        'tier_after': b2a,
      },
    );
  }
}

Future<void> _bundleForgeAndQty2(Rtae c) async {
  final bun = await c.rest(
    'GET',
    'product_bundles?id=eq.25a5db88-ef3d-41d2-b031-3e6a2d6c929a&select=id,status,total_eur,buyer_id,seller_id,product_ids',
    service: true,
  );
  c.note('p2.bundle.forged', 'bundle buyer total_eur', bun.map, lens: 'AE3');
  final total = numOf(bun.map?['total_eur']);
  final st = '${bun.map?['status']}'.toLowerCase();
  if (bun.ok && total != null && total <= 2 && st == 'accepted') {
    c.hold(
      id: 'AE3-BUNDLE-ROW-TOTAL-1',
      lens: 'AE3',
      severity: 'P2',
      title: 'Bundle accepted ficou com total_eur=1 na BD (checkout usou catálogo)',
      actor: 'buyer JWT',
      pre: 'INSERT total_eur=1',
      repro: 'GET product_bundles',
      expected: 'total alinhado ao catálogo ou INSERT recusado',
      obtained: bun.map,
    );
  } else if (total != null && total > 2) {
    c.block('AE3-BUNDLE-REWRITE', 'AE3', 'trigger reescreveu total_eur', bun.map);
  }

  final o = await c.orderRow('106a762e-ea1e-42ef-be4d-f11fd4605311');
  c.note('p2.qty2.row', 'order bundle qty=2', o, lens: 'AE3');
}

Future<void> _payStaleLive(Rtae c) async {
  const sid = 'cs_test_a1CPJ7RKEUbL7zBMy2ROuMjikFEjqFptdjaYztsAwhp5y5mUEvjalBSGXd';
  const oid = '7714f95a-608a-4d2f-8da4-681abe110cbc';
  const pid = '90048de5-4d3e-4295-8643-8a19d14b1262';

  final sess = await c.stripeSession(sid);
  c.note('p2.stale.sess', 'Stripe session stale', {
    'http': sess.status,
    'amount': sess.map?['amount_total'],
    'currency': sess.map?['currency'],
    'status': sess.map?['status'],
    'pay': sess.map?['payment_status'],
    'pi': sess.map?['payment_intent'],
    'meta': sess.map?['metadata'],
  }, lens: 'AE8');

  final w0 = await c.wallets();
  final prod0 = await c.productRow(pid);
  final order0 = await c.orderRow(oid);

  final pi = sess.map?['payment_intent']?.toString();
  if (pi != null && pi.startsWith('pi_')) {
    final conf = await c.stripeConfirmPi(pi);
    c.note('p2.stale.confirm', 'confirm PI TEST', {
      'http': conf.status,
      'st': conf.map?['status'],
      'amt': conf.map?['amount'],
      'err': conf.map?['error'] ?? conf.snippet,
    }, lens: 'AE8');
  } else if (c.stripeTestKey == null) {
    c.skip('AE8-STALE-PAY', 'AE8', 'sem sk_test_ local', 'no key');
  }

  final settle = await c.settleGet(sid);
  c.note('p2.stale.settle', 'GET settle', {
    'http': settle.status,
    'loc': settle.location,
    'body': settle.snippet,
  }, lens: 'AE8');

  final order1 = await c.orderRow(oid);
  final prod1 = await c.productRow(pid);
  final w1 = await c.wallets();
  c.note('p2.stale.after', 'BD pós-settle', {
    'order0': order0,
    'order1': order1,
    'prod0': prod0,
    'prod1': prod1,
    'w0': w0,
    'w1': w1,
  }, lens: 'AE8');

  final paid = '${order1?['status']}'.toLowerCase() == 'pago';
  final cents = numOf(order1?['amount_paid_cents']) ?? 0;
  if (paid && cents > 0 && cents < 2000) {
    c.hold(
      id: 'AE1-STALE-LIVE-CAPTURED',
      lens: 'AE8',
      severity: 'P0',
      title: 'Captura TEST: pagou ~5€ por SKU de catálogo 40€ (live_item ended)',
      actor: 'buyer JWT + Stripe TEST',
      pre: 'Session 590 cents vs catálogo 4265',
      repro: 'confirm PI + GET checkout_return=success',
      expected: 'recusa ou captura 4265',
      obtained: {
        'status': order1?['status'],
        'amount_paid_cents': cents,
        'product_qty': prod1?['quantity'],
        'wallets': w1,
      },
      evidence: {'order': order1, 'product': prod1},
    );
  }

  // Recriar o ataque fresco se a Session pass1 já expirou.
  final pNew = await c.createProduct(
    title: '$prefix-ae8-stale',
    price: 40,
    qty: 2,
  );
  if (pNew == null) return;
  final liveId = await c.insertLive(active: true);
  if (liveId == null) return;
  final li = await c.insertMarketItem(
    liveId: liveId,
    productId: pNew,
    price: 5,
    jwt: c.sellerJwt,
  );
  await c.rest('PATCH', 'lives?id=eq.$liveId', service: true, body: {
    'is_active': false,
    'status': 'ended',
  }, prefer: 'return=minimal');
  if (li == null) return;
  final oid2 = await c.insertOrder(
    productId: pNew,
    jwt: c.buyerJwt,
    price: 40,
    liveItemId: li,
    liveId: liveId,
  );
  if (oid2 == null) return;
  final ck = await c.checkout(orderId: oid2, amount: 1);
  c.note('p2.stale.fresh', 'replay ended live price', {
    'amt': ck.amountTotal,
    'sid': ck.sessionId,
    'want40': expectedQuoteCents(unitEur: 40),
    'want5': expectedQuoteCents(unitEur: 5),
  }, lens: 'AE1');
  if (ck.ok && (ck.amountTotal ?? 0) == 590) {
    final sess2 = await c.stripeSession(ck.sessionId ?? '');
    final pi2 = sess2.map?['payment_intent']?.toString();
    if (pi2 != null && pi2.startsWith('pi_')) {
      final conf2 = await c.stripeConfirmPi(pi2);
      final set2 = await c.settleGet(ck.sessionId!);
      final o2 = await c.orderRow(oid2);
      final pr = await c.productRow(pNew);
      c.note('p2.stale.fresh.pay', 'captura replay', {
        'conf': conf2.brief,
        'settle': set2.status,
        'order': o2,
        'product': pr,
      }, lens: 'AE8');
      final c2 = numOf(o2?['amount_paid_cents']) ?? 0;
      if ('${o2?['status']}'.toLowerCase() == 'pago' && c2 == 590) {
        c.hold(
          id: 'AE1-STALE-LIVE-CAPTURED',
          lens: 'AE8',
          severity: 'P0',
          title: 'Captura TEST replay: 590 cents vs catálogo 40€',
          actor: 'buyer JWT + Stripe TEST',
          pre: 'SKU 40€ live_item ended 5€',
          repro: 'orders+live_item ended; checkout; confirm PI TEST; GET settle',
          expected: '4265 cents',
          obtained: {'order': o2, 'product': pr, 'confirm': conf2.map},
        );
      }
    }
  }

  // Controlo: mesma SKU sem live_item → 40€.
  final pCtrl = await c.createProduct(
    title: '$prefix-ae8-ctrl',
    price: 40,
    qty: 1,
  );
  if (pCtrl != null) {
    final oc = await c.insertOrder(productId: pCtrl, jwt: c.buyerJwt, price: 40);
    if (oc != null) {
      final ckc = await c.checkout(orderId: oc);
      c.note('p2.ctrl.40', 'sem live_item', {
        'amt': ckc.amountTotal,
        'want': expectedQuoteCents(unitEur: 40),
      }, lens: 'AE1');
    }
  }
}

Future<void> _buyerLiveItem(Rtae c) async {
  final p = await c.createProduct(title: '$prefix-ae1-bli', price: 40, qty: 2);
  if (p == null) return;
  final liveId = await c.insertLive();
  if (liveId == null) return;
  final li = await c.insertMarketItem(
    liveId: liveId,
    productId: p,
    price: 1,
    jwt: c.buyerJwt,
  );
  c.note('p2.buyer.li', 'buyer INSERT live_item price=1', li, lens: 'AE1');
  if (li != null) {
    c.hold(
      id: 'AE1-BUYER-FORGE-LIVE-ITEM',
      lens: 'AE1',
      severity: 'P0',
      title: 'Buyer criou live_item a 1€ no live do vendedor',
      actor: 'buyer JWT',
      pre: 'live do seller',
      repro: 'POST live_items price=1 jwt buyer',
      expected: 'RLS insert own live',
      obtained: li,
    );
  } else {
    c.block('AE1-BUYER-LI', 'AE1', 'buyer não cria live_item', 'null');
  }

  // live ainda activa: preço live vs catálogo (pode ser intencional).
  final liS = await c.insertMarketItem(
    liveId: liveId,
    productId: p,
    price: 5,
    jwt: c.sellerJwt,
  );
  if (liS != null) {
    final o = await c.insertOrder(
      productId: p,
      jwt: c.buyerJwt,
      liveItemId: liS,
      liveId: liveId,
      price: 40,
    );
    if (o != null) {
      final ck = await c.checkout(orderId: o);
      c.note('p2.live.active', 'live ACTIVA price 5 vs cat 40', {
        'amt': ck.amountTotal,
        'want5': expectedQuoteCents(unitEur: 5),
        'want40': expectedQuoteCents(unitEur: 40),
      }, lens: 'AE1');
    }
  }
}

Future<void> _bagMetadata(Rtae c) async {
  const sid = 'cs_test_a10w2Yvwy8dJEJPTJT78bZaqqj2zYnmvJrzlnBwRAHQ7yDfuge90SAfAHk';
  final sess = await c.stripeSession(sid);
  c.note('p2.bag.meta', 'metadata Session reutilizada A+B vs A+C', {
    'http': sess.status,
    'meta': sess.map?['metadata'],
    'amount': sess.map?['amount_total'],
  }, lens: 'AE2');
}

Future<void> _qty2CheckoutAndHold(Rtae c) async {
  const oid = '106a762e-ea1e-42ef-be4d-f11fd4605311';
  final row = await c.orderRow(oid);
  if (row == null) {
    c.skip('AE3-QTY2-CK', 'AE3', 'order qty2 desapareceu', 'null');
    return;
  }
  final ck = await c.checkout(orderId: oid);
  final want1 = expectedQuoteCents(unitEur: 8, qty: 1);
  final want2 = expectedQuoteCents(unitEur: 8, qty: 2);
  c.note('p2.qty2.ck', 'checkout bundle line qty=2', {
    'qty': row['quantity'],
    'cq': row['contract_qty'],
    'amt': ck.amountTotal,
    'want1': want1,
    'want2': want2,
    'http': ck.status,
    'err': ck.ok ? null : ck.snippet,
  }, lens: 'AE3');
  if (ck.ok && (ck.amountTotal ?? 0) == want2) {
    c.hold(
      id: 'AE3-BUNDLE-QTY2-CHECKOUT',
      lens: 'AE3',
      severity: 'P1',
      title: 'Checkout cobra 2 unidades numa linha de conjunto aceite',
      actor: 'buyer JWT',
      pre: 'bundle accepted; order quantity=2',
      repro: 'POST create-payment-intent order qty=2',
      expected: 'qty=1 ou recusa bundle_order_quantity_must_be_one',
      obtained: {
        'amount_total': ck.amountTotal,
        'session': ck.sessionId,
        'order': row,
      },
    );
  }
}
