/// DY pass2 — confirmar C1 selo, B1 bag após rate-limit, A5 hitch pós-draw, A1 ledger.
/// Staging only. NÃO corrigir.
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

  stdout.writeln('sleep 50s for checkout rate-limit…');
  await Future<void>.delayed(const Duration(seconds: 50));

  try {
    await confirmA1(c, s1);
    await redoC1(c, s1, b1);
    await redoB1(c, s1, b1, b2);
    await redoA5hitch(c, s1, b1, b2);
  } finally {
    await c.endAllCreatedLives();
    await c.restoreSeller1Published();
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

  await dumpJson('${outDir()}/pass2.json', {
    'auditor': 'REDTEAM_BLIND_DY_COMPOSICAO_POS_DNDS_v1',
    'pass': 2,
    'prefix': prefix,
    'probes': c.probes,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'skipped': c.skipped,
    'classe_nova': c.classeNova.toList()..sort(),
  });
  stdout.writeln('WROTE pass2.json probes=${c.probes.length} '
      'findings=${c.findings.length}');
}

Future<void> confirmA1(Rtdy c, String s1) async {
  final led = await c.payoutLedger(s1, limit: 10);
  final hit = led.where((r) {
    final k = '${r['idempotency_key']}';
    return k.contains('rtdy1737unpubpay');
  }).toList();
  final w = await c.walletRow(s1);
  final prof = await c.profile(s1);
  c.note('A1.ledger', 'payout ledger vs unpublished (pass1)', {
    'wallet': w,
    'hub': prof?['hub_published'],
    'match': hit,
    'led_n': led.length,
    'led_head': led.take(3).toList(),
  }, lens: 'DY8');
  c.probe(
    id: 'A1r',
    surfaces: 'wallet ledger + Hub published + tip pending',
    action: 'confirmar rtdy1737unpubpay no ledger (saldo existente, não mint)',
    http: {'match_n': hit.length, 'hub': prof?['hub_published']},
    oracles: {
      'match': hit,
      'balance': w?['balance'],
      'published': prof?['hub_published'],
    },
    result: 'FAIL',
    lens: 'DY4',
    classeNova: true,
  );
}

Future<void> redoC1(Rtdy c, String s1, String b1) async {
  final sku = await c.createProduct(
    title: '$prefix C1r offer',
    qty: 2,
    price: 18.0,
    listed: true,
    live: false,
  );
  if (sku == null) {
    c.skip('C1r', 'DY6', 'sku', 'null');
    return;
  }
  final off = await c.insertOffer(
    productId: sku,
    amount: 8,
    listPrice: 18,
    jwt: c.buyerJwt,
  );
  final offId = off.firstId;
  if (offId == null) {
    c.skip('C1r', 'DY6', 'offer', off.brief);
    return;
  }
  await c.acceptOffer(offId);
  final offRow = await c.offerRow(offId);
  final oid = await c.insertOrder(
    productId: sku,
    jwt: c.buyerJwt,
    price: 8.0,
    offerId: offId,
  );
  HttpHit? cpi;
  if (oid != null) {
    cpi = await c.checkout(
      orderId: oid,
      productId: sku,
      jwt: c.buyerJwt,
      amount: 1,
    );
    if (c.usefulCs(cpi)) c.createdSessionIds.add(cpi.sessionId!);
  }
  final hub = await c.hubSku(sku, jwt: c.buyerJwt);
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
      actor: 'B1 CPI amount=1 vs oferta 8€',
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
    c.block('C1r', 'DY6', 'oferta aceite: selo servidor vs amount=1', {
      'offer': offRow?['amount'],
      'status': offRow?['status'],
      'sealed': sealed,
      'hub_n': hub.list.length,
      'cpi': cpi?.brief,
    });
  }
  c.probe(
    id: 'C1r',
    surfaces: 'offer + CPI + Hub + orders',
    action: 'oferta 8€ aceite + CPI amount=1 (selo) após rate-limit',
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

Future<void> redoB1(Rtdy c, String s1, String b1, String b2) async {
  final skuA = await c.createProduct(
    title: '$prefix B1r hitch-A',
    qty: 1,
    listed: true,
    live: true,
  );
  final skuB = await c.createProduct(
    title: '$prefix B1r bag-B',
    qty: 1,
    listed: true,
    live: false,
  );
  final live = await c.createLive(title: '$prefix B1r raffle-bag');
  if (skuA == null || skuB == null || live == null) {
    c.skip('B1r', 'DY2', 'fixture', 'null');
    return;
  }
  final liA = await c.createLiveItem(
    liveId: live,
    title: '$prefix B1r li-A',
    kind: 'marketplace_product',
    productId: skuA,
  );
  final raf = await c.createRaffle(
    liveId: live,
    seller: s1,
    liveItemId: liA,
    title: '$prefix B1r raffle-A',
  );
  if (raf.firstId != null) {
    await c.awardTickets(raf.firstId!, b2, src: 'b1r');
  }
  String? resA;
  HttpHit? acc;
  if (liA != null) {
    resA = await c.insertReservation(
      liveId: live,
      liveItemId: liA,
      jwt: c.buyer2Jwt,
      buyer: b2,
    );
    if (resA != null) acc = await c.acceptRes(resA);
  }
  final oidB = await c.insertOrder(
    productId: skuB,
    jwt: c.buyerJwt,
    price: 12.0,
  );
  HttpHit? bagB;
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
      actor: 'S1 accept + B1 bag',
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
    c.block('B1r', 'DY2', 'rifa+accept A não cega bag B; Hub A/B', {
      'accepted': accepted,
      'bag_cs': bagB?.sessionId,
      'bag': bagB?.brief,
      'hubA': hubA.list.length,
      'hubB': hubB.list.length,
      'raf': raf.firstId,
    });
  }
  c.probe(
    id: 'B1r',
    surfaces: 'rifa + live accept + bag outra linha + Hub',
    action: 'rifa activa A + accept hitch A + bag CPI SKU-B (retry)',
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

Future<void> redoA5hitch(Rtdy c, String s1, String b1, String b2) async {
  final sku = await c.createProduct(
    title: '$prefix A5r prize',
    qty: 1,
    listed: true,
    live: true,
  );
  final live = await c.createLive(title: '$prefix A5r raffle');
  if (sku == null || live == null) {
    c.skip('A5r', 'DY7', 'fixture', 'null');
    return;
  }
  final li = await c.createLiveItem(
    liveId: live,
    title: '$prefix A5r li',
    kind: 'marketplace_product',
    productId: sku,
  );
  final raf = await c.createRaffle(
    liveId: live,
    seller: s1,
    liveItemId: li,
    title: '$prefix A5r prize',
  );
  final rafId = raf.firstId;
  if (rafId == null || li == null) {
    c.skip('A5r', 'DY7', 'raffle', raf.brief);
    return;
  }
  await c.awardTickets(rafId, b1, src: 'a5r');
  await c.closeRaffle(rafId);
  final draw = await c.drawRaffle(rafId);
  final winners = await c.raffleWinners(rafId);
  final prizes = await c.prizeOrders(rafId);
  final prod = await c.productRow(sku);
  final hub = await c.hubSku(sku, jwt: c.buyerJwt);
  final item0 = await c.liveItemRow(li);
  final res = await c.insertReservation(
    liveId: live,
    liveItemId: li,
    jwt: c.buyer2Jwt,
    buyer: b2,
  );
  HttpHit? acc;
  Map<String, dynamic>? resRow;
  if (res != null) {
    acc = await c.acceptRes(res);
    resRow = await c.resRow(res);
  }
  final item1 = await c.liveItemRow(li);
  final acceptedAfterDraw = '${resRow?['status']}' == 'accepted';
  String result;
  if (winners.isNotEmpty && acceptedAfterDraw) {
    result = 'HOLD';
    c.hold(
      id: 'P2-A5-HITCH-AFTER-DRAW',
      lens: 'DY7',
      severity: 'P2',
      title: 'Após draw, hitch live do prémio ainda aceita reserva',
      actor: 'B2 reservation + S1 accept',
      pre: 'rifa drawn; Hub n=0 qty=0',
      repro: 'POST live_reservation_requests + PATCH accepted',
      expected: 'reserva deny; item ≠ available',
      obtained: {
        'draw': draw.brief,
        'hub_n': hub.list.length,
        'qty': prod?['quantity'],
        'item0': item0?['status'],
        'item1': item1?['status'],
        'res': resRow,
        'acc': acc?.brief,
        'prize_n': prizes.length,
      },
    );
  } else {
    result = 'FAIL';
    c.block('A5r', 'DY7', 'hitch pós-draw vs Hub/stock selados', {
      'hub_n': hub.list.length,
      'qty': prod?['quantity'],
      'winners': winners.length,
      'prize_n': prizes.length,
      'item0': item0?['status'],
      'item1': item1?['status'],
      'res': res,
      'res_st': resRow?['status'],
      'acc': acc?.brief,
    });
  }
  c.probe(
    id: 'A5r',
    surfaces: 'rifa drawn + live hitch + Hub + products',
    action: 'após draw Hub 0: B2 reserva live_item still available',
    http: {'draw': draw.brief, 'acc': acc?.brief, 'res': res},
    oracles: {
      'hub_n': hub.list.length,
      'qty': prod?['quantity'],
      'winners': winners.length,
      'prize_n': prizes.length,
      'item0': item0?['status'],
      'item1': item1?['status'],
      'res_st': resRow?['status'],
    },
    result: result,
    lens: 'DY7',
    classeNova: true,
    countFinding: result == 'HOLD',
  );
}
