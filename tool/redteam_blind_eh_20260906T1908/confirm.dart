/// Confirm EH B1/B2/B3/A7-notes on clean mutex (buyer2 + buyer1 after clear).
/// Not a product patch. Staging only.
import 'dart:convert';
import 'dart:io';

import '_rteh.dart';

Future<void> main() async {
  final c = Rteh.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();

  // Fixture restore: mutex leftover from this pass / prior packs.
  await c.rest(
    'DELETE',
    'batata_checkout_mutex?buyer_id=eq.${c.buyerId}',
    service: true,
    prefer: 'return=minimal',
  );
  await c.rest(
    'DELETE',
    'batata_checkout_mutex?buyer_id=eq.${c.buyer2Id}',
    service: true,
    prefer: 'return=minimal',
  );
  await c.cancelOrders(c.createdOrderIds);

  final out = <String, Object?>{};

  Future<Map<String, Object?>> appOnce({
    required String tag,
    required String payment,
    required String jwt,
    required String buyer,
    Map<String, Object?> extra = const {},
  }) async {
    final pid = await c.createProduct(title: '$prefix-cf-$tag');
    if (pid == null) return {'tag': tag, 'err': 'no pid'};
    final oid = await c.insertOrder(
      productId: pid,
      payment: payment,
      jwt: jwt,
      buyer: buyer,
    );
    if (oid == null) return {'tag': tag, 'err': 'no oid', 'pid': pid};
    final sql = await c.sqlOffBool(payment);
    final cpi = await c.cpiOnce(
      () => c.checkout(
        orderId: oid,
        productId: pid,
        jwt: jwt,
        buyer: buyer,
        extra: extra,
      ),
    );
    final row = await c.orderRow(oid);
    return {
      'tag': tag,
      'payment': payment,
      'sql': sql,
      'cpi': cpi.brief,
      'sid': sidOf(cpi, row),
      'opened': opened(cpi),
      'off': offDenied(cpi),
      'contention': cpi.body.toLowerCase().contains('contention'),
      'pm': row?['payment_method'],
    };
  }

  out['b2_app'] = await appOnce(
    tag: 'b2-app',
    payment: 'Pagamento na App',
    jwt: c.buyer2Jwt!,
    buyer: c.buyer2Id!,
  );
  out['b2_card'] = await appOnce(
    tag: 'b2-card',
    payment: 'card',
    jwt: c.buyer2Jwt!,
    buyer: c.buyer2Id!,
  );
  out['b2_apple'] = await appOnce(
    tag: 'b2-apple',
    payment: 'applepay',
    jwt: c.buyer2Jwt!,
    buyer: c.buyer2Id!,
  );
  out['b2_google'] = await appOnce(
    tag: 'b2-google',
    payment: 'googlepay',
    jwt: c.buyer2Jwt!,
    buyer: c.buyer2Id!,
  );
  out['b2_notes'] = await appOnce(
    tag: 'b2-notes',
    payment: 'Pagamento na App',
    jwt: c.buyer2Jwt!,
    buyer: c.buyer2Id!,
    extra: {
      'notes': 'paga por ifthenpay entidade 11234',
      'payment_method': 'ifthenpay',
    },
  );

  out['b1_app'] = await appOnce(
    tag: 'b1-app',
    payment: 'Pagamento na App',
    jwt: c.buyerJwt!,
    buyer: c.buyerId!,
  );
  out['b1_card'] = await appOnce(
    tag: 'b1-card',
    payment: 'card',
    jwt: c.buyerJwt!,
    buyer: c.buyerId!,
  );
  out['b1_apple'] = await appOnce(
    tag: 'b1-apple',
    payment: 'applepay',
    jwt: c.buyerJwt!,
    buyer: c.buyerId!,
  );

  await c.cancelOrders(c.createdOrderIds);
  await dumpJson('${outDir()}/confirm.json', {
    'auditor': 'REDTEAM_BLIND_EH_PAYMETHOD_POS_OPEN_v1',
    'prefix': prefix,
    'confirm': out,
  });
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
}
