/// PASS 3 — H3 2.ª conta hijack · H6 Edge confia buyer_id/seller_id do body.
import 'dart:io';
import '_rth.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rth.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final out = <String, Object?>{
    'pass': 3,
    'prefix': prefix,
  };

  final sku = await c.insertProduct(title: '$prefix h3-sku', qty: 5, price: 8.5);
  final oid = sku == null
      ? null
      : await c.insertOrder(
          productId: sku,
          jwt: c.buyerJwt,
        );
  out['sku'] = sku;
  out['order'] = oid;

  if (oid != null) {
    // H3: buyer2 PATCH order da buyer1
    final patchId = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: c.buyer2Jwt,
      body: {'buyer_id': c.buyer2Id, 'status': 'pago'},
    );
    c.note('p3.h3.patch.order', 'buyer2 PATCH order B1', patchId.brief,
        lens: 'H3');
    final after = await c.orderRow(oid);
    if (after?['buyer_id']?.toString() == c.buyer2Id) {
      c.hold(
        id: 'RTH-H3-001',
        lens: 'H3',
        severity: 'P0',
        title: 'buyer2 assumiu buyer_id da encomenda de B1',
        actor: 'buyer2',
        pre: 'order $oid buyer=B1',
        repro: 'PATCH orders buyer_id=B2',
        expected: 'buyer_id intacto / 403',
        obtained: after,
      );
    }
    if (after?['status']?.toString() == 'pago' &&
        after?['buyer_id']?.toString() == c.buyerId) {
      c.hold(
        id: 'RTH-H3-002',
        lens: 'H3',
        severity: 'P1',
        title: 'buyer2 marcou encomenda alheia como paga',
        actor: 'buyer2',
        pre: 'order $oid',
        repro: 'PATCH orders status=pago',
        expected: '[] / 403',
        obtained: after,
      );
    }

    final selB2 = await c.rest(
      'GET',
      'orders?id=eq.$oid&select=id,buyer_id,status,price_total',
      jwt: c.buyer2Jwt,
    );
    c.note('p3.h3.select', 'buyer2 SELECT order B1', selB2.brief, lens: 'H3');
    if (selB2.ok && selB2.list.isNotEmpty) {
      c.hold(
        id: 'RTH-H3-003',
        lens: 'H3',
        severity: 'P1',
        title: 'buyer2 lê encomenda de B1',
        actor: 'buyer2',
        pre: 'RLS parties',
        repro: 'GET orders?id=eq.B1order',
        expected: '[]',
        obtained: selB2.snippet,
      );
    }

    final rev = await c.rest('POST', 'reviews', jwt: c.buyer2Jwt, body: {
      'order_id': oid,
      'buyer_id': c.buyerId,
      'target_id': c.sellerId,
      'author_role': 'comprador',
      'stars': 1,
      'comment': '$prefix hijack review',
    });
    c.note('p3.h3.review', 'buyer2 review order B1', rev.brief, lens: 'H3');
    if (rev.ok && rev.firstId != null) {
      c.hold(
        id: 'RTH-H3-004',
        lens: 'H3',
        severity: 'P1',
        title: 'buyer2 escreveu review na encomenda de B1',
        actor: 'buyer2',
        pre: 'order $oid não é de B2; não concluido',
        repro: 'POST reviews order_id=B1',
        expected: '403',
        obtained: rev.brief,
      );
    }

    final disp = await c.rest('POST', 'order_disputes', jwt: c.buyer2Jwt, body: {
      'order_id': oid,
      'buyer_id': c.buyerId,
      'reason': 'danificado',
    });
    c.note('p3.h3.dispute', 'buyer2 disputa order B1', disp.brief, lens: 'H3');
    if (disp.ok && disp.firstId != null) {
      c.hold(
        id: 'RTH-H3-005',
        lens: 'H3',
        severity: 'P1',
        title: 'buyer2 abriu disputa na encomenda de B1',
        actor: 'buyer2',
        pre: 'order $oid',
        repro: 'POST order_disputes',
        expected: '403',
        obtained: disp.brief,
      );
    }
  }

  // H3: INSERT chat como se fosse B1
  final chatForge = await c.rest('POST', 'chats', jwt: c.buyer2Jwt, body: {
    'user_a': c.buyerId,
    'user_b': c.sellerId,
  });
  c.note('p3.h3.chat.forge', 'buyer2 INSERT chat B1-S1', chatForge.brief,
      lens: 'H3');
  if (chatForge.ok && chatForge.firstId != null) {
    c.createdChatIds.add(chatForge.firstId!);
    c.hold(
      id: 'RTH-H3-006',
      lens: 'H3',
      severity: 'P0',
      title: 'buyer2 criou thread fingindo ser B1',
      actor: 'buyer2',
      pre: 'user_a=B1 user_b=S1 JWT=B2',
      repro: 'POST chats',
      expected: '403',
      obtained: chatForge.brief,
    );
  }

  // Chat real B1-S1, depois B2 tenta mensagens / swap
  final chatReal = await c.rest('POST', 'chats', jwt: c.buyerJwt, body: {
    'user_a': c.buyerId,
    'user_b': c.sellerId,
  });
  c.note('p3.h3.chat.real', 'B1 INSERT chat', chatReal.brief, lens: 'H3');
  var chatId = chatReal.firstId;
  if (chatId == null) {
    final exist = await c.rest(
      'GET',
      'chats?or=(and(user_a.eq.${c.buyerId},user_b.eq.${c.sellerId}),and(user_a.eq.${c.sellerId},user_b.eq.${c.buyerId}))&select=id,user_a,user_b&limit=1',
      jwt: c.buyerJwt,
    );
    chatId = exist.firstId;
    c.note('p3.h3.chat.exist', 'chat existente', exist.brief, lens: 'H3');
  }
  if (chatId != null) c.createdChatIds.add(chatId);

  if (chatId != null) {
    final swap = await c.rest(
      'PATCH',
      'chats?id=eq.$chatId',
      jwt: c.buyerJwt,
      body: {'user_a': c.buyer2Id},
    );
    c.note('p3.h3.chat.swap', 'B1 PATCH user_a=B2', swap.brief, lens: 'H3');
    final chatObs = await c.rest(
      'GET',
      'chats?id=eq.$chatId&select=id,user_a,user_b',
      service: true,
    );
    if (chatObs.map?['user_a']?.toString() == c.buyer2Id) {
      c.hold(
        id: 'RTH-H3-007',
        lens: 'H3',
        severity: 'P1',
        title: 'Participante trocou user_a para outra conta',
        actor: 'buyer',
        pre: 'trigger freeze user_a/user_b',
        repro: 'PATCH chats user_a=B2',
        expected: 'user_a frozen',
        obtained: chatObs.snippet,
      );
    }

    final msgX = await c.rest('POST', 'chat_messages', jwt: c.buyer2Jwt, body: {
      'chat_id': chatId,
      'sender_id': c.buyerId,
      'content': '$prefix hijack msg',
    });
    c.note('p3.h3.msg', 'buyer2 INSERT msg no chat B1', msgX.brief, lens: 'H3');
    if (msgX.ok && msgX.firstId != null) {
      c.hold(
        id: 'RTH-H3-008',
        lens: 'H3',
        severity: 'P1',
        title: 'buyer2 escreveu no chat B1–S1',
        actor: 'buyer2',
        pre: 'não participante',
        repro: 'POST chat_messages chat_id=B1',
        expected: '403',
        obtained: msgX.brief,
      );
    }

    final readX = await c.rest(
      'GET',
      'chat_messages?chat_id=eq.$chatId&select=id,sender_id,content&limit=5',
      jwt: c.buyer2Jwt,
    );
    c.note('p3.h3.msg.read', 'buyer2 lê msgs B1', readX.brief, lens: 'H3');
    if (readX.ok && readX.list.isNotEmpty) {
      c.hold(
        id: 'RTH-H3-009',
        lens: 'H3',
        severity: 'P1',
        title: 'buyer2 lê mensagens do chat B1–S1',
        actor: 'buyer2',
        pre: 'não participante',
        repro: 'GET chat_messages',
        expected: '[]',
        obtained: {'n': readX.list.length, 'snip': readX.snippet},
      );
    }
  }

  // Seller forja encomenda como se o comprador fosse B2
  if (sku != null) {
    final forged = await c.rest('POST', 'orders', jwt: c.sellerJwt, body: {
      'buyer_id': c.buyer2Id,
      'seller_id': c.sellerId,
      'product_id': sku,
      'price_total': 8.5,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    });
    c.note('p3.h3.seller.forge', 'seller INSERT order buyer=B2', forged.brief,
        lens: 'H3');
    if (forged.ok && forged.firstId != null) {
      c.createdOrderIds.add(forged.firstId!);
      final frow = await c.orderRow(forged.firstId!);
      if (frow?['buyer_id']?.toString() == c.buyer2Id) {
        c.hold(
          id: 'RTH-H3-010',
          lens: 'H3',
          severity: 'P1',
          title: 'Vendedor criou hold atribuído a B2 sem consentimento',
          actor: 'seller',
          pre: 'RLS insert seller_id=uid; buyer_id=B2',
          repro: 'POST orders JWT seller buyer_id=B2',
          expected: 'buyer_id forçado ao uid ou 403',
          obtained: frow,
        );
      }
    }
  }

  // ---- H6 Edge body IDs ----
  if (oid != null) {
    final piSpoof = await c.edge('create-payment-intent', {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'order_id': oid,
      'product_id': sku,
      'quantity': 1,
      'amount': 1,
      'currency': 'eur',
      'shipping_method': 'carrier',
    }, jwt: c.buyer2Jwt);
    c.note('p3.h6.pi.spoof', 'B2 checkout order B1 com buyer_id=B1',
        piSpoof.brief,
        lens: 'H6');
    if (piSpoof.ok && piSpoof.hasCheckout) {
      c.hold(
        id: 'RTH-H6-001',
        lens: 'H6',
        severity: 'P0',
        title: 'Edge emitiu Session com JWT B2 e buyer_id de B1',
        actor: 'buyer2',
        pre: 'order $oid é de B1',
        repro: 'create-payment-intent buyer_id=B1 JWT=B2',
        expected: '401/403 mismatch',
        obtained: piSpoof.brief,
      );
    }

    final piOwn = await c.edge('create-payment-intent', {
      'buyer_id': c.buyer2Id,
      'seller_id': c.sellerId,
      'order_id': oid,
      'product_id': sku,
      'quantity': 1,
      'amount': 1,
      'currency': 'eur',
      'shipping_method': 'carrier',
    }, jwt: c.buyer2Jwt);
    c.note('p3.h6.pi.ownid', 'B2 checkout order B1 com o próprio buyer_id',
        piOwn.brief,
        lens: 'H6');
    if (piOwn.ok && piOwn.hasCheckout) {
      c.hold(
        id: 'RTH-H6-002',
        lens: 'H6',
        severity: 'P0',
        title: 'Edge emitiu Session para encomenda alheia (JWT=buyer_id≠order.buyer)',
        actor: 'buyer2',
        pre: 'order $oid buyer=B1',
        repro: 'create-payment-intent order_id=B1 JWT=B2',
        expected: '403 / buyer mismatch',
        obtained: piOwn.brief,
      );
    }

    final refundB2 = await c.edge('refund-order', {
      'order_id': oid,
    }, jwt: c.buyer2Jwt);
    c.note('p3.h6.refund.b2', 'B2 refund order B1', refundB2.brief, lens: 'H6');
    if (refundB2.ok && refundB2.map?['ok'] == true && refundB2.map?['skipped'] != true) {
      c.hold(
        id: 'RTH-H6-003',
        lens: 'H6',
        severity: 'P0',
        title: 'buyer2 reembolsou encomenda de B1',
        actor: 'buyer2',
        pre: 'refund-order exige uid==seller',
        repro: 'POST refund-order JWT B2',
        expected: '403 Sem permissão',
        obtained: refundB2.brief,
      );
    }

    final refundBuyer = await c.edge('refund-order', {
      'order_id': oid,
    }, jwt: c.buyerJwt);
    c.note('p3.h6.refund.b1', 'B1 refund própria', refundBuyer.brief, lens: 'H6');
    if (refundBuyer.ok &&
        refundBuyer.map?['ok'] == true &&
        refundBuyer.map?['skipped'] != true) {
      c.hold(
        id: 'RTH-H6-004',
        lens: 'H6',
        severity: 'P1',
        title: 'Comprador chamou refund-order (Edge seller-only)',
        actor: 'buyer',
        pre: 'uid !== seller_id',
        repro: 'POST refund-order JWT buyer',
        expected: '403',
        obtained: refundBuyer.brief,
      );
    }
  }

  final connect = await c.edge('create-connect-account', {
    'user_id': c.sellerId,
  }, jwt: c.buyer2Jwt);
  c.note('p3.h6.connect', 'B2 connect user_id=S1', connect.brief, lens: 'H6');
  if (connect.ok && connect.body.contains('account')) {
    c.hold(
      id: 'RTH-H6-005',
      lens: 'H6',
      severity: 'P1',
      title: 'create-connect-account aceitou user_id alheio',
      actor: 'buyer2',
      pre: 'body.user_id=S1 JWT=B2',
      repro: 'POST create-connect-account',
      expected: '400 spoof',
      obtained: connect.brief,
    );
  }

  final live = await c.insertLive(active: false);
  if (live != null) {
    final completeB2 = await c.edge('complete-mux-live', {
      'live_id': live,
    }, jwt: c.buyer2Jwt);
    c.note('p3.h6.complete', 'B2 complete live S1', completeB2.brief, lens: 'H6');
    if (completeB2.ok) {
      c.hold(
        id: 'RTH-H6-006',
        lens: 'H6',
        severity: 'P1',
        title: 'buyer2 encerrou live do vendedor',
        actor: 'buyer2',
        pre: 'live $live',
        repro: 'POST complete-mux-live JWT B2',
        expected: '403',
        obtained: completeB2.brief,
      );
    }
  }

  // e2e settle sem service_role (JWT)
  final e2eJwt = await c.edge('create-payment-intent', {
    'e2e_settle': true,
    'buyer_id': c.buyer2Id,
    'seller_id': c.sellerId,
    'order_id': oid,
    'payment_intent_id': 'pi_fake_rth',
  }, jwt: c.buyer2Jwt);
  c.note('p3.h6.e2e.jwt', 'JWT tenta caminho e2e settle', e2eJwt.brief,
      lens: 'H6');

  out['notes'] = c.notes;
  out['findings'] = c.findings;
  await c.endLives();
  await dumpJson('tool/redteam_blind_h_20260831T1706/pass3.json', out);
  stdout.writeln('PASS3 findings=${c.findings.length}');
}
