/// Pass 1 — F1–F8 políticas finas (RLS ∩ trigger ∩ Edge ∩ view). Sem captura.
/// Auditor cego. Não corrige. Staging only. Sem directo is_active persistente.
import 'dart:io';
import '_rtf.dart';

void main() async {
  final env = loadEnv();
  final c = Rtf.fromEnv(env);
  await c.loginActors(env);
  await c.ensureBuyer2();
  await c.ensureSeller2();

  final findings = <Map<String, dynamic>>[];
  final map = <String, dynamic>{
    'auditor': 'REDTEAM_BLIND_F_POLITICAS_FINAS_v1',
    'stamp': stamp,
    'production_touched': false,
    'fase4': false,
    'corrections_applied': false,
  };
  var n = 0;
  String nid(String s) => 'RTF1250-${s.toUpperCase()}-${++n}';
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
  // Fixtures
  // ---------------------------------------------------------------------------
  final pidListed = await c.insertProduct(title: '$prefix listed');
  final pidUnlisted = await c.insertProduct(
    title: '$prefix unlisted-secret',
    listed: false,
    price: 88.8,
  );
  final pidSold = await c.insertProduct(
    title: '$prefix sold',
    sold: true,
    qty: 0,
    listed: false,
  );
  final pidS2 = await c.insertProduct(
    title: '$prefix s2 listed',
    seller: c.seller2Id,
    price: 7.5,
  );
  final qty1 = await c.insertProduct(title: '$prefix qty1', qty: 1, price: 15);

  final sellerProf = await c.rest(
    'GET',
    'profiles?id=eq.${c.sellerId}&select=id,hub_published,handle,is_live',
    service: true,
  );
  final hubWas = sellerProf.map?['hub_published'] == true;
  map['seller_hub_published_was'] = hubWas;
  await c.rest(
    'PATCH',
    'profiles?id=eq.${c.sellerId}',
    service: true,
    body: {'hub_published': true, 'is_live': false},
    prefer: 'return=minimal',
  );

  String? draftLiveId;
  String? endedLiveId;
  String? endedDraftItemId;
  String? endedActiveItemId;
  String? unpublishedEndedLiveId;

  final draftLive = await c.rest('POST', 'lives', service: true, body: {
    'title': '$prefix draft-live',
    'status': 'draft',
    'seller_id': c.sellerId,
    'vendedor_id': c.sellerId,
    'is_active': false,
  });
  draftLiveId = draftLive.firstId;

  final endedLive = await c.rest('POST', 'lives', service: true, body: {
    'title': '$prefix ended-public',
    'status': 'ended',
    'seller_id': c.sellerId,
    'vendedor_id': c.sellerId,
    'is_active': false,
  });
  endedLiveId = endedLive.firstId;

  if (endedLiveId != null) {
    final secretItem = await c.rest('POST', 'live_items', service: true, body: {
      'live_id': endedLiveId,
      'title': '$prefix DRAFT-SECRET-ITEM',
      'price': 199.5,
      'quantity': 3,
      'ref_code': 'RTF-SEC',
      'seller_id': c.sellerId,
      'is_active': false,
      'status': 'draft',
      'product_id': pidUnlisted,
      'checkout_product_id': pidUnlisted,
    });
    endedDraftItemId = secretItem.firstId;
    map['ended_draft_item_insert'] = {
      'http': secretItem.status,
      'id': endedDraftItemId,
      'snip': secretItem.snippet,
    };

    final visItem = await c.rest('POST', 'live_items', service: true, body: {
      'live_id': endedLiveId,
      'title': '$prefix ended-visible-item',
      'price': 12.5,
      'quantity': 1,
      'ref_code': 'RTF-END',
      'seller_id': c.sellerId,
      'is_active': true,
      'status': 'available',
      'product_id': pidUnlisted,
      'checkout_product_id': pidUnlisted,
    });
    endedActiveItemId = visItem.firstId;
  }

  final unpubLive = await c.rest('POST', 'lives', service: true, body: {
    'title': '$prefix ended-unpub',
    'status': 'ended',
    'seller_id': c.seller2Id,
    'vendedor_id': c.seller2Id,
    'is_active': false,
  });
  unpublishedEndedLiveId = unpubLive.firstId;

  map['fixtures'] = {
    'listed': pidListed,
    'unlisted': pidUnlisted,
    'sold': pidSold,
    's2': pidS2,
    'qty1': qty1,
    'draft_live': draftLiveId,
    'ended_live': endedLiveId,
    'ended_draft_item': endedDraftItemId,
    'ended_active_item': endedActiveItemId,
    'unpub_ended': unpublishedEndedLiveId,
    'seller': c.sellerId,
    'buyer': c.buyerId,
    'buyer2': c.buyer2Id,
    'seller2': c.seller2Id,
  };

  // ===========================================================================
  // F2 — View vs base (Hub items sem filtro de status)
  // ===========================================================================
  if (endedDraftItemId != null) {
    final hubItem = await c.rest(
      'GET',
      'hub_live_items_public?id=eq.$endedDraftItemId&select=id,title,price,status,is_active,live_id',
    );
    final discItem = await c.rest(
      'GET',
      'hub_live_items_discovery_public?id=eq.$endedDraftItemId&select=id,title,price,status,is_active',
    );
    await hit('F2-hub-draft-item-on-ended', Future.value(hubItem), identity: 'anon');
    await hit('F2-disc-draft-item-on-ended', Future.value(discItem), identity: 'anon');
    if ((hubItem.ok && hubItem.list.isNotEmpty) ||
        (discItem.ok && discItem.list.isNotEmpty)) {
      add(finding(
        id: nid('f2-hub-draft-item'),
        lens: 'F2',
        severity: 'P2',
        title: 'Hub/discovery expõe live_item draft (título/preço) de live ended pública',
        pre: 'live ended hub_published + item status=draft is_active=false $endedDraftItemId',
        repro: 'GET hub_live_items_public / hub_live_items_discovery_public as anon',
        proven: true,
        evidence: {'hub': hubItem.snippet, 'disc': discItem.snippet},
        note: 'views joinam lives públicas sem filtrar status do item',
      ));
    }
  }

  if (endedLiveId != null) {
    final hubLive = await c.rest(
      'GET',
      'hub_lives_public?id=eq.$endedLiveId&select=id,status,title,is_active,mux_playback_id',
    );
    final discLive = await c.rest(
      'GET',
      'hub_lives_discovery_public?id=eq.$endedLiveId&select=id,status,title,is_active',
    );
    await hit('F2-hub-ended-live', Future.value(hubLive), identity: 'anon');
    await hit('F2-disc-ended-live', Future.value(discLive), identity: 'anon');

    final fomo = await c.rpc('batata_hub_live_fomo_snapshot', {
      'p_live_id': endedLiveId,
    });
    await hit('F2-fomo-ended', Future.value(fomo), identity: 'anon');
    final fomoBody = fomo.body;
    if (fomo.ok &&
        endedDraftItemId != null &&
        fomoBody.contains(endedDraftItemId)) {
      add(finding(
        id: nid('f2-fomo-draft-qty'),
        lens: 'F2',
        severity: 'P2',
        title: 'FOMO SECURITY DEFINER devolve qty de item draft numa live ended pública',
        pre: 'anon RPC batata_hub_live_fomo_snapshot($endedLiveId)',
        repro: 'POST rpc/batata_hub_live_fomo_snapshot',
        proven: true,
        evidence: {'snip': fomo.snippet},
      ));
    }
  }

  if (unpublishedEndedLiveId != null) {
    final hubUnpub = await c.rest(
      'GET',
      'hub_lives_public?id=eq.$unpublishedEndedLiveId&select=id,title,status',
    );
    final discUnpub = await c.rest(
      'GET',
      'hub_lives_discovery_public?id=eq.$unpublishedEndedLiveId&select=id,title,status,seller_name',
    );
    await hit('F2-hub-unpub-ended', Future.value(hubUnpub), identity: 'anon');
    await hit('F2-disc-unpub-ended', Future.value(discUnpub), identity: 'anon');
    if ((hubUnpub.ok && hubUnpub.list.isNotEmpty) ||
        (discUnpub.ok && discUnpub.list.isNotEmpty)) {
      add(finding(
        id: nid('f2-unpub-ended-live'),
        lens: 'F2',
        severity: 'P2',
        title: 'Live ended de seller NÃO hub_published visível no Hub/discovery',
        pre: 'seller2 hub_published=false live ended $unpublishedEndedLiveId',
        repro: 'GET hub_lives_* as anon',
        proven: true,
        evidence: {'hub': hubUnpub.snippet, 'disc': discUnpub.snippet},
      ));
    }
  }

  // Draft + is_active flip (seller JWT) → Hub lives public OR is_active
  if (draftLiveId != null) {
    final flip = await c.rest(
      'PATCH',
      'lives?id=eq.$draftLiveId',
      jwt: c.sellerJwt,
      body: {'is_active': true},
    );
    await hit('F2-seller-flip-draft-active', Future.value(flip), identity: 'seller');
    final hubDraft = await c.rest(
      'GET',
      'hub_lives_public?id=eq.$draftLiveId&select=id,status,is_active,title',
    );
    final discDraft = await c.rest(
      'GET',
      'hub_lives_discovery_public?id=eq.$draftLiveId&select=id,status,is_active,title',
    );
    await hit('F2-hub-draft-after-flip', Future.value(hubDraft), identity: 'anon');
    await hit('F2-disc-draft-after-flip', Future.value(discDraft), identity: 'anon');
    if (hubDraft.ok && hubDraft.list.isNotEmpty) {
      add(finding(
        id: nid('f2-draft-active-hub'),
        lens: 'F2',
        severity: 'P2',
        title: 'Seller JWT is_active=true em live draft → aparece em hub_lives_public',
        pre: 'status=draft + is_active flip $draftLiveId',
        repro: 'PATCH lives is_active; GET hub_lives_public anon',
        proven: true,
        evidence: {'hub': hubDraft.snippet, 'disc': discDraft.snippet, 'patch': flip.snippet},
      ));
    }
    await c.rest(
      'PATCH',
      'lives?id=eq.$draftLiveId',
      service: true,
      body: {'is_active': false, 'status': 'draft'},
      prefer: 'return=minimal',
    );
  }

  // Base vs Hub: reviews / directory / lives stream key (mapa, residual se UUID)
  final reviewsBase = await c.rest(
    'GET',
    'reviews_gerais?select=id,buyer_id,target_id,stars&limit=3',
    jwt: c.buyer2Jwt,
  );
  await hit('F2-reviews-base', Future.value(reviewsBase), identity: 'buyer2');
  final dirLabs = await c.rest(
    'GET',
    'profiles_directory_public?hub_published=eq.false&select=id,handle,full_name&limit=5',
    jwt: c.buyer2Jwt,
  );
  await hit('F2-directory-unpublished', Future.value(dirLabs), identity: 'buyer2');
  if (dirLabs.ok &&
      dirLabs.list.any((e) => e is Map && e['id']?.toString() != c.buyer2Id)) {
    add(finding(
      id: nid('f2-directory-labs'),
      lens: 'F2',
      severity: 'P2',
      title: 'profiles_directory_public ainda lista labs unpublished alheios',
      pre: 'hub_published=false filter',
      repro: 'GET profiles_directory_public?hub_published=eq.false as buyer2',
      proven: true,
      evidence: {'snip': dirLabs.snippet, 'n': dirLabs.list.length},
    ));
  }

  final livesKey = await c.rest(
    'GET',
    'lives?id=eq.$endedLiveId&select=id,mux_stream_key,stream_key,status',
    jwt: c.buyer2Jwt,
  );
  await hit('F2-lives-base-b2', Future.value(livesKey), identity: 'buyer2');
  if (livesKey.ok && livesKey.list.isNotEmpty) {
    final body = livesKey.body;
    final keyLeak = RegExp(r'"(mux_stream_key|stream_key)"\s*:\s*"[^"]+"').hasMatch(body);
    add(finding(
      id: nid('f2-lives-base'),
      lens: 'F2',
      severity: keyLeak ? 'P1' : 'P2',
      title: keyLeak
          ? 'buyer2 lê stream key na tabela lives'
          : 'buyer2 SELECT lives alheia (Hub filtra; base não)',
      pre: 'ended live $endedLiveId',
      repro: 'GET lives?id=eq.<ended> as buyer2',
      proven: true,
      evidence: {'snip': livesKey.snippet},
    ));
  }

  // ===========================================================================
  // F1 — Policy OR: reserva em live ended → shadow SELECT unlist
  // ===========================================================================
  String? resvEndedId;
  if (endedLiveId != null && endedActiveItemId != null) {
    final resv = await c.rest('POST', 'live_reservation_requests', jwt: c.buyerJwt, body: {
      'live_id': endedLiveId,
      'live_item_id': endedActiveItemId,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'requested_qty': 1,
      'status': 'pending',
      'source': 'fleaber_live',
    });
    await hit('F1-resv-ended-live', Future.value(resv), identity: 'buyer');
    resvEndedId = resv.firstId;
    if (resv.ok && resvEndedId != null) {
      add(finding(
        id: nid('f3-resv-ended'),
        lens: 'F3',
        severity: 'P2',
        title: 'INSERT reserva pending em live ENDED (trigger não raise)',
        pre: 'live ended $endedLiveId item $endedActiveItemId',
        repro: 'POST live_reservation_requests source=fleaber_live as buyer',
        proven: true,
        evidence: {'id': resvEndedId, 'snip': resv.snippet},
      ));
    }
    final seenUnlist = await c.rest(
      'GET',
      'products?id=eq.$pidUnlisted&select=id,title,price,quantity,list_on_marketplace,is_sold',
      jwt: c.buyerJwt,
    );
    await hit('F1-unlist-via-resv', Future.value(seenUnlist), identity: 'buyer');
    if (seenUnlist.ok && seenUnlist.list.isNotEmpty) {
      add(finding(
        id: nid('f1-shadow-resv'),
        lens: 'F1',
        severity: 'P2',
        title: 'Policy live_checkout_shadow revela produto unlist via reserva em live ended',
        pre: 'reserva $resvEndedId + product unlist $pidUnlisted',
        repro: 'POST reservation ended live; GET products?id=unlist as buyer',
        proven: true,
        evidence: {'snip': seenUnlist.snippet, 'resv': resvEndedId},
      ));
    }
    final seenB2 = await c.rest(
      'GET',
      'products?id=eq.$pidUnlisted&select=id,title,price',
      jwt: c.buyer2Jwt,
    );
    await hit('F1-unlist-b2-no-resv', Future.value(seenB2), identity: 'buyer2');
  }

  // Buyer INSERT reservation status=accepted (F3 silent rewrite?)
  if (endedLiveId != null && endedDraftItemId != null) {
    final acc = await c.rest('POST', 'live_reservation_requests', jwt: c.buyerJwt, body: {
      'live_id': endedLiveId,
      'live_item_id': endedDraftItemId,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'requested_qty': 1,
      'status': 'accepted',
      'source': 'fleaber_live',
    });
    await hit('F3-resv-self-accept', Future.value(acc), identity: 'buyer');
    final st = acc.map?['status']?.toString();
    if (acc.ok && st == 'accepted') {
      add(finding(
        id: nid('f3-resv-self-accept'),
        lens: 'F3',
        severity: 'P1',
        title: 'Buyer INSERT reservation status=accepted persistiu (consome capacidade)',
        pre: 'item $endedDraftItemId',
        repro: 'POST live_reservation_requests status=accepted as buyer',
        proven: true,
        evidence: {'snip': acc.snippet, 'id': acc.firstId},
      ));
    }
  }

  // E6 1 repro — hold unlist sem live_id
  final e6 = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pidUnlisted,
    'quantity': 1,
    'price_total': 88.8,
    'status': 'aguarda_pagamento',
    'payment_method': 'pagamento na app',
    'shipping_method': 'hand',
  });
  await hit('E6-hold-unlist-1repro', Future.value(e6), identity: 'buyer');

  // Ghost cancelado 1 repro (classe fechada — só mapa)
  final ghost = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pidUnlisted,
    'quantity': 1,
    'price_total': 1,
    'status': 'cancelado',
    'payment_method': 'pagamento na app',
    'shipping_method': 'hand',
  });
  await hit('F3-ghost-cancelado-1repro', Future.value(ghost), identity: 'buyer');
  if (ghost.ok && ghost.firstId != null) {
    final leak = await c.rest(
      'GET',
      'products?id=eq.$pidUnlisted&select=id,title,list_on_marketplace',
      jwt: c.buyer2Jwt,
    );
    await hit('F1-ghost-b2', Future.value(leak), identity: 'buyer2');
  }

  // ===========================================================================
  // F3 — INSERT pago / PATCH wallet_release / bundle unlist
  // ===========================================================================
  final pago = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pidListed,
    'quantity': 1,
    'price_total': 12.5,
    'status': 'pago',
    'payment_method': 'pagamento na app',
    'stripe_payment_intent_id': 'pi_fake_rtf1250',
    'amount_paid_cents': 1250,
    'shipping_method': 'hand',
  });
  await hit('F3-insert-pago', Future.value(pago), identity: 'buyer');
  final pagoId = pago.firstId;
  final pagoSt = pago.map?['status']?.toString();
  final pagoPi = pago.map?['stripe_payment_intent_id']?.toString();
  final pagoAmt = pago.map?['amount_paid_cents'];
  if (pago.ok &&
      (pagoSt == 'pago' ||
          (pagoPi != null && pagoPi.startsWith('pi_fake')) ||
          (pagoAmt is num && pagoAmt > 0))) {
    add(finding(
      id: nid('f3-pago-persist'),
      lens: 'F3',
      severity: 'P0',
      title: 'INSERT JWT persistiu pago / PI fake / amount_paid',
      pre: 'listed $pidListed',
      repro: 'POST orders status=pago PI fake',
      proven: true,
      evidence: {'snip': pago.snippet},
    ));
  }

  if (pagoId != null) {
    final wr = await c.rest('PATCH', 'orders?id=eq.$pagoId', jwt: c.buyerJwt, body: {
      'wallet_release_processed_at': DateTime.now().toUtc().toIso8601String(),
      'auto_feedback_processed_at': DateTime.now().toUtc().toIso8601String(),
    });
    await hit('F3-patch-wallet-release', Future.value(wr), identity: 'buyer');
    final wrRow = await c.rest(
      'GET',
      'orders?id=eq.$pagoId&select=id,status,wallet_release_processed_at,auto_feedback_processed_at,amount_paid_cents,stripe_payment_intent_id',
      service: true,
    );
    await hit('F3-obs-wallet-release', Future.value(wrRow), identity: 'svc');
    if (wrRow.map?['wallet_release_processed_at'] != null) {
      add(finding(
        id: nid('f3-jwt-wallet-flag'),
        lens: 'F3',
        severity: 'P1',
        title: 'JWT gravou wallet_release_processed_at',
        pre: 'order $pagoId',
        repro: 'PATCH orders wallet_release_processed_at as buyer',
        proven: true,
        evidence: {'snip': wrRow.snippet},
      ));
    }
  }

  // Buyer self-accept bundle (E4 1 repro)
  if (pidListed != null && pidUnlisted != null) {
    final bun = await c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_ids': [pidListed, pidUnlisted],
      'status': 'accepted',
      'discount_pct': 50,
      'catalog_subtotal': 1,
    });
    await hit('E4-bundle-self-accept-1repro', Future.value(bun), identity: 'buyer');
    final bunSt = bun.map?['status']?.toString();
    if (bun.ok && bunSt == 'accepted') {
      add(finding(
        id: nid('e4-bundle-accepted'),
        lens: 'F3',
        severity: 'P1',
        title: 'Buyer INSERT bundle status=accepted persistiu',
        pre: 'listed+unlist',
        repro: 'POST product_bundles status=accepted as buyer',
        proven: true,
        evidence: {'snip': bun.snippet},
      ));
    }
    final sub = await c.rpc('batata_product_bundles_catalog_subtotal', {
      'p_product_ids': [pidUnlisted, pidSold],
    }, jwt: c.buyerJwt);
    await hit('F8-catalog-subtotal-dead', Future.value(sub), identity: 'buyer');
    final subVal = sub.json;
    if (sub.ok && subVal is num && subVal > 0) {
      add(finding(
        id: nid('f8-subtotal-dead'),
        lens: 'F8',
        severity: 'P2',
        title: 'catalog_subtotal JWT soma preço de unlist/sold',
        pre: 'ids unlist+sold',
        repro: 'rpc batata_product_bundles_catalog_subtotal',
        proven: true,
        evidence: {'snip': sub.snippet},
      ));
    }
  }

  // ===========================================================================
  // F4 — Edge vs BD
  // ===========================================================================
  if (endedLiveId != null && endedActiveItemId != null && pidUnlisted != null) {
    final piEnded = await c.edge('create-payment-intent', {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pidUnlisted,
      'live_id': endedLiveId,
      'live_item_id': endedActiveItemId,
      'quantity': 1,
      'amount': 1,
      'currency': 'eur',
      'shipping_method': 'hand',
      if (resvEndedId != null) 'reservation_request_id': resvEndedId,
    }, jwt: c.buyerJwt);
    await hit('F4-pi-unlist-ended-live', Future.value(piEnded), identity: 'buyer');
    if (piEnded.ok && piEnded.hasCheckout) {
      add(finding(
        id: nid('f8-pi-unlist-ended'),
        lens: 'F8',
        severity: 'P1',
        title: 'Edge criou Session para unlist via live_item de live ENDED',
        pre: 'unlist $pidUnlisted live ended $endedLiveId item $endedActiveItemId',
        repro: 'POST create-payment-intent live_item ended + unlist',
        proven: true,
        evidence: {'snip': piEnded.snippet},
        note: 'SESSION ≠ captura — encadear pagamento se P1',
      ));
    }
  }

  final piSold = await c.edge('create-payment-intent', {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': pidSold,
    'quantity': 1,
    'amount': 1,
    'currency': 'eur',
    'shipping_method': 'hand',
  }, jwt: c.buyerJwt);
  await hit('E6-pi-sold-1repro', Future.value(piSold), identity: 'buyer');

  final ocrBuyer = await c.edge('ingest-ocr-reservation', {
    'live_id': endedLiveId,
    'ocr_line_hash': 'rtf1250hashxxxx',
    'detected_at': DateTime.now().toUtc().toIso8601String(),
    'ref_slug': 'RTF-END',
    'requested_qty': 1,
    'external_display_name': 'RTF',
  }, jwt: c.buyerJwt);
  await hit('F4-ocr-as-buyer-no-token', Future.value(ocrBuyer), identity: 'buyer');

  final muxBuyer = await c.edge('create-mux-live', {
    'title': '$prefix hostile-mux',
  }, jwt: c.buyer2Jwt);
  await hit('F4-mux-as-buyer2', Future.value(muxBuyer), identity: 'buyer2');

  final sms = await c.edge('send-sms-bulkgate', {
    'to': '+351900000000',
    'text': 'rtf',
  }, jwt: c.buyer2Jwt);
  await hit('F4-sms-buyer2', Future.value(sms), identity: 'buyer2');

  final del = await c.edge('delete-test-account', {
    'user_id': c.sellerId,
  }, jwt: c.buyer2Jwt);
  await hit('F4-delete-account-cross', Future.value(del), identity: 'buyer2');

  if (pagoId != null) {
    final rel = await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': pagoId,
    }, jwt: c.buyerJwt);
    await hit('F4-rpc-release-unpaid', Future.value(rel), identity: 'buyer');
    final relB2 = await c.rpc('batata_release_seller_wallet_for_order', {
      'p_order_id': pagoId,
    }, jwt: c.buyer2Jwt);
    await hit('F4-rpc-release-b2', Future.value(relB2), identity: 'buyer2');
  }

  final acceptResv = resvEndedId == null
      ? null
      : await c.rpc('batata_process_live_reservation_request', {
          'p_request_id': resvEndedId,
          'p_action': 'accept',
        }, jwt: c.buyerJwt);
  if (acceptResv != null) {
    await hit('F4-buyer-accept-own-resv', Future.value(acceptResv), identity: 'buyer');
    if (acceptResv.ok && acceptResv.body.contains('"ok":true')) {
      add(finding(
        id: nid('f7-buyer-accept-resv'),
        lens: 'F7',
        severity: 'P1',
        title: 'Buyer RPC accept da própria reserva (autoridade seller)',
        pre: 'resv $resvEndedId',
        repro: 'rpc batata_process_live_reservation_request accept as buyer',
        proven: true,
        evidence: {'snip': acceptResv.snippet},
      ));
    }
  }

  // ===========================================================================
  // F5 — Pairing TTL / ended live / Edge claim
  // ===========================================================================
  String? pairCode;
  String? deviceToken;
  if (endedLiveId != null) {
    final created = await c.rpc('batata_ps_create_pairing', {
      'p_live_id': endedLiveId,
      'p_device_id_hint': 'rtf1250-pc',
    }, jwt: c.sellerJwt);
    await hit('F5-pair-create-ended', Future.value(created), identity: 'seller');
    pairCode = created.map?['code']?.toString();
    if (created.ok && pairCode != null && pairCode.length == 6) {
      add(finding(
        id: nid('f5-pair-ended'),
        lens: 'F5',
        severity: 'P2',
        title: 'Seller cria código pairing em live ENDED (TTL 120s)',
        pre: 'live ended $endedLiveId',
        repro: 'rpc batata_ps_create_pairing as seller',
        proven: true,
        evidence: {'code_len': pairCode.length, 'snip': created.snippet},
        note: 'encadear Edge claim + OCR',
      ));
      final claim = await c.edge('ps-pairing-claim', {
        'code': pairCode,
        'device_id': 'rtf1250-claim',
        'app_version': 'rtf',
      });
      await hit('F5-edge-claim-ended', Future.value(claim), identity: 'anon');
      deviceToken = claim.map?['device_token']?.toString();
      if (claim.ok && deviceToken != null && deviceToken.isNotEmpty) {
        add(finding(
          id: nid('f5-claim-ended'),
          lens: 'F5',
          severity: 'P2',
          title: 'Edge claim pairing OK em live ENDED — token PS emitido',
          pre: 'code on ended live',
          repro: 'POST functions/v1/ps-pairing-claim anon',
          proven: true,
          evidence: {
            'snip': clip(claim.body, 200),
            'has_token': true,
            'live_id': claim.map?['live_id'],
          },
        ));
        final ingest = await c.edge(
          'ingest-ocr-reservation',
          {
            'live_id': endedLiveId,
            'ocr_line_hash': 'rtf1250ocrhash01',
            'detected_at': DateTime.now().toUtc().toIso8601String(),
            'ref_slug': 'RTF-END',
            'requested_qty': 1,
            'external_display_name': 'OCR-RTF',
            'ocr_raw_line': 'quero RTF-END',
          },
          extra: {'x-device-token': deviceToken},
        );
        await hit('F8-ocr-ended-with-token', Future.value(ingest), identity: 'device');
        if (ingest.ok &&
            (ingest.body.contains('"ok":true') ||
                ingest.body.contains('reservation'))) {
          add(finding(
            id: nid('f8-ocr-ended'),
            lens: 'F8',
            severity: 'P1',
            title: 'OCR ingest criou reserva em live ENDED (pairing+claim+ingest)',
            pre: 'ended live + claimed token',
            repro: 'create pairing ended → Edge claim → ingest-ocr-reservation',
            proven: true,
            evidence: {'snip': ingest.snippet},
          ));
        }
      }
    }

    // Helper cannot? create pairing on ended — F7
    // First need helper accepted. Done in F7 below after invite.
  }

  // Offer TTL 1 repro (classe anterior)
  if (pidListed != null) {
    final off = await c.rest('POST', 'product_offers', jwt: c.buyerJwt, body: {
      'product_id': pidListed,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'amount': 8.0,
      'status': 'pending',
      'expires_at': DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
    });
    await hit('F5-offer-expired-insert', Future.value(off), identity: 'buyer');
    final oid = off.firstId;
    if (oid != null) {
      final acc = await c.rest(
        'PATCH',
        'product_offers?id=eq.$oid',
        jwt: c.sellerJwt,
        body: {'status': 'accepted'},
      );
      await hit('F5-offer-seller-accept-expired', Future.value(acc), identity: 'seller');
      if (acc.ok && acc.map?['status']?.toString() == 'accepted') {
        add(finding(
          id: nid('f5-offer-ttl'),
          lens: 'F5',
          severity: 'P2',
          title: 'Seller aceita product_offer com expires_at no passado',
          pre: 'offer $oid amount 8 expired',
          repro: 'PATCH product_offers status=accepted as seller',
          proven: true,
          evidence: {'snip': acc.snippet},
        ));
      }
    }
  }

  // ===========================================================================
  // F6 — Multi-seller bag residual
  // ===========================================================================
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
    if (bag.ok && bag.hasCheckout) {
      add(finding(
        id: nid('f6-bag-ms'),
        lens: 'F6',
        severity: 'P1',
        title: 'Bag Checkout Session com dois sellers',
        pre: 'orders $o1 + $o2',
        repro: 'create-payment-intent bag_checkout 2 sellers',
        proven: true,
        evidence: {'snip': bag.snippet},
      ));
    }
  }

  // ===========================================================================
  // F7 — Helper permission mínima
  // ===========================================================================
  final inv = await c.rest('POST', 'seller_helpers', jwt: c.sellerJwt, body: {
    'seller_id': c.sellerId,
    'helper_user_id': c.buyer2Id,
    'invited_by': c.sellerId,
    'invitation_status': 'pending',
    'active': false,
    'display_name': 'RTF1250 chat',
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
    final accH = await c.rest(
      'PATCH',
      'seller_helpers?id=eq.$hid',
      jwt: c.buyer2Jwt,
      body: {
        'invitation_status': 'accepted',
        'active': true,
        'permissions': {
          'can_manage_reservations': true,
          'can_manage_payouts': true,
          'can_manage_raffles': true,
        },
      },
    );
    await hit('F7-helper-self-escalate', Future.value(accH), identity: 'buyer2');
    final obsH = await c.rest(
      'GET',
      'seller_helpers?id=eq.$hid&select=id,active,invitation_status,permissions',
      service: true,
    );
    await hit('F7-obs-helper', Future.value(obsH), identity: 'svc');
    final perms = obsH.map?['permissions'];
    var escalated = false;
    if (perms is Map) {
      escalated = perms['can_manage_reservations'] == true ||
          perms['can_manage_payouts'] == true ||
          perms['can_manage_raffles'] == true;
    }
    if (escalated) {
      add(finding(
        id: nid('f7-helper-escalate'),
        lens: 'F7',
        severity: 'P1',
        title: 'Helper PATCH alargou permissions ao aceitar convite',
        pre: 'invite chat-only $hid',
        repro: 'PATCH seller_helpers permissions as helper',
        proven: true,
        evidence: {'snip': obsH.snippet},
      ));
    }

    if (endedLiveId != null) {
      final pairH = await c.rpc('batata_ps_create_pairing', {
        'p_live_id': endedLiveId,
        'p_device_id_hint': 'rtf1250-helper',
      }, jwt: c.buyer2Jwt);
      await hit('F7-helper-pair-ended', Future.value(pairH), identity: 'buyer2');
      if (pairH.ok && pairH.map?['ok'] == true) {
        add(finding(
          id: nid('f7-helper-pair'),
          lens: 'F7',
          severity: 'P2',
          title: 'Helper chat-only criou pairing em live ended',
          pre: 'permissions chat only',
          repro: 'rpc batata_ps_create_pairing as helper',
          proven: true,
          evidence: {'snip': pairH.snippet},
        ));
      }
    }

    if (resvEndedId != null) {
      final hAcc = await c.rpc('batata_process_live_reservation_request', {
        'p_request_id': resvEndedId,
        'p_action': 'accept',
      }, jwt: c.buyer2Jwt);
      await hit('F7-helper-accept-resv', Future.value(hAcc), identity: 'buyer2');
      if (hAcc.ok && hAcc.body.contains('"ok":true')) {
        add(finding(
          id: nid('f7-helper-resv'),
          lens: 'F7',
          severity: 'P1',
          title: 'Helper chat-only accept reserva (can_manage_reservations implícito)',
          pre: 'helper $hid chat-only',
          repro: 'rpc process_live_reservation_request as helper',
          proven: true,
          evidence: {'snip': hAcc.snippet},
        ));
      }
    }

    final raffle = await c.rpc('batata_live_raffle_draw', {
      'p_live_id': endedLiveId,
    }, jwt: c.buyer2Jwt);
    await hit('F7-helper-raffle', Future.value(raffle), identity: 'buyer2');
  }

  // Admin RPC as buyer
  final admin = await c.rpc('batata_admin_list_profiles', {
    'p_limit': 5,
  }, jwt: c.buyer2Jwt);
  await hit('F7-admin-rpc', Future.value(admin), identity: 'buyer2');

  final expire = await c.rpc('expire_product_offers', {}, jwt: c.buyer2Jwt);
  await hit('F7-expire-offers-jwt', Future.value(expire), identity: 'buyer2');

  // Invite oracle (anti-atrophy class — 1 hit, not Pass 1 spend)
  final invEmail = await c.rpc('batata_staff_invite_helper_by_email', {
    'p_email': 'nobody-rtf1250@example.invalid',
    'p_display_name': 'x',
    'p_permissions': {'can_manage_payouts': true},
  }, jwt: c.sellerJwt);
  await hit('F7-invite-ghost-email', Future.value(invEmail), identity: 'seller');

  // Wallets / tokens / disputes
  final wal = await c.rest(
    'GET',
    'wallets?select=id,user_id,balance&limit=5',
    jwt: c.buyer2Jwt,
  );
  await hit('F2-wallets-b2', Future.value(wal), identity: 'buyer2');
  if (wal.ok &&
      wal.list.any((e) => e is Map && e['user_id']?.toString() != c.buyer2Id)) {
    add(finding(
      id: nid('f2-wallet-cross'),
      lens: 'F2',
      severity: 'P0',
      title: 'buyer2 lê wallets de outros UIDs',
      pre: 'GET wallets',
      repro: 'GET wallets as buyer2',
      proven: true,
      evidence: {'snip': wal.snippet},
    ));
  }

  final tok = await c.rest(
    'GET',
    'seller_device_tokens?select=id,seller_id,device_id,token_hash&limit=5',
    jwt: c.buyer2Jwt,
  );
  await hit('F2-device-tokens-b2', Future.value(tok), identity: 'buyer2');
  if (tok.ok && tok.list.isNotEmpty) {
    add(finding(
      id: nid('f2-device-tokens'),
      lens: 'F2',
      severity: 'P1',
      title: 'buyer2 lê seller_device_tokens',
      pre: 'JWT buyer2',
      repro: 'GET seller_device_tokens',
      proven: true,
      evidence: {'snip': tok.snippet},
    ));
  }

  final iban = await c.rest(
    'GET',
    'profiles?id=eq.${c.sellerId}&select=id,iban,mb_way,phone,legal_full_name,shipping_line1',
    jwt: c.buyer2Jwt,
  );
  await hit('F1-pii-seller-as-b2', Future.value(iban), identity: 'buyer2');

  // Race: two buyers pending on qty=1 item
  if (endedLiveId != null && endedActiveItemId != null) {
    final r1 = c.rest('POST', 'live_reservation_requests', jwt: c.buyerJwt, body: {
      'live_id': endedLiveId,
      'live_item_id': endedActiveItemId,
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'requested_qty': 1,
      'status': 'accepted',
      'source': 'fleaber_live',
    });
    final r2 = c.rest('POST', 'live_reservation_requests', jwt: c.buyer2Jwt, body: {
      'live_id': endedLiveId,
      'live_item_id': endedActiveItemId,
      'buyer_id': c.buyer2Id,
      'seller_id': c.sellerId,
      'requested_qty': 1,
      'status': 'accepted',
      'source': 'fleaber_live',
    });
    final rr = await Future.wait([r1, r2]);
    await hit('F8-race-resv-a', Future.value(rr[0]), identity: 'buyer');
    await hit('F8-race-resv-b', Future.value(rr[1]), identity: 'buyer2');
  }

  // Restore seller hub flag / no live
  await c.rest(
    'PATCH',
    'profiles?id=eq.${c.sellerId}',
    service: true,
    body: {'hub_published': hubWas, 'is_live': false},
    prefer: 'return=minimal',
  );
  if (draftLiveId != null) {
    await c.rest(
      'PATCH',
      'lives?id=eq.$draftLiveId',
      service: true,
      body: {'is_active': false, 'status': 'draft'},
      prefer: 'return=minimal',
    );
  }
  if (endedLiveId != null) {
    await c.rest(
      'PATCH',
      'lives?id=eq.$endedLiveId',
      service: true,
      body: {'is_active': false, 'status': 'ended'},
      prefer: 'return=minimal',
    );
  }

  map['findings'] = findings;
  map['finding_count'] = findings.length;
  final out = '${repoRoot()}/tool/redteam_blind_f_20260831T1250/out/pass1.json';
  await dumpJson(out, map);
  stderr.writeln('WROTE $out findings=${findings.length}');
}
