/// BR pass2b — oráculo desconto tier vs P0 9+9.
import 'dart:io';

import '_rtbr.dart';

Future<void> main() async {
  final c = Rtbr.fromEnv(loadEnv());
  await c.loginActors();
  final d = await c.rest(
    'GET',
    'seller_bundle_discounts?seller_id=eq.${c.sellerId}&select=*',
    service: true,
  );
  stdout.writeln('discounts ${d.brief}');
  await dumpJson('${outDir()}/pass2b_discounts.json', {
    'seller': c.sellerId,
    'hit': d.brief,
    'json': d.json,
  });

  // 1 linha 9€ deve ser 1010; 3 linhas para ver tier
  final p1 = await c.createProduct(price: 9, qty: 3, title: '$prefix-t1');
  final p2 = await c.createProduct(price: 9, qty: 3, title: '$prefix-t2');
  final p3 = await c.createProduct(price: 9, qty: 3, title: '$prefix-t3');
  final o1 = await c.insertOrder(productId: p1!, jwt: c.buyerJwt, price: 9);
  final single = await c.checkout(orderId: o1!);
  final o2 = await c.insertOrder(productId: p2!, jwt: c.buyerJwt, price: 9);
  final o3 = await c.insertOrder(productId: p3!, jwt: c.buyerJwt, price: 9);
  final bag2 = await c.checkoutBag(lines: [
    {'order_id': o1, 'product_id': p1},
    {'order_id': o2, 'product_id': p2},
  ]);
  final bag3 = await c.checkoutBag(lines: [
    {'order_id': o1, 'product_id': p1},
    {'order_id': o2, 'product_id': p2},
    {'order_id': o3!, 'product_id': p3},
  ]);
  stdout.writeln('single9 amt=${single.amountTotal} expect=${expectedQuoteCents(unitEur: 9)}');
  stdout.writeln('bag2 amt=${bag2.amountTotal}');
  stdout.writeln('bag3 amt=${bag3.amountTotal}');
  await dumpJson('${outDir()}/pass2b_quotes.json', {
    'single': {'amt': single.amountTotal, 'map': single.map},
    'bag2': {'amt': bag2.amountTotal, 'map': bag2.map},
    'bag3': {'amt': bag3.amountTotal, 'map': bag3.map},
    'expect_single': expectedQuoteCents(unitEur: 9),
    'expect_2_no_disc': 1800 + protectionFeeCents(1800, 0),
    'expect_2_10pct': 1620 + protectionFeeCents(1620, 0),
    'expect_3_no_disc': 2700 + protectionFeeCents(2700, 0),
  });
}
