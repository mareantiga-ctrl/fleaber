/// Pass 1 — POÇO 1 morto/montra + POÇO 3 política fina. Sem correções.
import 'dart:io';
import '_rt.dart';

bool persisted(HttpR r) =>
    r.ok && (r.list.isNotEmpty || (r.map != null && r.map!['id'] != null));

Future<void> main() async {
  final c = Rti4(loadEnv());
  await c.boot();
  stdout.writeln('boot buyer=${c.buyerId} seller=${c.sellerId} fresh=${c.freshId}');

  // ---- Schema / grants (service fixture observe) ----
  final cols = await c.call(
    'GET',
    '/rest/v1/products?select=id,title,price,quantity,cost_price,list_on_marketplace,is_sold,deleted_at,available_for_live&limit=1',
    service: true,
  );
  c.note('schema.products', 'products columns probe', cols.brief, well: '3');

  // ---- Anon Hub vs base ----
  final hubProdAnon = await c.rest(
    'GET',
    'hub_products_public?select=id,title,price,is_sold,seller_id&limit=20',
  );
  c.note('p3.hub.products.anon', 'hub_products_public anon', {
    'http': hubProdAnon.status,
    'n': hubProdAnon.list.length,
  }, well: '3');

  final baseAnon = await c.rest(
    'GET',
    'products?select=id,title,price,cost_price,quantity,list_on_marketplace,is_sold&limit=5',
  );
  c.note('p3.products.anon', 'products table anon', baseAnon.brief, well: '3');
  if (baseAnon.ok && baseAnon.list.isNotEmpty) {
    final row = Map<String, dynamic>.from(baseAnon.list.first as Map);
    final sensitive = row.containsKey('cost_price') && row['cost_price'] != null;
    c.finding(
      id: 'P3-ANON-PRODUCTS',
      title: 'Anon SELECT na tabela products (fora da view Hub)',
      actor: 'anon',
      sev: sensitive ? 'P1' : 'P2',
      well: '3',
      pre: 'GRANT/RLS products para anon',
      request: 'GET /rest/v1/products',
      before: null,
      after: clip(baseAnon.body, 500),
      impact: sensitive
          ? 'Anon lê catálogo base incluindo custo'
          : 'Anon lê tabela base em vez da view pública',
      repro: 'GET products as anon',
    );
  } else {
    c.hold('p3.products.anon', 'anon sem SELECT products', baseAnon.brief, well: '3');
  }

  final livesAnon = await c.rest(
    'GET',
    'lives?select=id,status,is_active,mux_stream_key,stream_key,seller_id&limit=5',
  );
  c.note('p3.lives.anon', 'lives table anon', livesAnon.brief, well: '3');
  if (livesAnon.ok && livesAnon.list.any((e) {
        if (e is! Map) return false;
        final k = '${e['mux_stream_key'] ?? e['stream_key'] ?? ''}';
        return k.isNotEmpty && k != 'null';
      })) {
    c.finding(
      id: 'P3-ANON-STREAM-KEY',
      title: 'Anon lê stream key via tabela lives',
      actor: 'anon',
      sev: 'P1',
      well: '3',
      pre: 'GET lives',
      request: 'GET lives select stream keys',
      before: null,
      after: clip(livesAnon.body, 400),
      impact: 'Chave de ingest visível',
      repro: 'GET lives as anon',
    );
  }

  final profilesAnon = await c.rest(
    'GET',
    'profiles?select=id,full_name,phone,iban,email,legal_full_name,shipping_line1&limit=3',
  );
  c.note('p3.profiles.anon', 'profiles anon', profilesAnon.brief, well: '3');

  // ---- Fixtures mortos ----
  final unlisted = await c.insertProduct(listed: false, sold: false, title: '$prefix-UNLIST');
  final sold = await c.insertProduct(listed: true, sold: true, title: '$prefix-SOLD');
  final listed = await c.insertProduct(listed: true, sold: false, title: '$prefix-LIVE', qty: 1);
  final listed2 = await c.insertProduct(listed: true, sold: false, title: '$prefix-B2', qty: 1, price: 5.5);
  if (unlisted == null || sold == null || listed == null) {
    stdout.writeln('FATAL fixture products');
    await c.dump('pass1');
    return;
  }
  final uid = unlisted['id'].toString();
  final sid = sold['id'].toString();
  final lid = listed['id'].toString();

  // Hub vs mortos
  final hubU = await c.rest('GET', 'hub_products_public?id=eq.$uid&select=id,title,is_sold');
  final hubS = await c.rest('GET', 'hub_products_public?id=eq.$sid&select=id,title,is_sold');
  final hubL = await c.rest('GET', 'hub_products_public?id=eq.$lid&select=id,title,is_sold,price');
  c.note('p1.hub.unlisted', 'hub unlist', {'n': hubU.list.length, 'http': hubU.status}, well: '1');
  c.note('p1.hub.sold', 'hub sold', {'n': hubS.list.length, 'http': hubS.status}, well: '1');
  if (hubU.list.isNotEmpty) {
    c.finding(
      id: 'P1-HUB-UNLIST',
      title: 'Hub público mostra produto unlist',
      actor: 'anon',
      sev: 'P2',
      well: '1',
      pre: 'list_on_marketplace=false',
      request: 'GET hub_products_public',
      before: unlisted,
      after: hubU.brief,
      impact: 'Montra pública mostra morto',
      repro: 'GET hub_products_public?id=eq.unlist',
    );
  } else {
    c.hold('p1.hub.unlisted', 'Hub vazio para unlist', hubU.brief, well: '1');
  }
  if (hubS.list.isNotEmpty) {
    c.finding(
      id: 'P1-HUB-SOLD',
      title: 'Hub público mostra is_sold',
      actor: 'anon',
      sev: 'P2',
      well: '1',
      pre: 'is_sold=true',
      request: 'GET hub_products_public',
      before: sold,
      after: hubS.brief,
      impact: 'Vendidos na montra',
      repro: 'GET hub_products_public is_sold',
    );
  } else {
    c.hold('p1.hub.sold', 'Hub vazio para is_sold', hubS.brief, well: '1');
  }

  // Buyer REST SELECT mortos (sem order)
  final buyU = await c.rest(
    'GET',
    'products?id=eq.$uid&select=id,title,price,cost_price,quantity,list_on_marketplace,is_sold',
    token: c.buyerJwt,
  );
  final buyS = await c.rest(
    'GET',
    'products?id=eq.$sid&select=id,title,price,cost_price,is_sold',
    token: c.buyerJwt,
  );
  c.note('p1.buyer.unlist.select', 'buyer select unlist', buyU.brief, well: '1');
  if (buyU.ok && buyU.list.isNotEmpty) {
    final row = Map<String, dynamic>.from(buyU.list.first as Map);
    c.finding(
      id: 'P1-BUYER-SELECT-UNLIST',
      title: 'Buyer lê produto unlist (preço/custo) sem order',
      actor: 'buyer JWT',
      sev: row['cost_price'] != null ? 'P1' : 'P2',
      well: '1',
      pre: 'list_on_marketplace=false, sem order',
      request: 'GET products',
      before: null,
      after: row,
      impact: 'Oráculo de preço/stock de SKU morto',
      repro: 'GET products?id=eq.unlist as buyer',
    );
  } else {
    c.hold('p1.buyer.unlist.select', 'buyer não vê unlist', buyU.brief, well: '1');
  }
  if (buyS.ok && buyS.list.isNotEmpty) {
    c.finding(
      id: 'P1-BUYER-SELECT-SOLD',
      title: 'Buyer lê produto is_sold sem order',
      actor: 'buyer JWT',
      sev: 'P2',
      well: '1',
      pre: 'is_sold=true',
      request: 'GET products sold',
      before: null,
      after: buyS.brief,
      impact: 'SKU vendido visível fora da montra',
      repro: 'GET products is_sold as buyer',
    );
  } else {
    c.hold('p1.buyer.sold.select', 'buyer não vê is_sold', buyS.brief, well: '1');
  }

  // Cost price on listed (buyer)
  final buyL = await c.rest(
    'GET',
    'products?id=eq.$lid&select=id,price,cost_price,quantity',
    token: c.buyerJwt,
  );
  if (buyL.ok && buyL.list.isNotEmpty) {
    final row = Map<String, dynamic>.from(buyL.list.first as Map);
    if (row.containsKey('cost_price') && row['cost_price'] != null) {
      c.finding(
        id: 'P3-COST-PRICE',
        title: 'Buyer lê cost_price no produto listado',
        actor: 'buyer JWT',
        sev: 'P2',
        well: '3',
        pre: 'produto listado',
        request: 'GET products select cost_price',
        before: null,
        after: row,
        impact: 'Custo interno no catálogo autenticado',
        repro: 'GET products?select=cost_price',
      );
    } else {
      c.hold('p3.cost_price', 'cost_price nulo ou omitido', row, well: '3');
    }
  }

  // ---- Hold JWT unlist / sold ----
  final oUnlist = await c.insertOrder(token: c.buyerJwt, productId: uid);
  c.note('p1.order.unlist', 'INSERT order unlist', oUnlist.brief, well: '1');
  if (persisted(oUnlist)) {
    final oid = c.orderIdOf(oUnlist)!;
    final after = await c.getOne('orders', oid, select: 'id,status,product_id,quantity');
    final chk = await c.checkout(token: c.buyerJwt, orderId: oid, productId: uid);
    c.note('p1.checkout.unlist', 'checkout unlist', chk.brief, well: '1');
    final sessionIssued = chk.ok &&
        ((chk.map?['checkoutUrl'] ?? chk.map?['url'] ?? chk.map?['session_id'] ?? '')
            .toString()
            .isNotEmpty);
    if (after != null &&
        ['reserva_pendente', 'reservado', 'aguarda_confirmacao']
            .contains('${after['status']}'.toLowerCase())) {
      c.finding(
        id: 'P1-HOLD-UNLIST',
        title: 'Hold JWT em produto unlist (Hub vazio)',
        actor: 'buyer JWT',
        sev: sessionIssued ? 'P1' : 'P2',
        well: '1',
        pre: 'list_on_marketplace=false, Hub vazio',
        request: 'POST orders + create-payment-intent',
        before: unlisted,
        after: {'order': after, 'checkout': clip(chk.body, 400), 'session': sessionIssued},
        impact: sessionIssued
            ? 'Session Stripe em SKU morto'
            : 'Hold de stock em SKU fora da montra',
        repro: 'POST orders unlist; POST create-payment-intent',
      );
    }
  } else {
    c.hold('p1.order.unlist', 'INSERT unlist bloqueado', oUnlist.brief, well: '1');
  }

  final oSold = await c.insertOrder(token: c.buyerJwt, productId: sid);
  c.note('p1.order.sold', 'INSERT order is_sold', oSold.brief, well: '1');
  if (persisted(oSold)) {
    final oid = c.orderIdOf(oSold)!;
    final chk = await c.checkout(token: c.buyerJwt, orderId: oid, productId: sid);
    c.finding(
      id: 'P1-HOLD-SOLD',
      title: 'Hold/checkout em is_sold=true',
      actor: 'buyer JWT',
      sev: chk.ok ? 'P1' : 'P2',
      well: '1',
      pre: 'is_sold=true',
      request: 'POST orders is_sold',
      before: sold,
      after: {'order': oSold.brief, 'checkout': chk.brief},
      impact: 'Segunda venda económica possível se Session',
      repro: 'POST orders is_sold',
    );
  } else {
    c.hold('p1.order.sold', 'INSERT is_sold bloqueado', oSold.brief, well: '1');
  }

  // Fake live_id / raffle
  final fakeLive = '00000000-0000-0000-0000-000000000001';
  final oFakeLive = await c.insertOrder(
    token: c.buyerJwt,
    productId: uid,
    liveId: fakeLive,
  );
  c.note('p1.order.fake.live', 'unlist + live_id fake', oFakeLive.brief, well: '1');
  if (persisted(oFakeLive)) {
    c.finding(
      id: 'P1-UNLIST-FAKE-LIVE',
      title: 'live_id UUID inválido bypassa unlist',
      actor: 'buyer JWT',
      sev: 'P1',
      well: '1',
      pre: 'unlist + live_id inexistente',
      request: 'POST orders live_id=fake',
      before: null,
      after: oFakeLive.brief,
      impact: 'Hold em morto via UUID forjado',
      repro: 'POST orders unlist + live_id fake',
    );
  } else {
    c.hold('p1.order.fake.live', 'fake live_id não bypassa', oFakeLive.brief, well: '1');
  }

  final oRaffle = await c.insertOrder(
    token: c.buyerJwt,
    productId: uid,
    liveRaffleId: fakeLive,
  );
  c.note('p1.order.raffle', 'unlist + live_raffle_id JWT', oRaffle.brief, well: '1');
  if (persisted(oRaffle)) {
    c.finding(
      id: 'P1-UNLIST-RAFFLE-JWT',
      title: 'live_raffle_id JWT bypassa unlist',
      actor: 'buyer JWT',
      sev: 'P1',
      well: '1',
      pre: 'unlist + live_raffle_id forjado',
      request: 'POST orders live_raffle_id',
      before: null,
      after: oRaffle.brief,
      impact: 'Hold fantasma / venda de morto',
      repro: 'POST orders live_raffle_id',
    );
  } else {
    c.hold('p1.order.raffle', 'raffle JWT ignorado', oRaffle.brief, well: '1');
  }

  // ---- Zombie live: seller PATCH is_active on ended ----
  final liveIns = await c.rest(
    'POST',
    'lives',
    token: c.sellerJwt,
    body: {
      'seller_id': c.sellerId,
      'vendedor_id': c.sellerId,
      'title': '$prefix-ZOMBIE',
      'status': 'ended',
      'is_active': false,
    },
  );
  c.note('p1.live.insert', 'INSERT ended live', liveIns.brief, well: '1');
  String? liveId = c.orderIdOf(liveIns) ?? liveIns.map?['id']?.toString();
  if (liveIns.list.isNotEmpty && liveIns.list.first is Map) {
    liveId = (liveIns.list.first as Map)['id']?.toString() ?? liveId;
  }
  if (liveId != null) c.createdLiveIds.add(liveId);

  if (liveId != null) {
    final z = await c.rest(
      'PATCH',
      'lives?id=eq.$liveId',
      token: c.sellerJwt,
      body: {'is_active': true, 'status': 'ended'},
    );
    c.note('p1.zombie.patch', 'PATCH is_active on ended', z.brief, well: '1');
    final liveAfter = await c.getOne(
      'lives',
      liveId,
      select: 'id,status,is_active,seller_id',
    );
    final zombieOn = liveAfter?['is_active'] == true;
    c.note('p1.zombie.state', 'live after patch', liveAfter, well: '1');

    final oZ = await c.insertOrder(
      token: c.buyerJwt,
      productId: uid,
      liveId: liveId,
    );
    c.note('p1.zombie.order', 'order unlist + zombie live', oZ.brief, well: '1');
    if (persisted(oZ) && zombieOn) {
      final oid = c.orderIdOf(oZ)!;
      final chk = await c.checkout(
        token: c.buyerJwt,
        orderId: oid,
        productId: uid,
        extra: {'live_id': liveId},
      );
      final sessionIssued = chk.ok &&
          ((chk.map?['checkoutUrl'] ?? chk.map?['url'] ?? chk.map?['session_id'] ?? '')
              .toString()
              .isNotEmpty);
      c.finding(
        id: 'P1-ZOMBIE-LIVE-UNLIST',
        title: 'Seller reativa is_active em live ended → hold/checkout de unlist',
        actor: 'seller JWT + buyer JWT',
        sev: sessionIssued ? 'P1' : 'P2',
        well: '1',
        pre: 'produto unlist; live status=ended is_active=true (PATCH seller)',
        request: 'PATCH lives is_active; POST orders live_id; create-payment-intent',
        before: {'listed': false, 'live': liveAfter},
        after: {
          'order': oZ.brief,
          'checkout': clip(chk.body, 500),
          'session': sessionIssued,
          'checkoutUrl': chk.map?['checkoutUrl'] ?? chk.map?['url'],
        },
        impact: sessionIssued
            ? 'Session Stripe para SKU fora da montra via directo-zombie'
            : 'Hold de stock em SKU unlist via is_active residual',
        repro: 'PATCH lives is_active=true status=ended; POST orders unlist+live_id',
      );
    } else if (!zombieOn) {
      c.hold('p1.zombie.patch', 'is_active não persistiu em ended', liveAfter, well: '1');
    } else {
      c.hold('p1.zombie.order', 'hold unlist+zombie bloqueado', oZ.brief, well: '1');
    }

    // live_item on ended live — product_id leak
    if (listed != null) {
      final li = await c.rest(
        'POST',
        'live_items',
        token: c.sellerJwt,
        body: {
          'live_id': liveId,
          'seller_id': c.sellerId,
          'product_id': lid,
          'title': '$prefix-LI',
          'price': 4.5,
          'is_active': true,
        },
      );
      c.note('p1.live_item.insert', 'live_item ended', li.brief, well: '1');
      final liId = li.list.isNotEmpty
          ? (li.list.first as Map)['id']?.toString()
          : li.map?['id']?.toString();
      if (liId != null) {
        final liBuy = await c.rest(
          'GET',
          'live_items?id=eq.$liId&select=id,live_id,product_id,price,title,checkout_product_id',
          token: c.buyerJwt,
        );
        c.note('p3.live_items.buyer', 'buyer live_items ended', liBuy.brief, well: '3');
        final liAnon = await c.rest(
          'GET',
          'live_items?id=eq.$liId&select=id,product_id,price',
        );
        c.note('p3.live_items.anon', 'anon live_items', liAnon.brief, well: '3');
        if (liBuy.ok && liBuy.list.isNotEmpty) {
          final row = Map<String, dynamic>.from(liBuy.list.first as Map);
          if (row['product_id'] != null) {
            c.note('p3.live_items.product_id', 'product_id na tabela live_items', row, well: '3');
          }
        }
        final disc = await c.rest(
          'GET',
          'hub_live_items_discovery_public?live_id=eq.$liveId&select=id,title,price,live_id',
        );
        c.note('p1.discovery.items', 'discovery live_items ended', {
          'http': disc.status,
          'n': disc.list.length,
          'hub_published_needed': true,
        }, well: '1');
      }
    }

    // Restore zombie
    await c.rest(
      'PATCH',
      'lives?id=eq.$liveId',
      token: c.sellerJwt,
      body: {'is_active': false, 'status': 'ended'},
    );
  }

  // ---- Offers on unlist ----
  final offerU = await c.rest(
    'POST',
    'product_offers',
    token: c.buyerJwt,
    body: {
      'product_id': uid,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'amount': 2.0,
      'offered_by': 'buyer',
      'status': 'pending',
    },
  );
  c.note('p1.offer.unlist', 'offer unlist', offerU.brief, well: '1');
  if (persisted(offerU)) {
    final ofId = c.orderIdOf(offerU)!;
    final acc = await c.rest(
      'PATCH',
      'product_offers?id=eq.$ofId',
      token: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    c.note('p1.offer.accept.unlist', 'seller accept unlist offer', acc.brief, well: '1');
    final accepted = acc.ok &&
        (acc.list.isNotEmpty
            ? '${(acc.list.first as Map)['status']}'.toLowerCase() == 'accepted'
            : true);
    if (accepted) {
      final oOff = await c.insertOrder(
        token: c.buyerJwt,
        productId: uid,
        extra: {'product_offer_id': ofId},
      );
      c.finding(
        id: 'P1-OFFER-UNLIST',
        title: 'Oferta+accept em produto unlist persiste',
        actor: 'buyer+seller JWT',
        sev: persisted(oOff) ? 'P1' : 'P2',
        well: '1',
        pre: 'unlist; offer INSERT+accept',
        request: 'POST product_offers; PATCH accepted; POST orders',
        before: unlisted,
        after: {'offer': offerU.brief, 'accept': acc.brief, 'order': oOff.brief},
        impact: 'Contrato em SKU fora da montra',
        repro: 'offer unlist → accept → order',
      );
    } else {
      c.hold('p1.offer.accept.unlist', 'accept unlist não persistiu', acc.brief, well: '1');
    }
  } else {
    c.hold('p1.offer.unlist', 'offer unlist bloqueado', offerU.brief, well: '1');
  }

  // ---- Bundles unlist ----
  final bun = await c.rest(
    'POST',
    'product_bundles',
    token: c.buyerJwt,
    body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_ids': [uid],
      'status': 'pending',
    },
  );
  c.note('p1.bundle.unlist', 'bundle unlist', bun.brief, well: '1');
  if (persisted(bun)) {
    c.finding(
      id: 'P1-BUNDLE-UNLIST',
      title: 'Bundle INSERT com produto unlist',
      actor: 'buyer JWT',
      sev: 'P1',
      well: '1',
      pre: 'product unlist',
      request: 'POST product_bundles',
      before: unlisted,
      after: bun.brief,
      impact: 'Conjunto sobre SKU morto',
      repro: 'POST product_bundles product_ids unlist',
    );
  } else {
    c.hold('p1.bundle.unlist', 'bundle unlist rejeitado', bun.brief, well: '1');
  }

  // Bundle listed then unlist then accept
  if (listed2 != null) {
    final bun2 = await c.rest(
      'POST',
      'product_bundles',
      token: c.buyerJwt,
      body: {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_ids': [listed2['id'], lid],
        'status': 'pending',
      },
    );
    c.note('p1.bundle.listed', 'bundle listed pair', bun2.brief, well: '1');
    if (persisted(bun2)) {
      final bid = c.orderIdOf(bun2)!;
      await c.rest(
        'PATCH',
        'products?id=eq.${listed2['id']}',
        token: c.sellerJwt,
        body: {'list_on_marketplace': false},
      );
      final accB = await c.rest(
        'PATCH',
        'product_bundles?id=eq.$bid',
        token: c.sellerJwt,
        body: {'status': 'accepted'},
      );
      final st = accB.list.isNotEmpty
          ? '${(accB.list.first as Map)['status']}'.toLowerCase()
          : '';
      c.note('p1.bundle.accept.after.unlist', 'accept after unlist', accB.brief, well: '1');
      if (st == 'accepted') {
        c.finding(
          id: 'P1-BUNDLE-ACCEPT-AFTER-UNLIST',
          title: 'Seller aceita bundle depois de unlist de um SKU',
          actor: 'seller JWT',
          sev: 'P2',
          well: '1',
          pre: 'bundle pending; PATCH list_on_marketplace=false; accept',
          request: 'PATCH product_bundles status=accepted',
          before: bun2.brief,
          after: accB.brief,
          impact: 'Aceitação sobre conjunto já morto; checkout posterior a validar',
          repro: 'bundle → unlist member → seller accept',
        );
      } else {
        c.hold('p1.bundle.accept.after.unlist', 'accept após unlist não ficou accepted',
            accB.brief, well: '1');
      }
    }
  }

  // ---- Catalog subtotal oracle ----
  final sub = await c.rpc(
    'batata_product_bundles_catalog_subtotal',
    {'p_product_ids': [uid, sid, lid]},
    token: c.buyerJwt,
  );
  c.note('p1.catalog.subtotal', 'subtotal JWT mortos+vivo', sub.brief, well: '1');
  final subN = num.tryParse('${sub.json}') ?? -1;
  if (subN > 4.5) {
    c.finding(
      id: 'P1-SUBTOTAL-DEAD-ORACLE',
      title: 'catalog_subtotal JWT inclui preço de mortos',
      actor: 'buyer JWT',
      sev: 'P2',
      well: '1',
      pre: 'ids unlist+sold+listed',
      request: 'rpc batata_product_bundles_catalog_subtotal',
      before: null,
      after: sub.brief,
      impact: 'Oráculo de preço de SKUs mortos',
      repro: 'rpc catalog_subtotal com ids mortos',
    );
  } else {
    c.hold('p1.catalog.subtotal', 'subtotal JWT não soma mortos', sub.brief, well: '1');
  }

  // ---- Silent PATCH pago ----
  final oPend = await c.insertOrder(
    token: c.buyerJwt,
    productId: lid,
    shipping: 'carrier',
  );
  if (persisted(oPend)) {
    final oid = c.orderIdOf(oPend)!;
    final patchPago = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      token: c.buyerJwt,
      body: {'status': 'pago', 'amount_paid_cents': 99900},
    );
    final afterPago = await c.getOne(
      'orders',
      oid,
      select: 'id,status,amount_paid_cents,stripe_payment_intent_id',
    );
    c.note('p3.silent.pago', 'PATCH pago pending', {
      'http': patchPago.status,
      'after': afterPago,
    }, well: '3');
    final st = '${afterPago?['status'] ?? ''}'.toLowerCase();
    if (st == 'pago' || (afterPago?['amount_paid_cents'] ?? 0) == 99900) {
      c.finding(
        id: 'P3-JWT-PAGO',
        title: 'JWT marca pago ou amount_paid sem captura',
        actor: 'buyer JWT',
        sev: 'P0',
        well: '2',
        pre: 'order reserva_pendente',
        request: 'PATCH status=pago amount_paid_cents=99900',
        before: oPend.brief,
        after: afterPago,
        impact: 'Falsificação de pagamento plataforma',
        repro: 'PATCH orders pago',
      );
    } else if (patchPago.ok && st != 'pago') {
      c.hold('p3.silent.pago', 'HTTP OK mas status não persistiu pago (silent)', afterPago,
          well: '3');
    } else {
      c.hold('p3.patch.pago', 'PATCH pago rejeitado', patchPago.brief, well: '3');
    }
  }

  // ---- Anon RPCs DEFINER ----
  for (final fn in [
    'batata_generate_auto_feedback',
    'batata_wallet_payout_debit',
    'batata_refund_buyer_wallet_for_order',
    'batata_create_live_tip_pending',
  ]) {
    final r = await c.rpc(fn, {});
    c.note('p3.anon.rpc.$fn', 'anon rpc', r.brief, well: '3');
    if (r.ok && !r.brief.toLowerCase().contains('error')) {
      c.finding(
        id: 'P3-ANON-RPC-$fn',
        title: 'Anon executou RPC DEFINER $fn',
        actor: 'anon',
        sev: 'P1',
        well: '3',
        pre: 'grant execute?',
        request: 'POST rpc/$fn',
        before: null,
        after: r.brief,
        impact: 'RPC privilegiado sem JWT',
        repro: 'POST /rest/v1/rpc/$fn as anon',
      );
    }
  }

  // notifications_view
  final nvAnon = await c.rest('GET', 'notifications_view?select=*&limit=5');
  c.note('p4.notify.anon', 'notifications_view anon', nvAnon.brief, well: '4');
  if (nvAnon.ok && nvAnon.list.isNotEmpty) {
    c.finding(
      id: 'P4-NOTIFY-ANON',
      title: 'Anon lê notifications_view (favoritos alheios)',
      actor: 'anon',
      sev: 'P1',
      well: '4',
      pre: 'GET notifications_view',
      request: 'GET notifications_view',
      before: null,
      after: clip(nvAnon.body, 400),
      impact: 'Feed de favoritos cross-user',
      repro: 'GET notifications_view as anon',
    );
  } else {
    c.hold('p4.notify.anon', 'anon sem notifications_view', nvAnon.brief, well: '4');
  }

  final nvBuyer = await c.rest(
    'GET',
    'notifications_view?select=*&limit=20',
    token: c.buyerJwt,
  );
  c.note('p4.notify.buyer', 'notifications_view buyer', {
    'http': nvBuyer.status,
    'n': nvBuyer.list.length,
  }, well: '4');
  if (nvBuyer.ok && nvBuyer.list.any((e) {
        if (e is! Map) return false;
        return '${e['target_user_id']}' != c.buyerId;
      })) {
    c.finding(
      id: 'P4-NOTIFY-CROSS',
      title: 'Buyer vê notifications de outro seller',
      actor: 'buyer JWT',
      sev: 'P1',
      well: '4',
      pre: 'buyer não é o seller alvo',
      request: 'GET notifications_view',
      before: null,
      after: clip(nvBuyer.body, 400),
      impact: 'PII de favoritos alheios',
      repro: 'GET notifications_view as buyer',
    );
  }

  // discovery: buyer2 is_live without hub_published
  if (c.freshJwt != null && c.freshId != null) {
    final pub = await c.rest(
      'PATCH',
      'profiles?id=eq.${c.freshId}',
      token: c.freshJwt,
      body: {'is_live': true, 'hub_published': false, 'full_name': '$prefix-ghost'},
    );
    c.note('p3.fresh.is_live', 'PATCH is_live fresh', pub.brief, well: '3');
    final disc = await c.rest(
      'GET',
      'hub_profiles_discovery_public?id=eq.${c.freshId}&select=id,full_name,is_live,hub_published,handle',
    );
    c.note('p3.discovery.ghost', 'discovery fresh is_live', disc.brief, well: '3');
    if (disc.list.isNotEmpty) {
      c.finding(
        id: 'P3-DISCOVERY-IS-LIVE-FLAG',
        title: 'Discovery mostra perfil só com is_live (sem hub_published nem live real)',
        actor: 'fresh JWT + anon',
        sev: 'P2',
        well: '3',
        pre: 'hub_published=false is_live=true, sem lives activas',
        request: 'PATCH profiles is_live; GET hub_profiles_discovery_public',
        before: null,
        after: disc.brief,
        impact: 'Montra falsa / enumeração',
        repro: 'PATCH is_live; GET discovery',
      );
    } else {
      c.hold('p3.discovery.ghost', 'is_live sozinho não entra na discovery', disc.brief,
          well: '3');
    }
    await c.rest(
      'PATCH',
      'profiles?id=eq.${c.freshId}',
      token: c.freshJwt,
      body: {'is_live': false},
    );
  }

  // reviews INSERT pending order
  if (persisted(oPend)) {
    final oid = c.orderIdOf(oPend)!;
    final rev = await c.rest(
      'POST',
      'reviews',
      token: c.buyerJwt,
      body: {
        'order_id': oid,
        'buyer_id': c.buyerId,
        'target_id': c.sellerId,
        'stars': 5,
        'comment': '$prefix fake review',
        'author_role': 'comprador',
      },
    );
    c.note('p2.review.pending', 'review on pending', rev.brief, well: '2');
    if (persisted(rev)) {
      c.finding(
        id: 'P2-REVIEW-UNPAID',
        title: 'Review persistida em order não concluída',
        actor: 'buyer JWT',
        sev: 'P1',
        well: '2',
        pre: 'order reserva_pendente',
        request: 'POST reviews',
        before: oPend.brief,
        after: rev.brief,
        impact: 'Reputação forjada',
        repro: 'POST reviews order pending',
      );
    } else {
      c.hold('p2.review.pending', 'review pending bloqueada', rev.brief, well: '2');
    }
  }

  await c.dump('pass1');
  stdout.writeln(
    'pass1 done findings=${c.findings.length} holds=${c.holds.length}',
  );
}
