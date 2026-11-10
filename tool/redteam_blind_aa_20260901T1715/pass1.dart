/// REDTEAM_BLIND_AA_LIVE_POS_X_v1 — pass1
/// Variantes NOVAS pós X+VWX. Staging only. Sem produção. Sem Fase 4. Sem fixes.
/// dart run tool/redteam_blind_aa_20260901T1715/pass1.dart
import 'dart:io';

import '_rtaa.dart';

Future<void> main() async {
  final c = Rtaa.fromEnv(loadEnv());
  try {
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
  if (liveA == null || liveB == null || liveS2 == null) {
    throw StateError('fixture lives failed');
  }

  final itemA1 = await c.insertLiveOnlyItem(
      liveId: liveA, qty: 5, ref: 'AA1', jwt: c.sellerJwt);
  final itemA2 = await c.insertLiveOnlyItem(
      liveId: liveA, qty: 1, ref: 'AA2', jwt: c.sellerJwt);
  final itemA3 = await c.insertLiveOnlyItem(
      liveId: liveA, qty: 1, ref: 'AA3', jwt: c.sellerJwt);
  final itemB1 = await c.insertLiveOnlyItem(
      liveId: liveB, qty: 2, ref: 'AB1', jwt: c.sellerJwt);
  final itemS2 = await c.insertLiveOnlyItem(
      liveId: liveS2, qty: 2, ref: 'AS2', jwt: c.seller2Jwt);
  final pidMkt = await c.createProduct(qty: 1, title: '$prefix-mkt');
  final itemMkt = pidMkt == null
      ? null
      : await c.insertMarketItem(
          liveId: liveA, productId: pidMkt, ref: 'AM1', jwt: c.sellerJwt);

  c.note('fix.items', 'items', {
    'A1': itemA1,
    'A2': itemA2,
    'A3': itemA3,
    'B1': itemB1,
    'S2': itemS2,
    'mkt': itemMkt,
    'pid': pidMkt,
  });

  await staffSetup(c);
  await runAa1(c, liveA, itemA1, itemA2, itemA3, pidMkt, itemMkt);
  await runAa2(c, liveA, itemA1, liveS2, itemS2);
  await runAa3(c, liveA, itemA2, itemA3, pidMkt);
  await runAa4(c, liveA, liveB, liveS2, itemA3, itemB1, itemS2);
  await runAa5(c, liveA, liveDraft, liveS2);
  await runAa6(c, liveA, itemA1);
  await runAa7(c, liveA, itemA1, liveS2, itemS2);
  await runAa8(c, liveA, itemA1, pidMkt, itemMkt, w0);

  final w1 = await c.wallets();
  c.note('fix.w1', 'wallets after', {'before': w0, 'after': w1});

  } finally {
    await c.dumpAll();
    await c.endLives();
    stdout.writeln(
        'DONE findings=${c.findings.length} blocked=${c.blocked.length} '
        'lenses=${c.lensesHit.toList()..sort()}');
  }
}

Future<void> staffSetup(Rtaa c) async {
  final hid = await c.inviteHelper(
    helperUserId: c.helperId!,
    helperEmail: '${prefix.toLowerCase()}-h1@fleaber.test',
  );
  if (hid != null) {
    await c.acceptInvite(hid, jwt: c.helperJwt);
    final act = await c.activateHelper(hid);
    c.note('staff.activate', 'seller activa helper', act.brief, lens: 'AA2');
  }
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
    await c.activateHelper(viewHid);
  }
  c.note('staff.rows', 'helpers', {
    'h1': hid == null ? null : await c.helperRow(hid),
    'hv': viewHid == null ? null : await c.helperRow(viewHid),
  }, lens: 'AA2');
}

/// AA1 — facebook/manual: caminhos que NÃO são o RPC convert sem PI exact.
Future<void> runAa1(
  Rtaa c,
  String liveA,
  String? itemA1,
  String? itemA2,
  String? itemA3,
  String? pidMkt,
  String? itemMkt,
) async {
  if (itemA1 == null || itemA2 == null) return;

  // Baseline fechado: RPC convert facebook_manual sem PI — documentar, não parar.
  final fbRpc = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  final fbRpcId = fbRpc.firstId;
  if (fbRpcId != null) {
    c.createdReqIds.add(fbRpcId);
    final acc = await c.processReservation(fbRpcId, 'accept');
    final conv = await c.processReservation(fbRpcId, 'convert');
    c.note('aa1.rpc.convert.nopi', 'RPC convert facebook_manual sem PI', {
      'insert': fbRpc.brief,
      'accept': acc.brief,
      'convert': conv.brief,
      'err': conv.rpcError,
    }, lens: 'AA1');
    if (conv.rpcOk) {
      c.hold(
        id: 'RTAA-AA1-rpc-convert-nopi',
        lens: 'AA1',
        severity: 'P1',
        title: 'RPC convert facebook_manual ainda passa sem order paga',
        actor: 'seller JWT',
        pre: 'facebook_manual accepted; zero PI',
        repro: 'rpc batata_process_live_reservation_request action=convert',
        expected: 'convert_requires_paid_order',
        obtained: conv.brief,
      );
    } else {
      c.block('RTAA-AA1-rpc-convert-nopi', 'AA1',
          'RPC convert sem PI recusado (fecho X)', conv.brief);
    }
  }

  // NOVO: INSERT directo status=converted (não passa pelo RPC).
  final insConv = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    status: 'converted',
    qty: 1,
    jwt: c.sellerJwt,
  );
  final insConvId = insConv.firstId;
  if (insConvId != null) c.createdReqIds.add(insConvId);
  final insRow = insConvId == null ? null : await c.reqRow(insConvId);
  final itemAfterIns = await c.itemRow(itemA1);
  final stockAfterIns = await c.stock(itemA1);
  c.note('aa1.insert.converted', 'INSERT facebook_manual status=converted', {
    'hit': insConv.brief,
    'row': insRow,
    'item': itemAfterIns,
    'stock': stockAfterIns.brief,
  }, lens: 'AA1');
  if (insConv.ok && (insRow?['status']?.toString() == 'converted')) {
    c.hold(
      id: 'RTAA-AA1-insert-converted',
      lens: 'AA1',
      severity: 'P1',
      title: 'seller INSERT facebook_manual já converted — fura convert_requires_paid_order',
      actor: 'seller JWT',
      pre: 'live_only qty=5; zero PI; zero order',
      repro: 'POST live_reservation_requests source=facebook_manual status=converted',
      expected: 'pending ou 403; converted só via RPC com order paga',
      obtained: {
        'status': insRow?['status'],
        'qty': insRow?['requested_qty'],
        'stock': stockAfterIns.brief,
        'item_status': itemAfterIns?['status'],
      },
    );
  } else {
    c.block('RTAA-AA1-insert-converted', 'AA1',
        'INSERT converted recusado', insConv.brief);
  }

  // NOVO: pending → PATCH converted (bypass RPC).
  final fbPend = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyer2Id,
    jwt: c.sellerJwt,
  );
  final pendId = fbPend.firstId;
  if (pendId != null) {
    c.createdReqIds.add(pendId);
    final patchConv = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$pendId',
      jwt: c.sellerJwt,
      body: {'status': 'converted'},
    );
    final pRow = await c.reqRow(pendId);
    final stockP = await c.stock(itemA1);
    c.note('aa1.patch.converted', 'PATCH pending→converted', {
      'patch': patchConv.brief,
      'row': pRow,
      'stock': stockP.brief,
    }, lens: 'AA1');
    if (patchConv.ok && pRow?['status']?.toString() == 'converted') {
      c.hold(
        id: 'RTAA-AA1-patch-converted',
        lens: 'AA1',
        severity: 'P1',
        title: 'PATCH status=converted sem order paga / sem RPC convert',
        actor: 'seller JWT',
        pre: 'facebook_manual pending; zero PI',
        repro: 'PATCH live_reservation_requests.status=converted',
        expected: 'trigger recusa ou restaura pending',
        obtained: {'row': pRow, 'stock': stockP.brief},
      );
    } else {
      c.block('RTAA-AA1-patch-converted', 'AA1',
          'PATCH converted recusado', patchConv.brief);
    }
  }

  // NOVO: helper_manual INSERT converted.
  final hm = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    source: 'helper_manual',
    status: 'converted',
    jwt: c.sellerJwt,
  );
  if (hm.firstId != null) c.createdReqIds.add(hm.firstId!);
  final hmRow = hm.firstId == null ? null : await c.reqRow(hm.firstId!);
  c.note('aa1.helper-manual.converted', 'INSERT helper_manual converted', {
    'hit': hm.brief,
    'row': hmRow,
  }, lens: 'AA1');
  if (hm.ok && hmRow?['status'] == 'converted') {
    c.hold(
      id: 'RTAA-AA1-helper-manual-insert-converted',
      lens: 'AA1',
      severity: 'P1',
      title: 'helper_manual INSERT converted sem PI',
      actor: 'seller JWT',
      pre: 'zero PI',
      repro: 'POST live_reservation_requests source=helper_manual status=converted',
      expected: 'não converted sem order paga',
      obtained: hmRow,
    );
  } else {
    c.block('RTAA-AA1-helper-manual-insert-converted', 'AA1',
        'helper_manual INSERT converted recusado', hm.brief);
  }

  // NOVO: JWT INSERT order "pago" + PI fake → RPC convert.
  if (pidMkt != null && itemMkt != null) {
    final fakeOrd = await c.insertOrder(
      productId: pidMkt,
      jwt: c.sellerJwt,
      status: 'pago',
      liveItemId: itemMkt,
      liveId: liveA,
      price: 12,
    );
    if (fakeOrd.firstId != null) c.createdOrderIds.add(fakeOrd.firstId!);
    final o1 = fakeOrd.firstId == null ? null : await c.orderRow(fakeOrd.firstId!);
    final piPatch = fakeOrd.firstId == null
        ? null
        : await c.rest(
            'PATCH',
            'orders?id=eq.${fakeOrd.firstId}',
            jwt: c.sellerJwt,
            body: {
              'status': 'pago',
              'amount_paid_cents': 1200,
              'stripe_payment_intent_id': 'pi_rtaa_fake',
            },
          );
    final o2 = fakeOrd.firstId == null ? null : await c.orderRow(fakeOrd.firstId!);
    final fbM = await c.insertReservation(
      liveId: liveA,
      liveItemId: itemMkt,
      buyer: c.buyerId,
      jwt: c.sellerJwt,
    );
    String? fbMId = fbM.firstId;
    if (fbMId != null) {
      c.createdReqIds.add(fbMId);
      await c.processReservation(fbMId, 'accept');
      final convM = await c.processReservation(fbMId, 'convert');
      c.note('aa1.fake-order.convert', 'order JWT pago + convert mkt', {
        'insert_order': fakeOrd.brief,
        'order_after_insert': o1,
        'pi_patch': piPatch?.brief,
        'order_after_patch': o2,
        'convert': convM.brief,
      }, lens: 'AA1');
      final paidLike = o2 != null &&
          (numOf(o2['amount_paid_cents']) ?? 0) > 0 &&
          '${o2['status']}'.toLowerCase().contains('pago');
      if (convM.rpcOk && (paidLike || (o1?['status'] == 'pago'))) {
        c.hold(
          id: 'RTAA-AA1-forged-paid-order-convert',
          lens: 'AA1',
          severity: 'P1',
          title: 'order JWT forjada como paga desbloqueia convert',
          actor: 'seller JWT',
          pre: 'INSERT/PATCH orders status=pago amount_paid_cents; facebook_manual',
          repro: 'POST orders pago + rpc convert',
          expected: 'money_cols zera PI/cents; convert_requires_paid_order',
          obtained: {'order': o2 ?? o1, 'convert': convM.brief},
        );
      } else {
        c.block(
            'RTAA-AA1-forged-paid-order-convert',
            'AA1',
            'order forjada não desbloqueia convert',
            {
              'order': o2 ?? o1,
              'convert': convM.brief,
            });
      }
    }
  }

  // NOVO: mark_sold em SKU marketplace sem PI (não é convert RPC).
  if (itemMkt != null && pidMkt != null) {
    final preP = await c.productRow(pidMkt);
    final mark = await c.markSold(itemMkt);
    final postP = await c.productRow(pidMkt);
    final postI = await c.itemRow(itemMkt);
    c.note('aa1.mark-sold.mkt', 'mark_sold marketplace sem PI', {
      'rpc': mark.brief,
      'pre': preP,
      'product': postP,
      'item': postI,
    }, lens: 'AA1');
    final unlisted = postP != null &&
        (postP['is_sold'] == true || postP['list_on_marketplace'] == false);
    if (mark.rpcOk && unlisted) {
      c.hold(
        id: 'RTAA-AA1-mark-sold-mkt-nopi',
        lens: 'AA1',
        severity: 'P1',
        title: 'mark_sold tira SKU do marketplace sem encomenda paga',
        actor: 'seller JWT',
        pre: 'SKU qty=1 listado; zero PI',
        repro: 'rpc batata_mark_live_item_sold',
        expected: 'mark_sold exige order paga no SKU marketplace, ou não unlist',
        obtained: {'product': postP, 'item': postI, 'rpc': mark.brief},
      );
    } else if (mark.rpcOk) {
      c.block('RTAA-AA1-mark-sold-mkt-nopi', 'AA1',
          'mark_sold ok mas SKU continua listado', postP);
    } else {
      c.block('RTAA-AA1-mark-sold-mkt-nopi', 'AA1',
          'mark_sold recusado', mark.brief);
    }
  }

  // NOVO: fleaber_live PATCH converted pelo seller.
  final fl = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA2,
    buyer: c.buyerId,
    source: 'fleaber_live',
    jwt: c.buyerJwt,
  );
  final flId = fl.firstId;
  if (flId != null) {
    c.createdReqIds.add(flId);
    final flPatch = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$flId',
      jwt: c.sellerJwt,
      body: {'status': 'converted'},
    );
    final flRow = await c.reqRow(flId);
    c.note('aa1.fleaber.patch.converted', 'fleaber_live PATCH converted', {
      'insert': fl.brief,
      'patch': flPatch.brief,
      'row': flRow,
    }, lens: 'AA1');
    if (flPatch.ok && flRow?['status'] == 'converted') {
      c.hold(
        id: 'RTAA-AA1-fleaber-patch-converted',
        lens: 'AA1',
        severity: 'P1',
        title: 'seller PATCH fleaber_live → converted sem pagamento',
        actor: 'seller JWT',
        pre: 'fleaber_live pending do buyer',
        repro: 'PATCH status=converted',
        expected: 'convert só com order paga',
        obtained: flRow,
      );
    } else {
      c.block('RTAA-AA1-fleaber-patch-converted', 'AA1',
          'fleaber_live PATCH converted recusado', flPatch.brief);
    }
  }

  // Buyer INSERT facebook_manual (não exact X1 se já fechado — probe).
  final buyerFb = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    jwt: c.buyerJwt,
  );
  c.note('aa1.buyer.insert.fb', 'buyer INSERT facebook_manual', buyerFb.brief,
      lens: 'AA1');
  if (buyerFb.ok) {
    c.hold(
      id: 'RTAA-AA1-buyer-insert-fb',
      lens: 'AA1',
      severity: 'P2',
      title: 'comprador INSERT facebook_manual na live alheia',
      actor: 'buyer JWT',
      pre: 'live seller',
      repro: 'POST live_reservation_requests source=facebook_manual',
      expected: '403',
      obtained: buyerFb.brief,
    );
  } else {
    c.block('RTAA-AA1-buyer-insert-fb', 'AA1',
        'buyer facebook_manual recusado', buyerFb.brief);
  }
}

/// AA2 — staff helper: perms, qty, convert, loja alheia.
Future<void> runAa2(
  Rtaa c,
  String liveA,
  String? itemA1,
  String liveS2,
  String? itemS2,
) async {
  if (itemA1 == null) return;

  String? hid;
  if (c.createdHelperIds.isNotEmpty) {
    hid = c.createdHelperIds.first;
  } else {
    final listH = await c.rest(
      'GET',
      'seller_helpers?helper_user_id=eq.${c.helperId}&seller_id=eq.${c.sellerId}&select=id,permissions,active,invitation_status',
      service: true,
    );
    hid = listH.map?['id']?.toString();
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
    final perms = after?['permissions'];
    final sold = perms is Map && perms['can_mark_items_sold'] == true;
    c.note('aa2.widen', 'helper PATCH permissions', {
      'patch': widen.brief,
      'perms': perms,
    }, lens: 'AA2');
    if (widen.ok && sold) {
      c.hold(
        id: 'RTAA-AA2-helper-self-widen',
        lens: 'AA2',
        severity: 'P1',
        title: 'helper atribui-se can_mark_items_sold',
        actor: 'helper JWT',
        pre: 'convite só can_manage_reservations',
        repro: 'PATCH seller_helpers.permissions',
        expected: '403 ou restore',
        obtained: after,
      );
    } else {
      c.block('RTAA-AA2-helper-self-widen', 'AA2',
          'widen bloqueado', {'patch': widen.brief, 'perms': perms});
    }

    // NOVO: helper inflate DEPOIS de widen (composição), qty 5→7 não 1→40.
    final preQty = await c.itemRow(itemA1);
    final inf = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemA1',
      jwt: c.helperJwt,
      body: {'quantity': 7},
    );
    final postQty = await c.itemRow(itemA1);
    c.note('aa2.helper.inflate', 'helper PATCH qty 5→7', {
      'pre': preQty?['quantity'],
      'patch': inf.brief,
      'post': postQty?['quantity'],
    }, lens: 'AA2');
    final q0 = numOf(preQty?['quantity']) ?? 0;
    final q1 = numOf(postQty?['quantity']) ?? 0;
    if (inf.ok && q1 > q0) {
      c.hold(
        id: 'RTAA-AA2-helper-inflate-via-widen',
        lens: 'AA2',
        severity: 'P1',
        title: 'helper aumenta qty após self-widen can_mark_items_sold',
        actor: 'helper JWT',
        pre: 'item qty=$q0',
        repro: 'PATCH seller_helpers.permissions + PATCH live_items.quantity',
        expected: 'qty_increase_not_allowed sem perm real do dono',
        obtained: {'pre': q0, 'post': q1, 'patch': inf.brief},
      );
    } else {
      c.block('RTAA-AA2-helper-inflate-via-widen', 'AA2',
          'helper inflate recusado', inf.brief);
    }
  }

  // Helper INSERT converted.
  final hIns = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    status: 'converted',
    jwt: c.helperJwt,
  );
  if (hIns.firstId != null) c.createdReqIds.add(hIns.firstId!);
  final hRow = hIns.firstId == null ? null : await c.reqRow(hIns.firstId!);
  c.note('aa2.helper.insert.converted', 'helper INSERT converted', {
    'hit': hIns.brief,
    'row': hRow,
  }, lens: 'AA2');
  if (hIns.ok && hRow?['status'] == 'converted') {
    c.hold(
      id: 'RTAA-AA2-helper-insert-converted',
      lens: 'AA2',
      severity: 'P1',
      title: 'helper INSERT facebook_manual converted sem PI',
      actor: 'helper JWT',
      pre: 'staff can_manage_reservations',
      repro: 'POST live_reservation_requests status=converted',
      expected: 'pending ou 403',
      obtained: hRow,
    );
  } else {
    c.block('RTAA-AA2-helper-insert-converted', 'AA2',
        'helper INSERT converted recusado', hIns.brief);
  }

  // Helper na loja alheia.
  if (itemS2 != null) {
    final hS2 = await c.insertReservation(
      liveId: liveS2,
      liveItemId: itemS2,
      seller: c.seller2Id,
      buyer: c.buyerId,
      jwt: c.helperJwt,
    );
    c.note('aa2.helper.loja-alheia', 'helper INSERT na live seller2',
        hS2.brief, lens: 'AA2');
    if (hS2.ok) {
      c.hold(
        id: 'RTAA-AA2-helper-foreign-shop',
        lens: 'AA2',
        severity: 'P1',
        title: 'helper da loja 1 cria reserva na live do seller2',
        actor: 'helper JWT',
        pre: 'helper só da loja seller1',
        repro: 'POST live_reservation_requests live=seller2',
        expected: '403 not_allowed',
        obtained: hS2.brief,
      );
    } else {
      c.block('RTAA-AA2-helper-foreign-shop', 'AA2',
          'helper loja alheia recusado', hS2.brief);
    }

    final hMarkS2 = await c.markSold(itemS2, jwt: c.helperJwt);
    c.note('aa2.helper.mark-s2', 'helper mark_sold item seller2',
        hMarkS2.brief, lens: 'AA2');
    if (hMarkS2.rpcOk) {
      c.hold(
        id: 'RTAA-AA2-helper-mark-sold-foreign',
        lens: 'AA2',
        severity: 'P0',
        title: 'helper marca vendido item da live alheia',
        actor: 'helper JWT',
        pre: 'item seller2',
        repro: 'rpc batata_mark_live_item_sold',
        expected: 'not_allowed',
        obtained: hMarkS2.brief,
      );
    } else {
      c.block('RTAA-AA2-helper-mark-sold-foreign', 'AA2',
          'helper mark_sold foreign recusado', hMarkS2.brief);
    }
  }

  // View-only helper convert / insert.
  final vIns = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    jwt: c.viewJwt,
  );
  c.note('aa2.view.insert', 'view-only INSERT facebook_manual', vIns.brief,
      lens: 'AA2');
  if (vIns.ok) {
    c.hold(
      id: 'RTAA-AA2-view-insert-fb',
      lens: 'AA2',
      severity: 'P1',
      title: 'helper só-ver INSERT facebook_manual',
      actor: 'view helper JWT',
      pre: 'perms só can_view_live_dashboard',
      repro: 'POST live_reservation_requests',
      expected: '403',
      obtained: vIns.brief,
    );
  } else {
    c.block('RTAA-AA2-view-insert-fb', 'AA2',
        'view-only INSERT recusado', vIns.brief);
  }
}

/// AA3 — qty / sold: dono inflate, race, live_only, Hub qty.
Future<void> runAa3(
  Rtaa c,
  String liveA,
  String? itemA2,
  String? itemA3,
  String? pidMkt,
) async {
  if (itemA3 == null) return;

  // Dono inflate (não é helper 1→40). qty 1→3.
  final pre = await c.itemRow(itemA3);
  final ownInf = await c.rest(
    'PATCH',
    'live_items?id=eq.$itemA3',
    jwt: c.sellerJwt,
    body: {'quantity': 3},
  );
  final post = await c.itemRow(itemA3);
  c.note('aa3.owner.inflate', 'dono PATCH qty 1→3', {
    'pre': pre?['quantity'],
    'patch': ownInf.brief,
    'post': post?['quantity'],
  }, lens: 'AA3');
  // Dono restock é produto; não é finding sozinho. Composição abaixo.

  // INSERT qty=0 live_only + Hub.
  final z = await c.insertLiveOnlyItem(
    liveId: liveA, qty: 0, ref: 'AZ0', jwt: c.sellerJwt,
  );
  if (z != null) {
    final hubZ = await c.hubItem(z);
    final rowZ = await c.itemRow(z);
    c.note('aa3.qty0', 'INSERT live_only qty=0', {
      'id': z,
      'row': rowZ,
      'hub': hubZ,
    }, lens: 'AA3');
    if (rowZ != null && (numOf(rowZ['quantity']) ?? -1) == 0 && hubZ != null) {
      c.hold(
        id: 'RTAA-AA3-hub-qty0',
        lens: 'AA3',
        severity: 'P2',
        title: 'Hub público ainda mostra live_item qty=0',
        actor: 'seller JWT + view hub_live_items_public',
        pre: 'INSERT quantity=0',
        repro: 'POST live_items qty=0; GET hub_live_items_public',
        expected: 'INSERT recusado ou view exclui qty<=0',
        obtained: {'row': rowZ, 'hub': hubZ},
      );
    } else if (hubZ == null && rowZ != null) {
      c.block('RTAA-AA3-hub-qty0', 'AA3', 'Hub esconde qty=0 (fecho V)',
          rowZ);
    } else {
      c.block('RTAA-AA3-hub-qty0', 'AA3', 'INSERT qty=0 recusado ou nulo', z);
    }
  }

  // Negative qty.
  final neg = await c.rest(
    'PATCH',
    'live_items?id=eq.$itemA3',
    jwt: c.sellerJwt,
    body: {'quantity': -1},
  );
  final negRow = await c.itemRow(itemA3);
  c.note('aa3.neg', 'PATCH qty=-1',
      {'patch': neg.brief, 'qty': negRow?['quantity']}, lens: 'AA3');
  if (neg.ok && (numOf(negRow?['quantity']) ?? 0) < 0) {
    c.hold(
      id: 'RTAA-AA3-neg-qty',
      lens: 'AA3',
      severity: 'P1',
      title: 'live_item quantity negativa',
      actor: 'seller JWT',
      pre: 'item A3',
      repro: 'PATCH live_items.quantity=-1',
      expected: 'CHECK / trigger',
      obtained: negRow,
    );
  } else {
    c.block('RTAA-AA3-neg-qty', 'AA3', 'qty negativa recusada', neg.brief);
  }

  // Race dois PATCH converted em qty=1 itemA2 (se ainda qty 1).
  if (itemA2 != null) {
    final r1 = await c.insertReservation(
      liveId: liveA,
      liveItemId: itemA2,
      buyer: c.buyerId,
      jwt: c.sellerJwt,
    );
    final r2 = await c.insertReservation(
      liveId: liveA,
      liveItemId: itemA2,
      buyer: c.buyer2Id,
      jwt: c.sellerJwt,
    );
    if (r1.firstId != null && r2.firstId != null) {
      c.createdReqIds.addAll([r1.firstId!, r2.firstId!]);
      final raced = await parallel([
        c.rest('PATCH', 'live_reservation_requests?id=eq.${r1.firstId}',
            jwt: c.sellerJwt, body: {'status': 'converted'}),
        c.rest('PATCH', 'live_reservation_requests?id=eq.${r2.firstId}',
            jwt: c.sellerJwt, body: {'status': 'converted'}),
      ]);
      final row1 = await c.reqRow(r1.firstId!);
      final row2 = await c.reqRow(r2.firstId!);
      final nConv = [
        row1?['status'],
        row2?['status'],
      ].where((s) => s == 'converted').length;
      c.note('aa3.race.patch', 'race PATCH converted qty=1', {
        'a': raced[0].brief,
        'b': raced[1].brief,
        'row1': row1?['status'],
        'row2': row2?['status'],
        'nConv': nConv,
      }, lens: 'AA3');
      if (nConv >= 2) {
        c.hold(
          id: 'RTAA-AA3-race-two-converted',
          lens: 'AA3',
          severity: 'P1',
          title: 'dois converted permanentes em item qty=1 via PATCH paralelo',
          actor: 'seller JWT ×2',
          pre: 'live_only qty=1; duas facebook_manual pending',
          repro: 'PATCH converted em paralelo',
          expected: 'um converted, outro qty_exceeds_stock',
          obtained: {'nConv': nConv, 's1': row1?['status'], 's2': row2?['status']},
        );
      } else {
        c.block('RTAA-AA3-race-two-converted', 'AA3',
            'race não deixou 2 converted', nConv);
      }
    }
  }

  // Product qty inflate com hold — se pid ainda existir.
  if (pidMkt != null) {
    final pq = await c.rest(
      'PATCH',
      'products?id=eq.$pidMkt',
      jwt: c.sellerJwt,
      body: {'quantity': 40},
    );
    final prow = await c.productRow(pidMkt);
    c.note('aa3.product.inflate', 'dono PATCH product qty→40', {
      'patch': pq.brief,
      'row': prow,
    }, lens: 'AA3');
  }
}

/// AA4 — cross-live / cross-seller sabotage.
Future<void> runAa4(
  Rtaa c,
  String liveA,
  String liveB,
  String liveS2,
  String? itemA3,
  String? itemB1,
  String? itemS2,
) async {
  // Mover live_item sem reservas activas para live B (mesmo seller).
  if (itemA3 != null) {
    final mv = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemA3',
      jwt: c.sellerJwt,
      body: {'live_id': liveB},
    );
    final after = await c.itemRow(itemA3);
    c.note('aa4.move.same-seller', 'move item A3 liveA→liveB', {
      'patch': mv.brief,
      'live_id': after?['live_id'],
    }, lens: 'AA4');
    if (mv.ok && after?['live_id'] == liveB) {
      c.hold(
        id: 'RTAA-AA4-move-item-across-lives',
        lens: 'AA4',
        severity: 'P2',
        title: 'live_item muda de live sem reservas (immutability só com fila)',
        actor: 'seller JWT',
        pre: 'item sem reservas activas',
        repro: 'PATCH live_items.live_id',
        expected: 'live_id imutável sempre, ou só draft',
        obtained: after,
      );
    } else {
      c.block('RTAA-AA4-move-item-across-lives', 'AA4',
          'move live_id recusado', mv.brief);
    }
  }

  // Mover item do seller1 para live do seller2.
  if (itemB1 != null) {
    final hij = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemB1',
      jwt: c.sellerJwt,
      body: {'live_id': liveS2},
    );
    final after = await c.itemRow(itemB1);
    c.note('aa4.move.cross-seller', 'move item seller1 → live seller2', {
      'patch': hij.brief,
      'live_id': after?['live_id'],
    }, lens: 'AA4');
    if (hij.ok && after?['live_id'] == liveS2) {
      c.hold(
        id: 'RTAA-AA4-plant-item-foreign-live',
        lens: 'AA4',
        severity: 'P1',
        title: 'seller planta live_item na live de outro vendedor',
        actor: 'seller JWT',
        pre: 'item na live B; live S2 é do seller2',
        repro: 'PATCH live_items.live_id=<live seller2>',
        expected: 'live_item_not_authorized / mismatch',
        obtained: after,
      );
    } else {
      c.block('RTAA-AA4-plant-item-foreign-live', 'AA4',
          'plantar na live alheia recusado', hij.brief);
    }
  }

  // Seller2 PATCH live seller1 ended.
  final kill = await c.rest(
    'PATCH',
    'lives?id=eq.$liveA',
    jwt: c.seller2Jwt,
    body: {'status': 'ended', 'is_active': false},
  );
  c.note('aa4.s2.end.liveA', 'seller2 termina live A', kill.brief, lens: 'AA4');
  if (kill.ok) {
    c.hold(
      id: 'RTAA-AA4-end-foreign-live',
      lens: 'AA4',
      severity: 'P0',
      title: '2.º seller termina live alheia',
      actor: 'seller2 JWT',
      pre: 'live A do seller1',
      repro: 'PATCH lives status=ended',
      expected: '403',
      obtained: kill.brief,
    );
  } else {
    c.block('RTAA-AA4-end-foreign-live', 'AA4',
        'end live alheia recusado', kill.brief);
  }

  // Seller2 INSERT item na live A.
  final plant = await c.insertLiveOnlyItem(
    liveId: liveA, qty: 1, ref: 'HACK', jwt: c.seller2Jwt,
  );
  c.note('aa4.s2.insert.itemA', 'seller2 INSERT item na live A', plant,
      lens: 'AA4');
  if (plant != null) {
    c.hold(
      id: 'RTAA-AA4-insert-item-foreign-live',
      lens: 'AA4',
      severity: 'P1',
      title: '2.º seller cria live_item na live alheia',
      actor: 'seller2 JWT',
      pre: 'live A seller1',
      repro: 'POST live_items live_id=A',
      expected: '403',
      obtained: plant,
    );
  } else {
    c.block('RTAA-AA4-insert-item-foreign-live', 'AA4',
        'INSERT item live alheia recusado', 'null');
  }

  // PATCH reservation live_item_id para item de outra live (não exact mismatch INSERT).
  if (itemS2 != null && itemB1 != null) {
    final rr = await c.insertReservation(
      liveId: liveA,
      liveItemId: itemB1,
      buyer: c.buyerId,
      jwt: c.sellerJwt,
    );
    if (rr.firstId != null) {
      c.createdReqIds.add(rr.firstId!);
      final rebind = await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.${rr.firstId}',
        jwt: c.sellerJwt,
        body: {'live_item_id': itemS2, 'live_id': liveS2},
      );
      final row = await c.reqRow(rr.firstId!);
      c.note('aa4.rebind.item', 'PATCH reserva para item seller2', {
        'patch': rebind.brief,
        'row': row,
      }, lens: 'AA4');
      if (rebind.ok && row?['live_item_id'] == itemS2) {
        c.hold(
          id: 'RTAA-AA4-rebind-reservation-foreign-item',
          lens: 'AA4',
          severity: 'P1',
          title: 'reserva re-ligada a live_item de outro vendedor',
          actor: 'seller JWT',
          pre: 'facebook_manual no item B1',
          repro: 'PATCH live_item_id + live_id para seller2',
          expected: 'live_item_live_mismatch / not_authorized',
          obtained: row,
        );
      } else {
        c.block('RTAA-AA4-rebind-reservation-foreign-item', 'AA4',
            'rebind foreign recusado', rebind.brief);
      }
    }
  }
}

/// AA5 — Mux / publish: token alheio, draft, stream key.
Future<void> runAa5(
  Rtaa c,
  String liveA,
  String? liveDraft,
  String liveS2,
) async {
  // Stream key leak via REST.
  final buyerLive = await c.rest(
    'GET',
    'lives?id=eq.$liveA&select=id,status,mux_stream_key,stream_key,mux_playback_id,seller_id',
    jwt: c.buyerJwt,
  );
  final anonLive = await c.rest(
    'GET',
    'lives?id=eq.$liveA&select=id,mux_stream_key,stream_key',
  );
  final mapB = buyerLive.map;
  final sk = (mapB?['mux_stream_key'] ?? mapB?['stream_key'])?.toString() ?? '';
  c.note('aa5.stream-key', 'GET lives stream_key', {
    'buyer': buyerLive.brief,
    'anon': anonLive.brief,
    'has_key': sk.isNotEmpty,
  }, lens: 'AA5');
  if (sk.isNotEmpty) {
    c.hold(
      id: 'RTAA-AA5-stream-key-leak',
      lens: 'AA5',
      severity: 'P1',
      title: 'comprador lê mux_stream_key da live',
      actor: 'buyer JWT',
      pre: 'live A activa',
      repro: 'GET lives?select=mux_stream_key',
      expected: 'coluna omitida / null para não-dono',
      obtained: {'status': buyerLive.status, 'key_len': sk.length},
    );
  } else {
    c.block('RTAA-AA5-stream-key-leak', 'AA5',
        'stream_key não vaza no GET buyer/anon', buyerLive.brief);
  }

  // Token alheio.
  final tokS2 = await c.edge('livekit-mux-publish', {
    'step': 'token',
    'live_id': liveA,
  }, jwt: c.seller2Jwt);
  c.note('aa5.token.s2', 'seller2 token live A', tokS2.brief, lens: 'AA5');
  if (tokS2.ok && (tokS2.map?['token'] != null || tokS2.body.contains('eyJ'))) {
    c.hold(
      id: 'RTAA-AA5-token-foreign',
      lens: 'AA5',
      severity: 'P1',
      title: '2.º seller obtém LiveKit token da live alheia',
      actor: 'seller2 JWT',
      pre: 'live A seller1',
      repro: 'POST livekit-mux-publish step=token live_id=A',
      expected: '403 Sem permissão',
      obtained: tokS2.brief,
    );
  } else {
    c.block('RTAA-AA5-token-foreign', 'AA5',
        'token alheio recusado', tokS2.brief);
  }

  final tokH = await c.edge('livekit-mux-publish', {
    'step': 'token',
    'live_id': liveA,
  }, jwt: c.helperJwt);
  c.note('aa5.token.helper', 'helper token live A', tokH.brief, lens: 'AA5');
  if (tokH.ok) {
    c.hold(
      id: 'RTAA-AA5-token-helper',
      lens: 'AA5',
      severity: 'P2',
      title: 'helper obtém token de publish da live do dono',
      actor: 'helper JWT',
      pre: 'staff can_manage_reservations',
      repro: 'POST livekit-mux-publish step=token',
      expected: '403 só dono (ou staff can_publish se existir)',
      obtained: tokH.brief,
    );
  } else {
    c.block('RTAA-AA5-token-helper', 'AA5', 'helper token recusado', tokH.brief);
  }

  final tokB = await c.edge('livekit-mux-publish', {
    'step': 'token',
    'live_id': liveA,
  }, jwt: c.buyerJwt);
  c.note('aa5.token.buyer', 'buyer token live A', tokB.brief, lens: 'AA5');
  if (tokB.ok) {
    c.hold(
      id: 'RTAA-AA5-token-buyer',
      lens: 'AA5',
      severity: 'P1',
      title: 'comprador obtém token de publish',
      actor: 'buyer JWT',
      pre: 'live A',
      repro: 'POST livekit-mux-publish step=token',
      expected: '403',
      obtained: tokB.brief,
    );
  } else {
    c.block('RTAA-AA5-token-buyer', 'AA5', 'buyer token recusado', tokB.brief);
  }

  // complete-mux-live foreign (não stop_egress exact).
  final cmp = await c.edge('complete-mux-live', {
    'live_id': liveA,
  }, jwt: c.seller2Jwt);
  c.note('aa5.complete.s2', 'seller2 complete-mux-live A', cmp.brief,
      lens: 'AA5');
  if (cmp.ok) {
    c.hold(
      id: 'RTAA-AA5-complete-foreign',
      lens: 'AA5',
      severity: 'P1',
      title: '2.º seller completa/termina Mux da live alheia',
      actor: 'seller2 JWT',
      pre: 'live A',
      repro: 'POST complete-mux-live live_id=A',
      expected: '403',
      obtained: cmp.brief,
    );
  } else {
    c.block('RTAA-AA5-complete-foreign', 'AA5',
        'complete-mux foreign recusado', cmp.brief);
  }

  // Draft token.
  if (liveDraft != null) {
    final tokD = await c.edge('livekit-mux-publish', {
      'step': 'token',
      'live_id': liveDraft,
    }, jwt: c.sellerJwt);
    c.note('aa5.token.draft', 'dono token live draft', tokD.brief, lens: 'AA5');
    // Dono no próprio draft é esperado; seller2 no draft alheio:
    final tokD2 = await c.edge('livekit-mux-publish', {
      'step': 'token',
      'live_id': liveDraft,
    }, jwt: c.seller2Jwt);
    c.note('aa5.token.draft.s2', 'seller2 token draft A', tokD2.brief,
        lens: 'AA5');
    if (tokD2.ok) {
      c.hold(
        id: 'RTAA-AA5-draft-token-foreign',
        lens: 'AA5',
        severity: 'P1',
        title: '2.º seller token no draft alheio',
        actor: 'seller2 JWT',
        pre: 'draft seller1',
        repro: 'POST livekit-mux-publish live_id=draft',
        expected: '403',
        obtained: tokD2.brief,
      );
    } else {
      c.block('RTAA-AA5-draft-token-foreign', 'AA5',
          'draft token foreign recusado', tokD2.brief);
    }
  }

  // create-mux-live buyer / helper.
  final muxB = await c.edge('create-mux-live', {'title': '$prefix buyer mux'},
      jwt: c.buyerJwt);
  c.note('aa5.create.buyer', 'buyer create-mux-live', muxB.brief, lens: 'AA5');
  if (muxB.ok) {
    c.hold(
      id: 'RTAA-AA5-create-mux-buyer',
      lens: 'AA5',
      severity: 'P1',
      title: 'comprador cria stream Mux (custo)',
      actor: 'buyer JWT',
      pre: 'conta buyer',
      repro: 'POST create-mux-live',
      expected: '403 Apenas vendedor',
      obtained: muxB.brief,
    );
  } else {
    c.block('RTAA-AA5-create-mux-buyer', 'AA5',
        'buyer create-mux recusado', muxB.brief);
  }

  // egress com stream_key alheio no próprio live (não stop_egress exact).
  final ownTok = await c.edge('livekit-mux-publish', {
    'step': 'egress',
    'live_id': liveS2,
    'stream_key': sk.isNotEmpty ? sk : 'stolen_key',
  }, jwt: c.seller2Jwt);
  c.note('aa5.egress.stolen-key', 'seller2 egress com key de A', ownTok.brief,
      lens: 'AA5');
  // 403/404/5xx sem prova de hijack Mux = block. ok com egress_id = finding.
  if (ownTok.ok && (ownTok.map?['egress_id'] != null)) {
    c.hold(
      id: 'RTAA-AA5-egress-stolen-stream-key',
      lens: 'AA5',
      severity: 'P1',
      title: 'egress LiveKit para stream_key de outra live',
      actor: 'seller2 JWT',
      pre: 'live S2 própria; stream_key lido de live A',
      repro: 'POST livekit-mux-publish step=egress stream_key=<A>',
      expected: 'usar só a key da live autenticada',
      obtained: ownTok.brief,
    );
  } else {
    c.block('RTAA-AA5-egress-stolen-stream-key', 'AA5',
        'egress stolen key não comprovado', ownTok.brief);
  }

  // livekit-egress-cleanup sem secret.
  final clean = await c.edge('livekit-egress-cleanup', {'live_id': liveA},
      jwt: c.buyerJwt);
  c.note('aa5.cleanup.buyer', 'buyer egress-cleanup', clean.brief, lens: 'AA5');
  if (clean.ok) {
    c.hold(
      id: 'RTAA-AA5-cleanup-unauth',
      lens: 'AA5',
      severity: 'P1',
      title: 'buyer dispara livekit-egress-cleanup',
      actor: 'buyer JWT',
      pre: 'sem service_role / cleanup secret',
      repro: 'POST livekit-egress-cleanup',
      expected: '401 Unauthorized',
      obtained: clean.brief,
    );
  } else {
    c.block('RTAA-AA5-cleanup-unauth', 'AA5',
        'cleanup unauth recusado', clean.brief);
  }

  // resolve-mux-playback como buyer (leitura) — só finding se mutar.
  final res = await c.edge('resolve-mux-playback', {'live_id': liveA},
      jwt: c.buyerJwt);
  c.note('aa5.resolve.buyer', 'buyer resolve-mux-playback', res.brief,
      lens: 'AA5');
}

/// AA6 — rifa / share no caminho.
Future<void> runAa6(Rtaa c, String liveA, String? itemA1) async {
  final raf = await c.rpc('batata_create_live_raffle', {
    'p_live_id': liveA,
    'p_title': '$prefix rifa',
  }, jwt: c.sellerJwt);
  c.note('aa6.create', 'create raffle', raf.brief, lens: 'AA6');
  final rafMap = raf.map;
  final rafId = rafMap?['id']?.toString() ??
      rafMap?['raffle_id']?.toString() ??
      rafMap?['raffle']?.toString();

  if (!raf.ok) {
    c.skip('RTAA-AA6-raffle', 'AA6', 'create raffle falhou / skip', raf.brief);
    return;
  }

  final award = await c.rpc('batata_award_live_raffle_tickets', {
    'p_raffle_id': rafId,
    'p_delta': 50,
  }, jwt: c.buyerJwt);
  c.note('aa6.award.buyer', 'buyer award tickets', award.brief, lens: 'AA6');
  if (award.rpcOk) {
    c.hold(
      id: 'RTAA-AA6-buyer-award-tickets',
      lens: 'AA6',
      severity: 'P1',
      title: 'comprador atribui-se bilhetes de rifa',
      actor: 'buyer JWT',
      pre: 'rifa do seller',
      repro: 'rpc batata_award_live_raffle_tickets delta=50',
      expected: 'not_allowed',
      obtained: award.brief,
    );
  } else {
    c.block('RTAA-AA6-buyer-award-tickets', 'AA6',
        'buyer award recusado', award.brief);
  }

  final shareS2 = await c.rpc('batata_claim_live_raffle_share_intent', {
    'p_raffle_id': rafId,
  }, jwt: c.seller2Jwt);
  c.note('aa6.share.s2', 'seller2 claim share sem partilha', shareS2.brief,
      lens: 'AA6');

  final drawS2 = await c.rpc('batata_draw_live_raffle_winners', {
    'p_raffle_id': rafId,
  }, jwt: c.seller2Jwt);
  c.note('aa6.draw.s2', 'seller2 draw rifa alheia', drawS2.brief, lens: 'AA6');
  if (drawS2.rpcOk) {
    c.hold(
      id: 'RTAA-AA6-draw-foreign',
      lens: 'AA6',
      severity: 'P1',
      title: '2.º seller sorteia rifa alheia',
      actor: 'seller2 JWT',
      pre: 'rifa live A',
      repro: 'rpc batata_draw_live_raffle_winners',
      expected: 'not_allowed',
      obtained: drawS2.brief,
    );
  } else {
    c.block('RTAA-AA6-draw-foreign', 'AA6', 'draw foreign recusado',
        drawS2.brief);
  }

  if (itemA1 != null) {
    final prize = await c.rpc('batata_create_raffle_prize_order', {
      'p_raffle_id': rafId,
      'p_live_item_id': itemA1,
      'p_winner_id': c.seller2Id,
    }, jwt: c.seller2Jwt);
    c.note('aa6.prize.s2', 'seller2 cria prize order', prize.brief, lens: 'AA6');
    if (prize.rpcOk || prize.ok) {
      c.hold(
        id: 'RTAA-AA6-prize-order-foreign',
        lens: 'AA6',
        severity: 'P1',
        title: '2.º seller cria encomenda prémio na rifa alheia',
        actor: 'seller2 JWT',
        pre: 'rifa seller1',
        repro: 'rpc batata_create_raffle_prize_order winner=self',
        expected: 'not_allowed',
        obtained: prize.brief,
      );
    } else {
      c.block('RTAA-AA6-prize-order-foreign', 'AA6',
          'prize order foreign recusado', prize.brief);
    }
  }
}

/// AA7 — 2.º seller PATCH/accept foreign.
Future<void> runAa7(
  Rtaa c,
  String liveA,
  String? itemA1,
  String liveS2,
  String? itemS2,
) async {
  if (itemA1 == null) return;
  final fb = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  final id = fb.firstId;
  if (id == null) {
    c.skip('RTAA-AA7', 'AA7', 'insert fb falhou', fb.brief);
    return;
  }
  c.createdReqIds.add(id);

  final acc = await c.processReservation(id, 'accept', jwt: c.seller2Jwt);
  c.note('aa7.accept.s2', 'seller2 accept reserva seller1', acc.brief,
      lens: 'AA7');
  if (acc.rpcOk) {
    c.hold(
      id: 'RTAA-AA7-accept-foreign',
      lens: 'AA7',
      severity: 'P1',
      title: '2.º seller accept reserva da live alheia',
      actor: 'seller2 JWT',
      pre: 'facebook_manual pending live A',
      repro: 'rpc batata_process_live_reservation_request action=accept',
      expected: 'not_allowed',
      obtained: acc.brief,
    );
  } else {
    c.block('RTAA-AA7-accept-foreign', 'AA7',
        'accept foreign recusado', acc.brief);
  }

  final conv = await c.processReservation(id, 'convert', jwt: c.seller2Jwt);
  c.note('aa7.convert.s2', 'seller2 convert reserva seller1', conv.brief,
      lens: 'AA7');
  if (conv.rpcOk) {
    c.hold(
      id: 'RTAA-AA7-convert-foreign',
      lens: 'AA7',
      severity: 'P1',
      title: '2.º seller convert reserva alheia',
      actor: 'seller2 JWT',
      pre: 'reserva live A',
      repro: 'rpc convert JWT seller2',
      expected: 'not_allowed',
      obtained: conv.brief,
    );
  } else {
    c.block('RTAA-AA7-convert-foreign', 'AA7',
        'convert foreign recusado', conv.brief);
  }

  // Self-invite como helper na loja 1.
  final self = await c.rest('POST', 'seller_helpers', jwt: c.seller2Jwt, body: {
    'seller_id': c.sellerId,
    'helper_user_id': c.seller2Id,
    'invited_by': c.seller2Id,
    'invited_email': '${prefix.toLowerCase()}-s2@fleaber.test',
    'display_name': 's2',
    'invitation_status': 'accepted',
    'active': true,
    'permissions': {
      'can_manage_reservations': true,
      'can_mark_items_sold': true,
    },
  });
  c.note('aa7.self-staff', 'seller2 INSERT staff na loja 1', self.brief,
      lens: 'AA7');
  if (self.ok) {
    c.hold(
      id: 'RTAA-AA7-self-staff',
      lens: 'AA7',
      severity: 'P1',
      title: '2.º seller auto-convida-se staff na loja 1',
      actor: 'seller2 JWT',
      pre: 'sem convite do dono',
      repro: 'POST seller_helpers seller_id=seller1 active=true',
      expected: '403',
      obtained: self.brief,
    );
  } else {
    c.block('RTAA-AA7-self-staff', 'AA7', 'self-staff recusado', self.brief);
  }

  // PATCH live_items qty do seller1.
  final q = await c.rest(
    'PATCH',
    'live_items?id=eq.$itemA1',
    jwt: c.seller2Jwt,
    body: {'quantity': 99},
  );
  c.note('aa7.patch.qty.s2', 'seller2 PATCH qty item A', q.brief, lens: 'AA7');
  if (q.ok) {
    c.hold(
      id: 'RTAA-AA7-patch-qty-foreign',
      lens: 'AA7',
      severity: 'P1',
      title: '2.º seller altera qty do live_item alheio',
      actor: 'seller2 JWT',
      pre: 'item A1',
      repro: 'PATCH live_items.quantity=99',
      expected: '403',
      obtained: q.brief,
    );
  } else {
    c.block('RTAA-AA7-patch-qty-foreign', 'AA7',
        'PATCH qty foreign recusado', q.brief);
  }
}

/// AA8 — composição convert → order fantasma → Δwallet.
Future<void> runAa8(
  Rtaa c,
  String liveA,
  String? itemA1,
  String? pidMkt,
  String? itemMkt,
  Map<String, num> w0,
) async {
  if (itemA1 == null) return;

  // Fixture service_role: order paga qty=1; duas reservas facebook qty=1; convert ambas.
  final paid = await c.rest('POST', 'orders', service: true, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pidMkt,
    'price_total': 9.0,
    'quantity': 1,
    'status': 'pago',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
    'live_item_id': itemA1,
    'live_id': liveA,
    'amount_paid_cents': 900,
    'stripe_payment_intent_id': 'pi_rtaa_fixture_reuse',
  });
  if (paid.firstId != null) c.createdOrderIds.add(paid.firstId!);
  c.note('aa8.fixture.paid', 'service_role order paga qty=1', paid.brief,
      lens: 'AA8');

  final a = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  final b = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  final idA = a.firstId;
  final idB = b.firstId;
  HttpHit? convA;
  HttpHit? convB;
  if (idA != null) {
    c.createdReqIds.add(idA);
    await c.processReservation(idA, 'accept');
    convA = await c.processReservation(idA, 'convert');
  }
  if (idB != null) {
    c.createdReqIds.add(idB);
    await c.processReservation(idB, 'accept');
    convB = await c.processReservation(idB, 'convert');
  }
  final rowA = idA == null ? null : await c.reqRow(idA);
  final rowB = idB == null ? null : await c.reqRow(idB);
  final w1 = await c.wallets();
  final dSeller = (w1['seller'] ?? 0) - (w0['seller'] ?? 0);
  c.note('aa8.reuse.pi', 'uma order paga desbloqueia N converts', {
    'order': paid.firstId,
    'convA': convA?.brief,
    'convB': convB?.brief,
    'stA': rowA?['status'],
    'stB': rowB?['status'],
    'dSeller': dSeller,
  }, lens: 'AA8');

  final nConv = [
    rowA?['status'],
    rowB?['status'],
  ].where((s) => s == 'converted').length;
  if (nConv >= 2 && paid.ok) {
    c.hold(
      id: 'RTAA-AA8-paid-order-reuse-convert',
      lens: 'AA8',
      severity: 'P1',
      title: 'uma order paga (qty=1) desbloqueia dois convert facebook_manual',
      actor: 'seller JWT + fixture order paga',
      pre: '1 order pago cents=900 qty=1; 2 reservas facebook do mesmo buyer+item',
      repro: 'rpc convert ×2',
      expected: 'convert amarra 1:1 à order / qty paga',
      obtained: {
        'nConverted': nConv,
        'dSeller': dSeller,
        'convA': convA?.brief,
        'convB': convB?.brief,
      },
    );
  } else {
    c.block('RTAA-AA8-paid-order-reuse-convert', 'AA8',
        'reuse PI não deu 2 converted', {
      'nConv': nConv,
      'a': convA?.brief,
      'b': convB?.brief,
    });
  }

  if (dSeller > 0) {
    c.hold(
      id: 'RTAA-AA8-convert-wallet-mint',
      lens: 'AA8',
      severity: 'P0',
      title: 'convert/manual creditou carteira sem Stripe real',
      actor: 'seller JWT',
      pre: 'fixture order + convert facebook',
      repro: 'Δ wallets.balance seller',
      expected: 'Δ=0 (só webhook/capture credita)',
      obtained: {'dSeller': dSeller, 'w0': w0, 'w1': w1},
    );
  } else {
    c.block('RTAA-AA8-convert-wallet-mint', 'AA8',
        'convert não mintou carteira', dSeller);
  }

  // reconcile stripe com order não paga.
  if (pidMkt != null) {
    final holdOrd = await c.insertOrder(
      productId: pidMkt,
      jwt: c.buyerJwt,
      status: 'reserva_pendente',
      liveItemId: itemMkt,
      liveId: liveA,
    );
    if (holdOrd.firstId != null) {
      c.createdOrderIds.add(holdOrd.firstId!);
      final rec = await c.rpc('batata_live_reconcile_stripe_order', {
        'p_order_id': holdOrd.firstId,
      }, jwt: c.sellerJwt);
      c.note('aa8.reconcile.unpaid', 'reconcile order não paga', rec.brief,
          lens: 'AA8');
      if (rec.rpcOk) {
        c.hold(
          id: 'RTAA-AA8-reconcile-unpaid',
          lens: 'AA8',
          severity: 'P1',
          title: 'reconcile stripe em order não paga converte reserva',
          actor: 'seller JWT',
          pre: 'order reserva_pendente',
          repro: 'rpc batata_live_reconcile_stripe_order',
          expected: 'order_not_paid',
          obtained: rec.brief,
        );
      } else {
        c.block('RTAA-AA8-reconcile-unpaid', 'AA8',
            'reconcile unpaid recusado', rec.brief);
      }
    }
  }

  // Wallet PATCH directo.
  final wPatch = await c.rest(
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    jwt: c.sellerJwt,
    body: {'balance': 99999},
  );
  c.note('aa8.wallet.patch', 'seller PATCH wallets.balance', wPatch.brief,
      lens: 'AA8');
  if (wPatch.ok) {
    c.hold(
      id: 'RTAA-AA8-wallet-patch',
      lens: 'AA8',
      severity: 'P0',
      title: 'JWT PATCH wallets.balance',
      actor: 'seller JWT',
      pre: 'carteira própria',
      repro: 'PATCH wallets.balance=99999',
      expected: '403',
      obtained: wPatch.brief,
    );
  } else {
    c.block('RTAA-AA8-wallet-patch', 'AA8', 'PATCH wallet recusado',
        wPatch.brief);
  }
}
