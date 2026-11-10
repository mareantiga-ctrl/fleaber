/// BH pass2 — BH4 hitch/mark_sold · BH5 live_id/qty · BH6 race end∥accept · reopen
import 'dart:io';
import '_rtbh.dart';

Future<void> main() async {
  final c = Rtbh.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.ensureHelpers();

  final liveA = await c.insertLive(title: '$prefix-p2A');
  final liveB = await c.insertLive(seller: c.seller2Id, title: '$prefix-p2B');
  if (liveA == null) {
    stderr.writeln('no live');
    await c.dumpAll('pass2.json');
    exit(4);
  }
  final itemA = await c.insertLiveItem(liveId: liveA, qty: 2, title: '$prefix-p2-only');
  final ownExtra = await c.insertProduct(price: 22, qty: 1, title: '$prefix-extra');
  final alienSku = await c.insertProduct(
    price: 30,
    qty: 1,
    seller: c.seller2Id,
    title: '$prefix-alien',
  );
  final mktSku = await c.insertProduct(price: 15, qty: 1, live: true, title: '$prefix-p2-mkt');
  final itemMkt = mktSku == null
      ? null
      : await c.insertLiveItem(
          liveId: liveA,
          kind: 'marketplace_product',
          productId: mktSku,
          title: '$prefix-p2-mkt-item',
        );

  await _bh4Hitch(c, liveA, liveB, itemA, ownExtra, alienSku);
  await _bh5QtyLiveId(c, liveA, liveB, itemA, itemMkt, mktSku);
  await _bh6RaceReopen(c, liveA, itemA, itemMkt, mktSku);

  await c.endAllLives();
  await c.dumpAll('pass2.json');
  stdout.writeln(
      'DONE p2 findings=${c.findings.length} blocked=${c.blocked.length} lenses=${c.lensesHit.toList()..sort()}');
}

Future<void> _bh4Hitch(
  Rtbh c,
  String liveA,
  String? liveB,
  String? itemA,
  String? ownExtra,
  String? alienSku,
) async {
  if (itemA == null) return;

  // Hitch checkout alheio (INSERT novo item)
  if (alienSku != null) {
    final hitchIns = await c.rest('POST', 'live_items', jwt: c.sellerJwt, body: {
      'live_id': liveA,
      'item_kind': 'live_only',
      'title': '$prefix-hitch-alien',
      'quantity': 1,
      'price': 9,
      'is_active': true,
      'status': 'available',
      'checkout_product_id': alienSku,
    });
    if (hitchIns.ok) {
      final id = hitchIns.firstId;
      if (id != null) c.createdItemIds.add(id);
      c.hold(
        id: 'BH4-01',
        lens: 'BH4',
        severity: 'P1',
        title: 'INSERT live_only com checkout_product_id de outro seller',
        actor: 'seller JWT',
        pre: 'SKU seller2',
        repro: 'POST live_items checkout_product_id alien',
        expected: 'live_item_checkout_product_seller_mismatch',
        obtained: hitchIns.brief,
      );
    } else {
      c.block('BH4-01', 'BH4', 'INSERT hitch alien checkout', hitchIns);
    }

    final hitchPatch = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemA',
      jwt: c.sellerJwt,
      body: {'checkout_product_id': alienSku},
    );
    await c.expectDenied(
      id: 'BH4-02',
      lens: 'BH4',
      title: 'PATCH hitch checkout_product_id alheio',
      hit: hitchPatch,
      actor: 'seller JWT',
      pre: 'item live_only próprio',
      repro: 'PATCH checkout_product_id seller2',
      severityIfOpen: 'P1',
    );
  }

  // Hitch SKU extra próprio + mark_sold sem PI
  if (ownExtra != null) {
    final before = await c.productRow(ownExtra);
    final hitchOwn = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemA',
      jwt: c.sellerJwt,
      body: {'checkout_product_id': ownExtra},
    );
    if (hitchOwn.ok) {
      c.note('BH4-03a', 'hitch checkout próprio extra', hitchOwn, lens: 'BH4');
      final ms = await c.markSold(itemA);
      final after = await c.productRow(ownExtra);
      final unlisted = after?['is_sold'] == true || after?['list_on_marketplace'] == false;
      if (ms.rpcOk && unlisted) {
        c.hold(
          id: 'BH4-03',
          lens: 'BH4',
          severity: 'P1',
          title: 'mark_sold live_only hitch SKU extra próprio deslista sem PI',
          actor: 'seller JWT',
          pre: 'checkout_product_id=SKU extra, sem order paga do live_item',
          repro: 'PATCH checkout_product_id próprio + rpc mark_sold',
          expected: 'SKU extra continua listado / is_sold=false',
          obtained: {
            'mark': ms.brief,
            'before': before,
            'after': after,
          },
        );
      } else {
        c.block('BH4-03', 'BH4', 'hitch own extra mark_sold sem unlist', {
          'mark': ms.brief,
          'after': after,
        });
      }
      // restaurar checkout
      await c.rest(
        'PATCH',
        'live_items?id=eq.$itemA',
        service: true,
        body: {'checkout_product_id': null, 'status': 'available'},
        prefer: 'return=minimal',
      );
      await c.rest(
        'PATCH',
        'products?id=eq.$ownExtra',
        service: true,
        body: {'is_sold': false, 'list_on_marketplace': true},
        prefer: 'return=minimal',
      );
    } else {
      c.block('BH4-03', 'BH4', 'PATCH hitch own extra', hitchOwn);
    }
  }

  // Buyer / seller2 mark_sold
  final buyerMs = await c.markSold(itemA, jwt: c.buyerJwt);
  await c.expectDenied(
    id: 'BH4-04',
    lens: 'BH4',
    title: 'Buyer mark_sold item da live A',
    hit: buyerMs,
    actor: 'buyer JWT',
    pre: 'não é dono',
    repro: 'rpc mark_sold',
    severityIfOpen: 'P1',
    openIf: (h) => h.rpcOk,
  );
  if (c.seller2Jwt != null) {
    final s2ms = await c.markSold(itemA, jwt: c.seller2Jwt);
    await c.expectDenied(
      id: 'BH4-05',
      lens: 'BH4',
      title: 'Seller2 mark_sold no item da live A',
      hit: s2ms,
      actor: 'seller2 JWT',
      pre: 'live A de seller1',
      repro: 'rpc mark_sold',
      severityIfOpen: 'P1',
      openIf: (h) => h.rpcOk,
    );
  }

  // INSERT status=sold
  final insSold = await c.rest('POST', 'live_items', jwt: c.sellerJwt, body: {
    'live_id': liveA,
    'item_kind': 'live_only',
    'title': '$prefix-sold-ins',
    'quantity': 1,
    'price': 5,
    'is_active': true,
    'status': 'sold',
  });
  await c.expectDenied(
    id: 'BH4-06',
    lens: 'BH4',
    title: 'INSERT live_item status=sold (bypass RPC)',
    hit: insSold,
    actor: 'seller JWT',
    pre: 'sold só via mark_sold',
    repro: 'POST live_items status=sold',
    severityIfOpen: 'P2',
  );

  // PATCH status=sold directo
  final patchSold = await c.rest(
    'PATCH',
    'live_items?id=eq.$itemA',
    jwt: c.sellerJwt,
    body: {'status': 'sold'},
  );
  await c.expectDenied(
    id: 'BH4-07',
    lens: 'BH4',
    title: 'PATCH status=sold directo sem RPC',
    hit: patchSold,
    actor: 'seller JWT',
    pre: 'guard rpc_only',
    repro: 'PATCH live_items status=sold',
    severityIfOpen: 'P2',
  );

  // upsert marketplace com produto alheio
  if (alienSku != null) {
    final up = await c.rpc('batata_upsert_marketplace_live_item', {
      'p_seller_id': c.sellerId,
      'p_product_id': alienSku,
      'p_live_id': liveA,
    });
    await c.expectDenied(
      id: 'BH4-08',
      lens: 'BH4',
      title: 'upsert marketplace live_item com SKU seller2',
      hit: up,
      actor: 'seller JWT',
      pre: 'produto alheio',
      repro: 'rpc batata_upsert_marketplace_live_item',
      severityIfOpen: 'P1',
      openIf: (h) => h.ok && h.firstId != null,
    );
  }
}

Future<void> _bh5QtyLiveId(
  Rtbh c,
  String liveA,
  String? liveB,
  String? itemA,
  String? itemMkt,
  String? mktSku,
) async {
  if (itemA == null) return;

  final qtyOwner = await c.rest(
    'PATCH',
    'live_items?id=eq.$itemA',
    jwt: c.sellerJwt,
    body: {'quantity': 40},
  );
  if (qtyOwner.ok) {
    final row = await c.itemRow(itemA);
    final q = numOf(row?['quantity'])?.round();
    if (q != null && q >= 40) {
      c.hold(
        id: 'BH5-01',
        lens: 'BH5',
        severity: 'P2',
        title: 'Dono infla qty live_only 2→40 mid-live sem PI',
        actor: 'seller JWT',
        pre: 'item_kind=live_only qty=2',
        repro: 'PATCH live_items quantity=40',
        expected: 'live_item_qty_increase_not_allowed',
        obtained: {'patch': qtyOwner.brief, 'row': row},
      );
    } else {
      c.block('BH5-01', 'BH5', 'qty increase capped', qtyOwner);
    }
    await c.rest(
      'PATCH',
      'live_items?id=eq.$itemA',
      service: true,
      body: {'quantity': 2},
      prefer: 'return=minimal',
    );
  } else {
    c.block('BH5-01', 'BH5', 'dono qty increase live_only', qtyOwner);
  }

  if (liveB != null) {
    final move = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemA',
      jwt: c.sellerJwt,
      body: {'live_id': liveB},
    );
    await c.expectDenied(
      id: 'BH5-02',
      lens: 'BH5',
      title: 'Mover live_item da live A para live B (seller2)',
      hit: move,
      actor: 'seller JWT',
      pre: 'item da live A',
      repro: 'PATCH live_id=liveB',
      severityIfOpen: 'P1',
    );
  }

  // qty reserva > stock
  final over = await c.buyerReserve(itemA, qty: 99);
  c.trackRes(over);
  if (over.ok) {
    final q = numOf(over.map?['requested_qty'])?.round();
    if (q != null && q > 2) {
      c.hold(
        id: 'BH5-03',
        lens: 'BH5',
        severity: 'P1',
        title: 'Buyer reserva qty 99 > stock 2',
        actor: 'buyer JWT',
        pre: 'live_only qty=2',
        repro: 'POST reservation requested_qty=99',
        expected: 'qty capped ≤2 ou 4xx',
        obtained: over.brief,
      );
    } else {
      c.block('BH5-03', 'BH5', 'qty cap $q', over);
    }
  } else {
    c.block('BH5-03', 'BH5', 'over-qty reserve', over);
  }

  // mismatch live_id no INSERT
  if (liveB != null) {
    final mismatch = await c.rest('POST', 'live_reservation_requests', jwt: c.buyerJwt, body: {
      'live_item_id': itemA,
      'live_id': liveB,
      'requested_qty': 1,
      'source': 'fleaber_live',
      'status': 'pending',
    });
    await c.expectDenied(
      id: 'BH5-04',
      lens: 'BH5',
      title: 'Reserva item A com live_id da live B',
      hit: mismatch,
      actor: 'buyer JWT',
      pre: 'item.live_id=A, body live_id=B',
      repro: 'POST reservation live_item_id=A live_id=B',
      severityIfOpen: 'P1',
    );
  }

  if (c.helperMarkJwt != null) {
    final hQty = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemA',
      jwt: c.helperMarkJwt,
      body: {'quantity': 9},
    );
    if (hQty.ok) {
      c.hold(
        id: 'BH5-05',
        lens: 'BH5',
        severity: 'P2',
        title: 'Helper can_mark_items_sold infla qty live_only',
        actor: 'helper mark',
        pre: 'AHAM: live_only qty increase blocked mesmo com can_mark',
        repro: 'PATCH quantity=9 JWT helper mark',
        expected: 'live_item_qty_increase_not_allowed',
        obtained: hQty.brief,
      );
      await c.rest(
        'PATCH',
        'live_items?id=eq.$itemA',
        service: true,
        body: {'quantity': 2},
        prefer: 'return=minimal',
      );
    } else {
      c.block('BH5-05', 'BH5', 'helper mark qty live_only', hQty);
    }
  }
}

Future<void> _bh6RaceReopen(
  Rtbh c,
  String liveA,
  String? itemA,
  String? itemMkt,
  String? mktSku,
) async {
  if (itemA == null) return;

  // Pending, end, accept sem reopen
  final r1 = await c.buyerReserve(itemA);
  c.trackRes(r1);
  final rid = r1.firstId;
  await c.endLive(liveA);
  if (rid != null) {
    final accEnded = await c.patchRes(rid, {'status': 'accepted'});
    await c.expectDenied(
      id: 'BH6-01',
      lens: 'BH6',
      title: 'Accept reserva após live ended (sem reopen)',
      hit: accEnded,
      actor: 'seller JWT',
      pre: 'pending criado no ar; live agora ended',
      repro: 'PATCH accepted após status=ended',
      severityIfOpen: 'P1',
    );
    final newRes = await c.buyerReserve(itemA);
    await c.expectDenied(
      id: 'BH6-02',
      lens: 'BH6',
      title: 'INSERT reserva em live ended',
      hit: newRes,
      actor: 'buyer JWT',
      pre: 'live ended',
      repro: 'POST live_reservation_requests',
      severityIfOpen: 'P1',
    );
  }

  // Reopen + accept (produto marketplace)
  final re = await c.reopenLive(liveA);
  c.note('BH6-03a', 'seller reopen ended→live', re, lens: 'BH6');
  if (re.ok) {
    final live = await c.liveRow(liveA);
    final broadcasting = live?['status'] == 'live' && live?['is_active'] == true;
    if (!broadcasting) {
      c.block('BH6-03', 'BH6', 'reopen não voltou a broadcasting', live);
    } else if (itemMkt != null && mktSku != null) {
      final qtyBefore = numOf((await c.productRow(mktSku))?['quantity']);
      final rp = await c.buyerReserve(itemMkt);
      c.trackRes(rp);
      final rpid = rp.firstId;
      if (rpid != null) {
        final acc = await c.patchRes(rpid, {'status': 'accepted'});
        final qtyAfter = numOf((await c.productRow(mktSku))?['quantity']);
        final res = await c.resRow(rpid);
        if (acc.ok && res?['status'] == 'accepted') {
          c.hold(
            id: 'BH6-03',
            lens: 'BH6',
            severity: 'P3',
            title: 'Reopen live ended + accept reserva de produto (fila revivida)',
            actor: 'seller JWT',
            pre: 'seller PATCH ended→live is_active=true, depois accept marketplace item',
            repro: 'PATCH lives live+active; PATCH reservation accepted',
            expected: 'ended irreversível OU fila expirada',
            obtained: {
              'accept': acc.brief,
              'res': res,
              'qty_before': qtyBefore,
              'qty_after': qtyAfter,
            },
          );
        } else {
          c.block('BH6-03', 'BH6', 'reopen+accept produto', {
            'accept': acc.brief,
            'res': res,
          });
        }
      }
    } else if (rid != null) {
      final acc2 = await c.patchRes(rid, {'status': 'accepted'});
      if (acc2.ok) {
        c.hold(
          id: 'BH6-03',
          lens: 'BH6',
          severity: 'P3',
          title: 'Reopen ended + accept pending antigo live_only',
          actor: 'seller JWT',
          pre: 'pending criado antes do end',
          repro: 'reopen + PATCH accepted',
          expected: 'pending expirado / live_ended',
          obtained: acc2.brief,
        );
      } else {
        c.block('BH6-03', 'BH6', 'reopen+accept pending antigo', acc2);
      }
    }
  } else {
    c.block('BH6-03', 'BH6', 'seller não reabre ended', re);
  }

  // Seller2 reopen live A
  if (c.seller2Jwt != null) {
    await c.endLive(liveA, service: true);
    final s2re = await c.reopenLive(liveA, jwt: c.seller2Jwt);
    await c.expectDenied(
      id: 'BH6-04',
      lens: 'BH7',
      title: 'Seller2 reabre live A',
      hit: s2re,
      actor: 'seller2 JWT',
      pre: 'live A de seller1 ended',
      repro: 'PATCH lives status=live is_active=true',
      severityIfOpen: 'P1',
    );
    await c.reopenLive(liveA);
  }

  // Race end ∥ accept
  final raceItem = await c.insertLiveItem(liveId: liveA, qty: 1, title: '$prefix-race');
  if (raceItem != null) {
    final rr = await c.buyerReserve(raceItem);
    c.trackRes(rr);
    final rrid = rr.firstId;
    if (rrid != null) {
      final results = await Future.wait([
        c.endLive(liveA),
        c.patchRes(rrid, {'status': 'accepted'}),
        c.patchRes(rrid, {'status': 'accepted'}),
        c.endLive(liveA),
      ]);
      final res = await c.resRow(rrid);
      final live = await c.liveRow(liveA);
      final acceptedOnEnded = res?['status'] == 'accepted' &&
          live?['status'] == 'ended' &&
          live?['is_active'] == false;
      c.note('BH6-05', 'race end∥accept', {
        'hits': results.map((h) => h.brief).toList(),
        'res': res,
        'live': {'status': live?['status'], 'active': live?['is_active']},
      }, lens: 'BH6');
      if (acceptedOnEnded) {
        c.hold(
          id: 'BH6-05',
          lens: 'BH6',
          severity: 'P1',
          title: 'Race end∥accept: reserva accepted em live já ended',
          actor: 'seller JWT paralelo',
          pre: 'pending qty=1; PATCH ended ∥ PATCH accepted',
          repro: 'Future.wait endLive + accept ×2',
          expected: 'accepted só se broadcasting OU ambos fail-closed',
          obtained: {'res': res, 'live': live, 'hits': results.map((e) => e.status).toList()},
        );
      } else {
        c.block('BH6-05', 'BH6', 'race end∥accept sem accepted-on-ended', {
          'res': res?['status'],
          'live': live?['status'],
        });
      }
    }
  }
}
