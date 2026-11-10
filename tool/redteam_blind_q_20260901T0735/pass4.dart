/// Confirm accounting on P0 order + label persist. Observation only.
import 'dart:io';

import '_rtq.dart';

void main() async {
  final env = loadEnv();
  final c = Rtq.fromEnv(env);
  await c.loginActors();

  const oid = 'fe8256e6-a1eb-418b-a97f-1184c7e42b08';
  const didClosed = '1673ab1f-f565-4c5d-b585-b83251a7eaef';
  const didRace = '33773d4b-dd8a-446c-85b1-5743c7c0884e';
  const hijackRes = 'b1de1706-437f-40be-a2a2-e5625f058d40';
  const victimProd = '26f9ce2f-d306-4303-a19f-41b6e3221382';

  final o = await c.orderRow(oid);
  final w = await c.wallets();
  final tx = await c.walletTxns(orderId: oid);
  final dClosed = await c.disputeRow(didClosed);
  final dRace = await c.disputeRow(didRace);
  final res = await c.reservationRow(hijackRes);
  final prod = await c.productRow(victimProd);

  // Buyer tries checkout of victim SKU (hijack composition).
  final pay = await c.edge('create-payment-intent', {
    'product_id': victimProd,
    'quantity': 1,
  }, jwt: c.buyerJwt);

  await dumpJson('${outDir()}/pass4.json', {
    'order_p0': o,
    'wallets': w,
    'txns': tx,
    'dispute_closed': dClosed,
    'dispute_recusada': dRace,
    'hijack_res': res,
    'victim_product': prod,
    'create_payment_victim_sku': pay.brief,
  });
  stdout.writeln('order ${o?['status']} rf=${o?['stripe_refund_id']} wr=${o?['wallet_refund_processed_at']}');
  stdout.writeln('wallets $w');
  stdout.writeln('label=${dClosed?['return_label_url']}');
  stdout.writeln('recusada=${dRace?['status']}');
  stdout.writeln('pay ${pay.brief}');
  exit(0);
}
