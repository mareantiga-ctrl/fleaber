// ignore_for_file: avoid_print
/// PASS 1 — ataques hostis LIVE (JWT/anon). service_role só observa.
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
  final sb = LiveOpsStagingClient(url: url, anonKey: anon, serviceRoleKey: svc);
  final buyerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_BUYER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
  );
  final sellerTok = await sb.signIn(
    email: envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL'),
    password: envRequire(e, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
  );

  final findings = <Map<String, dynamic>>[];
  final matrix = <Map<String, dynamic>>[];

  Future<http.Response> req(
    String method,
    String path, {
    String? token,
    Object? body,
    Map<String, String>? extra,
  }) {
    final headers = <String, String>{
      'apikey': anon,
      'Authorization': 'Bearer ${token ?? anon}',
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

  Future<http.Response> svcReq(String method, String path, {Object? body}) {
    final headers = <String, String>{
      'apikey': svc,
      'Authorization': 'Bearer $svc',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
    final uri = Uri.parse('$url$path');
    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers);
      case 'POST':
        return http.post(uri, headers: headers, body: body == null ? null : jsonEncode(body));
      case 'PATCH':
        return http.patch(uri, headers: headers, body: body == null ? null : jsonEncode(body));
      default:
        throw StateError(method);
    }
  }

  void rec({
    required String surface,
    required String attack,
    required String identity,
    required http.Response r,
    String? impact,
    String? severity,
    String? token,
  }) {
    final row = {
      'surface': surface,
      'attack': attack,
      'identity': identity,
      'result': r.statusCode,
      'body': r.body.length > 1200 ? '${r.body.substring(0, 1200)}…' : r.body,
      if (impact != null) 'impact': impact,
      if (severity != null) 'severity': severity,
    };
    matrix.add(row);
    if (severity != null) findings.add(row);
  }

  // --- observe fixtures (service_role) ---
  final walletBeforeBuyer = jsonDecode(
    (await svcReq('GET', '/rest/v1/wallets?id=eq.$buyerId&select=id,balance')).body,
  );
  final walletBeforeSeller = jsonDecode(
    (await svcReq('GET', '/rest/v1/wallets?id=eq.$sellerId&select=id,balance')).body,
  );

  final thirdOrders = jsonDecode((await svcReq(
    'GET',
    '/rest/v1/orders?select=id,buyer_id,seller_id,status,amount_paid_cents,price_total&buyer_id=neq.$buyerId&seller_id=neq.$sellerId&limit=3',
  )).body) as List;

  final sellerProduct = jsonDecode((await svcReq(
    'GET',
    '/rest/v1/products?seller_id=eq.$sellerId&select=id,title,price,quantity,is_sold&limit=1',
  )).body) as List;

  final otherProduct = jsonDecode((await svcReq(
    'GET',
    '/rest/v1/products?seller_id=neq.$sellerId&seller_id=neq.$buyerId&select=id,seller_id,title,price,quantity&limit=1',
  )).body) as List;

  final liveItem = jsonDecode((await svcReq(
    'GET',
    '/rest/v1/live_items?select=id,live_id,seller_id,status,price,product_id&limit=1',
  )).body) as List;

  final paidOrder = jsonDecode((await svcReq(
    'GET',
    '/rest/v1/orders?buyer_id=eq.$buyerId&seller_id=eq.$sellerId&status=eq.pago&select=id,status,amount_paid_cents,price_total,quantity,product_id,stripe_payment_intent_id&limit=1',
  )).body) as List;

  final pendingOrder = jsonDecode((await svcReq(
    'GET',
    '/rest/v1/orders?buyer_id=eq.$buyerId&seller_id=eq.$sellerId&status=in.(reserva_pendente,reservado,aguarda_confirmacao,aguarda_pagamento)&select=id,status,price_total,quantity,product_id,payment_method,shipping_method,contract_unit_cents,contract_qty&limit=3&order=created_at.desc',
  )).body) as List;

  File('tool/redteam_blind_indep_20260830/out/observe_fixtures.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'wallet_buyer': walletBeforeBuyer,
      'wallet_seller': walletBeforeSeller,
      'third_orders': thirdOrders,
      'seller_product': sellerProduct,
      'other_product': otherProduct,
      'live_item': liveItem,
      'paid_order': paidOrder,
      'pending_order': pendingOrder,
    }),
  );

  final prodId = sellerProduct.isNotEmpty ? sellerProduct.first['id'] as String : null;
  final otherProdId = otherProduct.isNotEmpty ? otherProduct.first['id'] as String : null;
  final otherProdSeller = otherProduct.isNotEmpty ? otherProduct.first['seller_id'] as String : null;
  final liId = liveItem.isNotEmpty ? liveItem.first['id'] as String : null;
  final thirdOrderId = thirdOrders.isNotEmpty ? thirdOrders.first['id'] as String : null;
  final paidId = paidOrder.isNotEmpty ? paidOrder.first['id'] as String : null;
  final pendingId = pendingOrder.isNotEmpty ? pendingOrder.first['id'] as String : null;

  print('fixtures prod=$prodId other=$otherProdId li=$liId third=$thirdOrderId paid=$paidId pending=$pendingId');

  // ========== RLS money ==========
  rec(
    surface: 'wallets',
    attack: 'SELECT other wallet by id',
    identity: 'buyer',
    r: await req('GET', '/rest/v1/wallets?id=eq.$sellerId&select=*', token: buyerTok),
  );
  rec(
    surface: 'wallets',
    attack: 'PATCH own balance += 9999',
    identity: 'buyer',
    r: await req('PATCH', '/rest/v1/wallets?id=eq.$buyerId', token: buyerTok, body: {'balance': 9999.99}),
  );
  rec(
    surface: 'wallets',
    attack: 'PATCH seller balance',
    identity: 'buyer',
    r: await req('PATCH', '/rest/v1/wallets?id=eq.$sellerId', token: buyerTok, body: {'balance': 1}),
  );
  rec(
    surface: 'wallets',
    attack: 'INSERT wallet with balance 500',
    identity: 'buyer',
    r: await req('POST', '/rest/v1/wallets', token: buyerTok, body: {
      'id': buyerId,
      'balance': 500,
    }),
  );
  rec(
    surface: 'wallet_transactions',
    attack: 'INSERT credit type venda',
    identity: 'buyer',
    r: await req('POST', '/rest/v1/wallet_transactions', token: buyerTok, body: {
      'wallet_id': buyerId,
      'amount': 100,
      'type': 'reembolso',
      'description': 'hostile',
    }),
  );
  rec(
    surface: 'wallet_payout_ledger',
    attack: 'INSERT transferred row',
    identity: 'buyer',
    r: await req('POST', '/rest/v1/wallet_payout_ledger', token: buyerTok, body: {
      'idempotency_key': 'hostile-payout-${DateTime.now().millisecondsSinceEpoch}',
      'user_id': buyerId,
      'amount_cents': 100,
      'amount_eur': 1,
      'status': 'transferred',
    }),
  );

  // ========== orders money / FSM ==========
  rec(
    surface: 'orders',
    attack: 'INSERT status=pago + stripe + amount_paid',
    identity: 'buyer',
    r: await req('POST', '/rest/v1/orders', token: buyerTok, body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': prodId,
      'status': 'pago',
      'price_total': 0.01,
      'quantity': 1,
      'amount_paid_cents': 99999,
      'stripe_payment_intent_id': 'pi_hostile_fake',
      'stripe_checkout_session_id': 'cs_hostile_fake',
      'payment_method': 'seguro fleaber',
    }),
  );
  rec(
    surface: 'orders',
    attack: 'INSERT as seller status=pago off-platform',
    identity: 'seller',
    r: await req('POST', '/rest/v1/orders', token: sellerTok, body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': prodId,
      'status': 'pago',
      'price_total': 1,
      'quantity': 1,
      'payment_method': 'mb way',
    }),
  );
  rec(
    surface: 'orders',
    attack: 'INSERT qty=999999',
    identity: 'buyer',
    r: await req('POST', '/rest/v1/orders', token: buyerTok, body: {
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': prodId,
      'status': 'reserva_pendente',
      'price_total': 1,
      'quantity': 999999,
    }),
  );
  rec(
    surface: 'orders',
    attack: 'INSERT with other seller product + self as seller',
    identity: 'buyer',
    r: await req('POST', '/rest/v1/orders', token: buyerTok, body: {
      'buyer_id': buyerId,
      'seller_id': buyerId,
      'product_id': otherProdId,
      'status': 'reserva_pendente',
      'price_total': 0.5,
      'quantity': 1,
    }),
  );
  rec(
    surface: 'orders',
    attack: 'SELECT third-party order by id',
    identity: 'buyer',
    r: await req('GET', '/rest/v1/orders?id=eq.$thirdOrderId&select=*', token: buyerTok),
  );
  if (pendingId != null) {
    rec(
      surface: 'orders',
      attack: 'PATCH pending → pago as buyer',
      identity: 'buyer',
      r: await req('PATCH', '/rest/v1/orders?id=eq.$pendingId', token: buyerTok, body: {'status': 'pago'}),
    );
    rec(
      surface: 'orders',
      attack: 'PATCH pending amount_paid + stripe',
      identity: 'buyer',
      r: await req('PATCH', '/rest/v1/orders?id=eq.$pendingId', token: buyerTok, body: {
        'amount_paid_cents': 1,
        'stripe_payment_intent_id': 'pi_x',
      }),
    );
    rec(
      surface: 'orders',
      attack: 'PATCH pending quantity=99',
      identity: 'buyer',
      r: await req('PATCH', '/rest/v1/orders?id=eq.$pendingId', token: buyerTok, body: {'quantity': 99}),
    );
    rec(
      surface: 'orders',
      attack: 'PATCH pending price_total=0.01',
      identity: 'buyer',
      r: await req('PATCH', '/rest/v1/orders?id=eq.$pendingId', token: buyerTok, body: {'price_total': 0.01}),
    );
    rec(
      surface: 'orders',
      attack: 'PATCH pending → pago as seller (platform pm)',
      identity: 'seller',
      r: await req('PATCH', '/rest/v1/orders?id=eq.$pendingId', token: sellerTok, body: {'status': 'pago'}),
    );
  }
  if (paidId != null) {
    rec(
      surface: 'orders',
      attack: 'PATCH paid → cancelado as buyer',
      identity: 'buyer',
      r: await req('PATCH', '/rest/v1/orders?id=eq.$paidId', token: buyerTok, body: {'status': 'cancelado'}),
    );
    rec(
      surface: 'orders',
      attack: 'PATCH paid swap buyer_id',
      identity: 'buyer',
      r: await req('PATCH', '/rest/v1/orders?id=eq.$paidId', token: buyerTok, body: {'buyer_id': sellerId}),
    );
  }

  // ========== catalog ==========
  if (otherProdId != null) {
    rec(
      surface: 'products',
      attack: 'PATCH other seller price=0.01',
      identity: 'buyer',
      r: await req('PATCH', '/rest/v1/products?id=eq.$otherProdId', token: buyerTok, body: {'price': 0.01}),
    );
    rec(
      surface: 'products',
      attack: 'PATCH other seller quantity=999',
      identity: 'seller',
      r: await req('PATCH', '/rest/v1/products?id=eq.$otherProdId', token: sellerTok, body: {'quantity': 999}),
    );
  }
  if (prodId != null) {
    rec(
      surface: 'products',
      attack: 'PATCH own product price after listing (seller)',
      identity: 'seller',
      r: await req('PATCH', '/rest/v1/products?id=eq.$prodId', token: sellerTok, body: {'price': 0.01}),
    );
  }

  // ========== profiles / authz ==========
  rec(
    surface: 'profiles',
    attack: 'PATCH user_type=admin',
    identity: 'buyer',
    r: await req('PATCH', '/rest/v1/profiles?id=eq.$buyerId', token: buyerTok, body: {'user_type': 'admin'}),
  );
  rec(
    surface: 'profiles',
    attack: 'PATCH user_type=vendedor',
    identity: 'buyer',
    r: await req('PATCH', '/rest/v1/profiles?id=eq.$buyerId', token: buyerTok, body: {'user_type': 'vendedor'}),
  );
  rec(
    surface: 'profiles',
    attack: 'PATCH user_type=admim',
    identity: 'buyer',
    r: await req('PATCH', '/rest/v1/profiles?id=eq.$buyerId', token: buyerTok, body: {'user_type': 'admim'}),
  );
  rec(
    surface: 'profiles',
    attack: 'SELECT seller profile by id',
    identity: 'buyer',
    r: await req('GET', '/rest/v1/profiles?id=eq.$sellerId&select=*', token: buyerTok),
  );
  rec(
    surface: 'profiles',
    attack: 'SELECT * all profiles',
    identity: 'buyer',
    r: await req('GET', '/rest/v1/profiles?select=id,full_name,user_type,phone,email,iban&limit=5', token: buyerTok),
  );

  // ========== lives / mux ==========
  rec(
    surface: 'lives',
    attack: 'SELECT mux_stream_key,stream_key',
    identity: 'buyer',
    r: await req('GET', '/rest/v1/lives?select=id,mux_stream_key,stream_key,mux_playback_id&limit=3', token: buyerTok),
  );
  rec(
    surface: 'lives',
    attack: 'SELECT id,title,status',
    identity: 'buyer',
    r: await req('GET', '/rest/v1/lives?select=id,title,status,is_active&limit=3', token: buyerTok),
  );
  rec(
    surface: 'lives',
    attack: 'SELECT stream keys as seller',
    identity: 'seller',
    r: await req('GET', '/rest/v1/lives?select=id,mux_stream_key,stream_key&seller_id=eq.$sellerId&limit=3', token: sellerTok),
  );
  rec(
    surface: 'hub_lives_public',
    attack: 'SELECT *',
    identity: 'anon',
    r: await req('GET', '/rest/v1/hub_lives_public?select=*&limit=3'),
  );
  rec(
    surface: 'hub_lives_public',
    attack: 'SELECT *',
    identity: 'buyer',
    r: await req('GET', '/rest/v1/hub_lives_public?select=*&limit=3', token: buyerTok),
  );

  // ========== staff helpers ==========
  rec(
    surface: 'seller_helpers',
    attack: 'INSERT self as seller staff with all perms',
    identity: 'buyer',
    r: await req('POST', '/rest/v1/seller_helpers', token: buyerTok, body: {
      'seller_id': sellerId,
      'helper_user_id': buyerId,
      'display_name': 'hostile',
      'active': true,
      'invitation_status': 'accepted',
      'permissions': {
        'can_mark_items_sold': true,
        'can_manage_reservations': true,
        'can_change_current_item': true,
      },
    }),
  );

  // ========== reviews / chat / disputes ==========
  rec(
    surface: 'reviews',
    attack: 'INSERT review without purchase',
    identity: 'buyer',
    r: await req('POST', '/rest/v1/reviews', token: buyerTok, body: {
      'author_id': buyerId,
      'target_user_id': sellerId,
      'rating': 1,
      'comment': 'hostile',
      'role': 'buyer',
    }),
  );
  rec(
    surface: 'reviews',
    attack: 'INSERT as seller about self',
    identity: 'seller',
    r: await req('POST', '/rest/v1/reviews', token: sellerTok, body: {
      'author_id': sellerId,
      'target_user_id': buyerId,
      'rating': 5,
      'comment': 'self',
      'role': 'buyer',
    }),
  );
  for (final t in [
    'chats',
    'messages',
    'chat_messages',
    'order_disputes',
    'disputes',
    'live_messages',
    'live_reservation_requests',
    'product_offers',
    'live_raffles',
    'live_raffle_winners',
    'live_tips',
    'ps_device_tokens',
    'notifications',
    'favorites',
    'follows',
    'seller_banking',
    'banking_details',
    'stripe_checkout_events',
    'fleaber_commissions',
  ]) {
    rec(
      surface: t,
      attack: 'SELECT * limit 3',
      identity: 'buyer',
      r: await req('GET', '/rest/v1/$t?select=*&limit=3', token: buyerTok),
    );
    rec(
      surface: t,
      attack: 'SELECT * limit 3',
      identity: 'anon',
      r: await req('GET', '/rest/v1/$t?select=*&limit=3'),
    );
  }

  // ========== RPCs ==========
  final rpcTries = <Map<String, dynamic>>[
    {'fn': 'batata_wallet_payout_debit', 'body': {'p_user_id': sellerId, 'p_amount_cents': 1, 'p_idempotency_key': 'hostilekey99'}},
    {'fn': 'batata_wallet_payout_finish', 'body': {'p_idempotency_key': 'hostilekey99', 'p_stripe_transfer_id': 'tr_x', 'p_failed': false}},
    {'fn': 'batata_credit_wallet_once', 'body': {'p_wallet_id': buyerId, 'p_order_id': paidId, 'p_amount': 50, 'p_type': 'venda', 'p_description': 'x'}},
    {'fn': 'batata_debit_wallet_once', 'body': {'p_wallet_id': sellerId, 'p_order_id': paidId, 'p_amount': 0.01, 'p_type': 'levantamento'}},
    {'fn': 'batata_ensure_wallet', 'body': {'p_user_id': sellerId}},
    {'fn': 'batata_wallet_apply_tip_once', 'body': {'p_wallet_id': buyerId, 'p_tip_id': buyerId, 'p_amount': 10, 'p_type': 'gorjeta_recebida', 'p_description': 'x'}},
    {'fn': 'batata_send_live_tip_from_wallet', 'body': {'p_live_id': liId, 'p_seller_id': sellerId, 'p_amount': 1, 'p_message': 'x'}},
    {'fn': 'batata_release_seller_wallet_for_order', 'body': {'p_order_id': paidId}},
    {'fn': 'batata_refund_buyer_wallet_for_order', 'body': {'p_order_id': paidId}},
    {'fn': 'batata_clawback_seller_wallet_for_order', 'body': {'p_order_id': paidId}},
    {'fn': 'batata_mark_live_item_sold', 'body': {'p_live_item_id': liId}},
    {'fn': 'batata_live_reconcile_stripe_order', 'body': {'p_order_id': paidId}},
    {'fn': 'batata_sync_live_item_for_order', 'body': {'p_order_id': paidId}},
    {'fn': 'batata_tick_live_raffle', 'body': {'p_raffle_id': buyerId}},
    {'fn': 'batata_create_raffle_prize_order', 'body': {'p_raffle_id': buyerId, 'p_winner_id': buyerId, 'p_qty': 1}},
    {'fn': 'batata_find_user_id_by_email', 'body': {'p_email': envRequire(e, 'LIVE_OPS_TEST_SELLER_EMAIL')}},
    {'fn': 'batata_seller_direct_payment_details', 'body': {'p_seller_id': sellerId}},
    {'fn': 'batata_create_seller_device_token', 'body': {'p_label': 'hostile'}},
    {'fn': 'batata_ps_claim_pairing', 'body': {'p_code': '000000', 'p_device_id': 'x'}},
    {'fn': 'batata_product_held_qty', 'body': {'p_product_id': prodId}},
    {'fn': 'batata_product_checkout_available', 'body': {'p_product_id': prodId, 'p_qty': 1}},
    {'fn': 'batata_order_wallet_reembolso_cents', 'body': {'p_order_id': paidId}},
    {'fn': 'batata_generate_auto_feedback', 'body': {}},
    {'fn': 'batata_recompact_reservation_queue', 'body': {'p_live_item_id': liId}},
    {'fn': 'batata_recompute_live_item_status', 'body': {'p_live_item_id': liId}},
    {'fn': 'exec_sql', 'body': {'query': 'select 1'}},
    {'fn': 'sql', 'body': {'q': 'select 1'}},
  ];

  for (final t in rpcTries) {
    final fn = t['fn'] as String;
    final body = Map<String, dynamic>.from(t['body'] as Map);
    for (final who in ['anon', 'buyer', 'seller']) {
      final tok = who == 'anon' ? null : (who == 'buyer' ? buyerTok : sellerTok);
      final r = await req('POST', '/rest/v1/rpc/$fn', token: tok, body: body);
      rec(surface: 'rpc/$fn', attack: 'call with hostile/ids', identity: who, r: r);
    }
  }

  // ========== Edge ==========
  Future<http.Response> edge(
    String fn,
    Object body, {
    String? token,
    String method = 'POST',
    String qs = '',
    Map<String, String>? extra,
  }) {
    final headers = {
      'apikey': anon,
      'Authorization': 'Bearer ${token ?? anon}',
      'Content-Type': 'application/json',
      ...?extra,
    };
    final uri = Uri.parse('$url/functions/v1/$fn$qs');
    if (method == 'GET') return http.get(uri, headers: headers);
    return http.post(uri, headers: headers, body: jsonEncode(body));
  }

  rec(
    surface: 'edge/create-mux-live',
    attack: 'buyer create live with valid title',
    identity: 'buyer',
    r: await edge('create-mux-live', {'title': 'Hostile Live Title'}, token: buyerTok),
  );
  rec(
    surface: 'edge/create-payment-intent',
    attack: 'amount=50 vs order, swapped seller, prize_shipping',
    identity: 'buyer',
    r: await edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': pendingId ?? paidId,
      'amount': 50,
      'quantity': 99,
      'item_price': 0.01,
      'seller_id': buyerId,
      'product_id': otherProdId,
      'prize_shipping': true,
      'shipping_method': 'hand',
    }, token: buyerTok),
  );
  rec(
    surface: 'edge/create-payment-intent',
    attack: 'seller checkout as buyer_id in body',
    identity: 'seller',
    r: await edge('create-payment-intent', {
      'buyer_id': buyerId,
      'order_id': pendingId ?? paidId,
      'amount': 50,
    }, token: sellerTok),
  );
  rec(
    surface: 'edge/create-payment-intent',
    attack: 'bag mix order + foreign product line',
    identity: 'buyer',
    r: await edge('create-payment-intent', {
      'buyer_id': buyerId,
      'bag_checkout': true,
      'bag_lines': [
        {'order_id': pendingId ?? paidId, 'quantity': 1, 'line_total_cents': 1},
        {'order_id': thirdOrderId, 'quantity': 1, 'line_total_cents': 1},
      ],
    }, token: buyerTok),
  );
  rec(
    surface: 'edge/refund-order',
    attack: 'buyer refund own order',
    identity: 'buyer',
    r: await edge('refund-order', {'order_id': paidId}, token: buyerTok),
  );
  rec(
    surface: 'edge/refund-order',
    attack: 'seller refund third-party order',
    identity: 'seller',
    r: await edge('refund-order', {'order_id': thirdOrderId}, token: sellerTok),
  );
  rec(
    surface: 'edge/create-live-tip-checkout',
    attack: 'amount_eur=0.5 to self seller_id',
    identity: 'buyer',
    r: await edge('create-live-tip-checkout', {
      'seller_id': sellerId,
      'amount_eur': 0.5,
      'live_id': liId,
    }, token: buyerTok),
  );
  rec(
    surface: 'edge/create-live-tip-checkout',
    attack: 'amount_eur=5000',
    identity: 'buyer',
    r: await edge('create-live-tip-checkout', {
      'seller_id': sellerId,
      'amount_eur': 5000,
    }, token: buyerTok),
  );
  rec(
    surface: 'edge/create-connect-account',
    attack: 'payout amount=1 cents with new key',
    identity: 'buyer',
    r: await edge('create-connect-account', {
      'user_id': sellerId,
      'amount': 1,
      'idempotency_key': 'hostile-payout-${DateTime.now().millisecondsSinceEpoch}',
    }, token: buyerTok),
  );
  rec(
    surface: 'edge/create-payment-intent',
    attack: 'GET settle without session',
    identity: 'anon',
    r: await edge('create-payment-intent', {}, method: 'GET', qs: '?checkout_return=success&session_id=cs_test_fake'),
  );
  rec(
    surface: 'edge/create-payment-intent',
    attack: 'fase2_e2e_settle as buyer JWT',
    identity: 'buyer',
    r: await edge('create-payment-intent', {
      'order_id': paidId,
      'payment_intent_id': 'pi_fake',
    }, token: buyerTok, qs: '?fase2_e2e_settle=1'),
  );
  rec(
    surface: 'edge/complete-mux-live',
    attack: 'buyer complete random live',
    identity: 'buyer',
    r: await edge('complete-mux-live', {'live_id': liId}, token: buyerTok),
  );
  rec(
    surface: 'edge/livekit-mux-publish',
    attack: 'buyer step=token',
    identity: 'buyer',
    r: await edge('livekit-mux-publish', {'live_id': liId, 'step': 'token'}, token: buyerTok),
  );
  rec(
    surface: 'edge/ps-pairing-claim',
    attack: 'code 000000',
    identity: 'anon',
    r: await edge('ps-pairing-claim', {'code': '000000', 'device_id': 'hostile'}),
  );
  rec(
    surface: 'edge/ingest-ocr-reservation',
    attack: 'fake device token',
    identity: 'anon',
    r: await edge('ingest-ocr-reservation', {
      'live_id': liId,
      'ocr_line_hash': 'abcdefghijkl',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'ref_number': 1,
    }, extra: {'x-device-token': 'hostile-token'}),
  );

  // storage
  rec(
    surface: 'storage',
    attack: 'list buckets',
    identity: 'buyer',
    r: await req('GET', '/storage/v1/bucket', token: buyerTok),
  );
  rec(
    surface: 'storage',
    attack: 'list buckets',
    identity: 'anon',
    r: await req('GET', '/storage/v1/bucket'),
  );

  // wallet after
  final walletAfterBuyer = jsonDecode(
    (await svcReq('GET', '/rest/v1/wallets?id=eq.$buyerId&select=id,balance')).body,
  );
  final walletAfterSeller = jsonDecode(
    (await svcReq('GET', '/rest/v1/wallets?id=eq.$sellerId&select=id,balance')).body,
  );

  final out = {
    'wallet_before_buyer': walletBeforeBuyer,
    'wallet_after_buyer': walletAfterBuyer,
    'wallet_before_seller': walletBeforeSeller,
    'wallet_after_seller': walletAfterSeller,
    'matrix': matrix,
    'flagged': findings,
  };
  File('tool/redteam_blind_indep_20260830/out/01_hostile.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));

  print('matrix=${matrix.length}');
  // print interesting (not 401/403/404/42501 empty)
  var interesting = 0;
  for (final m in matrix) {
    final st = m['result'] as int;
    final body = (m['body'] as String? ?? '');
    final okish = st == 200 || st == 201 || st == 204;
    final leak = okish && body.isNotEmpty && body != '[]' && body != 'null';
    if (leak || (st >= 200 && st < 300) || (st >= 500)) {
      interesting++;
      print('${m['identity']} ${m['surface']} ${m['attack']} → $st ${body.length > 180 ? body.substring(0, 180) : body}');
    }
  }
  print('interesting_rows=$interesting');
}
