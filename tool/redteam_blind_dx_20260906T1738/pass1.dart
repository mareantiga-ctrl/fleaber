/// RED TEAM CEGO DX — matriz A settle + B tip + C refund/webhook/CORS + D caixa.
/// Staging only. NÃO corrigir. NÃO produção. NÃO Fase 4.
import 'dart:io';
import '_rtdx.dart';

bool looksPaidCopy(HttpHit? h) {
  final t = (h?.body ?? '').toLowerCase();
  return t.contains('pagamento recebido') ||
      t.contains('pagamento confirmado') ||
      t.contains('"status":"pago"') ||
      t.contains('gorjeta registada');
}

bool stripeOracle(HttpHit? h) {
  final t = (h?.body ?? '').toLowerCase();
  return t.contains('no such checkout.session') ||
      t.contains('no such payment_intent') ||
      t.contains('resource_missing');
}

bool corsEchoes(HttpHit h, String origin) {
  final a = (h.acao ?? '').trim();
  if (a.isEmpty) return false;
  if (a == origin) return true;
  if (origin.startsWith('chrome-extension://') &&
      a.startsWith('chrome-extension://')) {
    return true;
  }
  if (origin.contains('evil.com') && a.contains('evil.com')) return true;
  return false;
}

void main() async {
  final c = Rtdx.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.restoreSeller1Published();
  await c.setHub(c.seller2Id!, false);

  final s1 = c.sellerId!;
  final s2 = c.seller2Id!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;

  try {
    await runSettle(c, s1, b1, b2);
    await runTip(c, s1, s2, b2);
    await runRefundWebhookCors(c, s1, b1);
    await runCaixa(c, s1);
  } finally {
    await c.endLives();
    await c.restoreSeller1Published();
    await c.setHub(s2, false);
  }

  await c.dumpAll('pass1.json');
  stdout.writeln(
    'DX DONE probes=${c.probes.length} findings=${c.findings.where((f) => f['count'] == true).length} '
    'lenses=${c.lensesHit.toList()..sort()}',
  );
}

Future<void> runSettle(Rtdx c, String s1, String b1, String b2) async {
  const price = 12.0;
  final pidA = await c.createProduct(
    seller: s1,
    title: '$prefix settle-A',
    qty: 4,
    price: price,
  );
  final pidB = await c.createProduct(
    seller: s1,
    title: '$prefix settle-B',
    qty: 4,
    price: price,
  );
  if (pidA == null || pidB == null) {
    c.skip('A*', 'DX1', 'SKU fixture falhou', {'a': pidA, 'b': pidB});
    return;
  }
  final oidA = await c.insertOrder(
    productId: pidA,
    buyer: b2,
    seller: s1,
    price: price,
  );
  final oidB = await c.insertOrder(
    productId: pidB,
    buyer: b1,
    seller: s1,
    price: price,
  );
  if (oidA == null || oidB == null) {
    c.skip('A*', 'DX1', 'order fixture falhou', {'a': oidA, 'b': oidB});
    return;
  }

  // A3 metadata/body amount hostil + web_return_origin evil (classe_nova extra no body)
  final ckA = await c.checkout(
    orderId: oidA,
    buyer: b2,
    jwt: c.buyer2Jwt,
    amount: 1,
    productId: pidA,
    seller: s1,
    extra: {
      'total': 50,
      'server_amount_cents': '50',
      'web_return_origin': 'https://evil.com',
    },
  );
  final sidA = ckA.sessionId;
  final quoted = numOf(ckA.map?['server_amount_cents'])?.round();
  final stripeAmt = numOf(ckA.map?['amount_total'])?.round();
  final urlA = '${ckA.map?['checkoutUrl'] ?? ''}';
  final clientWon = ckA.ok &&
      ((quoted != null && quoted <= 50) ||
          (stripeAmt != null && stripeAmt <= 50));
  final evilUrl = urlA.contains('evil.com');
  c.probe(
    id: 'A3',
    edgeRpc: 'create-payment-intent POST',
    payload:
        'B2 POST amount=1 total=50 server_amount_cents=50 web_return_origin=https://evil.com vs SKU 12,00€',
    http: ckA,
    stripeBd: {
      'sid': sidA,
      'server_amount_cents': quoted,
      'amount_total': stripeAmt,
      'checkoutUrl_has_evil': evilUrl,
      'price_total': (await c.orderRow(oidA))?['price_total'],
    },
    result: !ckA.ok ? 'SKIP' : ((clientWon || evilUrl) ? 'FAIL' : 'HOLD'),
    lens: 'DX1',
    countFinding: clientWon || evilUrl,
    classeNova: true,
  );
  if (clientWon || evilUrl) {
    c.hold(
      id: clientWon ? 'DX-P0-A3-CLIENT-AMOUNT' : 'DX-P1-A3-EVIL-RETURN',
      lens: 'DX1',
      severity: clientWon ? 'P0' : 'P1',
      title: clientWon
          ? 'Checkout usou amount do cliente em vez da quote servidor'
          : 'web_return_origin evil.com entrou no checkoutUrl',
      actor: 'B2 JWT',
      pre: 'SKU 12,00€; body amount=1; web_return_origin=https://evil.com',
      repro: 'POST create-payment-intent amount=1 total=50 web_return_origin=evil',
      expected: 'server_amount_cents ≥ 1200; URL sem evil.com',
      obtained: ckA.brief,
    );
  } else if (ckA.ok) {
    c.block('A3.amount', 'DX1', 'quote servidor; evil origin sanitizado', {
      'quoted': quoted,
      'amount_total': stripeAmt,
      'url_has_evil': evilUrl,
    });
  } else {
    c.skip('A3', 'DX1', 'checkout A3 não criou Session', ckA);
  }

  // A1 settle unpaid + session inexistente (classe_nova: inexistente vs oráculo Stripe)
  HttpHit? a1unpaid;
  HttpHit? a1missing;
  HttpHit? a1fake;
  Map<String, dynamic>? rowA1;
  if (sidA != null) {
    a1unpaid = await c.settleGet(sidA);
    rowA1 = await c.orderRow(oidA);
  }
  a1missing = await c.edge(
    'create-payment-intent',
    method: 'GET',
    qs: 'checkout_return=success',
  );
  a1fake = await c.settleGet('cs_test_rtdx_inexistente_dead_000');
  final a1credited = c.orderPaid(rowA1) ||
      looksPaidCopy(a1unpaid) ||
      (numOf(rowA1?['amount_paid_cents']) ?? 0) > 0;
  final a1oracle = stripeOracle(a1fake) || stripeOracle(a1missing);
  final a1fakePaid = looksPaidCopy(a1fake) || a1fake.status == 200 && a1fake.ok;
  c.probe(
    id: 'A1',
    edgeRpc: 'create-payment-intent GET settle',
    payload:
        'GET unpaid $sidA + GET sem session_id + GET cs_test_inexistente',
    http: {
      'unpaid': a1unpaid?.brief,
      'missing': a1missing.brief,
      'fake': a1fake.brief,
    },
    stripeBd: {
      'status': rowA1?['status'],
      'amount_paid_cents': rowA1?['amount_paid_cents'],
    },
    result: sidA == null
        ? 'SKIP'
        : ((a1credited || a1oracle || a1fakePaid) ? 'FAIL' : 'HOLD'),
    lens: 'DX1',
    countFinding: a1credited || a1oracle || a1fakePaid,
    classeNova: true,
  );
  if (a1credited || a1oracle || a1fakePaid) {
    c.hold(
      id: a1credited ? 'DX-P0-A1-SETTLE-UNPAID' : 'DX-P3-A1-ORACLE',
      lens: 'DX1',
      severity: a1credited ? 'P0' : 'P3',
      title: a1credited
          ? 'GET settle unpaid marcou encomenda paga'
          : 'GET session inexistente ecoa oráculo Stripe',
      actor: 'anon GET',
      pre: 'Session unpaid / cs_test morta',
      repro: 'GET create-payment-intent?checkout_return=success&session_id=',
      expected: 'unpaid 4xx; fake 400 genérico; order ≠pago',
      obtained: {
        'unpaid': a1unpaid?.brief,
        'fake': a1fake.brief,
        'missing': a1missing.brief,
        'row': rowA1,
      },
    );
  } else if (sidA != null) {
    c.block('A1.unpaid', 'DX1', 'unpaid + inexistente sem crédito / sem oráculo', {
      'unpaid': a1unpaid?.brief,
      'fake': a1fake.brief,
      'missing': a1missing.status,
      'status': rowA1?['status'],
    });
  }

  // A2 session_id alheio outra order/buyer (classe_nova vs tip↔order DL)
  final ckB = await c.checkout(
    orderId: oidB,
    buyer: b1,
    jwt: c.buyerJwt,
    amount: 99999,
    productId: pidB,
    seller: s1,
  );
  final sidB = ckB.sessionId;
  HttpHit? a2cross;
  HttpHit? a2qs;
  Map<String, dynamic>? rowB0;
  Map<String, dynamic>? rowA2;
  Map<String, dynamic>? rowB2;
  if (sidA != null) {
    rowB0 = await c.orderRow(oidB);
    a2cross = await c.settleGet(sidA, extraQs: 'order_id=$oidB&buyer_id=$b1');
    a2qs = await c.edge(
      'create-payment-intent',
      method: 'GET',
      qs:
          'checkout_return=success&session_id=$sidA&session_id=${sidB ?? "cs_test_none"}&order_id=$oidB',
    );
    rowA2 = await c.orderRow(oidA);
    rowB2 = await c.orderRow(oidB);
  }
  final a2paidB = c.orderPaid(rowB2) ||
      looksPaidCopy(a2cross) ||
      looksPaidCopy(a2qs) ||
      (numOf(rowB2?['amount_paid_cents']) ?? 0) > 0;
  final a2paidA = c.orderPaid(rowA2);
  c.probe(
    id: 'A2',
    edgeRpc: 'create-payment-intent GET settle alheio',
    payload:
        'GET sidA (B2) + order_id=oidB (B1); query session_id duplicado sidA&sidB',
    http: {
      'ckB': ckB.brief,
      'cross': a2cross?.brief,
      'dup_qs': a2qs?.brief,
    },
    stripeBd: {
      'oidA_status': rowA2?['status'],
      'oidB_status': rowB2?['status'],
      'oidB_before': rowB0?['status'],
      'sidA': sidA,
      'sidB': sidB,
    },
    result: sidA == null ? 'SKIP' : (a2paidB ? 'FAIL' : 'HOLD'),
    lens: 'DX1',
    countFinding: a2paidB,
    classeNova: true,
  );
  if (a2paidB) {
    c.hold(
      id: 'DX-P0-A2-SESSION-ALHEIO',
      lens: 'DX1',
      severity: 'P0',
      title: 'GET settle sidA creditou order B (buyer alheio)',
      actor: 'anon GET',
      pre: 'oidA B2 / oidB B1 Sessions distintas',
      repro: 'GET settle session_id=sidA&order_id=oidB',
      expected: 'oidB permanece reserva_pendente',
      obtained: {
        'cross': a2cross?.brief,
        'dup': a2qs?.brief,
        'rowB': rowB2,
      },
    );
  } else if (sidA != null) {
    c.block('A2.alheio', 'DX1', 'sidA não liquida oidB; duplicado qs inerte', {
      'oidA': rowA2?['status'],
      'oidB': rowB2?['status'],
      'a2paidA': a2paidA,
    });
  }

  // A4 reuse Session + settle (sem sk_test expire nativo)
  HttpHit? reuse;
  HttpHit? dead;
  Map<String, dynamic>? rowA4;
  if (oidA.isNotEmpty) {
    reuse = await c.checkout(
      orderId: oidA,
      buyer: b2,
      jwt: c.buyer2Jwt,
      amount: 1,
      productId: pidA,
      seller: s1,
    );
    dead = await c.settleGet('cs_test_dead_expired_rtdx_000');
    rowA4 = await c.orderRow(oidA);
  }
  final reuseSid = reuse?.sessionId;
  final duplicated = reuseSid != null &&
      sidA != null &&
      reuseSid != sidA &&
      reuse != null &&
      reuse.ok;
  final a4paid = c.orderPaid(rowA4) || looksPaidCopy(dead);
  c.probe(
    id: 'A4',
    edgeRpc: 'create-payment-intent POST reuse + GET dead',
    payload:
        '2.º POST mesma order oidA; GET cs_test_dead_expired (sem sk_test expire)',
    http: {'reuse': reuse?.brief, 'dead': dead?.brief},
    stripeBd: {
      'sidA': sidA,
      'reuseSid': reuseSid,
      'status': rowA4?['status'],
    },
    result: reuse == null
        ? 'SKIP'
        : ((duplicated && a4paid) || a4paid ? 'FAIL' : 'HOLD'),
    lens: 'DX1',
    countFinding: a4paid,
  );
  if (a4paid) {
    c.hold(
      id: 'DX-P0-A4-DEAD-SETTLE',
      lens: 'DX1',
      severity: 'P0',
      title: 'GET Session morta / 2.º POST liquidou a encomenda',
      actor: 'B2 JWT + anon GET',
      pre: 'sem expire Stripe nativo (sem sk_test_ local)',
      repro: 'POST reuse + GET cs_test_dead',
      expected: 'mesmo sid ou 400; order ≠pago',
      obtained: {'reuse': reuse?.brief, 'dead': dead?.brief, 'row': rowA4},
    );
  } else if (reuse != null) {
    c.block('A4.reuse', 'DX1', 'reuse sem captura extra; dead não credita', {
      'sidA': sidA,
      'reuseSid': reuseSid,
      'dead': dead?.status,
    });
  }

  // A5 GET settle 2× paralelo (race obrigatória, classe_nova)
  HttpHit? g1;
  HttpHit? g2;
  Map<String, dynamic>? rowA5;
  if (sidA != null) {
    final raced = await Future.wait([
      c.settleGet(sidA),
      c.settleGet(sidA, extraQs: 'order_id=$oidA'),
    ]);
    g1 = raced[0];
    g2 = raced[1];
    rowA5 = await c.orderRow(oidA);
  }
  final a5paid = c.orderPaid(rowA5) ||
      looksPaidCopy(g1) ||
      looksPaidCopy(g2) ||
      (numOf(rowA5?['amount_paid_cents']) ?? 0) > 0;
  c.probe(
    id: 'A5',
    edgeRpc: 'create-payment-intent GET ∥ GET',
    payload: 'Future.wait GET settle sidA ×2 (idempotency unpaid)',
    http: {'g1': g1?.brief, 'g2': g2?.brief},
    stripeBd: {
      'status': rowA5?['status'],
      'amount_paid_cents': rowA5?['amount_paid_cents'],
    },
    result: sidA == null ? 'SKIP' : (a5paid ? 'FAIL' : 'HOLD'),
    lens: 'DX6',
    countFinding: a5paid,
    classeNova: true,
    race: true,
  );
  if (a5paid) {
    c.hold(
      id: 'DX-P0-A5-SETTLE-RACE',
      lens: 'DX6',
      severity: 'P0',
      title: 'GET settle paralelo unpaid marcou pago',
      actor: 'anon GET ×2',
      pre: 'Session unpaid',
      repro: 'Future.wait two GET checkout_return=success',
      expected: 'ambos unpaid; status reserva_pendente',
      obtained: {'g1': g1?.brief, 'g2': g2?.brief, 'row': rowA5},
    );
  } else if (sidA != null) {
    c.block('A5.race', 'DX6', 'settle∥settle unpaid sem crédito', {
      'g1': g1?.status,
      'g2': g2?.status,
      'status': rowA5?['status'],
    });
  }
}

Future<void> runTip(Rtdx c, String s1, String s2, String b2) async {
  final live = await c.insertLive(seller: s1, title: '$prefix tip-s1');
  final liveS2 = await c.insertLive(seller: s2, title: '$prefix tip-s2');
  if (live == null) {
    c.skip('B*', 'DX2', 'live S1 fixture falhou', live);
    return;
  }
  await c.restoreSeller1Published();

  // B1 amount / tip_id / live_id hostil
  final amts = <Object>[0, -1, 0.5, 501];
  final amtHits = <String, String>{};
  for (final a in amts) {
    final h = await c.tipCheckout(
      liveId: live,
      seller: s1,
      amountEur: a,
      jwt: c.buyer2Jwt,
    );
    amtHits['$a'] = h.brief;
  }
  final tipIdHit = await c.tipCheckout(
    liveId: live,
    seller: s1,
    amountEur: 2,
    jwt: c.buyer2Jwt,
    extra: {'tip_id': '00000000-0000-4000-8000-000000000001'},
  );
  final liveFake = await c.tipCheckout(
    liveId: '00000000-0000-4000-8000-000000000099',
    seller: s1,
    amountEur: 2,
    jwt: c.buyer2Jwt,
  );
  final anyAmtOk = amtHits.values.any((s) => s.startsWith('200'));
  final hostilOk = tipIdHit.ok || liveFake.ok;
  c.probe(
    id: 'B1',
    edgeRpc: 'create-live-tip-checkout POST',
    payload:
        'amount 0/-1/0.5/501 + tip_id cliente + live_id UUID inexistente',
    http: {
      ...amtHits,
      'tip_id': tipIdHit.brief,
      'live_fake': liveFake.brief,
    },
    stripeBd: {'sessions': 0},
    result: (anyAmtOk || hostilOk) ? 'FAIL' : 'HOLD',
    lens: 'DX2',
    countFinding: anyAmtOk || hostilOk,
    classeNova: true,
  );
  if (anyAmtOk || hostilOk) {
    c.hold(
      id: 'DX-P0-B1-TIP-HOSTIL',
      lens: 'DX2',
      severity: 'P0',
      title: 'tip aceitou amount/tip_id/live_id hostil',
      actor: 'B2 JWT',
      pre: 'teto 1–500€; client tip_id forbidden; live must exist',
      repro: 'POST create-live-tip-checkout amount/tip_id/live_id hostil',
      expected: '400',
      obtained: {
        ...amtHits,
        'tip_id': tipIdHit.brief,
        'live_fake': liveFake.brief,
      },
    );
  } else {
    c.block('B1.hostil', 'DX2', 'amount/tip_id/live_id hostil recusados', {
      ...amtHits,
      'tip_id': tipIdHit.status,
      'live_fake': liveFake.status,
    });
  }

  // B2 tip∥end_live / unpublish (race)
  final liveRace = await c.insertLive(seller: s1, title: '$prefix tip-race');
  HttpHit? tipRace;
  HttpHit? endHit;
  if (liveRace != null) {
    final raced = await Future.wait([
      c.tipCheckout(
        liveId: liveRace,
        seller: s1,
        amountEur: 2,
        jwt: c.buyer2Jwt,
      ),
      c.rest('PATCH', 'lives?id=eq.$liveRace', service: true, body: {
        'is_active': false,
        'status': 'ended',
      }, prefer: 'return=minimal'),
      () async {
        await c.setHub(s1, false);
        return HttpHit(0, 'unpublish', {'ok': true});
      }(),
    ]);
    tipRace = raced[0];
    endHit = raced[1];
    await c.restoreSeller1Published();
  }
  String? tipRaceId = tipRace?.tipId;
  if (tipRaceId != null) c.createdTipIds.add(tipRaceId);
  Map<String, dynamic>? tipRaceRow;
  HttpHit? tipRaceSettle;
  num dWallet = 0;
  if (tipRaceId != null) {
    tipRaceRow = await c.tipRow(tipRaceId);
  }
  if (tipRace?.sessionId != null) {
    final w0 = await c.walletBal(s1);
    tipRaceSettle = await c.tipSettleGet(tipRace!.sessionId!);
    final w1 = await c.walletBal(s1);
    dWallet = w1 - w0;
    if (tipRaceId != null) tipRaceRow = await c.tipRow(tipRaceId);
  }
  final b2credited = (tipRaceRow != null &&
          '${tipRaceRow['status']}'.toLowerCase() == 'paid') ||
      dWallet > 0 ||
      looksPaidCopy(tipRaceSettle);
  c.probe(
    id: 'B2',
    edgeRpc: 'create-live-tip-checkout ∥ end_live/unpublish',
    payload: 'Future.wait POST tip + PATCH live ended + hub unpublish',
    http: {
      'tip': tipRace?.brief,
      'end': endHit?.brief,
      'settle': tipRaceSettle?.brief,
    },
    stripeBd: {
      'tip_id': tipRaceId,
      'tip_status': tipRaceRow?['status'],
      'delta_wallet': dWallet,
    },
    result: liveRace == null ? 'SKIP' : (b2credited ? 'FAIL' : 'HOLD'),
    lens: 'DX6',
    countFinding: b2credited,
    classeNova: true,
    race: true,
  );
  if (b2credited) {
    c.hold(
      id: 'DX-P0-B2-TIP-UNPUBLISH',
      lens: 'DX6',
      severity: 'P0',
      title: 'tip∥end_live creditou wallet / marcou paid unpaid',
      actor: 'B2 JWT + service end_live',
      pre: 'tips só broadcasting + hub published',
      repro: 'Future.wait tip POST ∥ PATCH ended ∥ unpublish',
      expected: '400 broadcasting ou pending Δwallet 0',
      obtained: {
        'tip': tipRace?.brief,
        'row': tipRaceRow,
        'delta': dWallet,
      },
    );
  } else if (liveRace != null) {
    c.block('B2.race', 'DX6', 'tip∥end sem crédito', {
      'tip': tipRace?.status,
      'status': tipRaceRow?['status'],
      'delta': dWallet,
    });
  }

  // B3 seller≠owner (1 residual máx)
  await c.setHub(s2, true);
  final wrong = await c.tipCheckout(
    liveId: live,
    seller: s2,
    amountEur: 2,
    jwt: c.buyer2Jwt,
  );
  final s2own = liveS2 == null
      ? null
      : await c.tipCheckout(
          liveId: liveS2,
          seller: s1,
          amountEur: 2,
          jwt: c.buyer2Jwt,
        );
  await c.setHub(s2, false);
  final b3fail = wrong.ok || (s2own?.ok == true);
  c.probe(
    id: 'B3',
    edgeRpc: 'create-live-tip-checkout POST',
    payload: 'seller_id S2 na live S1; seller_id S1 na live S2',
    http: {'s2_on_s1': wrong.brief, 's1_on_s2': s2own?.brief},
    result: b3fail ? 'FAIL' : 'HOLD',
    lens: 'DX2',
    countFinding: b3fail,
  );
  if (b3fail) {
    c.hold(
      id: 'DX-P1-B3-TIP-SELLER',
      lens: 'DX2',
      severity: 'P1',
      title: 'tip aceita seller_id ≠ dono da live',
      actor: 'B2 JWT',
      pre: 'Tip seller does not own this live',
      repro: 'POST create-live-tip-checkout seller_id alheio',
      expected: '400',
      obtained: {'wrong': wrong.brief, 's2own': s2own?.brief},
    );
  } else {
    c.block('B3.owner', 'DX2', 'seller≠owner 400 (residual clássico)', {
      'wrong': wrong.brief,
      's2own': s2own?.brief,
    });
  }

  // B4 tip Session TEST unpaid oracle Δwallet 0
  final liveB4 = await c.insertLive(seller: s1, title: '$prefix tip-b4');
  HttpHit? tipOk;
  if (liveB4 != null) {
    await c.restoreSeller1Published();
    tipOk = await c.tipCheckout(
      liveId: liveB4,
      seller: s1,
      amountEur: 2,
      jwt: c.buyer2Jwt,
    );
  }
  final sidTip = tipOk?.sessionId;
  if (tipOk?.tipId != null) c.createdTipIds.add(tipOk!.tipId!);
  HttpHit? settleTip;
  HttpHit? settleTipLiveQs;
  Map<String, dynamic>? tipB4;
  num dB4 = 0;
  if (sidTip != null) {
    final w0 = await c.walletBal(s1);
    settleTip = await c.tipSettleGet(sidTip);
    settleTipLiveQs = await c.tipSettleGet(
      sidTip,
      extraQs: 'live_id=${liveS2 ?? live}&sellerId=$s2',
    );
    final w1 = await c.walletBal(s1);
    dB4 = w1 - w0;
    if (tipOk?.tipId != null) tipB4 = await c.tipRow(tipOk!.tipId!);
  }
  final b4credited = dB4 > 0 ||
      looksPaidCopy(settleTip) ||
      looksPaidCopy(settleTipLiveQs) ||
      (tipB4 != null && '${tipB4['status']}'.toLowerCase() == 'paid');
  c.probe(
    id: 'B4',
    edgeRpc: 'create-live-tip-checkout GET settle unpaid',
    payload:
        'POST tip Session TEST + GET unpaid + GET live_id query alheio',
    http: {
      'create': tipOk?.brief,
      'settle': settleTip?.brief,
      'live_qs': settleTipLiveQs?.brief,
    },
    stripeBd: {
      'sid': sidTip,
      'tip_status': tipB4?['status'],
      'amount': tipB4?['amount'],
      'delta_wallet': dB4,
    },
    result: sidTip == null ? 'SKIP' : (b4credited ? 'FAIL' : 'HOLD'),
    lens: 'DX7',
    countFinding: b4credited,
  );
  if (b4credited) {
    c.hold(
      id: 'DX-P0-B4-TIP-UNPAID',
      lens: 'DX7',
      severity: 'P0',
      title: 'GET settle tip unpaid creditou wallet',
      actor: 'anon GET',
      pre: 'Session payment_status≠paid',
      repro: 'GET create-live-tip-checkout?checkout_return=success',
      expected: 'pending Δwallet 0',
      obtained: {
        'settle': settleTip?.brief,
        'row': tipB4,
        'delta': dB4,
      },
    );
  } else if (sidTip != null) {
    c.block('B4.unpaid', 'DX7', 'tip Session unpaid Δwallet 0', {
      'status': tipB4?['status'],
      'delta': dB4,
      'sid': sidTip,
    });
  } else {
    c.skip('B4', 'DX7', 'não criou tip Session (broadcast/429)', tipOk);
  }
}

Future<void> runRefundWebhookCors(Rtdx c, String s1, String b1) async {
  Future<({String oid, String pid, String? pi})> mustPay(String lens) async {
    final paid = await c.payToPago(lens: lens);
    if (paid == null) throw StateError('setup_paid_order failed $lens');
    return paid;
  }

  // D1 is in runCaixa; C1 uses its own paid order.
  final pBuyer = await mustPay('DX3');
  final balS0 = await c.walletBal(s1);
  final buyerRefund = await c.refundOrder(pBuyer.oid, jwt: c.buyerJwt);
  final rowAfterBuyer = await c.orderRow(pBuyer.oid);
  final balS1w = await c.walletBal(s1);
  final buyerDid = buyerRefund.ok &&
      buyerRefund.map?['ok'] == true &&
      buyerRefund.map?['skipped'] != true &&
      '${rowAfterBuyer?['stripe_refund_id'] ?? ''}'.isNotEmpty;
  c.probe(
    id: 'C1',
    edgeRpc: 'refund-order',
    payload: 'POST refund-order JWT comprador order=${pBuyer.oid}',
    http: buyerRefund,
    stripeBd: {
      'refund_id': rowAfterBuyer?['stripe_refund_id'],
      'status': rowAfterBuyer?['status'],
      'deltaSeller': balS1w - balS0,
      'pi': pBuyer.pi,
    },
    result: buyerDid ? 'FAIL' : 'HOLD',
    lens: 'DX3',
    countFinding: buyerDid,
  );
  if (buyerDid) {
    c.hold(
      id: 'DX-P0-C1-BUYER-REFUND',
      lens: 'DX3',
      severity: 'P0',
      title: 'buyer refund-order anulou Stripe da venda',
      actor: 'buyer JWT',
      pre: 'Edge exige user.id === seller_id',
      repro: 'POST refund-order {order_id} JWT comprador',
      expected: '403 Sem permissão',
      obtained: buyerRefund.brief,
    );
  } else {
    c.block('C1.buyer', 'DX3', 'buyer refund-order recusado (seller-only)',
        buyerRefund);
  }

  // C2 seller refund 2×
  final pIdem = await mustPay('DX3');
  final r1 = await c.refundOrder(pIdem.oid, jwt: c.sellerJwt);
  final row1 = await c.orderRow(pIdem.oid);
  final r2 = await c.refundOrder(pIdem.oid, jwt: c.sellerJwt);
  final row2 = await c.orderRow(pIdem.oid);
  final id1 = '${row1?['stripe_refund_id'] ?? r1.map?['refund_id'] ?? ''}';
  final id2 = '${row2?['stripe_refund_id'] ?? r2.map?['refund_id'] ?? ''}';
  final firstOk = r1.ok && r1.map?['ok'] == true && r1.map?['skipped'] != true;
  final secondNew = r2.ok &&
      r2.map?['ok'] == true &&
      r2.map?['already_refunded'] != true &&
      r2.map?['idempotent'] != true &&
      id2.isNotEmpty &&
      id1.isNotEmpty &&
      id2 != id1;
  c.probe(
    id: 'C2',
    edgeRpc: 'refund-order ×2',
    payload: 'seller refund pago ${pIdem.oid} duas vezes',
    http: {'r1': r1.brief, 'r2': r2.brief},
    stripeBd: {
      'refund1': id1,
      'refund2': id2,
      'status1': row1?['status'],
      'status2': row2?['status'],
      'pi': pIdem.pi,
      'already': r2.map?['already_refunded'],
      'idempotent': r2.map?['idempotent'],
    },
    result: !firstOk ? 'SKIP' : (secondNew ? 'FAIL' : 'HOLD'),
    lens: 'DX3',
    countFinding: secondNew,
  );
  if (secondNew) {
    c.hold(
      id: 'DX-P0-C2-REFUND-DUP',
      lens: 'DX3',
      severity: 'P0',
      title: '2.º refund-order criou refund Stripe distinto',
      actor: 'seller JWT',
      pre: 'idempotency fleaber_order_refund_{orderId}',
      repro: 'POST refund-order 2× mesma order paga',
      expected: '2.º already_refunded / mesmo refund_id',
      obtained: {'r1': r1.brief, 'r2': r2.brief, 'id1': id1, 'id2': id2},
    );
  } else if (firstOk) {
    c.block('C2.idem', 'DX3', '2.º refund idempotente', {
      'r1': r1.brief,
      'r2': r2.brief,
      'id1': id1,
      'id2': id2,
    });
  } else {
    c.skip('C2', 'DX3', '1.º seller refund não passou', r1);
  }

  // C3 refund∥release race
  final pRace = await mustPay('DX6');
  final balC0 = await c.walletBal(s1);
  final raced = await Future.wait([
    c.refundOrder(pRace.oid, jwt: c.sellerJwt),
    c.tryRelease(pRace.oid, jwt: c.buyerJwt),
    c.tryRelease(pRace.oid, jwt: c.sellerJwt),
  ]);
  final balC1 = await c.walletBal(s1);
  final refunded = raced[0].ok &&
      raced[0].map?['ok'] == true &&
      raced[0].map?['skipped'] != true;
  final released = raced[1].json == true || raced[2].json == true;
  final raceOpen = refunded && released && (balC1 - balC0) > 0;
  c.probe(
    id: 'C3',
    edgeRpc: 'refund-order ∥ batata_release_seller_wallet_for_order',
    payload: 'Future.wait refund seller + release buyer/seller no pago',
    http: raced.map((h) => h.brief).toList(),
    stripeBd: {
      'refunded': refunded,
      'released': released,
      'delta': balC1 - balC0,
      'pi': pRace.pi,
    },
    result: raceOpen ? 'FAIL' : 'HOLD',
    lens: 'DX6',
    countFinding: raceOpen,
    race: true,
  );
  if (raceOpen) {
    c.hold(
      id: 'DX-P0-C3-RACE',
      lens: 'DX6',
      severity: 'P0',
      title: 'race refund∥release: Stripe refund + crédito wallet',
      actor: 'seller refund + buyer/seller release paralelo',
      pre: 'release inelegível em pago',
      repro: 'Future.wait refund-order + release',
      expected: 'refund OU nada; release false; Δ≤0',
      obtained: {
        'hits': raced.map((h) => h.brief).toList(),
        'delta': balC1 - balC0,
      },
    );
  } else {
    c.block('C3.race', 'DX6', 'race pago sem crédito+refund simultâneo', {
      'refunded': refunded,
      'released': released,
      'delta': balC1 - balC0,
    });
  }

  // C4 webhook forge sem assinatura
  const fakeEvent = {
    'id': 'evt_rtdx_forge',
    'object': 'event',
    'type': 'checkout.session.completed',
    'data': {
      'object': {
        'id': 'cs_test_rtdx_forge',
        'object': 'checkout.session',
        'payment_status': 'paid',
        'amount_total': 99999,
        'metadata': {'order_id': '00000000-0000-4000-8000-000000000002'},
      },
    },
  };
  final noSig = await c.edge(
    'stripe-webhook',
    body: fakeEvent,
    extra: {'Origin': 'https://evil.com'},
  );
  final forged = await c.edge(
    'stripe-webhook',
    body: fakeEvent,
    extra: {
      'stripe-signature': 't=1,v1=deadbeefcafebabe',
      'Origin': 'https://evil.com',
    },
  );
  final whGet = await c.edge('stripe-webhook', method: 'GET');
  final forgedOk = noSig.ok || forged.ok;
  c.probe(
    id: 'C4',
    edgeRpc: 'stripe-webhook POST forge',
    payload:
        'POST sem stripe-signature + POST v1=deadbeef checkout.session.completed paid',
    http: {
      'no_sig': noSig.brief,
      'forged': forged.brief,
      'get': whGet.brief,
    },
    stripeBd: {
      'no_sig_acao': noSig.acao,
      'forged_acao': forged.acao,
    },
    result: forgedOk ? 'FAIL' : 'HOLD',
    lens: 'DX4',
    countFinding: forgedOk,
  );
  if (forgedOk) {
    c.hold(
      id: 'DX-P0-C4-WEBHOOK-FORGE',
      lens: 'DX4',
      severity: 'P0',
      title: 'webhook Stripe aceitou evento sem assinatura válida',
      actor: 'anon POST',
      pre: 'constructEventAsync exige whsec',
      repro: 'POST stripe-webhook sem sig / sig forjada',
      expected: '400 missing_signature / invalid_signature',
      obtained: {'no_sig': noSig.brief, 'forged': forged.brief},
    );
  } else {
    c.block('C4.sig', 'DX4', 'webhook recusa forge (400/401)', {
      'no_sig': noSig.status,
      'forged': forged.status,
      'get': whGet.status,
    });
  }

  // C5 CORS Origin evil / chrome-extension (classe_nova)
  const evil = 'https://evil.com';
  const ext = 'chrome-extension://abcdef123456';
  final optEvil = await c.edge(
    'create-payment-intent',
    method: 'OPTIONS',
    extra: {'Origin': evil},
  );
  final getEvil = await c.settleGet(
    'cs_test_rtdx_cors',
    extra: {'Origin': evil},
  );
  final optExt = await c.edge(
    'create-payment-intent',
    method: 'OPTIONS',
    extra: {'Origin': ext},
  );
  final postExt = await c.edge(
    'create-payment-intent',
    body: {'amount': 1},
    extra: {'Origin': ext},
    jwt: c.buyer2Jwt,
  );
  final optWh = await c.edge(
    'stripe-webhook',
    method: 'OPTIONS',
    extra: {'Origin': evil},
  );
  final optTip = await c.edge(
    'create-live-tip-checkout',
    method: 'OPTIONS',
    extra: {'Origin': evil},
  );
  final optRefund = await c.edge(
    'refund-order',
    method: 'OPTIONS',
    extra: {'Origin': ext},
  );
  final echoed = corsEchoes(optEvil, evil) ||
      corsEchoes(getEvil, evil) ||
      corsEchoes(optExt, ext) ||
      corsEchoes(postExt, ext) ||
      corsEchoes(optWh, evil) ||
      corsEchoes(optTip, evil) ||
      corsEchoes(optRefund, ext);
  c.probe(
    id: 'C5',
    edgeRpc: 'CORS OPTIONS/GET/POST Edge',
    payload:
        'Origin https://evil.com + chrome-extension://abcdef123456 em CPI / tip / refund / webhook',
    http: {
      'opt_evil': optEvil.brief,
      'get_evil': getEvil.brief,
      'opt_ext': optExt.brief,
      'post_ext': postExt.brief,
      'opt_wh': optWh.brief,
      'opt_tip': optTip.brief,
      'opt_refund': optRefund.brief,
    },
    stripeBd: {
      'acao_opt_evil': optEvil.acao,
      'acao_get_evil': getEvil.acao,
      'acao_opt_ext': optExt.acao,
      'acao_post_ext': postExt.acao,
      'acao_wh': optWh.acao,
      'acac_opt_evil': optEvil.acac,
    },
    result: echoed ? 'FAIL' : 'HOLD',
    lens: 'DX5',
    countFinding: echoed,
    classeNova: true,
  );
  if (echoed) {
    c.hold(
      id: 'DX-P2-C5-CORS-ECHO',
      lens: 'DX5',
      severity: 'P2',
      title: 'CORS ecoa Origin hostil (evil.com / chrome-extension)',
      actor: 'browser Origin header',
      pre: 'allowlist fleaber.pt; extensões nunca reflectir',
      repro: 'OPTIONS/GET Origin=https://evil.com | chrome-extension://',
      expected: 'ACAO ≠ Origin hostil (fleaber.pt ou omitido)',
      obtained: {
        'opt_evil': optEvil.acao,
        'get_evil': getEvil.acao,
        'opt_ext': optExt.acao,
        'post_ext': postExt.acao,
        'opt_wh': optWh.acao,
      },
    );
  } else {
    c.block('C5.cors', 'DX5', 'Origin hostil não ecoado', {
      'opt_evil': optEvil.acao,
      'get_evil': getEvil.acao,
      'opt_ext': optExt.acao,
      'post_ext': postExt.acao,
      'opt_wh': optWh.acao,
    });
  }
}

Future<void> runCaixa(Rtdx c, String s1) async {
  // D1 pago Stripe TEST (prova PI)
  final paid = await c.payToPago(lens: 'DX7');
  Map<String, dynamic>? row;
  if (paid != null) row = await c.orderRow(paid.oid);
  final isPago = paid != null &&
      c.orderPaid(row) &&
      '${row?['stripe_payment_intent_id'] ?? paid.pi ?? ''}'.startsWith('pi_');
  c.probe(
    id: 'D1',
    edgeRpc: 'sec-fase2-e2e-oversell setup_paid_order',
    payload: 'pago Stripe TEST real (PI succeeded) order=${paid?.oid}',
    http: paid == null ? 'setup_failed' : 'oid=${paid.oid} pi=${paid.pi}',
    stripeBd: {
      'oid': paid?.oid,
      'pid': paid?.pid,
      'pi': paid?.pi ?? row?['stripe_payment_intent_id'],
      'status': row?['status'],
      'amount_paid_cents': row?['amount_paid_cents'],
    },
    result: isPago ? 'HOLD' : 'SKIP',
    lens: 'DX7',
  );
  if (!isPago) {
    c.skip('D1', 'DX7', 'setup_paid_order não liquidou', {
      'paid': paid?.oid,
      'row': row,
    });
  } else {
    c.block('D1.pago', 'DX7', 'PI TEST succeeded; order pago', {
      'pi': paid.pi ?? row?['stripe_payment_intent_id'],
      'status': row?['status'],
    });
  }

  // D2 Connect transfer residual sem double
  await c.ensureWalletBalance(s1, 3);
  final t0 = await c.transferIds(s1);
  final bal0 = await c.walletBal(s1);
  const key = 'rtdx1738xfer01';
  final p100 = await c.connect({'amount': 100, 'idempotency_key': key});
  final raced = await Future.wait([
    c.connect({'amount': 100, 'idempotency_key': key}),
    c.connect({'amount': 500, 'idempotency_key': key}),
  ]);
  final t1 = await c.transferIds(s1);
  final newT = t1.difference(t0);
  final bal1 = await c.walletBal(s1);
  final doubled = newT.length >= 2 || (bal0 - bal1) >= 5;
  c.probe(
    id: 'D2',
    edgeRpc: 'create-connect-account',
    payload:
        'key $key amount 100 depois ∥ 100+500 (residual Connect sem double)',
    http: {
      'p100': p100.brief,
      'r100': raced[0].brief,
      'r500': raced[1].brief,
    },
    stripeBd: {
      'new_tr': newT.toList(),
      'delta': bal1 - bal0,
      'idempotent': raced[0].map?['idempotent'] ?? raced[1].map?['idempotent'],
    },
    result: doubled ? 'FAIL' : 'HOLD',
    lens: 'DX7',
    countFinding: doubled,
    race: true,
  );
  if (doubled) {
    c.hold(
      id: 'DX-P0-D2-CONNECT-DOUBLE',
      lens: 'DX7',
      severity: 'P0',
      title: 'Connect mesma key criou 2 Transfers / debitou a mais',
      actor: 'seller JWT',
      pre: 'idempotency canónica por user+key',
      repro: 'POST connect key K 100 depois paralelo 100∥500',
      expected: '1 Transfer; 2.º idempotent',
      obtained: {
        'p100': p100.brief,
        'raced': raced.map((h) => h.brief).toList(),
        'new_tr': newT.toList(),
        'delta': bal1 - bal0,
      },
    );
  } else {
    c.block('D2.idem', 'DX7', 'Connect sem double Transfer', {
      'n_tr': newT.length,
      'delta': bal1 - bal0,
      'p100': p100.brief,
    });
  }
}
