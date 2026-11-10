/// Pass 1 — J1–J6 discovery + first hostile hits. Staging only. No fixes.
import 'dart:convert';
import 'dart:io';

import '_rtj.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rtj.fromEnv(env);
  await c.loginActors(env);
  await c.ensureBuyer2();
  await c.ensureSeller2();

  c.note('actors', {
    'buyer': c.buyerId,
    'seller': c.sellerId,
    'buyer2': c.buyer2Id,
    'seller2': c.seller2Id,
  });

  // --- OpenAPI surface ---
  final oa = await c.req('GET', '/rest/v1/', extra: {'Accept': 'application/openapi+json'});
  final defs = <String>[];
  if (oa.json is Map) {
    final paths = (oa.json as Map)['paths'];
    if (paths is Map) {
      for (final k in paths.keys) {
        final s = k.toString();
        if (s.contains('chat') ||
            s.contains('review') ||
            s.contains('notif') ||
            s.contains('favorit') ||
            s.contains('follow') ||
            s.contains('push') ||
            s.contains('device_token') ||
            s.contains('handle') ||
            s.contains('bundle') ||
            s.contains('live_message')) {
          defs.add(s);
        }
      }
    }
  }
  c.note('openapi.surface', defs);

  // --- Fixtures: chat + orders ---
  final chatsSvc = await c.rest(
    'GET',
    'chats?or=(and(user_a.eq.${c.buyerId},user_b.eq.${c.sellerId}),and(user_a.eq.${c.sellerId},user_b.eq.${c.buyerId}))&select=id,user_a,user_b,created_at&limit=3',
    service: true,
  );
  String? chatId = chatsSvc.firstId;
  if (chatId == null) {
    final created = await c.rest('POST', 'chats', jwt: c.buyerJwt, body: {
      'user_a': c.buyerId,
      'user_b': c.sellerId,
    });
    c.note('chat.create', {'http': created.status, 'body': created.snippet});
    chatId = created.firstId;
  }
  c.note('chat.id', chatId);

  final ordersBuyer = await c.rest(
    'GET',
    'orders?buyer_id=eq.${c.buyerId}&seller_id=eq.${c.sellerId}&select=id,status,payment_method,amount_paid_cents,price_total,stripe_checkout_session_id,stripe_payment_intent_id&order=created_at.desc&limit=8',
    service: true,
  );
  c.note('orders.buyer_seller', {
    'http': ordersBuyer.status,
    'n': ordersBuyer.list.length,
    'rows': ordersBuyer.list.take(8).map((e) {
      if (e is! Map) return e;
      return {
        'id': e['id'],
        'status': e['status'],
        'pm': e['payment_method'],
        'paid_cents': e['amount_paid_cents'],
        'total': e['price_total'],
        'has_cs': (e['stripe_checkout_session_id']?.toString() ?? '').isNotEmpty,
      };
    }).toList(),
  });

  final paidOrder = ordersBuyer.list.cast<dynamic>().where((e) {
    if (e is! Map) return false;
    final st = (e['status'] ?? '').toString().toLowerCase();
    return st == 'pago' ||
        st == 'enviado' ||
        st == 'concluido' ||
        st == 'entregue';
  }).cast<Map>().toList();
  final unpaidOrder = ordersBuyer.list.cast<dynamic>().where((e) {
    if (e is! Map) return false;
    final st = (e['status'] ?? '').toString().toLowerCase();
    return st.contains('pendente') || st == 'reserva_pendente' || st == 'aguardando';
  }).cast<Map>().toList();
  final concluido = ordersBuyer.list.cast<dynamic>().where((e) {
    if (e is! Map) return false;
    final st = (e['status'] ?? '').toString().toLowerCase();
    return st == 'concluido' || st == 'entregue';
  }).cast<Map>().toList();

  final oidPaid = paidOrder.isNotEmpty ? paidOrder.first['id']?.toString() : null;
  final oidUnpaid =
      unpaidOrder.isNotEmpty ? unpaidOrder.first['id']?.toString() : null;
  final oidDone = concluido.isNotEmpty ? concluido.first['id']?.toString() : null;
  final csVictim = paidOrder
      .map((e) => e['stripe_checkout_session_id']?.toString() ?? '')
      .firstWhere((s) => s.startsWith('cs_'), orElse: () => '');

  // =====================================================================
  // J1 — chat card forge
  // =====================================================================
  if (chatId != null) {
    Future<Map<String, Object?>> tryCard(
      String tag,
      String jwt,
      String text, {
      String? sender,
      String? chat,
    }) async {
      final h = await c.rest('POST', 'chat_messages', jwt: jwt, body: {
        'chat_id': chat ?? chatId,
        'sender_id': sender ?? '00000000-0000-0000-0000-000000000000',
        'text': text,
      });
      return {
        'tag': tag,
        'http': h.status,
        'id': h.firstId,
        'body': h.snippet,
        'stored_text': h.map?['text'],
        'stored_sender': h.map?['sender_id'],
      };
    }

    final j1 = <Map<String, Object?>>[];

    j1.add(await tryCard(
      'server_only_bag_paid',
      c.buyerJwt!,
      fleaberCard({
        'kind': 'marketplace_bag_paid',
        'order_id': oidPaid ?? '00000000-0000-0000-0000-000000000001',
        'total': 9999.99,
      }),
    ));
    j1.add(await tryCard(
      'raffle_prize',
      c.buyerJwt!,
      fleaberCard({'kind': 'raffle_prize', 'prize': 'iPhone'}),
    ));
    j1.add(await tryCard(
      'kind_denied_paid_fake',
      c.buyerJwt!,
      fleaberCard({'kind': 'order_paid', 'total': 1.00}),
    ));
    j1.add(await tryCard(
      'seguro_paid_unpaid_order',
      c.buyerJwt!,
      fleaberCard({
        'kind': 'seguro_fleaber_paid',
        'order_id': oidUnpaid ?? oidPaid ?? '00000000-0000-0000-0000-000000000001',
        'total': 8888.88,
        'label': '$prefix-LIE',
      }),
    ));
    j1.add(await tryCard(
      'seguro_paid_no_order',
      c.buyerJwt!,
      fleaberCard({'kind': 'seguro_fleaber_paid', 'total': 777.00}),
    ));
    j1.add(await tryCard(
      'bundle_proposal_fake_total',
      c.buyerJwt!,
      fleaberCard({
        'kind': 'bundle_proposal',
        'bundle_id': '00000000-0000-0000-0000-000000000099',
        'total_eur': 0.01,
        'subtotal_eur': 500.00,
        'seller_id': c.sellerId,
        'buyer_id': c.buyerId,
      }),
    ));
    j1.add(await tryCard(
      'chat_image_private_url',
      c.buyerJwt!,
      fleaberCard({
        'kind': 'chat_image',
        'url':
            '${c.url}/storage/v1/object/fleaber_private/order_proofs/${c.sellerId}/secret.jpg',
      }),
    ));
    j1.add(await tryCard(
      'shipped_as_buyer',
      c.buyerJwt!,
      fleaberCard({
        'kind': 'reservation_order_shipped',
        'order_id': oidPaid ?? '00000000-0000-0000-0000-000000000001',
      }),
    ));
    j1.add(await tryCard(
      'receipt_as_buyer',
      c.buyerJwt!,
      fleaberCard({
        'kind': 'reservation_seller_confirmed_receipt',
        'order_id': oidPaid ?? '00000000-0000-0000-0000-000000000001',
      }),
    ));
    j1.add(await tryCard(
      'completed_as_buyer_unpaid',
      c.buyerJwt!,
      fleaberCard({
        'kind': 'reservation_order_completed',
        'order_id': oidUnpaid ?? oidPaid ?? '00000000-0000-0000-0000-000000000001',
      }),
    ));
    j1.add(await tryCard(
      'direct_pay_as_buyer',
      c.buyerJwt!,
      fleaberCard({
        'kind': 'order_direct_payment_details',
        'order_id': oidPaid ?? '00000000-0000-0000-0000-000000000001',
        'iban': 'PT50000000000000000000000',
        'mbway': '999999999',
      }),
    ));
    j1.add(await tryCard(
      'sender_spoof_seller',
      c.buyerJwt!,
      'ola $prefix',
      sender: c.sellerId,
    ));
    j1.add(await tryCard(
      'buyer2_into_ab_chat',
      c.buyer2Jwt!,
      fleaberCard({
        'kind': 'seguro_fleaber_paid',
        'order_id': oidPaid ?? '00000000-0000-0000-0000-000000000001',
        'total': 1,
      }),
    ));

    // seller cards
    j1.add(await tryCard(
      'seller_direct_pay_fake_iban',
      c.sellerJwt!,
      fleaberCard({
        'kind': 'order_direct_payment_details',
        'order_id': oidPaid ?? oidUnpaid ?? '00000000-0000-0000-0000-000000000001',
        'iban': 'PT50RTJFAKE00000000000000',
        'mbway': '910000000',
      }),
    ));
    j1.add(await tryCard(
      'seller_shipped_unpaid',
      c.sellerJwt!,
      fleaberCard({
        'kind': 'reservation_order_shipped',
        'order_id': oidUnpaid ?? oidPaid ?? '00000000-0000-0000-0000-000000000001',
      }),
    ));

    // UPDATE classic (1 repro — HOLD if immutable)
    final insertedPlain = j1.firstWhere(
      (e) => e['tag'] == 'sender_spoof_seller' && e['http'] == 201,
      orElse: () => {},
    );
    if (insertedPlain['id'] != null) {
      final mid = insertedPlain['id'];
      final upd = await c.rest(
        'PATCH',
        'chat_messages?id=eq.$mid',
        jwt: c.buyerJwt,
        body: {
          'text': fleaberCard({
            'kind': 'seguro_fleaber_paid',
            'order_id': oidPaid,
            'total': 1.00,
          }),
        },
      );
      j1.add({
        'tag': 'update_plain_to_json',
        'http': upd.status,
        'body': upd.snippet,
        'stored': upd.map?['text'],
      });
    }

    final jsonHits = j1
        .where((e) =>
            e['http'] == 201 &&
            (e['stored_text']?.toString() ?? '').startsWith('FLEABER_JSON_V1:'))
        .toList();
    for (final hit in jsonHits) {
      final mid = hit['id'];
      final upd = await c.rest(
        'PATCH',
        'chat_messages?id=eq.$mid',
        jwt: c.buyerJwt,
        body: {
          'text': fleaberCard({'kind': 'marketplace_bag_paid', 'total': 0.01}),
        },
      );
      j1.add({
        'tag': 'update_json_immutable_${hit['tag']}',
        'http': upd.status,
        'body': upd.snippet,
      });
    }

    // stranger chat SELECT
    final xchat = await c.rest(
      'GET',
      'chat_messages?chat_id=eq.$chatId&select=id,sender_id,text&limit=5',
      jwt: c.buyer2Jwt,
    );
    j1.add({
      'tag': 'buyer2_read_ab_chat',
      'http': xchat.status,
      'n': xchat.list.length,
      'body': xchat.snippet,
    });

    c.note('j1.cards', j1);

    for (final hit in j1) {
      final tag = hit['tag']?.toString() ?? '';
      final http = hit['http'];
      final persisted = http == 201;
      if (tag == 'buyer2_read_ab_chat' && (hit['n'] as int? ?? 0) > 0) {
        c.addFinding(finding(
          id: '$prefix-J1-XCHAT-READ',
          lens: 'J1',
          severity: 'P1',
          title: 'buyer2 lê mensagens do chat A↔B',
          pre: 'JWT buyer2, chat alheio',
          repro: 'GET chat_messages?chat_id=eq.$chatId',
          proven: true,
          evidence: {'n': hit['n'], 'body': hit['body']},
        ));
      }
      if (persisted &&
          (tag == 'server_only_bag_paid' ||
              tag == 'raffle_prize' ||
              tag == 'kind_denied_paid_fake')) {
        c.addFinding(finding(
          id: '$prefix-J1-$tag',
          lens: 'J1',
          severity: 'P1',
          title: 'INSERT card servidor/kind negado persistiu',
          pre: tag,
          repro: 'POST chat_messages FLEABER_JSON_V1',
          proven: true,
          evidence: hit,
        ));
      }
      if (persisted && tag == 'buyer2_into_ab_chat') {
        c.addFinding(finding(
          id: '$prefix-J1-STRANGER-INSERT',
          lens: 'J1',
          severity: 'P1',
          title: 'buyer2 INSERT no chat A↔B',
          pre: 'não participante',
          repro: 'POST chat_messages chat_id A-B',
          proven: true,
          evidence: hit,
        ));
      }
      if (persisted && tag == 'seguro_paid_unpaid_order') {
        c.addFinding(finding(
          id: '$prefix-J1-SEGURO-UNPAID',
          lens: 'J1',
          severity: 'P2',
          title: 'Card «pago» INSERT em encomenda não paga',
          pre: 'kind seguro_fleaber_paid + order pendente',
          repro: 'POST chat_messages',
          proven: true,
          evidence: hit,
          note: 'UI mostra recibo; CTAs de envio/caixa devem ler orders.status',
        ));
      }
      if (persisted && tag == 'seller_shipped_unpaid') {
        c.addFinding(finding(
          id: '$prefix-J1-SHIP-UNPAID',
          lens: 'J1',
          severity: 'P2',
          title: 'Seller INSERT «enviado» em encomenda não paga',
          pre: 'reservation_order_shipped',
          repro: 'POST chat_messages',
          proven: true,
          evidence: hit,
        ));
      }
      if (persisted && tag == 'seller_direct_pay_fake_iban') {
        c.addFinding(finding(
          id: '$prefix-J1-IBAN-CARD',
          lens: 'J1',
          severity: 'P2',
          title: 'Seller INSERT IBAN/MB WAY no card (não validado vs perfil)',
          pre: 'order_direct_payment_details',
          repro: 'POST chat_messages',
          proven: true,
          evidence: {'http': http, 'id': hit['id']},
          note: 'Mentira do próprio seller — UI vs perfil; sem authz extra',
        ));
      }
      if (persisted &&
          tag == 'sender_spoof_seller' &&
          hit['stored_sender'] == c.sellerId) {
        c.addFinding(finding(
          id: '$prefix-J1-SENDER-SPOOF',
          lens: 'J1',
          severity: 'P0',
          title: 'sender_id spoof persistiu como seller',
          pre: 'JWT buyer, body sender_id=seller',
          repro: 'POST chat_messages',
          proven: true,
          evidence: hit,
        ));
      }
      if (tag.startsWith('update_json_immutable') && http == 200) {
        final stored = hit['body']?.toString() ?? '';
        if (stored.contains('marketplace_bag_paid')) {
          c.addFinding(finding(
            id: '$prefix-J1-JSON-UPDATE',
            lens: 'J1',
            severity: 'P1',
            title: 'UPDATE FLEABER_JSON_V1 mutou card',
            pre: 'D4 deveria ser imutável',
            repro: 'PATCH chat_messages text',
            proven: true,
            evidence: hit,
          ));
        }
      }
    }
  }

  // =====================================================================
  // J2 — reviews
  // =====================================================================
  final j2 = <String, Object?>{};
  final revGerais = await c.rest(
    'GET',
    'reviews_gerais?select=id,buyer_id,target_id,stars,comment&limit=8',
    jwt: c.buyer2Jwt,
  );
  j2['reviews_gerais_b2'] = {
    'http': revGerais.status,
    'n': revGerais.list.length,
    'cols': revGerais.list.isNotEmpty && revGerais.list.first is Map
        ? (revGerais.list.first as Map).keys.toList()
        : [],
    'sample': clip(revGerais.body, 500),
  };
  final alienBuyer = revGerais.list.where((e) {
    if (e is! Map) return false;
    final bid = e['buyer_id']?.toString();
    return bid != null &&
        bid.isNotEmpty &&
        bid != c.buyer2Id &&
        bid != c.buyerId;
  }).toList();
  // 6-A HOLD expected. Only finding if STILL leaking alien buyer_id.
  if (alienBuyer.isNotEmpty) {
    c.addFinding(finding(
      id: '$prefix-J2-REVIEWS-BUYER-ID',
      lens: 'J2',
      severity: 'P2',
      title: 'reviews_gerais ainda expõe buyer_id alheio (6-A reaberto)',
      pre: 'JWT buyer2',
      repro: 'GET reviews_gerais',
      proven: true,
      evidence: {'n': alienBuyer.length, 'sample': clip(alienBuyer.first)},
    ));
  }

  final hubRev = await c.rest(
    'GET',
    'hub_reviews_public?select=id,author_display,comment,stars,target_id,buyer_id&limit=8',
  );
  j2['hub_reviews_anon'] = {
    'http': hubRev.status,
    'n': hubRev.list.length,
    'has_buyer_id': hubRev.body.contains('buyer_id'),
    'sample': clip(hubRev.body, 400),
  };

  final pubRatings = await c.rest(
    'GET',
    'reviews_public_ratings?select=id,target_id,stars,comment,purchase_verified,author_role&limit=8',
  );
  j2['reviews_public_ratings_anon'] = {
    'http': pubRatings.status,
    'n': pubRatings.list.length,
    'sample': clip(pubRatings.body, 400),
  };

  Future<Map<String, Object?>> tryReview(
    String tag,
    String jwt,
    Map<String, Object?> body,
  ) async {
    final h = await c.rest('POST', 'reviews', jwt: jwt, body: body);
    return {
      'tag': tag,
      'http': h.status,
      'id': h.firstId,
      'body': h.snippet,
      'stored': h.map,
    };
  }

  final reviewsTries = <Map<String, Object?>>[];
  reviewsTries.add(await tryReview('no_order', c.buyer2Jwt!, {
    'stars': 5,
    'comment': '$prefix no-order',
    'target_id': c.sellerId,
    'author_role': 'comprador',
    'buyer_id': c.buyer2Id,
  }));
  reviewsTries.add(await tryReview('seller_self', c.sellerJwt!, {
    'stars': 5,
    'comment': '$prefix seller-self',
    'target_id': c.sellerId,
    'author_role': 'vendedor',
    'buyer_id': c.sellerId,
    'order_id': oidDone ?? oidPaid,
  }));
  if (oidDone != null || oidPaid != null) {
    reviewsTries.add(await tryReview('b2_on_b1_order', c.buyer2Jwt!, {
      'stars': 1,
      'comment': '$prefix hijack',
      'target_id': c.sellerId,
      'author_role': 'comprador',
      'buyer_id': c.buyerId,
      'order_id': oidDone ?? oidPaid,
    }));
  }
  if (oidUnpaid != null) {
    reviewsTries.add(await tryReview('unpaid_order', c.buyerJwt!, {
      'stars': 5,
      'comment': '$prefix unpaid',
      'order_id': oidUnpaid,
      'buyer_id': c.buyerId,
    }));
  }
  if (oidDone != null) {
    reviewsTries.add(await tryReview('dup_or_ok', c.buyerJwt!, {
      'stars': 5,
      'comment': '$prefix dup',
      'order_id': oidDone,
      'buyer_id': c.buyerId,
    }));
  }

  // UPDATE stars on any review buyer2 can see
  final ownRev = await c.rest(
    'GET',
    'reviews?select=id,stars,buyer_id,comment&limit=3',
    jwt: c.buyerJwt,
  );
  if (ownRev.list.isNotEmpty && ownRev.list.first is Map) {
    final rid = (ownRev.list.first as Map)['id'];
    final oldStars = (ownRev.list.first as Map)['stars'];
    final upd = await c.rest(
      'PATCH',
      'reviews?id=eq.$rid',
      jwt: c.buyerJwt,
      body: {'stars': 1, 'comment': '$prefix mutated'},
    );
    reviewsTries.add({
      'tag': 'update_stars',
      'http': upd.status,
      'body': upd.snippet,
      'old': oldStars,
      'new': upd.map?['stars'],
      'new_comment': upd.map?['comment'],
    });
  }

  j2['tries'] = reviewsTries;
  c.note('j2', j2);

  for (final t in reviewsTries) {
    if (t['http'] == 201 &&
        t['tag'] != 'dup_or_ok') {
      c.addFinding(finding(
        id: '$prefix-J2-${t['tag']}',
        lens: 'J2',
        severity: t['tag'] == 'b2_on_b1_order' ? 'P0' : 'P1',
        title: 'INSERT review hostil persistiu (${t['tag']})',
        pre: t['tag']!.toString(),
        repro: 'POST reviews',
        proven: true,
        evidence: t,
      ));
    }
    if (t['tag'] == 'update_stars' &&
        t['http'] == 200 &&
        t['new'] == 1 &&
        t['old'] != 1) {
      c.addFinding(finding(
        id: '$prefix-J2-STARS-MUTATE',
        lens: 'J2',
        severity: 'P1',
        title: 'UPDATE stars/comment de review persistiu',
        pre: 'JWT buyer dono',
        repro: 'PATCH reviews stars=1',
        proven: true,
        evidence: t,
      ));
    }
  }

  // =====================================================================
  // J5 — notifications / push
  // =====================================================================
  final j5 = <String, Object?>{};
  for (final t in [
    'notifications',
    'user_notifications',
    'in_app_notifications',
    'push_tokens',
    'user_push_tokens',
    'device_tokens',
    'fcm_tokens',
    'seller_device_tokens',
    'notifications_view',
  ]) {
    final g = await c.rest('GET', '$t?select=*&limit=5', jwt: c.buyer2Jwt);
    j5['GET_$t'] = {'http': g.status, 'n': g.list.length, 'body': g.snippet};
    if (g.ok && g.list.isNotEmpty && t != 'notifications_view') {
      final alien = g.list.where((e) {
        if (e is! Map) return false;
        final uid = (e['user_id'] ?? e['buyer_id'] ?? e['seller_id'] ?? e['owner_id'])
            ?.toString();
        return uid != null && uid.isNotEmpty && uid != c.buyer2Id;
      }).toList();
      if (alien.isNotEmpty) {
        c.addFinding(finding(
          id: '$prefix-J5-READ-$t',
          lens: 'J5',
          severity: t.contains('token') ? 'P1' : 'P2',
          title: 'buyer2 lê $t alheio',
          pre: 'GET $t',
          repro: 'GET /rest/v1/$t',
          proven: true,
          evidence: {'n': alien.length, 'sample': clip(alien.first)},
        ));
      }
    }
    final ins = await c.rest('POST', t, jwt: c.buyer2Jwt, body: {
      'user_id': c.sellerId,
      'buyer_id': c.sellerId,
      'seller_id': c.sellerId,
      'title': '$prefix forge',
      'body': 'pwn',
      'message': 'pwn',
      'token': 'rtj-fake-token',
    });
    j5['POST_$t'] = {'http': ins.status, 'body': ins.snippet};
    if (ins.status == 201) {
      c.addFinding(finding(
        id: '$prefix-J5-INSERT-$t',
        lens: 'J5',
        severity: 'P1',
        title: 'INSERT $t forjado (user_id alheio ou token)',
        pre: 'JWT buyer2',
        repro: 'POST $t',
        proven: true,
        evidence: {'id': ins.firstId, 'body': ins.snippet},
      ));
    }
  }
  c.note('j5', j5);

  // =====================================================================
  // J6 — favorites / follows
  // =====================================================================
  final products = await c.rest(
    'GET',
    'products?seller_id=eq.${c.sellerId}&list_on_marketplace=eq.true&is_sold=eq.false&select=id,title,price,quantity,list_on_marketplace&limit=3',
    service: true,
  );
  final pid = products.firstId;
  c.note('j6.product', {'http': products.status, 'id': pid, 'n': products.list.length});

  if (pid != null) {
    final fav = await c.rest('POST', 'favorites', jwt: c.buyer2Jwt, body: {
      'user_id': c.buyer2Id,
      'product_id': pid,
    });
    c.note('j6.fav_insert', {'http': fav.status, 'id': fav.firstId, 'body': fav.snippet});

    final favHijack = await c.rest('POST', 'favorites', jwt: c.buyer2Jwt, body: {
      'user_id': c.buyerId,
      'product_id': pid,
    });
    c.note('j6.fav_hijack',
        {'http': favHijack.status, 'id': favHijack.firstId, 'body': favHijack.snippet});
    if (favHijack.status == 201) {
      c.addFinding(finding(
        id: '$prefix-J6-FAV-HIJACK',
        lens: 'J6',
        severity: 'P1',
        title: 'buyer2 INSERT favorite como buyer1',
        pre: 'user_id ≠ auth.uid()',
        repro: 'POST favorites',
        proven: true,
        evidence: {'id': favHijack.firstId},
      ));
    }

    await c.rest('PATCH', 'products?id=eq.$pid', service: true, body: {
      'list_on_marketplace': false,
    }, prefer: 'return=minimal');

    final favAfter = await c.rest(
      'GET',
      'favorites?product_id=eq.$pid&select=id,user_id,product_id',
      jwt: c.buyer2Jwt,
    );
    final prodAfter = await c.rest(
      'GET',
      'products?id=eq.$pid&select=id,title,price,list_on_marketplace,is_sold',
      jwt: c.buyer2Jwt,
    );
    c.note('j6.after_unlist', {
      'fav_http': favAfter.status,
      'fav_n': favAfter.list.length,
      'prod_http': prodAfter.status,
      'prod_n': prodAfter.list.length,
      'prod': prodAfter.map,
    });
    // restore listing so we don't leave lab product unlisted
    await c.rest('PATCH', 'products?id=eq.$pid', service: true, body: {
      'list_on_marketplace': true,
    }, prefer: 'return=minimal');

    if (prodAfter.ok && prodAfter.list.isNotEmpty) {
      c.addFinding(finding(
        id: '$prefix-J6-FAV-UNLIST-READ',
        lens: 'J6',
        severity: 'P2',
        title: 'Após unlist, JWT buyer2 ainda lê o produto via RLS (favorito ou shadow)',
        pre: 'favorite + list_on_marketplace=false',
        repro: 'GET products?id=eq (JWT) após unlist',
        proven: true,
        evidence: {
          'fav_n': favAfter.list.length,
          'prod': prodAfter.map,
        },
        note: 'Não re-provar checkout unlist (anti-atrofia). Só leitura.',
      ));
    }
  }

  final folHijack = await c.rest('POST', 'follows', jwt: c.buyer2Jwt, body: {
    'follower_id': c.buyerId,
    'following_id': c.sellerId,
  });
  c.note('j6.follow_hijack',
      {'http': folHijack.status, 'body': folHijack.snippet});
  if (folHijack.status == 201) {
    c.addFinding(finding(
      id: '$prefix-J6-FOLLOW-HIJACK',
      lens: 'J6',
      severity: 'P1',
      title: 'buyer2 INSERT follow como buyer1',
      pre: 'follower_id ≠ auth.uid()',
      repro: 'POST follows',
      proven: true,
      evidence: {'id': folHijack.firstId},
    ));
  }
  final folSelf = await c.rest('POST', 'follows', jwt: c.buyer2Jwt, body: {
    'follower_id': c.buyer2Id,
    'following_id': c.sellerId,
  });
  c.note('j6.follow_ok', {'http': folSelf.status, 'id': folSelf.firstId});
  final folEnum = await c.rest(
    'GET',
    'follows?select=follower_id,following_id&limit=20',
    jwt: c.buyer2Jwt,
  );
  final folAlien = folEnum.list.where((e) {
    if (e is! Map) return false;
    return e['follower_id'] != c.buyer2Id && e['following_id'] != c.buyer2Id;
  }).toList();
  c.note('j6.follow_enum',
      {'http': folEnum.status, 'n': folEnum.list.length, 'alien': folAlien.length});
  if (folAlien.isNotEmpty) {
    c.addFinding(finding(
      id: '$prefix-J6-FOLLOW-ENUM',
      lens: 'J6',
      severity: 'P2',
      title: 'buyer2 enumera follows alheios',
      pre: 'GET follows',
      repro: 'GET follows JWT buyer2',
      proven: true,
      evidence: {'n': folAlien.length},
    ));
  }

  // =====================================================================
  // J4 — handle / deep link / resolve
  // =====================================================================
  final sellerProf = await c.rest(
    'GET',
    'profiles?id=eq.${c.sellerId}&select=id,handle,hub_published,full_name',
    service: true,
  );
  final sellerHandle = sellerProf.map?['handle']?.toString();
  c.note('j4.seller_handle', sellerHandle);

  final patchHandle = await c.rest(
    'PATCH',
    'profiles?id=eq.${c.buyer2Id}',
    jwt: c.buyer2Jwt,
    body: {'handle': sellerHandle, 'hub_published': true},
  );
  c.note('j4.patch_handle', {
    'http': patchHandle.status,
    'body': patchHandle.snippet,
    'stored': patchHandle.map,
  });
  if (patchHandle.ok && patchHandle.map?['handle'] == sellerHandle) {
    c.addFinding(finding(
      id: '$prefix-J4-HANDLE-STEAL-PATCH',
      lens: 'J4',
      severity: 'P0',
      title: 'PATCH profiles.handle roubou handle do seller',
      pre: 'JWT buyer2',
      repro: 'PATCH profiles handle=seller',
      proven: true,
      evidence: patchHandle.map,
    ));
  }

  final claim = await c.rpc('batata_claim_handle', {'p_handle': sellerHandle ?? 'x'},
      jwt: c.buyer2Jwt);
  c.note('j4.claim_handle', {'http': claim.status, 'body': claim.snippet});
  if (claim.ok && (claim.map?['ok'] == true)) {
    c.addFinding(finding(
      id: '$prefix-J4-HANDLE-CLAIM',
      lens: 'J4',
      severity: 'P0',
      title: 'RPC claim_handle apoderou-se do handle do seller',
      pre: 'JWT buyer2, handle ocupado',
      repro: 'rpc batata_claim_handle',
      proven: true,
      evidence: claim.map,
    ));
  }

  final change = await c.rpc(
      'batata_change_handle', {'p_new_handle': sellerHandle ?? 'x'},
      jwt: c.buyer2Jwt);
  c.note('j4.change_handle', {'http': change.status, 'body': change.snippet});

  final resolveAnon = await c.rpc(
      'batata_resolve_handle', {'p_handle': sellerHandle ?? 'x'});
  c.note('j4.resolve_anon', {
    'http': resolveAnon.status,
    'body': clip(resolveAnon.body, 500),
  });

  // publish hub as buyer2 for seller? 
  final pub = await c.rpc('batata_publish_hub', {}, jwt: c.buyer2Jwt);
  c.note('j4.publish_hub_b2', {'http': pub.status, 'body': pub.snippet});

  // stripe settle with victim session as buyer2
  if (csVictim.isNotEmpty) {
    final settle = await c.req(
      'GET',
      '/functions/v1/create-payment-intent?checkout_return=success&session_id=$csVictim',
      jwt: c.buyer2Jwt,
    );
    c.note('j4.settle_stolen_cs', {
      'http': settle.status,
      'body': clip(settle.body, 400),
      'cs_prefix': csVictim.length > 12 ? csVictim.substring(0, 12) : csVictim,
    });
  }

  final refundB2 = await c.edge('refund-order', {
    'order_id': oidPaid ?? oidDone ?? '00000000-0000-0000-0000-000000000001',
  }, jwt: c.buyer2Jwt);
  c.note('j7.refund_b2', {'http': refundB2.status, 'body': refundB2.snippet});
  if (refundB2.status == 200 && (refundB2.map?['ok'] == true)) {
    c.addFinding(finding(
      id: '$prefix-J7-REFUND-STRANGER',
      lens: 'J7',
      severity: 'P0',
      title: 'buyer2 refund-order em encomenda alheia',
      pre: 'Edge refund-order JWT buyer2',
      repro: 'POST refund-order order_id vítima',
      proven: true,
      evidence: refundB2.map,
    ));
  }

  // =====================================================================
  // live_messages
  // =====================================================================
  final lives = await c.rest(
    'GET',
    'lives?select=id,status,is_active,seller_id&order=created_at.desc&limit=5',
    service: true,
  );
  final liveId = lives.firstId;
  final liveEnded = lives.list.cast<dynamic>().where((e) {
    if (e is! Map) return false;
    return (e['status']?.toString() ?? '').toLowerCase() == 'ended' ||
        e['is_active'] == false;
  });
  final endedId = liveEnded.isNotEmpty
      ? (liveEnded.first as Map)['id']?.toString()
      : null;
  if (liveId != null) {
    final lmChat = await c.rest('POST', 'live_messages', jwt: c.buyer2Jwt, body: {
      'live_id': liveId,
      'user_id': c.buyer2Id,
      'kind': 'chat',
      'body': '$prefix hello',
    });
    final lmTip = await c.rest('POST', 'live_messages', jwt: c.buyer2Jwt, body: {
      'live_id': liveId,
      'user_id': c.buyer2Id,
      'kind': 'tip',
      'body': 'Recebeu uma gorjeta',
      'tip_amount': 50,
    });
    c.note('j1.live_msg', {
      'live': liveId,
      'chat': {'http': lmChat.status, 'body': lmChat.snippet},
      'tip': {'http': lmTip.status, 'id': lmTip.firstId, 'body': lmTip.snippet},
    });
    if (lmTip.status == 201) {
      c.addFinding(finding(
        id: '$prefix-J1-LIVE-TIP-FORGE',
        lens: 'J1',
        severity: 'P1',
        title: 'INSERT live_messages kind=tip forjado',
        pre: 'JWT buyer2',
        repro: 'POST live_messages kind=tip',
        proven: true,
        evidence: {'id': lmTip.firstId, 'live': liveId},
      ));
    }
  }
  if (endedId != null) {
    final lmEnded = await c.rest('POST', 'live_messages', jwt: c.buyer2Jwt, body: {
      'live_id': endedId,
      'user_id': c.buyer2Id,
      'kind': 'chat',
      'body': '$prefix on ended',
    });
    final lmRead = await c.rest(
      'GET',
      'live_messages?live_id=eq.$endedId&select=id,kind,body,user_id,sender_label&limit=8',
      jwt: c.buyer2Jwt,
    );
    c.note('j1.live_ended', {
      'insert': {'http': lmEnded.status, 'body': lmEnded.snippet},
      'read': {
        'http': lmRead.status,
        'n': lmRead.list.length,
        'sample': clip(lmRead.body, 400),
      },
    });
  }

  await dumpJson(
    '${Directory.current.path.contains('redteam_blind_j_') ? Directory.current.path : '${repoRoot()}/tool/redteam_blind_j_$stamp'}/out/pass1.json',
    {
      'prefix': prefix,
      'notes': c.notes,
      'findings': c.findings,
    },
  );
  stdout.writeln('pass1 findings=${c.findings.length}');
  for (final f in c.findings) {
    stdout.writeln('  ${f['severity']} ${f['id']} ${f['title']}');
  }
}
