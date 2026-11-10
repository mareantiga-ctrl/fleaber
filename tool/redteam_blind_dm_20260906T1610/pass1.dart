/// RED TEAM CEGO DM pass1 — composição cross-surface ≥12.
/// Staging only. NÃO corrigir. NÃO produção. NÃO Fase 4.
import 'dart:convert';
import 'dart:io';
import '_rtdm.dart';

bool insertOk(HttpHit h) =>
    h.ok ||
    h.status == 409 ||
    h.body.contains('23505') ||
    h.body.toLowerCase().contains('duplicate');

Future<void> main() async {
  final c = Rtdm.fromEnv(loadEnv());
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
    'handle': 'rtdm1610s2',
  }, prefer: 'return=minimal');

  c.note('fix.s1', 'S1 published', await c.profile(s1), lens: 'DM1');
  c.note('fix.s2', 'S2 unpublished', await c.profile(s2), lens: 'DM1');

  try {
    await runA(c, s1: s1, s2: s2, b1: b1, b2: b2);
    await runB(c, s1: s1, b1: b1, b2: b2);
    await runC(c, s1: s1, b1: b1);
    await runD(c, s1: s1, b1: b1, b2: b2);
  } finally {
    await c.endAllCreatedLives();
    await c.restoreSeller1Published();
    final after = await c.profile(s1);
    c.note('restore.s1', 'S1 hub_published after', after?['hub_published'],
        lens: 'DM1');
  }

  await dumpJson('${outDir()}/pass1.json', {
    'auditor': 'REDTEAM_BLIND_DM_CROSS_SURFACE_POS_DBDG_v1',
    'prefix': prefix,
    'staging': projectMust,
    'probes': c.probes,
    'findings': c.findings,
    'blocked': c.blocked,
    'skipped': c.skipped,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
    'actors': {
      'b1': b1,
      's1': s1,
      'b2': b2,
      's2': s2,
    },
    'created': {
      'products': c.createdProductIds,
      'orders': c.createdOrderIds,
      'lives': c.createdLiveIds,
      'items': c.createdLiveItemIds,
      'res': c.createdResIds,
      'tips': c.createdTipIds,
    },
  });
  stdout.writeln('WROTE ${outDir()}/pass1.json probes=${c.probes.length} '
      'findings=${c.findings.length}');
}

Future<void> runA(
  Rtdm c, {
  required String s1,
  required String s2,
  required String b1,
  required String b2,
}) async {
  // ----- A1 unpublish mid-checkout / mid-tip -----
  final skuA1 = await c.createProduct(
    title: '$prefix A1 mkt',
    qty: 2,
    listed: true,
    live: false,
  );
  final liveA1 = await c.createLive(title: '$prefix A1 air');
  String? tipId;
  String? tipSid;
  HttpHit? cpiBefore;
  HttpHit? cpiAfter;
  HttpHit? tipCreate;
  HttpHit? tipGet;
  HttpHit? followUnpub;
  Map<String, dynamic>? hubAnonMid;
  Map<String, dynamic>? hubJwtMid;
  Map<String, dynamic>? profMid;
  String? oidA1;

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
    }
  }
  if (liveA1 != null) {
    tipCreate = await c.edge('create-live-tip-checkout', {
      'live_id': liveA1,
      'seller_id': s1,
      'amount_eur': 2,
    }, jwt: c.buyer2Jwt);
    tipId = tipCreate.map?['tipId']?.toString() ??
        tipCreate.map?['tip_id']?.toString();
    tipSid = tipCreate.map?['checkoutSessionId']?.toString() ??
        tipCreate.map?['sessionId']?.toString() ??
        tipCreate.map?['checkout_session_id']?.toString();
    if (tipId != null) c.createdTipIds.add(tipId);
  }

  final unpub = await c.rpc('batata_publish_hub', {'p_publish': false},
      jwt: c.sellerJwt);
  profMid = await c.profile(s1);
  if (skuA1 != null) {
    final ha = await c.hubSku(skuA1, anon: true);
    final hj = await c.hubSku(skuA1, jwt: c.buyerJwt);
    hubAnonMid = {'status': ha.status, 'n': ha.list.length, 'body': clip(ha.body, 120)};
    hubJwtMid = {'status': hj.status, 'n': hj.list.length, 'body': clip(hj.body, 120)};
  }
  if (oidA1 != null && skuA1 != null) {
    cpiAfter = await c.checkout(
      orderId: oidA1,
      productId: skuA1,
      jwt: c.buyerJwt,
    );
  }
  if (tipSid != null && tipSid.isNotEmpty) {
    tipGet = await c.edge(
      'create-live-tip-checkout',
      null,
      method: 'GET',
      jwt: c.buyer2Jwt,
      qs: 'checkout_return=success&session_id=$tipSid',
    );
  }
  followUnpub = await c.rest('POST', 'follows', jwt: c.buyerJwt, body: {
    'follower_id': b1,
    'following_id': s1,
  });
  if (insertOk(followUnpub) && followUnpub.firstId != null) {
    c.createdFollowIds.add(followUnpub.firstId!);
  }

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

  final restPub = await c.rpc('batata_publish_hub', {'p_publish': true},
      jwt: c.sellerJwt);
  var afterPub = await c.profile(s1);
  if (afterPub?['hub_published'] != true) {
    await c.restoreSeller1Published();
    afterPub = await c.profile(s1);
  }

  final hubGone = (hubAnonMid?['n'] == 0) && (hubJwtMid?['n'] == 0);
  final unpubOk = profMid?['hub_published'] == false;
  final followDenied = denied(followUnpub) && !insertOk(followUnpub);
  final unpaidTipOk = !tipCredited;
  final cpiStill = cpiAfter != null &&
      cpiAfter.ok &&
      (cpiAfter.sessionId ?? '').startsWith('cs_');

  String a1result;
  if (!unpubOk) {
    a1result = 'SKIP';
    c.skip('A1', 'DM6', 'unpublish RPC não pegou', unpub);
  } else if (tipCredited) {
    a1result = 'HOLD';
    c.hold(
      id: 'P0-1',
      lens: 'DM3',
      severity: 'P0',
      title: 'GET tip após unpublish creditou gorjeta não paga',
      actor: 'B2',
      pre: 'Session tip + hub_published=false',
      repro: 'GET create-live-tip-checkout?checkout_return=success',
      expected: 'pending; sem crédito',
      obtained: {'tipStatus': tipStatus, 'get': tipGet?.brief},
    );
  } else if (!hubGone) {
    a1result = 'HOLD';
    c.hold(
      id: 'P1-A1-HUB',
      lens: 'DM1',
      severity: 'P1',
      title: 'Unpublish: Hub ainda mostra SKU enquanto perfil está unpublished',
      actor: 'anon+B1',
      pre: 'RPC batata_publish_hub(false)',
      repro: 'GET hub_products_public id=SKU',
      expected: '0 linhas anon e JWT',
      obtained: {'anon': hubAnonMid, 'jwt': hubJwtMid, 'hub': profMid},
    );
  } else if (!followDenied) {
    a1result = 'HOLD';
    c.hold(
      id: 'P1-A1-FOLLOW',
      lens: 'DM6',
      severity: 'P1',
      title: 'Follow aceite com loja unpublished a meio do checkout',
      actor: 'B1',
      pre: 'hub_published=false mid-CPI',
      repro: 'POST follows following=S1',
      expected: '403 42501',
      obtained: followUnpub.brief,
    );
  } else {
    a1result = 'FAIL';
    c.block('A1', 'DM6', 'unpublish: Hub vazio + follow deny + tip unpaid', {
      'hubGone': hubGone,
      'followDenied': followDenied,
      'cpiStill': cpiStill,
      'unpaidTip': unpaidTipOk,
    });
  }

  c.probe(
    id: 'A1',
    surfaces: 'Hub + checkout CPI + tip + follows',
    action: 'unpublish mid-CPI + mid-tip + follow',
    http: {
      'cpiBefore': cpiBefore?.brief,
      'unpub': unpub.brief,
      'cpiAfter': cpiAfter?.brief,
      'tipCreate': tipCreate?.brief,
      'tipGet': tipGet?.brief,
      'follow': followUnpub.brief,
      'restore': restPub.brief,
    },
    oracles: {
      'hub_mid': profMid?['hub_published'],
      'hubAnon_n': hubAnonMid?['n'],
      'hubJwt_n': hubJwtMid?['n'],
      'tipStatus': tipStatus,
      'tipCredited': tipCredited,
      'hub_after': afterPub?['hub_published'],
      'cpi_cs_after_unpub': cpiStill,
    },
    result: a1result,
    lens: 'DM6',
    countFinding: a1result == 'HOLD',
  );

  // ----- A2 follow+favorite vs vitrine -----
  await c.restoreSeller1Published();
  final skuA2 = await c.createProduct(
    title: '$prefix A2 vitrine',
    qty: 3,
    listed: true,
  );
  HttpHit? hubBefore;
  HttpHit? favPub;
  HttpHit? folPub;
  HttpHit? hubAfterUnpub;
  HttpHit? favUnpub;
  if (skuA2 != null) {
    hubBefore = await c.hubSku(skuA2, jwt: c.buyerJwt);
    favPub = await c.rest('POST', 'favorites', jwt: c.buyerJwt, body: {
      'user_id': b1,
      'product_id': skuA2,
    });
    if (insertOk(favPub) && favPub.firstId != null) {
      c.createdFavIds.add(favPub.firstId!);
    }
    folPub = await c.rest('POST', 'follows', jwt: c.buyerJwt, body: {
      'follower_id': b1,
      'following_id': s1,
    });
    if (insertOk(folPub) && folPub.firstId != null) {
      c.createdFollowIds.add(folPub.firstId!);
    }
    await c.rpc('batata_publish_hub', {'p_publish': false}, jwt: c.sellerJwt);
    hubAfterUnpub = await c.hubSku(skuA2, anon: true);
    favUnpub = await c.rest('POST', 'favorites', jwt: c.buyer2Jwt, body: {
      'user_id': b2,
      'product_id': skuA2,
    });
    await c.restoreSeller1Published();
  }

  final vitrinePub = hubBefore != null && hubBefore.ok && hubBefore.list.isNotEmpty;
  final vitrineGone =
      hubAfterUnpub != null && hubAfterUnpub.list.isEmpty;
  final favHappy = favPub != null && insertOk(favPub);
  final favDeniedUnpub = favUnpub != null && denied(favUnpub);

  String a2result;
  if (skuA2 == null) {
    a2result = 'SKIP';
    c.skip('A2', 'DM1', 'SKU A2 fail', 'null');
  } else if (vitrinePub && favHappy && vitrineGone && favDeniedUnpub) {
    a2result = 'FAIL';
    c.block('A2', 'DM1', 'vitrine+fav published OK; unpublished Hub+fav deny', {
      'hubBefore_n': hubBefore?.list.length,
      'favPub': favPub?.status,
      'hubAfter_n': hubAfterUnpub?.list.length,
      'favUnpub': favUnpub?.status,
    });
  } else if (vitrinePub && !vitrineGone) {
    a2result = 'HOLD';
    c.hold(
      id: 'P1-A2-VITRINE',
      lens: 'DM1',
      severity: 'P1',
      title: 'Vitrine Hub ainda lista SKU após unpublish',
      actor: 'anon',
      pre: 'SKU listado; RPC unpublish',
      repro: 'GET hub_products_public',
      expected: '0 linhas',
      obtained: hubAfterUnpub?.brief,
    );
  } else if (vitrinePub && !favDeniedUnpub) {
    a2result = 'HOLD';
    c.hold(
      id: 'P1-A2-FAV',
      lens: 'DM6',
      severity: 'P1',
      title: 'Favorite aceite em SKU de loja unpublished',
      actor: 'B2',
      pre: 'hub_published=false',
      repro: 'POST favorites',
      expected: '403',
      obtained: favUnpub?.brief,
    );
  } else {
    a2result = 'FAIL';
    c.block('A2', 'DM1', 'follow/favorite vs vitrine (estado misto HOLD-safe)', {
      'vitrinePub': vitrinePub,
      'vitrineGone': vitrineGone,
      'favHappy': favHappy,
      'favDeniedUnpub': favDeniedUnpub,
      'folPub': folPub?.brief,
    });
  }
  c.probe(
    id: 'A2',
    surfaces: 'Hub vitrine + follows + favorites + profiles',
    action: 'follow+favorite published vs hub_products_public após unpublish',
    http: {
      'hubBefore': hubBefore?.brief,
      'favPub': favPub?.brief,
      'folPub': folPub?.brief,
      'hubAfter': hubAfterUnpub?.brief,
      'favUnpub': favUnpub?.brief,
    },
    oracles: {
      'vitrinePub': vitrinePub,
      'vitrineGone': vitrineGone,
      'favHappy': favHappy,
      'favDeniedUnpub': favDeniedUnpub,
    },
    result: a2result,
    lens: 'DM1',
    residual: a2result == 'FAIL' && favHappy,
    countFinding: a2result == 'HOLD',
  );

  // ----- A3 produto sold no Hub vs CPI -----
  await c.restoreSeller1Published();
  final skuSold = await c.createProduct(
    title: '$prefix A3 sold',
    qty: 1,
    listed: true,
    sold: true,
  );
  HttpHit? hubSold;
  HttpHit? hubSoldAnon;
  String? oidSold;
  HttpHit? cpiSold;
  Map<String, dynamic>? prodSold;
  if (skuSold != null) {
    prodSold = await c.productRow(skuSold);
    hubSold = await c.hubSku(skuSold, jwt: c.buyerJwt);
    hubSoldAnon = await c.hubSku(skuSold, anon: true);
    oidSold = await c.insertOrder(
      productId: skuSold,
      jwt: c.buyerJwt,
      price: 12.0,
    );
    if (oidSold != null) {
      cpiSold = await c.checkout(
        orderId: oidSold,
        productId: skuSold,
        jwt: c.buyerJwt,
      );
    }
  }
  final hubHidesSold =
      (hubSold?.list.isEmpty ?? false) && (hubSoldAnon?.list.isEmpty ?? false);
  final cpiBlocked = cpiSold == null || denied(cpiSold) || !cpiSold.ok;
  final csSold = (cpiSold?.sessionId ?? '').startsWith('cs_');

  String a3result;
  if (skuSold == null) {
    a3result = 'SKIP';
    c.skip('A3', 'DM1', 'SKU sold fail', 'null');
  } else if (hubHidesSold && cpiBlocked && !csSold) {
    a3result = 'FAIL';
    c.block('A3', 'DM1', 'Hub esconde sold + CPI recusa Session', {
      'hub_n': hubSold?.list.length,
      'cpi': cpiSold?.brief,
    });
  } else if (!hubHidesSold) {
    a3result = 'HOLD';
    c.hold(
      id: 'P1-A3-HUB-SOLD',
      lens: 'DM1',
      severity: 'P1',
      title: 'Hub lista produto is_sold=true',
      actor: 'anon+B1',
      pre: 'is_sold=true list_on_marketplace=true',
      repro: 'GET hub_products_public',
      expected: '0 linhas',
      obtained: {'jwt': hubSold?.brief, 'anon': hubSoldAnon?.brief, 'prod': prodSold},
    );
  } else if (csSold) {
    a3result = 'HOLD';
    c.hold(
      id: 'P1-A3-CPI-SOLD',
      lens: 'DM3',
      severity: 'P1',
      title: 'CPI abre Session Stripe para produto already sold',
      actor: 'B1',
      pre: 'is_sold=true',
      repro: 'create-payment-intent',
      expected: '400 sem cs_',
      obtained: cpiSold?.brief,
    );
  } else {
    a3result = 'FAIL';
    c.block('A3', 'DM1', 'sold vs CPI (Hub hide ou CPI deny)', {
      'hubHidesSold': hubHidesSold,
      'cpiBlocked': cpiBlocked,
    });
  }
  c.probe(
    id: 'A3',
    surfaces: 'Hub + products + CPI',
    action: 'is_sold=true → vitrine vs checkout',
    http: {
      'hubJwt': hubSold?.brief,
      'hubAnon': hubSoldAnon?.brief,
      'cpi': cpiSold?.brief,
      'order': oidSold,
    },
    oracles: {
      'prod': prodSold,
      'hubHidesSold': hubHidesSold,
      'cpiBlocked': cpiBlocked,
      'cs_': csSold,
    },
    result: a3result,
    lens: 'DM1',
    countFinding: a3result == 'HOLD',
  );
}

Future<void> runB(
  Rtdm c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // ----- B1 hitch live + bag marketplace mesmo SKU qty=1 -----
  final skuB1 = await c.createProduct(
    title: '$prefix B1 hitch-bag',
    qty: 1,
    listed: true,
    live: true,
  );
  final liveB1 = await c.createLive(title: '$prefix B1 hitch');
  String? liB1;
  String? oidBag;
  HttpHit? bagHit;
  HttpHit? accHit;
  Map<String, dynamic>? resB;
  Map<String, dynamic>? prodAfterB1;
  if (skuB1 != null && liveB1 != null) {
    liB1 = await c.createLiveItem(
      liveId: liveB1,
      title: '$prefix B1 li',
      kind: 'marketplace_product',
      productId: skuB1,
    );
    oidBag = await c.insertOrder(
      productId: skuB1,
      jwt: c.buyerJwt,
      price: 12.0,
      qty: 1,
    );
    String? rid;
    if (liB1 != null) {
      rid = await c.insertReservation(
        liveId: liveB1,
        liveItemId: liB1,
        jwt: c.buyer2Jwt,
        buyer: b2,
      );
    }
    if (oidBag != null && rid != null) {
      final bagF = c.checkoutBag(
        lines: [
          {
            'order_id': oidBag,
            'product_id': skuB1,
            'quantity': 1,
          }
        ],
        jwt: c.buyerJwt,
        seller: s1,
      );
      final accF = c.acceptRes(rid);
      final raced = await Future.wait([bagF, accF]);
      bagHit = raced[0];
      accHit = raced[1];
      resB = await c.resRow(rid);
    }
    prodAfterB1 = await c.productRow(skuB1);
  }

  final bagCs = (bagHit?.sessionId ?? '').startsWith('cs_') && (bagHit?.ok ?? false);
  final liveAcc = resB?['status'] == 'accepted';
  final bothClaim = bagCs && liveAcc;

  String b1result;
  if (skuB1 == null || liveB1 == null || liB1 == null) {
    b1result = 'SKIP';
    c.skip('B1', 'DM2', 'fixture hitch/bag fail', {
      'sku': skuB1,
      'live': liveB1,
      'li': liB1,
    });
  } else if (bothClaim) {
    b1result = 'HOLD';
    c.hold(
      id: 'P1-B1-HITCH-BAG',
      lens: 'DM2',
      severity: 'P1',
      title: 'Hitch live accept + bag CPI ambos reclamam a mesma unidade',
      actor: 'B1 bag ∥ B2 live',
      pre: 'qty=1 marketplace+live hitch',
      repro: 'Future.wait bag CPI ∥ PATCH accepted',
      expected: '≤1 claim (bag XOR live)',
      obtained: {
        'bag': bagHit?.brief,
        'acc': accHit?.brief,
        'res': resB,
        'prod': prodAfterB1,
      },
    );
  } else {
    b1result = 'FAIL';
    c.block('B1', 'DM2', 'hitch+bag: um só claim ou ambos recusados', {
      'bagCs': bagCs,
      'liveAcc': liveAcc,
      'bag': bagHit?.brief,
      'acc': accHit?.brief,
      'res': resB,
      'prod': prodAfterB1,
    });
  }
  c.probe(
    id: 'B1',
    surfaces: 'live hitch + bag marketplace + products',
    action: 'Future.wait bag CPI ∥ live accept mesmo SKU qty=1',
    http: {'bag': bagHit?.brief, 'accept': accHit?.brief},
    oracles: {
      'bagCs': bagCs,
      'liveAcc': liveAcc,
      'prod': prodAfterB1,
      'res': resB,
    },
    result: b1result,
    lens: 'DM2',
    countFinding: b1result == 'HOLD',
  );

  // ----- B2 qty 0 live vs list_on_marketplace -----
  final skuB2 = await c.createProduct(
    title: '$prefix B2 qty0',
    qty: 0,
    listed: true,
    sold: false,
    live: true,
  );
  final liveB2 = await c.createLive(title: '$prefix B2 qty0');
  String? liB2;
  HttpHit? hubB2;
  HttpHit? hubB2anon;
  String? oidB2;
  HttpHit? cpiB2;
  Map<String, dynamic>? liRow;
  Map<String, dynamic>? prodB2;
  if (skuB2 != null && liveB2 != null) {
    liB2 = await c.createLiveItem(
      liveId: liveB2,
      title: '$prefix B2 li',
      kind: 'live_only',
      checkoutProductId: skuB2,
      quantity: 0,
      status: 'sold',
    );
    prodB2 = await c.productRow(skuB2);
    if (liB2 != null) liRow = await c.liveItemRow(liB2);
    hubB2 = await c.hubSku(skuB2, jwt: c.buyerJwt);
    hubB2anon = await c.hubSku(skuB2, anon: true);
    oidB2 = await c.insertOrder(
      productId: skuB2,
      jwt: c.buyerJwt,
      price: 12.0,
    );
    if (oidB2 != null) {
      cpiB2 = await c.checkout(
        orderId: oidB2,
        productId: skuB2,
        jwt: c.buyerJwt,
      );
    }
  }
  final hubShowsQty0 = (hubB2?.list.isNotEmpty ?? false) ||
      (hubB2anon?.list.isNotEmpty ?? false);
  final cpiQty0Cs = (cpiB2?.sessionId ?? '').startsWith('cs_') && (cpiB2?.ok ?? false);
  final liveZero = (numOf(liRow?['quantity']) ?? 0) <= 0 ||
      '${liRow?['status']}' == 'sold';

  String b2result;
  if (skuB2 == null) {
    b2result = 'SKIP';
    c.skip('B2', 'DM2', 'SKU qty0 fail', 'null');
  } else if (hubShowsQty0 || cpiQty0Cs) {
    b2result = 'HOLD';
    c.hold(
      id: 'P1-B2-QTY0-HUB',
      lens: 'DM2',
      severity: 'P1',
      title: 'qty=0 / live sold: Hub e/ou CPI ainda vendem o SKU',
      actor: 'B1 + anon Hub',
      pre: 'products.quantity=0 is_sold=false listed; live_item sold/qty0',
      repro: 'GET hub_products_public + CPI',
      expected: 'Hub 0 linhas e CPI 400',
      obtained: {
        'hubJwt_n': hubB2?.list.length,
        'hubAnon_n': hubB2anon?.list.length,
        'cpi': cpiB2?.brief,
        'prod': prodB2,
        'live_item': liRow,
        'liveZero': liveZero,
      },
    );
  } else {
    b2result = 'FAIL';
    c.block('B2', 'DM2', 'qty0: Hub esconde + CPI deny', {
      'hub_n': hubB2?.list.length,
      'cpi': cpiB2?.brief,
      'li': liRow,
    });
  }
  c.probe(
    id: 'B2',
    surfaces: 'live_item + products + Hub + CPI',
    action: 'qty=0 live sold vs list_on_marketplace',
    http: {
      'hubJwt': hubB2?.brief,
      'hubAnon': hubB2anon?.brief,
      'cpi': cpiB2?.brief,
    },
    oracles: {
      'prod': prodB2,
      'live_item': liRow,
      'hubShowsQty0': hubShowsQty0,
      'cpiQty0Cs': cpiQty0Cs,
      'liveZero': liveZero,
    },
    result: b2result,
    lens: 'DM2',
    countFinding: b2result == 'HOLD',
  );

  // ----- B3 refund restaura order + product + live_item -----
  final paidB3 = await c.payToPago(lens: 'DM7', initialQty: 2);
  String? liB3;
  String? liveB3id;
  Map<String, dynamic>? prodBeforeRf;
  Map<String, dynamic>? liBeforeRf;
  HttpHit? rfB3;
  Map<String, dynamic>? orderAfterRf;
  Map<String, dynamic>? prodAfterRf;
  Map<String, dynamic>? liAfterRf;
  if (paidB3 != null) {
    liveB3id = await c.createLive(title: '$prefix B3 refund hitch');
    if (liveB3id != null) {
      liB3 = await c.createLiveItem(
        liveId: liveB3id,
        title: '$prefix B3 li',
        kind: 'marketplace_product',
        productId: paidB3.pid,
      );
    }
    prodBeforeRf = await c.productRow(paidB3.pid);
    if (liB3 != null) liBeforeRf = await c.liveItemRow(liB3);
    rfB3 = await c.refund(paidB3.oid);
    orderAfterRf = await c.orderRow(paidB3.oid);
    prodAfterRf = await c.productRow(paidB3.pid);
    if (liB3 != null) liAfterRf = await c.liveItemRow(liB3);
  }

  final qtyBefore = numOf(prodBeforeRf?['quantity']) ?? 0;
  final qtyAfter = numOf(prodAfterRf?['quantity']) ?? 0;
  final stockDelta = qtyAfter - qtyBefore;
  final orderRestored = orderAfterRf != null &&
      ('${orderAfterRf['status']}'.contains('devolv') ||
          '${orderAfterRf['status']}' == 'cancelado' ||
          '${orderAfterRf['status']}' == 'reembolsado');
  final doubleStock = stockDelta > 1;

  String b3result;
  if (paidB3 == null) {
    b3result = 'SKIP';
    c.skip('B3', 'DM7', 'setup_paid_order fail', 'null');
  } else if (doubleStock) {
    b3result = 'HOLD';
    c.hold(
      id: 'P1-B3-DOUBLE-STOCK',
      lens: 'DM7',
      severity: 'P1',
      title: 'Refund restaurou stock >1 unidade',
      actor: 'seller JWT refund-order',
      pre: 'pago Stripe TEST hitch marketplace',
      repro: 'POST refund-order',
      expected: 'stock +0 ou +1; order devolvida',
      obtained: {
        'qty': '$qtyBefore→$qtyAfter',
        'order': orderAfterRf,
        'li_before': liBeforeRf,
        'li_after': liAfterRf,
        'rf': rfB3?.brief,
      },
    );
  } else {
    b3result = 'FAIL';
    c.block('B3', 'DM7', 'refund restore ≤1 + order terminal', {
      'qty': '$qtyBefore→$qtyAfter',
      'order': orderAfterRf?['status'],
      'rf': rfB3?.brief,
      'li_before': liBeforeRf?['status'],
      'li_after': liAfterRf?['status'],
      'orderRestored': orderRestored,
    });
  }
  c.probe(
    id: 'B3',
    surfaces: 'order + product + live_item hitch',
    action: 'refund-order após pago Stripe + hitch',
    http: rfB3?.brief ?? 'n/a',
    oracles: {
      'qty': '$qtyBefore→$qtyAfter',
      'order_status': orderAfterRf?['status'],
      'pi': paidB3?.pi,
      'li_before': liBeforeRf,
      'li_after': liAfterRf,
      'stockDelta': stockDelta,
    },
    result: b3result,
    lens: 'DM7',
    countFinding: b3result == 'HOLD',
  );
}

Future<void> runC(Rtdm c, {required String s1, required String b1}) async {
  // ----- C1 pago Stripe → chat card + order status + wallet Δ -----
  final wBuyer0 = await c.walletBal(c.buyerId);
  final wSeller0 = await c.walletBal(c.sellerId);
  final paidC1 = await c.payToPago(lens: 'DM3', initialQty: 2);
  Map<String, dynamic>? orderC1;
  Map<String, dynamic>? prodC1;
  HttpHit? hubC1;
  List<Map<String, dynamic>> chats = const [];
  List<Map<String, dynamic>> msgs = const [];
  num wBuyer1 = wBuyer0;
  num wSeller1 = wSeller0;
  if (paidC1 != null) {
    orderC1 = await c.orderRow(paidC1.oid);
    prodC1 = await c.productRow(paidC1.pid);
    hubC1 = await c.hubSku(paidC1.pid, jwt: c.buyerJwt);
    chats = await c.chatsForProduct(paidC1.pid);
    msgs = await c.chatMsgsForOrder(paidC1.oid);
    wBuyer1 = await c.walletBal(c.buyerId);
    wSeller1 = await c.walletBal(c.sellerId);
  }
  final statusPago = '${orderC1?['status']}' == 'pago';
  final qtyDrop = (numOf(prodC1?['quantity']) ?? 0) < 2;
  final dSeller = wSeller1 - wSeller0;
  final dBuyer = wBuyer1 - wBuyer0;
  final chatHasOrder = msgs.isNotEmpty ||
      chats.any((ch) =>
          '${ch['last_message']}'.contains(paidC1?.oid ?? '___'));
  final hubCoherent = statusPago &&
      ((prodC1?['is_sold'] == true) ||
          (numOf(prodC1?['quantity']) ?? 0) > 0 && (hubC1?.list.isNotEmpty ?? false) ||
          (numOf(prodC1?['quantity']) ?? 0) <= 0 && (hubC1?.list.isEmpty ?? true));

  String c1result;
  if (paidC1 == null || !statusPago) {
    c1result = paidC1 == null ? 'SKIP' : 'HOLD';
    if (paidC1 == null) {
      c.skip('C1', 'DM3', 'setup_paid_order fail', 'null');
    } else {
      c.hold(
        id: 'P1-C1-NOT-PAGO',
        lens: 'DM3',
        severity: 'P1',
        title: 'Stripe TEST succeeded mas order.status ≠ pago',
        actor: 'e2e setup_paid_order',
        pre: 'PI pm_card_visa confirm',
        repro: 'setup_paid_order',
        expected: 'status=pago',
        obtained: orderC1,
      );
    }
  } else if (!qtyDrop) {
    c1result = 'HOLD';
    c.hold(
      id: 'P1-C1-STOCK',
      lens: 'DM2',
      severity: 'P1',
      title: 'Pago Stripe sem baixar stock do produto',
      actor: 'settle',
      pre: 'initial_qty=2 compra 1',
      repro: 'setup_paid_order',
      expected: 'quantity 2→1',
      obtained: prodC1,
    );
  } else {
    c1result = 'FAIL';
    c.block('C1', 'DM3', 'pago Stripe: order+stock OK; chat/wallet observados', {
      'status': orderC1?['status'],
      'qty': prodC1?['quantity'],
      'dSeller': dSeller,
      'dBuyer': dBuyer,
      'chatHasOrder': chatHasOrder,
      'chats_n': chats.length,
      'msgs_n': msgs.length,
      'hub_n': hubC1?.list.length,
      'hubCoherent': hubCoherent,
      'pi': paidC1.pi,
    });
  }
  c.probe(
    id: 'C1',
    surfaces: 'orders + chat + wallets + Hub + products',
    action: 'setup_paid_order Stripe TEST 4242 → oráculos multi-sítio',
    http: paidC1?.hit.brief ?? 'n/a',
    oracles: {
      'status': orderC1?['status'],
      'qty': prodC1?['quantity'],
      'is_sold': prodC1?['is_sold'],
      'amount_paid_cents': orderC1?['amount_paid_cents'],
      'pi': paidC1?.pi,
      'dSeller': dSeller,
      'dBuyer': dBuyer,
      'chatHasOrder': chatHasOrder,
      'chats_n': chats.length,
      'msgs_n': msgs.length,
      'hub_n': hubC1?.list.length,
      'wallet_release_note':
          'Δwallet pode ser 0 até release — não é P0 se status=pago',
    },
    result: c1result,
    lens: 'DM5',
    countFinding: c1result == 'HOLD',
  );

  // Keep paidC1 as pago for C3? Separate paid for dispute.
  // ----- C2 off-platform MB WAY → sem Session + seller confirma -----
  final skuC2 = await c.createProduct(
    title: '$prefix C2 mbway',
    qty: 2,
    listed: true,
    live: false,
  );
  String? oidC2;
  HttpHit? cpiC2;
  HttpHit? rpcConfirm;
  HttpHit? patchPago;
  Map<String, dynamic>? orderC2;
  if (skuC2 != null) {
    oidC2 = await c.insertOrder(
      productId: skuC2,
      jwt: c.buyerJwt,
      price: 12.0,
      payment: 'MB WAY',
    );
    if (oidC2 != null) {
      cpiC2 = await c.checkout(
        orderId: oidC2,
        productId: skuC2,
        jwt: c.buyerJwt,
      );
      rpcConfirm = await c.rpc(
        'batata_seller_confirm_direct_payment',
        {'p_order_id': oidC2, 'order_id': oidC2},
        jwt: c.sellerJwt,
      );
      patchPago = await c.rest(
        'PATCH',
        'orders?id=eq.$oidC2',
        jwt: c.sellerJwt,
        body: {'status': 'pago', 'amount_paid_cents': 1200},
      );
      orderC2 = await c.orderRow(oidC2);
    }
  }
  final sqlOff = oidC2 == null
      ? null
      : await c.rpc(
          'batata_is_off_platform_payment',
          {'p_method': 'MB WAY'},
          jwt: c.buyerJwt,
        );
  final noCs = !((cpiC2?.sessionId ?? '').startsWith('cs_') && (cpiC2?.ok ?? false));
  final stillUnpaid = orderC2 != null &&
      '${orderC2['status']}' != 'pago' &&
      (numOf(orderC2['amount_paid_cents']) ?? 0) == 0;
  final cpiOff = cpiC2 != null && denied(cpiC2);

  String c2result;
  if (oidC2 == null) {
    c2result = 'SKIP';
    c.skip('C2', 'DM3', 'order MB WAY fail', 'null');
  } else if (!cpiOff || !noCs) {
    c2result = 'HOLD';
    c.hold(
      id: 'P1-C2-MBWAY-CS',
      lens: 'DM3',
      severity: 'P1',
      title: 'MB WAY canónico abriu Session Stripe',
      actor: 'B1 CPI',
      pre: 'payment_method=MB WAY',
      repro: 'create-payment-intent',
      expected: '400 off-platform; sem cs_',
      obtained: {'cpi': cpiC2?.brief, 'sql': sqlOff?.brief},
      countExactClosed: true,
    );
  } else if (!stillUnpaid) {
    c2result = 'HOLD';
    c.hold(
      id: 'P0-C2-FAKE-PAGO',
      lens: 'DM3',
      severity: 'P0',
      title: 'Seller confirmou/PATCH pago em MB WAY sem captura',
      actor: 'S1 JWT',
      pre: 'MB WAY reserva_pendente',
      repro: 'RPC confirm + PATCH status=pago',
      expected: 'status≠pago; amount_paid=0',
      obtained: {
        'rpc': rpcConfirm?.brief,
        'patch': patchPago?.brief,
        'order': orderC2,
      },
    );
  } else {
    c2result = 'FAIL';
    c.block('C2', 'DM3', 'MB WAY: CPI 400 + seller não marca pago', {
      'cpi': cpiC2?.brief,
      'rpc': rpcConfirm?.brief,
      'patch': patchPago?.brief,
      'status': orderC2?['status'],
      'sql': sqlOff?.brief,
    });
  }
  c.probe(
    id: 'C2',
    surfaces: 'orders + CPI + RPC seller confirm',
    action: 'MB WAY exact → sem Session; seller tenta confirmar',
    http: {
      'cpi': cpiC2?.brief,
      'rpc': rpcConfirm?.brief,
      'patch': patchPago?.brief,
      'sql': sqlOff?.brief,
    },
    oracles: {
      'status': orderC2?['status'],
      'cs': cpiC2?.sessionId,
      'amount_paid': orderC2?['amount_paid_cents'],
      'stillUnpaid': stillUnpaid,
    },
    result: c2result,
    lens: 'DM3',
    residual: c2result == 'FAIL',
    countFinding: c2result == 'HOLD' && c2result != 'FAIL',
  );

  // ----- C3 disputa+refund sem double stock -----
  final paidC3 = await c.payToPago(lens: 'DM7', initialQty: 2);
  HttpHit? disp;
  HttpHit? rfC3;
  Map<String, dynamic>? prodC3b;
  Map<String, dynamic>? prodC3a;
  Map<String, dynamic>? orderC3;
  num? stripeN;
  num? stripeSum;
  if (paidC3 != null) {
    prodC3b = await c.productRow(paidC3.pid);
    disp = await c.insertDispute(orderId: paidC3.oid);
    final qtyAtOpen = numOf((await c.productRow(paidC3.pid))?['quantity']) ?? 0;
    rfC3 = await c.refund(paidC3.oid);
    orderC3 = await c.orderRow(paidC3.oid);
    prodC3a = await c.productRow(paidC3.pid);
    c.note('C3.qty_at_dispute', 'qty após abrir disputa', qtyAtOpen, lens: 'DM7');
    if (paidC3.pi != null) {
      final refunds = await c.stripeRefunds(paidC3.pi!);
      if (refunds.json is Map) {
        final data = (refunds.json as Map)['data'];
        if (data is List) {
          stripeN = data.length;
          stripeSum = 0;
          for (final e in data) {
            if (e is Map) {
              stripeSum = (stripeSum ?? 0) + (numOf(e['amount']) ?? 0);
            }
          }
        }
      }
    }
  }
  final q0 = numOf(prodC3b?['quantity']) ?? 0;
  final q1 = numOf(prodC3a?['quantity']) ?? 0;
  final dStock = q1 - q0;
  final paidCents = numOf(orderC3?['amount_paid_cents']) ?? 0;
  final stockOk = dStock <= 1 &&
      dStock >= 0 &&
      (stripeN == null || stripeN <= 1) &&
      (stripeSum == null || stripeSum <= paidCents || paidCents == 0);

  String c3result;
  if (paidC3 == null) {
    c3result = 'SKIP';
    c.skip('C3', 'DM7', 'paid fail', 'null');
  } else if (!stockOk) {
    c3result = 'HOLD';
    c.hold(
      id: 'P1-C3-DOUBLE',
      lens: 'DM7',
      severity: 'P1',
      title: 'Disputa+refund restaurou stock ×2 ou refund > captura',
      actor: 'B1 disputa + S1 refund',
      pre: 'pago Stripe TEST',
      repro: 'POST order_disputes + refund-order',
      expected: 'stock +0/+1; ≤1 refund ≤ captura',
      obtained: {
        'qty': '$q0→$q1',
        'stripeN': stripeN,
        'stripeSum': stripeSum,
        'paid': paidCents,
        'disp': disp?.brief,
        'rf': rfC3?.brief,
      },
    );
  } else {
    c3result = 'FAIL';
    c.block('C3', 'DM7', 'disputa+refund stock ≤1 e refund ≤ captura', {
      'qty': '$q0→$q1',
      'stripeN': stripeN,
      'stripeSum': stripeSum,
      'disp': disp?.status,
      'rf': rfC3?.brief,
      'status': orderC3?['status'],
    });
  }
  c.probe(
    id: 'C3',
    surfaces: 'order_disputes + refund-order + products + Stripe',
    action: 'disputa aberta + refund sem double stock',
    http: {'disp': disp?.brief, 'rf': rfC3?.brief},
    oracles: {
      'qty': '$q0→$q1',
      'status': orderC3?['status'],
      'stripeN': stripeN,
      'stripeSum': stripeSum,
      'paidCents': paidCents,
    },
    result: c3result,
    lens: 'DM7',
    countFinding: c3result == 'HOLD',
  );
}

Future<void> runD(
  Rtdm c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // ----- D1 bag ∥ live accept mesmo stock qty=1 -----
  final skuD1 = await c.createProduct(
    title: '$prefix D1 race',
    qty: 1,
    listed: true,
    live: true,
  );
  final liveD1 = await c.createLive(title: '$prefix D1 race');
  HttpHit? bagD;
  HttpHit? accD;
  Map<String, dynamic>? resD;
  Map<String, dynamic>? prodD1;
  if (skuD1 != null && liveD1 != null) {
    final li = await c.createLiveItem(
      liveId: liveD1,
      title: '$prefix D1 li',
      kind: 'marketplace_product',
      productId: skuD1,
    );
    final oid = await c.insertOrder(
      productId: skuD1,
      jwt: c.buyerJwt,
      price: 12.0,
    );
    final rid = li == null
        ? null
        : await c.insertReservation(
            liveId: liveD1,
            liveItemId: li,
            jwt: c.buyer2Jwt,
            buyer: b2,
          );
    if (oid != null && rid != null) {
      final raced = await Future.wait([
        c.checkout(
          orderId: oid,
          productId: skuD1,
          jwt: c.buyerJwt,
        ),
        c.acceptRes(rid),
      ]);
      bagD = raced[0];
      accD = raced[1];
      resD = await c.resRow(rid);
    }
    prodD1 = await c.productRow(skuD1);
  }
  final d1Cs = (bagD?.ok ?? false) && (bagD?.sessionId ?? '').startsWith('cs_');
  final d1Acc = resD?['status'] == 'accepted';
  String d1result;
  if (skuD1 == null) {
    d1result = 'SKIP';
    c.skip('D1', 'DM4', 'fixture fail', 'null');
  } else if (d1Cs && d1Acc) {
    d1result = 'HOLD';
    c.hold(
      id: 'P1-D1-RACE',
      lens: 'DM4',
      severity: 'P1',
      title: 'Race bag CPI ∥ live accept: dois claims na última unidade',
      actor: 'B1 ∥ S1 accept B2',
      pre: 'qty=1',
      repro: 'Future.wait CPI ∥ PATCH accepted',
      expected: '≤1 sucesso',
      obtained: {'cpi': bagD?.brief, 'acc': accD?.brief, 'res': resD, 'prod': prodD1},
    );
  } else {
    d1result = 'FAIL';
    c.block('D1', 'DM4', 'race bag∥accept: ≤1 claim', {
      'd1Cs': d1Cs,
      'd1Acc': d1Acc,
      'cpi': bagD?.brief,
      'acc': accD?.brief,
      'res': resD,
    });
  }
  c.probe(
    id: 'D1',
    surfaces: 'CPI bag + live_reservation + products',
    action: 'Future.wait CPI ∥ live accept qty=1',
    http: {'cpi': bagD?.brief, 'accept': accD?.brief},
    oracles: {'cs': d1Cs, 'accepted': d1Acc, 'prod': prodD1, 'res': resD},
    result: d1result,
    lens: 'DM4',
    countFinding: d1result == 'HOLD',
  );

  // ----- D2 end_live ∥ CPI -----
  final skuD2 = await c.createProduct(
    title: '$prefix D2 end∥cpi',
    qty: 1,
    listed: true,
    live: true,
  );
  final liveD2 = await c.createLive(title: '$prefix D2 air');
  HttpHit? cpiD2;
  Map<String, dynamic>? liveAfter;
  Map<String, dynamic>? orderD2;
  if (skuD2 != null && liveD2 != null) {
    await c.createLiveItem(
      liveId: liveD2,
      title: '$prefix D2 li',
      kind: 'marketplace_product',
      productId: skuD2,
    );
    final oid = await c.insertOrder(
      productId: skuD2,
      jwt: c.buyerJwt,
      price: 12.0,
    );
    if (oid != null) {
      final raced = await Future.wait([
        c.endLive(liveD2).then((_) async {
          return c.rest(
            'GET',
            'lives?id=eq.$liveD2&select=id,status,is_active',
            service: true,
          );
        }),
        c.checkout(orderId: oid, productId: skuD2, jwt: c.buyerJwt),
      ]);
      liveAfter = raced[0].map;
      cpiD2 = raced[1];
      orderD2 = await c.orderRow(oid);
    }
  }
  final liveEnded = liveAfter?['status'] == 'ended' || liveAfter?['is_active'] == false;
  final cpiOk = (cpiD2?.ok ?? false) && (cpiD2?.sessionId ?? '').startsWith('cs_');
  String d2result;
  if (skuD2 == null || liveD2 == null) {
    d2result = 'SKIP';
    c.skip('D2', 'DM4', 'fixture fail', 'null');
  } else {
    // Marketplace CPI can still succeed after live ended — that's OK if product listed.
    // Finding only if CPI succeeds AND live still shows as public live stock.
    final hubLive = await c.hubLives(liveD2, anon: true);
    final liveStillPublic = hubLive.list.isNotEmpty && liveEnded == false;
    if (cpiOk && liveStillPublic) {
      d2result = 'HOLD';
      c.hold(
        id: 'P2-D2-LIVE-PUBLIC',
        lens: 'DM4',
        severity: 'P2',
        title: 'end_live perdeu a race: Hub ainda mostra live activa + CPI OK',
        actor: 'service end ∥ B1 CPI',
        pre: 'live hitch + listed SKU',
        repro: 'Future.wait end_live ∥ CPI',
        expected: 'live ended no Hub; CPI só se SKU marketplace listado',
        obtained: {
          'live': liveAfter,
          'cpi': cpiD2?.brief,
          'hubLive_n': hubLive.list.length,
        },
      );
    } else {
      d2result = 'FAIL';
      c.block('D2', 'DM4', 'end_live∥CPI: live ended; CPI marketplace documentado', {
        'liveEnded': liveEnded,
        'cpiOk': cpiOk,
        'hubLive_n': hubLive.list.length,
        'order': orderD2?['status'],
      });
    }
  }
  c.probe(
    id: 'D2',
    surfaces: 'lives + Hub lives + CPI + orders',
    action: 'Future.wait end_live ∥ CPI mesmo SKU hitch',
    http: cpiD2?.brief ?? 'n/a',
    oracles: {
      'liveAfter': liveAfter,
      'cpiOk': cpiOk,
      'liveEnded': liveEnded,
      'order': orderD2?['status'],
    },
    result: d2result,
    lens: 'DM4',
    countFinding: d2result == 'HOLD',
  );

  // ----- D3 refund ∥ nova compra mesma unidade -----
  final paidD3 = await c.payToPago(lens: 'DM4', initialQty: 1);
  HttpHit? rfD3;
  HttpHit? cpiNew;
  Map<String, dynamic>? prodMid;
  Map<String, dynamic>? prodEnd;
  Map<String, dynamic>? orderOld;
  Map<String, dynamic>? orderNew;
  if (paidD3 != null) {
    prodMid = await c.productRow(paidD3.pid);
    final oidNew = await c.insertOrder(
      productId: paidD3.pid,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 5.9,
    );
    if (oidNew != null) {
      final raced = await Future.wait([
        c.refund(paidD3.oid),
        c.checkout(
          orderId: oidNew,
          productId: paidD3.pid,
          jwt: c.buyer2Jwt,
          buyer: b2,
        ),
      ]);
      rfD3 = raced[0];
      cpiNew = raced[1];
      orderOld = await c.orderRow(paidD3.oid);
      orderNew = await c.orderRow(oidNew);
      prodEnd = await c.productRow(paidD3.pid);
    }
  }
  final newCs = (cpiNew?.ok ?? false) && (cpiNew?.sessionId ?? '').startsWith('cs_');
  final refunded = rfD3 != null && (rfD3.ok || '${rfD3.body}'.contains('already_refunded'));
  final qtyEnd = numOf(prodEnd?['quantity']) ?? -1;
  final qtyMid = numOf(prodMid?['quantity']) ?? -1;
  // After pay qty1→0 sold; refund restores; parallel buy of restored unit.
  // Finding: new CPI succeeds WHILE qty still 0 AND refund didn't restore yet
  // but then both leave qty inconsistent (e.g. qty=2 after refund+no consume, or qty=-ish).
  final inconsistent = qtyEnd > 1 || qtyEnd < 0;

  String d3result;
  if (paidD3 == null) {
    d3result = 'SKIP';
    c.skip('D3', 'DM4', 'paid fail', 'null');
  } else if (inconsistent) {
    d3result = 'HOLD';
    c.hold(
      id: 'P1-D3-REFUND-RACE',
      lens: 'DM4',
      severity: 'P1',
      title: 'Refund ∥ nova CPI deixou stock incoerente',
      actor: 'S1 refund ∥ B2 CPI',
      pre: 'pago qty inicial 1 (após pay ~0)',
      repro: 'Future.wait refund-order ∥ CPI',
      expected: 'qty 0 ou 1 coerente com claims',
      obtained: {
        'qtyMid': qtyMid,
        'qtyEnd': qtyEnd,
        'rf': rfD3?.brief,
        'cpi': cpiNew?.brief,
        'old': orderOld?['status'],
        'new': orderNew?['status'],
      },
    );
  } else {
    d3result = 'FAIL';
    c.block('D3', 'DM4', 'refund∥nova compra: stock coerente', {
      'qtyMid': qtyMid,
      'qtyEnd': qtyEnd,
      'refunded': refunded,
      'newCs': newCs,
      'old': orderOld?['status'],
      'new': orderNew?['status'],
    });
  }
  c.probe(
    id: 'D3',
    surfaces: 'refund-order + CPI + products + orders',
    action: 'Future.wait refund ∥ CPI nova compra mesma unidade',
    http: {'rf': rfD3?.brief, 'cpi': cpiNew?.brief},
    oracles: {
      'qtyMid': qtyMid,
      'qtyEnd': qtyEnd,
      'old_status': orderOld?['status'],
      'new_status': orderNew?['status'],
      'newCs': newCs,
      'refunded': refunded,
    },
    result: d3result,
    lens: 'DM4',
    countFinding: d3result == 'HOLD',
  );
}
