/// PASS 4 — G8 cron vs humano · G9 composição · JWT switch · wrap.
import 'dart:io';
import '_rtg.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rtg.fromEnv(env);
  await c.loginActors();
  await c.ensureBuyer2();

  final out = <String, Object?>{'pass': 4, 'prefix': prefix};

  // ---- G5: live reservation TTL (item_kind correcto) ----
  final live4 = await c.insertLive(active: false);
  final pLi = await c.insertProduct(
    title: '$prefix resv-ttl',
    qty: 1,
    live: true,
    listed: false,
  );
  final li = await c.rest('POST', 'live_items', service: true, body: {
    'live_id': live4,
    'product_id': pLi,
    'checkout_product_id': pLi,
    'seller_id': c.sellerId,
    'title': 'rtg ttl',
    'ref_code': 'RTG4',
    'item_kind': 'marketplace_product',
    'quantity': 1,
    'is_active': true,
    'status': 'available',
    'price': 8.5,
  });
  c.note('p4.g5.live_item', 'live_items insert', li.brief, lens: 'G5');
  final liveItemId = li.firstId;
  if (live4 != null && liveItemId != null) {
    final resv = await c.rest(
      'POST',
      'live_reservation_requests',
      jwt: c.buyerJwt,
      body: {
        'live_id': live4,
        'live_item_id': liveItemId,
        'seller_id': c.sellerId,
        'buyer_id': c.buyerId,
        'requested_qty': 1,
        'source': 'fleaber_live',
        'status': 'pending',
      },
    );
    c.note('p4.g5.resv', 'INSERT reservation', resv.brief, lens: 'G5');
    final rid = resv.firstId;
    if (rid != null) {
      await c.rest(
        'PATCH',
        'live_reservation_requests?id=eq.$rid',
        service: true,
        body: {
          'expires_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 15))
              .toIso8601String(),
        },
      );
      final acc = await c.rpc(
        'batata_process_live_reservation_request',
        {'p_request_id': rid, 'p_action': 'accept'},
        jwt: c.sellerJwt,
      );
      final conv = await c.rpc(
        'batata_live_reservation_stripe_convert',
        {'p_request_id': rid},
        jwt: c.buyerJwt,
      );
      final conv2 = await c.rpc(
        'batata_live_reservation_stripe_convert',
        {'p_request_id': rid},
        jwt: c.buyer2Jwt,
      );
      final row = await c.rest(
        'GET',
        'live_reservation_requests?id=eq.$rid&select=id,status,expires_at,buyer_id,notes',
        service: true,
      );
      c.note('p4.g5.ttl', 'accept/convert after expire', {
        'accept': acc.brief,
        'convert': conv.brief,
        'convert_b2': conv2.brief,
        'row': row.map,
      }, lens: 'G5');
      final st = '${row.map?['status']}'.toLowerCase();
      if (st == 'accepted' || st == 'converted') {
        c.hold(
          id: 'RTG-G5-002',
          lens: 'G5',
          severity: 'P1',
          title: 'Reserva live aceite/convertida com expires_at no passado',
          actor: 'seller JWT + buyer JWT',
          pre: 'expires_at -15m',
          repro:
              'rpc process accept; rpc batata_live_reservation_stripe_convert',
          expected: 'expired',
          obtained: {'row': row.map, 'accept': acc.brief, 'convert': conv.brief},
        );
      }
      if (conv2.ok && conv2.map?['ok'] == true) {
        c.hold(
          id: 'RTG-G5-004',
          lens: 'G5',
          severity: 'P1',
          title: '2.º buyer converte reserva alheia expirada',
          actor: 'buyer2 JWT',
          pre: 'reservation buyer1',
          repro: 'rpc stripe_convert',
          expected: 'not_allowed',
          obtained: conv2.brief,
        );
      }
    }
  }
  await c.endLives();

  // ---- G8: auto-feedback vs human review on same concluido order ----
  final paid = await c.e2e('setup_paid_order', {'initial_qty': 2});
  c.note('p4.fixture', 'setup_paid_order', paid.brief, lens: 'G8');
  final pm = paid.map ?? {};
  final oid = (pm['order_id'] ??
          (pm['order'] is Map ? (pm['order'] as Map)['id'] : null))
      ?.toString();
  final pid = pm['product_id']?.toString();
  if (pid != null) c.createdProductIds.add(pid);
  if (oid != null) {
    c.createdOrderIds.add(oid);
    // Hand-delivery: buyer may concluido from pago
    await c.rest('PATCH', 'orders?id=eq.$oid', jwt: c.sellerJwt, body: {
      'shipping_method': 'entrega em mão',
    });
    final toPaidShip = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: c.sellerJwt,
      body: {'status': 'enviado'},
    );
    c.note('p4.ship', 'seller enviado', toPaidShip.brief, lens: 'G8');
    final toConc = await c.rest(
      'PATCH',
      'orders?id=eq.$oid',
      jwt: c.buyerJwt,
      body: {'status': 'concluido'},
    );
    c.note('p4.conc', 'buyer concluido', toConc.brief, lens: 'G8');
    final row = await c.orderRow(oid);
    out['order_after_conc'] = row;

    if ('${row?['status']}'.toLowerCase() == 'concluido') {
      // Age completed_at via fixture then race human review ∥ auto-feedback
      await c.rest(
        'PATCH',
        'orders?id=eq.$oid',
        service: true,
        body: {
          'completed_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 49))
              .toIso8601String(),
        },
      );
      final r = await parallel([
        c.rest('POST', 'reviews', jwt: c.buyerJwt, body: {
          'order_id': oid,
          'target_id': c.sellerId,
          'stars': 5,
          'author_role': 'comprador',
          'comment': '$prefix human',
        }),
        c.rpc(
          'batata_generate_auto_feedback',
          {'p_now': DateTime.now().toUtc().toIso8601String()},
          service: true,
        ),
      ]);
      final revs = await c.rest(
        'GET',
        'reviews?order_id=eq.$oid&select=id,stars,author_role,comment,created_at',
        service: true,
      );
      c.note('p4.g8.review_cron', 'human review ∥ auto-feedback', {
        'human': r[0].brief,
        'cron': r[1].brief,
        'reviews': revs.list.length,
      }, lens: 'G8');
      if (revs.list.length >= 2) {
        c.hold(
          id: 'RTG-G8-003',
          lens: 'G8',
          severity: 'P2',
          title: 'Review humana e auto-feedback no mesmo order em paralelo',
          actor: 'buyer INSERT reviews ∥ cron',
          pre: 'concluido + completed_at -49h',
          repro: 'Future.wait POST reviews ∥ batata_generate_auto_feedback',
          expected: '1 review comprador',
          obtained: revs.list,
        );
      }
      final w = await c.wallets();
      final rel = await c.orderRow(oid);
      out['wallets_after_review'] = w;
      out['order_after_review'] = rel;
    }
  }

  // ---- G7: use seller JWT as buyer on checkout of someone else's hold ----
  final p = await c.insertProduct(title: '$prefix jwt-switch', qty: 2);
  final o = await c.insertOrder(productId: p!, jwt: c.buyerJwt);
  final payAsSeller = await c.edge('create-payment-intent', {
    'order_id': o,
    'buyer_id': c.buyerId,
    'shipping_method': 'entrega em mão',
  }, jwt: c.sellerJwt);
  c.note('p4.g7.seller_pays_buyer_order', 'seller JWT checkout order buyer',
      payAsSeller.brief, lens: 'G7');
  if (payAsSeller.ok &&
      (payAsSeller.map?['url'] != null ||
          payAsSeller.map?['checkout_url'] != null)) {
    c.hold(
      id: 'RTG-G7-003',
      lens: 'G7',
      severity: 'P1',
      title: 'Seller JWT cria Checkout Session da order do comprador',
      actor: 'seller JWT',
      pre: 'hold buyer',
      repro: 'POST create-payment-intent com seller token + buyer_id da order',
      expected: '403 / not buyer',
      obtained: payAsSeller.brief,
    );
  }

  // ---- G6: buyer2 PATCH foreign order ----
  final x = await c.rest(
    'PATCH',
    'orders?id=eq.$o',
    jwt: c.buyer2Jwt,
    body: {'status': 'cancelado'},
  );
  c.note('p4.g6.foreign_patch', 'buyer2 PATCH order alheia', x.brief, lens: 'G6');
  if (x.ok && x.list.isNotEmpty) {
    c.hold(
      id: 'RTG-G6-005',
      lens: 'G6',
      severity: 'P1',
      title: '2.º buyer altera status de encomenda alheia',
      actor: 'buyer2 JWT',
      pre: 'order buyer1',
      repro: 'PATCH status=cancelado',
      expected: '0 rows / RLS',
      obtained: x.brief,
    );
  }

  // ---- G9: stale price + parallel checkout + unlist ----
  final p9 = await c.insertProduct(
    title: '$prefix g9-compose',
    qty: 1,
    price: 5.0,
  );
  final o9 = await c.insertOrder(productId: p9!, jwt: c.buyerJwt, price: 5.0);
  await c.rest('PATCH', 'products?id=eq.$p9', jwt: c.sellerJwt, body: {
    'price': 50.0,
  });
  final compose = await parallel([
    c.edge('create-payment-intent', {
      'order_id': o9,
      'buyer_id': c.buyerId,
      'shipping_method': 'entrega em mão',
    }, jwt: c.buyerJwt),
    c.edge('create-payment-intent', {
      'order_id': o9,
      'buyer_id': c.buyerId,
      'shipping_method': 'entrega em mão',
    }, jwt: c.buyerJwt),
    c.rest('PATCH', 'products?id=eq.$p9', jwt: c.sellerJwt, body: {
      'list_on_marketplace': false,
    }),
  ]);
  c.note('p4.g9.compose', '2× checkout ∥ unlist após price bump', {
    'pay1': compose[0].brief,
    'pay2': compose[1].brief,
    'unlist': compose[2].brief,
    'product': await c.productRow(p9),
    'order': await c.orderRow(o9!),
  }, lens: 'G9');
  final sessions = compose
      .take(2)
      .where((h) => h.ok)
      .map((h) => h.map?['url'] ?? h.map?['checkout_url'] ?? h.map?['session_id'])
      .where((x) => x != null)
      .toSet();
  if (sessions.length >= 2) {
    c.hold(
      id: 'RTG-G9-002',
      lens: 'G9',
      severity: 'P1',
      title: 'Composição: preço velho + dual Session + unlist em paralelo',
      actor: 'buyer ×2 ∥ seller',
      pre: 'order 5€, produto 50€, qty=1',
      repro: 'Future.wait 2× checkout ∥ unlist',
      expected: '≤1 Session e recusa se unlist',
      obtained: {
        'sessions': sessions.length,
        'a': compose[0].brief,
        'b': compose[1].brief,
      },
    );
  }

  // ---- G5: expired checkout still GET-able (unpaid session after unlist) ----
  // Use leftover o9 session if any
  final url = compose[0].map?['url']?.toString() ??
      compose[0].map?['checkout_url']?.toString();
  final sid = compose[0].map?['session_id']?.toString();
  if (sid != null) {
    final lateGet = await c.req(
      'GET',
      '/functions/v1/create-payment-intent?checkout_return=success&session_id=$sid',
      jwt: c.buyerJwt,
    );
    c.note('p4.g5.stale_session_get', 'GET settle Session após unlist',
        lateGet.brief, lens: 'G5');
  }
  out['checkout_url_present'] = url != null;

  // ---- G3: INSERT stripe_checkout_events as JWT (fake replay log) ----
  final ev = await c.rest('POST', 'stripe_checkout_events', jwt: c.buyerJwt, body: {
    'session_id': 'cs_test_rtg_fake',
    'order_id': o,
    'event': 'webhook.checkout.session.settled',
    'detail': '{"stripe_event_id":"evt_rtg"}',
  });
  c.note('p4.g3.events_insert', 'JWT INSERT stripe_checkout_events', ev.brief,
      lens: 'G3');
  if (ev.ok) {
    c.hold(
      id: 'RTG-G3-005',
      lens: 'G3',
      severity: 'P2',
      title: 'JWT insere eventos Stripe (oráculo / replay log)',
      actor: 'buyer JWT',
      pre: 'tabela stripe_checkout_events',
      repro: 'POST stripe_checkout_events',
      expected: 'RLS deny',
      obtained: ev.brief,
    );
  }

  out['findings'] = c.findings;
  out['notes'] = c.notes;
  out['wallets'] = await c.wallets();
  out['created'] = {
    'products': c.createdProductIds,
    'orders': c.createdOrderIds,
  };
  await dumpJson('tool/redteam_blind_g_20260831T1253/pass4.json', out);
  stdout.writeln('PASS4 findings=${c.findings.length}');
}
