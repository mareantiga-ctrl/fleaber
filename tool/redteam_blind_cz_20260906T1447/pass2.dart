import '_rtcz.dart';

/// Pass 2 — CZ-C2 buyer refund seller-only · CZ-C3 release∥refund race
void main() async {
  final c = Rtcz.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureSeller2();

  Future<({String oid, String pid, String? pi})> mustPay(String lens) async {
    final paid = await c.payToPago(lens: lens);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  final pBuyer = await mustPay('CZ5');
  final balS0 = await c.walletBal(c.sellerId);
  final buyerRefund = await c.refundOrder(pBuyer.oid, jwt: c.buyerJwt);
  final rowAfterBuyer = await c.orderRow(pBuyer.oid);
  final balS1 = await c.walletBal(c.sellerId);
  final buyerDidRefund = buyerRefund.ok &&
      buyerRefund.map?['ok'] == true &&
      buyerRefund.map?['skipped'] != true &&
      (rowAfterBuyer?['stripe_refund_id'] != null &&
          '${rowAfterBuyer?['stripe_refund_id']}'.isNotEmpty);
  c.probe(
    id: 'CZ-C2-BUYER-REFUND',
    lens: 'CZ5',
    payload: 'POST refund-order JWT comprador order=${pBuyer.oid}',
    httpBd:
        '${buyerRefund.brief} refund_id=${rowAfterBuyer?['stripe_refund_id']} Δseller=${balS1 - balS0}',
    result: buyerDidRefund ? 'FAIL' : 'HOLD',
  );
  if (buyerDidRefund) {
    c.hold(
      id: 'CZ-P0-BUYER-REFUND',
      lens: 'CZ5',
      severity: 'P0',
      title: 'buyer refund-order anulou Stripe da venda',
      actor: 'buyer JWT',
      pre: 'Edge exige user.id === seller_id',
      repro: 'POST refund-order {order_id} JWT comprador',
      expected: '403 Sem permissão',
      obtained: buyerRefund.brief,
    );
  } else {
    c.block('refund.buyer', 'CZ5', 'buyer refund-order recusado (seller-only)',
        buyerRefund);
  }

  final pRace = await mustPay('CZ5');
  final balC0 = await c.walletBal(c.sellerId);
  final raced = await Future.wait([
    c.refundOrder(pRace.oid, jwt: c.sellerJwt),
    c.tryRelease(pRace.oid, jwt: c.buyerJwt),
    c.tryRelease(pRace.oid, jwt: c.sellerJwt),
  ]);
  final balC1 = await c.walletBal(c.sellerId);
  final refunded = raced[0].ok &&
      raced[0].map?['ok'] == true &&
      raced[0].map?['skipped'] != true;
  final released = raced[1].json == true || raced[2].json == true;
  final raceOpen = refunded && released && (balC1 - balC0) > 0;
  c.probe(
    id: 'CZ-C3-REL-REFUND-RACE',
    lens: 'CZ5',
    payload: 'Future.wait refund-order + release em pago',
    httpBd:
        'refunded=$refunded released=$released Δ=${balC1 - balC0} hits=${raced.map((h) => h.brief).toList()}',
    result: raceOpen ? 'FAIL' : 'HOLD',
  );
  if (raceOpen) {
    c.hold(
      id: 'CZ-P0-REL-REFUND-RACE',
      lens: 'CZ5',
      severity: 'P0',
      title: 'race refund∥release em pago: Stripe refund + crédito wallet',
      actor: 'seller refund + buyer release paralelo',
      pre: 'release inelegível em pago; refund seller-only',
      repro: 'Future.wait refund-order + release no pago',
      expected: 'refund OU nada; release false; sem crédito extra',
      obtained: {
        'hits': raced.map((h) => h.brief).toList(),
        'delta': balC1 - balC0,
      },
    );
  } else {
    c.block('race.rel.refund', 'CZ5', 'race pago sem crédito+refund simultâneo', {
      'refunded': refunded,
      'released': released,
      'delta': balC1 - balC0,
    });
  }

  await c.dumpAll('pass2.json');
}
