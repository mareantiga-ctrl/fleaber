/// PASS 1 — G5 TTL · G6 estado obsoleto · G7 JWT velho · descoberta.
import 'dart:io';
import '_rtg.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rtg.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final out = <String, Object?>{
    'pass': 1,
    'prefix': prefix,
    'actors': {
      'buyer': c.buyerId,
      'seller': c.sellerId,
      'buyer2': c.buyer2Id,
      'seller2': c.seller2Id,
    },
  };

  // ---- Discover RPCs with time/expire/settle/release in name ----
  final openapi = await c.req(
    'GET',
    '/rest/v1/',
    extra: {'Accept': 'application/openapi+json'},
    service: true,
  );
  final rpcNames = <String>[];
  if (openapi.json is Map) {
    final paths = (openapi.json as Map)['paths'];
    if (paths is Map) {
      for (final k in paths.keys) {
        final s = k.toString();
        if (s.startsWith('/rpc/')) {
          final n = s.substring(5);
          if (RegExp(
            r'expir|settle|release|refund|hold|replay|idempot|payout|feedback|claim|pairing|reservation|wallet|offer|cron',
            caseSensitive: false,
          ).hasMatch(n)) {
            rpcNames.add(n);
          }
        }
      }
    }
  }
  rpcNames.sort();
  out['rpc_time_related'] = rpcNames;
  c.note('p1.rpcs', 'RPCs tempo/dinheiro visíveis', rpcNames.length);

  // ---- G7: logout then reuse JWT ----
  final jwtBefore = c.buyerJwt!;
  final logout = await c.req('POST', '/auth/v1/logout', jwt: jwtBefore, body: {});
  c.note('p1.logout', 'POST logout', logout.brief, lens: 'G7');
  final stillWrite = await c.rest('POST', 'orders', jwt: jwtBefore, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'price_total': 1.0,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  // Need a product — create first
  final pJwt = await c.insertProduct(title: '$prefix jwt-ttl', qty: 3);
  final stillWrite2 = await c.rest('POST', 'orders', jwt: jwtBefore, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pJwt,
    'price_total': 8.5,
    'quantity': 1,
    'status': 'reserva_pendente',
    'payment_method': 'Pagamento na app',
    'shipping_method': 'entrega em mão',
  });
  if (stillWrite2.ok && stillWrite2.firstId != null) {
    c.createdOrderIds.add(stillWrite2.firstId!);
    c.hold(
      id: 'RTG-G7-001',
      lens: 'G7',
      severity: 'P2',
      title: 'JWT comprador continua a escrever depois de logout',
      actor: 'buyer JWT pós-logout',
      pre: 'POST /auth/v1/logout com o mesmo access_token',
      repro: 'POST orders com o JWT anterior',
      expected: '401 / sessão revogada',
      obtained: stillWrite2.brief,
      evidence: {
        'logout_http': logout.status,
        'order_id': stillWrite2.firstId,
        'product_id': pJwt,
      },
    );
  } else {
    c.note('p1.g7.blocked', 'JWT pós-logout bloqueado', stillWrite2.brief,
        lens: 'G7');
  }
  // Relogin buyer for rest of pass
  c.buyerJwt = await c.signIn(
    envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );

  // ---- G6: stale PATCH status after world moved ----
  final pStale = await c.insertProduct(title: '$prefix stale-patch', qty: 2);
  final oidStale = await c.insertOrder(
    productId: pStale!,
    jwt: c.buyerJwt,
  );
  // Seller cancels
  final cancel = await c.rest(
    'PATCH',
    'orders?id=eq.$oidStale',
    jwt: c.sellerJwt,
    body: {'status': 'cancelado'},
  );
  c.note('p1.g6.seller_cancel', 'seller cancela hold', cancel.brief, lens: 'G6');
  // Buyer still has "pending" on screen → PATCH pago / concluido
  final stalePago = await c.rest(
    'PATCH',
    'orders?id=eq.$oidStale',
    jwt: c.buyerJwt,
    body: {'status': 'pago'},
  );
  final staleConc = await c.rest(
    'PATCH',
    'orders?id=eq.$oidStale',
    jwt: c.buyerJwt,
    body: {'status': 'concluido'},
  );
  final afterStale = await c.orderRow(oidStale!);
  c.note('p1.g6.stale_pago', 'buyer PATCH pago pós-cancel', stalePago.brief,
      lens: 'G6');
  c.note('p1.g6.stale_conc', 'buyer PATCH concluido pós-cancel', staleConc.brief,
      lens: 'G6');
  final st = '${afterStale?['status']}'.toLowerCase();
  if (st == 'pago' || st == 'concluido') {
    c.hold(
      id: 'RTG-G6-001',
      lens: 'G6',
      severity: 'P1',
      title: 'PATCH obsoleto do comprador reabre encomenda cancelada para $st',
      actor: 'buyer JWT',
      pre: 'seller cancelou hold; ecrã comprador ainda pendente',
      repro: 'PATCH orders status=pago|concluido',
      expected: 'permanece cancelado',
      obtained: afterStale,
      evidence: {
        'cancel': cancel.brief,
        'pago': stalePago.brief,
        'concluido': staleConc.brief,
      },
    );
  }

  // Seller PATCH enviado on cancelled (stale studio screen)
  final staleShip = await c.rest(
    'PATCH',
    'orders?id=eq.$oidStale',
    jwt: c.sellerJwt,
    body: {'status': 'enviado'},
  );
  final afterShip = await c.orderRow(oidStale);
  c.note('p1.g6.stale_ship', 'seller PATCH enviado pós-cancel', staleShip.brief,
      lens: 'G6');
  if ('${afterShip?['status']}'.toLowerCase() == 'enviado') {
    c.hold(
      id: 'RTG-G6-002',
      lens: 'G6',
      severity: 'P1',
      title: 'Seller marca enviado numa encomenda já cancelada',
      actor: 'seller JWT',
      pre: 'order cancelado',
      repro: 'PATCH status=enviado',
      expected: 'bloqueado',
      obtained: afterShip,
    );
  }

  // ---- G6: checkout com preço velho após PATCH produto ----
  final pPrice = await c.insertProduct(
    title: '$prefix stale-price',
    qty: 2,
    price: 8.5,
  );
  final oidPrice = await c.insertOrder(
    productId: pPrice!,
    jwt: c.buyerJwt,
    price: 8.5,
  );
  await c.rest(
    'PATCH',
    'products?id=eq.$pPrice',
    jwt: c.sellerJwt,
    body: {'price': 99.0},
  );
  final payOld = await c.edge('create-payment-intent', {
    'order_id': oidPrice,
    'buyer_id': c.buyerId,
    'shipping_method': 'entrega em mão',
  }, jwt: c.buyerJwt);
  c.note('p1.g6.stale_price', 'checkout após seller subir preço 8.5→99',
      payOld.brief, lens: 'G6');
  final quote = payOld.map;
  final amount = quote?['amount_cents'] ?? quote?['amount'];
  // If session created at 850¢ after price 99€ → buyer underpays (P1)
  // If 9900¢ → uses live price (may surprise buyer, P3)
  if (payOld.ok) {
    final cents = amount is num
        ? amount.round()
        : int.tryParse('$amount') ?? -1;
    if (cents > 0 && cents <= 900) {
      c.hold(
        id: 'RTG-G6-003',
        lens: 'G6',
        severity: 'P1',
        title: 'Checkout sela preço velho 8,50€ depois do vendedor subir para 99€',
        actor: 'buyer JWT + seller PATCH',
        pre: 'order criado a 8.50; produto PATCH 99',
        repro: 'POST create-payment-intent na order antiga',
        expected: 'recusa ou requote ao preço actual',
        obtained: payOld.brief,
        evidence: {'amount': amount, 'order': oidPrice, 'product': pPrice},
      );
    } else {
      c.note('p1.g6.price_requote', 'checkout requote/recusa', {
        'cents': cents,
        'http': payOld.status,
      }, lens: 'G6');
    }
  }

  // ---- G5: offer expires_at passado + seller accept ----
  final pOff = await c.insertProduct(title: '$prefix offer-ttl', qty: 2);
  final offer = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
    'product_id': pOff,
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'amount': 5.0,
    'status': 'pending',
    'offered_by': 'buyer',
  });
  final offerId = offer.firstId;
  c.note('p1.g5.offer_ins', 'INSERT offer', offer.brief, lens: 'G5');
  if (offerId != null) {
    await c.rest(
      'PATCH',
      'product_offers?id=eq.$offerId',
      service: true,
      body: {
        'expires_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 3))
            .toIso8601String(),
      },
    );
    final acc = await c.rest(
      'PATCH',
      'product_offers?id=eq.$offerId',
      jwt: c.sellerJwt,
      body: {'status': 'accepted'},
    );
    final offRow = await c.rest(
      'GET',
      'product_offers?id=eq.$offerId&select=id,status,amount,expires_at',
      service: true,
    );
    c.note('p1.g5.offer_acc', 'seller accept expired', acc.brief, lens: 'G5');
    if (acc.ok && '${offRow.map?['status']}'.toLowerCase() == 'accepted') {
      c.hold(
        id: 'RTG-G5-001',
        lens: 'G5',
        severity: 'P1',
        title: 'Seller aceita proposta com expires_at no passado',
        actor: 'seller JWT',
        pre: 'offer pending, expires_at -3h (fixture service)',
        repro: 'PATCH status=accepted',
        expected: 'offer_expired',
        obtained: offRow.map,
      );
    }
  }

  // ---- G5: live reservation accept after expires_at ----
  final liveId = await c.insertLive(active: false);
  final pLive = await c.insertProduct(
    title: '$prefix live-resv',
    qty: 1,
    live: true,
    listed: false,
  );
  String? liveItemId;
  if (liveId != null && pLive != null) {
    final li = await c.rest('POST', 'live_items', service: true, body: {
      'live_id': liveId,
      'product_id': pLive,
      'seller_id': c.sellerId,
      'title': '$prefix item',
      'status': 'available',
    });
    liveItemId = li.firstId ?? li.map?['id']?.toString();
    c.note('p1.g5.live_item', 'live_items insert', li.brief, lens: 'G5');
    if (liveItemId == null) {
      // try alternate columns
      final li2 = await c.rest('POST', 'live_items', service: true, body: {
        'live_id': liveId,
        'id': pLive,
      });
      liveItemId = li2.firstId;
      c.note('p1.g5.live_item2', 'live_items alt', li2.brief, lens: 'G5');
    }
  }
  String? resvId;
  if (liveId != null && liveItemId != null) {
    final resv = await c.rest(
      'POST',
      'live_reservation_requests',
      jwt: c.buyerJwt,
      body: {
        'live_id': liveId,
        'live_item_id': liveItemId,
        'seller_id': c.sellerId,
        'buyer_id': c.buyerId,
        'requested_qty': 1,
        'source': 'fleaber_live',
        'status': 'pending',
      },
    );
    resvId = resv.firstId;
    c.note('p1.g5.resv_ins', 'buyer INSERT reservation', resv.brief, lens: 'G5');
    if (resvId != null) {
      await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$resvId',
        service: true,
        body: {
          'expires_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 10))
              .toIso8601String(),
        },
      );
      final accept = await c.rpc(
        'batata_process_live_reservation_request',
        {'p_request_id': resvId, 'p_action': 'accept'},
        jwt: c.sellerJwt,
      );
      final row = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$resvId&select=id,status,expires_at,requested_qty',
        service: true,
      );
      c.note('p1.g5.resv_acc', 'seller accept expired resv', accept.brief,
          lens: 'G5');
      final rst = '${row.map?['status']}'.toLowerCase();
      if (accept.ok && rst == 'accepted') {
        c.hold(
          id: 'RTG-G5-002',
          lens: 'G5',
          severity: 'P1',
          title: 'Seller aceita reserva live com expires_at no passado',
          actor: 'seller JWT',
          pre: 'live_reservation_requests.expires_at -10m, status pending',
          repro: 'rpc batata_process_live_reservation_request accept',
          expected: 'expired / recusa',
          obtained: {'rpc': accept.brief, 'row': row.map},
          evidence: {
            'live_id': liveId,
            'live_item_id': liveItemId,
            'resv_id': resvId,
          },
        );
        // G9 compose: convert expired-accepted into marketplace hold
        final conv = await c.insertOrder(
          productId: pLive!,
          jwt: c.buyerJwt,
          qty: 1,
        );
        if (conv != null) {
          c.hold(
            id: 'RTG-G9-001',
            lens: 'G9',
            severity: 'P1',
            title: 'Reserva live expirada aceite converte-se em hold de stock',
            actor: 'buyer JWT após G5-002',
            pre: 'reservation accepted despite TTL',
            repro: 'POST orders no mesmo SKU',
            expected: 'hold recusado (TTL / sold)',
            obtained: await c.orderRow(conv),
            evidence: {'order_id': conv, 'product': await c.productRow(pLive)},
          );
        }
      }
    }
  }

  // ---- G5: pairing claim after expires_at ----
  if (liveId != null) {
    final pair = await c.rpc(
      'batata_ps_create_pairing',
      {'p_live_id': liveId},
      jwt: c.sellerJwt,
    );
    c.note('p1.g5.pair_create', 'create pairing', pair.brief, lens: 'G5');
    final code = pair.map?['code']?.toString();
    final pairId = pair.map?['id']?.toString();
    if (pairId != null || code != null) {
      if (pairId != null) {
        await c.rest(
          'PATCH',
          'ps_pairing_sessions?id=eq.$pairId',
          service: true,
          body: {
            'expires_at': DateTime.now()
                .toUtc()
                .subtract(const Duration(minutes: 5))
                .toIso8601String(),
          },
        );
      } else if (code != null) {
        await c.rest(
          'PATCH',
          'ps_pairing_sessions?code=eq.$code',
          service: true,
          body: {
            'expires_at': DateTime.now()
                .toUtc()
                .subtract(const Duration(minutes: 5))
                .toIso8601String(),
          },
        );
      }
      final claim = await c.rpc(
        'batata_ps_claim_pairing',
        {
          'p_code': code ?? '',
          'p_device_id': 'rtg-g5-dev',
          'p_device_name': 'rtg',
        },
        jwt: c.buyerJwt,
      );
      // also try edge
      final claimEdge = await c.edge('ps-pairing-claim', {
        'code': code,
        'device_id': 'rtg-g5-dev',
      }, jwt: c.buyerJwt);
      c.note('p1.g5.pair_claim', 'claim expired pairing rpc', claim.brief,
          lens: 'G5');
      c.note('p1.g5.pair_edge', 'claim expired pairing edge', claimEdge.brief,
          lens: 'G5');
      final claimed = (claim.ok && claim.map?['ok'] != false) ||
          (claimEdge.ok && claimEdge.map?['ok'] != false);
      if (claimed &&
          (claim.body.toLowerCase().contains('token') ||
              claimEdge.body.toLowerCase().contains('token') ||
              claim.map?['ok'] == true ||
              claimEdge.map?['ok'] == true)) {
        c.hold(
          id: 'RTG-G5-003',
          lens: 'G5',
          severity: 'P1',
          title: 'Claim de pairing depois de expires_at na BD',
          actor: 'buyer JWT',
          pre: 'ps_pairing_sessions.expires_at passado',
          repro: 'rpc batata_ps_claim_pairing / edge ps-pairing-claim',
          expected: 'expired',
          obtained: {'rpc': claim.brief, 'edge': claimEdge.brief},
        );
      }
    }
  }

  // ---- G5: JWT chama cron expire / auto-feedback (autoridade) ----
  final expireJwt = await c.rpc('batata_expire_product_offers', {}, jwt: c.buyerJwt);
  final fbJwt = await c.rpc(
    'batata_generate_auto_feedback',
    {
      'p_now': DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String(),
    },
    jwt: c.buyerJwt,
  );
  c.note('p1.g8.expire_jwt', 'buyer chama expire offers', expireJwt.brief,
      lens: 'G8');
  c.note('p1.g8.autofb_jwt', 'buyer chama auto-feedback futuro', fbJwt.brief,
      lens: 'G8');
  if (expireJwt.ok && expireJwt.status == 200) {
    c.hold(
      id: 'RTG-G8-001',
      lens: 'G8',
      severity: 'P2',
      title: 'JWT autenticado executa cron batata_expire_product_offers',
      actor: 'buyer JWT',
      pre: 'função de cron',
      repro: 'POST rpc/batata_expire_product_offers',
      expected: 'permission denied',
      obtained: expireJwt.brief,
    );
  }
  if (fbJwt.ok && fbJwt.status == 200) {
    c.hold(
      id: 'RTG-G8-002',
      lens: 'G8',
      severity: 'P1',
      title: 'JWT dispara auto-feedback com p_now no futuro (acelera 48h)',
      actor: 'buyer JWT',
      pre: 'cron 48h',
      repro: 'rpc batata_generate_auto_feedback p_now=+30d',
      expected: 'só service_role',
      obtained: fbJwt.brief,
    );
  }

  // ---- G1 sequential double checkout (baseline before parallel) ----
  final pDup = await c.insertProduct(title: '$prefix dup-co', qty: 2);
  final oidDup = await c.insertOrder(productId: pDup!, jwt: c.buyerJwt);
  final co1 = await c.edge('create-payment-intent', {
    'order_id': oidDup,
    'buyer_id': c.buyerId,
    'shipping_method': 'entrega em mão',
  }, jwt: c.buyerJwt);
  final co2 = await c.edge('create-payment-intent', {
    'order_id': oidDup,
    'buyer_id': c.buyerId,
    'shipping_method': 'entrega em mão',
  }, jwt: c.buyerJwt);
  c.note('p1.g1.co_seq', 'double checkout sequencial', {
    'a': co1.brief,
    'b': co2.brief,
  }, lens: 'G1');

  await c.endLives();
  out['findings'] = c.findings;
  out['notes'] = c.notes;
  out['created'] = {
    'products': c.createdProductIds,
    'orders': c.createdOrderIds,
    'lives': c.createdLiveIds,
  };
  await dumpJson(
    'tool/redteam_blind_g_20260831T1253/pass1.json',
    out,
  );
  stdout.writeln('PASS1 findings=${c.findings.length} notes=${c.notes.length}');
}
