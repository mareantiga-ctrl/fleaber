import '_rtcn.dart';

/// Pass 2 — CN-D release∥refund · partial refund→release · buyer 403 · seller2 alheio
void main() async {
  final c = Rtcn.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureSeller2();

  Future<({String oid, String pid, String? pi})> mustPay(String lens) async {
    final paid = await c.payToPago(lens: lens);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  // CN-D buyer refund 403
  final pBuyer = await mustPay('CN6');
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
    id: 'CN-D-BUYER-REFUND',
    lens: 'CN6',
    payload: 'POST refund-order JWT comprador order=${pBuyer.oid}',
    httpBd:
        '${buyerRefund.brief} refund_id=${rowAfterBuyer?['stripe_refund_id']} Δseller=${balS1 - balS0}',
    result: buyerDidRefund ? 'FAIL' : 'HOLD',
  );
  if (buyerDidRefund) {
    c.hold(
      id: 'CN-P0-BUYER-REFUND',
      lens: 'CN6',
      severity: 'P0',
      title: 'buyer refund-order anulou Stripe da venda',
      actor: 'buyer JWT',
      pre: 'Edge exige user.id === seller_id',
      repro: 'POST refund-order {order_id} JWT comprador',
      expected: '403 Sem permissão',
      obtained: buyerRefund.brief,
    );
  } else {
    c.block('refund.buyer', 'CN6', 'buyer refund-order recusado (seller-only)',
        buyerRefund);
  }

  // CN-D seller2 refund alheio
  final pX = await mustPay('CN6');
  final s2ref = await c.refundOrder(pX.oid, jwt: c.seller2Jwt);
  final s2Open = s2ref.ok && s2ref.map?['ok'] == true && s2ref.map?['skipped'] != true;
  c.probe(
    id: 'CN-D-S2-REFUND',
    lens: 'CN6',
    payload: 'POST refund-order order seller1 JWT seller2',
    httpBd: s2ref.brief,
    result: s2Open ? 'FAIL' : 'HOLD',
  );
  await c.expectDenied(
    id: 'CN-P0-S2-REFUND',
    lens: 'CN6',
    title: 'seller2 refund-order da venda do seller1',
    hit: s2ref,
    actor: 'seller2 JWT',
    pre: 'só o seller da encomenda',
    repro: 'POST refund-order order seller1, JWT seller2',
    severityIfOpen: 'P0',
    openIf: (h) => h.ok && h.map?['ok'] == true && h.map?['skipped'] != true,
  );

  // CN-D release∥refund race em pago
  final pRace = await mustPay('CN3');
  final balC0 = await c.walletBal(c.sellerId);
  final raced = await Future.wait([
    c.refundOrder(pRace.oid, jwt: c.sellerJwt),
    c.tryRelease(pRace.oid, jwt: c.buyerJwt),
    c.tryRelease(pRace.oid, jwt: c.sellerJwt),
  ]);
  final balC1 = await c.walletBal(c.sellerId);
  final rowRace = await c.orderRow(pRace.oid);
  final refunded = raced[0].ok &&
      raced[0].map?['ok'] == true &&
      raced[0].map?['skipped'] != true;
  final released = raced[1].json == true || raced[2].json == true;
  final raceOpen = refunded && released && (balC1 - balC0) > 0;
  c.probe(
    id: 'CN-D-REL-REFUND-RACE',
    lens: 'CN3',
    payload: 'Future.wait refund-order + release em pago',
    httpBd:
        'refunded=$refunded released=$released Δ=${balC1 - balC0} hits=${raced.map((h) => h.brief).toList()}',
    result: raceOpen ? 'FAIL' : 'HOLD',
  );
  if (raceOpen) {
    c.hold(
      id: 'CN-P0-REL-REFUND-RACE',
      lens: 'CN3',
      severity: 'P0',
      title: 'race refund∥release em pago: Stripe refund + crédito wallet',
      actor: 'seller refund + buyer release paralelo',
      pre: 'release inelegível em pago; refund seller-only',
      repro: 'Future.wait refund-order + release no pago',
      expected: 'refund OU nada; release false; sem crédito extra',
      obtained: {
        'hits': raced.map((h) => h.brief).toList(),
        'delta': balC1 - balC0,
        'order': rowRace,
      },
    );
  } else {
    c.block('race.rel.refund', 'CN3', 'race pago sem crédito+refund simultâneo', {
      'refunded': refunded,
      'released': released,
      'delta': balC1 - balC0,
    });
  }

  // CN-D partial refund (body amount) → then ship/concluido/release
  final pPart = await mustPay('CN3');
  final rowPaid0 = await c.orderRow(pPart.oid);
  final paidCents = (numOf(rowPaid0?['amount_paid_cents']) ?? 0).round();
  final partial = await c.refundOrder(pPart.oid, extraBody: {
    'amount': 100,
    'amount_cents': 100,
    'refund_amount': 100,
    'partial': true,
  }, jwt: c.sellerJwt);
  final rowPart = await c.orderRow(pPart.oid);
  final claimed = (numOf(partial.map?['amount_cents']) ?? 0).round();
  final ship = await c.patchOrder(pPart.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final concl = await c.patchOrder(pPart.oid, {'status': 'concluido'}, jwt: c.buyerJwt);
  final balP0 = await c.walletBal(c.sellerId);
  final relAfter = await c.tryRelease(pPart.oid, jwt: c.buyerJwt);
  final balP1 = await c.walletBal(c.sellerId);
  final rowAfterRel = await c.orderRow(pPart.oid);
  final credited = (balP1 - balP0) > 0.009 && relAfter.json == true;
  final overCap = partial.ok &&
      partial.map?['ok'] == true &&
      claimed > paidCents &&
      paidCents > 0;
  c.probe(
    id: 'CN-D-PARTIAL-THEN-RELEASE',
    lens: 'CN3',
    payload: 'refund-order amount=100 depois enviado→concluido→release',
    httpBd:
        'refund=${partial.brief} claimed=$claimed paid=$paidCents ship=${ship.brief} concl=${concl.brief} rel=${relAfter.brief} Δ=${balP1 - balP0} refund_id=${rowAfterRel?['stripe_refund_id']}',
    result: (credited || overCap) ? 'FAIL' : 'HOLD',
  );
  if (overCap) {
    c.hold(
      id: 'CN-P0-REFUND-GT-CAPTURE',
      lens: 'CN3',
      severity: 'P0',
      title: 'refund-order body amount > captura',
      actor: 'seller JWT',
      pre: 'amount da ordem/PI residual, não do body',
      repro: 'POST refund-order {amount:100} vs paid=$paidCents',
      expected: 'refund ≤ amount_paid_cents',
      obtained: {'hit': partial.brief, 'paid': paidCents, 'claimed': claimed},
    );
  }
  if (credited) {
    c.hold(
      id: 'CN-P0-PARTIAL-THEN-RELEASE',
      lens: 'CN3',
      severity: 'P0',
      title: 'após refund (parcial ou total) o release creditou wallet',
      actor: 'seller refund + buyer release',
      pre: 'release vê stripe_refund_id e não minta',
      repro: 'refund-order amount=100; enviado; concluido; release',
      expected: 'release false, Δ=0 se já há refund Stripe',
      obtained: {
        'refund': partial.brief,
        'claimed': claimed,
        'paid': paidCents,
        'rel': relAfter.brief,
        'delta': balP1 - balP0,
        'order': rowAfterRel,
      },
    );
  } else {
    c.block('partial.then.release', 'CN3',
        'release pós-refund não creditou (claimed=$claimed paid=$paidCents)', {
      'refund': partial.brief,
      'rel': relAfter.brief,
      'delta': balP1 - balP0,
    });
  }

  await c.dumpAll('pass2.json');
}
