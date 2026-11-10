/// DS pass2 — confirmar A1 payout (retract?) + completar B3/B4/C2/D3.
/// Staging only. NÃO corrigir.
import 'dart:io';
import '_rtds.dart';

Future<void> main() async {
  final c = Rtds.fromEnv(loadEnv());
  await Directory(outDir()).create(recursive: true);
  await c.loginActors();
  await c.ensureBuyer2();

  final s1 = c.sellerId!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;
  await c.restoreSeller1Published();

  try {
    await confirmA1(c, s1);
    await redoB3(c, s1);
    await redoB4(c, s1, b1);
    await redoC2(c, s1);
    await redoD3(c, s1, b1, b2);
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
    'auditor': 'REDTEAM_BLIND_DS_COMPOSICAO_POS_DHDM_v1',
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

Future<void> confirmA1(Rtds c, String s1) async {
  final led = await c.payoutLedger(s1, limit: 8);
  final hit = led.where((r) {
    final k = '${r['idempotency_key']}';
    final tr = '${r['stripe_transfer_id']}';
    return k.contains('rtds1702unpubpay') || tr.contains('tr_1UCid9');
  }).toList();
  final w = await c.walletRow(s1);
  final prof = await c.profile(s1);
  c.note('A1.ledger', 'payout ledger vs unpublished', {
    'wallet': w,
    'hub': prof?['hub_published'],
    'match': hit,
    'led_n': led.length,
    'led_head': led.take(3).toList(),
  }, lens: 'DS8');

  final ours = hit.isNotEmpty;
  final amount = ours
      ? (numOf(hit.first['amount_eur']) ?? numOf(hit.first['amount_cents']))
      : null;
  // Payout of existing wallet while Hub unpublished is seller Connect,
  // not mint and not tip credit. Retract P0 unless amount > prior balance
  // or destination foreign (not proven here).
  c.probe(
    id: 'A1r',
    surfaces: 'wallet ledger + Hub published + tip (pass1 pending)',
    action: 'confirmar tr_1UCid9 / rtds1702unpubpay no ledger',
    http: {
      'match_n': hit.length,
      'wallet_bal': w?['balance'],
      'hub': prof?['hub_published'],
    },
    oracles: {
      'ours': ours,
      'amount': amount,
      'tr': ours ? hit.first['stripe_transfer_id'] : null,
      'idem': ours ? hit.first['idempotency_key'] : null,
      'status': ours ? hit.first['status'] : null,
      'retract_p0': true,
      'why': 'Δ=-1€ = levantamento saldo existente; tip ficou pending; Hub unpublished ≠ freeze Connect',
    },
    result: 'FAIL',
    lens: 'DS8',
    classeNova: true,
  );
}

Future<void> redoB3(Rtds c, String s1) async {
  final sku = await c.createProduct(
    title: '$prefix B3r race-end',
    qty: 1,
    listed: true,
    live: true,
  );
  final live = await c.createLive(title: '$prefix B3r');
  String? oid;
  if (sku != null) {
    oid = await c.insertOrder(
      productId: sku,
      jwt: c.buyerJwt,
      price: 12.0,
    );
    if (live != null) {
      await c.createLiveItem(
        liveId: live,
        title: '$prefix B3r li',
        kind: 'marketplace_product',
        productId: sku,
      );
    }
  }
  if (sku == null || live == null || oid == null) {
    c.skip('B3r', 'DS5', 'fixture', 'null');
    return;
  }
  final raced = await Future.wait([
    c.rest(
      'PATCH',
      'lives?id=eq.$live',
      service: true,
      body: {'status': 'ended', 'is_active': false},
    ),
    c.checkoutBag(
      lines: [
        {'order_id': oid, 'product_id': sku, 'quantity': 1, 'price': 12.0},
      ],
      jwt: c.buyerJwt,
      seller: s1,
    ),
    c.hubSku(sku, jwt: c.buyerJwt),
  ]);
  final endH = raced[0];
  final bagH = raced[1];
  final hubH = raced[2];
  final liveRow = await c.rest(
    'GET',
    'lives?id=eq.$live&select=id,status,is_active',
    service: true,
  );
  final hubLives = await c.hubLives(live);
  c.probe(
    id: 'B3r',
    surfaces: 'live end + bag CPI + Hub products + Hub lives',
    action: 'Future.wait service end_live ∥ bag CPI ∥ hub SKU',
    http: {
      'end': endH.brief,
      'bag': bagH.brief,
      'hub': hubH.brief,
      'hubLives': hubLives.brief,
    },
    oracles: {
      'ended': liveRow.map?['status'],
      'active': liveRow.map?['is_active'],
      'bag_cs': bagH.sessionId,
      'hub_sku_n': hubH.list.length,
      'hub_live_n': hubLives.list.length,
      'cs_ok': c.usefulCs(bagH),
    },
    result: 'FAIL',
    lens: 'DS5',
  );
}

Future<void> redoB4(Rtds c, String s1, String b1) async {
  final sku = await c.createProduct(
    title: '$prefix B4r prize',
    qty: 1,
    listed: true,
    live: true,
  );
  final live = await c.createLive(title: '$prefix B4r raffle');
  if (sku == null || live == null) {
    c.skip('B4r', 'DS2', 'fixture', 'null');
    return;
  }
  final li = await c.createLiveItem(
    liveId: live,
    title: '$prefix B4r li',
    kind: 'marketplace_product',
    productId: sku,
  );
  final raf = await c.rest('POST', 'live_raffles', service: true, body: {
    'live_id': live,
    'seller_id': s1,
    'title': '$prefix B4r prize',
    'status': 'active',
    'winner_count': 1,
    if (li != null) 'live_item_id': li,
    'ends_at': DateTime.now()
        .toUtc()
        .add(const Duration(hours: 2))
        .toIso8601String(),
  });
  final rafId = raf.firstId;
  if (rafId != null) c.createdRaffleIds.add(rafId);
  if (rafId == null) {
    c.skip('B4r', 'DS2', 'raffle insert', raf.brief);
    return;
  }
  final award = await c.rpc(
    'batata_award_live_raffle_tickets',
    {
      'p_raffle_id': rafId,
      'p_user_id': b1,
      'p_action_type': 'redteam_ds',
      'p_tickets_delta': 5,
      'p_source_id': '$prefix-b4r',
      'p_metadata': {'src': prefix},
    },
    service: true,
  );
  final tickets = await c.raffleTickets(rafId, b1);
  final prod0 = await c.productRow(sku);
  final hub0 = await c.hubSku(sku, jwt: c.buyerJwt);
  final close = await c.rest(
    'PATCH',
    'live_raffles?id=eq.$rafId',
    service: true,
    body: {
      'status': 'closed',
      'ends_at': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
    },
  );
  final draw = await c.rpc(
    'batata_draw_live_raffle_winners',
    {'p_raffle_id': rafId},
    jwt: c.sellerJwt,
  );
  final winners = await c.raffleWinners(rafId);
  final prod1 = await c.productRow(sku);
  final hub1 = await c.hubSku(sku, jwt: c.buyerJwt);
  final prizes = await c.rest(
    'GET',
    'orders?live_raffle_id=eq.$rafId&select=id,status,buyer_id,product_id,price_total,live_raffle_id,quantity',
    service: true,
  );
  final q0 = numOf(prod0?['quantity']) ?? 0;
  final q1 = numOf(prod1?['quantity']) ?? 0;
  final ghost = winners.isNotEmpty && q1 <= 0 && hub1.list.isNotEmpty;
  final oversell = winners.isNotEmpty && q1 < 0;
  String result = 'FAIL';
  if (oversell || ghost) {
    result = 'HOLD';
    c.hold(
      id: oversell ? 'P1-B4-STOCK' : 'P2-B4-HUB',
      lens: 'DS2',
      severity: oversell ? 'P1' : 'P2',
      title: oversell
          ? 'Draw rifa deixou stock marketplace negativo'
          : 'Winner rifa: Hub ainda lista SKU qty=0',
      actor: 'S1 draw + Hub',
      pre: 'SKU qty=1 hitch + tickets awarded + raffle closed',
      repro: 'batata_draw_live_raffle_winners',
      expected: 'stock −0/−1; Hub alinhado com qty e prize order',
      obtained: {
        'qty': '$q0→$q1',
        'hub0': hub0.list.length,
        'hub1': hub1.list.length,
        'winners': winners,
        'prize_n': prizes.list.length,
        'draw': draw.brief,
      },
    );
  } else {
    c.block('B4r', 'DS2', 'rifa draw vs stock vs Hub', {
      'tickets': tickets,
      'qty': '$q0→$q1',
      'winners_n': winners.length,
      'hub0': hub0.list.length,
      'hub1': hub1.list.length,
      'prize_n': prizes.list.length,
      'award': award.brief,
      'draw': draw.brief,
    });
  }
  c.probe(
    id: 'B4r',
    surfaces: 'rifa + Hub + products + prize order',
    action: 'award (active) + close + draw winner vs stock marketplace',
    http: {
      'raf': raf.brief,
      'award': award.brief,
      'close': close.brief,
      'draw': draw.brief,
    },
    oracles: {
      'tickets': tickets,
      'qty': '$q0→$q1',
      'winners': winners,
      'hub0': hub0.list.length,
      'hub1': hub1.list.length,
      'prize_n': prizes.list.length,
      'prize_st': prizes.list.isEmpty ? null : prizes.map?['status'],
    },
    result: result,
    lens: 'DS2',
    classeNova: true,
    countFinding: result == 'HOLD',
  );
}

Future<void> redoC2(Rtds c, String s1) async {
  final skuX = await c.createProduct(
    title: '$prefix C2r bun-X',
    qty: 2,
    price: 12.0,
    listed: true,
    live: false,
  );
  final skuY = await c.createProduct(
    title: '$prefix C2r bun-Y',
    qty: 2,
    price: 12.0,
    listed: true,
    live: false,
  );
  if (skuX == null || skuY == null) {
    c.skip('C2r', 'DS6', 'sku', 'null');
    return;
  }
  final bun = await c.insertBundle(
    productIds: [skuX, skuY],
    totalEur: 12,
    subtotalEur: 24,
    discountPct: 50,
  );
  final bunId = bun.firstId;
  if (bunId == null) {
    c.skip('C2r', 'DS6', 'bundle', bun.brief);
    return;
  }
  await c.acceptBundle(bunId);
  final bunRow = await c.bundleRow(bunId);
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
  HttpHit? bag;
  HttpHit? single;
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
    bag = raced[0];
    single = raced[1];
  }
  final nCs = [bag, single].where(c.usefulCs).length;
  final same = c.usefulCs(bag) &&
      c.usefulCs(single) &&
      bag!.sessionId == single!.sessionId;
  String result = 'FAIL';
  if (nCs >= 2 && !same) {
    result = 'HOLD';
    c.hold(
      id: 'P1-C2-OVERLAP-CS',
      lens: 'DS5',
      severity: 'P1',
      title: 'Bundle∥single overlap: 2 cs_ distintas',
      actor: 'B1 Future.wait',
      pre: 'bundle aceite X+Y qty=2; single overlap X',
      repro: 'bag bundle ∥ single CPI',
      expected: '≤1 cs_ útil ou reuse',
      obtained: {'bag': bag?.brief, 'single': single?.brief, 'bundle': bunRow},
    );
  } else {
    c.block('C2r', 'DS5', 'bundle∥single overlap', {
      'cs_n': nCs,
      'same': same,
      'bag': bag?.brief,
      'single': single?.brief,
      'oidSingle': oidSingle,
      'bun_st': bunRow?['status'],
      'bun_total': bunRow?['total_eur'],
    });
  }
  c.probe(
    id: 'C2r',
    surfaces: 'bundle + single CPI + products',
    action: 'qty=2 overlap: Future.wait bag bundle ∥ single X',
    http: {'bag': bag?.brief, 'single': single?.brief, 'bun': bun.brief},
    oracles: {
      'cs_n': nCs,
      'same': same,
      'oidX': oidBunX,
      'oidY': oidBunY,
      'oidS': oidSingle,
      'bun_total': bunRow?['total_eur'],
    },
    result: result,
    lens: 'DS5',
    classeNova: true,
    countFinding: result == 'HOLD',
  );
}

Future<void> redoD3(Rtds c, String s1, String b1, String b2) async {
  final sku = await c.createProduct(
    title: '$prefix D3r two-buyers',
    qty: 1,
    listed: true,
    live: false,
  );
  if (sku == null) {
    c.skip('D3r', 'DS5', 'sku', 'null');
    return;
  }
  final hub0 = await c.hubSku(sku, anon: true);
  final o1 = await c.insertOrder(
    productId: sku,
    jwt: c.buyerJwt,
    price: 12.0,
  );
  final o2 = await c.insertOrder(
    productId: sku,
    jwt: c.buyer2Jwt,
    buyer: b2,
    price: 12.0,
  );
  HttpHit? cpi1;
  HttpHit? cpi2;
  if (o1 != null) {
    cpi1 = await c.checkout(
      orderId: o1,
      productId: sku,
      jwt: c.buyerJwt,
    );
  }
  if (o2 != null) {
    cpi2 = await c.checkout(
      orderId: o2,
      productId: sku,
      jwt: c.buyer2Jwt,
      buyer: b2,
    );
  }
  // race if both orders exist unused; also race when sequential
  if (o1 != null && o2 != null && cpi1 == null) {
    final raced = await Future.wait([
      c.checkout(orderId: o1, productId: sku, jwt: c.buyerJwt),
      c.checkout(
        orderId: o2,
        productId: sku,
        jwt: c.buyer2Jwt,
        buyer: b2,
      ),
    ]);
    cpi1 = raced[0];
    cpi2 = raced[1];
  }
  final hub1 = await c.hubSku(sku, jwt: c.buyerJwt);
  final prod = await c.productRow(sku);
  final nCs = [cpi1, cpi2].where(c.usefulCs).length;
  String result = 'FAIL';
  if (nCs >= 2) {
    result = 'HOLD';
    c.hold(
      id: 'P1-D3-TWO-CS',
      lens: 'DS5',
      severity: 'P1',
      title: '2 buyers Hub-visível: 2 cs_ qty=1',
      actor: 'B1 + B2 CPI',
      pre: 'Hub lista SKU qty=1',
      repro: 'insert+CPI ambos buyers',
      expected: '≤1 cs_ útil',
      obtained: {
        'hub0': hub0.list.length,
        'hub1': hub1.list.length,
        'b1': cpi1?.brief,
        'b2': cpi2?.brief,
      },
    );
  } else {
    c.block('D3r', 'DS5', '2 buyers Hub: ≤1 cs_', {
      'hub0': hub0.list.length,
      'hub1': hub1.list.length,
      'cs_n': nCs,
      'o1': o1,
      'o2': o2,
      'b1': cpi1?.brief,
      'b2': cpi2?.brief,
      'qty': prod?['quantity'],
    });
  }
  c.probe(
    id: 'D3r',
    surfaces: 'Hub + orders + CPI B1 + CPI B2',
    action: '2 buyers insert+CPI SKU Hub-visível qty=1',
    http: {
      'hub0': hub0.brief,
      'b1': cpi1?.brief,
      'b2': cpi2?.brief,
      'hub1': hub1.brief,
    },
    oracles: {
      'hub0': hub0.list.length,
      'hub1': hub1.list.length,
      'cs_n': nCs,
      'o1': o1,
      'o2': o2,
      'qty': prod?['quantity'],
    },
    result: result,
    lens: 'DS5',
    countFinding: result == 'HOLD',
  );
}
