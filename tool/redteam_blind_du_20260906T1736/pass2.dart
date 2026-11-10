/// RED TEAM CEGO DU pass2 — reteste draws com rifa AINDA activa (award antes do close).
/// Pass1: ends_at no passado → award raffle_ended → no_participants (fixture, não produto).
/// Staging only. NÃO corrigir.
import 'dart:io';

import '_rtdu.dart';

String futureIso() => DateTime.now()
    .toUtc()
    .add(const Duration(hours: 2))
    .toIso8601String();

Future<({
  String? sku,
  String? live,
  String? li,
  String? raf,
  HttpHit? ins,
})> makeLiveRaffle(
  Rtdu c, {
  required String s1,
  required String title,
  int qty = 1,
  int winnerCount = 1,
  bool hitch = true,
}) async {
  String? sku;
  if (hitch) {
    sku = await c.createProduct(
      title: '$prefix P2 $title',
      qty: qty,
      listed: true,
      live: true,
      price: 9.0,
    );
  }
  final live = await c.createLive(title: '$prefix P2 $title');
  String? li;
  if (live != null) {
    li = hitch && sku != null
        ? await c.createLiveItem(
            liveId: live,
            title: '$prefix P2 $title-li',
            kind: 'marketplace_product',
            productId: sku,
          )
        : await c.createLiveItem(
            liveId: live,
            title: '$prefix P2 $title-li',
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
      'title': '$prefix P2 $title',
      'status': 'active',
      'winner_count': winnerCount,
      if (li != null) 'live_item_id': li,
      'ends_at': futureIso(),
    });
    raf = ins.firstId;
    if (raf != null) c.createdRaffleIds.add(raf);
  }
  return (sku: sku, live: live, li: li, raf: raf, ins: ins);
}

Future<int> seedTickets(
  Rtdu c, {
  required String raf,
  required String user,
  String? jwt,
  int extra = 4,
}) async {
  final join = await c.joinRaffle(raf, jwt: jwt ?? c.buyerJwt);
  c.note('p2.join', 'join $user', join.brief, lens: 'DU1');
  var t = await c.raffleTickets(raf, user);
  if (t < 1) {
    final aw = await c.awardTickets(raffleId: raf, userId: user, delta: extra);
    c.note('p2.award', 'award $user', aw.brief, lens: 'DU1');
    t = await c.raffleTickets(raf, user);
  } else if (extra > 0) {
    await c.awardTickets(raffleId: raf, userId: user, delta: extra);
    t = await c.raffleTickets(raf, user);
  }
  return t;
}

Future<void> main() async {
  final c = Rtdu.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final s1 = c.sellerId!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;
  await c.restoreSeller1Published();

  try {
    await runDraws(c, s1: s1, b1: b1, b2: b2);
  } finally {
    await c.endAllCreatedLives();
    await c.restoreSeller1Published();
  }

  await dumpJson('${outDir()}/pass2.json', {
    'auditor': 'REDTEAM_BLIND_DU_RAFFLE_HUB_POS_DNDS_v1',
    'pass': 2,
    'prefix': prefix,
    'probes': c.probes,
    'findings': c.findings,
    'blocked': c.blocked,
    'skipped': c.skipped,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
    'created': {
      'products': c.createdProductIds,
      'raffles': c.createdRaffleIds,
      'lives': c.createdLiveIds,
      'orders': c.createdOrderIds,
    },
  });
  stdout.writeln('WROTE pass2.json probes=${c.probes.length} '
      'findings=${c.findings.length}');
}

Future<void> runDraws(
  Rtdu c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // A1 + A4 + A5 + B2 + D2 + D3 on one qty=1 hitch
  final fx = await makeLiveRaffle(c, s1: s1, title: 'A1 hitch1');
  HttpHit? close;
  HttpHit? drawB;
  HttpHit? draw1;
  HttpHit? draw2;
  HttpHit? hub;
  HttpHit? ins;
  HttpHit? cpi;
  HttpHit? seal;
  Map<String, dynamic>? prod0;
  Map<String, dynamic>? prod1;
  Map<String, dynamic>? li;
  Map<String, dynamic>? raf;
  List<Map<String, dynamic>> wins = const [];
  List<Map<String, dynamic>> prizes = const [];
  var tickets = 0;
  if (fx.raf != null && fx.sku != null) {
    tickets = await seedTickets(c, raf: fx.raf!, user: b1, extra: 4);
    prod0 = await c.productRow(fx.sku!);
    close = await c.closeRaffle(fx.raf!);
    drawB = await c.drawRaffle(fx.raf!, jwt: c.buyerJwt);
    draw1 = await c.drawRaffle(fx.raf!);
    draw2 = await c.drawRaffle(fx.raf!);
    wins = await c.raffleWinners(fx.raf!);
    prizes = await c.prizeOrders(fx.raf!);
    prod1 = await c.productRow(fx.sku!);
    li = fx.li == null ? null : await c.liveItemRow(fx.li!);
    raf = await c.raffleRow(fx.raf!);
    hub = await c.hubSku(fx.sku!, jwt: c.buyerJwt);
    seal = await c.sealPrize(fx.raf!);
    ins = await c.insertOrderHit(
      productId: fx.sku!,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 9.0,
    );
    if (ins.ok && ins.firstId != null) {
      cpi = await c.checkout(
        orderId: ins.firstId!,
        jwt: c.buyer2Jwt,
        buyer: b2,
        productId: fx.sku!,
        seller: s1,
        amount: 9,
      );
    }
  }

  final drawOk = '${raf?['status']}' == 'drawn' || wins.isNotEmpty;
  final hubN = hub?.list.length ?? -1;
  final q0 = numOf(prod0?['quantity']) ?? -1;
  final q1 = numOf(prod1?['quantity']) ?? -1;
  final sold = prod1?['is_sold'] == true;
  final listed = prod1?['list_on_marketplace'] == true;
  final liSt = '${li?['status'] ?? ''}';
  final buyerDrew = drawB?.rpcOk == true;
  final hubLeak = drawOk && hubN > 0;
  final insertLeak = drawOk && ins != null && ins.ok;
  final qtyLeak = drawOk && q1 >= 1 && !sold;
  final a1fail = drawOk && (hubLeak || insertLeak || qtyLeak);
  final a1drawFail = fx.raf != null && tickets >= 1 && !drawOk;

  if (buyerDrew) {
    c.hold(
      id: 'P1-A5-BUYER-DRAW',
      lens: 'DU6',
      severity: 'P1',
      title: 'JWT comprador sorteou rifa closed com tickets',
      actor: 'buyer JWT',
      pre: 'closed + tickets≥1',
      repro: 'batata_draw_live_raffle_winners JWT buyer',
      expected: 'not_allowed',
      obtained: drawB?.brief,
    );
  } else {
    c.block('A5', 'DU6', 'buyer draw recusado (pass2 ripe)', drawB?.brief);
  }
  c.probe(
    id: 'A5',
    surfaces: 'rifa RPC',
    action: 'JWT buyer draw em rifa closed com tickets',
    http: drawB ?? 'n/a',
    oracles: {'tickets': tickets, 'buyer_ok': buyerDrew, 'nWin': wins.length},
    result: buyerDrew ? 'FAIL' : 'HOLD',
    lens: 'DU6',
    countFinding: buyerDrew,
  );

  if (a1drawFail) {
    c.hold(
      id: 'P2-A1-DRAW-FAIL',
      lens: 'DU1',
      severity: 'P2',
      title: 'Draw qty=1 hitch não fechou drawn (pass2, tickets ok)',
      actor: 'seller JWT',
      pre: 'active→close tickets=$tickets',
      repro: 'close + draw',
      expected: 'drawn',
      obtained: {
        'close': close?.brief,
        'draw': draw1?.brief,
        'status': raf?['status'],
        'tickets': tickets,
      },
    );
  } else if (a1fail) {
    c.hold(
      id: hubLeak || insertLeak ? 'P1-A1-HUB-LEAK' : 'P2-A1-QTY',
      lens: 'DU2',
      severity: hubLeak || insertLeak ? 'P1' : 'P2',
      title: 'Após drawn qty=1 o prémio continua comprável',
      actor: 'S1 draw + B2 insert/Hub',
      pre: 'SKU qty=1 hitch, winner',
      repro: 'draw + hub_products_public + POST orders',
      expected: 'Hub 0; insert deny; qty 0 / is_sold',
      obtained: {
        'hub_n': hubN,
        'qty': '$q0→$q1',
        'sold': sold,
        'listed': listed,
        'ins': ins?.brief,
        'nWin': wins.length,
        'prize_n': prizes.length,
        'li': liSt,
      },
    );
  } else {
    c.block('A1', 'DU2', 'drawn qty=1 Hub/insert/qty', {
      'hub_n': hubN,
      'qty': '$q0→$q1',
      'sold': sold,
      'ins': ins?.brief,
      'draw': draw1?.brief,
      'nWin': wins.length,
    });
  }
  c.probe(
    id: 'A1',
    surfaces: 'Hub + products + live_item + orders',
    action: 'draw qty=1 marketplace hitch → Hub 0 + insert deny',
    http: {
      'close': close?.brief,
      'draw': draw1?.brief,
      'ins': ins?.brief,
    },
    oracles: {
      'tickets': tickets,
      'qty': '$q0→$q1',
      'hub_n': hubN,
      'sold': sold,
      'listed': listed,
      'nWin': wins.length,
      'prize_n': prizes.length,
      'li': liSt,
      'status': raf?['status'],
    },
    result: a1drawFail || a1fail ? 'FAIL' : 'HOLD',
    lens: 'DU2',
    residual: true,
    countFinding: a1drawFail || a1fail,
  );

  final a4fail = wins.length > 1 || (draw2?.rpcOk == true && wins.length > 1);
  if (a4fail) {
    c.hold(
      id: 'P1-A4-DOUBLE-DRAW',
      lens: 'DU1',
      severity: 'P1',
      title: '2.º draw criou vencedor extra',
      actor: 'seller ×2',
      pre: 'já drawn',
      repro: 'draw ×2',
      expected: '1 winner; 2.º deny',
      obtained: {'d2': draw2?.brief, 'nWin': wins.length},
    );
  } else {
    c.block('A4', 'DU1', '2.º draw deny', {
      'd2': draw2?.brief,
      'nWin': wins.length,
      'status': raf?['status'],
    });
  }
  c.probe(
    id: 'A4',
    surfaces: 'rifa winners',
    action: 'draw 2× idempotente',
    http: '${draw1?.brief} | ${draw2?.brief}',
    oracles: {'nWin': wins.length, 'status': raf?['status']},
    result: a4fail ? 'FAIL' : 'HOLD',
    lens: 'DU1',
    residual: true,
    countFinding: a4fail,
  );

  final d2mismatch = drawOk && prizes.isEmpty && (hubLeak || insertLeak);
  c.probe(
    id: 'D2',
    surfaces: 'draw return + products + Hub + orders',
    action: 'prize_orders[] vs seal.ok',
    http: {'draw': draw1?.brief, 'seal': seal?.brief},
    oracles: {
      'prize_n': prizes.length,
      'seal': seal?.brief,
      'hub_n': hubN,
      'qty': q1,
      'draw_ok': drawOk,
    },
    result: d2mismatch ? 'FAIL' : 'HOLD',
    lens: 'DU7',
    classeNova: true,
    countFinding: d2mismatch,
  );
  if (d2mismatch) {
    c.hold(
      id: 'P2-D2-SEAL-VS-PRIZE',
      lens: 'DU7',
      severity: 'P2',
      title: 'prize_orders vazio e selo não fechou a montra',
      actor: 'draw + Hub',
      pre: 'drawn hitch qty=1',
      repro: 'prize_orders + seal + Hub',
      expected: 'seal fecha Hub mesmo sem prize_orders',
      obtained: {
        'prize_n': prizes.length,
        'hub_n': hubN,
        'seal': seal?.brief,
      },
    );
  } else {
    c.block('D2', 'DU7', 'prize_orders vs seal', {
      'prize_n': prizes.length,
      'hub_n': hubN,
      'seal': seal?.brief,
    });
  }

  final d3fail = drawOk && liSt.toLowerCase() == 'available';
  if (d3fail) {
    c.hold(
      id: 'P2-D3-LI-AVAILABLE',
      lens: 'DU2',
      severity: 'P2',
      title: 'live_item continua available após drawn',
      actor: 'S1 draw',
      pre: 'hitch marketplace',
      repro: 'GET live_items',
      expected: 'sold/reserved ≠ available',
      obtained: li,
    );
  } else {
    c.block('D3', 'DU2', 'live_item pós-draw', li);
  }
  c.probe(
    id: 'D3',
    surfaces: 'live_item + rifa',
    action: 'live_item status após draw',
    http: draw1 ?? 'n/a',
    oracles: {'status': liSt, 'active': li?['is_active'], 'drawn': raf?['status']},
    result: d3fail ? 'FAIL' : 'HOLD',
    lens: 'DU2',
    classeNova: true,
    countFinding: d3fail,
  );

  final b2fail = drawOk && (insertLeak || c.usefulCs(cpi));
  if (b2fail) {
    c.hold(
      id: 'P1-B2-CPI-AFTER-DRAWN',
      lens: 'DU3',
      severity: 'P1',
      title: 'Após drawn, insert/CPI ainda abre compra do prémio',
      actor: 'B2 JWT',
      pre: 'drawn qty=1',
      repro: 'POST orders + CPI',
      expected: 'insert deny; sem cs_',
      obtained: {'ins': ins?.brief, 'cpi': cpi?.brief, 'hub_n': hubN},
    );
  } else {
    c.block('B2', 'DU3', 'insert/CPI pós-drawn', {
      'ins': ins?.brief,
      'cpi': cpi?.brief,
      'draw_ok': drawOk,
    });
  }
  c.probe(
    id: 'B2',
    surfaces: 'orders + CPI + Hub',
    action: 'after drawn: CPI / insert order nova',
    http: {'ins': ins?.brief, 'cpi': cpi?.brief},
    oracles: {'hub_n': hubN, 'qty': q1, 'draw_ok': drawOk},
    result: !drawOk ? 'SKIP' : (b2fail ? 'FAIL' : 'HOLD'),
    lens: 'DU3',
    classeNova: true,
    countFinding: b2fail,
  );

  // A2 winner_count=2 stock=2
  final fx2 = await makeLiveRaffle(c,
      s1: s1, title: 'A2 wc2', qty: 2, winnerCount: 2);
  HttpHit? a2draw;
  HttpHit? a2hub;
  HttpHit? a2ins;
  Map<String, dynamic>? a2prod;
  List<Map<String, dynamic>> a2win = const [];
  if (fx2.raf != null && fx2.sku != null) {
    await seedTickets(c, raf: fx2.raf!, user: b1, extra: 3);
    await seedTickets(c, raf: fx2.raf!, user: b2, jwt: c.buyer2Jwt, extra: 3);
    await c.closeRaffle(fx2.raf!);
    a2draw = await c.drawRaffle(fx2.raf!);
    a2win = await c.raffleWinners(fx2.raf!);
    a2prod = await c.productRow(fx2.sku!);
    a2hub = await c.hubSku(fx2.sku!, jwt: c.buyerJwt);
    a2ins = await c.insertOrderHit(
      productId: fx2.sku!,
      jwt: c.buyerJwt,
      buyer: b1,
      price: 9.0,
    );
  }
  final a2q = numOf(a2prod?['quantity']) ?? -1;
  final a2hubN = a2hub?.list.length ?? -1;
  final a2ok = a2win.length >= 2 &&
      a2ins != null &&
      !a2ins.ok &&
      (a2q < 1 || a2hubN == 0);
  final a2leak = a2win.length >= 2 &&
      (a2ins?.ok == true || (a2hubN > 0 && a2q >= 1));
  if (a2leak && !a2ok) {
    c.hold(
      id: 'P1-A2-MULTIWIN',
      lens: 'DU5',
      severity: 'P1',
      title: 'Multi-winner stock=2 não selou / 2.º insert passou',
      actor: 'S1 draw wc=2',
      pre: 'qty=2; 2 holders',
      repro: 'draw wc=2 + Hub + insert',
      expected: 'qty 0; Hub 0; insert deny',
      obtained: {
        'nWin': a2win.length,
        'qty': a2q,
        'hub_n': a2hubN,
        'ins': a2ins?.brief,
        'draw': a2draw?.brief,
      },
    );
  } else {
    c.block('A2', 'DU5', 'wc=2 selo', {
      'nWin': a2win.length,
      'qty': a2q,
      'hub_n': a2hubN,
      'ins': a2ins?.brief,
      'draw': a2draw?.brief,
    });
  }
  c.probe(
    id: 'A2',
    surfaces: 'Hub + products + winners + orders',
    action: 'draw winner_count=2 stock=2',
    http: {'draw': a2draw?.brief, 'ins': a2ins?.brief},
    oracles: {
      'nWin': a2win.length,
      'qty': a2q,
      'hub_n': a2hubN,
      'sold': a2prod?['is_sold'],
      'prize_n': fx2.raf == null ? 0 : (await c.prizeOrders(fx2.raf!)).length,
    },
    result: (a2leak && !a2ok) ? 'FAIL' : 'HOLD',
    lens: 'DU5',
    classeNova: true,
    countFinding: a2leak && !a2ok,
  );

  // A3 live_only
  final fx3 = await makeLiveRaffle(c,
      s1: s1, title: 'A3 liveonly', hitch: false);
  HttpHit? a3draw;
  Map<String, dynamic>? a3li;
  var a3n = 0;
  if (fx3.raf != null) {
    await seedTickets(c, raf: fx3.raf!, user: b1, extra: 3);
    await c.closeRaffle(fx3.raf!);
    a3draw = await c.drawRaffle(fx3.raf!);
    a3n = (await c.raffleWinners(fx3.raf!)).length;
    a3li = fx3.li == null ? null : await c.liveItemRow(fx3.li!);
  }
  final a3leak = a3n > 0 &&
      a3li != null &&
      '${a3li['status']}'.toLowerCase() == 'available' &&
      a3li['is_active'] == true;
  if (a3leak) {
    c.hold(
      id: 'P2-A3-LIVEONLY-LEAK',
      lens: 'DU1',
      severity: 'P2',
      title: 'Rifa live_only drawn deixa item available',
      actor: 'S1 draw',
      pre: 'live_only sem product_id',
      repro: 'draw + GET live_items',
      expected: 'sold/inactive',
      obtained: {'draw': a3draw?.brief, 'li': a3li, 'nWin': a3n},
    );
  } else {
    c.block('A3', 'DU1', 'live_only pós-draw', {
      'draw': a3draw?.brief,
      'li': a3li?['status'],
      'active': a3li?['is_active'],
      'nWin': a3n,
    });
  }
  c.probe(
    id: 'A3',
    surfaces: 'live_item + rifa (sem product)',
    action: 'draw live_only skipped vs leak',
    http: a3draw ?? 'n/a',
    oracles: {
      'li': a3li,
      'nWin': a3n,
      'product_id': a3li?['product_id'],
    },
    result: a3leak ? 'FAIL' : 'HOLD',
    lens: 'DU1',
    classeNova: true,
    countFinding: a3leak,
  );

  // B1 race draw∥CPI
  final fxb = await makeLiveRaffle(c, s1: s1, title: 'B1 race');
  HttpHit? b1draw;
  HttpHit? b1cpi;
  HttpHit? b1ins;
  HttpHit? b1hub;
  Map<String, dynamic>? b1prod;
  var b1win = 0;
  if (fxb.raf != null && fxb.sku != null) {
    await seedTickets(c, raf: fxb.raf!, user: b1, extra: 4);
    await c.closeRaffle(fxb.raf!);
    b1ins = await c.insertOrderHit(
      productId: fxb.sku!,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 9.0,
    );
    final oid = b1ins.firstId;
    final raced = await Future.wait([
      c.drawRaffle(fxb.raf!),
      if (oid != null)
        c.checkout(
          orderId: oid,
          jwt: c.buyer2Jwt,
          buyer: b2,
          productId: fxb.sku!,
          seller: s1,
          amount: 9,
        )
      else
        Future.value(b1ins),
    ]);
    b1draw = raced[0];
    b1cpi = raced[1];
    b1win = (await c.raffleWinners(fxb.raf!)).length;
    b1prod = await c.productRow(fxb.sku!);
    b1hub = await c.hubSku(fxb.sku!, jwt: c.buyerJwt);
  }
  final b1q = numOf(b1prod?['quantity']) ?? -1;
  final b1hubN = b1hub?.list.length ?? -1;
  final both = b1win >= 1 && c.usefulCs(b1cpi);
  final b1fail = both && (b1hubN > 0 || b1q >= 1);
  if (b1fail) {
    c.hold(
      id: 'P1-B1-DRAW-CPI-RACE',
      lens: 'DU4',
      severity: 'P1',
      title: 'Race draw∥CPI deixou prémio comprável',
      actor: 'S1 draw ∥ B2 CPI',
      pre: 'qty=1 closed com tickets',
      repro: 'Future.wait draw + CPI',
      expected: 'Hub 0 se drawn',
      obtained: {
        'draw': b1draw?.brief,
        'cpi': b1cpi?.brief,
        'qty': b1q,
        'hub_n': b1hubN,
        'nWin': b1win,
      },
    );
  } else {
    c.block('B1', 'DU4', 'draw∥CPI', {
      'draw': b1draw?.brief,
      'cpi': b1cpi?.brief,
      'qty': b1q,
      'hub_n': b1hubN,
      'nWin': b1win,
      'cs': c.usefulCs(b1cpi),
    });
  }
  c.probe(
    id: 'B1',
    surfaces: 'rifa + CPI + Hub + products',
    action: 'award + draw∥CPI paralelo',
    http: {'draw': b1draw?.brief, 'cpi': b1cpi?.brief, 'ins': b1ins?.brief},
    oracles: {
      'qty': b1q,
      'hub_n': b1hubN,
      'nWin': b1win,
      'cs': b1cpi?.sessionId,
    },
    result: b1fail ? 'FAIL' : 'HOLD',
    lens: 'DU4',
    classeNova: true,
    race: true,
    countFinding: b1fail,
  );

  // B3 leftover 3
  final fxL = await makeLiveRaffle(c, s1: s1, title: 'B3 left3', qty: 3);
  HttpHit? ldraw;
  HttpHit? lhub;
  HttpHit? lins;
  Map<String, dynamic>? lprod;
  var lwin = 0;
  if (fxL.raf != null && fxL.sku != null) {
    await seedTickets(c, raf: fxL.raf!, user: b1, extra: 4);
    await c.closeRaffle(fxL.raf!);
    ldraw = await c.drawRaffle(fxL.raf!);
    lwin = (await c.raffleWinners(fxL.raf!)).length;
    lprod = await c.productRow(fxL.sku!);
    lhub = await c.hubSku(fxL.sku!, jwt: c.buyerJwt);
    lins = await c.insertOrderHit(
      productId: fxL.sku!,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 9.0,
    );
  }
  final lq = numOf(lprod?['quantity']) ?? -1;
  final lhubN = lhub?.list.length ?? -1;
  final lwrong = lwin >= 1 && lq == 3;
  if (lwrong) {
    c.hold(
      id: 'P2-B3-LEFTOVER',
      lens: 'DU2',
      severity: 'P2',
      title: 'Leftover qty=3 winners=1 não decrementou',
      actor: 'S1 draw',
      pre: 'qty=3',
      repro: 'draw 1 winner + quantity',
      expected: 'qty=2 leftover',
      obtained: {'qty': lq, 'hub_n': lhubN, 'nWin': lwin, 'ins': lins?.brief},
    );
  } else {
    c.block('B3', 'DU2', 'leftover qty', {
      'qty': lq,
      'hub_n': lhubN,
      'nWin': lwin,
      'ins_ok': lins?.ok,
      'draw': ldraw?.brief,
    });
  }
  c.probe(
    id: 'B3',
    surfaces: 'Hub + products + winners',
    action: 'leftover stock=3 winners=1',
    http: {'draw': ldraw?.brief, 'ins': lins?.brief},
    oracles: {
      'qty': lq,
      'hub_n': lhubN,
      'nWin': lwin,
      'listed': lprod?['list_on_marketplace'],
    },
    result: lwrong ? 'FAIL' : 'HOLD',
    lens: 'DU2',
    classeNova: true,
    countFinding: lwrong,
  );

  // B4 refund premio_rifa
  final fxR = await makeLiveRaffle(c, s1: s1, title: 'B4 refund', qty: 1);
  HttpHit? rdraw;
  HttpHit? rrf;
  HttpHit? rhub;
  Map<String, dynamic>? rp0;
  Map<String, dynamic>? rp1;
  List<Map<String, dynamic>> rpr = const [];
  if (fxR.raf != null && fxR.sku != null) {
    await seedTickets(c, raf: fxR.raf!, user: b1, extra: 4);
    await c.closeRaffle(fxR.raf!);
    rdraw = await c.drawRaffle(fxR.raf!);
    rpr = await c.prizeOrders(fxR.raf!);
    rp0 = await c.productRow(fxR.sku!);
    if (rpr.isNotEmpty) {
      final oid = rpr.first['id']?.toString();
      if (oid != null) {
        rrf = await c.refund(oid, jwt: c.sellerJwt);
        if (!rrf.ok) {
          rrf = await c.rest(
            'PATCH',
            'orders?id=eq.$oid',
            jwt: c.sellerJwt,
            body: {'status': 'cancelado'},
          );
        }
        if (!rrf.ok) {
          rrf = await c.rest(
            'PATCH',
            'orders?id=eq.$oid',
            service: true,
            body: {'status': 'cancelado'},
          );
        }
      }
    }
    rp1 = await c.productRow(fxR.sku!);
    rhub = await c.hubSku(fxR.sku!, jwt: c.buyerJwt);
  }
  final rq0 = numOf(rp0?['quantity']) ?? -1;
  final rq1 = numOf(rp1?['quantity']) ?? -1;
  final rhubN = rhub?.list.length ?? -1;
  final restored = rpr.isNotEmpty && (rq1 > rq0 || (rq1 >= 1 && rhubN > 0));
  if (restored) {
    c.hold(
      id: 'P1-B4-REFUND-RESTORE',
      lens: 'DU3',
      severity: 'P1',
      title: 'Cancel/refund premio_rifa restaurou Hub',
      actor: 'seller refund',
      pre: 'drawn + prize',
      repro: 'refund-order / PATCH cancelado',
      expected: 'Hub 0',
      obtained: {'rf': rrf?.brief, 'qty': '$rq0→$rq1', 'hub_n': rhubN},
    );
  } else {
    c.block('B4', 'DU3', 'refund vs Hub', {
      'rf': rrf?.brief,
      'qty': '$rq0→$rq1',
      'hub_n': rhubN,
      'prize_n': rpr.length,
      'draw': rdraw?.brief,
    });
  }
  c.probe(
    id: 'B4',
    surfaces: 'orders premio_rifa + Hub + products',
    action: 'refund/cancel premio_rifa vs Hub restore',
    http: {'draw': rdraw?.brief, 'rf': rrf?.brief},
    oracles: {
      'prize_n': rpr.length,
      'qty': '$rq0→$rq1',
      'hub_n': rhubN,
      'prize_status': rpr.isEmpty ? null : rpr.first['status'],
    },
    result: restored ? 'FAIL' : 'HOLD',
    lens: 'DU3',
    classeNova: true,
    countFinding: restored,
  );

  // C2 hitch+rifa award∥unlist
  final fxc = await makeLiveRaffle(c, s1: s1, title: 'C2 hitch');
  HttpHit? unlist;
  HttpHit? award;
  HttpHit? acc;
  HttpHit? cdraw;
  HttpHit? chub;
  Map<String, dynamic>? cprod;
  Map<String, dynamic>? cres;
  var cn = 0;
  if (fxc.live != null &&
      fxc.li != null &&
      fxc.sku != null &&
      fxc.raf != null) {
    final rid = await c.insertReservation(
      liveId: fxc.live!,
      liveItemId: fxc.li!,
      jwt: c.buyer2Jwt,
      buyer: b2,
    );
    final raced = await Future.wait([
      seedTickets(c, raf: fxc.raf!, user: b1, extra: 4),
      c.unlistProduct(fxc.sku!),
    ]);
    award = null;
    unlist = raced[1] as HttpHit;
    if (rid != null) acc = await c.acceptRes(rid);
    await c.closeRaffle(fxc.raf!);
    cdraw = await c.drawRaffle(fxc.raf!);
    cn = (await c.raffleWinners(fxc.raf!)).length;
    if (rid != null) cres = await c.resRow(rid);
    cprod = await c.productRow(fxc.sku!);
    chub = await c.hubSku(fxc.sku!, jwt: c.buyerJwt);
  }
  final accepted = cres?['status'] == 'accepted';
  final cq = numOf(cprod?['quantity']) ?? -1;
  final chubN = chub?.list.length ?? -1;
  final c2leak = accepted && cn >= 1 && (cq >= 1 || chubN > 0);
  if (c2leak) {
    c.hold(
      id: 'P1-C2-HITCH-RAFFLE',
      lens: 'DU5',
      severity: 'P1',
      title: 'Accept hitch + winner SKU qty=1 ainda listado',
      actor: 'accept + draw',
      pre: 'qty=1 hitch+rifa award∥unlist',
      repro: 'accept + draw',
      expected: 'Hub 0',
      obtained: {
        'acc': acc?.brief,
        'res': cres,
        'nWin': cn,
        'qty': cq,
        'hub_n': chubN,
        'unlist': unlist?.brief,
      },
    );
  } else {
    c.block('C2', 'DU5', 'hitch+rifa', {
      'acc': acc?.brief,
      'res': cres?['status'],
      'nWin': cn,
      'qty': cq,
      'hub_n': chubN,
      'unlist': unlist?.brief,
      'draw': cdraw?.brief,
      'award_note': award?.brief,
    });
  }
  c.probe(
    id: 'C2',
    surfaces: 'live accept + rifa + Hub + products',
    action: 'accept hitch + rifa mesmo SKU (award∥unlist)',
    http: {
      'unlist': unlist?.brief,
      'acc': acc?.brief,
      'draw': cdraw?.brief,
    },
    oracles: {
      'res': cres?['status'],
      'nWin': cn,
      'qty': cq,
      'hub_n': chubN,
      'listed': cprod?['list_on_marketplace'],
      'double_claim': accepted && cn >= 1,
    },
    result: c2leak ? 'FAIL' : 'HOLD',
    lens: 'DU5',
    classeNova: true,
    race: true,
    countFinding: c2leak,
  );
}
