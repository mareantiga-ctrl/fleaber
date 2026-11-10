/// Pass 2 — live_items correctos, OCR em draft, shadow+caixa, mux buyer, cleanup.
/// Não corrige. Staging only. Sem is_active persistente.
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
    'pass': 2,
  };
  var n = 200;
  String nid(String s) => 'RTF1250-${s.toUpperCase()}-${++n}';
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

  const listed = 'd70145a9-203a-4b2d-b05f-6439e8b369d7';
  const unlisted = 'f3f94bbf-07af-4891-9ba8-dc5e38406f5f';
  const sold = '77aa8cab-6cf0-4654-a1f4-d8a38f016ba7';
  const endedLive = '4bf308fe-51e8-45d6-ac21-d539e7a94da6';
  const draftLive = '1332ba7e-91fb-4d4d-ab78-7052649d2363';
  const muxHostile = '72115a99-967e-40d7-8268-e6fd372b56d3';
  const helperId = 'c7c1cec2-bf55-41ea-984f-76a1799b79fa';
  const endedToken =
      'a1d9ea3be2c8c9d9847d6e56a9e31ced401db50816ffdb8105b3c9664ed714e9';

  // Cleanup accidental Mux live from pass1 (buyer2).
  await note(
    'CLEAN-mux-hostile',
    c.rest('PATCH', 'lives?id=eq.$muxHostile', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }),
    idn: 'svc',
  );
  await note(
    'CLEAN-complete-mux',
    c.edge('complete-mux-live', {'live_id': muxHostile}, jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );

  await c.rest(
    'PATCH',
    'profiles?id=eq.${c.buyer2Id}',
    service: true,
    body: {'user_type': 'comprador', 'is_live': false, 'hub_published': false},
    prefer: 'return=minimal',
  );

  await c.rest(
    'PATCH',
    'profiles?id=eq.${c.sellerId}',
    service: true,
    body: {'hub_published': true, 'is_live': false},
    prefer: 'return=minimal',
  );

  // ---------------------------------------------------------------------------
  // Live items: marketplace_product (quantity null) on ended + draft
  // ---------------------------------------------------------------------------
  final pausedEnded = await note(
    'INS-paused-ended',
    c.rest('POST', 'live_items', service: true, body: {
      'live_id': endedLive,
      'title': '$prefix paused-secret',
      'price': 199.5,
      'ref_code': 'RTF-PAU',
      'seller_id': c.sellerId,
      'is_active': false,
      'status': 'paused',
      'item_kind': 'marketplace_product',
      'product_id': unlisted,
      'checkout_product_id': unlisted,
    }),
    idn: 'svc',
  );
  final pausedId = pausedEnded.firstId;

  final availEnded = await note(
    'INS-avail-ended',
    c.rest('POST', 'live_items', service: true, body: {
      'live_id': endedLive,
      'title': '$prefix avail-ended',
      'price': 12.5,
      'ref_code': 'RTF-AVL',
      'seller_id': c.sellerId,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': unlisted,
      'checkout_product_id': unlisted,
    }),
    idn: 'svc',
  );
  final availEndedId = availEnded.firstId;

  final draftItem = await note(
    'INS-draft-live-item',
    c.rest('POST', 'live_items', service: true, body: {
      'live_id': draftLive,
      'title': '$prefix draft-live-item',
      'price': 77.7,
      'ref_code': 'RTF-DFT',
      'seller_id': c.sellerId,
      'is_active': true,
      'status': 'available',
      'item_kind': 'marketplace_product',
      'product_id': unlisted,
      'checkout_product_id': unlisted,
    }),
    idn: 'svc',
  );
  final draftItemId = draftItem.firstId;

  final liveOnly = await note(
    'INS-live-only-ended',
    c.rest('POST', 'live_items', service: true, body: {
      'live_id': endedLive,
      'title': '$prefix live-only-secret',
      'price': 55,
      'quantity': 2,
      'ref_code': 'RTF-LO',
      'seller_id': c.sellerId,
      'is_active': false,
      'status': 'paused',
      'item_kind': 'live_only',
    }),
    idn: 'svc',
  );

  // F2 Hub items
  for (final id in [pausedId, availEndedId, draftItemId, liveOnly.firstId]) {
    if (id == null) continue;
    await note(
      'F2-hub-item-$id',
      c.rest(
        'GET',
        'hub_live_items_public?id=eq.$id&select=id,title,price,status,is_active,live_id',
      ),
      idn: 'anon',
    );
    await note(
      'F2-disc-item-$id',
      c.rest(
        'GET',
        'hub_live_items_discovery_public?id=eq.$id&select=id,title,price,status,is_active',
      ),
      idn: 'anon',
    );
  }

  final hubPaused = map['F2-hub-item-$pausedId'];
  if (pausedId != null && hubPaused is Map && hubPaused['n'] == 1) {
    add(finding(
      id: nid('f2-hub-paused'),
      lens: 'F2',
      severity: 'P2',
      title: 'Hub expõe live_item paused/inactivo de live ended pública',
      pre: 'item $pausedId status=paused is_active=false live ended',
      repro: 'GET hub_live_items_public as anon',
      proven: true,
      evidence: {'snip': hubPaused['snip']},
    ));
  }

  await note(
    'F2-fomo-ended-2',
    c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': endedLive}),
    idn: 'anon',
  );
  await note(
    'F2-fomo-draft',
    c.rpc('batata_hub_live_fomo_snapshot', {'p_live_id': draftLive}),
    idn: 'anon',
  );

  // ---------------------------------------------------------------------------
  // F1 reservation on ended available item → shadow unlist
  // ---------------------------------------------------------------------------
  String? resvId;
  if (availEndedId != null) {
    final resv = await note(
      'F1-resv-ended-avail',
      c.rest('POST', 'live_reservation_requests', jwt: c.buyerJwt, body: {
        'live_id': endedLive,
        'live_item_id': availEndedId,
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'requested_qty': 1,
        'status': 'pending',
        'source': 'fleaber_live',
      }),
      idn: 'buyer',
    );
    resvId = resv.firstId;
    if (resv.ok) {
      add(finding(
        id: nid('f3-resv-ended'),
        lens: 'F3',
        severity: 'P2',
        title: 'Reserva pending em live ENDED (item available)',
        pre: 'live ended $endedLive item $availEndedId',
        repro: 'POST live_reservation_requests as buyer',
        proven: true,
        evidence: {'id': resvId, 'snip': resv.snippet},
      ));
    }
    final seen = await note(
      'F1-unlist-after-resv',
      c.rest(
        'GET',
        'products?id=eq.$unlisted&select=id,title,price,quantity,list_on_marketplace',
        jwt: c.buyerJwt,
      ),
      idn: 'buyer',
    );
    if (seen.ok && seen.list.isNotEmpty) {
      add(finding(
        id: nid('f1-shadow-resv'),
        lens: 'F1',
        severity: 'P2',
        title: 'Shadow RLS revela unlist via reserva em live ended',
        pre: 'resv $resvId unlist $unlisted',
        repro: 'GET products?id=unlist as buyer after reservation',
        proven: true,
        evidence: {'snip': seen.snippet},
      ));
    }
  }

  // Hold unlist + live_id ended / live_item
  await note(
    'F8-hold-unlist-ended-liveid',
    c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': unlisted,
      'live_id': endedLive,
      'live_item_id': availEndedId,
      'quantity': 1,
      'price_total': 12.5,
      'status': 'aguarda_pagamento',
      'payment_method': 'pagamento na app',
      'shipping_method': 'hand',
    }),
    idn: 'buyer',
  );

  await note(
    'F8-hold-unlist-draft-liveid',
    c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': unlisted,
      'live_id': draftLive,
      'live_item_id': draftItemId,
      'quantity': 1,
      'price_total': 77.7,
      'status': 'aguarda_pagamento',
      'payment_method': 'pagamento na app',
      'shipping_method': 'hand',
    }),
    idn: 'buyer',
  );

  // Existing listed hold + PI with order_id (metadata)
  final holdListed = await note(
    'F8-hold-listed',
    c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': listed,
      'quantity': 1,
      'price_total': 12.5,
      'status': 'aguarda_pagamento',
      'payment_method': 'pagamento na app',
      'shipping_method': 'hand',
    }),
    idn: 'buyer',
  );
  final listedOrd = holdListed.firstId;

  // Try PI for unlist by forging order_id of listed but product unlist — Edge should ignore client product
  if (listedOrd != null) {
    await note(
      'F4-pi-listed-ok-control',
      c.edge('create-payment-intent', {
        'buyer_id': c.buyerId,
        'seller_id': c.sellerId,
        'product_id': unlisted,
        'order_id': listedOrd,
        'quantity': 1,
        'amount': 1,
        'currency': 'eur',
        'shipping_method': 'hand',
        'live_id': endedLive,
        'live_item_id': availEndedId,
      }, jwt: c.buyerJwt),
      idn: 'buyer',
    );
  }

  // ---------------------------------------------------------------------------
  // F5/F8 pairing DRAFT live → claim → OCR
  // ---------------------------------------------------------------------------
  final pairDraft = await note(
    'F5-pair-draft',
    c.rpc('batata_ps_create_pairing', {
      'p_live_id': draftLive,
      'p_device_id_hint': 'rtf1250-draft',
    }, jwt: c.sellerJwt),
    idn: 'seller',
  );
  final draftCode = pairDraft.map?['code']?.toString();
  String? draftToken;
  if (draftCode != null && draftCode.length == 6) {
    add(finding(
      id: nid('f5-pair-draft'),
      lens: 'F5',
      severity: 'P2',
      title: 'Seller cria pairing em live DRAFT',
      pre: 'draft live $draftLive',
      repro: 'rpc batata_ps_create_pairing',
      proven: true,
      evidence: {'snip': pairDraft.snippet},
    ));
    final claim = await note(
      'F5-claim-draft',
      c.edge('ps-pairing-claim', {
        'code': draftCode,
        'device_id': 'rtf1250-draft-claim',
      }),
      idn: 'anon',
    );
    draftToken = claim.map?['device_token']?.toString();
    if (claim.ok && draftToken != null && draftToken.isNotEmpty) {
      add(finding(
        id: nid('f5-claim-draft'),
        lens: 'F5',
        severity: 'P2',
        title: 'Edge claim pairing em live DRAFT — token emitido',
        pre: 'draft $draftLive',
        repro: 'POST ps-pairing-claim anon',
        proven: true,
        evidence: {'has_token': true, 'live_id': claim.map?['live_id']},
      ));
      final ingest = await note(
        'F8-ocr-draft',
        c.edge(
          'ingest-ocr-reservation',
          {
            'live_id': draftLive,
            'ocr_line_hash': 'rtf1250drafthash1',
            'detected_at': DateTime.now().toUtc().toIso8601String(),
            'ref_slug': 'RTF-DFT',
            'requested_qty': 1,
            'external_display_name': 'OCR-DRAFT',
            'ocr_raw_line': 'quero RTF-DFT',
          },
          extra: {'x-device-token': draftToken},
        ),
        idn: 'device',
      );
      if (ingest.ok && !ingest.body.contains('live_ended') && ingest.body.contains('"ok":true')) {
        add(finding(
          id: nid('f8-ocr-draft'),
          lens: 'F8',
          severity: 'P1',
          title: 'OCR ingest criou reserva em live DRAFT (pairing∩Edge∩trigger)',
          pre: 'draft live + claimed token',
          repro: 'pairing draft → claim → ingest-ocr',
          proven: true,
          evidence: {'snip': ingest.snippet},
        ));
        final seen2 = await note(
          'F8-unlist-after-ocr-draft',
          c.rest(
            'GET',
            'products?id=eq.$unlisted&select=id,title,price,list_on_marketplace',
            jwt: c.buyerJwt,
          ),
          idn: 'buyer',
        );
        // OCR reservations may be facebook source / no buyer_id — check svc
        final ocrRows = await note(
          'OBS-ocr-resv',
          c.rest(
            'GET',
            'live_reservation_requests?live_id=eq.$draftLive&select=id,status,source,buyer_id,live_item_id,requested_qty&order=created_at.desc&limit=5',
            service: true,
          ),
          idn: 'svc',
        );
        if (ocrRows.ok && ocrRows.list.isNotEmpty) {
          add(finding(
            id: nid('f8-ocr-row'),
            lens: 'F8',
            severity: 'P1',
            title: 'Existe reserva criada por OCR em live draft',
            pre: 'draft $draftLive',
            repro: 'GET live_reservation_requests as svc after ingest',
            proven: true,
            evidence: {'snip': ocrRows.snippet, 'unlist_seen': seen2.list.isNotEmpty},
          ));
        }
      }
    }
  }

  // Heartbeat + panel with ENDED token
  await note(
    'F5-hb-ended-token',
    c.edge(
      'ps-heartbeat',
      {
        'live_id': endedLive,
        'device_id': 'rtf1250-claim',
        'status': 'online',
      },
      extra: {'x-device-token': endedToken},
    ),
    idn: 'device',
  );
  await note(
    'F5-panel-ended-token',
    c.edge(
      'ps-panel-log',
      {'live_id': endedLive, 'event': 'rtf'},
      extra: {'x-device-token': endedToken},
    ),
    idn: 'device',
  );

  // Expire then claim: new pairing, svc expire, claim
  final pair2 = await note(
    'F5-pair-then-expire',
    c.rpc('batata_ps_create_pairing', {
      'p_live_id': endedLive,
      'p_device_id_hint': 'rtf1250-exp',
    }, jwt: c.sellerJwt),
    idn: 'seller',
  );
  final code2 = pair2.map?['code']?.toString();
  if (code2 != null) {
    await c.rest(
      'PATCH',
      'ps_pairing_sessions?code=eq.$code2',
      service: true,
      body: {
        'expires_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      },
      prefer: 'return=minimal',
    );
    final late = await note(
      'F5-claim-expired',
      c.edge('ps-pairing-claim', {
        'code': code2,
        'device_id': 'rtf1250-late',
      }),
      idn: 'anon',
    );
    if (late.ok && late.map?['ok'] == true) {
      add(finding(
        id: nid('f5-claim-expired'),
        lens: 'F5',
        severity: 'P1',
        title: 'Edge claim aceita código com expires_at no passado',
        pre: 'code $code2 expired via svc',
        repro: 'PATCH expires_at past; POST ps-pairing-claim',
        proven: true,
        evidence: {'snip': late.snippet},
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // F4 mux as real buyer + buyer2 now comprador
  // ---------------------------------------------------------------------------
  await note(
    'F4-mux-buyer2-comprador',
    c.edge('create-mux-live', {'title': '$prefix mux-b2'}, jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );
  await note(
    'F4-mux-lab-buyer',
    c.edge('create-mux-live', {'title': '$prefix mux-b'}, jwt: c.buyerJwt),
    idn: 'buyer',
  );
  await note(
    'F4-complete-mux-cross',
    c.edge('complete-mux-live', {'live_id': endedLive}, jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );

  // Wallets / storage / chats / raffle / directory
  await note(
    'F2-wallets-star',
    c.rest('GET', 'wallets?select=id,balance,stripe_account_id&limit=8', jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );
  await note(
    'F2-wallets-seller-as-b2',
    c.rest(
      'GET',
      'wallets?id=eq.${c.sellerId}&select=id,balance,stripe_account_id',
      jwt: c.buyer2Jwt,
    ),
    idn: 'buyer2',
  );
  await note(
    'F2-wt-b2',
    c.rest('GET', 'wallet_transactions?select=id,wallet_id,amount,type&limit=5', jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );
  await note(
    'F2-dir-limit',
    c.rest(
      'GET',
      'profiles_directory_public?select=id,handle,full_name&limit=8',
      jwt: c.buyer2Jwt,
    ),
    idn: 'buyer2',
  );
  await note(
    'F2-orders-other',
    c.rest(
      'GET',
      'orders?select=id,buyer_id,seller_id,status,price_total&limit=8',
      jwt: c.buyer2Jwt,
    ),
    idn: 'buyer2',
  );
  await note(
    'F2-storage-list',
    c.req('GET', '/storage/v1/object/list/chat-media', jwt: c.buyer2Jwt, body: {
      'prefix': '',
      'limit': 5,
    }),
    idn: 'buyer2',
  );
  await note(
    'F7-raffle-assert',
    c.rpc('batata_live_raffle_assert_seller', {'p_live_id': endedLive}, jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );
  await note(
    'F7-expire-offers',
    c.rpc('batata_expire_product_offers', {}, jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );
  await note(
    'F2-helpers-table',
    c.rest(
      'GET',
      'seller_helpers?select=id,seller_id,helper_user_id,permissions,invited_email&limit=8',
      jwt: c.buyer2Jwt,
    ),
    idn: 'buyer2',
  );
  await note(
    'F2-disputes',
    c.rest('GET', 'order_disputes?select=id,order_id,buyer_id,status&limit=5', jwt: c.buyer2Jwt),
    idn: 'buyer2',
  );

  // Favorites unlist + sold
  await note(
    'F8-fav-unlist',
    c.rest('POST', 'favorites', jwt: c.buyerJwt, body: {
      'user_id': c.buyerId,
      'product_id': unlisted,
    }),
    idn: 'buyer',
  );
  await note(
    'F8-fav-sold',
    c.rest('POST', 'favorites', jwt: c.buyerJwt, body: {
      'user_id': c.buyerId,
      'product_id': sold,
    }),
    idn: 'buyer',
  );

  // Helper raffle prize qty (granted authenticated)
  if (availEndedId != null) {
    await note(
      'F7-helper-prize-qty',
      c.rpc('batata_live_raffle_prize_hold_qty', {'p_live_item_id': availEndedId}, jwt: c.buyer2Jwt),
      idn: 'buyer2',
    );
  }

  // Bundle without catalog_subtotal col
  await note(
    'E4-bundle-retry',
    c.rest('POST', 'product_bundles', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_ids': [listed, unlisted],
      'status': 'accepted',
      'discount_pct': 40,
    }),
    idn: 'buyer',
  );

  // Restore hub flag (was true)
  await c.rest(
    'PATCH',
    'profiles?id=eq.${c.sellerId}',
    service: true,
    body: {'is_live': false},
    prefer: 'return=minimal',
  );
  await c.rest(
    'PATCH',
    'lives?id=eq.$draftLive',
    service: true,
    body: {'is_active': false, 'status': 'draft'},
    prefer: 'return=minimal',
  );
  await c.rest(
    'PATCH',
    'lives?id=eq.$endedLive',
    service: true,
    body: {'is_active': false, 'status': 'ended'},
    prefer: 'return=minimal',
  );
  await c.rest(
    'PATCH',
    'lives?id=eq.$muxHostile',
    service: true,
    body: {'is_active': false, 'status': 'ended'},
    prefer: 'return=minimal',
  );

  map['findings'] = findings;
  map['finding_count'] = findings.length;
  final out = '${repoRoot()}/tool/redteam_blind_f_20260831T1250/out/pass2.json';
  await dumpJson(out, map);
  stderr.writeln('WROTE $out findings=${findings.length}');
}
