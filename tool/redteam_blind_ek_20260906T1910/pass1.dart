/// RED TEAM CEGO EK pass1 — composição multi-sítio ≥18 POS_OPEN_MVP.
/// Staging only. NÃO corrigir. NÃO produção. NÃO Fase 4.
/// Obrigatório: 6∥4 + expand + Hub. Classe nova: bag∥single, bag pago 4 sítios.
import 'dart:io';
import '_rtek.dart';

const pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

Future<void> main() async {
  final c = Rtek.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureBuyer3();
  await c.ensureSeller2();

  final s1 = c.sellerId!;
  final s2 = c.seller2Id!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;
  final b3 = c.buyer3Id!;

  await c.restoreSeller1Published();
  await c.setHub(s2, false);
  await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'user_type': 'vendedor',
    'handle': 'rtek1910s2',
  }, prefer: 'return=minimal');

  c.note('fix.s1', 'S1 published', await c.profile(s1), lens: 'EK1');
  c.note('fix.s2', 'S2 unpublished', await c.profile(s2), lens: 'EK1');
  c.note('fix.b3', 'B3 fresco CPI', b3, lens: 'EK6');

  try {
    await runA(c, s1: s1, b1: b1, b2: b2);
    await runB(c, s1: s1, b1: b1, b2: b2, b3: b3);
    await runC(c, s1: s1, b1: b1, b2: b2);
    await runD(c, s1: s1, b1: b1, b2: b2, b3: b3);
  } finally {
    await c.endAllCreatedLives();
    await c.restoreSeller1Published();
    final after = await c.profile(s1);
    c.note('restore.s1', 'S1 hub_published after', after?['hub_published'],
        lens: 'EK1');
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
    'auditor': 'REDTEAM_BLIND_EK_COMPOSICAO_POS_OPEN_v1',
    'prefix': prefix,
    'staging': projectMust,
    'probes': c.probes,
    'findings': c.findings,
    'blocked': c.blocked,
    'skipped': c.skipped,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
    'classe_nova': c.classeNova.toList()..sort(),
    'actors': {'b1': b1, 's1': s1, 'b2': b2, 's2': s2, 'b3': b3},
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
      'disputes': c.createdDisputeIds,
    },
  });
  stdout.writeln('WROTE ${outDir()}/pass1.json probes=${c.probes.length} '
      'findings=${c.findings.length} nova=${c.classeNova.length}');
}

Future<void> runA(
  Rtek c, {
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
    'idempotency_key': 'rtek1910unpubpay',
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
    c.skip('A1', 'EK1', 'unpublish RPC não pegou', unpub);
  } else if (tipCredited) {
    a1result = 'HOLD';
    c.hold(
      id: 'P0-A1-TIP',
      lens: 'EK4',
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
    c.block('A1', 'EK1', 'unpublish mid-CPI+tip; tip unpaid; payout observado', {
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
    lens: 'EK1',
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
    c.skip('A5', 'EK1', 'sku A2 fail', 'null');
  } else if (hubShowsSold && insertOkSold) {
    a2result = 'HOLD';
    c.hold(
      id: 'P2-A5-SOLD-HUB',
      lens: 'EK1',
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
    c.block('A5', 'EK1', 'sold+listed: Hub/insert observados', {
      'hub_n': hubA2?.list.length,
      'ins': insA2?.brief,
      'sold': prodA2?['is_sold'],
      'listed': prodA2?['list_on_marketplace'],
    });
  }
  c.probe(
    id: 'A5',
    surfaces: 'Hub + products + orders',
    action: 'sold+listed vs vitrine vs insert',
    http: {'hub': hubA2?.brief, 'ins': insA2?.brief},
    oracles: {
      'hub_n': hubA2?.list.length,
      'ins_ok': insertOkSold,
      'sold': prodA2?['is_sold'],
    },
    result: a2result,
    lens: 'EK1',
    residual: true,
    countFinding: a2result == 'HOLD',
  );

  // ----- A3 leftover após pago parcial -----
  final paidA3 = await c.payToPago(lens: 'EK1', initialQty: 2);
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
    c.skip('A2', 'EK1', 'paid A3 fail', 'null');
  } else if ('${ordA3?['status']}' == 'pago' && qtyA3 == 1 && leftoverBuyable) {
    a3result = 'FAIL';
    c.block('A2', 'EK1', 'leftover após pago: Hub+CPI coerentes', {
      'status': ordA3?['status'],
      'qty': qtyA3,
      'hub_n': hubA3?.list.length,
      'cs': cpiA3?.sessionId,
    });
  } else if ('${ordA3?['status']}' == 'pago' && qtyA3 <= 0 && leftoverBuyable) {
    a3result = 'HOLD';
    c.hold(
      id: 'P1-A2-GHOST-LEFTOVER',
      lens: 'EK1',
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
    c.block('A2', 'EK1', 'leftover após pago observado', {
      'status': ordA3?['status'],
      'qty': qtyA3,
      'hub_n': hubA3?.list.length,
      'cpi': cpiA3?.brief,
      'pi': paidA3?.pi,
    });
  }
  c.probe(
    id: 'A2',
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
    lens: 'EK1',
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
    c.skip('A3', 'EK1', 'sku A4 fail', 'null');
  } else if (twoOwners) {
    a4result = 'HOLD';
    c.hold(
      id: 'P1-A3-DOUBLE-HOLD',
      lens: 'EK1',
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
    c.block('A3', 'EK1', 'follow+favorite+hold: ≤1 dono; Hub/fav/follow', {
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
    id: 'A3',
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
    lens: 'EK1',
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
  final itemSt = '${liA5row?['status'] ?? ''}';
  final itemStillAvailable = itemSt == 'available';
  // Anti-atrofia: Hub hide rifa drawn qty=1 — 1 linha, NÃO contar.
  // Classe nova DTDY/DU: Hub 0 MAS live_item continua available.
  final hubHideClassic = winA5.isNotEmpty && hubA5n == 1;
  final liveItemStale =
      winA5.isNotEmpty && hubA5n == 0 && itemStillAvailable;
  final sealedHubOpenStock =
      winA5.isNotEmpty && hubA5n == 0 && (insA5?.ok == true);
  String a5result;
  if (skuA5 == null || liveA5 == null || rafA5?.firstId == null) {
    a5result = 'SKIP';
    c.skip('A4', 'EK7', 'raffle A5 fixture', rafA5?.brief ?? 'null');
  } else if (liveItemStale || sealedHubOpenStock) {
    a5result = 'HOLD';
    c.hold(
      id: liveItemStale ? 'P2-A5-LIVEITEM-AVAILABLE' : 'P2-A5-SEAL-STOCK',
      lens: 'EK7',
      severity: 'P2',
      title: liveItemStale
          ? 'Rifa drawn: Hub 0 mas live_item continua available'
          : 'Hub ocultou o prémio mas insert marketplace ainda abre',
      actor: 'S1 draw + Hub + live_item + B2 insert',
      pre: 'rifa drawn winner B1; qty=1',
      repro: 'draw + hub_products_public + live_items.status + POST orders',
      expected: 'live_item ≠ available; Hub 0; insert deny',
      obtained: {
        'hub_n': hubA5n,
        'qty': qtyA5,
        'ins': insA5?.brief,
        'winners': winA5.length,
        'prize_n': prizeA5.length,
        'item': liA5row?['status'],
        'item_active': liA5row?['is_active'],
      },
    );
  } else if (hubHideClassic) {
    a5result = 'FAIL';
    c.block('A4', 'EK7', 'Hub hide rifa drawn clássico — anti-atrofia', {
      'hub_n': hubA5n,
      'item': itemSt,
      'note': 'não contar',
    });
  } else {
    a5result = 'FAIL';
    c.block('A4', 'EK7', 'rifa drawn + Hub + live_item selados', {
      'hub_n': hubA5n,
      'qty': qtyA5,
      'ins': insA5?.brief,
      'winners': winA5.length,
      'prize_n': prizeA5.length,
      'item': itemSt,
    });
  }
  c.probe(
    id: 'A4',
    surfaces: 'rifa + Hub + products + insert + live_item',
    action: 'draw winner + Hub + live_item ≠ available (reteste DU)',
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
      'item': itemSt,
      'item_active': liA5row?['is_active'],
    },
    result: a5result,
    lens: 'EK7',
    classeNova: true,
    countFinding: a5result == 'HOLD' && !hubHideClassic,
  );
}

Future<void> runB(
  Rtek c, {
  required String s1,
  required String b1,
  required String b2,
  required String b3,
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
    c.skip('C1', 'EK2', 'fixture B1 fail', 'null');
  } else if (accepted && !bagOk && denied(bagB ?? HttpHit(0, '', {}))) {
    b1result = 'HOLD';
    c.hold(
      id: 'P2-C1-CROSS-LINE',
      lens: 'EK2',
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
    c.block('C1', 'EK2', 'rifa+accept A não cega bag B; Hub A/B', {
      'accepted': accepted,
      'bag_cs': bagB?.sessionId,
      'hubA': hubA?.list.length,
      'hubB': hubB?.list.length,
      'raf': rafB1?.firstId,
    });
  }
  c.probe(
    id: 'C1',
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
    lens: 'EK2',
    classeNova: true,
    countFinding: b1result == 'HOLD',
  );

  // ----- B3 bag∥single + Hub (classe_nova POS_OPEN) -----
  final skusBs = <String>[];
  final oidsBs = <String>[];
  HttpHit? bagHit;
  HttpHit? singleHit;
  Map<String, Object?>? bagOr;
  Map<String, Object?>? singleOr;
  final hubBs = <int>[];
  final ledgerBs = <String>[];
  for (var i = 0; i < 3; i++) {
    final pid = await c.createProduct(
      title: '$prefix B3 bag-single-$i',
      qty: 2,
      listed: true,
      live: false,
    );
    if (pid == null) continue;
    skusBs.add(pid);
    final oid = await c.insertOrder(
      productId: pid,
      jwt: c.buyer3Jwt,
      buyer: b3,
      price: 12.0,
    );
    if (oid != null) oidsBs.add(oid);
  }
  List<Map<String, Object?>> bsLines(List<int> idx) => [
        for (final i in idx)
          if (i < oidsBs.length && i < skusBs.length)
            {
              'order_id': oidsBs[i],
              'product_id': skusBs[i],
              'quantity': 1,
              'price': 12.0,
            },
      ];
  if (oidsBs.length == 3) {
    final raced = await Future.wait([
      c.checkoutBag(
        lines: bsLines([0, 1, 2]),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
      ),
      c.checkout(
        orderId: oidsBs[1],
        productId: skusBs[1],
        jwt: c.buyer3Jwt,
        buyer: b3,
      ),
    ]);
    bagHit = raced[0];
    singleHit = raced[1];
    if (c.usefulCs(bagHit)) c.createdSessionIds.add(bagHit.sessionId!);
    if (c.usefulCs(singleHit)) c.createdSessionIds.add(singleHit.sessionId!);
    bagOr = await c.sessionOracle(bagHit.sessionId);
    singleOr = await c.sessionOracle(singleHit.sessionId);
  }
  for (final pid in skusBs) {
    hubBs.add((await c.hubSku(pid, jwt: c.buyer3Jwt)).list.length);
  }
  for (final oid in oidsBs) {
    ledgerBs.add('${(await c.orderRow(oid))?['stripe_checkout_session_id'] ?? ''}');
  }
  final csBs = [bagHit, singleHit].where(c.usefulCs).length;
  final openBs = [bagOr, singleOr]
      .where((o) => o != null && o['status'] == 'open')
      .length;
  final twoBs = csBs >= 2 && (c.stripeTestKey == null || openBs >= 2);
  String b3gate;
  if (oidsBs.length < 3) {
    b3gate = 'SKIP';
    c.skip('B3', 'EK6', 'fixture bag∥single 3 linhas', oidsBs.length);
  } else if (twoBs) {
    b3gate = 'HOLD';
    c.hold(
      id: 'P1-B3-BAG-SINGLE-HUB',
      lens: 'EK6',
      severity: 'P1',
      title: 'Saco de 3 e pagamento avulso da linha do meio: dois links',
      actor: 'B3 bag ABC ∥ CPI linha B',
      pre: '3 SKUs qty=2 Hub visíveis',
      repro: 'Future.wait checkoutBag ABC ∥ checkout single B; Hub',
      expected: '≤1 cs_ open/payable; Hub coerente',
      obtained: {
        'cs_n': csBs,
        'open': openBs,
        'bag': bagOr,
        'single': singleOr,
        'hub': hubBs,
        'ledger': ledgerBs,
      },
    );
  } else {
    b3gate = 'FAIL';
    c.block('B3', 'EK6', 'bag∥single + Hub: ≤1 cs_ ou 2.ª expired', {
      'cs_n': csBs,
      'open': openBs,
      'bag': bagOr,
      'single': singleOr,
      'hub': hubBs,
      'ledger': ledgerBs,
    });
  }
  c.probe(
    id: 'B3',
    surfaces: 'bag + single CPI + Hub + orders',
    action: 'Future.wait saco ABC ∥ avulso B; Hub stock',
    http: {'bag': bagHit?.brief, 'single': singleHit?.brief},
    oracles: {
      'cs_n': csBs,
      'open': openBs,
      'bag': bagOr,
      'single': singleOr,
      'hub_ns': hubBs,
      'ledger': ledgerBs,
    },
    result: b3gate,
    lens: 'EK6',
    classeNova: true,
    countFinding: b3gate == 'HOLD',
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
    c.skip('D3', 'EK5', 'fixture B3', 'null');
  } else {
    b3result = 'FAIL';
    c.block('D3', 'EK5', 'end_live∥bag∥Hub observados', {
      'end': endH?.brief,
      'bag': bagRace?.brief,
      'hub_n': hubRace?.list.length,
      'live': liveRow,
      'hub_live_n': hubLive?.list.length,
    });
  }
  c.probe(
    id: 'D3',
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
    lens: 'EK5',
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
    c.skip('C5', 'EK7', 'raffle B4 fixture', rafB4?.brief ?? 'null');
  } else if (twoOwners || doubleClaim) {
    b4result = 'HOLD';
    c.hold(
      id: 'P1-C5-DRAW-CPI',
      lens: 'EK5',
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
    c.block('C5', 'EK5', 'rifa draw∥CPI marketplace: sem dois donos', {
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
    id: 'C5',
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
    lens: 'EK5',
    classeNova: true,
    countFinding: b4result == 'HOLD',
  );

  // ----- B5 6∥4 bag + Hub stock após 1 pago (composição DT) -----
  final paidB5 = await c.payToPago(lens: 'EK8', initialQty: 2, buyer: b1);
  HttpHit? hubPaid;
  Map<String, dynamic>? prodPaid;
  Map<String, dynamic>? ordPaid;
  final skus6 = <String>[];
  final oids6 = <String>[];
  HttpHit? bag6;
  HttpHit? bag4;
  final hubAfter = <int>[];
  Map<String, Object?>? s6or;
  Map<String, Object?>? s4or;
  if (paidB5 != null) {
    ordPaid = await c.orderRow(paidB5.oid);
    prodPaid = await c.productRow(paidB5.pid);
    hubPaid = await c.hubSku(paidB5.pid, jwt: c.buyerJwt);
  }
  for (var i = 0; i < 6; i++) {
    final pid = await c.createProduct(
      title: '$prefix B5 bag-$i',
      qty: 2,
      listed: true,
      live: false,
    );
    if (pid == null) continue;
    skus6.add(pid);
    final oid = await c.insertOrder(
      productId: pid,
      jwt: c.buyer3Jwt,
      buyer: b3,
      price: 12.0,
    );
    if (oid != null) oids6.add(oid);
  }
  List<Map<String, Object?>> bagLines(List<int> idx) => [
        for (final i in idx)
          if (i < oids6.length && i < skus6.length)
            {
              'order_id': oids6[i],
              'product_id': skus6[i],
              'quantity': 1,
              'price': 12.0,
            },
      ];
  if (oids6.length == 6) {
    final raced = await Future.wait([
      c.checkoutBag(
        lines: bagLines([0, 1, 2, 3, 4, 5]),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
      ),
      c.checkoutBag(
        lines: bagLines([1, 2, 3, 4]),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
      ),
    ]);
    bag6 = raced[0];
    bag4 = raced[1];
    if (c.usefulCs(bag6)) c.createdSessionIds.add(bag6.sessionId!);
    if (c.usefulCs(bag4)) c.createdSessionIds.add(bag4.sessionId!);
    s6or = await c.sessionOracle(bag6.sessionId);
    s4or = await c.sessionOracle(bag4.sessionId);
  }
  for (final pid in skus6) {
    final h = await c.hubSku(pid, jwt: c.buyer3Jwt);
    hubAfter.add(h.list.length);
  }
  final csN = [bag6, bag4].where(c.usefulCs).length;
  final openPayable = [
    s6or,
    s4or,
  ].where((o) => o != null && o['status'] == 'open').length;
  final leftoverHub = hubPaid?.list.length ?? -1;
  final leftoverQty = numOf(prodPaid?['quantity']) ?? -1;
  String b5result;
  if (paidB5 == null || oids6.length < 6) {
    b5result = 'SKIP';
    c.skip('B1', 'EK6', 'fixture B5 6∥4/pago', {
      'paid': paidB5?.hit.brief,
      'oids': oids6.length,
    });
  } else if (csN >= 2 && (openPayable >= 2 || c.stripeTestKey == null)) {
    b5result = 'HOLD';
    c.hold(
      id: 'P1-B1-64-BAG-HUB',
      lens: 'EK6',
      severity: 'P1',
      title: '6∥4 bag: duas Sessions úteis após pago leftover Hub',
      actor: 'B3 bag 6∥4; leftover pago B1',
      pre: '1 SKU pago leftover Hub; 6 linhas B3 qty=2',
      repro: 'setup_paid_order + Future.wait bag6 ∥ bag4',
      expected: '≤1 cs_ open; leftover Hub n=1 qty=1',
      obtained: {
        'cs_n': csN,
        'open': openPayable,
        's6': s6or,
        's4': s4or,
        'leftover_hub': leftoverHub,
        'leftover_qty': leftoverQty,
        'hub_bag': hubAfter,
        'paid_status': ordPaid?['status'],
      },
    );
  } else {
    b5result = 'FAIL';
    c.block('B1', 'EK6', '6∥4 bag + Hub leftover após pago observados', {
      'cs_n': csN,
      'open': openPayable,
      's6': s6or,
      's4': s4or,
      'leftover_hub': leftoverHub,
      'leftover_qty': leftoverQty,
      'hub_bag': hubAfter,
      'paid': ordPaid?['status'],
      'pi': paidB5.pi,
    });
  }
  c.probe(
    id: 'B1',
    surfaces: 'bag 6∥4 + Hub leftover + orders + products',
    action: 'pago leftover + Future.wait bag ABCDEF ∥ BCDE; Hub stock',
    http: {'paid': paidB5?.hit.brief, 'bag6': bag6?.brief, 'bag4': bag4?.brief},
    oracles: {
      'cs_n': csN,
      'open_payable': openPayable,
      's6': s6or,
      's4': s4or,
      'leftover_hub': leftoverHub,
      'leftover_qty': leftoverQty,
      'hub_bag_ns': hubAfter,
      'pi': paidB5?.pi,
    },
    result: b5result,
    lens: 'EK6',
    classeNova: true,
    countFinding: b5result == 'HOLD',
  );
}

Future<void> runC(
  Rtek c, {
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
    c.skip('C2', 'EK6', 'offer C1 fail', off?.brief ?? 'null');
  } else if (under) {
    c1result = 'HOLD';
    c.hold(
      id: 'P0-C2-UNDERPAY',
      lens: 'EK6',
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
    c.block('C2', 'EK6', 'oferta aceite: selo servidor vs amount=1', {
      'offer': offRow?['amount'],
      'status': offRow?['status'],
      'sealed': sealed,
      'hub_n': hubC1?.list.length,
      'cpi': cpiC1?.brief,
      'ord': ordC1?['status'],
    });
  }
  c.probe(
    id: 'C2',
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
    lens: 'EK6',
    classeNova: true,
    countFinding: c1result == 'HOLD',
  );

  // ----- B4 bag pago único → Hub / order / chat / wallet (4 sítios) -----
  final wS0bag = await c.walletBal(s1);
  final wB0bag = await c.walletBal(b1);
  final paidBag = await c.payBag(seller: s1, buyer: b1);
  c.note('fixture.bag', 'setup_paid_bag Stripe TEST 4242', paidBag.brief,
      lens: 'EK8');
  final bagMap = paidBag.map ?? {};
  final oidA = bagMap['order_a_id']?.toString();
  final oidB = bagMap['order_b_id']?.toString();
  final pidA = bagMap['product_a_id']?.toString();
  final pidB = bagMap['product_b_id']?.toString();
  if (oidA != null) c.createdOrderIds.add(oidA);
  if (oidB != null) c.createdOrderIds.add(oidB);
  if (pidA != null) c.createdProductIds.add(pidA);
  if (pidB != null) c.createdProductIds.add(pidB);
  Map<String, dynamic>? ordA;
  Map<String, dynamic>? ordB;
  Map<String, dynamic>? prodA;
  Map<String, dynamic>? prodB;
  HttpHit? hubA4;
  HttpHit? hubB4;
  HttpHit? cardA;
  HttpHit? cardB;
  if (oidA != null) ordA = await c.orderRow(oidA);
  if (oidB != null) ordB = await c.orderRow(oidB);
  if (pidA != null) {
    prodA = await c.productRow(pidA);
    hubA4 = await c.hubSku(pidA, jwt: c.buyerJwt);
    final chatA = await c.ensureChat(pidA);
    if (chatA != null && oidA != null) {
      cardA = await c.postCard(chatA, {
        'kind': 'reservation_payment_submitted',
        'order_id': oidA,
        'notes': 'bag',
      });
    }
  }
  if (pidB != null) {
    prodB = await c.productRow(pidB);
    hubB4 = await c.hubSku(pidB, jwt: c.buyerJwt);
    final chatB = await c.ensureChat(pidB);
    if (chatB != null && oidB != null) {
      cardB = await c.postCard(chatB, {
        'kind': 'reservation_payment_submitted',
        'order_id': oidB,
        'notes': 'bag',
      });
    }
  }
  final wS1bag = await c.walletBal(s1);
  final wB1bag = await c.walletBal(b1);
  final bothPago =
      '${ordA?['status']}' == 'pago' && '${ordB?['status']}' == 'pago';
  final paidA = numOf(ordA?['amount_paid_cents']) ?? 0;
  final paidB = numOf(ordB?['amount_paid_cents']) ?? 0;
  final piAmt = numOf(bagMap['pi_amount_cents']) ?? 0;
  final lineHasFull = piAmt > 0 && (paidA == piAmt || paidB == piAmt);
  final qtyDrop =
      (numOf(prodA?['quantity']) ?? 3) < 3 && (numOf(prodB?['quantity']) ?? 3) < 3;
  final leftoverHub =
      (hubA4?.list.length ?? 0) == 1 && (hubB4?.list.length ?? 0) == 1;
  String b4result;
  if (!paidBag.ok || oidA == null || oidB == null) {
    b4result = 'SKIP';
    c.skip('B4', 'EK8', 'setup_paid_bag fail', paidBag.brief);
  } else if (!bothPago) {
    b4result = 'HOLD';
    c.hold(
      id: 'P1-B4-BAG-NOT-PAGO',
      lens: 'EK8',
      severity: 'P1',
      title: 'Saco Stripe TEST succeeded mas uma linha ≠ pago',
      actor: 'e2e setup_paid_bag 4242',
      pre: '2 linhas mesmo PI',
      repro: 'setup_paid_bag + Hub/order/chat/wallet',
      expected: 'ambas pago; Hub leftover; wallet sem mint',
      obtained: {
        'ordA': ordA?['status'],
        'ordB': ordB?['status'],
        'hubA': hubA4?.list.length,
        'hubB': hubB4?.list.length,
      },
    );
  } else if (lineHasFull) {
    b4result = 'HOLD';
    c.hold(
      id: 'P0-B4-BAG-FULL-LINE',
      lens: 'EK8',
      severity: 'P0',
      title: 'Uma linha do saco ficou com o PI inteiro',
      actor: 'setup_paid_bag',
      pre: '2 linhas mesmo PI',
      repro: 'amount_paid_cents vs pi_amount',
      expected: 'nenhuma linha = PI completo; soma = PI',
      obtained: {'paidA': paidA, 'paidB': paidB, 'pi': piAmt},
    );
  } else if (!qtyDrop) {
    b4result = 'HOLD';
    c.hold(
      id: 'P1-B4-BAG-STOCK',
      lens: 'EK8',
      severity: 'P1',
      title: 'Saco pago sem baixar stock nas duas linhas',
      actor: 'settle bag',
      pre: 'qty inicial 3 cada',
      repro: 'setup_paid_bag + products.quantity',
      expected: 'qty 3→2 em A e B',
      obtained: {'qtyA': prodA?['quantity'], 'qtyB': prodB?['quantity']},
    );
  } else {
    b4result = 'FAIL';
    c.block('B4', 'EK8', 'bag pago único: 4 sítios observados', {
      'both_pago': bothPago,
      'paidA': paidA,
      'paidB': paidB,
      'pi': piAmt,
      'hubA': hubA4?.list.length,
      'hubB': hubB4?.list.length,
      'leftover_hub': leftoverHub,
      'qtyA': prodA?['quantity'],
      'qtyB': prodB?['quantity'],
      'dSeller': wS1bag - wS0bag,
      'dBuyer': wB1bag - wB0bag,
      'cardA': cardA?.brief,
      'cardB': cardB?.brief,
      'pi_id': bagMap['payment_intent_id'],
    });
  }
  c.probe(
    id: 'B4',
    surfaces: 'Hub + orders + chat + wallet',
    action: 'saco pago Stripe TEST 4242 → 4 oráculos',
    http: paidBag.brief,
    oracles: {
      'both_pago': bothPago,
      'paidA': paidA,
      'paidB': paidB,
      'pi_amt': piAmt,
      'hubA_n': hubA4?.list.length,
      'hubB_n': hubB4?.list.length,
      'qtyA': prodA?['quantity'],
      'qtyB': prodB?['quantity'],
      'dSeller': wS1bag - wS0bag,
      'dBuyer': wB1bag - wB0bag,
      'cardA_ok': cardA?.ok,
      'cardB_ok': cardB?.ok,
      'pi': bagMap['payment_intent_id'],
    },
    result: b4result,
    lens: 'EK8',
    classeNova: true,
    countFinding: b4result == 'HOLD',
  );

  // ----- C3 release∥disputa + chat card + wallet (composição DW) -----
  final paidC3 = await c.payToPago(lens: 'EK4', initialQty: 2);
  HttpHit? plantC3;
  HttpHit? relC3;
  HttpHit? dispC3;
  HttpHit? cardC3;
  HttpHit? hubC3;
  Map<String, dynamic>? ordC3;
  Map<String, dynamic>? dispRow;
  String? chatC3;
  final wS0c3 = await c.walletBal(s1);
  if (paidC3 != null) {
    plantC3 = await c.plantConcluidoMao(paidC3.oid);
    chatC3 = await c.ensureChat(paidC3.pid);
    final raced = await Future.wait([
      c.tryRelease(paidC3.oid, jwt: c.buyerJwt),
      c.insertDispute(orderId: paidC3.oid),
    ]);
    relC3 = raced[0];
    dispC3 = raced[1];
    ordC3 = await c.orderRow(paidC3.oid);
    if (dispC3.firstId != null) dispRow = await c.disputeRow(dispC3.firstId!);
    hubC3 = await c.hubSku(paidC3.pid, jwt: c.buyerJwt);
    if (chatC3 != null) {
      cardC3 = await c.postCard(chatC3, {
        'kind': 'dispute_opened',
        'order_id': paidC3.oid,
        'dispute_id': dispC3.firstId,
        'notes': 'RTEK C3',
      });
    }
  }
  final wS1c3 = await c.walletBal(s1);
  final releasedC3 = c.releasedTrue(relC3);
  final dWalletC3 = wS1c3 - wS0c3;
  final dispOpen = dispC3 != null &&
      dispC3.ok &&
      '${dispRow?['status'] ?? ''}' == 'aberta';
  final twoEffects = releasedC3 && dWalletC3 > 0 && dispOpen;
  String c3result;
  if (paidC3 == null) {
    c3result = 'SKIP';
    c.skip('C3', 'EK4', 'paid C3 fail', 'null');
  } else if (twoEffects) {
    c3result = 'HOLD';
    c.hold(
      id: 'P1-C3-RELEASE-DISPUTE-CHAT',
      lens: 'EK4',
      severity: 'P1',
      title: 'Release creditou E disputa aberta; card chat visível',
      actor: 'B1 release ∥ disputa + card',
      pre: 'pago Stripe; plant concluido+mão',
      repro: 'Future.wait release + POST disputa; POST chat card',
      expected: '1 efeito (crédito XOR disputa) + chat coerente',
      obtained: {
        'rel': relC3?.brief,
        'disp': dispC3?.brief,
        'dWallet': dWalletC3,
        'card': cardC3?.brief,
        'status': ordC3?['status'],
        'hub_n': hubC3?.list.length,
        'disp_st': dispRow?['status'],
      },
    );
  } else {
    c3result = 'FAIL';
    c.block('C3', 'EK4', 'release∥disputa: 1 efeito (anti-atrofia) + chat', {
      'rel': relC3?.brief,
      'disp': dispC3?.brief,
      'dWallet': dWalletC3,
      'released': releasedC3,
      'disp_open': dispOpen,
      'card': cardC3?.brief,
      'status': ordC3?['status'],
      'hub_n': hubC3?.list.length,
      'plant': plantC3?.brief,
      'note': '1 efeito = HOLD anti-atrofia, não contar',
    });
  }
  c.probe(
    id: 'C3',
    surfaces: 'wallet + disputa + chat card + Hub leftover',
    action: 'Future.wait release∥disputa em concluido+mão + card chat',
    http: {
      'plant': plantC3?.brief,
      'rel': relC3?.brief,
      'disp': dispC3?.brief,
      'card': cardC3?.brief,
    },
    oracles: {
      'released': releasedC3,
      'dWallet': dWalletC3,
      'disp_open': dispOpen,
      'disp_st': dispRow?['status'],
      'card_ok': cardC3?.ok,
      'status': ordC3?['status'],
      'hub_n': hubC3?.list.length,
      'pi': paidC3?.pi,
    },
    result: c3result,
    lens: 'EK4',
    classeNova: true,
    countFinding: twoEffects,
  );

  // ----- C4 revoke proof mid-disputa + proof_ok + UI path -----
  final paidC4 = await c.payToPago(lens: 'EK3', initialQty: 1);
  HttpHit? upC4;
  HttpHit? dispC4;
  HttpHit? delC4;
  HttpHit? revC4;
  HttpHit? okC4;
  HttpHit? replyC4;
  HttpHit? authAfter;
  Map<String, dynamic>? dispAfter;
  String? pathC4;
  String? signedC4;
  String? noQC4;
  if (paidC4 != null) {
    await c.plantConcluidoMao(paidC4.oid);
    pathC4 = c.disputeObj(b1, paidC4.oid, 'mid.png');
    upC4 = await c.storageUpload(
      objectName: pathC4,
      bytes: pngBytes,
      jwt: c.buyerJwt,
    );
    signedC4 = await c.signObject(pathC4, jwt: c.buyerJwt);
    noQC4 =
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/$pathC4';
    final proofUrl = signedC4 ?? noQC4 ?? '';
    dispC4 = await c.insertDispute(
      orderId: paidC4.oid,
      photos: proofUrl.isEmpty ? null : [proofUrl],
    );
    delC4 = await c.storageDelete(pathC4, jwt: c.buyerJwt);
    revC4 = await c.revokePath(pathC4, jwt: c.buyerJwt);
    okC4 = await c.proofOk(
      noQC4,
      service: true,
      buyer: b1,
      oid: paidC4.oid,
    );
    authAfter = await c.storageGet(pathC4, jwt: c.buyerJwt);
    if (dispC4.firstId != null) {
      replyC4 = await c.insertReply(
        disputeId: dispC4.firstId!,
        photos: noQC4 == null ? null : [noQC4],
        message: 'RTEK C4 UI path after revoke',
      );
      dispAfter = await c.disputeRow(dispC4.firstId!);
    }
  }
  final proofStillOk = '${okC4?.body}'.toLowerCase().contains('true');
  final uiStillAccepts = replyC4 != null && replyC4.ok;
  String c4result;
  if (paidC4 == null || upC4 == null || !upC4.ok) {
    c4result = 'SKIP';
    c.skip('C4', 'EK3', 'upload/pago C4 fail', upC4?.brief ?? 'null');
  } else if (proofStillOk || uiStillAccepts) {
    c4result = 'HOLD';
    c.hold(
      id: 'P2-C4-REVOKE-MID-DISPUTE',
      lens: 'EK3',
      severity: 'P2',
      title: 'Revoke a meio da disputa: proof_ok/UI ainda aceitam URL morta',
      actor: 'B1 disputa + revoke + reply',
      pre: 'pago; upload PNG; disputa aberta com signed URL',
      repro: 'DELETE+revoke mid-disputa → proof_ok + POST reply',
      expected: 'proof_ok false; reply/path UI recusa URL revogada',
      obtained: {
        'up': upC4.brief,
        'disp': dispC4?.brief,
        'del': delC4?.brief,
        'rev': revC4?.body,
        'proof_ok': okC4?.body,
        'auth': authAfter?.brief,
        'reply': replyC4?.brief,
        'disp_st': dispAfter?['status'],
      },
    );
  } else {
    c4result = 'FAIL';
    c.block('C4', 'EK3', 'revoke mid-disputa: proof_ok/UI fechados', {
      'up': upC4.brief,
      'disp': dispC4?.brief,
      'rev': revC4?.body,
      'proof_ok': okC4?.body,
      'auth': authAfter?.brief,
      'reply': replyC4?.brief,
      'disp_st': dispAfter?['status'],
    });
  }
  c.probe(
    id: 'C4',
    surfaces: 'storage + disputa + proof_ok + chat/reply UI',
    action: 'revoke proof mid-disputa + proof_ok + reply UI path',
    http: {
      'up': upC4?.brief,
      'disp': dispC4?.brief,
      'rev': revC4?.brief,
      'ok': okC4?.brief,
      'reply': replyC4?.brief,
    },
    oracles: {
      'proof_ok': okC4?.body,
      'auth': authAfter?.status,
      'reply_ok': replyC4?.ok,
      'disp_st': dispAfter?['status'],
      'pi': paidC4?.pi,
      'path': pathC4,
    },
    result: c4result,
    lens: 'EK3',
    classeNova: true,
    countFinding: c4result == 'HOLD',
  );
}

Future<void> runD(
  Rtek c, {
  required String s1,
  required String b1,
  required String b2,
  required String b3,
}) async {
  // ----- D1 refund ∥ nova compra leftover (residual race) -----
  final paidD1 = await c.payToPago(lens: 'EK5', initialQty: 2);
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
    c.skip('D2', 'EK5', 'paid D1 fail', 'null');
  } else if (q1 < 0 || q1 > q0 + 2) {
    d1result = 'HOLD';
    c.hold(
      id: 'P1-D2-STOCK-RACE',
      lens: 'EK5',
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
    c.block('D2', 'EK5', 'refund∥leftover CPI stock observado', {
      'qty': '$q0→$q1',
      'rf': rf?.brief,
      'cpi': cpiNew?.brief,
      'old': oldOrd?['status'],
      'new': newOrd?['status'],
    });
  }
  c.probe(
    id: 'D2',
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
    lens: 'EK5',
    residual: true,
    countFinding: d1result == 'HOLD',
  );

  // ----- D2 2 buyers Hub visível + CPI qty=1 (race) -----
  final skuD2 = await c.createProduct(
    title: '$prefix D2 two-buyers',
    qty: 1,
    listed: true,
    live: false,
  );
  HttpHit? hubD2;
  HttpHit? cpi1;
  HttpHit? cpi2;
  HttpHit? hubAfterD2;
  String? o1;
  String? o2;
  if (skuD2 != null) {
    hubD2 = await c.hubSku(skuD2, anon: true);
    o1 = await c.insertOrder(
      productId: skuD2,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 12.0,
    );
    o2 = await c.insertOrder(
      productId: skuD2,
      jwt: c.buyer3Jwt,
      buyer: b3,
      price: 12.0,
    );
    final raced = await Future.wait([
      if (o1 != null)
        c.checkout(
          orderId: o1,
          productId: skuD2,
          jwt: c.buyer2Jwt,
          buyer: b2,
        )
      else
        Future.value(HttpHit(0, 'no_o1', {})),
      if (o2 != null)
        c.checkout(
          orderId: o2,
          productId: skuD2,
          jwt: c.buyer3Jwt,
          buyer: b3,
        )
      else
        Future.value(HttpHit(0, 'no_o2', {})),
    ]);
    cpi1 = raced[0];
    cpi2 = raced[1];
    if (c.usefulCs(cpi1)) c.createdSessionIds.add(cpi1.sessionId!);
    if (c.usefulCs(cpi2)) c.createdSessionIds.add(cpi2.sessionId!);
    hubAfterD2 = await c.hubSku(skuD2, jwt: c.buyer2Jwt);
  }
  final two = [cpi1, cpi2].where(c.usefulCs).length;
  String d2result;
  if (skuD2 == null) {
    d2result = 'SKIP';
    c.skip('D1', 'EK5', 'sku D2 fail', 'null');
  } else if (two >= 2) {
    d2result = 'HOLD';
    c.hold(
      id: 'P1-D1-TWO-CS',
      lens: 'EK5',
      severity: 'P1',
      title: '2 buyers Hub-visível: 2 cs_ no qty=1',
      actor: 'B2∥B3 CPI',
      pre: 'Hub lista SKU qty=1',
      repro: 'Future.wait insert+CPI B2 ∥ B3',
      expected: '≤1 cs_ útil; 2.º insert ou CPI deny',
      obtained: {
        'hub0': hubD2?.list.length,
        'hub1': hubAfterD2?.list.length,
        'b2': cpi1?.brief,
        'b3': cpi2?.brief,
        'o1': o1,
        'o2': o2,
      },
    );
  } else {
    d2result = 'FAIL';
    c.block('D1', 'EK5', '2 buyers Hub visível: ≤1 cs_', {
      'hub0': hubD2?.list.length,
      'hub1': hubAfterD2?.list.length,
      'cs_n': two,
      'o2': o2,
      'b2': cpi1?.brief,
      'b3': cpi2?.brief,
    });
  }
  c.probe(
    id: 'D1',
    surfaces: 'Hub + CPI B2 + CPI B3 + orders',
    action: 'Future.wait 2 buyers insert+CPI qty=1 Hub-visível',
    http: {'hub': hubD2?.brief, 'b2': cpi1?.brief, 'b3': cpi2?.brief},
    oracles: {
      'hub0': hubD2?.list.length,
      'hub1': hubAfterD2?.list.length,
      'cs_n': two,
      'sid1': cpi1?.sessionId,
      'sid2': cpi2?.sessionId,
      'o2_ok': o2 != null,
    },
    result: d2result,
    lens: 'EK5',
    countFinding: d2result == 'HOLD',
  );

  // ----- D3 pago 4242 → Hub + order + wallet + chat (4 sítios) -----
  final wB0 = await c.walletBal(c.buyerId);
  final wS0 = await c.walletBal(c.sellerId);
  final paidD3 = await c.payToPago(lens: 'EK8', initialQty: 2);
  Map<String, dynamic>? ordD3;
  Map<String, dynamic>? prodD3;
  HttpHit? hubD3;
  HttpHit? cardD3;
  List<Map<String, dynamic>> chats = const [];
  List<Map<String, dynamic>> msgsD3 = const [];
  var wB1d = wB0;
  var wS1d = wS0;
  if (paidD3 != null) {
    ordD3 = await c.orderRow(paidD3.oid);
    prodD3 = await c.productRow(paidD3.pid);
    hubD3 = await c.hubSku(paidD3.pid, jwt: c.buyerJwt);
    final chatId = await c.ensureChat(paidD3.pid);
    if (chatId != null) {
      cardD3 = await c.postCard(chatId, {
        'kind': 'reservation_payment_submitted',
        'order_id': paidD3.oid,
        'notes': 'pago',
      });
    }
    chats = await c.chatsForProduct(paidD3.pid);
    msgsD3 = await c.chatMsgsForOrder(paidD3.oid);
    wB1d = await c.walletBal(c.buyerId);
    wS1d = await c.walletBal(c.sellerId);
  }
  final statusPago = '${ordD3?['status']}' == 'pago';
  final qtyDrop = (numOf(prodD3?['quantity']) ?? 2) < 2;
  String d3result;
  if (paidD3 == null) {
    d3result = 'SKIP';
    c.skip('D4', 'EK8', 'setup_paid_order fail', 'null');
  } else if (!statusPago) {
    d3result = 'HOLD';
    c.hold(
      id: 'P1-D4-NOT-PAGO',
      lens: 'EK8',
      severity: 'P1',
      title: 'Stripe TEST succeeded mas order ≠ pago',
      actor: 'e2e setup_paid_order 4242',
      pre: 'PI pm_card_visa',
      repro: 'setup_paid_order',
      expected: 'status=pago visível Hub/order/wallet/chat',
      obtained: ordD3,
    );
  } else if (!qtyDrop) {
    d3result = 'HOLD';
    c.hold(
      id: 'P1-D4-STOCK',
      lens: 'EK8',
      severity: 'P1',
      title: 'Pago Stripe sem baixar stock',
      actor: 'settle',
      pre: 'initial_qty=2 compra 1',
      repro: 'setup_paid_order',
      expected: 'quantity 2→1',
      obtained: prodD3,
    );
  } else {
    d3result = 'FAIL';
    c.block('D4', 'EK8', 'pago 4242: 4 sítios observados', {
      'status': ordD3?['status'],
      'qty': prodD3?['quantity'],
      'hub_n': hubD3?.list.length,
      'dSeller': wS1d - wS0,
      'dBuyer': wB1d - wB0,
      'chats_n': chats.length,
      'card': cardD3?.brief,
      'msgs_n': msgsD3.length,
      'pi': paidD3.pi,
      'paid_cents': ordD3?['amount_paid_cents'],
    });
  }
  c.probe(
    id: 'D4',
    surfaces: 'Hub + order + wallet + chat',
    action: 'pago Stripe TEST 4242 → 4 oráculos',
    http: paidD3?.hit.brief ?? 'n/a',
    oracles: {
      'status': ordD3?['status'],
      'qty': prodD3?['quantity'],
      'amount_paid_cents': ordD3?['amount_paid_cents'],
      'pi': paidD3?.pi,
      'hub_n': hubD3?.list.length,
      'dSeller': wS1d - wS0,
      'dBuyer': wB1d - wB0,
      'chats_n': chats.length,
      'card_ok': cardD3?.ok,
    },
    result: d3result,
    lens: 'EK8',
    countFinding: d3result == 'HOLD',
  );

  // ----- D4 expand bag subset→superset + settle só Session final open -----
  final skusD4 = <String>[];
  final oidsD4 = <String>[];
  HttpHit? bagSub;
  HttpHit? bagSuper;
  Map<String, Object?>? subOr;
  Map<String, Object?>? superOr;
  final hubD4n = <int>[];
  for (var i = 0; i < 4; i++) {
    final pid = await c.createProduct(
      title: '$prefix D4 expand-$i',
      qty: 2,
      listed: true,
      live: false,
    );
    if (pid == null) continue;
    skusD4.add(pid);
    final oid = await c.insertOrder(
      productId: pid,
      jwt: c.buyer3Jwt,
      buyer: b3,
      price: 14.0,
    );
    if (oid != null) oidsD4.add(oid);
  }
  List<Map<String, Object?>> d4lines(List<int> idx) => [
        for (final i in idx)
          if (i < oidsD4.length && i < skusD4.length)
            {
              'order_id': oidsD4[i],
              'product_id': skusD4[i],
              'quantity': 1,
              'price': 14.0,
            },
      ];
  if (oidsD4.length == 4) {
    final raced = await Future.wait([
      c.checkoutBag(
        lines: d4lines([0, 1]),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
      ),
      Future(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return c.checkoutBag(
          lines: d4lines([0, 1, 2, 3]),
          jwt: c.buyer3Jwt,
          buyer: b3,
          seller: s1,
        );
      }),
    ]);
    bagSub = raced[0];
    bagSuper = raced[1];
    if (c.usefulCs(bagSub)) c.createdSessionIds.add(bagSub.sessionId!);
    if (c.usefulCs(bagSuper)) c.createdSessionIds.add(bagSuper.sessionId!);
    subOr = await c.sessionOracle(bagSub.sessionId);
    superOr = await c.sessionOracle(bagSuper.sessionId);
  }
  for (final pid in skusD4) {
    hubD4n.add((await c.hubSku(pid, jwt: c.buyer3Jwt)).list.length);
  }
  final csD4 = [bagSub, bagSuper].where(c.usefulCs).length;
  final subOpen = subOr?['status'] == 'open';
  final superOpen = superOr?['status'] == 'open';
  final twoOpen = csD4 >= 2 &&
      (c.stripeTestKey == null || (subOpen && superOpen));
  String d4result;
  if (oidsD4.length < 4) {
    d4result = 'SKIP';
    c.skip('B2', 'EK6', 'fixture expand 4 linhas', oidsD4.length);
  } else if (twoOpen) {
    d4result = 'HOLD';
    c.hold(
      id: 'P1-B2-EXPAND-OPEN',
      lens: 'EK6',
      severity: 'P1',
      title: 'Expand subset→superset: duas Sessions ainda open',
      actor: 'B3 bag AB t=0 ∥ ABCD t=50ms',
      pre: '4 SKUs qty=2; subset 2 linhas depois superset 4',
      repro: 'Future.wait bag AB + sleep 50ms bag ABCD; Stripe status',
      expected: 'só Session final (superset) open; subset expired',
      obtained: {
        'cs_n': csD4,
        'sub': subOr,
        'super': superOr,
        'hub': hubD4n,
      },
    );
  } else {
    d4result = 'FAIL';
    c.block('B2', 'EK6', 'expand subset→superset: settle só final open', {
      'cs_n': csD4,
      'sub': subOr,
      'super': superOr,
      'hub': hubD4n,
      'sub_open': subOpen,
      'super_open': superOpen,
    });
  }
  c.probe(
    id: 'B2',
    surfaces: 'bag expand + Stripe Session + Hub stock',
    action: 'subset AB →50ms superset ABCD; só Session final open',
    http: {'sub': bagSub?.brief, 'super': bagSuper?.brief},
    oracles: {
      'cs_n': csD4,
      'sub': subOr,
      'super': superOr,
      'hub_ns': hubD4n,
      'stripe_key': c.stripeTestKey != null,
    },
    result: d4result,
    lens: 'EK6',
    classeNova: true,
    countFinding: d4result == 'HOLD',
  );
}
