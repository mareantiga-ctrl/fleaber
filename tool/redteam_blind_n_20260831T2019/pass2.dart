import 'dart:convert';
import 'dart:io';

import '_rtn.dart';

/// Pass 2 — raffle mint RPCs, prize order, bag/items, LiveKit admin, device tokens.
void main() async {
  final c = Rtn.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final out = <String, Object?>{
    'auditor': 'REDTEAM_BLIND_N_LIVE_STREAM_v1',
    'pass': 2,
    'stamp': stamp,
  };

  final liveA = await c.insertLive(
    seller: c.sellerId,
    status: 'live',
    active: true,
    muxPlayback: 'rtn2_a_pb_$stamp',
    muxLiveId: 'rtn2_a_mux_$stamp',
    streamKey: 'rtn2_a_sk_$stamp',
    egressId: 'EG_RTN2_A_$stamp',
  );
  final liveB = await c.insertLive(
    seller: c.seller2Id,
    status: 'live',
    active: true,
    muxPlayback: 'rtn2_b_pb_$stamp',
    muxLiveId: 'rtn2_b_mux_$stamp',
    streamKey: 'rtn2_b_sk_$stamp',
    egressId: 'EG_RTN2_B_$stamp',
  );
  final prod = await c.insertProduct(title: '$prefix p2', qty: 1, price: 11);

  Future<String?> tryItem(String label, Map<String, dynamic> body) async {
    final h = await c.rest('POST', 'live_items', service: true, body: body);
    c.note('p2.item.$label', 'insert live_items', h.brief, lens: 'N5');
    out['item_$label'] = h.brief;
    return h.firstId;
  }

  var itemA = await tryItem('min', {
    'live_id': liveA,
    'ref_code': 'RTN2A',
    'title': '$prefix artigo',
    'price': 11,
    'is_active': true,
  });
  itemA ??= await tryItem('qty', {
    'live_id': liveA,
    'ref_code': 'RTN2B',
    'title': '$prefix artigo',
    'price': 11,
    'is_active': true,
    'quantity': 1,
    'status': 'available',
  });
  itemA ??= await tryItem('kind', {
    'live_id': liveA,
    'ref_code': 'RTN2C',
    'title': '$prefix artigo',
    'price': 11,
    'is_active': true,
    'quantity': 1,
    'item_kind': 'product',
    'product_id': prod,
  });
  if (itemA != null) c.createdLiveItemIds.add(itemA);

  final raffle = await c.insertRaffle(liveId: liveA!, liveItemId: itemA);
  out['fixtures'] = {
    'liveA': liveA,
    'liveB': liveB,
    'itemA': itemA,
    'raffle': raffle,
    'prod': prod,
  };

  // ---- N6 mint tickets RPC ----
  if (raffle != null) {
    final mint = await c.rpc(
      'batata_award_live_raffle_tickets',
      {
        'p_raffle_id': raffle,
        'p_user_id': c.buyerId,
        'p_action_type': 'rtn_mint',
        'p_tickets_delta': 50,
        'p_source_id': 'rtn-mint-$stamp',
      },
      jwt: c.buyerJwt,
    );
    c.note('p2.n6.mint', 'buyer award tickets +50', mint.brief, lens: 'N6');
    out['n6.mint'] = mint.json ?? mint.snippet;
    if (mint.ok && mint.map?['ok'] == true) {
      c.finding(
        id: 'RTN-n6.mint.tickets',
        lens: 'N6',
        severity: 'P1',
        title: 'JWT comprador chama batata_award_live_raffle_tickets e aumenta saldo',
        actor: 'buyer',
        pre: 'rifa activa, RPC DEFINER sem assert de seller no corpo original',
        repro: 'POST rpc/batata_award_live_raffle_tickets delta=50',
        expected: '403 / not_allowed (só service_role)',
        obtained: mint.brief,
        evidence: {'json': mint.map},
      );
    } else {
      c.hold(
        id: 'n6.mint',
        lens: 'N6',
        title: 'award_live_raffle_tickets JWT recusado',
        actor: 'buyer',
        obtained: mint,
      );
    }

    await c.rpc('batata_join_live_raffle', {'p_raffle_id': raffle},
        jwt: c.buyerJwt);
    final share1 = await c.rpc(
      'batata_claim_live_raffle_share_intent',
      {'p_raffle_id': raffle},
      jwt: c.buyerJwt,
    );
    final share2 = await c.rpc(
      'batata_claim_live_raffle_share_intent',
      {'p_raffle_id': raffle},
      jwt: c.buyerJwt,
    );
    c.note('p2.n6.share', 'share x2', '${share1.brief} | ${share2.brief}',
        lens: 'N6');
    out['n6.share'] = {'a': share1.map, 'b': share2.map};
    if (share2.map?['ok'] == true && share2.map?['duplicate'] != true) {
      final b1 = share1.map?['ticket_balance'];
      final b2 = share2.map?['ticket_balance'];
      if (b1 is num && b2 is num && b2 > b1) {
        c.finding(
          id: 'RTN-n6.share.dup',
          lens: 'N6',
          severity: 'P2',
          title: 'share intent duplicado aumenta tickets',
          actor: 'buyer',
          pre: 'já claimed',
          repro: 'claim_live_raffle_share_intent ×2',
          expected: 'duplicate',
          obtained: '$b1 → $b2',
        );
      }
    }

    final link = await c.rpc(
      'batata_ensure_live_raffle_referral_link',
      {'p_raffle_id': raffle},
      jwt: c.buyerJwt,
    );
    c.note('p2.n6.link', 'buyer ensure referral link', link.brief, lens: 'N6');
    out['n6.link'] = link.json ?? link.snippet;

    final winIns = await c.rest(
      'POST',
      'live_raffle_winners',
      jwt: c.buyerJwt,
      body: {
        'raffle_id': raffle,
        'user_id': c.buyerId,
        'rank': 1,
      },
    );
    c.note('p2.n6.win.insert', 'buyer INSERT winners', winIns.brief, lens: 'N6');
    if (winIns.ok && winIns.firstId != null) {
      c.finding(
        id: 'RTN-n6.win.insert',
        lens: 'N6',
        severity: 'P1',
        title: 'comprador INSERT live_raffle_winners',
        actor: 'buyer',
        pre: 'sem draw',
        repro: 'POST live_raffle_winners',
        expected: '403',
        obtained: winIns.brief,
      );
    }

    final prize = await c.rpc(
      'batata_create_raffle_prize_order',
      {
        'p_raffle_id': raffle,
        'p_winner_uid': c.buyerId,
        'p_rank': 1,
      },
      jwt: c.buyerJwt,
    );
    c.note('p2.n6.prize', 'buyer create prize order', prize.brief, lens: 'N6');
    out['n6.prize'] = prize.json ?? prize.snippet;
    if (prize.ok && prize.body.contains('-') && prize.status == 200) {
      c.finding(
        id: 'RTN-n6.prize.order',
        lens: 'N6',
        severity: 'P0',
        title: 'comprador cria encomenda prémio-rifa',
        actor: 'buyer',
        pre: 'sem ser winner oficial / ou após INSERT winner',
        repro: 'rpc batata_create_raffle_prize_order',
        expected: 'not_allowed / not_raffle_winner',
        obtained: prize.brief,
      );
    } else {
      c.hold(
        id: 'n6.prize',
        lens: 'N6',
        title: 'create_raffle_prize_order JWT não criou order',
        actor: 'buyer',
        obtained: prize,
      );
    }

    final entIns = await c.rest(
      'POST',
      'live_raffle_entries',
      jwt: c.buyerJwt,
      body: {
        'raffle_id': raffle,
        'live_id': liveA,
        'user_id': c.buyer2Id,
        'ticket_balance': 99,
        'is_eligible': true,
      },
    );
    c.note('p2.n6.entry.insert', 'buyer INSERT entries B2 +99', entIns.brief,
        lens: 'N6');
    if (entIns.ok && entIns.firstId != null) {
      c.finding(
        id: 'RTN-n6.entry.insert',
        lens: 'N6',
        severity: 'P1',
        title: 'comprador INSERT live_raffle_entries com ticket_balance 99',
        actor: 'buyer',
        pre: 'JWT B1, user_id B2',
        repro: 'POST live_raffle_entries',
        expected: '403',
        obtained: entIns.brief,
      );
    }

    final entUpd = await c.rest(
      'PATCH',
      'live_raffle_entries?raffle_id=eq.$raffle&user_id=eq.${c.buyerId}',
      jwt: c.buyerJwt,
      body: {'ticket_balance': 99},
    );
    c.note('p2.n6.entry.patch', 'buyer PATCH own tickets 99', entUpd.brief,
        lens: 'N6');
    if (entUpd.ok && entUpd.list.isNotEmpty) {
      c.finding(
        id: 'RTN-n6.entry.patch',
        lens: 'N6',
        severity: 'P1',
        title: 'comprador PATCH ticket_balance da própria entry',
        actor: 'buyer',
        pre: 'já joined',
        repro: 'PATCH live_raffle_entries ticket_balance=99',
        expected: '0 rows / 403',
        obtained: entUpd.brief,
      );
    }

    final stateAnon = await c.rpc(
      'batata_get_live_raffle_state',
      {'p_live_id': liveA},
    );
    c.note('p2.n6.state.anon', 'anon raffle state', stateAnon.brief, lens: 'N6');
    out['n6.state.anon'] = stateAnon.json ?? stateAnon.snippet;

    final closeB = await c.rpc(
      'batata_close_live_raffle',
      {'p_raffle_id': raffle},
      jwt: c.buyerJwt,
    );
    c.note('p2.n6.close.buyer', 'buyer close raffle', closeB.brief, lens: 'N6');
    if (closeB.ok && closeB.map?['ok'] == true) {
      c.finding(
        id: 'RTN-n6.close.buyer',
        lens: 'N6',
        severity: 'P1',
        title: 'comprador fecha rifa alheia',
        actor: 'buyer',
        pre: 'rifa do vendedor',
        repro: 'rpc batata_close_live_raffle',
        expected: 'not_allowed',
        obtained: closeB.brief,
      );
    }

    final cancelS2 = await c.rpc(
      'batata_cancel_live_raffle',
      {'p_raffle_id': raffle},
      jwt: c.seller2Jwt,
    );
    c.note('p2.n6.cancel.s2', 'seller2 cancel A raffle', cancelS2.brief,
        lens: 'N6');
    if (cancelS2.ok && cancelS2.map?['ok'] == true) {
      c.finding(
        id: 'RTN-n6.cancel.s2',
        lens: 'N6',
        severity: 'P1',
        title: 'outro vendedor cancela rifa alheia',
        actor: 'seller2',
        pre: 'rifa de A',
        repro: 'rpc batata_cancel_live_raffle',
        expected: 'not_allowed',
        obtained: cancelS2.brief,
      );
    }
  }

  // ---- N5 live items REST + RPCs ----
  for (final actor in [
    ['anon', null],
    ['buyer', c.buyerJwt],
    ['seller2', c.seller2Jwt],
    ['seller', c.sellerJwt],
  ]) {
    final h = await c.rest(
      'GET',
      'live_items?live_id=eq.$liveA&select=id,title,quantity,price,status,ref_code',
      jwt: actor[1] as String?,
    );
    c.note('p2.n5.items.${actor[0]}', '${actor[0]} GET live_items', h.brief,
        lens: 'N5');
    out['items.${actor[0]}'] = {
      'http': h.status,
      'n': h.list.length,
      'snip': h.snippet
    };
  }

  if (itemA != null) {
    final stockAnon = await c.rpc(
      'batata_live_item_stock',
      {'p_live_item_id': itemA},
    );
    c.note('p2.n5.stock.anon', 'anon stock', stockAnon.brief, lens: 'N5');
    out['n5.stock.anon'] = stockAnon.json ?? stockAnon.snippet;

    final upsert = await c.rpc(
      'batata_upsert_live_only_item',
      {
        'p_seller_id': c.sellerId,
        'p_live_id': liveA,
        'p_title': '$prefix stolen',
        'p_price': 1,
        'p_quantity': 5,
      },
      jwt: c.buyerJwt,
    );
    c.note('p2.n5.upsert.buyer', 'buyer upsert live-only as seller', upsert.brief,
        lens: 'N5');
    out['n5.upsert'] = upsert.json ?? upsert.snippet;
    if (upsert.ok && upsert.firstId != null) {
      c.finding(
        id: 'RTN-n5.upsert.buyer',
        lens: 'N5',
        severity: 'P1',
        title: 'comprador upsert artigo live na loja alheia',
        actor: 'buyer',
        pre: 'p_seller_id alheio',
        repro: 'rpc batata_upsert_live_only_item',
        expected: 'not_allowed',
        obtained: upsert.brief,
      );
    }

    final setActive = await c.rpc(
      'set_active_live_item',
      {'p_live_item_id': itemA},
      jwt: c.buyerJwt,
    );
    c.note('p2.n5.setactive', 'buyer set_active_live_item', setActive.brief,
        lens: 'N5');

    final recompute = await c.rpc(
      'batata_recompute_live_item_status',
      {'p_live_item_id': itemA},
      jwt: c.buyerJwt,
    );
    c.note('p2.n5.recompute', 'buyer recompute', recompute.brief, lens: 'N5');

    final mkt = await c.rpc(
      'batata_upsert_marketplace_live_item',
      {
        'p_seller_id': c.sellerId,
        'p_product_id': prod,
        'p_live_id': liveA,
      },
      jwt: c.buyerJwt,
    );
    c.note('p2.n5.mkt', 'buyer upsert marketplace item', mkt.brief, lens: 'N5');
    if (mkt.ok && mkt.body.contains('-') && mkt.status == 200) {
      c.finding(
        id: 'RTN-n5.mkt.buyer',
        lens: 'N5',
        severity: 'P1',
        title: 'comprador liga produto do vendedor ao directo',
        actor: 'buyer',
        pre: 'p_seller_id alheio',
        repro: 'rpc batata_upsert_marketplace_live_item',
        expected: 'not_allowed',
        obtained: mkt.brief,
      );
    }

    final req1 = await c.insertReservation(
      liveId: liveA,
      liveItemId: itemA,
      buyer: c.buyerId,
      qty: 1,
    );
    final accAvail = await c.rpc(
      'batata_live_reservation_accept_available',
      {'p_live_item_id': itemA, 'p_request_id': req1},
      jwt: c.buyerJwt,
    );
    c.note('p2.n5.accept.avail', 'buyer accept_available', accAvail.brief,
        lens: 'N5');
    out['n5.accept.avail'] = accAvail.json ?? accAvail.snippet;
    if (accAvail.ok && accAvail.map?['ok'] == true) {
      c.finding(
        id: 'RTN-n5.accept.avail',
        lens: 'N5',
        severity: 'P1',
        title: 'comprador accept_available da própria reserva',
        actor: 'buyer',
        pre: 'pedido pending',
        repro: 'rpc batata_live_reservation_accept_available',
        expected: 'not_allowed',
        obtained: accAvail.brief,
      );
    }

    final qLive = await c.rpc(
      'batata_live_reservation_queue_for_live',
      {'p_live_id': liveA, 'p_include_history': true},
      jwt: c.buyerJwt,
    );
    c.note('p2.n5.queue', 'buyer queue-for-live', qLive.brief, lens: 'N5');
    out['n5.queue'] = {
      'http': qLive.status,
      'n': qLive.list.length,
      'snip': qLive.snippet
    };
    final queueHasOther = qLive.list.any((e) {
      if (e is! Map) return false;
      final bid = e['buyer_id']?.toString();
      return bid != null && bid != c.buyerId;
    });
    if (qLive.ok && queueHasOther) {
      c.finding(
        id: 'RTN-n5.queue.pii',
        lens: 'N5',
        severity: 'P1',
        title: 'comprador vê fila de reservas de outros (buyer_id)',
        actor: 'buyer',
        pre: 'RPC queue for live',
        repro: 'rpc batata_live_reservation_queue_for_live',
        expected: 'só as próprias / not_allowed',
        obtained: qLive.brief,
      );
    }

    if (req1 != null) {
      final bagQty = await c.rpc(
        'batata_live_bag_update_qty',
        {'p_request_id': req1, 'p_qty': 99},
        jwt: c.buyer2Jwt,
      );
      c.note('p2.n5.bag.b2', 'B2 update qty of B1 bag', bagQty.brief, lens: 'N5');
      if (bagQty.ok && bagQty.map?['ok'] == true) {
        c.finding(
          id: 'RTN-n5.bag.b2',
          lens: 'N5',
          severity: 'P1',
          title: 'B2 altera qty do saco de B1',
          actor: 'buyer2',
          pre: 'pedido de B1',
          repro: 'rpc batata_live_bag_update_qty',
          expected: 'not_allowed',
          obtained: bagQty.brief,
        );
      }
      final bagRm = await c.rpc(
        'batata_live_bag_remove_request',
        {'p_request_id': req1},
        jwt: c.buyer2Jwt,
      );
      c.note('p2.n5.bagrm.b2', 'B2 remove B1 bag', bagRm.brief, lens: 'N5');
      if (bagRm.ok && bagRm.map?['ok'] == true) {
        c.finding(
          id: 'RTN-n5.bagrm.b2',
          lens: 'N5',
          severity: 'P1',
          title: 'B2 remove reserva de B1',
          actor: 'buyer2',
          pre: 'pedido de B1',
          repro: 'rpc batata_live_bag_remove_request',
          expected: 'not_allowed',
          obtained: bagRm.brief,
        );
      }
    }
  }

  // ---- N7 viewers / private messages / tips ----
  final viewers = await c.rest(
    'GET',
    'live_viewers?live_id=eq.$liveA&select=*',
    jwt: c.buyerJwt,
  );
  c.note('p2.n7.viewers', 'buyer GET live_viewers', viewers.brief, lens: 'N7');
  out['n7.viewers'] = {'http': viewers.status, 'n': viewers.list.length};
  if (viewers.ok && viewers.list.any((e) {
    return e is Map && e['user_id']?.toString() != c.buyerId;
  })) {
    c.finding(
      id: 'RTN-n7.viewers.pii',
      lens: 'N7',
      severity: 'P2',
      title: 'comprador lista user_id de outros espectadores',
      actor: 'buyer',
      pre: 'GET live_viewers',
      repro: 'GET live_viewers?live_id=',
      expected: 'só a própria row / 403',
      obtained: viewers.brief,
    );
  }

  final pm = await c.rest(
    'GET',
    'live_private_messages?select=*&limit=5',
    jwt: c.buyerJwt,
  );
  c.note('p2.n7.pm', 'buyer GET live_private_messages', pm.brief, lens: 'N7');
  out['n7.pm'] = {'http': pm.status, 'n': pm.list.length, 'snip': pm.snippet};

  final chat = await c.rest(
    'POST',
    'live_messages',
    jwt: c.buyerJwt,
    body: {
      'live_id': liveA,
      'kind': 'chat',
      'body': 'RTN chat',
      'sender_label': 'Maria Demo FleaHub',
      'user_id': c.sellerId,
    },
  );
  c.note('p2.n7.chat.impersonate', 'buyer chat as seller label', chat.brief,
      lens: 'N7');
  if (chat.ok) {
    final uid = chat.map?['user_id']?.toString();
    if (uid == c.sellerId) {
      c.finding(
        id: 'RTN-n7.chat.uid',
        lens: 'N7',
        severity: 'P1',
        title: 'comprador grava live_messages.user_id do vendedor',
        actor: 'buyer',
        pre: 'POST chat user_id=seller',
        repro: 'POST live_messages',
        expected: 'user_id = JWT',
        obtained: chat.brief,
      );
    } else {
      c.note('p2.n7.chat.label', 'label spoof possível user_id=$uid', chat.brief,
          lens: 'N7');
      if ((chat.map?['sender_label']?.toString() ?? '').contains('Maria')) {
        c.finding(
          id: 'RTN-n7.chat.label',
          lens: 'N7',
          severity: 'P2',
          title: 'comprador spoofa sender_label do vendedor no chat público',
          actor: 'buyer',
          pre: 'POST live_messages sender_label=nome do seller',
          repro: 'POST live_messages kind=chat',
          expected: 'label derivado do perfil JWT',
          obtained: chat.map?['sender_label'],
        );
      }
    }
  }

  final tipPend = await c.rpc(
    'batata_create_live_tip_pending',
    {
      'p_live_id': liveA,
      'p_seller_id': c.sellerId,
      'p_amount': 1.0,
      'p_buyer_id': c.sellerId,
    },
    jwt: c.buyerJwt,
  );
  c.note('p2.n7.tip.pending', 'create tip pending spoof buyer', tipPend.brief,
      lens: 'N7');
  out['n7.tip.pending'] = tipPend.json ?? tipPend.snippet;

  final settle = await c.rpc(
    'batata_settle_live_tip_from_stripe',
    {
      'p_session_id': 'cs_test_rtn_forged_$stamp',
    },
    jwt: c.buyerJwt,
  );
  c.note('p2.n7.tip.settle', 'JWT settle tip forged cs', settle.brief, lens: 'N7');
  out['n7.tip.settle'] = settle.json ?? settle.snippet;
  if (settle.ok && settle.map?['ok'] == true) {
    c.finding(
      id: 'RTN-n7.tip.settle',
      lens: 'N7',
      severity: 'P0',
      title: 'JWT settle tip com session Stripe forjada',
      actor: 'buyer',
      pre: 'cs_test_rtn_forged',
      repro: 'rpc batata_settle_live_tip_from_stripe',
      expected: 'fail / só webhook',
      obtained: settle.brief,
    );
  }

  final applyTip = await c.rpc(
    'batata_wallet_apply_tip_once',
    {
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
    },
    jwt: c.buyerJwt,
  );
  c.note('p2.n7.tip.apply', 'JWT wallet_apply_tip_once', applyTip.brief,
      lens: 'N7');
  out['n7.tip.apply'] = applyTip.json ?? applyTip.snippet;

  final syncOrd = await c.rpc(
    'batata_sync_live_item_for_order',
    {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    jwt: c.buyerJwt,
  );
  c.note('p2.n5.sync.order', 'buyer sync live item for fake order', syncOrd.brief,
      lens: 'N5');

  // device tokens
  final tokTab = await c.rest(
    'GET',
    'seller_device_tokens?select=*&limit=5',
    jwt: c.buyerJwt,
  );
  c.note('p2.n1.devicetok', 'buyer GET seller_device_tokens', tokTab.brief,
      lens: 'N1');
  out['n1.device'] = {'http': tokTab.status, 'n': tokTab.list.length};
  if (tokTab.ok && tokTab.list.isNotEmpty) {
    c.finding(
      id: 'RTN-n1.device.tokens',
      lens: 'N1',
      severity: 'P0',
      title: 'comprador lê seller_device_tokens (OCR ingest)',
      actor: 'buyer',
      pre: 'tabela pairing',
      repro: 'GET seller_device_tokens',
      expected: '403',
      obtained: tokTab.brief,
    );
  }
  final tokAnon = await c.rest(
    'GET',
    'seller_device_tokens?select=id,device_token_plain&limit=3',
  );
  c.note('p2.n1.devicetok.anon', 'anon device tokens', tokAnon.brief, lens: 'N1');

  final svcTok = await c.rest(
    'GET',
    'seller_device_tokens?select=id,seller_id,live_id,device_token_plain,expires_at&order=created_at.desc&limit=3',
    service: true,
  );
  out['n1.device.svc.n'] = svcTok.list.length;
  if (svcTok.list.isNotEmpty) {
    final row = Map<String, dynamic>.from(svcTok.list.first as Map);
    final plain = row['device_token_plain']?.toString() ?? '';
    final lid = row['live_id']?.toString() ?? liveA;
    if (plain.isNotEmpty) {
      final ocr = await c.edge(
        'ingest-ocr-reservation',
        extra: {'x-device-token': plain},
        body: {
          'live_id': lid,
          'ocr_line_hash': 'rtn2hash$stamp',
          'requested_qty': 9,
          'ref_slug': 'RTN2A',
        },
      );
      c.note('p2.n5.ocr.stolen', 'OCR with stolen device token', ocr.brief,
          lens: 'N5');
      out['n5.ocr.stolen'] = ocr.brief;
      if (ocr.ok && ocr.map?['ok'] == true) {
        c.finding(
          id: 'RTN-n5.ocr.stolen',
          lens: 'N5',
          severity: 'P1',
          title: 'token de pairing existente aceita ingest OCR hostil (qty 9)',
          actor: 'anon+stolen-token',
          pre: 'token lido via service (simula leak); JWT não leu a tabela',
          repro: 'POST ingest-ocr-reservation x-device-token=<token>',
          expected: 'token bound to device/live; qty cap',
          obtained: ocr.brief,
        );
      }
    }
  }

  // ---- N4 LiveKit admin with owner publisher token ----
  final tok = await c.edge(
    'livekit-mux-publish',
    body: {'step': 'token', 'live_id': liveA},
    jwt: c.sellerJwt,
  );
  final token = tok.map?['token']?.toString();
  final lkUrl = tok.map?['livekit_url']?.toString() ?? '';
  out['n4.token.http'] = tok.status;
  if (token != null && lkUrl.isNotEmpty) {
    final host = lkUrl.replaceFirst('wss://', 'https://').replaceFirst('ws://', 'http://');
    Future<HttpHit> lk(String rpc, [Object? body]) {
      return c.req(
        'POST',
        '$host/twirp/livekit.RoomService/$rpc',
        extra: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body ?? {},
      );
    }

    final listRooms = await lk('ListRooms', {});
    c.note('p2.n4.lk.list', 'owner token ListRooms', listRooms.brief, lens: 'N4');
    out['n4.listRooms'] = listRooms.brief;
    if (listRooms.ok) {
      c.finding(
        id: 'RTN-n4.lk.list',
        lens: 'N4',
        severity: 'P1',
        title: 'token publisher lista rooms LiveKit (admin)',
        actor: 'seller-token',
        pre: 'JWT video.canPublish room-scoped',
        repro: 'POST twirp livekit.RoomService/ListRooms',
        expected: 'permissão negada (não roomAdmin)',
        obtained: listRooms.brief,
      );
    }

    final listEgress = await c.req(
      'POST',
      '$host/twirp/livekit.Egress/ListEgress',
      extra: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: {},
    );
    c.note('p2.n4.lk.egress', 'owner token ListEgress', listEgress.brief,
        lens: 'N4');
    out['n4.listEgress'] = listEgress.brief;
    if (listEgress.ok) {
      c.finding(
        id: 'RTN-n4.lk.egress.list',
        lens: 'N4',
        severity: 'P1',
        title: 'token publisher lista egress (pode expor destinos RTMP)',
        actor: 'seller-token',
        pre: 'mesmo token de publicação',
        repro: 'POST twirp livekit.Egress/ListEgress',
        expected: 'denied',
        obtained: listEgress.brief,
      );
    }

    // join other seller room name from public id
    if (liveB != null) {
      final del = await lk('DeleteRoom', {'room': 'fleaber_${liveB.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '')}'});
      c.note('p2.n4.lk.delB', 'owner A token DeleteRoom B', del.brief, lens: 'N4');
      out['n4.delB'] = del.brief;
      if (del.ok) {
        c.finding(
          id: 'RTN-n4.lk.delB',
          lens: 'N4',
          severity: 'P0',
          title: 'token da live A apaga room LiveKit da live B',
          actor: 'seller-token',
          pre: 'room name previsível fleaber_<uuid>',
          repro: 'DeleteRoom fleaber_<liveB>',
          expected: 'denied (grant room-scoped)',
          obtained: del.brief,
        );
      }
    }
  }

  // real egress IDs in staging
  final realEg = await c.rest(
    'GET',
    'lives?livekit_egress_id=not.is.null&select=id,seller_id,status,livekit_egress_id,livekit_room_name&limit=5',
    service: true,
  );
  out['n4.real_egress'] = realEg.list.map((e) {
    if (e is Map) {
      return {
        'id': e['id'],
        'status': e['status'],
        'egress_len': e['livekit_egress_id']?.toString().length,
      };
    }
    return e;
  }).toList();
  c.note('p2.n4.real.eg', 'staging lives with egress', 'n=${realEg.list.length}',
      lens: 'N4');
  if (realEg.list.isNotEmpty && liveA != null) {
    final eg = (realEg.list.first as Map)['livekit_egress_id']?.toString();
    final owner = (realEg.list.first as Map)['seller_id']?.toString();
    if (eg != null && owner != c.sellerId) {
      final stop = await c.edge(
        'livekit-mux-publish',
        body: {'step': 'stop_egress', 'live_id': liveA, 'egress_id': eg},
        jwt: c.sellerJwt,
      );
      c.note('p2.n4.stop.real', 'stop real foreign egress', stop.brief, lens: 'N4');
      out['n4.stop.real'] = stop.brief;
      if (stop.status == 200) {
        c.finding(
          id: 'RTN-n4.stop.real',
          lens: 'N4',
          severity: 'P1',
          title: 'stop_egress com egress_id LIVE de outro vendedor (HTTP 200)',
          actor: 'seller',
          pre: 'egress real noutro lives row',
          repro: 'POST livekit-mux-publish step=stop_egress egress_id=<alheio>',
          expected: '403',
          obtained: stop.brief,
          evidence: {'foreign_live': (realEg.list.first as Map)['id']},
        );
      }
    }
  }

  // qualify referrals without seller (DEFINER)
  final qual = await c.rpc(
    'batata_qualify_live_raffle_referral_visits',
    {'p_live_id': liveA},
    jwt: c.buyerJwt,
  );
  c.note('p2.n6.qualify', 'buyer qualify referrals', qual.brief, lens: 'N6');
  out['n6.qualify'] = qual.json ?? qual.snippet;

  final activate = raffle == null
      ? null
      : await c.rpc(
          'batata_activate_live_raffle',
          {'p_raffle_id': raffle},
          jwt: c.buyerJwt,
        );
  if (activate != null) {
    c.note('p2.n6.activate', 'buyer activate raffle', activate.brief, lens: 'N6');
  }

  // audit log / actions leak
  final audit = await c.rest(
    'GET',
    'live_raffle_audit_log?select=*&limit=5',
    jwt: c.buyerJwt,
  );
  c.note('p2.n6.audit', 'buyer GET raffle audit', audit.brief, lens: 'N6');
  out['n6.audit'] = {'http': audit.status, 'n': audit.list.length};

  final actions = await c.rest(
    'GET',
    'live_raffle_actions?select=*&limit=5',
    jwt: c.buyerJwt,
  );
  c.note('p2.n6.actions', 'buyer GET raffle actions', actions.brief, lens: 'N6');
  out['n6.actions'] = {'http': actions.status, 'n': actions.list.length};

  final studio = await c.rest(
    'GET',
    'live_vendor_studio_logs?select=*&limit=5',
    jwt: c.buyerJwt,
  );
  c.note('p2.n7.studio', 'buyer GET studio logs', studio.brief, lens: 'N7');
  out['n7.studio'] = {'http': studio.status, 'n': studio.list.length};

  final tips = await c.rest(
    'GET',
    'live_tips?select=*&limit=5',
    jwt: c.buyerJwt,
  );
  c.note('p2.n7.tips', 'buyer GET live_tips', tips.brief, lens: 'N7');
  out['n7.tips'] = {'http': tips.status, 'n': tips.list.length, 'snip': tips.snippet};
  if (tips.ok && tips.list.any((e) => e is Map && e['buyer_id']?.toString() != c.buyerId)) {
    c.finding(
      id: 'RTN-n7.tips.cross',
      lens: 'N7',
      severity: 'P1',
      title: 'comprador lê live_tips de outros',
      actor: 'buyer',
      pre: 'GET live_tips',
      repro: 'GET live_tips',
      expected: 'só as próprias',
      obtained: tips.brief,
    );
  }

  await c.endLives();
  out['findings'] = c.findings;
  out['holds'] = c.holds;
  out['notes'] = c.notes;
  await dumpJson('${outDir()}/pass2.json', out);
  stdout.writeln('FINDINGS ${c.findings.length} HOLDS ${c.holds.length}');
  stdout.writeln('WROTE ${outDir()}/pass2.json');
}
