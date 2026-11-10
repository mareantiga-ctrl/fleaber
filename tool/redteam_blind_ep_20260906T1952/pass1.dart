/// RED TEAM CEGO EP pass1 — multi-buyer / Hub / live / stock POS_OPEN_GATE ≥24.
/// Staging only. NÃO corrigir. NÃO produção. NÃO Fase 4.
import 'dart:io';

import '_rtep.dart';

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
    'live_claims': liveClaimsOf(rows),
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

int liveClaimsOf(List<Map<String, dynamic>> rows) {
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

Future<({List<String> skus, List<String> oids})> plantBag(
  Rtdu c, {
  required String buyer,
  required String jwt,
  required String tag,
  int n = 6,
  int qty = 1,
  double price = 8,
}) async {
  final skus = <String>[];
  final oids = <String>[];
  for (var i = 0; i < n; i++) {
    final id = await c.createProduct(
      title: '$prefix $tag sku$i',
      qty: qty,
      price: price + i,
    );
    if (id != null) skus.add(id);
  }
  for (final pid in skus) {
    final oid = await c.insertOrder(
      productId: pid,
      jwt: jwt,
      buyer: buyer,
      price: price,
    );
    if (oid != null) oids.add(oid);
  }
  return (skus: skus, oids: oids);
}

List<Map<String, Object?>> bagLines(List<String> oids, List<String> skus,
    {int? from, int? to}) {
  final a = from ?? 0;
  final b = to ?? oids.length;
  final out = <Map<String, Object?>>[];
  for (var i = a; i < b && i < oids.length && i < skus.length; i++) {
    out.add({'order_id': oids[i], 'product_id': skus[i]});
  }
  return out;
}

Future<void> main() async {
  final c = Rtdu.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  stdout.writeln('EP pass1 staging=${c.url} prefix=$prefix');
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureBuyer3();
  await c.ensureSeller2();
  final s1 = c.sellerId!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;
  final b3 = c.buyer3Id!;
  final s2 = c.seller2Id!;
  await c.restoreSeller1Published();
  await c.setHub(s2, false);
  c.note('actors', 'ids', {
    'b1': b1,
    's1': s1,
    'b2': b2,
    'b3': b3,
    's2': s2,
  });

  try {
    await runA(c, s1: s1, b1: b1, b2: b2, b3: b3, s2: s2);
    await runB(c, s1: s1, b1: b1, b2: b2, b3: b3);
    await runC(c, s1: s1, b1: b1, b2: b2, b3: b3);
    await runD(c, s1: s1, b1: b1, b2: b2, b3: b3, s2: s2);
    await runE(c, s1: s1, b1: b1, b2: b2, b3: b3);
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
    'auditor': 'REDTEAM_BLIND_EP_MULTI_BUYER_STRESS_POS_OPEN_v1',
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
    'actors': {'b1': b1, 's1': s1, 'b2': b2, 'b3': b3, 's2': s2},
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
  required String b3,
  required String s2,
}) async {
  // A1 — 3 buyers insert qty=1 (só 1 wins)
  final a1pid = await c.createProduct(
    title: '$prefix A1 qty1 3buyers',
    qty: 1,
    price: 11,
  );
  HttpHit? a1b1;
  HttpHit? a1b2;
  HttpHit? a1b3;
  if (a1pid != null) {
    final raced = await Future.wait([
      c.insertOrderHit(productId: a1pid, jwt: c.buyerJwt, buyer: b1, price: 11),
      c.insertOrderHit(productId: a1pid, jwt: c.buyer2Jwt, buyer: b2, price: 11),
      c.insertOrderHit(productId: a1pid, jwt: c.buyer3Jwt, buyer: b3, price: 11),
    ]);
    a1b1 = raced[0];
    a1b2 = raced[1];
    a1b3 = raced[2];
  }
  final a1rows = a1pid == null ? <Map<String, dynamic>>[] : await c.ordersForProduct(a1pid);
  final a1heldH = a1pid == null ? null : await c.heldQty(a1pid);
  final a1held = a1heldH == null ? -1 : c.heldQtyNum(a1heldH);
  final a1prod = a1pid == null ? null : await c.productRow(a1pid);
  final a1hub = a1pid == null ? null : await c.hubSku(a1pid, jwt: c.buyerJwt);
  final a1claims = c.liveClaims(a1rows);
  final a1ok = [a1b1, a1b2, a1b3].where((h) => h != null && h.ok).length;
  final a1oversell = a1pid != null && a1claims >= 2;
  if (a1oversell) {
    c.hold(
      id: 'P1-A1-THREE-INSERT',
      lens: 'EP-A',
      severity: a1claims >= 2 ? 'P1' : 'P1',
      title: '3 buyers insert qty=1: dois+ holds vivos',
      actor: 'B1∥B2∥B3 JWT insert',
      pre: 'SKU qty=1',
      repro: 'Future.wait insertOrder B1+B2+B3',
      expected: '≤1 hold vivo / 2.º e 3.º 400 hold',
      obtained: {
        'ok': a1ok,
        'claims': a1claims,
        'held': a1held,
        'b1': a1b1?.brief,
        'b2': a1b2?.brief,
        'b3': a1b3?.brief,
      },
    );
  } else {
    c.block('A1', 'EP-A', '3 buyers insert ≤1 hold', {
      'ok': a1ok,
      'claims': a1claims,
      'held': a1held,
      'b1': a1b1?.brief,
      'b2': a1b2?.brief,
      'b3': a1b3?.brief,
    });
  }
  c.probe(
    id: 'A1',
    surfaces: 'orders + hold + Hub + products',
    action: '3 buyers insert qty=1 paralelo',
    http: {
      'b1': a1b1?.brief,
      'b2': a1b2?.brief,
      'b3': a1b3?.brief,
      'held': a1heldH?.brief,
    },
    oracles: claimSnap(a1rows, held: a1held, prod: a1prod, hubN: a1hub?.list.length),
    result: a1oversell ? 'FAIL' : 'HOLD',
    lens: 'EP-A',
    race: true,
    classeNova: true,
    countFinding: a1oversell,
  );

  await pause();

  // A2 — 2 buyers CPI∥CPI qty=1
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
      lens: 'EP-A',
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
    c.block('A2', 'EP-A', '2 buyers CPI ≤1', {
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
    },
    result: a2oversell ? 'FAIL' : 'HOLD',
    lens: 'EP-A',
    race: true,
    countFinding: a2oversell,
  );

  await pause(800);

  // A3 — B1 bag ∥ B2 single ∥ B3 insert mesmo SKU
  final a3shared = await c.createProduct(
    title: '$prefix A3 shared',
    qty: 1,
    price: 10,
  );
  final a3pad1 = await c.createProduct(title: '$prefix A3 pad1', qty: 2, price: 8);
  final a3pad2 = await c.createProduct(title: '$prefix A3 pad2', qty: 2, price: 8);
  HttpHit? a3bag;
  HttpHit? a3single;
  HttpHit? a3ins3;
  if (a3shared != null && a3pad1 != null && a3pad2 != null) {
    final oSharedB1 = await c.insertOrder(
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
    if (oSharedB1 != null && oPad1 != null && oPad2 != null) {
      final raced = await Future.wait([
        c.checkoutBag(
          lines: [
            {'order_id': oSharedB1, 'product_id': a3shared},
            {'order_id': oPad1, 'product_id': a3pad1},
            {'order_id': oPad2, 'product_id': a3pad2},
          ],
          jwt: c.buyerJwt,
          buyer: b1,
          seller: s1,
          amount: 1,
        ),
        c.insertOrderHit(
          productId: a3shared,
          jwt: c.buyer2Jwt,
          buyer: b2,
          price: 10,
        ),
        c.insertOrderHit(
          productId: a3shared,
          jwt: c.buyer3Jwt,
          buyer: b3,
          price: 10,
        ),
      ]);
      a3bag = raced[0];
      a3single = raced[1];
      a3ins3 = raced[2];
    }
  }
  final a3rows =
      a3shared == null ? <Map<String, dynamic>>[] : await c.ordersForProduct(a3shared);
  final a3heldH = a3shared == null ? null : await c.heldQty(a3shared);
  final a3held = a3heldH == null ? -1 : c.heldQtyNum(a3heldH);
  final a3prod = a3shared == null ? null : await c.productRow(a3shared);
  final a3hub = a3shared == null ? null : await c.hubSku(a3shared, jwt: c.buyerJwt);
  final a3claims = c.liveClaims(a3rows);
  final a3fail = a3claims >= 2;
  if (a3fail) {
    c.hold(
      id: 'P1-A3-BAG-SINGLE-INSERT',
      lens: 'EP-A',
      severity: 'P1',
      title: 'bag∥insert B2∥insert B3 mesmo SKU qty=1: dois+ claims',
      actor: 'B1 bag ∥ B2 insert ∥ B3 insert',
      pre: 'SKU qty=1 + 2 pads; B1 já com hold bag',
      repro: 'Future.wait checkoutBag + insert B2 + insert B3',
      expected: '≤1 hold efectivo no SKU partilhado',
      obtained: {
        'claims': a3claims,
        'held': a3held,
        'bag': a3bag?.brief,
        'b2': a3single?.brief,
        'b3': a3ins3?.brief,
      },
    );
  } else {
    c.block('A3', 'EP-A', 'bag∥B2∥B3 ≤1 claim no SKU', {
      'claims': a3claims,
      'bag': a3bag?.brief,
      'b2': a3single?.brief,
      'b3': a3ins3?.brief,
    });
  }
  c.probe(
    id: 'A3',
    surfaces: 'bag + insert B2 + insert B3 + hold + products',
    action: 'bag B1 ∥ insert B2 ∥ insert B3 mesmo SKU qty=1',
    http: {
      'bag': a3bag?.brief,
      'b2': a3single?.brief,
      'b3': a3ins3?.brief,
    },
    oracles: {
      ...claimSnap(a3rows, held: a3held, prod: a3prod, hubN: a3hub?.list.length),
      'cs_bag': a3bag?.sessionId,
    },
    result: a3fail ? 'FAIL' : 'HOLD',
    lens: 'EP-A',
    classeNova: true,
    race: true,
    countFinding: a3fail,
  );

  await pause();

  // A4 — favorite + hold + 2.º + 3.º
  final a4pid = await c.createProduct(
    title: '$prefix A4 fav',
    qty: 1,
    price: 13,
  );
  HttpHit? a4fav;
  HttpHit? a4i1;
  HttpHit? a4i2;
  HttpHit? a4i3;
  HttpHit? a4favRow;
  if (a4pid != null) {
    a4fav = await c.favorite(a4pid, jwt: c.buyerJwt, user: b1);
    a4i1 = await c.insertOrderHit(
      productId: a4pid,
      jwt: c.buyerJwt,
      buyer: b1,
      price: 13,
    );
    final raced = await Future.wait([
      c.insertOrderHit(
        productId: a4pid,
        jwt: c.buyer2Jwt,
        buyer: b2,
        price: 13,
      ),
      c.insertOrderHit(
        productId: a4pid,
        jwt: c.buyer3Jwt,
        buyer: b3,
        price: 13,
      ),
    ]);
    a4i2 = raced[0];
    a4i3 = raced[1];
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
      id: 'P1-A4-FAV-HOLD-3',
      lens: 'EP-A',
      severity: 'P1',
      title: 'favorite+hold não impediu 2.º/3.º dono qty=1',
      actor: 'B1 fav+insert · B2∥B3 insert',
      pre: 'SKU qty=1',
      repro: 'POST favorites; insert B1; Future.wait insert B2+B3',
      expected: '≤1 hold; fav ≠ stock claim extra',
      obtained: {
        'claims': a4claims,
        'i1': a4i1?.brief,
        'i2': a4i2?.brief,
        'i3': a4i3?.brief,
        'fav': a4fav?.brief,
      },
    );
  } else {
    c.block('A4', 'EP-A', 'fav+hold 2.º+3.º recusados', {
      'claims': a4claims,
      'i1': a4i1?.brief,
      'i2': a4i2?.brief,
      'i3': a4i3?.brief,
      'fav_n': a4favRow?.list.length,
    });
  }
  c.probe(
    id: 'A4',
    surfaces: 'favorites + orders + hold + Hub',
    action: 'favorite B1 + hold + insert B2∥B3',
    http: {
      'fav': a4fav?.brief,
      'i1': a4i1?.brief,
      'i2': a4i2?.brief,
      'i3': a4i3?.brief,
    },
    oracles: {
      ...claimSnap(a4rows, held: a4held, prod: a4prod, hubN: a4hub?.list.length),
      'fav_n': a4favRow?.list.length,
    },
    result: a4fail ? 'FAIL' : 'HOLD',
    lens: 'EP-A',
    classeNova: true,
    race: true,
    countFinding: a4fail,
  );

  // A5 — cancel hold → Hub restore → 2.º claim
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
  HttpHit? a5second;
  Map<String, dynamic>? a5prodAfter;
  if (a5pid != null) {
    a5ins = await c.insertOrderHit(
      productId: a5pid,
      jwt: c.buyerJwt,
      buyer: b1,
      price: 14,
    );
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
    a5second = await c.insertOrderHit(
      productId: a5pid,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 14,
    );
  }
  final a5rows = a5pid == null ? <Map<String, dynamic>>[] : await c.ordersForProduct(a5pid);
  final a5heldAfterH = a5pid == null ? null : await c.heldQty(a5pid);
  final a5heldAfter = a5heldAfterH == null ? -1 : c.heldQtyNum(a5heldAfterH);
  final hubHoldN = a5hubHold?.list.length ?? -1;
  final hubAfterN = a5hubAfter?.list.length ?? -1;
  final soldAfter = a5prodAfter?['is_sold'] == true;
  final listedAfter = a5prodAfter?['list_on_marketplace'] == true;
  final qtyAfter = numOf(a5prodAfter?['quantity']) ?? -1;
  final restoreFail = a5ins != null &&
      a5ins.ok &&
      listedAfter &&
      qtyAfter >= 1 &&
      (soldAfter || hubAfterN == 0) &&
      hubHoldN == 0;
  final secondOk = a5second?.ok == true;
  final a5fail = restoreFail || (a5can?.ok == true && !secondOk && hubAfterN >= 1);
  if (a5fail) {
    c.hold(
      id: restoreFail ? 'P2-A5-HUB-RESTORE' : 'P1-A5-SECOND-CLAIM',
      lens: 'EP-A',
      severity: restoreFail ? 'P2' : 'P1',
      title: restoreFail
          ? 'cancel hold não restaurou Hub'
          : 'após cancel+Hub restore o 2.º buyer não conseguiu claim',
      actor: 'B1 insert+cancel · B2 insert',
      pre: 'SKU qty=1 listed',
      repro: 'insert; PATCH cancelado; hub; insert B2',
      expected: 'Hub restaura; B2 consegue 1 hold',
      obtained: {
        'hub_hold': hubHoldN,
        'hub_after': hubAfterN,
        'second': a5second?.brief,
        'can': a5can?.brief,
      },
    );
  } else {
    c.block('A5', 'EP-A', 'cancel Hub restore + 2.º claim', {
      'hub_hold': hubHoldN,
      'hub_after': hubAfterN,
      'second_ok': secondOk,
      'held': a5heldAfter,
      'can': a5can?.brief,
    });
  }
  c.probe(
    id: 'A5',
    surfaces: 'orders + Hub + products',
    action: 'cancel hold → Hub restore → 2.º claim B2',
    http: {
      'ins': a5ins?.brief,
      'can': a5can?.brief,
      'second': a5second?.brief,
    },
    oracles: {
      ...claimSnap(a5rows, held: a5heldAfter, prod: a5prodAfter, hubN: hubAfterN),
      'hub_hold_n': hubHoldN,
      'second_ok': secondOk,
    },
    result: a5fail ? 'FAIL' : 'HOLD',
    lens: 'EP-A',
    classeNova: true,
    countFinding: a5fail,
  );

  // A6 — qty hostil 99 body + JWT PATCH
  final a6pid = await c.createProduct(
    title: '$prefix A6 qty',
    qty: 1,
    price: 16,
  );
  HttpHit? a6patch;
  HttpHit? a6cpi;
  HttpHit? a6ins;
  Map<String, dynamic>? a6ord;
  Map<String, dynamic>? a6prod;
  if (a6pid != null) {
    a6ins = await c.insertOrderHit(
      productId: a6pid,
      jwt: c.buyerJwt,
      buyer: b1,
      qty: 1,
      price: 16,
    );
    final oid = a6ins.firstId;
    if (oid != null) {
      a6patch = await c.rest(
        'PATCH',
        'orders?id=eq.$oid',
        jwt: c.buyerJwt,
        body: {'quantity': 99},
      );
      a6cpi = await c.checkout(
        orderId: oid,
        jwt: c.buyerJwt,
        buyer: b1,
        productId: a6pid,
        seller: s1,
        amount: 1,
        quantity: 99,
      );
      a6ord = await c.orderRow(oid);
    }
    a6prod = await c.productRow(a6pid);
  }
  final a6qty = numOf(a6ord?['quantity']) ?? -1;
  final a6prodQty = numOf(a6prod?['quantity']) ?? -1;
  final a6applied = numOf(a6ord?['stock_units_applied']);
  final a6fail = (a6qty >= 2 && a6prodQty < 2) ||
      (a6applied != null && a6applied >= 2 && a6prodQty < 2);
  if (a6fail) {
    c.hold(
      id: 'P1-A6-QTY-HOSTIL',
      lens: 'EP-A',
      severity: 'P1',
      title: 'qty hostil 99 aplicou stock > available',
      actor: 'B1 PATCH+CPI quantity=99',
      pre: 'SKU qty=1',
      repro: 'PATCH orders.quantity=99; CPI quantity=99',
      expected: 'qty efectiva 1 / CPI deny; stock products inalterado',
      obtained: {
        'patch': a6patch?.brief,
        'cpi': a6cpi?.brief,
        'ord_qty': a6qty,
        'prod_qty': a6prodQty,
        'applied': a6applied,
      },
    );
  } else {
    c.block('A6', 'EP-A', 'qty hostil clamp/deny', {
      'patch': a6patch?.brief,
      'cpi': a6cpi?.brief,
      'ord_qty': a6qty,
      'prod_qty': a6prodQty,
    });
  }
  c.probe(
    id: 'A6',
    surfaces: 'orders PATCH + CPI body + products',
    action: 'qty hostil 99 body + JWT PATCH',
    http: {'patch': a6patch?.brief, 'cpi': a6cpi?.brief, 'ins': a6ins?.brief},
    oracles: {
      'ord_qty': a6qty,
      'prod_qty': a6prodQty,
      'applied': a6applied,
      'cs': a6cpi?.sessionId,
      'patch_status': a6patch?.status,
    },
    result: a6fail ? 'FAIL' : 'HOLD',
    lens: 'EP-A',
    countFinding: a6fail,
  );

  // A7 — cross-seller bag
  final a7s1 = await c.createProduct(title: '$prefix A7 s1', qty: 2, price: 12);
  final a7s2 = await c.createProduct(
    title: '$prefix A7 s2',
    qty: 2,
    price: 14,
    seller: s1,
  );
  // seller2 product
  final a7s2p = await c.createProduct(
    title: '$prefix A7 s2p',
    qty: 2,
    price: 14,
    seller: s2,
  );
  HttpHit? a7bag;
  if (a7s1 != null && a7s2p != null) {
    final o1 = await c.insertOrder(
      productId: a7s1,
      jwt: c.buyer3Jwt,
      buyer: b3,
      price: 12,
    );
    final o2 = await c.insertOrder(
      productId: a7s2p,
      jwt: c.buyer3Jwt,
      buyer: b3,
      seller: s2,
      price: 14,
    );
    if (o1 != null && o2 != null) {
      a7bag = await c.checkoutBag(
        lines: [
          {'order_id': o1, 'product_id': a7s1},
          {'order_id': o2, 'product_id': a7s2p, 'seller_id': s2},
        ],
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
        amount: 1,
      );
    }
  }
  final a7fail = c.usefulCs(a7bag);
  if (a7fail) {
    c.hold(
      id: 'P1-A7-CROSS-SELLER',
      lens: 'EP-A',
      severity: 'P1',
      title: 'bag cross-seller criou Session',
      actor: 'B3 bag S1+S2',
      pre: '1 order S1 + 1 order S2',
      repro: 'checkoutBag 2 sellers',
      expected: '400 one seller / cross-seller deny',
      obtained: a7bag?.brief,
    );
  } else {
    c.block('A7', 'EP-A', 'bag cross-seller deny', a7bag?.brief);
  }
  c.probe(
    id: 'A7',
    surfaces: 'bag CPI + 2 sellers',
    action: 'cross-seller bag deny',
    http: a7bag?.brief ?? 'n/a',
    oracles: {
      'cs': a7bag?.sessionId,
      'denied': denied(a7bag ?? HttpHit(0, '', null)),
      'pad': a7s2,
    },
    result: a7fail ? 'FAIL' : 'HOLD',
    lens: 'EP-A',
    countFinding: a7fail,
  );
}

Future<void> runB(
  Rtdu c, {
  required String s1,
  required String b1,
  required String b2,
  required String b3,
}) async {
  // B1 — sold+listed vs Hub vs insert (1 residual clássico)
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
  HttpHit? b1ins;
  if (b1pid != null) {
    b1ins = await c.insertOrderHit(
      productId: b1pid,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 15,
    );
  }
  final leak = (b1hubBuyer?.list.length ?? 0) > 0 || (b1hubAnon?.list.length ?? 0) > 0;
  final insOkSold = b1ins?.ok == true;
  final b1fail = leak || insOkSold;
  if (b1fail) {
    c.hold(
      id: leak ? 'P2-B1-HUB-SOLD' : 'P1-B1-INSERT-SOLD',
      lens: 'EP-B',
      severity: leak ? 'P2' : 'P1',
      title: leak ? 'Hub mostra SKU sold+listed' : 'insert aceite em SKU sold qty=0',
      actor: 'buyer JWT + anon + B2 insert',
      pre: 'is_sold=true list_on_marketplace=true qty=0',
      repro: 'GET hub_products_public; insertOrder',
      expected: 'Hub 0; insert 400 hold',
      obtained: {
        'buyer': b1hubBuyer?.list.length,
        'anon': b1hubAnon?.list.length,
        'ins': b1ins?.brief,
      },
    );
  } else {
    c.block('B1', 'EP-B', 'Hub hide sold + insert deny', {
      'buyer_n': b1hubBuyer?.list.length,
      'anon_n': b1hubAnon?.list.length,
      'ins': b1ins?.brief,
    });
  }
  c.probe(
    id: 'B1',
    surfaces: 'hub_products_public + products + insert',
    action: 'sold+listed vs Hub vs insert',
    http: {
      'buyer': b1hubBuyer?.brief,
      'anon': b1hubAnon?.brief,
      'ins': b1ins?.brief,
    },
    oracles: {
      'buyer_n': b1hubBuyer?.list.length,
      'anon_n': b1hubAnon?.list.length,
      'sold': b1prod?['is_sold'],
      'qty': b1prod?['quantity'],
      'ins_ok': insOkSold,
    },
    result: b1fail ? 'FAIL' : 'HOLD',
    lens: 'EP-B',
    residual: true,
    countFinding: b1fail,
  );

  await pause(600);

  // B2 — leftover 3→2→1 cadeia de pagos
  final paid3 = await c.payToPago(lens: 'EP-B', initialQty: 3);
  Map<String, dynamic>? p3;
  HttpHit? h3;
  Map<String, dynamic>? o3;
  if (paid3 != null) {
    p3 = await c.productRow(paid3.pid);
    o3 = await c.orderRow(paid3.oid);
    h3 = await c.hubSku(paid3.pid, jwt: c.buyerJwt);
  }
  final paid2 = await c.payToPago(lens: 'EP-B', initialQty: 2);
  Map<String, dynamic>? p2;
  HttpHit? h2;
  Map<String, dynamic>? o2;
  if (paid2 != null) {
    p2 = await c.productRow(paid2.pid);
    o2 = await c.orderRow(paid2.oid);
    h2 = await c.hubSku(paid2.pid, jwt: c.buyerJwt);
  }
  final q3 = numOf(p3?['quantity']) ?? -1;
  final q2 = numOf(p2?['quantity']) ?? -1;
  final n3 = h3?.list.length ?? -1;
  final n2 = h2?.list.length ?? -1;
  final st3 = '${o3?['status'] ?? ''}'.toLowerCase() == 'pago';
  final st2 = '${o2?['status'] ?? ''}'.toLowerCase() == 'pago';
  final chainOk = paid3 != null &&
      paid2 != null &&
      st3 &&
      st2 &&
      q3 == 2 &&
      q2 == 1 &&
      n3 == 1 &&
      n2 == 1;
  final b2fail = (paid3 != null && st3 && q3 != 2) ||
      (paid2 != null && st2 && q2 != 1) ||
      (st3 && q3 == 2 && n3 != 1) ||
      (st2 && q2 == 1 && n2 != 1);
  if (paid3 == null && paid2 == null) {
    c.skip('B2', 'EP-B', 'setup_paid_order chain fail', 'null');
  } else if (b2fail) {
    c.hold(
      id: 'P1-B2-LEFTOVER-CHAIN',
      lens: 'EP-B',
      severity: q3 != 2 || q2 != 1 ? 'P1' : 'P2',
      title: 'cadeia pagos leftover 3→2 / 2→1 incoerente',
      actor: 'e2e setup_paid_order ×2',
      pre: 'SKU qty=3 e qty=2',
      repro: 'setup_paid_order initial_qty 3 depois 2; Hub',
      expected: 'qty 2 Hub 1; qty 1 Hub 1; ambos pago',
      obtained: {
        'q3': q3,
        'hub3': n3,
        'q2': q2,
        'hub2': n2,
        'pi3': paid3?.pi,
        'pi2': paid2?.pi,
      },
    );
  } else {
    c.block('B2', 'EP-B', 'leftover 3→2 e 2→1 Hub coerente', {
      'q3': q3,
      'hub3': n3,
      'q2': q2,
      'hub2': n2,
      'chainOk': chainOk,
    });
  }
  c.probe(
    id: 'B2',
    surfaces: 'orders + products + Hub + Stripe',
    action: 'leftover 3→2→1 cadeia de pagos 4242',
    http: {'p3': paid3?.hit.brief, 'p2': paid2?.hit.brief},
    oracles: {
      'q3': q3,
      'hub3': n3,
      'st3': st3,
      'pi3': paid3?.pi,
      'q2': q2,
      'hub2': n2,
      'st2': st2,
      'pi2': paid2?.pi,
    },
    result: (paid3 == null && paid2 == null)
        ? 'SKIP'
        : (b2fail ? 'FAIL' : 'HOLD'),
    lens: 'EP-B',
    classeNova: true,
    countFinding: b2fail,
  );

  await pause(800);

  // B3 — unpublish mid-CPI + mid-tip
  final b3pid = await c.createProduct(
    title: '$prefix B3 unpub',
    qty: 2,
    price: 16,
    listed: true,
  );
  final b3live = await c.createLive(title: '$prefix B3 tip');
  HttpHit? b3ins;
  HttpHit? b3unpub;
  HttpHit? b3cpi;
  HttpHit? b3tip;
  HttpHit? b3hubAfter;
  if (b3pid != null && b3live != null) {
    b3ins = await c.insertOrderHit(
      productId: b3pid,
      jwt: c.buyerJwt,
      buyer: b1,
      price: 16,
    );
    final oid = b3ins.firstId;
    final raced = await Future.wait([
      c.publishHub(false),
      if (oid != null)
        c.checkout(
          orderId: oid,
          jwt: c.buyerJwt,
          buyer: b1,
          productId: b3pid,
          seller: s1,
          amount: 16,
        )
      else
        Future.value(b3ins),
      c.tipCheckout(liveId: b3live, seller: s1, jwt: c.buyer2Jwt),
    ]);
    b3unpub = raced[0];
    b3cpi = raced[1];
    b3tip = raced[2];
    b3hubAfter = await c.hubSku(b3pid, jwt: c.buyerJwt);
    await c.restoreSeller1Published();
  }
  final b3hubN = b3hubAfter?.list.length ?? -1;
  final prof = await c.profile(s1);
  final published = prof?['hub_published'] == true;
  // After restore, Hub should list leftover SKU. During unpublish Hub 0 is OK.
  // FAIL: CPI+tip both succeed while creating 2 money paths on unpublished hub
  // is not oversell; FAIL if Hub still lists while unpublished before restore.
  // We restored already — record unpublish RPC + CPI/tip outcomes.
  // Oversell: 2 claims on qty=2 is OK (qty=2). Check CPI didn't create extra qty.
  final b3prod = b3pid == null ? null : await c.productRow(b3pid);
  final b3rows = b3pid == null ? <Map<String, dynamic>>[] : await c.ordersForProduct(b3pid);
  final b3claims = c.liveClaims(b3rows);
  final b3fail = b3claims > 2;
  if (b3fail) {
    c.hold(
      id: 'P1-B3-UNPUB-RACE',
      lens: 'EP-B',
      severity: 'P1',
      title: 'unpublish∥CPI∥tip criou claims extra',
      actor: 'S1 unpublish ∥ B1 CPI ∥ B2 tip',
      pre: 'SKU qty=2 listed + live',
      repro: 'Future.wait publishHub(false)+CPI+tipCheckout',
      expected: '≤2 holds; hub unpublished no leak extra stock',
      obtained: {
        'unpub': b3unpub?.brief,
        'cpi': b3cpi?.brief,
        'tip': b3tip?.brief,
        'claims': b3claims,
      },
    );
  } else {
    c.block('B3', 'EP-B', 'unpublish∥CPI∥tip', {
      'unpub': b3unpub?.brief,
      'cpi': b3cpi?.brief,
      'tip': b3tip?.brief,
      'hub_n': b3hubN,
      'restored': published,
      'cs_cpi': c.usefulCs(b3cpi),
      'cs_tip': c.usefulCs(b3tip),
    });
  }
  c.probe(
    id: 'B3',
    surfaces: 'hub publish + CPI + tip + products',
    action: 'unpublish mid-CPI + mid-tip',
    http: {
      'unpub': b3unpub?.brief,
      'cpi': b3cpi?.brief,
      'tip': b3tip?.brief,
    },
    oracles: {
      'claims': b3claims,
      'hub_n_after_restore': b3hubN,
      'published': published,
      'cs_cpi': b3cpi?.sessionId,
      'cs_tip': b3tip?.sessionId,
      'qty': b3prod?['quantity'],
      'ins': b3ins?.brief,
    },
    result: b3fail ? 'FAIL' : 'HOLD',
    lens: 'EP-B',
    classeNova: true,
    race: true,
    countFinding: b3fail,
  );

  await pause(400);

  // B4 — Hub anon vs buyer vs sellable RPC
  final b4listed = await c.createProduct(
    title: '$prefix B4 listed',
    qty: 2,
    listed: true,
    sold: false,
    price: 9,
  );
  final b4sold = await c.createProduct(
    title: '$prefix B4 sold',
    qty: 0,
    listed: true,
    sold: true,
    price: 9,
  );
  final b4un = await c.createProduct(
    title: '$prefix B4 unlisted',
    qty: 3,
    listed: false,
    sold: false,
    price: 9,
  );
  HttpHit? sellL;
  HttpHit? sellS;
  HttpHit? sellU;
  HttpHit? hubLB;
  HttpHit? hubLA;
  HttpHit? hubSB;
  HttpHit? hubSA;
  HttpHit? hubUB;
  HttpHit? hubUA;
  if (b4listed != null) {
    sellL = await c.hubSellable(b4listed);
    hubLB = await c.hubSku(b4listed, jwt: c.buyerJwt);
    hubLA = await c.hubSku(b4listed, anon: true);
  }
  if (b4sold != null) {
    sellS = await c.hubSellable(b4sold);
    hubSB = await c.hubSku(b4sold, jwt: c.buyerJwt);
    hubSA = await c.hubSku(b4sold, anon: true);
  }
  if (b4un != null) {
    sellU = await c.hubSellable(b4un);
    hubUB = await c.hubSku(b4un, jwt: c.buyerJwt);
    hubUA = await c.hubSku(b4un, anon: true);
  }
  final nLB = hubLB?.list.length ?? -1;
  final nLA = hubLA?.list.length ?? -1;
  final nSB = hubSB?.list.length ?? -1;
  final nSA = hubSA?.list.length ?? -1;
  final nUB = hubUB?.list.length ?? -1;
  final nUA = hubUA?.list.length ?? -1;
  final sl = sellL == null ? false : c.sellableTrue(sellL);
  final ss = sellS == null ? true : c.sellableTrue(sellS);
  final su = sellU == null ? true : c.sellableTrue(sellU);
  final b4fail = nLB != 1 ||
      nLA != 1 ||
      nSB != 0 ||
      nSA != 0 ||
      nUB != 0 ||
      nUA != 0 ||
      sl != true ||
      ss != false ||
      su != false;
  if (b4fail) {
    c.hold(
      id: 'P2-B4-HUB-SELLABLE',
      lens: 'EP-B',
      severity: 'P2',
      title: 'Hub anon/buyer ≠ sellable RPC',
      actor: 'anon + B1 + svc sellable',
      pre: 'listed qty2 / sold qty0 / unlisted qty3',
      repro: 'GET hub_products_public + batata_product_hub_sellable',
      expected: 'Hub 1/1 listed; 0 sold; 0 unlisted; sellable true/false/false',
      obtained: {
        'nLB': nLB,
        'nLA': nLA,
        'nSB': nSB,
        'nSA': nSA,
        'nUB': nUB,
        'nUA': nUA,
        'sl': sl,
        'ss': ss,
        'su': su,
        'sellL': sellL?.brief,
        'sellS': sellS?.brief,
        'sellU': sellU?.brief,
      },
    );
  } else {
    c.block('B4', 'EP-B', 'Hub anon=buyer=sellable', {
      'nLB': nLB,
      'nLA': nLA,
      'nSB': nSB,
      'sl': sl,
      'ss': ss,
      'su': su,
    });
  }
  c.probe(
    id: 'B4',
    surfaces: 'hub_products_public anon/buyer + sellable RPC',
    action: 'Hub anon vs buyer vs sellable RPC',
    http: {
      'listed_b': hubLB?.brief,
      'listed_a': hubLA?.brief,
      'sellL': sellL?.brief,
      'sellS': sellS?.brief,
      'sellU': sellU?.brief,
    },
    oracles: {
      'nLB': nLB,
      'nLA': nLA,
      'nSB': nSB,
      'nSA': nSA,
      'nUB': nUB,
      'nUA': nUA,
      'sl': sl,
      'ss': ss,
      'su': su,
    },
    result: b4fail ? 'FAIL' : 'HOLD',
    lens: 'EP-B',
    classeNova: true,
    countFinding: b4fail,
  );

  await pause(600);

  // B5 — sold Hub 0 após rifa + após pago
  final fx = await makeLiveRaffle(c, s1: s1, title: 'B5 raffle-hub');
  HttpHit? b5draw;
  HttpHit? b5hubRaf;
  Map<String, dynamic>? b5prodRaf;
  Map<String, dynamic>? b5li;
  var b5win = 0;
  if (fx.raf != null && fx.sku != null) {
    await seedTickets(c, raf: fx.raf!, user: b1);
    await c.closeRaffle(fx.raf!);
    b5draw = await c.drawRaffle(fx.raf!);
    b5win = (await c.raffleWinners(fx.raf!)).length;
    b5prodRaf = await c.productRow(fx.sku!);
    b5li = fx.li == null ? null : await c.liveItemRow(fx.li!);
    b5hubRaf = await c.hubSku(fx.sku!, jwt: c.buyerJwt);
  }
  final paid1 = await c.payToPago(lens: 'EP-B', initialQty: 1);
  HttpHit? b5hubPay;
  Map<String, dynamic>? b5prodPay;
  Map<String, dynamic>? b5ordPay;
  if (paid1 != null) {
    b5prodPay = await c.productRow(paid1.pid);
    b5ordPay = await c.orderRow(paid1.oid);
    b5hubPay = await c.hubSku(paid1.pid, jwt: c.buyerJwt);
  }
  final qR = numOf(b5prodRaf?['quantity']) ?? -1;
  final nR = b5hubRaf?.list.length ?? -1;
  final qP = numOf(b5prodPay?['quantity']) ?? -1;
  final nP = b5hubPay?.list.length ?? -1;
  final pago = '${b5ordPay?['status'] ?? ''}'.toLowerCase() == 'pago';
  final drawn = b5win >= 1;
  final b5fail = (drawn && nR != 0) || (pago && qP < 1 && nP != 0);
  if (b5fail) {
    c.hold(
      id: 'P1-B5-HUB-AFTER-SEAL',
      lens: 'EP-B',
      severity: 'P1',
      title: 'Hub ainda lista após rifa drawn e/ou pago qty=1',
      actor: 'S1 draw + e2e pago',
      pre: 'rifa hitch qty=1; pago qty=1',
      repro: 'draw; GET Hub; setup_paid_order qty=1; GET Hub',
      expected: 'Hub 0 após drawn; Hub 0 após pago qty=1',
      obtained: {
        'nR': nR,
        'qR': qR,
        'nP': nP,
        'qP': qP,
        'nWin': b5win,
        'draw': b5draw?.brief,
        'pi': paid1?.pi,
      },
    );
  } else {
    c.block('B5', 'EP-B', 'Hub 0 após rifa e após pago', {
      'nR': nR,
      'qR': qR,
      'nP': nP,
      'qP': qP,
      'nWin': b5win,
      'pago': pago,
    });
  }
  c.probe(
    id: 'B5',
    surfaces: 'rifa + Hub + pago 4242 + products + live_item',
    action: 'sold Hub 0 após rifa + após pago',
    http: {'draw': b5draw?.brief, 'paid': paid1?.hit.brief},
    oracles: {
      'nWin': b5win,
      'hub_raf': nR,
      'qty_raf': qR,
      'li': b5li?['status'],
      'li_open': liOpen(b5li),
      'hub_pay': nP,
      'qty_pay': qP,
      'pago': pago,
      'pi': paid1?.pi,
    },
    result: b5fail ? 'FAIL' : 'HOLD',
    lens: 'EP-B',
    classeNova: true,
    countFinding: b5fail,
  );
}

Future<void> runC(
  Rtdu c, {
  required String s1,
  required String b1,
  required String b2,
  required String b3,
}) async {
  await pause(600);
  // C1 — draw qty=1 + live_item ≠ available
  final c1fx = await makeLiveRaffle(c, s1: s1, title: 'C1 draw-qty1');
  HttpHit? c1draw;
  HttpHit? c1ins;
  HttpHit? c1hub;
  Map<String, dynamic>? c1prod;
  Map<String, dynamic>? c1li;
  var c1win = 0;
  if (c1fx.raf != null && c1fx.sku != null) {
    await seedTickets(c, raf: c1fx.raf!, user: b1);
    await c.closeRaffle(c1fx.raf!);
    c1draw = await c.drawRaffle(c1fx.raf!);
    c1win = (await c.raffleWinners(c1fx.raf!)).length;
    c1ins = await c.insertOrderHit(
      productId: c1fx.sku!,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 9,
    );
    c1prod = await c.productRow(c1fx.sku!);
    c1li = c1fx.li == null ? null : await c.liveItemRow(c1fx.li!);
    c1hub = await c.hubSku(c1fx.sku!, jwt: c.buyerJwt);
  }
  final c1open = liOpen(c1li);
  final c1hubN = c1hub?.list.length ?? -1;
  final c1q = numOf(c1prod?['quantity']) ?? -1;
  final c1fail = c1win >= 1 && (c1open || c1hubN > 0 || c1ins?.ok == true);
  if (c1fail) {
    c.hold(
      id: 'P1-C1-DRAW-AVAILABLE',
      lens: 'EP-C',
      severity: 'P1',
      title: 'após draw qty=1 live_item ainda available e/ou Hub/insert vivos',
      actor: 'S1 draw + B2 insert',
      pre: 'hitch qty=1 tickets',
      repro: 'draw; live_item; Hub; insert B2',
      expected: 'li ≠ available; Hub 0; insert 400',
      obtained: {
        'draw': c1draw?.brief,
        'li': c1li?['status'],
        'hub': c1hubN,
        'ins': c1ins?.brief,
        'nWin': c1win,
      },
    );
  } else {
    c.block('C1', 'EP-C', 'draw qty=1 sela live_item+Hub', {
      'draw': c1draw?.brief,
      'li': c1li?['status'],
      'hub': c1hubN,
      'ins': c1ins?.brief,
      'nWin': c1win,
    });
  }
  c.probe(
    id: 'C1',
    surfaces: 'rifa + live_item + Hub + insert',
    action: 'draw qty=1 + live_item ≠ available',
    http: {'draw': c1draw?.brief, 'ins': c1ins?.brief},
    oracles: {
      'nWin': c1win,
      'li': c1li?['status'],
      'li_open': c1open,
      'hub_n': c1hubN,
      'qty': c1q,
      'ins_ok': c1ins?.ok,
    },
    result: c1fail ? 'FAIL' : 'HOLD',
    lens: 'EP-C',
    residual: true,
    countFinding: c1fail,
  );

  await pause(600);

  // C2 — winner_count=2 stock=2
  final c2fx = await makeLiveRaffle(
    c,
    s1: s1,
    title: 'C2 wc2',
    qty: 2,
    winnerCount: 2,
  );
  HttpHit? c2draw;
  HttpHit? c2ins;
  HttpHit? c2hub;
  Map<String, dynamic>? c2prod;
  Map<String, dynamic>? c2li;
  var c2win = 0;
  if (c2fx.raf != null && c2fx.sku != null) {
    await seedTickets(c, raf: c2fx.raf!, user: b1);
    await c.joinRaffle(c2fx.raf!, jwt: c.buyer2Jwt);
    await c.awardTickets(raffleId: c2fx.raf!, userId: b2, delta: 5);
    await c.closeRaffle(c2fx.raf!);
    c2draw = await c.drawRaffle(c2fx.raf!);
    c2win = (await c.raffleWinners(c2fx.raf!)).length;
    c2ins = await c.insertOrderHit(
      productId: c2fx.sku!,
      jwt: c.buyer3Jwt,
      buyer: b3,
      price: 9,
    );
    c2prod = await c.productRow(c2fx.sku!);
    c2li = c2fx.li == null ? null : await c.liveItemRow(c2fx.li!);
    c2hub = await c.hubSku(c2fx.sku!, jwt: c.buyerJwt);
  }
  final c2q = numOf(c2prod?['quantity']) ?? -1;
  final c2hubN = c2hub?.list.length ?? -1;
  final c2fail = c2win >= 2 && (c2q >= 1 || c2hubN > 0 || c2ins?.ok == true);
  if (c2fail) {
    c.hold(
      id: 'P1-C2-WC2-STOCK',
      lens: 'EP-C',
      severity: 'P1',
      title: 'winner_count=2 stock=2 não selou leftover/Hub',
      actor: 'S1 draw 2 winners + B3 insert',
      pre: 'qty=2 wc=2 tickets B1+B2',
      repro: 'draw; insert B3; Hub',
      expected: 'qty 0 Hub 0 insert 400; 2 winners',
      obtained: {
        'nWin': c2win,
        'qty': c2q,
        'hub': c2hubN,
        'ins': c2ins?.brief,
        'draw': c2draw?.brief,
      },
    );
  } else {
    c.block('C2', 'EP-C', 'wc=2 stock=2 selado', {
      'nWin': c2win,
      'qty': c2q,
      'hub': c2hubN,
      'ins': c2ins?.brief,
    });
  }
  c.probe(
    id: 'C2',
    surfaces: 'rifa multi-winner + Hub + products + insert',
    action: 'winner_count=2 stock=2',
    http: {'draw': c2draw?.brief, 'ins': c2ins?.brief},
    oracles: {
      'nWin': c2win,
      'qty': c2q,
      'hub_n': c2hubN,
      'li': c2li?['status'],
      'ins_ok': c2ins?.ok,
    },
    result: c2fail ? 'FAIL' : 'HOLD',
    lens: 'EP-C',
    classeNova: true,
    countFinding: c2fail,
  );

  await pause(800);

  // C3 — draw∥CPI∥insert
  final c3fx = await makeLiveRaffle(c, s1: s1, title: 'C3 race3');
  HttpHit? c3draw;
  HttpHit? c3cpi;
  HttpHit? c3ins;
  HttpHit? c3hub;
  Map<String, dynamic>? c3prod;
  Map<String, dynamic>? c3li;
  var c3win = 0;
  if (c3fx.raf != null && c3fx.sku != null) {
    await seedTickets(c, raf: c3fx.raf!, user: b1);
    await c.closeRaffle(c3fx.raf!);
    final pre = await c.insertOrderHit(
      productId: c3fx.sku!,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 9,
    );
    final oid = pre.firstId;
    final raced = await Future.wait([
      c.drawRaffle(c3fx.raf!),
      if (oid != null)
        c.checkout(
          orderId: oid,
          jwt: c.buyer2Jwt,
          buyer: b2,
          productId: c3fx.sku!,
          seller: s1,
          amount: 9,
        )
      else
        Future.value(pre),
      c.insertOrderHit(
        productId: c3fx.sku!,
        jwt: c.buyer3Jwt,
        buyer: b3,
        price: 9,
      ),
    ]);
    c3draw = raced[0];
    c3cpi = raced[1];
    c3ins = raced[2];
    c3win = (await c.raffleWinners(c3fx.raf!)).length;
    c3prod = await c.productRow(c3fx.sku!);
    c3li = c3fx.li == null ? null : await c.liveItemRow(c3fx.li!);
    c3hub = await c.hubSku(c3fx.sku!, jwt: c.buyerJwt);
  }
  final c3q = numOf(c3prod?['quantity']) ?? -1;
  final c3hubN = c3hub?.list.length ?? -1;
  final c3both = c3win >= 1 && c.usefulCs(c3cpi);
  final c3fail = (c3both && (c3hubN > 0 || c3q >= 1)) ||
      (c3win >= 1 && c3ins?.ok == true && c3q < 1);
  if (c3fail) {
    c.hold(
      id: 'P1-C3-DRAW-CPI-INSERT',
      lens: 'EP-C',
      severity: 'P1',
      title: 'draw∥CPI∥insert qty=1: dois donos ou Hub aberto',
      actor: 'S1 draw ∥ B2 CPI ∥ B3 insert',
      pre: 'hitch qty=1 closed tickets',
      repro: 'Future.wait draw + CPI + insert',
      expected: '≤1 dono; Hub 0 se drawn; 3.º insert deny',
      obtained: {
        'draw': c3draw?.brief,
        'cpi': c3cpi?.brief,
        'ins': c3ins?.brief,
        'nWin': c3win,
        'qty': c3q,
        'hub': c3hubN,
      },
    );
  } else {
    c.block('C3', 'EP-C', 'draw∥CPI∥insert', {
      'draw': c3draw?.brief,
      'cpi': c3cpi?.brief,
      'ins': c3ins?.brief,
      'nWin': c3win,
      'qty': c3q,
      'hub': c3hubN,
      'cs': c.usefulCs(c3cpi),
    });
  }
  c.probe(
    id: 'C3',
    surfaces: 'rifa + CPI + insert + Hub + live_item',
    action: 'draw∥CPI∥insert qty=1',
    http: {
      'draw': c3draw?.brief,
      'cpi': c3cpi?.brief,
      'ins': c3ins?.brief,
    },
    oracles: {
      'nWin': c3win,
      'qty': c3q,
      'hub_n': c3hubN,
      'cs': c3cpi?.sessionId,
      'li': c3li?['status'],
      'ins_ok': c3ins?.ok,
    },
    result: c3fail ? 'FAIL' : 'HOLD',
    lens: 'EP-C',
    classeNova: true,
    race: true,
    countFinding: c3fail,
  );

  await pause(600);

  // C4 — hitch accept ∥ bag outro SKU
  final c4hitch = await c.createProduct(
    title: '$prefix C4 hitch',
    qty: 1,
    price: 9,
    listed: true,
    live: true,
  );
  final c4live = await c.createLive(title: '$prefix C4 hitch-bag');
  String? c4li;
  if (c4live != null && c4hitch != null) {
    c4li = await c.createLiveItem(
      liveId: c4live,
      title: '$prefix C4-li',
      kind: 'marketplace_product',
      productId: c4hitch,
    );
  }
  String? c4rid;
  if (c4live != null && c4li != null) {
    c4rid = await c.insertReservation(
      liveId: c4live,
      liveItemId: c4li,
      jwt: c.buyerJwt,
      buyer: b1,
    );
  }
  final planted = await plantBag(
    c,
    buyer: b3,
    jwt: c.buyer3Jwt!,
    tag: 'C4bag',
    n: 2,
    qty: 2,
    price: 8,
  );
  HttpHit? c4acc;
  HttpHit? c4bag;
  if (c4rid != null && planted.oids.length == 2) {
    final raced = await Future.wait([
      c.acceptRes(c4rid),
      c.checkoutBag(
        lines: bagLines(planted.oids, planted.skus),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
        amount: 1,
      ),
    ]);
    c4acc = raced[0];
    c4bag = raced[1];
  }
  final c4res = c4rid == null ? null : await c.resRow(c4rid);
  final c4hRows =
      c4hitch == null ? <Map<String, dynamic>>[] : await c.ordersForProduct(c4hitch);
  final c4hClaims = c.liveClaims(c4hRows);
  var bagDouble = 0;
  for (final pid in planted.skus) {
    final rows = await c.ordersForProduct(pid);
    if (c.liveClaims(rows) >= 2) bagDouble++;
  }
  final c4fail = c4hClaims >= 2 || bagDouble > 0;
  if (c4fail) {
    c.hold(
      id: 'P1-C4-HITCH-BAG',
      lens: 'EP-C',
      severity: 'P1',
      title: 'hitch accept∥bag outro SKU: double claim',
      actor: 'S1 accept hitch ∥ B3 bag pads',
      pre: 'hitch qty=1 pending + 2 pads B3',
      repro: 'Future.wait acceptRes + checkoutBag',
      expected: 'hitch ≤1; pads ≤1/SKU; bag noutro SKU não rouba hitch',
      obtained: {
        'acc': c4acc?.brief,
        'bag': c4bag?.brief,
        'hitch_claims': c4hClaims,
        'bagDouble': bagDouble,
        'res': c4res?['status'],
      },
    );
  } else {
    c.block('C4', 'EP-C', 'hitch∥bag outro SKU isolados', {
      'acc': c4acc?.brief,
      'bag': c4bag?.brief,
      'hitch_claims': c4hClaims,
      'res': c4res?['status'],
      'cs': c.usefulCs(c4bag),
    });
  }
  c.probe(
    id: 'C4',
    surfaces: 'hitch accept + bag + orders + live_item',
    action: 'hitch accept ∥ bag outro SKU',
    http: {'acc': c4acc?.brief, 'bag': c4bag?.brief},
    oracles: {
      'res': c4res?['status'],
      'hitch_claims': c4hClaims,
      'bagDouble': bagDouble,
      'cs': c4bag?.sessionId,
    },
    result: c4fail ? 'FAIL' : 'HOLD',
    lens: 'EP-C',
    classeNova: true,
    race: true,
    countFinding: c4fail,
  );

  await pause(600);

  // C5 — end_live∥bag∥Hub refresh
  final c5sku = await c.createProduct(
    title: '$prefix C5 hitch',
    qty: 1,
    price: 9,
    listed: true,
    live: true,
  );
  final c5pad = await c.createProduct(title: '$prefix C5 pad', qty: 2, price: 8);
  final c5live = await c.createLive(title: '$prefix C5 endbag');
  String? c5li;
  if (c5live != null && c5sku != null) {
    c5li = await c.createLiveItem(
      liveId: c5live,
      title: '$prefix C5-li',
      kind: 'marketplace_product',
      productId: c5sku,
    );
  }
  HttpHit? c5end;
  HttpHit? c5bag;
  HttpHit? c5hub;
  if (c5sku != null && c5pad != null && c5live != null) {
    final oSku = await c.insertOrder(
      productId: c5sku,
      jwt: c.buyer3Jwt,
      buyer: b3,
      price: 9,
    );
    final oPad = await c.insertOrder(
      productId: c5pad,
      jwt: c.buyer3Jwt,
      buyer: b3,
      price: 8,
    );
    if (oSku != null && oPad != null) {
      final raced = await Future.wait([
        c.rest(
          'PATCH',
          'lives?id=eq.$c5live',
          service: true,
          body: {'status': 'ended', 'is_active': false},
          prefer: 'return=representation',
        ),
        c.checkoutBag(
          lines: [
            {'order_id': oSku, 'product_id': c5sku},
            {'order_id': oPad, 'product_id': c5pad},
          ],
          jwt: c.buyer3Jwt,
          buyer: b3,
          seller: s1,
          amount: 1,
        ),
        c.hubSku(c5sku, jwt: c.buyerJwt),
      ]);
      c5end = raced[0];
      c5bag = raced[1];
      c5hub = raced[2];
    }
  }
  final c5prod = c5sku == null ? null : await c.productRow(c5sku);
  final c5hubAfter = c5sku == null ? null : await c.hubSku(c5sku, jwt: c.buyerJwt);
  final c5rows =
      c5sku == null ? <Map<String, dynamic>>[] : await c.ordersForProduct(c5sku);
  final c5liRow = c5li == null ? null : await c.liveItemRow(c5li);
  final c5claims = c.liveClaims(c5rows);
  final c5fail = c5claims >= 2;
  if (c5fail) {
    c.hold(
      id: 'P1-C5-END-BAG',
      lens: 'EP-C',
      severity: 'P1',
      title: 'end_live∥bag∥Hub: 2 stock claims',
      actor: 'svc end_live ∥ B3 bag ∥ Hub GET',
      pre: 'hitch qty=1 + pad',
      repro: 'Future.wait end_live + checkoutBag + hubSku',
      expected: '≤1 hold no hitch',
      obtained: {
        'end': c5end?.brief,
        'bag': c5bag?.brief,
        'claims': c5claims,
      },
    );
  } else {
    c.block('C5', 'EP-C', 'end_live∥bag∥Hub ≤1', {
      'end': c5end?.brief,
      'bag': c5bag?.brief,
      'claims': c5claims,
      'cs': c.usefulCs(c5bag),
    });
  }
  c.probe(
    id: 'C5',
    surfaces: 'lives + bag + Hub + live_item',
    action: 'end_live∥bag∥Hub refresh',
    http: {
      'end': c5end?.brief,
      'bag': c5bag?.brief,
      'hub_race': c5hub?.brief,
    },
    oracles: {
      'claims': c5claims,
      'cs': c5bag?.sessionId,
      'hub_n': c5hubAfter?.list.length,
      'qty': c5prod?['quantity'],
      'li': c5liRow?['status'],
    },
    result: c5fail ? 'FAIL' : 'HOLD',
    lens: 'EP-C',
    classeNova: true,
    race: true,
    countFinding: c5fail,
  );

  await pause(400);

  // C6 — partilhar sem/com rifa + forge entry
  const ghost = '00000000-0000-4000-8000-0000000000ep';
  final shareNo = await c.claimShare(ghost, jwt: c.buyerJwt);
  final joinNo = await c.joinRaffle(ghost, jwt: c.buyerJwt);
  final tGhost = await c.raffleTickets(ghost, b1);
  final liveYes = await c.createLive(title: '$prefix C6 share-forge');
  String? rafC6;
  if (liveYes != null) {
    final ins = await c.rest('POST', 'live_raffles', service: true, body: {
      'live_id': liveYes,
      'seller_id': s1,
      'title': '$prefix C6 share',
      'status': 'active',
      'winner_count': 1,
      'ends_at': futureIso(),
    });
    rafC6 = ins.firstId;
    if (rafC6 != null) c.createdRaffleIds.add(rafC6);
  }
  HttpHit? joinYes;
  HttpHit? shareYes;
  HttpHit? forgeIns;
  HttpHit? forgeAward;
  var tAfter = 0;
  if (rafC6 != null) {
    joinYes = await c.joinRaffle(rafC6, jwt: c.buyerJwt);
    shareYes = await c.claimShare(rafC6, jwt: c.buyerJwt);
    tAfter = await c.raffleTickets(rafC6, b1);
    forgeIns = await c.rest('POST', 'live_raffle_entries', jwt: c.buyer2Jwt, body: {
      'raffle_id': rafC6,
      'user_id': b1,
      'ticket_balance': 99,
    });
    forgeAward = await c.awardTickets(
      raffleId: rafC6,
      userId: b1,
      delta: 50,
      service: false,
      jwt: c.buyer2Jwt,
    );
  }
  final noRaffleLeak = tGhost > 0 || shareNo.rpcOk || joinNo.rpcOk;
  final forged = forgeIns?.ok == true || forgeAward?.rpcOk == true;
  final c6fail = noRaffleLeak || forged;
  if (c6fail) {
    c.hold(
      id: noRaffleLeak ? 'P1-C6-SHARE-NO-RAFFLE' : 'P1-C6-FORGE-ENTRY',
      lens: 'EP-C',
      severity: 'P1',
      title: noRaffleLeak
          ? 'partilhar sem rifa deu bilhetes'
          : 'forge entry/award JWT alheio aceite',
      actor: 'B1 share · B2 forge',
      pre: 'UUID fantasma + rifa active',
      repro: 'claim_share ghost; join+share real; POST entries user alheio',
      expected: 'sem rifa = 0 tickets; forge 403 RLS',
      obtained: {
        'shareNo': shareNo.brief,
        'joinNo': joinNo.brief,
        'tGhost': tGhost,
        'forgeIns': forgeIns?.brief,
        'forgeAward': forgeAward?.brief,
        'tAfter': tAfter,
      },
    );
  } else {
    c.block('C6', 'EP-C', 'share sem/com rifa + forge deny', {
      'shareNo': shareNo.brief,
      'joinYes': joinYes?.brief,
      'shareYes': shareYes?.brief,
      'tAfter': tAfter,
      'forgeIns': forgeIns?.brief,
    });
  }
  c.probe(
    id: 'C6',
    surfaces: 'rifa social + RLS entries',
    action: 'partilhar sem/com rifa + forge entry',
    http: {
      'shareNo': shareNo.brief,
      'joinYes': joinYes?.brief,
      'shareYes': shareYes?.brief,
      'forgeIns': forgeIns?.brief,
      'forgeAward': forgeAward?.brief,
    },
    oracles: {
      'tGhost': tGhost,
      'tAfter': tAfter,
      'forged': forged,
      'noRaffleLeak': noRaffleLeak,
    },
    result: c6fail ? 'FAIL' : 'HOLD',
    lens: 'EP-C',
    classeNova: true,
    countFinding: c6fail,
  );
}

Future<void> runD(
  Rtdu c, {
  required String s1,
  required String b1,
  required String b2,
  required String b3,
  required String s2,
}) async {
  await pause(800);
  // D1 — 6∥4 esperado fail-closed / ≤1 ; dual create = P1 mesmo se EL saturou
  final d1 = await plantBag(
    c,
    buyer: b3,
    jwt: c.buyer3Jwt!,
    tag: 'D1-6x4',
    n: 6,
    qty: 1,
    price: 7,
  );
  HttpHit? d1six;
  HttpHit? d1four;
  if (d1.oids.length == 6) {
    final raced = await Future.wait([
      c.checkoutBag(
        lines: bagLines(d1.oids, d1.skus),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
        amount: 1,
      ),
      c.checkoutBag(
        lines: bagLines(d1.oids, d1.skus, from: 1, to: 5),
        jwt: c.buyer3Jwt,
        buyer: b3,
        seller: s1,
        amount: 1,
      ),
    ]);
    d1six = raced[0];
    d1four = raced[1];
  }
  var d1double = 0;
  final perSku = <Map<String, Object?>>[];
  final overlap = d1.skus.length >= 5 ? d1.skus.sublist(1, 5) : d1.skus;
  for (final pid in overlap) {
    final rows = await c.ordersForProduct(pid);
    final claims = c.liveClaims(rows);
    final heldH = await c.heldQty(pid);
    final held = c.heldQtyNum(heldH);
    if (claims >= 2 || held >= 2) d1double++;
    perSku.add({'pid': pid, 'claims': claims, 'held': held});
  }
  final dual = c.dualCs(d1six, d1four);
  final d1fail = d1double > 0 || dual;
  if (d1fail) {
    c.hold(
      id: d1double > 0 ? 'P1-D1-OVERLAP-STOCK' : 'P1-D1-DUAL-BAG',
      lens: 'EP-D',
      severity: 'P1',
      title: d1double > 0
          ? '6∥4 criou 2 stock claims no mesmo SKU'
          : '6∥4 dual create: 2 cs_ open/payable (fail-closed quebrado)',
      actor: 'B3 bag6 ∥ bag4',
      pre: '6 SKU qty=1',
      repro: 'Future.wait checkoutBag 6 + 4 overlap',
      expected: 'fail-closed / ≤1 cs_; ≤1 dono/SKU',
      obtained: {
        'dual': dual,
        'doubleClaim': d1double,
        'sid6': d1six?.sessionId,
        'sid4': d1four?.sessionId,
        'six': d1six?.brief,
        'four': d1four?.brief,
      },
    );
  } else {
    c.block('D1', 'EP-D', '6∥4 fail-closed ≤1', {
      'dual': dual,
      'doubleClaim': d1double,
      'sid6': d1six?.sessionId,
      'sid4': d1four?.sessionId,
      'st6': d1six?.status,
      'st4': d1four?.status,
    });
  }
  c.probe(
    id: 'D1',
    surfaces: 'bag overlap + hold + products',
    action: '6∥4 fail-closed / ≤1 (dual create = P1)',
    http: {'bag6': d1six?.brief, 'bag4': d1four?.brief},
    oracles: {
      'dual': dual,
      'doubleClaim': d1double,
      'sid6': d1six?.sessionId,
      'sid4': d1four?.sessionId,
      'reused6': d1six?.reused,
      'reused4': d1four?.reused,
      'perSku': perSku,
    },
    result: d1fail ? 'FAIL' : 'HOLD',
    lens: 'EP-D',
    classeNova: true,
    race: true,
    countFinding: d1fail,
  );

  await pause(800);

  // D2 — expand (esperado 400)
  final d2 = await plantBag(
    c,
    buyer: b3,
    jwt: c.buyer3Jwt!,
    tag: 'D2-expand',
    n: 4,
    qty: 1,
    price: 9,
  );
  HttpHit? d2sub;
  HttpHit? d2super;
  if (d2.oids.length == 4) {
    d2sub = await c.checkoutBag(
      lines: bagLines(d2.oids, d2.skus, from: 0, to: 2),
      jwt: c.buyer3Jwt,
      buyer: b3,
      seller: s1,
      amount: 1,
    );
    await pause(50);
    d2super = await c.checkoutBag(
      lines: bagLines(d2.oids, d2.skus),
      jwt: c.buyer3Jwt,
      buyer: b3,
      seller: s1,
      amount: 1,
    );
  }
  final dual2 = c.dualCs(d2sub, d2super);
  final expandDenied = d2super != null &&
      (d2super.status == 400 || denied(d2super) || d2super.reused == true);
  var d2double = 0;
  for (final pid in d2.skus) {
    final rows = await c.ordersForProduct(pid);
    if (c.liveClaims(rows) >= 2) d2double++;
  }
  final d2fail = dual2 || d2double > 0 || (c.usefulCs(d2sub) && c.usefulCs(d2super) && !expandDenied);
  if (d2fail) {
    c.hold(
      id: dual2 ? 'P1-D2-EXPAND-DUAL' : 'P1-D2-EXPAND',
      lens: 'EP-D',
      severity: 'P1',
      title: 'expand subset→superset não fail-closed (esperado 400 / ≤1 cs_)',
      actor: 'B3 bag AB depois ABCD',
      pre: '4 SKU qty=1; subset open',
      repro: 'checkoutBag AB; 50ms; checkoutBag ABCD',
      expected: '2.º 400 / contention / reuse; não 2 cs_ distintas',
      obtained: {
        'sub': d2sub?.brief,
        'super': d2super?.brief,
        'dual': dual2,
        'doubleClaim': d2double,
        'sidSub': d2sub?.sessionId,
        'sidSuper': d2super?.sessionId,
      },
    );
  } else {
    c.block('D2', 'EP-D', 'expand 400/reuse/≤1', {
      'sub': d2sub?.brief,
      'super': d2super?.brief,
      'dual': dual2,
      'expandDenied': expandDenied,
    });
  }
  c.probe(
    id: 'D2',
    surfaces: 'bag expand + hold',
    action: 'expand subset→superset (esperado 400)',
    http: {'sub': d2sub?.brief, 'super': d2super?.brief},
    oracles: {
      'dual': dual2,
      'doubleClaim': d2double,
      'sidSub': d2sub?.sessionId,
      'sidSuper': d2super?.sessionId,
      'expandDenied': expandDenied,
    },
    result: d2fail ? 'FAIL' : 'HOLD',
    lens: 'EP-D',
    classeNova: true,
    race: true,
    countFinding: d2fail,
  );

  await pause(600);

  // D3 — bag pago + Hub leftover
  final bagPaid = await c.payBag(buyer: b1, seller: s1);
  c.note('D3.bag', 'setup_paid_bag Stripe TEST 4242', bagPaid.brief, lens: 'EP-D');
  final bm = bagPaid.map ?? {};
  final pa = bm['product_a_id']?.toString();
  final pb = bm['product_b_id']?.toString();
  if (pa != null) c.createdProductIds.add(pa);
  if (pb != null) c.createdProductIds.add(pb);
  final oa = bm['order_a_id']?.toString();
  final ob = bm['order_b_id']?.toString();
  if (oa != null) c.createdOrderIds.add(oa);
  if (ob != null) c.createdOrderIds.add(ob);
  Map<String, dynamic>? prodA;
  Map<String, dynamic>? prodB;
  HttpHit? hubA;
  HttpHit? hubB;
  Map<String, dynamic>? ordA;
  Map<String, dynamic>? ordB;
  if (pa != null) {
    prodA = await c.productRow(pa);
    hubA = await c.hubSku(pa, jwt: c.buyerJwt);
  }
  if (pb != null) {
    prodB = await c.productRow(pb);
    hubB = await c.hubSku(pb, jwt: c.buyerJwt);
  }
  if (oa != null) ordA = await c.orderRow(oa);
  if (ob != null) ordB = await c.orderRow(ob);
  final qA = numOf(prodA?['quantity']) ?? -1;
  final qB = numOf(prodB?['quantity']) ?? -1;
  final nA = hubA?.list.length ?? -1;
  final nB = hubB?.list.length ?? -1;
  final stA = '${ordA?['status'] ?? ''}'.toLowerCase() == 'pago';
  final stB = '${ordB?['status'] ?? ''}'.toLowerCase() == 'pago';
  final d3fail = !bagPaid.ok ||
      !stA ||
      !stB ||
      qA != 2 ||
      qB != 2 ||
      nA != 1 ||
      nB != 1;
  if (!bagPaid.ok) {
    c.skip('D3', 'EP-D', 'setup_paid_bag fail', bagPaid.brief);
  } else if (d3fail) {
    c.hold(
      id: 'P1-D3-BAG-PAGO-HUB',
      lens: 'EP-D',
      severity: (qA != 2 || qB != 2) ? 'P1' : 'P2',
      title: 'bag pago leftover Hub incoerente',
      actor: 'e2e setup_paid_bag 4242',
      pre: '2 SKU qty=3',
      repro: 'setup_paid_bag; products.quantity; hub_products_public',
      expected: 'ambas pago; qty 3→2; Hub 1 cada',
      obtained: {
        'qA': qA,
        'qB': qB,
        'nA': nA,
        'nB': nB,
        'stA': stA,
        'stB': stB,
        'pi': bm['payment_intent_id'],
      },
    );
  } else {
    c.block('D3', 'EP-D', 'bag pago leftover Hub 2', {
      'qA': qA,
      'qB': qB,
      'nA': nA,
      'nB': nB,
      'pi': bm['payment_intent_id'],
    });
  }
  c.probe(
    id: 'D3',
    surfaces: 'bag pago + products + Hub',
    action: 'bag pago + Hub leftover',
    http: bagPaid.brief,
    oracles: {
      'qA': qA,
      'qB': qB,
      'nA': nA,
      'nB': nB,
      'stA': stA,
      'stB': stB,
      'pi': bm['payment_intent_id'],
      'paid_a': bm['paid_a'],
      'paid_b': bm['paid_b'],
    },
    result: !bagPaid.ok ? 'SKIP' : (d3fail ? 'FAIL' : 'HOLD'),
    lens: 'EP-D',
    classeNova: true,
    countFinding: bagPaid.ok && d3fail,
  );
}

Future<void> runE(
  Rtdu c, {
  required String s1,
  required String b1,
  required String b2,
  required String b3,
}) async {
  await pause(600);
  // E1 — pago 4242 + 2.º deny
  final paid1 = await c.payToPago(lens: 'EP-E', initialQty: 1);
  HttpHit? e1ins;
  HttpHit? e1hub;
  Map<String, dynamic>? e1prod;
  Map<String, dynamic>? e1ord;
  if (paid1 != null) {
    e1ord = await c.orderRow(paid1.oid);
    e1prod = await c.productRow(paid1.pid);
    e1hub = await c.hubSku(paid1.pid, jwt: c.buyerJwt);
    e1ins = await c.insertOrderHit(
      productId: paid1.pid,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 12,
    );
  }
  final e1q = numOf(e1prod?['quantity']) ?? -1;
  final e1hubN = e1hub?.list.length ?? -1;
  final e1pago = '${e1ord?['status'] ?? ''}'.toLowerCase() == 'pago';
  final e1insOk = e1ins?.ok == true;
  final e1fail = paid1 != null && e1pago && e1insOk && e1q < 1;
  if (paid1 == null) {
    c.skip('E1', 'EP-E', 'setup_paid_order qty=1 fail', 'null');
  } else if (e1fail) {
    c.hold(
      id: 'P1-E1-SECOND-AFTER-PAID',
      lens: 'EP-E',
      severity: 'P1',
      title: '2.º insert após pago qty=1 aceite',
      actor: 'B2 insert no SKU já pago',
      pre: 'setup_paid_order initial_qty=1',
      repro: 'pago; insertOrder B2',
      expected: '400 hold; Hub 0',
      obtained: {
        'ins': e1ins?.brief,
        'qty': e1q,
        'hub_n': e1hubN,
        'sold': e1prod?['is_sold'],
      },
    );
  } else {
    c.block('E1', 'EP-E', 'pago 4242 + 2.º deny', {
      'ins': e1ins?.brief,
      'qty': e1q,
      'hub_n': e1hubN,
      'pago': e1pago,
      'pi': paid1.pi,
    });
  }
  c.probe(
    id: 'E1',
    surfaces: 'orders + Hub + products + Stripe',
    action: 'pago 4242 + 2.º deny',
    http: {'paid': paid1?.hit.brief, 'ins': e1ins?.brief},
    oracles: {
      'qty': e1q,
      'hub_n': e1hubN,
      'sold': e1prod?['is_sold'],
      'ins_ok': e1insOk,
      'pi': e1ord?['stripe_payment_intent_id'],
      'pago': e1pago,
    },
    result: paid1 == null ? 'SKIP' : (e1fail ? 'FAIL' : 'HOLD'),
    lens: 'EP-E',
    countFinding: e1fail,
  );

  await pause(800);

  // E2 — refund∥nova compra leftover
  final paidL = await c.payToPago(lens: 'EP-E', initialQty: 2);
  HttpHit? e2ins;
  HttpHit? e2cpi;
  HttpHit? e2ref;
  Map<String, dynamic>? e2prodAfter;
  HttpHit? e2hubAfter;
  if (paidL != null) {
    e2ins = await c.insertOrderHit(
      productId: paidL.pid,
      jwt: c.buyer2Jwt,
      buyer: b2,
      price: 5.9,
    );
    final oid2 = e2ins.firstId;
    final raced = await Future.wait([
      c.refund(paidL.oid, jwt: c.sellerJwt),
      if (oid2 != null)
        c.checkout(
          orderId: oid2,
          jwt: c.buyer2Jwt,
          buyer: b2,
          productId: paidL.pid,
          seller: s1,
          amount: 5.9,
        )
      else
        Future.value(e2ins),
    ]);
    e2ref = raced[0];
    e2cpi = raced[1];
    e2prodAfter = await c.productRow(paidL.pid);
    e2hubAfter = await c.hubSku(paidL.pid, jwt: c.buyerJwt);
  }
  final e2rows =
      paidL == null ? <Map<String, dynamic>>[] : await c.ordersForProduct(paidL.pid);
  final e2claims = c.liveClaims(e2rows);
  final e2q = numOf(e2prodAfter?['quantity']) ?? -1;
  // leftover 2, consume 1 paid, leftover 1. B2 hold that 1. Refund restores +1.
  // 2 live claims (pago maybe still live until refund settles + B2 hold) can be OK.
  // FAIL only if 3+ live claims (oversell) or Hub lists while qty=0 with 2 owners.
  final e2hubN = e2hubAfter?.list.length ?? -1;
  final oversell = e2claims >= 3;
  if (paidL == null) {
    c.skip('E2', 'EP-E', 'setup_paid_order leftover fail', 'null');
  } else if (oversell) {
    c.hold(
      id: 'P0-E2-REFUND-OVERSELL',
      lens: 'EP-E',
      severity: 'P0',
      title: 'refund∥nova compra leftover: 3+ claims vivos',
      actor: 'S1 refund ∥ B2 CPI leftover',
      pre: 'pago qty 2→1; B2 hold leftover',
      repro: 'Future.wait refund + CPI B2',
      expected: 'sem oversell; leftover coerente',
      obtained: {
        'claims': e2claims,
        'qty': e2q,
        'hub': e2hubN,
        'ref': e2ref?.brief,
        'cpi': e2cpi?.brief,
      },
    );
  } else {
    c.block('E2', 'EP-E', 'refund∥nova compra leftover', {
      'claims': e2claims,
      'qty': e2q,
      'hub': e2hubN,
      'ref': e2ref?.brief,
      'cpi': e2cpi?.brief,
      'pi': paidL.pi,
    });
  }
  c.probe(
    id: 'E2',
    surfaces: 'refund + CPI leftover + Hub + products',
    action: 'refund∥nova compra leftover',
    http: {
      'paid': paidL?.hit.brief,
      'ins': e2ins?.brief,
      'ref': e2ref?.brief,
      'cpi': e2cpi?.brief,
    },
    oracles: {
      'claims': e2claims,
      'qty': e2q,
      'hub_n': e2hubN,
      'cs': e2cpi?.sessionId,
      'pi': paidL?.pi,
    },
    result: paidL == null ? 'SKIP' : (oversell ? 'FAIL' : 'HOLD'),
    lens: 'EP-E',
    classeNova: true,
    race: true,
    countFinding: oversell,
  );

  await pause(400);

  // E3 — chat card amount vs order após pago
  final paidC = await c.payToPago(lens: 'EP-E', initialQty: 2);
  HttpHit? e3card;
  Map<String, dynamic>? e3ord;
  Map<String, dynamic>? e3prod;
  HttpHit? e3hub;
  List<Map<String, dynamic>> e3chats = [];
  if (paidC != null) {
    e3ord = await c.orderRow(paidC.oid);
    e3prod = await c.productRow(paidC.pid);
    e3hub = await c.hubSku(paidC.pid, jwt: c.buyerJwt);
    final chatId = await c.ensureChat(paidC.pid, buyer: b1, seller: s1);
    final paidCents = numOf(e3ord?['amount_paid_cents']) ?? 590;
    if (chatId != null) {
      e3card = await c.postCard(chatId, {
        'type': 'order_paid',
        'order_id': paidC.oid,
        'amount_cents': paidCents,
        'product_id': paidC.pid,
      });
    }
    e3chats = await c.chatsForProduct(paidC.pid);
  }
  final e3pago = '${e3ord?['status'] ?? ''}'.toLowerCase() == 'pago';
  final e3paid = numOf(e3ord?['amount_paid_cents']) ?? -1;
  final cardOk = e3card?.ok == true;
  var cardAmtMismatch = false;
  if (e3card?.ok == true) {
    final t = e3card!.body;
    if (t.contains('amount_cents') && e3paid > 0) {
      cardAmtMismatch = !t.contains('$e3paid') && !t.contains('590');
    }
  }
  final e3fail = paidC != null && e3pago && (e3paid <= 0 || cardAmtMismatch);
  if (paidC == null) {
    c.skip('E3', 'EP-E', 'setup_paid_order chat fail', 'null');
  } else if (e3fail) {
    c.hold(
      id: 'P2-E3-CHAT-AMOUNT',
      lens: 'EP-E',
      severity: 'P2',
      title: 'chat card amount ≠ order após pago',
      actor: 'B1 postCard vs order.amount_paid_cents',
      pre: 'pago 4242 leftover',
      repro: 'setup_paid_order; POST chat FLEABER_JSON_V1',
      expected: 'card amount = amount_paid_cents; order pago',
      obtained: {
        'paid': e3paid,
        'card': e3card?.brief,
        'status': e3ord?['status'],
      },
    );
  } else {
    c.block('E3', 'EP-E', 'chat card vs order após pago', {
      'paid': e3paid,
      'card_ok': cardOk,
      'chats': e3chats.length,
      'status': e3ord?['status'],
      'hub_n': e3hub?.list.length,
      'qty': e3prod?['quantity'],
      'pi': paidC.pi,
    });
  }
  c.probe(
    id: 'E3',
    surfaces: 'chat card + orders + Hub',
    action: 'chat card amount vs order após pago',
    http: {'paid': paidC?.hit.brief, 'card': e3card?.brief},
    oracles: {
      'amount_paid_cents': e3paid,
      'status': e3ord?['status'],
      'card_ok': cardOk,
      'chats_n': e3chats.length,
      'hub_n': e3hub?.list.length,
      'qty': e3prod?['quantity'],
      'pi': paidC?.pi,
    },
    result: paidC == null ? 'SKIP' : (e3fail ? 'FAIL' : 'HOLD'),
    lens: 'EP-E',
    classeNova: true,
    countFinding: e3fail,
  );
}
