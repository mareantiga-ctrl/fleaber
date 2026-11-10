// ignore_for_file: avoid_print
/// PASS 2/3 — invariantes, composição, races LIVE.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../live_ops_staging_client.dart';

void main() async {
  final e = loadLiveOpsStagingEnv();
  final url = normalizeSupabaseProjectUrl(envRequire(e, 'SUPABASE_URL'));
  if (!url.contains('fxdknzrqjenzqcvnwqqq')) {
    stderr.writeln('ABORT');
    exit(2);
  }
  final anon = envRequire(e, 'SUPABASE_ANON_KEY');
  final svc = envRequire(e, 'SUPABASE_SERVICE_ROLE_KEY');
  final buyerId = envRequire(e, 'LIVE_OPS_TEST_BUYER_ID');
  final sellerId = envRequire(e, 'LIVE_OPS_TEST_SELLER_ID');
  final otherSeller = '69104e91-6a00-40d9-a7c9-b1571422ae43';
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  final matrix = <Map<String, dynamic>>[];

  Future<http.Response> req(
    String method,
    String path, {
    String? token,
    Object? body,
    Map<String, String>? extra,
    bool service = false,
  }) {
    final key = service ? svc : anon;
    final headers = <String, String>{
      'apikey': key,
      'Authorization': 'Bearer ${service ? svc : (token ?? anon)}',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
      ...?extra,
    };
    final uri = Uri.parse('$url$path');
    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers);
      case 'POST':
        return http.post(uri, headers: headers, body: body == null ? null : jsonEncode(body));
      case 'PATCH':
        return http.patch(uri, headers: headers, body: body == null ? null : jsonEncode(body));
      case 'DELETE':
        return http.delete(uri, headers: headers);
      default:
        throw StateError(method);
    }
  }

  void rec(String surface, String attack, String identity, http.Response r, [dynamic extra]) {
    final row = {
      'surface': surface,
      'attack': attack,
      'identity': identity,
      'result': r.statusCode,
      'body': r.body.length > 1500 ? '${r.body.substring(0, 1500)}…' : r.body,
      if (extra != null) 'extra': extra,
    };
    matrix.add(row);
    final st = r.statusCode;
    final body = r.body;
    final interesting = (st >= 200 && st < 300 && body.isNotEmpty && body != '[]') ||
        st >= 500 ||
        (st == 200);
    if (interesting) {
      print('$identity $surface $attack → $st ${body.length > 220 ? body.substring(0, 220) : body}');
    }
  }

  dynamic j(http.Response r) {
    try {
      return jsonDecode(r.body);
    } catch (_) {
      return r.body;
    }
  }

  // restore V0 product price (fixture we mutated)
  await req('PATCH', '/rest/v1/products?id=eq.f85ded7d-c00a-4e70-8931-77a81d309bd7',
      service: true, body: {'price': 10});

  // snapshot wallets
  final wBuyer0 = j(await req('GET', '/rest/v1/wallets?id=eq.$buyerId&select=balance', service: true));
  final wSeller0 = j(await req('GET', '/rest/v1/wallets?id=eq.$sellerId&select=balance', service: true));

  // --- banking IDOR ---
  rec(
    'rpc/batata_seller_direct_payment_details',
    'buyer vs OTHER seller',
    'buyer',
    await req('POST', '/rest/v1/rpc/batata_seller_direct_payment_details',
        token: buyerTok, body: {'p_seller_id': otherSeller}),
  );

  // --- live_messages user chat IDOR ---
  rec(
    'live_messages',
    'SELECT kind=user other lives',
    'buyer',
    await req('GET',
        '/rest/v1/live_messages?kind=eq.user&select=id,live_id,user_id,body,kind&limit=10',
        token: buyerTok),
  );

  // --- raffle draw_seed of others ---
  rec(
    'live_raffles',
    'SELECT draw_seed other seller',
    'buyer',
    await req('GET',
        '/rest/v1/live_raffles?seller_id=eq.$otherSeller&select=id,status,draw_seed,title&limit=5',
        token: buyerTok),
  );

  // --- stripe events IDOR ---
  rec(
    'stripe_checkout_events',
    'SELECT buyer_id neq self',
    'buyer',
    await req('GET',
        '/rest/v1/stripe_checkout_events?buyer_id=neq.$buyerId&select=id,buyer_id,session_id,event&limit=5',
        token: buyerTok),
  );

  // --- chat IDOR ---
  final otherChat = j(await req('GET',
      '/rest/v1/chats?or=(user_a.eq.$otherSeller,user_b.eq.$otherSeller)&user_a=neq.$buyerId&user_b=neq.$buyerId&select=id,user_a,user_b&limit=1',
      service: true));
  String? otherChatId;
  if (otherChat is List && otherChat.isNotEmpty) {
    otherChatId = otherChat.first['id'] as String?;
    rec(
      'chats',
      'GET third-party chat',
      'buyer',
      await req('GET', '/rest/v1/chats?id=eq.$otherChatId&select=*', token: buyerTok),
    );
    rec(
      'chat_messages',
      'GET third-party chat messages',
      'buyer',
      await req('GET', '/rest/v1/chat_messages?chat_id=eq.$otherChatId&select=id,text,sender_id&limit=5',
          token: buyerTok),
    );
  }

  // --- reviews ---
  rec(
    'reviews',
    'INSERT without order',
    'buyer',
    await req('POST', '/rest/v1/reviews', token: buyerTok, body: {
      'buyer_id': sellerId,
      'target_id': sellerId,
      'stars': 5,
      'comment': 'hostile',
      'author_role': 'vendedor',
    }),
  );
  rec(
    'reviews',
    'INSERT with pending order',
    'buyer',
    await req('POST', '/rest/v1/reviews', token: buyerTok, body: {
      'order_id': '1eee5383-20e0-4e8e-b34f-0f915c48cb65',
      'target_id': sellerId,
      'stars': 1,
      'comment': 'hostile pending',
      'author_role': 'comprador',
    }),
  );
  rec(
    'reviews',
    'INSERT duplicate on paid order as seller role',
    'buyer',
    await req('POST', '/rest/v1/reviews', token: buyerTok, body: {
      'order_id': '6a3268c5-44ea-4a9e-b87e-b4ca13887131',
      'target_id': sellerId,
      'stars': 5,
      'comment': 'hostile paid',
      'author_role': 'vendedor',
    }),
  );

  // --- reservation accept as buyer ---
  rec(
    'live_reservation_requests',
    'PATCH pending → accepted as buyer',
    'buyer',
    await req(
      'PATCH',
      '/rest/v1/live_reservation_requests?id=eq.d5c84b3c-17e4-412d-9d8a-ef3fc022703f',
      token: buyerTok,
      body: {'status': 'accepted', 'requested_qty': 99},
    ),
  );

  // --- offer oneshot ---
  rec(
    'product_offers',
    'INSERT amount 0.01 on seller product',
    'buyer',
    await req('POST', '/rest/v1/product_offers', token: buyerTok, body: {
      'product_id': 'f85ded7d-c00a-4e70-8931-77a81d309bd7',
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'amount': 0.01,
      'status': 'accepted',
    }),
  );

  // --- shipping PATCH sealed hand → carrier (want cheaper? other way) ---
  rec(
    'orders',
    'PATCH sealed hand → carrier',
    'buyer',
    await req('PATCH', '/rest/v1/orders?id=eq.1eee5383-20e0-4e8e-b34f-0f915c48cb65',
        token: buyerTok, body: {'shipping_method': 'carrier'}),
  );
  rec(
    'orders',
    'PATCH sealed hand → carrier as seller',
    'seller',
    await req('PATCH', '/rest/v1/orders?id=eq.1eee5383-20e0-4e8e-b34f-0f915c48cb65',
        token: sellerTok, body: {'shipping_method': 'carrier'}),
  );

  // --- off-platform: buyer creates MB WAY, seller marks pago, wallet? ---
  final mbIns = await req('POST', '/rest/v1/orders', token: buyerTok, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': 'f85ded7d-c00a-4e70-8931-77a81d309bd7',
    'status': 'reserva_pendente',
    'quantity': 1,
    'payment_method': 'mb way',
    'shipping_method': 'hand',
  });
  rec('orders', 'INSERT mb way pending', 'buyer', mbIns);
  String? mbId;
  final mbBody = j(mbIns);
  if (mbBody is List && mbBody.isNotEmpty) mbId = mbBody.first['id'] as String?;
  if (mbId != null) {
    rec(
      'orders',
      'seller PATCH mb way → reservado',
      'seller',
      await req('PATCH', '/rest/v1/orders?id=eq.$mbId', token: sellerTok, body: {'status': 'reservado'}),
    );
    rec(
      'orders',
      'seller PATCH mb way reservado → pago',
      'seller',
      await req('PATCH', '/rest/v1/orders?id=eq.$mbId', token: sellerTok, body: {'status': 'pago'}),
    );
    rec(
      'rpc/batata_release_seller_wallet_for_order',
      'seller release after fake mb way pago',
      'seller',
      await req('POST', '/rest/v1/rpc/batata_release_seller_wallet_for_order',
          token: sellerTok, body: {'p_order_id': mbId}),
    );
  }

  // --- checkout Edge ---
  Future<http.Response> edge(String fn, Object body, {String? token, String qs = '', String method = 'POST'}) {
    final headers = {
      'apikey': anon,
      'Authorization': 'Bearer ${token ?? anon}',
      'Content-Type': 'application/json',
    };
    final uri = Uri.parse('$url/functions/v1/$fn$qs');
    if (method == 'GET') return http.get(uri, headers: headers);
    return http.post(uri, headers: headers, body: jsonEncode(body));
  }

  // catalog freeze: order 295610ed sealed at 10€ after catalog 0.01 then restored 10
  rec(
    'edge/create-payment-intent',
    'checkout sealed 10€ order after catalog drop attempt amount=50',
    'buyer',
    await edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': '295610ed-818f-4913-a32b-76cadd76f1ad',
      'amount': 50,
      'quantity': 99,
      'shipping_method': 'hand',
    }, token: buyerTok),
  );

  rec(
    'edge/create-payment-intent',
    'prize_shipping on normal pending',
    'buyer',
    await edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': '1eee5383-20e0-4e8e-b34f-0f915c48cb65',
      'prize_shipping': true,
      'shipping_method': 'hand',
    }, token: buyerTok),
  );

  rec(
    'edge/create-payment-intent',
    'pending order amount=1 shipping carrier vs sealed hand',
    'buyer',
    await edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': '1eee5383-20e0-4e8e-b34f-0f915c48cb65',
      'amount': 1,
      'shipping_method': 'carrier',
    }, token: buyerTok),
  );

  rec(
    'edge/create-live-tip-checkout',
    'amount_eur=1',
    'buyer',
    await edge('create-live-tip-checkout', {
      'seller_id': sellerId,
      'amount_eur': 1,
    }, token: buyerTok),
  );

  // dual payout different keys 1 cent
  final k1 = 'race-payout-a-${DateTime.now().millisecondsSinceEpoch}';
  final k2 = 'race-payout-b-${DateTime.now().millisecondsSinceEpoch}';
  final payouts = await Future.wait([
    edge('create-connect-account', {'amount': 1, 'idempotency_key': k1}, token: buyerTok),
    edge('create-connect-account', {'amount': 1, 'idempotency_key': k2}, token: buyerTok),
  ]);
  rec('edge/create-connect-account', 'dual payout key A', 'buyer', payouts[0]);
  rec('edge/create-connect-account', 'dual payout key B', 'buyer', payouts[1]);
  rec(
    'edge/create-connect-account',
    'retry same key A',
    'buyer',
    await edge('create-connect-account', {'amount': 1, 'idempotency_key': k1}, token: buyerTok),
  );

  // --- STOCK=1 race ---
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final prodRace = j(await req('POST', '/rest/v1/products', service: true, body: {
    'seller_id': sellerId,
    'title': 'RT-RACE-$stamp',
    'price': 5.0,
    'quantity': 1,
    'list_on_marketplace': true,
    'available_for_live': false,
    'is_sold': false,
    'ref_code': 'RACE$stamp',
  }));
  String? racePid;
  if (prodRace is List && prodRace.isNotEmpty) {
    racePid = prodRace.first['id'] as String;
  } else if (prodRace is Map && prodRace['id'] != null) {
    racePid = prodRace['id'] as String;
  }
  print('race_product=$racePid');
  if (racePid != null) {
    final inserts = await Future.wait(List.generate(10, (i) {
      return req('POST', '/rest/v1/orders', token: buyerTok, body: {
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': racePid,
        'status': 'reserva_pendente',
        'quantity': 1,
        'payment_method': 'Pagamento na app',
        'shipping_method': 'hand',
      });
    }));
    final created = <String>[];
    for (var i = 0; i < inserts.length; i++) {
      rec('orders', 'race insert $i stock=1', 'buyer', inserts[i]);
      final b = j(inserts[i]);
      if (inserts[i].statusCode == 201 && b is List && b.isNotEmpty) {
        created.add(b.first['id'] as String);
      }
    }
    print('race_created_orders=${created.length} ids=$created');

    if (created.length >= 2) {
      final sessions = await Future.wait([
        edge('create-payment-intent', {
          'buyer_id': buyerId,
          'order_id': created[0],
          'amount': 1,
          'shipping_method': 'hand',
        }, token: buyerTok),
        edge('create-payment-intent', {
          'buyer_id': buyerId,
          'order_id': created[1],
          'amount': 1,
          'shipping_method': 'hand',
        }, token: buyerTok),
      ]);
      rec('edge/create-payment-intent', 'race session order0', 'buyer', sessions[0]);
      rec('edge/create-payment-intent', 'race session order1', 'buyer', sessions[1]);
    }

    final held = await req('POST', '/rest/v1/rpc/batata_product_held_qty',
        token: buyerTok, body: {'p_product_id': racePid});
    rec('rpc/batata_product_held_qty', 'after race inserts', 'buyer', held);

    final prodAfter = await req('GET',
        '/rest/v1/products?id=eq.$racePid&select=id,quantity,is_sold,price',
        service: true);
    rec('products', 'observe stock after race', 'service_observe', prodAfter);

    // cleanup pending race orders
    for (final id in created) {
      await req('PATCH', '/rest/v1/orders?id=eq.$id', service: true, body: {'status': 'cancelado'});
    }
  }

  // --- storage objects ---
  rec('storage', 'list chat_media root', 'buyer',
      await req('POST', '/storage/v1/object/list/chat_media', token: buyerTok, body: {
        'prefix': '',
        'limit': 10,
      }));
  rec('storage', 'list chat_media other seller prefix', 'buyer',
      await req('POST', '/storage/v1/object/list/chat_media', token: buyerTok, body: {
        'prefix': 'product_photos/$otherSeller',
        'limit': 10,
      }));
  rec('storage', 'list product_photos', 'anon',
      await req('POST', '/storage/v1/object/list/product_photos', body: {'prefix': '', 'limit': 5}));

  // --- GET settle with leaked session from own events ---
  rec(
    'edge/create-payment-intent',
    'GET settle known cs_test from own events',
    'anon',
    await edge(
      'create-payment-intent',
      {},
      method: 'GET',
      qs: '?checkout_return=success&session_id=cs_test_a1tfykIgkmKntJhy7Xf6cXxAh9OP0plkbH73UChNQtNGU2FbftL1wc33Xq',
    ),
  );

  // --- dispute IDOR ---
  rec(
    'order_disputes',
    'INSERT dispute on third-party order',
    'buyer',
    await req('POST', '/rest/v1/order_disputes', token: buyerTok, body: {
      'order_id': '92b6dc7f-209f-45ad-a8a1-20159fdddcbf',
      'buyer_id': buyerId,
      'reason': 'outro',
      'description': 'hostile',
    }),
  );

  // wallets after
  final wBuyer1 = j(await req('GET', '/rest/v1/wallets?id=eq.$buyerId&select=balance', service: true));
  final wSeller1 = j(await req('GET', '/rest/v1/wallets?id=eq.$sellerId&select=balance', service: true));

  // observe mb way order final
  Map<String, dynamic>? mbFinal;
  if (mbId != null) {
    final r = j(await req('GET',
        '/rest/v1/orders?id=eq.$mbId&select=id,status,amount_paid_cents,wallet_release_processed_at,stock_units_applied,payment_method',
        service: true));
    if (r is List && r.isNotEmpty) mbFinal = Map<String, dynamic>.from(r.first as Map);
  }

  final out = {
    'wallets': {'buyer0': wBuyer0, 'buyer1': wBuyer1, 'seller0': wSeller0, 'seller1': wSeller1},
    'mb_way_order': mbFinal,
    'race_product': racePid,
    'matrix': matrix,
  };
  File('tool/redteam_blind_indep_20260830/out/02_pass23.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  print('wallets buyer $wBuyer0 → $wBuyer1 seller $wSeller0 → $wSeller1');
  print('mb_final=$mbFinal');
  print('matrix=${matrix.length}');
}
