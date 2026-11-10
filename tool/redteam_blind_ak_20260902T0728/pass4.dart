import 'dart:io';

import '_rtak.dart';

/// Pass 4 — marketplace hitch with quantity NULL (kind_stock_chk) then end → Session.
void main() async {
  final c = Rtak.fromEnv(loadEnv());
  await c.loginActors();

  final sku = await c.insertProduct(
    title: '$prefix p4-sku-40',
    price: 40,
    qty: 3,
    listed: true,
    live: true,
  );
  final live = await c.insertLive(
    seller: c.sellerId,
    status: 'live',
    active: true,
    muxPlayback: 'rtak_p4_live_$stamp',
    title: '$prefix p4-live',
  );
  final item = await c.rest('POST', 'live_items', service: true, body: {
    'live_id': live,
    'seller_id': c.sellerId,
    'title': '$prefix p4-cheap5',
    'status': 'available',
    'is_active': true,
    'price': 5,
    'item_kind': 'marketplace_product',
    'product_id': sku,
    'ref_code': 'RTAKP4',
  });
  stdout.writeln('ITEM ${item.status} ${item.body}');
  final iid = item.firstId;

  final out = <String, Object?>{
    'pass': 4,
    'sku': sku,
    'live': live,
    'item': iid,
    'item_http': '${item.status} ${clip(item.body, 400)}',
  };

  if (iid != null && live != null && sku != null) {
    await c.rest('PATCH', 'lives?id=eq.$live', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');

    final restB = await c.rest(
      'GET',
      'live_items?id=eq.$iid&select=id,price,status,quantity,is_active,item_kind,product_id',
      jwt: c.buyerJwt,
    );
    final fomo = await c.rpc('batata_hub_live_fomo_snapshot', {
      'p_live_id': live,
    });
    final hub = await c.rest(
      'GET',
      'hub_live_items_public?id=eq.$iid&select=id,price,status',
      jwt: c.buyerJwt,
    );
    c.note('p4.surfaces', 'after end',
        'rest=${restB.brief} fomo=${fomo.brief} hub=${hub.brief}',
        lens: 'AK7');

    final orderIns = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': sku,
      'live_item_id': iid,
      'live_id': live,
      'quantity': 1,
      'status': 'pendente',
      'payment_method': 'stripe',
      'shipping_method': 'ctt',
    });
    stdout.writeln('ORDER ${orderIns.status} ${orderIns.body}');
    final oid = orderIns.firstId;
    Map<String, dynamic>? contract;
    if (oid != null) {
      final crow = await c.rest(
        'GET',
        'orders?id=eq.$oid&select=id,status,contract_unit_cents,price_total,live_item_id,product_id',
        service: true,
      );
      contract = crow.map;
      final pi = await c.edge(
        'create-payment-intent',
        jwt: c.buyerJwt,
        extra: {'Origin': 'https://fleaber.pt'},
        body: {'order_id': oid, 'product_id': sku},
      );
      stdout.writeln('PI ${pi.status} ${clip(pi.body, 400)}');
      final cs = RegExp(r'cs_test_[A-Za-z0-9]+').firstMatch(pi.body)?.group(0);
      out['order'] = oid;
      out['contract'] = contract;
      out['cs'] = cs;
      out['pi'] = pi.brief;

      final cents = contract?['contract_unit_cents'];
      final looksCheap = cents == 500 ||
          pi.body.contains('590') ||
          (pi.map?['amount_total'] is num &&
              (pi.map!['amount_total'] as num) <= 700);
      if (looksCheap && pi.hasCheckout) {
        c.finding(
          id: 'RTAK-AK7-ENDED-HITCH-PRICE',
          lens: 'AK7',
          severity: 'P0',
          title:
              'Após ended, hitch marketplace_product a 5€ sela contrato e Session (catálogo 40€)',
          actor: 'buyer JWT',
          pre: 'item_kind=marketplace_product quantity NULL; live ended',
          repro: 'POST orders live_item_id → create-payment-intent',
          expected: 'cobrar catálogo 40€ ou recusar live ended',
          obtained: 'contract=$cents pi=${pi.snippet}',
          evidence: {
            'order': oid,
            'cs': cs,
            'contract_unit_cents': cents,
            'live_item': iid,
          },
        );
      } else if (!orderIns.ok) {
        c.hold(
          id: 'RTAK-AK7-ENDED-HITCH-PRICE',
          lens: 'AK7',
          title: 'order hitch ended recusado',
          actor: 'buyer JWT',
          pre: 'ended hitch',
          repro: 'POST orders',
          expected: 'denied',
          obtained: orderIns.brief,
        );
      } else {
        c.hold(
          id: 'RTAK-AK7-ENDED-HITCH-PRICE',
          lens: 'AK7',
          title: 'Session não barata / sem checkout',
          actor: 'buyer JWT',
          pre: 'ended hitch',
          repro: 'create-payment-intent',
          expected: '40€ or deny',
          obtained: 'contract=$cents ${pi.brief}',
        );
      }
    } else {
      c.hold(
        id: 'RTAK-AK7-ENDED-HITCH-PRICE',
        lens: 'AK7',
        title: 'INSERT order falhou',
        actor: 'buyer JWT',
        pre: 'ended hitch',
        repro: 'POST orders',
        expected: 'denied or 201',
        obtained: orderIns.brief,
      );
    }
  }

  await c.endLives();
  out['findings'] = c.findings;
  out['holds'] = c.holds;
  out['notes'] = c.notes;
  final path = '${repoRoot()}/tool/redteam_blind_ak_$stamp/pass4.json';
  await dumpJson(path, out);
  stdout.writeln(
      'WROTE $path findings=${c.findings.length} holds=${c.holds.length}');
}
