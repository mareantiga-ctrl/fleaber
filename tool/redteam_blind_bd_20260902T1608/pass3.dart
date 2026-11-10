/// PASS 3 — races payout, unicode key, overdraft, composição residual.
/// dart run tool/redteam_blind_bd_20260902T1608/pass3.dart
import '_rtbd.dart';

bool moneyMoved(HttpHit h) =>
    h.ok &&
    (h.transferId != null || h.map?['success'] == true);

Future<void> main() async {
  final c = Rtbd.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureSeller2();
  final w0 = await c.walletsSnap();
  c.note('p3.w0', 'saldos', w0, lens: 'BD6');

  // BD7 limpo: pago → enviado → entregue → concluido → release → payout → refund
  final clean = await c.payToPago(lens: 'BD7', initialQty: 2);
  if (clean != null) {
    final oid = clean.oid;
    final envio = await c.patchOrder(oid, {'status': 'enviado'}, jwt: c.sellerJwt);
    c.note('bd7.clean.enviado', 'enviado', envio.brief, lens: 'BD7');
    await c.patchOrder(oid, {'status': 'entregue'}, jwt: c.buyerJwt);
    await c.patchOrder(oid, {'status': 'concluido'}, jwt: c.buyerJwt);
    final rowC = await c.orderRow(oid);
    c.note('bd7.clean.row', 'pré-release', rowC, lens: 'BD7');
    final wPre = await c.walletsSnap();
    final rel = await c.release(oid, jwt: c.buyerJwt);
    final wPost = await c.walletsSnap();
    final dRel = (wPost['seller'] ?? 0) - (wPre['seller'] ?? 0);
    c.note('bd7.clean.release', 'release esperado crédito', {
      'rpc': rel.brief,
      'dSeller': dRel,
    }, lens: 'BD7');
    if (rel.body.trim() != 'true' && dRel < 0.009) {
      c.block('BD7.clean.release', 'BD7', 'release não creditou (gate)', {
        'rpc': rel.brief,
        'row': rowC,
        'd': dRel,
      });
    }
    final rel2 = await c.release(oid, jwt: c.buyerJwt);
    final w2 = await c.walletsSnap();
    final d2 = (w2['seller'] ?? 0) - (wPost['seller'] ?? 0);
    if (d2 > 0.009) {
      c.finding(
        id: 'BD7-double-release-clean',
        lens: 'BD7',
        severity: 'P0',
        title: 'Segundo release creditou de novo (ciclo limpo)',
        actor: 'buyer JWT',
        pre: 'já libertado Δ=$dRel',
        repro: 'rpc release 2× após concluido+envio',
        expected: 'false Δ=0',
        obtained: {'rpc': rel2.brief, 'd': d2},
      );
    } else {
      c.block('BD7.clean.twice', 'BD7', '2º release Δ=0', rel2);
    }
    if (dRel > 0.009) {
      final pay = await c.payout(amount: 100, key: '${prefix}-clean-pay');
      c.note('bd7.clean.payout', 'payout 100¢ pós-release', pay.brief, lens: 'BD7');
    }
    final wPreRef = await c.walletsSnap();
    final ref = await c.refund(oid);
    final wPostRef = await c.walletsSnap();
    final claw = (wPreRef['seller'] ?? 0) - (wPostRef['seller'] ?? 0);
    c.note('bd7.clean.refund', 'refund pós-release+payout', {
      'refund': ref.brief,
      'claw': claw,
      'wPre': wPreRef,
      'wPost': wPostRef,
    }, lens: 'BD7');
    final refundOk = ref.ok &&
        ref.map?['ok'] == true &&
        ref.map?['skipped'] != true &&
        ref.map?['already_refunded'] != true;
    if (refundOk && dRel > 0.009 && claw < 0.009) {
      c.finding(
        id: 'BD7-refund-after-release-no-claw',
        lens: 'BD7',
        severity: 'P0',
        title: 'Refund Stripe após release sem clawback (ciclo limpo)',
        actor: 'seller JWT',
        pre: 'release Δ=$dRel',
        repro: 'hop+release; refund-order',
        expected: 'clawback ≥ crédito ou refund 403',
        obtained: {'refund': ref.brief, 'claw': claw},
      );
    } else {
      c.block('BD7.clean.refund', 'BD7', 'refund pós-release 403/clawback/idempotente',
          {'refund': ref.brief, 'claw': claw});
    }
  } else {
    c.skip('BD7.clean', 'BD7', 'setup_paid_order limpo falhou', 'null');
  }

  final balCents = ((w0['seller'] ?? 0) * 100).round();

  // BD6 — N payouts keys distintas a somar > saldo
  final n = 5;
  final each = balCents > 0 ? (balCents ~/ 2).clamp(100, 500) : 100;
  final keys = List.generate(n, (i) => '${prefix}-race-$i-${DateTime.now().microsecondsSinceEpoch}');
  final hits = await parallel([
    for (final k in keys)
      c.payout(amount: each, key: k),
  ]);
  final okTransfers = hits.where(moneyMoved).toList();
  final uniqueTr = <String>{};
  for (final h in okTransfers) {
    final id = h.transferId;
    if (id != null) uniqueTr.add(id);
  }
  c.note('bd6.race', 'N payouts paralelo keys distintas', {
    'n': n,
    'each': each,
    'balCents': balCents,
    'ok': okTransfers.length,
    'uniqueTr': uniqueTr.length,
    'briefs': hits.map((h) => h.brief).toList(),
  }, lens: 'BD6');
  final wRace = await c.walletsSnap();
  if (uniqueTr.length >= 2 && balCents < each * 2) {
    c.finding(
      id: 'BD6-parallel-overdraft',
      lens: 'BD6',
      severity: 'P0',
      title: 'Payouts paralelos keys distintas criaram ≥2 Transfers acima do saldo',
      actor: 'seller JWT',
      pre: 'saldo ${w0['seller']} €; each=$each ¢ × $n',
      repro: 'Future.wait N× create-connect-account keys distintas',
      expected: '≤1 Transfer ou insufficient_balance no resto',
      obtained: {
        'uniqueTr': uniqueTr.length,
        'wAfter': wRace['seller'],
      },
    );
  } else {
    c.block('BD6.race', 'BD6', 'paralelo sem overdraft líquido', {
      'ok': okTransfers.length,
      'uniqueTr': uniqueTr.length,
      'wAfter': wRace['seller'],
    });
  }

  // Unicode / newline na key (não colisão slice-64)
  final uni = await c.payout(
    amount: 100,
    key: '${prefix}-uni-\u202e\n\u0000KEY',
  );
  c.note('bd6.unicode.key', 'idempotency unicode/newline/NUL', uni.brief,
      lens: 'BD6');
  if (moneyMoved(uni) && (w0['seller'] ?? 0) < 1) {
    c.finding(
      id: 'BD6-unicode-key-mint',
      lens: 'BD6',
      severity: 'P1',
      title: 'Payout com key unicode criou Transfer sem saldo',
      actor: 'seller JWT',
      pre: 'saldo ${w0['seller']}',
      repro: 'idempotency_key com U+202E/NUL/newline',
      expected: '400 insufficient / invalid',
      obtained: uni.brief,
    );
  } else {
    c.block('BD6.unicode', 'BD6', 'key unicode sem mint extra', uni);
  }

  // Same key twice (smoke HOLD, não é finding clássico se 2ª idempotente)
  final kSame = '${prefix}-same-key';
  final a = await c.payout(amount: 100, key: kSame);
  final b = await c.payout(amount: 100, key: kSame);
  c.note('bd6.samekey', 'mesma key 2×', {'a': a.brief, 'b': b.brief},
      lens: 'BD6');
  if (a.transferId != null &&
      b.transferId != null &&
      a.transferId != b.transferId) {
    c.finding(
      id: 'BD6-same-key-two-transfers',
      lens: 'BD6',
      severity: 'P0',
      title: 'Mesma idempotency_key gerou duas Transfers',
      actor: 'seller JWT',
      pre: 'key=$kSame',
      repro: '2× payout mesma key',
      expected: '2ª idempotente mesmo transferId',
      obtained: {'a': a.transferId, 'b': b.transferId},
    );
  } else {
    c.block('BD6.samekey', 'BD6', 'mesma key sem 2 Transfers', {
      'a': a.transferId,
      'b': b.transferId,
    });
  }

  // Buyer chama payout (não é vendedor Connect)
  final buyerPay = await c.payout(
    amount: 100,
    key: '${prefix}-buyer-payout',
    jwt: c.buyerJwt,
  );
  c.note('bd1.buyer.payout', 'buyer tenta levantamento', buyerPay.brief,
      lens: 'BD1');
  if (moneyMoved(buyerPay)) {
    c.finding(
      id: 'BD1-buyer-payout',
      lens: 'BD1',
      severity: 'P1',
      title: 'Buyer JWT criou Transfer Connect',
      actor: 'buyer JWT',
      pre: 'conta comprador',
      repro: 'POST create-connect-account amount=100',
      expected: 'Connect not ready / 400',
      obtained: buyerPay.brief,
    );
  } else {
    c.block('BD1.buyer.payout', 'BD1', 'buyer payout sem Transfer', buyerPay);
  }

  // Anon payout
  final anonPay = await c.edge('create-connect-account', {
    'amount': 100,
    'idempotency_key': '${prefix}-anon-pay',
  });
  c.note('bd1.anon.payout', 'anon payout', anonPay.brief, lens: 'BD1');
  if (moneyMoved(anonPay)) {
    c.finding(
      id: 'BD1-anon-payout',
      lens: 'BD1',
      severity: 'P0',
      title: 'Anon criou Transfer',
      actor: 'anon',
      pre: 'sem JWT user',
      repro: 'POST create-connect-account anon',
      expected: '401',
      obtained: anonPay.brief,
    );
  } else {
    c.block('BD1.anon.payout', 'BD1', 'anon payout recusado', anonPay);
  }

  // Composição: hop return em order já release (se pass2 deixou uma)
  // Nova order pago → hop return sem release → refund
  final paid2 = await c.payToPago(lens: 'BD7', initialQty: 2);
  if (paid2 != null) {
    final oid = paid2.oid;
    await c.patchOrder(oid, {'status': 'enviado'}, jwt: c.sellerJwt);
    await c.patchOrder(oid, {'status': 'entregue'}, jwt: c.buyerJwt);
    final conc = await c.patchOrder(oid, {'status': 'concluido'},
        jwt: c.buyerJwt);
    c.note('bd7.ret.conc', 'concluido para return', conc.brief, lens: 'BD7');
    final d = await c.insertDispute(oid);
    c.note('bd7.ret.disp', 'disputa', d.brief, lens: 'BD7');
    final ped = await c.patchOrder(oid, {'status': 'pedido_devolucao'},
        jwt: c.buyerJwt);
    c.note('bd7.ret.ped', 'pedido_devolucao', ped.brief, lens: 'BD7');
    // Buyer tenta concluido a meio da devolução
    final concMid = await c.patchOrder(oid, {'status': 'concluido'},
        jwt: c.buyerJwt);
    c.note('bd7.ret.conc_mid', 'buyer concluido durante return', concMid.brief,
        lens: 'BD7');
    final rowMid = await c.orderRow(oid);
    if (rowMid?['status'] == 'concluido') {
      c.finding(
        id: 'BD7-concluido-during-return',
        lens: 'BD7',
        severity: 'P1',
        title: 'Buyer marcou concluido a meio da devolução',
        actor: 'buyer JWT',
        pre: 'pedido_devolucao',
        repro: 'PATCH status=concluido',
        expected: 'order_concluido_denied_during_return',
        obtained: rowMid?['status'],
      );
    } else {
      c.block('BD7.conc_mid', 'BD7', 'concluido durante return bloqueado',
          concMid);
    }
    final relDuring = await c.release(oid, jwt: c.buyerJwt);
    c.note('bd7.ret.release', 'release durante return', relDuring.brief,
        lens: 'BD7');
    if (relDuring.body.trim() == 'true') {
      c.finding(
        id: 'BD7-release-during-return',
        lens: 'BD7',
        severity: 'P0',
        title: 'Release durante devolução creditou vendedor',
        actor: 'buyer JWT',
        pre: 'status return FSM',
        repro: 'rpc release em pedido_devolucao',
        expected: 'false (disputa aberta ou não concluido)',
        obtained: relDuring.brief,
      );
    } else {
      c.block('BD7.release.return', 'BD7', 'release durante return = false',
          relDuring);
    }
  } else {
    c.skip('BD7.return.fixture', 'BD7', '2º setup_paid_order falhou', 'null');
  }

  final w1 = await c.walletsSnap();
  c.note('p3.w1', 'saldos finais', {'before': w0, 'after': w1}, lens: 'BD7');
  await c.dumpAll('pass3.json');
}
