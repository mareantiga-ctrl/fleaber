/// Observação Stripe/wallets do P0 — service_role só observe.
import 'dart:io';
import '_rtt.dart';

Future<void> main() async {
  final c = Rtt.fromEnv(loadEnv());
  await c.loginActors();
  const oid = 'a8e51373-dc2f-4d0b-9057-3f4add003bff';
  const pi = 'pi_3UAmhrH7FWYUN3jh0tc1WYIM';
  const oidB = 'f7914a3f-d7a7-450c-a8f7-1ae1baed2c8a';
  const piB = 'pi_3UAmhwH7FWYUN3jh0vmw4rjC';

  final oA = await c.orderRow(oid);
  final oB = await c.orderRow(oidB);
  final txA = await c.walletTxns(orderId: oid, limit: 10);
  final txB = await c.walletTxns(orderId: oidB, limit: 10);
  final stA = await c.e2e('list_stripe_refunds', {
    'payment_intent_id': pi,
    'order_id': oid,
  });
  final stB = await c.e2e('list_stripe_refunds', {
    'payment_intent_id': piB,
    'order_id': oidB,
  });
  final w = await c.wallets();
  await dumpJson('${outDir()}/observe_p0.json', {
    'order_a': oA,
    'order_b': oB,
    'tx_a': txA,
    'tx_b': txB,
    'stripe_a': stA.json,
    'stripe_b': stB.json,
    'wallets': w,
  });
  stdout.writeln('A ${oA?['status']} refund=${oA?['stripe_refund_id']} wr=${oA?['wallet_refund_processed_at']}');
  stdout.writeln('stripeA ${stA.brief}');
  stdout.writeln('B ${oB?['status']} refund=${oB?['stripe_refund_id']}');
  stdout.writeln('stripeB ${stB.brief}');
  stdout.writeln('wallets $w');
  stdout.writeln('txA ${clip(txA, 800)}');
}
