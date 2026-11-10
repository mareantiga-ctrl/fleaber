/// ED pass2 — D1 pago 4242 + settle coerente (e2e settle_get_replay falhou sem PI na Session).
/// Staging only. NÃO corrigir.
import 'dart:io';
import '_rted.dart';

void main() async {
  final c = Rted.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  final s1 = c.sellerId!;
  final b2 = c.buyer2Id!;

  final paid = await c.payToPago(lens: 'ED7', buyer: b2);
  if (paid == null) {
    c.skip('D1', 'ED7', 'setup_paid_order falhou', paid);
    await c.dumpAll('pass2.json');
    return;
  }
  final row0 = await c.orderRow(paid.oid);
  final w0 = await c.walletBal(s1);
  final amt0 = numOf(row0?['amount_paid_cents']) ?? 0;

  final settleMissing = await c.settleGet(
    'cs_test_rted_d1_no_session',
    extraQs: 'order_id=${paid.oid}',
  );
  final settlePi = await c.settleGet(
    paid.pi ?? 'pi_rted_none',
    extraQs: 'order_id=${paid.oid}',
  );
  final fase2 = await c.fase2SettleBuyer(
    orderId: paid.oid,
    paymentIntentId: paid.pi ?? '',
    productId: paid.pid,
    jwt: c.buyer2Jwt,
  );

  final row1 = await c.orderRow(paid.oid);
  final w1 = await c.walletBal(s1);
  final amt1 = numOf(row1?['amount_paid_cents']) ?? 0;
  final refunded = '${row1?['stripe_refund_id'] ?? ''}'.isNotEmpty;
  final minted = (w1 - w0) > 0;
  final doubled = amt1 > amt0 && amt0 > 0;
  final stillPago = c.orderPaid(row1);
  final isPago = stillPago && '${row1?['stripe_payment_intent_id'] ?? paid.pi}'.startsWith('pi_');
  final bad = !isPago || refunded || minted || doubled || fase2.ok;

  c.probe(
    id: 'D1',
    edgeRpc: 'setup_paid_order + GET settle + fase2 JWT',
    payload:
        'PI 4242 pago ${paid.oid}; GET settle cs_morta + pi_ como session; POST fase2_e2e_settle JWT B2',
    http: {
      'missing': settleMissing.brief,
      'pi_as_sid': settlePi.brief,
      'fase2': fase2.brief,
    },
    stripeBd: {
      'oid': paid.oid,
      'pi': paid.pi ?? row1?['stripe_payment_intent_id'],
      'status0': row0?['status'],
      'status1': row1?['status'],
      'amount0': amt0,
      'amount1': amt1,
      'refund_id': row1?['stripe_refund_id'],
      'delta_wallet': w1 - w0,
      'fase2_status': fase2.status,
    },
    result: bad ? 'FAIL' : 'HOLD',
    lens: 'ED7',
    countFinding: bad,
    classeNova: true,
  );
  if (bad) {
    c.hold(
      id: 'ED-P0-D1-SETTLE-PAID',
      lens: 'ED7',
      severity: 'P0',
      title: 'settle pós-pago 4242 refund/duplicou/fase2 JWT',
      actor: 'B2 JWT + anon GET',
      pre: 'order já pago; GET settle / fase2 JWT não devem alterar caixa',
      repro: 'setup_paid_order; GET settle; POST fase2 JWT',
      expected: 'pago inalterado; refund vazio; Δwallet 0; fase2 401',
      obtained: {
        'row0': row0,
        'row1': row1,
        'delta': w1 - w0,
        'fase2': fase2.brief,
      },
    );
  } else {
    c.block('D1.pago', 'ED7', 'pago 4242; settle extra sem mint/refund; fase2 JWT 401', {
      'pi': paid.pi,
      'status': row1?['status'],
      'amount': amt1,
      'delta': w1 - w0,
      'fase2': fase2.status,
    });
  }

  await c.dumpAll('pass2.json');
  stdout.writeln(
    'ED PASS2 D1=${c.probes.last['result']} findings=${c.findings.where((f) => f['count'] == true).length}',
  );
}
