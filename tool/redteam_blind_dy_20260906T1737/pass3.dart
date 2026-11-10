/// DY pass3 — C1 selo e B1 bag com B2 (B1 rate-limited). Staging. NÃO corrigir.
import 'dart:io';
import '_rtdy.dart';

Future<void> main() async {
  final c = Rtdy.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  final s1 = c.sellerId!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;
  await c.restoreSeller1Published();

  try {
    await redoC1b2(c, s1, b2);
    await redoB1b2(c, s1, b1, b2);
  } finally {
    await c.endAllCreatedLives();
    await c.restoreSeller1Published();
  }

  await dumpJson('${outDir()}/pass3.json', {
    'auditor': 'REDTEAM_BLIND_DY_COMPOSICAO_POS_DNDS_v1',
    'pass': 3,
    'prefix': prefix,
    'probes': c.probes,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'skipped': c.skipped,
    'classe_nova': c.classeNova.toList()..sort(),
  });
  stdout.writeln('WROTE pass3.json probes=${c.probes.length} '
      'findings=${c.findings.length}');
}

Future<void> redoC1b2(Rtdy c, String s1, String b2) async {
  final sku = await c.createProduct(
    title: '$prefix C1b offer',
    qty: 2,
    price: 18.0,
    listed: true,
    live: false,
  );
  if (sku == null) {
    c.skip('C1b', 'DY6', 'sku', 'null');
    return;
  }
  final off = await c.insertOffer(
    productId: sku,
    amount: 8,
    listPrice: 18,
    jwt: c.buyer2Jwt,
    buyer: b2,
  );
  final offId = off.firstId;
  if (offId == null) {
    c.skip('C1b', 'DY6', 'offer', off.brief);
    return;
  }
  await c.acceptOffer(offId);
  final offRow = await c.offerRow(offId);
  final oid = await c.insertOrder(
    productId: sku,
    jwt: c.buyer2Jwt,
    buyer: b2,
    price: 8.0,
    offerId: offId,
  );
  HttpHit? cpi;
  if (oid != null) {
    cpi = await c.checkout(
      orderId: oid,
      productId: sku,
      jwt: c.buyer2Jwt,
      buyer: b2,
      amount: 1,
    );
    if (c.usefulCs(cpi)) c.createdSessionIds.add(cpi.sessionId!);
  }
  final hub = await c.hubSku(sku, jwt: c.buyer2Jwt);
  final sealed = cpi?.amountTotal;
  final under = c.usefulCs(cpi) && sealed != null && sealed < 800;
  String result;
  if (under) {
    result = 'HOLD';
    c.hold(
      id: 'P0-C1-UNDERPAY',
      lens: 'DY6',
      severity: 'P0',
      title: 'CPI selou underpay da oferta aceite',
      actor: 'B2 CPI amount=1 vs oferta 8€',
      pre: 'oferta aceite 8€ list 18€',
      repro: 'create-payment-intent amount=1',
      expected: 'selo ≥800¢ (oferta) ou deny',
      obtained: {
        'sealed': sealed,
        'offer': offRow,
        'cpi': cpi?.brief,
        'hub_n': hub.list.length,
      },
    );
  } else {
    result = 'FAIL';
    c.block('C1b', 'DY6', 'oferta aceite: selo servidor vs amount=1 (B2)', {
      'offer': offRow?['amount'],
      'status': offRow?['status'],
      'sealed': sealed,
      'hub_n': hub.list.length,
      'cpi': cpi?.brief,
      'cs': cpi?.sessionId,
    });
  }
  c.probe(
    id: 'C1b',
    surfaces: 'offer + CPI + Hub + orders',
    action: 'B2 oferta 8€ aceite + CPI amount=1 (selo)',
    http: {'off': off.brief, 'cpi': cpi?.brief},
    oracles: {
      'offer_amt': offRow?['amount'],
      'offer_st': offRow?['status'],
      'sealed_cents': sealed,
      'hub_n': hub.list.length,
      'cs': cpi?.sessionId,
    },
    result: result,
    lens: 'DY6',
    classeNova: true,
    countFinding: result == 'HOLD',
  );
}

Future<void> redoB1b2(Rtdy c, String s1, String b1, String b2) async {
  final skuA = await c.createProduct(
    title: '$prefix B1b hitch-A',
    qty: 1,
    listed: true,
    live: true,
  );
  final skuB = await c.createProduct(
    title: '$prefix B1b bag-B',
    qty: 1,
    listed: true,
    live: false,
  );
  final live = await c.createLive(title: '$prefix B1b raffle-bag');
  if (skuA == null || skuB == null || live == null) {
    c.skip('B1b', 'DY2', 'fixture', 'null');
    return;
  }
  final liA = await c.createLiveItem(
    liveId: live,
    title: '$prefix B1b li-A',
    kind: 'marketplace_product',
    productId: skuA,
  );
  final raf = await c.createRaffle(
    liveId: live,
    seller: s1,
    liveItemId: liA,
    title: '$prefix B1b raffle-A',
  );
  if (raf.firstId != null) {
    await c.awardTickets(raf.firstId!, b1, src: 'b1b');
  }
  String? resA;
  HttpHit? acc;
  if (liA != null) {
    resA = await c.insertReservation(
      liveId: live,
      liveItemId: liA,
      jwt: c.buyerJwt,
      buyer: b1,
    );
    if (resA != null) acc = await c.acceptRes(resA);
  }
  final oidB = await c.insertOrder(
    productId: skuB,
    jwt: c.buyer2Jwt,
    buyer: b2,
    price: 12.0,
  );
  HttpHit? bagB;
  if (oidB != null) {
    bagB = await c.checkoutBag(
      lines: [
        {'order_id': oidB, 'product_id': skuB, 'quantity': 1, 'price': 12.0},
      ],
      jwt: c.buyer2Jwt,
      buyer: b2,
      seller: s1,
    );
    if (c.usefulCs(bagB)) c.createdSessionIds.add(bagB.sessionId!);
  }
  final hubA = await c.hubSku(skuA, jwt: c.buyerJwt);
  final hubB = await c.hubSku(skuB, jwt: c.buyerJwt);
  final resRow = resA == null ? null : await c.resRow(resA);
  final accepted = '${resRow?['status']}' == 'accepted';
  final bagOk = c.usefulCs(bagB);
  String result;
  if (accepted && !bagOk && denied(bagB ?? HttpHit(0, '', {}))) {
    result = 'HOLD';
    c.hold(
      id: 'P2-B1-CROSS-LINE',
      lens: 'DY2',
      severity: 'P2',
      title: 'Accept live SKU-A (com rifa) bloqueou saco da OUTRA linha SKU-B',
      actor: 'S1 accept + B2 bag',
      pre: 'SKU-A hitch+rifa accepted; SKU-B stock independente',
      repro: 'accept A + bag CPI B',
      expected: 'saco B abre cs_',
      obtained: {
        'acc': acc?.brief,
        'bag': bagB?.brief,
        'hubA': hubA.list.length,
        'hubB': hubB.list.length,
      },
    );
  } else {
    result = 'FAIL';
    c.block('B1b', 'DY2', 'rifa+accept A não cega bag B; Hub A/B', {
      'accepted': accepted,
      'bag_cs': bagB?.sessionId,
      'bag': bagB?.brief,
      'hubA': hubA.list.length,
      'hubB': hubB.list.length,
      'raf': raf.firstId,
    });
  }
  c.probe(
    id: 'B1b',
    surfaces: 'rifa + live accept + bag outra linha + Hub',
    action: 'B1 hitch A + B2 bag CPI SKU-B (evitar rate-limit B1)',
    http: {'acc': acc?.brief, 'bag': bagB?.brief, 'raf': raf.brief},
    oracles: {
      'res': resRow?['status'],
      'bag_cs': bagB?.sessionId,
      'hubA_n': hubA.list.length,
      'hubB_n': hubB.list.length,
    },
    result: result,
    lens: 'DY2',
    classeNova: true,
    countFinding: result == 'HOLD',
  );
}
