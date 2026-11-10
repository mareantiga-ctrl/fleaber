/// RED TEAM CEGO DU pass1 — rifa / Hub / stock / convert / hitch pós-DNDS ≥16.
/// Staging only. NÃO corrigir. NÃO produção. NÃO Fase 4.
import 'dart:io';

import '_rtdu.dart';

String pastIso() => DateTime.now()
    .toUtc()
    .subtract(const Duration(minutes: 2))
    .toIso8601String();

Future<void> main() async {
  final c = Rtdu.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final s1 = c.sellerId!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;
  final s2 = c.seller2Id!;

  await c.restoreSeller1Published();
  await c.setHub(s2, false);

  try {
    await runA(c, s1: s1, b1: b1, b2: b2);
    await runB(c, s1: s1, b1: b1, b2: b2);
    await runC(c, s1: s1, b1: b1, b2: b2);
    await runD(c, s1: s1, b1: b1);
  } finally {
    await c.endAllCreatedLives();
    await c.restoreSeller1Published();
    for (final rid in c.createdRaffleIds) {
      await c.rest(
        'PATCH',
        'live_raffles?id=eq.$rid',
        service: true,
        body: {'status': 'cancelled'},
        prefer: 'return=minimal',
      );
    }
  }

  final nova = c.probes.where((p) => p['classe_nova'] == true).length;
  final races = c.probes.where((p) => p['race'] == true).length;
  final residual = c.probes.where((p) => p['residual'] == true).length;
  await dumpJson('${outDir()}/pass1.json', {
    'auditor': 'REDTEAM_BLIND_DU_RAFFLE_HUB_POS_DNDS_v1',
    'prefix': prefix,
    'staging': projectMust,
    'probes': c.probes,
    'findings': c.findings,
    'blocked': c.blocked,
    'skipped': c.skipped,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
    'classe_nova': c.classeNova.toList()..sort(),
    'counts': {
      'probes': c.probes.length,
      'classe_nova': nova,
      'races': races,
      'residual': residual,
      'findings': c.findings.length,
    },
    'actors': {'b1': b1, 's1': s1, 'b2': b2, 's2': s2},
    'created': {
      'products': c.createdProductIds,
      'orders': c.createdOrderIds,
      'lives': c.createdLiveIds,
      'items': c.createdLiveItemIds,
      'res': c.createdResIds,
      'raffles': c.createdRaffleIds,
    },
  });
  stdout.writeln('WROTE ${outDir()}/pass1.json probes=${c.probes.length} '
      'nova=$nova races=$races residual=$residual findings=${c.findings.length}');
}

Future<({
  String? sku,
  String? live,
  String? li,
  String? raf,
  HttpHit? ins,
})> makeHitchRaffle(
  Rtdu c, {
  required String s1,
  required String title,
  int qty = 1,
  int winnerCount = 1,
  bool hitch = true,
  bool listed = true,
}) async {
  String? sku;
  if (hitch) {
    sku = await c.createProduct(
      title: '$prefix $title',
      qty: qty,
      listed: listed,
      live: true,
      price: 9.0,
    );
  }
  final live = await c.createLive(title: '$prefix $title');
  String? li;
  if (live != null) {
    li = hitch && sku != null
        ? await c.createLiveItem(
            liveId: live,
            title: '$prefix $title-li',
            kind: 'marketplace_product',
            productId: sku,
          )
        : await c.createLiveItem(
            liveId: live,
            title: '$prefix $title-li',
            kind: 'live_only',
            quantity: qty,
          );
  }
  HttpHit? ins;
  String? raf;
  if (live != null) {
    ins = await c.rest('POST', 'live_raffles', service: true, body: {
      'live_id': live,
      'seller_id': s1,
      'title': '$prefix $title',
      'status': 'active',
      'winner_count': winnerCount,
      if (li != null) 'live_item_id': li,
      'ends_at': pastIso(),
    });
    raf = ins.firstId;
    if (raf != null) c.createdRaffleIds.add(raf);
  }
  return (sku: sku, live: live, li: li, raf: raf, ins: ins);
}

Future<void> runA(
  Rtdu c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  final fx = await makeHitchRaffle(c,
      s1: s1, title: 'A1 qty1 hitch', qty: 1, winnerCount: 1);
  HttpHit? award;
  HttpHit? close;
  HttpHit? drawBuyer;
  HttpHit? draw1;
  HttpHit? draw2;
  HttpHit? hubA1;
  HttpHit? insAfter;
  HttpHit? cpiAfter;
  HttpHit? sealCall;
  Map<String, dynamic>? prodBefore;
  Map<String, dynamic>? prodAfter;
  Map<String, dynamic>? liAfter;
  Map<String, dynamic>? rafAfter;
  List<Map<String, dynamic>> winners = const [];
  List<Map<String, dynamic>> prizes = const [];
  var tickets = 0;

  if (fx.raf != null && fx.sku != null) {
    award = await c.awardTickets(raffleId: fx.raf!, userId: b1, delta: 5);
    tickets = await c.raffleTickets(fx.raf!, b1);
    close = await c.closeRaffle(fx.raf!);
    prodBefore = await c.productRow(fx.sku!);

    // A5 first: buyer JWT draw on closed raffle with tickets
    drawBuyer = await c.drawRaffle(fx.raf!, jwt: c.buyerJwt);

    draw1 = await c.drawRaffle(fx.raf!, jwt: c.sellerJwt);
    draw2 = await c.drawRaffle(fx.raf!, jwt: c.sellerJwt);
    winners = await c.raffleWinners(fx.raf!);
    prizes = await c.prizeOrders(fx.raf!);
    prodAfter = await c.productRow(fx.sku!);
    liAfter = fx.li == null ? null : await c.liveItemRow(fx.li!);
    rafAfter = await c.raffleRow(fx.raf!);
    hubA1 = await c.hubSku(fx.sku!, jwt: c.buyerJwt);
    sealCall = await c.sealPrize(fx.raf!);

    insAfter = await c.insertOrderHit(
      productId: fx.sku!,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 9.0,
    );
    if (insAfter.ok && insAfter.firstId != null) {
      cpiAfter = await c.checkout(
        orderId: insAfter.firstId!,
        jwt: c.buyer2Jwt,
        buyer: b2,
        productId: fx.sku!,
        seller: s1,
        amount: 9,
      );
    } else {
      cpiAfter = insAfter;
    }
  }

  final hubN = hubA1?.list.length ?? -1;
  final q0 = numOf(prodBefore?['quantity']) ?? -1;
  final q1 = numOf(prodAfter?['quantity']) ?? -1;
  final sold = prodAfter?['is_sold'] == true;
  final listed = prodAfter?['list_on_marketplace'] == true;
  final liStatus = '${liAfter?['status'] ?? ''}';
  final liAvail = liStatus.toLowerCase() == 'available';
  final prizeN = prizes.length;
  final drawOk = draw1?.rpcOk == true ||
      (draw1?.ok == true && '${rafAfter?['status']}' == 'drawn');
  final buyerDrew = drawBuyer?.rpcOk == true;
  final doubleWin = winners.length > 1;
  final insertLeak = insAfter != null && insAfter.ok;
  final hubLeak = drawOk && hubN > 0;
  final qtyLeak = drawOk && q1 >= 1 && !sold;

  // ----- A5 -----
  if (fx.raf == null) {
    c.skip('A5', 'DU6', 'raffle fixture fail', fx.ins?.brief);
  } else if (buyerDrew) {
    c.hold(
      id: 'P1-A5-BUYER-DRAW',
      lens: 'DU6',
      severity: 'P1',
      title: 'JWT comprador sorteou a rifa',
      actor: 'buyer JWT',
      pre: 'rifa closed com tickets B1',
      repro: 'rpc batata_draw_live_raffle_winners JWT buyer',
      expected: 'not_allowed / 4xx',
      obtained: drawBuyer?.brief,
    );
  } else {
    c.block('A5', 'DU6', 'buyer draw recusado', drawBuyer?.brief);
  }
  c.probe(
    id: 'A5',
    surfaces: 'rifa RPC',
    action: 'JWT buyer tenta batata_draw_live_raffle_winners',
    http: drawBuyer ?? 'n/a',
    oracles: {'winners_pre': 0, 'buyer_ok': buyerDrew},
    result: fx.raf == null ? 'SKIP' : (buyerDrew ? 'FAIL' : 'HOLD'),
    lens: 'DU6',
    countFinding: buyerDrew,
  );

  // ----- A1 reteste clássico qty=1 -----
  String a1result;
  if (fx.sku == null || fx.raf == null || !drawOk) {
    a1result = fx.raf == null ? 'SKIP' : (drawOk ? 'HOLD' : 'FAIL');
    if (fx.raf == null) {
      c.skip('A1', 'DU1', 'fixture fail', fx.ins?.brief);
    } else if (!drawOk) {
      c.hold(
        id: 'P2-A1-DRAW-FAIL',
        lens: 'DU1',
        severity: 'P2',
        title: 'Draw qty=1 hitch não fechou drawn',
        actor: 'seller JWT',
        pre: 'SKU qty=1 listed hitch + tickets',
        repro: 'close + batata_draw_live_raffle_winners',
        expected: 'drawn + Hub 0',
        obtained: {'draw': draw1?.brief, 'status': rafAfter?['status']},
      );
    }
  } else if (hubLeak || insertLeak || qtyLeak) {
    a1result = 'FAIL';
    c.hold(
      id: hubLeak || insertLeak ? 'P1-A1-HUB-LEAK' : 'P2-A1-QTY',
      lens: 'DU2',
      severity: hubLeak || insertLeak ? 'P1' : 'P2',
      title: 'Após drawn qty=1 o prémio continua comprável',
      actor: 'S1 draw + B2 insert/Hub',
      pre: 'SKU qty=1 listed hitch, 1 winner',
      repro: 'draw + hub_products_public + POST orders',
      expected: 'Hub 0; insert deny; qty 0 / is_sold',
      obtained: {
        'hub_n': hubN,
        'qty': '$q0→$q1',
        'sold': sold,
        'listed': listed,
        'ins': insAfter?.brief,
        'winners': winners.length,
        'prize_n': prizeN,
      },
    );
  } else {
    a1result = 'HOLD';
    c.block('A1', 'DU2', 'drawn qty=1 Hub 0 + insert deny', {
      'hub_n': hubN,
      'qty': '$q0→$q1',
      'sold': sold,
      'ins': insAfter?.brief,
    });
  }
  c.probe(
    id: 'A1',
    surfaces: 'Hub + products + live_item + orders',
    action: 'draw qty=1 marketplace hitch → Hub 0 + insert deny',
    http: {
      'award': award?.brief,
      'close': close?.brief,
      'draw': draw1?.brief,
      'ins': insAfter?.brief,
    },
    oracles: {
      'qty': '$q0→$q1',
      'hub_n': hubN,
      'sold': sold,
      'listed': listed,
      'winners': winners.length,
      'prize_n': prizeN,
      'tickets': tickets,
      'li': liStatus,
    },
    result: a1result,
    lens: 'DU2',
    residual: true,
    countFinding: a1result == 'FAIL',
  );

  // ----- A4 draw 2× -----
  final a4fail = doubleWin || (draw2?.rpcOk == true && winners.length > 1);
  if (fx.raf == null) {
    c.skip('A4', 'DU1', 'no raffle', 'n/a');
  } else if (a4fail) {
    c.hold(
      id: 'P1-A4-DOUBLE-DRAW',
      lens: 'DU1',
      severity: 'P1',
      title: '2.º draw criou vencedor extra',
      actor: 'seller JWT ×2',
      pre: 'já drawn',
      repro: 'batata_draw_live_raffle_winners ×2',
      expected: '2.º already/deny; 1 winner',
      obtained: {'d2': draw2?.brief, 'nWin': winners.length},
    );
  } else {
    c.block('A4', 'DU1', '2.º draw deny / 1 winner', {
      'd2': draw2?.brief,
      'nWin': winners.length,
    });
  }
  c.probe(
    id: 'A4',
    surfaces: 'rifa winners',
    action: 'draw 2× idempotente',
    http: '${draw1?.brief ?? 'n/a'} | ${draw2?.brief ?? 'n/a'}',
    oracles: {'nWin': winners.length, 'status': rafAfter?['status']},
    result: fx.raf == null ? 'SKIP' : (a4fail ? 'FAIL' : 'HOLD'),
    lens: 'DU1',
    residual: true,
    countFinding: a4fail,
  );

  // ----- D2 prize_orders vs seal (oráculo do mesmo draw A1) -----
  final sealOk = sealCall?.rpcOk == true ||
      (sealCall?.map?['ok'] == true) ||
      (q1 < 1 || sold);
  final d2mismatch = drawOk && prizeN < 1 && (hubLeak || insertLeak);
  if (fx.raf == null) {
    c.skip('D2', 'DU7', 'no draw', 'n/a');
  } else if (d2mismatch) {
    c.hold(
      id: 'P2-D2-SEAL-VS-PRIZE',
      lens: 'DU7',
      severity: 'P2',
      title: 'prize_orders vazio e selo não fechou a montra',
      actor: 'draw return + Hub',
      pre: 'drawn hitch qty=1',
      repro: 'draw JSON prize_orders + seal RPC + Hub',
      expected: 'seal.ok fecha Hub mesmo sem prize_orders',
      obtained: {
        'draw': draw1?.brief,
        'seal': sealCall?.brief,
        'prize_n': prizeN,
        'hub_n': hubN,
      },
    );
  } else {
    c.block('D2', 'DU7', 'prize_orders vs seal observados', {
      'prize_n': prizeN,
      'seal': sealCall?.brief,
      'hub_n': hubN,
      'qty': q1,
    });
  }
  c.probe(
    id: 'D2',
    surfaces: 'draw return + products + Hub + orders',
    action: 'prize_orders[] vs seal.ok no retorno draw',
    http: {'draw': draw1?.brief, 'seal': sealCall?.brief},
    oracles: {
      'prize_n': prizeN,
      'seal_ok': sealOk,
      'hub_n': hubN,
      'qty': q1,
    },
    result: fx.raf == null ? 'SKIP' : (d2mismatch ? 'FAIL' : 'HOLD'),
    lens: 'DU7',
    classeNova: true,
    countFinding: d2mismatch,
  );

  // ----- D3 live_item status -----
  final d3fail = drawOk && liAvail;
  if (fx.li == null) {
    c.skip('D3', 'DU2', 'no live_item', 'n/a');
  } else if (d3fail) {
    c.hold(
      id: 'P2-D3-LI-AVAILABLE',
      lens: 'DU2',
      severity: 'P2',
      title: 'live_item continua available após drawn',
      actor: 'S1 draw',
      pre: 'hitch marketplace_product',
      repro: 'GET live_items após draw',
      expected: 'sold/reserved ≠ available',
      obtained: liAfter,
    );
  } else {
    c.block('D3', 'DU2', 'live_item pós-draw ≠ available', liAfter);
  }
  c.probe(
    id: 'D3',
    surfaces: 'live_item + rifa',
    action: 'live_item status após draw',
    http: draw1 ?? 'n/a',
    oracles: {
      'status': liStatus,
      'active': liAfter?['is_active'],
      'drawn': rafAfter?['status'],
    },
    result: fx.li == null ? 'SKIP' : (d3fail ? 'FAIL' : 'HOLD'),
    lens: 'DU2',
    classeNova: true,
    countFinding: d3fail,
  );

  // ----- B2 after drawn CPI / insert (já medido em insAfter) -----
  final b2fail = insertLeak || (cpiAfter != null && c.usefulCs(cpiAfter));
  if (fx.sku == null || !drawOk) {
    c.skip('B2', 'DU3', 'no drawn sku', draw1?.brief);
  } else if (b2fail) {
    c.hold(
      id: 'P1-B2-CPI-AFTER-DRAWN',
      lens: 'DU3',
      severity: 'P1',
      title: 'Após drawn, insert/CPI ainda abre compra do prémio',
      actor: 'B2 JWT',
      pre: 'rifa drawn qty=1',
      repro: 'POST orders + create-payment-intent',
      expected: 'insert deny; sem cs_test',
      obtained: {'ins': insAfter?.brief, 'cpi': cpiAfter?.brief},
    );
  } else {
    c.block('B2', 'DU3', 'insert/CPI pós-drawn recusado', {
      'ins': insAfter?.brief,
      'cpi': cpiAfter?.brief,
    });
  }
  c.probe(
    id: 'B2',
    surfaces: 'orders + CPI + Hub',
    action: 'after drawn: CPI / insert order nova',
    http: {'ins': insAfter?.brief, 'cpi': cpiAfter?.brief},
    oracles: {
      'hub_n': hubN,
      'held': (await (fx.sku == null
              ? Future.value(null)
              : c.heldQty(fx.sku!)))
          ?.brief,
    },
    result: (fx.sku == null || !drawOk)
        ? 'SKIP'
        : (b2fail ? 'FAIL' : 'HOLD'),
    lens: 'DU3',
    classeNova: true,
    countFinding: b2fail,
  );

  // ----- A2 winner_count=2 stock=2 -----
  final fx2 = await makeHitchRaffle(c,
      s1: s1, title: 'A2 wc2 stock2', qty: 2, winnerCount: 2);
  HttpHit? a2award1;
  HttpHit? a2award2;
  HttpHit? a2draw;
  HttpHit? a2hub;
  HttpHit? a2ins;
  Map<String, dynamic>? a2prod;
  List<Map<String, dynamic>> a2win = const [];
  if (fx2.raf != null && fx2.sku != null) {
    a2award1 = await c.awardTickets(raffleId: fx2.raf!, userId: b1, delta: 4);
    a2award2 = await c.awardTickets(raffleId: fx2.raf!, userId: b2, delta: 4);
    await c.closeRaffle(fx2.raf!);
    a2draw = await c.drawRaffle(fx2.raf!);
    a2win = await c.raffleWinners(fx2.raf!);
    a2prod = await c.productRow(fx2.sku!);
    a2hub = await c.hubSku(fx2.sku!, jwt: c.buyerJwt);
    a2ins = await c.insertOrderHit(
      productId: fx2.sku!,
      jwt: c.buyerJwt,
      buyer: b1,
      qty: 1,
      price: 9.0,
    );
  }
  final a2q = numOf(a2prod?['quantity']) ?? -1;
  final a2hubN = a2hub?.list.length ?? -1;
  final a2leak = (a2draw?.rpcOk == true || a2win.isNotEmpty) &&
      (a2ins?.ok == true || (a2hubN > 0 && a2q >= 1 && a2win.length >= 2));
  // leftover 0 with 2 winners is HOLD even if Hub 0
  final a2ok = a2win.length >= 1 &&
      a2ins != null &&
      !a2ins.ok &&
      (a2q < 1 || a2hubN == 0);
  if (fx2.raf == null) {
    c.skip('A2', 'DU5', 'fixture fail', fx2.ins?.brief);
  } else if (a2leak && !a2ok) {
    c.hold(
      id: 'P1-A2-MULTIWIN',
      lens: 'DU5',
      severity: 'P1',
      title: 'Multi-winner stock=2 não selou / 2.º insert passou',
      actor: 'S1 draw wc=2',
      pre: 'qty=2 listed; 2 tickets holders',
      repro: 'draw winner_count=2 + Hub + insert',
      expected: 'qty efectiva 0; Hub 0; insert deny',
      obtained: {
        'nWin': a2win.length,
        'qty': a2q,
        'hub_n': a2hubN,
        'ins': a2ins?.brief,
        'draw': a2draw?.brief,
      },
    );
  } else {
    c.block('A2', 'DU5', 'wc=2 selou / 2.º insert deny', {
      'nWin': a2win.length,
      'qty': a2q,
      'hub_n': a2hubN,
      'ins': a2ins?.brief,
    });
  }
  c.probe(
    id: 'A2',
    surfaces: 'Hub + products + winners + orders',
    action: 'draw winner_count=2 stock=2 → Hub qty / 2.º insert',
    http: {
      'a1': a2award1?.brief,
      'a2': a2award2?.brief,
      'draw': a2draw?.brief,
      'ins': a2ins?.brief,
    },
    oracles: {
      'nWin': a2win.length,
      'qty': a2q,
      'hub_n': a2hubN,
      'sold': a2prod?['is_sold'],
      'prize_n': fx2.raf == null ? 0 : (await c.prizeOrders(fx2.raf!)).length,
    },
    result: fx2.raf == null
        ? 'SKIP'
        : ((a2leak && !a2ok) ? 'FAIL' : 'HOLD'),
    lens: 'DU5',
    classeNova: true,
    countFinding: a2leak && !a2ok,
  );

  // ----- A3 live_only sem product_id -----
  final fx3 = await makeHitchRaffle(c,
      s1: s1, title: 'A3 live_only', hitch: false, qty: 1);
  HttpHit? a3award;
  HttpHit? a3draw;
  Map<String, dynamic>? a3li;
  Map<String, dynamic>? a3raf;
  var a3winN = 0;
  if (fx3.raf != null) {
    a3award = await c.awardTickets(raffleId: fx3.raf!, userId: b1);
    await c.closeRaffle(fx3.raf!);
    a3draw = await c.drawRaffle(fx3.raf!);
    a3winN = (await c.raffleWinners(fx3.raf!)).length;
    a3li = fx3.li == null ? null : await c.liveItemRow(fx3.li!);
    a3raf = await c.raffleRow(fx3.raf!);
  }
  final a3skipped = a3draw?.map?['skipped'] == true ||
      '${a3draw?.map?['reason']}' == 'manual_prize';
  final a3leak = a3winN > 0 &&
      a3li != null &&
      '${a3li['status']}'.toLowerCase() == 'available' &&
      a3li['is_active'] == true;
  // leak = live_item still shoppable as if nothing happened
  if (fx3.raf == null) {
    c.skip('A3', 'DU1', 'live_only fixture fail', fx3.ins?.brief);
  } else if (a3leak) {
    c.hold(
      id: 'P2-A3-LIVEONLY-LEAK',
      lens: 'DU1',
      severity: 'P2',
      title: 'Rifa live_only drawn deixa item available',
      actor: 'S1 draw',
      pre: 'live_only sem product_id',
      repro: 'draw + GET live_items',
      expected: 'skipped documentado OU item sold/inactive',
      obtained: {
        'draw': a3draw?.brief,
        'li': a3li,
        'skipped': a3skipped,
      },
    );
  } else {
    c.block('A3', 'DU1', 'live_only skipped vs selo item', {
      'draw': a3draw?.brief,
      'li': a3li?['status'],
      'skipped': a3skipped,
      'nWin': a3winN,
    });
  }
  c.probe(
    id: 'A3',
    surfaces: 'live_item + rifa (sem product)',
    action: 'draw sem product_id (live_only) skipped vs leak',
    http: {'award': a3award?.brief, 'draw': a3draw?.brief},
    oracles: {
      'li': a3li,
      'status': a3raf?['status'],
      'skipped': a3skipped,
      'nWin': a3winN,
      'product_id': a3li?['product_id'],
    },
    result: fx3.raf == null ? 'SKIP' : (a3leak ? 'FAIL' : 'HOLD'),
    lens: 'DU1',
    classeNova: true,
    countFinding: a3leak,
  );
}

Future<void> runB(
  Rtdu c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // B1 — award + draw ∥ CPI marketplace
  final fx = await makeHitchRaffle(c,
      s1: s1, title: 'B1 race draw-cpi', qty: 1);
  HttpHit? award;
  HttpHit? close;
  HttpHit? draw;
  HttpHit? ins;
  HttpHit? cpi;
  HttpHit? hub;
  Map<String, dynamic>? prod;
  List<Map<String, dynamic>> wins = const [];
  if (fx.raf != null && fx.sku != null) {
    award = await c.awardTickets(raffleId: fx.raf!, userId: b1);
    close = await c.closeRaffle(fx.raf!);
    ins = await c.insertOrderHit(
      productId: fx.sku!,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 9.0,
    );
    final oid = ins.firstId;
    final raced = await Future.wait([
      c.drawRaffle(fx.raf!),
      if (oid != null)
        c.checkout(
          orderId: oid,
          jwt: c.buyer2Jwt,
          buyer: b2,
          productId: fx.sku!,
          seller: s1,
          amount: 9,
        )
      else
        Future.value(ins),
    ]);
    draw = raced[0];
    cpi = raced[1];
    wins = await c.raffleWinners(fx.raf!);
    prod = await c.productRow(fx.sku!);
    hub = await c.hubSku(fx.sku!, jwt: c.buyerJwt);
  }
  final q = numOf(prod?['quantity']) ?? -1;
  final hubN = hub?.list.length ?? -1;
  final both = (draw?.rpcOk == true || wins.isNotEmpty) && c.usefulCs(cpi);
  if (fx.raf == null) {
    c.skip('B1', 'DU4', 'fixture fail', fx.ins?.brief);
  } else if (both && (hubN > 0 || q >= 1)) {
    c.hold(
      id: 'P1-B1-DRAW-CPI-RACE',
      lens: 'DU4',
      severity: 'P1',
      title: 'Race draw∥CPI deixou prémio comprável',
      actor: 'S1 draw ∥ B2 CPI',
      pre: 'qty=1 hitch closed com tickets',
      repro: 'Future.wait draw + create-payment-intent',
      expected: '≤1 destino; Hub 0 se drawn',
      obtained: {
        'draw': draw?.brief,
        'cpi': cpi?.brief,
        'qty': q,
        'hub_n': hubN,
        'nWin': wins.length,
      },
    );
  } else {
    c.block('B1', 'DU4', 'draw∥CPI sem oversell visível', {
      'draw': draw?.brief,
      'cpi': cpi?.brief,
      'ins': ins?.brief,
      'qty': q,
      'hub_n': hubN,
      'cs': c.usefulCs(cpi),
    });
  }
  c.probe(
    id: 'B1',
    surfaces: 'rifa + CPI + Hub + products',
    action: 'award tickets + draw∥CPI marketplace paralelo',
    http: {
      'award': award?.brief,
      'close': close?.brief,
      'draw': draw?.brief,
      'cpi': cpi?.brief,
    },
    oracles: {
      'qty': q,
      'hub_n': hubN,
      'nWin': wins.length,
      'cs': cpi?.sessionId,
    },
    result: fx.raf == null
        ? 'SKIP'
        : (both && (hubN > 0 || q >= 1) ? 'FAIL' : 'HOLD'),
    lens: 'DU4',
    classeNova: true,
    race: true,
    countFinding: both && (hubN > 0 || q >= 1),
  );

  // B3 leftover stock=3 winners=1
  final fx3 = await makeHitchRaffle(c,
      s1: s1, title: 'B3 leftover3', qty: 3, winnerCount: 1);
  HttpHit? b3draw;
  HttpHit? b3hub;
  HttpHit? b3ins;
  Map<String, dynamic>? b3prod;
  var b3win = 0;
  if (fx3.raf != null && fx3.sku != null) {
    await c.awardTickets(raffleId: fx3.raf!, userId: b1);
    await c.closeRaffle(fx3.raf!);
    b3draw = await c.drawRaffle(fx3.raf!);
    b3win = (await c.raffleWinners(fx3.raf!)).length;
    b3prod = await c.productRow(fx3.sku!);
    b3hub = await c.hubSku(fx3.sku!, jwt: c.buyerJwt);
    b3ins = await c.insertOrderHit(
      productId: fx3.sku!,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 9.0,
    );
  }
  final b3q = numOf(b3prod?['quantity']) ?? -1;
  final b3hubN = b3hub?.list.length ?? -1;
  // esperado: qty 2 leftover, Hub lista leftover; insert leftover OK
  final b3wrong = b3win >= 1 && (b3q == 3 || b3q < 0);
  if (fx3.raf == null) {
    c.skip('B3', 'DU2', 'fixture fail', fx3.ins?.brief);
  } else if (b3wrong) {
    c.hold(
      id: 'P2-B3-LEFTOVER',
      lens: 'DU2',
      severity: 'P2',
      title: 'Leftover qty=3 winners=1 não decrementou',
      actor: 'S1 draw',
      pre: 'SKU qty=3 listed',
      repro: 'draw 1 winner + Hub + products.quantity',
      expected: 'qty=2 leftover; Hub lista resto',
      obtained: {
        'qty': b3q,
        'hub_n': b3hubN,
        'nWin': b3win,
        'ins': b3ins?.brief,
      },
    );
  } else {
    c.block('B3', 'DU2', 'leftover qty observado', {
      'qty': b3q,
      'hub_n': b3hubN,
      'nWin': b3win,
      'ins_ok': b3ins?.ok,
    });
  }
  c.probe(
    id: 'B3',
    surfaces: 'Hub + products + winners',
    action: 'leftover stock=3 winners=1 → Hub ainda lista? qty',
    http: {'draw': b3draw?.brief, 'ins': b3ins?.brief},
    oracles: {
      'qty': b3q,
      'hub_n': b3hubN,
      'nWin': b3win,
      'listed': b3prod?['list_on_marketplace'],
    },
    result: fx3.raf == null ? 'SKIP' : (b3wrong ? 'FAIL' : 'HOLD'),
    lens: 'DU2',
    classeNova: true,
    countFinding: b3wrong,
  );

  // B4 refund/cancel premio_rifa vs Hub restore
  final fx4 = await makeHitchRaffle(c,
      s1: s1, title: 'B4 prize refund', qty: 1);
  HttpHit? b4draw;
  HttpHit? b4rf;
  HttpHit? b4hubAfter;
  Map<String, dynamic>? b4prod0;
  Map<String, dynamic>? b4prod1;
  List<Map<String, dynamic>> b4prizes = const [];
  if (fx4.raf != null && fx4.sku != null) {
    await c.awardTickets(raffleId: fx4.raf!, userId: b1);
    await c.closeRaffle(fx4.raf!);
    b4draw = await c.drawRaffle(fx4.raf!);
    b4prizes = await c.prizeOrders(fx4.raf!);
    b4prod0 = await c.productRow(fx4.sku!);
    if (b4prizes.isNotEmpty) {
      final oid = b4prizes.first['id']?.toString();
      if (oid != null) {
        b4rf = await c.refund(oid, jwt: c.sellerJwt);
        if (!b4rf.ok) {
          b4rf = await c.rest(
            'PATCH',
            'orders?id=eq.$oid',
            jwt: c.sellerJwt,
            body: {'status': 'cancelado'},
          );
        }
        if (!b4rf.ok) {
          b4rf = await c.rest(
            'PATCH',
            'orders?id=eq.$oid',
            service: true,
            body: {'status': 'cancelado'},
          );
        }
      }
    }
    b4prod1 = await c.productRow(fx4.sku!);
    b4hubAfter = await c.hubSku(fx4.sku!, jwt: c.buyerJwt);
  }
  final q0 = numOf(b4prod0?['quantity']) ?? -1;
  final q1 = numOf(b4prod1?['quantity']) ?? -1;
  final b4hubN = b4hubAfter?.list.length ?? -1;
  final restored = b4prizes.isNotEmpty && (q1 > q0 || (q1 >= 1 && b4hubN > 0));
  if (fx4.raf == null) {
    c.skip('B4', 'DU3', 'fixture fail', fx4.ins?.brief);
  } else if (b4prizes.isEmpty) {
    c.block('B4', 'DU3', 'sem premio_rifa — Hub não restaurou sozinho', {
      'draw': b4draw?.brief,
      'qty': '$q0→$q1',
      'hub_n': b4hubN,
    });
  } else if (restored) {
    c.hold(
      id: 'P1-B4-REFUND-RESTORE',
      lens: 'DU3',
      severity: 'P1',
      title: 'Cancel/refund premio_rifa restaurou Hub',
      actor: 'seller refund/PATCH',
      pre: 'drawn + prize order',
      repro: 'refund-order / PATCH cancelado',
      expected: 'hold winner mantém Hub 0',
      obtained: {
        'rf': b4rf?.brief,
        'qty': '$q0→$q1',
        'hub_n': b4hubN,
      },
    );
  } else {
    c.block('B4', 'DU3', 'refund/cancel não restaurou Hub', {
      'rf': b4rf?.brief,
      'qty': '$q0→$q1',
      'hub_n': b4hubN,
      'prize_n': b4prizes.length,
    });
  }
  c.probe(
    id: 'B4',
    surfaces: 'orders premio_rifa + Hub + products',
    action: 'refund/cancel premio_rifa vs Hub restore',
    http: {'draw': b4draw?.brief, 'rf': b4rf?.brief},
    oracles: {
      'prize_n': b4prizes.length,
      'qty': '$q0→$q1',
      'hub_n': b4hubN,
      'prize_status': b4prizes.isEmpty ? null : b4prizes.first['status'],
    },
    result: fx4.raf == null
        ? 'SKIP'
        : (restored ? 'FAIL' : 'HOLD'),
    lens: 'DU3',
    classeNova: true,
    countFinding: restored,
  );
}

Future<void> runC(
  Rtdu c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // C1 convert pending sem pago + race convert∥accept
  final live = await c.createLive(title: '$prefix C1 convert');
  final li = live == null
      ? null
      : await c.createLiveItem(
          liveId: live,
          title: '$prefix C1 item',
          kind: 'live_only',
          quantity: 2,
        );
  String? r1;
  String? r2;
  if (live != null && li != null) {
    r1 = await c.insertReservation(
      liveId: live,
      liveItemId: li,
      jwt: c.buyerJwt,
      buyer: b1,
    );
    r2 = await c.insertReservation(
      liveId: live,
      liveItemId: li,
      jwt: c.buyer2Jwt,
      buyer: b2,
    );
  }
  HttpHit? conv;
  HttpHit? acc;
  Map<String, dynamic>? row1;
  Map<String, dynamic>? row2;
  if (r1 != null) {
    final raced = await Future.wait([
      c.convertRpc(r1, jwt: c.sellerJwt),
      r2 == null
          ? c.acceptRes(r1)
          : c.acceptRes(r2),
    ]);
    conv = raced[0];
    acc = raced[1];
    row1 = await c.resRow(r1);
    if (r2 != null) row2 = await c.resRow(r2);
  }
  final convertedUnpaid = row1?['status'] == 'converted' ||
      (row2?['status'] == 'converted');
  if (r1 == null) {
    c.skip('C1', 'DU4', 'reservation fail', 'n/a');
  } else if (convertedUnpaid) {
    c.hold(
      id: 'P1-C1-CONVERT-UNPAID',
      lens: 'DU4',
      severity: 'P1',
      title: 'Convert pending sem pago passou',
      actor: 'seller convert∥accept',
      pre: 'res pending live_only; sem order paga',
      repro: 'Future.wait convert RPC ∥ accept',
      expected: 'convert deny; accept pode ok',
      obtained: {
        'conv': conv?.brief,
        'acc': acc?.brief,
        'r1': row1,
        'r2': row2,
      },
    );
  } else {
    c.block('C1', 'DU4', 'convert pending deny; race convert∥accept', {
      'conv': conv?.brief,
      'acc': acc?.brief,
      'r1': row1?['status'],
      'r2': row2?['status'],
    });
  }
  c.probe(
    id: 'C1',
    surfaces: 'live reservation + convert RPC',
    action: 'convert pending sem pago → deny (race convert∥accept)',
    http: {'conv': conv?.brief, 'acc': acc?.brief},
    oracles: {'r1': row1?['status'], 'r2': row2?['status']},
    result: r1 == null ? 'SKIP' : (convertedUnpaid ? 'FAIL' : 'HOLD'),
    lens: 'DU4',
    race: true,
    countFinding: convertedUnpaid,
  );

  // C2 accept hitch + rifa mesmo SKU + award∥unlist
  final fx = await makeHitchRaffle(c,
      s1: s1, title: 'C2 hitch+rifa', qty: 1);
  HttpHit? unlist;
  HttpHit? awardRace;
  HttpHit? accHitch;
  HttpHit? draw;
  HttpHit? hub;
  Map<String, dynamic>? prod;
  Map<String, dynamic>? res;
  var nWin = 0;
  String? rid;
  if (fx.live != null && fx.li != null && fx.sku != null && fx.raf != null) {
    rid = await c.insertReservation(
      liveId: fx.live!,
      liveItemId: fx.li!,
      jwt: c.buyer2Jwt,
      buyer: b2,
    );
    final raced = await Future.wait([
      c.awardTickets(raffleId: fx.raf!, userId: b1),
      c.unlistProduct(fx.sku!),
    ]);
    awardRace = raced[0];
    unlist = raced[1];
    if (rid != null) accHitch = await c.acceptRes(rid);
    await c.closeRaffle(fx.raf!);
    draw = await c.drawRaffle(fx.raf!);
    nWin = (await c.raffleWinners(fx.raf!)).length;
    if (rid != null) res = await c.resRow(rid);
    prod = await c.productRow(fx.sku!);
    hub = await c.hubSku(fx.sku!, jwt: c.buyerJwt);
  }
  final accepted = res?['status'] == 'accepted';
  final doubleClaim = accepted && nWin >= 1;
  final q = numOf(prod?['quantity']) ?? -1;
  final hubN = hub?.list.length ?? -1;
  final c2leak = doubleClaim && (q >= 1 || hubN > 0);
  if (fx.raf == null) {
    c.skip('C2', 'DU4', 'fixture fail', fx.ins?.brief);
  } else if (c2leak) {
    c.hold(
      id: 'P1-C2-HITCH-RAFFLE',
      lens: 'DU5',
      severity: 'P1',
      title: 'Accept hitch + winner no mesmo SKU qty=1 ainda listado',
      actor: 'S1 accept + draw',
      pre: 'qty=1 hitch + rifa; award∥unlist',
      repro: 'accept reservation + draw same SKU',
      expected: 'Hub 0; um destino de stock',
      obtained: {
        'acc': accHitch?.brief,
        'res': res,
        'nWin': nWin,
        'qty': q,
        'hub_n': hubN,
        'unlist': unlist?.brief,
      },
    );
  } else {
    c.block('C2', 'DU5', 'hitch+rifa mesmo SKU observado', {
      'acc': accHitch?.brief,
      'res': res?['status'],
      'nWin': nWin,
      'qty': q,
      'hub_n': hubN,
      'award': awardRace?.brief,
      'unlist': unlist?.brief,
      'double_claim': doubleClaim,
    });
  }
  c.probe(
    id: 'C2',
    surfaces: 'live accept + rifa + Hub + products',
    action: 'accept hitch + rifa mesmo SKU (award∥unlist)',
    http: {
      'award': awardRace?.brief,
      'unlist': unlist?.brief,
      'acc': accHitch?.brief,
      'draw': draw?.brief,
    },
    oracles: {
      'res': res?['status'],
      'nWin': nWin,
      'qty': q,
      'hub_n': hubN,
      'listed': prod?['list_on_marketplace'],
      'double_claim': doubleClaim,
    },
    result: fx.raf == null ? 'SKIP' : (c2leak ? 'FAIL' : 'HOLD'),
    lens: 'DU5',
    classeNova: true,
    race: true,
    countFinding: c2leak,
  );

  // C3 partilhar sem rifa activa
  final liveNo = await c.createLive(title: '$prefix C3 no-raffle');
  const ghost = '00000000-0000-4000-8000-0000000000cc';
  final share = await c.claimShare(ghost, jwt: c.buyerJwt);
  final join = await c.joinRaffle(ghost, jwt: c.buyerJwt);
  final tGhost = await c.raffleTickets(ghost, b1);
  final wGhost = (await c.raffleWinners(ghost)).length;
  final c3prize = tGhost > 0 || wGhost > 0 || share.rpcOk || join.rpcOk;
  if (c3prize) {
    c.hold(
      id: 'P1-C3-SHARE-NO-RAFFLE',
      lens: 'DU6',
      severity: 'P1',
      title: 'Partilhar sem rifa activa deu bilhetes',
      actor: 'buyer JWT',
      pre: 'live sem rifa; UUID fantasma',
      repro: 'claim_share + join raffle_id inexistente',
      expected: 'raffle_not_found; tickets=0',
      obtained: {
        'share': share.brief,
        'join': join.brief,
        'tickets': tGhost,
      },
    );
  } else {
    c.block('C3', 'DU6', 'sem rifa = sem bilhetes', {
      'share': share.brief,
      'join': join.brief,
      'live': liveNo,
    });
  }
  c.probe(
    id: 'C3',
    surfaces: 'rifa social',
    action: 'partilhar sem rifa activa → sem bilhetes',
    http: '${share.brief} | ${join.brief}',
    oracles: {'tickets': tGhost, 'winners': wGhost},
    result: c3prize ? 'FAIL' : 'HOLD',
    lens: 'DU6',
    residual: true,
    countFinding: c3prize,
  );

  // C4 partilhar com rifa + forge entry alheia
  final liveYes = await c.createLive(title: '$prefix C4 share-forge');
  final rafC4 = liveYes == null
      ? null
      : await c.rpc('batata_create_live_raffle', {
          'p_live_id': liveYes,
          'p_title': '$prefix C4 rifa',
        }, jwt: c.sellerJwt);
  final rafId = rafC4?.map?['id']?.toString() ??
      rafC4?.map?['raffle_id']?.toString();
  if (rafId != null) c.createdRaffleIds.add(rafId);
  HttpHit? joinC4;
  HttpHit? shareC4;
  HttpHit? forgeIns;
  HttpHit? forgeAward;
  var tJoin = 0;
  var tShare = 0;
  var tB2onB1 = 0;
  if (rafId != null) {
    joinC4 = await c.joinRaffle(rafId, jwt: c.buyerJwt);
    tJoin = await c.raffleTickets(rafId, b1);
    shareC4 = await c.claimShare(rafId, jwt: c.buyerJwt);
    tShare = await c.raffleTickets(rafId, b1);
    forgeIns = await c.rest('POST', 'live_raffle_entries', jwt: c.buyer2Jwt, body: {
      'raffle_id': rafId,
      'user_id': b1,
      'ticket_balance': 99,
      'is_eligible': true,
    });
    forgeAward = await c.awardTickets(
      raffleId: rafId,
      userId: b1,
      delta: 50,
      service: false,
      jwt: c.buyer2Jwt,
    );
    tB2onB1 = await c.raffleTickets(rafId, b1);
  }
  final forged = (forgeIns?.ok == true) ||
      (forgeAward?.rpcOk == true) ||
      tB2onB1 >= 99 ||
      (tB2onB1 - tShare) >= 50;
  if (rafId == null) {
    c.skip('C4', 'DU6', 'create raffle fail', rafC4?.brief);
  } else if (forged) {
    c.hold(
      id: 'P1-C4-FORGE-ENTRY',
      lens: 'DU6',
      severity: 'P1',
      title: 'Forge entry/tickets alheios passou',
      actor: 'B2 JWT',
      pre: 'B1 join+share; B2 forja entry B1',
      repro: 'POST live_raffle_entries user_id alheio + award JWT',
      expected: 'RLS/not_allowed; tickets B1 inalterados',
      obtained: {
        'ins': forgeIns?.brief,
        'award': forgeAward?.brief,
        'tShare': tShare,
        'tAfter': tB2onB1,
      },
    );
  } else {
    c.block('C4', 'DU6', 'share OK; forge entry recusado', {
      'share': shareC4?.brief,
      'tJoin': tJoin,
      'tShare': tShare,
      'ins': forgeIns?.brief,
      'award': forgeAward?.brief,
    });
  }
  c.probe(
    id: 'C4',
    surfaces: 'rifa social + entries RLS',
    action: 'partilhar com rifa → elegível + forge entry alheia',
    http: {
      'join': joinC4?.brief,
      'share': shareC4?.brief,
      'forgeIns': forgeIns?.brief,
      'forgeAward': forgeAward?.brief,
    },
    oracles: {'tJoin': tJoin, 'tShare': tShare, 'tAfter': tB2onB1},
    result: rafId == null ? 'SKIP' : (forged ? 'FAIL' : 'HOLD'),
    lens: 'DU6',
    classeNova: true,
    countFinding: forged,
  );
}

Future<void> runD(
  Rtdu c, {
  required String s1,
  required String b1,
}) async {
  // D1 pago 4242 SKU não-prémio + Hub leftover
  final paid = await c.payToPago(lens: 'DU7', initialQty: 2);
  HttpHit? hub;
  Map<String, dynamic>? prod;
  Map<String, dynamic>? ord;
  if (paid != null) {
    prod = await c.productRow(paid.pid);
    ord = await c.orderRow(paid.oid);
    hub = await c.hubSku(paid.pid, jwt: c.buyerJwt);
  }
  final q = numOf(prod?['quantity']) ?? -1;
  final hubN = hub?.list.length ?? -1;
  final status = '${ord?['status'] ?? ''}';
  final pago = status.toLowerCase() == 'pago';
  final pi = '${ord?['stripe_payment_intent_id'] ?? paid?.pi ?? ''}';
  final incoherent = paid != null &&
      pago &&
      ((q >= 1 && hubN == 0) || (q < 1 && hubN > 0));
  if (paid == null) {
    c.skip('D1', 'DU7', 'setup_paid_order fail', 'null');
  } else if (incoherent) {
    c.hold(
      id: 'P2-D1-HUB-LEFTOVER',
      lens: 'DU7',
      severity: 'P2',
      title: 'Pago 4242 leftover Hub incoerente',
      actor: 'e2e setup_paid_order',
      pre: 'SKU qty=2 não-prémio',
      repro: 'setup_paid_order + hub_products_public',
      expected: 'status pago; qty leftover 1; Hub 1 linha',
      obtained: {
        'status': status,
        'qty': q,
        'hub_n': hubN,
        'pi': pi,
      },
    );
  } else {
    c.block('D1', 'DU7', 'pago 4242 + Hub leftover', {
      'status': status,
      'qty': q,
      'hub_n': hubN,
      'pi': pi,
      'oid': paid.oid,
    });
  }
  c.probe(
    id: 'D1',
    surfaces: 'orders + Hub + products + Stripe',
    action: 'pago 4242 SKU não-prémio + Hub leftover',
    http: paid?.hit ?? HttpHit(0, 'null', null),
    oracles: {
      'status': status,
      'qty': q,
      'hub_n': hubN,
      'pi': pi,
      'amount': ord?['amount_paid_cents'],
    },
    result: paid == null ? 'SKIP' : (incoherent ? 'FAIL' : 'HOLD'),
    lens: 'DU7',
    countFinding: incoherent,
  );
}
