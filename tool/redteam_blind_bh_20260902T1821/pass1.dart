/// BH pass1 — BH1 convert/broadcast · BH2 staff/FOMO · BH3 stock/Hub
/// Variantes NOVAS: sinónimos FOMO, homoglyph, helper perms parciais.
import 'dart:io';
import '_rtbh.dart';

Future<void> main() async {
  final c = Rtbh.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.ensureHelpers();
  c.note('actors', 'JWT lab', {
    'b1': c.buyerId,
    's1': c.sellerId,
    'b2': c.buyer2Id,
    's2': c.seller2Id,
    'hchat': c.helperChatId,
    'hmark': c.helperMarkId,
    'hview': c.helperViewId,
    'hres': c.helperResId,
  });

  final liveA = await c.insertLive(title: '$prefix-A');
  final liveB = await c.insertLive(seller: c.seller2Id, title: '$prefix-B-s2');
  if (liveA == null) {
    stderr.writeln('no live A');
    await c.dumpAll('pass1.json');
    exit(4);
  }
  final itemOnly = await c.insertLiveItem(liveId: liveA, qty: 2, title: '$prefix-only');
  final sku = await c.insertProduct(price: 18, qty: 1, live: true, title: '$prefix-sku');
  final itemMkt = sku == null
      ? null
      : await c.insertLiveItem(
          liveId: liveA,
          kind: 'marketplace_product',
          productId: sku,
          title: '$prefix-mkt',
        );
  c.note('fixture', 'live A items', {
    'liveA': liveA,
    'liveB': liveB,
    'only': itemOnly,
    'sku': sku,
    'mkt': itemMkt,
  }, lens: 'BH1');

  await _bh1BroadcastConvert(c, liveA, itemOnly, sku, itemMkt);
  await _bh2StaffFomo(c, liveA, liveB, itemOnly);
  await _bh3StockHub(c, liveA, itemOnly, itemMkt);

  await c.endAllLives();
  await c.dumpAll('pass1.json');
  stdout.writeln(
      'DONE p1 findings=${c.findings.length} blocked=${c.blocked.length} lenses=${c.lensesHit.toList()..sort()}');
}

Future<void> _bh1BroadcastConvert(
  Rtbh c,
  String liveA,
  String? itemOnly,
  String? sku,
  String? itemMkt,
) async {
  if (itemOnly == null) return;

  // Exact «comprou» — baseline fechada, não contar se blocked.
  final exact = await c.sysMsg(liveA, '✅ Ana comprou o casaco');
  await c.expectDenied(
    id: 'BH1-00',
    lens: 'BH1',
    title: 'system_message exact comprou (baseline ATBE — não contar se HOLD)',
    hit: exact,
    actor: 'seller JWT',
    pre: 'live A no ar',
    repro: 'rpc batata_live_system_message body ✅ comprou',
    severityIfOpen: 'P2',
    openIf: (h) => h.rpcOk,
  );

  final unpaidBc = await c.purchaseBc(
    liveId: liveA,
    buyer: c.buyerId!,
    itemId: itemOnly,
  );
  if (unpaidBc.rpcOk || unpaidBc.json == true) {
    final msgs = await c.messages(liveA);
    final fake = msgs.any((m) =>
        (m is Map) &&
        '${m['body']}'.toLowerCase().contains('comprou'));
    if (fake) {
      c.hold(
        id: 'BH1-01',
        lens: 'BH1',
        severity: 'P2',
        title: 'purchase_broadcast sem order paga inseriu «comprou»',
        actor: 'seller JWT',
        pre: 'sem order paga do item',
        repro: 'rpc batata_live_purchase_broadcast',
        expected: 'false / sem mensagem',
        obtained: {'rpc': unpaidBc.brief, 'msgs': msgs.take(3).toList()},
      );
    } else {
      c.block('BH1-01', 'BH1', 'purchase_broadcast unpaid (exact — não contar)',
          unpaidBc);
    }
  } else {
    c.block('BH1-01', 'BH1', 'purchase_broadcast unpaid (exact — não contar)',
        unpaidBc);
  }

  // NOVOS sinónimos FOMO
  final synonyms = <String, String>{
    'levou': '🛒 Ana levou o casaco',
    'sold': '✅ Ana sold the jacket',
    'esgotou': 'Ana esgotou a última unidade',
    'homoglyph': '✅ Ana compr\u043eu o casaco', // cyrillic о
    'zwj': '✅ Ana com\u200bprou o casaco',
    'leet': '✅ Ana c0mprou o casaco',
    'cart': '🛒 vendido agora mesmo',
  };
  final persisted = <String, String>{};
  for (final e in synonyms.entries) {
    final h = await c.sysMsg(liveA, e.value);
    if (h.rpcOk) {
      persisted[e.key] = h.brief;
    } else {
      c.block('BH1-02-${e.key}', 'BH1', 'FOMO ${e.key} blocked', h);
    }
  }
  if (persisted.isNotEmpty) {
    final msgs = await c.messages(liveA);
    final bodies = msgs
        .whereType<Map>()
        .map((m) => '${m['body']}')
        .where((b) =>
            b.contains('levou') ||
            b.toLowerCase().contains('sold') ||
            b.contains('esgotou') ||
            b.contains('vendido') ||
            b.contains('compr'))
        .toList();
    c.hold(
      id: 'BH1-02',
      lens: 'BH2',
      severity: 'P2',
      title: 'system_message aceita anúncio FOMO por sinónimo/homoglyph',
      actor: 'seller JWT',
      pre: 'filtro só comprou|purchased|bought',
      repro: 'rpc batata_live_system_message levou/sold/esgotou/cyrillic/ZW/c0mprou',
      expected: 'purchase_announce_via_broadcast_only',
      obtained: {'rpc_ok': persisted, 'bodies': bodies},
      evidence: {'persisted_keys': persisted.keys.toList()},
    );
  }

  // REST INSERT kind=system (bypass RPC)
  final restSys = await c.rest('POST', 'live_messages', jwt: c.sellerJwt, body: {
    'live_id': liveA,
    'user_id': c.sellerId,
    'kind': 'system',
    'body': '✅ Ana levou o artigo (REST)',
    'sender_label': 'Sistema',
  });
  await c.expectDenied(
    id: 'BH1-03',
    lens: 'BH1',
    title: 'INSERT REST live_messages kind=system FOMO',
    hit: restSys,
    actor: 'seller JWT',
    pre: 'RLS insert só kind=chat',
    repro: 'POST live_messages kind=system',
    severityIfOpen: 'P2',
  );

  final restChatFomo = await c.rest('POST', 'live_messages', jwt: c.sellerJwt, body: {
    'live_id': liveA,
    'user_id': c.sellerId,
    'kind': 'chat',
    'body': '✅ Ana levou o casaco',
  });
  if (restChatFomo.ok) {
    c.note('BH1-04', 'chat REST com texto FOMO (não system) persistiu', restChatFomo,
        lens: 'BH1');
  } else {
    c.block('BH1-04', 'BH1', 'chat REST FOMO', restChatFomo);
  }

  // Convert sem PI
  final resH = await c.buyerReserve(itemOnly);
  c.trackRes(resH);
  final rid = resH.firstId;
  if (rid != null) {
    final conv = await c.patchRes(rid, {'status': 'converted'});
    await c.expectDenied(
      id: 'BH1-05',
      lens: 'BH1',
      title: 'PATCH converted sem order paga',
      hit: conv,
      actor: 'seller JWT',
      pre: 'reserva pending, sem PI',
      repro: 'PATCH live_reservation_requests status=converted',
      severityIfOpen: 'P1',
    );
    final acc = await c.patchRes(rid, {'status': 'accepted'});
    if (acc.ok) {
      c.note('BH1-06', 'accept pending→accepted (legítimo hold)', acc, lens: 'BH1');
      final conv2 = await c.patchRes(rid, {'status': 'converted'});
      await c.expectDenied(
        id: 'BH1-07',
        lens: 'BH1',
        title: 'PATCH accepted→converted sem PI',
        hit: conv2,
        actor: 'seller JWT',
        pre: 'accepted, sem order paga',
        repro: 'PATCH status=converted',
        severityIfOpen: 'P1',
      );
    } else {
      c.note('BH1-06', 'accept falhou', acc, lens: 'BH1');
    }
  }

  final stripeConv = await c.rpc('batata_live_reservation_stripe_convert', {
    'p_request_id': rid ?? '00000000-0000-0000-0000-000000000001',
    'p_order_id': null,
  }, jwt: c.sellerJwt);
  await c.expectDenied(
    id: 'BH1-08',
    lens: 'BH1',
    title: 'stripe_convert JWT sem order paga',
    hit: stripeConv,
    actor: 'seller JWT',
    pre: 'reserva sem PI',
    repro: 'rpc batata_live_reservation_stripe_convert',
    severityIfOpen: 'P1',
    openIf: (h) => h.rpcOk,
  );

  // INSERT accepted / converted seller (force_pending)
  if (itemOnly != null) {
    final insAcc = await c.rest('POST', 'live_reservation_requests', jwt: c.sellerJwt, body: {
      'live_id': liveA,
      'live_item_id': itemOnly,
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'requested_qty': 1,
      'source': 'facebook_manual',
      'status': 'accepted',
    });
    c.trackRes(insAcc);
    if (insAcc.ok) {
      final st = insAcc.map?['status']?.toString();
      if (st == 'accepted' || st == 'converted') {
        c.hold(
          id: 'BH1-09',
          lens: 'BH1',
          severity: 'P1',
          title: 'INSERT facebook_manual accepted persistiu a consumir stock sem PI',
          actor: 'seller JWT',
          pre: 'force_pending deveria descer a pending',
          repro: 'POST live_reservation_requests source=facebook_manual status=accepted',
          expected: 'pending ou 4xx',
          obtained: insAcc.brief,
        );
      } else {
        c.block('BH1-09', 'BH1', 'INSERT accepted forçado a $st', insAcc);
      }
    } else {
      c.block('BH1-09', 'BH1', 'INSERT accepted facebook_manual', insAcc);
    }

    final insConv = await c.rest('POST', 'live_reservation_requests', jwt: c.sellerJwt, body: {
      'live_id': liveA,
      'live_item_id': itemOnly,
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'requested_qty': 1,
      'source': 'helper_manual',
      'status': 'converted',
    });
    c.trackRes(insConv);
    if (insConv.ok) {
      final st = insConv.map?['status']?.toString();
      if (st == 'converted') {
        c.hold(
          id: 'BH1-10',
          lens: 'BH1',
          severity: 'P1',
          title: 'INSERT helper_manual converted sem PI',
          actor: 'seller JWT',
          pre: 'sem order paga',
          repro: 'POST reservation status=converted',
          expected: 'convert_requires_paid_order ou pending',
          obtained: insConv.brief,
        );
      } else {
        c.block('BH1-10', 'BH1', 'INSERT converted caiu para $st', insConv);
      }
    } else {
      c.block('BH1-10', 'BH1', 'INSERT converted helper_manual', insConv);
    }
  }

  // Broadcast com order cancelada + PI vivo (service fixture — actor JWT)
  if (sku != null && itemMkt != null) {
    final ord = await c.rest('POST', 'orders', service: true, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': sku,
      'live_id': liveA,
      'live_item_id': itemMkt,
      'quantity': 1,
      'status': 'cancelado',
      'price_total': 18,
      'amount_paid_cents': 0,
      'stripe_payment_intent_id': 'pi_rtbh_ghost_${stamp}',
      'payment_method': 'MB WAY',
      'shipping_method': 'entrega em mão',
    });
    final oid = ord.firstId;
    if (oid != null) c.createdOrderIds.add(oid);
    c.note('BH1-11a', 'order cancelada+PI fixture', ord, lens: 'BH1');
    final bcCancel = await c.purchaseBc(
      liveId: liveA,
      buyer: c.buyerId!,
      itemId: itemMkt,
    );
    final msgs = await c.messages(liveA);
    final announced = msgs.any((m) =>
        m is Map &&
        '${m['body']}'.contains('comprou') &&
        '${m['user_id']}' == c.buyerId);
    if (bcCancel.rpcOk && announced) {
      c.hold(
        id: 'BH1-11',
        lens: 'BH1',
        severity: 'P2',
        title: 'purchase_broadcast com order cancelada + PI residual',
        actor: 'seller JWT',
        pre: 'order cancelado com stripe_payment_intent_id',
        repro: 'rpc batata_live_purchase_broadcast',
        expected: 'false',
        obtained: {'rpc': bcCancel.brief, 'order': oid},
      );
    } else {
      c.block('BH1-11', 'BH1', 'broadcast cancelada+PI', bcCancel);
    }

    // Order de OUTRO live_item
    if (itemOnly != null) {
      final bcWrongItem = await c.purchaseBc(
        liveId: liveA,
        buyer: c.buyerId!,
        itemId: itemOnly,
      );
      await c.expectDenied(
        id: 'BH1-12',
        lens: 'BH5',
        title: 'purchase_broadcast item A com PI noutro item',
        hit: bcWrongItem,
        actor: 'seller JWT',
        pre: 'PI/order no item marketplace, broadcast no live_only',
        repro: 'rpc batata_live_purchase_broadcast p_live_item_id live_only',
        severityIfOpen: 'P2',
        openIf: (h) => h.rpcOk || h.json == true,
      );
    }
  }
}

Future<void> _bh2StaffFomo(
  Rtbh c,
  String liveA,
  String? liveB,
  String? itemOnly,
) async {
  if (c.helperChatJwt == null) {
    c.skip('BH2-00', 'BH2', 'helper chat-only não criado', 'adminUser fail');
    return;
  }

  final chatMsg = await c.sysMsg(liveA, 'Staff: artigo a caminho', jwt: c.helperChatJwt);
  if (chatMsg.rpcOk) {
    c.note('BH2-01', 'helper can_manage_chat envia system_message não-FOMO', chatMsg,
        lens: 'BH2');
  } else {
    c.note('BH2-01', 'helper chat system_message denied', chatMsg, lens: 'BH2');
  }

  final chatFomo = await c.sysMsg(liveA, '🛒 o João levou este', jwt: c.helperChatJwt);
  if (chatFomo.rpcOk) {
    c.hold(
      id: 'BH2-02',
      lens: 'BH2',
      severity: 'P2',
      title: 'Helper chat-only anuncia FOMO «levou» via system_message',
      actor: 'helper can_manage_chat',
      pre: 'perms só chat',
      repro: 'rpc batata_live_system_message levou',
      expected: 'purchase_announce_via_broadcast_only',
      obtained: chatFomo.brief,
    );
  } else {
    c.block('BH2-02', 'BH2', 'helper FOMO levou', chatFomo);
  }

  if (itemOnly != null) {
    final chatMark = await c.markSold(itemOnly, jwt: c.helperChatJwt);
    await c.expectDenied(
      id: 'BH2-03',
      lens: 'BH2',
      title: 'Helper can_manage_chat only executa mark_sold',
      hit: chatMark,
      actor: 'helper chat-only',
      pre: 'sem can_mark_items_sold',
      repro: 'rpc batata_mark_live_item_sold',
      severityIfOpen: 'P1',
      openIf: (h) => h.rpcOk,
    );

    final resH = await c.buyerReserve(itemOnly, jwt: c.buyer2Jwt);
    c.trackRes(resH);
    final rid = resH.firstId;
    if (rid != null) {
      final chatAcc = await c.patchRes(rid, {'status': 'accepted'}, jwt: c.helperChatJwt);
      await c.expectDenied(
        id: 'BH2-04',
        lens: 'BH2',
        title: 'Helper chat-only accept reserva',
        hit: chatAcc,
        actor: 'helper chat-only',
        pre: 'sem can_manage_reservations',
        repro: 'PATCH reservation accepted',
        severityIfOpen: 'P1',
      );
    }

    final qty = await c.rest(
      'PATCH',
      'live_items?id=eq.$itemOnly',
      jwt: c.helperChatJwt,
      body: {'quantity': 40},
    );
    await c.expectDenied(
      id: 'BH2-05',
      lens: 'BH5',
      title: 'Helper chat-only infla qty 2→40',
      hit: qty,
      actor: 'helper chat-only',
      pre: 'qty=2',
      repro: 'PATCH live_items quantity=40',
      severityIfOpen: 'P1',
    );
  }

  if (c.helperViewJwt != null && itemOnly != null) {
    final viewMark = await c.markSold(itemOnly, jwt: c.helperViewJwt);
    await c.expectDenied(
      id: 'BH2-06',
      lens: 'BH2',
      title: 'Helper view/change_item mark_sold',
      hit: viewMark,
      actor: 'helper can_change_current_item',
      pre: 'sem can_mark',
      repro: 'rpc mark_sold',
      severityIfOpen: 'P1',
      openIf: (h) => h.rpcOk,
    );
    final viewMsg = await c.sysMsg(liveA, 'dashboard ping', jwt: c.helperViewJwt);
    await c.expectDenied(
      id: 'BH2-07',
      lens: 'BH2',
      title: 'Helper view-only system_message',
      hit: viewMsg,
      actor: 'helper view',
      pre: 'sem can_manage_chat',
      repro: 'rpc system_message',
      severityIfOpen: 'P2',
      openIf: (h) => h.rpcOk,
    );
  }

  if (c.helperMarkJwt != null && itemOnly != null) {
    final markMsg = await c.sysMsg(liveA, 'mark helper chat', jwt: c.helperMarkJwt);
    await c.expectDenied(
      id: 'BH2-08',
      lens: 'BH2',
      title: 'Helper mark_sold-only envia system_message',
      hit: markMsg,
      actor: 'helper can_mark_items_sold',
      pre: 'sem can_manage_chat',
      repro: 'rpc system_message',
      severityIfOpen: 'P2',
      openIf: (h) => h.rpcOk,
    );
  }

  if (c.helperResJwt != null && itemOnly != null) {
    final resMark = await c.markSold(itemOnly, jwt: c.helperResJwt);
    await c.expectDenied(
      id: 'BH2-09',
      lens: 'BH2',
      title: 'Helper reservations-only mark_sold',
      hit: resMark,
      actor: 'helper can_manage_reservations',
      pre: 'sem can_mark_items_sold',
      repro: 'rpc mark_sold',
      severityIfOpen: 'P1',
      openIf: (h) => h.rpcOk,
    );
  }

  // Helper noutro seller
  if (liveB != null && c.helperChatJwt != null) {
    final alien = await c.sysMsg(liveB, 'staff loja alheia', jwt: c.helperChatJwt);
    await c.expectDenied(
      id: 'BH2-10',
      lens: 'BH7',
      title: 'Helper seller1 system_message na live seller2',
      hit: alien,
      actor: 'helper chat seller1',
      pre: 'live B do seller2',
      repro: 'rpc system_message liveB',
      severityIfOpen: 'P2',
      openIf: (h) => h.rpcOk,
    );
  }
}

Future<void> _bh3StockHub(
  Rtbh c,
  String liveA,
  String? itemOnly,
  String? itemMkt,
) async {
  if (itemOnly == null) return;

  final stockAnonLive = await c.rpc('batata_live_item_stock', {
    'p_live_item_id': itemOnly,
  });
  c.note('BH3-01', 'stock anon enquanto broadcasting', stockAnonLive, lens: 'BH3');

  final endHit = await c.endLive(liveA, service: true);
  final liveAfterEnd = await c.liveRow(liveA);
  c.note('BH3-end', 'endLive service', {
    'patch': endHit.brief,
    'row': {
      'status': liveAfterEnd?['status'],
      'active': liveAfterEnd?['is_active'],
    },
  }, lens: 'BH3');
  final stockAnonEnded = await c.rpc('batata_live_item_stock', {
    'p_live_item_id': itemOnly,
  });
  final stockBuyerEnded = await c.rpc('batata_live_item_stock', {
    'p_live_item_id': itemOnly,
  }, jwt: c.buyerJwt);
  final stockSellerEnded = await c.rpc('batata_live_item_stock', {
    'p_live_item_id': itemOnly,
  }, jwt: c.sellerJwt);

  bool oracle(HttpHit h) {
    final m = h.map;
    if (m == null) return false;
    if (m['ok'] == false) return false;
    final avail = numOf(m['available_qty'] ?? m['available']);
    return avail != null;
  }

  final reallyEnded = liveAfterEnd?['status'] == 'ended' &&
      liveAfterEnd?['is_active'] == false;
  if (!reallyEnded) {
    c.skip('BH3-02', 'BH3', 'endLive não persistiu ended — stock gate não auditável',
        liveAfterEnd);
  } else if (oracle(stockAnonEnded)) {
    c.hold(
      id: 'BH3-02',
      lens: 'BH3',
      severity: 'P3',
      title: 'anon lê stock de item após live ended',
      actor: 'anon',
      pre: 'live ended',
      repro: 'rpc batata_live_item_stock',
      expected: 'live_item_not_found',
      obtained: stockAnonEnded.brief,
    );
  } else {
    c.block('BH3-02', 'BH3', 'anon stock ended gated', stockAnonEnded);
  }

  if (!reallyEnded) {
    c.skip('BH3-03', 'BH3', 'endLive não persistiu — skip buyer stock ended',
        liveAfterEnd);
  } else if (oracle(stockBuyerEnded)) {
    c.hold(
      id: 'BH3-03',
      lens: 'BH3',
      severity: 'P3',
      title: 'buyer JWT lê stock após live ended (oráculo vitrine)',
      actor: 'buyer JWT',
      pre: 'live ended, buyer não é staff',
      repro: 'rpc batata_live_item_stock JWT buyer',
      expected: 'live_item_not_found',
      obtained: stockBuyerEnded.brief,
    );
  } else {
    c.block('BH3-03', 'BH3', 'buyer stock ended gated', stockBuyerEnded);
  }
  c.note('BH3-04', 'seller stock ended (gestão)', stockSellerEnded, lens: 'BH3');

  final hub = await c.rest(
    'GET',
    'hub_live_items_discovery_public?id=eq.$itemOnly&select=id,status,title',
  );
  if (!reallyEnded) {
    c.skip('BH3-05', 'BH3', 'endLive não persistiu — skip Hub ended', liveAfterEnd);
  } else if (hub.list.isNotEmpty) {
    c.hold(
      id: 'BH3-05',
      lens: 'BH3',
      severity: 'P2',
      title: 'Hub discovery ainda mostra item de live ended',
      actor: 'anon',
      pre: 'live ended',
      repro: 'GET hub_live_items_discovery_public',
      expected: '[]',
      obtained: hub.brief,
    );
  } else {
    c.block('BH3-05', 'BH3', 'Hub discovery ended vazio', hub);
  }

  // qty RPC anon vs jwt
  final qtyAnon = await c.rpc('batata_live_item_total_qty', {
    'p_live_item_id': itemOnly,
  });
  final qtyBuyer = await c.rpc('batata_live_item_total_qty', {
    'p_live_item_id': itemOnly,
  }, jwt: c.buyerJwt);
  c.note('BH3-06', 'total_qty anon/buyer ended', {
    'anon': qtyAnon.brief,
    'buyer': qtyBuyer.brief,
  }, lens: 'BH3');
  if (qtyAnon.ok && numOf(qtyAnon.json) != null && numOf(qtyAnon.json)! > 0) {
    c.hold(
      id: 'BH3-06',
      lens: 'BH3',
      severity: 'P3',
      title: 'anon batata_live_item_total_qty devolve qty em live ended',
      actor: 'anon',
      pre: 'GRANT anon revogado ATBE — confirmar',
      repro: 'rpc batata_live_item_total_qty',
      expected: '401/403 ou 0',
      obtained: qtyAnon.brief,
    );
  } else {
    c.block('BH3-06', 'BH3', 'anon total_qty ended', qtyAnon);
  }
  if (reallyEnded && qtyBuyer.ok && numOf(qtyBuyer.json) != null && numOf(qtyBuyer.json)! > 0) {
    c.hold(
      id: 'BH3-07',
      lens: 'BH3',
      severity: 'P3',
      title: 'buyer JWT batata_live_item_total_qty devolve qty em live ended',
      actor: 'buyer JWT',
      pre: 'stock gated; total_qty ainda GRANT authenticated sem gate broadcasting',
      repro: 'rpc batata_live_item_total_qty JWT buyer após ended',
      expected: '0 / not_found / 403',
      obtained: qtyBuyer.brief,
    );
  } else {
    c.block('BH3-07', 'BH3', 'buyer total_qty ended', qtyBuyer);
  }

  await c.reopenLive(liveA);
}
