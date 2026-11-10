/// PASS 4 — H7 composição identidade → caixa (hold / Session / refund).
import 'dart:io';
import '_rth.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rth.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  await c.ensureHelperChat();
  await c.ensureHelperRes();

  final out = <String, Object?>{
    'pass': 4,
    'prefix': prefix,
    'wallets_before': await c.wallets(),
  };

  c.helperChatLinkId = await c.inviteHelper(
    helperUserId: c.helperChatId!,
    helperJwt: c.helperChatJwt!,
    permissions: chatOnlyPerms,
    display: '$prefix chat-only',
  );

  // H3 retry: chat_messages.text (coluna real)
  final chatExist = await c.rest(
    'GET',
    'chats?or=(and(user_a.eq.${c.buyerId},user_b.eq.${c.sellerId}),and(user_a.eq.${c.sellerId},user_b.eq.${c.buyerId}))&select=id,user_a,user_b&limit=1',
    jwt: c.buyerJwt,
  );
  final chatId = chatExist.firstId;
  c.note('p4.h3.chat', 'chat B1-S1', chatExist.brief, lens: 'H3');
  if (chatId != null) {
    final msgX = await c.rest('POST', 'chat_messages', jwt: c.buyer2Jwt, body: {
      'chat_id': chatId,
      'sender_id': c.buyerId,
      'text': '$prefix hijack msg',
    });
    c.note('p4.h3.msg', 'B2 INSERT text no chat B1', msgX.brief, lens: 'H3');
    if (msgX.ok && msgX.firstId != null) {
      c.hold(
        id: 'RTH-H3-011',
        lens: 'H3',
        severity: 'P1',
        title: 'buyer2 escreveu no chat B1–S1',
        actor: 'buyer2',
        pre: 'não participante; coluna text',
        repro: 'POST chat_messages text JWT B2',
        expected: '403',
        obtained: msgX.brief,
      );
    }
    final readX = await c.rest(
      'GET',
      'chat_messages?chat_id=eq.$chatId&select=id,sender_id,text&limit=5',
      jwt: c.buyer2Jwt,
    );
    c.note('p4.h3.msg.read', 'B2 lê msgs B1', readX.brief, lens: 'H3');
    if (readX.ok && readX.list.isNotEmpty) {
      c.hold(
        id: 'RTH-H3-012',
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

  // Fixture Stripe TEST — service_role só setup.
  final paid = await c.e2e('setup_paid_order', {'initial_qty': 2});
  c.note('p4.fixture', 'setup_paid_order', paid.brief, lens: 'H7');
  out['setup_paid'] = paid.map ?? paid.snippet;
  final paidOrderId = paid.map?['order_id']?.toString() ??
      paid.map?['id']?.toString();
  final paidPi = paid.map?['payment_intent_id']?.toString() ??
      paid.map?['stripe_payment_intent_id']?.toString();

  if (paidOrderId != null) {
    c.createdOrderIds.add(paidOrderId);
    final row = await c.orderRow(paidOrderId);
    out['paid_row'] = row;

    // Helper chat-only tenta refund da venda paga
    final href = await c.edge('refund-order', {
      'order_id': paidOrderId,
    }, jwt: c.helperChatJwt);
    c.note('p4.h7.helper.refund', 'helper refund paid', href.brief, lens: 'H7');
    if (href.ok && href.map?['ok'] == true && href.map?['skipped'] != true) {
      c.hold(
        id: 'RTH-H7-001',
        lens: 'H7',
        severity: 'P0',
        title: 'Helper chat-only reembolsou encomenda paga Stripe',
        actor: 'helperChat',
        pre: 'order $paidOrderId pago; can_issue_refunds=false',
        repro: 'POST refund-order JWT helper',
        expected: '403 Sem permissão',
        obtained: href.brief,
      );
    }

    // buyer2 refund da venda de B1
    final b2ref = await c.edge('refund-order', {
      'order_id': paidOrderId,
    }, jwt: c.buyer2Jwt);
    c.note('p4.h7.b2.refund', 'B2 refund paid B1', b2ref.brief, lens: 'H7');
    if (b2ref.ok && b2ref.map?['ok'] == true && b2ref.map?['skipped'] != true) {
      c.hold(
        id: 'RTH-H7-002',
        lens: 'H7',
        severity: 'P0',
        title: '2.ª conta reembolsou captura Stripe de B1',
        actor: 'buyer2',
        pre: 'order $paidOrderId',
        repro: 'POST refund-order JWT B2',
        expected: '403',
        obtained: b2ref.brief,
      );
    }

    // Seller2 refund loja alheia
    final s2ref = await c.edge('refund-order', {
      'order_id': paidOrderId,
    }, jwt: c.seller2Jwt);
    c.note('p4.h7.s2.refund', 'S2 refund order S1', s2ref.brief, lens: 'H7');
    if (s2ref.ok && s2ref.map?['ok'] == true && s2ref.map?['skipped'] != true) {
      c.hold(
        id: 'RTH-H7-003',
        lens: 'H7',
        severity: 'P0',
        title: 'Seller2 reembolsou venda da loja S1',
        actor: 'seller2',
        pre: 'uid !== order.seller_id',
        repro: 'POST refund-order JWT S2',
        expected: '403',
        obtained: s2ref.brief,
      );
    }

    // Conceder refund ao helper e repetir (perm bit vs Edge uid==seller)
    if (c.helperChatLinkId != null) {
      await c.rest(
        'PATCH',
        'seller_helpers?id=eq.${c.helperChatLinkId}',
        jwt: c.sellerJwt,
        body: {'permissions': refundPerms, 'active': true, 'invitation_status': 'accepted'},
      );
      final has = await c.rpc('batata_staff_has_permission', {
        'p_seller_id': c.sellerId,
        'p_permission': 'can_issue_refunds',
      }, jwt: c.helperChatJwt);
      c.note('p4.h7.has.refund', 'helper bit refund após grant', has.brief,
          lens: 'H7');
      final href2 = await c.edge('refund-order', {
        'order_id': paidOrderId,
      }, jwt: c.helperChatJwt);
      c.note('p4.h7.helper.refund.granted', 'helper refund com bit', href2.brief,
          lens: 'H7');
      if (href2.ok && href2.map?['ok'] == true && href2.map?['skipped'] != true) {
        c.hold(
          id: 'RTH-H7-004',
          lens: 'H7',
          severity: 'P1',
          title: 'Helper com can_issue_refunds reembolsou via Edge (uid≠seller)',
          actor: 'helperChat',
          pre: 'permissions can_issue_refunds=true; Edge compara uid==seller',
          repro: 'POST refund-order JWT helper',
          expected: '403 (Edge seller-only) OU refund se staff for honrado',
          obtained: href2.brief,
        );
      }
    }

    // B2 tenta settle GET / replay PI
    if (paidPi != null) {
      final settle = await c.edge(
        'create-payment-intent',
        null,
        method: 'GET',
        jwt: c.buyer2Jwt,
        extra: {
          'checkout_return': 'success',
          // query via path
        },
      );
      c.note('p4.h7.settle.get', 'B2 GET settle', settle.brief, lens: 'H7');
    }
  }

  // Composição: seller forja hold B2 → B2 checkout (identidade) → Session
  final sku = await c.insertProduct(title: '$prefix h7-forge', qty: 3);
  if (sku != null) {
    final forged = await c.rest('POST', 'orders', jwt: c.sellerJwt, body: {
      'buyer_id': c.buyer2Id,
      'seller_id': c.sellerId,
      'product_id': sku,
      'price_total': 8.5,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'carrier',
    });
    c.note('p4.h7.forge', 'seller hold as B2', forged.brief, lens: 'H7');
    final fid = forged.firstId;
    if (fid != null) {
      c.createdOrderIds.add(fid);
      final ck = await c.edge('create-payment-intent', {
        'buyer_id': c.buyer2Id,
        'seller_id': c.sellerId,
        'order_id': fid,
        'product_id': sku,
        'quantity': 1,
        'amount': 850,
        'currency': 'eur',
        'shipping_method': 'carrier',
      }, jwt: c.buyer2Jwt);
      c.note('p4.h7.forge.checkout', 'B2 Session no hold forjado', ck.brief,
          lens: 'H7');
      if (ck.ok && ck.hasCheckout) {
        c.hold(
          id: 'RTH-H7-005',
          lens: 'H7',
          severity: 'P1',
          title: 'Hold forjado pelo vendedor gerou Checkout Session para B2',
          actor: 'seller→buyer2',
          pre: 'seller INSERT order buyer=B2; B2 JWT checkout',
          repro: 'POST orders seller + create-payment-intent B2',
          expected: 'hold rejeitado OU checkout recusa order não criada pelo buyer',
          obtained: {
            'order': fid,
            'checkout': ck.brief,
          },
        );
      }
    }
  }

  // Helper chat-only accept reserva do próprio (conluio) em live activa
  final live = await c.insertLive(active: true);
  final liveSku = await c.insertProduct(
    title: '$prefix h7-collude',
    qty: 2,
    live: true,
    listed: false,
  );
  if (live != null && liveSku != null) {
    final up = await c.rpc('batata_upsert_marketplace_live_item', {
      'p_seller_id': c.sellerId,
      'p_product_id': liveSku,
      'p_live_id': live,
    }, jwt: c.sellerJwt);
    final itemId = RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    ).firstMatch(up.body)?.group(0);
    c.note('p4.h7.upsert', 'collude item', up.brief, lens: 'H7');
    if (itemId != null) {
      final resv = await c.rest(
        'POST',
        'live_reservation_requests',
        jwt: c.helperChatJwt,
        body: {
          'live_id': live,
          'live_item_id': itemId,
          'seller_id': c.sellerId,
          'buyer_id': c.helperChatId,
          'requested_qty': 1,
          'source': 'fleaber_live',
          'status': 'pending',
        },
      );
      c.note('p4.h7.resv', 'helper reserva como buyer', resv.brief, lens: 'H7');
      final rid = resv.firstId;
      if (rid != null) {
        final acc = await c.rpc('batata_process_live_reservation_request', {
          'p_request_id': rid,
          'p_action': 'accept',
        }, jwt: c.helperChatJwt);
        c.note('p4.h7.accept.self', 'helper chat-only accept própria', acc.brief,
            lens: 'H7');
        if (acc.ok &&
            (acc.map?['ok'] == true || acc.body.contains('"ok":true'))) {
          c.hold(
            id: 'RTH-H7-006',
            lens: 'H7',
            severity: 'P1',
            title: 'Helper chat-only aceitou a própria reserva (conluio)',
            actor: 'helperChat',
            pre: 'can_manage_reservations=false; buyer_id=self',
            repro: 'INSERT resv JWT helper + process accept JWT helper',
            expected: 'not_allowed / reservation_accept_not_authorized',
            obtained: acc.brief,
          );
        }
      }
    }
  }

  out['wallets_after'] = await c.wallets();
  out['notes'] = c.notes;
  out['findings'] = c.findings;
  await c.endLives();
  await dumpJson('tool/redteam_blind_h_20260831T1706/pass4.json', out);
  stdout.writeln('PASS4 findings=${c.findings.length}');
}
