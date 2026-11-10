import 'dart:io';

import '_rtn.dart';

/// Pass 3 — retract/confirm P0 device tokens; live_items write; tips/actions cross-user; bag REST; tip pending.
void main() async {
  final c = Rtn.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final out = <String, Object?>{
    'auditor': 'REDTEAM_BLIND_N_LIVE_STREAM_v1',
    'pass': 3,
    'stamp': stamp,
    'buyer': c.buyerId,
    'seller': c.sellerId,
    'seller2': c.seller2Id,
  };

  final liveA = await c.insertLive(
    seller: c.sellerId,
    status: 'live',
    active: true,
    muxPlayback: 'rtn3_a_pb_$stamp',
    muxLiveId: 'rtn3_a_mux_$stamp',
    streamKey: 'rtn3_a_sk_$stamp',
  );
  final draft = await c.insertLive(
    seller: c.sellerId,
    status: 'draft',
    active: false,
  );
  final itemH = await c.rest('POST', 'live_items', service: true, body: {
    'live_id': liveA,
    'ref_code': 'RTN3A',
    'title': '$prefix a',
    'price': 7,
    'is_active': true,
    'quantity': 1,
    'status': 'available',
  });
  final itemA = itemH.firstId;
  if (itemA != null) c.createdLiveItemIds.add(itemA);
  final draftItemH = await c.rest('POST', 'live_items', service: true, body: {
    'live_id': draft,
    'ref_code': 'RTN3D',
    'title': '$prefix draft item',
    'price': 4,
    'is_active': true,
    'quantity': 8,
    'status': 'available',
  });
  final draftItem = draftItemH.firstId;
  if (draftItem != null) c.createdLiveItemIds.add(draftItem);
  out['fixtures'] = {
    'liveA': liveA,
    'draft': draft,
    'itemA': itemA,
    'draftItem': draftItem,
    'itemIns': itemH.brief,
  };

  // ----- device tokens: own vs seller -----
  final ownTok = await c.rest(
    'GET',
    'seller_device_tokens?select=id,seller_id,device_id,live_id,token_hash,created_at',
    jwt: c.buyerJwt,
  );
  final sellerTok = await c.rest(
    'GET',
    'seller_device_tokens?seller_id=eq.${c.sellerId}&select=id,seller_id,device_id,token_hash',
    jwt: c.buyerJwt,
  );
  final s2Tok = await c.rest(
    'GET',
    'seller_device_tokens?seller_id=eq.${c.seller2Id}&select=id,seller_id',
    jwt: c.buyerJwt,
  );
  final cols = ownTok.list.isNotEmpty
      ? Map<String, dynamic>.from(ownTok.list.first as Map).keys.toList()
      : <String>[];
  final ownSellerIds = ownTok.list
      .whereType<Map>()
      .map((e) => e['seller_id']?.toString())
      .toSet();
  c.note(
    'p3.n1.tok',
    'device tokens own/seller/s2',
    'own.n=${ownTok.list.length} sellers=$ownSellerIds seller.n=${sellerTok.list.length} s2.n=${s2Tok.list.length} cols=$cols',
    lens: 'N1',
  );
  out['n1.tok'] = {
    'own_n': ownTok.list.length,
    'own_seller_ids': ownSellerIds.toList(),
    'lab_seller_n': sellerTok.list.length,
    's2_n': s2Tok.list.length,
    'cols': cols,
    'own_http': ownTok.status,
    'seller_http': sellerTok.status,
  };
  final seesForeign = ownSellerIds.any((id) => id != null && id != c.buyerId);
  if (ownTok.ok && seesForeign) {
    c.finding(
      id: 'RTN-n1.device.cross',
      lens: 'N1',
      severity: 'P0',
      title: 'comprador lê seller_device_tokens de outros vendedores',
      actor: 'buyer',
      pre: 'GET sem filtro vs seller_id lab',
      repro: 'GET seller_device_tokens',
      expected: 'só rows próprias',
      obtained: 'seller_ids=$ownSellerIds lab_n=${sellerTok.list.length}',
    );
  } else if (ownTok.ok && sellerTok.list.isEmpty) {
    c.hold(
      id: 'n1.device.own_only',
      lens: 'N1',
      title: 'buyer só vê tokens com seller_id=próprio (não o vendedor lab) — P0 pass2 retratado',
      actor: 'buyer',
      obtained: 'own.n=${ownTok.list.length} lab.n=0 cols=$cols',
    );
  }

  final star = await c.rest(
    'GET',
    'seller_device_tokens?select=*&limit=1',
    jwt: c.buyerJwt,
  );
  final starKeys = star.map?.keys.toList();
  out['n1.tok.star_keys'] = starKeys;
  final hasPlain = (starKeys ?? []).any((k) =>
      k.toString().contains('plain') ||
      k.toString() == 'token' ||
      k.toString() == 'device_token');
  if (hasPlain && seesForeign) {
    c.finding(
      id: 'RTN-n1.device.plain',
      lens: 'N1',
      severity: 'P0',
      title: 'token em claro visível via REST',
      actor: 'buyer',
      pre: 'select=*',
      repro: 'GET seller_device_tokens select=*',
      expected: 'só hash',
      obtained: '$starKeys',
    );
  }

  // ----- live_items write / draft leak -----
  if (itemA != null) {
    final patchB = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemA',
      jwt: c.buyerJwt,
      body: {'quantity': 99, 'price': 0.01},
    );
    c.note('p3.n5.patch.buyer', 'buyer PATCH live_items', patchB.brief, lens: 'N5');
    out['n5.patch.buyer'] = patchB.brief;
    if (patchB.ok && patchB.list.isNotEmpty) {
      c.finding(
        id: 'RTN-n5.patch.buyer',
        lens: 'N5',
        severity: 'P0',
        title: 'comprador PATCH quantity/price de live_items alheio',
        actor: 'buyer',
        pre: 'item qty=1',
        repro: 'PATCH live_items',
        expected: '0 rows',
        obtained: patchB.brief,
      );
    } else {
      c.hold(
        id: 'n5.patch.buyer',
        lens: 'N5',
        title: 'buyer PATCH live_items 0 rows',
        actor: 'buyer',
        obtained: patchB,
      );
    }

    final patchS2 = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemA',
      jwt: c.seller2Jwt,
      body: {'quantity': 99},
    );
    c.note('p3.n5.patch.s2', 'seller2 PATCH item A', patchS2.brief, lens: 'N5');
    if (patchS2.ok && patchS2.list.isNotEmpty) {
      c.finding(
        id: 'RTN-n5.patch.s2',
        lens: 'N5',
        severity: 'P0',
        title: 'outro vendedor PATCH live_items da live A',
        actor: 'seller2',
        pre: 'item da live A',
        repro: 'PATCH live_items JWT s2',
        expected: '0 rows',
        obtained: patchS2.brief,
      );
    }

    final delB = await c.rest(
      'DELETE',
      'live_items?id=eq.$itemA',
      jwt: c.buyerJwt,
    );
    c.note('p3.n5.del.buyer', 'buyer DELETE live_items', delB.brief, lens: 'N5');
    if (delB.ok && (delB.list.isNotEmpty || delB.status == 204)) {
      final still = await c.rest(
        'GET',
        'live_items?id=eq.$itemA&select=id',
        service: true,
      );
      if (still.list.isEmpty) {
        c.finding(
          id: 'RTN-n5.del.buyer',
          lens: 'N5',
          severity: 'P0',
          title: 'comprador apaga artigo da live',
          actor: 'buyer',
          pre: 'item A',
          repro: 'DELETE live_items',
          expected: '403',
          obtained: delB.brief,
        );
      }
    }
  }

  final draftGet = await c.rest(
    'GET',
    'live_items?id=eq.$draftItem&select=id,title,quantity,live_id',
    jwt: c.buyerJwt,
  );
  c.note('p3.n5.draft.items', 'buyer GET draft live items', draftGet.brief,
      lens: 'N5');
  out['n5.draft.items'] = draftGet.json ?? draftGet.snippet;
  if (draftGet.ok && draftGet.list.isNotEmpty) {
    c.finding(
      id: 'RTN-n5.draft.items',
      lens: 'N5',
      severity: 'P2',
      title: 'comprador lê artigos de directo em rascunho (qty incluída)',
      actor: 'buyer',
      pre: 'live status=draft, item qty=8',
      repro: 'GET live_items?id=eq.<draftItem>',
      expected: '[] (só Hub/público quando live)',
      obtained: draftGet.brief,
    );
  }

  final fomo = await c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': liveA});
  final restQty = await c.rest(
    'GET',
    'live_items?id=eq.$itemA&select=id,quantity',
    jwt: c.buyerJwt,
  );
  c.note('p3.n5.fomo.vs.rest', 'FOMO vs REST qty',
      'fomo=${fomo.brief} rest=${restQty.brief}',
      lens: 'N5');
  out['n5.fomo'] = fomo.json;
  out['n5.rest.qty'] = restQty.map;
  if (restQty.ok && restQty.map?['quantity'] != null) {
    c.finding(
      id: 'RTN-n5.qty.rest',
      lens: 'N5',
      severity: 'P2',
      title: 'JWT lê quantity exacta em live_items; vitrine Hub/FOMO esconde stock cru',
      actor: 'buyer',
      pre: 'item qty=1, Hub view sem quantity',
      repro: 'GET live_items?select=quantity',
      expected: 'quantidade só via FOMO agregado / RPC stock seller',
      obtained: restQty.map,
      evidence: {'fomo': fomo.map, 'hub_view_has_qty': false},
    );
  }

  // ----- raffle actions / tips cross -----
  final acts = await c.rest(
    'GET',
    'live_raffle_actions?select=id,raffle_id,user_id,action_type,tickets_delta&limit=20',
    jwt: c.buyerJwt,
  );
  final actUsers = acts.list
      .whereType<Map>()
      .map((e) => e['user_id']?.toString())
      .whereType<String>()
      .toSet();
  c.note('p3.n6.actions', 'actions users', 'n=${acts.list.length} users=$actUsers',
      lens: 'N6');
  out['n6.actions.users'] = actUsers.toList();
  final foreignActs = actUsers.where((u) => u != c.buyerId).toList();
  if (foreignActs.isNotEmpty) {
    c.finding(
      id: 'RTN-n6.actions.cross',
      lens: 'N6',
      severity: 'P2',
      title: 'comprador lê live_raffle_actions de outros users',
      actor: 'buyer',
      pre: 'GET sem filtro',
      repro: 'GET live_raffle_actions',
      expected: 'só as próprias acções',
      obtained: 'foreign=${foreignActs.length} n=${acts.list.length}',
    );
  }

  final tipsX = await c.rest(
    'GET',
    'live_tips?buyer_id=neq.${c.buyerId}&select=id,buyer_id,seller_id,amount,status,stripe_session_id&limit=10',
    jwt: c.buyerJwt,
  );
  c.note('p3.n7.tips.x', 'tips of others', tipsX.brief, lens: 'N7');
  out['n7.tips.x'] = {'http': tipsX.status, 'n': tipsX.list.length};
  if (tipsX.ok && tipsX.list.isNotEmpty) {
    c.finding(
      id: 'RTN-n7.tips.cross',
      lens: 'N7',
      severity: 'P1',
      title: 'comprador lê live_tips de outros compradores (montante/session)',
      actor: 'buyer',
      pre: 'GET buyer_id=neq.me',
      repro: 'GET live_tips',
      expected: '[]',
      obtained: tipsX.brief,
    );
  } else {
    c.hold(
      id: 'n7.tips.own',
      lens: 'N7',
      title: 'buyer não lê tips de outros',
      actor: 'buyer',
      obtained: tipsX,
    );
  }

  // ----- tip pending with fake session -----
  final tipPend = await c.rpc(
    'batata_create_live_tip_pending',
    {
      'p_live_id': liveA,
      'p_seller_id': c.sellerId,
      'p_amount': 99.0,
      'p_message': 'rtn3',
      'p_stripe_session_id': 'cs_test_rtn3_forged_$stamp',
    },
    jwt: c.buyerJwt,
  );
  c.note('p3.n7.tip.pending', 'create pending + forged cs', tipPend.brief,
      lens: 'N7');
  out['n7.tip.pending'] = tipPend.json ?? tipPend.snippet;
  if (tipPend.ok &&
      (tipPend.map?['ok'] == true || tipPend.body.contains('tip'))) {
    c.finding(
      id: 'RTN-n7.tip.pending.cs',
      lens: 'N7',
      severity: 'P1',
      title: 'create_live_tip_pending aceita stripe_session_id forjado',
      actor: 'buyer',
      pre: 'cs_test_rtn3_forged',
      repro: 'rpc batata_create_live_tip_pending p_stripe_session_id=forjado',
      expected: 'ignorar session do cliente / só Edge',
      obtained: tipPend.brief,
    );
  } else {
    c.hold(
      id: 'n7.tip.pending',
      lens: 'N7',
      title: 'create_live_tip_pending não persistiu session forjada',
      actor: 'buyer',
      obtained: tipPend,
    );
  }

  // ----- reservation REST -----
  final bag = await c.rest(
    'POST',
    'live_reservation_requests',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveA,
      'live_item_id': itemA,
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'requested_qty': 1,
      'status': 'pending',
      'source': 'fleaber_live',
    },
  );
  c.note('p3.n5.bag.ins', 'buyer INSERT reservation', bag.brief, lens: 'N5');
  out['n5.bag.ins'] = bag.brief;
  final bagId = bag.firstId;
  if (bag.ok && bagId != null) {
    c.createdRequestIds.add(bagId);
    final bagS2 = await c.rest(
      'POST',
      'live_reservation_requests',
      jwt: c.seller2Jwt,
      body: {
        'live_id': liveA,
        'live_item_id': itemA,
        'seller_id': c.sellerId,
        'buyer_id': c.seller2Id,
        'requested_qty': 1,
        'status': 'accepted',
        'source': 'fleaber_live',
      },
    );
    c.note('p3.n5.bag.s2', 'seller2 INSERT accepted on A qty=1', bagS2.brief,
        lens: 'N5');
    if (bagS2.ok &&
        (bagS2.map?['status']?.toString() == 'accepted' ||
            bagS2.list.isNotEmpty)) {
      c.finding(
        id: 'RTN-n5.bag.s2.accept',
        lens: 'N5',
        severity: 'P1',
        title: 'outro actor INSERT reserva já accepted (salta fila)',
        actor: 'seller2',
        pre: 'item qty=1',
        repro: 'POST live_reservation_requests status=accepted',
        expected: 'status forçado pending / 403',
        obtained: bagS2.brief,
      );
    }

    final acc = await c.rpc(
      'batata_live_reservation_accept_available',
      {'p_live_item_id': itemA, 'p_exclude_request_id': bagId},
      jwt: c.buyerJwt,
    );
    c.note('p3.n5.accept', 'buyer accept_available', acc.brief, lens: 'N5');
    out['n5.accept'] = acc.json ?? acc.snippet;
    if (acc.ok && acc.map?['ok'] == true) {
      c.finding(
        id: 'RTN-n5.accept.avail',
        lens: 'N5',
        severity: 'P1',
        title: 'comprador dispara accept_available',
        actor: 'buyer',
        pre: 'RPC seller-ops',
        repro: 'rpc batata_live_reservation_accept_available',
        expected: 'not_allowed',
        obtained: acc.brief,
      );
    }

    final qOthers = await c.rest(
      'GET',
      'live_reservation_requests?live_id=eq.$liveA&select=id,buyer_id,status,requested_qty',
      jwt: c.buyerJwt,
    );
    c.note('p3.n5.req.get', 'buyer GET reservations of live', qOthers.brief,
        lens: 'N5');
    out['n5.req.get'] = {
      'http': qOthers.status,
      'n': qOthers.list.length,
      'snip': qOthers.snippet
    };
    final others = qOthers.list.whereType<Map>().where((e) {
      return e['buyer_id']?.toString() != c.buyerId;
    }).toList();
    if (others.isNotEmpty) {
      c.finding(
        id: 'RTN-n5.req.cross',
        lens: 'N5',
        severity: 'P1',
        title: 'comprador lê reservas de outros na mesma live',
        actor: 'buyer',
        pre: 'GET live_reservation_requests',
        repro: 'GET live_reservation_requests?live_id=',
        expected: 'só as próprias',
        obtained: 'n_other=${others.length}',
      );
    }
  } else if (!bag.ok) {
    c.hold(
      id: 'n5.bag.ins',
      lens: 'N5',
      title: 'buyer INSERT reservation recusado/erro',
      actor: 'buyer',
      obtained: bag,
    );
  }

  // chat without spoofed user_id
  final chat = await c.rest(
    'POST',
    'live_messages',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveA,
      'kind': 'chat',
      'body': 'RTN3 hello',
      'sender_label': 'Sistema',
    },
  );
  c.note('p3.n7.chat', 'buyer chat no user_id', chat.brief, lens: 'N7');
  out['n7.chat'] = chat.brief;
  if (chat.ok) {
    if (chat.map?['kind'] == 'chat' &&
        (chat.map?['sender_label']?.toString() == 'Sistema')) {
      c.finding(
        id: 'RTN-n7.chat.label.sys',
        lens: 'N7',
        severity: 'P2',
        title: 'comprador posta chat com sender_label=Sistema',
        actor: 'buyer',
        pre: 'POST live_messages',
        repro: 'POST kind=chat sender_label=Sistema',
        expected: 'label do perfil',
        obtained: chat.map?['sender_label'],
      );
    }
  }

  // migrate catalog as buyer
  final mig = await c.rpc(
    'batata_migrate_live_catalog',
    {'p_seller_id': c.sellerId, 'p_live_id': liveA},
    jwt: c.buyerJwt,
  );
  c.note('p3.n5.migrate', 'buyer migrate catalog', mig.brief, lens: 'N5');
  out['n5.migrate'] = mig.json ?? mig.snippet;

  final recon = await c.rpc(
    'batata_live_reconcile_stripe_order',
    {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    jwt: c.buyerJwt,
  );
  c.note('p3.n5.recon', 'buyer reconcile fake order', recon.brief, lens: 'N5');
  out['n5.recon'] = recon.json ?? recon.snippet;

  final startOpen = await c.rpc(
    'batata_live_start_open_reservations_check',
    {'p_live_id': liveA},
    jwt: c.buyerJwt,
  );
  c.note('p3.n5.startopen', 'buyer start open reservations check', startOpen.brief,
      lens: 'N5');
  out['n5.startopen'] = startOpen.json ?? startOpen.snippet;

  await c.endLives();
  out['findings'] = c.findings;
  out['holds'] = c.holds;
  out['notes'] = c.notes;
  await dumpJson('${outDir()}/pass3.json', out);
  stdout.writeln('FINDINGS ${c.findings.length} HOLDS ${c.holds.length}');
  stdout.writeln('WROTE ${outDir()}/pass3.json');
}
