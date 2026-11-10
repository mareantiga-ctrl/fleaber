import '_rtch.dart';

/// Pass 2 — CH2 return POST · CH3 refund JWT / amount · CH3 release∥refund · CH6 actor
void main() async {
  final c = Rtch.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  Future<({String oid, String pid, String? pi})> mustPay(String lens) async {
    final paid = await c.payToPago(lens: lens);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  // --- CH2: POST onboarding web_return_origin hostil (não só GET) ---
  final wrOrigins = <String, String>{
    'idn': 'https://fle\u0430ber.pt', // cirílico a no host
    'ideo': 'https://fleaber\u3002pt',
    'js': 'javascript:https://fleaber.pt',
    'slashu': 'https://fleaber.pt\u2215evil.com',
    'nl': 'https://fleaber.pt\nLocation: https://evil.com',
    'pct00': 'https://fleaber.pt%00.evil.com',
    'evilpt': 'https://fleaber.pt.evil.pt',
    'localhostEvil': 'http://localhost.evil.com',
    'openredir': 'https://fleaber.pt/wallet?next=https://evil.com',
    'hashat': 'https://fleaber.pt#@evil.com',
  };
  for (final e in wrOrigins.entries) {
    final post = await c.connect({'web_return_origin': e.value});
    c.note('wr.post.${e.key}', 'POST origin ${e.value}', post.brief, lens: 'CH2');
    final url = '${post.map?['url'] ?? ''} ${post.location ?? ''}'.toLowerCase();
    final hostile = url.contains('evil') ||
        url.contains('javascript:') ||
        url.contains('%00') ||
        (url.contains('fle') && url.contains('ber.pt') && url.contains('xn--'));
    if (hostile) {
      c.hold(
        id: 'CH-P2-WR-POST-${e.key}',
        lens: 'CH2',
        severity: 'P2',
        title: 'POST web_return_origin ${e.value} vazou para Stripe url',
        actor: 'seller JWT',
        pre: 'sanitizeWebReturnOrigin allowlist',
        repro: 'POST create-connect-account {web_return_origin: ${e.value}}',
        expected: 'url Stripe sem host hostil',
        obtained: post.brief,
      );
    } else {
      c.block('wr.post.${e.key}', 'CH2', 'POST origin não vazou hostil', post);
    }

    final get = await c.edge(
      'create-connect-account',
      method: 'GET',
      qs: 'web_return_origin=${Uri.encodeQueryComponent(e.value)}',
      jwt: c.sellerJwt,
    );
    final loc = (get.location ?? '').toLowerCase();
    final gHostile = loc.contains('evil') ||
        loc.contains('javascript') ||
        loc.startsWith('data:') ||
        loc.contains('%00');
    if (get.status == 303 && gHostile) {
      c.hold(
        id: 'CH-P2-WR-GET-${e.key}',
        lens: 'CH2',
        severity: 'P2',
        title: 'GET web_return_origin ${e.value} → Location hostil',
        actor: 'seller JWT GET',
        pre: 'safeWalletReturnLocation allowlist',
        repro: 'GET create-connect-account?web_return_origin=',
        expected: 'sem 303 hostil',
        obtained: get.brief,
      );
    } else {
      c.block('wr.get.${e.key}', 'CH2', 'GET origin sem Location hostil', get);
    }
  }

  // --- CH3/CH6 buyer + seller2 refund ---
  final pBuyer = await mustPay('CH6');
  final balS0 = await c.walletBal(c.sellerId);
  final buyerRefund = await c.refundOrder(pBuyer.oid, jwt: c.buyerJwt);
  final rowAfterBuyer = await c.orderRow(pBuyer.oid);
  final balS1 = await c.walletBal(c.sellerId);
  c.note('refund.buyer', 'buyer refund-order', {
    'hit': buyerRefund.brief,
    'order': rowAfterBuyer?['stripe_refund_id'],
    'dSeller': balS1 - balS0,
  }, lens: 'CH6');
  final buyerDidRefund = buyerRefund.ok &&
      buyerRefund.map?['ok'] == true &&
      buyerRefund.map?['skipped'] != true &&
      (rowAfterBuyer?['stripe_refund_id'] != null &&
          '${rowAfterBuyer?['stripe_refund_id']}'.isNotEmpty);
  if (buyerDidRefund) {
    c.hold(
      id: 'CH-P0-BUYER-REFUND',
      lens: 'CH6',
      severity: 'P0',
      title: 'buyer refund-order anulou Stripe da venda',
      actor: 'buyer JWT',
      pre: 'Edge exige user.id === seller_id',
      repro: 'POST refund-order {order_id} JWT comprador',
      expected: '403 Sem permissão',
      obtained: buyerRefund.brief,
    );
  } else {
    c.block('refund.buyer', 'CH6', 'buyer refund-order recusado (seller-only mantém-se)',
        buyerRefund);
  }

  final pX = await mustPay('CH6');
  final s2ref = await c.refundOrder(pX.oid, jwt: c.seller2Jwt);
  await c.expectDenied(
    id: 'CH-P0-S2-REFUND',
    lens: 'CH6',
    title: 'seller2 refund-order da venda do seller1',
    hit: s2ref,
    actor: 'seller2 JWT',
    pre: 'só o seller da encomenda',
    repro: 'POST refund-order order seller1, JWT seller2',
    severityIfOpen: 'P0',
    openIf: (h) => h.ok && h.map?['ok'] == true && h.map?['skipped'] != true,
  );

  // refund > captura via body
  final pAmt = await mustPay('CH3');
  final over = await c.refundOrder(pAmt.oid, extraBody: {
    'amount': 999999,
    'amount_cents': 999999,
    'refund_amount': 999999,
    'currency': 'usd',
    'partial': true,
  }, jwt: c.sellerJwt);
  final rowOver = await c.orderRow(pAmt.oid);
  final paidCents = (numOf(rowOver?['amount_paid_cents']) ?? 0).round();
  final claimed = (numOf(over.map?['amount_cents']) ?? 0).round();
  c.note('refund.over', 'body amount=999999', {
    'hit': over.brief,
    'paid': paidCents,
    'claimed': claimed,
  }, lens: 'CH3');
  final refundedOk =
      over.ok && over.map?['ok'] == true && over.map?['skipped'] != true;
  if (refundedOk && claimed > paidCents && paidCents > 0) {
    c.hold(
      id: 'CH-P0-REFUND-GT-CAPTURE',
      lens: 'CH3',
      severity: 'P0',
      title: 'refund-order body amount > captura da linha',
      actor: 'seller JWT',
      pre: 'amount da ordem/PI residual, não do body',
      repro: 'POST refund-order {amount:999999}',
      expected: 'refund ≤ amount_paid_cents',
      obtained: {'hit': over.brief, 'paid': paidCents, 'claimed': claimed},
    );
  } else {
    c.block('refund.over', 'CH3', 'refund ignorou amount do body ou ≤ captura', {
      'hit': over.brief,
      'paid': paidCents,
      'claimed': claimed,
    });
  }

  // release sem eligible (pago)
  final pRel = await mustPay('CH3');
  final balR0 = await c.walletBal(c.sellerId);
  final relPago = await c.tryRelease(pRel.oid, jwt: c.buyerJwt);
  final balR1 = await c.walletBal(c.sellerId);
  c.note('rel.pago', 'release em pago', {
    'hit': relPago.brief,
    'delta': balR1 - balR0,
  }, lens: 'CH3');
  if (relPago.json == true && (balR1 - balR0) > 0) {
    c.hold(
      id: 'CH-P0-REL-PAGO',
      lens: 'CH3',
      severity: 'P0',
      title: 'release em status=pago creditou wallet',
      actor: 'buyer JWT',
      pre: 'release só concluido + shipped/mão',
      repro: 'rpc batata_release_seller_wallet_for_order em pago',
      expected: 'false, Δ=0',
      obtained: {'hit': relPago.brief, 'delta': balR1 - balR0},
    );
  } else {
    c.block('rel.pago', 'CH3', 'release pago recusado Δ=0', relPago);
  }

  // release∥refund race no pago
  final pRace = await mustPay('CH3');
  final balC0 = await c.walletBal(c.sellerId);
  final raced = await Future.wait([
    c.refundOrder(pRace.oid, jwt: c.sellerJwt),
    c.tryRelease(pRace.oid, jwt: c.buyerJwt),
    c.tryRelease(pRace.oid, jwt: c.sellerJwt),
  ]);
  final balC1 = await c.walletBal(c.sellerId);
  final rowRace = await c.orderRow(pRace.oid);
  c.note('race.rel.refund', 'refund∥release em pago', {
    'hits': raced.map((h) => h.brief).toList(),
    'delta': balC1 - balC0,
    'refund_id': rowRace?['stripe_refund_id'],
    'release_at': rowRace?['wallet_release_processed_at'],
  }, lens: 'CH3');
  final refunded = raced[0].ok &&
      raced[0].map?['ok'] == true &&
      raced[0].map?['skipped'] != true;
  final released = raced[1].json == true || raced[2].json == true;
  if (refunded && released && (balC1 - balC0) > 0) {
    c.hold(
      id: 'CH-P0-REL-REFUND-RACE',
      lens: 'CH3',
      severity: 'P0',
      title: 'race refund∥release em pago: Stripe refund + crédito wallet',
      actor: 'seller refund + buyer release paralelo',
      pre: 'release inelegível em pago; refund seller-only',
      repro: 'Future.wait refund-order + release no pago',
      expected: 'refund OU nada; release false; sem crédito líquido extra',
      obtained: {
        'hits': raced.map((h) => h.brief).toList(),
        'delta': balC1 - balC0,
        'order': rowRace,
      },
    );
  } else {
    c.block('race.rel.refund', 'CH3', 'race pago sem crédito+refund simultâneo', {
      'refunded': refunded,
      'released': released,
      'delta': balC1 - balC0,
      'hits': raced.map((h) => h.brief).toList(),
    });
  }

  // release∥refund após enviado→concluido
  final pSh = await mustPay('CH3');
  final ship = await c.patchOrder(pSh.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final concl = await c.patchOrder(pSh.oid, {'status': 'concluido'}, jwt: c.buyerJwt);
  c.note('ship.concl', 'enviado→concluido', {
    'ship': ship.brief,
    'concl': concl.brief,
    'row': await c.orderRow(pSh.oid),
  }, lens: 'CH3');
  final balS00 = await c.walletBal(c.sellerId);
  final raced2 = await Future.wait([
    c.refundOrder(pSh.oid, jwt: c.sellerJwt),
    c.tryRelease(pSh.oid, jwt: c.buyerJwt),
  ]);
  final balS11 = await c.walletBal(c.sellerId);
  final rowSh = await c.orderRow(pSh.oid);
  c.note('race.after.ship', 'refund∥release pós-concluido', {
    'hits': raced2.map((h) => h.brief).toList(),
    'delta': balS11 - balS00,
    'order': rowSh,
  }, lens: 'CH3');
  final rfOk = raced2[0].ok &&
      raced2[0].map?['ok'] == true &&
      raced2[0].map?['skipped'] != true;
  final relOk = raced2[1].json == true;
  if (rfOk && relOk) {
    c.hold(
      id: 'CH-P0-REL-REFUND-SHIP',
      lens: 'CH3',
      severity: 'P0',
      title: 'race refund∥release após concluido: refund Stripe + crédito',
      actor: 'seller+buyer paralelo',
      pre: 'refund blocked shipped; release 1×',
      repro: 'enviado→concluido; Future.wait refund + release',
      expected: 'release crédito XOR refund, não ambos',
      obtained: {
        'hits': raced2.map((h) => h.brief).toList(),
        'delta': balS11 - balS00,
        'order': rowSh,
      },
    );
  } else {
    c.block('race.after.ship', 'CH3', 'pós-envio: não houve refund+release juntos', {
      'refunded': rfOk,
      'released': relOk,
      'delta': balS11 - balS00,
    });
  }

  await c.dumpAll('pass2.json');
}
