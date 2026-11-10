/// Pass 2 — observar estado final Pass 1 + lentes que falharam por schema + F6/F8.
/// Não corrige. Staging only. Sem directo persistente.
import 'dart:io';
import '_rtf.dart';

void main() async {
  final env = loadEnv();
  final c = Rtf.fromEnv(env);
  await c.loginActors(env);
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final findings = <Map<String, dynamic>>[];
  final map = <String, dynamic>{};
  var n = 100;
  String nid(String s) => 'RTF0735-${s.toUpperCase()}-${++n}';
  void add(Map<String, dynamic> f) => findings.add(f);

  Future<HttpHit> note(String label, Future<HttpHit> fut, {String idn = ''}) async {
    final h = await fut;
    map[label] = {
      'http': h.status,
      'n': h.list.length,
      'id': h.firstId,
      'snip': h.snippet,
      'identity': idn,
    };
    stderr.writeln('${h.status} $label ${h.snippet}');
    return h;
  }

  const listed = 'ef9217c7-5c3a-4a50-92b8-dc535216f629';
  const unlisted = '38a7d055-94bb-4a2d-bb80-5063c2b0ba45';
  const ghost = '66ee144e-8f2a-45bf-8e3e-34349826d293';
  const pagoIns = 'f2a8b690-a5fc-479e-8dd1-60778bc8d33c';
  const offerOrd = 'f9741e1e-9572-4538-938b-f8c87d684749';
  const offerId = '18d08a85-a477-4289-b686-b0fd13b8aabd';
  const draftLive = 'bdd782c8-f2c4-49c4-9579-d197b2d479c9';
  const endedLive = 'a61fd280-edd1-4efa-b203-c79bffeb6b1b';
  const helperId = '98f192ab-1850-4bb6-9ae9-2611ca7bc780';

  // ---------------------------------------------------------------------------
  // Observar INSERT pago fake + contrato offer expirada
  // ---------------------------------------------------------------------------
  final pagoRow = await note(
    'OBS-pago-insert',
    c.rest(
      'GET',
      'orders?id=eq.$pagoIns&select=id,status,stripe_payment_intent_id,stripe_checkout_session_id,amount_paid_cents,contract_unit_cents,price_total,quantity,product_offer_id',
      service: true,
    ),
    idn: 'svc',
  );
  final st = pagoRow.map?['status']?.toString();
  final pi = pagoRow.map?['stripe_payment_intent_id']?.toString();
  final paid = pagoRow.map?['amount_paid_cents'];
  map['pago_parsed'] = {'status': st, 'pi': pi, 'paid': paid};
  if (st == 'pago' || (paid is num && paid > 0) || (pi != null && pi.startsWith('pi_'))) {
    add(finding(
      id: nid('f4-pago-persisted'),
      lens: 'F4',
      severity: 'P0',
      title: 'INSERT JWT persistiu status pago / PI fake / amount_paid',
      pre: 'order $pagoIns',
      repro: 'GET orders as svc após POST JWT status=pago',
      proven: true,
      evidence: {'row': pagoRow.map},
    ));
  }

  final ofRow = await note(
    'OBS-offer-order',
    c.rest(
      'GET',
      'orders?id=eq.$offerOrd&select=id,status,price_total,contract_unit_cents,contract_qty,product_offer_id,stripe_checkout_session_id,amount_paid_cents',
      service: true,
    ),
    idn: 'svc',
  );
  final offerRow = await note(
    'OBS-offer',
    c.rest(
      'GET',
      'product_offers?id=eq.$offerId&select=id,status,amount,expires_at,responded_at',
      service: true,
    ),
    idn: 'svc',
  );
  final unit = ofRow.map?['contract_unit_cents'];
  final boundOffer = ofRow.map?['product_offer_id'];
  map['offer_contract'] = {
    'unit_cents': unit,
    'product_offer_id': boundOffer,
    'price_total': ofRow.map?['price_total'],
    'session': ofRow.map?['stripe_checkout_session_id'],
    'offer_status': offerRow.map?['status'],
    'offer_amount': offerRow.map?['amount'],
    'offer_expires': offerRow.map?['expires_at'],
  };
  // P1 só se contrato selou 800¢ (8€) apesar de expires_at passado
  if (unit == 800 || unit == 8) {
    add(finding(
      id: nid('f5-stale-price-sealed'),
      lens: 'F5',
      severity: 'P1',
      title: 'Contrato selou preço da offer expirada (8€)',
      pre: 'offer $offerId expires_at passado + accepted',
      repro: 'INSERT order + create-payment-intent',
      proven: true,
      evidence: map['offer_contract'] as Map<String, Object?>,
    ));
  }

  final ghostRow = await note(
    'OBS-ghost',
    c.rest(
      'GET',
      'orders?id=eq.$ghost&select=id,status,product_id,amount_paid_cents,contract_unit_cents',
      service: true,
    ),
    idn: 'svc',
  );

  // Edge no ghost cancelado
  final ghostCk = await note(
    'F8-edge-ghost-cancelado',
    c.edge('create-payment-intent', {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': unlisted,
      'order_id': ghost,
      'quantity': 1,
      'amount': 1,
      'currency': 'eur',
      'shipping_method': 'hand',
    }, jwt: c.buyerJwt),
    idn: 'buyer',
  );
  if (ghostCk.ok && ghostCk.body.contains('cs_test')) {
    add(finding(
      id: nid('f8-ghost-session'),
      lens: 'F8',
      severity: 'P1',
      title: 'Edge criou Session para order cancelada de produto unlisted',
      pre: 'ghost $ghost',
      repro: 'POST create-payment-intent',
      proven: true,
      evidence: {'snip': ghostCk.snippet},
    ));
  }

  // Edge no INSERT pago (se ficou hold)
  final pagoCk = await note(
    'F4-edge-pago-insert',
    c.edge('create-payment-intent', {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': listed,
      'order_id': pagoIns,
      'quantity': 1,
      'amount': 1,
      'currency': 'eur',
      'shipping_method': 'hand',
    }, jwt: c.buyerJwt),
    idn: 'buyer',
  );

  // ---------------------------------------------------------------------------
  // F1 profiles (sem coluna email)
  // ---------------------------------------------------------------------------
  final prof = await note(
    'F1-profiles-b2',
    c.rest(
      'GET',
      'profiles?id=eq.${c.sellerId}&select=id,full_name,phone,iban,mb_way,legal_full_name,shipping_line1,shipping_city,handle,hub_published',
      jwt: c.buyer2Jwt,
    ),
    idn: 'buyer2',
  );
  if (prof.ok && prof.list.isNotEmpty) {
    final row = prof.map ?? {};
    final leaked = <String>[];
    for (final k in ['phone', 'iban', 'mb_way', 'legal_full_name', 'shipping_line1']) {
      final v = row[k];
      if (v != null && v.toString().trim().isNotEmpty) leaked.add(k);
    }
    add(finding(
      id: nid('f1-profiles-or'),
      lens: 'F1',
      severity: leaked.isNotEmpty ? 'P1' : 'P2',
      title: leaked.isNotEmpty
          ? 'buyer2 lê PII profiles: $leaked'
          : 'buyer2 SELECT linha profiles do seller (OR larga vs own-row)',
      pre: 'id=seller',
      repro: 'GET profiles?id=eq.seller as buyer2',
      proven: true,
      evidence: {'snip': prof.snippet, 'leaked': leaked},
    ));
  }

  final dir = await note(
    'F2-directory',
    c.rest(
      'GET',
      'profiles_directory_public?id=eq.${c.sellerId}&select=id,full_name,handle,location,user_type',
      jwt: c.buyer2Jwt,
    ),
    idn: 'buyer2',
  );
  final dirOther = await note(
    'F2-directory-limit',
    c.rest(
      'GET',
      'profiles_directory_public?select=id,full_name,handle&limit=8',
      jwt: c.buyer2Jwt,
    ),
    idn: 'buyer2',
  );
  if (dirOther.ok && dirOther.list.length > 1) {
    add(finding(
      id: nid('f2-directory-all'),
      lens: 'F2',
      severity: 'P2',
      title: 'profiles_directory_public lista vários perfis (não só o próprio)',
      pre: 'view grant authenticated',
      repro: 'GET profiles_directory_public?limit=8 as buyer2',
      proven: true,
      evidence: {'n': dirOther.list.length, 'snip': dirOther.snippet},
    ));
  }

  // ---------------------------------------------------------------------------
  // F2 draft live_items (live_only, sem product_id)
  // ---------------------------------------------------------------------------
  final di = await note(
    'FIX-draft-item',
    c.rest('POST', 'live_items', service: true, body: {
      'live_id': draftLive,
      'title': '$prefix draft-secret-only',
      'price': 77.0,
      'quantity': 4,
      'ref_code': 'RTF-D2',
      'seller_id': c.sellerId,
      'is_active': false,
      'status': 'draft',
      'item_kind': 'live_only',
    }),
    idn: 'svc',
  );
  final draftItem = di.firstId;
  if (draftItem != null) {
    final hub = await note(
      'F2-hub-draft-item',
      c.rest('GET', 'hub_live_items_public?id=eq.$draftItem&select=id,title,price'),
      idn: 'anon',
    );
    final baseA = await note(
      'F2-base-draft-anon',
      c.rest(
        'GET',
        'live_items?id=eq.$draftItem&select=id,title,price,quantity,status,live_id',
      ),
      idn: 'anon',
    );
    final baseB = await note(
      'F2-base-draft-b2',
      c.rest(
        'GET',
        'live_items?id=eq.$draftItem&select=id,title,price,quantity,status,live_id',
        jwt: c.buyer2Jwt,
      ),
      idn: 'buyer2',
    );
    final viewClean = !hub.ok || hub.list.isEmpty;
    final baseLeak = (baseA.ok && baseA.list.isNotEmpty) || (baseB.ok && baseB.list.isNotEmpty);
    if (viewClean && baseLeak) {
      add(finding(
        id: nid('f2-draft-items'),
        lens: 'F2',
        severity: 'P2',
        title: 'Hub esconde live_item de draft; tabela base devolve preço/qty',
        pre: 'live draft $draftLive item $draftItem',
        repro: 'GET hub_live_items_public vs live_items',
        proven: true,
        evidence: {
          'hub': hub.snippet,
          'anon': baseA.snippet,
          'b2': baseB.snippet,
        },
      ));
    }
    // F8: reservar item draft
    final rr = await note(
      'F8-reserve-draft-item',
      c.rest('POST', 'live_reservation_requests', jwt: c.buyerJwt, body: {
        'live_item_id': draftItem,
        'buyer_id': c.buyerId,
        'requested_qty': 1,
        'status': 'pending',
        'source': 'fleaber_live',
      }),
      idn: 'buyer',
    );
    if (rr.ok && rr.firstId != null) {
      add(finding(
        id: nid('f8-reserve-draft'),
        lens: 'F8',
        severity: 'P1',
        title: 'Reserva em live_item de directo draft (UI/Hub esconde)',
        pre: 'item $draftItem live draft',
        repro: 'POST live_reservation_requests',
        proven: true,
        evidence: {'snip': rr.snippet},
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // F6 multi-seller bag (produtos frescos qty=3)
  // ---------------------------------------------------------------------------
  final p1 = await c.insertProduct(title: '$prefix bag-s1', qty: 3, price: 11);
  final p2 = await c.insertProduct(
    title: '$prefix bag-s2',
    seller: c.seller2Id,
    qty: 3,
    price: 9,
  );
  final h1 = await note(
    'F6-hold-s1',
    c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': p1,
      'quantity': 1,
      'price_total': 11,
      'status': 'aguarda_pagamento',
      'payment_method': 'pagamento na app',
      'shipping_method': 'carrier',
    }),
    idn: 'buyer',
  );
  final h2 = await note(
    'F6-hold-s2',
    c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.seller2Id,
      'product_id': p2,
      'quantity': 1,
      'price_total': 9,
      'status': 'aguarda_pagamento',
      'payment_method': 'pagamento na app',
      'shipping_method': 'carrier',
    }),
    idn: 'buyer',
  );
  if (h1.firstId != null && h2.firstId != null) {
    final bag = await note(
      'F6-bag-two-sellers',
      c.edge('create-payment-intent', {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': p1,
        'order_id': h1.firstId,
        'quantity': 1,
        'amount': 1,
        'currency': 'eur',
        'shipping_method': 'carrier',
        'bag_checkout': true,
        'bag_lines': [
          {'order_id': h1.firstId, 'product_id': p1, 'seller_id': c.sellerId},
          {'order_id': h2.firstId, 'product_id': p2, 'seller_id': c.seller2Id},
        ],
      }, jwt: c.buyerJwt),
      idn: 'buyer',
    );
    if (bag.ok && bag.body.contains('cs_test')) {
      add(finding(
        id: nid('f6-bag-ms'),
        lens: 'F6',
        severity: 'P1',
        title: 'Bag Session com dois sellers',
        pre: '${h1.firstId} + ${h2.firstId}',
        repro: 'bag_checkout two seller_ids',
        proven: true,
        evidence: {'snip': bag.snippet},
      ));
    }
    // omit line.seller_id (rely on order)
    final bag2 = await note(
      'F6-bag-omit-seller',
      c.edge('create-payment-intent', {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': p1,
        'order_id': h1.firstId,
        'quantity': 1,
        'amount': 1,
        'currency': 'eur',
        'shipping_method': 'carrier',
        'bag_checkout': true,
        'bag_lines': [
          {'order_id': h1.firstId, 'product_id': p1},
          {'order_id': h2.firstId, 'product_id': p2},
        ],
      }, jwt: c.buyerJwt),
      idn: 'buyer',
    );
    if (bag2.ok && bag2.body.contains('cs_test')) {
      add(finding(
        id: nid('f6-bag-omit'),
        lens: 'F6',
        severity: 'P1',
        title: 'Bag Session dois sellers omitindo seller_id nas lines',
        pre: 'orders de s1 e s2',
        repro: 'bag_lines sem seller_id',
        proven: true,
        evidence: {'snip': bag2.snippet},
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // F5 pairing TTL (seller create on ended; expire; claim JWT)
  // ---------------------------------------------------------------------------
  var pair = await note(
    'F5-ps-create-ended',
    c.rpc('batata_ps_create_pairing', {'p_live_id': endedLive}, jwt: c.sellerJwt),
    idn: 'seller',
  );
  if (!pair.ok || pair.body.contains('not_allowed') || pair.body.contains('live_not')) {
    // activar 1s, criar, desactivar — não deixar directo
    await c.rest('PATCH', 'lives?id=eq.$endedLive', service: true, body: {
      'is_active': true,
      'status': 'live',
    }, prefer: 'return=minimal');
    pair = await note(
      'F5-ps-create-live',
      c.rpc('batata_ps_create_pairing', {'p_live_id': endedLive}, jwt: c.sellerJwt),
      idn: 'seller',
    );
    await c.rest('PATCH', 'lives?id=eq.$endedLive', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
  }
  String? code;
  if (pair.json is Map) {
    final m = pair.json as Map;
    code = (m['code'] ?? m['pairing_code'] ?? (m['data'] is Map ? (m['data'] as Map)['code'] : null))
        ?.toString();
  }
  map['pairing_code_present'] = code != null && code.isNotEmpty;
  if (code != null && code.isNotEmpty) {
    await c.req('PATCH', '/rest/v1/rpc/dummy', service: true); // no-op keep types
    // expire via table (name unknown) — try pairing_sessions / helper_pairing_sessions / ps_pairing
    for (final t in [
      'ps_pairing_sessions',
      'helper_pairing_sessions',
      'seller_device_pairing',
      'live_pairing_codes',
    ]) {
      final e = await c.rest('PATCH', '$t?code=eq.$code', service: true, body: {
        'expires_at': DateTime.now().toUtc().subtract(const Duration(minutes: 3)).toIso8601String(),
      });
      map['expire-$t'] = {'http': e.status, 'snip': e.snippet};
    }
    final claim = await note(
      'F5-ps-claim-expired',
      c.rpc('batata_ps_claim_pairing', {
        'p_code': code,
        'p_device_id': 'rtf-b2',
        'p_display_name': 'rtf',
      }, jwt: c.buyer2Jwt),
      idn: 'buyer2',
    );
    if (claim.ok && claim.body.contains('"ok":true')) {
      add(finding(
        id: nid('f5-pair-ttl'),
        lens: 'F5',
        severity: 'P1',
        title: 'Claim pairing após expires_at',
        pre: 'code expirado',
        repro: 'rpc batata_ps_claim_pairing as buyer2',
        proven: true,
        evidence: {'snip': claim.snippet},
      ));
    }
  }
  // F7 helper chat-only create pairing
  final helpPair = await note(
    'F7-helper-create-pairing',
    c.rpc('batata_ps_create_pairing', {'p_live_id': endedLive}, jwt: c.buyer2Jwt),
    idn: 'helper-chat',
  );
  if (helpPair.ok && helpPair.body.contains('"ok":true')) {
    add(finding(
      id: nid('f7-chat-pairing'),
      lens: 'F7',
      severity: 'P1',
      title: 'Helper só can_manage_chat criou pairing code',
      pre: 'helper $helperId chat-only',
      repro: 'rpc batata_ps_create_pairing as buyer2',
      proven: true,
      evidence: {'snip': helpPair.snippet},
    ));
  }

  // ---------------------------------------------------------------------------
  // F2 wallets / logs / messages / chats
  // ---------------------------------------------------------------------------
  await note('F2-wallets-star', c.rest('GET', 'wallets?select=*&limit=3', jwt: c.buyer2Jwt),
      idn: 'buyer2');
  await note(
    'F2-wallet-tx',
    c.rest('GET', 'wallet_transactions?select=id,user_id,amount&limit=5', jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );
  await note('F2-staff-logs', c.rest('GET', 'staff_action_logs?select=*&limit=3', jwt: c.buyer2Jwt),
      idn: 'buyer2');
  final msgs = await note(
    'F2-live-messages',
    c.rest('GET', 'live_messages?select=id,live_id,user_id,body,kind&limit=5', jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );
  if (msgs.ok && msgs.list.any((e) => e is Map && e['user_id']?.toString() != c.buyer2Id)) {
    add(finding(
      id: nid('f2-live-msg-user'),
      lens: 'F2',
      severity: 'P2',
      title: 'JWT lê live_messages.user_id de outros (Hub omite)',
      pre: 'hub_live_messages_public sem user_id',
      repro: 'GET live_messages as buyer2',
      proven: true,
      evidence: {'snip': msgs.snippet},
    ));
  }
  final chats = await note(
    'F2-chats',
    c.rest('GET', 'chats?select=id,buyer_id,seller_id&limit=8', jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );
  if (chats.ok &&
      chats.list.any((e) =>
          e is Map &&
          e['buyer_id']?.toString() != c.buyer2Id &&
          e['seller_id']?.toString() != c.buyer2Id)) {
    add(finding(
      id: nid('f2-chats-cross'),
      lens: 'F2',
      severity: 'P1',
      title: 'buyer2 lê chats onde não é party',
      pre: 'JWT buyer2',
      repro: 'GET chats?limit=8',
      proven: true,
      evidence: {'snip': chats.snippet},
    ));
  }

  // tokens / devices
  for (final t in ['device_tokens', 'user_device_tokens', 'fcm_tokens', 'push_tokens']) {
    final h = await c.rest('GET', '$t?select=*&limit=3', jwt: c.buyer2Jwt);
    map['table-$t'] = {'http': h.status, 'snip': h.snippet};
  }

  // OpenAPI via service
  final oa = await c.req(
    'GET',
    '/rest/v1/',
    service: true,
    extra: {'Accept': 'application/openapi+json'},
  );
  map['openapi_svc'] = oa.status;
  if (oa.json is Map) {
    final p = (oa.json as Map)['paths'];
    if (p is Map) {
      final rpcs = p.keys
          .map((e) => e.toString())
          .where((s) => s.startsWith('/rpc/'))
          .map((s) => s.substring(5))
          .toList()
        ..sort();
      map['rpc_n'] = rpcs.length;
      map['rpc_policy'] = rpcs
          .where((r) =>
              r.contains('pair') ||
              r.contains('wallet') ||
              r.contains('payout') ||
              r.contains('staff') ||
              r.contains('admin') ||
              r.contains('expire') ||
              r.contains('iban') ||
              r.contains('feedback'))
          .toList();
    }
  }

  // garantir lives fechadas
  await c.rest('PATCH', 'lives?id=eq.$endedLive', service: true, body: {
    'is_active': false,
    'status': 'ended',
  }, prefer: 'return=minimal');
  await c.rest('PATCH', 'lives?id=eq.$draftLive', service: true, body: {
    'is_active': false,
    'status': 'draft',
  }, prefer: 'return=minimal');

  final proven = findings.where((f) => f['proven'] == true).toList();
  final out = {
    'auditor': 'REDTEAM_BLIND_F_POLITICAS_FINAS_v1',
    'stamp': stamp,
    'pass': 2,
    'map': map,
    'findings': findings,
    'proven_n': proven.length,
    'ghost': ghostRow.map,
    'dir_http': dir.status,
  };
  final dirPath = Directory.current.path.contains('redteam_blind_f_')
      ? Directory.current.path
      : '${Directory.current.path}/tool/redteam_blind_f_$stamp';
  await dumpJson('$dirPath/out/pass2.json', out);
  stderr.writeln('PASS2 proven=${proven.length}');
}
