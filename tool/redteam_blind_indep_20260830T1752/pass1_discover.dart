/// PASS 1 — coverage. Blind independent red-team 20260830T1752.
/// Staging fxdknzrqjenzqcvnwqqq. No production. No Fase 4. No fixes.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '_http.dart';

Future<void> main() async {
  final c = await boot();
  stdout.writeln('PASS1 boot ok buyer=${c.buyerId} seller=${c.sellerId}');

  await _openapiAndRpcs(c);
  await _rlsTables(c);
  await _orderInsertHostile(c);
  await _orderPatchMoney(c);
  await _wallet(c);
  await _reviews(c);
  await _profilesAdmin(c);
  await _livesStreamKeys(c);
  await _chatDisputesStorage(c);
  await _offersReservationsRaffles(c);
  await _edgeFunctions(c);
  await _sensitiveRpcs(c);

  await dumpJson(
    'tool/redteam_blind_indep_20260830T1752/out/pass1.json',
    {
      'project': projectMust,
      'prefix': prefix,
      'pass': 1,
      'matrix': matrix,
      'findings': findings,
      'gaps': gaps,
    },
  );
  stdout.writeln(
    'PASS1 done matrix=${matrix.length} findings=${findings.length}',
  );
}

Future<void> _openapiAndRpcs(Ctx c) async {
  final r = await http.get(
    Uri.parse('${c.url}/rest/v1/'),
    headers: {
      ...c.anonH,
      'Accept': 'application/openapi+json',
    },
  );
  rec(
    surface: 'POSTGREST',
    attack: 'openapi_anon',
    identity: 'anon',
    result: brief(r, 200),
  );
  final paths = <String>[];
  final rpcNames = <String>[];
  try {
    final j = jsonDecode(r.body);
    if (j is Map && j['paths'] is Map) {
      for (final k in (j['paths'] as Map).keys) {
        paths.add(k.toString());
        if (k.toString().startsWith('/rpc/')) {
          rpcNames.add(k.toString().replaceFirst('/rpc/', ''));
        }
      }
    }
  } catch (_) {}
  rec(
    surface: 'RPC',
    attack: 'openapi_rpc_count',
    identity: 'anon',
    result: 'paths=${paths.length} rpcs=${rpcNames.length}',
    evidence: rpcNames.take(80).toList(),
  );
  await dumpJson(
    'tool/redteam_blind_indep_20260830T1752/out/openapi_rpcs.json',
    {'rpc_count': rpcNames.length, 'rpcs': rpcNames, 'path_count': paths.length},
  );
}

Future<void> _rlsTables(Ctx c) async {
  const tables = [
    'orders',
    'products',
    'wallets',
    'wallet_transactions',
    'wallet_payout_ledger',
    'reviews',
    'lives',
    'live_items',
    'live_reservation_requests',
    'live_raffles',
    'live_tips',
    'product_offers',
    'chats',
    'messages',
    'chat_messages',
    'order_disputes',
    'disputes',
    'profiles',
    'stripe_checkout_events',
    'seller_bundle_discounts',
    'payout_details',
    'seller_payout_details',
    'order_items',
    'notifications',
    'storage.objects',
  ];
  for (final t in tables) {
    for (final ident in ['anon', 'buyer', 'seller']) {
      final h = ident == 'anon'
          ? c.anonH
          : ident == 'buyer'
              ? c.buyerH
              : c.sellerH;
      final g = await rest(c.url, 'GET', '$t?select=*&limit=5', headers: h);
      rec(
        surface: t,
        attack: 'SELECT * limit 5',
        identity: ident,
        result: brief(g, 280),
        impact: looksOk(g) ? 'read_possible' : 'denied_or_missing',
      );
    }
  }

  // Cross-user: buyer reads seller wallet / orders of others
  final w = await rest(
    c.url,
    'GET',
    'wallets?id=eq.${c.sellerId}&select=id,balance',
    headers: c.buyerH,
  );
  rec(
    surface: 'wallets',
    attack: 'buyer SELECT seller wallet',
    identity: 'buyer',
    result: brief(w),
    impact: looksOk(w) && w.body.contains(c.sellerId) ? 'CROSS_USER_WALLET' : 'blocked',
    severity: looksOk(w) && w.body.contains(c.sellerId) ? 'P1' : '',
  );
  if (looksOk(w) && w.body.contains('"balance"')) {
    finding(
      id: 'RT1752-P1-WALLET-READ',
      severity: 'P2',
      title: 'Buyer lê saldo da wallet do vendedor',
      actor: 'buyer JWT',
      pre: 'conhece seller UUID',
      repro: 'GET wallets?id=eq.<seller>',
      impact: 'privacidade de saldo',
      evidence: brief(w),
    );
  }

  final oOther = await rest(
    c.url,
    'GET',
    'orders?buyer_id=neq.${c.buyerId}&select=id,buyer_id,seller_id,price_total,status,stripe_payment_intent_id,amount_paid_cents&limit=8',
    headers: c.buyerH,
  );
  rec(
    surface: 'orders',
    attack: 'buyer SELECT others orders',
    identity: 'buyer',
    result: brief(oOther, 320),
  );
}

Future<void> _orderInsertHostile(Ctx c) async {
  // Fixture product via service_role
  final prod = await rest(
    c.url,
    'POST',
    'products',
    headers: {
      ...c.svcH,
      'Prefer': 'return=representation',
    },
    body: {
      'seller_id': c.sellerId,
      'title': '$prefix-prod-hostile',
      'price': 19.90,
      'quantity': 3,
      'list_on_marketplace': true,
    },
  );
  rec(
    surface: 'products',
    attack: 'fixture insert service_role',
    identity: 'service_role_observe',
    result: brief(prod, 240),
  );
  String? productId;
  try {
    final j = tryJson(prod);
    if (j is List && j.isNotEmpty) productId = j[0]['id']?.toString();
    if (j is Map) productId = j['id']?.toString();
  } catch (_) {}
  if (productId == null || productId.isEmpty) {
    // maybe schema differs — fetch seller product
    final g = await rest(
      c.url,
      'GET',
      'products?seller_id=eq.${c.sellerId}&select=id,price,quantity,title&limit=1',
      headers: c.svcH,
    );
    try {
      final j = tryJson(g);
      if (j is List && j.isNotEmpty) productId = j[0]['id']?.toString();
    } catch (_) {}
  }
  if (productId == null) {
    gaps.add('no product fixture for order insert');
    return;
  }

  final payloads = <String, Map<String, dynamic>>{
    'cheap_contract': {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': productId,
      'quantity': 1,
      'price_total': 0.01,
      'contract_unit_cents': 1,
      'contract_qty': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
      'shipping_method': 'hand',
    },
    'qty_99': {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': productId,
      'quantity': 99,
      'price_total': 0.50,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    },
    'status_pago': {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': productId,
      'quantity': 1,
      'price_total': 1,
      'status': 'pago',
      'payment_method': 'Pagamento na app',
      'amount_paid_cents': 1,
      'stripe_payment_intent_id': 'pi_fake_$prefix',
    },
    'other_buyer': {
      'buyer_id': c.sellerId,
      'seller_id': c.sellerId,
      'product_id': productId,
      'quantity': 1,
      'price_total': 1,
      'status': 'reserva_pendente',
      'payment_method': 'Pagamento na app',
    },
    'prize': {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': productId,
      'quantity': 1,
      'price_total': 0,
      'status': 'premio_rifa',
      'payment_method': 'Pagamento na app',
      'live_raffle_id': '00000000-0000-0000-0000-000000000001',
    },
  };

  for (final e in payloads.entries) {
    final r = await rest(
      c.url,
      'POST',
      'orders',
      headers: c.buyerH,
      body: e.value,
    );
    rec(
      surface: 'orders',
      attack: 'INSERT ${e.key}',
      identity: 'buyer',
      result: brief(r),
    );
    if (looksOk(r)) {
      final row = tryJson(r);
      Map? m;
      if (row is List && row.isNotEmpty) m = row[0] as Map?;
      if (row is Map) m = row;
      final status = m?['status']?.toString();
      final pt = m?['price_total'];
      final cuc = m?['contract_unit_cents'];
      final qty = m?['quantity'];
      final paid = m?['amount_paid_cents'];
      final pi = m?['stripe_payment_intent_id'];
      rec(
        surface: 'orders',
        attack: 'INSERT ${e.key} FINAL_ROW',
        identity: 'buyer',
        result: 'status=$status price_total=$pt contract_unit_cents=$cuc qty=$qty paid=$paid pi=$pi',
        evidence: clip(m),
      );
      final cheap = cuc == 1 || (pt is num && pt <= 0.05 && e.key == 'cheap_contract');
      if (cheap && (cuc == 1)) {
        finding(
          id: 'RT1752-P0-CONTRACT-CLIENT',
          severity: 'P0',
          title: 'Buyer selou contract_unit_cents=1 via INSERT',
          actor: 'buyer JWT',
          pre: 'produto de catálogo ~19.90',
          repro: 'POST orders contract_unit_cents=1',
          impact: 'checkout pode cobrar 1 cêntimo se Edge confiar no contrato',
          evidence: m,
        );
      }
      if (status == 'pago' || (paid != null && paid != 0) || (pi != null && pi.toString().startsWith('pi_fake'))) {
        finding(
          id: 'RT1752-P0-FAKE-PAID',
          severity: 'P0',
          title: 'Buyer inseriu encomenda como paga / com PI falso',
          actor: 'buyer JWT',
          pre: 'INSERT status=pago',
          repro: 'POST orders status=pago amount_paid_cents=1',
          impact: 'falsificar pagamento plataforma',
          evidence: m,
        );
      }
      if (e.key == 'qty_99' && qty == 99) {
        finding(
          id: 'RT1752-P1-QTY-99',
          severity: 'P1',
          title: 'Buyer inseriu quantity=99 contra stock=3',
          actor: 'buyer JWT',
          pre: 'produto stock 3',
          repro: 'POST orders quantity=99',
          impact: 'oversell de contrato se checkout aceitar qty selada',
          evidence: m,
        );
      }
    }
  }

  // Anon insert
  final anonIns = await rest(
    c.url,
    'POST',
    'orders',
    headers: c.anonH,
    body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': productId,
      'quantity': 1,
      'price_total': 0.01,
      'contract_unit_cents': 1,
      'status': 'pago',
      'payment_method': 'Pagamento na app',
    },
  );
  rec(
    surface: 'orders',
    attack: 'anon INSERT paid cheap',
    identity: 'anon',
    result: brief(anonIns),
    severity: looksOk(anonIns) ? 'P0' : '',
  );
  if (looksOk(anonIns)) {
    finding(
      id: 'RT1752-P0-ANON-ORDER',
      severity: 'P0',
      title: 'Anon inseriu encomenda',
      actor: 'anon',
      pre: 'sem login',
      repro: 'POST orders',
      impact: 'criação de encomenda sem identidade',
      evidence: brief(anonIns),
    );
  }
}

Future<void> _orderPatchMoney(Ctx c) async {
  final mine = await rest(
    c.url,
    'GET',
    'orders?buyer_id=eq.${c.buyerId}&select=id,status,price_total,contract_unit_cents,quantity,amount_paid_cents&order=created_at.desc&limit=1',
    headers: c.buyerH,
  );
  String? oid;
  try {
    final j = tryJson(mine);
    if (j is List && j.isNotEmpty) oid = j[0]['id']?.toString();
  } catch (_) {}
  if (oid == null) {
    rec(surface: 'orders', attack: 'PATCH money', identity: 'buyer', result: 'no own order');
    return;
  }
  for (final patch in [
    {'price_total': 0.01},
    {'contract_unit_cents': 1},
    {'quantity': 99},
    {'status': 'pago'},
    {'amount_paid_cents': 1},
    {'stripe_payment_intent_id': 'pi_patched_$prefix'},
    {'seller_id': c.buyerId},
  ]) {
    final r = await rest(
      c.url,
      'PATCH',
      'orders?id=eq.$oid',
      headers: c.buyerH,
      body: patch,
    );
    rec(
      surface: 'orders',
      attack: 'PATCH ${patch.keys.first}',
      identity: 'buyer',
      result: brief(r),
    );
    if (looksOk(r) && r.body.contains(patch.values.first.toString())) {
      finding(
        id: 'RT1752-P0-PATCH-${patch.keys.first}',
        severity: 'P0',
        title: 'Buyer PATCH persistiu ${patch.keys.first}',
        actor: 'buyer JWT',
        pre: 'order própria',
        repro: 'PATCH orders ${patch.keys.first}',
        impact: 'autoridade financeira via UPDATE',
        evidence: brief(r),
      );
    }
  }

  // Seller patch buyer order to pago
  final sPatch = await rest(
    c.url,
    'PATCH',
    'orders?id=eq.$oid',
    headers: c.sellerH,
    body: {'status': 'pago', 'amount_paid_cents': 1990},
  );
  rec(
    surface: 'orders',
    attack: 'seller PATCH buyer order pago',
    identity: 'seller',
    result: brief(sPatch),
  );
}

Future<void> _wallet(Ctx c) async {
  final patch = await rest(
    c.url,
    'PATCH',
    'wallets?id=eq.${c.buyerId}',
    headers: c.buyerH,
    body: {'balance': 9999.99},
  );
  rec(surface: 'wallets', attack: 'PATCH own balance', identity: 'buyer', result: brief(patch));
  if (looksOk(patch) && patch.body.contains('9999')) {
    finding(
      id: 'RT1752-P0-WALLET-PATCH',
      severity: 'P0',
      title: 'Buyer PATCH wallets.balance',
      actor: 'buyer JWT',
      pre: 'carteira própria',
      repro: 'PATCH wallets balance=9999.99',
      impact: 'criar saldo sem fundos',
      evidence: brief(patch),
    );
  }

  final other = await rest(
    c.url,
    'PATCH',
    'wallets?id=eq.${c.sellerId}',
    headers: c.buyerH,
    body: {'balance': 1},
  );
  rec(surface: 'wallets', attack: 'PATCH seller wallet', identity: 'buyer', result: brief(other));

  final insTx = await rest(
    c.url,
    'POST',
    'wallet_transactions',
    headers: c.buyerH,
    body: {
      'wallet_id': c.buyerId,
      'amount': 500,
      'type': 'credit',
      'description': '$prefix mint',
    },
  );
  rec(surface: 'wallet_transactions', attack: 'INSERT credit', identity: 'buyer', result: brief(insTx));

  for (final fn in [
    ['batata_ensure_wallet', {'p_user_id': c.sellerId}],
    ['batata_wallet_payout_debit', {'p_user_id': c.sellerId, 'p_amount_cents': 100, 'p_idempotency_key': '${prefix}_debit'}],
    ['batata_credit_wallet_once', {'p_wallet_id': c.buyerId, 'p_order_id': '00000000-0000-0000-0000-000000000001', 'p_amount': 50, 'p_kind': 'x', 'p_label': 'x'}],
    ['batata_release_seller_wallet_for_order', {'p_order_id': '00000000-0000-0000-0000-000000000001'}],
    ['batata_refund_buyer_wallet_for_order', {'p_order_id': '00000000-0000-0000-0000-000000000001'}],
  ]) {
    final r = await rpcRaw(
      c.url,
      fn[0] as String,
      Map<String, dynamic>.from(fn[1] as Map),
      headers: c.buyerH,
    );
    rec(
      surface: 'RPC',
      attack: fn[0] as String,
      identity: 'buyer',
      result: brief(r),
    );
    if (looksOk(r) && (fn[0] as String).contains('credit')) {
      finding(
        id: 'RT1752-P0-CREDIT-RPC',
        severity: 'P0',
        title: 'JWT executou credit wallet',
        actor: 'buyer JWT',
        pre: 'RPC credit',
        repro: '${fn[0]}',
        impact: 'mint de saldo',
        evidence: brief(r),
      );
    }
  }
}

Future<void> _reviews(Ctx c) async {
  final ins = await rest(
    c.url,
    'POST',
    'reviews',
    headers: c.buyerH,
    body: {
      'author_id': c.buyerId,
      'target_id': c.sellerId,
      'stars': 5,
      'comment': '$prefix fake',
      'purchase_verified': true,
      'author_role': 'buyer',
      'target_type': 'seller',
      'is_automatic': false,
    },
  );
  rec(surface: 'reviews', attack: 'INSERT verified without order', identity: 'buyer', result: brief(ins));
  if (looksOk(ins) && ins.body.contains('true')) {
    finding(
      id: 'RT1752-P1-REVIEW-FORGE',
      severity: 'P1',
      title: 'Review purchase_verified sem transação',
      actor: 'buyer JWT',
      pre: 'sem order paga ligada',
      repro: 'POST reviews purchase_verified=true',
      impact: 'fraude reputacional',
      evidence: brief(ins),
    );
  }

  final asOther = await rest(
    c.url,
    'POST',
    'reviews',
    headers: c.buyerH,
    body: {
      'author_id': c.sellerId,
      'target_id': c.buyerId,
      'stars': 1,
      'comment': '$prefix as other',
      'purchase_verified': true,
    },
  );
  rec(surface: 'reviews', attack: 'INSERT as other author', identity: 'buyer', result: brief(asOther));
}

Future<void> _profilesAdmin(Ctx c) async {
  for (final patch in [
    {'user_type': 'admin'},
    {'user_type': 'administrador'},
    {'user_type': 'vendedor'},
    {'is_admin': true},
    {'role': 'admin'},
  ]) {
    final r = await rest(
      c.url,
      'PATCH',
      'profiles?id=eq.${c.buyerId}',
      headers: c.buyerH,
      body: patch,
    );
    rec(
      surface: 'profiles',
      attack: 'PATCH ${patch.keys.first}=${patch.values.first}',
      identity: 'buyer',
      result: brief(r),
    );
    if (looksOk(r) && r.body.toLowerCase().contains('${patch.values.first}'.toLowerCase())) {
      finding(
        id: 'RT1752-P0-PROFILE-ROLE',
        severity: 'P0',
        title: 'Buyer elevou user_type/role',
        actor: 'buyer JWT',
        pre: 'perfil próprio',
        repro: 'PATCH profiles ${patch}',
        impact: 'assumir autoridade seller/admin',
        evidence: brief(r),
      );
    }
  }
}

Future<void> _livesStreamKeys(Ctx c) async {
  for (final ident in ['anon', 'buyer']) {
    final h = ident == 'anon' ? c.anonH : c.buyerH;
    final r = await rest(
      c.url,
      'GET',
      'lives?select=id,mux_stream_key,stream_key,mux_live_id,seller_id,vendedor_id&limit=5',
      headers: h,
    );
    rec(
      surface: 'lives',
      attack: 'SELECT stream keys',
      identity: ident,
      result: brief(r),
    );
    final b = r.body.toLowerCase();
    if (looksOk(r) &&
        (b.contains('mux_stream_key') || b.contains('"stream_key"')) &&
        !b.contains('permission denied') &&
        r.body.contains(':')) {
      final hasVal = RegExp(r'stream_key"\s*:\s*"[^"]+').hasMatch(r.body);
      if (hasVal) {
        finding(
          id: 'RT1752-P1-STREAM-KEY',
          severity: 'P1',
          title: 'Stream key Mux visível via PostgREST',
          actor: ident,
          pre: 'SELECT lives',
          repro: 'GET lives?select=mux_stream_key,stream_key',
          impact: 'hijack de ingest RTMP',
          evidence: 'body_has_key_value',
        );
      }
    }
  }
}

Future<void> _chatDisputesStorage(Ctx c) async {
  for (final t in ['chats', 'messages', 'chat_messages', 'order_disputes', 'disputes']) {
    final r = await rest(
      c.url,
      'GET',
      '$t?select=*&limit=8',
      headers: c.buyerH,
    );
    rec(surface: t, attack: 'SELECT *', identity: 'buyer', result: brief(r, 240));
  }

  final buckets = await http.get(
    Uri.parse('${c.url}/storage/v1/bucket'),
    headers: c.buyerH,
  );
  rec(surface: 'storage', attack: 'LIST buckets', identity: 'buyer', result: brief(buckets, 240));

  final objs = await http.post(
    Uri.parse('${c.url}/storage/v1/object/list/chat-attachments'),
    headers: c.buyerH,
    body: jsonEncode({'prefix': '', 'limit': 20}),
  );
  rec(surface: 'storage', attack: 'list chat-attachments', identity: 'buyer', result: brief(objs, 240));

  final objs2 = await http.post(
    Uri.parse('${c.url}/storage/v1/object/list/dispute-evidence'),
    headers: c.buyerH,
    body: jsonEncode({'prefix': '', 'limit': 20}),
  );
  rec(surface: 'storage', attack: 'list dispute-evidence', identity: 'buyer', result: brief(objs2, 240));
}

Future<void> _offersReservationsRaffles(Ctx c) async {
  final offer = await rest(
    c.url,
    'POST',
    'product_offers',
    headers: c.buyerH,
    body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': '00000000-0000-0000-0000-000000000001',
      'amount': 0.01,
      'status': 'accepted',
      'quantity': 1,
    },
  );
  rec(surface: 'product_offers', attack: 'INSERT accepted 0.01', identity: 'buyer', result: brief(offer));

  final acc = await rest(
    c.url,
    'PATCH',
    'product_offers?buyer_id=eq.${c.buyerId}',
    headers: c.buyerH,
    body: {'status': 'accepted', 'amount': 0.01},
  );
  rec(surface: 'product_offers', attack: 'PATCH self-accept', identity: 'buyer', result: brief(acc));

  final res = await rest(
    c.url,
    'POST',
    'live_reservation_requests',
    headers: c.buyerH,
    body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'requested_qty': 99,
      'status': 'accepted',
    },
  );
  rec(surface: 'live_reservation_requests', attack: 'INSERT qty=99 accepted', identity: 'buyer', result: brief(res));

  final raffle = await rpcRaw(
    c.url,
    'batata_draw_live_raffle_winners',
    {'p_raffle_id': '00000000-0000-0000-0000-000000000001'},
    headers: c.buyerH,
  );
  rec(surface: 'RPC', attack: 'draw raffle as buyer', identity: 'buyer', result: brief(raffle));
}

Future<void> _edgeFunctions(Ctx c) async {
  final edges = <String, Object?>{
    'create-payment-intent': {
      'buyer_id': c.buyerId,
      'order_id': '00000000-0000-0000-0000-000000000001',
      'amount': 1,
      'quantity': 99,
      'prize_shipping': true,
      'shipping_method': 'hand',
      'seller_id': c.sellerId,
    },
    'refund-order': {'order_id': '00000000-0000-0000-0000-000000000001'},
    'create-connect-account': {
      'user_id': c.sellerId,
      'amount': 50000,
      'idempotency_key': '${prefix}_payout_x',
    },
    'create-live-tip-checkout': {
      'seller_id': c.sellerId,
      'amount_eur': 1,
      'live_id': '00000000-0000-0000-0000-000000000001',
      'tip_id': '00000000-0000-0000-0000-000000000002',
    },
    'create-mux-live': {'title': '$prefix hijack live'},
    'complete-mux-live': {'live_id': '00000000-0000-0000-0000-000000000001'},
    'livekit-mux-publish': {
      'step': 'token',
      'live_id': '00000000-0000-0000-0000-000000000001',
    },
    'ingest-ocr-reservation': {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'ocr_line_hash': 'abcdefgh',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'requested_qty': 99,
    },
    'ps-pairing-claim': {'code': '000000', 'device_id': 'rt1752'},
    'delete-test-account': {'confirm': 'APAGAR TUDO'},
    'sec-fase2-e2e-oversell': {'buyer_id': c.buyerId, 'seller_id': c.sellerId},
    'stripe-webhook': {'type': 'checkout.session.completed'},
    'send-sms-bulkgate': {'phone': '+351910000000', 'text': 'x'},
    'resolve-mux-playback': {'live_id': '00000000-0000-0000-0000-000000000001'},
    'meta-data-deletion': {},
  };

  for (final e in edges.entries) {
    final r = await edge(c.url, e.key, e.value, anon: c.anon, jwt: c.buyerJwt);
    rec(
      surface: 'EDGE ${e.key}',
      attack: 'buyer hostile body',
      identity: 'buyer',
      result: brief(r),
    );
  }

  // anon edges
  for (final fn in [
    'create-payment-intent',
    'refund-order',
    'create-connect-account',
    'create-mux-live',
    'stripe-webhook',
    'sec-fase2-e2e-oversell',
    'delete-test-account',
  ]) {
    final r = await edge(c.url, fn, {}, anon: c.anon);
    rec(surface: 'EDGE $fn', attack: 'anon', identity: 'anon', result: brief(r, 200));
  }

  // seller refund other
  final ref = await edge(
    c.url,
    'refund-order',
    {'order_id': '00000000-0000-0000-0000-000000000001'},
    anon: c.anon,
    jwt: c.sellerJwt,
  );
  rec(surface: 'EDGE refund-order', attack: 'seller random uuid', identity: 'seller', result: brief(ref));

  // GET settle unauthenticated
  final settle = await http.get(
    Uri.parse(
      '${c.url}/functions/v1/create-payment-intent?checkout_return=success&session_id=cs_test_fake_$prefix',
    ),
    headers: {'apikey': c.anon, 'Authorization': 'Bearer ${c.anon}'},
  );
  rec(
    surface: 'EDGE create-payment-intent GET settle',
    attack: 'fake session_id',
    identity: 'anon',
    result: brief(settle, 240),
  );

  final fase2 = await http.post(
    Uri.parse('${c.url}/functions/v1/create-payment-intent?fase2_e2e_settle=1'),
    headers: c.buyerH,
    body: jsonEncode({
      'order_id': '00000000-0000-0000-0000-000000000001',
      'payment_intent_id': 'pi_x',
    }),
  );
  rec(
    surface: 'EDGE fase2_e2e_settle',
    attack: 'buyer JWT',
    identity: 'buyer',
    result: brief(fase2),
  );
}

Future<void> _sensitiveRpcs(Ctx c) async {
  const names = [
    'batata_find_user_id_by_email',
    'batata_create_live_tip_pending',
    'batata_settle_live_tip_from_stripe',
    'batata_finalize_stripe_order_refund',
    'batata_claim_checkout_session_slot',
    'batata_send_live_tip_from_wallet',
    'batata_ps_claim_pairing',
    'batata_ingest_ocr_reservation_v2',
    'batata_generate_auto_feedback',
    'batata_mark_live_item_sold',
    'batata_live_reconcile_stripe_order',
    'exec_sql',
    'sql',
    'query',
  ];
  for (final n in names) {
    Map<String, dynamic> p = {};
    if (n == 'batata_find_user_id_by_email') {
      p = {'p_email': 'axinoquaa@axinoquaa.pt'};
    } else if (n == 'batata_create_live_tip_pending') {
      p = {
        'p_live_id': '00000000-0000-0000-0000-000000000001',
        'p_seller_id': c.sellerId,
        'p_amount': 1,
      };
    } else if (n == 'batata_send_live_tip_from_wallet') {
      p = {
        'p_live_id': '00000000-0000-0000-0000-000000000001',
        'p_seller_id': c.sellerId,
        'p_amount': 1,
      };
    } else if (n.contains('order') || n.contains('slot')) {
      p = {
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_claim_token': 'abcdefghijkl',
      };
    } else if (n.contains('email')) {
      p = {'p_email': 'x@y.z'};
    }
    final r = await rpcRaw(c.url, n, p, headers: c.buyerH);
    rec(surface: 'RPC', attack: n, identity: 'buyer', result: brief(r));
    final a = await rpcRaw(c.url, n, p, headers: c.anonH);
    rec(surface: 'RPC', attack: n, identity: 'anon', result: brief(a, 200));
  }

  // seller email enum
  final em = await rpcRaw(
    c.url,
    'batata_find_user_id_by_email',
    {'p_email': 'axinoqua@axinoquaa.pt'},
    headers: c.sellerH,
  );
  rec(
    surface: 'RPC',
    attack: 'find_user_id_by_email seller',
    identity: 'seller',
    result: brief(em),
    impact: looksOk(em) && em.body.contains('-') ? 'email_to_uuid' : 'blocked_or_null',
  );
}
