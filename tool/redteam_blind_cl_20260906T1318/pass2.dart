/// REDTEAM_BLIND_CL_LIVE_POS_CDCI_v1 — pass2 staff B1–B3 + hitch/convert C1–C4.
/// Staging only. No fixes.
import 'dart:io';

import '_rtcl.dart';

Future<void> main() async {
  final c = Rtcl.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureHelperChatOnly();
  await c.ensureHelperNone();
  await c.ensureHelperSold();

  final liveA = await c.createLive(title: '$prefix p2A');
  final liveB = await c.createLive(title: '$prefix p2B');
  final skuA =
      await c.createProduct(title: '$prefix p2 skuA', qty: 1, live: true);
  final skuB =
      await c.createProduct(title: '$prefix p2 skuB', qty: 1, live: true);
  if (liveA == null || liveB == null || skuA == null || skuB == null) {
    stderr.writeln('fixture fail');
    await c.endAllCreatedLives();
    exit(4);
  }
  final itemA = await c.createLiveItem(
    liveId: liveA,
    title: '$prefix p2 itemA',
    ref: 'RTCL-P2A',
    kind: 'live_only',
    checkoutProductId: skuA,
    quantity: 1,
  );
  final itemB = await c.createLiveItem(
    liveId: liveB,
    title: '$prefix p2 itemB',
    ref: 'RTCL-P2B',
    kind: 'live_only',
    checkoutProductId: skuB,
    quantity: 1,
  );
  if (itemA == null || itemB == null) {
    stderr.writeln('items fail');
    await c.endAllCreatedLives();
    exit(4);
  }

  // --- B1 buyer INSERT staff/helper row (self onto seller store) ---
  final b1 = await c.rest('POST', 'seller_helpers', jwt: c.buyerJwt, body: {
    'seller_id': c.sellerId,
    'helper_user_id': c.buyerId,
    'invited_by': c.buyerId,
    'display_name': '$prefix buyer-as-staff',
    'active': true,
    'invitation_status': 'accepted',
    'permissions': {
      'can_manage_chat': true,
      'can_manage_reservations': true,
      'can_mark_items_sold': true,
    },
  });
  if (b1.ok && b1.firstId != null) {
    c.createdHelperIds.add(b1.firstId!);
    c.hold(
      id: 'p2.B1.buyer.insert.helper',
      lens: 'CL1',
      severity: 'P1',
      title: 'Buyer INSERT seller_helpers em loja alheia',
      actor: 'buyer JWT',
      pre: 'RLS insert só seller_id=auth.uid()',
      repro: 'POST seller_helpers seller_id=seller helper_user_id=buyer',
      expected: '403 RLS',
      obtained: b1.brief,
    );
    c.probe(
      id: 'p2.B1.buyer.insert.helper',
      lens: 'CL1',
      payload: 'POST seller_helpers seller=V helper=B accepted+chat',
      http: b1.brief,
      verdict: 'FAIL',
    );
  } else {
    c.block('p2.B1.buyer.insert.helper', 'CL1',
        'buyer insert helper recusado (HOLD)', b1.brief);
    c.probe(
      id: 'p2.B1.buyer.insert.helper',
      lens: 'CL1',
      payload: 'POST seller_helpers seller=V helper=B accepted+chat',
      http: b1.brief,
      verdict: 'HOLD',
    );
  }

  // Buyer INSERT as if they were the shop owner (self-promote shop).
  final b1b = await c.rest('POST', 'seller_helpers', jwt: c.buyerJwt, body: {
    'seller_id': c.buyerId,
    'helper_user_id': c.buyer2Id,
    'invited_by': c.buyerId,
    'display_name': '$prefix buyer-shop',
    'active': true,
    'invitation_status': 'accepted',
    'permissions': {'can_manage_chat': true},
  });
  c.note('p2.B1.buyer.self_shop', 'buyer cria helper na própria identidade',
      b1b.brief, lens: 'CL1');

  // --- B2 helper self-escalate can_manage_chat ---
  final h0rows = await c.rest(
    'GET',
    'seller_helpers?helper_user_id=eq.${c.helperNoneId}&select=id,permissions,active,invitation_status',
    service: true,
  );
  final hid0 = h0rows.map?['id']?.toString();
  if (hid0 != null) {
    final before = h0rows.map?['permissions'];
    final esc = await c.rest(
      'PATCH',
      'seller_helpers?id=eq.$hid0',
      jwt: c.helperNoneJwt,
      body: {
        'permissions': {
          'can_manage_chat': true,
          'can_manage_reservations': true,
          'can_mark_items_sold': true,
        },
      },
    );
    final after = await c.rest(
      'GET',
      'seller_helpers?id=eq.$hid0&select=permissions,active',
      service: true,
    );
    final perms = after.map?['permissions'];
    final got = perms is Map && perms['can_manage_chat'] == true;
    final had = before is Map && before['can_manage_chat'] == true;
    if (esc.ok && got && !had) {
      c.hold(
        id: 'p2.B2.helper.self_escalate',
        lens: 'CL1',
        severity: 'P1',
        title: 'Helper zero-perms PATCH can_manage_chat self',
        actor: 'helper zero JWT',
        pre: 'permissions todas false; trigger SEC-014',
        repro: 'PATCH seller_helpers permissions can_manage_chat=true',
        expected: 'RLS/trigger bloqueia; perms inalteradas',
        obtained: {'patch': esc.brief, 'before': before, 'after': perms},
      );
      c.probe(
        id: 'p2.B2.helper.self_escalate',
        lens: 'CL1',
        payload: 'PATCH helper0 permissions can_manage_chat=true',
        http: esc.brief,
        verdict: 'FAIL',
        extra: {'after': perms},
      );
    } else {
      c.block('p2.B2.helper.self_escalate', 'CL1',
          'helper self-escalate recusado (HOLD)', {
        'patch': esc.brief,
        'before': before,
        'after': perms,
      });
      c.probe(
        id: 'p2.B2.helper.self_escalate',
        lens: 'CL1',
        payload: 'PATCH helper0 permissions can_manage_chat=true',
        http: esc.brief,
        verdict: 'HOLD',
        extra: {'after': perms},
      );
    }
  }

  // Chat-only helper also tries extra perms.
  final h1rows = await c.rest(
    'GET',
    'seller_helpers?helper_user_id=eq.${c.helperId}&select=id,permissions',
    service: true,
  );
  final hid1 = h1rows.map?['id']?.toString();
  if (hid1 != null) {
    final esc1 = await c.rest(
      'PATCH',
      'seller_helpers?id=eq.$hid1',
      jwt: c.helperJwt,
      body: {
        'permissions': {
          'can_manage_chat': true,
          'can_mark_items_sold': true,
          'can_manage_reservations': true,
        },
      },
    );
    final after1 = await c.rest(
      'GET',
      'seller_helpers?id=eq.$hid1&select=permissions',
      service: true,
    );
    final p1 = after1.map?['permissions'];
    final sold = p1 is Map && p1['can_mark_items_sold'] == true;
    if (esc1.ok && sold) {
      c.hold(
        id: 'p2.B2b.helper.chat.escalate_sold',
        lens: 'CL1',
        severity: 'P1',
        title: 'Helper chat-only PATCH can_mark_items_sold',
        actor: 'helper chat JWT',
        pre: 'só can_manage_chat',
        repro: 'PATCH seller_helpers can_mark_items_sold',
        expected: 'perms inalteradas',
        obtained: {'patch': esc1.brief, 'after': p1},
      );
    } else {
      c.block('p2.B2b.helper.chat.escalate_sold', 'CL1',
          'helper chat não alarga perms', esc1.brief);
    }
  }

  // --- B3 helper zero-perms anuncia FOMO ---
  final b3 = await c.rpc(
    'batata_live_system_message',
    {
      'p_live_id': liveA,
      'p_body': 'ultimo pezzo',
      'p_sender_label': 'Sistema',
    },
    jwt: c.helperNoneJwt,
  );
  final b3ok = b3.map?['ok'] == true;
  if (b3ok) {
    c.hold(
      id: 'p2.B3.helper0.fomo',
      lens: 'CL2',
      severity: 'P2',
      title: 'Helper zero-perms publicou FOMO system',
      actor: 'helper zero JWT',
      pre: 'can_manage_chat=false',
      repro: 'rpc batata_live_system_message ultimo pezzo',
      expected: 'not_allowed',
      obtained: b3.brief,
    );
    c.probe(
      id: 'p2.B3.helper0.fomo',
      lens: 'CL2',
      payload: 'helper0 RPC ultimo pezzo',
      http: b3.brief,
      verdict: 'FAIL',
    );
  } else {
    c.block('p2.B3.helper0.fomo', 'CL2', 'helper0 FOMO recusado (HOLD)',
        b3.brief);
    c.probe(
      id: 'p2.B3.helper0.fomo',
      lens: 'CL2',
      payload: 'helper0 RPC ultimo pezzo',
      http: b3.brief,
      verdict: 'HOLD',
    );
  }

  // --- C2 convert sem PI ---
  final ridA = await c.insertReservation(
    liveId: liveA,
    liveItemId: itemA,
    jwt: c.buyerJwt,
    buyer: c.buyerId,
  );
  if (ridA == null) {
    stderr.writeln('pending A fail');
    await c.endAllCreatedLives();
    exit(4);
  }
  await c.rest(
    'PATCH',
    'live_reservation_requests?id=eq.$ridA',
    jwt: c.sellerJwt,
    body: {'status': 'accepted'},
  );
  final convRpc = await c.rpc(
    'batata_live_reservation_stripe_convert',
    {'p_request_id': ridA},
    jwt: c.sellerJwt,
  );
  final afterConv = await c.rest(
    'GET',
    'live_reservation_requests?id=eq.$ridA&select=id,status',
    service: true,
  );
  final st = afterConv.map?['status']?.toString();
  if (convRpc.map?['ok'] == true && st == 'converted') {
    c.hold(
      id: 'p2.C2.convert.nopi',
      lens: 'CL1',
      severity: 'P0',
      title: 'stripe_convert sem PI deixou status=converted',
      actor: 'seller JWT',
      pre: 'accepted, sem order paga',
      repro: 'rpc batata_live_reservation_stripe_convert',
      expected: 'recusa; status≠converted',
      obtained: {'rpc': convRpc.brief, 'row': afterConv.map},
    );
    c.probe(
      id: 'p2.C2.convert.nopi',
      lens: 'CL1',
      payload: 'stripe_convert accepted sem PI',
      http: convRpc.brief,
      verdict: 'FAIL',
    );
  } else {
    c.block('p2.C2.convert.nopi', 'CL1', 'convert sem PI recusado (HOLD)',
        {'rpc': convRpc.brief, 'status': st});
    c.probe(
      id: 'p2.C2.convert.nopi',
      lens: 'CL1',
      payload: 'stripe_convert accepted sem PI',
      http: convRpc.brief,
      verdict: 'HOLD',
      extra: {'status': st},
    );
  }

  // --- C3 convert PI alheio (order live A → reserva live B) ---
  final ridB = await c.insertReservation(
    liveId: liveB,
    liveItemId: itemB,
    jwt: c.buyer2Jwt,
    buyer: c.buyer2Id,
  );
  if (ridB != null) {
    await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$ridB',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
  }
  final planted = await c.rest('POST', 'orders', service: true, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': skuA,
    'live_id': liveA,
    'live_item_id': itemA,
    'quantity': 1,
    'price_total': 9,
    'status': 'pago',
    'payment_method': 'MB WAY',
    'shipping_method': 'entrega em mão',
    'stripe_payment_intent_id': 'pi_rtcl_stolen_${stamp}_A',
    'amount_paid_cents': 900,
  });
  if (planted.firstId != null) c.createdOrderIds.add(planted.firstId!);
  if (planted.ok && planted.firstId != null && ridB != null) {
    final recCross = await c.rpc(
      'batata_live_reconcile_stripe_order',
      {
        'p_order_id': planted.firstId,
        'p_reservation_request_id': ridB,
      },
      jwt: c.sellerJwt,
    );
    final afterCross = await c.rest(
      'GET',
      'live_reservation_requests?id=eq.$ridB&select=id,status,buyer_id,live_id',
      service: true,
    );
    if (recCross.map?['ok'] == true &&
        afterCross.map?['status'] == 'converted') {
      c.hold(
        id: 'p2.C3.convert.pi_alheio',
        lens: 'CL1',
        severity: 'P0',
        title: 'reconcile order live A → reserva live B converted',
        actor: 'seller JWT',
        pre: 'PI/order de outra live e outro item',
        repro: 'rpc batata_live_reconcile_stripe_order orderA + resB',
        expected: 'mismatch recusa',
        obtained: {'rpc': recCross.brief, 'res': afterCross.map},
      );
      c.probe(
        id: 'p2.C3.convert.pi_alheio',
        lens: 'CL1',
        payload: 'reconcile PI liveA → res liveB',
        http: recCross.brief,
        verdict: 'FAIL',
      );
    } else {
      c.block('p2.C3.convert.pi_alheio', 'CL1',
          'reconcile PI alheio recusado (HOLD)', recCross.brief);
      c.probe(
        id: 'p2.C3.convert.pi_alheio',
        lens: 'CL1',
        payload: 'reconcile PI liveA → res liveB',
        http: recCross.brief,
        verdict: 'HOLD',
      );
    }
  } else {
    c.probe(
      id: 'p2.C3.convert.pi_alheio',
      lens: 'CL1',
      payload: 'reconcile PI liveA → res liveB',
      http: planted.brief,
      verdict: 'HOLD',
      extra: {'reason': 'plant/ridB fail'},
    );
  }

  // --- C1 hitch qty>stock ---
  final liveH = await c.createLive(title: '$prefix p2 hitch');
  final skuH =
      await c.createProduct(title: '$prefix hitch sku', qty: 1, live: true);
  if (liveH != null && skuH != null) {
    final li1 = await c.createLiveItem(
      liveId: liveH,
      title: '$prefix hitch A',
      ref: 'RTCL-HA',
      kind: 'marketplace_product',
      productId: skuH,
    );
    final li2 = await c.createLiveItem(
      liveId: liveH,
      title: '$prefix hitch B',
      ref: 'RTCL-HB',
      kind: 'live_only',
      checkoutProductId: skuH,
      quantity: 1,
    );
    if (li1 != null) {
      await c.rest(
        'PATCH',
        'live_items?id=eq.$li1',
        service: true,
        body: {'checkout_product_id': null, 'logical_item_id': null},
        prefer: 'return=minimal',
      );
    }
    HttpHit? a2;
    Map<String, dynamic>? row1;
    Map<String, dynamic>? row2;
    if (li1 != null && li2 != null) {
      final r1 = await c.insertReservation(
        liveId: liveH,
        liveItemId: li1,
        jwt: c.buyerJwt,
        buyer: c.buyerId,
      );
      if (r1 != null) {
        await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$r1',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
      }
      final r2 = await c.insertReservation(
        liveId: liveH,
        liveItemId: li2,
        jwt: c.buyer2Jwt,
        buyer: c.buyer2Id,
      );
      if (r2 != null) {
        a2 = await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$r2',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        );
      }
      row1 = r1 == null
          ? null
          : (await c.rest(
              'GET',
              'live_reservation_requests?id=eq.$r1&select=id,status,requested_qty',
              service: true,
            ))
              .map;
      row2 = r2 == null
          ? null
          : (await c.rest(
              'GET',
              'live_reservation_requests?id=eq.$r2&select=id,status,requested_qty',
              service: true,
            ))
              .map;
      if (row1?['status'] == 'accepted' && row2?['status'] == 'accepted') {
        c.hold(
          id: 'p2.C1.hitch.qty_stock',
          lens: 'CL4',
          severity: 'P1',
          title: 'Dois accepts no mesmo SKU hitch (qty=1)',
          actor: 'seller JWT',
          pre: 'qty produto=1; marketplace+live_only',
          repro: 'accept LI1 depois LI2',
          expected: '2º qty_exceeds_stock',
          obtained: {'r1': row1, 'r2': row2, 'a2': a2?.brief},
        );
        c.probe(
          id: 'p2.C1.hitch.qty_stock',
          lens: 'CL4',
          payload: 'hitch marketplace+live_only qty=1 two accepts',
          http: a2?.brief ?? 'n/a',
          verdict: 'FAIL',
          extra: {'r1': row1, 'r2': row2},
        );
      } else {
        c.block('p2.C1.hitch.qty_stock', 'CL4',
            '2º accept recusado (HOLD hitch)', {
          'r1': row1,
          'r2': row2,
          'a2': a2?.brief,
        });
        c.probe(
          id: 'p2.C1.hitch.qty_stock',
          lens: 'CL4',
          payload: 'hitch marketplace+live_only qty=1 two accepts',
          http: a2?.brief ?? 'n/a',
          verdict: 'HOLD',
          extra: {'r1': row1, 'r2': row2},
        );
      }
    }
  }

  // qty>stock on single item
  final liveQ = await c.createLive(title: '$prefix p2 qty');
  final skuQ =
      await c.createProduct(title: '$prefix p2 qty sku', qty: 1, live: true);
  final liQ = (liveQ == null || skuQ == null)
      ? null
      : await c.createLiveItem(
          liveId: liveQ,
          title: '$prefix qty over',
          ref: 'RTCL-QO',
          kind: 'live_only',
          checkoutProductId: skuQ,
          quantity: 1,
        );
  if (liveQ != null && liQ != null) {
    final over = await c.insertReservation(
      liveId: liveQ,
      liveItemId: liQ,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
      qty: 5,
    );
    if (over != null) {
      final accOver = await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$over',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
      final rowOver = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$over&select=id,status,requested_qty',
        service: true,
      );
      final qty = rowOver.map?['requested_qty'] as num? ?? 0;
      if (rowOver.map?['status'] == 'accepted' && qty > 1) {
        c.hold(
          id: 'p2.C1b.qty.over_stock',
          lens: 'CL5',
          severity: 'P1',
          title: 'Accept qty=5 em item qty=1',
          actor: 'seller JWT',
          pre: 'live_only quantity=1',
          repro: 'POST reservation requested_qty=5 + PATCH accepted',
          expected: 'qty_exceeds_stock / coerção a 1',
          obtained: {'row': rowOver.map, 'accept': accOver.brief},
        );
        c.probe(
          id: 'p2.C1b.qty.over_stock',
          lens: 'CL5',
          payload: 'requested_qty=5 accept item qty=1',
          http: accOver.brief,
          verdict: 'FAIL',
          extra: rowOver.map,
        );
      } else {
        c.block('p2.C1b.qty.over_stock', 'CL5', 'qty>stock não accepted>1', {
          'row': rowOver.map,
          'accept': accOver.brief,
        });
        c.probe(
          id: 'p2.C1b.qty.over_stock',
          lens: 'CL5',
          payload: 'requested_qty=5 accept item qty=1',
          http: accOver.brief,
          verdict: 'HOLD',
          extra: rowOver.map,
        );
      }
    }
  }

  // --- C4 end_live ∥ accept ---
  final liveR = await c.createLive(title: '$prefix race end');
  final skuR =
      await c.createProduct(title: '$prefix race sku', qty: 1, live: true);
  final liR = (liveR == null || skuR == null)
      ? null
      : await c.createLiveItem(
          liveId: liveR,
          title: '$prefix race item',
          ref: 'RTCL-RC',
          kind: 'live_only',
          checkoutProductId: skuR,
          quantity: 1,
        );
  if (liveR != null && liR != null) {
    final rRace = await c.insertReservation(
      liveId: liveR,
      liveItemId: liR,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    if (rRace != null) {
      final raced = await Future.wait([
        c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$rRace',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        ),
        c.rest(
          'PATCH',
          'lives?id=eq.$liveR',
          service: true,
          body: {'status': 'ended', 'is_active': false},
        ),
        c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$rRace',
          jwt: c.sellerJwt,
          body: {'status': 'accepted'},
        ),
      ]);
      final afterRace = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$rRace&select=id,status',
        service: true,
      );
      final liveAfter = await c.rest(
        'GET',
        'lives?id=eq.$liveR&select=id,status,is_active',
        service: true,
      );
      final ended = liveAfter.map?['status']?.toString() == 'ended' &&
          liveAfter.map?['is_active'] != true;
      final accepted = afterRace.map?['status']?.toString() == 'accepted';
      if (ended && accepted) {
        c.note(
          'p2.C4.race.accept.won',
          'accept ganhou a race contra end',
          afterRace.map,
          lens: 'CL6',
        );
        c.probe(
          id: 'p2.C4.end_parallel_accept',
          lens: 'CL6',
          payload: 'end_live ∥ PATCH accepted',
          http: raced.map((h) => h.brief).join(' | '),
          verdict: 'HOLD',
          extra: {
            'note': 'accept durante end não é P0 se stock/caixa intactos; '
                'reserva accepted em live ended — anotar',
            'res': afterRace.map,
            'live': liveAfter.map,
          },
        );
      } else {
        c.block('p2.C4.end_parallel_accept', 'CL6',
            'end ganhou; accept não ficou accepted', {
          'res': afterRace.map,
          'live': liveAfter.map,
          'hits': raced.map((h) => h.brief).toList(),
        });
        c.probe(
          id: 'p2.C4.end_parallel_accept',
          lens: 'CL6',
          payload: 'end_live ∥ PATCH accepted',
          http: raced.map((h) => h.brief).join(' | '),
          verdict: 'HOLD',
          extra: {'res': afterRace.map, 'live': liveAfter.map},
        );
      }

      final accLate = await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$rRace',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
      final lateRow = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$rRace&select=id,status',
        service: true,
      );
      if (!accepted && lateRow.map?['status'] == 'accepted') {
        c.hold(
          id: 'p2.C4.accept.after.end',
          lens: 'CL6',
          severity: 'P1',
          title: 'Accept depois de live ended',
          actor: 'seller JWT',
          pre: 'status=ended is_active=false',
          repro: 'PATCH accepted após end',
          expected: 'live_ended',
          obtained: {'patch': accLate.brief, 'row': lateRow.map},
        );
      } else {
        c.block('p2.C4.accept.after.end', 'CL6',
            'accept pós-end recusado ou já decided', accLate.brief);
      }
    }
  }

  await dumpJson('${outDir()}/pass2.json', {
    'auditor': 'REDTEAM_BLIND_CL_LIVE_POS_CDCI_v1',
    'prefix': prefix,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'probes': c.probes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'pass2 done findings=${c.findings.length} blocked=${c.blocked.length} '
      'probes=${c.probes.length}');
}
