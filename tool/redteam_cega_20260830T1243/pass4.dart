import 'dart:io';

import '_http.dart';

Future<void> main() async {
  final ctx = await boot();
  final matrix = <Map<String, dynamic>>[];

  void row(String surface, String attack, String identity, Hit h) {
    matrix.add({
      'surface': surface,
      'attack': attack,
      'identity': identity,
      'result': '${h.status} ${h.snippet}',
    });
  }

  const sid = 'cs_test_a1r2TzykXcvB1WiD9uoHCobzYDBciVggb0UuwvA7Ban2TYawJtsfBYO2CS';
  final settleAnon = await ctx.rest(
    'GET',
    '/functions/v1/create-payment-intent?checkout_return=success&session_id=$sid',
  );
  row('SETTLE', 'GET return unpaid session', 'anon', settleAnon);

  final settleBuyer = await ctx.rest(
    'GET',
    '/functions/v1/create-payment-intent?checkout_return=success&session_id=$sid',
    jwt: ctx.buyerJwt,
  );
  row('SETTLE', 'GET return unpaid session', 'buyer', settleBuyer);

  final fake = await ctx.rest(
    'GET',
    '/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_fake_not_real',
  );
  row('SETTLE', 'GET fake session', 'anon', fake);

  final after = await ctx.select(
    'orders',
    service: true,
    filter: 'id=eq.3c9d060b-fa04-4e4c-926a-0e61f138306e',
    select: 'id,status,amount_paid_cents,stripe_payment_intent_id',
  );
  row('SETTLE', 'order after unpaid settle GET', 'service', after);

  // offers: buyer insert pending, seller accept 0.01, then order
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final prod = await ctx.rest('POST', '/rest/v1/products', jwt: ctx.sellerJwt, body: {
    'seller_id': ctx.sellerId,
    'title': 'CEGA1243 offer $stamp',
    'price': 30.00,
    'quantity': 1,
    'list_on_marketplace': true,
  });
  row('OFFERS', 'product', 'seller', prod);
  String? pid;
  if (prod.json is List && (prod.json as List).isNotEmpty) {
    pid = ((prod.json as List).first as Map)['id']?.toString();
  }
  if (pid != null) {
    final off = await ctx.rest('POST', '/rest/v1/product_offers', jwt: ctx.buyerJwt, body: {
      'product_id': pid,
      'buyer_id': ctx.buyerId,
      'seller_id': ctx.sellerId,
      'amount': 0.01,
      'status': 'pending',
    });
    row('OFFERS', 'buyer insert pending 0.01', 'buyer', off);
    String? oid;
    if (off.ok && off.json is List && (off.json as List).isNotEmpty) {
      oid = ((off.json as List).first as Map)['id']?.toString();
    }
    if (oid != null) {
      final acc = await ctx.rest(
        'PATCH',
        '/rest/v1/product_offers?id=eq.$oid',
        jwt: ctx.sellerJwt,
        body: {'status': 'accepted'},
      );
      row('OFFERS', 'seller accept 0.01', 'seller', acc);
      final accB = await ctx.rest(
        'PATCH',
        '/rest/v1/product_offers?id=eq.$oid',
        jwt: ctx.buyerJwt,
        body: {'status': 'accepted'},
      );
      row('OFFERS', 'buyer self-accept', 'buyer', accB);
      final order = await ctx.rest('POST', '/rest/v1/orders', jwt: ctx.buyerJwt, body: {
        'buyer_id': ctx.buyerId,
        'seller_id': ctx.sellerId,
        'product_id': pid,
        'product_offer_id': oid,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Seguro Fleaber',
        'shipping_method': 'hand',
      });
      row('OFFERS', 'order with offer 0.01', 'buyer', order);
      if (order.ok) {
        String? orderId;
        if (order.json is List && (order.json as List).isNotEmpty) {
          orderId = ((order.json as List).first as Map)['id']?.toString();
        }
        if (orderId != null) {
          final ck = await ctx.edge('create-payment-intent', {
            'buyer_id': ctx.buyerId,
            'order_id': orderId,
            'shipping_method': 'hand',
          }, jwt: ctx.buyerJwt);
          row('OFFERS', 'checkout after 0.01 offer', 'buyer', ck);
        }
      }
    }
  }

  // waitlist / converted reservation
  final conv = await ctx.rest(
    'PATCH',
    '/rest/v1/live_reservation_requests?status=eq.pending&buyer_id=eq.${ctx.buyerId}',
    jwt: ctx.buyerJwt,
    body: {'status': 'converted', 'requested_qty': 99},
  );
  row('BAG', 'buyer PATCH converted qty99', 'buyer', conv);

  final oa = await ctx.rest('GET', '/rest/v1/', extra: {
    'Accept': 'application/openapi+json',
    'Content-Profile': 'public',
  });
  row('OpenAPI', 'GET rest root', 'anon', Hit(oa.status, oa.body.substring(0, oa.body.length.clamp(0, 200))));

  await writeOut('pass4.json', {'pass': 4, 'matrix': matrix});
  stdout.writeln('PASS4 done matrix=${matrix.length}');
}
