/// REDTEAM_BLIND_AD_LIVE_POS_YZAA_v1 — pass1
/// Variantes NOVAS pós-fecho YZAA. Staging only. Sem produção. Sem Fase 4. Sem fixes.
/// dart run tool/redteam_blind_ad_20260901T1825/pass1.dart
import 'dart:io';

import '_rtad.dart';

Future<void> main() async {
  final c = Rtad.fromEnv(loadEnv());
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
    if (liveA == null || liveB == null || liveS2 == null) {
      throw StateError('fixture lives failed');
    }

    final itemA1 = await c.insertLiveOnlyItem(
        liveId: liveA, qty: 4, ref: 'AD1', jwt: c.sellerJwt);
    final itemA2 = await c.insertLiveOnlyItem(
        liveId: liveA, qty: 1, ref: 'AD2', jwt: c.sellerJwt);
    final itemA3 = await c.insertLiveOnlyItem(
        liveId: liveA, qty: 1, ref: 'AD3', jwt: c.sellerJwt);
    final itemA4 = await c.insertLiveOnlyItem(
        liveId: liveA, qty: 2, ref: 'AD4', jwt: c.sellerJwt);
    final itemB1 = await c.insertLiveOnlyItem(
        liveId: liveB, qty: 2, ref: 'ADB', jwt: c.sellerJwt);
    final itemS2 = await c.insertLiveOnlyItem(
        liveId: liveS2, qty: 2, ref: 'ADS', jwt: c.seller2Jwt);
    final pidMkt = await c.createProduct(qty: 1, title: '$prefix-mkt');
    final itemMkt = pidMkt == null
        ? null
        : await c.insertMarketItem(
            liveId: liveA, productId: pidMkt, ref: 'ADM', jwt: c.sellerJwt);
    final pidMkt2 = await c.createProduct(qty: 1, title: '$prefix-mkt2');
    final itemMkt2 = pidMkt2 == null
        ? null
        : await c.insertMarketItem(
            liveId: liveA, productId: pidMkt2, ref: 'ADM2', jwt: c.sellerJwt);

    c.note('fix.items', 'items', {
      'A1': itemA1,
      'A2': itemA2,
      'A3': itemA3,
      'A4': itemA4,
      'B1': itemB1,
      'S2': itemS2,
      'mkt': itemMkt,
      'pid': pidMkt,
      'mkt2': itemMkt2,
      'pid2': pidMkt2,
    });

    await staffSetup(c);
    await runAd1(c, liveA, itemA1, itemA2);
    await runAd2(c, liveA, itemA1, itemA4);
    await runAd3(c, liveA, itemA2, itemA3);
    await runAd4(c, liveA, itemA3, itemA4, pidMkt, itemMkt, pidMkt2, itemMkt2);
    await runAd5(c, liveA, liveB, liveS2, itemA4, itemB1, itemS2);
    await runAd6(c, liveA, itemA4);
    await runAd7(c, liveA, liveS2, itemA1, itemS2);
    await runAd8(c, liveA, itemA1, pidMkt, itemMkt, w0);

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

Future<void> staffSetup(Rtad c) async {
  final hid = await c.inviteHelper(
    helperUserId: c.helperId!,
    helperEmail: '${prefix.toLowerCase()}-h1@fleaber.test',
  );
  if (hid != null) {
    c.helperRowId = hid;
    await c.acceptInvite(hid, jwt: c.helperJwt);
    await c.activateHelper(hid);
  }
  final viewHid = await c.inviteHelper(
    helperUserId: c.viewId!,
    helperEmail: '${prefix.toLowerCase()}-hv@fleaber.test',
    perms: {
      'can_view_live_dashboard': true,
      'can_manage_reservations': false,
      'can_mark_items_sold': false,
      'can_change_current_item': false,
    },
  );
  if (viewHid != null) {
    c.viewRowId = viewHid;
    await c.acceptInvite(viewHid, jwt: c.viewJwt);
    await c.activateHelper(viewHid);
  }
  c.note('staff.rows', 'helpers', {
    'h1': hid == null ? null : await c.helperRow(hid),
    'hv': viewHid == null ? null : await c.helperRow(viewHid),
  }, lens: 'AD2');
}

Map<String, Object?> stockBrief(HttpHit h) {
  final m = h.map ?? {};
  return {
    'http': h.status,
    'ok': h.rpcOk,
    'available': m['available_qty'],
    'sold': m['sold_converted_qty'],
    'reserved': m['reserved_accepted_qty'],
    'status': m['item_status'] ?? m['status'],
  };
}

/// AD1 — outros caminhos para converted sem order paga (não PATCH pending→converted exact).
Future<void> runAd1(Rtad c, String liveA, String? itemA1, String? itemA2) async {
  if (itemA1 == null || itemA2 == null) return;

  // 1) Seller INSERT fleaber_live already converted (buyer_id = self).
  final insSelf = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.sellerId,
    source: 'fleaber_live',
    status: 'converted',
    jwt: c.sellerJwt,
  );
  final insSelfId = insSelf.firstId;
  if (insSelfId != null) c.createdReqIds.add(insSelfId);
  final insSelfRow = insSelfId == null ? null : await c.reqRow(insSelfId);
  c.note('ad1.insert.fleaber.self.converted', 'seller INSERT fleaber_live converted', {
    'http': insSelf.brief,
    'row': insSelfRow,
  }, lens: 'AD1');
  if (insSelf.ok && insSelfRow?['status'] == 'converted') {
    c.hold(
      id: 'RTAD-AD1-insert-fleaber-self-converted',
      lens: 'AD1',
      severity: 'P1',
      title: 'vendedor INSERT fleaber_live já converted (buyer=self) sem PI',
      actor: 'seller',
      pre: 'live activa; item live_only; zero order paga',
      repro: 'POST live_reservation_requests source=fleaber_live status=converted buyer_id=seller',
      expected: 'pending ou 403; converted só com order paga',
      obtained: insSelfRow,
      evidence: {'insert': insSelf.brief, 'row': insSelfRow},
    );
  } else {
    c.block('RTAD-AD1-insert-fleaber-self-converted', 'AD1',
        'INSERT fleaber_live converted recusado/forçado', insSelf.brief);
  }

  // 2) Buyer INSERT fleaber_live converted (should force pending).
  final insB = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    source: 'fleaber_live',
    status: 'converted',
    jwt: c.buyerJwt,
  );
  final insBId = insB.firstId;
  if (insBId != null) c.createdReqIds.add(insBId);
  final insBRow = insBId == null ? null : await c.reqRow(insBId);
  c.note('ad1.insert.buyer.fleaber.converted', 'buyer INSERT fleaber_live converted', {
    'http': insB.brief,
    'row': insBRow,
  }, lens: 'AD1');
  if (insB.ok && insBRow?['status'] == 'converted') {
    c.hold(
      id: 'RTAD-AD1-buyer-insert-fleaber-converted',
      lens: 'AD1',
      severity: 'P1',
      title: 'comprador INSERT fleaber_live já converted sem PI',
      actor: 'buyer',
      pre: 'live activa',
      repro: 'POST source=fleaber_live status=converted',
      expected: 'status pending',
      obtained: insBRow,
    );
  } else {
    c.block('RTAD-AD1-buyer-insert-fleaber-converted', 'AD1',
        'buyer INSERT converted forçado a pending/recusado', {
      'http': insB.brief,
      'status': insBRow?['status'],
    });
  }

  // 3) facebook_manual pending → RPC accept → PATCH converted (não pending→converted exact).
  final fb = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  final fbId = fb.firstId;
  if (fbId != null) {
    c.createdReqIds.add(fbId);
    final acc = await c.processReservation(fbId, 'accept');
    c.note('ad1.accept.fb', 'RPC accept facebook_manual', acc.brief, lens: 'AD1');
    final afterAcc = await c.reqRow(fbId);
    final patch = await c.patchReq(fbId, {'status': 'converted'});
    final after = await c.reqRow(fbId);
    final st = await c.stock(itemA1);
    c.note('ad1.patch.accepted-to-converted', 'PATCH accepted→converted', {
      'after_accept': afterAcc,
      'patch': patch.brief,
      'after': after,
      'stock': stockBrief(st),
    }, lens: 'AD1');
    if (after?['status'] == 'converted') {
      c.hold(
        id: 'RTAD-AD1-patch-accepted-to-converted',
        lens: 'AD1',
        severity: 'P1',
        title: 'PATCH accepted→converted sem order paga (guard só cobre pending→converted)',
        actor: 'seller',
        pre: 'facebook_manual accepted via RPC; zero PI',
        repro: 'PATCH live_reservation_requests.status=converted sobre row accepted',
        expected: 'convert_requires_paid_order; status permanece accepted',
        obtained: after,
        evidence: {
          'patch': patch.brief,
          'stock': stockBrief(st),
          'orders': await c.ordersForItem(itemA1),
        },
      );
    } else {
      c.block('RTAD-AD1-patch-accepted-to-converted', 'AD1',
          'PATCH accepted→converted recusado/restaurado', {
        'patch': patch.brief,
        'status': after?['status'],
      });
    }
  }

  // 4) stripe_convert JWT (sem PI).
  final fb2 = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyer2Id,
    jwt: c.sellerJwt,
  );
  final fb2Id = fb2.firstId;
  if (fb2Id != null) {
    c.createdReqIds.add(fb2Id);
    await c.processReservation(fb2Id, 'accept');
    for (final actor in [
      ['seller', c.sellerJwt],
      ['buyer', c.buyerJwt],
      ['helper', c.helperJwt],
    ]) {
      final sc = await c.stripeConvert(fb2Id, jwt: actor[1]);
      final row = await c.reqRow(fb2Id);
      c.note('ad1.stripe_convert.${actor[0]}', 'stripe_convert ${actor[0]}', {
        'rpc': sc.brief,
        'status': row?['status'],
      }, lens: 'AD1');
      if ((sc.rpcOk || sc.ok) && row?['status'] == 'converted') {
        c.hold(
          id: 'RTAD-AD1-stripe-convert-${actor[0]}',
          lens: 'AD1',
          severity: 'P1',
          title: 'batata_live_reservation_stripe_convert JWT ${actor[0]} sem PI',
          actor: actor[0] as String,
          pre: 'facebook_manual accepted; zero order paga',
          repro: 'POST /rpc/batata_live_reservation_stripe_convert',
          expected: '403 / grant recusado; status accepted',
          obtained: {'rpc': sc.brief, 'row': row},
        );
        break;
      } else {
        c.block('RTAD-AD1-stripe-convert-${actor[0]}', 'AD1',
            'stripe_convert ${actor[0]} recusado', sc.brief);
      }
    }
  }

  // 5) RPC convert após INSERT order JWT (não paga).
  final pid = await c.createProduct(qty: 1, title: '$prefix-ad1-ord', listed: false);
  if (pid != null && fb2Id != null) {
    final ord = await c.insertOrder(
      productId: pid,
      jwt: c.buyerJwt,
      liveItemId: itemA1,
      liveId: liveA,
      status: 'pago',
    );
    final oid = ord.firstId;
    final orow = oid == null ? null : await c.orderRow(oid);
    c.note('ad1.order.insert.pago', 'buyer INSERT order status=pago', {
      'http': ord.brief,
      'row': orow,
    }, lens: 'AD1');
    if (orow != null &&
        '${orow['status']}'.toLowerCase() == 'pago' &&
        ((numOf(orow['amount_paid_cents']) ?? 0) > 0 ||
            '${orow['stripe_payment_intent_id'] ?? ''}'.isNotEmpty)) {
      c.hold(
        id: 'RTAD-AD1-jwt-insert-paid-order',
        lens: 'AD1',
        severity: 'P0',
        title: 'JWT INSERT order já paga (falso PI)',
        actor: 'buyer',
        pre: 'INSERT orders status=pago',
        repro: 'POST orders status=pago',
        expected: 'status reserva_pendente; amount_paid_cents null',
        obtained: orow,
      );
    } else {
      c.block('RTAD-AD1-jwt-insert-paid-order', 'AD1',
          'INSERT pago forçado a não-pago', orow ?? ord.brief);
    }
    if (oid != null) {
      final rec = await c.reconcile(oid, reqId: fb2Id);
      final row = await c.reqRow(fb2Id);
      c.note('ad1.reconcile.unpaid', 'reconcile order JWT + reserva', {
        'rpc': rec.brief,
        'req': row,
      }, lens: 'AD1');
      if (row?['status'] == 'converted') {
        c.hold(
          id: 'RTAD-AD1-reconcile-unpaid-order',
          lens: 'AD1',
          severity: 'P1',
          title: 'reconcile_stripe_order converte reserva com order não paga',
          actor: 'seller',
          pre: 'order JWT não paga; reserva accepted',
          repro: 'RPC batata_live_reconcile_stripe_order',
          expected: 'order_not_paid; status accepted',
          obtained: {'rpc': rec.brief, 'row': row},
        );
      } else {
        c.block('RTAD-AD1-reconcile-unpaid-order', 'AD1',
            'reconcile unpaid não converteu', rec.brief);
      }
      final syn = await c.syncLiveItem(oid);
      final row2 = await c.reqRow(fb2Id);
      c.note('ad1.sync.unpaid', 'sync_live_item_for_order unpaid', {
        'rpc': syn.brief,
        'req': row2,
      }, lens: 'AD1');
      if (row2?['status'] == 'converted') {
        c.hold(
          id: 'RTAD-AD1-sync-unpaid-converts',
          lens: 'AD1',
          severity: 'P1',
          title: 'sync_live_item_for_order converte reserva com order não paga',
          actor: 'seller',
          pre: 'order não paga',
          repro: 'RPC batata_sync_live_item_for_order',
          expected: 'não altera status da reserva',
          obtained: {'rpc': syn.brief, 'row': row2},
        );
      } else {
        c.block('RTAD-AD1-sync-unpaid-converts', 'AD1',
            'sync unpaid não converteu', syn.brief);
      }
    }
  }

  // 6) RPC convert facebook_manual sem PI (baseline — não parar).
  if (fb2Id != null) {
    final conv = await c.processReservation(fb2Id, 'convert');
    final row = await c.reqRow(fb2Id);
    c.note('ad1.rpc.convert.nopi', 'RPC convert sem PI (baseline)', {
      'rpc': conv.brief,
      'status': row?['status'],
    }, lens: 'AD1');
    if (conv.rpcOk && row?['status'] == 'converted') {
      c.hold(
        id: 'RTAD-AD1-rpc-convert-nopi',
        lens: 'AD1',
        severity: 'P1',
        title: 'RPC process convert facebook_manual ainda passa sem PI',
        actor: 'seller',
        pre: 'accepted; zero PI',
        repro: 'RPC batata_process_live_reservation_request action=convert',
        expected: 'convert_requires_paid_order',
        obtained: {'rpc': conv.brief, 'row': row},
      );
    } else {
      c.block('RTAD-AD1-rpc-convert-nopi', 'AD1',
          'RPC convert sem PI recusado', conv.brief);
    }
  }
}

/// AD2 — permissões finas do staff/helper.
Future<void> runAd2(Rtad c, String liveA, String? itemA1, String? itemA4) async {
  if (itemA1 == null || itemA4 == null) return;

  // Helper self-escalates permissions.
  if (c.helperRowId != null) {
    final esc = await c.setHelperPerms(c.helperRowId!, {
      'can_manage_reservations': true,
      'can_mark_items_sold': true,
      'can_change_current_item': true,
      'can_view_live_dashboard': true,
    }, jwt: c.helperJwt);
    final row = await c.helperRow(c.helperRowId!);
    c.note('ad2.helper.self-escalate', 'helper PATCH permissions', {
      'http': esc.brief,
      'row': row,
    }, lens: 'AD2');
    final perms = row?['permissions'];
    final mark = perms is Map && perms['can_mark_items_sold'] == true;
    if (esc.ok && mark) {
      c.hold(
        id: 'RTAD-AD2-helper-self-escalate',
        lens: 'AD2',
        severity: 'P1',
        title: 'helper alarga permissions (can_mark_items_sold) sozinho',
        actor: 'helper',
        pre: 'convite aceite; perms só can_manage_reservations',
        repro: 'PATCH seller_helpers.permissions',
        expected: 'permissions imutáveis para o helper',
        obtained: row,
      );
    } else {
      c.block('RTAD-AD2-helper-self-escalate', 'AD2',
          'helper não alargou permissions', {'http': esc.brief, 'perms': perms});
    }
  }

  // View-only: accept / convert / mark_sold / inflate qty.
  final fb = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  final fbId = fb.firstId;
  if (fbId != null) {
    c.createdReqIds.add(fbId);
    final acc = await c.processReservation(fbId, 'accept', jwt: c.viewJwt);
    c.note('ad2.view.accept', 'view-only RPC accept', acc.brief, lens: 'AD2');
    if (acc.rpcOk) {
      c.hold(
        id: 'RTAD-AD2-view-accept',
        lens: 'AD2',
        severity: 'P1',
        title: 'helper só can_view aceita reserva',
        actor: 'helper-view',
        pre: 'permissions só can_view_live_dashboard',
        repro: 'RPC process action=accept',
        expected: 'not_allowed',
        obtained: acc.brief,
      );
    } else {
      c.block('RTAD-AD2-view-accept', 'AD2', 'view-only accept recusado',
          acc.brief);
    }
    final conv = await c.processReservation(fbId, 'convert', jwt: c.viewJwt);
    c.note('ad2.view.convert', 'view-only RPC convert', conv.brief, lens: 'AD2');
    if (conv.rpcOk) {
      c.hold(
        id: 'RTAD-AD2-view-convert',
        lens: 'AD2',
        severity: 'P1',
        title: 'helper só can_view converte reserva',
        actor: 'helper-view',
        pre: 'can_view_live_dashboard',
        repro: 'RPC process action=convert',
        expected: 'not_allowed',
        obtained: conv.brief,
      );
    } else {
      c.block('RTAD-AD2-view-convert', 'AD2', 'view-only convert recusado',
          conv.brief);
    }
  }

  final mk = await c.markSold(itemA4, jwt: c.viewJwt);
  final afterMk = await c.itemRow(itemA4);
  c.note('ad2.view.mark_sold', 'view-only mark_sold', {
    'rpc': mk.brief,
    'item': afterMk,
  }, lens: 'AD2');
  if (mk.rpcOk || afterMk?['status'] == 'sold') {
    c.hold(
      id: 'RTAD-AD2-view-mark-sold',
      lens: 'AD2',
      severity: 'P1',
      title: 'helper só can_view marca item vendido',
      actor: 'helper-view',
      pre: 'live_only qty=2; perms view-only',
      repro: 'RPC batata_mark_live_item_sold',
      expected: 'not_allowed; status available',
      obtained: {'rpc': mk.brief, 'item': afterMk},
    );
  } else {
    c.block('RTAD-AD2-view-mark-sold', 'AD2', 'view-only mark_sold recusado',
        mk.brief);
  }

  final qtyBefore = await c.itemRow(itemA4);
  final infl = await c.updateLiveItemQty(itemA4, 40, jwt: c.viewJwt);
  final qtyAfter = await c.itemRow(itemA4);
  c.note('ad2.view.inflate', 'view-only update_live_item qty=40', {
    'rpc': infl.brief,
    'before': qtyBefore?['quantity'],
    'after': qtyAfter?['quantity'],
  }, lens: 'AD2');
  final q0 = numOf(qtyBefore?['quantity']) ?? 0;
  final q1 = numOf(qtyAfter?['quantity']) ?? 0;
  if (infl.rpcOk && q1 > q0) {
    c.hold(
      id: 'RTAD-AD2-view-inflate-qty',
      lens: 'AD2',
      severity: 'P1',
      title: 'helper só can_view infla quantity via update_live_item',
      actor: 'helper-view',
      pre: 'can_view_live_dashboard; qty original 2',
      repro: 'RPC batata_update_live_item p_quantity=40',
      expected: 'not_allowed ou qty inalterada',
      obtained: {'rpc': infl.brief, 'qty': q1},
    );
  } else {
    c.block('RTAD-AD2-view-inflate-qty', 'AD2',
        'view-only inflate recusado', {'rpc': infl.brief, 'qty': q1});
  }

  // Helper can_manage: PATCH accepted→converted (não exact AA2 pending→converted).
  final fbH = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyer2Id,
    jwt: c.helperJwt,
  );
  final fbHid = fbH.firstId;
  if (fbHid != null) {
    c.createdReqIds.add(fbHid);
    await c.processReservation(fbHid, 'accept', jwt: c.helperJwt);
    final p = await c.patchReq(fbHid, {'status': 'converted'}, jwt: c.helperJwt);
    final row = await c.reqRow(fbHid);
    c.note('ad2.helper.patch.accepted-converted', 'helper PATCH accepted→converted', {
      'patch': p.brief,
      'row': row,
    }, lens: 'AD2');
    if (row?['status'] == 'converted') {
      c.hold(
        id: 'RTAD-AD2-helper-patch-accepted-converted',
        lens: 'AD2',
        severity: 'P1',
        title: 'helper PATCH accepted→converted sem PI',
        actor: 'helper',
        pre: 'can_manage_reservations; facebook_manual accepted',
        repro: 'PATCH status=converted sobre accepted',
        expected: 'convert_requires_paid_order',
        obtained: row,
      );
    } else {
      c.block('RTAD-AD2-helper-patch-accepted-converted', 'AD2',
          'helper PATCH accepted→converted recusado', p.brief);
    }
  }

  // Seller grants can_change_current_item only → mark_sold.
  if (c.helperRowId != null) {
    await c.setHelperPerms(c.helperRowId!, {
      'can_manage_reservations': false,
      'can_view_live_dashboard': true,
      'can_change_current_item': true,
      'can_mark_items_sold': false,
    });
    final mk2 = await c.markSold(itemA4, jwt: c.helperJwt);
    final after = await c.itemRow(itemA4);
    c.note('ad2.change-item.mark_sold', 'helper can_change_current_item mark_sold', {
      'rpc': mk2.brief,
      'item': after,
    }, lens: 'AD2');
    if (mk2.rpcOk || after?['status'] == 'sold') {
      c.hold(
        id: 'RTAD-AD2-change-item-mark-sold',
        lens: 'AD2',
        severity: 'P1',
        title: 'helper can_change_current_item (sem can_mark) marca vendido',
        actor: 'helper',
        pre: 'perms só can_change_current_item + view',
        repro: 'RPC batata_mark_live_item_sold',
        expected: 'not_allowed',
        obtained: {'rpc': mk2.brief, 'item': after},
      );
    } else {
      c.block('RTAD-AD2-change-item-mark-sold', 'AD2',
          'can_change_current_item mark_sold recusado', mk2.brief);
    }
    // restore manage
    await c.setHelperPerms(c.helperRowId!, {
      'can_manage_reservations': true,
      'can_view_live_dashboard': true,
      'can_change_current_item': false,
      'can_mark_items_sold': false,
    });
  }
}

/// AD3 — item esgotado ainda visível (não hub_live_items_public exact AA3-hub).
Future<void> runAd3(Rtad c, String liveA, String? itemA2, String? itemA3) async {
  if (itemA2 == null) return;

  // Accept facebook_manual qty=1 on qty=1 item → available=0 without convert.
  final fb = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA2,
    buyer: c.buyerId,
    qty: 1,
    jwt: c.sellerJwt,
  );
  final fbId = fb.firstId;
  if (fbId == null) return;
  c.createdReqIds.add(fbId);
  await c.processReservation(fbId, 'accept');
  final st = await c.stock(itemA2);
  final hub = await c.hubItem(itemA2);
  final disc = await c.hubDiscovery(itemA2, jwt: c.buyerJwt);
  final discAnon = await c.hubDiscovery(itemA2, anon: true);
  final liBuyer = await c.rest(
    'GET',
    'live_items?id=eq.$itemA2&select=id,status,is_active,quantity,title',
    jwt: c.buyerJwt,
  );
  c.note('ad3.accept.surfaces', 'accept qty=1 → Hub/discovery/REST', {
    'stock': stockBrief(st),
    'hub_public': hub,
    'discovery_buyer': disc,
    'discovery_anon': discAnon,
    'live_items_buyer': liBuyer.brief,
  }, lens: 'AD3');

  final avail = numOf(st.map?['available_qty']) ?? -1;
  if (avail <= 0 && disc != null) {
    c.hold(
      id: 'RTAD-AD3-discovery-shows-exhausted',
      lens: 'AD3',
      severity: 'P2',
      title: 'Hub discovery ainda mostra item com available_qty=0 (view sem filtro stock)',
      actor: 'buyer',
      pre: 'facebook_manual accepted qty=1 em item qty=1; sem convert/PI',
      repro: 'GET hub_live_items_discovery_public?id=eq.<item>',
      expected: 'vazio (paridade hub_live_items_public available_qty>0)',
      obtained: {
        'available': avail,
        'hub_public': hub,
        'discovery': disc,
      },
    );
  } else {
    c.block('RTAD-AD3-discovery-shows-exhausted', 'AD3',
        'discovery não mostra item esgotado (ou stock ainda >0)', {
      'available': avail,
      'discovery': disc,
      'hub': hub,
    });
  }

  if (avail <= 0 && liBuyer.ok && liBuyer.map != null) {
    c.hold(
      id: 'RTAD-AD3-live-items-rest-exhausted',
      lens: 'AD3',
      severity: 'P2',
      title: 'REST live_items ainda devolve item esgotado ao comprador',
      actor: 'buyer',
      pre: 'available_qty=0; status não sold',
      repro: 'GET live_items?id=eq.<item> JWT buyer',
      expected: 'escondido ou status sold',
      obtained: liBuyer.map,
    );
  } else {
    c.block('RTAD-AD3-live-items-rest-exhausted', 'AD3',
        'REST live_items esgotado oculto ou stock>0', liBuyer.brief);
  }

  // PATCH live_items.status=sold → Hub vs discovery.
  if (itemA3 != null) {
    final p = await c.patchItem(itemA3, {'status': 'sold'});
    final after = await c.itemRow(itemA3);
    final hub3 = await c.hubItem(itemA3);
    final disc3 = await c.hubDiscovery(itemA3, jwt: c.buyerJwt);
    c.note('ad3.patch.status-sold', 'PATCH live_items.status=sold', {
      'patch': p.brief,
      'item': after,
      'hub': hub3,
      'discovery': disc3,
    }, lens: 'AD3');
    if (after?['status'] == 'sold' && p.ok) {
      c.hold(
        id: 'RTAD-AD3-patch-item-status-sold',
        lens: 'AD3',
        severity: 'P1',
        title: 'PATCH live_items.status=sold esconde Hub sem PI / sem mark_sold',
        actor: 'seller',
        pre: 'live_only qty=1; zero order',
        repro: 'PATCH live_items.status=sold',
        expected: 'status imutável sem RPC mark_sold + order paga',
        obtained: {'item': after, 'hub': hub3},
      );
    } else {
      c.block('RTAD-AD3-patch-item-status-sold', 'AD3',
          'PATCH status=sold recusado', p.brief);
    }
  }
}

/// AD4 — deslistar / mark_sold sem PI (não mark_sold marketplace exact).
Future<void> runAd4(
  Rtad c,
  String liveA,
  String? itemA3,
  String? itemA4,
  String? pidMkt,
  String? itemMkt,
  String? pidMkt2,
  String? itemMkt2,
) async {
  // Direct PATCH products unlist (não passa por mark_sold).
  if (pidMkt != null) {
    final before = await c.productRow(pidMkt);
    final p = await c.patchProduct(pidMkt, {
      'is_sold': true,
      'list_on_marketplace': false,
    });
    final after = await c.productRow(pidMkt);
    final hubP = await c.hubProduct(pidMkt, jwt: c.buyerJwt);
    c.note('ad4.patch.product.unlist', 'PATCH products is_sold+unlist', {
      'before': before,
      'patch': p.brief,
      'after': after,
      'hub': hubP,
    }, lens: 'AD4');
    if (after?['is_sold'] == true || after?['list_on_marketplace'] == false) {
      c.hold(
        id: 'RTAD-AD4-patch-product-unlist',
        lens: 'AD4',
        severity: 'P1',
        title: 'PATCH products is_sold/list_on_marketplace deslista SKU sem PI',
        actor: 'seller',
        pre: 'SKU marketplace qty=1; zero order paga',
        repro: 'PATCH products is_sold=true list_on_marketplace=false',
        expected: 'guard recusa unlist sem order paga (paridade mark_sold)',
        obtained: after,
        evidence: {'hub_products': hubP, 'patch': p.brief},
      );
    } else {
      c.block('RTAD-AD4-patch-product-unlist', 'AD4',
          'PATCH product unlist recusado', p.brief);
    }
  }

  // mark_sold live_only — unlist checkout_product sem PI (ramo else do RPC).
  if (itemA4 != null) {
    final before = await c.itemRow(itemA4);
    final mk = await c.markSold(itemA4);
    final after = await c.itemRow(itemA4);
    final st = await c.stock(itemA4);
    c.note('ad4.mark_sold.live_only', 'mark_sold live_only sem PI', {
      'before': before,
      'rpc': mk.brief,
      'after': after,
      'stock': stockBrief(st),
    }, lens: 'AD4');
    if (after?['status'] == 'sold') {
      c.hold(
        id: 'RTAD-AD4-mark-sold-live-only-no-pi',
        lens: 'AD4',
        severity: 'P1',
        title: 'mark_sold live_only põe status=sold e esgota Hub sem order paga',
        actor: 'seller',
        pre: 'live_only; zero PI',
        repro: 'RPC batata_mark_live_item_sold',
        expected: 'recusa ou não sold sem PI (paridade marketplace)',
        obtained: {'rpc': mk.brief, 'item': after, 'stock': stockBrief(st)},
      );
    } else {
      c.block('RTAD-AD4-mark-sold-live-only-no-pi', 'AD4',
          'mark_sold live_only recusado', mk.brief);
    }
  }

  // mark_sold marketplace: Hub live sold mas SKU continua? (variante: efeito live, não unlist mkt exact).
  if (itemMkt2 != null && pidMkt2 != null) {
    final mk = await c.markSold(itemMkt2);
    final item = await c.itemRow(itemMkt2);
    final prod = await c.productRow(pidMkt2);
    final hubI = await c.hubItem(itemMkt2);
    final hubP = await c.hubProduct(pidMkt2, jwt: c.buyerJwt);
    c.note('ad4.mark_sold.mkt.live-effect', 'mark_sold mkt sem PI — efeito live/Hub', {
      'rpc': mk.brief,
      'item': item,
      'prod': prod,
      'hub_item': hubI,
      'hub_prod': hubP,
    }, lens: 'AD4');
    if (item?['status'] == 'sold') {
      c.hold(
        id: 'RTAD-AD4-mark-sold-mkt-kills-live',
        lens: 'AD4',
        severity: 'P1',
        title: 'mark_sold marketplace mata live_item/Hub sem PI (mesmo se SKU fica listado)',
        actor: 'seller',
        pre: 'marketplace_product; zero order paga',
        repro: 'RPC batata_mark_live_item_sold em SKU mkt',
        expected: 'não sold na live sem PI',
        obtained: {
          'item_status': item?['status'],
          'product': prod,
          'hub_item': hubI,
        },
      );
    } else {
      c.block('RTAD-AD4-mark-sold-mkt-kills-live', 'AD4',
          'mark_sold mkt não sold na live', mk.brief);
    }
  }
}

/// AD5 — mover live_id / inflar qty (não move exact com reservas).
Future<void> runAd5(
  Rtad c,
  String liveA,
  String liveB,
  String liveS2,
  String? itemA4,
  String? itemB1,
  String? itemS2,
) async {
  // Move live_id ANTES de qualquer reserva (item fresco).
  final fresh = await c.insertLiveOnlyItem(
      liveId: liveA, qty: 1, ref: 'AD5', jwt: c.sellerJwt);
  if (fresh != null) {
    final mv = await c.patchItem(fresh, {'live_id': liveB});
    final after = await c.itemRow(fresh);
    c.note('ad5.move.no-res', 'PATCH live_id sem reservas liveA→liveB', {
      'patch': mv.brief,
      'after': after,
    }, lens: 'AD5');
    if (after?['live_id'] == liveB) {
      c.hold(
        id: 'RTAD-AD5-move-live-id-no-reservation',
        lens: 'AD5',
        severity: 'P2',
        title: 'item sem reservas muda de live (live_id mutável até 1ª reserva)',
        actor: 'seller',
        pre: 'live_only novo; zero reservas',
        repro: 'PATCH live_items.live_id',
        expected: 'live_id imutável sempre, ou só via RPC dono com auditoria',
        obtained: after,
      );
    } else {
      c.block('RTAD-AD5-move-live-id-no-reservation', 'AD5',
          'move sem reservas recusado', mv.brief);
    }

    // Cross-seller move sem reservas.
    final mvS2 = await c.patchItem(fresh, {'live_id': liveS2});
    final afterS2 = await c.itemRow(fresh);
    c.note('ad5.move.cross-seller', 'PATCH live_id → live seller2', {
      'patch': mvS2.brief,
      'after': afterS2,
    }, lens: 'AD5');
    if (afterS2?['live_id'] == liveS2) {
      c.hold(
        id: 'RTAD-AD5-move-to-foreign-live',
        lens: 'AD5',
        severity: 'P1',
        title: 'item do vendedor A move para live do vendedor B',
        actor: 'seller',
        pre: 'item próprio; live seller2',
        repro: 'PATCH live_items.live_id=<live seller2>',
        expected: 'live_item_not_authorized',
        obtained: afterS2,
      );
    } else {
      c.block('RTAD-AD5-move-to-foreign-live', 'AD5',
          'move para live alheia recusado', mvS2.brief);
    }
  }

  // Move reservation.live_id.
  if (itemB1 != null) {
    final fb = await c.insertReservation(
      liveId: liveA,
      liveItemId: itemB1,
      buyer: c.buyerId,
      jwt: c.sellerJwt,
    );
    // itemB1 is on liveB — mismatch insert may fail; try item on liveA if needed.
    c.note('ad5.res.mismatch.insert', 'INSERT reserva item liveB via liveA',
        fb.brief, lens: 'AD5');
    if (fb.ok) {
      c.hold(
        id: 'RTAD-AD5-insert-item-live-mismatch',
        lens: 'AD5',
        severity: 'P1',
        title: 'INSERT reserva com live_id ≠ live_item.live_id',
        actor: 'seller',
        pre: 'itemB1 pertence a liveB; POST live_id=liveA',
        repro: 'POST live_reservation_requests live_id mismatch',
        expected: 'live_item_live_mismatch',
        obtained: fb.brief,
      );
    } else {
      c.block('RTAD-AD5-insert-item-live-mismatch', 'AD5',
          'INSERT mismatch recusado', fb.brief);
    }

    final okFb = await c.insertReservation(
      liveId: liveB,
      liveItemId: itemB1,
      buyer: c.buyerId,
      jwt: c.sellerJwt,
    );
    final rid = okFb.firstId;
    if (rid != null) {
      c.createdReqIds.add(rid);
      final mv = await c.patchReq(rid, {'live_id': liveA});
      final row = await c.reqRow(rid);
      c.note('ad5.patch.req.live_id', 'PATCH reserva.live_id para outra live', {
        'patch': mv.brief,
        'row': row,
      }, lens: 'AD5');
      if (row?['live_id'] == liveA) {
        c.hold(
          id: 'RTAD-AD5-patch-reservation-live-id',
          lens: 'AD5',
          severity: 'P1',
          title: 'PATCH reserva.live_id move pedido para outra live',
          actor: 'seller',
          pre: 'facebook_manual pending em liveB',
          repro: 'PATCH live_reservation_requests.live_id',
          expected: 'live_id imutável / mismatch',
          obtained: row,
        );
      } else {
        c.block('RTAD-AD5-patch-reservation-live-id', 'AD5',
            'PATCH reserva.live_id recusado', mv.brief);
      }
    }
  }

  // Helper inflate via REST PATCH quantity (não RPC exact X2).
  if (itemS2 == null && itemA4 != null) {
    // use a fresh item
  }
  final inflItem = await c.insertLiveOnlyItem(
      liveId: liveA, qty: 1, ref: 'AD5q', jwt: c.sellerJwt);
  if (inflItem != null) {
    final restH = await c.patchItem(inflItem, {'quantity': 40}, jwt: c.helperJwt);
    final afterH = await c.itemRow(inflItem);
    c.note('ad5.helper.patch.qty', 'helper PATCH live_items.quantity=40', {
      'patch': restH.brief,
      'after': afterH,
    }, lens: 'AD5');
    if ((numOf(afterH?['quantity']) ?? 0) >= 40) {
      c.hold(
        id: 'RTAD-AD5-helper-patch-qty',
        lens: 'AD5',
        severity: 'P1',
        title: 'helper PATCH quantity 1→40 sem can_mark_items_sold',
        actor: 'helper',
        pre: 'can_manage_reservations; live_only qty=1',
        repro: 'PATCH live_items.quantity=40',
        expected: 'live_item_qty_increase_not_allowed',
        obtained: afterH,
      );
    } else {
      c.block('RTAD-AD5-helper-patch-qty', 'AD5',
          'helper PATCH qty recusado', restH.brief);
    }

    // Seller grants can_mark → inflate.
    if (c.helperRowId != null) {
      await c.setHelperPerms(c.helperRowId!, {
        'can_manage_reservations': true,
        'can_view_live_dashboard': true,
        'can_mark_items_sold': true,
      });
      final restM = await c.patchItem(inflItem, {'quantity': 40}, jwt: c.helperJwt);
      final afterM = await c.itemRow(inflItem);
      c.note('ad5.helper.mark.inflate', 'helper can_mark PATCH qty=40', {
        'patch': restM.brief,
        'after': afterM,
      }, lens: 'AD5');
      if ((numOf(afterM?['quantity']) ?? 0) >= 40) {
        c.hold(
          id: 'RTAD-AD5-helper-mark-inflate-qty',
          lens: 'AD5',
          severity: 'P2',
          title: 'helper can_mark_items_sold infla quantity (perm serve dois fins)',
          actor: 'helper',
          pre: 'seller concedeu can_mark_items_sold',
          repro: 'PATCH live_items.quantity=40',
          expected: 'mark_sold ≠ inflate stock',
          obtained: afterM,
        );
      } else {
        c.block('RTAD-AD5-helper-mark-inflate-qty', 'AD5',
            'can_mark não inflou qty', restM.brief);
      }
      await c.setHelperPerms(c.helperRowId!, {
        'can_manage_reservations': true,
        'can_view_live_dashboard': true,
        'can_mark_items_sold': false,
      });
    }
  }
}

/// AD6 — races (dois PATCH converted simultâneos / dois accept).
Future<void> runAd6(Rtad c, String liveA, String? itemA4) async {
  final raceItem = await c.insertLiveOnlyItem(
      liveId: liveA, qty: 1, ref: 'AD6', jwt: c.sellerJwt);
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
  final id1 = r1.firstId;
  final id2 = r2.firstId;
  if (id1 == null || id2 == null) {
    c.skip('RTAD-AD6-race-accept', 'AD6', 'não criou 2 pending', {
      'r1': r1.brief,
      'r2': r2.brief,
    });
    return;
  }
  c.createdReqIds.addAll([id1, id2]);

  final accs = await parallel([
    c.processReservation(id1, 'accept'),
    c.processReservation(id2, 'accept'),
  ]);
  final row1 = await c.reqRow(id1);
  final row2 = await c.reqRow(id2);
  final st = await c.stock(raceItem);
  c.note('ad6.race.accept', 'dois RPC accept paralelos qty=1', {
    'a1': accs[0].brief,
    'a2': accs[1].brief,
    'r1': row1,
    'r2': row2,
    'stock': stockBrief(st),
  }, lens: 'AD6');
  final aOk = [row1, row2].where((r) => r?['status'] == 'accepted').length;
  final sold = numOf(st.map?['sold_converted_qty']) ?? 0;
  final reserved = numOf(st.map?['reserved_accepted_qty']) ?? 0;
  if (aOk >= 2 || (reserved + sold) > 1) {
    c.hold(
      id: 'RTAD-AD6-race-double-accept',
      lens: 'AD6',
      severity: 'P1',
      title: 'dois accept paralelos em item qty=1 — oversell capacidade',
      actor: 'seller',
      pre: 'duas facebook_manual pending; item qty=1',
      repro: 'RPC accept ×2 em paralelo',
      expected: 'só 1 accepted; available≥0; reserved+sold≤1',
      obtained: {
        'accepted_rows': aOk,
        'reserved': reserved,
        'sold': sold,
        'r1': row1?['status'],
        'r2': row2?['status'],
      },
    );
  } else {
    c.block('RTAD-AD6-race-double-accept', 'AD6',
        'race accept não oversell', {
      'accepted': aOk,
      'reserved': reserved,
      'sold': sold,
    });
  }

  // Parallel PATCH converted on whichever is accepted.
  final targets = <String>[];
  if (row1?['status'] == 'accepted') targets.add(id1);
  if (row2?['status'] == 'accepted') targets.add(id2);
  if (row1?['status'] == 'pending') targets.add(id1);
  if (targets.isEmpty) targets.add(id1);
  final patches = await parallel([
    for (final t in targets.take(2))
      c.patchReq(t, {'status': 'converted'}),
    if (targets.length == 1) c.patchReq(targets.first, {'status': 'converted'}),
  ]);
  final afters = <Map<String, dynamic>?>[];
  for (final t in [id1, id2]) {
    afters.add(await c.reqRow(t));
  }
  final nConv = afters.where((r) => r?['status'] == 'converted').length;
  c.note('ad6.race.patch.converted', 'PATCH converted paralelo', {
    'patches': patches.map((p) => p.brief).toList(),
    'rows': afters,
    'n_converted': nConv,
  }, lens: 'AD6');
  if (nConv >= 1) {
    c.hold(
      id: 'RTAD-AD6-race-patch-converted',
      lens: 'AD6',
      severity: 'P1',
      title: 'race PATCH converted simultâneo sem PI',
      actor: 'seller',
      pre: 'reservas accepted/pending; zero PI',
      repro: 'dois PATCH status=converted em paralelo',
      expected: 'nenhum converted sem order paga',
      obtained: {'n_converted': nConv, 'rows': afters},
    );
  } else {
    c.block('RTAD-AD6-race-patch-converted', 'AD6',
        'race PATCH converted não passou', patches.map((p) => p.brief).toList());
  }
}

/// AD7 — sabotar live alheia.
Future<void> runAd7(
  Rtad c,
  String liveA,
  String liveS2,
  String? itemA1,
  String? itemS2,
) async {
  if (itemA1 == null || itemS2 == null) return;

  final fb = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA1,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  final rid = fb.firstId;
  if (rid != null) {
    c.createdReqIds.add(rid);
    final acc = await c.processReservation(rid, 'accept', jwt: c.seller2Jwt);
    c.note('ad7.s2.accept', 'seller2 RPC accept reserva seller1', acc.brief,
        lens: 'AD7');
    if (acc.rpcOk) {
      c.hold(
        id: 'RTAD-AD7-seller2-accept-foreign',
        lens: 'AD7',
        severity: 'P1',
        title: 'seller2 aceita reserva da live alheia',
        actor: 'seller2',
        pre: 'facebook_manual pending na live seller1',
        repro: 'RPC process accept JWT seller2',
        expected: 'not_allowed',
        obtained: acc.brief,
      );
    } else {
      c.block('RTAD-AD7-seller2-accept-foreign', 'AD7',
          'seller2 accept recusado', acc.brief);
    }
    final p = await c.patchReq(rid, {'status': 'converted'}, jwt: c.seller2Jwt);
    final row = await c.reqRow(rid);
    c.note('ad7.s2.patch.converted', 'seller2 PATCH converted alheio', {
      'patch': p.brief,
      'row': row,
    }, lens: 'AD7');
    if (row?['status'] == 'converted' && p.ok) {
      c.hold(
        id: 'RTAD-AD7-seller2-patch-converted',
        lens: 'AD7',
        severity: 'P1',
        title: 'seller2 PATCH converted na reserva alheia',
        actor: 'seller2',
        pre: 'reserva seller1',
        repro: 'PATCH status=converted JWT seller2',
        expected: 'RLS recusa',
        obtained: row,
      );
    } else {
      c.block('RTAD-AD7-seller2-patch-converted', 'AD7',
          'seller2 PATCH converted recusado', p.brief);
    }
  }

  final mk = await c.markSold(itemA1, jwt: c.seller2Jwt);
  c.note('ad7.s2.mark_sold', 'seller2 mark_sold item seller1', mk.brief,
      lens: 'AD7');
  if (mk.rpcOk) {
    c.hold(
      id: 'RTAD-AD7-seller2-mark-sold',
      lens: 'AD7',
      severity: 'P1',
      title: 'seller2 mark_sold item da live alheia',
      actor: 'seller2',
      pre: 'item seller1',
      repro: 'RPC batata_mark_live_item_sold JWT seller2',
      expected: 'not_allowed',
      obtained: mk.brief,
    );
  } else {
    c.block('RTAD-AD7-seller2-mark-sold', 'AD7',
        'seller2 mark_sold recusado', mk.brief);
  }

  final helperOnS2 = await c.markSold(itemS2, jwt: c.helperJwt);
  c.note('ad7.helper.mark.s2', 'helper seller1 mark_sold item seller2',
      helperOnS2.brief, lens: 'AD7');
  if (helperOnS2.rpcOk) {
    c.hold(
      id: 'RTAD-AD7-helper-mark-sold-foreign',
      lens: 'AD7',
      severity: 'P1',
      title: 'helper do seller1 mark_sold item do seller2',
      actor: 'helper',
      pre: 'staff só da loja seller1',
      repro: 'RPC mark_sold no item seller2',
      expected: 'not_allowed',
      obtained: helperOnS2.brief,
    );
  } else {
    c.block('RTAD-AD7-helper-mark-sold-foreign', 'AD7',
        'helper mark_sold foreign recusado', helperOnS2.brief);
  }

  final infl = await c.updateLiveItemQty(itemS2, 99, jwt: c.sellerJwt);
  final after = await c.itemRow(itemS2);
  c.note('ad7.s1.inflate.s2', 'seller1 update_live_item qty no item seller2', {
    'rpc': infl.brief,
    'after': after,
  }, lens: 'AD7');
  if ((numOf(after?['quantity']) ?? 0) >= 99) {
    c.hold(
      id: 'RTAD-AD7-seller-inflate-foreign-qty',
      lens: 'AD7',
      severity: 'P1',
      title: 'seller1 infla qty do item seller2',
      actor: 'seller',
      pre: 'item live seller2',
      repro: 'RPC batata_update_live_item p_quantity=99',
      expected: 'not_allowed',
      obtained: after,
    );
  } else {
    c.block('RTAD-AD7-seller-inflate-foreign-qty', 'AD7',
        'inflate foreign recusado', infl.brief);
  }
}

/// AD8 — caixa: Δ wallet / order fantasma após convert sem PI.
Future<void> runAd8(
  Rtad c,
  String liveA,
  String? itemA1,
  String? pidMkt,
  String? itemMkt,
  Map<String, num> w0,
) async {
  final wNow = await c.wallets();
  final orders = itemA1 == null ? <dynamic>[] : await c.ordersForItem(itemA1);
  c.note('ad8.wallets.mid', 'wallets vs baseline', {
    'w0': w0,
    'now': wNow,
    'orders_itemA1': orders,
  }, lens: 'AD8');

  for (final e in wNow.entries) {
    final delta = e.value - (w0[e.key] ?? 0);
    if (delta.abs() > 0.009) {
      c.hold(
        id: 'RTAD-AD8-wallet-delta-${e.key}',
        lens: 'AD8',
        severity: delta > 0 ? 'P0' : 'P2',
        title: 'Δ wallet ${e.key} = $delta após probes live sem Stripe',
        actor: e.key,
        pre: 'só JWT staging; Stripe TEST não usado',
        repro: 'wallets() antes vs depois pass1',
        expected: 'Δ = 0',
        obtained: {'before': w0[e.key], 'after': e.value, 'delta': delta},
      );
    }
  }
  if (c.findings.where((f) => (f['id'] as String).startsWith('RTAD-AD8-wallet')).isEmpty) {
    c.block('RTAD-AD8-wallet-delta', 'AD8', 'sem Δ wallet', wNow);
  }

  // Checkout Stripe após mark_sold / converted fantasma.
  if (itemMkt != null) {
    final pi = await c.edge('create-live-checkout', {
      'live_item_id': itemMkt,
    }, jwt: c.buyerJwt);
    c.note('ad8.checkout.after.probes', 'edge create-live-checkout pós probes',
        pi.brief, lens: 'AD8');
    // Não é finding por si: só se PI criado sobre item já converted/sold sem pagamento.
  }
}
