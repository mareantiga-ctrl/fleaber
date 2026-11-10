import 'dart:io';

import '_rti4.dart';

Future<void> main() async {
  final c = Rti4(loadEnv());
  await c.boot();
  final liveId = '4d2efb5a-d520-4478-8d8d-1a2a0a92cc5c';
  final p = await c.insertProduct(listed: false, sold: false, qty: 1, price: 4.5);
  if (p == null) {
    stderr.writeln('no product');
    return;
  }
  final hold = await c.insertOrder(
    token: c.buyerJwt,
    productId: p['id'].toString(),
    liveId: liveId,
    shipping: 'Entrega em mão (€0.00)',
  );
  stdout.writeln('HOLD ${hold.brief}');
  if (!hold.ok || hold.list.isEmpty) {
    await c.dump('pass5');
    return;
  }
  final oid = (hold.list.first as Map)['id'].toString();
  final ck = await c.edge(
    'create-payment-intent',
    {
      'amount': 450,
      'currency': 'eur',
      'product_id': p['id'],
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'order_id': oid,
      'quantity': 1,
      'item_price': 450,
      'shipping': 0,
      'protection_fee': 65,
      'shipping_method': 'Entrega em mão (€0.00)',
      'live_id': liveId,
    },
    token: c.buyerJwt,
  );
  stdout.writeln('CK ${ck.brief}');
  final url = ck.map?['checkoutUrl']?.toString() ?? '';
  File('tool/redteam_blind_indep_$stamp/out/pass5_checkout_url.txt')
      .writeAsStringSync(url);
  stdout.writeln('URL_LEN=${url.length}');
  stdout.writeln('URL=$url');
  c.note('p5.session', 'fresh unlist live session', {
    'order': oid,
    'product': p['id'],
    'session': ck.map?['checkoutSessionId'],
    'url_len': url.length,
  }, well: '1');
  await c.dump('pass5');
}
