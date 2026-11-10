/// RED TEAM CEGO FC — smoke disputa / refund / settle / tip PRE-P4.
/// Staging only. Stripe TEST. NÃO CORRIGIR. Fase 4 não.
/// Anti-atrofia: NÃO tip seller≠owner · NÃO Coptic charset.
import 'dart:io';
import '_rtfc.dart';

bool looksPaidCopy(HttpHit? h) {
  final t = (h?.body ?? '').toLowerCase();
  return t.contains('pagamento recebido') ||
      t.contains('pagamento confirmado') ||
      t.contains('"status":"pago"') ||
      t.contains('gorjeta registada') ||
      t.contains('gorjeta conclu');
}

bool corsEchoes(HttpHit h, String origin) {
  final a = (h.acao ?? '').trim();
  if (a.isEmpty) return false;
  if (a == origin) return true;
  if (origin == 'null' && a.toLowerCase() == 'null') return true;
  if (origin.startsWith('chrome-extension://') &&
      a.startsWith('chrome-extension://')) {
    return true;
  }
  if (origin.contains('evil.com') && a.contains('evil.com')) return true;
  return false;
}

Future<({String oid, String pid, String? pi})> mustPay(
  Rtfc c,
  String lens,
) async {
  final paid = await c.payToPago(lens: lens);
  if (paid == null) throw StateError('setup_paid_order failed $lens');
  return paid;
}

Future<void> main() async {
  final c = Rtfc.fromEnv(loadEnv());
  stdout.writeln('FC pass1 staging=${c.url} prefix=$prefix');
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.restoreSeller1Published();
  if (c.seller2Id != null) {
    await c.rest('PATCH', 'profiles?id=eq.${c.seller2Id}', service: true, body: {
      'hub_published': false,
    }, prefer: 'return=minimal');
  }

  final s1 = c.sellerId!;
  final s2 = c.seller2Id!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;
  stdout.writeln('actors B1=$b1 S1=$s1 B2=$b2 S2=$s2');
  c.skipped.add({
    'id': 'HOLD-anti-atrofia',
    'title': 'tip seller≠owner · Coptic charset — não corridos / não contar',
  });

  try {
    await runDispute(c, s1);
    await runRefundSettle(c, s1, b1, b2);
    await runTipEdge(c, s1, b1, b2);
  } catch (e, st) {
    stderr.writeln('FC abort: $e\n$st');
    c.note('abort', 'uncaught', '$e');
  } finally {
    await c.endLives();
    await c.restoreSeller1Published();
    await c.dumpAll('pass1.json');
    stdout.writeln(
        'probes=${c.probes.length} findings=${c.findings.length} nova=${c.classeNova.length}');
  }
}

Future<void> runDispute(Rtfc c, String s1) async {
  // A1 release∥disputa t=0 → 1 efeito líquido (não crédito+claim)
  final pay0 = await mustPay(c, 'FC-A');
  await c.markConcluidoMao(pay0.oid);
  final r0 = await c.raceReleaseDispute(pay0.oid, delayMs: 0);
  final or0 = await c.oracleWalletDispute(pay0.oid, s1);
  final both0 = or0['both'] == true;
  c.probe(
    id: 'A1',
    lens: 'FC-A',
    edgeRpc: 'release∥disputa t=0',
    payload: 'Future.wait release + disputa oid ${pay0.oid} PI ${pay0.pi}',
    http: 'rel ${r0[0].brief} | disp ${r0[1].brief}',
    stripeBd: or0,
    result: both0 ? 'FAIL' : 'HOLD',
    classeNova: true,
    race: true,
    countFinding: both0,
  );
  if (both0) {
    c.hold(
      id: 'FC-P0-A1-RELEASE-DISPUTE-0MS',
      lens: 'FC-A',
      severity: 'P0',
      title: 'release∥disputa t=0 crédito líquido + claim aberto',
      actor: 'buyer JWT',
      pre: '1 efeito líquido (clawback / só disputa / só release sem claim)',
      repro: 'Future.wait batata_release_seller_wallet_for_order ∥ INSERT disputa t=0',
      expected: 'both=false (net≤0 OU sem claim aberto)',
      obtained: or0,
    );
  } else {
    c.block('A1.race-0ms', 'FC-A', 't=0 both=false net=${or0['net']} open=${or0['open_n']}', or0);
  }

  // A2 release∥disputa t=50 dispute-first → 1 efeito
  final pay50 = await mustPay(c, 'FC-A');
  await c.markConcluidoMao(pay50.oid);
  final r50 = await c.raceReleaseDispute(
    pay50.oid,
    delayMs: 50,
    disputeFirst: true,
  );
  final or50 = await c.oracleWalletDispute(pay50.oid, s1);
  final both50 = or50['both'] == true;
  c.probe(
    id: 'A2',
    lens: 'FC-A',
    edgeRpc: 'release∥disputa t=50 dispute-first',
    payload: 'INSERT disputa first →50ms→ release oid ${pay50.oid} PI ${pay50.pi}',
    http: 'disp ${r50[0].brief} | rel ${r50[1].brief}',
    stripeBd: or50,
    result: both50 ? 'FAIL' : 'HOLD',
    classeNova: true,
    race: true,
    countFinding: both50,
  );
  if (both50) {
    c.hold(
      id: 'FC-P0-A2-RELEASE-DISPUTE-50MS',
      lens: 'FC-A',
      severity: 'P0',
      title: 'release∥disputa t=50 crédito líquido + claim aberto',
      actor: 'buyer JWT',
      pre: '1 efeito líquido',
      repro: 'Future.wait disputa first + release delay 50ms',
      expected: 'both=false',
      obtained: or50,
    );
  } else {
    c.block('A2.race-50ms', 'FC-A', 't=50 both=false net=${or50['net']} open=${or50['open_n']}', or50);
  }

  // A3 disputa após enviado — documentar allow/deny (finding só se mint)
  final payEnv = await mustPay(c, 'FC-A');
  await c.markEnviado(payEnv.oid);
  final rowEnvBefore = await c.orderRow(payEnv.oid);
  final wBefore = await c.walletBal(s1);
  final dispEnv = await c.insertDispute(
    orderId: payEnv.oid,
    description: '$prefix disputa após enviado',
  );
  final rowEnvAfter = await c.orderRow(payEnv.oid);
  final orEnv = await c.oracleWalletDispute(payEnv.oid, s1);
  final wAfter = await c.walletBal(s1);
  final dW = wAfter - wBefore;
  final minted = dW > 0.01 || (orEnv['net'] as num) > 0.01;
  final window = dispEnv.status == 201
      ? 'ALLOW'
      : (dispEnv.denied ? 'DENY' : 'OTHER');
  c.probe(
    id: 'A3',
    lens: 'FC-A',
    edgeRpc: 'POST order_disputes após status=enviado',
    payload: 'oid ${payEnv.oid} st=${rowEnvBefore?['status']} PI ${payEnv.pi}',
    http: dispEnv.brief,
    stripeBd: {
      'window': window,
      'status_before': rowEnvBefore?['status'],
      'status_after': rowEnvAfter?['status'],
      'Δwallet': dW,
      'oracle': orEnv,
    },
    result: minted ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: minted,
  );
  if (minted) {
    c.hold(
      id: 'FC-P0-A3-DISPUTE-ENVIADO-MINT',
      lens: 'FC-A',
      severity: 'P0',
      title: 'disputa em enviado mintou wallet',
      actor: 'buyer JWT',
      pre: 'janela enviado allow/deny documentada; sem mint',
      repro: 'PATCH enviado; POST order_disputes',
      expected: 'Δwallet=0',
      obtained: {'window': window, 'Δ': dW, 'oracle': orEnv},
    );
  } else {
    c.block('A3.window-enviado', 'FC-A', 'janela $window Δ=0', {
      'http': dispEnv.status,
      'window': window,
      'Δ': dW,
    });
  }
}

Future<void> runRefundSettle(
  Rtfc c,
  String s1,
  String b1,
  String b2,
) async {
  // B1 buyer refund 403 + B2 seller 2× mesma order → 1 re_
  final payRef = await mustPay(c, 'FC-B');
  final buyerRef = await c.refundOrder(payRef.oid, jwt: c.buyerJwt);
  final sel1 = await c.refundOrder(payRef.oid, jwt: c.sellerJwt);
  final sel2 = await c.refundOrder(payRef.oid, jwt: c.sellerJwt);
  final rowRef = await c.orderRow(payRef.oid);
  final reIds = {
    sel1.map?['refundId'] ?? sel1.map?['refund_id'],
    sel2.map?['refundId'] ?? sel2.map?['refund_id'],
    rowRef?['stripe_refund_id'],
  }.where((e) => '$e'.startsWith('re_')).map((e) => '$e').toSet();
  final buyerOk = buyerRef.status == 200;
  c.probe(
    id: 'B1',
    lens: 'FC-B',
    edgeRpc: 'refund-order JWT comprador',
    payload: 'POST refund-order oid ${payRef.oid} PI ${payRef.pi}',
    http: buyerRef.brief,
    stripeBd: 'st=${rowRef?['status']} re=${rowRef?['stripe_refund_id']}',
    result: buyerOk ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: buyerOk,
  );
  if (buyerOk) {
    c.hold(
      id: 'FC-P0-B1-BUYER-REFUND',
      lens: 'FC-B',
      severity: 'P0',
      title: 'Buyer refund-order aberto',
      actor: 'buyer JWT',
      pre: 'seller-only',
      repro: 'POST refund-order JWT comprador',
      expected: '403',
      obtained: buyerRef.brief,
    );
  } else {
    c.block('B1.buyer-403', 'FC-B', 'buyer ${buyerRef.status}', buyerRef);
  }

  final doubleRe = reIds.length > 1;
  c.probe(
    id: 'B2',
    lens: 'FC-B',
    edgeRpc: 'refund-order seller 2× mesma order',
    payload: 'seller JWT 2× oid ${payRef.oid}',
    http: 's1 ${sel1.brief} | s2 ${sel2.brief}',
    stripeBd: 're_ n=${reIds.length} $reIds',
    result: doubleRe ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: doubleRe,
  );
  if (doubleRe) {
    c.hold(
      id: 'FC-P0-B2-REFUND-DUP',
      lens: 'FC-B',
      severity: 'P0',
      title: 'seller refund 2× criou >1 re_',
      actor: 'seller JWT',
      pre: 'idempotency 1 refund / order',
      repro: 'POST refund-order seller 2×',
      expected: '1 re_',
      obtained: reIds.toList(),
    );
  } else {
    c.block('B2.seller-2x', 'FC-B', '1 re_ em 2× n=${reIds.length}', reIds.toList());
  }

  // B3 settle session unpaid → 402 / sem Δwallet
  const price = 12.0;
  final pidA = await c.createProduct(
    seller: s1,
    title: '$prefix settle-A',
    qty: 3,
    price: price,
  );
  final pidB = await c.createProduct(
    seller: s1,
    title: '$prefix settle-B',
    qty: 3,
    price: price,
  );
  if (pidA == null || pidB == null) {
    c.skip('B3/B4', 'FC-B', 'SKU fixture falhou', {'a': pidA, 'b': pidB});
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
    c.skip('B3/B4', 'FC-B', 'order fixture falhou', {'a': oidA, 'b': oidB});
    return;
  }
  final ckA = await c.checkout(
    orderId: oidA,
    jwt: c.buyer2Jwt,
    buyer: b2,
    amount: 1,
    productId: pidA,
    seller: s1,
  );
  final sidA = ckA.sessionId;
  final wB3a = await c.walletBal(s1);
  HttpHit getUnpaid = HttpHit(0, 'no sid', {'error': 'no sid'});
  HttpHit postUnpaid = HttpHit(0, 'no sid', {'error': 'no sid'});
  if (sidA != null) {
    getUnpaid = await c.settleGet(sidA, jwt: c.buyer2Jwt);
    postUnpaid = await c.settlePost(
      sidA,
      jwt: c.buyer2Jwt,
      body: {
        'checkout_return': 'success',
        'session_id': sidA,
        'amount': 1,
        'payment_status': 'paid',
      },
    );
  }
  final wB3b = await c.walletBal(s1);
  final rowA = await c.orderRow(oidA);
  final unpaidPaid = c.orderPaid(rowA) ||
      looksPaidCopy(getUnpaid) ||
      looksPaidCopy(postUnpaid) ||
      (wB3b - wB3a) > 0.01;
  c.probe(
    id: 'B3',
    lens: 'FC-B',
    edgeRpc: 'GET/POST settle Session unpaid',
    payload: 'sid=$sidA oidA=$oidA GET+POST checkout_return=success',
    http: 'GET ${getUnpaid.brief} | POST ${postUnpaid.brief} | CPI ${ckA.brief}',
    stripeBd:
        'st=${rowA?['status']} Δ=${wB3b - wB3a} paid_cents=${rowA?['amount_paid_cents']}',
    result: unpaidPaid ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: unpaidPaid,
  );
  if (unpaidPaid) {
    c.hold(
      id: 'FC-P0-B3-SETTLE-UNPAID',
      lens: 'FC-B',
      severity: 'P0',
      title: 'settle unpaid creditou / marcou pago',
      actor: 'B2 JWT',
      pre: 'Session unpaid 402 / sem Δwallet',
      repro: 'GET/POST create-payment-intent checkout_return=success unpaid',
      expected: '402/400; reserva_pendente Δ=0',
      obtained: {
        'get': getUnpaid.brief,
        'post': postUnpaid.brief,
        'st': rowA?['status'],
        'Δ': wB3b - wB3a,
      },
    );
  } else {
    c.block('B3.settle-unpaid', 'FC-B', 'GET ${getUnpaid.status} POST ${postUnpaid.status} Δ=0', {
      'st': rowA?['status'],
    });
  }

  // B4 settle session alheia → deny (sem credit)
  HttpHit getAlien = HttpHit(0, 'no sid', {'error': 'no sid'});
  HttpHit postAlien = HttpHit(0, 'no sid', {'error': 'no sid'});
  if (sidA != null) {
    getAlien = await c.settleGet(sidA, jwt: c.buyerJwt, extraQs: 'order_id=$oidB');
    postAlien = await c.settlePost(
      sidA,
      jwt: c.buyerJwt,
      body: {
        'checkout_return': 'success',
        'session_id': sidA,
        'order_id': oidB,
        'buyer_id': b1,
      },
    );
  }
  final ckAlien = await c.checkout(
    orderId: oidB,
    jwt: c.buyerJwt,
    buyer: b1,
    amount: 1,
    productId: pidB,
    extra: {
      if (sidA != null) 'session_id': sidA,
      if (sidA != null) 'checkout_session_id': sidA,
      'order_id': oidA,
    },
  );
  final rowA4a = await c.orderRow(oidA);
  final rowA4b = await c.orderRow(oidB);
  final alienPaid = c.orderPaid(rowA4a) || c.orderPaid(rowA4b);
  c.probe(
    id: 'B4',
    lens: 'FC-B',
    edgeRpc: 'GET/POST settle session alheia + CPI inject sidA→oidB',
    payload: 'sidA (B2) JWT B1 order_id=oidB; CPI oidB session_id=sidA',
    http:
        'GET ${getAlien.brief} | POST ${postAlien.brief} | CPI ${ckAlien.brief}',
    stripeBd:
        'A ${rowA4a?['status']} B ${rowA4b?['status']} sidB=${ckAlien.sessionId}',
    result: alienPaid ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: alienPaid,
  );
  if (alienPaid) {
    c.hold(
      id: 'FC-P0-B4-SESSION-ALHEIA',
      lens: 'FC-B',
      severity: 'P0',
      title: 'settle session alheia marcou pago noutra order/buyer',
      actor: 'B1 JWT',
      pre: 'Session alheia não liquida outra order',
      repro: 'GET/POST sidA JWT B1; CPI oidB com session_id=sidA',
      expected: '402/400; ambas reserva_pendente',
      obtained: {
        'A': rowA4a?['status'],
        'B': rowA4b?['status'],
      },
    );
  } else {
    c.block('B4.session-alheia', 'FC-B', 'A/B pendente GET ${getAlien.status}', {
      'A': rowA4a?['status'],
      'B': rowA4b?['status'],
    });
  }

  // D1 extra classe_nova: refund∥release → net=0
  final payD1 = await mustPay(c, 'FC-B');
  final wD1a = await c.walletBal(s1);
  final raced = await Future.wait([
    c.refundOrder(payD1.oid, jwt: c.sellerJwt),
    c.tryRelease(payD1.oid, jwt: c.buyerJwt),
  ]);
  final wD1b = await c.walletBal(s1);
  final orD1 = await c.oracleWalletDispute(payD1.oid, s1);
  final d1Net = (wD1b - wD1a) > 0.01 || (orD1['net'] as num) > 0.01;
  c.probe(
    id: 'D1',
    lens: 'FC-B',
    edgeRpc: 'refund-order ∥ release',
    payload: 'Future.wait seller refund + buyer release oid ${payD1.oid}',
    http: 'ref ${raced[0].brief} | rel ${raced[1].brief}',
    stripeBd: 'Δ=${wD1b - wD1a} net=${orD1['net']} re=${orD1['refund_id']}',
    result: d1Net ? 'FAIL' : 'HOLD',
    classeNova: true,
    race: true,
    countFinding: d1Net,
  );
  if (d1Net) {
    c.hold(
      id: 'FC-P0-D1-REFUND-RELEASE',
      lens: 'FC-B',
      severity: 'P0',
      title: 'refund∥release criou crédito líquido',
      actor: 'seller+buyer JWT',
      pre: 'refund anula; release false; Δ=0',
      repro: 'Future.wait refund∥release',
      expected: 'Δwallet=0',
      obtained: orD1,
    );
  } else {
    c.block('D1.refund-release', 'FC-B', 'Δ=0 net=${orD1['net']}', orD1);
  }
}

Future<void> runTipEdge(Rtfc c, String s1, String b1, String b2) async {
  // C1 tip Session unpaid GET settle → Δwallet=0
  final liveId = await c.insertLive(seller: s1, title: '$prefix tip live');
  if (liveId == null) {
    c.skip('C1', 'FC-C', 'insertLive falhou', null);
  } else {
    final tip = await c.tipCheckout(
      liveId: liveId,
      seller: s1,
      amountEur: 2,
      jwt: c.buyer2Jwt,
    );
    final sid = tip.sessionId;
    final tid = tip.tipId;
    final w0 = await c.walletBal(s1);
    HttpHit getTip = HttpHit(0, 'no sid', {'error': 'no sid'});
    if (sid != null) {
      getTip = await c.tipSettleGet(sid, jwt: c.buyer2Jwt);
    }
    final tipAfter = tid == null ? null : await c.tipRow(tid);
    final w1 = await c.walletBal(s1);
    final dTip = w1 - w0;
    final credited = '${tipAfter?['status']}' == 'paid' || dTip > 0.001;
    c.probe(
      id: 'C1',
      lens: 'FC-C',
      edgeRpc: 'tip unpaid GET settle Δwallet',
      payload: 'GET checkout_return=success sid=$sid tip=$tid live=$liveId',
      http: 'POST ${tip.brief} | GET ${getTip.brief}',
      stripeBd: 'tip ${tipAfter?['status']} Δ=$dTip',
      result: credited ? 'FAIL' : 'HOLD',
      classeNova: true,
      countFinding: credited,
    );
    if (credited) {
      c.hold(
        id: 'FC-P0-C1-TIP-UNPAID',
        lens: 'FC-C',
        severity: 'P0',
        title: 'GET settle tip unpaid creditou wallet',
        actor: 'B2 JWT',
        pre: 'Session unpaid nunca credita',
        repro: 'POST tip + GET create-live-tip-checkout unpaid',
        expected: 'pending Δ=0',
        obtained: {'tip': tipAfter, 'Δ': dTip, 'get': getTip.brief},
      );
    } else {
      c.block('C1.tip-unpaid', 'FC-C', 'pending Δ=0 GET ${getTip.status}', {
        'status': tipAfter?['status'],
        'Δ': dTip,
      });
    }
  }

  // C2 webhook sem assinatura → deny sem side-effect
  final bodyPaid = {
    'id': 'evt_rtfc_0924_nosig',
    'object': 'event',
    'type': 'checkout.session.completed',
    'livemode': true,
    'data': {
      'object': {
        'id': 'cs_test_rtfc_nosig',
        'object': 'checkout.session',
        'payment_status': 'paid',
        'amount_total': 99999,
        'metadata': {'order_id': '00000000-0000-0000-0000-000000000001'},
      }
    }
  };
  final noSig = await c.stripeWebhookForge(bodyPaid);
  final dead =
      't=${DateTime.now().millisecondsSinceEpoch ~/ 1000},v1=deadbeefdeadbeef';
  final deadHit = await c.stripeWebhookForge(bodyPaid, signature: dead);
  final forged = noSig.ok || deadHit.ok;
  c.probe(
    id: 'C2',
    lens: 'FC-C',
    edgeRpc: 'stripe-webhook sem assinatura + sig morta',
    payload: 'checkout.session.completed paid livemode=true sem sig / v1=deadbeef',
    http: 'nosig ${noSig.brief} | dead ${deadHit.brief}',
    stripeBd: '—',
    result: forged ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: forged,
  );
  if (forged) {
    c.hold(
      id: 'FC-P0-C2-WEBHOOK-FORGE',
      lens: 'FC-C',
      severity: 'P0',
      title: 'webhook aceitou forge sem assinatura',
      actor: 'anon POST',
      pre: 'constructEventAsync exige whsec',
      repro: 'POST stripe-webhook sem stripe-signature',
      expected: '400 missing/invalid_signature',
      obtained: {'nosig': noSig.brief, 'dead': deadHit.brief},
    );
  } else {
    c.block('C2.webhook', 'FC-C', 'nosig ${noSig.status} dead ${deadHit.status}', {
      'nosig': noSig.status,
      'dead': deadHit.status,
    });
  }

  // C3 CORS Origin evil em CPI ou refund — sem eco perigoso
  const evil = 'https://evil.com';
  final corsHits = <String, HttpHit>{
    'opt_evil_cpi': await c.edge(
      'create-payment-intent',
      method: 'OPTIONS',
      extra: {'Origin': evil},
    ),
    'opt_evil_refund': await c.edge(
      'refund-order',
      method: 'OPTIONS',
      extra: {'Origin': evil},
    ),
    'post_evil_cpi': await c.edge(
      'create-payment-intent',
      extra: {'Origin': evil},
      body: {'order_id': 'x'},
      jwt: c.buyerJwt,
    ),
    'post_evil_refund': await c.edge(
      'refund-order',
      extra: {'Origin': evil},
      body: {'order_id': 'x'},
      jwt: c.buyerJwt,
    ),
  };
  final echoes = <String>[];
  for (final e in corsHits.entries) {
    if (corsEchoes(e.value, evil)) echoes.add('${e.key}=${e.value.acao}');
  }
  c.probe(
    id: 'C3',
    lens: 'FC-C',
    edgeRpc: 'CORS Origin evil CPI/refund',
    payload: 'OPTIONS+POST Origin=https://evil.com CPI e refund-order',
    http: corsHits.map((k, v) => MapEntry(k, '${v.status} acao=${v.acao}')),
    stripeBd: 'echoes=$echoes',
    result: echoes.isNotEmpty ? 'FAIL' : 'HOLD',
    classeNova: true,
    countFinding: echoes.isNotEmpty,
  );
  if (echoes.isNotEmpty) {
    c.hold(
      id: 'FC-P2-C3-CORS-ECHO',
      lens: 'FC-C',
      severity: 'P2',
      title: 'CORS ecoa Origin evil.com',
      actor: 'browser Origin',
      pre: 'allowlist fleaber.pt; não ecoar evil',
      repro: 'OPTIONS/POST Origin=https://evil.com CPI ou refund-order',
      expected: 'ACAO ≠ https://evil.com',
      obtained: echoes,
    );
  } else {
    c.block('C3.cors-evil', 'FC-C', 'não ecoa evil.com', {
      for (final e in corsHits.entries) e.key: e.value.acao,
    });
  }
}
