/// BN pass2 — verify P1 pool, helper escalate, mux race, caixa leftovers.
import 'dart:io';

import '_rtbn.dart';

Future<void> main() async {
  final c = Rtbn.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  const liveA = '7f8c0a1b-5a41-4399-9ffe-aee37847b318';
  const itemPool1 = '46c5aa18-8f48-44ea-a991-978a7fe594c1';
  const itemPool2 = '6de541a1-2736-47df-acbb-33ca00276182';
  const reqPool1 = '954cc131-3a14-4bf1-b2c2-a33b234826f0';
  const reqPool2 = '7b54ee0f-3985-4a8a-bbad-b5d4e9bfea53';
  const restConvId = '5cf3a117-9e20-49d5-a154-530dc172e9ee';
  const jwtOrder = '3bdaf76b-276e-4131-af00-6d66d4b07812';
  const svcOrder = 'c7f0cdb5-a002-44b3-b28d-0a9ba4c46fd0';
  const hitchItem = 'eb5ee2ac-6c2c-4fd7-b7b5-67bed4c22b55';
  const skuExtra = '05ba755e-b70d-4a55-9c43-571e4c080893';
  const helperChatUser = 'b811dac8-2216-498d-8a35-3b8155004a2c';

  // ── observe pool P1 ──────────────────────────────────────────────────
  final r1 = await c.reqRow(reqPool1);
  final r2 = await c.reqRow(reqPool2);
  final i1 = await c.itemRow(itemPool1);
  final i2 = await c.itemRow(itemPool2);
  final st1 = await c.stock(itemPool1, service: true);
  final st2 = await c.stock(itemPool2, service: true);
  final rem = await c.rpc('batata_ref_history_remaining_qty', {
    'p_seller_id': c.sellerId,
    'p_logical_item_id': itemPool1,
  }, service: true);
  final base = await c.rpc('batata_ref_history_pool_base_qty', {
    'p_seller_id': c.sellerId,
    'p_logical_item_id': itemPool1,
  }, service: true);
  c.note('p2.pool.obs', 'pool observe', {
    'r1': r1,
    'r2': r2,
    'i1': i1,
    'i2': i2,
    'st1': st1.map,
    'st2': st2.map,
    'remaining': rem.json,
    'base': base.json,
  }, lens: 'BN5');

  final bothAcc = r1?['status'] == 'accepted' && r2?['status'] == 'accepted';
  final sameLogical = i1?['logical_item_id']?.toString() == itemPool1 &&
      i2?['logical_item_id']?.toString() == itemPool1;
  final remN = rem.json is num
      ? rem.json as num
      : num.tryParse('${rem.json}') ?? 999;
  if (bothAcc && sameLogical) {
    c.hold(
      id: 'P1-BN5-qty-pool-double-accept',
      lens: 'BN5',
      severity: remN <= 0 ? 'P1' : 'P2',
      title:
          'Dois live_only mesmo logical_item_id ambos accepted (pool base=1)',
      actor: 'seller JWT accept + service fixture logical_item_id',
      pre: 'itemPool2.logical_item_id=itemPool1; qty=1 cada',
      repro: 'PATCH accepted ×2; rpc remaining_qty',
      expected: '2.º accept bloqueado; remaining>=0 coerente com 1 hold',
      obtained: {
        's1': r1?['status'],
        's2': r2?['status'],
        'logical1': i1?['logical_item_id'],
        'logical2': i2?['logical_item_id'],
        'base': base.json,
        'remaining': rem.json,
        'avail1': st1.map?['available_qty'],
        'avail2': st2.map?['available_qty'],
        'reserved1': st1.map?['reserved_accepted_qty'],
        'reserved2': st2.map?['reserved_accepted_qty'],
      },
    );
  } else {
    c.block('P2-BN5-pool-not-both', 'BN5', 'pool not both accepted', {
      'r1': r1?['status'],
      'r2': r2?['status'],
      'logical': [i1?['logical_item_id'], i2?['logical_item_id']],
    });
  }

  // seller-reachable: two live_only SAME ref via seller JWT
  final liveNew = await c.insertLive();
  if (liveNew != null) {
    final a = await c.insertLiveOnlyItem(
      liveId: liveNew,
      qty: 1,
      ref: 'BNSAME',
      jwt: c.sellerJwt,
    );
    final b = await c.insertLiveOnlyItem(
      liveId: liveNew,
      qty: 1,
      ref: 'BNSAME',
      jwt: c.sellerJwt,
    );
    c.note('p2.sameref.insert', 'seller same ref', {
      'a': a,
      'b': b,
      'rowA': a == null ? null : await c.itemRow(a),
      'rowB': b == null ? null : await c.itemRow(b),
    }, lens: 'BN5');
    if (a != null && b != null) {
      final ra = await c.insertReservation(
        liveId: liveNew,
        liveItemId: a,
        buyer: c.buyerId,
        jwt: c.buyerJwt,
      );
      final rb = await c.insertReservation(
        liveId: liveNew,
        liveItemId: b,
        buyer: c.buyer2Id,
        jwt: c.buyer2Jwt,
      );
      final ia = ra.firstId;
      final ib = rb.firstId;
      if (ia != null && ib != null) {
        final p1 = await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$ia',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
        final p2 = await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$ib',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
        final sa = await c.reqRow(ia);
        final sb = await c.reqRow(ib);
        final n = [sa?['status'], sb?['status']]
            .where((s) => s == 'accepted')
            .length;
        final rowA = await c.itemRow(a);
        final rowB = await c.itemRow(b);
        final shared = rowA?['logical_item_id'] != null &&
            rowA?['logical_item_id'] == rowB?['logical_item_id'];
        if (n >= 2 && shared) {
          c.hold(
            id: 'P1-BN5-same-ref-double-accept',
            lens: 'BN5',
            severity: 'P1',
            title:
                'Seller JWT dois live_only mesmo ref_code + logical partilhado, 2 accepted',
            actor: 'seller JWT',
            pre: 'dois INSERT live_only ref=BNSAME qty=1',
            repro: 'PATCH accepted ×2',
            expected: '2.º accept qty_exceeds_stock se pool partilhado',
            obtained: {
              'n': n,
              'shared': shared,
              'logA': rowA?['logical_item_id'],
              'logB': rowB?['logical_item_id'],
              'p1': p1.brief,
              'p2': p2.brief,
            },
          );
        } else {
          c.block('BN5-sameref', 'BN5', 'same ref double', {
            'n': n,
            'shared': shared,
            'logA': rowA?['logical_item_id'],
            'logB': rowB?['logical_item_id'],
            'p1': p1.brief,
            'p2': p2.brief,
          });
        }
      }

      // seller PATCH logical_item_id of B onto A
      if (a != null && b != null) {
        final patchLog = await c.rest(
          'PATCH',
          'live_items?id=eq.$b',
          jwt: c.sellerJwt,
          body: {'logical_item_id': a},
        );
        c.note('p2.logical.patch', 'seller PATCH logical_item_id', patchLog.brief,
            lens: 'BN5');
      }
    }

    // ── BN6 race complete-mux-live ∥ accept ────────────────────────────
    final raceItem = await c.insertLiveOnlyItem(
      liveId: liveNew,
      qty: 1,
      ref: 'BNMUXRACE',
      service: true,
    );
    if (raceItem != null) {
      final rp = await c.insertReservation(
        liveId: liveNew,
        liveItemId: raceItem,
        buyer: c.buyerId,
        jwt: c.buyerJwt,
      );
      final rid = rp.firstId;
      if (rid != null) {
        final raced = await parallel([
          c.edge('complete-mux-live', {'live_id': liveNew}, jwt: c.sellerJwt),
          c.rest(
            'PATCH',
            'live_reservation_requests?id=eq.$rid',
            jwt: c.sellerJwt,
            body: {'status': 'accepted'},
          ),
        ]);
        final liveAfter = await c.rest(
          'GET',
          'lives?id=eq.$liveNew&select=id,status,is_active',
          service: true,
        );
        final reqAfter = await c.reqRow(rid);
        final ended =
            '${liveAfter.map?['status']}'.toLowerCase() == 'ended';
        final accepted = reqAfter?['status'] == 'accepted';
        c.note('p2.race.mux', 'complete-mux || accept', {
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
            pre: 'pending qty=1',
            repro: 'Future.wait complete-mux-live + PATCH accepted',
            expected: 'accept falha live_ended se live já ended',
            obtained: {
              'ended': ended,
              'accepted': accepted,
              'mux': raced[0].brief,
              'req': reqAfter,
            },
          );
        } else {
          c.block('BN6-mux-race', 'BN6', 'mux end||accept', {
            'ended': ended,
            'accepted': accepted,
            'mux': raced[0].brief,
          });
        }
      }
    }
  }

  // ── helper self-escalate ─────────────────────────────────────────────
  final chatH = await c.ensureNamedHelper(tag: 'hc', pass: 'Rtbn1903hc!xK');
  c.helperChatJwt = chatH['jwt'];
  c.helperChatId = chatH['id'] ?? helperChatUser;
  final hrows = await c.rest(
    'GET',
    'seller_helpers?helper_user_id=eq.${c.helperChatId}&select=id,permissions,active,invitation_status',
    service: true,
  );
  c.note('p2.helper.rows', 'helper chat rows', hrows.brief, lens: 'BN2');
  final hid = hrows.map?['id']?.toString();
  if (hid != null) {
    final before = hrows.map?['permissions'];
    final esc = await c.rest(
      'PATCH',
      'seller_helpers?id=eq.$hid',
      jwt: c.helperChatJwt,
      body: {
        'permissions': {
          'can_mark_items_sold': true,
          'can_manage_reservations': true,
          'can_manage_chat': true,
        },
      },
    );
    final after = await c.rest(
      'GET',
      'seller_helpers?id=eq.$hid&select=permissions',
      service: true,
    );
    final perms = after.map?['permissions'];
    final got = perms is Map && perms['can_mark_items_sold'] == true;
    final had = before is Map && before['can_mark_items_sold'] == true;
    if (esc.ok && got && !had) {
      c.hold(
        id: 'P1-BN2-helper-self-escalate',
        lens: 'BN2',
        severity: 'P1',
        title: 'Helper PATCH permissions self-escalate can_mark_items_sold',
        actor: 'helper chat JWT',
        pre: 'helper só can_manage_chat',
        repro: 'PATCH seller_helpers permissions',
        expected: 'RLS bloqueia',
        obtained: {'patch': esc.brief, 'before': before, 'after': perms},
      );
    } else {
      c.block('BN2-05', 'BN2', 'helper self-escalate', {
        'patch': esc.brief,
        'before': before,
        'after': perms,
      });
    }
  }

  // ── FOMO persist check ───────────────────────────────────────────────
  final msgs = await c.msgs(liveA, limit: 30);
  final fomoHits = msgs
      .where((m) {
        final b = '${m['body']}';
        return b.contains('snapped') ||
            b.contains('claimed') ||
            b.contains('ｃｏｍｐｒｏｕ') ||
            b.contains('\u043E') ||
            b.contains('grabbed') ||
            b.contains('took it');
      })
      .map((m) => m['body'])
      .toList();
  c.note('p2.fomo.persist', 'FOMO still in live_messages', {
    'n': fomoHits.length,
    'sample': fomoHits.take(8).toList(),
  }, lens: 'BN2');

  final accMsg = msgs.any((m) => '${m['body']}'.contains('Reserva aceite'));
  c.note('p2.accept.msg', 'accept_broadcast still posted', accMsg, lens: 'BN1');

  // ── REST converted coerced? ──────────────────────────────────────────
  final convRow = await c.reqRow(restConvId);
  c.note('p2.rest.converted', 'REST insert converted actual status', convRow,
      lens: 'BN1');

  // ── hitch leftover ───────────────────────────────────────────────────
  final hitch = await c.itemRow(hitchItem);
  final extra = await c.productRow(skuExtra);
  c.note('p2.hitch', 'hitch after mark_sold', {
    'item': hitch,
    'sku': extra,
  }, lens: 'BN4');

  // ── caixa leftover orders ────────────────────────────────────────────
  final oJwt = await c.orderRow(jwtOrder);
  final oSvc = await c.orderRow(svcOrder);
  c.note('p2.orders', 'fake pago leftover', {
    'jwt': oJwt,
    'svc': oSvc,
  }, lens: 'BN8');
  final w = await c.wallets();
  c.note('p2.wallets', 'wallets', w, lens: 'BN8');

  // cancel leftover pago fixtures if still pago (cleanup observe only)
  for (final oid in [jwtOrder, svcOrder]) {
    await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      service: true,
      body: {'status': 'cancelado'},
      prefer: 'return=minimal',
    );
  }

  await c.endLives();

  final open = c.findings.where((f) => f['proven'] == true).toList();
  await dumpJson('${outDir()}/pass2.json', {
    'auditor': 'REDTEAM_BLIND_BN_LIVE_POS_BFBK_v1',
    'stamp': stamp,
    'findings': open,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'PASS2 done findings=${open.length} blocked=${c.blocked.length}');
}
