/// Blind E pass4 — Session Stripe PRE-unlist, depois unlist, pagar a Session antiga.
import 'dart:convert';
import 'dart:io';

import '_rte.dart';

void main() async {
  final env = loadEnv();
  final c = Rte.fromEnv(env);
  await c.loginActors(env);

  final pid = await c.insertProduct(
    title: '$prefix stale-session',
    price: 5.5,
    qty: 2,
  );
  if (pid == null) {
    stderr.writeln('no product');
    exit(1);
  }
  final o = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pid,
    'quantity': 1,
    'status': 'reservado',
    'price_total': 5.5,
    'shipping_method': 'ctt',
  });
  final oid = o.firstId;
  if (oid == null) {
    stderr.writeln('no order ${o.snippet}');
    exit(1);
  }

  final pay = await c.edge('create-payment-intent', jwt: c.buyerJwt, body: {
    'order_id': oid,
    'buyer_id': c.buyerId,
    'shipping_method': 'ctt',
  });
  final url = pay.map?['checkoutUrl']?.toString();
  final sid = pay.map?['checkoutSessionId']?.toString();

  await c.rest(
    'PATCH',
    'products?id=eq.$pid',
    jwt: c.sellerJwt,
    body: {'list_on_marketplace': false},
  );
  final prod = await c.rest(
    'GET',
    'products?id=eq.$pid&select=id,list_on_marketplace,is_sold,quantity',
    service: true,
  );
  final replay = await c.edge('create-payment-intent', jwt: c.buyerJwt, body: {
    'order_id': oid,
    'buyer_id': c.buyerId,
    'shipping_method': 'ctt',
  });

  final data = {
    'pid': pid,
    'oid': oid,
    'checkoutUrl': url,
    'checkoutSessionId': sid,
    'pay_http': pay.status,
    'listed_after': prod.map?['list_on_marketplace'],
    'product': prod.map,
    'replay_http': replay.status,
    'replay_body': replay.body,
    'pay_body_keys': pay.map?.keys.toList(),
  };
  await dumpJson('tool/redteam_blind_e_orbita_$stamp/out/pass4_session.json', data);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(data));
}
