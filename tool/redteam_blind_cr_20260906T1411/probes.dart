/// REDTEAM_BLIND_CR_LIVE_POS_ALLOW_v1 — staging only. No fixes. No Fase 4.
import 'dart:io';

import '_rtcr.dart';

Future<void> main() async {
  final c = Rtcl.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2(hubPublished: false);
  await c.ensureHelperNone();

  final table = <Map<String, dynamic>>[];
  final fomoPersisted = <Map<String, dynamic>>[];

  void row({
    required String probeId,
    required String poco,
    required String payload,
    required String rpcHttp,
    required String buyerGet,
    required String verdict,
    String? lens,
    Object? extra,
  }) {
    if (lens != null) c.lensesHit.add(lens);
    table.add({
      'probe_id': probeId,
      'poco': poco,
      'payload': payload,
      'rpc_http': rpcHttp,
      'buyer_get': buyerGet,
      'verdict': verdict,
      if (lens != null) 'lens': lens,
      if (extra != null) 'extra': extra,
    });
    c.probe(
      id: probeId,
      lens: lens ?? poco,
      payload: payload,
      http: '$rpcHttp | buyer=$buyerGet',
      verdict: verdict,
      extra: extra,
    );
  }

  Future<Map<String, dynamic>> hubSee(String liveId, String body) async {
    final hubB = await c.rest(
      'GET',
      'hub_live_messages_public?live_id=eq.$liveId'
          '&kind=eq.system&select=id,kind,body,sender_label&limit=80',
      jwt: c.buyerJwt,
    );
    final restB = await c.rest(
      'GET',
      'live_messages?live_id=eq.$liveId&kind=eq.system'
          '&select=id,kind,body,sender_label&limit=80',
      jwt: c.buyerJwt,
    );
    final hubBodies = hubB.list
        .whereType<Map>()
        .map((m) => '${m['body']}')
        .toList();
    final restBodies = restB.list
        .whereType<Map>()
        .map((m) => '${m['body']}')
        .toList();
    final visHub = hubBodies.contains(body);
    final visRest = restBodies.contains(body);
    String label;
    if (visHub) {
      label = 'HUB VISIBLE kind=system';
    } else if (visRest) {
      label = 'REST VISIBLE hub=NO';
    } else {
      label = 'NOT VISIBLE hub=${hubB.status}/${hubB.list.length} '
          'rest=${restB.status}/${restB.list.length}';
    }
    return {
      'label': label,
      'hub': visHub,
      'rest': visRest,
      'hub_n': hubB.list.length,
      'rest_n': restB.list.length,
      'hub_http': hubB.brief,
    };
  }

  Future<void> fomoRpc({
    required String probeId,
    required String poco,
    required String lens,
    required String body,
    required String? jwt,
    required String actor,
    required String liveId,
    bool residual = false,
    bool expectOk = false,
  }) async {
    final h = await c.rpc(
      'batata_live_system_message',
      {
        'p_live_id': liveId,
        'p_body': body,
        'p_sender_label': 'Sistema',
      },
      jwt: jwt,
    );
    final ok = h.map?['ok'] == true;
    final err = h.map?['error']?.toString() ?? '';
    final vis = await hubSee(liveId, body);
    String verdict;
    if (expectOk) {
      if (ok && (vis['hub'] == true || vis['rest'] == true)) {
        verdict = 'HOLD';
        c.block(probeId, lens, 'legítimo OK (welcome/neutro)', h.brief);
      } else if (ok && vis['hub'] != true && vis['rest'] != true) {
        verdict = 'FAIL';
        c.hold(
          id: probeId,
          lens: lens,
          severity: 'P2',
          title: 'System msg legítima ok:true mas buyer não vê',
          actor: actor,
          pre: 'welcome/neutro deve chegar ao Hub',
          repro: 'rpc batata_live_system_message p_body=$body',
          expected: 'ok:true + Hub kind=system',
          obtained: {'rpc': h.brief, 'buyer': vis},
        );
      } else {
        verdict = 'FAIL';
        c.hold(
          id: probeId,
          lens: lens,
          severity: 'P2',
          title: 'System msg legítima recusada pela allowlist',
          actor: actor,
          pre: 'welcome/neutro não-FOMO',
          repro: 'rpc batata_live_system_message p_body=$body',
          expected: 'ok:true',
          obtained: h.brief,
        );
      }
    } else if (residual) {
      if (ok && (vis['hub'] == true || vis['rest'] == true)) {
        verdict = 'FAIL';
        c.hold(
          id: probeId,
          lens: lens,
          severity: 'P2',
          title: 'REGRESSÃO stem residual persistiu: $body',
          actor: actor,
          pre: 'stem CDCI/allowlist já fechado',
          repro: 'rpc batata_live_system_message p_body=$body',
          expected: 'ok=false purchase_announce_via_broadcast_only',
          obtained: {'rpc': h.brief, 'buyer': vis},
        );
      } else {
        verdict = 'HOLD';
        c.block(probeId, lens, 'residual stem recusado (não contar)', err);
      }
    } else {
      if (ok && (vis['hub'] == true || vis['rest'] == true)) {
        verdict = 'FAIL';
        fomoPersisted.add({'id': probeId, 'body': body, 'vis': vis});
        c.hold(
          id: probeId,
          lens: lens,
          severity: 'P2',
          title: 'FOMO stem-bypass persistiu: $body',
          actor: actor,
          pre: 'fora da stem list allowlist; sem convert pago',
          repro: 'rpc batata_live_system_message p_body=$body',
          expected: 'ok=false purchase_announce_via_broadcast_only',
          obtained: {'rpc': h.brief, 'buyer': vis},
        );
      } else if (ok) {
        verdict = 'FAIL';
        c.hold(
          id: probeId,
          lens: lens,
          severity: 'P2',
          title: 'FOMO ok:true (buyer GET incerto): $body',
          actor: actor,
          pre: 'row system inserida',
          repro: 'rpc + GET hub/live_messages',
          expected: 'ok=false',
          obtained: {'rpc': h.brief, 'buyer': vis},
        );
      } else {
        verdict = 'HOLD';
        c.block(probeId, lens, 'FOMO recusado', err.isEmpty ? h.brief : err);
      }
    }
    row(
      probeId: probeId,
      poco: poco,
      payload: body,
      rpcHttp: h.brief,
      buyerGet: '${vis['label']}',
      verdict: verdict,
      lens: lens,
      extra: {'ok': ok, 'actor': actor, 'residual': residual},
    );
  }

  final liveFomo = await c.createLive(title: '$prefix fomo');
  final skuFomo =
      await c.createProduct(title: '$prefix fomo sku', qty: 2, live: true);
  if (liveFomo == null || skuFomo == null) {
    stderr.writeln('fixture fomo fail');
    await c.endAllCreatedLives();
    exit(4);
  }
  final itemFomo = await c.createLiveItem(
    liveId: liveFomo,
    title: '$prefix fomo item',
    ref: 'RTCR-FOMO',
    kind: 'live_only',
    checkoutProductId: skuFomo,
    quantity: 2,
  );
  if (itemFomo == null) {
    stderr.writeln('item fomo fail');
    await c.endAllCreatedLives();
    exit(4);
  }

  final stockBefore = await c.stock(itemFomo);
  c.note('stock.before', 'stock antes FOMO', stockBefore, lens: 'CR3');

  final sellerPub = await c.rest(
    'GET',
    'profiles?id=eq.${c.sellerId}&select=id,hub_published,handle',
    service: true,
  );
  c.note('seller.hub', 'seller hub_published', sellerPub.map, lens: 'CR1');

  // --- CR-A positive ---
  await fomoRpc(
    probeId: 'A1.welcome',
    poco: 'CR-A',
    lens: 'CR1',
    body: 'Bem-vindos ao directo!',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    liveId: liveFomo,
    expectOk: true,
  );
  await fomoRpc(
    probeId: 'A2.neutro.comecar',
    poco: 'CR-A',
    lens: 'CR1',
    body: 'O directo está a começar',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    liveId: liveFomo,
    expectOk: true,
  );

  // --- CR-B bypass ---
  await fomoRpc(
    probeId: 'B1.es.ultimo_disponible',
    poco: 'CR-B',
    lens: 'CR2',
    body: 'último disponible',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    liveId: liveFomo,
  );
  await fomoRpc(
    probeId: 'B1.ptbr.ja_foi',
    poco: 'CR-B',
    lens: 'CR3',
    body: 'já foi',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    liveId: liveFomo,
  );
  await fomoRpc(
    probeId: 'B2.nl.uitverkocht',
    poco: 'CR-B',
    lens: 'CR2',
    body: 'uitverkocht',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    liveId: liveFomo,
  );
  await fomoRpc(
    probeId: 'B2.pl.wyprzedane',
    poco: 'CR-B',
    lens: 'CR2',
    body: 'wyprzedane',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    liveId: liveFomo,
  );
  await fomoRpc(
    probeId: 'B2.ro.epuizat',
    poco: 'CR-B',
    lens: 'CR2',
    body: 'epuizat',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    liveId: liveFomo,
  );
  await fomoRpc(
    probeId: 'B3.emoji.fire_one',
    poco: 'CR-B',
    lens: 'CR3',
    body: '🔥1️⃣',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    liveId: liveFomo,
  );
  await fomoRpc(
    probeId: 'B4.control.esaurito_spaced',
    poco: 'CR-B',
    lens: 'CR2',
    body: 'e s a u r i t o',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    liveId: liveFomo,
    residual: true,
  );
  await fomoRpc(
    probeId: 'B4.new.corre_que_some',
    poco: 'CR-B',
    lens: 'CR3',
    body: 'corre que some',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    liveId: liveFomo,
  );
  await fomoRpc(
    probeId: 'B4.new.sumiu',
    poco: 'CR-B',
    lens: 'CR3',
    body: 'sumiu',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    liveId: liveFomo,
  );

  // B5 buyer INSERT kind=system FOMO
  final b5 = await c.rest('POST', 'live_messages', jwt: c.buyerJwt, body: {
    'live_id': liveFomo,
    'user_id': c.buyerId,
    'kind': 'system',
    'body': 'já foi',
    'sender_label': 'Sistema',
  });
  final b5ok = b5.ok && b5.firstId != null;
  if (b5ok) {
    c.hold(
      id: 'B5.buyer.insert.system',
      lens: 'CR3',
      severity: 'P1',
      title: 'Buyer INSERT live_messages kind=system FOMO',
      actor: 'buyer JWT',
      pre: 'RLS insert só kind=chat',
      repro: 'POST live_messages kind=system body=já foi',
      expected: '403 RLS',
      obtained: b5.brief,
    );
  } else {
    c.block('B5.buyer.insert.system', 'CR3', 'buyer INSERT system recusado',
        b5.brief);
  }
  final b5vis = await hubSee(liveFomo, 'já foi');
  row(
    probeId: 'B5.buyer.insert.system',
    poco: 'CR-B',
    payload: 'POST live_messages kind=system body=já foi',
    rpcHttp: b5.brief,
    buyerGet: '${b5vis['label']}',
    verdict: b5ok ? 'FAIL' : 'HOLD',
    lens: 'CR3',
  );

  // B6 helper zero-perms
  final b6 = await c.rpc(
    'batata_live_system_message',
    {
      'p_live_id': liveFomo,
      'p_body': 'uitverkocht',
      'p_sender_label': 'Sistema',
    },
    jwt: c.helperNoneJwt,
  );
  final b6ok = b6.map?['ok'] == true;
  final b6vis = await hubSee(liveFomo, 'uitverkocht');
  if (b6ok) {
    c.hold(
      id: 'B6.helper0.scarcity',
      lens: 'CR2',
      severity: 'P2',
      title: 'Helper zero-perms publicou scarcity system',
      actor: 'helper zero JWT',
      pre: 'can_manage_chat=false',
      repro: 'rpc batata_live_system_message uitverkocht',
      expected: 'not_allowed',
      obtained: b6.brief,
    );
  } else {
    c.block('B6.helper0.scarcity', 'CR2', 'helper0 recusado', b6.brief);
  }
  row(
    probeId: 'B6.helper0.scarcity',
    poco: 'CR-B',
    payload: 'helper0 RPC uitverkocht',
    rpcHttp: b6.brief,
    buyerGet: '${b6vis['label']}',
    verdict: b6ok ? 'FAIL' : 'HOLD',
    lens: 'CR2',
  );

  final stockAfter = await c.stock(itemFomo);
  c.note('stock.after', 'stock depois FOMO', stockAfter, lens: 'CR3');
  if (stockBefore?['available_qty'] != null &&
      stockAfter?['available_qty'] != null &&
      stockAfter?['available_qty'] != stockBefore?['available_qty']) {
    c.hold(
      id: 'fomo.stock.delta',
      lens: 'CR3',
      severity: 'P1',
      title: 'FOMO system message alterou stock',
      actor: 'seller JWT',
      pre: 'só anúncio',
      repro: 'stock before/after',
      expected: 'available_qty inalterado',
      obtained: {'before': stockBefore, 'after': stockAfter},
    );
  }

  final ordersFomo = await c.rest(
    'GET',
    'orders?live_id=eq.$liveFomo&select=id,status,amount_paid_cents',
    service: true,
  );
  final paidFomo = ordersFomo.list.whereType<Map>().where((o) {
    final st = '${o['status']}'.toLowerCase();
    final cents = o['amount_paid_cents'];
    return st.contains('pago') || (cents is num && cents > 0);
  }).toList();
  c.note('fomo.caixa', 'orders pagas nesta live FOMO',
      {'n': ordersFomo.list.length, 'paid': paidFomo.length},
      lens: 'CR3');

  // --- CR-C hitch ---
  final liveH = await c.createLive(title: '$prefix hitch');
  final skuH =
      await c.createProduct(title: '$prefix hitch sku', qty: 1, live: true);
  HttpHit? a2;
  Map<String, dynamic>? row1;
  Map<String, dynamic>? row2;
  if (liveH != null && skuH != null) {
    final li1 = await c.createLiveItem(
      liveId: liveH,
      title: '$prefix hitch A',
      ref: 'RTCR-HA',
      kind: 'marketplace_product',
      productId: skuH,
    );
    final li2 = await c.createLiveItem(
      liveId: liveH,
      title: '$prefix hitch B',
      ref: 'RTCR-HB',
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
    }
  }
  final hitchBoth = row1?['status'] == 'accepted' &&
      row2?['status'] == 'accepted';
  if (hitchBoth) {
    c.hold(
      id: 'C1.hitch.qty_stock',
      lens: 'CR4',
      severity: 'P1',
      title: 'Dois accepts no mesmo SKU hitch (qty=1)',
      actor: 'seller JWT',
      pre: 'qty produto=1; marketplace+live_only',
      repro: 'accept LI1 depois LI2',
      expected: '2º qty_exceeds_stock',
      obtained: {'r1': row1, 'r2': row2, 'a2': a2?.brief},
    );
  } else {
    c.block('C1.hitch.qty_stock', 'CR4', '2º accept recusado (HOLD hitch)', {
      'r1': row1,
      'r2': row2,
      'a2': a2?.brief,
    });
  }
  row(
    probeId: 'C1.hitch.qty_stock',
    poco: 'CR-C',
    payload: 'hitch marketplace+live_only qty=1 two accepts',
    rpcHttp: a2?.brief ?? 'n/a',
    buyerGet: 'n/a (reserva)',
    verdict: hitchBoth ? 'FAIL' : 'HOLD',
    lens: 'CR4',
    extra: {'r1': row1, 'r2': row2},
  );

  // C2 convert sem PI
  final liveA = await c.createLive(title: '$prefix convA');
  final liveB = await c.createLive(title: '$prefix convB');
  final skuA =
      await c.createProduct(title: '$prefix conv skuA', qty: 1, live: true);
  final skuB =
      await c.createProduct(title: '$prefix conv skuB', qty: 1, live: true);
  final itemA = (liveA == null || skuA == null)
      ? null
      : await c.createLiveItem(
          liveId: liveA,
          title: '$prefix conv itemA',
          ref: 'RTCR-CA',
          kind: 'live_only',
          checkoutProductId: skuA,
          quantity: 1,
        );
  final itemB = (liveB == null || skuB == null)
      ? null
      : await c.createLiveItem(
          liveId: liveB,
          title: '$prefix conv itemB',
          ref: 'RTCR-CB',
          kind: 'live_only',
          checkoutProductId: skuB,
          quantity: 1,
        );
  String? stA;
  HttpHit? convRpc;
  if (liveA != null && itemA != null) {
    final ridA = await c.insertReservation(
      liveId: liveA,
      liveItemId: itemA,
      jwt: c.buyerJwt,
      buyer: c.buyerId,
    );
    if (ridA != null) {
      await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$ridA',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
      convRpc = await c.rpc(
        'batata_live_reservation_stripe_convert',
        {'p_request_id': ridA},
        jwt: c.sellerJwt,
      );
      final afterConv = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$ridA&select=id,status',
        service: true,
      );
      stA = afterConv.map?['status']?.toString();
      if (convRpc.map?['ok'] == true && stA == 'converted') {
        c.hold(
          id: 'C2.convert.nopi',
          lens: 'CR5',
          severity: 'P0',
          title: 'stripe_convert sem PI deixou status=converted',
          actor: 'seller JWT',
          pre: 'accepted, sem order paga',
          repro: 'rpc batata_live_reservation_stripe_convert',
          expected: 'recusa; status≠converted',
          obtained: {'rpc': convRpc.brief, 'status': stA},
        );
      } else {
        c.block('C2.convert.nopi', 'CR5', 'convert sem PI recusado',
            {'rpc': convRpc.brief, 'status': stA});
      }
    }
  }
  row(
    probeId: 'C2.convert.nopi',
    poco: 'CR-C',
    payload: 'stripe_convert accepted sem PI',
    rpcHttp: convRpc?.brief ?? 'fixture fail',
    buyerGet: 'n/a',
    verdict: (convRpc?.map?['ok'] == true && stA == 'converted')
        ? 'FAIL'
        : 'HOLD',
    lens: 'CR5',
    extra: {'status': stA},
  );

  // C2b PI alheio
  HttpHit? recCross;
  Map<String, dynamic>? afterCross;
  if (liveA != null &&
      liveB != null &&
      itemA != null &&
      itemB != null &&
      skuA != null) {
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
      'stripe_payment_intent_id': 'pi_rtcr_stolen_${stamp}_A',
      'amount_paid_cents': 900,
    });
    if (planted.firstId != null) c.createdOrderIds.add(planted.firstId!);
    if (planted.ok && planted.firstId != null && ridB != null) {
      recCross = await c.rpc(
        'batata_live_reconcile_stripe_order',
        {
          'p_order_id': planted.firstId,
          'p_reservation_request_id': ridB,
        },
        jwt: c.sellerJwt,
      );
      afterCross = (await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$ridB&select=id,status,buyer_id,live_id',
        service: true,
      ))
          .map;
      if (recCross.map?['ok'] == true && afterCross?['status'] == 'converted') {
        c.hold(
          id: 'C2.convert.pi_alheio',
          lens: 'CR5',
          severity: 'P0',
          title: 'reconcile order live A → reserva live B converted',
          actor: 'seller JWT',
          pre: 'PI/order de outra live',
          repro: 'rpc batata_live_reconcile_stripe_order orderA + resB',
          expected: 'mismatch recusa',
          obtained: {'rpc': recCross.brief, 'res': afterCross},
        );
      } else {
        c.block('C2.convert.pi_alheio', 'CR5', 'PI alheio recusado',
            recCross.brief);
      }
    }
  }
  row(
    probeId: 'C2.convert.pi_alheio',
    poco: 'CR-C',
    payload: 'reconcile PI liveA → res liveB',
    rpcHttp: recCross?.brief ?? 'plant fail',
    buyerGet: 'n/a',
    verdict: (recCross?.map?['ok'] == true &&
            afterCross?['status'] == 'converted')
        ? 'FAIL'
        : 'HOLD',
    lens: 'CR5',
  );

  // C3 end_live ∥ accept
  final liveR = await c.createLive(title: '$prefix race');
  final skuR =
      await c.createProduct(title: '$prefix race sku', qty: 1, live: true);
  final liR = (liveR == null || skuR == null)
      ? null
      : await c.createLiveItem(
          liveId: liveR,
          title: '$prefix race item',
          ref: 'RTCR-RC',
          kind: 'live_only',
          checkoutProductId: skuR,
          quantity: 1,
        );
  String raceHttp = 'n/a';
  String raceVerdict = 'SKIP';
  Map<String, dynamic>? raceRes;
  Map<String, dynamic>? raceLive;
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
      raceHttp = raced.map((h) => h.brief).join(' | ');
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
      raceRes = afterRace.map;
      raceLive = liveAfter.map;
      final ended = liveAfter.map?['status']?.toString() == 'ended' &&
          liveAfter.map?['is_active'] != true;
      final accepted = afterRace.map?['status']?.toString() == 'accepted';
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
      final lateAccepted = lateRow.map?['status'] == 'accepted' &&
          !accepted &&
          ended;
      if (lateAccepted) {
        raceVerdict = 'FAIL';
        c.hold(
          id: 'C3.end_parallel_accept',
          lens: 'CR6',
          severity: 'P1',
          title: 'Accept depois de live ended',
          actor: 'seller JWT',
          pre: 'status=ended is_active=false',
          repro: 'PATCH accepted após end',
          expected: 'live_ended',
          obtained: {'patch': accLate.brief, 'row': lateRow.map},
        );
      } else {
        raceVerdict = 'HOLD';
        c.block('C3.end_parallel_accept', 'CR6',
            'end/accept race sem accept pós-end', {
          'res': afterRace.map,
          'live': liveAfter.map,
          'late': accLate.brief,
        });
      }
    }
  }
  row(
    probeId: 'C3.end_parallel_accept',
    poco: 'CR-C',
    payload: 'end_live ∥ PATCH accepted',
    rpcHttp: raceHttp,
    buyerGet: 'n/a',
    verdict: raceVerdict,
    lens: 'CR6',
    extra: {'res': raceRes, 'live': raceLive},
  );

  // C4 playback residual — unpublished seller2
  const fakeKey = 'RTCRSTREAM1411secretxx';
  const fakeMuxLive = 'RTCRMUXLIVE1411fake01';
  final liveUnpub = await c.createLive(
    seller: c.seller2Id,
    title: '$prefix mux unpub',
    extra: {
      'mux_playback_id': 'RTCRMUX1411fake0001',
      'playback_id': 'RTCRPB1411plain0001',
    },
  );
  if (liveUnpub != null) {
    await c.rest(
      'PATCH',
      'lives?id=eq.$liveUnpub',
      service: true,
      body: {
        'mux_stream_key': fakeKey,
        'mux_live_id': fakeMuxLive,
        'status': 'ended',
        'is_active': false,
      },
      prefer: 'return=minimal',
    );
  }
  HttpHit? muxHit;
  String? muxVal;
  if (liveUnpub != null) {
    muxHit = await c.rest(
      'GET',
      'lives?id=eq.$liveUnpub&select=id,mux_live_id',
      jwt: c.buyerJwt,
    );
    muxVal = muxHit.map?['mux_live_id']?.toString();
  }
  final muxLeak =
      muxHit != null && muxHit.ok && muxVal != null && muxVal.isNotEmpty;
  if (muxLeak) {
    c.hold(
      id: 'C4.mux.live_id.unpub',
      lens: 'CR7',
      severity: 'P2',
      title: 'Buyer lê mux_live_id de live unpublished',
      actor: 'buyer JWT',
      pre: 'seller2 hub_published=false; live ended',
      repro: 'GET lives?select=mux_live_id unpublished',
      expected: '403 / vazio',
      obtained: muxHit?.brief,
    );
  } else {
    c.block('C4.mux.live_id.unpub', 'CR7', 'buyer não lê mux_live_id',
        muxHit?.brief);
  }
  row(
    probeId: 'C4.mux.live_id.unpub',
    poco: 'CR-C',
    payload: 'GET lives select=mux_live_id unpublished (buyer)',
    rpcHttp: muxHit?.brief ?? 'no live',
    buyerGet: muxLeak ? 'LEAK $muxVal' : 'empty/403',
    verdict: muxLeak ? 'FAIL' : 'HOLD',
    lens: 'CR7',
  );

  await c.endAllCreatedLives();

  for (final hid in c.createdHelperIds) {
    await c.rest(
      'PATCH',
      'seller_helpers?id=eq.$hid',
      service: true,
      body: {'active': false, 'invitation_status': 'rejected'},
      prefer: 'return=minimal',
    );
  }

  final residualCount = table
      .where((r) =>
          '${r['probe_id']}'.contains('esaurito') ||
          '${r['probe_id']}'.contains('control.'))
      .length;
  final failRows =
      table.where((r) => '${r['verdict']}'.startsWith('FAIL')).toList();
  final holdRows = table.where((r) => r['verdict'] == 'HOLD').toList();
  final atrophy = table.isEmpty
      ? false
      : (holdRows.length / table.length) >= 0.5 && failRows.isEmpty;

  await dumpJson('${outDir()}/probes.json', {
    'auditor': 'REDTEAM_BLIND_CR_LIVE_POS_ALLOW_v1',
    'prefix': prefix,
    'liveFomo': liveFomo,
    'table': table,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
    'fomo_persisted': fomoPersisted,
    'residual_control_rows': residualCount,
    'stock_before': stockBefore,
    'stock_after': stockAfter,
    'paid_fomo': paidFomo,
    'seller_hub': sellerPub.map,
  });

  stdout.writeln('TABLE_ROWS=${table.length}');
  stdout.writeln('FAIL_ROWS=${failRows.length}');
  stdout.writeln('HOLD_ROWS=${holdRows.length}');
  stdout.writeln('RESIDUAL_CTRL=$residualCount');
  stdout.writeln('ATROPHY=$atrophy');
  stdout.writeln('FINDINGS=${c.findings.length}');
  stdout.writeln('LENSES=${c.lensesHit.toList()..sort()}');
}
