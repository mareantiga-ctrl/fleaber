/// PASS 3 — composition + extra races. Blind independent 20260830T1752.
import 'dart:io';

import 'package:http/http.dart' as http;

import '_http.dart';

Future<void> main() async {
  final c = await boot();
  stdout.writeln('PASS3 boot');

  await _bagMix(c);
  await _crossUserCheckout(c);
  await _tipWalletMint(c);
  await _ocrIngest(c);
  await _muxBuyer(c);
  await _livekitForeign(c);
  await _disputeInsert(c);
  await _partialRefundFields(c);
  await _refundConcurrent(c);
  await _ensureWalletOther(c);
  await _anonDefiner(c);
  await _storageForeign(c);
  await _messagesForeign(c);

  await dumpJson(
    'tool/redteam_blind_indep_20260830T1752/out/pass3.json',
    {
      'project': projectMust,
      'pass': 3,
      'matrix': matrix,
      'findings': findings,
      'gaps': gaps,
    },
  );
  stdout.writeln('PASS3 done matrix=${matrix.length} findings=${findings.length}');
}

Future<Map?> _lastBuyerOrder(Ctx c) async {
  final r = await rest(
    c.url,
    'GET',
    'orders?buyer_id=eq.${c.buyerId}&select=id,status,product_id,seller_id,price_total,contract_unit_cents&order=created_at.desc&limit=1',
    headers: c.buyerH,
  );
  final j = tryJson(r);
  if (j is List && j.isNotEmpty) return j[0] as Map;
  return null;
}

Future<void> _bagMix(Ctx c) async {
  final o = await _lastBuyerOrder(c);
  if (o == null) return;
  final r = await edge(
    c.url,
    'create-payment-intent',
    {
      'buyer_id': c.buyerId,
      'bag_checkout': true,
      'bag_lines': [
        {'order_id': o['id'], 'line_total_cents': 1, 'quantity': 99},
        {'order_id': o['id'], 'line_total_cents': 1},
      ],
      'shipping_method': 'hand',
      'amount': 1,
    },
    anon: c.anon,
    jwt: c.buyerJwt,
  );
  rec(surface: 'BAG', attack: 'dup line + amount 1', identity: 'buyer', result: brief(r, 300));
}

Future<void> _crossUserCheckout(Ctx c) async {
  final foreign = await rest(
    c.url,
    'GET',
    'orders?buyer_id=neq.${c.buyerId}&select=id,buyer_id,seller_id,status&limit=3',
    headers: c.svcH,
  );
  rec(surface: 'ORDERS', attack: 'observe foreign orders', identity: 'service_role_observe', result: brief(foreign, 200));
  final j = tryJson(foreign);
  if (j is! List || j.isEmpty) return;
  final oid = j[0]['id'].toString();
  final owner = j[0]['buyer_id'].toString();
  final r = await edge(
    c.url,
    'create-payment-intent',
    {
      'buyer_id': c.buyerId,
      'order_id': oid,
      'shipping_method': 'hand',
    },
    anon: c.anon,
    jwt: c.buyerJwt,
  );
  rec(
    surface: 'CHECKOUT',
    attack: 'checkout foreign order owner=$owner',
    identity: 'buyer',
    result: brief(r, 280),
  );
  if (looksOk(r)) {
    finding(
      id: 'RT1752-P0-CROSS-CHECKOUT',
      severity: 'P0',
      title: 'Buyer criou Session para order de outro buyer',
      actor: 'buyer JWT',
      pre: 'UUID de order alheia',
      repro: 'POST create-payment-intent order_id alheio',
      impact: 'cross-user financeiro',
      evidence: brief(r),
    );
  }
}

Future<void> _tipWalletMint(Ctx c) async {
  final lives = await rest(
    c.url,
    'GET',
    'lives?select=id,seller_id,vendedor_id&limit=3',
    headers: c.svcH,
  );
  rec(surface: 'TIPS', attack: 'observe lives', identity: 'observe', result: brief(lives, 200));
  String? liveId;
  try {
    final j = tryJson(lives);
    if (j is List && j.isNotEmpty) liveId = j[0]['id']?.toString();
  } catch (_) {}
  final r = await rpcRaw(
    c.url,
    'batata_send_live_tip_from_wallet',
    {
      'p_live_id': liveId ?? '00000000-0000-0000-0000-000000000001',
      'p_seller_id': c.sellerId,
      'p_amount': 1,
    },
    headers: c.buyerH,
  );
  rec(surface: 'TIPS', attack: 'wallet tip 1eur', identity: 'buyer', result: brief(r));

  final t = await edge(
    c.url,
    'create-live-tip-checkout',
    {
      'seller_id': c.sellerId,
      'live_id': liveId,
      'amount_eur': 1.00,
    },
    anon: c.anon,
    jwt: c.buyerJwt,
  );
  rec(surface: 'TIPS', attack: 'stripe tip 1eur', identity: 'buyer', result: brief(t, 240));

  final huge = await edge(
    c.url,
    'create-live-tip-checkout',
    {
      'seller_id': c.sellerId,
      'live_id': liveId,
      'amount_eur': 999999,
    },
    anon: c.anon,
    jwt: c.buyerJwt,
  );
  rec(surface: 'TIPS', attack: 'amount 999999', identity: 'buyer', result: brief(huge, 200));
}

Future<void> _ocrIngest(Ctx c) async {
  final r = await edge(
    c.url,
    'ingest-ocr-reservation',
    {
      'live_id': '00000000-0000-0000-0000-000000000001',
      'ocr_line_hash': 'rt1752hashxx',
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'requested_qty': 99,
      'ref_slug': 'A1',
    },
    anon: c.anon,
    jwt: c.buyerJwt,
    extra: {'x-device-token': 'stolen-token-rt1752'},
  );
  rec(surface: 'OCR', attack: 'fake device token qty=99', identity: 'buyer', result: brief(r, 240));
}

Future<void> _muxBuyer(Ctx c) async {
  final r = await edge(
    c.url,
    'create-mux-live',
    {'title': '$prefix buyer live'},
    anon: c.anon,
    jwt: c.buyerJwt,
  );
  rec(surface: 'MUX', attack: 'buyer create live', identity: 'buyer', result: brief(r, 280));
  if (looksOk(r) && r.body.contains('stream_key')) {
    finding(
      id: 'RT1752-P1-MUX-BUYER',
      severity: 'P1',
      title: 'Buyer criou directo Mux',
      actor: 'buyer JWT',
      pre: 'conta comprador',
      repro: 'POST create-mux-live',
      impact: 'custo Mux + stream key',
      evidence: 'stream_key in response',
    );
  }
}

Future<void> _livekitForeign(Ctx c) async {
  final lives = await rest(
    c.url,
    'GET',
    'lives?select=id&limit=1',
    headers: c.svcH,
  );
  String? id;
  final j = tryJson(lives);
  if (j is List && j.isNotEmpty) id = j[0]['id']?.toString();
  if (id == null) return;
  final r = await edge(
    c.url,
    'livekit-mux-publish',
    {'step': 'token', 'live_id': id},
    anon: c.anon,
    jwt: c.buyerJwt,
  );
  rec(surface: 'LIVEKIT', attack: 'buyer token for seller live', identity: 'buyer', result: brief(r, 240));
}

Future<void> _disputeInsert(Ctx c) async {
  final o = await _lastBuyerOrder(c);
  for (final t in ['order_disputes', 'disputes']) {
    final r = await rest(
      c.url,
      'POST',
      t,
      headers: c.buyerH,
      body: {
        'order_id': o?['id'],
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'status': 'open',
        'reason': '$prefix',
      },
    );
    rec(surface: t, attack: 'INSERT', identity: 'buyer', result: brief(r, 220));
  }
}

Future<void> _partialRefundFields(Ctx c) async {
  final o = await _lastBuyerOrder(c);
  if (o == null) return;
  final r = await edge(
    c.url,
    'refund-order',
    {'order_id': o['id'], 'amount': 1, 'amount_cents': 1, 'partial': true},
    anon: c.anon,
    jwt: c.buyerJwt,
  );
  rec(surface: 'REFUND', attack: 'buyer refund own + amount body', identity: 'buyer', result: brief(r, 240));
  final s = await edge(
    c.url,
    'refund-order',
    {'order_id': o['id'], 'amount_cents': 999999},
    anon: c.anon,
    jwt: c.sellerJwt,
  );
  rec(surface: 'REFUND', attack: 'seller refund amount_cents body ignored?', identity: 'seller', result: brief(s, 240));
}

Future<void> _refundConcurrent(Ctx c) async {
  final o = await _lastBuyerOrder(c);
  if (o == null) return;
  final futs = <Future<http.Response>>[];
  for (var i = 0; i < 6; i++) {
    futs.add(edge(
      c.url,
      'refund-order',
      {'order_id': o['id']},
      anon: c.anon,
      jwt: c.sellerJwt,
    ));
  }
  final rs = await Future.wait(futs);
  for (final r in rs) {
    rec(surface: 'REFUND', attack: 'parallel seller refund', identity: 'seller', result: brief(r, 180));
  }
}

Future<void> _ensureWalletOther(Ctx c) async {
  final r = await rpcRaw(
    c.url,
    'batata_ensure_wallet',
    {'p_user_id': c.sellerId},
    headers: c.buyerH,
  );
  rec(surface: 'WALLET', attack: 'ensure_wallet(seller)', identity: 'buyer', result: brief(r));
}

Future<void> _anonDefiner(Ctx c) async {
  for (final fn in [
    'batata_create_live_tip_pending',
    'batata_mark_live_item_sold',
    'batata_release_seller_wallet_for_order',
    'batata_finalize_stripe_order_refund',
    'batata_draw_live_raffle_winners',
  ]) {
    final r = await rpcRaw(
      c.url,
      fn,
      {
        'p_live_id': '00000000-0000-0000-0000-000000000001',
        'p_seller_id': c.sellerId,
        'p_amount': 5,
        'p_live_item_id': '00000000-0000-0000-0000-000000000001',
        'p_order_id': '00000000-0000-0000-0000-000000000001',
        'p_raffle_id': '00000000-0000-0000-0000-000000000001',
        'p_refund_id': 're_x',
        'p_payment_intent_id': 'pi_x',
        'p_session_id': 'cs_x',
        'p_amount_cents': 100,
      },
      headers: c.anonH,
    );
    rec(surface: 'RPC', attack: 'anon $fn', identity: 'anon', result: brief(r, 200));
    if (looksOk(r)) {
      finding(
        id: 'RT1752-P0-ANON-DEFINER-$fn',
        severity: 'P0',
        title: 'Anon executou SECURITY DEFINER $fn',
        actor: 'anon',
        pre: 'sem JWT',
        repro: 'POST /rpc/$fn',
        impact: 'função privilegiada sem identidade',
        evidence: brief(r),
      );
    }
  }
}

Future<void> _storageForeign(Ctx c) async {
  for (final b in [
    'chat-attachments',
    'dispute-evidence',
    'product-images',
    'avatars',
    'returns',
  ]) {
    final r = await http.post(
      Uri.parse('${c.url}/storage/v1/object/list/$b'),
      headers: c.buyerH,
      body: '{"limit":10,"prefix":""}',
    );
    rec(surface: 'STORAGE', attack: 'list $b', identity: 'buyer', result: brief(r, 200));
  }
}

Future<void> _messagesForeign(Ctx c) async {
  for (final t in ['messages', 'chat_messages', 'chats']) {
    final r = await rest(
      c.url,
      'GET',
      '$t?select=*&limit=20',
      headers: c.buyerH,
    );
    rec(surface: t, attack: 'SELECT 20', identity: 'buyer', result: brief(r, 220));
    if (looksOk(r) && r.body.contains(c.sellerId) == false) {
      // still check if other buyer ids appear
    }
  }
}
