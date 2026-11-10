/// Pass 3 — POÇO 4 órbita + races + composição. Sem correções.
import 'dart:io';
import '_rt.dart';

Future<void> main() async {
  final c = Rti4(loadEnv());
  await c.boot();

  // ---- Connect return origin ----
  final evilOrigins = [
    'https://evil.com',
    'https://fleaber.pt.evil.com',
    'https://evil.com/@fleaber.pt',
    'http://fleaber.pt',
    'https://fleaber.pt%2F%2Fevil.com',
    'https://localhost.evil.com',
  ];
  for (final o in evilOrigins) {
    final r = await c.edge(
      'create-connect-account',
      {'web_return_origin': o},
      token: c.sellerJwt,
    );
    c.note('p4.connect.origin', 'connect origin $o', {
      'http': r.status,
      'loc': r.location,
      'snip': clip(r.body, 220),
    }, well: '4');
    final loc = (r.location ?? r.map?['url'] ?? r.body).toString();
    if (loc.contains('evil.com') && !loc.contains('fleaber.pt/wallet')) {
      c.finding(
        id: 'P4-CONNECT-REDIRECT',
        title: 'Connect return origin open-redirect',
        actor: 'seller JWT',
        sev: 'P1',
        well: '4',
        pre: 'web_return_origin hostil',
        request: 'POST create-connect-account',
        before: o,
        after: clip(loc, 300),
        impact: 'Phishing OAuth/Connect',
        repro: 'POST create-connect-account web_return_origin=$o',
      );
    }
  }
  c.hold('p4.connect.origin', 'origens evil não ecoadas em Location (amostra)',
      evilOrigins, well: '4');

  // ---- Tip Edge bind / amount ----
  final liveR = await c.rest(
    'POST',
    'lives',
    token: c.sellerJwt,
    body: {
      'seller_id': c.sellerId,
      'title': '$prefix-TIP',
      'status': 'ended',
      'is_active': false,
    },
  );
  String? liveId;
  if (liveR.list.isNotEmpty) liveId = (liveR.list.first as Map)['id']?.toString();
  liveId ??= liveR.map?['id']?.toString();
  if (liveId != null) c.createdLiveIds.add(liveId);

  if (liveId != null) {
    final tipPend = await c.rpc(
      'batata_create_live_tip_pending',
      {
        'p_live_id': liveId,
        'p_seller_id': c.sellerId,
        'p_amount': 5,
        'p_message': '$prefix tip ended',
        'p_stripe_session_id': 'cs_test_forged_bind',
      },
      token: c.buyerJwt,
    );
    c.note('p4.tip.pending.ended', 'tip pending ended + forged session', tipPend.brief,
        well: '4');
    final tipId = '${tipPend.json ?? ''}';

    final tipEdge = await c.edge(
      'create-live-tip-checkout',
      {
        'live_id': liveId,
        'seller_id': c.sellerId,
        'amount_eur': 1,
        'tip_id': tipId.length > 10 ? tipId.replaceAll('"', '') : null,
        'web_return_origin': 'https://evil.com',
      },
      token: c.buyerJwt,
    );
    c.note('p4.tip.edge', 'tip checkout amount/origin', clip(tipEdge.body, 400), well: '4');

    // Bind stolen session id via REST
    if (tipId.length > 10) {
      final tid = tipId.replaceAll('"', '');
      final bind = await c.rest(
        'PATCH',
        'live_tips?id=eq.$tid',
        token: c.buyerJwt,
        body: {'stripe_session_id': 'cs_test_stolen', 'status': 'completed'},
      );
      final after = await c.getOne(
        'live_tips',
        tid,
        select: 'id,status,stripe_session_id,amount,seller_amount',
      );
      c.note('p4.tip.bind.patch', 'PATCH tip session/status', {
        'http': bind.status,
        'after': after,
      }, well: '4');
      if ('${after?['status']}'.toLowerCase() == 'completed') {
        c.finding(
          id: 'P4-TIP-JWT-COMPLETE',
          title: 'JWT marca live_tip completed sem captura',
          actor: 'buyer JWT',
          sev: 'P1',
          well: '4',
          pre: 'tip pending',
          request: 'PATCH live_tips status=completed',
          before: tipPend.brief,
          after: after,
          impact: 'Gorjeta liquidada sem Stripe/wallet',
          repro: 'PATCH live_tips completed',
        );
      } else {
        c.hold('p4.tip.bind.patch', 'tip status não completed via JWT', after, well: '4');
      }
    }

    // Wallet tip ended
    final wTip = await c.rpc(
      'batata_send_live_tip_from_wallet',
      {
        'p_live_id': liveId,
        'p_seller_id': c.sellerId,
        'p_amount': 1,
      },
      token: c.buyerJwt,
    );
    c.note('p4.tip.wallet.ended', 'wallet tip on ended live', wTip.brief, well: '4');
  }

  // ---- Follows / favorites cross ----
  final folAll = await c.rest(
    'GET',
    'follows?select=follower_id,following_id,created_at&limit=20',
    token: c.freshJwt ?? c.buyerJwt,
  );
  c.note('p4.follows.select', 'follows as fresh/buyer', {
    'http': folAll.status,
    'n': folAll.list.length,
  }, well: '4');
  if (folAll.ok &&
      c.freshId != null &&
      folAll.list.any((e) {
        if (e is! Map) return false;
        return '${e['follower_id']}' != c.freshId &&
            '${e['following_id']}' != c.freshId;
      })) {
    c.finding(
      id: 'P4-FOLLOWS-ENUM',
      title: 'JWT enumera follows alheios',
      actor: 'fresh JWT',
      sev: 'P2',
      well: '4',
      pre: 'fresh user',
      request: 'GET follows',
      before: null,
      after: clip(folAll.body, 400),
      impact: 'Grafo social global',
      repro: 'GET follows as fresh',
    );
  } else {
    c.hold('p4.follows.select', 'follows scoped', {'n': folAll.list.length}, well: '4');
  }

  if (c.freshJwt != null && c.freshId != null) {
    final hijack = await c.rest(
      'POST',
      'follows',
      token: c.freshJwt,
      body: {'follower_id': c.buyerId, 'following_id': c.sellerId},
    );
    c.note('p4.follows.hijack', 'INSERT follow as other uid', hijack.brief, well: '4');
    if (hijack.ok && hijack.list.isNotEmpty) {
      final row = Map<String, dynamic>.from(hijack.list.first as Map);
      if ('${row['follower_id']}' == c.buyerId) {
        c.finding(
          id: 'P4-FOLLOW-AS-OTHER',
          title: 'Fresh JWT cria follow com follower_id alheio',
          actor: 'fresh JWT',
          sev: 'P1',
          well: '4',
          pre: 'follower_id=buyer',
          request: 'POST follows',
          before: null,
          after: row,
          impact: 'Autoridade de identidade em follows',
          repro: 'POST follows follower_id=other',
        );
      }
    } else {
      c.hold('p4.follows.hijack', 'follow as other bloqueado', hijack.brief, well: '4');
    }
  }

  final favs = await c.rest(
    'GET',
    'favorites?select=id,user_id,product_id&limit=20',
    token: c.freshJwt ?? c.buyerJwt,
  );
  c.note('p4.favorites.select', 'favorites fresh', {
    'http': favs.status,
    'n': favs.list.length,
  }, well: '4');
  if (favs.ok &&
      c.freshId != null &&
      favs.list.any((e) => e is Map && '${e['user_id']}' != c.freshId)) {
    c.finding(
      id: 'P4-FAV-CROSS',
      title: 'JWT lê favorites de outros',
      actor: 'fresh JWT',
      sev: 'P1',
      well: '4',
      pre: 'GET favorites',
      request: 'GET favorites',
      before: null,
      after: clip(favs.body, 400),
      impact: 'Lista de desejos alheia',
      repro: 'GET favorites as other',
    );
  } else {
    c.hold('p4.favorites.select', 'favorites scoped', {'n': favs.list.length}, well: '4');
  }

  // Favorite unlisted (oracle)
  final unlist = await c.insertProduct(listed: false, sold: false, title: '$prefix-FAV');
  if (unlist != null) {
    final fav = await c.rest(
      'POST',
      'favorites',
      token: c.buyerJwt,
      body: {'user_id': c.buyerId, 'product_id': unlist['id']},
    );
    c.note('p4.fav.unlist', 'favorite unlist', fav.brief, well: '4');
  }

  // Device token as buyer
  final tok = await c.rpc(
    'batata_create_seller_device_token',
    {'p_device_id': 'rti4-device', 'p_label': 'x'},
    token: c.buyerJwt,
  );
  c.note('p4.device.buyer', 'device token as buyer', tok.brief, well: '4');
  if (tok.map?['ok'] == true && tok.map?['token'] != null) {
    c.finding(
      id: 'P4-OCR-TOKEN-BUYER',
      title: 'Buyer cria device token OCR de seller',
      actor: 'buyer JWT',
      sev: 'P1',
      well: '4',
      pre: 'buyer não seller',
      request: 'rpc batata_create_seller_device_token',
      before: null,
      after: clip(tok.body, 300),
      impact: 'Token de ingestão/OCR',
      repro: 'rpc device token as buyer',
    );
  } else {
    c.hold('p4.device.buyer', 'buyer device token negado', tok.brief, well: '4');
  }

  // Cron / cleanup without secret
  final cron = await c.edge('livekit-egress-cleanup', {'secret': 'x'}, token: c.buyerJwt);
  c.note('p4.cron.cleanup', 'egress cleanup JWT', cron.brief, well: '4');
  if (cron.ok && (cron.map?['ok'] == true || cron.body.contains('deleted'))) {
    c.finding(
      id: 'P4-CRON-JWT',
      title: 'JWT dispara cleanup/cron privilegiado',
      actor: 'buyer JWT',
      sev: 'P1',
      well: '4',
      pre: 'sem secret vault',
      request: 'POST livekit-egress-cleanup',
      before: null,
      after: cron.brief,
      impact: 'Órbita operacional sem autoridade',
      repro: 'POST livekit-egress-cleanup as buyer',
    );
  } else {
    c.hold('p4.cron.cleanup', 'cleanup JWT negado', cron.brief, well: '4');
  }

  // Webhook sem assinatura
  final wh = await c.call(
    'POST',
    '/functions/v1/stripe-webhook',
    body: {
      'type': 'checkout.session.completed',
      'data': {
        'object': {'id': 'cs_test_fake', 'payment_status': 'paid'}
      }
    },
  );
  c.note('p4.webhook.nosig', 'webhook sem stripe-signature', wh.brief, well: '4');
  if (wh.ok && !wh.body.toLowerCase().contains('signature')) {
    // anti-atrophy: webhook sem assinatura já HOLD — residual se 200 vazio
    c.note('p4.webhook.residual', 'HTTP webhook (núcleo saturado se 400)', wh.brief,
        well: '4');
  }

  // auto_feedback as JWT
  final af = await c.rpc('batata_generate_auto_feedback', {}, token: c.buyerJwt);
  c.note('p4.auto_feedback.jwt', 'auto_feedback JWT', af.brief, well: '4');
  if (af.ok && '${af.json}'.contains('generated')) {
    c.finding(
      id: 'P4-AUTO-FEEDBACK-JWT',
      title: 'JWT dispara auto-feedback cron',
      actor: 'buyer JWT',
      sev: 'P1',
      well: '2',
      pre: 'rpc cron',
      request: 'rpc batata_generate_auto_feedback',
      before: null,
      after: af.brief,
      impact: 'Reviews automáticas sob demanda',
      repro: 'rpc auto_feedback as buyer',
    );
  } else {
    c.hold('p4.auto_feedback.jwt', 'auto_feedback JWT negado', af.brief, well: '4');
  }

  // ---- Race: qty=1 dois holds paralelos ----
  final raceP = await c.insertProduct(
    listed: true,
    sold: false,
    title: '$prefix-RACE',
    qty: 1,
  );
  if (raceP != null) {
    final pid = raceP['id'].toString();
    final futs = List.generate(
      4,
      (i) => c.insertOrder(
        token: c.buyerJwt,
        productId: pid,
        qty: 1,
        extra: {'client_tag': 'race-$i'},
      ),
    );
    final rs = await Future.wait(futs);
    final held = <String>[];
    for (final r in rs) {
      c.note('p1.race.hold', 'parallel hold', r.brief, well: '1');
      final oid = c.orderIdOf(r);
      if (oid != null) {
        final row = await c.getOne('orders', oid, select: 'id,status,quantity');
        final st = '${row?['status'] ?? ''}'.toLowerCase();
        if (['reserva_pendente', 'reservado', 'aguarda_confirmacao'].contains(st)) {
          held.add(oid);
        }
      }
    }
    final prod = await c.getOne('products', pid, select: 'id,quantity,is_sold');
    c.note('p1.race.result', 'holds vs stock', {
      'held': held.length,
      'product': prod,
    }, well: '1');
    if (held.length >= 2) {
      // Session both?
      final chk0 = await c.checkout(token: c.buyerJwt, orderId: held[0], productId: pid);
      final chk1 = await c.checkout(token: c.buyerJwt, orderId: held[1], productId: pid);
      final s0 = chk0.ok &&
          '${chk0.map?['checkoutUrl'] ?? chk0.map?['url'] ?? chk0.map?['session_id']}'
              .isNotEmpty;
      final s1 = chk1.ok &&
          '${chk1.map?['checkoutUrl'] ?? chk1.map?['url'] ?? chk1.map?['session_id']}'
              .isNotEmpty;
      c.note('p1.race.checkout', 'dual session qty=1', {
        's0': s0,
        's1': s1,
        'c0': clip(chk0.body, 200),
        'c1': clip(chk1.body, 200),
      }, well: '1');
      if (held.length >= 2 && s0 && s1) {
        c.finding(
          id: 'P1-RACE-DUAL-SESSION',
          title: 'qty=1: dois holds + duas Sessions',
          actor: 'buyer JWT N-paralelo',
          sev: 'P2',
          well: '1',
          pre: 'quantity=1, 4 INSERT paralelos',
          request: 'POST orders ×4; create-payment-intent ×2',
          before: raceP,
          after: {'held': held, 'sessions': [s0, s1], 'product': prod},
          impact:
              'SESSION CRIADA em duplicado; captura permanente não provada neste passo',
          repro: '4× POST orders parallel qty=1',
        );
      } else if (held.length >= 2) {
        c.note('p1.race.two.holds', 'dois holds sem dual session', {
          'held': held.length,
          's0': s0,
          's1': s1,
        }, well: '1');
      }
    } else {
      c.hold('p1.race.hold', 'no máximo 1 hold qty=1', {'held': held.length}, well: '1');
    }
  }

  // Hub reviews_public PII
  final hr = await c.rest(
    'GET',
    'hub_reviews_public?select=id,author_display,comment,stars,target_id,buyer_id&limit=8',
  );
  c.note('p3.hub.reviews', 'hub_reviews_public', {
    'http': hr.status,
    'n': hr.list.length,
    'snip': clip(hr.body, 300),
  }, well: '3');

  final hp = await c.rest(
    'GET',
    'hub_profiles_public?select=id,handle,full_name,location,phone,iban&limit=5',
  );
  c.note('p3.hub.profiles', 'hub_profiles_public cols', {
    'http': hp.status,
    'n': hp.list.length,
  }, well: '3');

  await c.dump('pass3');
  stdout.writeln('pass3 done findings=${c.findings.length} holds=${c.holds.length}');
}
