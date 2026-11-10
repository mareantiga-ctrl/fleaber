/// RED TEAM CEGO DK — confirm C3 refund stock (pago, sem enviado). Não corrige.
import 'dart:convert';
import 'dart:io';
import '_rtdk.dart';

void main() async {
  final c = Rtdk.fromEnv(loadEnv());
  await c.loginActors();

  final paid = await c.payToPago(lens: 'DK5', initialQty: 1);
  if (paid == null) throw StateError('setup_paid_order');
  final before = await c.productRow(paid.pid);
  final row0 = await c.orderRow(paid.oid);
  final w0 = await c.wallets();

  final rf1 = await c.refund(paid.oid, jwt: c.sellerJwt);
  final mid = await c.productRow(paid.pid);
  final row1 = await c.orderRow(paid.oid);
  final w1 = await c.wallets();

  final rf2 = await c.refund(paid.oid, jwt: c.sellerJwt);
  final after = await c.productRow(paid.pid);
  final row2 = await c.orderRow(paid.oid);
  final w2 = await c.wallets();

  final q0 = numOf(before?['quantity'])?.round();
  final q1 = numOf(mid?['quantity'])?.round();
  final q2 = numOf(after?['quantity'])?.round();
  final dS1 = (w1['seller'] ?? 0) - (w0['seller'] ?? 0);
  final dS2 = (w2['seller'] ?? 0) - (w1['seller'] ?? 0);
  final dB1 = (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0);

  final doubled = (q2 ?? -1) > (q1 ?? 0);
  final restoredOnce = (q0 ?? -1) == 0 && (q1 ?? -1) == 1;
  final held = doubled || ((q1 ?? 0) > 1);

  if (held) {
    c.hold(
      id: 'DK-C3.refund_stock_x2',
      lens: 'DK5',
      severity: 'P0',
      title: 'refund duplica ou infla stock',
      actor: 'seller JWT refund-order',
      pre: 'Stripe TEST pago (não enviado) qty produto 0',
      repro: 'refund-order ×2',
      expected: 'qty 0→1→1',
      obtained: 'qty $q0→$q1→$q2 rf1=${rf1.brief} rf2=${rf2.brief}',
    );
    c.probe(
      id: 'DK-C3.refund_stock_x2',
      matrix: 'DK-C',
      payload: 'refund-order ×2 em pago (não enviado)',
      http: '${rf1.brief} || ${rf2.brief}',
      bd: 'qty $q0→$q1→$q2 st ${row0?['status']}→${row1?['status']}→${row2?['status']} '
          'refund_id=${row1?['stripe_refund_id']} Δs1=$dS1 Δs2=$dS2 Δb1=$dB1',
      result: 'HOLD',
    );
  } else {
    c.block('DK-C3.refund_stock_x2', 'DK5', 'refund stock +1 não ×2', {
      'qty': '$q0→$q1→$q2',
      'restoredOnce': restoredOnce,
      'rf1': rf1.brief,
      'rf2': rf2.brief,
      'refund_id': row1?['stripe_refund_id'],
      'dS1': dS1,
      'dS2': dS2,
      'dB1': dB1,
    });
    c.probe(
      id: 'DK-C3.refund_stock_x2',
      matrix: 'DK-C',
      payload: 'refund-order ×2 em pago (não enviado)',
      http: '${rf1.brief} || ${rf2.brief}',
      bd: 'qty $q0→$q1→$q2 st ${row0?['status']}→${row1?['status']}→${row2?['status']} '
          'refund_id=${row1?['stripe_refund_id']} Δs1=$dS1 Δs2=$dS2 Δb1=$dB1',
      result: 'FAIL',
    );
  }

  // Extra: PATCH wallet_release_processed_at JWT
  final paid2 = await c.payToPago(lens: 'DK3', initialQty: 1);
  if (paid2 != null) {
    final wr = await c.patchOrder(paid2.oid, {
      'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
    }, jwt: c.buyerJwt);
    final wrRow = await c.orderRow(paid2.oid);
    final wrHeld = wrRow?['wallet_release_processed_at'] != null;
    if (wrHeld) {
      c.hold(
        id: 'DK-B1d.patch_wallet_release_flag',
        lens: 'DK3',
        severity: 'P0',
        title: 'buyer PATCH wallet_release_processed_at',
        actor: 'buyer JWT',
        pre: 'order paga',
        repro: 'PATCH wallet_release_processed_at',
        expected: '42501 immutable / BD null',
        obtained: wr.brief,
      );
      c.probe(
        id: 'DK-B1d.patch_wallet_release_flag',
        matrix: 'DK-B',
        payload: 'B1 PATCH wallet_release_processed_at',
        http: wr.brief,
        bd: 'flag=${wrRow?['wallet_release_processed_at']}',
        result: 'HOLD',
      );
    } else {
      c.block('DK-B1d.patch_wallet_release_flag', 'DK3',
          'wallet release flag immutable', wr);
      c.probe(
        id: 'DK-B1d.patch_wallet_release_flag',
        matrix: 'DK-B',
        payload: 'B1 PATCH wallet_release_processed_at',
        http: wr.brief,
        bd: 'flag=${wrRow?['wallet_release_processed_at']}',
        result: 'FAIL',
      );
    }
  }

  await c.dumpAll('confirm_c3.json');
  stdout.writeln(jsonEncode({
    'c3': {
      'qty': '$q0→$q1→$q2',
      'rf1': rf1.brief,
      'rf2': rf2.brief,
      'held': held,
    },
    'findings': c.findings.map((f) => f['id']).toList(),
    'probes': c.probes.length,
  }));
}
