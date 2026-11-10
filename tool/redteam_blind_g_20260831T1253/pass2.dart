/// PASS 2 — G1 double-submit + G2 races reais (Future.wait, não sequencial).
import 'dart:io';
import '_rtg.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rtg.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();

  final out = <String, Object?>{'pass': 2, 'prefix': prefix};
  final w0 = await c.wallets();
  out['wallets_before'] = w0;

  final stale = await c.orderRow('5c513bab-f308-47d8-8047-93b1356cd386');
  c.note('p2.observe.stale_order', 'order after pass1 PATCH storm', stale,
      lens: 'G6');
  if (stale != null &&
      '${stale['status']}'.toLowerCase() != 'cancelado' &&
      '${stale['status']}'.toLowerCase() != 'cancelled') {
    // seller could not cancel; buyer PATCH 200 — record if status drifted
    c.note('p2.observe.stale_status', 'status actual', stale['status'],
        lens: 'G6');
  }

  // ========== RACE 1: G1 two POST create-payment-intent same order ==========
  final p1 = await c.insertProduct(title: '$prefix race-co', qty: 2);
  final o1 = await c.insertOrder(productId: p1!, jwt: c.buyerJwt);
  final bodyCo = {
    'order_id': o1,
    'buyer_id': c.buyerId,
    'shipping_method': 'entrega em mão',
  };
  final rCo = await parallel([
    c.edge('create-payment-intent', bodyCo, jwt: c.buyerJwt),
    c.edge('create-payment-intent', bodyCo, jwt: c.buyerJwt),
  ]);
  c.note('p2.g1.pay_parallel', '2× create-payment-intent', {
    'a': rCo[0].brief,
    'b': rCo[1].brief,
  }, lens: 'G1');
  String? urlOf(HttpHit h) {
    final m = h.map;
    return (m?['url'] ??
            m?['checkoutUrl'] ??
            m?['checkout_url'] ??
            m?['session_id'] ??
            m?['id'])
        ?.toString();
  }

  int? centsOf(HttpHit h) {
    final m = h.map;
    final v = m?['server_amount_cents'] ?? m?['amount_cents'] ?? m?['amountCents'];
    if (v is num) return v.round();
    return int.tryParse('$v');
  }

  final urls = [urlOf(rCo[0]), urlOf(rCo[1])].whereType<String>().toSet();
  final bothOk = rCo.every((h) => h.ok);
  c.note('p2.g1.pay_cents', 'session urls/cents', {
    'urls': urls.length,
    'cents': [centsOf(rCo[0]), centsOf(rCo[1])],
  }, lens: 'G1');
  if (bothOk && urls.length >= 2) {
    c.hold(
      id: 'RTG-G1-001',
      lens: 'G1',
      severity: 'P1',
      title: 'Dois POST create-payment-intent em paralelo geram duas Sessions',
      actor: 'buyer JWT ×2 paralelo',
      pre: 'uma order reserva_pendente',
      repro: 'Future.wait 2× POST create-payment-intent',
      expected: '1 Session / 2.ª recusada',
      obtained: {'a': rCo[0].brief, 'b': rCo[1].brief, 'distinct': urls.length},
      evidence: {'order_id': o1, 'product_id': p1},
    );
  }

  // ========== RACE 2: G2 two buyers last unit ==========
  final pLast = await c.insertProduct(title: '$prefix last-unit', qty: 1);
  final rLast = await parallel([
    c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pLast,
      'price_total': 8.5,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    }),
    c.rest('POST', 'orders', jwt: c.buyer2Jwt, body: {
      'buyer_id': c.buyer2Id,
      'seller_id': c.sellerId,
      'product_id': pLast,
      'price_total': 8.5,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    }),
  ]);
  for (final h in rLast) {
    if (h.firstId != null) c.createdOrderIds.add(h.firstId!);
  }
  final holds = await c.rest(
    'GET',
    'orders?product_id=eq.$pLast&select=id,status,buyer_id,quantity&status=in.(reserva_pendente,reservado,pendente,aguarda_confirmacao,pago)',
    service: true,
  );
  final holdCount = holds.list.length;
  c.note('p2.g2.last_unit', '2 buyers qty=1', {
    'b1': rLast[0].brief,
    'b2': rLast[1].brief,
    'active_holds': holdCount,
  }, lens: 'G2');
  if (holdCount >= 2) {
    c.hold(
      id: 'RTG-G2-001',
      lens: 'G2',
      severity: 'P1',
      title: 'Dois compradores em paralelo criam hold no último stock (qty=1)',
      actor: 'buyer JWT ∥ buyer2 JWT',
      pre: 'produto quantity=1 listed',
      repro: 'Future.wait 2× POST orders',
      expected: '1 hold; 2.º order_hold_exceeds_stock',
      obtained: holds.list,
      evidence: {
        'product': await c.productRow(pLast!),
        'http': [rLast[0].status, rLast[1].status],
      },
    );
  }

  // ========== RACE 3: G2 checkout ∥ unlist ==========
  final pUn = await c.insertProduct(title: '$prefix unlist-race', qty: 1);
  final oUn = await c.insertOrder(productId: pUn!, jwt: c.buyerJwt);
  final rUn = await parallel([
    c.edge('create-payment-intent', {
      'order_id': oUn,
      'buyer_id': c.buyerId,
      'shipping_method': 'entrega em mão',
    }, jwt: c.buyerJwt),
    c.rest('PATCH', 'products?id=eq.$pUn', jwt: c.sellerJwt, body: {
      'list_on_marketplace': false,
    }),
  ]);
  c.note('p2.g2.checkout_unlist', 'pay ∥ unlist', {
    'pay': rUn[0].brief,
    'unlist': rUn[1].brief,
    'product': await c.productRow(pUn),
  }, lens: 'G2');
  if (rUn[0].ok && (urlOf(rUn[0]) ?? '').isNotEmpty) {
    c.hold(
      id: 'RTG-G2-002',
      lens: 'G2',
      severity: 'P2',
      title: 'Checkout Session criada em corrida com unlist do SKU',
      actor: 'buyer Edge ∥ seller PATCH',
      pre: 'hold + listed; unlist no mesmo instante',
      repro: 'Future.wait create-payment-intent ∥ PATCH list_on_marketplace=false',
      expected: 'Session recusada se unlist ganhar; se Session nascer, captura deve refund',
      obtained: rUn[0].brief,
      proven: true,
      evidence: {
        'order': oUn,
        'product_after': await c.productRow(pUn),
        'note': 'Captura 4242 no pass3 se Session persistir',
      },
    );
  }

  // G6 stale price with server_amount_cents
  final pPx = await c.insertProduct(
    title: '$prefix stale-cents',
    qty: 2,
    price: 8.5,
  );
  final oPx = await c.insertOrder(productId: pPx!, jwt: c.buyerJwt, price: 8.5);
  await c.rest('PATCH', 'products?id=eq.$pPx', jwt: c.sellerJwt, body: {
    'price': 99.0,
  });
  final payPx = await c.edge('create-payment-intent', {
    'order_id': oPx,
    'buyer_id': c.buyerId,
    'shipping_method': 'entrega em mão',
  }, jwt: c.buyerJwt);
  final pxCents = centsOf(payPx);
  c.note('p2.g6.stale_price', 'checkout after 8.5→99', {
    'http': payPx.status,
    'cents': pxCents,
    'snip': payPx.brief,
  }, lens: 'G6');
  if (payPx.ok && pxCents != null && pxCents <= 1500) {
    c.hold(
      id: 'RTG-G6-003',
      lens: 'G6',
      severity: 'P1',
      title: 'Checkout cobra o preço selado 8,50€ depois do SKU ir a 99€',
      actor: 'buyer Edge após seller PATCH price',
      pre: 'order price_total=8.50; product.price=99',
      repro: 'POST create-payment-intent',
      expected: 'requote 99€ ou recusa',
      obtained: {'server_amount_cents': pxCents, 'body': payPx.brief},
    );
  }
  final pHu = await c.insertProduct(title: '$prefix hold-unlist', qty: 1);
  final rHu = await parallel([
    c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pHu,
      'price_total': 8.5,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'entrega em mão',
    }),
    c.rest('PATCH', 'products?id=eq.$pHu', jwt: c.sellerJwt, body: {
      'list_on_marketplace': false,
      'is_sold': true,
    }),
  ]);
  if (rHu[0].firstId != null) c.createdOrderIds.add(rHu[0].firstId!);
  c.note('p2.g2.hold_unlist', 'hold INSERT ∥ sold+unlist', {
    'hold': rHu[0].brief,
    'unlist': rHu[1].brief,
    'product': await c.productRow(pHu!),
    'order': rHu[0].firstId == null ? null : await c.orderRow(rHu[0].firstId!),
  }, lens: 'G2');
  if (rHu[0].ok && rHu[0].firstId != null) {
    final orow = await c.orderRow(rHu[0].firstId!);
    final pst = '${orow?['status']}'.toLowerCase();
    if (pst.contains('pendente') || pst.contains('reserv')) {
      c.hold(
        id: 'RTG-G2-003',
        lens: 'G2',
        severity: 'P1',
        title: 'Hold criado em corrida com unlist+sold do último SKU',
        actor: 'buyer POST ∥ seller PATCH',
        pre: 'qty=1 listed',
        repro: 'Future.wait POST orders ∥ PATCH is_sold+unlist',
        expected: 'hold recusado ou produto não sold com hold',
        obtained: {'order': orow, 'product': await c.productRow(pHu)},
      );
    }
  }

  // ========== RACE 5: G1 two accept same offer ==========
  final pOff = await c.insertProduct(title: '$prefix offer-race', qty: 2);
  final off = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': pOff,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': 6.0,
    'status': 'pending',
    'offered_by': 'buyer',
  });
  final offId = off.firstId;
  if (offId != null) {
    final rAcc = await parallel([
      c.rest('PATCH', 'product_offers?id=eq.$offId', jwt: c.sellerJwt, body: {
        'status': 'accepted',
      }),
      c.rest('PATCH', 'product_offers?id=eq.$offId', jwt: c.sellerJwt, body: {
        'status': 'accepted',
      }),
    ]);
    c.note('p2.g1.offer_acc', '2× accept offer', {
      'a': rAcc[0].brief,
      'b': rAcc[1].brief,
    }, lens: 'G1');
  }

  // ========== RACE 6: G1 two wallet tips (if live required, record block) ==========
  final live = await c.insertLive(active: true);
  final rTip = await parallel([
    c.rpc('batata_send_live_tip_from_wallet', {
      'p_seller_id': c.sellerId,
      'p_amount': 1.0,
      'p_live_id': live,
    }, jwt: c.buyerJwt),
    c.rpc('batata_send_live_tip_from_wallet', {
      'p_seller_id': c.sellerId,
      'p_amount': 1.0,
      'p_live_id': live,
    }, jwt: c.buyerJwt),
  ]);
  c.note('p2.g1.tip_wallet', '2× tip wallet paralelo', {
    'a': rTip[0].brief,
    'b': rTip[1].brief,
    'wallets': await c.wallets(),
  }, lens: 'G1');
  await c.endLives();

  // ========== RACE 7: G2 accept offer ∥ expire cron ==========
  final pEx = await c.insertProduct(title: '$prefix offer-expire-race', qty: 1);
  final off2 = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': pEx,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': 4.0,
    'status': 'pending',
    'offered_by': 'buyer',
  });
  final off2Id = off2.firstId;
  if (off2Id != null) {
    await c.rest(
      'PATCH',
      'product_offers?id=eq.$off2Id',
      service: true,
      body: {
        'expires_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(seconds: 2))
            .toIso8601String(),
      },
    );
    final rEx = await parallel([
      c.rest('PATCH', 'product_offers?id=eq.$off2Id', jwt: c.sellerJwt, body: {
        'status': 'accepted',
      }),
      c.rpc('batata_expire_product_offers', {}, service: true),
    ]);
    final row = await c.rest(
      'GET',
      'product_offers?id=eq.$off2Id&select=id,status,expires_at,responded_at',
      service: true,
    );
    c.note('p2.g2.offer_expire', 'accept ∥ expire cron', {
      'accept': rEx[0].brief,
      'expire': rEx[1].brief,
      'row': row.map,
    }, lens: 'G2');
    if ('${row.map?['status']}'.toLowerCase() == 'accepted') {
      c.hold(
        id: 'RTG-G2-004',
        lens: 'G2',
        severity: 'P1',
        title: 'Accept em corrida com cron de expire deixa offer accepted após TTL',
        actor: 'seller PATCH ∥ service expire',
        pre: 'expires_at já no passado',
        repro: 'Future.wait accept ∥ batata_expire_product_offers',
        expected: 'expired',
        obtained: row.map,
      );
    }
  }

  // ========== RACE 8: G1 payout debit same key + different keys ==========
  final sameKey = '${prefix}_pay_same_key';
  final rPaySame = await parallel([
    c.rpc('batata_wallet_payout_debit', {
      'p_user_id': c.sellerId,
      'p_amount_cents': 100,
      'p_idempotency_key': sameKey,
    }, jwt: c.sellerJwt),
    c.rpc('batata_wallet_payout_debit', {
      'p_user_id': c.sellerId,
      'p_amount_cents': 100,
      'p_idempotency_key': sameKey,
    }, jwt: c.sellerJwt),
  ]);
  c.note('p2.g1.payout_same', 'payout same idempotency_key ∥', {
    'a': rPaySame[0].brief,
    'b': rPaySame[1].brief,
  }, lens: 'G1');
  final rPayDiff = await parallel([
    for (var i = 0; i < 2; i++)
      c.rpc('batata_wallet_payout_debit', {
        'p_user_id': c.sellerId,
        'p_amount_cents': 50,
        'p_idempotency_key': '${prefix}_pay_diff_$i',
      }, jwt: c.sellerJwt),
  ]);
  c.note('p2.g1.payout_diff', 'payout 2 keys distintas ∥', {
    'a': rPayDiff[0].brief,
    'b': rPayDiff[1].brief,
    'wallets': await c.wallets(),
  }, lens: 'G1');
  final debitHits = rPayDiff.where((h) {
    final m = h.map;
    return h.ok && m != null && m['ok'] == true && m['idempotent'] != true;
  }).length;
  if (debitHits >= 2) {
    c.hold(
      id: 'RTG-G1-002',
      lens: 'G1',
      severity: 'P0',
      title: 'Dois débitos de payout em paralelo com keys distintas',
      actor: 'seller JWT ×2',
      pre: 'wallet seller',
      repro: 'Future.wait 2× batata_wallet_payout_debit keys diferentes',
      expected: 'RPC recusada a JWT (só Edge) ou 1 débito',
      obtained: {
        'a': rPayDiff[0].brief,
        'b': rPayDiff[1].brief,
        'wallets': await c.wallets(),
      },
    );
  }

  // ========== RACE 9: G2 live reservation accept ∥ expire + bag remove ==========
  final live2 = await c.insertLive(active: false);
  final pLi = await c.insertProduct(
    title: '$prefix resv-race',
    qty: 1,
    live: true,
    listed: false,
  );
  final refCode = 'RTG-${stamp.substring(stamp.length - 4)}';
  final li = await c.rest('POST', 'live_items', service: true, body: {
    'live_id': live2,
    'product_id': pLi,
    'checkout_product_id': pLi,
    'seller_id': c.sellerId,
    'title': 'rtg item',
    'ref_code': refCode,
    'item_kind': 'marketplace',
    'quantity': 1,
    'is_active': true,
    'status': 'available',
    'price': 8.5,
  });
  final liveItemId = li.firstId;
  if (live2 != null && liveItemId != null) {
    final resv = await c.rest('POST', 'live_reservation_requests', jwt: c.buyerJwt, body: {
      'live_id': live2,
      'live_item_id': liveItemId,
      'seller_id': c.sellerId,
      'buyer_id': c.buyerId,
      'requested_qty': 1,
      'source': 'fleaber_live',
      'status': 'pending',
    });
    final rid = resv.firstId;
    if (rid != null) {
      final rRes = await parallel([
        c.rpc('batata_process_live_reservation_request', {
          'p_request_id': rid,
          'p_action': 'accept',
        }, jwt: c.sellerJwt),
        c.rpc('batata_live_bag_remove_request', {
          'p_request_id': rid,
        }, jwt: c.buyerJwt),
      ]);
      final row = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$rid&select=id,status,expires_at',
        service: true,
      );
      c.note('p2.g2.resv_acc_rm', 'accept ∥ bag_remove', {
        'accept': rRes[0].brief,
        'remove': rRes[1].brief,
        'row': row.map,
      }, lens: 'G2');

      // G5: expire then accept + stripe_convert (no TTL gate in RPC)
      final resv2 = await c.rest(
        'POST',
        'live_reservation_requests',
        jwt: c.buyerJwt,
        body: {
          'live_id': live2,
          'live_item_id': liveItemId,
          'seller_id': c.sellerId,
          'buyer_id': c.buyerId,
          'requested_qty': 1,
          'source': 'fleaber_live',
          'status': 'pending',
        },
      );
      final rid2 = resv2.firstId;
      if (rid2 != null) {
        await c.rest(
          'PATCH',
          'live_reservation_requests?id=eq.$rid2',
          service: true,
          body: {
            'expires_at': DateTime.now()
                .toUtc()
                .subtract(const Duration(minutes: 20))
                .toIso8601String(),
          },
        );
        final accExp = await c.rpc(
          'batata_process_live_reservation_request',
          {'p_request_id': rid2, 'p_action': 'accept'},
          jwt: c.sellerJwt,
        );
        final convExp = await c.rpc(
          'batata_live_reservation_stripe_convert',
          {'p_request_id': rid2},
          jwt: c.buyerJwt,
        );
        final convX = await c.rpc(
          'batata_live_reservation_stripe_convert',
          {'p_request_id': rid2},
          jwt: c.buyer2Jwt,
        );
        final row2 = await c.rest(
          'GET',
          'live_reservation_requests?id=eq.$rid2&select=id,status,expires_at,notes',
          service: true,
        );
        c.note('p2.g5.resv_ttl', 'accept+convert after expires_at', {
          'accept': accExp.brief,
          'convert_buyer': convExp.brief,
          'convert_b2': convX.brief,
          'row': row2.map,
        }, lens: 'G5');
        final rst = '${row2.map?['status']}'.toLowerCase();
        if (rst == 'accepted' || rst == 'converted') {
          c.hold(
            id: 'RTG-G5-002',
            lens: 'G5',
            severity: 'P1',
            title: 'Reserva live TTL ignorado: accept/convert após expires_at',
            actor: 'seller accept + buyer stripe_convert',
            pre: 'expires_at -20m, status pending',
            repro:
                'rpc process accept; rpc batata_live_reservation_stripe_convert',
            expected: 'expired / recusa',
            obtained: {
              'accept': accExp.brief,
              'convert': convExp.brief,
              'row': row2.map,
            },
          );
        }
        if (convX.ok && convX.map?['ok'] == true) {
          c.hold(
            id: 'RTG-G5-004',
            lens: 'G5',
            severity: 'P1',
            title: '2.º buyer converte reserva alheia (stripe_convert sem auth de dono)',
            actor: 'buyer2 JWT',
            pre: 'reservation de buyer1',
            repro: 'rpc batata_live_reservation_stripe_convert',
            expected: 'not_allowed',
            obtained: convX.brief,
          );
        }
      }
    } else {
      c.note('p2.g5.resv_ins_fail', 'reservation insert', resv.brief, lens: 'G5');
    }
  } else {
    c.note('p2.g5.live_item_fail', 'live_items insert', li.brief, lens: 'G5');
  }
  await c.endLives();

  out['findings'] = c.findings;
  out['notes'] = c.notes;
  out['wallets_after'] = await c.wallets();
  out['created'] = {
    'products': c.createdProductIds,
    'orders': c.createdOrderIds,
    'lives': c.createdLiveIds,
  };
  await dumpJson('tool/redteam_blind_g_20260831T1253/pass2.json', out);
  stdout.writeln('PASS2 findings=${c.findings.length}');
}
