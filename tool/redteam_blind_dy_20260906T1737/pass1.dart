/// RED TEAM CEGO DY pass1 — composição multi-superfície ≥18.
/// Staging only. NÃO corrigir. NÃO produção. NÃO Fase 4.
/// Cruzamentos novos vs DS: follow+favorite+hold · rifa∥CPI no draw ·
/// live_only prize · oferta+bundle Session · disputa+release+stock · rifa+bag+Hub.
import 'dart:io';
import '_rtdy.dart';

Future<void> main() async {
  final c = Rtdy.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final s1 = c.sellerId!;
  final s2 = c.seller2Id!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;

  await c.restoreSeller1Published();
  await c.setHub(s2, false);
  await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'user_type': 'vendedor',
    'handle': 'rtdy1737s2',
  }, prefer: 'return=minimal');

  c.note('fix.s1', 'S1 published', await c.profile(s1), lens: 'DY1');
  c.note('fix.s2', 'S2 unpublished', await c.profile(s2), lens: 'DY1');

  try {
    await runA(c, s1: s1, b1: b1, b2: b2);
    await runB(c, s1: s1, b1: b1, b2: b2);
    await runC(c, s1: s1, b1: b1, b2: b2);
    await runD(c, s1: s1, b1: b1, b2: b2);
  } finally {
    await c.endAllCreatedLives();
    await c.restoreSeller1Published();
    final after = await c.profile(s1);
    c.note('restore.s1', 'S1 hub_published after', after?['hub_published'],
        lens: 'DY1');
    for (final rid in c.createdRaffleIds) {
      await c.rest(
        'PATCH',
        'live_raffles?id=eq.$rid',
        service: true,
        body: {'status': 'closed'},
        prefer: 'return=minimal',
      );
    }
  }

  await dumpJson('${outDir()}/pass1.json', {
    'auditor': 'REDTEAM_BLIND_DY_COMPOSICAO_POS_DNDS_v1',
    'prefix': prefix,
    'staging': projectMust,
    'probes': c.probes,
    'findings': c.findings,
    'blocked': c.blocked,
    'skipped': c.skipped,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
    'classe_nova': c.classeNova.toList()..sort(),
    'actors': {'b1': b1, 's1': s1, 'b2': b2, 's2': s2},
    'created': {
      'products': c.createdProductIds,
      'orders': c.createdOrderIds,
      'lives': c.createdLiveIds,
      'items': c.createdLiveItemIds,
      'res': c.createdResIds,
      'tips': c.createdTipIds,
      'offers': c.createdOfferIds,
      'bundles': c.createdBundleIds,
      'raffles': c.createdRaffleIds,
      'follows': c.createdFollowIds,
      'favs': c.createdFavIds,
    },
  });
  stdout.writeln('WROTE ${outDir()}/pass1.json probes=${c.probes.length} '
      'findings=${c.findings.length} nova=${c.classeNova.length}');
}

Future<void> runA(
  Rtdy c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // ----- A1 unpublish mid-checkout AND mid-tip + payout -----
  final skuA1 = await c.createProduct(
    title: '$prefix A1 mkt',
    qty: 2,
    listed: true,
    live: false,
  );
  final liveA1 = await c.createLive(title: '$prefix A1 air');
  String? oidA1;
  HttpHit? cpiBefore;
  HttpHit? cpiAfter;
  HttpHit? tipCreate;
  HttpHit? tipGet;
  HttpHit? payoutUnpub;
  Map<String, dynamic>? hubAnonMid;
  Map<String, dynamic>? hubJwtMid;
  Map<String, dynamic>? profMid;
  String? tipId;
  String? tipSid;
  final wSeller0 = await c.walletBal(s1);

  if (skuA1 != null) {
    oidA1 = await c.insertOrder(
      productId: skuA1,
      jwt: c.buyerJwt,
      price: 12.0,
    );
    if (oidA1 != null) {
      cpiBefore = await c.checkout(
        orderId: oidA1,
        productId: skuA1,
        jwt: c.buyerJwt,
      );
      if (c.usefulCs(cpiBefore)) {
        c.createdSessionIds.add(cpiBefore.sessionId!);
      }
    }
  }
  if (liveA1 != null) {
    tipCreate = await c.tipCheckout(liveId: liveA1, seller: s1, amountEur: 2);
    tipId = tipCreate.tipId;
    tipSid = tipCreate.sessionId;
    if (tipId != null) c.createdTipIds.add(tipId);
    if (c.usefulCs(tipCreate)) c.createdSessionIds.add(tipCreate.sessionId!);
  }

  final unpub = await c.rpc(
    'batata_publish_hub',
    {'p_publish': false},
    jwt: c.sellerJwt,
  );
  profMid = await c.profile(s1);
  if (skuA1 != null) {
    final ha = await c.hubSku(skuA1, anon: true);
    final hj = await c.hubSku(skuA1, jwt: c.buyerJwt);
    hubAnonMid = {'status': ha.status, 'n': ha.list.length};
    hubJwtMid = {'status': hj.status, 'n': hj.list.length};
  }
  if (oidA1 != null && skuA1 != null) {
    cpiAfter = await c.checkout(
      orderId: oidA1,
      productId: skuA1,
      jwt: c.buyerJwt,
    );
  }
  if (tipSid != null && tipSid.isNotEmpty) {
    tipGet = await c.tipSettleGet(tipSid, jwt: c.buyer2Jwt);
  }
  payoutUnpub = await c.connectPayout({
    'amount': 100,
    'idempotency_key': 'rtdy1737unpubpay',
  });
  final wSellerMid = await c.walletBal(s1);

  var tipStatus = '';
  var tipCredited = false;
  if (tipId != null) {
    final row = await c.rest(
      'GET',
      'live_tips?id=eq.$tipId&select=id,status,amount',
      service: true,
    );
    tipStatus = '${row.map?['status'] ?? ''}';
    tipCredited = tipStatus == 'paid' || tipStatus == 'settled';
  }

  await c.restoreSeller1Published();
  final afterPub = await c.profile(s1);
  final led = await c.payoutLedger(s1, limit: 6);

  final unpubOk = profMid?['hub_published'] == false;
  final hubGone = (hubAnonMid?['n'] == 0) && (hubJwtMid?['n'] == 0);
  final payoutStole = payoutUnpub.payoutOk && (wSellerMid - wSeller0) < -0.5;
  // Tip mint without paid settle = P0. Payout of existing Connect balance
  // while unpublished = HOLD anti-atrophy (DS retract), not mint.
  String a1result;
  if (!unpubOk) {
    a1result = 'SKIP';
    c.skip('A1', 'DY1', 'unpublish RPC não pegou', unpub);
  } else if (tipCredited) {
    a1result = 'HOLD';
    c.hold(
      id: 'P0-A1-TIP',
      lens: 'DY4',
      severity: 'P0',
      title: 'Tip creditada após unpublish sem settle pago',
      actor: 'B2 tip GET',
      pre: 'loja unpublished a meio do checkout e da gorjeta',
      repro: 'unpublish + tip GET unpaid',
      expected: 'tip pending',
      obtained: {
        'tip': tipStatus,
        'get': tipGet?.brief,
        'payout': payoutUnpub.brief,
      },
    );
  } else {
    a1result = 'FAIL';
    c.block('A1', 'DY1', 'unpublish mid-CPI+tip; tip unpaid; payout observado', {
      'hub_gone': hubGone,
      'tip': tipStatus,
      'payout': payoutUnpub.status,
      'dWallet': wSellerMid - wSeller0,
      'payoutOk': payoutUnpub.payoutOk,
      'note': payoutStole
          ? 'payout debitou saldo existente (não mint) — anti-atrofia'
          : 'payout sem débito anómalo',
    });
  }
  c.probe(
    id: 'A1',
    surfaces: 'Hub + CPI + tip + wallet/payout',
    action: 'unpublish mid-checkout E mid-tip + payout unpublished',
    http: {
      'unpub': unpub.brief,
      'cpiBefore': cpiBefore?.brief,
      'cpiAfter': cpiAfter?.brief,
      'tip': tipCreate?.brief,
      'payout': payoutUnpub.brief,
    },
    oracles: {
      'hub_anon_n': hubAnonMid?['n'],
      'hub_jwt_n': hubJwtMid?['n'],
      'published_mid': profMid?['hub_published'],
      'published_after': afterPub?['hub_published'],
      'tip': tipStatus,
      'dWallet': wSellerMid - wSeller0,
      'payoutOk': payoutUnpub.payoutOk,
      'led_n': led.length,
    },
    result: a1result,
    lens: 'DY1',
    classeNova: true,
    countFinding: a1result == 'HOLD',
  );

  // ----- A2 sold+listed vs Hub vs insert (residual) -----
  final skuA2 = await c.createProduct(
    title: '$prefix A2 sold-listed',
    qty: 1,
    listed: true,
    sold: true,
    live: false,
  );
  HttpHit? hubA2;
  HttpHit? insA2;
  Map<String, dynamic>? prodA2;
  if (skuA2 != null) {
    prodA2 = await c.productRow(skuA2);
    hubA2 = await c.hubSku(skuA2, anon: true);
    insA2 = await c.insertOrderHit(
      productId: skuA2,
      jwt: c.buyerJwt,
      price: 12.0,
    );
  }
  final hubShowsSold = (hubA2?.list.length ?? 0) > 0;
  final insertOkSold = insA2 != null && insA2.ok;
  String a2result;
  if (skuA2 == null) {
    a2result = 'SKIP';
    c.skip('A2', 'DY1', 'sku A2 fail', 'null');
  } else if (hubShowsSold && insertOkSold) {
    a2result = 'HOLD';
    c.hold(
      id: 'P2-A2-SOLD-HUB',
      lens: 'DY1',
      severity: 'P2',
      title: 'SKU sold+listed visível no Hub e insert aceite',
      actor: 'anon Hub + B1 insert',
      pre: 'is_sold=true list_on_marketplace=true qty=1',
      repro: 'hub_products_public + POST orders',
      expected: 'Hub 0; insert deny',
      obtained: {'hub_n': hubA2?.list.length, 'ins': insA2?.brief, 'row': prodA2},
    );
  } else {
    a2result = 'FAIL';
    c.block('A2', 'DY1', 'sold+listed: Hub/insert observados', {
      'hub_n': hubA2?.list.length,
      'ins': insA2?.brief,
      'sold': prodA2?['is_sold'],
      'listed': prodA2?['list_on_marketplace'],
    });
  }
  c.probe(
    id: 'A2',
    surfaces: 'Hub + products + orders',
    action: 'sold+listed vs vitrine vs insert',
    http: {'hub': hubA2?.brief, 'ins': insA2?.brief},
    oracles: {
      'hub_n': hubA2?.list.length,
      'ins_ok': insertOkSold,
      'sold': prodA2?['is_sold'],
    },
    result: a2result,
    lens: 'DY1',
    residual: true,
    countFinding: a2result == 'HOLD',
  );

  // ----- A3 leftover após pago parcial -----
  final paidA3 = await c.payToPago(lens: 'DY1', initialQty: 2);
  HttpHit? hubA3;
  HttpHit? cpiA3;
  Map<String, dynamic>? prodA3;
  Map<String, dynamic>? ordA3;
  String? oidLeft;
  if (paidA3 != null) {
    ordA3 = await c.orderRow(paidA3.oid);
    prodA3 = await c.productRow(paidA3.pid);
    hubA3 = await c.hubSku(paidA3.pid, jwt: c.buyerJwt);
    oidLeft = await c.insertOrder(
      productId: paidA3.pid,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 12.0,
    );
    if (oidLeft != null) {
      cpiA3 = await c.checkout(
        orderId: oidLeft,
        productId: paidA3.pid,
        jwt: c.buyer2Jwt,
        buyer: b2,
      );
      if (c.usefulCs(cpiA3)) c.createdSessionIds.add(cpiA3.sessionId!);
    }
  }
  final leftoverBuyable = c.usefulCs(cpiA3);
  final qtyA3 = numOf(prodA3?['quantity']) ?? -1;
  String a3result;
  if (paidA3 == null) {
    a3result = 'SKIP';
    c.skip('A3', 'DY1', 'paid A3 fail', 'null');
  } else if ('${ordA3?['status']}' == 'pago' && qtyA3 == 1 && leftoverBuyable) {
    a3result = 'FAIL';
    c.block('A3', 'DY1', 'leftover após pago: Hub+CPI coerentes', {
      'status': ordA3?['status'],
      'qty': qtyA3,
      'hub_n': hubA3?.list.length,
      'cs': cpiA3?.sessionId,
    });
  } else if ('${ordA3?['status']}' == 'pago' && qtyA3 <= 0 && leftoverBuyable) {
    a3result = 'HOLD';
    c.hold(
      id: 'P1-A3-GHOST-LEFTOVER',
      lens: 'DY1',
      severity: 'P1',
      title: 'Pago esgotou stock mas leftover ainda abre Session',
      actor: 'B2 CPI leftover',
      pre: 'pago qty 2→0',
      repro: 'insert+CPI leftover',
      expected: 'Hub 0; CPI deny',
      obtained: {
        'qty': qtyA3,
        'hub_n': hubA3?.list.length,
        'cpi': cpiA3?.brief,
      },
    );
  } else {
    a3result = 'FAIL';
    c.block('A3', 'DY1', 'leftover após pago observado', {
      'status': ordA3?['status'],
      'qty': qtyA3,
      'hub_n': hubA3?.list.length,
      'cpi': cpiA3?.brief,
      'pi': paidA3?.pi,
    });
  }
  c.probe(
    id: 'A3',
    surfaces: 'Hub + orders + CPI leftover',
    action: 'leftover após pago parcial qty 2→1',
    http: {'paid': paidA3?.hit.brief, 'cpi': cpiA3?.brief, 'hub': hubA3?.brief},
    oracles: {
      'status': ordA3?['status'],
      'qty': qtyA3,
      'hub_n': hubA3?.list.length,
      'cs': cpiA3?.sessionId,
      'pi': paidA3?.pi,
    },
    result: a3result,
    lens: 'DY1',
    countFinding: a3result == 'HOLD',
  );

  // ----- A4 follow + favorite + hold qty=1 + 2.º buyer (classe_nova) -----
  final skuA4 = await c.createProduct(
    title: '$prefix A4 fav-hold',
    qty: 1,
    listed: true,
    live: false,
  );
  HttpHit? folA4;
  HttpHit? favA4;
  HttpHit? cpiB1;
  HttpHit? insB2;
  HttpHit? hubA4;
  HttpHit? folAfter;
  HttpHit? favAfter;
  String? oidA4;
  Map<String, dynamic>? prodA4;
  if (skuA4 != null) {
    folA4 = await c.followSeller(s1, jwt: c.buyerJwt, follower: b1);
    favA4 = await c.favorite(skuA4, jwt: c.buyerJwt, user: b1);
    oidA4 = await c.insertOrder(
      productId: skuA4,
      jwt: c.buyerJwt,
      price: 12.0,
    );
    if (oidA4 != null) {
      cpiB1 = await c.checkout(
        orderId: oidA4,
        productId: skuA4,
        jwt: c.buyerJwt,
      );
      if (c.usefulCs(cpiB1)) c.createdSessionIds.add(cpiB1.sessionId!);
    }
    insB2 = await c.insertOrderHit(
      productId: skuA4,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 12.0,
    );
    hubA4 = await c.hubSku(skuA4, jwt: c.buyerJwt);
    prodA4 = await c.productRow(skuA4);
    folAfter = await c.followRow(b1, s1);
    favAfter = await c.favRow(skuA4, b1);
  }
  final twoOwners = c.usefulCs(cpiB1) && (insB2?.ok == true);
  String a4result;
  if (skuA4 == null) {
    a4result = 'SKIP';
    c.skip('A4', 'DY1', 'sku A4 fail', 'null');
  } else if (twoOwners) {
    a4result = 'HOLD';
    c.hold(
      id: 'P1-A4-DOUBLE-HOLD',
      lens: 'DY1',
      severity: 'P1',
      title: 'follow+favorite: 2.º buyer insert após hold qty=1',
      actor: 'B1 CPI + B2 insert',
      pre: 'qty=1; B1 follow+fav+CPI',
      repro: 'B2 POST orders',
      expected: '2.º insert deny; Hub 0',
      obtained: {
        'cpi': cpiB1?.brief,
        'insB2': insB2?.brief,
        'hub_n': hubA4?.list.length,
        'fol': folAfter?.list.length,
        'fav': favAfter?.list.length,
      },
    );
  } else {
    a4result = 'FAIL';
    c.block('A4', 'DY1', 'follow+favorite+hold: ≤1 dono; Hub/fav/follow', {
      'fol': folA4?.brief,
      'fav': favA4?.brief,
      'cs': cpiB1?.sessionId,
      'insB2': insB2?.brief,
      'hub_n': hubA4?.list.length,
      'fol_n': folAfter?.list.length,
      'fav_n': favAfter?.list.length,
      'qty': prodA4?['quantity'],
    });
  }
  c.probe(
    id: 'A4',
    surfaces: 'follows + favorites + Hub + CPI hold',
    action: 'follow S1 + favorite SKU + hold qty=1 + 2.º buyer insert',
    http: {
      'fol': folA4?.brief,
      'fav': favA4?.brief,
      'cpi': cpiB1?.brief,
      'insB2': insB2?.brief,
    },
    oracles: {
      'hub_n': hubA4?.list.length,
      'cs': cpiB1?.sessionId,
      'b2_ok': insB2?.ok,
      'fol_n': folAfter?.list.length,
      'fav_n': favAfter?.list.length,
    },
    result: a4result,
    lens: 'DY1',
    classeNova: true,
    countFinding: a4result == 'HOLD',
  );

  // ----- A5 rifa drawn + Hub + insert (reteste se Hub 0) -----
  final skuA5 = await c.createProduct(
    title: '$prefix A5 raffle-prize',
    qty: 1,
    listed: true,
    live: true,
  );
  final liveA5 = await c.createLive(title: '$prefix A5 raffle');
  String? liA5;
  HttpHit? rafA5;
  HttpHit? awardA5;
  HttpHit? drawA5;
  HttpHit? hubA5;
  HttpHit? insA5;
  Map<String, dynamic>? prodA5;
  List<Map<String, dynamic>> winA5 = const [];
  List<Map<String, dynamic>> prizeA5 = const [];
  if (liveA5 != null && skuA5 != null) {
    liA5 = await c.createLiveItem(
      liveId: liveA5,
      title: '$prefix A5 prize-li',
      kind: 'marketplace_product',
      productId: skuA5,
    );
    rafA5 = await c.createRaffle(
      liveId: liveA5,
      seller: s1,
      liveItemId: liA5,
      title: '$prefix A5 prize',
    );
    final rafId = rafA5.firstId;
    if (rafId != null) {
      awardA5 = await c.awardTickets(rafId, b1, src: 'a5');
      await c.closeRaffle(rafId);
      drawA5 = await c.drawRaffle(rafId);
      winA5 = await c.raffleWinners(rafId);
      prizeA5 = await c.prizeOrders(rafId);
      prodA5 = await c.productRow(skuA5);
      hubA5 = await c.hubSku(skuA5, jwt: c.buyerJwt);
      // reteste insert se Hub 0; também se Hub 1 (stock vs vitrine)
      insA5 = await c.insertOrderHit(
        productId: skuA5,
        jwt: c.buyer2Jwt,
        buyer: b2,
        price: 12.0,
      );
    }
  }
  final hubA5n = hubA5?.list.length ?? -1;
  final qtyA5 = numOf(prodA5?['quantity']) ?? -1;
  final liA5row = liA5 == null ? null : await c.liveItemRow(liA5);
  // Anti-atrofia: Hub hide rifa drawn clássico — NÃO contar P2 se só a vitrine
  // ainda lista. Contar só se Hub 0 (selado) MAS insert ainda 200 (stock furo).
  final sealedHubOpenStock =
      winA5.isNotEmpty && hubA5n == 0 && (insA5?.ok == true);
  String a5result;
  if (skuA5 == null || liveA5 == null || rafA5?.firstId == null) {
    a5result = 'SKIP';
    c.skip('A5', 'DY7', 'raffle A5 fixture', rafA5?.brief ?? 'null');
  } else if (sealedHubOpenStock) {
    a5result = 'HOLD';
    c.hold(
      id: 'P2-A5-SEAL-STOCK',
      lens: 'DY7',
      severity: 'P2',
      title: 'Hub ocultou o prémio mas insert marketplace ainda abre',
      actor: 'B2 insert pós-draw',
      pre: 'rifa drawn winner B1; Hub n=0',
      repro: 'POST orders SKU prémio',
      expected: 'insert deny (hold/sold)',
      obtained: {
        'hub_n': hubA5n,
        'qty': qtyA5,
        'ins': insA5?.brief,
        'winners': winA5.length,
        'prize_n': prizeA5.length,
        'item': liA5row?['status'],
      },
    );
  } else {
    a5result = 'FAIL';
    c.block('A5', 'DY7', 'rifa drawn + Hub + insert (clássico Hub HOLD se n=1)', {
      'hub_n': hubA5n,
      'qty': qtyA5,
      'ins': insA5?.brief,
      'winners': winA5.length,
      'prize_n': prizeA5.length,
      'item': liA5row?['status'],
      'note': hubA5n == 1
          ? 'Hub hide rifa drawn clássico — anti-atrofia, não contar'
          : 'Hub 0; insert deny ou fixture',
    });
  }
  c.probe(
    id: 'A5',
    surfaces: 'rifa + Hub + products + insert + live_item',
    action: 'draw winner + Hub + insert (reteste se Hub 0)',
    http: {
      'raf': rafA5?.brief,
      'award': awardA5?.brief,
      'draw': drawA5?.brief,
      'ins': insA5?.brief,
    },
    oracles: {
      'hub_n': hubA5n,
      'qty': qtyA5,
      'winners': winA5.length,
      'prize_n': prizeA5.length,
      'ins_ok': insA5?.ok,
      'item': liA5row?['status'],
    },
    result: a5result,
    lens: 'DY7',
    classeNova: true,
    countFinding: a5result == 'HOLD',
  );
}

Future<void> runB(
  Rtdy c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // ----- B1 accept hitch SKU-A + bag SKU-B + rifa activa em A (rifa+bag+Hub) -----
  final skuA = await c.createProduct(
    title: '$prefix B1 hitch-A',
    qty: 1,
    listed: true,
    live: true,
  );
  final skuB = await c.createProduct(
    title: '$prefix B1 bag-B',
    qty: 1,
    listed: true,
    live: false,
  );
  final liveB1 = await c.createLive(title: '$prefix B1 raffle-bag');
  String? liA;
  String? resA;
  HttpHit? acc;
  HttpHit? bagB;
  HttpHit? hubA;
  HttpHit? hubB;
  HttpHit? rafB1;
  String? oidB;
  if (liveB1 != null && skuA != null) {
    liA = await c.createLiveItem(
      liveId: liveB1,
      title: '$prefix B1 li-A',
      kind: 'marketplace_product',
      productId: skuA,
    );
    rafB1 = await c.createRaffle(
      liveId: liveB1,
      seller: s1,
      liveItemId: liA,
      title: '$prefix B1 raffle-A',
    );
    if (rafB1.firstId != null) {
      await c.awardTickets(rafB1.firstId!, b2, src: 'b1');
    }
    if (liA != null) {
      resA = await c.insertReservation(
        liveId: liveB1,
        liveItemId: liA,
        jwt: c.buyer2Jwt,
        buyer: b2,
      );
      if (resA != null) acc = await c.acceptRes(resA);
    }
  }
  if (skuB != null) {
    oidB = await c.insertOrder(
      productId: skuB,
      jwt: c.buyerJwt,
      price: 12.0,
    );
    if (oidB != null) {
      bagB = await c.checkoutBag(
        lines: [
          {'order_id': oidB, 'product_id': skuB, 'quantity': 1, 'price': 12.0},
        ],
        jwt: c.buyerJwt,
        seller: s1,
      );
      if (c.usefulCs(bagB)) c.createdSessionIds.add(bagB.sessionId!);
    }
  }
  if (skuA != null) hubA = await c.hubSku(skuA, jwt: c.buyerJwt);
  if (skuB != null) hubB = await c.hubSku(skuB, jwt: c.buyerJwt);
  final resRow = resA == null ? null : await c.resRow(resA);
  final accepted = '${resRow?['status']}' == 'accepted';
  final bagOk = c.usefulCs(bagB);
  String b1result;
  if (skuA == null || skuB == null || liveB1 == null) {
    b1result = 'SKIP';
    c.skip('B1', 'DY2', 'fixture B1 fail', 'null');
  } else if (accepted && !bagOk && denied(bagB ?? HttpHit(0, '', {}))) {
    b1result = 'HOLD';
    c.hold(
      id: 'P2-B1-CROSS-LINE',
      lens: 'DY2',
      severity: 'P2',
      title: 'Accept live SKU-A (com rifa) bloqueou saco da OUTRA linha SKU-B',
      actor: 'S1 accept + B1 bag',
      pre: 'SKU-A hitch+rifa accepted; SKU-B stock independente',
      repro: 'accept A + bag CPI B',
      expected: 'saco B abre cs_',
      obtained: {
        'acc': acc?.brief,
        'bag': bagB?.brief,
        'hubA': hubA?.list.length,
        'hubB': hubB?.list.length,
        'raf': rafB1?.firstId,
      },
    );
  } else {
    b1result = 'FAIL';
    c.block('B1', 'DY2', 'rifa+accept A não cega bag B; Hub A/B', {
      'accepted': accepted,
      'bag_cs': bagB?.sessionId,
      'hubA': hubA?.list.length,
      'hubB': hubB?.list.length,
      'raf': rafB1?.firstId,
    });
  }
  c.probe(
    id: 'B1',
    surfaces: 'rifa + live accept + bag outra linha + Hub',
    action: 'rifa activa A + accept hitch A + bag CPI SKU-B',
    http: {'acc': acc?.brief, 'bag': bagB?.brief, 'raf': rafB1?.brief},
    oracles: {
      'res': resRow?['status'],
      'bag_cs': bagB?.sessionId,
      'hubA_n': hubA?.list.length,
      'hubB_n': hubB?.list.length,
      'raf_id': rafB1?.firstId,
    },
    result: b1result,
    lens: 'DY2',
    classeNova: true,
    countFinding: b1result == 'HOLD',
  );

  // ----- B2 convert + chat card + Hub -----
  final paidB2 = await c.payToPago(lens: 'DY2', initialQty: 1);
  String? liveB2;
  String? liB2;
  String? resB2;
  HttpHit? conv;
  HttpHit? rec;
  HttpHit? card;
  HttpHit? hubB2;
  Map<String, dynamic>? resAfter;
  Map<String, dynamic>? prodB2;
  Map<String, dynamic>? ordB2;
  String? chatB2;
  if (paidB2 != null) {
    ordB2 = await c.orderRow(paidB2.oid);
    prodB2 = await c.productRow(paidB2.pid);
    liveB2 = await c.createLive(title: '$prefix B2 convert');
    if (liveB2 != null) {
      liB2 = await c.createLiveItem(
        liveId: liveB2,
        title: '$prefix B2 li',
        kind: 'marketplace_product',
        productId: paidB2.pid,
      );
      if (liB2 != null) {
        resB2 = await c.insertReservation(
          liveId: liveB2,
          liveItemId: liB2,
          jwt: c.buyerJwt,
          buyer: b1,
        );
        if (resB2 != null) {
          await c.acceptRes(resB2);
          conv = await c.rpc(
            'batata_live_reservation_stripe_convert',
            {'p_request_id': resB2, 'p_order_id': paidB2.oid},
            jwt: c.sellerJwt,
          );
          rec = await c.rpc(
            'batata_live_reconcile_stripe_order',
            {
              'p_order_id': paidB2.oid,
              'p_reservation_request_id': resB2,
            },
            jwt: c.sellerJwt,
          );
          resAfter = await c.resRow(resB2);
        }
      }
    }
    hubB2 = await c.hubSku(paidB2.pid, jwt: c.buyerJwt);
    chatB2 = await c.ensureChat(paidB2.pid);
    if (chatB2 != null) {
      card = await c.postCard(chatB2, {
        'kind': 'reservation_payment_submitted',
        'order_id': paidB2.oid,
        'notes': 'ok',
      });
    }
  }
  final converted = '${resAfter?['status']}' == 'converted';
  final qtyB2 = numOf(prodB2?['quantity']) ?? -1;
  final hubN = hubB2?.list.length ?? -1;
  final ghost = converted && hubN == 1 && qtyB2 <= 0;
  String b2result;
  if (paidB2 == null) {
    b2result = 'SKIP';
    c.skip('B2', 'DY2', 'paid B2 fail', 'null');
  } else if (ghost) {
    b2result = 'HOLD';
    c.hold(
      id: 'P2-B2-CONVERT-HUB',
      lens: 'DY2',
      severity: 'P2',
      title: 'Reserva converted; Hub ainda lista SKU qty=0',
      actor: 'S1 convert/reconcile + Hub',
      pre: 'pago Stripe qty 1→0; hitch+accept+convert',
      repro: 'stripe_convert + reconcile + hub_products_public',
      expected: 'Hub 0 se qty=0 converted',
      obtained: {
        'res': resAfter,
        'hub_n': hubN,
        'qty': qtyB2,
        'conv': conv?.brief,
        'rec': rec?.brief,
      },
    );
  } else {
    b2result = 'FAIL';
    c.block('B2', 'DY2', 'convert/reconcile vs Hub vs chat observados', {
      'converted': converted,
      'hub_n': hubN,
      'qty': qtyB2,
      'card': card?.brief,
      'conv': conv?.brief,
      'rec': rec?.brief,
      'status': ordB2?['status'],
    });
  }
  c.probe(
    id: 'B2',
    surfaces: 'live convert + Hub + chat card + order',
    action: 'pago Stripe + hitch convert/reconcile + card chat',
    http: {
      'paid': paidB2?.hit.brief,
      'conv': conv?.brief,
      'rec': rec?.brief,
      'card': card?.brief,
    },
    oracles: {
      'res': resAfter?['status'],
      'hub_n': hubN,
      'qty': qtyB2,
      'order': ordB2?['status'],
      'pi': paidB2?.pi,
      'card_ok': card?.ok,
    },
    result: b2result,
    lens: 'DY2',
    classeNova: true,
    countFinding: b2result == 'HOLD',
  );

  // ----- B3 end_live ∥ bag CPI ∥ Hub (race) -----
  final skuB3 = await c.createProduct(
    title: '$prefix B3 end-bag',
    qty: 1,
    listed: true,
    live: true,
  );
  final liveB3 = await c.createLive(title: '$prefix B3 air');
  String? liB3;
  String? oidB3;
  HttpHit? endH;
  HttpHit? bagRace;
  HttpHit? hubRace;
  HttpHit? hubLive;
  if (liveB3 != null && skuB3 != null) {
    liB3 = await c.createLiveItem(
      liveId: liveB3,
      title: '$prefix B3 li',
      kind: 'marketplace_product',
      productId: skuB3,
    );
    oidB3 = await c.insertOrder(
      productId: skuB3,
      jwt: c.buyerJwt,
      price: 12.0,
    );
    if (oidB3 != null) {
      final raced = await Future.wait([
        c.rest(
          'PATCH',
          'lives?id=eq.$liveB3',
          service: true,
          body: {'status': 'ended', 'is_active': false},
          prefer: 'return=representation',
        ),
        c.checkoutBag(
          lines: [
            {
              'order_id': oidB3,
              'product_id': skuB3,
              'quantity': 1,
              'price': 12.0,
            },
          ],
          jwt: c.buyerJwt,
          seller: s1,
        ),
        c.hubSku(skuB3, jwt: c.buyerJwt),
      ]);
      endH = raced[0];
      bagRace = raced[1];
      hubRace = raced[2];
      if (c.usefulCs(bagRace)) c.createdSessionIds.add(bagRace.sessionId!);
    }
    hubLive = await c.hubLives(liveB3);
  }
  final liveRow = liveB3 == null
      ? null
      : (await c.rest(
          'GET',
          'lives?id=eq.$liveB3&select=id,status,is_active',
          service: true,
        ))
          .map;
  String b3result;
  if (skuB3 == null || liveB3 == null) {
    b3result = 'SKIP';
    c.skip('B3', 'DY5', 'fixture B3', 'null');
  } else {
    b3result = 'FAIL';
    c.block('B3', 'DY5', 'end_live∥bag∥Hub observados', {
      'end': endH?.brief,
      'bag': bagRace?.brief,
      'hub_n': hubRace?.list.length,
      'live': liveRow,
      'hub_live_n': hubLive?.list.length,
    });
  }
  c.probe(
    id: 'B3',
    surfaces: 'live end + bag CPI + Hub',
    action: 'Future.wait end_live ∥ bag CPI ∥ Hub SKU',
    http: {'end': endH?.brief, 'bag': bagRace?.brief, 'hub': hubRace?.brief},
    oracles: {
      'live': liveRow,
      'bag_cs': bagRace?.sessionId,
      'hub_n': hubRace?.list.length,
      'hub_live_n': hubLive?.list.length,
      'li': liB3,
    },
    result: b3result,
    lens: 'DY5',
    countFinding: false,
  );

  // ----- B4 rifa + marketplace CPI paralelo no draw (race classe_nova) -----
  final skuB4 = await c.createProduct(
    title: '$prefix B4 race-prize',
    qty: 1,
    listed: true,
    live: true,
  );
  final liveB4 = await c.createLive(title: '$prefix B4 race');
  String? liB4;
  HttpHit? rafB4;
  HttpHit? drawB4;
  HttpHit? insB4;
  HttpHit? cpiB4;
  HttpHit? hubB4;
  Map<String, dynamic>? prodB4;
  List<Map<String, dynamic>> winB4 = const [];
  List<Map<String, dynamic>> prizeB4 = const [];
  String? oidRace;
  if (liveB4 != null && skuB4 != null) {
    liB4 = await c.createLiveItem(
      liveId: liveB4,
      title: '$prefix B4 li',
      kind: 'marketplace_product',
      productId: skuB4,
    );
    rafB4 = await c.createRaffle(
      liveId: liveB4,
      seller: s1,
      liveItemId: liB4,
      title: '$prefix B4 prize',
    );
    final rafId = rafB4.firstId;
    if (rafId != null) {
      await c.awardTickets(rafId, b1, src: 'b4');
      await c.closeRaffle(rafId);
      oidRace = await c.insertOrder(
        productId: skuB4,
        jwt: c.buyer2Jwt,
        buyer: b2,
        price: 12.0,
      );
      final raced = await Future.wait([
        c.drawRaffle(rafId),
        if (oidRace != null)
          c.checkout(
            orderId: oidRace,
            productId: skuB4,
            jwt: c.buyer2Jwt,
            buyer: b2,
          )
        else
          Future.value(HttpHit(0, 'no_oid', {})),
      ]);
      drawB4 = raced[0];
      cpiB4 = raced[1];
      if (c.usefulCs(cpiB4)) c.createdSessionIds.add(cpiB4.sessionId!);
      winB4 = await c.raffleWinners(rafId);
      prizeB4 = await c.prizeOrders(rafId);
      prodB4 = await c.productRow(skuB4);
      hubB4 = await c.hubSku(skuB4, jwt: c.buyerJwt);
      if (oidRace != null) {
        insB4 = HttpHit(200, oidRace, {'id': oidRace});
      }
    }
  }
  final qtyB4 = numOf(prodB4?['quantity']) ?? -1;
  final doubleClaim = winB4.isNotEmpty &&
      c.usefulCs(cpiB4) &&
      qtyB4 >= 1 &&
      prizeB4.isEmpty;
  final twoOwners = winB4.isNotEmpty &&
      oidRace != null &&
      prizeB4.isNotEmpty &&
      c.usefulCs(cpiB4);
  String b4result;
  if (skuB4 == null || liveB4 == null || rafB4?.firstId == null) {
    b4result = 'SKIP';
    c.skip('B4', 'DY7', 'raffle B4 fixture', rafB4?.brief ?? 'null');
  } else if (twoOwners || doubleClaim) {
    b4result = 'HOLD';
    c.hold(
      id: 'P1-B4-DRAW-CPI',
      lens: 'DY5',
      severity: 'P1',
      title: 'Draw rifa ∥ CPI marketplace: dois donos no qty=1',
      actor: 'S1 draw ∥ B2 CPI',
      pre: 'SKU qty=1 hitch prémio; tickets B1; B2 order pronta',
      repro: 'Future.wait draw + CPI B2',
      expected: '≤1 dono (prize OU cs_, não ambos com stock livre)',
      obtained: {
        'draw': drawB4?.brief,
        'cpi': cpiB4?.brief,
        'winners': winB4.length,
        'prize_n': prizeB4.length,
        'qty': qtyB4,
        'hub_n': hubB4?.list.length,
        'cs': cpiB4?.sessionId,
      },
    );
  } else {
    b4result = 'FAIL';
    c.block('B4', 'DY5', 'rifa draw∥CPI marketplace: sem dois donos', {
      'draw': drawB4?.brief,
      'cpi': cpiB4?.brief,
      'winners': winB4.length,
      'prize_n': prizeB4.length,
      'qty': qtyB4,
      'hub_n': hubB4?.list.length,
      'ins': insB4?.brief,
    });
  }
  c.probe(
    id: 'B4',
    surfaces: 'rifa draw + CPI marketplace + Hub + products',
    action: 'Future.wait draw winners ∥ CPI B2 no mesmo SKU qty=1',
    http: {'draw': drawB4?.brief, 'cpi': cpiB4?.brief, 'raf': rafB4?.brief},
    oracles: {
      'winners': winB4.length,
      'prize_n': prizeB4.length,
      'qty': qtyB4,
      'hub_n': hubB4?.list.length,
      'cs': cpiB4?.sessionId,
      'oid_b2': oidRace,
    },
    result: b4result,
    lens: 'DY5',
    classeNova: true,
    countFinding: b4result == 'HOLD',
  );

  // ----- B5 live_only prize vs Hub (sem product) -----
  final liveB5 = await c.createLive(title: '$prefix B5 live-only');
  String? liB5;
  HttpHit? rafB5;
  HttpHit? drawB5;
  HttpHit? hubLiveB5;
  HttpHit? hubGhost;
  List<Map<String, dynamic>> winB5 = const [];
  List<Map<String, dynamic>> prizeB5 = const [];
  List<dynamic> ghostSkus = const [];
  Map<String, dynamic>? liB5row;
  if (liveB5 != null) {
    liB5 = await c.createLiveItem(
      liveId: liveB5,
      title: '$prefix B5 live-only prize',
      kind: 'live_only',
      quantity: 1,
      price: 0,
    );
    rafB5 = await c.createRaffle(
      liveId: liveB5,
      seller: s1,
      liveItemId: liB5,
      title: '$prefix B5 live-only',
    );
    final rafId = rafB5.firstId;
    if (rafId != null && liB5 != null) {
      await c.awardTickets(rafId, b1, src: 'b5');
      await c.closeRaffle(rafId);
      drawB5 = await c.drawRaffle(rafId);
      winB5 = await c.raffleWinners(rafId);
      prizeB5 = await c.prizeOrders(rafId);
      liB5row = await c.liveItemRow(liB5);
      hubLiveB5 = await c.hubLives(liveB5);
      final ghosts = await c.rest(
        'GET',
        'products?seller_id=eq.$s1&title=ilike.*${Uri.encodeQueryComponent('B5 live-only')}*&select=id,title,quantity,list_on_marketplace,is_sold',
        service: true,
      );
      ghostSkus = ghosts.list;
      if (ghostSkus.isNotEmpty) {
        final gid = (ghostSkus.first as Map)['id']?.toString();
        if (gid != null) hubGhost = await c.hubSku(gid, jwt: c.buyerJwt);
      }
    }
  }
  final leakedProduct = ghostSkus.isNotEmpty && (hubGhost?.list.length ?? 0) > 0;
  String b5result;
  if (liveB5 == null || rafB5?.firstId == null) {
    b5result = 'SKIP';
    c.skip('B5', 'DY7', 'live_only raffle fixture', rafB5?.brief ?? 'null');
  } else if (leakedProduct) {
    b5result = 'HOLD';
    c.hold(
      id: 'P2-B5-LIVEONLY-HUB',
      lens: 'DY7',
      severity: 'P2',
      title: 'Prémio live_only materializou SKU no Hub',
      actor: 'S1 draw live_only',
      pre: 'rifa sem product_id; item_kind=live_only',
      repro: 'draw + hub_products_public / products title',
      expected: '0 SKU marketplace; Hub lives ≠ loja',
      obtained: {
        'ghosts': ghostSkus,
        'hub_n': hubGhost?.list.length,
        'winners': winB5.length,
        'prize_n': prizeB5.length,
        'item': liB5row,
      },
    );
  } else {
    b5result = 'FAIL';
    c.block('B5', 'DY7', 'live_only prize: sem SKU Hub; item/lives observados', {
      'winners': winB5.length,
      'prize_n': prizeB5.length,
      'item': liB5row?['status'],
      'ghosts_n': ghostSkus.length,
      'hub_live_n': hubLiveB5?.list.length,
      'draw': drawB5?.brief,
    });
  }
  c.probe(
    id: 'B5',
    surfaces: 'rifa live_only + Hub lives + products + prize order',
    action: 'draw prémio sem product vs Hub (não criar SKU)',
    http: {'raf': rafB5?.brief, 'draw': drawB5?.brief, 'hubLive': hubLiveB5?.brief},
    oracles: {
      'winners': winB5.length,
      'prize_n': prizeB5.length,
      'item': liB5row?['status'],
      'ghosts_n': ghostSkus.length,
      'hub_live_n': hubLiveB5?.list.length,
      'hub_ghost_n': hubGhost?.list.length,
    },
    result: b5result,
    lens: 'DY7',
    classeNova: true,
    countFinding: b5result == 'HOLD',
  );
}

Future<void> runC(
  Rtdy c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // ----- C1 oferta aceite + CPI underpay (selo servidor) -----
  final skuC1 = await c.createProduct(
    title: '$prefix C1 offer',
    qty: 2,
    price: 18.0,
    listed: true,
    live: false,
  );
  HttpHit? off;
  HttpHit? acc;
  HttpHit? cpiC1;
  HttpHit? hubC1;
  String? oidC1;
  String? offId;
  Map<String, dynamic>? offRow;
  Map<String, dynamic>? ordC1;
  if (skuC1 != null) {
    off = await c.insertOffer(
      productId: skuC1,
      amount: 8,
      listPrice: 18,
      jwt: c.buyerJwt,
    );
    offId = off.firstId;
    if (offId != null) {
      acc = await c.acceptOffer(offId);
      offRow = await c.offerRow(offId);
      oidC1 = await c.insertOrder(
        productId: skuC1,
        jwt: c.buyerJwt,
        price: 8.0,
        offerId: offId,
      );
      if (oidC1 != null) {
        cpiC1 = await c.checkout(
          orderId: oidC1,
          productId: skuC1,
          jwt: c.buyerJwt,
          amount: 1,
        );
        if (c.usefulCs(cpiC1)) c.createdSessionIds.add(cpiC1.sessionId!);
      }
    }
    hubC1 = await c.hubSku(skuC1, jwt: c.buyerJwt);
    if (oidC1 != null) ordC1 = await c.orderRow(oidC1);
  }
  final sealed = cpiC1?.amountTotal;
  final under = c.usefulCs(cpiC1) && sealed != null && sealed < 800;
  String c1result;
  if (skuC1 == null || offId == null) {
    c1result = 'SKIP';
    c.skip('C1', 'DY6', 'offer C1 fail', off?.brief ?? 'null');
  } else if (under) {
    c1result = 'HOLD';
    c.hold(
      id: 'P0-C1-UNDERPAY',
      lens: 'DY6',
      severity: 'P0',
      title: 'CPI selou underpay da oferta aceite',
      actor: 'B1 CPI amount=1 vs oferta 8€',
      pre: 'oferta aceite 8€ list 18€',
      repro: 'create-payment-intent amount=1',
      expected: 'selo ≥800¢ (oferta) ou deny',
      obtained: {
        'sealed': sealed,
        'offer': offRow,
        'cpi': cpiC1?.brief,
        'hub_n': hubC1?.list.length,
      },
    );
  } else {
    c1result = 'FAIL';
    c.block('C1', 'DY6', 'oferta aceite: selo servidor vs amount=1', {
      'offer': offRow?['amount'],
      'status': offRow?['status'],
      'sealed': sealed,
      'hub_n': hubC1?.list.length,
      'cpi': cpiC1?.brief,
      'ord': ordC1?['status'],
    });
  }
  c.probe(
    id: 'C1',
    surfaces: 'offer + CPI + Hub + orders',
    action: 'oferta 8€ aceite + CPI amount=1 (selo servidor)',
    http: {'off': off?.brief, 'acc': acc?.brief, 'cpi': cpiC1?.brief},
    oracles: {
      'offer_amt': offRow?['amount'],
      'offer_st': offRow?['status'],
      'sealed_cents': sealed,
      'hub_n': hubC1?.list.length,
      'order': ordC1?['status'],
    },
    result: c1result,
    lens: 'DY6',
    classeNova: true,
    countFinding: c1result == 'HOLD',
  );

  // ----- C2 oferta+bundle overlap Session (classe_nova vs bundle∥single só) -----
  final skuX = await c.createProduct(
    title: '$prefix C2 off-X',
    qty: 1,
    price: 18.0,
    listed: true,
    live: false,
  );
  final skuY = await c.createProduct(
    title: '$prefix C2 bun-Y',
    qty: 1,
    price: 12.0,
    listed: true,
    live: false,
  );
  HttpHit? offC2;
  HttpHit? bun;
  HttpHit? cpiOff;
  HttpHit? bagBun;
  HttpHit? hubX;
  HttpHit? hubY;
  String? oidOff;
  String? oidBunX;
  String? oidBunY;
  Map<String, dynamic>? bunRow;
  Map<String, dynamic>? offRowC2;
  if (skuX != null && skuY != null) {
    offC2 = await c.insertOffer(
      productId: skuX,
      amount: 10,
      listPrice: 18,
      jwt: c.buyerJwt,
    );
    final offIdC2 = offC2.firstId;
    if (offIdC2 != null) {
      await c.acceptOffer(offIdC2);
      offRowC2 = await c.offerRow(offIdC2);
      oidOff = await c.insertOrder(
        productId: skuX,
        jwt: c.buyerJwt,
        price: 10.0,
        offerId: offIdC2,
      );
    }
    bun = await c.insertBundle(
      productIds: [skuX, skuY],
      totalEur: 15,
      subtotalEur: 30,
      discountPct: 50,
      jwt: c.buyer2Jwt,
      buyer: b2,
    );
    final bunId = bun.firstId;
    if (bunId != null) {
      await c.acceptBundle(bunId);
      bunRow = await c.bundleRow(bunId);
      oidBunX = await c.insertOrder(
        productId: skuX,
        jwt: c.buyer2Jwt,
        buyer: b2,
        price: 7.5,
        bundleId: bunId,
      );
      oidBunY = await c.insertOrder(
        productId: skuY,
        jwt: c.buyer2Jwt,
        buyer: b2,
        price: 7.5,
        bundleId: bunId,
      );
    }
    final raced = await Future.wait([
      if (oidOff != null)
        c.checkout(
          orderId: oidOff,
          productId: skuX,
          jwt: c.buyerJwt,
        )
      else
        Future.value(HttpHit(0, 'no_off', {})),
      if (oidBunX != null && oidBunY != null)
        c.checkoutBag(
          lines: [
            {
              'order_id': oidBunX,
              'product_id': skuX,
              'quantity': 1,
              'price': 7.5,
            },
            {
              'order_id': oidBunY,
              'product_id': skuY,
              'quantity': 1,
              'price': 7.5,
            },
          ],
          jwt: c.buyer2Jwt,
          buyer: b2,
          seller: s1,
        )
      else
        Future.value(HttpHit(0, 'no_bun', {})),
    ]);
    cpiOff = raced[0];
    bagBun = raced[1];
    if (c.usefulCs(cpiOff)) c.createdSessionIds.add(cpiOff.sessionId!);
    if (c.usefulCs(bagBun)) c.createdSessionIds.add(bagBun.sessionId!);
    hubX = await c.hubSku(skuX, jwt: c.buyerJwt);
    hubY = await c.hubSku(skuY, jwt: c.buyerJwt);
  }
  final overlapCs = [cpiOff, bagBun].where(c.usefulCs).length;
  String c2result;
  if (skuX == null || skuY == null) {
    c2result = 'SKIP';
    c.skip('C2', 'DY6', 'sku C2 fail', 'null');
  } else if (overlapCs >= 2) {
    c2result = 'HOLD';
    c.hold(
      id: 'P1-C2-OFFER-BUNDLE',
      lens: 'DY6',
      severity: 'P1',
      title: 'Oferta e bundle abriram 2 Sessions no mesmo SKU qty=1',
      actor: 'B1 CPI oferta ∥ B2 bag bundle',
      pre: 'SKU-X qty=1; oferta aceite; bundle X+Y aceite',
      repro: 'Future.wait CPI oferta X ∥ bag bundle X+Y',
      expected: '≤1 cs_ (overlap X)',
      obtained: {
        'off': cpiOff?.brief,
        'bag': bagBun?.brief,
        'hubX': hubX?.list.length,
        'hubY': hubY?.list.length,
        'oid_off': oidOff,
        'oid_bun_x': oidBunX,
      },
    );
  } else {
    c2result = 'FAIL';
    c.block('C2', 'DY6', 'oferta∥bundle overlap: ≤1 cs_ no SKU-X', {
      'cs_n': overlapCs,
      'off': cpiOff?.brief,
      'bag': bagBun?.brief,
      'offer_st': offRowC2?['status'],
      'bun_st': bunRow?['status'],
      'hubX': hubX?.list.length,
      'hubY': hubY?.list.length,
      'oid_bun_x': oidBunX,
    });
  }
  c.probe(
    id: 'C2',
    surfaces: 'offer + bundle + CPI Session + Hub',
    action: 'Future.wait CPI oferta SKU-X ∥ bag bundle X+Y (qty=1 overlap)',
    http: {'off': cpiOff?.brief, 'bag': bagBun?.brief, 'bun': bun?.brief},
    oracles: {
      'cs_n': overlapCs,
      'offer_st': offRowC2?['status'],
      'bun_st': bunRow?['status'],
      'hubX_n': hubX?.list.length,
      'hubY_n': hubY?.list.length,
      'sid_off': cpiOff?.sessionId,
      'sid_bag': bagBun?.sessionId,
    },
    result: c2result,
    lens: 'DY5',
    classeNova: true,
    countFinding: c2result == 'HOLD',
  );

  // ----- C3 chat card amount vs order após pago -----
  final paidC3 = await c.payToPago(lens: 'DY3', initialQty: 2);
  HttpHit? cardOk;
  HttpHit? cardHostil;
  Map<String, dynamic>? ordC3;
  List<Map<String, dynamic>> msgs = const [];
  String? chatC3;
  if (paidC3 != null) {
    ordC3 = await c.orderRow(paidC3.oid);
    chatC3 = await c.ensureChat(paidC3.pid);
    if (chatC3 != null) {
      cardOk = await c.postCard(chatC3, {
        'kind': 'reservation_payment_submitted',
        'order_id': paidC3.oid,
        'notes': 'ok',
      });
      cardHostil = await c.postCard(chatC3, {
        'kind': 'reservation_payment_submitted',
        'order_id': paidC3.oid,
        'notes': 'pago',
        'amount': 0.01,
        'amount_paid_cents': 1,
      });
      msgs = await c.chatMsgsForOrder(paidC3.oid);
    }
  }
  final paidCents = numOf(ordC3?['amount_paid_cents']) ?? 0;
  final mutated = '${ordC3?['status']}' == 'pago' &&
      paidCents > 0 &&
      paidCents < 100 &&
      (cardHostil?.ok == true);
  String c3result;
  if (paidC3 == null) {
    c3result = 'SKIP';
    c.skip('C3', 'DY3', 'paid C3 fail', 'null');
  } else if (mutated) {
    c3result = 'HOLD';
    c.hold(
      id: 'P0-C3-CARD-LEDGER',
      lens: 'DY3',
      severity: 'P0',
      title: 'Card hostil alterou amount_paid da order paga',
      actor: 'B1 chat card',
      pre: 'pago Stripe',
      repro: 'POST chat_messages card amount=0.01',
      expected: 'amount_paid inalterado',
      obtained: {
        'paid_cents': paidCents,
        'card': cardHostil?.brief,
        'status': ordC3?['status'],
      },
    );
  } else {
    c3result = 'FAIL';
    c.block('C3', 'DY3', 'card hostil vs amount_paid inalterado', {
      'cardOk': cardOk?.brief,
      'cardHostil': cardHostil?.brief,
      'paid_cents': paidCents,
      'status': ordC3?['status'],
      'msgs_n': msgs.length,
    });
  }
  c.probe(
    id: 'C3',
    surfaces: 'chat card + orders + wallet snapshot',
    action: 'pago Stripe + card canónico vs amount hostil',
    http: {'ok': cardOk?.brief, 'hostil': cardHostil?.brief},
    oracles: {
      'status': ordC3?['status'],
      'amount_paid_cents': paidCents,
      'pi': paidC3?.pi,
      'msgs_n': msgs.length,
      'hostil_ok': cardHostil?.ok,
    },
    result: c3result,
    lens: 'DY3',
    countFinding: c3result == 'HOLD',
  );

  // ----- C4 seller/buyer PATCH pago sem Stripe -----
  final skuC4 = await c.createProduct(
    title: '$prefix C4 patch-pago',
    qty: 2,
    listed: true,
    live: false,
  );
  String? oidC4;
  HttpHit? patchSeller;
  HttpHit? patchBuyer;
  Map<String, dynamic>? ordC4;
  final wS0c = await c.walletBal(s1);
  if (skuC4 != null) {
    oidC4 = await c.insertOrder(
      productId: skuC4,
      jwt: c.buyerJwt,
      price: 12.0,
    );
    if (oidC4 != null) {
      patchBuyer =
          await c.patchOrder(oidC4, {'status': 'pago'}, jwt: c.buyerJwt);
      patchSeller = await c.patchOrder(
        oidC4,
        {'status': 'pago', 'amount_paid_cents': 1200},
        jwt: c.sellerJwt,
      );
      ordC4 = await c.orderRow(oidC4);
    }
  }
  final wS1c = await c.walletBal(s1);
  final faked = '${ordC4?['status']}' == 'pago';
  String c4result;
  if (oidC4 == null) {
    c4result = 'SKIP';
    c.skip('C4', 'DY8', 'order C4 fail', 'null');
  } else if (faked) {
    c4result = 'HOLD';
    c.hold(
      id: 'P0-C4-FAKE-PAGO',
      lens: 'DY8',
      severity: 'P0',
      title: 'Seller/buyer PATCH status=pago sem Stripe',
      actor: 'S1/B1 JWT PATCH orders',
      pre: 'reserva_pendente sem PI',
      repro: 'PATCH status=pago amount_paid_cents=1200',
      expected: '403; status≠pago',
      obtained: {
        'buyer': patchBuyer?.brief,
        'seller': patchSeller?.brief,
        'order': ordC4,
        'dWallet': wS1c - wS0c,
      },
    );
  } else {
    c4result = 'FAIL';
    c.block('C4', 'DY8', 'PATCH pago sem Stripe recusado', {
      'buyer': patchBuyer?.brief,
      'seller': patchSeller?.brief,
      'status': ordC4?['status'],
      'paid': ordC4?['amount_paid_cents'],
      'dWallet': wS1c - wS0c,
    });
  }
  c.probe(
    id: 'C4',
    surfaces: 'orders + wallet',
    action: 'seller/buyer PATCH pago sem captura Stripe',
    http: {'buyer': patchBuyer?.brief, 'seller': patchSeller?.brief},
    oracles: {
      'status': ordC4?['status'],
      'amount_paid': ordC4?['amount_paid_cents'],
      'pi': ordC4?['stripe_payment_intent_id'],
      'dWallet': wS1c - wS0c,
    },
    result: c4result,
    lens: 'DY8',
    countFinding: c4result == 'HOLD',
  );
}

Future<void> runD(
  Rtdy c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // ----- D1 refund ∥ nova compra leftover (residual race) -----
  final paidD1 = await c.payToPago(lens: 'DY5', initialQty: 2);
  HttpHit? rf;
  HttpHit? cpiNew;
  Map<String, dynamic>? prod0;
  Map<String, dynamic>? prod1;
  Map<String, dynamic>? oldOrd;
  Map<String, dynamic>? newOrd;
  String? oidNew;
  if (paidD1 != null) {
    prod0 = await c.productRow(paidD1.pid);
    oidNew = await c.insertOrder(
      productId: paidD1.pid,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 12.0,
    );
    if (oidNew != null) {
      final raced = await Future.wait([
        c.refund(paidD1.oid),
        c.checkout(
          orderId: oidNew,
          productId: paidD1.pid,
          jwt: c.buyer2Jwt,
          buyer: b2,
        ),
      ]);
      rf = raced[0];
      cpiNew = raced[1];
      if (c.usefulCs(cpiNew)) c.createdSessionIds.add(cpiNew.sessionId!);
    }
    oldOrd = await c.orderRow(paidD1.oid);
    if (oidNew != null) newOrd = await c.orderRow(oidNew);
    prod1 = await c.productRow(paidD1.pid);
  }
  final q0 = numOf(prod0?['quantity']) ?? 0;
  final q1 = numOf(prod1?['quantity']) ?? 0;
  String d1result;
  if (paidD1 == null) {
    d1result = 'SKIP';
    c.skip('D1', 'DY5', 'paid D1 fail', 'null');
  } else if (q1 < 0 || q1 > q0 + 2) {
    d1result = 'HOLD';
    c.hold(
      id: 'P1-D1-STOCK-RACE',
      lens: 'DY5',
      severity: 'P1',
      title: 'refund∥CPI leftover: stock incoerente',
      actor: 'S1 refund ∥ B2 CPI',
      pre: 'pago leftover qty=1',
      repro: 'Future.wait refund-order + CPI leftover',
      expected: 'stock 1→1 ou 1→2; sem qty negativa',
      obtained: {
        'qty': '$q0→$q1',
        'rf': rf?.brief,
        'cpi': cpiNew?.brief,
        'old': oldOrd?['status'],
      },
    );
  } else {
    d1result = 'FAIL';
    c.block('D1', 'DY5', 'refund∥leftover CPI stock observado', {
      'qty': '$q0→$q1',
      'rf': rf?.brief,
      'cpi': cpiNew?.brief,
      'old': oldOrd?['status'],
      'new': newOrd?['status'],
    });
  }
  c.probe(
    id: 'D1',
    surfaces: 'refund + CPI leftover + products + Hub leftover',
    action: 'Future.wait refund pago ∥ CPI leftover qty=1',
    http: {'rf': rf?.brief, 'cpi': cpiNew?.brief},
    oracles: {
      'qty': '$q0→$q1',
      'old': oldOrd?['status'],
      'new': newOrd?['status'],
      'cs': cpiNew?.sessionId,
      'pi': paidD1?.pi,
    },
    result: d1result,
    lens: 'DY5',
    residual: true,
    countFinding: d1result == 'HOLD',
  );

  // ----- D2 release ∥ disputa + stock/Hub (classe_nova) -----
  final paidD2 = await c.payToPago(lens: 'DY8', initialQty: 2);
  HttpHit? rel;
  HttpHit? disp;
  HttpHit? hubD2;
  Map<String, dynamic>? ordD2;
  Map<String, dynamic>? prodD2;
  final w0 = await c.walletBal(s1);
  if (paidD2 != null) {
    final raced = await Future.wait([
      c.tryRelease(paidD2.oid, jwt: c.buyerJwt),
      c.insertDispute(orderId: paidD2.oid),
    ]);
    rel = raced[0];
    disp = raced[1];
    ordD2 = await c.orderRow(paidD2.oid);
    prodD2 = await c.productRow(paidD2.pid);
    hubD2 = await c.hubSku(paidD2.pid, jwt: c.buyerJwt);
  }
  final w1 = await c.walletBal(s1);
  final released = rel?.json == true || '${rel?.json}' == 'true';
  final dWallet = w1 - w0;
  String d2result;
  if (paidD2 == null) {
    d2result = 'SKIP';
    c.skip('D2', 'DY8', 'paid D2 fail', 'null');
  } else if (released && dWallet > 0 && disp != null && disp.ok) {
    d2result = 'HOLD';
    c.hold(
      id: 'P1-D2-RELEASE-DISPUTE',
      lens: 'DY8',
      severity: 'P1',
      title: 'Release creditou wallet com disputa aberta',
      actor: 'B1 release ∥ disputa',
      pre: 'pago Stripe ainda sem envio',
      repro: 'Future.wait release + POST order_disputes',
      expected: 'release false; Δwallet≤0 ou disputa recusa',
      obtained: {
        'rel': rel?.brief,
        'disp': disp.brief,
        'dWallet': dWallet,
        'qty': prodD2?['quantity'],
        'hub_n': hubD2?.list.length,
        'order': ordD2,
      },
    );
  } else {
    d2result = 'FAIL';
    c.block('D2', 'DY8', 'release∥disputa+stock: sem crédito líquido anómalo', {
      'rel': rel?.brief,
      'disp': disp?.brief,
      'dWallet': dWallet,
      'status': ordD2?['status'],
      'qty': prodD2?['quantity'],
      'hub_n': hubD2?.list.length,
    });
  }
  c.probe(
    id: 'D2',
    surfaces: 'wallet release + disputa + orders + Hub leftover + stock',
    action: 'Future.wait release ∥ POST disputa; oráculo stock/Hub',
    http: {'rel': rel?.brief, 'disp': disp?.brief, 'hub': hubD2?.brief},
    oracles: {
      'released': released,
      'dWallet': dWallet,
      'status': ordD2?['status'],
      'disp_ok': disp?.ok,
      'qty': prodD2?['quantity'],
      'hub_n': hubD2?.list.length,
      'pi': paidD2?.pi,
    },
    result: d2result,
    lens: 'DY8',
    classeNova: true,
    countFinding: d2result == 'HOLD',
  );

  // ----- D3 2 buyers Hub visível + CPI qty=1 -----
  final skuD3 = await c.createProduct(
    title: '$prefix D3 two-buyers',
    qty: 1,
    listed: true,
    live: false,
  );
  HttpHit? hubD3;
  HttpHit? cpi1;
  HttpHit? cpi2;
  HttpHit? hubAfter;
  String? o1;
  String? o2;
  if (skuD3 != null) {
    hubD3 = await c.hubSku(skuD3, anon: true);
    o1 = await c.insertOrder(
      productId: skuD3,
      jwt: c.buyerJwt,
      price: 12.0,
    );
    o2 = await c.insertOrder(
      productId: skuD3,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 12.0,
    );
    if (o1 != null) {
      cpi1 = await c.checkout(orderId: o1, productId: skuD3, jwt: c.buyerJwt);
      if (c.usefulCs(cpi1)) c.createdSessionIds.add(cpi1.sessionId!);
    }
    if (o2 != null) {
      cpi2 = await c.checkout(
        orderId: o2,
        productId: skuD3,
        jwt: c.buyer2Jwt,
        buyer: b2,
      );
      if (c.usefulCs(cpi2)) c.createdSessionIds.add(cpi2.sessionId!);
    }
    hubAfter = await c.hubSku(skuD3, jwt: c.buyerJwt);
  }
  final two = [cpi1, cpi2].where(c.usefulCs).length;
  final twoInserts = o1 != null && o2 != null;
  String d3result;
  if (skuD3 == null) {
    d3result = 'SKIP';
    c.skip('D3', 'DY5', 'sku D3 fail', 'null');
  } else if (two >= 2) {
    d3result = 'HOLD';
    c.hold(
      id: 'P1-D3-TWO-CS',
      lens: 'DY5',
      severity: 'P1',
      title: '2 buyers Hub-visível: 2 cs_ no qty=1',
      actor: 'B1+B2 CPI',
      pre: 'Hub lista SKU qty=1',
      repro: 'insert+CPI B1 depois B2',
      expected: '≤1 cs_ útil; 2.º insert ou CPI deny',
      obtained: {
        'hub0': hubD3?.list.length,
        'hub1': hubAfter?.list.length,
        'b1': cpi1?.brief,
        'b2': cpi2?.brief,
        'two_inserts': twoInserts,
      },
    );
  } else {
    d3result = 'FAIL';
    c.block('D3', 'DY5', '2 buyers Hub visível: ≤1 cs_', {
      'hub0': hubD3?.list.length,
      'hub1': hubAfter?.list.length,
      'cs_n': two,
      'o2': o2,
      'b1': cpi1?.brief,
      'b2': cpi2?.brief,
    });
  }
  c.probe(
    id: 'D3',
    surfaces: 'Hub + CPI B1 + CPI B2 + orders',
    action: '2 buyers insert+CPI em SKU Hub-visível qty=1',
    http: {'hub': hubD3?.brief, 'b1': cpi1?.brief, 'b2': cpi2?.brief},
    oracles: {
      'hub0': hubD3?.list.length,
      'hub1': hubAfter?.list.length,
      'cs_n': two,
      'sid1': cpi1?.sessionId,
      'sid2': cpi2?.sessionId,
      'o2_ok': o2 != null,
    },
    result: d3result,
    lens: 'DY5',
    countFinding: d3result == 'HOLD',
  );

  // ----- D4 pago 4242 → Hub + order + wallet + chat (4 sítios) -----
  final wB0 = await c.walletBal(c.buyerId);
  final wS0 = await c.walletBal(c.sellerId);
  final paidD4 = await c.payToPago(lens: 'DY8', initialQty: 2);
  Map<String, dynamic>? ordD4;
  Map<String, dynamic>? prodD4;
  HttpHit? hubD4;
  HttpHit? cardD4;
  List<Map<String, dynamic>> chats = const [];
  List<Map<String, dynamic>> msgsD4 = const [];
  var wB1 = wB0;
  var wS1 = wS0;
  if (paidD4 != null) {
    ordD4 = await c.orderRow(paidD4.oid);
    prodD4 = await c.productRow(paidD4.pid);
    hubD4 = await c.hubSku(paidD4.pid, jwt: c.buyerJwt);
    final chatId = await c.ensureChat(paidD4.pid);
    if (chatId != null) {
      cardD4 = await c.postCard(chatId, {
        'kind': 'reservation_payment_submitted',
        'order_id': paidD4.oid,
        'notes': 'pago',
      });
    }
    chats = await c.chatsForProduct(paidD4.pid);
    msgsD4 = await c.chatMsgsForOrder(paidD4.oid);
    wB1 = await c.walletBal(c.buyerId);
    wS1 = await c.walletBal(c.sellerId);
  }
  final statusPago = '${ordD4?['status']}' == 'pago';
  final qtyDrop = (numOf(prodD4?['quantity']) ?? 2) < 2;
  String d4result;
  if (paidD4 == null) {
    d4result = 'SKIP';
    c.skip('D4', 'DY8', 'setup_paid_order fail', 'null');
  } else if (!statusPago) {
    d4result = 'HOLD';
    c.hold(
      id: 'P1-D4-NOT-PAGO',
      lens: 'DY8',
      severity: 'P1',
      title: 'Stripe TEST succeeded mas order ≠ pago',
      actor: 'e2e setup_paid_order 4242',
      pre: 'PI pm_card_visa',
      repro: 'setup_paid_order',
      expected: 'status=pago visível Hub/order/wallet/chat',
      obtained: ordD4,
    );
  } else if (!qtyDrop) {
    d4result = 'HOLD';
    c.hold(
      id: 'P1-D4-STOCK',
      lens: 'DY8',
      severity: 'P1',
      title: 'Pago Stripe sem baixar stock',
      actor: 'settle',
      pre: 'initial_qty=2 compra 1',
      repro: 'setup_paid_order',
      expected: 'quantity 2→1',
      obtained: prodD4,
    );
  } else {
    d4result = 'FAIL';
    c.block('D4', 'DY8', 'pago 4242: 4 sítios observados', {
      'status': ordD4?['status'],
      'qty': prodD4?['quantity'],
      'hub_n': hubD4?.list.length,
      'dSeller': wS1 - wS0,
      'dBuyer': wB1 - wB0,
      'chats_n': chats.length,
      'card': cardD4?.brief,
      'msgs_n': msgsD4.length,
      'pi': paidD4.pi,
      'paid_cents': ordD4?['amount_paid_cents'],
    });
  }
  c.probe(
    id: 'D4',
    surfaces: 'Hub + order + wallet + chat',
    action: 'pago Stripe TEST 4242 → 4 oráculos',
    http: paidD4?.hit.brief ?? 'n/a',
    oracles: {
      'status': ordD4?['status'],
      'qty': prodD4?['quantity'],
      'amount_paid_cents': ordD4?['amount_paid_cents'],
      'pi': paidD4?.pi,
      'hub_n': hubD4?.list.length,
      'dSeller': wS1 - wS0,
      'dBuyer': wB1 - wB0,
      'chats_n': chats.length,
      'card_ok': cardD4?.ok,
    },
    result: d4result,
    lens: 'DY8',
    countFinding: d4result == 'HOLD',
  );
}
