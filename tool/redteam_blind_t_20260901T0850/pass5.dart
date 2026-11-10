/// T8: refund-order Stripe depois do mint carteira no pedido P0 (status pago).
import 'dart:io';
import '_rtt.dart';

Future<void> main() async {
  final c = Rtt.fromEnv(loadEnv());
  await c.loginActors();
  const oid = 'a8e51373-dc2f-4d0b-9057-3f4add003bff';
  const pi = 'pi_3UAmhrH7FWYUN3jh0tc1WYIM';
  final w0 = await c.wallets();
  final o0 = await c.orderRow(oid);
  final rf = await c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt);
  final o1 = await c.orderRow(oid);
  final w1 = await c.wallets();
  final st = await c.e2e('list_stripe_refunds', {
    'payment_intent_id': pi,
    'order_id': oid,
  });
  final tx = await c.walletTxns(orderId: oid, limit: 15);
  c.note('T8.refund.after.mint', 'refund-order após mint carteira', {
    'rpc': rf.brief,
    'order_before': {
      'status': o0?['status'],
      'stripe_refund_id': o0?['stripe_refund_id'],
      'wallet_refund': o0?['wallet_refund_processed_at'],
    },
    'order_after': {
      'status': o1?['status'],
      'stripe_refund_id': o1?['stripe_refund_id'],
    },
    'wallets': {'before': w0, 'after': w1},
  }, lens: 'T8');
  if (rf.ok && '${o1?['stripe_refund_id'] ?? ''}'.isNotEmpty) {
    c.hold(
      id: 'T8-WALLET-THEN-STRIPE-REFUND',
      lens: 'T8',
      severity: 'P0',
      title:
          'Depois do mint carteira (parcial), refund-order em pago devolve Stripe — dinheiro duplicado',
      actor: 'seller JWT',
      pre: 'order pago; wallet_refund_processed_at set; PI capturado; stripe_refund_id vazio',
      repro: 'POST refund-order após batata_process_partial_refund_dispute',
      expected: 'recusar segundo canal ou clawback',
      obtained: {
        'edge': rf.json,
        'order': o1,
        'wallets_before': w0,
        'wallets_after': w1,
      },
      evidence: {'stripe': st.json, 'tx': tx},
    );
  } else {
    c.closed('T8.refund.after.mint', 'refund-order recusado após mint', rf.brief,
        lens: 'T8');
  }
  await dumpJson('${outDir()}/pass5.json', {
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'stripe': st.json,
    'order': o1,
    'wallets': w1,
    'tx': tx,
  });
  stdout.writeln(
      'PASS5 findings=${c.findings.length} stripe_refund=${o1?['stripe_refund_id']}');
}
