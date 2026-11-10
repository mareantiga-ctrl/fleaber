/// RED TEAM CEGO DS pass1 — composição multi-superfície ≥16.
/// Staging only. NÃO corrigir. NÃO produção. NÃO Fase 4.
import 'dart:io';
import '_rtds.dart';

bool insertOk(HttpHit h) =>
    h.ok ||
    h.status == 409 ||
    h.body.contains('23505') ||
    h.body.toLowerCase().contains('duplicate');

Future<void> main() async {
  final c = Rtds.fromEnv(loadEnv());
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
    'handle': 'rtds1702s2',
  }, prefer: 'return=minimal');

  c.note('fix.s1', 'S1 published', await c.profile(s1), lens: 'DS1');
  c.note('fix.s2', 'S2 unpublished', await c.profile(s2), lens: 'DS1');

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
        lens: 'DS1');
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
    'auditor': 'REDTEAM_BLIND_DS_COMPOSICAO_POS_DHDM_v1',
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
    },
  });
  stdout.writeln('WROTE ${outDir()}/pass1.json probes=${c.probes.length} '
      'findings=${c.findings.length} nova=${c.classeNova.length}');
}

Future<void> runA(
  Rtds c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // ----- A1 unpublish mid-checkout AND mid-tip + payout (classe_nova) -----
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
  num wSeller0 = await c.walletBal(s1);

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
        c.createdSessionIds.add(cpiBefore!.sessionId!);
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

  final unpub = await c.rpc('batata_publish_hub', {'p_publish': false},
      jwt: c.sellerJwt);
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
    'idempotency_key': 'rtds1702unpubpay',
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

  final unpubOk = profMid?['hub_published'] == false;
  final hubGone = (hubAnonMid?['n'] == 0) && (hubJwtMid?['n'] == 0);
  final unpaidTipOk = !tipCredited;
  final payoutStole = payoutUnpub.payoutOk && (wSellerMid - wSeller0) < -0.5;
  final led = await c.payoutLedger(s1, limit: 4);

  String a1result;
  if (!unpubOk) {
    a1result = 'SKIP';
    c.skip('A1', 'DS7', 'unpublish RPC não pegou', unpub);
  } else if (tipCredited || payoutStole) {
    a1result = 'HOLD';
    c.hold(
      id: tipCredited ? 'P0-A1-TIP' : 'P0-A1-PAYOUT',
      lens: 'DS8',
      severity: 'P0',
      title: tipCredited
          ? 'Tip creditada após unpublish sem settle pago'
          : 'Payout debitou durante Hub unpublished',
      actor: 'B2 tip GET / S1 connect',
      pre: 'loja unpublished a meio do checkout e da gorjeta',
      repro: 'unpublish + tip GET unpaid + create-connect-account',
      expected: 'tip pending; payout recusado ou Δwallet=0',
      obtained: {
        'tip': tipStatus,
        'payout': payoutUnpub.brief,
        'dWallet': wSellerMid - wSeller0,
      },
    );
  } else {
    a1result = 'FAIL';
    c.block('A1', 'DS7', 'unpublish mid-CPI+tip; payout não roubou', {
      'hubGone': hubGone,
      'tip': tipStatus,
      'payout': payoutUnpub.status,
      'dWallet': wSellerMid - wSeller0,
    });
  }
  c.probe(
    id: 'A1',
    surfaces: 'Hub + CPI + tip + wallet/payout',
    action: 'unpublish mid-checkout E mid-tip + payout unpublished',
    http: {
      'cpiBefore': cpiBefore?.brief,
      'unpub': unpub.brief,
      'cpiAfter': cpiAfter?.brief,
      'tipCreate': tipCreate?.brief,
      'tipGet': tipGet?.brief,
      'payout': payoutUnpub.brief,
    },
    oracles: {
      'hub_mid': profMid?['hub_published'],
      'hubAnon_n': hubAnonMid?['n'],
      'hubJwt_n': hubJwtMid?['n'],
      'tipStatus': tipStatus,
      'tipCredited': tipCredited,
      'payoutOk': payoutUnpub.payoutOk,
      'dWallet': wSellerMid - wSeller0,
      'hub_after': afterPub?['hub_published'],
      'ledger_n': led.length,
      'unpaidTipOk': unpaidTipOk,
    },
    result: a1result,
    lens: 'DS7',
    classeNova: true,
    countFinding: a1result == 'HOLD',
  );

  // ----- A2 sold+listed vs Hub vs CPI (residual DM A3) -----
  final skuA2 = await c.createProduct(
    title: '$prefix A2 sold',
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
    hubA2 = await c.hubSku(skuA2, jwt: c.buyerJwt);
    insA2 = await c.insertOrderHit(
      productId: skuA2,
      jwt: c.buyerJwt,
      price: 12.0,
    );
  }
  final hubHidden = (hubA2?.list.length ?? 0) == 0;
  final cpiDenied = insA2 == null || denied(insA2) || !insA2.ok;
  String a2result;
  if (skuA2 == null) {
    a2result = 'SKIP';
    c.skip('A2', 'DS1', 'sku sold fail', 'null');
  } else if (!hubHidden && !cpiDenied) {
    a2result = 'HOLD';
    c.hold(
      id: 'P1-A2-SOLD',
      lens: 'DS1',
      severity: 'P1',
      title: 'SKU sold+listed visível no Hub e checkout abre',
      actor: 'B1 Hub + insertOrder',
      pre: 'is_sold=true list_on_marketplace=true',
      repro: 'hub_products_public + POST orders',
      expected: 'Hub 0 linhas; insert/CPI recusa',
      obtained: {'hub': hubA2?.brief, 'ins': insA2?.brief, 'prod': prodA2},
    );
  } else {
    a2result = 'FAIL';
    c.block('A2', 'DS1', 'sold oculto no Hub e/ou checkout recusa', {
      'hub_n': hubA2?.list.length,
      'ins': insA2?.brief,
      'sold': prodA2?['is_sold'],
    });
  }
  c.probe(
    id: 'A2',
    surfaces: 'Hub + products + orders/CPI',
    action: 'is_sold=true listed vs vitrine vs insert',
    http: {'hub': hubA2?.brief, 'ins': insA2?.brief},
    oracles: {
      'sold': prodA2?['is_sold'],
      'listed': prodA2?['list_on_marketplace'],
      'hub_n': hubA2?.list.length,
      'insert_ok': insA2?.ok,
    },
    result: a2result,
    lens: 'DS1',
    residual: true,
    countFinding: a2result == 'HOLD',
  );

  // ----- A3 leftover após pago parcial stock -----
  final paidA3 = await c.payToPago(lens: 'DS1', initialQty: 2);
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
      jwt: c.buyerJwt,
      price: 12.0,
    );
    if (oidLeft != null) {
      cpiA3 = await c.checkout(
        orderId: oidLeft,
        productId: paidA3.pid,
        jwt: c.buyerJwt,
      );
      if (c.usefulCs(cpiA3)) c.createdSessionIds.add(cpiA3!.sessionId!);
    }
  }
  final leftoverQty = numOf(prodA3?['quantity']) ?? -1;
  final hubShows = (hubA3?.list.length ?? 0) == 1;
  final leftoverBuyable = c.usefulCs(cpiA3);
  final paidOk = '${ordA3?['status']}' == 'pago';
  String a3result;
  if (paidA3 == null || !paidOk) {
    a3result = paidA3 == null ? 'SKIP' : 'HOLD';
    if (paidA3 == null) {
      c.skip('A3', 'DS1', 'setup_paid_order fail', 'null');
    } else {
      c.hold(
        id: 'P1-A3-NOT-PAGO',
        lens: 'DS8',
        severity: 'P1',
        title: 'pago Stripe mas status ≠ pago',
        actor: 'e2e setup_paid_order',
        pre: 'initial_qty=2',
        repro: 'setup_paid_order',
        expected: 'status=pago qty leftover=1',
        obtained: ordA3,
      );
    }
  } else if (leftoverQty == 1 && !hubShows && leftoverBuyable) {
    a3result = 'HOLD';
    c.hold(
      id: 'P2-A3-HUB-LEFTOVER',
      lens: 'DS1',
      severity: 'P2',
      title: 'Leftover qty=1 comprável mas Hub esconde',
      actor: 'B1 Hub + CPI',
      pre: 'pago 1 de 2; leftover=1',
      repro: 'hub_products_public + CPI leftover',
      expected: 'Hub mostra leftover XOR CPI recusa',
      obtained: {
        'qty': leftoverQty,
        'hub_n': hubA3?.list.length,
        'cpi': cpiA3?.brief,
      },
    );
  } else if (leftoverQty > 0 && leftoverBuyable && hubShows) {
    a3result = 'FAIL';
    c.block('A3', 'DS1', 'leftover Hub+CPI coerentes', {
      'qty': leftoverQty,
      'hub_n': hubA3?.list.length,
      'cs': cpiA3?.sessionId,
    });
  } else if (leftoverQty <= 0 && hubShows) {
    a3result = 'HOLD';
    c.hold(
      id: 'P2-A3-HUB-GHOST',
      lens: 'DS1',
      severity: 'P2',
      title: 'Hub lista SKU com qty leftover 0',
      actor: 'anon/B1 Hub',
      pre: 'pago esgotou ou leftover 0',
      repro: 'hub_products_public',
      expected: 'Hub 0 linhas',
      obtained: {'qty': leftoverQty, 'hub': hubA3?.brief},
    );
  } else {
    a3result = 'FAIL';
    c.block('A3', 'DS1', 'leftover observado', {
      'qty': leftoverQty,
      'hub_n': hubA3?.list.length,
      'cpi': cpiA3?.brief,
      'status': ordA3?['status'],
    });
  }
  c.probe(
    id: 'A3',
    surfaces: 'Hub + orders + products + CPI',
    action: 'pago parcial qty 2→1; leftover vs Hub vs CPI',
    http: {'paid': paidA3?.hit.brief, 'hub': hubA3?.brief, 'cpi': cpiA3?.brief},
    oracles: {
      'status': ordA3?['status'],
      'qty': leftoverQty,
      'hub_n': hubA3?.list.length,
      'cs': cpiA3?.sessionId,
      'pi': paidA3?.pi,
    },
    result: a3result,
    lens: 'DS1',
    countFinding: a3result == 'HOLD',
  );

  // ----- A4 favorite + checkout-hold + Hub (NÃO hitch live clássico) -----
  final skuA4 = await c.createProduct(
    title: '$prefix A4 fav-hold',
    qty: 1,
    listed: true,
    live: false,
  );
  HttpHit? favA4;
  HttpHit? hubA4;
  HttpHit? cpiB1;
  HttpHit? cpiB2;
  HttpHit? favAfter;
  String? oidA4;
  Map<String, dynamic>? prodA4;
  if (skuA4 != null) {
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
      if (c.usefulCs(cpiB1)) c.createdSessionIds.add(cpiB1!.sessionId!);
    }
    hubA4 = await c.hubSku(skuA4, jwt: c.buyer2Jwt);
    final oidB2 = await c.insertOrder(
      productId: skuA4,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 12.0,
    );
    if (oidB2 != null) {
      cpiB2 = await c.checkout(
        orderId: oidB2,
        productId: skuA4,
        jwt: c.buyer2Jwt,
        buyer: b2,
      );
    }
    favAfter = await c.favRow(skuA4, b1);
    prodA4 = await c.productRow(skuA4);
  }
  final twoCs = [cpiB1, cpiB2].where((h) => c.usefulCs(h)).length;
  final favKept = (favAfter?.list.length ?? 0) >= 1 || insertOk(favA4 ?? HttpHit(0, '', {}));
  String a4result;
  if (skuA4 == null) {
    a4result = 'SKIP';
    c.skip('A4', 'DS1', 'sku A4 fail', 'null');
  } else if (twoCs >= 2) {
    a4result = 'HOLD';
    c.hold(
      id: 'P1-A4-DOUBLE-CS',
      lens: 'DS5',
      severity: 'P1',
      title: 'Favorite+hold: 2 Sessions no mesmo qty=1',
      actor: 'B1 CPI hold + B2 CPI',
      pre: 'qty=1 listed; B1 favorite + CPI',
      repro: 'B2 create-payment-intent mesmo SKU',
      expected: '≤1 cs_ útil',
      obtained: {'b1': cpiB1?.brief, 'b2': cpiB2?.brief, 'hub_n': hubA4?.list.length},
    );
  } else {
    a4result = 'FAIL';
    c.block('A4', 'DS1', 'favorite+hold: ≤1 cs_; Hub/fav observados', {
      'fav': favA4?.brief,
      'hub_n': hubA4?.list.length,
      'cs_n': twoCs,
      'fav_kept': favKept,
      'qty': prodA4?['quantity'],
    });
  }
  c.probe(
    id: 'A4',
    surfaces: 'favorites + Hub + CPI hold',
    action: 'favorite SKU + checkout hold qty=1 + 2.º buyer CPI',
    http: {
      'fav': favA4?.brief,
      'cpiB1': cpiB1?.brief,
      'cpiB2': cpiB2?.brief,
      'hub': hubA4?.brief,
    },
    oracles: {
      'hub_n': hubA4?.list.length,
      'cs_n': twoCs,
      'fav_n': favAfter?.list.length,
      'qty': prodA4?['quantity'],
    },
    result: a4result,
    lens: 'DS1',
    classeNova: true,
    countFinding: a4result == 'HOLD',
  );
}

Future<void> runB(
  Rtds c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // ----- B1 accept live SKU-A + bag OUTRA linha SKU-B mesmo seller -----
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
  final liveB1 = await c.createLive(title: '$prefix B1 other-line');
  String? liA;
  String? resA;
  HttpHit? acc;
  HttpHit? bagB;
  HttpHit? hubA;
  HttpHit? hubB;
  String? oidB;
  if (liveB1 != null && skuA != null) {
    liA = await c.createLiveItem(
      liveId: liveB1,
      title: '$prefix B1 li-A',
      kind: 'marketplace_product',
      productId: skuA,
    );
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
    c.skip('B1', 'DS2', 'fixture B1 fail', 'null');
  } else if (accepted && !bagOk && denied(bagB ?? HttpHit(0, '', {}))) {
    b1result = 'HOLD';
    c.hold(
      id: 'P2-B1-CROSS-LINE',
      lens: 'DS2',
      severity: 'P2',
      title: 'Accept live SKU-A bloqueou saco da OUTRA linha SKU-B',
      actor: 'S1 accept + B1 bag',
      pre: 'SKU-A hitch accepted; SKU-B stock independente qty=1',
      repro: 'accept live A + bag CPI linha B',
      expected: 'saco B abre cs_ (stock distinto)',
      obtained: {
        'acc': acc?.brief,
        'bag': bagB?.brief,
        'res': resRow,
        'hubA': hubA?.list.length,
        'hubB': hubB?.list.length,
      },
    );
  } else {
    b1result = 'FAIL';
    c.block('B1', 'DS2', 'accept A não cega bag B', {
      'accepted': accepted,
      'bag_cs': bagB?.sessionId,
      'hubA': hubA?.list.length,
      'hubB': hubB?.list.length,
    });
  }
  c.probe(
    id: 'B1',
    surfaces: 'live accept + bag outra linha + Hub',
    action: 'accept hitch SKU-A + bag CPI SKU-B mesmo seller',
    http: {'acc': acc?.brief, 'bag': bagB?.brief},
    oracles: {
      'res': resRow?['status'],
      'bag_cs': bagB?.sessionId,
      'hubA_n': hubA?.list.length,
      'hubB_n': hubB?.list.length,
    },
    result: b1result,
    lens: 'DS2',
    classeNova: true,
    countFinding: b1result == 'HOLD',
  );

  // ----- B2 convert + Hub + chat card -----
  final paidB2 = await c.payToPago(lens: 'DS2', initialQty: 1);
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
    c.skip('B2', 'DS2', 'paid B2 fail', 'null');
  } else if (ghost) {
    b2result = 'HOLD';
    c.hold(
      id: 'P2-B2-CONVERT-HUB',
      lens: 'DS2',
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
    c.block('B2', 'DS2', 'convert/reconcile vs Hub vs chat observados', {
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
      'hub': hubB2?.brief,
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
    lens: 'DS2',
    classeNova: true,
    countFinding: b2result == 'HOLD',
  );

  // ----- B3 end_live ∥ bag CPI ∥ Hub refresh -----
  final skuB3 = await c.createProduct(
    title: '$prefix B3 race-end',
    qty: 1,
    listed: true,
    live: true,
  );
  final liveB3 = await c.createLive(title: '$prefix B3 end-bag');
  String? liB3;
  String? oidB3;
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
  }
  HttpHit? bagRace;
  HttpHit? hubRace;
  HttpHit? liveAfter;
  if (liveB3 != null && oidB3 != null && skuB3 != null) {
    final raced = await Future.wait([
      c.rest(
        'PATCH',
        'lives?id=eq.$liveB3',
        jwt: c.sellerJwt,
        body: {'status': 'ended', 'is_active': false},
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
    liveAfter = raced[0];
    bagRace = raced[1];
    hubRace = raced[2];
    if (c.usefulCs(bagRace)) c.createdSessionIds.add(bagRace.sessionId!);
  }
  final liveEnded = await c.rest(
    'GET',
    'lives?id=eq.$liveB3&select=id,status,is_active',
    service: true,
  );
  final ended = liveEnded.map?['status'] == 'ended' ||
      liveEnded.map?['is_active'] == false;
  String b3result;
  if (skuB3 == null || liveB3 == null) {
    b3result = 'SKIP';
    c.skip('B3', 'DS5', 'B3 fixture fail', 'null');
  } else {
    b3result = 'FAIL';
    c.block('B3', 'DS5', 'end_live∥bag∥Hub: 1 bag cs_ máx observado', {
      'end': liveAfter?.brief,
      'bag': bagRace?.brief,
      'hub_n': hubRace?.list.length,
      'ended': ended,
    });
  }
  c.probe(
    id: 'B3',
    surfaces: 'live end + bag CPI + Hub',
    action: 'Future.wait end_live ∥ bag CPI ∥ hub_products_public',
    http: {
      'end': liveAfter?.brief,
      'bag': bagRace?.brief,
      'hub': hubRace?.brief,
    },
    oracles: {
      'ended': ended,
      'bag_cs': bagRace?.sessionId,
      'hub_n': hubRace?.list.length,
      'li': liB3,
    },
    result: b3result,
    lens: 'DS5',
    countFinding: false,
  );

  // ----- B4 raffle winner + stock marketplace -----
  final skuB4 = await c.createProduct(
    title: '$prefix B4 prize',
    qty: 1,
    listed: true,
    live: true,
  );
  final liveB4 = await c.createLive(title: '$prefix B4 raffle');
  String? liB4;
  HttpHit? rafIns;
  String? rafId;
  HttpHit? award;
  HttpHit? close;
  HttpHit? draw;
  HttpHit? hubB4;
  Map<String, dynamic>? prodB4b;
  Map<String, dynamic>? prodB4a;
  List<Map<String, dynamic>> winners = const [];
  if (liveB4 != null && skuB4 != null) {
    liB4 = await c.createLiveItem(
      liveId: liveB4,
      title: '$prefix B4 prize-li',
      kind: 'marketplace_product',
      productId: skuB4,
    );
    rafIns = await c.rest('POST', 'live_raffles', service: true, body: {
      'live_id': liveB4,
      'seller_id': s1,
      'title': '$prefix raffle prize',
      'status': 'active',
      'winner_count': 1,
      if (liB4 != null) 'live_item_id': liB4,
      'ends_at': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 2))
          .toIso8601String(),
    });
    rafId = rafIns.firstId;
    if (rafId != null) c.createdRaffleIds.add(rafId);
    if (rafId != null) {
      award = await c.rpc(
        'batata_award_live_raffle_tickets',
        {
          'p_raffle_id': rafId,
          'p_user_id': b1,
          'p_action_type': 'redteam_ds',
          'p_tickets_delta': 5,
          'p_source_id': prefix,
          'p_metadata': {'src': prefix},
        },
        service: true,
      );
      close = await c.rest(
        'PATCH',
        'live_raffles?id=eq.$rafId',
        jwt: c.sellerJwt,
        body: {'status': 'closed'},
      );
      if (!close.ok) {
        close = await c.rest(
          'PATCH',
          'live_raffles?id=eq.$rafId',
          service: true,
          body: {'status': 'closed'},
        );
      }
      prodB4b = await c.productRow(skuB4);
      draw = await c.rpc(
        'batata_draw_live_raffle_winners',
        {'p_raffle_id': rafId},
        jwt: c.sellerJwt,
      );
      winners = await c.raffleWinners(rafId);
      prodB4a = await c.productRow(skuB4);
      hubB4 = await c.hubSku(skuB4, jwt: c.buyerJwt);
    }
  }
  final prizeOrders = rafId == null
      ? <dynamic>[]
      : (await c.rest(
          'GET',
          'orders?live_raffle_id=eq.$rafId&select=id,status,buyer_id,product_id,price_total,live_raffle_id',
          service: true,
        ))
          .list;
  final q0 = numOf(prodB4b?['quantity']) ?? 0;
  final q1 = numOf(prodB4a?['quantity']) ?? 0;
  final stockVanish = winners.isNotEmpty && q1 < 0;
  final doubleGone = winners.isNotEmpty && (q0 - q1) > 1;
  String b4result;
  if (skuB4 == null || liveB4 == null || rafId == null) {
    b4result = 'SKIP';
    c.skip('B4', 'DS2', 'raffle fixture fail', rafIns?.brief ?? 'null');
  } else if (stockVanish || doubleGone) {
    b4result = 'HOLD';
    c.hold(
      id: 'P1-B4-RAFFLE-STOCK',
      lens: 'DS2',
      severity: 'P1',
      title: 'Draw rifa restaurou/consumiu stock marketplace incoerente',
      actor: 'S1 draw + Hub',
      pre: 'SKU qty=1 listed hitch + raffle closed',
      repro: 'award tickets + draw winners',
      expected: 'stock −0/−1; Hub alinhado; prize order se winner',
      obtained: {
        'qty': '$q0→$q1',
        'winners': winners,
        'hub_n': hubB4?.list.length,
        'prize_n': prizeOrders.length,
        'draw': draw?.brief,
      },
    );
  } else {
    b4result = 'FAIL';
    c.block('B4', 'DS2', 'rifa winner vs stock vs Hub observados', {
      'qty': '$q0→$q1',
      'winners_n': winners.length,
      'hub_n': hubB4?.list.length,
      'prize_n': prizeOrders.length,
      'draw': draw?.brief,
      'award': award?.brief,
    });
  }
  c.probe(
    id: 'B4',
    surfaces: 'rifa + live_item + Hub + products + prize order',
    action: 'award+draw winner vs stock marketplace',
    http: {
      'raf': rafIns?.brief,
      'award': award?.brief,
      'close': close?.brief,
      'draw': draw?.brief,
    },
    oracles: {
      'qty': '$q0→$q1',
      'winners': winners.length,
      'hub_n': hubB4?.list.length,
      'prize_n': prizeOrders.length,
      'tickets': rafId == null ? 0 : await c.raffleTickets(rafId, b1),
    },
    result: b4result,
    lens: 'DS2',
    classeNova: true,
    countFinding: b4result == 'HOLD',
  );
}

Future<void> runC(
  Rtds c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // ----- C1 oferta aceite + CPI underpay + Hub -----
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
          extra: {'total_eur': 0.01, 'offer_amount': 0.01},
        );
        if (c.usefulCs(cpiC1)) c.createdSessionIds.add(cpiC1!.sessionId!);
        ordC1 = await c.orderRow(oidC1);
      }
    }
    hubC1 = await c.hubSku(skuC1, jwt: c.buyerJwt);
  }
  final sealed = cpiC1?.amountTotal;
  final under = c.usefulCs(cpiC1) && sealed != null && sealed < 800;
  String c1result;
  if (skuC1 == null || offId == null) {
    c1result = 'SKIP';
    c.skip('C1', 'DS6', 'offer fixture fail', off?.brief ?? 'null');
  } else if (under) {
    c1result = 'HOLD';
    c.hold(
      id: 'P0-C1-UNDERPAY',
      lens: 'DS6',
      severity: 'P0',
      title: 'Oferta 8€ aceite: Session below selo (underpay)',
      actor: 'B1 CPI amount=1',
      pre: 'product_offers.amount=8 accepted',
      repro: 'INSERT order product_offer_id; CPI amount=1',
      expected: 'amount_total ≥ 800¢ (selo 8€)',
      obtained: {
        'cpi': cpiC1?.brief,
        'sealed': sealed,
        'offer': offRow,
        'hub_n': hubC1?.list.length,
      },
    );
  } else {
    c1result = 'FAIL';
    c.block('C1', 'DS6', 'oferta aceite: CPI selo; Hub observado', {
      'offer': offRow?['amount'],
      'status': offRow?['status'],
      'sealed': sealed,
      'hub_n': hubC1?.list.length,
      'cpi': cpiC1?.brief,
    });
  }
  c.probe(
    id: 'C1',
    surfaces: 'offer + CPI + Hub + orders',
    action: 'oferta 8€ aceite + CPI underpay amount=1 + Hub',
    http: {'off': off?.brief, 'acc': acc?.brief, 'cpi': cpiC1?.brief},
    oracles: {
      'offer_amt': offRow?['amount'],
      'offer_st': offRow?['status'],
      'sealed_cents': sealed,
      'hub_n': hubC1?.list.length,
      'order_offer': ordC1?['product_offer_id'],
    },
    result: c1result,
    lens: 'DS6',
    classeNova: true,
    countFinding: c1result == 'HOLD',
  );

  // ----- C2 bundle + single overlap Session -----
  final skuX = await c.createProduct(
    title: '$prefix C2 bun-X',
    qty: 1,
    price: 12.0,
    listed: true,
    live: false,
  );
  final skuY = await c.createProduct(
    title: '$prefix C2 bun-Y',
    qty: 2,
    price: 12.0,
    listed: true,
    live: false,
  );
  HttpHit? bun;
  HttpHit? bunAcc;
  HttpHit? bagBun;
  HttpHit? cpiSingle;
  String? bunId;
  Map<String, dynamic>? bunRow;
  if (skuX != null && skuY != null) {
    bun = await c.insertBundle(
      productIds: [skuX, skuY],
      totalEur: 12,
      subtotalEur: 24,
      discountPct: 50,
    );
    bunId = bun.firstId;
    if (bunId != null) {
      bunAcc = await c.acceptBundle(bunId);
      bunRow = await c.bundleRow(bunId);
      final oidBunX = await c.insertOrder(
        productId: skuX,
        jwt: c.buyerJwt,
        price: 6.0,
        bundleId: bunId,
      );
      final oidBunY = await c.insertOrder(
        productId: skuY,
        jwt: c.buyerJwt,
        price: 6.0,
        bundleId: bunId,
      );
      final oidSingle = await c.insertOrder(
        productId: skuX,
        jwt: c.buyerJwt,
        price: 12.0,
      );
      if (oidBunX != null && oidBunY != null && oidSingle != null) {
        final raced = await Future.wait([
          c.checkoutBag(
            lines: [
              {
                'order_id': oidBunX,
                'product_id': skuX,
                'quantity': 1,
                'price': 6.0,
                'bundle_id': bunId,
              },
              {
                'order_id': oidBunY,
                'product_id': skuY,
                'quantity': 1,
                'price': 6.0,
                'bundle_id': bunId,
              },
            ],
            jwt: c.buyerJwt,
            seller: s1,
            amount: 1,
          ),
          c.checkout(
            orderId: oidSingle,
            productId: skuX,
            jwt: c.buyerJwt,
            amount: 1,
          ),
        ]);
        bagBun = raced[0];
        cpiSingle = raced[1];
        if (c.usefulCs(bagBun)) c.createdSessionIds.add(bagBun.sessionId!);
        if (c.usefulCs(cpiSingle)) {
          c.createdSessionIds.add(cpiSingle.sessionId!);
        }
      }
    }
  }
  final overlapCs = [bagBun, cpiSingle].where((h) => c.usefulCs(h)).length;
  final sameSid = (bagBun?.sessionId ?? 'a') == (cpiSingle?.sessionId ?? 'b') &&
      c.usefulCs(bagBun);
  String c2result;
  if (skuX == null || bunId == null) {
    c2result = 'SKIP';
    c.skip('C2', 'DS6', 'bundle fixture fail', bun?.brief ?? 'null');
  } else if (overlapCs >= 2 && !sameSid) {
    c2result = 'HOLD';
    c.hold(
      id: 'P1-C2-OVERLAP-CS',
      lens: 'DS5',
      severity: 'P1',
      title: 'Bundle∥single mesma linha: 2 cs_ distintas úteis',
      actor: 'B1 Future.wait bag bundle + single',
      pre: 'bundle aceite SKU X+Y; single overlap X qty=1',
      repro: 'bag CPI bundle ∥ single CPI X',
      expected: '≤1 cs_ útil ou reuse',
      obtained: {
        'bag': bagBun?.brief,
        'single': cpiSingle?.brief,
        'bundle': bunRow,
      },
    );
  } else {
    c2result = 'FAIL';
    c.block('C2', 'DS5', 'bundle∥single overlap ≤1 cs_ útil', {
      'cs_n': overlapCs,
      'sameSid': sameSid,
      'bag': bagBun?.brief,
      'single': cpiSingle?.brief,
      'bun_st': bunRow?['status'],
      'bunAcc': bunAcc?.brief,
    });
  }
  c.probe(
    id: 'C2',
    surfaces: 'bundle + single CPI + products',
    action: 'Future.wait bag bundle ∥ single overlap mesma linha X',
    http: {
      'bun': bun?.brief,
      'acc': bunAcc?.brief,
      'bag': bagBun?.brief,
      'single': cpiSingle?.brief,
    },
    oracles: {
      'cs_n': overlapCs,
      'sameSid': sameSid,
      'bun_total': bunRow?['total_eur'],
      'bun_st': bunRow?['status'],
    },
    result: c2result,
    lens: 'DS5',
    classeNova: true,
    countFinding: c2result == 'HOLD',
  );

  // ----- C3 chat card vs order amount após pago -----
  final paidC3 = await c.payToPago(lens: 'DS3', initialQty: 2);
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
  final hostilOk = cardHostil != null && cardHostil.ok;
  String c3result;
  if (paidC3 == null) {
    c3result = 'SKIP';
    c.skip('C3', 'DS3', 'paid C3 fail', 'null');
  } else if (hostilOk && '${ordC3?['status']}' == 'pago' && paidCents > 1) {
    c3result = 'FAIL';
    c.block('C3', 'DS3', 'card hostil persistiu; order amount não mudou', {
      'cardHostil': cardHostil?.brief,
      'status': ordC3?['status'],
      'paid_cents': paidCents,
      'cardOk': cardOk?.brief,
      'note': 'card ≠ ledger; se amount_paid não baixou, higiene chat não P0',
    });
  } else {
    c3result = 'FAIL';
    c.block('C3', 'DS3', 'chat vs order amount observados', {
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
    action: 'pago Stripe + card canónico vs card amount hostil',
    http: {'ok': cardOk?.brief, 'hostil': cardHostil?.brief},
    oracles: {
      'status': ordC3?['status'],
      'amount_paid_cents': paidCents,
      'pi': paidC3?.pi,
      'msgs_n': msgs.length,
      'hostil_persisted': hostilOk,
    },
    result: c3result,
    lens: 'DS3',
    countFinding: false,
  );

  // ----- C4 seller PATCH pago sem Stripe -----
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
  num wS0 = await c.walletBal(s1);
  if (skuC4 != null) {
    oidC4 = await c.insertOrder(
      productId: skuC4,
      jwt: c.buyerJwt,
      price: 12.0,
    );
    if (oidC4 != null) {
      patchBuyer = await c.patchOrder(oidC4, {'status': 'pago'}, jwt: c.buyerJwt);
      patchSeller = await c.patchOrder(
        oidC4,
        {'status': 'pago', 'amount_paid_cents': 1200},
        jwt: c.sellerJwt,
      );
      ordC4 = await c.orderRow(oidC4);
    }
  }
  final wS1 = await c.walletBal(s1);
  final faked = '${ordC4?['status']}' == 'pago';
  String c4result;
  if (oidC4 == null) {
    c4result = 'SKIP';
    c.skip('C4', 'DS8', 'order C4 fail', 'null');
  } else if (faked) {
    c4result = 'HOLD';
    c.hold(
      id: 'P0-C4-FAKE-PAGO',
      lens: 'DS8',
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
        'dWallet': wS1 - wS0,
      },
    );
  } else {
    c4result = 'FAIL';
    c.block('C4', 'DS8', 'PATCH pago sem Stripe recusado', {
      'buyer': patchBuyer?.brief,
      'seller': patchSeller?.brief,
      'status': ordC4?['status'],
      'paid': ordC4?['amount_paid_cents'],
      'dWallet': wS1 - wS0,
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
      'dWallet': wS1 - wS0,
    },
    result: c4result,
    lens: 'DS8',
    countFinding: c4result == 'HOLD',
  );
}

Future<void> runD(
  Rtds c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // ----- D1 refund ∥ nova compra leftover -----
  final paidD1 = await c.payToPago(lens: 'DS5', initialQty: 2);
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
    c.skip('D1', 'DS5', 'paid D1 fail', 'null');
  } else if (q1 < 0 || q1 > q0 + 2) {
    d1result = 'HOLD';
    c.hold(
      id: 'P1-D1-STOCK-RACE',
      lens: 'DS5',
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
    c.block('D1', 'DS5', 'refund∥leftover CPI stock observado', {
      'qty': '$q0→$q1',
      'rf': rf?.brief,
      'cpi': cpiNew?.brief,
      'old': oldOrd?['status'],
      'new': newOrd?['status'],
    });
  }
  c.probe(
    id: 'D1',
    surfaces: 'refund + CPI leftover + products',
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
    lens: 'DS5',
    residual: true,
    countFinding: d1result == 'HOLD',
  );

  // ----- D2 release ∥ disputa -----
  final paidD2 = await c.payToPago(lens: 'DS4', initialQty: 2);
  HttpHit? rel;
  HttpHit? disp;
  Map<String, dynamic>? ordD2;
  num w0 = await c.walletBal(s1);
  if (paidD2 != null) {
    final raced = await Future.wait([
      c.tryRelease(paidD2.oid, jwt: c.buyerJwt),
      c.insertDispute(orderId: paidD2.oid),
    ]);
    rel = raced[0];
    disp = raced[1];
    ordD2 = await c.orderRow(paidD2.oid);
  }
  final w1 = await c.walletBal(s1);
  final released = rel?.json == true || '${rel?.json}' == 'true';
  final dWallet = w1 - w0;
  String d2result;
  if (paidD2 == null) {
    d2result = 'SKIP';
    c.skip('D2', 'DS4', 'paid D2 fail', 'null');
  } else if (released && dWallet > 0 && disp != null && disp.ok) {
    d2result = 'HOLD';
    c.hold(
      id: 'P1-D2-RELEASE-DISPUTE',
      lens: 'DS4',
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
        'order': ordD2,
      },
    );
  } else {
    d2result = 'FAIL';
    c.block('D2', 'DS4', 'release∥disputa: sem crédito líquido anómalo', {
      'rel': rel?.brief,
      'disp': disp?.brief,
      'dWallet': dWallet,
      'status': ordD2?['status'],
    });
  }
  c.probe(
    id: 'D2',
    surfaces: 'wallet release + disputa + orders',
    action: 'Future.wait release ∥ POST disputa no pago',
    http: {'rel': rel?.brief, 'disp': disp?.brief},
    oracles: {
      'released': released,
      'dWallet': dWallet,
      'status': ordD2?['status'],
      'disp_ok': disp?.ok,
      'pi': paidD2?.pi,
    },
    result: d2result,
    lens: 'DS4',
    classeNova: true,
    countFinding: d2result == 'HOLD',
  );

  // ----- D3 2 buyers Hub visível + CPI -----
  final skuD3 = await c.createProduct(
    title: '$prefix D3 two-buyers',
    qty: 1,
    listed: true,
    live: false,
  );
  HttpHit? hubD3;
  HttpHit? cpi1;
  HttpHit? cpi2;
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
    if (o1 != null && o2 != null) {
      final raced = await Future.wait([
        c.checkout(orderId: o1, productId: skuD3, jwt: c.buyerJwt),
        c.checkout(
          orderId: o2,
          productId: skuD3,
          jwt: c.buyer2Jwt,
          buyer: b2,
        ),
      ]);
      cpi1 = raced[0];
      cpi2 = raced[1];
      if (c.usefulCs(cpi1)) c.createdSessionIds.add(cpi1.sessionId!);
      if (c.usefulCs(cpi2)) c.createdSessionIds.add(cpi2.sessionId!);
    }
  }
  final two = [cpi1, cpi2].where((h) => c.usefulCs(h)).length;
  String d3result;
  if (skuD3 == null) {
    d3result = 'SKIP';
    c.skip('D3', 'DS5', 'sku D3 fail', 'null');
  } else if (two >= 2) {
    d3result = 'HOLD';
    c.hold(
      id: 'P1-D3-TWO-CS',
      lens: 'DS5',
      severity: 'P1',
      title: '2 buyers Hub-visível: 2 cs_ no qty=1',
      actor: 'B1∥B2 CPI',
      pre: 'Hub lista SKU qty=1',
      repro: 'Future.wait CPI B1 + CPI B2',
      expected: '≤1 cs_ útil',
      obtained: {
        'hub_n': hubD3?.list.length,
        'b1': cpi1?.brief,
        'b2': cpi2?.brief,
      },
    );
  } else {
    d3result = 'FAIL';
    c.block('D3', 'DS5', '2 buyers Hub visível: ≤1 cs_', {
      'hub_n': hubD3?.list.length,
      'cs_n': two,
      'b1': cpi1?.brief,
      'b2': cpi2?.brief,
    });
  }
  c.probe(
    id: 'D3',
    surfaces: 'Hub + CPI B1 + CPI B2',
    action: '2 buyers Future.wait CPI em SKU Hub-visível qty=1',
    http: {'hub': hubD3?.brief, 'b1': cpi1?.brief, 'b2': cpi2?.brief},
    oracles: {
      'hub_n': hubD3?.list.length,
      'cs_n': two,
      'sid1': cpi1?.sessionId,
      'sid2': cpi2?.sessionId,
    },
    result: d3result,
    lens: 'DS5',
    countFinding: d3result == 'HOLD',
  );

  // ----- D4 pago 4242 → Hub + order + wallet + chat -----
  final wB0 = await c.walletBal(c.buyerId);
  final wS0 = await c.walletBal(c.sellerId);
  final paidD4 = await c.payToPago(lens: 'DS8', initialQty: 2);
  Map<String, dynamic>? ordD4;
  Map<String, dynamic>? prodD4;
  HttpHit? hubD4;
  List<Map<String, dynamic>> chats = const [];
  List<Map<String, dynamic>> msgsD4 = const [];
  num wB1 = wB0;
  num wS1 = wS0;
  if (paidD4 != null) {
    ordD4 = await c.orderRow(paidD4.oid);
    prodD4 = await c.productRow(paidD4.pid);
    hubD4 = await c.hubSku(paidD4.pid, jwt: c.buyerJwt);
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
    c.skip('D4', 'DS8', 'setup_paid_order fail', 'null');
  } else if (!statusPago) {
    d4result = 'HOLD';
    c.hold(
      id: 'P1-D4-NOT-PAGO',
      lens: 'DS8',
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
      lens: 'DS8',
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
    c.block('D4', 'DS8', 'pago 4242: 4 sítios observados', {
      'status': ordD4?['status'],
      'qty': prodD4?['quantity'],
      'hub_n': hubD4?.list.length,
      'dSeller': wS1 - wS0,
      'dBuyer': wB1 - wB0,
      'chats_n': chats.length,
      'msgs_n': msgsD4.length,
      'pi': paidD4.pi,
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
      'msgs_n': msgsD4.length,
    },
    result: d4result,
    lens: 'DS8',
    countFinding: d4result == 'HOLD',
  );
}
