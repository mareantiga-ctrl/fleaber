/// REDTEAM_BLIND_W_CHAT_PROVAS_v1 — staging only. Não corrige. Não toca produção.
import 'dart:convert';
import 'dart:io';
import '_rtw.dart';

Future<void> main() async {
  final c = Rtw.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  stdout.writeln('actors B=${c.buyerId} S=${c.sellerId} B2=${c.buyer2Id}');

  final w0 = await c.wallets();
  c.note('w0.wallets', 'saldos iniciais', w0, lens: 'W8');

  // ----- fixtures -----
  final holdProd = await c.insertProduct(title: '$prefix hold', price: 7.2);
  final holdOid = await c.insertOrder(
    productId: holdProd!,
    price: 7.2,
    status: 'reserva_pendente',
    jwt: c.buyerJwt,
  );
  final holdChat = await c.ensureChat(holdProd);
  c.note('fx.hold', 'hold order+chat', {
    'oid': holdOid,
    'chat': holdChat,
    'prod': holdProd,
  }, lens: 'W1');

  final paidFx = await c.setupPaidStripe();
  final paidOid = paidFx['order_id'];
  final paidPid = paidFx['product_id'];
  final paidPi = paidFx['pi'];
  String? paidChat;
  if (paidPid != null) {
    paidChat = await c.ensureChat(paidPid);
  }
  Map<String, dynamic>? paidOrder;
  if (paidOid != null) paidOrder = await c.orderRow(paidOid);
  c.note('fx.paid', 'stripe paid', {
    'oid': paidOid,
    'chat': paidChat,
    'pi': paidPi,
    'status': paidOrder?['status'],
    'paid_cents': paidOrder?['amount_paid_cents'],
  }, lens: 'W1');

  if (holdOid == null || holdChat == null) {
    stderr.writeln('fixture hold failed');
  }
  if (paidOid == null || paidChat == null) {
    stderr.writeln('fixture paid/chat failed — continuing with hold');
  }

  final b = c.buyerJwt!;
  final s = c.sellerJwt!;
  final b2 = c.buyer2Jwt!;
  final s2 = c.seller2Jwt!;

  // =====================================================================
  // W1 — INSERT system kinds / seguro without capture / fake receipt amount
  // =====================================================================
  Future<void> tryIns(
    String id,
    String lens,
    String chatId,
    String jwt,
    String text, {
    String? title,
    String? createdAt,
    bool expectBlock = true,
    String? sender,
  }) async {
    final r = await c.postMsg(chatId, text,
        jwt: jwt, createdAt: createdAt, sender: sender);
    if (r.ok) {
      if (expectBlock) {
        c.hold(
          id: id,
          lens: lens,
          severity: 'P1',
          title: title ?? 'INSERT system card aceite',
          actor: jwt == b
              ? 'buyer JWT'
              : jwt == s
                  ? 'seller JWT'
                  : jwt == b2
                      ? 'buyer2 JWT'
                      : 'JWT',
          pre: 'chat participante',
          repro: 'POST chat_messages text=${clip(text, 120)}',
          expected: 'bloqueado',
          obtained: r.brief,
          evidence: {'msg_id': r.firstId, 'body': clip(r.body, 400)},
        );
      } else {
        c.note(id, title ?? 'INSERT permitido', r.brief, lens: lens);
      }
    } else {
      c.closed(id, title ?? 'INSERT bloqueado', r.brief, lens: lens);
    }
  }

  if (holdChat != null && holdOid != null) {
    await tryIns(
      'W1.order_paid.unpaid',
      'W1',
      holdChat,
      b,
      jsonCard('order_paid', {'order_id': holdOid, 'total': 99.0}),
      title: 'Buyer INSERT order_paid em hold sem captura',
    );
    await tryIns(
      'W1.seguro.unpaid',
      'W1',
      holdChat,
      b,
      jsonCard('seguro_fleaber_paid', {'order_id': holdOid, 'total': 99.0}),
      title: 'Buyer INSERT seguro_fleaber_paid em hold sem captura',
    );
    await tryIns(
      'W1.bag.unpaid',
      'W1',
      holdChat,
      b,
      jsonCard('marketplace_bag_paid', {'order_id': holdOid, 'total': 40}),
      title: 'Buyer INSERT marketplace_bag_paid',
    );
    await tryIns(
      'W1.plain.seguro',
      'W1',
      holdChat,
      b,
      'Compra paga através do Seguro Fleaber: artigo (99,00 €).',
      title: 'Buyer INSERT plain legado Seguro',
    );
    await tryIns(
      'W1.plain.nbsp',
      'W1',
      holdChat,
      b,
      'Compra\u00a0paga através do Seguro Fleaber: artigo (88,00 €).',
      title: 'Buyer INSERT Seguro com NBSP (bypass regex)',
      expectBlock: false,
    );
    await tryIns(
      'W1.plain.dblspace',
      'W1',
      holdChat,
      b,
      'Compra  paga através do Seguro Fleaber: artigo (77,00 €).',
      title: 'Buyer INSERT Seguro com espaço duplo',
      expectBlock: false,
    );
    await tryIns(
      'W1.plain.conjunto',
      'W1',
      holdChat,
      b,
      'Compra em conjunto paga através do Seguro Fleaber: 3 artigos (120,00 €).',
      title: 'Buyer INSERT plain conjunto Seguro',
    );
    await tryIns(
      'W1.bom.order_paid',
      'W1',
      holdChat,
      b,
      '\uFEFFFLEABER_JSON_V1:${jsonEncode({'kind': 'order_paid', 'order_id': holdOid})}',
      title: 'BOM + FLEABER_JSON_V1 order_paid',
      expectBlock: false,
    );
    await tryIns(
      'W1.lower.prefix',
      'W1',
      holdChat,
      b,
      'fleaber_json_v1:${jsonEncode({'kind': 'order_paid', 'order_id': holdOid})}',
      title: 'prefixo minúsculo order_paid',
      expectBlock: false,
    );
    await tryIns(
      'W1.kind.case',
      'W1',
      holdChat,
      b,
      jsonCard('ORDER_PAID', {'order_id': holdOid}),
      title: 'kind ORDER_PAID (lower→server_only)',
    );
    await tryIns(
      'W1.payment_submitted.unpaid',
      'W1',
      holdChat,
      b,
      jsonCard('reservation_payment_submitted', {
        'order_id': holdOid,
        'amount': 999,
      }),
      title: 'Buyer INSERT reservation_payment_submitted em hold',
      expectBlock: false,
    );
  }

  if (paidChat != null && paidOid != null) {
    await tryIns(
      'W1.seguro.fake_total',
      'W1',
      paidChat,
      b,
      jsonCard('seguro_fleaber_paid', {
        'order_id': paidOid,
        'total': 9999.99,
        'label': 'iPhone 15 Pro Max',
      }),
      title: 'Buyer INSERT seguro_fleaber_paid com total JSON ≠ order',
      expectBlock: false,
    );
    await tryIns(
      'W1.seguro.seller',
      'W1',
      paidChat,
      s,
      jsonCard('seguro_fleaber_paid', {
        'order_id': paidOid,
        'total': 1,
      }),
      title: 'Seller INSERT seguro_fleaber_paid (buyer-only)',
    );
    await tryIns(
      'W1.order_paid.captured',
      'W1',
      paidChat,
      b,
      jsonCard('order_paid', {'order_id': paidOid, 'total': 1}),
      title: 'Buyer INSERT order_paid em order capturada',
    );

    // W6 — seller cancel_request_outcome without Edge refund
    final wBeforeCancel = await c.wallets();
    final cancelIns = await c.postMsg(
      paidChat,
      jsonCard('cancel_request_outcome', {
        'order_id': paidOid,
        'outcome': 'accepted',
        'display':
            'Compra cancelada — Reembolso Stripe de 9999,99 € concluído na hora.',
        'v': 1,
      }),
      jwt: s,
    );
    final afterCancelOrder = await c.orderRow(paidOid);
    final wAfterCancel = await c.wallets();
    c.note('W6.cancel.ins', 'seller cancel_request_outcome', cancelIns.brief,
        lens: 'W6');
    if (cancelIns.ok) {
      final stillPaid = (afterCancelOrder?['status']?.toString() ?? '') !=
          'cancelado';
      final noRefund =
          (afterCancelOrder?['stripe_refund_id']?.toString() ?? '').isEmpty;
      final moneySame = wAfterCancel['seller'] == wBeforeCancel['seller'] &&
          wAfterCancel['buyer'] == wBeforeCancel['buyer'];
      c.hold(
        id: 'W6.P1.cancel_lie',
        lens: 'W6',
        severity: stillPaid && noRefund ? 'P1' : 'P2',
        title:
            'Vendedor INSERT cancel_request_outcome accepted sem refund Stripe',
        actor: 'seller JWT',
        pre: 'order Stripe capturada status=${paidOrder?['status']}',
        repro:
            'POST chat_messages FLEABER_JSON_V1 kind=cancel_request_outcome outcome=accepted',
        expected:
            'bloqueado, ou só aceite se BD/Stripe já cancelados',
        obtained:
            'msg=${cancelIns.firstId} status=${afterCancelOrder?['status']} refund_id=${afterCancelOrder?['stripe_refund_id']} wallets=$wAfterCancel',
        evidence: {
          'order_before': paidOrder,
          'order_after': afterCancelOrder,
          'wallets_before': wBeforeCancel,
          'wallets_after': wAfterCancel,
          'money_unchanged': moneySame,
          'ui_display':
              'Compra cancelada — Reembolso Stripe de 9999,99 € concluído na hora.',
        },
      );
    } else {
      c.closed('W6.cancel_outcome', 'seller cancel_request_outcome blocked',
          cancelIns.brief,
          lens: 'W6');
    }

    // buyer cannot insert cancel outcome
    await tryIns(
      'W6.buyer.cancel_outcome',
      'W6',
      paidChat,
      b,
      jsonCard('cancel_request_outcome', {
        'order_id': paidOid,
        'outcome': 'accepted',
        'display': 'cancelado',
      }),
      title: 'Buyer INSERT cancel_request_outcome',
    );

    // W5 shipped / completed cards without BD change
    await tryIns(
      'W5.shipped.lie',
      'W5',
      paidChat,
      s,
      jsonCard('reservation_order_shipped', {'order_id': paidOid}),
      title: 'Seller INSERT reservation_order_shipped sem BD enviado',
      expectBlock: false,
    );
    await tryIns(
      'W5.completed.lie',
      'W5',
      paidChat,
      b,
      jsonCard('reservation_order_completed', {'order_id': paidOid}),
      title: 'Buyer INSERT reservation_order_completed sem BD concluido',
      expectBlock: false,
    );
    await tryIns(
      'W5.seller_receipt.lie',
      'W5',
      paidChat,
      s,
      jsonCard('reservation_seller_confirmed_receipt', {'order_id': paidOid}),
      title: 'Seller INSERT confirmed_receipt sem BD',
      expectBlock: false,
    );

    final afterOps = await c.orderRow(paidOid);
    if (afterOps?['status']?.toString() == paidOrder?['status']?.toString()) {
      c.note('W5.bd.unchanged', 'status BD inalterado após cards operacionais',
          afterOps?['status'],
          lens: 'W5');
    }

    // W5 timeline created_at inject
    final past = await c.postMsg(
      paidChat,
      jsonCard('order_dispute_opened', {
        'order_id': paidOid,
        'reason': 'RTW backdate',
      }),
      jwt: b,
      createdAt: '2020-01-01T00:00:00Z',
    );
    if (past.ok) {
      final row = await c.msgRow(past.firstId!);
      final ca = row?['created_at']?.toString() ?? '';
      if (ca.startsWith('2020')) {
        c.hold(
          id: 'W5.P1.created_at_insert',
          lens: 'W5',
          severity: 'P1',
          title: 'JWT escolhe created_at — inject na cronologia do chat',
          actor: 'buyer JWT',
          pre: 'participante',
          repro: 'POST chat_messages created_at=2020-01-01T00:00:00Z',
          expected: 'created_at = now() (servidor)',
          obtained: ca,
          evidence: {'msg': row},
        );
      } else {
        c.closed('W5.created_at.insert', 'created_at forçado para now()', ca,
            lens: 'W5');
      }
    } else {
      c.closed('W5.created_at.insert', 'INSERT com created_at bloqueado',
          past.brief,
          lens: 'W5');
    }

    // W2 PATCH created_at of existing JSON
    if (cancelIns.ok && cancelIns.firstId != null) {
      final pCa = await c.rest(
        'PATCH',
        'chat_messages?id=eq.${cancelIns.firstId}',
        jwt: s,
        body: {'created_at': '2019-06-01T12:00:00Z'},
      );
      final after = await c.msgRow(cancelIns.firstId!);
      final ca = after?['created_at']?.toString() ?? '';
      if (pCa.ok && ca.startsWith('2019')) {
        c.hold(
          id: 'W5.P1.patch_created_at',
          lens: 'W5',
          severity: 'P1',
          title: 'PATCH created_at de card JSON — reordena timeline',
          actor: 'seller JWT (própria msg)',
          pre: 'card cancel_request_outcome imutável no text',
          repro: 'PATCH chat_messages created_at=2019-06-01',
          expected: 'created_at congelado em cards sistema',
          obtained: ca,
          evidence: {'patch': pCa.brief, 'row': after},
        );
      } else {
        c.closed('W5.patch_created_at', 'PATCH created_at recusado ou ignorado',
            '${pCa.brief} ca=$ca',
            lens: 'W5');
      }

      // W2 PATCH text of JSON
      final pTxt = await c.rest(
        'PATCH',
        'chat_messages?id=eq.${cancelIns.firstId}',
        jwt: s,
        body: {
          'text': jsonCard('cancel_request_outcome', {
            'order_id': paidOid,
            'outcome': 'accepted',
            'display': 'MUTATED',
          }),
        },
      );
      final afterTxt = await c.msgRow(cancelIns.firstId!);
      final mutated =
          (afterTxt?['text']?.toString() ?? '').contains('MUTATED');
      if (pTxt.ok && mutated) {
        c.hold(
          id: 'W2.P0.json_text_mutated',
          lens: 'W2',
          severity: 'P0',
          title: 'UPDATE text de card JSON sistema',
          actor: 'seller JWT',
          pre: 'FLEABER_JSON_V1 já gravado',
          repro: 'PATCH chat_messages text=…MUTATED',
          expected: 'chat_system_card_immutable',
          obtained: afterTxt?['text'],
        );
      } else {
        c.closed('W2.json_text', 'JSON text imutável', pTxt.brief, lens: 'W2');
      }
    }

    // W2 other-party non-text UPDATE
    final buyerPlain = await c.postMsg(paidChat, 'rtw-plain-marker', jwt: b);
    if (buyerPlain.ok && buyerPlain.firstId != null) {
      final otherPatch = await c.rest(
        'PATCH',
        'chat_messages?id=eq.${buyerPlain.firstId}',
        jwt: s,
        body: {
          'created_at': '2018-01-01T00:00:00Z',
          'is_reservation': true,
          'text': 'seller-overwrote-buyer-text',
        },
      );
      final row = await c.msgRow(buyerPlain.firstId!);
      final textKept = row?['text']?.toString() == 'rtw-plain-marker';
      final caMoved = (row?['created_at']?.toString() ?? '').startsWith('2018');
      final resFlag = row?['is_reservation'] == true;
      if (otherPatch.ok && (caMoved || resFlag) && textKept) {
        c.hold(
          id: 'W2.P1.counterparty_meta',
          lens: 'W2',
          severity: 'P1',
          title:
              'Participante PATCH created_at/is_reservation da mensagem do outro',
          actor: 'seller JWT',
          pre: 'RLS update_participants; guard só restaura text se sender≠uid',
          repro:
              'PATCH chat_messages id=msg_do_buyer created_at+is_reservation',
          expected: 'só o autor altera metadados; text alheio já congelado',
          obtained: row,
          evidence: {'text_kept': textKept, 'created_at_moved': caMoved},
        );
      } else if (otherPatch.ok && !textKept) {
        c.hold(
          id: 'W2.P0.counterparty_text',
          lens: 'W2',
          severity: 'P0',
          title: 'Participante altera text da mensagem do outro',
          actor: 'seller JWT',
          pre: 'msg buyer',
          repro: 'PATCH chat_messages text=',
          expected: 'text restaurado',
          obtained: row?['text'],
        );
      } else {
        c.closed('W2.counterparty_meta', 'PATCH alheio bloqueado ou no-op',
            '${otherPatch.brief} row=$row',
            lens: 'W2');
      }
    }

    // W2 DELETE own JSON receipt
    final fakeSeguroId = c.findings
            .where((f) => f['id'] == 'W1.seguro.fake_total')
            .isNotEmpty
        ? null
        : null;
    // find last seguro insert via query
    final seguroRows = await c.rest(
      'GET',
      'chat_messages?chat_id=eq.$paidChat&text=like.*seguro_fleaber_paid*&select=id,sender_id,text&order=id.desc&limit=3',
      service: true,
    );
    final ownSeguro = seguroRows.list.cast<dynamic>().where((e) {
      if (e is! Map) return false;
      return e['sender_id']?.toString() == c.buyerId;
    });
    if (ownSeguro.isNotEmpty) {
      final sid = ownSeguro.first['id'];
      final del = await c.rest(
        'DELETE',
        'chat_messages?id=eq.$sid',
        jwt: b,
      );
      final still = await c.msgRow(sid);
      if (del.ok && still == null) {
        c.hold(
          id: 'W2.P1.delete_receipt',
          lens: 'W2',
          severity: 'P1',
          title: 'Buyer DELETE do próprio card recibo JSON',
          actor: 'buyer JWT',
          pre: 'sender_id=buyer no card seguro_fleaber_paid',
          repro: 'DELETE chat_messages?id=eq.$sid',
          expected: 'cards sistema não apagáveis por JWT',
          obtained: del.brief,
        );
      } else {
        c.closed('W2.delete_receipt', 'DELETE recibo bloqueado',
            '${del.brief} still=$still',
            lens: 'W2');
      }
    } else {
      c.note('W2.delete_receipt.skip', 'sem card seguro próprio para DELETE',
          seguroRows.brief,
          lens: 'W2');
    }

    // W2 DELETE of service-role inserted receipt
    final svcIns = await c.rest('POST', 'chat_messages', service: true, body: {
      'chat_id': paidChat,
      'sender_id': c.buyerId,
      'receiver_id': c.sellerId,
      'text': jsonCard('order_paid', {'order_id': paidOid, 'total': 1}),
      'is_read': false,
    });
    c.note('W2.svc.order_paid', 'service insert order_paid (recibo oficial)',
        svcIns.brief,
        lens: 'W2');
    if (svcIns.ok && svcIns.firstId != null) {
      final delSvc = await c.rest(
        'DELETE',
        'chat_messages?id=eq.${svcIns.firstId}',
        jwt: b,
      );
      final gone = await c.msgRow(svcIns.firstId!);
      if (delSvc.ok && gone == null) {
        c.hold(
          id: 'W2.P0.delete_server_receipt',
          lens: 'W2',
          severity: 'P0',
          title: 'Buyer apaga recibo order_paid inserido pelo servidor',
          actor: 'buyer JWT',
          pre: 'service_role INSERT kind=order_paid sender=buyer',
          repro: 'DELETE chat_messages id=recibo_servidor',
          expected: 'recibo servidor imutável/não apagável',
          obtained: delSvc.brief,
        );
      } else {
        c.closed('W2.delete_server_receipt', 'DELETE recibo servidor bloqueado',
            delSvc.brief,
            lens: 'W2');
      }
    }

    // W8 — chat lie → refund / release
    final relAfterLie = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': paidOid},
      jwt: s,
    );
    c.note('W8.release.after_chat_lie', 'release após cards falsos',
        relAfterLie.brief,
        lens: 'W8');
    final refundBuyer = await c.edge('refund-order', {'order_id': paidOid}, jwt: b);
    final refundSeller = await c.edge('refund-order', {'order_id': paidOid}, jwt: s);
    c.note('W8.refund.buyer', 'refund-order buyer após cancel lie',
        refundBuyer.brief,
        lens: 'W8');
    c.note('W8.refund.seller', 'refund-order seller após cancel lie',
        refundSeller.brief,
        lens: 'W8');
    final postMoney = await c.orderRow(paidOid);
    if (refundBuyer.ok) {
      c.hold(
        id: 'W8.P0.buyer_refund',
        lens: 'W8',
        severity: 'P0',
        title: 'Comprador chama refund-order com sucesso',
        actor: 'buyer JWT',
        pre: 'chat com cancel_request_outcome falso',
        repro: 'POST /functions/v1/refund-order order_id',
        expected: '403 seller-only',
        obtained: refundBuyer.brief,
        evidence: {'order': postMoney},
      );
    } else {
      c.closed('W8.buyer_refund', 'buyer refund-order recusado',
          refundBuyer.brief,
          lens: 'W8');
    }
    if (refundSeller.ok &&
        (postMoney?['stripe_refund_id']?.toString() ?? '').isNotEmpty) {
      c.note('W8.seller.refund.happened',
          'seller refund-order moveu Stripe — Edge ignora o chat',
          postMoney,
          lens: 'W8');
    }

    // W3 — B2 thread
    final b2sel = await c.rest(
      'GET',
      'chat_messages?chat_id=eq.$paidChat&select=id,text,sender_id&limit=5',
      jwt: b2,
    );
    final b2ins = await c.postMsg(paidChat, 'b2-intrusion', jwt: b2);
    final b2patch = buyerPlain.ok
        ? await c.rest(
            'PATCH',
            'chat_messages?id=eq.${buyerPlain.firstId}',
            jwt: b2,
            body: {'is_read': true},
          )
        : HttpHit(0, 'skip', null);
    if (b2sel.ok && b2sel.list.isNotEmpty) {
      c.hold(
        id: 'W3.P0.b2_read',
        lens: 'W3',
        severity: 'P0',
        title: 'B2 lê chat_messages da thread B1/S1',
        actor: 'buyer2 JWT',
        pre: 'chat de outro par',
        repro: 'GET chat_messages?chat_id=eq.$paidChat',
        expected: '[]',
        obtained: b2sel.brief,
      );
    } else {
      c.closed('W3.b2_read', 'B2 não lê thread alheia', b2sel.brief, lens: 'W3');
    }
    if (b2ins.ok) {
      c.hold(
        id: 'W3.P0.b2_write',
        lens: 'W3',
        severity: 'P0',
        title: 'B2 escreve na thread B1/S1',
        actor: 'buyer2 JWT',
        pre: 'não participante',
        repro: 'POST chat_messages chat_id=thread_alheia',
        expected: 'RLS deny',
        obtained: b2ins.brief,
      );
    } else {
      c.closed('W3.b2_write', 'B2 INSERT thread alheia bloqueado', b2ins.brief,
          lens: 'W3');
    }
    c.note('W3.b2_patch', 'B2 PATCH msg alheia', b2patch.brief, lens: 'W3');

    final anonSel = await c.rest(
      'GET',
      'chat_messages?chat_id=eq.$paidChat&select=id&limit=3',
    );
    if (anonSel.ok && anonSel.list.isNotEmpty) {
      c.hold(
        id: 'W3.P0.anon_read',
        lens: 'W3',
        severity: 'P0',
        title: 'anon lê chat_messages',
        actor: 'anon',
        pre: 'sem JWT user',
        repro: 'GET chat_messages Authorization=anon',
        expected: '[]',
        obtained: anonSel.brief,
      );
    } else {
      c.closed('W3.anon_read', 'anon não lê chat', anonSel.brief, lens: 'W3');
    }

    // GraphQL
    final gql = await c.req('POST', '/graphql/v1', jwt: b2, body: {
      'query':
          'query { chatMessagesCollection(filter: { chatId: { eq: "$paidChat" } }, first: 5) { edges { node { id text senderId } } } }',
    });
    c.note('W3.gql', 'graphql chatMessagesCollection', gql.brief, lens: 'W3');
    final gqlText = gql.body;
    if (gql.ok &&
        gqlText.contains('"id"') &&
        !gqlText.contains('errors') &&
        gqlText.contains('chatMessagesCollection')) {
      final empty = gqlText.contains('"edges":[]') ||
          gqlText.contains('"edges": []');
      if (!empty) {
        c.hold(
          id: 'W3.P0.gql_read',
          lens: 'W3',
          severity: 'P0',
          title: 'GraphQL B2 lê mensagens da thread alheia',
          actor: 'buyer2 JWT',
          pre: 'pg graphql',
          repro: 'POST /graphql/v1 chatMessagesCollection',
          expected: 'edges vazios',
          obtained: clip(gql.body, 400),
        );
      } else {
        c.closed('W3.gql_read', 'GraphQL não devolve thread alheia', gql.brief,
            lens: 'W3');
      }
    }

    // W4 chat_image pointing at other path + arbitrary http
    await tryIns(
      'W4.chat_image.http',
      'W4',
      paidChat,
      b,
      jsonCard('chat_image', {
        'url': 'https://example.invalid/fake-mbway-receipt.png',
        'path': '',
      }),
      title: 'INSERT chat_image URL arbitrária',
      expectBlock: false,
    );
    await tryIns(
      'W4.chat_image.other_path',
      'W4',
      paidChat,
      b,
      jsonCard('chat_image', {
        'path': 'chat_uploads/${c.sellerId}/$paidChat/secret.jpg',
      }),
      title: 'INSERT chat_image path da pasta do outro',
      expectBlock: false,
    );

    // W7 bundle_proposal fake totals
    final bun = await c.rest('POST', 'product_bundles', jwt: b, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'status': 'pending',
      'total_eur': 10,
      'discount_eur': 0,
    });
    c.note('W7.bundle.ins', 'product_bundles INSERT', bun.brief, lens: 'W7');
    if (bun.ok && bun.firstId != null) {
      c.createdBundleIds.add(bun.firstId!);
      final fakeCard = await c.postMsg(
        paidChat,
        jsonCard('bundle_proposal', {
          'bundle_id': bun.firstId,
          'buyer_id': c.buyerId,
          'seller_id': c.sellerId,
          'total_eur': 8888.0,
          'discount_eur': 0,
          'product_ids': [paidPid],
          'request_mode': 'discount',
        }),
        jwt: b,
      );
      if (fakeCard.ok) {
        c.hold(
          id: 'W7.P1.bundle_payload_price',
          lens: 'W7',
          severity: 'P1',
          title:
              'INSERT bundle_proposal com total_eur JSON sem validação vs bundle/orders',
          actor: 'buyer JWT',
          pre: 'kind bundle_proposal na allowlist sem check de preço',
          repro:
              'POST chat_messages kind=bundle_proposal total_eur=8888 bundle real a 10',
          expected: 'preço do card = product_bundles.total_eur / orders',
          obtained: fakeCard.brief,
          evidence: {
            'bundle_id': bun.firstId,
            'bundle_total': 10,
            'card_total': 8888,
            'flutter':
                'BundleProposalChatCard usa payload total_eur quando frozen; pending usa bundle row se existir',
          },
        );
      } else {
        c.closed('W7.bundle_proposal', 'bundle_proposal INSERT blocked',
            fakeCard.brief,
            lens: 'W7');
      }

      // accepted freeze: service-mark accepted then insert stale card
      await c.rest(
        'PATCH',
        'product_bundles?id=eq.${bun.firstId}',
        service: true,
        body: {'status': 'accepted', 'total_eur': 10},
        prefer: 'return=minimal',
      );
      final frozenCard = await c.postMsg(
        paidChat,
        jsonCard('bundle_proposal', {
          'bundle_id': bun.firstId,
          'buyer_id': c.buyerId,
          'seller_id': c.sellerId,
          'total_eur': 7777.0,
          'discount_eur': 0,
          'product_ids': [paidPid],
          'request_mode': 'discount',
        }),
        jwt: b,
      );
      if (frozenCard.ok) {
        c.hold(
          id: 'W7.P1.bundle_frozen_payload',
          lens: 'W7',
          severity: 'P1',
          title:
              'Card conjunto aceite desenha total_eur do JSON (frozen), não da encomenda',
          actor: 'buyer JWT',
          pre: 'bundle status=accepted total=10; Flutter frozen lê payload',
          repro:
              'POST bundle_proposal total_eur=7777 com bundle_id aceite',
          expected: 'totais só da BD orders/bundle',
          obtained: frozenCard.brief,
          evidence: {
            'msg_id': frozenCard.firstId,
            'flutter_source':
                'frozen ? payload[total_eur] : bundle[total_eur]',
          },
        );
      } else {
        c.closed('W7.frozen_card', 'segundo bundle_proposal blocked',
            frozenCard.brief,
            lens: 'W7');
      }
    }

    // W7 price_offer_outcome fake
    await tryIns(
      'W7.price_outcome.fake',
      'W7',
      paidChat,
      s,
      jsonCard('price_offer_outcome', {
        'order_id': paidOid,
        'outcome': 'accepted',
        'amount': 0.01,
      }),
      title: 'Seller INSERT price_offer_outcome accepted amount=0.01',
      expectBlock: false,
    );
  }

  // =====================================================================
  // W4 — storage / proof_url variants / dispute photos
  // =====================================================================
  final proofPath =
      'order_proofs/${c.buyerId}/${holdOid ?? 'no-oid'}/rtw-proof.png';
  final upProof = await c.storageUpload(
    jwt: b,
    bucket: 'fleaber_private',
    path: proofPath,
    bytes: tinyPng,
  );
  c.note('W4.upload.proof', 'buyer upload order_proofs', upProof.brief,
      lens: 'W4');

  final listPub = await c.storageList(jwt: b2, bucket: 'chat_media', prefix: '');
  c.note('W4.list.chat_media', 'B2 list chat_media público', listPub.brief,
      lens: 'W4');
  if (listPub.ok && listPub.list.isNotEmpty) {
    // atrophy-adjacent if this is "list público exact" — still record as note
    // unless it leaks proofs/chat_uploads
    final leaked = listPub.body.contains('order_proofs') ||
        listPub.body.contains('chat_uploads') ||
        listPub.body.contains('order_disputes');
    if (leaked) {
      c.hold(
        id: 'W4.P1.public_list_private_prefix',
        lens: 'W4',
        severity: 'P1',
        title: 'List chat_media público devolve proofs/uploads',
        actor: 'buyer2 JWT',
        pre: 'bucket chat_media',
        repro: 'POST /storage/v1/object/list/chat_media prefix=',
        expected: 'sem order_proofs/chat_uploads',
        obtained: clip(listPub.body, 400),
      );
    } else {
      c.note('W4.list.catalog', 'list público sem proofs (catálogo?)',
          clip(listPub.body, 200),
          lens: 'W4');
    }
  }

  final listPrivB2 = await c.storageList(
    jwt: b2,
    bucket: 'fleaber_private',
    prefix: 'order_proofs/${c.buyerId}/',
  );
  c.note('W4.list.private.b2', 'B2 lista pasta proofs B1', listPrivB2.brief,
      lens: 'W4');
  if (listPrivB2.ok &&
      listPrivB2.body.contains('rtw-proof')) {
    c.hold(
      id: 'W4.P0.list_other_proofs',
      lens: 'W4',
      severity: 'P0',
      title: 'B2 lista objectos order_proofs de B1',
      actor: 'buyer2 JWT',
      pre: 'pasta order_proofs/{buyer1}/',
      repro: 'POST storage list fleaber_private prefix=order_proofs/{b1}/',
      expected: '[]',
      obtained: clip(listPrivB2.body, 400),
    );
  } else {
    c.closed('W4.list_other_proofs', 'B2 não lista proofs B1', listPrivB2.brief,
        lens: 'W4');
  }

  final signB2 = await c.storageSign(
    jwt: b2,
    bucket: 'fleaber_private',
    path: proofPath,
  );
  c.note('W4.sign.b2', 'B2 createSignedUrl path B1', signB2.brief, lens: 'W4');
  if (signB2.ok && (signB2.body.contains('signedURL') ||
      signB2.body.contains('signedUrl'))) {
    c.hold(
      id: 'W4.P0.sign_other_proof',
      lens: 'W4',
      severity: 'P0',
      title: 'B2 assina URL da prova de B1',
      actor: 'buyer2 JWT',
      pre: 'path order_proofs/{b1}/{oid}/…',
      repro: 'POST storage/v1/object/sign/fleaber_private/…',
      expected: '403/400',
      obtained: clip(signB2.body, 300),
    );
  } else {
    c.closed('W4.sign_other', 'B2 não assina prova alheia', signB2.brief,
        lens: 'W4');
  }

  final getB2 = await c.storageGet(
    jwt: b2,
    bucket: 'fleaber_private',
    path: proofPath,
  );
  if (getB2.status == 200 && getB2.body.length > 20) {
    c.hold(
      id: 'W4.P0.get_other_proof',
      lens: 'W4',
      severity: 'P0',
      title: 'B2 GET objecto prova B1',
      actor: 'buyer2 JWT',
      pre: 'objecto fleaber_private',
      repro: 'GET /storage/v1/object/fleaber_private/order_proofs/…',
      expected: '403',
      obtained: '${getB2.status} len=${getB2.body.length}',
    );
  } else {
    c.closed('W4.get_other', 'B2 GET prova alheia recusado', getB2.brief,
        lens: 'W4');
  }

  // path traversal
  final trav = await c.storageGet(
    jwt: b2,
    bucket: 'fleaber_private',
    path: 'order_proofs/${c.buyer2Id}/../${c.buyerId}/${holdOid}/rtw-proof.png',
  );
  c.note('W4.trav.get', 'path .. no GET', trav.brief, lens: 'W4');
  if (trav.status == 200 && trav.body.contains('PNG')) {
    c.hold(
      id: 'W4.P0.path_traversal',
      lens: 'W4',
      severity: 'P0',
      title: 'GET storage com .. atravessa pasta de outro uid',
      actor: 'buyer2 JWT',
      pre: 'objecto em order_proofs/{b1}/',
      repro: 'GET …/order_proofs/{b2}/../{b1}/{oid}/file',
      expected: '404/403',
      obtained: '${trav.status} ${clip(trav.body, 80)}',
    );
  } else {
    c.closed('W4.path_trav', 'traversal não serviu o ficheiro', trav.brief,
        lens: 'W4');
  }

  // proof_url INSERT bypass (trigger is UPDATE of proof_url)
  final evilInsert = await c.insertOrder(
    productId: holdProd,
    price: 3,
    jwt: b,
    proofUrl: 'https://evil.example/receipt.png',
  );
  if (evilInsert != null) {
    final row = await c.orderRow(evilInsert);
    final pu = row?['proof_url']?.toString() ?? '';
    if (pu.contains('evil.example')) {
      c.hold(
        id: 'W4.P1.proof_url_insert',
        lens: 'W4',
        severity: 'P1',
        title: 'INSERT orders.proof_url externo — trigger só cobre UPDATE',
        actor: 'buyer JWT',
        pre: 'trg_batata_orders_guard_proof_url BEFORE UPDATE OF proof_url',
        repro: 'POST orders proof_url=https://evil.example/receipt.png',
        expected: 'proof_url negado ou null',
        obtained: pu,
        evidence: {'order_id': evilInsert},
      );
    } else {
      c.closed('W4.proof_insert', 'INSERT proof_url não persistiu evil', pu,
          lens: 'W4');
    }
  } else {
    c.note('W4.proof_insert.fail', 'INSERT order com proof_url falhou', null,
        lens: 'W4');
  }

  // proof_url UPDATE variants (not the exact #https:// / wrap)
  if (holdOid != null) {
    final variants = <String, String>{
      'userinfo':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co%2estage.evil.example/x',
      'subdomain':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co.evil.example/storage/v1/x',
      'fleaber_typo': 'https://fleaber.app.evil.example/p.png',
      'data': 'data:image/png;base64,aaaa',
      'protocol_rel': '//evil.example/p.png',
      'javascript': 'javascript:alert(1)',
      'unicode_slash':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/chat_media/\u2215\u2215evil.example',
      'encoded_nl': 'https://fleaber.app/a%0d%0aLocation:%20https://evil.example',
      'backslash': 'https://fleaber.app\\@evil.example/p',
      'own_storage_other_user':
          'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/order_proofs/${c.sellerId}/x.png',
    };
    for (final e in variants.entries) {
      final p = await c.rest(
        'PATCH',
        'orders?id=eq.$holdOid',
        jwt: b,
        body: {'proof_url': e.value},
      );
      final row = await c.orderRow(holdOid);
      final stored = row?['proof_url']?.toString() ?? '';
      final persisted = stored == e.value || stored.contains(e.value);
      c.note('W4.proof.${e.key}', 'PATCH proof_url ${e.key}',
          '${p.brief} stored=${clip(stored, 80)}',
          lens: 'W4');
      if (p.ok && persisted && e.key != 'own_storage_other_user') {
        c.hold(
          id: 'W4.P1.proof_url_${e.key}',
          lens: 'W4',
          severity: 'P1',
          title: 'PATCH proof_url variante ${e.key} persistida',
          actor: 'buyer JWT',
          pre: 'order hold; guard host allowlist só se paid',
          repro: 'PATCH orders proof_url=${clip(e.value, 80)}',
          expected: 'denied',
          obtained: stored,
        );
      }
    }
    // paid order proof_url other-user storage path
    if (paidOid != null) {
      final paidProof = await c.rest(
        'PATCH',
        'orders?id=eq.$paidOid',
        jwt: b,
        body: {
          'proof_url':
              'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/authenticated/fleaber_private/order_proofs/${c.sellerId}/not-mine.png',
        },
      );
      final pr = await c.orderRow(paidOid);
      final stored = pr?['proof_url']?.toString() ?? '';
      if (paidProof.ok && stored.contains('${c.sellerId}')) {
        c.hold(
          id: 'W4.P1.paid_proof_other_uid',
          lens: 'W4',
          severity: 'P1',
          title:
              'Order paga aceita proof_url storage apontando à pasta de outro uid',
          actor: 'buyer JWT',
          pre: 'allowlist host supabase.co/storage sem amarrar uid',
          repro: 'PATCH orders.proof_url …/order_proofs/{seller}/…',
          expected: 'path só order_proofs/{auth.uid()}/{order_id}/',
          obtained: stored,
        );
      } else {
        c.closed('W4.paid_proof_other', 'proof_url paid other uid blocked',
            '${paidProof.brief} $stored',
            lens: 'W4');
      }
    }
  }

  // dispute + proof_photos arbitrary URLs
  String? did;
  if (paidOid != null) {
    final dIns = await c.rest('POST', 'order_disputes', jwt: b, body: {
      'order_id': paidOid,
      'buyer_id': c.buyerId,
      'reason': 'nao_corresponde',
      'description': '$prefix disputa',
      'status': 'aberta',
    });
    c.note('W4.dispute.jwt', 'buyer INSERT disputa', dIns.brief, lens: 'W4');
    did = dIns.firstId;
    if (did == null) {
      final fx = await c.rest('POST', 'order_disputes', service: true, body: {
        'order_id': paidOid,
        'buyer_id': c.buyerId,
        'reason': 'nao_corresponde',
        'description': '$prefix disputa fixture',
        'status': 'aberta',
      });
      did = fx.firstId;
      c.note('W4.dispute.fixture', 'service INSERT disputa', fx.brief,
          lens: 'W4');
    }
    if (did != null) c.createdDisputeIds.add(did);
  }

  if (did != null) {
    final reply = await c.rest('POST', 'order_dispute_replies', jwt: b, body: {
      'dispute_id': did,
      'sender_id': c.buyerId,
      'message': 'prova anexada',
      'proof_photos': [
        'https://evil.example/stolen-iban.png',
        'javascript:alert(1)',
        'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/chat_media/product_photos/${c.sellerId}/x.jpg',
      ],
    });
    c.note('W4.reply.photos', 'INSERT dispute reply proof_photos', reply.brief,
        lens: 'W4');
    if (reply.ok) {
      c.hold(
        id: 'W4.P1.dispute_proof_photos_any_url',
        lens: 'W4',
        severity: 'P1',
        title:
            'order_dispute_replies.proof_photos aceita URLs arbitrárias (evil/js)',
        actor: 'buyer JWT',
        pre: 'disputa aberta; sem guard de URL no array',
        repro:
            'POST order_dispute_replies proof_photos=[https://evil.example/…]',
        expected: 'só storage fleaber_private/order_disputes/{uid}/',
        obtained: reply.brief,
        evidence: {'dispute_id': did, 'msg_id': reply.firstId},
      );
    } else {
      c.closed('W4.proof_photos', 'proof_photos evil blocked', reply.brief,
          lens: 'W4');
    }

    // B2 read dispute
    final b2d = await c.rest(
      'GET',
      'order_disputes?id=eq.$did&select=id,status,description',
      jwt: b2,
    );
    if (b2d.ok && b2d.list.isNotEmpty) {
      c.hold(
        id: 'W3.P0.b2_dispute',
        lens: 'W3',
        severity: 'P0',
        title: 'B2 lê disputa B1/S1',
        actor: 'buyer2 JWT',
        pre: 'order_disputes alheia',
        repro: 'GET order_disputes?id=eq.$did',
        expected: '[]',
        obtained: b2d.brief,
      );
    } else {
      c.closed('W3.b2_dispute', 'B2 não lê disputa alheia', b2d.brief,
          lens: 'W3');
    }

    // seller PATCH resolvida — atrophy exact; probe but do not stop
    final patchRes = await c.rest(
      'PATCH',
      'order_disputes?id=eq.$did',
      jwt: s,
      body: {'status': 'resolvida'},
    );
    c.note('W4.seller.resolvida', 'seller PATCH resolvida (known exact)',
        patchRes.brief,
        lens: 'W4');

    // dispute storage path of seller as buyer
    final sellerDispPath =
        'order_disputes/${c.sellerId}/${did}_rtw.png';
    final upSellerAsBuyer = await c.storageUpload(
      jwt: b,
      bucket: 'fleaber_private',
      path: sellerDispPath,
      bytes: tinyPng,
    );
    c.note('W4.upload.seller_folder', 'buyer upload into seller dispute folder',
        upSellerAsBuyer.brief,
        lens: 'W4');
    if (upSellerAsBuyer.ok) {
      c.hold(
        id: 'W4.P1.upload_other_dispute_folder',
        lens: 'W4',
        severity: 'P1',
        title: 'Buyer faz upload para order_disputes/{seller_uid}/',
        actor: 'buyer JWT',
        pre: 'path app = order_disputes/{uploader_uid}/',
        repro: 'POST storage object order_disputes/{seller}/…',
        expected: 'só a própria pasta uid',
        obtained: upSellerAsBuyer.brief,
      );
    } else {
      c.closed('W4.upload_other_folder', 'upload pasta seller bloqueado',
          upSellerAsBuyer.brief,
          lens: 'W4');
    }

    final signSellerFolder = await c.storageSign(
      jwt: b,
      bucket: 'fleaber_private',
      path: sellerDispPath,
    );
    if (signSellerFolder.ok &&
        (signSellerFolder.body.contains('signedURL') ||
            signSellerFolder.body.contains('signedUrl'))) {
      c.hold(
        id: 'W4.P1.sign_seller_dispute',
        lens: 'W4',
        severity: 'P1',
        title: 'Buyer assina path order_disputes do vendedor',
        actor: 'buyer JWT',
        pre: 'policy counterparty: buyer só a própria pasta',
        repro: 'POST object/sign …/order_disputes/{seller}/…',
        expected: 'deny',
        obtained: clip(signSellerFolder.body, 240),
      );
    } else {
      c.closed('W4.sign_seller_disp', 'buyer não assina pasta seller',
          signSellerFolder.brief,
          lens: 'W4');
    }
  }

  // chats.last_message lie
  if (paidChat != null) {
    final lm = await c.rest(
      'PATCH',
      'chats?id=eq.$paidChat',
      jwt: b,
      body: {
        'last_message': 'Compra paga pelo Seguro Fleaber — 9999,99 €',
      },
    );
    c.note('W1.inbox.last_message', 'PATCH chats.last_message', lm.brief,
        lens: 'W1');
    if (lm.ok) {
      c.hold(
        id: 'W1.P2.inbox_preview_lie',
        lens: 'W1',
        severity: 'P2',
        title: 'Participante PATCH last_message da thread (pré-visualização)',
        actor: 'buyer JWT',
        pre: 'chats_update_participants',
        repro: 'PATCH chats last_message=Compra paga… 9999€',
        expected: 'last_message só via servidor/trigger',
        obtained: lm.brief,
      );
    }
  }

  // W8 composition: forged completed card then release
  if (paidOid != null) {
    final o = await c.orderRow(paidOid);
    final rel = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': paidOid},
      jwt: b,
    );
    c.note('W8.release.buyer', 'buyer tenta release', rel.brief, lens: 'W8');
    if (rel.ok && o?['wallet_release_processed_at'] == null) {
      final o2 = await c.orderRow(paidOid);
      if (o2?['wallet_release_processed_at'] != null) {
        c.hold(
          id: 'W8.P0.release_from_buyer',
          lens: 'W8',
          severity: 'P0',
          title: 'Buyer RPC liberta carteira do vendedor',
          actor: 'buyer JWT',
          pre: 'order ainda não concluída necessariamente',
          repro: 'rpc batata_release_seller_wallet_for_order',
          expected: 'deny ou no-op',
          obtained: o2,
        );
      }
    }
  }

  final wEnd = await c.wallets();
  c.note('wEnd.wallets', 'saldos finais', {'start': w0, 'end': wEnd},
      lens: 'W8');

  final out = {
    'stamp': stamp,
    'prefix': prefix,
    'production_touched': false,
    'fase4': false,
    'findings': c.findings,
    'closed': c.blocked,
    'notes': c.notes,
    'wallets_start': w0,
    'wallets_end': wEnd,
    'paid_order': paidOid,
    'hold_order': holdOid,
  };
  await dumpJson('${outDir()}/probe.json', out);
  stdout.writeln(
      'DONE findings=${c.findings.length} closed=${c.blocked.length}');
}
