/// RED TEAM CEGO EA pass1 — rifa / Hub / live_item pós-DTDY ≥16.
/// Staging only. NÃO corrigir. NÃO produção. NÃO Fase 4.
/// Rifa active + ends_at futuro; join+tickets antes do close (lição DU).
import 'dart:io';

import '_rtea.dart';

String futureIso() => DateTime.now()
    .toUtc()
    .add(const Duration(hours: 2))
    .toIso8601String();

bool liOpen(Map<String, dynamic>? li) {
  if (li == null) return false;
  final st = '${li['status']}'.toLowerCase().trim();
  return st == 'available' && li['is_active'] == true;
}

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
      title: '$prefix $title',
      qty: qty,
      listed: true,
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
  c.note('join', 'join $user', join.brief, lens: 'EA1');
  var t = await c.raffleTickets(raf, user);
  if (t < 1) {
    final aw = await c.awardTickets(raffleId: raf, userId: user, delta: extra);
    c.note('award', 'award $user', aw.brief, lens: 'EA1');
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
  final s2 = c.seller2Id!;
  await c.restoreSeller1Published();
  await c.setHub(s2, false);

  try {
    await runA1Bundle(c, s1: s1, b1: b1, b2: b2);
    await runA2A3(c, s1: s1, b1: b1, b2: b2);
    await runB(c, s1: s1, b1: b1, b2: b2);
    await runC(c, s1: s1, b1: b1, b2: b2);
    await runD1(c, s1: s1, b1: b1);
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
    'auditor': 'REDTEAM_BLIND_EA_RAFFLE_HUB_POS_DTDY_v1',
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

/// A1+A4+A5+B2+D2+D3 no mesmo hitch qty=1 (oráculo multi-sítio).
Future<void> runA1Bundle(
  Rtdu c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  final fx = await makeLiveRaffle(c, s1: s1, title: 'A1 hitch1');
  HttpHit? close;
  HttpHit? drawB;
  HttpHit? draw1;
  HttpHit? draw2;
  HttpHit? hub;
  HttpHit? ins;
  HttpHit? cpi;
  HttpHit? seal;
  HttpHit? recSeller;
  HttpHit? recBuyer;
  HttpHit? recSvc;
  HttpHit? recAfterTamper;
  HttpHit? patchLi;
  HttpHit? patchRf;
  Map<String, dynamic>? prod0;
  Map<String, dynamic>? prod1;
  Map<String, dynamic>? liDraw;
  Map<String, dynamic>? liAfterRec;
  Map<String, dynamic>? liFinal;
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
    liDraw = fx.li == null ? null : await c.liveItemRow(fx.li!);
    raf = await c.raffleRow(fx.raf!);
    hub = await c.hubSku(fx.sku!, jwt: c.buyerJwt);
    seal = await c.sealPrize(fx.raf!);

    // D3 — forçar recompute (seller / buyer / service)
    if (fx.li != null) {
      recSeller = await c.recomputeLiveItem(fx.li!, jwt: c.sellerJwt);
      recBuyer = await c.recomputeLiveItem(fx.li!, jwt: c.buyerJwt);
      recSvc = await c.recomputeLiveItem(fx.li!, service: true);
      liAfterRec = await c.liveItemRow(fx.li!);

      patchLi = await c.rest(
        'PATCH',
        'live_items?id=eq.${fx.li}',
        jwt: c.sellerJwt,
        body: {'status': 'available', 'is_active': true},
      );
      patchRf = await c.rest(
        'PATCH',
        'live_raffles?id=eq.${fx.raf}',
        jwt: c.sellerJwt,
        body: {'status': 'closed'},
      );
      recAfterTamper = await c.recomputeLiveItem(fx.li!, jwt: c.sellerJwt);
      liFinal = await c.liveItemRow(fx.li!);
    }

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
  final buyerDrew = drawB?.rpcOk == true;
  final hubLeak = drawOk && hubN > 0;
  final insertLeak = drawOk && ins != null && ins.ok;
  final qtyLeak = drawOk && q1 >= 1 && !sold;
  final a1fail = drawOk && (hubLeak || insertLeak || qtyLeak);
  final a1drawFail = fx.raf != null && tickets >= 1 && !drawOk;
  final a1LiFail = drawOk && liOpen(liDraw);

  // A5
  if (buyerDrew) {
    c.hold(
      id: 'P1-A5-BUYER-DRAW',
      lens: 'EA6',
      severity: 'P1',
      title: 'JWT comprador sorteou rifa closed com tickets',
      actor: 'buyer JWT',
      pre: 'closed + tickets≥1',
      repro: 'batata_draw_live_raffle_winners JWT buyer',
      expected: 'not_allowed',
      obtained: drawB?.brief,
    );
  } else {
    c.block('A5', 'EA6', 'buyer draw recusado', drawB?.brief);
  }
  c.probe(
    id: 'A5',
    surfaces: 'rifa RPC',
    action: 'JWT buyer tenta batata_draw_live_raffle_winners',
    http: drawB ?? 'n/a',
    oracles: {'tickets': tickets, 'buyer_ok': buyerDrew, 'nWin': wins.length},
    result: buyerDrew ? 'FAIL' : 'HOLD',
    lens: 'EA6',
    countFinding: buyerDrew,
  );

  // A1 reteste qty=1 Hub 0 + live_item ≠ available
  if (a1drawFail) {
    c.hold(
      id: 'P2-A1-DRAW-FAIL',
      lens: 'EA1',
      severity: 'P2',
      title: 'Draw qty=1 hitch não fechou drawn',
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
      lens: 'EA2',
      severity: hubLeak || insertLeak ? 'P1' : 'P2',
      title: 'Após drawn qty=1 o prémio continua comprável',
      actor: 'S1 draw + B2 insert/Hub',
      pre: 'SKU qty=1 hitch, winner',
      repro: 'draw + hub_products_public + POST orders + GET live_items',
      expected: 'Hub 0; insert deny; qty 0 / is_sold; live_item ≠ available',
      obtained: {
        'hub_n': hubN,
        'qty': '$q0→$q1',
        'sold': sold,
        'listed': listed,
        'ins': ins?.brief,
        'nWin': wins.length,
        'prize_n': prizes.length,
        'li': liDraw,
      },
    );
  } else {
    c.block('A1', 'EA2', 'drawn qty=1 Hub 0 + live_item selado', {
      'hub_n': hubN,
      'qty': '$q0→$q1',
      'sold': sold,
      'li': liDraw?['status'],
      'active': liDraw?['is_active'],
      'ins': ins?.brief,
    });
  }
  c.probe(
    id: 'A1',
    surfaces: 'Hub + products + live_item + orders',
    action: 'draw qty=1 marketplace hitch → Hub 0 + live_item ≠ available',
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
      'li': liDraw?['status'],
      'li_active': liDraw?['is_active'],
      'status': raf?['status'],
    },
    result: a1drawFail || a1fail || a1LiFail ? 'FAIL' : 'HOLD',
    lens: 'EA2',
    residual: true,
    countFinding: a1drawFail || a1fail,
  );

  // A4
  final a4fail = wins.length > 1 || (draw2?.rpcOk == true && wins.length > 1);
  if (a4fail) {
    c.hold(
      id: 'P1-A4-DOUBLE-DRAW',
      lens: 'EA1',
      severity: 'P1',
      title: '2.º draw criou vencedor extra',
      actor: 'seller ×2',
      pre: 'já drawn',
      repro: 'draw ×2',
      expected: '1 winner; 2.º deny',
      obtained: {'d2': draw2?.brief, 'nWin': wins.length},
    );
  } else {
    c.block('A4', 'EA1', '2.º draw deny', {
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
    lens: 'EA1',
    residual: true,
    countFinding: a4fail,
  );

  // D2
  final d2mismatch = drawOk && prizes.isEmpty && (hubLeak || insertLeak);
  if (d2mismatch) {
    c.hold(
      id: 'P2-D2-SEAL-VS-PRIZE',
      lens: 'EA7',
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
    c.block('D2', 'EA7', 'prize_orders vs seal', {
      'prize_n': prizes.length,
      'hub_n': hubN,
      'seal': seal?.brief,
    });
  }
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
    lens: 'EA7',
    classeNova: true,
    countFinding: d2mismatch,
  );

  // D3 — forçar recompute; status não volta available
  final recBuyerOk = recBuyer?.rpcOk == true;
  final recReopen = drawOk && (liOpen(liAfterRec) || liOpen(liFinal));
  final d3instant = drawOk && liOpen(liDraw);
  if (d3instant || recReopen) {
    c.hold(
      id: recReopen && !d3instant
          ? 'P2-D3-RECOMPUTE-REOPEN'
          : 'P2-D3-LI-AVAILABLE',
      lens: 'EA4',
      severity: 'P2',
      title: recReopen && !d3instant
          ? 'recompute / PATCH reabriu live_item available após drawn'
          : 'live_item continua available após drawn (recompute não selou)',
      actor: 'S1 draw + recompute JWT/svc + PATCH',
      pre: 'hitch marketplace qty=1 drawn',
      repro:
          'batata_recompute_live_item_status seller/buyer/svc; PATCH available; PATCH raffle closed; recompute',
      expected: 'sold/inactive; recompute não volta available',
      obtained: {
        'li_draw': liDraw,
        'li_after_rec': liAfterRec,
        'li_final': liFinal,
        'rec_s': recSeller?.brief,
        'rec_b': recBuyer?.brief,
        'rec_svc': recSvc?.brief,
        'patch_li': patchLi?.brief,
        'patch_rf': patchRf?.brief,
        'rec_tamper': recAfterTamper?.brief,
      },
    );
  } else {
    c.block('D3', 'EA4', 'recompute não reabre available', {
      'li_draw': liDraw?['status'],
      'li_final': liFinal?['status'] ?? liAfterRec?['status'],
      'rec_s': recSeller?.brief,
      'rec_b': recBuyer?.brief,
      'rec_svc': recSvc?.brief,
      'buyer_ok': recBuyerOk,
      'patch_li': patchLi?.brief,
      'patch_rf': patchRf?.brief,
    });
  }
  c.probe(
    id: 'D3',
    surfaces: 'live_item + recompute RPC + raffle',
    action:
        'forçar batata_recompute_live_item_status após draw — status não volta available',
    http: {
      'rec_s': recSeller?.brief,
      'rec_b': recBuyer?.brief,
      'rec_svc': recSvc?.brief,
      'patch_li': patchLi?.brief,
      'rec_tamper': recAfterTamper?.brief,
    },
    oracles: {
      'li_draw': liDraw?['status'],
      'li_draw_active': liDraw?['is_active'],
      'li_after_rec': liAfterRec?['status'],
      'li_final': liFinal?['status'],
      'li_final_active': liFinal?['is_active'],
      'buyer_recompute_ok': recBuyerOk,
      'drawn': raf?['status'],
    },
    result: (d3instant || recReopen) ? 'FAIL' : 'HOLD',
    lens: 'EA4',
    classeNova: true,
    countFinding: d3instant || recReopen,
  );

  // B2
  final b2fail = drawOk && (insertLeak || c.usefulCs(cpi));
  if (b2fail) {
    c.hold(
      id: 'P1-B2-CPI-AFTER-DRAWN',
      lens: 'EA3',
      severity: 'P1',
      title: 'Após drawn, insert/CPI ainda abre compra do prémio',
      actor: 'B2 JWT',
      pre: 'drawn qty=1',
      repro: 'POST orders + CPI',
      expected: 'insert deny; sem cs_',
      obtained: {'ins': ins?.brief, 'cpi': cpi?.brief, 'hub_n': hubN},
    );
  } else {
    c.block('B2', 'EA3', 'insert/CPI pós-drawn', {
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
    lens: 'EA3',
    classeNova: true,
    countFinding: b2fail,
  );
}

Future<void> runA2A3(
  Rtdu c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  final fx2 = await makeLiveRaffle(c,
      s1: s1, title: 'A2 wc2', qty: 2, winnerCount: 2);
  HttpHit? a2draw;
  HttpHit? a2hub;
  HttpHit? a2ins;
  HttpHit? a2rec;
  Map<String, dynamic>? a2prod;
  Map<String, dynamic>? a2li;
  List<Map<String, dynamic>> a2win = const [];
  if (fx2.raf != null && fx2.sku != null) {
    await seedTickets(c, raf: fx2.raf!, user: b1, extra: 3);
    await seedTickets(c, raf: fx2.raf!, user: b2, jwt: c.buyer2Jwt, extra: 3);
    await c.closeRaffle(fx2.raf!);
    a2draw = await c.drawRaffle(fx2.raf!);
    a2win = await c.raffleWinners(fx2.raf!);
    a2prod = await c.productRow(fx2.sku!);
    a2li = fx2.li == null ? null : await c.liveItemRow(fx2.li!);
    if (fx2.li != null) {
      a2rec = await c.recomputeLiveItem(fx2.li!, jwt: c.sellerJwt);
      a2li = await c.liveItemRow(fx2.li!);
    }
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
      (a2ins?.ok == true || (a2hubN > 0 && a2q >= 1) || liOpen(a2li));
  if (a2leak && !a2ok) {
    c.hold(
      id: 'P1-A2-MULTIWIN',
      lens: 'EA5',
      severity: liOpen(a2li) ? 'P2' : 'P1',
      title: 'Multi-winner stock=2 não selou / 2.º insert / live_item aberto',
      actor: 'S1 draw wc=2',
      pre: 'qty=2; 2 holders',
      repro: 'draw wc=2 + Hub + insert + live_item + recompute',
      expected: 'qty 0; Hub 0; insert deny; live_item ≠ available',
      obtained: {
        'nWin': a2win.length,
        'qty': a2q,
        'hub_n': a2hubN,
        'ins': a2ins?.brief,
        'draw': a2draw?.brief,
        'li': a2li,
        'rec': a2rec?.brief,
      },
    );
  } else {
    c.block('A2', 'EA5', 'wc=2 selo + live_item', {
      'nWin': a2win.length,
      'qty': a2q,
      'hub_n': a2hubN,
      'ins': a2ins?.brief,
      'li': a2li?['status'],
      'active': a2li?['is_active'],
      'rec': a2rec?.brief,
    });
  }
  c.probe(
    id: 'A2',
    surfaces: 'Hub + products + winners + orders + live_item',
    action: 'draw winner_count=2 stock=2 → Hub qty / 2.º insert / live_item',
    http: {'draw': a2draw?.brief, 'ins': a2ins?.brief, 'rec': a2rec?.brief},
    oracles: {
      'nWin': a2win.length,
      'qty': a2q,
      'hub_n': a2hubN,
      'sold': a2prod?['is_sold'],
      'li': a2li?['status'],
      'li_active': a2li?['is_active'],
    },
    result: (a2leak && !a2ok) ? 'FAIL' : 'HOLD',
    lens: 'EA5',
    classeNova: true,
    countFinding: a2leak && !a2ok,
  );

  // A3 live_only
  final fx3 =
      await makeLiveRaffle(c, s1: s1, title: 'A3 liveonly', hitch: false);
  HttpHit? a3draw;
  HttpHit? a3rec;
  HttpHit? a3hubGhost;
  Map<String, dynamic>? a3li;
  var a3n = 0;
  if (fx3.raf != null) {
    await seedTickets(c, raf: fx3.raf!, user: b1, extra: 3);
    await c.closeRaffle(fx3.raf!);
    a3draw = await c.drawRaffle(fx3.raf!);
    a3n = (await c.raffleWinners(fx3.raf!)).length;
    a3li = fx3.li == null ? null : await c.liveItemRow(fx3.li!);
    if (fx3.li != null) {
      a3rec = await c.recomputeLiveItem(fx3.li!, service: true);
      a3li = await c.liveItemRow(fx3.li!);
    }
    if (a3li?['product_id'] != null) {
      a3hubGhost = await c.hubSku('${a3li!['product_id']}', jwt: c.buyerJwt);
    }
  }
  final a3leak = a3n > 0 && liOpen(a3li);
  if (a3leak) {
    c.hold(
      id: 'P2-A3-LIVEONLY-LEAK',
      lens: 'EA1',
      severity: 'P2',
      title: 'Rifa live_only drawn deixa item available',
      actor: 'S1 draw',
      pre: 'live_only sem product_id',
      repro: 'draw + GET live_items + recompute svc',
      expected: 'sold/inactive',
      obtained: {
        'draw': a3draw?.brief,
        'li': a3li,
        'nWin': a3n,
        'rec': a3rec?.brief,
        'hub': a3hubGhost?.brief,
      },
    );
  } else {
    c.block('A3', 'EA1', 'live_only pós-draw + recompute', {
      'draw': a3draw?.brief,
      'li': a3li?['status'],
      'active': a3li?['is_active'],
      'nWin': a3n,
      'rec': a3rec?.brief,
      'product_id': a3li?['product_id'],
    });
  }
  c.probe(
    id: 'A3',
    surfaces: 'live_item + rifa (sem product) + Hub leak check',
    action: 'draw live_only sem product_id → live_item + leak Hub',
    http: a3draw ?? 'n/a',
    oracles: {
      'li': a3li?['status'],
      'active': a3li?['is_active'],
      'nWin': a3n,
      'product_id': a3li?['product_id'],
      'rec': a3rec?.brief,
      'hub_ghost': a3hubGhost?.list.length,
    },
    result: a3leak ? 'FAIL' : 'HOLD',
    lens: 'EA1',
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
  final fxb = await makeLiveRaffle(c, s1: s1, title: 'B1 race');
  HttpHit? b1draw;
  HttpHit? b1cpi;
  HttpHit? b1ins;
  HttpHit? b1hub;
  Map<String, dynamic>? b1prod;
  Map<String, dynamic>? b1li;
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
    b1li = fxb.li == null ? null : await c.liveItemRow(fxb.li!);
    b1hub = await c.hubSku(fxb.sku!, jwt: c.buyerJwt);
  }
  final b1q = numOf(b1prod?['quantity']) ?? -1;
  final b1hubN = b1hub?.list.length ?? -1;
  final both = b1win >= 1 && c.usefulCs(b1cpi);
  final b1fail = both && (b1hubN > 0 || b1q >= 1 || liOpen(b1li));
  if (b1fail) {
    c.hold(
      id: 'P1-B1-DRAW-CPI-RACE',
      lens: 'EA4',
      severity: 'P1',
      title: 'Race draw∥CPI deixou prémio comprável / live_item aberto',
      actor: 'S1 draw ∥ B2 CPI',
      pre: 'qty=1 closed com tickets',
      repro: 'Future.wait draw + CPI',
      expected: 'Hub 0 se drawn; live_item ≠ available',
      obtained: {
        'draw': b1draw?.brief,
        'cpi': b1cpi?.brief,
        'qty': b1q,
        'hub_n': b1hubN,
        'nWin': b1win,
        'li': b1li,
      },
    );
  } else {
    c.block('B1', 'EA4', 'draw∥CPI', {
      'draw': b1draw?.brief,
      'cpi': b1cpi?.brief,
      'qty': b1q,
      'hub_n': b1hubN,
      'nWin': b1win,
      'cs': c.usefulCs(b1cpi),
      'li': b1li?['status'],
    });
  }
  c.probe(
    id: 'B1',
    surfaces: 'rifa + CPI + Hub + products + live_item',
    action: 'award + draw∥CPI marketplace paralelo',
    http: {'draw': b1draw?.brief, 'cpi': b1cpi?.brief, 'ins': b1ins?.brief},
    oracles: {
      'qty': b1q,
      'hub_n': b1hubN,
      'nWin': b1win,
      'cs': b1cpi?.sessionId,
      'li': b1li?['status'],
    },
    result: b1fail ? 'FAIL' : 'HOLD',
    lens: 'EA4',
    classeNova: true,
    race: true,
    countFinding: b1fail,
  );

  // B3 leftover
  final fxL = await makeLiveRaffle(c, s1: s1, title: 'B3 left3', qty: 3);
  HttpHit? ldraw;
  HttpHit? lhub;
  HttpHit? lins;
  HttpHit? lrec;
  Map<String, dynamic>? lprod;
  Map<String, dynamic>? lli;
  var lwin = 0;
  if (fxL.raf != null && fxL.sku != null) {
    await seedTickets(c, raf: fxL.raf!, user: b1, extra: 4);
    await c.closeRaffle(fxL.raf!);
    ldraw = await c.drawRaffle(fxL.raf!);
    lwin = (await c.raffleWinners(fxL.raf!)).length;
    lprod = await c.productRow(fxL.sku!);
    lli = fxL.li == null ? null : await c.liveItemRow(fxL.li!);
    if (fxL.li != null) {
      lrec = await c.recomputeLiveItem(fxL.li!, jwt: c.sellerJwt);
      lli = await c.liveItemRow(fxL.li!);
    }
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
      lens: 'EA2',
      severity: 'P2',
      title: 'Leftover qty=3 winners=1 não decrementou',
      actor: 'S1 draw',
      pre: 'qty=3',
      repro: 'draw 1 winner + quantity',
      expected: 'qty=2 leftover; Hub lista resto',
      obtained: {
        'qty': lq,
        'hub_n': lhubN,
        'nWin': lwin,
        'ins': lins?.brief,
        'li': lli,
        'rec': lrec?.brief,
      },
    );
  } else {
    c.block('B3', 'EA2', 'leftover qty', {
      'qty': lq,
      'hub_n': lhubN,
      'nWin': lwin,
      'ins_ok': lins?.ok,
      'li': lli?['status'],
      'rec': lrec?.brief,
    });
  }
  c.probe(
    id: 'B3',
    surfaces: 'Hub + products + winners + live_item',
    action: 'leftover stock=3 winners=1 → Hub lista? qty',
    http: {'draw': ldraw?.brief, 'ins': lins?.brief, 'rec': lrec?.brief},
    oracles: {
      'qty': lq,
      'hub_n': lhubN,
      'nWin': lwin,
      'listed': lprod?['list_on_marketplace'],
      'li': lli?['status'],
      'li_active': lli?['is_active'],
    },
    result: lwrong ? 'FAIL' : 'HOLD',
    lens: 'EA2',
    classeNova: true,
    countFinding: lwrong,
  );

  // B4
  final fxR = await makeLiveRaffle(c, s1: s1, title: 'B4 refund', qty: 1);
  HttpHit? rdraw;
  HttpHit? rrf;
  HttpHit? rhub;
  Map<String, dynamic>? rp0;
  Map<String, dynamic>? rp1;
  Map<String, dynamic>? rli;
  List<Map<String, dynamic>> rpr = const [];
  if (fxR.raf != null && fxR.sku != null) {
    await seedTickets(c, raf: fxR.raf!, user: b1, extra: 4);
    await c.closeRaffle(fxR.raf!);
    rdraw = await c.drawRaffle(fxR.raf!);
    rpr = await c.prizeOrders(fxR.raf!);
    rp0 = await c.productRow(fxR.sku!);
    rli = fxR.li == null ? null : await c.liveItemRow(fxR.li!);
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
    if (fxR.li != null) rli = await c.liveItemRow(fxR.li!);
  }
  final rq0 = numOf(rp0?['quantity']) ?? -1;
  final rq1 = numOf(rp1?['quantity']) ?? -1;
  final rhubN = rhub?.list.length ?? -1;
  final restored = rpr.isNotEmpty && (rq1 > rq0 || (rq1 >= 1 && rhubN > 0));
  if (restored) {
    c.hold(
      id: 'P1-B4-REFUND-RESTORE',
      lens: 'EA3',
      severity: 'P1',
      title: 'Cancel/refund premio_rifa restaurou Hub',
      actor: 'seller refund',
      pre: 'drawn + prize',
      repro: 'refund-order / PATCH cancelado',
      expected: 'Hub 0',
      obtained: {
        'rf': rrf?.brief,
        'qty': '$rq0→$rq1',
        'hub_n': rhubN,
        'li': rli,
      },
    );
  } else {
    c.block('B4', 'EA3', 'refund vs Hub', {
      'rf': rrf?.brief,
      'qty': '$rq0→$rq1',
      'hub_n': rhubN,
      'prize_n': rpr.length,
      'li': rli?['status'],
    });
  }
  c.probe(
    id: 'B4',
    surfaces: 'orders premio_rifa + Hub + products + live_item',
    action: 'refund/cancel premio_rifa vs Hub restore',
    http: {'draw': rdraw?.brief, 'rf': rrf?.brief},
    oracles: {
      'prize_n': rpr.length,
      'qty': '$rq0→$rq1',
      'hub_n': rhubN,
      'li': rli?['status'],
    },
    result: restored ? 'FAIL' : 'HOLD',
    lens: 'EA3',
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
      r2 == null ? c.acceptRes(r1) : c.acceptRes(r2),
    ]);
    conv = raced[0];
    acc = raced[1];
    row1 = await c.resRow(r1);
    if (r2 != null) row2 = await c.resRow(r2);
  }
  final convertedUnpaid = row1?['status'] == 'converted' ||
      (row2?['status'] == 'converted');
  if (convertedUnpaid) {
    c.hold(
      id: 'P1-C1-CONVERT-UNPAID',
      lens: 'EA3',
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
    c.block('C1', 'EA3', 'convert pending deny; race convert∥accept', {
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
    lens: 'EA3',
    race: true,
    countFinding: convertedUnpaid,
  );

  final fxc = await makeLiveRaffle(c, s1: s1, title: 'C2 hitch');
  HttpHit? unlist;
  HttpHit? accH;
  HttpHit? cdraw;
  HttpHit? chub;
  Map<String, dynamic>? cprod;
  Map<String, dynamic>? cres;
  Map<String, dynamic>? cli;
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
    unlist = raced[1] as HttpHit;
    if (rid != null) accH = await c.acceptRes(rid);
    await c.closeRaffle(fxc.raf!);
    cdraw = await c.drawRaffle(fxc.raf!);
    cn = (await c.raffleWinners(fxc.raf!)).length;
    if (rid != null) cres = await c.resRow(rid);
    cprod = await c.productRow(fxc.sku!);
    cli = await c.liveItemRow(fxc.li!);
    chub = await c.hubSku(fxc.sku!, jwt: c.buyerJwt);
  }
  final accepted = cres?['status'] == 'accepted';
  final cq = numOf(cprod?['quantity']) ?? -1;
  final chubN = chub?.list.length ?? -1;
  final c2leak = accepted && cn >= 1 && (cq >= 1 || chubN > 0);
  if (c2leak) {
    c.hold(
      id: 'P1-C2-HITCH-RAFFLE',
      lens: 'EA5',
      severity: 'P1',
      title: 'Accept hitch + winner SKU qty=1 ainda listado',
      actor: 'accept + draw',
      pre: 'qty=1 hitch+rifa award∥unlist',
      repro: 'accept + draw',
      expected: 'Hub 0',
      obtained: {
        'acc': accH?.brief,
        'res': cres,
        'nWin': cn,
        'qty': cq,
        'hub_n': chubN,
        'unlist': unlist?.brief,
        'li': cli,
      },
    );
  } else {
    c.block('C2', 'EA5', 'hitch+rifa', {
      'acc': accH?.brief,
      'res': cres?['status'],
      'nWin': cn,
      'qty': cq,
      'hub_n': chubN,
      'unlist': unlist?.brief,
      'li': cli?['status'],
    });
  }
  c.probe(
    id: 'C2',
    surfaces: 'live accept + rifa + Hub + products + live_item',
    action: 'accept hitch + rifa mesmo SKU (award∥unlist)',
    http: {'unlist': unlist?.brief, 'acc': accH?.brief, 'draw': cdraw?.brief},
    oracles: {
      'res': cres?['status'],
      'nWin': cn,
      'qty': cq,
      'hub_n': chubN,
      'listed': cprod?['list_on_marketplace'],
      'double_claim': accepted && cn >= 1,
      'li': cli?['status'],
    },
    result: c2leak ? 'FAIL' : 'HOLD',
    lens: 'EA5',
    classeNova: true,
    race: true,
    countFinding: c2leak,
  );

  await c.createLive(title: '$prefix C3 no-raffle');
  const ghost = '00000000-0000-4000-8000-0000000000ea';
  final share = await c.claimShare(ghost, jwt: c.buyerJwt);
  final join = await c.joinRaffle(ghost, jwt: c.buyerJwt);
  final tGhost = await c.raffleTickets(ghost, b1);
  final wGhost = (await c.raffleWinners(ghost)).length;
  final c3prize = tGhost > 0 || wGhost > 0 || share.rpcOk || join.rpcOk;
  if (c3prize) {
    c.hold(
      id: 'P1-C3-SHARE-NO-RAFFLE',
      lens: 'EA6',
      severity: 'P1',
      title: 'Partilhar sem rifa activa deu bilhetes',
      actor: 'buyer JWT',
      pre: 'UUID fantasma',
      repro: 'claim_share + join raffle_id inexistente',
      expected: 'raffle_not_found; tickets=0',
      obtained: {
        'share': share.brief,
        'join': join.brief,
        'tickets': tGhost,
      },
    );
  } else {
    c.block('C3', 'EA6', 'sem rifa = sem bilhetes', {
      'share': share.brief,
      'join': join.brief,
    });
  }
  c.probe(
    id: 'C3',
    surfaces: 'rifa social',
    action: 'partilhar sem rifa activa → sem bilhetes',
    http: '${share.brief} | ${join.brief}',
    oracles: {'tickets': tGhost, 'winners': wGhost},
    result: c3prize ? 'FAIL' : 'HOLD',
    lens: 'EA6',
    residual: true,
    countFinding: c3prize,
  );

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
    c.skip('C4', 'EA6', 'create raffle fail', rafC4?.brief);
  } else if (forged) {
    c.hold(
      id: 'P1-C4-FORGE-ENTRY',
      lens: 'EA6',
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
    c.block('C4', 'EA6', 'share OK; forge entry recusado', {
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
    lens: 'EA6',
    classeNova: true,
    countFinding: forged,
  );
}

Future<void> runD1(
  Rtdu c, {
  required String s1,
  required String b1,
}) async {
  final paid = await c.payToPago(lens: 'EA7', initialQty: 2);
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
    c.skip('D1', 'EA7', 'setup_paid_order fail', 'null');
  } else if (incoherent) {
    c.hold(
      id: 'P2-D1-HUB-LEFTOVER',
      lens: 'EA7',
      severity: 'P2',
      title: 'Pago 4242 leftover Hub incoerente',
      actor: 'e2e setup_paid_order',
      pre: 'SKU qty=2 não-prémio',
      repro: 'setup_paid_order + hub_products_public',
      expected: 'status pago; qty leftover 1; Hub 1 linha',
      obtained: {'status': status, 'qty': q, 'hub_n': hubN, 'pi': pi},
    );
  } else {
    c.block('D1', 'EA7', 'pago 4242 + Hub leftover', {
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
    lens: 'EA7',
    countFinding: incoherent,
  );
}
