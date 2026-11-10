/// REDTEAM_BLIND_AD pass2 — isolar P1 convert sem PI + Hub/stock.
/// dart run tool/redteam_blind_ad_20260901T1825/pass2.dart
import 'dart:io';

import '_rtad.dart';

Future<void> main() async {
  final c = Rtad.fromEnv(loadEnv());
  try {
    await c.loginActors();
    await c.ensureHelper();
    await staff(c);

    final live = await c.insertLive();
    if (live == null) throw StateError('live');

    await isoInsertConverted(c, live);
    await isoPatchAcceptedConverted(c, live);
    await isoHelperPatchAcceptedConverted(c, live);
    await isoPendingConvertedControl(c, live);
    await isoFbInsertConvertedControl(c, live);
    await isoPatchStatusSoldHub(c, live);
    await isoMarkSoldLiveOnly(c, live);

    final w = await c.wallets();
    c.note('p2.wallets', 'wallets', w, lens: 'AD8');
  } finally {
    await c.dumpAll('findings_pass2.json');
    await c.endLives();
    stdout.writeln(
        'PASS2 findings=${c.findings.length} blocked=${c.blocked.length}');
  }
}

Future<void> staff(Rtad c) async {
  final existing = await c.rest(
    'GET',
    'seller_helpers?helper_user_id=eq.${c.helperId}&seller_id=eq.${c.sellerId}&select=id,active,permissions,invitation_status',
    service: true,
  );
  final exId = existing.firstId;
  if (exId != null) {
    c.helperRowId = exId;
    await c.activateHelper(exId);
    return;
  }
  final hid = await c.inviteHelper(
    helperUserId: c.helperId!,
    helperEmail: '${prefix.toLowerCase()}-h1@fleaber.test',
  );
  if (hid != null) {
    c.helperRowId = hid;
    await c.acceptInvite(hid, jwt: c.helperJwt);
    await c.activateHelper(hid);
  }
}

Map<String, Object?> briefStock(HttpHit h) => {
      'available': h.map?['available_qty'],
      'sold': h.map?['sold_converted_qty'],
      'reserved': h.map?['reserved_accepted_qty'],
    };

Future<void> isoInsertConverted(Rtad c, String live) async {
  final item = await c.insertLiveOnlyItem(
      liveId: live, qty: 1, ref: 'P2A', jwt: c.sellerJwt);
  if (item == null) return;
  final st0 = await c.stock(item);
  final hub0 = await c.hubItem(item);
  final ins = await c.insertReservation(
    liveId: live,
    liveItemId: item,
    buyer: c.sellerId,
    source: 'fleaber_live',
    status: 'converted',
    jwt: c.sellerJwt,
  );
  final id = ins.firstId;
  if (id != null) c.createdReqIds.add(id);
  final row = id == null ? null : await c.reqRow(id);
  final st1 = await c.stock(item);
  final hub1 = await c.hubItem(item);
  final disc1 = await c.hubDiscovery(item, jwt: c.buyerJwt);
  final orders = await c.ordersForItem(item);
  c.note('p2.insert.converted.iso', 'INSERT fleaber converted qty=1 isolado', {
    'insert': ins.brief,
    'row': row,
    'stock0': briefStock(st0),
    'stock1': briefStock(st1),
    'hub0': hub0 != null,
    'hub1': hub1,
    'discovery1': disc1,
    'orders': orders,
  }, lens: 'AD1');
  final sold = numOf(st1.map?['sold_converted_qty']) ?? 0;
  final avail = numOf(st1.map?['available_qty']) ?? -1;
  if (row?['status'] == 'converted' && sold >= 1 && orders.isEmpty) {
    c.hold(
      id: 'RTAD-AD1-insert-fleaber-converted-iso',
      lens: 'AD1',
      severity: 'P1',
      title: 'INSERT fleaber_live converted qty=1 consome stock e some do Hub sem order',
      actor: 'seller',
      pre: 'item live_only qty=1 isolado; zero PI',
      repro: 'POST source=fleaber_live status=converted buyer_id=seller',
      expected: 'pending; sold=0; Hub visível',
      obtained: {
        'status': row?['status'],
        'sold': sold,
        'available': avail,
        'hub': hub1,
        'orders': orders.length,
        'processed_by': row?['processed_by_user_id'],
      },
      evidence: {
        'stock0': briefStock(st0),
        'stock1': briefStock(st1),
        'hub0': hub0,
        'discovery': disc1,
      },
    );
  } else {
    c.block('RTAD-AD1-insert-fleaber-converted-iso', 'AD1',
        'INSERT converted isolado não consumiu', {
      'row': row,
      'stock': briefStock(st1),
    });
  }
}

Future<void> isoPatchAcceptedConverted(Rtad c, String live) async {
  final item = await c.insertLiveOnlyItem(
      liveId: live, qty: 1, ref: 'P2B', jwt: c.sellerJwt);
  if (item == null) return;
  final fb = await c.insertReservation(
    liveId: live,
    liveItemId: item,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  final id = fb.firstId;
  if (id == null) return;
  c.createdReqIds.add(id);
  final acc = await c.processReservation(id, 'accept');
  final afterAcc = await c.reqRow(id);
  final stAcc = await c.stock(item);
  final patch = await c.patchReq(id, {'status': 'converted'});
  final after = await c.reqRow(id);
  final st1 = await c.stock(item);
  final hub1 = await c.hubItem(item);
  final disc1 = await c.hubDiscovery(item, jwt: c.buyerJwt);
  final orders = await c.ordersForItem(item);
  c.note('p2.patch.accepted-converted.iso', 'PATCH accepted→converted isolado', {
    'accept': acc.brief,
    'after_accept': afterAcc,
    'stock_accepted': briefStock(stAcc),
    'patch': patch.brief,
    'after': after,
    'stock1': briefStock(st1),
    'hub1': hub1,
    'discovery': disc1,
    'orders': orders,
  }, lens: 'AD1');
  if (after?['status'] == 'converted' &&
      (numOf(st1.map?['sold_converted_qty']) ?? 0) >= 1 &&
      orders.isEmpty) {
    c.hold(
      id: 'RTAD-AD1-patch-accepted-converted-iso',
      lens: 'AD1',
      severity: 'P1',
      title: 'PATCH accepted→converted qty=1: sold sem order; Hub some; discovery fica',
      actor: 'seller',
      pre: 'facebook_manual accepted; item qty=1; zero PI',
      repro: 'RPC accept; PATCH status=converted',
      expected: 'convert_requires_paid_order; sold=0',
      obtained: {
        'status': after?['status'],
        'sold': st1.map?['sold_converted_qty'],
        'available': st1.map?['available_qty'],
        'hub_public': hub1,
        'discovery': disc1,
        'orders': 0,
        'processed_by': after?['processed_by_user_id'],
      },
    );
  } else {
    c.block('RTAD-AD1-patch-accepted-converted-iso', 'AD1',
        'PATCH accepted→converted isolado recusado', {
      'patch': patch.brief,
      'status': after?['status'],
      'stock': briefStock(st1),
    });
  }
}

Future<void> isoHelperPatchAcceptedConverted(Rtad c, String live) async {
  final item = await c.insertLiveOnlyItem(
      liveId: live, qty: 1, ref: 'P2C', jwt: c.sellerJwt);
  if (item == null) return;
  final fb = await c.insertReservation(
    liveId: live,
    liveItemId: item,
    buyer: c.buyerId,
    jwt: c.helperJwt,
  );
  final id = fb.firstId;
  if (id == null) {
    c.skip('RTAD-AD2-helper-accepted-converted-iso', 'AD2',
        'helper INSERT facebook_manual falhou', fb.brief);
    return;
  }
  c.createdReqIds.add(id);
  final acc = await c.processReservation(id, 'accept', jwt: c.helperJwt);
  final afterAcc = await c.reqRow(id);
  final patch = await c.patchReq(id, {'status': 'converted'}, jwt: c.helperJwt);
  final after = await c.reqRow(id);
  final st = await c.stock(item);
  final orders = await c.ordersForItem(item);
  c.note('p2.helper.patch.accepted-converted', 'helper PATCH accepted→converted iso', {
    'insert': fb.brief,
    'accept': acc.brief,
    'after_accept': afterAcc,
    'patch': patch.brief,
    'after': after,
    'stock': briefStock(st),
    'orders': orders,
  }, lens: 'AD2');
  if (after?['status'] == 'converted' &&
      (numOf(st.map?['sold_converted_qty']) ?? 0) >= 1) {
    c.hold(
      id: 'RTAD-AD2-helper-patch-accepted-converted-iso',
      lens: 'AD2',
      severity: 'P1',
      title: 'helper PATCH accepted→converted consome stock sem PI',
      actor: 'helper',
      pre: 'can_manage_reservations; facebook_manual accepted qty=1',
      repro: 'RPC accept; PATCH status=converted JWT helper',
      expected: 'convert_requires_paid_order',
      obtained: {
        'status': after?['status'],
        'sold': st.map?['sold_converted_qty'],
        'orders': orders.length,
      },
    );
  } else {
    c.block('RTAD-AD2-helper-patch-accepted-converted-iso', 'AD2',
        'helper PATCH accepted→converted recusado', {
      'patch': patch.brief,
      'status': after?['status'],
    });
  }
}

Future<void> isoPendingConvertedControl(Rtad c, String live) async {
  final item = await c.insertLiveOnlyItem(
      liveId: live, qty: 1, ref: 'P2D', jwt: c.sellerJwt);
  if (item == null) return;
  final fb = await c.insertReservation(
    liveId: live,
    liveItemId: item,
    buyer: c.buyerId,
    jwt: c.sellerJwt,
  );
  final id = fb.firstId;
  if (id == null) return;
  c.createdReqIds.add(id);
  final patch = await c.patchReq(id, {'status': 'converted'});
  final after = await c.reqRow(id);
  c.note('p2.control.pending-converted', 'controlo PATCH pending→converted', {
    'patch': patch.brief,
    'status': after?['status'],
  }, lens: 'AD1');
  if (after?['status'] == 'converted') {
    c.hold(
      id: 'RTAD-AD1-patch-pending-converted-still-open',
      lens: 'AD1',
      severity: 'P1',
      title: 'PATCH pending→converted ainda passa (regressão do fecho AA)',
      actor: 'seller',
      pre: 'facebook_manual pending',
      repro: 'PATCH status=converted',
      expected: 'convert_requires_paid_order',
      obtained: after,
    );
  } else {
    c.block('RTAD-AD1-patch-pending-converted-still-open', 'AD1',
        'controlo pending→converted continua fechado', patch.brief);
  }
}

Future<void> isoFbInsertConvertedControl(Rtad c, String live) async {
  final item = await c.insertLiveOnlyItem(
      liveId: live, qty: 1, ref: 'P2E', jwt: c.sellerJwt);
  if (item == null) return;
  final ins = await c.insertReservation(
    liveId: live,
    liveItemId: item,
    buyer: c.buyerId,
    status: 'converted',
    jwt: c.sellerJwt,
  );
  final id = ins.firstId;
  final row = id == null ? null : await c.reqRow(id);
  if (id != null) c.createdReqIds.add(id);
  c.note('p2.control.fb.insert.converted', 'controlo INSERT facebook converted', {
    'insert': ins.brief,
    'status': row?['status'],
  }, lens: 'AD1');
  if (row?['status'] == 'converted') {
    c.hold(
      id: 'RTAD-AD1-fb-insert-converted-still-open',
      lens: 'AD1',
      severity: 'P1',
      title: 'INSERT facebook_manual converted ainda passa',
      actor: 'seller',
      pre: 'source=facebook_manual status=converted',
      repro: 'POST live_reservation_requests',
      expected: 'forced pending',
      obtained: row,
    );
  } else {
    c.block('RTAD-AD1-fb-insert-converted-still-open', 'AD1',
        'controlo INSERT facebook converted forçado pending', row?['status']);
  }
}

Future<void> isoPatchStatusSoldHub(Rtad c, String live) async {
  final item = await c.insertLiveOnlyItem(
      liveId: live, qty: 1, ref: 'P2F', jwt: c.sellerJwt);
  if (item == null) return;
  final st0 = await c.stock(item);
  final hub0 = await c.hubItem(item);
  final p = await c.patchItem(item, {'status': 'sold'});
  final after = await c.itemRow(item);
  final st1 = await c.stock(item);
  final hub1 = await c.hubItem(item);
  final disc1 = await c.hubDiscovery(item, jwt: c.buyerJwt);
  c.note('p2.patch.status-sold.iso', 'PATCH status=sold isolado', {
    'patch': p.brief,
    'item': after,
    'stock0': briefStock(st0),
    'stock1': briefStock(st1),
    'hub0': hub0 != null,
    'hub1': hub1,
    'discovery': disc1,
  }, lens: 'AD3');
  if (after?['status'] == 'sold' && hub0 != null && hub1 == null) {
    c.hold(
      id: 'RTAD-AD3-patch-status-sold-hub-iso',
      lens: 'AD3',
      severity: 'P1',
      title: 'PATCH live_items.status=sold esconde Hub público sem PI nem converted',
      actor: 'seller',
      pre: 'live_only qty=1 visível no Hub; zero reservas',
      repro: 'PATCH live_items.status=sold',
      expected: 'status sold só via mark_sold com regra de PI, ou recusa',
      obtained: {
        'status': after?['status'],
        'stock': briefStock(st1),
        'hub_public': hub1,
        'discovery': disc1,
      },
    );
  } else {
    c.block('RTAD-AD3-patch-status-sold-hub-iso', 'AD3',
        'PATCH sold não escondeu Hub ou não ficou sold', {
      'item': after,
      'hub1': hub1,
    });
  }
}

Future<void> isoMarkSoldLiveOnly(Rtad c, String live) async {
  final item = await c.insertLiveOnlyItem(
      liveId: live, qty: 1, ref: 'P2G', jwt: c.sellerJwt);
  if (item == null) return;
  final hub0 = await c.hubItem(item);
  final mk = await c.markSold(item);
  final after = await c.itemRow(item);
  final st = await c.stock(item);
  final hub1 = await c.hubItem(item);
  c.note('p2.mark_sold.live_only.iso', 'mark_sold live_only qty=1 isolado', {
    'rpc': mk.brief,
    'item': after,
    'stock': briefStock(st),
    'hub0': hub0 != null,
    'hub1': hub1,
  }, lens: 'AD4');
  if (after?['status'] == 'sold') {
    c.hold(
      id: 'RTAD-AD4-mark-sold-live-only-iso',
      lens: 'AD4',
      severity: 'P1',
      title: 'mark_sold live_only qty=1 fica sold sem PI',
      actor: 'seller',
      pre: 'live_only qty=1; zero order',
      repro: 'RPC batata_mark_live_item_sold',
      expected: 'não sold sem PI, ou sold só com order paga',
      obtained: {'item': after, 'stock': briefStock(st), 'hub': hub1},
    );
  } else {
    c.block('RTAD-AD4-mark-sold-live-only-iso', 'AD4',
        'mark_sold live_only não persiste sold (recompute)', {
      'rpc': mk.brief,
      'status': after?['status'],
      'stock': briefStock(st),
      'hub1': hub1,
    });
  }
}
