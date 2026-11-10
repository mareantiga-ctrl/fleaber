/// REDTEAM_BLIND_DI_OFERTAS_CHAT_POS_DBDG_v1
/// Staging only. NÃO CORRIGIR. Fase 4 não. Residual 12,00 ≤1 HOLD — não contar.
import 'dart:io';

import '_rtdi.dart';

Future<void> main() async {
  final c = Rtdi.fromEnv(loadEnv());
  stdout.writeln('DI pass1 staging=${c.url} prefix=$prefix');
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  c.note('actors', 'ids', {
    'b': c.buyerId,
    's': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
  });
  final wal0 = await c.wallets();
  c.note('wallet.pre', 'baseline', wal0, lens: 'DI7');

  await diAOffers(c);
  await diBBundles(c);
  await diCChat(c, wal0);

  final wal1 = await c.wallets();
  c.note('wallet.post', 'após probes', {'pre': wal0, 'post': wal1}, lens: 'DI7');

  await c.cancelOrders(c.createdOrderIds);
  for (final sid in c.createdSessionIds.toSet()) {
    if (sid.startsWith('cs_')) await c.stripeExpire(sid);
  }

  await c.dumpAll('pass1.json');
  await dumpJson('${outDir()}/probes.json', {
    'auditor': 'REDTEAM_BLIND_DI_OFERTAS_CHAT_POS_DBDG_v1',
    'stamp': stamp,
    'prefix': prefix,
    'probes': c.probes,
    'n': c.probes.length,
    'findings': c.findings,
    'blocked': c.blocked,
    'skipped': c.skipped,
    'lenses': c.lensesHit.toList()..sort(),
    'wells': c.wellsTried.toList()..sort(),
  });
  stdout.writeln(
    'DONE probes=${c.probes.length} findings=${c.findings.length} '
    'blocked=${c.blocked.length} skip=${c.skipped.length} '
    'lenses=${c.lensesHit.toList()..sort()}',
  );
}

bool underpay(HttpHit ck, int floorCents) =>
    ck.ok && ck.amountTotal != null && ck.amountTotal! < floorCents;

Future<String?> sku(
  Rtdi c, {
  required String tag,
  int qty = 3,
  double price = 18,
  bool listed = true,
  bool sold = false,
}) {
  return c.createProduct(
    title: '$prefix-$tag',
    qty: qty,
    price: price,
    listed: listed,
    sold: sold,
  );
}

Future<HttpHit> acceptOffer(Rtdi c, String offerId, {String? jwt}) {
  return c.rest(
    'PATCH',
    'product_offers?id=eq.$offerId',
    jwt: jwt ?? c.sellerJwt,
    body: {'status': 'accepted'},
  );
}

Future<HttpHit> rejectOffer(Rtdi c, String offerId, {String? jwt}) {
  return c.rest(
    'PATCH',
    'product_offers?id=eq.$offerId',
    jwt: jwt ?? c.buyerJwt,
    body: {'status': 'rejected'},
  );
}

List<Map<String, Object?>> bagLines(Iterable<({String oid, String pid})> rows) {
  return [
    for (final r in rows) {'order_id': r.oid, 'product_id': r.pid},
  ];
}

Future<void> diAOffers(Rtdi c) async {
  // A1 — INSERT hostil status=accepted amount=0.01 (catálogo 18€)
  final pA1 = await sku(c, tag: 'a1', price: 18, qty: 2);
  if (pA1 == null) {
    c.skip('A1', 'DI1', 'sem SKU', null);
    return;
  }
  final insA1 = await c.insertOffer(
    productId: pA1,
    amount: 0.01,
    listPrice: 18,
    status: 'accepted',
  );
  final a1id = insA1.firstId;
  final a1row = a1id == null ? null : await c.offerRow(a1id);
  final a1st = '${a1row?['status']}';
  final a1amt = numOf(a1row?['amount']);
  final autoAcc = a1st == 'accepted';
  c.note('A1.insert', 'offer hostil status=accepted amount=0.01', {
    'ins': insA1.brief,
    'row': a1row,
  }, lens: 'DI1', well: 'DI-A');
  if (autoAcc) {
    c.hold(
      id: 'P0-A1',
      lens: 'DI1',
      severity: 'P0',
      title: 'Oferta 0,01€ inserida já aceite (sem vendedor)',
      actor: 'buyer JWT',
      pre: 'SKU 18€; POST status=accepted amount=0.01',
      repro: 'POST product_offers status=accepted amount=0.01',
      expected: 'status=pending ou reject',
      obtained: a1row,
    );
    c.probe(
      id: 'A1',
      poco: 'DI-A',
      payload: 'POST offer amount=0.01 status=accepted',
      http: insA1,
      bd: a1row,
      verdict: 'HOLD',
      lens: 'DI1',
    );
  } else {
    c.block('A1', 'DI1', 'INSERT não auto-aceita; amount persistido=$a1amt status=$a1st',
        insA1.brief);
    c.probe(
      id: 'A1',
      poco: 'DI-A',
      payload: 'POST offer amount=0.01 status=accepted no body',
      http: insA1,
      bd: 'status=$a1st amount=$a1amt',
      verdict: 'FAIL',
      lens: 'DI1',
    );
  }

  // A1b — oferta honesta 8€ aceite; CPI amount=1 (body hostil)
  final pA1b = await sku(c, tag: 'a1b', price: 18, qty: 2);
  HttpHit ckA1b = HttpHit(0, 'no', {});
  if (pA1b != null) {
    final off = await c.insertOffer(productId: pA1b, amount: 8, listPrice: 18);
    final oidOff = off.firstId;
    if (oidOff != null) {
      final acc = await acceptOffer(c, oidOff);
      final order = await c.insertOrder(
        productId: pA1b,
        price: 1,
        offerId: oidOff,
        jwt: c.buyerJwt,
      );
      if (order != null) {
        ckA1b = await c.checkout(
          orderId: order,
          productId: pA1b,
          amount: 1,
        );
        c.trackSession(ckA1b);
      }
      c.note('A1b.cpi', 'offer 8€ aceite + CPI amount=1', {
        'off': off.brief,
        'acc': acc.brief,
        'ck': ckA1b.brief,
        'amt': ckA1b.amountTotal,
        'order': order,
      }, lens: 'DI1', well: 'DI-A');
    }
  }
  // 8€ + protecção ~1,05€ ≈ 905¢; body 1€ seria ~170¢. Floor 400¢.
  if (underpay(ckA1b, 400)) {
    c.hold(
      id: 'P0-A1b',
      lens: 'DI1',
      severity: 'P0',
      title: 'CPI body amount=1 venceu oferta aceite 8€',
      actor: 'buyer JWT',
      pre: 'product_offers.amount=8 accepted',
      repro: 'INSERT order product_offer_id; CPI amount=1',
      expected: 'amount_total ≈ 905¢ (8€+taxas)',
      obtained: ckA1b.brief,
    );
    c.probe(
      id: 'A1b',
      poco: 'DI-A',
      payload: 'oferta 8€ aceite + CPI amount=1',
      http: ckA1b,
      bd: ckA1b.amountTotal,
      verdict: 'HOLD',
      lens: 'DI1',
    );
  } else {
    c.block('A1b', 'DI1', 'CPI usou oferta 8€ (não body 1€)', {
      'amt': ckA1b.amountTotal,
      'status': ckA1b.status,
    });
    c.probe(
      id: 'A1b',
      poco: 'DI-A',
      payload: 'oferta 8€ aceite + CPI amount=1 (fluxo terminal quote)',
      http: ckA1b,
      bd: 'amount_total=${ckA1b.amountTotal}',
      verdict: ckA1b.ok ? 'PASS' : 'FAIL',
      lens: 'DI1',
    );
  }

  // A1c — PATCH amount após pending (imutável)
  final pA1c = await sku(c, tag: 'a1c', price: 18, qty: 2);
  if (pA1c != null) {
    final off = await c.insertOffer(productId: pA1c, amount: 8, listPrice: 18);
    final oidOff = off.firstId;
    HttpHit patch = HttpHit(0, 'no', {});
    Map<String, dynamic>? after;
    if (oidOff != null) {
      patch = await c.rest(
        'PATCH',
        'product_offers?id=eq.$oidOff',
        jwt: c.buyerJwt,
        body: {'amount': 0.01},
      );
      after = await c.offerRow(oidOff);
    }
    final mutated = numOf(after?['amount']) != null &&
        (numOf(after?['amount'])! - 8).abs() > 0.02;
    c.note('A1c.patch', 'PATCH amount=0.01 pending', {
      'patch': patch.brief,
      'after': after,
    }, lens: 'DI1', well: 'DI-A');
    if (mutated) {
      c.hold(
        id: 'P1-A1c',
        lens: 'DI1',
        severity: 'P1',
        title: 'Buyer alterou amount da oferta pending',
        actor: 'buyer JWT',
        pre: 'amount=8 pending',
        repro: 'PATCH product_offers.amount=0.01',
        expected: 'offer_amount_immutable',
        obtained: after,
      );
      c.probe(
        id: 'A1c',
        poco: 'DI-A',
        payload: 'PATCH amount=0.01 em oferta pending',
        http: patch,
        bd: after,
        verdict: 'HOLD',
        lens: 'DI1',
      );
    } else {
      c.block('A1c', 'DI1', 'amount imutável', patch.brief);
      c.probe(
        id: 'A1c',
        poco: 'DI-A',
        payload: 'PATCH amount=0.01 em oferta pending',
        http: patch,
        bd: 'amount=${after?['amount']}',
        verdict: 'FAIL',
        lens: 'DI1',
      );
    }
  }

  // A2 — accept ∥ reject race
  final pA2 = await sku(c, tag: 'a2', price: 18, qty: 2);
  if (pA2 != null) {
    final off = await c.insertOffer(productId: pA2, amount: 8, listPrice: 18);
    final oidOff = off.firstId;
    if (oidOff != null) {
      final raced = await parallel([
        acceptOffer(c, oidOff),
        rejectOffer(c, oidOff),
      ]);
      final row = await c.offerRow(oidOff);
      final st = '${row?['status']}';
      final order = await c.insertOrder(
        productId: pA2,
        price: 8,
        offerId: oidOff,
        jwt: c.buyerJwt,
      );
      HttpHit ck = HttpHit(0, 'no_order', {});
      if (order != null) {
        ck = await c.checkout(orderId: order, productId: pA2, amount: 1);
        c.trackSession(ck);
      }
      final sealed = order == null
          ? null
          : (await c.orderRow(order))?['contract_unit_cents'];
      final usedRejected = st == 'rejected' &&
          ck.ok &&
          ck.amountTotal != null &&
          ck.amountTotal! < 1200 &&
          (numOf(sealed) ?? 0) > 0 &&
          (numOf(sealed)! - 800).abs() < 2;
      c.note('A2.race', 'accept ∥ reject', {
        'acc': raced[0].brief,
        'rej': raced[1].brief,
        'st': st,
        'ck': ck.brief,
        'sealed': sealed,
        'order': order,
      }, lens: 'DI2', well: 'DI-A');
      if (usedRejected) {
        c.hold(
          id: 'P1-A2',
          lens: 'DI2',
          severity: 'P1',
          title: 'Oferta rejected ainda selou 8€ no checkout',
          actor: 'buyer JWT',
          pre: 'Future.wait accept∥reject',
          repro: 'INSERT order product_offer_id; CPI',
          expected: 'catálogo 18€ ou bloqueio se rejected',
          obtained: {'status': st, 'ck': ck.brief, 'sealed': sealed},
        );
        c.probe(
          id: 'A2',
          poco: 'DI-A',
          payload: 'accept ∥ reject Future.wait',
          http: {'acc': raced[0].brief, 'rej': raced[1].brief, 'ck': ck.brief},
          bd: 'status=$st sealed=$sealed amt=${ck.amountTotal}',
          verdict: 'HOLD',
          lens: 'DI2',
        );
      } else {
        c.block('A2', 'DI2', 'corrida terminal única status=$st', {
          'st': st,
          'amt': ck.amountTotal,
          'sealed': sealed,
        });
        c.probe(
          id: 'A2',
          poco: 'DI-A',
          payload: 'accept ∥ reject Future.wait',
          http: {'acc': raced[0].brief, 'rej': raced[1].brief, 'ck': ck.brief},
          bd: 'status=$st sealed=$sealed amt=${ck.amountTotal}',
          verdict: 'FAIL',
          lens: 'DI2',
        );
      }
    }
  }

  // A3 — stale rejected + CPI
  final pA3 = await sku(c, tag: 'a3', price: 18, qty: 2);
  if (pA3 != null) {
    final off = await c.insertOffer(productId: pA3, amount: 2, listPrice: 18);
    final oidOff = off.firstId;
    HttpHit ck = HttpHit(0, 'no', {});
    Map<String, dynamic>? orow;
    if (oidOff != null) {
      await rejectOffer(c, oidOff, jwt: c.sellerJwt);
      final order = await c.insertOrder(
        productId: pA3,
        price: 2,
        offerId: oidOff,
        jwt: c.buyerJwt,
      );
      if (order != null) {
        orow = await c.orderRow(order);
        ck = await c.checkout(orderId: order, productId: pA3, amount: 1);
        c.trackSession(ck);
      }
    }
    final bound = orow?['product_offer_id']?.toString();
    final sealed = numOf(orow?['contract_unit_cents']);
    final stale = ck.ok &&
        ck.amountTotal != null &&
        ck.amountTotal! < 400 &&
        (sealed == null || sealed <= 250);
    c.note('A3.stale', 'rejected + CPI', {
      'ck': ck.brief,
      'bound': bound,
      'sealed': sealed,
      'amt': ck.amountTotal,
    }, lens: 'DI1', well: 'DI-A');
    if (stale) {
      c.hold(
        id: 'P0-A3',
        lens: 'DI1',
        severity: 'P0',
        title: 'Oferta rejected ainda underpay no CPI',
        actor: 'buyer JWT',
        pre: 'product_offers.status=rejected amount=2',
        repro: 'INSERT order product_offer_id; CPI',
        expected: 'catálogo 18€ ou bloqueio',
        obtained: ck.brief,
      );
      c.probe(
        id: 'A3',
        poco: 'DI-A',
        payload: 'offer rejected amount=2 + CPI',
        http: ck,
        bd: 'offer_id=$bound sealed=$sealed amt=${ck.amountTotal}',
        verdict: 'HOLD',
        lens: 'DI1',
      );
    } else {
      c.block('A3', 'DI1', 'stale rejected não underpay', {
        'amt': ck.amountTotal,
        'bound': bound,
        'sealed': sealed,
      });
      c.probe(
        id: 'A3',
        poco: 'DI-A',
        payload: 'offer rejected amount=2 + CPI',
        http: ck,
        bd: 'offer_id=$bound sealed=$sealed amt=${ck.amountTotal}',
        verdict: 'FAIL',
        lens: 'DI1',
      );
    }
  }

  // A4 — qty>1 com oferta (deve ser 1)
  final pA4 = await sku(c, tag: 'a4', price: 18, qty: 5);
  if (pA4 != null) {
    final off = await c.insertOffer(productId: pA4, amount: 8, listPrice: 18);
    final oidOff = off.firstId;
    HttpHit ins = HttpHit(0, 'no', {});
    if (oidOff != null) {
      await acceptOffer(c, oidOff);
      ins = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': pA4,
        'price_total': 8,
        'quantity': 3,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'entrega em mão',
        'product_offer_id': oidOff,
      });
      if (ins.firstId != null) c.createdOrderIds.add(ins.firstId!);
    }
    final qtyOk = ins.ok;
    c.note('A4.qty', 'order qty=3 + offer', ins.brief, lens: 'DI4', well: 'DI-A');
    if (qtyOk) {
      final row = await c.orderRow(ins.firstId!);
      final q = numOf(row?['quantity'])?.round();
      final sealedQ = numOf(row?['contract_qty'])?.round();
      if ((q ?? 0) > 1 || (sealedQ ?? 0) > 1) {
        c.hold(
          id: 'P1-A4',
          lens: 'DI4',
          severity: 'P1',
          title: 'Oferta aceite ligada a quantity>1',
          actor: 'buyer JWT',
          pre: 'offer accepted; stock 5',
          repro: 'POST orders quantity=3 product_offer_id',
          expected: 'offer_quantity_must_be_one',
          obtained: row,
        );
        c.probe(
          id: 'A4',
          poco: 'DI-A',
          payload: 'order qty=3 com product_offer_id aceite',
          http: ins,
          bd: 'qty=$q contract_qty=$sealedQ',
          verdict: 'HOLD',
          lens: 'DI4',
        );
      } else {
        c.block('A4', 'DI4', 'qty forçada a 1', row);
        c.probe(
          id: 'A4',
          poco: 'DI-A',
          payload: 'order qty=3 com product_offer_id aceite',
          http: ins,
          bd: 'qty=$q contract_qty=$sealedQ',
          verdict: 'FAIL',
          lens: 'DI4',
        );
      }
    } else {
      c.block('A4', 'DI4', 'qty>1 recusada', ins.brief);
      c.probe(
        id: 'A4',
        poco: 'DI-A',
        payload: 'order qty=3 com product_offer_id aceite',
        http: ins,
        bd: 'recusado',
        verdict: 'FAIL',
        lens: 'DI4',
      );
    }
  }

  // A5 — unpublished / sold
  final pUn = await sku(c, tag: 'a5u', price: 18, qty: 2, listed: false);
  final pSold = await sku(c, tag: 'a5s', price: 18, qty: 2, sold: true);
  final insUn = pUn == null
      ? HttpHit(0, 'no_sku', {})
      : await c.insertOffer(productId: pUn, amount: 8, listPrice: 18);
  HttpHit accSold = HttpHit(0, 'no', {});
  HttpHit insSold = HttpHit(0, 'no', {});
  if (pSold != null) {
    insSold = await c.insertOffer(productId: pSold, amount: 8, listPrice: 18);
    final sid = insSold.firstId;
    if (sid != null) {
      accSold = await acceptOffer(c, sid);
    }
  }
  // listed live SKU then unlist then accept
  final pLive = await sku(c, tag: 'a5live', price: 18, qty: 2);
  HttpHit accUnlist = HttpHit(0, 'no', {});
  Map<String, dynamic>? accUnlistRow;
  if (pLive != null) {
    final off = await c.insertOffer(productId: pLive, amount: 8, listPrice: 18);
    final oidOff = off.firstId;
    await c.rest(
      'PATCH',
      'products?id=eq.$pLive',
      service: true,
      body: {'list_on_marketplace': false},
    );
    if (oidOff != null) {
      accUnlist = await acceptOffer(c, oidOff);
      accUnlistRow = await c.offerRow(oidOff);
    }
  }
  final unOk = insUn.ok;
  final soldAcc = accSold.ok || '${accUnlistRow?['status']}' == 'accepted';
  c.note('A5.dead', 'unpublished/sold', {
    'insUn': insUn.brief,
    'insSold': insSold.brief,
    'accSold': accSold.brief,
    'accUnlist': accUnlist.brief,
    'unlistRow': accUnlistRow,
  }, lens: 'DI4', well: 'DI-A');
  if (unOk || soldAcc) {
    c.hold(
      id: 'P1-A5',
      lens: 'DI4',
      severity: 'P1',
      title: 'Oferta em SKU unpublished/sold',
      actor: 'buyer/seller JWT',
      pre: 'list_on_marketplace=false ou is_sold=true',
      repro: 'POST product_offers / PATCH accepted',
      expected: 'offer_product_not_listed',
      obtained: {
        'insUn': insUn.brief,
        'accSold': accSold.brief,
        'accUnlist': accUnlist.brief,
        'st': accUnlistRow?['status'],
      },
    );
    c.probe(
      id: 'A5',
      poco: 'DI-A',
      payload: 'offer unpublished INSERT + sold/unlist accept',
      http: {
        'un': insUn.brief,
        'sold': accSold.brief,
        'unlist': accUnlist.brief,
      },
      bd: accUnlistRow,
      verdict: 'HOLD',
      lens: 'DI4',
    );
  } else {
    c.block('A5', 'DI4', 'unpublished/sold recusados', {
      'un': insUn.status,
      'sold': accSold.status,
      'unlist': accUnlist.status,
    });
    c.probe(
      id: 'A5',
      poco: 'DI-A',
      payload: 'offer unpublished INSERT + sold/unlist accept',
      http: {
        'un': insUn.brief,
        'soldAcc': accSold.brief,
        'unlistAcc': accUnlist.brief,
      },
      bd: 'recusado',
      verdict: 'FAIL',
      lens: 'DI4',
    );
  }

  // A6 — one-shot reuse
  final pA6 = await sku(c, tag: 'a6', price: 18, qty: 4);
  if (pA6 != null) {
    final off = await c.insertOffer(productId: pA6, amount: 8, listPrice: 18);
    final oidOff = off.firstId;
    HttpHit second = HttpHit(0, 'no', {});
    String? firstId;
    if (oidOff != null) {
      await acceptOffer(c, oidOff);
      firstId = await c.insertOrder(
        productId: pA6,
        price: 8,
        offerId: oidOff,
        jwt: c.buyerJwt,
      );
      second = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': pA6,
        'price_total': 8,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Pagamento na app',
        'shipping_method': 'entrega em mão',
        'product_offer_id': oidOff,
      });
      if (second.firstId != null) c.createdOrderIds.add(second.firstId!);
    }
    final reused = second.ok;
    Map<String, dynamic>? srow;
    if (reused && second.firstId != null) {
      srow = await c.orderRow(second.firstId!);
    }
    final stillBound = srow?['product_offer_id']?.toString() == oidOff;
    c.note('A6.reuse', '2.ª order mesma oferta', {
      'first': firstId,
      'second': second.brief,
      'srow': srow,
    }, lens: 'DI2', well: 'DI-A');
    if (reused && stillBound) {
      c.hold(
        id: 'P1-A6',
        lens: 'DI2',
        severity: 'P1',
        title: 'Oferta aceite reutilizada na 2.ª order',
        actor: 'buyer JWT',
        pre: '1.ª order activa com product_offer_id',
        repro: 'POST 2.ª order mesmo offer_id',
        expected: 'offer_already_consumed',
        obtained: srow,
      );
      c.probe(
        id: 'A6',
        poco: 'DI-A',
        payload: '2.ª order mesmo product_offer_id aceite',
        http: second,
        bd: srow,
        verdict: 'HOLD',
        lens: 'DI2',
      );
    } else {
      c.block('A6', 'DI2', 'one-shot: 2.ª recusada ou sem bind', second.brief);
      c.probe(
        id: 'A6',
        poco: 'DI-A',
        payload: '2.ª order mesmo product_offer_id aceite',
        http: second,
        bd: reused ? 'offer_id=${srow?['product_offer_id']}' : 'recusado',
        verdict: 'FAIL',
        lens: 'DI2',
      );
    }
  }
}

Future<void> diBBundles(Rtdi c) async {
  // B1 — multi-SKU total_eur hostil vs linhas
  final p0 = await sku(c, tag: 'b1-0', price: 10, qty: 2);
  final p1 = await sku(c, tag: 'b1-1', price: 12, qty: 2);
  if (p0 == null || p1 == null) {
    c.skip('B1', 'DI3', 'sem SKUs', null);
    return;
  }
  final bun = await c.insertBundle(
    productIds: [p0, p1],
    totalEur: 0.01,
    discountPct: 99,
    subtotalEur: 22,
  );
  final bid = bun.firstId;
  Map<String, dynamic>? brow = bid == null ? null : await c.bundleRow(bid);
  HttpHit acc = HttpHit(0, 'no', {});
  HttpHit ck = HttpHit(0, 'no', {});
  String? o0;
  String? o1;
  if (bid != null) {
    acc = await c.rest(
      'PATCH',
      'product_bundles?id=eq.$bid',
      jwt: c.sellerJwt,
      body: {'status': 'accepted', 'total_eur': 0.01, 'discount_pct': 99},
    );
    brow = await c.bundleRow(bid);
    o0 = await c.insertOrder(
      productId: p0,
      price: 10,
      bundleId: bid,
      jwt: c.buyerJwt,
    );
    o1 = await c.insertOrder(
      productId: p1,
      price: 12,
      bundleId: bid,
      jwt: c.buyerJwt,
    );
    if (o0 != null && o1 != null) {
      ck = await c.checkoutBag(
        lines: bagLines([(oid: o0, pid: p0), (oid: o1, pid: p1)]),
        amount: 1,
      );
      c.trackSession(ck);
    }
  }
  final totalBd = numOf(brow?['total_eur']);
  final disc = numOf(brow?['discount_pct']);
  // catálogo 22€; cap 50% → 11€ mínimo honesto; underpay se Session < 400¢
  c.note('B1.bundle', 'total_eur=0.01 hostil', {
    'ins': bun.brief,
    'acc': acc.brief,
    'row': brow,
    'ck': ck.brief,
    'amt': ck.amountTotal,
  }, lens: 'DI3', well: 'DI-B');
  final forgedBd = totalBd != null && totalBd < 1;
  final sessionCheap = underpay(ck, 400);
  if (forgedBd || sessionCheap) {
    c.hold(
      id: 'P0-B1',
      lens: 'DI3',
      severity: 'P0',
      title: 'Bundle total_eur hostil no ledger ou na Session',
      actor: 'buyer JWT',
      pre: 'SKUs 10€+12€; INSERT total_eur=0.01 discount_pct=99',
      repro: 'POST product_bundles; PATCH accepted; bag CPI',
      expected: 'subtotal catálogo; cap 50%; Session ≥11€',
      obtained: {'row': brow, 'amt': ck.amountTotal},
    );
    c.probe(
      id: 'B1',
      poco: 'DI-B',
      payload: 'bundle multi-SKU total_eur=0.01 vs linhas 10+12',
      http: {'ins': bun.brief, 'acc': acc.brief, 'ck': ck.brief},
      bd: 'total=$totalBd disc=$disc amt=${ck.amountTotal}',
      verdict: 'HOLD',
      lens: 'DI3',
    );
  } else {
    c.block('B1', 'DI3', 'total reescrito; Session não underpay', {
      'total': totalBd,
      'disc': disc,
      'amt': ck.amountTotal,
    });
    c.probe(
      id: 'B1',
      poco: 'DI-B',
      payload: 'bundle multi-SKU total_eur=0.01 vs linhas 10+12',
      http: {'ins': bun.brief, 'ck': ck.brief},
      bd: 'total=$totalBd disc=$disc amt=${ck.amountTotal}',
      verdict: ck.ok ? 'PASS' : 'FAIL',
      lens: 'DI3',
    );
  }

  // B2 — accept ∥ stock 0 numa linha
  final q0 = await sku(c, tag: 'b2-0', price: 10, qty: 2);
  final q1 = await sku(c, tag: 'b2-1', price: 12, qty: 2);
  if (q0 != null && q1 != null) {
    final bun2 = await c.insertBundle(
      productIds: [q0, q1],
      totalEur: 22,
      discountPct: 0,
      subtotalEur: 22,
    );
    final bid2 = bun2.firstId;
    HttpHit acc2 = HttpHit(0, 'no', {});
    HttpHit ck2 = HttpHit(0, 'no', {});
    Map<String, dynamic>? prow;
    if (bid2 != null) {
      await c.rest(
        'PATCH',
        'products?id=eq.$q1',
        service: true,
        body: {'quantity': 0},
      );
      prow = await c.productRow(q1);
      acc2 = await c.rest(
        'PATCH',
        'product_bundles?id=eq.$bid2',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
      final oA = await c.insertOrder(
        productId: q0,
        price: 10,
        bundleId: bid2,
        jwt: c.buyerJwt,
      );
      final oB = await c.insertOrder(
        productId: q1,
        price: 12,
        bundleId: bid2,
        jwt: c.buyerJwt,
      );
      if (oA != null && oB != null) {
        ck2 = await c.checkoutBag(
          lines: bagLines([(oid: oA, pid: q0), (oid: oB, pid: q1)]),
          amount: 1,
        );
        c.trackSession(ck2);
      }
    }
    final accOk = acc2.ok;
    final paidGhost = ck2.ok && ck2.sessionId != null;
    c.note('B2.stock0', 'accept com qty=0', {
      'prow': prow,
      'acc': acc2.brief,
      'ck': ck2.brief,
    }, lens: 'DI4', well: 'DI-B');
    if (paidGhost) {
      c.hold(
        id: 'P0-B2',
        lens: 'DI4',
        severity: 'P0',
        title: 'Bundle aceite com linha stock 0 gerou Session',
        actor: 'buyer JWT',
        pre: 'products.quantity=0 numa linha do conjunto',
        repro: 'PATCH accepted; bag CPI',
        expected: 'accept ou CPI bloqueado',
        obtained: ck2.brief,
      );
      c.probe(
        id: 'B2',
        poco: 'DI-B',
        payload: 'bundle accept com stock 0 numa linha',
        http: {'acc': acc2.brief, 'ck': ck2.brief},
        bd: 'qty=${prow?['quantity']} amt=${ck2.amountTotal}',
        verdict: 'HOLD',
        lens: 'DI4',
      );
    } else {
      c.block('B2', 'DI4', 'stock 0: accept=$accOk CPI bloqueado/sem cs', {
        'acc': acc2.status,
        'ck': ck2.status,
        'qty': prow?['quantity'],
      });
      c.probe(
        id: 'B2',
        poco: 'DI-B',
        payload: 'bundle accept com stock 0 numa linha',
        http: {'acc': acc2.brief, 'ck': ck2.brief},
        bd: 'qty=${prow?['quantity']}',
        verdict: 'FAIL',
        lens: 'DI4',
      );
    }
  }

  // B3 — 2.ª proposta / mix de bundles
  final r0 = await sku(c, tag: 'b3-0', price: 10, qty: 3);
  final r1 = await sku(c, tag: 'b3-1', price: 12, qty: 3);
  final r2 = await sku(c, tag: 'b3-2', price: 14, qty: 3);
  if (r0 != null && r1 != null && r2 != null) {
    final bunA = await c.insertBundle(
      productIds: [r0, r1],
      totalEur: 22,
      discountPct: 0,
    );
    final bunB = await c.insertBundle(
      productIds: [r1, r2],
      totalEur: 26,
      discountPct: 0,
    );
    final idA = bunA.firstId;
    final idB = bunB.firstId;
    HttpHit accA = HttpHit(0, 'no', {});
    HttpHit accB = HttpHit(0, 'no', {});
    HttpHit mix = HttpHit(0, 'no', {});
    if (idA != null) {
      accA = await c.rest(
        'PATCH',
        'product_bundles?id=eq.$idA',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
    }
    if (idB != null) {
      accB = await c.rest(
        'PATCH',
        'product_bundles?id=eq.$idB',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
    }
    final oX = await c.insertOrder(
      productId: r0,
      price: 10,
      bundleId: idA,
      jwt: c.buyerJwt,
    );
    final oY = await c.insertOrder(
      productId: r1,
      price: 12,
      bundleId: idB,
      jwt: c.buyerJwt,
    );
    if (oX != null && oY != null) {
      mix = await c.checkoutBag(
        lines: bagLines([(oid: oX, pid: r0), (oid: oY, pid: r1)]),
        amount: 1,
      );
      c.trackSession(mix);
    }
    final mixedOk = mix.ok && mix.sessionId != null;
    c.note('B3.supersede', '2 bundles + mix bag', {
      'a': bunA.brief,
      'b': bunB.brief,
      'accA': accA.brief,
      'accB': accB.brief,
      'mix': mix.brief,
    }, lens: 'DI3', well: 'DI-B');
    if (mixedOk) {
      c.hold(
        id: 'P1-B3',
        lens: 'DI3',
        severity: 'P1',
        title: 'Saco misturou dois contratos de conjunto',
        actor: 'buyer JWT',
        pre: 'bundle A aceite (r0,r1) + bundle B aceite (r1,r2)',
        repro: 'bag CPI linhas de A e B',
        expected: 'bag cannot mix multiple bundle contracts',
        obtained: mix.brief,
      );
      c.probe(
        id: 'B3',
        poco: 'DI-B',
        payload: '2.ª proposta + mix de 2 bundle_id no saco',
        http: mix,
        bd: mix.amountTotal,
        verdict: 'HOLD',
        lens: 'DI3',
      );
    } else {
      c.block('B3', 'DI3', 'mix 2 bundles recusado', mix.brief);
      c.probe(
        id: 'B3',
        poco: 'DI-B',
        payload: '2.ª proposta + mix de 2 bundle_id no saco',
        http: {'insB': bunB.brief, 'mix': mix.brief},
        bd: 'recusado',
        verdict: 'FAIL',
        lens: 'DI3',
      );
    }
  }

  // B4 — underpay body vs bundle aceite honesto
  final s0 = await sku(c, tag: 'b4-0', price: 10, qty: 2);
  final s1 = await sku(c, tag: 'b4-1', price: 12, qty: 2);
  if (s0 != null && s1 != null) {
    final bun4 = await c.insertBundle(
      productIds: [s0, s1],
      totalEur: 22,
      discountPct: 0,
      jwt: c.sellerJwt,
      subtotalEur: 22,
    );
    final bid4 = bun4.firstId;
    HttpHit ck4 = HttpHit(0, 'no', {});
    Map<String, dynamic>? brow4;
    if (bid4 != null) {
      await c.rest(
        'PATCH',
        'product_bundles?id=eq.$bid4',
        jwt: c.sellerJwt,
        body: {'status': 'accepted', 'discount_pct': 0},
      );
      brow4 = await c.bundleRow(bid4);
      final oA = await c.insertOrder(
        productId: s0,
        price: 10,
        bundleId: bid4,
        jwt: c.buyerJwt,
      );
      final oB = await c.insertOrder(
        productId: s1,
        price: 12,
        bundleId: bid4,
        jwt: c.buyerJwt,
      );
      if (oA != null && oB != null) {
        ck4 = await c.checkoutBag(
          lines: bagLines([(oid: oA, pid: s0), (oid: oB, pid: s1)]),
          amount: 1,
        );
        c.trackSession(ck4);
      }
    }
    // 22€ + protecção ≈ 2375¢; floor 1500¢
    c.note('B4.underpay', 'CPI amount=1 vs bundle aceite', {
      'row': brow4,
      'ck': ck4.brief,
      'amt': ck4.amountTotal,
    }, lens: 'DI3', well: 'DI-B');
    if (underpay(ck4, 1500)) {
      c.hold(
        id: 'P0-B4',
        lens: 'DI3',
        severity: 'P0',
        title: 'CPI amount=1 underpay do conjunto aceite',
        actor: 'buyer JWT',
        pre: 'bundle accepted total catálogo 22€',
        repro: 'bag CPI amount=1',
        expected: 'amount_total ≈ 22€+taxas',
        obtained: ck4.brief,
      );
      c.probe(
        id: 'B4',
        poco: 'DI-B',
        payload: 'pagamento bundle aceite + CPI amount=1',
        http: ck4,
        bd: 'total=${brow4?['total_eur']} amt=${ck4.amountTotal}',
        verdict: 'HOLD',
        lens: 'DI3',
      );
    } else {
      c.block('B4', 'DI3', 'body 1€ não underpay do conjunto', {
        'amt': ck4.amountTotal,
        'total': brow4?['total_eur'],
      });
      c.probe(
        id: 'B4',
        poco: 'DI-B',
        payload: 'pagamento bundle aceite + CPI amount=1',
        http: ck4,
        bd: 'total=${brow4?['total_eur']} amt=${ck4.amountTotal}',
        verdict: ck4.ok ? 'PASS' : 'FAIL',
        lens: 'DI3',
      );
    }
  }

  // B5 — saco incompleto (1 de 2 SKUs) com bundle aceite
  final t0 = await sku(c, tag: 'b5-0', price: 10, qty: 2);
  final t1 = await sku(c, tag: 'b5-1', price: 12, qty: 2);
  if (t0 != null && t1 != null) {
    final bun5 = await c.insertBundle(productIds: [t0, t1], totalEur: 22);
    final bid5 = bun5.firstId;
    HttpHit ck5 = HttpHit(0, 'no', {});
    if (bid5 != null) {
      await c.rest(
        'PATCH',
        'product_bundles?id=eq.$bid5',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
      final oOnly = await c.insertOrder(
        productId: t0,
        price: 10,
        bundleId: bid5,
        jwt: c.buyerJwt,
      );
      if (oOnly != null) {
        ck5 = await c.checkoutBag(
          lines: bagLines([(oid: oOnly, pid: t0)]),
          amount: 1,
        );
        c.trackSession(ck5);
      }
    }
    final partialOk = ck5.ok && ck5.sessionId != null;
    c.note('B5.incomplete', 'bag 1/2 SKUs', ck5.brief, lens: 'DI3', well: 'DI-B');
    if (partialOk) {
      c.hold(
        id: 'P1-B5',
        lens: 'DI3',
        severity: 'P1',
        title: 'Saco incompleto pagou conjunto aceite',
        actor: 'buyer JWT',
        pre: 'bundle accepted 2 SKUs; bag só 1',
        repro: 'bag CPI 1 linha',
        expected: 'bag must include all items',
        obtained: ck5.brief,
      );
      c.probe(
        id: 'B5',
        poco: 'DI-B',
        payload: 'bundle aceite + saco só 1 de 2 SKUs',
        http: ck5,
        bd: ck5.amountTotal,
        verdict: 'HOLD',
        lens: 'DI3',
      );
    } else {
      c.block('B5', 'DI3', 'saco incompleto recusado', ck5.brief);
      c.probe(
        id: 'B5',
        poco: 'DI-B',
        payload: 'bundle aceite + saco só 1 de 2 SKUs',
        http: ck5,
        bd: 'recusado',
        verdict: 'FAIL',
        lens: 'DI3',
      );
    }
  }
}

Future<void> diCChat(Rtdi c, Map<String, num> wal0) async {
  final paid = await c.payToPago(lens: 'DI5');
  final skuC = await sku(c, tag: 'c-pending', price: 12, qty: 2);
  if (paid == null || skuC == null) {
    c.skip('C*', 'DI5', 'fixture chat/pago em falta', paid?.oid);
    return;
  }
  final chatPaid = await c.ensureChat(paid.pid);
  final chatPend = await c.ensureChat(skuC);
  final pendOid = await c.insertOrder(
    productId: skuC,
    jwt: c.buyerJwt,
    price: 12,
    payment: 'MB WAY',
  );
  if (chatPaid == null || chatPend == null || pendOid == null) {
    c.skip('C*', 'DI5', 'chat/order pendente em falta', null);
    return;
  }

  Future<HttpHit> card(
    String chatId,
    Map<String, Object?> payload, {
    String? jwt,
  }) async {
    final h = await c.postMsg(
      chatId: chatId,
      text: jsonCard(payload),
      jwt: jwt ?? c.buyerJwt,
    );
    if (h.firstId != null) c.createdMsgIds.add(h.firstId!);
    return h;
  }

  // C1 — canónico OK
  final c1 = await card(chatPaid, {
    'kind': 'reservation_payment_submitted',
    'order_id': paid.oid,
    'notes': 'ok',
  });
  final st1 = '${(await c.orderRow(paid.oid))?['status']}';
  c.note('C1.canonical', 'notes=ok', c1.brief, lens: 'DI5', well: 'DI-C');
  if (c1.ok) {
    c.block('C1', 'DI5', 'card canónico persistiu; status=$st1', c1.brief);
    c.probe(
      id: 'C1',
      poco: 'DI-C',
      payload: 'reservation_payment_submitted notes=ok (pago Stripe)',
      http: c1,
      bd: 'orders.status=$st1',
      verdict: 'PASS',
      lens: 'DI5',
    );
  } else {
    c.hold(
      id: 'P2-C1',
      lens: 'DI5',
      severity: 'P2',
      title: 'Card canónico notes=ok recusado',
      actor: 'buyer JWT',
      pre: 'encomenda Stripe pago',
      repro: 'POST reservation_payment_submitted notes=ok',
      expected: '201',
      obtained: c1.brief,
    );
    c.probe(
      id: 'C1',
      poco: 'DI-C',
      payload: 'reservation_payment_submitted notes=ok',
      http: c1,
      bd: 'orders.status=$st1',
      verdict: 'HOLD',
      lens: 'DI5',
    );
  }

  // C2 — card + PATCH pago sem Stripe
  final c2card = await card(chatPend, {
    'kind': 'reservation_payment_submitted',
    'order_id': pendOid,
    'notes': 'pago',
  });
  final before = '${(await c.orderRow(pendOid))?['status']}';
  final patch = await c.patchOrder(
    pendOid,
    {'status': 'pago'},
    jwt: c.buyerJwt,
  );
  final after = '${(await c.orderRow(pendOid))?['status']}';
  final walS = await c.walletBal(c.sellerId);
  final moved = after == 'pago' && before != 'pago';
  c.note('C2.fsm', 'card+PATCH pago', {
    'card': c2card.brief,
    'patch': patch.brief,
    'before': before,
    'after': after,
    'wal': walS,
  }, lens: 'DI7', well: 'DI-C');
  if (moved) {
    c.hold(
      id: 'P0-C2',
      lens: 'DI7',
      severity: 'P0',
      title: 'Buyer marcou pago sem Stripe (card+PATCH)',
      actor: 'buyer JWT',
      pre: 'reserva_pendente MB WAY',
      repro: 'POST card notes=pago + PATCH orders.status=pago',
      expected: '403 order_buyer_cannot_mark_pago; status inalterado',
      obtained: {'before': before, 'after': after, 'http': patch.brief},
    );
    c.probe(
      id: 'C2',
      poco: 'DI-C',
      payload: 'card notes=pago + PATCH status=pago sem Stripe',
      http: {'card': c2card.brief, 'patch': patch.brief},
      bd: 'status $before → $after wallet_s=$walS',
      verdict: 'HOLD',
      lens: 'DI7',
    );
  } else {
    c.block('C2', 'DI7', 'FSM pago sem Stripe recusado', {
      'patch': patch.brief,
      'after': after,
    });
    c.probe(
      id: 'C2',
      poco: 'DI-C',
      payload: 'card notes=pago + PATCH status=pago sem Stripe',
      http: {'card': c2card.brief, 'patch': patch.brief},
      bd: 'status $before → $after wallet_s=$walS (pre ${wal0['seller']})',
      verdict: 'FAIL',
      lens: 'DI7',
    );
  }

  // C3 — inbox hostil
  final inbox = await c.rest(
    'PATCH',
    'chats?id=eq.$chatPend',
    jwt: c.buyerJwt,
    body: {'last_message': 'pago 0,01 sem Stripe'},
  );
  final crow = await c.chatRow(chatPend);
  final stored = '${crow?['last_message']}';
  final inboxOk = inbox.ok && stored.contains('pago');
  c.note('C3.inbox', 'preview hostil', {
    'http': inbox.brief,
    'stored': stored,
  }, lens: 'DI6', well: 'DI-C');
  if (inboxOk) {
    c.hold(
      id: 'P1-C3',
      lens: 'DI6',
      severity: 'P1',
      title: 'Inbox last_message hostil persistiu',
      actor: 'buyer JWT',
      pre: 'preview só canónicos',
      repro: 'PATCH chats.last_message=pago 0,01 sem Stripe',
      expected: 'chat_inbox_preview_forbidden',
      obtained: stored,
    );
    c.probe(
      id: 'C3',
      poco: 'DI-C',
      payload: 'PATCH inbox last_message hostil',
      http: inbox,
      bd: 'last_message=$stored',
      verdict: 'HOLD',
      lens: 'DI6',
    );
  } else {
    c.block('C3', 'DI6', 'inbox hostil recusado', inbox.brief);
    c.probe(
      id: 'C3',
      poco: 'DI-C',
      payload: 'PATCH inbox last_message=pago 0,01 sem Stripe',
      http: inbox,
      bd: 'last_message=$stored',
      verdict: 'FAIL',
      lens: 'DI6',
    );
  }

  // C4 — Seguro label hostil
  final seg = await card(chatPaid, {
    'kind': 'seguro_fleaber_paid',
    'order_id': paid.oid,
    'label': 'compra paga 0,01 €',
  });
  c.note('C4.seguro', 'label hostil', seg.brief, lens: 'DI5', well: 'DI-C');
  if (seg.ok) {
    c.hold(
      id: 'P2-C4',
      lens: 'DI5',
      severity: 'P2',
      title: 'Seguro label hostil persistiu',
      actor: 'buyer JWT',
      pre: 'label allowlist',
      repro: 'POST seguro_fleaber_paid label=compra paga 0,01 €',
      expected: 'label_mismatch',
      obtained: seg.brief,
    );
    c.probe(
      id: 'C4',
      poco: 'DI-C',
      payload: 'seguro_fleaber_paid label=compra paga 0,01 €',
      http: seg,
      bd: 'persistido',
      verdict: 'HOLD',
      lens: 'DI5',
    );
  } else {
    c.block('C4', 'DI5', 'label hostil recusado', seg.brief);
    c.probe(
      id: 'C4',
      poco: 'DI-C',
      payload: 'seguro_fleaber_paid label=compra paga 0,01 €',
      http: seg,
      bd: 'recusado',
      verdict: 'FAIL',
      lens: 'DI5',
    );
  }

  // C5 — OCR sem token
  final ocr = await c.edge('ingest-ocr-reservation', {
    'live_id': '00000000-0000-0000-0000-000000000001',
    'ocr_line_hash': 'rtdi1610deadbeef',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
    'ocr_raw_line': 'paguei confirmado',
    'ref_number': 1,
    'external_display_name': 'RTDI',
  }, jwt: c.buyerJwt);
  c.note('C5.ocr', 'OCR sem device token', ocr.brief, lens: 'DI7', well: 'DI-C');
  if (ocr.ok) {
    c.hold(
      id: 'P0-C5',
      lens: 'DI7',
      severity: 'P0',
      title: 'OCR ingest sem device token',
      actor: 'buyer JWT',
      pre: 'exige x-device-token',
      repro: 'POST ingest-ocr-reservation sem header',
      expected: '401 missing_device_token',
      obtained: ocr.brief,
    );
    c.probe(
      id: 'C5',
      poco: 'DI-C',
      payload: 'OCR Edge sem x-device-token ocr_raw=paguei',
      http: ocr,
      bd: 'ingest ok',
      verdict: 'HOLD',
      lens: 'DI7',
    );
  } else {
    c.block('C5', 'DI7', 'OCR sem token recusado', ocr.brief);
    c.probe(
      id: 'C5',
      poco: 'DI-C',
      payload: 'OCR Edge sem x-device-token ocr_raw=paguei',
      http: ocr,
      bd: 'sem ingest',
      verdict: 'FAIL',
      lens: 'DI7',
    );
  }

  // C6 — price_offer amount mismatch (card ≠ ledger)
  final pOff = await sku(c, tag: 'c6-offer', price: 18, qty: 2);
  if (pOff != null) {
    final chatO = await c.ensureChat(pOff);
    final off = await c.insertOffer(productId: pOff, amount: 8, listPrice: 18);
    final oidOff = off.firstId;
    HttpHit cardOff = HttpHit(0, 'no', {});
    if (chatO != null && oidOff != null) {
      cardOff = await card(chatO, {
        'kind': 'price_offer',
        'offer_id': oidOff,
        'amount': 0.01,
      });
    }
    c.note('C6.offer-card', 'price_offer amount=0.01 vs BD 8', cardOff.brief,
        lens: 'DI5', well: 'DI-C');
    if (cardOff.ok) {
      c.hold(
        id: 'P1-C6',
        lens: 'DI5',
        severity: 'P1',
        title: 'Card price_offer amount hostil ≠ ledger',
        actor: 'buyer JWT',
        pre: 'product_offers.amount=8 pending',
        repro: 'POST price_offer amount=0.01',
        expected: 'chat_system_card_offer_amount_mismatch',
        obtained: cardOff.brief,
      );
      c.probe(
        id: 'C6',
        poco: 'DI-C',
        payload: 'price_offer card amount=0.01 vs BD 8€',
        http: cardOff,
        bd: 'offer amount=8',
        verdict: 'HOLD',
        lens: 'DI5',
      );
    } else {
      c.block('C6', 'DI5', 'card offer amount mismatch recusado', cardOff.brief);
      c.probe(
        id: 'C6',
        poco: 'DI-C',
        payload: 'price_offer card amount=0.01 vs BD 8€',
        http: cardOff,
        bd: 'recusado',
        verdict: 'FAIL',
        lens: 'DI5',
      );
    }
  }

  // C7 — bundle_proposal total mismatch
  final u0 = await sku(c, tag: 'c7-0', price: 10, qty: 2);
  final u1 = await sku(c, tag: 'c7-1', price: 12, qty: 2);
  if (u0 != null && u1 != null) {
    final bun = await c.insertBundle(productIds: [u0, u1], totalEur: 22);
    final bid = bun.firstId;
    final chatB = await c.ensureChat(u0);
    HttpHit cardB = HttpHit(0, 'no', {});
    final brow = bid == null ? null : await c.bundleRow(bid);
    if (chatB != null && bid != null) {
      cardB = await card(chatB, {
        'kind': 'bundle_proposal',
        'bundle_id': bid,
        'total_eur': 0.01,
      });
    }
    c.note('C7.bundle-card', 'bundle_proposal total=0.01 vs BD', {
      'row': brow,
      'card': cardB.brief,
    }, lens: 'DI5', well: 'DI-C');
    if (cardB.ok) {
      c.hold(
        id: 'P1-C7',
        lens: 'DI5',
        severity: 'P1',
        title: 'Card bundle_proposal total hostil ≠ ledger',
        actor: 'buyer JWT',
        pre: 'product_bundles.total_eur catálogo',
        repro: 'POST bundle_proposal total_eur=0.01',
        expected: 'chat_system_card_bundle_total_mismatch',
        obtained: cardB.brief,
      );
      c.probe(
        id: 'C7',
        poco: 'DI-C',
        payload: 'bundle_proposal card total_eur=0.01 vs BD',
        http: cardB,
        bd: 'total=${brow?['total_eur']}',
        verdict: 'HOLD',
        lens: 'DI5',
      );
    } else {
      c.block('C7', 'DI5', 'card bundle total mismatch recusado', cardB.brief);
      c.probe(
        id: 'C7',
        poco: 'DI-C',
        payload: 'bundle_proposal card total_eur=0.01 vs BD',
        http: cardB,
        bd: 'total=${brow?['total_eur']} recusado',
        verdict: 'FAIL',
        lens: 'DI5',
      );
    }
  }

  // Residual exacto ≤1 HOLD — não contar
  final residual = await card(chatPaid, {
    'kind': 'reservation_payment_submitted',
    'order_id': paid.oid,
    'notes': '12,00',
  });
  c.note('C8.residual', 'notes=12,00', residual.brief, lens: 'DI5', well: 'DI-C');
  c.probe(
    id: 'C8',
    poco: 'DI-C',
    payload: 'notes=12,00 (residual exacto CQ — não contar)',
    http: residual,
    bd: residual.ok ? 'persistido' : 'recusado',
    verdict: 'HOLD',
    lens: 'DI5',
  );
}
