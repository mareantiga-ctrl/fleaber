/// REDTEAM_BLIND_AJ pass2 — deepen AJ4-02 + remaining lenses with valid market fixtures.
import 'dart:io';
import '_rtaj.dart';

Future<void> main() async {
  final rt = Rtaj.fromEnv(loadEnv());
  stdout.writeln('AJ pass2 staging=${rt.url}');
  await rt.loginActors();
  await rt.ensureBuyer2();
  await rt.ensureSeller2();

  final liveA = await rt.insertLive();
  final liveB = await rt.insertLive();
  final liveS2 = await rt.insertLive(seller: rt.seller2Id);
  if (liveA == null || liveB == null || liveS2 == null) {
    stderr.writeln('no live');
    exit(4);
  }

  final victim = await rt.createProduct(
    seller: rt.seller2Id,
    title: '$prefix-victim-hub',
    qty: 1,
    price: 21,
  );
  final victim2 = await rt.createProduct(
    seller: rt.seller2Id,
    title: '$prefix-victim-patch',
    qty: 1,
    price: 22,
  );
  final ownMkt = await rt.createProduct(title: '$prefix-own-mkt', qty: 1, price: 14);
  final skuDup = await rt.createProduct(title: '$prefix-dup', qty: 1, price: 16);

  // market items: quantity MUST be null (kind_stock_chk)
  final mkt = await rt.insertMarketItem(
    liveId: liveA,
    productId: ownMkt!,
    jwt: rt.sellerJwt,
    ref: 'MKT1',
  );
  rt.note('p2.mkt', 'market item qty-null', mkt, lens: 'AJ3');

  // ----- AJ4-02b: Hub + buyer surfaces after cross-unlist -----
  if (victim != null) {
    final hubBefore = await rt.rest(
      'GET',
      'hub_products_public?id=eq.$victim&select=id,title,is_sold',
    );
    final lo = await rt.insertLiveOnlyItem(
      liveId: liveA,
      qty: 1,
      jwt: rt.sellerJwt,
      checkoutProductId: victim,
      ref: 'VIC1',
    );
    Map<String, dynamic>? itemBefore;
    if (lo != null) itemBefore = await rt.itemRow(lo);
    final prodBefore = await rt.productRow(victim);
    HttpHit? ms;
    if (lo != null) ms = await rt.markSold(lo, jwt: rt.sellerJwt);
    final prodAfter = await rt.productRow(victim);
    final itemAfter = lo == null ? null : await rt.itemRow(lo);
    final hubAfter = await rt.rest(
      'GET',
      'hub_products_public?id=eq.$victim&select=id,title,is_sold',
    );
    final buyerProd = await rt.rest(
      'GET',
      'products?id=eq.$victim&select=id,is_sold,list_on_marketplace,seller_id',
      jwt: rt.buyerJwt,
    );
    final s2prod = await rt.rest(
      'GET',
      'products?id=eq.$victim&select=id,is_sold,list_on_marketplace',
      jwt: rt.seller2Jwt,
    );
    final buyAttempt = await rt.insertOrder(
      productId: victim,
      seller: rt.seller2Id,
      jwt: rt.buyerJwt,
      price: 21,
    );
    final w0 = await rt.walletBal(rt.seller2Id);
    rt.note('p2.aj4.hub', 'cross unlist surfaces', {
      'hubBefore': hubBefore.brief,
      'hubAfter': hubAfter.brief,
      'buyerProd': buyerProd.brief,
      's2prod': s2prod.brief,
      'buyAttempt': buyAttempt.brief,
      'itemBefore': itemBefore,
      'itemAfter': itemAfter,
      'walletS2': w0,
    }, lens: 'AJ4');

    final unlisted = prodAfter?['is_sold'] == true &&
        prodAfter?['list_on_marketplace'] == false;
    final hubGone = hubAfter.ok && hubAfter.list.isEmpty;
    if (unlisted) {
      rt.hold(
        id: 'AJ4-02b',
        lens: 'AJ4',
        severity: 'P1',
        title: 'Unlist cruzado: Hub some; live_item pode ficar available',
        actor: 'seller',
        pre: 'SKU seller2 listado no Hub; live_only checkout_product_id',
        repro: 'mark_sold no live_only do seller A',
        expected: 'produto seller2 intacto',
        obtained: {
          'ms': ms?.brief,
          'prodBefore': prodBefore,
          'prodAfter': prodAfter,
          'hubBeforeEmpty': hubBefore.list.isEmpty,
          'hubAfterGone': hubGone,
          'itemStatusAfter': itemAfter?['status'],
          'buyAttempt': buyAttempt.brief,
          'victimPublicId': victim,
        },
      );
    } else {
      rt.block('AJ4-02b', 'AJ4', 'cross unlist not sticky', prodAfter);
    }

    // seller2 tries to relist
    final relist = await rt.rest(
      'PATCH',
      'products?id=eq.$victim',
      jwt: rt.seller2Jwt,
      body: {'is_sold': false, 'list_on_marketplace': true},
    );
    final afterRelist = await rt.productRow(victim);
    rt.note('p2.aj4.relist', 'seller2 relist', {
      'patch': relist.brief,
      'row': afterRelist,
    }, lens: 'AJ4');
  }

  // PATCH checkout_product_id on existing live_only → second victim
  if (victim2 != null) {
    final lo = await rt.insertLiveOnlyItem(
      liveId: liveA,
      qty: 1,
      jwt: rt.sellerJwt,
      ref: 'PATCHCK',
    );
    if (lo != null) {
      final patch = await rt.rest(
        'PATCH',
        'live_items?id=eq.$lo',
        jwt: rt.sellerJwt,
        body: {'checkout_product_id': victim2},
      );
      final row = await rt.itemRow(lo);
      final before = await rt.productRow(victim2);
      final ms = await rt.markSold(lo, jwt: rt.sellerJwt);
      final after = await rt.productRow(victim2);
      if (after?['is_sold'] == true) {
        rt.hold(
          id: 'AJ4-06',
          lens: 'AJ4',
          severity: 'P1',
          title: 'PATCH checkout_product_id depois do INSERT + mark_sold unlist alheio',
          actor: 'seller',
          pre: 'live_only sem checkout; PATCH para SKU seller2',
          repro: 'PATCH checkout_product_id + mark_sold',
          expected: 'PATCH recusado ou unlist só próprio',
          obtained: {
            'patch': patch.brief,
            'row': row,
            'before': before,
            'ms': ms.brief,
            'after': after,
          },
        );
      } else {
        rt.block('AJ4-06', 'AJ4', 'PATCH checkout then mark_sold', {
          'patch': patch.brief,
          'ms': ms.brief,
          'after': after,
        });
      }
    }
  }

  // buyer cannot set checkout_product_id
  if (mkt != null && victim != null) {
    final bp = await rt.rest(
      'PATCH',
      'live_items?id=eq.$mkt',
      jwt: rt.buyerJwt,
      body: {'checkout_product_id': victim},
    );
    rt.block('AJ4-07', 'AJ4', 'buyer PATCH checkout_product_id', bp.brief);
  }

  // mark_sold marketplace_product without PI — should NOT unlist (AA invariant)
  if (mkt != null && ownMkt != null) {
    final before = await rt.productRow(ownMkt);
    final ms = await rt.markSold(mkt, jwt: rt.sellerJwt);
    final after = await rt.productRow(ownMkt);
    final item = await rt.itemRow(mkt);
    if (after?['is_sold'] == true || after?['list_on_marketplace'] == false) {
      rt.hold(
        id: 'AJ4-08',
        lens: 'AJ4',
        severity: 'P1',
        title: 'mark_sold marketplace_product deslista sem PI (regressão AA)',
        actor: 'seller',
        pre: 'sem order paga',
        repro: 'mark_sold em item_kind=marketplace_product',
        expected: 'produto continua listado',
        obtained: {'ms': ms.brief, 'before': before, 'after': after, 'item': item},
      );
    } else {
      rt.block('AJ4-08', 'AJ4', 'mkt mark_sold no unlist without PI', {
        'ms': ms.brief,
        'after': after,
        'itemStatus': item?['status'],
      });
    }
  }

  // AJ3 Hub after INSERT sold
  final soldIns = await rt.rest('POST', 'live_items', jwt: rt.sellerJwt, body: {
    'live_id': liveA,
    'ref_code': 'SOLD2',
    'title': '$prefix sold2',
    'price': 3,
    'is_active': true,
    'item_kind': 'live_only',
    'quantity': 1,
    'status': 'sold',
  });
  final soldId = soldIns.firstId;
  if (soldId != null) rt.createdItemIds.add(soldId);
  if (soldId != null) {
    final disc = await rt.rest(
      'GET',
      'hub_live_items_discovery_public?id=eq.$soldId&select=id,status',
    );
    final hub = await rt.rest(
      'GET',
      'hub_live_items_public?id=eq.$soldId&select=id,status',
    );
    final buyerLi = await rt.rest(
      'GET',
      'live_items?id=eq.$soldId&select=id,status',
      jwt: rt.buyerJwt,
    );
    final ghost = (disc.list.isNotEmpty) || (hub.list.isNotEmpty) || buyerLi.list.isNotEmpty;
    if (ghost) {
      rt.hold(
        id: 'AJ3-03',
        lens: 'AJ3',
        severity: 'P2',
        title: 'INSERT status=sold ainda visível a buyer/Hub',
        actor: 'buyer/anon',
        pre: 'INSERT sold',
        repro: 'GET hub + REST buyer',
        expected: 'oculto',
        obtained: {
          'disc': disc.brief,
          'hub': hub.brief,
          'buyer': buyerLi.brief,
        },
      );
    } else {
      rt.block('AJ3-03', 'AJ3', 'INSERT sold hidden', {
        'disc': disc.brief,
        'hub': hub.brief,
        'buyer': buyerLi.brief,
      });
    }
  }

  // AJ1 remaining with market item
  if (mkt != null && ownMkt != null) {
    final pend = await rt.insertReservation(
      liveId: liveA,
      liveItemId: mkt,
      buyer: rt.buyerId,
      jwt: rt.buyerJwt,
      source: 'fleaber_live',
    );
    final rid = pend.firstId;
    final ord = await rt.insertOrder(
      productId: ownMkt,
      jwt: rt.buyerJwt,
      liveItemId: mkt,
      liveId: liveA,
      price: 14,
    );
    final oid = ord.firstId;
    rt.note('p2.aj1.ord', 'buyer order+res', {
      'res': pend.brief,
      'ord': ord.brief,
    }, lens: 'AJ1');
    if (oid != null && rid != null) {
      await rt.rest('PATCH', 'orders?id=eq.$oid', jwt: rt.buyerJwt, body: {
        'status': 'paid',
      });
      final rec = await rt.reconcileStripe(oid, reqId: rid, jwt: rt.buyerJwt);
      final sync = await rt.syncItemForOrder(oid, jwt: rt.buyerJwt);
      final req = await rt.reqRow(rid);
      final orow = await rt.orderRow(oid);
      if (req?['status'] == 'converted') {
        rt.hold(
          id: 'AJ1-06b',
          lens: 'AJ1',
          severity: 'P1',
          title: 'reconcile/sync converte reserva sem PI (order paid EN)',
          actor: 'buyer',
          pre: 'order sem amount_paid',
          repro: 'PATCH paid + reconcile/sync',
          expected: 'pending',
          obtained: {
            'rec': rec.brief,
            'sync': sync.brief,
            'req': req,
            'order': orow,
          },
        );
      } else {
        rt.block('AJ1-06b', 'AJ1', 'reconcile unpaid market', {
          'rec': rec.brief,
          'sync': sync.brief,
          'st': req?['status'],
          'ost': orow?['status'],
        });
      }
    }
  }

  // AJ5 duplicate SKU across two lives (quantity null)
  if (skuDup != null) {
    final d1 = await rt.insertMarketItem(
      liveId: liveA,
      productId: skuDup,
      jwt: rt.sellerJwt,
      ref: 'D1',
    );
    final d2 = await rt.insertMarketItem(
      liveId: liveB,
      productId: skuDup,
      jwt: rt.sellerJwt,
      ref: 'D2',
    );
    rt.note('p2.dup', 'dup items', {'d1': d1, 'd2': d2}, lens: 'AJ5');
    if (d1 != null && d2 != null) {
      final r1 = await rt.insertReservation(
        liveId: liveA,
        liveItemId: d1,
        buyer: rt.buyerId,
        jwt: rt.buyerJwt,
        source: 'fleaber_live',
      );
      final r2 = await rt.insertReservation(
        liveId: liveB,
        liveItemId: d2,
        buyer: rt.buyer2Id,
        jwt: rt.buyer2Jwt,
        source: 'fleaber_live',
      );
      final a1 = r1.firstId == null
          ? null
          : await rt.processReservation(r1.firstId!, 'accept');
      final a2 = r2.firstId == null
          ? null
          : await rt.processReservation(r2.firstId!, 'accept');
      final s1 = r1.firstId == null ? null : await rt.reqRow(r1.firstId!);
      final s2 = r2.firstId == null ? null : await rt.reqRow(r2.firstId!);
      final o1 = await rt.insertOrder(
        productId: skuDup,
        jwt: rt.buyerJwt,
        liveItemId: d1,
        liveId: liveA,
        price: 16,
      );
      final o2 = await rt.insertOrder(
        productId: skuDup,
        buyer: rt.buyer2Id,
        jwt: rt.buyer2Jwt,
        liveItemId: d2,
        liveId: liveB,
        price: 16,
      );
      final bothAcc =
          s1?['status'] == 'accepted' && s2?['status'] == 'accepted';
      final bothOrd = o1.ok && o2.ok;
      if (bothAcc || bothOrd) {
        rt.hold(
          id: 'AJ5-01b',
          lens: 'AJ5',
          severity: bothOrd ? 'P1' : 'P2',
          title: 'SKU qty=1 duplicado em duas lives: dupla accept/order',
          actor: 'seller+buyers',
          pre: 'unique é (live_id,product_id) não global',
          repro: 'dois live_items + accept + order',
          expected: '2º accept ou 2ª order bloqueada',
          obtained: {
            'a1': a1?.brief,
            'a2': a2?.brief,
            'st1': s1?['status'],
            'st2': s2?['status'],
            'o1': o1.brief,
            'o2': o2.brief,
          },
        );
      } else {
        rt.block('AJ5-01b', 'AJ5', 'dup sku holds', {
          'st1': s1?['status'],
          'st2': s2?['status'],
          'o1': o1.brief,
          'o2': o2.brief,
        });
      }
    }
  }

  // AJ3 after accept on market item
  if (mkt != null && ownMkt != null) {
    final st = await rt.stock(mkt, jwt: rt.buyerJwt);
    final disc = await rt.rest(
      'GET',
      'hub_live_items_discovery_public?id=eq.$mkt&select=id,status',
    );
    final hub = await rt.rest(
      'GET',
      'hub_live_items_public?id=eq.$mkt&select=id,status',
    );
    final fomo = await rt.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': liveA});
    final ph = await rt.rest(
      'GET',
      'hub_products_public?id=eq.$ownMkt&select=id,is_sold',
    );
    rt.note('p2.aj3.mkt', 'hub after mkt path', {
      'stock': st.brief,
      'disc': disc.brief,
      'hub': hub.brief,
      'fomo': clip(fomo.brief, 200),
      'prodHub': ph.brief,
    }, lens: 'AJ3');
  }

  // AJ7 tip spoof seller_id
  final tip = await rt.edge('create-live-tip-checkout', {
    'live_id': liveS2,
    'seller_id': rt.sellerId,
    'amount_eur': 1,
  }, jwt: rt.buyerJwt);
  rt.note('p2.aj8.tip', 'tip spoof seller_id', tip.brief, lens: 'AJ8');
  if (tip.ok) {
    final url = tip.map?['url'] ?? tip.map?['session_url'] ?? tip.map;
    rt.hold(
      id: 'AJ8-03',
      lens: 'AJ8',
      severity: 'P2',
      title: 'Tip checkout live alheia com seller_id spoof',
      actor: 'buyer',
      pre: 'liveS2 + seller_id=A',
      repro: 'edge create-live-tip-checkout',
      expected: '403 / live owner only',
      obtained: {'http': tip.brief, 'url': url},
    );
  } else {
    rt.block('AJ8-03', 'AJ8', 'tip spoof', tip.brief);
  }

  // AJ6 race convert same request
  if (mkt != null) {
    final p = await rt.insertReservation(
      liveId: liveA,
      liveItemId: mkt,
      buyer: rt.buyer2Id,
      jwt: rt.buyer2Jwt,
      source: 'fleaber_live',
    );
    final id = p.firstId;
    if (id != null) {
      await rt.processReservation(id, 'accept');
      final raced = await parallel([
        rt.processReservation(id, 'convert'),
        rt.processReservation(id, 'convert'),
      ]);
      rt.note('p2.aj6.convert', 'double convert', raced.map((e) => e.brief).toList(),
          lens: 'AJ6');
    }
  }

  // GraphQL live_items
  final gql = await rt.req('POST', '/graphql/v1', jwt: rt.buyerJwt, body: {
    'query': '{ live_itemsCollection(first: 3) { edges { node { id status } } } }',
  });
  rt.note('p2.gql', 'graphql', gql.brief, lens: 'AJ3');

  // restore victims (cleanup, not a product fix)
  const pass1Victims = [
    'd5d09e94-d1a8-4bd3-b429-a17b4ec8b3cb',
    '33c0358d-dfb6-4321-b1a5-9d25bb5b06b1',
  ];
  for (final id in [victim, victim2, ...pass1Victims]) {
    if (id == null) continue;
    await rt.rest('PATCH', 'products?id=eq.$id', service: true, body: {
      'is_sold': false,
      'list_on_marketplace': true,
    }, prefer: 'return=minimal');
  }

  await rt.endLives();
  await dumpJson('${outDir()}/pass2.json', {
    'findings': rt.findings,
    'blocked': rt.blocked,
    'notes': rt.notes,
    'lenses': rt.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'PASS2 findings=${rt.findings.length} blocked=${rt.blocked.length}');
}
