/// REDTEAM_BLIND_E_ORBITA_v1 — PASS 3: E6 qty=0, dual-buyer, session vs cancel.
import 'dart:io';

import '_http.dart';

Future<void> main() async {
  final c = await boot();
  stdout.writeln('E PASS3 boot');

  await _qtyZero(c);
  await _dualBuyerSold(c);
  await _sessionThenCancel(c);
  await _observePass2Leftovers(c);

  await dumpJson(
    'tool/redteam_blind_e_orbita_20260830T1810/out/pass3.json',
    {
      'auditor': 'REDTEAM_BLIND_E_ORBITA_v1',
      'pass': 3,
      'production_touched': false,
      'fase4': false,
      'corrections_applied': false,
      'matrix': matrix,
      'findings': findings,
      'gaps': gaps,
    },
  );
  stdout.writeln(
    'PASS3 done matrix=${matrix.length} findings=${findings.length}',
  );
}

Future<String?> _mkProduct(
  Ctx c,
  String title, {
  required int qty,
  required bool sold,
  required bool listed,
}) async {
  final p = await rest(
    c.url,
    'POST',
    'products',
    headers: c.svcH,
    body: {
      'seller_id': c.sellerId,
      'title': title,
      'price': 7.0,
      'quantity': qty,
      'list_on_marketplace': listed,
      'is_sold': sold,
    },
  );
  rec(
    lens: 'E6',
    surface: 'products',
    attack: 'fixture_$title',
    identity: 'service_role_setup',
    result: brief(p, 140),
  );
  final j = tryJson(p);
  if (j is List && j.isNotEmpty) return j.first['id']?.toString();
  return null;
}

Future<void> _qtyZero(Ctx c) async {
  final pid = await _mkProduct(
    c,
    '$prefix-qty0',
    qty: 0,
    sold: true,
    listed: false,
  );
  if (pid == null) return;
  final ord = await rest(
    c.url,
    'POST',
    'orders',
    headers: c.buyerH,
    body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'price_total': 7.0,
      'status': 'reserva_pendente',
      'quantity': 1,
      'shipping_method': 'Entrega em Mão (€0.00)',
    },
  );
  rec(
    lens: 'E6',
    surface: 'orders',
    attack: 'hold_qty0_sold',
    identity: 'buyer',
    result: brief(ord, 280),
  );
  if (looksOk(ord)) {
    finding(
      id: 'E6-QTY0-STILL-HOLD',
      severity: 'P1',
      title: 'Hold em produto quantity=0 + is_sold + unlisted',
      actor: 'buyer',
      pre: 'stock 0',
      repro: 'POST orders qty=1 on product quantity=0',
      impact: 'Hold sem stock fisico',
      evidence: brief(ord, 400),
    );
    final j = tryJson(ord);
    if (j is List && j.isNotEmpty) {
      await rest(
        c.url,
        'PATCH',
        'orders',
        headers: c.svcH,
        qs: 'id=eq.${j.first['id']}',
        body: {'status': 'cancelado'},
      );
    }
  }
}

Future<void> _dualBuyerSold(Ctx c) async {
  final pid = await _mkProduct(
    c,
    '$prefix-duel',
    qty: 1,
    sold: true,
    listed: false,
  );
  if (pid == null) return;

  Future<dynamic> hold(Map<String, String> h, String bid) {
    return rest(
      c.url,
      'POST',
      'orders',
      headers: h,
      body: {
        'buyer_id': bid,
        'seller_id': c.sellerId,
        'product_id': pid,
        'price_total': 7.0,
        'status': 'reserva_pendente',
        'quantity': 1,
        'shipping_method': 'Entrega em Mão (€0.00)',
      },
    );
  }

  final a = await hold(c.buyerH, c.buyerId);
  final b = await hold(c.buyer2H, c.buyer2Id);
  rec(
    lens: 'E6',
    surface: 'orders',
    attack: 'dual_buyer_qty1_sold',
    identity: 'buyer||buyer2',
    result: 'A=${brief(a, 180)} B=${brief(b, 180)}',
  );
  if (looksOk(a) && looksOk(b)) {
    finding(
      id: 'E6-OVERSELL-SOLD-QTY1',
      severity: 'P1',
      title: 'Dois buyers criam hold permanente em SKU is_sold qty=1',
      actor: 'buyer+buyer2',
      pre: 'quantity=1 is_sold=true unlisted',
      repro: 'POST orders paralelo 2 JWTs',
      impact: 'Oversell em morto: 2 consumos de capacidade 1',
      evidence: {'A': brief(a, 300), 'B': brief(b, 300)},
    );
  }
  for (final r in [a, b]) {
    if (!looksOk(r)) continue;
    final j = tryJson(r);
    if (j is List && j.isNotEmpty) {
      await rest(
        c.url,
        'PATCH',
        'orders',
        headers: c.svcH,
        qs: 'id=eq.${j.first['id']}',
        body: {'status': 'cancelado'},
      );
    }
  }
}

Future<void> _sessionThenCancel(Ctx c) async {
  final pid = await _mkProduct(
    c,
    '$prefix-sess-cancel',
    qty: 2,
    sold: true,
    listed: false,
  );
  if (pid == null) return;
  final ord = await rest(
    c.url,
    'POST',
    'orders',
    headers: c.buyerH,
    body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'price_total': 7.0,
      'status': 'reserva_pendente',
      'quantity': 1,
      'shipping_method': 'Entrega em Mão (€0.00)',
    },
  );
  if (!looksOk(ord)) {
    rec(
      lens: 'E6',
      surface: 'orders',
      attack: 'sess_cancel_order_fail',
      identity: 'buyer',
      result: brief(ord, 200),
    );
    return;
  }
  final oid = (tryJson(ord) as List).first['id'].toString();
  final pay = await edge(
    c.url,
    'create-payment-intent',
    anon: c.anon,
    jwt: c.buyerJwt,
    body: {
      'buyer_id': c.buyerId,
      'order_id': oid,
      'shipping_method': 'Entrega em Mão (€0.00)',
      'currency': 'eur',
    },
  );
  rec(
    lens: 'E6',
    surface: 'create-payment-intent',
    attack: 'session_before_cancel',
    identity: 'buyer',
    result: brief(pay, 350),
  );
  await rest(
    c.url,
    'PATCH',
    'orders',
    headers: c.svcH,
    qs: 'id=eq.$oid',
    body: {'status': 'cancelado'},
  );
  final after = await rest(
    c.url,
    'GET',
    'orders',
    headers: c.svcH,
    qs: 'id=eq.$oid&select=id,status,stripe_checkout_session_id,price_total',
  );
  rec(
    lens: 'E6',
    surface: 'orders',
    attack: 'status_after_cancel_with_open_session',
    identity: 'service_role_observe',
    result: brief(after, 280),
  );

  // Replay GET checkout_return success — sem pagar, so oraculo
  final pj = tryJson(pay);
  String? sid;
  if (pj is Map) sid = pj['checkoutSessionId']?.toString();
  if (sid != null && sid.isNotEmpty) {
    final ret = await edge(
      c.url,
      'create-payment-intent',
      anon: c.anon,
      method: 'GET',
      qs: '?checkout_return=success&session_id=$sid',
    );
    rec(
      lens: 'E7',
      surface: 'create-payment-intent',
      attack: 'return_unpaid_after_cancel',
      identity: 'anon',
      result: '${ret.statusCode} ${brief(ret, 220)} loc=${ret.headers['location'] ?? ''}',
    );
  }
}

Future<void> _observePass2Leftovers(Ctx c) async {
  for (final oid in [
    'a1852f3f-6497-442c-8430-405a71268a88',
    '95385f51-94f5-486b-9417-a0831fb82cde',
    'b8b32b59-0f9d-49c5-9e0e-3bb22806223e',
  ]) {
    final r = await rest(
      c.url,
      'GET',
      'orders',
      headers: c.svcH,
      qs: 'id=eq.$oid&select=id,status,price_total,product_id,bundle_id,stripe_checkout_session_id',
    );
    rec(
      lens: 'E10',
      surface: 'orders',
      attack: 'observe_pass2_$oid',
      identity: 'service_role_observe',
      result: brief(r, 280),
    );
  }
}
