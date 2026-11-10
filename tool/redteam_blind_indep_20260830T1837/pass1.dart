/// PASS 1 — cobertura: OpenAPI, RLS, RPC, Edge, dinheiro, stock, privacidade.
/// Auditoria cega independente 20260830T1837. Não corrige. Não produção.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '_rt.dart';

Future<void> main() async {
  final c = await boot();
  stdout.writeln('PASS1 boot ok staging=$projectMust buyer=${c.buyerId}');

  await _openapi(c);
  await _tableSweep(c);
  await _columnSecrets(c);
  await _rlsWrites(c);
  await _rpcSweep(c);
  await _edgeSweep(c);
  await _orderMoney(c);
  await _stockHold(c);
  await _reviewsDisputesOffers(c);
  await _privacyChatStorage(c);
  await _profilesAuthz(c);

  await dumpJson('pass1', {
    'pass': 1,
    'project': projectMust,
    'prefix': prefix,
    'utc': DateTime.now().toUtc().toIso8601String(),
    'matrix': matrix,
    'findings': findings,
    'gaps': gaps,
    'invariants': invariants,
  });
  stdout.writeln(
    'PASS1 done matrix=${matrix.length} findings=${findings.length}',
  );
}

Future<void> _openapi(Ctx c) async {
  final r = await http.get(
    Uri.parse('${c.url}/rest/v1/'),
    headers: {
      ...c.anonH,
      'Accept': 'application/openapi+json',
    },
  );
  rec(
    surface: 'OPENAPI',
    attack: 'GET /rest/v1/ openapi as anon',
    identity: 'anon',
    result: '${r.statusCode} bytes=${r.body.length}',
  );
  final paths = <String>[];
  final rpcs = <String>[];
  try {
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final p = j['paths'];
    if (p is Map) {
      for (final k in p.keys) {
        final s = k.toString();
        paths.add(s);
        if (s.startsWith('/rpc/')) rpcs.add(s.substring(5));
      }
    }
  } catch (e) {
    gaps.add('openapi parse: $e');
  }
  await dumpJson('openapi_paths', {'tables_or_paths': paths, 'rpcs': rpcs});
  rec(
    surface: 'OPENAPI',
    attack: 'inventory paths/rpcs',
    identity: 'anon',
    result: 'paths=${paths.length} rpcs=${rpcs.length}',
    evidence: {'rpc_sample': rpcs.take(80).toList()},
  );
}

const _tables = [
  'orders',
  'products',
  'profiles',
  'wallets',
  'wallet_transactions',
  'wallet_payout_ledger',
  'chats',
  'chat_messages',
  'order_disputes',
  'order_dispute_replies',
  'reviews',
  'reviews_gerais',
  'reviews_public_ratings',
  'lives',
  'live_items',
  'live_reservation_requests',
  'live_messages',
  'live_tips',
  'live_raffles',
  'live_raffle_winners',
  'live_raffle_tickets',
  'product_offers',
  'product_bundles',
  'stripe_checkout_events',
  'seller_helpers',
  'staff_action_logs',
  'app_logs',
  'fleaber_commissions',
  'user_notifications',
  'favorites',
  'follows',
  'ps_pairings',
  'ps_pairing_codes',
  'seller_device_tokens',
  'order_returns',
  'partial_refunds',
  'bag_items',
  'waitlist',
];

Future<void> _tableSweep(Ctx c) async {
  for (final t in _tables) {
    for (final idn in ['anon', 'buyer', 'seller']) {
      final h = idn == 'anon'
          ? c.anonH
          : idn == 'buyer'
              ? c.buyerH
              : c.sellerH;
      final r = await rest(
        c.url,
        'GET',
        '$t?select=*&limit=5',
        headers: h,
      );
      final rows = asMaps(decode(r));
      final leaked = rows.where((row) {
        final ids = [
          row['buyer_id'],
          row['seller_id'],
          row['user_id'],
          row['id'],
          row['wallet_id'],
        ].map((e) => e?.toString() ?? '').toList();
        if (idn == 'anon') return rows.isNotEmpty;
        if (idn == 'buyer') {
          return !ids.contains(c.buyerId) && rows.isNotEmpty;
        }
        return !ids.contains(c.sellerId) && rows.isNotEmpty;
      }).toList();
      rec(
        surface: 'RLS_SELECT',
        attack: 'GET $t limit 5',
        identity: idn,
        result: '${r.statusCode} n=${rows.length} otherish=${leaked.length}',
        evidence: r.statusCode == 200
            ? {
                'n': rows.length,
                'keys': rows.isEmpty ? [] : rows.first.keys.take(20).toList(),
              }
            : briefBody(r),
        impact: leaked.isNotEmpty && r.statusCode == 200
            ? 'possible_cross_user_read'
            : '',
      );
    }
  }

  // Cross-user: buyer reads seller wallet / other orders by UUID
  final w = await rest(
    c.url,
    'GET',
    'wallets?id=eq.${c.sellerId}&select=*',
    headers: c.buyerH,
  );
  rec(
    surface: 'WALLET',
    attack: 'buyer SELECT seller wallet by UUID',
    identity: 'buyer',
    result: briefBody(w),
    impact: w.statusCode == 200 && asMaps(decode(w)).isNotEmpty
        ? 'cross_user_wallet_read'
        : '',
  );
  if (w.statusCode == 200 && asMaps(decode(w)).isNotEmpty) {
    finding(
      id: 'RT1837-P1-WALLET-READ',
      severity: 'P1',
      title: 'Buyer JWT lê carteira de outro utilizador',
      actor: 'buyer',
      pre: 'UUID seller conhecido',
      repro: 'GET /wallets?id=eq.{seller}',
      impact: 'saldo alheio',
      evidence: briefBody(w),
    );
  }

  final oth = await rest(
    c.url,
    'GET',
    'orders?seller_id=eq.${c.sellerId}&buyer_id=neq.${c.buyerId}&select=id,buyer_id,seller_id,status,price_total,amount_paid_cents&limit=8',
    headers: c.buyerH,
  );
  rec(
    surface: 'ORDERS',
    attack: 'buyer SELECT other buyers orders of lab seller',
    identity: 'buyer',
    result: briefBody(oth),
  );
}

Future<void> _columnSecrets(Ctx c) async {
  for (final col in [
    'mux_stream_key',
    'stream_key',
    'mux_live_id',
    'livekit_egress_id',
    'livekit_room_name',
  ]) {
    for (final idn in ['anon', 'buyer', 'seller']) {
      final h = idn == 'anon'
          ? c.anonH
          : idn == 'buyer'
              ? c.buyerH
              : c.sellerH;
      final r = await rest(
        c.url,
        'GET',
        'lives?select=id,$col&limit=3',
        headers: h,
      );
      rec(
        surface: 'MUX',
        attack: 'SELECT lives.$col',
        identity: idn,
        result: briefBody(r),
        impact: r.statusCode == 200 &&
                r.body.contains(col) &&
                !r.body.contains('permission')
            ? 'stream_secret_column_readable'
            : '',
      );
    }
  }

  final bank = await rest(
    c.url,
    'GET',
    'profiles?select=id,iban,mbway,phone,email,stripe_account_id,bank_iban,nif&limit=5',
    headers: c.buyerH,
  );
  rec(
    surface: 'PROFILES',
    attack: 'buyer SELECT banking/PII columns',
    identity: 'buyer',
    result: briefBody(bank),
  );
}

Future<void> _rlsWrites(Ctx c) async {
  // Wallet mint
  final wIns = await rest(
    c.url,
    'POST',
    'wallets',
    headers: c.buyerH,
    body: {
      'id': c.buyerId,
      'balance': 9999.99,
    },
  );
  rec(
    surface: 'WALLET',
    attack: 'buyer INSERT wallet balance 9999',
    identity: 'buyer',
    result: briefBody(wIns),
  );
  final wPatch = await rest(
    c.url,
    'PATCH',
    'wallets?id=eq.${c.buyerId}',
    headers: c.buyerH,
    body: {'balance': 8888.88},
  );
  rec(
    surface: 'WALLET',
    attack: 'buyer PATCH own balance',
    identity: 'buyer',
    result: briefBody(wPatch),
  );
  if (wPatch.statusCode >= 200 && wPatch.statusCode < 300) {
    final after = await rest(
      c.url,
      'GET',
      'wallets?id=eq.${c.buyerId}&select=id,balance',
      headers: c.svcH,
    );
    final rows = asMaps(decode(after));
    final bal = rows.isEmpty ? null : rows.first['balance'];
    rec(
      surface: 'WALLET',
      attack: 'observe balance after JWT PATCH',
      identity: 'svc_observe',
      result: 'balance=$bal',
      evidence: rows,
    );
    if (bal != null && num.tryParse(bal.toString()) == 8888.88) {
      finding(
        id: 'RT1837-P0-WALLET-PATCH',
        severity: 'P0',
        title: 'JWT altera saldo de carteira',
        actor: 'buyer',
        pre: 'carteira própria',
        repro: 'PATCH /wallets balance=8888.88',
        impact: 'criação de fundos',
        evidence: rows,
      );
    }
  }

  final wt = await rest(
    c.url,
    'POST',
    'wallet_transactions',
    headers: c.buyerH,
    body: {
      'wallet_id': c.buyerId,
      'amount': 500,
      'type': 'venda',
      'description': '$prefix mint',
    },
  );
  rec(
    surface: 'LEDGER',
    attack: 'buyer INSERT wallet_transactions +500 venda',
    identity: 'buyer',
    result: briefBody(wt),
  );

  // Stripe events forge
  final ev = await rest(
    c.url,
    'POST',
    'stripe_checkout_events',
    headers: c.buyerH,
    body: {
      'session_id': 'cs_test_$prefix',
      'order_id': null,
      'event': 'refund_created',
      'detail': 'forged',
    },
  );
  rec(
    surface: 'STRIPE_EVENTS',
    attack: 'buyer INSERT refund_created',
    identity: 'buyer',
    result: briefBody(ev),
  );

  // Products: buyer inserts as seller
  final pIns = await rest(
    c.url,
    'POST',
    'products',
    headers: c.buyerH,
    body: {
      'seller_id': c.sellerId,
      'title': '$prefix hijack product',
      'price': 1,
      'quantity': 1,
      'list_on_marketplace': true,
    },
  );
  rec(
    surface: 'PRODUCTS',
    attack: 'buyer INSERT product claiming seller_id',
    identity: 'buyer',
    result: briefBody(pIns),
  );

  // Seller helpers: buyer becomes helper of seller
  final sh = await rest(
    c.url,
    'POST',
    'seller_helpers',
    headers: c.buyerH,
    body: {
      'seller_id': c.sellerId,
      'helper_user_id': c.buyerId,
      'can_manage_reservations': true,
      'can_manage_raffles': true,
      'status': 'active',
    },
  );
  rec(
    surface: 'STAFF',
    attack: 'buyer INSERT self as seller helper with raffles',
    identity: 'buyer',
    result: briefBody(sh),
  );
}

Future<void> _rpcSweep(Ctx c) async {
  final probes = <Map<String, dynamic>>[
    {
      'fn': 'batata_credit_wallet_once',
      'args': {
        'p_user_id': c.buyerId,
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_amount': 100,
        'p_type': 'venda',
        'p_description': prefix,
      },
      'who': 'buyer',
    },
    {
      'fn': 'batata_wallet_apply_tip_once',
      'args': {
        'p_wallet_id': c.buyerId,
        'p_tip_id': '00000000-0000-0000-0000-000000000001',
        'p_amount': 50,
        'p_type': 'gorjeta_recebida',
        'p_description': prefix,
      },
      'who': 'buyer',
    },
    {
      'fn': 'batata_wallet_payout_debit',
      'args': {
        'p_user_id': c.sellerId,
        'p_amount_cents': 100,
        'p_idempotency_key': '${prefix}-payout',
      },
      'who': 'buyer',
    },
    {
      'fn': 'batata_claim_checkout_session_slot',
      'args': {
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_claim_token': 'claiming:aaaaaaaaaaaa',
      },
      'who': 'buyer',
    },
    {
      'fn': 'batata_ensure_wallet',
      'args': {'p_user_id': c.sellerId},
      'who': 'buyer',
    },
    {
      'fn': 'batata_release_seller_wallet_for_order',
      'args': {'p_order_id': '00000000-0000-0000-0000-000000000001'},
      'who': 'buyer',
    },
    {
      'fn': 'batata_refund_buyer_wallet_for_order',
      'args': {'p_order_id': '00000000-0000-0000-0000-000000000001'},
      'who': 'seller',
    },
    {
      'fn': 'batata_find_user_id_by_email',
      'args': {'p_email': c.buyerEmail},
      'who': 'seller',
    },
    {
      'fn': 'batata_find_user_id_by_email',
      'args': {'p_email': c.sellerEmail},
      'who': 'buyer',
    },
    {
      'fn': 'batata_admin_resolve_dispute',
      'args': {
        'p_dispute_id': '00000000-0000-0000-0000-000000000001',
        'p_resolution': 'aceite',
        'p_note': prefix,
      },
      'who': 'buyer',
    },
    {
      'fn': 'batata_admin_resolve_dispute',
      'args': {
        'p_dispute_id': '00000000-0000-0000-0000-000000000001',
        'p_resolution': 'aceite',
        'p_note': prefix,
      },
      'who': 'anon',
    },
    {
      'fn': 'batata_draw_live_raffle_winners',
      'args': {'p_raffle_id': '00000000-0000-0000-0000-000000000001'},
      'who': 'buyer',
    },
    {
      'fn': 'batata_mark_live_item_sold',
      'args': {'p_live_item_id': '00000000-0000-0000-0000-000000000001'},
      'who': 'buyer',
    },
    {
      'fn': 'batata_create_raffle_prize_order',
      'args': {
        'p_raffle_id': '00000000-0000-0000-0000-000000000001',
        'p_winner_id': c.buyerId,
        'p_qty': 1,
      },
      'who': 'buyer',
    },
    {
      'fn': 'execute_sql',
      'args': {'query': 'select 1'},
      'who': 'buyer',
    },
    {
      'fn': 'batata_ps_claim_pairing',
      'args': {
        'p_code': '000000',
        'p_device_id': 'rt1837',
        'p_app_version': '1',
      },
      'who': 'anon',
    },
    {
      'fn': 'batata_is_admin',
      'args': <String, dynamic>{},
      'who': 'buyer',
    },
    {
      'fn': 'batata_send_live_tip_from_wallet',
      'args': {
        'p_live_id': '00000000-0000-0000-0000-000000000001',
        'p_seller_id': c.sellerId,
        'p_amount': 1,
      },
      'who': 'buyer',
    },
  ];

  for (final p in probes) {
    final who = p['who'] as String;
    final h = who == 'anon'
        ? c.anonH
        : who == 'seller'
            ? c.sellerH
            : c.buyerH;
    final fn = p['fn'] as String;
    final r = await rpc(c.url, fn, p['args'], headers: h);
    rec(
      surface: 'RPC',
      attack: 'call $fn',
      identity: who,
      result: briefBody(r),
      impact: (r.statusCode == 200 &&
              !r.body.toLowerCase().contains('error') &&
              fn.contains('wallet'))
          ? 'rpc_wallet_success'
          : '',
    );
    if (fn == 'batata_find_user_id_by_email' && r.statusCode == 200) {
      final body = r.body.trim();
      if (body.contains('-') && body.length > 30) {
        finding(
          id: 'RT1837-P2-EMAIL-UUID',
          severity: 'P2',
          title: 'RPC email→UUID devolveu identidade',
          actor: who,
          pre: 'email conhecido',
          repro: 'rpc batata_find_user_id_by_email',
          impact: 'enumeração de contas',
          evidence: briefBody(r),
        );
      }
    }
  }
}

Future<void> _edgeSweep(Ctx c) async {
  final edges = <Map<String, dynamic>>[
    {
      'fn': 'create-payment-intent',
      'who': 'buyer',
      'body': {
        'buyer_id': c.buyerId,
        'order_id': '00000000-0000-0000-0000-000000000001',
        'amount': 50,
        'quantity': 1,
        'shipping_method': 'hand',
      },
    },
    {
      'fn': 'create-payment-intent',
      'who': 'anon',
      'body': {
        'buyer_id': c.buyerId,
        'order_id': '00000000-0000-0000-0000-000000000001',
        'amount': 50,
      },
    },
    {
      'fn': 'refund-order',
      'who': 'buyer',
      'body': {'order_id': '00000000-0000-0000-0000-000000000001'},
    },
    {
      'fn': 'create-connect-account',
      'who': 'buyer',
      'body': {
        'user_id': c.sellerId,
        'amount': 10000,
        'idempotency_key': '${prefix}-payout-x',
      },
    },
    {
      'fn': 'create-live-tip-checkout',
      'who': 'buyer',
      'body': {
        'live_id': '00000000-0000-0000-0000-000000000001',
        'seller_id': c.sellerId,
        'amount_eur': 1,
      },
    },
    {
      'fn': 'create-mux-live',
      'who': 'buyer',
      'body': {'title': 'RT1837 hostile mux'},
    },
    {
      'fn': 'livekit-mux-publish',
      'who': 'buyer',
      'body': {
        'step': 'token',
        'live_id': '00000000-0000-0000-0000-000000000001',
      },
    },
    {
      'fn': 'ingest-ocr-reservation',
      'who': 'anon',
      'body': {
        'live_id': '00000000-0000-0000-0000-000000000001',
        'ocr_line_hash': 'deadbeefdeadbeef',
        'detected_at': DateTime.now().toUtc().toIso8601String(),
        'ref_number': 1,
      },
      'extra': {'x-device-token': 'forged-token-rt1837'},
    },
    {
      'fn': 'ps-pairing-claim',
      'who': 'anon',
      'body': {'code': '123456', 'device_id': 'rt1837'},
    },
    {
      'fn': 'delete-test-account',
      'who': 'buyer',
      'body': {'confirm': 'APAGAR TUDO'},
    },
    {
      'fn': 'send-sms-bulkgate',
      'who': 'anon',
      'body': {'phone': '+351900000000', 'text': 'pwn'},
    },
    {
      'fn': 'sec-fase2-e2e-oversell',
      'who': 'buyer',
      'body': {'probe': true},
    },
    {
      'fn': 'complete-mux-live',
      'who': 'buyer',
      'body': {'live_id': '00000000-0000-0000-0000-000000000001'},
    },
    {
      'fn': 'meta-data-deletion',
      'who': 'anon',
      'body': {'user_id': c.buyerId},
    },
  ];

  for (final e in edges) {
    final who = e['who'] as String;
    final h = who == 'anon'
        ? c.anonH
        : who == 'seller'
            ? c.sellerH
            : c.buyerH;
    final extra = (e['extra'] as Map?)?.map((k, v) => MapEntry('$k', '$v'));
    final r = await edge(
      c.url,
      e['fn'] as String,
      e['body'],
      headers: h,
      extraHeaders: extra,
    );
    rec(
      surface: 'EDGE',
      attack: 'POST ${e['fn']}',
      identity: who,
      result: briefBody(r),
    );
  }

  final wh = await http.post(
    Uri.parse('${c.url}/functions/v1/stripe-webhook'),
    headers: {
      ...c.anonH,
      'stripe-signature': 't=1,v1=forged',
    },
    body: jsonEncode({
      'type': 'checkout.session.completed',
      'data': {
        'object': {
          'id': 'cs_test_forged',
          'payment_status': 'paid',
          'metadata': {'order_id': '00000000-0000-0000-0000-000000000001'},
        },
      },
    }),
  );
  rec(
    surface: 'WEBHOOK',
    attack: 'POST stripe-webhook forged signature',
    identity: 'anon',
    result: briefBody(wh),
  );

  final settle = await edge(
    c.url,
    'create-payment-intent',
    null,
    headers: c.anonH,
    method: 'GET',
    query: {
      'checkout_return': 'success',
      'session_id': 'cs_test_forged_settle',
    },
  );
  rec(
    surface: 'SETTLE',
    attack: 'GET create-payment-intent checkout_return forged session',
    identity: 'anon',
    result: briefBody(settle),
  );
}

Future<Map<String, dynamic>?> _fixtureProduct(Ctx c, {int qty = 5}) async {
  try {
    return await c.admin.insert('products', {
      'seller_id': c.sellerId,
      'title': '$prefix stock $qty ${tag()}',
      'price': 5.00,
      'quantity': qty,
      'list_on_marketplace': true,
      'is_sold': false,
    });
  } catch (e) {
    rec(
      surface: 'FIXTURE',
      attack: 'svc insert product',
      identity: 'svc',
      result: '$e',
    );
    return null;
  }
}

Future<void> _orderMoney(Ctx c) async {
  final prod = await _fixtureProduct(c, qty: 3);
  if (prod == null) {
    gaps.add('sem fixture product — skip order money');
    return;
  }
  final pid = prod['id'].toString();

  // Buyer INSERT paid + fake PI + tiny price
  final hostile = await rest(
    c.url,
    'POST',
    'orders',
    headers: c.buyerH,
    body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'quantity': 99,
      'price_total': 0.01,
      'status': 'pago',
      'amount_paid_cents': 999999,
      'stripe_payment_intent_id': 'pi_fake_$prefix',
      'stripe_checkout_session_id': 'cs_fake_$prefix',
      'payment_method': 'Seguro Fleaber',
      'shipping_method': 'hand',
    },
  );
  rec(
    surface: 'ORDERS',
    attack: 'buyer INSERT pago+fake PI+qty 99+0.01€',
    identity: 'buyer',
    result: briefBody(hostile),
  );
  final hRows = asMaps(decode(hostile));
  if (hRows.isNotEmpty) {
    final row = hRows.first;
    final oid = row['id']?.toString();
    rec(
      surface: 'ORDERS',
      attack: 'observe hostile INSERT row',
      identity: 'buyer',
      result:
          'status=${row['status']} qty=${row['quantity']} total=${row['price_total']} paid=${row['amount_paid_cents']} pi=${row['stripe_payment_intent_id']}',
      evidence: {
        'status': row['status'],
        'qty': row['quantity'],
        'price_total': row['price_total'],
        'amount_paid_cents': row['amount_paid_cents'],
        'pi': row['stripe_payment_intent_id'],
        'contract_unit_cents': row['contract_unit_cents'],
        'contract_qty': row['contract_qty'],
      },
    );
    final st = '${row['status']}'.toLowerCase();
    final paid = row['amount_paid_cents'];
    final pi = '${row['stripe_payment_intent_id'] ?? ''}';
    if (st == 'pago' || (paid != null && paid != 0) || pi.startsWith('pi_')) {
      finding(
        id: 'RT1837-P0-ORDER-FAKE-PAY',
        severity: 'P0',
        title: 'JWT INSERT cria encomenda paga / PI / amount_paid',
        actor: 'buyer',
        pre: 'produto listado',
        repro: 'POST /orders status=pago amount_paid_cents PI',
        impact: 'falsificar pagamento plataforma',
        evidence: row,
      );
    }

    if (oid != null) {
      final patch = await rest(
        c.url,
        'PATCH',
        'orders?id=eq.$oid',
        headers: c.buyerH,
        body: {
          'price_total': 0.50,
          'quantity': 1,
          'status': 'pago',
          'amount_paid_cents': 1,
        },
      );
      rec(
        surface: 'ORDERS',
        attack: 'buyer PATCH money/status after insert',
        identity: 'buyer',
        result: briefBody(patch),
      );
      final obs = await rest(
        c.url,
        'GET',
        'orders?id=eq.$oid&select=id,status,price_total,quantity,amount_paid_cents,contract_unit_cents,contract_qty',
        headers: c.svcH,
      );
      rec(
        surface: 'ORDERS',
        attack: 'svc observe after JWT PATCH',
        identity: 'svc_observe',
        result: briefBody(obs),
        evidence: decode(obs),
      );

      // Checkout with underpay claim
      final ck = await edge(
        c.url,
        'create-payment-intent',
        {
          'buyer_id': c.buyerId,
          'order_id': oid,
          'amount': 50,
          'quantity': 1,
          'item_price': 0.01,
          'shipping_method': 'hand',
          'prize_shipping': true,
          'product_id': pid,
        },
        headers: c.buyerH,
      );
      rec(
        surface: 'CHECKOUT',
        attack: 'create-payment-intent amount=50 prize_shipping qty body',
        identity: 'buyer',
        result: briefBody(ck),
      );

      final ck2 = await edge(
        c.url,
        'create-payment-intent',
        {
          'buyer_id': c.buyerId,
          'order_id': oid,
          'amount': 50,
          'shipping_method': 'hand',
        },
        headers: c.buyerH,
      );
      rec(
        surface: 'CHECKOUT',
        attack: 'create-payment-intent underpay 50c vs contract',
        identity: 'buyer',
        result: briefBody(ck2),
      );
      _noteCheckoutAmount(ck2, oid);

      // Swap parties
      final swap = await rest(
        c.url,
        'PATCH',
        'orders?id=eq.$oid',
        headers: c.buyerH,
        body: {
          'buyer_id': c.sellerId,
          'seller_id': c.buyerId,
        },
      );
      rec(
        surface: 'ORDERS',
        attack: 'buyer PATCH swap buyer/seller',
        identity: 'buyer',
        result: briefBody(swap),
      );
    }
  }

  // Seller INSERT order as if buyer paid off-platform
  final off = await rest(
    c.url,
    'POST',
    'orders',
    headers: c.sellerH,
    body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 5,
      'status': 'pago',
      'payment_method': 'MB WAY',
      'shipping_method': 'hand',
    },
  );
  rec(
    surface: 'ORDERS',
    attack: 'seller INSERT pago MB WAY for buyer',
    identity: 'seller',
    result: briefBody(off),
  );

  // Cross: checkout someone else's order
  final otherOrd = await rest(
    c.url,
    'GET',
    'orders?seller_id=eq.${c.sellerId}&buyer_id=neq.${c.buyerId}&select=id,buyer_id,status&limit=1',
    headers: c.svcH,
  );
  final others = asMaps(decode(otherOrd));
  if (others.isNotEmpty) {
    final oid = others.first['id'].toString();
    final ck = await edge(
      c.url,
      'create-payment-intent',
      {
        'buyer_id': c.buyerId,
        'order_id': oid,
        'shipping_method': 'hand',
      },
      headers: c.buyerH,
    );
    rec(
      surface: 'CHECKOUT',
      attack: 'buyer checkout foreign order $oid',
      identity: 'buyer',
      result: briefBody(ck),
    );
  }
}

void _noteCheckoutAmount(http.Response ck, String oid) {
  final d = decode(ck);
  String? url;
  if (d is Map) {
    url = d['url']?.toString() ?? d['checkout_url']?.toString();
  }
  rec(
    surface: 'CHECKOUT',
    attack: 'parse session url for order $oid',
    identity: 'buyer',
    result: 'http=${ck.statusCode} url=${url != null}',
    evidence: d is Map
        ? {
            'keys': d.keys.toList(),
            'amount': d['amount'],
            'amount_cents': d['amount_cents'],
            'server_amount_cents': d['server_amount_cents'],
          }
        : briefBody(ck),
  );
}

Future<void> _stockHold(Ctx c) async {
  final prod = await _fixtureProduct(c, qty: 1);
  if (prod == null) return;
  final pid = prod['id'].toString();

  Future<http.Response> ins(String label) {
    return rest(
      c.url,
      'POST',
      'orders',
      headers: c.buyerH,
      body: {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': pid,
        'quantity': 1,
        'price_total': 5,
        'status': 'reserva_pendente',
        'payment_method': 'Seguro Fleaber',
        'shipping_method': 'hand',
      },
    );
  }

  final a = await ins('A');
  final b = await ins('B');
  rec(
    surface: 'STOCK',
    attack: 'two sequential holds qty=1 stock=1',
    identity: 'buyer',
    result: 'A=${briefBody(a)} B=${briefBody(b)}',
  );
  final aOk = a.statusCode >= 200 && a.statusCode < 300;
  final bOk = b.statusCode >= 200 && b.statusCode < 300;
  if (aOk && bOk) {
    finding(
      id: 'RT1837-P1-STOCK-DOUBLE-HOLD',
      severity: 'P1',
      title: 'Duas reservas JWT válidas para stock=1',
      actor: 'buyer',
      pre: 'produto qty=1',
      repro: 'dois POST /orders reserva_pendente qty=1',
      impact: 'capacidade duplicada; oversell se ambos checkout',
      evidence: {'a': briefBody(a), 'b': briefBody(b)},
    );
  }

  // Parallel race 10x
  final prod2 = await _fixtureProduct(c, qty: 1);
  if (prod2 != null) {
    final pid2 = prod2['id'].toString();
    final futs = List.generate(
      10,
      (i) => rest(
        c.url,
        'POST',
        'orders',
        headers: c.buyerH,
        body: {
          'buyer_id': c.buyerId,
          'seller_id': c.sellerId,
          'product_id': pid2,
          'quantity': 1,
          'price_total': 5,
          'status': 'reserva_pendente',
          'payment_method': 'Seguro Fleaber',
          'shipping_method': 'hand',
        },
      ),
    );
    final rs = await Future.wait(futs);
    final oks = rs.where((r) => r.statusCode >= 200 && r.statusCode < 300).length;
    rec(
      surface: 'STOCK',
      attack: '10 concurrent INSERT holds stock=1',
      identity: 'buyer',
      result: 'ok=$oks / 10 statuses=${rs.map((e) => e.statusCode).toList()}',
    );
    if (oks > 1) {
      finding(
        id: 'RT1837-P1-STOCK-RACE',
        severity: 'P1',
        title: 'Race: mais de um hold JWT em stock=1',
        actor: 'buyer',
        pre: 'produto qty=1',
        repro: '10 POST /orders concorrentes',
        impact: 'oversell de capacidade',
        evidence: {'ok': oks, 'codes': rs.map((e) => e.statusCode).toList()},
      );
    }
  }
}

Future<void> _reviewsDisputesOffers(Ctx c) async {
  final rev = await rest(
    c.url,
    'POST',
    'reviews',
    headers: c.buyerH,
    body: {
      'reviewer_id': c.buyerId,
      'reviewee_id': c.sellerId,
      'rating': 5,
      'comment': '$prefix forged',
      'role': 'buyer',
      'purchase_verified': true,
    },
  );
  rec(
    surface: 'REVIEWS',
    attack: 'buyer INSERT review verified without order',
    identity: 'buyer',
    result: briefBody(rev),
  );
  if (rev.statusCode >= 200 && rev.statusCode < 300) {
    finding(
      id: 'RT1837-P1-REVIEW-FORGE',
      severity: 'P1',
      title: 'Review forjada sem transacção',
      actor: 'buyer',
      pre: 'nenhuma',
      repro: 'POST /reviews purchase_verified=true',
      impact: 'reputação falsa',
      evidence: briefBody(rev),
    );
  }

  final asSeller = await rest(
    c.url,
    'POST',
    'reviews',
    headers: c.buyerH,
    body: {
      'reviewer_id': c.sellerId,
      'reviewee_id': c.buyerId,
      'rating': 1,
      'comment': '$prefix as seller',
      'role': 'seller',
    },
  );
  rec(
    surface: 'REVIEWS',
    attack: 'buyer INSERT review in seller identity',
    identity: 'buyer',
    result: briefBody(asSeller),
  );

  final disp = await rest(
    c.url,
    'POST',
    'order_disputes',
    headers: c.buyerH,
    body: {
      'order_id': '00000000-0000-0000-0000-000000000001',
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'reason': prefix,
      'status': 'aberta',
    },
  );
  rec(
    surface: 'DISPUTES',
    attack: 'buyer INSERT dispute on fake order',
    identity: 'buyer',
    result: briefBody(disp),
  );

  // Offer self-accept: create as buyer then PATCH accepted
  final prods = await rest(
    c.url,
    'GET',
    'products?seller_id=eq.${c.sellerId}&list_on_marketplace=eq.true&select=id,price,quantity&limit=1',
    headers: c.buyerH,
  );
  final plist = asMaps(decode(prods));
  if (plist.isNotEmpty) {
    final pid = plist.first['id'].toString();
    final off = await rest(
      c.url,
      'POST',
      'product_offers',
      headers: c.buyerH,
      body: {
        'product_id': pid,
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'amount': 0.01,
        'offered_by': 'buyer',
        'status': 'accepted',
      },
    );
    rec(
      surface: 'OFFERS',
      attack: 'buyer INSERT offer amount=0.01 status=accepted',
      identity: 'buyer',
      result: briefBody(off),
    );
    final oRows = asMaps(decode(off));
    if (oRows.isNotEmpty) {
      final oid = oRows.first['id'].toString();
      rec(
        surface: 'OFFERS',
        attack: 'observe offer INSERT',
        identity: 'buyer',
        result:
            'status=${oRows.first['status']} amount=${oRows.first['amount']}',
        evidence: oRows.first,
      );
      final acc = await rest(
        c.url,
        'PATCH',
        'product_offers?id=eq.$oid',
        headers: c.buyerH,
        body: {'status': 'accepted', 'amount': 0.01},
      );
      rec(
        surface: 'OFFERS',
        attack: 'buyer self-accept offer',
        identity: 'buyer',
        result: briefBody(acc),
      );
    }
  }
}

Future<void> _privacyChatStorage(Ctx c) async {
  final chats = await rest(
    c.url,
    'GET',
    'chats?select=id,buyer_id,seller_id&limit=20',
    headers: c.buyerH,
  );
  rec(
    surface: 'CHAT',
    attack: 'buyer GET chats',
    identity: 'buyer',
    result: briefBody(chats),
  );
  final clist = asMaps(decode(chats));
  final foreign = clist.where((r) {
    final b = r['buyer_id']?.toString();
    final s = r['seller_id']?.toString();
    return b != c.buyerId && s != c.buyerId;
  }).toList();
  if (foreign.isNotEmpty) {
    finding(
      id: 'RT1837-P1-CHAT-LIST',
      severity: 'P1',
      title: 'Buyer lista chats alheios',
      actor: 'buyer',
      pre: 'JWT',
      repro: 'GET /chats',
      impact: 'metadados de conversas alheias',
      evidence: {'n': foreign.length, 'sample': foreign.take(3).toList()},
    );
    final cid = foreign.first['id'].toString();
    final msgs = await rest(
      c.url,
      'GET',
      'chat_messages?chat_id=eq.$cid&select=id,body,sender_id&limit=5',
      headers: c.buyerH,
    );
    rec(
      surface: 'CHAT',
      attack: 'buyer GET messages of foreign chat',
      identity: 'buyer',
      result: briefBody(msgs),
    );
    if (msgs.statusCode == 200 && asMaps(decode(msgs)).isNotEmpty) {
      finding(
        id: 'RT1837-P1-CHAT-MSGS',
        severity: 'P1',
        title: 'Buyer lê mensagens de chat alheio',
        actor: 'buyer',
        pre: 'chat_id alheio',
        repro: 'GET /chat_messages?chat_id=eq.',
        impact: 'conteúdo privado',
        evidence: briefBody(msgs),
      );
    }
  }

  final disp = await rest(
    c.url,
    'GET',
    'order_disputes?select=id,order_id,buyer_id,seller_id,reason,status&limit=10',
    headers: c.buyerH,
  );
  rec(
    surface: 'DISPUTES',
    attack: 'buyer GET disputes',
    identity: 'buyer',
    result: briefBody(disp),
  );
  final dlist = asMaps(decode(disp));
  final dForeign = dlist.where((r) {
    return r['buyer_id']?.toString() != c.buyerId &&
        r['seller_id']?.toString() != c.buyerId;
  }).toList();
  if (dForeign.isNotEmpty) {
    finding(
      id: 'RT1837-P1-DISPUTE-READ',
      severity: 'P1',
      title: 'Buyer lê disputas alheias',
      actor: 'buyer',
      pre: 'JWT',
      repro: 'GET /order_disputes',
      impact: 'PII / provas',
      evidence: {'n': dForeign.length},
    );
  }

  // Storage list
  final st = await http.get(
    Uri.parse(
      '${c.url}/storage/v1/object/list/fleaber_private?prefix=order_disputes/',
    ),
    headers: {
      'apikey': c.anon,
      'Authorization': 'Bearer ${c.buyerJwt}',
    },
  );
  rec(
    surface: 'STORAGE',
    attack: 'list fleaber_private order_disputes',
    identity: 'buyer',
    result: briefBody(st),
  );

  final pub = await http.get(
    Uri.parse('${c.url}/storage/v1/object/list/product-images'),
    headers: {
      'apikey': c.anon,
      'Authorization': 'Bearer ${c.anon}',
    },
  );
  rec(
    surface: 'STORAGE',
    attack: 'anon list product-images',
    identity: 'anon',
    result: briefBody(pub),
  );
}

Future<void> _profilesAuthz(Ctx c) async {
  final patch = await rest(
    c.url,
    'PATCH',
    'profiles?id=eq.${c.buyerId}',
    headers: c.buyerH,
    body: {
      'user_type': 'admin',
    },
  );
  rec(
    surface: 'AUTH',
    attack: 'buyer PATCH user_type=admin',
    identity: 'buyer',
    result: briefBody(patch),
  );
  final obs = await rest(
    c.url,
    'GET',
    'profiles?id=eq.${c.buyerId}&select=id,user_type',
    headers: c.svcH,
  );
  final rows = asMaps(decode(obs));
  rec(
    surface: 'AUTH',
    attack: 'observe user_type after PATCH',
    identity: 'svc_observe',
    result: briefBody(obs),
    evidence: rows,
  );
  if (rows.isNotEmpty &&
      '${rows.first['user_type']}'.toLowerCase().contains('admin')) {
    finding(
      id: 'RT1837-P0-ADMIN-TYPE',
      severity: 'P0',
      title: 'Buyer eleva user_type a admin',
      actor: 'buyer',
      pre: 'JWT próprio',
      repro: 'PATCH /profiles user_type=admin',
      impact: 'autoridade admin',
      evidence: rows,
    );
    // revert via svc
    try {
      await c.admin.patch(
        'profiles',
        'id=eq.${c.buyerId}',
        {'user_type': 'comprador'},
      );
    } catch (_) {}
  }

  final other = await rest(
    c.url,
    'PATCH',
    'profiles?id=eq.${c.sellerId}',
    headers: c.buyerH,
    body: {'full_name': '$prefix hijack'},
  );
  rec(
    surface: 'AUTH',
    attack: 'buyer PATCH seller profile',
    identity: 'buyer',
    result: briefBody(other),
  );
}
