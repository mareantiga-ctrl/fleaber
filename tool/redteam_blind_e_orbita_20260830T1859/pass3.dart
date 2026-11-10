/// Blind E — Pass 3: estado final após captura TEST saco unlist.
import 'dart:io';

import '_http.dart';

Future<void> main() async {
  final c = await boot();
  const oid = '25be8a2d-281a-4d43-80ab-1defa3619d9f';
  const pid = '4f1dfa03-a189-4dcb-a8e1-0630899a7f5b';
  const sid = 'cs_test_a1w6QyEcJvK5Pfk9PDluQ2LFfxvPnLriefHnZHBZW6UbUzCCfVf9ccgNP2';

  final order = await c.select(
    'orders',
    service: true,
    select:
        'id,status,quantity,price_total,amount_paid_cents,stripe_checkout_session_id,stripe_payment_intent_id,stripe_refund_id,stock_units_applied,shipping_method',
    filter: 'id=eq.$oid',
    limit: 1,
  );
  final product = await c.select(
    'products',
    service: true,
    select: 'id,quantity,is_sold,list_on_marketplace,title,price',
    filter: 'id=eq.$pid',
    limit: 1,
  );
  final wallet = await c.select(
    'wallets',
    service: true,
    select: 'id,balance',
    filter: 'id=eq.${c.sellerId}',
    limit: 1,
  );
  final ev = await c.select(
    'stripe_checkout_events',
    service: true,
    select: 'event,created_at,order_id,session_id',
    filter: 'order_id=eq.$oid',
    limit: 20,
  );
  // some schemas use different col names
  final ev2 = await c.rest(
    'GET',
    '/rest/v1/stripe_checkout_events?order_id=eq.$oid&select=*&limit=15&order=created_at.desc',
    service: true,
  );
  final ev3 = await c.rest(
    'GET',
    '/rest/v1/stripe_checkout_events?select=*&session_id=eq.$sid&limit=10',
    service: true,
  );

  await writeOut('pass3_after_pay.json', {
    'order_http': order.status,
    'order': order.snippet,
    'product_http': product.status,
    'product': product.snippet,
    'wallet': wallet.snippet,
    'events_filter': ev.snippet,
    'events_star': ev2.snippet,
    'events_by_sid': ev3.snippet,
  });
  stdout.writeln('ORDER ${order.snippet}');
  stdout.writeln('PRODUCT ${product.snippet}');
  stdout.writeln('WALLET ${wallet.snippet}');
}
