/// PASS 2 — AL composição disputa/parcial/race/chat/enviado. Não corrige.
import 'dart:io';
import '_rtal.dart';

Future<void> main() async {
  final c = Rtal.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.wallets();
  c.note('p2.snap', 'saldos', w0, lens: 'AL7');

  // ---------------------------------------------------------------------------
  // AL2 — HTML GET origem recusada: sem URL hostil no corpo
  // ---------------------------------------------------------------------------
  final htmlEvil = await c.connectGet(
    qs: '?web_return_origin=${Uri.encodeQueryComponent('https://evil.com')}',
  );
  final bodyEvil = htmlEvil.body.toLowerCase();
  c.note('al2.html.evil', 'GET HTML origem recusada', {
    'status': htmlEvil.status,
    'hasEvil': bodyEvil.contains('evil.com'),
    'hasJsLoc': bodyEvil.contains('location') && bodyEvil.contains('evil'),
    'snippet': clip(htmlEvil.body, 280),
  }, lens: 'AL2');
  if (bodyEvil.contains('evil.com') || htmlEvil.location?.contains('evil') == true) {
    c.hold(
      id: 'AL2-html-contains-evil',
      lens: 'AL2',
      severity: 'P1',
      title: 'Resposta Connect inclui origem hostil',
      actor: 'anon GET',
      pre: 'web_return_origin=https://evil.com',
      repro: 'GET create-connect-account',
      expected: 'sem evil.com',
      obtained: clip(htmlEvil.body, 300),
    );
  } else {
    c.block('AL2-html-evil', 'AL2', 'HTML recusado sem evil.com', htmlEvil.status);
  }

  // localhost 303 — sem tokens; loopback. Documentar, não P0.
  final locLocal = await c.connectGet(qs: '?web_return_origin=http://127.0.0.1');
  c.note('al2.localhost', '303 loopback sem query', {
    'status': locLocal.status,
    'location': locLocal.location,
  }, lens: 'AL2');

  // ---------------------------------------------------------------------------
  // AL5 — seller PATCH enviado depois refund-order
  // ---------------------------------------------------------------------------
  final paidEnv = await c.payToPago(lens: 'AL5');
  if (paidEnv != null) {
    await c.markMao(paidEnv.oid);
    final env = await c.rest(
      'PATCH',
      'orders?id=eq.${paidEnv.oid}',
      jwt: c.sellerJwt,
      body: {'status': 'enviado'},
    );
    c.note('al5.enviado', 'seller PATCH enviado', env.brief, lens: 'AL5');
    final refEnv = await c.refund(paidEnv.oid);
    c.note('al5.refund.enviado', 'refund-order em enviado', refEnv.brief, lens: 'AL5');
    final rowEnv = await c.orderRow(paidEnv.oid);
    if (refEnv.ok && refEnv.map?['ok'] == true) {
      c.hold(
        id: 'AL5-refund-after-enviado',
        lens: 'AL5',
        severity: 'P1',
        title: 'Seller reembolsou Stripe depois de marcar enviado',
        actor: 'seller JWT',
        pre: 'status enviado, PI capturado',
        repro: 'PATCH enviado + POST refund-order',
        expected: '403 order_refund_blocked_status',
        obtained: {
          'refund': refEnv.brief,
          'status': rowEnv?['status'],
        },
      );
    } else {
      c.block('AL5-ref-env', 'AL5', 'refund em enviado bloqueado', refEnv);
    }
  }

  // ---------------------------------------------------------------------------
  // AL3/AL6 — concluido SEM release → disputa → oferta 200% / 40% → process_partial
  // ---------------------------------------------------------------------------
  final wBeforeDisp = await c.wallets();
  final paidD = await c.payToPago(lens: 'AL3');
  if (paidD != null) {
    await c.markMao(paidD.oid);
    final conc = await c.rest(
      'PATCH',
      'orders?id=eq.${paidD.oid}',
      jwt: c.buyerJwt,
      body: {'status': 'concluido'},
    );
    c.note('al3.conc.no-rel', 'concluido sem release', conc.brief, lens: 'AL3');

    final disp = await c.insertDispute(paidD.oid);
    c.note('al3.disp.insert', 'disputa pré-release', disp.brief, lens: 'AL3');

    final dispB2 = await c.insertDispute(paidD.oid,
        jwt: c.buyer2Jwt, buyer: c.buyer2Id);
    c.note('al6.disp.b2', 'buyer2 disputa ordem B1', dispB2.brief, lens: 'AL6');
    if (dispB2.ok && dispB2.firstId != null) {
      c.hold(
        id: 'AL6-b2-dispute-foreign',
        lens: 'AL6',
        severity: 'P1',
        title: '2.º comprador abriu disputa em encomenda alheia',
        actor: 'buyer2 JWT',
        pre: 'order B1 concluido',
        repro: 'POST order_disputes buyer_id=B2',
        expected: '403 RLS',
        obtained: dispB2.brief,
      );
    } else {
      c.block('AL6-disp-b2', 'AL6', 'buyer2 disputa recusada', dispB2);
    }

    if (disp.ok) {
      final offer200 = await c.rest(
        'PATCH',
        'order_disputes?order_id=eq.${paidD.oid}',
        jwt: c.sellerJwt,
        body: {
          'seller_offer_type': 'partial_refund',
          'seller_refund_percent': 200,
        },
      );
      c.note('al6.offer.200', 'oferta 200%', offer200.brief, lens: 'AL6');
      final part200 = await c.rpc('batata_process_partial_refund_dispute', {
        'p_order_id': paidD.oid,
        'p_refund_percent': 200,
      }, jwt: c.buyerJwt);
      c.note('al6.partial.200', 'process_partial 200%', part200.brief, lens: 'AL6');
      final w200 = await c.wallets();
      final dB200 = (w200['buyer'] ?? 0) - (wBeforeDisp['buyer'] ?? 0);
      final dS200 = (w200['seller'] ?? 0) - (wBeforeDisp['seller'] ?? 0);
      c.note('al6.partial.200.delta', 'Δ após 200%', {
        'dB': dB200,
        'dS': dS200,
        'rpc': part200.brief,
      }, lens: 'AL6');
      if (dB200 > 5.90) {
        c.hold(
          id: 'AL6-partial-over-capture',
          lens: 'AL6',
          severity: 'P0',
          title: 'Parcial 200% creditou buyer acima da captura',
          actor: 'buyer JWT process_partial',
          pre: 'oferta seller 200%',
          repro: 'rpc batata_process_partial_refund_dispute',
          expected: 'clamp 100% + recusa Stripe full / Δ≤ captura-comissao',
          obtained: {'dB': dB200, 'dS': dS200, 'rpc': part200.brief},
        );
      }

      // se 200% falhou, oferta 40%
      final rowAfter200 = await c.orderRow(paidD.oid);
      final alreadyRefunded = rowAfter200?['wallet_refund_processed_at'] != null;
      if (!alreadyRefunded) {
        final offer40 = await c.rest(
          'PATCH',
          'order_disputes?order_id=eq.${paidD.oid}',
          jwt: c.sellerJwt,
          body: {
            'seller_offer_type': 'partial_refund',
            'seller_refund_percent': 40,
          },
        );
        c.note('al3.offer.40', 'oferta 40%', offer40.brief, lens: 'AL3');
        final part40 = await c.rpc('batata_process_partial_refund_dispute', {
          'p_order_id': paidD.oid,
          'p_refund_percent': 40,
        }, jwt: c.buyerJwt);
        c.note('al3.partial.40', 'process_partial 40%', part40.brief, lens: 'AL3');
        final w40 = await c.wallets();
        final dB = (w40['buyer'] ?? 0) - (wBeforeDisp['buyer'] ?? 0);
        final dS = (w40['seller'] ?? 0) - (wBeforeDisp['seller'] ?? 0);
        final tx = await c.walletTxns(orderId: paidD.oid);
        c.note('al3.partial.40.books', 'livros 40%', {
          'dB': dB,
          'dS': dS,
          'sum': dB + dS,
          'tx': tx,
          'rpc': part40.brief,
        }, lens: 'AL3');

        // refund-order depois do parcial (AL7)
        final refAfterPart = await c.refund(paidD.oid);
        c.note('al7.refund.after-partial', 'refund-order pós-parcial',
            refAfterPart.brief, lens: 'AL7');
        final rowA = await c.orderRow(paidD.oid);
        final wA = await c.wallets();
        final dB2 = (wA['buyer'] ?? 0) - (wBeforeDisp['buyer'] ?? 0);
        if (refAfterPart.ok &&
            refAfterPart.map?['ok'] == true &&
            dB2 > 0.05 &&
            (numOf(refAfterPart.map?['amount_cents']) ?? 0) >= 590) {
          c.hold(
            id: 'AL7-partial-plus-full-stripe',
            lens: 'AL7',
            severity: 'P0',
            title: 'Parcial wallet + refund Stripe da captura completa',
            actor: 'buyer process_partial + seller refund-order',
            pre: '40% wallet já mintado',
            repro: 'POST refund-order após parcial',
            expected: '403 concluido ou residual Stripe só',
            obtained: {
              'refund': refAfterPart.brief,
              'dBuyer': dB2,
              'stripe_refund': rowA?['stripe_refund_id'],
            },
          );
        } else {
          c.block('AL7-part-ref', 'AL7', 'refund pós-parcial não duplicou captura',
              refAfterPart);
        }

        // buyer2 process_partial
        final partB2 = await c.rpc('batata_process_partial_refund_dispute', {
          'p_order_id': paidD.oid,
          'p_refund_percent': 40,
        }, jwt: c.buyer2Jwt);
        c.note('al6.partial.b2', 'buyer2 process_partial', partB2.brief,
            lens: 'AL6');
        if (partB2.ok && '${partB2.body}' == 'true') {
          c.hold(
            id: 'AL6-b2-partial-foreign',
            lens: 'AL6',
            severity: 'P0',
            title: 'Buyer2 executou parcial de encomenda alheia',
            actor: 'buyer2 JWT',
            pre: 'disputa de B1',
            repro: 'rpc process_partial',
            expected: '42501 not_allowed',
            obtained: partB2.brief,
          );
        } else {
          c.block('AL6-part-b2', 'AL6', 'buyer2 parcial recusado', partB2);
        }
      }

      // release depois de disputa
      final relAfter = await c.rpc(
        'batata_release_seller_wallet_for_order',
        {'p_order_id': paidD.oid},
        jwt: c.buyerJwt,
      );
      c.note('al3.release.after-disp', 'release com disputa aberta',
          relAfter.brief, lens: 'AL3');
    } else {
      c.skip('AL3-disp', 'AL3', 'INSERT disputa falhou', disp);
    }
  }

  // ---------------------------------------------------------------------------
  // AL3/AL4 — race refund-order ∥ concluido+release
  // ---------------------------------------------------------------------------
  final wRace0 = await c.wallets();
  final paidR = await c.payToPago(lens: 'AL7');
  if (paidR != null) {
    await c.markMao(paidR.oid);
    final race = await Future.wait([
      c.refund(paidR.oid),
      c.rest('PATCH', 'orders?id=eq.${paidR.oid}', jwt: c.buyerJwt, body: {
        'status': 'concluido',
      }),
    ]);
    final relR = await c.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': paidR.oid},
      jwt: c.buyerJwt,
    );
    final rowR = await c.orderRow(paidR.oid);
    final wRace = await c.wallets();
    final txR = await c.walletTxns(orderId: paidR.oid);
    c.note('al7.race', 'refund ∥ concluido + release', {
      'refund': race[0].brief,
      'concluido': race[1].brief,
      'release': relR.brief,
      'order': rowR,
      'dB': (wRace['buyer'] ?? 0) - (wRace0['buyer'] ?? 0),
      'dS': (wRace['seller'] ?? 0) - (wRace0['seller'] ?? 0),
      'tx': txR,
    }, lens: 'AL7');
    final dB = (wRace['buyer'] ?? 0) - (wRace0['buyer'] ?? 0);
    final dS = (wRace['seller'] ?? 0) - (wRace0['seller'] ?? 0);
    final hasStripeRf =
        rowR?['stripe_refund_id'] != null && '${rowR?['stripe_refund_id']}'.isNotEmpty;
    if (dS > 0.05 && dB > 0.05) {
      c.hold(
        id: 'AL7-race-double-credit',
        lens: 'AL7',
        severity: 'P0',
        title: 'Race refund∥release creditou buyer e seller',
        actor: 'seller refund-order ∥ buyer concluido',
        pre: 'order pago',
        repro: 'Future.wait refund + PATCH concluido + release',
        expected: 'um lado só',
        obtained: {'dB': dB, 'dS': dS, 'refund': hasStripeRf, 'row': rowR},
      );
    } else if (dS > 0.05 && hasStripeRf) {
      c.hold(
        id: 'AL7-race-release-plus-stripe-refund',
        lens: 'AL7',
        severity: 'P0',
        title: 'Race: seller creditado e PI reembolsado',
        actor: 'seller+buyer',
        pre: 'pago',
        repro: 'refund ∥ release',
        expected: 'release false se refund ganhou',
        obtained: {'dS': dS, 'refund': rowR?['stripe_refund_id']},
      );
    } else {
      c.block('AL7-race', 'AL7', 'race sem crédito duplo', {
        'dB': dB,
        'dS': dS,
        'rf': hasStripeRf,
        'st': rowR?['status'],
      });
    }
  }

  // ---------------------------------------------------------------------------
  // AL5 — chat card cancel sem refund Stripe
  // ---------------------------------------------------------------------------
  final paidC = await c.payToPago(lens: 'AL5');
  if (paidC != null) {
    final chatId = await c.ensureChat(paidC.pid);
    c.note('al5.chat', 'chat fixture', chatId, lens: 'AL5');
    if (chatId != null) {
      final card = await c.rest('POST', 'chat_messages', jwt: c.sellerJwt, body: {
        'chat_id': chatId,
        'sender_id': c.sellerId,
        'receiver_id': c.buyerId,
        'text':
            'FLEABER_JSON_V1:{"kind":"cancel_request_outcome","order_id":"${paidC.oid}","outcome":"accepted","status":"cancelado"}',
      });
      c.note('al5.chat.cancel', 'INSERT cancel_request_outcome', card.brief,
          lens: 'AL5');
      final rowC = await c.orderRow(paidC.oid);
      if (rowC?['status'] == 'cancelado' &&
          (rowC?['stripe_refund_id'] == null ||
              '${rowC?['stripe_refund_id']}'.isEmpty)) {
        c.hold(
          id: 'AL5-chat-cancel-no-stripe',
          lens: 'AL5',
          severity: 'P1',
          title: 'Card chat cancelou venda paga sem refund Stripe',
          actor: 'seller JWT chat_messages',
          pre: 'order pago',
          repro: 'INSERT FLEABER_JSON_V1 cancel_request_outcome',
          expected: 'chat_system_card_cancel_not_refunded',
          obtained: rowC,
        );
      } else {
        c.block('AL5-chat-can', 'AL5', 'card cancel não anulou PI', card);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // AL5 — PATCH cancelado 200: o status mudou?
  // ---------------------------------------------------------------------------
  final paidK = await c.payToPago(lens: 'AL5');
  if (paidK != null) {
    await c.markMao(paidK.oid);
    await c.rest('PATCH', 'orders?id=eq.${paidK.oid}', jwt: c.buyerJwt, body: {
      'status': 'concluido',
    });
    final can = await c.rest(
      'PATCH',
      'orders?id=eq.${paidK.oid}',
      jwt: c.buyerJwt,
      body: {'status': 'cancelado'},
    );
    final rowK = await c.orderRow(paidK.oid);
    c.note('al5.cancel.200', 'PATCH cancelado pós-concluido', {
      'hit': can.brief,
      'status': rowK?['status'],
      'bodyStatus': can.map?['status'],
    }, lens: 'AL5');
    if (rowK?['status'] == 'cancelado') {
      c.hold(
        id: 'AL5-buyer-cancel-concluido',
        lens: 'AL5',
        severity: 'P0',
        title: 'Buyer cancelou encomenda já concluída',
        actor: 'buyer JWT',
        pre: 'concluido',
        repro: 'PATCH status=cancelado',
        expected: 'status permanece concluido',
        obtained: rowK?['status'],
      );
    } else if (can.ok && rowK?['status'] == 'concluido') {
      c.hold(
        id: 'AL5-cancel-silent-200',
        lens: 'AL5',
        severity: 'P2',
        title: 'PATCH cancelado devolve 200 mas o estado não muda',
        actor: 'buyer JWT',
        pre: 'concluido pós-AEAFAG',
        repro: 'PATCH orders status=cancelado',
        expected: '403/200 com 0 rows, ou 200 só se mudou',
        obtained: {
          'http': can.status,
          'rows': can.list.length,
          'status': rowK?['status'],
        },
      );
    } else {
      c.block('AL5-can-200', 'AL5', 'cancelado não passou', can);
    }
  }

  // ---------------------------------------------------------------------------
  // AL1 — amount enorme / string científica
  // ---------------------------------------------------------------------------
  final huge = await c.payout(
    amountCents: 2147483647,
    key: '${prefix}_huge',
  );
  c.note('al1.huge', 'payout maxint', huge.brief, lens: 'AL1');
  if (huge.ok && huge.map?['success'] == true) {
    c.hold(
      id: 'AL1-payout-maxint',
      lens: 'AL1',
      severity: 'P0',
      title: 'Payout de 2147483647 cêntimos',
      actor: 'seller JWT',
      pre: 'saldo ~18€',
      repro: 'POST create-connect-account amount=2147483647',
      expected: 'insufficient_balance',
      obtained: huge.brief,
    );
  } else {
    c.block('AL1-huge', 'AL1', 'maxint recusado', huge);
  }

  final sci = await c.edge('create-connect-account', {
    'amount': '1e2',
    'idempotency_key': '${prefix}_sci',
  }, jwt: c.sellerJwt);
  c.note('al1.sci', 'amount 1e2', sci.brief, lens: 'AL1');

  final wEnd = await c.wallets();
  c.note('p2.final', 'saldos', {
    'start': w0,
    'end': wEnd,
    'dB': (wEnd['buyer'] ?? 0) - (w0['buyer'] ?? 0),
    'dS': (wEnd['seller'] ?? 0) - (w0['seller'] ?? 0),
  }, lens: 'AL7');

  await c.dumpAll('pass2.json');
  stdout.writeln(
      'DONE2 findings=${c.findings.length} blocked=${c.blocked.length}');
}
