/// REDTEAM_BLIND_DJ_LIVE_STOCK_POS_DBDG_v1 — stock/hitch/convert/rifa.
/// Staging only. No fixes. No Fase 4.
import 'dart:io';

import '_rtdj.dart';

bool insertOk(HttpHit h) =>
    h.ok ||
    h.status == 409 ||
    h.body.contains('23505') ||
    h.body.toLowerCase().contains('duplicate');

Future<void> main() async {
  final c = Rtdj.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2(hubPublished: false);
  await c.restoreSeller1Published();

  final s1 = c.sellerId!;
  final s2 = c.seller2Id!;
  final b1 = c.buyerId!;
  final b2 = c.buyer2Id!;

  Future<Map<String, dynamic>?> resRow(String id) async {
    final h = await c.rest(
      'GET',
      'live_reservation_requests?id=eq.$id&select=id,status,requested_qty,buyer_id,live_id,live_item_id',
      service: true,
    );
    return h.map;
  }

  Future<HttpHit> accept(String rid) => c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$rid',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );

  Future<HttpHit> reject(String rid) => c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$rid',
        jwt: c.sellerJwt,
        body: {'status': 'rejected'},
      );

  // =====================================================================
  // DJ-A — FOMO allowlist controlo (não chase)
  // =====================================================================
  final liveA = await c.createLive(title: '$prefix a-fomo');
  if (liveA == null) {
    stderr.writeln('fixture liveA fail');
    exit(4);
  }

  Future<Map<String, dynamic>> visibility(String body) async {
    final rest = await c.rest(
      'GET',
      'live_messages?live_id=eq.$liveA&kind=eq.system&body=eq.${Uri.encodeQueryComponent(body)}&select=id,kind,body,sender_label&limit=5',
      jwt: c.buyerJwt,
    );
    final hubB = await c.rest(
      'GET',
      'hub_live_messages_public?live_id=eq.$liveA&kind=eq.system&body=eq.${Uri.encodeQueryComponent(body)}&select=id,kind,body,sender_label&limit=5',
      jwt: c.buyerJwt,
    );
    final hubA = await c.rest(
      'GET',
      'hub_live_messages_public?live_id=eq.$liveA&kind=eq.system&body=eq.${Uri.encodeQueryComponent(body)}&select=id,kind,body,sender_label&limit=5',
    );
    final hubBHit = hubB.list.any((r) => r is Map && '${r['body']}' == body);
    final hubAHit = hubA.list.any((r) => r is Map && '${r['body']}' == body);
    final restHit = rest.list.any((r) => r is Map && '${r['body']}' == body);
    return {
      'rest_buyer': restHit,
      'hub_buyer': hubBHit,
      'hub_anon': hubAHit,
      'visible_hub': hubBHit || hubAHit,
    };
  }

  Future<void> sysCtrl({
    required String id,
    required String body,
    required bool positive,
    bool residual = false,
  }) async {
    final h = await c.rpc(
      'batata_live_system_message',
      {
        'p_live_id': liveA,
        'p_body': body,
        'p_sender_label': 'Sistema',
      },
      jwt: c.sellerJwt,
    );
    final ok = h.map?['ok'] == true;
    final vis = ok ? await visibility(body) : <String, dynamic>{};
    final hubSees = vis['visible_hub'] == true;
    if (positive) {
      final good = ok && hubSees;
      if (!good) {
        c.hold(
          id: id,
          lens: 'DJ1',
          severity: 'P2',
          title: 'System msg legítima bloqueada: $body',
          actor: 'seller JWT',
          pre: 'allowlist DBDG welcome/directo a começar',
          repro: 'rpc batata_live_system_message p_body=$body',
          expected: 'ok=true + Hub visível',
          obtained: {'rpc': h.brief, 'vis': vis},
        );
      } else {
        c.block(id, 'DJ1', 'controlo positivo OK', {'rpc': h.brief, 'vis': vis});
      }
      c.probe(
        id: id,
        poco: 'DJ-A',
        payload: body,
        http: h,
        bd: vis,
        result: good ? 'HOLD' : 'FAIL',
        lens: 'DJ1',
      );
    } else {
      final leaked = ok && hubSees;
      if (leaked) {
        c.hold(
          id: id,
          lens: 'DJ2',
          severity: 'P2',
          title: 'FOMO free-text persistiu: $body',
          actor: 'seller JWT',
          pre: 'allowlist DBDG deve deny',
          repro: 'rpc batata_live_system_message p_body=$body',
          expected: 'ok=false purchase_announce_via_broadcast_only',
          obtained: {'rpc': h.brief, 'vis': vis},
        );
      } else {
        c.block(id, 'DJ2', 'FOMO deny (HOLD residual)', h.brief);
      }
      c.probe(
        id: id,
        poco: 'DJ-A',
        payload: body,
        http: h,
        bd: vis,
        result: leaked ? 'FAIL' : 'HOLD',
        lens: 'DJ2',
        residual: residual,
        countFinding: leaked,
      );
    }
  }

  await sysCtrl(id: 'A1.welcome', body: 'Bem-vindos ao directo!', positive: true);
  await sysCtrl(
    id: 'A2.directo.comecar',
    body: 'O directo está a começar',
    positive: true,
  );
  await sysCtrl(
    id: 'A3.voou_tudo',
    body: 'voou tudo',
    positive: false,
    residual: true,
  );

  // =====================================================================
  // DJ-B — Stock / hitch
  // =====================================================================

  // --- B1 2 buyers hitch mesma unidade (race accept∥accept) ---
  final liveB1 = await c.createLive(title: '$prefix b1-same-unit');
  final skuB1 =
      await c.createProduct(title: '$prefix b1 sku', qty: 1, live: true);
  final itemB1 = (liveB1 == null || skuB1 == null)
      ? null
      : await c.createLiveItem(
          liveId: liveB1,
          title: '$prefix b1 item',
          ref: 'RTDJ-B1',
          kind: 'live_only',
          checkoutProductId: skuB1,
          quantity: 1,
        );
  if (liveB1 != null && itemB1 != null) {
    final r1 = await c.insertReservation(
      liveId: liveB1,
      liveItemId: itemB1,
      jwt: c.buyerJwt,
      buyer: b1,
    );
    final r2 = await c.insertReservation(
      liveId: liveB1,
      liveItemId: itemB1,
      jwt: c.buyer2Jwt,
      buyer: b2,
    );
    HttpHit? a1;
    HttpHit? a2;
    if (r1 != null && r2 != null) {
      final raced = await Future.wait([accept(r1), accept(r2)]);
      a1 = raced[0];
      a2 = raced[1];
    }
    final row1 = r1 == null ? null : await resRow(r1);
    final row2 = r2 == null ? null : await resRow(r2);
    final st1 = row1?['status']?.toString();
    final st2 = row2?['status']?.toString();
    final nAcc = [st1, st2].where((s) => s == 'accepted' || s == 'converted').length;
    final stock = await c.stock(itemB1);
    final oversell = nAcc >= 2;
    if (oversell) {
      c.hold(
        id: 'B1.two_buyers.same_unit',
        lens: 'DJ3',
        severity: 'P1',
        title: 'Dois accepts na mesma unidade (qty=1)',
        actor: 'seller JWT race Future.wait',
        pre: 'live_only qty=1; 2 pending B1+B2',
        repro: 'PATCH accepted ∥ PATCH accepted',
        expected: '1 accepted; 2º qty_exceeds_stock',
        obtained: {'r1': row1, 'r2': row2, 'a1': a1?.brief, 'a2': a2?.brief, 'stock': stock},
      );
    } else {
      c.block('B1.two_buyers.same_unit', 'DJ3', '1 unidade no máximo (HOLD)', {
        'r1': row1,
        'r2': row2,
        'a1': a1?.brief,
        'a2': a2?.brief,
        'n_accepted': nAcc,
      });
    }
    c.probe(
      id: 'B1.two_buyers.same_unit',
      poco: 'DJ-B',
      payload: '2 buyers hitch mesma unidade qty=1 accept∥accept',
      http: '${a1?.brief ?? 'n/a'} | ${a2?.brief ?? 'n/a'}',
      bd: {'r1': row1, 'r2': row2, 'stock': stock, 'n_accepted': nAcc},
      result: oversell ? 'FAIL' : 'HOLD',
      lens: 'DJ7',
    );
  } else {
    c.probe(
      id: 'B1.two_buyers.same_unit',
      poco: 'DJ-B',
      payload: '2 buyers hitch mesma unidade',
      http: 'fixture fail',
      result: 'SKIP',
      lens: 'DJ3',
    );
  }

  // --- B2 hitch qty > available ---
  final liveB2 = await c.createLive(title: '$prefix b2-qty');
  final skuB2 =
      await c.createProduct(title: '$prefix b2 sku', qty: 1, live: true);
  final itemB2 = (liveB2 == null || skuB2 == null)
      ? null
      : await c.createLiveItem(
          liveId: liveB2,
          title: '$prefix b2 item',
          ref: 'RTDJ-B2',
          kind: 'live_only',
          checkoutProductId: skuB2,
          quantity: 1,
        );
  if (liveB2 != null && itemB2 != null) {
    final rQty = await c.insertReservation(
      liveId: liveB2,
      liveItemId: itemB2,
      jwt: c.buyerJwt,
      buyer: b1,
      qty: 5,
    );
    final pending = rQty == null ? null : await resRow(rQty);
    final clamped = (pending?['requested_qty'] as num?)?.toInt() ?? -1;
    HttpHit? accQty;
    Map<String, dynamic>? afterAcc;
    if (rQty != null) {
      accQty = await accept(rQty);
      afterAcc = await resRow(rQty);
    }
    final oversellQty = (afterAcc?['status'] == 'accepted' ||
            afterAcc?['status'] == 'converted') &&
        ((afterAcc?['requested_qty'] as num?)?.toInt() ?? 0) > 1;
    final insertOversell = clamped > 1;
    if (insertOversell || oversellQty) {
      c.hold(
        id: 'B2.hitch.qty_gt_avail',
        lens: 'DJ4',
        severity: 'P1',
        title: 'Reserva qty>available na unidade qty=1',
        actor: 'buyer JWT insert qty=5',
        pre: 'live_only quantity=1',
        repro: 'POST live_reservation_requests requested_qty=5; PATCH accepted',
        expected: 'clamp ≤1 ou qty_exceeds_stock',
        obtained: {
          'pending': pending,
          'accept': accQty?.brief,
          'after': afterAcc,
        },
      );
    } else {
      c.block('B2.hitch.qty_gt_avail', 'DJ4', 'qty clamp/deny (HOLD)', {
        'pending': pending,
        'accept': accQty?.brief,
        'after': afterAcc,
      });
    }
    c.probe(
      id: 'B2.hitch.qty_gt_avail',
      poco: 'DJ-B',
      payload: 'hitch requested_qty=5 em item qty=1',
      http: accQty?.brief ?? 'insert ${pending == null ? 'fail' : 'ok'}',
      bd: {'pending': pending, 'after': afterAcc},
      result: (insertOversell || oversellQty) ? 'FAIL' : 'HOLD',
      lens: 'DJ4',
    );
  }

  // --- B3 accept ∥ reject paralelo ---
  final liveB3 = await c.createLive(title: '$prefix b3-acc-rej');
  final skuB3 =
      await c.createProduct(title: '$prefix b3 sku', qty: 1, live: true);
  final itemB3 = (liveB3 == null || skuB3 == null)
      ? null
      : await c.createLiveItem(
          liveId: liveB3,
          title: '$prefix b3 item',
          ref: 'RTDJ-B3',
          kind: 'live_only',
          checkoutProductId: skuB3,
          quantity: 1,
        );
  if (liveB3 != null && itemB3 != null) {
    final rB3 = await c.insertReservation(
      liveId: liveB3,
      liveItemId: itemB3,
      jwt: c.buyerJwt,
      buyer: b1,
    );
    if (rB3 != null) {
      final raced = await Future.wait([accept(rB3), reject(rB3)]);
      final after = await resRow(rB3);
      final st = after?['status']?.toString();
      final converted = st == 'converted';
      final split = st != 'accepted' && st != 'rejected' && st != 'pending';
      if (converted || split) {
        c.hold(
          id: 'B3.accept_reject.parallel',
          lens: 'DJ7',
          severity: 'P1',
          title: 'accept∥reject deixou estado inconsistente',
          actor: 'seller JWT Future.wait',
          pre: 'pending qty=1',
          repro: 'PATCH accepted ∥ PATCH rejected',
          expected: 'accepted XOR rejected; ≠converted',
          obtained: {'after': after, 'a': raced[0].brief, 'r': raced[1].brief},
        );
      } else {
        c.block('B3.accept_reject.parallel', 'DJ7',
            'estado terminal único (HOLD)', after);
      }
      c.probe(
        id: 'B3.accept_reject.parallel',
        poco: 'DJ-B',
        payload: 'accept ∥ reject mesma reserva',
        http: '${raced[0].brief} | ${raced[1].brief}',
        bd: after,
        result: (converted || split) ? 'FAIL' : 'HOLD',
        lens: 'DJ7',
      );
    }
  }

  // --- B4 end_live ∥ accept ---
  final liveB4 = await c.createLive(title: '$prefix b4-end-acc');
  final skuB4 =
      await c.createProduct(title: '$prefix b4 sku', qty: 1, live: true);
  final itemB4 = (liveB4 == null || skuB4 == null)
      ? null
      : await c.createLiveItem(
          liveId: liveB4,
          title: '$prefix b4 item',
          ref: 'RTDJ-B4',
          kind: 'live_only',
          checkoutProductId: skuB4,
          quantity: 1,
        );
  if (liveB4 != null && itemB4 != null) {
    final rB4 = await c.insertReservation(
      liveId: liveB4,
      liveItemId: itemB4,
      jwt: c.buyerJwt,
      buyer: b1,
    );
    if (rB4 != null) {
      final raced = await Future.wait([
        accept(rB4),
        c.rest(
          'PATCH',
          'lives?id=eq.$liveB4',
          service: true,
          body: {'status': 'ended', 'is_active': false},
        ),
        accept(rB4),
      ]);
      final after = await resRow(rB4);
      final liveAfter = await c.rest(
        'GET',
        'lives?id=eq.$liveB4&select=id,status,is_active',
        service: true,
      );
      final st = after?['status']?.toString();
      final cash = st == 'converted';
      if (cash) {
        c.hold(
          id: 'B4.end_live.parallel_accept',
          lens: 'DJ7',
          severity: 'P0',
          title: 'end∥accept converteu sem PI',
          actor: 'seller JWT + service end',
          pre: 'pending; sem order paga',
          repro: 'PATCH accepted ∥ PATCH lives ended',
          expected: '≠converted',
          obtained: {'res': after, 'live': liveAfter.map},
        );
      } else {
        c.block('B4.end_live.parallel_accept', 'DJ7',
            'end∥accept sem caixa (HOLD)', {
          'res': after,
          'live': liveAfter.map,
        });
      }
      c.probe(
        id: 'B4.end_live.parallel_accept',
        poco: 'DJ-B',
        payload: 'end_live ∥ PATCH accepted',
        http: raced.map((h) => h.brief).join(' | '),
        bd: {'res': after, 'live': liveAfter.map},
        result: cash ? 'FAIL' : 'HOLD',
        lens: 'DJ7',
      );
    }
  }

  // --- B5 reserve após ended ---
  final liveB5 = await c.createLive(title: '$prefix b5-after-end');
  final skuB5 =
      await c.createProduct(title: '$prefix b5 sku', qty: 1, live: true);
  final itemB5 = (liveB5 == null || skuB5 == null)
      ? null
      : await c.createLiveItem(
          liveId: liveB5,
          title: '$prefix b5 item',
          ref: 'RTDJ-B5',
          kind: 'live_only',
          checkoutProductId: skuB5,
          quantity: 1,
        );
  if (liveB5 != null && itemB5 != null) {
    await c.endLive(liveB5);
    final rLate = await c.insertReservation(
      liveId: liveB5,
      liveItemId: itemB5,
      jwt: c.buyerJwt,
      buyer: b1,
    );
    HttpHit? accLate;
    Map<String, dynamic>? lateRow;
    if (rLate != null) {
      accLate = await accept(rLate);
      lateRow = await resRow(rLate);
    }
    final acceptedLate = lateRow?['status'] == 'accepted' ||
        lateRow?['status'] == 'converted';
    if (acceptedLate) {
      c.hold(
        id: 'B5.reserve.after.ended',
        lens: 'DJ4',
        severity: 'P1',
        title: 'Accept após live ended',
        actor: 'buyer insert + seller accept',
        pre: 'status=ended is_active=false',
        repro: 'POST reservation após end; PATCH accepted',
        expected: 'live_ended / insert deny',
        obtained: {
          'insert_id': rLate,
          'accept': accLate?.brief,
          'row': lateRow,
        },
      );
    } else {
      c.block('B5.reserve.after.ended', 'DJ4',
          'reserva/accept pós-end recusado (HOLD)', {
        'insert_id': rLate,
        'accept': accLate?.brief,
        'row': lateRow,
      });
    }
    c.probe(
      id: 'B5.reserve.after.ended',
      poco: 'DJ-B',
      payload: 'POST reservation + accept após lives.status=ended',
      http: accLate?.brief ?? (rLate == null ? 'insert deny' : 'insert ok'),
      bd: {'insert_id': rLate, 'row': lateRow},
      result: acceptedLate ? 'FAIL' : 'HOLD',
      lens: 'DJ4',
    );
  }

  // --- B6 hitch marketplace + live_only mesmo SKU qty=1 ---
  final liveB6 = await c.createLive(title: '$prefix b6-hitch-pool');
  final skuB6 =
      await c.createProduct(title: '$prefix b6 hitch sku', qty: 1, live: true);
  if (liveB6 != null && skuB6 != null) {
    final liM = await c.createLiveItem(
      liveId: liveB6,
      title: '$prefix hitch mkt',
      ref: 'RTDJ-B6M',
      kind: 'marketplace_product',
      productId: skuB6,
    );
    final liL = await c.createLiveItem(
      liveId: liveB6,
      title: '$prefix hitch live',
      ref: 'RTDJ-B6L',
      kind: 'live_only',
      checkoutProductId: skuB6,
      quantity: 1,
    );
    if (liM != null) {
      await c.rest(
        'PATCH',
        'live_items?id=eq.$liM',
        service: true,
        body: {'checkout_product_id': null, 'logical_item_id': null},
        prefer: 'return=minimal',
      );
    }
    String? rm;
    String? rl;
    HttpHit? a2;
    if (liM != null && liL != null) {
      rm = await c.insertReservation(
        liveId: liveB6,
        liveItemId: liM,
        jwt: c.buyerJwt,
        buyer: b1,
      );
      if (rm != null) await accept(rm);
      rl = await c.insertReservation(
        liveId: liveB6,
        liveItemId: liL,
        jwt: c.buyer2Jwt,
        buyer: b2,
      );
      if (rl != null) a2 = await accept(rl);
    }
    final rowM = rm == null ? null : await resRow(rm);
    final rowL = rl == null ? null : await resRow(rl);
    final both = rowM?['status'] == 'accepted' && rowL?['status'] == 'accepted';
    final prod = await c.productQty(skuB6);
    if (both) {
      c.hold(
        id: 'B6.hitch.mkt_live_only',
        lens: 'DJ3',
        severity: 'P1',
        title: 'Hitch marketplace+live_only qty=1 dois accepts',
        actor: 'seller JWT',
        pre: 'produto quantity=1',
        repro: 'accept LI marketplace depois LI live_only',
        expected: '2º qty_exceeds_stock',
        obtained: {'m': rowM, 'l': rowL, 'a2': a2?.brief, 'product': prod},
      );
    } else {
      c.block('B6.hitch.mkt_live_only', 'DJ3', '2º hitch recusado (HOLD)', {
        'm': rowM,
        'l': rowL,
        'a2': a2?.brief,
      });
    }
    c.probe(
      id: 'B6.hitch.mkt_live_only',
      poco: 'DJ-B',
      payload: 'hitch marketplace_product + live_only mesmo SKU qty=1',
      http: a2?.brief ?? 'n/a',
      bd: {'m': rowM, 'l': rowL, 'product': prod},
      result: both ? 'FAIL' : 'HOLD',
      lens: 'DJ3',
    );
  }

  // =====================================================================
  // DJ-C — Convert / rifa / Mux
  // =====================================================================

  // --- C1 convert sem PI ---
  final liveC1 = await c.createLive(title: '$prefix c1-nopi');
  final skuC1 =
      await c.createProduct(title: '$prefix c1 sku', qty: 1, live: true);
  final itemC1 = (liveC1 == null || skuC1 == null)
      ? null
      : await c.createLiveItem(
          liveId: liveC1,
          title: '$prefix c1 item',
          ref: 'RTDJ-C1',
          kind: 'live_only',
          checkoutProductId: skuC1,
          quantity: 1,
        );
  if (liveC1 != null && itemC1 != null) {
    final rC1 = await c.insertReservation(
      liveId: liveC1,
      liveItemId: itemC1,
      jwt: c.buyerJwt,
      buyer: b1,
    );
    if (rC1 != null) await accept(rC1);
    final rpcConv = rC1 == null
        ? null
        : await c.rpc(
            'batata_live_reservation_stripe_convert',
            {'p_request_id': rC1},
            jwt: c.sellerJwt,
          );
    final patchConv = rC1 == null
        ? null
        : await c.rest(
            'PATCH',
            'live_reservation_requests?id=eq.$rC1',
            jwt: c.sellerJwt,
            body: {'status': 'converted'},
          );
    final after = rC1 == null ? null : await resRow(rC1);
    final converted = after?['status'] == 'converted';
    if (converted) {
      c.hold(
        id: 'C1.convert.nopi',
        lens: 'DJ5',
        severity: 'P0',
        title: 'Convert sem PI pago próprio',
        actor: 'seller JWT',
        pre: 'accepted; zero orders pagas',
        repro: 'rpc stripe_convert + PATCH status=converted',
        expected: '403 / convert_requires_paid_order; status≠converted',
        obtained: {
          'rpc': rpcConv?.brief,
          'patch': patchConv?.brief,
          'row': after,
        },
      );
    } else {
      c.block('C1.convert.nopi', 'DJ5', 'convert sem PI recusado (HOLD)', {
        'rpc': rpcConv?.brief,
        'patch': patchConv?.brief,
        'status': after?['status'],
      });
    }
    c.probe(
      id: 'C1.convert.nopi',
      poco: 'DJ-C',
      payload: 'convert accepted sem PI (RPC + PATCH)',
      http: '${rpcConv?.brief ?? 'n/a'} | ${patchConv?.brief ?? 'n/a'}',
      bd: after,
      result: converted ? 'FAIL' : 'HOLD',
      lens: 'DJ5',
    );
  }

  // --- C2 convert PI alheio / outra live ---
  final liveC2a = await c.createLive(title: '$prefix c2-src');
  final liveC2b = await c.createLive(title: '$prefix c2-dst');
  final skuC2a =
      await c.createProduct(title: '$prefix c2a sku', qty: 1, live: true);
  final skuC2b =
      await c.createProduct(title: '$prefix c2b sku', qty: 1, live: true);
  final itemC2a = (liveC2a == null || skuC2a == null)
      ? null
      : await c.createLiveItem(
          liveId: liveC2a,
          title: '$prefix c2a',
          ref: 'RTDJ-C2A',
          kind: 'live_only',
          checkoutProductId: skuC2a,
          quantity: 1,
        );
  final itemC2b = (liveC2b == null || skuC2b == null)
      ? null
      : await c.createLiveItem(
          liveId: liveC2b,
          title: '$prefix c2b',
          ref: 'RTDJ-C2B',
          kind: 'live_only',
          checkoutProductId: skuC2b,
          quantity: 1,
        );
  String? rC2b;
  if (liveC2b != null && itemC2b != null) {
    rC2b = await c.insertReservation(
      liveId: liveC2b,
      liveItemId: itemC2b,
      jwt: c.buyer2Jwt,
      buyer: b2,
    );
    if (rC2b != null) await accept(rC2b);
  }
  HttpHit? planted;
  if (liveC2a != null && itemC2a != null && skuC2a != null) {
    planted = await c.rest('POST', 'orders', service: true, body: {
      'buyer_id': b1,
      'seller_id': s1,
      'product_id': skuC2a,
      'live_id': liveC2a,
      'live_item_id': itemC2a,
      'quantity': 1,
      'price_total': 9,
      'status': 'pago',
      'payment_method': 'MB WAY',
      'shipping_method': 'entrega em mão',
      'stripe_payment_intent_id': 'pi_rtdj_stolen_${stamp}_A',
      'amount_paid_cents': 900,
    });
    if (planted.firstId != null) c.createdOrderIds.add(planted.firstId!);
  }
  if (planted?.ok == true && planted?.firstId != null && rC2b != null) {
    final rec = await c.rpc(
      'batata_live_reconcile_stripe_order',
      {
        'p_order_id': planted!.firstId,
        'p_reservation_request_id': rC2b,
      },
      jwt: c.sellerJwt,
    );
    final after = await resRow(rC2b);
    final converted = rec.map?['ok'] == true && after?['status'] == 'converted';
    if (converted) {
      c.hold(
        id: 'C2.convert.pi_alheio',
        lens: 'DJ5',
        severity: 'P0',
        title: 'Reconcile PI live A / buyer1 → reserva live B buyer2',
        actor: 'seller JWT',
        pre: 'order paga live A item A; reserva accepted live B buyer2',
        repro: 'rpc batata_live_reconcile_stripe_order',
        expected: 'mismatch / convert_requires_paid_order',
        obtained: {'rpc': rec.brief, 'res': after},
      );
    } else {
      c.block('C2.convert.pi_alheio', 'DJ5', 'PI alheio recusado (HOLD)',
          rec.brief);
    }
    c.probe(
      id: 'C2.convert.pi_alheio',
      poco: 'DJ-C',
      payload: 'reconcile PI liveA buyer1 → res liveB buyer2',
      http: rec,
      bd: after,
      result: converted ? 'FAIL' : 'HOLD',
      lens: 'DJ5',
    );
  } else {
    c.probe(
      id: 'C2.convert.pi_alheio',
      poco: 'DJ-C',
      payload: 'reconcile PI alheio',
      http: planted?.brief ?? 'plant fail',
      result: 'SKIP',
      lens: 'DJ5',
    );
  }

  // --- C3 convert após unpublish ---
  final liveC3 = await c.createLive(title: '$prefix c3-unpub');
  final skuC3 =
      await c.createProduct(title: '$prefix c3 sku', qty: 1, live: true);
  final itemC3 = (liveC3 == null || skuC3 == null)
      ? null
      : await c.createLiveItem(
          liveId: liveC3,
          title: '$prefix c3 item',
          ref: 'RTDJ-C3',
          kind: 'live_only',
          checkoutProductId: skuC3,
          quantity: 1,
        );
  if (liveC3 != null && itemC3 != null) {
    final rC3 = await c.insertReservation(
      liveId: liveC3,
      liveItemId: itemC3,
      jwt: c.buyerJwt,
      buyer: b1,
    );
    if (rC3 != null) await accept(rC3);
    await c.setHub(s1, false);
    await c.endLive(liveC3);
    final patch = rC3 == null
        ? null
        : await c.rest(
            'PATCH',
            'live_reservation_requests?id=eq.$rC3',
            jwt: c.sellerJwt,
            body: {'status': 'converted'},
          );
    final afterNoPi = rC3 == null ? null : await resRow(rC3);
    final convertedNoPi = afterNoPi?['status'] == 'converted';
    if (convertedNoPi) {
      c.hold(
        id: 'C3.convert.after.unpublish',
        lens: 'DJ5',
        severity: 'P0',
        title: 'Convert sem PI após unpublish+end',
        actor: 'seller JWT',
        pre: 'accepted; hub_published=false; live ended; sem order paga',
        repro: 'PATCH converted após unpublish',
        expected: 'convert_requires_paid_order',
        obtained: {'patch': patch?.brief, 'row': afterNoPi},
      );
    } else {
      c.block('C3.convert.after.unpublish', 'DJ5',
          'convert pós-unpublish sem PI recusado (HOLD)', patch?.brief);
    }
    c.probe(
      id: 'C3.convert.after.unpublish',
      poco: 'DJ-C',
      payload: 'PATCH converted após hub unpublish + live ended sem PI',
      http: patch ?? 'n/a',
      bd: afterNoPi,
      result: convertedNoPi ? 'FAIL' : 'HOLD',
      lens: 'DJ5',
    );
    await c.restoreSeller1Published();
  }

  // --- C4 rifa follow unpublished vs published ---
  await c.setHub(s2, false);
  await c.rest('PATCH', 'profiles?id=eq.$s2', service: true, body: {
    'user_type': 'vendedor',
  }, prefer: 'return=minimal');
  final liveRaffleUn = await c.createLive(
    seller: s2,
    title: '$prefix raffle-unpub',
  );
  final raffleUn = liveRaffleUn == null
      ? null
      : await c.rest('POST', 'live_raffles', service: true, body: {
          'live_id': liveRaffleUn,
          'seller_id': s2,
          'title': '$prefix raffle unpub',
          'status': 'active',
          'winner_count': 1,
        });
  final raffleUnId = raffleUn?.firstId;
  if (raffleUnId != null) c.createdRaffleIds.add(raffleUnId);

  Future<void> delFollow(String follower, String following) async {
    await c.rest(
      'DELETE',
      'follows?follower_id=eq.$follower&following_id=eq.$following',
      jwt: c.buyer2Jwt,
      prefer: 'return=minimal',
    );
    await c.rest(
      'DELETE',
      'follows?follower_id=eq.$follower&following_id=eq.$following',
      service: true,
      prefer: 'return=minimal',
    );
  }

  await delFollow(b2, s2);
  final folUn = await c.rest('POST', 'follows', jwt: c.buyer2Jwt, body: {
    'follower_id': b2,
    'following_id': s2,
  });
  if (folUn.firstId != null) c.createdFollowIds.add(folUn.firstId!);
  final ticketsUn =
      raffleUnId == null ? 0 : await c.raffleTickets(raffleUnId, b2);
  final unpubAward = insertOk(folUn) && folUn.status != 409 && ticketsUn > 0;
  final unpubFollowed = insertOk(folUn) && folUn.status != 409;
  if (unpubAward) {
    c.hold(
      id: 'C4.raffle.follow.unpublished',
      lens: 'DJ6',
      severity: 'P1',
      title: 'Follow unpublished atribuiu tickets de rifa',
      actor: 'buyer2 JWT',
      pre: 'S2 hub_published=false; raffle active',
      repro: 'POST follows following_id=S2',
      expected: '403 deny; tickets=0',
      obtained: {'http': folUn.brief, 'tickets': ticketsUn},
    );
  } else {
    c.block(
      'C4.raffle.follow.unpublished',
      'DJ6',
      'follow unpublished deny / 0 tickets (HOLD residual)',
      {'http': folUn.brief, 'tickets': ticketsUn, 'followed': unpubFollowed},
    );
  }
  c.probe(
    id: 'C4.raffle.follow.unpublished',
    poco: 'DJ-C',
    payload: 'B2 follow S2 unpublished + raffle active',
    http: folUn,
    bd: {'tickets': ticketsUn, 'raffle': raffleUnId},
    result: unpubAward ? 'FAIL' : 'HOLD',
    lens: 'DJ6',
    residual: true,
    countFinding: unpubAward,
  );

  await c.restoreSeller1Published();
  final liveRafflePub = await c.createLive(title: '$prefix raffle-pub');
  final rafflePub = liveRafflePub == null
      ? null
      : await c.rest('POST', 'live_raffles', service: true, body: {
          'live_id': liveRafflePub,
          'seller_id': s1,
          'title': '$prefix raffle pub',
          'status': 'active',
          'winner_count': 1,
        });
  final rafflePubId = rafflePub?.firstId;
  if (rafflePubId != null) c.createdRaffleIds.add(rafflePubId);
  await delFollow(b2, s1);
  final folPub = await c.rest('POST', 'follows', jwt: c.buyer2Jwt, body: {
    'follower_id': b2,
    'following_id': s1,
  });
  if (folPub.firstId != null) c.createdFollowIds.add(folPub.firstId!);
  final ticketsPub =
      rafflePubId == null ? 0 : await c.raffleTickets(rafflePubId, b2);
  final pubOk = insertOk(folPub);
  // Follow published OK é o controlo; tickets>0 esperado se lifetime grant
  // ainda não existir. 0 tickets com follow 201 = lifetime já gasto (HOLD).
  if (!pubOk) {
    c.hold(
      id: 'C4.raffle.follow.published',
      lens: 'DJ6',
      severity: 'P2',
      title: 'Follow published recusado',
      actor: 'buyer2 JWT',
      pre: 'S1 hub_published=true; raffle active',
      repro: 'POST follows following_id=S1',
      expected: '201 + tickets≥0',
      obtained: {'http': folPub.brief, 'tickets': ticketsPub},
    );
  } else {
    c.block('C4.raffle.follow.published', 'DJ6',
        'follow published OK (HOLD)', {
      'http': folPub.brief,
      'tickets': ticketsPub,
    });
  }
  c.probe(
    id: 'C4.raffle.follow.published',
    poco: 'DJ-C',
    payload: 'B2 follow S1 published + raffle active',
    http: folPub,
    bd: {'tickets': ticketsPub, 'raffle': rafflePubId},
    result: pubOk ? 'HOLD' : 'FAIL',
    lens: 'DJ6',
  );

  // --- C5 playback unpublished buyer ---
  const fakePlayback = 'RTDJPLAY1609fake0001';
  const fakePlaybackCol = 'RTDJPB1609plain0001';
  const fakeRoom = 'RTDJROOM1609livekit';
  final liveUnpub = await c.createLive(
    seller: s2,
    title: '$prefix mux-unpub',
    extra: {
      'mux_playback_id': fakePlayback,
      'playback_id': fakePlaybackCol,
      'livekit_room_name': fakeRoom,
    },
  );
  if (liveUnpub != null) {
    final pb = await c.rest(
      'GET',
      'lives?id=eq.$liveUnpub&select=id,playback_id,mux_playback_id,livekit_room_name',
      jwt: c.buyerJwt,
    );
    final leaked = pb.ok &&
        ((pb.map?['playback_id']?.toString().isNotEmpty ?? false) ||
            (pb.map?['mux_playback_id']?.toString().isNotEmpty ?? false) ||
            (pb.map?['livekit_room_name']?.toString().isNotEmpty ?? false));
    if (leaked) {
      c.hold(
        id: 'C5.buyer.playback.unpublished',
        lens: 'DJ8',
        severity: 'P2',
        title: 'Buyer lê playback/mux/livekit unpublished',
        actor: 'buyer JWT',
        pre: 'S2 unpublished; cols preenchidas',
        repro: 'GET lives select playback_id,mux_playback_id,livekit_room_name',
        expected: '403 / vazio',
        obtained: pb.brief,
      );
    } else {
      c.block('C5.buyer.playback.unpublished', 'DJ8',
          'buyer não lê playback unpublished (HOLD)', pb.brief);
    }
    c.probe(
      id: 'C5.buyer.playback.unpublished',
      poco: 'DJ-C',
      payload: 'GET lives playback/mux/livekit unpublished',
      http: pb,
      bd: pb.map,
      result: leaked ? 'FAIL' : 'HOLD',
      lens: 'DJ8',
    );
  }

  // --- C6 tip mid-live residual ---
  final liveTip = await c.createLive(title: '$prefix c6-tip');
  final balBefore = await c.walletBal(s1);
  final tipCreate = liveTip == null
      ? null
      : await c.edge(
          'create-live-tip-checkout',
          jwt: c.buyer2Jwt,
          body: {
            'live_id': liveTip,
            'seller_id': s1,
            'amount_eur': 2,
          },
        );
  String? tipId = tipCreate?.map?['tipId']?.toString() ??
      tipCreate?.map?['tip_id']?.toString();
  if (tipId != null) c.createdTipIds.add(tipId);
  var tipStatus = '';
  if (tipId != null) {
    final row = await c.rest(
      'GET',
      'live_tips?id=eq.$tipId&select=id,status,amount',
      service: true,
    );
    tipStatus = '${row.map?['status'] ?? ''}';
  }
  final balAfter = await c.walletBal(s1);
  final credited = tipStatus == 'paid' ||
      tipStatus == 'settled' ||
      (balAfter - balBefore) > 0;
  if (credited) {
    c.hold(
      id: 'C6.tip.mid_live',
      lens: 'DJ5',
      severity: 'P0',
      title: 'Tip mid-live creditou carteira sem pagamento',
      actor: 'buyer2 JWT edge',
      pre: 'live active; sem Stripe pay',
      repro: 'POST create-live-tip-checkout amount_eur=2',
      expected: 'pending/unpaid; Δ wallet=0',
      obtained: {
        'http': tipCreate?.brief,
        'tipId': tipId,
        'status': tipStatus,
        'dWallet': balAfter - balBefore,
      },
    );
  } else {
    c.block('C6.tip.mid_live', 'DJ5', 'tip mid-live sem crédito (HOLD residual)',
        {
      'http': tipCreate?.brief,
      'status': tipStatus,
      'dWallet': balAfter - balBefore,
    });
  }
  c.probe(
    id: 'C6.tip.mid_live',
    poco: 'DJ-C',
    payload: 'create-live-tip-checkout mid-live amount_eur=2 sem pay',
    http: tipCreate ?? 'n/a',
    bd: {
      'tipId': tipId,
      'status': tipStatus,
      'dWallet': balAfter - balBefore,
    },
    result: credited ? 'FAIL' : 'HOLD',
    lens: 'DJ5',
    residual: true,
    countFinding: credited,
  );

  await c.restoreSeller1Published();
  await dumpJson('${outDir()}/pass1.json', {
    'auditor': 'REDTEAM_BLIND_DJ_LIVE_STOCK_POS_DBDG_v1',
    'prefix': prefix,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'probes': c.probes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  await c.endAllCreatedLives();
  stdout.writeln(
      'pass1 done findings=${c.findings.length} blocked=${c.blocked.length} '
      'probes=${c.probes.length}');
}
