/// Confirm B5: release∥disputa — estado actual, refund gate, clawback.
import 'dart:convert';
import 'dart:io';
import '_rtdw.dart';

Future<void> main() async {
  final c = Rtdw.fromEnv(loadEnv());
  await c.loginActors();
  const oid = 'ff0851b9-3378-43d9-a894-742e72c8aa69';
  const did = '6bc94bed-1ba0-487a-b36c-574716973292';
  final s1 = c.sellerId!;

  final order = await c.orderRow(oid);
  final disp = await c.rest(
    'GET',
    'order_disputes?id=eq.$did&select=id,order_id,buyer_id,status,reason,created_at',
    service: true,
  );
  final txns = await c.walletTxns(s1, limit: 12);
  final related = txns.where((t) => '${t['order_id']}' == oid).toList();
  final bal = await c.walletBal(s1);

  final refSeller = await c.refundOrder(oid, jwt: c.sellerJwt);
  final refBuyer = await c.refundOrder(oid, jwt: c.buyerJwt);
  final relAgain = await c.tryRelease(oid, jwt: c.buyerJwt);
  final partial = await c.rpc('batata_process_partial_refund_dispute', {
    'p_dispute_id': did,
    'p_percent': 100,
  }, jwt: c.buyerJwt);
  final partialS = await c.rpc('batata_process_partial_refund_dispute', {
    'p_dispute_id': did,
    'p_percent': 100,
  }, jwt: c.sellerJwt);

  final order2 = await c.orderRow(oid);
  final bal2 = await c.walletBal(s1);

  final out = {
    'order': order,
    'order_after': order2,
    'dispute': disp.map ?? disp.brief,
    'wallet_txns_this_order': related,
    'balance_now': bal,
    'balance_after_attempts': bal2,
    'refund_seller': refSeller.brief,
    'refund_buyer': refBuyer.brief,
    'release_again': relAgain.brief,
    'partial_buyer': partial.brief,
    'partial_seller': partialS.brief,
  };
  await dumpJson('${outDir()}/confirm_b5.json', out);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'status': order?['status'],
    'release_at': order?['wallet_release_processed_at'],
    'refund_at': order?['wallet_refund_processed_at'],
    'pi': order?['stripe_payment_intent_id'],
    'stripe_refund': order?['stripe_refund_id'],
    'disp': disp.brief,
    'txns': related,
    'bal': bal,
    'refS': refSeller.brief,
    'refB': refBuyer.brief,
    'rel2': relAgain.brief,
    'partialB': partial.brief,
    'partialS': partialS.brief,
    'dBal': bal2 - bal,
  }));
}
