/// REDTEAM_BLIND_X pass1 — facebook_manual / staff / qty / mux / 2.º seller.
/// Staging only. No production. No Fase 4. No fixes.
import 'dart:io';

import '_rtx.dart';

Future<void> main() async {
  final c = Rtx.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.ensureHelper();
  await c.ensureViewHelper();

  final w0 = await c.wallets();
  c.note('fix.w0', 'wallets before', w0);

  final liveA = await c.insertLive();
  final liveB = await c.insertLive();
  final liveS2 = await c.insertLive(seller: c.seller2Id);
  final liveDraft = await c.insertLive(active: false, status: 'draft');
  c.note('fix.lives', 'lives A/B/S2/draft', {
    'A': liveA,
    'B': liveB,
    'S2': liveS2,
    'draft': liveDraft,
  });
  if (liveA == null || liveB == null || liveS2 == null) {
    throw StateError('fixture lives failed');
  }

  final itemA1 = await c.insertLiveOnlyItem(
    liveId: liveA,
    qty: 5,
    ref: 'XA1',
    jwt: c.sellerJwt,
  );
  final itemA2 = await c.insertLiveOnlyItem(
    liveId: liveA,
    qty: 1,
    ref: 'XA2',
    jwt: c.sellerJwt,
  );
  final itemB1 = await c.insertLiveOnlyItem(
    liveId: liveB,
    qty: 2,
    ref: 'XB1',
    jwt: c.sellerJwt,
  );
  final itemS2 = await c.insertLiveOnlyItem(
    liveId: liveS2,
    qty: 2,
    ref: 'XS2',
    jwt: c.seller2Jwt,
  );
  final pidMkt = await c.createProduct(qty: 1, title: '$prefix-mkt1');
  final itemMkt = pidMkt == null
      ? null
      : await c.insertMarketItem(
          liveId: liveA,
          productId: pidMkt,
          ref: 'XM1',
          jwt: c.sellerJwt,
        );
  c.note('fix.items', 'items', {
    'A1': itemA1,
    'A2': itemA2,
    'B1': itemB1,
    'S2': itemS2,
    'mkt': itemMkt,
    'pid': pidMkt,
  });

  await runX1(c, liveA, itemA1);
  await runX2(c, liveA, itemA1, liveS2, itemS2);
  await runX3(c, liveA, itemA1, itemA2, itemB1);
  await runX4(c, liveA, liveB, itemA1, itemB1, pidMkt, itemMkt);
  await runX5(c, liveA, liveDraft);
  await runX6(c, liveA);
  await runX7(c, liveA, itemA1, liveS2, itemS2);
  await runX8(c, liveA, itemA1, itemMkt, pidMkt);

  await c.endLives();
  final wEnd = await c.wallets();
  c.note('fix.wend', 'wallets after (lives ended)', wEnd);

  final out = {
    'auditor': 'REDTEAM_BLIND_X_LIVE_MANUAL_STAFF_v1',
    'stamp': stamp,
    'production_touched': false,
    'fase4': false,
    'lenses': c.lensesHit.toList()..sort(),
    'findings': c.findings,
    'blocked': c.blocked,
    'skipped': c.skipped,
    'notes': c.notes,
    'ids': {
      'lives': c.createdLiveIds,
      'items': c.createdItemIds,
      'reqs': c.createdReqIds,
      'products': c.createdProductIds,
      'orders': c.createdOrderIds,
      'helpers': c.createdHelperIds,
    },
    'wallets': {'before': w0, 'after': wEnd},
  };
  await dumpJson('${outDir()}/pass1.json', out);
  stdout.writeln(
      'WROTE ${outDir()}/pass1.json findings=${c.findings.length} blocked=${c.blocked.length}');
}

Future<void> runX1(Rtx c, String liveA, String? itemA1) async {
  final buyerFb = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    jwt: c.buyerJwt,
  );
  c.note('x1.buyer.fb', 'buyer INSERT facebook_manual', buyerFb.brief, lens: 'X1');
  if (buyerFb.ok) {
    c.hold(
      id: 'RTX-X1-buyer-insert-fb',
      lens: 'X1',
      severity: 'P1',
      title: 'Comprador INSERT facebook_manual na live alheia',
      actor: 'buyer JWT',
      pre: 'live A seller; buyer não é staff',
      repro: 'POST live_reservation_requests source=facebook_manual JWT buyer',
      expected: 'RLS recusa',
      obtained: buyerFb.brief,
      evidence: {'row': buyerFb.map},
    );
  } else {
    c.block('RTX-X1-buyer-insert-fb', 'X1', 'buyer facebook_manual recusado',
        buyerFb.brief);
  }

  final fbPend = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    status: 'accepted',
    qty: 1,
    jwt: c.sellerJwt,
  );
  c.note('x1.seller.fb.accepted', 'seller INSERT facebook_manual status=accepted',
      fbPend.brief, lens: 'X1');
  final fbId = fbPend.firstId;
  if (fbId != null) c.createdReqIds.add(fbId);
  final fbRow0 = fbId == null ? null : await c.reqRow(fbId);
  final forcedPending = fbRow0?['status']?.toString() == 'pending';
  if (fbPend.ok && !forcedPending && fbRow0?['status'] == 'accepted') {
    c.hold(
      id: 'RTX-X1-insert-accepted',
      lens: 'X1',
      severity: 'P2',
      title: 'facebook_manual INSERT directo como accepted (sem RPC accept)',
      actor: 'seller JWT',
      pre: 'live activa; item qty=5',
      repro: 'POST live_reservation_requests status=accepted source=facebook_manual',
      expected: 'trigger força pending',
      obtained: fbRow0,
      evidence: {'insert': fbPend.brief, 'row': fbRow0},
    );
  } else if (fbPend.ok) {
    c.block('RTX-X1-force-pending', 'X1', 'INSERT accepted forçado a pending',
        fbRow0);
  }

  if (fbId != null && fbRow0?['status'] == 'pending') {
    final acc = await c.processReservation(fbId, 'accept', jwt: c.sellerJwt);
    c.note('x1.fb.accept', 'accept facebook_manual', acc.brief, lens: 'X1');
  }

  if (fbId != null) {
    final wBefore = await c.wallets();
    final conv = await c.processReservation(fbId, 'convert', jwt: c.sellerJwt);
    final rowAfter = await c.reqRow(fbId);
    final itemAfter = itemA1 == null ? null : await c.itemRow(itemA1);
    final orders = itemA1 == null ? <dynamic>[] : await c.ordersForItem(itemA1);
    final wAfter = await c.wallets();
    c.note('x1.fb.convert', 'convert facebook_manual sem PI', {
      'rpc': conv.brief,
      'row': rowAfter,
      'item': itemAfter,
      'orders': orders.length,
      'wallets': {'before': wBefore, 'after': wAfter},
    }, lens: 'X1');
    final converted = rowAfter?['status'] == 'converted';
    final walletDelta = (wAfter['seller'] ?? 0) - (wBefore['seller'] ?? 0);
    if (converted && conv.rpcOk) {
      var sev = 'P1';
      for (final o in orders) {
        if (o is! Map) continue;
        final paid = numOf(o['amount_paid_cents']) ?? 0;
        final pi = '${o['stripe_payment_intent_id']}';
        if (paid > 0 || (pi.isNotEmpty && pi != 'null')) {
          sev = 'P0';
        }
      }
      if (walletDelta > 0) sev = 'P0';
      c.hold(
        id: 'RTX-X1-fb-convert-no-pi',
        lens: 'X1',
        severity: sev,
        title: 'convert facebook_manual sem encomenda paga / PI',
        actor: 'seller JWT',
        pre: 'reserva facebook_manual accepted; zero PI; item live_only qty=5',
        repro:
            'rpc batata_process_live_reservation_request action=convert source=facebook_manual',
        expected:
            'convert_requires_paid_order também para facebook_manual, ou convert sem marcar vendido/caixa',
        obtained: {
          'rpc': conv.map ?? conv.brief,
          'status': rowAfter?['status'],
          'item_status': itemAfter?['status'],
          'orders': orders,
          'seller_wallet_delta': walletDelta,
        },
        evidence: {
          'request_id': fbId,
          'item_id': itemA1,
          'converted': converted,
          'item': itemAfter,
          'orders': orders,
          'wallet_delta': walletDelta,
        },
      );
    } else {
      c.block('RTX-X1-fb-convert-no-pi', 'X1',
          'convert facebook_manual recusado sem pago', conv.brief);
    }
  }

  final fbAlienBuyer = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.seller2Id,
    jwt: c.sellerJwt,
  );
  c.note('x1.fb.buyer-s2', 'seller marca seller2 como buyer facebook_manual',
      fbAlienBuyer.brief, lens: 'X1');
  if (fbAlienBuyer.ok) {
    final rid = fbAlienBuyer.firstId;
    if (rid != null) c.createdReqIds.add(rid);
    c.hold(
      id: 'RTX-X1-fb-buyer-id-arbitrary',
      lens: 'X1',
      severity: 'P2',
      title: 'seller facebook_manual com buyer_id de outro utilizador',
      actor: 'seller JWT',
      pre: 'live A; buyer_id = seller2',
      repro: 'POST live_reservation_requests source=facebook_manual buyer_id=<seller2>',
      expected: 'buyer_id só nulo (walk-in) ou claim do próprio',
      obtained: fbAlienBuyer.map,
      evidence: {'row': fbAlienBuyer.map},
    );
  } else {
    c.block('RTX-X1-fb-buyer-id-arbitrary', 'X1',
        'buyer_id alheio recusado', fbAlienBuyer.brief);
  }

  final fbNullItem = await c.insertReservation(
    liveId: liveA,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  c.note('x1.fb.null-item', 'facebook_manual sem live_item_id', fbNullItem.brief,
      lens: 'X1');
  if (fbNullItem.ok) {
    final rid = fbNullItem.firstId;
    if (rid != null) c.createdReqIds.add(rid);
    c.hold(
      id: 'RTX-X1-fb-null-item',
      lens: 'X1',
      severity: 'P2',
      title: 'facebook_manual sem live_item_id aceite',
      actor: 'seller JWT',
      pre: 'live A activa',
      repro: 'POST live_reservation_requests source=facebook_manual sem live_item_id',
      expected: 'NOT NULL / recusa',
      obtained: fbNullItem.map,
    );
  } else {
    c.block('RTX-X1-fb-null-item', 'X1', 'sem live_item_id recusado',
        fbNullItem.brief);
  }

  final flIns = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    source: 'fleaber_live',
    jwt: c.buyerJwt,
  );
  c.note('x1.fl.insert', 'buyer fleaber_live pending', flIns.brief, lens: 'X1');
  if (flIns.ok && flIns.firstId != null) {
    c.createdReqIds.add(flIns.firstId!);
    final acc = await c.processReservation(flIns.firstId!, 'accept');
    final conv = await c.processReservation(flIns.firstId!, 'convert');
    c.note('x1.fl.convert', 'control fleaber_live convert sem PI', {
      'accept': acc.brief,
      'convert': conv.brief,
    }, lens: 'X1');
    if (conv.rpcOk && (await c.reqRow(flIns.firstId!))?['status'] == 'converted') {
      c.hold(
        id: 'RTX-X1-fl-convert-no-pi',
        lens: 'X1',
        severity: 'P1',
        title: 'convert fleaber_live sem PI (controlo — classe known)',
        actor: 'seller JWT',
        pre: 'fleaber_live accepted; zero PI',
        repro: 'rpc convert source=fleaber_live',
        expected: 'convert_requires_paid_order',
        obtained: conv.map ?? conv.brief,
      );
    } else {
      c.block('RTX-X1-fl-convert-no-pi', 'X1',
          'controlo: fleaber_live convert exige pago', conv.brief);
    }
  }
}

Future<void> runX2(
  Rtx c,
  String liveA,
  String? itemA1,
  String liveS2,
  String? itemS2,
) async {
  final hid = await c.inviteHelper(
    helperUserId: c.helperId!,
    helperEmail: '${prefix.toLowerCase()}-h1@fleaber.test',
  );
  c.note('x2.invite', 'invite helper can_manage_reservations', hid, lens: 'X2');
  if (hid != null) {
    final accH = await c.acceptInvite(hid, jwt: c.helperJwt);
    c.note('x2.accept', 'helper aceita convite', accH.brief, lens: 'X2');
  }
  final hRow = hid == null ? null : await c.helperRow(hid);
  c.note('x2.helper.row', 'helper row', hRow, lens: 'X2');

  final viewHid = await c.inviteHelper(
    helperUserId: c.viewId!,
    helperEmail: '${prefix.toLowerCase()}-hv@fleaber.test',
    perms: {
      'can_view_live_dashboard': true,
      'can_manage_reservations': false,
    },
  );
  if (viewHid != null) {
    await c.acceptInvite(viewHid, jwt: c.viewJwt);
  }

  if (hid != null) {
    final widen = await c.rest(
      'PATCH',
      'seller_helpers?id=eq.$hid',
      jwt: c.helperJwt,
      body: {
        'permissions': {
          'can_manage_reservations': true,
          'can_mark_items_sold': true,
          'can_change_current_item': true,
          'can_manage_stock': true,
        },
      },
    );
    final after = await c.helperRow(hid);
    c.note('x2.widen', 'helper PATCH permissions', {
      'patch': widen.brief,
      'row': after?['permissions'],
    }, lens: 'X2');
    final perms = after?['permissions'];
    final sold = perms is Map && perms['can_mark_items_sold'] == true;
    if (widen.ok && sold) {
      c.hold(
        id: 'RTX-X2-helper-widen-perms',
        lens: 'X2',
        severity: 'P1',
        title: 'helper alarga permissions via PATCH',
        actor: 'helper JWT',
        pre: 'convite aceite; perms só can_manage_reservations',
        repro: 'PATCH seller_helpers.permissions',
        expected: 'trigger restaura permissions do seller',
        obtained: after,
      );
    } else {
      c.block('RTX-X2-helper-widen-perms', 'X2', 'widen permissions bloqueado',
          {'patch': widen.brief, 'perms': perms});
    }
  }

  final s2staff = await c.rest('POST', 'seller_helpers', jwt: c.seller2Jwt, body: {
    'seller_id': c.sellerId,
    'helper_user_id': c.seller2Id,
    'invited_by': c.seller2Id,
    'invited_email': '${prefix.toLowerCase()}-s2@fleaber.test',
    'display_name': 's2',
    'invitation_status': 'accepted',
    'active': true,
    'permissions': {'can_manage_reservations': true},
  });
  c.note('x2.s2.self', 'seller2 INSERT staff na loja seller1', s2staff.brief,
      lens: 'X2');
  if (s2staff.ok) {
    c.hold(
      id: 'RTX-X2-s2-self-staff',
      lens: 'X2',
      severity: 'P0',
      title: '2.º seller insere-se como staff da loja alheia',
      actor: 'seller2 JWT',
      pre: 'seller2 não é dono',
      repro: 'POST seller_helpers seller_id=<seller1> JWT seller2',
      expected: 'RLS recusa',
      obtained: s2staff.map,
    );
  } else {
    c.block('RTX-X2-s2-self-staff', 'X2', 'self-staff alheio recusado',
        s2staff.brief);
  }

  final fbH = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyer2Id,
    jwt: c.helperJwt,
  );
  c.note('x2.helper.insert-fb', 'helper INSERT facebook_manual', fbH.brief,
      lens: 'X2');
  if (fbH.ok && fbH.firstId != null) {
    c.createdReqIds.add(fbH.firstId!);
    final acc = await c.processReservation(fbH.firstId!, 'accept', jwt: c.helperJwt);
    final conv = await c.processReservation(fbH.firstId!, 'convert', jwt: c.helperJwt);
    final row = await c.reqRow(fbH.firstId!);
    c.note('x2.helper.convert', 'helper accept+convert facebook_manual', {
      'accept': acc.brief,
      'convert': conv.brief,
      'row': row,
    }, lens: 'X2');
    if (conv.rpcOk && row?['status'] == 'converted') {
      c.hold(
        id: 'RTX-X2-helper-convert-fb',
        lens: 'X2',
        severity: 'P1',
        title: 'staff helper convert facebook_manual sem PI',
        actor: 'helper JWT can_manage_reservations',
        pre: 'helper aceite; facebook_manual pending',
        repro: 'rpc convert JWT helper',
        expected: 'convert exige pago, ou helper não converte sem PI',
        obtained: {'rpc': conv.map, 'row': row},
      );
    } else {
      c.block('RTX-X2-helper-convert-fb', 'X2', 'helper convert recusado',
          conv.brief);
    }
  } else {
    c.block('RTX-X2-helper-insert-fb', 'X2', 'helper INSERT facebook_manual recusado',
        fbH.brief);
  }

  final fbV = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  if (fbV.ok && fbV.firstId != null) {
    c.createdReqIds.add(fbV.firstId!);
    await c.processReservation(fbV.firstId!, 'accept', jwt: c.sellerJwt);
    final convV = await c.processReservation(fbV.firstId!, 'convert', jwt: c.viewJwt);
    c.note('x2.view.convert', 'view-only convert', convV.brief, lens: 'X2');
    if (convV.rpcOk && (await c.reqRow(fbV.firstId!))?['status'] == 'converted') {
      c.hold(
        id: 'RTX-X2-view-convert',
        lens: 'X2',
        severity: 'P1',
        title: 'helper só can_view_live_dashboard consegue convert',
        actor: 'view helper JWT',
        pre: 'perms sem can_manage_reservations',
        repro: 'rpc convert JWT view-helper',
        expected: 'not_allowed',
        obtained: convV.map ?? convV.brief,
      );
    } else {
      c.block('RTX-X2-view-convert', 'X2', 'view-only convert recusado',
          convV.brief);
    }
  }

  if (itemS2 == null) return;
  final fbCross = await c.insertReservation(
    liveId: liveS2,
    liveItemId: itemS2,
    seller: c.seller2Id,
    buyer: c.buyerId,
    jwt: c.helperJwt,
  );
  c.note('x2.helper.cross-live', 'helper seller1 INSERT na live seller2',
      fbCross.brief, lens: 'X2');
  if (fbCross.ok) {
    c.hold(
      id: 'RTX-X2-helper-cross-seller-insert',
      lens: 'X2',
      severity: 'P0',
      title: 'helper da loja A reserva/insere na live do seller2',
      actor: 'helper JWT (staff de seller1)',
      pre: 'helper sem relação com seller2',
      repro: 'POST live_reservation_requests live_id=<S2> JWT helper-A',
      expected: 'RLS recusa',
      obtained: fbCross.map,
    );
  } else {
    c.block('RTX-X2-helper-cross-seller-insert', 'X2',
        'helper cross-seller INSERT recusado', fbCross.brief);
  }
  final s2req = await c.insertReservation(
    liveId: liveS2,
    liveItemId: itemS2,
    seller: c.seller2Id,
    buyer: c.buyerId,
    jwt: c.seller2Jwt,
  );
  if (s2req.ok && s2req.firstId != null) {
    c.createdReqIds.add(s2req.firstId!);
    final convX = await c.processReservation(s2req.firstId!, 'convert',
        jwt: c.helperJwt);
    c.note('x2.helper.convert-s2', 'helper A convert reserva seller2',
        convX.brief, lens: 'X2');
    if (convX.rpcOk) {
      c.hold(
        id: 'RTX-X2-helper-convert-foreign',
        lens: 'X2',
        severity: 'P0',
        title: 'helper da loja A converte reserva da live seller2',
        actor: 'helper JWT',
        pre: 'reserva seller2 pending/accepted',
        repro: 'rpc convert JWT helper-A p_request_id=<S2>',
        expected: 'not_allowed',
        obtained: convX.map ?? convX.brief,
      );
    } else {
      c.block('RTX-X2-helper-convert-foreign', 'X2',
          'helper convert foreign recusado', convX.brief);
    }
  }
}

Future<void> runX3(
  Rtx c,
  String liveA,
  String? itemA1,
  String? itemA2,
  String? itemB1,
) async {
  if (itemA2 != null) {
    final fbQ = await c.insertReservation(
      liveId: liveA,
      liveItemId: itemA2,
      buyer: c.buyerId,
      qty: 1,
      jwt: c.sellerJwt,
    );
    if (fbQ.ok && fbQ.firstId != null) {
      c.createdReqIds.add(fbQ.firstId!);
      await c.processReservation(fbQ.firstId!, 'accept');
      final infl = await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.${fbQ.firstId}',
        jwt: c.sellerJwt,
        body: {'requested_qty': 9},
      );
      final rowInfl = await c.reqRow(fbQ.firstId!);
      c.note('x3.inflate-qty', 'PATCH requested_qty após accept', {
        'patch': infl.brief,
        'row': rowInfl,
      }, lens: 'X3');
      if (infl.ok && (numOf(rowInfl?['requested_qty']) ?? 0) > 1) {
        c.hold(
          id: 'RTX-X3-inflate-qty-after-accept',
          lens: 'X3',
          severity: 'P1',
          title: 'inflacionar requested_qty após accept (item qty=1)',
          actor: 'seller JWT',
          pre: 'facebook_manual accepted qty=1; item live_only qty=1',
          repro: 'PATCH live_reservation_requests.requested_qty=9',
          expected: 'qty_exceeds_stock / imutável',
          obtained: rowInfl,
        );
        final conv = await c.processReservation(fbQ.firstId!, 'convert');
        c.note('x3.convert-inflated', 'convert após inflate', conv.brief, lens: 'X3');
      } else {
        c.block('RTX-X3-inflate-qty-after-accept', 'X3',
            'inflate qty pós-accept bloqueado', infl.brief);
      }
    }

    final qtyPatch = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemA2',
      jwt: c.sellerJwt,
      body: {'quantity': 50},
    );
    final itemQ = await c.itemRow(itemA2);
    c.note('x3.item-qty', 'PATCH live_items.quantity mid-live', {
      'patch': qtyPatch.brief,
      'item': itemQ,
    }, lens: 'X3');
    if (qtyPatch.ok && (numOf(itemQ?['quantity']) ?? 0) >= 50) {
      c.hold(
        id: 'RTX-X3-inflate-item-qty-midlive',
        lens: 'X3',
        severity: 'P2',
        title: 'inflacionar quantity do live_item a meio do directo',
        actor: 'seller JWT',
        pre: 'live_only qty=1 com reserva',
        repro: 'PATCH live_items.quantity=50',
        expected: 'cap vs reservas / pool estável',
        obtained: itemQ,
      );
    } else {
      c.block('RTX-X3-inflate-item-qty-midlive', 'X3',
          'inflate live_item qty bloqueado ou limitado', qtyPatch.brief);
    }
  }

  if (itemB1 != null) {
    final mark = await c.rpc('batata_mark_live_item_sold', {
      'p_live_item_id': itemB1,
    }, jwt: c.sellerJwt);
    final itemSold = await c.itemRow(itemB1);
    c.note('x3.mark-sold', 'mark_live_item_sold sem convert/PI', {
      'rpc': mark.brief,
      'item': itemSold,
    }, lens: 'X3');
    if (mark.rpcOk || itemSold?['status'] == 'sold') {
      c.hold(
        id: 'RTX-X3-mark-sold-no-convert',
        lens: 'X3',
        severity: 'P2',
        title: 'marcar live_item sold sem convert nem pagamento',
        actor: 'seller JWT',
        pre: 'item B1 live_only sem reserva convertida',
        repro: 'rpc batata_mark_live_item_sold',
        expected:
            'sold só após convert com dinheiro ou fluxo manual explícito isolado',
        obtained: {'rpc': mark.map, 'item': itemSold},
      );
    } else {
      c.block('RTX-X3-mark-sold-no-convert', 'X3', 'mark_sold recusado',
          mark.brief);
    }

    final markB = await c.rpc('batata_mark_live_item_sold', {
      'p_live_item_id': itemB1,
    }, jwt: c.buyerJwt);
    c.note('x3.buyer.mark-sold', 'buyer mark_sold item alheio', markB.brief,
        lens: 'X3');
    if (markB.rpcOk) {
      c.hold(
        id: 'RTX-X3-buyer-mark-sold',
        lens: 'X3',
        severity: 'P0',
        title: 'comprador marca live_item sold',
        actor: 'buyer JWT',
        pre: 'item do seller',
        repro: 'rpc batata_mark_live_item_sold JWT buyer',
        expected: 'not_allowed',
        obtained: markB.map ?? markB.brief,
      );
    } else {
      c.block('RTX-X3-buyer-mark-sold', 'X3', 'buyer mark_sold recusado',
          markB.brief);
    }
  }

  final fbPendConv = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyer2Id,
    jwt: c.sellerJwt,
  );
  if (fbPendConv.ok && fbPendConv.firstId != null) {
    c.createdReqIds.add(fbPendConv.firstId!);
    final convP = await c.processReservation(fbPendConv.firstId!, 'convert');
    final st = (await c.reqRow(fbPendConv.firstId!))?['status'];
    c.note('x3.pending-convert', 'convert a partir de pending', {
      'rpc': convP.brief,
      'status': st,
    }, lens: 'X3');
    if (convP.rpcOk && st == 'converted') {
      c.hold(
        id: 'RTX-X3-convert-from-pending',
        lens: 'X3',
        severity: 'P2',
        title: 'convert facebook_manual ainda pending (sem accept)',
        actor: 'seller JWT',
        pre: 'status=pending',
        repro: 'rpc convert sem accept',
        expected: 'só accepted → converted',
        obtained: {'rpc': convP.map, 'status': st},
      );
    } else {
      c.block('RTX-X3-convert-from-pending', 'X3',
          'convert pending recusado ou não converted', convP.brief);
    }
  }

  final raceItem = await c.insertLiveOnlyItem(
    liveId: liveA,
    qty: 1,
    ref: 'XRACE',
    jwt: c.sellerJwt,
  );
  if (raceItem == null) return;
  final r1 = await c.insertReservation(
    liveId: liveA,
    liveItemId: raceItem,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  final r2 = await c.insertReservation(
    liveId: liveA,
    liveItemId: raceItem,
    buyer: c.buyer2Id,
    jwt: c.sellerJwt,
  );
  if (r1.firstId == null || r2.firstId == null) return;
  c.createdReqIds.addAll([r1.firstId!, r2.firstId!]);
  final raced = await parallel([
    c.processReservation(r1.firstId!, 'accept'),
    c.processReservation(r2.firstId!, 'accept'),
  ]);
  final a1 = await c.reqRow(r1.firstId!);
  final a2 = await c.reqRow(r2.firstId!);
  c.note('x3.race-accept', 'dois accept paralelo qty=1', {
    'rpc0': raced[0].brief,
    'rpc1': raced[1].brief,
    's1': a1?['status'],
    's2': a2?['status'],
    'q1': a1?['requested_qty'],
    'q2': a2?['requested_qty'],
  }, lens: 'X3');
  final accN = [a1?['status'], a2?['status']]
      .where((s) => s == 'accepted' || s == 'converted')
      .length;
  if (accN >= 2) {
    c.hold(
      id: 'RTX-X3-race-accept-qty1',
      lens: 'X3',
      severity: 'P1',
      title: 'dois accept facebook_manual permanentes em item qty=1',
      actor: 'seller JWT ×2 paralelo',
      pre: 'live_only qty=1; duas reservas pending',
      repro: 'dois rpc accept em paralelo',
      expected: 'um accepted, outro qty_exceeds_stock',
      obtained: {'a1': a1, 'a2': a2},
    );
  } else {
    c.block('RTX-X3-race-accept-qty1', 'X3', 'race accept: no máximo um vencedor', {
      'accN': accN,
      'a1': a1?['status'],
      'a2': a2?['status'],
    });
  }
}

Future<void> runX4(
  Rtx c,
  String liveA,
  String liveB,
  String? itemA1,
  String? itemB1,
  String? pidMkt,
  String? itemMkt,
) async {
  final crossBind = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemB1,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  c.note('x4.cross-bind', 'live_id=A + live_item de B', crossBind.brief, lens: 'X4');
  if (crossBind.ok) {
    c.hold(
      id: 'RTX-X4-item-other-live',
      lens: 'X4',
      severity: 'P1',
      title: 'reserva com live_item de outra live do mesmo seller',
      actor: 'seller JWT',
      pre: 'item B1 pertence a live B',
      repro: 'POST reservation live_id=A live_item_id=<B1>',
      expected: 'live_item_live_mismatch',
      obtained: crossBind.map,
    );
  } else {
    c.block('RTX-X4-item-other-live', 'X4',
        'cross-live item recusado (mismatch)', crossBind.brief);
  }

  if (itemA1 != null) {
    final move = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemA1',
      jwt: c.sellerJwt,
      body: {'live_id': liveB},
    );
    c.note('x4.move-item', 'PATCH live_id do item com reservas', move.brief,
        lens: 'X4');
    if (move.ok) {
      c.hold(
        id: 'RTX-X4-move-item-with-res',
        lens: 'X4',
        severity: 'P1',
        title: 'mover live_item para outra live com reservas activas',
        actor: 'seller JWT',
        pre: 'item A1 com reservas accepted/converted',
        repro: 'PATCH live_items.live_id=<B>',
        expected: 'live_item_live_id_immutable',
        obtained: move.map ?? move.brief,
      );
    } else {
      c.block('RTX-X4-move-item-with-res', 'X4',
          'move live_id com reservas bloqueado', move.brief);
    }
  }

  if (pidMkt == null) return;
  final itemMktB = await c.insertMarketItem(
    liveId: liveB,
    productId: pidMkt,
    ref: 'XM2',
    jwt: c.sellerJwt,
  );
  c.note('x4.same-sku-two-lives', 'mesmo product_id em live B', itemMktB, lens: 'X4');
  if (itemMktB == null || itemMkt == null) return;
  final ra = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemMkt,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  final rb = await c.insertReservation(
    liveId: liveB,
    liveItemId: itemMktB,
    buyer: c.buyer2Id,
    jwt: c.sellerJwt,
  );
  if (ra.firstId != null) c.createdReqIds.add(ra.firstId!);
  if (rb.firstId != null) c.createdReqIds.add(rb.firstId!);
  HttpHit? convA;
  HttpHit? convB;
  if (ra.ok && ra.firstId != null) {
    await c.processReservation(ra.firstId!, 'accept');
    convA = await c.processReservation(ra.firstId!, 'convert');
  }
  if (rb.ok && rb.firstId != null) {
    await c.processReservation(rb.firstId!, 'accept');
    convB = await c.processReservation(rb.firstId!, 'convert');
  }
  final prod = await c.productRow(pidMkt);
  c.note('x4.dual-convert-sku', 'convert facebook_manual nas duas lives', {
    'convA': convA?.brief,
    'convB': convB?.brief,
    'product': prod,
  }, lens: 'X4');
  final sa = ra.firstId == null ? null : (await c.reqRow(ra.firstId!))?['status'];
  final sb = rb.firstId == null ? null : (await c.reqRow(rb.firstId!))?['status'];
  if (sa == 'converted' && sb == 'converted') {
    c.hold(
      id: 'RTX-X4-dual-live-same-sku-convert',
      lens: 'X4',
      severity: 'P1',
      title: 'mesmo SKU qty=1 convertido facebook_manual em duas lives',
      actor: 'seller JWT',
      pre: 'product qty=1 em live A e live B',
      repro: 'accept+convert facebook_manual em ambos live_items',
      expected: 'segunda convert/accept recusada (pool)',
      obtained: {'sa': sa, 'sb': sb, 'product': prod},
    );
  } else {
    c.block('RTX-X4-dual-live-same-sku-convert', 'X4',
        'segunda live não converteu o mesmo SKU', {
      'sa': sa,
      'sb': sb,
      'convB': convB?.brief,
    });
  }
}

Future<void> runX5(Rtx c, String liveA, String? liveDraft) async {
  final muxBuyer = await c.edge('livekit-mux-publish', {
    'step': 'token',
    'live_id': liveA,
  }, jwt: c.buyerJwt);
  c.note('x5.mux.buyer', 'buyer token live A', muxBuyer.brief, lens: 'X5');
  final muxToken = muxBuyer.map?['token']?.toString();
  if (muxBuyer.ok && muxToken != null && muxToken.isNotEmpty) {
    c.hold(
      id: 'RTX-X5-mux-token-buyer',
      lens: 'X5',
      severity: 'P0',
      title: 'comprador obtém token LiveKit publish da live do vendedor',
      actor: 'buyer JWT',
      pre: 'live A do seller',
      repro: 'POST livekit-mux-publish step=token live_id=<A> JWT buyer',
      expected: '403 Sem permissão',
      obtained: muxBuyer.brief,
    );
  } else {
    c.block('RTX-X5-mux-token-buyer', 'X5', 'buyer mux token recusado',
        muxBuyer.brief);
  }

  final muxS2 = await c.edge('livekit-mux-publish', {
    'step': 'token',
    'live_id': liveA,
  }, jwt: c.seller2Jwt);
  c.note('x5.mux.s2', 'seller2 token live A', muxS2.brief, lens: 'X5');
  if (muxS2.ok && (muxS2.map?['token']?.toString() ?? '').isNotEmpty) {
    c.hold(
      id: 'RTX-X5-mux-token-s2',
      lens: 'X5',
      severity: 'P0',
      title: '2.º seller obtém token publish da live alheia',
      actor: 'seller2 JWT',
      pre: 'live A não é dele',
      repro: 'POST livekit-mux-publish step=token JWT seller2',
      expected: '403',
      obtained: muxS2.brief,
    );
  } else {
    c.block('RTX-X5-mux-token-s2', 'X5', 'seller2 mux token recusado', muxS2.brief);
  }

  final muxH = await c.edge('livekit-mux-publish', {
    'step': 'token',
    'live_id': liveA,
  }, jwt: c.helperJwt);
  c.note('x5.mux.helper', 'helper token live A', muxH.brief, lens: 'X5');
  if (muxH.ok && (muxH.map?['token']?.toString() ?? '').isNotEmpty) {
    c.note('x5.mux.helper.got', 'helper publish token (staff da loja)', muxH.brief,
        lens: 'X5');
  } else {
    c.block('RTX-X5-mux-helper', 'X5', 'helper sem token publish (owner-only)',
        muxH.brief);
  }

  if (liveDraft != null) {
    final muxDraft = await c.edge('livekit-mux-publish', {
      'step': 'token',
      'live_id': liveDraft,
    }, jwt: c.sellerJwt);
    c.note('x5.mux.draft', 'token em live draft', muxDraft.brief, lens: 'X5');
    if (muxDraft.ok && (muxDraft.map?['token']?.toString() ?? '').isNotEmpty) {
      c.hold(
        id: 'RTX-X5-mux-draft-token',
        lens: 'X5',
        severity: 'P2',
        title: 'token publish em live draft',
        actor: 'seller JWT',
        pre: 'live status=draft is_active=false',
        repro: 'POST livekit-mux-publish step=token live_id=<draft>',
        expected: 'recusa ou draft não publica Mux',
        obtained: muxDraft.brief,
      );
    } else {
      c.block('RTX-X5-mux-draft-token', 'X5', 'draft token recusado',
          muxDraft.brief);
    }
  }

  final muxCreateB = await c.edge('create-mux-live', {
    'title': '$prefix hijack',
  }, jwt: c.buyerJwt);
  c.note('x5.create-mux.buyer', 'buyer create-mux-live', muxCreateB.brief,
      lens: 'X5');
  if (muxCreateB.ok) {
    c.hold(
      id: 'RTX-X5-create-mux-buyer',
      lens: 'X5',
      severity: 'P2',
      title: 'comprador cria live Mux',
      actor: 'buyer JWT',
      pre: 'buyer de laboratório',
      repro: 'POST create-mux-live JWT buyer',
      expected: 'recusa se não for vendedor, ou live órfã sem stock alheio',
      obtained: muxCreateB.brief,
    );
  } else {
    c.block('RTX-X5-create-mux-buyer', 'X5', 'buyer create-mux recusado',
        muxCreateB.brief);
  }

  final completeS2 = await c.edge('complete-mux-live', {
    'live_id': liveA,
  }, jwt: c.seller2Jwt);
  c.note('x5.complete.s2', 'seller2 complete-mux live A', completeS2.brief,
      lens: 'X5');
  if (completeS2.ok) {
    c.hold(
      id: 'RTX-X5-complete-foreign',
      lens: 'X5',
      severity: 'P1',
      title: '2.º seller termina Mux da live alheia',
      actor: 'seller2 JWT',
      pre: 'live A do seller',
      repro: 'POST complete-mux-live live_id=<A> JWT seller2',
      expected: '403',
      obtained: completeS2.brief,
    );
  } else {
    c.block('RTX-X5-complete-foreign', 'X5', 'complete-mux foreign recusado',
        completeS2.brief);
  }

  final stopS2 = await c.edge('livekit-mux-publish', {
    'step': 'stop_egress',
    'live_id': liveA,
    'egress_id': 'EG_FOREIGN',
  }, jwt: c.seller2Jwt);
  c.note('x5.stop.s2', 'seller2 stop_egress live A', stopS2.brief, lens: 'X5');
  if (stopS2.ok) {
    c.hold(
      id: 'RTX-X5-stop-egress-foreign',
      lens: 'X5',
      severity: 'P1',
      title: 'seller2 stop_egress na live alheia',
      actor: 'seller2 JWT',
      pre: 'não é dono',
      repro: 'POST livekit-mux-publish step=stop_egress JWT seller2',
      expected: '403 (não re-auditar exact mismatch egress_id do dono)',
      obtained: stopS2.brief,
    );
  } else {
    c.block('RTX-X5-stop-egress-foreign', 'X5', 'stop_egress foreign recusado',
        stopS2.brief);
  }
}

Future<void> runX6(Rtx c, String liveA) async {
  final raffleIns = await c.rest('POST', 'live_raffles', jwt: c.sellerJwt, body: {
    'live_id': liveA,
    'seller_id': c.sellerId,
    'title': '$prefix raffle',
    'status': 'open',
  });
  c.note('x6.raffle.insert', 'seller INSERT live_raffles', raffleIns.brief,
      lens: 'X6');
  if (!raffleIns.ok) {
    c.skip('RTX-X6-raffle', 'X6', 'INSERT live_raffles falhou — RPC-only / SKIP',
        raffleIns.brief);
    return;
  }
  final rafId = raffleIns.firstId;
  final drawS2 = await c.rpc('batata_draw_live_raffle_winners', {
    'p_raffle_id': rafId,
  }, jwt: c.seller2Jwt);
  c.note('x6.draw.s2', 'seller2 draw raffle seller1', drawS2.brief, lens: 'X6');
  if (drawS2.rpcOk) {
    c.hold(
      id: 'RTX-X6-draw-foreign',
      lens: 'X6',
      severity: 'P1',
      title: '2.º seller sorteia rifa da live alheia',
      actor: 'seller2 JWT',
      pre: 'raffle da live A',
      repro: 'rpc batata_draw_live_raffle_winners JWT seller2',
      expected: 'not_allowed',
      obtained: drawS2.map ?? drawS2.brief,
    );
  } else {
    c.block('RTX-X6-draw-foreign', 'X6', 'draw foreign recusado', drawS2.brief);
  }
}

Future<void> runX7(
  Rtx c,
  String liveA,
  String? itemA1,
  String liveS2,
  String? itemS2,
) async {
  final s2itemA = await c.insertLiveOnlyItem(
    liveId: liveA,
    qty: 1,
    ref: 'XEVIL',
    jwt: c.seller2Jwt,
  );
  c.note('x7.s2.insert-item', 'seller2 INSERT item na live A', s2itemA, lens: 'X7');
  if (s2itemA != null) {
    c.hold(
      id: 'RTX-X7-s2-insert-item-foreign-live',
      lens: 'X7',
      severity: 'P0',
      title: '2.º seller adiciona artigo na live de outro',
      actor: 'seller2 JWT',
      pre: 'live A do seller1',
      repro: 'POST live_items live_id=<A> JWT seller2',
      expected: 'live_item_not_authorized / RLS',
      obtained: s2itemA,
    );
  } else {
    c.block('RTX-X7-s2-insert-item-foreign-live', 'X7',
        'INSERT item live alheia recusado', 'no id');
  }

  if (itemA1 != null) {
    final s2patch = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemA1',
      jwt: c.seller2Jwt,
      body: {'quantity': 999},
    );
    c.note('x7.s2.patch-item', 'seller2 PATCH qty item A', s2patch.brief,
        lens: 'X7');
    if (s2patch.ok) {
      c.hold(
        id: 'RTX-X7-s2-patch-item-qty',
        lens: 'X7',
        severity: 'P0',
        title: '2.º seller altera stock do artigo live alheio',
        actor: 'seller2 JWT',
        pre: 'item A1',
        repro: 'PATCH live_items.quantity JWT seller2',
        expected: 'RLS recusa',
        obtained: s2patch.brief,
      );
    } else {
      c.block('RTX-X7-s2-patch-item-qty', 'X7', 'PATCH item alheio recusado',
          s2patch.brief);
    }

    final s2acc = await c.insertReservation(
      liveId: liveA,
      liveItemId: itemA1,
      buyer: c.buyerId,
      jwt: c.seller2Jwt,
    );
    c.note('x7.s2.insert-res', 'seller2 INSERT reserva na live A', s2acc.brief,
        lens: 'X7');
    if (s2acc.ok) {
      c.hold(
        id: 'RTX-X7-s2-insert-fb-foreign',
        lens: 'X7',
        severity: 'P0',
        title: '2.º seller cria facebook_manual na live alheia',
        actor: 'seller2 JWT',
        pre: 'não é dono nem staff',
        repro: 'POST live_reservation_requests JWT seller2 live=<A>',
        expected: 'RLS recusa',
        obtained: s2acc.map,
      );
    } else {
      c.block('RTX-X7-s2-insert-fb-foreign', 'X7',
          'seller2 INSERT reserva alheia recusado', s2acc.brief);
    }
  }

  final ownS2 = await c.insertReservation(
    liveId: liveS2,
    liveItemId: itemS2,
    seller: c.seller2Id,
    buyer: c.buyerId,
    jwt: c.seller2Jwt,
  );
  if (ownS2.ok && ownS2.firstId != null) {
    c.createdReqIds.add(ownS2.firstId!);
    final hijack = await c.processReservation(ownS2.firstId!, 'accept',
        jwt: c.sellerJwt);
    c.note('x7.s1.accept-s2', 'seller1 accept reserva seller2', hijack.brief,
        lens: 'X7');
    if (hijack.rpcOk) {
      c.hold(
        id: 'RTX-X7-s1-accept-s2-res',
        lens: 'X7',
        severity: 'P0',
        title: 'seller1 processa reserva da live do seller2',
        actor: 'seller JWT',
        pre: 'reserva seller2',
        repro: 'rpc accept JWT seller1 p_request_id=<S2>',
        expected: 'not_allowed',
        obtained: hijack.map ?? hijack.brief,
      );
    } else {
      c.block('RTX-X7-s1-accept-s2-res', 'X7',
          'seller1 accept reserva seller2 recusado', hijack.brief);
    }
  }
}

Future<void> runX8(
  Rtx c,
  String liveA,
  String? itemA1,
  String? itemMkt,
  String? pidMkt,
) async {
  if (itemMkt != null && pidMkt != null) {
    final fbM = await c.insertReservation(
      liveId: liveA,
      liveItemId: itemMkt,
      buyer: c.buyerId,
      jwt: c.sellerJwt,
    );
    if (fbM.ok && fbM.firstId != null) {
      c.createdReqIds.add(fbM.firstId!);
      await c.processReservation(fbM.firstId!, 'accept');
      final wB = await c.wallets();
      final conv = await c.processReservation(fbM.firstId!, 'convert');
      final item = await c.itemRow(itemMkt);
      final prod = await c.productRow(pidMkt);
      final orders = await c.ordersForItem(itemMkt);
      final wA = await c.wallets();
      c.note('x8.mkt.convert', 'convert facebook_manual em SKU marketplace', {
        'rpc': conv.brief,
        'item': item,
        'product': prod,
        'orders': orders,
        'wdelta': {'seller': (wA['seller'] ?? 0) - (wB['seller'] ?? 0)},
      }, lens: 'X8');

      final phantom = await c.insertOrder(
        productId: pidMkt,
        jwt: c.buyerJwt,
        status: 'pago',
        liveItemId: itemMkt,
        liveId: liveA,
      );
      c.note('x8.phantom-order', 'buyer INSERT order pago após convert FB',
          phantom.brief, lens: 'X8');
      if (phantom.ok) {
        final oid = phantom.firstId;
        final orow = oid == null ? null : await c.orderRow(oid);
        final pi = orow?['stripe_payment_intent_id']?.toString() ?? '';
        final paid = numOf(orow?['amount_paid_cents']) ?? 0;
        if (orow?['status'] == 'pago' && (pi.isEmpty || pi == 'null') && paid <= 0) {
          c.hold(
            id: 'RTX-X8-phantom-pago-after-fb-convert',
            lens: 'X8',
            severity: 'P0',
            title: 'após convert FB, INSERT order status=pago sem PI',
            actor: 'buyer JWT',
            pre: 'SKU convertido facebook_manual; zero Stripe',
            repro: 'POST orders status=pago após convert',
            expected: 'recusa / status não pago sem captura',
            obtained: orow,
          );
        } else {
          c.note('x8.phantom.row', 'order insert result', orow, lens: 'X8');
        }
      } else {
        c.block('RTX-X8-phantom-pago', 'X8', 'INSERT pago após convert recusado',
            phantom.brief);
      }

      if (prod != null &&
          prod['list_on_marketplace'] == true &&
          prod['is_sold'] != true) {
        c.hold(
          id: 'RTX-X8-mkt-still-listed-after-fb-convert',
          lens: 'X8',
          severity: 'P1',
          title: 'SKU marketplace continua listado após convert facebook_manual',
          actor: 'seller JWT convert',
          pre: 'product qty=1 convertido no directo sem PI',
          repro: 'convert facebook_manual → GET products',
          expected: 'is_sold ou qty 0 / unlist se o convert consome stock',
          obtained: prod,
        );
      } else if (prod != null) {
        c.block('RTX-X8-mkt-listed', 'X8', 'produto unlisted ou sold após convert',
            prod);
      }
    }
  }

  final hm = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    source: 'helper_manual',
    jwt: c.helperJwt ?? c.sellerJwt,
  );
  c.note('x8.helper-manual.insert', 'helper_manual INSERT', hm.brief, lens: 'X8');
  if (hm.ok && hm.firstId != null) {
    c.createdReqIds.add(hm.firstId!);
    await c.processReservation(hm.firstId!, 'accept', jwt: c.sellerJwt);
    final conv = await c.processReservation(hm.firstId!, 'convert');
    final row = await c.reqRow(hm.firstId!);
    if (conv.rpcOk && row?['status'] == 'converted') {
      c.hold(
        id: 'RTX-X8-helper-manual-convert-no-pi',
        lens: 'X8',
        severity: 'P1',
        title: 'convert helper_manual sem encomenda paga',
        actor: 'seller JWT',
        pre: 'source=helper_manual accepted; zero PI',
        repro: 'rpc convert source=helper_manual',
        expected:
            'convert_requires_paid_order ou convert sem efeito de caixa/stock catálogo',
        obtained: {'rpc': conv.map, 'row': row},
      );
    } else {
      c.block('RTX-X8-helper-manual-convert-no-pi', 'X8',
          'helper_manual convert recusado', conv.brief);
    }
  }

  final spoofReq = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyer2Id,
    jwt: c.sellerJwt,
  );
  if (spoofReq.ok && spoofReq.firstId != null) {
    c.createdReqIds.add(spoofReq.firstId!);
    final acc = await c.processReservation(
      spoofReq.firstId!,
      'accept',
      processedBy: c.buyerId,
    );
    final row = await c.reqRow(spoofReq.firstId!);
    c.note('x8.processed-by', 'p_processed_by = buyer', {
      'rpc': acc.brief,
      'processed_by': row?['processed_by_user_id'],
    }, lens: 'X8');
    if (row?['processed_by_user_id'] == c.buyerId) {
      c.hold(
        id: 'RTX-X8-processed-by-spoof',
        lens: 'X8',
        severity: 'P3',
        title: 'p_processed_by cliente grava UUID alheio',
        actor: 'seller JWT',
        pre: 'accept facebook_manual',
        repro: 'rpc accept p_processed_by=<buyer>',
        expected: 'auth.uid() autoritativo',
        obtained: row,
      );
    } else {
      c.block('RTX-X8-processed-by-spoof', 'X8',
          'processed_by forçado a auth.uid() ou ignorado', row);
    }
  }
}
