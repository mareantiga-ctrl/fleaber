/// REDTEAM_BLIND_AJ pass1 — new variants only. Staging. No fixes.
import 'dart:io';
import '_rtaj.dart';

Future<void> main() async {
  final rt = Rtaj.fromEnv(loadEnv());
  stdout.writeln('AJ pass1 staging=${rt.url}');
  await rt.loginActors();
  await rt.ensureBuyer2();
  await rt.ensureSeller2();
  await rt.ensureHelper();
  await rt.ensureViewHelper();

  final liveA = await rt.insertLive();
  final liveB = await rt.insertLive();
  final liveS2 = await rt.insertLive(seller: rt.seller2Id);
  if (liveA == null || liveB == null || liveS2 == null) {
    stderr.writeln('fixture live failed');
    await dumpJson('${outDir()}/pass1.json', {'error': 'no live'});
    exit(4);
  }

  final sku1 = await rt.createProduct(title: '$prefix-sku1', qty: 1, price: 11);
  final sku2 = await rt.createProduct(title: '$prefix-sku2', qty: 1, price: 13);
  final skuS2 = await rt.createProduct(
    seller: rt.seller2Id,
    title: '$prefix-s2sku',
    qty: 1,
    price: 15,
  );
  final skuOwn = await rt.createProduct(title: '$prefix-own-ck', qty: 1, price: 8);

  final itemLo = await rt.insertLiveOnlyItem(
    liveId: liveA,
    qty: 1,
    jwt: rt.sellerJwt,
  );
  final itemMkt = await rt.insertMarketItem(
    liveId: liveA,
    productId: sku1!,
    qty: 1,
    jwt: rt.sellerJwt,
  );
  final itemLo2 = await rt.insertLiveOnlyItem(
    liveId: liveA,
    qty: 2,
    jwt: rt.sellerJwt,
    ref: 'Q2',
  );

  // staff
  final hEmail = '${prefix.toLowerCase()}-h1@fleaber.test';
  final vEmail = '${prefix.toLowerCase()}-hv@fleaber.test';
  final hid = await rt.inviteHelper(
    helperUserId: rt.helperId!,
    helperEmail: hEmail,
    perms: {
      'can_manage_reservations': true,
      'can_view_live_dashboard': true,
    },
  );
  if (hid != null) {
    final acc = await rt.acceptInvite(hid, jwt: rt.helperJwt);
    rt.note('staff.invite.ops', 'ops helper accept', acc.brief, lens: 'AJ2');
  }
  final vid = await rt.inviteHelper(
    helperUserId: rt.viewId!,
    helperEmail: vEmail,
    perms: {
      'can_view_live_dashboard': true,
      'can_manage_reservations': false,
      'can_mark_items_sold': false,
      'can_change_current_item': false,
    },
  );
  if (vid != null) {
    final acc = await rt.acceptInvite(vid, jwt: rt.viewJwt);
    rt.note('staff.invite.view', 'view helper accept', acc.brief, lens: 'AJ2');
  }

  // --------------------------------------------------------------------------
  // AJ1 convert bypass — NEW paths (not PATCH accepted→converted exact)
  // --------------------------------------------------------------------------
  if (itemLo != null) {
    final rPend = await rt.insertReservation(
      liveId: liveA,
      liveItemId: itemLo,
      buyer: rt.buyerId,
      jwt: rt.buyerJwt,
      source: 'fleaber_live',
    );
    final rid = rPend.firstId;
    rt.note('aj1.buyer.pending', 'buyer pending', rPend.brief, lens: 'AJ1');

    if (rid != null) {
      final sc = await rt.stripeConvert(rid, jwt: rt.buyerJwt);
      final afterSc = await rt.reqRow(rid);
      if (afterSc?['status'] == 'converted') {
        rt.hold(
          id: 'AJ1-01',
          lens: 'AJ1',
          severity: 'P1',
          title: 'stripe_convert JWT converte sem order paga',
          actor: 'buyer',
          pre: 'pending sem order paga',
          repro: 'POST rpc/batata_live_reservation_stripe_convert',
          expected: 'blocked / status!=converted',
          obtained: {'rpc': sc.brief, 'row': afterSc},
        );
      } else {
        rt.block('AJ1-01', 'AJ1', 'stripe_convert JWT', {
          'rpc': sc.brief,
          'status': afterSc?['status'],
        });
      }

      final scS = await rt.stripeConvert(rid, jwt: rt.sellerJwt);
      final afterScS = await rt.reqRow(rid);
      if (afterScS?['status'] == 'converted') {
        rt.hold(
          id: 'AJ1-02',
          lens: 'AJ1',
          severity: 'P1',
          title: 'stripe_convert seller JWT converte sem PI',
          actor: 'seller',
          pre: 'pending sem order paga',
          repro: 'POST rpc/batata_live_reservation_stripe_convert seller',
          expected: 'blocked',
          obtained: {'rpc': scS.brief, 'row': afterScS},
        );
      } else {
        rt.block('AJ1-02', 'AJ1', 'stripe_convert seller', {
          'rpc': scS.brief,
          'status': afterScS?['status'],
        });
      }

      final convRpc = await rt.processReservation(rid, 'convert');
      final afterConv = await rt.reqRow(rid);
      if (afterConv?['status'] == 'converted') {
        rt.hold(
          id: 'AJ1-03',
          lens: 'AJ1',
          severity: 'P1',
          title: 'process convert pending sem order paga',
          actor: 'seller',
          pre: 'pending',
          repro: 'p_action=convert sem PI',
          expected: 'convert_requires_paid_order',
          obtained: {'rpc': convRpc.brief, 'row': afterConv},
        );
      } else {
        rt.block('AJ1-03', 'AJ1', 'process convert pending', {
          'rpc': convRpc.brief,
          'status': afterConv?['status'],
        });
      }
    }

    final insConv = await rt.insertReservation(
      liveId: liveA,
      liveItemId: itemLo,
      buyer: rt.buyerId,
      jwt: rt.sellerJwt,
      source: 'ocr_manual',
      status: 'converted',
    );
    if (insConv.ok && insConv.map?['status'] == 'converted') {
      rt.hold(
        id: 'AJ1-04',
        lens: 'AJ1',
        severity: 'P1',
        title: 'INSERT converted via source ocr_manual (bypass force_pending)',
        actor: 'seller',
        pre: 'source ocr_manual',
        repro: 'POST live_reservation_requests status=converted source=ocr_manual',
        expected: 'convert_requires_paid_order ou pending',
        obtained: insConv.brief,
      );
    } else {
      rt.block('AJ1-04', 'AJ1', 'INSERT converted ocr_manual', insConv.brief);
    }

    final insAcc = await rt.insertReservation(
      liveId: liveA,
      liveItemId: itemLo,
      buyer: rt.buyer2Id,
      jwt: rt.sellerJwt,
      source: 'instagram',
      status: 'accepted',
      qty: 1,
    );
    rt.note('aj1.insert.accepted.ig', 'INSERT accepted source instagram',
        insAcc.brief,
        lens: 'AJ1');
    if (insAcc.ok && insAcc.map?['status'] == 'accepted') {
      rt.hold(
        id: 'AJ1-05',
        lens: 'AJ1',
        severity: 'P2',
        title: 'INSERT accepted com source fora da lista force_pending',
        actor: 'seller',
        pre: 'source=instagram',
        repro: 'POST reservation status=accepted source=instagram',
        expected: 'pending (force) ou qty check',
        obtained: insAcc.map,
      );
    } else {
      rt.block('AJ1-05', 'AJ1', 'INSERT accepted instagram', insAcc.brief);
    }

    // order status 'paid' EN + sync RPC
    if (sku1 != null && itemMkt != null) {
      final ord = await rt.insertOrder(
        productId: sku1,
        jwt: rt.buyerJwt,
        liveItemId: itemMkt,
        liveId: liveA,
        price: 11,
      );
      final oid = ord.firstId;
      rt.note('aj1.order.insert', 'buyer order', ord.brief, lens: 'AJ1');
      if (oid != null) {
        final patchPaid = await rt.rest(
          'PATCH',
          'orders?id=eq.$oid',
          jwt: rt.buyerJwt,
          body: {'status': 'paid'},
        );
        final orow = await rt.orderRow(oid);
        rt.note('aj1.order.paid.en', 'PATCH status=paid', {
          'patch': patchPaid.brief,
          'row': orow?['status'],
        }, lens: 'AJ1');

        final r2 = await rt.insertReservation(
          liveId: liveA,
          liveItemId: itemMkt,
          buyer: rt.buyerId,
          jwt: rt.buyerJwt,
          source: 'fleaber_live',
        );
        final r2id = r2.firstId;
        final sync = await rt.syncItemForOrder(oid, jwt: rt.buyerJwt);
        final rec = await rt.reconcileStripe(oid, reqId: r2id, jwt: rt.buyerJwt);
        final afterSyncReq = r2id == null ? null : await rt.reqRow(r2id);
        final afterOrd = await rt.orderRow(oid);
        if (afterSyncReq?['status'] == 'converted') {
          rt.hold(
            id: 'AJ1-06',
            lens: 'AJ1',
            severity: 'P1',
            title: 'sync/reconcile converte com status paid/aguarda sem PI',
            actor: 'buyer',
            pre: 'order sem amount_paid nem PI',
            repro: 'PATCH status=paid + sync_live_item_for_order / reconcile',
            expected: 'reservation != converted',
            obtained: {
              'sync': sync.brief,
              'reconcile': rec.brief,
              'req': afterSyncReq,
              'order': afterOrd,
            },
          );
        } else {
          rt.block('AJ1-06', 'AJ1', 'sync/reconcile unpaid', {
            'sync': sync.brief,
            'reconcile': rec.brief,
            'req': afterSyncReq?['status'],
            'order': afterOrd?['status'],
          });
        }

        final patchAguarda = await rt.rest(
          'PATCH',
          'orders?id=eq.$oid',
          jwt: rt.sellerJwt,
          body: {'status': 'aguarda_confirmacao'},
        );
        final rec2 = await rt.reconcileStripe(oid, reqId: r2id, jwt: rt.sellerJwt);
        final afterRec2 = r2id == null ? null : await rt.reqRow(r2id);
        if (afterRec2?['status'] == 'converted') {
          rt.hold(
            id: 'AJ1-07',
            lens: 'AJ1',
            severity: 'P1',
            title: 'reconcile trata aguarda_confirmacao como pago',
            actor: 'seller',
            pre: 'order aguarda_confirmacao sem PI',
            repro: 'PATCH aguarda_confirmacao + reconcile',
            expected: 'order_not_paid / no convert',
            obtained: {
              'patch': patchAguarda.brief,
              'rpc': rec2.brief,
              'req': afterRec2,
            },
          );
        } else {
          rt.block('AJ1-07', 'AJ1', 'reconcile aguarda', {
            'patch': patchAguarda.brief,
            'rpc': rec2.brief,
            'status': afterRec2?['status'],
          });
        }
      }
    }
  }

  // AJ1 one PI (service fixture paid) converting TWO reservations
  if (itemLo2 != null && sku2 != null) {
    final rA = await rt.insertReservation(
      liveId: liveA,
      liveItemId: itemLo2,
      buyer: rt.buyerId,
      jwt: rt.buyerJwt,
      source: 'fleaber_live',
    );
    final rB = await rt.insertReservation(
      liveId: liveA,
      liveItemId: itemLo2,
      buyer: rt.buyerId,
      jwt: rt.buyerJwt,
      source: 'fleaber_live',
    );
    // paid order fixture — service_role only to CREATE paid state, exploit is JWT convert
    final paid = await rt.rest('POST', 'orders', service: true, body: {
      'buyer_id': rt.buyerId,
      'seller_id': rt.sellerId,
      'product_id': sku2,
      'price_total': 13,
      'quantity': 1,
      'status': 'pago',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
      'live_item_id': itemLo2,
      'live_id': liveA,
      'amount_paid_cents': 1300,
      'stripe_payment_intent_id': 'pi_rtaj_reuse_${stamp}',
    });
    final paidId = paid.firstId;
    if (paidId != null) rt.createdOrderIds.add(paidId);
    rt.note('aj1.paid.fixture', 'service paid order qty=1', paid.brief, lens: 'AJ1');

    final idA = rA.firstId;
    final idB = rB.firstId;
    if (idA != null) {
      await rt.processReservation(idA, 'accept');
    }
    if (idB != null) {
      await rt.processReservation(idB, 'accept');
    }
    HttpHit? cA;
    HttpHit? cB;
    if (idA != null) cA = await rt.processReservation(idA, 'convert');
    if (idB != null) cB = await rt.processReservation(idB, 'convert');
    final rowA = idA == null ? null : await rt.reqRow(idA);
    final rowB = idB == null ? null : await rt.reqRow(idB);
    final convCount = [
      rowA?['status'],
      rowB?['status'],
    ].where((s) => s == 'converted').length;
    if (convCount >= 2) {
      rt.hold(
        id: 'AJ1-08',
        lens: 'AJ1',
        severity: 'P1',
        title: 'Um order pago converte duas reservas (sem bind único)',
        actor: 'seller',
        pre: 'qty=2 item, 1 PI qty=1, duas reservas mesmo buyer',
        repro: 'process convert nas duas reservas',
        expected: 'só 1 converted (order já consumida)',
        obtained: {
          'cA': cA?.brief,
          'cB': cB?.brief,
          'rowA': rowA,
          'rowB': rowB,
        },
      );
    } else {
      rt.block('AJ1-08', 'AJ1', 'one PI two convert', {
        'convCount': convCount,
        'cA': cA?.brief,
        'cB': cB?.brief,
        'stA': rowA?['status'],
        'stB': rowB?['status'],
      });
    }
  }

  // --------------------------------------------------------------------------
  // AJ4 mark_sold NEW: checkout_product_id live_only, INSERT sold, cross-seller
  // --------------------------------------------------------------------------
  if (skuOwn != null) {
    final loCk = await rt.insertLiveOnlyItem(
      liveId: liveA,
      qty: 1,
      jwt: rt.sellerJwt,
      checkoutProductId: skuOwn,
      ref: 'CKOWN',
    );
    rt.note('aj4.lo.ck.own', 'live_only + checkout own sku', loCk, lens: 'AJ4');
    if (loCk != null) {
      final before = await rt.productRow(skuOwn);
      final ms = await rt.markSold(loCk, jwt: rt.sellerJwt);
      final after = await rt.productRow(skuOwn);
      final item = await rt.itemRow(loCk);
      if (after?['is_sold'] == true || after?['list_on_marketplace'] == false) {
        rt.hold(
          id: 'AJ4-01',
          lens: 'AJ4',
          severity: 'P2',
          title: 'mark_sold live_only deslista checkout_product_id sem PI',
          actor: 'seller',
          pre: 'live_only com checkout_product_id do próprio SKU, sem order paga',
          repro: 'rpc batata_mark_live_item_sold',
          expected: 'produto permanece listado (sem PI)',
          obtained: {
            'rpc': ms.brief,
            'before': before,
            'after': after,
            'item': item,
          },
        );
      } else {
        rt.block('AJ4-01', 'AJ4', 'live_only checkout own unlist', {
          'rpc': ms.brief,
          'after': after,
          'itemStatus': item?['status'],
        });
      }
    }
  }

  if (skuS2 != null) {
    final loX = await rt.insertLiveOnlyItem(
      liveId: liveA,
      qty: 1,
      jwt: rt.sellerJwt,
      checkoutProductId: skuS2,
      ref: 'CKX',
    );
    rt.note('aj4.lo.ck.x', 'live_only checkout OTHER sku', loX, lens: 'AJ4');
    if (loX != null) {
      final before = await rt.productRow(skuS2);
      final ms = await rt.markSold(loX, jwt: rt.sellerJwt);
      final after = await rt.productRow(skuS2);
      if (after?['is_sold'] == true || after?['list_on_marketplace'] == false) {
        rt.hold(
          id: 'AJ4-02',
          lens: 'AJ4',
          severity: 'P1',
          title: 'mark_sold deslista produto de outro vendedor via checkout_product_id',
          actor: 'seller',
          pre: 'live_only.checkout_product_id = SKU seller2',
          repro: 'INSERT live_only + mark_sold',
          expected: 'blocked insert ou unlist só do próprio',
          obtained: {
            'item': loX,
            'rpc': ms.brief,
            'before': before,
            'after': after,
          },
        );
      } else {
        rt.block('AJ4-02', 'AJ4', 'cross-seller checkout unlist', {
          'item': loX,
          'rpc': ms.brief,
          'after': after,
        });
      }
    } else {
      rt.block('AJ4-02', 'AJ4', 'INSERT live_only checkout other blocked', 'no item');
    }
  }

  final insSold = await rt.rest('POST', 'live_items', jwt: rt.sellerJwt, body: {
    'live_id': liveA,
    'ref_code': 'SOLDINS',
    'title': '$prefix insert-sold',
    'price': 4,
    'is_active': true,
    'item_kind': 'live_only',
    'quantity': 1,
    'status': 'sold',
  });
  if (insSold.ok) {
    final id = insSold.firstId;
    if (id != null) rt.createdItemIds.add(id);
    if (insSold.map?['status'] == 'sold') {
      rt.hold(
        id: 'AJ4-03',
        lens: 'AJ4',
        severity: 'P2',
        title: 'INSERT live_item status=sold (guard só no UPDATE)',
        actor: 'seller',
        pre: 'item novo',
        repro: 'POST live_items status=sold',
        expected: 'live_item_status_sold_rpc_only ou status!=sold',
        obtained: insSold.map,
      );
    } else {
      rt.block('AJ4-03', 'AJ4', 'INSERT sold coerced', insSold.map);
    }
  } else {
    rt.block('AJ4-03', 'AJ4', 'INSERT sold', insSold.brief);
  }

  if (itemMkt != null) {
    final msBuyer = await rt.markSold(itemMkt, jwt: rt.buyerJwt);
    rt.block('AJ4-04', 'AJ4', 'buyer mark_sold', msBuyer.brief);
    final msS2 = await rt.markSold(itemMkt, jwt: rt.seller2Jwt);
    if (msS2.rpcOk) {
      final row = await rt.itemRow(itemMkt);
      if (row?['status'] == 'sold') {
        rt.hold(
          id: 'AJ4-05',
          lens: 'AJ7',
          severity: 'P1',
          title: 'seller2 mark_sold na live alheia',
          actor: 'seller2',
          pre: 'item da live A',
          repro: 'rpc mark_sold JWT seller2',
          expected: 'not_allowed',
          obtained: {'rpc': msS2.brief, 'row': row},
        );
      }
    } else {
      rt.block('AJ4-05', 'AJ7', 'seller2 mark_sold', msS2.brief);
    }
  }

  // --------------------------------------------------------------------------
  // AJ3 Hub / discovery NEW surfaces (not REST live_items exact AG3)
  // --------------------------------------------------------------------------
  Future<void> hubScan(String tag, String itemId, String? productId) async {
    final disc = await rt.rest(
      'GET',
      'hub_live_items_discovery_public?id=eq.$itemId&select=id,status,title',
    );
    final hub = await rt.rest(
      'GET',
      'hub_live_items_public?id=eq.$itemId&select=id,status,title',
    );
    final fomo = await rt.rpc(
      'batata_hub_live_fomo_snapshot',
      {'p_live_id': liveA},
    );
    final fomoAnon = await rt.rpc(
      'batata_hub_live_fomo_snapshot',
      {'p_live_id': liveA},
    );
    HttpHit? prodHub;
    HttpHit? prodRestBuyer;
    if (productId != null) {
      prodHub = await rt.rest(
        'GET',
        'hub_products_public?id=eq.$productId&select=id,title,is_sold',
      );
      prodRestBuyer = await rt.rest(
        'GET',
        'products?id=eq.$productId&select=id,title,is_sold,list_on_marketplace,quantity',
        jwt: rt.buyerJwt,
      );
    }
    final restBuyer = await rt.rest(
      'GET',
      'live_items?id=eq.$itemId&select=id,status,quantity,is_active',
      jwt: rt.buyerJwt,
    );
    rt.note('aj3.$tag', 'hub scan', {
      'discovery': disc.brief,
      'hub_items': hub.brief,
      'fomo': clip(fomo.brief, 220),
      'fomoAnon': clip(fomoAnon.brief, 120),
      'prodHub': prodHub?.brief,
      'prodBuyer': prodRestBuyer?.brief,
      'restBuyer': restBuyer.brief,
    }, lens: 'AJ3');
    final discHit = disc.ok && disc.list.isNotEmpty;
    final hubHit = hub.ok && hub.list.isNotEmpty;
    final fomoItems = fomo.map?['items'];
    var fomoHit = false;
    if (fomoItems is List) {
      fomoHit = fomoItems.any((e) => e is Map && e['live_item_id'] == itemId);
    }
    return;
  }

  if (itemMkt != null) {
    await hubScan('mkt-before', itemMkt, sku1);
  }

  // exhaust via accept then see hub (NEW: accepted full, not status=sold)
  if (itemMkt != null) {
    final pend = await rt.insertReservation(
      liveId: liveA,
      liveItemId: itemMkt,
      buyer: rt.buyer2Id,
      jwt: rt.buyer2Jwt,
      source: 'fleaber_live',
    );
    final pid = pend.firstId;
    HttpHit? acc;
    if (pid != null) acc = await rt.processReservation(pid, 'accept');
    final st = await rt.stock(itemMkt);
    final item = await rt.itemRow(itemMkt);
    rt.note('aj3.accepted.stock', 'after accept', {
      'acc': acc?.brief,
      'stock': st.brief,
      'item': item,
    }, lens: 'AJ3');
    final disc = await rt.rest(
      'GET',
      'hub_live_items_discovery_public?id=eq.$itemMkt&select=id,status',
    );
    final hub = await rt.rest(
      'GET',
      'hub_live_items_public?id=eq.$itemMkt&select=id,status',
    );
    final fomo = await rt.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': liveA});
    final fomoItems = fomo.map?['items'];
    var fomoAvail = <dynamic>[];
    if (fomoItems is List) {
      fomoAvail = fomoItems
          .whereType<Map>()
          .where((e) => e['live_item_id'] == itemMkt)
          .toList();
    }
    final ghostDisc = disc.ok && disc.list.isNotEmpty;
    final ghostHub = hub.ok && hub.list.isNotEmpty;
    final ghostFomo = fomoAvail.any((e) {
      final aq = e['available_qty'];
      return aq is num && aq <= 0;
    });
    if (ghostDisc || ghostHub || ghostFomo) {
      rt.hold(
        id: 'AJ3-01',
        lens: 'AJ3',
        severity: 'P2',
        title: 'Item esgotado por accept ainda visível em Hub/FOMO',
        actor: 'anon/buyer',
        pre: 'qty=1 accepted',
        repro: 'GET hub_* + fomo após accept',
        expected: 'oculto / available_qty>0 só se visível',
        obtained: {
          'disc': disc.brief,
          'hub': hub.brief,
          'fomoMatch': fomoAvail,
          'stock': st.map,
        },
      );
    } else {
      rt.block('AJ3-01', 'AJ3', 'hub after accept', {
        'disc': disc.brief,
        'hub': hub.brief,
        'fomoMatch': fomoAvail,
      });
    }

    if (sku1 != null) {
      final ph = await rt.rest(
        'GET',
        'hub_products_public?id=eq.$sku1&select=id,is_sold',
      );
      if (ph.ok && ph.list.isNotEmpty) {
        rt.hold(
          id: 'AJ3-02',
          lens: 'AJ3',
          severity: 'P2',
          title: 'SKU marketplace continua no Hub após live accept esgotar',
          actor: 'anon',
          pre: 'live qty=1 accepted, product ainda listado',
          repro: 'GET hub_products_public',
          expected: 'oculto se stock live esgotado (ou documentar canal paralelo)',
          obtained: ph.map,
        );
      } else {
        rt.block('AJ3-02', 'AJ3', 'hub products after accept', ph.brief);
      }
    }
  }

  // --------------------------------------------------------------------------
  // AJ5 live_id / qty NEW: duplicate SKU, INSERT huge qty, move, other product
  // --------------------------------------------------------------------------
  if (sku2 != null) {
    final dup1 = await rt.insertMarketItem(
      liveId: liveA,
      productId: sku2,
      qty: 1,
      jwt: rt.sellerJwt,
      ref: 'DUP1',
    );
    final dup2 = await rt.insertMarketItem(
      liveId: liveB,
      productId: sku2,
      qty: 1,
      jwt: rt.sellerJwt,
      ref: 'DUP2',
    );
    rt.note('aj5.dup.items', 'two live_items same sku', {
      'dup1': dup1,
      'dup2': dup2,
    }, lens: 'AJ5');
    if (dup1 != null && dup2 != null) {
      final p1 = await rt.insertReservation(
        liveId: liveA,
        liveItemId: dup1,
        buyer: rt.buyerId,
        jwt: rt.buyerJwt,
        source: 'fleaber_live',
      );
      final p2 = await rt.insertReservation(
        liveId: liveB,
        liveItemId: dup2,
        buyer: rt.buyer2Id,
        jwt: rt.buyer2Jwt,
        source: 'fleaber_live',
      );
      final a1 = p1.firstId == null
          ? null
          : await rt.processReservation(p1.firstId!, 'accept');
      final a2 = p2.firstId == null
          ? null
          : await rt.processReservation(p2.firstId!, 'accept');
      final row1 = p1.firstId == null ? null : await rt.reqRow(p1.firstId!);
      final row2 = p2.firstId == null ? null : await rt.reqRow(p2.firstId!);
      final bothAcc = row1?['status'] == 'accepted' && row2?['status'] == 'accepted';
      final o1 = await rt.insertOrder(
        productId: sku2,
        jwt: rt.buyerJwt,
        liveItemId: dup1,
        liveId: liveA,
        price: 13,
      );
      final o2 = await rt.insertOrder(
        productId: sku2,
        buyer: rt.buyer2Id,
        jwt: rt.buyer2Jwt,
        liveItemId: dup2,
        liveId: liveB,
        price: 13,
      );
      final holdOrders = [o1, o2].where((h) => h.ok).length;
      if (bothAcc || holdOrders >= 2) {
        rt.hold(
          id: 'AJ5-01',
          lens: 'AJ5',
          severity: holdOrders >= 2 ? 'P1' : 'P2',
          title: 'Mesmo SKU qty=1 em duas lives: dupla reserva/order',
          actor: 'seller+buyers',
          pre: 'product.quantity=1, dois live_items',
          repro: 'accept em cada live_item + INSERT order',
          expected: '2º accept ou 2ª order bloqueada',
          obtained: {
            'a1': a1?.brief,
            'a2': a2?.brief,
            'st1': row1?['status'],
            'st2': row2?['status'],
            'o1': o1.brief,
            'o2': o2.brief,
          },
        );
      } else {
        rt.block('AJ5-01', 'AJ5', 'duplicate sku two lives', {
          'st1': row1?['status'],
          'st2': row2?['status'],
          'o1': o1.brief,
          'o2': o2.brief,
        });
      }
    }
  }

  final huge = await rt.insertLiveOnlyItem(
    liveId: liveA,
    qty: 99,
    jwt: rt.sellerJwt,
    ref: 'HUGE',
  );
  if (huge != null) {
    final row = await rt.itemRow(huge);
    final q = row?['quantity'];
    if (q is num && q >= 99) {
      rt.hold(
        id: 'AJ5-02',
        lens: 'AJ5',
        severity: 'P3',
        title: 'INSERT live_only qty=99 (inflate só bloqueado no UPDATE)',
        actor: 'seller',
        pre: 'item novo',
        repro: 'POST live_items quantity=99',
        expected: 'cap ou 1 (se política = não inflar live_only)',
        obtained: row,
      );
    } else {
      rt.block('AJ5-02', 'AJ5', 'INSERT qty 99', row);
    }
  }

  if (itemLo != null) {
    final mv = await rt.rest(
      'PATCH',
      'live_items?id=eq.$itemLo',
      jwt: rt.sellerJwt,
      body: {'live_id': liveB},
    );
    final after = await rt.itemRow(itemLo);
    if (after?['live_id'] == liveB) {
      rt.hold(
        id: 'AJ5-03',
        lens: 'AJ5',
        severity: 'P2',
        title: 'Mover live_item para outra live (reservas existentes ou não)',
        actor: 'seller',
        pre: 'itemLo com possível reserva',
        repro: 'PATCH live_id',
        expected: 'live_item_live_id_immutable se houve reserva',
        obtained: {'patch': mv.brief, 'row': after},
      );
    } else {
      rt.block('AJ5-03', 'AJ5', 'move live_id', {
        'patch': mv.brief,
        'live_id': after?['live_id'],
      });
    }
  }

  if (skuS2 != null) {
    final steal = await rt.insertMarketItem(
      liveId: liveA,
      productId: skuS2,
      qty: 1,
      jwt: rt.sellerJwt,
      ref: 'STEAL',
    );
    if (steal != null) {
      rt.hold(
        id: 'AJ5-04',
        lens: 'AJ7',
        severity: 'P1',
        title: 'Anexar product_id de outro vendedor ao live_item',
        actor: 'seller',
        pre: 'sku seller2',
        repro: 'POST live_items product_id=seller2',
        expected: 'live_item_product_seller_mismatch',
        obtained: steal,
      );
    } else {
      rt.block('AJ5-04', 'AJ7', 'attach other product', 'blocked');
    }
  }

  // --------------------------------------------------------------------------
  // AJ2 staff / helper NEW (view-only ≠ can_change_current_item AG)
  // --------------------------------------------------------------------------
  if (itemLo != null) {
    final viewMs = await rt.markSold(itemLo, jwt: rt.viewJwt);
    final viewItem = await rt.itemRow(itemLo);
    if (viewMs.rpcOk && viewItem?['status'] == 'sold') {
      rt.hold(
        id: 'AJ2-01',
        lens: 'AJ2',
        severity: 'P1',
        title: 'Helper view-only executa mark_sold',
        actor: 'view-helper',
        pre: 'só can_view_live_dashboard',
        repro: 'rpc mark_sold JWT view',
        expected: 'not_allowed',
        obtained: {'rpc': viewMs.brief, 'row': viewItem},
      );
    } else {
      rt.block('AJ2-01', 'AJ2', 'view mark_sold', viewMs.brief);
    }

    final viewPatch = await rt.rest(
      'PATCH',
      'live_items?id=eq.$itemLo',
      jwt: rt.viewJwt,
      body: {'title': 'pwn-view'},
    );
    if (viewPatch.ok) {
      rt.hold(
        id: 'AJ2-02',
        lens: 'AJ2',
        severity: 'P2',
        title: 'Helper view-only PATCH live_items',
        actor: 'view-helper',
        pre: 'view-only',
        repro: 'PATCH live_items title',
        expected: 'denied',
        obtained: viewPatch.brief,
      );
    } else {
      rt.block('AJ2-02', 'AJ2', 'view PATCH item', viewPatch.brief);
    }

    final viewLive = await rt.rest(
      'PATCH',
      'lives?id=eq.$liveA',
      jwt: rt.viewJwt,
      body: {'is_active': false, 'status': 'ended'},
    );
    final liveRow = await rt.rest(
      'GET',
      'lives?id=eq.$liveA&select=id,status,is_active',
      service: true,
    );
    if (viewLive.ok && liveRow.map?['status'] == 'ended') {
      rt.hold(
        id: 'AJ2-03',
        lens: 'AJ2',
        severity: 'P1',
        title: 'Helper view-only termina a live',
        actor: 'view-helper',
        pre: 'view-only',
        repro: 'PATCH lives status=ended',
        expected: 'denied',
        obtained: {'patch': viewLive.brief, 'row': liveRow.map},
      );
      // restore live for remaining probes
      await rt.rest('PATCH', 'lives?id=eq.$liveA', service: true, body: {
        'is_active': true,
        'status': 'live',
      }, prefer: 'return=minimal');
    } else {
      rt.block('AJ2-02b', 'AJ2', 'view end live', viewLive.brief);
    }

    if (vid != null) {
      final esc = await rt.rest(
        'PATCH',
        'seller_helpers?id=eq.$vid',
        jwt: rt.viewJwt,
        body: {
          'permissions': {
            'can_mark_items_sold': true,
            'can_manage_reservations': true,
            'can_change_current_item': true,
          },
        },
      );
      final hrow = await rt.helperRow(vid);
      final perms = hrow?['permissions'];
      var escalated = false;
      if (perms is Map && perms['can_mark_items_sold'] == true) {
        escalated = true;
      }
      if (escalated) {
        rt.hold(
          id: 'AJ2-04',
          lens: 'AJ2',
          severity: 'P1',
          title: 'Helper self-escalate permissions',
          actor: 'view-helper',
          pre: 'view-only invite accepted',
          repro: 'PATCH seller_helpers.permissions',
          expected: 'permissions imutáveis',
          obtained: {'patch': esc.brief, 'row': hrow},
        );
      } else {
        rt.block('AJ2-04', 'AJ2', 'self-escalate', {
          'patch': esc.brief,
          'perms': perms,
        });
      }
    }

    final opsItem = await rt.insertLiveOnlyItem(
      liveId: liveA,
      qty: 5,
      jwt: rt.helperJwt,
      ref: 'HINS',
    );
    if (opsItem != null) {
      rt.hold(
        id: 'AJ2-05',
        lens: 'AJ2',
        severity: 'P2',
        title: 'Helper can_manage_reservations INSERT live_item qty=5',
        actor: 'ops-helper',
        pre: 'sem can_mark_items_sold',
        repro: 'POST live_items JWT helper',
        expected: 'denied ou qty=1',
        obtained: await rt.itemRow(opsItem),
      );
    } else {
      rt.block('AJ2-05', 'AJ2', 'helper INSERT item', 'blocked');
    }
  }

  // --------------------------------------------------------------------------
  // AJ7 cross-seller sabotage NEW
  // --------------------------------------------------------------------------
  final endS2 = await rt.rest(
    'PATCH',
    'lives?id=eq.$liveS2',
    jwt: rt.sellerJwt,
    body: {'is_active': false, 'status': 'ended'},
  );
  final s2row = await rt.rest(
    'GET',
    'lives?id=eq.$liveS2&select=id,status,is_active',
    service: true,
  );
  if (endS2.ok && s2row.map?['status'] == 'ended') {
    rt.hold(
      id: 'AJ7-01',
      lens: 'AJ7',
      severity: 'P1',
      title: 'Seller A termina live de seller2 via PATCH',
      actor: 'seller',
      pre: 'liveS2 alheia',
      repro: 'PATCH lives?id=eq.s2',
      expected: 'denied',
      obtained: {'patch': endS2.brief, 'row': s2row.map},
    );
    await rt.rest('PATCH', 'lives?id=eq.$liveS2', service: true, body: {
      'is_active': true,
      'status': 'live',
    }, prefer: 'return=minimal');
  } else {
    rt.block('AJ7-01', 'AJ7', 'PATCH other live', endS2.brief);
  }

  final muxTok = await rt.edge('livekit-mux-publish', {
    'step': 'token',
    'live_id': liveS2,
  }, jwt: rt.sellerJwt);
  if (muxTok.ok && (muxTok.map?['token'] != null || muxTok.body.contains('eyJ'))) {
    rt.hold(
      id: 'AJ7-02',
      lens: 'AJ7',
      severity: 'P1',
      title: 'LiveKit token para live alheia',
      actor: 'seller',
      pre: 'liveS2',
      repro: 'edge livekit-mux-publish step=token',
      expected: '403',
      obtained: muxTok.brief,
    );
  } else {
    rt.block('AJ7-02', 'AJ7', 'mux token other live', muxTok.brief);
  }

  final completeOther = await rt.edge('complete-mux-live', {
    'live_id': liveS2,
  }, jwt: rt.sellerJwt);
  if (completeOther.ok && completeOther.map?['ok'] == true) {
    rt.hold(
      id: 'AJ7-03',
      lens: 'AJ7',
      severity: 'P1',
      title: 'complete-mux-live em live alheia',
      actor: 'seller',
      pre: 'liveS2',
      repro: 'edge complete-mux-live',
      expected: '403',
      obtained: completeOther.brief,
    );
  } else {
    rt.block('AJ7-03', 'AJ7', 'complete-mux other', completeOther.brief);
  }

  final sk = await rt.rest(
    'GET',
    'lives?id=eq.$liveS2&select=id,mux_stream_key,stream_key,mux_live_id',
    jwt: rt.buyerJwt,
  );
  final skMap = sk.map;
  final leaked = skMap != null &&
      ((skMap['mux_stream_key'] ?? '').toString().isNotEmpty ||
          (skMap['stream_key'] ?? '').toString().isNotEmpty);
  if (leaked) {
    rt.hold(
      id: 'AJ7-04',
      lens: 'AJ7',
      severity: 'P1',
      title: 'Buyer lê stream_key REST',
      actor: 'buyer',
      pre: 'live pública',
      repro: 'GET lives select mux_stream_key',
      expected: 'coluna omitida / 403',
      obtained: sk.brief,
    );
  } else {
    rt.block('AJ7-04', 'AJ7', 'stream_key REST', sk.brief);
  }

  final sys = await rt.rpc('batata_live_system_message', {
    'p_live_id': liveS2,
    'p_body': 'Pagamento recebido 50€ — Sistema',
    'p_sender_label': 'Sistema',
  }, jwt: rt.buyerJwt);
  if (sys.rpcOk) {
    final msgs = await rt.rest(
      'GET',
      'live_messages?live_id=eq.$liveS2&select=id,kind,body,sender_label,user_id&order=created_at.desc&limit=3',
      service: true,
    );
    rt.hold(
      id: 'AJ7-05',
      lens: 'AJ7',
      severity: 'P2',
      title: 'Buyer injeta mensagem system na live alheia',
      actor: 'buyer',
      pre: 'liveS2',
      repro: 'rpc batata_live_system_message',
      expected: 'not_allowed / owner-only',
      obtained: {'rpc': sys.brief, 'msgs': msgs.brief},
    );
  } else {
    rt.block('AJ7-05', 'AJ7', 'system message other live', sys.brief);
  }

  final itemS2 = await rt.insertLiveOnlyItem(
    liveId: liveS2,
    qty: 1,
    jwt: rt.sellerJwt,
    ref: 'XLIVE',
  );
  if (itemS2 != null) {
    rt.hold(
      id: 'AJ7-06',
      lens: 'AJ7',
      severity: 'P1',
      title: 'Seller A cria live_item na live de seller2',
      actor: 'seller',
      pre: 'liveS2',
      repro: 'POST live_items live_id=s2',
      expected: 'live_item_not_authorized',
      obtained: itemS2,
    );
  } else {
    rt.block('AJ7-06', 'AJ7', 'insert item other live', 'blocked');
  }

  // --------------------------------------------------------------------------
  // AJ6 races
  // --------------------------------------------------------------------------
  final raceItem = await rt.insertLiveOnlyItem(
    liveId: liveA,
    qty: 1,
    jwt: rt.sellerJwt,
    ref: 'RACE',
  );
  if (raceItem != null) {
    final rp1 = await rt.insertReservation(
      liveId: liveA,
      liveItemId: raceItem,
      buyer: rt.buyerId,
      jwt: rt.buyerJwt,
      source: 'fleaber_live',
    );
    final rp2 = await rt.insertReservation(
      liveId: liveA,
      liveItemId: raceItem,
      buyer: rt.buyer2Id,
      jwt: rt.buyer2Jwt,
      source: 'fleaber_live',
    );
    final id1 = rp1.firstId;
    final id2 = rp2.firstId;
    if (id1 != null && id2 != null) {
      final raced = await parallel([
        rt.processReservation(id1, 'accept'),
        rt.processReservation(id2, 'accept'),
      ]);
      final s1 = await rt.reqRow(id1);
      final s2 = await rt.reqRow(id2);
      final accN = [s1?['status'], s2?['status']]
          .where((s) => s == 'accepted')
          .length;
      if (accN >= 2) {
        rt.hold(
          id: 'AJ6-01',
          lens: 'AJ6',
          severity: 'P1',
          title: 'Race dois accept no último stock',
          actor: 'seller',
          pre: 'qty=1 duas pending',
          repro: '2x process accept paralelo',
          expected: '1 accepted',
          obtained: {
            'rpc': raced.map((e) => e.brief).toList(),
            's1': s1,
            's2': s2,
          },
        );
      } else {
        rt.block('AJ6-01', 'AJ6', 'race accept', {
          'accN': accN,
          'rpc': raced.map((e) => e.brief).toList(),
        });
      }
    }

    final racedMs = await parallel([
      rt.markSold(raceItem, jwt: rt.sellerJwt),
      rt.markSold(raceItem, jwt: rt.sellerJwt),
    ]);
    rt.note('aj6.mark_sold.race', 'double mark_sold',
        racedMs.map((e) => e.brief).toList(),
        lens: 'AJ6');
  }

  // --------------------------------------------------------------------------
  // AJ8 caixa: wallet after convert attempts + ghost pago
  // --------------------------------------------------------------------------
  final w0 = await rt.wallets();
  if (sku1 != null && itemMkt != null) {
    final ghost = await rt.insertOrder(
      productId: sku1,
      jwt: rt.buyerJwt,
      liveItemId: itemMkt,
      liveId: liveA,
      status: 'pago',
      price: 1,
    );
    final gid = ghost.firstId;
    final grow = gid == null ? null : await rt.orderRow(gid);
    if (grow != null &&
        grow['status'] == 'pago' &&
        (numOf(grow['amount_paid_cents']) ?? 0) == 0 &&
        (grow['stripe_payment_intent_id'] == null ||
            '${grow['stripe_payment_intent_id']}'.isEmpty)) {
      rt.hold(
        id: 'AJ8-01',
        lens: 'AJ8',
        severity: 'P1',
        title: 'Buyer INSERT order status=pago sem PI',
        actor: 'buyer',
        pre: 'JWT buyer',
        repro: 'POST orders status=pago',
        expected: 'reserva_pendente',
        obtained: grow,
      );
    } else {
      rt.block('AJ8-01', 'AJ8', 'ghost pago insert', {
        'http': ghost.brief,
        'row': grow,
      });
    }
  }
  final w1 = await rt.wallets();
  rt.note('aj8.wallet.delta', 'wallets', {'before': w0, 'after': w1}, lens: 'AJ8');
  final dSeller = (w1['seller'] ?? 0) - (w0['seller'] ?? 0);
  final dBuyer = (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0);
  if (dSeller.abs() > 0.001 || dBuyer.abs() > 0.001) {
    rt.hold(
      id: 'AJ8-02',
      lens: 'AJ8',
      severity: 'P0',
      title: 'Δ wallet após probes live sem Stripe TEST',
      actor: 'jwt',
      pre: 'sem captura TEST',
      repro: 'pass1',
      expected: 'Δ=0',
      obtained: {'before': w0, 'after': w1},
    );
  } else {
    rt.block('AJ8-02', 'AJ8', 'wallet delta zero', {'before': w0, 'after': w1});
  }

  final tip = await rt.edge('create-live-tip-checkout', {
    'live_id': liveS2,
    'amount_eur': 1,
  }, jwt: rt.buyerJwt);
  rt.note('aj8.tip.other', 'tip checkout live alheia', tip.brief, lens: 'AJ8');

  await rt.endLives();

  await dumpJson('${outDir()}/pass1.json', {
    'findings': rt.findings,
    'blocked': rt.blocked,
    'notes': rt.notes,
    'skipped': rt.skipped,
    'lenses': rt.lensesHit.toList()..sort(),
    'ids': {
      'liveA': liveA,
      'liveB': liveB,
      'liveS2': liveS2,
      'products': rt.createdProductIds,
      'items': rt.createdItemIds,
      'reqs': rt.createdReqIds,
      'orders': rt.createdOrderIds,
    },
  });
  stdout.writeln(
      'DONE findings=${rt.findings.length} blocked=${rt.blocked.length} notes=${rt.notes.length}');
}
