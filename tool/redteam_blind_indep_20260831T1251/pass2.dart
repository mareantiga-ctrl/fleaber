/// Pass 2 — POÇO 2 pós-caixa + captura TEST. Sem correções.
import 'dart:io';
import '_rt.dart';

Future<void> main() async {
  final c = Rti4(loadEnv());
  await c.boot();

  // ---- Captura TEST via e2e fixture (sk_test + pm_card_visa na Edge) ----
  Map<String, dynamic>? paid;
  if ((c.e2eSecret ?? '').length >= 16) {
    final setup = await c.e2e('setup_paid_order', {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'initial_qty': 2,
    });
    c.note('p2.setup_paid', 'e2e setup_paid_order', clip(setup.body, 600), well: '2');
    paid = setup.map;
    var oid = '${paid?['order_id'] ?? ''}';
    var pid = '${paid?['product_id'] ?? ''}';
    if (oid.isEmpty && paid?['order'] is Map) {
      oid = '${(paid!['order'] as Map)['id'] ?? ''}';
    }
    if (pid.isEmpty && paid?['product'] is Map) {
      pid = '${(paid!['product'] as Map)['id'] ?? ''}';
    }
    if (oid.isNotEmpty) c.createdOrderIds.add(oid);
    if (pid.isNotEmpty) c.createdProductIds.add(pid);

    if (oid.isEmpty) {
      c.note('p2.setup_paid.empty', 'sem order_id', paid, well: '2');
    } else {
      final before = await c.getOne(
        'orders',
        oid,
        select:
            'id,status,amount_paid_cents,stripe_payment_intent_id,wallet_release_processed_at,payment_method,shipping_method,buyer_id,seller_id,product_id,quantity',
      );
      c.note('p2.paid.row', 'order after setup', before, well: '2');
      final captured = '${before?['status']}'.toLowerCase() == 'pago' &&
          (before?['amount_paid_cents'] ?? 0) > 0;
      if (!captured) {
        c.note('p2.paid.not.captured', 'setup não deixou pago+cents', before, well: '2');
      }

      // Buyer jump pago → concluido (carrier default)
      final jump = await c.rest(
        'PATCH',
        'orders?id=eq.$oid',
        token: c.buyerJwt,
        body: {'status': 'concluido'},
      );
      final afterJump = await c.getOne(
        'orders',
        oid,
        select: 'id,status,wallet_release_processed_at,amount_paid_cents',
      );
      c.note('p2.buyer.concluido', 'buyer pago→concluido', {
        'http': jump.status,
        'after': afterJump,
      }, well: '2');
      if ('${afterJump?['status']}'.toLowerCase() == 'concluido' &&
          '${before?['status']}'.toLowerCase() == 'pago') {
        c.finding(
          id: 'P2-BUYER-CONCLUIDO-CARRIER',
          title: 'Buyer salta pago→concluido sem enviado (não mão)',
          actor: 'buyer JWT',
          sev: 'P1',
          well: '2',
          pre: 'order pago captura TEST',
          request: 'PATCH status=concluido',
          before: before,
          after: afterJump,
          impact: 'Confirmação precoce; possível release',
          repro: 'PATCH orders concluido from pago',
        );
      } else {
        c.hold('p2.buyer.concluido', 'buyer não concluiu desde pago', afterJump, well: '2');
      }

      // Buyer entregue from pago
      final ent = await c.rest(
        'PATCH',
        'orders?id=eq.$oid',
        token: c.buyerJwt,
        body: {'status': 'entregue'},
      );
      final afterEnt = await c.getOne('orders', oid, select: 'id,status');
      c.note('p2.buyer.entregue', 'buyer pago→entregue', {
        'http': ent.status,
        'after': afterEnt,
      }, well: '2');
      if ('${afterEnt?['status']}'.toLowerCase() == 'entregue' &&
          '${before?['status']}'.toLowerCase() == 'pago') {
        c.finding(
          id: 'P2-BUYER-ENTREGUE-SKIP-SHIP',
          title: 'Buyer marca entregue a partir de pago (sem enviado)',
          actor: 'buyer JWT',
          sev: 'P1',
          well: '2',
          pre: 'pago',
          request: 'PATCH entregue',
          before: before,
          after: afterEnt,
          impact: 'Salto de estado logístico',
          repro: 'PATCH entregue from pago',
        );
      } else {
        c.hold('p2.buyer.entregue', 'entregue desde pago bloqueado', afterEnt, well: '2');
      }

      // Buyer marks enviado
      final envio = await c.rest(
        'PATCH',
        'orders?id=eq.$oid',
        token: c.buyerJwt,
        body: {'status': 'enviado'},
      );
      final afterEnv = await c.getOne('orders', oid, select: 'id,status');
      c.note('p2.buyer.enviado', 'buyer marca enviado', {
        'http': envio.status,
        'after': afterEnv,
      }, well: '2');
      if ('${afterEnv?['status']}'.toLowerCase() == 'enviado' &&
          '${before?['buyer_id']}' == c.buyerId) {
        c.finding(
          id: 'P2-BUYER-ENVIA',
          title: 'Buyer marca enviado (papel vendedor)',
          actor: 'buyer JWT',
          sev: 'P1',
          well: '2',
          pre: 'order pago',
          request: 'PATCH enviado',
          before: before,
          after: afterEnv,
          impact: 'Autoridade de envio usurpada',
          repro: 'PATCH enviado as buyer',
        );
      } else {
        c.hold('p2.buyer.enviado', 'buyer não marca enviado', afterEnv, well: '2');
      }

      // Seller marks concluido
      final sCon = await c.rest(
        'PATCH',
        'orders?id=eq.$oid',
        token: c.sellerJwt,
        body: {'status': 'concluido'},
      );
      final afterS = await c.getOne('orders', oid, select: 'id,status');
      c.note('p2.seller.concluido', 'seller→concluido', {
        'http': sCon.status,
        'after': afterS,
      }, well: '2');
      if ('${afterS?['status']}'.toLowerCase() == 'concluido' &&
          '${before?['status']}'.toLowerCase() != 'concluido') {
        c.finding(
          id: 'P2-SELLER-CONCLUIDO',
          title: 'Seller marca concluido (confirmação do comprador)',
          actor: 'seller JWT',
          sev: 'P1',
          well: '2',
          pre: 'order pago',
          request: 'PATCH concluido as seller',
          before: before,
          after: afterS,
          impact: 'Fecha ciclo e pode libertar fundos sem o buyer',
          repro: 'PATCH concluido as seller',
        );
      } else {
        c.hold('p2.seller.concluido', 'seller não conclui', afterS, well: '2');
      }

      // JWT wallet_release flag
      final rel = await c.rest(
        'PATCH',
        'orders?id=eq.$oid',
        token: c.buyerJwt,
        body: {'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String()},
      );
      final afterRel = await c.getOne(
        'orders',
        oid,
        select: 'id,status,wallet_release_processed_at',
      );
      c.note('p2.jwt.release.flag', 'PATCH wallet_release_processed_at', {
        'http': rel.status,
        'after': afterRel,
      }, well: '2');
      if (afterRel?['wallet_release_processed_at'] != null &&
          before?['wallet_release_processed_at'] == null) {
        c.finding(
          id: 'P2-JWT-RELEASE-FLAG',
          title: 'JWT grava wallet_release_processed_at',
          actor: 'buyer JWT',
          sev: 'P1',
          well: '2',
          pre: 'flag null',
          request: 'PATCH wallet_release_processed_at',
          before: before,
          after: afterRel,
          impact: 'Bloqueia refund/release real ou finge payout',
          repro: 'PATCH wallet_release_processed_at',
        );
      } else {
        c.hold('p2.jwt.release.flag', 'flag release imutável', afterRel, well: '2');
      }

      // JWT amount / PI
      final money = await c.rest(
        'PATCH',
        'orders?id=eq.$oid',
        token: c.buyerJwt,
        body: {
          'amount_paid_cents': 1,
          'stripe_payment_intent_id': 'pi_fake_rti4',
        },
      );
      final afterMoney = await c.getOne(
        'orders',
        oid,
        select: 'id,amount_paid_cents,stripe_payment_intent_id',
      );
      c.note('p2.jwt.money', 'PATCH money cols', {
        'http': money.status,
        'after': afterMoney,
      }, well: '2');
      if ((afterMoney?['amount_paid_cents'] ?? before?['amount_paid_cents']) !=
              before?['amount_paid_cents'] ||
          '${afterMoney?['stripe_payment_intent_id']}' == 'pi_fake_rti4') {
        c.finding(
          id: 'P2-JWT-MONEY-MUT',
          title: 'JWT muta amount_paid_cents ou PI',
          actor: 'buyer JWT',
          sev: 'P0',
          well: '2',
          pre: 'order pago',
          request: 'PATCH amount_paid_cents/PI',
          before: before,
          after: afterMoney,
          impact: 'Contrato financeiro mutável pelo cliente',
          repro: 'PATCH amount_paid_cents',
        );
      } else {
        c.hold('p2.jwt.money', 'money cols imutáveis', afterMoney, well: '2');
      }

      // Seller ship
      final ship = await c.rest(
        'PATCH',
        'orders?id=eq.$oid',
        token: c.sellerJwt,
        body: {'status': 'enviado'},
      );
      final afterShip = await c.getOne('orders', oid, select: 'id,status');
      c.note('p2.seller.ship', 'seller enviado', {
        'http': ship.status,
        'after': afterShip,
      }, well: '2');

      // Refund as buyer
      final rfB = await c.edge('refund-order', {'order_id': oid}, token: c.buyerJwt);
      c.note('p2.refund.buyer', 'refund as buyer', rfB.brief, well: '2');
      if (rfB.ok && rfB.map?['ok'] == true && rfB.map?['skipped'] != true) {
        c.finding(
          id: 'P2-REFUND-BUYER',
          title: 'Buyer executa refund-order (seller-only)',
          actor: 'buyer JWT',
          sev: 'P1',
          well: '2',
          pre: 'order pago',
          request: 'POST refund-order',
          before: before,
          after: rfB.brief,
          impact: 'Reembolso sem autoridade do vendedor',
          repro: 'POST refund-order as buyer',
        );
      } else {
        c.hold('p2.refund.buyer', 'buyer refund negado ou skipped', rfB.brief, well: '2');
      }

      // Cross-user refund (fresh)
      if (c.freshJwt != null) {
        final rfF = await c.edge('refund-order', {'order_id': oid}, token: c.freshJwt);
        c.note('p2.refund.fresh', 'refund fresh JWT', rfF.brief, well: '2');
        if (rfF.ok && rfF.map?['ok'] == true && rfF.map?['skipped'] != true) {
          c.finding(
            id: 'P2-REFUND-CROSS',
            title: 'JWT alheio reembolsa order',
            actor: 'fresh JWT',
            sev: 'P0',
            well: '2',
            pre: 'order de outro buyer',
            request: 'POST refund-order',
            before: before,
            after: rfF.brief,
            impact: 'Cross-user financeiro',
            repro: 'POST refund-order as other user',
          );
        } else {
          c.hold('p2.refund.fresh', 'fresh refund negado', rfF.brief, well: '2');
        }
      }

      // Review on pago (not concluido)
      final rev = await c.rest(
        'POST',
        'reviews',
        token: c.buyerJwt,
        body: {
          'order_id': oid,
          'buyer_id': c.buyerId,
          'target_id': c.sellerId,
          'stars': 5,
          'comment': '$prefix review pago',
          'author_role': 'comprador',
        },
      );
      c.note('p2.review.pago', 'review while pago', rev.brief, well: '2');
      if (rev.ok && (rev.list.isNotEmpty || rev.map?['id'] != null)) {
        c.finding(
          id: 'P2-REVIEW-PAGO',
          title: 'Review em order pago (não concluido)',
          actor: 'buyer JWT',
          sev: 'P1',
          well: '2',
          pre: 'status pago/enviado ≠ concluido',
          request: 'POST reviews',
          before: afterShip,
          after: rev.brief,
          impact: 'Reputação sem ciclo fechado',
          repro: 'POST reviews on pago',
        );
      } else {
        c.hold('p2.review.pago', 'review pago bloqueada', rev.brief, well: '2');
      }

      // Dispute as fresh
      if (c.freshJwt != null) {
        final disp = await c.rest(
          'POST',
          'order_disputes',
          token: c.freshJwt,
          body: {
            'order_id': oid,
            'buyer_id': c.freshId,
            'reason': '$prefix hijack dispute',
            'status': 'aberta',
          },
        );
        c.note('p2.dispute.fresh', 'dispute as other', disp.brief, well: '2');
        if (disp.ok && (disp.list.isNotEmpty || disp.map?['id'] != null)) {
          c.finding(
            id: 'P2-DISPUTE-CROSS',
            title: 'JWT alheio abre disputa noutro pedido',
            actor: 'fresh JWT',
            sev: 'P1',
            well: '2',
            pre: 'order de outro buyer',
            request: 'POST order_disputes',
            before: null,
            after: disp.brief,
            impact: 'Autoridade de disputa usurpada',
            repro: 'POST order_disputes as other',
          );
        } else {
          c.hold('p2.dispute.fresh', 'dispute cross bloqueada', disp.brief, well: '2');
        }
      }

      // Dual GET settle
      final cs = '${before?['stripe_checkout_session_id'] ?? paid?['session_id'] ?? ''}';
      final pi = '${before?['stripe_payment_intent_id'] ?? paid?['payment_intent_id'] ?? ''}';
      if (cs.startsWith('cs_')) {
        final g1 = await c.call(
          'GET',
          '/functions/v1/create-payment-intent?session_id=$cs&checkout_return=success',
        );
        final g2 = await c.call(
          'GET',
          '/functions/v1/create-payment-intent?session_id=$cs&checkout_return=success',
        );
        c.note('p2.settle.dual', 'dual GET settle', {
          'g1': g1.brief,
          'g2': g2.brief,
        }, well: '2');
      }
      if (pi.startsWith('pi_')) {
        final fakeCs = 'cs_test_rti4_not_a_session';
        final gFake = await c.call(
          'GET',
          '/functions/v1/create-payment-intent?session_id=$fakeCs&checkout_return=success',
        );
        c.note('p2.settle.fake.cs', 'GET settle fake cs', gFake.brief, well: '2');
      }
    }
  } else {
    c.note('p2.e2e.missing', 'sem FLEABER_STAGING_CRASH_INJECT_SECRET — lacuna captura',
        null, well: '2');
  }

  // ---- Buyer JWT cria Session em listed e tenta settle unpaid ----
  final p = await c.insertProduct(listed: true, sold: false, title: '$prefix-PAY', qty: 1);
  if (p != null) {
    final o = await c.insertOrder(
      token: c.buyerJwt,
      productId: p['id'].toString(),
      shipping: 'carrier',
    );
    if (o.ok) {
      final oid = c.orderIdOf(o);
      if (oid != null) {
        final chk = await c.checkout(
          token: c.buyerJwt,
          orderId: oid,
          productId: p['id'].toString(),
        );
        c.note('p2.session.create', 'Session listed', clip(chk.body, 500), well: '2');
        final url = '${chk.map?['checkoutUrl'] ?? chk.map?['url'] ?? ''}';
        final cs = '${chk.map?['session_id'] ?? chk.map?['sessionId'] ?? ''}';
        // Unlist then GET settle unpaid
        await c.rest(
          'PATCH',
          'products?id=eq.${p['id']}',
          token: c.sellerJwt,
          body: {'list_on_marketplace': false},
        );
        if (cs.startsWith('cs_') || url.contains('cs_')) {
          final sid = cs.startsWith('cs_')
              ? cs
              : RegExp(r'cs_(test|live)_[A-Za-z0-9]+').firstMatch(url)?.group(0) ?? '';
          if (sid.startsWith('cs_')) {
            final settle = await c.call(
              'GET',
              '/functions/v1/create-payment-intent?session_id=$sid&checkout_return=success',
            );
            final after = await c.getOne('orders', oid, select: 'id,status,amount_paid_cents');
            c.note('p2.settle.unpaid.unlist', 'GET settle unpaid after unlist', {
              'http': settle.status,
              'loc': settle.location,
              'order': after,
            }, well: '2');
            if ('${after?['status']}'.toLowerCase() == 'pago') {
              c.finding(
                id: 'P2-SETTLE-UNPAID-UNLIST',
                title: 'GET settle marca pago em Session não paga após unlist',
                actor: 'anon GET',
                sev: 'P0',
                well: '2',
                pre: 'Session criada; unlist; sem captura Stripe',
                request: 'GET create-payment-intent?session_id&checkout_return=success',
                before: chk.brief,
                after: after,
                impact: 'Falsificação de pagamento via settle',
                repro: 'GET settle unpaid cs after unlist',
              );
            } else {
              c.hold('p2.settle.unpaid', 'GET settle unpaid ≠ pago', after, well: '2');
            }
          }
        }

        // Hostil amount no Edge
        final o2 = await c.insertOrder(
          token: c.buyerJwt,
          productId: p['id'].toString(),
          price: 4.5,
        );
        if (c.orderIdOf(o2) != null) {
          final hostile = await c.checkout(
            token: c.buyerJwt,
            orderId: c.orderIdOf(o2)!,
            extra: {
              'amount': 50,
              'item_price': 0.5,
              'quantity': 99,
              'buyer_id': c.sellerId,
            },
          );
          c.note('p2.edge.hostile', 'Edge amount/qty/buyer mutation', clip(hostile.body, 400),
              well: '2');
        }
      }
    }
  }

  // Hand shipping concluido from pago (segunda captura)
  if ((c.e2eSecret ?? '').length >= 16) {
    final setup2 = await c.e2e('setup_paid_order', {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'initial_qty': 1,
    });
    final oid2 = '${setup2.map?['order_id'] ?? ''}';
    if (oid2.isNotEmpty) {
      c.createdOrderIds.add(oid2);
      await c.rest(
        'PATCH',
        'orders?id=eq.$oid2',
        service: true,
        body: {'shipping_method': 'hand'},
      );
      final h = await c.rest(
        'PATCH',
        'orders?id=eq.$oid2',
        token: c.buyerJwt,
        body: {'status': 'concluido'},
      );
      final afterH = await c.getOne(
        'orders',
        oid2,
        select: 'id,status,wallet_release_processed_at,shipping_method',
      );
      c.note('p2.hand.concluido', 'mão pago→concluido', {
        'http': h.status,
        'after': afterH,
      }, well: '2');
      // wallet delta
      final wB = await c.getOne('wallets', c.sellerId, select: 'id,balance');
      c.note('p2.wallet.seller', 'seller wallet after hand concluido', wB, well: '2');
    }
  }

  await c.dump('pass2');
  stdout.writeln('pass2 done findings=${c.findings.length} holds=${c.holds.length}');
}
