/// BN pass3 — seller JWT logical_item_id hitch + pool double-accept; mux race with mux_live_id.
import 'dart:io';

import '_rtbn.dart';

Future<void> main() async {
  final c = Rtbn.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();

  final live = await c.insertLive(
    muxLiveId: 'bnMux$stamp',
    muxPlayback: 'bnPlay$stamp',
    muxStreamKey: 'bnKey$stamp',
  );
  if (live == null) {
    stderr.writeln('no live');
    return;
  }

  final a = await c.insertLiveOnlyItem(
    liveId: live,
    qty: 1,
    ref: 'BNLOGA',
    jwt: c.sellerJwt,
  );
  final b = await c.insertLiveOnlyItem(
    liveId: live,
    qty: 1,
    ref: 'BNLOGB',
    jwt: c.sellerJwt,
  );
  if (a == null || b == null) {
    c.note('p3.items.fail', 'insert', {'a': a, 'b': b}, lens: 'BN5');
    await dumpJson('${outDir()}/pass3.json', {'notes': c.notes});
    return;
  }

  final patch = await c.rest(
    'PATCH',
    'live_items?id=eq.$b',
    jwt: c.sellerJwt,
    body: {'logical_item_id': a},
  );
  final rowA = await c.itemRow(a);
  final rowB = await c.itemRow(b);
  c.note('p3.logical', 'PATCH logical JWT', {
    'patch': patch.brief,
    'rowA': rowA,
    'rowB': rowB,
  }, lens: 'BN5');

  final pa = await c.insertReservation(
    liveId: live,
    liveItemId: a,
    buyer: c.buyerId,
    jwt: c.buyerJwt,
  );
  final pb = await c.insertReservation(
    liveId: live,
    liveItemId: b,
    buyer: c.buyer2Id,
    jwt: c.buyer2Jwt,
  );
  final ia = pa.firstId;
  final ib = pb.firstId;
  HttpHit? acc1;
  HttpHit? acc2;
  Map<String, dynamic>? sa;
  Map<String, dynamic>? sb;
  if (ia != null && ib != null) {
    acc1 = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$ia',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    acc2 = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$ib',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    sa = await c.reqRow(ia);
    sb = await c.reqRow(ib);
  }

  final rem = await c.rpc('batata_ref_history_remaining_qty', {
    'p_seller_id': c.sellerId,
    'p_logical_item_id': a,
  }, jwt: c.sellerJwt);
  final base = await c.rpc('batata_ref_history_pool_base_qty', {
    'p_seller_id': c.sellerId,
    'p_logical_item_id': a,
  }, jwt: c.sellerJwt);
  final stA = await c.stock(a, jwt: c.sellerJwt);
  final stB = await c.stock(b, jwt: c.sellerJwt);

  final nAcc = [sa?['status'], sb?['status']]
      .where((s) => s == 'accepted')
      .length;
  final linked = rowB?['logical_item_id']?.toString() == a;
  c.note('p3.pool.result', 'double accept after logical hitch', {
    'nAcc': nAcc,
    'linked': linked,
    's1': sa?['status'],
    's2': sb?['status'],
    'acc1': acc1?.brief,
    'acc2': acc2?.brief,
    'base': base.json,
    'remaining': rem.json,
    'stA': stA.map,
    'stB': stB.map,
  }, lens: 'BN5');

  if (nAcc >= 2 && linked) {
    c.hold(
      id: 'P1-BN5-logical-hitch-double-accept',
      lens: 'BN5',
      severity: 'P1',
      title:
          'Seller JWT PATCH logical_item_id (refs distintas) + 2 accepted em pool base=1',
      actor: 'seller JWT',
      pre: 'dois live_only qty=1 refs BNLOGA/BNLOGB; PATCH B.logical=A.id',
      repro:
          'PATCH live_items.logical_item_id; PATCH reservations accepted ×2',
      expected: '2.º accept qty_exceeds_stock (pool remaining)',
      obtained: {
        'nAcc': nAcc,
        'base': base.json,
        'remaining': rem.json,
        'availA': stA.map?['available_qty'],
        'availB': stB.map?['available_qty'],
        'resA': stA.map?['reserved_accepted_qty'],
        'resB': stB.map?['reserved_accepted_qty'],
        's1': sa?['status'],
        's2': sb?['status'],
      },
    );
  } else {
    c.block('BN5-logical-hitch', 'BN5', 'logical hitch double', {
      'nAcc': nAcc,
      'linked': linked,
      'acc1': acc1?.brief,
      'acc2': acc2?.brief,
      'remaining': rem.json,
    });
  }

  // mux race with mux_live_id present
  final raceItem = await c.insertLiveOnlyItem(
    liveId: live,
    qty: 1,
    ref: 'BNMUX3',
    jwt: c.sellerJwt,
  );
  if (raceItem != null) {
    final rp = await c.insertReservation(
      liveId: live,
      liveItemId: raceItem,
      buyer: c.buyerId,
      jwt: c.buyerJwt,
    );
    final rid = rp.firstId;
    if (rid != null) {
      final raced = await parallel([
        c.edge('complete-mux-live', {'live_id': live}, jwt: c.sellerJwt),
        c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$rid',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        ),
      ]);
      final liveAfter = await c.rest(
        'GET',
        'lives?id=eq.$live&select=id,status,is_active,mux_live_id',
        service: true,
      );
      final reqAfter = await c.reqRow(rid);
      final ended = '${liveAfter.map?['status']}'.toLowerCase() == 'ended';
      final accepted = reqAfter?['status'] == 'accepted';
      c.note('p3.mux.race', 'complete-mux || accept', {
        'mux': raced[0].brief,
        'accept': raced[1].brief,
        'live': liveAfter.map,
        'req': reqAfter?['status'],
      }, lens: 'BN6');
      if (ended && accepted) {
        c.hold(
          id: 'P2-BN6-mux-end-accept',
          lens: 'BN6',
          severity: 'P2',
          title:
              'Race complete-mux-live ∥ accept deixa reserva accepted em live ended',
          actor: 'seller JWT ×2',
          pre: 'live com mux_live_id dummy; pending qty=1',
          repro: 'Future.wait complete-mux-live + PATCH accepted',
          expected: 'accept falha live_ended se live já ended',
          obtained: {
            'ended': ended,
            'accepted': accepted,
            'mux': raced[0].brief,
          },
        );
      } else {
        c.block('BN6-mux3', 'BN6', 'mux race', {
          'ended': ended,
          'accepted': accepted,
          'mux': raced[0].brief,
        });
      }
    }
  }

  await c.endLives();

  final open = c.findings.where((f) => f['proven'] == true).toList();
  await dumpJson('${outDir()}/pass3.json', {
    'auditor': 'REDTEAM_BLIND_BN_LIVE_POS_BFBK_v1',
    'stamp': stamp,
    'findings': open,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'PASS3 done findings=${open.length} blocked=${c.blocked.length}');
}
