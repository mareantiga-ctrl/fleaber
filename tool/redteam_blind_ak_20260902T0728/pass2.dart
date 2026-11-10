import 'dart:io';

import '_rtak.dart';

/// Pass 2 — deepen Hub 401 / FOMO / mux / handle after lives ended.
/// Fixtures: reuse pass1 IDs where still in BD; create ACTIVE then end.
void main() async {
  final c = Rtak.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();

  const endedPub = '7148ec4f-395d-476e-9ba5-bdee9a6738b2';
  const reservedFullItem = '386a1d58-8834-4731-9f8e-c24aeda8c95f';
  const leftoverLive = '894f3fcb-3ede-437b-b01c-7f574b3c05cb';
  const leftoverItem = '576e5f08-93ea-430d-99c7-a01f2805dbf8';
  const activeUnpub = '0a535c48-0b19-4c78-8c11-0ba2e3cb2913';
  const sku = 'e1369e47-7985-43d1-874d-326ae2d6930b';

  final out = <String, Object?>{
    'auditor': 'REDTEAM_BLIND_AK_HUB_EDGE_POS_AEAFAG_v1',
    'pass': 2,
    'stamp': stamp,
  };

  Future<HttpHit> asAnon(String method, String qs, {Object? body}) =>
      c.rest(method, qs, body: body);

  Future<HttpHit> asBuyer(String method, String qs, {Object? body}) =>
      c.rest(method, qs, jwt: c.buyerJwt, body: body);

  // ---- Hub views: anon vs JWT vs service (GRANT batata_live_item_stock) ----
  final views = [
    'hub_live_items_public?live_id=eq.$endedPub&select=id,title,price,status',
    'hub_live_items_discovery_public?id=eq.$leftoverItem&select=id,title,price,status',
    'hub_lives_public?id=eq.$endedPub&select=id,status,is_active,mux_playback_id,mux_vod_playback_id',
    'hub_lives_discovery_public?id=eq.$activeUnpub&select=id,status,is_active,seller_handle,mux_playback_id',
  ];
  final viewMatrix = <String, Object?>{};
  for (final q in views) {
    final a = await asAnon('GET', q);
    final b = await asBuyer('GET', q);
    final s = await c.rest('GET', q, service: true);
    viewMatrix[q.split('?').first] = {
      'anon': a.brief,
      'buyer': b.brief,
      'svc': clip(s.body, 220),
    };
  }
  out['view_matrix'] = viewMatrix;

  final hubItemsAnon = await asAnon(
    'GET',
    'hub_live_items_public?live_id=eq.$endedPub&select=id,title,price,status',
  );
  final hubItemsBuyer = await asBuyer(
    'GET',
    'hub_live_items_public?live_id=eq.$endedPub&select=id,title,price,status',
  );
  c.note('p2.hub_items', 'anon vs buyer hub_live_items_public',
      'anon=${hubItemsAnon.brief} buyer=${hubItemsBuyer.brief}',
      lens: 'AK1');

  if (hubItemsAnon.status == 401 ||
      hubItemsAnon.body.contains('batata_live_item_stock')) {
    c.finding(
      id: 'RTAK-AK1-HUB-ITEMS-GRANT',
      lens: 'AK1',
      severity: 'P2',
      title:
          'Hub web (anon) não consegue ler hub_live_items_public: 42501 batata_live_item_stock',
      actor: 'anon',
      pre: 'view security_barrier chama stock() no WHERE; GRANT execute em falta para anon',
      repro: 'GET /rest/v1/hub_live_items_public',
      expected: '200 [] ou linhas filtradas — não 401 que parte a loja Hub',
      obtained: hubItemsAnon.brief,
      evidence: {'buyer': hubItemsBuyer.brief},
    );
  }

  if (hubItemsBuyer.ok &&
      hubItemsBuyer.list.any((e) =>
          e is Map && e['id']?.toString() == reservedFullItem)) {
    c.finding(
      id: 'RTAK-AK1-RESERVED-FULL-IN-VIEW',
      lens: 'AK1',
      severity: 'P2',
      title:
          'JWT vê reserved_full no Hub (AEAFAG esconde no REST live_items; view não exclui o status)',
      actor: 'buyer JWT',
      pre: 'item status=reserved_full qty=1 available_qty=1',
      repro: 'GET hub_live_items_public JWT',
      expected: 'oculto como REST reserved_full',
      obtained: hubItemsBuyer.snippet,
    );
  }

  // stock RPC
  for (final actor in ['anon', 'buyer']) {
    final h = await c.rpc(
      'batata_live_item_stock',
      {'p_live_item_id': reservedFullItem},
      jwt: actor == 'buyer' ? c.buyerJwt : null,
    );
    c.note('p2.stock_$actor', 'stock rpc $actor', h.brief, lens: 'AK1');
    if (h.ok && h.map != null && h.map!['available_qty'] != null) {
      c.finding(
        id: 'RTAK-AK1-STOCK-RPC-$actor'.toUpperCase(),
        lens: 'AK1',
        severity: actor == 'anon' ? 'P2' : 'P3',
        title: '$actor executa batata_live_item_stock em item de gravado',
        actor: actor,
        pre: 'UUID FOMO',
        repro: 'POST rpc/batata_live_item_stock',
        expected: 'anon sem GRANT; JWT só se item visível no player',
        obtained: h.snippet,
      );
    } else {
      c.hold(
        id: 'RTAK-AK1-STOCK-RPC-$actor'.toUpperCase(),
        lens: 'AK1',
        title: 'stock rpc $actor recusado',
        actor: actor,
        pre: 'uuid',
        repro: 'rpc stock',
        expected: 'denied',
        obtained: h.brief,
      );
    }
  }

  // handle_suggested AFTER lives ended (pass1 ended them)
  final discS2 = await asAnon(
    'GET',
    'hub_profiles_discovery_public?id=eq.${c.seller2Id}&select=id,handle,hub_published,is_live',
  );
  final hubS2 = await asAnon(
    'GET',
    'hub_profiles_public?id=eq.${c.seller2Id}&select=id',
  );
  final livesS2 = await c.rest(
    'GET',
    'lives?seller_id=eq.${c.seller2Id}&select=id,status,is_active&order=created_at.desc&limit=5',
    service: true,
  );
  final resolve = await c.rpc('batata_resolve_handle', {
    'p_handle': 'rtak-s2-suggested',
  });
  c.note('p2.resolve_after_end', 'handle_suggested após endLives',
      'rpc=${resolve.brief} disc=${discS2.brief} hub=${hubS2.brief} lives=${clip(livesS2.body, 200)}',
      lens: 'AK1');
  if (resolve.map?['found'] == true &&
      resolve.map?['hub_published'] != true &&
      discS2.list.isEmpty &&
      hubS2.list.isEmpty) {
    c.finding(
      id: 'RTAK-AK1-HANDLE-SUGGESTED-OFFLINE',
      lens: 'AK1',
      severity: 'P1',
      title:
          'batata_resolve_handle via handle_suggested devolve UUID com vitrine e discovery vazias (sem directo)',
      actor: 'anon',
      pre: 'hub_published=false handle=null handle_suggested set; lives ended',
      repro: 'POST rpc/batata_resolve_handle p_handle=rtak-s2-suggested',
      expected: 'found=false — o que a Hub não mostra não se resolve',
      obtained: resolve.snippet,
      evidence: {
        'discovery': discS2.list.length,
        'hub': hubS2.list.length,
        'lives': clip(livesS2.body, 180),
      },
    );
  } else {
    c.hold(
      id: 'RTAK-AK1-HANDLE-SUGGESTED-OFFLINE',
      lens: 'AK1',
      title: 'resolve suggested alinhado com discovery ou not_found',
      actor: 'anon',
      pre: 'after end',
      repro: 'rpc resolve',
      expected: 'aligned',
      obtained:
          'found=${resolve.map?['found']} disc=${discS2.list.length} hub=${hubS2.list.length}',
    );
  }

  // mux after end (active unpub now ended)
  final muxAfter = await c.edge('resolve-mux-playback', body: {
    'live_id': activeUnpub,
  });
  c.note('p2.mux_after_end', 'resolve-mux após endLives', muxAfter.brief,
      lens: 'AK5');
  if (muxAfter.ok && muxAfter.map?['playback_url'] != null) {
    c.finding(
      id: 'RTAK-AK5-MUX-AFTER-END-UNPUB',
      lens: 'AK5',
      severity: 'P2',
      title: 'resolve-mux ainda devolve playback após ended unpublished',
      actor: 'anon',
      pre: 'live foi ended no pass1',
      repro: 'POST resolve-mux-playback',
      expected: 'live_not_public',
      obtained: muxAfter.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK5-MUX-AFTER-END-UNPUB',
      lens: 'AK5',
      title: 'mux unpublished ended recusado após end',
      actor: 'anon',
      pre: 'ended',
      repro: 'resolve-mux',
      expected: '404',
      obtained: muxAfter.brief,
    );
  }

  // VOD of published ended
  final muxVod = await c.edge('resolve-mux-playback', body: {
    'live_id': endedPub,
  });
  c.note('p2.mux_vod_pub', 'resolve-mux published ended VOD', muxVod.brief,
      lens: 'AK5');

  // ---- ACTIVE published live + cheap item, then end, then checkout ----
  final liveNow = await c.insertLive(
    seller: c.sellerId,
    status: 'live',
    active: true,
    muxPlayback: 'rtak_p2_live_$stamp',
    title: '$prefix p2-active-then-end',
  );
  String? cheapId;
  if (liveNow != null) {
    cheapId = await c.insertLiveItem(
      liveId: liveNow,
      title: '$prefix p2-cheap-5',
      status: 'available',
      active: true,
      qty: 2,
      price: 5,
      productId: sku,
      itemKind: 'marketplace_product',
    );
  }
  c.note('p2.cheap_insert', 'item on ACTIVE live', cheapId ?? 'null',
      lens: 'AK7');

  if (cheapId != null && liveNow != null) {
    final restDuring = await asBuyer(
      'GET',
      'live_items?id=eq.$cheapId&select=id,price,status,quantity,is_active',
    );
    final fomoDuring = await c.rpc('batata_hub_live_fomo_snapshot', {
      'p_live_id': liveNow,
    });
    c.note('p2.during', 'REST+FOMO while live',
        'rest=${restDuring.brief} fomo=${fomoDuring.brief}',
        lens: 'AK1');

    await c.rest('PATCH', 'lives?id=eq.$liveNow', service: true, body: {
      'is_active': false,
      'status': 'ended',
    }, prefer: 'return=minimal');

    final restAfter = await asBuyer(
      'GET',
      'live_items?id=eq.$cheapId&select=id,price,status,quantity,is_active',
    );
    final fomoAfter = await c.rpc('batata_hub_live_fomo_snapshot', {
      'p_live_id': liveNow,
    });
    final hubAfter = await asAnon(
      'GET',
      'hub_live_items_public?id=eq.$cheapId&select=id,price,status',
    );
    c.note('p2.after_end_item', 'item after live ended',
        'rest=${restAfter.brief} fomo=${fomoAfter.brief} hub=${hubAfter.brief}',
        lens: 'AK1');

    if (restAfter.list.isNotEmpty) {
      c.finding(
        id: 'RTAK-AK1-REST-AFTER-END',
        lens: 'AK1',
        severity: 'P2',
        title:
            'Após terminar o directo, REST live_items ainda devolve o artigo (preço 5€)',
        actor: 'buyer JWT',
        pre: 'live ended; item still is_active available',
        repro: 'GET live_items?id=eq.',
        expected: '[] — broadcasting false; só Hub gravado se contrato VOD',
        obtained: restAfter.snippet,
      );
    } else {
      c.hold(
        id: 'RTAK-AK1-REST-AFTER-END',
        lens: 'AK1',
        title: 'REST esconde item após ended',
        actor: 'buyer JWT',
        pre: 'ended',
        repro: 'GET live_items',
        expected: '[]',
        obtained: restAfter.brief,
      );
    }

    final orderIns = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': sku,
      'live_item_id': cheapId,
      'live_id': liveNow,
      'quantity': 1,
      'status': 'pendente',
      'payment_method': 'stripe',
      'shipping_method': 'ctt',
    });
    c.note('p2.order', 'order with ended cheap live_item', orderIns.brief,
        lens: 'AK7');
    final oid = orderIns.firstId;
    if (oid != null) {
      c.createdOrderIds.add(oid);
      final contract = await c.rest(
        'GET',
        'orders?id=eq.$oid&select=id,status,contract_unit_cents,price_total,live_item_id',
        service: true,
      );
      c.note('p2.contract', 'order contract cents', contract.brief, lens: 'AK7');
      final cents = contract.map?['contract_unit_cents'];
      final pi = await c.edge(
        'create-payment-intent',
        jwt: c.buyerJwt,
        extra: {'Origin': 'https://fleaber.pt'},
        body: {
          'order_id': oid,
          'product_id': sku,
          'web_return_origin': 'https://fleaber.pt.evil.com',
        },
      );
      c.note('p2.pi', 'payment-intent ended cheap', pi.brief, lens: 'AK7');
      final cs =
          RegExp(r'cs_test_[A-Za-z0-9]+').firstMatch(pi.body)?.group(0);
      out['p2_session'] = {
        'order': oid,
        'contract_unit_cents': cents,
        'cs': cs,
        'pi': pi.brief,
      };
      final cheapContract = cents == 500 || cents == 5;
      final bodyLow = pi.body.toLowerCase();
      final looksCheap = bodyLow.contains('590') ||
          (pi.map?['amount_total'] is num &&
              (pi.map!['amount_total'] as num) <= 700);
      if (orderIns.ok && (cheapContract || (pi.hasCheckout && looksCheap))) {
        c.finding(
          id: 'RTAK-AK7-ENDED-LIVE-ITEM-PRICE',
          lens: 'AK7',
          severity: 'P0',
          title:
              'live_item de directo já ended sela contract_unit_cents=500 e Session barata (catálogo 40€)',
          actor: 'buyer JWT',
          pre: 'item criado em live activa, live ended, item continua available',
          repro: 'POST orders live_item_id → create-payment-intent',
          expected: 'recusar live_item de ended / cobrar 40€',
          obtained: 'contract=$cents pi=${pi.snippet}',
          evidence: {
            'order': oid,
            'cs': cs,
            'contract_unit_cents': cents,
            'live_id': liveNow,
            'live_item_id': cheapId,
          },
        );
      } else if (!orderIns.ok) {
        c.hold(
          id: 'RTAK-AK7-ENDED-LIVE-ITEM-PRICE',
          lens: 'AK7',
          title: 'INSERT order ended live_item recusado',
          actor: 'buyer JWT',
          pre: 'ended',
          repro: 'POST orders',
          expected: 'denied',
          obtained: orderIns.brief,
        );
      } else {
        c.hold(
          id: 'RTAK-AK7-ENDED-LIVE-ITEM-PRICE',
          lens: 'AK7',
          title: 'order aceite mas preço não parece 5€',
          actor: 'buyer JWT',
          pre: 'ended item',
          repro: 'create-payment-intent',
          expected: '40€ or deny',
          obtained: 'contract=$cents ${pi.brief}',
        );
      }

      if (cs != null) {
        final settle = await c.edge(
          'create-payment-intent',
          method: 'GET',
          qs: '?checkout_return=success&session_id=$cs',
          extra: {'Origin': 'https://evil.com'},
        );
        c.note('p2.settle', 'GET settle unpaid cheap session', settle.brief,
            lens: 'AK3');
        if (settle.body.toLowerCase().contains('pagamento recebido') ||
            settle.status == 303 &&
                (settle.location ?? '').contains('stripe-success')) {
          c.finding(
            id: 'RTAK-AK3-SETTLE-UNPAID-PAID',
            lens: 'AK3',
            severity: 'P0',
            title: 'GET settle unpaid trata como pago',
            actor: 'anon',
            pre: 'cs unpaid',
            repro: 'GET create-payment-intent?checkout_return=success',
            expected: 'não confirmado',
            obtained: settle.brief,
          );
        } else {
          c.hold(
            id: 'RTAK-AK3-SETTLE-UNPAID',
            lens: 'AK3',
            title: 'settle unpaid não captura',
            actor: 'anon',
            pre: 'unpaid cs',
            repro: 'GET settle',
            expected: 'não confirmado',
            obtained: settle.brief,
          );
        }

        // B2 GET same session — leak in HTML?
        final b2 = await c.edge(
          'create-payment-intent',
          method: 'GET',
          jwt: c.buyer2Jwt,
          qs: '?checkout_return=success&session_id=$cs',
        );
        c.note('p2.b2settle', 'B2 settle B1 cs', b2.brief, lens: 'AK3');
        final leak = b2.body.contains(oid) ||
            b2.body.contains(c.buyerId ?? 'no') ||
            (b2.location ?? '').contains('order_id');
        if (leak) {
          c.finding(
            id: 'RTAK-AK3-SETTLE-CROSS-LEAK',
            lens: 'AK3',
            severity: 'P2',
            title: 'GET settle de Session alheia ecoa order_id/buyer no HTML/Location',
            actor: 'buyer2 JWT',
            pre: 'cs de B1',
            repro: 'GET create-payment-intent?session_id=',
            expected: 'página genérica sem ids',
            obtained: b2.brief,
          );
        }
      }
    }
  } else {
    c.note('p2.cheap_fail', 'could not insert cheap on active live', 'skip AK7',
        lens: 'AK7');
  }

  // Storage list with prefixes (M listed tree; pass1 empty at prefix="")
  final prefixes = ['', 'product_photos', 'live_item_photos', 'profile_photos'];
  final st = <String, Object?>{};
  for (final p in prefixes) {
    final h = await c.req(
      'POST',
      '/storage/v1/object/list/chat_media',
      body: {'prefix': p, 'limit': 30},
    );
    st[p.isEmpty ? '(root)' : p] = {
      'status': h.status,
      'n': h.list.length,
      'brief': clip(h.body, 160),
    };
  }
  out['storage_prefixes'] = st;
  final listed = st.values.whereType<Map>().any((m) => (m['n'] as int? ?? 0) > 0);
  if (listed) {
    c.finding(
      id: 'RTAK-AK6-CHAT-MEDIA-LIST',
      lens: 'AK6',
      severity: 'P1',
      title: 'Anon ainda lista prefixos chat_media (controlo M — reabrir?)',
      actor: 'anon',
      pre: 'prefix product_photos etc',
      repro: 'POST object/list/chat_media',
      expected: '[] (fecho pós-M)',
      obtained: st.toString(),
    );
  } else {
    c.hold(
      id: 'RTAK-AK6-CHAT-MEDIA-LIST',
      lens: 'AK6',
      title: 'list chat_media prefixos vazios (M fechado ou mascarado)',
      actor: 'anon',
      pre: 'prefixes',
      repro: 'POST list',
      expected: '[]',
      obtained: st.toString(),
    );
  }

  // Tip on published ended live (seller1) — live_id required
  final tipPub = await c.edge(
    'create-live-tip-checkout',
    jwt: c.buyerJwt,
    extra: {'Origin': 'https://fleaber.pt'},
    body: {
      'seller_id': c.sellerId,
      'live_id': endedPub,
      'amount_eur': 1,
      'web_return_origin': 'https://fleaber.pt',
    },
  );
  c.note('p2.tip_ended_pub', 'tip on published ended live', tipPub.brief,
      lens: 'AK4');
  if (tipPub.hasCheckout) {
    c.finding(
      id: 'RTAK-AK4-TIP-ENDED-PUB',
      lens: 'AK4',
      severity: 'P2',
      title: 'Gorjeta Session em directo already ended (published)',
      actor: 'buyer JWT',
      pre: 'live ended published',
      repro: 'POST create-live-tip-checkout live_id=ended',
      expected: 'recusar live não activa',
      obtained: tipPub.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK4-TIP-ENDED-PUB',
      lens: 'AK4',
      title: 'tip ended published recusado',
      actor: 'buyer JWT',
      pre: 'ended pub',
      repro: 'POST tip checkout',
      expected: '400',
      obtained: tipPub.brief,
    );
  }

  // webhook unsigned
  final wh = await c.edge('stripe-webhook', body: {
    'type': 'checkout.session.completed',
    'data': {
      'object': {'id': 'cs_test_rtak_wh'}
    },
  });
  c.note('p2.webhook', 'stripe-webhook no sig', wh.brief, lens: 'AK4');
  if (wh.status == 200) {
    c.finding(
      id: 'RTAK-AK4-WEBHOOK-NOSIG',
      lens: 'AK4',
      severity: 'P0',
      title: 'stripe-webhook aceita POST sem assinatura',
      actor: 'anon',
      pre: 'sem Stripe-Signature',
      repro: 'POST stripe-webhook',
      expected: '400 missing_signature',
      obtained: wh.snippet,
    );
  } else {
    c.hold(
      id: 'RTAK-AK4-WEBHOOK-NOSIG',
      lens: 'AK4',
      title: 'webhook sem sig recusado',
      actor: 'anon',
      pre: 'no sig',
      repro: 'POST stripe-webhook',
      expected: '400',
      obtained: wh.brief,
    );
  }

  await c.endLives();

  out['findings'] = c.findings;
  out['holds'] = c.holds;
  out['notes'] = c.notes;
  final path = '${repoRoot()}/tool/redteam_blind_ak_$stamp/pass2.json';
  await dumpJson(path, out);
  stdout.writeln(
      'WROTE $path findings=${c.findings.length} holds=${c.holds.length}');
}
