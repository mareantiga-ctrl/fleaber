/// Observe E6 capture on order 3b63916a after Stripe TEST pay.
import 'dart:io';

import '_http.dart';

Future<void> main() async {
  final c = await boot();
  const oid = '3b63916a-c241-4ecd-9283-9bb07d01a800';
  const pid = '35dd8125-872f-4440-8ed7-25da64f5d84d';
  final o = await rest(
    c.url,
    'GET',
    'orders',
    headers: c.svcH,
    qs:
        'id=eq.$oid&select=id,status,price_total,stripe_checkout_session_id,stripe_payment_intent_id,stripe_refund_id,quantity,product_id',
  );
  final p = await rest(
    c.url,
    'GET',
    'products',
    headers: c.svcH,
    qs: 'id=eq.$pid&select=id,quantity,is_sold,list_on_marketplace,title',
  );
  final w = await rest(
    c.url,
    'GET',
    'wallets',
    headers: c.svcH,
    qs: 'id=eq.${c.sellerId}&select=id,balance',
  );
  await dumpJson(
    'tool/redteam_blind_e_orbita_20260830T1810/out/pay_dead_after.json',
    {
      'order': tryJson(o),
      'product': tryJson(p),
      'seller_wallet': tryJson(w),
    },
  );
  stdout.writeln('order=${brief(o, 400)}');
  stdout.writeln('product=${brief(p, 300)}');
  stdout.writeln('wallet=${brief(w, 200)}');
}
