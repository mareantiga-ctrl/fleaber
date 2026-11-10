/// PASS 3 — composição, races, RPCs privilegiados, premio_rifa×hold, storage, PII.
/// Auditoria cega 20260830T1837. Não corrige. Não produção.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '_rt.dart';

Future<void> main() async {
  final c = await boot();
  stdout.writeln('PASS3 boot');

  await _rpcPrivileged(c);
  await _piiRetry(c);
  await _premioRifaHoldBypass(c);
  await _altStatusHolds(c);
  await _storageDeep(c);
  await _chatInject(c);
  await _bankingOracle(c);
  await _dualSettle(c);
  await _reviewsGerais(c);
  await _tipAndRaffle(c);
  await _partialRefundRpc(c);

  await dumpJson('pass3', {
    'pass': 3,
    'project': projectMust,
    'utc': DateTime.now().toUtc().toIso8601String(),
    'matrix': matrix,
    'findings': findings,
    'gaps': gaps,
    'invariants': invariants,
  });
  stdout.writeln(
    'PASS3 done matrix=${matrix.length} findings=${findings.length}',
  );
}

Future<void> _rpcPrivileged(Ctx c) async {
  final calls = <Map<String, dynamic>>[
    {
      'fn': 'batata_admin_list_profiles',
      'args': {'p_limit': 20},
      'who': 'buyer',
    },
    {
      'fn': 'staging_nuke_user_data',
      'args': {'p_user_id': c.buyerId},
      'who': 'buyer',
    },
    {
      'fn': 'staging_restore_stock_before_nuke',
      'args': {'p_user_id': c.sellerId},
      'who': 'buyer',
    },
    {
      'fn': 'batata_lab_clear_all_fm_pending',
      'args': <String, dynamic>{},
      'who': 'buyer',
    },
    {
      'fn': 'batata_debit_wallet_once',
      'args': {
        'p_wallet_id': c.sellerId,
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_amount': 1,
        'p_type': 'levantamento',
      },
      'who': 'buyer',
    },
    {
      'fn': 'batata_finalize_stripe_order_refund',
      'args': {
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_refund_id': 're_fake',
        'p_payment_intent_id': 'pi_fake',
        'p_session_id': 'cs_fake',
        'p_amount_cents': 100,
      },
      'who': 'buyer',
    },
    {
      'fn': 'batata_clawback_seller_wallet_for_order',
      'args': {'p_order_id': '00000000-0000-0000-0000-000000000001'},
      'who': 'buyer',
    },
    {
      'fn': 'batata_settle_live_tip_from_stripe',
      'args': {
        'p_tip_id': '00000000-0000-0000-0000-000000000001',
        'p_session_id': 'cs_fake',
        'p_amount_cents': 100,
      },
      'who': 'buyer',
    },
    {
      'fn': 'batata_wallet_payout_finish',
      'args': {
        'p_idempotency_key': 'x',
        'p_transfer_id': 'tr_fake',
        'p_ok': true,
      },
      'who': 'buyer',
    },
    {
      'fn': 'batata_record_buyer_purchase_ledger',
      'args': {'p_order_id': '00000000-0000-0000-0000-000000000001'},
      'who': 'buyer',
    },
    {
      'fn': 'batata_award_live_raffle_tickets',
      'args': {
        'p_raffle_id': '00000000-0000-0000-0000-000000000001',
        'p_buyer_id': c.buyerId,
        'p_source': 'share',
        'p_qty': 10,
        'p_meta': 'x',
      },
      'who': 'buyer',
    },
    {
      'fn': 'batata_confirm_ps_reservation',
      'args': {'p_reservation_id': '00000000-0000-0000-0000-000000000001'},
      'who': 'buyer',
    },
    {
      'fn': 'batata_live_reservation_stripe_convert',
      'args': {'p_reservation_id': '00000000-0000-0000-0000-000000000001'},
      'who': 'buyer',
    },
    {
      'fn': 'batata_generate_auto_feedback',
      'args': {'p_order_id': '00000000-0000-0000-0000-000000000001'},
      'who': 'buyer',
    },
    {
      'fn': 'batata_process_partial_refund_dispute',
      'args': {
        'p_dispute_id': '00000000-0000-0000-0000-000000000001',
        'p_percent': 100,
      },
      'who': 'buyer',
    },
    {
      'fn': 'batata_anon_rate_check',
      'args': {
        'p_key': 'x',
        'p_rpc': 'x',
        'p_limit': 1,
      },
      'who': 'anon',
    },
    {
      'fn': 'batata_invoke_livekit_egress_cleanup',
      'args': <String, dynamic>{},
      'who': 'buyer',
    },
    {
      'fn': 'batata_create_seller_device_token',
      'args': {'p_label': 'rt1837'},
      'who': 'buyer',
    },
  ];

  for (final p in calls) {
    final who = p['who'] as String;
    final h = who == 'anon' ? c.anonH : who == 'seller' ? c.sellerH : c.buyerH;
    final fn = p['fn'] as String;
    final r = await rpc(c.url, fn, p['args'], headers: h);
    rec(
      surface: 'RPC',
      attack: 'priv $fn',
      identity: who,
      result: briefBody(r),
    );
    final ok = r.statusCode == 200 &&
        !r.body.toLowerCase().contains('permission') &&
        !r.body.toLowerCase().contains('not_allowed') &&
        !r.body.toLowerCase().contains('denied');
    if (ok &&
        (fn.contains('admin') ||
            fn.contains('nuke') ||
            fn.contains('finalize') ||
            fn.contains('debit') ||
            fn.contains('award') ||
            fn.contains('settle_live_tip') ||
            fn.contains('payout_finish'))) {
      finding(
        id: 'RT1837-P1-RPC-$fn',
        severity: fn.contains('nuke') || fn.contains('debit') || fn.contains('finalize')
            ? 'P1'
            : 'P2',
        title: 'RPC privilegiado executável por JWT: $fn',
        actor: who,
        pre: 'JWT',
        repro: 'POST /rpc/$fn',
        impact: 'autoridade indevida',
        evidence: briefBody(r),
      );
    }
  }
}

Future<void> _piiRetry(Ctx c) async {
  final r = await rest(
    c.url,
    'GET',
    'profiles?select=id,full_name,phone,mb_way,iban,shipping_line1,shipping_city,legal_full_name&limit=20',
    headers: c.buyerH,
  );
  rec(
    surface: 'PROFILES',
    attack: 'buyer SELECT banking/PII no nif',
    identity: 'buyer',
    result: briefBody(r),
  );
  final rows = asMaps(decode(r));
  final others = rows.where((x) => x['id']?.toString() != c.buyerId).toList();
  rec(
    surface: 'PROFILES',
    attack: 'other profile rows',
    identity: 'buyer',
    result: 'n_other=${others.length} n_total=${rows.length}',
    evidence: others.take(3).map((e) => {
          'id': e['id'],
          'iban': e['iban'],
          'mb_way': e['mb_way'],
          'phone': e['phone'],
          'ship': e['shipping_line1'],
        }).toList(),
  );
  final leaked = others.where((x) {
    return '${x['iban'] ?? ''}${x['mb_way'] ?? ''}${x['phone'] ?? ''}${x['shipping_line1'] ?? ''}'
        .trim()
        .isNotEmpty;
  }).toList();
  if (leaked.isNotEmpty) {
    finding(
      id: 'RT1837-P1-PII-PROFILES',
      severity: 'P1',
      title: 'Buyer lê PII/banking de outros perfis',
      actor: 'buyer',
      pre: 'JWT',
      repro: 'GET /profiles select iban,mb_way,phone,shipping',
      impact: 'dados bancários / morada alheios',
      evidence: {'n': leaked.length},
    );
  }
}

Future<Map<String, dynamic>?> _prod(Ctx c, {int qty = 1, double price = 8}) async {
  try {
    return await c.admin.insert('products', {
      'seller_id': c.sellerId,
      'title': '$prefix p3 ${tag()}',
      'price': price,
      'quantity': qty,
      'list_on_marketplace': true,
      'is_sold': false,
    });
  } catch (e) {
    rec(surface: 'FIXTURE', attack: 'product', identity: 'svc', result: '$e');
    return null;
  }
}

Future<Map<String, dynamic>?> _insOrder(
  Ctx c,
  String pid, {
  String status = 'reserva_pendente',
  String pay = 'Seguro Fleaber',
}) async {
  final r = await rest(
    c.url,
    'POST',
    'orders',
    headers: c.buyerH,
    body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'quantity': 1,
      'price_total': 8,
      'status': status,
      'payment_method': pay,
      'shipping_method': 'hand',
    },
  );
  rec(
    surface: 'STOCK',
    attack: 'INSERT status=$status',
    identity: 'buyer',
    result: briefBody(r),
  );
  final rows = asMaps(decode(r));
  return rows.isEmpty ? null : rows.first;
}

Future<void> _premioRifaHoldBypass(Ctx c) async {
  final p = await _prod(c, qty: 1, price: 8);
  if (p == null) return;
  final pid = p['id'].toString();
  final a = await _insOrder(c, pid);
  if (a == null) return;
  final aid = a['id'].toString();

  final patch = await rest(
    c.url,
    'PATCH',
    'orders?id=eq.$aid',
    headers: c.buyerH,
    body: {'status': 'premio_rifa'},
  );
  rec(
    surface: 'STOCK',
    attack: 'buyer PATCH hold → premio_rifa',
    identity: 'buyer',
    result: briefBody(patch),
  );
  final obs = await rest(
    c.url,
    'GET',
    'orders?id=eq.$aid&select=id,status',
    headers: c.svcH,
  );
  rec(
    surface: 'STOCK',
    attack: 'observe status after premio_rifa patch',
    identity: 'svc_observe',
    result: briefBody(obs),
    evidence: decode(obs),
  );
  final st = asMaps(decode(obs)).firstOrNull?['status']?.toString() ?? '';

  final b = await _insOrder(c, pid);
  rec(
    surface: 'STOCK',
    attack: 'second hold after A status=$st',
    identity: 'buyer',
    result: b == null ? 'blocked' : 'CREATED ${b['id']} status=${b['status']}',
  );

  if (b != null && st.toLowerCase() == 'premio_rifa') {
    final ckA = await edge(
      c.url,
      'create-payment-intent',
      {
        'buyer_id': c.buyerId,
        'order_id': aid,
        'shipping_method': 'hand',
        'prize_shipping': true,
      },
      headers: c.buyerH,
    );
    final ckB = await edge(
      c.url,
      'create-payment-intent',
      {
        'buyer_id': c.buyerId,
        'order_id': b['id'],
        'shipping_method': 'hand',
      },
      headers: c.buyerH,
    );
    rec(
      surface: 'STOCK',
      attack: 'checkout A premio_rifa + B hold',
      identity: 'buyer',
      result: 'A=${briefBody(ckA)} B=${briefBody(ckB)}',
    );
    if (ckA.statusCode == 200 && ckB.statusCode == 200) {
      finding(
        id: 'RT1837-P1-PREMIO-HOLD',
        severity: 'P1',
        title: 'premio_rifa liberta hold e permite 2ª order+checkout em stock=1',
        actor: 'buyer',
        pre: 'produto qty=1',
        repro: 'PATCH premio_rifa; segundo INSERT; dois create-payment-intent',
        impact: 'duas Sessions na última unidade',
        evidence: {'a': briefBody(ckA), 'b': briefBody(ckB)},
      );
    }
  }
}

Future<void> _altStatusHolds(Ctx c) async {
  final p = await _prod(c, qty: 1, price: 8);
  if (p == null) return;
  final pid = p['id'].toString();
  for (final st in [
    'pendente',
    'draft',
    'open',
    'saco',
    'cart',
    'new',
    'aguardando',
    'premio_rifa',
  ]) {
    await _insOrder(c, pid, status: st);
  }
}

Future<void> _storageDeep(Ctx c) async {
  for (final prefix in [
    'order_disputes/',
    'order_proofs/',
    'chat_uploads/',
    'order_disputes/${c.sellerId}/',
    'order_proofs/${c.sellerId}/',
    'chat_uploads/${c.sellerId}/',
  ]) {
    final r = await http.post(
      Uri.parse('${c.url}/storage/v1/object/list/fleaber_private'),
      headers: {
        'apikey': c.anon,
        'Authorization': 'Bearer ${c.buyerJwt}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'prefix': prefix, 'limit': 20}),
    );
    rec(
      surface: 'STORAGE',
      attack: 'list fleaber_private prefix=$prefix',
      identity: 'buyer',
      result: briefBody(r),
    );
    if (r.statusCode == 200) {
      final list = decode(r);
      if (list is List && list.isNotEmpty) {
        final names = list.whereType<Map>().map((e) => e['name']).toList();
        rec(
          surface: 'STORAGE',
          attack: 'names under $prefix',
          identity: 'buyer',
          result: 'n=${names.length}',
          evidence: names.take(10).toList(),
        );
      }
    }
  }
}

Future<void> _chatInject(Ctx c) async {
  final chats = await rest(
    c.url,
    'GET',
    'chats?select=id,user_a,user_b&limit=30',
    headers: c.buyerH,
  );
  final clist = asMaps(decode(chats));
  final foreign = clist.where((r) {
    return r['user_a']?.toString() != c.buyerId &&
        r['user_b']?.toString() != c.buyerId;
  }).toList();
  rec(
    surface: 'CHAT',
    attack: 'foreign chats count',
    identity: 'buyer',
    result: 'foreign=${foreign.length} total=${clist.length}',
  );
  if (foreign.isNotEmpty) {
    final cid = foreign.first['id'].toString();
    final ins = await rest(
      c.url,
      'POST',
      'chat_messages',
      headers: c.buyerH,
      body: {
        'chat_id': cid,
        'sender_id': c.buyerId,
        'text': '$prefix inject',
      },
    );
    rec(
      surface: 'CHAT',
      attack: 'INSERT message into foreign chat',
      identity: 'buyer',
      result: briefBody(ins),
    );
    if (ins.statusCode >= 200 && ins.statusCode < 300 && asMaps(decode(ins)).isNotEmpty) {
      finding(
        id: 'RT1837-P1-CHAT-INJECT',
        severity: 'P1',
        title: 'Buyer injeta mensagem em chat alheio',
        actor: 'buyer',
        pre: 'chat_id alheio',
        repro: 'POST /chat_messages',
        impact: 'spoof / conteúdo em thread alheia',
        evidence: briefBody(ins),
      );
    }
  }

  // Cross read via seller JWT of a chat without seller? skip
}

Future<void> _bankingOracle(Ctx c) async {
  final own = await rpc(
    c.url,
    'batata_get_my_payout_details',
    <String, dynamic>{},
    headers: c.buyerH,
  );
  rec(
    surface: 'BANKING',
    attack: 'get_my_payout_details buyer',
    identity: 'buyer',
    result: briefBody(own),
  );

  final lab = await rpc(
    c.url,
    'batata_seller_direct_payment_details',
    {'p_seller_id': c.sellerId},
    headers: c.buyerH,
  );
  rec(
    surface: 'BANKING',
    attack: 'seller_direct_payment_details lab seller (has orders)',
    identity: 'buyer',
    result: briefBody(lab),
  );

  final prods = await rest(
    c.url,
    'GET',
    'products?select=seller_id&limit=30',
    headers: c.buyerH,
  );
  final sids = asMaps(decode(prods))
      .map((e) => e['seller_id']?.toString() ?? '')
      .where((id) => id.isNotEmpty && id != c.sellerId && id != c.buyerId)
      .toSet();
  rec(
    surface: 'BANKING',
    attack: 'other seller ids from catalog',
    identity: 'buyer',
    result: 'n=${sids.length}',
  );
  for (final sid in sids.take(5)) {
    final r = await rpc(
      c.url,
      'batata_seller_direct_payment_details',
      {'p_seller_id': sid},
      headers: c.buyerH,
    );
    rec(
      surface: 'BANKING',
      attack: 'oracle seller $sid',
      identity: 'buyer',
      result: briefBody(r),
    );
    final d = decode(r);
    var leaked = false;
    if (d is List && d.isNotEmpty) {
      final m = d.first;
      if (m is Map &&
          ('${m['iban'] ?? ''}${m['mb_way'] ?? ''}'.trim().isNotEmpty)) {
        leaked = true;
      }
    }
    if (leaked) {
      finding(
        id: 'RT1837-P1-BANK-ORACLE',
        severity: 'P1',
        title: 'RPC devolve IBAN/MB WAY de vendedor sem relação',
        actor: 'buyer',
        pre: 'seller_id de catálogo sem order',
        repro: 'rpc batata_seller_direct_payment_details',
        impact: 'dados bancários',
        evidence: briefBody(r),
      );
    }
  }
}

Future<void> _dualSettle(Ctx c) async {
  if (c.crashSecret.isEmpty) {
    gaps.add('sem e2e secret dual settle');
    return;
  }
  // Two concurrent setup_paid_order — independent products, not oversell.
  // Dual GET settle on one session from a new checkout.
  final p = await _prod(c, qty: 1, price: 9);
  if (p == null) return;
  final o = await _insOrder(c, p['id'].toString());
  if (o == null) return;
  final ck = await edge(
    c.url,
    'create-payment-intent',
    {
      'buyer_id': c.buyerId,
      'order_id': o['id'],
      'shipping_method': 'hand',
    },
    headers: c.buyerH,
  );
  rec(
    surface: 'SETTLE',
    attack: 'create session for dual settle',
    identity: 'buyer',
    result: briefBody(ck),
  );
  final d = decode(ck);
  if (d is! Map) return;
  final sid = '${d['checkoutSessionId'] ?? ''}';
  if (sid.isEmpty) return;
  final futs = List.generate(
    8,
    (_) => edge(
      c.url,
      'create-payment-intent',
      null,
      headers: c.anonH,
      method: 'GET',
      query: {'checkout_return': 'success', 'session_id': sid},
    ),
  );
  final rs = await Future.wait(futs);
  var paidish = 0;
  for (final r in rs) {
    rec(
      surface: 'SETTLE',
      attack: 'GET settle unpaid session',
      identity: 'anon',
      result: briefBody(r),
    );
    if (r.body.toLowerCase().contains('pago') ||
        r.body.toLowerCase().contains('recebido')) {
      paidish++;
    }
  }
  rec(
    surface: 'SETTLE',
    attack: 'unpaid session settle race paidish',
    identity: 'anon',
    result: 'paidish=$paidish / 8',
  );

  final obs = await rest(
    c.url,
    'GET',
    'orders?id=eq.${o['id']}&select=id,status,amount_paid_cents',
    headers: c.svcH,
  );
  rec(
    surface: 'SETTLE',
    attack: 'observe order after forged settle GETs',
    identity: 'svc_observe',
    result: briefBody(obs),
    evidence: decode(obs),
  );
}

Future<void> _reviewsGerais(Ctx c) async {
  final r = await rest(
    c.url,
    'POST',
    'reviews_gerais',
    headers: c.buyerH,
    body: {
      'reviewer_id': c.buyerId,
      'reviewee_id': c.sellerId,
      'stars': 5,
      'comment': '$prefix gerais',
    },
  );
  rec(
    surface: 'REVIEWS',
    attack: 'INSERT reviews_gerais',
    identity: 'buyer',
    result: briefBody(r),
  );
}

Future<void> _tipAndRaffle(Ctx c) async {
  final lives = await rest(
    c.url,
    'GET',
    'lives?select=id,seller_id,status,is_active&limit=5',
    headers: c.buyerH,
  );
  rec(
    surface: 'LIVE',
    attack: 'buyer list lives',
    identity: 'buyer',
    result: briefBody(lives),
  );
  final ll = asMaps(decode(lives));
  if (ll.isNotEmpty) {
    final live = ll.first;
    final lid = live['id'].toString();
    final sid = live['seller_id']?.toString() ?? c.sellerId;
    final tip = await rpc(
      c.url,
      'batata_send_live_tip_from_wallet',
      {
        'p_live_id': lid,
        'p_seller_id': sid,
        'p_amount': 1,
        'p_message': prefix,
      },
      headers: c.buyerH,
    );
    rec(
      surface: 'TIPS',
      attack: 'wallet tip to live',
      identity: 'buyer',
      result: briefBody(tip),
    );

    final pending = await rpc(
      c.url,
      'batata_create_live_tip_pending',
      {
        'p_live_id': lid,
        'p_seller_id': sid,
        'p_amount': 1,
        'p_message': prefix,
        'p_stripe_session_id': 'cs_fake_$prefix',
      },
      headers: c.buyerH,
    );
    rec(
      surface: 'TIPS',
      attack: 'create_live_tip_pending with fake session',
      identity: 'buyer',
      result: briefBody(pending),
    );
  }

  final raffles = await rest(
    c.url,
    'GET',
    'live_raffles?select=id,live_id,status&limit=5',
    headers: c.buyerH,
  );
  rec(
    surface: 'RAFFLE',
    attack: 'buyer GET raffles',
    identity: 'buyer',
    result: briefBody(raffles),
  );
  final rf = asMaps(decode(raffles));
  if (rf.isNotEmpty) {
    final id = rf.first['id'].toString();
    final join = await rpc(
      c.url,
      'batata_join_live_raffle',
      {'p_raffle_id': id},
      headers: c.buyerH,
    );
    rec(
      surface: 'RAFFLE',
      attack: 'join raffle',
      identity: 'buyer',
      result: briefBody(join),
    );
    final draw = await rpc(
      c.url,
      'batata_draw_live_raffle_winners',
      {'p_raffle_id': id},
      headers: c.buyerH,
    );
    rec(
      surface: 'RAFFLE',
      attack: 'buyer draw raffle',
      identity: 'buyer',
      result: briefBody(draw),
    );
  }
}

Future<void> _partialRefundRpc(Ctx c) async {
  final ds = await rest(
    c.url,
    'GET',
    'order_disputes?select=id,order_id,status,buyer_id&limit=5',
    headers: c.buyerH,
  );
  rec(
    surface: 'DISPUTES',
    attack: 'list own disputes for partial',
    identity: 'buyer',
    result: briefBody(ds),
  );
  final list = asMaps(decode(ds));
  if (list.isEmpty) return;
  final id = list.first['id'].toString();
  final r = await rpc(
    c.url,
    'batata_process_partial_refund_dispute',
    {'p_dispute_id': id, 'p_percent': 100},
    headers: c.buyerH,
  );
  rec(
    surface: 'REFUND',
    attack: 'buyer process_partial_refund 100%',
    identity: 'buyer',
    result: briefBody(r),
  );
  final r2 = await rpc(
    c.url,
    'batata_process_partial_refund_dispute',
    {'p_dispute_id': id, 'p_percent': 100},
    headers: c.sellerH,
  );
  rec(
    surface: 'REFUND',
    attack: 'seller process_partial_refund 100%',
    identity: 'seller',
    result: briefBody(r2),
  );
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
