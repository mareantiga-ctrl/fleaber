/// Probe independente — auditoria cega 2026-08-26.
/// JWT comprador/vendedor. service_role só para setup/observação/cleanup.
/// Não paga Stripe. Não toca produção. Dados descartáveis.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'live_ops_staging_client.dart';

late String url;
late String anon;
late LiveOpsStagingClient sb;
late String buyerId;
late String sellerId;
late String buyerJwt;
late String sellerJwt;

final findings = <Map<String, dynamic>>[];
final createdOrderIds = <String>[];
String? disposableProductId;

void rec(String id, String result, String detail) {
  findings.add({'id': id, 'result': result, 'detail': detail});
  stdout.writeln('[$result] $id — $detail');
}

Map<String, String> jwtH(String jwt) => {
      'apikey': anon,
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };

Map<String, String> anonH() => {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
      'Content-Type': 'application/json',
    };

Future<http.Response> rest(
  String method,
  String path, {
  String? jwt,
  Object? body,
  Map<String, String>? extra,
}) {
  final headers = jwt == null ? anonH() : jwtH(jwt);
  if (extra != null) headers.addAll(extra);
  final uri = Uri.parse('$url$path');
  final encoded = body == null ? null : jsonEncode(body);
  switch (method) {
    case 'GET':
      return http.get(uri, headers: headers);
    case 'POST':
      return http.post(uri, headers: headers, body: encoded);
    case 'PATCH':
      return http.patch(uri, headers: headers, body: encoded);
    case 'DELETE':
      return http.delete(uri, headers: headers);
    default:
      throw ArgumentError(method);
  }
}

Future<http.Response> rpcUser(
  String fn,
  Map<String, dynamic> params,
  String jwt,
) {
  return rest('POST', '/rest/v1/rpc/$fn', jwt: jwt, body: params);
}

Future<http.Response> edge(
  String fn,
  Object? body, {
  String? jwt,
  String method = 'POST',
  String query = '',
  Map<String, String>? extra,
}) {
  final headers = <String, String>{
    'apikey': anon,
    'Content-Type': 'application/json',
  };
  if (jwt != null) headers['Authorization'] = 'Bearer $jwt';
  if (extra != null) headers.addAll(extra);
  final uri = Uri.parse('$url/functions/v1/$fn$query');
  if (method == 'GET') return http.get(uri, headers: headers);
  return http.post(uri, headers: headers, body: body == null ? null : jsonEncode(body));
}

String snippet(http.Response r, [int n = 280]) {
  final b = r.body.replaceAll('\n', ' ');
  return 'HTTP ${r.statusCode} ${b.length > n ? '${b.substring(0, n)}…' : b}';
}

bool denied(http.Response r) {
  final b = r.body.toLowerCase();
  return r.statusCode == 401 ||
      r.statusCode == 403 ||
      r.statusCode == 425 ||
      b.contains('permission denied') ||
      b.contains('42501') ||
      b.contains('not_allowed') ||
      b.contains('sem permissão') ||
      b.contains('row-level security');
}

Future<void> main() async {
  final env = loadLiveOpsStagingEnv();
  url = normalizeSupabaseProjectUrl(envRequire(env, 'SUPABASE_URL'));
  anon = envRequire(env, 'SUPABASE_ANON_KEY');
  sb = LiveOpsStagingClient(
    url: url,
    anonKey: anon,
    serviceRoleKey: envRequire(env, 'SUPABASE_SERVICE_ROLE_KEY'),
  );
  buyerId = envRequire(env, 'LIVE_OPS_TEST_BUYER_ID');
  sellerId = envRequire(env, 'LIVE_OPS_TEST_SELLER_ID');

  try {
    buyerJwt = await sb.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_BUYER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_BUYER_PASSWORD'),
    );
    rec('LOGIN_BUYER', 'OK', 'JWT obtido');
  } catch (e) {
    rec('LOGIN_BUYER', 'FAIL', '$e');
    stdout.writeln(jsonEncode({'fatal': 'buyer login failed', 'error': '$e'}));
    return;
  }
  try {
    sellerJwt = await sb.signIn(
      email: envRequire(env, 'LIVE_OPS_TEST_SELLER_EMAIL'),
      password: envRequire(env, 'LIVE_OPS_TEST_SELLER_PASSWORD'),
    );
    rec('LOGIN_SELLER', 'OK', 'JWT obtido');
  } catch (e) {
    rec('LOGIN_SELLER', 'FAIL', '$e');
    return;
  }

  await _setupDisposable();
  try {
    await _authz();
    await _orders();
    await _walletRpcs();
    await _raffleRpcs();
    await _liveBag();
    await _edges();
    await _storage();
    await _profiles();
  } finally {
    await _cleanup();
  }

  stdout.writeln('\n===== SUMMARY =====');
  stdout.writeln(jsonEncode(findings));
}

Future<void> _setupDisposable() async {
  try {
    final products = await sb.select(
      'products',
      filter: 'seller_id=eq.$sellerId',
      limit: 1,
    );
    if (products.isEmpty) {
      rec('SETUP_PRODUCT', 'WARN', 'vendedor sem produtos — skip alguns testes');
      return;
    }
    disposableProductId = products.first['id']?.toString();
    rec('SETUP_PRODUCT', 'OK', 'product=$disposableProductId');
  } catch (e) {
    rec('SETUP_PRODUCT', 'FAIL', '$e');
  }
}

Future<String?> _insertBuyerOrder({
  required num price,
  int qty = 1,
  String status = 'reserva_pendente',
  String? paymentMethod,
}) async {
  if (disposableProductId == null) return null;
  final r = await rest('POST', '/rest/v1/orders', jwt: buyerJwt, body: {
    'buyer_id': buyerId,
    'seller_id': sellerId,
    'product_id': disposableProductId,
    'price_total': price,
    'quantity': qty,
    'status': status,
    if (paymentMethod != null) 'payment_method': paymentMethod,
  });
  if (r.statusCode >= 400) {
    rec('ORDER_INSERT', 'INFO', 'insert $status $price → ${snippet(r)}');
    return null;
  }
  final list = jsonDecode(r.body);
  if (list is List && list.isNotEmpty) {
    final id = (list.first as Map)['id']?.toString();
    if (id != null) createdOrderIds.add(id);
    return id;
  }
  return null;
}

Future<void> _authz() async {
  // Anon SELECT orders
  final aOrders = await rest('GET', '/rest/v1/orders?select=id&limit=5');
  rec(
    'ANON_ORDERS',
    (aOrders.statusCode >= 400 || aOrders.body == '[]') ? 'BLOCKED' : 'OPEN',
    snippet(aOrders),
  );

  // Anon SELECT profiles
  final aProf = await rest(
    'GET',
    '/rest/v1/profiles?select=id,email,phone,mb_way,iban,user_type&limit=5',
  );
  rec(
    'ANON_PROFILES',
    (aProf.statusCode >= 400 || aProf.body == '[]') ? 'BLOCKED' : 'OPEN',
    snippet(aProf),
  );

  // Buyer SELECT other wallets
  final w = await rest(
    'GET',
    '/rest/v1/wallets?select=id,balance&id=eq.$sellerId',
    jwt: buyerJwt,
  );
  final wOpen = w.statusCode < 400 && w.body != '[]';
  rec('BUYER_READ_SELLER_WALLET', wOpen ? 'OPEN' : 'BLOCKED', snippet(w));

  // Buyer UPDATE own wallet balance
  final wu = await rest(
    'PATCH',
    '/rest/v1/wallets?id=eq.$buyerId',
    jwt: buyerJwt,
    body: {'balance': 99999.99},
  );
  rec(
    'BUYER_PATCH_OWN_WALLET',
    denied(wu) || wu.body == '[]' ? 'BLOCKED' : 'OPEN',
    snippet(wu),
  );

  // Buyer INSERT wallet
  final wi = await rest(
    'POST',
    '/rest/v1/wallets',
    jwt: buyerJwt,
    body: {'id': buyerId, 'balance': 5000},
  );
  rec(
    'BUYER_INSERT_WALLET',
    denied(wi) ? 'BLOCKED' : 'OPEN',
    snippet(wi),
  );

  // Cross-user orders
  final oth = await rest(
    'GET',
    '/rest/v1/orders?select=id,buyer_id,seller_id,price_total&buyer_id=neq.$buyerId&seller_id=neq.$buyerId&limit=5',
    jwt: buyerJwt,
  );
  rec(
    'BUYER_READ_FOREIGN_ORDERS',
    (oth.statusCode < 400 && oth.body != '[]') ? 'OPEN' : 'BLOCKED',
    snippet(oth),
  );

  // Stream keys
  final livesStar = await rest(
    'GET',
    '/rest/v1/lives?select=id,mux_stream_key,stream_key&limit=3',
    jwt: buyerJwt,
  );
  rec(
    'BUYER_READ_STREAM_KEYS',
    livesStar.statusCode == 200 && livesStar.body.contains('mux_stream_key')
        ? 'OPEN'
        : 'BLOCKED',
    snippet(livesStar),
  );

  // credit_wallet_once as buyer
  final cred = await rpcUser(
    'batata_credit_wallet_once',
    {
      'p_user_id': buyerId,
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_amount': 10,
      'p_type': 'reembolso',
      'p_note': 'audit',
    },
    buyerJwt,
  );
  rec(
    'BUYER_CREDIT_WALLET_ONCE',
    denied(cred) ? 'BLOCKED' : 'OPEN',
    snippet(cred),
  );

  // stripe_convert as buyer
  final conv = await rpcUser(
    'batata_live_reservation_stripe_convert',
    {
      'p_order_id': '00000000-0000-0000-0000-000000000001',
      'p_request_id': '00000000-0000-0000-0000-000000000002',
    },
    buyerJwt,
  );
  rec(
    'BUYER_STRIPE_CONVERT',
    denied(conv) ? 'BLOCKED' : 'REACHED',
    snippet(conv),
  );

  // payout debit as buyer
  final po = await rpcUser(
    'batata_wallet_payout_debit',
    {
      'p_user_id': buyerId,
      'p_amount_cents': 100,
      'p_idempotency_key': 'audit-cega-${DateTime.now().millisecondsSinceEpoch}',
    },
    buyerJwt,
  );
  rec(
    'BUYER_PAYOUT_DEBIT',
    denied(po) ? 'BLOCKED' : 'OPEN',
    snippet(po),
  );

  // settle tip 3-arg
  final tip3 = await rpcUser(
    'batata_settle_live_tip_from_stripe',
    {
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
      'p_stripe_session_id': 'cs_test_audit',
      'p_paid_amount_cents': 1000,
    },
    buyerJwt,
  );
  rec(
    'BUYER_SETTLE_TIP_3ARG',
    denied(tip3) ? 'BLOCKED' : 'REACHED',
    snippet(tip3),
  );

  // settle tip 2-arg overload
  final tip2 = await rpcUser(
    'batata_settle_live_tip_from_stripe',
    {
      'p_tip_id': '00000000-0000-0000-0000-000000000001',
      'p_stripe_session_id': 'cs_test_audit',
    },
    buyerJwt,
  );
  rec(
    'BUYER_SETTLE_TIP_2ARG',
    (tip2.statusCode == 404 ||
            tip2.body.contains('Could not find') ||
            denied(tip2))
        ? 'BLOCKED'
        : 'OPEN',
    snippet(tip2),
  );

  // system message to arbitrary live
  final lives = await rest(
    'GET',
    '/rest/v1/lives?select=id&limit=1',
    jwt: buyerJwt,
  );
  String? liveId;
  try {
    final list = jsonDecode(lives.body);
    if (list is List && list.isNotEmpty) {
      liveId = (list.first as Map)['id']?.toString();
    }
  } catch (_) {}
  if (liveId != null) {
    final sys = await rpcUser(
      'batata_live_system_message',
      {
        'p_live_id': liveId,
        'p_body': 'AUDIT_CEGA_PROBE_IGNORE',
        'p_sender_label': 'Sistema',
      },
      buyerJwt,
    );
    rec(
      'BUYER_SYSTEM_MESSAGE',
      denied(sys) || sys.body.contains('"ok":false') ? 'BLOCKED' : 'OPEN',
      snippet(sys),
    );
  } else {
    rec('BUYER_SYSTEM_MESSAGE', 'SKIP', 'sem lives visíveis');
  }

  // award tickets
  final aw = await rpcUser(
    'batata_award_live_raffle_tickets',
    {
      'p_raffle_id': '00000000-0000-0000-0000-000000000001',
      'p_user_id': buyerId,
      'p_source': 'audit',
      'p_delta': 99,
      'p_note': 'x',
      'p_meta': <String, dynamic>{},
    },
    buyerJwt,
  );
  rec(
    'BUYER_AWARD_TICKETS',
    denied(aw) ? 'BLOCKED' : 'REACHED',
    snippet(aw),
  );
}

Future<void> _orders() async {
  // Forge low price INSERT
  final cheapId = await _insertBuyerOrder(price: 0.01, qty: 1);
  if (cheapId != null) {
    final rows = await sb.select('orders', filter: 'id=eq.$cheapId', limit: 1);
    final stored = rows.isEmpty ? null : rows.first['price_total'];
    rec(
      'FORGE_PRICE_INSERT',
      (stored == 0.01 || stored == '0.01' || stored == 0.010) ? 'OPEN' : 'CLAMPED',
      'stored_price=$stored order=$cheapId',
    );

    // Buyer self-pago
    final pago = await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.$cheapId',
      jwt: buyerJwt,
      body: {'status': 'pago'},
    );
    final afterPago = await sb.select('orders', filter: 'id=eq.$cheapId', limit: 1);
    final st = afterPago.isEmpty ? '?' : afterPago.first['status'];
    rec(
      'BUYER_SELF_PAGO',
      st == 'pago' ? 'OPEN' : 'BLOCKED',
      'status=$st ${snippet(pago)}',
    );

    // Buyer bump qty pre-pay
    final qty = await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.$cheapId',
      jwt: buyerJwt,
      body: {'quantity': 99, 'price_total': 0.01},
    );
    final afterQty = await sb.select('orders', filter: 'id=eq.$cheapId', limit: 1);
    rec(
      'BUYER_PREPAY_QTY_PRICE',
      'INFO',
      'qty=${afterQty.first['quantity']} price=${afterQty.first['price_total']} ${snippet(qty)}',
    );

    // Buyer forge premio_rifa
    final raffle = await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.$cheapId',
      jwt: buyerJwt,
      body: {
        'status': 'premio_rifa',
        'payment_method': 'Prémio da Rifa',
      },
    );
    final afterR = await sb.select('orders', filter: 'id=eq.$cheapId', limit: 1);
    rec(
      'BUYER_FORGE_PREMIO_RIFA',
      afterR.first['status'] == 'premio_rifa' ? 'OPEN' : 'BLOCKED',
      'status=${afterR.first['status']} pm=${afterR.first['payment_method']} ${snippet(raffle)}',
    );

    // Seller mark pago on unpaid (MB WAY model)
    final sellerPago = await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.$cheapId',
      jwt: sellerJwt,
      body: {'status': 'pago'},
    );
    final afterS = await sb.select('orders', filter: 'id=eq.$cheapId', limit: 1);
    rec(
      'SELLER_MARK_PAGO_UNPAID',
      afterS.first['status'] == 'pago' ? 'OPEN' : 'BLOCKED',
      'status=${afterS.first['status']} ${snippet(sellerPago)}',
    );

    // If seller made it pago, try buyer/seller cancel
    if (afterS.first['status'] == 'pago') {
      final cancelB = await rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$cheapId',
        jwt: buyerJwt,
        body: {'status': 'cancelado'},
      );
      final afterCB = await sb.select('orders', filter: 'id=eq.$cheapId', limit: 1);
      rec(
        'BUYER_CANCEL_POSTPAY',
        afterCB.first['status'] == 'cancelado' ? 'OPEN' : 'BLOCKED',
        'status=${afterCB.first['status']} ${snippet(cancelB)}',
      );

      final cancelS = await rest(
        'PATCH',
        '/rest/v1/orders?id=eq.$cheapId',
        jwt: sellerJwt,
        body: {'status': 'cancelado'},
      );
      final afterCS = await sb.select('orders', filter: 'id=eq.$cheapId', limit: 1);
      rec(
        'SELLER_CANCEL_POSTPAY',
        afterCS.first['status'] == 'cancelado' ? 'OPEN' : 'BLOCKED',
        'status=${afterCS.first['status']} ${snippet(cancelS)}',
      );

      // revert to unpaid for cleanup if still pago (avoid consuming stock permanently)
      if (afterCS.first['status'] == 'pago') {
        try {
          await sb.patch('orders', 'id=eq.$cheapId', {'status': 'cancelado'});
        } catch (e) {
          rec('CLEANUP_CANCEL_SVC', 'INFO', '$e');
        }
      }
    }
  } else {
    rec('FORGE_PRICE_INSERT', 'FAIL', 'não conseguiu inserir order');
  }

  // Insert already-paid
  final paidInsert = await _insertBuyerOrder(price: 1, status: 'pago');
  if (paidInsert != null) {
    final rows = await sb.select('orders', filter: 'id=eq.$paidInsert', limit: 1);
    rec(
      'INSERT_ALREADY_PAGO',
      rows.first['status'] == 'pago' ? 'OPEN' : 'CLAMPED',
      'status=${rows.first['status']}',
    );
  }

  // Stripe IDs from client
  final stripeId = await _insertBuyerOrder(price: 2);
  if (stripeId != null) {
    final patch = await rest(
      'PATCH',
      '/rest/v1/orders?id=eq.$stripeId',
      jwt: buyerJwt,
      body: {
        'stripe_payment_intent_id': 'pi_audit_fake',
        'stripe_checkout_session_id': 'cs_audit_fake',
      },
    );
    final after = await sb.select('orders', filter: 'id=eq.$stripeId', limit: 1);
    rec(
      'BUYER_SET_STRIPE_IDS',
      (after.first['stripe_payment_intent_id'] != null) ? 'OPEN' : 'BLOCKED',
      'pi=${after.first['stripe_payment_intent_id']} ${snippet(patch)}',
    );
  }
}

Future<void> _walletRpcs() async {
  final oid = await _insertBuyerOrder(price: 12.34, qty: 1);
  if (oid == null) {
    rec('PARTIAL_REFUND_RPC', 'SKIP', 'sem order');
    return;
  }

  Map<String, dynamic>? walletBefore;
  try {
    final w = await sb.select('wallets', filter: 'id=eq.$buyerId', limit: 1);
    walletBefore = w.isEmpty ? null : w.first;
  } catch (_) {}

  final r = await rpcUser(
    'batata_process_partial_refund_dispute',
    {'p_order_id': oid, 'p_refund_percent': 100},
    buyerJwt,
  );
  Map<String, dynamic>? walletAfter;
  try {
    final w = await sb.select('wallets', filter: 'id=eq.$buyerId', limit: 1);
    walletAfter = w.isEmpty ? null : w.first;
  } catch (_) {}

  final beforeBal = walletBefore?['balance'];
  final afterBal = walletAfter?['balance'];
  final minted = (afterBal != null &&
      beforeBal != null &&
      num.tryParse('$afterBal') != null &&
      num.tryParse('$beforeBal') != null &&
      num.parse('$afterBal') > num.parse('$beforeBal'));

  rec(
    'PARTIAL_REFUND_RPC',
    minted
        ? 'OPEN_MINT'
        : (denied(r) ? 'BLOCKED' : (r.body.contains('true') ? 'RETURNED_TRUE' : 'NO_MINT')),
    'before=$beforeBal after=$afterBal ${snippet(r)}',
  );

  // If minted, try to reverse via service_role observation only — do not leave extra balance
  if (minted) {
    rec('PARTIAL_REFUND_IMPACT', 'P0_CANDIDATE', 'saldo subiu sem pagamento Stripe');
  }

  final rel = await rpcUser(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': oid},
    buyerJwt,
  );
  rec(
    'RELEASE_SELLER_WALLET',
    denied(rel) ? 'BLOCKED' : 'REACHED',
    snippet(rel),
  );

  final ref = await rpcUser(
    'batata_refund_buyer_wallet_for_order',
    {'p_order_id': oid},
    sellerJwt,
  );
  rec(
    'REFUND_BUYER_WALLET_SELLER',
    denied(ref) ? 'BLOCKED' : 'REACHED',
    snippet(ref),
  );

  // wallet tip cap
  final tipHi = await rpcUser(
    'batata_send_live_tip_from_wallet',
    {
      'p_live_id': null,
      'p_seller_id': sellerId,
      'p_amount': 9999,
      'p_message': 'audit',
    },
    buyerJwt,
  );
  rec(
    'WALLET_TIP_9999',
    (tipHi.body.toLowerCase().contains('máximo') ||
            tipHi.body.toLowerCase().contains('maximo') ||
            tipHi.body.contains('500') ||
            denied(tipHi) ||
            tipHi.body.contains('insufficient'))
        ? 'CAPPED_OR_INSUFFICIENT'
        : 'REACHED',
    snippet(tipHi),
  );
}

Future<void> _raffleRpcs() async {
  final prize = await rpcUser(
    'batata_create_raffle_prize_order',
    {
      'p_raffle_id': '00000000-0000-0000-0000-000000000001',
      'p_winner_id': buyerId,
      'p_qty': 1,
    },
    buyerJwt,
  );
  rec(
    'BUYER_CREATE_PRIZE_ORDER',
    denied(prize) ? 'BLOCKED' : 'REACHED',
    snippet(prize),
  );

  final draw = await rpcUser(
    'batata_draw_live_raffle_winners',
    {'p_raffle_id': '00000000-0000-0000-0000-000000000001'},
    buyerJwt,
  );
  rec(
    'BUYER_DRAW_RAFFLE',
    (denied(draw) ||
            draw.body.contains('not_seller') ||
            draw.body.toLowerCase().contains('não') ||
            draw.statusCode >= 400)
        ? 'BLOCKED'
        : 'OPEN',
    snippet(draw),
  );
}

Future<void> _liveBag() async {
  final reqs = await rest(
    'GET',
    '/rest/v1/live_reservation_requests?select=id,buyer_id,requested_qty,status&limit=3',
    jwt: buyerJwt,
  );
  rec('BUYER_LIST_RESERVATIONS', 'INFO', snippet(reqs));

  // Try insert extreme qty
  final ins = await rest(
    'POST',
    '/rest/v1/live_reservation_requests',
    jwt: buyerJwt,
    body: {
      'buyer_id': buyerId,
      'requested_qty': 9999,
      'status': 'accepted',
      'source': 'fleaber_live',
    },
  );
  rec(
    'BUYER_INSERT_RESERVATION_EXTREME',
    denied(ins) || ins.statusCode >= 400 ? 'BLOCKED' : 'OPEN',
    snippet(ins),
  );

  // Seller update qty on someone else's request if any exist
  try {
    final all = await sb.select('live_reservation_requests', limit: 1);
    if (all.isNotEmpty) {
      final id = all.first['id'];
      final oldQty = all.first['requested_qty'];
      final patch = await rest(
        'PATCH',
        '/rest/v1/live_reservation_requests?id=eq.$id',
        jwt: sellerJwt,
        body: {'requested_qty': 1},
      );
      rec(
        'SELLER_PATCH_RESERVATION_QTY',
        denied(patch) || patch.body == '[]' ? 'BLOCKED' : 'OPEN',
        'id=$id old=$oldQty ${snippet(patch)}',
      );
      // restore
      if (patch.statusCode < 400 && patch.body != '[]') {
        try {
          await sb.patch(
            'live_reservation_requests',
            'id=eq.$id',
            {'requested_qty': oldQty},
          );
        } catch (_) {}
      }
    } else {
      rec('SELLER_PATCH_RESERVATION_QTY', 'SKIP', 'sem reservas');
    }
  } catch (e) {
    rec('SELLER_PATCH_RESERVATION_QTY', 'INFO', '$e');
  }

  final qtyRpc = await rpcUser(
    'batata_live_bag_update_qty',
    {
      'p_request_id': '00000000-0000-0000-0000-000000000001',
      'p_qty': 9999,
    },
    buyerJwt,
  );
  rec('BAG_QTY_RPC_EXTREME', 'INFO', snippet(qtyRpc));
}

Future<void> _edges() async {
  // webhook no signature
  final wh = await edge('stripe-webhook', {'type': 'checkout.session.completed'});
  rec(
    'WEBHOOK_NO_SIG',
    (wh.statusCode == 400 || wh.statusCode == 401) ? 'BLOCKED' : 'OPEN',
    snippet(wh),
  );

  // refund as buyer
  final oid = createdOrderIds.isEmpty ? '00000000-0000-0000-0000-000000000001' : createdOrderIds.first;
  final refB = await edge('refund-order', {'order_id': oid}, jwt: buyerJwt);
  rec(
    'REFUND_AS_BUYER',
    (refB.statusCode == 403 || denied(refB)) ? 'BLOCKED' : 'OPEN',
    snippet(refB),
  );

  // create-payment-intent without JWT
  final cpi = await edge('create-payment-intent', {
    'order_id': oid,
    'buyer_id': buyerId,
    'amount': 1,
  });
  rec(
    'CHECKOUT_NO_JWT',
    (cpi.statusCode == 401 || cpi.statusCode == 403) ? 'BLOCKED' : 'OPEN',
    snippet(cpi),
  );

  // checkout as buyer on own cheap order if any
  if (createdOrderIds.isNotEmpty) {
    final cpi2 = await edge('create-payment-intent', {
      'order_id': createdOrderIds.first,
      'buyer_id': buyerId,
    }, jwt: buyerJwt);
    rec('CHECKOUT_OWN_UNPAID', 'INFO', snippet(cpi2, 400));
  }

  // forged service_role payload for fase2_e2e_settle
  final fakePayload = base64Url
      .encode(utf8.encode(jsonEncode({'role': 'service_role', 'iss': 'audit'})))
      .replaceAll('=', '');
  final fakeJwt = 'eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.$fakePayload.x';
  final e2e = await http.post(
    Uri.parse('$url/functions/v1/create-payment-intent?fase2_e2e_settle=1'),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $fakeJwt',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'order_id': '00000000-0000-0000-0000-000000000001',
      'payment_intent_id': 'pi_does_not_exist',
    }),
  );
  rec(
    'FASE2_E2E_FORGED_JWT',
    e2e.statusCode == 401 ? 'BLOCKED' : 'AUTH_BYPASS',
    snippet(e2e),
  );

  final e2eFn = await edge(
    'sec-fase2-e2e-oversell',
    {'buyer_id': buyerId, 'seller_id': sellerId},
    jwt: fakeJwt,
  );
  rec(
    'E2E_OVERSELL_FORGED_JWT',
    e2eFn.statusCode == 401 ? 'BLOCKED' : 'AUTH_BYPASS',
    snippet(e2eFn),
  );

  // ingest OCR no token
  final ocr = await edge('ingest-ocr-reservation', {
    'live_id': '00000000-0000-0000-0000-000000000001',
    'ocr_line_hash': 'abcdefghijkl',
  });
  rec(
    'OCR_NO_TOKEN',
    (ocr.statusCode == 401 || ocr.body.contains('missing_device_token'))
        ? 'BLOCKED'
        : 'OPEN',
    snippet(ocr),
  );

  // livekit cleanup no auth
  final cl = await edge('livekit-egress-cleanup', {});
  rec(
    'EGRESS_CLEANUP_NO_AUTH',
    cl.statusCode == 401 ? 'BLOCKED' : 'OPEN',
    snippet(cl),
  );

  // delete-test-account as buyer
  final nuke = await edge(
    'delete-test-account',
    {'confirm': 'APAGAR TUDO'},
    jwt: buyerJwt,
  );
  rec('NUKE_AS_BUYER', 'INFO', snippet(nuke));

  // create-mux-live as buyer (cost)
  final mux = await edge(
    'create-mux-live',
    {'title': 'AUDIT CEGA NAO USAR'},
    jwt: buyerJwt,
  );
  rec(
    'MUX_CREATE_AS_BUYER',
    (mux.statusCode == 401 || mux.statusCode == 403) ? 'BLOCKED' : 'REACHED',
    snippet(mux, 200),
  );

  // payout as buyer via connect
  final pay = await edge(
    'create-connect-account',
    {
      'user_id': buyerId,
      'amount': 1,
      'idempotency_key': 'audit-cega-no-payout',
    },
    jwt: buyerJwt,
  );
  rec('CONNECT_PAYOUT_AS_BUYER', 'INFO', snippet(pay, 220));
}

Future<void> _storage() async {
  // list chat_media as anon
  final list = await http.post(
    Uri.parse('$url/storage/v1/object/list/chat_media'),
    headers: anonH(),
    body: jsonEncode({'prefix': 'order_proofs', 'limit': 5}),
  );
  rec('ANON_LIST_PROOFS', 'INFO', snippet(list));

  // upload to other user's product_photos
  final up = await http.post(
    Uri.parse(
      '$url/storage/v1/object/chat_media/product_photos/$sellerId/audit_cega.txt',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'text/plain',
    },
    body: 'audit',
  );
  rec(
    'BUYER_UPLOAD_SELLER_PATH',
    (up.statusCode == 400 || up.statusCode == 403 || up.statusCode == 401)
        ? 'BLOCKED'
        : 'OPEN',
    snippet(up),
  );

  final proof = await http.post(
    Uri.parse(
      '$url/storage/v1/object/chat_media/order_proofs/$buyerId/audit_cega.txt',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'text/plain',
    },
    body: 'audit',
  );
  rec(
    'BUYER_UPLOAD_PROOF_PUBLIC_BUCKET',
    (proof.statusCode == 400 || proof.statusCode == 403) ? 'BLOCKED' : 'OPEN',
    snippet(proof),
  );

  final priv = await http.post(
    Uri.parse(
      '$url/storage/v1/object/fleaber_private/order_proofs/$sellerId/audit_cega.txt',
    ),
    headers: {
      'apikey': anon,
      'Authorization': 'Bearer $buyerJwt',
      'Content-Type': 'text/plain',
    },
    body: 'audit',
  );
  rec(
    'BUYER_UPLOAD_SELLER_PRIVATE_PROOF',
    (priv.statusCode == 400 || priv.statusCode == 403 || priv.statusCode == 401)
        ? 'BLOCKED'
        : 'OPEN',
    snippet(priv),
  );
}

Future<void> _profiles() async {
  final admin = await rest(
    'PATCH',
    '/rest/v1/profiles?id=eq.$buyerId',
    jwt: buyerJwt,
    body: {'user_type': 'admin'},
  );
  final after = await rest(
    'GET',
    '/rest/v1/profiles?select=id,user_type&id=eq.$buyerId',
    jwt: buyerJwt,
  );
  rec(
    'BUYER_SET_ADMIN',
    after.body.contains('admin') && !after.body.contains('comprador')
        ? 'OPEN'
        : 'BLOCKED',
    'patch=${snippet(admin)} get=${snippet(after)}',
  );

  // PII of seller
  final pii = await rest(
    'GET',
    '/rest/v1/profiles?select=id,email,phone,mb_way,iban,legal_full_name&id=eq.$sellerId',
    jwt: buyerJwt,
  );
  rec('BUYER_READ_SELLER_PII', pii.body == '[]' || denied(pii) ? 'BLOCKED' : 'OPEN', snippet(pii));
}

Future<void> _cleanup() async {
  for (final id in createdOrderIds) {
    try {
      await sb.deleteWhere('orders', 'id=eq.$id');
      rec('CLEANUP_ORDER', 'OK', id);
    } catch (e) {
      rec('CLEANUP_ORDER', 'WARN', '$id $e');
    }
  }
}
