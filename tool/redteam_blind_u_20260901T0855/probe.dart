/// RED TEAM CEGO U — marketplace / checkout / saco. Staging only. Não corrige.
library;

import 'dart:io';

import '_rtu.dart';

Future<void> main() async {
  final c = Rtu.fromEnv(loadEnv());
  stdout.writeln('RTU $stamp ${c.url}');
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('actors', 'login', {
    'buyer': c.buyerId,
    'seller': c.sellerId,
    'buyer2': c.buyer2Id,
    'seller2': c.seller2Id,
  });

  await lensU1(c);
  await lensU2(c);
  await lensU3(c);
  await lensU4(c);
  await lensU5(c);
  await lensU6(c);
  await lensU7(c);
  await lensU8(c);

  final legit = await c.payToPago(lens: 'U3', initialQty: 2);
  if (legit != null) {
    final books = await c.books(legit.oid);
    c.note('legit.paid', 'compra Stripe TEST marketplace', {
      'oid': legit.oid,
      'pid': legit.pid,
      'pi': legit.pi,
      'status': books['order']?['status'],
      'amount_paid_cents': books['order']?['amount_paid_cents'],
      'stock_units_applied': books['order']?['stock_units_applied'],
      'product_qty': books['product']?['quantity'],
    }, lens: 'U3');
  }

  final bagPaid = await c.e2e('setup_paid_bag', {});
  c.note('legit.bag', 'setup_paid_bag Stripe TEST', bagPaid.brief, lens: 'U3');
  if (bagPaid.ok) {
    c.lensesHit.add('U8');
  }

  await dumpJson('${outDir()}/probe.json', {
    'stamp': stamp,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
    'DONE findings=${c.findings.length} blocked=${c.blocked.length} lenses=${c.lensesHit}',
  );
}

Future<void> lensU1(Rtu c) async {
  final sku = await c.createProduct(title: '$prefix u1', qty: 2, price: 12);
  if (sku == null) return;

  final q9999 = await c.insertOrder(
    productId: sku,
    jwt: c.buyerJwt,
    qty: 9999,
    price: 12,
  );
  if (q9999 != null) {
    final row = await c.orderRow(q9999);
    c.hold(
      id: 'RTU-U1-qty-9999',
      lens: 'U1',
      severity: 'P0',
      title: 'Hold marketplace aceita quantity=9999',
      actor: 'buyer JWT',
      pre: 'SKU qty=2',
      repro: 'POST orders quantity=9999',
      expected: 'recusar',
      obtained: row,
    );
  } else {
    c.block('RTU-U1-qty-9999', 'U1', 'quantity=9999 recusado', 'no row');
  }

  final q99 = await c.insertOrder(
    productId: sku,
    jwt: c.buyerJwt,
    qty: 99,
    price: 12,
  );
  if (q99 != null) {
    final row = await c.orderRow(q99);
    c.hold(
      id: 'RTU-U1-qty-99-vs-stock-2',
      lens: 'U1',
      severity: 'P0',
      title: 'Hold qty=99 com stock=2',
      actor: 'buyer JWT',
      pre: 'SKU qty=2',
      repro: 'POST orders quantity=99',
      expected: 'order_hold_exceeds_stock',
      obtained: row,
    );
  } else {
    c.block('RTU-U1-qty-99', 'U1', 'qty=99 vs stock=2 recusado', 'no row');
  }

  final hold = await c.insertOrder(
    productId: sku,
    jwt: c.buyerJwt,
    qty: 1,
    price: 12,
  );
  if (hold != null) {
    final patchQty = await c.rest(
      'PATCH',
      'orders?id=eq.$hold',
      jwt: c.buyerJwt,
      body: {'quantity': 2},
    );
    if (patchQty.ok) {
      c.hold(
        id: 'RTU-U1-patch-qty',
        lens: 'U1',
        severity: 'P1',
        title: 'Buyer PATCH quantity após hold',
        actor: 'buyer JWT',
        pre: 'order qty=1',
        repro: 'PATCH orders.quantity=2',
        expected: 'order_money_fields_immutable',
        obtained: patchQty.brief,
      );
    } else {
      c.block('RTU-U1-patch-qty', 'U1', 'PATCH quantity bloqueado', patchQty.brief);
    }

    final alien = await c.createProduct(
      seller: c.seller2Id,
      title: '$prefix u1-alien',
      qty: 1,
      price: 9,
    );
    if (alien != null) {
      final unlistAlien = await c.rest(
        'PATCH',
        'products?id=eq.$alien',
        jwt: c.buyerJwt,
        body: {'list_on_marketplace': false},
      );
      if (unlistAlien.ok) {
        c.hold(
          id: 'RTU-U1-unlist-alheio',
          lens: 'U1',
          severity: 'P0',
          title: 'Buyer unlista SKU de outro vendedor',
          actor: 'buyer JWT',
          pre: 'produto S2',
          repro: 'PATCH products.list_on_marketplace=false',
          expected: 'RLS deny',
          obtained: unlistAlien.brief,
        );
      } else {
        c.block('RTU-U1-unlist-alheio', 'U1', 'unlist alheio bloqueado', unlistAlien.brief);
      }
    }

    final skuS2 = await c.createProduct(
      seller: c.seller2Id,
      title: '$prefix u1-s2',
      qty: 2,
      price: 8,
    );
    if (skuS2 != null) {
      final o2 = await c.insertOrder(
        productId: skuS2,
        jwt: c.buyerJwt,
        seller: c.seller2Id,
        qty: 1,
        price: 8,
      );
      if (o2 != null) {
        final bag = await c.checkoutBag(
          lines: [
            {'order_id': hold, 'product_id': sku, 'seller_id': c.sellerId},
            {'order_id': o2, 'product_id': skuS2, 'seller_id': c.seller2Id},
          ],
        );
        if (bag.ok && bag.checkoutSessionId != null) {
          c.hold(
            id: 'RTU-U1-cross-seller-bag',
            lens: 'U1',
            severity: 'P1',
            title: 'Bag checkout mistura dois vendedores',
            actor: 'buyer JWT',
            pre: '2 holds S1+S2',
            repro: 'POST create-payment-intent bag_checkout 2 sellers',
            expected: 'bag lines must share one seller',
            obtained: bag.brief,
            evidence: {'session': bag.checkoutSessionId, 'amount': bag.serverAmount},
          );
        } else {
          c.block('RTU-U1-cross-seller', 'U1', 'cross-seller bag recusado', bag.brief);
        }
      }
    }
  }
}

Future<void> lensU2(Rtu c) async {
  final sku = await c.createProduct(title: '$prefix u2-offer', qty: 5, price: 20);
  if (sku == null) return;
  final chat = await c.ensureChat(sku);

  final insAccepted = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': sku,
    'chat_id': chat,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': 0.50,
    'list_price': 20,
    'offered_by': 'buyer',
    'status': 'accepted',
  });
  if (insAccepted.ok && (insAccepted.map?['status'] == 'accepted')) {
    c.hold(
      id: 'RTU-U2-insert-accepted',
      lens: 'U2',
      severity: 'P0',
      title: 'Buyer INSERT oferta já accepted a 0,50 €',
      actor: 'buyer JWT',
      pre: 'SKU 20 €',
      repro: 'POST product_offers status=accepted amount=0.50',
      expected: 'forçar pending',
      obtained: insAccepted.map,
    );
  } else {
    c.block('RTU-U2-insert-accepted', 'U2', 'INSERT accepted recusado/forçado pending', insAccepted.brief);
  }

  final pending = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': sku,
    'chat_id': chat,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': 5,
    'list_price': 20,
    'offered_by': 'buyer',
    'status': 'pending',
  });
  final offerId = pending.firstId;
  if (offerId != null) c.createdOfferIds.add(offerId);

  if (offerId != null) {
    final selfAcc = await c.rest(
      'PATCH',
      'product_offers?id=eq.$offerId',
      jwt: c.buyerJwt,
      body: {'status': 'accepted'},
    );
    if (selfAcc.ok && selfAcc.map?['status'] == 'accepted') {
      c.hold(
        id: 'RTU-U2-self-accept',
        lens: 'U2',
        severity: 'P0',
        title: 'Buyer aceita a própria oferta',
        actor: 'buyer JWT',
        pre: 'pending offered_by=buyer',
        repro: 'PATCH product_offers.status=accepted',
        expected: 'offer_accept_not_authorized',
        obtained: selfAcc.map,
      );
    } else {
      c.block('RTU-U2-self-accept', 'U2', 'self-accept bloqueado', selfAcc.brief);
    }

    final acc = await c.rest(
      'PATCH',
      'product_offers?id=eq.$offerId',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    c.note('u2.offer.acc', 'seller accept 5€', acc.brief, lens: 'U2');

    if (acc.ok || acc.map?['status'] == 'accepted') {
      final amtPatch = await c.rest(
        'PATCH',
        'product_offers?id=eq.$offerId',
        jwt: c.buyerJwt,
        body: {'amount': 0.50},
      );
      if (amtPatch.ok && numOf(amtPatch.map?['amount']) == 0.5) {
        c.hold(
          id: 'RTU-U2-amount-after-accept',
          lens: 'U2',
          severity: 'P0',
          title: 'Buyer altera amount após aceite',
          actor: 'buyer JWT',
          pre: 'accepted 5€',
          repro: 'PATCH product_offers.amount=0.50',
          expected: 'offer_amount_immutable',
          obtained: amtPatch.map,
        );
      } else {
        c.block('RTU-U2-amt-immut', 'U2', 'amount imutável após aceite', amtPatch.brief);
      }

      final multi = await c.insertOrder(
        productId: sku,
        jwt: c.buyerJwt,
        qty: 4,
        price: 5,
        offerId: offerId,
      );
      if (multi != null) {
        final row = await c.orderRow(multi);
        final unit = numOf(row?['contract_unit_cents']);
        final cq = numOf(row?['contract_qty']);
        final ck = await c.checkout(orderId: multi, amount: 1, productId: sku);
        final payCents = ck.serverAmount;
        final catalog4 = 20 * 4 * 100;
        final offer4 = 5 * 4 * 100;
        c.note('u2.offer.qty4', 'order+checkout oferta×qty', {
          'oid': multi,
          'contract_unit': unit,
          'contract_qty': cq,
          'checkout': ck.brief,
          'server_amount': payCents,
        }, lens: 'U2');
        if (cq != null && cq > 1 && unit != null && unit <= 500) {
          final cheap = payCents != null && payCents < catalog4;
          if (cheap || (cq >= 4 && unit <= 500)) {
            c.hold(
              id: 'RTU-U2-offer-qty-n',
              lens: 'U2',
              severity: 'P0',
              title: 'Oferta aceite de 1 unidade aplica-se a qty=N',
              actor: 'buyer JWT',
              pre: 'oferta aceite 5 € (SKU 20 €, stock=5)',
              repro: 'POST orders quantity=4 product_offer_id; create-payment-intent',
              expected: 'offer_quantity_must_be_one ou catálogo × qty',
              obtained: {
                'contract_unit_cents': unit,
                'contract_qty': cq,
                'checkout_cents': payCents,
                'catalog_4_cents': catalog4,
                'offer_4_cents': offer4,
                'session': ck.checkoutSessionId,
              },
              evidence: {'order': row, 'checkout': ck.brief},
            );
          }
        } else {
          c.block('RTU-U2-offer-qty-n', 'U2', 'qty>1 com oferta recusado ou qty=1', {
            'oid': multi,
            'qty': cq,
            'unit': unit,
            'ck': ck.brief,
          });
        }
      } else {
        c.block('RTU-U2-offer-qty-n', 'U2', 'order qty=4 com oferta recusado', 'no row');
      }

      final second = await c.insertOrder(
        productId: sku,
        jwt: c.buyerJwt,
        qty: 1,
        price: 5,
        offerId: offerId,
      );
      if (second != null) {
        final row = await c.orderRow(second);
        if (row?['product_offer_id']?.toString() == offerId) {
          c.hold(
            id: 'RTU-U2-offer-reuse',
            lens: 'U2',
            severity: 'P1',
            title: 'Oferta aceite reutilizada em segunda encomenda',
            actor: 'buyer JWT',
            pre: 'oferta já ligada a order',
            repro: 'POST orders product_offer_id (2.ª vez)',
            expected: 'offer_already_consumed',
            obtained: row,
          );
        } else {
          c.block('RTU-U2-offer-reuse', 'U2', '2.ª order sem offer_id', row);
        }
      } else {
        c.block('RTU-U2-offer-reuse', 'U2', '2.ª order com oferta recusada', 'no row');
      }
    }
  }

  // Oferta caducada (expires_at no passado, status ainda pending)
  final skuExp = await c.createProduct(title: '$prefix u2-exp', qty: 2, price: 18);
  if (skuExp != null) {
    final chatE = await c.ensureChat(skuExp);
    final dead = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
      'product_id': skuExp,
      'chat_id': chatE,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'amount': 6,
      'list_price': 18,
      'offered_by': 'buyer',
      'status': 'pending',
      'expires_at': DateTime.now().toUtc().subtract(const Duration(days: 3)).toIso8601String(),
    });
    final did = dead.firstId;
    c.note('u2.dead.insert', 'offer expires_at passado', dead.brief, lens: 'U2');
    if (did != null) {
      c.createdOfferIds.add(did);
      final accDead = await c.rest(
        'PATCH',
        'product_offers?id=eq.$did',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
      final st = accDead.map?['status']?.toString();
      if (accDead.ok && st == 'accepted') {
        final oid = await c.insertOrder(
          productId: skuExp,
          jwt: c.buyerJwt,
          qty: 1,
          price: 6,
          offerId: did,
        );
        final row = oid == null ? null : await c.orderRow(oid);
        final ck = oid == null
            ? null
            : await c.checkout(orderId: oid, amount: 1, productId: skuExp);
        c.hold(
          id: 'RTU-U2-dead-offer-accept',
          lens: 'U2',
          severity: 'P1',
          title: 'Aceitar oferta com expires_at no passado',
          actor: 'seller JWT + buyer checkout',
          pre: 'pending expires_at = now-3d',
          repro: 'PATCH accepted; POST orders; create-payment-intent',
          expected: 'recusar accept ou não selar preço da oferta',
          obtained: {
            'accept': accDead.brief,
            'order': row,
            'checkout': ck?.brief,
            'server_amount': ck?.serverAmount,
          },
        );
      } else {
        c.block('RTU-U2-dead-offer', 'U2', 'accept oferta caducada recusado', accDead.brief);
      }
    }
  }

  await bundlePartialCheckout(c);
}

Future<void> bundlePartialCheckout(Rtu c) async {
  final expensive = await c.createProduct(title: '$prefix u2-bun-hi', qty: 2, price: 20);
  final cheapA = await c.createProduct(title: '$prefix u2-bun-a', qty: 3, price: 1);
  final cheapB = await c.createProduct(title: '$prefix u2-bun-b', qty: 3, price: 1);
  if (expensive == null || cheapA == null || cheapB == null) return;

  final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_ids': [expensive, cheapA, cheapB],
    'status': 'pending',
    'discount_pct': 50,
  });
  c.note('u2.bundle.ins', 'buyer bundle 3 SKUs', bun.brief, lens: 'U2');
  final bid = bun.firstId;
  if (bid == null) {
    c.block('RTU-U2-bundle-ins', 'U2', 'INSERT bundle falhou', bun.brief);
    return;
  }
  c.createdBundleIds.add(bid);

  final acc = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.sellerJwt,
    body: {'status': 'accepted', 'discount_pct': 50},
  );
  c.note('u2.bundle.acc', 'seller accept +50%', acc.brief, lens: 'U2');
  final total = numOf(acc.map?['total_eur']) ?? numOf(bun.map?['total_eur']);

  final buyerPatch = await c.rest(
    'PATCH',
    'product_bundles?id=eq.$bid',
    jwt: c.buyerJwt,
    body: {'total_eur': 0.50},
  );
  if (buyerPatch.ok && numOf(buyerPatch.map?['total_eur']) == 0.5) {
    c.hold(
      id: 'RTU-U2-bundle-buyer-total',
      lens: 'U2',
      severity: 'P0',
      title: 'Buyer PATCH total_eur do conjunto aceite',
      actor: 'buyer JWT',
      pre: 'bundle accepted',
      repro: 'PATCH product_bundles.total_eur=0.50',
      expected: 'congelar totais',
      obtained: buyerPatch.map,
    );
  } else {
    c.block('RTU-U2-bundle-buyer-total', 'U2', 'buyer não muda total_eur', buyerPatch.brief);
  }

  final onlyHi = await c.insertOrder(
    productId: expensive,
    jwt: c.buyerJwt,
    qty: 1,
    price: 20,
    bundleId: bid,
  );
  if (onlyHi == null) {
    c.block('RTU-U2-bundle-partial-order', 'U2', 'order com bundle_id falhou', 'no row');
    return;
  }
  final row = await c.orderRow(onlyHi);
  final ck = await c.checkoutBag(
    lines: [
      {'order_id': onlyHi, 'product_id': expensive, 'seller_id': c.sellerId},
    ],
    amount: 1,
  );
  final pay = ck.serverAmount;
  final catalogHi = 20 * 100;
  // protecção ~ 0.65+5% sobre itens; se itens ≈ total_eur do conjunto (11€) << 20€
  c.note('u2.bundle.partial.ck', 'bag só artigo caro', {
    'bundle_total': total,
    'order': row,
    'checkout': ck.brief,
    'server_amount': pay,
  }, lens: 'U2');
  if (ck.ok && pay != null && total != null && pay < catalogHi + 50) {
    final bundleCents = euroToCents(total);
    // Se cobrou o total do conjunto (3 artigos) por 1 artigo → finding
    if ((pay - bundleCents).abs() < 200 || pay < catalogHi) {
      c.hold(
        id: 'RTU-U2-bundle-partial-bag',
        lens: 'U2',
        severity: 'P0',
        title: 'Checkout do conjunto aplica total_eur sem todos os artigos no saco',
        actor: 'buyer JWT',
        pre: 'bundle aceite 3 SKUs (20+1+1); 1 hold do artigo 20 €',
        repro: 'POST create-payment-intent bag_checkout só order do SKU caro',
        expected: 'cobrar catálogo do(s) artigo(s) no saco, ou exigir todos os product_ids',
        obtained: {
          'bundle_total_eur': total,
          'checkout_cents': pay,
          'catalog_hi_cents': catalogHi,
          'session': ck.checkoutSessionId,
        },
        evidence: {'order': row, 'bundle': acc.map ?? bun.map, 'checkout': ck.brief},
      );
    }
  } else if (!ck.ok) {
    c.block('RTU-U2-bundle-partial', 'U2', 'bag parcial recusado', ck.brief);
  }
}

Future<void> lensU3(Rtu c) async {
  final sku = await c.createProduct(title: '$prefix u3', qty: 3, price: 12);
  if (sku == null) return;
  final oid = await c.insertOrder(
    productId: sku,
    jwt: c.buyerJwt,
    qty: 1,
    price: 12,
    shipping: 'envio transportadora (€3.50)',
  );
  if (oid == null) return;

  final cheapBody = await c.checkout(orderId: oid, amount: 1, productId: sku);
  c.note('u3.body.amount', 'body amount=1 vs quote', cheapBody.brief, lens: 'U3');
  final cents = cheapBody.serverAmount;
  if (cheapBody.ok && cents != null && cents < 350) {
    c.hold(
      id: 'RTU-U3-body-amount',
      lens: 'U3',
      severity: 'P0',
      title: 'Session Stripe segue amount do body',
      actor: 'buyer JWT',
      pre: 'order 12 € + transportadora',
      repro: 'POST create-payment-intent amount=1',
      expected: 'quote servidor (itens+portes+protecção)',
      obtained: cheapBody.brief,
      evidence: {'server_amount': cents},
    );
  } else {
    c.block('RTU-U3-body-amount', 'U3', 'quote ignora body.amount', {
      'cents': cents,
      'brief': cheapBody.brief,
    });
  }

  final shipBody = await c.edge('create-payment-intent', {
    'buyer_id': c.buyerId,
    'order_id': oid,
    'amount': 1,
    'product_id': sku,
    'shipping_method': 'mao',
  }, jwt: c.buyerJwt);
  final shipCents = shipBody.serverAmount;
  // transportadora selada = 350 portes; mão = 0. Se quote sem 350 → unseal
  if (shipBody.ok && shipCents != null && shipCents < 1200) {
    // 12€=1200 + 0 ship + prot ≈ 1325; com carrier 12€+3.50+prot ≈ 1693
    c.note('u3.ship.body', 'checkout com body=mao vs selo carrier', {
      'cents': shipCents,
      'brief': shipBody.brief,
    }, lens: 'U3');
  }
  final expectedCarrierMin = 12 * 100 + 350;
  if (shipBody.ok && shipCents != null && shipCents < expectedCarrierMin) {
    c.hold(
      id: 'RTU-U3-ship-body-override',
      lens: 'U3',
      severity: 'P1',
      title: 'Body shipping_method=mão vence selo transportadora',
      actor: 'buyer JWT',
      pre: 'order shipping=envio transportadora',
      repro: 'POST create-payment-intent shipping_method=mao',
      expected: 'portes 3,50 € do selo',
      obtained: {'cents': shipCents, 'brief': shipBody.brief},
    );
  } else {
    c.block('RTU-U3-ship-body', 'U3', 'portes do selo prevalecem', shipBody.brief);
  }

  final prize = await c.checkout(
    orderId: oid,
    amount: 50,
    productId: sku,
    prize: true,
  );
  if (prize.ok && prize.checkoutSessionId != null) {
    final pc = prize.serverAmount;
    if (pc != null && pc < 1000) {
      c.hold(
        id: 'RTU-U3-prize-marketplace',
        lens: 'U3',
        severity: 'P0',
        title: 'prize_shipping em encomenda marketplace (só portes)',
        actor: 'buyer JWT',
        pre: 'order marketplace sem rifa',
        repro: 'POST create-payment-intent prize_shipping=true',
        expected: 'Checkout blocked: order is not a raffle prize',
        obtained: prize.brief,
      );
    }
  } else {
    c.block('RTU-U3-prize', 'U3', 'prize_shipping marketplace bloqueado', prize.brief);
  }

  final ensure = await c.rpc(
    'batata_ensure_checkout_product',
    {'p_live_item_id': '00000000-0000-0000-0000-000000000001'},
    jwt: c.buyerJwt,
  );
  c.note('u3.ensure', 'ensure_checkout_product buyer', ensure.brief, lens: 'U3');

  final fakeGet = await c.req(
    'GET',
    '/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_rtu0855_unpaid',
    jwt: c.buyerJwt,
  );
  if (fakeGet.status >= 200 && fakeGet.status < 300 && fakeGet.body.toLowerCase().contains('pago')) {
    c.hold(
      id: 'RTU-U3-fake-session-settle',
      lens: 'U3',
      severity: 'P0',
      title: 'GET settle com session inventada marca pago',
      actor: 'buyer JWT',
      pre: 'cs_test inexistente',
      repro: 'GET create-payment-intent?checkout_return=success&session_id=',
      expected: '400/402',
      obtained: fakeGet.brief,
    );
  } else {
    c.block('RTU-U3-fake-session', 'U3', 'settle session fake recusado', fakeGet.brief);
  }

  final e2eJwt = await c.edge(
    'create-payment-intent',
    {'order_id': oid, 'payment_intent_id': 'pi_test_x'},
    jwt: c.buyerJwt,
    qs: 'fase2_e2e_settle=1',
  );
  if (e2eJwt.ok) {
    c.hold(
      id: 'RTU-U3-e2e-settle-jwt',
      lens: 'U3',
      severity: 'P0',
      title: 'fase2_e2e_settle aceita JWT comprador',
      actor: 'buyer JWT',
      pre: 'sk_test',
      repro: 'POST create-payment-intent?fase2_e2e_settle=1',
      expected: '401 service_role required',
      obtained: e2eJwt.brief,
    );
  } else {
    c.block('RTU-U3-e2e-jwt', 'U3', 'e2e settle exige service_role', e2eJwt.brief);
  }
}

Future<void> lensU4(Rtu c) async {
  final last = await c.createProduct(title: '$prefix u4-last', qty: 1, price: 11);
  if (last == null) return;

  final races = await parallel([
    c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': last,
      'price_total': 11,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    }),
    c.rest('POST', 'orders', jwt: c.buyer2Jwt, body: {
      'buyer_id': c.buyer2Id,
      'seller_id': c.sellerId,
      'product_id': last,
      'price_total': 11,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    }),
  ]);
  final okIds = <String>[];
  for (final h in races) {
    final id = h.firstId;
    if (h.ok && id != null) {
      okIds.add(id);
      c.createdOrderIds.add(id);
    }
  }
  c.note('u4.twoholds', '2 buyers última unidade', {
    'a': races[0].brief,
    'b': races[1].brief,
    'ok': okIds.length,
  }, lens: 'U4');
  if (okIds.length >= 2) {
    c.hold(
      id: 'RTU-U4-two-holds-last-unit',
      lens: 'U4',
      severity: 'P0',
      title: 'Dois holds simultâneos na última unidade marketplace',
      actor: 'buyer + buyer2 JWT',
      pre: 'SKU qty=1',
      repro: 'Future.wait POST orders ×2',
      expected: '1 hold, 1 order_hold_exceeds_stock',
      obtained: {'holds': okIds.length, 'ids': okIds},
    );
  } else {
    c.block('RTU-U4-twoholds', 'U4', '2.º hold última unidade recusado', {
      'ok': okIds.length,
      'a': races[0].brief,
      'b': races[1].brief,
    });
  }

  final hs = await c.createProduct(title: '$prefix u4-hs', qty: 1, price: 10);
  if (hs != null) {
    late String? oid;
    late HttpHit sold;
    await Future.wait([
      c.insertOrder(productId: hs, jwt: c.buyerJwt, qty: 1, price: 10).then((v) => oid = v),
      c.rest('PATCH', 'products?id=eq.$hs', jwt: c.sellerJwt, body: {'is_sold': true}).then((v) => sold = v),
    ]);
    c.note('u4.hold-sold', 'hold ∥ is_sold', {
      'oid': oid,
      'sold': sold.brief,
    }, lens: 'U4');
    final holdId = oid;
    if (holdId != null) {
      final prod = await c.productRow(hs);
      final ck = await c.checkout(orderId: holdId, amount: 50, productId: hs);
      if (ck.ok && ck.checkoutSessionId != null && prod?['is_sold'] == true) {
        c.hold(
          id: 'RTU-U4-hold-sold-checkout',
          lens: 'U4',
          severity: 'P1',
          title: 'Checkout após hold∥sold no mesmo SKU',
          actor: 'buyer JWT + seller JWT',
          pre: 'Future.wait insert hold ∥ PATCH is_sold',
          repro: 'create-payment-intent no hold',
          expected: 'Checkout blocked: product is marked sold',
          obtained: {'checkout': ck.brief, 'product': prod},
        );
      } else {
        c.block('RTU-U4-hold-sold', 'U4', 'checkout sold bloqueado ou hold falhou', {
          'ck': ck.brief,
          'sold': prod?['is_sold'],
        });
      }
    }
  }

  final ul = await c.createProduct(title: '$prefix u4-ul', qty: 2, price: 13);
  if (ul != null) {
    final oid = await c.insertOrder(productId: ul, jwt: c.buyerJwt, qty: 1, price: 13);
    if (oid != null) {
      final raced = await Future.wait([
        c.checkout(orderId: oid, amount: 50, productId: ul),
        c.rest('PATCH', 'products?id=eq.$ul', jwt: c.sellerJwt, body: {
          'list_on_marketplace': false,
        }),
      ]);
      final ck = raced[0];
      final unlist = raced[1];
      c.note('u4.ck-unlist', 'checkout ∥ unlist', {
        'ck': ck.brief,
        'unlist': unlist.brief,
      }, lens: 'U4');
      if (ck.ok && ck.checkoutSessionId != null) {
        final prod = await c.productRow(ul);
        if (prod?['list_on_marketplace'] == false) {
          c.hold(
            id: 'RTU-U4-checkout-unlist-race',
            lens: 'U4',
            severity: 'P1',
            title: 'Session criada em corrida com unlist',
            actor: 'buyer + seller JWT',
            pre: 'hold listed',
            repro: 'Future.wait create-payment-intent ∥ PATCH unlist',
            expected: 'falhar checkout se unlist ganhar',
            obtained: {'checkout': ck.brief, 'product': prod},
            proven: ck.ok,
          );
        }
      } else {
        c.block('RTU-U4-ck-unlist', 'U4', 'checkout∥unlist sem Session', ck.brief);
      }
    }
  }

  // Dual-pool: mesmo SKU marketplace + live_item
  final dual = await c.createProduct(
    title: '$prefix u4-dual',
    qty: 1,
    price: 14,
    live: true,
  );
  if (dual != null) {
    final mkt = await c.insertOrder(
      productId: dual,
      jwt: c.buyerJwt,
      qty: 1,
      price: 14,
    );
    c.note('u4.dual.mkt', 'hold marketplace SKU live-capable', {
      'oid': mkt,
      'pid': dual,
    }, lens: 'U4');
  }
}

Future<void> lensU5(Rtu c) async {
  final sku = await c.createProduct(title: '$prefix u5-mb', qty: 2, price: 8);
  if (sku == null) return;
  final oid = await c.insertOrder(
    productId: sku,
    jwt: c.buyerJwt,
    qty: 1,
    price: 8,
    payment: 'MB WAY',
  );
  if (oid == null) return;

  final stripeOnMb = await c.checkout(orderId: oid, amount: 50, productId: sku);
  if (stripeOnMb.ok && stripeOnMb.checkoutSessionId != null) {
    c.hold(
      id: 'RTU-U5-mbway-stripe-session',
      lens: 'U5',
      severity: 'P1',
      title: 'Checkout Stripe abre em encomenda MB WAY',
      actor: 'buyer JWT',
      pre: 'payment_method=MB WAY',
      repro: 'POST create-payment-intent',
      expected: 'Checkout blocked: off-platform',
      obtained: stripeOnMb.brief,
    );
  } else {
    c.block('RTU-U5-mb-stripe', 'U5', 'Stripe recusado em MB WAY', stripeOnMb.brief);
  }

  final buyerPago = await c.markPago(oid, jwt: c.buyerJwt);
  if (buyerPago.ok && (await c.orderRow(oid))?['status'] == 'pago') {
    c.hold(
      id: 'RTU-U5-buyer-pago',
      lens: 'U5',
      severity: 'P0',
      title: 'Comprador marca MB WAY como pago',
      actor: 'buyer JWT',
      pre: 'reserva_pendente MB WAY',
      repro: 'PATCH orders.status=pago',
      expected: 'reverter / recusar',
      obtained: buyerPago.brief,
    );
  } else {
    c.block('RTU-U5-buyer-pago', 'U5', 'buyer não marca pago', buyerPago.brief);
  }

  final buyerDone = await c.markConcluido(oid, jwt: c.buyerJwt);
  final stDone = (await c.orderRow(oid))?['status'];
  if (buyerDone.ok && stDone == 'concluido') {
    c.hold(
      id: 'RTU-U5-buyer-concluido-early',
      lens: 'U5',
      severity: 'P0',
      title: 'Comprador conclui MB WAY ainda em reserva',
      actor: 'buyer JWT',
      pre: 'reserva_pendente',
      repro: 'PATCH status=concluido',
      expected: 'reverter',
      obtained: {'status': stDone, 'brief': buyerDone.brief},
    );
  } else {
    c.block('RTU-U5-concluido-early', 'U5', 'concluido cedo bloqueado', {
      'status': stDone,
      'brief': buyerDone.brief,
    });
  }

  final wBefore = await c.walletBal(c.sellerId);
  final sPago = await c.markPago(oid, jwt: c.sellerJwt);
  final after = await c.orderRow(oid);
  final wAfter = await c.walletBal(c.sellerId);
  c.note('u5.seller.pago', 'S marca pago MB WAY', {
    'patch': sPago.brief,
    'status': after?['status'],
    'amount_paid_cents': after?['amount_paid_cents'],
    'wallet_delta': wAfter - wBefore,
    'stock_units': after?['stock_units_applied'],
  }, lens: 'U5');
  if (sPago.ok && after?['status'] == 'pago') {
    if ((numOf(after?['amount_paid_cents']) ?? 0) > 0) {
      c.hold(
        id: 'RTU-U5-mbway-amount-paid',
        lens: 'U5',
        severity: 'P1',
        title: 'MB WAY pago pelo vendedor escreve amount_paid_cents',
        actor: 'seller JWT',
        pre: 'sem prova / sem Stripe',
        repro: 'PATCH status=pago',
        expected: 'status pago off-platform sem amount_paid_cents Stripe',
        obtained: after,
      );
    }
    if (wAfter > wBefore) {
      c.hold(
        id: 'RTU-U5-mbway-wallet-mint',
        lens: 'U5',
        severity: 'P0',
        title: 'Marcar MB WAY pago credita a carteira de plataforma',
        actor: 'seller JWT',
        pre: 'sem captura Stripe',
        repro: 'PATCH status=pago',
        expected: 'Δwallet = 0',
        obtained: {'before': wBefore, 'after': wAfter},
      );
    } else {
      c.block('RTU-U5-mb-wallet', 'U5', 'MB WAY pago sem mint wallet', wAfter - wBefore);
    }
    final ref = await c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt);
    c.note('u5.refund.mb', 'refund-order MB WAY', ref.brief, lens: 'U5');
    if (ref.ok && (ref.map?['refund_id'] != null || '${ref.body}'.contains('re'))) {
      final hasStripe = (await c.orderRow(oid))?['stripe_refund_id'] != null;
      if (hasStripe) {
        c.hold(
          id: 'RTU-U5-mbway-stripe-refund',
          lens: 'U5',
          severity: 'P1',
          title: 'refund-order em MB WAY cria refund Stripe',
          actor: 'seller JWT',
          pre: 'order MB WAY sem PI',
          repro: 'POST refund-order',
          expected: 'not_seguro_fleaber / sem Stripe',
          obtained: ref.brief,
        );
      }
    }
  } else {
    c.block('RTU-U5-seller-pago', 'U5', 'S não marcou pago MB WAY', sPago.brief);
  }

  final last = await c.createProduct(title: '$prefix u5-last-mb', qty: 1, price: 7);
  if (last != null) {
    final a = await c.insertOrder(
      productId: last,
      jwt: c.buyerJwt,
      qty: 1,
      price: 7,
      payment: 'MB WAY',
    );
    final b = await c.insertOrder(
      productId: last,
      jwt: c.buyer2Jwt,
      buyer: c.buyer2Id,
      qty: 1,
      price: 7,
      payment: 'MB WAY',
    );
    final ids = [a, b].whereType<String>().toList();
    c.note('u5.mb.two', '2 MB WAY holds stock=1', ids, lens: 'U5');
    if (ids.length >= 2) {
      await c.markPago(ids[0], jwt: c.sellerJwt);
      await c.markPago(ids[1], jwt: c.sellerJwt);
      final sa = await c.orderRow(ids[0]);
      final sb = await c.orderRow(ids[1]);
      if (sa?['status'] == 'pago' && sb?['status'] == 'pago') {
        c.hold(
          id: 'RTU-U5-mbway-double-pago',
          lens: 'U5',
          severity: 'P0',
          title: 'Duas encomendas MB WAY pagas no último stock',
          actor: 'seller JWT',
          pre: '2 holds qty=1 stock=1',
          repro: 'PATCH pago nas duas',
          expected: 'só 1 pago',
          obtained: {'a': sa, 'b': sb},
        );
      } else {
        c.block('RTU-U5-mb-double', 'U5', '2.º pago MB WAY recusado', {
          'a': sa?['status'],
          'b': sb?['status'],
        });
      }
    }
  }
}

Future<void> lensU6(Rtu c) async {
  final paid = await c.payToPago(lens: 'U6', initialQty: 2);
  if (paid == null) {
    c.block('RTU-U6-fixture', 'U6', 'setup_paid_order falhou', 'null');
    return;
  }
  final wBefore = await c.wallets();
  final prodBefore = await c.productRow(paid.pid);

  final cancel = await c.markCancel(paid.oid, jwt: c.buyerJwt);
  final afterCancel = await c.orderRow(paid.oid);
  c.note('u6.cancel.paid', 'buyer cancel pós-pago', {
    'patch': cancel.brief,
    'status': afterCancel?['status'],
  }, lens: 'U6');
  if (afterCancel?['status'] == 'cancelado') {
    c.hold(
      id: 'RTU-U6-cancel-after-paid',
      lens: 'U6',
      severity: 'P0',
      title: 'Comprador anula encomenda já paga',
      actor: 'buyer JWT',
      pre: 'Stripe TEST pago',
      repro: 'PATCH status=cancelado',
      expected: 'manter pago',
      obtained: afterCancel,
    );
  } else {
    c.block('RTU-U6-cancel-paid', 'U6', 'cancel pós-pago bloqueado', afterCancel?['status']);
  }

  final buyerRefund = await c.edge('refund-order', {'order_id': paid.oid}, jwt: c.buyerJwt);
  if (buyerRefund.ok) {
    c.hold(
      id: 'RTU-U6-buyer-refund',
      lens: 'U6',
      severity: 'P0',
      title: 'Comprador chama refund-order (Seguro)',
      actor: 'buyer JWT',
      pre: 'order pago Stripe',
      repro: 'POST refund-order',
      expected: '403 Sem permissão',
      obtained: buyerRefund.brief,
    );
  } else {
    c.block('RTU-U6-buyer-refund', 'U6', 'buyer refund-order recusado', buyerRefund.brief);
  }

  final sellerRefund = await c.edge('refund-order', {'order_id': paid.oid}, jwt: c.sellerJwt);
  c.note('u6.seller.refund', 'refund-order seller', sellerRefund.brief, lens: 'U6');
  final afterRef = await c.books(paid.oid);
  final prodAfter = afterRef['product'] as Map<String, dynamic>?;
  final q0 = numOf(prodBefore?['quantity']) ?? 0;
  final q1 = numOf(prodAfter?['quantity']) ?? 0;
  if (sellerRefund.ok && q1 > q0 + 1) {
    c.hold(
      id: 'RTU-U6-double-restock',
      lens: 'U6',
      severity: 'P1',
      title: 'Refund restock > unidades da encomenda',
      actor: 'seller JWT',
      pre: 'pago qty=1',
      repro: 'POST refund-order',
      expected: '+1 stock',
      obtained: {'qty_before': q0, 'qty_after': q1, 'wallets': afterRef['wallets']},
    );
  }

  c.note('u6.books', 'contabilidade refund', {
    'w_before': wBefore,
    'after': {
      'status': (afterRef['order'] as Map?)?['status'],
      'refund': (afterRef['order'] as Map?)?['stripe_refund_id'],
      'stock_units': (afterRef['order'] as Map?)?['stock_units_applied'],
      'qty': prodAfter?['quantity'],
      'seller_estorno': afterRef['seller_estorno'],
    },
  }, lens: 'U6');

  // 2.º refund
  final again = await c.edge('refund-order', {'order_id': paid.oid}, jwt: c.sellerJwt);
  c.note('u6.refund2', 'refund repetido', again.brief, lens: 'U6');
}

Future<void> lensU7(Rtu c) async {
  final paid = await c.payToPago(lens: 'U7', initialQty: 3);
  if (paid == null) return;
  final o = await c.orderRow(paid.oid);
  final p = await c.productRow(paid.pid);
  final qty = numOf(p?['quantity']);
  final applied = numOf(o?['stock_units_applied']);
  c.note('u7.cross', 'stock order vs product', {
    'order_status': o?['status'],
    'order_qty': o?['quantity'],
    'stock_units_applied': applied,
    'product_qty': qty,
    'is_sold': p?['is_sold'],
    'listed': p?['list_on_marketplace'],
  }, lens: 'U7');
  if (o?['status'] == 'pago' && qty != null && applied != null) {
    // initial 3, sold 1 → expect qty=2 unless trigger uses different accounting
    if (qty < 0) {
      c.hold(
        id: 'RTU-U7-negative-stock',
        lens: 'U7',
        severity: 'P0',
        title: 'Stock marketplace negativo após pago',
        actor: 'observe',
        pre: 'setup_paid_order initial_qty=3',
        repro: 'consultar products.quantity',
        expected: 'quantity >= 0',
        obtained: p,
      );
    }
  }

  final pricePatch = await c.rest(
    'PATCH',
    'products?id=eq.${paid.pid}',
    jwt: c.buyerJwt,
    body: {'price': 0.50},
  );
  if (pricePatch.ok) {
    c.hold(
      id: 'RTU-U7-buyer-price',
      lens: 'U7',
      severity: 'P0',
      title: 'Buyer PATCH preço do anúncio',
      actor: 'buyer JWT',
      pre: 'produto alheio',
      repro: 'PATCH products.price=0.50',
      expected: 'RLS deny',
      obtained: pricePatch.brief,
    );
  } else {
    c.block('RTU-U7-buyer-price', 'U7', 'buyer não muda preço', pricePatch.brief);
  }
}

Future<void> lensU8(Rtu c) async {
  // Encadear oferta morta/qty + checkout + wallet (se Session criada)
  final sku = await c.createProduct(title: '$prefix u8-chain', qty: 4, price: 25);
  if (sku == null) return;
  final chat = await c.ensureChat(sku);
  final off = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': sku,
    'chat_id': chat,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': 6,
    'list_price': 25,
    'offered_by': 'buyer',
  });
  final oidOffer = off.firstId;
  if (oidOffer == null) return;
  c.createdOfferIds.add(oidOffer);
  await c.rest(
    'PATCH',
    'product_offers?id=eq.$oidOffer',
    jwt: c.sellerJwt,
    body: {'status': 'accepted'},
  );
  final order = await c.insertOrder(
    productId: sku,
    jwt: c.buyerJwt,
    qty: 3,
    price: 6,
    offerId: oidOffer,
  );
  if (order == null) {
    c.block('RTU-U8-chain-order', 'U8', 'cadeia oferta×3 recusada no INSERT', 'no row');
    return;
  }
  final w0 = await c.wallets();
  final ck = await c.checkout(orderId: order, amount: 1, productId: sku);
  c.note('u8.chain', 'oferta×3 → Session', {
    'order': await c.orderRow(order),
    'checkout': ck.brief,
    'wallets': w0,
  }, lens: 'U8');
  if (ck.ok && (ck.serverAmount ?? 99999) < 25 * 3 * 100) {
    c.hold(
      id: 'RTU-U8-offer-qty-checkout',
      lens: 'U8',
      severity: 'P0',
      title: 'Cadeia: oferta 6 € × qty 3 gera Session abaixo do catálogo',
      actor: 'buyer JWT',
      pre: 'oferta aceite 6 €, SKU 25 € ×4',
      repro: 'order qty=3 + create-payment-intent',
      expected: 'recusar qty>1 ou cobrar 25×3',
      obtained: {
        'server_amount_cents': ck.serverAmount,
        'catalog_3': 7500,
        'session': ck.checkoutSessionId,
      },
    );
  }

  final walIns = await c.rest('POST', 'wallet_transactions', jwt: c.buyerJwt, body: {
    'wallet_id': c.buyerId,
    'amount': 500,
    'type': 'reembolso',
    'description': prefix,
  });
  if (walIns.ok) {
    c.hold(
      id: 'RTU-U8-wallet-insert',
      lens: 'U8',
      severity: 'P0',
      title: 'Buyer INSERT wallet_transactions',
      actor: 'buyer JWT',
      pre: 'JWT',
      repro: 'POST wallet_transactions',
      expected: 'RLS deny',
      obtained: walIns.brief,
    );
  } else {
    c.block('RTU-U8-wallet-ins', 'U8', 'wallet INSERT bloqueado', walIns.brief);
  }
}
