/// Pass 1 — F1–F7 políticas finas (RLS ∩ trigger ∩ Edge ∩ view). Sem captura ainda.
/// Auditor cego. Não corrige. Staging only. Sem directo is_active=true persistente.
import 'dart:convert';
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
  var n = 0;
  String nid(String s) => 'RTF0735-${s.toUpperCase()}-${++n}';
  void add(Map<String, dynamic> f) => findings.add(f);

  Future<Map<String, dynamic>> hit(
    String label,
    Future<HttpHit> fut, {
    String identity = '',
  }) async {
    final h = await fut;
    final row = {
      'label': label,
      'identity': identity,
      'http': h.status,
      'n': h.list.length,
      'id': h.firstId,
      'snip': h.snippet,
    };
    map[label] = row;
    stderr.writeln('${h.status} $label ${h.snippet}');
    return row;
  }

  // ---------------------------------------------------------------------------
  // MAPA
  // ---------------------------------------------------------------------------
  final openapi = await c.req(
    'GET',
    '/rest/v1/',
    extra: {'Accept': 'application/openapi+json'},
  );
  final paths = <String>[];
  final rpcs = <String>[];
  if (openapi.json is Map) {
    final p = (openapi.json as Map)['paths'];
    if (p is Map) {
      for (final k in p.keys) {
        final s = k.toString();
        paths.add(s);
        if (s.startsWith('/rpc/')) rpcs.add(s.substring(5));
      }
    }
  }
  paths.sort();
  rpcs.sort();
  map['openapi_http'] = openapi.status;
  map['path_count'] = paths.length;
  map['rpc_count'] = rpcs.length;
  map['hub_paths'] = paths.where((p) => p.contains('hub_')).toList();
  map['policyish_rpcs'] = rpcs
      .where((r) =>
          r.contains('staff') ||
          r.contains('helper') ||
          r.contains('permission') ||
          r.contains('expire') ||
          r.contains('wallet') ||
          r.contains('payout') ||
          r.contains('iban') ||
          r.contains('direct_payment'))
      .toList();

  final pidListed = await c.insertProduct(title: '$prefix listed');
  final pidUnlisted = await c.insertProduct(title: '$prefix unlisted', listed: false);
  final pidSold = await c.insertProduct(title: '$prefix sold', sold: true, qty: 0);
  final pidS2 = await c.insertProduct(
    title: '$prefix s2 listed',
    seller: c.seller2Id,
    price: 7.5,
  );
  map['fixtures'] = {
    'listed': pidListed,
    'unlisted': pidUnlisted,
    'sold': pidSold,
    's2': pidS2,
  };

  String? draftLiveId;
  String? draftItemId;
  String? endedLiveId;
  String? endedItemId;
  final draftLive = await c.rest('POST', 'lives', service: true, body: {
    'title': '$prefix draft-live',
    'status': 'draft',
    'seller_id': c.sellerId,
    'vendedor_id': c.sellerId,
    'is_active': false,
  });
  draftLiveId = draftLive.firstId;
  if (draftLiveId != null) {
    final di = await c.rest('POST', 'live_items', service: true, body: {
      'live_id': draftLiveId,
      'title': '$prefix draft-secret-item',
      'price': 99.5,
      'quantity': 3,
      'ref_code': 'RTF-DRAFT',
      'seller_id': c.sellerId,
      'is_active': false,
      'status': 'draft',
      'product_id': pidUnlisted,
      'checkout_product_id': pidUnlisted,
    });
    draftItemId = di.firstId;
    map['draft_item_insert'] = {'http': di.status, 'snip': di.snippet, 'id': draftItemId};
  }
  final endedLive = await c.rest('POST', 'lives', service: true, body: {
    'title': '$prefix ended-live',
    'status': 'ended',
    'seller_id': c.sellerId,
    'vendedor_id': c.sellerId,
    'is_active': false,
  });
  endedLiveId = endedLive.firstId;
  if (endedLiveId != null) {
    final ei = await c.rest('POST', 'live_items', service: true, body: {
      'live_id': endedLiveId,
      'title': '$prefix ended-item',
      'price': 12.5,
      'quantity': 1,
      'ref_code': 'RTF-ENDED',
      'seller_id': c.sellerId,
      'is_active': false,
      'status': 'ended',
      'product_id': pidUnlisted,
      'checkout_product_id': pidUnlisted,
    });
    endedItemId = ei.firstId;
  }
  map['lives'] = {
    'draft': draftLiveId,
    'ended': endedLiveId,
    'draft_item': draftItemId,
    'ended_item': endedItemId,
  };

  // ---------------------------------------------------------------------------
  // F1 — Policy OR shadow
  // ---------------------------------------------------------------------------
  Future<void> selectProduct(String? pid, String who, String? jwt, String tag) async {
    if (pid == null) return;
    final h = await c.rest(
      'GET',
      'products?id=eq.$pid&select=id,title,price,quantity,is_sold,list_on_marketplace,seller_id',
      jwt: jwt,
    );
    await hit('F1-prod-$tag', Future.value(h), identity: who);
    final seen = h.ok && h.list.isNotEmpty;
    if (seen && (tag.contains('unlisted') || tag.contains('sold')) && who != 'seller' && who != 'svc') {
      add(finding(
        id: nid('f1-$tag'),
        lens: 'F1',
        severity: tag.contains('buyer2') ? 'P2' : 'P2',
        title: '$who lê produto $tag via tabela base (policy OR?)',
        pre: 'produto $pid $tag',
        repro: 'GET products?id=eq.$pid as $who',
        proven: true,
        evidence: {'http': h.status, 'snip': h.snippet},
      ));
    }
  }

  await selectProduct(pidListed, 'anon', null, 'listed-anon');
  await selectProduct(pidUnlisted, 'anon', null, 'unlisted-anon');
  await selectProduct(pidSold, 'anon', null, 'sold-anon');
  await selectProduct(pidUnlisted, 'buyer2', c.buyer2Jwt, 'unlisted-buyer2');
  await selectProduct(pidSold, 'buyer2', c.buyer2Jwt, 'sold-buyer2');
  await selectProduct(pidListed, 'buyer2', c.buyer2Jwt, 'listed-buyer2');
  await selectProduct(pidUnlisted, 'seller', c.sellerJwt, 'unlisted-seller');

  // leftover USING(true) on profiles?
  final piiCols =
      'id,full_name,phone,iban,mb_way,legal_full_name,shipping_line1,shipping_city,email,handle,hub_published';
  final profB2 = await c.rest(
    'GET',
    'profiles?id=eq.${c.sellerId}&select=$piiCols',
    jwt: c.buyer2Jwt,
  );
  await hit('F1-profiles-seller-as-b2', Future.value(profB2), identity: 'buyer2');
  if (profB2.ok && profB2.list.isNotEmpty) {
    final row = profB2.map ?? {};
    final leaked = <String>[];
    for (final k in ['phone', 'iban', 'mb_way', 'legal_full_name', 'shipping_line1', 'email']) {
      final v = row[k];
      if (v != null && v.toString().trim().isNotEmpty) leaked.add('$k=$v');
    }
    add(finding(
      id: nid('f1-profiles-or'),
      lens: 'F1',
      severity: leaked.isNotEmpty ? 'P1' : 'P2',
      title: leaked.isNotEmpty
          ? 'buyer2 lê PII de profiles alheio: $leaked'
          : 'buyer2 SELECT linha profiles do seller (own-row policy anulada por OR larga)',
      pre: 'profiles RLS deveria ser id=auth.uid()',
      repro: 'GET profiles?id=eq.<seller> as buyer2',
      proven: true,
      evidence: {'http': profB2.status, 'snip': profB2.snippet, 'leaked': leaked},
    ));
  }

  final livesDraftB2 = await c.rest(
    'GET',
    'lives?id=eq.$draftLiveId&select=id,status,title,mux_stream_key,stream_key,mux_playback_id,seller_id',
    jwt: c.buyer2Jwt,
  );
  await hit('F1-lives-draft-b2', Future.value(livesDraftB2), identity: 'buyer2');
  final livesDraftAnon = await c.rest(
    'GET',
    'lives?id=eq.$draftLiveId&select=id,status,title,mux_stream_key,stream_key',
  );
  await hit('F1-lives-draft-anon', Future.value(livesDraftAnon), identity: 'anon');
  if ((livesDraftB2.ok && livesDraftB2.list.isNotEmpty) ||
      (livesDraftAnon.ok && livesDraftAnon.list.isNotEmpty)) {
    final body = livesDraftB2.list.isNotEmpty ? livesDraftB2.body : livesDraftAnon.body;
    final keyLeak = body.contains('mux_stream_key') &&
        !body.contains('"mux_stream_key":null') &&
        RegExp(r'"mux_stream_key"\s*:\s*"[^"]+"').hasMatch(body);
    add(finding(
      id: nid('f1-lives-draft'),
      lens: 'F1',
      severity: keyLeak ? 'P1' : 'P2',
      title: keyLeak
          ? 'stream key de live draft visível'
          : 'live draft visível na tabela base (Hub esconde)',
      pre: 'live status=draft is_active=false',
      repro: 'GET lives?id=eq.<draft>',
      proven: true,
      evidence: {'b2': livesDraftB2.snippet, 'anon': livesDraftAnon.snippet},
    ));
  }

  // ---------------------------------------------------------------------------
  // F2 — View vs base
  // ---------------------------------------------------------------------------
  if (draftItemId != null) {
    final hubItem = await c.rest('GET', 'hub_live_items_public?id=eq.$draftItemId&select=*');
    final baseItemAnon = await c.rest(
      'GET',
      'live_items?id=eq.$draftItemId&select=id,title,price,quantity,status,live_id,product_id',
    );
    final baseItemB2 = await c.rest(
      'GET',
      'live_items?id=eq.$draftItemId&select=id,title,price,quantity,status,live_id,product_id',
      jwt: c.buyer2Jwt,
    );
    await hit('F2-hub-draft-item', Future.value(hubItem), identity: 'anon');
    await hit('F2-base-draft-item-anon', Future.value(baseItemAnon), identity: 'anon');
    await hit('F2-base-draft-item-b2', Future.value(baseItemB2), identity: 'buyer2');
    final viewClean = !hubItem.ok || hubItem.list.isEmpty;
    final baseLeak = (baseItemAnon.ok && baseItemAnon.list.isNotEmpty) ||
        (baseItemB2.ok && baseItemB2.list.isNotEmpty);
    if (viewClean && baseLeak) {
      add(finding(
        id: nid('f2-draft-items'),
        lens: 'F2',
        severity: 'P2',
        title: 'Hub esconde item de live draft; tabela live_items devolve preço/qty',
        pre: 'live draft + live_item $draftItemId',
        repro: 'GET hub_live_items_public vs GET live_items as anon/buyer2',
        proven: true,
        evidence: {
          'hub': hubItem.snippet,
          'anon': baseItemAnon.snippet,
          'b2': baseItemB2.snippet,
        },
      ));
    }
  }

  if (pidSold != null) {
    final hubSold = await c.rest(
      'GET',
      'hub_products_public?id=eq.$pidSold&select=id,title,is_sold',
    );
    final baseSold = await c.rest(
      'GET',
      'products?id=eq.$pidSold&select=id,title,is_sold,quantity',
      jwt: c.buyer2Jwt,
    );
    await hit('F2-hub-sold', Future.value(hubSold), identity: 'anon');
    await hit('F2-base-sold-b2', Future.value(baseSold), identity: 'buyer2');
  }

  final dirB2 = await c.rest(
    'GET',
    'profiles_directory_public?id=eq.${c.sellerId}&select=id,full_name,handle,location,user_type,hub_published',
    jwt: c.buyer2Jwt,
  );
  await hit('F2-directory-seller', Future.value(dirB2), identity: 'buyer2');
  final hubProf = await c.rest(
    'GET',
    'hub_profiles_public?id=eq.${c.sellerId}&select=id,handle,full_name',
  );
  await hit('F2-hub-profile-seller', Future.value(hubProf), identity: 'anon');

  final notifView = await c.rest('GET', 'notifications_view?select=*&limit=3', jwt: c.buyer2Jwt);
  final notifBase = await c.rest(
    'GET',
    'user_notifications?select=id,user_id,title,body&limit=5',
    jwt: c.buyer2Jwt,
  );
  await hit('F2-notif-view', Future.value(notifView), identity: 'buyer2');
  await hit('F2-notif-base', Future.value(notifBase), identity: 'buyer2');
  if (notifBase.ok && notifBase.list.any((e) {
        if (e is! Map) return false;
        return e['user_id']?.toString() != c.buyer2Id;
      })) {
    add(finding(
      id: nid('f2-notif-cross'),
      lens: 'F2',
      severity: 'P1',
      title: 'buyer2 lê user_notifications de outro UID',
      pre: 'JWT buyer2',
      repro: 'GET user_notifications?limit=5',
      proven: true,
      evidence: {'snip': notifBase.snippet},
    ));
  }

  final reviewsBase = await c.rest(
    'GET',
    'reviews_gerais?select=id,buyer_id,target_id,stars,comment&limit=5',
    jwt: c.buyer2Jwt,
  );
  final reviewsHub = await c.rest('GET', 'hub_reviews_public?select=id,author_display,stars&limit=5');
  await hit('F2-reviews-base', Future.value(reviewsBase), identity: 'buyer2');
  await hit('F2-reviews-hub', Future.value(reviewsHub), identity: 'anon');
  if (reviewsBase.ok && reviewsBase.list.isNotEmpty) {
    final hasOther = reviewsBase.list.any((e) {
      if (e is! Map) return false;
      final bid = e['buyer_id']?.toString();
      return bid != null && bid != c.buyer2Id;
    });
    if (hasOther) {
      add(finding(
        id: nid('f2-reviews-buyer-id'),
        lens: 'F2',
        severity: 'P2',
        title: 'JWT lê reviews_gerais.buyer_id (Hub omite)',
        pre: 'hub_reviews_public sem buyer_id',
        repro: 'GET reviews_gerais as buyer2',
        proven: true,
        evidence: {'snip': reviewsBase.snippet},
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // F3 — Trigger silent vs raise
  // ---------------------------------------------------------------------------
  // INSERT status que NÃO segura stock sobre produto unlisted
  final silentHold = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pidUnlisted,
    'quantity': 1,
    'price_total': 12.5,
    'status': 'cancelado',
    'payment_method': 'pagamento na app',
    'shipping_method': 'hand',
  });
  await hit('F3-insert-cancelado-unlisted', Future.value(silentHold), identity: 'buyer');
  final ghostId = silentHold.firstId;
  if (silentHold.ok && ghostId != null) {
    add(finding(
      id: nid('f3-ghost-order'),
      lens: 'F3',
      severity: 'P2',
      title: 'INSERT order status=cancelado em produto unlisted → 2xx (gate hold saltado)',
      pre: 'unlisted $pidUnlisted',
      repro: 'POST orders status=cancelado product unlisted',
      proven: true,
      evidence: {'http': silentHold.status, 'id': ghostId, 'snip': silentHold.snippet},
      note: 'ainda não é compra; encadear SELECT produto + PATCH hold',
    ));
    final leakViaOrder = await c.rest(
      'GET',
      'products?id=eq.$pidUnlisted&select=id,title,price,quantity,list_on_marketplace',
      jwt: c.buyerJwt,
    );
    await hit('F3-unlisted-via-ghost-order', Future.value(leakViaOrder), identity: 'buyer');
    if (leakViaOrder.ok && leakViaOrder.list.isNotEmpty) {
      add(finding(
        id: nid('f1-or-via-order'),
        lens: 'F1',
        severity: 'P2',
        title: 'Policy products OR exists(orders) revela unlisted após ghost cancelado',
        pre: 'order cancelado $ghostId',
        repro: 'GET products?id=eq.unlisted as buyer',
        proven: true,
        evidence: {'snip': leakViaOrder.snippet},
      ));
    }
    final promote = await c.rest('PATCH', 'orders?id=eq.$ghostId', jwt: c.buyerJwt, body: {
      'status': 'aguarda_pagamento',
    });
    await hit('F3-promote-ghost-hold', Future.value(promote), identity: 'buyer');
    if (promote.ok && promote.list.isNotEmpty) {
      final st = promote.map?['status']?.toString();
      if (st == 'aguarda_pagamento') {
        add(finding(
          id: nid('f3-promote-unlist'),
          lens: 'F3',
          severity: 'P1',
          title: 'Ghost cancelado → PATCH aguarda_pagamento em unlisted (hold efectivo)',
          pre: 'order $ghostId product unlisted',
          repro: 'PATCH status=aguarda_pagamento',
          proven: true,
          evidence: {'snip': promote.snippet},
        ));
      }
    }
  }

  // Bundle: buyer INSERT total_eur hostil — silent rewrite vs raise (E4 1×)
  if (pidListed != null) {
    final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_ids': [pidListed],
      'status': 'accepted',
      'total_eur': 0.01,
      'discount_pct': 90,
    });
    await hit('F3-bundle-insert-hostile', Future.value(bun), identity: 'buyer');
    final bunId = bun.firstId;
    if (bun.ok && bunId != null) {
      final st = bun.map?['status'];
      final tot = bun.map?['total_eur'];
      if (st == 'accepted') {
        add(finding(
          id: nid('e4-self-accept'),
          lens: 'F3',
          severity: 'P2',
          title: 'E4 residual: buyer INSERT bundle já accepted',
          pre: '1 repro máximo anti-atrofia',
          repro: 'POST product_bundles status=accepted',
          proven: true,
          evidence: {'snip': bun.snippet},
        ));
      }
      map['bundle_rewrite'] = {'status': st, 'total': tot};
      final acc = await c.rest('PATCH', 'product_bundles?id=eq.$bunId', jwt: c.buyerJwt, body: {
        'status': 'accepted',
        'total_eur': 0.01,
      });
      await hit('E4-bundle-self-accept-patch', Future.value(acc), identity: 'buyer');
    }
  }

  // Wallet RPC 200 false
  final rel = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': ghostId ?? '00000000-0000-0000-0000-000000000001'},
    jwt: c.buyerJwt,
  );
  await hit('F3-wallet-release-ghost', Future.value(rel), identity: 'buyer');

  // ---------------------------------------------------------------------------
  // F4 — Edge vs BD
  // ---------------------------------------------------------------------------
  if (pidUnlisted != null) {
    final holdUnlist = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pidUnlisted,
      'quantity': 1,
      'price_total': 1,
      'status': 'aguarda_pagamento',
      'payment_method': 'pagamento na app',
      'shipping_method': 'hand',
    });
    await hit('F4-hold-unlisted', Future.value(holdUnlist), identity: 'buyer');
    // E6 one-shot: ended live_id stamp
    if (endedLiveId != null) {
      final holdStamp = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': pidUnlisted,
        'quantity': 1,
        'price_total': 12.5,
        'status': 'aguarda_pagamento',
        'payment_method': 'pagamento na app',
        'shipping_method': 'hand',
        'live_id': endedLiveId,
      });
      await hit('E6-hold-unlist-ended-live', Future.value(holdStamp), identity: 'buyer');
      if (holdStamp.ok && holdStamp.firstId != null) {
        add(finding(
          id: nid('e6-unlist-ended'),
          lens: 'F4',
          severity: 'P1',
          title: 'E6 residual: hold unlisted + live_id ended',
          pre: '1 repro máximo; live ended $endedLiveId',
          repro: 'POST orders live_id=ended unlist',
          proven: true,
          evidence: {'snip': holdStamp.snippet},
        ));
        final ck = await c.edge('create-payment-intent', {
          'buyer_id': c.buyerId,
          'seller_id': c.sellerId,
          'product_id': pidUnlisted,
          'order_id': holdStamp.firstId,
          'quantity': 1,
          'amount': 1,
          'currency': 'eur',
          'shipping_method': 'hand',
        }, jwt: c.buyerJwt);
        await hit('E6-edge-unlist-ended', Future.value(ck), identity: 'buyer');
      }
    }
  }

  // INSERT pago + PI fake (should raise) — not dual-session
  final fakePago = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pidListed,
    'quantity': 1,
    'price_total': 12.5,
    'status': 'pago',
    'payment_method': 'pagamento na app',
    'shipping_method': 'hand',
    'stripe_payment_intent_id': 'pi_rtf_fake',
    'amount_paid_cents': 1250,
  });
  await hit('F4-insert-pago-fake-pi', Future.value(fakePago), identity: 'buyer');
  if (fakePago.ok && fakePago.map?['status'] == 'pago') {
    add(finding(
      id: nid('f4-pago-insert'),
      lens: 'F4',
      severity: 'P0',
      title: 'JWT INSERT order já pago com PI fake',
      pre: 'listed $pidListed',
      repro: 'POST orders status=pago stripe_payment_intent_id=pi_rtf_fake',
      proven: true,
      evidence: {'snip': fakePago.snippet},
    ));
  }

  // Banking oracle: buyer2 pede IBAN do seller sem relação
  final iban = await c.rpc(
    'batata_seller_direct_payment_details',
    {'p_seller_id': c.sellerId},
    jwt: c.buyer2Jwt,
  );
  await hit('F4-iban-oracle-b2', Future.value(iban), identity: 'buyer2');
  if (iban.ok && (iban.body.contains('iban') || iban.body.contains('mb_way')) &&
      iban.body.length > 8 &&
      !iban.body.contains('[]') &&
      iban.list.isNotEmpty) {
    add(finding(
      id: nid('f4-iban'),
      lens: 'F4',
      severity: 'P1',
      title: 'buyer2 sem order lê IBAN/MB WAY do seller',
      pre: 'sem relação off-platform',
      repro: 'rpc batata_seller_direct_payment_details',
      proven: true,
      evidence: {'snip': iban.snippet},
    ));
  }

  // ---------------------------------------------------------------------------
  // F5 — Partial unique / TTL
  // ---------------------------------------------------------------------------
  if (pidListed != null) {
    final offer = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
      'product_id': pidListed,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'amount': 8.0,
      'list_price': 12.5,
      'offered_by': 'buyer',
      'status': 'pending',
    });
    await hit('F5-offer-insert', Future.value(offer), identity: 'buyer');
    final oid = offer.firstId;
    if (oid != null) {
      final exp = await c.rest('PATCH', 'product_offers?id=eq.$oid', service: true, body: {
        'expires_at': DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String(),
      });
      await hit('F5-offer-expire-svc', Future.value(exp), identity: 'svc');
      final acc = await c.rest('PATCH', 'product_offers?id=eq.$oid', jwt: c.sellerJwt, body: {
        'status': 'accepted',
      });
      await hit('F5-offer-accept-expired', Future.value(acc), identity: 'seller');
      if (acc.ok && acc.map?['status'] == 'accepted') {
        add(finding(
          id: nid('f5-offer-ttl'),
          lens: 'F5',
          severity: 'P2',
          title: 'Seller aceita offer com expires_at no passado (cron/TTL não é fronteira)',
          pre: 'offer $oid expires_at -2h, status ainda pending',
          repro: 'PATCH status=accepted as seller',
          proven: true,
          evidence: {'snip': acc.snippet},
        ));
        final holdOffer = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
          'buyer_id': c.buyerId,
          'seller_id': c.sellerId,
          'product_id': pidListed,
          'quantity': 1,
          'price_total': 8.0,
          'status': 'aguarda_pagamento',
          'payment_method': 'pagamento na app',
          'shipping_method': 'hand',
          'product_offer_id': oid,
        });
        await hit('F5-hold-expired-offer', Future.value(holdOffer), identity: 'buyer');
        if (holdOffer.ok && holdOffer.firstId != null) {
          final ck = await c.edge('create-payment-intent', {
            'buyer_id': c.buyerId,
            'seller_id': c.sellerId,
            'product_id': pidListed,
            'order_id': holdOffer.firstId,
            'quantity': 1,
            'amount': 1,
            'currency': 'eur',
            'shipping_method': 'hand',
          }, jwt: c.buyerJwt);
          await hit('F5-edge-expired-offer', Future.value(ck), identity: 'buyer');
          if (ck.ok && ck.body.contains('cs_test')) {
            add(finding(
              id: nid('f5-offer-checkout'),
              lens: 'F5',
              severity: 'P1',
              title: 'Checkout Session TEST após aceitar offer expirada',
              pre: 'offer expired+accepted; order ${holdOffer.firstId}',
              repro: 'POST create-payment-intent',
              proven: true,
              evidence: {'snip': ck.snippet},
              note: 'SESSION ≠ captura; contrato pode ser preço lista',
            ));
          }
        }
      }
    }
  }

  // Pairing: criar código, expirar na BD, claim
  final pairCreate = await c.rpc('batata_create_helper_pairing_code', {
    'p_live_id': endedLiveId,
  }, jwt: c.sellerJwt);
  await hit('F5-pairing-create', Future.value(pairCreate), identity: 'seller');
  String? pairCode;
  if (pairCreate.json is Map) {
    pairCode = (pairCreate.json as Map)['code']?.toString() ??
        (pairCreate.json as Map)['pairing_code']?.toString();
  }
  if (pairCode != null && pairCode.isNotEmpty) {
    await c.rest(
      'PATCH',
      'helper_pairing_sessions?code=eq.$pairCode',
      service: true,
      body: {
        'expires_at': DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String(),
      },
    );
    final claim = await c.rpc('batata_claim_helper_pairing_code', {
      'p_code': pairCode,
    }, jwt: c.buyer2Jwt);
    await hit('F5-pairing-claim-expired', Future.value(claim), identity: 'buyer2');
    if (claim.ok && !claim.body.toLowerCase().contains('expir') && claim.status == 200) {
      final okish = claim.body.contains('true') || claim.body.contains('token') || claim.body.contains('ok');
      if (okish && !claim.body.contains('"ok":false')) {
        add(finding(
          id: nid('f5-pairing-ttl'),
          lens: 'F5',
          severity: 'P1',
          title: 'Claim pairing code após expires_at na BD',
          pre: 'code expirado svc',
          repro: 'rpc claim as buyer2',
          proven: true,
          evidence: {'snip': claim.snippet},
        ));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // F6 — Multi-seller bag
  // ---------------------------------------------------------------------------
  String? o1;
  String? o2;
  if (pidListed != null) {
    final a = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pidListed,
      'quantity': 1,
      'price_total': 12.5,
      'status': 'aguarda_pagamento',
      'payment_method': 'pagamento na app',
      'shipping_method': 'carrier',
    });
    o1 = a.firstId;
    await hit('F6-hold-s1', Future.value(a), identity: 'buyer');
  }
  if (pidS2 != null) {
    final b = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.seller2Id,
      'product_id': pidS2,
      'quantity': 1,
      'price_total': 7.5,
      'status': 'aguarda_pagamento',
      'payment_method': 'pagamento na app',
      'shipping_method': 'carrier',
    });
    o2 = b.firstId;
    await hit('F6-hold-s2', Future.value(b), identity: 'buyer');
  }
  if (o1 != null && o2 != null) {
    final bag = await c.edge('create-payment-intent', {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pidListed,
      'order_id': o1,
      'quantity': 1,
      'amount': 1,
      'currency': 'eur',
      'shipping_method': 'carrier',
      'bag_checkout': true,
      'bag_lines': [
        {'order_id': o1, 'product_id': pidListed, 'seller_id': c.sellerId},
        {'order_id': o2, 'product_id': pidS2, 'seller_id': c.seller2Id},
      ],
    }, jwt: c.buyerJwt);
    await hit('F6-bag-two-sellers', Future.value(bag), identity: 'buyer');
    if (bag.ok && bag.body.contains('cs_test')) {
      add(finding(
        id: nid('f6-bag-ms'),
        lens: 'F6',
        severity: 'P1',
        title: 'Bag Checkout Session com dois sellers',
        pre: 'orders $o1 (s1) + $o2 (s2)',
        repro: 'POST create-payment-intent bag_checkout bag_lines 2 sellers',
        proven: true,
        evidence: {'snip': bag.snippet},
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // F7 — Helper permission mínima
  // ---------------------------------------------------------------------------
  final inv = await c.rest('POST', 'seller_helpers', jwt: c.sellerJwt, body: {
    'seller_id': c.sellerId,
    'helper_user_id': c.buyer2Id,
    'invited_by': c.sellerId,
    'invitation_status': 'pending',
    'active': false,
    'permissions': {
      'can_manage_chat': true,
      'can_manage_reservations': false,
      'can_manage_raffles': false,
      'can_manage_payouts': false,
      'can_manage_helpers': false,
      'can_manage_orders': false,
      'can_view_live_dashboard': false,
      'can_view_analytics': false,
    },
  });
  await hit('F7-helper-invite', Future.value(inv), identity: 'seller');
  final hid = inv.firstId;
  if (hid != null) {
    final esc = await c.rest('PATCH', 'seller_helpers?id=eq.$hid', jwt: c.buyer2Jwt, body: {
      'invitation_status': 'accepted',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
      'active': true,
      'permissions': {
        'can_manage_chat': true,
        'can_manage_reservations': true,
        'can_manage_raffles': true,
        'can_manage_payouts': true,
        'can_manage_helpers': true,
        'can_manage_orders': true,
        'can_view_live_dashboard': true,
        'can_view_analytics': true,
      },
    });
    await hit('F7-helper-accept-escalate', Future.value(esc), identity: 'buyer2');
    final perms = esc.map?['permissions'];
    final payout = perms is Map && perms['can_manage_payouts'] == true;
    if (esc.ok && payout) {
      add(finding(
        id: nid('f7-escalate'),
        lens: 'F7',
        severity: 'P1',
        title: 'Helper ao aceitar convite gravou can_manage_payouts',
        pre: 'invite só can_manage_chat',
        repro: 'PATCH seller_helpers accepted + permissions hostis',
        proven: true,
        evidence: {'snip': esc.snippet},
      ));
    }
    // mesmo se permissions stripped, tenta rifa / pairing / payout RPC
    final raffle = await c.rest('POST', 'live_raffles', jwt: c.buyer2Jwt, body: {
      'live_id': endedLiveId,
      'seller_id': c.sellerId,
      'status': 'active',
    });
    await hit('F7-helper-chat-only-raffle', Future.value(raffle), identity: 'buyer2');
    if (raffle.ok && raffle.firstId != null) {
      add(finding(
        id: nid('f7-chat-implies-raffle'),
        lens: 'F7',
        severity: 'P1',
        title: 'Helper só can_manage_chat criou live_raffles',
        pre: 'permissions chat-only (após accept)',
        repro: 'POST live_raffles as helper',
        proven: true,
        evidence: {'snip': raffle.snippet},
      ));
    }
    final payRpc = await c.rpc('batata_staff_has_permission', {
      'p_seller_id': c.sellerId,
      'p_permission': 'can_manage_payouts',
    }, jwt: c.buyer2Jwt);
    await hit('F7-staff-has-payouts', Future.value(payRpc), identity: 'buyer2');
  }

  // can_view_analytics → logs alheios? (sem helper)
  final logs = await c.rest(
    'GET',
    'staff_action_logs?select=id,seller_id,action&limit=5',
    jwt: c.buyer2Jwt,
  );
  await hit('F7-staff-logs-b2', Future.value(logs), identity: 'buyer2');
  if (logs.ok && logs.list.isNotEmpty) {
    add(finding(
      id: nid('f7-logs'),
      lens: 'F7',
      severity: 'P2',
      title: 'buyer2 lê staff_action_logs',
      pre: 'sem helper / sem analytics',
      repro: 'GET staff_action_logs',
      proven: true,
      evidence: {'snip': logs.snippet},
    ));
  }

  // ---------------------------------------------------------------------------
  // F2 extra: wallets / orders cruzados
  // ---------------------------------------------------------------------------
  final wal = await c.rest(
    'GET',
    'wallets?select=id,user_id,balance&limit=5',
    jwt: c.buyer2Jwt,
  );
  await hit('F2-wallets-b2', Future.value(wal), identity: 'buyer2');
  if (wal.ok && wal.list.any((e) => e is Map && e['user_id']?.toString() != c.buyer2Id)) {
    add(finding(
      id: nid('f2-wallet-cross'),
      lens: 'F2',
      severity: 'P0',
      title: 'buyer2 lê wallets de outros',
      pre: 'JWT buyer2',
      repro: 'GET wallets?limit=5',
      proven: true,
      evidence: {'snip': wal.snippet},
    ));
  }
  final ordX = await c.rest(
    'GET',
    'orders?seller_id=eq.${c.sellerId}&select=id,buyer_id,status,price_total&limit=5',
    jwt: c.buyer2Jwt,
  );
  await hit('F2-orders-seller-as-b2', Future.value(ordX), identity: 'buyer2');
  if (ordX.ok && ordX.list.any((e) => e is Map && e['buyer_id']?.toString() != c.buyer2Id)) {
    add(finding(
      id: nid('f2-orders-cross'),
      lens: 'F2',
      severity: 'P1',
      title: 'buyer2 lê orders de outros buyers do seller',
      pre: 'sem ser party',
      repro: 'GET orders?seller_id=eq.<seller>',
      proven: true,
      evidence: {'snip': ordX.snippet},
    ));
  }

  // stream key column as seller (own) vs buyer
  if (endedLiveId != null) {
    final skB = await c.rest(
      'GET',
      'lives?id=eq.$endedLiveId&select=id,mux_stream_key,stream_key',
      jwt: c.buyerJwt,
    );
    final skS = await c.rest(
      'GET',
      'lives?id=eq.$endedLiveId&select=id,mux_stream_key,stream_key',
      jwt: c.sellerJwt,
    );
    await hit('F2-streamkey-buyer', Future.value(skB), identity: 'buyer');
    await hit('F2-streamkey-seller', Future.value(skS), identity: 'seller');
  }

  // End any accidental active flag
  if (draftLiveId != null) {
    await c.rest('PATCH', 'lives?id=eq.$draftLiveId', service: true, body: {
      'is_active': false,
      'status': 'draft',
    }, prefer: 'return=minimal');
  }
  if (endedLiveId != null) {
    await c.rest('PATCH', 'lives?id=eq.$endedLiveId', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');
  }

  final proven = findings.where((f) => f['proven'] == true).toList();
  final out = {
    'auditor': 'REDTEAM_BLIND_F_POLITICAS_FINAS_v1',
    'stamp': stamp,
    'prefix': prefix,
    'map': map,
    'findings': findings,
    'proven_n': proven.length,
    'by_sev': {
      for (final s in ['P0', 'P1', 'P2', 'P3', 'INFO'])
        s: proven.where((f) => f['severity'] == s).length,
    },
  };
  final dir = Directory.current.path.contains('redteam_blind_f_')
      ? Directory.current.path
      : '${Directory.current.path}/tool/redteam_blind_f_$stamp';
  await dumpJson('$dir/out/pass1.json', out);
  stderr.writeln('PASS1 findings proven=${proven.length} sev=${out['by_sev']}');
}
