import 'dart:io';

import '_rti4.dart';

Future<void> main() async {
  final c = Rti4(loadEnv());
  await c.boot();

  final unlistedId = 'bf6c5e1d-f59f-471c-be48-f12d5f36d044';
  final holdOid = '73be7fe0-4f15-409b-9eb4-93fec9f5fb5b';
  final liveId = '4d2efb5a-d520-4478-8d8d-1a2a0a92cc5c';

  final prod = await c.getOne(
    'products',
    unlistedId,
    select: 'id,title,is_sold,list_on_marketplace,quantity,seller_id',
  );
  final live = await c.getOne(
    'lives',
    liveId,
    select: 'id,seller_id,vendedor_id,status,is_active,title',
  );
  final items = await c.rest(
    'GET',
    'live_items?live_id=eq.$liveId&or=(product_id.eq.$unlistedId,checkout_product_id.eq.$unlistedId)&select=id,product_id,checkout_product_id,title,is_active',
    service: true,
  );
  c.note('p1b.context', 'unlist+live context', {
    'product': prod,
    'live': live,
    'live_items_for_sku': items.list,
  }, well: '1');

  // Edge checkout with required buyer_id
  final ck = await c.edge(
    'create-payment-intent',
    {
      'amount': 450,
      'currency': 'eur',
      'product_id': unlistedId,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'order_id': holdOid,
      'quantity': 1,
      'item_price': 450,
      'shipping': 0,
      'protection_fee': 0,
      'shipping_method': 'Entrega em mão (€0.00)',
      'live_id': liveId,
    },
    token: c.buyerJwt,
  );
  c.note('p1b.edge.unlist.live', 'edge checkout unlist+live', ck.brief, well: '1');
  final cs = ck.map?['checkoutSessionId']?.toString();
  final curl = ck.map?['checkoutUrl']?.toString();
  if (ck.ok && (cs ?? '').isNotEmpty) {
    c.finding(
      id: 'RTI4-P1-EDGE-UNLIST-LIVE',
      title: 'Edge cria Checkout Session de SKU unlistado via live_id activo (sem live_item)',
      actor: 'buyer JWT + Edge',
      sev: 'P1',
      well: '1',
      pre:
          'list_on_marketplace=false, Hub vazio, product NÃO está em live_items desta live',
      request: 'create-payment-intent order+buyer_id+live_id',
      before: {'product': prod, 'live_items': items.list},
      after: {
        'checkoutSessionId': cs,
        'hasUrl': (curl ?? '').isNotEmpty,
        'http': ck.brief,
      },
      impact:
          'SESSION CRIADA sobre montra morta. Qualquer live activo do seller reabre catálogo unlistado a quem tenha o UUID. Captura ≠ session — pass2/browser.',
      repro:
          'seller unlist + POST orders live_id=live activa (sem live_item) + create-payment-intent',
    );
    File('tool/redteam_blind_indep_$stamp/out/unlist_live_checkout.json')
        .writeAsStringSync(
      '{"order_id":"$holdOid","checkoutSessionId":"$cs","checkoutUrl":"${curl ?? ''}"}',
    );
    final getSettle = await c.call(
      'GET',
      '/functions/v1/create-payment-intent?checkout_return=success&session_id=$cs',
    );
    final oAfter = await c.getOne(
      'orders',
      holdOid,
      select: 'id,status,amount_paid_cents,stripe_checkout_session_id',
    );
    c.note('p1b.settle.unpaid', 'GET settle session unlist-live', {
      'http': getSettle.brief,
      'order': oAfter,
    }, well: '1');
    if ((oAfter?['status'] ?? '').toString().toLowerCase() == 'pago') {
      c.finding(
        id: 'RTI4-P1-SETTLE-UNPAID-DEAD',
        title: 'GET settle marca pago em Session de SKU morto não paga',
        actor: 'anon GET',
        sev: 'P0',
        well: '1',
        pre: 'cs criado, não pago',
        request: 'GET settle',
        before: holdOid,
        after: oAfter,
        impact: 'Captura falsa + venda de morto.',
        repro: 'GET create-payment-intent unpaid cs',
      );
    }
  } else {
    c.hold('p1b.edge.unlist.live', 'Edge recusou Session em unlist+live', ck.brief,
        well: '1');
  }

  // is_sold + own active live
  final sold = await c.insertProduct(listed: true, sold: true, qty: 1);
  if (sold != null) {
    final r = await c.insertOrder(
      token: c.buyerJwt,
      productId: sold['id'].toString(),
      liveId: liveId,
    );
    c.note('p1b.sold.live', 'is_sold + live_id activo', r.brief, well: '1');
    if (r.ok) {
      c.finding(
        id: 'RTI4-P1-SOLD-LIVE-HOLD',
        title: 'is_sold hold via live_id activo',
        actor: 'buyer',
        sev: 'P1',
        well: '1',
        pre: 'is_sold=true',
        request: 'POST orders live_id',
        before: sold,
        after: r.brief,
        impact: 'Vendidos voltam a hold durante directo.',
        repro: 'POST orders is_sold + live_id',
      );
    } else {
      c.hold('p1b.sold.live', 'is_sold continua bloqueado com live', r.brief,
          well: '1');
    }
  }

  // Fresh buyer same unlist+live (needs UUID)
  if (c.freshJwt != null) {
    final r = await c.insertOrder(
      token: c.freshJwt!,
      productId: unlistedId,
      buyer: c.freshId,
      liveId: liveId,
    );
    c.note('p1b.fresh.unlist.live', 'fresh hold unlist+live', r.brief, well: '1');
    if (r.ok && r.list.isNotEmpty) {
      c.createdOrderIds.add((r.list.first as Map)['id'].toString());
      c.finding(
        id: 'RTI4-P1-FRESH-DEAD-LIVE',
        title: 'buyer fresco hold de unlist alheio via live_id',
        actor: 'fresh',
        sev: 'P1',
        well: '1',
        pre: 'signup; UUID conhecido; live activa seller',
        request: 'POST orders',
        before: unlistedId,
        after: r.brief,
        impact: 'UUID + live activa = catálogo morto reaberto a qualquer conta.',
        repro: 'signup + POST orders live_id',
      );
    } else {
      c.hold('p1b.fresh.unlist', 'fresh não holda unlist (RLS/trigger)', r.brief,
          well: '1');
    }
  }

  // Offer on unlisted: persisted in pass1. Seller accept as buyer?
  final offers = await c.rest(
    'GET',
    'product_offers?product_id=eq.$unlistedId&select=id,status,amount,buyer_id,product_id&limit=5',
    service: true,
  );
  c.note('p1b.offers', 'offers on unlist', offers.brief, well: '1');
  if (offers.list.isNotEmpty) {
    final oid = (offers.list.first as Map)['id'].toString();
    final accB = await c.rest(
      'PATCH',
      'product_offers?id=eq.$oid',
      token: c.buyerJwt,
      body: {'status': 'accepted'},
    );
    final after = await c.getOne('product_offers', oid, select: 'id,status,amount');
    c.note('p1b.offer.self.accept', 'buyer accept own offer unlist',
        '${accB.brief} after=${after?['status']}', well: '1');
    if ((after?['status'] ?? '').toString().toLowerCase() == 'accepted') {
      c.finding(
        id: 'RTI4-P1-OFFER-SELF-ACCEPT-DEAD',
        title: 'buyer auto-aceita oferta em SKU unlistado',
        actor: 'buyer',
        sev: 'P1',
        well: '1',
        pre: 'offer pending em unlist',
        request: 'PATCH product_offers status=accepted',
        before: oid,
        after: after,
        impact: 'Contrato de preço selado sobre montra morta sem seller.',
        repro: 'POST offer unlist + PATCH accepted as buyer',
      );
    } else {
      c.hold('p1b.offer.self', 'self-accept recusado ou revertido', after, well: '1');
    }
    // persist offer-on-dead as P2 if still pending
    c.finding(
      id: 'RTI4-P1-OFFER-UNLIST',
      title: 'JWT cria product_offer em SKU unlistado (Hub vazio)',
      actor: 'buyer',
      sev: 'P2',
      well: '1',
      pre: 'list_on_marketplace=false; REST buyer SELECT vazio antes do offer?',
      request: 'POST product_offers',
      before: unlistedId,
      after: offers.list.first,
      impact: 'Canal de negociação em catálogo morto se o UUID for conhecido.',
      repro: 'POST product_offers product_id unlist',
    );
  }

  // Bundles schema
  final bunCols = await c.rest(
    'GET',
    'product_bundles?select=*&limit=1',
    service: true,
  );
  c.note('p3.bundle.cols', 'bundle sample', bunCols.brief, well: '3');
  final bun = await c.rest(
    'POST',
    'product_bundles',
    token: c.buyerJwt,
    body: {
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'status': 'accepted',
      'total_eur': 1,
    },
  );
  c.note('p1b.bundle.accept', 'buyer bundle accepted', bun.brief, well: '1');

  // Wallets correct columns
  final wAnon = await c.rest('GET', 'wallets?select=id,balance&limit=5');
  final wBuy = await c.rest(
    'GET',
    'wallets?select=id,balance&limit=5',
    token: c.buyerJwt,
  );
  c.note('p3.wallets.anon', 'wallets anon', wAnon.brief, well: '3');
  c.note('p3.wallets.buyer', 'wallets buyer', wBuy.brief, well: '3');
  final others = wBuy.list.whereType<Map>().where((m) => m['id'] != c.buyerId);
  if (wBuy.ok && others.isNotEmpty) {
    c.finding(
      id: 'RTI4-P3-WALLET-XUSER',
      title: 'buyer lê balance de wallets alheias',
      actor: 'buyer',
      sev: 'P1',
      well: '3',
      pre: 'GET wallets?select=id,balance',
      request: 'buyer JWT',
      before: null,
      after: others.map((m) => m['id']).take(5).toList(),
      impact: 'Saldo cross-user.',
      repro: 'GET wallets',
    );
  } else {
    c.hold('p3.wallets.scope', 'wallets buyer scoped', wBuy.brief, well: '3');
  }

  // Cron real names from pass1 hints
  for (final fn in [
    'batata_expire_product_offers',
    'batata_process_auto_feedback',
    'batata_wallet_payout_finalize',
    'batata_invoke_livekit_egress_cleanup',
    'batata_claim_expired_reservations',
  ]) {
    final a = await c.rpc(fn, {});
    final b = await c.rpc(fn, {}, token: c.buyerJwt);
    c.note('p4.cron2.$fn.anon', fn, a.brief, well: '4');
    c.note('p4.cron2.$fn.buyer', fn, b.brief, well: '4');
  }

  // OpenAPI via service
  final oa = await c.call(
    'GET',
    '/rest/v1/',
    service: true,
    extra: {'Accept': 'application/openapi+json'},
  );
  c.note('p3.oa.svc', 'openapi svc', '${oa.status} len=${oa.body.length}', well: '3');

  // notifications_view
  final nv = await c.rest(
    'GET',
    'notifications_view?select=*&limit=5',
    token: c.buyerJwt,
  );
  c.note('p4.notif.view', 'notifications_view', nv.brief, well: '4');

  // Hub FOMO rpc
  final fomo = await c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': liveId});
  c.note('p3.fomo.anon', 'fomo anon', fomo.brief, well: '3');

  await c.dump('pass3');
  stdout.writeln(
      'PASS3 done findings=${c.findings.length} holds=${c.holds.length}');
}
