/// BH pass3 — BH7 Mux/sabotage · BH8 caixa · reconcile MB WAY pending fantasma
import 'dart:io';
import '_rtbh.dart';

Future<void> main() async {
  final c = Rtbh.fromEnv(loadEnv());
  await c.loginActors();
  await c.ensureBuyer2();
  await c.ensureSeller2();
  final w0 = await c.wallets();
  c.note('wallets0', 'caixa inicial', w0, lens: 'BH8');

  final liveA = await c.insertLive(
    title: '$prefix-p3A',
    muxLiveId: 'fake_mux_$stamp',
    muxPlaybackId: 'fake_pb_$stamp',
    streamKey: 'sk_fake_$stamp',
  );
  final liveDraft = await c.insertLive(
    title: '$prefix-draft',
    status: 'draft',
    active: false,
    muxLiveId: 'fake_mux_draft_$stamp',
    streamKey: 'sk_draft_$stamp',
  );
  if (liveA == null) {
    stderr.writeln('no live');
    await c.dumpAll('pass3.json');
    exit(4);
  }
  final itemA = await c.insertLiveItem(liveId: liveA, qty: 2, title: '$prefix-p3-only');
  final sku = await c.insertProduct(price: 14, qty: 1, live: true, title: '$prefix-p3-sku');
  final itemMkt = sku == null
      ? null
      : await c.insertLiveItem(
          liveId: liveA,
          kind: 'marketplace_product',
          productId: sku,
          title: '$prefix-p3-mkt',
        );

  await _bh7Mux(c, liveA, liveDraft, itemA);
  await _bh8ReconcileCaixa(c, liveA, itemA, itemMkt, sku, w0);

  await c.endAllLives();
  await c.dumpAll('pass3.json');
  stdout.writeln(
      'DONE p3 findings=${c.findings.length} blocked=${c.blocked.length} lenses=${c.lensesHit.toList()..sort()}');
}

Future<void> _bh7Mux(
  Rtbh c,
  String liveA,
  String? liveDraft,
  String? itemA,
) async {
  // Seller2 complete-mux-live cruzado
  if (c.seller2Jwt != null) {
    final complete = await c.edge('complete-mux-live', {'live_id': liveA},
        jwt: c.seller2Jwt);
    await c.expectDenied(
      id: 'BH7-01',
      lens: 'BH7',
      title: 'Seller2 complete-mux-live da live A',
      hit: complete,
      actor: 'seller2 JWT',
      pre: 'live A seller1 com mux_live_id fake',
      repro: 'POST functions/v1/complete-mux-live live_id=A',
      severityIfOpen: 'P1',
      openIf: (h) => h.ok && (h.map?['ok'] == true || h.status == 502),
    );

    for (final step in ['token', 'egress', 'stop_egress']) {
      final pub = await c.edge('livekit-mux-publish', {
        'step': step,
        'live_id': liveA,
        'stream_key': 'stolen',
      }, jwt: c.seller2Jwt);
      final opened = pub.ok &&
          pub.map?['error'] == null &&
          (pub.map?['token'] != null ||
              pub.map?['egress_id'] != null ||
              pub.map?['ok'] == true);
      if (opened) {
        c.hold(
          id: 'BH7-02-$step',
          lens: 'BH7',
          severity: 'P1',
          title: 'Seller2 livekit-mux-publish step=$step live A',
          actor: 'seller2 JWT',
          pre: 'owner cruzado',
          repro: 'POST livekit-mux-publish $step',
          expected: '403 Sem permissão',
          obtained: pub.brief,
        );
      } else {
        c.block('BH7-02-$step', 'BH7', 'seller2 publish $step', pub);
      }
    }
  }

  final buyerComplete = await c.edge('complete-mux-live', {'live_id': liveA},
      jwt: c.buyerJwt);
  await c.expectDenied(
    id: 'BH7-03',
    lens: 'BH7',
    title: 'Buyer complete-mux-live',
    hit: buyerComplete,
    actor: 'buyer JWT',
    pre: 'não é dono',
    repro: 'POST complete-mux-live',
    severityIfOpen: 'P1',
    openIf: (h) => h.ok && (h.map?['ok'] == true || h.status == 502),
  );

  final anonComplete = await c.edge('complete-mux-live', {'live_id': liveA});
  await c.expectDenied(
    id: 'BH7-04',
    lens: 'BH7',
    title: 'Anon complete-mux-live',
    hit: anonComplete,
    actor: 'anon',
    pre: 'sem JWT seller',
    repro: 'POST complete-mux-live anon',
    severityIfOpen: 'P1',
    openIf: (h) => h.ok && h.map?['ok'] == true,
  );

  // REST stream key leak / PATCH cruzado
  final selAnon = await c.rest(
    'GET',
    'lives?id=eq.$liveA&select=id,mux_stream_key,stream_key,mux_live_id,status',
  );
  final keys = selAnon.map;
  final leaked = keys != null &&
      ((keys['mux_stream_key'] != null && '${keys['mux_stream_key']}'.isNotEmpty) ||
          (keys['stream_key'] != null && '${keys['stream_key']}'.isNotEmpty));
  if (leaked) {
    c.hold(
      id: 'BH7-05',
      lens: 'BH7',
      severity: 'P1',
      title: 'Anon REST lê mux_stream_key / stream_key da live A',
      actor: 'anon',
      pre: 'fixture com stream_key',
      repro: 'GET lives?select=mux_stream_key,stream_key',
      expected: 'coluna vazia /  RLS omit',
      obtained: selAnon.brief,
    );
  } else {
    c.block('BH7-05', 'BH7', 'anon stream key não vaza', selAnon);
  }

  if (c.seller2Jwt != null) {
    final patchKey = await c.rest(
      'PATCH',
      'lives?id=eq.$liveA',
      jwt: c.seller2Jwt,
      body: {'mux_stream_key': 'stolen_key', 'is_active': false, 'status': 'ended'},
    );
    await c.expectDenied(
      id: 'BH7-06',
      lens: 'BH7',
      title: 'Seller2 PATCH stream_key / end da live A',
      hit: patchKey,
      actor: 'seller2 JWT',
      pre: 'RLS lives_update_own',
      repro: 'PATCH lives mux_stream_key',
      severityIfOpen: 'P1',
    );
  }

  // resolve-mux-playback draft / ended
  if (liveDraft != null) {
    final pbDraft = await c.edge('resolve-mux-playback', {'live_id': liveDraft});
    if (pbDraft.ok &&
        (pbDraft.map?['playback_id'] != null ||
            pbDraft.map?['vod_playback_id'] != null)) {
      c.hold(
        id: 'BH7-07',
        lens: 'BH7',
        severity: 'P2',
        title: 'resolve-mux-playback devolve playback em draft',
        actor: 'anon',
        pre: 'live draft is_active=false',
        repro: 'POST resolve-mux-playback live_id=draft',
        expected: 'live_not_public 404',
        obtained: pbDraft.brief,
      );
    } else {
      c.block('BH7-07', 'BH7', 'playback draft gated', pbDraft);
    }
  }

  final hub = await c.rest(
    'GET',
    'hub_lives_public?id=eq.$liveA&select=id,status,mux_playback_id,mux_vod_playback_id',
  );
  c.note('BH7-08', 'hub_lives_public live A', hub, lens: 'BH7');
  final vodWhileLive = hub.map?['mux_vod_playback_id'];
  if (vodWhileLive != null && '$vodWhileLive'.isNotEmpty) {
    c.hold(
      id: 'BH7-08',
      lens: 'BH7',
      severity: 'P3',
      title: 'Hub expõe VOD enquanto status=live',
      actor: 'anon',
      pre: 'live broadcasting',
      repro: 'GET hub_lives_public',
      expected: 'mux_vod_playback_id null se não ended',
      obtained: hub.brief,
    );
  } else {
    c.block('BH7-08', 'BH7', 'VOD não vaza em live', hub);
  }

  // create-mux-live buyer
  final createBuyer = await c.edge('create-mux-live', {'title': 'BH hijack stream'},
      jwt: c.buyerJwt);
  await c.expectDenied(
    id: 'BH7-09',
    lens: 'BH7',
    title: 'Buyer cria stream Mux',
    hit: createBuyer,
    actor: 'buyer JWT',
    pre: 'user_type comprador',
    repro: 'POST create-mux-live',
    severityIfOpen: 'P2',
    openIf: (h) => h.ok && h.map?['stream_key'] != null,
  );
}

Future<void> _bh8ReconcileCaixa(
  Rtbh c,
  String liveA,
  String? itemA,
  String? itemMkt,
  String? sku,
  Map<String, num?> w0,
) async {
  if (itemA == null || sku == null || itemMkt == null) {
    c.skip('BH8-00', 'BH8', 'sem SKU marketplace', null);
    return;
  }

  // Buyer INSERT order aguarda_confirmacao (MB WAY pending) + live bind
  final pend = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
    'buyer_id': c.buyerId,
    'seller_id': c.sellerId,
    'product_id': sku,
    'live_id': liveA,
    'live_item_id': itemMkt,
    'quantity': 1,
    'status': 'aguarda_confirmacao',
    'price_total': 14,
    'payment_method': 'MB WAY',
    'shipping_method': 'entrega em mão',
  });
  final oid = pend.firstId;
  if (oid != null) c.createdOrderIds.add(oid);
  c.note('BH8-01a', 'INSERT order MB WAY aguarda_confirmacao', pend, lens: 'BH8');

  if (oid == null) {
    // try reserva_pendente then patch
    final p2 = await c.rest('POST', 'orders', jwt: c.buyerJwt, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': sku,
      'live_id': liveA,
      'live_item_id': itemMkt,
      'quantity': 1,
      'status': 'reserva_pendente',
      'price_total': 14,
      'payment_method': 'MB WAY',
      'shipping_method': 'entrega em mão',
    });
    final oid2 = p2.firstId;
    if (oid2 != null) c.createdOrderIds.add(oid2);
    c.note('BH8-01b', 'fallback reserva_pendente', p2, lens: 'BH8');
    if (oid2 != null) {
      final patch = await c.rest(
        'PATCH',
        'orders?id=eq.$oid2',
        jwt: c.buyerJwt,
        body: {'status': 'aguarda_confirmacao'},
      );
      c.note('BH8-01c', 'PATCH aguarda_confirmacao', patch, lens: 'BH8');
      await _reconcileGhost(c, oid2, liveA, itemMkt, sku, w0, label: 'patched');
    }
    return;
  }

  await _reconcileGhost(c, oid, liveA, itemMkt, sku, w0, label: 'insert');
}

Future<void> _reconcileGhost(
  Rtbh c,
  String orderId,
  String liveA,
  String itemMkt,
  String sku,
  Map<String, num?> w0, {
  required String label,
}) async {
  final beforeRes = await c.rest(
    'GET',
    'live_reservation_requests?live_item_id=eq.$itemMkt&select=id,status,notes,requested_qty,buyer_id',
    service: true,
  );
  final recB = await c.rpc('batata_live_reconcile_stripe_order', {
    'p_order_id': orderId,
  }, jwt: c.buyerJwt);
  final recS = await c.rpc('batata_live_reconcile_stripe_order', {
    'p_order_id': orderId,
  }, jwt: c.sellerJwt);
  final afterRes = await c.rest(
    'GET',
    'live_reservation_requests?live_item_id=eq.$itemMkt&select=id,status,notes,requested_qty,buyer_id,source',
    service: true,
  );
  final order = await c.rest(
    'GET',
    'orders?id=eq.$orderId&select=id,status,amount_paid_cents,stripe_payment_intent_id,live_id,live_item_id',
    service: true,
  );
  final prod = await c.productRow(sku);
  final w1 = await c.wallets();

  c.note('BH8-02-$label', 'reconcile MB WAY pending', {
    'recB': recB.brief,
    'recS': recS.brief,
    'order': order.map,
    'res_after': afterRes.list,
    'w0': w0,
    'w1': w1,
  }, lens: 'BH8');

  bool consuming(dynamic r) {
    if (r is! Map) return false;
    final st = '${r['status']}';
    return st == 'accepted' || st == 'converted';
  }

  final newConsuming = afterRes.list.where(consuming).toList();
  final ghosts = afterRes.list.where((r) {
    if (r is! Map) return false;
    final notes = '${r['notes']}';
    return notes.contains(orderId) || notes.contains('stripe_paid');
  }).toList();

  if (newConsuming.isNotEmpty &&
      numOf(order.map?['amount_paid_cents']) == 0 &&
      (order.map?['stripe_payment_intent_id'] == null ||
          '${order.map?['stripe_payment_intent_id']}'.isEmpty)) {
    c.hold(
      id: 'BH8-01',
      lens: 'BH8',
      severity: 'P1',
      title: 'Reconcile MB WAY aguarda_confirmacao converte reserva sem captura',
      actor: 'buyer/seller JWT',
      pre: 'order sem amount_paid nem PI, status aguarda_confirmacao',
      repro: 'rpc batata_live_reconcile_stripe_order',
      expected: 'order_not_paid / sem converted',
      obtained: {
        'recB': recB.brief,
        'recS': recS.brief,
        'consuming': newConsuming,
        'order': order.map,
        'product': prod,
      },
    );
  } else if (ghosts.isNotEmpty) {
    final pendingGhost = ghosts.any((r) => r is Map && r['status'] == 'pending');
    c.hold(
      id: 'BH8-02',
      lens: 'BH8',
      severity: pendingGhost ? 'P2' : 'P2',
      title: 'Reconcile MB WAY pending cria fila fantasma (notes stripe_paid*)',
      actor: 'seller/buyer JWT',
      pre: 'order MB WAY não capturada',
      repro: 'rpc batata_live_reconcile_stripe_order',
      expected: 'sem INSERT reservation',
      obtained: {
        'recB': recB.brief,
        'recS': recS.brief,
        'ghosts': ghosts,
        'order': order.map,
      },
    );
  } else {
    c.block('BH8-01', 'BH8', 'reconcile MB WAY sem convert/ghost', {
      'recB': recB.brief,
      'recS': recS.brief,
      'res': afterRes.list.length,
    });
  }

  // Δ wallet
  final dSeller = (w1['seller'] ?? 0) - (w0['seller'] ?? 0);
  final dBuyer = (w1['buyer'] ?? 0) - (w0['buyer'] ?? 0);
  if (dSeller > 0 || dBuyer > 0) {
    c.hold(
      id: 'BH8-03',
      lens: 'BH8',
      severity: 'P0',
      title: 'Reconcile MB WAY pending mintou saldo wallet',
      actor: 'JWT reconcile',
      pre: 'sem captura Stripe',
      repro: 'rpc reconcile + wallets',
      expected: 'Δwallet = 0',
      obtained: {'w0': w0, 'w1': w1, 'dSeller': dSeller, 'dBuyer': dBuyer},
    );
  } else {
    c.block('BH8-03', 'BH8', 'sem Δ wallet no reconcile pending', {
      'dSeller': dSeller,
      'dBuyer': dBuyer,
    });
  }

  // Anon reconcile
  final recAnon = await c.rpc('batata_live_reconcile_stripe_order', {
    'p_order_id': orderId,
  });
  await c.expectDenied(
    id: 'BH8-04',
    lens: 'BH8',
    title: 'Anon chama reconcile_stripe_order',
    hit: recAnon,
    actor: 'anon',
    pre: 'GRANT authenticated',
    repro: 'rpc reconcile anon',
    severityIfOpen: 'P2',
    openIf: (h) => h.rpcOk,
  );

  // Seller2 reconcile order alheia
  if (c.seller2Jwt != null) {
    final recS2 = await c.rpc('batata_live_reconcile_stripe_order', {
      'p_order_id': orderId,
    }, jwt: c.seller2Jwt);
    await c.expectDenied(
      id: 'BH8-05',
      lens: 'BH8',
      title: 'Seller2 reconcile order seller1/buyer1',
      hit: recS2,
      actor: 'seller2 JWT',
      pre: 'não é party',
      repro: 'rpc reconcile',
      severityIfOpen: 'P1',
      openIf: (h) => h.rpcOk,
    );
  }

  c.note('BH8-beforeRes', 'reservas antes', beforeRes.list.length, lens: 'BH8');
}
