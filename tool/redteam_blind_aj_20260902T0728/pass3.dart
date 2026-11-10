/// REDTEAM_BLIND_AJ pass3 — Hub published proof + accept log + repeat unlist.
import 'dart:io';
import '_rtaj.dart';

Future<void> main() async {
  final rt = Rtaj.fromEnv(loadEnv());
  stdout.writeln('AJ pass3');
  await rt.loginActors();
  await rt.ensureSeller2();
  await rt.ensureBuyer2();

  await rt.rest('PATCH', 'profiles?id=eq.${rt.seller2Id}', service: true, body: {
    'hub_published': true,
  }, prefer: 'return=minimal');

  final liveA = await rt.insertLive();
  final liveS2 = await rt.insertLive(seller: rt.seller2Id);
  if (liveA == null || liveS2 == null) exit(4);

  final victim = await rt.createProduct(
    seller: rt.seller2Id,
    title: '$prefix-hub-pub',
    qty: 1,
    price: 19,
  );
  if (victim == null) exit(4);

  final hub0 = await rt.rest(
    'GET',
    'hub_products_public?id=eq.$victim&select=id,title,is_sold,seller_id',
  );
  final hub0b = await rt.rest(
    'GET',
    'hub_products_public?id=eq.$victim&select=id,title,is_sold',
    jwt: rt.buyerJwt,
  );
  final lo = await rt.insertLiveOnlyItem(
    liveId: liveA,
    qty: 1,
    jwt: rt.sellerJwt,
    checkoutProductId: victim,
    ref: 'HUBP',
  );
  final ms = lo == null
      ? null
      : await rt.markSold(lo, jwt: rt.sellerJwt);
  final item = lo == null ? null : await rt.itemRow(lo);
  final prod = await rt.productRow(victim);
  final hub1 = await rt.rest(
    'GET',
    'hub_products_public?id=eq.$victim&select=id,title,is_sold',
  );
  final hub1b = await rt.rest(
    'GET',
    'hub_products_public?id=eq.$victim&select=id,title,is_sold',
    jwt: rt.buyerJwt,
  );

  rt.note('p3.hub', 'published hub unlist', {
    'hub0anon': hub0.brief,
    'hub0buyer': hub0b.brief,
    'ms': ms?.brief,
    'itemStatus': item?['status'],
    'prod': prod,
    'hub1anon': hub1.brief,
    'hub1buyer': hub1b.brief,
  }, lens: 'AJ3');

  final shownThenHidden = hub0.list.isNotEmpty && hub1.list.isEmpty;
  final shownBuyerThenHidden = hub0b.list.isNotEmpty && hub1b.list.isEmpty;
  if (prod?['is_sold'] == true && (shownThenHidden || shownBuyerThenHidden || hub0.list.isEmpty)) {
    rt.hold(
      id: 'AJ4-02c',
      lens: 'AJ3',
      severity: 'P1',
      title: 'SKU Hub público de seller2 some após mark_sold alheio',
      actor: 'seller A + anon/buyer Hub',
      pre: 'seller2 hub_published=true, produto listado',
      repro: 'live_only.checkout_product_id=victim + mark_sold JWT A',
      expected: 'Hub continua a mostrar o SKU seller2',
      obtained: {
        'hub0anonCount': hub0.list.length,
        'hub0buyerCount': hub0b.list.length,
        'hub1anonCount': hub1.list.length,
        'hub1buyerCount': hub1b.list.length,
        'prod': prod,
        'itemStatus': item?['status'],
        'shownThenHidden': shownThenHidden || shownBuyerThenHidden,
      },
    );
  } else {
    rt.block('AJ4-02c', 'AJ3', 'hub published unlist', {
      'hub0': hub0.brief,
      'hub1': hub1.brief,
      'prod': prod,
    });
  }

  // repeat: new victim via PATCH on SAME live_only still available
  final victimB = await rt.createProduct(
    seller: rt.seller2Id,
    title: '$prefix-hub-pub-2',
    qty: 1,
    price: 18,
  );
  if (lo != null && victimB != null && item?['status'] != 'sold') {
    final p = await rt.rest(
      'PATCH',
      'live_items?id=eq.$lo',
      jwt: rt.sellerJwt,
      body: {'checkout_product_id': victimB},
    );
    final ms2 = await rt.markSold(lo, jwt: rt.sellerJwt);
    final prodB = await rt.productRow(victimB);
    if (prodB?['is_sold'] == true) {
      rt.hold(
        id: 'AJ4-09',
        lens: 'AJ4',
        severity: 'P1',
        title: 'Reuso do mesmo live_item (status available) para unlist segundo SKU',
        actor: 'seller',
        pre: 'mark_sold não deixou status=sold',
        repro: 'PATCH checkout_product_id + mark_sold de novo',
        expected: 'item sold impede segundo unlist',
        obtained: {
          'patch': p.brief,
          'ms2': ms2.brief,
          'prodB': prodB,
          'item': await rt.itemRow(lo),
        },
      );
    } else {
      rt.block('AJ4-09', 'AJ4', 'reuse item second unlist', {
        'ms2': ms2.brief,
        'prodB': prodB,
      });
    }
  }

  // dup accept RPC detail
  final sku = await rt.createProduct(title: '$prefix-p3dup', qty: 1, price: 10);
  final liveB = await rt.insertLive();
  if (sku != null && liveB != null) {
    final d1 = await rt.insertMarketItem(
        liveId: liveA, productId: sku, jwt: rt.sellerJwt, ref: 'P3D1');
    final d2 = await rt.insertMarketItem(
        liveId: liveB, productId: sku, jwt: rt.sellerJwt, ref: 'P3D2');
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
      rt.note('p3.dup.accept', 'accept rpc', {
        'stock1': (await rt.stock(d1)).brief,
        'stock2': (await rt.stock(d2)).brief,
        'a1': a1?.brief,
        'a2': a2?.brief,
        's1': r1.firstId == null ? null : (await rt.reqRow(r1.firstId!))?['status'],
        's2': r2.firstId == null ? null : (await rt.reqRow(r2.firstId!))?['status'],
      }, lens: 'AJ5');
    }
  }

  // restore
  for (final id in [victim, victimB]) {
    if (id == null) continue;
    await rt.rest('PATCH', 'products?id=eq.$id', service: true, body: {
      'is_sold': false,
      'list_on_marketplace': true,
    }, prefer: 'return=minimal');
  }
  await rt.rest('PATCH', 'profiles?id=eq.${rt.seller2Id}', service: true, body: {
    'hub_published': false,
  }, prefer: 'return=minimal');

  await rt.endLives();
  await dumpJson('${outDir()}/pass3.json', {
    'findings': rt.findings,
    'blocked': rt.blocked,
    'notes': rt.notes,
    'lenses': rt.lensesHit.toList()..sort(),
  });
  stdout.writeln('PASS3 findings=${rt.findings.length} blocked=${rt.blocked.length}');
}
