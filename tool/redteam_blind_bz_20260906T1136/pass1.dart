/// REDTEAM_BLIND_BZ_LIVE_POS_BRBW_v1 — pass1 FOMO novos + convert sem PI.
/// Staging only. No fixes.
import 'dart:io';

import '_rtbz.dart';

Future<void> main() async {
  final c = Rtbz.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureHelperChatOnly();

  final liveId = await c.createLive(title: '$prefix p1');
  final sku = await c.createProduct(title: '$prefix p1 sku', qty: 1, live: true);
  if (liveId == null || sku == null) {
    stderr.writeln('fixture live/sku fail');
    exit(4);
  }
  final itemId = await c.createLiveItem(
    liveId: liveId,
    title: '$prefix p1 item',
    ref: 'RTBZ-P1A',
    kind: 'live_only',
    checkoutProductId: sku,
    quantity: 1,
  );
  if (itemId == null) {
    stderr.writeln('fixture item fail ${c.notes}');
    await c.endAllCreatedLives();
    exit(4);
  }

  Future<void> tryFomo({
    required String id,
    required String body,
    required String? jwt,
    required String actor,
    bool exactClosed = false,
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
    final err = h.map?['error']?.toString() ?? h.brief;
    if (ok) {
      if (exactClosed) {
        c.note(id, 'persistiu (exacto BT/BN, não contar)', h.brief, lens: 'BZ2');
      } else {
        c.hold(
          id: id,
          lens: 'BZ2',
          severity: 'P2',
          title: 'FOMO anúncio de compra persistiu: $body',
          actor: actor,
          pre: 'denylist BRBW sem este sinónimo',
          repro: 'rpc batata_live_system_message p_body=$body',
          expected: 'ok=false purchase_announce_via_broadcast_only',
          obtained: h.brief,
          evidence: {'body': body, 'rpc': h.map},
        );
      }
    } else {
      if (exactClosed) {
        c.block(id, 'BZ2', 'exacto BT/BN recusado (não contar)', err);
      } else {
        c.block(id, 'BZ2', 'sinónimo recusado', err);
      }
    }
  }

  // Exactos BRBW / BT / BN — HOLD, não contar.
  for (final row in [
    ['esgotado', 'esgotado'],
    ['gone', 'gone'],
    ['itsmine', "it's mine"],
    ['outofstock', 'out of stock'],
    ['sold', 'sold'],
    ['soldout', 'sold out'],
    ['claimed', 'claimed'],
    ['snapup', 'snap up'],
    ['levou', 'Ana levou'],
  ]) {
    await tryFomo(
      id: 'p1.fomo.exact.${row[0]}',
      body: row[1],
      jwt: c.sellerJwt,
      actor: 'seller JWT',
      exactClosed: true,
    );
  }

  // Novos sinónimos (contar se persistirem — uma classe).
  for (final row in [
    ['lastone', 'last one'],
    ['janoha', 'já não há'],
    ['janaoha', 'ja nao ha'],
    ['esgotada', 'esgotada'],
    ['esgotados', 'esgotados'],
    ['vendida', 'vendida'],
    ['semstock', 'sem stock'],
    ['nomore', 'no more'],
    ['taken', 'taken'],
    ['thatsmine', "that's mine"],
    ['mine', 'mine'],
    ['ultima', 'última unidade'],
    ['reserved', 'reserved'],
    ['naohamais', 'nao ha mais'],
    ['lastavail', 'last available'],
    ['oneleft', '1 left'],
    ['lastpiece', 'last piece'],
    ['forastock', 'fora de stock'],
    ['janaoexiste', 'já não existe'],
    ['noquedan', 'no quedan'],
    ['itstaken', "it's taken"],
    ['onlyoneleft', 'only one left'],
    ['unavailable', 'unavailable'],
    ['offsale', 'off sale'],
    ['stockzero', 'stock 0'],
    ['zerostock', 'zero stock'],
    ['jasiu', 'já saiu'],
    ['last1', 'last 1'],
  ]) {
    await tryFomo(
      id: 'p1.fomo.new.${row[0]}',
      body: row[1],
      jwt: c.sellerJwt,
      actor: 'seller JWT',
    );
  }

  await tryFomo(
    id: 'p1.fomo.helper.lastone',
    body: 'last one',
    jwt: c.helperJwt,
    actor: 'helper can_manage_chat',
  );
  await tryFomo(
    id: 'p1.fomo.helper.janoha',
    body: 'já não há',
    jwt: c.helperJwt,
    actor: 'helper can_manage_chat',
  );

  // Buyer RPC system.
  final buyerSys = await c.rpc(
    'batata_live_system_message',
    {'p_live_id': liveId, 'p_body': 'last one', 'p_sender_label': 'Sistema'},
    jwt: c.buyerJwt,
  );
  if (buyerSys.map?['ok'] == true) {
    c.hold(
      id: 'p1.fomo.buyer.system',
      lens: 'BZ2',
      severity: 'P2',
      title: 'Buyer RPC system_message last one persistiu',
      actor: 'buyer JWT',
      pre: 'só seller/helper chat',
      repro: 'rpc batata_live_system_message last one',
      expected: 'not_allowed',
      obtained: buyerSys.brief,
    );
  } else {
    c.block('p1.fomo.buyer.system', 'BZ2', 'buyer system recusado',
        buyerSys.brief);
  }

  // INSERT directo kind=system — bypass do denylist RPC.
  Future<void> tryInsertSystem({
    required String id,
    required String? jwt,
    required String actor,
    required String body,
  }) async {
    final uid = actor.contains('buyer')
        ? c.buyerId
        : actor.contains('helper')
            ? c.helperId
            : c.sellerId;
    final h = await c.rest('POST', 'live_messages', jwt: jwt, body: {
      'live_id': liveId,
      'user_id': uid,
      'kind': 'system',
      'body': body,
      'sender_label': 'Sistema',
    });
    if (h.ok && h.firstId != null) {
      c.hold(
        id: id,
        lens: 'BZ2',
        severity: body == 'sold' || body == 'esgotado' ? 'P2' : 'P2',
        title: 'INSERT live_messages kind=system bypass RPC: $body ($actor)',
        actor: actor,
        pre: 'denylist só em batata_live_system_message',
        repro: 'POST live_messages kind=system body=$body',
        expected: '403/RLS',
        obtained: h.brief,
        evidence: {'body': body, 'id': h.firstId},
      );
    } else {
      c.block(id, 'BZ2', 'INSERT system recusado ($actor $body)', h.brief);
    }
  }

  await tryInsertSystem(
    id: 'p1.fomo.insert.buyer.sold',
    jwt: c.buyerJwt,
    actor: 'buyer JWT',
    body: 'sold',
  );
  await tryInsertSystem(
    id: 'p1.fomo.insert.seller.sold',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    body: 'sold',
  );
  await tryInsertSystem(
    id: 'p1.fomo.insert.seller.lastone',
    jwt: c.sellerJwt,
    actor: 'seller JWT',
    body: 'last one',
  );
  await tryInsertSystem(
    id: 'p1.fomo.insert.helper.lastone',
    jwt: c.helperJwt,
    actor: 'helper JWT',
    body: 'last one',
  );

  // Buyer vê as system messages novas.
  final seen = await c.rest(
    'GET',
    'live_messages?live_id=eq.$liveId&kind=eq.system&select=id,body,kind&order=created_at.desc&limit=40',
    jwt: c.buyerJwt,
  );
  final bodies = seen.list
      .whereType<Map>()
      .map((m) => m['body']?.toString() ?? '')
      .toList();
  c.note('p1.fomo.buyer.sees', 'buyer vê system bodies', bodies, lens: 'BZ2');

  // BZ1 — purchase_broadcast sem PI.
  for (final actor in ['buyer', 'seller']) {
    final jwt = actor == 'buyer' ? c.buyerJwt : c.sellerJwt;
    final h = await c.rpc(
      'batata_live_purchase_broadcast',
      {
        'p_live_id': liveId,
        'p_buyer_id': c.buyerId,
        'p_live_item_id': itemId,
      },
      jwt: jwt,
    );
    final persisted = h.json == true || h.map?['ok'] == true;
    if (persisted) {
      c.hold(
        id: 'p1.broadcast.$actor.nopi',
        lens: 'BZ1',
        severity: 'P1',
        title: 'purchase_broadcast sem order paga ($actor)',
        actor: '$actor JWT',
        pre: 'sem PI',
        repro: 'rpc batata_live_purchase_broadcast',
        expected: 'false',
        obtained: h.brief,
      );
    } else {
      c.block('p1.broadcast.$actor.nopi', 'BZ1', 'broadcast sem PI recusado',
          h.brief);
    }
  }

  final accBuyer = await c.rpc(
    'batata_live_reservation_accept_broadcast',
    {
      'p_live_id': liveId,
      'p_buyer_id': c.buyerId,
      'p_live_item_id': itemId,
      'p_requested_qty': 1,
    },
    jwt: c.buyerJwt,
  );
  if (accBuyer.json == true) {
    c.hold(
      id: 'p1.accept_broadcast.buyer',
      lens: 'BZ1',
      severity: 'P2',
      title: 'Buyer JWT accept_broadcast true',
      actor: 'buyer JWT',
      pre: 'só seller/staff',
      repro: 'rpc batata_live_reservation_accept_broadcast buyer',
      expected: 'false',
      obtained: accBuyer.brief,
    );
  } else {
    c.block('p1.accept_broadcast.buyer', 'BZ1',
        'buyer accept_broadcast recusado (exacto, não contar)', accBuyer.brief);
  }

  // Convert sem PI (fleaber_live).
  final rid = await c.insertReservation(
    liveId: liveId,
    liveItemId: itemId,
    jwt: c.buyerJwt,
    buyer: c.buyerId,
  );
  if (rid != null) {
    final acc = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$rid',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    c.note('p1.accept.seller', 'seller PATCH accepted', acc.brief, lens: 'BZ1');

    final convRpc = await c.rpc(
      'batata_live_reservation_stripe_convert',
      {'p_request_id': rid},
      jwt: c.sellerJwt,
    );
    final afterConv = await c.rest(
      'GET',
      'live_reservation_requests?id=eq.$rid&select=id,status',
      service: true,
    );
    final st = afterConv.map?['status']?.toString();
    if (convRpc.map?['ok'] == true && st == 'converted') {
      c.hold(
        id: 'p1.convert.seller.nopi',
        lens: 'BZ1',
        severity: 'P0',
        title: 'stripe_convert sem PI deixou status=converted',
        actor: 'seller JWT',
        pre: 'accepted, sem order paga',
        repro: 'rpc batata_live_reservation_stripe_convert',
        expected: 'recusa; status≠converted',
        obtained: {'rpc': convRpc.brief, 'row': afterConv.map},
      );
    } else {
      c.block('p1.convert.seller.nopi', 'BZ1', 'convert sem PI recusado',
          {'rpc': convRpc.brief, 'status': st});
    }

    final patchConv = await c.rest(
      'PATCH',
      'live_reservation_requests?id=eq.$rid',
      jwt: c.sellerJwt,
      body: {'status': 'converted'},
    );
    final afterP = await c.rest(
      'GET',
      'live_reservation_requests?id=eq.$rid&select=id,status',
      service: true,
    );
    if (patchConv.ok && afterP.map?['status'] == 'converted') {
      c.hold(
        id: 'p1.patch.converted.nopi',
        lens: 'BZ8',
        severity: 'P0',
        title: 'PATCH converted sem order paga',
        actor: 'seller JWT',
        pre: 'accepted, sem PI',
        repro: 'PATCH status=converted',
        expected: 'convert_requires_paid_order',
        obtained: {'patch': patchConv.brief, 'row': afterP.map},
      );
    } else {
      c.block('p1.patch.converted.nopi', 'BZ8', 'PATCH converted recusado',
          patchConv.brief);
    }
  }

  // facebook_manual: seller cria accepted + convert sem PI.
  final liveFb = await c.createLive(title: '$prefix p1 fb');
  final skuFb =
      await c.createProduct(title: '$prefix p1 fb sku', qty: 1, live: true);
  final itemFb = (liveFb == null || skuFb == null)
      ? null
      : await c.createLiveItem(
          liveId: liveFb,
          title: '$prefix p1 fb item',
          ref: 'RTBZ-P1FB',
          kind: 'live_only',
          checkoutProductId: skuFb,
          quantity: 1,
        );
  if (liveFb != null && itemFb != null) {
    final fbRes = await c.insertReservation(
      liveId: liveFb,
      liveItemId: itemFb,
      jwt: c.sellerJwt,
      buyer: c.buyerId,
      seller: c.sellerId,
      status: 'pending',
      source: 'facebook_manual',
    );
    c.note('p1.fb.insert', 'facebook_manual pending seller JWT', fbRes,
        lens: 'BZ1');
    if (fbRes != null) {
      final fbAcc = await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$fbRes',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
      c.note('p1.fb.accept', 'facebook_manual accept', fbAcc.brief, lens: 'BZ1');
      final fbConv = await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$fbRes',
        jwt: c.sellerJwt,
        body: {'status': 'converted'},
      );
      final fbAfter = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$fbRes&select=id,status,source',
        service: true,
      );
      if (fbConv.ok && fbAfter.map?['status'] == 'converted') {
        c.hold(
          id: 'p1.fb.patch.converted.nopi',
          lens: 'BZ1',
          severity: 'P0',
          title: 'facebook_manual PATCH converted sem PI',
          actor: 'seller JWT',
          pre: 'source=facebook_manual accepted, sem order paga',
          repro: 'PATCH status=converted',
          expected: 'convert_requires_paid_order',
          obtained: {'patch': fbConv.brief, 'row': fbAfter.map},
        );
      } else {
        c.block('p1.fb.patch.converted.nopi', 'BZ1',
            'facebook_manual convert recusado', fbConv.brief);
      }
    }

    final fbDirect = await c.insertReservation(
      liveId: liveFb,
      liveItemId: itemFb,
      jwt: c.sellerJwt,
      buyer: c.buyer2Id,
      seller: c.sellerId,
      status: 'converted',
      source: 'facebook_manual',
    );
    if (fbDirect != null) {
      final row = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$fbDirect&select=id,status,source',
        service: true,
      );
      if (row.map?['status'] == 'converted') {
        c.hold(
          id: 'p1.fb.insert.converted',
          lens: 'BZ1',
          severity: 'P0',
          title: 'INSERT facebook_manual já converted sem PI',
          actor: 'seller JWT',
          pre: 'sem order paga',
          repro: 'POST live_reservation_requests source=facebook_manual status=converted',
          expected: 'convert_requires_paid_order',
          obtained: row.map,
        );
      } else {
        c.block('p1.fb.insert.converted', 'BZ1',
            'INSERT converted não ficou converted', row.map);
      }
    } else {
      c.block('p1.fb.insert.converted', 'BZ1',
          'INSERT facebook_manual converted recusado', 'no row');
    }
  }

  await dumpJson('${outDir()}/pass1.json', {
    'auditor': 'REDTEAM_BLIND_BZ_LIVE_POS_BRBW_v1',
    'prefix': prefix,
    'liveId': liveId,
    'itemId': itemId,
    'findings': c.findings,
    'blocked': c.blocked,
    'notes': c.notes,
    'lenses': c.lensesHit.toList()..sort(),
  });
  stdout.writeln(
      'pass1 done findings=${c.findings.length} blocked=${c.blocked.length}');
}
