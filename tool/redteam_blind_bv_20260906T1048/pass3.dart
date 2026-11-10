import '_rtbv.dart';

/// Pass 3 — fechar BV5 FSM (enviado sem mexer shipping_method) + controlo positivo release.
void main() async {
  final c = Rtbv.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  Future<({String oid, String pid, String? pi})> mustPay(String lens) async {
    final paid = await c.payToPago(lens: lens);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  // Controlo: seller marca enviado (trigger shipped_at), buyer conclui, release credita.
  final p = await mustPay('BV5');
  final row0 = await c.orderRow(p.oid);
  c.note('p3.row0', 'pago fresco', row0, lens: 'BV5');

  final ship = await c.patchOrder(p.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final rowShip = await c.orderRow(p.oid);
  c.note('p3.enviado', 'seller PATCH status=enviado only', {
    'hit': ship.brief,
    'order': rowShip,
  }, lens: 'BV5');

  final concl = await c.patchOrder(p.oid, {'status': 'concluido'}, jwt: c.buyerJwt);
  final rowConcl = await c.orderRow(p.oid);
  c.note('p3.concl', 'buyer PATCH concluido após enviado', {
    'hit': concl.brief,
    'order': rowConcl,
  }, lens: 'BV5');

  final unshipNull = await c.patchOrder(p.oid, {'shipped_at': null}, jwt: c.sellerJwt);
  final unshipPago = await c.patchOrder(p.oid, {
    'status': 'pago',
    'shipped_at': null,
  }, jwt: c.sellerJwt);
  final unshipEnviado = await c.patchOrder(p.oid, {'status': 'enviado'}, jwt: c.sellerJwt);
  final rowAfter = await c.orderRow(p.oid);
  c.note('p3.unship', 'seller tenta unship/regressão após concluido', {
    'null': unshipNull.brief,
    'pago': unshipPago.brief,
    'enviado': unshipEnviado.brief,
    'order': rowAfter,
  }, lens: 'BV5');

  final st = '${rowAfter?['status']}'.toLowerCase();
  final shippedCleared = rowAfter?['shipped_at'] == null ||
      '${rowAfter?['shipped_at']}'.trim().isEmpty;
  if (st != 'concluido' || shippedCleared) {
    c.hold(
      id: 'BV-P1-UNSHIP',
      lens: 'BV5',
      severity: 'P1',
      title: 'seller alterou concluido ou limpou shipped_at',
      actor: 'seller JWT',
      pre: 'concluido imutável; shipped_at imutável após set',
      repro: 'enviado→concluido; PATCH shipped_at=null / status=pago',
      expected: 'status=concluido e shipped_at preenchido',
      obtained: {
        'null': unshipNull.brief,
        'pago': unshipPago.brief,
        'order': rowAfter,
      },
    );
  } else {
    c.block('p3.unship', 'BV5', 'concluido+shipped_at imutáveis', {
      'null': unshipNull.brief,
      'pago': unshipPago.brief,
      'enviado': unshipEnviado.brief,
      'status': st,
      'shipped_at': rowAfter?['shipped_at'],
    });
  }

  final bal0 = await c.walletBal(c.sellerId);
  final rel = await c.tryRelease(p.oid, jwt: c.buyerJwt);
  final relS = await c.tryRelease(p.oid, jwt: c.sellerJwt);
  final rel2 = await c.tryRelease(p.oid, jwt: c.buyer2Jwt);
  final bal1 = await c.walletBal(c.sellerId);
  final rowRel = await c.orderRow(p.oid);
  c.note('p3.release', 'release após concluido+shipped', {
    'buyer': rel.brief,
    'seller': relS.brief,
    'buyer2': rel2.brief,
    'delta': bal1 - bal0,
    'order': rowRel,
  }, lens: 'BV7');

  // Buyer2 não deve creditar (já released ou false)
  if (rel2.ok && rel2.json == true && (bal1 - bal0) > 0 && rel.json != true) {
    c.hold(
      id: 'BV-P0-REL-B2',
      lens: 'BV6',
      severity: 'P0',
      title: 'buyer2 release creditou venda alheia',
      actor: 'buyer2 JWT',
      pre: 'release só buyer da encomenda',
      repro: 'rpc batata_release_seller_wallet_for_order JWT buyer2',
      expected: 'false',
      obtained: rel2.brief,
    );
  } else {
    c.block('p3.rel.b2', 'BV6', 'buyer2 release não creditou extra', {
      'buyer2': rel2.json,
      'delta': bal1 - bal0,
      'buyerRel': rel.json,
    });
  }

  // Segundo release não minta
  final bal2pre = await c.walletBal(c.sellerId);
  final relAgain = await c.tryRelease(p.oid, jwt: c.buyerJwt);
  final bal2post = await c.walletBal(c.sellerId);
  if (bal2post - bal2pre > 0) {
    c.hold(
      id: 'BV-P0-REL-DUP',
      lens: 'BV3',
      severity: 'P0',
      title: 'segundo release mintou carteira',
      actor: 'buyer JWT',
      pre: 'wallet_release_processed_at selo',
      repro: 'rpc release 2× após concluido',
      expected: 'Δ=0',
      obtained: {'delta': bal2post - bal2pre, 'hit': relAgain.brief},
    );
  } else {
    c.block('p3.rel.dup', 'BV7', 'segundo release Δ=0', {
      'delta': bal2post - bal2pre,
      'hit': relAgain.json,
    });
  }

  // Refund após release (clawback?)
  final rf = await c.refundOrder(p.oid, jwt: c.sellerJwt);
  final rowRf = await c.orderRow(p.oid);
  c.note('p3.refund.after.release', 'seller refund-order pós-release', {
    'hit': rf.brief,
    'order': rowRf,
  }, lens: 'BV3');

  await c.dumpAll('pass3.json');
}
