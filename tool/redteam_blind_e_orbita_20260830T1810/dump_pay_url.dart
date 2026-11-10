/// Dump full checkout URL for dead SKU (E6 capture attempt).
import 'dart:io';

import '_http.dart';

Future<void> main() async {
  final c = await boot();
  final p = await rest(
    c.url,
    'POST',
    'products',
    headers: c.svcH,
    body: {
      'seller_id': c.sellerId,
      'title': '$prefix-payme',
      'price': 6.0,
      'quantity': 2,
      'list_on_marketplace': false,
      'is_sold': true,
    },
  );
  final pid = (tryJson(p) as List).first['id'].toString();
  final ord = await rest(
    c.url,
    'POST',
    'orders',
    headers: c.buyerH,
    body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'price_total': 6.0,
      'status': 'reserva_pendente',
      'quantity': 1,
      'shipping_method': 'Entrega em Mão (€0.00)',
    },
  );
  if (!looksOk(ord)) {
    stderr.writeln('order fail ${brief(ord, 400)}');
    exit(1);
  }
  final oid = (tryJson(ord) as List).first['id'].toString();
  final pay = await edge(
    c.url,
    'create-payment-intent',
    anon: c.anon,
    jwt: c.buyerJwt,
    body: {
      'buyer_id': c.buyerId,
      'order_id': oid,
      'shipping_method': 'Entrega em Mão (€0.00)',
      'currency': 'eur',
    },
  );
  await dumpJson(
    'tool/redteam_blind_e_orbita_20260830T1810/out/pay_dead.json',
    {
      'order_id': oid,
      'product_id': pid,
      'status_code': pay.statusCode,
      'body': tryJson(pay),
    },
  );
  stdout.writeln('wrote pay_dead.json order=$oid http=${pay.statusCode}');
}
