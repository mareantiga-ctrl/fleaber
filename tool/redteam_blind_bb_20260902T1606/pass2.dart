/// RED TEAM CEGO BB — pass 2. Confirmação + lacunas. Não corrige.
import 'dart:io';
import '_rtbb.dart';

bool rpcOk(HttpHit h) =>
    h.ok && (h.body.contains('"ok":true') || h.body.contains('"ok": true'));

Future<void> main() async {
  final rt = Rtbb.fromEnv(loadEnv());
  await rt.loginActors();
  await rt.ensureBuyer2();
  await rt.ensureSeller2();
  await rt.ensureHelper();

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

  final liveA = await rt.insertLive(title: '$prefix p2 A');
  final liveB = await rt.insertLive(seller: rt.seller2Id, title: '$prefix p2 B');
  if (liveA == null || liveB == null) {
    rt.skip('BB.p2.live', 'BB1', 'insertLive', {'a': liveA, 'b': liveB});
    await rt.dumpAll('pass2.json');
    exit(4);
  }
  final sku = await rt.createProduct(title: '$prefix p2 sku', qty: 2, price: 12);
  final itemA = await rt.insertItem(
    liveId: liveA,
    service: true,
    title: '$prefix p2 itemA',
    qty: 1,
  );
  final itemA2 = await rt.insertItem(
    liveId: liveA,
    service: true,
    title: '$prefix p2 itemA2',
    qty: 1,
    productId: sku,
    kind: 'marketplace_product',
  );
  final itemB = await rt.insertItem(
    liveId: liveB,
    service: true,
    title: '$prefix p2 itemB',
  );
  final idA = itemA.firstId;
  final idA2 = itemA2.firstId;
  final idB = itemB.firstId;
  if (idA == null || idA2 == null) {
    rt.skip('BB.p2.items', 'BB1', 'items', itemA.brief);
    await rt.cleanupSoft();
    await rt.dumpAll('pass2.json');
    exit(4);
  }

  // Staff chat-only (accepted+active)
  final hid = await rt.inviteHelper(
    helperUserId: rt.helperId!,
    status: 'accepted',
    active: true,
    perms: const {
      'can_manage_chat': true,
      'can_mark_items_sold': false,
      'can_manage_reservations': false,
    },
  );

  // ---- BB8-03 retract: PATCH wallet 200 [] não muda saldo ----
  final w0 = await rt.walletBal(rt.buyerId);
  final wPatch = await rt.rest(
    'PATCH',
    'wallets?id=eq.${rt.buyerId}',
    jwt: rt.buyerJwt,
    body: {'balance': 9999},
  );
  final w1 = await rt.walletBal(rt.buyerId);
  if (wPatch.ok && w1 != w0) {
    rt.hold(
      id: 'BB8-03',
      lens: 'BB8',
      severity: 'P0',
      title: 'Buyer PATCH wallet.balance persiste',
      actor: 'buyer JWT',
      pre: 'pass1 200 [] suspeito',
      repro: 'PATCH wallets balance=9999',
      expected: 'negado / saldo intacto',
      obtained: {'hit': wPatch.brief, 'w0': w0, 'w1': w1},
    );
  } else {
    rt.block('BB8-03', 'BB8', 'PATCH wallet 200 sem persistir', {
      'hit': wPatch.brief,
      'w0': w0,
      'w1': w1,
    });
  }

  // ---- BB1-04 confirm: helper system «comprou» visível como system ----
  final marker = 'RTBB2-P2-HELPER-LIE-${rt.nextRef()}';
  final sysH = await rt.rpc('batata_live_system_message', {
    'p_live_id': liveA,
    'p_body': '✅ Comprador fantasma comprou $marker',
    'p_sender_label': 'Sistema',
  }, jwt: rt.helperJwt);
  final msgsB2 = await rt.liveMsgs(liveA, jwt: rt.buyer2Jwt);
  final msgsB1 = await rt.liveMsgs(liveA, jwt: rt.buyerJwt);
  Map<String, dynamic>? lie;
  for (final m in [...msgsB2, ...msgsB1]) {
    if (m is Map && '${m['body']}'.contains(marker)) {
      lie = Map<String, dynamic>.from(m);
      break;
    }
  }
  final helperLie = rpcOk(sysH) &&
      lie != null &&
      '${lie['kind']}' == 'system' &&
      '${lie['body']}'.contains('comprou');
  if (helperLie) {
    rt.hold(
      id: 'BB1-04',
      lens: 'BB2',
      severity: 'P3',
      title:
          'Helper can_manage_chat publica kind=system «comprou» sem order paga (visível a outros buyers)',
      actor: 'helper JWT; leitura buyer2',
      pre:
          'ANAS exige PI em purchase_broadcast; system_message só cheque staff chat',
      repro: 'rpc batata_live_system_message body ✅ comprou',
      expected: 'anúncio de compra só com PI; ou kind≠system',
      obtained: {'rpc': sysH.brief, 'msg': lie},
      evidence: {'visible_b2': msgsB2.any((m) => m is Map && '${m['body']}'.contains(marker))},
    );
  } else {
    rt.block('BB1-04', 'BB2', 'helper system comprou', {
      'rpc': sysH.brief,
      'lie': lie,
    });
  }

  // Helper na live alheia
  final sysAlien = await rt.rpc('batata_live_system_message', {
    'p_live_id': liveB,
    'p_body': '✅ sabotagem $marker',
    'p_sender_label': 'Sistema',
  }, jwt: rt.helperJwt);
  rt.judge(
    id: 'BB1-04b',
    lens: 'BB7',
    title: 'Helper da loja A system_message na live do seller2',
    hit: sysAlien,
    cracked: rpcOk(sysAlien),
    actor: 'helper JWT',
    pre: 'staff só da loja A',
    repro: 'rpc system_message liveB',
    severity: 'P2',
  );

  // Helper sem can_manage_chat
  if (hid != null) {
    await rt.rest(
      'PATCH',
      'seller_helpers?id=eq.$hid',
      service: true,
      body: {
        'permissions': {
          'can_manage_chat': false,
          'can_mark_items_sold': false,
        },
        'active': true,
        'invitation_status': 'accepted',
      },
      prefer: 'return=minimal',
    );
    final sysNoChat = await rt.rpc('batata_live_system_message', {
      'p_live_id': liveA,
      'p_body': '✅ sem chat perm $marker',
      'p_sender_label': 'Sistema',
    }, jwt: rt.helperJwt);
    rt.judge(
      id: 'BB1-04c',
      lens: 'BB2',
      title: 'Helper sem can_manage_chat ainda injeta system',
      hit: sysNoChat,
      cracked: rpcOk(sysNoChat),
      actor: 'helper JWT',
      pre: 'permissions.can_manage_chat=false',
      repro: 'rpc system_message',
      severity: 'P2',
    );
    // restore chat for leftover tests
    await rt.rest(
      'PATCH',
      'seller_helpers?id=eq.$hid',
      service: true,
      body: {
        'permissions': {'can_manage_chat': true},
        'active': true,
        'invitation_status': 'accepted',
      },
      prefer: 'return=minimal',
    );
  }

  // Seller system_message (canal próprio) — HOLD produto, não finding
  final sysS = await rt.rpc('batata_live_system_message', {
    'p_live_id': liveA,
    'p_body': '✅ seller anuncia $marker',
    'p_sender_label': 'Sistema',
  }, jwt: rt.sellerJwt);
  rt.note('BB1-03.hold', 'seller system_message próprio canal', sysS, lens: 'BB1');

  // ---- facebook_manual convert sem PI ----
  final resFb = await rt.insertRes(
    liveId: liveA,
    itemId: idA,
    jwt: rt.buyerJwt,
    source: 'facebook_manual',
  );
  HttpHit convFb;
  if (resFb.firstId != null) {
    await rt.processRes(resFb.firstId!, 'accept');
    convFb = await rt.processRes(resFb.firstId!, 'convert');
  } else {
    final svcFb = await rt.insertRes(
      liveId: liveA,
      itemId: idA,
      service: true,
      source: 'facebook_manual',
    );
    if (svcFb.firstId != null) {
      await rt.processRes(svcFb.firstId!, 'accept');
      convFb = await rt.processRes(svcFb.firstId!, 'convert');
    } else {
      convFb = svcFb;
    }
  }
  rt.judge(
    id: 'BB1-12',
    lens: 'BB1',
    title: 'convert facebook_manual sem PI',
    hit: convFb,
    cracked: convFb.ok &&
        !convFb.body.contains('convert_requires_paid_order') &&
        !convFb.body.contains('not_allowed') &&
        (convFb.body.contains('"ok":true') || convFb.body.contains('converted')),
    actor: 'seller JWT',
    pre: 'source facebook_manual',
    repro: 'process convert',
    severity: 'P1',
  );

  // ---- reconcile aguarda_confirmacao (MB WAY pendente) ----
  if (sku != null) {
    final pend = await rt.rest('POST', 'orders', service: true, body: {
      'buyer_id': rt.buyerId,
      'seller_id': rt.sellerId,
      'product_id': sku,
      'price_total': 12,
      'quantity': 1,
      'status': 'aguarda_confirmacao',
      'payment_method': 'MB WAY',
      'shipping_method': 'entrega em mão',
      'live_item_id': idA,
      'live_id': liveA,
    });
    if (pend.firstId != null) rt.createdOrderIds.add(pend.firstId!);
    final recB = pend.firstId == null
        ? pend
        : await rt.rpc('batata_live_reconcile_stripe_order', {
            'p_order_id': pend.firstId,
          }, jwt: rt.buyerJwt);
    final recS = pend.firstId == null
        ? pend
        : await rt.rpc('batata_live_reconcile_stripe_order', {
            'p_order_id': pend.firstId,
          }, jwt: rt.sellerJwt);
    final converted = await rt.rest(
      'GET',
      'live_reservation_requests?live_id=eq.$liveA&buyer_id=eq.${rt.buyerId}&status=eq.converted&select=id,status,notes,source,live_item_id',
      service: true,
    );
    final cracked = (rpcOk(recB) && !recB.body.contains('order_not_paid')) ||
        (rpcOk(recS) && !recS.body.contains('order_not_paid')) ||
        converted.list.isNotEmpty;
    rt.judge(
      id: 'BB1-14',
      lens: 'BB1',
      title: 'reconcile com order aguarda_confirmacao (sem captura) converte fila',
      hit: recS,
      cracked: cracked,
      actor: 'buyer+seller JWT',
      pre: 'fixture MB WAY pendente; função lista aguarda_confirmacao como paga',
      repro: 'rpc batata_live_reconcile_stripe_order',
      severity: 'P1',
      evidence: {
        'ins': pend.brief,
        'buyer': recB.brief,
        'seller': recS.brief,
        'converted': converted.list,
      },
    );

    // Cross-item: PI/pago no item A2, broadcast do item A
    final paidA2 = await rt.insertPaidOrder(
      productId: sku,
      liveItemId: idA2,
      liveId: liveA,
      price: 12,
    );
    final bcWrong = await rt.rpc('batata_live_purchase_broadcast', {
      'p_live_id': liveA,
      'p_buyer_id': rt.buyerId,
      'p_live_item_id': idA,
    }, jwt: rt.sellerJwt);
    final wrongTrue =
        bcWrong.ok && (bcWrong.body.contains('true') && !bcWrong.body.contains('false'));
    rt.judge(
      id: 'BB1-17',
      lens: 'BB1',
      title: 'Broadcast item A usando order paga do item A2',
      hit: bcWrong,
      cracked: wrongTrue,
      actor: 'seller JWT',
      pre: 'pago só em A2',
      repro: 'purchase_broadcast p_live_item_id=A',
      severity: 'P2',
      evidence: {'paidA2': paidA2},
    );

    // premio_rifa JWT: status real
    final rifa = await rt.rest('POST', 'orders', jwt: rt.buyerJwt, body: {
      'buyer_id': rt.buyerId,
      'seller_id': rt.sellerId,
      'product_id': sku,
      'price_total': 0,
      'quantity': 1,
      'status': 'premio_rifa',
      'payment_method': 'rifa',
      'shipping_method': 'entrega em mão',
      'live_item_id': idA2,
      'live_id': liveA,
    });
    if (rifa.firstId != null) {
      rt.createdOrderIds.add(rifa.firstId!);
      final row = await rt.orderRow(rifa.firstId!);
      rt.note('BB1-09.status', 'order JWT premio_rifa persistida', row, lens: 'BB1');
      final stuck = '${row?['status']}' == 'premio_rifa';
      rt.judge(
        id: 'BB1-09b',
        lens: 'BB8',
        title: 'Buyer INSERT order status=premio_rifa persiste',
        hit: rifa,
        cracked: rifa.ok && stuck,
        actor: 'buyer JWT',
        pre: 'sem rifa real',
        repro: 'POST orders status=premio_rifa',
        severity: 'P3',
        evidence: {'row': row},
      );
    }
  }

  // qty=50 clamp
  final fat = await rt.insertRes(
    liveId: liveA,
    itemId: idA,
    jwt: rt.buyer2Jwt,
    buyer: rt.buyer2Id,
    qty: 50,
  );
  final fatRow = fat.firstId != null ? await rt.resRow(fat.firstId!) : null;
  final storedQty = fatRow?['requested_qty'];
  rt.judge(
    id: 'BB5-05',
    lens: 'BB5',
    title: 'requested_qty=50 persiste acima do stock',
    hit: fat,
    cracked: fat.ok && storedQty is num && storedQty > 1,
    actor: 'buyer2 JWT',
    pre: 'item qty=1',
    repro: 'POST reservation requested_qty=50',
    severity: 'P3',
    evidence: {'row': fatRow},
  );

  // race accept rows
  final raceLive = await rt.insertLive(title: '$prefix p2 race');
  if (raceLive != null) {
    final ri = await rt.insertItem(
      liveId: raceLive,
      service: true,
      title: '$prefix p2 race item',
      qty: 1,
    );
    final rid = ri.firstId;
    if (rid != null) {
      final a = await rt.insertRes(
        liveId: raceLive,
        itemId: rid,
        jwt: rt.buyerJwt,
      );
      final b = await rt.insertRes(
        liveId: raceLive,
        itemId: rid,
        jwt: rt.buyer2Jwt,
        buyer: rt.buyer2Id,
      );
      HttpHit? acc1;
      HttpHit? acc2;
      if (a.firstId != null) acc1 = await rt.processRes(a.firstId!, 'accept');
      if (b.firstId != null) acc2 = await rt.processRes(b.firstId!, 'accept');
      final r1 = a.firstId != null ? await rt.resRow(a.firstId!) : null;
      final r2 = b.firstId != null ? await rt.resRow(b.firstId!) : null;
      final both = '${r1?['status']}' == 'accepted' && '${r2?['status']}' == 'accepted';
      rt.judge(
        id: 'BB6-03',
        lens: 'BB6',
        title: 'Dois accepted em item qty=1',
        hit: acc2 ?? acc1 ?? b,
        cracked: both,
        actor: 'seller JWT',
        pre: '2 pending',
        repro: '2x process accept',
        severity: 'P1',
        evidence: {
          'r1': r1,
          'r2': r2,
          'acc1': acc1?.brief,
          'acc2': acc2?.brief,
        },
      );
    }
  }

  // resolve-mux-playback / playback id leak
  final pb = await rt.edge('resolve-mux-playback', {
    'live_id': liveB,
  }, jwt: rt.buyerJwt);
  rt.note('BB7-10', 'resolve-mux-playback live alheia', pb, lens: 'BB7');
  rt.judge(
    id: 'BB7-10',
    lens: 'BB7',
    title: 'resolve-mux-playback devolve stream_key da live alheia',
    hit: pb,
    cracked: pb.ok &&
        pb.body.toLowerCase().contains('stream') &&
        pb.body.contains('key'),
    actor: 'buyer JWT',
    pre: 'live B',
    repro: 'POST resolve-mux-playback',
    severity: 'P1',
  );

  // Happy-path broadcast COM PI (anti-regressão)
  if (sku != null) {
    final paid = await rt.insertPaidOrder(
      productId: sku,
      liveItemId: idA2,
      liveId: liveA,
      price: 12,
    );
    final bcOk = await rt.rpc('batata_live_purchase_broadcast', {
      'p_live_id': liveA,
      'p_buyer_id': rt.buyerId,
      'p_live_item_id': idA2,
    }, jwt: rt.sellerJwt);
    rt.note('BB1.happy', 'broadcast com order paga', {
      'order': paid,
      'bc': bcOk.brief,
    }, lens: 'BB1');
  }

  final wallets = await rt.wallets();
  rt.note('wallets.p2', 'saldos', wallets, lens: 'BB8');

  await rt.cleanupSoft();
  await rt.dumpAll('pass2.json');
  stdout.writeln(
    'DONE p2 findings=${rt.findings.length} blocked=${rt.blocked.length}',
  );
}
