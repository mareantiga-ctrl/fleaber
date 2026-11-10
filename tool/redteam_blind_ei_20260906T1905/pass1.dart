/// RED TEAM CEGO EI pass1 — stock / Hub / hold POS_OPEN_MVP ≥16.
/// Staging only. NÃO corrigir. NÃO produção. NÃO Fase 4.
import 'dart:io';

import '_rtei.dart';

String futureIso() => DateTime.now()
    .toUtc()
    .add(const Duration(hours: 2))
    .toIso8601String();

bool liOpen(Map<String, dynamic>? li) {
  if (li == null) return false;
  final st = '${li['status']}'.toLowerCase().trim();
  return st == 'available' && li['is_active'] == true;
}

Future<void> pause([int ms = 400]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

Future<({
  String? sku,
  String? live,
  String? li,
  String? raf,
})> makeLiveRaffle(
  Rtdu c, {
  required String s1,
  required String title,
  int qty = 1,
  int winnerCount = 1,
}) async {
  final sku = await c.createProduct(
    title: '$prefix $title',
    qty: qty,
    listed: true,
    live: true,
    price: 9.0,
  );
  final live = await c.createLive(title: '$prefix $title');
  String? li;
  if (live != null && sku != null) {
    li = await c.createLiveItem(
      liveId: live,
      title: '$prefix $title-li',
      kind: 'marketplace_product',
      productId: sku,
    );
  }
  String? raf;
  if (live != null) {
    final ins = await c.rest('POST', 'live_raffles', service: true, body: {
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
  return (sku: sku, live: live, li: li, raf: raf);
}

Future<int> seedTickets(Rtdu c, {required String raf, required String user}) async {
  await c.joinRaffle(raf, jwt: c.buyerJwt);
  var t = await c.raffleTickets(raf, user);
  if (t < 1) {
    await c.awardTickets(raffleId: raf, userId: user, delta: 5);
    t = await c.raffleTickets(raf, user);
  } else {
    await c.awardTickets(raffleId: raf, userId: user, delta: 4);
    t = await c.raffleTickets(raf, user);
  }
  return t;
}

Map<String, Object?> claimSnap(
  List<Map<String, dynamic>> rows, {
  num? held,
  Map<String, dynamic>? prod,
  int? hubN,
}) {
  return {
    'n_orders': rows.length,
    'live_claims': RtduDummy.live(rows),
    'statuses': rows.map((e) => e['status']).toList(),
    'buyers': rows.map((e) => e['buyer_id']).toSet().toList(),
    if (held != null) 'held': held,
    if (prod != null)
      'prod': {
        'qty': prod['quantity'],
        'sold': prod['is_sold'],
        'listed': prod['list_on_marketplace'],
      },
    if (hubN != null) 'hub_n': hubN,
  };
}

/// Tiny shim so claimSnap can call liveClaims without a client.
class RtduDummy {
  static int live(List<Map<String, dynamic>> rows) {
    const dead = {
      'cancelado',
      'cancelled',
      'expired',
      'expirado',
      'reembolsado',
      'refunded',
      'rejeitado',
    };
    var n = 0;
    for (final r in rows) {
      final st = '${r['status'] ?? ''}'.toLowerCase().trim();
      if (st.isEmpty || dead.contains(st)) continue;
      n += (numOf(r['quantity']) ?? 1).round();
    }
    return n;
  }
}

Future<void> main() async {
  final c = Rtdu.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  stdout.writeln('EI pass1 staging=${c.url} prefix=$prefix');
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final s1 = c.sellerId!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;
  final s2 = c.seller2Id!;
  await c.restoreSeller1Published();
  await c.setHub(s2, false);
  c.note('actors', 'ids', {'b1': b1, 's1': s1, 'b2': b2, 's2': s2});

  try {
    await runA(c, s1: s1, b1: b1, b2: b2);
    await runB(c, s1: s1, b1: b1, b2: b2);
    await runC(c, s1: s1, b1: b1, b2: b2, s2: s2);
    await runD(c, s1: s1, b1: b1, b2: b2);
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
  final fails = c.probes.where((p) => p['result'] == 'FAIL').length;
  await dumpJson('${outDir()}/pass1.json', {
    'auditor': 'REDTEAM_BLIND_EI_STOCK_HUB_POS_OPEN_v1',
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
      'fails': fails,
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

Future<void> runA(
  Rtdu c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // A1 — 2 buyers insert qty=1 paralelo
  final a1pid = await c.createProduct(
    title: '$prefix A1 qty1',
    qty: 1,
    price: 11,
  );
  HttpHit? a1b1;
  HttpHit? a1b2;
  if (a1pid != null) {
    final raced = await Future.wait([
      c.insertOrderHit(productId: a1pid, jwt: c.buyerJwt, buyer: b1, price: 11),
      c.insertOrderHit(productId: a1pid, jwt: c.buyer2Jwt, buyer: b2, price: 11),
    ]);
    a1b1 = raced[0];
    a1b2 = raced[1];
  }
  final a1rows = a1pid == null ? <Map<String, dynamic>>[] : await c.ordersForProduct(a1pid);
  final a1heldH = a1pid == null ? null : await c.heldQty(a1pid);
  final a1held = a1heldH == null ? -1 : c.heldQtyNum(a1heldH);
  final a1prod = a1pid == null ? null : await c.productRow(a1pid);
  final a1hub = a1pid == null ? null : await c.hubSku(a1pid, jwt: c.buyerJwt);
  final a1claims = c.liveClaims(a1rows);
  final a1ok = [a1b1, a1b2].where((h) => h != null && h.ok).length;
  final a1oversell = a1pid != null && a1claims >= 2;
  if (a1oversell) {
    c.hold(
      id: 'P1-A1-TWO-INSERT',
      lens: 'EI-A',
      severity: 'P1',
      title: '2 buyers insert qty=1: dois holds vivos',
      actor: 'B1∥B2 JWT insert',
      pre: 'SKU qty=1',
      repro: 'Future.wait insertOrder B1 + B2',
      expected: '≤1 hold vivo / 2.º 400 hold',
      obtained: {
        'ok': a1ok,
        'claims': a1claims,
        'held': a1held,
        'b1': a1b1?.brief,
        'b2': a1b2?.brief,
      },
    );
  } else {
    c.block('A1', 'EI-A', '2 buyers insert ≤1 hold', {
      'ok': a1ok,
      'claims': a1claims,
      'held': a1held,
      'b1': a1b1?.brief,
      'b2': a1b2?.brief,
    });
  }
  c.probe(
    id: 'A1',
    surfaces: 'orders + hold + Hub + products',
    action: '2 buyers insert qty=1 paralelo',
    http: {'b1': a1b1?.brief, 'b2': a1b2?.brief, 'held': a1heldH?.brief},
    oracles: claimSnap(a1rows, held: a1held, prod: a1prod, hubN: a1hub?.list.length),
    result: a1oversell ? 'FAIL' : 'HOLD',
    lens: 'EI-A',
    race: true,
    countFinding: a1oversell,
  );

  await pause();

  // A2 — 2 buyers CPI paralelo
  final a2pid = await c.createProduct(
    title: '$prefix A2 cpi',
    qty: 1,
    price: 12,
  );
  HttpHit? a2i1;
  HttpHit? a2i2;
  HttpHit? a2c1;
  HttpHit? a2c2;
  if (a2pid != null) {
    a2i1 = await c.insertOrderHit(
      productId: a2pid,
      jwt: c.buyerJwt,
      buyer: b1,
      price: 12,
    );
    a2i2 = await c.insertOrderHit(
      productId: a2pid,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 12,
    );
    final o1 = a2i1.firstId;
    final o2 = a2i2.firstId;
    final raced = await Future.wait([
      if (o1 != null)
        c.checkout(
          orderId: o1,
          jwt: c.buyerJwt,
          buyer: b1,
          productId: a2pid,
          seller: s1,
          amount: 12,
        )
      else
        Future.value(a2i1),
      if (o2 != null)
        c.checkout(
          orderId: o2,
          jwt: c.buyer2Jwt,
          buyer: b2,
          productId: a2pid,
          seller: s1,
          amount: 12,
        )
      else
        Future.value(a2i2),
    ]);
    a2c1 = raced[0];
    a2c2 = raced[1];
  }
  final a2rows = a2pid == null ? <Map<String, dynamic>>[] : await c.ordersForProduct(a2pid);
  final a2heldH = a2pid == null ? null : await c.heldQty(a2pid);
  final a2held = a2heldH == null ? -1 : c.heldQtyNum(a2heldH);
  final a2prod = a2pid == null ? null : await c.productRow(a2pid);
  final a2hub = a2pid == null ? null : await c.hubSku(a2pid, jwt: c.buyerJwt);
  final a2claims = c.liveClaims(a2rows);
  final a2cs = [a2c1, a2c2].where(c.usefulCs).length;
  final a2oversell = a2claims >= 2 || a2cs >= 2;
  if (a2oversell) {
    c.hold(
      id: 'P1-A2-TWO-CPI',
      lens: 'EI-A',
      severity: 'P1',
      title: '2 buyers CPI qty=1: dois cs_ e/ou dois holds',
      actor: 'B1∥B2 CPI',
      pre: 'SKU qty=1',
      repro: 'insert seq + Future.wait CPI',
      expected: '≤1 cs_ open + ≤1 hold',
      obtained: {
        'cs': a2cs,
        'claims': a2claims,
        'c1': a2c1?.brief,
        'c2': a2c2?.brief,
        'sid1': a2c1?.sessionId,
        'sid2': a2c2?.sessionId,
      },
    );
  } else {
    c.block('A2', 'EI-A', '2 buyers CPI ≤1', {
      'cs': a2cs,
      'claims': a2claims,
      'c1': a2c1?.brief,
      'c2': a2c2?.brief,
    });
  }
  c.probe(
    id: 'A2',
    surfaces: 'CPI + orders + hold + Hub',
    action: '2 buyers CPI paralelo qty=1',
    http: {
      'i1': a2i1?.brief,
      'i2': a2i2?.brief,
      'c1': a2c1?.brief,
      'c2': a2c2?.brief,
    },
    oracles: {
      ...claimSnap(a2rows, held: a2held, prod: a2prod, hubN: a2hub?.list.length),
      'cs_n': a2cs,
      'sid1': a2c1?.sessionId,
      'sid2': a2c2?.sessionId,
      'reused1': a2c1?.reused,
      'reused2': a2c2?.reused,
    },
    result: a2oversell ? 'FAIL' : 'HOLD',
    lens: 'EI-A',
    classeNova: true,
    race: true,
    countFinding: a2oversell,
  );

  await pause(800);

  // A3 — bag B1 ∥ single B2 mesmo SKU (bag∥Hub)
  final a3shared = await c.createProduct(
    title: '$prefix A3 shared',
    qty: 1,
    price: 10,
  );
  final a3pad1 = await c.createProduct(title: '$prefix A3 pad1', qty: 2, price: 8);
  final a3pad2 = await c.createProduct(title: '$prefix A3 pad2', qty: 2, price: 8);
  HttpHit? a3bag;
  HttpHit? a3single;
  String? a3oSharedB1;
  String? a3oSharedB2;
  if (a3shared != null && a3pad1 != null && a3pad2 != null) {
    a3oSharedB1 = await c.insertOrder(
      productId: a3shared,
      jwt: c.buyerJwt,
      buyer: b1,
      price: 10,
    );
    final oPad1 = await c.insertOrder(
      productId: a3pad1,
      jwt: c.buyerJwt,
      buyer: b1,
      price: 8,
    );
    final oPad2 = await c.insertOrder(
      productId: a3pad2,
      jwt: c.buyerJwt,
      buyer: b1,
      price: 8,
    );
    a3oSharedB2 = (await c.insertOrderHit(
      productId: a3shared,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 10,
    ))
        .firstId;
    if (a3oSharedB1 != null && oPad1 != null && oPad2 != null) {
      final raced = await Future.wait([
        c.checkoutBag(
          lines: [
            {'order_id': a3oSharedB1, 'product_id': a3shared},
            {'order_id': oPad1, 'product_id': a3pad1},
            {'order_id': oPad2, 'product_id': a3pad2},
          ],
          jwt: c.buyerJwt,
          buyer: b1,
          seller: s1,
          amount: 1,
        ),
        if (a3oSharedB2 != null)
          c.checkout(
            orderId: a3oSharedB2,
            jwt: c.buyer2Jwt,
            buyer: b2,
            productId: a3shared,
            seller: s1,
            amount: 10,
          )
        else
          Future.value(HttpHit(0, 'no_b2_order', null)),
      ]);
      a3bag = raced[0];
      a3single = raced[1];
    }
  }
  final a3rows =
      a3shared == null ? <Map<String, dynamic>>[] : await c.ordersForProduct(a3shared);
  final a3heldH = a3shared == null ? null : await c.heldQty(a3shared);
  final a3held = a3heldH == null ? -1 : c.heldQtyNum(a3heldH);
  final a3prod = a3shared == null ? null : await c.productRow(a3shared);
  final a3hub = a3shared == null ? null : await c.hubSku(a3shared, jwt: c.buyerJwt);
  final a3claims = c.liveClaims(a3rows);
  final a3cs = [a3bag, a3single].where(c.usefulCs).length;
  final a3fail = a3claims >= 2;
  if (a3fail) {
    c.hold(
      id: 'P1-A3-BAG-HUB',
      lens: 'EI-A',
      severity: 'P1',
      title: 'bag∥single mesmo SKU qty=1: dois stock claims',
      actor: 'B1 bag ∥ B2 Hub single',
      pre: 'SKU qty=1 + 2 pads',
      repro: 'Future.wait checkoutBag + checkout single',
      expected: '≤1 hold efectivo no SKU partilhado',
      obtained: {
        'claims': a3claims,
        'cs': a3cs,
        'bag': a3bag?.brief,
        'single': a3single?.brief,
        'held': a3held,
      },
    );
  } else {
    c.block('A3', 'EI-A', 'bag∥Hub ≤1 claim no SKU', {
      'claims': a3claims,
      'cs': a3cs,
      'bag': a3bag?.brief,
      'single': a3single?.brief,
    });
  }
  c.probe(
    id: 'A3',
    surfaces: 'bag + Hub single + hold + products',
    action: 'bag B1 ∥ single B2 mesmo SKU qty=1',
    http: {'bag': a3bag?.brief, 'single': a3single?.brief},
    oracles: {
      ...claimSnap(a3rows, held: a3held, prod: a3prod, hubN: a3hub?.list.length),
      'cs_n': a3cs,
      'sid_bag': a3bag?.sessionId,
      'sid_single': a3single?.sessionId,
    },
    result: a3fail ? 'FAIL' : 'HOLD',
    lens: 'EI-A',
    classeNova: true,
    race: true,
    countFinding: a3fail,
  );

  await pause();

  // A4 — favorite + hold + 2.º
  final a4pid = await c.createProduct(
    title: '$prefix A4 fav',
    qty: 1,
    price: 13,
  );
  HttpHit? a4fav;
  HttpHit? a4i1;
  HttpHit? a4i2;
  HttpHit? a4favRow;
  if (a4pid != null) {
    a4fav = await c.favorite(a4pid, jwt: c.buyerJwt, user: b1);
    a4i1 = await c.insertOrderHit(
      productId: a4pid,
      jwt: c.buyerJwt,
      buyer: b1,
      price: 13,
    );
    a4i2 = await c.insertOrderHit(
      productId: a4pid,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 13,
    );
    a4favRow = await c.favRow(a4pid, b1);
  }
  final a4rows = a4pid == null ? <Map<String, dynamic>>[] : await c.ordersForProduct(a4pid);
  final a4heldH = a4pid == null ? null : await c.heldQty(a4pid);
  final a4held = a4heldH == null ? -1 : c.heldQtyNum(a4heldH);
  final a4prod = a4pid == null ? null : await c.productRow(a4pid);
  final a4hub = a4pid == null ? null : await c.hubSku(a4pid, jwt: c.buyerJwt);
  final a4claims = c.liveClaims(a4rows);
  final a4fail = a4claims >= 2;
  if (a4fail) {
    c.hold(
      id: 'P1-A4-FAV-HOLD',
      lens: 'EI-A',
      severity: 'P1',
      title: 'favorite+hold não impediu 2.º dono qty=1',
      actor: 'B1 fav+insert · B2 insert',
      pre: 'SKU qty=1',
      repro: 'POST favorites; insert B1; insert B2',
      expected: '≤1 hold; fav ≠ stock claim extra',
      obtained: {
        'claims': a4claims,
        'i1': a4i1?.brief,
        'i2': a4i2?.brief,
        'fav': a4fav?.brief,
      },
    );
  } else {
    c.block('A4', 'EI-A', 'fav+hold 2.º recusado', {
      'claims': a4claims,
      'i1': a4i1?.brief,
      'i2': a4i2?.brief,
      'fav_n': a4favRow?.list.length,
    });
  }
  c.probe(
    id: 'A4',
    surfaces: 'favorites + orders + hold + Hub',
    action: 'favorite B1 + hold + insert B2',
    http: {'fav': a4fav?.brief, 'i1': a4i1?.brief, 'i2': a4i2?.brief},
    oracles: {
      ...claimSnap(a4rows, held: a4held, prod: a4prod, hubN: a4hub?.list.length),
      'fav_n': a4favRow?.list.length,
    },
    result: a4fail ? 'FAIL' : 'HOLD',
    lens: 'EI-A',
    classeNova: true,
    countFinding: a4fail,
  );

  // A5 — cancel/refund → Hub restore
  final a5pid = await c.createProduct(
    title: '$prefix A5 cancel',
    qty: 1,
    price: 14,
    listed: true,
  );
  HttpHit? a5ins;
  HttpHit? a5hubHold;
  HttpHit? a5can;
  HttpHit? a5hubAfter;
  Map<String, dynamic>? a5prodHold;
  Map<String, dynamic>? a5prodAfter;
  if (a5pid != null) {
    a5ins = await c.insertOrderHit(
      productId: a5pid,
      jwt: c.buyerJwt,
      buyer: b1,
      price: 14,
    );
    a5prodHold = await c.productRow(a5pid);
    a5hubHold = await c.hubSku(a5pid, jwt: c.buyerJwt);
    final oid = a5ins.firstId;
    if (oid != null) {
      a5can = await c.cancelOrder(oid, jwt: c.buyerJwt);
      if (!a5can.ok) {
        a5can = await c.cancelOrder(oid, service: true);
      }
    }
    a5prodAfter = await c.productRow(a5pid);
    a5hubAfter = await c.hubSku(a5pid, jwt: c.buyerJwt);
  }
  final a5rows = a5pid == null ? <Map<String, dynamic>>[] : await c.ordersForProduct(a5pid);
  final a5heldAfterH = a5pid == null ? null : await c.heldQty(a5pid);
  final a5heldAfter = a5heldAfterH == null ? -1 : c.heldQtyNum(a5heldAfterH);
  final hubHoldN = a5hubHold?.list.length ?? -1;
  final hubAfterN = a5hubAfter?.list.length ?? -1;
  final soldAfter = a5prodAfter?['is_sold'] == true;
  final listedAfter = a5prodAfter?['list_on_marketplace'] == true;
  final qtyAfter = numOf(a5prodAfter?['quantity']) ?? -1;
  // Restore fail: still sold/hidden after cancel while qty>=1 listed.
  final a5fail = a5ins != null &&
      a5ins.ok &&
      listedAfter &&
      qtyAfter >= 1 &&
      (soldAfter || hubAfterN == 0) &&
      hubHoldN == 0;
  if (a5fail) {
    c.hold(
      id: 'P2-A5-HUB-RESTORE',
      lens: 'EI-A',
      severity: 'P2',
      title: 'cancel hold não restaurou Hub',
      actor: 'B1 insert + cancel',
      pre: 'SKU qty=1 listed',
      repro: 'insert reserva_pendente; PATCH cancelado; hub_products_public',
      expected: 'após cancel Hub lista de novo se qty≥1 listed',
      obtained: {
        'hub_hold': hubHoldN,
        'hub_after': hubAfterN,
        'sold_after': soldAfter,
        'qty': qtyAfter,
        'can': a5can?.brief,
      },
    );
  } else {
    c.block('A5', 'EI-A', 'cancel/refund Hub restore', {
      'hub_hold': hubHoldN,
      'hub_after': hubAfterN,
      'sold_after': soldAfter,
      'qty': qtyAfter,
      'held': a5heldAfter,
      'can': a5can?.brief,
    });
  }
  c.probe(
    id: 'A5',
    surfaces: 'orders + Hub + products',
    action: 'cancel hold → Hub restore',
    http: {
      'ins': a5ins?.brief,
      'can': a5can?.brief,
      'hub_hold': a5hubHold?.brief,
      'hub_after': a5hubAfter?.brief,
    },
    oracles: {
      ...claimSnap(a5rows, held: a5heldAfter, prod: a5prodAfter, hubN: hubAfterN),
      'hub_hold_n': hubHoldN,
      'prod_hold_sold': a5prodHold?['is_sold'],
    },
    result: a5fail ? 'FAIL' : 'HOLD',
    lens: 'EI-A',
    countFinding: a5fail,
  );
}

Future<void> runB(
  Rtdu c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  // B1 — sold+listed vs Hub (1 residual clássico anti-atrofia)
  final b1pid = await c.createProduct(
    title: '$prefix B1 sold listed',
    qty: 0,
    price: 15,
    listed: true,
    sold: true,
  );
  final b1hubBuyer = b1pid == null ? null : await c.hubSku(b1pid, jwt: c.buyerJwt);
  final b1hubAnon = b1pid == null ? null : await c.hubSku(b1pid, anon: true);
  final b1prod = b1pid == null ? null : await c.productRow(b1pid);
  final leak = (b1hubBuyer?.list.length ?? 0) > 0 || (b1hubAnon?.list.length ?? 0) > 0;
  if (leak) {
    c.hold(
      id: 'P2-B1-HUB-SOLD',
      lens: 'EI-B',
      severity: 'P2',
      title: 'Hub mostra SKU sold+listed',
      actor: 'buyer JWT + anon',
      pre: 'is_sold=true list_on_marketplace=true qty=0',
      repro: 'GET hub_products_public',
      expected: 'Hub 0',
      obtained: {
        'buyer': b1hubBuyer?.list.length,
        'anon': b1hubAnon?.list.length,
        'prod': b1prod,
      },
    );
  } else {
    c.block('B1', 'EI-B', 'Hub hide sold clássico', {
      'buyer_n': b1hubBuyer?.list.length,
      'anon_n': b1hubAnon?.list.length,
    });
  }
  c.probe(
    id: 'B1',
    surfaces: 'hub_products_public + products',
    action: 'sold+listed vs Hub hide',
    http: {'buyer': b1hubBuyer?.brief, 'anon': b1hubAnon?.brief},
    oracles: {
      'buyer_n': b1hubBuyer?.list.length,
      'anon_n': b1hubAnon?.list.length,
      'sold': b1prod?['is_sold'],
      'listed': b1prod?['list_on_marketplace'],
      'qty': b1prod?['quantity'],
    },
    result: leak ? 'FAIL' : 'HOLD',
    lens: 'EI-B',
    residual: true,
    countFinding: leak,
  );

  // B3 — rifa drawn ∥ CPI (antes de B2 pago para não misturar caixa)
  await pause(600);
  final fxb = await makeLiveRaffle(c, s1: s1, title: 'B3 draw-cpi');
  HttpHit? b3draw;
  HttpHit? b3cpi;
  HttpHit? b3ins;
  HttpHit? b3hub;
  Map<String, dynamic>? b3prod;
  Map<String, dynamic>? b3li;
  var b3win = 0;
  if (fxb.raf != null && fxb.sku != null) {
    await seedTickets(c, raf: fxb.raf!, user: b1);
    await c.closeRaffle(fxb.raf!);
    b3ins = await c.insertOrderHit(
      productId: fxb.sku!,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 9.0,
    );
    final oid = b3ins.firstId;
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
        Future.value(b3ins),
    ]);
    b3draw = raced[0];
    b3cpi = raced[1];
    b3win = (await c.raffleWinners(fxb.raf!)).length;
    b3prod = await c.productRow(fxb.sku!);
    b3li = fxb.li == null ? null : await c.liveItemRow(fxb.li!);
    b3hub = await c.hubSku(fxb.sku!, jwt: c.buyerJwt);
  }
  final b3q = numOf(b3prod?['quantity']) ?? -1;
  final b3hubN = b3hub?.list.length ?? -1;
  final b3both = b3win >= 1 && c.usefulCs(b3cpi);
  final b3fail = b3both && (b3hubN > 0 || b3q >= 1);
  if (b3fail) {
    c.hold(
      id: 'P1-B3-DRAW-CPI',
      lens: 'EI-B',
      severity: 'P1',
      title: 'rifa drawn∥CPI deixou SKU comprável',
      actor: 'S1 draw ∥ B2 CPI',
      pre: 'qty=1 hitch closed com tickets',
      repro: 'Future.wait draw + CPI',
      expected: 'Hub 0 se drawn; sem 2.º cs_ útil',
      obtained: {
        'draw': b3draw?.brief,
        'cpi': b3cpi?.brief,
        'qty': b3q,
        'hub_n': b3hubN,
        'nWin': b3win,
      },
    );
  } else {
    c.block('B3', 'EI-B', 'draw∥CPI', {
      'draw': b3draw?.brief,
      'cpi': b3cpi?.brief,
      'qty': b3q,
      'hub_n': b3hubN,
      'nWin': b3win,
      'cs': c.usefulCs(b3cpi),
      'li': b3li?['status'],
    });
  }
  c.probe(
    id: 'B3',
    surfaces: 'rifa + CPI + Hub + products + live_item',
    action: 'rifa drawn ∥ CPI qty=1',
    http: {'draw': b3draw?.brief, 'cpi': b3cpi?.brief, 'ins': b3ins?.brief},
    oracles: {
      'qty': b3q,
      'hub_n': b3hubN,
      'nWin': b3win,
      'cs': b3cpi?.sessionId,
      'li': b3li?['status'],
      'li_open': liOpen(b3li),
    },
    result: b3fail ? 'FAIL' : 'HOLD',
    lens: 'EI-B',
    classeNova: true,
    race: true,
    countFinding: b3fail,
  );

  await pause(800);

  // B4 — unlist ∥ CPI
  final b4pid = await c.createProduct(
    title: '$prefix B4 unlist',
    qty: 1,
    price: 16,
    listed: true,
  );
  HttpHit? b4ins;
  HttpHit? b4unlist;
  HttpHit? b4cpi;
  if (b4pid != null) {
    b4ins = await c.insertOrderHit(
      productId: b4pid,
      jwt: c.buyerJwt,
      buyer: b1,
      price: 16,
    );
    final oid = b4ins.firstId;
    final raced = await Future.wait([
      c.unlistProduct(b4pid),
      if (oid != null)
        c.checkout(
          orderId: oid,
          jwt: c.buyerJwt,
          buyer: b1,
          productId: b4pid,
          seller: s1,
          amount: 16,
        )
      else
        Future.value(b4ins),
    ]);
    b4unlist = raced[0];
    b4cpi = raced[1];
  }
  final b4prod = b4pid == null ? null : await c.productRow(b4pid);
  final b4hub = b4pid == null ? null : await c.hubSku(b4pid, jwt: c.buyerJwt);
  final b4rows = b4pid == null ? <Map<String, dynamic>>[] : await c.ordersForProduct(b4pid);
  final listed = b4prod?['list_on_marketplace'] == true;
  final hubN = b4hub?.list.length ?? -1;
  // FAIL: still listed+Hub after unlist, OR Hub shows unlisted SKU, OR 2 claims.
  final b4claims = c.liveClaims(b4rows);
  final unlisted = listed == false;
  final hubGhost = unlisted && hubN > 0;
  final b4fail = hubGhost || b4claims >= 2;
  if (b4fail) {
    c.hold(
      id: 'P1-B4-UNLIST-CPI',
      lens: 'EI-B',
      severity: hubGhost ? 'P2' : 'P1',
      title: hubGhost
          ? 'unlist∥CPI Hub ainda lista SKU unlisted'
          : 'unlist∥CPI dois stock claims',
      actor: 'S1 unlist ∥ B1 CPI',
      pre: 'SKU qty=1 listed',
      repro: 'Future.wait unlist + CPI',
      expected: 'Hub 0 se unlisted; ≤1 hold',
      obtained: {
        'unlist': b4unlist?.brief,
        'cpi': b4cpi?.brief,
        'listed': listed,
        'hub_n': hubN,
        'claims': b4claims,
      },
    );
  } else {
    c.block('B4', 'EI-B', 'unlist∥CPI Hub/hold coerente', {
      'unlist': b4unlist?.brief,
      'cpi': b4cpi?.brief,
      'listed': listed,
      'hub_n': hubN,
      'cs': c.usefulCs(b4cpi),
      'claims': b4claims,
    });
  }
  c.probe(
    id: 'B4',
    surfaces: 'products unlist + CPI + Hub',
    action: 'unlist ∥ CPI',
    http: {'unlist': b4unlist?.brief, 'cpi': b4cpi?.brief, 'ins': b4ins?.brief},
    oracles: {
      'listed': listed,
      'hub_n': hubN,
      'cs': b4cpi?.sessionId,
      'claims': b4claims,
    },
    result: b4fail ? 'FAIL' : 'HOLD',
    lens: 'EI-B',
    classeNova: true,
    race: true,
    countFinding: b4fail,
  );

  await pause(600);

  // B5 — end_live ∥ bag
  final b5sku = await c.createProduct(
    title: '$prefix B5 hitch',
    qty: 1,
    price: 9,
    listed: true,
    live: true,
  );
  final b5pad = await c.createProduct(title: '$prefix B5 pad', qty: 2, price: 8);
  final b5live = await c.createLive(title: '$prefix B5 endbag');
  String? b5li;
  if (b5live != null && b5sku != null) {
    b5li = await c.createLiveItem(
      liveId: b5live,
      title: '$prefix B5-li',
      kind: 'marketplace_product',
      productId: b5sku,
    );
  }
  HttpHit? b5end;
  HttpHit? b5bag;
  if (b5sku != null && b5pad != null && b5live != null) {
    final oSku = await c.insertOrder(
      productId: b5sku,
      jwt: c.buyerJwt,
      buyer: b1,
      price: 9,
    );
    final oPad = await c.insertOrder(
      productId: b5pad,
      jwt: c.buyerJwt,
      buyer: b1,
      price: 8,
    );
    if (oSku != null && oPad != null) {
      final raced = await Future.wait([
        c.rest(
          'PATCH',
          'lives?id=eq.$b5live',
          service: true,
          body: {'status': 'ended', 'is_active': false},
          prefer: 'return=representation',
        ),
        c.checkoutBag(
          lines: [
            {'order_id': oSku, 'product_id': b5sku},
            {'order_id': oPad, 'product_id': b5pad},
          ],
          jwt: c.buyerJwt,
          buyer: b1,
          seller: s1,
          amount: 1,
        ),
      ]);
      b5end = raced[0];
      b5bag = raced[1];
    }
  }
  final b5prod = b5sku == null ? null : await c.productRow(b5sku);
  final b5hub = b5sku == null ? null : await c.hubSku(b5sku, jwt: c.buyerJwt);
  final b5rows = b5sku == null ? <Map<String, dynamic>>[] : await c.ordersForProduct(b5sku);
  final b5liRow = b5li == null ? null : await c.liveItemRow(b5li);
  final b5claims = c.liveClaims(b5rows);
  final liveEnded = '${b5end?.map?['status'] ?? ''}' == 'ended' ||
      (b5end?.ok == true);
  final b5fail = b5claims >= 2;
  if (b5fail) {
    c.hold(
      id: 'P1-B5-END-BAG',
      lens: 'EI-B',
      severity: 'P1',
      title: 'end_live∥bag criou 2 stock claims',
      actor: 'svc end_live ∥ B1 bag',
      pre: 'hitch qty=1 + pad',
      repro: 'Future.wait end_live + checkoutBag',
      expected: '≤1 hold no hitch',
      obtained: {
        'end': b5end?.brief,
        'bag': b5bag?.brief,
        'claims': b5claims,
      },
    );
  } else {
    c.block('B5', 'EI-B', 'end_live∥bag ≤1 claim', {
      'end': b5end?.brief,
      'bag': b5bag?.brief,
      'claims': b5claims,
      'cs': c.usefulCs(b5bag),
      'ended': liveEnded,
    });
  }
  c.probe(
    id: 'B5',
    surfaces: 'lives + bag + Hub + live_item',
    action: 'end_live ∥ bag hitch qty=1',
    http: {'end': b5end?.brief, 'bag': b5bag?.brief},
    oracles: {
      'claims': b5claims,
      'cs': b5bag?.sessionId,
      'hub_n': b5hub?.list.length,
      'qty': b5prod?['quantity'],
      'li': b5liRow?['status'],
      'ended': liveEnded,
    },
    result: b5fail ? 'FAIL' : 'HOLD',
    lens: 'EI-B',
    classeNova: true,
    race: true,
    countFinding: b5fail,
  );
}

Future<void> runC(
  Rtdu c, {
  required String s1,
  required String b1,
  required String b2,
  required String s2,
}) async {
  await pause(800);
  // C1 — 6∥4 overlap: stock holds coerentes (≤1 dono efectivo por SKU)
  final c1skus = <String>[];
  for (var i = 0; i < 6; i++) {
    final id = await c.createProduct(
      title: '$prefix C1 sku$i',
      qty: 1,
      price: 7.0 + i,
    );
    if (id != null) c1skus.add(id);
  }
  HttpHit? c1bag6;
  HttpHit? c1bag4;
  final c1oids = <String>[];
  if (c1skus.length == 6) {
    for (final pid in c1skus) {
      final oid = await c.insertOrder(
        productId: pid,
        jwt: c.buyerJwt,
        buyer: b1,
        price: 7,
      );
      if (oid != null) c1oids.add(oid);
    }
    if (c1oids.length == 6) {
      final lines6 = <Map<String, Object?>>[];
      for (var i = 0; i < 6; i++) {
        lines6.add({'order_id': c1oids[i], 'product_id': c1skus[i]});
      }
      final lines4 = <Map<String, Object?>>[];
      for (var i = 1; i < 5; i++) {
        lines4.add({'order_id': c1oids[i], 'product_id': c1skus[i]});
      }
      final raced = await Future.wait([
        c.checkoutBag(
          lines: lines6,
          jwt: c.buyerJwt,
          buyer: b1,
          seller: s1,
          amount: 1,
        ),
        c.checkoutBag(
          lines: lines4,
          jwt: c.buyerJwt,
          buyer: b1,
          seller: s1,
          amount: 1,
        ),
      ]);
      c1bag6 = raced[0];
      c1bag4 = raced[1];
    }
  }
  final overlapIds = c1skus.length >= 5 ? c1skus.sublist(1, 5) : c1skus;
  final perSku = <Map<String, Object?>>[];
  var doubleClaim = 0;
  for (final pid in overlapIds) {
    final rows = await c.ordersForProduct(pid);
    final claims = c.liveClaims(rows);
    final heldH = await c.heldQty(pid);
    final held = c.heldQtyNum(heldH);
    if (claims >= 2 || (held is num && held >= 2)) doubleClaim++;
    perSku.add({
      'pid': pid,
      'claims': claims,
      'held': held,
      'sids': rows.map((e) => e['stripe_checkout_session_id']).toSet().toList(),
    });
  }
  final c1cs = [c1bag6, c1bag4].where(c.usefulCs).length;
  final c1fail = doubleClaim > 0;
  if (c1fail) {
    c.hold(
      id: 'P1-C1-OVERLAP-STOCK',
      lens: 'EI-C',
      severity: 'P1',
      title: 'overlap 6∥4 criou 2 stock claims no mesmo SKU',
      actor: 'B1 bag6 ∥ bag4',
      pre: '6 SKU qty=1',
      repro: 'Future.wait checkoutBag 6 + 4 overlap',
      expected: '≤1 dono efectivo por SKU (2 cs_ órfãs OK se ledger 1)',
      obtained: {'doubleClaim': doubleClaim, 'cs': c1cs, 'perSku': perSku},
    );
  } else {
    c.block('C1', 'EI-C', '6∥4 stock ≤1 dono/SKU', {
      'cs': c1cs,
      'doubleClaim': doubleClaim,
      'sid6': c1bag6?.sessionId,
      'sid4': c1bag4?.sessionId,
    });
  }
  c.probe(
    id: 'C1',
    surfaces: 'bag overlap + hold + products',
    action: '6∥4 overlap stock holds coerentes',
    http: {'bag6': c1bag6?.brief, 'bag4': c1bag4?.brief},
    oracles: {
      'cs_n': c1cs,
      'doubleClaim': doubleClaim,
      'sid6': c1bag6?.sessionId,
      'sid4': c1bag4?.sessionId,
      'reused6': c1bag6?.reused,
      'reused4': c1bag4?.reused,
      'perSku': perSku,
    },
    result: c1fail ? 'FAIL' : 'HOLD',
    lens: 'EI-C',
    classeNova: true,
    race: true,
    countFinding: c1fail,
  );

  await pause(600);

  // C2 — cross-seller bag deny
  final c2s1 = await c.createProduct(
    title: '$prefix C2 s1',
    qty: 2,
    price: 12,
  );
  final c2s2 = await c.createProduct(
    title: '$prefix C2 s2',
    qty: 2,
    price: 14,
    seller: s2,
  );
  HttpHit? c2bag;
  if (c2s1 != null && c2s2 != null) {
    final o1 = await c.insertOrder(
      productId: c2s1,
      jwt: c.buyerJwt,
      buyer: b1,
      price: 12,
    );
    final o2 = await c.insertOrder(
      productId: c2s2,
      jwt: c.buyerJwt,
      buyer: b1,
      seller: s2,
      price: 14,
    );
    if (o1 != null && o2 != null) {
      c2bag = await c.checkoutBag(
        lines: [
          {'order_id': o1, 'product_id': c2s1},
          {'order_id': o2, 'product_id': c2s2, 'seller_id': s2},
        ],
        jwt: c.buyerJwt,
        buyer: b1,
        seller: s1,
        amount: 1,
      );
    }
  }
  final c2fail = c.usefulCs(c2bag);
  if (c2fail) {
    c.hold(
      id: 'P1-C2-CROSS-SELLER',
      lens: 'EI-C',
      severity: 'P1',
      title: 'bag cross-seller criou Session',
      actor: 'B1 bag S1+S2',
      pre: '1 order S1 + 1 order S2',
      repro: 'checkoutBag 2 sellers',
      expected: '400 one seller / cross-seller deny',
      obtained: c2bag?.brief,
    );
  } else {
    c.block('C2', 'EI-C', 'bag cross-seller deny', c2bag?.brief);
  }
  c.probe(
    id: 'C2',
    surfaces: 'bag CPI + 2 sellers',
    action: 'cross-seller bag deny',
    http: c2bag?.brief ?? 'n/a',
    oracles: {'cs': c2bag?.sessionId, 'denied': denied(c2bag ?? HttpHit(0, '', null))},
    result: c2fail ? 'FAIL' : 'HOLD',
    lens: 'EI-C',
    classeNova: true,
    countFinding: c2fail,
  );

  // C3 — qty hostil body
  final c3pid = await c.createProduct(
    title: '$prefix C3 qty',
    qty: 1,
    price: 16,
  );
  HttpHit? c3patch;
  HttpHit? c3cpi;
  HttpHit? c3ins;
  Map<String, dynamic>? c3ord;
  Map<String, dynamic>? c3prod;
  if (c3pid != null) {
    c3ins = await c.insertOrderHit(
      productId: c3pid,
      jwt: c.buyerJwt,
      buyer: b1,
      qty: 1,
      price: 16,
    );
    final oid = c3ins.firstId;
    if (oid != null) {
      c3patch = await c.rest(
        'PATCH',
        'orders?id=eq.$oid',
        jwt: c.buyerJwt,
        body: {'quantity': 99},
      );
      c3cpi = await c.checkout(
        orderId: oid,
        jwt: c.buyerJwt,
        buyer: b1,
        productId: c3pid,
        seller: s1,
        amount: 1,
        quantity: 99,
      );
      c3ord = await c.orderRow(oid);
    }
    c3prod = await c.productRow(c3pid);
  }
  final c3qty = numOf(c3ord?['quantity']) ?? -1;
  final c3prodQty = numOf(c3prod?['quantity']) ?? -1;
  final c3applied = numOf(c3ord?['stock_units_applied']);
  final c3fail = (c3qty >= 2 && c3prodQty < 2) ||
      (c3applied != null && c3applied >= 2 && c3prodQty < 2);
  if (c3fail) {
    c.hold(
      id: 'P1-C3-QTY-HOSTIL',
      lens: 'EI-C',
      severity: 'P1',
      title: 'qty hostil 99 aplicou stock > available',
      actor: 'B1 PATCH+CPI quantity=99',
      pre: 'SKU qty=1',
      repro: 'PATCH orders.quantity=99; CPI quantity=99',
      expected: 'qty efectiva 1 / CPI deny; stock products inalterado oversell',
      obtained: {
        'patch': c3patch?.brief,
        'cpi': c3cpi?.brief,
        'ord_qty': c3qty,
        'prod_qty': c3prodQty,
        'applied': c3applied,
      },
    );
  } else {
    c.block('C3', 'EI-C', 'qty hostil clamp/deny', {
      'patch': c3patch?.brief,
      'cpi': c3cpi?.brief,
      'ord_qty': c3qty,
      'prod_qty': c3prodQty,
      'cs': c.usefulCs(c3cpi),
    });
  }
  c.probe(
    id: 'C3',
    surfaces: 'orders PATCH + CPI body + products',
    action: 'qty hostil 99 body',
    http: {'patch': c3patch?.brief, 'cpi': c3cpi?.brief, 'ins': c3ins?.brief},
    oracles: {
      'ord_qty': c3qty,
      'prod_qty': c3prodQty,
      'applied': c3applied,
      'cs': c3cpi?.sessionId,
      'patch_status': c3patch?.status,
    },
    result: c3fail ? 'FAIL' : 'HOLD',
    lens: 'EI-C',
    classeNova: true,
    countFinding: c3fail,
  );
}

Future<void> runD(
  Rtdu c, {
  required String s1,
  required String b1,
  required String b2,
}) async {
  await pause(800);
  // D1 + B2 — pago 4242 leftover qty 2→1 + Hub
  final paid = await c.payToPago(lens: 'EI-D', initialQty: 2);
  HttpHit? d1hub;
  Map<String, dynamic>? d1prod;
  Map<String, dynamic>? d1ord;
  if (paid != null) {
    d1prod = await c.productRow(paid.pid);
    d1ord = await c.orderRow(paid.oid);
    d1hub = await c.hubSku(paid.pid, jwt: c.buyerJwt);
  }
  final d1q = numOf(d1prod?['quantity']) ?? -1;
  final d1hubN = d1hub?.list.length ?? -1;
  final d1status = '${d1ord?['status'] ?? ''}';
  final d1pago = d1status.toLowerCase() == 'pago';
  final d1pi = '${d1ord?['stripe_payment_intent_id'] ?? paid?.pi ?? ''}';
  final leftoverWrong = paid != null && d1pago && d1q != 1;
  final hubWrong = paid != null &&
      d1pago &&
      ((d1q >= 1 && d1hubN == 0 && d1prod?['list_on_marketplace'] == true && d1prod?['is_sold'] != true) ||
          (d1q < 1 && d1hubN > 0));
  final d1fail = leftoverWrong || hubWrong;
  if (paid == null) {
    c.skip('D1', 'EI-D', 'setup_paid_order fail', 'null');
    c.skip('B2', 'EI-B', 'setup_paid_order fail', 'null');
  } else if (d1fail) {
    c.hold(
      id: leftoverWrong ? 'P1-D1-LEFTOVER' : 'P2-D1-HUB-LEFTOVER',
      lens: 'EI-D',
      severity: leftoverWrong ? 'P1' : 'P2',
      title: leftoverWrong
          ? 'Pago 4242 qty 2 não ficou leftover 1'
          : 'Pago 4242 leftover Hub incoerente',
      actor: 'e2e setup_paid_order',
      pre: 'SKU qty=2',
      repro: 'setup_paid_order + hub_products_public',
      expected: 'status pago; qty leftover 1; Hub 1 se listed unsold',
      obtained: {
        'status': d1status,
        'qty': d1q,
        'hub_n': d1hubN,
        'pi': d1pi,
        'sold': d1prod?['is_sold'],
        'listed': d1prod?['list_on_marketplace'],
      },
    );
  } else {
    c.block('D1', 'EI-D', 'pago 4242 + Hub leftover', {
      'status': d1status,
      'qty': d1q,
      'hub_n': d1hubN,
      'pi': d1pi,
      'oid': paid.oid,
    });
  }
  c.probe(
    id: 'D1',
    surfaces: 'orders + Hub + products + Stripe',
    action: 'pago 4242 + Hub leftover',
    http: paid?.hit ?? HttpHit(0, 'null', null),
    oracles: {
      'status': d1status,
      'qty': d1q,
      'hub_n': d1hubN,
      'pi': d1pi,
      'amount': d1ord?['amount_paid_cents'],
      'sold': d1prod?['is_sold'],
      'listed': d1prod?['list_on_marketplace'],
    },
    result: paid == null ? 'SKIP' : (d1fail ? 'FAIL' : 'HOLD'),
    lens: 'EI-D',
    countFinding: d1fail,
  );
  c.probe(
    id: 'B2',
    surfaces: 'products qty + Hub após pago',
    action: 'leftover qty 2→1 após pago',
    http: paid?.hit ?? HttpHit(0, 'null', null),
    oracles: {
      'qty': d1q,
      'hub_n': d1hubN,
      'status': d1status,
      'applied': d1ord?['stock_units_applied'],
    },
    result: paid == null ? 'SKIP' : (leftoverWrong ? 'FAIL' : 'HOLD'),
    lens: 'EI-B',
    countFinding: leftoverWrong,
  );

  // D2 — 2.º insert após pago (qty=1 consumido)
  await pause(600);
  final paid1 = await c.payToPago(lens: 'EI-D', initialQty: 1);
  HttpHit? d2ins;
  HttpHit? d2hub;
  Map<String, dynamic>? d2prod;
  Map<String, dynamic>? d2ord;
  if (paid1 != null) {
    d2ord = await c.orderRow(paid1.oid);
    d2prod = await c.productRow(paid1.pid);
    d2hub = await c.hubSku(paid1.pid, jwt: c.buyerJwt);
    d2ins = await c.insertOrderHit(
      productId: paid1.pid,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 12,
    );
  }
  final d2q = numOf(d2prod?['quantity']) ?? -1;
  final d2hubN = d2hub?.list.length ?? -1;
  final d2pago = '${d2ord?['status'] ?? ''}'.toLowerCase() == 'pago';
  final d2insOk = d2ins?.ok == true;
  final d2fail = paid1 != null && d2pago && d2insOk && d2q < 1;
  if (paid1 == null) {
    c.skip('D2', 'EI-D', 'setup_paid_order qty=1 fail', 'null');
  } else if (d2fail) {
    c.hold(
      id: 'P1-D2-INSERT-AFTER-PAID',
      lens: 'EI-D',
      severity: 'P1',
      title: '2.º insert após pago qty=1 aceite',
      actor: 'B2 insert no SKU já pago',
      pre: 'setup_paid_order initial_qty=1',
      repro: 'pago; insertOrder B2',
      expected: '400 hold / qty_exceeds; Hub 0',
      obtained: {
        'ins': d2ins?.brief,
        'qty': d2q,
        'hub_n': d2hubN,
        'sold': d2prod?['is_sold'],
      },
    );
  } else {
    c.block('D2', 'EI-D', '2.º insert após pago recusado', {
      'ins': d2ins?.brief,
      'qty': d2q,
      'hub_n': d2hubN,
      'sold': d2prod?['is_sold'],
      'pago': d2pago,
    });
  }
  c.probe(
    id: 'D2',
    surfaces: 'orders insert + products + Hub',
    action: '2.º insert após pago qty=1',
    http: {'paid': paid1?.hit.brief, 'ins': d2ins?.brief},
    oracles: {
      'qty': d2q,
      'hub_n': d2hubN,
      'sold': d2prod?['is_sold'],
      'ins_ok': d2insOk,
      'ins_status': d2ins?.status,
      'pi': d2ord?['stripe_payment_intent_id'],
    },
    result: paid1 == null ? 'SKIP' : (d2fail ? 'FAIL' : 'HOLD'),
    lens: 'EI-D',
    classeNova: true,
    countFinding: d2fail,
  );

  // D3 — Hub public vs products qty (oráculo multi-estado)
  final d3listed = await c.createProduct(
    title: '$prefix D3 listed',
    qty: 2,
    price: 9,
    listed: true,
    sold: false,
  );
  final d3sold = await c.createProduct(
    title: '$prefix D3 sold',
    qty: 0,
    price: 9,
    listed: true,
    sold: true,
  );
  final d3unlisted = await c.createProduct(
    title: '$prefix D3 unlisted',
    qty: 3,
    price: 9,
    listed: false,
    sold: false,
  );
  final hListed =
      d3listed == null ? null : await c.hubSku(d3listed, jwt: c.buyerJwt);
  final hSold = d3sold == null ? null : await c.hubSku(d3sold, jwt: c.buyerJwt);
  final hUnlisted =
      d3unlisted == null ? null : await c.hubSku(d3unlisted, jwt: c.buyerJwt);
  final pListed = d3listed == null ? null : await c.productRow(d3listed);
  final pSold = d3sold == null ? null : await c.productRow(d3sold);
  final pUnlisted = d3unlisted == null ? null : await c.productRow(d3unlisted);
  final nListed = hListed?.list.length ?? -1;
  final nSold = hSold?.list.length ?? -1;
  final nUnlisted = hUnlisted?.list.length ?? -1;
  final d3fail = nListed != 1 || nSold != 0 || nUnlisted != 0;
  if (d3fail) {
    c.hold(
      id: 'P2-D3-HUB-QTY',
      lens: 'EI-D',
      severity: 'P2',
      title: 'Hub public ≠ products qty/sold/listed',
      actor: 'buyer JWT hub_products_public',
      pre: '3 SKUs listed-qty2 / sold-qty0 / unlisted-qty3',
      repro: 'GET hub_products_public vs products',
      expected: 'Hub 1 / 0 / 0',
      obtained: {
        'listed': nListed,
        'sold': nSold,
        'unlisted': nUnlisted,
        'pListed': pListed,
        'pSold': pSold,
        'pUnlisted': pUnlisted,
      },
    );
  } else {
    c.block('D3', 'EI-D', 'Hub public vs qty coerente', {
      'listed': nListed,
      'sold': nSold,
      'unlisted': nUnlisted,
    });
  }
  c.probe(
    id: 'D3',
    surfaces: 'hub_products_public + products',
    action: 'Hub public vs products qty/sold/listed',
    http: {
      'listed': hListed?.brief,
      'sold': hSold?.brief,
      'unlisted': hUnlisted?.brief,
    },
    oracles: {
      'hub_listed': nListed,
      'hub_sold': nSold,
      'hub_unlisted': nUnlisted,
      'qty_listed': pListed?['quantity'],
      'qty_sold': pSold?['quantity'],
      'qty_unlisted': pUnlisted?['quantity'],
    },
    result: d3fail ? 'FAIL' : 'HOLD',
    lens: 'EI-D',
    classeNova: true,
    countFinding: d3fail,
  );
}
