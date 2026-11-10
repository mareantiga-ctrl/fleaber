import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../live_ops_staging_client.dart';
import '_http.dart';

Future<void> main() async {
  final ctx = await boot();
  final e = loadLiveOpsStagingEnv();
  final e2eSecret = e['FLEABER_STAGING_CRASH_INJECT_SECRET'] ?? '';
  final matrix = <Map<String, dynamic>>[];
  final findings = <Map<String, dynamic>>[];
  final notes = <String>[];

  void row(String surface, String attack, String identity, Hit h, {String extra = ''}) {
    matrix.add({
      'surface': surface,
      'attack': attack,
      'identity': identity,
      'result': '${h.status} ${h.snippet}',
      'extra': extra,
    });
  }

  void finding({
    required String id,
    required String severity,
    required String title,
    required String actor,
    required String pre,
    required String repro,
    required String impact,
    Object? evidence,
  }) {
    findings.add({
      'id': id,
      'severity': severity,
      'title': title,
      'actor': actor,
      'preconditions': pre,
      'reproduction': repro,
      'impact': impact,
      'state': 'OPEN',
      'evidence': evidence,
    });
  }

  // cleanup mux from pass2
  final muxDone = await ctx.edge(
    'complete-mux-live',
    {'live_id': 'd4e2adf7-dae3-4c42-9804-c9bbc4dc5cad'},
    jwt: ctx.sellerJwt,
  );
  row('MUX', 'complete buyer2 live as lab seller', 'seller', muxDone);
  // buyer2 jwt — sign in again
  // buyer2 live from pass2 — ended via service_role below.
  // complete as... we don't have buyer2 password in this run unless we recreate.
  // try complete with seller of that live = buyer2, we don't have jwt. Use original
  // complete-mux-live as... 404 if not owner. Service observe + complete via edge
  // with a new sign-in isn't possible. End via service patch lives.
  await ctx.rest('PATCH', '/rest/v1/lives?id=eq.d4e2adf7-dae3-4c42-9804-c9bbc4dc5cad',
      service: true, body: {'status': 'ended', 'is_active': false});

  // ---- STORAGE deep ----
  Future<Hit> listPrefix(String jwt, String bucket, String prefix) {
    return ctx.rest('POST', '/storage/v1/object/list/$bucket', jwt: jwt, body: {
      'prefix': prefix,
      'limit': 50,
    });
  }

  for (final prefix in [
    'order_proofs/',
    'order_proofs/${ctx.sellerId}/',
    'order_proofs/${ctx.buyerId}/',
    'order_disputes/',
    'chat_uploads/',
  ]) {
    final h = await listPrefix(ctx.buyerJwt, 'fleaber_private', prefix);
    row('STORAGE', 'list fleaber_private $prefix', 'buyer', h);
    final j = h.json;
    if (h.ok && j is List && j.isNotEmpty && prefix.startsWith('order_proofs/${ctx.sellerId}')) {
      finding(
        id: 'P1-STORAGE-PROOF-CROSS',
        severity: 'P1',
        title: 'Buyer lista provas de encomenda do seller noutro path',
        actor: 'buyer JWT',
        pre: 'conhece UUID seller',
        repro: 'POST storage list fleaber_private prefix=order_proofs/<seller>/',
        impact: 'ficheiros de prova alheios',
        evidence: h.snippet,
      );
    }
  }

  final pub = await listPrefix(ctx.buyerJwt, 'chat_media', 'product_photos/${ctx.sellerId}/');
  row('STORAGE', 'list chat_media product_photos seller', 'buyer', pub);

  // try download first object if any under order_proofs
  final ownProofs = await listPrefix(ctx.buyerJwt, 'fleaber_private', 'order_proofs/${ctx.buyerId}/');
  row('STORAGE', 'list own proofs', 'buyer', ownProofs);

  // ---- product + reservado checkout ----
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final prod = await ctx.rest('POST', '/rest/v1/products', jwt: ctx.sellerJwt, body: {
    'seller_id': ctx.sellerId,
    'title': 'CEGA1243 reservado $stamp',
    'price': 20.00,
    'quantity': 2,
    'list_on_marketplace': true,
  });
  row('PRODUCTS', 'INSERT qty2 price20', 'seller', prod);
  String? pid;
  final pj = prod.json;
  if (prod.ok) {
    if (pj is List && pj.isNotEmpty) pid = (pj.first as Map)['id']?.toString();
  }

  String? oid;
  if (pid != null) {
    final o = await ctx.rest('POST', '/rest/v1/orders', jwt: ctx.buyerJwt, body: {
      'buyer_id': ctx.buyerId,
      'seller_id': ctx.sellerId,
      'product_id': pid,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Seguro Fleaber',
      'shipping_method': 'hand',
      'price_total': 0.01,
    });
    row('ORDERS', 'INSERT reserva_pendente price 0.01', 'buyer', o);
    final oj = o.json;
    Map<String, dynamic>? orow;
    if (o.ok && oj is List && oj.isNotEmpty) {
      orow = Map<String, dynamic>.from(oj.first as Map);
      oid = orow['id']?.toString();
    }
    if (orow != null) {
      notes.add(
          'sealed unit=${orow['contract_unit_cents']} qty=${orow['contract_qty']} total=${orow['price_total']} status=${orow['status']}');
    }

    // seller drops catalog price
    final drop = await ctx.rest(
      'PATCH',
      '/rest/v1/products?id=eq.$pid',
      jwt: ctx.sellerJwt,
      body: {'price': 0.50},
    );
    row('CATALOG', 'seller drop price to 0.50 after order', 'seller', drop);

    if (oid != null) {
      final ckCheap = await ctx.edge('create-payment-intent', {
        'buyer_id': ctx.buyerId,
        'order_id': oid,
        'amount': 50,
        'quantity': 2,
        'shipping_method': 'hand',
        'item_price': 0.5,
        'shipping': 0,
        'protection_fee': 0,
      }, jwt: ctx.buyerJwt);
      row('CHECKOUT', 'amount=50 after catalog drop', 'buyer', ckCheap);

      final ckOk = await ctx.edge('create-payment-intent', {
        'buyer_id': ctx.buyerId,
        'order_id': oid,
        'shipping_method': 'hand',
      }, jwt: ctx.buyerJwt);
      row('CHECKOUT', 'authoritative hand', 'buyer', ckOk);

      // parse amount from response
      void inspectCheckout(String label, Hit h) {
        final j = h.json;
        if (j is Map) {
          notes.add('$label keys=${j.keys.toList()} amount=${j['amount'] ?? j['amount_cents'] ?? j['amount_total']} url=${j['url'] ?? j['checkout_url']}');
          final amt = j['amount'] ?? j['amount_cents'] ?? j['amount_total'];
          if (amt != null && amt is num && amt < 2000) {
            // 20€ = 2000 cents + protection. If session < catalog*qty, flag.
            finding(
              id: 'P0-CHECKOUT-UNDERPAY',
              severity: 'P0',
              title: 'Checkout Session abaixo do contrato selado',
              actor: 'buyer JWT',
              pre: 'order reserva_pendente contract 20€',
              repro: 'POST create-payment-intent amount=50 shipping=hand',
              impact: 'pagar menos que o contrato',
              evidence: h.snippet,
            );
          }
        }
      }

      inspectCheckout('cheap', ckCheap);
      inspectCheckout('ok', ckOk);

      // dual session race 10x
      final futs = List.generate(
        10,
        (i) => ctx.edge('create-payment-intent', {
          'buyer_id': ctx.buyerId,
          'order_id': oid,
          'shipping_method': 'hand',
          'amount': i.isEven ? 50 : 99999,
        }, jwt: ctx.buyerJwt),
      );
      final raced = await Future.wait(futs);
      final oks = raced.where((h) => h.ok).length;
      row('RACE', '10x checkout same order', 'buyer',
          Hit(200, 'ok=$oks sample=${raced.first.snippet}'));
      notes.add('checkout_race_ok=$oks');

      // second order on remaining qty
      final o2 = await ctx.rest('POST', '/rest/v1/orders', jwt: ctx.buyerJwt, body: {
        'buyer_id': ctx.buyerId,
        'seller_id': ctx.sellerId,
        'product_id': pid,
        'quantity': 1,
        'status': 'reserva_pendente',
        'payment_method': 'Seguro Fleaber',
        'shipping_method': 'hand',
      });
      row('ORDERS', '2nd reserva_pendente remaining stock', 'buyer', o2);
      String? oid2;
      if (o2.ok) {
        final j = o2.json;
        if (j is List && j.isNotEmpty) oid2 = (j.first as Map)['id']?.toString();
      }
      if (oid2 != null) {
        final c1 = ctx.edge('create-payment-intent', {
          'buyer_id': ctx.buyerId,
          'order_id': oid,
          'shipping_method': 'hand',
        }, jwt: ctx.buyerJwt);
        final c2 = ctx.edge('create-payment-intent', {
          'buyer_id': ctx.buyerId,
          'order_id': oid2,
          'shipping_method': 'hand',
        }, jwt: ctx.buyerJwt);
        final dual = await Future.wait([c1, c2]);
        row('CHECKOUT', 'session order1', 'buyer', dual[0]);
        row('CHECKOUT', 'session order2 remaining', 'buyer', dual[1]);
      }

      // money patch after reservado
      final money = await ctx.rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$oid',
        jwt: ctx.buyerJwt,
        body: {
          'price_total': 0.01,
          'contract_unit_cents': 1,
          'amount_paid_cents': 1,
        },
      );
      row('ORDERS', 'PATCH money after reservado', 'buyer', money);
      final obs = await ctx.select(
        'orders',
        service: true,
        filter: 'id=eq.$oid',
        select: 'id,status,price_total,contract_unit_cents,amount_paid_cents',
      );
      row('ORDERS', 'observe after money patch', 'service', obs);
    }
  }

  // ---- MB WAY seller false pago ----
  final pMb = await ctx.rest('POST', '/rest/v1/products', jwt: ctx.sellerJwt, body: {
    'seller_id': ctx.sellerId,
    'title': 'CEGA1243 mbway $stamp',
    'price': 15.00,
    'quantity': 1,
    'list_on_marketplace': true,
  });
  String? pidMb;
  if (pMb.ok) {
    final j = pMb.json;
    if (j is List && j.isNotEmpty) pidMb = (j.first as Map)['id']?.toString();
  }
  String? oidMb;
  if (pidMb != null) {
    final om = await ctx.rest('POST', '/rest/v1/orders', jwt: ctx.buyerJwt, body: {
      'buyer_id': ctx.buyerId,
      'seller_id': ctx.sellerId,
      'product_id': pidMb,
      'quantity': 1,
      'status': 'reserva_pendente',
      'payment_method': 'MB WAY',
      'shipping_method': 'hand',
    });
    row('ORDERS', 'INSERT MB WAY reserva_pendente', 'buyer', om);
    if (om.ok) {
      final j = om.json;
      if (j is List && j.isNotEmpty) oidMb = (j.first as Map)['id']?.toString();
    }
    if (oidMb != null) {
      final acc = await ctx.rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$oidMb',
        jwt: ctx.sellerJwt,
        body: {'status': 'reservado'},
      );
      row('FSM', 'seller accept MB WAY → reservado', 'seller', acc);
      final bank = await ctx.rpc(
        'batata_seller_direct_payment_details',
        {'p_seller_id': ctx.sellerId},
        jwt: ctx.buyerJwt,
      );
      row('BANKING', 'IBAN after reservado MB WAY', 'buyer', bank);
      final pago = await ctx.rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$oidMb',
        jwt: ctx.sellerJwt,
        body: {'status': 'pago'},
      );
      row('FSM', 'seller PATCH pago off-platform', 'seller', pago);
      final afterPago = await ctx.select(
        'orders',
        service: true,
        filter: 'id=eq.$oidMb',
        select: 'id,status,amount_paid_cents,stock_units_applied,payment_method',
      );
      row('ORDERS', 'observe after seller pago', 'service', afterPago);
      final rel = await ctx.rpc(
        'batata_release_seller_wallet_for_order',
        {'p_order_id': oidMb},
        jwt: ctx.buyerJwt,
      );
      row('WALLET_RPC', 'release after fake off-platform pago', 'buyer', rel);
      // try concluido
      final env = await ctx.rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$oidMb',
        jwt: ctx.sellerJwt,
        body: {'status': 'enviado'},
      );
      row('FSM', 'seller PATCH enviado after pago', 'seller', env);
      final conc = await ctx.rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$oidMb',
        jwt: ctx.buyerJwt,
        body: {'status': 'concluido'},
      );
      row('FSM', 'buyer PATCH concluido', 'buyer', conc);
      final rel2 = await ctx.rpc(
        'batata_release_seller_wallet_for_order',
        {'p_order_id': oidMb},
        jwt: ctx.buyerJwt,
      );
      row('WALLET_RPC', 'release after concluido off-platform', 'buyer', rel2);
      final wS = await ctx.select(
        'wallets',
        service: true,
        filter: 'id=eq.${ctx.sellerId}',
        select: 'id,balance',
      );
      row('WALLET', 'seller after off-platform release', 'service', wS);

      // review on this order
      final rev = await ctx.rest('POST', '/rest/v1/reviews', jwt: ctx.buyerJwt, body: {
        'order_id': oidMb,
        'stars': 5,
        'comment': 'cega mbway review',
      });
      row('REVIEWS', 'insert on off-platform concluido', 'buyer', rev);
      final rev2 = await ctx.rest('POST', '/rest/v1/reviews', jwt: ctx.buyerJwt, body: {
        'order_id': oidMb,
        'stars': 1,
        'comment': 'cega dup',
      });
      row('REVIEWS', 'duplicate review', 'buyer', rev2);
    }
  }

  // reviews on existing concluido platform order
  final paid = await ctx.select(
    'orders',
    jwt: ctx.buyerJwt,
    select: 'id,status,amount_paid_cents,payment_method',
    filter: 'status=eq.concluido',
    limit: 5,
  );
  row('ORDERS', 'concluido list', 'buyer', paid);
  if (paid.ok && paid.json is List && (paid.json as List).isNotEmpty) {
    final id = ((paid.json as List).first as Map)['id'].toString();
    final r = await ctx.rest('POST', '/rest/v1/reviews', jwt: ctx.buyerJwt, body: {
      'order_id': id,
      'stars': 5,
      'comment': 'cega platform review',
    });
    row('REVIEWS', 'insert on existing concluido', 'buyer', r);
  }

  // ---- tips checkout ----
  final lives = await ctx.select(
    'lives',
    jwt: ctx.buyerJwt,
    select: 'id,seller_id,status',
    limit: 3,
  );
  String? liveId;
  if (lives.ok && lives.json is List && (lives.json as List).isNotEmpty) {
    liveId = ((lives.json as List).first as Map)['id']?.toString();
  }
  if (liveId != null) {
    final tLow = await ctx.edge('create-live-tip-checkout', {
      'live_id': liveId,
      'seller_id': ctx.sellerId,
      'amount_eur': 0.01,
    }, jwt: ctx.buyerJwt);
    row('TIPS', 'checkout 0.01€', 'buyer', tLow);
    final tHuge = await ctx.edge('create-live-tip-checkout', {
      'live_id': liveId,
      'seller_id': ctx.sellerId,
      'amount_eur': 9999,
    }, jwt: ctx.buyerJwt);
    row('TIPS', 'checkout 9999€', 'buyer', tHuge);
    final tSwap = await ctx.edge('create-live-tip-checkout', {
      'live_id': liveId,
      'seller_id': ctx.buyerId,
      'amount_eur': 5,
    }, jwt: ctx.buyerJwt);
    row('TIPS', 'checkout seller_id=self', 'buyer', tSwap);
  }

  // ---- live reservation accept / qty ----
  final bags = await ctx.select(
    'live_reservation_requests',
    jwt: ctx.buyerJwt,
    select: 'id,live_item_id,status,requested_qty,source',
    filter: 'status=eq.pending',
    limit: 5,
  );
  row('BAG', 'pending reservations', 'buyer', bags);
  if (bags.ok && bags.json is List && (bags.json as List).isNotEmpty) {
    final bag = Map<String, dynamic>.from((bags.json as List).first as Map);
    final rid = bag['id'].toString();
    final li = bag['live_item_id'].toString();
    final accB = await ctx.rest(
      'PATCH',
      '/rest/v1/live_reservation_requests?id=eq.$rid',
      jwt: ctx.buyerJwt,
      body: {'status': 'accepted', 'requested_qty': 99},
    );
    row('BAG', 'buyer self-accept qty99', 'buyer', accB);
    final accS = await ctx.rest(
      'PATCH',
      '/rest/v1/live_reservation_requests?id=eq.$rid',
      jwt: ctx.sellerJwt,
      body: {'status': 'accepted'},
    );
    row('BAG', 'seller accept pending', 'seller', accS);
    final stock = await ctx.rpc('batata_live_item_stock', {'p_live_item_id': li}, jwt: ctx.buyerJwt);
    row('BAG', 'stock after accept attempt', 'buyer', stock);
  }

  // ---- disputes ----
  if (oid != null) {
    final d = await ctx.rest('POST', '/rest/v1/order_disputes', jwt: ctx.buyerJwt, body: {
      'order_id': oid,
      'buyer_id': ctx.buyerId,
      'seller_id': ctx.sellerId,
      'status': 'open',
      'reason': 'cega',
    });
    row('DISPUTES', 'INSERT on unpaid reservado', 'buyer', d);
  }

  // ---- Stripe TEST fixture via e2e secret then JWT attacks ----
  if (e2eSecret.length >= 16) {
    final setup = await ctx.rest(
      'POST',
      '/functions/v1/sec-fase2-e2e-oversell',
      jwt: ctx.buyerJwt,
      extra: {'x-fleaber-e2e-secret': e2eSecret},
      body: {
        'probe': 'setup_paid_order',
        'buyer_id': ctx.buyerId,
        'seller_id': ctx.sellerId,
        'initial_qty': 1,
      },
    );
    row('E2E_FIXTURE', 'setup_paid_order (harness not JWT exploit)', 'e2e-secret', setup);
    notes.add('e2e_setup=${setup.snippet}');
    String? paidOid;
    String? pi;
    final sj = setup.json;
    if (setup.ok && sj is Map) {
      paidOid = (sj['order_id'] ?? sj['order']?['id'])?.toString();
      if (sj['order'] is Map) {
        paidOid ??= (sj['order'] as Map)['id']?.toString();
      }
      pi = sj['payment_intent_id']?.toString();
      // search nested
      void walk(dynamic v) {
        if (paidOid != null && pi != null) return;
        if (v is Map) {
          paidOid ??= v['order_id']?.toString();
          if (v['order'] is Map) {
            paidOid ??= (v['order'] as Map)['id']?.toString();
          }
          final maybePi = v['payment_intent_id']?.toString();
          if (maybePi != null && maybePi.startsWith('pi_')) pi ??= maybePi;
          final maybeId = v['id']?.toString();
          if (maybeId != null && maybeId.startsWith('pi_')) pi ??= maybeId;
          v.values.forEach(walk);
        }
      }
      walk(sj);
    }
    notes.add('paidOid=$paidOid pi=$pi');
    if (paidOid != null && paidOid!.contains('-')) {
      final before = await ctx.select(
        'orders',
        service: true,
        filter: 'id=eq.$paidOid',
        select:
            'id,status,amount_paid_cents,stock_units_applied,stripe_payment_intent_id,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at,quantity,product_id',
      );
      row('E2E', 'order after capture', 'service', before);

      final rfB = await ctx.edge('refund-order', {'order_id': paidOid}, jwt: ctx.buyerJwt);
      row('REFUND', 'buyer refunds captured', 'buyer', rfB);
      final rfS1 = ctx.edge('refund-order', {'order_id': paidOid}, jwt: ctx.sellerJwt);
      final rfS2 = ctx.edge('refund-order', {'order_id': paidOid}, jwt: ctx.sellerJwt);
      final dualRf = await Future.wait([rfS1, rfS2]);
      row('RACE', 'dual seller refund 1', 'seller', dualRf[0]);
      row('RACE', 'dual seller refund 2', 'seller', dualRf[1]);

      final afterRf = await ctx.select(
        'orders',
        service: true,
        filter: 'id=eq.$paidOid',
        select:
            'id,status,amount_paid_cents,stripe_refund_id,wallet_refund_processed_at,wallet_release_processed_at,stock_units_applied',
      );
      row('E2E', 'order after dual refund', 'service', afterRf);

      final rel = await ctx.rpc(
        'batata_release_seller_wallet_for_order',
        {'p_order_id': paidOid},
        jwt: ctx.buyerJwt,
      );
      row('WALLET_RPC', 'release after refund', 'buyer', rel);
      final wB = await ctx.select('wallets', service: true, filter: 'id=eq.${ctx.buyerId}', select: 'id,balance');
      final wS = await ctx.select('wallets', service: true, filter: 'id=eq.${ctx.sellerId}', select: 'id,balance');
      row('WALLET', 'buyer after refund/release', 'service', wB);
      row('WALLET', 'seller after refund/release', 'service', wS);

      // payout retry same key
      final key = 'cega-payout-${Random().nextInt(1 << 20)}-retryxx';
      final p1 = ctx.edge('create-connect-account', {
        'amount': 100,
        'idempotency_key': key,
      }, jwt: ctx.sellerJwt);
      final p2 = ctx.edge('create-connect-account', {
        'amount': 100,
        'idempotency_key': key,
      }, jwt: ctx.sellerJwt);
      final p3 = ctx.edge('create-connect-account', {
        'amount': 100,
        'idempotency_key': '$key-b',
      }, jwt: ctx.sellerJwt);
      final pays = await Future.wait([p1, p2, p3]);
      row('PAYOUT', 'retry same idempotency 1', 'seller', pays[0]);
      row('PAYOUT', 'retry same idempotency 2', 'seller', pays[1]);
      row('PAYOUT', 'different key same amount', 'seller', pays[2]);
    }
  }

  // second e2e paid order for release+refund compose if first was refunded
  if (e2eSecret.length >= 16) {
    final setup2 = await ctx.rest(
      'POST',
      '/functions/v1/sec-fase2-e2e-oversell',
      jwt: ctx.buyerJwt,
      extra: {'x-fleaber-e2e-secret': e2eSecret},
      body: {
        'probe': 'setup_paid_order',
        'buyer_id': ctx.buyerId,
        'seller_id': ctx.sellerId,
        'initial_qty': 1,
      },
    );
    row('E2E_FIXTURE', 'setup_paid_order #2 for release path', 'e2e-secret', setup2);
    final sj = setup2.json;
    String? oid2;
    if (sj is Map) {
      oid2 = sj['order_id']?.toString();
      if (sj['order'] is Map) oid2 ??= (sj['order'] as Map)['id']?.toString();
    }
    if (oid2 != null && oid2.contains('-')) {
      final ship = await ctx.rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$oid2',
        jwt: ctx.sellerJwt,
        body: {'status': 'enviado'},
      );
      row('FSM', 'seller ship captured order', 'seller', ship);
      final conc = await ctx.rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$oid2',
        jwt: ctx.buyerJwt,
        body: {'status': 'concluido'},
      );
      row('FSM', 'buyer concluido captured', 'buyer', conc);
      final obs = await ctx.select(
        'orders',
        service: true,
        filter: 'id=eq.$oid2',
        select: 'id,status,wallet_release_processed_at,amount_paid_cents',
      );
      row('E2E', 'status after ship/concluido', 'service', obs);
      final relA = ctx.rpc('batata_release_seller_wallet_for_order', {'p_order_id': oid2}, jwt: ctx.buyerJwt);
      final relB = ctx.rpc('batata_release_seller_wallet_for_order', {'p_order_id': oid2}, jwt: ctx.buyerJwt);
      final rels = await Future.wait([relA, relB]);
      row('RACE', 'dual release 1', 'buyer', rels[0]);
      row('RACE', 'dual release 2', 'buyer', rels[1]);
      final wS = await ctx.select('wallets', service: true, filter: 'id=eq.${ctx.sellerId}', select: 'id,balance');
      row('WALLET', 'seller after dual release', 'service', wS);
      final rf = await ctx.edge('refund-order', {'order_id': oid2}, jwt: ctx.sellerJwt);
      row('REFUND', 'seller refund AFTER release', 'seller', rf);
      final wS2 = await ctx.select('wallets', service: true, filter: 'id=eq.${ctx.sellerId}', select: 'id,balance');
      final wB2 = await ctx.select('wallets', service: true, filter: 'id=eq.${ctx.buyerId}', select: 'id,balance');
      row('WALLET', 'seller after release+refund', 'service', wS2);
      row('WALLET', 'buyer after release+refund', 'service', wB2);
      final finalO = await ctx.select(
        'orders',
        service: true,
        filter: 'id=eq.$oid2',
        select:
            'id,status,amount_paid_cents,stripe_refund_id,wallet_release_processed_at,wallet_refund_processed_at',
      );
      row('E2E', 'final order release+refund', 'service', finalO);
    }
  }

  await writeOut('pass3.json', {
    'pass': 3,
    'notes': notes,
    'matrix': matrix,
    'findings': findings,
  });
  stdout.writeln('PASS3 done findings=${findings.length} matrix=${matrix.length}');
}
