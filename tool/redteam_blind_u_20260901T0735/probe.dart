/// REDTEAM_BLIND_U_MARKETPLACE_CHECKOUT_v1
/// dart run tool/redteam_blind_u_20260901T0735/probe.dart
/// Staging only. No production. No SQL/Edge/Flutter patches.
import 'dart:io';

import '_rtu.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rtu.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final w0 = await c.wallets();
  c.note('w0', 'wallets t0', w0, lens: 'U8');

  // =====================================================================
  // U1 — saco / qty
  // =====================================================================
  final skuQty = await c.createProduct(title: '$prefix qty-race', qty: 3, price: 11);
  if (skuQty != null) {
    final over = await c.insertOrder(
      productId: skuQty,
      jwt: c.buyerJwt,
      qty: 99,
      price: 11,
    );
    c.note('u1.qty99', 'INSERT qty=99 stock=3', over ?? 'null-id', lens: 'U1');
    if (over != null) {
      c.hold(
        id: 'RTU-U1-qty99-hold',
        lens: 'U1',
        severity: 'P0',
        title: 'Hold JWT qty=99 com stock=3',
        actor: 'buyer JWT',
        pre: 'SKU qty=3',
        repro: 'POST orders quantity=99',
        expected: 'order_hold_exceeds_stock / invalid_order_quantity',
        obtained: over,
      );
    } else {
      c.block('RTU-U1-qty99', 'U1', 'qty=99 bloqueado', 'no order id');
    }

    final q0 = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': skuQty,
      'quantity': 0,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    c.note('u1.qty0', 'INSERT qty=0', q0.brief, lens: 'U1');
    if (q0.ok && q0.firstId != null) {
      c.createdOrderIds.add(q0.firstId!);
      final row = await c.orderRow(q0.firstId!);
      final sealedQty = numOf(row?['quantity']) ?? numOf(row?['contract_qty']);
      if ((sealedQty ?? 0) >= 1 && q0.ok) {
        c.note('u1.qty0.seal', 'qty=0 selado para $sealedQty', row, lens: 'U1');
      }
    }

    // Race: B1 qty=2 e B2 qty=2 em stock=3
    final r1 = c.insertOrder(
      productId: skuQty,
      jwt: c.buyerJwt,
      qty: 2,
      price: 11,
    );
    final r2 = c.insertOrder(
      productId: skuQty,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
      qty: 2,
      price: 11,
    );
    final raceQty = await Future.wait([r1, r2]);
    c.note('u1.race.2of3', 'B1 qty=2 ∥ B2 qty=2 stock=3', raceQty, lens: 'U1');
    final held = raceQty.whereType<String>().toList();
    if (held.length >= 2) {
      c.hold(
        id: 'RTU-U1-race-qty-variant',
        lens: 'U1',
        severity: 'P0',
        title: 'Dois holds qty=2 em stock=3 (variante last-unit)',
        actor: 'buyer JWT ∥ buyer2 JWT',
        pre: 'SKU qty=3',
        repro: 'Future.wait POST orders quantity=2',
        expected: 'só um hold cabe (2+2>3)',
        obtained: held,
      );
    } else {
      c.block('RTU-U1-race-2of3', 'U1', 'race qty=2 stock=3 serializou', held);
    }

    // PATCH qty após hold
    if (held.isNotEmpty) {
      final patchQty = await c.rest(
        'PATCH',
        'orders?id=eq.${held.first}',
        jwt: c.buyerJwt,
        body: {'quantity': 3},
      );
      c.note('u1.patch.qty', 'PATCH quantity após hold', patchQty.brief, lens: 'U1');
      if (patchQty.ok) {
        c.hold(
          id: 'RTU-U1-patch-qty',
          lens: 'U1',
          severity: 'P0',
          title: 'JWT altera quantity após hold',
          actor: 'buyer JWT',
          pre: 'order reserva_pendente',
          repro: 'PATCH orders.quantity=3',
          expected: 'order_money_fields_immutable',
          obtained: patchQty.brief,
        );
      } else {
        c.block('RTU-U1-patch-qty', 'U1', 'quantity imutável', patchQty.brief);
      }
    }
  }

  // Unlist alheio
  final skuUnlist = await c.createProduct(title: '$prefix unlist-other', qty: 2, price: 9);
  if (skuUnlist != null) {
    final alienUnlist = await c.rest(
      'PATCH',
      'products?id=eq.$skuUnlist',
      jwt: c.buyerJwt,
      body: {'list_on_marketplace': false},
    );
    c.note('u1.unlist.alien', 'B PATCH unlist SKU de S', alienUnlist.brief, lens: 'U1');
    if (alienUnlist.ok) {
      c.hold(
        id: 'RTU-U1-unlist-alheio',
        lens: 'U1',
        severity: 'P0',
        title: 'Comprador unlista anúncio alheio',
        actor: 'buyer JWT',
        pre: 'produto seller',
        repro: 'PATCH products.list_on_marketplace=false',
        expected: 'RLS deny',
        obtained: alienUnlist.brief,
      );
    } else {
      c.block('RTU-U1-unlist-alheio', 'U1', 'unlist alheio bloqueado', alienUnlist.brief);
    }
  }

  // Cross-seller bag
  final skuS1 = await c.createProduct(title: '$prefix bag-s1', qty: 2, price: 8);
  final skuS2 = await c.createProduct(
    title: '$prefix bag-s2',
    qty: 2,
    price: 8,
    seller: c.seller2Id,
  );
  String? oidS1;
  String? oidS2own;
  if (skuS1 != null) {
    oidS1 = await c.insertOrder(productId: skuS1, jwt: c.buyerJwt, price: 8);
  }
  if (skuS2 != null) {
    oidS2own = await c.insertOrder(
      productId: skuS2,
      jwt: c.buyerJwt,
      seller: c.seller2Id,
      price: 8,
    );
  }
  if (oidS1 != null && oidS2own != null) {
    final crossBag = await c.checkoutBag(
      lines: [
        {'order_id': oidS1, 'product_id': skuS1, 'seller_id': c.sellerId},
        {'order_id': oidS2own, 'product_id': skuS2, 'seller_id': c.seller2Id},
      ],
      amount: 50,
    );
    c.note('u1.cross.seller.bag', 'bag 2 sellers', crossBag.brief, lens: 'U1');
    if (crossBag.ok && (crossBag.checkoutSessionId ?? '').startsWith('cs_')) {
      c.hold(
        id: 'RTU-U1-cross-seller-bag',
        lens: 'U1',
        severity: 'P0',
        title: 'Checkout saco com dois vendedores',
        actor: 'buyer JWT',
        pre: '2 orders sellers distintos',
        repro: 'POST create-payment-intent bag_checkout 2 sellers',
        expected: 'bag lines must share one seller',
        obtained: crossBag.brief,
      );
    } else {
      c.block('RTU-U1-cross-seller-bag', 'U1', 'cross-seller bag bloqueado', crossBag.brief);
    }
  }

  // Steal bag line
  if (oidS1 != null && skuS1 != null) {
    final steal = await c.checkoutBag(
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
      lines: [
        {'order_id': oidS1, 'product_id': skuS1, 'seller_id': c.sellerId},
      ],
      amount: 50,
    );
    c.note('u1.steal.bag', 'B2 paga order de B1', steal.brief, lens: 'U1');
    if (steal.ok && (steal.checkoutSessionId ?? '').startsWith('cs_')) {
      c.hold(
        id: 'RTU-U1-steal-bag-line',
        lens: 'U1',
        severity: 'P0',
        title: 'B2 abre Session Stripe na order de B1',
        actor: 'buyer2 JWT',
        pre: 'order buyer=B1',
        repro: 'POST create-payment-intent bag_lines order_id B1',
        expected: 'order does not belong to buyer',
        obtained: steal.brief,
      );
    } else {
      c.block('RTU-U1-steal-bag', 'U1', 'steal bag line bloqueado', steal.brief);
    }
  }

  // Same SKU two lines vs stock 1
  final skuDup = await c.createProduct(title: '$prefix same-sku-2lines', qty: 1, price: 10);
  if (skuDup != null) {
    final a = await c.insertOrder(productId: skuDup, jwt: c.buyerJwt, qty: 1, price: 10);
    final b = await c.insertOrder(productId: skuDup, jwt: c.buyerJwt, qty: 1, price: 10);
    c.note('u1.samesku.holds', '2 holds mesmo SKU stock=1', {'a': a, 'b': b}, lens: 'U1');
    if (a != null && b != null) {
      c.hold(
        id: 'RTU-U1-same-sku-two-holds',
        lens: 'U1',
        severity: 'P0',
        title: 'Dois holds do mesmo comprador no último stock',
        actor: 'buyer JWT',
        pre: 'SKU qty=1',
        repro: '2× POST orders quantity=1',
        expected: '2.º hold recusado',
        obtained: {'a': a, 'b': b},
      );
      final bagSame = await c.checkoutBag(
        lines: [
          {'order_id': a, 'product_id': skuDup},
          {'order_id': b, 'product_id': skuDup},
        ],
        amount: 50,
      );
      c.note('u1.samesku.bag', 'bag 2 linhas mesmo SKU', bagSame.brief, lens: 'U1');
      if (bagSame.ok && (bagSame.checkoutSessionId ?? '').startsWith('cs_')) {
        c.hold(
          id: 'RTU-U1-same-sku-bag-session',
          lens: 'U1',
          severity: 'P0',
          title: 'Session saco para 2 unidades com stock=1',
          actor: 'buyer JWT',
          pre: '2 orders mesmo SKU',
          repro: 'bag_checkout 2 lines same product_id',
          expected: 'quantity exceeds available stock',
          obtained: bagSame.brief,
        );
      } else {
        c.block('RTU-U1-same-sku-bag', 'U1', 'bag mesmo SKU bloqueado no quote', bagSame.brief);
      }
    } else {
      c.block('RTU-U1-same-sku-holds', 'U1', '2.º hold mesmo SKU recusado', {'a': a, 'b': b});
    }
  }

  // =====================================================================
  // U2 — oferta / bundle
  // =====================================================================
  final skuOffer = await c.createProduct(title: '$prefix offer', qty: 4, price: 20);
  String? offerPending;
  String? chatOffer;
  if (skuOffer != null) {
    chatOffer = await c.ensureChat(skuOffer);
    final offerIns = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
      'product_id': skuOffer,
      'chat_id': chatOffer,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'amount': 0.01,
      'list_price': 20,
      'offered_by': 'buyer',
      'status': 'pending',
      'expires_at': DateTime.now().toUtc().add(const Duration(hours: 48)).toIso8601String(),
    });
    c.note('u2.offer.001', 'REST oferta 0.01€ (Flutter pede < list)', offerIns.brief, lens: 'U2');
    offerPending = offerIns.firstId;
    if (offerPending != null) c.createdOfferIds.add(offerPending);

    // Self-accept
    if (offerPending != null) {
      final selfAcc = await c.rest(
        'PATCH',
        'product_offers?id=eq.$offerPending',
        jwt: c.buyerJwt,
        body: {'status': 'accepted'},
      );
      c.note('u2.offer.self', 'B aceita a própria oferta', selfAcc.brief, lens: 'U2');
      if (selfAcc.ok && (selfAcc.map?['status']?.toString() == 'accepted')) {
        c.hold(
          id: 'RTU-U2-offer-self-accept',
          lens: 'U2',
          severity: 'P0',
          title: 'Comprador aceita a própria oferta',
          actor: 'buyer JWT',
          pre: 'offered_by=buyer pending',
          repro: 'PATCH product_offers.status=accepted',
          expected: 'offer_accept_not_authorized',
          obtained: selfAcc.brief,
        );
      } else {
        c.block('RTU-U2-self-accept', 'U2', 'self-accept bloqueado', selfAcc.brief);
      }

      final acc = await c.rest(
        'PATCH',
        'product_offers?id=eq.$offerPending',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
      c.note('u2.offer.seller.acc', 'S aceita 0.01€', acc.brief, lens: 'U2');
      if (acc.ok && acc.map?['status']?.toString() == 'accepted') {
        final oidOffer = await c.insertOrder(
          productId: skuOffer,
          jwt: c.buyerJwt,
          offerId: offerPending,
          price: 0.01,
        );
        c.note('u2.offer.order', 'order com oferta 0.01', oidOffer, lens: 'U2');
        if (oidOffer != null) {
          final orow = await c.orderRow(oidOffer);
          final unit = numOf(orow?['contract_unit_cents']);
          c.note('u2.offer.seal', 'contrato selado', orow, lens: 'U2');
          final ck = await c.checkout(orderId: oidOffer, amount: 50, productId: skuOffer);
          c.note('u2.offer.checkout', 'checkout oferta 0.01', ck.brief, lens: 'U2');
          final paidAmt = ck.serverAmount;
          if (ck.ok && paidAmt != null && paidAmt < 200 && (unit ?? 0) <= 1) {
            c.hold(
              id: 'RTU-U2-offer-penny-checkout',
              lens: 'U2',
              severity: 'P1',
              title: 'Session Stripe ao preço da oferta 0,01€ (REST, sem piso)',
              actor: 'buyer JWT + seller accept',
              pre: 'oferta 0.01 aceite; catálogo 20€',
              repro: 'POST product_offers amount=0.01; accept; create-payment-intent',
              expected: 'piso de oferta ou recusa de amount << list',
              obtained: {
                'server_amount_cents': paidAmt,
                'contract_unit_cents': unit,
                'session': ck.checkoutSessionId,
              },
            );
          }
        }

        // 2.ª order mesma oferta
        final oid2 = await c.insertOrder(
          productId: skuOffer,
          jwt: c.buyerJwt,
          offerId: offerPending,
          price: 0.01,
        );
        c.note('u2.offer.reuse', '2.ª order mesma oferta', oid2, lens: 'U2');
        if (oid2 != null) {
          final r2 = await c.orderRow(oid2);
          final unit2 = numOf(r2?['contract_unit_cents']);
          if ((unit2 ?? 9999) <= 1) {
            c.hold(
              id: 'RTU-U2-offer-reuse',
              lens: 'U2',
              severity: 'P0',
              title: 'Oferta aceite reutilizada na 2.ª unidade',
              actor: 'buyer JWT',
              pre: 'oferta já ligada a order',
              repro: 'POST orders product_offer_id=<consumed>',
              expected: 'offer_already_consumed / catálogo',
              obtained: r2,
            );
          } else {
            c.block('RTU-U2-offer-reuse', 'U2', '2.ª order não herda oferta', {
              'unit2': unit2,
              'offer_id': r2?['product_offer_id'],
            });
          }
        }
      }
    }

    // Oferta morta: unlist então accept
    final skuDead = await c.createProduct(title: '$prefix offer-dead', qty: 2, price: 15);
    if (skuDead != null) {
      final ch = await c.ensureChat(skuDead);
      final deadIns = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
        'product_id': skuDead,
        'chat_id': ch,
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'amount': 10,
        'list_price': 15,
        'offered_by': 'buyer',
        'status': 'pending',
      });
      final deadId = deadIns.firstId;
      if (deadId != null) c.createdOfferIds.add(deadId);
      await c.rest(
        'PATCH',
        'products?id=eq.$skuDead',
        jwt: c.sellerJwt,
        body: {'list_on_marketplace': false},
      );
      if (deadId != null) {
        final deadAcc = await c.rest(
          'PATCH',
          'product_offers?id=eq.$deadId',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
        c.note('u2.offer.dead', 'accept após unlist', deadAcc.brief, lens: 'U2');
        if (deadAcc.ok && deadAcc.map?['status']?.toString() == 'accepted') {
          c.hold(
            id: 'RTU-U2-dead-offer-accept',
            lens: 'U2',
            severity: 'P1',
            title: 'Aceitar oferta de artigo já unlistado',
            actor: 'seller JWT',
            pre: 'list_on_marketplace=false',
            repro: 'PATCH offer accepted após unlist',
            expected: 'offer_product_not_listed',
            obtained: deadAcc.brief,
          );
        } else {
          c.block('RTU-U2-dead-offer', 'U2', 'oferta morta bloqueada', deadAcc.brief);
        }
      }
    }

    // Expire então accept
    final skuExp = await c.createProduct(title: '$prefix offer-exp', qty: 2, price: 18);
    if (skuExp != null) {
      final ch = await c.ensureChat(skuExp);
      final expIns = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
        'product_id': skuExp,
        'chat_id': ch,
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'amount': 9,
        'list_price': 18,
        'offered_by': 'buyer',
        'status': 'pending',
        'expires_at': DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String(),
      });
      final expId = expIns.firstId;
      c.note('u2.offer.exp.insert', 'oferta já expirada no INSERT', expIns.brief, lens: 'U2');
      if (expId != null) {
        c.createdOfferIds.add(expId);
        final expAcc = await c.rest(
          'PATCH',
          'product_offers?id=eq.$expId',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
        c.note('u2.offer.exp.acc', 'accept oferta expires_at no passado', expAcc.brief, lens: 'U2');
        if (expAcc.ok && expAcc.map?['status']?.toString() == 'accepted') {
          c.hold(
            id: 'RTU-U2-expired-offer-accept',
            lens: 'U2',
            severity: 'P1',
            title: 'Aceitar oferta com expires_at no passado',
            actor: 'seller JWT',
            pre: 'expires_at < now, status pending',
            repro: 'PATCH accepted',
            expected: 'recusa / expire cron',
            obtained: expAcc.brief,
          );
        } else {
          c.block('RTU-U2-expired-accept', 'U2', 'oferta expirada não aceita', expAcc.brief);
        }
      }
    }
  }

  // Bundle: total aceite ≠ checkout (descontos tabela vs bundle.total_eur)
  final bA = await c.createProduct(title: '$prefix bundle-A', qty: 2, price: 20);
  final bB = await c.createProduct(title: '$prefix bundle-B', qty: 2, price: 20);
  if (bA != null && bB != null) {
    final discOff = await c.rest(
      'POST',
      'seller_bundle_discounts',
      jwt: c.sellerJwt,
      body: {
        'seller_id': c.sellerId,
        'enabled': false,
        'tier_2_pct': 0,
        'tier_3_pct': 0,
        'tier_5_pct': 0,
        'custom_tiers': [],
      },
    );
    // upsert
    final discUp = await c.rest(
      'PATCH',
      'seller_bundle_discounts?seller_id=eq.${c.sellerId}',
      jwt: c.sellerJwt,
      body: {
        'enabled': false,
        'tier_2_pct': 0,
        'tier_3_pct': 0,
        'tier_5_pct': 0,
        'custom_tiers': <Map<String, Object>>[],
      },
    );
    c.note('u2.disc.off', 'descontos loja OFF', '${discOff.brief} / ${discUp.brief}', lens: 'U2');

    final chatB = await c.ensureChat(bA);
    final bunIns = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'chat_id': chatB,
      'product_ids': [bA, bB],
      'subtotal_eur': 40,
      'discount_pct': 50,
      'discount_eur': 20,
      'total_eur': 20,
      'status': 'pending',
    });
    c.note('u2.bundle.ins', 'buyer INSERT bundle (pct deve ir a 0)', bunIns.brief, lens: 'U2');
    final bunId = bunIns.firstId;
    if (bunId != null) c.createdBundleIds.add(bunId);

    if (bunId != null) {
      final bunPct = await c.rest(
        'PATCH',
        'product_bundles?id=eq.$bunId',
        jwt: c.sellerJwt,
        body: {'discount_pct': 50, 'status': 'accepted'},
      );
      c.note('u2.bundle.accept50', 'S accept + 50%', bunPct.brief, lens: 'U2');
      final bunRow = bunPct.map ??
          (await c.rest('GET', 'product_bundles?id=eq.$bunId', service: true)).map;
      final bundleTotal = numOf(bunRow?['total_eur']);
      c.note('u2.bundle.row', 'bundle após accept', bunRow, lens: 'U2');

      final oA = await c.insertOrder(
        productId: bA,
        jwt: c.buyerJwt,
        bundleId: bunId,
        price: 10,
        shipping: 'entrega em mão',
      );
      final oB = await c.insertOrder(
        productId: bB,
        jwt: c.buyerJwt,
        bundleId: bunId,
        price: 10,
        shipping: 'entrega em mão',
      );
      if (oA != null && oB != null) {
        final ra = await c.orderRow(oA);
        final rb = await c.orderRow(oB);
        c.note('u2.bundle.orders', 'contratos das linhas', {
          'a': ra?['contract_unit_cents'],
          'b': rb?['contract_unit_cents'],
          'price_a': ra?['price_total'],
          'price_b': rb?['price_total'],
        }, lens: 'U2');

        final bag = await c.checkoutBag(
          lines: [
            {'order_id': oA, 'product_id': bA},
            {'order_id': oB, 'product_id': bB},
          ],
          amount: 2000,
          shipping: 'mao',
        );
        c.note('u2.bundle.checkout', 'bag checkout vs bundle.total', bag.brief, lens: 'U2');
        final server = bag.serverAmount;
        final itemsFull = 20 * 100 + 20 * 100;
        final itemsHalf = (itemsFull * 0.5).round();
        final protFull = protectionFeeCents(itemsFull, 0);
        final protHalf = protectionFeeCents(itemsHalf, 0);
        final expectFull = itemsFull + protFull;
        final expectHalf = itemsHalf + protHalf;
        if (bag.ok && server != null) {
          final vsBundle = bundleTotal == null ? null : euroToCents(bundleTotal) + protHalf;
          if (server >= expectFull - 2 && (bundleTotal ?? 40) <= 20.01) {
            c.hold(
              id: 'RTU-U2-bundle-total-ignored',
              lens: 'U2',
              severity: 'P1',
              title: 'Checkout Stripe ignora total_eur do conjunto aceite (50% vs 0%)',
              actor: 'buyer JWT checkout bag',
              pre: 'bundle accepted discount_pct=50 total=20; seller_bundle_discounts disabled',
              repro: 'POST create-payment-intent bag_checkout das 2 orders',
              expected: 'server_amount ≈ 20€ itens + protecção',
              obtained: {
                'server_amount_cents': server,
                'expect_half_cents': expectHalf,
                'expect_full_cents': expectFull,
                'bundle_total_eur': bundleTotal,
                'vs_bundle_plus_prot': vsBundle,
                'session': bag.checkoutSessionId,
              },
            );
          } else if ((server - expectHalf).abs() <= 2) {
            c.block('RTU-U2-bundle-match', 'U2', 'checkout alinhado a 50%', server);
          } else {
            c.note('u2.bundle.amt.other', 'montante fora dos dois pólos', {
              'server': server,
              'full': expectFull,
              'half': expectHalf,
            }, lens: 'U2');
          }
        }

        // Dual Session no saco (claim só no single)
        final bag2 = await c.checkoutBag(
          lines: [
            {'order_id': oA, 'product_id': bA},
            {'order_id': oB, 'product_id': bB},
          ],
          amount: 50,
        );
        c.note('u2.bag.dual', '2.º POST bag mesmo par', {
          's1': bag.checkoutSessionId,
          's2': bag2.checkoutSessionId,
          'b2': bag2.brief,
        }, lens: 'U3');
        final cs1 = bag.checkoutSessionId ?? '';
        final cs2 = bag2.checkoutSessionId ?? '';
        if (cs1.startsWith('cs_') && cs2.startsWith('cs_') && cs1 != cs2) {
          c.hold(
            id: 'RTU-U3-bag-dual-session',
            lens: 'U3',
            severity: 'P1',
            title: 'Saco marketplace cria 2 Checkout Sessions (sem claim)',
            actor: 'buyer JWT',
            pre: 'bag_checkout (claim só no single)',
            repro: '2× POST create-payment-intent bag_checkout',
            expected: 'reuse da Session aberta',
            obtained: {'cs1': cs1, 'cs2': cs2},
          );
        } else {
          c.block('RTU-U3-bag-dual', 'U3', '2.º bag reutiliza ou recusa', {
            'cs1': cs1,
            'cs2': cs2,
            'b2': bag2.brief,
          });
        }
      }

      // Race accept ∥ unlist
      final bC = await c.createProduct(title: '$prefix bun-race-A', qty: 1, price: 14);
      final bD = await c.createProduct(title: '$prefix bun-race-B', qty: 1, price: 14);
      if (bC != null && bD != null) {
        final bun2 = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
          'seller_id': c.sellerId,
          'buyer_id': c.buyerId,
          'product_ids': [bC, bD],
          'status': 'pending',
        });
        final bun2id = bun2.firstId;
        if (bun2id != null) {
          c.createdBundleIds.add(bun2id);
          final raceBun = await parallel([
            c.rest(
              'PATCH',
              'product_bundles?id=eq.$bun2id',
              jwt: c.sellerJwt,
              body: {'status': 'accepted', 'discount_pct': 10},
            ),
            c.rest(
              'PATCH',
              'products?id=eq.$bC',
              jwt: c.sellerJwt,
              body: {'list_on_marketplace': false},
            ),
          ]);
          c.note('u2.bundle.race.unlist', 'accept ∥ unlist', {
            'accept': raceBun[0].brief,
            'unlist': raceBun[1].brief,
          }, lens: 'U2');
          final st = raceBun[0].map?['status']?.toString();
          if (st == 'accepted') {
            final after = await c.productRow(bC);
            if (after?['list_on_marketplace'] == false) {
              c.hold(
                id: 'RTU-U2-bundle-accept-unlist-race',
                lens: 'U2',
                severity: 'P1',
                title: 'Conjunto aceite em corrida com unlist de um SKU',
                actor: 'seller JWT Future.wait',
                pre: 'bundle pending; unlist membro',
                repro: 'PATCH accepted ∥ PATCH list_on_marketplace=false',
                expected: 'bundle_product_not_listed OU unlist depois falha o accept',
                obtained: {
                  'accept': raceBun[0].brief,
                  'listed': after?['list_on_marketplace'],
                },
              );
            }
          } else {
            c.block('RTU-U2-bundle-race', 'U2', 'accept∥unlist não deixou accepted+unlisted', {
              'accept': raceBun[0].brief,
            });
          }
        }
      }
    }

    // Offer + bundle stacking
    await c.rest(
      'PATCH',
      'seller_bundle_discounts?seller_id=eq.${c.sellerId}',
      jwt: c.sellerJwt,
      body: {
        'enabled': true,
        'tier_2_pct': 50,
        'tier_3_pct': 50,
        'tier_5_pct': 50,
      },
    );
    final sA = await c.createProduct(title: '$prefix stack-A', qty: 2, price: 20);
    final sB = await c.createProduct(title: '$prefix stack-B', qty: 2, price: 20);
    if (sA != null && sB != null) {
      final chA = await c.ensureChat(sA);
      final chB = await c.ensureChat(sB);
      Future<String?> acceptOffer(String pid, String chat, num amt) async {
        final ins = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
          'product_id': pid,
          'chat_id': chat,
          'buyer_id': c.buyerId,
          'seller_id': c.sellerId,
          'amount': amt,
          'list_price': 20,
          'offered_by': 'buyer',
          'status': 'pending',
        });
        final id = ins.firstId;
        if (id == null) return null;
        c.createdOfferIds.add(id);
        await c.rest(
          'PATCH',
          'product_offers?id=eq.$id',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
        return id;
      }

      final ofA = await acceptOffer(sA, chA ?? '', 10);
      final ofB = await acceptOffer(sB, chB ?? '', 10);
      final o1 = await c.insertOrder(productId: sA, jwt: c.buyerJwt, offerId: ofA, price: 10);
      final o2 = await c.insertOrder(productId: sB, jwt: c.buyerJwt, offerId: ofB, price: 10);
      if (o1 != null && o2 != null) {
        final stack = await c.checkoutBag(
          lines: [
            {'order_id': o1, 'product_id': sA},
            {'order_id': o2, 'product_id': sB},
          ],
          amount: 50,
        );
        c.note('u2.stack', 'oferta 10+10 e desconto conjunto 50%', stack.brief, lens: 'U2');
        final amt = stack.serverAmount;
        // 10+10=20€ itens, 50% → 10€ + prot. Catálogo 40€ 50% → 20€ + prot.
        final itemsOfferDisc = euroToCents(10); // 10+10 then 50%
        final prot = protectionFeeCents(itemsOfferDisc, 0);
        final expectStack = itemsOfferDisc + prot;
        final itemsOfferOnly = euroToCents(20);
        final expectOfferOnly = itemsOfferOnly + protectionFeeCents(itemsOfferOnly, 0);
        if (stack.ok && amt != null && (amt - expectStack).abs() <= 2) {
          c.hold(
            id: 'RTU-U2-offer-bundle-stack',
            lens: 'U2',
            severity: 'P1',
            title: 'Desconto de conjunto aplica-se por cima do contrato da oferta',
            actor: 'buyer JWT bag',
            pre: '2 ofertas 10€ aceites + seller_bundle_discounts 50%',
            repro: 'bag_checkout das 2 orders seladas a 10€',
            expected: 'desconto de conjunto sobre catálogo OU ofertas sem segundo corte',
            obtained: {
              'server_amount_cents': amt,
              'expect_stack_10eur_plus_prot': expectStack,
              'expect_offer_only_20eur_plus_prot': expectOfferOnly,
            },
          );
        } else {
          c.block('RTU-U2-stack', 'U2', 'sem stack (ou quote falhou)', {
            'amt': amt,
            'stack': expectStack,
            'offerOnly': expectOfferOnly,
            'brief': stack.brief,
          });
        }
      }
    }
  }

  // =====================================================================
  // U3 — checkout Stripe quote
  // =====================================================================
  final skuCk = await c.createProduct(title: '$prefix ck-body', qty: 2, price: 12);
  if (skuCk != null) {
    final oid = await c.insertOrder(
      productId: skuCk,
      jwt: c.buyerJwt,
      price: 12,
      shipping: 'entrega em mão',
    );
    if (oid != null) {
      final cheap = await c.checkout(
        orderId: oid,
        amount: 50,
        productId: skuCk,
        shipping: 'mao',
      );
      c.note('u3.body.amount', 'body.amount=50 vs catálogo 12€', cheap.brief, lens: 'U3');
      final amt = cheap.serverAmount;
      final items = euroToCents(12);
      final prot = protectionFeeCents(items, 0);
      final expect = items + prot;
      if (cheap.ok && amt != null && (amt - expect).abs() <= 2) {
        c.block('RTU-U3-body-amount', 'U3', 'body.amount ignorado (quote servidor)', amt);
      } else if (cheap.ok && amt != null && amt <= 50) {
        c.hold(
          id: 'RTU-U3-body-amount-wins',
          lens: 'U3',
          severity: 'P0',
          title: 'Checkout cobra o amount do body',
          actor: 'buyer JWT',
          pre: 'catálogo 12€, body.amount=50 cêntimos',
          repro: 'POST create-payment-intent amount=50',
          expected: 'server_amount ≈ 12€ + protecção',
          obtained: amt,
        );
      }

      // contract injection
      final inj = await c.insertOrder(
        productId: skuCk,
        jwt: c.buyerJwt,
        price: 0.50,
        contractUnitCents: 1,
      );
      if (inj != null) {
        final ir = await c.orderRow(inj);
        c.note('u3.contract.inject', 'JWT contract_unit_cents=1', ir, lens: 'U3');
        final unit = numOf(ir?['contract_unit_cents']);
        if ((unit ?? 0) <= 1) {
          c.hold(
            id: 'RTU-U3-contract-inject',
            lens: 'U3',
            severity: 'P0',
            title: 'JWT sela contract_unit_cents=1',
            actor: 'buyer JWT',
            pre: 'catálogo 12€',
            repro: 'POST orders contract_unit_cents=1',
            expected: 'JWT limpa contract_* e sela catálogo',
            obtained: ir,
          );
        } else {
          c.block('RTU-U3-contract-inject', 'U3', 'JWT não manda contrato', unit);
        }
      }

      // shipping PATCH after seal
      final shipPatch = await c.rest(
        'PATCH',
        'orders?id=eq.$oid',
        jwt: c.buyerJwt,
        body: {'shipping_method': 'transportadora'},
      );
      c.note('u3.ship.patch', 'PATCH portes após hold', shipPatch.brief, lens: 'U3');
      final afterShip = await c.orderRow(oid);
      final ckShip = await c.checkout(orderId: oid, amount: 50, shipping: 'mao');
      c.note('u3.ship.checkout', 'checkout após PATCH carrier', {
        'patch': shipPatch.brief,
        'sealed': afterShip?['shipping_method'],
        'quote': ckShip.brief,
        'amt': ckShip.serverAmount,
      }, lens: 'U3');
      if (shipPatch.ok) {
        final shipAmt = ckShip.serverAmount;
        final withCarrier = items + 350 + protectionFeeCents(items, 350);
        final withHand = items + protectionFeeCents(items, 0);
        if (ckShip.ok && shipAmt != null && (shipAmt - withCarrier).abs() <= 2) {
          c.hold(
            id: 'RTU-U3-ship-patch-after-hold',
            lens: 'U3',
            severity: 'P1',
            title: 'JWT muda portes após hold e o quote segue o PATCH',
            actor: 'buyer JWT',
            pre: 'order selada entrega em mão',
            repro: 'PATCH shipping_method=transportadora; create-payment-intent',
            expected: 'shipping_method imutável no hold / selo original',
            obtained: {
              'sealed': afterShip?['shipping_method'],
              'server_amount_cents': shipAmt,
              'hand': withHand,
              'carrier': withCarrier,
            },
          );
        } else if (shipPatch.ok && ckShip.ok) {
          c.note('u3.ship.mutable', 'portes mutáveis mas quote não carrier', {
            'amt': shipAmt,
            'hand': withHand,
            'carrier': withCarrier,
          }, lens: 'U3');
          // still a mutability issue if patch stuck
          if ((afterShip?['shipping_method']?.toString() ?? '').contains('transportadora')) {
            c.hold(
              id: 'RTU-U3-ship-mutable',
              lens: 'U3',
              severity: 'P2',
              title: 'shipping_method mutável por JWT após hold',
              actor: 'buyer JWT',
              pre: 'reserva_pendente selada mão',
              repro: 'PATCH orders.shipping_method',
              expected: 'campo selado como payment_method/quantity',
              obtained: afterShip?['shipping_method'],
            );
          }
        }
      } else {
        c.block('RTU-U3-ship-patch', 'U3', 'portes imutáveis', shipPatch.brief);
      }

      // prize_shipping em marketplace
      final prize = await c.checkout(orderId: oid, amount: 50, prize: true);
      c.note('u3.prize', 'prize_shipping=true em order marketplace', prize.brief, lens: 'U3');
      if (prize.ok && (prize.checkoutSessionId ?? '').startsWith('cs_')) {
        final pAmt = prize.serverAmount ?? 0;
        if (pAmt < items) {
          c.hold(
            id: 'RTU-U3-prize-flag',
            lens: 'U3',
            severity: 'P0',
            title: 'prize_shipping reduz o total de um anúncio marketplace',
            actor: 'buyer JWT',
            pre: 'order sem rifa',
            repro: 'POST create-payment-intent prize_shipping=true',
            expected: 'Checkout blocked: order is not a raffle prize',
            obtained: prize.brief,
          );
        }
      } else {
        c.block('RTU-U3-prize', 'U3', 'prize_shipping marketplace bloqueado', prize.brief);
      }

      // off-platform Stripe
      final oidMb = await c.insertOrder(
        productId: skuCk,
        jwt: c.buyerJwt,
        payment: 'MB WAY',
        price: 12,
      );
      if (oidMb != null) {
        final mbCk = await c.checkout(orderId: oidMb, amount: 50);
        c.note('u3.mbway.stripe', 'Stripe em order MB WAY', mbCk.brief, lens: 'U3');
        if (mbCk.ok && (mbCk.checkoutSessionId ?? '').startsWith('cs_')) {
          c.hold(
            id: 'RTU-U3-mbway-stripe-session',
            lens: 'U3',
            severity: 'P1',
            title: 'Checkout Stripe abre em encomenda MB WAY',
            actor: 'buyer JWT',
            pre: 'payment_method=MB WAY',
            repro: 'POST create-payment-intent',
            expected: 'order is off-platform payment',
            obtained: mbCk.brief,
          );
        } else {
          c.block('RTU-U3-mbway-stripe', 'U3', 'MB WAY sem Session Stripe', mbCk.brief);
        }
      }

      // seller PATCH price after hold
      await c.rest(
        'PATCH',
        'products?id=eq.$skuCk',
        jwt: c.sellerJwt,
        body: {'price': 1.00},
      );
      final oidNew = await c.insertOrder(productId: skuCk, jwt: c.buyerJwt, price: 12);
      final ckOldHold = await c.checkout(orderId: oid!, amount: 50);
      c.note('u3.price.after.hold', 'catálogo 1€; hold antigo', {
        'old_session': ckOldHold.serverAmount,
        'old_order': oid,
        'new_order': oidNew,
      }, lens: 'U3');
    }
  }

  // checkout ∥ unlist
  final skuRace = await c.createProduct(title: '$prefix ck-unlist', qty: 2, price: 13);
  if (skuRace != null) {
    final oidR = await c.insertOrder(productId: skuRace, jwt: c.buyerJwt, price: 13);
    if (oidR != null) {
      final raced = await parallel([
        c.checkout(orderId: oidR, amount: 50, productId: skuRace),
        c.rest(
          'PATCH',
          'products?id=eq.$skuRace',
          jwt: c.sellerJwt,
          body: {'list_on_marketplace': false},
        ),
      ]);
      c.note('u3.ck.unlist', 'checkout ∥ unlist', {
        'ck': raced[0].brief,
        'un': raced[1].brief,
        'cs': raced[0].checkoutSessionId,
      }, lens: 'U3');
      final listed = (await c.productRow(skuRace))?['list_on_marketplace'];
      if (raced[0].ok &&
          (raced[0].checkoutSessionId ?? '').startsWith('cs_') &&
          listed == false) {
        c.hold(
          id: 'RTU-U3-checkout-unlist-race',
          lens: 'U3',
          severity: 'P1',
          title: 'Session Stripe criada em corrida com unlist',
          actor: 'buyer checkout ∥ seller unlist',
          pre: 'hold + list=true',
          repro: 'Future.wait create-payment-intent ∥ PATCH unlist',
          expected: 'um dos dois falha; sem Session se já unlistado',
          obtained: {
            'session': raced[0].checkoutSessionId,
            'listed': listed,
          },
        );
      } else {
        c.block('RTU-U3-ck-unlist', 'U3', 'race checkout∥unlist sem Session+unlist', {
          'ck': raced[0].brief,
          'listed': listed,
        });
      }
    }
  }

  // =====================================================================
  // U4 — oversell v2 (variante qty, não last-unit exact)
  // =====================================================================
  final skuOv = await c.createProduct(title: '$prefix oversell-3', qty: 3, price: 7);
  if (skuOv != null) {
    final oa = await c.insertOrder(
      productId: skuOv,
      jwt: c.buyerJwt,
      qty: 2,
      price: 7,
    );
    final ob = await c.insertOrder(
      productId: skuOv,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
      qty: 2,
      price: 7,
    );
    // If sequential, second should fail. Parallel already done. Try checkout on whatever exists.
    final ids = [oa, ob].whereType<String>().toList();
    c.note('u4.holds', 'holds qty=2 stock=3', ids, lens: 'U4');
    if (ids.length == 2) {
      final cks = await parallel([
        c.checkout(orderId: ids[0], jwt: c.buyerJwt, buyer: c.buyerId, amount: 50),
        c.checkout(orderId: ids[1], jwt: c.buyer2Jwt, buyer: c.buyer2Id, amount: 50),
      ]);
      c.note('u4.ck.race', '2 checkouts qty=2 stock=3', {
        'a': cks[0].brief,
        'b': cks[1].brief,
      }, lens: 'U4');
      final sessions = cks
          .where((h) => (h.checkoutSessionId ?? '').startsWith('cs_'))
          .length;
      if (sessions >= 2) {
        c.hold(
          id: 'RTU-U4-two-sessions-over-stock',
          lens: 'U4',
          severity: 'P0',
          title: 'Duas Sessions Stripe para 4 unidades em stock=3',
          actor: 'B1 ∥ B2',
          pre: '2 holds qty=2',
          repro: 'Future.wait create-payment-intent',
          expected: 'uma Session no máximo',
          obtained: {
            'a': cks[0].checkoutSessionId,
            'b': cks[1].checkoutSessionId,
          },
        );
      } else {
        c.block('RTU-U4-ck-over', 'U4', '2.º checkout recusado', sessions);
      }
    }
  }

  // live + marketplace mesmo SKU (leve): available_for_live + hold marketplace
  final skuCross = await c.createProduct(
    title: '$prefix live-mkt',
    qty: 1,
    price: 9,
    live: true,
  );
  if (skuCross != null) {
    final holdM = await c.insertOrder(productId: skuCross, jwt: c.buyerJwt, price: 9);
    c.note('u4.cross.hold', 'hold marketplace SKU also live', holdM, lens: 'U4');
    final lives = await c.rest(
      'GET',
      'lives?seller_id=eq.${c.sellerId}&select=id,status,is_active&order=created_at.desc&limit=3',
      service: true,
    );
    c.note('u4.cross.lives', 'lives do seller (observação)', lives.brief, lens: 'U4');
    if (holdM != null && lives.list.isNotEmpty) {
      final liveId = (lives.list.first as Map)['id']?.toString();
      if (liveId != null) {
        final li = await c.rest('POST', 'live_items', service: true, body: {
          'live_id': liveId,
          'product_id': skuCross,
          'title': '$prefix cross',
          'price': 9,
          'quantity': 1,
        });
        c.note('u4.cross.liveitem', 'live_item no SKU já em hold mkt', li.brief, lens: 'U4');
        if (li.ok && li.firstId != null) {
          final avail = await c.rpc('batata_product_checkout_available', {
            'p_product_id': skuCross,
            'p_exclude_order_id': holdM,
            'p_need_qty': 1,
          }, service: true);
          c.note('u4.cross.avail', 'stock check após hold+live_item', avail.brief, lens: 'U4');
        }
      }
    }
  }

  // =====================================================================
  // U5 — MB WAY / mão
  // =====================================================================
  final skuMb = await c.createProduct(title: '$prefix mbway', qty: 2, price: 8);
  if (skuMb != null) {
    final oidMb = await c.insertOrder(
      productId: skuMb,
      jwt: c.buyerJwt,
      payment: 'MB WAY',
      price: 8,
    );
    if (oidMb != null) {
      final before = await c.productRow(skuMb);
      final wBefore = await c.walletBal(c.sellerId);
      final buyerPago = await c.markPago(oidMb, jwt: c.buyerJwt);
      c.note('u5.buyer.pago', 'B marca pago MB WAY', buyerPago.brief, lens: 'U5');
      if (buyerPago.ok &&
          (await c.orderRow(oidMb))?['status']?.toString() == 'pago') {
        c.hold(
          id: 'RTU-U5-buyer-mark-pago',
          lens: 'U5',
          severity: 'P0',
          title: 'Comprador marca MB WAY como pago',
          actor: 'buyer JWT',
          pre: 'reserva_pendente MB WAY',
          repro: 'PATCH status=pago',
          expected: 'status permanece hold',
          obtained: (await c.orderRow(oidMb))?['status'],
        );
      } else {
        c.block('RTU-U5-buyer-pago', 'U5', 'B não marca pago', buyerPago.brief);
      }

      final earlyConc = await c.markConcluido(oidMb, jwt: c.buyerJwt);
      c.note('u5.buyer.concluido.early', 'B concluido sem pago', earlyConc.brief, lens: 'U5');
      if (earlyConc.ok &&
          (await c.orderRow(oidMb))?['status']?.toString() == 'concluido') {
        c.hold(
          id: 'RTU-U5-buyer-concluido-early',
          lens: 'U5',
          severity: 'P0',
          title: 'Comprador conclui MB WAY ainda em reserva',
          actor: 'buyer JWT',
          pre: 'reserva_pendente',
          repro: 'PATCH status=concluido',
          expected: 'bloqueado',
          obtained: (await c.orderRow(oidMb))?['status'],
        );
      } else {
        c.block('RTU-U5-early-concluido', 'U5', 'concluido cedo bloqueado', earlyConc.brief);
      }

      final sPago = await c.markPago(oidMb, jwt: c.sellerJwt);
      c.note('u5.seller.pago', 'S marca pago MB WAY (sem prova)', sPago.brief, lens: 'U5');
      final afterPago = await c.orderRow(oidMb);
      final afterProd = await c.productRow(skuMb);
      final wAfter = await c.walletBal(c.sellerId);
      final tx = await c.walletTxns(orderId: oidMb);
      c.note('u5.seller.pago.books', 'stock/wallet após S pago', {
        'order': afterPago?['status'],
        'qty_before': before?['quantity'],
        'qty_after': afterProd?['quantity'],
        'is_sold': afterProd?['is_sold'],
        'wallet_delta': (wAfter - wBefore),
        'tx': tx.length,
        'amount_paid_cents': afterPago?['amount_paid_cents'],
      }, lens: 'U5');

      if (afterPago?['status']?.toString() == 'pago') {
        if ((numOf(afterPago?['amount_paid_cents']) ?? 0) > 0) {
          c.hold(
            id: 'RTU-U5-mbway-amount-paid',
            lens: 'U5',
            severity: 'P0',
            title: 'MB WAY pago pelo vendedor escreve amount_paid_cents',
            actor: 'seller JWT',
            pre: 'sem captura Stripe',
            repro: 'PATCH status=pago',
            expected: 'amount_paid_cents nulo/0',
            obtained: afterPago?['amount_paid_cents'],
          );
        }
        if ((wAfter - wBefore) > 0.009) {
          c.hold(
            id: 'RTU-U5-mbway-wallet-mint',
            lens: 'U5',
            severity: 'P0',
            title: 'Marcar MB WAY pago credita a carteira',
            actor: 'seller JWT + collusion',
            pre: 'sem captura plataforma',
            repro: 'PATCH pago; ler wallets.balance',
            expected: 'Δwallet=0',
            obtained: {'delta': wAfter - wBefore, 'tx': tx},
          );
        } else {
          c.block('RTU-U5-mbway-wallet', 'U5', 'MB WAY pago sem mint wallet', wAfter - wBefore);
        }

        // buyer concluido after seller pago (mão)
        await c.markMao(oidMb, jwt: c.sellerJwt);
        final conc = await c.markConcluido(oidMb, jwt: c.buyerJwt);
        c.note('u5.concluido.after.pago', 'B concluido após S pago mão', conc.brief, lens: 'U5');
        final wRel = await c.walletBal(c.sellerId);
        if ((wRel - wAfter) > 0.009) {
          c.hold(
            id: 'RTU-U5-mbway-release-on-concluido',
            lens: 'U5',
            severity: 'P0',
            title: 'Concluir MB WAY liberta saldo de plataforma',
            actor: 'buyer JWT concluido',
            pre: 'pago off-platform amount_paid=0',
            repro: 'PATCH concluido',
            expected: 'sem crédito wallet',
            obtained: wRel - wAfter,
          );
        }

        final refMb = await c.edge('refund-order', {'order_id': oidMb}, jwt: c.sellerJwt);
        c.note('u5.refund.mbway', 'refund-order em MB WAY', refMb.brief, lens: 'U5');
      } else {
        c.block('RTU-U5-seller-pago', 'U5', 'S não conseguiu marcar pago MB WAY', sPago.brief);
      }

      // collusion 2 buyers last unit MB WAY
      final skuMb1 = await c.createProduct(title: '$prefix mb-last', qty: 1, price: 6);
      if (skuMb1 != null) {
        final h1 = c.insertOrder(
          productId: skuMb1,
          jwt: c.buyerJwt,
          payment: 'MB WAY',
          price: 6,
        );
        final h2 = c.insertOrder(
          productId: skuMb1,
          jwt: c.buyer2Jwt,
          buyer: c.buyer2Id,
          payment: 'MB WAY',
          price: 6,
        );
        final two = await Future.wait([h1, h2]);
        c.note('u5.mb.twoholds', '2 MB WAY holds stock=1', two, lens: 'U5');
        final okIds = two.whereType<String>().toList();
        if (okIds.length >= 2) {
          final p1 = await c.markPago(okIds[0], jwt: c.sellerJwt);
          final p2 = await c.markPago(okIds[1], jwt: c.sellerJwt);
          c.note('u5.mb.two.pago', 'S marca pago nas duas', {
            'p1': p1.brief,
            'p2': p2.brief,
          }, lens: 'U5');
          final st1 = (await c.orderRow(okIds[0]))?['status'];
          final st2 = (await c.orderRow(okIds[1]))?['status'];
          if (st1 == 'pago' && st2 == 'pago') {
            c.hold(
              id: 'RTU-U5-mbway-double-pago',
              lens: 'U5',
              severity: 'P0',
              title: 'Duas encomendas MB WAY pagas no último stock',
              actor: 'seller JWT collusion',
              pre: '2 holds qty=1 stock=1',
              repro: '2× PATCH pago',
              expected: '2.º pago recusado / 2.º hold inexistente',
              obtained: {'st1': st1, 'st2': st2},
            );
          }
        } else {
          c.block('RTU-U5-mb-twoholds', 'U5', '2.º hold MB WAY recusado', two);
        }
      }
    }
  }

  // =====================================================================
  // U6 — cancel / refund
  // =====================================================================
  final legit = await c.payToPago(lens: 'U3', initialQty: 3);
  Map<String, dynamic>? legitBooks;
  if (legit != null) {
    legitBooks = await c.books(legit.oid);
    c.note('u6.legit.paid', 'compra Stripe TEST marketplace', {
      'oid': legit.oid,
      'status': legitBooks['order']?['status'],
      'qty': legitBooks['product']?['quantity'],
      'amount_paid': legitBooks['order']?['amount_paid_cents'],
      'pi': legit.pi,
    }, lens: 'U8');

    final cancelPaid = await c.markCancel(legit.oid, jwt: c.buyerJwt);
    c.note('u6.cancel.paid', 'B anula pós-pago', cancelPaid.brief, lens: 'U6');
    final afterCancel = await c.orderRow(legit.oid);
    if (afterCancel?['status']?.toString() == 'cancelado') {
      c.hold(
        id: 'RTU-U6-cancel-after-paid',
        lens: 'U6',
        severity: 'P0',
        title: 'Comprador anula encomenda já paga',
        actor: 'buyer JWT',
        pre: 'status=pago Stripe TEST',
        repro: 'PATCH status=cancelado',
        expected: 'status permanece pago',
        obtained: afterCancel?['status'],
      );
    } else {
      c.block('RTU-U6-cancel-paid', 'U6', 'anular pós-pago bloqueado', afterCancel?['status']);
    }

    // buyer refund-order
    final br = await c.edge('refund-order', {'order_id': legit.oid}, jwt: c.buyerJwt);
    c.note('u6.refund.buyer', 'B chama refund-order', br.brief, lens: 'U6');
    if (br.ok && br.map?['ok'] == true && br.map?['skipped'] != true) {
      c.hold(
        id: 'RTU-U6-buyer-refund',
        lens: 'U6',
        severity: 'P0',
        title: 'Comprador JWT executa refund Stripe',
        actor: 'buyer JWT',
        pre: 'order pago marketplace',
        repro: 'POST refund-order',
        expected: '403 Sem permissão',
        obtained: br.brief,
      );
    } else {
      c.block('RTU-U6-buyer-refund', 'U6', 'refund buyer bloqueado', br.brief);
    }

    final s2ref = await c.edge('refund-order', {'order_id': legit.oid}, jwt: c.seller2Jwt);
    c.note('u6.refund.s2', 'S2 refund order de S1', s2ref.brief, lens: 'U6');
    if (s2ref.ok && s2ref.map?['ok'] == true && s2ref.map?['skipped'] != true) {
      c.hold(
        id: 'RTU-U6-seller2-refund',
        lens: 'U6',
        severity: 'P0',
        title: '2.º vendedor reembolsa venda alheia',
        actor: 'seller2 JWT',
        pre: 'order seller=S1',
        repro: 'POST refund-order',
        expected: '403',
        obtained: s2ref.brief,
      );
    } else {
      c.block('RTU-U6-s2-refund', 'U6', 'refund alheio bloqueado', s2ref.brief);
    }

    // legitimate ship path — não partir
    await c.markMao(legit.oid);
    final envio = await c.markEnviado(legit.oid);
    c.note('u6.legit.envio', 'S envio correcto pós-pago', envio.brief, lens: 'U8');
  }

  // Bag pago + refund 1 linha
  final bagPaid = await c.e2e('setup_paid_bag', {});
  c.note('u6.bag.paid', 'setup_paid_bag Stripe TEST', bagPaid.brief, lens: 'U6');
  final bagMap = bagPaid.map ?? {};
  final bagA = bagMap['order_a_id']?.toString();
  final bagB = bagMap['order_b_id']?.toString();
  final bagPA = bagMap['product_a_id']?.toString();
  final bagPB = bagMap['product_b_id']?.toString();
  if (bagPA != null) c.createdProductIds.add(bagPA);
  if (bagPB != null) c.createdProductIds.add(bagPB);
  if (bagA != null) c.createdOrderIds.add(bagA);
  if (bagB != null) c.createdOrderIds.add(bagB);

  if (bagA != null && bagB != null) {
    final prodA0 = await c.productRow(bagPA ?? '');
    final prodB0 = await c.productRow(bagPB ?? '');
    final refA = await c.edge('refund-order', {'order_id': bagA}, jwt: c.sellerJwt);
    c.note('u6.bag.refund.A', 'refund linha A do saco', refA.brief, lens: 'U6');
    final oa = await c.orderRow(bagA);
    final ob = await c.orderRow(bagB);
    final prodA1 = await c.productRow(bagPA ?? '');
    final prodB1 = await c.productRow(bagPB ?? '');
    c.note('u6.bag.refund.books', 'após refund A', {
      'a_status': oa?['status'],
      'b_status': ob?['status'],
      'a_refund': oa?['stripe_refund_id'],
      'b_refund': ob?['stripe_refund_id'],
      'qty_a_0': prodA0?['quantity'],
      'qty_a_1': prodA1?['quantity'],
      'qty_b_0': prodB0?['quantity'],
      'qty_b_1': prodB1?['quantity'],
      'ref': refA.map,
    }, lens: 'U6');

    final bKilled = ob?['status']?.toString() == 'cancelado' ||
        (ob?['stripe_refund_id']?.toString().trim().isNotEmpty ?? false);
    if (bKilled && oa?['stripe_refund_id'] != null) {
      c.hold(
        id: 'RTU-U6-bag-refund-collateral',
        lens: 'U6',
        severity: 'P0',
        title: 'Refund da linha A do saco afecta a linha B',
        actor: 'seller JWT refund-order',
        pre: 'saco 2 linhas mesmo PI TEST',
        repro: 'POST refund-order order_id=A',
        expected: 'B permanece pago; stock B intacto',
        obtained: {
          'b_status': ob?['status'],
          'b_refund': ob?['stripe_refund_id'],
          'qty_b_0': prodB0?['quantity'],
          'qty_b_1': prodB1?['quantity'],
        },
      );
    } else {
      c.block('RTU-U6-bag-line', 'U6', 'refund A não derruba B', {
        'b': ob?['status'],
        'qty_b': [prodB0?['quantity'], prodB1?['quantity']],
      });
    }

    // restock duplo: 2.º refund A
    final refA2 = await c.edge('refund-order', {'order_id': bagA}, jwt: c.sellerJwt);
    final prodA2 = await c.productRow(bagPA ?? '');
    c.note('u6.bag.refund.A2', '2.º refund A (idempotência / restock)', {
      'ref': refA2.brief,
      'qty1': prodA1?['quantity'],
      'qty2': prodA2?['quantity'],
    }, lens: 'U6');
    final q1 = numOf(prodA1?['quantity']) ?? 0;
    final q2 = numOf(prodA2?['quantity']) ?? 0;
    if (q2 > q1) {
      c.hold(
        id: 'RTU-U6-double-restock',
        lens: 'U6',
        severity: 'P1',
        title: 'Segundo refund da mesma linha volta a subir stock',
        actor: 'seller JWT',
        pre: 'já refundido',
        repro: '2× POST refund-order',
        expected: 'idempotente; quantity estável',
        obtained: {'qty1': q1, 'qty2': q2},
      );
    } else {
      c.block('RTU-U6-double-restock', 'U6', '2.º refund sem restock extra', {'q1': q1, 'q2': q2});
    }
  }

  // Cancel hold then restock (unpaid)
  final skuHold = await c.createProduct(title: '$prefix cancel-hold', qty: 2, price: 5);
  if (skuHold != null) {
    final oidH = await c.insertOrder(productId: skuHold, jwt: c.buyerJwt, price: 5);
    final qHold = (await c.productRow(skuHold))?['quantity'];
    if (oidH != null) {
      final can = await c.markCancel(oidH, jwt: c.buyerJwt);
      final qAfter = (await c.productRow(skuHold))?['quantity'];
      c.note('u6.cancel.hold', 'cancel reserva', {
        'can': can.brief,
        'qty_hold_row': qHold,
        'qty_after': qAfter,
      }, lens: 'U6');
      // quantity typically unchanged on hold (decrement only on pago). If it jumped up, double restock.
      if ((numOf(qAfter) ?? 0) > (numOf(qHold) ?? 0)) {
        c.hold(
          id: 'RTU-U6-cancel-hold-restock',
          lens: 'U6',
          severity: 'P1',
          title: 'Cancelar hold sobe stock (hold não tinha decrementado)',
          actor: 'buyer JWT',
          pre: 'reserva_pendente',
          repro: 'PATCH cancelado',
          expected: 'quantity inalterada se hold não consome stock',
          obtained: {'before': qHold, 'after': qAfter},
        );
      }
    }
  }

  // =====================================================================
  // U7 — cross-superfície
  // =====================================================================
  final skuHub = await c.createProduct(title: '$prefix hub-ghost', qty: 0, price: 11, sold: false);
  if (skuHub != null) {
    final feed = await c.rest(
      'GET',
      'products?id=eq.$skuHub&select=id,price,quantity,is_sold,list_on_marketplace',
      jwt: c.buyerJwt,
    );
    final hub = await c.rest(
      'GET',
      'hub_products_public?id=eq.$skuHub&select=id,price,is_sold,title',
      jwt: c.buyerJwt,
    );
    final hubAnon = await c.rest(
      'GET',
      'hub_products_public?id=eq.$skuHub&select=id,price,is_sold,title',
    );
    c.note('u7.ghost', 'qty=0 is_sold=false Início vs Hub', {
      'feed': feed.map,
      'hub_jwt': hub.list.length,
      'hub_anon': hubAnon.list.length,
      'hub_row': hub.map ?? hub.list,
    }, lens: 'U7');
    final visibleHub = hub.list.isNotEmpty || hub.map != null;
    final visibleFeed = feed.ok && (feed.map?['quantity'] == 0);
    if (visibleHub && visibleFeed) {
      c.hold(
        id: 'RTU-U7-hub-qty0-ghost',
        lens: 'U7',
        severity: 'P2',
        title: 'Hub lista anúncio com quantity=0 e is_sold=false',
        actor: 'buyer JWT / anon view',
        pre: 'SKU qty=0 listed',
        repro: 'GET hub_products_public?id=eq.<sku>',
        expected: 'oculto (sem stock efectivo)',
        obtained: {
          'hub': hub.map ?? hub.list,
          'feed_qty': feed.map?['quantity'],
        },
      );
    } else {
      c.block('RTU-U7-ghost', 'U7', 'qty=0 não aparece no Hub (ou feed)', {
        'hub': hub.list.length,
        'feed': feed.map,
      });
    }

    final holdGhost = await c.insertOrder(productId: skuHub, jwt: c.buyerJwt, price: 11);
    c.note('u7.ghost.hold', 'hold qty=0', holdGhost, lens: 'U7');
    if (holdGhost != null) {
      c.hold(
        id: 'RTU-U7-hold-qty0',
        lens: 'U7',
        severity: 'P1',
        title: 'Hold JWT em artigo com quantity=0',
        actor: 'buyer JWT',
        pre: 'qty=0 is_sold=false',
        repro: 'POST orders',
        expected: 'order_hold_exceeds_stock',
        obtained: holdGhost,
      );
    }
  }

  // preço Hub vs catálogo após hold (Hub não tem quantity)
  if (skuCk != null) {
    final p = await c.productRow(skuCk);
    final hubP = await c.rest(
      'GET',
      'hub_products_public?id=eq.$skuCk&select=id,price,is_sold',
      jwt: c.buyerJwt,
    );
    c.note('u7.price', 'preço products vs Hub', {
      'products': p?['price'],
      'hub': hubP.map ?? hubP.list,
      'qty': p?['quantity'],
    }, lens: 'U7');
  }

  // =====================================================================
  // U8 — composição: oferta barata + desconto + pago + wallet
  // =====================================================================
  // Restore discounts 50% and pay a bag via e2e isn't offer-aware.
  // Chain: JWT offer-sealed bag quote already recorded. Paid path = legit + bag.
  if (legit != null) {
    final books2 = await c.books(legit.oid);
    final st = books2['order']?['status']?.toString();
    final paid = numOf(books2['order']?['amount_paid_cents']) ?? 0;
    final stockApplied = books2['order']?['stock_units_applied'];
    c.note('u8.legit.books', 'contabilidade compra marketplace', {
      'status': st,
      'amount_paid_cents': paid,
      'stock_units': stockApplied,
      'product_qty': books2['product']?['quantity'],
      'seller_venda': books2['seller_venda'],
      'pi': books2['order']?['stripe_payment_intent_id'],
    }, lens: 'U8');
    if (st != 'pago' && st != 'enviado' && st != 'concluido') {
      c.hold(
        id: 'RTU-U8-legit-not-paid',
        lens: 'U8',
        severity: 'P1',
        title: 'Fixture Stripe TEST marketplace não ficou paga',
        actor: 'e2e setup_paid_order',
        pre: 'pm_card_visa',
        repro: 'setup_paid_order',
        expected: 'status pago/enviado',
        obtained: st,
      );
    }
  }

  // custom_tiers 99% (CHECK nas colunas nomeadas; jsonb sem CHECK)
  final custom99 = await c.rest(
    'PATCH',
    'seller_bundle_discounts?seller_id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {
      'enabled': true,
      'tier_2_pct': 50,
      'custom_tiers': [
        {'min_items': 2, 'pct': 99},
      ],
    },
  );
  c.note('u8.custom99.write', 'custom_tiers pct=99', custom99.brief, lens: 'U8');
  if (bA != null && bB != null) {
    // new pair
    final xA = await c.createProduct(title: '$prefix custom99-A', qty: 2, price: 20);
    final xB = await c.createProduct(title: '$prefix custom99-B', qty: 2, price: 20);
    if (xA != null && xB != null) {
      final ox = await c.insertOrder(productId: xA, jwt: c.buyerJwt, price: 20);
      final oy = await c.insertOrder(productId: xB, jwt: c.buyerJwt, price: 20);
      if (ox != null && oy != null) {
        final q = await c.checkoutBag(
          lines: [
            {'order_id': ox, 'product_id': xA},
            {'order_id': oy, 'product_id': xB},
          ],
          amount: 50,
        );
        c.note('u8.custom99.quote', 'bag com custom 99% (Edge cap 50?)', q.brief, lens: 'U8');
        final amt = q.serverAmount;
        final items99 = (euroToCents(40) * 0.01).round();
        final items50 = (euroToCents(40) * 0.5).round();
        if (q.ok && amt != null) {
          final got99 = (amt - (items99 + protectionFeeCents(items99, 0))).abs() <= 3;
          if (got99) {
            c.hold(
              id: 'RTU-U8-custom-tiers-99',
              lens: 'U8',
              severity: 'P0',
              title: 'custom_tiers 99% fura o tecto de 50% no checkout',
              actor: 'seller JWT write + buyer checkout',
              pre: 'seller_bundle_discounts.custom_tiers pct=99',
              repro: 'PATCH custom_tiers; bag_checkout 2 SKUs',
              expected: 'Math.min(50, pct) → 50%',
              obtained: amt,
            );
          } else {
            c.block('RTU-U8-custom99', 'U8', 'Edge capou custom_tiers a 50%', {
              'amt': amt,
              'expect50': items50 + protectionFeeCents(items50, 0),
            });
          }
        }
      }
    }
  }

  // reset discounts so we don't leave seller at 99
  await c.rest(
    'PATCH',
    'seller_bundle_discounts?seller_id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {
      'enabled': false,
      'tier_2_pct': 0,
      'custom_tiers': <Map<String, Object>>[],
    },
  );

  final wEnd = await c.wallets();
  final out = {
    'auditor': 'REDTEAM_BLIND_U_MARKETPLACE_CHECKOUT_v1',
    'prefix': prefix,
    'frozen_at': DateTime.now().toUtc().toIso8601String(),
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
    'actors': {
      'buyer': c.buyerId,
      'seller': c.sellerId,
      'buyer2': c.buyer2Id,
      'seller2': c.seller2Id,
    },
    'w0': w0,
    'wEnd': wEnd,
    'orders': c.createdOrderIds,
    'products': c.createdProductIds,
    'offers': c.createdOfferIds,
    'bundles': c.createdBundleIds,
    'lenses_hit': c.lensesHit.toList()..sort(),
    'notes': c.notes,
    'blocked': c.blocked,
    'findings': c.findings,
  };
  await dumpJson('${outDir()}/probe.json', out);
  stdout.writeln('WROTE ${outDir()}/probe.json findings=${c.findings.length} blocked=${c.blocked.length}');
}
