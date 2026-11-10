/// RED TEAM CEGO BB — pass 1. Staging only. Não corrige.
/// Variantes ≠ AP/AV/AJ exactos: system_message, reconcile aguarda,
/// UPDATE pending pós-ended, premio_rifa, Mux/OCR, paused/draft, hitch cruzado.
import 'dart:io';
import '_rtbb.dart';

Future<void> main() async {
  final rt = Rtbb.fromEnv(loadEnv());
  await rt.loginActors();
  await rt.ensureBuyer2();
  await rt.ensureSeller2();
  await rt.ensureHelper();
  rt.note('actors', 'JWT B1/S1/B2/S2/H', {
    'b1': rt.buyerId,
    's1': rt.sellerId,
    'b2': rt.buyer2Id,
    's2': rt.seller2Id,
    'h': rt.helperId,
  });

  final wallets0 = await rt.wallets();
  rt.note('wallets.t0', 'saldos iniciais', wallets0, lens: 'BB8');

  final leftover = await rt.rest(
    'GET',
    'lives?title=like.*$prefix*&select=id,status,is_active',
    service: true,
  );
  for (final row in leftover.list) {
    if (row is Map && row['id'] != null) {
      await rt.rest(
        'PATCH',
        'lives?id=eq.${row['id']}',
        service: true,
        body: {'status': 'ended', 'is_active': false},
        prefer: 'return=minimal',
      );
    }
  }

  final liveA = await rt.insertLive(title: '$prefix A live');
  final liveScheduled = await rt.insertLive(
    title: '$prefix A scheduled',
    status: 'scheduled',
    active: true,
  );
  final liveDraft = await rt.insertLive(
    title: '$prefix A draft',
    status: 'draft',
    active: false,
  );
  final liveIdle = await rt.insertLive(
    title: '$prefix A idle',
    status: 'live',
    active: false,
  );
  final liveEnded = await rt.insertLive(
    title: '$prefix A ended',
    status: 'ended',
    active: false,
  );
  final liveB = await rt.insertLive(
    seller: rt.seller2Id,
    title: '$prefix B s2',
  );
  if (liveA == null || liveB == null) {
    rt.skip('BB.fixture', 'BB1', 'insertLive falhou', {'a': liveA, 'b': liveB});
    await rt.cleanupSoft();
    await rt.dumpAll('pass1.json');
    exit(4);
  }

  final skuA = await rt.createProduct(title: '$prefix skuA', qty: 2, price: 11);
  final skuExtra = await rt.createProduct(
    title: '$prefix skuExtra',
    qty: 1,
    price: 8,
  );
  final skuS2 = await rt.createProduct(
    seller: rt.seller2Id,
    title: '$prefix skuS2',
    qty: 1,
    price: 7,
  );

  final itemA = await rt.insertItem(
    liveId: liveA,
    service: true,
    title: '$prefix itemA',
    qty: 1,
    price: 9,
  );
  final itemA2 = await rt.insertItem(
    liveId: liveA,
    service: true,
    title: '$prefix itemA2',
    qty: 1,
    price: 10,
    productId: skuA,
    kind: 'marketplace_product',
  );
  final itemScheduled = liveScheduled == null
      ? null
      : await rt.insertItem(
          liveId: liveScheduled,
          service: true,
          title: '$prefix itemScheduled',
        );
  final itemDraft = liveDraft == null
      ? null
      : await rt.insertItem(
          liveId: liveDraft,
          service: true,
          title: '$prefix itemDraft',
        );
  final itemIdle = liveIdle == null
      ? null
      : await rt.insertItem(
          liveId: liveIdle,
          service: true,
          title: '$prefix itemIdle',
        );
  final itemEnded = liveEnded == null
      ? null
      : await rt.insertItem(
          liveId: liveEnded,
          service: true,
          title: '$prefix itemEnded',
        );
  final itemB = await rt.insertItem(
    liveId: liveB,
    service: true,
    title: '$prefix itemB s2',
  );
  final idA = itemA.firstId;
  final idA2 = itemA2.firstId;
  final idScheduled = itemScheduled?.firstId;
  final idDraft = itemDraft?.firstId;
  final idIdle = itemIdle?.firstId;
  final idEnded = itemEnded?.firstId;
  final idB = itemB.firstId;
  rt.note('fixture.items', 'ids', {
    'A': idA,
    'A2': idA2,
    'scheduled': idScheduled,
    'draft': idDraft,
    'idle': idIdle,
    'ended': idEnded,
    'B': idB,
    'hits': {
      'A': itemA.brief,
      'B': itemB.brief,
    },
  });
  if (idA == null || idB == null) {
    rt.skip('BB.fixture.items', 'BB1', 'live_items falhou', itemA.brief);
    await rt.cleanupSoft();
    await rt.dumpAll('pass1.json');
    exit(4);
  }

  // Staff: chat-only vs mark_sold-only (service fixture accepted+active)
  final hidChat = await rt.inviteHelper(
    helperUserId: rt.helperId!,
    status: 'accepted',
    active: true,
    perms: const {
      'can_manage_chat': true,
      'can_mark_items_sold': false,
      'can_manage_reservations': false,
      'can_change_current_item': false,
    },
  );

  // ---------------------------------------------------------------------------
  // BB1 — convert / anúncio «comprou» sem PI (caminhos ≠ purchase_broadcast exact)
  // ---------------------------------------------------------------------------
  final bcUnpaid = await rt.rpc('batata_live_purchase_broadcast', {
    'p_live_id': liveA,
    'p_buyer_id': rt.buyerId,
    'p_live_item_id': idA,
  }, jwt: rt.buyerJwt);
  final msgsAfterUnpaid = await rt.liveMsgs(liveA, service: true);
  final unpaidInjected = msgsAfterUnpaid.any(
    (m) =>
        m is Map &&
        '${m['kind']}' == 'system' &&
        '${m['body']}'.toLowerCase().contains('comprou'),
  );
  rt.judge(
    id: 'BB1-01',
    lens: 'BB1',
    title: 'purchase_broadcast sem order paga (regressão ANAS)',
    hit: bcUnpaid,
    cracked: unpaidInjected || (bcUnpaid.ok && bcUnpaid.body.contains('true')),
    actor: 'buyer JWT',
    pre: 'sem order',
    repro: 'rpc batata_live_purchase_broadcast',
    severity: 'P2',
    expected: 'false / sem system comprou',
  );

  final sysBuyer = await rt.rpc('batata_live_system_message', {
    'p_live_id': liveA,
    'p_body': '✅ Maestro Buyer comprou $prefix itemA',
    'p_sender_label': 'Sistema',
  }, jwt: rt.buyerJwt);
  rt.judge(
    id: 'BB1-02',
    lens: 'BB1',
    title: 'Buyer RPC system_message finge compra',
    hit: sysBuyer,
    cracked: sysBuyer.ok &&
        (sysBuyer.body.contains('"ok":true') ||
            sysBuyer.body.contains('"ok": true')),
    actor: 'buyer JWT',
    pre: 'ANAS fechou purchase_broadcast; outro RPC',
    repro: 'rpc batata_live_system_message',
    severity: 'P2',
  );

  final sysSeller = await rt.rpc('batata_live_system_message', {
    'p_live_id': liveA,
    'p_body': '✅ Comprador fantasma comprou $prefix itemA',
    'p_sender_label': 'Sistema',
  }, jwt: rt.sellerJwt);
  final msgsSellerSys = await rt.liveMsgs(liveA, jwt: rt.buyer2Jwt);
  final sellerLieVisible = msgsSellerSys.any(
    (m) =>
        m is Map &&
        '${m['kind']}' == 'system' &&
        '${m['body']}'.contains('Comprador fantasma'),
  );
  if (sysSeller.ok && sellerLieVisible) {
    rt.hold(
      id: 'BB1-03',
      lens: 'BB1',
      severity: 'P3',
      title: 'Seller system_message texto livre tipo «comprou» sem PI',
      actor: 'seller JWT; leitura buyer2',
      pre: 'purchase_broadcast exige pago; system_message é texto livre',
      repro: 'rpc batata_live_system_message body ✅ comprou',
      expected: 'anúncio de compra só via purchase_broadcast com PI',
      obtained: {
        'hit': sysSeller.brief,
        'visible_b2': sellerLieVisible,
      },
    );
  } else {
    rt.block('BB1-03', 'BB1', 'seller system_message fake compra', {
      'hit': sysSeller.brief,
      'visible': sellerLieVisible,
    });
  }

  final sysHelper = await rt.rpc('batata_live_system_message', {
    'p_live_id': liveA,
    'p_body': '✅ Staff mentiu: comprou $prefix',
    'p_sender_label': 'Sistema',
  }, jwt: rt.helperJwt);
  rt.judge(
    id: 'BB1-04',
    lens: 'BB2',
    title: 'Helper can_manage_chat only injeta system «comprou»',
    hit: sysHelper,
    cracked: sysHelper.ok &&
        (sysHelper.body.contains('"ok":true') ||
            sysHelper.body.contains('"ok": true')),
    actor: 'helper JWT chat-only',
    pre: 'perms só can_manage_chat',
    repro: 'rpc batata_live_system_message',
    severity: 'P2',
  );

  final sysAlien = await rt.rpc('batata_live_system_message', {
    'p_live_id': liveB,
    'p_body': '✅ sabotagem comprou item alheio',
    'p_sender_label': 'Sistema',
  }, jwt: rt.sellerJwt);
  rt.judge(
    id: 'BB1-05',
    lens: 'BB7',
    title: 'Seller1 system_message na live do seller2',
    hit: sysAlien,
    cracked: sysAlien.ok &&
        (sysAlien.body.contains('"ok":true') ||
            sysAlien.body.contains('"ok": true')),
    actor: 'seller JWT',
    pre: 'live B de seller2',
    repro: 'rpc batata_live_system_message liveB',
    severity: 'P2',
  );

  final insSys = await rt.rest('POST', 'live_messages', jwt: rt.buyerJwt, body: {
    'live_id': liveA,
    'user_id': rt.buyerId,
    'kind': 'system',
    'body': '✅ INSERT REST comprou $prefix',
    'sender_label': 'Sistema',
  });
  rt.judge(
    id: 'BB1-06',
    lens: 'BB1',
    title: 'Buyer INSERT live_messages kind=system',
    hit: insSys,
    cracked: insSys.ok,
    actor: 'buyer JWT',
    pre: 'policy insert_chat exige kind=chat',
    repro: 'POST live_messages kind=system',
    severity: 'P2',
  );

  final insChatFake = await rt.rest(
    'POST',
    'live_messages',
    jwt: rt.buyerJwt,
    body: {
      'live_id': liveA,
      'user_id': rt.buyerId,
      'kind': 'chat',
      'body': '✅ Maestro Buyer comprou $prefix itemA',
    },
  );
  rt.note('BB1-07', 'chat livre com texto comprou (não system)', insChatFake,
      lens: 'BB1');

  String? chatId = insChatFake.firstId;
  if (chatId == null && insChatFake.ok) {
    final recent = await rt.liveMsgs(liveA, jwt: rt.buyerJwt);
    for (final m in recent) {
      if (m is Map && '${m['kind']}' == 'chat' && '${m['user_id']}' == rt.buyerId) {
        chatId = '${m['id']}';
        break;
      }
    }
  }
  if (chatId != null) {
    final upKind = await rt.rest(
      'PATCH',
      'live_messages?id=eq.$chatId',
      jwt: rt.buyerJwt,
      body: {'kind': 'system'},
    );
    final afterKind = await rt.rest(
      'GET',
      'live_messages?id=eq.$chatId&select=id,kind,body',
      service: true,
    );
    final becameSys = '${afterKind.map?['kind']}' == 'system';
    rt.judge(
      id: 'BB1-08',
      lens: 'BB1',
      title: 'Buyer PATCH kind chat→system',
      hit: upKind,
      cracked: becameSys,
      actor: 'buyer JWT',
      pre: 'mensagem chat própria',
      repro: 'PATCH live_messages kind=system',
      severity: 'P2',
      evidence: {'row': afterKind.map},
    );
  } else {
    rt.skip('BB1-08', 'BB1', 'sem chat id para PATCH kind', insChatFake.brief);
  }

  // premio_rifa fixture (service) + JWT broadcast — se passar, exploit só se JWT criar status
  if (skuA != null) {
    final rifaOrder = await rt.rest('POST', 'orders', service: true, body: {
      'buyer_id': rt.buyerId,
      'seller_id': rt.sellerId,
      'product_id': skuA,
      'price_total': 0,
      'quantity': 1,
      'status': 'premio_rifa',
      'payment_method': 'rifa',
      'shipping_method': 'entrega em mão',
      'amount_paid_cents': 0,
      'live_item_id': idA,
      'live_id': liveA,
    });
    if (rifaOrder.firstId != null) rt.createdOrderIds.add(rifaOrder.firstId!);
    final bcRifa = await rt.rpc('batata_live_purchase_broadcast', {
      'p_live_id': liveA,
      'p_buyer_id': rt.buyerId,
      'p_live_item_id': idA,
    }, jwt: rt.buyerJwt);
    final jwtRifa = await rt.rest('POST', 'orders', jwt: rt.buyerJwt, body: {
      'buyer_id': rt.buyerId,
      'seller_id': rt.sellerId,
      'product_id': skuA,
      'price_total': 0,
      'quantity': 1,
      'status': 'premio_rifa',
      'payment_method': 'rifa',
      'shipping_method': 'entrega em mão',
      'live_item_id': idA2,
      'live_id': liveA,
    });
    if (jwtRifa.firstId != null) rt.createdOrderIds.add(jwtRifa.firstId!);
    final bcRifaJwt = jwtRifa.ok
        ? await rt.rpc('batata_live_purchase_broadcast', {
            'p_live_id': liveA,
            'p_buyer_id': rt.buyerId,
            'p_live_item_id': idA2,
          }, jwt: rt.buyerJwt)
        : jwtRifa;
    final rifaJwtWorked = jwtRifa.ok &&
        bcRifaJwt.ok &&
        (bcRifaJwt.body.contains('true') || '${bcRifaJwt.json}' == 'true');
    if (rifaJwtWorked) {
      rt.hold(
        id: 'BB1-09',
        lens: 'BB1',
        severity: 'P2',
        title: 'Buyer cria order premio_rifa e anuncia compra sem PI',
        actor: 'buyer JWT',
        pre: 'broadcast aceita status premio_rifa',
        repro: 'POST orders status=premio_rifa + purchase_broadcast',
        expected: 'INSERT pago/rifa bloqueado; broadcast false',
        obtained: {'ins': jwtRifa.brief, 'bc': bcRifaJwt.brief},
      );
    } else {
      rt.block('BB1-09', 'BB1', 'premio_rifa JWT + broadcast', {
        'svc_ins': rifaOrder.brief,
        'svc_bc': bcRifa.brief,
        'jwt_ins': jwtRifa.brief,
        'jwt_bc': bcRifaJwt.brief,
      });
    }
  }

  // Order cancelada com PI vivo (fixture pago → PATCH cancelado)
  if (skuA != null) {
    final paidThenCancel = await rt.insertPaidOrder(
      productId: skuA,
      liveItemId: idA2,
      liveId: liveA,
      price: 11,
    );
    if (paidThenCancel != null) {
      await rt.rest(
        'PATCH',
        'orders?id=eq.$paidThenCancel',
        service: true,
        body: {'status': 'cancelado'},
        prefer: 'return=minimal',
      );
      final row = await rt.orderRow(paidThenCancel);
      final bcCancel = await rt.rpc('batata_live_purchase_broadcast', {
        'p_live_id': liveA,
        'p_buyer_id': rt.buyerId,
        'p_live_item_id': idA2,
      }, jwt: rt.sellerJwt);
      final stillAnnounced = bcCancel.ok &&
          (bcCancel.body.contains('true') || '${bcCancel.json}' == 'true');
      rt.judge(
        id: 'BB1-10',
        lens: 'BB1',
        title: 'Broadcast com order cancelada mas PI ainda no row',
        hit: bcCancel,
        cracked: stillAnnounced,
        actor: 'seller JWT',
        pre: 'order foi pago depois status=cancelado; PI permanece',
        repro: 'rpc purchase_broadcast',
        severity: 'P2',
        evidence: {'order': row},
      );
    }
  }

  // Convert sem PI — fleaber_live / facebook_manual / helper_manual
  final resA = await rt.insertRes(
    liveId: liveA,
    itemId: idA,
    jwt: rt.buyerJwt,
    source: 'fleaber_live',
  );
  if (resA.firstId != null) {
    final acc = await rt.processRes(resA.firstId!, 'accept');
    final conv = await rt.processRes(resA.firstId!, 'convert');
    rt.judge(
      id: 'BB1-11',
      lens: 'BB1',
      title: 'process convert fleaber_live sem PI',
      hit: conv,
      cracked: conv.ok &&
          !conv.body.contains('convert_requires_paid_order') &&
          !conv.body.contains('not_allowed'),
      actor: 'seller JWT',
      pre: 'accepted sem order',
      repro: 'batata_process_live_reservation_request convert',
      expected: 'convert_requires_paid_order',
    );
    rt.note('BB1-11.accept', 'accept sem PI', acc, lens: 'BB1');
  }

  final resFb = await rt.insertRes(
    liveId: liveA,
    itemId: idA,
    jwt: rt.buyer2Jwt,
    buyer: rt.buyer2Id,
    source: 'facebook_manual',
  );
  if (resFb.firstId != null) {
    await rt.processRes(resFb.firstId!, 'accept');
    final convFb = await rt.processRes(resFb.firstId!, 'convert');
    rt.judge(
      id: 'BB1-12',
      lens: 'BB1',
      title: 'convert facebook_manual sem PI',
      hit: convFb,
      cracked: convFb.ok && !convFb.body.contains('convert_requires_paid_order'),
      actor: 'seller JWT',
      pre: 'source facebook_manual',
      repro: 'process convert',
      expected: 'convert_requires_paid_order (VWX todos os sources)',
    );
  }

  if (resA.firstId != null) {
    final patchConv = await rt.rest(
      'PATCH',
      'live_reservation_requests?id=eq.${resA.firstId}',
      jwt: rt.sellerJwt,
      body: {'status': 'converted'},
    );
    final row = await rt.resRow(resA.firstId!);
    rt.judge(
      id: 'BB1-13',
      lens: 'BB1',
      title: 'Seller PATCH reservation → converted',
      hit: patchConv,
      cracked: '${row?['status']}' == 'converted',
      actor: 'seller JWT',
      pre: 'fila sem PI',
      repro: 'PATCH live_reservation_requests status',
      severity: 'P1',
      evidence: {'row': row},
    );
  }

  // Reconcile com aguarda_confirmacao (não capturado)
  if (skuA != null) {
    final holdOrder = await rt.insertOpenOrder(
      productId: skuA,
      jwt: rt.buyerJwt,
      liveItemId: idA,
      liveId: liveA,
      status: 'aguarda_confirmacao',
      price: 9,
    );
    if (holdOrder != null) {
      final rec = await rt.rpc('batata_live_reconcile_stripe_order', {
        'p_order_id': holdOrder,
      }, jwt: rt.buyerJwt);
      final recSeller = await rt.rpc('batata_live_reconcile_stripe_order', {
        'p_order_id': holdOrder,
      }, jwt: rt.sellerJwt);
      final convertedAfter = await rt.rest(
        'GET',
        'live_reservation_requests?live_item_id=eq.$idA&buyer_id=eq.${rt.buyerId}&status=eq.converted&select=id,status,notes,source',
        service: true,
      );
      final crackedRec = rec.ok &&
              (rec.body.contains('"ok":true') || rec.body.contains('direct_insert')) ||
          (recSeller.ok && recSeller.body.contains('"ok":true')) ||
          convertedAfter.list.isNotEmpty;
      rt.judge(
        id: 'BB1-14',
        lens: 'BB1',
        title: 'reconcile_stripe_order com status aguarda_confirmacao (sem captura)',
        hit: recSeller.ok ? recSeller : rec,
        cracked: crackedRec,
        actor: 'buyer+seller JWT',
        pre: 'order JWT aguarda_confirmacao; função trata como paga',
        repro: 'rpc batata_live_reconcile_stripe_order',
        severity: 'P1',
        evidence: {
          'buyer': rec.brief,
          'seller': recSeller.brief,
          'converted_rows': convertedAfter.list,
        },
      );
    } else {
      rt.note('BB1-14.skip', 'INSERT aguarda_confirmacao JWT falhou', 'no id',
          lens: 'BB1');
    }

    final sync = await rt.rpc('batata_sync_live_item_for_order', {
      'p_order_id': holdOrder ?? '00000000-0000-0000-0000-000000000001',
    }, jwt: rt.buyerJwt);
    rt.note('BB1-15', 'sync_live_item_for_order', sync, lens: 'BB1');
  }

  final insConv = await rt.insertRes(
    liveId: liveA,
    itemId: idA,
    jwt: rt.buyerJwt,
    status: 'converted',
    source: 'fleaber_live',
  );
  final insConvRow =
      insConv.firstId != null ? await rt.resRow(insConv.firstId!) : null;
  rt.judge(
    id: 'BB1-16',
    lens: 'BB1',
    title: 'Buyer INSERT reservation já converted',
    hit: insConv,
    cracked: insConv.ok && '${insConvRow?['status']}' == 'converted',
    actor: 'buyer JWT',
    pre: 'force_pending_manual deve forçar pending',
    repro: 'POST live_reservation_requests status=converted',
    severity: 'P1',
    evidence: {'row': insConvRow},
  );

  // ---------------------------------------------------------------------------
  // BB2 — staff/helper
  // ---------------------------------------------------------------------------
  final hMark = await rt.markSold(idA, jwt: rt.helperJwt);
  final itemAfterH = await rt.itemRow(idA);
  rt.judge(
    id: 'BB2-01',
    lens: 'BB2',
    title: 'Helper chat-only mark_sold',
    hit: hMark,
    cracked: hMark.ok &&
        !hMark.body.contains('not_allowed') &&
        '${itemAfterH?['status']}' == 'sold',
    actor: 'helper JWT',
    pre: 'só can_manage_chat',
    repro: 'rpc batata_mark_live_item_sold',
    severity: 'P1',
  );

  if (resA.firstId != null) {
    final hAcc = await rt.processRes(resA.firstId!, 'accept', jwt: rt.helperJwt);
    rt.judge(
      id: 'BB2-02',
      lens: 'BB2',
      title: 'Helper chat-only accept reserva',
      hit: hAcc,
      cracked: hAcc.ok && !hAcc.body.contains('not_allowed'),
      actor: 'helper JWT',
      pre: 'sem can_manage_reservations',
      repro: 'process accept',
      severity: 'P1',
    );
  }

  final esc = await rt.rest(
    'PATCH',
    'seller_helpers?id=eq.$hidChat',
    jwt: rt.helperJwt,
    body: {
      'permissions': {
        'can_mark_items_sold': true,
        'can_manage_reservations': true,
      },
    },
  );
  final hrow = hidChat != null ? await rt.helperRow(hidChat) : null;
  final perms = hrow?['permissions'];
  final escalated = perms is Map &&
      (perms['can_mark_items_sold'] == true ||
          perms['can_manage_reservations'] == true);
  rt.judge(
    id: 'BB2-03',
    lens: 'BB2',
    title: 'Helper PATCH self-escalate permissions',
    hit: esc,
    cracked: escalated,
    actor: 'helper JWT',
    pre: 'aceitou chat-only',
    repro: 'PATCH seller_helpers permissions',
    severity: 'P1',
    evidence: {'row': hrow},
  );

  final hInviteS2 = await rt.rest('POST', 'seller_helpers', jwt: rt.helperJwt, body: {
    'seller_id': rt.seller2Id,
    'helper_user_id': rt.helperId,
    'display_name': 'pwn s2',
    'invited_by': rt.helperId,
    'invitation_status': 'accepted',
    'active': true,
    'permissions': {'can_mark_items_sold': true},
  });
  rt.judge(
    id: 'BB2-04',
    lens: 'BB2',
    title: 'Helper INSERT staff na loja do seller2',
    hit: hInviteS2,
    cracked: hInviteS2.ok,
    actor: 'helper JWT',
    pre: 'staff da loja A',
    repro: 'POST seller_helpers seller2',
    severity: 'P1',
  );
  if (hInviteS2.firstId != null) rt.createdHelperIds.add(hInviteS2.firstId!);

  // Seller promove helper a mark_sold e tenta mark_sold sem PI (próprio catálogo)
  if (hidChat != null) {
    await rt.rest(
      'PATCH',
      'seller_helpers?id=eq.$hidChat',
      service: true,
      body: {
        'permissions': {
          'can_manage_chat': true,
          'can_mark_items_sold': true,
        },
        'active': true,
        'invitation_status': 'accepted',
      },
      prefer: 'return=minimal',
    );
    final msStaff = await rt.markSold(idA2 ?? idA, jwt: rt.helperJwt);
    final skuAfter = skuA != null ? await rt.productRow(skuA) : null;
    final unlisted = skuAfter != null &&
        (skuAfter['is_sold'] == true || skuAfter['list_on_marketplace'] == false);
    if (msStaff.ok && unlisted) {
      rt.hold(
        id: 'BB2-05',
        lens: 'BB4',
        severity: 'P1',
        title: 'Helper can_mark_items_sold deslista SKU marketplace sem PI',
        actor: 'helper JWT',
        pre: 'item A2 marketplace_product; sem order paga neste item',
        repro: 'rpc mark_sold',
        expected: 'não deslista sem PI (AHAM)',
        obtained: {'hit': msStaff.brief, 'sku': skuAfter},
      );
    } else {
      rt.block('BB2-05', 'BB4', 'helper mark_sold sem PI não deslista SKU', {
        'hit': msStaff.brief,
        'sku': skuAfter,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // BB3 — stock / Hub / REST / estados live
  // ---------------------------------------------------------------------------
  if (liveScheduled != null && idScheduled != null) {
    final resScheduled = await rt.insertRes(
      liveId: liveScheduled,
      itemId: idScheduled,
      jwt: rt.buyerJwt,
    );
    rt.judge(
      id: 'BB3-01',
      lens: 'BB3',
      title: 'Reserva em live scheduled (is_active=true)',
      hit: resScheduled,
      cracked: resScheduled.ok,
      actor: 'buyer JWT',
      pre: 'ANAS usa is_broadcasting; scheduled ∉ live/ao_vivo/active',
      repro: 'POST live_reservation_requests',
      severity: 'P3',
    );
  } else {
    rt.skip('BB3-01', 'BB3', 'fixture scheduled em falta', liveScheduled);
  }

  if (liveDraft != null && idDraft != null) {
    final resDraft = await rt.insertRes(
      liveId: liveDraft,
      itemId: idDraft,
      jwt: rt.buyerJwt,
    );
    rt.judge(
      id: 'BB3-02',
      lens: 'BB3',
      title: 'Reserva em live draft',
      hit: resDraft,
      cracked: resDraft.ok,
      actor: 'buyer JWT',
      pre: 'draft is_active=false',
      repro: 'POST live_reservation_requests',
      severity: 'P3',
    );
  }

  if (liveIdle != null && idIdle != null) {
    final resIdle = await rt.insertRes(
      liveId: liveIdle,
      itemId: idIdle,
      jwt: rt.buyerJwt,
    );
    rt.judge(
      id: 'BB3-01b',
      lens: 'BB3',
      title: 'Reserva em status=live is_active=false',
      hit: resIdle,
      cracked: resIdle.ok,
      actor: 'buyer JWT',
      pre: 'is_broadcasting exige is_active',
      repro: 'POST live_reservation_requests',
      severity: 'P3',
    );
  }

  if (liveEnded != null && idEnded != null) {
    final resEnded = await rt.insertRes(
      liveId: liveEnded,
      itemId: idEnded,
      jwt: rt.buyerJwt,
    );
    rt.judge(
      id: 'BB3-03',
      lens: 'BB3',
      title: 'Reserva INSERT em live ended (regressão ANAS)',
      hit: resEnded,
      cracked: resEnded.ok,
      actor: 'buyer JWT',
      pre: 'ended is_active=false',
      repro: 'POST live_reservation_requests',
      severity: 'P3',
    );

    final restEnded = await rt.rest(
      'GET',
      'live_items?id=eq.$idEnded&select=id,status,quantity,title',
      jwt: rt.buyerJwt,
    );
    rt.note('BB3-04', 'REST buyer vê item de live ended', restEnded, lens: 'BB3');

    final hubEnded = await rt.rest(
      'GET',
      'hub_live_items_public?id=eq.$idEnded&select=id,status,title',
      jwt: rt.buyerJwt,
    );
    rt.note('BB3-05a', 'Hub item ended', hubEnded, lens: 'BB3');
  }

  final hubAnon = await rt.rest(
    'GET',
    'hub_live_items_public?id=eq.$idA&select=id,status,title',
  );
  rt.note('BB3-05', 'Hub anon live A', hubAnon, lens: 'BB3');

  final stockAnon = await rt.rpc('batata_live_item_stock', {
    'p_live_item_id': idA,
  });
  rt.note('BB3-06', 'stock RPC anon', stockAnon, lens: 'BB3');

  // ---------------------------------------------------------------------------
  // BB4 — mark_sold / hitch
  // ---------------------------------------------------------------------------
  if (skuS2 != null && skuExtra != null) {
    final hitchAlien = await rt.rest(
      'PATCH',
      'live_items?id=eq.$idA',
      jwt: rt.sellerJwt,
      body: {'checkout_product_id': skuS2},
    );
    final hitchRow = await rt.itemRow(idA);
    final msHitch = await rt.markSold(idA, jwt: rt.sellerJwt);
    final skuS2after = await rt.productRow(skuS2);
    final alienUnlisted = skuS2after != null &&
        (skuS2after['is_sold'] == true ||
            skuS2after['list_on_marketplace'] == false);
    rt.judge(
      id: 'BB4-01',
      lens: 'BB4',
      title: 'Hitch checkout_product do seller2 + mark_sold deslista alheio',
      hit: msHitch,
      cracked: alienUnlisted,
      actor: 'seller JWT',
      pre: 'SKU é do seller2',
      repro: 'PATCH checkout_product_id alheio + mark_sold',
      severity: 'P1',
      evidence: {
        'hitch': hitchAlien.brief,
        'item': hitchRow,
        'skuS2': skuS2after,
        'ms': msHitch.brief,
      },
    );

    final hitchOwn = await rt.rest(
      'PATCH',
      'live_items?id=eq.$idA',
      jwt: rt.sellerJwt,
      body: {'checkout_product_id': skuExtra},
    );
    final msOwn = await rt.markSold(idA, jwt: rt.sellerJwt);
    final extraAfter = await rt.productRow(skuExtra);
    final extraUnlisted = extraAfter != null &&
        (extraAfter['is_sold'] == true ||
            extraAfter['list_on_marketplace'] == false);
    rt.judge(
      id: 'BB4-02',
      lens: 'BB4',
      title: 'mark_sold live_only hitch SKU extra próprio sem PI',
      hit: msOwn,
      cracked: extraUnlisted,
      actor: 'seller JWT',
      pre: 'sem order paga do item A',
      repro: 'PATCH checkout_product_id próprio + mark_sold',
      severity: 'P2',
      evidence: {'hitch': hitchOwn.brief, 'sku': extraAfter},
    );
  }

  final patchSold = await rt.rest(
    'PATCH',
    'live_items?id=eq.$idB',
    jwt: rt.sellerJwt,
    body: {'status': 'sold'},
  );
  final itemBAfter = await rt.itemRow(idB);
  rt.judge(
    id: 'BB4-03',
    lens: 'BB7',
    title: 'Seller1 PATCH live_item do seller2 para sold',
    hit: patchSold,
    cracked: '${itemBAfter?['status']}' == 'sold',
    actor: 'seller JWT',
    pre: 'item B live seller2',
    repro: 'PATCH live_items status=sold',
    severity: 'P1',
    evidence: {'row': itemBAfter},
  );

  final insSold = await rt.insertItem(
    liveId: liveA,
    jwt: rt.sellerJwt,
    title: '$prefix sold insert',
    status: 'sold',
  );
  final insSoldRow =
      insSold.firstId != null ? await rt.itemRow(insSold.firstId!) : null;
  rt.judge(
    id: 'BB4-04',
    lens: 'BB4',
    title: 'INSERT live_item já sold',
    hit: insSold,
    cracked: insSold.ok && '${insSoldRow?['status']}' == 'sold',
    actor: 'seller JWT',
    pre: 'AHAM bloqueia INSERT sold',
    repro: 'POST live_items status=sold',
    severity: 'P3',
    evidence: {'row': insSoldRow},
  );

  final msBuyer = await rt.markSold(idA, jwt: rt.buyerJwt);
  rt.judge(
    id: 'BB4-05',
    lens: 'BB4',
    title: 'Buyer mark_sold item da live A',
    hit: msBuyer,
    cracked: msBuyer.ok && !msBuyer.body.contains('not_allowed'),
    actor: 'buyer JWT',
    pre: 'não é staff',
    repro: 'rpc mark_sold',
    severity: 'P1',
  );

  final msS2 = await rt.markSold(idA, jwt: rt.seller2Jwt);
  rt.judge(
    id: 'BB4-06',
    lens: 'BB7',
    title: 'Seller2 mark_sold no item da live A',
    hit: msS2,
    cracked: msS2.ok && !msS2.body.contains('not_allowed'),
    actor: 'seller2 JWT',
    pre: 'live alheia',
    repro: 'rpc mark_sold',
    severity: 'P1',
  );

  // ---------------------------------------------------------------------------
  // BB5 — live_id / qty / cross-seller
  // ---------------------------------------------------------------------------
  final moveItem = await rt.rest(
    'PATCH',
    'live_items?id=eq.$idA',
    jwt: rt.sellerJwt,
    body: {'live_id': liveB},
  );
  final moved = await rt.itemRow(idA);
  rt.judge(
    id: 'BB5-01',
    lens: 'BB5',
    title: 'Seller1 move live_item para live do seller2',
    hit: moveItem,
    cracked: '${moved?['live_id']}' == liveB,
    actor: 'seller JWT',
    pre: 'item A pertence a live A',
    repro: 'PATCH live_items live_id',
    severity: 'P1',
    evidence: {'row': moved},
  );

  final infl = await rt.rest(
    'PATCH',
    'live_items?id=eq.$idA',
    jwt: rt.sellerJwt,
    body: {'quantity': 99},
  );
  final inflRow = await rt.itemRow(idA);
  final qtyNow = inflRow?['quantity'];
  rt.judge(
    id: 'BB5-02',
    lens: 'BB5',
    title: 'Inflate quantity live_only mid-live',
    hit: infl,
    cracked: qtyNow is num && qtyNow >= 99,
    actor: 'seller JWT',
    pre: 'qty=1',
    repro: 'PATCH live_items quantity=99',
    severity: 'P2',
    evidence: {'row': inflRow},
  );

  final insOnB = await rt.insertItem(
    liveId: liveB,
    jwt: rt.sellerJwt,
    title: '$prefix planted on B',
  );
  rt.judge(
    id: 'BB5-03',
    lens: 'BB7',
    title: 'Seller1 INSERT live_item na live do seller2',
    hit: insOnB,
    cracked: insOnB.ok,
    actor: 'seller JWT',
    pre: 'live B alheia',
    repro: 'POST live_items live_id=B',
    severity: 'P1',
  );

  final crossRes = await rt.insertRes(
    liveId: liveA,
    itemId: idB,
    jwt: rt.buyerJwt,
    seller: rt.sellerId,
  );
  rt.judge(
    id: 'BB5-04',
    lens: 'BB5',
    title: 'Reserva item da live B com live_id da live A',
    hit: crossRes,
    cracked: crossRes.ok,
    actor: 'buyer JWT',
    pre: 'ANAS guarda broadcasting do live do ITEM (B está live)',
    repro: 'POST reservation live_id=A live_item=B',
    severity: 'P2',
  );

  final fatQty = await rt.insertRes(
    liveId: liveA,
    itemId: idA,
    jwt: rt.buyer2Jwt,
    buyer: rt.buyer2Id,
    qty: 50,
  );
  final fatRow =
      fatQty.firstId != null ? await rt.resRow(fatQty.firstId!) : null;
  rt.judge(
    id: 'BB5-05',
    lens: 'BB5',
    title: 'Pedido qty=50 em item qty=1',
    hit: fatQty,
    cracked: fatQty.ok && (fatRow?['requested_qty'] == 50),
    actor: 'buyer2 JWT',
    pre: 'item qty 1',
    repro: 'POST reservation requested_qty=50',
    severity: 'P2',
    evidence: {'row': fatRow},
  );

  // ---------------------------------------------------------------------------
  // BB6 — race / UPDATE pending após ended
  // ---------------------------------------------------------------------------
  // Reserva enquanto live A está no ar, depois ended, depois UPDATE
  final raceLive = await rt.insertLive(title: '$prefix race');
  final raceItem = raceLive == null
      ? null
      : await rt.insertItem(
          liveId: raceLive,
          service: true,
          title: '$prefix race item',
          qty: 1,
        );
  final raceItemId = raceItem?.firstId;
  HttpHit? pendingWhileLive;
  if (raceLive != null && raceItemId != null) {
    pendingWhileLive = await rt.insertRes(
      liveId: raceLive,
      itemId: raceItemId,
      jwt: rt.buyerJwt,
    );
    await rt.rest(
      'PATCH',
      'lives?id=eq.$raceLive',
      service: true,
      body: {'status': 'ended', 'is_active': false},
      prefer: 'return=minimal',
    );
    if (pendingWhileLive.firstId != null) {
      final upAfterEnd = await rt.rest(
        'PATCH',
        'live_reservation_requests?id=eq.${pendingWhileLive.firstId}',
        jwt: rt.buyerJwt,
        body: {'status': 'accepted', 'requested_qty': 2},
      );
      final rowAfter = await rt.resRow(pendingWhileLive.firstId!);
      final buyerForced = '${rowAfter?['status']}' == 'accepted';
      rt.judge(
        id: 'BB6-01',
        lens: 'BB6',
        title: 'Buyer UPDATE pending→accepted depois da live ended',
        hit: upAfterEnd,
        cracked: buyerForced,
        actor: 'buyer JWT',
        pre: 'ANAS só dispara no INSERT; UPDATE sem live_active',
        repro: 'PATCH reservation status=accepted com live ended',
        severity: 'P1',
        evidence: {'row': rowAfter},
      );

      final sellerAccEnded = await rt.processRes(
        pendingWhileLive.firstId!,
        'accept',
      );
      rt.judge(
        id: 'BB6-02',
        lens: 'BB6',
        title: 'Seller accept da pending após live ended',
        hit: sellerAccEnded,
        cracked: sellerAccEnded.ok &&
            !sellerAccEnded.body.contains('live_ended') &&
            !sellerAccEnded.body.contains('not_allowed'),
        actor: 'seller JWT',
        pre: 'live ended; pending criada enquanto broadcasting',
        repro: 'process accept',
        severity: 'P3',
      );
    }

    // micro-janela: reabrir + INSERT paralelo
    await rt.rest(
      'PATCH',
      'lives?id=eq.$raceLive',
      service: true,
      body: {'status': 'live', 'is_active': true},
      prefer: 'return=minimal',
    );
    final r1 = rt.insertRes(
      liveId: raceLive,
      itemId: raceItemId,
      jwt: rt.buyerJwt,
    );
    final r2 = rt.insertRes(
      liveId: raceLive,
      itemId: raceItemId,
      jwt: rt.buyer2Jwt,
      buyer: rt.buyer2Id,
    );
    final pair = await Future.wait([r1, r2]);
    String? id1 = pair[0].firstId;
    String? id2 = pair[1].firstId;
    if (id1 != null) {
      await rt.processRes(id1, 'accept');
    }
    if (id2 != null) {
      await rt.processRes(id2, 'accept');
    }
    final a1 = id1 != null ? await rt.resRow(id1) : null;
    final a2 = id2 != null ? await rt.resRow(id2) : null;
    final bothAcc = '${a1?['status']}' == 'accepted' &&
        '${a2?['status']}' == 'accepted';
    rt.judge(
      id: 'BB6-03',
      lens: 'BB6',
      title: 'Dois accepts simultâneos qty=1',
      hit: pair[1],
      cracked: bothAcc,
      actor: 'seller JWT após 2 pending',
      pre: 'item qty=1',
      repro: '2 INSERT + 2 accept',
      severity: 'P1',
      evidence: {'a1': a1, 'a2': a2, 'h1': pair[0].brief, 'h2': pair[1].brief},
    );
  }

  // ---------------------------------------------------------------------------
  // BB7 — sabotagem live alheia / Mux / OCR / raffle
  // ---------------------------------------------------------------------------
  final endAlien = await rt.rest(
    'PATCH',
    'lives?id=eq.$liveB',
    jwt: rt.sellerJwt,
    body: {'status': 'ended', 'is_active': false},
  );
  final liveBrow = await rt.rest(
    'GET',
    'lives?id=eq.$liveB&select=id,status,is_active,seller_id',
    service: true,
  );
  rt.judge(
    id: 'BB7-01',
    lens: 'BB7',
    title: 'Seller1 PATCH end na live do seller2',
    hit: endAlien,
    cracked: '${liveBrow.map?['status']}' == 'ended' ||
        liveBrow.map?['is_active'] == false && endAlien.ok,
    actor: 'seller JWT',
    pre: 'live B seller2',
    repro: 'PATCH lives status=ended',
    severity: 'P1',
    evidence: {'row': liveBrow.map},
  );

  final endBuyer = await rt.rest(
    'PATCH',
    'lives?id=eq.$liveA',
    jwt: rt.buyerJwt,
    body: {'status': 'ended', 'is_active': false},
  );
  rt.judge(
    id: 'BB7-02',
    lens: 'BB7',
    title: 'Buyer PATCH end na live A',
    hit: endBuyer,
    cracked: endBuyer.ok,
    actor: 'buyer JWT',
    pre: 'não é dono',
    repro: 'PATCH lives',
    severity: 'P1',
  );

  final muxComplete = await rt.edge('complete-mux-live', {
    'live_id': liveB,
  }, jwt: rt.sellerJwt);
  rt.judge(
    id: 'BB7-03',
    lens: 'BB7',
    title: 'complete-mux-live na live alheia',
    hit: muxComplete,
    cracked: muxComplete.ok,
    actor: 'seller JWT',
    pre: 'live B seller2',
    repro: 'POST functions/v1/complete-mux-live',
    severity: 'P1',
  );

  final muxPub = await rt.edge('livekit-mux-publish', {
    'live_id': liveB,
  }, jwt: rt.sellerJwt);
  rt.note('BB7-04', 'livekit-mux-publish live alheia', muxPub, lens: 'BB7');
  rt.judge(
    id: 'BB7-04',
    lens: 'BB7',
    title: 'livekit-mux-publish token na live alheia',
    hit: muxPub,
    cracked: muxPub.ok && muxPub.status != 403,
    actor: 'seller JWT',
    pre: 'live B',
    repro: 'POST livekit-mux-publish',
    severity: 'P1',
  );

  final createMux = await rt.edge('create-mux-live', {
    'live_id': liveB,
  }, jwt: rt.sellerJwt);
  rt.judge(
    id: 'BB7-05',
    lens: 'BB7',
    title: 'create-mux-live na live alheia',
    hit: createMux,
    cracked: createMux.ok,
    actor: 'seller JWT',
    pre: 'live B',
    repro: 'POST create-mux-live',
    severity: 'P1',
  );

  final sk = await rt.rest(
    'GET',
    'lives?id=eq.$liveB&select=id,stream_key,mux_stream_key,mux_live_id',
    jwt: rt.buyerJwt,
  );
  final skBody = sk.body.toLowerCase();
  final leakedKey = sk.ok &&
      (skBody.contains('stream_key') &&
          !skBody.contains('null') &&
          sk.map?['stream_key'] != null);
  rt.judge(
    id: 'BB7-06',
    lens: 'BB7',
    title: 'Buyer lê stream_key da live B',
    hit: sk,
    cracked: leakedKey,
    actor: 'buyer JWT',
    pre: 'coluna stream_key',
    repro: 'GET lives select stream_key',
    severity: 'P1',
  );

  final ocr = await rt.edge('ingest-ocr-reservation', {
    'live_id': liveA,
    'ref_slug': 'x',
    'requested_qty': 1,
    'external_display_name': 'pwn',
  }, jwt: rt.buyerJwt);
  rt.judge(
    id: 'BB7-07',
    lens: 'BB7',
    title: 'OCR ingest sem device token (JWT buyer)',
    hit: ocr,
    cracked: ocr.ok && !ocr.body.contains('missing_device_token'),
    actor: 'buyer JWT',
    pre: 'edge exige x-device-token',
    repro: 'POST ingest-ocr-reservation',
    severity: 'P1',
  );

  final raffleBc = await rt.rpc('batata_live_raffle_social_broadcast', {
    'p_live_id': liveB,
    'p_body': 'ganhou rifa falsa',
  }, jwt: rt.buyerJwt);
  rt.judge(
    id: 'BB7-08',
    lens: 'BB7',
    title: 'raffle_social_broadcast na live alheia',
    hit: raffleBc,
    cracked: raffleBc.ok && !raffleBc.denied,
    actor: 'buyer JWT',
    pre: 'GRANT deve ser service_role',
    repro: 'rpc batata_live_raffle_social_broadcast',
    severity: 'P2',
  );

  final tip = await rt.rest('POST', 'live_tips', jwt: rt.buyerJwt, body: {
    'live_id': liveB,
    'buyer_id': rt.buyerId,
    'amount': 50,
    'status': 'completed',
  });
  rt.judge(
    id: 'BB7-09',
    lens: 'BB7',
    title: 'INSERT live_tips completed na live alheia',
    hit: tip,
    cracked: tip.ok,
    actor: 'buyer JWT',
    pre: 'tip completed dispara system message',
    repro: 'POST live_tips status=completed',
    severity: 'P2',
  );

  // ---------------------------------------------------------------------------
  // BB8 — caixa
  // ---------------------------------------------------------------------------
  if (skuA != null) {
    final ghost = await rt.insertOpenOrder(
      productId: skuA,
      jwt: rt.buyerJwt,
      liveItemId: idA,
      liveId: liveA,
      status: 'pago',
      price: 9,
    );
    final ghostRow = ghost != null ? await rt.orderRow(ghost) : null;
    rt.judge(
      id: 'BB8-01',
      lens: 'BB8',
      title: 'Buyer INSERT order já pago (fantasma)',
      hit: ghost == null
          ? HttpHit(400, 'no id', null)
          : await rt.rest('GET', 'orders?id=eq.$ghost&select=id,status',
              service: true),
      cracked: ghost != null && '${ghostRow?['status']}' == 'pago',
      actor: 'buyer JWT',
      pre: 'sem Stripe',
      repro: 'POST orders status=pago',
      severity: 'P0',
      evidence: {'id': ghost, 'row': ghostRow},
    );

    final open = await rt.insertOpenOrder(
      productId: skuA,
      jwt: rt.buyerJwt,
      liveItemId: idA,
      liveId: liveA,
      status: 'reserva_pendente',
    );
    if (open != null) {
      final toPago = await rt.rest(
        'PATCH',
        'orders?id=eq.$open',
        jwt: rt.buyerJwt,
        body: {
          'status': 'pago',
          'amount_paid_cents': 900,
          'stripe_payment_intent_id': 'pi_rtbb2_fake',
        },
      );
      final after = await rt.orderRow(open);
      rt.judge(
        id: 'BB8-02',
        lens: 'BB8',
        title: 'Buyer PATCH order → pago + PI fake',
        hit: toPago,
        cracked: '${after?['status']}' == 'pago',
        actor: 'buyer JWT',
        pre: 'order reserva_pendente',
        repro: 'PATCH orders status/PI',
        severity: 'P0',
        evidence: {'row': after},
      );
    }
  }

  final wPatch = await rt.rest(
    'PATCH',
    'wallets?id=eq.${rt.buyerId}',
    jwt: rt.buyerJwt,
    body: {'balance': 9999},
  );
  rt.judge(
    id: 'BB8-03',
    lens: 'BB8',
    title: 'Buyer PATCH wallet.balance',
    hit: wPatch,
    cracked: wPatch.ok,
    actor: 'buyer JWT',
    pre: 'RLS wallets',
    repro: 'PATCH wallets',
    severity: 'P0',
  );

  final wallets1 = await rt.wallets();
  rt.note('wallets.t1', 'saldos finais', {
    't0': wallets0,
    't1': wallets1,
    'dBuyer': (wallets1['buyer'] ?? 0) - (wallets0['buyer'] ?? 0),
    'dSeller': (wallets1['seller'] ?? 0) - (wallets0['seller'] ?? 0),
    'dS2': (wallets1['seller2'] ?? 0) - (wallets0['seller2'] ?? 0),
  }, lens: 'BB8');

  await rt.cleanupSoft();
  await rt.dumpAll('pass1.json');
  stdout.writeln(
    'DONE findings=${rt.findings.length} blocked=${rt.blocked.length} skipped=${rt.skipped.length}',
  );
}
